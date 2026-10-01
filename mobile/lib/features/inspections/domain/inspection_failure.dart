import '../../../shared/errors/app_failure.dart';

class InspectionFailure implements AppFailure {
  const InspectionFailure(this.code, this.message);

  @override
  final String code;
  @override
  final String message;

  @override
  String toString() => message;
}
