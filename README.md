# Streambox (Flutter)

A movies-and-series app built from the Movies section of the Deeprowss app.

**Tabs:** Movies · Browser · Downloads · Library (Watch later + Watch history)

**Home (Netflix style):** billboard for today's #1 trending title (Play / My List), rows for Continue Watching, Trending Now, Top 10 Today, My List, New, Popular Movies, TV Shows and categories; search, Series / Movies / Categories chips and a poster grid (`lib/screens/movies_screen.dart`, `lib/widgets/netflix_widgets.dart`).

**Movie page:** Netflix-style title page (artwork + play button, match / year / length, white Play and grey Download buttons, synopsis, cast, My List / Share, More Like This / Details tabs) in `lib/screens/title_screen.dart`.

**Login:** Gmail-only Login / Sign up page with a movie-poster background (see `AUTH.md` for the one-time Google setup).

## What's inside

* **Movies** – daily-shuffled poster grid, TMDB trending / categories / search, movie page with player, backup player (Switch), cast and details. `assets/data/movies.json` holds your own titles (TMDB id only is enough, see below).
* **In-app browser + downloads** – the Download button on a movie opens the download page *inside Streambox* (pop-ups and ad redirects blocked). Any file the page hands over (mkv, mp4, zip, apk, pdf …) is saved by the in-app download manager: background downloads, progress notification, pause / resume / retry, open, delete. The **Browser** tab lets you type a web address or a search and download from any site the same way. Menu → *Download this link* downloads the current page's link.
* **Support ads (all kept from Deeprowss)** – "Ad support" page on first tap and every `adIntervalMinutes`, background preloading, Skip Ad countdown, ad shield, Free/Premium start page, token-based "Remove ads". All switches are in `lib/config.dart` / `assets/data/app_config.json`.
* **9 themes** – Midnight Violet (default), Crimson Cinema, Ocean Blue, Emerald Night, Golden Hour, Sunset Orange, Neon Cyan, Rose, Pure Black. Pick from the palette icon on the Movies header or Menu → Themes; the choice is saved.
* Languages, notice pop-up, update checker, share app, picture-in-picture, background playback – unchanged.

## Removed compared to Deeprowss

Football fixtures, highlights, TV channels, live scores, match chat, the Player hub (music / local video), push notifications and Firebase (no `google-services` / Firebase variables needed any more), and the Deeprows Browser promotion.

## Before you publish – things to set

1. `lib/config.dart`
   * `feedBase` still points at your Deeprowss Cloudflare Worker (needed for Premium and ad-free tokens, usage counts and shared tokens). Deploy a separate Worker (`cloudflare/`) if you want Streambox kept apart, or set it to `''` to switch Premium/tokens off.
   * `remoteConfigUrl`, `noticeUrl`, `moviesUrl` are empty (bundled files only). Host `assets/data/app_config.json` / `notice.json` / `movies.json` on GitHub and paste the raw links to change things without a new APK.
   * `joinUrl`, `whatsappUrl`, `supportUrl` (ad link), `tmdbApiKey` are carried over from Deeprowss – replace if you want Streambox to have its own.
2. GitHub → Settings → Secrets: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` (a **new** keystore is recommended so Streambox is a separate app). The workflow builds `com.deeprows.streambox`.
3. Add titles: `{ "tmdbId": 693134, "type": "movie" }` in `assets/data/movies.json`.

## Build

```
flutter create . --platforms=android --project-name=streambox --org com.deeprows
flutter pub get
dart run flutter_native_splash:create
dart run flutter_launcher_icons
python3 tool/patch_android_manifest.py
python3 tool/patch_min_sdk.py
python3 tool/patch_main_activity.py
python3 tool/patch_background_playback.py
python3 tool/patch_compile_sdk.py
flutter run
```

The included GitHub workflow does all of this and uploads a signed APK.

Content is provided by third-party sources; Streambox does not host or own any movie or series.
