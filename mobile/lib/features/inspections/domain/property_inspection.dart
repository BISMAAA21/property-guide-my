import 'inspection_checklist.dart';

enum InspectionStatus {
  inProgress,
  completed;

  String get storedValue => switch (this) {
    InspectionStatus.inProgress => 'in_progress',
    InspectionStatus.completed => 'completed',
  };

  String get displayName => switch (this) {
    InspectionStatus.inProgress => 'In progress',
    InspectionStatus.completed => 'Completed',
  };

  static InspectionStatus? fromStoredValue(Object? value) => switch (value) {
    'in_progress' => InspectionStatus.inProgress,
    'completed' => InspectionStatus.completed,
    _ => null,
  };
}

enum InspectionFindingState {
  notChecked,
  satisfactory,
  concern,
  notApplicable;

  String get storedValue => switch (this) {
    InspectionFindingState.notChecked => 'not_checked',
    InspectionFindingState.satisfactory => 'satisfactory',
    InspectionFindingState.concern => 'concern',
    InspectionFindingState.notApplicable => 'not_applicable',
  };

  String get displayName => switch (this) {
    InspectionFindingState.notChecked => 'Not checked',
    InspectionFindingState.satisfactory => 'Looks satisfactory',
    InspectionFindingState.concern => 'Concern found',
    InspectionFindingState.notApplicable => 'Not applicable',
  };

  bool get isAnswered => this != InspectionFindingState.notChecked;

  static InspectionFindingState? fromStoredValue(Object? value) =>
      switch (value) {
        'not_checked' => InspectionFindingState.notChecked,
        'satisfactory' => InspectionFindingState.satisfactory,
        'concern' => InspectionFindingState.concern,
        'not_applicable' => InspectionFindingState.notApplicable,
        _ => null,
      };
}

class InspectionFinding {
  const InspectionFinding({
    required this.checkId,
    required this.sectionId,
    required this.state,
    required this.note,
    this.concernImagePath,
    this.concernImageUrl,
  });

  factory InspectionFinding.empty(InspectionChecklistItem item) =>
      InspectionFinding(
        checkId: item.id,
        sectionId: item.sectionId,
        state: InspectionFindingState.notChecked,
        note: '',
      );

  final String checkId;
  final String sectionId;
  final InspectionFindingState state;
  final String note;
  final String? concernImagePath;
  final String? concernImageUrl;

  bool get hasConcernPhoto =>
      concernImagePath != null && concernImageUrl != null;

  String? validate() {
    final item = InspectionChecklist.itemById(checkId);
    if (item == null || item.sectionId != sectionId) {
      return 'The inspection check is not part of the current checklist.';
    }
    if (note.trim().length > 1000) {
      return 'Keep inspection notes within 1000 characters.';
    }
    if ((concernImagePath == null) != (concernImageUrl == null)) {
      return 'Concern photo information is incomplete.';
    }
    if (hasConcernPhoto && state != InspectionFindingState.concern) {
      return 'A concern photo can be attached only to a concern.';
    }
    return null;
  }

  InspectionFinding copyWith({
    InspectionFindingState? state,
    String? note,
    String? concernImagePath,
    String? concernImageUrl,
    bool clearConcernPhoto = false,
  }) {
    return InspectionFinding(
      checkId: checkId,
      sectionId: sectionId,
      state: state ?? this.state,
      note: note ?? this.note,
      concernImagePath: clearConcernPhoto
          ? null
          : concernImagePath ?? this.concernImagePath,
      concernImageUrl: clearConcernPhoto
          ? null
          : concernImageUrl ?? this.concernImageUrl,
    );
  }
}

class PropertyInspection {
  const PropertyInspection({
    required this.id,
    required this.studentId,
    required this.propertyId,
    required this.propertyName,
    required this.checklistVersion,
    required this.status,
    required this.findings,
    required this.startedAt,
    required this.updatedAt,
    this.completedAt,
  });

  final String id;
  final String studentId;
  final String propertyId;
  final String propertyName;
  final String checklistVersion;
  final InspectionStatus status;
  final List<InspectionFinding> findings;
  final DateTime? startedAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;

  int get answeredCount =>
      findings.where((finding) => finding.state.isAnswered).length;
  int get totalCount => InspectionChecklist.items.length;
  int get concernCount => findings
      .where((finding) => finding.state == InspectionFindingState.concern)
      .length;
  double get progress => totalCount == 0 ? 0 : answeredCount / totalCount;
  bool get canComplete =>
      status == InspectionStatus.inProgress &&
      findings.length == totalCount &&
      findings.every((finding) => finding.state.isAnswered);

  InspectionFinding findingFor(String checkId) =>
      findings.firstWhere((finding) => finding.checkId == checkId);

  List<InspectionSectionSummary> get sectionSummaries => InspectionChecklist
      .sections
      .map((section) {
        final sectionFindings = section.items
            .map((item) => findingFor(item.id))
            .toList(growable: false);
        return InspectionSectionSummary(
          section: section,
          findings: sectionFindings,
        );
      })
      .toList(growable: false);

  static List<InspectionFinding> emptyFindings() => InspectionChecklist.items
      .map(InspectionFinding.empty)
      .toList(growable: false);
}

class InspectionSectionSummary {
  const InspectionSectionSummary({
    required this.section,
    required this.findings,
  });

  final InspectionChecklistSection section;
  final List<InspectionFinding> findings;

  int get concernCount => findings
      .where((finding) => finding.state == InspectionFindingState.concern)
      .length;
  int get satisfactoryCount => findings
      .where((finding) => finding.state == InspectionFindingState.satisfactory)
      .length;
  int get notApplicableCount => findings
      .where((finding) => finding.state == InspectionFindingState.notApplicable)
      .length;
}
