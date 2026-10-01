class PropertyReview {
  const PropertyReview({
    required this.id,
    required this.propertyId,
    required this.studentId,
    required this.studentName,
    required this.rating,
    required this.comment,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String propertyId;
  final String studentId;
  final String studentName;
  final int rating;
  final String comment;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

class ReviewWriteInput {
  const ReviewWriteInput({required this.rating, required this.comment});

  final int rating;
  final String comment;

  String? validate() {
    if (rating < 1 || rating > 5) {
      return 'Choose a rating from one to five stars.';
    }
    final normalizedComment = comment.trim();
    if (normalizedComment.length < 5) {
      return 'Write at least 5 characters about the property.';
    }
    if (normalizedComment.length > 1000) {
      return 'Keep the review within 1000 characters.';
    }
    return null;
  }
}
