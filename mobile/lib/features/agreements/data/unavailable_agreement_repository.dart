import 'dart:typed_data';

import '../domain/agreement_failure.dart';
import '../domain/agreement_repository.dart';
import '../domain/agreement_result.dart';

class UnavailableAgreementRepository implements AgreementRepository {
  const UnavailableAgreementRepository();

  AgreementFailure get _failure => const AgreementFailure(
    'firebase-not-configured',
    'Connect Firebase before simplifying tenancy agreements.',
  );

  @override
  Future<AgreementReport> simplifyAndSave({
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async => throw _failure;

  @override
  Stream<List<AgreementReport>> watchReports() => Stream.error(_failure);
}
