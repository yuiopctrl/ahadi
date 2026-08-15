import '../../features/auth/domain/auth_models.dart';

abstract class AhadiApi {
  Future<LoginResult> loginWithPin({
    required String phone,
    required String pin,
  });
  Future<void> requestOtp(String phone);
  Future<LoginResult> verifyOtp({required String phone, required String token});
  Future<void> setPin({required String pin, required String confirmPin});
  Future<void> changePin({
    required String currentPin,
    required String newPin,
    required String confirmNewPin,
  });
  Future<void> logout();
  Future<UserContext> me();
  Future<TenantContext> tenantContext(String tenantId);
  Future<List<SubscriptionPlan>> plans();
  Future<Map<String, dynamic>> billingSummary(String tenantId);
  Future<Map<String, dynamic>> completeOnboarding(Map<String, dynamic> payload);
  Future<Map<String, dynamic>> createEvent(
    String tenantId,
    Map<String, dynamic> payload,
  );
  Future<Map<String, dynamic>> eventFinancialSummary(
    String tenantId,
    String eventId,
  );
  Future<List<Map<String, dynamic>>> eventMembers(
    String tenantId,
    String eventId,
  );
  Future<List<Map<String, dynamic>>> contacts(String tenantId);
  Future<Map<String, dynamic>> contactDetail(String tenantId, String memberId);
  Future<Map<String, dynamic>> createContact(
    String tenantId,
    Map<String, dynamic> payload,
  );
  Future<Map<String, dynamic>> updateContact(
    String tenantId,
    String memberId,
    Map<String, dynamic> payload,
  );
  Future<List<Map<String, dynamic>>> availableContactsForEvent(
    String tenantId,
    String eventId,
  );
  Future<Map<String, dynamic>> eventMemberDetail(
    String tenantId,
    String eventId,
    String eventMemberId,
  );
  Future<Map<String, dynamic>> attachEventMember(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  );
  Future<Map<String, dynamic>> createEventMember(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  );
  Future<Map<String, dynamic>> removeEventMember(
    String tenantId,
    String eventId,
    String eventMemberId,
    Map<String, dynamic> payload,
  );
  Future<List<Map<String, dynamic>>> eventPledges(
    String tenantId,
    String eventId,
  );
  Future<Map<String, dynamic>> upsertPledge(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload, {
    String? pledgeId,
  });
}

class LoginResult {
  const LoginResult({required this.credentials});

  final SessionCredentials credentials;
}
