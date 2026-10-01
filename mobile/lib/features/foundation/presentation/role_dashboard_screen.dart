import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/domain/user_role.dart';

class RoleDashboardScreen extends ConsumerWidget {
  const RoleDashboardScreen({required this.role, super.key});

  final UserRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(authControllerProvider);
    final user = controller.snapshot.user;
    final content = _contentFor(role);
    return Scaffold(
      backgroundColor: content.backgroundColor,
      appBar: AppBar(
        title: Text(content.appBarTitle),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: controller.isBusy ? null : controller.signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Hello, ${user?.name ?? role.displayName}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            Text(content.subtitle),
            const SizedBox(height: 24),
            ...content.actions.map(
              (action) => Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(child: Icon(action.icon)),
                  title: Text(action.title),
                  subtitle: Text(action.subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showPlannedFeature(context, action.title),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: content.destinations,
      ),
    );
  }

  void _showPlannedFeature(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature is scheduled in a later sprint.')),
    );
  }
}

class _DashboardContent {
  const _DashboardContent({
    required this.appBarTitle,
    required this.subtitle,
    required this.backgroundColor,
    required this.actions,
    required this.destinations,
  });

  final String appBarTitle;
  final String subtitle;
  final Color backgroundColor;
  final List<_DashboardAction> actions;
  final List<NavigationDestination> destinations;
}

class _DashboardAction {
  const _DashboardAction(this.icon, this.title, this.subtitle);

  final IconData icon;
  final String title;
  final String subtitle;
}

_DashboardContent _contentFor(UserRole role) => switch (role) {
  UserRole.student => const _DashboardContent(
    appBarTitle: 'Student Home',
    subtitle: 'Find and assess your next rental with guided support.',
    backgroundColor: Color(0xFFF0FDFA),
    actions: [
      _DashboardAction(
        Icons.search,
        'Find a property',
        'Search approved Malaysian student rentals.',
      ),
      _DashboardAction(
        Icons.fact_check_outlined,
        'Guided inspection',
        'Follow a room-by-room checklist.',
      ),
      _DashboardAction(
        Icons.document_scanner_outlined,
        'Understand an agreement',
        'Upload a PDF for clause-by-clause guidance.',
      ),
    ],
    destinations: [
      NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: 'Home',
      ),
      NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
      NavigationDestination(
        icon: Icon(Icons.assignment_outlined),
        label: 'Reports',
      ),
    ],
  ),
  UserRole.agent => const _DashboardContent(
    appBarTitle: 'Agent Workspace',
    subtitle: 'Manage your property portfolio and approval submissions.',
    backgroundColor: Color(0xFFFFFBEB),
    actions: [
      _DashboardAction(
        Icons.add_home_work_outlined,
        'Create listing',
        'Add property details and listing images.',
      ),
      _DashboardAction(
        Icons.inventory_2_outlined,
        'My listings',
        'Review drafts, submissions, and approval status.',
      ),
      _DashboardAction(
        Icons.reviews_outlined,
        'Property reviews',
        'Read student feedback for your properties.',
      ),
    ],
    destinations: [
      NavigationDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: 'Overview',
      ),
      NavigationDestination(icon: Icon(Icons.apartment), label: 'Listings'),
      NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
    ],
  ),
  UserRole.admin => const _DashboardContent(
    appBarTitle: 'Administration',
    subtitle: 'Protect platform quality, accounts, and listing approvals.',
    backgroundColor: Color(0xFFF5F3FF),
    actions: [
      _DashboardAction(
        Icons.approval_outlined,
        'Pending approvals',
        'Review property submissions from agents.',
      ),
      _DashboardAction(
        Icons.manage_accounts_outlined,
        'Manage users',
        'Disable or re-enable platform accounts.',
      ),
      _DashboardAction(
        Icons.shield_outlined,
        'Moderation',
        'Review invalid listings and inappropriate content.',
      ),
    ],
    destinations: [
      NavigationDestination(
        icon: Icon(Icons.space_dashboard_outlined),
        selectedIcon: Icon(Icons.space_dashboard),
        label: 'Overview',
      ),
      NavigationDestination(icon: Icon(Icons.approval), label: 'Approvals'),
      NavigationDestination(icon: Icon(Icons.people_outline), label: 'Users'),
    ],
  ),
};
