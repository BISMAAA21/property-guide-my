import 'app_user.dart';

enum AuthSnapshotStatus {
  loading,
  configurationRequired,
  signedOut,
  authenticated,
  missingProfile,
  disabled,
  failure,
}

class AuthSnapshot {
  const AuthSnapshot._({required this.status, this.user, this.message});

  const AuthSnapshot.loading() : this._(status: AuthSnapshotStatus.loading);

  const AuthSnapshot.configurationRequired([String? message])
    : this._(
        status: AuthSnapshotStatus.configurationRequired,
        message: message,
      );

  const AuthSnapshot.signedOut() : this._(status: AuthSnapshotStatus.signedOut);

  const AuthSnapshot.authenticated(AppUser user)
    : this._(status: AuthSnapshotStatus.authenticated, user: user);

  const AuthSnapshot.missingProfile()
    : this._(status: AuthSnapshotStatus.missingProfile);

  const AuthSnapshot.disabled(AppUser user)
    : this._(status: AuthSnapshotStatus.disabled, user: user);

  const AuthSnapshot.failure(String message)
    : this._(status: AuthSnapshotStatus.failure, message: message);

  final AuthSnapshotStatus status;
  final AppUser? user;
  final String? message;
}
