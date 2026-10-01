import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/presentation/async_state_widgets.dart';
import '../../../shared/validation/image_content.dart';
import '../../inspections/domain/inspection_checklist.dart';
import '../application/damage_detection_providers.dart';
import '../domain/damage_detection_failure.dart';
import '../domain/damage_detection_repository.dart';
import '../domain/damage_detection_result.dart';

typedef DamageImagePicker = Future<XFile?> Function();

class DamageDetectionScreen extends ConsumerStatefulWidget {
  const DamageDetectionScreen({
    required this.propertyId,
    this.inspectionId = '',
    this.checkId = '',
    this.photoPath = '',
    this.photoUrl = '',
    this.pickDamageImage,
    super.key,
  });

  final String propertyId;
  final String inspectionId;
  final String checkId;
  final String photoPath;
  final String photoUrl;
  final DamageImagePicker? pickDamageImage;

  @override
  ConsumerState<DamageDetectionScreen> createState() =>
      _DamageDetectionScreenState();
}

class _DamageDetectionScreenState extends ConsumerState<DamageDetectionScreen> {
  XFile? _selectedFile;
  Uint8List? _selectedBytes;
  String? _selectedContentType;
  DamageReport? _latestReport;
  String? _errorMessage;
  bool _useInspectionPhoto = false;
  bool _isChoosing = false;
  bool _isDetecting = false;

  bool get _hasAnyHandoffValue =>
      widget.inspectionId.isNotEmpty ||
      widget.checkId.isNotEmpty ||
      widget.photoPath.isNotEmpty ||
      widget.photoUrl.isNotEmpty;

  bool get _hasValidHandoff =>
      widget.propertyId.isNotEmpty &&
      widget.inspectionId.isNotEmpty &&
      InspectionChecklist.itemById(widget.checkId) != null &&
      widget.photoPath.isNotEmpty &&
      widget.photoUrl.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _useInspectionPhoto = _hasValidHandoff;
  }

  Future<void> _chooseImage() async {
    if (_isChoosing || _isDetecting) return;
    setState(() {
      _isChoosing = true;
      _errorMessage = null;
    });
    try {
      final picker =
          widget.pickDamageImage ??
          () => ImagePicker().pickImage(
            source: ImageSource.gallery,
            imageQuality: 92,
          );
      final file = await picker();
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final contentType =
          detectSupportedImageContentType(bytes) ?? _contentTypeFor(file);
      final inputError = DamageImageInput(
        byteLength: bytes.length,
        contentType: contentType,
      ).validate();
      if (inputError != null) {
        throw DamageDetectionFailure('invalid-damage-image', inputError);
      }
      if (!mounted) return;
      setState(() {
        _selectedFile = file;
        _selectedBytes = bytes;
        _selectedContentType = contentType;
        _useInspectionPhoto = false;
        _latestReport = null;
      });
    } on DamageDetectionFailure catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'The selected damage photo could not be read.';
        });
      }
    } finally {
      if (mounted) setState(() => _isChoosing = false);
    }
  }

  Future<void> _detect() async {
    DamagePhotoSource source;
    if (_useInspectionPhoto && _hasValidHandoff) {
      source = InspectionDamagePhoto(
        inspectionId: widget.inspectionId,
        checkId: widget.checkId,
        imagePath: widget.photoPath,
      );
    } else {
      final file = _selectedFile;
      final bytes = _selectedBytes;
      final contentType = _selectedContentType;
      if (file == null || bytes == null || contentType == null) {
        setState(() => _errorMessage = 'Choose a photo before analysing.');
        return;
      }
      source = UploadedDamagePhoto(
        bytes: bytes,
        filename: file.name,
        contentType: contentType,
      );
    }
    setState(() {
      _isDetecting = true;
      _errorMessage = null;
      _latestReport = null;
    });
    try {
      final report = await ref
          .read(damageDetectionRepositoryProvider)
          .detectDamage(propertyId: widget.propertyId, source: source);
      if (mounted) setState(() => _latestReport = report);
    } on DamageDetectionFailure catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Damage detection failed unexpectedly. Try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _isDetecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.propertyId.isEmpty ||
        (_hasAnyHandoffValue && !_hasValidHandoff)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Damage detection')),
        body: const _CenteredMessage(
          icon: Icons.error_outline,
          message: 'The concern photo context is incomplete. Return to the inspection summary and try again.',
        ),
      );
    }
    final check = InspectionChecklist.itemById(widget.checkId);
    return Scaffold(
      appBar: AppBar(title: const Text('Damage detection')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _useInspectionPhoto && check != null
                ? check.title
                : 'Check a property photo',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Upload a clear, close photograph. The model checks only for a possible wall crack, water or damp stain, mold, or no supported visible damage.',
          ),
          const SizedBox(height: 12),
          const _DamageSafetyNotice(),
          const SizedBox(height: 16),
          _DamagePhotoPreview(
            bytes: _selectedBytes,
            networkUrl: _useInspectionPhoto ? widget.photoUrl : null,
            filename: _useInspectionPhoto
                ? 'Guided Inspection concern photo'
                : _selectedFile?.name,
          ),
          if (_useInspectionPhoto) ...[
            const SizedBox(height: 8),
            Text(
              'Property: ${widget.propertyId}\nInspection: ${widget.inspectionId}',
              key: const Key('damage_handoff_context'),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('choose_damage_image_button'),
            onPressed: _isChoosing || _isDetecting ? null : _chooseImage,
            icon: _isChoosing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_outlined),
            label: Text(
              _useInspectionPhoto || _selectedBytes != null
                  ? 'Choose a different uploaded photo'
                  : 'Choose damage photo',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('run_damage_detection_button'),
            onPressed:
                (_useInspectionPhoto || _selectedBytes != null) && !_isDetecting
                ? _detect
                : null,
            icon: _isDetecting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.biotech_outlined),
            label: Text(_isDetecting ? 'Analysing photoâ€¦' : 'Analyse photo'),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            InlineErrorCard(
              key: const Key('damage_detection_error'),
              message: _errorMessage!,
            ),
          ],
          if (_latestReport != null) ...[
            const SizedBox(height: 20),
            DamageDetectionResultCard(
              report: _latestReport!,
              heading: 'Latest observation',
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Previous observations',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          _DamageHistory(propertyId: widget.propertyId),
        ],
      ),
    );
  }
}

class DamageDetectionResultCard extends StatelessWidget {
  const DamageDetectionResultCard({
    required this.report,
    this.heading = 'Damage observation',
    super.key,
  });

  final DamageReport report;
  final String heading;

  @override
  Widget build(BuildContext context) {
    final result = report.result;
    final color = result.damageClass.isPossibleDefect
        ? Colors.orange.shade900
        : Colors.green.shade700;
    return Card(
      key: const Key('damage_detection_result_card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(heading, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  result.damageClass.isPossibleDefect
                      ? Icons.warning_amber_outlined
                      : Icons.check_circle_outline,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.damageClass.displayName,
                    key: const Key('damage_class_text'),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(color: color, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Semantics(
              label:
                  'Model confidence ${(result.modelScore * 100).toStringAsFixed(1)} percent',
              child: LinearProgressIndicator(
                key: const Key('damage_score_indicator'),
                value: result.modelScore,
                minHeight: 10,
                color: color,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Model confidence ${(result.modelScore * 100).toStringAsFixed(1)}%',
              key: const Key('damage_score_text'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(
              result.recommendation,
              key: const Key('damage_recommendation'),
            ),
            if (result.boundingBox == null) ...[
              const SizedBox(height: 8),
              const Text(
                'This baseline classifies the whole photo and does not locate a specific area.',
              ),
            ],
            const Divider(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.disclaimer,
                    key: const Key('damage_disclaimer'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DamageHistory extends ConsumerWidget {
  const _DamageHistory({required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<DamageReport>>(
      stream: ref
          .watch(damageDetectionRepositoryProvider)
          .watchReports(propertyId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AsyncErrorView(
            key: const Key('damage_history_error'),
            error: snapshot.error,
            fallback: 'Previous damage reports could not be loaded.',
            compact: true,
          );
        }
        if (!snapshot.hasData) {
          return const AsyncLoadingView(
            label: 'Loading damage history',
            compact: true,
          );
        }
        final reports = snapshot.data!;
        if (reports.isEmpty) {
          return const AsyncEmptyView(
            key: Key('damage_history_empty'),
            message: 'No previous damage observations for this property.',
            icon: Icons.home_repair_service_outlined,
            compact: true,
          );
        }
        return Column(
          children: reports
              .map(
                (report) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DamageDetectionResultCard(
                    report: report,
                    heading: _reportHeading(report.createdAt),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }

  static String _reportHeading(DateTime? date) {
    if (date == null) return 'Saved observation';
    final local = date.toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return 'Saved ${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }
}

class _DamagePhotoPreview extends StatelessWidget {
  const _DamagePhotoPreview({
    required this.bytes,
    required this.networkUrl,
    required this.filename,
  });

  final Uint8List? bytes;
  final String? networkUrl;
  final String? filename;

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (bytes != null) {
      image = Image.memory(
        bytes!,
        key: const Key('damage_image_preview'),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _BrokenImage(),
      );
    } else if (networkUrl != null && networkUrl!.isNotEmpty) {
      image = Image.network(
        networkUrl!,
        key: const Key('damage_handoff_preview'),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _BrokenImage(),
      );
    } else {
      image = const ColoredBox(
        color: Color(0xFFE8E8E8),
        child: Center(
          child: Icon(Icons.add_photo_alternate_outlined, size: 48),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Uploaded photo',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            AspectRatio(aspectRatio: 16 / 9, child: image),
            if (filename != null) ...[
              const SizedBox(height: 6),
              Text(filename!, overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
    );
  }
}

class _BrokenImage extends StatelessWidget {
  const _BrokenImage();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0xFFE8E8E8),
    child: Center(child: Icon(Icons.broken_image_outlined)),
  );
}

class _DamageSafetyNotice extends StatelessWidget {
  const _DamageSafetyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.health_and_safety_outlined),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'This is an AI-assisted observation from an uploaded photo, not a diagnosis or safety inspection. Use a qualified professional when concerned.',
            ),
          ),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

String _contentTypeFor(XFile file) {
  final declared = file.mimeType?.toLowerCase().split(';').first.trim();
  if (declared != null && declared.isNotEmpty) return declared;
  final name = file.name.toLowerCase();
  if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
  if (name.endsWith('.png')) return 'image/png';
  if (name.endsWith('.webp')) return 'image/webp';
  return '';
}
