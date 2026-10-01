import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_guidance/app/bootstrap.dart';
import 'package:property_guidance/features/administration/application/user_management_providers.dart';
import 'package:property_guidance/features/administration/domain/user_management_repository.dart';
import 'package:property_guidance/features/administration/presentation/admin_dashboard_screen.dart';
import 'package:property_guidance/features/auth/application/auth_controller.dart';
import 'package:property_guidance/features/auth/domain/app_user.dart';
import 'package:property_guidance/features/auth/domain/auth_repository.dart';
import 'package:property_guidance/features/auth/domain/auth_snapshot.dart';
import 'package:property_guidance/features/auth/domain/user_role.dart';
import 'package:property_guidance/features/properties/application/property_providers.dart';
import 'package:property_guidance/features/properties/domain/property_listing.dart';
import 'package:property_guidance/features/properties/domain/property_repository.dart';
import 'package:property_guidance/features/properties/presentation/agent_property_dashboard_screen.dart';

void main() {
  testWidgets('agent dashboard displays owned listings and lifecycle counts', (
    tester,
  ) async {
    final agent = _user('agent-one', UserRole.agent);
    final properties = [
      _property('draft-home', PropertyApprovalStatus.draft),
      _property('pending-home', PropertyApprovalStatus.pending),
      _property('approved-home', PropertyApprovalStatus.approved),
    ];

    await _pump(
      tester,
      user: agent,
      properties: properties,
      users: [agent],
      child: const AgentPropertyDashboardScreen(),
    );

    expect(find.text('Agent Workspace'), findsOneWidget);
    expect(find.text('My listings'), findsOneWidget);
    expect(find.text('draft-home'), findsOneWidget);
    expect(find.text('pending-home'), findsOneWidget);
    expect(find.text('approved-home'), findsOneWidget);
    expect(find.text('Pending review'), findsWidgets);
  });

  testWidgets(
    'admin dashboard shows counts, pending work, and account controls',
    (tester) async {
      final admin = _user('admin-one', UserRole.admin);
      final users = [
        admin,
        _user('agent-one', UserRole.agent),
        _user('student-one', UserRole.student),
      ];
      final properties = [
        _property('pending-home', PropertyApprovalStatus.pending),
        _property('approved-home', PropertyApprovalStatus.approved),
      ];

      await _pump(
        tester,
        user: admin,
        properties: properties,
        users: users,
        child: const AdminDashboardScreen(),
      );

      expect(find.text('Administration'), findsOneWidget);
      expect(find.text('System overview'), findsOneWidget);
      expect(find.text('Pending property approvals'), findsOneWidget);
      expect(find.text('Students'), findsOneWidget);
      expect(find.text('Agents'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('User and agent management'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.scrollUntilVisible(
        find.text('student-one'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('student-one'), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(2));
    },
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required AppUser user,
  required List<PropertyListing> properties,
  required List<AppUser> users,
  required Widget child,
}) async {
  final authController = AuthController(_FakeAuthRepository(user));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseBootstrapProvider.overrideWithValue(
          const FirebaseBootstrapResult.ready(),
        ),
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository(user)),
        authControllerProvider.overrideWithValue(authController),
        propertyRepositoryProvider.overrideWithValue(
          _FakePropertyRepository(properties),
        ),
        userManagementRepositoryProvider.overrideWithValue(
          _FakeUserRepository(users),
        ),
      ],
      child: MaterialApp(home: child),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

AppUser _user(String uid, UserRole role) => AppUser(
  uid: uid,
  name: uid,
  email: '$uid@example.test',
  role: role,
  status: AccountStatus.active,
);

PropertyListing _property(String name, PropertyApprovalStatus status) {
  return PropertyListing(
    id: name,
    agentId: 'agent-one',
    propertyName: name,
    location: 'Cyberjaya, Selangor',
    normalizedLocation: 'cyberjaya, selangor',
    monthlyRent: 1400,
    bedrooms: 2,
    bathrooms: 1,
    propertyType: PropertyType.apartment,
    description: 'A controlled property listing used for dashboard tests.',
    facilities: const ['Wi-Fi'],
    imageUrls: const [],
    approvalStatus: status,
    ratingAverage: 0,
    ratingCount: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

class _FakeAuthRepository implements AuthRepository {
  const _FakeAuthRepository(this.user);

  final AppUser user;

  @override
  Stream<AuthSnapshot> watchSession() {
    late final StreamController<AuthSnapshot> controller;
    controller = StreamController<AuthSnapshot>(
      sync: true,
      onListen: () {
        controller.add(AuthSnapshot.authenticated(user));
        controller.close();
      },
    );
    return controller.stream;
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
  Future<void> signOut() async {}
}

class _FakePropertyRepository implements PropertyRepository {
  const _FakePropertyRepository(this.properties);

  final List<PropertyListing> properties;

  @override
  Stream<List<PropertyListing>> watchAllListings() => Stream.value(properties);

  @override
  Stream<List<PropertyListing>> watchApprovedListings() => Stream.value(
    properties
        .where((item) => item.approvalStatus == PropertyApprovalStatus.approved)
        .toList(),
  );

  @override
  Stream<List<PropertyListing>> watchOwnedListings(String agentId) =>
      Stream.value(
        properties.where((item) => item.agentId == agentId).toList(),
      );

  @override
  Stream<PropertyListing?> watchListing(String propertyId) => Stream.value(
    properties.where((item) => item.id == propertyId).firstOrNull,
  );

  @override
  Future<void> approveListing(String propertyId) => _unsupported();

  @override
  Future<String> createListing(PropertyWriteInput input) => _unsupported();

  @override
  Future<void> deactivateListing(String propertyId) => _unsupported();

  @override
  Future<void> rejectListing(String propertyId, String reason) =>
      _unsupported();

  @override
  Future<void> removeListing(String propertyId) => _unsupported();

  @override
  Future<void> removeListingImage({
    required String propertyId,
    required String imageUrl,
  }) => _unsupported();

  @override
  Future<void> submitForReview(String propertyId) => _unsupported();

  @override
  Future<void> updateListing(String propertyId, PropertyWriteInput input) =>
      _unsupported();

  @override
  Future<String> uploadListingImage({
    required String propertyId,
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) => _unsupported();

  Never _unsupported() => throw UnsupportedError('Not used in dashboard test.');
}

class _FakeUserRepository implements UserManagementRepository {
  const _FakeUserRepository(this.users);

  final List<AppUser> users;

  @override
  Stream<List<AppUser>> watchUsers() => Stream.value(users);

  @override
  Stream<AppUser?> watchUser(String uid) =>
      Stream.value(users.where((user) => user.uid == uid).firstOrNull);

  @override
  Future<void> setAccountStatus(String uid, AccountStatus status) async {}

  @override
  Future<void> updateAgentProfile(AgentProfileInput input) async {}
}
