import 'dart:typed_data';

import 'property_listing.dart';

abstract interface class PropertyRepository {
  Stream<List<PropertyListing>> watchOwnedListings(String agentId);

  Stream<List<PropertyListing>> watchAllListings();

  Stream<List<PropertyListing>> watchApprovedListings();

  Stream<PropertyListing?> watchListing(String propertyId);

  Future<String> createListing(PropertyWriteInput input);

  Future<void> updateListing(String propertyId, PropertyWriteInput input);

  Future<void> submitForReview(String propertyId);

  Future<void> deactivateListing(String propertyId);

  Future<void> approveListing(String propertyId);

  Future<void> rejectListing(String propertyId, String reason);

  Future<void> removeListing(String propertyId);

  Future<String> uploadListingImage({
    required String propertyId,
    required Uint8List bytes,
    required String filename,
    required String contentType,
  });

  Future<void> removeListingImage({
    required String propertyId,
    required String imageUrl,
  });
}
