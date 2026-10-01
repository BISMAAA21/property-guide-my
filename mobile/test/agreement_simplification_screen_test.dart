import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_guidance/features/agreements/application/agreement_providers.dart';
import 'package:property_guidance/features/agreements/data/unavailable_agreement_repository.dart';
import 'package:property_guidance/features/agreements/domain/agreement_failure.dart';
import 'package:property_guidance/features/agreements/domain/agreement_result.dart';
import 'package:property_guidance/features/agreements/presentation/agreement_simplification_screen.dart';

void main() {
  testWidgets(
    'requires privacy consent then saves and displays ordered clauses',
    (tester) async {
      final repository = _AgreementFake();
      tester.view.physicalSize = const Size(900, 1900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agreementRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            home: AgreementSimplificationScreen(
              pickPdf: () async => PickedAgreementPdf(
                name: 'sample-tenancy.pdf',
                bytes: Uint8List.fromList('%PDF-test'.codeUnits),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final chooseButton = find.byKey(const Key('choose_agreement_pdf_button'));
      expect(tester.widget<OutlinedButton>(chooseButton).onPressed, isNull);
      expect(find.byKey(const Key('agreement_legal_notice')), findsOneWidget);
      expect(find.textContaining('external AI provider'), findsOneWidget);

      await tester.tap(find.byKey(const Key('agreement_privacy_consent')));
      await tester.pump();
      await tester.tap(chooseButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.text('sample-tenancy.pdf'), findsOneWidget);
      await tester.tap(find.byKey(const Key('simplify_agreement_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      await tester.scrollUntilVisible(
        find.byKey(const Key('agreement_result_card')),
        400,
        scrollable: find.byType(Scrollable).first,
      );

      expect(repository.calls, 1);
      expect(
        find.byKey(const Key('agreement_result_disclaimer')),
        findsOneWidget,
      );
      expect(find.textContaining('not legal advice'), findsWidgets);
      expect(find.byKey(const Key('agreement_clause-1')), findsOneWidget);
      expect(find.byKey(const Key('agreement_clause-2')), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets('processing failure never displays a successful result', (
    tester,
  ) async {
    final repository = _AgreementFake(
      failure: const AgreementFailure(
        'provider-unavailable',
        'The agreement provider is temporarily unavailable.',
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [agreementRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: AgreementSimplificationScreen(
            pickPdf: () async => PickedAgreementPdf(
              name: 'sample.pdf',
              bytes: Uint8List.fromList('%PDF-test'.codeUnits),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('agreement_privacy_consent')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('choose_agreement_pdf_button')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('simplify_agreement_button')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('simplify_agreement_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('agreement_error')), findsOneWidget);
    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
    expect(find.byKey(const Key('agreement_result_card')), findsNothing);
  });

  testWidgets('free-tier quota failure is shown and cannot become a result', (
    tester,
  ) async {
    final repository = _AgreementFake(
      failure: const AgreementFailure(
        'agreement-api-429',
        'The agreement provider quota is temporarily exhausted.',
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [agreementRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: AgreementSimplificationScreen(
            pickPdf: () async => PickedAgreementPdf(
              name: 'controlled-sample.pdf',
              bytes: Uint8List.fromList('%PDF-test'.codeUnits),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('agreement_privacy_consent')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('choose_agreement_pdf_button')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('simplify_agreement_button')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('simplify_agreement_button')));
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    expect(find.byKey(const Key('agreement_error')), findsOneWidget);
    expect(
      find.textContaining('quota is temporarily exhausted'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('agreement_result_card')), findsNothing);
  });
}

class _AgreementFake extends UnavailableAgreementRepository {
  _AgreementFake({this.failure});

  final AgreementFailure? failure;
  int calls = 0;

  @override
  Stream<List<AgreementReport>> watchReports() => Stream.value(const []);

  @override
  Future<AgreementReport> simplifyAndSave({
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async {
    calls += 1;
    if (failure case final error?) throw error;
    return AgreementReport(
      id: 'agreement-one',
      studentId: 'student-one',
      documentPath:
          'students/student-one/agreements/agreement-one/document.pdf',
      filename: filename,
      result: const AgreementSimplificationResult(
        extractionMethod: AgreementExtractionMethod.mixed,
        clauses: [
          SimplifiedAgreementClause(
            id: 'clause-1',
            title: 'Rent',
            original: '1. RENT\nPay RM 1,500 monthly.',
            simplified: 'You pay RM 1,500 every month.',
            importantPoints: ['Monthly payment'],
          ),
          SimplifiedAgreementClause(
            id: 'clause-2',
            title: 'Deposit',
            original: '2. DEPOSIT\nPay RM 3,000 before moving in.',
            simplified: 'You pay RM 3,000 before moving in.',
            importantPoints: ['Before moving in'],
          ),
        ],
        disclaimer: 'This is simplified information, not legal advice.',
        modelId: 'controlled-model',
      ),
      createdAt: DateTime.utc(2026, 8, 17),
    );
  }
}
