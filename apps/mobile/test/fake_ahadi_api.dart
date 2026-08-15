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
  int contactsCalls = 0;
  int eventMembersCalls = 0;
  int eventPledgesCalls = 0;
  String? lastTenantId;
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
      return '${row['full_name'] ?? ''} ${row['phone_e164'] ?? ''}'
          .toLowerCase()
          .contains(query);
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
      return '${row['member_name'] ?? ''} ${row['full_name'] ?? ''} ${row['phone_e164'] ?? ''}'
          .toLowerCase()
          .contains(query);
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

String _normalizedPledgeStatus(String value) {
  final status = value.trim().toUpperCase();
  if (status == 'UNPAID') return 'PENDING';
  if (status == 'PARTIAL') return 'PARTIALLY_PAID';
  if (status == 'DONE') return 'PAID';
  return status;
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
