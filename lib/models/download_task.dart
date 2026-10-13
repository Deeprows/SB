enum DownloadStatus { downloading, paused, completed, failed }

class DownloadTask {
  /// Native downloader task id. It changes when a task is resumed or retried.
  String id;
  final String url;
  final String referer;
  String name;
  int percent; // 0..100, reported by the background downloader
  int? total; // bytes, from the server when it tells us
  DownloadStatus status;
  String? error;
  final DateTime createdAt;

  DownloadTask({
    required this.id,
    required this.url,
    required this.name,
    this.referer = '',
    this.percent = 0,
    this.total,
    this.status = DownloadStatus.downloading,
    this.error,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 0..1, or null (indeterminate) while nothing has been reported yet.
  double? get progress {
    if (status == DownloadStatus.completed) return 1;
    if (percent <= 0) return null;
    return (percent / 100).clamp(0.0, 1.0);
  }

  /// Approximate bytes done (needs the total size).
  int get received => total == null ? 0 : (total! * percent / 100).round();

  bool get active => status == DownloadStatus.downloading;

  String get extension {
    final i = name.lastIndexOf('.');
    return i < 0 ? '' : name.substring(i + 1).toLowerCase();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'referer': referer,
        'name': name,
        'percent': percent,
        'total': total,
        'status': status.name,
        'error': error,
        'createdAt': createdAt.toIso8601String(),
      };

  static DownloadTask? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final id = (raw['id'] ?? '').toString();
    final url = (raw['url'] ?? '').toString();
    if (id.isEmpty || url.isEmpty) return null;
    return DownloadTask(
      id: id,
      url: url,
      referer: (raw['referer'] ?? '').toString(),
      name: (raw['name'] ?? 'download').toString(),
      percent: (raw['percent'] as num?)?.toInt() ?? 0,
      total: (raw['total'] as num?)?.toInt(),
      status: DownloadStatus.values.firstWhere(
        (e) => e.name == raw['status'],
        orElse: () => DownloadStatus.failed,
      ),
      error: raw['error']?.toString(),
      createdAt: DateTime.tryParse((raw['createdAt'] ?? '').toString()),
    );
  }
}
