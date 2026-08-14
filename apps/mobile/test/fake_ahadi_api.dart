import 'dart:async';

import 'package:ahadi_mobile/core/errors/api_failure.dart';
import 'package:ahadi_mobile/core/networking/ahadi_api.dart';
import 'package:ahadi_mobile/features/auth/domain/auth_models.dart';

class FakeAhadiApi implements AhadiApi {
  int loginPinCalls = 0;
  int requestOtpCalls = 0;
  int verifyOtpCalls = 0;
  int setPinCalls = 0;
  int changePinCalls = 0;
  int logoutCalls = 0;
  int meCalls = 0;
  int tenantContextCalls = 0;
  String? lastTenantId;
  Map<String, dynamic>? lastOnboardingPayload;
  Completer<LoginResult>? loginCompleter;
  Completer<TenantContext>? tenantCompleter;
  Object? meError;

  UserContext userContext = userWithMemberships([
    membership('tenant-a', 'Herosimini Committee'),
  ]);
  final Map<String, TenantContext> tenantContexts = {
    'tenant-a': makeTenantContext('tenant-a', 'Herosimini Committee'),
    'tenant-b': makeTenantContext('tenant-b', 'Valentino Group'),
  };

  @override
  Future<Map<String, dynamic>> billingSummary(String tenantId) async => {
    'subscription': {'status': 'TRIAL'},
  };

  @override
  Future<void> changePin({
    required String currentPin,
    required String newPin,
    required String confirmNewPin,
  }) async {
    changePinCalls += 1;
  }

  @override
  Future<Map<String, dynamic>> completeOnboarding(
    Map<String, dynamic> payload,
  ) async {
    lastOnboardingPayload = payload;
    userContext = userWithMemberships([
      ...userContext.tenantMemberships,
      membership('tenant-new', payload['tenantName'] as String),
    ]);
    tenantContexts['tenant-new'] = makeTenantContext(
      'tenant-new',
      payload['tenantName'] as String,
    );
    return {'tenant_id': 'tenant-new'};
  }

  @override
  Future<LoginResult> loginWithPin({
    required String phone,
    required String pin,
  }) async {
    loginPinCalls += 1;
    if (loginCompleter != null) {
      return loginCompleter!.future;
    }
    return const LoginResult(
      credentials: SessionCredentials(
        accessToken: 'access',
        refreshToken: 'refresh',
      ),
    );
  }

  @override
  Future<void> logout() async {
    logoutCalls += 1;
  }

  @override
  Future<UserContext> me() async {
    meCalls += 1;
    final error = meError;
    if (error != null) throw error;
    return userContext;
  }

  @override
  Future<List<SubscriptionPlan>> plans() async => const [
    SubscriptionPlan(code: 'BASIC', name: 'Basic'),
  ];

  @override
  Future<void> requestOtp(String phone) async {
    requestOtpCalls += 1;
  }

  @override
  Future<void> setPin({required String pin, required String confirmPin}) async {
    setPinCalls += 1;
  }

  @override
  Future<TenantContext> tenantContext(String tenantId) async {
    tenantContextCalls += 1;
    lastTenantId = tenantId;
    if (tenantCompleter != null) {
      return tenantCompleter!.future;
    }
    return tenantContexts[tenantId] ?? makeTenantContext(tenantId, tenantId);
  }

  @override
  Future<LoginResult> verifyOtp({
    required String phone,
    required String token,
  }) async {
    verifyOtpCalls += 1;
    return const LoginResult(
      credentials: SessionCredentials(
        accessToken: 'otp-access',
        refreshToken: 'otp-refresh',
      ),
    );
  }
}

UserContext userWithMemberships(List<TenantMembership> memberships) {
  return UserContext(
    profile: const UserProfile(
      fullName: 'Test Doctor',
      phoneE164: '+255712345678',
      email: 'test@example.com',
    ),
    onboardingCompleted: true,
    tenantMemberships: memberships,
  );
}

TenantMembership membership(String id, String name) {
  return TenantMembership(
    tenantId: id,
    tenantName: name,
    tenantStatus: 'ACTIVE',
    membershipStatus: 'ACTIVE',
    isOwner: id == 'tenant-a',
    roles: const ['TENANT_OWNER'],
    permissions: const ['events.view'],
    accessibleEvents: const [
      EventSummary(id: 'event-1', name: 'Main Event', status: 'ACTIVE'),
    ],
    subscription: const SubscriptionSummary(status: 'TRIAL', planName: 'Basic'),
  );
}

TenantContext makeTenantContext(String id, String name) {
  return TenantContext(
    tenantId: id,
    tenantName: name,
    events: const [
      EventSummary(id: 'event-1', name: 'Main Event', status: 'ACTIVE'),
    ],
    permissions: const ['events.view'],
    subscription: const SubscriptionSummary(status: 'TRIAL', planName: 'Basic'),
  );
}

const expiredSessionFailure = ApiFailure(
  kind: ApiFailureKind.unauthenticated,
  message: 'Session required',
  code: 'SESSION_REQUIRED',
  statusCode: 401,
);
