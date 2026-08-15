import 'dart:async';

import 'package:ahadi_mobile/core/errors/api_failure.dart';
import 'package:ahadi_mobile/core/networking/ahadi_api.dart';
import 'package:ahadi_mobile/features/auth/domain/auth_models.dart';

class FakeAhadiApi implements AhadiApi {
  int loginPinCalls = 0;
  int requestOtpCalls = 0;
  int verifyOtpCalls = 0;
  int setPinCalls = 0;
  int accountStateCalls = 0;
  int acceptInvitationCalls = 0;
  int declineInvitationCalls = 0;
  int changePinCalls = 0;
  int logoutCalls = 0;
  int meCalls = 0;
  int tenantContextCalls = 0;
  int contactsCalls = 0;
  int eventMembersCalls = 0;
  int eventPledgesCalls = 0;
  int eventReportCalls = 0;
  int recordPaymentCalls = 0;
  int reversePaymentCalls = 0;
  int whatsappPreviewCalls = 0;
  int smsPreviewCalls = 0;
  int sendPledgeRequestCalls = 0;
  int sendBalanceReminderCalls = 0;
  int retrySmsCalls = 0;
  int tenantUsersCalls = 0;
  int inviteTenantUserCalls = 0;
  int resendTenantInvitationCalls = 0;
  int updateTenantUserRoleCalls = 0;
  int suspendTenantUserCalls = 0;
  int reactivateTenantUserCalls = 0;
  int removeTenantUserCalls = 0;
  String? lastTenantId;
  String? lastEventId;
  String? lastReportType;
  String? lastContactsSearch;
  int? lastContactsLimit;
  int? lastContactsOffset;
  String? lastPledgesSearch;
  String? lastPledgesStatus;
  int? lastPledgesLimit;
  int? lastPledgesOffset;
  Map<String, dynamic>? lastOnboardingPayload;
  Map<String, dynamic>? lastCreatedEvent;
  Map<String, dynamic>? lastUpdatedEvent;
  Map<String, dynamic>? lastCreatedContact;
  Map<String, dynamic>? lastUpdatedContact;
  Map<String, dynamic>? lastPledgePayload;
  Map<String, dynamic>? lastReportPayload;
  Map<String, dynamic>? lastPaymentPayload;
  Map<String, dynamic>? lastReversePayload;
  Map<String, dynamic>? lastShareSettingsPayload;
  Map<String, dynamic>? lastSmsPreviewPayload;
  Map<String, dynamic>? lastSmsSendPayload;
  Map<String, dynamic>? lastProfilePayload;
  Map<String, dynamic>? lastInvitePayload;
  Map<String, dynamic>? lastRolePayload;
  Completer<LoginResult>? loginCompleter;
  Completer<TenantContext>? tenantCompleter;
  Object? meError;
  Object? attachError;

  UserContext userContext = userWithMemberships([
    membership('tenant-a', 'Herosimini Committee'),
  ]);
  final Map<String, TenantContext> tenantContexts = {
    'tenant-a': makeTenantContext('tenant-a', 'Herosimini Committee'),
    'tenant-b': makeTenantContext('tenant-b', 'Valentino Group'),
  };
  final eventSummaries = <String, Map<String, dynamic>>{};
  List<Map<String, dynamic>> contactRows = [
    {
      'member_id': 'member-a',
      'full_name': 'Jane Contact',
      'phone_e164': '+255712345678',
      'event_count': 1,
    },
  ];
  List<Map<String, dynamic>> tenantUserRows = [
    {
      'tenant_user_id': 'tu-owner',
      'row_id': 'tu-owner',
      'row_type': 'USER',
      'full_name': 'Godfrey Mrema',
      'phone_e164': '+255712345678',
      'email': 'godfrey@example.com',
      'status': 'ACTIVE',
      'roles': ['TENANT_OWNER'],
      'joined_at': '2026-08-01T08:00:00Z',
    },
    {
      'tenant_user_id': 'tu-treasurer',
      'row_id': 'tu-treasurer',
      'row_type': 'USER',
      'full_name': 'Mary Joseph',
      'phone_e164': '+255713676401',
      'email': 'mary@example.com',
      'status': 'ACTIVE',
      'roles': ['TREASURER'],
      'joined_at': '2026-08-10T08:00:00Z',
    },
    {
      'invitation_id': 'inv-collector',
      'row_id': 'inv-collector',
      'row_type': 'INVITATION',
      'full_name': 'John Mushi',
      'phone_e164': '+255754000111',
      'email': null,
      'status': 'INVITED',
      'roles': ['COLLECTOR'],
      'created_at': '2026-08-15T08:00:00Z',
    },
  ];

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
  Future<Map<String, dynamic>> createEvent(
    String tenantId,
    Map<String, dynamic> payload,
  ) async {
    lastTenantId = tenantId;
    lastCreatedEvent = payload;
    return {'eventId': 'event-new', ...payload};
  }

  @override
  Future<Map<String, dynamic>> updateEvent(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  ) async {
    lastTenantId = tenantId;
    lastUpdatedEvent = payload;
    final context = tenantContexts[tenantId];
    if (context != null) {
      tenantContexts[tenantId] = TenantContext(
        tenantId: context.tenantId,
        tenantName: context.tenantName,
        events: context.events
            .map(
              (event) => event.id == eventId
                  ? EventSummary(
                      id: event.id,
                      name: payload['name'] as String? ?? event.name,
                      status: event.status,
                      eventType:
                          payload['eventType'] as String? ?? event.eventType,
                      customEventType:
                          payload['customEventType'] as String? ??
                          event.customEventType,
                      eventDate:
                          payload['eventDate'] as String? ?? event.eventDate,
                      venue: payload['venue'] as String? ?? event.venue,
                      pledgeDeadline:
                          payload['pledgeDeadline'] as String? ??
                          event.pledgeDeadline,
                      targetAmount:
                          payload['targetAmount'] as num? ?? event.targetAmount,
                      memberCount: event.memberCount,
                      totalPledged: event.totalPledged,
                      totalCollected: event.totalCollected,
                      totalOutstanding: event.totalOutstanding,
                    )
                  : event,
            )
            .toList(),
        permissions: context.permissions,
        isOwner: context.isOwner,
        accessState: context.accessState,
        subscription: context.subscription,
      );
    }
    return {'id': eventId, ...payload};
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
  Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> payload,
  ) async {
    lastProfilePayload = payload;
    userContext = UserContext(
      profile: UserProfile(
        fullName:
            payload['fullName'] as String? ??
            userContext.profile?.fullName ??
            '',
        phoneE164: userContext.profile?.phoneE164 ?? '+255712345678',
        email: payload['email'] as String?,
      ),
      onboardingCompleted: userContext.onboardingCompleted,
      tenantMemberships: userContext.tenantMemberships,
      pendingInvitations: userContext.pendingInvitations,
    );
    return {
      'full_name': userContext.profile?.fullName,
      'phone_e164': userContext.profile?.phoneE164,
      'email': userContext.profile?.email,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> tenantUsers(
    String tenantId, {
    String? search,
    int? limit,
    int? offset,
  }) async {
    tenantUsersCalls += 1;
    lastTenantId = tenantId;
    final query = (search ?? '').toLowerCase();
    final filtered = tenantUserRows.where((row) {
      if (query.isEmpty) return true;
      return _matchesNameOrPhone(
        row,
        query,
        ['full_name', 'fullName'],
        ['phone_e164', 'phoneE164', 'phone'],
      );
    }).toList();
    return filtered.skip(offset ?? 0).take(limit ?? filtered.length).toList();
  }

  @override
  Future<Map<String, dynamic>> inviteTenantUser(
    String tenantId,
    Map<String, dynamic> payload,
  ) async {
    inviteTenantUserCalls += 1;
    lastTenantId = tenantId;
    lastInvitePayload = payload;
    final row = {
      'invitation_id': 'inv-new',
      'row_id': 'inv-new',
      'row_type': 'INVITATION',
      'full_name': payload['fullName'],
      'phone_e164': payload['phone'],
      'email': payload['email'],
      'status': 'INVITED',
      'roles': [payload['role']],
      'created_at': '2026-08-15T09:00:00Z',
    };
    tenantUserRows.add(row);
    return {'kind': 'INVITATION', 'invitationId': 'inv-new'};
  }

  @override
  Future<Map<String, dynamic>> resendTenantInvitation(
    String tenantId,
    String invitationId,
  ) async {
    resendTenantInvitationCalls += 1;
    lastTenantId = tenantId;
    return {'invitationId': invitationId, 'resent': true};
  }

  @override
  Future<Map<String, dynamic>> updateTenantUserRole(
    String tenantId,
    String tenantUserId,
    Map<String, dynamic> payload,
  ) async {
    updateTenantUserRoleCalls += 1;
    lastTenantId = tenantId;
    lastRolePayload = payload;
    return {
      'tenantUserId': tenantUserId,
      'roles': [payload['role']],
    };
  }

  @override
  Future<Map<String, dynamic>> suspendTenantUser(
    String tenantId,
    String tenantUserId,
  ) async {
    suspendTenantUserCalls += 1;
    return {'tenantUserId': tenantUserId, 'status': 'SUSPENDED'};
  }

  @override
  Future<Map<String, dynamic>> reactivateTenantUser(
    String tenantId,
    String tenantUserId,
  ) async {
    reactivateTenantUserCalls += 1;
    return {'tenantUserId': tenantUserId, 'status': 'ACTIVE'};
  }

  @override
  Future<Map<String, dynamic>> removeTenantUser(
    String tenantId,
    String tenantUserId,
  ) async {
    removeTenantUserCalls += 1;
    return {'tenantUserId': tenantUserId, 'status': 'REMOVED'};
  }

  @override
  Future<Map<String, dynamic>> contactDetail(
    String tenantId,
    String memberId,
  ) async {
    lastTenantId = tenantId;
    return {
      'contact': {
        'id': memberId,
        'member_id': memberId,
        'full_name': 'Jane Contact',
        'phone_e164': '+255712345678',
      },
      'events': <Map<String, dynamic>>[],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> contacts(
    String tenantId, {
    String? search,
    int? limit,
    int? offset,
  }) async {
    contactsCalls += 1;
    lastTenantId = tenantId;
    lastContactsSearch = search;
    lastContactsLimit = limit;
    lastContactsOffset = offset;
    final rows = contactRows;
    final filtered = rows.where((row) {
      final query = search?.toLowerCase() ?? '';
      if (query.isEmpty) return true;
      return _matchesNameOrPhone(
        row,
        query,
        ['full_name'],
        ['phone_e164', 'alternative_phone_e164'],
      );
    }).toList();
    return filtered.skip(offset ?? 0).take(limit ?? filtered.length).toList();
  }

  @override
  Future<Map<String, dynamic>> createContact(
    String tenantId,
    Map<String, dynamic> payload,
  ) async {
    lastTenantId = tenantId;
    lastCreatedContact = payload;
    return {'member_id': 'member-new', ...payload};
  }

  @override
  Future<Map<String, dynamic>> updateContact(
    String tenantId,
    String memberId,
    Map<String, dynamic> payload,
  ) async {
    lastTenantId = tenantId;
    lastUpdatedContact = payload;
    return {'member_id': memberId, ...payload};
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
  Future<List<Map<String, dynamic>>> availableContactsForEvent(
    String tenantId,
    String eventId,
  ) async {
    lastTenantId = tenantId;
    return [
      {
        'member_id': 'member-a',
        'full_name': 'Jane Contact',
        'phone_e164': '+255712345678',
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> attachEventMember(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  ) async {
    lastTenantId = tenantId;
    final error = attachError;
    if (error != null) throw error;
    return {'event_member_id': 'em-new', ...payload};
  }

  @override
  Future<Map<String, dynamic>> eventMemberDetail(
    String tenantId,
    String eventId,
    String eventMemberId,
  ) async {
    lastTenantId = tenantId;
    return {
      'member': {
        'event_member_id': eventMemberId,
        'full_name': 'Jane Contact',
        'phone_e164': '+255712345678',
        'pledged_amount': 100000,
        'total_allocated': 40000,
        'outstanding_amount': 60000,
        'pledge_status': 'PARTIALLY_PAID',
      },
      'payments': <Map<String, dynamic>>[],
    };
  }

  @override
  Future<Map<String, dynamic>> createEventMember(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  ) async {
    lastTenantId = tenantId;
    return {'event_member_id': 'em-new', ...payload};
  }

  @override
  Future<Map<String, dynamic>> eventFinancialSummary(
    String tenantId,
    String eventId,
  ) async {
    lastTenantId = tenantId;
    final configured = eventSummaries[eventId];
    if (configured != null) return configured;
    return {
      'totalPledged': 100000,
      'totalAllocated': 40000,
      'totalOutstanding': 60000,
      'memberCount': 1,
    };
  }

  @override
  Future<Map<String, dynamic>> eventReport(
    String tenantId,
    String eventId,
    String reportType,
    Map<String, dynamic> payload,
  ) async {
    eventReportCalls += 1;
    lastTenantId = tenantId;
    lastEventId = eventId;
    lastReportType = reportType;
    lastReportPayload = payload;
    final page = payload['page'] is int ? payload['page'] as int : 1;
    final pageSize = payload['pageSize'] is int
        ? payload['pageSize'] as int
        : 20;
    final search = (payload['search'] as String? ?? '').toLowerCase();
    if (reportType == 'payments') {
      final filtered = _paymentRows.where((row) {
        if (search.isEmpty) return true;
        return '${row['member']} ${row['receiptNumber']} ${row['transactionReference']}'
            .toLowerCase()
            .contains(search);
      }).toList();
      return _report(filtered, page, pageSize);
    }
    if (reportType == 'outstanding') {
      final filtered = _outstandingRows.where((row) {
        if (search.isEmpty) return true;
        return '${row['member']} ${row['phone']}'.toLowerCase().contains(
          search,
        );
      }).toList();
      return {
        ..._report(filtered, page, pageSize),
        'summary': {
          'totalOutstanding': filtered.fold<num>(
            0,
            (sum, row) => sum + (row['outstanding'] as num),
          ),
          'outstandingMembers': filtered.length,
          'overdueMembers': 0,
        },
      };
    }
    return _report(<Map<String, dynamic>>[], page, pageSize);
  }

  @override
  Future<List<Map<String, dynamic>>> eventMembers(
    String tenantId,
    String eventId,
  ) async {
    eventMembersCalls += 1;
    lastTenantId = tenantId;
    return [
      {
        'event_member_id': 'em-a',
        'member_id': 'member-a',
        'full_name': 'Jane Contact',
        'phone_e164': '+255712345678',
        'pledged_amount': 100000,
        'total_allocated': 40000,
        'outstanding_amount': 60000,
        'pledge_status': 'PARTIALLY_PAID',
      },
    ];
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
    eventPledgesCalls += 1;
    lastTenantId = tenantId;
    lastPledgesSearch = search;
    lastPledgesStatus = status;
    lastPledgesLimit = limit;
    lastPledgesOffset = offset;
    final rows = [
      {
        'pledge_id': 'pledge-a',
        'event_member_id': 'em-a',
        'member_name': 'Jane Contact',
        'phone_e164': '+255712345678',
        'pledged_amount': 100000,
        'total_allocated': 40000,
        'outstanding_amount': 60000,
        'status': 'PARTIALLY_PAID',
        'due_date': '2026-08-24',
        'created_at': '2026-08-01',
      },
      {
        'pledge_id': 'pledge-b',
        'event_member_id': 'em-b',
        'member_name': 'Unpaid Contact',
        'phone_e164': '+255712345679',
        'pledged_amount': 80000,
        'total_allocated': 0,
        'outstanding_amount': 80000,
        'pledge_status': 'PENDING',
        'due_date': '2026-08-25',
        'created_at': '2026-08-02',
      },
      {
        'pledge_id': 'pledge-c',
        'event_member_id': 'em-c',
        'member_name': 'Done Contact',
        'phone_e164': '+255712345680',
        'pledged_amount': 50000,
        'total_allocated': 50000,
        'outstanding_amount': 0,
        'pledgeStatus': 'PAID',
        'due_date': '2026-08-26',
        'created_at': '2026-08-03',
      },
    ];
    final filtered = rows.where((row) {
      final statusQuery = _normalizedPledgeStatus(status ?? 'ALL');
      final rowStatus = _normalizedPledgeStatus(
        '${row['status'] ?? row['pledge_status'] ?? row['pledgeStatus'] ?? ''}',
      );
      if (statusQuery != 'ALL' && rowStatus != statusQuery) return false;
      final query = search?.toLowerCase() ?? '';
      if (query.isEmpty) return true;
      return _matchesNameOrPhone(
        row,
        query,
        ['member_name', 'full_name'],
        ['phone_e164', 'alternative_phone_e164'],
      );
    }).toList();
    return filtered.skip(offset ?? 0).take(limit ?? filtered.length).toList();
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
  Future<Map<String, dynamic>> accountState(String phone) async {
    accountStateCalls += 1;
    return {
      'phone': phone,
      'state': 'NEW_PHONE',
      'existingVerifiedAccount': false,
    };
  }

  @override
  Future<void> setPin({required String pin, required String confirmPin}) async {
    setPinCalls += 1;
  }

  @override
  Future<Map<String, dynamic>> acceptInvitation(String invitationId) async {
    acceptInvitationCalls += 1;
    final invitation = userContext.pendingInvitations.firstWhere(
      (item) => item.invitationId == invitationId,
      orElse: () => const TenantInvitation(
        invitationId: 'invitation-a',
        tenantId: 'tenant-a',
        tenantName: 'Herosimini Committee',
        roleCode: 'VIEWER',
        fullName: '',
      ),
    );
    userContext = UserContext(
      profile: userContext.profile,
      onboardingCompleted: true,
      tenantMemberships: [
        ...userContext.tenantMemberships,
        membership(invitation.tenantId, invitation.tenantName),
      ],
      pendingInvitations: userContext.pendingInvitations
          .where((item) => item.invitationId != invitationId)
          .toList(),
    );
    tenantContexts[invitation.tenantId] = makeTenantContext(
      invitation.tenantId,
      invitation.tenantName,
    );
    return {'ok': true, 'tenantId': invitation.tenantId};
  }

  @override
  Future<Map<String, dynamic>> declineInvitation(String invitationId) async {
    declineInvitationCalls += 1;
    userContext = UserContext(
      profile: userContext.profile,
      onboardingCompleted: userContext.onboardingCompleted,
      tenantMemberships: userContext.tenantMemberships,
      pendingInvitations: userContext.pendingInvitations
          .where((item) => item.invitationId != invitationId)
          .toList(),
    );
    return {'ok': true};
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
  Future<Map<String, dynamic>> upsertPledge(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload, {
    String? pledgeId,
  }) async {
    lastTenantId = tenantId;
    lastPledgePayload = payload;
    return {'pledge_id': pledgeId ?? 'pledge-new', ...payload};
  }

  @override
  Future<Map<String, dynamic>> recordPayment(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  ) async {
    recordPaymentCalls += 1;
    lastTenantId = tenantId;
    lastEventId = eventId;
    lastPaymentPayload = payload;
    return {
      'payment_id': 'payment-new',
      'payment_number': 'PAY-0002',
      'receipt_id': 'receipt-new',
      'receipt_number': 'AHADI-0002',
      'payment_amount': payload['amount'],
      'allocated_amount': payload['amount'],
      'unallocated_amount': 0,
      'outstanding_amount': 0,
      'pledge_status': 'PAID',
    };
  }

  @override
  Future<Map<String, dynamic>> paymentDetail(
    String tenantId,
    String eventId,
    String paymentId,
  ) async {
    lastTenantId = tenantId;
    lastEventId = eventId;
    return _paymentRows.firstWhere(
      (row) => row['paymentId'] == paymentId,
      orElse: () => _paymentRows.first,
    );
  }

  @override
  Future<Map<String, dynamic>> reversePayment(
    String tenantId,
    String eventId,
    String paymentId,
    Map<String, dynamic> payload,
  ) async {
    reversePaymentCalls += 1;
    lastTenantId = tenantId;
    lastEventId = eventId;
    lastReversePayload = payload;
    return {'paymentId': paymentId, 'status': 'REVERSED'};
  }

  @override
  Future<Map<String, dynamic>> receiptDetail(
    String tenantId,
    String receiptId,
  ) async {
    lastTenantId = tenantId;
    return {
      'receipt_id': receiptId,
      'receipt_number': 'AHADI-0001',
      'member_name': 'Jane Contact',
      'payment_amount': 150000,
      'allocated_amount': 100000,
      'unallocated_excess': 50000,
      'payment_method': 'CASH',
      'payment_date': '2026-08-15T08:00:00Z',
      'payment_status': 'CONFIRMED',
      'received_by_name': 'Treasurer',
    };
  }

  @override
  Future<Map<String, dynamic>> whatsappShareSettings(
    String tenantId,
    String eventId,
  ) async {
    lastTenantId = tenantId;
    return {
      'headerText': 'AHADI ZA HARUSI YA MAIN EVENT',
      'footerText': '© AHADI APP',
      'showPaymentInstructions': true,
      'paymentInstructions': 'TUMA KWA:\nM-Pesa: 0712345678',
      'showAlama': true,
      'alamaLabels': {
        'completed': 'Amemaliza',
        'partial': 'Amepunguza',
        'noPledge': 'Hajatoa Ahadi',
      },
      'defaultListFormat': 'DETAILED',
      'defaultSort': 'ORIGINAL',
      'defaultIncludeSummary': true,
    };
  }

  @override
  Future<Map<String, dynamic>> updateWhatsappShareSettings(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  ) async {
    lastTenantId = tenantId;
    lastEventId = eventId;
    lastShareSettingsPayload = payload;
    return payload;
  }

  @override
  Future<Map<String, dynamic>> whatsappSharePreview(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  ) async {
    whatsappPreviewCalls += 1;
    lastTenantId = tenantId;
    lastEventId = eventId;
    return {
      'text': '*AHADI ZA HARUSI YA MAIN EVENT*\n\nTUMA KWA:\nM-Pesa: 0712345678\n\n1. Jane Contact - TZS 100,000 ✅✅\n\n*MUHTASARI*\nJumla ya Ahadi: TZS 100,000\n\nAlama:\n✅✅ -- Amemaliza\n© AHADI APP',
    };
  }

  @override
  Future<List<Map<String, dynamic>>> messageHistory(String tenantId) async {
    lastTenantId = tenantId;
    return [
      {
        'id': 'sms-a',
        'event_id': 'event-1',
        'event_name': 'Main Event',
        'member_name': 'Jane Contact',
        'phone_e164': '+255712345678',
        'template_code': 'BALANCE_REMINDER',
        'message_type': 'Balance Reminder',
        'message_body': 'Ndugu Jane, salio lako ni TZS 60,000.',
        'status': 'SENT',
        'sender_id': 'MICHANGO',
        'provider': 'NEXTSMS',
        'created_at': '2026-08-15T14:00:00Z',
        'sent_at': '2026-08-15T14:01:00Z',
        'batch_id': 'batch-a',
      },
      {
        'id': 'sms-b',
        'event_id': 'event-1',
        'event_name': 'Main Event',
        'member_name': 'Unpaid Contact',
        'phone_e164': '+255712345679',
        'template_code': 'BALANCE_REMINDER',
        'message_type': 'Balance Reminder',
        'message_body': 'Ndugu Unpaid, salio lako ni TZS 80,000.',
        'status': 'FAILED',
        'sender_id': 'MICHANGO',
        'provider': 'NEXTSMS',
        'created_at': '2026-08-15T14:00:00Z',
        'last_error_message': 'Provider rejected the message.',
        'batch_id': 'batch-a',
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> smsSettings(String tenantId) async {
    lastTenantId = tenantId;
    return {
      'smsEnabled': true,
      'provider': 'NEXTSMS',
      'senderId': 'MICHANGO',
      'defaultLanguage': 'sw',
      'allowedSenderIds': ['MICHANGO', 'SHEREHE'],
    };
  }

  @override
  Future<Map<String, dynamic>> updateSmsSettings(
    String tenantId,
    Map<String, dynamic> payload,
  ) async {
    lastTenantId = tenantId;
    return {'smsEnabled': payload['smsEnabled'], ...payload};
  }

  @override
  Future<Map<String, dynamic>> smsProviderOptions(String tenantId) async {
    lastTenantId = tenantId;
    return {
      'providers': [
        {
          'provider': 'NEXTSMS',
          'senderIds': [
            {'senderId': 'MICHANGO'},
            {'senderId': 'SHEREHE'},
          ],
        },
        {
          'provider': 'WEBBULKSMS',
          'senderIds': [
            {'senderId': 'MICHANGO'},
          ],
        },
      ],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> smsTemplates(String tenantId) async {
    lastTenantId = tenantId;
    return [
      {
        'code': 'PLEDGE_REQUEST',
        'body':
            'Ndugu {{member_name}}, tunaomba uweke ahadi kwa {{event_name}}.',
        'variables': ['member_name', 'event_name'],
        'samplePreview':
            'Ndugu Jane Contact, tunaomba uweke ahadi kwa Main Event.',
        'samplePreviewCharacters': 58,
        'maxCharacters': 159,
        'language': 'sw',
      },
      {
        'code': 'BALANCE_REMINDER',
        'body': 'Ndugu {{member_name}}, salio lako ni TZS {{balance}}.',
        'variables': ['member_name', 'balance'],
        'samplePreview': 'Ndugu Jane Contact, salio lako ni TZS 60,000.',
        'samplePreviewCharacters': 48,
        'maxCharacters': 159,
        'language': 'sw',
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> updateSmsTemplate(
    String tenantId,
    String code,
    Map<String, dynamic> payload,
  ) async {
    lastTenantId = tenantId;
    return {'code': code, ...payload};
  }

  @override
  Future<Map<String, dynamic>> resetSmsTemplate(
    String tenantId,
    String code,
  ) async {
    lastTenantId = tenantId;
    return {'code': code, 'body': 'Reset body'};
  }

  @override
  Future<List<Map<String, dynamic>>> noPledgeMessageRecipients(
    String tenantId,
    String eventId,
  ) async {
    lastTenantId = tenantId;
    lastEventId = eventId;
    return [
      {
        'eventMemberId': 'em-b',
        'memberId': 'member-b',
        'fullName': 'Unpaid Contact',
        'phone': '+255712345679',
        'maskedPhone': '+255*****679',
        'ineligibleReason': null,
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> smsBulkPreview(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  ) async {
    smsPreviewCalls += 1;
    lastTenantId = tenantId;
    lastEventId = eventId;
    lastSmsPreviewPayload = payload;
    return {
      'templateCode': payload['templateCode'],
      'validMessages': (payload['eventMemberIds'] as List?)?.length ?? 0,
      'samplePreview': payload['templateCode'] == 'PLEDGE_REQUEST'
          ? 'Ndugu Unpaid Contact, tunaomba uweke ahadi kwa Main Event.'
          : 'Ndugu Jane Contact, salio lako ni TZS 60,000.',
      'samplePreviewCharacters': 55,
      'maxCharacters': 159,
    };
  }

  @override
  Future<Map<String, dynamic>> sendPledgeRequestBulk(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  ) async {
    sendPledgeRequestCalls += 1;
    lastTenantId = tenantId;
    lastEventId = eventId;
    lastSmsSendPayload = payload;
    return {'queued': (payload['eventMemberIds'] as List?)?.length ?? 0};
  }

  @override
  Future<Map<String, dynamic>> sendBalanceReminderBulk(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  ) async {
    sendBalanceReminderCalls += 1;
    lastTenantId = tenantId;
    lastEventId = eventId;
    lastSmsSendPayload = payload;
    return {'queued': (payload['eventMemberIds'] as List?)?.length ?? 0};
  }

  @override
  Future<Map<String, dynamic>> retrySms(
    String tenantId,
    String outboxId,
    Map<String, dynamic> payload,
  ) async {
    retrySmsCalls += 1;
    lastTenantId = tenantId;
    return {'queued': true, 'outboxId': outboxId};
  }

  @override
  Future<Map<String, dynamic>> removeEventMember(
    String tenantId,
    String eventId,
    String eventMemberId,
    Map<String, dynamic> payload,
  ) async {
    lastTenantId = tenantId;
    return {'event_member_id': eventMemberId, 'removed': true};
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

String _compactPhoneSearch(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('255')) return digits.substring(3);
  if (digits.startsWith('0')) return digits.substring(1);
  return digits;
}

bool _matchesNameOrPhone(
  Map<String, dynamic> row,
  String search,
  List<String> nameKeys,
  List<String> phoneKeys,
) {
  final textSearch = search.trim().toLowerCase();
  if (textSearch.isEmpty) return true;
  final textHaystack = nameKeys
      .map((key) => '${row[key] ?? ''}')
      .join(' ')
      .toLowerCase();
  if (textHaystack.contains(textSearch)) return true;
  final phoneNeedle = _compactPhoneSearch(textSearch);
  if (phoneNeedle.isEmpty) return false;
  return phoneKeys.any(
    (key) => _compactPhoneSearch('${row[key] ?? ''}').contains(phoneNeedle),
  );
}

Map<String, dynamic> _report(
  List<Map<String, dynamic>> rows,
  int page,
  int pageSize,
) {
  final start = (page - 1) * pageSize;
  final paged = rows.skip(start).take(pageSize).toList();
  return {
    'data': paged,
    'summary': <String, dynamic>{},
    'pagination': {
      'page': page,
      'pageSize': pageSize,
      'totalRows': rows.length,
      'totalPages': rows.isEmpty ? 0 : (rows.length / pageSize).ceil(),
    },
  };
}

final _paymentRows = <Map<String, dynamic>>[
  {
    'paymentId': 'payment-a',
    'receiptId': 'receipt-a',
    'receiptNumber': 'AHADI-0001',
    'eventMemberId': 'em-a',
    'member': 'Jane Contact',
    'amount': 150000,
    'allocatedAmount': 100000,
    'unallocatedAmount': 50000,
    'paymentMethod': 'CASH',
    'transactionReference': '',
    'receivedBy': 'Treasurer',
    'status': 'CONFIRMED',
    'date': '2026-08-15T08:00:00Z',
  },
];

final _outstandingRows = <Map<String, dynamic>>[
  {
    'pledgeId': 'pledge-a',
    'eventMemberId': 'em-a',
    'member': 'Jane Contact',
    'phone': '+255712345678',
    'pledged': 100000,
    'paid': 40000,
    'outstanding': 60000,
    'effectiveDueDate': '2026-08-24',
    'status': 'PARTIALLY_PAID',
  },
];

String _normalizedPledgeStatus(String value) {
  final status = value.trim().toUpperCase();
  if (status == 'UNPAID') return 'PENDING';
  if (status == 'PARTIAL') return 'PARTIALLY_PAID';
  if (status == 'DONE') return 'PAID';
  return status;
}

UserContext userWithMemberships(
  List<TenantMembership> memberships, {
  List<TenantInvitation> pendingInvitations = const [],
}) {
  return UserContext(
    profile: const UserProfile(
      fullName: 'Test Doctor',
      phoneE164: '+255712345678',
      email: 'test@example.com',
    ),
    onboardingCompleted: true,
    tenantMemberships: memberships,
    pendingInvitations: pendingInvitations,
  );
}

TenantInvitation invitation(String id, String tenantId, String tenantName) {
  return TenantInvitation(
    invitationId: id,
    tenantId: tenantId,
    tenantName: tenantName,
    fullName: 'Mary Joseph',
    email: null,
    roleCode: 'TREASURER',
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
      EventSummary(
        id: 'event-1',
        name: 'Main Event',
        status: 'ACTIVE',
        eventType: 'WEDDING',
      ),
    ],
    subscription: const SubscriptionSummary(status: 'TRIAL', planName: 'Basic'),
  );
}

TenantContext makeTenantContext(
  String id,
  String name, {
  List<EventSummary> events = const [
    EventSummary(
      id: 'event-1',
      name: 'Main Event',
      status: 'ACTIVE',
      eventType: 'WEDDING',
      eventDate: '2026-08-24',
      totalPledged: 100000,
      totalCollected: 40000,
      totalOutstanding: 60000,
    ),
  ],
}) {
  return TenantContext(
    tenantId: id,
    tenantName: name,
    events: events,
    permissions: const [
      'events.view',
      'events.create',
      'events.update',
      'members.create',
      'members.update',
      'members.assign_event',
      'pledges.create',
      'pledges.update',
      'messages.view',
      'messages.send',
      'messages.manage_settings',
      'users.view',
      'users.invite',
      'users.manage_roles',
      'users.suspend',
    ],
    isOwner: true,
    accessState: 'ACTIVE',
    subscription: const SubscriptionSummary(status: 'TRIAL', planName: 'Basic'),
  );
}

const expiredSessionFailure = ApiFailure(
  kind: ApiFailureKind.unauthenticated,
  message: 'Session required',
  code: 'SESSION_REQUIRED',
  statusCode: 401,
);
