import '../../../shared/errors/app_failure.dart';

class ImageVerificationFailure implements AppFailure {
  const ImageVerificationFailure(this.code, this.message);

  @override
  final String code;
  @override
  final String message;

  @override
  String toString() => message;
}
