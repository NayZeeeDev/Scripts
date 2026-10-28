// Server key authentication: `x-pulse-key` → `pulse_server_by_key(p_key)`.
// Lookups are cached in memory keyed by the SHA-256 of the key (plaintext keys are never kept):
// rows for 60 s, misses for 10 s. Concurrent lookups of the same key share one rpc.

import type { Deps, ServerRecord } from "./types.ts";

const KEY_SHAPE_RE = /^[A-Za-z0-9_-]{8,128}$/;
const encoder = new TextEncoder();

export function looksLikeKey(key: string): boolean {
  return KEY_SHAPE_RE.test(key);
}

async function sha256Hex(text: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(text)));
  let hex = "";
  for (const byte of digest) hex += byte.toString(16).padStart(2, "0");
  return hex;
}

function asString(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value : fallback;
}

/**
 * Accepts what PostgREST returns for the function: a row object, a one-row array (setof),
 * or null / an all-null composite when no server matches.
 */
export function parseServerRow(raw: unknown): ServerRecord | null {
  const row = Array.isArray(raw) ? raw[0] : raw;
  if (typeof row !== "object" || row === null) return null;
  const r = row as Record<string, unknown>;
  if (typeof r.id !== "string" || r.id === "") return null;
  return {
    id: r.id,
    slug: asString(r.slug),
    name: asString(r.name),
    tag: asString(r.tag),
    color: asString(r.color, "#08afa2"),
    trusted: r.trusted !== false,
    networkAdmin: r.network_admin === true || r.networkAdmin === true,
    active: r.active !== false,
  };
}

interface Entry {
  server: ServerRecord | null;
  expires: number;
}

export class ServerKeyCache {
  readonly #entries = new Map<string, Entry>();
  readonly #inflight = new Map<string, Promise<ServerRecord | null>>();

  constructor(
    readonly ttlMs = 60_000,
    readonly negativeTtlMs = 10_000,
    readonly maxEntries = 5_000,
  ) {}

  /** The server for `key` (inactive servers included; the caller rejects them), or null. */
  async resolve(key: string, deps: Pick<Deps, "rpc" | "now">): Promise<ServerRecord | null> {
    const hash = await sha256Hex(key);
    const now = deps.now().getTime();
    const cached = this.#entries.get(hash);
    if (cached && cached.expires > now) return cached.server;
    if (cached) this.#entries.delete(hash);

    const pending = this.#inflight.get(hash);
    if (pending) return pending;

    const lookup = this.#lookup(hash, key, deps);
    this.#inflight.set(hash, lookup);
    const clear = () => {
      if (this.#inflight.get(hash) === lookup) this.#inflight.delete(hash);
    };
    lookup.then(clear, clear);
    return lookup;
  }

  async #lookup(hash: string, key: string, deps: Pick<Deps, "rpc" | "now">): Promise<ServerRecord | null> {
    const server = parseServerRow(await deps.rpc("pulse_server_by_key", { p_key: key }));
    const ttl = server ? this.ttlMs : this.negativeTtlMs;
    this.#store(hash, { server, expires: deps.now().getTime() + ttl });
    return server;
  }

  #store(hash: string, entry: Entry): void {
    this.#entries.delete(hash);
    this.#entries.set(hash, entry);
    while (this.#entries.size > this.maxEntries) {
      const oldest = this.#entries.keys().next();
      if (oldest.done) break;
      this.#entries.delete(oldest.value);
    }
  }

  clear(): void {
    this.#entries.clear();
  }
}
