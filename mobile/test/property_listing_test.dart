import 'package:flutter_test/flutter_test.dart';
import 'package:property_guidance/features/properties/domain/property_listing.dart';

void main() {
  group('PropertyWriteInput', () {
    test('accepts and normalizes a valid Malaysian property draft', () {
      const input = PropertyWriteInput(
        propertyName: ' Cyberjaya Student Suite ',
        location: ' Cyberjaya, Selangor ',
        monthlyRent: 1450,
        bedrooms: 2,
        bathrooms: 1,
        propertyType: PropertyType.apartment,
        description:
            'A controlled demonstration apartment near university campuses.',
        facilities: [' Wi-Fi ', 'Study area', 'Wi-Fi', ''],
      );

      expect(input.validate(), isNull);
      expect(input.normalizedFacilities, ['Wi-Fi', 'Study area']);
    });

    test('rejects invalid rent and insufficient description', () {
      const input = PropertyWriteInput(
        propertyName: 'Demo home',
        location: 'Kuala Lumpur',
        monthlyRent: 0,
        bedrooms: 1,
        bathrooms: 1,
        propertyType: PropertyType.room,
        description: 'Too short',
        facilities: [],
      );

      expect(input.validate(), 'Enter a valid monthly rent.');
    });
  });

  group('PropertyLifecycle', () {
    test('agent transitions are limited to submit and deactivate', () {
      expect(
        PropertyLifecycle.canAgentTransition(
          PropertyApprovalStatus.draft,
          PropertyApprovalStatus.pending,
        ),
        isTrue,
      );
      expect(
        PropertyLifecycle.canAgentTransition(
          PropertyApprovalStatus.rejected,
          PropertyApprovalStatus.pending,
        ),
        isTrue,
      );
      expect(
        PropertyLifecycle.canAgentTransition(
          PropertyApprovalStatus.approved,
          PropertyApprovalStatus.inactive,
        ),
        isTrue,
      );
      expect(
        PropertyLifecycle.canAgentTransition(
          PropertyApprovalStatus.pending,
          PropertyApprovalStatus.approved,
        ),
        isFalse,
      );
    });

    test('administrator can only decide a pending listing', () {
      expect(
        PropertyLifecycle.canAdminTransition(
          PropertyApprovalStatus.pending,
          PropertyApprovalStatus.approved,
        ),
        isTrue,
      );
      expect(
        PropertyLifecycle.canAdminTransition(
          PropertyApprovalStatus.pending,
          PropertyApprovalStatus.rejected,
        ),
        isTrue,
      );
      expect(
        PropertyLifecycle.canAdminTransition(
          PropertyApprovalStatus.draft,
          PropertyApprovalStatus.approved,
        ),
        isFalse,
      );
    });
  });

  group('PropertySearchFilter', () {
    final approvedCyberjaya = _listing(
      id: 'cyberjaya-suite',
      status: PropertyApprovalStatus.approved,
      location: 'Cyberjaya, Selangor',
      rent: 1200,
      rating: 4.6,
      updatedAt: DateTime(2026, 8, 3),
    );
    final approvedKualaLumpur = _listing(
      id: 'kl-room',
      status: PropertyApprovalStatus.approved,
      location: 'Kuala Lumpur',
      rent: 900,
      rating: 3.8,
      updatedAt: DateTime(2026, 8, 5),
    );
    final draft = _listing(
      id: 'private-draft',
      status: PropertyApprovalStatus.draft,
      location: 'Cyberjaya, Selangor',
      rent: 800,
      rating: 5,
      updatedAt: DateTime(2026, 8, 6),
    );

    test('returns only approved listings matching every filter', () {
      const filter = PropertySearchFilter(
        query: 'suite',
        location: 'cyberjaya',
        minimumRent: 1000,
        maximumRent: 1300,
        minimumRating: 4,
      );

      expect(filter.apply([draft, approvedKualaLumpur, approvedCyberjaya]), [
        approvedCyberjaya,
      ]);
    });

    test('sorts approved results by rent, rating, and update date', () {
      final source = [approvedCyberjaya, approvedKualaLumpur, draft];

      expect(
        const PropertySearchFilter(sortOrder: PropertySortOrder.priceLowToHigh)
            .apply(source)
            .map((item) => item.id),
        ['kl-room', 'cyberjaya-suite'],
      );
      expect(
        const PropertySearchFilter(sortOrder: PropertySortOrder.ratingHighToLow)
            .apply(source)
            .map((item) => item.id),
        ['cyberjaya-suite', 'kl-room'],
      );
      expect(
        const PropertySearchFilter().apply(source).map((item) => item.id),
        ['kl-room', 'cyberjaya-suite'],
      );
    });

    test('rejects malformed ranges instead of silently changing them', () {
      const filter = PropertySearchFilter(minimumRent: 1500, maximumRent: 900);

      expect(filter.validate(), 'Minimum rent cannot exceed maximum rent.');
      expect(() => filter.apply([approvedCyberjaya]), throwsArgumentError);
    });
  });
}

PropertyListing _listing({
  required String id,
  required PropertyApprovalStatus status,
  required String location,
  required double rent,
  required double rating,
  required DateTime updatedAt,
}) {
  return PropertyListing(
    id: id,
    agentId: 'agent-one',
    propertyName: id,
    location: location,
    normalizedLocation: location.toLowerCase(),
    monthlyRent: rent,
    bedrooms: 2,
    bathrooms: 1,
    propertyType: PropertyType.apartment,
    description: 'A searchable property for international student testing.',
    facilities: const ['Wi-Fi'],
    imageUrls: const [],
    approvalStatus: status,
    ratingAverage: rating,
    ratingCount: 3,
    createdAt: DateTime(2026, 8),
    updatedAt: updatedAt,
  );
}
