package io.github.dferrandizmont.sonoglitch

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import kotlin.concurrent.thread

/**
 * Encodes the lossless PNG of the app as a JPEG.
 *
 * The PNG is written by the app in the cache of the app and only its path
 * crosses the platform channel: a picture of 50 megapixels is a copy, a
 * pause and a risk of a `TransactionTooLargeException` if it travels as
 * bytes.
 *
 * The encoding runs on a background thread, because decoding a picture of
 * 24 megapixels and compressing it takes seconds and the platform thread
 * belongs to the interface.
 */
class ImageEncoderPlugin : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "encodeJpeg" -> encodeJpeg(call, result)
            else -> result.notImplemented()
        }
    }

    private fun encodeJpeg(call: MethodCall, result: MethodChannel.Result) {
        val inputPath = call.argument<String>("inputPath")
        val outputPath = call.argument<String>("outputPath")
        if (inputPath.isNullOrEmpty() || outputPath.isNullOrEmpty()) {
            result.error(
                "invalid_arguments",
                "The input and the output paths are needed",
                null,
            )
            return
        }
        thread(name = "sonoglitch-encoder") {
            val outcome = runCatching { encode(inputPath, outputPath) }
            // The result has to be delivered on the platform thread.
            Handler(Looper.getMainLooper()).post {
                outcome
                    .onSuccess { result.success(it) }
                    .onFailure {
                        result.error(
                            "encode_failed",
                            // The message never carries a path: the logs of
                            // the app are shared with the user.
                            "The picture could not be encoded as a JPEG",
                            null,
                        )
                    }
            }
        }
    }

    /**
     * Decodes the PNG and writes the JPEG, and removes the PNG.
     *
     * The PNG is only removed when the JPEG is written: when the encoding
     * fails, the PNG is the picture of the export.
     */
    private fun encode(inputPath: String, outputPath: String): String {
        val bitmap = BitmapFactory.decodeFile(inputPath)
            ?: throw IllegalStateException("The PNG could not be decoded")
        var completed = false
        try {
            FileOutputStream(outputPath).use { stream ->
                // The chroma of the JPEG is 4:2:0: `Bitmap.compress` cannot
                // write 4:4:4, which would need a real encoder (libjpeg-turbo)
                // that the app does not carry yet. The quality of 95 keeps
                // the detail of the picture as far as the chroma allows.
                val written = bitmap.compress(
                    Bitmap.CompressFormat.JPEG,
                    JPEG_QUALITY,
                    stream,
                )
                if (!written) {
                    throw IllegalStateException("The JPEG could not be written")
                }
            }
            // Mark success only after use has also closed the output stream.
            completed = true
        } finally {
            bitmap.recycle()
            if (!completed) File(outputPath).delete()
        }
        File(inputPath).delete()
        return outputPath
    }

    companion object {
        /** The quality of the JPEG. */
        private const val JPEG_QUALITY = 95
    }
}
