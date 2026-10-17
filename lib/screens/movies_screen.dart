import 'dart:async';
import 'dart:ui' show ImageFilter;

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
import '../widgets/latest_trailers_row.dart';
import '../widgets/app_refresh.dart';
import '../widgets/glass.dart';
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
  List<Movie> _popMovies = const []; // TMDB popular movies
  List<Movie> _popTv = const []; // TMDB popular series
  bool _homeRowsBusy = false;
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
  final _heroCtl = PageController();
  Timer? _heroTimer;
  int _heroPage = 0;
  int _heroCount = 0;

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
      _newDay();
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
    _loadPopular();
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
    // The billboard flips to the next title every few seconds.
    _heroTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted || _heroCount < 2 || !_heroCtl.hasClients) return;
      if (_sc.hasClients && _sc.offset > 200) return; // not visible
      _heroCtl.animateToPage((_heroPage + 1) % _heroCount,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic);
    });
  }

  void _onLibrary() {
    if (mounted) setState(() {});
  }

  void _onSync() {
    // Coming back to the app after midnight: pick up the new day's order.
    if (_dayKey != _today()) _newDay();
    if (_loading) {
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted && !_loading) _load(remote: true);
      });
      return;
    }
    _load(remote: true);
    _loadTrending();
    _loadPopular();
  }

  /// A new day: new shuffle and a fresh copy of every TMDB list.
  void _newDay() {
    setState(() => _dayKey = _today());
    _discover.clear();
    _loadTrending(force: true);
    _loadPopular(force: true);
    _fetchHomeRows();
    if (_genre != null) _fetchDiscover();
  }

  /// New app language: reload so titles and descriptions follow it.
  void _onLanguage() {
    _discover.clear();
    if (_genre != null) _fetchDiscover();
    if (_query.trim().length >= 2) _onQuery(_query);
    _load().then((_) => _load(remote: true));
    _loadTrending(force: true);
    _loadPopular(force: true);
  }

  @override
  void dispose() {
    ContentSync.tick.removeListener(_onSync);
    AppLocale.notifier.removeListener(_onLanguage);
    MovieLibrary.instance.removeListener(_onLibrary);
    _debounce?.cancel();
    _midnight?.cancel();
    _heroTimer?.cancel();
    _heroCtl.dispose();
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
    _fetchHomeRows();
  }

  /// Saved copy first (instant), then TMDB's live popular movies + series.
  Future<void> _loadPopular({bool force = false}) async {
    if (!TmdbService.enabled) return;
    try {
      final m = await tmdb.popular(tv: false, fetch: false);
      final t = await tmdb.popular(tv: true, fetch: false);
      if (mounted && (m.isNotEmpty || t.isNotEmpty)) {
        setState(() {
          if (m.isNotEmpty) _popMovies = m;
          if (t.isNotEmpty) _popTv = t;
        });
      }
      final fm = await tmdb.popular(tv: false, force: force);
      final ft = await tmdb.popular(tv: true, force: force);
      if (mounted) {
        setState(() {
          if (fm.isNotEmpty) _popMovies = fm;
          if (ft.isNotEmpty) _popTv = ft;
        });
      }
    } catch (_) {}
  }

  /// Fills the home category rows (the first six categories) with TMDB's
  /// popular titles of that category. Rows keep your own list until the
  /// TMDB titles arrive, or when TMDB can't be reached.
  Future<void> _fetchHomeRows() async {
    if (_homeRowsBusy) return;
    if (!AppConfig.tmdbCategories || !TmdbService.enabled) return;
    _homeRowsBusy = true;
    try {
      for (final g in _genres.take(6)) {
        if (_discover.containsKey(g)) continue;
        final res = await tmdb.discover(g);
        if (!mounted) return;
        if (res.isNotEmpty) setState(() => _discover[g] = res);
      }
    } finally {
      _homeRowsBusy = false;
    }
  }

  /// Saved copy first (instant), then a fresh one.
  Future<void> _loadTrending({bool force = false}) async {
    if (!TmdbService.enabled || !AppConfig.tmdbTrending) return;
    try {
      final cached = await tmdb.trending(fetch: false);
      if (mounted && cached.isNotEmpty) setState(() => _trending = cached);
      final fresh = await tmdb.trending(force: force);
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
            await _loadTrending(force: true);
            await _loadPopular(force: true);
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
    final content = Padding(
      padding: EdgeInsets.fromLTRB(14, top + 8, 14, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _searching ? _searchRow() : _brandRow(),
          if (!_searching) ...[
            const SizedBox(height: 10),
            _chips(),
          ],
        ],
      ),
    );
    if (solid) {
      return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Ui.bg.withValues(alpha: .80),
              border: Border(bottom: BorderSide(color: Ui.line)),
            ),
            child: content,
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: .72),
            Colors.transparent,
          ],
        ),
      ),
      child: content,
    );
  }

  Widget _brandRow() {
    return Row(
      children: [
        GlassIconButton(
          icon: Icons.menu_rounded,
          onTap: () => Scaffold.of(context).openDrawer(),
        ),
        const SizedBox(width: 12),
        // The DamiMovies logo mark (same badge as the splash screen).
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(color: Ui.red.withValues(alpha: .5), blurRadius: 12),
            ],
          ),
          child: Image.asset('assets/splash/logo_mark.png',
              fit: BoxFit.contain, filterQuality: FilterQuality.high),
        ),
        const SizedBox(width: 9),
        const Text('DamiMovies',
            style: TextStyle(
              fontSize: 21,
              letterSpacing: -.4,
              fontWeight: FontWeight.w900,
              shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
            )),
        const Spacer(),
        GlassIconButton(
          icon: Icons.search_rounded,
          onTap: () => setState(() => _searching = true),
        ),
        const SizedBox(width: 8),
        GlassIconButton(
          icon: MovieLibrary.instance.watchLater.isEmpty
              ? Icons.bookmark_border_rounded
              : Icons.bookmark_rounded,
          onTap: _openLibrary,
        ),
      ],
    );
  }

  Widget _searchRow() {
    return Row(
      children: [
        GlassIconButton(icon: Icons.arrow_back_rounded, onTap: _closeSearch),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 46,
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
                fillColor: Colors.white.withValues(alpha: .08),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Ui.glassLine),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Ui.glassLine),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Ui.red.withValues(alpha: .8)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chips() {
    final filtered = _type != null || _genre != null;
    Widget gap(Widget w) =>
        Padding(padding: const EdgeInsets.only(right: 8), child: w);
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        children: [
          if (filtered)
            gap(GestureDetector(
              onTap: () => setState(() {
                _type = null;
                _genre = null;
              }),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: .09),
                  border: Border.all(color: Ui.glassLine),
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

  /// Bottom sheet with every category as a tappable pill.
  void _showCategories() {
    final names = _genres;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Ui.panel,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .7),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Categories'.tr,
                    style: const TextStyle(
                        fontSize: 22,
                        letterSpacing: -.3,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final g in <String?>[null, ...names])
                      NfChip(
                        label: g == null ? 'All Categories'.tr : g.tr,
                        selected: g == _genre || (g == null && _genre == null),
                        onTap: () {
                          Navigator.pop(ctx);
                          _pickGenre(g);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- home page

  List<Widget> _homeSlivers(double top) {
    final heroes = _heroes();
    _heroCount = heroes.length;
    final rows = _rows();
    return [
      SliverToBoxAdapter(
        child: heroes.isEmpty
            ? SizedBox(height: top + 110)
            : _billboard(heroes, top),
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
                  Padding(
                      key: r.key,
                      padding: const EdgeInsets.only(bottom: 24),
                      child: r),
              ],
            ),
          ),
        ),
    ];
  }

  /// Up to five titles for the billboard: today's trending first, otherwise
  /// the day's shuffled picks. Each is (title, isTrending).
  List<(Movie, bool)> _heroes() {
    final out = <(Movie, bool)>[];
    for (final m in _trending) {
      if (m.image.startsWith('http')) out.add((m, true));
      if (out.length >= 5) return out;
    }
    if (out.isNotEmpty) return out;
    final withArt = _all.where((m) => m.image.startsWith('http')).toList()
      ..sort((a, b) => _dayRank(a).compareTo(_dayRank(b)));
    return [for (final m in withArt.take(5)) (m, false)];
  }

  /// TMDB posters come as w500; the billboard is bigger.
  String _big(String url) => url.replaceFirst('/w500/', '/w780/');

  Widget _billboard(List<(Movie, bool)> heroes, double top) {
    final w = MediaQuery.of(context).size.width;
    final h = w * 1.28;
    return SizedBox(
      height: h,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(34)),
            child: SizedBox(
              height: h,
              child: PageView.builder(
                controller: _heroCtl,
                itemCount: heroes.length,
                onPageChanged: (i) => setState(() => _heroPage = i),
                itemBuilder: (_, i) =>
                    _heroPageItem(heroes[i].$1, heroes[i].$2, i),
              ),
            ),
          ),
          // Page dots.
          if (heroes.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < heroes.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      height: 6,
                      width: i == _heroPage ? 22 : 6,
                      decoration: BoxDecoration(
                        gradient: i == _heroPage ? Ui.gradient : null,
                        color: i == _heroPage
                            ? null
                            : Colors.white.withValues(alpha: .3),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _heroPageItem(Movie m, bool trending, int index) {
    final saved = MovieLibrary.instance.isSaved(m);
    final genres = m.genres.take(3).map((g) => g.tr).join('  •  ');
    const shadow = [Shadow(color: Colors.black87, blurRadius: 12)];
    return Stack(
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
                stops: const [0, .22, .5, 1],
                colors: [
                  Colors.black.withValues(alpha: .7),
                  Colors.transparent,
                  Ui.bg.withValues(alpha: .55),
                  Ui.bg.withValues(alpha: .96),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 34,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      gradient: Ui.gradient,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                        trending
                            ? '#${index + 1} ${'Trending Today'.tr}'
                            : 'Featured'.tr,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Ui.palette.onAccent)),
                  ),
                  if (m.rating != null) ...[
                    const SizedBox(width: 8),
                    RatingPill(m.rating!),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text(m.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 34,
                      height: 1.04,
                      letterSpacing: -.8,
                      fontWeight: FontWeight.w900,
                      shadows: shadow)),
              if (genres.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(genres,
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: .85),
                        fontWeight: FontWeight.w600,
                        shadows: shadow)),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 11,
                    child: GradientButton(
                      label: 'Play'.tr,
                      icon: Icons.play_arrow_rounded,
                      onTap: () => _playNow(m),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 10,
                    child: GlassButton(
                      label: 'My List'.tr,
                      icon: saved ? Icons.check_rounded : Icons.add_rounded,
                      onTap: () => _toggleList(m),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
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
    // Latest Trailers sits right under Top 10 Today (or under the Popular
    // row when there is no Top 10 yet).
    if (TmdbService.enabled) {
      out.add(LatestTrailersRow(
          key: const ValueKey('latest-trailers'), onOpen: _details));
    }
    add('My List'.tr, lib.watchLater);
    add('New on ${AppConfig.appName}', newest);
    // Popular and category rows come from TMDB's live lists; your own list
    // is the fallback while they load or when TMDB can't be reached.
    add('Popular Movies'.tr,
        _popMovies.isNotEmpty ? _popMovies : ranked.where((m) => !m.isSeries));
    add('TV Shows'.tr,
        _popTv.isNotEmpty ? _popTv : ranked.where((m) => m.isSeries));
    for (final g in _genres.take(6)) {
      final live = _discover[g];
      add(g.tr,
          (live != null && live.isNotEmpty)
              ? live
              : ranked.where((m) => m.genres.contains(g)),
          min: 4);
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 2 / 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
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
