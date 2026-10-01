import 'dart:typed_data';

import '../domain/inspection_failure.dart';
import '../domain/inspection_repository.dart';
import '../domain/property_inspection.dart';

class UnavailableInspectionRepository implements InspectionRepository {
  const UnavailableInspectionRepository();

  InspectionFailure get _failure => const InspectionFailure(
    'firebase-not-configured',
    'Connect the Firebase project before using guided inspection.',
  );

  @override
  Future<void> completeInspection(String inspectionId) async => throw _failure;

  @override
  Future<void> saveFinding({
    required String inspectionId,
    required InspectionFinding finding,
  }) async => throw _failure;

  @override
  Future<String> startOrResume({
    required String propertyId,
    required String propertyName,
  }) async => throw _failure;

  @override
  Future<String> uploadConcernPhoto({
    required String inspectionId,
    required String checkId,
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async => throw _failure;

  @override
  Stream<PropertyInspection?> watchInspection(String inspectionId) =>
      Stream.error(_failure);

  @override
  Stream<PropertyInspection?> watchPropertyInspection(String propertyId) =>
      Stream.error(_failure);
}
