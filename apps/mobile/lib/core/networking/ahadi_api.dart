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
}

class LoginResult {
  const LoginResult({required this.credentials});

  final SessionCredentials credentials;
}
