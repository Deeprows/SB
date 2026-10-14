import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'config.dart';
import 'screens/start_gate.dart';
import 'services/app_nav.dart';
import 'services/locale_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_watermark.dart';

class DamiMoviesApp extends StatelessWidget {
  const DamiMoviesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ThemeController.index,
      builder: (_, _, _) => ValueListenableBuilder<String>(
        valueListenable: AppLocale.notifier,
        builder: (_, lang, _) => MaterialApp(
        title: AppConfig.appName,
        locale: Locale(lang),
        supportedLocales: [
          for (final l in AppLocale.supported) Locale(l.code),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        debugShowCheckedModeBanner: false,
        navigatorKey: AppNav.key,
        scaffoldMessengerKey: AppNav.messengerKey,
        theme: buildTheme(),
        builder: (context, child) => Stack(
          fit: StackFit.expand,
          children: [
            child ?? const SizedBox.shrink(),
            const ThemeWatermark(),
          ],
        ),
        home: const StartGate(),
        ),
      ),
    );
  }
}
