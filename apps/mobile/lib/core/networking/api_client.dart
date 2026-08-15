// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../config/app_config.dart';
import '../errors/api_failure.dart';
import '../../features/auth/domain/auth_models.dart';
import 'ahadi_api.dart';

typedef AccessTokenProvider = Future<String?> Function();

class ApiClient implements AhadiApi {
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
  Future<LoginResult> loginWithPin({
    required String phone,
    required String pin,
  }) async {
    final json = await _request(
      '/auth/login-pin',
      method: 'POST',
      auth: false,
      body: {'phone': phone, 'pin': pin},
    );
    return LoginResult(
      credentials: SessionCredentials.fromJson(jsonMap(json['session'])),
    );
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
  Future<LoginResult> verifyOtp({
    required String phone,
    required String token,
  }) async {
    final json = await _request(
      '/auth/verify-otp',
      method: 'POST',
      auth: false,
      body: {'phone': phone, 'token': token},
    );
    return LoginResult(
      credentials: SessionCredentials.fromJson(jsonMap(json['session'])),
    );
  }

  @override
  Future<void> setPin({required String pin, required String confirmPin}) async {
    await _request(
      '/auth/set-pin',
      method: 'POST',
      body: {'pin': pin, 'confirmPin': confirmPin},
    );
  }

  @override
  Future<void> changePin({
    required String currentPin,
    required String newPin,
    required String confirmNewPin,
  }) async {
    await _request(
      '/auth/change-pin',
      method: 'POST',
      body: {
        'currentPin': currentPin,
        'newPin': newPin,
        'confirmNewPin': confirmNewPin,
      },
    );
  }

  @override
  Future<void> logout() async {
    await _request('/auth/logout', method: 'POST');
  }

  @override
  Future<UserContext> me() async {
    final json = await _request('/me');
    return UserContext.fromJson(jsonMap(json['data']));
  }

  @override
  Future<TenantContext> tenantContext(String tenantId) async {
    final json = await _request('/tenant-context', tenantId: tenantId);
    return TenantContext.fromJson(jsonMap(json['data']));
  }

  @override
  Future<List<SubscriptionPlan>> plans() async {
    final json = await _request('/plans', auth: false);
    return objectList(json['data']).map(SubscriptionPlan.fromJson).toList();
  }

  @override
  Future<Map<String, dynamic>> billingSummary(String tenantId) async {
    final json = await _request('/billing/summary', tenantId: tenantId);
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> completeOnboarding(
    Map<String, dynamic> payload,
  ) async {
    return _request('/onboarding/complete', method: 'POST', body: payload);
  }

  @override
  Future<Map<String, dynamic>> createEvent(
    String tenantId,
    Map<String, dynamic> payload,
  ) async {
    final json = await _request(
      '/events',
      method: 'POST',
      tenantId: tenantId,
      body: payload,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> eventFinancialSummary(
    String tenantId,
    String eventId,
  ) async {
    final json = await _request(
      '/events/$eventId/financial-summary',
      tenantId: tenantId,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<List<Map<String, dynamic>>> eventMembers(
    String tenantId,
    String eventId,
  ) async {
    final json = await _request('/events/$eventId/members', tenantId: tenantId);
    return objectList(json['data']);
  }

  @override
  Future<List<Map<String, dynamic>>> contacts(String tenantId) async {
    final json = await _request('/contacts', tenantId: tenantId);
    return objectList(json['data']);
  }

  @override
  Future<Map<String, dynamic>> contactDetail(
    String tenantId,
    String memberId,
  ) async {
    final json = await _request('/contacts/$memberId', tenantId: tenantId);
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> createContact(
    String tenantId,
    Map<String, dynamic> payload,
  ) async {
    final json = await _request(
      '/contacts',
      method: 'POST',
      tenantId: tenantId,
      body: payload,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> updateContact(
    String tenantId,
    String memberId,
    Map<String, dynamic> payload,
  ) async {
    final json = await _request(
      '/members/$memberId',
      method: 'PATCH',
      tenantId: tenantId,
      body: payload,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<List<Map<String, dynamic>>> availableContactsForEvent(
    String tenantId,
    String eventId,
  ) async {
    final json = await _request(
      '/events/$eventId/contacts/available',
      tenantId: tenantId,
    );
    return objectList(json['data']);
  }

  @override
  Future<Map<String, dynamic>> eventMemberDetail(
    String tenantId,
    String eventId,
    String eventMemberId,
  ) async {
    final json = await _request(
      '/events/$eventId/members/$eventMemberId',
      tenantId: tenantId,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> attachEventMember(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  ) async {
    final json = await _request(
      '/events/$eventId/members/attach',
      method: 'POST',
      tenantId: tenantId,
      body: payload,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> createEventMember(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  ) async {
    final json = await _request(
      '/events/$eventId/members',
      method: 'POST',
      tenantId: tenantId,
      body: payload,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> removeEventMember(
    String tenantId,
    String eventId,
    String eventMemberId,
    Map<String, dynamic> payload,
  ) async {
    final json = await _request(
      '/events/$eventId/members/$eventMemberId/remove',
      method: 'POST',
      tenantId: tenantId,
      body: payload,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<List<Map<String, dynamic>>> eventPledges(
    String tenantId,
    String eventId,
  ) async {
    final json = await _request('/events/$eventId/pledges', tenantId: tenantId);
    return objectList(json['data']);
  }

  @override
  Future<Map<String, dynamic>> upsertPledge(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload, {
    String? pledgeId,
  }) async {
    final json = await _request(
      pledgeId == null
          ? '/events/$eventId/pledges'
          : '/events/$eventId/pledges/$pledgeId',
      method: pledgeId == null ? 'POST' : 'PATCH',
      tenantId: tenantId,
      body: payload,
    );
    return jsonMap(json['data']);
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    bool auth = true,
    String? tenantId,
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
      if (tenantId != null) {
        request.headers.set('X-Tenant-ID', tenantId);
      }
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

Map<String, dynamic> jsonMap(Object? value) {
  return value is Map<String, dynamic> ? value : <String, dynamic>{};
}

String _requestId() {
  final random = Random.secure();
  String hex(int length) =>
      List.generate(length, (_) => random.nextInt(16).toRadixString(16)).join();
  return '${hex(8)}-${hex(4)}-4${hex(3)}-${(8 + random.nextInt(4)).toRadixString(16)}${hex(3)}-${hex(12)}';
}
