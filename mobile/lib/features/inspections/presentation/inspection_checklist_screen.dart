import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/errors/app_failure.dart';
import '../../../shared/presentation/async_state_widgets.dart';
import '../../../shared/validation/image_content.dart';
import '../../properties/presentation/property_widgets.dart';
import '../application/inspection_providers.dart';
import '../domain/inspection_checklist.dart';
import '../domain/property_inspection.dart';

class InspectionChecklistScreen extends ConsumerStatefulWidget {
  const InspectionChecklistScreen({
    required this.propertyId,
    required this.inspectionId,
    super.key,
  });

  final String propertyId;
  final String inspectionId;

  @override
  ConsumerState<InspectionChecklistScreen> createState() =>
      _InspectionChecklistScreenState();
}

class _InspectionChecklistScreenState
    extends ConsumerState<InspectionChecklistScreen> {
  late final Stream<PropertyInspection?> _inspectionStream;
  final Set<String> _busyChecks = {};
  bool _completing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _inspectionStream = ref
        .read(inspectionRepositoryProvider)
        .watchInspection(widget.inspectionId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Room-by-room checklist')),
      body: StreamBuilder<PropertyInspection?>(
        stream: _inspectionStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AsyncLoadingView(
              label: 'Loading inspection checklist',
            );
          }
          final inspection = snapshot.data;
          if (snapshot.hasError || inspection == null) {
            return AsyncErrorView(
              error: snapshot.error,
              fallback: 'The inspection checklist could not be loaded.',
            );
          }
          if (inspection.status == InspectionStatus.completed) {
            return _CompletedState(
              onViewSummary: () => _openSummary(inspection.id),
            );
          }
          final remaining = inspection.totalCount - inspection.answeredCount;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              inspection.propertyName,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          Text('${(inspection.progress * 100).round()}%'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: inspection.progress),
                      const SizedBox(height: 6),
                      Text(
                        '${inspection.answeredCount} of ${inspection.totalCount} checks saved automatically',
                      ),
                    ],
                  ),
                ),
              ),
              if (_error case final error?) ...[
                const SizedBox(height: 8),
                AsyncFailureCard(message: error),
              ],
              const SizedBox(height: 8),
              ...InspectionChecklist.sections.map(
                (section) => _SectionCard(
                  section: section,
                  inspection: inspection,
                  busyChecks: _busyChecks,
                  onEdit: _editFinding,
                ),
              ),
              const SizedBox(height: 16),
              if (_completing) const LinearProgressIndicator(),
              FilledButton.icon(
                key: const Key('complete_inspection_button'),
                onPressed: inspection.canComplete && !_completing
                    ? () => _complete(inspection)
                    : null,
                icon: const Icon(Icons.task_alt),
                label: const Text('Complete inspection'),
              ),
              if (!inspection.canComplete) ...[
                const SizedBox(height: 6),
                Text(
                  'Answer the remaining $remaining checks before completing.',
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _editFinding(InspectionFinding finding) async {
    if (_busyChecks.contains(finding.checkId)) return;
    final item = InspectionChecklist.itemById(finding.checkId)!;
    final noteController = TextEditingController(text: finding.note);
    var state = finding.state;
    XFile? selectedPhoto;
    String? validationError;
    final result = await showDialog<_FindingEditResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(item.title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(item.guidance),
                const SizedBox(height: 14),
                DropdownButtonFormField<InspectionFindingState>(
                  key: const Key('inspection_state_field'),
                  initialValue: state,
                  decoration: const InputDecoration(
                    labelText: 'Result',
                    border: OutlineInputBorder(),
                  ),
                  items: InspectionFindingState.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.displayName),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      state = value;
                      if (state != InspectionFindingState.concern) {
                        selectedPhoto = null;
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('inspection_note_field'),
                  controller: noteController,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    labelText: 'Optional note',
                    hintText: 'Record details, questions, or agreed follow-up.',
                    border: const OutlineInputBorder(),
                    errorText: validationError,
                  ),
                ),
                if (state == InspectionFindingState.concern) ...[
                  const SizedBox(height: 8),
                  if (selectedPhoto != null)
                    Text('Selected photo: ${selectedPhoto!.name}')
                  else if (finding.hasConcernPhoto)
                    const Text('An existing concern photo is attached.'),
                  OutlinedButton.icon(
                    key: const Key('choose_concern_photo_button'),
                    onPressed: () async {
                      final photo = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 85,
                      );
                      if (photo != null) {
                        setDialogState(() => selectedPhoto = photo);
                      }
                    },
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(
                      finding.hasConcernPhoto
                          ? 'Replace concern photo'
                          : 'Add concern photo',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('save_inspection_finding_button'),
              onPressed: () {
                final next = finding.copyWith(
                  state: state,
                  note: noteController.text,
                  clearConcernPhoto: state != InspectionFindingState.concern,
                );
                final error = next.validate();
                if (error != null) {
                  setDialogState(() => validationError = error);
                  return;
                }
                Navigator.pop(
                  context,
                  _FindingEditResult(finding: next, photo: selectedPhoto),
                );
              },
              child: const Text('Save check'),
            ),
          ],
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      noteController.dispose();
    });
    if (result == null) return;
    await _runForCheck(finding.checkId, () async {
      final repository = ref.read(inspectionRepositoryProvider);
      await repository.saveFinding(
        inspectionId: widget.inspectionId,
        finding: result.finding,
      );
      if (result.photo case final photo?) {
        final bytes = await photo.readAsBytes();
        final fallbackType = photo.mimeType ?? _contentTypeFor(photo.name);
        await repository.uploadConcernPhoto(
          inspectionId: widget.inspectionId,
          checkId: finding.checkId,
          bytes: bytes,
          filename: photo.name,
          contentType: detectSupportedImageContentType(bytes) ?? fallbackType,
        );
      }
    });
  }

  Future<void> _runForCheck(
    String checkId,
    Future<void> Function() action,
  ) async {
    setState(() {
      _busyChecks.add(checkId);
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = userFacingErrorMessage(
            error,
            fallback: 'The checklist change could not be saved.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyChecks.remove(checkId));
    }
  }

  Future<void> _complete(PropertyInspection inspection) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Complete inspection?'),
            content: Text(
              'Your ${inspection.concernCount} recorded concerns will appear in a private summary. Completed checks cannot be edited.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep checking'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Complete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    setState(() {
      _completing = true;
      _error = null;
    });
    try {
      await ref
          .read(inspectionRepositoryProvider)
          .completeInspection(inspection.id);
      if (mounted) _openSummary(inspection.id);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = userFacingErrorMessage(
            error,
            fallback: 'The inspection could not be completed.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  void _openSummary(String inspectionId) {
    context.go(
      '/student/properties/${widget.propertyId}/inspection/$inspectionId/summary',
    );
  }

  static String _contentTypeFor(String filename) {
    final normalized = filename.toLowerCase();
    if (normalized.endsWith('.png')) return 'image/png';
    if (normalized.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.inspection,
    required this.busyChecks,
    required this.onEdit,
  });

  final InspectionChecklistSection section;
  final PropertyInspection inspection;
  final Set<String> busyChecks;
  final ValueChanged<InspectionFinding> onEdit;

  @override
  Widget build(BuildContext context) {
    final findings = section.items
        .map((item) => inspection.findingFor(item.id))
        .toList(growable: false);
    final answered = findings
        .where((finding) => finding.state.isAnswered)
        .length;
    return Card(
      child: ExpansionTile(
        key: Key('inspection_section_${section.id}'),
        initiallyExpanded: answered < findings.length,
        leading: const Icon(Icons.room_preferences_outlined),
        title: Text(section.title),
        subtitle: Text('$answered of ${findings.length} checked'),
        children: findings
            .map((finding) {
              final item = InspectionChecklist.itemById(finding.checkId)!;
              final busy = busyChecks.contains(finding.checkId);
              return ListTile(
                key: Key('inspection_check_${finding.checkId}'),
                leading: busy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _iconFor(finding.state),
                        color: _colorFor(finding.state),
                      ),
                title: Text(item.title),
                subtitle: Text(
                  finding.note.isEmpty
                      ? finding.state.displayName
                      : '${finding.state.displayName} — ${finding.note}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: finding.hasConcernPhoto
                    ? const Icon(Icons.photo_outlined)
                    : const Icon(Icons.chevron_right),
                onTap: busy ? null : () => onEdit(finding),
              );
            })
            .toList(growable: false),
      ),
    );
  }

  static IconData _iconFor(InspectionFindingState state) => switch (state) {
    InspectionFindingState.notChecked => Icons.radio_button_unchecked,
    InspectionFindingState.satisfactory => Icons.check_circle_outline,
    InspectionFindingState.concern => Icons.warning_amber_outlined,
    InspectionFindingState.notApplicable => Icons.remove_circle_outline,
  };

  static Color _colorFor(InspectionFindingState state) => switch (state) {
    InspectionFindingState.notChecked => Colors.grey,
    InspectionFindingState.satisfactory => Colors.green,
    InspectionFindingState.concern => Colors.orange,
    InspectionFindingState.notApplicable => Colors.blueGrey,
  };
}

class _FindingEditResult {
  const _FindingEditResult({required this.finding, required this.photo});

  final InspectionFinding finding;
  final XFile? photo;
}

class _CompletedState extends StatelessWidget {
  const _CompletedState({required this.onViewSummary});

  final VoidCallback onViewSummary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton.icon(
        onPressed: onViewSummary,
        icon: const Icon(Icons.summarize_outlined),
        label: const Text('View completed summary'),
      ),
    );
  }
}
