import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/config/firebase_config.dart';

enum FirebaseBootstrapStatus { ready, notConfigured, failed }

class FirebaseBootstrapResult {
  const FirebaseBootstrapResult._({required this.status, this.message});

  const FirebaseBootstrapResult.ready()
    : this._(status: FirebaseBootstrapStatus.ready);

  const FirebaseBootstrapResult.notConfigured()
    : this._(status: FirebaseBootstrapStatus.notConfigured);

  const FirebaseBootstrapResult.failed(String message)
    : this._(status: FirebaseBootstrapStatus.failed, message: message);

  final FirebaseBootstrapStatus status;
  final String? message;

  bool get isReady => status == FirebaseBootstrapStatus.ready;
}

abstract final class FirebaseBootstrap {
  static Future<FirebaseBootstrapResult> initialize() async {
    const config = FirebaseConfig();
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: config.isConfigured ? config.options : null,
        );
      }
      await FirebaseAppCheck.instance.activate(
        providerAndroid: androidAppCheckProvider(releaseMode: kReleaseMode),
      );
      return const FirebaseBootstrapResult.ready();
    } on FirebaseException {
      if (!config.isConfigured) {
        return const FirebaseBootstrapResult.notConfigured();
      }
      return const FirebaseBootstrapResult.failed(
        'Firebase could not be initialized. Check the application configuration and try again.',
      );
    }
  }
}

AndroidAppCheckProvider androidAppCheckProvider({required bool releaseMode}) =>
    releaseMode
    ? const AndroidPlayIntegrityProvider()
    : const AndroidDebugProvider();

final firebaseBootstrapProvider = Provider<FirebaseBootstrapResult>((ref) {
  throw StateError(
    'Firebase bootstrap must be supplied at application startup.',
  );
});
