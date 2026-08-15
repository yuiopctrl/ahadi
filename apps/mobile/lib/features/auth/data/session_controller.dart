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
  String? selectedEventId;
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
      !(userContext?.pendingInvitations.isNotEmpty ?? false) &&
      activeMemberships.isEmpty;
  bool get needsInvitationReview =>
      isAuthenticated &&
      selectedTenantContext == null &&
      activeMemberships.isEmpty &&
      (userContext?.pendingInvitations.isNotEmpty ?? false);
  EventSummary? get selectedEvent {
    final eventId = selectedEventId;
    if (eventId == null) return null;
    final events = selectedTenantContext?.events ?? const <EventSummary>[];
    for (final event in events) {
      if (event.id == eventId) return event;
    }
    return null;
  }

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

  Future<Map<String, dynamic>> accountState(String phone) {
    return _api.accountState(normalizeTanzaniaPhone(phone));
  }

  Future<void> requestRegistrationOtp(String phone) async {
    if (isSubmitting) return;
    isSubmitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      final normalized = normalizeTanzaniaPhone(phone);
      await _api.requestOtp(normalized);
    } catch (error) {
      errorMessage = _messageFor(error);
      rethrow;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> verifyRegistrationOtp({
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
      userContext = await _api.me();
    } catch (error) {
      errorMessage = _messageFor(error);
      rethrow;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> setRegistrationPin({
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
      userContext = await _api.me();
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
    await restoreEventForTenant();
    notifyListeners();
  }

  Future<void> switchTenant(String tenantId) async {
    selectedTenantContext = null;
    selectedTenantId = null;
    selectedEventId = null;
    notifyListeners();
    await selectTenant(tenantId);
  }

  Future<void> selectEvent(String eventId) async {
    final tenantId = _requireTenantId();
    final events = selectedTenantContext?.events ?? const <EventSummary>[];
    if (!events.any((event) => event.id == eventId)) {
      throw StateError('Choose an event from the selected organization.');
    }
    selectedEventId = eventId;
    await _storage.saveSelectedEventId(tenantId, eventId);
    notifyListeners();
  }

  Future<void> clearSelectedEvent() async {
    final tenantId = selectedTenantId;
    if (tenantId != null) {
      await _storage.clearSelectedEventId(tenantId);
    }
    selectedEventId = null;
    notifyListeners();
  }

  Future<void> restoreEventForTenant() async {
    final tenantId = selectedTenantId;
    final events = selectedTenantContext?.events ?? const <EventSummary>[];
    if (tenantId == null || events.isEmpty) {
      selectedEventId = null;
      return;
    }
    final stored = await _storage.readSelectedEventId(tenantId);
    if (stored != null && events.any((event) => event.id == stored)) {
      selectedEventId = stored;
      return;
    }
    final active = events.where((event) => event.status == 'ACTIVE').toList();
    if (active.length == 1) {
      selectedEventId = active.first.id;
      await _storage.saveSelectedEventId(tenantId, active.first.id);
      return;
    }
    selectedEventId = null;
  }

  Future<List<SubscriptionPlan>> plans() => _api.plans();

  Future<Map<String, dynamic>> billingSummary() {
    final tenantId = selectedTenantId;
    if (tenantId == null) return Future.value(<String, dynamic>{});
    return _api.billingSummary(tenantId);
  }

  Future<void> refreshTenantContext() async {
    final tenantId = selectedTenantId;
    if (tenantId == null) return;
    selectedTenantContext = await _api.tenantContext(tenantId);
    await restoreEventForTenant();
    notifyListeners();
  }

  Future<Map<String, dynamic>> createEvent(Map<String, dynamic> payload) async {
    final tenantId = _requireTenantId();
    final result = await _api.createEvent(tenantId, payload);
    await refreshTenantContext();
    return result;
  }

  Future<EventSummary> updateEvent(
    String eventId,
    Map<String, dynamic> payload,
  ) async {
    final tenantId = _requireTenantId();
    await _api.updateEvent(tenantId, eventId, payload);
    await refreshTenantContext();
    final refreshed = selectedTenantContext?.events
        .where((event) => event.id == eventId)
        .firstOrNull;
    if (refreshed == null) {
      throw StateError('Updated event is not available in this organization.');
    }
    return refreshed;
  }

  Future<Map<String, dynamic>> eventFinancialSummary(String eventId) {
    return _api.eventFinancialSummary(_requireTenantId(), eventId);
  }

  Future<Map<String, dynamic>> eventReport(
    String eventId,
    String reportType,
    Map<String, dynamic> payload,
  ) {
    return _api.eventReport(_requireTenantId(), eventId, reportType, payload);
  }

  Future<List<Map<String, dynamic>>> eventMembers(String eventId) {
    return _api.eventMembers(_requireTenantId(), eventId);
  }

  Future<List<Map<String, dynamic>>> contacts({
    String? search,
    int? limit,
    int? offset,
  }) {
    return _api.contacts(
      _requireTenantId(),
      search: search,
      limit: limit,
      offset: offset,
    );
  }

  Future<Map<String, dynamic>> contactDetail(String memberId) {
    return _api.contactDetail(_requireTenantId(), memberId);
  }

  Future<Map<String, dynamic>> createContact(Map<String, dynamic> payload) {
    final normalized = Map<String, dynamic>.from(payload);
    final phone = normalized['phone'];
    if (phone is String && phone.trim().isNotEmpty) {
      normalized['phone'] = normalizeTanzaniaPhone(phone);
    }
    final alternativePhone = normalized['alternativePhone'];
    if (alternativePhone is String && alternativePhone.trim().isNotEmpty) {
      normalized['alternativePhone'] = normalizeTanzaniaPhone(alternativePhone);
    }
    return _api.createContact(_requireTenantId(), normalized);
  }

  Future<Map<String, dynamic>> updateContact(
    String memberId,
    Map<String, dynamic> payload,
  ) {
    final normalized = Map<String, dynamic>.from(payload);
    final phone = normalized['phoneE164'];
    if (phone is String && phone.trim().isNotEmpty) {
      normalized['phoneE164'] = normalizeTanzaniaPhone(phone);
    }
    final alternativePhone = normalized['alternativePhoneE164'];
    if (alternativePhone is String && alternativePhone.trim().isNotEmpty) {
      normalized['alternativePhoneE164'] = normalizeTanzaniaPhone(
        alternativePhone,
      );
    }
    return _api.updateContact(_requireTenantId(), memberId, normalized);
  }

  Future<List<Map<String, dynamic>>> availableContactsForEvent(String eventId) {
    return _api.availableContactsForEvent(_requireTenantId(), eventId);
  }

  Future<Map<String, dynamic>> eventMemberDetail(
    String eventId,
    String eventMemberId,
  ) {
    return _api.eventMemberDetail(_requireTenantId(), eventId, eventMemberId);
  }

  Future<Map<String, dynamic>> attachEventMember(
    String eventId,
    String memberId,
  ) {
    return _api.attachEventMember(_requireTenantId(), eventId, {
      'memberId': memberId,
    });
  }

  Future<Map<String, dynamic>> createEventMember(
    String eventId,
    Map<String, dynamic> payload,
  ) {
    return _api.createEventMember(_requireTenantId(), eventId, payload);
  }

  Future<Map<String, dynamic>> removeEventMember(
    String eventId,
    String eventMemberId, {
    String? reason,
  }) {
    return _api.removeEventMember(_requireTenantId(), eventId, eventMemberId, {
      'reason': reason,
    });
  }

  Future<List<Map<String, dynamic>>> eventPledges(
    String eventId, {
    String? search,
    String? status,
    int? limit,
    int? offset,
  }) {
    return _api.eventPledges(
      _requireTenantId(),
      eventId,
      search: search,
      status: status,
      limit: limit,
      offset: offset,
    );
  }

  Future<Map<String, dynamic>> upsertPledge(
    String eventId,
    Map<String, dynamic> payload, {
    String? pledgeId,
  }) {
    return _api.upsertPledge(
      _requireTenantId(),
      eventId,
      payload,
      pledgeId: pledgeId,
    );
  }

  Future<Map<String, dynamic>> recordPayment(
    String eventId,
    Map<String, dynamic> payload,
  ) {
    return _api.recordPayment(_requireTenantId(), eventId, {
      ...payload,
      'idempotencyKey': payload['idempotencyKey'] ?? _uuidV4(),
    });
  }

  Future<Map<String, dynamic>> paymentDetail(String eventId, String paymentId) {
    return _api.paymentDetail(_requireTenantId(), eventId, paymentId);
  }

  Future<Map<String, dynamic>> reversePayment(
    String eventId,
    String paymentId,
    String reason,
  ) {
    return _api.reversePayment(_requireTenantId(), eventId, paymentId, {
      'reason': reason,
      'idempotencyKey': _uuidV4(),
    });
  }

  Future<Map<String, dynamic>> receiptDetail(String receiptId) {
    return _api.receiptDetail(_requireTenantId(), receiptId);
  }

  Future<Map<String, dynamic>> whatsappShareSettings(String eventId) {
    return _api.whatsappShareSettings(_requireTenantId(), eventId);
  }

  Future<Map<String, dynamic>> updateWhatsappShareSettings(
    String eventId,
    Map<String, dynamic> payload,
  ) {
    return _api.updateWhatsappShareSettings(
      _requireTenantId(),
      eventId,
      payload,
    );
  }

  Future<Map<String, dynamic>> whatsappSharePreview(
    String eventId,
    Map<String, dynamic> payload,
  ) {
    return _api.whatsappSharePreview(_requireTenantId(), eventId, payload);
  }

  Future<List<Map<String, dynamic>>> messageHistory() {
    return _api.messageHistory(_requireTenantId());
  }

  Future<Map<String, dynamic>> smsSettings() {
    return _api.smsSettings(_requireTenantId());
  }

  Future<Map<String, dynamic>> updateSmsSettings(Map<String, dynamic> payload) {
    return _api.updateSmsSettings(_requireTenantId(), payload);
  }

  Future<Map<String, dynamic>> smsProviderOptions() {
    return _api.smsProviderOptions(_requireTenantId());
  }

  Future<List<Map<String, dynamic>>> smsTemplates() {
    return _api.smsTemplates(_requireTenantId());
  }

  Future<Map<String, dynamic>> updateSmsTemplate(
    String code,
    Map<String, dynamic> payload,
  ) {
    return _api.updateSmsTemplate(_requireTenantId(), code, payload);
  }

  Future<Map<String, dynamic>> resetSmsTemplate(String code) {
    return _api.resetSmsTemplate(_requireTenantId(), code);
  }

  Future<List<Map<String, dynamic>>> noPledgeMessageRecipients(String eventId) {
    return _api.noPledgeMessageRecipients(_requireTenantId(), eventId);
  }

  Future<Map<String, dynamic>> smsBulkPreview(
    String eventId,
    Map<String, dynamic> payload,
  ) {
    return _api.smsBulkPreview(_requireTenantId(), eventId, payload);
  }

  Future<Map<String, dynamic>> sendPledgeRequestBulk(
    String eventId,
    List<String> eventMemberIds,
  ) {
    return _api.sendPledgeRequestBulk(_requireTenantId(), eventId, {
      'eventMemberIds': eventMemberIds,
      'idempotencyKey': _uuidV4(),
    });
  }

  Future<Map<String, dynamic>> sendBalanceReminderBulk(
    String eventId,
    List<String> eventMemberIds,
  ) {
    return _api.sendBalanceReminderBulk(_requireTenantId(), eventId, {
      'eventMemberIds': eventMemberIds,
      'idempotencyKey': _uuidV4(),
    });
  }

  Future<Map<String, dynamic>> retrySms(String outboxId) {
    return _api.retrySms(_requireTenantId(), outboxId, {
      'idempotencyKey': _uuidV4(),
    });
  }

  Future<List<Map<String, dynamic>>> tenantUsers({
    String? search,
    int? limit,
    int? offset,
  }) {
    return _api.tenantUsers(
      _requireTenantId(),
      search: search,
      limit: limit,
      offset: offset,
    );
  }

  Future<Map<String, dynamic>> inviteTenantUser(Map<String, dynamic> payload) {
    final normalized = Map<String, dynamic>.from(payload);
    final phone = normalized['phone'];
    if (phone is String && phone.trim().isNotEmpty) {
      normalized['phone'] = normalizeTanzaniaPhone(phone);
    }
    return _api.inviteTenantUser(_requireTenantId(), normalized);
  }

  Future<Map<String, dynamic>> resendTenantInvitation(String invitationId) {
    return _api.resendTenantInvitation(_requireTenantId(), invitationId);
  }

  Future<Map<String, dynamic>> updateTenantUserRole(
    String tenantUserId,
    String role,
  ) {
    return _api.updateTenantUserRole(_requireTenantId(), tenantUserId, {
      'role': role,
    });
  }

  Future<Map<String, dynamic>> suspendTenantUser(String tenantUserId) {
    return _api.suspendTenantUser(_requireTenantId(), tenantUserId);
  }

  Future<Map<String, dynamic>> reactivateTenantUser(String tenantUserId) {
    return _api.reactivateTenantUser(_requireTenantId(), tenantUserId);
  }

  Future<Map<String, dynamic>> removeTenantUser(String tenantUserId) {
    return _api.removeTenantUser(_requireTenantId(), tenantUserId);
  }

  Future<void> updateProfile({
    required String fullName,
    required String email,
  }) async {
    if (isSubmitting) return;
    isSubmitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _api.updateProfile({
        'fullName': fullName.trim(),
        'email': email.trim().isEmpty ? null : email.trim(),
      });
      userContext = await _api.me();
    } catch (error) {
      errorMessage = _messageFor(error);
      rethrow;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> acceptInvitation(String invitationId) async {
    if (isSubmitting) return;
    isSubmitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      final result = await _api.acceptInvitation(invitationId);
      await _resolveAccess();
      final tenantId = result['tenantId'] is String
          ? result['tenantId'] as String
          : result['tenant_id'] is String
          ? result['tenant_id'] as String
          : null;
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

  Future<void> declineInvitation(String invitationId) async {
    if (isSubmitting) return;
    isSubmitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _api.declineInvitation(invitationId);
      userContext = await _api.me();
    } catch (error) {
      errorMessage = _messageFor(error);
      rethrow;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
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
            : num.tryParse(targetAmount.replaceAll(',', '').trim()),
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
    selectedEventId = null;
    await _storage.clearSession();
    bootstrapState = BootstrapState.unauthenticated;
    notifyListeners();
  }

  String _requireTenantId() {
    final tenantId = selectedTenantId;
    if (tenantId == null) {
      throw StateError('Select an organization first.');
    }
    return tenantId;
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
        selectedEventId = null;
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
    if (userContext?.pendingInvitations.isNotEmpty == true &&
        activeMemberships.isEmpty) {
      selectedTenantContext = null;
      selectedEventId = null;
      if (selectedTenantId != null) {
        selectedTenantId = null;
        await _storage.clearSelectedTenantId();
      }
      return;
    }

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
      selectedEventId = null;
      if (selectedTenantId != null && !storedTenant) {
        selectedTenantId = null;
        await _storage.clearSelectedTenantId();
      }
      return;
    }
    selectedTenantContext = await _api.tenantContext(tenantToSelect);
    selectedTenantId = tenantToSelect;
    await _storage.saveSelectedTenantId(tenantToSelect);
    await restoreEventForTenant();
  }

  String _messageFor(Object error) {
    if (error is ApiFailure) return error.friendlyMessage;
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
