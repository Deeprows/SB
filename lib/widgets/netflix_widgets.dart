import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/movie.dart';
import '../theme/app_theme.dart';
import 'glass.dart';
import 'movie_card.dart' show MoviePoster, initialsOf;

/// Poster tile: rounded artwork with a soft shadow, hairline border and an
/// optional rating pill. (Name kept so every screen picks the new look up.)
class NfPoster extends StatelessWidget {
  final Movie movie;
  final VoidCallback? onTap;
  final double radius;
  final bool showRating;
  const NfPoster({
    super.key,
    required this.movie,
    this.onTap,
    this.radius = 14,
    this.showRating = true,
  });

  @override
  Widget build(BuildContext context) {
    final Widget art;
    if (movie.image.startsWith('http')) {
      art = CachedNetworkImage(
        imageUrl: movie.image,
        fit: BoxFit.cover,
        memCacheWidth: 360,
        fadeInDuration: const Duration(milliseconds: 220),
        placeholder: (_, _) => ColoredBox(color: Ui.card),
        errorWidget: (_, _, _) => _fallback(),
      );
    } else if (movie.hasImage) {
      art = MoviePoster(movie: movie);
    } else {
      art = _fallback();
    }
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .45),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              art,
              // Hairline edge so dark posters don't melt into the page.
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: .09)),
                  ),
                ),
              ),
              if (showRating && movie.rating != null)
                Positioned(left: 6, top: 6, child: RatingPill(movie.rating!)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallback() => ColoredBox(
        color: Ui.card,
        child: Center(
          child: Text(initialsOf(movie.title),
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.white.withValues(alpha: .4))),
        ),
      );
}

/// A titled, horizontally scrolling row of posters. With [numbered] it is the
/// "Top 10" row: a big gradient rank number sits behind each poster.
class NfRow extends StatelessWidget {
  final String title;
  final List<Movie> movies;
  final void Function(Movie) onTap;
  final bool numbered;
  const NfRow({
    super.key,
    required this.title,
    required this.movies,
    required this.onTap,
    this.numbered = false,
  });

  static const posterW = 118.0;
  static const posterH = 177.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Ui.redSoft, Ui.red],
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 18,
                        letterSpacing: -.2,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
        SizedBox(
          // a little extra height so the poster shadows aren't clipped
          height: posterH + 12,
          child: ListView.separated(
            clipBehavior: Clip.none,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            itemCount: movies.length,
            separatorBuilder: (_, _) => SizedBox(width: numbered ? 6 : 12),
            itemBuilder: (_, i) => numbered
                ? _TopTenItem(
                    rank: i + 1, movie: movies[i], onTap: () => onTap(movies[i]))
                : SizedBox(
                    width: posterW,
                    child: NfPoster(
                        movie: movies[i], onTap: () => onTap(movies[i])),
                  ),
          ),
        ),
      ],
    );
  }
}

class _TopTenItem extends StatelessWidget {
  final int rank;
  final Movie movie;
  final VoidCallback onTap;
  const _TopTenItem(
      {required this.rank, required this.movie, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final wide = rank >= 10;
    final numW = wide ? 92.0 : 56.0;
    const fontSize = 124.0;
    final label = '$rank';
    final letter = wide ? -14.0 : -4.0;
    return SizedBox(
      width: numW + NfRow.posterW - (wide ? 6 : 0),
      child: Stack(
        children: [
          Positioned(
            left: wide ? -4 : 0,
            bottom: -16,
            child: ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (r) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Ui.redSoft, Ui.red.withValues(alpha: .25)],
              ).createShader(r),
              child: Text(label,
                  style: TextStyle(
                    fontSize: fontSize,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: letter,
                    color: Colors.white,
                  )),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: NfRow.posterW,
            child: NfPoster(movie: movie, onTap: onTap, showRating: false),
          ),
        ],
      ),
    );
  }
}

/// Pill used under the top bar ("Series", "Movies", "Categories"). The chosen
/// one fills with the accent gradient; the rest are frosted glass.
class NfChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool dropdown;
  final VoidCallback onTap;
  const NfChip({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.dropdown = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Ui.palette.onAccent : Colors.white;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected ? Ui.gradient : null,
          color: selected ? null : Colors.white.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
              color: selected ? Colors.transparent : Ui.glassLine),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    color: fg, fontSize: 13.5, fontWeight: FontWeight.w700)),
            if (dropdown) ...[
              const SizedBox(width: 2),
              Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: fg),
            ],
          ],
        ),
      ),
    );
  }
}
