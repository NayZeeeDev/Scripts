// Unit tests for the pulse-api gateway with in-memory fakes (no network, no database).
// Run from nayzeee-streamer/:
//   deno test --allow-env --allow-net supabase/tests/gateway.test.ts

import { assert, assertEquals, assertExists, assertMatch, assertNotEquals, assertRejects, assertStringIncludes } from "jsr:@std/assert@1";
import { ACTIONS, handle } from "../functions/pulse-api/index.ts";
import { getAction, rpcName } from "../functions/pulse-api/lib/actions.ts";
import { parseServerRow } from "../functions/pulse-api/lib/auth.ts";
import { RpcError } from "../functions/pulse-api/lib/errors.ts";
import { LiveKitClient, LiveKitError, twirpBase } from "../functions/pulse-api/lib/livekit.ts";
import { TokenBuckets } from "../functions/pulse-api/lib/ratelimit.ts";
import { createStorage, type StorageClientLike } from "../functions/pulse-api/lib/storage.ts";
import type { CreateRoomOptions, Deps, Json, TokenGrants } from "../functions/pulse-api/lib/types.ts";
import { hostAllowed } from "../functions/pulse-api/lib/validate.ts";

// ---------------------------------------------------------------------------------------------
// Fakes

const KEY = "pk_" + "a1".repeat(24);
const KEY_INACTIVE = "pk_" + "b2".repeat(24);
const KEY_OTHER = "pk_" + "c3".repeat(24);
const SERVER_ID = "11111111-1111-4111-8111-111111111111";
const OTHER_SERVER_ID = "33333333-3333-4333-8333-333333333333";
const CHANNEL_ID = "22222222-2222-4222-8222-222222222222";
const STREAM_ID = "44444444-4444-4444-8444-444444444444";
const PUBLIC_BASE = "https://proj.supabase.co/storage/v1/object/public/pulse-media";
const ACTOR = { ref: "char:ABC123", name: "Tlay Jones" };
const START = Date.UTC(2026, 9, 28, 12, 0, 0);

type Handler = (args: Record<string, unknown>) => unknown;

interface LkCall {
  op: "createRoom" | "token" | "sendData" | "deleteRoom" | "signedUpload";
  args: unknown[];
}

interface FakeOptions {
  handlers?: Record<string, Handler>;
  settings?: Record<string, Json>;
  failSend?: boolean;
  failDelete?: boolean;
  failCreate?: boolean;
  debug?: boolean;
}

function fakeServerRow(id: string, active: boolean) {
  return {
    id,
    slug: id === SERVER_ID ? "nzrp" : "other",
    name: "Nayzeee RP",
    tag: "NZRP",
    color: "#08afa2",
    trusted: true,
    network_admin: false,
    active,
  };
}

function makeFake(options: FakeOptions = {}) {
  const rpcCalls: { fn: string; args: Record<string, unknown> }[] = [];
  const lk: LkCall[] = [];
  const logs: string[] = [];
  let nowMs = START;
  const settings: Record<string, Json> = options.settings ??
    { chatMaxLength: 300, imageHosts: ["i.imgur.com", "*.discordapp.net"] };

  const deps: Deps = {
    rpc: (fn, args) => {
      rpcCalls.push({ fn, args });
      if (fn === "pulse_server_by_key") {
        if (args.p_key === KEY) return Promise.resolve(fakeServerRow(SERVER_ID, true));
        if (args.p_key === KEY_INACTIVE) return Promise.resolve(fakeServerRow("55555555-5555-4555-8555-555555555555", false));
        if (args.p_key === KEY_OTHER) return Promise.resolve([fakeServerRow(OTHER_SERVER_ID, true)]);
        return Promise.resolve(null);
      }
      const handler = options.handlers?.[fn];
      if (handler) {
        try {
          return Promise.resolve(handler(args));
        } catch (err) {
          return Promise.reject(err);
        }
      }
      if (fn === "pulse_act_server_hello") {
        return Promise.resolve({ ok: true, data: { server: fakeServerRow(SERVER_ID, true), settings } });
      }
      return Promise.reject(new RpcError(fn, "PGRST202", `Could not find the function public.${fn}`, null, null));
    },
    storage: {
      publicBase: PUBLIC_BASE,
      signedUpload: (bucket, path, contentType, upsert) => {
        lk.push({ op: "signedUpload", args: [bucket, path, contentType, upsert] });
        return Promise.resolve({
          uploadUrl: `https://proj.supabase.co/storage/v1/object/upload/sign/${bucket}/${path}?token=signed`,
          headers: { "content-type": contentType, "x-upsert": upsert ? "true" : "false", "cache-control": "max-age=3600" },
        });
      },
      publicUrl: (bucket, path) => `https://proj.supabase.co/storage/v1/object/public/${bucket}/${path}`,
    },
    livekit: {
      url: "wss://live.example.com",
      token: (grants: TokenGrants) => {
        lk.push({ op: "token", args: [grants] });
        return Promise.resolve(`token-for-${grants.identity}`);
      },
      createRoom: (opts: CreateRoomOptions) => {
        lk.push({ op: "createRoom", args: [opts] });
        return options.failCreate
          ? Promise.reject(new LiveKitError("LiveKit CreateRoom failed: timed out after 5000 ms", 0, "unavailable"))
          : Promise.resolve();
      },
      deleteRoom: (room: string) => {
        lk.push({ op: "deleteRoom", args: [room] });
        return options.failDelete ? Promise.reject(new Error("boom")) : Promise.resolve();
      },
      sendData: (room: string, topic: string, payload: Json) => {
        lk.push({ op: "sendData", args: [room, topic, payload] });
        return options.failSend
          ? Promise.reject(new LiveKitError("LiveKit SendData failed (503 unavailable)", 503, "unavailable"))
          : Promise.resolve();
      },
      listParticipants: () => Promise.resolve([]),
    },
    now: () => new Date(nowMs),
    log: (level, message) => {
      logs.push(`${level}: ${message}`);
    },
    debug: options.debug ?? false,
  };

  return {
    deps,
    rpcCalls,
    lk,
    logs,
    advance(ms: number) {
      nowMs += ms;
    },
    calls(fn: string) {
      return rpcCalls.filter((call) => call.fn === fn);
    },
  };
}

function post(body: unknown, init: { key?: string | null; headers?: Record<string, string>; raw?: string } = {}) {
  const headers: Record<string, string> = { "content-type": "application/json", ...init.headers };
  const key = init.key === undefined ? KEY : init.key;
  if (key !== null) headers["x-pulse-key"] = key;
  return new Request("http://localhost/pulse-api", {
    method: "POST",
    headers,
    body: init.raw ?? JSON.stringify(body),
  });
}

async function call(deps: Deps, body: unknown, init?: Parameters<typeof post>[1]) {
  const res = await handle(post(body, init), deps);
  const json = await res.json() as Record<string, unknown>;
  return { status: res.status, body: json, res };
}

const ok = (data: Record<string, Json> = {}, fx?: Record<string, Json>) => (fx ? { ok: true, data, fx } : { ok: true, data });

// ---------------------------------------------------------------------------------------------
// Health / method / auth

Deno.test("GET /health returns ok without auth; other methods are rejected", async () => {
  const f = makeFake();
  const health = await handle(new Request("http://localhost/pulse-api/health"), f.deps);
  assertEquals(health.status, 200);
  assertEquals(await health.json(), { ok: true });

  const get = await handle(new Request("http://localhost/pulse-api"), f.deps);
  assertEquals(get.status, 405);
  assertEquals(get.headers.get("allow"), "POST");
  assertEquals((await get.json()).error, "bad_request");
  assertEquals(f.rpcCalls.length, 0);
});

Deno.test("auth: missing, malformed and unknown keys are 401", async () => {
  const f = makeFake();
  const missing = await call(f.deps, { action: "server.hello" }, { key: null });
  assertEquals(missing.status, 401);
  assertEquals(missing.body.ok, false);
  assertEquals(missing.body.error, "unauthorized");

  const malformed = await call(f.deps, { action: "server.hello" }, { key: "has spaces in it" });
  assertEquals(malformed.status, 401);
  assertEquals(f.calls("pulse_server_by_key").length, 0, "malformed keys never reach the database");

  const unknown = await call(f.deps, { action: "server.hello" }, { key: "pk_" + "0".repeat(48) });
  assertEquals(unknown.status, 401);
  assertEquals(unknown.body.error, "unauthorized");
  assertEquals(f.calls("pulse_server_by_key").length, 1);
});

Deno.test("auth: negative lookups are cached 10 s", async () => {
  const f = makeFake();
  const badKey = "pk_" + "d4".repeat(24);
  await call(f.deps, { action: "server.hello" }, { key: badKey });
  await call(f.deps, { action: "server.hello" }, { key: badKey });
  assertEquals(f.calls("pulse_server_by_key").length, 1);
  f.advance(10_001);
  await call(f.deps, { action: "server.hello" }, { key: badKey });
  assertEquals(f.calls("pulse_server_by_key").length, 2);
});

Deno.test("auth: valid lookups are cached 60 s and the key is passed as p_key", async () => {
  const f = makeFake();
  const first = await call(f.deps, { action: "server.hello" });
  assertEquals(first.status, 200);
  assertEquals(first.body.ok, true);
  assertEquals(f.calls("pulse_server_by_key")[0].args, { p_key: KEY });
  f.advance(59_000);
  await call(f.deps, { action: "server.hello" });
  assertEquals(f.calls("pulse_server_by_key").length, 1);
  f.advance(2_000);
  await call(f.deps, { action: "server.hello" });
  assertEquals(f.calls("pulse_server_by_key").length, 2);
});

Deno.test("auth: inactive servers are 401; setof rows and null composites are understood", async () => {
  const f = makeFake();
  const inactive = await call(f.deps, { action: "server.hello" }, { key: KEY_INACTIVE });
  assertEquals(inactive.status, 401);
  assertStringIncludes(String(inactive.body.message), "disabled");

  const other = await call(f.deps, { action: "server.hello" }, { key: KEY_OTHER });
  assertEquals(other.status, 200);
  assertEquals(f.calls("pulse_act_server_hello").at(-1)?.args.p_server, OTHER_SERVER_ID);

  assertEquals(parseServerRow({ id: null, slug: null }), null);
  assertEquals(parseServerRow([]), null);
  assertEquals(parseServerRow(null), null);
  assertEquals(parseServerRow({ id: SERVER_ID, network_admin: true })?.networkAdmin, true);
});

// ---------------------------------------------------------------------------------------------
// Routing / body

Deno.test("routing: malformed JSON, unknown actions and bad params are 400 bad_request", async () => {
  const f = makeFake();
  const malformed = await call(f.deps, null, { raw: "{not json" });
  assertEquals(malformed.status, 400);
  assertEquals(malformed.body.error, "bad_request");

  const notObject = await call(f.deps, [1, 2, 3]);
  assertEquals(notObject.status, 400);

  const unknown = await call(f.deps, { action: "stream.hack", actor: ACTOR });
  assertEquals(unknown.status, 400);
  assertEquals(unknown.body.error, "bad_request");
  assertStringIncludes(String(unknown.body.message), "stream.hack");

  const inherited = await call(f.deps, { action: "constructor" });
  assertEquals(inherited.status, 400);

  const badParams = await call(f.deps, { action: "browse.home", actor: ACTOR, params: [1] });
  assertEquals(badParams.status, 400);

  const wrongType = await call(f.deps, { action: "browse.home", actor: ACTOR }, {
    headers: { "content-type": "text/plain" },
  });
  assertEquals(wrongType.status, 415);
  assertEquals(f.rpcCalls.filter((c) => c.fn.startsWith("pulse_act_")).length, 0);
});

Deno.test("routing: actor is required for actor actions and ignored for server actions", async () => {
  const f = makeFake({
    handlers: {
      pulse_act_browse_home: () => ok({ live: [] }),
      pulse_act_admin_streams: () => ok({ streams: [] }),
    },
  });
  const noActor = await call(f.deps, { action: "browse.home" });
  assertEquals(noActor.status, 400);
  assertStringIncludes(String(noActor.body.message), "actor");

  const badRef = await call(f.deps, { action: "browse.home", actor: { ref: "a b", name: "x" } });
  assertEquals(badRef.status, 400);

  const okHome = await call(f.deps, { action: "browse.home", actor: { ref: "char:XYZ", name: "  Long\nName  " } });
  assertEquals(okHome.status, 200);
  assertEquals(f.calls("pulse_act_browse_home")[0].args, {
    p_server: SERVER_ID,
    p_actor: { ref: "char:XYZ", name: "Long Name" },
    p_params: {},
  });

  const admin = await call(f.deps, { action: "admin.streams", actor: ACTOR, params: [] });
  assertEquals(admin.status, 200);
  assertEquals(f.calls("pulse_act_admin_streams")[0].args.p_actor, null);
});

Deno.test("routing: params are cleaned (unknown keys dropped, defaults applied, ids normalised)", async () => {
  const f = makeFake({ handlers: { pulse_act_browse_live: () => ok({ streams: [], total: 0 }) } });
  const res = await call(f.deps, {
    action: "browse.live",
    actor: ACTOR,
    params: { category: "Street-Racing", evil: "drop me", _publicBase: "https://evil.example" },
  });
  assertEquals(res.status, 200);
  assertEquals(res.body, { ok: true, data: { streams: [], total: 0 } });
  assertEquals(f.calls("pulse_act_browse_live")[0].args.p_params, {
    category: "street-racing",
    sort: "viewers",
    limit: 60,
    offset: 0,
  });
});

Deno.test("registry: every SPEC §2.2 action exists with the right caller kind", () => {
  const server = [
    "server.hello",
    "live.poll",
    "points.tick",
    "admin.streams",
    "admin.end_stream",
    "admin.ban",
    "admin.reports",
    "admin.report_update",
    "admin.verify",
    "admin.lookup",
  ];
  const serverActor = ["sparks.credit", "cashout.request", "cashout.refund", "stream.start"];
  const actor = [
    "account.me", "account.update", "account.handle_check", "media.upload", "browse.home", "browse.live",
    "browse.search", "browse.following", "channel.get", "follow.set", "wallet.get", "sparks.cheer", "sub.buy",
    "sub.gift", "sub.cancel", "subs.mine", "stream.update", "stream.heartbeat", "stream.end", "stream.watch",
    "chat.send", "chat.history", "chat.delete", "chat.timeout", "chat.ban", "chat.unban", "chat.clear",
    "chat.settings", "mods.list", "mods.set", "bans.list", "user.card", "rewards.list", "rewards.save",
    "rewards.delete", "rewards.redeem", "redemptions.list", "redemptions.update", "poll.create", "poll.vote",
    "poll.end", "raid.start", "dash.overview", "dash.followers", "dash.subs", "activity.list", "report.create",
  ];
  for (const name of server) assertEquals(getAction(name)?.kind, "server", name);
  for (const name of serverActor) assertEquals(getAction(name)?.kind, "server+actor", name);
  for (const name of actor) assertEquals(getAction(name)?.kind, "actor", name);
  assertEquals(Object.keys(ACTIONS).length, server.length + serverActor.length + actor.length);
  assertEquals(rpcName("admin.report_update"), "pulse_act_admin_report_update");
  assertEquals(rpcName("chat.send"), "pulse_act_chat_send");
  assertEquals(getAction("toString"), undefined);
});

// ---------------------------------------------------------------------------------------------
// Rate limiting

Deno.test("rate limit: per server 40 req/s with burst 80", async () => {
  const f = makeFake();
  for (let i = 0; i < 80; i++) {
    const res = await call(f.deps, { action: "server.hello" });
    assertEquals(res.status, 200, `request ${i}`);
  }
  const limited = await call(f.deps, { action: "server.hello" });
  assertEquals(limited.status, 429);
  assertEquals(limited.body.error, "rate_limited");
  assertExists(limited.res.headers.get("retry-after"));

  f.advance(500); // +20 tokens
  for (let i = 0; i < 20; i++) assertEquals((await call(f.deps, { action: "server.hello" })).status, 200);
  assertEquals((await call(f.deps, { action: "server.hello" })).status, 429);

  // Another server has its own bucket.
  assertEquals((await call(f.deps, { action: "server.hello" }, { key: KEY_OTHER })).status, 200);
});

Deno.test("rate limit: chat.send is 1/s burst 3 per actor", async () => {
  const f = makeFake({
    handlers: { pulse_act_chat_send: (args) => ok({ message: { body: (args.p_params as { body: string }).body } }) },
  });
  const send = (actor = ACTOR) => call(f.deps, { action: "chat.send", actor, params: { channelId: CHANNEL_ID, body: "hi" } });
  for (let i = 0; i < 3; i++) assertEquals((await send()).status, 200);
  const limited = await send();
  assertEquals(limited.status, 429);
  assertEquals(limited.body.error, "rate_limited");
  assertEquals((await send({ ref: "char:OTHER", name: "Other" })).status, 200, "other actors are unaffected");
  f.advance(1_000);
  assertEquals((await send()).status, 200);
  assertEquals((await send()).status, 429);
  assertEquals(f.calls("pulse_act_chat_send").length, 5);
});

Deno.test("TokenBuckets refill, cap at burst and evict least recently used keys", () => {
  const buckets = new TokenBuckets(2, 4, 2);
  for (let i = 0; i < 4; i++) assert(buckets.take("a", 0).allowed);
  const denied = buckets.take("a", 0);
  assertEquals(denied.allowed, false);
  assertEquals(denied.retryAfterMs, 500);
  assert(buckets.take("a", 500).allowed);
  assertEquals(buckets.take("a", 500).allowed, false);
  buckets.take("b", 600);
  buckets.take("c", 700);
  assertEquals(buckets.size, 2);
  assert(buckets.take("a", 700).allowed, "evicted key starts with a full bucket");
});

// ---------------------------------------------------------------------------------------------
// Validation

async function expectError(f: ReturnType<typeof makeFake>, action: string, params: unknown, code: string, status: number) {
  const res = await call(f.deps, { action, actor: ACTOR, params });
  assertEquals(res.body.ok, false, `${action} ${JSON.stringify(params)}`);
  assertEquals(res.body.error, code, `${action}: ${res.body.message}`);
  assertEquals(res.status, status, `${action} status`);
  assertEquals(typeof res.body.message, "string");
  return res;
}

Deno.test("validation: chat.send uses settings.chatMaxLength (cached 30 s via server.hello with null actor)", async () => {
  const f = makeFake({
    settings: { chatMaxLength: 10, imageHosts: [] },
    handlers: { pulse_act_chat_send: () => ok({ message: {} }) },
  });
  const long = await expectError(f, "chat.send", { channelId: CHANNEL_ID, body: "x".repeat(11) }, "too_long", 200);
  assertStringIncludes(String(long.body.message), "10");
  await expectError(f, "chat.send", { channelId: CHANNEL_ID, body: "   " }, "empty", 200);
  await expectError(f, "chat.send", { channelId: "not-a-uuid", body: "hello" }, "bad_request", 400);
  await expectError(f, "chat.send", { channelId: CHANNEL_ID, body: 42 }, "bad_request", 400);

  const hello = f.calls("pulse_act_server_hello");
  assertEquals(hello.length, 1, "settings fetched once and cached");
  assertEquals(hello[0].args, { p_server: SERVER_ID, p_actor: null, p_params: {} });

  const accepted = await call(f.deps, { action: "chat.send", actor: ACTOR, params: { channelId: CHANNEL_ID, body: " 0123456789 " } });
  assertEquals(accepted.status, 200);
  assertEquals((f.calls("pulse_act_chat_send")[0].args.p_params as { body: string }).body, "0123456789");

  f.advance(30_001);
  await call(f.deps, { action: "chat.send", actor: ACTOR, params: { channelId: CHANNEL_ID, body: "again" } });
  assertEquals(f.calls("pulse_act_server_hello").length, 2, "settings refreshed after 30 s");
});

Deno.test("validation: chat length is capped at 500 even if settings allow more", async () => {
  const f = makeFake({ settings: { chatMaxLength: 5000, imageHosts: [] } });
  await expectError(f, "chat.send", { channelId: CHANNEL_ID, body: "y".repeat(501) }, "too_long", 200);
});

Deno.test("validation: account.update handles, images, panels, socials, tags, accent", async () => {
  const f = makeFake({ handlers: { pulse_act_account_update: (args) => ok({ account: args.p_params as Json }) } });
  await expectError(f, "account.update", { handle: "ab" }, "handle_invalid", 200);
  await expectError(f, "account.update", { handle: "bad handle!" }, "handle_invalid", 200);
  await expectError(f, "account.update", { avatar: "https://evil.example.com/a.png" }, "bad_image_host", 200);
  await expectError(f, "account.update", { avatar: "http://i.imgur.com/a.png" }, "bad_image_host", 200);
  await expectError(f, "account.update", { bio: "b".repeat(401) }, "too_long", 200);
  await expectError(f, "account.update", { accent: "teal" }, "bad_request", 400);
  await expectError(f, "account.update", { tags: ["ok", "NOT_ALLOWED!"] }, "bad_request", 400);
  await expectError(f, "account.update", { tags: ["a", "b", "c", "d", "e", "f", "g"] }, "bad_request", 400);
  await expectError(f, "account.update", { panels: Array.from({ length: 7 }, () => ({ title: "t", body: "b" })) }, "bad_request", 400);
  await expectError(f, "account.update", { panels: [{ title: "t", body: "p".repeat(601) }] }, "too_long", 200);
  const socials: Record<string, string> = {};
  for (let i = 0; i < 9; i++) socials[`site${i}`] = "x";
  await expectError(f, "account.update", { socials }, "bad_request", 400);
  await expectError(f, "account.update", { socials: { twitter: "t".repeat(81) } }, "too_long", 200);
  await expectError(f, "account.update", {}, "bad_request", 400);

  const good = await call(f.deps, {
    action: "account.update",
    actor: ACTOR,
    params: {
      handle: "Tlay_Jones",
      avatar: `${PUBLIC_BASE}/avatars/x/1.jpg`,
      banner: "https://cdn.discordapp.net/b.png",
      accent: "#08AFA2",
      tags: ["Racing", "racing", "late night"],
      socials: { Twitter: "@tlay", youtube: "" },
      panels: [{ title: "About", body: "Line one\r\n\r\n\r\n\r\nLine two", image: "https://i.imgur.com/p.png" }],
      pointsIcon: "fa-bolt",
      unknown: true,
    },
  });
  assertEquals(good.status, 200);
  assertEquals(f.calls("pulse_act_account_update")[0].args.p_params, {
    handle: "Tlay_Jones",
    avatar: `${PUBLIC_BASE}/avatars/x/1.jpg`,
    banner: "https://cdn.discordapp.net/b.png",
    accent: "#08afa2",
    socials: { twitter: "@tlay" },
    panels: [{ title: "About", body: "Line one\n\nLine two", image: "https://i.imgur.com/p.png" }],
    tags: ["racing", "late night"],
    pointsIcon: "bolt",
  });

  const cleared = await call(f.deps, { action: "account.update", actor: ACTOR, params: { avatar: null, banner: "" } });
  assertEquals(cleared.status, 200);
  assertEquals(f.calls("pulse_act_account_update")[1].args.p_params, { avatar: null, banner: null });
});

Deno.test("validation: economy, polls, streams and uploads enforce ranges and enums", async () => {
  const f = makeFake();
  await expectError(f, "sparks.cheer", { channelId: CHANNEL_ID, amount: 0 }, "bad_request", 400);
  await expectError(f, "sparks.cheer", { channelId: CHANNEL_ID, amount: 1_000_001 }, "bad_request", 400);
  await expectError(f, "sparks.cheer", { channelId: CHANNEL_ID, amount: 1.5 }, "bad_request", 400);
  await expectError(f, "sub.buy", { channelId: CHANNEL_ID, tier: 4 }, "bad_request", 400);
  await expectError(f, "sub.gift", { channelId: CHANNEL_ID, tier: 1, count: 21 }, "bad_request", 400);
  await expectError(f, "sub.gift", { channelId: CHANNEL_ID, tier: 1, count: 0 }, "bad_request", 400);
  await expectError(f, "cashout.request", { amount: 10_000_001, mode: "all" }, "bad_request", 400);
  await expectError(f, "cashout.request", { amount: 100, mode: "everything" }, "bad_request", 400);
  await expectError(f, "sparks.credit", { amount: 0, reason: "purchase" }, "bad_request", 400);
  await expectError(f, "sparks.credit", { amount: 10, reason: "gift" }, "bad_request", 400);
  await expectError(f, "poll.create", { question: "Q?", options: ["only one"], duration: 60 }, "bad_request", 400);
  await expectError(f, "poll.create", { question: "Q?", options: ["1", "2", "3", "4", "5", "6"], duration: 60 }, "bad_request", 400);
  await expectError(f, "poll.create", { question: "Q?", options: ["a", "b"], duration: 29 }, "bad_request", 400);
  await expectError(f, "poll.create", { question: "Q?", options: ["a", "o".repeat(61)], duration: 60 }, "bad_request", 400);
  await expectError(f, "stream.start", { title: "t".repeat(121), category: "music" }, "title_invalid", 200);
  await expectError(f, "stream.start", { title: "   ", category: "music" }, "title_invalid", 200);
  await expectError(f, "stream.start", { title: "Live", category: "music", scene: "drone" }, "bad_request", 400);
  await expectError(f, "media.upload", { kind: "thumbnail", contentType: "image/jpeg" }, "bad_request", 400);
  await expectError(f, "media.upload", { kind: "avatar", contentType: "image/gif" }, "bad_request", 400);
  await expectError(f, "report.create", { channelId: CHANNEL_ID, reason: "meh" }, "bad_request", 400);
  await expectError(f, "dash.overview", { range: 14 }, "bad_request", 400);
  await expectError(f, "channel.get", {}, "bad_request", 400);
  await expectError(f, "follow.set", { channelId: CHANNEL_ID }, "bad_request", 400);
  assertEquals(f.rpcCalls.filter((c) => c.fn.startsWith("pulse_act_") && c.fn !== "pulse_act_server_hello").length, 0);
});

Deno.test("validation: stream.start defaults are filled before SQL", async () => {
  const f = makeFake({ handlers: { pulse_act_stream_start: () => ok({ stream: { id: STREAM_ID } }) } });
  const res = await call(f.deps, { action: "stream.start", actor: ACTOR, params: { title: "  Night shift  ", category: "police" } });
  assertEquals(res.status, 200);
  assertEquals(f.calls("pulse_act_stream_start")[0].args.p_params, {
    title: "Night shift",
    category: "police",
    tags: [],
    language: "en",
    mature: false,
    scene: "gameplay",
    vertical: false,
    quality: { width: 1280, height: 720, fps: 30, tier: 0 },
    micTier: 0,
  });
});

Deno.test("hostAllowed matches exact hosts and wildcard subdomains only", () => {
  assert(hostAllowed("i.imgur.com", ["i.imgur.com"]));
  assert(hostAllowed("media.discordapp.net", ["*.discordapp.net"]));
  assert(hostAllowed("a.b.example.com", [".example.com"]));
  assertEquals(hostAllowed("discordapp.net.evil.com", ["*.discordapp.net"]), false);
  assertEquals(hostAllowed("evilimgur.com", ["imgur.com"]), false);
});

// ---------------------------------------------------------------------------------------------
// fx execution

Deno.test("fx: stream.start runs createRoom → token → broadcast and merges data.livekit", async () => {
  const room = `pulse_${STREAM_ID}`;
  const f = makeFake({
    handlers: {
      pulse_act_stream_start: () =>
        ok({ stream: { id: STREAM_ID, title: "Live" } }, {
          deleteRoom: "pulse_old",
          broadcast: [{ room: "pulse_old", topic: "event", payload: { type: "stream_end", data: { reason: "replaced" } } }],
          token: { room, identity: `ch_${CHANNEL_ID}`, name: "Tlay Jones", publish: true, ttl: 43_200 },
          createRoom: { name: room, emptyTimeout: 600, maxParticipants: 0 },
        }),
    },
  });
  const res = await call(f.deps, { action: "stream.start", actor: ACTOR, params: { title: "Live", category: "music" } });
  assertEquals(res.status, 200);
  assertEquals(res.body.ok, true);
  const data = res.body.data as Record<string, unknown>;
  assertEquals(data.stream, { id: STREAM_ID, title: "Live" });
  assertEquals(data.livekit, { url: "wss://live.example.com", token: `token-for-ch_${CHANNEL_ID}` });
  assertEquals(f.lk.map((c) => c.op), ["createRoom", "token", "sendData", "deleteRoom"]);
  assertEquals(f.lk[0].args[0], { name: room, emptyTimeout: 600, maxParticipants: 0 });
  assertEquals(f.lk[1].args[0], { room, identity: `ch_${CHANNEL_ID}`, name: "Tlay Jones", publish: true, ttl: 43_200 });
  assertEquals(f.lk[3].args[0], "pulse_old");
  assert(!("fx" in res.body));
});

Deno.test("fx: media.upload passes _publicBase and merges uploadUrl/method/headers/publicUrl", async () => {
  const f = makeFake({
    handlers: {
      pulse_act_media_upload: (args) => {
        const params = args.p_params as Record<string, unknown>;
        assertEquals(params._publicBase, PUBLIC_BASE);
        return ok({ path: "thumbs/x.jpg", publicUrl: `${PUBLIC_BASE}/thumbs/${STREAM_ID}.jpg?v=123` }, {
          upload: { bucket: "pulse-media", path: `thumbs/${STREAM_ID}.jpg`, contentType: "image/jpeg", upsert: true },
        });
      },
    },
  });
  const res = await call(f.deps, {
    action: "media.upload",
    actor: ACTOR,
    params: { kind: "thumbnail", contentType: "image/jpeg", streamId: STREAM_ID.toUpperCase(), _publicBase: "https://evil" },
  });
  assertEquals(res.status, 200);
  const data = res.body.data as Record<string, unknown>;
  assertEquals(data.uploadUrl, `https://proj.supabase.co/storage/v1/object/upload/sign/pulse-media/thumbs/${STREAM_ID}.jpg?token=signed`);
  assertEquals(data.method, "PUT");
  assertEquals(data.headers, { "content-type": "image/jpeg", "x-upsert": "true", "cache-control": "max-age=3600" });
  assertEquals(data.publicUrl, `${PUBLIC_BASE}/thumbs/${STREAM_ID}.jpg?v=123`, "SQL publicUrl is kept");
  assertEquals(f.lk[0], { op: "signedUpload", args: ["pulse-media", `thumbs/${STREAM_ID}.jpg`, "image/jpeg", true] });
  assertEquals((f.calls("pulse_act_media_upload")[0].args.p_params as Record<string, unknown>).streamId, STREAM_ID);
});

Deno.test("fx: upload without SQL publicUrl falls back to storage.publicUrl (+?v= when upsert)", async () => {
  const f = makeFake({
    handlers: {
      pulse_act_media_upload: () =>
        ok({}, { upload: { bucket: "pulse-media", path: "avatars/a/b.jpg", contentType: "image/png", upsert: false } }),
    },
  });
  const res = await call(f.deps, { action: "media.upload", actor: ACTOR, params: { kind: "avatar", contentType: "image/png" } });
  const data = res.body.data as Record<string, unknown>;
  assertEquals(data.publicUrl, "https://proj.supabase.co/storage/v1/object/public/pulse-media/avatars/a/b.jpg");
  assertEquals((data.headers as Record<string, string>)["x-upsert"], "false");
});

Deno.test("fx: chat broadcasts go out in order; failures are logged, not fatal", async () => {
  const room = `pulse_${STREAM_ID}`;
  const message = { id: "1", kind: "chat", body: "hi" };
  const f = makeFake({
    failSend: true,
    failDelete: true,
    handlers: {
      pulse_act_chat_send: () =>
        ok({ message }, {
          broadcast: [
            { room, topic: "chat", payload: message },
            { room, topic: "event", payload: { type: "goal", data: { goals: [] } } },
            { topic: "event" },
          ],
          deleteRoom: "pulse_gone",
        }),
    },
  });
  const res = await call(f.deps, { action: "chat.send", actor: ACTOR, params: { channelId: CHANNEL_ID, body: "hi" } });
  assertEquals(res.status, 200);
  assertEquals(res.body, { ok: true, data: { message } });
  assertEquals(f.lk.map((c) => [c.op, ...c.args.slice(0, 2)]), [
    ["sendData", room, "chat"],
    ["sendData", room, "event"],
    ["deleteRoom", "pulse_gone"],
  ]);
  assertEquals(f.lk[0].args[2], message);
  assert(f.logs.some((l) => l.includes("broadcast to") && l.includes("failed")));
  assert(f.logs.some((l) => l.includes("malformed fx.broadcast")));
  assert(f.logs.some((l) => l.includes("deleteRoom pulse_gone failed")));
});

Deno.test("fx: createRoom failure is a 500 with a safe message", async () => {
  const f = makeFake({
    failCreate: true,
    handlers: {
      pulse_act_stream_start: () =>
        ok({ stream: {} }, {
          createRoom: { name: "pulse_x" },
          token: { room: "pulse_x", identity: "ch_x", publish: true, ttl: 60 },
        }),
    },
  });
  const res = await call(f.deps, { action: "stream.start", actor: ACTOR, params: { title: "Live", category: "music" } });
  assertEquals(res.status, 500);
  assertEquals(res.body.error, "internal");
  assertStringIncludes(String(res.body.message), "Streaming service unavailable");
  assertEquals(f.lk.map((c) => c.op), ["createRoom"], "token is not minted after a failed createRoom");
});

// ---------------------------------------------------------------------------------------------
// Error mapping

Deno.test("errors: SQL app errors pass through with HTTP 200 (extra fields kept, fx stripped)", async () => {
  const f = makeFake({
    handlers: {
      pulse_act_chat_send: () => ({
        ok: false,
        error: "slow",
        message: "Slow mode is on",
        wait: 4,
        fx: { broadcast: [{ room: "pulse_r", topic: "event", payload: { type: "chat_clear", data: {} } }] },
      }),
      pulse_act_sparks_cheer: () => {
        throw new RpcError("pulse_act_sparks_cheer", "P0001", "insufficient_sparks", "You need 90 more Sparks", null);
      },
      pulse_act_sub_buy: () => ({ ok: false }),
    },
  });
  const slow = await call(f.deps, { action: "chat.send", actor: ACTOR, params: { channelId: CHANNEL_ID, body: "hello" } });
  assertEquals(slow.status, 200);
  assertEquals(slow.body, { ok: false, error: "slow", message: "Slow mode is on", wait: 4 });
  assertEquals(f.lk.map((c) => c.op), ["sendData"], "side-effect fx of failed envelopes still run");

  const cheer = await call(f.deps, { action: "sparks.cheer", actor: ACTOR, params: { channelId: CHANNEL_ID, amount: 100, message: "" } });
  assertEquals(cheer.status, 200);
  assertEquals(cheer.body, { ok: false, error: "insufficient_sparks", message: "You need 90 more Sparks" });
  assertEquals(f.calls("pulse_act_sparks_cheer")[0].args.p_params, { channelId: CHANNEL_ID, amount: 100 });

  const bare = await call(f.deps, { action: "sub.buy", actor: ACTOR, params: { channelId: CHANNEL_ID, tier: 1 } });
  assertEquals(bare.status, 200);
  assertEquals(bare.body.error, "internal");
});

Deno.test("errors: exceptions are 500 internal and never leak details unless PULSE_DEBUG", async () => {
  const secret = "service_role_secret_value";
  const handlers = {
    pulse_act_wallet_get: () => {
      throw new RpcError("pulse_act_wallet_get", "42883", `function failed near ${secret}`, null, null);
    },
    pulse_act_subs_mine: () => "not an envelope",
  };
  const f = makeFake({ handlers });
  const res = await call(f.deps, { action: "wallet.get", actor: ACTOR });
  assertEquals(res.status, 500);
  assertEquals(res.body.ok, false);
  assertEquals(res.body.error, "internal");
  assertMatch(String(res.body.message), /^Internal error \(ref [0-9a-f]{8}\)$/);
  assert(!JSON.stringify(res.body).includes(secret));
  assert(f.logs.some((l) => l.includes("RpcError(pulse_act_wallet_get, 42883)")));
  assert(!f.logs.some((l) => l.includes(secret)), "no details in logs without debug");

  const bad = await call(f.deps, { action: "subs.mine", actor: ACTOR });
  assertEquals(bad.status, 500);

  const missing = await call(f.deps, { action: "browse.following", actor: ACTOR });
  assertEquals(missing.status, 500, "missing SQL function is an internal error");

  const dbg = makeFake({ handlers, debug: true });
  await call(dbg.deps, { action: "wallet.get", actor: ACTOR });
  assert(dbg.logs.some((l) => l.includes(secret)), "debug logs include details");
});

Deno.test("server.hello primes the settings cache", async () => {
  const f = makeFake({
    handlers: {
      pulse_act_server_hello: () => ok({ server: {}, settings: { chatMaxLength: 5, imageHosts: [] } }),
      pulse_act_chat_send: () => ok({ message: {} }),
    },
  });
  assertEquals((await call(f.deps, { action: "server.hello", actor: ACTOR })).status, 200);
  assertEquals(f.calls("pulse_act_server_hello")[0].args.p_actor, null);
  await expectError(f, "chat.send", { channelId: CHANNEL_ID, body: "123456" }, "too_long", 200);
  assertEquals(f.calls("pulse_act_server_hello").length, 1);
});

Deno.test("settings fetch failure falls back to defaults without failing the request", async () => {
  const f = makeFake({
    handlers: {
      pulse_act_server_hello: () => {
        throw new RpcError("pulse_act_server_hello", "08006", "connection failure", null, null);
      },
      pulse_act_chat_send: () => ok({ message: {} }),
    },
  });
  const res = await call(f.deps, { action: "chat.send", actor: ACTOR, params: { channelId: CHANNEL_ID, body: "fine" } });
  assertEquals(res.status, 200);
  await expectError(f, "chat.send", { channelId: CHANNEL_ID, body: "z".repeat(301) }, "too_long", 200);
  assert(f.logs.some((l) => l.includes("settings refresh failed")));
  assertEquals(f.calls("pulse_act_server_hello").length, 1, "retry is delayed after a failure");
});

// ---------------------------------------------------------------------------------------------
// LiveKit JWT + Twirp

const LK_KEY = "APIkey123";
const LK_SECRET = "s3cr3t-livekit-secret-value-0123456789";

function b64urlDecode(part: string): Uint8Array<ArrayBuffer> {
  const b64 = part.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (part.length % 4)) % 4);
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

async function verifyJwt(token: string, secret: string) {
  const parts = token.split(".");
  assertEquals(parts.length, 3);
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, [
    "verify",
  ]);
  const valid = await crypto.subtle.verify(
    "HMAC",
    key,
    b64urlDecode(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
  const header = JSON.parse(new TextDecoder().decode(b64urlDecode(parts[0])));
  const claims = JSON.parse(new TextDecoder().decode(b64urlDecode(parts[1])));
  return { valid, header, claims };
}

Deno.test("livekit: participant token is a valid HS256 JWT with the SPEC grants", async () => {
  const now = new Date(START);
  const client = new LiveKitClient({ url: "wss://live.example.com", apiKey: LK_KEY, apiSecret: LK_SECRET, now: () => now });
  const token = await client.token({
    room: "pulse_r1",
    identity: "v_acc_ab12",
    name: "Viewer",
    publish: false,
    ttl: 21_600,
    metadata: { accountId: "acc", badges: ["sub:1:3"] },
  });
  const { valid, header, claims } = await verifyJwt(token, LK_SECRET);
  assert(valid, "signature verifies with the API secret");
  assertEquals(header, { alg: "HS256", typ: "JWT" });
  const nowSec = Math.floor(START / 1000);
  assertEquals(claims.iss, LK_KEY);
  assertEquals(claims.sub, "v_acc_ab12");
  assertEquals(claims.name, "Viewer");
  assertEquals(claims.nbf, nowSec - 10);
  assertEquals(claims.exp, nowSec + 21_600);
  assertMatch(claims.jti, /^[0-9a-f-]{36}$/);
  assertEquals(claims.metadata, JSON.stringify({ accountId: "acc", badges: ["sub:1:3"] }));
  assertEquals(claims.video, {
    room: "pulse_r1",
    roomJoin: true,
    canSubscribe: true,
    canPublish: false,
    canPublishData: false,
    canUpdateOwnMetadata: false,
    hidden: false,
  });
  assertEquals((await verifyJwt(token, "wrong-secret")).valid, false);

  const publisher = await verifyJwt(
    await client.token({ room: "pulse_r1", identity: "ch_1", publish: true, ttl: 43_200 }),
    LK_SECRET,
  );
  assertEquals(publisher.claims.video.canPublish, true);
  assertEquals(publisher.claims.name, "ch_1");
  assertEquals(publisher.claims.exp - publisher.claims.nbf, 43_210);
  assert(!("metadata" in publisher.claims));
});

Deno.test("livekit: admin token carries room admin grants and a 600 s ttl", async () => {
  const client = new LiveKitClient({ url: "wss://live.example.com", apiKey: LK_KEY, apiSecret: LK_SECRET, now: () => new Date(START) });
  const { valid, claims } = await verifyJwt(await client.adminToken("pulse_r1"), LK_SECRET);
  assert(valid);
  assertEquals(claims.video, { roomCreate: true, roomAdmin: true, roomList: true, room: "pulse_r1" });
  assertEquals(claims.exp, Math.floor(START / 1000) + 600);
  assert(!("sub" in claims));
});

interface Captured {
  url: string;
  auth: string;
  body: Record<string, unknown>;
}

function fakeFetch(responses: Array<{ status: number; body: unknown }>, captured: Captured[]): typeof fetch {
  return (input, init) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
    const headers = new Headers(init?.headers);
    captured.push({ url, auth: headers.get("authorization") ?? "", body: JSON.parse(String(init?.body ?? "{}")) });
    const next = responses.shift() ?? { status: 200, body: {} };
    return Promise.resolve(new Response(JSON.stringify(next.body), { status: next.status }));
  };
}

Deno.test("livekit: Twirp requests use the https base, admin bearer tokens and proto JSON fields", async () => {
  const captured: Captured[] = [];
  const client = new LiveKitClient({
    url: "wss://live.example.com/",
    apiKey: LK_KEY,
    apiSecret: LK_SECRET,
    fetch: fakeFetch([
      { status: 200, body: { name: "pulse_r1" } },
      { status: 200, body: {} },
      { status: 404, body: { code: "not_found", msg: "room not found" } },
      {
        status: 200,
        body: { participants: [{ sid: "PA_1", identity: "ch_1", name: "Tlay", state: "ACTIVE", joined_at: "1700000000", tracks: [{}] }] },
      },
      { status: 500, body: { code: "internal", msg: "kaboom" } },
    ], captured),
  });

  await client.createRoom({ name: "pulse_r1", emptyTimeout: 300, maxParticipants: 0 });
  const payload = { id: "9", kind: "chat", body: "héllo ✓" };
  await client.sendData("pulse_r1", "chat", payload);
  await client.deleteRoom("pulse_r1"); // 404 not_found counts as deleted
  const participants = await client.listParticipants("pulse_r1");
  await assertRejects(() => client.sendData("pulse_r1", "event", {}), LiveKitError);

  assertEquals(captured.map((c) => c.url), [
    "https://live.example.com/twirp/livekit.RoomService/CreateRoom",
    "https://live.example.com/twirp/livekit.RoomService/SendData",
    "https://live.example.com/twirp/livekit.RoomService/DeleteRoom",
    "https://live.example.com/twirp/livekit.RoomService/ListParticipants",
    "https://live.example.com/twirp/livekit.RoomService/SendData",
  ]);
  assertEquals(captured[0].body, { name: "pulse_r1", empty_timeout: 300, max_participants: 0 });

  const send = captured[1];
  assertEquals(send.body.room, "pulse_r1");
  assertEquals(send.body.kind, "RELIABLE");
  assertEquals(send.body.topic, "chat");
  const decoded = new TextDecoder().decode(Uint8Array.from(atob(String(send.body.data)), (c) => c.charCodeAt(0)));
  assertEquals(JSON.parse(decoded), payload);
  assertEquals(atob(String(send.body.nonce)).length, 16);

  assertMatch(send.auth, /^Bearer [\w-]+\.[\w-]+\.[\w-]+$/);
  const admin = await verifyJwt(send.auth.slice(7), LK_SECRET);
  assert(admin.valid);
  assertEquals(admin.claims.video.room, "pulse_r1");
  assertEquals(admin.claims.video.roomAdmin, true);

  assertEquals(captured[2].body, { room: "pulse_r1" });
  assertEquals(participants, [{
    sid: "PA_1",
    identity: "ch_1",
    name: "Tlay",
    state: "ACTIVE",
    metadata: "",
    joinedAt: 1_700_000_000,
    isPublisher: true,
  }]);
});

Deno.test("livekit: request timeouts surface as LiveKitError", async () => {
  const hanging: typeof fetch = (_input, init) =>
    new Promise((_resolve, reject) => {
      init?.signal?.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")));
    });
  const client = new LiveKitClient({ url: "ws://localhost:7880", apiKey: LK_KEY, apiSecret: LK_SECRET, fetch: hanging, timeoutMs: 20 });
  const err = await assertRejects(() => client.createRoom({ name: "r", emptyTimeout: 1, maxParticipants: 0 }), LiveKitError);
  assertStringIncludes(err.message, "timed out");
  assertEquals(twirpBase("ws://localhost:7880/"), "http://localhost:7880");
  assertEquals(twirpBase("wss://x.livekit.cloud"), "https://x.livekit.cloud");
});

// ---------------------------------------------------------------------------------------------
// Storage

function fakeStorageClient(log: unknown[], fail = false): StorageClientLike {
  return {
    storage: {
      from: (bucket: string) => ({
        createSignedUploadUrl: (path: string, options?: { upsert: boolean }) => {
          log.push([bucket, path, options]);
          if (fail) return Promise.resolve({ data: null, error: { message: "Bucket not found" } });
          return Promise.resolve({
            data: {
              signedUrl: `http://kong:8000/storage/v1/object/upload/sign/${bucket}/${path}?token=abc`,
              token: "abc",
              path,
            },
            error: null,
          });
        },
      }),
    },
  };
}

Deno.test("storage: signed uploads return the raw PUT headers storage-js would send", async () => {
  const log: unknown[] = [];
  const storage = createStorage(fakeStorageClient(log), "https://proj.supabase.co/");
  assertEquals(storage.publicBase, PUBLIC_BASE);
  assertEquals(storage.publicUrl("pulse-media", "avatars/a b/c.jpg"), `${PUBLIC_BASE}/avatars/a%20b/c.jpg`);
  const signed = await storage.signedUpload("pulse-media", "thumbs/s.jpg", "image/webp", true);
  assertEquals(log, [["pulse-media", "thumbs/s.jpg", { upsert: true }]]);
  assertEquals(signed.uploadUrl, "http://kong:8000/storage/v1/object/upload/sign/pulse-media/thumbs/s.jpg?token=abc");
  assertEquals(signed.headers, { "content-type": "image/webp", "x-upsert": "true", "cache-control": "max-age=3600" });

  const local = createStorage(fakeStorageClient([]), "http://kong:8000", "http://127.0.0.1:54321");
  assertEquals(local.publicBase, "http://127.0.0.1:54321/storage/v1/object/public/pulse-media");
  const rewritten = await local.signedUpload("pulse-media", "a.jpg", "image/jpeg", false);
  assertEquals(rewritten.uploadUrl, "http://127.0.0.1:54321/storage/v1/object/upload/sign/pulse-media/a.jpg?token=abc");
  assertEquals(rewritten.headers["x-upsert"], "false");

  const failing = createStorage(fakeStorageClient([], true), "https://proj.supabase.co");
  await assertRejects(() => failing.signedUpload("pulse-media", "a.jpg", "image/jpeg", false), Error, "Bucket not found");
});

Deno.test("stateful caches are isolated per deps object", async () => {
  const a = makeFake();
  const b = makeFake();
  await call(a.deps, { action: "server.hello" });
  await call(b.deps, { action: "server.hello" });
  assertEquals(a.calls("pulse_server_by_key").length, 1);
  assertEquals(b.calls("pulse_server_by_key").length, 1);
  assertNotEquals(a.deps, b.deps);
});

Deno.test("validation: sub badges accept a Lua-style array keyed by tier", async () => {
  const f = makeFake({ handlers: { pulse_act_account_update: () => ok({ account: {} }) } });
  const badge = (name: string) => ({ name, icon: "fa-star", color: "#E5A50A" });
  const res = await call(f.deps, {
    action: "account.update",
    actor: ACTOR,
    params: { subBadges: [badge("One"), null, badge("Three")] },
  });
  assertEquals(res.status, 200);
  assertEquals(f.calls("pulse_act_account_update")[0].args.p_params, {
    subBadges: {
      "1": { name: "One", icon: "star", color: "#e5a50a" },
      "3": { name: "Three", icon: "star", color: "#e5a50a" },
    },
  });
  await expectError(f, "account.update", { subBadges: [badge("a"), badge("b"), badge("c"), badge("d")] }, "bad_request", 400);
});

// ---------------------------------------------------------------------------------------------
// Optional integration run against a real database with the Pulse migration applied:
//   PULSE_TEST_DATABASE_URL=postgres://postgres@localhost:54329/<db> deno test --allow-env --allow-net ...
// The gateway runs unchanged; only `rpc` is swapped for direct SQL calls and LiveKit/Storage stay fake.

const PG_URL = Deno.env.get("PULSE_TEST_DATABASE_URL");

Deno.test({
  name: "integration: gateway against Postgres (set PULSE_TEST_DATABASE_URL)",
  ignore: !PG_URL,
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const { default: postgres } = await import("npm:postgres@3.4.7");
    const sql = postgres(PG_URL ?? "", { max: 2, onnotice: () => {} });
    try {
      const fake = makeFake();
      const rpc: Deps["rpc"] = async (fn, args) => {
        if (!/^pulse_[a-z_]+$/.test(fn)) throw new Error(`refusing to call ${fn}`);
        if (fn === "pulse_server_by_key") {
          const rows = await sql.unsafe(`select row_to_json(t) as r from public.${fn}($1) t`, [String(args.p_key)]);
          return rows[0]?.r ?? null;
        }
        // postgres.js serialises parameters of a jsonb placeholder itself: pass objects as-is.
        const rows = await sql.unsafe(`select public.${fn}($1::uuid, $2::jsonb, $3::jsonb) as r`, [
          String(args.p_server),
          (args.p_actor ?? null) as never,
          args.p_params as never,
        ]);
        return rows[0].r;
      };
      const deps: Deps = { ...fake.deps, rpc };
      const slug = "itest-" + crypto.randomUUID().slice(0, 8);
      const [{ key }] = await sql`select public.pulse_register_server(${slug}, ${"Integration"}, ${"ITST"}) as key`;
      assertMatch(String(key), /^pk_[0-9a-f]{48}$/);

      const bad = await call(deps, { action: "server.hello" }, { key: "pk_" + "f".repeat(48) });
      assertEquals(bad.status, 401);

      const hello = await call(deps, { action: "server.hello" }, { key: String(key) });
      assertEquals(hello.status, 200, JSON.stringify(hello.body));
      const helloData = hello.body.data as { server: { slug: string }; settings: { chatMaxLength: number; categories: unknown[] } };
      assertEquals(helloData.server.slug, slug);
      assertEquals(typeof helloData.settings.chatMaxLength, "number");
      assert(Array.isArray(helloData.settings.categories));

      const actor = { ref: "char:" + crypto.randomUUID().slice(0, 8), name: "Integration Tester" };
      const created = await call(deps, { action: "account.me", actor, params: { create: true } }, { key: String(key) });
      assertEquals(created.status, 200, JSON.stringify(created.body));
      const account = (created.body.data as { account: { id: string; handle: string; ref: string } }).account;
      assertMatch(account.handle, /^[A-Za-z0-9_]{3,20}$/);
      assertEquals(account.ref, actor.ref);

      const again = await call(deps, { action: "account.me", actor }, { key: String(key) });
      assertEquals((again.body.data as { account: { id: string } }).account.id, account.id);

      const offline = await call(deps, {
        action: "chat.send",
        actor,
        params: { channelId: account.id, body: "hello" },
      }, { key: String(key) });
      assertEquals(offline.status, 200);
      assertEquals(offline.body.ok, false);
      assertEquals(offline.body.error, "offline");

      const upload = await call(deps, {
        action: "media.upload",
        actor,
        params: { kind: "avatar", contentType: "image/jpeg" },
      }, { key: String(key) });
      assertEquals(upload.status, 200, JSON.stringify(upload.body));
      const uploadData = upload.body.data as { uploadUrl: string; method: string; publicUrl: string };
      assertEquals(uploadData.method, "PUT");
      assertStringIncludes(uploadData.uploadUrl, `/avatars/${account.id}/`);
      assert(uploadData.publicUrl.startsWith(`${PUBLIC_BASE}/avatars/${account.id}/`));
    } finally {
      await sql.end({ timeout: 5 });
    }
  },
});
