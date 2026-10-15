import '../services/remote_config.dart';
import '../utils/posted_at.dart';
class Movie {
  final String name;
  final String url;
  final String downloadUrl;
  final DateTime? date;
  final String? rating; // "7.4"
  final List<String> genres;
  final String image;

  /// TMDB id (null for older rows that only have a plain link).
  final int? tmdbId;

  const Movie({
    required this.name,
    required this.url,
    required this.downloadUrl,
    required this.date,
    required this.rating,
    required this.genres,
    required this.image,
    this.tmdbId,
  });

  /// Player link for a TMDB id.
  static String embedUrlFor(int tmdbId, {bool tv = false}) =>
      '${RemoteConfig.instance.embedBase}/${tv ? 'tv' : 'movie'}/$tmdbId';

  /// Backup player link (Switch button): movies `<altEmbedBase>/movie/<id>`,
  /// series `<altEmbedBase>/tv/<id>/1/1`.
  static String altEmbedUrlFor(String id, {bool tv = false}) => tv
      ? '${RemoteConfig.instance.altEmbedBase}/tv/$id/1/1'
      : '${RemoteConfig.instance.altEmbedBase}/movie/$id';

  /// Third player link (Switch button 3/3): movies
  /// `<thirdEmbedBase>/movie/<id>`, series `<thirdEmbedBase>/tv/<id>/1/1`.
  static String thirdEmbedUrlFor(String id, {bool tv = false}) => tv
      ? '${RemoteConfig.instance.thirdEmbedBase}/tv/$id/1/1'
      : '${RemoteConfig.instance.thirdEmbedBase}/movie/$id';

  /// The id the backup players use: the TMDB id, or the id inside the row's
  /// own embed link (older rows). Null when unknown.
  String? get _embedId =>
      tmdbId?.toString() ??
      RegExp(r'/embed/(?:movie|tv)/(tt\d+|\d+)').firstMatch(url)?.group(1);

  /// Backup player for this title, or '' when its id is unknown.
  String get altUrl {
    final id = _embedId;
    return id == null ? '' : altEmbedUrlFor(id, tv: isSeries);
  }

  /// Third player for this title, or '' when its id is unknown.
  String get thirdUrl {
    final id = _embedId;
    return id == null ? '' : thirdEmbedUrlFor(id, tv: isSeries);
  }

  /// Download link for a TMDB id: `<downloadBase>/movie/<id>` or
  /// `<downloadBase>/tv/<id>`.
  static String downloadUrlFor(int tmdbId, {bool tv = false}) =>
      '${RemoteConfig.instance.downloadBase}/${tv ? 'tv' : 'movie'}/$tmdbId';

  /// Genre labels in one spelling, so your own rows and TMDB titles land in
  /// the same category pill ("Science Fiction" / "Sci-fi" -> "Sci-Fi";
  /// TMDB's "Action & Adventure" -> "Action" + "Adventure").
  static List<String> genreNames(String raw) {
    final g = raw.trim();
    switch (g.toLowerCase()) {
      case '':
        return const [];
      case 'science fiction':
      case 'sci-fi':
      case 'sci fi':
      case 'scifi':
        return const ['Sci-Fi'];
      case 'action & adventure':
        return const ['Action', 'Adventure'];
      case 'sci-fi & fantasy':
        return const ['Sci-Fi', 'Fantasy'];
      case 'war & politics':
        return const ['War'];
    }
    return [g];
  }

  /// A row that only carries a TMDB id and still needs its details.
  bool get needsDetails => tmdbId != null && name.isEmpty;

  /// Fills empty fields of this row from [o] (the TMDB copy); anything the
  /// row already sets itself wins.
  Movie fillFrom(Movie o) => Movie(
        name: name.isEmpty ? o.name : name,
        url: url,
        downloadUrl: downloadUrl,
        date: date ?? o.date,
        rating: rating ?? o.rating,
        genres: genres.isEmpty ? o.genres : genres,
        image: image.isEmpty ? o.image : image,
        tmdbId: tmdbId,
      );

  /// Saved form for Watch Later / Watch history; read back by [tryParse].
  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'downloadUrl': downloadUrl,
        if (date != null) 'date': date!.toIso8601String(),
        if (rating != null) 'rating': '$rating/10',
        'genre': genres.join(','),
        'image': image,
        if (tmdbId != null) 'tmdbId': tmdbId,
        'type': isSeries ? 'tv' : 'movie',
      };

  bool get isSeries =>
      url.contains('/embed/tv/') || url.contains('/tv/');
  bool get hasDownload => downloadUrl.startsWith('http');
  bool get hasImage => image.startsWith('http') || image.startsWith('data:image');

  /// Name without a trailing/parenthesised year: "Dhamaal (2026)" -> "Dhamaal".
  String get title => name
      .replaceAll(RegExp(r'\s*\(\d{4}\)\s*$'), '')
      .replaceAll(RegExp(r'\s+(19|20)\d{2}\s*$'), '')
      .trim();

  String? get year {
    final m = RegExp(r'((?:19|20)\d{2})\s*\)?\s*$').firstMatch(name);
    return m?.group(1);
  }

  static Movie? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    String s(String k) => (raw[k] ?? '').toString().trim();
    final name = s('name');
    var url = s('url');

    // A row can be just a TMDB id: {"tmdbId": 9319989, "type": "movie"}
    // ("type": "tv" for a series). Links are built from the id.
    final tmdbId = int.tryParse(
        (raw['tmdbId'] ?? raw['tmdb_id'] ?? raw['tmdb'] ?? '').toString());
    final tv = const {'tv', 'series', 'show'}
        .contains((raw['type'] ?? raw['mediaType'] ?? '').toString().toLowerCase());
    if (tmdbId != null && !url.startsWith('http')) {
      url = embedUrlFor(tmdbId, tv: tv);
    }
    if (!url.startsWith('http')) return null;
    if (name.isEmpty && tmdbId == null) return null;
    url = _swapHost(url);

    var date = s('date');
    var dl = s('downloadUrl');
    // Some rows have the date shifted into downloadUrl.
    if (!dl.startsWith('http')) {
      if (date.isEmpty && RegExp(r'^\d{4}-\d\d-\d\d').hasMatch(dl)) date = dl;
      dl = '';
    }
    if (dl.isEmpty && tmdbId != null) {
      if (url.contains('/embed/tv/') || url.contains('/tv/')) {
        dl = downloadUrlFor(tmdbId, tv: true);
      } else if (url.contains('/embed/movie/') || url.contains('/movie/')) {
        dl = downloadUrlFor(tmdbId);
      }
    }

    return Movie(
      name: name,
      url: url,
      downloadUrl: dl,
      date: parsePostedAt(date, s('time')),
      rating: parseRating(s('rating')),
      genres: s('genre')
          .split(',')
          .expand(genreNames)
          .toSet()
          .toList(),
      image: normalizeImage(s('image')),
      tmdbId: tmdbId,
    );
  }

  /// Same movie with another poster.
  Movie withImage(String img) => Movie(
        name: name,
        url: url,
        downloadUrl: downloadUrl,
        date: date,
        rating: rating,
        genres: genres,
        image: img,
        tmdbId: tmdbId,
      );

  /// TMDB website image links (www./media.themoviedb.org, sizes such as
  /// `w600_and_h900_face`) are page assets, not the image CDN, and often fail
  /// or get blocked in apps. They are moved to image.tmdb.org (w500).
  static String normalizeImage(String raw) {
    final m = RegExp(
            r'^https?://(?:www\.|media\.)?themoviedb\.org/t/p/[^/]+/(.+)$',
            caseSensitive: false)
        .firstMatch(raw);
    if (m != null) return 'https://image.tmdb.org/t/p/w500/${m.group(1)}';
    return raw;
  }

  /// A row with a full link on an old player host (app_config.json
  /// `movies.replaceHosts`, e.g. vsembed.ru) is moved to the current
  /// `movies.embedBase`, so changing the player link fixes your own rows too.
  static String _swapHost(String url) {
    final m = RegExp(r'^https?://([^/]+)/embed/(movie|tv)/(.*)$',
            caseSensitive: false)
        .firstMatch(url);
    if (m == null) return url;
    final host = m.group(1)!.toLowerCase();
    if (!RemoteConfig.instance.replaceHosts.contains(host)) return url;
    return '${RemoteConfig.instance.embedBase}/${m.group(2)!.toLowerCase()}/${m.group(3)}';
  }

  /// "IMDb 5.1/10", "7.0/10 ⭐", "68/100 TMDB ⭐", "Action | Drama - 8.0/10 ⭐"
  /// all become a one-decimal score out of 10, or null.
  static String? parseRating(String raw) {
    final m10 = RegExp(r'(\d+(?:\.\d+)?)\s*/\s*10(?!\d)').firstMatch(raw);
    if (m10 != null) {
      final v = double.tryParse(m10.group(1)!);
      if (v != null) return v.toStringAsFixed(1);
    }
    final m100 = RegExp(r'(\d+(?:\.\d+)?)\s*/\s*100').firstMatch(raw);
    if (m100 != null) {
      final v = double.tryParse(m100.group(1)!);
      if (v != null) return (v / 10).toStringAsFixed(1);
    }
    return null;
  }
}
