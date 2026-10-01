import '../../../shared/errors/app_failure.dart';

class AgreementFailure implements AppFailure {
  const AgreementFailure(this.code, this.message);

  @override
  final String code;
  @override
  final String message;

  @override
  String toString() => message;
}
