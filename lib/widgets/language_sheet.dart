import 'package:flutter/material.dart';

import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../utils/l10n.dart';

/// Language picker opened from the drawer menu.
Future<void> showLanguageSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Ui.panel,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: ValueListenableBuilder<String>(
        valueListenable: AppLocale.notifier,
        builder: (_, _, _) {
          Widget tile(String value, String title, String? subtitle) {
            final selected = AppLocale.choice == value;
            return ListTile(
              title: Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              subtitle: subtitle == null
                  ? null
                  : Text(subtitle,
                      style: TextStyle(color: Ui.muted, fontSize: 12)),
              trailing: selected
                  ? Icon(Icons.check_circle_rounded, color: Ui.red)
                  : null,
              onTap: () async {
                await AppLocale.set(value);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('Choose language'.tr,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900)),
                ),
                tile(AppLocale.auto, 'Automatic (phone language)'.tr, null),
                for (final l in AppLocale.supported)
                  tile(l.code, l.native, l.english),
              ],
            ),
          );
        },
      ),
    ),
  );
}
