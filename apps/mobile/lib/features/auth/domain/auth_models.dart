class SessionCredentials {
  const SessionCredentials({
    required this.accessToken,
    required this.refreshToken,
  });

  final String accessToken;
  final String refreshToken;

  Map<String, String> toStorage() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
  };

  static SessionCredentials? fromStorage(Map<String, String> values) {
    final accessToken = values['accessToken'];
    final refreshToken = values['refreshToken'];
    if (accessToken == null ||
        refreshToken == null ||
        accessToken.isEmpty ||
        refreshToken.isEmpty) {
      return null;
    }
    return SessionCredentials(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  factory SessionCredentials.fromJson(Map<String, dynamic> json) {
    return SessionCredentials(
      accessToken:
          stringValue(json, 'access_token') ??
          stringValue(json, 'accessToken') ??
          '',
      refreshToken:
          stringValue(json, 'refresh_token') ??
          stringValue(json, 'refreshToken') ??
          '',
    );
  }
}

class UserProfile {
  const UserProfile({
    required this.fullName,
    required this.phoneE164,
    this.email,
  });

  final String fullName;
  final String phoneE164;
  final String? email;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      fullName: stringValue(json, 'fullName') ?? '',
      phoneE164:
          stringValue(json, 'phoneE164') ??
          stringValue(json, 'phone_e164') ??
          '',
      email: stringValue(json, 'email'),
    );
  }
}

class SubscriptionSummary {
  const SubscriptionSummary({
    this.id,
    required this.status,
    required this.planName,
    this.planCode,
    this.trialEndsAt,
    this.currentPeriodEnd,
    this.limits = const {},
    this.eventUsage = const {},
  });

  final String? id;
  final String status;
  final String planName;
  final String? planCode;
  final String? trialEndsAt;
  final String? currentPeriodEnd;
  final Map<String, dynamic> limits;
  final Map<String, dynamic> eventUsage;

  factory SubscriptionSummary.fromJson(Map<String, dynamic> json) {
    final limitsJson = json['limits'];
    final eventUsageJson = json['eventUsage'] ?? json['event_usage'];
    return SubscriptionSummary(
      id: stringValue(json, 'id'),
      status: stringValue(json, 'status') ?? '',
      planName:
          stringValue(json, 'planName') ??
          stringValue(json, 'plan_name') ??
          stringValue(json, 'planCode') ??
          stringValue(json, 'plan_code') ??
          '',
      planCode: stringValue(json, 'planCode') ?? stringValue(json, 'plan_code'),
      trialEndsAt:
          stringValue(json, 'trialEndsAt') ??
          stringValue(json, 'trial_ends_at'),
      currentPeriodEnd:
          stringValue(json, 'currentPeriodEnd') ??
          stringValue(json, 'current_period_end'),
      limits: objectMap(limitsJson),
      eventUsage: objectMap(eventUsageJson),
    );
  }
}

class EventSummary {
  const EventSummary({
    required this.id,
    required this.name,
    required this.status,
    required this.eventType,
    this.customEventType,
    this.eventDate,
    this.venue,
    this.pledgeDeadline,
    this.targetAmount,
    this.memberCount,
    this.totalPledged,
    this.totalCollected,
    this.totalOutstanding,
  });

  final String id;
  final String name;
  final String status;
  final String eventType;
  final String? customEventType;
  final String? eventDate;
  final String? venue;
  final String? pledgeDeadline;
  final num? targetAmount;
  final num? memberCount;
  final num? totalPledged;
  final num? totalCollected;
  final num? totalOutstanding;

  factory EventSummary.fromJson(Map<String, dynamic> json) {
    return EventSummary(
      id: stringValue(json, 'id') ?? '',
      name: stringValue(json, 'name') ?? '',
      status: stringValue(json, 'status') ?? '',
      eventType:
          stringValue(json, 'eventType') ??
          stringValue(json, 'event_type') ??
          '',
      customEventType:
          stringValue(json, 'customEventType') ??
          stringValue(json, 'custom_event_type'),
      eventDate:
          stringValue(json, 'eventDate') ?? stringValue(json, 'event_date'),
      venue: stringValue(json, 'venue'),
      pledgeDeadline:
          stringValue(json, 'pledgeDeadline') ??
          stringValue(json, 'pledge_deadline'),
      targetAmount:
          numberValue(json, 'targetAmount') ??
          numberValue(json, 'target_amount'),
      memberCount:
          numberValue(json, 'memberCount') ?? numberValue(json, 'member_count'),
      totalPledged:
          numberValue(json, 'totalPledged') ??
          numberValue(json, 'total_pledged'),
      totalCollected:
          numberValue(json, 'totalCollected') ??
          numberValue(json, 'totalCollected') ??
          numberValue(json, 'total_collected') ??
          numberValue(json, 'totalPaid') ??
          numberValue(json, 'total_paid'),
      totalOutstanding:
          numberValue(json, 'totalOutstanding') ??
          numberValue(json, 'total_outstanding'),
    );
  }
}

class TenantMembership {
  const TenantMembership({
    required this.tenantId,
    required this.tenantName,
    required this.tenantStatus,
    required this.membershipStatus,
    required this.isOwner,
    required this.roles,
    required this.permissions,
    required this.accessibleEvents,
    this.subscription,
  });

  final String tenantId;
  final String tenantName;
  final String tenantStatus;
  final String membershipStatus;
  final bool isOwner;
  final List<String> roles;
  final List<String> permissions;
  final List<EventSummary> accessibleEvents;
  final SubscriptionSummary? subscription;

  bool get isAccessible {
    return membershipStatus == 'ACTIVE' &&
        (tenantStatus == 'ACTIVE' || tenantStatus == 'TRIAL');
  }

  factory TenantMembership.fromJson(Map<String, dynamic> json) {
    final subscriptionJson = json['subscription'];
    return TenantMembership(
      tenantId:
          stringValue(json, 'tenantId') ?? stringValue(json, 'tenant_id') ?? '',
      tenantName:
          stringValue(json, 'tenantName') ??
          stringValue(json, 'tenant_name') ??
          '',
      tenantStatus:
          stringValue(json, 'tenantStatus') ??
          stringValue(json, 'tenant_status') ??
          '',
      membershipStatus:
          stringValue(json, 'membershipStatus') ??
          stringValue(json, 'membership_status') ??
          '',
      isOwner: json['isOwner'] == true || json['is_owner'] == true,
      roles: stringList(json['roles']),
      permissions: stringList(json['permissions']),
      accessibleEvents: objectList(
        json['accessibleEvents'] ?? json['accessible_events'],
      ).map(EventSummary.fromJson).toList(),
      subscription: subscriptionJson is Map<String, dynamic>
          ? SubscriptionSummary.fromJson(subscriptionJson)
          : null,
    );
  }
}

class UserContext {
  const UserContext({
    required this.onboardingCompleted,
    required this.tenantMemberships,
    required this.pendingInvitations,
    this.profile,
  });

  final UserProfile? profile;
  final bool onboardingCompleted;
  final List<TenantMembership> tenantMemberships;
  final List<TenantInvitation> pendingInvitations;

  List<TenantMembership> get activeMemberships {
    return tenantMemberships
        .where((membership) => membership.isAccessible)
        .toList(growable: false);
  }

  factory UserContext.fromJson(Map<String, dynamic> json) {
    final profileJson = json['profile'];
    return UserContext(
      profile: profileJson is Map<String, dynamic>
          ? UserProfile.fromJson(profileJson)
          : null,
      onboardingCompleted:
          json['onboardingCompleted'] == true ||
          json['onboarding_completed'] == true,
      tenantMemberships: objectList(
        json['tenantMemberships'] ?? json['tenant_memberships'],
      ).map(TenantMembership.fromJson).toList(),
      pendingInvitations: objectList(
        json['pendingInvitations'] ?? json['pending_invitations'],
      ).map(TenantInvitation.fromJson).toList(),
    );
  }
}

class TenantInvitation {
  const TenantInvitation({
    required this.invitationId,
    required this.tenantId,
    required this.tenantName,
    required this.roleCode,
    required this.fullName,
    this.email,
  });

  final String invitationId;
  final String tenantId;
  final String tenantName;
  final String roleCode;
  final String fullName;
  final String? email;

  factory TenantInvitation.fromJson(Map<String, dynamic> json) {
    return TenantInvitation(
      invitationId:
          stringValue(json, 'invitationId') ??
          stringValue(json, 'invitation_id') ??
          '',
      tenantId:
          stringValue(json, 'tenantId') ?? stringValue(json, 'tenant_id') ?? '',
      tenantName:
          stringValue(json, 'tenantName') ??
          stringValue(json, 'tenant_name') ??
          '',
      roleCode:
          stringValue(json, 'roleCode') ?? stringValue(json, 'role_code') ?? '',
      fullName:
          stringValue(json, 'fullName') ?? stringValue(json, 'full_name') ?? '',
      email: stringValue(json, 'email'),
    );
  }
}

class TenantContext {
  const TenantContext({
    required this.tenantId,
    required this.tenantName,
    required this.events,
    required this.permissions,
    required this.isOwner,
    required this.accessState,
    this.subscription,
  });

  final String tenantId;
  final String tenantName;
  final List<EventSummary> events;
  final List<String> permissions;
  final bool isOwner;
  final String accessState;
  final SubscriptionSummary? subscription;

  factory TenantContext.fromJson(Map<String, dynamic> json) {
    final tenant = json['tenant'];
    final tenantMap = tenant is Map<String, dynamic>
        ? tenant
        : <String, dynamic>{};
    final membership = json['membership'];
    final membershipMap = membership is Map<String, dynamic>
        ? membership
        : <String, dynamic>{};
    final subscriptionJson = json['subscription'];
    return TenantContext(
      tenantId:
          stringValue(tenantMap, 'id') ?? stringValue(json, 'tenantId') ?? '',
      tenantName:
          stringValue(tenantMap, 'name') ??
          stringValue(json, 'tenantName') ??
          '',
      events: objectList(json['events']).map(EventSummary.fromJson).toList(),
      permissions: stringList(json['permissions']),
      isOwner:
          membershipMap['isOwner'] == true || membershipMap['is_owner'] == true,
      accessState: stringValue(json, 'accessState') ?? 'ACTIVE',
      subscription: subscriptionJson is Map<String, dynamic>
          ? SubscriptionSummary.fromJson(subscriptionJson)
          : null,
    );
  }
}

class SubscriptionPlan {
  const SubscriptionPlan({
    required this.code,
    required this.name,
    this.id,
    this.description,
    this.currency = 'TZS',
    this.priceAmount = 0,
    this.billingInterval = 'CUSTOM',
    this.trialDays = 0,
    this.maxActiveEvents = 0,
    this.maxMembers = 0,
    this.maxUsers = 0,
    this.includedSms = 0,
    this.features = const {},
    this.isPublic = true,
    this.isActive = true,
    this.displayOrder = 0,
  });

  final String? id;
  final String code;
  final String name;
  final String? description;
  final String currency;
  final num priceAmount;
  final String billingInterval;
  final int trialDays;
  final int maxActiveEvents;
  final int maxMembers;
  final int maxUsers;
  final int includedSms;
  final Map<String, dynamic> features;
  final bool isPublic;
  final bool isActive;
  final int displayOrder;

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: stringValue(json, 'id'),
      code: stringValue(json, 'code') ?? '',
      name: stringValue(json, 'name') ?? stringValue(json, 'code') ?? '',
      description: stringValue(json, 'description'),
      currency: stringValue(json, 'currency') ?? 'TZS',
      priceAmount:
          numberValue(json, 'priceAmount') ??
          numberValue(json, 'price_amount') ??
          0,
      billingInterval:
          stringValue(json, 'billingInterval') ??
          stringValue(json, 'billing_interval') ??
          'CUSTOM',
      trialDays:
          (numberValue(json, 'trialDays') ??
                  numberValue(json, 'trial_days') ??
                  0)
              .toInt(),
      maxActiveEvents:
          (numberValue(json, 'maxActiveEvents') ??
                  numberValue(json, 'max_active_events') ??
                  0)
              .toInt(),
      maxMembers:
          (numberValue(json, 'maxMembers') ??
                  numberValue(json, 'max_members') ??
                  0)
              .toInt(),
      maxUsers:
          (numberValue(json, 'maxUsers') ?? numberValue(json, 'max_users') ?? 0)
              .toInt(),
      includedSms:
          (numberValue(json, 'includedSms') ??
                  numberValue(json, 'included_sms') ??
                  0)
              .toInt(),
      features: objectMap(json['features']),
      isPublic:
          boolValue(json, 'isPublic') ?? boolValue(json, 'is_public') ?? true,
      isActive:
          boolValue(json, 'isActive') ?? boolValue(json, 'is_active') ?? true,
      displayOrder:
          (numberValue(json, 'displayOrder') ??
                  numberValue(json, 'display_order') ??
                  0)
              .toInt(),
    );
  }
}

bool? boolValue(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is bool ? value : null;
}

String? stringValue(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String ? value : null;
}

num? numberValue(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) return value;
  if (value is String) return num.tryParse(value);
  return null;
}

List<String> stringList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList(growable: false);
}

List<Map<String, dynamic>> objectList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Map<String, dynamic>>().toList(growable: false);
}

Map<String, dynamic> objectMap(Object? value) {
  return value is Map<String, dynamic> ? value : const <String, dynamic>{};
}
