package io.github.dferrandizmont.sonoglitch

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Build
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.Executors
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.sin

/** PCM is overwritten in native memory; only three dBFS numbers leave this class. */
class SpectrumPlugin : EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    // Recorder and reader ownership stays on this one control thread.
    private val control = Executors.newSingleThreadExecutor { task ->
        Thread(task, "sonoglitch-spectrum-control")
    }
    private var worker: Thread? = null
    private var recorder: AudioRecord? = null
    private var paused = false
    private var disposed = false
    // Only main changes the generation; both background threads read it.
    @Volatile private var generation = 0

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (disposed) return
        stop()
        sink = events
        if (!paused) start()
    }

    override fun onCancel(arguments: Any?) {
        if (disposed) return
        sink = null
        stop()
    }

    fun pause() {
        if (disposed) return
        paused = true
        stop()
    }

    fun resume() {
        if (disposed || !paused) return
        paused = false
        if (sink != null) start()
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        sink = null
        stop()
        // Drain the final stop before the control thread exits. Never wait on main.
        control.shutdown()
    }

    private fun start() {
        val current = ++generation
        control.execute {
            if (!stopInput()) {
                main.post { fail(current) }
                return@execute
            }
            if (current != generation) return@execute
            try {
                val minimum = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT)
                check(minimum > 0)
                val opened = AudioRecord(MediaRecorder.AudioSource.MIC, RATE,
                    AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
                    max(minimum, FRAME * 4))
                recorder = opened
                check(opened.state == AudioRecord.STATE_INITIALIZED)
                if (current != generation) {
                    stopInput()
                    return@execute
                }
                opened.startRecording()
                check(opened.recordingState == AudioRecord.RECORDSTATE_RECORDING)
                if (current != generation) {
                    stopInput()
                    return@execute
                }
                worker = Thread({ read(opened, current) }, "sonoglitch-spectrum")
                worker!!.start()
            } catch (_: Exception) {
                stopInput()
                main.post { fail(current) }
            }
        }
    }

    private fun stop() {
        // Invalidate reads and already-posted events immediately on main.
        // All potentially blocking native work runs behind earlier lifecycle work.
        generation++
        control.execute { stopInput() }
    }

    /** Control thread only: no later start can overtake this stop/join/release. */
    private fun stopInput(): Boolean {
        val input = recorder
        val reader = worker
        // stop() unblocks READ_BLOCKING. A failed native stop can still leave a
        // read stuck: keep waiting off-main rather than release an in-use input.
        try { input?.stop() } catch (_: RuntimeException) { }
        var interrupted = false
        while (reader?.isAlive == true) {
            try { reader.join() } catch (_: InterruptedException) { interrupted = true }
        }
        worker = null
        try {
            input?.release()
        } catch (_: RuntimeException) {
            // Fail closed: retain ownership and do not open another recorder
            // until a later serialized cleanup can release this one.
            if (interrupted) Thread.currentThread().interrupt()
            return false
        }
        recorder = null
        if (interrupted) Thread.currentThread().interrupt()
        return true
    }

    private fun fail(current: Int) {
        if (generation != current) return
        sink?.error("unavailable", "Microphone input is unavailable", null)
        sink?.endOfStream()
        sink = null
        stop()
    }

    private fun read(input: AudioRecord, current: Int) {
        val pcm = ShortArray(FRAME)
        val real = DoubleArray(FRAME)
        val imaginary = DoubleArray(FRAME)
        val window = DoubleArray(FRAME) { 0.5 * (1 - cos(2 * PI * it / (FRAME - 1))) }
        val windowPower = window.sumOf { it * it }
        var nextEvent = 0L
        try {
            while (current == generation) {
                var offset = 0
                while (current == generation && offset < FRAME) {
                    val count = input.read(pcm, offset, FRAME - offset, AudioRecord.READ_BLOCKING)
                    check(count > 0)
                    offset += count
                }
                if (current != generation) break
                if (Build.VERSION.SDK_INT >= 29) {
                    check(input.activeRecordingConfiguration?.isClientSilenced != true)
                }
                for (i in 0 until FRAME) {
                    real[i] = pcm[i] / 32768.0 * window[i]
                    imaginary[i] = 0.0
                }
                fft(real, imaginary)
                val now = android.os.SystemClock.elapsedRealtimeNanos()
                if (now >= nextEvent) {
                    nextEvent = if (nextEvent == 0L) now + 50_000_000L
                        else nextEvent + 50_000_000L
                    val powers = DoubleArray(3)
                    for (bin in 1..FRAME / 2) {
                        val frequency = bin.toDouble() * RATE / FRAME
                        val band = when {
                            frequency < 20 -> continue
                            frequency < 250 -> 0
                            frequency < 2000 -> 1
                            frequency < 8000 -> 2
                            else -> continue
                        }
                        // Parseval with Hann power correction, relative to PCM full scale.
                        powers[band] += 2 * (real[bin] * real[bin] +
                            imaginary[bin] * imaginary[bin]) / (FRAME * windowPower)
                    }
                    val bands = powers.map { 10 * log10(max(1e-12, it)) }
                    main.post {
                        if (current == generation) sink?.success(bands)
                    }
                }
            }
        } catch (_: Exception) {
            main.post { fail(current) }
        } finally {
            pcm.fill(0)
            real.fill(0.0)
            imaginary.fill(0.0)
        }
    }

    /** In-place radix-2 FFT, no library or audio buffer on the platform channel. */
    private fun fft(real: DoubleArray, imaginary: DoubleArray) {
        var j = 0
        for (i in 1 until FRAME) {
            var bit = FRAME shr 1
            while (j and bit != 0) { j = j xor bit; bit = bit shr 1 }
            j = j xor bit
            if (i < j) {
                val r = real[i]; real[i] = real[j]; real[j] = r
                val im = imaginary[i]; imaginary[i] = imaginary[j]; imaginary[j] = im
            }
        }
        var length = 2
        while (length <= FRAME) {
            val angle = -2 * PI / length
            for (start in 0 until FRAME step length) {
                for (k in 0 until length / 2) {
                    val a = start + k
                    val b = a + length / 2
                    val c = cos(angle * k)
                    val s = sin(angle * k)
                    val r = real[b] * c - imaginary[b] * s
                    val im = real[b] * s + imaginary[b] * c
                    real[b] = real[a] - r
                    imaginary[b] = imaginary[a] - im
                    real[a] += r
                    imaginary[a] += im
                }
            }
            length *= 2
        }
    }

    companion object {
        private const val RATE = 44100
        private const val FRAME = 1024
    }
}
