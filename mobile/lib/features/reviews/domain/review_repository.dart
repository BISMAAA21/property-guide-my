import 'property_review.dart';

abstract interface class ReviewRepository {
  Stream<List<PropertyReview>> watchPropertyReviews(String propertyId);

  Future<void> saveReview({
    required String propertyId,
    required ReviewWriteInput input,
  });

  Future<void> removeReview(PropertyReview review);
}
