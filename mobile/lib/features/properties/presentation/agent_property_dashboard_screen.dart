import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/presentation/async_state_widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../application/property_providers.dart';
import '../domain/property_listing.dart';
import 'property_widgets.dart';

class AgentPropertyDashboardScreen extends ConsumerWidget {
  const AgentPropertyDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.snapshot.user!;
    final repository = ref.watch(propertyRepositoryProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBEB),
      appBar: AppBar(
        title: const Text('Agent Workspace'),
        actions: [
          IconButton(
            tooltip: 'Edit agent profile',
            onPressed: () => context.push('/agent/profile'),
            icon: const Icon(Icons.account_circle_outlined),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: auth.isBusy ? null : auth.signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/agent/properties/new'),
        icon: const Icon(Icons.add_home_work_outlined),
        label: const Text('New listing'),
      ),
      body: StreamBuilder<List<PropertyListing>>(
        stream: repository.watchOwnedListings(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AsyncLoadingView(label: 'Loading your properties');
          }
          if (snapshot.hasError) {
            return AsyncErrorView(
              error: snapshot.error,
              fallback: 'Your properties could not be loaded.',
            );
          }
          final listings = snapshot.data ?? const [];
          final counts = {
            for (final status in PropertyApprovalStatus.values)
              status: listings
                  .where((listing) => listing.approvalStatus == status)
                  .length,
          };
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
            children: [
              Text(
                'Hello, ${user.name}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const Text('Manage owned listings and approval submissions.'),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: PropertyApprovalStatus.values
                    .map(
                      (status) => _CountCard(
                        label: status.displayName,
                        count: counts[status] ?? 0,
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 24),
              Text(
                'My listings',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (listings.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No listings yet. Create a draft to get started.',
                    ),
                  ),
                )
              else
                ...listings.map(
                  (listing) => PropertyListCard(
                    listing: listing,
                    onTap: () =>
                        context.push('/agent/properties/${listing.id}'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$count', style: Theme.of(context).textTheme.headlineSmall),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
