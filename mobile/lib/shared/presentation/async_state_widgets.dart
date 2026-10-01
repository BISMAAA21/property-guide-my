import 'package:flutter/material.dart';

import '../errors/app_failure.dart';

class AsyncLoadingView extends StatelessWidget {
  const AsyncLoadingView({
    required this.label,
    this.compact = false,
    super.key,
  });

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = Semantics(
      liveRegion: true,
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
    return compact
        ? Padding(padding: const EdgeInsets.all(16), child: content)
        : Center(
            child: Padding(padding: const EdgeInsets.all(24), child: content),
          );
  }
}

class AsyncErrorView extends StatelessWidget {
  const AsyncErrorView({
    required this.error,
    required this.fallback,
    this.onRetry,
    this.compact = false,
    super.key,
  });

  final Object? error;
  final String fallback;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final offline = isConnectivityFailure(error);
    final content = Semantics(
      liveRegion: true,
      child: Card(
        key: const Key('async_error_state'),
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(offline ? Icons.cloud_off_outlined : Icons.error_outline),
              const SizedBox(height: 8),
              Text(
                userFacingErrorMessage(error, fallback: fallback),
                textAlign: TextAlign.center,
              ),
              if (offline) ...[
                const SizedBox(height: 6),
                const Text(
                  'Check your connection. Live Firebase screens reconnect automatically.',
                  textAlign: TextAlign.center,
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const Key('async_retry_button'),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return compact
        ? content
        : Center(
            child: Padding(padding: const EdgeInsets.all(20), child: content),
          );
  }
}

class AsyncEmptyView extends StatelessWidget {
  const AsyncEmptyView({
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.compact = false,
    super.key,
  });

  final String message;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = Semantics(
      label: message,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
    return compact
        ? Padding(padding: const EdgeInsets.all(16), child: content)
        : Center(
            child: Padding(padding: const EdgeInsets.all(24), child: content),
          );
  }
}

class InlineErrorCard extends StatelessWidget {
  const InlineErrorCard({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.error_outline),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }
}
