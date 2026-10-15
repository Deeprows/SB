import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Settings you can change WITHOUT a new APK: support-ad link, movie player /
/// download links, the app-update APK link and the live-chat switch.
///
/// They live in `assets/data/app_config.json` (see REMOTE_CONFIG.md). Order of
/// use: the file on GitHub -> the last copy saved on the phone -> the copy
/// bundled in the APK -> the defaults in [AppConfig]. A key that is missing
/// falls back to the next one, so a half-filled file never breaks the app.
class RemoteConfig with WidgetsBindingObserver {
  RemoteConfig._();
  static final RemoteConfig instance = RemoteConfig._();

  static const _kCache = 'cache_app_config';
  static const _refreshGap = Duration(seconds: 60);

  Map<String, dynamic> _data = const {};
  DateTime? _lastFetch;
  bool _observing = false;
  bool _fetching = false;

  /// Bumps every time new values were applied.
  final ValueNotifier<int> changed = ValueNotifier<int>(0);

  // ------------------------------------------------------------ loading

  /// Reads the saved / bundled copy (fast, local only) and then refreshes from
  /// the network in the background. Never throws.
  Future<void> init() async {
    var loaded = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_kCache);
      if (cached != null) loaded = apply(cached);
    } catch (_) {}
    if (!loaded) {
      try {
        apply(await rootBundle.loadString('assets/data/app_config.json'));
      } catch (_) {}
    }
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
    unawaited(refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  /// Downloads the file again (at most once a minute unless [force]).
  Future<void> refresh({bool force = false}) async {
    final url = AppConfig.remoteConfigUrl.trim();
    if (url.isEmpty || _fetching) return;
    final last = _lastFetch;
    if (!force && last != null && DateTime.now().difference(last) < _refreshGap) {
      return;
    }
    _fetching = true;
    _lastFetch = DateTime.now();
    try {
      final original = Uri.parse(url);
      final uri = original.replace(queryParameters: {
        ...original.queryParameters,
        '_refresh': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      final r = await http.get(uri, headers: const {
        'Cache-Control': 'no-cache, no-store, max-age=0',
        'Pragma': 'no-cache',
      }).timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final body = utf8.decode(r.bodyBytes);
        if (apply(body)) {
          try {
            (await SharedPreferences.getInstance()).setString(_kCache, body);
          } catch (_) {}
        }
      }
    } catch (_) {
      // Offline or GitHub down: keep what we have.
    } finally {
      _fetching = false;
    }
  }

  /// Applies a JSON text (or an already decoded map). Returns false and keeps
  /// the current values when it is not a JSON object.
  bool apply(Object? source) {
    try {
      final decoded = source is String ? jsonDecode(source) : source;
      if (decoded is! Map) return false;
      _data = Map<String, dynamic>.from(decoded);
      changed.value++;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Forget everything (tests): every getter returns its [AppConfig] default.
  @visibleForTesting
  void reset() => _data = const {};

  // ------------------------------------------------------------- helpers

  Map<String, dynamic> _section(String name) {
    final s = _data[name];
    return s is Map ? Map<String, dynamic>.from(s) : const {};
  }

  /// A string that is present in the file wins, even when it is empty
  /// (e.g. an empty supportUrl switches ads off). Missing = [fallback].
  String _str(String section, String key, String fallback) {
    final v = _section(section)[key];
    return v is String ? v.trim() : fallback;
  }

  int _int(String section, String key, int fallback) {
    final v = _section(section)[key];
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  bool _bool(String section, String key, bool fallback) {
    final v = _section(section)[key];
    if (v is bool) return v;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true') return true;
      if (s == 'false') return false;
    }
    return fallback;
  }

  String _base(String v) => v.replaceAll(RegExp(r'/+$'), '');

  // ----------------------------------------------------------------- ads

  bool get adsEnabled => _bool('ads', 'enabled', true);

  /// Empty when ads are switched off, so every `isEmpty` check keeps working.
  String get supportUrl =>
      adsEnabled ? _str('ads', 'supportUrl', AppConfig.supportUrl) : '';

  int get adIntervalMinutes =>
      _int('ads', 'intervalMinutes', AppConfig.adIntervalMinutes);

  int get supportSkipAfterSeconds =>
      _int('ads', 'skipAfterSeconds', AppConfig.supportSkipAfterSeconds);

  // -------------------------------------------------------------- movies

  String get embedBase =>
      _base(_str('movies', 'embedBase', AppConfig.embedBase));
  String get altEmbedBase =>
      _base(_str('movies', 'altEmbedBase', AppConfig.altEmbedBase));
  String get thirdEmbedBase =>
      _base(_str('movies', 'thirdEmbedBase', AppConfig.thirdEmbedBase));
  String get downloadBase =>
      _base(_str('movies', 'downloadBase', AppConfig.downloadBase));

  /// Rows in movies.json that still carry a full link on one of these hosts
  /// (e.g. `vsembed.ru`) are switched to [embedBase] automatically.
  List<String> get replaceHosts {
    final v = _section('movies')['replaceHosts'];
    if (v is List) {
      return v
          .map((e) => e.toString().trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const ['vsembed.ru', 'vsembed.su'];
  }

  // -------------------------------------------------------------- update

  /// Direct link to the new .apk. Empty = no update published.
  String get updateApkUrl => _str('update', 'apkUrl', AppConfig.updateUrl);
  String get updateVersion => _str('update', 'version', '');
  String get updateNotes => _str('update', 'notes', '');

  // -------------------------------------------------------------- scores

  /// Real live scores on the fixture cards.
  bool get scoresEnabled => _bool('scores', 'enabled', true);

  /// Seconds between score lookups while the Live screen is open (20-300).
  int get scoresPollSeconds =>
      _int('scores', 'pollSeconds', 45).clamp(20, 300);

  /// Scoreboard feed. Must return ESPN-style JSON (`{"events":[...]}`); the
  /// app adds `?dates=YYYYMMDD`.
  String get scoresUrl => _str('scores', 'url',
      'https://site.api.espn.com/apis/site/v2/sports/soccer/all/scoreboard');

  // --------------------------------------------------------------- share

  /// Text sent with the APK when someone taps Share App.
  String get shareMessage => _str('share', 'message',
      'Get ${AppConfig.appName} - stream, download and save movies and series');

  /// Your download page / website, added after the message. Empty = no link.
  String get shareLink => _str('share', 'link', AppConfig.websiteUrl);

  /// The full text: "message: link" (or just the message when no link).
  String get shareText {
    final m = shareMessage;
    final l = shareLink;
    if (l.isEmpty) return m;
    return m.isEmpty ? l : '$m: $l';
  }

  // ---------------------------------------------------------------- chat

  bool get chatEnabled => _bool('chat', 'enabled', true);
}
