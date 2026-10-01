import 'dart:typed_data';

import 'property_inspection.dart';

class ConcernPhotoInput {
  const ConcernPhotoInput({
    required this.byteLength,
    required this.contentType,
  });

  static const maxBytes = 10 * 1024 * 1024;

  final int byteLength;
  final String contentType;

  String? validate() {
    if (byteLength <= 0 || byteLength > maxBytes) {
      return 'Choose a concern photo smaller than 10 MiB.';
    }
    if (!const {
      'image/jpeg',
      'image/png',
      'image/webp',
    }.contains(contentType)) {
      return 'Choose a JPEG, PNG, or WebP concern photo.';
    }
    return null;
  }
}

abstract interface class InspectionRepository {
  Stream<PropertyInspection?> watchPropertyInspection(String propertyId);

  Stream<PropertyInspection?> watchInspection(String inspectionId);

  Future<String> startOrResume({
    required String propertyId,
    required String propertyName,
  });

  Future<void> saveFinding({
    required String inspectionId,
    required InspectionFinding finding,
  });

  Future<String> uploadConcernPhoto({
    required String inspectionId,
    required String checkId,
    required Uint8List bytes,
    required String filename,
    required String contentType,
  });

  Future<void> completeInspection(String inspectionId);
}
