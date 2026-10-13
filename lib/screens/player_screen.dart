import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import '../services/pip_service.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../config.dart';
import '../models/movie.dart';
import '../models/movie_info.dart';
import '../services/ad_shield.dart';
import '../services/background_playback.dart';
import '../services/movie_library.dart';
import '../services/player_html.dart';
import '../services/settings_service.dart';
import '../services/stream_resolver.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_watermark.dart';
import '../widgets/movie_info_panel.dart';
import 'browser_screen.dart' show siteOf;

/// WebView based player. Plays:
///  * m3u8 (hls.js), mpd (dash.js) and direct video files through a built-in
///    HTML5 player page,
///  * anything else (embed pages, iframes, player links) as a normal web page.
class PlayerScreen extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String url;
  final String? altUrl;
  final bool isLive;

  /// Optional per-stream headers (IPTV Nexus). The referer becomes the
  /// player page origin; the user agent replaces the default one.
  final String? referer;
  final String? userAgent;
  final String? altReferer;
  final String? altUserAgent;

  /// Set for football matches ("Home vs Away"): the stream page then shows
  /// the compact controls and the live chat instead of the info panel.
  final String? chatMatch;

  /// Set for movies and series: the page then shows slim controls and the
  /// TMDB details (overview, cast, ...) instead of the stream help box.
  final Movie? movie;

  const PlayerScreen({
    super.key,
    required this.title,
    required this.url,
    this.subtitle,
    this.altUrl,
    this.referer,
    this.userAgent,
    this.altReferer,
    this.altUserAgent,
    this.isLive = false,
    this.chatMatch,
    this.movie,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  late final WebViewController _wc;
  final GlobalKey _videoKey = GlobalKey();

  late final List<String> _sources = [
    widget.url,
    if (widget.altUrl != null &&
        widget.altUrl!.trim().isNotEmpty &&
        widget.altUrl!.trim() != widget.url.trim())
      widget.altUrl!,
  ];
  late final List<String?> _referers = [
    widget.referer,
    if (_sources.length > 1) widget.altReferer,
  ];
  late final List<String?> _agents = [
    widget.userAgent,
    if (_sources.length > 1) widget.altUserAgent,
  ];
  int _srcIdx = 0;

  /// Page origin for the built-in player. Uses the stream's own referer when
  /// it has one. Plain http:// streams get an http:// origin, because a
  /// WebView blocks http requests made from an https page (mixed content).
  String _playerBase(String streamUrl) {
    final ref = (_referers[_srcIdx] ?? '').trim();
    if (ref.startsWith('http://') || ref.startsWith('https://')) return ref;
    if (streamUrl.toLowerCase().startsWith('http://')) {
      return AppConfig.playerOrigin.replaceFirst('https://', 'http://');
    }
    return AppConfig.playerOrigin;
  }

  bool _error = false;
  bool _settled = false;
  bool _landscape = false;
  String _initialHost = '';

  // Pop-up / redirect blocking. Cross-site hops are only trusted during the
  // first load (short links, embed redirects); after that, the page may not
  // send the player to another website by itself.
  DateTime _startedAt = DateTime.now();
  final Set<String> _allowedSites = {};
  static const _gateWindow = Duration(seconds: 5);
  bool _pipEnabled = false;

  MovieInfo? _info; // TMDB details of a movie page
  bool _infoLoading = false;

  Widget? _fullscreenWidget;
  VoidCallback? _fullscreenHidden;

  ResolvedStream get _stream => StreamResolver.resolve(_sources[_srcIdx]);

  @override
  void initState() {
    super.initState();
    ThemeDecor.hold();
    WakelockPlus.enable();
    WidgetsBinding.instance.addObserver(this);
    BackgroundPlayback.start(
      widget.title,
      _onStopTapped,
      onPlay: () => _wc.runJavaScript(_videosJs('v.play()')).catchError((_) {}),
      onPause: () => _wc.runJavaScript(_videosJs('v.pause()')).catchError((_) {}),
      onSeekBy: (sec) => _wc
          .runJavaScript(_videosJs(
              'v.currentTime=Math.max(0,v.currentTime+($sec))'))
          .catchError((_) {}),
    );

    _wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(AppConfig.userAgent)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          _keepVisible();
          _killPopups();
        },
        onProgress: (_) => _killPopups(),
        onPageFinished: (_) {
          _settled = true;
          _keepVisible();
          _killPopups();
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted) {
            setState(() => _error = true);
          }
        },
        onNavigationRequest: _onNavigation,
      ));

    final p = _wc.platform;
    if (p is AndroidWebViewController) {
      p.setMediaPlaybackRequiresUserGesture(false);
      p.setCustomWidgetCallbacks(
        onShowCustomWidget: _showFullscreen,
        onHideCustomWidget: _hideFullscreen,
      );
      final cookies = WebViewCookieManager().platform;
      if (cookies is AndroidWebViewCookieManager) {
        cookies.setAcceptThirdPartyCookies(p, true);
      }
    }

    Settings.floatingPlayer().then((v) {
      if (mounted) setState(() => _pipEnabled = v);
    });
    _start();

    final movie = widget.movie;
    if (movie != null) MovieLibrary.instance.addToHistory(movie);
    if (movie != null && TmdbService.enabled) {
      _infoLoading = true;
      tmdb.info(movie).then((i) {
        if (mounted) {
          setState(() {
            _info = i;
            _infoLoading = false;
          });
        }
      });
    }
  }

  // ------------------------------------------------- background playback

  /// "Stop" on the background-playback notification: close the player.
  void _onStopTapped() {
    if (!mounted) return;
    _wc.runJavaScript(
        "document.querySelectorAll('video').forEach(function(v){try{v.pause()}catch(e){}})")
        .catchError((_) {});
    Navigator.of(context).maybePop();
  }

  /// JS that runs [action] on every <video> of the page (v = the video).
  String _videosJs(String action) =>
      "document.querySelectorAll('video').forEach(function(v){try{$action}catch(e){}})";

  /// Stops the page from pausing itself because it thinks it is hidden.
  void _keepVisible() {
    _wc.runJavaScript(BackgroundPlayback.keepVisibleJs).catchError((_) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      _wc.runJavaScript(BackgroundPlayback.rememberPlayingJs)
          .catchError((_) {});
      // If the page still paused its video, start it again.
      for (final ms in const [400, 1500]) {
        Future.delayed(Duration(milliseconds: ms), () {
          if (mounted) {
            _wc.runJavaScript(BackgroundPlayback.resumePlayingJs)
                .catchError((_) {});
          }
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      _wc.runJavaScript(BackgroundPlayback.resumePlayingJs)
          .catchError((_) {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BackgroundPlayback.stop(_onStopTapped);
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    ThemeDecor.release();
    super.dispose();
  }

  // ---------------------------------------------------------------- loading

  Future<void> _start() async {
    final s = _stream;
    setState(() {
      _error = false;
      _settled = false;
    });
    if (s.kind == StreamKind.invalid) {
      setState(() => _error = true);
      return;
    }
    _initialHost = Uri.tryParse(s.url)?.host ?? '';
    _startedAt = DateTime.now();
    _allowedSites
      ..clear()
      ..add(siteOf(_initialHost));
    try {
      await _wc.setUserAgent(_agents[_srcIdx] ?? AppConfig.userAgent);
      if (s.usesHtmlPlayer) {
        final low = await Settings.forceLowQuality();
        await _wc.loadHtmlString(
          buildPlayerHtml(s, lowQuality: low),
          baseUrl: _playerBase(s.url),
        );
      } else {
        await _wc.loadRequest(Uri.parse(s.url));
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  bool get _gateOpen =>
      !_settled && DateTime.now().difference(_startedAt) < _gateWindow;

  /// Keeps ad redirects out. Frames and sub-resources (what embeds are made
  /// of) are never affected. Top-level navigation to another website is only
  /// trusted while the first page is loading; afterwards it is blocked and a
  /// snackbar offers ALLOW in case the redirect was legitimate.
  NavigationDecision _onNavigation(NavigationRequest r) {
    if (!r.isMainFrame) {
      // Frames/sub-resources stay allowed (embeds are made of them), except
      // known ad networks.
      return AdShield.isAdSubframe(r.url)
          ? NavigationDecision.prevent
          : NavigationDecision.navigate;
    }
    final uri = Uri.tryParse(r.url);
    if (uri == null) return NavigationDecision.prevent;
    if (AdShield.isAdUrl(r.url)) return NavigationDecision.prevent;
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'about' || scheme == 'data' || scheme == 'blob') {
      return NavigationDecision.navigate;
    }
    // intent://, market://, custom app schemes: never leave the app.
    if (scheme != 'http' && scheme != 'https') {
      return NavigationDecision.prevent;
    }
    final site = siteOf(uri.host);
    if (_gateOpen) {
      _allowedSites.add(site);
      return NavigationDecision.navigate;
    }
    if (_allowedSites.contains(site) ||
        site == siteOf(Uri.parse(AppConfig.playerOrigin).host)) {
      return NavigationDecision.navigate;
    }
    _noteBlocked(uri);
    return NavigationDecision.prevent;
  }

  /// Blocked redirects are dropped silently (no notification).
  void _noteBlocked(Uri uri) {}

  /// Neutralises pop-ups opened by the page itself and by transparent
  /// click-catcher overlays (window.open / target=_blank links).
  void _killPopups() {
    if (_stream.usesHtmlPlayer) return; // our own page has no ads
    _wc.runJavaScript(AdShield.adShieldJs).catchError((_) {});
  }

  // ------------------------------------------------------------- fullscreen

  Future<void> _applyOrientation({required bool landscape}) async {
    if (landscape) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _showFullscreen(Widget widget, void Function() onHidden) {
    if (!mounted) return;
    setState(() {
      _fullscreenWidget = widget;
      _fullscreenHidden = onHidden;
    });
    _applyOrientation(landscape: true);
  }

  void _hideFullscreen() {
    if (!mounted) return;
    setState(() {
      _fullscreenWidget = null;
      _fullscreenHidden = null;
    });
    _applyOrientation(landscape: _landscape);
  }

  void _toggleLandscape() {
    setState(() => _landscape = !_landscape);
    _applyOrientation(landscape: _landscape);
  }

  // ---------------------------------------------------------------- actions

  void _switchSource() {
    setState(() => _srcIdx = (_srcIdx + 1) % _sources.length);
    _start();
  }

  Future<void> _enterPip() async {
    try {
      if (await PipService.isAvailable() && await PipService.enter()) return;
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Floating player is not supported here')));
  }

  /// Opens Android's "Cast screen" panel so the stream (including web embeds)
  /// can be mirrored to a TV or Chromecast.
  Future<void> _cast() async {
    const actions = [
      'android.settings.CAST_SETTINGS',
      'android.settings.WIFI_DISPLAY_SETTINGS',
    ];
    for (final a in actions) {
      try {
        await AndroidIntent(action: a).launch();
        return;
      } catch (_) {}
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Open "Cast" or "Smart View" from your phone\'s quick settings')));
  }

  /// Bookmark next to "Cast to screen": saves the movie for later.
  Widget _watchLaterButton(Movie m) {
    return ListenableBuilder(
      listenable: MovieLibrary.instance,
      builder: (context, _) {
        final saved = MovieLibrary.instance.isSaved(m);
        return IconButton(
          tooltip: saved ? 'Remove from Watch later' : 'Save to Watch later',
          onPressed: () async {
            final now = await MovieLibrary.instance.toggleWatchLater(m);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                  duration: const Duration(seconds: 2),
                  content: Text(
                      now ? 'Saved to Watch later' : 'Removed from Watch later')));
          },
          icon: Icon(
            saved ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
            color: saved ? Ui.red : null,
          ),
        );
      },
    );
  }

  void _onBack() {
    if (_fullscreenWidget != null) {
      _fullscreenHidden?.call();
      _hideFullscreen();
    } else if (_landscape) {
      _toggleLandscape();
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final fs = _fullscreenWidget != null;
    final immersive = _landscape || fs;

    final video = ColoredBox(
      key: _videoKey,
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          WebViewWidget(controller: _wc),
          if (_error) _ErrorOverlay(
            hasAlt: _sources.length > 1,
            invalid: _stream.kind == StreamKind.invalid,
            onRetry: _start,
            onAlt: _switchSource,
          ),
        ],
      ),
    );

    return PopScope(
      canPop: !immersive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: immersive ? Colors.black : Ui.bg,
        body: Stack(
          children: [
            if (immersive)
              Positioned.fill(child: video)
            else
              _portraitBody(video),
            if (_landscape && !fs) ...[
              Positioned(
                left: 12,
                top: 12,
                child: _RoundButton(
                    icon: Icons.arrow_back_rounded, onTap: _onBack),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: _RoundButton(
                    icon: Icons.screen_rotation_rounded,
                    onTap: _toggleLandscape),
              ),
            ],
            if (fs)
              Positioned.fill(
                child: ColoredBox(color: Colors.black, child: _fullscreenWidget),
              ),
          ],
        ),
      ),
    );
  }

  /// Slim Reload / Switch / Rotate row used on football match pages.
  Widget _compactControls({double side = 10, double top = 6}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(side, top, side, 8),
      child: Row(
        children: [
          Expanded(
              child: _MiniAction(
                  icon: Icons.refresh_rounded, label: 'Reload', onTap: _start)),
          const SizedBox(width: 8),
          Expanded(
              child: _MiniAction(
                  icon: Icons.swap_horiz_rounded,
                  label: _sources.length > 1
                      ? 'Switch ${_srcIdx + 1}/${_sources.length}'
                      : 'Switch',
                  enabled: _sources.length > 1,
                  onTap: _switchSource)),
          const SizedBox(width: 8),
          Expanded(
              child: _MiniAction(
                  icon: Icons.screen_rotation_rounded,
                  label: 'Rotate',
                  onTap: _toggleLandscape)),
        ],
      ),
    );
  }

  /// Netflix-style title block: big title, then "87% Match  2026  1h 44m  HD".
  Widget _movieHeader(MovieInfo? info) {
    final m = widget.movie!;
    final score = double.tryParse(m.rating ?? '');
    final runtime = info?.runtimeText ?? '';
    final seasons = info?.seasons;
    final facts = <String>[
      if (m.year != null) m.year!,
      if (m.isSeries && seasons != null)
        (seasons == 1 ? '1 Season' : '$seasons Seasons')
      else if (runtime.isNotEmpty)
        runtime,
    ];
    Widget badge(String t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            border: Border.all(color: Ui.muted.withValues(alpha: .8)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(t,
              style: TextStyle(
                  color: Ui.muted, fontSize: 11, fontWeight: FontWeight.w700)),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title,
              style: const TextStyle(
                  fontSize: 24, height: 1.1, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (score != null)
                Text('${(score * 10).round()}% Match',
                    style: TextStyle(
                        color: Ui.green,
                        fontSize: 14,
                        fontWeight: FontWeight.w900)),
              for (final f in facts)
                Text(f,
                    style: TextStyle(
                        color: Ui.muted,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              badge(m.isSeries ? 'Series' : 'Movie'),
              badge('HD'),
            ],
          ),
          if (info != null && info.tagline.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(info.tagline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Ui.dim, fontSize: 12.5, fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }

  /// Netflix-style icon-over-label row: My List, Reload, Switch, Rotate, Cast.
  Widget _nfActions() {
    final m = widget.movie!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ListenableBuilder(
            listenable: MovieLibrary.instance,
            builder: (context, _) {
              final saved = MovieLibrary.instance.isSaved(m);
              return _NfAction(
                icon: saved ? Icons.check_rounded : Icons.add_rounded,
                label: 'My List',
                onTap: () async {
                  final now = await MovieLibrary.instance.toggleWatchLater(m);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(
                        duration: const Duration(seconds: 2),
                        content: Text(
                            now ? 'Added to My List' : 'Removed from My List')));
                },
              );
            },
          ),
          _NfAction(icon: Icons.refresh_rounded, label: 'Reload', onTap: _start),
          _NfAction(
            icon: Icons.swap_horiz_rounded,
            label: _sources.length > 1
                ? 'Switch ${_srcIdx + 1}/${_sources.length}'
                : 'Switch',
            enabled: _sources.length > 1,
            onTap: _switchSource,
          ),
          _NfAction(
              icon: Icons.screen_rotation_rounded,
              label: 'Rotate',
              onTap: _toggleLandscape),
          _NfAction(icon: Icons.cast_rounded, label: 'Cast', onTap: _cast),
        ],
      ),
    );
  }

  /// Movie / series page: title, slim controls, then the TMDB details.
  Widget _movieBody() {
    final info = _info;
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _movieHeader(info),
        _nfActions(),
        MovieInfoPanel(
            movie: widget.movie!, info: info, loading: _infoLoading),
      ],
    );
  }

  Widget _portraitBody(Widget video) {
    final s = _stream;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                if (widget.movie != null) _watchLaterButton(widget.movie!),
                IconButton(
                  tooltip: 'Cast to screen',
                  onPressed: _cast,
                  icon: const Icon(Icons.cast_rounded),
                ),
                if (_pipEnabled)
                  IconButton(
                    tooltip: 'Floating player',
                    onPressed: _enterPip,
                    icon: const Icon(Icons.picture_in_picture_alt_rounded),
                  ),
              ],
            ),
          ),
          AspectRatio(aspectRatio: 16 / 9, child: video),
          if (widget.movie != null)
            Expanded(child: _movieBody())
          else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Text(widget.title,
                    style: const TextStyle(
                        fontSize: 20,
                        height: 1.2,
                        fontWeight: FontWeight.w900)),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(widget.subtitle!,
                      style: TextStyle(
                          color: Ui.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Chip(icon: Icons.play_circle_outline_rounded, label: s.label),
                    if (_sources.length > 1)
                      _Chip(
                          icon: Icons.layers_outlined,
                          label: 'Stream ${_srcIdx + 1} of ${_sources.length}'),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _Action(
                          icon: Icons.refresh_rounded,
                          label: 'Reload',
                          onTap: _start),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Action(
                          icon: Icons.swap_horiz_rounded,
                          label: 'Switch',
                          enabled: _sources.length > 1,
                          onTap: _switchSource),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Action(
                          icon: Icons.screen_rotation_rounded,
                          label: 'Rotate',
                          onTap: _toggleLandscape),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Ui.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Ui.line),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: Ui.muted),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Stream not loading? Tap Reload, or Switch to try the '
                          'backup source. Pop-ups, redirects and on-screen ads are blocked '
                          'automatically.',
                          style: TextStyle(
                              color: Ui.muted, fontSize: 12.5, height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  final bool hasAlt;
  final bool invalid;
  final VoidCallback onRetry;
  final VoidCallback onAlt;
  const _ErrorOverlay({
    required this.hasAlt,
    required this.invalid,
    required this.onRetry,
    required this.onAlt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: .88),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, color: Ui.redSoft, size: 34),
          const SizedBox(height: 8),
          Text(
            invalid ? 'This link can\'t be played' : 'Couldn\'t load the stream',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onRetry,
                style: FilledButton.styleFrom(backgroundColor: Ui.red),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
              if (hasAlt)
                OutlinedButton.icon(
                  onPressed: onAlt,
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text('Other source'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Ui.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Ui.muted),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Ui.muted)),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : .4,
      child: Material(
        color: Ui.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Ui.line),
            ),
            child: Column(
              children: [
                Icon(icon, size: 22, color: Colors.white),
                const SizedBox(height: 6),
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: .5),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

/// Compact pill button: icon and label side by side.
class _MiniAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  const _MiniAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : .4,
      child: Material(
        color: Ui.card,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(99),
          child: Container(
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Ui.line),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NfAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  const _NfAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : .35,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 25),
              const SizedBox(height: 5),
              Text(label,
                  style: TextStyle(
                      color: Ui.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
