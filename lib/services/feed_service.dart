import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/movie.dart';
import '../utils/posted_at.dart';
import 'install_id.dart';
import 'tmdb_service.dart';

/// Loads the movie list. Order of preference:
/// remote feed (when asked) -> last cached remote copy -> bundled asset.
class FeedService {
  /// True when the last remote download failed and saved/bundled content was
  /// used instead. Read right after a load; the screens show it after a pull.
  bool lastRemoteFailed = false;

  /// Per-feed result of the last remote download (true = failed and a saved
  /// or bundled copy was used). Lets one screen know whether ITS feed was
  /// fresh, even while other screens load their own feeds at the same time.
  final Map<String, bool> _failed = {};
  bool remoteFailedFor(String name) => _failed[name] ?? false;

  Future<List<Movie>> loadMovies({bool remote = false}) async {
    final raw = await _list(
      name: 'movies',
      asset: 'assets/data/movies.json',
      cacheKey: 'cache_movies',
      remoteUrl: AppConfig.moviesUrl,
      remote: remote,
    );

    final parsed = raw.map(Movie.tryParse).whereType<Movie>().toList();

    // Rows that only hold a TMDB id get their name, poster, rating and genres
    // from TMDB (saved copy when offline / not refreshing).
    final fetch = remote && TmdbService.enabled;
    final filled = <Movie>[];
    for (var i = 0; i < parsed.length; i += 8) {
      final chunk = parsed.skip(i).take(8);
      filled.addAll((await Future.wait(chunk.map((m) async {
        if (!m.needsDetails) return m;
        final d = await tmdb.details(m.tmdbId!,
            tv: m.isSeries, fetch: fetch);
        return d == null ? null : m.fillFrom(d);
      })))
          .whereType<Movie>());
    }

    // Rows with no poster: look it up on TMDB (saved copy when offline).
    if (TmdbService.enabled) {
      for (var i = 0; i < filled.length; i += 8) {
        final end = i + 8 > filled.length ? filled.length : i + 8;
        final part = await Future.wait(filled.sublist(i, end).map((m) async {
          if (m.hasImage) return m;
          final p = await tmdb.posterFor(m, fetch: fetch);
          return p.isEmpty ? m : m.withImage(p);
        }));
        filled.replaceRange(i, end, part);
      }
    }

    final seen = <String>{};
    final list = filled.where((m) => seen.add(m.url)).toList();

    // Newest first (date and time), stable for items posted the same day.
    final sorted = newestFirst(list, (m) => m.date);

    // TMDB trending titles go after your own list.
    if (AppConfig.tmdbTrending && TmdbService.enabled) {
      final ids = {for (final m in sorted) if (m.tmdbId != null) m.tmdbId};
      for (final m in await tmdb.trending(fetch: remote)) {
        if (seen.add(m.url) && !ids.contains(m.tmdbId)) sorted.add(m);
      }
    }
    return sorted;
  }

  Future<List<dynamic>> _list({
    required String name,
    required String asset,
    required String cacheKey,
    required String remoteUrl,
    required bool remote,
  }) async {
    if (remote && remoteUrl.isNotEmpty) {
      lastRemoteFailed = true; // until a download succeeds below
      _failed[name] = true;
      try {
        final res = await _download(name, remoteUrl);

        if (res != null && res.statusCode == 200) {
          final data = _decode(utf8.decode(res.bodyBytes));

          if (data.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();

            await prefs.setString(
              cacheKey,
              jsonEncode(data),
            );

            lastRemoteFailed = false;
            _failed[name] = false;
            return data;
          }
        }
      } catch (_) {
        // fall through to cache / bundled copy
      }
    } else if (remote) {
      lastRemoteFailed = false; // bundled-only mode: nothing to download
      _failed[name] = false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      if (remoteUrl.isEmpty) {
        // Bundled-only mode: drop any copy cached from an older remote feed,
        // otherwise it would keep hiding the data shipped in the app.
        await prefs.remove(cacheKey);
      } else {
        final cached = prefs.getString(cacheKey);

        if (cached != null) {
          final data = _decode(cached);

          if (data.isNotEmpty) {
            return data;
          }
        }
      }
    } catch (_) {}

    return _decode(
      await rootBundle.loadString(asset),
    );
  }

  /// Downloads one feed: through your Cloudflare Worker when
  /// [AppConfig.feedBase] is set (so the request is counted), otherwise - or if
  /// the Worker is unreachable - straight from [fallbackUrl] (GitHub).
  Future<http.Response?> _download(String name, String fallbackUrl) async {
    final base = AppConfig.feedBase.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isNotEmpty) {
      try {
        final res = await _getFresh(
          '$base/feed/$name.json',
          headers: {
            'X-Install-Id': await InstallId.get(),
            'X-App-Version': AppConfig.appVersion,
            'X-Platform': 'android',
          },
        );
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) return res;
      } catch (_) {
        // Worker down / blocked: use the direct link below.
      }
    }
    if (fallbackUrl.isEmpty) return null;
    try {
      return await _getFresh(fallbackUrl);
    } catch (_) {
      return null;
    }
  }

  /// Fetches a remote feed while preventing normal HTTP/proxy caching.
  ///
  /// The timestamp is added to the URL so GitHub Raw/CDN/proxy layers
  /// treat each refresh as a new request.
  Future<http.Response> _getFresh(
    String url, {
    Map<String, String> headers = const {},
  }) {
    final original = Uri.parse(url);

    final uri = original.replace(
      queryParameters: {
        ...original.queryParameters,
        '_refresh': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );

    return http
        .get(
          uri,
          headers: {
            'Cache-Control': 'no-cache, no-store, max-age=0',
            'Pragma': 'no-cache',
            ...headers,
          },
        )
        .timeout(
          const Duration(seconds: 7),
        );
  }

  List<dynamic> _decode(String body) {
    final d = jsonDecode(body);

    if (d is List) return d;

    if (d is Map) {
      for (final k in const [
        'movies',
        'items',
      ]) {
        if (d[k] is List) {
          return d[k] as List;
        }
      }
    }

    return const [];
  }
}

final feed = FeedService();
