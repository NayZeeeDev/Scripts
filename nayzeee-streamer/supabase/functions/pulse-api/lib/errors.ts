// Error classes shared across the gateway, plus a log-safe error description.

import { LiveKitError } from "./livekit.ts";
import { StorageFailure } from "./storage.ts";

/** A protocol-level failure answered with a specific HTTP status (401, 400, 413, 429, ...). */
export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly headers: Record<string, string> = {},
  ) {
    super(message);
    this.name = "HttpError";
  }
}

/** Required environment variables are missing. Only variable names are carried. */
export class ConfigError extends Error {
  constructor(readonly missing: readonly string[]) {
    super(`missing environment variables: ${missing.join(", ")}`);
    this.name = "ConfigError";
  }
}

/** The SQL returned an envelope / fx entry the gateway cannot use. */
export class FxError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "FxError";
  }
}

/** A PostgREST / Postgres error raised by an rpc call. */
export class RpcError extends Error {
  constructor(
    readonly fn: string,
    readonly code: string,
    message: string,
    readonly details: string | null,
    readonly hint: string | null,
  ) {
    super(message);
    this.name = "RpcError";
  }
}

/**
 * Log-safe description. Our own error classes carry no secrets (room names, function names,
 * SQLSTATE codes, env var names); anything else is described by name only unless debugging.
 */
export function describeError(err: unknown, debug = false): string {
  if (
    err instanceof LiveKitError || err instanceof StorageFailure || err instanceof FxError ||
    err instanceof ConfigError
  ) {
    return err.message;
  }
  if (err instanceof RpcError) {
    const base = `RpcError(${err.fn}${err.code ? `, ${err.code}` : ""})`;
    return debug ? `${base}: ${err.message}${err.details ? ` (${err.details})` : ""}` : base;
  }
  if (err instanceof Error) return debug ? `${err.name}: ${err.message}` : err.name;
  return "unknown error";
}
