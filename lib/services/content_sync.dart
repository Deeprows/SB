import 'package:flutter/foundation.dart';

/// Asks every screen to re-download its list (fixtures, highlights, movies,
/// TV). Triggered when the app returns to the foreground, every few
/// minutes while it is open, and when a push notification arrives.
class ContentSync {
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// [force] skips the 10 second throttle (used for push notifications).
  static void request({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_last) < const Duration(seconds: 10)) return;
    _last = now;
    tick.value++;
  }
}
