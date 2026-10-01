import 'dart:typed_data';

import '../domain/property_failure.dart';
import '../domain/property_listing.dart';
import '../domain/property_repository.dart';

class UnavailablePropertyRepository implements PropertyRepository {
  const UnavailablePropertyRepository();

  PropertyFailure get _failure => const PropertyFailure(
    'firebase-not-configured',
    'Connect the Firebase project before managing property listings.',
  );

  Never _unavailable() => throw const PropertyFailure(
    'firebase-not-configured',
    'Connect the Firebase project before managing property listings.',
  );

  @override
  Future<void> approveListing(String propertyId) async => _unavailable();

  @override
  Future<String> createListing(PropertyWriteInput input) async =>
      _unavailable();

  @override
  Future<void> deactivateListing(String propertyId) async => _unavailable();

  @override
  Future<void> rejectListing(String propertyId, String reason) async =>
      _unavailable();

  @override
  Future<void> removeListing(String propertyId) async => _unavailable();

  @override
  Future<void> removeListingImage({
    required String propertyId,
    required String imageUrl,
  }) async => _unavailable();

  @override
  Future<void> submitForReview(String propertyId) async => _unavailable();

  @override
  Future<void> updateListing(
    String propertyId,
    PropertyWriteInput input,
  ) async => _unavailable();

  @override
  Future<String> uploadListingImage({
    required String propertyId,
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async => _unavailable();

  @override
  Stream<List<PropertyListing>> watchAllListings() => Stream.error(_failure);

  @override
  Stream<List<PropertyListing>> watchApprovedListings() =>
      Stream.error(_failure);

  @override
  Stream<PropertyListing?> watchListing(String propertyId) =>
      Stream.error(_failure);

  @override
  Stream<List<PropertyListing>> watchOwnedListings(String agentId) =>
      Stream.error(_failure);
}
