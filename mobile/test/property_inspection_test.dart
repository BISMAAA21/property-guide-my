import 'package:flutter_test/flutter_test.dart';
import 'package:property_guidance/features/inspections/domain/inspection_checklist.dart';
import 'package:property_guidance/features/inspections/domain/inspection_repository.dart';
import 'package:property_guidance/features/inspections/domain/property_inspection.dart';

void main() {
  group('InspectionChecklist', () {
    test('defines six ordered areas and eighteen stable unique checks', () {
      expect(InspectionChecklist.version, '1.0.0');
      expect(InspectionChecklist.sections.map((section) => section.id), [
        'living_room',
        'bedroom',
        'bathroom',
        'kitchen',
        'utilities',
        'safety',
      ]);
      expect(InspectionChecklist.items, hasLength(18));
      expect(
        InspectionChecklist.items.map((item) => item.id).toSet(),
        hasLength(18),
      );
    });
  });

  group('PropertyInspection', () {
    test('preserves partial results and calculates resumable progress', () {
      final findings = PropertyInspection.emptyFindings();
      final first = findings.first;
      findings[0] = first.copyWith(
        state: InspectionFindingState.satisfactory,
        note: 'Checked during the visit.',
      );
      final inspection = _inspection(findings: findings);

      expect(inspection.answeredCount, 1);
      expect(inspection.progress, closeTo(1 / 18, 0.0001));
      expect(
        inspection.findingFor(first.checkId).note,
        'Checked during the visit.',
      );
      expect(inspection.canComplete, isFalse);
    });

    test('requires every check before completion', () {
      final answered = PropertyInspection.emptyFindings()
          .map(
            (finding) =>
                finding.copyWith(state: InspectionFindingState.satisfactory),
          )
          .toList(growable: false);

      expect(_inspection(findings: answered).canComplete, isTrue);
      expect(
        _inspection(
          findings: answered
              .map(
                (finding) => finding.checkId == answered.last.checkId
                    ? finding.copyWith(state: InspectionFindingState.notChecked)
                    : finding,
              )
              .toList(growable: false),
        ).canComplete,
        isFalse,
      );
    });

    test('groups concerns and photos into the matching room summary', () {
      final findings = PropertyInspection.emptyFindings()
          .map(
            (finding) =>
                finding.copyWith(state: InspectionFindingState.satisfactory),
          )
          .toList();
      findings[0] = findings[0].copyWith(
        state: InspectionFindingState.concern,
        note: 'Possible damp mark near the window.',
        concernImagePath: 'students/student-one/inspections/property-one_student-one/photo.jpg',
        concernImageUrl: 'https://example.test/photo.jpg',
      );
      final inspection = _inspection(
        findings: findings,
        status: InspectionStatus.completed,
      );

      expect(inspection.concernCount, 1);
      expect(inspection.sectionSummaries.first.concernCount, 1);
      expect(
        inspection.sectionSummaries.first.findings.first.hasConcernPhoto,
        isTrue,
      );
      expect(
        inspection.sectionSummaries
            .skip(1)
            .every((summary) => summary.concernCount == 0),
        isTrue,
      );
    });
  });

  group('ConcernPhotoInput', () {
    test('accepts supported uploads and explains photo failures', () {
      expect(
        const ConcernPhotoInput(
          byteLength: 1024,
          contentType: 'image/jpeg',
        ).validate(),
        isNull,
      );
      expect(
        const ConcernPhotoInput(
          byteLength: 0,
          contentType: 'image/jpeg',
        ).validate(),
        'Choose a concern photo smaller than 10 MiB.',
      );
      expect(
        const ConcernPhotoInput(
          byteLength: 1024,
          contentType: 'application/pdf',
        ).validate(),
        'Choose a JPEG, PNG, or WebP concern photo.',
      );
    });
  });
}

PropertyInspection _inspection({
  required List<InspectionFinding> findings,
  InspectionStatus status = InspectionStatus.inProgress,
}) {
  return PropertyInspection(
    id: 'property-one_student-one',
    studentId: 'student-one',
    propertyId: 'property-one',
    propertyName: 'Test Property',
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
