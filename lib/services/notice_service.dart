import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/notice.dart';
import '../screens/browser_screen.dart' show openExternally;
import '../theme/app_theme.dart';

/// Loads notice.json (remote -> last saved copy -> bundled file) and shows it.
class NoticeService {
  NoticeService._();
  static final NoticeService instance = NoticeService._();

  static const _kCache = 'cache_notice';
  static const _kSeen = 'notice_seen_key';
  bool _startChecked = false;

  /// Never throws. A broken or missing file simply means "no notice".
  Future<Notice> load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}

    final url = AppConfig.noticeUrl.trim();
    if (url.isNotEmpty) {
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
        if (r.statusCode == 200 && r.body.trim().isNotEmpty) {
          final body = utf8.decode(r.bodyBytes);
          final n = _parseBody(body);
          if (n != null) {
            await prefs?.setString(_kCache, body);
            return n;
          }
        }
      } catch (_) {}

      final cached = prefs?.getString(_kCache);
      if (cached != null) {
        final n = _parseBody(cached);
        if (n != null) return n;
      }
    }

    try {
      return _parseBody(await rootBundle.loadString('assets/data/notice.json')) ??
          Notice.none;
    } catch (_) {
      return Notice.none;
    }
  }

  Notice? _parseBody(String body) {
    try {
      return Notice.parse(jsonDecode(body));
    } catch (_) {
      // Not JSON: treat the whole text as the message.
      final t = body.trim();
      return t.isEmpty || t.startsWith('<') ? null : Notice.parse(t);
    }
  }

  /// Pops the notice up once per notice id when the app opens (only if the
  /// file says "popup": true and "enabled": true). Safe to call repeatedly.
  Future<void> showOnStart(BuildContext context) async {
    if (_startChecked) return;
    _startChecked = true;
    final n = await load();
    if (!n.visible || !n.popup || !context.mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_kSeen) == n.key) return;
      await prefs.setString(_kSeen, n.key);
    } catch (_) {}
    if (!context.mounted) return;
    await show(context, n);
  }

  /// The drawer's "Notice" item: always shows the current notice.
  Future<void> showFromMenu(BuildContext context) async {
    final n = await load();
    if (!context.mounted) return;
    await show(
      context,
      n.visible
          ? n
          : const Notice(
              enabled: true,
              message: 'No new notices right now.',
            ),
    );
  }

  Future<void> show(BuildContext context, Notice n) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Ui.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Ui.red.withValues(alpha: .35)),
        ),
        title: Row(children: [
          Icon(Icons.campaign_rounded, color: Ui.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(n.title,
                style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ]),
        content: SingleChildScrollView(
          child: Text(n.message,
              style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(n.okText)),
          if (n.hasButton)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Ui.red),
              onPressed: () {
                Navigator.pop(ctx);
                openExternally(n.buttonUrl);
              },
              child: Text(n.buttonText,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }
}
