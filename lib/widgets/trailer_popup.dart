import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../models/movie.dart';
import '../models/trailer_item.dart';
import '../theme/app_theme.dart';
import '../utils/l10n.dart';

/// Opens a trailer in a popup and starts playing it. A moment later a small
/// "Watch movie now | Later" prompt slides up over the video:
///  * Watch movie now -> the popup closes and [onWatch] opens the movie page.
///  * Later           -> the prompt goes away and the trailer plays on.
Future<void> showTrailerPopup(
  BuildContext context,
  TrailerItem item, {
  required void Function(Movie) onWatch,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .86),
    builder: (ctx) => _TrailerPopup(
      item: item,
      onWatch: (m) {
        Navigator.of(ctx).pop();
        onWatch(m);
      },
    ),
  );
}

class _TrailerPopup extends StatefulWidget {
  final TrailerItem item;
  final void Function(Movie) onWatch;
  const _TrailerPopup({required this.item, required this.onWatch});

  @override
  State<_TrailerPopup> createState() => _TrailerPopupState();
}

class _TrailerPopupState extends State<_TrailerPopup> {
  late final WebViewController _wc;
  Timer? _promptTimer;
  bool _loading = true;
  bool _promptVisible = false; // fades in after a short moment
  bool _dismissed = false; // "Later" was tapped: never show it again

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
        // Keep the popup on YouTube's player; anything else is ignored.
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
    final k = widget.item.trailer.key;
    // The base URL gives YouTube a referrer, which its embed needs.
    _wc.loadHtmlString(
      '''<!doctype html><html><head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}iframe{border:0;width:100%;height:100%}</style>
</head><body>
<iframe src="https://www.youtube-nocookie.com/embed/$k?autoplay=1&playsinline=1&rel=0&modestbranding=1&fs=1"
 allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen></iframe>
</body></html>''',
      baseUrl: 'https://www.youtube-nocookie.com',
    );
    _promptTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted && !_dismissed) setState(() => _promptVisible = true);
    });
  }

  @override
  void dispose() {
    _promptTimer?.cancel();
    super.dispose();
  }

  void _later() {
    setState(() {
      _dismissed = true;
      _promptVisible = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Dialog(
      backgroundColor: Ui.panel,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.movie.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                      Text(item.trailer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Ui.muted, fontSize: 12.5)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close'.tr,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                WebViewWidget(controller: _wc),
                if (_loading)
                  Center(child: CircularProgressIndicator(color: Ui.red)),
                if (!_dismissed)
                  Positioned(
                    left: 10,
                    right: 10,
                    // above YouTube's own control bar
                    bottom: 54,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      offset: _promptVisible ? Offset.zero : const Offset(0, .6),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 280),
                        opacity: _promptVisible ? 1 : 0,
                        child: IgnorePointer(
                          ignoring: !_promptVisible,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: _prompt(item),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// "Watch movie now | Later"
  Widget _prompt(TrailerItem item) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Ui.glassLine),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Ui.red,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => widget.onWatch(item.movie),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow_rounded,
                        size: 20, color: Ui.palette.onAccent),
                    const SizedBox(width: 4),
                    Text('Watch movie now'.tr,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Ui.palette.onAccent)),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: 1,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: Colors.white.withValues(alpha: .25),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: _later,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text('Later'.tr,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
