import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap.dart';
import '../data/firebase_damage_detection_repository.dart';
import '../data/unavailable_damage_detection_repository.dart';
import '../domain/damage_detection_repository.dart';

final damageDetectionRepositoryProvider = Provider<DamageDetectionRepository>((
  ref,
) {
  final bootstrap = ref.watch(firebaseBootstrapProvider);
  return bootstrap.isReady
      ? FirebaseDamageDetectionRepository()
      : const UnavailableDamageDetectionRepository();
});
