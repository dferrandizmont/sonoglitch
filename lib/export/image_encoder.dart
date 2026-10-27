import 'dart:io';

import 'package:flutter/services.dart';

import '../debug/debug_log.dart';

/// Encodes the lossless PNG of the app as a JPEG.
///
/// The native plugin decodes the PNG and writes the JPEG on a background
/// thread, so the bytes of the picture never cross the platform channel:
/// only the paths do. A picture of 50 megapixels is a copy, a pause and a
/// risk of a `TransactionTooLargeException` if it travels as bytes.
class ImageEncoder {
  ImageEncoder({required this.log, MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// The name of the channel of the native encoder.
  static const String channelName = 'sonoglitch/encoder';

  /// The method that encodes a PNG as a JPEG.
  static const String encodeMethod = 'encodeJpeg';

  /// The quality of the JPEG.
  ///
  /// The native encoder writes 4:2:0 chroma: 4:4:4 needs a real encoder
  /// (libjpeg-turbo), which the app does not carry yet.
  static const int jpegQuality = 95;

  /// Where the problems are reported.
  final DebugLog log;

  final MethodChannel _channel;

  /// Encodes [png] as a JPEG in [output].
  ///
  /// The PNG is deleted when the JPEG is written. When the encoder fails,
  /// the PNG is kept and returned instead: the picture is never lost
  /// because of an encoder.
  Future<File> encode(File png, File output) async {
    try {
      final path = await _channel.invokeMethod<String>(encodeMethod, {
        'inputPath': png.path,
        'outputPath': output.path,
      });
      if (path == null || path.isEmpty) {
        throw StateError('The encoder returned no path');
      }
      final encoded = File(path);
      if (!encoded.existsSync()) {
        throw StateError('The encoder wrote no file');
      }
      // The intermediate PNG is not needed any more.
      _delete(png);
      log.info('export', 'the picture was encoded as a JPEG');
      return encoded;
    } catch (error, stackTrace) {
      _delete(output);
      log.error(
        'export',
        'the picture could not be encoded as a JPEG, the PNG is kept',
        error,
        stackTrace,
      );
      return png;
    }
  }

  /// Removes a file that is not needed any more.
  void _delete(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (error) {
      log.warning('export', 'the temporary image could not be deleted: $error');
    }
  }
}
