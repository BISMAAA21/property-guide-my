import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/presentation/async_state_widgets.dart';
import '../application/inspection_providers.dart';
import '../domain/inspection_checklist.dart';
import '../domain/property_inspection.dart';

class InspectionSummaryScreen extends ConsumerStatefulWidget {
  const InspectionSummaryScreen({
    required this.propertyId,
    required this.inspectionId,
    super.key,
  });

  final String propertyId;
  final String inspectionId;

  @override
  ConsumerState<InspectionSummaryScreen> createState() =>
      _InspectionSummaryScreenState();
}

class _InspectionSummaryScreenState
    extends ConsumerState<InspectionSummaryScreen> {
  late final Stream<PropertyInspection?> _inspectionStream;

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
      appBar: AppBar(title: const Text('Inspection summary')),
      body: StreamBuilder<PropertyInspection?>(
        stream: _inspectionStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AsyncLoadingView(label: 'Loading inspection summary');
          }
          final inspection = snapshot.data;
          if (snapshot.hasError || inspection == null) {
            return AsyncErrorView(
              error: snapshot.error,
              fallback: 'The inspection summary could not be loaded.',
            );
          }
          if (inspection.status != InspectionStatus.completed) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Complete every checklist item before viewing the final summary.',
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.task_alt, size: 42),
                      const SizedBox(height: 10),
                      Text(
                        inspection.propertyName,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${inspection.totalCount} checks completed • ${inspection.concernCount} concerns',
                      ),
                      Text('Checklist version ${inspection.checklistVersion}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This private summary records your observations. It does not certify the property as safe or replace a qualified professional inspection.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Results by area',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              ...inspection.sectionSummaries.map(
                (summary) => _SummarySection(
                  summary: summary,
                  onDamageHandoff: (finding) =>
                      _openDamageHandoff(context, inspection, finding),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () =>
                    context.go('/student/properties/${widget.propertyId}'),
                icon: const Icon(Icons.home_work_outlined),
                label: const Text('Return to property'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openDamageHandoff(
    BuildContext context,
    PropertyInspection inspection,
    InspectionFinding finding,
  ) {
    final uri = Uri(
      path:
          '/student/properties/${widget.propertyId}/inspection/${inspection.id}/damage',
      queryParameters: {
        'checkId': finding.checkId,
        'photoPath': finding.concernImagePath!,
        'photoUrl': finding.concernImageUrl!,
      },
    );
    context.push(uri.toString());
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.summary, required this.onDamageHandoff});

  final InspectionSectionSummary summary;
  final ValueChanged<InspectionFinding> onDamageHandoff;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('summary_section_${summary.section.id}'),
      child: ExpansionTile(
        initiallyExpanded: summary.concernCount > 0,
        leading: Icon(
          summary.concernCount > 0
              ? Icons.warning_amber_outlined
              : Icons.check_circle_outline,
          color: summary.concernCount > 0 ? Colors.orange : Colors.green,
        ),
        title: Text(summary.section.title),
        subtitle: Text(
          '${summary.concernCount} concerns • ${summary.satisfactoryCount} satisfactory • ${summary.notApplicableCount} not applicable',
        ),
        children: summary.findings
            .map((finding) {
              final item = InspectionChecklist.itemById(finding.checkId)!;
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          finding.state == InspectionFindingState.concern
                              ? Icons.warning_amber_outlined
                              : finding.state ==
                                    InspectionFindingState.satisfactory
                              ? Icons.check_circle_outline
                              : Icons.remove_circle_outline,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              Text(finding.state.displayName),
                              if (finding.note.isNotEmpty) Text(finding.note),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (finding.hasConcernPhoto) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          finding.concernImageUrl!,
                          height: 160,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox(
                            height: 80,
                            child: Center(
                              child: Text(
                                'Concern photo could not be displayed.',
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        key: Key('damage_handoff_${finding.checkId}'),
                        onPressed: () => onDamageHandoff(finding),
                        icon: const Icon(Icons.biotech_outlined),
                        label: const Text('Analyse photo for visible damage'),
                      ),
                    ],
                    const Divider(height: 24),
                  ],
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}
