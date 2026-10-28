// Postgres access. Every DB call is a plpgsql function invoked through PostgREST `rpc`
// (SPEC §4); TypeScript never queries tables directly.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { RpcError } from "./errors.ts";

export { RpcError };

const RPC_TIMEOUT_MS = 15_000;
const APP_ERROR_CODE_RE = /^[a-z][a-z0-9_]{1,40}$/;

export interface PgErrorLike {
  message: string;
  code?: string | null;
  details?: string | null;
  hint?: string | null;
}

export type RpcCall = (
  fn: string,
  args: Record<string, unknown>,
) => PromiseLike<{ data: unknown; error: PgErrorLike | null }>;

/** Wraps a supabase-js style rpc into `Deps.rpc`: returns data or throws `RpcError`. */
export function rpcFrom(call: RpcCall): (fn: string, args: Record<string, unknown>) => Promise<unknown> {
  return async (fn, args) => {
    const { data, error } = await call(fn, args);
    if (error) {
      throw new RpcError(fn, error.code ?? "", error.message || "rpc failed", error.details ?? null, error.hint ?? null);
    }
    return data;
  };
}

/**
 * A plpgsql `raise exception '<code>'` (SQLSTATE P0001) whose message is an error code is an
 * application error (e.g. a guard inside SQL), not a crash: surface it as `{ ok:false, error }`.
 */
export function appErrorFromRpc(err: unknown): { error: string; message: string } | null {
  if (!(err instanceof RpcError) || err.code !== "P0001") return null;
  const code = err.message.trim();
  if (!APP_ERROR_CODE_RE.test(code)) return null;
  const message = (err.details ?? err.hint ?? "").trim();
  return { error: code, message: message || code.replaceAll("_", " ") };
}

function timeoutFetch(timeoutMs: number): typeof fetch {
  return (input, init) => {
    const timeout = AbortSignal.timeout(timeoutMs);
    const signal = init?.signal ? AbortSignal.any([init.signal, timeout]) : timeout;
    return fetch(input, { ...init, signal });
  };
}

/** Service-role client (bypasses RLS; never exposed to game servers). */
export function createSupabase(url: string, serviceRoleKey: string): SupabaseClient {
  return createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { fetch: timeoutFetch(RPC_TIMEOUT_MS), headers: { "x-client-info": "pulse-api" } },
  });
}
