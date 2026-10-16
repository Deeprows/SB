import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Who is signed in (kept on the phone).
class AuthUser {
  final String email;
  final String name;
  final String? photoUrl;

  const AuthUser({required this.email, required this.name, this.photoUrl});

  Map<String, dynamic> toJson() =>
      {'email': email, 'name': name, 'photoUrl': photoUrl};

  static AuthUser? fromJson(Object? j) {
    if (j is! Map) return null;
    final email = '${j['email'] ?? ''}';
    if (email.isEmpty) return null;
    final photo = j['photoUrl'];
    return AuthUser(
      email: email,
      name: '${j['name'] ?? ''}'.trim().isEmpty
          ? email.split('@').first
          : '${j['name']}',
      photoUrl: photo is String && photo.isNotEmpty ? photo : null,
    );
  }
}

enum SignInResult {
  ok,
  cancelled,
  notGmail,
  setupError,
  network,
  failed,

  /// Log in was chosen but this Gmail never signed up.
  notRegistered,
}

/// Gmail-only sign-in (Google Sign-In). No password, no Firebase.
/// The saved account is read at start-up, so people stay signed in and the
/// app still opens offline.
class AuthService extends ChangeNotifier {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _kUser = 'auth_user';
  static const _kRegistered = 'auth_registered';

  final GoogleSignIn _google = GoogleSignIn(
    scopes: const ['email', 'profile'],
    serverClientId:
        AppConfig.googleServerClientId.isEmpty ? null : AppConfig.googleServerClientId,
  );

  AuthUser? _user;
  AuthUser? get user => _user;

  /// Technical detail of the last failed sign-in (shown small on the login
  /// page so problems are easy to diagnose).
  String lastError = '';
  bool get signedIn => !AppConfig.loginRequired || _user != null;

  /// Only @gmail.com (and the older @googlemail.com) addresses are allowed.
  static bool isGmail(String email) {
    final e = email.trim().toLowerCase();
    return e.endsWith('@gmail.com') || e.endsWith('@googlemail.com');
  }

  /// Reads the saved account (never touches the network).
  Future<void> init() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_kUser);
      if (raw != null) {
        final u = AuthUser.fromJson(jsonDecode(raw));
        if (u != null && isGmail(u.email)) {
          _user = u;
          // People who were already signed in count as signed up, so they
          // can log back in after signing out.
          await _rememberRegistered(u.email);
          _server('signup', u.email); // best effort, not awaited
        }
      }
    } catch (_) {}
  }

  // ------------------------------------------------------------ registry
  // A Gmail address must sign up once before it can log in. The list of
  // signed-up addresses lives on the server (Worker + D1) when
  // AppConfig.feedBase is set, and is also remembered on this phone so
  // people who already signed up can still log in offline.

  static String _norm(String email) =>
      email.trim().toLowerCase().replaceAll('@googlemail.com', '@gmail.com');

  Future<Set<String>> _localRegistry() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_kRegistered);
      if (raw != null) {
        return (jsonDecode(raw) as List).map((e) => '$e').toSet();
      }
    } catch (_) {}
    return <String>{};
  }

  Future<void> _rememberRegistered(String email) async {
    try {
      final set = await _localRegistry()..add(_norm(email));
      await (await SharedPreferences.getInstance())
          .setString(_kRegistered, jsonEncode(set.toList()));
    } catch (_) {}
  }

  /// Calls the Worker. Returns (status, error-code-from-body), or null when
  /// the Worker cannot be reached at all.
  Future<(int, String)?> _server(String path, String email) async {
    final base = AppConfig.feedBase.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) return null;
    try {
      final res = await http
          .post(
            Uri.parse('$base/auth/$path'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'email': _norm(email)}),
          )
          .timeout(const Duration(seconds: 12));
      var err = '';
      try {
        final j = jsonDecode(res.body);
        if (j is Map && j['error'] != null) err = '${j['error']}';
      } catch (_) {}
      return (res.statusCode, err);
    } catch (_) {
      return null;
    }
  }

  /// True when the server answered but has no accounts feature (an older
  /// Worker without /auth routes, or one without its database yet). The app
  /// then keeps the registry on this phone instead of failing.
  bool _serverLacksAccounts((int, String) r) =>
      r.$1 == 503 ||
      r.$1 == 405 ||
      (r.$1 == 404 && r.$2 != 'not_registered');

  /// Sign up: register the address. Log in: it must already be registered.
  /// Returns [SignInResult.ok] when the person may continue.
  Future<SignInResult> _gate(String email, {required bool signup}) async {
    final hasServer = AppConfig.feedBase.trim().isNotEmpty;

    if (signup) {
      if (hasServer) {
        final r = await _server('signup', email);
        if (r == null) return SignInResult.network;
        if (r.$1 == 200) {
          await _rememberRegistered(email);
          return SignInResult.ok;
        }
        if (!_serverLacksAccounts(r)) {
          return r.$1 == 400 ? SignInResult.notGmail : SignInResult.failed;
        }
      }
      await _rememberRegistered(email);
      return SignInResult.ok;
    }

    // Log in.
    if ((await _localRegistry()).contains(_norm(email))) return SignInResult.ok;
    if (hasServer) {
      final r = await _server('login', email);
      if (r == null) return SignInResult.network;
      if (r.$1 == 200) {
        await _rememberRegistered(email);
        return SignInResult.ok;
      }
      if (r.$1 == 404 && r.$2 == 'not_registered') {
        return SignInResult.notRegistered;
      }
      if (!_serverLacksAccounts(r)) {
        return r.$1 == 400 ? SignInResult.notGmail : SignInResult.failed;
      }
    }
    return SignInResult.notRegistered;
  }

  /// Opens the Google account picker. [signup] true = Sign up (registers the
  /// address), false = Log in (only for addresses that signed up before).
  Future<SignInResult> signIn({bool signup = false}) async {
    lastError = '';
    final started = DateTime.now();
    try {
      // Sign out first so the account picker always shows.
      try {
        await _google.signOut();
      } catch (_) {}
      final acc = await _google.signIn();
      if (acc == null) return _cancelled(started);
      if (!isGmail(acc.email)) {
        try {
          await _google.signOut();
        } catch (_) {}
        return SignInResult.notGmail;
      }
      final gate = await _gate(acc.email, signup: signup);
      if (gate != SignInResult.ok) {
        try {
          await _google.signOut();
        } catch (_) {}
        return gate;
      }
      await _save(AuthUser(
        email: acc.email,
        name: acc.displayName ?? acc.email.split('@').first,
        photoUrl: acc.photoUrl,
      ));
      return SignInResult.ok;
    } on PlatformException catch (e) {
      lastError = '${e.code} ${e.message ?? ''}'.trim();
      debugPrint('Google sign-in failed: $lastError');
      final m = lastError;
      if (m.contains('network_error') || m.contains('ApiException: 7')) {
        return SignInResult.network;
      }
      if (m.contains('sign_in_canceled') || m.contains('ApiException: 12501')) {
        return _cancelled(started);
      }
      // 10 = app not registered (package / SHA-1), 12500 = consent screen.
      if (m.contains('ApiException: 10') || m.contains('ApiException: 12500')) {
        return SignInResult.setupError;
      }
      return SignInResult.failed;
    } catch (e) {
      lastError = '$e';
      debugPrint('Google sign-in failed: $e');
      return SignInResult.failed;
    }
  }

  /// A "cancel" that comes back almost instantly is not a person closing the
  /// account picker: it is Google refusing this build (not set up yet).
  SignInResult _cancelled(DateTime started) {
    if (DateTime.now().difference(started) < const Duration(milliseconds: 1500)) {
      lastError = 'Closed immediately (Google sign-in not set up for this app)';
      return SignInResult.setupError;
    }
    return SignInResult.cancelled;
  }

  /// Fallback while Google sign-in is not set up: accepts a typed Gmail
  /// address. Only the format is checked, Google does not verify it.
  Future<SignInResult> signInManually(String email,
      {bool signup = false}) async {
    final e = email.trim().toLowerCase();
    if (!isGmail(e) || e.split('@').first.isEmpty) return SignInResult.notGmail;
    final gate = await _gate(e, signup: signup);
    if (gate != SignInResult.ok) return gate;
    await _save(AuthUser(email: e, name: e.split('@').first));
    return SignInResult.ok;
  }


  /// Short-lived Google ID token used by the community API. The Worker verifies
  /// this token with Google before accepting any post, comment, or like.
  Future<String?> googleIdToken() async {
    // Without a Web client ID the build can never get an ID token, so do not
    // wait for Google; the community uses this phone's key instead.
    if (AppConfig.googleServerClientId.isEmpty) return null;
    try {
      var account = _google.currentUser;
      account ??= await _google.signInSilently();
      if (account == null) return null;
      final auth = await account.authentication;
      final token = auth.idToken;
      return token != null && token.isNotEmpty ? token : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(AuthUser u) async {
    _user = u;
    try {
      (await SharedPreferences.getInstance())
          .setString(_kUser, jsonEncode(u.toJson()));
    } catch (_) {}
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      await _google.signOut();
    } catch (_) {}
    _user = null;
    try {
      (await SharedPreferences.getInstance()).remove(_kUser);
    } catch (_) {}
    notifyListeners();
  }
}
