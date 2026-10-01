import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../properties/domain/property_listing.dart';
import '../domain/property_review.dart';
import '../domain/review_failure.dart';
import '../domain/review_repository.dart';

class FirebaseReviewRepository implements ReviewRepository {
  FirebaseReviewRepository({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _reviews =>
      _firestore.collection('reviews');

  @override
  Stream<List<PropertyReview>> watchPropertyReviews(String propertyId) {
    return _reviews
        .where('propertyId', isEqualTo: propertyId)
        .limit(100)
        .snapshots()
        .map((snapshot) {
          final reviews =
              snapshot.docs.map(_fromDocument).toList(growable: false)..sort(
                (left, right) =>
                    (right.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                        .compareTo(
                          left.updatedAt ??
                              DateTime.fromMillisecondsSinceEpoch(0),
                        ),
              );
          return List.unmodifiable(reviews);
        });
  }

  @override
  Future<void> saveReview({
    required String propertyId,
    required ReviewWriteInput input,
  }) async {
    final validationError = input.validate();
    if (validationError != null) {
      throw ReviewFailure('invalid-review', validationError);
    }
    final uid = _authenticatedUid();
    final propertyReference = _firestore
        .collection('properties')
        .doc(propertyId);
    final profileReference = _firestore.collection('users').doc(uid);
    final reviewReference = _reviews.doc(_reviewId(propertyId, uid));
    try {
      await _firestore.runTransaction((transaction) async {
        final propertySnapshot = await transaction.get(propertyReference);
        final profileSnapshot = await transaction.get(profileReference);
        final reviewSnapshot = await transaction.get(reviewReference);
        final propertyData = propertySnapshot.data();
        final profileData = profileSnapshot.data();
        if (!propertySnapshot.exists ||
            propertyData?['approvalStatus'] !=
                PropertyApprovalStatus.approved.name) {
          throw const ReviewFailure(
            'property-not-reviewable',
            'Only approved properties can be reviewed.',
          );
        }
        if (!profileSnapshot.exists ||
            profileData?['role'] != 'student' ||
            profileData?['status'] != 'active') {
          throw const ReviewFailure(
            'student-required',
            'An active student account is required to review a property.',
          );
        }
        final ratingCount =
            (propertyData?['ratingCount'] as num?)?.toInt() ?? 0;
        final ratingAverage =
            (propertyData?['ratingAverage'] as num?)?.toDouble() ?? 0;
        final oldRating = reviewSnapshot.exists
            ? (reviewSnapshot.data()?['rating'] as num).toInt()
            : null;
        final newCount = oldRating == null ? ratingCount + 1 : ratingCount;
        final oldTotal = ratingAverage * ratingCount;
        final newTotal = oldTotal - (oldRating ?? 0) + input.rating;
        final newAverage = newCount == 0 ? 0 : newTotal / newCount;
        final now = FieldValue.serverTimestamp();
        transaction.set(reviewReference, {
          'propertyId': propertyId,
          'studentId': uid,
          'studentName': (profileData?['name'] as String).trim(),
          'rating': input.rating,
          'comment': input.comment.trim(),
          'createdAt': reviewSnapshot.exists
              ? reviewSnapshot.data()!['createdAt']
              : now,
          'updatedAt': now,
        });
        transaction.update(propertyReference, {
          'ratingAverage': newAverage,
          'ratingCount': newCount,
          'updatedAt': now,
        });
      });
    } on FirebaseException catch (error) {
      throw _mapFirebaseError(error);
    }
  }

  @override
  Future<void> removeReview(PropertyReview review) async {
    _authenticatedUid();
    final reviewReference = _reviews.doc(review.id);
    final propertyReference = _firestore
        .collection('properties')
        .doc(review.propertyId);
    try {
      await _firestore.runTransaction((transaction) async {
        final reviewSnapshot = await transaction.get(reviewReference);
        final propertySnapshot = await transaction.get(propertyReference);
        if (!reviewSnapshot.exists) return;
        final propertyData = propertySnapshot.data();
        if (!propertySnapshot.exists || propertyData == null) {
          transaction.delete(reviewReference);
          return;
        }
        final ratingCount = (propertyData['ratingCount'] as num?)?.toInt() ?? 0;
        final ratingAverage =
            (propertyData['ratingAverage'] as num?)?.toDouble() ?? 0;
        final storedRating =
            (reviewSnapshot.data()?['rating'] as num?)?.toInt() ??
            review.rating;
        final newCount = ratingCount > 0 ? ratingCount - 1 : 0;
        final newAverage = newCount == 0
            ? 0.0
            : ((ratingAverage * ratingCount) - storedRating) / newCount;
        transaction.delete(reviewReference);
        transaction.update(propertyReference, {
          'ratingAverage': newAverage,
          'ratingCount': newCount,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } on FirebaseException catch (error) {
      throw _mapFirebaseError(error);
    }
  }

  String _authenticatedUid() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const ReviewFailure(
        'auth-required',
        'Sign in before managing reviews.',
      );
    }
    return uid;
  }

  static String _reviewId(String propertyId, String studentId) =>
      '${propertyId}_$studentId';

  static PropertyReview _fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final propertyId = data['propertyId'];
    final studentId = data['studentId'];
    final studentName = data['studentName'];
    final comment = data['comment'];
    final rating = data['rating'];
    if (propertyId is! String ||
        studentId is! String ||
        studentName is! String ||
        comment is! String ||
        rating is! num ||
        rating.toInt() < 1 ||
        rating.toInt() > 5) {
      throw const ReviewFailure(
        'invalid-review-data',
        'A stored property review contains invalid fields.',
      );
    }
    return PropertyReview(
      id: document.id,
      propertyId: propertyId,
      studentId: studentId,
      studentName: studentName.trim(),
      rating: rating.toInt(),
      comment: comment.trim(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  static ReviewFailure _mapFirebaseError(FirebaseException error) {
    final message = switch (error.code) {
      'permission-denied' =>
        'You are not allowed to perform this review action.',
      'unavailable' => 'The review service is temporarily unavailable.',
      _ => 'The review action could not be completed. Please try again.',
    };
    return ReviewFailure(error.code, message);
  }
}
