import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:property_guidance/shared/validation/image_content.dart';

void main() {
  group('image content validation', () {
    test('detects supported image signatures', () {
      expect(
        detectSupportedImageContentType(
          Uint8List.fromList([0xff, 0xd8, 0xff, 0x00]),
        ),
        'image/jpeg',
      );
      expect(
        detectSupportedImageContentType(
          Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
        ),
        'image/png',
      );
      expect(
        detectSupportedImageContentType(
          Uint8List.fromList([
            0x52,
            0x49,
            0x46,
            0x46,
            0,
            0,
            0,
            0,
            0x57,
            0x45,
            0x42,
            0x50,
          ]),
        ),
        'image/webp',
      );
    });

    test('normalizes parameters and rejects a mismatched signature', () {
      final png = Uint8List.fromList([
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]);

      expect(
        normalizeImageContentType(' IMAGE/PNG; charset=binary '),
        'image/png',
      );
      expect(imageContentMatchesType(png, 'IMAGE/PNG; charset=binary'), isTrue);
      expect(imageContentMatchesType(png, 'image/jpeg'), isFalse);
      expect(
        detectSupportedImageContentType(Uint8List.fromList([1, 2, 3])),
        isNull,
      );
    });
  });
}
