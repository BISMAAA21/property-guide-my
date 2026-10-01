import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_guidance/features/administration/application/user_management_providers.dart';
import 'package:property_guidance/features/administration/data/unavailable_user_management_repository.dart';
import 'package:property_guidance/features/auth/application/auth_controller.dart';
import 'package:property_guidance/features/auth/domain/app_user.dart';
import 'package:property_guidance/features/auth/domain/auth_repository.dart';
import 'package:property_guidance/features/auth/domain/auth_snapshot.dart';
import 'package:property_guidance/features/auth/domain/user_role.dart';
import 'package:property_guidance/features/properties/application/property_providers.dart';
import 'package:property_guidance/features/properties/data/unavailable_property_repository.dart';
import 'package:property_guidance/features/properties/domain/property_listing.dart';
import 'package:property_guidance/features/properties/presentation/student_property_detail_screen.dart';
import 'package:property_guidance/features/reviews/application/review_providers.dart';
import 'package:property_guidance/features/reviews/data/unavailable_review_repository.dart';
import 'package:property_guidance/features/reviews/domain/property_review.dart';

void main() {
  testWidgets('student details contain listing, agent, workflow, and reviews', (
    tester,
  ) async {
    const student = AppUser(
      uid: 'student-one',
      name: 'Student One',
      email: 'student@example.test',
      role: UserRole.student,
      status: AccountStatus.active,
    );
    const agent = AppUser(
      uid: 'agent-one',
      name: 'Agent One',
      email: 'agent@example.test',
      role: UserRole.agent,
      status: AccountStatus.active,
      agencyName: 'Student Homes Agency',
      phone: '+60 12 345 6789',
      registrationNumber: 'REA-12345',
    );
    final auth = AuthController(const _DetailAuthRepository(student));
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWithValue(auth),
          propertyRepositoryProvider.overrideWithValue(
            _DetailPropertyRepository(_property),
          ),
          userManagementRepositoryProvider.overrideWithValue(
            const _DetailUserRepository(agent),
          ),
          reviewRepositoryProvider.overrideWithValue(
            const _DetailReviewRepository(),
          ),
        ],
        child: const MaterialApp(
          home: StudentPropertyDetailScreen(propertyId: 'property-one'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Cyberjaya Student Suite'), findsOneWidget);
    expect(find.text('Cyberjaya, Selangor'), findsOneWidget);
    expect(find.text('RM 1450 monthly'), findsOneWidget);
    expect(find.text('2 bedrooms'), findsOneWidget);
    expect(find.text('1 bathrooms'), findsOneWidget);
    expect(
      find.text('A furnished apartment near university transport.'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('agent_information_card')),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Agent One'), findsOneWidget);
    expect(find.text('Student Homes Agency'), findsOneWidget);
    expect(find.text('Registration REA-12345'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('guided_inspection_button')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('verify_property_button')), findsOneWidget);
    expect(find.byKey(const Key('damage_detection_button')), findsOneWidget);
    expect(find.byKey(const Key('guided_inspection_button')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('reviews_empty_state')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('write_review_button')), findsOneWidget);
  });
}

final _property = PropertyListing(
  id: 'property-one',
  agentId: 'agent-one',
  propertyName: 'Cyberjaya Student Suite',
  location: 'Cyberjaya, Selangor',
  normalizedLocation: 'cyberjaya, selangor',
  monthlyRent: 1450,
  bedrooms: 2,
  bathrooms: 1,
  propertyType: PropertyType.apartment,
  description: 'A furnished apartment near university transport.',
  facilities: const ['Wi-Fi', 'Study room'],
  imageUrls: const [],
  approvalStatus: PropertyApprovalStatus.approved,
  ratingAverage: 4.5,
  ratingCount: 2,
  createdAt: DateTime(2026, 8),
  updatedAt: DateTime(2026, 8, 12),
);

class _DetailPropertyRepository extends UnavailablePropertyRepository {
  const _DetailPropertyRepository(this.property);

  final PropertyListing property;

  @override
  Stream<PropertyListing?> watchListing(String propertyId) =>
      Stream.value(property);
}

class _DetailUserRepository extends UnavailableUserManagementRepository {
  const _DetailUserRepository(this.agent);

  final AppUser agent;

  @override
  Stream<AppUser?> watchUser(String uid) => Stream.value(agent);
}

class _DetailReviewRepository extends UnavailableReviewRepository {
  const _DetailReviewRepository();

  @override
  Stream<List<PropertyReview>> watchPropertyReviews(String propertyId) =>
      Stream.value(const []);
}

class _DetailAuthRepository implements AuthRepository {
  const _DetailAuthRepository(this.user);

  final AppUser user;

  @override
  Stream<AuthSnapshot> watchSession() =>
      Stream.value(AuthSnapshot.authenticated(user));

  @override
  Future<void> registerStudent({
    required String name,
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}
