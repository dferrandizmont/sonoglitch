package io.github.dferrandizmont.sonoglitch

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    /** The channel of the light sensor of the phone. */
    private var ambientLightChannel: EventChannel? = null
    private var spectrumChannel: EventChannel? = null
    private var encoderChannel: MethodChannel? = null
    private var volumeKeysChannel: MethodChannel? = null
    private var volumeKeysEnabled = false
    private val capturedVolumeKeys = mutableSetOf<Int>()
    private val spectrum = SpectrumPlugin()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        volumeKeysChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "sonoglitch/volume_keys",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "setEnabled") {
                    volumeKeysEnabled = call.arguments == true
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        }
        spectrumChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "sonoglitch/spectrum",
        ).also { it.setStreamHandler(spectrum) }
        // The light sensor needs no permission, so it is simply plugged in.
        ambientLightChannel =
            EventChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "sonoglitch/ambient_light",
            ).also { channel ->
                channel.setStreamHandler(AmbientLightPlugin(applicationContext))
            }
        // The encoder of the JPEG of the exports.
        encoderChannel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "sonoglitch/encoder",
            ).also { it.setMethodCallHandler(ImageEncoderPlugin()) }
    }

    override fun onPause() {
        volumeKeysEnabled = false
        capturedVolumeKeys.clear()
        spectrum.pause()
        super.onPause()
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (isVolumeKey(keyCode)) {
            // Finish an intercepted hold even if Dart disables capture after
            // the first down: repeats must not start changing system volume.
            if (keyCode in capturedVolumeKeys) return true
            if (volumeKeysEnabled) {
                capturedVolumeKeys.add(keyCode)
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                    volumeKeysChannel?.invokeMethod("press", null)
                }
                return true
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        if (isVolumeKey(keyCode)) {
            val captured = capturedVolumeKeys.remove(keyCode)
            if (captured || volumeKeysEnabled) return true
        }
        return super.onKeyUp(keyCode, event)
    }

    private fun isVolumeKey(keyCode: Int) =
        keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_UP

    override fun onResume() {
        super.onResume()
        spectrum.resume()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        volumeKeysEnabled = false
        capturedVolumeKeys.clear()
        volumeKeysChannel?.setMethodCallHandler(null)
        volumeKeysChannel = null
        spectrum.dispose()
        spectrumChannel?.setStreamHandler(null)
        spectrumChannel = null
        encoderChannel?.setMethodCallHandler(null)
        encoderChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
