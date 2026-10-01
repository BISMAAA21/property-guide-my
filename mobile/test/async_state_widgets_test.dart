import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_guidance/features/properties/domain/property_failure.dart';
import 'package:property_guidance/shared/presentation/async_state_widgets.dart';

void main() {
  testWidgets('unknown errors are replaced by a safe fallback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AsyncErrorView(
            error: Exception('internal server and credential details'),
            fallback: 'The content could not be loaded.',
          ),
        ),
      ),
    );

    expect(find.text('The content could not be loaded.'), findsOneWidget);
    expect(find.textContaining('credential details'), findsNothing);
  });

  testWidgets('typed connectivity error offers clear status and retry', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AsyncErrorView(
            error: const PropertyFailure(
              'firebase-unavailable',
              'Properties are temporarily unavailable.',
            ),
            fallback: 'Fallback message.',
            onRetry: () => retries += 1,
          ),
        ),
      ),
    );

    expect(
      find.text('Properties are temporarily unavailable.'),
      findsOneWidget,
    );
    expect(find.textContaining('Check your connection'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    await tester.tap(find.byKey(const Key('async_retry_button')));
    expect(retries, 1);
  });

  testWidgets('loading state exposes a descriptive live-region label', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AsyncLoadingView(label: 'Loading approved properties'),
        ),
      ),
    );

    expect(find.text('Loading approved properties'), findsOneWidget);
    final semantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byType(AsyncLoadingView),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(semantics.properties.label, 'Loading approved properties');
    expect(semantics.properties.liveRegion, isTrue);
  });
}
