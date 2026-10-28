// pulse-api — the single Supabase Edge Function gateway between FiveM servers and the
// Pulse backend (SPEC §2 and §4).
//
//   POST  { action, actor?, params? }   header x-pulse-key: <server key>
//   GET   …/health                      → { ok: true }
//
// Flow: method → server key auth (cached) → per-server rate limit → body → action registry →
// actor → strict params validation → per-actor chat limit → `pulse_act_<action>` rpc →
// envelope fx (createRoom → token → upload → broadcast → deleteRoom) → `{ ok, data }`.

import { getAction, rpcName } from "./lib/actions.ts";
import { looksLikeKey, ServerKeyCache } from "./lib/auth.ts";
import { appErrorFromRpc, createSupabase, rpcFrom } from "./lib/db.ts";
import { ConfigError, describeError, FxError, HttpError } from "./lib/errors.ts";
import { executeFx } from "./lib/fx.ts";
import { LiveKitClient, LiveKitError } from "./lib/livekit.ts";
import { chatLimiter, serverLimiter, type TokenBuckets } from "./lib/ratelimit.ts";
import { DEFAULT_SETTINGS, SettingsCache } from "./lib/settings.ts";
import { createStorage, StorageFailure } from "./lib/storage.ts";
import { asObject, ValidationError, type ValidateContext } from "./lib/validate.ts";
import type { Actor, Deps, Json, JsonObject, LiveKitApi, Logger, ServerRecord, StorageApi } from "./lib/types.ts";

export type { Deps } from "./lib/types.ts";
export { ACTIONS } from "./lib/actions.ts";

const MAX_BODY_BYTES = 64 * 1024;
// deno-lint-ignore no-control-regex
const ACTOR_REF_RE = /^[^\s\u0000-\u001F\u007F]{3,128}$/u;
// deno-lint-ignore no-control-regex
const CONTROL_RUN_RE = /[\u0000-\u001F\u007F-\u009F]+/g;
const ACTOR_NAME_MAX = 64;
const JSON_TYPE_RE = /^application\/(?:[\w.+-]+\+)?json\s*(?:;|$)/i;

// ---------------------------------------------------------------------------------------------
// Per-deps memory (caches and limiters), so tests with separate fakes never share state.

interface GatewayState {
  auth: ServerKeyCache;
  settings: SettingsCache;
  servers: TokenBuckets;
  chat: TokenBuckets;
}

const states = new WeakMap<Deps, GatewayState>();

function stateFor(deps: Deps): GatewayState {
  let state = states.get(deps);
  if (!state) {
    state = {
      auth: new ServerKeyCache(),
      settings: new SettingsCache(),
      servers: serverLimiter(),
      chat: chatLimiter(),
    };
    states.set(deps, state);
  }
  return state;
}

const consoleLogger: Logger = (level, message) => {
  const line = `[pulse-api] ${message}`;
  if (level === "error") console.error(line);
  else if (level === "warn") console.warn(line);
  else console.log(line);
};

// ---------------------------------------------------------------------------------------------
// Responses

function json(status: number, body: unknown, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...headers },
  });
}

function internalError(err: unknown, action: string, log: Logger, debug: boolean): Response {
  const ref = crypto.randomUUID().slice(0, 8);
  let message = "Internal error";
  if (err instanceof LiveKitError) message = "Streaming service unavailable";
  else if (err instanceof StorageFailure) message = "Storage service unavailable";
  else if (err instanceof ConfigError) message = "Gateway is not configured";
  const stack = debug && err instanceof Error && err.stack ? `\n${err.stack}` : "";
  log("error", `internal ref=${ref} action=${action || "-"} ${describeError(err, debug)}${stack}`);
  return json(500, { ok: false, error: "internal", message: `${message} (ref ${ref})` });
}

function rateLimited(retryAfterMs: number, message: string): HttpError {
  const seconds = Math.max(1, Math.ceil(retryAfterMs / 1000));
  return new HttpError(429, "rate_limited", `${message}; retry in ${seconds}s`, { "retry-after": String(seconds) });
}

// ---------------------------------------------------------------------------------------------
// Request pieces

function isHealthPath(pathname: string): boolean {
  return pathname === "/health" || pathname.endsWith("/health");
}

async function authenticate(req: Request, deps: Deps, state: GatewayState): Promise<ServerRecord> {
  const key = (req.headers.get("x-pulse-key") ?? "").trim();
  if (!key) throw new HttpError(401, "unauthorized", "Missing x-pulse-key header");
  if (!looksLikeKey(key)) throw new HttpError(401, "unauthorized", "Invalid server key");
  const server = await state.auth.resolve(key, deps);
  if (!server) throw new HttpError(401, "unauthorized", "Invalid server key");
  if (!server.active) throw new HttpError(401, "unauthorized", "This server is disabled on the network");
  return server;
}

interface RequestBody {
  action: string;
  actor: unknown;
  params: JsonObject;
}

async function readBody(req: Request): Promise<RequestBody> {
  const type = req.headers.get("content-type");
  if (type && !JSON_TYPE_RE.test(type.trim())) {
    throw new HttpError(415, "bad_request", "Content-Type must be application/json");
  }
  const declared = Number(req.headers.get("content-length") ?? "0");
  if (declared > MAX_BODY_BYTES) throw new HttpError(413, "bad_request", "Request body is too large");
  const bytes = new Uint8Array(await req.arrayBuffer());
  if (bytes.byteLength > MAX_BODY_BYTES) throw new HttpError(413, "bad_request", "Request body is too large");

  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    throw new HttpError(400, "bad_request", "Request body must be valid JSON");
  }
  const body = asObject(parsed);
  if (!body || Array.isArray(parsed)) throw new HttpError(400, "bad_request", "Request body must be a JSON object");
  if (typeof body.action !== "string" || body.action === "") {
    throw new HttpError(400, "bad_request", "action is required");
  }
  const params = body.params === undefined || body.params === null ? {} : asObject(body.params);
  if (!params) throw new HttpError(400, "bad_request", "params must be an object");
  return { action: body.action, actor: body.actor, params: params as JsonObject };
}

function parseActor(raw: unknown, action: string): Actor {
  const actor = asObject(raw);
  if (!actor || Array.isArray(raw)) throw new HttpError(400, "bad_request", `actor is required for ${action}`);
  const ref = typeof actor.ref === "string" ? actor.ref.trim() : "";
  if (!ACTOR_REF_RE.test(ref)) {
    throw new HttpError(400, "bad_request", "actor.ref must be 3-128 characters without spaces");
  }
  if (actor.name !== undefined && actor.name !== null && typeof actor.name !== "string") {
    throw new HttpError(400, "bad_request", "actor.name must be a string");
  }
  const cleaned = (actor.name ?? "").normalize("NFC").replace(CONTROL_RUN_RE, " ").trim();
  const name = Array.from(cleaned).slice(0, ACTOR_NAME_MAX).join("").trim() || "Player";
  return { ref, name };
}

function originOf(url: string): string {
  try {
    return new URL(url).origin;
  } catch {
    return "";
  }
}

async function validationContext(
  needsSettings: boolean,
  server: ServerRecord,
  deps: Deps,
  state: GatewayState,
  log: Logger,
): Promise<ValidateContext> {
  const settings = needsSettings ? await state.settings.get(server.id, deps, log) : DEFAULT_SETTINGS;
  return {
    chatMaxLength: settings.chatMaxLength,
    imageHosts: settings.imageHosts,
    storageOrigin: originOf(deps.storage.publicBase),
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

async function respond(
  action: string,
  envelope: unknown,
  deps: Deps,
  state: GatewayState,
  log: Logger,
  debug: boolean,
): Promise<Response> {
  if (!isRecord(envelope) || typeof envelope.ok !== "boolean") {
    throw new FxError(`${rpcName(action)} did not return an envelope`);
  }

  if (envelope.ok === false) {
    try {
      await executeFx(envelope.fx, {}, deps, log, { sideEffectsOnly: true, debug });
    } catch (err) {
      log("warn", `fx of failed ${action} skipped: ${describeError(err, debug)}`);
    }
    const body: JsonObject = {};
    for (const [key, value] of Object.entries(envelope)) {
      if (key !== "fx") body[key] = value as Json;
    }
    const code = typeof envelope.error === "string" && envelope.error ? envelope.error : "internal";
    body.ok = false;
    body.error = code;
    body.message = typeof envelope.message === "string" ? envelope.message : code.replaceAll("_", " ");
    return json(200, body);
  }

  const rawData = envelope.data ?? {};
  if (!isRecord(rawData)) throw new FxError(`${rpcName(action)} returned non-object data`);
  const data = await executeFx(envelope.fx, rawData as JsonObject, deps, log, { debug });
  if (action === "server.hello") state.settings.prime(data.settings, deps.now().getTime());
  return json(200, { ok: true, data });
}

// ---------------------------------------------------------------------------------------------
// Handler

export async function handle(req: Request, deps: Deps): Promise<Response> {
  const log = deps.log ?? consoleLogger;
  const debug = deps.debug === true;
  let action = "";
  try {
    if (req.method === "GET" && isHealthPath(new URL(req.url).pathname)) return json(200, { ok: true });
    if (req.method !== "POST") {
      throw new HttpError(405, "bad_request", "Use POST with a JSON body", { allow: "POST" });
    }

    const state = stateFor(deps);
    const server = await authenticate(req, deps, state);

    const serverLimit = state.servers.take(server.id, deps.now().getTime());
    if (!serverLimit.allowed) throw rateLimited(serverLimit.retryAfterMs, "Too many requests from this server");

    const body = await readBody(req);
    const def = getAction(body.action);
    if (!def) throw new HttpError(400, "bad_request", `Unknown action "${body.action.slice(0, 64)}"`);
    action = body.action;

    const actor = def.kind === "server" ? null : parseActor(body.actor, action);
    const ctx = await validationContext(def.needsSettings === true, server, deps, state, log);
    const params = def.validate(body.params, ctx);
    if (params instanceof ValidationError) {
      return json(params.error === "bad_request" ? 400 : 200, params.toJSON());
    }

    if (action === "chat.send" && actor) {
      const chatLimit = state.chat.take(`${server.id}\n${actor.ref}`, deps.now().getTime());
      if (!chatLimit.allowed) throw rateLimited(chatLimit.retryAfterMs, "You are sending messages too fast");
    }
    if (action === "media.upload") params._publicBase = deps.storage.publicBase;

    let envelope: unknown;
    try {
      envelope = await deps.rpc(rpcName(action), { p_server: server.id, p_actor: actor, p_params: params });
    } catch (err) {
      const appError = appErrorFromRpc(err);
      if (appError) return json(200, { ok: false, ...appError });
      throw err;
    }
    return await respond(action, envelope, deps, state, log, debug);
  } catch (err) {
    if (err instanceof HttpError) {
      return json(err.status, { ok: false, error: err.code, message: err.message }, err.headers);
    }
    return internalError(err, action, log, debug);
  }
}

// ---------------------------------------------------------------------------------------------
// Production wiring

function env(name: string): string {
  return (Deno.env.get(name) ?? "").trim();
}

function unconfiguredStorage(error: ConfigError): StorageApi {
  return {
    publicBase: "",
    signedUpload: () => Promise.reject(error),
    publicUrl: () => {
      throw error;
    },
  };
}

function unconfiguredLiveKit(error: ConfigError, url: string): LiveKitApi {
  const fail = () => Promise.reject(error);
  return { url, token: fail, createRoom: fail, deleteRoom: fail, sendData: fail, listParticipants: fail };
}

let defaultDepsInstance: Deps | null = null;

/**
 * Real dependencies from the function's environment (memoised so caches and limiters persist
 * across requests in one worker). Missing variables do not throw here: the affected service
 * fails with a ConfigError (→ 500 "Gateway is not configured") and the names are logged once.
 */
export function defaultDeps(): Deps {
  if (defaultDepsInstance) return defaultDepsInstance;
  const log = consoleLogger;
  const debug = env("PULSE_DEBUG") === "1";

  const supabaseUrl = env("SUPABASE_URL");
  const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY");
  const dbMissing = [["SUPABASE_URL", supabaseUrl], ["SUPABASE_SERVICE_ROLE_KEY", serviceKey]]
    .filter(([, value]) => !value)
    .map(([name]) => name);

  let rpc: Deps["rpc"];
  let storage: StorageApi;
  if (dbMissing.length === 0) {
    const client = createSupabase(supabaseUrl, serviceKey);
    rpc = rpcFrom((fn, args) => client.rpc(fn, args));
    try {
      storage = createStorage(client, supabaseUrl, env("PULSE_PUBLIC_URL") || undefined);
    } catch {
      const error = new ConfigError(["PULSE_PUBLIC_URL (invalid URL)"]);
      log("error", error.message);
      storage = unconfiguredStorage(error);
    }
  } else {
    const error = new ConfigError(dbMissing);
    log("error", error.message);
    rpc = () => Promise.reject(error);
    storage = unconfiguredStorage(error);
  }

  const livekitUrl = env("LIVEKIT_URL");
  const livekitKey = env("LIVEKIT_API_KEY");
  const livekitSecret = env("LIVEKIT_API_SECRET");
  const lkMissing = [["LIVEKIT_URL", livekitUrl], ["LIVEKIT_API_KEY", livekitKey], [
    "LIVEKIT_API_SECRET",
    livekitSecret,
  ]]
    .filter(([, value]) => !value)
    .map(([name]) => name);
  let livekit: LiveKitApi;
  if (lkMissing.length === 0) {
    livekit = new LiveKitClient({ url: livekitUrl, apiKey: livekitKey, apiSecret: livekitSecret });
  } else {
    const error = new ConfigError(lkMissing);
    log("error", error.message);
    livekit = unconfiguredLiveKit(error, livekitUrl);
  }

  defaultDepsInstance = { rpc, storage, livekit, now: () => new Date(), log, debug };
  return defaultDepsInstance;
}

// Serve when deployed (Supabase Edge Runtime defines `EdgeRuntime`) or run directly;
// stay inert when imported by tests.
if (import.meta.main || "EdgeRuntime" in globalThis) {
  Deno.serve((req) => handle(req, defaultDeps()));
}
