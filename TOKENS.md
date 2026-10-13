# Remove ads with a token

A phone asks for a token, you create it, and entering it switches **every ad
off** on that phone for the number of days you choose. It works while Premium /
Paystack stays hidden (`showSubscriptions = false`).

## How people use it

Menu → **Remove ads** (also shown on the support overlay when it is visible).

1. **Request token** – they must type their WhatsApp number (with country code),
   which is how you reach them to confirm payment – or **Buy token on WhatsApp**
   to chat with you directly.
2. The token appears on that screen by itself within about 20 seconds of you
   creating it. Tap **Remove ads now**.
3. Got a token from a chat instead? Type it under **Already have a token?**.

Once ads are removed, the menu item shows **Subscription: Active** with the end
date and days left. Ads stop immediately (the "We Need Your Support" page, its first-tap trigger
and the timer all check the same Premium flag). Time stacks if a phone redeems
more than one token.

## How you hand tokens out

Open `https://deeprowss-feed.deeprows.workers.dev/sub/admin?token=<ADMIN_TOKEN>`

* **Token requests** – every phone that pressed *Request token*, with the WhatsApp
  number it typed and an **Open WhatsApp** link. Choose the days, press **Create token**. That token only
  works on that phone, and the phone shows it by itself. **Dismiss** removes a
  request.
* **Make tokens** – make 1-20 tokens in advance (e.g. to paste into a WhatsApp
  chat). Each works **once**, on any phone.
* **Grant days to an ID** – unchanged; `0` days switches a phone off.
* Lists of unused tokens and of ad-free phones.

## One-time Worker setup (phone browser is enough)

Tokens need only the database and the admin password, **not Paystack**:

1. Cloudflare → Storage & databases → **D1** → create `deeprowss_subs`
   (skip if you already did this for Premium).
2. Your Worker → Settings → Bindings → Add → **D1 database**, variable name
   exactly `DB`.
3. Worker → Settings → Variables and Secrets → add secret `ADMIN_TOKEN`
   (any long random text). `STATS_TOKEN` is used if `ADMIN_TOKEN` is missing.
4. Paste the new `cloudflare/worker.js` into the Worker and **Deploy**
   (the tables create themselves).
5. Open `/health`. It must show `"tokens":true`.

Then build the new APK. If the Worker is not set up, **Request token** shows a
"server error / not set up" message and nobody loses anything.

## Settings (`lib/config.dart`)

| Setting               | Meaning                                                      |
|-----------------------|--------------------------------------------------------------|
| `showRemoveAds`       | false hides the menu item and the overlay button             |
| `tokenRequestMessage` | pre-filled chat message (uses `whatsappUrl`, else `joinUrl`) |
| `plansEnabled`/`feedBase` | must be on / set (same as Premium)                       |

## Good to know

* Tokens are 12 characters from an alphabet without 0/O/1/I and are checked on
  the Worker, never inside the app, so the APK contains no tokens.
* Like Premium, it belongs to the phone's install ID: after a reinstall the
  person asks for a new token (or you grant days to the ID they send you).
* Tests: `node --no-warnings cloudflare/token.test.mjs` (Node 22+).
