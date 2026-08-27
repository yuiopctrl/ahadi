import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_translations.dart';

enum AppLanguage { sw, en }

class AppLocaleController extends ChangeNotifier {
  AppLocaleController({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _storageKey = 'ahadi.uiLanguage';

  final FlutterSecureStorage _storage;
  AppLanguage _language = AppLanguage.en;

  AppLanguage get language => _language;

  Future<void> load() async {
    final stored = await _storage.read(key: _storageKey);
    final resolved = AppLanguage.values.where((l) => l.name == stored);
    if (resolved.isNotEmpty && resolved.first != _language) {
      _language = resolved.first;
      notifyListeners();
    }
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (_language == language) return;
    _language = language;
    notifyListeners();
    await _storage.write(key: _storageKey, value: language.name);
  }

  String t(String key) {
    final entry = appTranslations[key];
    if (entry == null) return key;
    return entry[_language] ?? entry[AppLanguage.en] ?? key;
  }
}

class AppLocaleScope extends InheritedNotifier<AppLocaleController> {
  const AppLocaleScope({
    super.key,
    required AppLocaleController controller,
    required super.child,
  }) : super(notifier: controller);

  static final AppLocaleController _fallback = AppLocaleController();

  /// Falls back to a standalone (unpersisted) controller when no scope is
  /// present in the tree, so widgets/screens can still be tested in
  /// isolation without wrapping them in [AppLocaleScope].
  static AppLocaleController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppLocaleScope>();
    return scope?.notifier ?? _fallback;
  }
}

extension AppLocalizationX on BuildContext {
  String t(String key) => AppLocaleScope.of(this).t(key);
  AppLanguage get appLanguage => AppLocaleScope.of(this).language;
}
