// ignore_for_file: prefer_initializing_formals

import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/errors/api_failure.dart';
import '../../../core/networking/ahadi_api.dart';
import '../../../core/storage/session_storage.dart';
import '../../auth/domain/auth_models.dart';
import 'phone_normalization.dart';

enum BootstrapState {
  initializing,
  restoringSession,
  resolvingAccess,
  ready,
  unauthenticated,
  error,
}

enum ForgotPinStep { phone, otp, newPin }

class SessionController extends ChangeNotifier {
  SessionController({required AhadiApi api, required SessionStorage storage})
    : _api = api,
      _storage = storage;

  final AhadiApi _api;
  final SessionStorage _storage;

  BootstrapState bootstrapState = BootstrapState.initializing;
  SessionCredentials? credentials;
  UserContext? userContext;
  TenantContext? selectedTenantContext;
  String? selectedTenantId;
  String? errorMessage;
  bool isSubmitting = false;

  String? get accessToken => credentials?.accessToken;
  bool get isAuthenticated => credentials != null && userContext != null;
  List<TenantMembership> get activeMemberships =>
      userContext?.activeMemberships ?? const [];
  bool get needsOrganizationSelection =>
      isAuthenticated &&
      selectedTenantContext == null &&
      activeMemberships.length > 1;
  bool get needsOrganizationCreation =>
      isAuthenticated &&
      selectedTenantContext == null &&
      activeMemberships.isEmpty;

  Future<void> initialize() async {
    bootstrapState = BootstrapState.restoringSession;
    errorMessage = null;
    notifyListeners();
    credentials = await _storage.readSession();
    selectedTenantId = await _storage.readSelectedTenantId();
    if (credentials == null) {
      await _storage.clearSession();
      bootstrapState = BootstrapState.unauthenticated;
      notifyListeners();
      return;
    }
    await _resolveAccess(clearOnSessionExpiry: true);
  }

  Future<void> loginWithPin({
    required String phone,
    required String pin,
  }) async {
    if (isSubmitting) return;
    isSubmitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      final normalizedPhone = normalizeTanzaniaPhone(phone);
      if (!isValidPin(pin)) {
        throw const FormatException('Enter your 4 digit PIN.');
      }
      final result = await _api.loginWithPin(phone: normalizedPhone, pin: pin);
      credentials = result.credentials;
      await _storage.saveSession(result.credentials);
      await _resolveAccess();
    } catch (error) {
      errorMessage = _messageFor(error);
      if (error is ApiFailure && error.code == 'PIN_INVALID') {
        rethrow;
      }
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> requestForgotPinOtp(String phone) async {
    if (isSubmitting) return;
    isSubmitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _api.requestOtp(normalizeTanzaniaPhone(phone));
    } catch (error) {
      errorMessage = _messageFor(error);
      rethrow;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> verifyForgotPinOtp({
    required String phone,
    required String token,
  }) async {
    if (isSubmitting) return;
    isSubmitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      final result = await _api.verifyOtp(
        phone: normalizeTanzaniaPhone(phone),
        token: token,
      );
      credentials = result.credentials;
      await _storage.saveSession(result.credentials);
    } catch (error) {
      errorMessage = _messageFor(error);
      rethrow;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> setForgottenPin({
    required String pin,
    required String confirmPin,
  }) async {
    if (isSubmitting) return;
    isSubmitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      if (pin != confirmPin) throw const FormatException('PINs do not match.');
      if (isWeakPin(pin)) throw const FormatException('Choose a stronger PIN.');
      await _api.setPin(pin: pin, confirmPin: confirmPin);
      await _resolveAccess();
    } catch (error) {
      errorMessage = _messageFor(error);
      rethrow;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> changePin({
    required String currentPin,
    required String newPin,
    required String confirmNewPin,
  }) async {
    if (isSubmitting) return;
    isSubmitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      if (newPin != confirmNewPin) {
        throw const FormatException('PINs do not match.');
      }
      if (isWeakPin(newPin)) {
        throw const FormatException('Choose a stronger PIN.');
      }
      await _api.changePin(
        currentPin: currentPin,
        newPin: newPin,
        confirmNewPin: confirmNewPin,
      );
    } catch (error) {
      errorMessage = _messageFor(error);
      rethrow;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> selectTenant(String tenantId) async {
    errorMessage = null;
    notifyListeners();
    final context = await _api.tenantContext(tenantId);
    selectedTenantId = tenantId;
    selectedTenantContext = context;
    await _storage.saveSelectedTenantId(tenantId);
    notifyListeners();
  }

  Future<void> switchTenant(String tenantId) async {
    selectedTenantContext = null;
    selectedTenantId = null;
    notifyListeners();
    await selectTenant(tenantId);
  }

  Future<List<SubscriptionPlan>> plans() => _api.plans();

  Future<Map<String, dynamic>> billingSummary() {
    final tenantId = selectedTenantId;
    if (tenantId == null) return Future.value(<String, dynamic>{});
    return _api.billingSummary(tenantId);
  }

  Future<void> createOrganization({
    required String planCode,
    required String tenantName,
    required String tenantPhone,
    required String tenantEmail,
    required String adminFullName,
    required String adminEmail,
    required String firstEventName,
    required String eventType,
    required String eventDate,
    required String venue,
    required String targetAmount,
    required String pledgeDeadline,
  }) async {
    if (isSubmitting) return;
    isSubmitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      final payload = <String, dynamic>{
        'planCode': planCode,
        'onboardingIntent': activeMemberships.isEmpty
            ? 'FIRST_TENANT'
            : 'CREATE_ADDITIONAL_TENANT',
        'tenantName': tenantName,
        'tenantPhone': normalizeTanzaniaPhone(tenantPhone),
        'tenantEmail': tenantEmail.trim().isEmpty ? null : tenantEmail.trim(),
        'adminFullName': adminFullName,
        'adminEmail': adminEmail.trim().isEmpty ? null : adminEmail.trim(),
        'preferredLanguage': 'sw',
        'firstEventName': firstEventName,
        'eventType': eventType,
        'customEventType': null,
        'eventDate': eventDate.trim().isEmpty ? null : eventDate.trim(),
        'venue': venue.trim().isEmpty ? null : venue.trim(),
        'targetAmount': targetAmount.trim().isEmpty
            ? null
            : num.tryParse(targetAmount.trim()),
        'pledgeDeadline': pledgeDeadline.trim().isEmpty
            ? null
            : pledgeDeadline.trim(),
        'betaInvitationCode': null,
        'idempotencyKey': _uuidV4(),
      };
      final response = await _api.completeOnboarding(payload);
      await _resolveAccess();
      final membershipsAfterCreate = activeMemberships;
      final tenantId = response['tenant_id'] is String
          ? response['tenant_id'] as String
          : response['tenantId'] is String
          ? response['tenantId'] as String
          : membershipsAfterCreate.isEmpty
          ? null
          : membershipsAfterCreate.last.tenantId;
      if (tenantId != null) {
        await selectTenant(tenantId);
      }
    } catch (error) {
      errorMessage = _messageFor(error);
      rethrow;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _api.logout().catchError((_) {});
    credentials = null;
    userContext = null;
    selectedTenantContext = null;
    selectedTenantId = null;
    await _storage.clearSession();
    bootstrapState = BootstrapState.unauthenticated;
    notifyListeners();
  }

  Future<void> _resolveAccess({bool clearOnSessionExpiry = false}) async {
    bootstrapState = BootstrapState.resolvingAccess;
    notifyListeners();
    try {
      userContext = await _api.me();
      await _restoreTenantSelection();
      bootstrapState = BootstrapState.ready;
      notifyListeners();
    } catch (error) {
      if (clearOnSessionExpiry &&
          error is ApiFailure &&
          error.isSessionExpired) {
        credentials = null;
        userContext = null;
        selectedTenantContext = null;
        selectedTenantId = null;
        await _storage.clearSession();
        bootstrapState = BootstrapState.unauthenticated;
        notifyListeners();
        return;
      }
      errorMessage = _messageFor(error);
      bootstrapState = BootstrapState.error;
      notifyListeners();
    }
  }

  Future<void> _restoreTenantSelection() async {
    final memberships = activeMemberships;
    final storedTenant =
        selectedTenantId != null &&
        memberships.any(
          (membership) => membership.tenantId == selectedTenantId,
        );
    final tenantToSelect = storedTenant
        ? selectedTenantId
        : memberships.length == 1
        ? memberships.first.tenantId
        : null;
    if (tenantToSelect == null) {
      selectedTenantContext = null;
      if (selectedTenantId != null && !storedTenant) {
        selectedTenantId = null;
        await _storage.clearSelectedTenantId();
      }
      return;
    }
    selectedTenantContext = await _api.tenantContext(tenantToSelect);
    selectedTenantId = tenantToSelect;
    await _storage.saveSelectedTenantId(tenantToSelect);
  }

  String _messageFor(Object error) {
    if (error is ApiFailure) return error.message;
    if (error is FormatException) return error.message;
    return 'Something went wrong. Please try again.';
  }
}

String _uuidV4() {
  final random = Random.secure();
  String hex(int length) =>
      List.generate(length, (_) => random.nextInt(16).toRadixString(16)).join();
  return '${hex(8)}-${hex(4)}-4${hex(3)}-${(8 + random.nextInt(4)).toRadixString(16)}${hex(3)}-${hex(12)}';
}
