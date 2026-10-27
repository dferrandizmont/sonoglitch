import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/camera/exif.dart';

/// Builds a small JPEG with an EXIF orientation tag.
Uint8List jpegWithOrientation(int orientation) {
  final bytes = <int>[
    0xFF, 0xD8, // start of image
    0xFF, 0xE1, 0x00, 0x22, // APP1, length 34
    0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
    0x49, 0x49, 0x2A, 0x00, // little endian, 42
    0x08, 0x00, 0x00, 0x00, // the first IFD is at 8
    0x01, 0x00, // one entry
    0x12, 0x01, // the orientation tag
    0x03, 0x00, // a short
    0x01, 0x00, 0x00, 0x00, // one value
    orientation & 0xFF, (orientation >> 8) & 0xFF, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, // no next IFD
    0xFF, 0xD9, // end of image
  ];
  return Uint8List.fromList(bytes);
}

void main() {
  group('the EXIF orientation', () {
    test('is read from the picture', () {
      expect(readExifOrientation(jpegWithOrientation(1)), 1);
      expect(readExifOrientation(jpegWithOrientation(6)), 6);
      expect(readExifOrientation(jpegWithOrientation(8)), 8);
    });

    test('a picture without EXIF has no orientation', () {
      final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);
      expect(readExifOrientation(bytes), isNull);
    });

    test('something that is not a picture has no orientation', () {
      expect(readExifOrientation(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });

    test('an empty picture has no orientation', () {
      expect(readExifOrientation(Uint8List(0)), isNull);
    });
  });

  group('the rotation of the orientation', () {
    test('the normal one does not turn', () {
      final orientation = ExifOrientation.fromValue(1);
      expect(orientation?.rotationDegrees, 0);
      expect(orientation?.mirrored, isFalse);
    });

    test('the turned ones', () {
      expect(ExifOrientation.fromValue(3)?.rotationDegrees, 180);
      expect(ExifOrientation.fromValue(6)?.rotationDegrees, 90);
      expect(ExifOrientation.fromValue(8)?.rotationDegrees, 270);
    });

    test('the mirrored ones', () {
      expect(ExifOrientation.fromValue(2)?.mirrored, isTrue);
      expect(ExifOrientation.fromValue(4)?.mirrored, isTrue);
      expect(ExifOrientation.fromValue(5)?.mirrored, isTrue);
      expect(ExifOrientation.fromValue(7)?.mirrored, isTrue);
    });

    test('values 5 and 7 are the transpose and the transverse', () {
      // EXIF 5 = "mirror horizontal and rotate 270° CW" = transpose.
      final five = ExifOrientation.fromValue(5);
      expect(five, isNotNull);
      expect(five!.rotationDegrees, 270);
      expect(five.mirrored, isTrue);

      // EXIF 7 = "mirror horizontal and rotate 90° CW" = transverse.
      final seven = ExifOrientation.fromValue(7);
      expect(seven, isNotNull);
      expect(seven!.rotationDegrees, 90);
      expect(seven.mirrored, isTrue);
    });

    test('an unknown value has no orientation', () {
      expect(ExifOrientation.fromValue(42), isNull);
    });
  });
}
