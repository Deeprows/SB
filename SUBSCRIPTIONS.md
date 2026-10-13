> **Premium is temporarily hidden** (`AppConfig.showSubscriptions = false`). Set it to `true` to show the plans page, menu item and "go Premium" button again.

# Free & Premium (Paystack)

On start the app shows a plans page.

* **Free** - everything is open. The "We Need Your Support" page appears after
  every 15 minutes of use (`AppConfig.adIntervalMinutes`).
* **Premium** - ₦2,000 / month through Paystack (shown on the card as "Secured by Paystack"). No pop-ups. After paying, Premium turns on by itself, an access code (the Paystack payment reference) is shown and can be used with *Restore purchase*, and Paystack e-mails the receipt. People
  outside Nigeria see the same price in their own currency (an estimate; the
  charge is always in naira).
* **Can't pay online** - the *Pay manually on WhatsApp* button opens a chat
  with the person's ID already in the message; you switch Premium on from the
  admin page (below).

Premium people skip the plans page and go straight into the app.

## How it works

```
app  ->  Worker /sub/start   ->  Paystack checkout (inside the app)
                                      |
Paystack -> Worker /sub/webhook (signed) and app -> /sub/verify
                                      |
                              D1: subs + payments  ->  app -> /sub/status
```

The Paystack secret key lives only in the Worker. A payment is counted once
per Paystack reference, and only when it is a successful NGN payment of at
least the price. One paid month = 31 days, one paid year = 366 days; paying again stacks on the time
that is left.

## One-time setup (phone browser is enough)

1. **Paystack** > Settings > API Keys & Webhooks
   * copy the **Secret key** (start with `sk_test_...` to try it, then switch
     to `sk_live_...`)
   * set **Webhook URL** to `https://deeprowss-feed.deeprows.workers.dev/sub/webhook`
2. *(optional, for monthly auto-renew)* Paystack > Products > **Plans** >
   Create plan: ₦2,000, monthly. Copy its plan code (`PLN_...`).
3. **Cloudflare** > Storage & databases > **D1** > Create database
   `deeprowss_subs`. Then your Worker > Settings > Bindings > Add > **D1
   database**, variable name exactly `DB`. (The tables create themselves.)
4. Worker > Settings > Variables and Secrets:
   * `PAYSTACK_SECRET_KEY` (secret) - from step 1
   * `PAYSTACK_PLAN_CODE` (optional) - from step 2; without it the auto-renew
     switch is hidden and each month is paid by hand
   * `ADMIN_TOKEN` (secret) - any long random text, for the admin page
   * `PRICE_NGN` (optional) - default 2000; change it here, no new APK needed
   * `PRICE_NGN_YEAR` (optional) - yearly price, default 20000 (two months free)
   * `PAYSTACK_PLAN_CODE_YEAR` (optional) - a yearly Paystack plan for card auto-renew
5. Paste the new `cloudflare/worker.js` into the Worker and **Deploy**.
6. Open `https://deeprowss-feed.deeprows.workers.dev/health`. It must show
   `"subscriptions":true`.
7. Pay once yourself with the test key (Paystack gives test cards), then
   switch to the live key.

## Manual (WhatsApp) payers

1. Put your link in `lib/config.dart`: `whatsappUrl = 'https://wa.me/<number>'`
   (country code, no `+`).
2. When someone pays you, their WhatsApp message contains `My ID: ...`.
3. Open `https://deeprowss-feed.deeprows.workers.dev/sub/admin?token=<ADMIN_TOKEN>`,
   paste the ID, enter the days (30) and press **Grant**. Enter **0** to switch
   someone off. The page also lists who is premium.
4. The phone picks it up the next time the app opens or when the person
   reopens the plans page.

## Settings in the app (`lib/config.dart`)

| Setting                 | Meaning                                                    |
|-------------------------|------------------------------------------------------------|
| `plansEnabled`          | false = no plans page and no ads for anyone                |
| `showPlansEveryStart`   | true: plans page on every launch for non-premium people    |
| `adIntervalMinutes`     | minutes of use between support pages (15)                  |
| `adRetryMinutes`        | if the support page can't load, ask again after this many  |
| `supportUrl`            | the ad / smart link (empty = no ads)                       |
| `whatsappUrl`           | manual-payment chat (empty = "coming soon" message)        |
| `supportOnCardTap`      | the old tap-a-card trigger; **off**                        |

## Good to know

* There is no login. Premium belongs to the phone's install ID, so after a
  reinstall or on a new phone use **Restore purchase** (e-mail + the payment
  reference from the Paystack receipt) or ask on WhatsApp.
* The ad clock counts only time the app is open on screen, and keeps counting
  across launches. It pauses on the plans / payment pages.
* Auto-renew works for cards only (Paystack limitation). Bank-transfer and
  USSD payers pay again each month. To stop an auto-renewing customer, use
  Paystack > Customers > Subscriptions.
* Exchange rates come from a free public API and are cached for 6 hours. If
  it is down, the naira price is shown alone.
* Tests: `node --no-warnings cloudflare/subscription.test.mjs` (Node 22+).
* If you ever publish on Google Play: Play requires Google Play Billing for
  digital subscriptions, so Paystack is fine for your own APK / GitHub
  downloads but not for a Play Store release.
