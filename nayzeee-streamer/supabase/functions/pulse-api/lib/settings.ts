// Network settings needed by validation (chat length, image hosts). Fetched through
// `pulse_act_server_hello` (p_actor null) and cached 30 s; successful `server.hello` calls
// prime the cache too. On failure the last value (or the SPEC defaults) is used and the
// refresh is retried after 5 s, so a DB hiccup never blocks validation.

import type { Deps, GatewaySettings, Logger } from "./types.ts";

export const CHAT_HARD_MAX = 500;
export const DEFAULT_SETTINGS: Readonly<GatewaySettings> = Object.freeze({ chatMaxLength: 300, imageHosts: [] });
const RETRY_AFTER_FAILURE_MS = 5_000;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Reads the gateway-relevant subset of NetworkSettings, or null when `raw` is not an object. */
export function parseSettings(raw: unknown): GatewaySettings | null {
  if (!isRecord(raw)) return null;
  const length = raw.chatMaxLength;
  const chatMaxLength = typeof length === "number" && Number.isFinite(length) && length >= 1
    ? Math.min(CHAT_HARD_MAX, Math.floor(length))
    : DEFAULT_SETTINGS.chatMaxLength;
  const imageHosts = Array.isArray(raw.imageHosts)
    ? raw.imageHosts
      .filter((host): host is string => typeof host === "string")
      .map((host) => host.trim().toLowerCase())
      .filter((host) => host.length > 0)
    : [];
  return { chatMaxLength, imageHosts };
}

export class SettingsCache {
  #value: GatewaySettings | null = null;
  #at = 0;
  #retryAt = 0;
  #inflight: Promise<GatewaySettings> | null = null;

  constructor(readonly ttlMs = 30_000) {}

  /** Seeds the cache from a `server.hello` response. */
  prime(raw: unknown, nowMs: number): void {
    const settings = parseSettings(raw);
    if (!settings) return;
    this.#value = settings;
    this.#at = nowMs;
    this.#retryAt = 0;
  }

  get(serverId: string, deps: Pick<Deps, "rpc" | "now">, log: Logger): Promise<GatewaySettings> {
    const now = deps.now().getTime();
    if (this.#value && now - this.#at < this.ttlMs) return Promise.resolve(this.#value);
    if (now < this.#retryAt) return Promise.resolve(this.#fallback());
    if (this.#inflight) return this.#inflight;

    const load = this.#load(serverId, deps, log);
    this.#inflight = load;
    const clear = () => {
      if (this.#inflight === load) this.#inflight = null;
    };
    load.then(clear, clear);
    return load;
  }

  async #load(serverId: string, deps: Pick<Deps, "rpc" | "now">, log: Logger): Promise<GatewaySettings> {
    try {
      const envelope = await deps.rpc("pulse_act_server_hello", { p_server: serverId, p_actor: null, p_params: {} });
      const settings = isRecord(envelope) && envelope.ok === true && isRecord(envelope.data)
        ? parseSettings(envelope.data.settings)
        : null;
      if (!settings) throw new Error("server.hello returned no settings");
      this.#value = settings;
      this.#at = deps.now().getTime();
      this.#retryAt = 0;
      return settings;
    } catch (err) {
      this.#retryAt = deps.now().getTime() + RETRY_AFTER_FAILURE_MS;
      const name = err instanceof Error ? err.name : "error";
      log("warn", `settings refresh failed (${name}); using ${this.#value ? "cached" : "default"} settings`);
      return this.#fallback();
    }
  }

  #fallback(): GatewaySettings {
    return this.#value ?? { ...DEFAULT_SETTINGS, imageHosts: [] };
  }
}
