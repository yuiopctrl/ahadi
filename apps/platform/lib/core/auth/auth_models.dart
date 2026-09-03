String? stringValue(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String ? value : null;
}

Map<String, dynamic> jsonMap(Object? value) {
  return value is Map<String, dynamic> ? value : <String, dynamic>{};
}

List<Map<String, dynamic>> jsonList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Map<String, dynamic>>().toList();
}

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

class PlatformProfile {
  const PlatformProfile({
    required this.fullName,
    required this.phoneE164,
    this.email,
  });

  final String fullName;
  final String phoneE164;
  final String? email;

  factory PlatformProfile.fromJson(Map<String, dynamic> json) {
    return PlatformProfile(
      fullName: stringValue(json, 'fullName') ?? '',
      phoneE164: stringValue(json, 'phoneE164') ?? '',
      email: stringValue(json, 'email'),
    );
  }
}

/// Mirrors the API's UserContext shape (see packages/types/src/index.ts),
/// but the platform console only ever cares about the platform.* fields --
/// tenantMemberships are ignored, matching the spec's "do not require a
/// tenant context to use the Platform Console" rule.
class PlatformSession {
  const PlatformSession({
    required this.profile,
    required this.isPlatformUser,
    required this.platformRole,
    required this.platformStatus,
    required this.platformPermissions,
  });

  final PlatformProfile? profile;
  final bool isPlatformUser;
  final String? platformRole;
  final String? platformStatus;
  final List<String> platformPermissions;

  bool get hasActivePlatformAccess =>
      isPlatformUser && platformStatus == 'ACTIVE' && platformRole != null;

  bool hasPermission(String permission) {
    if (!hasActivePlatformAccess) return false;
    if (platformRole == 'PLATFORM_OWNER' &&
        permission.startsWith('platform.')) {
      return true;
    }
    return platformPermissions.contains(permission);
  }

  factory PlatformSession.fromJson(Map<String, dynamic> json) {
    final profileJson = json['profile'];
    return PlatformSession(
      profile: profileJson is Map<String, dynamic>
          ? PlatformProfile.fromJson(profileJson)
          : null,
      isPlatformUser: json['isPlatformUser'] == true,
      platformRole: stringValue(json, 'platformRole'),
      platformStatus: stringValue(json, 'platformStatus'),
      platformPermissions: (json['platformPermissions'] is List)
          ? (json['platformPermissions'] as List).whereType<String>().toList()
          : const [],
    );
  }
}
