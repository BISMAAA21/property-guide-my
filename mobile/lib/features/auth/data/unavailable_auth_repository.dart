import '../domain/auth_repository.dart';
import '../domain/auth_snapshot.dart';
import '../domain/auth_failure.dart';

class UnavailableAuthRepository implements AuthRepository {
  const UnavailableAuthRepository({this.message});

  final String? message;

  @override
  Stream<AuthSnapshot> watchSession() =>
      Stream.value(AuthSnapshot.configurationRequired(message));

  Never _unavailable() {
    throw const AuthFailure(
      'firebase-not-configured',
      'Connect the Firebase project before using authentication.',
    );
  }

  @override
  Future<void> registerStudent({
    required String name,
    required String email,
    required String password,
  }) async => _unavailable();

  @override
  Future<void> sendPasswordReset(String email) async => _unavailable();

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async => _unavailable();

  @override
  Future<void> signOut() async => _unavailable();
}
