import 'package:flutter_test/flutter_test.dart';
import 'package:property_guidance/features/agreements/domain/agreement_result.dart';

void main() {
  test('parses ordered clause response with required legal disclaimer', () {
    final result = AgreementSimplificationResult.fromJson(_validResponse());

    expect(result.extractionMethod, AgreementExtractionMethod.mixed);
    expect(result.clauses.map((clause) => clause.id), ['clause-1', 'clause-2']);
    expect(result.clauses.first.original, '1. RENT\nPay RM 1,500 monthly.');
    expect(result.clauses.first.importantPoints, ['RM 1,500', 'Monthly']);
  });

  test('rejects missing or reordered clauses', () {
    final response = _validResponse();
    response['clauses'] = [
      (response['clauses']! as List)[1],
      (response['clauses']! as List)[0],
    ];

    expect(
      () => AgreementSimplificationResult.fromJson(response),
      throwsFormatException,
    );
  });

  test('rejects output that does not disclose it is not legal advice', () {
    final response = _validResponse();
    response['disclaimer'] = 'This result is guaranteed.';

    expect(
      () => AgreementSimplificationResult.fromJson(response),
      throwsFormatException,
    );
  });

  test('validates PDF type and size before upload', () {
    expect(
      const AgreementPdfInput(
        byteLength: 5,
        contentType: 'application/pdf',
      ).validate(),
      isNull,
    );
    expect(
      const AgreementPdfInput(
        byteLength: AgreementPdfInput.maxBytes + 1,
        contentType: 'application/pdf',
      ).validate(),
      contains('10 MiB'),
    );
    expect(
      const AgreementPdfInput(
        byteLength: 5,
        contentType: 'text/plain',
      ).validate(),
      contains('PDF'),
    );
  });
}

Map<String, dynamic> _validResponse() => {
  'extractionMethod': 'mixed',
  'clauses': [
    {
      'id': 'clause-1',
      'title': 'Rent',
      'original': '1. RENT\nPay RM 1,500 monthly.',
      'simplified': 'You pay RM 1,500 every month.',
      'importantPoints': ['RM 1,500', 'Monthly'],
    },
    {
      'id': 'clause-2',
      'title': 'Deposit',
      'original': '2. DEPOSIT\nPay RM 3,000 before moving in.',
      'simplified': 'You pay RM 3,000 before moving in.',
      'importantPoints': ['RM 3,000'],
    },
  ],
  'disclaimer': 'This is simplified information, not legal advice.',
  'modelId': 'controlled-model',
};
