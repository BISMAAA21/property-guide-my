import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/errors/app_failure.dart';
import '../../../shared/presentation/async_state_widgets.dart';
import '../../../shared/validation/image_content.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/user_role.dart';
import '../../reviews/presentation/property_reviews_panel.dart';
import '../application/property_providers.dart';
import '../domain/property_listing.dart';
import 'property_widgets.dart';

class PropertyDetailScreen extends ConsumerStatefulWidget {
  const PropertyDetailScreen({required this.propertyId, super.key});

  final String propertyId;

  @override
  ConsumerState<PropertyDetailScreen> createState() =>
      _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends ConsumerState<PropertyDetailScreen> {
  late final Stream<PropertyListing?> _listingStream;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _listingStream = ref
        .read(propertyRepositoryProvider)
        .watchListing(widget.propertyId);
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authControllerProvider).snapshot.user!.role;
    return StreamBuilder<PropertyListing?>(
      stream: _listingStream,
      builder: (context, snapshot) {
        final title = role == UserRole.admin
            ? 'Review property'
            : 'Property listing';
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: const AsyncLoadingView(label: 'Loading property listing'),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: AsyncErrorView(
              error: snapshot.error,
              fallback: 'The property listing could not be loaded.',
            ),
          );
        }
        if (snapshot.data == null) {
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: const AsyncEmptyView(
              message: 'Listing not found.',
              icon: Icons.home_work_outlined,
            ),
          );
        }
        final listing = snapshot.data!;
        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      listing.propertyName,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  PropertyStatusChip(listing.approvalStatus),
                ],
              ),
              Text(
                listing.location,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              if (listing.imageUrls.isEmpty)
                Container(
                  height: 180,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Text('No listing images added yet'),
                  ),
                )
              else
                SizedBox(
                  height: 200,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: listing.imageUrls.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final imageUrl = listing.imageUrls[index];
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.network(
                              imageUrl,
                              width: 280,
                              height: 200,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const SizedBox(
                                width: 280,
                                child: Center(
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              ),
                            ),
                          ),
                          if (role == UserRole.agent &&
                              listing.approvalStatus.isEditable)
                            Positioned(
                              right: 8,
                              top: 8,
                              child: IconButton.filledTonal(
                                tooltip: 'Remove image',
                                onPressed: _busy
                                    ? null
                                    : () => _removeImage(listing, imageUrl),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _Fact(
                    icon: Icons.payments_outlined,
                    label:
                        'RM ${listing.monthlyRent.toStringAsFixed(0)} monthly',
                  ),
                  _Fact(
                    icon: Icons.bed_outlined,
                    label: '${listing.bedrooms} bedrooms',
                  ),
                  _Fact(
                    icon: Icons.bathtub_outlined,
                    label: '${listing.bathrooms} bathrooms',
                  ),
                  _Fact(
                    icon: Icons.home_work_outlined,
                    label: listing.propertyType.displayName,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Description',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(listing.description),
              if (listing.facilities.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'Facilities',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: listing.facilities
                      .map((facility) => Chip(label: Text(facility)))
                      .toList(growable: false),
                ),
              ],
              if (listing.rejectionReason case final reason?) ...[
                const SizedBox(height: 20),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Administrator feedback: $reason'),
                  ),
                ),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: 16),
                AsyncFailureCard(message: error),
              ],
              const SizedBox(height: 20),
              if (_busy) const LinearProgressIndicator(),
              const SizedBox(height: 8),
              if (role == UserRole.agent) ..._agentActions(listing),
              if (role == UserRole.admin) ..._adminActions(listing),
              if (role == UserRole.agent || role == UserRole.admin) ...[
                const SizedBox(height: 28),
                PropertyReviewsPanel(
                  propertyId: listing.id,
                  role: role,
                  currentUserId: ref
                      .watch(authControllerProvider)
                      .snapshot
                      .user!
                      .uid,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  List<Widget> _agentActions(PropertyListing listing) {
    if (listing.approvalStatus.isEditable) {
      return [
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickImages,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Add listing images'),
        ),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => context.push('/agent/properties/${listing.id}/edit'),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit property details'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : () => _submit(listing),
          icon: const Icon(Icons.send_outlined),
          label: const Text('Submit for administrator review'),
        ),
      ];
    }
    if (listing.approvalStatus == PropertyApprovalStatus.approved) {
      return [
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _deactivate(listing),
          icon: const Icon(Icons.visibility_off_outlined),
          label: const Text('Deactivate listing'),
        ),
      ];
    }
    return const [];
  }

  List<Widget> _adminActions(PropertyListing listing) {
    return [
      if (listing.approvalStatus == PropertyApprovalStatus.pending) ...[
        FilledButton.icon(
          onPressed: _busy ? null : () => _approve(listing),
          icon: const Icon(Icons.approval_outlined),
          label: const Text('Approve listing'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _reject(listing),
          icon: const Icon(Icons.rate_review_outlined),
          label: const Text('Request changes'),
        ),
      ],
      TextButton.icon(
        onPressed: _busy ? null : () => _removeListing(listing),
        icon: const Icon(Icons.delete_forever_outlined),
        label: const Text('Remove invalid listing'),
      ),
    ];
  }

  Future<void> _pickImages() async {
    final files = await ImagePicker().pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;
    await _run(() async {
      for (final file in files.take(8)) {
        final bytes = await file.readAsBytes();
        final fallbackType = file.mimeType ?? _contentTypeFor(file.name);
        await ref
            .read(propertyRepositoryProvider)
            .uploadListingImage(
              propertyId: widget.propertyId,
              bytes: bytes,
              filename: file.name,
              contentType:
                  detectSupportedImageContentType(bytes) ?? fallbackType,
            );
      }
    });
  }

  Future<void> _removeImage(PropertyListing listing, String imageUrl) async {
    final confirmed = await _confirm(
      title: 'Remove image?',
      message: 'This image will be permanently removed from the listing.',
      action: 'Remove',
    );
    if (!confirmed) return;
    await _run(
      () => ref
          .read(propertyRepositoryProvider)
          .removeListingImage(propertyId: listing.id, imageUrl: imageUrl),
    );
  }

  Future<void> _submit(PropertyListing listing) async {
    final confirmed = await _confirm(
      title: 'Submit listing?',
      message: 'You cannot edit the listing while it is pending administrator review.',
      action: 'Submit',
    );
    if (confirmed) {
      await _run(
        () => ref.read(propertyRepositoryProvider).submitForReview(listing.id),
      );
    }
  }

  Future<void> _deactivate(PropertyListing listing) async {
    final confirmed = await _confirm(
      title: 'Deactivate listing?',
      message: 'Students will no longer see this approved property.',
      action: 'Deactivate',
    );
    if (confirmed) {
      await _run(
        () =>
            ref.read(propertyRepositoryProvider).deactivateListing(listing.id),
      );
    }
  }

  Future<void> _approve(PropertyListing listing) async {
    final confirmed = await _confirm(
      title: 'Approve listing?',
      message: 'The property will become visible to students.',
      action: 'Approve',
    );
    if (confirmed) {
      await _run(
        () => ref.read(propertyRepositoryProvider).approveListing(listing.id),
      );
    }
  }

  Future<void> _reject(PropertyListing listing) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request listing changes'),
        content: TextField(
          controller: reasonController,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'Explain what the agent needs to correct.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, reasonController.text),
            child: const Text('Send feedback'),
          ),
        ],
      ),
    );
    reasonController.dispose();
    if (reason == null) return;
    await _run(
      () => ref
          .read(propertyRepositoryProvider)
          .rejectListing(listing.id, reason),
    );
  }

  Future<void> _removeListing(PropertyListing listing) async {
    final confirmed = await _confirm(
      title: 'Remove listing permanently?',
      message: 'The property record and its uploaded images will be deleted. This cannot be undone.',
      action: 'Remove permanently',
    );
    if (!confirmed) return;
    final succeeded = await _run(
      () => ref.read(propertyRepositoryProvider).removeListing(listing.id),
    );
    if (succeeded && mounted) context.go('/admin');
  }

  Future<bool> _run(Future<void> Function() action) async {
    if (_busy) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      return true;
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = userFacingErrorMessage(
            error,
            fallback: 'The property action could not be completed.',
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  static String _contentTypeFor(String filename) {
    final normalized = filename.toLowerCase();
    if (normalized.endsWith('.png')) return 'image/png';
    if (normalized.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(avatar: Icon(icon, size: 18), label: Text(label));
  }
}
