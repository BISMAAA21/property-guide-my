import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/errors/app_failure.dart';
import '../../../shared/presentation/async_state_widgets.dart';
import '../../auth/domain/user_role.dart';
import '../application/review_providers.dart';
import '../domain/property_review.dart';

class PropertyReviewsPanel extends ConsumerStatefulWidget {
  const PropertyReviewsPanel({
    required this.propertyId,
    required this.role,
    required this.currentUserId,
    super.key,
  });

  final String propertyId;
  final UserRole role;
  final String currentUserId;

  @override
  ConsumerState<PropertyReviewsPanel> createState() =>
      _PropertyReviewsPanelState();
}

class _PropertyReviewsPanelState extends ConsumerState<PropertyReviewsPanel> {
  late final Stream<List<PropertyReview>> _reviewsStream;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reviewsStream = ref
        .read(reviewRepositoryProvider)
        .watchPropertyReviews(widget.propertyId);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PropertyReview>>(
      stream: _reviewsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AsyncLoadingView(
            label: 'Loading student reviews',
            compact: true,
          );
        }
        if (snapshot.hasError) {
          return AsyncErrorView(
            error: snapshot.error,
            fallback: 'Student reviews could not be loaded.',
            compact: true,
          );
        }
        final reviews = snapshot.data ?? const [];
        final ownReview = reviews
            .where((review) => review.studentId == widget.currentUserId)
            .firstOrNull;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Student reviews (${reviews.length})',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (widget.role == UserRole.student)
                  FilledButton.tonalIcon(
                    key: const Key('write_review_button'),
                    onPressed: _busy
                        ? null
                        : () => _editReview(existing: ownReview),
                    icon: Icon(
                      ownReview == null
                          ? Icons.rate_review_outlined
                          : Icons.edit_outlined,
                    ),
                    label: Text(
                      ownReview == null ? 'Write review' : 'Edit mine',
                    ),
                  ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
            if (_error case final error?) ...[
              const SizedBox(height: 10),
              InlineErrorCard(key: const Key('review_error'), message: error),
            ],
            const SizedBox(height: 10),
            if (reviews.isEmpty)
              const Card(
                key: Key('reviews_empty_state'),
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'No student reviews yet. Be the first to share a useful property experience.',
                  ),
                ),
              )
            else
              ...reviews.map(
                (review) => _ReviewCard(
                  review: review,
                  isCurrentStudent: review.studentId == widget.currentUserId,
                  onRemove: widget.role == UserRole.admin && !_busy
                      ? () => _removeReview(review)
                      : null,
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _editReview({PropertyReview? existing}) async {
    final commentController = TextEditingController(text: existing?.comment);
    var rating = existing?.rating ?? 5;
    String? validationError;
    final input = await showDialog<ReviewWriteInput>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Write a review' : 'Edit your review'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Choose a rating'),
                const SizedBox(height: 6),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: List.generate(5, (index) {
                    final value = index + 1;
                    return IconButton(
                      key: Key('review_star_$value'),
                      tooltip: '$value stars',
                      onPressed: () => setDialogState(() => rating = value),
                      icon: Icon(
                        value <= rating ? Icons.star : Icons.star_border,
                        color: Colors.amber.shade700,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('review_comment_field'),
                  controller: commentController,
                  minLines: 4,
                  maxLines: 7,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    labelText: 'Property experience',
                    hintText: 'Share specific information that may help other students.',
                    border: const OutlineInputBorder(),
                    errorText: validationError,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('save_review_button'),
              onPressed: () {
                final candidate = ReviewWriteInput(
                  rating: rating,
                  comment: commentController.text,
                );
                final error = candidate.validate();
                if (error != null) {
                  setDialogState(() => validationError = error);
                  return;
                }
                Navigator.pop(context, candidate);
              },
              child: const Text('Save review'),
            ),
          ],
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      commentController.dispose();
    });
    if (input == null) return;
    await _run(
      () => ref
          .read(reviewRepositoryProvider)
          .saveReview(propertyId: widget.propertyId, input: input),
    );
  }

  Future<void> _removeReview(PropertyReview review) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove this review?'),
            content: const Text(
              'The review will be deleted and the property rating will be recalculated.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove review'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await _run(() => ref.read(reviewRepositoryProvider).removeReview(review));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = userFacingErrorMessage(
            error,
            fallback: 'The review action could not be completed.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.review,
    required this.isCurrentStudent,
    required this.onRemove,
  });

  final PropertyReview review;
  final bool isCurrentStudent;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('review_${review.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isCurrentStudent
                        ? '${review.studentName} (you)'
                        : review.studentName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    tooltip: 'Remove review',
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            Row(
              children: [
                ...List.generate(
                  5,
                  (index) => Icon(
                    index < review.rating ? Icons.star : Icons.star_border,
                    size: 18,
                    color: Colors.amber.shade700,
                  ),
                ),
                if (review.updatedAt case final date?) ...[
                  const SizedBox(width: 8),
                  Text(_formatDate(date)),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(review.comment),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
