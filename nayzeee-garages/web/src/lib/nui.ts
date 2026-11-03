/**
 * NUI transport: typed calls to Lua (fetchNui / request) and the Lua -> NUI message bus.
 * In a normal browser (vite dev / preview) calls are answered by mock handlers registered
 * with mockNui() from src/dev/mocks/*.
 */
import type { ApiResult, NuiCallbackName, NuiCallbacks, NuiMessage } from './types';

export const isBrowser = typeof window.GetParentResourceName !== 'function';
export const resourceName = isBrowser ? 'nayzeee-garages' : window.GetParentResourceName!();

type Req<K extends NuiCallbackName> = NuiCallbacks[K]['req'];
type Res<K extends NuiCallbackName> = NuiCallbacks[K]['res'];
type MockHandler<K extends NuiCallbackName> = (
  data: Req<K>,
) => Res<K> | ApiResult<Res<K>> | Promise<Res<K> | ApiResult<Res<K>>>;

const mocks = new Map<string, MockHandler<NuiCallbackName>>();

/**
 * Locale table from the `init` message, kept here so transport errors can be translated
 * without importing i18n (i18n -> store -> nui would be an import cycle).
 */
let locale: Record<string, string> = {};
const tr = (text: string): string => locale[text] ?? text;

/** Register a browser-only mock answer for a NUI callback (dev harness only). */
export function mockNui<K extends NuiCallbackName>(name: K, handler: MockHandler<K>) {
  mocks.set(name, handler as unknown as MockHandler<NuiCallbackName>);
}

function isResult(v: unknown): v is ApiResult<unknown> {
  return !!v && typeof v === 'object' && typeof (v as { ok?: unknown }).ok === 'boolean';
}

/** Raw typed call into Lua. Never throws. */
export async function fetchNui<K extends NuiCallbackName>(name: K, data?: Req<K>): Promise<ApiResult<Res<K>>> {
  const payload = (data ?? {}) as Req<K>;
  if (isBrowser) {
    await new Promise((r) => setTimeout(r, 120));
    const handler = mocks.get(name) as MockHandler<K> | undefined;
    if (!handler) return { ok: true, data: null as Res<K> };
    try {
      const out = await handler(payload);
      return isResult(out) ? (out as ApiResult<Res<K>>) : { ok: true, data: out as Res<K> };
    } catch (e) {
      return { ok: false, error: e instanceof Error ? e.message : String(e) };
    }
  }
  try {
    const resp = await fetch(`https://${resourceName}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(payload),
    });
    const json: unknown = await resp.json().catch(() => null);
    if (isResult(json)) return json as ApiResult<Res<K>>;
    return { ok: true, data: (json ?? null) as Res<K> };
  } catch {
    return { ok: false, error: tr('Request failed') };
  }
}

type ErrorReporter = (message: string) => void;
let reportError: ErrorReporter = () => undefined;

/** Wired by the store so request() can raise error toasts without a circular import. */
export function setErrorReporter(fn: ErrorReporter) {
  reportError = fn;
}

/**
 * Call Lua and show an error toast automatically when the call fails.
 * Returns the full ApiResult so callers can branch on `ok`.
 */
export async function request<K extends NuiCallbackName>(
  name: K,
  data?: Req<K>,
  opts: { toastError?: boolean } = {},
): Promise<ApiResult<Res<K>>> {
  const res = await fetchNui(name, data);
  if (!res.ok && opts.toastError !== false) reportError(res.error);
  return res;
}

type Listener = (msg: NuiMessage) => void;
const listeners = new Set<Listener>();

window.addEventListener('message', (event: MessageEvent) => {
  const msg = event.data as NuiMessage | undefined;
  if (!msg || typeof msg !== 'object' || typeof (msg as { action?: unknown }).action !== 'string') return;
  if (msg.action === 'init') {
    const table: unknown = msg.data?.locale;
    locale = table && typeof table === 'object' && !Array.isArray(table) ? (table as Record<string, string>) : {};
  }
  listeners.forEach((fn) => fn(msg));
});

/** Subscribe to Lua -> NUI messages. Returns an unsubscribe function. */
export function onNuiMessage(fn: Listener) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

/** Simulate a Lua -> NUI message (dev harness / tests). */
export function emitNuiMessage(msg: NuiMessage) {
  window.postMessage(msg, '*');
}
