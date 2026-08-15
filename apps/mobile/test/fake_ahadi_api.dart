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
  Map<String, dynamic>? lastOnboardingPayload;
  Map<String, dynamic>? lastCreatedEvent;
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
        'full_name': 'Jane Contact',
        'phone_e164': '+255712345678',
      },
      'events': <Map<String, dynamic>>[],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> contacts(String tenantId) async {
    contactsCalls += 1;
    lastTenantId = tenantId;
    return [
      {
        'member_id': 'member-a',
        'full_name': 'Jane Contact',
        'phone_e164': '+255712345678',
        'event_count': 1,
      },
    ];
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
        'full_name': 'Jane Contact',
        'phone_e164': '+255712345678',
        'pledged_amount': 100000,
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> eventPledges(
    String tenantId,
    String eventId,
  ) async {
    eventPledgesCalls += 1;
    lastTenantId = tenantId;
    return [
      {
        'pledge_id': 'pledge-a',
        'event_member_id': 'em-a',
        'member_name': 'Jane Contact',
        'pledged_amount': 100000,
        'total_allocated': 40000,
        'outstanding_amount': 60000,
        'status': 'PARTIALLY_PAID',
      },
    ];
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
      'members.create',
      'members.assign_event',
      'pledges.create',
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
