import '../auth/auth_models.dart';

abstract class PlatformApi {
  // Auth
  Future<SessionCredentials> loginWithPin({
    required String phone,
    required String pin,
  });
  Future<void> requestOtp(String phone);
  Future<SessionCredentials> verifyOtp({
    required String phone,
    required String token,
  });
  Future<void> setPin(String pin);
  Future<PlatformSession> me();
  Future<void> logout();

  // Dashboard
  Future<Map<String, dynamic>> dashboard();

  // Organizations
  Future<List<Map<String, dynamic>>> listOrganizations();
  Future<Map<String, dynamic>> organizationDetail(String tenantId);
  Future<Map<String, dynamic>> setOrganizationStatus({
    required String tenantId,
    required String status,
    String? reason,
  });
  Future<Map<String, dynamic>> extendTrial({
    required String tenantId,
    required int days,
    required String reason,
  });
  Future<Map<String, dynamic>> startSupportSession({
    required String tenantId,
    required String reason,
    int? durationMinutes,
  });

  // Subscriptions
  Future<Map<String, dynamic>> changeSubscriptionPlan({
    required String tenantId,
    required String planId,
    required String reason,
  });
  Future<Map<String, dynamic>> setSubscriptionStatus({
    required String tenantId,
    required String status,
    required String reason,
  });

  // Plans
  Future<List<Map<String, dynamic>>> listPlans();
  Future<Map<String, dynamic>> createPlan(Map<String, dynamic> input);
  Future<Map<String, dynamic>> updatePlan(
    String planId,
    Map<String, dynamic> input,
  );

  // Platform users
  Future<List<Map<String, dynamic>>> listPlatformUsers();
  Future<Map<String, dynamic>> addPlatformUser({
    required String phoneE164,
    required String role,
  });
  Future<Map<String, dynamic>> setPlatformUserRole({
    required String platformUserId,
    required String role,
  });
  Future<Map<String, dynamic>> setPlatformUserStatus({
    required String platformUserId,
    required String status,
    String? reason,
  });

  // Support
  Future<List<Map<String, dynamic>>> listSupportRequests();
  Future<Map<String, dynamic>> updateSupportRequest(
    String supportRequestId,
    Map<String, dynamic> input,
  );

  // Audit
  Future<Map<String, dynamic>> listAuditLog({
    String? action,
    String? tenantId,
    String? entityType,
    int? beforeId,
    int limit = 50,
  });

  // Messaging
  Future<List<Map<String, dynamic>>> listSmsProviders();
  Future<Map<String, dynamic>> updateSmsProvider(
    String providerCode,
    Map<String, dynamic> input,
  );
  Future<Map<String, dynamic>> updateSmsSenderId(
    String providerCode,
    String senderId,
    Map<String, dynamic> input,
  );

  // System
  Future<Map<String, dynamic>> systemHealth();
  Future<List<Map<String, dynamic>>> systemErrors();
  Future<Map<String, dynamic>> rollout();
  Future<Map<String, dynamic>> updateRolloutSettings(
    Map<String, dynamic> input,
  );
}
