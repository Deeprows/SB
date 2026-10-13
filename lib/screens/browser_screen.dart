import 'package:flutter/material.dart';

import '../services/download_manager.dart';
import '../theme/app_theme.dart';
import '../utils/l10n.dart';
import 'browser_screen.dart';
import 'downloads_screen.dart';

/// The Browse tab: type a web address or a search and it opens in the in-app
/// browser. Files that a page hands over (mkv, mp4, zip, apk, pdf...) are
/// saved by the in-app download manager, so nothing leaves Streambox.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  /// A web address opens as it is; anything else becomes a web search.
  static String resolveInput(String raw) => _BrowseScreenState.resolveInput(raw);

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final _input = TextEditingController();

  static const _shortcuts = <(String, IconData, String)>[
    ('IMDb', Icons.star_rounded, 'https://www.imdb.com'),
    ('TMDB', Icons.movie_filter_rounded, 'https://www.themoviedb.org'),
    ('Rotten Tomatoes', Icons.local_movies_rounded,
        'https://www.rottentomatoes.com'),
    ('YouTube Trailers', Icons.smart_display_rounded,
        'https://www.youtube.com/results?search_query=official+trailer'),
    ('Wikipedia', Icons.menu_book_rounded, 'https://www.wikipedia.org'),
    ('Google', Icons.search_rounded, 'https://www.google.com'),
  ];

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// A web address opens as it is; anything else becomes a web search.
  static String resolveInput(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(t);
    if (hasScheme) return t;
    final looksLikeHost = !t.contains(' ') && t.contains('.');
    if (looksLikeHost) return 'https://$t';
    return 'https://www.google.com/search?q=${Uri.encodeQueryComponent(t)}';
  }

  void _go([String? url]) {
    final target = url ?? resolveInput(_input.text);
    if (target.isEmpty) return;
    FocusScope.of(context).unfocus();
    openInApp(context, target);
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, top + 18, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Browser'.tr,
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w900)),
            ),
            ListenableBuilder(
              listenable: DownloadManager.instance,
              builder: (context, _) => IconButton(
                tooltip: 'Downloads',
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const DownloadsScreen())),
                icon: const Icon(Icons.download_rounded),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Browse the web and download files without leaving Streambox.'.tr,
            style: TextStyle(color: Ui.muted, fontSize: 14, height: 1.3)),
        const SizedBox(height: 18),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Ui.red.withValues(alpha: .25),
                  blurRadius: 22,
                  offset: const Offset(0, 6)),
            ],
          ),
          child: TextField(
            controller: _input,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _go(),
            decoration: InputDecoration(
              hintText: 'Search or type a web address'.tr,
              hintStyle: TextStyle(color: Ui.dim),
              prefixIcon: Icon(Icons.public_rounded, color: Ui.muted),
              suffixIcon: IconButton(
                icon: Icon(Icons.arrow_forward_rounded, color: Ui.red),
                onPressed: _go,
              ),
              filled: true,
              fillColor: Ui.card,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Ui.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Ui.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Ui.red.withValues(alpha: .8)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text('Quick links'.tr,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.05,
          children: [
            for (final s in _shortcuts)
              Material(
                color: Ui.card,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _go(s.$3),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Ui.line),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(s.$2, color: Ui.redSoft, size: 28),
                        const SizedBox(height: 8),
                        Text(s.$1,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
