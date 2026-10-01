import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/errors/app_failure.dart';
import '../../../shared/presentation/async_state_widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/domain/user_role.dart';
import '../../properties/application/property_providers.dart';
import '../../properties/domain/property_listing.dart';
import '../../properties/presentation/property_widgets.dart';
import '../application/user_management_providers.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  String _query = '';
  String? _actionError;
  String? _busyUserId;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final propertyRepository = ref.watch(propertyRepositoryProvider);
    final userRepository = ref.watch(userManagementRepositoryProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F3FF),
      appBar: AppBar(
        title: const Text('Administration'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: auth.isBusy ? null : auth.signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: StreamBuilder<List<AppUser>>(
        stream: userRepository.watchUsers(),
        builder: (context, userSnapshot) {
          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const AsyncLoadingView(label: 'Loading user accounts');
          }
          if (userSnapshot.hasError) {
            return AsyncErrorView(
              error: userSnapshot.error,
              fallback: 'User accounts could not be loaded.',
            );
          }
          return StreamBuilder<List<PropertyListing>>(
            stream: propertyRepository.watchAllListings(),
            builder: (context, propertySnapshot) {
              if (propertySnapshot.connectionState == ConnectionState.waiting) {
                return const AsyncLoadingView(
                  label: 'Loading property approvals',
                );
              }
              if (propertySnapshot.hasError) {
                return AsyncErrorView(
                  error: propertySnapshot.error,
                  fallback: 'Property approvals could not be loaded.',
                );
              }
              return _buildContent(
                context,
                userSnapshot.data ?? const [],
                propertySnapshot.data ?? const [],
                auth.snapshot.user!.uid,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<AppUser> users,
    List<PropertyListing> properties,
    String currentAdminId,
  ) {
    final pending = properties
        .where((item) => item.approvalStatus == PropertyApprovalStatus.pending)
        .toList(growable: false);
    final normalizedQuery = _query.trim().toLowerCase();
    final visibleUsers = users
        .where((user) {
          if (normalizedQuery.isEmpty) return true;
          return user.name.toLowerCase().contains(normalizedQuery) ||
              user.email.toLowerCase().contains(normalizedQuery) ||
              user.role.name.contains(normalizedQuery);
        })
        .toList(growable: false);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        Text(
          'System overview',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _AdminCount(
              label: 'Students',
              count: users
                  .where((user) => user.role == UserRole.student)
                  .length,
            ),
            _AdminCount(
              label: 'Agents',
              count: users.where((user) => user.role == UserRole.agent).length,
            ),
            _AdminCount(label: 'Properties', count: properties.length),
            _AdminCount(
              label: 'Pending',
              count: pending.length,
              urgent: pending.isNotEmpty,
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text(
          'Pending property approvals',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (pending.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('No listings are waiting for review.'),
            ),
          )
        else
          ...pending.map(
            (listing) => PropertyListCard(
              listing: listing,
              onTap: () => context.push('/admin/properties/${listing.id}'),
            ),
          ),
        const SizedBox(height: 28),
        Text('All properties', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        ...properties
            .take(10)
            .map(
              (listing) => PropertyListCard(
                listing: listing,
                onTap: () => context.push('/admin/properties/${listing.id}'),
              ),
            ),
        if (properties.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('No properties have been created.'),
            ),
          ),
        const SizedBox(height: 28),
        Text(
          'User and agent management',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Search users by name, email, or role',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        if (_actionError case final error?) ...[
          const SizedBox(height: 10),
          AsyncFailureCard(message: error),
        ],
        const SizedBox(height: 10),
        ...visibleUsers.map(
          (user) => Card(
            child: ListTile(
              leading: CircleAvatar(child: Icon(_iconFor(user.role))),
              title: Text(user.name),
              subtitle: Text(
                '${user.email}\n${user.role.displayName} · ${user.status.name}',
              ),
              isThreeLine: true,
              trailing: user.uid == currentAdminId
                  ? const Tooltip(
                      message: 'Current administrator',
                      child: Icon(Icons.verified_user_outlined),
                    )
                  : Switch(
                      value: user.status == AccountStatus.active,
                      onChanged: _busyUserId == user.uid
                          ? null
                          : (active) => _setStatus(
                              user,
                              active
                                  ? AccountStatus.active
                                  : AccountStatus.disabled,
                            ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _setStatus(AppUser user, AccountStatus status) async {
    final verb = status == AccountStatus.disabled ? 'Disable' : 'Re-enable';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$verb ${user.name}?'),
        content: Text(
          status == AccountStatus.disabled
              ? 'The user will lose application and data access.'
              : 'The user will regain access according to their assigned role.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(verb),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _busyUserId = user.uid;
      _actionError = null;
    });
    try {
      await ref
          .read(userManagementRepositoryProvider)
          .setAccountStatus(user.uid, status);
    } catch (error) {
      if (mounted) {
        setState(
          () => _actionError = userFacingErrorMessage(
            error,
            fallback: 'The account status could not be changed.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  static IconData _iconFor(UserRole role) => switch (role) {
    UserRole.student => Icons.school_outlined,
    UserRole.agent => Icons.real_estate_agent_outlined,
    UserRole.admin => Icons.admin_panel_settings_outlined,
  };
}

class _AdminCount extends StatelessWidget {
  const _AdminCount({
    required this.label,
    required this.count,
    this.urgent = false,
  });

  final String label;
  final int count;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: urgent
            ? Theme.of(context).colorScheme.tertiaryContainer
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$count', style: Theme.of(context).textTheme.headlineSmall),
          Text(label),
        ],
      ),
    );
  }
}
