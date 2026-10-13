import 'dart:async';

import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../config.dart';
import 'remote_config.dart';

/// An ad page that was loaded in the background and is ready to be shown.
class PreloadedAd {
  final WebViewController controller;

  /// True when the page (redirects included) had finished loading already.
  final bool finished;
  const PreloadedAd(this.controller, this.finished);
}

/// Loads [AppConfig.supportUrl] in the background shortly BEFORE an ad is due,
/// like YouTube does, so that when the ad time comes the page is already
/// loaded and appears straight away instead of making the person wait.
///
///  * [warmUp] is safe to call often: it does nothing while a fresh copy is
///    already loading / loaded.
///  * [take] hands the loaded page to the ad screen (and forgets it, so the
///    next ad gets a new page).
///  * A copy older than [AppConfig.adPreloadMaxAgeSeconds] is thrown away and
///    loaded again, so the ad is never stale.
///
/// The caller decides whether ads are on at all (free plan, url set).
class AdPreloader {
  AdPreloader._();
  static final AdPreloader instance = AdPreloader._();

  static const _settleDelay = Duration(milliseconds: 1400);

  WebViewController? _wc;
  String? _loadedUrl;
  DateTime? _startedAt;
  bool _finished = false;
  bool _failed = false;
  Timer? _settle;

  bool get isReady => _wc != null && _finished && !_failed && !_isStale;

  bool get _isStale {
    final t = _startedAt;
    if (t == null) return true;
    return DateTime.now().difference(t).inSeconds >
        AppConfig.adPreloadMaxAgeSeconds;
  }

  /// Starts loading the ad page in the background (if not already done).
  void warmUp() {
    final url = RemoteConfig.instance.supportUrl;
    if (url.trim().isEmpty) return;
    // The link was changed in app_config.json: drop the old preloaded page.
    if (_wc != null && _loadedUrl != url) _discard();
    if (_wc != null && !_failed && !_isStale) return;
    _discard();

    final wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(AppConfig.userAgent)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) {
          final s = (Uri.tryParse(r.url)?.scheme ?? '').toLowerCase();
          const ok = {'http', 'https', 'about', 'data', 'blob'};
          return ok.contains(s)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
        onPageStarted: (_) {
          _settle?.cancel();
          _finished = false;
        },
        onProgress: (p) {
          if (p >= 100) _scheduleSettle();
        },
        onPageFinished: (_) => _scheduleSettle(),
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && !_finished) _failed = true;
        },
      ));

    final p = wc.platform;
    if (p is AndroidWebViewController) {
      final cookies = WebViewCookieManager().platform;
      if (cookies is AndroidWebViewCookieManager) {
        cookies.setAcceptThirdPartyCookies(p, true);
      }
    }

    _wc = wc;
    _startedAt = DateTime.now();
    try {
      _loadedUrl = url;
      unawaited(wc.loadRequest(Uri.parse(url)));
    } catch (_) {
      _failed = true;
    }
  }

  void _scheduleSettle() {
    _settle?.cancel();
    _settle = Timer(_settleDelay, () => _finished = true);
  }

  /// Gives the background page to the ad screen. Null = nothing usable, the
  /// ad screen then loads the page itself (the old behaviour).
  PreloadedAd? take() {
    final wc = _wc;
    if (wc == null ||
        _failed ||
        _isStale ||
        _loadedUrl != RemoteConfig.instance.supportUrl) {
      _discard();
      return null;
    }
    final ad = PreloadedAd(wc, _finished);
    _settle?.cancel();
    _wc = null;
    _startedAt = null;
    _finished = false;
    _failed = false;
    return ad;
  }

  void _discard() {
    _settle?.cancel();
    final wc = _wc;
    _wc = null;
    _startedAt = null;
    _finished = false;
    _failed = false;
    if (wc != null) {
      try {
        unawaited(wc.loadRequest(Uri.parse('about:blank')));
      } catch (_) {}
    }
  }
}
