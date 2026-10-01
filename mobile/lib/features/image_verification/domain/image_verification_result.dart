enum SimilarityLevel {
  high,
  moderate,
  low;

  static SimilarityLevel? fromStoredValue(Object? value) =>
      values.where((level) => level.name == value).firstOrNull;

  String get displayName => switch (this) {
    SimilarityLevel.high => 'High similarity',
    SimilarityLevel.moderate => 'Moderate similarity',
    SimilarityLevel.low => 'Low similarity',
  };
}

class ImageVerificationResult {
  const ImageVerificationResult({
    required this.similarityScore,
    required this.similarityLevel,
    required this.possibleMismatch,
    required this.bestListingImageIndex,
    required this.guidance,
    required this.disclaimer,
    required this.modelId,
    this.mismatchWarning,
  });

  factory ImageVerificationResult.fromJson(
    Map<String, dynamic> json, {
    required int listingImageCount,
  }) {
    final score = json['similarityScore'];
    final level = SimilarityLevel.fromStoredValue(json['similarityLevel']);
    final mismatch = json['possibleMismatch'];
    final warning = json['mismatchWarning'];
    final index = json['bestListingImageIndex'];
    final guidance = json['guidance'];
    final disclaimer = json['disclaimer'];
    final modelId = json['modelId'];
    if (score is! num ||
        !score.isFinite ||
        score < 0 ||
        score > 100 ||
        level == null ||
        mismatch is! bool ||
        (warning != null && warning is! String) ||
        index is! int ||
        index < 0 ||
        index >= listingImageCount ||
        guidance is! String ||
        guidance.trim().isEmpty ||
        disclaimer is! String ||
        disclaimer.trim().isEmpty ||
        modelId is! String ||
        modelId.trim().isEmpty ||
        (level == SimilarityLevel.low) != mismatch ||
        (mismatch && (warning is! String || warning.trim().isEmpty))) {
      throw const FormatException('Invalid image-verification response.');
    }
    return ImageVerificationResult(
      similarityScore: score.toDouble(),
      similarityLevel: level,
      possibleMismatch: mismatch,
      mismatchWarning: warning as String?,
      bestListingImageIndex: index,
      guidance: guidance.trim(),
      disclaimer: disclaimer.trim(),
      modelId: modelId.trim(),
    );
  }

  final double similarityScore;
  final SimilarityLevel similarityLevel;
  final bool possibleMismatch;
  final String? mismatchWarning;
  final int bestListingImageIndex;
  final String guidance;
  final String disclaimer;
  final String modelId;
}

class VerificationReport {
  const VerificationReport({
    required this.id,
    required this.studentId,
    required this.propertyId,
    required this.propertyName,
    required this.visitImagePath,
    required this.bestListingImageUrl,
    required this.result,
    required this.createdAt,
  });

  final String id;
  final String studentId;
  final String propertyId;
  final String propertyName;
  final String visitImagePath;
  final String bestListingImageUrl;
  final ImageVerificationResult result;
  final DateTime? createdAt;
}

class VerificationImageInput {
  const VerificationImageInput({
    required this.byteLength,
    required this.contentType,
  });

  static const maxBytes = 10 * 1024 * 1024;

  final int byteLength;
  final String contentType;

  String? validate() {
    if (byteLength <= 0 || byteLength > maxBytes) {
      return 'Choose a visit photo smaller than 10 MiB.';
    }
    if (!const {
      'image/jpeg',
      'image/png',
      'image/webp',
    }.contains(contentType)) {
      return 'Choose a JPEG, PNG, or WebP visit photo.';
    }
    return null;
  }
}
