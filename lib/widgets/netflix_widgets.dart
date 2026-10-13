import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/movie.dart';
import '../theme/app_theme.dart';
import 'movie_card.dart' show MoviePoster, initialsOf;

/// Netflix poster tile: square-ish corners, no text, just the artwork.
class NfPoster extends StatelessWidget {
  final Movie movie;
  final VoidCallback? onTap;
  final double radius;
  const NfPoster({
    super.key,
    required this.movie,
    this.onTap,
    this.radius = 4,
  });

  @override
  Widget build(BuildContext context) {
    final Widget art;
    if (movie.image.startsWith('http')) {
      art = CachedNetworkImage(
        imageUrl: movie.image,
        fit: BoxFit.cover,
        memCacheWidth: 360,
        fadeInDuration: const Duration(milliseconds: 200),
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
      child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: art),
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
/// "Top 10" row: a big outlined rank number sits behind each poster.
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

  static const posterW = 112.0;
  static const posterH = 168.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 9),
          child: Text(title,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
        SizedBox(
          height: posterH,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: movies.length,
            separatorBuilder: (_, _) => SizedBox(width: numbered ? 4 : 8),
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
    const fontSize = 118.0;
    final label = '$rank';
    return SizedBox(
      width: numW + NfRow.posterW - (wide ? 6 : 0),
      child: Stack(
        children: [
          Positioned(
            left: wide ? -4 : 0,
            bottom: -14,
            child: Stack(
              children: [
                // Outline.
                Text(label,
                    style: TextStyle(
                      fontSize: fontSize,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: wide ? -14 : -4,
                      foreground: Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = 3
                        ..color = Colors.white.withValues(alpha: .75),
                    )),
                // Dark fill so the poster overlaps a solid shape.
                Text(label,
                    style: TextStyle(
                      fontSize: fontSize,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: wide ? -14 : -4,
                      color: Ui.bg,
                    )),
              ],
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: NfRow.posterW,
            child: NfPoster(movie: movie, onTap: onTap),
          ),
        ],
      ),
    );
  }
}

/// Outlined pill used under the top bar ("Series", "Movies", "Categories").
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: .22)
              : Colors.black.withValues(alpha: .25),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
              color: Colors.white.withValues(alpha: selected ? .9 : .55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600)),
            if (dropdown) ...[
              const SizedBox(width: 2),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}
