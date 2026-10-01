import '../../../shared/errors/app_failure.dart';

class AuthFailure implements AppFailure {
  const AuthFailure(this.code, this.message);

  @override
  final String code;
  @override
  final String message;

  @override
  String toString() => message;
}
