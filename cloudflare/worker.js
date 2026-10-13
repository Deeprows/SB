/**
 * Deeprowss feed proxy + anonymous usage monitor (Cloudflare Worker).
 *
 *   App -> https://feed.<your-domain>/feed/movies.json -> this Worker
 *                                                               |-> GitHub raw
 *                                                               '-> Analytics Engine
 *
 * Analytics:
 *   POST /analytics
 *   Records anonymous app_open events.
 *
 * Stats:
 *   /stats?token=<STATS_TOKEN>
 *
 * Settings:
 *   GITHUB_RAW_BASE  optional
 *   FEED_TTL         optional, default 10 (seconds; 0 = no edge cache)
 *   STATS_TOKEN      secret
 *   CF_ACCOUNT_ID    secret
 *   CF_API_TOKEN     secret
 *   ANALYTICS        Analytics Engine binding
 *
 * Premium subscriptions (Paystack + D1), see SUBSCRIPTIONS.md:
 *   GET  /sub/config   price, local-currency equivalent
 *   POST /sub/start    creates a Paystack checkout
 *   GET  /sub/verify   confirms a payment after checkout
 *   GET  /sub/status   is this install premium?
 *   POST /sub/webhook  Paystack events (signature checked)
 *   POST /sub/restore  move a paid subscription to a new phone
 *   /sub/admin         grant / revoke manually (WhatsApp payers), make and
 *                      hand out ad-free tokens, see token requests
 *   POST /sub/token/request  a phone asks for an ad-free token
 *   GET  /sub/token/mine     has my request been answered? (token ready?)
 *   POST /sub/token/redeem   a phone turns a token into ad-free time
 *   (the three token routes only need the DB binding, not Paystack)
 *   Settings: PAYSTACK_SECRET_KEY (secret), PAYSTACK_PLAN_CODE (optional),
 *             ADMIN_TOKEN (secret, falls back to STATS_TOKEN),
 *             PRICE_NGN (optional, default 2000), PRICE_NGN_YEAR (optional,
 *             default 20000), PAYSTACK_PLAN_CODE_YEAR (optional),
 *             DB (D1 binding)
 *
 * Analytics: only an anonymous random install id, app version, platform and
 * country are recorded. Subscriptions store the install id and the e-mail
 * the person typed at checkout.
 */

const FILES = {
  "fixtures.json": "fixtures.json",
  "highlights.json": "highlights.json",
  "movies.json": "movies.json",
  "tv.json": "tv.json",
  "ticker.json": "ticker.json",
};

const DEFAULT_RAW_BASE =
  "https://raw.githubusercontent.com/Deeprows/myflutter-app/main/assets/data";

const DATASET = "deeprowss_app";

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET,HEAD,POST,OPTIONS",
  "access-control-allow-headers":
    "content-type, x-install-id, x-app-version, x-platform",
};

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: CORS,
      });
    }

    if (
      request.method !== "GET" &&
      request.method !== "HEAD" &&
      request.method !== "POST"
    ) {
      return json({ error: "method not allowed" }, 405);
    }

    // Health check.
    if (url.pathname === "/" || url.pathname === "/health") {
      return json({
        ok: true,
        service: "deeprowss-feed",
        // Setup check (no secret values): both should be true.
        analytics: Boolean(env.ANALYTICS),
        stats: Boolean(
          env.STATS_TOKEN && env.CF_ACCOUNT_ID && env.CF_API_TOKEN
        ),
        subscriptions: Boolean(env.DB && env.PAYSTACK_SECRET_KEY),
        // Ad-free tokens only need the D1 binding + an admin password.
        tokens: Boolean(env.DB && (env.ADMIN_TOKEN || env.STATS_TOKEN)),
      });
    }

    // Anonymous app-open analytics.
    if (
      url.pathname === "/analytics" &&
      request.method === "POST"
    ) {
      return analytics(request, env);
    }

    // Protected statistics page.
    if (
      url.pathname === "/stats" &&
      request.method === "GET"
    ) {
      return stats(url, env);
    }

    // Premium subscriptions.
    if (url.pathname.startsWith("/sub/")) {
      return subscriptions(request, env, url);
    }

    // Feed routes.
    const m = /^\/feed\/([a-z0-9_-]+\.json)$/i.exec(url.pathname);

    if (m && FILES[m[1].toLowerCase()]) {
      return feed(
        request,
        env,
        ctx,
        m[1].toLowerCase()
      );
    }

    return json({
      error: "not found",
    }, 404);
  },
};

// ------------------------------------------------------------------ analytics

async function analytics(request, env) {
  try {
    if (!env.ANALYTICS) {
      return json({
        ok: false,
        error: "analytics not configured",
      }, 503);
    }

    const body = await request.json().catch(() => ({}));

    // Currently we only accept app_open.
    const event = String(
      body.event || ""
    ).slice(0, 32);

    if (event !== "app_open") {
      return json({
        ok: false,
        error: "unsupported event",
      }, 400);
    }

    const installId = String(
      body.installId || ""
    ).slice(0, 64);

    const appVersion = String(
      body.appVersion || "unknown"
    ).slice(0, 32);

    const platform = String(
      body.platform || "unknown"
    ).slice(0, 16);

    if (!installId) {
      return json({
        ok: false,
        error: "installId required",
      }, 400);
    }

    // The index is what Analytics Engine samples on. A constant index would
    // put every event in one bucket and undercount phones as traffic grows,
    // so use the (high-cardinality) install id.
    env.ANALYTICS.writeDataPoint({
      indexes: [installId],

      blobs: [
        "app_open",
        appVersion,
        platform,
        installId,
        request.cf?.country || "??",
        "app",
      ],

      doubles: [
        1,
        200,
      ],
    });

    return json({
      ok: true,
    });

  } catch (_) {
    // Analytics must never prevent the app from opening.
    return json({
      ok: false,
    }, 400);
  }
}

// ------------------------------------------------------------------ feed

async function feed(request, env, ctx, file) {
  // Short edge cache (default 10 s) so a new post shows up almost at once.
  // FEED_TTL=0 is allowed and turns the edge cache off completely.
  // The live-screen feeds (fixtures, ticker) are never edge-cached: every
  // open/refresh must see the file as it is right now.
  const noCache = file === "fixtures.json" || file === "ticker.json";
  const defaultTtl = noCache ? "0" : "10";
  const parsedTtl = parseInt(env.FEED_TTL ?? defaultTtl, 10);
  const ttl = noCache
    ? 0
    : clamp(
        Number.isNaN(parsedTtl) ? 10 : parsedTtl,
        0,
        600
      );

  const base = (
    env.GITHUB_RAW_BASE ||
    DEFAULT_RAW_BASE
  ).replace(/\/+$/, "");

  // raw.githubusercontent.com keeps every URL cached for ~5 minutes, which
  // is why new posts used to appear late. A unique query string makes GitHub
  // treat each Worker fetch as a new request, so it always returns the file
  // as it is right now.
  const origin = `${base}/${FILES[file]}?cb=${Date.now()}`;

  // Ignore query parameters for edge-cache purposes.
  const cacheKey = new Request(
    `https://feed-cache.invalid/${file}`
  );

  const cache = caches.default;

  let status = 200;
  let cacheState = "HIT";

  let response =
    ttl > 0
      ? await cache.match(cacheKey)
      : undefined;

  if (!response) {
    cacheState = "MISS";

    try {
      const upstream = await fetch(
        origin,
        {
          headers: {
            "user-agent":
              "deeprowss-feed-worker",
            accept:
              "application/json",
            "cache-control":
              "no-cache, no-store, max-age=0",
            pragma: "no-cache",
          },

          cf: {
            cacheTtl: 0,
            cacheEverything: false,
          },
        }
      );

      if (!upstream.ok) {
        status = 502;

        response = json({
          error:
            "origin returned " +
            upstream.status,
        }, 502);

      } else {
        const body =
          await upstream.text();

        response = new Response(
          body,
          {
            status: 200,

            headers: {
              "content-type":
                "application/json; charset=utf-8",

              "cache-control":
                ttl > 0 ? `public, max-age=${ttl}` : "no-store",
            },
          }
        );

        if (ttl > 0) {
          ctx.waitUntil(
            cache.put(
              cacheKey,
              response.clone()
            )
          );
        }
      }

    } catch (_) {
      status = 502;

      response = json({
        error: "origin unreachable",
      }, 502);
    }
  }

  // Existing feed analytics.
  record(
    env,
    request,
    file,
    status,
    cacheState
  );

  const out = new Response(
    response.body,
    response
  );

  for (
    const [k, v]
    of Object.entries(CORS)
  ) {
    out.headers.set(k, v);
  }

  out.headers.set(
    "cache-control",
    "no-cache"
  );

  out.headers.set(
    "x-feed-cache",
    cacheState
  );

  return out;
}

// ------------------------------------------------------------------ feed analytics

function record(
  env,
  request,
  file,
  status,
  cacheState
) {
  try {
    if (!env.ANALYTICS) {
      return;
    }

    const h = request.headers;

    const installId = (h.get("x-install-id") || "").slice(0, 64);

    env.ANALYTICS.writeDataPoint({
      indexes: [installId || file],

      blobs: [
        file,
        (
          h.get("x-app-version") ||
          "unknown"
        ).slice(0, 32),

        (
          h.get("x-platform") ||
          "unknown"
        ).slice(0, 16),

        (
          h.get("x-install-id") ||
          "unknown"
        ).slice(0, 64),

        request.cf?.country || "??",

        cacheState,
      ],

      doubles: [
        1,
        status,
      ],
    });

  } catch (_) {
    // Analytics must never break the feed.
  }
}

// ----------------------------------------------------------------- stats

async function stats(url, env) {
  if (
    !env.STATS_TOKEN ||
    url.searchParams.get("token") !==
      env.STATS_TOKEN
  ) {
    return new Response(
      "Not found",
      { status: 404 }
    );
  }

  if (
    !env.CF_ACCOUNT_ID ||
    !env.CF_API_TOKEN
  ) {
    return html(
      page(
        "Stats not configured",
        "<p>Add the secrets <b>CF_ACCOUNT_ID</b> and <b>CF_API_TOKEN</b> (token with <i>Account Analytics: Read</i>) to this Worker.</p>"
      )
    );
  }

  const t = DATASET;

  const q = {

    // Actual app opens.
    today:
      `SELECT COUNT(DISTINCT blob4) AS phones, ` +
      `SUM(_sample_interval) AS app_opens ` +
      `FROM ${t} ` +
      `WHERE blob1 = 'app_open' ` +
      `AND timestamp > NOW() - INTERVAL '1' DAY`,

    // Daily app usage.
    days:
      `SELECT ` +
      `toStartOfInterval(timestamp, INTERVAL '1' DAY) AS day, ` +
      `COUNT(DISTINCT blob4) AS phones, ` +
      `SUM(_sample_interval) AS app_opens ` +
      `FROM ${t} ` +
      `WHERE blob1 = 'app_open' ` +
      `AND timestamp > NOW() - INTERVAL '7' DAY ` +
      `GROUP BY day ` +
      `ORDER BY day DESC`,

    // Countries using the app.
    countries:
      `SELECT ` +
      `blob5 AS country, ` +
      `COUNT(DISTINCT blob4) AS phones, ` +
      `SUM(_sample_interval) AS app_opens ` +
      `FROM ${t} ` +
      `WHERE blob1 = 'app_open' ` +
      `AND timestamp > NOW() - INTERVAL '7' DAY ` +
      `GROUP BY country ` +
      `ORDER BY phones DESC ` +
      `LIMIT 15`,

    // App versions.
    versions:
      `SELECT ` +
      `blob2 AS version, ` +
      `COUNT(DISTINCT blob4) AS phones ` +
      `FROM ${t} ` +
      `WHERE blob1 = 'app_open' ` +
      `AND timestamp > NOW() - INTERVAL '7' DAY ` +
      `GROUP BY version ` +
      `ORDER BY phones DESC ` +
      `LIMIT 10`,

    // Existing feed traffic.
    files:
      `SELECT ` +
      `blob1 AS file, ` +
      `SUM(_sample_interval) AS requests ` +
      `FROM ${t} ` +
      `WHERE blob1 IN (` +
      `'fixtures.json',` +
      `'highlights.json',` +
      `'movies.json',` +
      `'tv.json',` +
      `'ticker.json'` +
      `) ` +
      `AND timestamp > NOW() - INTERVAL '1' DAY ` +
      `GROUP BY file ` +
      `ORDER BY requests DESC`,
  };

  try {
    const res = {};

    for (
      const [k, sql]
      of Object.entries(q)
    ) {
      res[k] =
        await runSql(
          env,
          sql
        );
    }

    const today =
      res.today[0] || {};

    const body = `

      <div class="grid">

        <div class="big">
          <span>
            ${num(today.phones)}
          </span>
          unique phones (24 h)
        </div>

        <div class="big">
          <span>
            ${num(today.app_opens)}
          </span>
          app opens (24 h)
        </div>

      </div>

      ${table(
        "Last 7 days",
        [
          "day",
          "phones",
          "app opens"
        ],
        res.days.map(
          (r) => [
            String(r.day)
              .slice(0, 10),

            num(r.phones),

            num(r.app_opens),
          ]
        )
      )}

      ${table(
        "Countries (7 days)",
        [
          "country",
          "phones",
          "app opens"
        ],
        res.countries.map(
          (r) => [
            r.country,
            num(r.phones),
            num(r.app_opens),
          ]
        )
      )}

      ${table(
        "App versions (7 days)",
        [
          "version",
          "phones"
        ],
        res.versions.map(
          (r) => [
            r.version,
            num(r.phones),
          ]
        )
      )}

      ${table(
        "Feed files (24 h)",
        [
          "file",
          "requests"
        ],
        res.files.map(
          (r) => [
            r.file,
            num(r.requests),
          ]
        )
      )}

      <p class="muted">
        "Phones" = distinct anonymous
        install ids. App opens are recorded
        separately from feed requests.
        Data appears a minute or two after use.
      </p>
    `;

    return html(
      page(
        "Deeprowss usage",
        body
      )
    );

  } catch (e) {

    return html(
      page(
        "Stats error",
        `<p>${esc(
          String(
            e.message || e
          )
        )}</p>`
      ),
      500
    );
  }
}

// ------------------------------------------------------------------ SQL

async function runSql(
  env,
  sql
) {
  const r = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${env.CF_ACCOUNT_ID}/analytics_engine/sql`,
    {
      method: "POST",

      headers: {
        authorization:
          `Bearer ${env.CF_API_TOKEN}`,
      },

      body:
        sql +
        " FORMAT JSON",
    }
  );

  const text =
    await r.text();

  if (!r.ok) {
    throw new Error(
      `Analytics query failed (${r.status}): ${text.slice(0, 300)}`
    );
  }

  return (
    JSON.parse(text).data ||
    []
  );
}

// --------------------------------------------------------------- helpers

const clamp = (
  n,
  lo,
  hi
) =>
  Math.min(
    hi,
    Math.max(lo, n)
  );

const num = (v) =>
  Number(v || 0)
    .toLocaleString("en-US");

const esc = (s) =>
  String(s).replace(
    /[&<>"']/g,
    (c) =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#39;",
      }[c])
  );

function json(
  obj,
  status = 200
) {
  return new Response(
    JSON.stringify(obj),
    {
      status,

      headers: {
        "content-type":
          "application/json; charset=utf-8",

        ...CORS,
      },
    }
  );
}

function html(
  body,
  status = 200
) {
  return new Response(
    body,
    {
      status,

      headers: {
        "content-type":
          "text/html; charset=utf-8",

        "cache-control":
          "no-store",

        "x-robots-tag":
          "noindex",
      },
    }
  );
}

function table(
  title,
  head,
  rows
) {
  if (!rows.length) {
    return `
      <h2>${esc(title)}</h2>
      <p class="muted">
        No data yet.
      </p>
    `;
  }

  return `
    <h2>${esc(title)}</h2>

    <table>
      <tr>
        ${head
          .map(
            (h) =>
              `<th>${esc(h)}</th>`
          )
          .join("")}
      </tr>

      ${
        rows
          .map(
            (r) =>
              `<tr>${
                r
                  .map(
                    (c) =>
                      `<td>${esc(c)}</td>`
                  )
                  .join("")
              }</tr>`
          )
          .join("")
      }

    </table>
  `;
}

function page(
  title,
  body
) {
  return `<!doctype html>
<html>
<head>

<meta charset="utf-8">

<meta
  name="viewport"
  content="width=device-width,initial-scale=1"
>

<title>
  ${esc(title)}
</title>

<style>

body{
  margin:0;
  padding:18px;
  background:#0b0f17;
  color:#e8ecf3;
  font:15px/1.45 system-ui,sans-serif
}

h1{
  font-size:20px;
  margin:0 0 14px
}

h2{
  font-size:15px;
  margin:22px 0 8px;
  color:#9fb0c8
}

.grid{
  display:flex;
  gap:10px
}

.big{
  flex:1;
  background:#131a26;
  border:1px solid #243047;
  border-radius:14px;
  padding:14px;
  color:#9fb0c8;
  font-size:12.5px
}

.big span{
  display:block;
  font-size:28px;
  font-weight:800;
  color:#fff
}

table{
  width:100%;
  border-collapse:collapse;
  background:#131a26;
  border-radius:12px;
  overflow:hidden
}

th,td{
  padding:8px 10px;
  text-align:left;
  border-bottom:1px solid #1d2739
}

th{
  color:#9fb0c8;
  font-weight:600;
  font-size:12.5px
}

.muted{
  color:#7d8ca3;
  font-size:12.5px
}

</style>

</head>

<body>

<h1>
  ${esc(title)}
</h1>

${body}

</body>
</html>`;
}

// -------------------------------------------------------------- subscriptions
//
// Premium = no "Support" pop-ups. The app only ever asks THIS Worker whether
// an install is premium; the Paystack secret key never leaves the Worker.
//
//   charge.success (webhook) or /sub/verify  ->  payments (one row per
//   Paystack reference, so a payment can never be counted twice)  ->  subs
//   (one row per install id with the expiry time).

const DAY_MS = 86400000;
const PERIOD_DAYS = 31; // one paid month, with a day of slack for renewals
const YEAR_DAYS = 366; // one paid year, with a day of slack
const ID_RE = /^[a-z0-9]{16,64}$/i;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

let schemaReady = false;

const priceNgn = (env) =>
  Math.max(1, parseInt(env.PRICE_NGN ?? "2000", 10) || 2000);

// Yearly price (default 20,000 = two months free). Change PRICE_NGN_YEAR.
const priceYearNgn = (env) =>
  Math.max(1, parseInt(env.PRICE_NGN_YEAR ?? "20000", 10) || 20000);

/** "year" or "month". Renewals carry no metadata, so fall back to the amount. */
function periodOf(env, tx) {
  const p = String(tx?.metadata?.period || "");
  if (p === "year" || p === "month") return p;
  return Number(tx?.amount) >= priceYearNgn(env) * 100 ? "year" : "month";
}

async function ensureSchema(env) {
  if (schemaReady) return;
  await env.DB.batch([
    env.DB.prepare(
      "CREATE TABLE IF NOT EXISTS subs (install_id TEXT PRIMARY KEY, email TEXT, expires_at INTEGER NOT NULL DEFAULT 0, source TEXT, updated_at INTEGER NOT NULL DEFAULT 0)"
    ),
    env.DB.prepare(
      "CREATE INDEX IF NOT EXISTS subs_email ON subs (email)"
    ),
    env.DB.prepare(
      "CREATE TABLE IF NOT EXISTS payments (reference TEXT PRIMARY KEY, install_id TEXT, email TEXT, amount INTEGER, created_at INTEGER NOT NULL DEFAULT 0)"
    ),
    env.DB.prepare(
      "CREATE TABLE IF NOT EXISTS tokens (token TEXT PRIMARY KEY, days INTEGER NOT NULL, bound_to TEXT, note TEXT, created_at INTEGER NOT NULL DEFAULT 0, redeemed_by TEXT, redeemed_at INTEGER)"
    ),
    env.DB.prepare(
      "CREATE TABLE IF NOT EXISTS token_requests (install_id TEXT PRIMARY KEY, contact TEXT, created_at INTEGER NOT NULL DEFAULT 0)"
    ),
  ]);
  schemaReady = true;
}

async function subscriptions(request, env, url) {
  const path = url.pathname;

  // The "payment finished" page Paystack sends the person back to. The app's
  // checkout window notices this address and closes itself.
  if (path === "/sub/done") {
    return new Response(
      `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><body style="font-family:sans-serif;background:#080b10;color:#fff;text-align:center;padding:48px 20px"><h2>Payment received</h2><p>You can go back to the Deeprowss app.</p>`,
      { headers: { "content-type": "text/html; charset=utf-8" } }
    );
  }

  if (path === "/sub/config" && request.method === "GET") {
    return subConfig(url, env);
  }

  // Status, the admin page and the token routes only need the database;
  // everything else also needs the Paystack key.
  const dbOnly =
    path === "/sub/status" ||
    path === "/sub/admin" ||
    path.startsWith("/sub/token/");
  if (!env.DB || (!env.PAYSTACK_SECRET_KEY && !dbOnly)) {
    return json({ error: "subscriptions are not set up on the server" }, 503);
  }

  try {
    await ensureSchema(env);

    if (path === "/sub/status" && request.method === "GET") {
      return subStatus(url, env);
    }
    if (path === "/sub/start" && request.method === "POST") {
      return subStart(request, env, url);
    }
    if (path === "/sub/verify" && request.method === "GET") {
      return subVerify(url, env);
    }
    if (path === "/sub/webhook" && request.method === "POST") {
      return subWebhook(request, env);
    }
    if (path === "/sub/restore" && request.method === "POST") {
      return subRestore(request, env);
    }
    if (path === "/sub/token/request" && request.method === "POST") {
      return tokenRequest(request, env);
    }
    if (path === "/sub/token/mine" && request.method === "GET") {
      return tokenMine(url, env);
    }
    if (path === "/sub/token/redeem" && request.method === "POST") {
      return tokenRedeem(request, env);
    }
    if (path === "/sub/admin") {
      return subAdmin(request, env, url);
    }
  } catch (e) {
    console.error("subscription error", e && e.message);
    return json({ error: "server error" }, 500);
  }

  return json({ error: "not found" }, 404);
}

// ---- price + local currency ------------------------------------------------

async function ngnRates() {
  const key = new Request("https://rates.internal/ngn");
  let res = await caches.default.match(key);
  if (!res) {
    const r = await fetch("https://open.er-api.com/v6/latest/NGN");
    if (!r.ok) return null;
    const body = await r.json();
    if (!body || !body.rates) return null;
    res = new Response(JSON.stringify(body.rates), {
      headers: { "cache-control": "public, max-age=21600" },
    });
    await caches.default.put(key, res.clone());
  }
  return res.json();
}

function money(amount, currency) {
  try {
    return new Intl.NumberFormat("en", {
      style: "currency",
      currency,
      currencyDisplay: "narrowSymbol",
    }).format(amount);
  } catch {
    return `${currency} ${amount.toFixed(2)}`;
  }
}

async function subConfig(url, env) {
  const price = priceNgn(env);
  const yearPrice = priceYearNgn(env);
  const out = {
    price_ngn: price,
    price_display: money(price, "NGN").replace(/\.00$/, ""),
    year_price_ngn: yearPrice,
    year_price_display: money(yearPrice, "NGN").replace(/\.00$/, ""),
    recurring: Boolean(env.PAYSTACK_PLAN_CODE),
    recurring_year: Boolean(env.PAYSTACK_PLAN_CODE_YEAR),
    available: Boolean(env.DB && env.PAYSTACK_SECRET_KEY),
    currency: "NGN",
    local_display: null,
    year_local_display: null,
  };

  const cur = (url.searchParams.get("cur") || "").toUpperCase();
  if (/^[A-Z]{3}$/.test(cur) && cur !== "NGN") {
    try {
      const rates = await ngnRates();
      const rate = rates && Number(rates[cur]);
      if (rate > 0) {
        // Round up to a whole cent so the shown amount never looks cheaper
        // than what the bank will really take.
        const local = Math.ceil(price * rate * 100) / 100;
        const localYear = Math.ceil(yearPrice * rate * 100) / 100;
        out.currency = cur;
        out.local_amount = local;
        out.local_display = money(local, cur);
        out.year_local_display = money(localYear, cur);
      }
    } catch {
      // No rates: the app simply shows the naira price.
    }
  }
  return json(out);
}

// ---- Paystack --------------------------------------------------------------

async function paystack(env, path, init = {}) {
  const r = await fetch(`https://api.paystack.co${path}`, {
    ...init,
    headers: {
      authorization: `Bearer ${env.PAYSTACK_SECRET_KEY}`,
      "content-type": "application/json",
    },
  });
  let body = null;
  try {
    body = await r.json();
  } catch {}
  return { ok: r.ok && body && body.status === true, body };
}

async function hmacHex(secret, text) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(text)
  );
  return [...new Uint8Array(sig)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// ---- entitlement -----------------------------------------------------------

async function expiryOf(env, installId) {
  const row = await env.DB.prepare(
    "SELECT expires_at FROM subs WHERE install_id = ?"
  )
    .bind(installId)
    .first();
  return row ? Number(row.expires_at) || 0 : 0;
}

/** Adds [days] on top of whatever time is left (never loses paid time). */
async function addDays(env, installId, { email, source, days }) {
  const now = Date.now();
  const left = await expiryOf(env, installId);
  const expires = Math.max(now, left) + days * DAY_MS;
  await env.DB.prepare(
    "INSERT INTO subs (install_id, email, expires_at, source, updated_at) VALUES (?, ?, ?, ?, ?) " +
      "ON CONFLICT(install_id) DO UPDATE SET expires_at = excluded.expires_at, " +
      "email = COALESCE(excluded.email, subs.email), source = excluded.source, updated_at = excluded.updated_at"
  )
    .bind(installId, email || null, expires, source, now)
    .run();
  return expires;
}

/** Turns a successful Paystack transaction into premium time, once. */
async function settle(env, tx) {
  if (!tx || tx.status !== "success") return null;
  const period = periodOf(env, tx);
  const need = (period === "year" ? priceYearNgn(env) : priceNgn(env)) * 100;
  if (tx.currency !== "NGN" || Number(tx.amount) < need) {
    return null;
  }
  const reference = String(tx.reference || "");
  if (!reference) return null;

  const email = String(tx.customer?.email || "").toLowerCase() || null;
  let installId = tx.metadata?.install_id;
  if (!ID_RE.test(String(installId || ""))) {
    // An automatic renewal: Paystack does not repeat our metadata, so find
    // the install by the customer's e-mail.
    const row = email
      ? await env.DB.prepare(
          "SELECT install_id FROM subs WHERE email = ? ORDER BY updated_at DESC LIMIT 1"
        )
          .bind(email)
          .first()
      : null;
    installId = row?.install_id;
  }
  if (!installId) return null;

  const ins = await env.DB.prepare(
    "INSERT OR IGNORE INTO payments (reference, install_id, email, amount, created_at) VALUES (?, ?, ?, ?, ?)"
  )
    .bind(reference, installId, email, Number(tx.amount), Date.now())
    .run();

  if (ins.meta && ins.meta.changes === 0) {
    // Already counted (webhook and verify both arrive for one payment).
    return { installId, expires: await expiryOf(env, installId) };
  }
  const expires = await addDays(env, installId, {
    email,
    source: "paystack",
    days: period === "year" ? YEAR_DAYS : PERIOD_DAYS,
  });
  return { installId, expires };
}

// ---- routes ----------------------------------------------------------------

async function subStatus(url, env) {
  const id = url.searchParams.get("install") || "";
  if (!ID_RE.test(id)) return json({ error: "bad install id" }, 400);
  const expires = await expiryOf(env, id);
  return json({ active: expires > Date.now(), expires_at: expires });
}

async function subStart(request, env, url) {
  let b;
  try {
    b = await request.json();
  } catch {
    return json({ error: "bad request" }, 400);
  }
  const installId = String(b.install_id || "");
  const email = String(b.email || "").trim().toLowerCase();
  if (!ID_RE.test(installId)) return json({ error: "bad install id" }, 400);
  if (!EMAIL_RE.test(email)) {
    return json({ error: "Enter a valid e-mail address" }, 400);
  }

  const period = b.period === "year" ? "year" : "month";
  const allChannels = ["card", "ussd", "bank_transfer", "bank", "mobile_money"];
  const channels = Array.isArray(b.channels)
    ? b.channels.filter((c) => allChannels.includes(c))
    : [];

  const reference =
    "DR" +
    Date.now().toString(36) +
    crypto.randomUUID().replace(/-/g, "").slice(0, 10);
  const body = {
    email,
    amount: (period === "year" ? priceYearNgn(env) : priceNgn(env)) * 100, // kobo
    currency: "NGN",
    reference,
    callback_url: `${url.origin}/sub/done`,
    metadata: { install_id: installId, app: "deeprowss", period },
  };
  // Open Paystack straight on the method the person picked (card / USSD / ...).
  if (channels.length) body.channels = channels;
  // A plan makes the card renew by itself every month (card payments only).
  const planCode =
    period === "year" ? env.PAYSTACK_PLAN_CODE_YEAR : env.PAYSTACK_PLAN_CODE;
  if (b.recurring && planCode) body.plan = planCode;

  const r = await paystack(env, "/transaction/initialize", {
    method: "POST",
    body: JSON.stringify(body),
  });
  if (!r.ok || !r.body.data?.authorization_url) {
    return json(
      { error: r.body?.message || "Could not start the payment" },
      502
    );
  }

  // Remember the e-mail now so a renewal can find this install later.
  await env.DB.prepare(
    "INSERT INTO subs (install_id, email, expires_at, source, updated_at) VALUES (?, ?, 0, 'pending', ?) " +
      "ON CONFLICT(install_id) DO UPDATE SET email = excluded.email"
  )
    .bind(installId, email, Date.now())
    .run();

  return json({
    authorization_url: r.body.data.authorization_url,
    reference,
  });
}

async function subVerify(url, env) {
  const reference = url.searchParams.get("reference") || "";
  if (!/^[A-Za-z0-9._-]{6,80}$/.test(reference)) {
    return json({ error: "bad reference" }, 400);
  }
  const r = await paystack(
    env,
    `/transaction/verify/${encodeURIComponent(reference)}`
  );
  if (!r.ok) return json({ status: "failed" });
  const tx = r.body.data;
  if (tx.status !== "success") {
    const pending = ["pending", "ongoing", "processing", "queued"].includes(
      tx.status
    );
    return json({ status: pending ? "pending" : "failed" });
  }
  const done = await settle(env, tx);
  if (!done) return json({ status: "failed" });
  return json({
    status: "success",
    active: done.expires > Date.now(),
    expires_at: done.expires,
    install_id: done.installId,
  });
}

async function subWebhook(request, env) {
  const raw = await request.text();
  const sig = request.headers.get("x-paystack-signature") || "";
  if (!sig || sig !== (await hmacHex(env.PAYSTACK_SECRET_KEY, raw))) {
    return json({ error: "bad signature" }, 401);
  }
  let ev;
  try {
    ev = JSON.parse(raw);
  } catch {
    return json({ ok: true });
  }
  if (ev.event === "charge.success") await settle(env, ev.data);
  return json({ ok: true });
}

/** New phone: prove the payment with its e-mail + Paystack reference. */
async function subRestore(request, env) {
  let b;
  try {
    b = await request.json();
  } catch {
    return json({ error: "bad request" }, 400);
  }
  const installId = String(b.install_id || "");
  const email = String(b.email || "").trim().toLowerCase();
  const reference = String(b.reference || "").trim();
  if (!ID_RE.test(installId) || !EMAIL_RE.test(email) || !reference) {
    return json({ error: "Enter your e-mail and payment reference" }, 400);
  }
  const r = await paystack(
    env,
    `/transaction/verify/${encodeURIComponent(reference)}`
  );
  const tx = r.ok ? r.body.data : null;
  if (
    !tx ||
    tx.status !== "success" ||
    String(tx.customer?.email || "").toLowerCase() !== email
  ) {
    return json({ error: "No payment found for that e-mail and reference" }, 404);
  }
  const row = await env.DB.prepare(
    "SELECT MAX(expires_at) AS e FROM subs WHERE email = ?"
  )
    .bind(email)
    .first();
  const expires = Number(row?.e) || 0;
  if (expires <= Date.now()) {
    return json({ error: "That subscription has expired" }, 404);
  }
  await env.DB.prepare(
    "INSERT INTO subs (install_id, email, expires_at, source, updated_at) VALUES (?, ?, ?, 'restored', ?) " +
      "ON CONFLICT(install_id) DO UPDATE SET expires_at = MAX(subs.expires_at, excluded.expires_at), email = excluded.email, source = 'restored', updated_at = excluded.updated_at"
  )
    .bind(installId, email, expires, Date.now())
    .run();
  return json({ ok: true, active: true, expires_at: expires });
}

// ---- ad-free tokens ---------------------------------------------------------
//
// A phone asks for a token (/sub/token/request). You see the request on the
// admin page and press "Create token" (or make tokens in advance). The phone
// finds the token by itself (/sub/token/mine) or the person types it in; either
// way /sub/token/redeem turns it into ad-free days on that phone's install id.
// A token works once. A token made from a request only works on that phone.

const TOKEN_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0 O 1 I
const TOKEN_LEN = 12;
const MAX_TOKEN_DAYS = 3650;

function makeToken() {
  const bytes = new Uint8Array(TOKEN_LEN);
  crypto.getRandomValues(bytes);
  // 32 symbols and 256 byte values: "& 31" has no bias.
  return Array.from(bytes, (b) => TOKEN_ALPHABET[b & 31]).join("");
}

/** "abcd-efgh ijkl" -> "ABCDEFGHIJKL" */
const normToken = (t) =>
  String(t || "")
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "");

/** "ABCDEFGHJKLM" -> "ABCD-EFGH-JKLM" */
const showToken = (t) => String(t).replace(/(.{4})(?=.)/g, "$1-");

async function mintTokens(env, { days, count = 1, boundTo = null, note = "" }) {
  const out = [];
  for (let i = 0; i < count; i++) {
    const token = makeToken();
    await env.DB.prepare(
      "INSERT INTO tokens (token, days, bound_to, note, created_at) VALUES (?, ?, ?, ?, ?)"
    )
      .bind(token, days, boundTo, note || null, Date.now())
      .run();
    out.push(token);
  }
  return out;
}

async function tokenRequest(request, env) {
  let b;
  try {
    b = await request.json();
  } catch {
    return json({ error: "bad request" }, 400);
  }
  const installId = String(b.install_id || "");
  if (!ID_RE.test(installId)) return json({ error: "bad install id" }, 400);
  const contact = String(b.contact || "").trim().slice(0, 80);

  if ((await expiryOf(env, installId)) > Date.now()) {
    return json({ ok: true, state: "active" });
  }
  await env.DB.prepare(
    "INSERT INTO token_requests (install_id, contact, created_at) VALUES (?, ?, ?) " +
      "ON CONFLICT(install_id) DO UPDATE SET contact = COALESCE(NULLIF(excluded.contact, ''), token_requests.contact), created_at = excluded.created_at"
  )
    .bind(installId, contact, Date.now())
    .run();
  return json({ ok: true, state: "pending" });
}

/** Has the request been answered? Returns the token made for this phone. */
async function tokenMine(url, env) {
  const id = url.searchParams.get("install") || "";
  if (!ID_RE.test(id)) return json({ error: "bad install id" }, 400);
  const expires = await expiryOf(env, id);
  if (expires > Date.now()) {
    return json({ state: "active", expires_at: expires });
  }
  const t = await env.DB.prepare(
    "SELECT token, days FROM tokens WHERE bound_to = ? AND redeemed_by IS NULL ORDER BY created_at DESC LIMIT 1"
  )
    .bind(id)
    .first();
  if (t) return json({ state: "ready", token: showToken(t.token), days: t.days });
  const r = await env.DB.prepare(
    "SELECT 1 AS x FROM token_requests WHERE install_id = ?"
  )
    .bind(id)
    .first();
  return json({ state: r ? "pending" : "none" });
}

async function tokenRedeem(request, env) {
  let b;
  try {
    b = await request.json();
  } catch {
    return json({ error: "bad request" }, 400);
  }
  const installId = String(b.install_id || "");
  const token = normToken(b.token);
  if (!ID_RE.test(installId)) return json({ error: "bad install id" }, 400);
  if (token.length !== TOKEN_LEN) {
    return json({ error: "Enter the token exactly as you received it" }, 400);
  }

  const row = await env.DB.prepare(
    "SELECT token, days, bound_to, redeemed_by FROM tokens WHERE token = ?"
  )
    .bind(token)
    .first();
  if (!row) return json({ error: "That token is not valid" }, 404);

  if (row.redeemed_by) {
    if (row.redeemed_by === installId) {
      // Same phone pressing the button twice: just report the time it has.
      const e = await expiryOf(env, installId);
      return json({ ok: true, active: e > Date.now(), expires_at: e });
    }
    return json({ error: "That token has already been used" }, 409);
  }
  if (row.bound_to && row.bound_to !== installId) {
    return json({ error: "That token was made for another phone" }, 403);
  }

  // Claim it first (only one phone can win), then add the time.
  const claim = await env.DB.prepare(
    "UPDATE tokens SET redeemed_by = ?, redeemed_at = ? WHERE token = ? AND redeemed_by IS NULL"
  )
    .bind(installId, Date.now(), token)
    .run();
  if (Number(claim?.meta?.changes) !== 1) {
    return json({ error: "That token has already been used" }, 409);
  }
  const expires = await addDays(env, installId, {
    email: null,
    source: "token",
    days: Number(row.days),
  });
  await env.DB.prepare("DELETE FROM token_requests WHERE install_id = ?")
    .bind(installId)
    .run();
  return json({ ok: true, active: true, expires_at: expires });
}

/**
 * Phone-friendly admin page:
 *   /sub/admin?token=<ADMIN_TOKEN>
 *  - Token requests: phones that pressed "Request token". Choose the days and
 *    press "Create token"; the phone receives it by itself (or you send it).
 *  - Make tokens in advance (for people you chat with on WhatsApp/Telegram).
 *  - Grant days straight to an ID (0 days switches someone off).
 */
async function subAdmin(request, env, url) {
  const secret = env.ADMIN_TOKEN || env.STATS_TOKEN;
  const form = request.method === "POST" ? await request.formData() : null;
  const token = form ? form.get("token") : url.searchParams.get("token");
  if (!secret || token !== secret) return json({ error: "forbidden" }, 403);

  let note = "";
  let made = [];
  if (form) {
    const action = String(form.get("action") || "grant");
    const id = String(form.get("install_id") || "").trim();
    const days = parseInt(String(form.get("days") || ""), 10);
    const daysOk = days >= 0 && days <= MAX_TOKEN_DAYS;

    if (action === "mint") {
      const count = Math.min(
        20,
        Math.max(1, parseInt(String(form.get("count") || "1"), 10) || 1)
      );
      const label = String(form.get("note") || "").trim().slice(0, 60);
      if (!(days >= 1 && days <= MAX_TOKEN_DAYS)) {
        note = "Days must be 1-3650.";
      } else {
        made = await mintTokens(env, { days, count, note: label });
        note = `${made.length} token(s) made, ${days} day(s) each. Each works once, on any phone.`;
      }
    } else if (action === "answer") {
      if (!ID_RE.test(id) || !(days >= 1 && days <= MAX_TOKEN_DAYS)) {
        note = "Check the ID and the days (1-3650).";
      } else {
        const req = await env.DB.prepare(
          "SELECT contact FROM token_requests WHERE install_id = ?"
        )
          .bind(id)
          .first();
        made = await mintTokens(env, {
          days,
          boundTo: id,
          note: req?.contact || "",
        });
        // Answered: take it out of the waiting list. The phone now finds
        // the token through /sub/token/mine.
        await env.DB.prepare("DELETE FROM token_requests WHERE install_id = ?")
          .bind(id)
          .run();
        note = `Token made for ${id.slice(0, 12)}… (${days} days). The phone shows it by itself; you can also send it.`;
      }
    } else if (action === "dismiss") {
      await env.DB.prepare("DELETE FROM token_requests WHERE install_id = ?")
        .bind(id)
        .run();
      note = "Request removed.";
    } else if (!ID_RE.test(id) || !daysOk) {
      note = "Check the ID (letters/numbers only) and the days (0-3650).";
    } else if (days === 0) {
      await env.DB.prepare(
        "INSERT INTO subs (install_id, expires_at, source, updated_at) VALUES (?, 0, 'revoked', ?) " +
          "ON CONFLICT(install_id) DO UPDATE SET expires_at = 0, source = 'revoked', updated_at = excluded.updated_at"
      )
        .bind(id, Date.now())
        .run();
      note = `Premium switched off for ${id}`;
    } else {
      const e = await addDays(env, id, { email: null, source: "manual", days });
      note = `Premium until ${new Date(e).toISOString().slice(0, 10)} for ${id}`;
    }
  }

  const day = (ms) => new Date(Number(ms)).toISOString().slice(0, 10);
  const tk = esc(String(token));
  const btn = "padding:9px 12px;font-size:15px";
  const box = "width:100%;padding:12px;box-sizing:border-box";

  // Digits only go into the link, so nothing typed by a phone can break out.
  const waLink = (c) => {
    const d = String(c || "").replace(/\D/g, "");
    return d.length >= 7 && d.length <= 15
      ? ` &middot; <a href="https://wa.me/${d}" style="color:#22e07a">Open WhatsApp</a>`
      : "";
  };

  const reqs = (
    await env.DB.prepare(
      "SELECT install_id, contact, created_at FROM token_requests ORDER BY created_at DESC LIMIT 30"
    ).all()
  ).results || [];
  const reqHtml = reqs.length
    ? reqs
        .map(
          (r) => `<form method="post" style="background:#101722;padding:10px;border-radius:8px;margin:8px 0">
<input type="hidden" name="token" value="${tk}"><input type="hidden" name="install_id" value="${esc(r.install_id)}">
<div style="font-size:12.5px;margin-bottom:6px">${esc(String(r.install_id).slice(0, 12))}… &middot; ${esc(day(r.created_at))}${r.contact ? ` &middot; <b>${esc(r.contact)}</b>` : ""}${waLink(r.contact)}</div>
<input name="days" type="number" value="30" style="width:80px;padding:9px">
<button name="action" value="answer" style="${btn}">Create token</button>
<button name="action" value="dismiss" style="${btn}">Dismiss</button>
</form>`
        )
        .join("")
    : `<p style="color:#8d99ab;font-size:13px">No requests waiting.</p>`;

  const unused = (
    await env.DB.prepare(
      "SELECT token, days, bound_to, note FROM tokens WHERE redeemed_by IS NULL ORDER BY created_at DESC LIMIT 25"
    ).all()
  ).results || [];
  const unusedHtml = unused
    .map(
      (r) =>
        `<tr><td style="font-family:monospace">${esc(showToken(r.token))}</td><td>${esc(r.days)}d</td><td>${r.bound_to ? esc(String(r.bound_to).slice(0, 8)) + "…" : "any"}</td><td>${esc(r.note || "")}</td></tr>`
    )
    .join("");

  const rows = await env.DB.prepare(
    "SELECT install_id, email, expires_at, source FROM subs WHERE expires_at > 0 ORDER BY updated_at DESC LIMIT 25"
  ).all();
  const list = (rows.results || [])
    .map(
      (r) =>
        `<tr><td>${esc(String(r.install_id).slice(0, 12))}…</td><td>${esc(r.source)}</td><td>${esc(day(r.expires_at))}</td><td>${esc(r.email || "")}</td></tr>`
    )
    .join("");

  const madeHtml = made.length
    ? `<div style="background:#12301f;padding:10px;border-radius:8px;font-family:monospace;font-size:17px;line-height:1.7">${made
        .map((t) => esc(showToken(t)))
        .join("<br>")}</div>`
    : "";

  return html(
    `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>Ad-free admin</title>
<body style="font-family:sans-serif;background:#080b10;color:#e8edf5;padding:18px;max-width:560px;margin:auto">
<h2>Ad-free admin</h2>
${note ? `<p style="background:#16202e;padding:10px;border-radius:8px">${esc(note)}</p>` : ""}
${madeHtml}
<h3>Token requests</h3>
${reqHtml}
<h3>Make tokens</h3>
<form method="post">
<input type="hidden" name="token" value="${tk}"><input type="hidden" name="action" value="mint">
<p><input name="days" type="number" value="30" placeholder="Days" style="${box}"></p>
<p><input name="count" type="number" value="1" placeholder="How many (1-20)" style="${box}"></p>
<p><input name="note" placeholder="Note (optional, e.g. a name)" style="${box}"></p>
<p><button style="${box};font-size:16px">Make token(s)</button></p>
</form>
<h3>Grant days to an ID</h3>
<form method="post">
<input type="hidden" name="token" value="${tk}"><input type="hidden" name="action" value="grant">
<p><input name="install_id" placeholder="Paste the person's ID" style="${box}"></p>
<p><input name="days" type="number" value="30" style="${box}"></p>
<p><button style="${box};font-size:16px">Grant days (0 = switch off)</button></p>
</form>
<h3>Unused tokens</h3>
<table style="width:100%;font-size:12.5px"><tr><th align=left>Token<th align=left>Days<th align=left>For<th align=left>Note</tr>${unusedHtml}</table>
<h3>Ad-free phones</h3>
<table style="width:100%;font-size:12.5px"><tr><th align=left>ID<th align=left>Source<th align=left>Until<th align=left>E-mail</tr>${list}</table>
</body>`
  );
}
