import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap.dart';
import '../data/firebase_inspection_repository.dart';
import '../data/unavailable_inspection_repository.dart';
import '../domain/inspection_repository.dart';

final inspectionRepositoryProvider = Provider<InspectionRepository>((ref) {
  final bootstrap = ref.watch(firebaseBootstrapProvider);
  return bootstrap.isReady
      ? FirebaseInspectionRepository()
      : const UnavailableInspectionRepository();
});
