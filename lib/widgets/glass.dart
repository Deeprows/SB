import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Frosted-glass panel: blurred backdrop, faint white fill and hairline border.
class Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final Color? tint;
  const Glass({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding,
    this.blur = 18,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint ?? Colors.white.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Ui.glassLine),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Round glass icon button (back, search, bookmark...).
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 42,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Glass(
        radius: size,
        blur: 14,
        tint: Colors.black.withValues(alpha: .28),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * .52),
        ),
      ),
    );
  }
}

/// Primary call-to-action: accent gradient, rounded, soft glow.
class GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final double height;
  const GradientButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.height = 50,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: Ui.gradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Ui.red.withValues(alpha: .45),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 26, color: Ui.palette.onAccent),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Ui.palette.onAccent)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary action: glass pill with an icon and a label.
class GlassButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final double height;
  const GlassButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.height = 50,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Glass(
        radius: 16,
        blur: 14,
        tint: Colors.white.withValues(alpha: .10),
        child: SizedBox(
          height: height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small rounded rating pill (star + score).
class RatingPill extends StatelessWidget {
  final String rating;
  const RatingPill(this.rating, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 12, color: Color(0xFFFFC107)),
          const SizedBox(width: 3),
          Text(rating,
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
