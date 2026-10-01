import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/presentation/async_state_widgets.dart';
import '../../administration/application/user_management_providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/domain/user_role.dart';
import '../../reviews/presentation/property_reviews_panel.dart';
import '../application/property_providers.dart';
import '../domain/property_listing.dart';

class StudentPropertyDetailScreen extends ConsumerWidget {
  const StudentPropertyDetailScreen({required this.propertyId, super.key});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(propertyRepositoryProvider);
    final student = ref.watch(authControllerProvider).snapshot.user!;
    return StreamBuilder<PropertyListing?>(
      stream: repository.watchListing(propertyId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: AsyncLoadingView(label: 'Loading property details'),
          );
        }
        final listing = snapshot.data;
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Property details')),
            body: AsyncErrorView(
              error: snapshot.error,
              fallback: 'The property details could not be loaded.',
            ),
          );
        }
        if (listing == null ||
            listing.approvalStatus != PropertyApprovalStatus.approved) {
          return Scaffold(
            appBar: AppBar(title: const Text('Property details')),
            body: const AsyncEmptyView(
              message: 'This property is no longer available to students.',
              icon: Icons.home_work_outlined,
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Property details')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            children: [
              Text(
                listing.propertyName,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(
                listing.location,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              _PropertyImages(listing.imageUrls),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
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
                  _Fact(
                    icon: Icons.star,
                    label: listing.ratingCount == 0
                        ? 'No ratings yet'
                        : '${listing.ratingAverage.toStringAsFixed(1)} from ${listing.ratingCount}',
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                'Description',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(listing.description),
              if (listing.facilities.isNotEmpty) ...[
                const SizedBox(height: 22),
                Text(
                  'Facilities',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: listing.facilities
                      .map(
                        (facility) => Chip(
                          avatar: const Icon(Icons.check, size: 17),
                          label: Text(facility),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              const SizedBox(height: 24),
              _AgentInformation(agentId: listing.agentId),
              const SizedBox(height: 24),
              Text(
                'Property guidance',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('verify_property_button'),
                onPressed: () =>
                    context.push('/student/properties/${listing.id}/verify'),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Verify during a visit'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('damage_detection_button'),
                onPressed: () =>
                    context.push('/student/properties/${listing.id}/damage'),
                icon: const Icon(Icons.biotech_outlined),
                label: const Text('Check a damage photo'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('guided_inspection_button'),
                onPressed: () => context.push(
                  '/student/properties/${listing.id}/inspection',
                ),
                icon: const Icon(Icons.checklist_outlined),
                label: const Text('Start guided inspection'),
              ),
              const SizedBox(height: 28),
              PropertyReviewsPanel(
                propertyId: listing.id,
                role: UserRole.student,
                currentUserId: student.uid,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PropertyImages extends StatelessWidget {
  const _PropertyImages(this.urls);

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: const Text('No property images are available.'),
      );
    }
    return SizedBox(
      height: 220,
      child: PageView.builder(
        itemCount: urls.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  urls[index],
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Center(child: Icon(Icons.broken_image_outlined)),
                ),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Chip(label: Text('${index + 1} / ${urls.length}')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentInformation extends ConsumerWidget {
  const _AgentInformation({required this.agentId});

  final String agentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<AppUser?>(
      stream: ref.watch(userManagementRepositoryProvider).watchUser(agentId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: LinearProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return AsyncErrorView(
            error: snapshot.error,
            fallback: 'The listing agent information is unavailable.',
            compact: true,
          );
        }
        final agent = snapshot.data!;
        return Card(
          key: const Key('agent_information_card'),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Listing agent',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                _AgentLine(icon: Icons.person_outline, value: agent.name),
                if (agent.agencyName case final value?)
                  _AgentLine(icon: Icons.business_outlined, value: value),
                if (agent.phone case final value?)
                  _AgentLine(icon: Icons.phone_outlined, value: value),
                if (agent.registrationNumber case final value?)
                  _AgentLine(
                    icon: Icons.badge_outlined,
                    value: 'Registration $value',
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AgentLine extends StatelessWidget {
  const _AgentLine({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 19),
          const SizedBox(width: 9),
          Expanded(child: Text(value)),
        ],
      ),
    );
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
