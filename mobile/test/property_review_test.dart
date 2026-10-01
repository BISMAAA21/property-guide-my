import 'package:flutter_test/flutter_test.dart';
import 'package:property_guidance/features/reviews/domain/property_review.dart';

void main() {
  group('ReviewWriteInput', () {
    test('accepts a star rating and useful text', () {
      const input = ReviewWriteInput(
        rating: 4,
        comment: 'The room matched the approved listing photographs.',
      );

      expect(input.validate(), isNull);
    });

    test('rejects out-of-range stars and unhelpful text', () {
      expect(
        const ReviewWriteInput(rating: 0, comment: 'Useful review').validate(),
        'Choose a rating from one to five stars.',
      );
      expect(
        const ReviewWriteInput(rating: 5, comment: 'Bad').validate(),
        'Write at least 5 characters about the property.',
      );
    });
  });
}
