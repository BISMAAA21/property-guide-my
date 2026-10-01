import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_guidance/app/app.dart';
import 'package:property_guidance/app/bootstrap.dart';
import 'package:property_guidance/features/auth/application/auth_controller.dart';
import 'package:property_guidance/features/auth/domain/app_user.dart';
import 'package:property_guidance/features/auth/domain/auth_repository.dart';
import 'package:property_guidance/features/auth/domain/auth_snapshot.dart';
import 'package:property_guidance/features/auth/domain/user_role.dart';
import 'package:property_guidance/features/administration/application/user_management_providers.dart';
import 'package:property_guidance/features/administration/data/unavailable_user_management_repository.dart';
import 'package:property_guidance/features/administration/domain/user_management_repository.dart';
import 'package:property_guidance/features/agreements/application/agreement_providers.dart';
import 'package:property_guidance/features/agreements/data/unavailable_agreement_repository.dart';
import 'package:property_guidance/features/damage_detection/application/damage_detection_providers.dart';
import 'package:property_guidance/features/damage_detection/data/unavailable_damage_detection_repository.dart';
import 'package:property_guidance/features/image_verification/application/image_verification_providers.dart';
import 'package:property_guidance/features/image_verification/data/unavailable_image_verification_repository.dart';
import 'package:property_guidance/features/inspections/application/inspection_providers.dart';
import 'package:property_guidance/features/inspections/data/unavailable_inspection_repository.dart';
import 'package:property_guidance/features/properties/application/property_providers.dart';
import 'package:property_guidance/features/properties/data/unavailable_property_repository.dart';
import 'package:property_guidance/features/properties/domain/property_listing.dart';
import 'package:property_guidance/features/properties/domain/property_repository.dart';
import 'package:property_guidance/features/reviews/application/review_providers.dart';
import 'package:property_guidance/features/reviews/data/unavailable_review_repository.dart';

void main() {
  testWidgets('signed-out users reach login', (tester) async {
    final repository = FakeAuthRepository(const AuthSnapshot.signedOut());
    await _pumpApp(tester, repository);
    expect(find.text('Welcome back'), findsOneWidget);
  });

  for (final role in UserRole.values) {
    testWidgets('${role.name} reaches only its role dashboard', (tester) async {
      final repository = FakeAuthRepository(
        AuthSnapshot.authenticated(_userFor(role)),
      );
      await _pumpApp(tester, repository);
      expect(find.text(_titleFor(role)), findsOneWidget);
      for (final otherRole in UserRole.values.where((item) => item != role)) {
        expect(find.text(_titleFor(otherRole)), findsNothing);
      }
    });
  }

  testWidgets('disabled account is denied application access', (tester) async {
    final repository = FakeAuthRepository(
      AuthSnapshot.disabled(_userFor(UserRole.student)),
    );
    await _pumpApp(tester, repository);
    expect(find.text('Account disabled'), findsOneWidget);
    expect(find.text('Student Home'), findsNothing);
  });

  testWidgets('missing profile is denied application access', (tester) async {
    final repository = FakeAuthRepository(const AuthSnapshot.missingProfile());
    await _pumpApp(tester, repository);
    expect(find.text('Account setup incomplete'), findsOneWidget);
  });

  testWidgets('student dashboard opens the agreement module', (tester) async {
    final repository = FakeAuthRepository(
      AuthSnapshot.authenticated(_userFor(UserRole.student)),
    );
    await _pumpApp(tester, repository);

    await tester.tap(find.byKey(const Key('open_agreements_button')));
    await tester.pumpAndSettle();

    expect(find.text('Tenancy agreement simplification'), findsOneWidget);
    expect(find.byKey(const Key('agreement_privacy_consent')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Find a home'), findsOneWidget);
  });

  testWidgets('agent can return from profile to the workspace', (tester) async {
    final repository = FakeAuthRepository(
      AuthSnapshot.authenticated(_userFor(UserRole.agent)),
    );
    await _pumpApp(tester, repository);

    await tester.tap(find.byTooltip('Edit agent profile'));
    await tester.pumpAndSettle();
    expect(find.text('Agent profile'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Agent Workspace'), findsOneWidget);
  });

  testWidgets('administrator can return from review to administration', (
    tester,
  ) async {
    final admin = _userFor(UserRole.admin);
    final repository = FakeAuthRepository(AuthSnapshot.authenticated(admin));
    final listing = _approvedListing();
    await _pumpApp(
      tester,
      repository,
      propertyRepository: ConnectedPropertyRepository(listing),
      userManagementRepository: ConnectedUserManagementRepository(admin),
    );

    await tester.tap(find.text(listing.propertyName));
    await tester.pumpAndSettle();
    expect(find.text('Review property'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Administration'), findsOneWidget);
  });

  testWidgets(
    'successful sign out reaches login before a repository snapshot arrives',
    (tester) async {
      final repository = FakeAuthRepository(
        AuthSnapshot.authenticated(_userFor(UserRole.student)),
        emitSignedOutSnapshot: false,
      );
      await _pumpApp(tester, repository);

      await tester.tap(find.byTooltip('Sign out'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Account unavailable'), findsNothing);
    },
  );

  testWidgets(
    'student property journey connects every required visual module',
    (tester) async {
      final repository = FakeAuthRepository(
        AuthSnapshot.authenticated(_userFor(UserRole.student)),
      );
      final listing = _approvedListing();
      await _pumpApp(
        tester,
        repository,
        propertyRepository: ConnectedPropertyRepository(listing),
      );

      await tester.tap(find.byKey(Key('student_property_${listing.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Property details'), findsOneWidget);

      await _expectConnectedRoute(
        tester,
        buttonKey: 'verify_property_button',
        expectedTitle: 'Image verification',
      );
      await _expectConnectedRoute(
        tester,
        buttonKey: 'damage_detection_button',
        expectedTitle: 'Damage detection',
      );
      await _expectConnectedRoute(
        tester,
        buttonKey: 'guided_inspection_button',
        expectedTitle: 'Guided inspection',
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Find a home'), findsOneWidget);
    },
  );
}

Future<void> _pumpApp(
  WidgetTester tester,
  AuthRepository repository, {
  PropertyRepository propertyRepository = const UnavailablePropertyRepository(),
  UserManagementRepository userManagementRepository =
      const UnavailableUserManagementRepository(),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseBootstrapProvider.overrideWithValue(
          const FirebaseBootstrapResult.ready(),
        ),
        authRepositoryProvider.overrideWithValue(repository),
        propertyRepositoryProvider.overrideWithValue(propertyRepository),
        userManagementRepositoryProvider.overrideWithValue(
          userManagementRepository,
        ),
        agreementRepositoryProvider.overrideWithValue(
          const UnavailableAgreementRepository(),
        ),
        imageVerificationRepositoryProvider.overrideWithValue(
          const UnavailableImageVerificationRepository(),
        ),
        damageDetectionRepositoryProvider.overrideWithValue(
          const UnavailableDamageDetectionRepository(),
        ),
        inspectionRepositoryProvider.overrideWithValue(
          const UnavailableInspectionRepository(),
        ),
        reviewRepositoryProvider.overrideWithValue(
          const UnavailableReviewRepository(),
        ),
      ],
      child: const PropertyGuidanceApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expectConnectedRoute(
  WidgetTester tester, {
  required String buttonKey,
  required String expectedTitle,
}) async {
  final button = find.byKey(Key(buttonKey));
  if (button.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      button,
      300,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await Scrollable.ensureVisible(tester.element(button), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.text(expectedTitle), findsOneWidget);
  await tester.pageBack();
  await tester.pumpAndSettle();
  expect(find.text('Property details'), findsOneWidget);
}

PropertyListing _approvedListing() => PropertyListing(
  id: 'connected-home',
  agentId: 'agent-uid',
  propertyName: 'Connected Student Residence',
  location: 'Kuala Lumpur',
  normalizedLocation: 'kuala lumpur',
  monthlyRent: 1500,
  bedrooms: 2,
  bathrooms: 1,
  propertyType: PropertyType.apartment,
  description: 'A controlled approved listing used to verify connected routes.',
  facilities: const ['Wi-Fi'],
  imageUrls: const [],
  approvalStatus: PropertyApprovalStatus.approved,
  ratingAverage: 0,
  ratingCount: 0,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

AppUser _userFor(UserRole role) => AppUser(
  uid: '${role.name}-uid',
  name: role.displayName,
  email: '${role.name}@example.test',
  role: role,
  status: AccountStatus.active,
);

String _titleFor(UserRole role) => switch (role) {
  UserRole.student => 'Find a home',
  UserRole.agent => 'Agent Workspace',
  UserRole.admin => 'Administration',
};

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository(this._initial, {this.emitSignedOutSnapshot = true});

  final AuthSnapshot _initial;
  final bool emitSignedOutSnapshot;
  final _controller = StreamController<AuthSnapshot>.broadcast();

  @override
  Stream<AuthSnapshot> watchSession() async* {
    yield _initial;
    yield* _controller.stream;
  }

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
  Future<void> signOut() async {
    if (emitSignedOutSnapshot) {
      _controller.add(const AuthSnapshot.signedOut());
    }
  }
}

class ConnectedPropertyRepository extends UnavailablePropertyRepository {
  ConnectedPropertyRepository(this.listing);

  final PropertyListing listing;

  @override
  Stream<List<PropertyListing>> watchApprovedListings() =>
      Stream.value([listing]);

  @override
  Stream<List<PropertyListing>> watchAllListings() => Stream.value([listing]);

  @override
  Stream<PropertyListing?> watchListing(String propertyId) =>
      Stream.value(propertyId == listing.id ? listing : null);
}

class ConnectedUserManagementRepository
    extends UnavailableUserManagementRepository {
  const ConnectedUserManagementRepository(this.user);

  final AppUser user;

  @override
  Stream<List<AppUser>> watchUsers() => Stream.value([user]);
}
