// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../auth/auth_models.dart';
import '../config/app_config.dart';
import '../errors/api_failure.dart';
import 'platform_api.dart';

typedef AccessTokenProvider = Future<String?> Function();

class ApiClient implements PlatformApi {
  ApiClient({
    required AppConfig config,
    required AccessTokenProvider accessTokenProvider,
    HttpClient? httpClient,
  }) : _config = config,
       _accessTokenProvider = accessTokenProvider,
       _httpClient = httpClient ?? HttpClient();

  final AppConfig _config;
  final AccessTokenProvider _accessTokenProvider;
  final HttpClient _httpClient;

  @override
  Future<SessionCredentials> loginWithPin({
    required String phone,
    required String pin,
  }) async {
    final json = await _request(
      '/auth/login-pin',
      method: 'POST',
      auth: false,
      body: {'phone': phone, 'pin': pin},
    );
    return SessionCredentials.fromJson(jsonMap(json['session']));
  }

  @override
  Future<void> requestOtp(String phone) async {
    await _request(
      '/auth/request-otp',
      method: 'POST',
      auth: false,
      body: {'phone': phone},
    );
  }

  @override
  Future<SessionCredentials> verifyOtp({
    required String phone,
    required String token,
  }) async {
    final json = await _request(
      '/auth/verify-otp',
      method: 'POST',
      auth: false,
      body: {'phone': phone, 'token': token},
    );
    return SessionCredentials.fromJson(jsonMap(json['session']));
  }

  @override
  Future<void> setPin(String pin) async {
    await _request('/auth/set-pin', method: 'POST', body: {'pin': pin});
  }

  @override
  Future<PlatformSession> me() async {
    final json = await _request('/me');
    return PlatformSession.fromJson(jsonMap(json['data']));
  }

  @override
  Future<void> logout() async {
    await _request('/auth/logout', method: 'POST');
  }

  @override
  Future<Map<String, dynamic>> dashboard() async {
    final json = await _request('/platform/dashboard');
    return jsonMap(json['data']);
  }

  @override
  Future<List<Map<String, dynamic>>> listOrganizations() async {
    final json = await _request('/platform/tenants');
    return jsonList(json['data']);
  }

  @override
  Future<Map<String, dynamic>> organizationDetail(String tenantId) async {
    final json = await _request('/platform/tenants/$tenantId');
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> setOrganizationStatus({
    required String tenantId,
    required String status,
    String? reason,
  }) async {
    final json = await _request(
      '/platform/tenants/$tenantId/status',
      method: 'POST',
      body: {'status': status, 'reason': ?reason},
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> extendTrial({
    required String tenantId,
    required int days,
    required String reason,
  }) async {
    final json = await _request(
      '/platform/tenants/$tenantId/trial/extend',
      method: 'POST',
      body: {'days': days, 'reason': reason},
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> startSupportSession({
    required String tenantId,
    required String reason,
    int? durationMinutes,
  }) async {
    final json = await _request(
      '/platform/tenants/$tenantId/support-session',
      method: 'POST',
      body: {'reason': reason, 'durationMinutes': ?durationMinutes},
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> changeSubscriptionPlan({
    required String tenantId,
    required String planId,
    required String reason,
  }) async {
    final json = await _request(
      '/platform/tenants/$tenantId/subscription/plan',
      method: 'POST',
      body: {'planId': planId, 'reason': reason},
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> setSubscriptionStatus({
    required String tenantId,
    required String status,
    required String reason,
  }) async {
    final json = await _request(
      '/platform/tenants/$tenantId/subscription/status',
      method: 'POST',
      body: {'status': status, 'reason': reason},
    );
    return jsonMap(json['data']);
  }

  @override
  Future<List<Map<String, dynamic>>> listPlans() async {
    final json = await _request('/platform/plans');
    return jsonList(json['data']);
  }

  @override
  Future<Map<String, dynamic>> createPlan(Map<String, dynamic> input) async {
    final json = await _request('/platform/plans', method: 'POST', body: input);
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> updatePlan(
    String planId,
    Map<String, dynamic> input,
  ) async {
    final json = await _request(
      '/platform/plans/$planId',
      method: 'PUT',
      body: input,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<List<Map<String, dynamic>>> listPlatformUsers() async {
    final json = await _request('/platform/users');
    return jsonList(json['data']);
  }

  @override
  Future<Map<String, dynamic>> addPlatformUser({
    required String phoneE164,
    required String role,
  }) async {
    final json = await _request(
      '/platform/users',
      method: 'POST',
      body: {'phoneE164': phoneE164, 'role': role},
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> setPlatformUserRole({
    required String platformUserId,
    required String role,
  }) async {
    final json = await _request(
      '/platform/users/$platformUserId/role',
      method: 'PATCH',
      body: {'role': role},
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> setPlatformUserStatus({
    required String platformUserId,
    required String status,
    String? reason,
  }) async {
    final json = await _request(
      '/platform/users/$platformUserId/status',
      method: 'PATCH',
      body: {'status': status, 'reason': ?reason},
    );
    return jsonMap(json['data']);
  }

  @override
  Future<List<Map<String, dynamic>>> listSupportRequests() async {
    final json = await _request('/platform/support');
    return jsonList(json['data']);
  }

  @override
  Future<Map<String, dynamic>> updateSupportRequest(
    String supportRequestId,
    Map<String, dynamic> input,
  ) async {
    final json = await _request(
      '/platform/support/$supportRequestId',
      method: 'POST',
      body: input,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> listAuditLog({
    String? action,
    String? tenantId,
    String? entityType,
    int? beforeId,
    int limit = 50,
  }) async {
    final query = Uri(
      queryParameters: {
        if (action != null && action.isNotEmpty) 'action': action,
        if (tenantId != null && tenantId.isNotEmpty) 'tenantId': tenantId,
        if (entityType != null && entityType.isNotEmpty)
          'entityType': entityType,
        if (beforeId != null) 'beforeId': '$beforeId',
        'limit': '$limit',
      },
    ).query;
    final json = await _request('/platform/audit?$query');
    return jsonMap(json['data']);
  }

  @override
  Future<List<Map<String, dynamic>>> listSmsProviders() async {
    final json = await _request('/platform/sms/providers');
    return jsonList(jsonMap(json['data'])['providers']);
  }

  @override
  Future<Map<String, dynamic>> updateSmsProvider(
    String providerCode,
    Map<String, dynamic> input,
  ) async {
    final json = await _request(
      '/platform/sms/providers/$providerCode',
      method: 'PATCH',
      body: input,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> updateSmsSenderId(
    String providerCode,
    String senderId,
    Map<String, dynamic> input,
  ) async {
    final json = await _request(
      '/platform/sms/providers/$providerCode/sender-ids/$senderId',
      method: 'PATCH',
      body: input,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> systemHealth() async {
    final json = await _request('/platform/system/health');
    return jsonMap(json['data']);
  }

  @override
  Future<List<Map<String, dynamic>>> systemErrors() async {
    final json = await _request('/platform/system/errors');
    return jsonList(json['data']);
  }

  @override
  Future<Map<String, dynamic>> rollout() async {
    final json = await _request('/platform/beta');
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> updateRolloutSettings(
    Map<String, dynamic> input,
  ) async {
    final json = await _request(
      '/platform/beta/settings',
      method: 'PUT',
      body: input,
    );
    return jsonMap(json['data']);
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    bool auth = true,
    Map<String, dynamic>? body,
  }) async {
    final baseUrl = _config.apiBaseUrl.toString().replaceAll(
      RegExp(r'/+$'),
      '',
    );
    final cleanPath = path.replaceAll(RegExp(r'^/+'), '');
    final uri = Uri.parse('$baseUrl/$cleanPath');
    late HttpClientRequest request;
    try {
      request = await _httpClient
          .openUrl(method, uri)
          .timeout(const Duration(seconds: 12));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      request.headers.set('Pragma', 'no-cache');
      request.headers.set('X-Request-ID', _requestId());
      if (auth) {
        final token = await _accessTokenProvider();
        if (token != null && token.isNotEmpty) {
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        }
      }
      if (body != null) {
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final text = await utf8
          .decodeStream(response)
          .timeout(const Duration(seconds: 20));
      Object? decoded;

      if (text.isEmpty) {
        decoded = <String, dynamic>{};
      } else {
        try {
          decoded = jsonDecode(text);
        } on FormatException {
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw ApiFailure(
              kind: _kindFor(response.statusCode, null),
              message: 'Server returned HTTP ${response.statusCode}.',
              statusCode: response.statusCode,
              requestId: response.headers.value('X-Request-ID'),
            );
          }
          throw const ApiFailure(
            kind: ApiFailureKind.server,
            message: 'The server returned an invalid response.',
          );
        }
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _failureFromResponse(response, decoded);
      }

      return jsonMap(decoded);
    } on ApiFailure {
      rethrow;
    } on SocketException {
      throw const ApiFailure(
        kind: ApiFailureKind.networkUnavailable,
        message: 'No internet connection. Check your connection and try again.',
      );
    } on TimeoutException {
      throw const ApiFailure(
        kind: ApiFailureKind.networkUnavailable,
        message: 'The request timed out.',
      );
    } on FormatException {
      throw const ApiFailure(
        kind: ApiFailureKind.server,
        message: 'The server returned an invalid response.',
      );
    }
  }

  ApiFailure _failureFromResponse(
    HttpClientResponse response,
    Object? decoded,
  ) {
    final payload = jsonMap(decoded);
    final error = jsonMap(payload['error']);
    final code = stringValue(error, 'code');
    final message = stringValue(error, 'message') ?? 'Request failed';
    final requestId =
        stringValue(error, 'requestId') ??
        response.headers.value('X-Request-ID');
    return ApiFailure(
      kind: _kindFor(response.statusCode, code),
      message: message,
      code: code,
      requestId: requestId,
      statusCode: response.statusCode,
    );
  }

  ApiFailureKind _kindFor(int statusCode, String? code) {
    if (statusCode == 401 || code == 'SESSION_REQUIRED') {
      return ApiFailureKind.unauthenticated;
    }
    if (statusCode == 403 ||
        code == 'TENANT_ACCESS_DENIED' ||
        code == 'PLATFORM_ACCESS_DENIED' ||
        code == 'PERMISSION_DENIED') {
      return ApiFailureKind.forbidden;
    }
    if (statusCode == 409) return ApiFailureKind.conflict;
    if (statusCode == 400 ||
        code == 'INVALID_INPUT' ||
        code == 'INVALID_PHONE') {
      return ApiFailureKind.validation;
    }
    if (statusCode >= 500) return ApiFailureKind.server;
    return ApiFailureKind.unknown;
  }
}

String _requestId() {
  final random = Random.secure();
  String hex(int length) =>
      List.generate(length, (_) => random.nextInt(16).toRadixString(16)).join();
  return '${hex(8)}-${hex(4)}-4${hex(3)}-${(8 + random.nextInt(4)).toRadixString(16)}${hex(3)}-${hex(12)}';
}
