// Executes the `fx` block of a `pulse_act_*` envelope (SPEC §4) in the fixed order
// createRoom → token → upload → broadcast → deleteRoom, merging results into `data`.
// createRoom / token / upload failures are fatal (the caller answers 500); broadcast and
// deleteRoom failures are logged and skipped.

import { describeError, FxError } from "./errors.ts";
import { MEDIA_BUCKET } from "./storage.ts";
import type { BroadcastFx, CreateRoomOptions, Deps, Json, JsonObject, Logger, TokenGrants, UploadFx } from "./types.ts";

const DEFAULT_EMPTY_TIMEOUT = 300;
const DEFAULT_TOKEN_TTL = 21_600;

export interface FxOptions {
  /** Only run broadcast + deleteRoom (used for `{ ok:false }` envelopes). */
  sideEffectsOnly?: boolean;
  /** Include raw error messages of unknown errors in logs. */
  debug?: boolean;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function nonEmpty(value: unknown): value is string {
  return typeof value === "string" && value.length > 0;
}

export function parseCreateRoom(raw: unknown): CreateRoomOptions {
  if (!isRecord(raw) || !nonEmpty(raw.name)) throw new FxError("fx.createRoom needs a room name");
  const emptyTimeout = typeof raw.emptyTimeout === "number" && raw.emptyTimeout >= 0
    ? Math.floor(raw.emptyTimeout)
    : DEFAULT_EMPTY_TIMEOUT;
  const maxParticipants = typeof raw.maxParticipants === "number" && raw.maxParticipants >= 0
    ? Math.floor(raw.maxParticipants)
    : 0;
  return { name: raw.name, emptyTimeout, maxParticipants };
}

export function parseToken(raw: unknown): TokenGrants {
  if (!isRecord(raw) || !nonEmpty(raw.room) || !nonEmpty(raw.identity)) {
    throw new FxError("fx.token needs room and identity");
  }
  const grants: TokenGrants = {
    room: raw.room,
    identity: raw.identity,
    publish: raw.publish === true,
    ttl: typeof raw.ttl === "number" && raw.ttl > 0 ? raw.ttl : DEFAULT_TOKEN_TTL,
  };
  if (nonEmpty(raw.name)) grants.name = raw.name;
  if (raw.metadata !== undefined && raw.metadata !== null) grants.metadata = raw.metadata as Json;
  return grants;
}

export function parseUpload(raw: unknown): UploadFx {
  if (!isRecord(raw) || !nonEmpty(raw.path) || !nonEmpty(raw.contentType)) {
    throw new FxError("fx.upload needs path and contentType");
  }
  return {
    bucket: nonEmpty(raw.bucket) ? raw.bucket : MEDIA_BUCKET,
    path: raw.path,
    contentType: raw.contentType,
    upsert: raw.upsert === true,
  };
}

export function parseBroadcasts(raw: unknown, log: Logger): BroadcastFx[] {
  if (raw === undefined || raw === null) return [];
  const list = Array.isArray(raw) ? raw : [raw];
  const out: BroadcastFx[] = [];
  for (const entry of list) {
    if (isRecord(entry) && nonEmpty(entry.room) && nonEmpty(entry.topic) && entry.payload !== undefined) {
      out.push({ room: entry.room, topic: entry.topic, payload: entry.payload as Json });
    } else {
      log("warn", "skipping malformed fx.broadcast entry");
    }
  }
  return out;
}

export function parseDeleteRooms(raw: unknown): string[] {
  if (nonEmpty(raw)) return [raw];
  if (isRecord(raw) && nonEmpty(raw.room)) return [raw.room];
  if (Array.isArray(raw)) return raw.filter(nonEmpty);
  return [];
}

function withVersion(url: string, nowMs: number): string {
  return `${url}${url.includes("?") ? "&" : "?"}v=${Math.floor(nowMs / 1000)}`;
}

/** Runs `fx` and returns a new data object with token / upload results merged in. */
export async function executeFx(
  fx: unknown,
  data: JsonObject,
  deps: Deps,
  log: Logger,
  options: FxOptions = {},
): Promise<JsonObject> {
  const out: JsonObject = { ...data };
  if (fx === undefined || fx === null) return out;
  if (!isRecord(fx)) throw new FxError("fx must be an object");

  if (!options.sideEffectsOnly) {
    if (fx.createRoom !== undefined && fx.createRoom !== null) {
      await deps.livekit.createRoom(parseCreateRoom(fx.createRoom));
    }

    if (fx.token !== undefined && fx.token !== null) {
      const token = await deps.livekit.token(parseToken(fx.token));
      out.livekit = { url: deps.livekit.url, token };
    }

    if (fx.upload !== undefined && fx.upload !== null) {
      const upload = parseUpload(fx.upload);
      const signed = await deps.storage.signedUpload(upload.bucket, upload.path, upload.contentType, upload.upsert);
      out.uploadUrl = signed.uploadUrl;
      out.method = "PUT";
      out.headers = { ...signed.headers };
      if (!nonEmpty(out.publicUrl)) {
        const url = deps.storage.publicUrl(upload.bucket, upload.path);
        out.publicUrl = upload.upsert ? withVersion(url, deps.now().getTime()) : url;
      }
    }
  }

  for (const message of parseBroadcasts(fx.broadcast, log)) {
    try {
      await deps.livekit.sendData(message.room, message.topic, message.payload);
    } catch (err) {
      log("warn", `broadcast to ${message.room} (${message.topic}) failed: ${describeError(err, options.debug)}`);
    }
  }

  for (const room of parseDeleteRooms(fx.deleteRoom)) {
    try {
      await deps.livekit.deleteRoom(room);
    } catch (err) {
      log("warn", `deleteRoom ${room} failed: ${describeError(err, options.debug)}`);
    }
  }

  return out;
}
