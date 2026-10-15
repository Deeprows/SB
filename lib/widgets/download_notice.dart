import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/l10n.dart';

/// Shown once, the first time a file downloads inside the app (instead of
/// through Android's own downloader). Returns true when the person taps
/// "View downloads".
Future<bool> showInAppDownloadNotice(BuildContext context) async {
  final view = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Ui.panel,
      icon: Icon(Icons.download_done_rounded, color: Ui.redSoft, size: 34),
      title: Text('Downloading inside the app'.tr),
      content: Text(
        'Your file is saved by DamiMovies itself. A notification shows the '
                'progress and it keeps going if you minimise the app or lock '
                'the screen. If you close the app completely it pauses, and '
                'you can tap retry in Downloads to continue. Finished videos '
                'play in the Downloads tab.'
            .tr,
        style: TextStyle(color: Ui.muted, height: 1.4),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false), child: Text('OK'.tr)),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('View downloads'.tr,
                style: TextStyle(color: Ui.redSoft))),
      ],
    ),
  );
  return view ?? false;
}
