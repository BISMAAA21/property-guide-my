import 'dart:typed_data';

import 'damage_detection_result.dart';

sealed class DamagePhotoSource {
  const DamagePhotoSource();
}

final class UploadedDamagePhoto extends DamagePhotoSource {
  const UploadedDamagePhoto({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });

  final Uint8List bytes;
  final String filename;
  final String contentType;
}

final class InspectionDamagePhoto extends DamagePhotoSource {
  const InspectionDamagePhoto({
    required this.inspectionId,
    required this.checkId,
    required this.imagePath,
  });

  final String inspectionId;
  final String checkId;
  final String imagePath;
}

abstract interface class DamageDetectionRepository {
  Stream<List<DamageReport>> watchReports(String propertyId);

  Future<DamageReport> detectDamage({
    required String propertyId,
    required DamagePhotoSource source,
  });
}
