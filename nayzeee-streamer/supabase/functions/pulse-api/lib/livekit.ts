// LiveKit access tokens (HS256 JWT via WebCrypto) and RoomService Twirp calls.
// Twirp JSON is decoded server-side with protojson, which accepts the proto field names
// (snake_case) used here; `data` is bytes → standard base64, `kind` is the enum name.

import type { CreateRoomOptions, Json, JsonObject, LiveKitApi, LiveKitParticipant, TokenGrants } from "./types.ts";

const encoder = new TextEncoder();

export const ADMIN_TOKEN_TTL = 600;
const MIN_TOKEN_TTL = 60;
const MAX_TOKEN_TTL = 86_400;
const DEFAULT_TIMEOUT_MS = 5_000;

/** Thrown for failed RoomService calls. Never carries tokens or secrets. */
export class LiveKitError extends Error {
  constructor(message: string, readonly status: number, readonly code: string) {
    super(message);
    this.name = "LiveKitError";
  }
}

export function base64Encode(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

export function base64UrlEncode(bytes: Uint8Array): string {
  return base64Encode(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function importHmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, [
    "sign",
  ]);
}

/** Signs `claims` as a compact HS256 JWT. */
export async function signHs256(claims: JsonObject, key: CryptoKey): Promise<string> {
  const header = base64UrlEncode(encoder.encode(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const payload = base64UrlEncode(encoder.encode(JSON.stringify(claims)));
  const input = `${header}.${payload}`;
  const signature = new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(input)));
  return `${input}.${base64UrlEncode(signature)}`;
}

/** `wss://host` → `https://host`, `ws://host` → `http://host`, trailing slashes removed. */
export function twirpBase(url: string): string {
  const trimmed = url.trim().replace(/\/+$/, "");
  if (/^wss:\/\//i.test(trimmed)) return "https://" + trimmed.slice(6);
  if (/^ws:\/\//i.test(trimmed)) return "http://" + trimmed.slice(5);
  return trimmed;
}

function clampTtl(ttl: number): number {
  if (!Number.isFinite(ttl)) return MIN_TOKEN_TTL;
  return Math.min(MAX_TOKEN_TTL, Math.max(MIN_TOKEN_TTL, Math.floor(ttl)));
}

export interface LiveKitOptions {
  /** wss:// URL clients connect to. */
  url: string;
  apiKey: string;
  apiSecret: string;
  timeoutMs?: number;
  fetch?: typeof fetch;
  now?: () => Date;
}

export class LiveKitClient implements LiveKitApi {
  readonly url: string;
  readonly #apiKey: string;
  readonly #key: Promise<CryptoKey>;
  readonly #base: string;
  readonly #timeoutMs: number;
  readonly #fetch: typeof fetch;
  readonly #now: () => Date;

  constructor(options: LiveKitOptions) {
    this.url = options.url.trim();
    this.#apiKey = options.apiKey;
    this.#key = importHmacKey(options.apiSecret);
    this.#base = twirpBase(options.url);
    this.#timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    this.#fetch = options.fetch ?? fetch;
    this.#now = options.now ?? (() => new Date());
  }

  #nowSec(): number {
    return Math.floor(this.#now().getTime() / 1000);
  }

  /** Participant token: subscribe always, publish per grant, never data or own metadata. */
  async token(grants: TokenGrants): Promise<string> {
    const now = this.#nowSec();
    const claims: JsonObject = {
      iss: this.#apiKey,
      sub: grants.identity,
      name: grants.name ?? grants.identity,
      nbf: now - 10,
      exp: now + clampTtl(grants.ttl),
      jti: crypto.randomUUID(),
      video: {
        room: grants.room,
        roomJoin: true,
        canSubscribe: true,
        canPublish: grants.publish,
        canPublishData: false,
        canUpdateOwnMetadata: false,
        hidden: false,
      },
    };
    if (grants.metadata !== undefined && grants.metadata !== null) {
      claims.metadata = typeof grants.metadata === "string" ? grants.metadata : JSON.stringify(grants.metadata);
    }
    return signHs256(claims, await this.#key);
  }

  /** Server API token for RoomService calls (room-scoped when `room` is given). */
  async adminToken(room?: string): Promise<string> {
    const now = this.#nowSec();
    const video: JsonObject = { roomCreate: true, roomAdmin: true, roomList: true };
    if (room) video.room = room;
    const claims: JsonObject = {
      iss: this.#apiKey,
      nbf: now - 10,
      exp: now + ADMIN_TOKEN_TTL,
      jti: crypto.randomUUID(),
      video,
    };
    return signHs256(claims, await this.#key);
  }

  async createRoom(options: CreateRoomOptions): Promise<void> {
    await this.#twirp("CreateRoom", {
      name: options.name,
      empty_timeout: Math.max(0, Math.floor(options.emptyTimeout)),
      max_participants: Math.max(0, Math.floor(options.maxParticipants)),
    }, options.name);
  }

  /** Deleting a room that no longer exists counts as success. */
  async deleteRoom(room: string): Promise<void> {
    try {
      await this.#twirp("DeleteRoom", { room }, room);
    } catch (err) {
      if (err instanceof LiveKitError && (err.code === "not_found" || err.status === 404)) return;
      throw err;
    }
  }

  async sendData(room: string, topic: string, payload: Json): Promise<void> {
    const nonce = crypto.getRandomValues(new Uint8Array(16));
    await this.#twirp("SendData", {
      room,
      data: base64Encode(encoder.encode(JSON.stringify(payload))),
      kind: "RELIABLE",
      topic,
      nonce: base64Encode(nonce),
    }, room);
  }

  async listParticipants(room: string): Promise<LiveKitParticipant[]> {
    const body = await this.#twirp("ListParticipants", { room }, room);
    const list = Array.isArray(body.participants) ? body.participants : [];
    return list.flatMap((entry): LiveKitParticipant[] => {
      if (typeof entry !== "object" || entry === null || Array.isArray(entry)) return [];
      const p = entry as Record<string, unknown>;
      const joined = p.joined_at ?? p.joinedAt;
      const tracks = Array.isArray(p.tracks) ? p.tracks : [];
      return [{
        sid: String(p.sid ?? ""),
        identity: String(p.identity ?? ""),
        name: String(p.name ?? ""),
        state: String(p.state ?? ""),
        metadata: String(p.metadata ?? ""),
        joinedAt: Number(joined ?? 0) || 0,
        isPublisher: p.is_publisher === true || p.isPublisher === true || tracks.length > 0,
      }];
    });
  }

  async #twirp(method: string, body: JsonObject, room?: string): Promise<Record<string, unknown>> {
    const token = await this.adminToken(room);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.#timeoutMs);
    let response: Response;
    try {
      response = await this.#fetch(`${this.#base}/twirp/livekit.RoomService/${method}`, {
        method: "POST",
        headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
    } catch (err) {
      clearTimeout(timer);
      const reason = controller.signal.aborted ? `timed out after ${this.#timeoutMs} ms` : errorName(err);
      throw new LiveKitError(`LiveKit ${method} failed: ${reason}`, 0, "unavailable");
    }
    try {
      const text = await response.text();
      const parsed = parseJsonObject(text);
      if (!response.ok) {
        const code = typeof parsed.code === "string" ? parsed.code : "http_" + response.status;
        const msg = typeof parsed.msg === "string" ? `: ${parsed.msg.slice(0, 200)}` : "";
        throw new LiveKitError(`LiveKit ${method} failed (${response.status} ${code})${msg}`, response.status, code);
      }
      return parsed;
    } catch (err) {
      if (err instanceof LiveKitError) throw err;
      const reason = controller.signal.aborted ? `timed out after ${this.#timeoutMs} ms` : errorName(err);
      throw new LiveKitError(`LiveKit ${method} failed: ${reason}`, response.status, "unavailable");
    } finally {
      clearTimeout(timer);
    }
  }
}

function parseJsonObject(text: string): Record<string, unknown> {
  if (!text) return {};
  try {
    const value: unknown = JSON.parse(text);
    return typeof value === "object" && value !== null && !Array.isArray(value)
      ? value as Record<string, unknown>
      : {};
  } catch {
    return {};
  }
}

function errorName(err: unknown): string {
  return err instanceof Error ? err.name : "network error";
}
