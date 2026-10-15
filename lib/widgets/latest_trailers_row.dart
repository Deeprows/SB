import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../models/movie.dart';
import '../models/trailer_item.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../utils/l10n.dart';
import 'trailer_popup.dart';

/// "Latest Trailers" on the home page, like TMDB: a row of trailer cards with
/// a drop-down (Popular, Streaming, On TV, For Rent, In Theaters).
///
///  * Hold a card (or hover it with a mouse) and the trailer plays on the
///    card, muted.
///  * Tap a card and the trailer opens in a popup and plays with sound. A
///    small "Watch movie now | Later" prompt appears over it: Watch movie now
///    opens the title's page (play, download...), Later hides the prompt and
///    the trailer keeps playing.
class LatestTrailersRow extends StatefulWidget {
  final void Function(Movie) onOpen;
  const LatestTrailersRow({super.key, required this.onOpen});

  @override
  State<LatestTrailersRow> createState() => _LatestTrailersRowState();
}

class _LatestTrailersRowState extends State<LatestTrailersRow> {
  static const _cardW = 268.0;
  static const _cardH = _cardW * 9 / 16;

  String _category = TmdbService.trailerCategories.first;
  List<TrailerItem> _items = const [];
  bool _loading = true;
  bool _hadItems = false; // once something loaded, keep the section visible
  String? _previewKey; // YouTube id of the card that is playing
  Timer? _previewTimer;
  Timer? _hoverTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _hoverTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final cat = _category;
    setState(() {
      _loading = true;
      _previewKey = null;
    });
    final items = await tmdb.latestTrailers(cat);
    if (!mounted || cat != _category) return;
    setState(() {
      _items = items;
      _loading = false;
      if (items.isNotEmpty) _hadItems = true;
    });
  }

  /// Starts (or stops, with null) the card preview. It stops by itself after
  /// a while so a forgotten preview doesn't keep playing out of sight.
  void _preview(String? key) {
    _previewTimer?.cancel();
    if (!mounted) return;
    setState(() => _previewKey = key);
    if (key != null) {
      _previewTimer = Timer(const Duration(seconds: 25), () {
        if (mounted) setState(() => _previewKey = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // No TMDB key, or TMDB can't be reached: no section at all.
    if (!TmdbService.enabled) return const SizedBox.shrink();
    if (!_loading && _items.isEmpty && !_hadItems) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Ui.redSoft, Ui.red],
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text('Latest Trailers'.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 18,
                        letterSpacing: -.2,
                        fontWeight: FontWeight.w800)),
              ),
              _filter(),
            ],
          ),
        ),
        SizedBox(
          height: _cardH + 70,
          child: NotificationListener<ScrollStartNotification>(
            onNotification: (_) {
              if (_previewKey != null) _preview(null);
              return false;
            },
            child: _loading
                ? ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                    itemCount: 3,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, _) => Container(
                      width: _cardW,
                      height: _cardH,
                      alignment: Alignment.topCenter,
                      child: Container(
                        height: _cardH,
                        decoration: BoxDecoration(
                          color: Ui.card,
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => _card(_items[i], showHint: i == 0),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _filter() {
    return PopupMenuButton<String>(
      color: Ui.panel,
      tooltip: '',
      onSelected: (c) {
        if (c == _category) return;
        setState(() => _category = c);
        _load();
      },
      itemBuilder: (_) => [
        for (final c in TmdbService.trailerCategories)
          PopupMenuItem(
            value: c,
            child: Text(c.tr,
                style: TextStyle(
                    fontWeight:
                        c == _category ? FontWeight.w900 : FontWeight.w600,
                    color: c == _category ? Ui.redSoft : null)),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 7, 8, 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Ui.glassLine),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_category.tr,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more_rounded, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _card(TrailerItem item, {required bool showHint}) {
    final key = item.trailer.key;
    final playing = _previewKey == key;
    return MouseRegion(
      onEnter: (_) {
        _hoverTimer?.cancel();
        _hoverTimer = Timer(const Duration(milliseconds: 450), () {
          if (mounted) _preview(key);
        });
      },
      onExit: (_) {
        _hoverTimer?.cancel();
        if (_previewKey == key) _preview(null);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _preview(null); // stop the muted card preview first
          showTrailerPopup(context, item, onWatch: widget.onOpen);
        },
        onLongPress: () => _preview(playing ? null : key),
        child: SizedBox(
          width: _cardW,
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: _cardH,
                  width: _cardW,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: item.backdrop,
                        fit: BoxFit.cover,
                        memCacheWidth: 600,
                        placeholder: (_, _) => ColoredBox(color: Ui.card),
                        errorWidget: (_, _, _) => CachedNetworkImage(
                          imageUrl: item.trailer.thumbnail,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => ColoredBox(color: Ui.card),
                        ),
                      ),
                      if (playing)
                        IgnorePointer(
                          child: _PreviewPlayer(
                              key: ValueKey(key), videoKey: key),
                        )
                      else
                        Center(
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: .45),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: .75),
                                  width: 1.5),
                            ),
                            child: const Icon(Icons.play_arrow_rounded,
                                size: 32, color: Colors.white),
                          ),
                        ),
                      if (playing)
                        Positioned(
                          left: 8,
                          top: 8,
                          child: _tag('Preview'.tr, Icons.volume_off_rounded),
                        )
                      else if (showHint)
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: _tag('Hold to preview'.tr,
                              Icons.touch_app_rounded),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Text(item.movie.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 1),
              Text(item.trailer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Ui.muted, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String text, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 4),
            Text(text,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

/// A muted, looping YouTube preview that fills its card. It is shown over the
/// card picture and fades in once the page has loaded.
class _PreviewPlayer extends StatefulWidget {
  final String videoKey;
  const _PreviewPlayer({super.key, required this.videoKey});

  @override
  State<_PreviewPlayer> createState() => _PreviewPlayerState();
}

class _PreviewPlayerState extends State<_PreviewPlayer> {
  late final WebViewController _wc;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          // YouTube needs a moment to start; show the picture until then.
          Future<void>.delayed(const Duration(milliseconds: 900), () {
            if (mounted) setState(() => _ready = true);
          });
        },
        // Keep the preview on YouTube's player; anything else is ignored.
        onNavigationRequest: (r) {
          final host = Uri.tryParse(r.url)?.host ?? '';
          final ok = r.url == 'about:blank' ||
              host.endsWith('youtube-nocookie.com') ||
              host.endsWith('youtube.com') ||
              host.endsWith('ytimg.com') ||
              host.endsWith('google.com') ||
              host.endsWith('gstatic.com');
          return ok ? NavigationDecision.navigate : NavigationDecision.prevent;
        },
      ));
    final p = _wc.platform;
    if (p is AndroidWebViewController) {
      p.setMediaPlaybackRequiresUserGesture(false);
    }
    final k = widget.videoKey;
    _wc.loadHtmlString(
      '''<!doctype html><html><head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}iframe{border:0;width:100%;height:100%}</style>
</head><body>
<iframe src="https://www.youtube-nocookie.com/embed/$k?autoplay=1&mute=1&controls=0&loop=1&playlist=$k&playsinline=1&rel=0&modestbranding=1&disablekb=1&fs=0&iv_load_policy=3"
 allow="autoplay; encrypted-media" allowfullscreen></iframe>
</body></html>''',
      baseUrl: 'https://www.youtube-nocookie.com',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: _ready ? 1 : 0,
      child: WebViewWidget(controller: _wc),
    );
  }
}
