import 'auth_snapshot.dart';

abstract interface class AuthRepository {
  Stream<AuthSnapshot> watchSession();

  Future<void> signIn({required String email, required String password});

  Future<void> registerStudent({
    required String name,
    required String email,
    required String password,
  });

  Future<void> sendPasswordReset(String email);

  Future<void> signOut();
}
