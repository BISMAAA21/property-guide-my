import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/errors/app_failure.dart';
import '../../../shared/presentation/async_state_widgets.dart';
import '../../properties/application/property_providers.dart';
import '../../properties/domain/property_listing.dart';
import '../../properties/presentation/property_widgets.dart';
import '../application/inspection_providers.dart';
import '../domain/inspection_checklist.dart';
import '../domain/property_inspection.dart';

class InspectionHomeScreen extends ConsumerStatefulWidget {
  const InspectionHomeScreen({required this.propertyId, super.key});

  final String propertyId;

  @override
  ConsumerState<InspectionHomeScreen> createState() =>
      _InspectionHomeScreenState();
}

class _InspectionHomeScreenState extends ConsumerState<InspectionHomeScreen> {
  late final Stream<PropertyListing?> _propertyStream;
  late final Stream<PropertyInspection?> _inspectionStream;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _propertyStream = ref
        .read(propertyRepositoryProvider)
        .watchListing(widget.propertyId);
    _inspectionStream = ref
        .read(inspectionRepositoryProvider)
        .watchPropertyInspection(widget.propertyId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guided inspection')),
      body: StreamBuilder<PropertyListing?>(
        stream: _propertyStream,
        builder: (context, propertySnapshot) {
          if (propertySnapshot.connectionState == ConnectionState.waiting) {
            return const AsyncLoadingView(label: 'Loading inspection property');
          }
          final property = propertySnapshot.data;
          if (propertySnapshot.hasError || property == null) {
            return AsyncErrorView(
              error: propertySnapshot.error,
              fallback: 'The inspection property could not be loaded.',
            );
          }
          return StreamBuilder<PropertyInspection?>(
            stream: _inspectionStream,
            builder: (context, inspectionSnapshot) {
              if (inspectionSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return const AsyncLoadingView(
                  label: 'Loading saved inspection',
                );
              }
              if (inspectionSnapshot.hasError) {
                return AsyncErrorView(
                  error: inspectionSnapshot.error,
                  fallback: 'The saved inspection could not be loaded.',
                );
              }
              final inspection = inspectionSnapshot.data;
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                children: [
                  Text(
                    property.propertyName,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Text(property.location),
                  const SizedBox(height: 16),
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
                              'This checklist helps you record observations systematically. It is separate from AI damage detection and is not a professional building inspection.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error case final error?) ...[
                    const SizedBox(height: 10),
                    AsyncFailureCard(message: error),
                  ],
                  const SizedBox(height: 18),
                  if (inspection == null)
                    _NewInspection(busy: _busy, onStart: () => _start(property))
                  else if (inspection.status == InspectionStatus.inProgress)
                    _ResumeInspection(
                      inspection: inspection,
                      busy: _busy,
                      onResume: () => _openChecklist(inspection.id),
                    )
                  else
                    _CompletedInspection(
                      inspection: inspection,
                      onViewSummary: () => _openSummary(inspection.id),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _start(PropertyListing property) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(inspectionRepositoryProvider)
          .startOrResume(
            propertyId: property.id,
            propertyName: property.propertyName,
          );
      if (mounted) _openChecklist(id);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = userFacingErrorMessage(
            error,
            fallback: 'The guided inspection could not be started.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openChecklist(String inspectionId) {
    context.push(
      '/student/properties/${widget.propertyId}/inspection/$inspectionId',
    );
  }

  void _openSummary(String inspectionId) {
    context.push(
      '/student/properties/${widget.propertyId}/inspection/$inspectionId/summary',
    );
  }
}

class _NewInspection extends StatelessWidget {
  const _NewInspection({required this.busy, required this.onStart});

  final bool busy;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Inspection areas', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        ...InspectionChecklist.sections.map(
          (section) => Card(
            child: ListTile(
              leading: const Icon(Icons.room_preferences_outlined),
              title: Text(section.title),
              subtitle: Text('${section.items.length} checks'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (busy) const LinearProgressIndicator(),
        FilledButton.icon(
          key: const Key('start_inspection_button'),
          onPressed: busy ? null : onStart,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start guided inspection'),
        ),
      ],
    );
  }
}

class _ResumeInspection extends StatelessWidget {
  const _ResumeInspection({
    required this.inspection,
    required this.busy,
    required this.onResume,
  });

  final PropertyInspection inspection;
  final bool busy;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final percentage = (inspection.progress * 100).round();
    return Card(
      key: const Key('resume_inspection_card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Inspection in progress',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '${inspection.answeredCount} of ${inspection.totalCount} checks saved',
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: inspection.progress),
            const SizedBox(height: 6),
            Text('$percentage% complete'),
            if (inspection.concernCount > 0)
              Text('${inspection.concernCount} concerns recorded'),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('resume_inspection_button'),
              onPressed: busy ? null : onResume,
              icon: const Icon(Icons.restore),
              label: const Text('Resume saved inspection'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletedInspection extends StatelessWidget {
  const _CompletedInspection({
    required this.inspection,
    required this.onViewSummary,
  });

  final PropertyInspection inspection;
  final VoidCallback onViewSummary;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('completed_inspection_card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.task_alt, size: 48),
            const SizedBox(height: 10),
            Text(
              'Inspection completed',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              '${inspection.concernCount} concerns recorded across ${InspectionChecklist.sections.length} areas.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('view_inspection_summary_button'),
              onPressed: onViewSummary,
              icon: const Icon(Icons.summarize_outlined),
              label: const Text('View inspection summary'),
            ),
          ],
        ),
      ),
    );
  }
}
