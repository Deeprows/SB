import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/movie.dart';
import '../models/movie_info.dart';
import '../services/movie_library.dart';
import '../services/remote_config.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../utils/l10n.dart';
import '../utils/open_movie.dart';
import '../widgets/movie_card.dart' show MoviePoster, initialsOf;
import 'browser_screen.dart' show openInApp;

/// Netflix-style title page: big artwork with a play button, title, match /
/// year / length row, white Play and grey Download buttons, synopsis, cast,
/// My List / Share, and the "More Like This" / "Details" tabs.
class TitleScreen extends StatefulWidget {
  final Movie movie;
  const TitleScreen({super.key, required this.movie});

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> {
  MovieInfo? _info;
  bool _infoLoading = false;
  List<Movie>? _similar;
  int _tab = 0; // 0 = More Like This, 1 = Details
  bool _more = false;

  static const _netflixGrey = Color(0xFF2A2A2A);

  @override
  void initState() {
    super.initState();
    if (TmdbService.enabled) {
      _infoLoading = true;
      tmdb.info(widget.movie).then((i) {
        if (!mounted) return;
        setState(() {
          _info = i;
          _infoLoading = false;
        });
      });
    }
    _loadSimilar();
  }

  // ------------------------------------------------------------------ data

  String _key(Movie m) => m.tmdbId != null
      ? '${m.isSeries ? 'tv' : 'movie'}:${m.tmdbId}'
      : m.title.toLowerCase();

  /// "More Like This": popular titles from the same categories.
  Future<void> _loadSimilar() async {
    final me = widget.movie;
    final out = <Movie>[];
    final seen = <String>{_key(me)};
    void add(Iterable<Movie> list) {
      for (final m in list) {
        if (out.length >= 18) return;
        if (!m.hasImage) continue;
        if (seen.add(_key(m))) out.add(m);
      }
    }

    try {
      if (TmdbService.enabled) {
        for (final g in me.genres.take(3)) {
          if (out.length >= 18) break;
          add(await tmdb.discover(g));
        }
        if (out.length < 9) add(await tmdb.trending());
      }
    } catch (_) {}
    if (mounted) setState(() => _similar = out);
  }

  // --------------------------------------------------------------- actions

  void _play() => openMoviePlayer(context, widget.movie);

  Future<void> _download() => openInApp(context, widget.movie.downloadUrl,
      title: widget.movie.title, blockAds: true);

  Future<void> _share() async {
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    try {
      await Share.share(
        '${widget.movie.title}\n\n${RemoteConfig.instance.shareText}',
        sharePositionOrigin: origin,
      );
    } catch (_) {}
  }

  Future<void> _toggleList(BuildContext c) async {
    final now = await MovieLibrary.instance.toggleWatchLater(widget.movie);
    if (!c.mounted) return;
    ScaffoldMessenger.of(c)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(now ? 'Added to My List'.tr : 'Removed from My List'.tr)));
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final m = widget.movie;
    final info = _info;
    final w = MediaQuery.of(context).size.width;
    final top = MediaQuery.of(context).padding.top;

    final overview = info?.overview ?? '';
    final cast = info?.cast.map((c) => c.name).take(4).toList() ?? const [];
    final directors = info?.directors ?? const <String>[];

    return Scaffold(
      backgroundColor: Ui.bg,
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.zero,
            children: [
              _hero(w * .82),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.title,
                        style: const TextStyle(
                            fontSize: 26,
                            height: 1.1,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    _metaRow(info),
                    const SizedBox(height: 16),
                    _playButton(),
                    if (m.hasDownload) ...[
                      const SizedBox(height: 8),
                      _downloadButton(),
                    ],
                    const SizedBox(height: 16),
                    if (overview.isNotEmpty) _overview(overview),
                    if (_infoLoading && overview.isEmpty) ...[
                      for (final f in const [1.0, 1.0, .6]) _bar(f),
                    ],
                    if (cast.isNotEmpty)
                      _credit('Cast'.tr, '${cast.join(', ')}…'),
                    if (directors.isNotEmpty)
                      _credit(
                          m.isSeries ? 'Creators'.tr : 'Director'.tr,
                          directors.take(3).join(', ')),
                    const SizedBox(height: 18),
                    _actionRow(),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _tabs(),
              if (_tab == 0) _moreLikeThis() else _details(info),
              SizedBox(height: 28 + MediaQuery.of(context).padding.bottom),
            ],
          ),
          // Back button over the artwork.
          Positioned(
            top: top + 6,
            left: 8,
            child: _RoundIcon(
              icon: Icons.arrow_back_rounded,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ parts

  Widget _hero(double h) {
    final m = widget.movie;
    final backdrop = _info?.backdrop ?? '';
    return GestureDetector(
      onTap: _play,
      child: SizedBox(
        height: h,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (backdrop.startsWith('http'))
              CachedNetworkImage(
                imageUrl: backdrop,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                fadeInDuration: const Duration(milliseconds: 250),
                placeholder: (_, _) => ColoredBox(color: Ui.card),
                errorWidget: (_, _, _) => ColoredBox(color: Ui.card),
              )
            else
              _poster(m, radius: 0, alignment: Alignment.topCenter),
            // Dark fade at the top (for the back button) and into the page.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, .28, .62, 1],
                  colors: [
                    Colors.black.withValues(alpha: .65),
                    Colors.transparent,
                    Ui.bg.withValues(alpha: .35),
                    Ui.bg,
                  ],
                ),
              ),
            ),
            Center(
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .45),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 44),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "87% Match  2026  1h 44m  HD"
  Widget _metaRow(MovieInfo? info) {
    final m = widget.movie;
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
    TextStyle grey() => TextStyle(
        color: Ui.muted, fontSize: 14, fontWeight: FontWeight.w600);
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (score != null)
          Text('${(score * 10).round()}% ${'Match'.tr}',
              style: TextStyle(
                  color: Ui.green, fontSize: 14, fontWeight: FontWeight.w900)),
        for (final f in facts) Text(f, style: grey()),
        _badge(m.isSeries ? 'Series'.tr : 'Movie'.tr),
        _badge('HD'),
      ],
    );
  }

  Widget _badge(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: Ui.muted.withValues(alpha: .8)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(t,
            style: TextStyle(
                color: Ui.muted, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  Widget _playButton() => SizedBox(
        height: 46,
        child: FilledButton.icon(
          onPressed: _play,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          icon: const Icon(Icons.play_arrow_rounded, size: 30),
          label: Text('Play'.tr,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      );

  Widget _downloadButton() => SizedBox(
        height: 46,
        child: FilledButton.icon(
          onPressed: _download,
          style: FilledButton.styleFrom(
            backgroundColor: _netflixGrey,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          icon: const Icon(Icons.download_rounded, size: 24),
          label: Text('Download'.tr,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      );

  Widget _overview(String text) {
    final long = text.length > 180;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text,
            maxLines: _more ? null : 4,
            overflow: _more ? TextOverflow.visible : TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, height: 1.4)),
        if (long)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _more = !_more),
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_more ? 'Less'.tr : 'More'.tr,
                  style: TextStyle(
                      color: Ui.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _credit(String label, String value) => Padding(
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

  Widget _bar(double f) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: FractionallySizedBox(
          widthFactor: f,
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

  /// My List / Share, icon over label, like Netflix.
  Widget _actionRow() {
    return Row(
      children: [
        ListenableBuilder(
          listenable: MovieLibrary.instance,
          builder: (context, _) {
            final saved = MovieLibrary.instance.isSaved(widget.movie);
            return _Action(
              icon: saved ? Icons.check_rounded : Icons.add_rounded,
              label: 'My List'.tr,
              onTap: () => _toggleList(context),
            );
          },
        ),
        const SizedBox(width: 30),
        _Action(icon: Icons.send_outlined, label: 'Share'.tr, onTap: _share),
      ],
    );
  }

  /// MORE LIKE THIS | DETAILS, with the accent bar above the active one.
  Widget _tabs() {
    Widget tab(String label, int i) {
      final on = _tab == i;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _tab = i),
        child: Padding(
          padding: const EdgeInsets.only(right: 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 3,
                width: on ? 44 : 0,
                color: Ui.red,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(label.toUpperCase(),
                    style: TextStyle(
                        fontSize: 13.5,
                        letterSpacing: .4,
                        fontWeight: FontWeight.w800,
                        color: on ? Colors.white : Ui.dim)),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        tab('More Like This'.tr, 0),
        tab('Details'.tr, 1),
      ]),
    );
  }

  Widget _moreLikeThis() {
    final list = _similar;
    const count = 3;
    if (list == null) {
      return _grid([
        for (var i = 0; i < 6; i++) ColoredBox(color: Ui.card),
      ], count);
    }
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: Text('Nothing similar to show yet.'.tr,
              style: TextStyle(color: Ui.dim, fontSize: 13)),
        ),
      );
    }
    return _grid([
      for (final s in list)
        GestureDetector(
          onTap: () => openMovieTitle(context, s),
          child: _poster(s, radius: 4),
        ),
    ], count);
  }

  Widget _grid(List<Widget> tiles, int count) => GridView.count(
        crossAxisCount: count,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2 / 3,
        children: [
          for (final t in tiles)
            ClipRRect(borderRadius: BorderRadius.circular(4), child: t),
        ],
      );

  Widget _details(MovieInfo? info) {
    final m = widget.movie;
    final genres = (info != null && info.genres.isNotEmpty)
        ? info.genres
        : m.genres;
    final rows = <MapEntry<String, String>>[
      if (genres.isNotEmpty)
        MapEntry('Genres'.tr, genres.map((g) => g.tr).join(', ')),
      if (info != null && info.releaseDate.isNotEmpty)
        MapEntry(m.isSeries ? 'First aired'.tr : 'Released'.tr,
            info.releaseDate),
      if (info != null && info.runtimeText.isNotEmpty)
        MapEntry(m.isSeries ? 'Episode'.tr : 'Runtime'.tr, info.runtimeText),
      if (info != null && info.language.isNotEmpty)
        MapEntry('Language'.tr, info.language),
      if (info != null && info.status.isNotEmpty)
        MapEntry('Status'.tr, info.status),
      if (m.rating != null) MapEntry('Rating'.tr, '${m.rating} / 10'),
      if (info != null && info.directors.isNotEmpty)
        MapEntry(m.isSeries ? 'Creators'.tr : 'Director'.tr,
            info.directors.take(3).join(', ')),
      if (info != null && info.cast.isNotEmpty)
        MapEntry('Cast'.tr, info.cast.take(12).map((c) => c.name).join(', ')),
    ];
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: Text(
              _infoLoading ? 'Loading…'.tr : 'No more details available.'.tr,
              style: TextStyle(color: Ui.dim, fontSize: 13)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.key,
                      style: TextStyle(
                          color: Ui.dim,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(r.value,
                      style: const TextStyle(fontSize: 14, height: 1.35)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Poster that fills its box (square corners; the caller rounds them).
  Widget _poster(Movie m, {double radius = 0, Alignment alignment = Alignment.center}) {
    if (m.image.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: m.image,
        fit: BoxFit.cover,
        alignment: alignment,
        memCacheWidth: 500,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (_, _) => ColoredBox(color: Ui.card),
        errorWidget: (_, _, _) => ColoredBox(
          color: Ui.card,
          child: Center(
            child: Text(initialsOf(m.title),
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white.withValues(alpha: .4))),
          ),
        ),
      );
    }
    return MoviePoster(movie: m);
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Action({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26),
            const SizedBox(height: 5),
            Text(label,
                style: TextStyle(
                    color: Ui.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: .5),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, size: 24),
        ),
      ),
    );
  }
}
