import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../models/movie.dart';
import '../services/content_sync.dart';
import '../services/feed_service.dart';
import '../services/locale_service.dart';
import '../services/movie_library.dart';
import '../services/support_gate.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../utils/l10n.dart';
import '../utils/open_movie.dart';
import '../widgets/app_refresh.dart';
import '../widgets/netflix_widgets.dart';
import 'library_screen.dart';

/// Netflix-style home: a big billboard for today's top title, then rows
/// (Continue Watching, Trending Now, Top 10, My List, categories...).
/// Searching or picking Series / Movies / a category switches to a poster grid.
class MoviesScreen extends StatefulWidget {
  const MoviesScreen({super.key});

  @override
  State<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends State<MoviesScreen> {
  List<Movie> _all = const [];
  List<Movie> _trending = const []; // TMDB trending, most popular first
  bool _loading = true;
  String _query = '';
  String? _genre;
  String? _type; // null = all, 'movie' or 'tv'
  List<Movie> _found = const []; // TMDB search results
  final Map<String, List<Movie>> _discover = {}; // TMDB titles per category
  bool _discovering = false;
  bool _searching = false;
  bool _solid = false; // top bar turns solid after scrolling past the billboard
  Timer? _debounce;
  final _search = TextEditingController();
  final _sc = ScrollController();

  // The row order is shuffled once per day (local midnight).
  Timer? _midnight;
  int _dayKey = _today();

  static int _today() {
    final n = DateTime.now();
    return n.year * 10000 + n.month * 100 + n.day;
  }

  /// Rebuilds the front page when the day changes while the app is open.
  void _armMidnight() {
    _midnight?.cancel();
    final n = DateTime.now();
    final next = DateTime(n.year, n.month, n.day + 1, 0, 0, 2);
    _midnight = Timer(next.difference(n), () {
      if (!mounted) return;
      setState(() => _dayKey = _today());
      _armMidnight();
    });
  }

  /// Same title, same day -> same number, so the order holds all day and
  /// changes tomorrow. New titles added meanwhile don't reshuffle the rest.
  int _dayRank(Movie m) {
    var h = 0x811C9DC5;
    for (final c in '$_dayKey|${m.url}'.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (AppConfig.moviesUrl.isNotEmpty) _load(remote: true);
    });
    _loadTrending();
    ContentSync.tick.addListener(_onSync);
    AppLocale.notifier.addListener(_onLanguage);
    MovieLibrary.instance
      ..load()
      ..addListener(_onLibrary);
    _sc.addListener(() {
      final s = _sc.hasClients && _sc.offset > 70;
      if (s != _solid && mounted) setState(() => _solid = s);
    });
    _armMidnight();
  }

  void _onLibrary() {
    if (mounted) setState(() {});
  }

  void _onSync() {
    // Coming back to the app after midnight: pick up the new day's order.
    if (_dayKey != _today()) setState(() => _dayKey = _today());
    if (_loading) {
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted && !_loading) _load(remote: true);
      });
      return;
    }
    _load(remote: true);
  }

  /// New app language: reload so titles and descriptions follow it.
  void _onLanguage() {
    _discover.clear();
    if (_genre != null) _fetchDiscover();
    if (_query.trim().length >= 2) _onQuery(_query);
    _load().then((_) => _load(remote: true));
    _loadTrending();
  }

  @override
  void dispose() {
    ContentSync.tick.removeListener(_onSync);
    AppLocale.notifier.removeListener(_onLanguage);
    MovieLibrary.instance.removeListener(_onLibrary);
    _debounce?.cancel();
    _midnight?.cancel();
    _search.dispose();
    _sc.dispose();
    super.dispose();
  }

  Future<void> _load({bool remote = false}) async {
    final list = await feed.loadMovies(remote: remote);
    if (!mounted) return;
    setState(() {
      _all = list;
      _loading = false;
    });
  }

  /// Saved copy first (instant), then a fresh one.
  Future<void> _loadTrending() async {
    if (!TmdbService.enabled || !AppConfig.tmdbTrending) return;
    try {
      final cached = await tmdb.trending(fetch: false);
      if (mounted && cached.isNotEmpty) setState(() => _trending = cached);
      final fresh = await tmdb.trending();
      if (mounted && fresh.isNotEmpty) setState(() => _trending = fresh);
    } catch (_) {}
  }

  /// Searches the whole TMDB catalogue shortly after typing stops.
  void _onQuery(String v) {
    setState(() => _query = v);
    _debounce?.cancel();
    if (!AppConfig.tmdbSearch || !TmdbService.enabled || v.trim().length < 2) {
      if (_found.isNotEmpty) setState(() => _found = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final res = await tmdb.search(v);
      if (!mounted || _query.trim() != v.trim()) return;
      setState(() => _found = res);
    });
  }

  void _pickGenre(String? g) {
    setState(() => _genre = (g == null || _genre == g) ? null : g);
    _fetchDiscover();
  }

  /// Loads TMDB's popular titles for the selected category.
  Future<void> _fetchDiscover({bool force = false}) async {
    final g = _genre;
    if (g == null || !AppConfig.tmdbCategories || !TmdbService.enabled) return;
    if (!force && _discover.containsKey(g)) return;
    setState(() => _discovering = true);
    final res = await tmdb.discover(g);
    if (!mounted) return;
    setState(() {
      _discover[g] = res;
      _discovering = false;
    });
  }

  List<String> get _genres {
    final counts = <String, int>{};
    for (final m in _all) {
      for (final g in m.genres) {
        counts[g] = (counts[g] ?? 0) + 1;
      }
    }
    final keys = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return keys.take(14).toList();
  }

  void _details(Movie m) {
    SupportGate.guard(context, () {
      if (!mounted) return;
      openMovieTitle(context, m);
    });
  }

  void _playNow(Movie m) {
    SupportGate.guard(context, () {
      if (!mounted) return;
      openMoviePlayer(context, m);
    });
  }

  Future<void> _toggleList(Movie m) async {
    final now = await MovieLibrary.instance.toggleWatchLater(m);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(now ? 'Added to My List'.tr : 'Removed from My List'.tr)));
  }

  void _closeSearch() {
    _search.clear();
    setState(() => _searching = false);
    _onQuery('');
  }

  void _openLibrary() => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const LibraryScreen(initialTab: 0),
      ));

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final grid = _searching || q.isNotEmpty || _genre != null || _type != null;
    final top = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        AppRefresh(
          onRefresh: () async {
            _discover.clear();
            await _load(remote: true);
            await _loadTrending();
            await _fetchDiscover(force: true);
            return !feed.lastRemoteFailed;
          },
          child: CustomScrollView(
            controller: _sc,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: grid ? _gridSlivers(q, top) : _homeSlivers(top),
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: _topBar(top, grid)),
      ],
    );
  }

  // ------------------------------------------------------------ top bar

  Widget _topBar(double top, bool grid) {
    final solid = _solid || grid;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: solid ? Ui.bg.withValues(alpha: .96) : null,
        gradient: solid
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: .78),
                  Colors.transparent,
                ],
              ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(4, top + 4, 4, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _searching ? _searchRow() : _brandRow(),
            if (!_searching) ...[
              const SizedBox(height: 4),
              _chips(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _brandRow() {
    final saved = MovieLibrary.instance.watchLater.length;
    return Row(
      children: [
        IconButton(
          tooltip: 'Menu',
          onPressed: () => Scaffold.of(context).openDrawer(),
          icon: const Icon(Icons.menu_rounded),
        ),
        Text('STREAMBOX',
            style: TextStyle(
              color: Ui.red,
              fontSize: 21,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w900,
              shadows: const [Shadow(color: Colors.black54, blurRadius: 8)],
            )),
        const Spacer(),
        IconButton(
          tooltip: 'Search',
          onPressed: () => setState(() => _searching = true),
          icon: const Icon(Icons.search_rounded, size: 27),
        ),
        IconButton(
          tooltip: 'My List',
          onPressed: _openLibrary,
          icon: Badge(
            isLabelVisible: saved > 0,
            label: Text('$saved'),
            backgroundColor: Ui.red,
            child: const Icon(Icons.bookmark_border_rounded, size: 26),
          ),
        ),
      ],
    );
  }

  Widget _searchRow() {
    return Row(
      children: [
        IconButton(
          onPressed: _closeSearch,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        Expanded(
          child: SizedBox(
            height: 42,
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: _onQuery,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search movies and series…'.tr,
                hintStyle: TextStyle(color: Ui.dim),
                prefixIcon: Icon(Icons.search_rounded, color: Ui.muted),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          _onQuery('');
                        },
                      ),
                filled: true,
                fillColor: Ui.card,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
      ],
    );
  }

  Widget _chips() {
    final filtered = _type != null || _genre != null;
    Widget gap(Widget w) =>
        Padding(padding: const EdgeInsets.only(right: 8), child: w);
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          if (filtered)
            gap(GestureDetector(
              onTap: () => setState(() {
                _type = null;
                _genre = null;
              }),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: .25),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .55)),
                ),
                child: const Icon(Icons.close_rounded, size: 18),
              ),
            )),
          if (_type == null || _type == 'tv')
            gap(NfChip(
              label: 'TV Shows'.tr,
              selected: _type == 'tv',
              onTap: () => setState(() => _type = _type == 'tv' ? null : 'tv'),
            )),
          if (_type == null || _type == 'movie')
            gap(NfChip(
              label: 'Movies'.tr,
              selected: _type == 'movie',
              onTap: () =>
                  setState(() => _type = _type == 'movie' ? null : 'movie'),
            )),
          gap(NfChip(
            label: _genre == null ? 'Categories'.tr : _genre!.tr,
            selected: _genre != null,
            dropdown: true,
            onTap: _showCategories,
          )),
        ],
      ),
    );
  }

  /// Full-height black list of categories, like Netflix's "Categories".
  void _showCategories() {
    final names = _genres;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Ui.bg.withValues(alpha: .97),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * .92,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 36),
                children: [
                  for (final g in <String?>[null, ...names])
                    InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickGenre(g);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        child: Center(
                          child: Text(
                            g == null ? 'All Categories'.tr : g.tr,
                            style: TextStyle(
                              fontSize: (g == _genre) ? 22 : 19,
                              fontWeight:
                                  (g == _genre) ? FontWeight.w900 : FontWeight.w500,
                              color: (g == _genre) ? Colors.white : Ui.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 22, top: 6),
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pop(ctx),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.close_rounded,
                        color: Colors.black, size: 26),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- home page

  List<Widget> _homeSlivers(double top) {
    final hero = _pickHero();
    final rows = _rows();
    return [
      SliverToBoxAdapter(
        child: hero == null
            ? SizedBox(height: top + 110)
            : _billboard(hero.$1, top, top10: hero.$2),
      ),
      if (_loading && _all.isEmpty && _trending.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator(color: Ui.red)),
        )
      else
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 28),
            child: Column(
              children: [
                for (final r in rows)
                  Padding(padding: const EdgeInsets.only(bottom: 24), child: r),
              ],
            ),
          ),
        ),
    ];
  }

  /// (title, isTrendingNumberOne)
  (Movie, bool)? _pickHero() {
    for (final m in _trending) {
      if (m.image.startsWith('http')) return (m, true);
    }
    final withArt = _all.where((m) => m.image.startsWith('http')).toList()
      ..sort((a, b) => _dayRank(a).compareTo(_dayRank(b)));
    return withArt.isEmpty ? null : (withArt.first, false);
  }

  /// TMDB posters come as w500; the billboard is bigger.
  String _big(String url) => url.replaceFirst('/w500/', '/w780/');

  Widget _billboard(Movie m, double top, {required bool top10}) {
    final w = MediaQuery.of(context).size.width;
    final saved = MovieLibrary.instance.isSaved(m);
    final genres = m.genres.take(3).map((g) => g.tr).join('  •  ');
    const shadow = [Shadow(color: Colors.black87, blurRadius: 10)];
    return SizedBox(
      height: w * 1.32,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: () => _details(m),
            child: CachedNetworkImage(
              imageUrl: _big(m.image),
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              fadeInDuration: const Duration(milliseconds: 300),
              placeholder: (_, _) => ColoredBox(color: Ui.card),
              errorWidget: (_, _, _) => ColoredBox(color: Ui.card),
            ),
          ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, .2, .55, 1],
                  colors: [
                    Colors.black.withValues(alpha: .7),
                    Colors.transparent,
                    Ui.bg.withValues(alpha: .5),
                    Ui.bg,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (top10)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Ui.red,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text('TOP\n10',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 8,
                                height: 1,
                                fontWeight: FontWeight.w900,
                                color: Ui.palette.onAccent)),
                      ),
                      const SizedBox(width: 8),
                      Text('#1 in Trending Today'.tr,
                          style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              shadows: shadow)),
                    ],
                  ),
                const SizedBox(height: 8),
                Text(m.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 34,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        shadows: shadow)),
                if (genres.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(genres,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          shadows: shadow)),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: FilledButton.icon(
                          onPressed: () => _playNow(m),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4)),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 28),
                          label: Text('Play'.tr,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: FilledButton.icon(
                          onPressed: () => _toggleList(m),
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                const Color(0xFF3A3A3A).withValues(alpha: .9),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4)),
                          ),
                          icon: Icon(
                              saved ? Icons.check_rounded : Icons.add_rounded,
                              size: 24),
                          label: Text('My List'.tr,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _rows() {
    final lib = MovieLibrary.instance;
    final out = <Widget>[];

    void add(String title, Iterable<Movie> src,
        {bool numbered = false, int min = 3, int max = 20}) {
      final seen = <String>{};
      final list = <Movie>[];
      for (final m in src) {
        if (!m.hasImage) continue;
        if (seen.add(m.url)) list.add(m);
        if (list.length >= max) break;
      }
      if (list.length < min) return;
      out.add(NfRow(
          title: title, movies: list, onTap: _details, numbered: numbered));
    }

    final rank = {for (final m in _all) m.url: _dayRank(m)};
    final ranked = [..._all]..sort((a, b) => rank[a.url]!.compareTo(rank[b.url]!));
    final newest = _all.where((m) => m.date != null).toList()
      ..sort((a, b) => b.date!.compareTo(a.date!));

    add('Continue Watching'.tr, lib.history.map((e) => e.movie));
    if (_trending.isNotEmpty) {
      add('Trending Now'.tr, _trending);
      add('Top 10 Today'.tr, _trending, numbered: true, max: 10, min: 5);
    } else {
      add('Popular on ${AppConfig.appName}', ranked);
    }
    add('My List'.tr, lib.watchLater);
    add('New on ${AppConfig.appName}', newest);
    add('Popular Movies'.tr, ranked.where((m) => !m.isSeries));
    add('TV Shows'.tr, ranked.where((m) => m.isSeries));
    for (final g in _genres.take(6)) {
      add(g.tr, ranked.where((m) => m.genres.contains(g)), min: 4);
    }
    return out;
  }

  // ------------------------------------------------------------- grid mode

  List<Widget> _gridSlivers(String q, double top) {
    bool typeOk(Movie m) => _type == null || m.isSeries == (_type == 'tv');
    bool genreOk(Movie m) => _genre == null || m.genres.contains(_genre);
    final filtered = _all.where((m) {
      if (!typeOk(m) || !genreOk(m)) return false;
      return q.isEmpty || m.name.toLowerCase().contains(q);
    }).toList();

    // TMDB titles from the search box and from the selected category come
    // after the ones in your own list.
    final urls = {for (final m in _all) m.url};
    final ids = {for (final m in _all) if (m.tmdbId != null) m.tmdbId};
    void addExtra(Movie m, {required bool matchName}) {
      if (!typeOk(m) || !genreOk(m)) return;
      if (matchName && q.isNotEmpty && !m.name.toLowerCase().contains(q)) {
        return;
      }
      if (urls.contains(m.url) || ids.contains(m.tmdbId)) return;
      urls.add(m.url);
      filtered.add(m);
    }

    if (q.isNotEmpty) {
      for (final m in _found) {
        addExtra(m, matchName: false);
      }
    }
    if (_genre != null) {
      for (final m in _discover[_genre] ?? const <Movie>[]) {
        addExtra(m, matchName: true);
      }
    }
    // Browsing (no search text): a fresh order every day. Searching keeps
    // the best matches first.
    if (q.isEmpty) {
      final rank = {for (final m in filtered) m.url: _dayRank(m)};
      filtered.sort((a, b) => rank[a.url]!.compareTo(rank[b.url]!));
    }

    return [
      SliverToBoxAdapter(
          child: SizedBox(height: top + (_searching ? 64 : 104))),
      if (_loading || (filtered.isEmpty && _discovering))
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator(color: Ui.red)),
        )
      else if (filtered.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off_rounded, size: 44, color: Ui.dim),
              const SizedBox(height: 10),
              Text('Nothing found'.tr,
                  style: TextStyle(
                      color: Ui.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 2 / 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => NfPoster(
                movie: filtered[i],
                onTap: () => _details(filtered[i]),
              ),
              childCount: filtered.length,
            ),
          ),
        ),
    ];
  }
}
