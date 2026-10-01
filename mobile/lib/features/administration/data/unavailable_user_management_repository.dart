import '../../auth/domain/app_user.dart';
import '../../auth/domain/auth_failure.dart';
import '../domain/user_management_repository.dart';

class UnavailableUserManagementRepository implements UserManagementRepository {
  const UnavailableUserManagementRepository();

  AuthFailure get _failure => const AuthFailure(
    'firebase-not-configured',
    'Connect the Firebase project before managing accounts.',
  );

  @override
  Future<void> setAccountStatus(String uid, AccountStatus status) async {
    throw _failure;
  }

  @override
  Future<void> updateAgentProfile(AgentProfileInput input) async {
    throw _failure;
  }

  @override
  Stream<List<AppUser>> watchUsers() => Stream.error(_failure);

  @override
  Stream<AppUser?> watchUser(String uid) => Stream.error(_failure);
}
