import 'dart:typed_data';

import 'agreement_result.dart';

abstract interface class AgreementRepository {
  Stream<List<AgreementReport>> watchReports();

  Future<AgreementReport> simplifyAndSave({
    required Uint8List bytes,
    required String filename,
    required String contentType,
  });
}
