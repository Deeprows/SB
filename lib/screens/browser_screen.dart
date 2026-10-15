import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../config.dart';
import '../services/ad_shield.dart';
import '../services/download_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/download_notice.dart';
import '../widgets/glass.dart';
import 'downloads_screen.dart';

/// File links (apk, zip, mkv…) can't be saved by a WebView, so when a page
/// redirects to one it is downloaded by the in-app download manager.
final _fileLink = RegExp(
  r'\.(apk|zip|rar|7z|tar|gz|iso|exe|msi|dmg|torrent|mkv|mp4|avi|mov|m4v|webm|mp3|pdf)$',
  caseSensitive: false,
);

bool isDirectFileLink(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  if (_fileLink.hasMatch(uri.path)) return true;
  // e.g. /get.php?file=movie.mkv
  for (final v in uri.queryParameters.values) {
    if (_fileLink.hasMatch(v)) return true;
  }
  return false;
}

/// Site key used to tell "same website" from "somewhere else":
/// cdn.example.com and www.example.com -> example.com.
String siteOf(String host) {
  final parts = host.toLowerCase().split('.');
  if (parts.length <= 2) return parts.join('.');
  final tld = parts.last;
  final sld = parts[parts.length - 2];
  final keep = (tld.length == 2 &&
          const {'co', 'com', 'org', 'net', 'gov', 'ac', 'edu'}.contains(sld))
      ? 3
      : 2;
  return parts.sublist(parts.length - keep).join('.');
}

Future<bool> openExternally(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Opens [url] in the in-app browser window. Many file hosts serve a landing
/// page even when the address ends in .mkv, so the first load always happens
/// in-app; file redirects that happen afterwards are downloaded in-app.
///
/// With [blockAds] on (download pages), the page may not send you to another
/// website by itself: pop-ups and click-redirects to ad sites are blocked and
/// a snackbar offers an ALLOW button in case the redirect was legitimate.
Future<void> openInApp(BuildContext context, String url,
    {String? title, bool blockAds = false}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => BrowserScreen(url: url, title: title, blockAds: blockAds),
  ));
}

/// Clean in-app browser window: slim top bar with page title and host,
/// progress line, back/reload/menu. Pop-up windows and app-scheme redirects
/// (intent://, market://…) are blocked.
class BrowserScreen extends StatefulWidget {
  final String url;
  final String? title;
  final bool blockAds;
  const BrowserScreen(
      {super.key, required this.url, this.title, this.blockAds = false});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late final WebViewController _wc;
  int _progress = 0;
  bool _canGoBack = false;
  bool _error = false;
  String _url = '';
  String _pageTitle = '';

  // Video files found on the page (video tags, direct links) are offered
  // with a Download button so they can be saved by the in-app downloader.
  final List<String> _found = [];
  Timer? _sniffTimer;
  int _sniffRuns = 0;

  // Ad-redirect blocking.
  bool _blockOn = true;
  bool _firstLoadDone = false;
  final Set<String> _allowedSites = {};
  final Set<String> _checked = {};
  final Set<String> _notedSites = {};

  @override
  void initState() {
    super.initState();
    _url = widget.url;
    _allowedSites.add(siteOf(Uri.tryParse(widget.url)?.host ?? ''));

    _wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Ui.bg)
      ..setUserAgent(AppConfig.userAgent)
      ..addJavaScriptChannel('SBBridge',
          onMessageReceived: (m) => _onBridge(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: _onNavigation,
        onPageStarted: (u) {
          _shield();
          if (!mounted) return;
          setState(() {
            _url = u;
            _error = false;
            _found.clear();
          });
        },
        onProgress: (p) {
          _shield();
          if (mounted) setState(() => _progress = p);
        },
        onPageFinished: (u) async {
          _shield();
          final title = await _wc.getTitle();
          final back = await _wc.canGoBack();
          if (!mounted) return;
          _firstLoadDone = true;
          _startSniff();
          setState(() {
            _url = u;
            _pageTitle = title ?? '';
            _canGoBack = back;
            _progress = 100;
          });
        },
        onUrlChange: (c) async {
          final back = await _wc.canGoBack();
          if (!mounted) return;
          setState(() {
            if (c.url != null) _url = c.url!;
            _canGoBack = back;
          });
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted) {
            setState(() => _error = true);
          }
        },
      ));

    final p = _wc.platform;
    if (p is AndroidWebViewController) {
      p.setMediaPlaybackRequiresUserGesture(false);
      final cookies = WebViewCookieManager().platform;
      if (cookies is AndroidWebViewCookieManager) {
        cookies.setAcceptThirdPartyCookies(p, true);
      }
    }

    _wc.loadRequest(Uri.parse(widget.url));
  }

  @override
  void dispose() {
    _sniffTimer?.cancel();
    super.dispose();
  }

  NavigationDecision _onNavigation(NavigationRequest r) {
    final uri = Uri.tryParse(r.url);
    if (uri == null) return NavigationDecision.prevent;
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'about' || scheme == 'data' || scheme == 'blob') {
      return NavigationDecision.navigate;
    }
    // intent://, market://, custom app schemes: never leave the app.
    if (scheme != 'http' && scheme != 'https') {
      return NavigationDecision.prevent;
    }
    if (r.isMainFrame && r.url != widget.url && isDirectFileLink(r.url)) {
      _startDownload(r.url);
      return NavigationDecision.prevent;
    }
    if (widget.blockAds && _blockOn && AdShield.isAdUrl(r.url)) {
      return NavigationDecision.prevent;
    }
    if (r.isMainFrame && widget.blockAds && _blockOn) {
      final site = siteOf(uri.host);
      if (!_firstLoadDone) {
        // Redirects while the first page loads are normal (short links,
        // login hops...): trust them.
        _allowedSites.add(site);
      } else if (!_allowedSites.contains(site)) {
        // Another website after a tap: usually an ad, sometimes the file
        // host. Block the jump, but check whether it is a file first.
        _checkNavigation(r.url, crossSite: true);
        return NavigationDecision.prevent;
      }
    }
    if (r.isMainFrame && _firstLoadDone && r.url != _url) {
      // The WebView ignores file responses on its own (nothing happens when
      // the address has no .mp4/.mkv ending), so look at what it really is.
      _checkNavigation(r.url, crossSite: false);
    }
    return NavigationDecision.navigate;
  }

  /// Asks the server what [url] is. A file is downloaded in-app; a blocked
  /// cross-site page is reported so the person can allow it.
  Future<void> _checkNavigation(String url, {required bool crossSite}) async {
    if (!_checked.add(url)) return;
    Future<void>.delayed(const Duration(seconds: 6), () => _checked.remove(url));
    final cookie = await _pageCookies();
    final isFile = await DownloadManager.instance
        .looksLikeFile(url, referer: _url, cookie: cookie);
    if (!mounted) return;
    if (isFile) {
      _startDownload(url);
    } else if (crossSite) {
      final uri = Uri.tryParse(url);
      if (uri != null) _noteBlocked(uri);
    }
  }

  /// Addresses the page tried to open in a pop-up window.
  Future<void> _onBridge(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) return;
    if (AdShield.isAdUrl(url)) return;
    if (isDirectFileLink(url)) {
      _startDownload(url);
      return;
    }
    _checkNavigation(url, crossSite: false);
  }

  /// A page redirect to another website was blocked. Say so once per site,
  /// with an ALLOW button in case it was the real download page.
  void _noteBlocked(Uri uri) {
    final site = siteOf(uri.host);
    if (!mounted || !_notedSites.add(site)) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Blocked a redirect to ${uri.host}'),
        duration: const Duration(seconds: 7),
        action: SnackBarAction(
          label: 'ALLOW',
          textColor: Ui.redSoft,
          onPressed: () {
            _allowedSites.add(site);
            _notedSites.remove(site);
            _wc.loadRequest(uri);
          },
        ),
      ));
  }

  static const _sniffJs = r'''(function(){var out=[];
var re=/\.(mp4|mkv|webm|mov|m4v|avi|3gp)(\?|#|$)/i;
function add(u){try{if(!u)return;u=new URL(u,location.href).href;
if(/^https?:/.test(u)&&out.indexOf(u)<0)out.push(u);}catch(e){}}
document.querySelectorAll('video[src],video source[src]').forEach(function(e){add(e.getAttribute('src'));});
document.querySelectorAll('a[href]').forEach(function(a){var h=a.getAttribute('href');
if(h&&(re.test(h)||a.hasAttribute('download')))add(h);});
return JSON.stringify(out.slice(0,12));})()''';

  /// Looks for video files on the page for a while after it loads (download
  /// pages often reveal the real link only after a countdown or a click).
  void _startSniff() {
    _sniffTimer?.cancel();
    _sniffRuns = 0;
    _sniffOnce();
    _sniffTimer = Timer.periodic(const Duration(seconds: 2), (t) {
      if (!mounted || ++_sniffRuns > 30) {
        t.cancel();
        return;
      }
      _sniffOnce();
    });
  }

  Future<void> _sniffOnce() async {
    try {
      var r = (await _wc.runJavaScriptReturningResult(_sniffJs)).toString();
      if (r.startsWith('"')) r = jsonDecode(r) as String;
      final list = (jsonDecode(r) as List).map((e) => '$e').toList();
      var changed = false;
      for (final u in list) {
        if (!_found.contains(u)) {
          _found.add(u);
          changed = true;
        }
      }
      if (changed && mounted) setState(() {});
    } catch (_) {}
  }

  void _offerFound() {
    if (_found.length == 1) {
      _startDownload(_found.first);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Ui.panel,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text('Pick a file to download',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            ),
            for (final u in _found)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Icons.movie_rounded),
                title: Text(fileNameFromUrl(u),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(Uri.tryParse(u)?.host ?? '',
                    style: TextStyle(color: Ui.dim, fontSize: 12)),
                trailing: const Icon(Icons.download_rounded),
                onTap: () {
                  Navigator.pop(ctx);
                  _startDownload(u);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _shield() {
    if (widget.blockAds && _blockOn) {
      _wc.runJavaScript(AdShield.adShieldLightJs).catchError((_) {});
    }
  }

  String get _host => Uri.tryParse(_url)?.host ?? '';
  bool get _secure => _url.startsWith('https://');

  /// Best effort: cookies the page can see (HttpOnly cookies are not
  /// readable), so hosts that check a session still accept the request.
  Future<String> _pageCookies() async {
    try {
      final r = await _wc.runJavaScriptReturningResult('document.cookie');
      return r.toString().replaceAll(RegExp(r'^"|"$'), '');
    } catch (_) {
      return '';
    }
  }

  Future<void> _startDownload(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Starting download…'),
        duration: Duration(seconds: 30),
      ));
    final cookie = await _pageCookies();
    // Wait for the real result: the link is checked first and may turn out
    // not to be a file (or the server may refuse it).
    final error = await DownloadManager.instance.enqueue(
      url,
      referer: _url,
      cookie: cookie,
    );
    if (!mounted) return;
    if (error != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(error),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'OPEN IN BROWSER',
            textColor: Ui.redSoft,
            onPressed: () => openExternally(url),
          ),
        ));
      return;
    }
    messenger.hideCurrentSnackBar();
    if (await DownloadManager.instance.takeInAppNotice()) {
      if (!mounted) return;
      final view = await showInAppDownloadNotice(context);
      if (!mounted) return;
      if (view) {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const DownloadsScreen(),
        ));
        return;
      }
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Download started'),
        action: SnackBarAction(
          label: 'VIEW',
          textColor: Ui.redSoft,
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const DownloadsScreen(),
          )),
        ),
      ));
  }

  Future<void> _external() async {
    final ok = await openExternally(_url);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Couldn\'t open the link')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final heading = widget.title ??
        (_pageTitle.isNotEmpty ? _pageTitle : (_host.isEmpty ? 'Loading…' : _host));

    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _wc.goBack();
      },
      child: Scaffold(
        backgroundColor: Ui.bg,
        body: SafeArea(
          child: Column(
            children: [
              Container(
                height: 56,
                padding: const EdgeInsets.only(left: 4, right: 4),
                decoration: BoxDecoration(
                  color: Ui.panel,
                  border: Border(bottom: BorderSide(color: Ui.line)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            heading,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800),
                          ),
                          if (_host.isNotEmpty)
                            Row(
                              children: [
                                Icon(
                                  _secure
                                      ? Icons.lock_rounded
                                      : Icons.lock_open_rounded,
                                  size: 11,
                                  color: _secure ? Ui.green : Ui.dim,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    _host,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: Ui.muted,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    ListenableBuilder(
                      listenable: DownloadManager.instance,
                      builder: (context, _) => IconButton(
                        tooltip: 'Downloads',
                        onPressed: () =>
                            Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => const DownloadsScreen(),
                        )),
                        icon: Badge(
                          isLabelVisible:
                              DownloadManager.instance.activeCount > 0,
                          label: Text('${DownloadManager.instance.activeCount}'),
                          backgroundColor: Ui.red,
                          child: const Icon(Icons.download_rounded),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Reload',
                      onPressed: () {
                        setState(() => _error = false);
                        _wc.reload();
                      },
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    PopupMenuButton<String>(
                      color: Ui.panel,
                      icon: const Icon(Icons.more_vert_rounded),
                      onSelected: (v) {
                        if (v == 'external') _external();
                        if (v == 'download') _startDownload(_url);
                        if (v == 'ads') setState(() => _blockOn = !_blockOn);
                      },
                      itemBuilder: (_) => [
                        if (widget.blockAds)
                          PopupMenuItem(
                            value: 'ads',
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(_blockOn
                                  ? Icons.shield_rounded
                                  : Icons.shield_outlined),
                              title: Text(_blockOn
                                  ? 'Ad redirects: blocked'
                                  : 'Ad redirects: allowed'),
                            ),
                          ),
                        const PopupMenuItem(
                          value: 'download',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.download_rounded),
                            title: Text('Download this link'),
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'external',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.open_in_browser_rounded),
                            title: Text('Open in browser'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 2.5,
                child: _progress < 100 && !_error
                    ? LinearProgressIndicator(
                        value: _progress == 0 ? null : _progress / 100,
                        color: Ui.red,
                        backgroundColor: Colors.transparent,
                      )
                    : null,
              ),
              Expanded(
                child: Stack(
                  children: [
                    WebViewWidget(controller: _wc),
                    if (_found.isNotEmpty && !_error)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: GradientButton(
                          label: _found.length == 1
                              ? 'Download video'
                              : 'Download video (${_found.length})',
                          icon: Icons.download_rounded,
                          onTap: _offerFound,
                        ),
                      ),
                    if (_error)
                      Container(
                        color: Ui.bg,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.wifi_off_rounded,
                                size: 40, color: Ui.redSoft),
                            const SizedBox(height: 10),
                            const Text('Couldn\'t load this page',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed: () {
                                    setState(() => _error = false);
                                    _wc.reload();
                                  },
                                  style: FilledButton.styleFrom(
                                      backgroundColor: Ui.red),
                                  icon: const Icon(Icons.refresh_rounded,
                                      size: 18),
                                  label: const Text('Retry'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _external,
                                  icon: const Icon(
                                      Icons.open_in_browser_rounded,
                                      size: 18),
                                  label: const Text('Open in browser'),
                                ),
                              ],
                            ),
                          ],
                        ),
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
}
