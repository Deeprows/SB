// Run: node --no-warnings cloudflare/token.test.mjs   (Node 22+)
// Ad-free tokens: request -> admin creates -> phone finds / redeems.
// Deliberately NO Paystack key: tokens must work with only the DB binding.
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";

globalThis.caches = { default: { match: async () => undefined, put: async () => {} } };

const sqlite = new DatabaseSync(":memory:");
const DB = {
  prepare(sql) {
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
const env = { DB, ADMIN_TOKEN: "adm" };
const ctx = { waitUntil: () => {} };
const call = (path, init) => worker.fetch(new Request("https://feed.example.com" + path, init), env, ctx);
const post = (path, body) => call(path, { method: "POST", body: JSON.stringify(body) });
const admin = (fields) => {
  const f = new FormData();
  f.set("token", "adm");
  for (const [k, v] of Object.entries(fields)) f.set(k, String(v));
  return call("/sub/admin", { method: "POST", body: f });
};
const A = "a1b2c3d4e5f60718293a4b5c6d7e8f90";
const B = "ffeeddccbbaa00998877665544332211";
const C = "00112233445566778899aabbccddeeff";
const tokenIn = (htmlText) => /([A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4})/.exec(htmlText)?.[1];

// health
assert.equal((await (await call("/health")).json()).tokens, true);

// 1. request -> pending; asking again is harmless
let j = await (await post("/sub/token/request", { install_id: A, contact: "+234 801 234 5678" })).json();
assert.equal(j.state, "pending");
await post("/sub/token/request", { install_id: A });
assert.equal((await (await call(`/sub/token/mine?install=${A}`)).json()).state, "pending");
assert.equal((await (await call(`/sub/token/mine?install=${B}`)).json()).state, "none");
assert.equal((await post("/sub/token/request", { install_id: "x" })).status, 400);

// 2. admin page needs the password and shows the request (+ contact)
assert.equal((await call("/sub/admin?token=nope")).status, 403);
let page = await (await call("/sub/admin?token=adm")).text();
assert.ok(page.includes("+234 801 234 5678") && page.includes("https://wa.me/2348012345678") && page.includes('value="answer"'));

// 3. admin answers the request -> token bound to that phone; request leaves the list
page = await (await admin({ action: "answer", install_id: A, days: 30 })).text();
const tokA = tokenIn(page);
assert.ok(tokA, "token shown to admin");
assert.ok(!(await (await call("/sub/admin?token=adm")).text()).includes('value="answer"'), "request leaves the waiting list");
j = await (await call(`/sub/token/mine?install=${A}`)).json();
assert.equal(j.state, "ready"); assert.equal(j.token, tokA); assert.equal(j.days, 30);
assert.equal((await (await call(`/sub/token/mine?install=${B}`)).json()).state, "none", "other phones can't see it");

// 4. another phone cannot use a token made for A
j = await post("/sub/token/redeem", { install_id: B, token: tokA });
assert.equal(j.status, 403);
assert.equal((await (await call(`/sub/status?install=${B}`)).json()).active, false);

// 5. A redeems (lower-case, no dashes also accepted) -> ~30 days of ad-free
j = await (await post("/sub/token/redeem", { install_id: A, token: tokA.replace(/-/g, "").toLowerCase() })).json();
assert.equal(j.active, true);
assert.ok(Math.abs(j.expires_at - Date.now() - 30 * 86400000) < 60000);
let st = await (await call(`/sub/status?install=${A}`)).json();
assert.equal(st.active, true); assert.equal(st.expires_at, j.expires_at);
assert.equal((await (await call(`/sub/token/mine?install=${A}`)).json()).state, "active");

// 6. pressing again on the same phone does not add time; another phone is refused
j = await (await post("/sub/token/redeem", { install_id: A, token: tokA })).json();
assert.equal(j.expires_at, st.expires_at);
assert.equal((await post("/sub/token/redeem", { install_id: B, token: tokA })).status, 409);

// 7. open (any-phone) tokens: made in advance, work exactly once
page = await (await admin({ action: "mint", days: 7, count: 2, note: "friend" })).text();
const open = [...page.matchAll(/([A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4})/g)].map((m) => m[1]);
assert.equal(new Set(open).size, 2);
j = await (await post("/sub/token/redeem", { install_id: B, token: open[0] })).json();
assert.equal(j.active, true);
assert.equal((await post("/sub/token/redeem", { install_id: C, token: open[0] })).status, 409);
// time stacks on what is left
j = await (await post("/sub/token/redeem", { install_id: B, token: open[1] })).json();
assert.ok(Math.abs(j.expires_at - Date.now() - 14 * 86400000) < 60000);

// 8. junk tokens
assert.equal((await post("/sub/token/redeem", { install_id: C, token: "ABCD-EFGH-JKLM" })).status, 404);
assert.equal((await post("/sub/token/redeem", { install_id: C, token: "short" })).status, 400);

// 9. a phone that is already ad-free is told so instead of queueing a request
assert.equal((await (await post("/sub/token/request", { install_id: A })).json()).state, "active");

// 10. dismiss + grant + revoke still work on the same page
await post("/sub/token/request", { install_id: C });
await admin({ action: "dismiss", install_id: C });
assert.equal((await (await call(`/sub/token/mine?install=${C}`)).json()).state, "none");
await admin({ action: "grant", install_id: C, days: 5 });
assert.equal((await (await call(`/sub/status?install=${C}`)).json()).active, true);
await admin({ action: "grant", install_id: C, days: 0 });
assert.equal((await (await call(`/sub/status?install=${C}`)).json()).active, false);

// 11. Paystack routes still say "not set up" without the key
assert.equal((await post("/sub/start", { install_id: A, email: "a@b.co" })).status, 503);

console.log("token tests passed");
