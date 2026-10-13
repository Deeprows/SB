import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/movie.dart';
import '../theme/app_theme.dart';

class MovieCard extends StatelessWidget {
  final Movie movie;
  final VoidCallback onTap;
  const MovieCard({super.key, required this.movie, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Ui.radius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: MoviePoster(movie: movie, badges: true)),
            const SizedBox(height: 8),
            Text(
              movie.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, height: 1.2, fontWeight: FontWeight.w800),
            ),
            if (movie.year != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  movie.isSeries ? 'Series · ${movie.year}' : movie.year!,
                  style: TextStyle(
                      color: Ui.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600),
                ),
              )
            else if (movie.isSeries)
              Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text('Series',
                    style: TextStyle(
                        color: Ui.muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Poster image with a gradient + initials fallback (many titles have no image
/// and remote images can fail).
class MoviePoster extends StatelessWidget {
  final Movie movie;
  final bool badges;
  const MoviePoster({super.key, required this.movie, this.badges = false});

  static const _palettes = <List<Color>>[
    [Color(0xFF3A0F1E), Color(0xFF13111F)],
    [Color(0xFF0F2A3A), Color(0xFF0E1420)],
    [Color(0xFF1F2E12), Color(0xFF0D1510)],
    [Color(0xFF2E1B3F), Color(0xFF110F1E)],
    [Color(0xFF3A2A0F), Color(0xFF16110C)],
    [Color(0xFF0F3A33), Color(0xFF0B1517)],
  ];

  Widget _fallback() {
    final pal = _palettes[movie.name.hashCode.abs() % _palettes.length];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: pal,
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(initialsOf(movie.title),
              style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: Colors.white.withValues(alpha: .55))),
          const SizedBox(height: 4),
          Icon(Icons.movie_outlined,
              size: 18, color: Colors.white.withValues(alpha: .35)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Ui.radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (movie.hasImage)
            movie.image.startsWith('data:image')
                ? Image.memory(
                    UriData.parse(movie.image).contentAsBytes(),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => _fallback(),
                  )
                : CachedNetworkImage(
                    imageUrl: movie.image,
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 150),
                    placeholder: (_, _) => _fallback(),
                    errorWidget: (_, _, _) => _fallback(),
                  )
          else
            _fallback(),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Ui.radius),
              border: Border.all(color: Colors.white.withValues(alpha: .08)),
            ),
          ),
          if (badges && movie.rating != null)
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded,
                        size: 12, color: Color(0xFFFFC107)),
                    const SizedBox(width: 3),
                    Text(movie.rating!,
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ),
          if (badges)
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Ui.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Ui.red.withValues(alpha: .5), blurRadius: 12)
                  ],
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
        ],
      ),
    );
  }
}

/// "The Dark Knight" -> "TD", "Dune" -> "DUN". Shown when a poster is missing.
String initialsOf(String name) {
  final letters = RegExp(r'[A-Za-z\u00C0-\u00FF]');
  final words =
      name.split(RegExp(r'\s+')).where((w) => letters.hasMatch(w)).toList();
  if (words.isEmpty) return '?';
  String clean(String w) =>
      w.replaceAll(RegExp(r'[^A-Za-z\u00C0-\u00FF]'), '');
  if (words.length == 1) {
    final w = clean(words.first);
    return w.substring(0, w.length < 3 ? w.length : 3).toUpperCase();
  }
  return (clean(words[0])[0] + clean(words[1])[0]).toUpperCase();
}
