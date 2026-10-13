# Monitor app traffic with Cloudflare

The app downloads its lists (fixtures, highlights, movies, TV, ticker) from a
Cloudflare Worker that you own. The Worker gets the files from GitHub, keeps a
30-second copy at Cloudflare's edge and records anonymous usage. You then see:

* **Cloudflare dashboard** - Workers > your Worker > Metrics (requests, errors),
  and (if your domain is on Cloudflare) Analytics > Traffic (countries,
  status codes, bandwidth).
* **Your own page** - `https://<worker-address>/stats?token=<STATS_TOKEN>` shows
  distinct phones and requests per day, countries, app versions, files.

Streams (video) do not pass through Cloudflare; only these list downloads do.
If `deeprowss.com` is proxied (orange cloud) in Cloudflare, the match-chat
traffic to that site already shows up in that zone's Analytics.

## Setup (works from a phone browser, no computer needed)

1. dash.cloudflare.com > **Workers & Pages** > **Create** > **Hello World** >
   Deploy. Then **Edit code**, delete everything, paste `cloudflare/worker.js`,
   **Deploy**.
2. **Settings > Domains & Routes**: use the free `...workers.dev` address, or
   **Add > Custom domain** `feed.deeprowss.com` (the domain must be on
   Cloudflare).
3. **Settings > Bindings > Add > Analytics Engine**: variable name `ANALYTICS`,
   dataset `deeprowss_app`.
4. For the stats page, **Settings > Variables and Secrets > Add** (type Secret):
   * `STATS_TOKEN` - any long random text (you will use it in the stats link)
   * `CF_ACCOUNT_ID` - shown on the right of the Cloudflare dashboard home
   * `CF_API_TOKEN` - My Profile > API Tokens > Create Token > Custom token >
     permission **Account > Account Analytics > Read**
5. Open `https://<worker-address>/feed/movies.json`. You should see your movies
   JSON.
6. In the app's `lib/config.dart` set
   `static const feedBase = 'https://<worker-address>';` (no trailing slash).
   Keep the GitHub links (`fixturesUrl`, ...) set: they are the fallback if the
   Worker is ever down. Commit; the build produces the new APK.

Check: use the new APK, then open the `/stats?token=...` page (data appears
after a minute or two).

## Nothing shows up? Check in this order

1. Open `https://<worker-address>/health`. It must show
   `"analytics":true` and (for the stats page) `"stats":true`.
   * `analytics:false` -> step 3 above is missing: **Settings > Bindings >
     Add > Analytics Engine**, variable name exactly `ANALYTICS`, dataset
     `deeprowss_app`. Without it the app still works but nothing is recorded.
   * `stats:false` -> add the three secrets from step 4.
   * No `analytics` field at all -> the deployed Worker is an old copy; paste
     the current `cloudflare/worker.js` and **Deploy** again.
2. Open the app once on a phone with internet (use the APK built by GitHub
   Actions, not `flutter run` in debug, if you want the real app version).
3. Wait 1-2 minutes, then open `/stats?token=<STATS_TOKEN>`.
   "App opens" counts one launch (or a return after 30+ minutes away); a ping
   that fails is retried up to 3 times.

Data is sampled by install id, so distinct-phone counts stay accurate even at
higher traffic.

## Good to know

* **Free plan limit:** 100,000 Worker requests per day. One open app makes
  about 60 requests per hour (5 files every 5 minutes) plus pull-to-refreshes,
  so roughly 1,600 hours of app use per day fit. Beyond that the Workers Paid
  plan ($5/month) allows 10 million. If the limit is hit the app silently falls
  back to GitHub.
* **Privacy:** the app sends an anonymous random install id, the app version
  and "android". Cloudflare derives the country from the connection and also
  sees IP addresses in its own logs. Mention analytics in your privacy policy
  (and in Google Play's Data safety form if you publish there).
* **Freshness:** new items reach phones within about 10-60 seconds
  (`FEED_TTL` variable, in seconds, changes it; default 10, `0` = no edge cache). `fixtures` and `ticker` are never edge-cached, so the Live screen is always fresh.
* Tests: `node cloudflare/worker.test.mjs`.
