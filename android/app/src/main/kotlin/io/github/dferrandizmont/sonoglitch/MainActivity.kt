package io.github.dferrandizmont.sonoglitch

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    /** The channel of the light sensor of the phone. */
    private var ambientLightChannel: EventChannel? = null
    private var spectrumChannel: EventChannel? = null
    private var encoderChannel: MethodChannel? = null
    private val spectrum = SpectrumPlugin()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
        spectrum.pause()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        spectrum.resume()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        spectrum.dispose()
        spectrumChannel?.setStreamHandler(null)
        spectrumChannel = null
        encoderChannel?.setMethodCallHandler(null)
        encoderChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
