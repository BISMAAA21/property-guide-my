import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/errors/app_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../application/user_management_providers.dart';
import '../domain/user_management_repository.dart';

class AgentProfileScreen extends ConsumerStatefulWidget {
  const AgentProfileScreen({super.key});

  @override
  ConsumerState<AgentProfileScreen> createState() => _AgentProfileScreenState();
}

class _AgentProfileScreenState extends ConsumerState<AgentProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _agency = TextEditingController();
  final _phone = TextEditingController();
  final _registration = TextEditingController();
  bool _initialized = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _agency.dispose();
    _phone.dispose();
    _registration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).snapshot.user!;
    if (!_initialized) {
      _initialized = true;
      _name.text = user.name;
      _agency.text = user.agencyName ?? '';
      _phone.text = user.phone ?? '';
      _registration.text = user.registrationNumber ?? '';
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Agent profile')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(user.email, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 20),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value?.trim().length ?? 0) < 2
                    ? 'Enter your full name.'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _agency,
                decoration: const InputDecoration(
                  labelText: 'Agency name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value?.trim().length ?? 0) < 2
                    ? 'Enter the agency name.'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Contact number',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final length = value?.trim().length ?? 0;
                  return length < 7 || length > 24
                      ? 'Enter a valid contact number.'
                      : null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _registration,
                decoration: const InputDecoration(
                  labelText: 'Agent registration number',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value?.trim().length ?? 0) < 3
                    ? 'Enter a registration number.'
                    : null,
              ),
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(userManagementRepositoryProvider)
          .updateAgentProfile(
            AgentProfileInput(
              name: _name.text,
              agencyName: _agency.text,
              phone: _phone.text,
              registrationNumber: _registration.text,
            ),
          );
      if (mounted) context.go('/agent');
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = userFacingErrorMessage(
            error,
            fallback: 'The agent profile could not be saved.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
