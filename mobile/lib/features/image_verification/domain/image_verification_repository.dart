import 'dart:typed_data';

import 'image_verification_result.dart';

abstract interface class ImageVerificationRepository {
  Stream<List<VerificationReport>> watchReports(String propertyId);

  Future<VerificationReport> verifyVisitImage({
    required String propertyId,
    required Uint8List bytes,
    required String filename,
    required String contentType,
  });
}
