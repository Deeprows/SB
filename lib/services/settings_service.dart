import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SavedPlaylist {
  final String name;
  final String url;
  const SavedPlaylist(this.name, this.url);

  Map<String, String> toJson() => {'name': name, 'url': url};
}

/// Small wrapper over SharedPreferences for the drawer menu settings.
class Settings {
  static const _kLow = 'footbolive_force_low_quality';
  static const _kFloat = 'footbolive_floating_player';
  static const _kCopyright = 'footbolive_copyright_seen';
  static const _kTheme = 'footbolive_theme';
  static const _kPlaylists = 'footbolive_playlists';
  static const _kChatName = 'deeprowss_chat_username';

  static Future<int> themeIndex() async =>
      (await SharedPreferences.getInstance()).getInt(_kTheme) ?? 0;
  static Future<void> setThemeIndex(int v) async =>
      (await SharedPreferences.getInstance()).setInt(_kTheme, v);

  static Future<bool> forceLowQuality() async =>
      (await SharedPreferences.getInstance()).getBool(_kLow) ?? false;
  static Future<void> setForceLowQuality(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_kLow, v);

  static Future<bool> floatingPlayer() async =>
      (await SharedPreferences.getInstance()).getBool(_kFloat) ?? false;
  static Future<void> setFloatingPlayer(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_kFloat, v);

  static Future<String> chatName() async =>
      (await SharedPreferences.getInstance()).getString(_kChatName) ?? '';
  static Future<void> setChatName(String v) async =>
      (await SharedPreferences.getInstance()).setString(_kChatName, v);

  static Future<bool> copyrightSeen() async =>
      (await SharedPreferences.getInstance()).getBool(_kCopyright) ?? false;
  static Future<void> setCopyrightSeen() async =>
      (await SharedPreferences.getInstance()).setBool(_kCopyright, true);

  /// Playlist every install starts with. Users can delete it and add their own.
  static const defaultPlaylistName = 'Free-TV IPTV';
  static const defaultPlaylistUrl =
      'https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8';
  static const _kDefaultSeeded = 'footbolive_default_playlist_seeded';

  static Future<List<SavedPlaylist>> playlists() async {
    final prefs = await SharedPreferences.getInstance();
    var list = <SavedPlaylist>[];
    final raw = prefs.getString(_kPlaylists);
    if (raw != null) {
      try {
        list = (jsonDecode(raw) as List)
            .whereType<Map>()
            .map((m) => SavedPlaylist(
                (m['name'] ?? '').toString(), (m['url'] ?? '').toString()))
            .where((p) => p.url.isNotEmpty)
            .toList();
      } catch (_) {}
    }
    // Added once per install; after the user removes it, it stays removed.
    if (!(prefs.getBool(_kDefaultSeeded) ?? false)) {
      await prefs.setBool(_kDefaultSeeded, true);
      if (!list.any((p) => p.url == defaultPlaylistUrl)) {
        list = [const SavedPlaylist(defaultPlaylistName, defaultPlaylistUrl), ...list];
        await savePlaylists(list);
      }
    }
    return list;
  }

  static Future<void> savePlaylists(List<SavedPlaylist> list) async =>
      (await SharedPreferences.getInstance())
          .setString(_kPlaylists, jsonEncode(list.map((e) => e.toJson()).toList()));
}
