import 'package:flutter/services.dart';

/// Progress / result notifications for downloads that run inside the app
/// (the backup downloader in download_manager.dart). While a file downloads,
/// an Android foreground service shows one progress notification and keeps
/// the app alive when it is minimised or the screen is off. The native side
/// is added by tool/patch_download_service.py.
class DownloadNotifier {
  static const _channel = MethodChannel('footbolive/dlservice');
  static bool _on = false;

  /// Shows or updates the progress notification. [percent] is 0..100, or -1
  /// when the size isn't known yet (the bar keeps moving).
  static Future<void> progress({
    required String title,
    required String text,
    required int percent,
  }) async {
    final args = {'title': title, 'text': text, 'percent': percent};
    try {
      if (_on) {
        final ok = await _channel.invokeMethod<bool>('update', args);
        if (ok == true) return;
      }
      _on = (await _channel.invokeMethod<bool>('start', args)) ?? false;
    } catch (_) {
      _on = false;
    }
  }

  /// Removes the progress notification and ends the service.
  static Future<void> stop() async {
    _on = false;
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (_) {}
  }

  /// Copies a file into the phone's Downloads folder (Downloads/DamiMovies).
  /// Returns where it went, or null when it failed.
  static Future<String?> saveToDownloads(String path, String name) async {
    try {
      return await _channel
          .invokeMethod<String>('saveToDownloads', {'path': path, 'name': name});
    } catch (_) {
      return null;
    }
  }

  /// A "finished" or "failed" notification that stays in the tray.
  static Future<void> result(String name,
      {required bool ok, String? detail}) async {
    try {
      await _channel.invokeMethod<bool>('result', {
        'id': name.hashCode & 0x3ff,
        'title': ok ? 'Download finished' : 'Download failed',
        'text': ok ? name : (detail == null ? name : '$name - $detail'),
        'ok': ok,
      });
    } catch (_) {}
  }
}
