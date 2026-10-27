package io.github.dferrandizmont.sonoglitch

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.plugin.common.EventChannel

/**
 * Streams the ambient light of the place, in lux, from the light sensor of
 * the phone.
 *
 * The sensor is only read while the Dart side is listening, so the panel
 * does not drain the battery while the viewfinder is hidden. Devices
 * without a light sensor end the stream with an `unavailable` error instead
 * of crashing: the app then falls back to the brightness of the picture.
 */
class AmbientLightPlugin(context: Context) :
    EventChannel.StreamHandler,
    SensorEventListener {

    private val sensorManager: SensorManager =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager

    private val lightSensor: Sensor? =
        sensorManager.getDefaultSensor(Sensor.TYPE_LIGHT)

    private var sink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        val sensor = lightSensor
        if (sensor == null) {
            events?.error(
                "unavailable",
                "This device has no ambient light sensor",
                null,
            )
            return
        }
        sink = events
        sensorManager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_UI)
    }

    override fun onCancel(arguments: Any?) {
        sensorManager.unregisterListener(this)
        sink = null
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // The accuracy of the light sensor does not change its reading.
    }

    override fun onSensorChanged(event: SensorEvent?) {
        val lux = event?.values?.firstOrNull() ?: return
        sink?.success(lux.toDouble())
    }
}
