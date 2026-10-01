enum PropertyApprovalStatus {
  draft,
  pending,
  approved,
  rejected,
  inactive;

  static PropertyApprovalStatus? fromStoredValue(Object? value) {
    return values.where((status) => status.name == value).firstOrNull;
  }

  String get displayName => switch (this) {
    PropertyApprovalStatus.draft => 'Draft',
    PropertyApprovalStatus.pending => 'Pending review',
    PropertyApprovalStatus.approved => 'Approved',
    PropertyApprovalStatus.rejected => 'Changes required',
    PropertyApprovalStatus.inactive => 'Inactive',
  };

  bool get isEditable =>
      this == PropertyApprovalStatus.draft ||
      this == PropertyApprovalStatus.rejected;
}

enum PropertyType {
  room,
  studio,
  apartment,
  condominium,
  house;

  static PropertyType? fromStoredValue(Object? value) {
    return values.where((type) => type.name == value).firstOrNull;
  }

  String get displayName => switch (this) {
    PropertyType.room => 'Room',
    PropertyType.studio => 'Studio',
    PropertyType.apartment => 'Apartment',
    PropertyType.condominium => 'Condominium',
    PropertyType.house => 'House',
  };
}

class PropertyListing {
  const PropertyListing({
    required this.id,
    required this.agentId,
    required this.propertyName,
    required this.location,
    required this.normalizedLocation,
    required this.monthlyRent,
    required this.bedrooms,
    required this.bathrooms,
    required this.propertyType,
    required this.description,
    required this.facilities,
    required this.imageUrls,
    required this.approvalStatus,
    required this.ratingAverage,
    required this.ratingCount,
    required this.createdAt,
    required this.updatedAt,
    this.rejectionReason,
  });

  final String id;
  final String agentId;
  final String propertyName;
  final String location;
  final String normalizedLocation;
  final double monthlyRent;
  final int bedrooms;
  final int bathrooms;
  final PropertyType propertyType;
  final String description;
  final List<String> facilities;
  final List<String> imageUrls;
  final PropertyApprovalStatus approvalStatus;
  final String? rejectionReason;
  final double ratingAverage;
  final int ratingCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

class PropertyWriteInput {
  const PropertyWriteInput({
    required this.propertyName,
    required this.location,
    required this.monthlyRent,
    required this.bedrooms,
    required this.bathrooms,
    required this.propertyType,
    required this.description,
    required this.facilities,
  });

  final String propertyName;
  final String location;
  final double monthlyRent;
  final int bedrooms;
  final int bathrooms;
  final PropertyType propertyType;
  final String description;
  final List<String> facilities;

  String? validate() {
    if (propertyName.trim().length < 3) {
      return 'Enter a property name with at least 3 characters.';
    }
    if (location.trim().length < 3) {
      return 'Enter a Malaysian property location.';
    }
    if (!monthlyRent.isFinite || monthlyRent <= 0 || monthlyRent > 100000) {
      return 'Enter a valid monthly rent.';
    }
    if (bedrooms < 0 || bedrooms > 20) {
      return 'Bedrooms must be between 0 and 20.';
    }
    if (bathrooms < 1 || bathrooms > 20) {
      return 'Bathrooms must be between 1 and 20.';
    }
    if (description.trim().length < 20) {
      return 'Describe the property using at least 20 characters.';
    }
    if (facilities.length > 20 || facilities.any((item) => item.length > 60)) {
      return 'Provide no more than 20 short facility names.';
    }
    return null;
  }

  List<String> get normalizedFacilities => facilities
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

abstract final class PropertyLifecycle {
  static bool canAgentTransition(
    PropertyApprovalStatus from,
    PropertyApprovalStatus to,
  ) {
    return (from.isEditable && to == PropertyApprovalStatus.pending) ||
        (from == PropertyApprovalStatus.approved &&
            to == PropertyApprovalStatus.inactive);
  }

  static bool canAdminTransition(
    PropertyApprovalStatus from,
    PropertyApprovalStatus to,
  ) {
    return from == PropertyApprovalStatus.pending &&
        (to == PropertyApprovalStatus.approved ||
            to == PropertyApprovalStatus.rejected);
  }
}

enum PropertySortOrder {
  newest,
  priceLowToHigh,
  priceHighToLow,
  ratingHighToLow,
}

class PropertySearchFilter {
  const PropertySearchFilter({
    this.query = '',
    this.location = '',
    this.minimumRent,
    this.maximumRent,
    this.minimumRating,
    this.sortOrder = PropertySortOrder.newest,
  });

  final String query;
  final String location;
  final double? minimumRent;
  final double? maximumRent;
  final double? minimumRating;
  final PropertySortOrder sortOrder;

  String? validate() {
    if (minimumRent != null && minimumRent! < 0) {
      return 'Minimum rent cannot be negative.';
    }
    if (maximumRent != null && maximumRent! <= 0) {
      return 'Maximum rent must be greater than zero.';
    }
    if (minimumRent != null &&
        maximumRent != null &&
        minimumRent! > maximumRent!) {
      return 'Minimum rent cannot exceed maximum rent.';
    }
    if (minimumRating != null && (minimumRating! < 0 || minimumRating! > 5)) {
      return 'Rating must be between zero and five.';
    }
    return null;
  }

  List<PropertyListing> apply(Iterable<PropertyListing> source) {
    final validationError = validate();
    if (validationError != null) {
      throw ArgumentError(validationError);
    }
    final normalizedQuery = query.trim().toLowerCase();
    final normalizedLocation = location.trim().toLowerCase();
    final results = source
        .where((listing) {
          if (listing.approvalStatus != PropertyApprovalStatus.approved) {
            return false;
          }
          if (normalizedQuery.isNotEmpty &&
              !listing.propertyName.toLowerCase().contains(normalizedQuery) &&
              !listing.description.toLowerCase().contains(normalizedQuery) &&
              !listing.normalizedLocation.contains(normalizedQuery)) {
            return false;
          }
          if (normalizedLocation.isNotEmpty &&
              !listing.normalizedLocation.contains(normalizedLocation)) {
            return false;
          }
          if (minimumRent != null && listing.monthlyRent < minimumRent!) {
            return false;
          }
          if (maximumRent != null && listing.monthlyRent > maximumRent!) {
            return false;
          }
          if (minimumRating != null && listing.ratingAverage < minimumRating!) {
            return false;
          }
          return true;
        })
        .toList(growable: false);

    results.sort(switch (sortOrder) {
      PropertySortOrder.newest =>
        (left, right) =>
            (right.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                .compareTo(
                  left.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                ),
      PropertySortOrder.priceLowToHigh => (
        left,
        right,
      ) => left.monthlyRent.compareTo(right.monthlyRent),
      PropertySortOrder.priceHighToLow => (
        left,
        right,
      ) => right.monthlyRent.compareTo(left.monthlyRent),
      PropertySortOrder.ratingHighToLow => (
        left,
        right,
      ) => right.ratingAverage.compareTo(left.ratingAverage),
    });
    return List.unmodifiable(results);
  }
}
