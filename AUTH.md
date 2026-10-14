# Gmail login (Login / Sign up)

The first screen is a login page: a moving wall of movie posters (taken from
`assets/data/movies.json`) with one button, **Login with Gmail** /
**Continue with Gmail**, with **Log in** and **Sign up** tabs.

* **Sign up first.** A Gmail that has never signed up cannot log in: it is
  sent to the Sign up tab with "This Gmail has not signed up yet". After
  signing up once, the same Gmail can log in freely.
* Signed-up addresses are stored on the server in the Worker's D1 database
  (`POST /auth/signup`, `POST /auth/login`, table `accounts`, created
  automatically). Redeploy `cloudflare/worker.js` and make sure the `DB`
  binding exists (the same one Premium uses).
* They are also remembered on the phone, so someone who already signed up can
  still log in offline. People who were signed in before this update are
  counted as signed up.
* If `AppConfig.feedBase` is empty, or the Worker has no `DB` yet, the
  registry works on this phone only (a Gmail signed up on another phone
  would have to sign up again).

* Only `@gmail.com` (and `@googlemail.com`) accounts are accepted. Any other
  Google account (for example a work address) is signed out again and the
  person sees "Please use a Gmail account".
* No password and no Firebase. The signed-in account is saved on the phone,
  so people stay logged in and the app still opens offline.
* Menu -> account row at the top shows the avatar, name and Gmail; menu ->
  **Sign out** returns to the login page.
* Set `AppConfig.loginRequired = false` in `lib/config.dart` to switch the
  login page off while testing.

## One-time Google setup (needed, or the button shows "Could not sign in")

1. Google Cloud Console -> create / pick a project.
2. **APIs & Services -> OAuth consent screen**: app name DamiMovies, your
   support email. Choose *External*, then **Publish app** (while it is in
   "Testing", only the test users you add can sign in).
3. **APIs & Services -> Credentials -> Create credentials -> OAuth client ID
   -> Android**
   * Package name: `com.deeprows.streambox`
   * SHA-1: the SHA-1 of the keystore that signs the APK, i.e. your release
     key:
     ```
     keytool -list -v -keystore upload-keystore.jks -alias <KEY_ALIAS>
     ```
     Add a second Android client for the debug key
     (`~/.android/debug.keystore`, password `android`) if you also run
     `flutter run`.
4. (Optional) Create a **Web application** OAuth client and add its client ID
   as the GitHub secret `GOOGLE_SERVER_CLIENT_ID`. The workflow passes it
   with `--dart-define`. It is only needed if your own server must verify
   the ID token; plain sign-in works without it.

Because the app is built by GitHub Actions with your own keystore, the SHA-1
in step 3 must be the one from the `KEYSTORE_BASE64` keystore.

Common errors: `ApiException: 10` or `12500` = the package name / SHA-1 in
step 3 does not match the installed APK (or the consent screen is not
published).

## Getting in while Google is not set up yet

If the Gmail button says "Google sign-in is not set up for this app yet", the
login page shows **Enter your Gmail address instead**. It accepts any
`@gmail.com` address (format only; Google does not verify it) so you can use
the app. Once sign-in works, set `allowGmailFallback = false` in
`lib/config.dart`.

## Where to find the SHA-1

Open the GitHub Actions run -> step **Show signing SHA-1 (for Google sign-in
setup)** (also on the run's Summary page). Copy the package name and SHA-1
into the Android OAuth client in Google Cloud Console.
