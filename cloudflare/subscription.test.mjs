// Run: node --no-warnings cloudflare/subscription.test.mjs   (Node 22+)
// Uses Node's built-in SQLite as a stand-in for Cloudflare D1.
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { createHmac } from "node:crypto";

const store = new Map();
globalThis.caches = { default: {
  match: async (req) => { const r = store.get(req.url); return r ? r.clone() : undefined; },
  put: async (req, res) => { store.set(req.url, res); },
} };

// ---- fake Paystack + exchange-rate API
const txs = new Map();           // reference -> transaction object
let initBody = null;
globalThis.fetch = async (url, opts = {}) => {
  const u = String(url);
  if (u.includes("open.er-api.com")) {
    return new Response(JSON.stringify({ rates: { USD: 0.00065, GHS: 0.0099 } }));
  }
  if (u.endsWith("/transaction/initialize")) {
    assert.equal(opts.headers.authorization, "Bearer sk_test");
    initBody = JSON.parse(opts.body);
    txs.set(initBody.reference, {
      status: "success", reference: initBody.reference, currency: "NGN",
      amount: initBody.plan ? 200000 : initBody.amount,
      customer: { email: initBody.email }, metadata: initBody.metadata,
    });
    return new Response(JSON.stringify({ status: true, data: { authorization_url: "https://checkout.paystack.com/x", reference: initBody.reference } }));
  }
  const m = /\/transaction\/verify\/(.+)$/.exec(u);
  if (m) {
    const t = txs.get(decodeURIComponent(m[1]));
    return new Response(JSON.stringify(t ? { status: true, data: t } : { status: false, message: "not found" }), { status: t ? 200 : 404 });
  }
  throw new Error("unexpected fetch " + u);
};

// ---- D1 stand-in over node:sqlite
const sqlite = new DatabaseSync(":memory:");
const DB = {
  prepare(sql) {
    // Compile lazily, like D1 does, so a batch can create a table and then
    // an index on it.
    const stmt = () => sqlite.prepare(sql);
    let args = [];
    const o = {
      bind(...a) { args = a; return o; },
      async first() { return stmt().get(...args) ?? null; },
      async all() { return { results: stmt().all(...args) }; },
      async run() { const r = stmt().run(...args); return { meta: { changes: Number(r.changes) } }; },
      _run() { stmt().run(...args); },
    };
    return o;
  },
  async batch(list) { list.forEach((s) => s._run()); },
};

const worker = (await import("./worker.js")).default;
const env = { DB, PAYSTACK_SECRET_KEY: "sk_test", PAYSTACK_PLAN_CODE: "PLN_x", ADMIN_TOKEN: "adm" };
const ctx = { waitUntil: () => {} };
const call = (path, init) => worker.fetch(new Request("https://feed.example.com" + path, init), env, ctx);
const post = (path, body) => call(path, { method: "POST", body: JSON.stringify(body) });
const ID = "a1b2c3d4e5f60718293a4b5c6d7e8f90";
const ID2 = "ffeeddccbbaa00998877665544332211";

// 1. config: naira price, local equivalent, no secrets
let j = await (await call("/sub/config?cur=USD")).json();
assert.equal(j.price_ngn, 2000);
assert.equal(j.price_display, "₦2,000");
assert.equal(j.local_display, "$1.30");
assert.equal(j.recurring, true);
j = await (await call("/sub/config?cur=NGN")).json();
assert.equal(j.local_display, null);
j = await (await call("/sub/config?cur=ZZZ")).json();
assert.equal(j.local_display, null);

// 2. status of a stranger is inactive; bad ids rejected
j = await (await call(`/sub/status?install=${ID}`)).json();
assert.equal(j.active, false);
assert.equal((await call("/sub/status?install=x")).status, 400);

// 3. start: validates, builds the right Paystack request
assert.equal((await post("/sub/start", { install_id: ID, email: "bad" })).status, 400);
j = await (await post("/sub/start", { install_id: ID, email: "Ada@Example.com", recurring: false })).json();
assert.equal(j.authorization_url, "https://checkout.paystack.com/x");
assert.equal(initBody.amount, 200000);
assert.equal(initBody.currency, "NGN");
assert.equal(initBody.email, "ada@example.com");
assert.equal(initBody.metadata.install_id, ID);
assert.equal(initBody.callback_url, "https://feed.example.com/sub/done");
assert.equal(initBody.plan, undefined);
const ref1 = j.reference;

// 4. verify grants ~31 days, and is idempotent (webhook + verify for one payment)
j = await (await call(`/sub/verify?reference=${ref1}`)).json();
assert.equal(j.status, "success"); assert.equal(j.active, true);
const first = j.expires_at;
assert.ok(first - Date.now() > 30.9 * 86400000 && first - Date.now() < 31.1 * 86400000);
j = await (await call(`/sub/verify?reference=${ref1}`)).json();
assert.equal(j.expires_at, first);
const body = JSON.stringify({ event: "charge.success", data: txs.get(ref1) });
let sig = createHmac("sha512", "sk_test").update(body).digest("hex");
assert.equal((await call("/sub/webhook", { method: "POST", body, headers: { "x-paystack-signature": sig } })).status, 200);
j = await (await call(`/sub/status?install=${ID}`)).json();
assert.equal(j.expires_at, first, "same payment must not extend twice");
assert.equal(j.active, true);

// 5. webhook: bad signature rejected
assert.equal((await call("/sub/webhook", { method: "POST", body, headers: { "x-paystack-signature": "nope" } })).status, 401);

// 6. automatic renewal (no metadata) is matched by e-mail and stacks on top
txs.set("RENEW1", { status: "success", reference: "RENEW1", currency: "NGN", amount: 200000, customer: { email: "ada@example.com" }, metadata: {} });
const rb = JSON.stringify({ event: "charge.success", data: txs.get("RENEW1") });
sig = createHmac("sha512", "sk_test").update(rb).digest("hex");
await call("/sub/webhook", { method: "POST", body: rb, headers: { "x-paystack-signature": sig } });
j = await (await call(`/sub/status?install=${ID}`)).json();
assert.equal(j.expires_at, first + 31 * 86400000);

// 7. under-paid / wrong-currency / failed payments never grant
txs.set("CHEAP01", { status: "success", reference: "CHEAP01", currency: "NGN", amount: 100, customer: { email: "x@y.com" }, metadata: { install_id: ID2 } });
j = await (await call("/sub/verify?reference=CHEAP01")).json();
assert.equal(j.status, "failed");
txs.set("USD0001", { status: "success", reference: "USD0001", currency: "USD", amount: 900000, customer: { email: "x@y.com" }, metadata: { install_id: ID2 } });
assert.equal((await (await call("/sub/verify?reference=USD0001")).json()).status, "failed");
txs.set("ABAND01", { status: "abandoned", reference: "ABAND01", currency: "NGN", amount: 200000, customer: { email: "x@y.com" }, metadata: { install_id: ID2 } });
assert.equal((await (await call("/sub/verify?reference=ABAND01")).json()).status, "failed");
assert.equal((await (await call(`/sub/status?install=${ID2}`)).json()).active, false);
assert.equal((await call("/sub/verify?reference=a")).status, 400);

// 8. restore on a new phone: needs matching e-mail + a real reference
assert.equal((await post("/sub/restore", { install_id: ID2, email: "other@example.com", reference: ref1 })).status, 404);
j = await (await post("/sub/restore", { install_id: ID2, email: "ada@example.com", reference: ref1 })).json();
assert.equal(j.active, true);
assert.equal((await (await call(`/sub/status?install=${ID2}`)).json()).active, true);

// 9. recurring checkout sends the plan
await post("/sub/start", { install_id: ID, email: "ada@example.com", recurring: true });
assert.equal(initBody.plan, "PLN_x");

// 10. admin: protected, grants days for WhatsApp payers, revokes with 0
assert.equal((await call("/sub/admin?token=wrong")).status, 403);
const ID3 = "00112233445566778899aabbccddeeff";
const form = (o) => ({ method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams(o).toString() });
let page = await (await call("/sub/admin", form({ token: "adm", install_id: ID3, days: "30" }))).text();
assert.match(page, /Premium until/);
assert.equal((await (await call(`/sub/status?install=${ID3}`)).json()).active, true);
await call("/sub/admin", form({ token: "adm", install_id: ID3, days: "0" }));
assert.equal((await (await call(`/sub/status?install=${ID3}`)).json()).active, false);
assert.equal((await call("/sub/admin?token=adm")).status, 200);

// 11. not set up: config still answers, the rest says 503; feed unaffected
const bare = (p) => worker.fetch(new Request("https://f.example.com" + p), {}, ctx);
assert.equal((await bare("/sub/config")).status, 200);
assert.equal((await (await bare("/sub/config")).json()).available, false);
assert.equal((await bare(`/sub/status?install=${ID}`)).status, 503);

console.log("subscription tests passed");
