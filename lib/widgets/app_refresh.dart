import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Pull-to-refresh used on every list screen.
///
/// * the spinner appears BELOW the status bar (it used to hide under it, so a
///   pull looked like it did nothing)
/// * works from anywhere in the list, not only at the very top edge
/// * when finished it says whether fresh content was downloaded
class AppRefresh extends StatelessWidget {
  /// Returns true when fresh content was downloaded, false when the server
  /// could not be reached (saved content is shown instead).
  final Future<bool> Function() onRefresh;
  final Widget child;
  const AppRefresh({super.key, required this.onRefresh, required this.child});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: Ui.red,
      backgroundColor: Ui.panel,
      displacement: 44,
      edgeOffset: MediaQuery.of(context).padding.top,
      triggerMode: RefreshIndicatorTriggerMode.anywhere,
      onRefresh: () async {
        var ok = true;
        try {
          ok = await onRefresh();
        } catch (_) {
          ok = false;
        }
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(milliseconds: 1800),
            content: Text(ok
                ? 'Updated'
                : "Couldn't reach the server. Showing saved content."),
          ));
      },
      child: child,
    );
  }
}
