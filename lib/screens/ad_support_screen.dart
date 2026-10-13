import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../config.dart';
import '../services/ad_preloader.dart';
import '../services/remote_config.dart';
import '../theme/app_theme.dart';
import 'support_browser_screen.dart' show SupportResult;

/// YouTube-style ad page (first tap, then every few minutes of use).
///
///  1. The ad page is normally PRELOADED in the background shortly before it
///     is due ([AdPreloader]), so it appears instantly. If it is not ready yet
///     the screen shows "please wait" while it finishes loading; the ad is
///     never cut off while loading and Back is ignored.
///  2. Once loaded, the ad is shown with an "Ad" badge, a progress line and a
///     "Skip in N" button that turns into "Skip Ad" after
///     [RemoteConfig.instance.supportSkipAfterSeconds], exactly like YouTube.
///  3. The ad NEVER disappears by itself. It stays on screen until the person
///     taps Skip Ad, and they are back where they were.
///
/// If the person taps the ad, the button becomes "Continue".
///
/// Pops [SupportResult.completed] when it was shown, or
/// [SupportResult.failed] when it could not load at all (offline / dead link),
/// so nobody is ever locked out.
class AdSupportScreen extends StatefulWidget {
  final String url;

  /// Page loaded in the background by [AdPreloader] (null = load it here).
  final PreloadedAd? preloaded;
  const AdSupportScreen({super.key, required this.url, this.preloaded});

  @override
  State<AdSupportScreen> createState() => _AdSupportScreenState();
}

enum _Phase { loading, ready, error }

class _AdSupportScreenState extends State<AdSupportScreen> {
  late final WebViewController _wc;

  _Phase _phase = _Phase.loading;
  final ValueNotifier<int> _progress = ValueNotifier<int>(0);
  final ValueNotifier<double> _elapsed = ValueNotifier<double>(0);

  Timer? _settle; // waits a moment to be sure no redirect follows
  Timer? _maxLoad; // safety: a page that never says "finished"
  Timer? _tick;
  DateTime? _begin;

  bool _started = false; // the page has begun to load
  bool _everLoaded = false; // some page has finished loading at least once
  bool _forced = false; // max load time reached: stop going back to "loading"
  bool _done = false;
  bool _engaged = false; // the person tapped the ad: no automatic ending

  static const _settleDelay = Duration(milliseconds: 1400);

  @override
  void initState() {
    super.initState();
    final pre = widget.preloaded;
    _wc = pre?.controller ?? WebViewController();
    _wc
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Ui.bg)
      ..setUserAgent(AppConfig.userAgent)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) => _route(r.url),
        onPageStarted: (_) {
          _started = true;
          _makeClickable();
          _onNewPage();
        },
        onProgress: (p) {
          _progress.value = p;
          if (p >= 100) _scheduleSettle();
        },
        onPageFinished: (_) {
          _started = true;
          _makeClickable();
          _scheduleSettle();
        },
        onWebResourceError: (e) {
          // Only a failure of the page itself with nothing shown yet counts.
          if (e.isForMainFrame == true && !_everLoaded && mounted) {
            _fail();
          }
        },
      ));

    if (pre == null) {
      final p = _wc.platform;
      if (p is AndroidWebViewController) {
        final cookies = WebViewCookieManager().platform;
        if (cookies is AndroidWebViewCookieManager) {
          cookies.setAcceptThirdPartyCookies(p, true);
        }
      }
      _wc.loadRequest(Uri.parse(widget.url));
    } else {
      // Already loaded in the background: show it straight away.
      _started = true;
      _makeClickable();
      if (pre.finished) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _markLoaded());
      } else {
        _scheduleSettle(); // still finishing: the navigation events continue
      }
    }

    _armMaxLoad();
  }

  /// Safety net: a page that is still loading after
  /// [AppConfig.supportMaxLoadSeconds] is treated as loaded (if it showed
  /// anything) so it can never hold the person for ever.
  void _armMaxLoad() {
    _maxLoad?.cancel();
    _maxLoad = Timer(Duration(seconds: AppConfig.supportMaxLoadSeconds), () {
      if (_done || !mounted || _phase == _Phase.error) return;
      _forced = true;
      if (_phase == _Phase.loading) {
        if (_started) {
          _markLoaded();
        } else {
          _fail();
        }
      }
    });
  }

  // ------------------------------------------------------------ loading

  /// A page started loading. After the ad is showing this means the person
  /// tapped it (or it redirected): stop the automatic ending so they can look
  /// at it, they leave with the Continue button.
  void _onNewPage() {
    _settle?.cancel();
    if (_done || !mounted) return;
    if (_phase == _Phase.ready && !_engaged) {
      setState(() => _engaged = true);
    }
  }

  void _scheduleSettle() {
    if (_done || !mounted || _phase == _Phase.error) return;
    _settle?.cancel();
    _settle = Timer(_settleDelay, _markLoaded);
  }

  void _markLoaded() {
    if (_done || !mounted || _phase == _Phase.error) return;
    _everLoaded = true;
    _maxLoad?.cancel();
    if (_phase == _Phase.ready && _begin != null) return;
    setState(() => _phase = _Phase.ready);
    _startCountdown();
  }

  void _startCountdown() {
    _stopCountdown();
    _begin = DateTime.now();
    _elapsed.value = 0;
    _tick = Timer.periodic(const Duration(milliseconds: 100), (t) {
      final e = DateTime.now().difference(_begin!).inMilliseconds / 1000;
      _elapsed.value = e;
      // No automatic ending: the ad stays until the person taps Skip Ad.
      // Once the Skip button is available there is nothing left to count.
      if (e >= RemoteConfig.instance.supportSkipAfterSeconds) {
        t.cancel();
        _tick = null;
        _elapsed.value = e;
      }
    });
  }

  void _stopCountdown() {
    _tick?.cancel();
    _tick = null;
    _begin = null;
  }

  void _fail() {
    if (_done || !mounted) return;
    _stopCountdown();
    _settle?.cancel();
    setState(() => _phase = _Phase.error);
  }

  // ------------------------------------------------------------- closing

  /// Skip Ad / Continue tapped, or the ad ended: back to what the person was
  /// doing.
  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(SupportResult.completed);
  }

  /// The page could not load at all: let the person through.
  void _continueAnyway() {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(SupportResult.failed);
  }

  void _retry() {
    _started = false;
    _everLoaded = false;
    _forced = false;
    _engaged = false;
    _progress.value = 0;
    setState(() => _phase = _Phase.loading);
    _armMaxLoad();
    _wc.loadRequest(Uri.parse(widget.url));
  }

  @override
  void dispose() {
    _settle?.cancel();
    _maxLoad?.cancel();
    _tick?.cancel();
    _progress.dispose();
    _elapsed.dispose();
    // Stop the ad's sound / scripts now that it is closed.
    try {
      _wc.loadRequest(Uri.parse('about:blank'));
    } catch (_) {}
    super.dispose();
  }

  // ----------------------------------------------------------- web page

  /// Links that ask for a new tab / window would otherwise do nothing inside
  /// the app, so open them in this same page.
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

  // ---------------------------------------------------------------- UI

  bool get _canSkip =>
      _phase == _Phase.ready &&
      _elapsed.value >= RemoteConfig.instance.supportSkipAfterSeconds;

  static const _yellow = Color(0xFFFFCC00);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back is ignored while the ad is loading / before Skip is available.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_phase == _Phase.ready && _canSkip) _finish();
        if (_phase == _Phase.error) _continueAnyway();
      },
      child: Scaffold(
        backgroundColor: Ui.bg,
        body: SafeArea(
          child: Column(
            children: [
              _bar(),
              Expanded(
                child: _phase == _Phase.error
                    ? _ErrorView(onRetry: _retry, onContinue: _continueAnyway)
                    : Stack(
                        children: [
                          Positioned.fill(child: WebViewWidget(controller: _wc)),
                          // While the ad is still loading, hide the half-built
                          // page and show a wait message instead.
                          Positioned.fill(
                            child: IgnorePointer(
                              ignoring: _phase != _Phase.loading,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 250),
                                opacity: _phase == _Phase.loading ? 1 : 0,
                                child: Container(
                                  color: Ui.bg,
                                  alignment: Alignment.center,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 30,
                                        height: 30,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 3, color: Ui.red),
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        AppConfig.supportWaitText,
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_phase == _Phase.ready)
                            Positioned(
                              right: 0,
                              bottom: 22,
                              child: _skipButton(),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// YouTube's "Skip in 5" -> "Skip Ad" button.
  Widget _skipButton() {
    return ValueListenableBuilder<double>(
      valueListenable: _elapsed,
      builder: (_, e, _) {
        final wait = RemoteConfig.instance.supportSkipAfterSeconds - e;
        final ready = wait <= 0;
        return Material(
          color: Colors.black.withValues(alpha: .78),
          shape: const RoundedRectangleBorder(
            side: BorderSide(color: Colors.white70, width: 1),
            borderRadius: BorderRadius.horizontal(left: Radius.circular(4)),
          ),
          child: InkWell(
            onTap: ready ? _finish : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 11, 14, 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ready
                        ? (_engaged ? 'Continue' : 'Skip Ad')
                        : 'Skip in ${wait.ceil()}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: ready ? Colors.white : Colors.white60,
                    ),
                  ),
                  if (ready) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.skip_next_rounded,
                        size: 22, color: Colors.white),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _bar() {
    final loading = _phase != _Phase.ready;
    return Container(
      color: Ui.panel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _yellow,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text('Ad',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.w900)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: loading
                      ? Text(
                          AppConfig.supportWaitText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w800),
                        )
                      : ValueListenableBuilder<double>(
                          valueListenable: _elapsed,
                          builder: (_, e, _) {
                            final ready =
                                e >= RemoteConfig.instance.supportSkipAfterSeconds;
                            return Text(
                              _engaged
                                  ? 'Ad · tap Continue when you are done'
                                  : (ready
                                      ? 'Ad · tap Skip Ad to continue'
                                      : 'Ad'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13.5, fontWeight: FontWeight.w800),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          // Loading: page progress. Showing: yellow ad-progress line.
          loading
              ? ValueListenableBuilder<int>(
                  valueListenable: _progress,
                  builder: (_, p, _) => LinearProgressIndicator(
                    minHeight: 3,
                    value: p <= 0 ? null : p / 100,
                    backgroundColor: Ui.line,
                    valueColor: AlwaysStoppedAnimation(Ui.red),
                  ),
                )
              : ValueListenableBuilder<double>(
                  valueListenable: _elapsed,
                  builder: (_, e, _) => LinearProgressIndicator(
                    minHeight: 3,
                    value: _engaged
                        ? 1.0
                        : (e / RemoteConfig.instance.supportSkipAfterSeconds)
                            .clamp(0.0, 1.0)
                            .toDouble(),
                    backgroundColor: Ui.line,
                    valueColor: const AlwaysStoppedAnimation(_yellow),
                  ),
                ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onContinue;
  const _ErrorView({required this.onRetry, required this.onContinue});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 44, color: Ui.dim),
              const SizedBox(height: 12),
              const Text('The ad page could not load',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Check your internet connection, or continue without it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Ui.muted, fontSize: 13)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                children: [
                  FilledButton(onPressed: onRetry, child: const Text('Retry')),
                  OutlinedButton(
                      onPressed: onContinue, child: const Text('Continue')),
                ],
              ),
            ],
          ),
        ),
      );
}
