import 'dart:convert';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/ad_scheduler.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/l10n.dart';

/// Login / Sign up. One button only: Gmail. A slowly scrolling wall of movie
/// posters sits behind a dark glow so the page feels like a cinema lobby.
class LoginScreen extends StatefulWidget {
  /// Called after a successful Gmail sign-in.
  final VoidCallback onSignedIn;
  const LoginScreen({super.key, required this.onSignedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scroll = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 70),
  )..repeat();

  List<String> _posters = const [];
  bool _signup = false;
  bool _busy = false;
  String? _error;
  bool _setupError = false;

  @override
  void initState() {
    super.initState();
    // No ad pop-ups while the person is logging in.
    AdScheduler.instance.hold();
    _loadPosters();
  }

  @override
  void dispose() {
    AdScheduler.instance.release();
    _scroll.dispose();
    super.dispose();
  }

  /// Poster links from the bundled movies.json (no network needed to read
  /// the list; the pictures themselves are cached after the first start).
  Future<void> _loadPosters() async {
    try {
      final raw = await rootBundle.loadString('assets/data/movies.json');
      final data = jsonDecode(raw);
      final urls = <String>[];
      if (data is List) {
        for (final row in data) {
          if (row is! Map) continue;
          final img = '${row['image'] ?? ''}';
          // Skip wide backdrops: tall posters look best in the wall.
          if (img.startsWith('http') && !img.contains('w1280')) urls.add(img);
        }
      }
      urls.shuffle(math.Random());
      if (mounted) setState(() => _posters = urls.take(24).toList());
    } catch (_) {}
  }

  Future<void> _continue() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _setupError = false;
    });
    final r = await AuthService.instance.signIn();
    if (!mounted) return;
    switch (r) {
      case SignInResult.ok:
        widget.onSignedIn();
        return;
      case SignInResult.cancelled:
        setState(() => _busy = false);
        return;
      case SignInResult.notGmail:
        setState(() {
          _busy = false;
          _error = 'Please use a Gmail account (name@gmail.com).'.tr;
        });
        return;
      case SignInResult.setupError:
        setState(() {
          _busy = false;
          _setupError = true;
          _error = 'Google sign-in is not set up for this app yet.'.tr;
        });
        return;
      case SignInResult.network:
        setState(() {
          _busy = false;
          _error = 'No internet connection. Check it and try again.'.tr;
        });
        return;
      case SignInResult.failed:
        setState(() {
          _busy = false;
          _error = 'Could not sign in. Check your internet and try again.'.tr;
        });
        return;
    }
  }

  /// Temporary way in while Google sign-in is not set up (see AppConfig).
  Future<void> _manualGmail() async {
    final ctrl = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Enter your Gmail'.tr),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: 'name@gmail.com'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('CANCEL'.tr)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text('CONTINUE'.tr)),
        ],
      ),
    );
    if (email == null || !mounted) return;
    final ok = await AuthService.instance.signInManually(email);
    if (!mounted) return;
    if (ok) {
      widget.onSignedIn();
    } else {
      setState(() => _error = 'Please use a Gmail account (name@gmail.com).'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Ui.bg,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Poster wall.
            RepaintBoundary(
              child: _PosterWall(posters: _posters, anim: _scroll),
            ),
            // 2. Dark fade: posters show at the top, fade out to the card.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, .32, .62, 1],
                  colors: [
                    Ui.bg.withValues(alpha: .55),
                    Ui.bg.withValues(alpha: .35),
                    Ui.bg.withValues(alpha: .88),
                    Ui.bg,
                  ],
                ),
              ),
            ),
            // 3. Soft accent glow behind the card.
            Positioned(
              left: -80,
              right: -80,
              bottom: -140,
              height: 420,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      Ui.red.withValues(alpha: .38),
                      Ui.red.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            // 4. Content.
            SafeArea(
              child: LayoutBuilder(
                builder: (context, c) => SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: c.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                        children: [
                          const SizedBox(height: 18),
                          Image.asset(
                            'assets/splash/splash.png',
                            height: 120,
                            fit: BoxFit.contain,
                          ),
                          const Spacer(),
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                                20, 0, 20, math.max(pad.bottom, 0) + 18),
                            child: _card(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      decoration: BoxDecoration(
        color: Ui.panel.withValues(alpha: .86),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .5),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tabs(),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Column(
              key: ValueKey(_signup),
              children: [
                Text(
                  _signup ? 'Create your account'.tr : 'Welcome back'.tr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _signup
                      ? 'Join with your Gmail to stream, download and save movies.'
                          .tr
                      : 'Log in with your Gmail to pick up where you left off.'
                          .tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Ui.muted, fontSize: 13.5, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _gmailButton(),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _error == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline_rounded,
                            size: 17, color: Ui.redSoft),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                              style: TextStyle(
                                  color: Ui.redSoft,
                                  fontSize: 12.5,
                                  height: 1.35)),
                        ),
                      ],
                    ),
                  ),
          ),
          if (_error != null && AuthService.instance.lastError.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(AuthService.instance.lastError,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Ui.dim, fontSize: 10.5)),
            ),
          if (_setupError && AppConfig.allowGmailFallback)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextButton(
                onPressed: _manualGmail,
                child: Text('Enter your Gmail address instead'.tr,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded, size: 14, color: Ui.dim),
              const SizedBox(width: 6),
              Text('Gmail accounts only. No password needed.'.tr,
                  style: TextStyle(color: Ui.dim, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'By continuing you agree that Streambox does not host any movies. '
                    'All content belongs to its owners.'
                .tr,
            textAlign: TextAlign.center,
            style: TextStyle(color: Ui.dim, fontSize: 10.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _tabs() {
    Widget tab(String label, bool signup) {
      final on = _signup == signup;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _busy
              ? null
              : () => setState(() {
                    _signup = signup;
                    _error = null;
                  }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? Ui.red : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: on ? Ui.palette.onAccent : Ui.muted,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Ui.cardDeep,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Ui.line),
      ),
      child: Row(children: [
        tab('Log in'.tr, false),
        tab('Sign up'.tr, true),
      ]),
    );
  }

  Widget _gmailButton() {
    return SizedBox(
      height: 56,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        elevation: 6,
        shadowColor: Ui.red.withValues(alpha: .5),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: _busy ? null : _continue,
          child: Center(
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: Color(0xFF3C4043),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CustomPaint(painter: _GoogleG()),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _signup
                            ? 'Continue with Gmail'.tr
                            : 'Login with Gmail'.tr,
                        style: const TextStyle(
                          color: Color(0xFF1F1F1F),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ poster wall

/// Three tilted columns of posters drifting up / down / up.
class _PosterWall extends StatelessWidget {
  final List<String> posters;
  final Animation<double> anim;
  const _PosterWall({required this.posters, required this.anim});

  @override
  Widget build(BuildContext context) {
    if (posters.length < 6) return _fallback();
    final size = MediaQuery.of(context).size;
    const cols = 3;
    const gap = 10.0;
    // The wall is scaled up and tilted, so cover a bit more than the screen.
    final colW = (size.width * 1.25 - gap * (cols + 1)) / cols;
    final tileH = colW * 1.5;

    final columns = <Widget>[];
    for (var c = 0; c < cols; c++) {
      final mine = <String>[
        for (var i = c; i < posters.length; i += cols) posters[i],
      ];
      columns.add(SizedBox(
        width: colW,
        child: _PosterColumn(
          urls: mine,
          anim: anim,
          reverse: c == 1,
          tileW: colW,
          tileH: tileH,
          gap: gap,
          screenH: size.height * 1.4,
          phase: c * .21,
        ),
      ));
    }

    return ClipRect(
      child: OverflowBox(
        maxWidth: size.width * 1.25,
        maxHeight: size.height * 1.4,
        child: Transform.rotate(
          angle: -0.14,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: columns,
          ),
        ),
      ),
    );
  }

  /// No posters yet (first start offline): a quiet gradient with film icons.
  Widget _fallback() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Ui.card, Ui.bg],
        ),
      ),
      child: Align(
        alignment: const Alignment(0, -.55),
        child: Icon(Icons.movie_filter_rounded,
            size: 150, color: Ui.red.withValues(alpha: .10)),
      ),
    );
  }
}

class _PosterColumn extends StatelessWidget {
  final List<String> urls;
  final Animation<double> anim;
  final bool reverse;
  final double tileW, tileH, gap, screenH, phase;

  const _PosterColumn({
    required this.urls,
    required this.anim,
    required this.reverse,
    required this.tileW,
    required this.tileH,
    required this.gap,
    required this.screenH,
    required this.phase,
  });

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    final cycle = urls.length * (tileH + gap);
    // Enough repeats so the column is never shorter than the screen.
    final reps = ((screenH + cycle) / cycle).ceil() + 1;

    final tiles = <Widget>[
      for (var r = 0; r < reps; r++)
        for (final u in urls)
          Padding(
            padding: EdgeInsets.only(bottom: gap),
            child: SizedBox(
              width: tileW,
              height: tileH,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedNetworkImage(
                  imageUrl: u,
                  fit: BoxFit.cover,
                  memCacheWidth: 260,
                  fadeInDuration: const Duration(milliseconds: 350),
                  placeholder: (_, _) => ColoredBox(color: Ui.card),
                  errorWidget: (_, _, _) => ColoredBox(color: Ui.card),
                ),
              ),
            ),
          ),
    ];

    return AnimatedBuilder(
      animation: anim,
      child: OverflowBox(
        alignment: Alignment.topCenter,
        minHeight: 0,
        maxHeight: double.infinity,
        child: Column(mainAxisSize: MainAxisSize.min, children: tiles),
      ),
      builder: (_, child) {
        var t = (anim.value + phase) % 1.0;
        if (reverse) t = 1 - t;
        return Transform.translate(offset: Offset(0, -t * cycle), child: child);
      },
    );
  }
}

// ------------------------------------------------------------- Google "G"

class _GoogleG extends CustomPainter {
  const _GoogleG();

  static double _rad(double deg) => deg * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    final stroke = s * .2;
    final r = s * .5 - stroke / 2;
    final rect = Rect.fromCircle(center: c, radius: r);

    Paint p(Color col) => Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    // Angles are in degrees, clockwise from 3 o'clock.
    canvas.drawArc(rect, _rad(210), _rad(105), false, p(const Color(0xFFEA4335)));
    canvas.drawArc(rect, _rad(150), _rad(60), false, p(const Color(0xFFFBBC05)));
    canvas.drawArc(rect, _rad(45), _rad(105), false, p(const Color(0xFF34A853)));
    canvas.drawArc(rect, _rad(0), _rad(45), false, p(const Color(0xFF4285F4)));
    // The bar of the G.
    canvas.drawRect(
      Rect.fromLTRB(c.dx, c.dy - stroke / 2, s - 0.5, c.dy + stroke / 2),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
