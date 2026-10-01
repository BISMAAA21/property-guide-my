import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_guidance/features/auth/application/auth_controller.dart';
import 'package:property_guidance/features/auth/domain/app_user.dart';
import 'package:property_guidance/features/auth/domain/auth_repository.dart';
import 'package:property_guidance/features/auth/domain/auth_snapshot.dart';
import 'package:property_guidance/features/auth/domain/user_role.dart';
import 'package:property_guidance/features/properties/application/property_providers.dart';
import 'package:property_guidance/features/properties/data/unavailable_property_repository.dart';
import 'package:property_guidance/features/properties/domain/property_failure.dart';
import 'package:property_guidance/features/properties/domain/property_listing.dart';
import 'package:property_guidance/features/properties/presentation/student_property_search_screen.dart';

void main() {
  testWidgets('student discovery shows only approved properties and searches', (
    tester,
  ) async {
    final repository = _SearchPropertyRepository([
      _property(
        id: 'cyberjaya-suite',
        status: PropertyApprovalStatus.approved,
        location: 'Cyberjaya, Selangor',
      ),
      _property(
        id: 'kl-room',
        status: PropertyApprovalStatus.approved,
        location: 'Kuala Lumpur',
      ),
      _property(
        id: 'private-draft',
        status: PropertyApprovalStatus.draft,
        location: 'Cyberjaya, Selangor',
      ),
    ]);
    await _pump(tester, repository);

    expect(find.text('2 approved properties'), findsOneWidget);
    expect(find.text('cyberjaya-suite'), findsOneWidget);
    expect(find.text('private-draft'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('property_search_field')),
      'Kuala Lumpur',
    );
    await tester.pump();
    expect(find.text('1 approved property'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('kl-room'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('cyberjaya-suite'), findsNothing);
    expect(find.text('kl-room'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('property_search_field')),
      'No matching home',
    );
    await tester.pump();
    expect(find.byKey(const Key('property_empty_state')), findsOneWidget);
  });

  testWidgets('student can apply a location filter', (tester) async {
    await _pump(
      tester,
      _SearchPropertyRepository([
        _property(
          id: 'cyberjaya-suite',
          status: PropertyApprovalStatus.approved,
          location: 'Cyberjaya, Selangor',
        ),
        _property(
          id: 'kl-room',
          status: PropertyApprovalStatus.approved,
          location: 'Kuala Lumpur',
        ),
      ]),
    );

    await tester.tap(find.byKey(const Key('property_filter_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('location_filter_field')),
      'Cyberjaya',
    );
    await tester.tap(find.byKey(const Key('apply_property_filters')));
    await tester.pumpAndSettle();

    expect(find.text('cyberjaya-suite'), findsOneWidget);
    expect(find.text('kl-room'), findsNothing);
    expect(find.text('Filters applied'), findsOneWidget);
  });

  testWidgets('approved-property query failure is explained to the student', (
    tester,
  ) async {
    await _pump(tester, const _SearchPropertyRepository.failure());

    expect(find.textContaining('Search query unavailable'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  _SearchPropertyRepository propertyRepository,
) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  const user = AppUser(
    uid: 'student-one',
    name: 'Student One',
    email: 'student@example.test',
    role: UserRole.student,
    status: AccountStatus.active,
  );
  final auth = AuthController(const _StudentAuthRepository(user));
  addTearDown(auth.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWithValue(auth),
        propertyRepositoryProvider.overrideWithValue(propertyRepository),
      ],
      child: const MaterialApp(home: StudentPropertySearchScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

PropertyListing _property({
  required String id,
  required PropertyApprovalStatus status,
  required String location,
}) {
  return PropertyListing(
    id: id,
    agentId: 'agent-one',
    propertyName: id,
    location: location,
    normalizedLocation: location.toLowerCase(),
    monthlyRent: id == 'kl-room' ? 900 : 1400,
    bedrooms: 2,
    bathrooms: 1,
    propertyType: PropertyType.apartment,
    description: 'A complete property description for discovery testing.',
    facilities: const ['Wi-Fi'],
    imageUrls: const [],
    approvalStatus: status,
    ratingAverage: 4.2,
    ratingCount: 3,
    createdAt: DateTime(2026, 8),
    updatedAt: DateTime(2026, 8, 10),
  );
}

class _SearchPropertyRepository extends UnavailablePropertyRepository {
  const _SearchPropertyRepository(this.properties) : error = null;

  const _SearchPropertyRepository.failure()
    : properties = const [],
      error = 'Search query unavailable';

  final List<PropertyListing> properties;
  final String? error;

  @override
  Stream<List<PropertyListing>> watchApprovedListings() {
    if (error case final message?) {
      return Stream.error(PropertyFailure('query-unavailable', message));
    }
    return Stream.value(properties);
  }
}

class _StudentAuthRepository implements AuthRepository {
  const _StudentAuthRepository(this.user);

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
