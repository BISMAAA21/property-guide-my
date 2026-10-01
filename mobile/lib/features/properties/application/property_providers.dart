import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap.dart';
import '../data/firebase_property_repository.dart';
import '../data/unavailable_property_repository.dart';
import '../domain/property_repository.dart';

final propertyRepositoryProvider = Provider<PropertyRepository>((ref) {
  final bootstrap = ref.watch(firebaseBootstrapProvider);
  return bootstrap.isReady
      ? FirebasePropertyRepository()
      : const UnavailablePropertyRepository();
});
