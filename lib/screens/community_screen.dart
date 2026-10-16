import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/community_service.dart';
import '../theme/app_theme.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});
  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> with AutomaticKeepAliveClientMixin {
  final _api = CommunityService.instance;
  final _composer = TextEditingController();
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true, _sending = false;
  String? _error;
  @override bool get wantKeepAlive => true;
  @override void initState() { super.initState(); _load(); }
  @override void dispose() { _composer.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try { final p = await _api.posts(); if (mounted) setState(() => _posts = p); }
    catch (e) { if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', '')); }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _post() async {
    final text = _composer.text.trim(); if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try { await _api.createPost(text); _composer.clear(); await _load(); }
    catch (e) { _message(e.toString().replaceFirst('Exception: ', '')); }
    if (mounted) setState(() => _sending = false);
  }
  void _message(String text) { if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }

  @override Widget build(BuildContext context) {
    super.build(context);
    final user = AuthService.instance.user;
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(title: const Text('Movie Community', style: TextStyle(fontWeight: FontWeight.w900)), backgroundColor: Ui.bg,
        actions: [IconButton(tooltip: 'People', icon: const Icon(Icons.people_alt_outlined), onPressed: _showPeople), IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded), onPressed: _load)]),
      body: Column(children: [
        Container(margin: const EdgeInsets.fromLTRB(12, 8, 12, 10), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Ui.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: Ui.line)),
          child: Column(children: [Row(children: [CircleAvatar(backgroundImage: user?.photoUrl != null ? NetworkImage(user!.photoUrl!) : null, child: user?.photoUrl == null ? const Icon(Icons.person) : null), const SizedBox(width: 10), const Expanded(child: Text('What movie is worth watching?', style: TextStyle(fontWeight: FontWeight.w800)))]), const SizedBox(height: 10), TextField(controller: _composer, minLines: 2, maxLines: 5, maxLength: 500, decoration: const InputDecoration(hintText: 'Share a movie tweet or recommendation…', border: OutlineInputBorder()),), Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: _sending ? null : _post, icon: const Icon(Icons.send_rounded, size: 17), label: Text(_sending ? 'Posting…' : 'Post')))])),
        Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? _emptyError() : _posts.isEmpty ? const Center(child: Text('No movie tweets yet. Be the first to post!')) : RefreshIndicator(onRefresh: _load, child: ListView.separated(padding: const EdgeInsets.fromLTRB(12, 2, 12, 24), itemCount: _posts.length, separatorBuilder: (_, _) => const SizedBox(height: 10), itemBuilder: (_, i) => _postCard(_posts[i]))))
      ]),
    );
  }

  Widget _emptyError() => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off_rounded, size: 42), const SizedBox(height: 12), Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 12), const Text('Community APIs must be deployed to your Cloudflare Worker and Google sign-in must return an ID token.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)), const SizedBox(height: 12), FilledButton(onPressed: _load, child: const Text('Try again'))])));

  Widget _postCard(Map<String, dynamic> p) {
    final id = '${p['id']}'; final liked = p['likedByMe'] == true;
    return Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Ui.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: Ui.line)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(onTap: () => _showProfile('${p['email'] ?? ''}'), child: Row(children: [CircleAvatar(radius: 19, backgroundImage: (p['photoUrl'] is String && '${p['photoUrl']}'.isNotEmpty) ? NetworkImage('${p['photoUrl']}') : null, child: (p['photoUrl'] == null || '${p['photoUrl']}'.isEmpty) ? const Icon(Icons.person, size: 20) : null), const SizedBox(width: 9), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${p['name'] ?? 'Movie fan'}', style: const TextStyle(fontWeight: FontWeight.w900)), Text(_date('${p['createdAt'] ?? ''}'), style: TextStyle(color: Ui.muted, fontSize: 11))])), const Icon(Icons.chevron_right_rounded, color: Colors.white38)])),
      const SizedBox(height: 12), Text('${p['text'] ?? ''}', style: const TextStyle(fontSize: 14, height: 1.4)),
      if ('${p['movieTitle'] ?? ''}'.isNotEmpty) Container(margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: Ui.bg, borderRadius: BorderRadius.circular(12)), child: Row(children: [if ('${p['movieImage'] ?? ''}'.startsWith('http')) ClipRRect(borderRadius: BorderRadius.circular(7), child: Image.network('${p['movieImage']}', width: 42, height: 58, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 42, height: 58))) else const Icon(Icons.movie_outlined, size: 40), const SizedBox(width: 10), Expanded(child: Text('${p['movieTitle']}', style: const TextStyle(fontWeight: FontWeight.bold))), if (p['rating'] != null) Text('★ ${p['rating']}/10', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))])),
      const Divider(height: 22), Row(children: [TextButton.icon(onPressed: () async { try { await _api.toggleLike(id); await _load(); } catch (e) { _message('$e'); } }, icon: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? Colors.pinkAccent : Ui.muted), label: Text('${p['likeCount'] ?? 0}', style: TextStyle(color: liked ? Colors.pinkAccent : Ui.muted))), TextButton.icon(onPressed: () => _showComments(id), icon: const Icon(Icons.mode_comment_outlined), label: Text('${p['commentCount'] ?? 0}')), const Spacer(), IconButton(tooltip: 'View profile', onPressed: () => _showProfile('${p['email'] ?? ''}'), icon: const Icon(Icons.account_circle_outlined))])
    ]));
  }

  String _date(String raw) { final d = DateTime.tryParse(raw); if (d == null) return 'Recently'; final diff = DateTime.now().difference(d.toLocal()); if (diff.inMinutes < 1) return 'Just now'; if (diff.inHours < 1) return '${diff.inMinutes}m ago'; if (diff.inDays < 1) return '${diff.inHours}h ago'; return '${diff.inDays}d ago'; }

  Future<void> _showComments(String id) async {
    final input = TextEditingController();
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, backgroundColor: Ui.card, builder: (ctx) => SafeArea(child: Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16), child: SizedBox(height: MediaQuery.of(ctx).size.height * .65, child: Column(children: [const Text('Comments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(height: 12), Expanded(child: FutureBuilder<List<Map<String, dynamic>>>(future: _api.comments(id), builder: (_, snap) { if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator()); if (snap.hasError) return Center(child: Text('${snap.error}')); final rows = snap.data ?? []; if (rows.isEmpty) return const Center(child: Text('Be the first to comment.')); return ListView(children: rows.map((c) => ListTile(leading: CircleAvatar(child: Text('${c['name'] ?? 'M'}'.characters.first)), title: Text('${c['name'] ?? 'Movie fan'}'), subtitle: Text('${c['text'] ?? ''}')).toList()); })), Row(children: [Expanded(child: TextField(controller: input, maxLength: 500, decoration: const InputDecoration(hintText: 'Write a comment…'))), IconButton(icon: const Icon(Icons.send_rounded), onPressed: () async { final t = input.text.trim(); if (t.isEmpty) return; try { await _api.comment(id, t); input.clear(); if (ctx.mounted) Navigator.pop(ctx); await _load(); if (mounted) _showComments(id); } catch (e) { _message('$e'); } })])]))));
    input.dispose();
  }

  Future<void> _showPeople() async {
    try { final people = await _api.people(); if (!mounted) return; showModalBottomSheet<void>(context: context, backgroundColor: Ui.card, builder: (ctx) => SafeArea(child: SizedBox(height: MediaQuery.of(ctx).size.height * .65, child: ListView(padding: const EdgeInsets.all(12), children: [const Padding(padding: EdgeInsets.all(8), child: Text('Movie fans', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))), ...people.map((p) => ListTile(leading: CircleAvatar(backgroundImage: p['photoUrl'] != null ? NetworkImage('${p['photoUrl']}') : null, child: p['photoUrl'] == null ? const Icon(Icons.person) : null), title: Text('${p['name']}'), subtitle: Text('${p['postCount'] ?? 0} movie tweets'), onTap: () { Navigator.pop(ctx); _showProfile('${p['email']}'); }))])))); } catch (e) { _message('$e'); }
  }

  Future<void> _showProfile(String email) async {
    if (email.isEmpty) return;
    try { final p = await _api.profile(email); if (!mounted) return; showModalBottomSheet<void>(context: context, isScrollControlled: true, backgroundColor: Ui.card, builder: (ctx) => SafeArea(child: SizedBox(height: MediaQuery.of(ctx).size.height * .75, child: ListView(padding: const EdgeInsets.all(18), children: [Row(children: [CircleAvatar(radius: 32, backgroundImage: p['photoUrl'] != null ? NetworkImage('${p['photoUrl']}') : null, child: p['photoUrl'] == null ? const Icon(Icons.person, size: 30) : null), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${p['name']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), Text('${p['postCount'] ?? 0} movie tweets', style: TextStyle(color: Ui.muted))]))]), if ('${p['bio'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text('${p['bio']}')), const Padding(padding: EdgeInsets.only(top: 22, bottom: 8), child: Text('Latest movie tweets', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))), ...((p['posts'] as List? ?? []).map((x) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Text('${x['text']}')))))])))); } catch (e) { _message('$e'); }
  }
}
