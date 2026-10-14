import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/settings_service.dart';

/// One complete colour set. `accent` is the brand colour (used where the
/// code says `Ui.red`), `accentSoft` its lighter companion.
class Palette {
  final String name;
  final String tagline;
  final Color bg;
  final Color panel;
  final Color card;
  final Color cardDeep;
  final Color accent;
  final Color accentSoft;
  final Color muted;
  final Color dim;
  final Color line;
  final Color green;

  /// Text / icon colour on top of [accent] (dark for light accents).
  final Color onAccent;

  /// Big faint mark drawn over the whole app while this theme is selected
  /// (null = none). Optional; no DamiMovies theme uses it.
  final String? watermark;

  /// Faint black-and-white jersey stripes over the whole app.
  final bool stripes;

  /// Colour of those stripes (white for CR7, celeste for Messi).
  final Color stripeColor;

  /// Optional picture (an asset path) drawn faintly at the bottom of the
  /// screen. Nothing is shown when the file is missing.
  final String? backdropAsset;

  const Palette({
    required this.name,
    required this.tagline,
    required this.bg,
    required this.panel,
    required this.card,
    required this.cardDeep,
    required this.accent,
    required this.accentSoft,
    required this.muted,
    required this.dim,
    this.line = const Color(0x1FFFFFFF),
    this.green = const Color(0xFF22E07A),
    this.onAccent = Colors.white,
    this.watermark,
    this.stripes = false,
    this.stripeColor = Colors.white,
    this.backdropAsset,
  });
}

class Palettes {
  /// DamiMovies default: deep violet night with a soft purple glow.
  static const violet = Palette(
    name: 'Midnight Violet',
    tagline: 'Deep violet night, soft purple glow',
    bg: Color(0xFF09060F),
    panel: Color(0xFF110C1B),
    card: Color(0xFF161022),
    cardDeep: Color(0xFF0D0916),
    accent: Color(0xFF8B5CF6),
    accentSoft: Color(0xFFBBA2FF),
    muted: Color(0xFFB8B0CC),
    dim: Color(0xFF7B7390),
  );

  static const crimson = Palette(
    name: 'Crimson Cinema',
    tagline: 'Red carpet red on midnight black',
    bg: Color(0xFF0A0709),
    panel: Color(0xFF130C10),
    card: Color(0xFF181015),
    cardDeep: Color(0xFF0E080B),
    accent: Color(0xFFFF2D55),
    accentSoft: Color(0xFFFF7A93),
    muted: Color(0xFFC4B2B8),
    dim: Color(0xFF86707A),
  );

  static const ocean = Palette(
    name: 'Ocean Blue',
    tagline: 'Deep navy with electric blue',
    bg: Color(0xFF050B16),
    panel: Color(0xFF0B1527),
    card: Color(0xFF0E1B30),
    cardDeep: Color(0xFF08111F),
    accent: Color(0xFF2979FF),
    accentSoft: Color(0xFF7FB0FF),
    muted: Color(0xFFA7B8D0),
    dim: Color(0xFF6C7F9A),
  );

  static const emerald = Palette(
    name: 'Emerald Night',
    tagline: 'Forest dark with a fresh green glow',
    bg: Color(0xFF040C08),
    panel: Color(0xFF0A1710),
    card: Color(0xFF0D1D14),
    cardDeep: Color(0xFF07130D),
    accent: Color(0xFF00B574),
    accentSoft: Color(0xFF4FDDA6),
    muted: Color(0xFFAAC0B3),
    dim: Color(0xFF72877B),
  );

  static const gold = Palette(
    name: 'Golden Hour',
    tagline: 'Premiere-night gold on warm black',
    bg: Color(0xFF0B0904),
    panel: Color(0xFF15110A),
    card: Color(0xFF1B160D),
    cardDeep: Color(0xFF100D07),
    accent: Color(0xFFFFB400),
    accentSoft: Color(0xFFFFD36B),
    muted: Color(0xFFCDBF9F),
    dim: Color(0xFF8A7F66),
    onAccent: Color(0xFF1A1100),
  );

  static const sunset = Palette(
    name: 'Sunset Orange',
    tagline: 'Warm orange over dusk brown',
    bg: Color(0xFF0E0806),
    panel: Color(0xFF181009),
    card: Color(0xFF1E140D),
    cardDeep: Color(0xFF130C07),
    accent: Color(0xFFFF6B2C),
    accentSoft: Color(0xFFFFA074),
    muted: Color(0xFFD1BBAE),
    dim: Color(0xFF8F7667),
  );

  static const neon = Palette(
    name: 'Neon Cyan',
    tagline: 'Electric cyan on ink black',
    bg: Color(0xFF03090D),
    panel: Color(0xFF08131A),
    card: Color(0xFF0A1820),
    cardDeep: Color(0xFF050E13),
    accent: Color(0xFF00E5FF),
    accentSoft: Color(0xFF7DF3FF),
    muted: Color(0xFFA6C4CC),
    dim: Color(0xFF678893),
    onAccent: Color(0xFF021217),
  );

  static const rose = Palette(
    name: 'Rose',
    tagline: 'Soft pink glow on deep plum',
    bg: Color(0xFF12060E),
    panel: Color(0xFF1B0C16),
    card: Color(0xFF211019),
    cardDeep: Color(0xFF160912),
    accent: Color(0xFFFF4D8D),
    accentSoft: Color(0xFFFF9EC4),
    muted: Color(0xFFD1B3C2),
    dim: Color(0xFF93707F),
  );

  static const amoled = Palette(
    name: 'Pure Black',
    tagline: 'True black for OLED screens, silver accents',
    bg: Color(0xFF000000),
    panel: Color(0xFF0A0A0A),
    card: Color(0xFF111111),
    cardDeep: Color(0xFF050505),
    accent: Color(0xFFE5E7EB),
    accentSoft: Color(0xFFFFFFFF),
    muted: Color(0xFFC2C2C2),
    dim: Color(0xFF7C7C7C),
    onAccent: Color(0xFF0A0A0A),
  );

  static const all = [
    violet,
    crimson,
    ocean,
    emerald,
    gold,
    sunset,
    neon,
    rose,
    amoled,
  ];
}

/// Design tokens. Values follow the active [Palette], so they are getters.
class Ui {
  static Palette palette = Palettes.violet;

  static Color get bg => palette.bg;
  static Color get panel => palette.panel;
  static Color get card => palette.card;
  static Color get cardDeep => palette.cardDeep;
  static Color get red => palette.accent;
  static Color get redSoft => palette.accentSoft;
  static Color get muted => palette.muted;
  static Color get dim => palette.dim;
  static Color get line => palette.line;
  static Color get green => palette.green;
  static const radius = 16.0;
  static const radiusL = 22.0;

  /// Brand gradient (accent -> its soft companion) for primary buttons.
  static LinearGradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [palette.accent, palette.accentSoft],
      );

  /// Soft glass fill used by floating panels and chips.
  static Color get glass => Colors.white.withValues(alpha: .08);
  static Color get glassLine => Colors.white.withValues(alpha: .14);
}

/// Holds the selected theme, saves it, and repaints the whole app when it
/// changes (without losing the current screen).
class ThemeController {
  static final ValueNotifier<int> index = ValueNotifier<int>(0);

  static Future<void> load() async {
    final i = await Settings.themeIndex();
    _apply(i.clamp(0, Palettes.all.length - 1));
  }

  static void _apply(int i) {
    Ui.palette = Palettes.all[i];
    index.value = i;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Ui.panel,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  }

  static Future<void> set(int i) async {
    _apply(i);
    await Settings.setThemeIndex(i);
    // Many widgets read Ui.* directly, so mark every element for rebuild.
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return;
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    root.visitChildren(mark);
  }
}

ThemeData buildTheme() {
  final scheme = ColorScheme.dark(
    primary: Ui.red,
    onPrimary: Ui.palette.onAccent,
    secondary: Ui.redSoft,
    surface: Ui.panel,
    onSurface: Colors.white,
    error: Ui.red,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: Ui.bg,
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: Ui.bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: const TextStyle(
          fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.3),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.label,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Ui.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Ui.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Ui.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Ui.red.withValues(alpha: .8)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Ui.panel,
      height: 68,
      elevation: 0,
      indicatorColor: Ui.red.withValues(alpha: .16),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final on = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: on ? FontWeight.w800 : FontWeight.w600,
          color: on ? Colors.white : Ui.dim,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final on = states.contains(WidgetState.selected);
        return IconThemeData(color: on ? Ui.red : Ui.dim, size: 26);
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Ui.card,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Ui.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: Ui.cardDeep),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Ui.panel,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
  );
}
