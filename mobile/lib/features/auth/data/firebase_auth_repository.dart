import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;

import '../domain/app_user.dart';
import '../domain/auth_failure.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_snapshot.dart';
import '../domain/user_role.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  @override
  Stream<AuthSnapshot> watchSession() {
    late final StreamController<AuthSnapshot> controller;
    StreamSubscription<User?>? authSubscription;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
    profileSubscription;
    var generation = 0;
    var cancelled = false;

    Future<void> replaceProfileSubscription(User? firebaseUser) async {
      final currentGeneration = ++generation;
      final previousSubscription = profileSubscription;
      profileSubscription = null;
      await previousSubscription?.cancel();
      if (cancelled || currentGeneration != generation) return;

      if (firebaseUser == null) {
        controller.add(const AuthSnapshot.signedOut());
        return;
      }

      profileSubscription = _firestore
          .collection('users')
          .doc(firebaseUser.uid)
          .snapshots()
          .listen(
            (document) {
              if (cancelled || currentGeneration != generation) return;
              controller.add(_snapshotFromDocument(firebaseUser, document));
            },
            onError: (Object _, StackTrace stackTrace) {
              if (cancelled || currentGeneration != generation) return;
              if (_auth.currentUser == null) {
                controller.add(const AuthSnapshot.signedOut());
                return;
              }
              controller.addError(
                const AuthFailure(
                  'profile-read-failed',
                  'Your account profile could not be loaded.',
                ),
                stackTrace,
              );
            },
          );
    }

    controller = StreamController<AuthSnapshot>(
      onListen: () {
        authSubscription = _auth.authStateChanges().listen(
          (firebaseUser) {
            unawaited(replaceProfileSubscription(firebaseUser));
          },
          onError: (Object _, StackTrace stackTrace) {
            controller.addError(
              const AuthFailure(
                'session-read-failed',
                'Your account session could not be loaded.',
              ),
              stackTrace,
            );
          },
        );
      },
      onCancel: () async {
        cancelled = true;
        generation++;
        await profileSubscription?.cancel();
        await authSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  static AuthSnapshot _snapshotFromDocument(
    User firebaseUser,
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    if (!document.exists) {
      return const AuthSnapshot.missingProfile();
    }

    final data = document.data();
    final role = UserRole.fromStoredValue(data?['role'] as String?);
    final status = _readStatus(data?['status']);
    if (data == null || role == null || status == null) {
      return const AuthSnapshot.failure(
        'Your account profile is invalid. Contact an administrator.',
      );
    }

    final user = AppUser(
      uid: firebaseUser.uid,
      name: (data['name'] as String?)?.trim().isNotEmpty == true
          ? (data['name'] as String).trim()
          : firebaseUser.email ?? 'User',
      email: firebaseUser.email ?? (data['email'] as String? ?? ''),
      role: role,
      status: status,
      agencyName: (data['agencyName'] as String?)?.trim(),
      phone: (data['phone'] as String?)?.trim(),
      registrationNumber: (data['registrationNumber'] as String?)?.trim(),
    );
    return user.isDisabled
        ? AuthSnapshot.disabled(user)
        : AuthSnapshot.authenticated(user);
  }

  @override
  Future<void> registerStudent({
    required String name,
    required String email,
    required String password,
  }) async {
    UserCredential? credential;
    try {
      credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final firebaseUser = credential.user;
      if (firebaseUser == null) {
        throw const AuthFailure(
          'registration-failed',
          'The student account could not be created.',
        );
      }

      await firebaseUser.updateDisplayName(name.trim());
      await _firestore.collection('users').doc(firebaseUser.uid).set({
        'name': name.trim(),
        'email': email.trim().toLowerCase(),
        'role': UserRole.student.name,
        'status': AccountStatus.active.name,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseAuthException catch (error) {
      throw _mapAuthError(error);
    } on FirebaseException catch (error) {
      if (credential?.user != null) {
        await credential!.user!.delete().catchError((_) {});
      }
      throw AuthFailure(
        error.code,
        'The student profile could not be created. Please try again.',
      );
    }
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      throw _mapAuthError(error);
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      throw _mapAuthError(error);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  static AccountStatus? _readStatus(Object? value) => switch (value) {
    'active' => AccountStatus.active,
    'disabled' => AccountStatus.disabled,
    _ => null,
  };

  static AuthFailure _mapAuthError(FirebaseAuthException error) {
    final message = switch (error.code) {
      'invalid-email' => 'Enter a valid email address.',
      'user-disabled' => 'This account has been disabled.',
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' => 'The email or password is incorrect.',
      'email-already-in-use' => 'An account already uses this email address.',
      'weak-password' => 'Use a password with at least six characters.',
      'too-many-requests' => 'Too many attempts. Please wait and try again.',
      'network-request-failed' =>
        'Check your internet connection and try again.',
      _ => 'Authentication failed. Please try again.',
    };
    return AuthFailure(error.code, message);
  }
}
