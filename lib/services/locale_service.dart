import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLanguage {
  final String code;
  final String native; // shown in the picker, in the language itself
  final String english;
  const AppLanguage(this.code, this.native, this.english);
}

/// App language: follows the phone's language until the user picks one in
/// the menu ("Automatic" goes back to following the phone).
class AppLocale {
  static const supported = <AppLanguage>[
    AppLanguage('en', 'English', 'English'),
    AppLanguage('fr', 'Français', 'French'),
    AppLanguage('es', 'Español', 'Spanish'),
    AppLanguage('pt', 'Português', 'Portuguese'),
    AppLanguage('ar', 'العربية', 'Arabic'),
    AppLanguage('sw', 'Kiswahili', 'Swahili'),
  ];

  static const auto = 'system';
  static const _key = 'footbolive_language';

  /// Language code in use right now.
  static final ValueNotifier<String> notifier = ValueNotifier<String>('en');

  static String _choice = auto;
  static _PhoneLocaleWatcher? _watcher;

  /// What the user picked: [auto] or a language code.
  static String get choice => _choice;
  static String get code => notifier.value;

  static bool _has(String c) => supported.any((l) => l.code == c);

  static String _fromPhone() {
    final phone = WidgetsBinding.instance.platformDispatcher.locales;
    for (final l in phone) {
      if (_has(l.languageCode)) return l.languageCode;
    }
    return 'en';
  }

  static String _resolve() =>
      (_choice != auto && _has(_choice)) ? _choice : _fromPhone();

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _choice = prefs.getString(_key) ?? auto;
    notifier.value = _resolve();
    _watcher ??= _PhoneLocaleWatcher();
    WidgetsBinding.instance.addObserver(_watcher!);
  }

  static Future<void> set(String choice) async {
    _choice = choice;
    await (await SharedPreferences.getInstance()).setString(_key, choice);
    _apply();
  }

  static void _apply() {
    final next = _resolve();
    if (next == notifier.value) return;
    notifier.value = next;
    // Strings are looked up while building, so mark every element for
    // rebuild (same approach as ThemeController).
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return;
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    root.visitChildren(mark);
  }
}

/// The phone's language changed while the app is open.
class _PhoneLocaleWatcher with WidgetsBindingObserver {
  @override
  void didChangeLocales(List<Locale>? locales) {
    if (AppLocale.choice == AppLocale.auto) AppLocale._apply();
  }
}
