import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../config.dart';
import '../theme/app_theme.dart';

/// How the support page ended.
enum SupportResult {
  /// The person waited for the countdown and tapped Skip Ad.
  completed,

  /// Closed by the person before the time was up (error screen only now).
  closed,

  /// The page could not be loaded (offline, dead link).
  failed,
}

/// In-app browser for the support page. It NEVER closes by itself: after the
/// page has loaded, [seconds] count down, then a "Skip Ad" button appears and
/// the person taps it to leave (pops [SupportResult.completed]). Until then
/// they can use the page normally and interact with the ad.
///
/// The countdown starts when the page has loaded (or after a short fallback
/// if the page never reports "loaded"), so a slow page doesn't eat the time.
class SupportBrowserScreen extends StatefulWidget {
  final String url;
  final int seconds;
  const SupportBrowserScreen({
    super.key,
    required this.url,
    required this.seconds,
  });

  @override
  State<SupportBrowserScreen> createState() => _SupportBrowserScreenState();
}

class _SupportBrowserScreenState extends State<SupportBrowserScreen> {
  late final WebViewController _wc;
  final ValueNotifier<double> _left = ValueNotifier<double>(-1); // secs; -1 = loading
  Timer? _tick;
  Timer? _fallback;
  bool _error = false;
  bool _done = false;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    _wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Ui.bg)
      ..setUserAgent(AppConfig.userAgent)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) => _route(r.url),
        onPageStarted: (_) {
          if (mounted && _error) setState(() => _error = false);
          _makeClickable();
        },
        onPageFinished: (_) {
          _makeClickable();
          _startCountdown();
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted && _end == null) {
            setState(() => _error = true);
          }
        },
      ));

    final p = _wc.platform;
    if (p is AndroidWebViewController) {
      final cookies = WebViewCookieManager().platform;
      if (cookies is AndroidWebViewCookieManager) {
        cookies.setAcceptThirdPartyCookies(p, true);
      }
    }
    _wc.loadRequest(Uri.parse(widget.url));

    // Some pages never fire "finished" (endless trackers): start anyway.
    _fallback = Timer(const Duration(seconds: 8), () {
      if (!_error) _startCountdown();
    });
  }

  /// Links that ask for a new tab / window (target=_blank, window.open) would
  /// otherwise do nothing inside the app, so open them in this same page.
  static const _clickFix = '''
(function(){
  if (window.__spFix) return; window.__spFix = true;
  window.open = function(u){ if (u) { location.href = u; } return window; };
  document.addEventListener('click', function(e){
    var a = e.target && e.target.closest ? e.target.closest('a[target]') : null;
    if (a && a.target !== '_self') { a.target = '_self'; }
  }, true);
})();
''';

  void _makeClickable() {
    try {
      _wc.runJavaScript(_clickFix);
    } catch (_) {}
  }

  /// Web links go through. App links (intent://, market://) are turned into
  /// their web page so tapping them still goes somewhere; the rest is ignored.
  NavigationDecision _route(String url) {
    final uri = Uri.tryParse(url);
    final scheme = uri?.scheme.toLowerCase() ?? '';
    if (scheme == 'http' ||
        scheme == 'https' ||
        scheme == 'about' ||
        scheme == 'data' ||
        scheme == 'blob') {
      return NavigationDecision.navigate;
    }
    String? web;
    if (scheme == 'intent') {
      final fb = RegExp(r'S\.browser_fallback_url=([^;]+)').firstMatch(url);
      if (fb != null) {
        web = Uri.decodeComponent(fb.group(1)!);
      } else {
        final sch = RegExp(r'scheme=(https?);').firstMatch(url)?.group(1);
        final body = url.substring('intent://'.length).split('#Intent').first;
        if (sch != null && body.isNotEmpty) web = '$sch://$body';
      }
    } else if (scheme == 'market') {
      final id = uri?.queryParameters['id'];
      if (id != null && id.isNotEmpty) {
        web = 'https://play.google.com/store/apps/details?id=$id';
      }
    }
    final target = web == null ? null : Uri.tryParse(web);
    if (target != null && (target.scheme == 'http' || target.scheme == 'https')) {
      _wc.loadRequest(target);
    }
    return NavigationDecision.prevent;
  }

  void _startCountdown() {
    if (_end != null || _done || !mounted || _error) return;
    _fallback?.cancel();
    _end = DateTime.now().add(Duration(seconds: widget.seconds));
    _left.value = widget.seconds.toDouble();
    _tick = Timer.periodic(const Duration(milliseconds: 100), (t) {
      final ms = _end!.difference(DateTime.now()).inMilliseconds;
      if (ms <= 0) {
        // Countdown over: Skip Ad is now available. Nothing closes by itself.
        t.cancel();
        _left.value = 0;
      } else {
        _left.value = ms / 1000;
      }
    });
  }

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(SupportResult.completed);
  }

  bool get _canSkip => _left.value == 0;

  /// Back / close: only once Skip Ad is available (or on the error screen).
  void _backOrClose() {
    if (_error) {
      _closeEarly();
    } else if (_canSkip) {
      _finish();
    }
  }

  void _closeEarly() {
    if (_done) return;
    _done = true;
    Navigator.of(context)
        .pop(_error ? SupportResult.failed : SupportResult.closed);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _fallback?.cancel();
    _left.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.seconds.toDouble();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backOrClose();
      },
      child: Scaffold(
        backgroundColor: Ui.bg,
        body: SafeArea(
          child: Column(
            children: [
              // ---- slim top bar with the countdown --------------------------
              Container(
                color: Ui.panel,
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 8),
                        Icon(Icons.favorite_rounded, size: 16, color: Ui.red),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Thank you for supporting Streambox',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                        ValueListenableBuilder<double>(
                          valueListenable: _left,
                          builder: (_, v, _) {
                            final ready = v == 0;
                            return Material(
                              color: ready
                                  ? Ui.red
                                  : Ui.red.withValues(alpha: .14),
                              shape: StadiumBorder(
                                side: BorderSide(
                                    color: Ui.red.withValues(alpha: .45)),
                              ),
                              child: InkWell(
                                customBorder: const StadiumBorder(),
                                onTap: ready ? _finish : null,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        v < 0
                                            ? 'Loading…'
                                            : (ready
                                                ? 'Skip Ad'
                                                : 'Skip in ${v.ceil()}'),
                                        style: TextStyle(
                                            color: ready
                                                ? Colors.white
                                                : Ui.redSoft,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w800),
                                      ),
                                      if (ready) ...[
                                        const SizedBox(width: 4),
                                        const Icon(Icons.skip_next_rounded,
                                            size: 18, color: Colors.white),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    ValueListenableBuilder<double>(
                      valueListenable: _left,
                      builder: (_, v, _) => ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          value: v < 0 ? null : 1 - (v / total).clamp(0.0, 1.0),
                          backgroundColor: Ui.line,
                          valueColor: AlwaysStoppedAnimation(Ui.red),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ---- the page --------------------------------------------------
              Expanded(
                child: _error
                    ? _ErrorView(
                        onRetry: () {
                          setState(() => _error = false);
                          _wc.loadRequest(Uri.parse(widget.url));
                        },
                        onClose: _closeEarly,
                      )
                    : WebViewWidget(controller: _wc),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onClose;
  const _ErrorView({required this.onRetry, required this.onClose});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 44, color: Ui.dim),
              const SizedBox(height: 12),
              const Text('The page could not load',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Check your internet connection and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Ui.muted, fontSize: 13)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                children: [
                  FilledButton(onPressed: onRetry, child: const Text('Retry')),
                  OutlinedButton(onPressed: onClose, child: const Text('Close')),
                ],
              ),
            ],
          ),
        ),
      );
}
