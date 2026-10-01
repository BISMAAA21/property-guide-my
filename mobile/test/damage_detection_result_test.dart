import 'package:flutter_test/flutter_test.dart';
import 'package:property_guidance/features/damage_detection/domain/damage_detection_result.dart';

void main() {
  test('valid damage API result preserves supported class and score', () {
    final result = DamageDetectionResult.fromJson({
      'damageClass': 'water_or_damp_stain',
      'modelScore': 0.82,
      'boundingBox': null,
      'recommendation': 'Possible damp staining; inspect the area.',
      'disclaimer': 'AI-assisted observation only.',
      'modelId': 'controlled-model',
    });

    expect(result.damageClass, DamageClass.waterOrDampStain);
    expect(result.modelScore, 0.82);
    expect(result.boundingBox, isNull);
    expect(result.damageClass.displayName, 'Possible water or damp stain');
  });

  test('unknown label is rejected instead of expanding defect scope', () {
    expect(
      () => DamageDetectionResult.fromJson({
        'damageClass': 'electrical_fault',
        'modelScore': 0.9,
        'boundingBox': null,
        'recommendation': 'Unsupported label.',
        'disclaimer': 'AI-assisted observation only.',
        'modelId': 'controlled-model',
      }),
      throwsFormatException,
    );
  });

  test('bounding box must remain inside normalized image coordinates', () {
    expect(
      () => DamageDetectionResult.fromJson({
        'damageClass': 'mold',
        'modelScore': 0.7,
        'boundingBox': {'x': 0.8, 'y': 0.2, 'width': 0.4, 'height': 0.3},
        'recommendation': 'Possible mold.',
        'disclaimer': 'AI-assisted observation only.',
        'modelId': 'controlled-model',
      }),
      throwsFormatException,
    );
  });
}
