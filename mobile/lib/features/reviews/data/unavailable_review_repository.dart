import '../domain/property_review.dart';
import '../domain/review_failure.dart';
import '../domain/review_repository.dart';

class UnavailableReviewRepository implements ReviewRepository {
  const UnavailableReviewRepository();

  ReviewFailure get _failure => const ReviewFailure(
    'firebase-not-configured',
    'Connect the Firebase project before managing reviews.',
  );

  @override
  Future<void> removeReview(PropertyReview review) async => throw _failure;

  @override
  Future<void> saveReview({
    required String propertyId,
    required ReviewWriteInput input,
  }) async => throw _failure;

  @override
  Stream<List<PropertyReview>> watchPropertyReviews(String propertyId) =>
      Stream.error(_failure);
}
