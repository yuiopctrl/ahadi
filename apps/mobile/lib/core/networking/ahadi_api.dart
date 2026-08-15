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
  Future<Map<String, dynamic>> updateEvent(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  );
  Future<Map<String, dynamic>> eventFinancialSummary(
    String tenantId,
    String eventId,
  );
  Future<Map<String, dynamic>> eventReport(
    String tenantId,
    String eventId,
    String reportType,
    Map<String, dynamic> payload,
  );
  Future<List<Map<String, dynamic>>> eventMembers(
    String tenantId,
    String eventId,
  );
  Future<List<Map<String, dynamic>>> contacts(
    String tenantId, {
    String? search,
    int? limit,
    int? offset,
  });
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
    String eventId, {
    String? search,
    String? status,
    int? limit,
    int? offset,
  });
  Future<Map<String, dynamic>> upsertPledge(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload, {
    String? pledgeId,
  });
  Future<Map<String, dynamic>> recordPayment(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  );
  Future<Map<String, dynamic>> paymentDetail(
    String tenantId,
    String eventId,
    String paymentId,
  );
  Future<Map<String, dynamic>> reversePayment(
    String tenantId,
    String eventId,
    String paymentId,
    Map<String, dynamic> payload,
  );
  Future<Map<String, dynamic>> receiptDetail(String tenantId, String receiptId);
  Future<Map<String, dynamic>> whatsappShareSettings(
    String tenantId,
    String eventId,
  );
  Future<Map<String, dynamic>> updateWhatsappShareSettings(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  );
  Future<Map<String, dynamic>> whatsappSharePreview(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  );
  Future<List<Map<String, dynamic>>> messageHistory(String tenantId);
  Future<Map<String, dynamic>> smsSettings(String tenantId);
  Future<Map<String, dynamic>> updateSmsSettings(
    String tenantId,
    Map<String, dynamic> payload,
  );
  Future<Map<String, dynamic>> smsProviderOptions(String tenantId);
  Future<List<Map<String, dynamic>>> smsTemplates(String tenantId);
  Future<Map<String, dynamic>> updateSmsTemplate(
    String tenantId,
    String code,
    Map<String, dynamic> payload,
  );
  Future<Map<String, dynamic>> resetSmsTemplate(String tenantId, String code);
  Future<List<Map<String, dynamic>>> noPledgeMessageRecipients(
    String tenantId,
    String eventId,
  );
  Future<Map<String, dynamic>> smsBulkPreview(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  );
  Future<Map<String, dynamic>> sendPledgeRequestBulk(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  );
  Future<Map<String, dynamic>> sendBalanceReminderBulk(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  );
  Future<Map<String, dynamic>> retrySms(
    String tenantId,
    String outboxId,
    Map<String, dynamic> payload,
  );
}

class LoginResult {
  const LoginResult({required this.credentials});

  final SessionCredentials credentials;
}
