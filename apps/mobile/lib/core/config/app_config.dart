class AppConfig {
  const AppConfig({required this.apiBaseUrl});

  final Uri apiBaseUrl;

  static AppConfig fromEnvironment() {
    const rawApiBaseUrl = String.fromEnvironment('API_BASE_URL');
    if (rawApiBaseUrl.trim().isEmpty) {
      throw StateError(
        'API_BASE_URL is required. Example: flutter run --dart-define=API_BASE_URL=http://10.0.2.2:4000/api/v1',
      );
    }
    final uri = Uri.tryParse(rawApiBaseUrl);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw StateError('API_BASE_URL must be an absolute URL.');
    }
    if (uri.scheme != 'https' &&
        uri.host != '10.0.2.2' &&
        uri.host != 'localhost') {
      throw StateError(
        'Non-HTTPS API_BASE_URL is only allowed for localhost or the Android emulator host.',
      );
    }
    return AppConfig(apiBaseUrl: uri);
  }
}
