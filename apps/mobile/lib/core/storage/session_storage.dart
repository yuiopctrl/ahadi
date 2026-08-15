import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/auth/domain/auth_models.dart';

abstract class SessionStorage {
  Future<SessionCredentials?> readSession();
  Future<void> saveSession(SessionCredentials credentials);
  Future<void> clearSession();
  Future<String?> readSelectedTenantId();
  Future<void> saveSelectedTenantId(String tenantId);
  Future<void> clearSelectedTenantId();
  Future<String?> readSelectedEventId(String tenantId);
  Future<void> saveSelectedEventId(String tenantId, String eventId);
  Future<void> clearSelectedEventId(String tenantId);
}

class SecureSessionStorage implements SessionStorage {
  SecureSessionStorage({FlutterSecureStorage? secureStorage})
    : _storage = secureStorage ?? const FlutterSecureStorage();

  static const _accessTokenKey = 'ahadi.session.accessToken';
  static const _refreshTokenKey = 'ahadi.session.refreshToken';
  static const _selectedTenantKey = 'ahadi.selectedTenantId';

  final FlutterSecureStorage _storage;

  @override
  Future<SessionCredentials?> readSession() async {
    final accessToken = await _storage.read(key: _accessTokenKey);
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (accessToken == null || refreshToken == null) {
      return null;
    }
    return SessionCredentials.fromStorage({
      'accessToken': accessToken,
      'refreshToken': refreshToken,
    });
  }

  @override
  Future<void> saveSession(SessionCredentials credentials) async {
    await _storage.write(key: _accessTokenKey, value: credentials.accessToken);
    await _storage.write(
      key: _refreshTokenKey,
      value: credentials.refreshToken,
    );
  }

  @override
  Future<void> clearSession() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await clearSelectedTenantId();
  }

  @override
  Future<String?> readSelectedTenantId() =>
      _storage.read(key: _selectedTenantKey);

  @override
  Future<void> saveSelectedTenantId(String tenantId) =>
      _storage.write(key: _selectedTenantKey, value: tenantId);

  @override
  Future<void> clearSelectedTenantId() =>
      _storage.delete(key: _selectedTenantKey);

  @override
  Future<String?> readSelectedEventId(String tenantId) =>
      _storage.read(key: _selectedEventKey(tenantId));

  @override
  Future<void> saveSelectedEventId(String tenantId, String eventId) =>
      _storage.write(key: _selectedEventKey(tenantId), value: eventId);

  @override
  Future<void> clearSelectedEventId(String tenantId) =>
      _storage.delete(key: _selectedEventKey(tenantId));

  String _selectedEventKey(String tenantId) =>
      'ahadi.selectedEventId.$tenantId';
}

class MemorySessionStorage implements SessionStorage {
  SessionCredentials? session;
  String? selectedTenantId;
  final selectedEventIds = <String, String>{};

  @override
  Future<void> clearSelectedTenantId() async {
    selectedTenantId = null;
  }

  @override
  Future<void> clearSession() async {
    session = null;
    selectedTenantId = null;
    selectedEventIds.clear();
  }

  @override
  Future<String?> readSelectedTenantId() async => selectedTenantId;

  @override
  Future<SessionCredentials?> readSession() async => session;

  @override
  Future<void> saveSelectedTenantId(String tenantId) async {
    selectedTenantId = tenantId;
  }

  @override
  Future<void> saveSession(SessionCredentials credentials) async {
    session = credentials;
  }

  @override
  Future<String?> readSelectedEventId(String tenantId) async =>
      selectedEventIds[tenantId];

  @override
  Future<void> saveSelectedEventId(String tenantId, String eventId) async {
    selectedEventIds[tenantId] = eventId;
  }

  @override
  Future<void> clearSelectedEventId(String tenantId) async {
    selectedEventIds.remove(tenantId);
  }
}
