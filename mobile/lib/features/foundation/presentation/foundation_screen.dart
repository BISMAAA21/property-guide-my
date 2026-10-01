import 'package:flutter/material.dart';

import '../../../shared/config/app_config.dart';

class FoundationScreen extends StatelessWidget {
  const FoundationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Property Guide MY')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Rental guidance for international students',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'The project foundation is ready. Authentication and protected role experiences '
              'are delivered in Sprint 2.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            const _ModuleCard(
              icon: Icons.school_outlined,
              title: 'Student',
              description: 'Search, verify, inspect, detect damage, and simplify agreements.',
            ),
            const _ModuleCard(
              icon: Icons.real_estate_agent_outlined,
              title: 'Property Agent',
              description:
                  'Create and manage property listings and view their reviews.',
            ),
            const _ModuleCard(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Administrator',
              description:
                  'Manage users, moderate content, and approve listings.',
            ),
            const SizedBox(height: 16),
            Semantics(
              label: 'AI API configuration status',
              child: Chip(
                avatar: const Icon(Icons.lan_outlined),
                label: Text('Local API: ${AppConfig.aiApiBaseUrl}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
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
