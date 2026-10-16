import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/movie.dart';
import '../services/auth_service.dart';
import '../services/community_service.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../utils/l10n.dart';
import '../widgets/community_widgets.dart';
import '../widgets/glass.dart';

/// Opens the "new post" sheet. Pass [movie] to start with a title attached
/// (the Tweet button on a title page does). Returns true when it posted.
Future<bool> showCommunityComposer(
  BuildContext context, {
  Movie? movie,
  bool recommendation = false,
}) async {
  final svc = CommunityService.instance;
  if (!svc.available) {
    communityToast(context, const CommunityException('unavailable').message);
    return false;
  }
  if (!svc.signedIn) {
    communityToast(context, const CommunityException('google_required').message);
    return false;
  }
  final posted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Ui.panel,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (_) => _Composer(movie: movie, recommendation: recommendation),
  );
  if (posted == true && context.mounted) {
    communityToast(context, 'Posted');
  }
  return posted == true;
}

class _Composer extends StatefulWidget {
  final Movie? movie;
  final bool recommendation;
  const _Composer({required this.movie, required this.recommendation});

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _text = TextEditingController();
  late bool _recommend = widget.recommendation;
  late Movie? _movie = widget.movie;
  int _rating = 0; // 0-10
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _ready =>
      _text.text.trim().isNotEmpty && (!_recommend || _movie != null);

  Future<void> _pickMovie() async {
    final m = await showModalBottomSheet<Movie>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Ui.panel,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => const _MoviePicker(),
    );
    if (m != null && mounted) setState(() => _movie = m);
  }

  Future<void> _send() async {
    if (!_ready || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await CommunityService.instance.post(
        text: _text.text,
        recommendation: _recommend,
        movie: _movie,
        rating: _rating,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on CommunityException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = const CommunityException('').message);
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.user;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CommunityAvatar(
                    url: user?.photoUrl ?? '',
                    name: user?.name ?? '',
                    radius: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(user?.name ?? 'Movie fan'.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Glass(
              radius: 16,
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  _segment('Movie tweet', Icons.chat_bubble_rounded, !_recommend,
                      () => setState(() => _recommend = false)),
                  _segment('Recommendation', Icons.thumb_up_alt_rounded,
                      _recommend, () => setState(() => _recommend = true)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _text,
              autofocus: widget.movie == null,
              minLines: 4,
              maxLines: 8,
              maxLength: 500,
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: (_recommend
                        ? 'Why should people watch it?'
                        : 'What are you watching?')
                    .tr,
                filled: true,
                fillColor: Colors.white.withValues(alpha: .05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Ui.glassLine),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Ui.glassLine),
                ),
              ),
            ),
            const SizedBox(height: 6),
            if (_movie == null)
              OutlinedButton.icon(
                onPressed: _pickMovie,
                icon: const Icon(Icons.movie_filter_rounded, size: 20),
                label: Text((_recommend ? 'Pick a movie (required)' : 'Attach a movie').tr),
              )
            else
              _attached(),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!.tr,
                  style: TextStyle(color: Ui.red, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 16),
            Opacity(
              opacity: _ready && !_sending ? 1 : .45,
              child: GradientButton(
                label: _sending ? 'Posting…'.tr : 'Post'.tr,
                icon: Icons.send_rounded,
                onTap: _send,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment(String label, IconData icon, bool on, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            gradient: on ? Ui.gradient : null,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16, color: on ? Ui.palette.onAccent : Ui.muted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: on ? Ui.palette.onAccent : Ui.muted)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attached() {
    final m = _movie!;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Ui.glassLine),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 44,
                  height: 64,
                  child: m.image.startsWith('http')
                      ? CachedNetworkImage(
                          imageUrl: m.image,
                          fit: BoxFit.cover,
                          memCacheWidth: 160,
                          errorWidget: (_, _, _) =>
                              ColoredBox(color: Ui.cardDeep),
                        )
                      : ColoredBox(color: Ui.cardDeep),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(m.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14.5)),
              ),
              IconButton(
                tooltip: 'Remove'.tr,
                onPressed: () => setState(() {
                  _movie = null;
                  _rating = 0;
                }),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('Your rating'.tr,
                  style: TextStyle(color: Ui.muted, fontSize: 12.5)),
              const Spacer(),
              for (var i = 1; i <= 5; i++)
                GestureDetector(
                  onTap: () =>
                      setState(() => _rating = _rating == i * 2 ? 0 : i * 2),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(
                      _rating >= i * 2
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 30,
                      color: const Color(0xFFFFC107),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Search any movie or series and tap one to attach it.
class _MoviePicker extends StatefulWidget {
  const _MoviePicker();

  @override
  State<_MoviePicker> createState() => _MoviePickerState();
}

class _MoviePickerState extends State<_MoviePicker> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Movie> _found = const [];
  bool _busy = false;
  String _last = '';

  @override
  void initState() {
    super.initState();
    _loadTrending();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _loadTrending() async {
    if (!TmdbService.enabled) return;
    setState(() => _busy = true);
    final list = await tmdb.trending(fetch: true);
    if (!mounted) return;
    if (_q.text.trim().length >= 2) return; // a search is already showing
    setState(() {
      _found = list;
      _busy = false;
    });
  }

  void _changed(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (q.length < 2) {
      _loadTrending();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _busy = true);
      _last = q;
      final res = await tmdb.search(q);
      if (!mounted || _last != q) return;
      setState(() {
        _found = res;
        _busy = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * .8;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _q,
                autofocus: true,
                onChanged: _changed,
                decoration: InputDecoration(
                  hintText: 'Search any movie or series…'.tr,
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
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _found.isEmpty && !_busy
                  ? const CommunityMessage(
                      icon: Icons.movie_filter_outlined,
                      title: 'Nothing found',
                      hint: 'Try another title.')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 20),
                      itemCount: _found.length,
                      itemBuilder: (_, i) {
                        final m = _found[i];
                        return ListTile(
                          onTap: () => Navigator.of(context).pop(m),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 40,
                              height: 58,
                              child: m.image.startsWith('http')
                                  ? CachedNetworkImage(
                                      imageUrl: m.image,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 140,
                                      errorWidget: (_, _, _) =>
                                          ColoredBox(color: Ui.cardDeep),
                                    )
                                  : ColoredBox(color: Ui.cardDeep),
                            ),
                          ),
                          title: Text(m.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800)),
                          subtitle: Text(
                              [
                                (m.isSeries ? 'Series' : 'Movie').tr,
                                if (m.year != null) m.year!,
                                if (m.rating != null) '★ ${m.rating}',
                              ].join(' · '),
                              style: TextStyle(color: Ui.muted, fontSize: 12)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
