import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'install_id.dart';

/// Anonymous "app opened" ping sent to the Cloudflare Worker (`POST /analytics`).
///
/// Only a random install id, the app version and the platform are sent. It
/// never throws and never blocks app startup; if [AppConfig.feedBase] is empty
/// or the network is down it silently does nothing.
///
/// One `app_open` is recorded per launch. If the ping fails (no network, the
/// Worker is cold or down) it is retried a few times. When the app comes back
/// to the foreground after [_newSessionGap] away, it counts as a new open.
class AnalyticsService with WidgetsBindingObserver {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  /// Time away from the app after which the next return counts as a new open.
  static const _newSessionGap = Duration(minutes: 30);

  bool _started = false;
  bool _sent = false;
  bool _sending = false;
  DateTime? _pausedAt;

  /// Call once after `runApp`: records the launch and starts watching for
  /// the app coming back to the foreground.
  Future<void> start() async {
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addObserver(this);
    }
    await trackAppOpen();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      final away = _pausedAt;
      _pausedAt = null;

      // A long absence is a new "open"; a failed earlier ping is retried too.
      if (away != null && DateTime.now().difference(away) >= _newSessionGap) {
        _sent = false;
      }
      unawaited(trackAppOpen());
    }
  }

  /// Records one `app_open` event (retrying a few times if it fails).
  Future<void> trackAppOpen() async {
    if (_sent || _sending) return;

    final base = AppConfig.feedBase.trim();
    if (base.isEmpty) return;

    _sending = true;
    try {
      final installId = await InstallId.get();
      final uri = Uri.parse(
        '${base.replaceAll(RegExp(r'/+$'), '')}/analytics',
      );
      final body = jsonEncode({
        'event': 'app_open',
        'installId': installId,
        'appVersion': AppConfig.appVersion,
        'platform': Platform.isAndroid ? 'android' : Platform.operatingSystem,
      });

      for (var attempt = 0; attempt < 3 && !_sent; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(Duration(seconds: 5 * attempt));
        }

        try {
          final res = await http
              .post(
                uri,
                headers: const {'Content-Type': 'application/json'},
                body: body,
              )
              .timeout(const Duration(seconds: 8));

          if (res.statusCode >= 200 && res.statusCode < 300) {
            _sent = true;
          }
        } catch (_) {
          // Try again; analytics must never affect the app.
        }
      }
    } catch (_) {
      // Analytics must never affect the app.
    } finally {
      _sending = false;
    }
  }
}
