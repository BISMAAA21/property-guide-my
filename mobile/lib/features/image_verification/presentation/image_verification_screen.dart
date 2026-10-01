import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/presentation/async_state_widgets.dart';
import '../../../shared/validation/image_content.dart';
import '../../properties/application/property_providers.dart';
import '../../properties/domain/property_listing.dart';
import '../application/image_verification_providers.dart';
import '../domain/image_verification_failure.dart';
import '../domain/image_verification_result.dart';

typedef VisitImagePicker = Future<XFile?> Function();

class ImageVerificationScreen extends ConsumerStatefulWidget {
  const ImageVerificationScreen({
    required this.propertyId,
    this.pickVisitImage,
    super.key,
  });

  final String propertyId;
  final VisitImagePicker? pickVisitImage;

  @override
  ConsumerState<ImageVerificationScreen> createState() =>
      _ImageVerificationScreenState();
}

class _ImageVerificationScreenState
    extends ConsumerState<ImageVerificationScreen> {
  XFile? _selectedFile;
  Uint8List? _selectedBytes;
  String? _selectedContentType;
  VerificationReport? _latestReport;
  String? _errorMessage;
  bool _isChoosing = false;
  bool _isVerifying = false;

  Future<void> _chooseImage() async {
    if (_isChoosing || _isVerifying) return;
    setState(() {
      _isChoosing = true;
      _errorMessage = null;
    });
    try {
      final picker =
          widget.pickVisitImage ??
          () => ImagePicker().pickImage(
            source: ImageSource.gallery,
            imageQuality: 92,
          );
      final file = await picker();
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final contentType =
          detectSupportedImageContentType(bytes) ?? _contentTypeFor(file);
      final inputError = VerificationImageInput(
        byteLength: bytes.length,
        contentType: contentType,
      ).validate();
      if (inputError != null) {
        throw ImageVerificationFailure('invalid-visit-image', inputError);
      }
      if (!mounted) return;
      setState(() {
        _selectedFile = file;
        _selectedBytes = bytes;
        _selectedContentType = contentType;
        _latestReport = null;
      });
    } on ImageVerificationFailure catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'The selected visit photo could not be read.';
        });
      }
    } finally {
      if (mounted) setState(() => _isChoosing = false);
    }
  }

  Future<void> _verify(PropertyListing property) async {
    final file = _selectedFile;
    final bytes = _selectedBytes;
    final contentType = _selectedContentType;
    if (file == null || bytes == null || contentType == null) {
      setState(() => _errorMessage = 'Choose a visit photo before comparing.');
      return;
    }
    if (property.approvalStatus != PropertyApprovalStatus.approved ||
        property.imageUrls.isEmpty) {
      setState(() {
        _errorMessage = 'This property must be approved and have listing images before comparison.';
      });
      return;
    }
    setState(() {
      _isVerifying = true;
      _errorMessage = null;
      _latestReport = null;
    });
    try {
      final report = await ref
          .read(imageVerificationRepositoryProvider)
          .verifyVisitImage(
            propertyId: widget.propertyId,
            bytes: bytes,
            filename: file.name,
            contentType: contentType,
          );
      if (mounted) setState(() => _latestReport = report);
    } on ImageVerificationFailure catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Image verification failed unexpectedly. Try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final propertyRepository = ref.watch(propertyRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Image verification')),
      body: StreamBuilder<PropertyListing?>(
        stream: propertyRepository.watchListing(widget.propertyId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AsyncErrorView(
              error: snapshot.error,
              fallback: 'The property could not be loaded for verification.',
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AsyncLoadingView(
              label: 'Loading property verification',
            );
          }
          final property = snapshot.data;
          if (property == null ||
              property.approvalStatus != PropertyApprovalStatus.approved) {
            return const _CenteredMessage(
              icon: Icons.home_work_outlined,
              message: 'This approved property is no longer available.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                property.propertyName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Upload a photo taken during your visit. The AI compares its visual features with every approved listing image and selects the closest match.',
              ),
              const SizedBox(height: 12),
              const _SafetyNotice(),
              const SizedBox(height: 16),
              if (property.imageUrls.isEmpty)
                const _CenteredMessage(
                  icon: Icons.no_photography_outlined,
                  message: 'This property has no listing images available for comparison.',
                )
              else ...[
                _VisitImageCard(
                  bytes: _selectedBytes,
                  filename: _selectedFile?.name,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('choose_visit_image_button'),
                  onPressed: _isChoosing || _isVerifying ? null : _chooseImage,
                  icon: _isChoosing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file_outlined),
                  label: Text(
                    _selectedBytes == null
                        ? 'Choose visit photo'
                        : 'Choose a different photo',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const Key('run_image_verification_button'),
                  onPressed: _selectedBytes == null || _isVerifying
                      ? null
                      : () => _verify(property),
                  icon: _isVerifying
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.compare_outlined),
                  label: Text(
                    _isVerifying ? 'Comparing all imagesâ€¦' : 'Compare images',
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  InlineErrorCard(
                    key: const Key('image_verification_error'),
                    message: _errorMessage!,
                  ),
                ],
                if (_latestReport != null) ...[
                  const SizedBox(height: 20),
                  ImageVerificationResultCard(
                    report: _latestReport!,
                    heading: 'Latest comparison',
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Previous comparisons',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                _ReportHistory(propertyId: widget.propertyId),
              ],
            ],
          );
        },
      ),
    );
  }
}

class ImageVerificationResultCard extends StatelessWidget {
  const ImageVerificationResultCard({
    required this.report,
    this.heading = 'Comparison result',
    super.key,
  });

  final VerificationReport report;
  final String heading;

  @override
  Widget build(BuildContext context) {
    final result = report.result;
    final color = switch (result.similarityLevel) {
      SimilarityLevel.high => Colors.green.shade700,
      SimilarityLevel.moderate => Colors.orange.shade800,
      SimilarityLevel.low => Theme.of(context).colorScheme.error,
    };
    return Card(
      key: const Key('image_verification_result_card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(heading, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Semantics(
              label:
                  'Similarity score ${result.similarityScore.toStringAsFixed(1)} out of 100',
              child: LinearProgressIndicator(
                key: const Key('similarity_score_indicator'),
                value: result.similarityScore / 100,
                minHeight: 12,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${result.similarityScore.toStringAsFixed(1)} / 100',
              key: const Key('similarity_score_text'),
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.bold),
            ),
            Text(
              result.similarityLevel.displayName,
              key: const Key('similarity_level_text'),
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
            if (result.possibleMismatch) ...[
              const SizedBox(height: 12),
              Container(
                key: const Key('possible_mismatch_warning'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded),
                    const SizedBox(width: 8),
                    Expanded(child: Text(result.mismatchWarning!)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(result.guidance, key: const Key('verification_guidance')),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  report.bestListingImageUrl,
                  key: const Key('best_listing_image'),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: Color(0xFFE8E8E8),
                    child: Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Closest listing image ${result.bestListingImageIndex + 1}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.disclaimer,
                    key: const Key('verification_disclaimer'),
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

class _ReportHistory extends ConsumerWidget {
  const _ReportHistory({required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<VerificationReport>>(
      stream: ref
          .watch(imageVerificationRepositoryProvider)
          .watchReports(propertyId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AsyncErrorView(
            key: const Key('verification_history_error'),
            error: snapshot.error,
            fallback: 'Previous verification reports could not be loaded.',
            compact: true,
          );
        }
        if (!snapshot.hasData) {
          return const AsyncLoadingView(
            label: 'Loading verification history',
            compact: true,
          );
        }
        final reports = snapshot.data!;
        if (reports.isEmpty) {
          return const AsyncEmptyView(
            key: Key('verification_history_empty'),
            message: 'No previous comparisons for this property.',
            icon: Icons.compare_outlined,
            compact: true,
          );
        }
        return Column(
          children: reports
              .map(
                (report) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ImageVerificationResultCard(
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
    if (date == null) return 'Saved comparison';
    final local = date.toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return 'Saved ${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }
}

class _VisitImageCard extends StatelessWidget {
  const _VisitImageCard({required this.bytes, required this.filename});

  final Uint8List? bytes;
  final String? filename;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Visit photo', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: bytes == null
                  ? const ColoredBox(
                      color: Color(0xFFE8E8E8),
                      child: Center(
                        child: Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 48,
                        ),
                      ),
                    )
                  : Image.memory(
                      bytes!,
                      key: const Key('visit_image_preview'),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: Color(0xFFE8E8E8),
                        child: Center(child: Icon(Icons.broken_image_outlined)),
                      ),
                    ),
            ),
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

class _SafetyNotice extends StatelessWidget {
  const _SafetyNotice();

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
          Icon(Icons.shield_outlined),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Similarity is only one safety signal. Confirm the address, unit, agent details, and tenancy terms yourself.',
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
