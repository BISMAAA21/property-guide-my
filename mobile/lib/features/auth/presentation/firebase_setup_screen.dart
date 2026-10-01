import 'package:flutter/material.dart';

import '../../../shared/config/app_config.dart';

class FirebaseSetupScreen extends StatelessWidget {
  const FirebaseSetupScreen({super.key, this.errorMessage});

  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Property Guide MY')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(
              Icons.settings_suggest_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Firebase connection required',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            const Text(
              'The application shell is installed, but authentication remains locked until the project owner selects a Firebase project and supplies its Android configuration.',
            ),
            if (errorMessage case final message?) ...[
              const SizedBox(height: 12),
              Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            const _RolePreview(
              icon: Icons.school_outlined,
              title: 'Student experience',
              description: 'Search, inspect, verify images, detect damage, and understand agreements.',
            ),
            const _RolePreview(
              icon: Icons.real_estate_agent_outlined,
              title: 'Agent experience',
              description: 'Manage owned listings, approval status, profile, and reviews.',
            ),
            const _RolePreview(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Administrator experience',
              description: 'Manage accounts, approve listings, moderate content, and review counts.',
            ),
            const SizedBox(height: 16),
            Chip(
              avatar: const Icon(Icons.lan_outlined),
              label: Text('AI API: ${AppConfig.aiApiBaseUrl}'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RolePreview extends StatelessWidget {
  const _RolePreview({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Icon(icon, size: 32),
        title: Text(title),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(description),
        ),
      ),
    );
  }
}
