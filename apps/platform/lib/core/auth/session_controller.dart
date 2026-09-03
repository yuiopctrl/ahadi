import 'package:flutter/foundation.dart';

import '../errors/api_failure.dart';
import '../networking/platform_api.dart';
import 'auth_models.dart';
import 'session_storage.dart';

enum BootstrapState { loading, loggedOut, accessDenied, ready }

/// Owns the authentication/session lifecycle for the Platform Console.
///
/// Read-only data fetching for each module is done directly against [api]
/// by the feature screens (via FutureBuilder) -- only auth state that other
/// widgets need to react to (bootstrap state, current session) lives here,
/// mirroring apps/mobile's SessionController pattern without re-wrapping
/// every single platform endpoint as a passthrough method.
class SessionController extends ChangeNotifier {
  SessionController({required this.api, SessionStorage? storage})
    : _storage = storage ?? SecureSessionStorage();

  final PlatformApi api;
  final SessionStorage _storage;

  BootstrapState _state = BootstrapState.loading;
  PlatformSession? _session;
  String? _accessToken;
  String? _lastError;

  BootstrapState get bootstrapState => _state;
  PlatformSession? get session => _session;
  String? get lastError => _lastError;

  Future<String?> get accessToken async => _accessToken;

  Future<void> bootstrap() async {
    final stored = await _storage.readSession();
    if (stored == null) {
      _state = BootstrapState.loggedOut;
      notifyListeners();
      return;
    }
    _accessToken = stored.accessToken;
    await _loadSession();
  }

  Future<void> _loadSession() async {
    try {
      final session = await api.me();
      _session = session;
      _state = session.hasActivePlatformAccess
          ? BootstrapState.ready
          : BootstrapState.accessDenied;
    } on ApiFailure catch (failure) {
      if (failure.isSessionExpired) {
        await _storage.clearSession();
        _accessToken = null;
        _state = BootstrapState.loggedOut;
      } else {
        _lastError = failure.friendlyMessage;
        _state = BootstrapState.loggedOut;
      }
    }
    notifyListeners();
  }

  Future<bool> loginWithPin({
    required String phone,
    required String pin,
  }) async {
    _lastError = null;
    try {
      final credentials = await api.loginWithPin(phone: phone, pin: pin);
      await _storage.saveSession(credentials);
      _accessToken = credentials.accessToken;
      await _loadSession();
      return true;
    } on ApiFailure catch (failure) {
      _lastError = failure.friendlyMessage;
      notifyListeners();
      return false;
    }
  }

  Future<bool> requestForgotPinOtp(String phone) async {
    _lastError = null;
    try {
      await api.requestOtp(phone);
      return true;
    } on ApiFailure catch (failure) {
      _lastError = failure.friendlyMessage;
      notifyListeners();
      return false;
    }
  }

  Future<bool> verifyForgotPinOtpAndSetPin({
    required String phone,
    required String token,
    required String newPin,
  }) async {
    _lastError = null;
    try {
      final credentials = await api.verifyOtp(phone: phone, token: token);
      await _storage.saveSession(credentials);
      _accessToken = credentials.accessToken;
      await api.setPin(newPin);
      await _loadSession();
      return true;
    } on ApiFailure catch (failure) {
      _lastError = failure.friendlyMessage;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } on ApiFailure {
      // Ignore -- we're clearing local session state regardless.
    }
    await _storage.clearSession();
    _accessToken = null;
    _session = null;
    _state = BootstrapState.loggedOut;
    notifyListeners();
  }

  bool hasPermission(String permission) =>
      _session?.hasPermission(permission) ?? false;
}
