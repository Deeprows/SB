import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../config.dart';
import '../screens/ad_support_screen.dart';
import '../screens/plans_screen.dart';
import '../screens/remove_ads_screen.dart';
import '../screens/support_browser_screen.dart';
import '../services/ad_preloader.dart';
import '../services/remote_config.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';

enum SupportChoice { supported, released, premium }

/// Shows the "We Need Your Support" overlay. Resolves to [SupportChoice.supported]
/// once the support page has been viewed to the end, [SupportChoice.released]
/// when the support page cannot load at all (so nobody is locked out by a
/// dead link or no connection), or [SupportChoice.premium] when the person
/// chose to remove the ads instead.
Future<SupportChoice?> showSupportOverlay(BuildContext context) {
  // The overlay is hidden (AppConfig.supportOverlayVisible = false): load the
  // ad page directly, with only a short "please wait" bar on top of it.
  if (!AppConfig.supportOverlayVisible) return _showAdPage(context);
  return showGeneralDialog<SupportChoice>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Support DamiMovies',
    barrierColor: Colors.black.withValues(alpha: .74),
    transitionDuration: const Duration(milliseconds: 340),
    pageBuilder: (_, _, _) => const SupportOverlay(),
    transitionBuilder: (_, anim, _, child) {
      final c = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: c,
        child: ScaleTransition(
          scale: Tween<double>(begin: .94, end: 1).animate(c),
          child: child,
        ),
      );
    },
  );
}

/// Opens the ad page on top of whatever is showing. When it closes the person
/// is back exactly where they were (and the tapped item opens).
Future<SupportChoice?> _showAdPage(BuildContext context) async {
  final r = await Navigator.of(context, rootNavigator: true)
      .push<SupportResult>(
    MaterialPageRoute<SupportResult>(
      fullscreenDialog: true,
      builder: (_) => AdSupportScreen(
        url: RemoteConfig.instance.supportUrl,
        preloaded: AdPreloader.instance.take(),
      ),
    ),
  );
  return switch (r) {
    SupportResult.completed => SupportChoice.supported,
    SupportResult.failed => SupportChoice.released,
    _ => null,
  };
}

class SupportOverlay extends StatefulWidget {
  const SupportOverlay({super.key});

  @override
  State<SupportOverlay> createState() => _SupportOverlayState();
}

class _SupportOverlayState extends State<SupportOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..repeat(reverse: true);
  bool _busy = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_busy) return;
    _busy = true;
    final result = await Navigator.of(context).push<SupportResult>(
      MaterialPageRoute<SupportResult>(
        fullscreenDialog: true,
        builder: (_) => SupportBrowserScreen(
          url: RemoteConfig.instance.supportUrl,
          seconds: AppConfig.supportViewSeconds,
        ),
      ),
    );
    _busy = false;
    if (!mounted) return;
    // Closed early: stay on the overlay so the person can try again.
    if (result == SupportResult.completed) {
      Navigator.of(context).pop(SupportChoice.supported);
    } else if (result == SupportResult.failed) {
      Navigator.of(context).pop(SupportChoice.released);
    }
  }

  Future<void> _goPremium() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const PlansScreen()),
    );
    if (!mounted) return;
    if (SubscriptionService.instance.isPremium) {
      Navigator.of(context).pop(SupportChoice.premium);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mins = RemoteConfig.instance.adIntervalMinutes; // minutes between ads
    final secs = AppConfig.supportViewSeconds;
    final mLabel = mins == 1 ? 'minute' : 'minutes';

    final steps = <String>[
      'Click the button above ☝️',
      'Wait for the page to load 🥱',
      'Stay on the page for $secs seconds ❤️',
      'It will close automatically ☺️',
      'Enjoy uninterrupted streaming for the next $mins $mLabel 📺',
    ];

    return PopScope(
      canPop: false, // the overlay is closed by the CLICK HERE flow only
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
              child: const SizedBox.expand(),
            ),
          ),
          Material(
            type: MaterialType.transparency,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _topCard(mins, mLabel, secs),
                        const SizedBox(height: 14),
                        _stepsCard(steps),
                        if (SubscriptionService.instance.visible) ...[
                          const SizedBox(height: 10),
                          _premiumButton(),
                        ] else if (SubscriptionService.instance.tokensVisible) ...[
                          const SizedBox(height: 10),
                          _tokenButton(),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ top card

  Widget _topCard(int mins, String mLabel, int secs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Ui.panel,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Ui.red.withValues(alpha: .16), Ui.panel, Ui.panel],
          stops: const [0, .55, 1],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Ui.red.withValues(alpha: .38), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Ui.red.withValues(alpha: .18),
            blurRadius: 40,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Ui.red, Ui.redSoft],
              ),
              boxShadow: [
                BoxShadow(
                  color: Ui.red.withValues(alpha: .45),
                  blurRadius: 22,
                ),
              ],
            ),
            child: const Icon(Icons.favorite_rounded,
                color: Colors.white, size: 25),
          ),
          const SizedBox(height: 8),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (r) =>
                LinearGradient(colors: [Ui.redSoft, Ui.red]).createShader(r),
            child: const Text(
              'We Need Your Support',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w900,
                height: 1.05,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Help us keep DamiMovies running',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Ui.muted, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Ui.cardDeep,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Ui.line),
            ),
            child: Text(
              'Wait time: ${secs}s  •  Trigger: every $mins min  •  Auto close: ON',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Ui.dim, fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Choose your experience — support us with a single visit and '
            'enjoy $mins $mLabel of uninterrupted streaming.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Ui.muted,
                fontSize: 14,
                height: 1.25,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          _button(mins),
        ],
      ),
    );
  }

  Widget _button(int mins) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, _) {
        final t = Curves.easeInOut.transform(_pulse.value);
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(colors: [Ui.red, Ui.redSoft]),
            boxShadow: [
              BoxShadow(
                color: Ui.red.withValues(alpha: .28 + .22 * t),
                blurRadius: 18 + 12 * t,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: _open,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Column(
                  children: [
                    const Text(
                      'Click Here',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Open 1 AD per $mins min',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .88),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _premiumButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _goPremium,
        icon: Icon(Icons.workspace_premium_rounded, color: Ui.redSoft),
        label: Text('Remove ads — go Premium',
            style: TextStyle(
                color: Ui.redSoft, fontWeight: FontWeight.w800, fontSize: 14)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 13),
          side: BorderSide(color: Ui.red.withValues(alpha: .6)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22)),
        ),
      ),
    );
  }

  Future<void> _goRemoveAds() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const RemoveAdsScreen()),
    );
    if (!mounted) return;
    if (SubscriptionService.instance.isPremium) {
      Navigator.of(context).pop(SupportChoice.premium);
    }
  }

  Widget _tokenButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _goRemoveAds,
        icon: Icon(Icons.vpn_key_rounded, color: Ui.redSoft),
        label: Text('Remove ads — use a token',
            style: TextStyle(
                color: Ui.redSoft, fontWeight: FontWeight.w800, fontSize: 14)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 13),
          side: BorderSide(color: Ui.red.withValues(alpha: .6)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22)),
        ),
      ),
    );
  }

  // --------------------------------------------------------- steps card

  Widget _stepsCard(List<String> steps) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 13, 12, 12),
      decoration: BoxDecoration(
        color: Ui.panel,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Ui.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 3, bottom: 8),
            child: Text('Instructions —',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          for (var i = 0; i < steps.length; i++)
            Container(
              margin: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Ui.cardDeep,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Ui.line),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Ui.red.withValues(alpha: .1),
                      border: Border.all(color: Ui.red.withValues(alpha: .65)),
                    ),
                    child: Text('${i + 1}',
                        style: TextStyle(
                            color: Ui.redSoft,
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(steps[i],
                        style: const TextStyle(
                            fontSize: 13, height: 1.2, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
