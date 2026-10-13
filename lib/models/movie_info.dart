/// One cast member shown on a movie page.
class CastMember {
  final String name;
  final String character;
  final String photo; // full image url or ''

  const CastMember({
    required this.name,
    required this.character,
    required this.photo,
  });

  bool get hasPhoto => photo.startsWith('http');
}

/// Extra details for one title, fetched from TMDB.
class MovieInfo {
  final bool isSeries;
  final String overview;
  final String tagline;
  final String status;
  final String language;
  final String releaseDate; // yyyy-mm-dd or ''
  final String backdrop; // wide background image url or ''
  final int? runtime; // minutes (per episode for series)
  final int? seasons;
  final int? episodes;
  final List<String> genres;
  final List<String> directors; // directors, or creators for a series
  final List<CastMember> cast;

  const MovieInfo({
    required this.isSeries,
    required this.overview,
    required this.tagline,
    required this.status,
    required this.language,
    required this.releaseDate,
    required this.backdrop,
    required this.runtime,
    required this.seasons,
    required this.episodes,
    required this.genres,
    required this.directors,
    required this.cast,
  });

  /// "1h 44m", "45m", or '' when unknown.
  String get runtimeText {
    final r = runtime;
    if (r == null || r <= 0) return '';
    final h = r ~/ 60;
    final m = r % 60;
    if (h == 0) return '${m}m';
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  bool get hasContent =>
      overview.isNotEmpty || cast.isNotEmpty || directors.isNotEmpty;

  /// [j] is a TMDB `/movie/<id>` or `/tv/<id>` response fetched with
  /// `append_to_response=credits`.
  static MovieInfo? fromJson(dynamic j, {required bool tv}) {
    if (j is! Map) return null;
    String s(String k) => (j[k] ?? '').toString().trim();

    final genres = <String>[];
    if (j['genres'] is List) {
      for (final g in j['genres'] as List) {
        if (g is Map && g['name'] != null) genres.add(g['name'].toString());
      }
    }

    int? runtime;
    if (tv) {
      final r = j['episode_run_time'];
      if (r is List && r.isNotEmpty && r.first is num) {
        runtime = (r.first as num).toInt();
      }
    } else if (j['runtime'] is num) {
      runtime = (j['runtime'] as num).toInt();
    }

    var language = '';
    if (j['spoken_languages'] is List &&
        (j['spoken_languages'] as List).isNotEmpty) {
      final l = (j['spoken_languages'] as List).first;
      if (l is Map) {
        language = (l['english_name'] ?? l['name'] ?? '').toString();
      }
    }

    final credits = j['credits'];
    final cast = <CastMember>[];
    final directors = <String>[];
    if (credits is Map) {
      if (credits['cast'] is List) {
        for (final c in credits['cast'] as List) {
          if (c is! Map || (c['name'] ?? '').toString().isEmpty) continue;
          final p = (c['profile_path'] ?? '').toString();
          cast.add(CastMember(
            name: c['name'].toString(),
            character: (c['character'] ?? '').toString(),
            photo: p.isEmpty ? '' : 'https://image.tmdb.org/t/p/w185$p',
          ));
          if (cast.length >= 20) break;
        }
      }
      if (!tv && credits['crew'] is List) {
        for (final c in credits['crew'] as List) {
          if (c is Map && c['job'] == 'Director' && c['name'] != null) {
            directors.add(c['name'].toString());
          }
        }
      }
    }
    if (tv && j['created_by'] is List) {
      for (final c in j['created_by'] as List) {
        if (c is Map && c['name'] != null) directors.add(c['name'].toString());
      }
    }

    return MovieInfo(
      isSeries: tv,
      overview: s('overview'),
      tagline: s('tagline'),
      status: s('status'),
      language: language,
      releaseDate: s(tv ? 'first_air_date' : 'release_date'),
      backdrop: s('backdrop_path').isEmpty
          ? ''
          : 'https://image.tmdb.org/t/p/w780${s('backdrop_path')}',
      runtime: runtime,
      seasons: j['number_of_seasons'] is num
          ? (j['number_of_seasons'] as num).toInt()
          : null,
      episodes: j['number_of_episodes'] is num
          ? (j['number_of_episodes'] as num).toInt()
          : null,
      genres: genres.expand(_genreNames).toSet().toList(),
      directors: directors.toSet().toList(),
      cast: cast,
    );
  }

  static List<String> _genreNames(String g) => const {
        'Science Fiction': ['Sci-Fi'],
        'Action & Adventure': ['Action', 'Adventure'],
        'Sci-Fi & Fantasy': ['Sci-Fi', 'Fantasy'],
        'War & Politics': ['War'],
      }[g] ??
      [g];
}
