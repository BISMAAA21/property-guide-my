import 'dart:typed_data';

import '../domain/image_verification_failure.dart';
import '../domain/image_verification_repository.dart';
import '../domain/image_verification_result.dart';

class UnavailableImageVerificationRepository
    implements ImageVerificationRepository {
  const UnavailableImageVerificationRepository();

  ImageVerificationFailure get _failure => const ImageVerificationFailure(
    'firebase-not-configured',
    'Connect Firebase before using image verification.',
  );

  @override
  Future<VerificationReport> verifyVisitImage({
    required String propertyId,
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async => throw _failure;

  @override
  Stream<List<VerificationReport>> watchReports(String propertyId) =>
      Stream.error(_failure);
}
