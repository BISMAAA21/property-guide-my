import '../../../shared/errors/app_failure.dart';

class PropertyFailure implements AppFailure {
  const PropertyFailure(this.code, this.message);

  @override
  final String code;
  @override
  final String message;

  @override
  String toString() => message;
}
