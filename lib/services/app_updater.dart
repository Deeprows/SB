import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config.dart';
import '../screens/browser_screen.dart' show openExternally;
import '../theme/app_theme.dart';
import 'remote_config.dart';

class _NotAnApk implements Exception {}

/// "Update App": downloads the APK from `update.apkUrl` (app_config.json)
/// right away, with a progress pop-up, then opens Android's installer.
/// If the link is not a direct APK it is opened in the browser instead.
class AppUpdater {
  AppUpdater._();
  static final AppUpdater instance = AppUpdater._();

  bool _busy = false;

  Future<void> update(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context, rootNavigator: true);
    void say(String m) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));

    if (_busy) return;
    // Make sure the newest link is used.
    await RemoteConfig.instance.refresh(force: true);
    final url = RemoteConfig.instance.updateApkUrl;
    if (!url.startsWith('http')) {
      say('No update available right now.');
      return;
    }
    if (!Platform.isAndroid) {
      await openExternally(url);
      return;
    }

    _busy = true;
    try {
      // Android asks once for "install apps from this source".
      if (!await Permission.requestInstallPackages.isGranted) {
        final st = await Permission.requestInstallPackages.request();
        if (!st.isGranted) {
          say('Allow installs from this app to update.');
          return;
        }
      }

      final file = await _download(nav, url);
      if (file == null) return; // cancelled

      say('Tap Install to finish the update.');
      final r = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
      if (r.type != ResultType.done) {
        say('Could not start the installer.');
      }
    } on _NotAnApk {
      // A web page, not an APK: let the browser handle it.
      if (!await openExternally(url)) say('Could not open the update link.');
    } catch (_) {
      say('Update failed. Check your internet and try again.');
    } finally {
      _busy = false;
    }
  }

  /// Downloads with a progress pop-up. Null = the person cancelled.
  Future<File?> _download(NavigatorState nav, String url) async {
    final progress = ValueNotifier<double?>(null);
    var cancelled = false;
    var dialogOpen = true;

    unawaited(showDialog<void>(
      context: nav.context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: Ui.panel,
          title: const Text('Downloading update…',
              style: TextStyle(fontWeight: FontWeight.w800)),
          content: ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (_, v, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: v,
                    minHeight: 6,
                    color: Ui.red,
                    backgroundColor: Ui.line,
                  ),
                ),
                const SizedBox(height: 8),
                Text(v == null ? 'Starting…' : '${(v * 100).round()}%',
                    style: TextStyle(color: Ui.muted, fontSize: 13)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => cancelled = true,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ).whenComplete(() => dialogOpen = false));

    final client = http.Client();
    IOSink? sink;
    try {
      final req = http.Request('GET', Uri.parse(url))
        ..headers['user-agent'] = AppConfig.userAgent;
      final resp = await client.send(req).timeout(const Duration(seconds: 30));
      final type = (resp.headers['content-type'] ?? '').toLowerCase();
      if (resp.statusCode != 200 || type.contains('text/html')) {
        throw _NotAnApk();
      }
      final total = resp.contentLength ?? 0;
      final dir =
          await getExternalStorageDirectory() ?? await getTemporaryDirectory();
      final file = File('${dir.path}/streambox-update.apk');
      sink = file.openWrite();
      var got = 0;
      await for (final chunk in resp.stream) {
        if (cancelled) break;
        sink.add(chunk);
        got += chunk.length;
        progress.value = total > 0 ? got / total : null;
      }
      await sink.close();
      sink = null;
      if (cancelled) {
        try {
          await file.delete();
        } catch (_) {}
        return null;
      }
      return file;
    } finally {
      client.close();
      try {
        await sink?.close();
      } catch (_) {}
      if (dialogOpen && nav.mounted) nav.pop();
      progress.dispose();
    }
  }
}
