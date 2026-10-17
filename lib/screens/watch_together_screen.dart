import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/movie.dart';
import '../services/auth_service.dart';
import '../services/community_service.dart';
import '../services/feed_service.dart';
import '../theme/app_theme.dart';
import 'theatre_screen.dart';

const _gold = Color(0xFFFFC857);
const _velvet = Color(0xFF7A0F1E);

/// Watch Together lobby: pick a movie, pick who joins you, open the theatre.
/// Invitations you received and rooms you are already in are listed on top.
class WatchTogetherScreen extends StatefulWidget {
  /// Pre-selects this member (used by the "Watch Together" button on a
  /// member's profile).
  final String? inviteEmail;
  const WatchTogetherScreen({super.key, this.inviteEmail});

  @override
  State<WatchTogetherScreen> createState() => _WatchTogetherScreenState();
}

class _WatchTogetherScreenState extends State<WatchTogetherScreen> {
  final _community = CommunityService.instance;
  final _feed = FeedService();
  List<CommunityPerson> _people = [];
  List<Movie> _movies = [];
  List<Map<String, dynamic>> _invitations = [];
  List<Map<String, dynamic>> _rooms = [];
  final Set<String> _selectedPeople = {};
  Movie? _selectedMovie;
  String _movieQuery = '';
  String _personQuery = '';
  bool _loading = true;
  bool _busy = false;
  String? _error;

  String get _me => AuthService.instance.user?.email.trim().toLowerCase() ?? '';

  @override
  void initState() {
    super.initState();
    final pre = widget.inviteEmail?.trim().toLowerCase();
    if (pre != null && pre.isNotEmpty) _selectedPeople.add(pre);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait<dynamic>([
        _community.people(),
        _feed.loadMovies(),
        _community.watchInvitations(),
        _community.myWatchRooms(),
      ]);
      if (!mounted) return;
      setState(() {
        _people = (values[0] as List<CommunityPerson>)
            .where((p) => p.email.toLowerCase() != _me)
            .toList();
        _movies = values[1] as List<Movie>;
        _invitations = values[2] as List<Map<String, dynamic>>;
        _rooms = values[3] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } on CommunityException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = const CommunityException('').message;
        });
      }
    }
  }

  Future<void> _openRoom(Map<String, dynamic> room) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TheatreScreen(room: room),
    ));
    if (mounted) _load();
  }

  Future<void> _createRoom() async {
    final movie = _selectedMovie;
    if (movie == null || _selectedPeople.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pick a movie and at least one person.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final room = await _community.createWatchRoom(
          movie: movie, invitees: _selectedPeople.toList());
      if (!mounted) return;
      setState(() => _busy = false);
      await _openRoom(room);
    } on CommunityException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _takeSeat(Map<String, dynamic> invite, bool accept) async {
    final id = '${invite['id'] ?? ''}';
    if (id.isEmpty) return;
    setState(() => _busy = true);
    try {
      final room = await _community.respondWatchInvitation(id, accept);
      if (!mounted) return;
      setState(() {
        _invitations.removeWhere((x) => '${x['id']}' == id);
        _busy = false;
      });
      if (accept) await _openRoom(room);
    } on CommunityException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _movieQuery.trim().toLowerCase();
    final movies = _movies
        .where((m) => q.isEmpty || m.title.toLowerCase().contains(q))
        .take(60)
        .toList();
    final pq = _personQuery.trim().toLowerCase();
    final people = _people
        .where((p) => pq.isEmpty || p.name.toLowerCase().contains(pq))
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0A050D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Watch Together',
            style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
              onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              color: _gold,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                children: [
                  _hero(),
                  if (_error != null) _note(_error!),
                  if (_invitations.isNotEmpty) ...[
                    _heading('You are invited', Icons.mail_rounded),
                    for (final i in _invitations) _inviteCard(i),
                  ],
                  if (_rooms.isNotEmpty) ...[
                    _heading('Your open rooms', Icons.meeting_room_rounded),
                    for (final r in _rooms) _roomTile(r),
                  ],
                  _heading('1  Choose the movie', Icons.movie_creation_rounded),
                  _search('Search movies and series',
                      (v) => setState(() => _movieQuery = v)),
                  const SizedBox(height: 10),
                  if (movies.isEmpty)
                    _note('No movies found.')
                  else
                    SizedBox(
                      height: 200,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: movies.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (_, i) => _poster(movies[i]),
                      ),
                    ),
                  _heading('2  Who is coming?', Icons.people_alt_rounded),
                  _search('Search people',
                      (v) => setState(() => _personQuery = v)),
                  const SizedBox(height: 12),
                  if (_people.isEmpty)
                    _note('No other community members yet.')
                  else
                    Wrap(
                      spacing: 12,
                      runSpacing: 14,
                      children: [for (final p in people) _person(p)],
                    ),
                  const SizedBox(height: 22),
                  _summary(),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _busy ? null : _createRoom,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.theaters_rounded),
                    label: Text(_busy ? 'Opening…' : 'Open the theatre'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 15.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _hero() => Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF5A0B18), Color(0xFF1B0610)],
          ),
          border: Border.all(color: _gold.withValues(alpha: .35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.theater_comedy_rounded, size: 44, color: _gold),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Your private cinema',
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                      'Pick a movie and a friend. You both take a seat, the host starts the show, and you react and chat while it plays.',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: .75),
                          fontSize: 12.5,
                          height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _heading(String title, IconData icon) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
        child: Row(
          children: [
            Icon(icon, color: _gold, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      );

  Widget _search(String hint, ValueChanged<String> onChanged) => TextField(
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: const Icon(Icons.search_rounded),
          filled: true,
          fillColor: Colors.white.withValues(alpha: .07),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none),
        ),
      );

  Widget _note(String text) => Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(color: Ui.muted)),
      );

  Widget _poster(Movie m) {
    final chosen = _selectedMovie?.url == m.url;
    return GestureDetector(
      onTap: () => setState(() => _selectedMovie = m),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 122,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: chosen ? _gold : Colors.white12, width: chosen ? 2.2 : 1),
          boxShadow: chosen
              ? [BoxShadow(color: _gold.withValues(alpha: .35), blurRadius: 14)]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  m.image.startsWith('http')
                      ? CachedNetworkImage(
                          imageUrl: m.image,
                          fit: BoxFit.cover,
                          memCacheWidth: 300,
                          errorWidget: (_, _, _) =>
                              const Icon(Icons.movie_rounded))
                      : const Icon(Icons.movie_rounded, size: 38),
                  if (chosen)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                            color: _gold, shape: BoxShape.circle),
                        child: const Icon(Icons.check_rounded,
                            size: 16, color: Colors.black),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(7),
              child: Text(m.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _person(CommunityPerson p) {
    final chosen = _selectedPeople.contains(p.email.toLowerCase());
    return GestureDetector(
      onTap: () => setState(() {
        final e = p.email.toLowerCase();
        if (!_selectedPeople.remove(e)) _selectedPeople.add(e);
      }),
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: chosen ? _gold : Colors.white24,
                        width: chosen ? 2.4 : 1.2),
                    boxShadow: chosen
                        ? [
                            BoxShadow(
                                color: _gold.withValues(alpha: .4),
                                blurRadius: 12)
                          ]
                        : null,
                  ),
                  child: CircleAvatar(
                    radius: 28,
                    backgroundColor: _velvet,
                    foregroundImage: p.photoUrl.startsWith('https://')
                        ? CachedNetworkImageProvider(p.photoUrl)
                        : null,
                    child: Text(
                        p.name.isEmpty ? '?' : p.name[0].toUpperCase(),
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 18)),
                  ),
                ),
                if (chosen)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                          color: _gold, shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded,
                          size: 14, color: Colors.black),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(p.name.split(' ').first,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: chosen ? _gold : Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget _summary() {
    final m = _selectedMovie;
    final n = _selectedPeople.length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(Icons.confirmation_number_rounded, color: _gold),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              m == null
                  ? 'Pick a movie above'
                  : n == 0
                      ? '${m.title} · pick who joins you'
                      : '${m.title} · you + $n ${n == 1 ? 'guest' : 'guests'}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inviteCard(Map<String, dynamic> invite) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
            colors: [Color(0xFF4A0A16), Color(0xFF1E0710)]),
        border: Border.all(color: _gold.withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${invite['hostName'] ?? 'A movie fan'} invited you to watch',
              style: TextStyle(color: Colors.white.withValues(alpha: .8))),
          const SizedBox(height: 3),
          Text(roomTitle(invite),
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _takeSeat(invite, false),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _takeSeat(invite, true),
                  icon: const Icon(Icons.event_seat_rounded),
                  label: const Text('Take a seat'),
                  style: FilledButton.styleFrom(
                      backgroundColor: _gold, foregroundColor: Colors.black),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _roomTile(Map<String, dynamic> room) {
    final m = roomMovie(room);
    final people = room['people'] is List ? (room['people'] as List).length : 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: ListTile(
        onTap: () => _openRoom(room),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 40,
            height: 56,
            child: (m?.image.startsWith('http') ?? false)
                ? CachedNetworkImage(imageUrl: m!.image, fit: BoxFit.cover)
                : const Icon(Icons.theaters_rounded),
          ),
        ),
        title: Text(roomTitle(room),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(
            '$people ${people == 1 ? 'seat' : 'seats'} · ${room['status'] == 'playing' ? 'show started' : 'waiting to start'}',
            style: TextStyle(color: Ui.muted, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right_rounded, color: _gold),
      ),
    );
  }
}
