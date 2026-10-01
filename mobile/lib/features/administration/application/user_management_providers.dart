import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap.dart';
import '../data/firebase_user_management_repository.dart';
import '../data/unavailable_user_management_repository.dart';
import '../domain/user_management_repository.dart';

final userManagementRepositoryProvider = Provider<UserManagementRepository>((
  ref,
) {
  final bootstrap = ref.watch(firebaseBootstrapProvider);
  return bootstrap.isReady
      ? FirebaseUserManagementRepository()
      : const UnavailableUserManagementRepository();
});
