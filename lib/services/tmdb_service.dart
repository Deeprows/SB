import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/movie.dart';
import '../models/movie_info.dart';
import '../models/trailer_item.dart';

/// Talks to TMDB (api.themoviedb.org, v3) and turns its results into [Movie]s.
///
/// Every title is keyed by its TMDB id:
///   player   -> `<AppConfig.embedBase>/movie|tv/<id>`
///   download -> `<AppConfig.downloadBase>/movie|tv/<id>`
class TmdbService {
  static bool get enabled => AppConfig.tmdbApiKey.isNotEmpty;

  static const _detailsKey = 'cache_tmdb_details';
  static const _trendingKey = 'cache_tmdb_trending_day';
  static const _trendingAtKey = 'cache_tmdb_trending_day_at';
  static const _postersKey = 'cache_tmdb_posters';

  static const _genres = <int, String>{
    28: 'Action',
    12: 'Adventure',
    16: 'Animation',
    35: 'Comedy',
    80: 'Crime',
    99: 'Documentary',
    18: 'Drama',
    10751: 'Family',
    14: 'Fantasy',
    36: 'History',
    27: 'Horror',
    10402: 'Music',
    9648: 'Mystery',
    10749: 'Romance',
    878: 'Sci-Fi',
    10770: 'TV Movie',
    53: 'Thriller',
    10752: 'War',
    37: 'Western',
    10759: 'Action & Adventure',
    10762: 'Kids',
    10763: 'News',
    10764: 'Reality',
    10765: 'Sci-Fi & Fantasy',
    10766: 'Soap',
    10767: 'Talk',
    10768: 'War & Politics',
  };

  // ---------------------------------------------------------- connection
  //
  // Some networks block api.themoviedb.org (the request just hangs, so the
  // home page never gets its TMDB rows). Every request therefore tries up to
  // three routes and remembers the one that worked, so the next calls go
  // straight to it:
  //   direct -> api.themoviedb.org
  //   alt    -> api.tmdb.org (TMDB's own second address)
  //   proxy  -> your Cloudflare Worker (`<feedBase>/tmdb/...`, see
  //             cloudflare/worker.js), which fetches from TMDB for the phone.
  static const _routes = ['direct', 'alt', 'proxy'];
  static String _lastRoute = 'direct';

  static String get _proxyBase =>
      AppConfig.feedBase.trim().replaceAll(RegExp(r'/+$'), '');

  /// Host for poster / backdrop images. Follows the API route: when TMDB can
  /// only be reached through the Worker, images are loaded through it too.
  static String get imageBase => (_lastRoute == 'proxy' && _proxyBase.isNotEmpty)
      ? '$_proxyBase/tmdbimg'
      : 'https://image.tmdb.org';

  Uri? _uri(String route, String path, Map<String, String> q) {
    switch (route) {
      case 'alt':
        return Uri.https('api.tmdb.org', '/3$path', q);
      case 'proxy':
        if (_proxyBase.isEmpty) return null;
        final b = Uri.parse(_proxyBase);
        return b.replace(path: '${b.path}/tmdb/3$path', queryParameters: q);
      default:
        return Uri.https('api.themoviedb.org', '/3$path', q);
    }
  }

  Future<dynamic> _get(String path, [Map<String, String> query = const {}]) async {
    final q = <String, String>{
      'api_key': AppConfig.tmdbApiKey,
      'language': 'en-US',
      ...query,
    };
    final order = [_lastRoute, ..._routes.where((r) => r != _lastRoute)];
    // First pass is quick so a blocked route is skipped fast; the second
    // pass is patient for very slow connections.
    for (var attempt = 0; attempt < 2; attempt++) {
      final wait = Duration(seconds: attempt == 0 ? 10 : 15);
      for (final route in order) {
        final uri = _uri(route, path, q);
        if (uri == null) continue;
        try {
          final res = await http.get(uri).timeout(wait);
          if (res.statusCode == 200) {
            _lastRoute = route;
            return jsonDecode(utf8.decode(res.bodyBytes));
          }
          if (res.statusCode == 404) return null; // TMDB answered: no such title
          debugPrint('TMDB $route $path -> HTTP ${res.statusCode}');
        } catch (e) {
          debugPrint('TMDB $route $path failed: $e');
        }
      }
    }
    return null;
  }

  /// One TMDB result (list item or details) -> [Movie]. [type] is used when
  /// the result has no `media_type` of its own ("movie" or "tv").
  static Movie? fromJson(dynamic raw, {String type = 'movie'}) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! int) return null;
    final mediaType = (raw['media_type'] ?? type).toString();
    if (mediaType != 'movie' && mediaType != 'tv') return null; // e.g. person
    final tv = mediaType == 'tv';

    final title =
        (raw[tv ? 'name' : 'title'] ?? raw['title'] ?? raw['name'] ?? '')
            .toString()
            .trim();
    if (title.isEmpty) return null;

    final dateStr =
        (raw[tv ? 'first_air_date' : 'release_date'] ?? '').toString();
    final year = dateStr.length >= 4 ? dateStr.substring(0, 4) : null;

    final genres = <String>[];
    if (raw['genres'] is List) {
      for (final g in raw['genres'] as List) {
        if (g is Map && g['name'] != null) {
          genres.addAll(Movie.genreNames(g['name'].toString()));
        }
      }
    } else if (raw['genre_ids'] is List) {
      for (final g in raw['genre_ids'] as List) {
        final n = _genres[g];
        if (n != null) genres.addAll(Movie.genreNames(n));
      }
    }

    final vote = raw['vote_average'];
    final rating = (vote is num && vote > 0)
        ? Movie.parseRating('${vote.toStringAsFixed(1)}/10')
        : null;
    final poster = (raw['poster_path'] ?? '').toString();

    return Movie(
      name: year == null ? title : '$title ($year)',
      url: Movie.embedUrlFor(id, tv: tv),
      downloadUrl: Movie.downloadUrlFor(id, tv: tv),
      date: null, // keep "Added <date>" for rows you add yourself
      rating: rating,
      genres: genres.toSet().toList(),
      image: poster.isEmpty ? '' : '$imageBase/t/p/w500$poster',
      tmdbId: id,
    );
  }


  /// Poster for rows that have no image. The id comes from the row's player
  /// link (`/movie/<id>`, `/tv/<id>`, `?imdb=tt...`). Found posters are saved,
  /// so later loads (and offline) need no request. Returns '' when unknown.
  Future<String> posterFor(Movie m, {bool fetch = true}) async {
    final match = RegExp(r'(?:imdb=|/(?:movie|tv)/)(tt\d+|\d+)')
        .firstMatch(m.url);
    if (match == null) return '';
    var id = match.group(1)!;
    final isImdb = id.startsWith('tt') || m.url.contains('imdb=');
    if (isImdb && !id.startsWith('tt')) id = 'tt${id.padLeft(7, '0')}';
    final tv = m.isSeries;
    final key = '${tv ? 'tv' : 'movie'}:$id';

    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> cache = {};
    try {
      final c = prefs.getString(_postersKey);
      if (c != null) cache = Map<String, dynamic>.from(jsonDecode(c) as Map);
    } catch (_) {}

    var path = (cache[key] ?? '').toString();
    if (path.isEmpty && fetch) {
      dynamic d;
      if (id.startsWith('tt')) {
        d = await _get('/find/$id', {'external_source': 'imdb_id'});
        if (d is Map) {
          final list = (tv ? d['tv_results'] : d['movie_results']) ??
              d['movie_results'] ??
              d['tv_results'];
          d = (list is List && list.isNotEmpty) ? list.first : null;
        }
      } else {
        d = await _get('/${tv ? 'tv' : 'movie'}/$id');
      }
      if (d is Map) {
        path = (d['poster_path'] ?? '').toString();
        if (path.isNotEmpty) {
          cache[key] = path;
          await prefs.setString(_postersKey, jsonEncode(cache));
        }
      }
    }
    return path.isEmpty ? '' : 'https://image.tmdb.org/t/p/w500$path';
  }

  /// Fills in a row that only has a TMDB id. Uses the saved copy when
  /// [fetch] is false (or the request fails).
  Future<Movie?> details(int id, {required bool tv, bool fetch = true}) async {
    final key = '${tv ? 'tv' : 'movie'}:$id';
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> cache = {};
    try {
      final c = prefs.getString(_detailsKey);
      if (c != null) cache = Map<String, dynamic>.from(jsonDecode(c) as Map);
    } catch (_) {}

    if (fetch) {
      final d = await _get('/${tv ? 'tv' : 'movie'}/$id');
      if (d is Map && d['id'] == id) {
        cache[key] = d;
        await prefs.setString(_detailsKey, jsonEncode(cache));
      }
    }
    return fromJson(cache[key], type: tv ? 'tv' : 'movie');
  }

  /// TMDB's trending movies + series for TODAY (about 40), straight from
  /// `/trending/all/day`. Without [fetch] only the last saved copy is
  /// returned, so the first paint never waits on TMDB. A saved copy younger
  /// than 15 minutes is reused (the app syncs every minute); [force] always
  /// asks TMDB (pull to refresh, new day, new language).
  Future<List<Movie>> trending({bool fetch = true, bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (fetch) {
      final at = prefs.getInt(_trendingAtKey) ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - at;
      final fresh = prefs.getString(_trendingKey) != null &&
          age >= 0 &&
          age < const Duration(minutes: 15).inMilliseconds;
      if (force || !fresh) {
        // One page at a time: on a slow connection the first page is saved
        // (and shown) as soon as it arrives instead of waiting for both.
        final all = <dynamic>[];
        for (final page in const ['1', '2']) {
          final p = await _get('/trending/all/day', {'page': page});
          if (p is Map && p['results'] is List) all.addAll(p['results'] as List);
          if (all.isEmpty) break; // no connection to TMDB: stop early
          await prefs.setString(_trendingKey, jsonEncode(all));
          await prefs.setInt(
              _trendingAtKey, DateTime.now().millisecondsSinceEpoch);
        }
      }
    }
    try {
      final c = prefs.getString(_trendingKey);
      if (c == null) return const [];
      return (jsonDecode(c) as List)
          .map((e) => fromJson(e))
          .whereType<Movie>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// TMDB's live "popular" list: movies ([tv] false) or series ([tv] true).
  Future<List<Movie>> popular(
          {required bool tv, bool fetch = true, bool force = false}) =>
      list('/${tv ? 'tv' : 'movie'}/popular',
          type: tv ? 'tv' : 'movie', fetch: fetch, force: force);

  /// Any TMDB list endpoint (`/movie/popular`, `/movie/now_playing`,
  /// `/movie/top_rated`, `/tv/top_rated`...): about 40 titles. Saved after
  /// every download, so [fetch] false returns the last saved copy instantly
  /// (first paint, offline). A copy younger than 15 minutes is reused;
  /// [force] always asks TMDB.
  Future<List<Movie>> list(String path,
      {required String type, bool fetch = true, bool force = false}) async {
    final key = 'cache_tmdb_list${path.replaceAll('/', '_')}';
    final atKey = '${key}_at';
    final prefs = await SharedPreferences.getInstance();
    if (fetch) {
      final age =
          DateTime.now().millisecondsSinceEpoch - (prefs.getInt(atKey) ?? 0);
      final fresh = prefs.getString(key) != null &&
          age >= 0 &&
          age < const Duration(minutes: 15).inMilliseconds;
      if (force || !fresh) {
        final pages = await Future.wait([
          _get(path, {'page': '1'}),
          _get(path, {'page': '2'}),
        ]);
        final all = <dynamic>[];
        for (final p in pages) {
          if (p is Map && p['results'] is List) all.addAll(p['results'] as List);
        }
        if (all.isNotEmpty) {
          await prefs.setString(key, jsonEncode(all));
          await prefs.setInt(atKey, DateTime.now().millisecondsSinceEpoch);
        }
      }
    }
    try {
      final c = prefs.getString(key);
      if (c == null) return const [];
      return (jsonDecode(c) as List)
          .map((e) => fromJson(e, type: type))
          .whereType<Movie>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // category name -> [TMDB movie genre id, TMDB series genre id]
  static const _discoverIds = <String, List<String?>>{
    'Action': ['28', '10759'],
    'Adventure': ['12', '10759'],
    'Animation': ['16', '16'],
    'Comedy': ['35', '35'],
    'Crime': ['80', '80'],
    'Documentary': ['99', '99'],
    'Drama': ['18', '18'],
    'Family': ['10751', '10751'],
    'Fantasy': ['14', '10765'],
    'History': ['36', null],
    'Horror': ['27', null],
    'Music': ['10402', null],
    'Mystery': ['9648', '9648'],
    'Romance': ['10749', null],
    'Sci-Fi': ['878', '10765'],
    'Thriller': ['53', null],
    'War': ['10752', '10768'],
    'Western': ['37', '37'],
  };

  /// Categories shown on the home page and in the Categories sheet when TMDB
  /// is on (home rows use the first six).
  static List<String> get categories => const [
        'Action', 'Comedy', 'Drama', 'Horror', 'Sci-Fi', 'Animation',
        'Thriller', 'Romance', 'Crime', 'Adventure', 'Fantasy', 'Family',
        'Mystery', 'Documentary', 'War', 'History', 'Western', 'Music',
      ];

  /// Popular TMDB movies and series of one category (movies and series
  /// alternate in the result). Empty for categories TMDB does not have.
  Future<List<Movie>> discover(String genre) async {
    final ids = _discoverIds[genre];
    if (ids == null) return const [];
    const types = ['movie', 'tv'];
    final calls = <Future<dynamic>>[];
    final used = <String>[];
    for (var i = 0; i < 2; i++) {
      final id = ids[i];
      if (id == null) continue;
      used.add(types[i]);
      calls.add(_get('/discover/${types[i]}', {
        'with_genres': id,
        'sort_by': 'popularity.desc',
        'include_adult': 'false',
        'vote_count.gte': '50',
      }));
    }
    final res = await Future.wait(calls);
    final lists = <List<Movie>>[];
    for (var i = 0; i < res.length; i++) {
      final r = res[i];
      lists.add(r is Map && r['results'] is List
          ? (r['results'] as List)
              .map((e) => fromJson(e, type: used[i]))
              .whereType<Movie>()
              .toList()
          : <Movie>[]);
    }
    final out = <Movie>[];
    final longest = lists.fold<int>(0, (a, l) => l.length > a ? l.length : a);
    for (var i = 0; i < longest; i++) {
      for (final l in lists) {
        if (i < l.length) out.add(l[i]);
      }
    }
    return out;
  }

  final Map<String, MovieInfo> _infoCache = {};

  /// Overview, cast, director, runtime... for one title (null when TMDB has
  /// nothing for it). Works for rows with a TMDB id, rows whose link holds a
  /// TMDB or IMDb id, and otherwise looks the title up by name and year.
  Future<MovieInfo?> info(Movie m) async {
    if (!enabled) return null;
    try {
      final t = await _resolve(m);
      if (t == null) return null;
      final key = '${t.tv ? 'tv' : 'movie'}:${t.id}';
      final hit = _infoCache[key];
      if (hit != null) return hit;
      final d = await _get('/${t.tv ? 'tv' : 'movie'}/${t.id}',
          {
        'append_to_response': 'credits,videos',
        // trailers in English or with no language set
        'include_video_language': 'en,null',
      });
      final info = MovieInfo.fromJson(d, tv: t.tv);
      if (info != null && info.hasContent) _infoCache[key] = info;
      return info;
    } catch (_) {
      return null;
    }
  }

  Future<_Target?> _resolve(Movie m) async {
    if (m.tmdbId != null) return _Target(m.tmdbId!, m.isSeries);

    final mt = RegExp(r'/embed/(movie|tv)/(tt\d+|\d+)').firstMatch(m.url);
    if (mt != null) {
      final tv = mt.group(1) == 'tv';
      final id = mt.group(2)!;
      if (!id.startsWith('tt')) return _Target(int.parse(id), tv);
      final f = await _get('/find/$id', {'external_source': 'imdb_id'});
      if (f is Map) {
        final l = f[tv ? 'tv_results' : 'movie_results'];
        if (l is List && l.isNotEmpty) {
          final first = l.first;
          if (first is Map && first['id'] is int) {
            return _Target(first['id'] as int, tv);
          }
        }
      }
    }

    // Last resort: search by title (and year); only an exact title match is
    // accepted so a wrong film is never shown.
    final tv = m.isSeries;
    final title = m.title;
    if (title.isEmpty) return null;
    final yearKey = tv ? 'first_air_date_year' : 'year';
    final d = await _get(tv ? '/search/tv' : '/search/movie', {
      'query': title,
      if (m.year != null) yearKey: m.year!,
    });
    if (d is! Map || d['results'] is! List) return null;
    String norm(String x) => x.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final want = norm(title);
    for (final r in d['results'] as List) {
      if (r is! Map || r['id'] is! int) continue;
      final names = [r['title'], r['name'], r['original_title'], r['original_name']];
      if (names.any((n) => n != null && norm(n.toString()) == want)) {
        return _Target(r['id'] as int, tv);
      }
    }
    return null;
  }

  /// Searches movies and series on TMDB.
  Future<List<Movie>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final d = await _get('/search/multi', {'query': q, 'include_adult': 'false'});
    if (d is! Map || d['results'] is! List) return const [];
    return (d['results'] as List)
        .map((e) => fromJson(e))
        .whereType<Movie>()
        .toList();
  }

  // ----------------------------------------------------- latest trailers

  /// The choices of the home page's "Latest Trailers" drop-down.
  static const trailerCategories = [
    'Popular',
    'Streaming',
    'On TV',
    'For Rent',
    'In Theaters',
  ];

  final Map<String, List<TrailerItem>> _trailerCache = {};
  final Map<String, DateTime> _trailerAt = {};

  /// Titles of one [category] with their newest official trailer, newest
  /// trailer first. Titles without a YouTube trailer are left out. Kept for
  /// 30 minutes so switching back and forth is instant.
  Future<List<TrailerItem>> latestTrailers(String category,
      {bool force = false}) async {
    if (!enabled) return const [];
    final hit = _trailerCache[category];
    final at = _trailerAt[category];
    if (!force &&
        hit != null &&
        at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 30)) {
      return hit;
    }

    final (path, query, type) = switch (category) {
      'Streaming' => (
          '/discover/movie',
          <String, String>{
            'with_watch_monetization_types': 'flatrate',
            'watch_region': 'US',
            'sort_by': 'popularity.desc',
          },
          'movie'
        ),
      'On TV' => ('/tv/on_the_air', <String, String>{}, 'tv'),
      'For Rent' => (
          '/discover/movie',
          <String, String>{
            'with_watch_monetization_types': 'rent',
            'watch_region': 'US',
            'sort_by': 'popularity.desc',
          },
          'movie'
        ),
      'In Theaters' => (
          '/movie/now_playing',
          <String, String>{'region': 'US'},
          'movie'
        ),
      _ => ('/movie/popular', <String, String>{}, 'movie'),
    };

    final d = await _get(path, query);
    if (d is! Map || d['results'] is! List) return hit ?? const [];
    final rows = (d['results'] as List).whereType<Map>().take(16).toList();
    final found = await Future.wait(rows.map((r) => _trailerItem(r, type)));
    final items = [
      for (final i in found)
        if (i != null) i,
    ]..sort((a, b) => b.published.compareTo(a.published));
    final out = items.take(12).toList();
    if (out.isNotEmpty) {
      _trailerCache[category] = out;
      _trailerAt[category] = DateTime.now();
    }
    return out;
  }

  Future<TrailerItem?> _trailerItem(Map r, String type) async {
    final movie = fromJson(r, type: type);
    if (movie == null || movie.tmdbId == null) return null;
    final v = await _get(
        '/$type/${movie.tmdbId}/videos', {'include_video_language': 'en,null'});
    if (v is! Map || v['results'] is! List) return null;

    Map? best;
    var bestScore = -1;
    for (final e in v['results'] as List) {
      if (e is! Map || e['site'] != 'YouTube') continue;
      if ('${e['key'] ?? ''}'.isEmpty) continue;
      final kind = '${e['type'] ?? ''}';
      if (kind != 'Trailer' && kind != 'Teaser') continue;
      final score = (kind == 'Trailer' ? 2 : 0) + (e['official'] == true ? 1 : 0);
      final when = '${e['published_at'] ?? ''}';
      if (best == null ||
          score > bestScore ||
          (score == bestScore &&
              when.compareTo('${best['published_at'] ?? ''}') > 0)) {
        best = e;
        bestScore = score;
      }
    }
    if (best == null) return null;

    final trailer = Trailer(
      key: '${best['key']}',
      name: '${best['name'] ?? 'Official Trailer'}',
      type: '${best['type'] ?? 'Trailer'}',
      official: best['official'] == true,
    );
    final back = '${r['backdrop_path'] ?? ''}';
    return TrailerItem(
      movie,
      trailer,
      back.isEmpty ? trailer.thumbnail : 'https://image.tmdb.org/t/p/w780$back',
      '${best['published_at'] ?? ''}',
    );
  }

  /// Searches people (for Favorite people in the profile).
  Future<List<TmdbPerson>> searchPeople(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final d = await _get('/search/person', {'query': q, 'include_adult': 'false'});
    if (d is! Map || d['results'] is! List) return const [];
    final out = <TmdbPerson>[];
    for (final r in d['results'] as List) {
      if (r is! Map || r['id'] is! int) continue;
      final name = '${r['name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final path = '${r['profile_path'] ?? ''}';
      final known = <String>[];
      if (r['known_for'] is List) {
        for (final k in r['known_for'] as List) {
          if (k is Map) {
            final t = '${k['title'] ?? k['name'] ?? ''}'.trim();
            if (t.isNotEmpty) known.add(t);
          }
        }
      }
      out.add(TmdbPerson(
        r['id'] as int,
        name,
        path.isEmpty ? '' : 'https://image.tmdb.org/t/p/w185$path',
        known.take(3).join(', '),
      ));
    }
    return out;
  }
}

/// A person found on TMDB (actor, director...).
class TmdbPerson {
  final int id;
  final String name;
  final String photo;
  final String knownFor;
  const TmdbPerson(this.id, this.name, this.photo, this.knownFor);
}

class _Target {
  final int id;
  final bool tv;
  const _Target(this.id, this.tv);
}

final tmdb = TmdbService();
