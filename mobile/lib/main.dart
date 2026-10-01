import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bootstrap = await FirebaseBootstrap.initialize();
  runApp(
    ProviderScope(
      overrides: [firebaseBootstrapProvider.overrideWithValue(bootstrap)],
      child: const PropertyGuidanceApp(),
    ),
  );
}
