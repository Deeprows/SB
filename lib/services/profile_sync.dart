import 'dart:async';
import 'dart:convert';

import '../models/movie.dart';
import 'auth_service.dart';
import 'community_service.dart';
import 'movie_library.dart';
import 'profile_service.dart';
import 'rating_service.dart';

/// Keeps a copy of this person's profile (ratings, watch history, watchlist,
/// lists, reviews, check-ins, interests, favourite people) on the server, so
/// other members can open it from the community. Runs quietly in the
/// background whenever something in the profile changes.
class ProfileSync {
  ProfileSync._();
  static final ProfileSync instance = ProfileSync._();

  Timer? _timer;
  String _last = '';
  String _lastFor = '';
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    for (final l in [
      ProfileService.instance,
      MovieLibrary.instance,
      RatingService.instance,
      AuthService.instance,
    ]) {
      l.addListener(_schedule);
    }
    // Load what is saved on the phone; the loads notify and schedule a push.
    ProfileService.instance.load();
    RatingService.instance.load();
    MovieLibrary.instance.load();
    _schedule();
  }

  void _schedule([Duration after = const Duration(seconds: 5)]) {
    _timer?.cancel();
    _timer = Timer(after, () => unawaited(_push()));
  }

  Map<String, dynamic> _snapshot() {
    final prof = ProfileService.instance;
    final lib = MovieLibrary.instance;
    return {
      'v': 1,
      'ratings': [
        for (final (m, s) in RatingService.instance.ratedMovies.take(200))
          {...m.toJson(), 'stars': s},
      ],
      'history': [
        for (final e in lib.history.take(60))
          {...e.movie.toJson(), 'watchedAt': e.at.toIso8601String()},
      ],
      'watchlist': [for (final m in lib.watchLater.take(100)) m.toJson()],
      'lists': [
        for (final l in prof.lists.take(30))
          {
            'id': l.id,
            'name': l.name,
            'movies': [for (final m in l.movies.take(60)) m.toJson()],
          },
      ],
      'reviews': [for (final r in prof.reviews.take(60)) r.toJson()],
      'checkIns': [for (final c in prof.checkIns.take(60)) c.toJson()],
      'interests': prof.interests,
      'people': [for (final p in prof.people.take(60)) p.toJson()],
    };
  }

  Future<void> _push() async {
    final user = AuthService.instance.user;
    if (user == null || !CommunityService.instance.available) return;
    final email = user.email.trim().toLowerCase();
    // Never send the previous account's data under a new Gmail.
    if (ProfileService.instance.loadedFor != email) return;
    if (_lastFor != email) {
      _lastFor = email;
      _last = '';
    }
    final snap = _snapshot();
    final enc = jsonEncode(snap);
    if (enc == _last) return;
    try {
      await CommunityService.instance.pushProfileData(snap);
      _last = enc;
    } catch (_) {
      _schedule(const Duration(seconds: 60)); // try again later
    }
  }
}

/// Reads a snapshot back (used by the member profile screen).
class MemberData {
  final List<(Movie, int)> ratings;
  final List<(Movie, DateTime)> history;
  final List<Movie> watchlist;
  final List<UserList> lists;
  final List<MovieReview> reviews;
  final List<CheckIn> checkIns;
  final List<String> interests;
  final List<FavoritePerson> people;

  MemberData({
    this.ratings = const [],
    this.history = const [],
    this.watchlist = const [],
    this.lists = const [],
    this.reviews = const [],
    this.checkIns = const [],
    this.interests = const [],
    this.people = const [],
  });

  static List<dynamic> _list(dynamic v) => v is List ? v : const [];

  factory MemberData.fromJson(Map<String, dynamic> j) {
    final ratings = <(Movie, int)>[];
    for (final row in _list(j['ratings'])) {
      final m = Movie.tryParse(row);
      final s = row is Map ? (row['stars'] as num?)?.toInt() ?? 0 : 0;
      if (m != null && s > 0) ratings.add((m, s));
    }
    final history = <(Movie, DateTime)>[];
    for (final row in _list(j['history'])) {
      final m = Movie.tryParse(row);
      if (m == null) continue;
      final at = row is Map ? DateTime.tryParse('${row['watchedAt']}') : null;
      history.add((m, at ?? DateTime.now()));
    }
    return MemberData(
      ratings: ratings,
      history: history,
      watchlist: [
        for (final row in _list(j['watchlist']))
          if (Movie.tryParse(row) case final m?) m,
      ],
      lists: [
        for (final row in _list(j['lists']))
          if (UserList.tryParse(row) case final l?) l,
      ],
      reviews: [
        for (final row in _list(j['reviews']))
          if (MovieReview.tryParse(row) case final r?) r,
      ],
      checkIns: [
        for (final row in _list(j['checkIns']))
          if (CheckIn.tryParse(row) case final c?) c,
      ],
      interests: [for (final e in _list(j['interests'])) '$e'],
      people: [
        for (final row in _list(j['people']))
          if (FavoritePerson.tryParse(row) case final p?) p,
      ],
    );
  }

  List<ProfileBadge> get badges => ProfileService.buildBadges(
        ratings: ratings.length,
        watched: history.length,
        saved: watchlist.length,
        reviews: reviews.length,
        lists: lists.length,
        checkIns: checkIns.length,
        interests: interests.length,
        people: people.length,
      );

  int get earnedBadges => badges.where((b) => b.earned).length;
}
