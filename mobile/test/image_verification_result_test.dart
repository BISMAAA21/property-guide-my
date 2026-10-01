import 'package:flutter_test/flutter_test.dart';
import 'package:property_guidance/features/image_verification/domain/image_verification_result.dart';

void main() {
  test('valid API result preserves calibrated score and best image index', () {
    final result = ImageVerificationResult.fromJson({
      'similarityScore': 92.4,
      'similarityLevel': 'high',
      'possibleMismatch': false,
      'mismatchWarning': null,
      'bestListingImageIndex': 1,
      'guidance': 'Check the property details in person.',
      'disclaimer':
          'AI-assisted guidance only; this does not guarantee authenticity.',
      'modelId': 'controlled-model',
    }, listingImageCount: 3);

    expect(result.similarityScore, 92.4);
    expect(result.similarityLevel, SimilarityLevel.high);
    expect(result.bestListingImageIndex, 1);
    expect(result.possibleMismatch, isFalse);
  });

  test('low result must carry both mismatch flag and warning', () {
    expect(
      () => ImageVerificationResult.fromJson({
        'similarityScore': 32,
        'similarityLevel': 'low',
        'possibleMismatch': false,
        'mismatchWarning': null,
        'bestListingImageIndex': 0,
        'guidance': 'Check the exact unit.',
        'disclaimer': 'AI guidance only.',
        'modelId': 'controlled-model',
      }, listingImageCount: 1),
      throwsFormatException,
    );
  });

  test('best listing index must refer to a submitted listing image', () {
    expect(
      () => ImageVerificationResult.fromJson({
        'similarityScore': 80,
        'similarityLevel': 'moderate',
        'possibleMismatch': false,
        'mismatchWarning': null,
        'bestListingImageIndex': 2,
        'guidance': 'Compare fixed features.',
        'disclaimer': 'AI guidance only.',
        'modelId': 'controlled-model',
      }, listingImageCount: 2),
      throwsFormatException,
    );
  });
}
