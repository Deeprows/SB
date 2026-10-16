import 'package:flutter/material.dart';

import '../services/community_service.dart';
import '../theme/app_theme.dart';
import '../utils/l10n.dart';
import '../widgets/community_widgets.dart';

/// A member's public profile: how active they are, their last movie tweet,
/// their last recommendation and everything else they posted.
class CommunityProfileScreen extends StatefulWidget {
  final String email;
  final String? name;
  final String? photoUrl;
  const CommunityProfileScreen(
      {super.key, required this.email, this.name, this.photoUrl});

  @override
  State<CommunityProfileScreen> createState() => _CommunityProfileScreenState();
}

class _CommunityProfileScreenState extends State<CommunityProfileScreen> {
  CommunityProfile? _profile;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await CommunityService.instance.profile(widget.email);
      if (mounted) {
        setState(() {
          _profile = p;
          _error = null;
        });
      }
    } on CommunityException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.bg,
        title: Text((p?.mine ?? false ? 'My posts' : 'Profile').tr,
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: p == null ? _loading() : _content(p),
    );
  }

  Widget _loading() {
    if (_error != null) {
      return CommunityMessage(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load this profile',
        hint: _error!,
        action: 'Try again',
        onAction: () {
          setState(() => _error = null);
          _load();
        },
      );
    }
    return Column(
      children: [
        const SizedBox(height: 8),
        _header(
            widget.name ?? '', widget.photoUrl ?? '', null, posts: 0, likes: 0),
        const Expanded(child: Center(child: CircularProgressIndicator())),
      ],
    );
  }

  Widget _header(String name, String photo, String? bio,
      {required int posts, required int likes}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Ui.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Ui.glassLine),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CommunityAvatar(url: photo, name: name, radius: 34),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isEmpty ? '…' : name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.3)),
                    if (bio != null && bio.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(bio,
                          style: TextStyle(color: Ui.muted, fontSize: 13)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _stat(Icons.forum_rounded, '$posts', 'Posts'),
              const SizedBox(width: 10),
              _stat(Icons.favorite_rounded, '$likes', 'Likes received'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Ui.glassLine),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Ui.redSoft),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w900)),
                  Text(label.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Ui.muted, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, IconData icon) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Ui.redSoft),
            const SizedBox(width: 8),
            Text(title.tr,
                style: const TextStyle(
                    fontSize: 15.5, fontWeight: FontWeight.w900)),
          ],
        ),
      );

  Widget _content(CommunityProfile p) {
    final others = p.posts
        .where((x) => x.id != p.lastTweet?.id && x.id != p.lastRecommendation?.id)
        .toList();
    return RefreshIndicator(
      color: Ui.red,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _header(p.name, p.photoUrl, p.bio,
              posts: p.postCount, likes: p.likeCount),
          _section('Last movie tweet', Icons.chat_bubble_rounded),
          _slot(p.lastTweet, 'No movie tweets yet.'),
          _section('Last recommendation', Icons.thumb_up_alt_rounded),
          _slot(p.lastRecommendation, 'No recommendations yet.'),
          if (others.isNotEmpty) ...[
            _section('Earlier posts', Icons.history_rounded),
            for (final post in others)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: PostCard(post: post, showAuthor: false),
              ),
          ],
        ],
      ),
    );
  }

  Widget _slot(CommunityPost? post, String empty) {
    if (post == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: Text(empty.tr, style: TextStyle(color: Ui.muted)),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: PostCard(post: post, showAuthor: false),
    );
  }
}

/// Everyone in the community, most active first, with a search box.
class CommunityPeopleScreen extends StatefulWidget {
  const CommunityPeopleScreen({super.key});

  @override
  State<CommunityPeopleScreen> createState() => _CommunityPeopleScreenState();
}

class _CommunityPeopleScreenState extends State<CommunityPeopleScreen> {
  List<CommunityPerson>? _people;
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await CommunityService.instance.people();
      if (mounted) {
        setState(() {
          _people = list;
          _error = null;
        });
      }
    } on CommunityException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _people;
    final list = all == null
        ? const <CommunityPerson>[]
        : all
            .where((p) => p.name.toLowerCase().contains(_q.trim().toLowerCase()))
            .toList();
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.bg,
        title: Text('Movie fans'.tr,
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: 'Search people'.tr,
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white.withValues(alpha: .06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: all == null
                ? (_error != null
                    ? CommunityMessage(
                        icon: Icons.cloud_off_rounded,
                        title: 'Could not load people',
                        hint: _error!,
                        action: 'Try again',
                        onAction: _load)
                    : const Center(child: CircularProgressIndicator()))
                : list.isEmpty
                    ? const CommunityMessage(
                        icon: Icons.people_outline_rounded,
                        title: 'Nobody found',
                        hint: 'Try another name.')
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final p = list[i];
                          return ListTile(
                            onTap: () => openCommunityProfile(context, p.email,
                                name: p.name, photoUrl: p.photoUrl),
                            leading: CommunityAvatar(
                                url: p.photoUrl, name: p.name, radius: 21),
                            title: Text(p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            subtitle: Text(
                                '${p.postCount} ${'posts'.tr}',
                                style:
                                    TextStyle(color: Ui.muted, fontSize: 12)),
                            trailing: Icon(Icons.chevron_right_rounded,
                                color: Ui.dim),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
