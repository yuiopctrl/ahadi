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

  bool get isNetworkUnavailable => kind == ApiFailureKind.networkUnavailable;

  String get friendlyMessage {
    if (isNetworkUnavailable) {
      return 'No internet connection. Check your connection and try again.';
    }
    return message;
  }

  @override
  String toString() => friendlyMessage;
}
