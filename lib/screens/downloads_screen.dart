import 'package:flutter/material.dart';

import '../models/download_task.dart';
import '../services/download_manager.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'browser_screen.dart';

IconData _iconFor(String ext) {
  switch (ext) {
    case 'mp4':
    case 'mkv':
    case 'avi':
    case 'mov':
    case 'webm':
    case 'm4v':
      return Icons.movie_rounded;
    case 'mp3':
    case 'aac':
    case 'm4a':
      return Icons.music_note_rounded;
    case 'apk':
      return Icons.android_rounded;
    case 'zip':
    case 'rar':
    case '7z':
    case 'tar':
    case 'gz':
      return Icons.folder_zip_rounded;
    case 'pdf':
      return Icons.picture_as_pdf_rounded;
    default:
      return Icons.insert_drive_file_rounded;
  }
}

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final m = DownloadManager.instance;
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        final tasks = m.tasks;
        final hasDone =
            tasks.any((t) => t.status == DownloadStatus.completed);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Downloads',
                style: TextStyle(fontWeight: FontWeight.w900)),
            actions: [
              if (hasDone)
                IconButton(
                  tooltip: 'Clear finished',
                  onPressed: m.clearFinished,
                  icon: const Icon(Icons.done_all_rounded),
                ),
            ],
          ),
          body: tasks.isEmpty
              ? const _Empty()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: tasks.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    if (i == tasks.length) return const _Footnote();
                    return _TaskTile(task: tasks[i]);
                  },
                ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_for_offline_outlined,
                size: 52, color: Ui.dim),
            SizedBox(height: 12),
            Text('No downloads yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            SizedBox(height: 6),
            Text(
              'Open a movie, tap Download and use the download button on the page. Files show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Ui.muted, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 8),
      child: Text(
        'Downloads keep running in the background with a notification, even if you close the app, and are saved to your Downloads folder.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Ui.dim, fontSize: 11.5, height: 1.4),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final DownloadTask task;
  const _TaskTile({required this.task});

  DownloadManager get _m => DownloadManager.instance;

  Future<void> _open(BuildContext context) async {
    final ok = await _m.open(task.id);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Couldn\'t open it here. Find it in your Downloads folder.')));
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Ui.panel,
        title: const Text('Delete file?'),
        content: Text(task.name),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Delete', style: TextStyle(color: Ui.redSoft))),
        ],
      ),
    );
    if (ok == true) await _m.remove(task.id, deleteFile: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = task;
    final done = t.status == DownloadStatus.completed;
    final failed = t.status == DownloadStatus.failed;

    String subtitle;
    switch (t.status) {
      case DownloadStatus.downloading:
        subtitle = t.total != null
            ? '${fmtBytes(t.received)} of ${fmtBytes(t.total!)} · ${t.percent}%'
            : (t.percent > 0 ? '${t.percent}%' : 'Starting…');
      case DownloadStatus.paused:
        subtitle = t.percent > 0 ? 'Paused · ${t.percent}%' : 'Paused';
      case DownloadStatus.completed:
        subtitle = t.total != null
            ? '${fmtBytes(t.total!)} · Saved to Downloads'
            : 'Saved to Downloads';
      case DownloadStatus.failed:
        subtitle = t.error ?? 'Download failed';
    }

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Ui.card, Ui.cardDeep],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: failed
                ? Ui.red.withValues(alpha: .5)
                : t.active
                    ? Ui.red.withValues(alpha: .4)
                    : Ui.red.withValues(alpha: .18),
          ),
        ),
        child: InkWell(
          onTap: done ? () => _open(context) : null,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Ui.red.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Ui.red.withValues(alpha: .25)),
                  ),
                  child: Icon(_iconFor(t.extension),
                      color: Ui.redSoft, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              height: 1.2,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          maxLines: failed ? 3 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: failed ? Ui.redSoft : Ui.muted,
                              fontSize: 11.5,
                              height: 1.3,
                              fontWeight: FontWeight.w600)),
                      if (t.active || t.status == DownloadStatus.paused) ...[
                        const SizedBox(height: 7),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: t.progress,
                            minHeight: 4,
                            color: t.active ? Ui.red : Ui.dim,
                            backgroundColor: Colors.white12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ..._actions(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    final t = task;
    switch (t.status) {
      case DownloadStatus.downloading:
        return [
          IconButton(
              tooltip: 'Pause',
              onPressed: () => _m.pause(t.id),
              icon: const Icon(Icons.pause_rounded)),
          IconButton(
              tooltip: 'Cancel',
              onPressed: () => _m.cancel(t.id),
              icon: const Icon(Icons.close_rounded)),
        ];
      case DownloadStatus.paused:
        return [
          IconButton(
              tooltip: 'Resume',
              onPressed: () => _m.resume(t.id),
              icon: const Icon(Icons.play_arrow_rounded)),
          IconButton(
              tooltip: 'Cancel',
              onPressed: () => _m.cancel(t.id),
              icon: const Icon(Icons.close_rounded)),
        ];
      case DownloadStatus.failed:
        return [
          IconButton(
              tooltip: 'Retry',
              onPressed: () => _m.resume(t.id),
              icon: const Icon(Icons.refresh_rounded)),
          IconButton(
              tooltip: 'Open link in browser',
              onPressed: () => openExternally(t.url),
              icon: const Icon(Icons.public_rounded)),
          IconButton(
              tooltip: 'Remove',
              onPressed: () => _m.cancel(t.id),
              icon: const Icon(Icons.delete_outline_rounded)),
        ];
      case DownloadStatus.completed:
        return [
          PopupMenuButton<String>(
            color: Ui.panel,
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              if (v == 'open') _open(context);
              if (v == 'delete') _confirmDelete(context);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'open',
                child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.play_circle_outline_rounded),
                    title: Text('Open')),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline_rounded),
                    title: Text('Delete')),
              ),
            ],
          ),
        ];
    }
  }
}
