import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/analytics_service.dart';
import 'services/auth_service.dart';
import 'services/download_manager.dart';
import 'services/locale_service.dart';
import 'services/remote_config.dart';
import 'services/subscription_service.dart';
import 'theme/app_theme.dart';

/// Runs one start-up step without ever letting it stop the app from opening:
/// errors are swallowed and a step that hangs is abandoned after [limit].
Future<void> _safe(
  String name,
  Future<void> Function() step, {
  Duration limit = const Duration(seconds: 4),
}) async {
  try {
    await step().timeout(limit);
  } catch (e) {
    debugPrint('Start-up step "$name" skipped: $e');
  }
}

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exceptionAsString()}');
    };

    // Everything before runApp() keeps the native splash on screen, so each
    // step is guarded: a failing or hanging plugin can no longer freeze the
    // app on the splash.
    await _safe('orientation', () => SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]));

    // Saved theme (Midnight Violet until the person picks another).
    await _safe('theme', ThemeController.load);

    // Phone language (or the language picked in the menu).
    await _safe('language', AppLocale.load);

    // Ad / movie / update settings: saved copy now, fresh copy in the
    // background (never blocks start-up).
    await _safe('remote config', RemoteConfig.instance.init);

    // Saved Gmail account (login page shows when there is none).
    await _safe('account', AuthService.instance.init);

    // Free / Premium: reads the saved copy only; the Worker is asked later.
    await _safe('subscription', SubscriptionService.instance.init);

    runApp(const DamiMoviesApp());

    // Background downloader (flutter_downloader) + saved download list.
    // Started AFTER the first frame is requested: it talks to native code
    // and must never be able to block the app from opening.
    unawaited(_safe(
      'downloads',
      DownloadManager.instance.init,
      limit: const Duration(seconds: 20),
    ));

    // Analytics never blocks app startup.
    unawaited(AnalyticsService.instance.start());
  }, (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
  });
}
