import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:property_guidance/features/damage_detection/application/damage_detection_providers.dart';
import 'package:property_guidance/features/damage_detection/data/unavailable_damage_detection_repository.dart';
import 'package:property_guidance/features/damage_detection/domain/damage_detection_result.dart';
import 'package:property_guidance/features/inspections/application/inspection_providers.dart';
import 'package:property_guidance/features/inspections/data/unavailable_inspection_repository.dart';
import 'package:property_guidance/features/inspections/domain/inspection_checklist.dart';
import 'package:property_guidance/features/inspections/domain/property_inspection.dart';
import 'package:property_guidance/features/inspections/presentation/damage_handoff_screen.dart';
import 'package:property_guidance/features/inspections/presentation/inspection_checklist_screen.dart';
import 'package:property_guidance/features/inspections/presentation/inspection_home_screen.dart';
import 'package:property_guidance/features/inspections/presentation/inspection_summary_screen.dart';
import 'package:property_guidance/features/properties/application/property_providers.dart';
import 'package:property_guidance/features/properties/data/unavailable_property_repository.dart';
import 'package:property_guidance/features/properties/domain/property_listing.dart';

void main() {
  testWidgets('student starts a new inspection and reaches its checklist', (
    tester,
  ) async {
    final repository = _InspectionFake(null);
    final router = GoRouter(
      initialLocation: '/inspection',
      routes: [
        GoRoute(
          path: '/inspection',
          builder: (_, _) =>
              const InspectionHomeScreen(propertyId: 'property-one'),
        ),
        GoRoute(
          path: '/student/properties/property-one/inspection/property-one_student-one',
          builder: (_, _) =>
              const Scaffold(body: Text('Checklist route reached')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await _pumpRouter(tester, router, repository);

    expect(find.text('Living room'), findsOneWidget);
    expect(find.text('Safety'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('start_inspection_button')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('start_inspection_button')));
    await tester.pumpAndSettle();

    expect(repository.startCalls, 1);
    expect(find.text('Checklist route reached'), findsOneWidget);
  });

  testWidgets('student sees persisted progress and can resume', (tester) async {
    final findings = PropertyInspection.emptyFindings();
    findings[0] = findings[0].copyWith(
      state: InspectionFindingState.concern,
      note: 'Saved concern',
    );
    findings[1] = findings[1].copyWith(
      state: InspectionFindingState.satisfactory,
    );
    final repository = _InspectionFake(_inspection(findings: findings));
    final router = GoRouter(
      initialLocation: '/inspection',
      routes: [
        GoRoute(
          path: '/inspection',
          builder: (_, _) =>
              const InspectionHomeScreen(propertyId: 'property-one'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await _pumpRouter(tester, router, repository);

    expect(find.byKey(const Key('resume_inspection_card')), findsOneWidget);
    expect(find.text('2 of 18 checks saved'), findsOneWidget);
    expect(find.text('1 concerns recorded'), findsOneWidget);
    expect(find.byKey(const Key('resume_inspection_button')), findsOneWidget);
  });

  testWidgets('editing a checklist result persists it automatically', (
    tester,
  ) async {
    final repository = _InspectionFake(
      _inspection(findings: PropertyInspection.emptyFindings()),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inspectionRepositoryProvider.overrideWithValue(repository),
          damageDetectionRepositoryProvider.overrideWithValue(
            const _DamageHistoryFake(),
          ),
        ],
        child: const MaterialApp(
          home: InspectionChecklistScreen(
            propertyId: 'property-one',
            inspectionId: 'property-one_student-one',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    await tester.tap(
      find.byKey(const Key('inspection_check_living_walls_ceiling')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inspection_state_field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Looks satisfactory').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('inspection_note_field')),
      'Walls checked during the visit.',
    );
    await tester.tap(find.byKey(const Key('save_inspection_finding_button')));
    await tester.pumpAndSettle();

    expect(repository.savedFinding?.state, InspectionFindingState.satisfactory);
    expect(repository.savedFinding?.note, 'Walls checked during the visit.');
    expect(
      find.textContaining('1 of 18 checks saved automatically'),
      findsOneWidget,
    );
  });

  testWidgets('completed summary groups concern and preserves damage context', (
    tester,
  ) async {
    final findings = PropertyInspection.emptyFindings()
        .map(
          (finding) =>
              finding.copyWith(state: InspectionFindingState.satisfactory),
        )
        .toList();
    findings[0] = findings[0].copyWith(
      state: InspectionFindingState.concern,
      note: 'Possible damp mark.',
      concernImagePath:
          'students/student-one/inspections/property-one_student-one/damp.jpg',
      concernImageUrl: 'https://example.test/damp.jpg',
    );
    final repository = _InspectionFake(
      _inspection(findings: findings, status: InspectionStatus.completed),
    );
    final router = GoRouter(
      initialLocation: '/summary',
      routes: [
        GoRoute(
          path: '/summary',
          builder: (_, _) => const InspectionSummaryScreen(
            propertyId: 'property-one',
            inspectionId: 'property-one_student-one',
          ),
        ),
        GoRoute(
          path:
              '/student/properties/:propertyId/inspection/:inspectionId/damage',
          builder: (_, state) => DamageHandoffScreen(
            propertyId: state.pathParameters['propertyId']!,
            inspectionId: state.pathParameters['inspectionId']!,
            checkId: state.uri.queryParameters['checkId'] ?? '',
            photoPath: state.uri.queryParameters['photoPath'] ?? '',
            photoUrl: state.uri.queryParameters['photoUrl'] ?? '',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inspectionRepositoryProvider.overrideWithValue(repository),
          damageDetectionRepositoryProvider.overrideWithValue(
            const _DamageHistoryFake(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('18 checks completed • 1 concerns'), findsOneWidget);
    expect(
      find.byKey(const Key('summary_section_living_room')),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const Key('damage_handoff_living_walls_ceiling')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('damage_handoff_living_walls_ceiling')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Damage detection'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('damage_handoff_context')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('damage_handoff_context')), findsOneWidget);
    expect(find.textContaining('property-one_student-one'), findsOneWidget);
  });
}

Future<void> _pumpRouter(
  WidgetTester tester,
  GoRouter router,
  _InspectionFake inspectionRepository,
) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        propertyRepositoryProvider.overrideWithValue(const _PropertyFake()),
        inspectionRepositoryProvider.overrideWithValue(inspectionRepository),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

final _property = PropertyListing(
  id: 'property-one',
  agentId: 'agent-one',
  propertyName: 'Inspection Test Residence',
  location: 'Cyberjaya, Selangor',
  normalizedLocation: 'cyberjaya, selangor',
  monthlyRent: 1400,
  bedrooms: 2,
  bathrooms: 1,
  propertyType: PropertyType.apartment,
  description: 'An approved property used for guided inspection tests.',
  facilities: const ['Wi-Fi'],
  imageUrls: const [],
  approvalStatus: PropertyApprovalStatus.approved,
  ratingAverage: 4,
  ratingCount: 2,
  createdAt: DateTime(2026, 8, 17),
  updatedAt: DateTime(2026, 8, 17),
);

PropertyInspection _inspection({
  required List<InspectionFinding> findings,
  InspectionStatus status = InspectionStatus.inProgress,
}) {
  return PropertyInspection(
    id: 'property-one_student-one',
    studentId: 'student-one',
    propertyId: 'property-one',
    propertyName: _property.propertyName,
    checklistVersion: InspectionChecklist.version,
    status: status,
    findings: findings,
    startedAt: DateTime(2026, 8, 17),
    updatedAt: DateTime(2026, 8, 17),
    completedAt: status == InspectionStatus.completed
        ? DateTime(2026, 8, 17)
        : null,
  );
}

class _PropertyFake extends UnavailablePropertyRepository {
  const _PropertyFake();

  @override
  Stream<PropertyListing?> watchListing(String propertyId) =>
      Stream.value(_property);
}

class _InspectionFake extends UnavailableInspectionRepository {
  _InspectionFake(this.current) {
    controller = StreamController<PropertyInspection?>.broadcast(
      onListen: () => controller.add(current),
    );
  }

  PropertyInspection? current;
  late final StreamController<PropertyInspection?> controller;
  int startCalls = 0;
  InspectionFinding? savedFinding;

  @override
  Stream<PropertyInspection?> watchPropertyInspection(String propertyId) =>
      controller.stream;

  @override
  Stream<PropertyInspection?> watchInspection(String inspectionId) =>
      controller.stream;

  @override
  Future<String> startOrResume({
    required String propertyId,
    required String propertyName,
  }) async {
    startCalls += 1;
    return 'property-one_student-one';
  }

  @override
  Future<void> saveFinding({
    required String inspectionId,
    required InspectionFinding finding,
  }) async {
    savedFinding = finding;
    final stored = current!;
    final nextFindings = stored.findings
        .map((item) => item.checkId == finding.checkId ? finding : item)
        .toList(growable: false);
    current = PropertyInspection(
      id: stored.id,
      studentId: stored.studentId,
      propertyId: stored.propertyId,
      propertyName: stored.propertyName,
      checklistVersion: stored.checklistVersion,
      status: stored.status,
      findings: nextFindings,
      startedAt: stored.startedAt,
      updatedAt: DateTime(2026, 8, 17),
      completedAt: stored.completedAt,
    );
    controller.add(current);
  }

  @override
  Future<String> uploadConcernPhoto({
    required String inspectionId,
    required String checkId,
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async => 'https://example.test/photo.jpg';
}

class _DamageHistoryFake extends UnavailableDamageDetectionRepository {
  const _DamageHistoryFake();

  @override
  Stream<List<DamageReport>> watchReports(String propertyId) =>
      Stream.value(const []);
}
