import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/presentation/async_state_widgets.dart';
import '../application/agreement_providers.dart';
import '../domain/agreement_failure.dart';
import '../domain/agreement_result.dart';

class PickedAgreementPdf {
  const PickedAgreementPdf({
    required this.name,
    required this.bytes,
    this.contentType = 'application/pdf',
  });

  final String name;
  final Uint8List bytes;
  final String contentType;
}

typedef AgreementPdfPicker = Future<PickedAgreementPdf?> Function();

class AgreementSimplificationScreen extends ConsumerStatefulWidget {
  const AgreementSimplificationScreen({this.pickPdf, super.key});

  final AgreementPdfPicker? pickPdf;

  @override
  ConsumerState<AgreementSimplificationScreen> createState() =>
      _AgreementSimplificationScreenState();
}

class _AgreementSimplificationScreenState
    extends ConsumerState<AgreementSimplificationScreen> {
  PickedAgreementPdf? _selectedPdf;
  AgreementReport? _latestReport;
  String? _errorMessage;
  bool _privacyAccepted = false;
  bool _isChoosing = false;
  bool _isProcessing = false;

  Future<PickedAgreementPdf?> _pickPdf() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return PickedAgreementPdf(name: file.name, bytes: bytes);
  }

  Future<void> _chooseDocument() async {
    if (_isChoosing || _isProcessing || !_privacyAccepted) return;
    setState(() {
      _isChoosing = true;
      _errorMessage = null;
    });
    try {
      final selected = await (widget.pickPdf ?? _pickPdf)();
      if (selected == null) return;
      final error = AgreementPdfInput(
        byteLength: selected.bytes.length,
        contentType: selected.contentType,
      ).validate();
      if (error != null) {
        throw AgreementFailure('invalid-agreement', error);
      }
      if (!mounted) return;
      setState(() {
        _selectedPdf = selected;
        _latestReport = null;
      });
    } on AgreementFailure catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'The selected PDF could not be read.');
      }
    } finally {
      if (mounted) setState(() => _isChoosing = false);
    }
  }

  Future<void> _processDocument() async {
    final selected = _selectedPdf;
    if (!_privacyAccepted) {
      setState(
        () => _errorMessage = 'Accept the privacy notice before continuing.',
      );
      return;
    }
    if (selected == null) {
      setState(() => _errorMessage = 'Choose a tenancy agreement PDF first.');
      return;
    }
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _latestReport = null;
    });
    try {
      final report = await ref
          .read(agreementRepositoryProvider)
          .simplifyAndSave(
            bytes: selected.bytes,
            filename: selected.name,
            contentType: selected.contentType,
          );
      if (mounted) setState(() => _latestReport = report);
    } on AgreementFailure catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'Agreement processing failed unexpectedly. Try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Understand an agreement')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          Text(
            'Tenancy agreement simplification',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Upload an English native or scanned PDF. The result keeps each original clause beside a simpler explanation and important points.',
          ),
          const SizedBox(height: 16),
          const _LegalNotice(),
          const SizedBox(height: 12),
          _PrivacyNotice(
            accepted: _privacyAccepted,
            enabled: !_isChoosing && !_isProcessing,
            onChanged: (value) => setState(() {
              _privacyAccepted = value;
              _errorMessage = null;
            }),
          ),
          const SizedBox(height: 16),
          _SelectedDocumentCard(document: _selectedPdf),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('choose_agreement_pdf_button'),
            onPressed: _privacyAccepted && !_isChoosing && !_isProcessing
                ? _chooseDocument
                : null,
            icon: _isChoosing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            label: Text(
              _selectedPdf == null ? 'Choose PDF' : 'Choose a different PDF',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('simplify_agreement_button'),
            onPressed:
                _privacyAccepted && _selectedPdf != null && !_isProcessing
                ? _processDocument
                : null,
            icon: _isProcessing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.document_scanner_outlined),
            label: Text(
              _isProcessing
                  ? 'Extracting and simplifying…'
                  : 'Simplify clauses',
            ),
          ),
          if (_isProcessing) ...[
            const SizedBox(height: 8),
            const Text(
              'Scanned pages may take several minutes. Keep this screen open.',
              textAlign: TextAlign.center,
            ),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            InlineErrorCard(
              key: const Key('agreement_error'),
              message: _errorMessage!,
            ),
          ],
          if (_latestReport != null) ...[
            const SizedBox(height: 20),
            AgreementResultCard(
              report: _latestReport!,
              heading: 'Latest saved result',
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Previous agreements',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const _AgreementHistory(),
        ],
      ),
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice({
    required this.accepted,
    required this.enabled,
    required this.onChanged,
  });

  final bool accepted;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: CheckboxListTile(
        key: const Key('agreement_privacy_consent'),
        value: accepted,
        onChanged: enabled ? (value) => onChanged(value ?? false) : null,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('I understand how this document is processed'),
        subtitle: const Text(
          'Extracted agreement text is sent to the configured external AI provider. The PDF and saved result are private to your student account. For demonstrations, use only the supplied sample—not a real private agreement.',
        ),
      ),
    );
  }
}

class _LegalNotice extends StatelessWidget {
  const _LegalNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('agreement_legal_notice'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.gavel_outlined),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'This feature provides simplified information, not legal advice. Verify important terms with a qualified professional before signing.',
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedDocumentCard extends StatelessWidget {
  const _SelectedDocumentCard({required this.document});

  final PickedAgreementPdf? document;

  @override
  Widget build(BuildContext context) {
    final selected = document;
    return Card(
      key: const Key('selected_agreement_card'),
      child: ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(selected?.name ?? 'No PDF selected'),
        subtitle: Text(
          selected == null
              ? 'Maximum 10 MiB and 30 pages'
              : '${(selected.bytes.length / 1024).toStringAsFixed(1)} KiB',
        ),
      ),
    );
  }
}

class AgreementResultCard extends StatelessWidget {
  const AgreementResultCard({
    required this.report,
    this.heading = 'Saved agreement result',
    super.key,
  });

  final AgreementReport report;
  final String heading;

  @override
  Widget build(BuildContext context) {
    final result = report.result;
    return Card(
      key: const Key('agreement_result_card'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(heading, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(report.filename),
            Text(result.extractionMethod.label),
            const SizedBox(height: 12),
            Container(
              key: const Key('agreement_result_disclaimer'),
              padding: const EdgeInsets.all(12),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Text(
                result.disclaimer,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 10),
            ...result.clauses.map((clause) => _ClauseTile(clause: clause)),
          ],
        ),
      ),
    );
  }
}

class _ClauseTile extends StatelessWidget {
  const _ClauseTile({required this.clause});

  final SimplifiedAgreementClause clause;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: Key('agreement_${clause.id}'),
      tilePadding: EdgeInsets.zero,
      title: Text(clause.title),
      subtitle: Text(clause.simplified),
      childrenPadding: const EdgeInsets.only(bottom: 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Original wording', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        SelectableText(clause.original),
        const SizedBox(height: 10),
        Text(
          'Simplified information',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(clause.simplified),
        const SizedBox(height: 10),
        Text('Important points', style: Theme.of(context).textTheme.titleSmall),
        ...clause.importantPoints.map(
          (point) => Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('• $point'),
          ),
        ),
      ],
    );
  }
}

class _AgreementHistory extends ConsumerWidget {
  const _AgreementHistory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<AgreementReport>>(
      stream: ref.watch(agreementRepositoryProvider).watchReports(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AsyncLoadingView(
            label: 'Loading saved agreements',
            compact: true,
          );
        }
        if (snapshot.hasError) {
          return AsyncErrorView(
            error: snapshot.error,
            fallback: 'Saved agreements could not be loaded.',
            compact: true,
          );
        }
        final reports = snapshot.data ?? const [];
        if (reports.isEmpty) {
          return const AsyncEmptyView(
            message: 'No saved agreement results yet.',
            icon: Icons.description_outlined,
            compact: true,
          );
        }
        return Column(
          children: reports
              .map(
                (report) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AgreementResultCard(report: report),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}
