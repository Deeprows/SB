# DamiMovies Movie Community setup

This change adds a Movie Community tab, a shared tweet/recommendation feed, likes, comments, public member profiles, and a people directory. Community data is stored in the existing Cloudflare D1 database through `cloudflare/worker.js`.

## 1. Configure Google ID-token verification

The app uses Google Sign-In, but the community does **not** trust a typed email address. Each community request sends a Google ID token and the Worker asks Google to validate it.

1. Open Google Cloud Console → APIs & Services → Credentials.
2. Create or use a **Web application OAuth client ID** for the same Google Cloud project used by Android Google Sign-In. This is the **Web client ID**, not the Android client ID.
3. Add this value to the GitHub Actions build as a Dart define:

   `--dart-define=GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID`

   If the workflow passes Dart defines through GitHub Secrets, add a secret named `GOOGLE_SERVER_CLIENT_ID` and pass it to the Flutter build command. The resulting build must include this define.
4. In Cloudflare → Workers → your feed Worker → Settings → Variables and Secrets, add `GOOGLE_CLIENT_ID` with the exact same Web client ID. This value is not a secret, but can be configured as a variable.
5. Keep the existing D1 database binding named `DB` attached to the Worker.
6. Deploy the updated `cloudflare/worker.js`.

The Worker creates the community tables automatically when the first community request arrives. No manual SQL migration is required.

## 2. Verify setup

Open `https://streambox-feed.deeprows.workers.dev/health`. The response should include `"community":true`.

Build and install the app with the Web client ID Dart define, sign in through the Google account picker, open **Community**, publish a test tweet, then check the feed from a second device/account. Try liking it, commenting, and opening the author's profile.

## 3. Important behavior

- Only a Google-verified Gmail identity with a valid ID token can read or change community data.
- The token audience must match `GOOGLE_CLIENT_ID` on the Worker.
- A typed Gmail fallback may still let someone enter the rest of the app, but it cannot post, like, comment, or access community APIs unless Google Sign-In can provide a valid ID token.
- Posts and comments are limited to 500 characters. Post likes are unique per account.
- Community endpoints (all need the Google ID token):
  `GET /community/posts?kind=tweet|recommendation`, `POST /community/posts`,
  `POST /community/delete`, `POST /community/like`,
  `GET/POST /community/comments`, `POST /community/comments/delete`,
  `GET /community/people`, `GET /community/profile?email=...`
  (the profile includes the person's last tweet and last recommendation).
- Posts come in two kinds: **Movie tweet** and **Recommendation** (a recommendation must have a movie attached). A movie can be picked from TMDB in the post box, or attached with the **Tweet** button on any movie page.
- Owners can delete their own posts; a post owner can also delete any comment under their post.
- Limits: 20 posts per hour and 30 comments per 10 minutes per account.
- Databases created by the first version of the community are upgraded automatically (new columns `kind`, `movie_id`, `movie_type`); existing posts become movie tweets.

## 4. Where it is in the app

* Bottom bar: the **Community** tab (speech-bubbles icon) sits right after Home.
* Menu -> **Movie Community** opens the same feed with a back button.
* Profile tab -> **My community posts**.
* Tap any name or picture to open that person's profile.

## 5. Tests

`node --no-warnings cloudflare/community.test.mjs` (Node 22+) runs the Worker community code against an in-memory database, including the upgrade of an old database.
