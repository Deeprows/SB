import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/movie.dart';
import 'auth_service.dart';

/// Something went wrong talking to the community; [message] is safe to show.
class CommunityException implements Exception {
  final String code;
  const CommunityException(this.code);

  String get message {
    switch (code) {
      case 'google_required':
      case 'sign_in_required':
        return 'Sign in with your Gmail to use the community.';
      case 'google_verification_required':
        return 'Sign in with Google to use the community.';
      case 'community_key_mismatch':
        return 'This Gmail is already used on another phone. Ask the admin to reset it.';
      case 'network':
        return 'No connection. Please try again.';
      case 'slow_down':
        return 'You are going too fast. Try again in a bit.';
      case 'recommendation_needs_a_movie':
        return 'Pick a movie to recommend.';
      case 'unavailable':
        return 'The community is not set up yet.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  @override
  String toString() => message;
}

int? _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v');
bool _bool(dynamic v) => v == true || v == 1 || v == '1';
String _str(dynamic v) => v == null ? '' : '$v';
DateTime _at(dynamic v) =>
    DateTime.fromMillisecondsSinceEpoch((_int(v) ?? 0) * 1000);

/// One movie tweet or recommendation. One shared object per post, so a like
/// or comment shows everywhere the post appears.
class CommunityPost {
  final String id;
  final String email;
  String name;
  String photoUrl;
  final bool recommendation;
  final String text;
  final String movieTitle;
  final String movieImage;
  final int? movieId;
  final bool movieTv;

  /// 0-10, null = no rating.
  final int? rating;
  final DateTime createdAt;
  int likeCount;
  int commentCount;
  bool likedByMe;
  bool mine;

  CommunityPost({
    required this.id,
    required this.email,
    required this.name,
    required this.photoUrl,
    required this.recommendation,
    required this.text,
    required this.movieTitle,
    required this.movieImage,
    required this.movieId,
    required this.movieTv,
    required this.rating,
    required this.createdAt,
    required this.likeCount,
    required this.commentCount,
    required this.likedByMe,
    required this.mine,
  });

  bool get hasMovie => movieTitle.isNotEmpty;

  /// The title as a playable [Movie] (null when it has no TMDB id).
  Movie? get movie => movieId == null
      ? null
      : Movie.tryParse({
          'tmdbId': movieId,
          'type': movieTv ? 'tv' : 'movie',
          'name': movieTitle,
          'image': movieImage,
        });

  void _copyFrom(CommunityPost o) {
    name = o.name;
    photoUrl = o.photoUrl;
    likeCount = o.likeCount;
    commentCount = o.commentCount;
    likedByMe = o.likedByMe;
    mine = o.mine;
  }

  static CommunityPost? tryParse(dynamic j) {
    if (j is! Map) return null;
    final id = _str(j['id']);
    if (id.isEmpty) return null;
    final name = _str(j['name']).trim();
    return CommunityPost(
      id: id,
      email: _str(j['email']),
      name: name.isEmpty ? 'Movie fan' : name,
      photoUrl: _str(j['photoUrl']),
      recommendation: _str(j['kind']) == 'recommendation',
      text: _str(j['text']),
      movieTitle: _str(j['movieTitle']),
      movieImage: _str(j['movieImage']),
      movieId: _int(j['movieId']),
      movieTv: _str(j['movieType']) == 'tv',
      rating: _int(j['rating']),
      createdAt: _at(j['createdAt']),
      likeCount: _int(j['likeCount']) ?? 0,
      commentCount: _int(j['commentCount']) ?? 0,
      likedByMe: _bool(j['likedByMe']),
      mine: _bool(j['mine']),
    );
  }
}

class CommunityComment {
  final String id;
  final String email;
  final String name;
  final String photoUrl;
  final String text;
  final DateTime createdAt;
  final bool mine;
  final bool canDelete;

  const CommunityComment({
    required this.id,
    required this.email,
    required this.name,
    required this.photoUrl,
    required this.text,
    required this.createdAt,
    required this.mine,
    required this.canDelete,
  });

  static CommunityComment? tryParse(dynamic j) {
    if (j is! Map) return null;
    final id = _str(j['id']);
    if (id.isEmpty) return null;
    final name = _str(j['name']).trim();
    return CommunityComment(
      id: id,
      email: _str(j['email']),
      name: name.isEmpty ? 'Movie fan' : name,
      photoUrl: _str(j['photoUrl']),
      text: _str(j['text']),
      createdAt: _at(j['createdAt']),
      mine: _bool(j['mine']),
      canDelete: _bool(j['canDelete']),
    );
  }
}

class CommunityPerson {
  final String email;
  final String name;
  final String photoUrl;
  final int postCount;
  const CommunityPerson(this.email, this.name, this.photoUrl, this.postCount);
}

/// Someone's public profile: counts, last tweet, last recommendation.
class CommunityProfile {
  final String email;
  final String name;
  final String photoUrl;
  final String bio;
  final bool mine;
  final int postCount;
  final int likeCount;
  final CommunityPost? lastTweet;
  final CommunityPost? lastRecommendation;
  final List<CommunityPost> posts;

  const CommunityProfile({
    required this.email,
    required this.name,
    required this.photoUrl,
    required this.bio,
    required this.mine,
    required this.postCount,
    required this.likeCount,
    required this.lastTweet,
    required this.lastRecommendation,
    required this.posts,
  });
}

/// The movie community (tweets, recommendations, likes, comments, profiles).
/// Every call carries a Google ID token that the Worker verifies, see
/// COMMUNITY_SETUP.md.
class CommunityService extends ChangeNotifier {
  CommunityService._();
  static final CommunityService instance = CommunityService._();

  final Map<String, CommunityPost> _cache = {};
  final List<CommunityPost> _feed = [];
  String _kind = ''; // '' = all, 'tweet', 'recommendation'
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  List<CommunityPost> get feed => List.unmodifiable(_feed);
  String get kind => _kind;
  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;

  String get _base => AppConfig.feedBase.trim().replaceAll(RegExp(r'/+$'), '');
  bool get available => _base.isNotEmpty;
  bool get signedIn => AuthService.instance.user != null;

  // ------------------------------------------------------------------ http

  static String? _key;

  /// A random secret made once on this phone. The first phone to use a Gmail
  /// locks that Gmail's community account to this secret.
  Future<String> _phoneKey() async {
    if (_key != null) return _key!;
    try {
      final prefs = await SharedPreferences.getInstance();
      var k = prefs.getString('community_key');
      if (k == null || k.length < 32) {
        final r = Random.secure();
        k = List.generate(
                32, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'))
            .join();
        await prefs.setString('community_key', k);
      }
      return _key = k;
    } catch (_) {
      return _key = List.generate(
              32, (_) => Random.secure().nextInt(16).toRadixString(16))
          .join();
    }
  }

  Future<dynamic> _request(String path,
      {Map<String, dynamic>? body}) async {
    if (!available) throw const CommunityException('unavailable');
    final user = AuthService.instance.user;
    if (user == null) throw const CommunityException('google_required');
    // Two proofs are sent: a Google ID token when this build has one, and
    // this phone's own key. The Worker accepts either (COMMUNITY_SETUP.md).
    final token = await AuthService.instance.googleIdToken();
    final headers = {
      if (token != null) 'authorization': 'Bearer $token',
      'x-community-email': user.email.trim().toLowerCase(),
      'x-community-key': await _phoneKey(),
      'x-community-name': Uri.encodeComponent(user.name),
      if (user.photoUrl != null && user.photoUrl!.startsWith('https://'))
        'x-community-photo': Uri.encodeComponent(user.photoUrl!),
      if (body != null) 'content-type': 'application/json',
    };
    final uri = Uri.parse('$_base$path');
    final http.Response res;
    try {
      res = body != null
          ? await http
              .post(uri, headers: headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 15))
          : await http
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const CommunityException('network');
    }
    dynamic data;
    try {
      data = jsonDecode(res.body);
    } catch (_) {}
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final code = data is Map ? _str(data['error']) : '';
      throw CommunityException(res.statusCode == 503 ? 'unavailable' : code);
    }
    return data;
  }

  CommunityPost _intern(CommunityPost p) {
    final old = _cache[p.id];
    if (old == null) {
      _cache[p.id] = p;
      return p;
    }
    old._copyFrom(p);
    return old;
  }

  List<CommunityPost> _posts(dynamic raw) {
    final out = <CommunityPost>[];
    if (raw is List) {
      for (final row in raw) {
        final p = CommunityPost.tryParse(row);
        if (p != null) out.add(_intern(p));
      }
    }
    return out;
  }

  // ------------------------------------------------------------------ feed

  /// Loads the feed ([kind]: '' all, 'tweet', 'recommendation').
  Future<void> load({String? kind}) async {
    if (kind != null) _kind = kind;
    _loading = true;
    _error = null;
    notifyListeners();
    final asked = _kind;
    try {
      final d = await _request(
          '/community/posts${asked.isEmpty ? '' : '?kind=$asked'}');
      if (asked == _kind) {
        _feed
          ..clear()
          ..addAll(_posts(d is Map ? d['posts'] : null));
      }
    } on CommunityException catch (e) {
      _error = e.message;
    }
    _loaded = true;
    _loading = false;
    notifyListeners();
  }

  /// Publishes a post. [rating] is 0-10.
  Future<CommunityPost> post({
    required String text,
    required bool recommendation,
    Movie? movie,
    int? rating,
  }) async {
    final id = movie == null
        ? null
        : (movie.tmdbId ??
            int.tryParse(
                RegExp(r'/(?:movie|tv)/(\d+)').firstMatch(movie.url)?.group(1) ??
                    ''));
    final d = await _request('/community/posts', body: {
      'text': text.trim(),
      'kind': recommendation ? 'recommendation' : 'tweet',
      if (movie != null) 'movieTitle': movie.title,
      if (movie != null && movie.image.startsWith('https://'))
        'movieImage': movie.image,
      if (id != null) 'movieId': id,
      if (movie != null) 'movieType': movie.isSeries ? 'tv' : 'movie',
      if (movie != null && rating != null && rating > 0) 'rating': rating,
    });
    final p = CommunityPost.tryParse(d is Map ? d['post'] : null);
    if (p == null) throw const CommunityException('');
    final mine = _intern(p);
    if (_kind.isEmpty || (_kind == 'recommendation') == mine.recommendation) {
      _feed.insert(0, mine);
    }
    notifyListeners();
    return mine;
  }

  Future<void> deletePost(CommunityPost p) async {
    await _request('/community/delete', body: {'postId': p.id});
    _feed.removeWhere((x) => x.id == p.id);
    _cache.remove(p.id);
    notifyListeners();
  }

  /// Heart / un-heart. Changes at once; put back if the server refuses.
  Future<void> toggleLike(CommunityPost p) async {
    final was = p.likedByMe;
    final count = p.likeCount;
    p.likedByMe = !was;
    p.likeCount = was ? (count > 0 ? count - 1 : 0) : count + 1;
    notifyListeners();
    try {
      final d = await _request('/community/like', body: {'postId': p.id});
      if (d is Map) {
        p.likedByMe = _bool(d['liked']);
        p.likeCount = _int(d['likeCount']) ?? p.likeCount;
      }
    } catch (_) {
      p.likedByMe = was;
      p.likeCount = count;
      notifyListeners();
      rethrow;
    }
    notifyListeners();
  }

  // -------------------------------------------------------------- comments

  Future<List<CommunityComment>> comments(CommunityPost p) async {
    final d = await _request(
        '/community/comments?postId=${Uri.encodeQueryComponent(p.id)}');
    final out = <CommunityComment>[];
    final raw = d is Map ? d['comments'] : null;
    if (raw is List) {
      for (final row in raw) {
        final c = CommunityComment.tryParse(row);
        if (c != null) out.add(c);
      }
    }
    if (p.commentCount != out.length) {
      p.commentCount = out.length;
      notifyListeners();
    }
    return out;
  }

  Future<void> addComment(CommunityPost p, String text) async {
    final d = await _request('/community/comments',
        body: {'postId': p.id, 'text': text.trim()});
    p.commentCount = d is Map ? (_int(d['commentCount']) ?? p.commentCount + 1) : p.commentCount + 1;
    notifyListeners();
  }

  Future<void> deleteComment(CommunityPost p, CommunityComment c) async {
    await _request('/community/comments/delete', body: {'id': c.id});
    if (p.commentCount > 0) p.commentCount -= 1;
    notifyListeners();
  }

  // -------------------------------------------------------------- profiles

  Future<CommunityProfile> profile(String email) async {
    final d = await _request(
        '/community/profile?email=${Uri.encodeQueryComponent(email)}');
    final j = d is Map ? d['profile'] : null;
    if (j is! Map) throw const CommunityException('');
    CommunityPost? one(dynamic raw) {
      final p = CommunityPost.tryParse(raw);
      return p == null ? null : _intern(p);
    }

    final name = _str(j['name']).trim();
    return CommunityProfile(
      email: _str(j['email']),
      name: name.isEmpty ? 'Movie fan' : name,
      photoUrl: _str(j['photoUrl']),
      bio: _str(j['bio']),
      mine: _bool(j['mine']),
      postCount: _int(j['postCount']) ?? 0,
      likeCount: _int(j['likeCount']) ?? 0,
      lastTweet: one(j['lastTweet']),
      lastRecommendation: one(j['lastRecommendation']),
      posts: _posts(j['posts']),
    );
  }

  Future<List<CommunityPerson>> people() async {
    final d = await _request('/community/people');
    final out = <CommunityPerson>[];
    final raw = d is Map ? d['people'] : null;
    if (raw is List) {
      for (final r in raw) {
        if (r is! Map) continue;
        final email = _str(r['email']);
        if (email.isEmpty) continue;
        final name = _str(r['name']).trim();
        out.add(CommunityPerson(
          email,
          name.isEmpty ? email.split('@').first : name,
          _str(r['photoUrl']),
          _int(r['postCount']) ?? 0,
        ));
      }
    }
    return out;
  }

  /// Forget what is shown (on sign out).
  void clear() {
    _cache.clear();
    _feed.clear();
    _loaded = false;
    _error = null;
    notifyListeners();
  }
}
