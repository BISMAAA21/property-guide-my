import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:property_guidance/features/damage_detection/application/damage_detection_providers.dart';
import 'package:property_guidance/features/damage_detection/data/unavailable_damage_detection_repository.dart';
import 'package:property_guidance/features/damage_detection/domain/damage_detection_repository.dart';
import 'package:property_guidance/features/damage_detection/domain/damage_detection_result.dart';
import 'package:property_guidance/features/damage_detection/presentation/damage_detection_screen.dart';

void main() {
  testWidgets(
    'student uploads a photo and receives cautious mold observation',
    (tester) async {
      final repository = _DamageFake();
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      await _pumpScreen(
        tester,
        repository,
        DamageDetectionScreen(
          propertyId: 'property-one',
          pickDamageImage: () async =>
              XFile.fromData(bytes, name: 'damage.jpg', mimeType: 'image/jpeg'),
        ),
      );

      await tester.tap(find.byKey(const Key('choose_damage_image_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.byKey(const Key('damage_image_preview')), findsOneWidget);
      await tester.tap(find.byKey(const Key('run_damage_detection_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.scrollUntilVisible(
        find.byKey(const Key('damage_detection_result_card')),
        400,
        scrollable: find.byType(Scrollable).first,
      );

      final uploadedSource = repository.lastSource as UploadedDamagePhoto;
      expect(uploadedSource.contentType, 'image/png');
      expect(find.text('Possible mold'), findsOneWidget);
      expect(find.text('Model confidence 83.0%'), findsOneWidget);
      expect(find.byKey(const Key('damage_recommendation')), findsOneWidget);
      expect(find.byKey(const Key('damage_disclaimer')), findsOneWidget);
      expect(find.textContaining('diagnosed'), findsNothing);
    },
  );

  testWidgets('Guided Inspection handoff reuses its private concern photo', (
    tester,
  ) async {
    final repository = _DamageFake();
    await _pumpScreen(
      tester,
      repository,
      const DamageDetectionScreen(
        propertyId: 'property-one',
        inspectionId: 'property-one_student-one',
        checkId: 'living_walls_ceiling',
        photoPath: 'students/student-one/inspections/property-one_student-one/concern.jpg',
        photoUrl: 'https://example.test/concern.jpg',
      ),
    );

    expect(find.byKey(const Key('damage_handoff_context')), findsOneWidget);
    expect(find.byKey(const Key('damage_handoff_preview')), findsOneWidget);
    await tester.tap(find.byKey(const Key('run_damage_detection_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final source = repository.lastSource as InspectionDamagePhoto;
    expect(source.inspectionId, 'property-one_student-one');
    expect(source.checkId, 'living_walls_ceiling');
    expect(source.imagePath, contains('/inspections/'));
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _DamageFake repository,
  Widget screen,
) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        damageDetectionRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

class _DamageFake extends UnavailableDamageDetectionRepository {
  _DamageFake();

  DamagePhotoSource? lastSource;

  @override
  Stream<List<DamageReport>> watchReports(String propertyId) =>
      Stream.value(const []);

  @override
  Future<DamageReport> detectDamage({
    required String propertyId,
    required DamagePhotoSource source,
  }) async {
    lastSource = source;
    return DamageReport(
      id: 'damage-report-one',
      studentId: 'student-one',
      propertyId: propertyId,
      imagePath: source is InspectionDamagePhoto
          ? source.imagePath
          : 'students/student-one/damage/damage-report-one/damage.png',
      sourceType: source is InspectionDamagePhoto
          ? DamagePhotoSourceType.inspection
          : DamagePhotoSourceType.upload,
      inspectionId: source is InspectionDamagePhoto
          ? source.inspectionId
          : null,
      checkId: source is InspectionDamagePhoto ? source.checkId : null,
      result: const DamageDetectionResult(
        damageClass: DamageClass.mold,
        modelScore: 0.83,
        recommendation: 'The model noticed features consistent with possible mold growth. Seek professional advice.',
        disclaimer: 'AI-assisted observation only; this does not confirm damage or replace a qualified property inspection.',
        modelId: 'controlled-model',
      ),
      createdAt: DateTime.utc(2026, 8, 17),
    );
  }
}
