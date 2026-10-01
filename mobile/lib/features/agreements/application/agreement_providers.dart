import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap.dart';
import '../data/firebase_agreement_repository.dart';
import '../data/unavailable_agreement_repository.dart';
import '../domain/agreement_repository.dart';

final agreementRepositoryProvider = Provider<AgreementRepository>((ref) {
  final bootstrap = ref.watch(firebaseBootstrapProvider);
  return bootstrap.isReady
      ? FirebaseAgreementRepository()
      : const UnavailableAgreementRepository();
});
