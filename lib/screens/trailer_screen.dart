import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../models/movie_info.dart';
import '../theme/app_theme.dart';
import '../utils/l10n.dart';

/// Plays a TMDB trailer (a YouTube video) inside the app. Tapping the
/// thumbnails below switches to another video; "Open in YouTube" is the
/// fallback when a video refuses to play in an embed.
class TrailerScreen extends StatefulWidget {
  final String title;
  final List<Trailer> trailers;
  final int initial;
  const TrailerScreen({
    super.key,
    required this.title,
    required this.trailers,
    this.initial = 0,
  });

  @override
  State<TrailerScreen> createState() => _TrailerScreenState();
}

class _TrailerScreenState extends State<TrailerScreen> {
  late final WebViewController _wc;
  late int _i = widget.initial.clamp(0, widget.trailers.length - 1);
  bool _loading = true;

  Trailer get _t => widget.trailers[_i];

  @override
  void initState() {
    super.initState();
    _wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        // Keep the embed on YouTube's player; anything else is ignored.
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
    _play();
  }

  void _play() {
    setState(() => _loading = true);
    final k = _t.key;
    // The base URL gives YouTube a referrer, which its embed needs.
    _wc.loadHtmlString(
      '''<!doctype html><html><head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;height:100%;background:#000}iframe{border:0;width:100%;height:100%}</style>
</head><body>
<iframe src="https://www.youtube-nocookie.com/embed/$k?autoplay=1&playsinline=1&rel=0&modestbranding=1&fs=1"
 allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen></iframe>
</body></html>''',
      baseUrl: 'https://www.youtube-nocookie.com',
    );
  }

  Future<void> _openYoutube() async {
    try {
      await launchUrl(Uri.parse(_t.watchUrl),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Ui.bg,
      body: Column(
        children: [
          Container(
            color: Colors.black,
            padding: EdgeInsets.only(top: top),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  WebViewWidget(controller: _wc),
                  if (_loading)
                    Center(child: CircularProgressIndicator(color: Ui.red)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 12, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800)),
                      Text(_t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Ui.muted, fontSize: 12.5)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Open in YouTube'.tr,
                  onPressed: _openYoutube,
                  icon: const Icon(Icons.open_in_new_rounded),
                ),
              ],
            ),
          ),
          if (widget.trailers.length > 1) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('More videos'.tr,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: widget.trailers.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _VideoTile(
                  video: widget.trailers[i],
                  selected: i == _i,
                  onTap: () {
                    if (i == _i) return;
                    HapticFeedback.selectionClick();
                    setState(() => _i = i);
                    _play();
                  },
                ),
              ),
            ),
          ] else
            const Spacer(),
        ],
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  final Trailer video;
  final bool selected;
  final VoidCallback onTap;
  const _VideoTile(
      {required this.video, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected ? Ui.red.withValues(alpha: .14) : Ui.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? Ui.red.withValues(alpha: .7) : Ui.line),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 124,
                height: 70,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(video.thumbnail,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => ColoredBox(color: Ui.cardDeep)),
                    const Center(
                      child: Icon(Icons.play_circle_fill_rounded,
                          size: 30, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(video.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.25,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(video.type,
                      style: TextStyle(
                          color: selected ? Ui.redSoft : Ui.dim,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
