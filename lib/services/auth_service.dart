import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
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

enum SignInResult { ok, cancelled, notGmail, failed }

/// Gmail-only sign-in (Google Sign-In). No password, no Firebase.
/// The saved account is read at start-up, so people stay signed in and the
/// app still opens offline.
class AuthService extends ChangeNotifier {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _kUser = 'auth_user';

  final GoogleSignIn _google = GoogleSignIn(
    scopes: const ['email', 'profile'],
    serverClientId:
        AppConfig.googleServerClientId.isEmpty ? null : AppConfig.googleServerClientId,
  );

  AuthUser? _user;
  AuthUser? get user => _user;
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
        if (u != null && isGmail(u.email)) _user = u;
      }
    } catch (_) {}
  }

  /// Opens the Google account picker. Returns what happened.
  Future<SignInResult> signIn() async {
    try {
      // Sign out first so the account picker always shows.
      try {
        await _google.signOut();
      } catch (_) {}
      final acc = await _google.signIn();
      if (acc == null) return SignInResult.cancelled;
      if (!isGmail(acc.email)) {
        try {
          await _google.signOut();
        } catch (_) {}
        return SignInResult.notGmail;
      }
      _user = AuthUser(
        email: acc.email,
        name: acc.displayName ?? acc.email.split('@').first,
        photoUrl: acc.photoUrl,
      );
      try {
        (await SharedPreferences.getInstance())
            .setString(_kUser, jsonEncode(_user!.toJson()));
      } catch (_) {}
      notifyListeners();
      return SignInResult.ok;
    } catch (e) {
      debugPrint('Google sign-in failed: $e');
      return SignInResult.failed;
    }
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
