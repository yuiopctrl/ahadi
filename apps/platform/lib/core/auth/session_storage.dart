import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_models.dart';

abstract class SessionStorage {
  Future<SessionCredentials?> readSession();
  Future<void> saveSession(SessionCredentials credentials);
  Future<void> clearSession();
}

class SecureSessionStorage implements SessionStorage {
  SecureSessionStorage({FlutterSecureStorage? secureStorage})
    : _storage = secureStorage ?? const FlutterSecureStorage();

  static const _accessTokenKey = 'changisha_platform.session.accessToken';
  static const _refreshTokenKey = 'changisha_platform.session.refreshToken';

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
  }
}

class MemorySessionStorage implements SessionStorage {
  SessionCredentials? session;

  @override
  Future<void> clearSession() async {
    session = null;
  }

  @override
  Future<SessionCredentials?> readSession() async => session;

  @override
  Future<void> saveSession(SessionCredentials credentials) async {
    session = credentials;
  }
}
