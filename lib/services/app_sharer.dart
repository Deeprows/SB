import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import 'remote_config.dart';

/// "Share App": opens Android's share sheet with the app's own APK file, so
/// the person can send it with Xender, SHAREit, Bluetooth, WhatsApp... any
/// app on their phone that can send files. If the APK cannot be found, it
/// shares the website link as text instead.
class AppSharer {
  AppSharer._();
  static final AppSharer instance = AppSharer._();

  bool _busy = false;

  Future<void> share(BuildContext context) async {
    if (_busy) return;
    _busy = true;
    final messenger = ScaffoldMessenger.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final text = RemoteConfig.instance.shareText;
    try {
      final apk = Platform.isAndroid ? await _copyInstalledApk() : null;
      if (apk != null) {
        await Share.shareXFiles(
          [XFile(apk.path, mimeType: 'application/vnd.android.package-archive')],
          text: text,
          sharePositionOrigin: origin,
        );
      } else {
        await Share.share(text, sharePositionOrigin: origin);
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open sharing.')),
      );
    } finally {
      _busy = false;
    }
  }

  /// Android keeps the installed APK under /data/app and maps it into the
  /// running app, so it can be found in /proc/self/maps. It is copied to the
  /// cache folder (readable by the share sheet) under a friendly name.
  Future<File?> _copyInstalledApk() async {
    try {
      final maps = await File('/proc/self/maps').readAsString();
      final found = RegExp(r'(/data/app/\S+?\.apk)')
          .allMatches(maps)
          .map((m) => m.group(1)!)
          .toSet()
          .toList();
      if (found.isEmpty) return null;
      final path = found.firstWhere((p) => p.endsWith('base.apk'),
          orElse: () => found.first);
      final dir = await getTemporaryDirectory();
      final out = File('${dir.path}/${AppConfig.appName}.apk');
      return await File(path).copy(out.path);
    } catch (_) {
      return null;
    }
  }
}
