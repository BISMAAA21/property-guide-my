import '../../../shared/errors/app_failure.dart';

class ReviewFailure implements AppFailure {
  const ReviewFailure(this.code, this.message);

  @override
  final String code;
  @override
  final String message;

  @override
  String toString() => message;
}
