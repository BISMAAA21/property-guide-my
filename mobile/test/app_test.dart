import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_guidance/app/app.dart';
import 'package:property_guidance/app/bootstrap.dart';

void main() {
  testWidgets('unconfigured app explains Firebase requirement and role scope', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseBootstrapProvider.overrideWithValue(
            const FirebaseBootstrapResult.notConfigured(),
          ),
        ],
        child: const PropertyGuidanceApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Firebase connection required'), findsOneWidget);
    expect(find.text('Student experience'), findsOneWidget);
    expect(find.text('Agent experience'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Administrator experience'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Administrator experience'), findsOneWidget);
  });
}
