import 'package:flutter/material.dart';

import '../../../shared/presentation/async_state_widgets.dart';
import '../domain/property_listing.dart';

class PropertyStatusChip extends StatelessWidget {
  const PropertyStatusChip(this.status, {super.key});

  final PropertyApprovalStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      PropertyApprovalStatus.draft => (Colors.blueGrey, Icons.edit_note),
      PropertyApprovalStatus.pending => (Colors.orange, Icons.hourglass_top),
      PropertyApprovalStatus.approved => (
        Colors.green,
        Icons.verified_outlined,
      ),
      PropertyApprovalStatus.rejected => (Colors.red, Icons.feedback_outlined),
      PropertyApprovalStatus.inactive => (
        Colors.grey,
        Icons.visibility_off_outlined,
      ),
    };
    return Chip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(status.displayName),
      side: BorderSide(color: color.withValues(alpha: 0.45)),
    );
  }
}

class PropertyListCard extends StatelessWidget {
  const PropertyListCard({
    required this.listing,
    required this.onTap,
    super.key,
  });

  final PropertyListing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      listing.propertyName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  PropertyStatusChip(listing.approvalStatus),
                ],
              ),
              Text(listing.location),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text('RM ${listing.monthlyRent.toStringAsFixed(0)} / month'),
                  Text('${listing.bedrooms} bed'),
                  Text('${listing.bathrooms} bath'),
                  Text('${listing.imageUrls.length} images'),
                ],
              ),
              if (listing.rejectionReason case final reason?) ...[
                const SizedBox(height: 10),
                Text(
                  'Required changes: $reason',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AsyncFailureCard extends StatelessWidget {
  const AsyncFailureCard({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => InlineErrorCard(message: message);
}
