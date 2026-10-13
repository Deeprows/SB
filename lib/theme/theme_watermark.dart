import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'app_theme.dart';

/// Video players ask for the theme decoration (stripes, picture, watermark)
/// to be hidden while they are open, so nothing sits over a stream, a
/// highlight or a movie. Each player calls [hold] when it opens and
/// [release] when it closes.
class ThemeDecor {
  ThemeDecor._();
  static final ValueNotifier<int> _holds = ValueNotifier<int>(0);

  static void hold() => _later(() => _holds.value++);
  static void release() => _later(() {
        if (_holds.value > 0) _holds.value--;
      });

  // Changed after the current frame so it is safe to call from
  // initState / dispose.
  static void _later(VoidCallback change) {
    final b = SchedulerBinding.instance;
    b.addPostFrameCallback((_) => change());
    b.scheduleFrame();
  }
}

/// Extra decoration for the football-icon themes, drawn over the whole app
/// and never taking taps:
///  * faint jersey stripes (black & white for CR7, sky blue for Messi),
///  * a faint picture in the bottom-right corner (assets/themes/cr7.png or
///    messi.png),
///  * a big faint diagonal name ("MESSI 10", "CR7").
/// Draws nothing for the other themes.
class ThemeWatermark extends StatelessWidget {
  const ThemeWatermark({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ThemeDecor._holds,
      builder: (_, holds, __) =>
          holds > 0 ? const SizedBox.shrink() : _decor(),
    );
  }

  Widget _decor() {
    final p = Ui.palette;
    final text = p.watermark;
    final asset = p.backdropAsset;
    final hasText = text != null && text.isNotEmpty;
    if (!hasText && !p.stripes && asset == null) return const SizedBox.shrink();

    return Positioned.fill(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (p.stripes)
                const CustomPaint(painter: _StripesPainter()),
              if (asset != null)
                Align(
                  alignment: Alignment.bottomRight,
                  child: FractionallySizedBox(
                    heightFactor: .52,
                    child: Opacity(
                      opacity: .12,
                      child: Image.asset(
                        asset,
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomRight,
                        // File missing: just show nothing.
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              if (hasText)
                Center(
                  child: Transform.rotate(
                    angle: -0.42,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          text,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 84,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 6,
                            decoration: TextDecoration.none,
                            color: Ui.red.withValues(alpha: .06),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vertical bands, like the stripes of a football jersey.
class _StripesPainter extends CustomPainter {
  const _StripesPainter();

  static const _band = 26.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Ui.palette.stripeColor.withValues(alpha: .05);
    for (var x = 0.0; x < size.width; x += _band * 2) {
      canvas.drawRect(Rect.fromLTWH(x, 0, _band, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StripesPainter old) => false;
}
