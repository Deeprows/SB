import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/movie.dart';
import '../services/rating_service.dart';
import '../theme/app_theme.dart';
import '../utils/l10n.dart';

/// "Rate this" card for the title page: five tappable stars (tap the same
/// star again to clear) and, when the server has votes, the community score.
class RateThis extends StatefulWidget {
  final Movie movie;
  const RateThis({super.key, required this.movie});

  @override
  State<RateThis> createState() => _RateThisState();
}

class _RateThisState extends State<RateThis> {
  final _svc = RatingService.instance;

  @override
  void initState() {
    super.initState();
    _svc.load();
    _svc.refresh(widget.movie);
  }

  static const _gold = Color(0xFFFFC107);

  String _label(int mine) {
    switch (mine) {
      case 1:
        return 'Poor'.tr;
      case 2:
        return 'Fair'.tr;
      case 3:
        return 'Good'.tr;
      case 4:
        return 'Great'.tr;
      case 5:
        return 'Loved it'.tr;
    }
    return 'Tap a star to rate'.tr;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _svc,
      builder: (context, _) {
        final mine = _svc.mine(widget.movie);
        final com = _svc.community(widget.movie);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Ui.glassLine),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(mine > 0 ? 'Your rating'.tr : 'Rate this'.tr,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  if (com != null && com.count > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded, size: 16, color: _gold),
                        const SizedBox(width: 3),
                        Text(com.avg.toStringAsFixed(1),
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w900)),
                        Text('  (${com.count})',
                            style: TextStyle(color: Ui.dim, fontSize: 12)),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (var i = 1; i <= 5; i++)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _svc.rate(widget.movie, mine == i ? 0 : i);
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 160),
                          scale: i == mine ? 1.15 : 1,
                          child: Icon(
                            i <= mine
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 40,
                            color: i <= mine ? _gold : Ui.dim,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(_label(mine),
                  style: TextStyle(
                      color: mine > 0 ? _gold : Ui.muted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        );
      },
    );
  }
}
