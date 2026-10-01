import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/auth_controller.dart';
import 'auth_form_scaffold.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(authControllerProvider);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => AuthFormScaffold(
        title: 'Reset password',
        subtitle: 'Enter your account email to request reset instructions.',
        children: [
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email address',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value?.contains('@') ?? false)
                      ? null
                      : 'Enter a valid email address.',
                ),
                if (controller.actionError case final error?) ...[
                  const SizedBox(height: 12),
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (controller.notice case final notice?) ...[
                  const SizedBox(height: 12),
                  Text(notice),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: controller.isBusy
                      ? null
                      : () async {
                          if (!_formKey.currentState!.validate()) return;
                          await controller.sendPasswordReset(
                            _emailController.text,
                          );
                        },
                  child: const Text('Send reset instructions'),
                ),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Back to sign in'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
