enum DamageClass {
  wallCrack('wall_crack'),
  waterOrDampStain('water_or_damp_stain'),
  mold('mold'),
  noVisibleDamage('no_visible_damage');

  const DamageClass(this.storedValue);

  final String storedValue;

  static DamageClass? fromStoredValue(Object? value) =>
      values.where((item) => item.storedValue == value).firstOrNull;

  String get displayName => switch (this) {
    DamageClass.wallCrack => 'Possible wall crack',
    DamageClass.waterOrDampStain => 'Possible water or damp stain',
    DamageClass.mold => 'Possible mold',
    DamageClass.noVisibleDamage => 'No supported visible damage',
  };

  bool get isPossibleDefect => this != DamageClass.noVisibleDamage;
}

class DamageBoundingBox {
  const DamageBoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory DamageBoundingBox.fromJson(Map<String, dynamic> json) {
    final x = json['x'];
    final y = json['y'];
    final width = json['width'];
    final height = json['height'];
    if (x is! num ||
        y is! num ||
        width is! num ||
        height is! num ||
        !x.isFinite ||
        !y.isFinite ||
        !width.isFinite ||
        !height.isFinite ||
        x < 0 ||
        x > 1 ||
        y < 0 ||
        y > 1 ||
        width <= 0 ||
        width > 1 ||
        height <= 0 ||
        height > 1 ||
        x + width > 1 ||
        y + height > 1) {
      throw const FormatException('Invalid damage bounding box.');
    }
    return DamageBoundingBox(
      x: x.toDouble(),
      y: y.toDouble(),
      width: width.toDouble(),
      height: height.toDouble(),
    );
  }

  final double x;
  final double y;
  final double width;
  final double height;

  Map<String, double> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };
}

class DamageDetectionResult {
  const DamageDetectionResult({
    required this.damageClass,
    required this.modelScore,
    required this.recommendation,
    required this.disclaimer,
    required this.modelId,
    this.boundingBox,
  });

  factory DamageDetectionResult.fromJson(Map<String, dynamic> json) {
    final damageClass = DamageClass.fromStoredValue(json['damageClass']);
    final score = json['modelScore'];
    final rawBox = json['boundingBox'];
    final recommendation = json['recommendation'];
    final disclaimer = json['disclaimer'];
    final modelId = json['modelId'];
    if (damageClass == null ||
        score is! num ||
        !score.isFinite ||
        score < 0 ||
        score > 1 ||
        (rawBox != null && rawBox is! Map) ||
        recommendation is! String ||
        recommendation.trim().isEmpty ||
        disclaimer is! String ||
        disclaimer.trim().isEmpty ||
        modelId is! String ||
        modelId.trim().isEmpty) {
      throw const FormatException('Invalid damage-detection response.');
    }
    return DamageDetectionResult(
      damageClass: damageClass,
      modelScore: score.toDouble(),
      boundingBox: rawBox == null
          ? null
          : DamageBoundingBox.fromJson(Map<String, dynamic>.from(rawBox)),
      recommendation: recommendation.trim(),
      disclaimer: disclaimer.trim(),
      modelId: modelId.trim(),
    );
  }

  final DamageClass damageClass;
  final double modelScore;
  final DamageBoundingBox? boundingBox;
  final String recommendation;
  final String disclaimer;
  final String modelId;
}

enum DamagePhotoSourceType { upload, inspection }

class DamageReport {
  const DamageReport({
    required this.id,
    required this.studentId,
    required this.propertyId,
    required this.imagePath,
    required this.sourceType,
    required this.result,
    required this.createdAt,
    this.inspectionId,
    this.checkId,
  });

  final String id;
  final String studentId;
  final String propertyId;
  final String imagePath;
  final DamagePhotoSourceType sourceType;
  final String? inspectionId;
  final String? checkId;
  final DamageDetectionResult result;
  final DateTime? createdAt;
}

class DamageImageInput {
  const DamageImageInput({required this.byteLength, required this.contentType});

  static const maxBytes = 10 * 1024 * 1024;

  final int byteLength;
  final String contentType;

  String? validate() {
    if (byteLength <= 0 || byteLength > maxBytes) {
      return 'Choose a damage photo smaller than 10 MiB.';
    }
    if (!const {
      'image/jpeg',
      'image/png',
      'image/webp',
    }.contains(contentType)) {
      return 'Choose a JPEG, PNG, or WebP damage photo.';
    }
    return null;
  }
}
