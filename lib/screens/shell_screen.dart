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
        drawer: const StreamboxDrawer(),
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
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Ui.line)),
          ),
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: Ui.bg,
              surfaceTintColor: Colors.transparent,
              indicatorColor: Colors.transparent,
              height: 62,
              iconTheme: WidgetStateProperty.resolveWith((st) => IconThemeData(
                    size: 26,
                    color: st.contains(WidgetState.selected)
                        ? Colors.white
                        : Ui.dim,
                  )),
              labelTextStyle: WidgetStateProperty.resolveWith((st) => TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: st.contains(WidgetState.selected)
                        ? Colors.white
                        : Ui.dim,
                  )),
            ),
            child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home_filled),
                label: 'Home'.tr,
              ),
              NavigationDestination(
                icon: const Icon(Icons.public_outlined),
                selectedIcon: const Icon(Icons.public_rounded),
                label: 'Browser'.tr,
              ),
              NavigationDestination(
                icon: ListenableBuilder(
                  listenable: DownloadManager.instance,
                  builder: (_, _) => Badge(
                    isLabelVisible: DownloadManager.instance.activeCount > 0,
                    label: Text('${DownloadManager.instance.activeCount}'),
                    backgroundColor: Ui.red,
                    child: const Icon(Icons.download_outlined),
                  ),
                ),
                selectedIcon: const Icon(Icons.download_rounded),
                label: 'Downloads'.tr,
              ),
              NavigationDestination(
                icon: ListenableBuilder(
                  listenable: MovieLibrary.instance,
                  builder: (_, _) => Badge(
                    isLabelVisible: MovieLibrary.instance.watchLater.isNotEmpty,
                    label: Text('${MovieLibrary.instance.watchLater.length}'),
                    backgroundColor: Ui.red,
                    child: const Icon(Icons.bookmark_border_rounded),
                  ),
                ),
                selectedIcon: const Icon(Icons.bookmark_rounded),
                label: 'Library'.tr,
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
