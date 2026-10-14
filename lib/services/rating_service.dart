import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/movie.dart';
import 'auth_service.dart';
import 'install_id.dart';

/// What everyone together thinks of a title.
class CommunityRating {
  final double avg; // 0..5
  final int count;
  const CommunityRating(this.avg, this.count);
}

/// Your own 1-5 star ratings, kept on the phone, plus the community average
/// from your Cloudflare Worker (`/rate`, `/rating`) when it is set up. The
/// star you give always works, even offline; it is sent to the server when
/// possible.
class RatingService extends ChangeNotifier {
  RatingService._();
  static final RatingService instance = RatingService._();

  static const _kMine = 'user_ratings_v1';
  static const _kMovies = 'user_rating_movies_v1';

  final Map<String, int> _mine = {};
  final Map<String, Movie> _movies = {}; // the rated titles, for the profile
  final Map<String, CommunityRating> _community = {};
  Future<void>? _loading;

  /// Same key for every row of one title.
  static String keyOf(Movie m) => m.tmdbId != null
      ? '${m.isSeries ? 'tv' : 'movie'}:${m.tmdbId}'
      : 'url:${m.url}';

  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_kMine);
      if (raw != null) {
        final j = jsonDecode(raw);
        if (j is Map) {
          j.forEach((k, v) {
            final n = (v as num?)?.toInt() ?? 0;
            if (n >= 1 && n <= 5) _mine['$k'] = n;
          });
        }
      }
      final rawMovies = (await SharedPreferences.getInstance()).getString(_kMovies);
      if (rawMovies != null) {
        final j = jsonDecode(rawMovies);
        if (j is Map) {
          j.forEach((k, v) {
            final m = Movie.tryParse(v);
            if (m != null) _movies['$k'] = m;
          });
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  /// Everything you rated, newest first, with your stars.
  List<(Movie, int)> get ratedMovies {
    final out = <(Movie, int)>[];
    for (final e in _mine.entries.toList().reversed) {
      final m = _movies[e.key];
      if (m != null) out.add((m, e.value));
    }
    return out;
  }

  /// Your stars for [m]: 1-5, or 0 when you have not rated it.
  int mine(Movie m) => _mine[keyOf(m)] ?? 0;

  CommunityRating? community(Movie m) => _community[keyOf(m)];

  Future<void> _saveMine() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kMine, jsonEncode(_mine));
      await prefs.setString(_kMovies,
          jsonEncode({for (final e in _movies.entries) e.key: e.value.toJson()}));
    } catch (_) {}
  }

  String get _base =>
      AppConfig.feedBase.trim().replaceAll(RegExp(r'/+$'), '');

  Future<String> _voter() async {
    final email = AuthService.instance.user?.email;
    if (email != null && email.isNotEmpty) return email.toLowerCase();
    return 'dev-${await InstallId.get()}';
  }

  /// Sets your rating (1-5); 0 removes it.
  Future<void> rate(Movie m, int stars) async {
    await load();
    final key = keyOf(m);
    _mine.remove(key); // re-rating moves the title to the top of the list
    if (stars <= 0) {
      _movies.remove(key);
    } else {
      _mine[key] = stars.clamp(1, 5);
      _movies[key] = m;
    }
    notifyListeners();
    await _saveMine();
    unawaited(_send(key, stars <= 0 ? 0 : stars.clamp(1, 5)));
  }

  Future<void> _send(String key, int stars) async {
    if (_base.isEmpty) return;
    try {
      final res = await http
          .post(
            Uri.parse('$_base/rate'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(
                {'key': key, 'voter': await _voter(), 'stars': stars}),
          )
          .timeout(const Duration(seconds: 12));
      _takeCommunity(key, res);
    } catch (_) {}
  }

  /// Fetches the community average for [m] (quietly does nothing when the
  /// server has no ratings feature or is unreachable).
  Future<void> refresh(Movie m) async {
    if (_base.isEmpty) return;
    final key = keyOf(m);
    try {
      final res = await http
          .get(Uri.parse('$_base/rating').replace(queryParameters: {'key': key}))
          .timeout(const Duration(seconds: 10));
      _takeCommunity(key, res);
    } catch (_) {}
  }

  void _takeCommunity(String key, http.Response res) {
    if (res.statusCode != 200) return;
    try {
      final j = jsonDecode(res.body);
      if (j is Map && j['ok'] == true) {
        _community[key] = CommunityRating(
          (j['avg'] as num?)?.toDouble() ?? 0,
          (j['count'] as num?)?.toInt() ?? 0,
        );
        notifyListeners();
      }
    } catch (_) {}
  }
}
