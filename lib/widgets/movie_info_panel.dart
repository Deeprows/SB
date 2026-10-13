import 'package:flutter/material.dart';

import '../models/movie.dart';
import '../models/movie_info.dart';
import '../theme/app_theme.dart';
import '../utils/l10n.dart';

/// Synopsis and credits of a movie / series page, laid out like Netflix:
/// plain white synopsis, then grey "Cast:", "Director:" and "Genres:" lines.
/// Everything except the genres comes from TMDB, so while it loads (or when
/// TMDB has nothing for the title) the page simply shows less.
class MovieInfoPanel extends StatefulWidget {
  final Movie movie;
  final MovieInfo? info;
  final bool loading;
  const MovieInfoPanel({
    super.key,
    required this.movie,
    required this.info,
    required this.loading,
  });

  @override
  State<MovieInfoPanel> createState() => _MovieInfoPanelState();
}

class _MovieInfoPanelState extends State<MovieInfoPanel> {
  bool _more = false;

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final genres = (info != null && info.genres.isNotEmpty)
        ? info.genres
        : widget.movie.genres;
    final overview = info?.overview ?? '';
    final cast = info?.cast.map((c) => c.name).take(6).toList() ?? const [];
    final directors = info?.directors ?? const <String>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (overview.isNotEmpty) ...[
            Text(
              overview,
              maxLines: _more ? null : 4,
              overflow: _more ? TextOverflow.visible : TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            if (overview.length > 180)
              GestureDetector(
                onTap: () => setState(() => _more = !_more),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_more ? 'Less'.tr : 'More'.tr,
                      style: TextStyle(
                          color: Ui.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                ),
              ),
            const SizedBox(height: 12),
          ] else if (widget.loading) ...[
            for (final w in const [1.0, 1.0, .6]) _bar(w),
          ],
          if (cast.isNotEmpty) _line('Cast'.tr, '${cast.join(', ')}…'),
          if (directors.isNotEmpty)
            _line(widget.movie.isSeries ? 'Creators'.tr : 'Director'.tr,
                directors.take(3).join(', ')),
          if (genres.isNotEmpty)
            _line('Genres'.tr, genres.take(5).map((g) => g.tr).join(', ')),
        ],
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
                text: '$label: ',
                style: TextStyle(color: Ui.dim, fontWeight: FontWeight.w700)),
            TextSpan(text: value, style: TextStyle(color: Ui.muted)),
          ]),
          style: const TextStyle(fontSize: 12.5, height: 1.4),
        ),
      );

  /// Grey placeholder line while the details load.
  Widget _bar(double width) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: FractionallySizedBox(
          widthFactor: width,
          alignment: Alignment.centerLeft,
          child: Container(
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      );
}
