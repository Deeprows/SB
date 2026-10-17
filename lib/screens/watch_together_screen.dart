import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/movie.dart';
import '../services/community_service.dart';
import '../services/feed_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/open_movie.dart';

/// Invite community members to watch one movie together.
class WatchTogetherScreen extends StatefulWidget {
  const WatchTogetherScreen({super.key});

  @override
  State<WatchTogetherScreen> createState() => _WatchTogetherScreenState();
}

class _WatchTogetherScreenState extends State<WatchTogetherScreen> {
  final _community = CommunityService.instance;
  final _feed = FeedService();
  List<CommunityPerson> _people = [];
  List<Movie> _movies = [];
  List<Map<String, dynamic>> _invitations = [];
  final Set<String> _selectedPeople = {};
  Movie? _selectedMovie;
  String _query = '';
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _room;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final values = await Future.wait<dynamic>([
        _community.people(),
        _feed.loadMovies(),
        _community.watchInvitations(),
      ]);
      if (!mounted) return;
      final me = _community.signedIn ? _currentEmail() : '';
      setState(() {
        _people = (values[0] as List<CommunityPerson>).where((p) => p.email != me).toList();
        _movies = values[1] as List<Movie>;
        _invitations = values[2] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  String _currentEmail() => AuthService.instance.user?.email.trim().toLowerCase() ?? '';

  Future<void> _createRoom() async {
    final movie = _selectedMovie;
    if (movie == null || _selectedPeople.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose at least one person and one movie.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final room = await _community.createWatchRoom(movie: movie, invitees: _selectedPeople.toList());
      if (!mounted) return;
      setState(() { _room = room; _busy = false; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Watch Together invitations sent.')));
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.toString(); });
    }
  }

  Future<void> _respond(Map<String, dynamic> invitation, bool accept) async {
    final id = '${invitation['id'] ?? ''}';
    if (id.isEmpty) return;
    setState(() => _busy = true);
    try {
      final room = await _community.respondWatchInvitation(id, accept);
      if (!mounted) return;
      setState(() {
        _invitations.removeWhere((x) => '${x['id']}' == id);
        _busy = false;
        if (accept) _room = room;
      });
      if (accept) {
        final movieData = room['movie'];
        final movie = Movie.tryParse(movieData);
        if (movie != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('You joined the Watch Together room for ${movie.title}.')));
        }
      }
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.toString(); });
    }
  }

  Movie? _roomMovie() {
    final data = _room?['movie'];
    return Movie.tryParse(data);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _movies.where((m) => m.title.toLowerCase().contains(_query.toLowerCase())).take(100).toList();
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(backgroundColor: Ui.bg, title: const Text('Watch Together', style: TextStyle(fontWeight: FontWeight.w900)), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              color: Ui.red,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  if (_error != null) _message(_error!),
                  if (_invitations.isNotEmpty) ...[
                    _heading('Invitations for you', Icons.mail_rounded),
                    for (final invite in _invitations) _invitationCard(invite),
                    const SizedBox(height: 12),
                  ],
                  if (_room != null) _roomCard(),
                  _heading('1. Pick people to invite', Icons.people_alt_rounded),
                  Text('Select one or more community members.', style: TextStyle(color: Ui.muted, fontSize: 13)),
                  const SizedBox(height: 8),
                  if (_people.isEmpty) _message('No other community members are available yet.') else
                    ..._people.map(_personTile),
                  const SizedBox(height: 12),
                  _heading('2. Choose a movie', Icons.movie_creation_rounded),
                  TextField(
                    onChanged: (v) => setState(() => _query = v),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(hintText: 'Search movies and series', hintStyle: TextStyle(color: Ui.muted), prefixIcon: const Icon(Icons.search), filled: true, fillColor: Ui.card, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Ui.glassLine))),
                  ),
                  const SizedBox(height: 10),
                  if (filtered.isEmpty) _message('No movies found.') else
                    SizedBox(
                      height: 188,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final movie = filtered[index];
                          final chosen = _selectedMovie?.url == movie.url;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedMovie = movie),
                            child: Container(
                              width: 112,
                              decoration: BoxDecoration(color: Ui.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: chosen ? Ui.red : Ui.glassLine, width: chosen ? 2 : 1)),
                              clipBehavior: Clip.antiAlias,
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                Expanded(child: movie.image.startsWith('http') ? CachedNetworkImage(imageUrl: movie.image, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.movie)) : const Icon(Icons.movie, size: 38)),
                                Padding(padding: const EdgeInsets.all(7), child: Text(movie.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
                                if (chosen) const Padding(padding: EdgeInsets.only(bottom: 5), child: Icon(Icons.check_circle, color: Colors.green, size: 18)),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _busy ? null : _createRoom,
                    icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.groups_rounded),
                    label: Text(_busy ? 'Please wait…' : 'Send Watch Together invites'),
                    style: FilledButton.styleFrom(backgroundColor: Ui.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _heading(String title, IconData icon) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
    child: Row(children: [Icon(icon, color: Ui.redSoft, size: 20), const SizedBox(width: 8), Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900))) ]),
  );

  Widget _personTile(CommunityPerson p) {
    final selected = _selectedPeople.contains(p.email);
    return CheckboxListTile(
      value: selected,
      onChanged: (v) => setState(() => v == true ? _selectedPeople.add(p.email) : _selectedPeople.remove(p.email)),
      activeColor: Ui.red,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text('${p.postCount} community posts', style: TextStyle(color: Ui.muted, fontSize: 12)),
      secondary: CircleAvatar(backgroundColor: Ui.card, backgroundImage: p.photoUrl.startsWith('https://') ? CachedNetworkImageProvider(p.photoUrl) : null, child: p.photoUrl.isEmpty ? Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase()) : null),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: selected ? Ui.red : Ui.glassLine)),
    );
  }

  Widget _invitationCard(Map<String, dynamic> invite) {
    final movie = invite['movie'] is Map ? Map<String, dynamic>.from(invite['movie']) : <String, dynamic>{};
    return Container(
      margin: const EdgeInsets.only(bottom: 9), padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: Ui.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Ui.glassLine)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${invite['hostName'] ?? 'A movie fan'} invited you to watch:', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4), Text('${movie['title'] ?? 'a movie'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10), Row(children: [Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _respond(invite, false), child: const Text('Decline'))), const SizedBox(width: 8), Expanded(child: FilledButton(onPressed: _busy ? null : () => _respond(invite, true), style: FilledButton.styleFrom(backgroundColor: Ui.red), child: const Text('Accept & join')))]),
      ]),
    );
  }

  Widget _roomCard() {
    final movie = _roomMovie();
    if (movie == null) return const SizedBox.shrink();
    final accepted = (_room?['accepted'] as List? ?? []).length;
    final invitees = (_room?['invitees'] as List? ?? []).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Ui.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: Ui.red.withValues(alpha: .65))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Your Watch Together room', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 5), Text(movie.title, style: TextStyle(color: Ui.muted)),
        Text('$accepted of $invitees invited users accepted', style: TextStyle(color: Ui.muted, fontSize: 12)),
        const SizedBox(height: 10), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => openMoviePlayer(context, movie), icon: const Icon(Icons.play_arrow_rounded), label: const Text('Watch movie now'), style: FilledButton.styleFrom(backgroundColor: Ui.red))),
      ]),
    );
  }

  Widget _message(String text) => Container(margin: const EdgeInsets.symmetric(vertical: 6), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Ui.card, borderRadius: BorderRadius.circular(12)), child: Text(text, style: TextStyle(color: Ui.muted)));
}
