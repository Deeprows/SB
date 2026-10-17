import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, FileMode, IOSink;
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';
import 'package:flutter_downloader/flutter_downloader.dart' as fd;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/download_task.dart';
import 'download_notifier.dart';

// ------------------------------------------------------------- name helpers

String sanitizeFileName(String name) {
  var n = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  n = n.replaceAll(RegExp(r'^\.+'), '');
  if (n.length > 120) {
    final dot = n.lastIndexOf('.');
    final ext = (dot > 0 && n.length - dot <= 8) ? n.substring(dot) : '';
    n = n.substring(0, 120 - ext.length) + ext;
  }
  return n.isEmpty ? 'download' : n;
}

String fileNameFromUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return 'download';
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.isEmpty) return 'download';
  var last = segs.last;
  try {
    last = Uri.decodeComponent(last);
  } catch (_) {}
  return sanitizeFileName(last);
}

String? fileNameFromDisposition(String? header) {
  if (header == null || header.isEmpty) return null;
  final star = RegExp(r"filename\*\s*=\s*[^']*'[^']*'([^;]+)", caseSensitive: false)
      .firstMatch(header);
  if (star != null) {
    try {
      return sanitizeFileName(Uri.decodeComponent(star.group(1)!.trim()));
    } catch (_) {}
  }
  final plain = RegExp(r'filename\s*=\s*"?([^";]+)"?', caseSensitive: false)
      .firstMatch(header);
  if (plain != null) return sanitizeFileName(plain.group(1)!.trim());
  return null;
}

// ---------------------------------------------------- native callback bridge

const _portName = 'footbolive_downloader_port';

/// Runs in a background isolate: forwards progress to the UI isolate.
@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final send = IsolateNameServer.lookupPortByName(_portName);
  send?.send([id, status, progress]);
}

// Native status codes (flutter_downloader): 1 enqueued, 2 running,
// 3 complete, 4 failed, 5 canceled, 6 paused.
DownloadStatus? _mapStatus(int s) {
  switch (s) {
    case 1:
    case 2:
      return DownloadStatus.downloading;
    case 3:
      return DownloadStatus.completed;
    case 4:
      return DownloadStatus.failed;
    case 6:
      return DownloadStatus.paused;
  }
  return null;
}

class _Probe {
  final String? error;
  final String? fileName;
  final int? total;
  final String type;
  final String referer; // the Referer that the server accepted
  const _Probe(
      {this.error,
      this.fileName,
      this.total,
      this.type = '',
      this.referer = ''});
}

/// A running in-app (plain Dart) download. See [DownloadManager._run].
class _Job {
  bool stopped = false; // paused or cancelled
  http.Client? client;
}

String _extForType(String type) {
  final t = type.split(';').first.trim().toLowerCase();
  switch (t) {
    case 'video/mp4':
      return '.mp4';
    case 'video/x-matroska':
    case 'video/matroska':
      return '.mkv';
    case 'video/webm':
      return '.webm';
    case 'video/quicktime':
      return '.mov';
    case 'video/x-msvideo':
      return '.avi';
    case 'video/3gpp':
      return '.3gp';
  }
  return '';
}

// ------------------------------------------------------------------ manager

/// Background downloader built on the native Android download service
/// (WorkManager + foreground notification via `flutter_downloader`).
///
/// Downloads keep running when the app is minimised or swiped away, show a
/// notification with progress, and are saved to the phone's Downloads folder.
class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  static const _prefsKey = 'downloads_v2';

  final List<DownloadTask> _tasks = [];
  final Set<String> _starting = {};
  final Map<String, _Job> _jobs = {};
  final Map<String, String> _cookies = {};
  static const _dartPrefix = 'dart-';
  static const _kNotice = 'dl_inapp_notice_v1';
  DateTime _lastSync = DateTime.fromMillisecondsSinceEpoch(0);
  bool _serviceOn = false;

  /// True when the most recent download started inside the app (backup
  /// downloader) rather than through Android's background downloader.
  bool lastStartedInApp = false;
  static bool _isDart(String id) => id.startsWith(_dartPrefix);
  bool _ready = false;
  bool _available = false;
  Timer? _notifyTimer;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  int get activeCount => _tasks.where((t) => t.active).length;
  bool get available => _available;

  Future<void> init() async {
    if (_ready) return;
    _ready = true;

    try {
      await fd.FlutterDownloader
          .initialize(debug: false, ignoreSsl: false)
          .timeout(const Duration(seconds: 8));
      fd.FlutterDownloader.registerCallback(downloadCallback);
      _available = true;
    } catch (e) {
      debugPrint('FlutterDownloader init failed: $e');
    }

    // Progress updates from the background isolate.
    final port = ReceivePort();
    IsolateNameServer.removePortNameMapping(_portName);
    IsolateNameServer.registerPortWithName(port.sendPort, _portName);
    port.listen(_onPort);

    // Our list (names, sizes) ...
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final list = jsonDecode(raw);
        if (list is List) {
          _tasks
            ..clear()
            ..addAll(list.map(DownloadTask.tryParse).whereType<DownloadTask>());
        }
      }
    } catch (_) {}

    // ... reconciled with what the native side says happened meanwhile.
    if (_available) {
      try {
        final native = await fd.FlutterDownloader.loadTasks()
                .timeout(const Duration(seconds: 8)) ??
            [];
        for (final t in List.of(_tasks)) {
          fd.DownloadTask? n;
          for (final x in native) {
            if (x.taskId == t.id) {
              n = x;
              break;
            }
          }
          if (n == null) {
            if (t.status != DownloadStatus.completed) {
              t.status = DownloadStatus.failed;
              t.error = 'This download was interrupted. Start it again.';
            }
            continue;
          }
          t.percent = n.progress;
          final s = n.status;
          if (s == fd.DownloadTaskStatus.complete) {
            t.status = DownloadStatus.completed;
            t.percent = 100;
          } else if (s == fd.DownloadTaskStatus.failed) {
            t.status = DownloadStatus.failed;
            t.error ??= 'Download failed. Tap retry.';
          } else if (s == fd.DownloadTaskStatus.paused) {
            t.status = DownloadStatus.paused;
          } else if (s == fd.DownloadTaskStatus.running ||
              s == fd.DownloadTaskStatus.enqueued) {
            t.status = DownloadStatus.downloading;
          } else if (s == fd.DownloadTaskStatus.canceled) {
            _tasks.remove(t);
          }
        }
      } catch (_) {}
    }
    // In-app (Dart) downloads do not survive the app being closed: mark them
    // so they can be resumed from where they stopped.
    for (final t in _tasks) {
      if (_isDart(t.id) && t.active && !_jobs.containsKey(t.id)) {
        t.status = DownloadStatus.failed;
        t.error = 'This download was interrupted. Tap retry to continue.';
      }
    }
    _changed();
  }

  // ------------------------------------------------------------ bookkeeping

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode(_tasks.map((t) => t.toJson()).toList()));
    } catch (_) {}
  }

  void _tick() {
    _syncService();
    if (_notifyTimer?.isActive ?? false) return;
    _notifyTimer = Timer(const Duration(milliseconds: 300), notifyListeners);
  }

  void _changed() {
    _notifyTimer?.cancel();
    notifyListeners();
    _save();
    _syncService(force: true);
  }

  /// Keeps the progress notification (and the foreground service that keeps
  /// the app alive) in step with the downloads running inside the app.
  void _syncService({bool force = false}) {
    final active = [
      for (final t in _tasks)
        if (_isDart(t.id) && t.active) t,
    ];
    if (active.isEmpty) {
      if (_serviceOn) {
        _serviceOn = false;
        unawaited(DownloadNotifier.stop());
      }
      return;
    }
    final now = DateTime.now();
    if (!force &&
        _serviceOn &&
        now.difference(_lastSync) < const Duration(milliseconds: 900)) {
      return;
    }
    _lastSync = now;
    _serviceOn = true;
    final known = [
      for (final t in active)
        if (t.percent > 0) t.percent,
    ];
    final percent = known.isEmpty
        ? -1
        : known.reduce((a, b) => a + b) ~/ known.length;
    final title =
        active.length == 1 ? active.first.name : '${active.length} downloads';
    final text = percent < 0 ? 'Starting…' : '$percent%';
    unawaited(DownloadNotifier.progress(
        title: title, text: text, percent: percent));
  }

  /// True once, the first time a download runs inside the app: the caller
  /// then explains how it works (see widgets/download_notice.dart).
  Future<bool> takeInAppNotice() async {
    if (!lastStartedInApp) return false;
    lastStartedInApp = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kNotice) ?? false) return false;
      await prefs.setBool(_kNotice, true);
      return true;
    } catch (_) {
      return false;
    }
  }

  DownloadTask? _find(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _onPort(dynamic data) {
    if (data is! List || data.length < 3) return;
    final id = data[0] as String;
    final status = data[1] as int;
    final progress = data[2] as int;
    final t = _find(id);
    if (t == null) return;

    final mapped = _mapStatus(status);
    if (progress >= 0) t.percent = progress;
    if (mapped == null) {
      // canceled / undefined
      if (status == 5) {
        _tasks.remove(t);
        _changed();
      }
      return;
    }
    final changed = mapped != t.status;
    t.status = mapped;
    if (mapped == DownloadStatus.completed) t.percent = 100;
    if (mapped == DownloadStatus.failed) {
      t.error = 'Download failed. Check your connection and tap retry.';
    } else {
      t.error = null;
    }
    changed ? _changed() : _tick();
  }

  // -------------------------------------------------------------------- API

  /// Starts a background download. Returns null on success, otherwise a
  /// message that can be shown to the user.
  Future<String?> enqueue(
    String url, {
    String referer = '',
    String cookie = '',
    String? name,
  }) async {
    // Same link already in the list -> resume it instead of duplicating.
    for (final t in _tasks) {
      if (t.url == url && t.status != DownloadStatus.completed) {
        if (t.status == DownloadStatus.paused ||
            t.status == DownloadStatus.failed) {
          await resume(t.id);
        }
        return null;
      }
    }

    // A second tap while the first is still being checked does nothing.
    if (!_starting.add(url)) return null;
    try {
      return await _enqueue(url, referer, cookie, name);
    } finally {
      _starting.remove(url);
    }
  }

  Future<String?> _enqueue(
      String url, String referer, String cookie, String? name) async {
    final probe = await _probe(url, referer, cookie);
    if (probe.error != null) return probe.error;

    unawaited(_askNotificationPermission());

    final dir = await _saveDir();
    var fileName =
        sanitizeFileName(name ?? probe.fileName ?? fileNameFromUrl(url));
    if (!fileName.contains('.')) fileName += _extForType(probe.type);
    referer = probe.referer; // the one the server accepted
    final headers = <String, String>{
      'User-Agent': AppConfig.userAgent,
      if (referer.isNotEmpty) 'Referer': referer,
      if (cookie.isNotEmpty) 'Cookie': cookie,
    };

    // 1) The phone's background downloader (keeps going when the app is
    //    closed, shows a notification).
    String? id;
    if (_available) {
      try {
        id = await fd.FlutterDownloader.enqueue(
          url: url,
          savedDir: dir,
          fileName: fileName,
          headers: headers,
          showNotification: true,
          openFileFromNotification: true,
          // Files stay in the app's folder; "Save to phone folder" in the
          // Downloads tab copies them to the phone's Downloads folder.
          saveInPublicStorage: false,
        );
      } catch (e) {
        debugPrint('FlutterDownloader.enqueue failed: $e');
      }
    }

    if (id != null) {
      lastStartedInApp = false;
      _tasks.insert(
        0,
        DownloadTask(
          id: id,
          url: url,
          referer: referer,
          name: fileName,
          total: probe.total,
        ),
      );
      _changed();
      return null;
    }

    // 2) Backup: download inside the app with plain Dart, so the file still
    //    arrives in the app instead of being sent to another browser.
    return _startInApp(url, referer, cookie, dir, fileName, probe.total);
  }

  // ------------------------------------------------- in-app (Dart) download

  Future<String> _uniqueName(String dir, String name) async {
    if (!await File('$dir/$name').exists()) return name;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    for (var i = 1; i < 1000; i++) {
      final n = '$base ($i)$ext';
      if (!await File('$dir/$n').exists()) return n;
    }
    return name;
  }

  Future<String?> _startInApp(String url, String referer, String cookie,
      String dir, String fileName, int? total) async {
    try {
      final name = await _uniqueName(dir, fileName);
      final t = DownloadTask(
        id: '$_dartPrefix${DateTime.now().microsecondsSinceEpoch}',
        url: url,
        referer: referer,
        name: name,
        total: total,
      );
      _tasks.insert(0, t);
      _cookies[t.id] = cookie;
      lastStartedInApp = true;
      _changed();
      unawaited(_run(t, resume: false));
      return null;
    } catch (_) {
      return 'Couldn\'t start the download.';
    }
  }

  /// Copies a finished download to the phone's Downloads folder
  /// (Downloads/DamiMovies). Returns where it went, or null when it failed.
  Future<String?> saveToPhone(String id) async {
    final t = _find(id);
    if (t == null) return null;
    final path = await localPath(id);
    if (path == null) return null;
    var out = await DownloadNotifier.saveToDownloads(path, t.name);
    if (out == null) {
      // Android 9 and older need storage access first.
      try {
        final st = await Permission.storage.request();
        if (st.isGranted) {
          out = await DownloadNotifier.saveToDownloads(path, t.name);
        }
      } catch (_) {}
    }
    return out;
  }

  void _fail(DownloadTask t, String message) {
    t.status = DownloadStatus.failed;
    t.error = message;
    _changed();
    unawaited(DownloadNotifier.result(t.name, ok: false, detail: message));
  }

  /// Streams the file to the app's Downloads folder. [resume] continues a
  /// partly downloaded file with a Range request.
  Future<void> _run(DownloadTask t, {required bool resume}) async {
    final job = _Job();
    _jobs[t.id] = job;
    final client = http.Client();
    job.client = client;
    IOSink? sink;
    try {
      final dir = await _saveDir();
      final file = File('$dir/${t.name}');
      var have = 0;
      if (resume && await file.exists()) have = await file.length();

      final req = http.Request('GET', Uri.parse(t.url))
        ..followRedirects = true
        ..maxRedirects = 8;
      req.headers['User-Agent'] = AppConfig.userAgent;
      req.headers['Accept'] = '*/*';
      if (t.referer.isNotEmpty) req.headers['Referer'] = t.referer;
      final cookie = _cookies[t.id] ?? '';
      if (cookie.isNotEmpty) req.headers['Cookie'] = cookie;
      if (have > 0) req.headers['Range'] = 'bytes=$have-';

      final res = await client.send(req).timeout(const Duration(seconds: 25));
      if (res.statusCode >= 400) {
        throw 'The server replied ${res.statusCode}.';
      }
      final type = (res.headers['content-type'] ?? '').toLowerCase();
      if (type.startsWith('text/html') &&
          fileNameFromDisposition(res.headers['content-disposition']) == null) {
        throw 'This link opens a web page, not a file.';
      }

      final append = have > 0 && res.statusCode == 206;
      if (!append) have = 0; // server ignored Range: start from the top
      final len = res.contentLength;
      if (len != null && len > 0) t.total = len + have;

      sink = file.openWrite(mode: append ? FileMode.append : FileMode.write);
      var got = have;
      await for (final chunk in res.stream) {
        if (job.stopped) break;
        sink.add(chunk);
        got += chunk.length;
        final total = t.total;
        if (total != null && total > 0) {
          final pct = (got * 100 ~/ total).clamp(0, 100);
          if (pct != t.percent) {
            t.percent = pct;
            _tick();
          }
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (job.stopped) return;

      t.percent = 100;
      t.status = DownloadStatus.completed;
      t.error = null;
      _changed();
      unawaited(DownloadNotifier.result(t.name, ok: true));
    } on TimeoutException {
      if (!job.stopped) _fail(t, 'The server took too long to respond.');
    } catch (e) {
      if (!job.stopped) {
        _fail(t, e is String ? e : 'Download failed. Check your connection and tap retry.');
      }
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client.close();
      if (identical(_jobs[t.id], job)) _jobs.remove(t.id);
    }
  }

  void _stopJob(String id) {
    final job = _jobs[id];
    if (job == null) return;
    job.stopped = true;
    try {
      job.client?.close();
    } catch (_) {}
  }

  Future<void> pause(String id) async {
    final t = _find(id);
    if (t == null || !t.active) return;
    if (_isDart(id)) {
      _stopJob(id);
      t.status = DownloadStatus.paused;
      _changed();
      return;
    }
    try {
      await fd.FlutterDownloader.pause(taskId: id);
      t.status = DownloadStatus.paused;
      _changed();
    } catch (_) {}
  }

  Future<void> resume(String id) async {
    final t = _find(id);
    if (t == null || t.status == DownloadStatus.completed || t.active) return;
    if (_isDart(id)) {
      t.status = DownloadStatus.downloading;
      t.error = null;
      _changed();
      unawaited(_run(t, resume: true));
      return;
    }
    try {
      final newId = t.status == DownloadStatus.failed
          ? await fd.FlutterDownloader.retry(taskId: id)
          : await fd.FlutterDownloader.resume(taskId: id);
      if (newId != null) {
        t.id = newId;
        t.status = DownloadStatus.downloading;
        t.error = null;
        _changed();
      } else {
        t.status = DownloadStatus.failed;
        t.error = 'Couldn\'t resume. The server may not allow it.';
        _changed();
      }
    } catch (_) {
      t.status = DownloadStatus.failed;
      t.error = 'Couldn\'t resume. Open the link again.';
      _changed();
    }
  }

  /// Stops the task and removes it, deleting the file.
  Future<void> cancel(String id) async {
    final t = _find(id);
    if (t == null) return;
    if (_isDart(id)) {
      await remove(id, deleteFile: true);
      return;
    }
    if (t.active) {
      try {
        await fd.FlutterDownloader.cancel(taskId: id);
      } catch (_) {}
    }
    await remove(id, deleteFile: true);
  }

  Future<void> remove(String id, {bool deleteFile = false}) async {
    final t = _find(id);
    if (t == null) return;
    if (_isDart(id)) {
      _stopJob(id);
      _cookies.remove(id);
      _tasks.remove(t);
      _changed();
      if (deleteFile) {
        try {
          final f = File('${await _saveDir()}/${t.name}');
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      return;
    }
    _tasks.remove(t);
    _changed();
    try {
      await fd.FlutterDownloader.remove(
          taskId: id, shouldDeleteContent: deleteFile);
    } catch (_) {}
  }

  Future<void> clearFinished() async {
    final done =
        _tasks.where((t) => t.status == DownloadStatus.completed).toList();
    _tasks.removeWhere((t) => t.status == DownloadStatus.completed);
    _changed();
    for (final t in done) {
      try {
        await fd.FlutterDownloader.remove(
            taskId: t.id, shouldDeleteContent: false);
      } catch (_) {}
    }
  }

  /// True when [url] answers with a file (not a web page). Used by the
  /// in-app browser: the Android WebView silently ignores file responses
  /// whose address has no .mp4/.mkv ending, so those links are checked here
  /// and handed to the downloader instead.
  Future<bool> looksLikeFile(String url,
      {String referer = '', String cookie = ''}) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return false;
    }
    final probe = await _probe(url, referer, cookie);
    return probe.error == null;
  }

  /// Opens a finished download with an installed app. False if it couldn't.
  /// Full path of a finished download if the file is still there, else null.
  Future<String?> localPath(String id) async {
    if (_isDart(id)) {
      final t = _find(id);
      if (t == null) return null;
      final path = '${await _saveDir()}/${t.name}';
      return await File(path).exists() ? path : null;
    }
    if (!_available) return null;
    try {
      final all = await fd.FlutterDownloader.loadTasks() ?? [];
      for (final n in all) {
        if (n.taskId != id) continue;
        final name = n.filename;
        if (name == null || name.isEmpty) return null;
        final path = '${n.savedDir}/$name';
        return await File(path).exists() ? path : null;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> open(String id) async {
    if (_isDart(id)) return false; // videos play in-app via localPath()
    try {
      return await fd.FlutterDownloader.open(taskId: id);
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------- helpers

  Future<String> _saveDir() async {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {}
    base ??= await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/Downloads');
    if (!await d.exists()) await d.create(recursive: true);
    return d.path;
  }

  Future<void> _askNotificationPermission() async {
    try {
      final s = await Permission.notification.status;
      if (!s.isGranted) await Permission.notification.request();
    } catch (_) {}
  }

  /// Asks the server for the first byte only: tells us the real file name and
  /// size, and catches links that return a web page instead of a file.
  Future<_Probe> _probe(String url, String referer, String cookie) async {
    final client = http.Client();
    Future<http.StreamedResponse> send(bool range, String ref) {
      final req = http.Request('GET', Uri.parse(url))
        ..followRedirects = true
        ..maxRedirects = 8;
      req.headers['User-Agent'] = AppConfig.userAgent;
      req.headers['Accept'] = '*/*';
      if (ref.isNotEmpty) req.headers['Referer'] = ref;
      if (cookie.isNotEmpty) req.headers['Cookie'] = cookie;
      if (range) req.headers['Range'] = 'bytes=0-0';
      return client.send(req).timeout(const Duration(seconds: 12));
    }

    // Some hosts answer 403 to one Referer and accept another (or none).
    final uri = Uri.tryParse(url);
    final refs = <String>[
      referer,
      if (uri != null && uri.hasAuthority) '${uri.scheme}://${uri.host}/',
      '',
    ];
    final tried = <String>{};

    try {
      http.StreamedResponse? res;
      var usedRef = referer;
      for (final ref in refs) {
        if (!tried.add(ref)) continue;
        var r = await send(true, ref);
        if (r.statusCode >= 400) r = await send(false, ref);
        res = r;
        usedRef = ref;
        if (r.statusCode < 400) break;
      }
      if (res == null || res.statusCode >= 400) {
        return _Probe(error: 'The server replied ${res?.statusCode}.');
      }

      final type = (res.headers['content-type'] ?? '').toLowerCase();
      final disp = fileNameFromDisposition(res.headers['content-disposition']);
      if (type.startsWith('text/html') && disp == null) {
        return const _Probe(
            error: 'This link opens a web page, not a file. Use the page\'s '
                'own download button.');
      }

      int? total;
      final range = res.headers['content-range'];
      if (res.statusCode == 206 && range != null) {
        final m = RegExp(r'/(\d+)\s*$').firstMatch(range);
        if (m != null) total = int.tryParse(m.group(1)!);
      } else if (res.statusCode == 200 &&
          res.contentLength != null &&
          res.contentLength! > 0) {
        total = res.contentLength;
      }
      return _Probe(
          fileName: disp, total: total, type: type, referer: usedRef);
    } on TimeoutException {
      return const _Probe(error: 'The server took too long to respond.');
    } catch (_) {
      return const _Probe(error: 'Couldn\'t reach the server.');
    } finally {
      client.close();
    }
  }
}
