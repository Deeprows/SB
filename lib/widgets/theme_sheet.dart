import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/l10n.dart';

Future<void> showThemeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Ui.panel,
    // Lets the sheet grow to the screen height; the list scrolls inside it.
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: ValueListenableBuilder<int>(
        valueListenable: ThemeController.index,
        builder: (_, selected, _) => SingleChildScrollView(
          // Extra room at the bottom so the phone's navigation bar never
          // covers the last theme.
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose a theme'.tr,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 14),
              for (var i = 0; i < Palettes.all.length; i++)
                _ThemeTile(
                  palette: Palettes.all[i],
                  selected: i == selected,
                  onTap: () => ThemeController.set(i),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ThemeTile extends StatelessWidget {
  final Palette palette;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeTile(
      {required this.palette, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: palette.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: selected ? palette.accent : Colors.white12,
                  width: selected ? 2 : 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 44,
                  decoration: BoxDecoration(
                    color: palette.bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final c in [
                        palette.accent,
                        palette.accentSoft,
                        palette.panel
                      ])
                        Container(
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration:
                              BoxDecoration(color: c, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(palette.name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(palette.tagline,
                          style: TextStyle(
                              color: palette.muted, fontSize: 12)),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded, color: palette.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
