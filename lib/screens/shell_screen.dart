import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/content_sync.dart';
import '../services/download_manager.dart';
import '../services/movie_library.dart';
import '../services/notice_service.dart';
import '../theme/app_theme.dart';
import '../utils/l10n.dart';
import '../widgets/app_drawer.dart';
import '../widgets/glass.dart';
import 'browse_screen.dart';
import 'downloads_screen.dart';
import 'library_screen.dart';
import 'movies_screen.dart';

/// The whole app: Movies, Browser, Downloads and My Library.
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen>
    with WidgetsBindingObserver {
  int _index = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  DateTime? _lastBack;
  Timer? _autoRefresh;

  @override
  void initState() {
    super.initState();

    // Keep the movie lists current without the person having to pull down.
    WidgetsBinding.instance.addObserver(this);
    _autoRefresh = Timer.periodic(
      const Duration(seconds: 60),
      (_) => ContentSync.request(),
    );

    // notice.json: pop up once per notice id, a moment after the app opens.
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) NoticeService.instance.showOnStart(context);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ContentSync.request(force: true);
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onBack() {
    final state = _scaffoldKey.currentState;
    if (state != null && state.isDrawerOpen) {
      state.closeDrawer();
      return;
    }
    // From any other tab, back goes home first.
    if (_index != 0) {
      setState(() => _index = 0);
      return;
    }
    final now = DateTime.now();
    if (_lastBack != null &&
        now.difference(_lastBack!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBack = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Tap back more to exit'.tr),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: const DamiMoviesDrawer(),
        extendBody: false,
        body: IndexedStack(
          index: _index,
          children: const [
            MoviesScreen(),
            BrowseScreen(),
            DownloadsScreen(),
            LibraryScreen(),
          ],
        ),
        bottomNavigationBar: _FloatingNav(
          index: _index,
          onTap: (i) => setState(() => _index = i),
          items: [
            _NavItem(Icons.home_outlined, Icons.home_rounded, 'Home'.tr),
            _NavItem(Icons.public_outlined, Icons.public_rounded, 'Browser'.tr),
            _NavItem(
              Icons.download_outlined,
              Icons.download_rounded,
              'Downloads'.tr,
              badge: DownloadManager.instance,
              count: () => DownloadManager.instance.activeCount,
            ),
            _NavItem(
              Icons.bookmark_border_rounded,
              Icons.bookmark_rounded,
              'Library'.tr,
              badge: MovieLibrary.instance,
              count: () => MovieLibrary.instance.watchLater.length,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Listenable? badge;
  final int Function()? count;
  const _NavItem(this.icon, this.selectedIcon, this.label,
      {this.badge, this.count});
}

/// Floating glass tab bar: the chosen tab grows into an accent-gradient pill
/// with its label; the others show just their icon.
class _FloatingNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<_NavItem> items;
  const _FloatingNav(
      {required this.index, required this.onTap, required this.items});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      color: Ui.bg,
      padding: EdgeInsets.fromLTRB(14, 6, 14, bottom > 0 ? bottom : 10),
      child: Glass(
        radius: 26,
        blur: 20,
        tint: Ui.card.withValues(alpha: .85),
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(flex: i == index ? 21 : 10, child: _tab(i)),
          ],
        ),
      ),
    );
  }

  Widget _tab(int i) {
    final it = items[i];
    final on = i == index;
    Widget icon(bool on) {
      final w = Icon(on ? it.selectedIcon : it.icon,
          size: 24, color: on ? Ui.palette.onAccent : Ui.muted);
      if (it.badge == null) return w;
      return ListenableBuilder(
        listenable: it.badge!,
        builder: (_, _) {
          final n = it.count!();
          return Badge(
            isLabelVisible: n > 0 && !on,
            label: Text('$n'),
            backgroundColor: Ui.red,
            child: w,
          );
        },
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap(i);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        height: 46,
        decoration: BoxDecoration(
          gradient: on ? Ui.gradient : null,
          borderRadius: BorderRadius.circular(20),
          boxShadow: on
              ? [
                  BoxShadow(
                      color: Ui.red.withValues(alpha: .4),
                      blurRadius: 14,
                      offset: const Offset(0, 4))
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon(on),
            if (on)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(it.label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: Ui.palette.onAccent)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
