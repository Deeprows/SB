import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/community_post_screen.dart';
import '../screens/community_profile_screen.dart';
import '../services/community_service.dart';
import '../services/support_gate.dart';
import '../theme/app_theme.dart';
import '../utils/l10n.dart';
import '../utils/open_movie.dart';

const _gold = Color(0xFFFFC107);

/// "just now", "5m", "3h", "2d", "12 Oct".
String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 45) return 'just now'.tr;
  if (d.inMinutes < 60) return '${d.inMinutes < 1 ? 1 : d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${t.day} ${months[t.month - 1]}';
}

void communityToast(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      content: Text(message.tr),
    ));
}

/// Runs a community action and shows its error (if any) as a message.
Future<bool> communityTry(BuildContext context, Future<void> Function() job) async {
  try {
    await job();
    return true;
  } on CommunityException catch (e) {
    communityToast(context, e.message);
  } catch (_) {
    communityToast(context, const CommunityException('').message);
  }
  return false;
}

void openCommunityProfile(BuildContext context, String email,
    {String? name, String? photoUrl}) {
  if (email.isEmpty) return;
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) =>
        CommunityProfileScreen(email: email, name: name, photoUrl: photoUrl),
  ));
}

void openCommunityPost(BuildContext context, CommunityPost post) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => CommunityPostScreen(post: post),
  ));
}

/// Round picture with the person's initial while (or if) it cannot load.
class CommunityAvatar extends StatelessWidget {
  final String url;
  final String name;
  final double radius;
  const CommunityAvatar(
      {super.key, required this.url, required this.name, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final ring = Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: Ui.gradient),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: Ui.cardDeep,
        foregroundImage:
            url.startsWith('http') ? CachedNetworkImageProvider(url) : null,
        child: Text(initial,
            style: TextStyle(
                fontSize: radius * .85,
                fontWeight: FontWeight.w900,
                color: Ui.redSoft)),
      ),
    );
    return ring;
  }
}

/// 0-10 rating shown as five stars (half stars included).
class StarsRow extends StatelessWidget {
  final int rating10;
  final double size;
  const StarsRow({super.key, required this.rating10, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            rating10 >= i * 2
                ? Icons.star_rounded
                : (rating10 == i * 2 - 1
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded),
            size: size,
            color: _gold,
          ),
      ],
    );
  }
}

class _KindBadge extends StatelessWidget {
  final bool recommendation;
  const _KindBadge({required this.recommendation});

  @override
  Widget build(BuildContext context) {
    final c = recommendation ? _gold : Ui.redSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: .35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
              recommendation
                  ? Icons.thumb_up_alt_rounded
                  : Icons.chat_bubble_rounded,
              size: 11,
              color: c),
          const SizedBox(width: 4),
          Text((recommendation ? 'Recommends' : 'Tweet').tr,
              style: TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w800, color: c)),
        ],
      ),
    );
  }
}

/// The movie a post is about: poster, title, rating. Tap opens the title.
class PostMovie extends StatelessWidget {
  final CommunityPost post;
  const PostMovie({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    final movie = post.movie;
    final poster = post.movieImage.startsWith('http')
        ? CachedNetworkImage(
            imageUrl: post.movieImage,
            width: 52,
            height: 76,
            fit: BoxFit.cover,
            memCacheWidth: 200,
            errorWidget: (_, _, _) => _posterFallback(),
          )
        : _posterFallback();
    return Material(
      color: Colors.white.withValues(alpha: .05),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: movie == null
            ? null
            : () => SupportGate.guard(context, () {
                  if (context.mounted) openMovieTitle(context, movie);
                }),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Ui.glassLine),
          ),
          child: Row(
            children: [
              ClipRRect(
                  borderRadius: BorderRadius.circular(10), child: poster),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(post.movieTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text((post.movieTv ? 'Series' : 'Movie').tr,
                        style: TextStyle(color: Ui.muted, fontSize: 12)),
                    if (post.rating != null && post.rating! > 0) ...[
                      const SizedBox(height: 5),
                      StarsRow(rating10: post.rating!),
                    ],
                  ],
                ),
              ),
              if (movie != null)
                Icon(Icons.play_circle_fill_rounded,
                    size: 30, color: Ui.redSoft),
            ],
          ),
        ),
      ),
    );
  }

  Widget _posterFallback() => Container(
        width: 52,
        height: 76,
        color: Ui.cardDeep,
        child: Icon(Icons.movie_rounded, color: Ui.dim),
      );
}

/// One tweet / recommendation card.
class PostCard extends StatelessWidget {
  final CommunityPost post;

  /// On the post page: no "tap to open", full text.
  final bool detail;

  /// On someone's profile: the author row is hidden.
  final bool showAuthor;
  const PostCard(
      {super.key,
      required this.post,
      this.detail = false,
      this.showAuthor = true});

  Future<void> _like(BuildContext context) async {
    HapticFeedback.selectionClick();
    await communityTry(
        context, () => CommunityService.instance.toggleLike(post));
  }

  Future<void> _delete(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Ui.panel,
        title: Text('Delete this post?'.tr),
        content: Text('Its likes and comments will be removed too.'.tr),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('CANCEL'.tr)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('DELETE'.tr, style: TextStyle(color: Ui.red))),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    final ok = await communityTry(
        context, () => CommunityService.instance.deletePost(post));
    if (ok && detail && context.mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CommunityService.instance,
      builder: (context, _) {
        final liked = post.likedByMe;
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          decoration: BoxDecoration(
            color: Ui.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Ui.glassLine),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showAuthor)
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => openCommunityProfile(context, post.email,
                          name: post.name, photoUrl: post.photoUrl),
                      child: CommunityAvatar(
                          url: post.photoUrl, name: post.name, radius: 19),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => openCommunityProfile(context, post.email,
                            name: post.name, photoUrl: post.photoUrl),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(post.mine ? '${post.name} · ${'You'.tr}' : post.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14.5)),
                            const SizedBox(height: 2),
                            Text(timeAgo(post.createdAt),
                                style:
                                    TextStyle(color: Ui.muted, fontSize: 11.5)),
                          ],
                        ),
                      ),
                    ),
                    _KindBadge(recommendation: post.recommendation),
                    if (post.mine)
                      PopupMenuButton<String>(
                        color: Ui.panel,
                        icon: Icon(Icons.more_vert_rounded,
                            size: 20, color: Ui.muted),
                        onSelected: (_) => _delete(context),
                        itemBuilder: (_) => [
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: Row(children: [
                              Icon(Icons.delete_outline_rounded,
                                  size: 20, color: Ui.red),
                              const SizedBox(width: 10),
                              Text('Delete'.tr),
                            ]),
                          ),
                        ],
                      ),
                  ],
                )
              else
                Row(
                  children: [
                    _KindBadge(recommendation: post.recommendation),
                    const SizedBox(width: 8),
                    Text(timeAgo(post.createdAt),
                        style: TextStyle(color: Ui.muted, fontSize: 11.5)),
                    const Spacer(),
                    if (post.mine)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _delete(context),
                        icon: Icon(Icons.delete_outline_rounded,
                            size: 20, color: Ui.muted),
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: detail ? null : () => openCommunityPost(context, post),
                child: Text(post.text,
                    maxLines: detail ? null : 8,
                    overflow: detail ? null : TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, height: 1.42)),
              ),
              if (post.hasMovie) ...[
                const SizedBox(height: 12),
                PostMovie(post: post),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  _ActionButton(
                    onTap: () => _like(context),
                    color: liked ? const Color(0xFFFF4D79) : Ui.muted,
                    count: post.likeCount,
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (c, a) =>
                          ScaleTransition(scale: a, child: c),
                      child: Icon(
                        liked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        key: ValueKey<bool>(liked),
                        size: 22,
                        color: liked ? const Color(0xFFFF4D79) : Ui.muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _ActionButton(
                    onTap: detail ? null : () => openCommunityPost(context, post),
                    color: Ui.muted,
                    count: post.commentCount,
                    icon: Icon(Icons.mode_comment_outlined,
                        size: 21, color: Ui.muted),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  final Widget icon;
  final int count;
  final Color color;
  final VoidCallback? onTap;
  const _ActionButton(
      {required this.icon,
      required this.count,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 6),
            Text('$count',
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w800, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// Friendly empty / error block.
class CommunityMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  final String? action;
  final VoidCallback? onAction;
  const CommunityMessage(
      {super.key,
      required this.icon,
      required this.title,
      required this.hint,
      this.action,
      this.onAction});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: Ui.dim),
            const SizedBox(height: 14),
            Text(title.tr,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(hint.tr,
                textAlign: TextAlign.center,
                style: TextStyle(color: Ui.muted, fontSize: 13, height: 1.4)),
            if (action != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(action!.tr)),
            ],
          ],
        ),
      ),
    );
  }
}
