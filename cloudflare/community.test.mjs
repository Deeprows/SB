// Run: node --no-warnings cloudflare/community.test.mjs   (Node 22+)
// Movie community: tweets, recommendations, likes, comments, profiles.
// Google's token check is faked: the token IS the Gmail address.
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";

globalThis.caches = { default: { match: async () => undefined, put: async () => {} } };
const realFetch = globalThis.fetch;
globalThis.fetch = async (u, init) => {
  const s = String(u);
  if (s.startsWith("https://oauth2.googleapis.com/tokeninfo")) {
    const t = new URL(s).searchParams.get("id_token");
    if (!t.includes("@")) return new Response("{}", { status: 400 });
    return new Response(
      JSON.stringify({ aud: "web-client", email_verified: "true", email: t, name: t.split("@")[0], picture: "" }),
      { status: 200 }
    );
  }
  return realFetch(u, init);
};

const sqlite = new DatabaseSync(":memory:");
// An OLD database (before kind / movie_id existed) must upgrade itself.
sqlite.exec("CREATE TABLE community_posts (id TEXT PRIMARY KEY, email TEXT NOT NULL, text TEXT NOT NULL, movie_title TEXT, movie_image TEXT, rating INTEGER, created_at INTEGER NOT NULL)");
sqlite.exec("INSERT INTO community_posts VALUES ('old1','ann@gmail.com','old tweet',NULL,NULL,NULL,1)");

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
const env = { DB, GOOGLE_CLIENT_ID: "web-client" };
const ctx = { waitUntil: () => {} };
const call = (who, path, body) =>
  worker.fetch(
    new Request("https://feed.example.com" + path, {
      method: body ? "POST" : "GET",
      headers: who ? { authorization: `Bearer ${who}` } : {},
      body: body ? JSON.stringify(body) : undefined,
    }),
    env,
    ctx
  );
const ok = async (r) => { assert.equal(r.status < 300, true, `status ${r.status}`); return r.json(); };
const ann = "ann@gmail.com";
const bob = "bob@gmail.com";

assert.equal((await (await call(null, "/health")).json()).community, true);
assert.equal((await call(null, "/community/posts")).status, 401);
assert.equal((await call("nobody", "/community/posts")).status, 401);
// a Google-only Worker never accepts a phone key
assert.equal((await worker.fetch(new Request("https://f.example.com/community/posts", { headers: { "x-community-email": "k@gmail.com", "x-community-key": "a".repeat(32) } }), { ...env, COMMUNITY_REQUIRE_GOOGLE: "1" }, ctx)).status, 401);

// old rows survive the upgrade and count as tweets
let j = await ok(await call(ann, "/community/posts"));
assert.deepEqual(j.posts.map((p) => [p.id, p.kind]), [["old1", "tweet"]]);

// tweet + recommendation with a movie
j = await ok(await call(ann, "/community/posts", { text: "Dune on a big screen", kind: "tweet", movieTitle: "Dune", movieId: 438631, movieType: "movie", movieImage: "https://image.tmdb.org/t/p/w500/x.jpg", rating: 9 }));
const tweetId = j.id;
assert.equal(j.post.movieId, 438631);
assert.equal(j.post.mine, true);
assert.equal((await call(ann, "/community/posts", { text: "watch it", kind: "recommendation" })).status, 400);
assert.equal((await call(ann, "/community/posts", { text: "", kind: "tweet" })).status, 400);
j = await ok(await call(ann, "/community/posts", { text: "Must watch", kind: "recommendation", movieTitle: "Severance", movieId: 95396, movieType: "tv" }));
const recId = j.id;
assert.equal(j.post.movieType, "tv");

// filter by kind; newest first
j = await ok(await call(bob, "/community/posts?kind=recommendation"));
assert.deepEqual(j.posts.map((p) => p.id), [recId]);
j = await ok(await call(bob, "/community/posts"));
assert.deepEqual(j.posts.map((p) => p.id), [recId, tweetId, "old1"]);
assert.equal(j.posts[0].mine, false);

// likes toggle; likedByMe is a real boolean for the viewer
j = await ok(await call(bob, "/community/like", { postId: tweetId }));
assert.deepEqual([j.liked, j.likeCount], [true, 1]);
j = await ok(await call(bob, "/community/posts?kind=tweet"));
assert.deepEqual([j.posts[0].likeCount, j.posts[0].likedByMe], [1, true]);
j = await ok(await call(ann, "/community/posts?kind=tweet"));
assert.equal(j.posts[0].likedByMe, false);
j = await ok(await call(bob, "/community/like", { postId: tweetId }));
assert.deepEqual([j.liked, j.likeCount], [false, 0]);
assert.equal((await call(bob, "/community/like", { postId: "nope" })).status, 404);

// comments; delete rules
j = await ok(await call(bob, "/community/comments", { postId: tweetId, text: "Agree!" }));
assert.equal(j.commentCount, 1);
await ok(await call(ann, "/community/comments", { postId: tweetId, text: "Thanks" }));
assert.equal((await call(bob, "/community/comments", { postId: tweetId, text: "  " })).status, 400);
j = await ok(await call(bob, `/community/comments?postId=${tweetId}`));
assert.deepEqual(j.comments.map((c) => [c.name, c.mine, c.canDelete]), [["bob", true, true], ["ann", false, false]]);
const [bobsComment, annsComment] = j.comments.map((c) => c.id);
assert.equal((await call(bob, "/community/comments/delete", { id: annsComment })).status, 404);
await ok(await call(ann, "/community/comments/delete", { id: bobsComment })); // post owner may
j = await ok(await call(ann, `/community/comments?postId=${tweetId}`));
assert.equal(j.comments.length, 1);

// profile: last tweet + last recommendation, counts, people
j = (await ok(await call(bob, `/community/profile?email=${ann}`))).profile;
assert.equal(j.mine, false);
assert.equal(j.lastTweet.id, tweetId);
assert.equal(j.lastRecommendation.id, recId);
assert.equal(j.postCount, 3);
assert.equal((await call(bob, "/community/profile?email=ghost@gmail.com")).status, 404);
j = await ok(await call(bob, "/community/people"));
assert.ok(j.people.some((p) => p.email === ann && p.postCount === 3));

// only the author deletes a post, its comments go too
assert.equal((await call(bob, "/community/delete", { postId: tweetId })).status, 404);
await ok(await call(ann, "/community/delete", { postId: tweetId }));
j = await ok(await call(ann, `/community/comments?postId=${tweetId}`));
assert.equal(j.comments.length, 0);

// ---- no Google setup: the phone key is enough --------------------------------
const noGoogle = { DB }; // no GOOGLE_CLIENT_ID
const asPhone = (email, key, path, body) =>
  worker.fetch(
    new Request("https://feed.example.com" + path, {
      method: body ? "POST" : "GET",
      headers: { "x-community-email": email, "x-community-key": key, "x-community-name": encodeURIComponent("Zoë"), "x-community-photo": "https://example.com/z.jpg" },
      body: body ? JSON.stringify(body) : undefined,
    }),
    noGoogle,
    ctx
  );
const K1 = "1".repeat(32);
const K2 = "2".repeat(32);
const zoe = "zoe@gmail.com";

// first phone claims the Gmail and can post
j = await ok(await asPhone(zoe, K1, "/community/posts", { text: "hello from a phone", kind: "tweet" }));
assert.equal(j.post.name, "Zoë");
assert.equal(j.post.photoUrl, "https://example.com/z.jpg");
assert.equal(j.post.mine, true);
// same phone again works; another phone is refused
assert.equal((await asPhone(zoe, K1, "/community/posts")).status, 200);
let r = await asPhone(zoe, K2, "/community/posts");
assert.equal(r.status, 401);
assert.equal((await r.json()).error, "community_key_mismatch");
// bad / missing key or non-Gmail
assert.equal((await asPhone(zoe, "short", "/community/posts")).status, 401);
assert.equal((await asPhone("x@yahoo.com", K1, "/community/posts")).status, 401);
// a Google-verified login (token + client id) takes the Gmail over from a phone key
await ok(await call(zoe, "/community/posts"));
assert.equal((await asPhone(zoe, K2, "/community/posts")).status, 200); // key freed, K2 claims it now

// admin reset frees a Gmail
assert.equal((await worker.fetch(new Request(`https://f.example.com/community/admin/reset?token=bad&email=${zoe}`), { DB, ADMIN_TOKEN: "adm" }, ctx)).status, 403);
r = await worker.fetch(new Request(`https://f.example.com/community/admin/reset?token=adm&email=${zoe}`), { DB, ADMIN_TOKEN: "adm" }, ctx);
assert.equal(r.status, 200);
assert.equal((await asPhone(zoe, K1, "/community/posts")).status, 200); // K1 claims again

console.log("community: ok");
