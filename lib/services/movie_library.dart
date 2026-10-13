import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/movie.dart';

/// One entry of the watch history: the title and when it was last opened.
class WatchEntry {
  final Movie movie;
  final DateTime at;
  const WatchEntry(this.movie, this.at);
}

/// "Save and watch later" list and "Watch history", kept on the phone.
/// Screens listen to it, so every bookmark icon stays in sync.
class MovieLibrary extends ChangeNotifier {
  MovieLibrary._();
  static final MovieLibrary instance = MovieLibrary._();

  static const _kLater = 'deeprowss_watch_later';
  static const _kHistory = 'deeprowss_watch_history';
  static const _maxHistory = 200;

  final List<Movie> _later = [];
  final List<WatchEntry> _history = [];
  bool _loaded = false;
  Future<void>? _loading;

  /// Newest saved first.
  List<Movie> get watchLater => List.unmodifiable(_later);

  /// Most recently watched first.
  List<WatchEntry> get history => List.unmodifiable(_history);

  /// Reads the saved lists once (safe to call many times).
  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    final prefs = await SharedPreferences.getInstance();
    _later
      ..clear()
      ..addAll(_decode(prefs.getString(_kLater))
          .map(Movie.tryParse)
          .whereType<Movie>());
    _history.clear();
    for (final row in _decode(prefs.getString(_kHistory))) {
      final m = Movie.tryParse(row);
      final at = row is Map ? DateTime.tryParse('${row['watchedAt']}') : null;
      if (m != null) _history.add(WatchEntry(m, at ?? DateTime.now()));
    }
    _loaded = true;
    notifyListeners();
  }

  static List<dynamic> _decode(String? raw) {
    if (raw == null) return const [];
    try {
      final v = jsonDecode(raw);
      return v is List ? v : const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kLater, jsonEncode(_later.map((m) => m.toJson()).toList()));
    await prefs.setString(
        _kHistory,
        jsonEncode(_history
            .map((e) => {
                  ...e.movie.toJson(),
                  'watchedAt': e.at.toIso8601String(),
                })
            .toList()));
  }

  bool isSaved(Movie m) => _later.any((x) => x.url == m.url);

  /// Adds or removes [m]; returns true when it is now saved.
  Future<bool> toggleWatchLater(Movie m) async {
    await load();
    final i = _later.indexWhere((x) => x.url == m.url);
    final nowSaved = i < 0;
    if (nowSaved) {
      _later.insert(0, m);
    } else {
      _later.removeAt(i);
    }
    notifyListeners();
    await _save();
    return nowSaved;
  }

  Future<void> removeWatchLater(Movie m) async {
    await load();
    _later.removeWhere((x) => x.url == m.url);
    notifyListeners();
    await _save();
  }

  /// Puts [m] on top of the history (a title appears once, with its latest
  /// time).
  Future<void> addToHistory(Movie m) async {
    await load();
    _history.removeWhere((e) => e.movie.url == m.url);
    _history.insert(0, WatchEntry(m, DateTime.now()));
    if (_history.length > _maxHistory) {
      _history.removeRange(_maxHistory, _history.length);
    }
    notifyListeners();
    await _save();
  }

  Future<void> removeFromHistory(Movie m) async {
    await load();
    _history.removeWhere((e) => e.movie.url == m.url);
    notifyListeners();
    await _save();
  }

  Future<void> clearHistory() async {
    await load();
    _history.clear();
    notifyListeners();
    await _save();
  }

  bool get loaded => _loaded;
}
