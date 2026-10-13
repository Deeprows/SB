/// Central place for the things you are most likely to edit.
class AppConfig {
  static const appName = 'Streambox';

  /// Google sign-in (Gmail only). Optional "Web client ID" from Google Cloud
  /// Console -> Credentials; only needed if you also want an ID token for
  /// your own server. Pass with `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`.
  /// The Android OAuth client (package + SHA-1) is what makes sign-in work,
  /// see AUTH.md.
  static const googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// Turn the login page off (anyone can enter) while testing.
  static const loginRequired = true;

  /// Set by the build using `--dart-define=APP_VERSION=...`.
  /// Falls back to `dev` when no build-time version is provided.
  static const appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

  /// Drawer menu links. Leave a value empty to make its menu item show a
  /// "not set up yet" message instead of opening anything.
  static const websiteUrl = '';
  static const joinUrl =
      'https://t.me/deeprows'; // Telegram / WhatsApp / Discord invite link
  static const updateUrl = ''; // direct APK link (app_config.json "update.apkUrl" wins)

  /// Settings you can change any time without a new APK (support-ad link,
  /// movie player / download links, app update link, live-chat switch):
  /// edit assets/data/app_config.json in your GitHub repo (see
  /// REMOTE_CONFIG.md). Empty = only the bundled copy and the defaults below.
  static const remoteConfigUrl = '';

  /// Notice you can change without a new APK: edit assets/data/notice.json in
  /// your GitHub repo (see NOTICE.md). Shown in the menu's "Notice" item and,
  /// when the file says "popup": true, once when the app opens.
  /// Empty = only the bundled assets/data/notice.json is used.
  static const noticeUrl = '';

  /// Origin used as the base URL of the built-in HLS / MP4 / DASH player page.
  /// Some stream hosts only allow requests coming from your own site, so this
  /// mirrors the site the streams were originally played on.
  static const playerOrigin = 'https://deeprowss.com/';

  /// Movies and series are listed in `assets/data/movies.json` (bundled in
  /// the app) plus TMDB trending / categories / search (see below). Set
  /// [moviesUrl] to a raw JSON link (same shape as movies.json) to add titles
  /// without a new APK. Empty = bundled list only.
  static const moviesUrl = '';

  /// Cloudflare feed (traffic monitoring). When set, a remote movies list
  /// is downloaded from `<feedBase>/feed/movies.json`
  /// through your Cloudflare Worker (see `cloudflare/README.md`), which fetches
  /// them from GitHub and records anonymous usage. If the Worker is down the
  /// app falls back to the GitHub links above, so keep those set.
  ///
  /// Example: `https://feed.deeprowss.com`.
  /// Empty = download from GitHub only.
  static const feedBase = 'https://deeprowss-feed.deeprows.workers.dev';

  /// ---- Free vs Premium ---------------------------------------------------
  ///
  /// On start the app shows a plans page: FREE (everything, with the
  /// "We Need Your Support" page every [adIntervalMinutes] minutes of use) or
  /// PREMIUM (no ads, paid through Paystack). Needs [feedBase] (the Worker
  /// does the payment work, see SUBSCRIPTIONS.md). false = no plans page and
  /// no ads for anyone.
  static const plansEnabled = true;

  /// false = the Premium / plans screens, the "Go Premium" menu item and the
  /// "Remove ads - go Premium" button are hidden (everything is still built
  /// and ready). Ads keep working. Set true to bring Premium back.
  static const showSubscriptions = false;

  /// ---- Ad-free tokens ------------------------------------------------------
  ///
  /// true = the menu shows "Remove ads". The person taps "Request token", you
  /// answer on the Worker admin page (`/sub/admin?token=<ADMIN_TOKEN>`), and
  /// the token appears in their app (or you send it by chat). Entering a token
  /// removes ALL ads on that phone for the days you chose. Works while
  /// Premium/payments are hidden; needs [feedBase] and the Worker's D1 `DB`.
  /// See TOKENS.md.
  static const showRemoveAds = true;

  /// Chat message that is pre-filled when the person messages you for a token
  /// (their ID is added under it). Uses [whatsappUrl], or [joinUrl] if empty.
  static const tokenRequestMessage =
      'I need token to remove ads from Streambox app';

  /// true: the plans page shows on every launch for people who are not
  /// premium. false: only on the first launch and after a premium ends.
  static const showPlansEveryStart = true;

  /// Shown only until the Worker answers; the real price lives in the
  /// Worker (`PRICE_NGN`, default 2000) so one change updates every phone.
  static const premiumPriceFallbackNgn = 2000;

  /// Yearly price shown until the Worker answers (set PRICE_NGN_YEAR there).
  static const premiumYearPriceFallbackNgn = 20000;

  /// WhatsApp chat for people who cannot pay online (manual activation).
  /// Example: `https://wa.me/2348012345678`. Empty = the button tells the
  /// person it is coming soon. The app adds the person's ID to the message.
  static const whatsappUrl = 'https://wa.me/2348164887683';
  static const whatsappMessage =
      'Hello, I want to pay for Streambox Premium manually.';

  /// ---- "We Need Your Support" ad page (free plan) --------------------------
  ///
  /// Appears after [adIntervalMinutes] minutes of real use (the clock only
  /// runs while the app is open on screen and keeps counting across
  /// launches). Premium people never see it. The person opens
  /// [supportUrl] (your ad / smart link); once it has loaded, [supportViewSeconds]
  /// count down and then "Skip Ad" appears. The page never closes by itself.
  /// [supportUrl] empty = no ads at all.
  static const supportUrl =
      'https://www.profitableratecpmnetwork.com/iqv44jk21?key=c2752cc0c9c553ac66e4fb16cdb95f60';
  static const adIntervalMinutes = 10;
  static const supportViewSeconds = 6; // seconds after load before Skip Ad appears (never auto-closes)

  /// If the support page cannot load (offline / dead link) nobody is locked
  /// out; the overlay comes back after this many minutes of use.
  static const adRetryMinutes = 3;

  /// The FIRST tap on a fixture, highlight, TV channel or movie in each app
  /// launch shows the overlay; after that it comes back every
  /// [adIntervalMinutes] minutes of use. false = timer only.
  static const supportOnFirstTap = true;

  /// false = the "We Need Your Support" overlay (Click Here + instructions) is
  /// HIDDEN. Instead the ad page ([supportUrl]) opens straight away on the
  /// first tap and shows only a short wait message. true = old overlay back.
  static const supportOverlayVisible = false;

  /// Message on the bar while the ad page is loading.
  static const supportWaitText = 'Ad support timeout: please wait';

  /// NOT USED any more by the ad page: once it has fully loaded it stays on
  /// screen until the person taps Skip Ad (it never closes by itself).
  /// Kept only so older references still compile.
  static const supportAfterLoadSeconds = 10;

  /// Seconds after the ad has fully loaded before "Skip Ad" becomes tappable.
  static const supportSkipAfterSeconds = 6;

  /// The ad page is loaded in the BACKGROUND this many seconds before it is
  /// due (and once when the app starts), so it appears instantly when shown.
  /// 0 = no preloading (the page starts loading only when the ad is due).
  static const adPreloadLeadSeconds = 60;
  static const adPreloadOnStart = true;

  /// A preloaded page older than this is thrown away and loaded again.
  static const adPreloadMaxAgeSeconds = 240;

  /// The ad page is never cut off while it is loading. Only if it is still
  /// loading after this many seconds is it treated as loaded (so a page that
  /// never reports "finished" can't hold anyone for ever).
  static const supportMaxLoadSeconds = 40;

  /// Show the "Thanks" banner after the ad page closes.
  static const supportThanksBanner = false;

  /// Old 12-hour card-tap rule (not used any more; kept for the unit test).
  static const supportOnCardTap = false;
  static const supportIntervalHours = 12;
  static const supportRetryHours =
      1; // if the support page can't load, ask again after

  /// ---- TMDB (themoviedb.org) -------------------------------------------
  ///
  /// The TMDB id is the single key for a title: it is turned into the player
  /// link and the download link below, and TMDB supplies the name, poster,
  /// rating, genres and release date.
  ///
  /// v3 API key. Override at build time with
  /// `--dart-define=TMDB_API_KEY=...` (the GitHub workflow can pass a repo
  /// secret). Leave empty to switch every TMDB feature off.
  static const tmdbApiKey = String.fromEnvironment(
    'TMDB_API_KEY',
    defaultValue: 'b83de997ce0ca0406c12cab7f256e43a',
  );

  /// Player (embed) links:  {embedBase}/movie/{tmdb id}  and
  ///                        {embedBase}/tv/{tmdb id}
  static const embedBase = 'https://vsembed.su/embed';

  /// Backup player used by the Switch button on every movie / series page:
  ///   {altEmbedBase}/movie/{tmdb id}
  ///   {altEmbedBase}/tv/{tmdb id}/1/1
  static const altEmbedBase = 'https://web.nxsha.app/embed';

  /// Download links:  {downloadBase}/movie/{tmdb id}  and
  ///                  {downloadBase}/tv/{tmdb id}
  static const downloadBase = 'https://web.nxsha.app/dl';

  /// Adds TMDB's trending movies + series (about 40 titles) after the titles
  /// listed in `movies.json`. Set to false to show only your own list.
  static const tmdbTrending = true;

  /// Picking a category pill (Drama, Action, ...) also lists that category's
  /// popular TMDB movies and series after your own titles.
  static const tmdbCategories = true;

  /// Search box in Movies also searches the whole TMDB catalogue.
  static const tmdbSearch = true;

  /// Used when a fixture has no explicit duration (minutes).
  static const defaultMatchMinutes = 96;

  static const userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';
}
