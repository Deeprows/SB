import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/community_service.dart';
import '../theme/app_theme.dart';
import '../utils/l10n.dart';
import '../widgets/community_widgets.dart';

/// One post with all its comments and a box to write a new one.
class CommunityPostScreen extends StatefulWidget {
  final CommunityPost post;
  const CommunityPostScreen({super.key, required this.post});

  @override
  State<CommunityPostScreen> createState() => _CommunityPostScreenState();
}

class _CommunityPostScreenState extends State<CommunityPostScreen> {
  final _svc = CommunityService.instance;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<CommunityComment>? _comments;
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _svc.comments(widget.post);
      if (mounted) {
        setState(() {
          _comments = list;
          _error = null;
        });
      }
    } on CommunityException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final ok = await communityTry(
        context, () => _svc.addComment(widget.post, text));
    if (ok) {
      _input.clear();
      await _load();
      if (_scroll.hasClients) {
        await _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _delete(CommunityComment c) async {
    final ok =
        await communityTry(context, () => _svc.deleteComment(widget.post, c));
    if (ok) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.user;
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.bg,
        title: Text('Post'.tr,
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              color: Ui.red,
              onRefresh: _load,
              child: ListView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                children: [
                  PostCard(post: widget.post, detail: true),
                  const SizedBox(height: 18),
                  Text(
                    '${'Comments'.tr} (${widget.post.commentCount})',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  ..._commentList(),
                ],
              ),
            ),
          ),
          _inputBar(user),
        ],
      ),
    );
  }

  List<Widget> _commentList() {
    if (_error != null && _comments == null) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: TextButton(
                onPressed: _load, child: Text('${_error!.tr} · ${'Retry'.tr}')),
          ),
        ),
      ];
    }
    if (_comments == null) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_comments!.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text('Be the first to comment.'.tr,
                style: TextStyle(color: Ui.muted)),
          ),
        ),
      ];
    }
    return [
      for (final c in _comments!)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _CommentTile(comment: c, onDelete: () => _delete(c)),
        ),
    ];
  }

  Widget _inputBar(AuthUser? user) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          14, 8, 8, MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 12),
      decoration: BoxDecoration(
        color: Ui.panel,
        border: Border(top: BorderSide(color: Ui.glassLine)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'Write a comment…'.tr,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: .06),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 6),
            DecoratedBox(
              decoration:
                  BoxDecoration(gradient: Ui.gradient, shape: BoxShape.circle),
              child: IconButton(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Ui.palette.onAccent))
                    : Icon(Icons.send_rounded,
                        size: 20, color: Ui.palette.onAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final CommunityComment comment;
  final VoidCallback onDelete;
  const _CommentTile({required this.comment, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => openCommunityProfile(context, comment.email,
              name: comment.name, photoUrl: comment.photoUrl),
          child: CommunityAvatar(
              url: comment.photoUrl, name: comment.name, radius: 15),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 6, 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Ui.glassLine),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        comment.mine
                            ? '${comment.name} · ${'You'.tr}'
                            : comment.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                    ),
                    Text(timeAgo(comment.createdAt),
                        style: TextStyle(color: Ui.muted, fontSize: 11)),
                    if (comment.canDelete)
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: onDelete,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(Icons.close_rounded,
                              size: 16, color: Ui.muted),
                        ),
                      )
                    else
                      const SizedBox(width: 6),
                  ],
                ),
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(comment.text,
                      style: const TextStyle(fontSize: 14, height: 1.38)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
