import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../shared/validation/image_content.dart';
import '../domain/property_failure.dart';
import '../domain/property_listing.dart';
import '../domain/property_repository.dart';

class FirebasePropertyRepository implements PropertyRepository {
  FirebasePropertyRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance;

  static const maxListingImageBytes = 10 * 1024 * 1024;
  static const maxListingImages = 8;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _properties =>
      _firestore.collection('properties');

  CollectionReference<Map<String, dynamic>> get _reviews =>
      _firestore.collection('reviews');

  @override
  Stream<List<PropertyListing>> watchOwnedListings(String agentId) {
    if (agentId.isEmpty) {
      return Stream.error(
        const PropertyFailure(
          'agent-required',
          'An agent account is required.',
        ),
      );
    }
    return _properties
        .where('agentId', isEqualTo: agentId)
        .snapshots()
        .map(
          (snapshot) => _sorted(
            snapshot.docs.map(_listingFromDocument).toList(growable: false),
          ),
        );
  }

  @override
  Stream<List<PropertyListing>> watchAllListings() {
    return _properties.snapshots().map(
      (snapshot) => _sorted(
        snapshot.docs.map(_listingFromDocument).toList(growable: false),
      ),
    );
  }

  @override
  Stream<List<PropertyListing>> watchApprovedListings() {
    return _properties
        .where(
          'approvalStatus',
          isEqualTo: PropertyApprovalStatus.approved.name,
        )
        .orderBy('updatedAt', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => _sorted(
            snapshot.docs.map(_listingFromDocument).toList(growable: false),
          ),
        );
  }

  @override
  Stream<PropertyListing?> watchListing(String propertyId) {
    return _properties
        .doc(propertyId)
        .snapshots()
        .map(
          (document) => document.exists ? _listingFromDocument(document) : null,
        );
  }

  @override
  Future<String> createListing(PropertyWriteInput input) async {
    _validateInput(input);
    final uid = _authenticatedUid();
    final document = _properties.doc();
    try {
      await document.set({
        ..._writeData(input),
        'agentId': uid,
        'imageUrls': <String>[],
        'approvalStatus': PropertyApprovalStatus.draft.name,
        'ratingAverage': 0,
        'ratingCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return document.id;
    } on FirebaseException catch (error) {
      throw _mapFirebaseError(error);
    }
  }

  @override
  Future<void> updateListing(
    String propertyId,
    PropertyWriteInput input,
  ) async {
    _validateInput(input);
    final uid = _authenticatedUid();
    try {
      await _firestore.runTransaction((transaction) async {
        final reference = _properties.doc(propertyId);
        final snapshot = await transaction.get(reference);
        final listing = _existingListing(snapshot);
        _requireOwner(listing, uid);
        if (!listing.approvalStatus.isEditable) {
          throw const PropertyFailure(
            'listing-not-editable',
            'Only draft or rejected listings can be edited.',
          );
        }
        transaction.update(reference, {
          ..._writeData(input),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } on FirebaseException catch (error) {
      throw _mapFirebaseError(error);
    }
  }

  @override
  Future<void> submitForReview(String propertyId) async {
    final uid = _authenticatedUid();
    await _transition(
      propertyId,
      allowed: (listing) {
        _requireOwner(listing, uid);
        if (listing.imageUrls.isEmpty) {
          throw const PropertyFailure(
            'listing-image-required',
            'Add at least one listing image before submitting for review.',
          );
        }
        return PropertyLifecycle.canAgentTransition(
          listing.approvalStatus,
          PropertyApprovalStatus.pending,
        );
      },
      target: PropertyApprovalStatus.pending,
      extra: {'rejectionReason': FieldValue.delete()},
    );
  }

  @override
  Future<void> deactivateListing(String propertyId) async {
    final uid = _authenticatedUid();
    await _transition(
      propertyId,
      allowed: (listing) {
        _requireOwner(listing, uid);
        return PropertyLifecycle.canAgentTransition(
          listing.approvalStatus,
          PropertyApprovalStatus.inactive,
        );
      },
      target: PropertyApprovalStatus.inactive,
    );
  }

  @override
  Future<void> approveListing(String propertyId) {
    _authenticatedUid();
    return _transition(
      propertyId,
      allowed: (listing) => PropertyLifecycle.canAdminTransition(
        listing.approvalStatus,
        PropertyApprovalStatus.approved,
      ),
      target: PropertyApprovalStatus.approved,
      extra: {'rejectionReason': FieldValue.delete()},
    );
  }

  @override
  Future<void> rejectListing(String propertyId, String reason) {
    _authenticatedUid();
    final normalizedReason = reason.trim();
    if (normalizedReason.length < 5 || normalizedReason.length > 500) {
      throw const PropertyFailure(
        'invalid-rejection-reason',
        'Explain the required changes using 5 to 500 characters.',
      );
    }
    return _transition(
      propertyId,
      allowed: (listing) => PropertyLifecycle.canAdminTransition(
        listing.approvalStatus,
        PropertyApprovalStatus.rejected,
      ),
      target: PropertyApprovalStatus.rejected,
      extra: {'rejectionReason': normalizedReason},
    );
  }

  @override
  Future<void> removeListing(String propertyId) async {
    _authenticatedUid();
    final reference = _properties.doc(propertyId);
    try {
      final snapshot = await reference.get();
      final listing = _existingListing(snapshot);
      final reviews = await _reviews
          .where('propertyId', isEqualTo: propertyId)
          .get();
      if (reviews.docs.length > 450) {
        throw const PropertyFailure(
          'review-cleanup-limit',
          'This listing has too many reviews for safe client-side removal. Contact an administrator.',
        );
      }
      final batch = _firestore.batch()..delete(reference);
      for (final review in reviews.docs) {
        batch.delete(review.reference);
      }
      await batch.commit();
      var cleanupFailed = false;
      for (final imageUrl in listing.imageUrls) {
        try {
          await _storage.refFromURL(imageUrl).delete();
        } on FirebaseException catch (error) {
          if (error.code != 'object-not-found') cleanupFailed = true;
        }
      }
      if (cleanupFailed) {
        throw const PropertyFailure(
          'listing-image-cleanup-failed',
          'The listing was removed, but one or more unlinked images require administrator cleanup.',
        );
      }
    } on FirebaseException catch (error) {
      throw _mapFirebaseError(error);
    }
  }

  @override
  Future<String> uploadListingImage({
    required String propertyId,
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async {
    if (bytes.isEmpty || bytes.length > maxListingImageBytes) {
      throw const PropertyFailure(
        'invalid-image-size',
        'Choose an image smaller than 10 MiB.',
      );
    }
    final normalizedType = normalizeImageContentType(contentType);
    if (!supportedImageContentTypes.contains(normalizedType) ||
        !imageContentMatchesType(bytes, normalizedType)) {
      throw const PropertyFailure(
        'invalid-image-type',
        'Choose a valid JPEG, PNG, or WebP image whose content matches its type.',
      );
    }

    final uid = _authenticatedUid();
    final propertyReference = _properties.doc(propertyId);
    final snapshot = await propertyReference.get();
    final listing = _existingListing(snapshot);
    _requireOwner(listing, uid);
    if (!listing.approvalStatus.isEditable) {
      throw const PropertyFailure(
        'listing-not-editable',
        'Images can be changed only on draft or rejected listings.',
      );
    }
    if (listing.imageUrls.length >= maxListingImages) {
      throw const PropertyFailure(
        'image-limit',
        'A listing can contain up to 8 images.',
      );
    }

    final safeFilename = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final imageReference = _storage
        .ref()
        .child('properties/$uid/$propertyId/listing')
        .child('${DateTime.now().microsecondsSinceEpoch}_$safeFilename');
    try {
      await imageReference.putData(
        bytes,
        SettableMetadata(
          contentType: normalizedType,
          customMetadata: {'ownerId': uid, 'propertyId': propertyId},
        ),
      );
      final downloadUrl = await imageReference.getDownloadURL();
      try {
        await propertyReference.update({
          'imageUrls': FieldValue.arrayUnion([downloadUrl]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } on FirebaseException catch (error) {
        try {
          await imageReference.delete();
        } on FirebaseException {
          throw const PropertyFailure(
            'upload-rollback-failed',
            'The image uploaded but could not be linked or cleaned up. Contact an administrator.',
          );
        }
        throw _mapFirebaseError(error);
      }
      return downloadUrl;
    } on FirebaseException catch (error) {
      throw _mapFirebaseError(error);
    }
  }

  @override
  Future<void> removeListingImage({
    required String propertyId,
    required String imageUrl,
  }) async {
    final uid = _authenticatedUid();
    final propertyReference = _properties.doc(propertyId);
    final snapshot = await propertyReference.get();
    final listing = _existingListing(snapshot);
    _requireOwner(listing, uid);
    if (!listing.approvalStatus.isEditable ||
        !listing.imageUrls.contains(imageUrl)) {
      throw const PropertyFailure(
        'image-not-removable',
        'This listing image cannot be removed.',
      );
    }
    try {
      await propertyReference.update({
        'imageUrls': FieldValue.arrayRemove([imageUrl]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      try {
        await _storage.refFromURL(imageUrl).delete();
      } on FirebaseException catch (error) {
        if (error.code != 'object-not-found') {
          throw const PropertyFailure(
            'listing-image-cleanup-failed',
            'The image was removed from the listing, but its unlinked file requires administrator cleanup.',
          );
        }
      }
    } on FirebaseException catch (error) {
      throw _mapFirebaseError(error);
    }
  }

  Future<void> _transition(
    String propertyId, {
    required bool Function(PropertyListing listing) allowed,
    required PropertyApprovalStatus target,
    Map<String, Object?> extra = const {},
  }) async {
    try {
      await _firestore.runTransaction((transaction) async {
        final reference = _properties.doc(propertyId);
        final snapshot = await transaction.get(reference);
        final listing = _existingListing(snapshot);
        if (!allowed(listing)) {
          throw PropertyFailure(
            'invalid-status-transition',
            'A ${listing.approvalStatus.displayName.toLowerCase()} listing cannot move to ${target.displayName.toLowerCase()}.',
          );
        }
        transaction.update(reference, {
          'approvalStatus': target.name,
          'updatedAt': FieldValue.serverTimestamp(),
          ...extra,
        });
      });
    } on FirebaseException catch (error) {
      throw _mapFirebaseError(error);
    }
  }

  String _authenticatedUid() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const PropertyFailure(
        'auth-required',
        'Sign in before managing property listings.',
      );
    }
    return uid;
  }

  static Map<String, Object?> _writeData(PropertyWriteInput input) => {
    'propertyName': input.propertyName.trim(),
    'location': input.location.trim(),
    'normalizedLocation': input.location.trim().toLowerCase(),
    'monthlyRent': input.monthlyRent,
    'bedrooms': input.bedrooms,
    'bathrooms': input.bathrooms,
    'propertyType': input.propertyType.name,
    'description': input.description.trim(),
    'facilities': input.normalizedFacilities,
  };

  static void _validateInput(PropertyWriteInput input) {
    final validationError = input.validate();
    if (validationError != null) {
      throw PropertyFailure('invalid-property', validationError);
    }
  }

  static void _requireOwner(PropertyListing listing, String uid) {
    if (listing.agentId != uid) {
      throw const PropertyFailure(
        'property-not-owned',
        'You can manage only your own property listings.',
      );
    }
  }

  static PropertyListing _existingListing(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (!snapshot.exists) {
      throw const PropertyFailure(
        'property-not-found',
        'The property listing no longer exists.',
      );
    }
    return _listingFromDocument(snapshot);
  }

  static PropertyListing _listingFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      throw const PropertyFailure(
        'invalid-property-data',
        'The property listing data is missing.',
      );
    }
    final status = PropertyApprovalStatus.fromStoredValue(
      data['approvalStatus'],
    );
    final propertyType = PropertyType.fromStoredValue(data['propertyType']);
    final facilities = _stringList(data['facilities']);
    final imageUrls = _stringList(data['imageUrls']);
    if (status == null || propertyType == null) {
      throw const PropertyFailure(
        'invalid-property-data',
        'The property listing contains an unsupported type or status.',
      );
    }
    try {
      return PropertyListing(
        id: document.id,
        agentId: _requiredString(data, 'agentId'),
        propertyName: _requiredString(data, 'propertyName'),
        location: _requiredString(data, 'location'),
        normalizedLocation: _requiredString(data, 'normalizedLocation'),
        monthlyRent: (data['monthlyRent'] as num).toDouble(),
        bedrooms: (data['bedrooms'] as num).toInt(),
        bathrooms: (data['bathrooms'] as num).toInt(),
        propertyType: propertyType,
        description: _requiredString(data, 'description'),
        facilities: facilities,
        imageUrls: imageUrls,
        approvalStatus: status,
        rejectionReason: (data['rejectionReason'] as String?)?.trim(),
        ratingAverage: (data['ratingAverage'] as num?)?.toDouble() ?? 0,
        ratingCount: (data['ratingCount'] as num?)?.toInt() ?? 0,
        createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
        updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      );
    } on TypeError {
      throw const PropertyFailure(
        'invalid-property-data',
        'The property listing contains invalid data and cannot be displayed.',
      );
    }
  }

  static String _requiredString(Map<String, dynamic> data, String field) {
    final value = data[field];
    if (value is! String || value.trim().isEmpty) {
      throw PropertyFailure(
        'invalid-property-data',
        'The property listing is missing $field.',
      );
    }
    return value.trim();
  }

  static List<String> _stringList(Object? value) {
    if (value is! List || value.any((item) => item is! String)) {
      throw const PropertyFailure(
        'invalid-property-data',
        'The property listing contains an invalid list field.',
      );
    }
    return List<String>.unmodifiable(value.cast<String>());
  }

  static List<PropertyListing> _sorted(List<PropertyListing> listings) {
    listings.sort(
      (left, right) =>
          (right.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
            left.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          ),
    );
    return List.unmodifiable(listings);
  }

  static PropertyFailure _mapFirebaseError(FirebaseException error) {
    final message = switch (error.code) {
      'permission-denied' =>
        'You are not allowed to perform this property action.',
      'unavailable' => 'The property service is temporarily unavailable.',
      'not-found' ||
      'object-not-found' => 'The property or image no longer exists.',
      'unauthenticated' => 'Sign in before managing property listings.',
      _ => 'The property action could not be completed. Please try again.',
    };
    return PropertyFailure(error.code, message);
  }
}
