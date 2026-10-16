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
import '../widgets/glass.dart';
import '../widgets/movie_card.dart' show MoviePoster, initialsOf;
import '../widgets/download_notice.dart';
import '../widgets/profile_sheets.dart';
import '../widgets/rate_this.dart';
import '../services/download_manager.dart';
import 'browser_screen.dart' show openInApp, isDirectFileLink;
import 'downloads_screen.dart';
import 'trailer_screen.dart';
import 'community_composer.dart';

/// Netflix-style title page: big artwork with a play button, title, match /
/// year / length row, white Play and grey Download buttons, synopsis, cast,
/// My List / Share, and the "More Like This" / "Details" tabs.
class TitlePage extends StatefulWidget {
  final Movie movie;
  const TitlePage({super.key, required this.movie});

  @override
  State<TitlePage> createState() => _TitlePageState();
}

class _TitlePageState extends State<TitlePage> {
  MovieInfo? _info;
  bool _infoLoading = false;
  List<Movie>? _similar;
  int _tab = 0; // 0 = More Like This, 1 = Details
  bool _more = false;

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

  void _openTrailer([int index = 0]) {
    final t = _info?.trailers ?? const <Trailer>[];
    if (t.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TrailerScreen(
        title: widget.movie.title,
        trailers: t,
        initial: index,
      ),
    ));
  }

  /// A direct file link downloads right away inside the app; anything else
  /// (a download page) opens in the in-app browser, which picks up the file
  /// and offers it for download as soon as it finds one.
  Future<void> _download() async {
    final m = widget.movie;
    if (!isDirectFileLink(m.downloadUrl)) {
      return openInApp(context, m.downloadUrl, title: m.title, blockAds: true);
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text('Starting download…'.tr),
          duration: const Duration(seconds: 20)));
    final uri = Uri.tryParse(m.downloadUrl);
    final seg = (uri?.pathSegments.isNotEmpty ?? false) ? uri!.pathSegments.last : '';
    final dot = seg.lastIndexOf('.');
    final ext = dot > 0 ? seg.substring(dot) : '.mp4';
    final error = await DownloadManager.instance
        .enqueue(m.downloadUrl, name: sanitizeFileName('${m.title}$ext'));
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    if (await DownloadManager.instance.takeInAppNotice()) {
      if (!mounted) return;
      final view = await showInAppDownloadNotice(context);
      if (!mounted) return;
      if (view) {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const DownloadsScreen(),
        ));
        return;
      }
    }
    messenger.showSnackBar(SnackBar(
      content: Text('Download started'.tr),
      action: SnackBarAction(
        label: 'VIEW',
        textColor: Ui.redSoft,
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const DownloadsScreen(),
        )),
      ),
    ));
  }

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
    final directors = info?.directors ?? const <String>[];
    final hasTrailer = info?.mainTrailer != null;

    return Scaffold(
      backgroundColor: Ui.bg,
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.zero,
            children: [
              _hero(w * .9, hasTrailer),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.title,
                        style: const TextStyle(
                            fontSize: 30,
                            height: 1.05,
                            letterSpacing: -.8,
                            fontWeight: FontWeight.w900)),
                    if ((info?.tagline ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(info!.tagline,
                          style: TextStyle(
                              color: Ui.redSoft,
                              fontSize: 13.5,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w600)),
                    ],
                    const SizedBox(height: 14),
                    _metaRow(info),
                    const SizedBox(height: 20),
                    GradientButton(
                      label: 'Play'.tr,
                      icon: Icons.play_arrow_rounded,
                      onTap: _play,
                    ),
                    if (hasTrailer || m.hasDownload) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (hasTrailer)
                            Expanded(
                              child: GlassButton(
                                label: 'Trailer'.tr,
                                icon: Icons.movie_creation_outlined,
                                onTap: _openTrailer,
                              ),
                            ),
                          if (hasTrailer && m.hasDownload)
                            const SizedBox(width: 10),
                          if (m.hasDownload)
                            Expanded(
                              child: GlassButton(
                                label: 'Download'.tr,
                                icon: Icons.download_rounded,
                                onTap: _download,
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (overview.isNotEmpty) _overview(overview),
                    if (_infoLoading && overview.isEmpty) ...[
                      for (final f in const [1.0, 1.0, .6]) _bar(f),
                    ],
                    if (directors.isNotEmpty)
                      _credit(
                          m.isSeries ? 'Creators'.tr : 'Director'.tr,
                          directors.take(3).join(', ')),
                    const SizedBox(height: 14),
                    _actionRow(),
                    const SizedBox(height: 20),
                    RateThis(movie: m),
                  ],
                ),
              ),
              if ((info?.trailers.length ?? 0) > 0) ...[
                const SizedBox(height: 26),
                _sectionTitle('Trailers & Videos'.tr),
                _trailerRow(info!.trailers),
              ],
              if ((info?.cast.length ?? 0) > 0) ...[
                const SizedBox(height: 26),
                _sectionTitle('Cast'.tr),
                _castRow(info!.cast),
              ],
              const SizedBox(height: 26),
              _tabs(),
              if (_tab == 0) _moreLikeThis() else _details(info),
              SizedBox(height: 32 + MediaQuery.of(context).padding.bottom),
            ],
          ),
          // Back button over the artwork.
          Positioned(
            top: top + 8,
            left: 14,
            child: GlassIconButton(
              icon: Icons.arrow_back_rounded,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ parts

  Widget _hero(double h, bool hasTrailer) {
    final m = widget.movie;
    final backdrop = _info?.backdrop ?? '';
    return GestureDetector(
      onTap: hasTrailer ? _openTrailer : _play,
      child: SizedBox(
        height: h,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(34)),
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
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0, .25, .65, 1],
                        colors: [
                          Colors.black.withValues(alpha: .6),
                          Colors.transparent,
                          Ui.bg.withValues(alpha: .35),
                          Ui.bg,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Big glass play button; with a trailer it plays the trailer.
            Center(
              child: Glass(
                radius: 40,
                blur: 16,
                tint: Colors.black.withValues(alpha: .30),
                child: const SizedBox(
                  width: 72,
                  height: 72,
                  child: Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 46),
                ),
              ),
            ),
            if (hasTrailer)
              Positioned(
                left: 0,
                right: 0,
                bottom: 18,
                child: Center(
                  child: Glass(
                    radius: 99,
                    blur: 14,
                    tint: Colors.black.withValues(alpha: .35),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    child: Text('Watch trailer'.tr,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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
            Text(t,
                style: const TextStyle(
                    fontSize: 18,
                    letterSpacing: -.2,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      );

  /// Horizontal row of video thumbnails (TMDB trailers, teasers, clips).
  Widget _trailerRow(List<Trailer> list) => SizedBox(
        height: 140,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final t = list[i];
            return GestureDetector(
              onTap: () => _openTrailer(i),
              child: SizedBox(
                width: 220,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: t.thumbnail,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => ColoredBox(color: Ui.card),
                              errorWidget: (_, _, _) =>
                                  ColoredBox(color: Ui.card),
                            ),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: .5),
                                  ],
                                ),
                              ),
                            ),
                            Center(
                              child: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  gradient: Ui.gradient,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                        color: Ui.red.withValues(alpha: .5),
                                        blurRadius: 14)
                                  ],
                                ),
                                child: Icon(Icons.play_arrow_rounded,
                                    color: Ui.palette.onAccent, size: 28),
                              ),
                            ),
                            Positioned(
                              left: 8,
                              top: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: .6),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(t.type,
                                    style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Ui.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            );
          },
        ),
      );

  /// Round cast photos with the actor's name and role underneath.
  Widget _castRow(List<CastMember> cast) => SizedBox(
        height: 128,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: cast.length > 14 ? 14 : cast.length,
          separatorBuilder: (_, _) => const SizedBox(width: 14),
          itemBuilder: (_, i) {
            final c = cast[i];
            return SizedBox(
              width: 74,
              child: Column(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Ui.card,
                      border: Border.all(color: Ui.glassLine, width: 1.5),
                    ),
                    child: ClipOval(
                      child: c.hasPhoto
                          ? CachedNetworkImage(
                              imageUrl: c.photo,
                              fit: BoxFit.cover,
                              memCacheWidth: 200,
                              errorWidget: (_, _, _) => _avatarFallback(c.name),
                            )
                          : _avatarFallback(c.name),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(c.name,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.15,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            );
          },
        ),
      );

  Widget _avatarFallback(String name) => Center(
        child: Text(initialsOf(name),
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.white.withValues(alpha: .5))),
      );

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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star_rounded, size: 17, color: Color(0xFFFFC107)),
              const SizedBox(width: 3),
              Text(score.toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w900)),
            ],
          ),
        for (final f in facts) Text(f, style: grey()),
        _badge(m.isSeries ? 'Series'.tr : 'Movie'.tr),
        _badge('HD', filled: true),
      ],
    );
  }

  Widget _badge(String t, {bool filled = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          gradient: filled ? Ui.gradient : null,
          color: filled ? null : Colors.white.withValues(alpha: .09),
          border: filled ? null : Border.all(color: Ui.glassLine),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(t,
            style: TextStyle(
                color: filled ? Ui.palette.onAccent : Ui.muted,
                fontSize: 11,
                fontWeight: FontWeight.w800)),
      );

  Widget _overview(String text) {
    final long = text.length > 180;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text,
            maxLines: _more ? null : 4,
            overflow: _more ? TextOverflow.visible : TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 14.5,
                height: 1.5,
                color: Colors.white.withValues(alpha: .88))),
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

  /// My List / Share as round glass buttons with a label underneath.
  Widget _actionRow() {
    return Wrap(
      spacing: 18,
      runSpacing: 14,
      children: [
        ListenableBuilder(
          listenable: MovieLibrary.instance,
          builder: (context, _) {
            final saved = MovieLibrary.instance.isSaved(widget.movie);
            return _Action(
              icon: saved ? Icons.check_rounded : Icons.add_rounded,
              label: 'My List'.tr,
              active: saved,
              onTap: () => _toggleList(context),
            );
          },
        ),
        _Action(
            icon: Icons.format_list_bulleted_rounded,
            label: 'Lists'.tr,
            onTap: () => showAddToListSheet(context, widget.movie)),
        _Action(
            icon: Icons.rate_review_outlined,
            label: 'Review'.tr,
            onTap: () => showReviewDialog(context, widget.movie)),
        _Action(
            icon: Icons.check_circle_outline_rounded,
            label: 'Check in'.tr,
            onTap: () => doCheckIn(context, widget.movie)),
        _Action(
            icon: Icons.forum_outlined,
            label: 'Tweet'.tr,
            onTap: () =>
                showCommunityComposer(context, movie: widget.movie)),
        _Action(icon: Icons.ios_share_rounded, label: 'Share'.tr, onTap: _share),
      ],
    );
  }

  /// More Like This | Details as a segmented glass control.
  Widget _tabs() {
    Widget tab(String label, int i) {
      final on = _tab == i;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _tab = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              gradient: on ? Ui.gradient : null,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: on ? Ui.palette.onAccent : Ui.muted)),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Ui.glassLine),
        ),
        child: Row(children: [
          tab('More Like This'.tr, 0),
          tab('Details'.tr, 1),
        ]),
      ),
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
          child: _poster(s, radius: 14),
        ),
    ], count);
  }

  Widget _grid(List<Widget> tiles, int count) => GridView.count(
        crossAxisCount: count,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 2 / 3,
        children: [
          for (final t in tiles)
            ClipRRect(borderRadius: BorderRadius.circular(14), child: t),
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
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
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
  final bool active;
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: active ? Ui.gradient : null,
              color: active ? null : Colors.white.withValues(alpha: .09),
              shape: BoxShape.circle,
              border: active ? null : Border.all(color: Ui.glassLine),
            ),
            child: Icon(icon,
                size: 24, color: active ? Ui.palette.onAccent : Colors.white),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  color: Ui.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
