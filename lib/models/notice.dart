/// A message you can change without a new APK (assets/data/notice.json on
/// GitHub, see NOTICE.md).
///
///   {
///     "enabled": true,
///     "id": "update-1",            change it for every NEW notice
///     "title": "New version",
///     "message": "Version 1.1 is out.",
///     "popup": true,               true = pops up when the app opens (once per id)
///     "button_text": "Update now", optional button ...
///     "button_url": "https://...", ... that opens this link
///     "ok_text": "OK",             label of the close button
///     "expires": "2026-12-31"      optional, hidden after this date
///   }
///
/// A plain text file also works: the whole text becomes the message.
class Notice {
  final bool enabled;
  final String id;
  final String title;
  final String message;
  final bool popup;
  final String buttonText;
  final String buttonUrl;
  final String okText;

  const Notice({
    this.enabled = false,
    this.id = '',
    this.title = 'Notice',
    this.message = '',
    this.popup = true,
    this.buttonText = '',
    this.buttonUrl = '',
    this.okText = 'OK',
  });

  static const none = Notice();

  bool get visible => enabled && message.trim().isNotEmpty;

  bool get hasButton =>
      buttonText.trim().isNotEmpty && buttonUrl.trim().startsWith('http');

  /// Stable key used to remember that this notice was already shown.
  String get key => id.trim().isNotEmpty ? id.trim() : '$title|$message';

  static bool _bool(dynamic v, bool fallback) {
    if (v is bool) return v;
    if (v is String) return v.trim().toLowerCase() != 'false';
    return fallback;
  }

  static String _s(dynamic v, String fallback) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  static Notice parse(dynamic raw, {DateTime? now}) {
    if (raw is String) {
      final t = raw.trim();
      return t.isEmpty ? none : Notice(enabled: true, message: t);
    }
    if (raw is! Map) return none;

    final expires = DateTime.tryParse((raw['expires'] ?? '').toString());
    // "2026-12-31" counts until the end of that day.
    final expired = expires != null &&
        (now ?? DateTime.now()).isAfter(expires.add(const Duration(days: 1)));

    return Notice(
      enabled: _bool(raw['enabled'], true) && !expired,
      id: _s(raw['id'], ''),
      title: _s(raw['title'], 'Notice'),
      message: _s(raw['message'], ''),
      popup: _bool(raw['popup'], true),
      buttonText: _s(raw['button_text'], ''),
      buttonUrl: _s(raw['button_url'], ''),
      okText: _s(raw['ok_text'], 'OK'),
    );
  }
}
