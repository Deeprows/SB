import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// A random, anonymous ID created the first time the app runs. It contains no
/// personal data and is only sent to YOUR Cloudflare feed (never to GitHub), so
/// the dashboard can count how many different phones use the app.
class InstallId {
  static String? _cached;

  static Future<String> get() async {
    if (_cached != null) return _cached!;
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString('install_id');
      if (id == null || id.length < 16) {
        final r = Random.secure();
        id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'))
            .join();
        await prefs.setString('install_id', id);
      }
      return _cached = id;
    } catch (_) {
      return _cached = 'unknown';
    }
  }
}
