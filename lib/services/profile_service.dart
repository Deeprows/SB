import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/movie.dart';
import 'auth_service.dart';
import 'movie_library.dart';
import 'rating_service.dart';

/// A list you made yourself ("Weekend picks", "Best of 2026"...).
class UserList {
  final String id;
  String name;
  final List<Movie> movies;
  UserList({required this.id, required this.name, List<Movie>? movies})
      : movies = movies ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'movies': movies.map((m) => m.toJson()).toList(),
      };

  static UserList? tryParse(dynamic j) {
    if (j is! Map) return null;
    final id = '${j['id'] ?? ''}';
    final name = '${j['name'] ?? ''}'.trim();
    if (id.isEmpty || name.isEmpty) return null;
    final movies = <Movie>[];
    if (j['movies'] is List) {
      for (final row in j['movies'] as List) {
        final m = Movie.tryParse(row);
        if (m != null) movies.add(m);
      }
    }
    return UserList(id: id, name: name, movies: movies);
  }
}

class MovieReview {
  final Movie movie;
  final String text;
  final int stars; // 0 = not rated when written
  final DateTime at;
  const MovieReview(this.movie, this.text, this.stars, this.at);

  Map<String, dynamic> toJson() => {
        ...movie.toJson(),
        'reviewText': text,
        'reviewStars': stars,
        'at': at.toIso8601String(),
      };

  static MovieReview? tryParse(dynamic j) {
    final m = Movie.tryParse(j);
    if (m == null || j is! Map) return null;
    final text = '${j['reviewText'] ?? ''}'.trim();
    if (text.isEmpty) return null;
    return MovieReview(
      m,
      text,
      (j['reviewStars'] as num?)?.toInt() ?? 0,
      DateTime.tryParse('${j['at']}') ?? DateTime.now(),
    );
  }
}

class CheckIn {
  final Movie movie;
  final DateTime at;
  const CheckIn(this.movie, this.at);

  Map<String, dynamic> toJson() => {
        ...movie.toJson(),
        'at': at.toIso8601String(),
      };

  static CheckIn? tryParse(dynamic j) {
    final m = Movie.tryParse(j);
    if (m == null || j is! Map) return null;
    return CheckIn(m, DateTime.tryParse('${j['at']}') ?? DateTime.now());
  }
}

class FavoritePerson {
  final int id;
  final String name;
  final String photo;
  final String knownFor;
  const FavoritePerson(this.id, this.name, this.photo, this.knownFor);

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'photo': photo, 'knownFor': knownFor};

  static FavoritePerson? tryParse(dynamic j) {
    if (j is! Map) return null;
    final id = (j['id'] as num?)?.toInt();
    final name = '${j['name'] ?? ''}'.trim();
    if (id == null || name.isEmpty) return null;
    return FavoritePerson(
        id, name, '${j['photo'] ?? ''}', '${j['knownFor'] ?? ''}');
  }
}

class ProfileBadge {
  final String id;
  final String title;
  final String hint;
  final int have;
  final int need;
  const ProfileBadge(this.id, this.title, this.hint, this.have, this.need);
  bool get earned => have >= need;
}

/// Everything that makes up one person's profile: their lists, reviews,
/// check-ins, interests, favourite people and badges. It is saved on the
/// phone under the signed-in Gmail address, so each account has its own.
/// (Ratings, Watchlist and Watch history come from their own services.)
class ProfileService extends ChangeNotifier {
  ProfileService._() {
    AuthService.instance.addListener(_onAuth);
    MovieLibrary.instance.addListener(notifyListeners);
    RatingService.instance.addListener(notifyListeners);
  }
  static final ProfileService instance = ProfileService._();

  static const _prefix = 'profile_v1_';

  final List<UserList> _lists = [];
  final List<MovieReview> _reviews = [];
  final List<CheckIn> _checkIns = [];
  final List<String> _interests = [];
  final List<FavoritePerson> _people = [];

  String _loadedFor = '\u0000';
  Future<void>? _loading;

  /// Whose saved profile is loaded right now (lower-case Gmail or 'guest').
  String get loadedFor => _loadedFor;

  List<UserList> get lists => List.unmodifiable(_lists);
  List<MovieReview> get reviews => List.unmodifiable(_reviews);
  List<CheckIn> get checkIns => List.unmodifiable(_checkIns);
  List<String> get interests => List.unmodifiable(_interests);
  List<FavoritePerson> get people => List.unmodifiable(_people);

  String get _email =>
      (AuthService.instance.user?.email ?? 'guest').trim().toLowerCase();

  void _onAuth() {
    if (_email != _loadedFor) {
      _loading = null;
      load();
    }
  }

  /// Reads the saved profile of whoever is signed in (safe to call often).
  Future<void> load() {
    if (_loadedFor != _email) _loading = null;
    return _loading ??= _read();
  }

  Future<void> _read() async {
    final who = _email;
    _lists.clear();
    _reviews.clear();
    _checkIns.clear();
    _interests.clear();
    _people.clear();
    try {
      final raw = (await SharedPreferences.getInstance()).getString('$_prefix$who');
      if (raw != null) {
        final j = jsonDecode(raw);
        if (j is Map) {
          _fill(_lists, j['lists'], UserList.tryParse);
          _fill(_reviews, j['reviews'], MovieReview.tryParse);
          _fill(_checkIns, j['checkIns'], CheckIn.tryParse);
          _fill(_people, j['people'], FavoritePerson.tryParse);
          if (j['interests'] is List) {
            _interests.addAll((j['interests'] as List).map((e) => '$e'));
          }
        }
      }
    } catch (_) {}
    _loadedFor = who;
    notifyListeners();
  }

  static void _fill<T>(List<T> out, dynamic raw, T? Function(dynamic) parse) {
    if (raw is! List) return;
    for (final row in raw) {
      final v = parse(row);
      if (v != null) out.add(v);
    }
  }

  Future<void> _save() async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        '$_prefix$_loadedFor',
        jsonEncode({
          'lists': _lists.map((e) => e.toJson()).toList(),
          'reviews': _reviews.map((e) => e.toJson()).toList(),
          'checkIns': _checkIns.map((e) => e.toJson()).toList(),
          'interests': _interests,
          'people': _people.map((e) => e.toJson()).toList(),
        }),
      );
    } catch (_) {}
  }

  Future<void> _changed() async {
    notifyListeners();
    await _save();
  }

  // ------------------------------------------------------------------ lists

  Future<UserList> createList(String name) async {
    await load();
    final l = UserList(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name.trim().isEmpty ? 'My list' : name.trim());
    _lists.insert(0, l);
    await _changed();
    return l;
  }

  Future<void> renameList(UserList l, String name) async {
    if (name.trim().isEmpty) return;
    l.name = name.trim();
    await _changed();
  }

  Future<void> deleteList(UserList l) async {
    _lists.removeWhere((x) => x.id == l.id);
    await _changed();
  }

  bool inList(UserList l, Movie m) => l.movies.any((x) => x.url == m.url);

  /// Adds [m] to [l], or removes it when it is already there. True = added.
  Future<bool> toggleInList(UserList l, Movie m) async {
    final i = l.movies.indexWhere((x) => x.url == m.url);
    final added = i < 0;
    if (added) {
      l.movies.insert(0, m);
    } else {
      l.movies.removeAt(i);
    }
    await _changed();
    return added;
  }

  // ---------------------------------------------------------------- reviews

  MovieReview? reviewFor(Movie m) {
    for (final r in _reviews) {
      if (r.movie.url == m.url) return r;
    }
    return null;
  }

  /// Saves (or replaces) your review of [m]; empty text removes it.
  Future<void> saveReview(Movie m, String text) async {
    await load();
    _reviews.removeWhere((r) => r.movie.url == m.url);
    if (text.trim().isNotEmpty) {
      _reviews.insert(
        0,
        MovieReview(m, text.trim(), RatingService.instance.mine(m),
            DateTime.now()),
      );
    }
    await _changed();
  }

  Future<void> deleteReview(MovieReview r) async {
    _reviews.removeWhere((x) => identical(x, r));
    await _changed();
  }

  // --------------------------------------------------------------- check-ins

  Future<void> checkIn(Movie m) async {
    await load();
    _checkIns.insert(0, CheckIn(m, DateTime.now()));
    if (_checkIns.length > 300) _checkIns.removeRange(300, _checkIns.length);
    await _changed();
  }

  Future<void> deleteCheckIn(CheckIn c) async {
    _checkIns.removeWhere((x) => identical(x, c));
    await _changed();
  }

  // -------------------------------------------------------------- interests

  Future<void> toggleInterest(String genre) async {
    await load();
    if (!_interests.remove(genre)) _interests.add(genre);
    await _changed();
  }

  // ------------------------------------------------------- favourite people

  bool isFavorite(int id) => _people.any((p) => p.id == id);

  Future<void> toggleFavorite(FavoritePerson p) async {
    await load();
    final i = _people.indexWhere((x) => x.id == p.id);
    if (i >= 0) {
      _people.removeAt(i);
    } else {
      _people.insert(0, p);
    }
    await _changed();
  }

  // ----------------------------------------------------------------- badges

  /// Earned automatically from what the person does in the app.
  List<ProfileBadge> get badges => buildBadges(
        ratings: RatingService.instance.ratedMovies.length,
        watched: MovieLibrary.instance.history.length,
        saved: MovieLibrary.instance.watchLater.length,
        reviews: _reviews.length,
        lists: _lists.length,
        checkIns: _checkIns.length,
        interests: _interests.length,
        people: _people.length,
      );

  /// The badge rules, also used to show another member's badges.
  static List<ProfileBadge> buildBadges({
    required int ratings,
    required int watched,
    required int saved,
    required int reviews,
    required int lists,
    required int checkIns,
    required int interests,
    required int people,
  }) =>
      [
        ProfileBadge('first_rating', 'First Rating', 'Rate your first title', ratings, 1),
        ProfileBadge('critic', 'Critic', 'Rate 10 titles', ratings, 10),
        ProfileBadge('reviewer', 'Reviewer', 'Write your first review', reviews, 1),
        ProfileBadge('movie_buff', 'Movie Buff', 'Watch 25 titles', watched, 25),
        ProfileBadge('binge', 'Binge Watcher', 'Watch 100 titles', watched, 100),
        ProfileBadge('collector', 'Collector', 'Save 10 titles to your Watchlist', saved, 10),
        ProfileBadge('curator', 'Curator', 'Create your first list', lists, 1),
        ProfileBadge('checkin', 'Regular', 'Check in 5 times', checkIns, 5),
        ProfileBadge('taste', 'Taste Maker', 'Pick 3 interests', interests, 3),
        ProfileBadge('fan', 'Superfan', 'Add 3 favorite people', people, 3),
      ];

  int get earnedBadges => badges.where((b) => b.earned).length;
}
