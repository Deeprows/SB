import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/analytics_service.dart';
import 'services/auth_service.dart';
import 'services/profile_sync.dart';
import 'services/download_manager.dart';
import 'services/locale_service.dart';
import 'services/remote_config.dart';
import 'services/subscription_service.dart';
import 'theme/app_theme.dart';

/// Runs one start-up step without ever blocking the app: an error is logged
/// and a step that hangs (no network, plugin not answering) is given up on
/// after [seconds], so the app always gets past the splash screen.
Future<void> _step(String name, Future<void> Function() job,
    {int seconds = 8}) async {
  try {
    await job().timeout(Duration(seconds: seconds));
  } catch (e) {
    debugPrint('Start-up step "$name" failed or timed out: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _step('orientation', () => SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]));

  // Saved theme (Midnight Violet until the person picks another).
  await _step('theme', ThemeController.load);

  // Phone language (or the language picked in the menu).
  await _step('language', AppLocale.load);

  // Ad / movie / update settings: saved copy now, fresh copy in the
  // background (never blocks start-up).
  await _step('remote config', RemoteConfig.instance.init);

  // Saved Gmail account (login page shows when there is none).
  await _step('account', AuthService.instance.init);

  // Free / Premium: reads the saved copy only; the Worker is asked later.
  await _step('subscription', SubscriptionService.instance.init);

  // Background downloader (flutter_downloader) + saved download list.
  await _step('downloads', DownloadManager.instance.init);

  runApp(const DamiMoviesApp());

  // Keeps this person's profile copy on the server up to date, so other
  // members can open it from the community.
  try {
    ProfileSync.instance.start();
  } catch (e) {
    debugPrint('Profile sync could not start: $e');
  }

  // Analytics never blocks app startup.
  unawaited(
    AnalyticsService.instance.start(),
  );
}
