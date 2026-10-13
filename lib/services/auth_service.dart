import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
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

enum SignInResult { ok, cancelled, notGmail, setupError, network, failed }

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
        if (u != null && isGmail(u.email)) _user = u;
      }
    } catch (_) {}
  }

  /// Opens the Google account picker. Returns what happened.
  Future<SignInResult> signIn() async {
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
  Future<bool> signInManually(String email) async {
    final e = email.trim().toLowerCase();
    if (!isGmail(e) || e.split('@').first.isEmpty) return false;
    await _save(AuthUser(email: e, name: e.split('@').first));
    return true;
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
