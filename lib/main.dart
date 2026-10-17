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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Saved theme (Midnight Violet until the person picks another).
  await ThemeController.load();

  // Phone language (or the language picked in the menu).
  await AppLocale.load();

  // Ad / movie / update settings: saved copy now, fresh copy in the
  // background (never blocks start-up).
  await RemoteConfig.instance.init();

  // Saved Gmail account (login page shows when there is none).
  await AuthService.instance.init();

  // Free / Premium: reads the saved copy only; the Worker is asked later.
  await SubscriptionService.instance.init();

  // Background downloader (flutter_downloader) + saved download list.
  await DownloadManager.instance.init();

  runApp(const DamiMoviesApp());

  // Keeps this person's profile copy on the server up to date, so other
  // members can open it from the community.
  ProfileSync.instance.start();

  // Analytics never blocks app startup.
  unawaited(
    AnalyticsService.instance.start(),
  );
}
