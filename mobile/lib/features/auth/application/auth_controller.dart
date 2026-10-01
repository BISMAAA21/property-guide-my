import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap.dart';
import '../data/firebase_auth_repository.dart';
import '../data/unavailable_auth_repository.dart';
import '../domain/auth_failure.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_snapshot.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final bootstrap = ref.watch(firebaseBootstrapProvider);
  if (bootstrap.isReady) {
    return FirebaseAuthRepository();
  }
  return UnavailableAuthRepository(message: bootstrap.message);
});

final authControllerProvider = Provider<AuthController>((ref) {
  final controller = AuthController(ref.watch(authRepositoryProvider));
  ref.onDispose(controller.dispose);
  return controller;
});

class AuthController extends ChangeNotifier {
  AuthController(this._repository) {
    _subscription = _repository.watchSession().listen(
      _onSnapshot,
      onError: _onStreamError,
    );
  }

  final AuthRepository _repository;
  late final StreamSubscription<AuthSnapshot> _subscription;

  AuthSnapshot _snapshot = const AuthSnapshot.loading();
  bool _isBusy = false;
  String? _actionError;
  String? _notice;

  AuthSnapshot get snapshot => _snapshot;
  bool get isBusy => _isBusy;
  String? get actionError => _actionError;
  String? get notice => _notice;

  Future<bool> signIn({required String email, required String password}) {
    return _run(() => _repository.signIn(email: email, password: password));
  }

  Future<bool> registerStudent({
    required String name,
    required String email,
    required String password,
  }) {
    return _run(
      () => _repository.registerStudent(
        name: name,
        email: email,
        password: password,
      ),
    );
  }

  Future<bool> sendPasswordReset(String email) async {
    final succeeded = await _run(() => _repository.sendPasswordReset(email));
    if (succeeded) {
      _notice = 'Password reset instructions were sent if that account exists.';
      notifyListeners();
    }
    return succeeded;
  }

  Future<void> signOut() async {
    final succeeded = await _run(_repository.signOut);
    if (succeeded && _snapshot.status != AuthSnapshotStatus.signedOut) {
      _snapshot = const AuthSnapshot.signedOut();
      notifyListeners();
    }
  }

  void clearMessages() {
    if (_actionError == null && _notice == null) return;
    _actionError = null;
    _notice = null;
    notifyListeners();
  }

  Future<bool> _run(Future<void> Function() action) async {
    if (_isBusy) return false;
    _isBusy = true;
    _actionError = null;
    _notice = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on AuthFailure catch (failure) {
      _actionError = failure.message;
      return false;
    } catch (_) {
      _actionError = 'Something went wrong. Please try again.';
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  void _onSnapshot(AuthSnapshot snapshot) {
    _snapshot = snapshot;
    notifyListeners();
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    if (_snapshot.status == AuthSnapshotStatus.signedOut) return;
    _snapshot = AuthSnapshot.failure(
      error is AuthFailure
          ? error.message
          : 'Your account session could not be loaded.',
    );
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
