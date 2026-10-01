abstract interface class AppFailure implements Exception {
  String get code;
  String get message;
}

String userFacingErrorMessage(Object? error, {required String fallback}) {
  if (error is AppFailure && error.message.trim().isNotEmpty) {
    return error.message.trim();
  }
  return fallback;
}

bool isConnectivityFailure(Object? error) {
  if (error is! AppFailure) return false;
  final code = error.code.toLowerCase();
  return code.contains('offline') ||
      code.contains('network') ||
      code.contains('unavailable') ||
      code.contains('unreachable') ||
      code.contains('timeout');
}
