import 'package:changisha_platform/core/auth/auth_models.dart';
import 'package:changisha_platform/core/errors/api_failure.dart';
import 'package:changisha_platform/core/networking/platform_api.dart';

class FakePlatformApi implements PlatformApi {
  bool loginSucceeds = true;
  PlatformSession? meResult;
  Map<String, dynamic> dashboardResult = const {};
  List<Map<String, dynamic>> organizations = const [];
  List<Map<String, dynamic>> plans = const [];
  List<Map<String, dynamic>> platformUsers = const [];
  List<Map<String, dynamic>> supportRequests = const [];
  Map<String, dynamic> auditLogResult = const {'items': [], 'nextCursor': null};
  List<Map<String, dynamic>> smsProviders = const [];
  Map<String, dynamic> systemHealthResult = const {'smsQueue': <String, dynamic>{}};
  Map<String, dynamic> rolloutResult = const {'settings': <String, dynamic>{}};

  int logoutCalls = 0;

  @override
  Future<SessionCredentials> loginWithPin({required String phone, required String pin}) async {
    if (!loginSucceeds) {
      throw const ApiFailure(kind: ApiFailureKind.validation, message: 'Phone number or PIN is incorrect.', code: 'PIN_INVALID');
    }
    return const SessionCredentials(accessToken: 'token', refreshToken: 'refresh');
  }

  @override
  Future<void> requestOtp(String phone) async {}

  @override
  Future<SessionCredentials> verifyOtp({required String phone, required String token}) async {
    return const SessionCredentials(accessToken: 'token', refreshToken: 'refresh');
  }

  @override
  Future<void> setPin(String pin) async {}

  @override
  Future<PlatformSession> me() async {
    return meResult ??
        const PlatformSession(profile: null, isPlatformUser: false, platformRole: null, platformStatus: null, platformPermissions: []);
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
  }

  @override
  Future<Map<String, dynamic>> dashboard() async => dashboardResult;

  @override
  Future<List<Map<String, dynamic>>> listOrganizations() async => organizations;

  @override
  Future<Map<String, dynamic>> organizationDetail(String tenantId) async => const {};

  @override
  Future<Map<String, dynamic>> setOrganizationStatus({required String tenantId, required String status, String? reason}) async => const {};

  @override
  Future<Map<String, dynamic>> extendTrial({required String tenantId, required int days, required String reason}) async => const {};

  @override
  Future<Map<String, dynamic>> startSupportSession({required String tenantId, required String reason, int? durationMinutes}) async => const {};

  @override
  Future<Map<String, dynamic>> changeSubscriptionPlan({required String tenantId, required String planId, required String reason}) async => const {};

  @override
  Future<Map<String, dynamic>> setSubscriptionStatus({required String tenantId, required String status, required String reason}) async => const {};

  @override
  Future<List<Map<String, dynamic>>> listPlans() async => plans;

  @override
  Future<Map<String, dynamic>> createPlan(Map<String, dynamic> input) async => const {};

  @override
  Future<Map<String, dynamic>> updatePlan(String planId, Map<String, dynamic> input) async => const {};

  @override
  Future<List<Map<String, dynamic>>> listPlatformUsers() async => platformUsers;

  @override
  Future<Map<String, dynamic>> addPlatformUser({required String phoneE164, required String role}) async => const {};

  @override
  Future<Map<String, dynamic>> setPlatformUserRole({required String platformUserId, required String role}) async => const {};

  @override
  Future<Map<String, dynamic>> setPlatformUserStatus({required String platformUserId, required String status, String? reason}) async => const {};

  @override
  Future<List<Map<String, dynamic>>> listSupportRequests() async => supportRequests;

  @override
  Future<Map<String, dynamic>> updateSupportRequest(String supportRequestId, Map<String, dynamic> input) async => const {};

  @override
  Future<Map<String, dynamic>> listAuditLog({String? action, String? tenantId, String? entityType, int? beforeId, int limit = 50}) async => auditLogResult;

  @override
  Future<List<Map<String, dynamic>>> listSmsProviders() async => smsProviders;

  @override
  Future<Map<String, dynamic>> updateSmsProvider(String providerCode, Map<String, dynamic> input) async => const {};

  @override
  Future<Map<String, dynamic>> updateSmsSenderId(String providerCode, String senderId, Map<String, dynamic> input) async => const {};

  @override
  Future<Map<String, dynamic>> systemHealth() async => systemHealthResult;

  @override
  Future<List<Map<String, dynamic>>> systemErrors() async => const [];

  @override
  Future<Map<String, dynamic>> rollout() async => rolloutResult;

  @override
  Future<Map<String, dynamic>> updateRolloutSettings(Map<String, dynamic> input) async => const {};
}
