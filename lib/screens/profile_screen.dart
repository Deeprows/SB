import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../models/movie.dart';
import '../services/auth_service.dart';
import '../services/movie_library.dart';
import '../services/profile_service.dart';
import '../services/rating_service.dart';
import '../services/support_gate.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../utils/l10n.dart';
import '../utils/open_movie.dart';
import '../widgets/app_drawer.dart' show confirmSignOut;
import '../widgets/netflix_widgets.dart';
import '../widgets/profile_sheets.dart';
import 'library_screen.dart';

const _gold = Color(0xFFFFC107);

String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';

void _openTitle(BuildContext context, Movie m) {
  SupportGate.guard(context, () {
    if (context.mounted) openMovieTitle(context, m);
  });
}

Future<void> _push(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

Widget _thumb(Movie m, {double w = 56, double h = 84}) => ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: w,
        height: h,
        child: m.image.startsWith('http')
            ? CachedNetworkImage(
                imageUrl: m.image,
                fit: BoxFit.cover,
                memCacheWidth: 240,
                errorWidget: (_, _, _) => ColoredBox(color: Ui.card),
              )
            : ColoredBox(
                color: Ui.card,
                child: Icon(Icons.movie_rounded, color: Ui.dim)),
      ),
    );

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  const _Empty({required this.icon, required this.title, required this.hint});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 52, color: Ui.dim),
              const SizedBox(height: 12),
              Text(title.tr,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(hint.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Ui.muted, fontSize: 13, height: 1.4)),
            ],
          ),
        ),
      );
}

class _Page extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget> actions;
  final Widget? fab;
  const _Page(
      {required this.title,
      required this.body,
      this.actions = const [],
      this.fab});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Ui.bg,
        appBar: AppBar(
          backgroundColor: Ui.bg,
          title: Text(title.tr,
              style: const TextStyle(fontWeight: FontWeight.w900)),
          actions: actions,
        ),
        floatingActionButton: fab,
        body: body,
      );
}

/// Poster grid; [badge] puts a small label on each poster, [onRemove] adds
/// the little close button.
class _PosterGrid extends StatelessWidget {
  final List<(Movie, String?)> items;
  final Future<void> Function(Movie)? onRemove;
  const _PosterGrid({required this.items, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 28),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2 / 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final (m, label) = items[i];
        return Stack(
          fit: StackFit.expand,
          children: [
            NfPoster(movie: m, onTap: () => _openTitle(context, m)),
            if (label != null)
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .72),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded, size: 13, color: _gold),
                      const SizedBox(width: 2),
                      Text(label,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              ),
            if (onRemove != null)
              Positioned(
                right: 4,
                top: 4,
                child: Material(
                  color: Colors.black.withValues(alpha: .65),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => onRemove!(m),
                    child: const Padding(
                      padding: EdgeInsets.all(5),
                      child: Icon(Icons.close_rounded, size: 15),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// =========================================================== main profile

/// Profile tab: avatar and name, then the nine sections laid out like the
/// IMDb profile menu.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    ProfileService.instance.load();
    RatingService.instance.load();
    MovieLibrary.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    final prof = ProfileService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([
        auth,
        prof,
        MovieLibrary.instance,
        RatingService.instance,
      ]),
      builder: (context, _) {
        final user = auth.user;
        final name = user?.name ?? 'Guest'.tr;
        final photo = user?.photoUrl;

        final tiles = <_Tile>[
          // Same order as the IMDb menu, read left to right, top to bottom.
          _Tile(Icons.star_rounded, 'Ratings',
              RatingService.instance.ratedMovies.length,
              () => _push(context, const _RatingsPage())),
          _Tile(Icons.history_rounded, 'Watch history',
              MovieLibrary.instance.history.length,
              () => _push(context, const LibraryScreen(initialTab: 1))),
          _Tile(Icons.interests_rounded, 'Interests', prof.interests.length,
              () => _push(context, const _InterestsPage())),
          _Tile(Icons.bookmark_rounded, 'Watchlist',
              MovieLibrary.instance.watchLater.length,
              () => _push(context, const LibraryScreen(initialTab: 0))),
          _Tile(Icons.rate_review_rounded, 'Reviews', prof.reviews.length,
              () => _push(context, const _ReviewsPage())),
          _Tile(Icons.military_tech_rounded, 'Badges', prof.earnedBadges,
              () => _push(context, const _BadgesPage())),
          _Tile(Icons.format_list_bulleted_rounded, 'Lists', prof.lists.length,
              () => _push(context, const _ListsPage())),
          _Tile(Icons.check_circle_outline_rounded, 'Check-ins',
              prof.checkIns.length,
              () => _push(context, const _CheckInsPage())),
          _Tile(Icons.people_alt_rounded, 'Favorite people', prof.people.length,
              () => _push(context, const _PeoplePage())),
        ];

        return Scaffold(
          backgroundColor: Ui.bg,
          body: SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Ui.card,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Ui.glassLine),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 38,
                        backgroundColor: Ui.cardDeep,
                        foregroundImage: (photo == null || photo.isEmpty)
                            ? null
                            : NetworkImage(photo),
                        child: Icon(Icons.person_rounded,
                            size: 46, color: Ui.dim),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -.3)),
                            if (user != null) ...[
                              const SizedBox(height: 3),
                              Text(user.email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: Ui.muted, fontSize: 12.5)),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.military_tech_rounded,
                                    size: 17, color: _gold),
                                const SizedBox(width: 4),
                                Text(
                                    '${prof.earnedBadges}/${prof.badges.length} ${'Badges'.tr}',
                                    style: TextStyle(
                                        color: Ui.muted,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.02,
                  children: [for (final t in tiles) _TileCard(tile: t)],
                ),
                if (AppConfig.loginRequired && user != null) ...[
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: () => confirmSignOut(context),
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: Text('Sign out'.tr),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Tile {
  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;
  const _Tile(this.icon, this.label, this.count, this.onTap);
}

class _TileCard extends StatelessWidget {
  final _Tile tile;
  const _TileCard({required this.tile});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: tile.onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Ui.glassLine),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(tile.icon, size: 26, color: Ui.redSoft),
              const SizedBox(height: 7),
              Text(tile.label.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('${tile.count}',
                  style: TextStyle(
                      color: Ui.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================ ratings

class _RatingsPage extends StatelessWidget {
  const _RatingsPage();

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Ratings',
      body: ListenableBuilder(
        listenable: RatingService.instance,
        builder: (context, _) {
          final rated = RatingService.instance.ratedMovies;
          if (rated.isEmpty) {
            return const _Empty(
              icon: Icons.star_border_rounded,
              title: 'No ratings yet',
              hint: 'Rate a movie or series on its page and it shows up here.',
            );
          }
          return _PosterGrid(items: [for (final (m, s) in rated) (m, '$s')]);
        },
      ),
    );
  }
}

// ================================================================== lists

class _ListsPage extends StatelessWidget {
  const _ListsPage();

  @override
  Widget build(BuildContext context) {
    final svc = ProfileService.instance;
    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) {
        final lists = svc.lists;
        return _Page(
          title: 'Lists',
          fab: FloatingActionButton.extended(
            backgroundColor: Ui.red,
            foregroundColor: Ui.palette.onAccent,
            onPressed: () async {
              final name = await askText(context,
                  title: 'New list'.tr, hint: 'List name'.tr);
              if (name != null && name.trim().isNotEmpty) {
                await svc.createList(name);
              }
            },
            icon: const Icon(Icons.add_rounded),
            label: Text('New list'.tr),
          ),
          body: lists.isEmpty
              ? const _Empty(
                  icon: Icons.format_list_bulleted_rounded,
                  title: 'No lists yet',
                  hint:
                      'Make a list, then add titles to it with the List button on any movie page.')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
                  itemCount: lists.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final l = lists[i];
                    return Material(
                      color: Colors.white.withValues(alpha: .06),
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _push(context, _ListDetailPage(list: l)),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 86,
                                height: 84,
                                child: Stack(
                                  children: [
                                    if (l.movies.isEmpty)
                                      Center(
                                          child: Icon(
                                              Icons.format_list_bulleted_rounded,
                                              color: Ui.dim,
                                              size: 34)),
                                    for (var k = 0;
                                        k < l.movies.length && k < 3;
                                        k++)
                                      Positioned(
                                        left: k * 14.0,
                                        child: _thumb(l.movies[k],
                                            w: 56, h: 84),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(l.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w900)),
                                    const SizedBox(height: 3),
                                    Text('${l.movies.length} ${'titles'.tr}',
                                        style: TextStyle(
                                            color: Ui.muted, fontSize: 12.5)),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                color: Ui.panel,
                                onSelected: (v) async {
                                  if (v == 'rename') {
                                    final n = await askText(context,
                                        title: 'Rename list'.tr,
                                        initial: l.name);
                                    if (n != null) await svc.renameList(l, n);
                                  } else if (v == 'delete') {
                                    await svc.deleteList(l);
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                      value: 'rename', child: Text('Rename'.tr)),
                                  PopupMenuItem(
                                      value: 'delete', child: Text('Delete'.tr)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _ListDetailPage extends StatelessWidget {
  final UserList list;
  const _ListDetailPage({required this.list});

  @override
  Widget build(BuildContext context) {
    final svc = ProfileService.instance;
    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) => Scaffold(
        backgroundColor: Ui.bg,
        appBar: AppBar(
          backgroundColor: Ui.bg,
          title: Text(list.name,
              style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
        body: list.movies.isEmpty
            ? const _Empty(
                icon: Icons.playlist_add_rounded,
                title: 'This list is empty',
                hint: 'Open any movie and tap List to add it here.')
            : _PosterGrid(
                items: [for (final m in list.movies) (m, null)],
                onRemove: (m) async {
                  await svc.toggleInList(list, m);
                },
              ),
      ),
    );
  }
}

// ================================================================ reviews

class _ReviewsPage extends StatelessWidget {
  const _ReviewsPage();

  @override
  Widget build(BuildContext context) {
    final svc = ProfileService.instance;
    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) {
        final reviews = svc.reviews;
        return _Page(
          title: 'Reviews',
          body: reviews.isEmpty
              ? const _Empty(
                  icon: Icons.rate_review_outlined,
                  title: 'No reviews yet',
                  hint: 'Tap Review on a movie page to write your thoughts.')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                  itemCount: reviews.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final r = reviews[i];
                    return Material(
                      color: Colors.white.withValues(alpha: .06),
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _openTitle(context, r.movie),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _thumb(r.movie),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(r.movie.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w900)),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        if (r.stars > 0) ...[
                                          const Icon(Icons.star_rounded,
                                              size: 15, color: _gold),
                                          Text(' ${r.stars}/5  ',
                                              style: const TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w800)),
                                        ],
                                        Text(_date(r.at),
                                            style: TextStyle(
                                                color: Ui.muted,
                                                fontSize: 12)),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(r.text,
                                        maxLines: 6,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 13.5, height: 1.35)),
                                  ],
                                ),
                              ),
                              Column(
                                children: [
                                  IconButton(
                                    tooltip: 'Edit'.tr,
                                    icon: const Icon(Icons.edit_rounded,
                                        size: 19),
                                    onPressed: () =>
                                        showReviewDialog(context, r.movie),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete'.tr,
                                    icon: const Icon(Icons.delete_outline_rounded,
                                        size: 20),
                                    onPressed: () => svc.deleteReview(r),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

// ============================================================== check-ins

class _CheckInsPage extends StatelessWidget {
  const _CheckInsPage();

  @override
  Widget build(BuildContext context) {
    final svc = ProfileService.instance;
    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) {
        final items = svc.checkIns;
        return _Page(
          title: 'Check-ins',
          body: items.isEmpty
              ? const _Empty(
                  icon: Icons.check_circle_outline_rounded,
                  title: 'No check-ins yet',
                  hint: 'Tap Check in on a movie page when you start watching it.')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final c = items[i];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      leading: _thumb(c.movie, w: 46, h: 68),
                      title: Text(c.movie.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(_date(c.at),
                          style: TextStyle(color: Ui.muted, fontSize: 12.5)),
                      trailing: IconButton(
                        icon: const Icon(Icons.close_rounded, size: 19),
                        onPressed: () => svc.deleteCheckIn(c),
                      ),
                      onTap: () => _openTitle(context, c.movie),
                    );
                  },
                ),
        );
      },
    );
  }
}

// ============================================================== interests

const _allGenres = [
  'Action',
  'Adventure',
  'Animation',
  'Comedy',
  'Crime',
  'Documentary',
  'Drama',
  'Family',
  'Fantasy',
  'History',
  'Horror',
  'Kids',
  'Music',
  'Mystery',
  'Romance',
  'Sci-Fi',
  'Thriller',
  'War',
  'Western',
];

class _InterestsPage extends StatelessWidget {
  const _InterestsPage();

  @override
  Widget build(BuildContext context) {
    final svc = ProfileService.instance;
    return _Page(
      title: 'Interests',
      body: ListenableBuilder(
        listenable: svc,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            Text('Pick the kinds of titles you like.'.tr,
                style: TextStyle(color: Ui.muted, fontSize: 13.5)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in _allGenres)
                  FilterChip(
                    label: Text(g.tr),
                    selected: svc.interests.contains(g),
                    showCheckmark: false,
                    selectedColor: Ui.red,
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: svc.interests.contains(g)
                          ? Ui.palette.onAccent
                          : Colors.white,
                    ),
                    onSelected: (_) => svc.toggleInterest(g),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================= badges

class _BadgesPage extends StatelessWidget {
  const _BadgesPage();

  @override
  Widget build(BuildContext context) {
    final svc = ProfileService.instance;
    return _Page(
      title: 'Badges',
      body: ListenableBuilder(
        listenable: Listenable.merge(
            [svc, MovieLibrary.instance, RatingService.instance]),
        builder: (context, _) {
          final badges = svc.badges;
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
            itemCount: badges.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final b = badges[i];
              final value = (b.have / b.need).clamp(0.0, 1.0);
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: b.earned
                          ? _gold.withValues(alpha: .6)
                          : Ui.glassLine),
                ),
                child: Row(
                  children: [
                    Icon(Icons.military_tech_rounded,
                        size: 38, color: b.earned ? _gold : Ui.dim),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(b.title.tr,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 2),
                          Text(b.hint.tr,
                              style:
                                  TextStyle(color: Ui.muted, fontSize: 12.5)),
                          if (!b.earned) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: value,
                                minHeight: 5,
                                color: Ui.red,
                                backgroundColor:
                                    Colors.white.withValues(alpha: .1),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    b.earned
                        ? Icon(Icons.check_circle_rounded, color: Ui.green)
                        : Text('${b.have}/${b.need}',
                            style: TextStyle(
                                color: Ui.muted,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800)),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// =========================================================== favorite people

class _PeoplePage extends StatefulWidget {
  const _PeoplePage();

  @override
  State<_PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<_PeoplePage> {
  final _c = TextEditingController();
  List<TmdbPerson>? _results;
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() => _results = null);
      return;
    }
    setState(() => _busy = true);
    final r = await tmdb.searchPeople(q);
    if (!mounted) return;
    setState(() {
      _results = r;
      _busy = false;
    });
  }

  Widget _avatar(String photo, String name) => CircleAvatar(
        radius: 26,
        backgroundColor: Ui.card,
        foregroundImage: photo.isEmpty ? null : NetworkImage(photo),
        child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w900)),
      );

  @override
  Widget build(BuildContext context) {
    final svc = ProfileService.instance;
    return _Page(
      title: 'Favorite people',
      body: ListenableBuilder(
        listenable: svc,
        builder: (context, _) {
          final searching = _results != null;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                child: TextField(
                  controller: _c,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _search,
                  decoration: InputDecoration(
                    hintText: 'Search actors, directors…'.tr,
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: searching || _c.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _c.clear();
                              setState(() => _results = null);
                            },
                          )
                        : null,
                  ),
                ),
              ),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: searching
                    ? (_results!.isEmpty
                        ? const _Empty(
                            icon: Icons.search_off_rounded,
                            title: 'No one found',
                            hint: 'Try another spelling.')
                        : ListView.builder(
                            itemCount: _results!.length,
                            itemBuilder: (context, i) {
                              final p = _results![i];
                              final fav = svc.isFavorite(p.id);
                              return ListTile(
                                leading: _avatar(p.photo, p.name),
                                title: Text(p.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800)),
                                subtitle: p.knownFor.isEmpty
                                    ? null
                                    : Text(p.knownFor,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: Ui.muted, fontSize: 12.5)),
                                trailing: IconButton(
                                  icon: Icon(
                                      fav
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      color: fav ? Ui.red : null),
                                  onPressed: () => svc.toggleFavorite(
                                      FavoritePerson(
                                          p.id, p.name, p.photo, p.knownFor)),
                                ),
                              );
                            },
                          ))
                    : (svc.people.isEmpty
                        ? const _Empty(
                            icon: Icons.people_outline_rounded,
                            title: 'No favorite people yet',
                            hint: 'Search above and tap the heart to add someone.')
                        : ListView.builder(
                            itemCount: svc.people.length,
                            itemBuilder: (context, i) {
                              final p = svc.people[i];
                              return ListTile(
                                leading: _avatar(p.photo, p.name),
                                title: Text(p.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800)),
                                subtitle: p.knownFor.isEmpty
                                    ? null
                                    : Text(p.knownFor,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: Ui.muted, fontSize: 12.5)),
                                trailing: IconButton(
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () => svc.toggleFavorite(p),
                                ),
                              );
                            },
                          )),
              ),
            ],
          );
        },
      ),
    );
  }
}
