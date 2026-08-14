enum ApiFailureKind {
  networkUnavailable,
  unauthenticated,
  forbidden,
  validation,
  conflict,
  server,
  unknown,
}

class ApiFailure implements Exception {
  const ApiFailure({
    required this.kind,
    required this.message,
    this.code,
    this.requestId,
    this.statusCode,
  });

  final ApiFailureKind kind;
  final String message;
  final String? code;
  final String? requestId;
  final int? statusCode;

  bool get isSessionExpired => code == 'SESSION_REQUIRED' || statusCode == 401;

  @override
  String toString() => message;
}
