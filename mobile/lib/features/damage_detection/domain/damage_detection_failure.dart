import '../../../shared/errors/app_failure.dart';

class DamageDetectionFailure implements AppFailure {
  const DamageDetectionFailure(this.code, this.message);

  @override
  final String code;
  @override
  final String message;

  @override
  String toString() => message;
}
