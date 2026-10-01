import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_controller.dart';
import '../domain/auth_snapshot.dart';

class AccountProblemScreen extends ConsumerWidget {
  const AccountProblemScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(authControllerProvider);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final snapshot = controller.snapshot;
        final (title, message) = switch (snapshot.status) {
          AuthSnapshotStatus.disabled => (
            'Account disabled',
            'Your account has been disabled. Contact an administrator if you believe this is a mistake.',
          ),
          AuthSnapshotStatus.missingProfile => (
            'Account setup incomplete',
            'Your secure user profile is missing. Contact an administrator before continuing.',
          ),
          _ => (
            'Account unavailable',
            snapshot.message ?? 'Your account could not be loaded.',
          ),
        };
        return Scaffold(
          appBar: AppBar(title: const Text('Property Guide MY')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_person_outlined, size: 56),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: controller.isBusy ? null : controller.signOut,
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
