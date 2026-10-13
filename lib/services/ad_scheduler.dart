import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../widgets/support_overlay.dart';
import 'ad_preloader.dart';
import 'app_nav.dart';
import 'remote_config.dart';
import 'subscription_service.dart';
import 'support_gate.dart';

/// Free plan: shows the "We Need Your Support" page after every
/// [AppConfig.adIntervalMinutes] minutes of use (10). The very first tap on a
/// fixture / highlight / channel / movie also shows it (see SupportGate).
///
///  * The clock only runs while the app is open and on screen, and the
///    count is saved, so many short visits add up like one long one.
///  * It never runs for premium people, and pauses while the plans / payment
///    pages are open.
///  * After the support page has been viewed the clock starts again from 0.
class AdScheduler with WidgetsBindingObserver {
  AdScheduler._();
  static final AdScheduler instance = AdScheduler._();

  static const _kSeconds = 'ad_active_seconds';
  static const _step = Duration(seconds: 5);

  Timer? _timer;
  int _seconds = 0;
  int _unsaved = 0;
  int _holds = 0;
  bool _foreground = true;
  bool _showing = false;
  bool _started = false;

  int get _limit => RemoteConfig.instance.adIntervalMinutes * 60;

  bool get adsOn =>
      AppConfig.plansEnabled &&
      RemoteConfig.instance.adIntervalMinutes > 0 &&
      RemoteConfig.instance.supportUrl.trim().isNotEmpty &&
      !SubscriptionService.instance.isPremium;

  /// True while the overlay (from the timer) is on screen.
  bool get isShowing => _showing;

  /// Starts the next [AppConfig.adIntervalMinutes] countdown from zero (used
  /// after the first-tap overlay has been completed).
  void restartClock() {
    _seconds = 0;
    unawaited(_save());
  }

  /// Seconds of use counted so far (for tests / debugging).
  int get secondsCounted => _seconds;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _seconds = prefs.getInt(_kSeconds) ?? 0;
    } catch (_) {}
    WidgetsBinding.instance.addObserver(this);
    // Load the first ad page in the background so the first tap is instant.
    if (AppConfig.adPreloadOnStart && adsOn) AdPreloader.instance.warmUp();
    _timer = Timer.periodic(_step, (_) => _onTick());
  }

  /// Pause the clock while a page that must not be interrupted is open (the
  /// plans page and the payment window). Call [release] when it closes.
  void hold() => _holds++;
  void release() => _holds = math.max(0, _holds - 1);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      // A premium that ended (or began) while the app was closed.
      unawaited(SubscriptionService.instance.refresh());
    } else {
      _foreground = false;
      unawaited(_save());
    }
  }

  void _onTick() {
    if (!_foreground ||
        _showing ||
        SupportGate.showing ||
        _holds > 0 ||
        !adsOn) {
      return;
    }
    _seconds += _step.inSeconds;
    _unsaved += _step.inSeconds;
    if (_unsaved >= 30) unawaited(_save());
    // Shortly before the ad is due, load it in the background (YouTube style).
    if (AppConfig.adPreloadLeadSeconds > 0 &&
        _limit - _seconds <= AppConfig.adPreloadLeadSeconds) {
      AdPreloader.instance.warmUp();
    }
    if (_seconds >= _limit) unawaited(_fire());
  }

  Future<void> _fire() async {
    final ctx = AppNav.overlayContext;
    if (ctx == null || _showing || SupportGate.showing) return; // retry next tick
    _showing = true;
    SupportChoice? choice;
    try {
      choice = await showSupportOverlay(ctx);
    } finally {
      _showing = false;
    }
    switch (choice) {
      case SupportChoice.supported:
        _seconds = 0;
        SupportGate.showThanks();
      case SupportChoice.released:
        // The page would not load: nobody is locked out, ask again soon.
        _seconds = math.max(0, _limit - AppConfig.adRetryMinutes * 60);
      case SupportChoice.premium:
        _seconds = 0;
      case null:
        break;
    }
    await _save();
  }

  Future<void> _save() async {
    _unsaved = 0;
    try {
      (await SharedPreferences.getInstance()).setInt(_kSeconds, _seconds);
    } catch (_) {}
  }
}
