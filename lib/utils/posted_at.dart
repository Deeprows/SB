/// When an item was posted, for "newest first" ordering.
///
/// Accepts a plain date ("2026-10-06"), a full timestamp in `date`
/// ("2026-10-06 14:30", "2026-10-06T14:30:00Z"), or a date plus a separate
/// `time` field ("14:30" or "14:30:15"). Returns null when unusable.
DateTime? parsePostedAt(String date, [String time = '']) {
  final d = date.trim();
  if (d.isEmpty) return null;
  var dt = DateTime.tryParse(d);
  if (dt == null) return null;
  final t = time.trim();
  if (t.isNotEmpty && d.length <= 10) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(t);
    if (m != null) {
      dt = DateTime(
        dt.year,
        dt.month,
        dt.day,
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3) ?? '0'),
      );
    }
  }
  return dt;
}

/// Stable "newest first" sort: later date/time first; items with the same
/// moment keep their order in the file (the newest entries sit at the top of
/// the JSON); items without a date go last.
List<T> newestFirst<T>(List<T> list, DateTime? Function(T item) dateOf) {
  final order = List<int>.generate(list.length, (i) => i);
  order.sort((a, b) {
    final da = dateOf(list[a]);
    final db = dateOf(list[b]);
    if (da == null && db == null) return a.compareTo(b);
    if (da == null) return 1;
    if (db == null) return -1;
    final c = db.compareTo(da);
    return c != 0 ? c : a.compareTo(b);
  });
  return [for (final i in order) list[i]];
}
