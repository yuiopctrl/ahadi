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
  Future<Map<String, dynamic>> accountState(String phone) async {
    final json = await _request(
      '/auth/account-state',
      method: 'POST',
      auth: false,
      body: {'phone': phone},
    );
    return jsonMap(json['data']);
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
  Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> payload,
  ) async {
    final json = await _request('/profile', method: 'PATCH', body: payload);
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> acceptInvitation(String invitationId) async {
    final json = await _request(
      '/invitations/$invitationId/accept',
      method: 'POST',
      body: const <String, dynamic>{},
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> declineInvitation(String invitationId) async {
    final json = await _request(
      '/invitations/$invitationId/decline',
      method: 'POST',
      body: const <String, dynamic>{},
    );
    return jsonMap(json['data']);
  }

  @override
  Future<List<Map<String, dynamic>>> tenantUsers(
    String tenantId, {
    String? search,
    int? limit,
    int? offset,
  }) async {
    final params = <String, String>{};
    if (search != null && search.trim().isNotEmpty) {
      params['search'] = search.trim();
    }
    if (limit != null) params['limit'] = '$limit';
    if (offset != null) params['offset'] = '$offset';
    final path = Uri(
      path: '/users',
      queryParameters: params.isEmpty ? null : params,
    ).toString();
    final json = await _request(path, tenantId: tenantId);
    return objectList(json['data']);
  }

  @override
  Future<Map<String, dynamic>> inviteTenantUser(
    String tenantId,
    Map<String, dynamic> payload,
  ) async {
    final json = await _request(
      '/users/invitations',
      method: 'POST',
      tenantId: tenantId,
      body: payload,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> resendTenantInvitation(
    String tenantId,
    String invitationId,
  ) async {
    final json = await _request(
      '/users/invitations/$invitationId/resend',
      method: 'POST',
      tenantId: tenantId,
      body: const <String, dynamic>{},
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> updateTenantUserRole(
    String tenantId,
    String tenantUserId,
    Map<String, dynamic> payload,
  ) async {
    final json = await _request(
      '/users/$tenantUserId/role',
      method: 'PATCH',
      tenantId: tenantId,
      body: payload,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> suspendTenantUser(
    String tenantId,
    String tenantUserId,
  ) {
    return _tenantUserStatusAction(tenantId, tenantUserId, 'suspend');
  }

  @override
  Future<Map<String, dynamic>> reactivateTenantUser(
    String tenantId,
    String tenantUserId,
  ) {
    return _tenantUserStatusAction(tenantId, tenantUserId, 'reactivate');
  }

  @override
  Future<Map<String, dynamic>> removeTenantUser(
    String tenantId,
    String tenantUserId,
  ) {
    return _tenantUserStatusAction(tenantId, tenantUserId, 'remove');
  }

  Future<Map<String, dynamic>> _tenantUserStatusAction(
    String tenantId,
    String tenantUserId,
    String action,
  ) async {
    final json = await _request(
      '/users/$tenantUserId/$action',
      method: 'POST',
      tenantId: tenantId,
      body: const <String, dynamic>{},
    );
    return jsonMap(json['data']);
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
  Future<Map<String, dynamic>> updateEvent(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  ) async {
    final json = await _request(
      '/events/$eventId',
      method: 'PATCH',
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
  Future<Map<String, dynamic>> eventReport(
    String tenantId,
    String eventId,
    String reportType,
    Map<String, dynamic> payload,
  ) async {
    final json = await _request(
      '/events/$eventId/reports/$reportType',
      method: 'POST',
      tenantId: tenantId,
      body: payload,
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
  Future<List<Map<String, dynamic>>> contacts(
    String tenantId, {
    String? search,
    int? limit,
    int? offset,
  }) async {
    final query = Uri(
      queryParameters: {
        if (search != null && search.trim().isNotEmpty) 'search': search,
        if (limit != null) 'limit': '$limit',
        if (offset != null) 'offset': '$offset',
      },
    ).query;
    final json = await _request(
      query.isEmpty ? '/contacts' : '/contacts?$query',
      tenantId: tenantId,
    );
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
    String eventId, {
    String? search,
    String? status,
    int? limit,
    int? offset,
  }) async {
    final query = Uri(
      queryParameters: {
        if (search != null && search.trim().isNotEmpty) 'search': search,
        if (status != null && status != 'ALL') 'status': status,
        if (limit != null) 'limit': '$limit',
        if (offset != null) 'offset': '$offset',
      },
    ).query;
    final json = await _request(
      query.isEmpty
          ? '/events/$eventId/pledges'
          : '/events/$eventId/pledges?$query',
      tenantId: tenantId,
    );
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

  @override
  Future<Map<String, dynamic>> recordPayment(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  ) async {
    final json = await _request(
      '/events/$eventId/payments',
      method: 'POST',
      tenantId: tenantId,
      body: payload,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> paymentDetail(
    String tenantId,
    String eventId,
    String paymentId,
  ) async {
    final json = await _request(
      '/events/$eventId/payments/$paymentId',
      tenantId: tenantId,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> reversePayment(
    String tenantId,
    String eventId,
    String paymentId,
    Map<String, dynamic> payload,
  ) async {
    final json = await _request(
      '/events/$eventId/payments/$paymentId/reverse',
      method: 'POST',
      tenantId: tenantId,
      body: payload,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> receiptDetail(
    String tenantId,
    String receiptId,
  ) async {
    final json = await _request('/receipts/$receiptId', tenantId: tenantId);
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> whatsappShareSettings(
    String tenantId,
    String eventId,
  ) async {
    final json = await _request(
      '/events/$eventId/share/whatsapp-settings',
      tenantId: tenantId,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> updateWhatsappShareSettings(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  ) async {
    final json = await _request(
      '/events/$eventId/share/whatsapp-settings',
      method: 'PUT',
      tenantId: tenantId,
      body: payload,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> whatsappSharePreview(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  ) async {
    final json = await _request(
      '/events/$eventId/share/whatsapp-preview',
      method: 'POST',
      tenantId: tenantId,
      body: payload,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<List<Map<String, dynamic>>> messageHistory(String tenantId) async {
    final json = await _request('/messages', tenantId: tenantId);
    return objectList(json['data']);
  }

  @override
  Future<Map<String, dynamic>> smsSettings(String tenantId) async {
    final json = await _request('/messages/settings', tenantId: tenantId);
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> updateSmsSettings(
    String tenantId,
    Map<String, dynamic> payload,
  ) async {
    final json = await _request(
      '/messages/settings',
      method: 'PUT',
      tenantId: tenantId,
      body: payload,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> smsProviderOptions(String tenantId) async {
    final json = await _request(
      '/settings/messages/providers',
      tenantId: tenantId,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<List<Map<String, dynamic>>> smsTemplates(String tenantId) async {
    final json = await _request('/messages/templates', tenantId: tenantId);
    return objectList(json['data']);
  }

  @override
  Future<Map<String, dynamic>> updateSmsTemplate(
    String tenantId,
    String code,
    Map<String, dynamic> payload,
  ) async {
    final json = await _request(
      '/messages/templates/$code',
      method: 'PUT',
      tenantId: tenantId,
      body: payload,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> resetSmsTemplate(
    String tenantId,
    String code,
  ) async {
    final json = await _request(
      '/messages/templates/$code/reset',
      method: 'POST',
      tenantId: tenantId,
      body: const <String, dynamic>{},
    );
    return jsonMap(json['data']);
  }

  @override
  Future<List<Map<String, dynamic>>> noPledgeMessageRecipients(
    String tenantId,
    String eventId,
  ) async {
    final json = await _request(
      '/events/$eventId/messages/no-pledge-members',
      tenantId: tenantId,
    );
    return objectList(json['data']);
  }

  @override
  Future<Map<String, dynamic>> smsBulkPreview(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  ) async {
    final json = await _request(
      '/events/$eventId/messages/preview/bulk',
      method: 'POST',
      tenantId: tenantId,
      body: payload,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<List<Map<String, dynamic>>> allEventMembers(
    String tenantId,
    String eventId,
  ) async {
    final json = await _request(
      '/events/$eventId/messages/all-members',
      tenantId: tenantId,
    );
    return objectList(json['data']);
  }

  @override
  Future<List<Map<String, dynamic>>> customSmsTemplates(
    String tenantId,
  ) async {
    final json = await _request(
      '/messages/templates/custom',
      tenantId: tenantId,
    );
    return objectList(json['data']);
  }

  @override
  Future<Map<String, dynamic>> createCustomSmsTemplate(
    String tenantId,
    Map<String, dynamic> payload,
  ) async {
    final json = await _request(
      '/messages/templates/custom',
      method: 'POST',
      tenantId: tenantId,
      body: payload,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> updateCustomSmsTemplate(
    String tenantId,
    String code,
    Map<String, dynamic> payload,
  ) async {
    final json = await _request(
      '/messages/templates/custom/$code',
      method: 'PUT',
      tenantId: tenantId,
      body: payload,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> deleteCustomSmsTemplate(
    String tenantId,
    String code,
  ) async {
    final json = await _request(
      '/messages/templates/custom/$code',
      method: 'DELETE',
      tenantId: tenantId,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> customSmsBulkPreview(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  ) async {
    final json = await _request(
      '/events/$eventId/messages/custom/preview/bulk',
      method: 'POST',
      tenantId: tenantId,
      body: payload,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> sendCustomSmsBulk(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  ) async {
    final json = await _request(
      '/events/$eventId/messages/custom/bulk',
      method: 'POST',
      tenantId: tenantId,
      body: payload,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> sendPledgeRequestBulk(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  ) async {
    final json = await _request(
      '/events/$eventId/messages/pledge-request/bulk',
      method: 'POST',
      tenantId: tenantId,
      body: payload,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> sendBalanceReminderBulk(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  ) async {
    final json = await _request(
      '/events/$eventId/reminders/balance/bulk',
      method: 'POST',
      tenantId: tenantId,
      body: payload,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> retrySms(
    String tenantId,
    String outboxId,
    Map<String, dynamic> payload,
  ) async {
    final json = await _request(
      '/messages/$outboxId/retry',
      method: 'POST',
      tenantId: tenantId,
      body: payload,
    );
    return jsonMap(json['data']);
  }

  @override
  Future<Map<String, dynamic>> activity(
    String tenantId, {
    String? search,
    String? action,
    String? entityType,
    String? eventId,
    String? actorUserId,
    String? dateFrom,
    String? dateTo,
    int? limit,
    int? offset,
  }) async {
    final query = Uri(
      queryParameters: {
        if (search != null && search.trim().isNotEmpty) 'search': search,
        if (action != null && action.isNotEmpty) 'action': action,
        if (entityType != null && entityType.isNotEmpty)
          'entityType': entityType,
        if (eventId != null && eventId.isNotEmpty) 'eventId': eventId,
        if (actorUserId != null && actorUserId.isNotEmpty)
          'actorUserId': actorUserId,
        if (dateFrom != null && dateFrom.isNotEmpty) 'dateFrom': dateFrom,
        if (dateTo != null && dateTo.isNotEmpty) 'dateTo': dateTo,
        if (limit != null) 'limit': '$limit',
        if (offset != null) 'offset': '$offset',
      },
    ).query;
    return _request(
      query.isEmpty ? '/activity' : '/activity?$query',
      tenantId: tenantId,
    );
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
