// Shared types for the pulse-api gateway.
// Wire field names follow SPEC §2 exactly; never rename them here.

/** Any JSON value. */
export type Json = null | boolean | number | string | Json[] | JsonObject;

/** A JSON object (plain record of JSON values). */
export interface JsonObject {
  [key: string]: Json;
}

export type LogLevel = "debug" | "info" | "warn" | "error";

/** Log sink. The gateway never passes secrets to it. */
export type Logger = (level: LogLevel, message: string) => void;

/** The player a FiveM server vouches for (`body.actor`). */
export interface Actor {
  ref: string;
  name: string;
}

/** A FiveM server row resolved from its `x-pulse-key`. */
export interface ServerRecord {
  id: string;
  slug: string;
  name: string;
  tag: string;
  color: string;
  trusted: boolean;
  networkAdmin: boolean;
  active: boolean;
}

/** Subset of NetworkSettings (SPEC §2.1) the gateway itself reads. */
export interface GatewaySettings {
  /** Already capped to the gateway hard limit (500). */
  chatMaxLength: number;
  /** Lower-cased host names (`*.example.com` / `.example.com` match subdomains). */
  imageHosts: string[];
}

/** Grants for a LiveKit participant access token (from the `fx.token` envelope entry). */
export interface TokenGrants {
  room: string;
  identity: string;
  name?: string;
  publish: boolean;
  /** Seconds. */
  ttl: number;
  /** Serialised into the JWT `metadata` claim as a string. */
  metadata?: Json;
}

/** Options for `RoomService/CreateRoom`. */
export interface CreateRoomOptions {
  name: string;
  /** Seconds the room stays open with nobody in it. */
  emptyTimeout: number;
  /** 0 = unlimited. */
  maxParticipants: number;
}

/** A participant as reported by `RoomService/ListParticipants`. */
export interface LiveKitParticipant {
  sid: string;
  identity: string;
  name: string;
  state: string;
  metadata: string;
  /** Unix seconds, 0 when unknown. */
  joinedAt: number;
  isPublisher: boolean;
}

/** LiveKit operations the gateway needs. */
export interface LiveKitApi {
  /** Client-facing URL (wss://...) handed to players with their token. */
  readonly url: string;
  token(grants: TokenGrants): Promise<string>;
  createRoom(options: CreateRoomOptions): Promise<void>;
  deleteRoom(room: string): Promise<void>;
  sendData(room: string, topic: string, payload: Json): Promise<void>;
  listParticipants(room: string): Promise<LiveKitParticipant[]>;
}

/** Result of signing a direct-to-storage upload. */
export interface SignedUpload {
  uploadUrl: string;
  /** Headers the uploader must send with its raw `PUT`. */
  headers: Record<string, string>;
}

/** Storage operations the gateway needs. */
export interface StorageApi {
  /** `<origin>/storage/v1/object/public/pulse-media` — passed to SQL as `_publicBase`. */
  readonly publicBase: string;
  signedUpload(bucket: string, path: string, contentType: string, upsert: boolean): Promise<SignedUpload>;
  publicUrl(bucket: string, path: string): string;
}

/** Everything `handle()` touches outside its own memory. Tests pass fakes. */
export interface Deps {
  /** Calls a plpgsql function and returns its result, or throws. */
  rpc(fn: string, args: Record<string, unknown>): Promise<unknown>;
  storage: StorageApi;
  livekit: LiveKitApi;
  now(): Date;
  /** Defaults to console output. */
  log?: Logger;
  /** Log error details (PULSE_DEBUG=1). Defaults to false. */
  debug?: boolean;
}

/** Envelope fx block returned by `pulse_act_*` functions (SPEC §4). */
export interface BroadcastFx {
  room: string;
  topic: string;
  payload: Json;
}

export interface UploadFx {
  bucket: string;
  path: string;
  contentType: string;
  upsert: boolean;
}
