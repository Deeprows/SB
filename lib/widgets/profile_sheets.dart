import 'package:flutter/material.dart';

import '../models/movie.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../utils/l10n.dart';

/// One-line (or multi-line) text prompt. Returns null when cancelled.
Future<String?> askText(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  int maxLines = 1,
  int maxLength = 80,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextPrompt(
      title: title,
      initial: initial,
      hint: hint,
      maxLines: maxLines,
      maxLength: maxLength,
    ),
  );
}

class _TextPrompt extends StatefulWidget {
  final String title;
  final String initial;
  final String hint;
  final int maxLines;
  final int maxLength;
  const _TextPrompt({
    required this.title,
    required this.initial,
    required this.hint,
    required this.maxLines,
    required this.maxLength,
  });

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Ui.panel,
      title: Text(widget.title),
      content: TextField(
        controller: _c,
        autofocus: true,
        maxLines: widget.maxLines,
        minLines: widget.maxLines > 1 ? 3 : 1,
        maxLength: widget.maxLength,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('CANCEL'.tr)),
        TextButton(
            onPressed: () => Navigator.pop(context, _c.text),
            child: Text('SAVE'.tr, style: TextStyle(color: Ui.red))),
      ],
    );
  }
}

/// "Add to list": tick the lists the title should be in, or make a new one.
Future<void> showAddToListSheet(BuildContext context, Movie m) async {
  final svc = ProfileService.instance;
  await svc.load();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Ui.panel,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => ListenableBuilder(
      listenable: svc,
      builder: (_, _) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheet).size.height * .7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                child: Text('Add to list'.tr,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w900)),
              ),
              ListTile(
                leading: Icon(Icons.add_rounded, color: Ui.red),
                title: Text('New list'.tr,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () async {
                  final name = await askText(sheet,
                      title: 'New list'.tr, hint: 'List name'.tr);
                  if (name == null || name.trim().isEmpty) return;
                  final l = await svc.createList(name);
                  await svc.toggleInList(l, m);
                },
              ),
              for (final l in svc.lists)
                CheckboxListTile(
                  value: svc.inList(l, m),
                  activeColor: Ui.red,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(l.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${l.movies.length}',
                      style: TextStyle(color: Ui.muted, fontSize: 12)),
                  onChanged: (_) => svc.toggleInList(l, m),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Write, change or clear your review of a title.
Future<void> showReviewDialog(BuildContext context, Movie m) async {
  final svc = ProfileService.instance;
  await svc.load();
  if (!context.mounted) return;
  final text = await askText(
    context,
    title: 'Your review'.tr,
    initial: svc.reviewFor(m)?.text ?? '',
    hint: 'What did you think?'.tr,
    maxLines: 6,
    maxLength: 800,
  );
  if (text == null) return;
  await svc.saveReview(m, text);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(text.trim().isEmpty
            ? 'Review removed'.tr
            : 'Review saved'.tr)));
}

/// Marks that you are watching this title now.
Future<void> doCheckIn(BuildContext context, Movie m) async {
  await ProfileService.instance.checkIn(m);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 2),
        content: Text('Checked in'.tr)));
}
