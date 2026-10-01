import '../domain/damage_detection_failure.dart';
import '../domain/damage_detection_repository.dart';
import '../domain/damage_detection_result.dart';

class UnavailableDamageDetectionRepository
    implements DamageDetectionRepository {
  const UnavailableDamageDetectionRepository();

  DamageDetectionFailure get _failure => const DamageDetectionFailure(
    'firebase-not-configured',
    'Connect Firebase before using damage detection.',
  );

  @override
  Future<DamageReport> detectDamage({
    required String propertyId,
    required DamagePhotoSource source,
  }) async => throw _failure;

  @override
  Stream<List<DamageReport>> watchReports(String propertyId) =>
      Stream.error(_failure);
}
