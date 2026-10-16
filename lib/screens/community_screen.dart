import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/community_service.dart';
import '../theme/app_theme.dart';
import '../utils/l10n.dart';
import '../widgets/community_widgets.dart';
import 'community_composer.dart';
import 'community_profile_screen.dart';

/// Movie Community: a feed of movie tweets and recommendations. Tap a name to
/// open that person's profile, tap a post to like and comment.
///
/// As a bottom tab it loads the first time it is shown ([active]); opened from
/// the menu it is [standalone] and has a back button.
class CommunityScreen extends StatefulWidget {
  final bool active;
  final bool standalone;
  const CommunityScreen({super.key, this.active = true, this.standalone = false});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final _svc = CommunityService.instance;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(CommunityScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !_started) _start();
  }

  void _start() {
    _started = true;
    _svc.load();
  }

  static const _filters = <(String, String)>[
    ('', 'All'),
    ('tweet', 'Tweets'),
    ('recommendation', 'Recommended'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_svc, AuthService.instance]),
      builder: (context, _) {
        final posts = _svc.feed;
        return Scaffold(
          backgroundColor: Ui.bg,
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          floatingActionButton: DecoratedBox(
            decoration: BoxDecoration(
              gradient: Ui.gradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Ui.red.withValues(alpha: .45),
                    blurRadius: 20,
                    offset: const Offset(0, 8)),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => showCommunityComposer(context),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_rounded,
                          size: 20, color: Ui.palette.onAccent),
                      const SizedBox(width: 8),
                      Text('Post'.tr,
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Ui.palette.onAccent)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          body: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: Ui.red,
              onRefresh: () => _svc.load(),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _header(context)),
                  SliverToBoxAdapter(child: _composerTeaser(context)),
                  SliverToBoxAdapter(child: _chips()),
                  ..._body(context, posts),
                  const SliverToBoxAdapter(child: SizedBox(height: 96)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
      child: Row(
        children: [
          if (widget.standalone)
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
            )
          else
            const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Community'.tr,
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.5)),
                Text('Movie tweets & recommendations'.tr,
                    style: TextStyle(color: Ui.muted, fontSize: 12.5)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Movie fans'.tr,
            icon: const Icon(Icons.people_alt_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const CommunityPeopleScreen())),
          ),
        ],
      ),
    );
  }

  Widget _composerTeaser(BuildContext context) {
    final user = AuthService.instance.user;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Material(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => showCommunityComposer(context),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Ui.glassLine),
            ),
            child: Row(
              children: [
                CommunityAvatar(
                    url: user?.photoUrl ?? '',
                    name: user?.name ?? '',
                    radius: 19),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('What are you watching?'.tr,
                      style: TextStyle(color: Ui.muted, fontSize: 14.5)),
                ),
                Icon(Icons.movie_filter_rounded, color: Ui.redSoft),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chips() {
    return SizedBox(
      height: 54,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        children: [
          for (final (kind, label) in _filters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label.tr),
                selected: _svc.kind == kind,
                showCheckmark: false,
                selectedColor: Ui.red,
                backgroundColor: Colors.white.withValues(alpha: .06),
                side: BorderSide(color: Ui.glassLine),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _svc.kind == kind ? Ui.palette.onAccent : Ui.muted,
                ),
                onSelected: (_) => _svc.load(kind: kind),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _body(BuildContext context, List<CommunityPost> posts) {
    if (!_svc.loaded || (_svc.loading && posts.isEmpty)) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_svc.error != null && posts.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: CommunityMessage(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load the community',
            hint: _svc.error!,
            action: 'Try again',
            onAction: () => _svc.load(),
          ),
        ),
      ];
    }
    if (posts.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: CommunityMessage(
            icon: Icons.forum_outlined,
            title: 'No posts yet',
            hint: 'Be the first to share a movie tweet or recommendation.',
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        sliver: SliverList.separated(
          itemCount: posts.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) => PostCard(post: posts[i]),
        ),
      ),
    ];
  }
}
