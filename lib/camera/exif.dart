import 'dart:typed_data';

/// The orientation stored in the EXIF header of a picture.
///
/// Only the rotation and the mirroring are kept: the values of the EXIF
/// orientation tag map directly to them.
class ExifOrientation {
  const ExifOrientation(this.rotationDegrees, this.mirrored);

  /// Clockwise rotation, in degrees, needed to display the picture upright.
  final int rotationDegrees;

  /// Whether the picture also has to be flipped horizontally.
  final bool mirrored;

  /// Reads the orientation from the raw EXIF value.
  ///
  /// Returns null for the values the standard does not define.
  static ExifOrientation? fromValue(int value) {
    switch (value) {
      case 1:
        return const ExifOrientation(0, false);
      case 2:
        return const ExifOrientation(0, true);
      case 3:
        return const ExifOrientation(180, false);
      case 4:
        return const ExifOrientation(180, true);
      case 5:
        return const ExifOrientation(270, true);
      case 6:
        return const ExifOrientation(90, false);
      case 7:
        return const ExifOrientation(90, true);
      case 8:
        return const ExifOrientation(270, false);
      default:
        return null;
    }
  }
}

/// Reads the EXIF orientation of a JPEG file.
///
/// Returns null when the file has no EXIF block or no orientation tag, which
/// is the normal case for a picture that is already upright.
///
/// The parser only understands the small subset of the format that is needed
/// here: the APP1 segment with the `Exif` marker and the first IFD.
int? readExifOrientation(Uint8List bytes) {
  if (bytes.length < 4) return null;
  // Start of image marker.
  if (bytes[0] != 0xFF || bytes[1] != 0xD8) return null;

  var offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] != 0xFF) return null;
    final marker = bytes[offset + 1];
    // Markers without a payload.
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD8)) {
      offset += 2;
      continue;
    }
    // Start of scan: the metadata is over.
    if (marker == 0xDA || marker == 0xD9) return null;

    final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
    if (marker == 0xE1 && offset + 10 <= bytes.length) {
      final isExif =
          bytes[offset + 4] == 0x45 && // E
          bytes[offset + 5] == 0x78 && // x
          bytes[offset + 6] == 0x69 && // i
          bytes[offset + 7] == 0x66 && // f
          bytes[offset + 8] == 0x00 &&
          bytes[offset + 9] == 0x00;
      if (isExif) {
        return _readTiffOrientation(bytes, offset + 10);
      }
    }
    offset += 2 + length;
  }
  return null;
}

int? _readTiffOrientation(Uint8List bytes, int tiff) {
  if (tiff + 8 > bytes.length) return null;
  final littleEndian = bytes[tiff] == 0x49; // I
  if (!littleEndian && bytes[tiff] != 0x4D) return null; // M
  if (_u16(bytes, tiff + 2, littleEndian) != 42) return null;

  final ifd = tiff + _u32(bytes, tiff + 4, littleEndian);
  if (ifd + 2 > bytes.length) return null;
  final entries = _u16(bytes, ifd, littleEndian);

  for (var i = 0; i < entries; i++) {
    final entry = ifd + 2 + i * 12;
    if (entry + 12 > bytes.length) return null;
    if (_u16(bytes, entry, littleEndian) != 0x0112) continue; // Orientation
    final type = _u16(bytes, entry + 2, littleEndian);
    final count = _u32(bytes, entry + 4, littleEndian);
    if (count < 1) return null;
    // SHORT values are stored in the first two bytes of the value field.
    if (type == 3) return _u16(bytes, entry + 8, littleEndian);
    return _u32(bytes, entry + 8, littleEndian);
  }
  return null;
}

int _u16(Uint8List bytes, int offset, bool littleEndian) {
  if (offset + 2 > bytes.length) return 0;
  final high = bytes[offset];
  final low = bytes[offset + 1];
  return littleEndian ? (high | (low << 8)) : ((high << 8) | low);
}

int _u32(Uint8List bytes, int offset, bool littleEndian) {
  if (offset + 4 > bytes.length) return 0;
  if (littleEndian) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}
