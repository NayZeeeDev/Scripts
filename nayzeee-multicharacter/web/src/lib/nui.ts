// NUI bridge: fetch to Lua callbacks + message listener. Falls back to a mock bridge in a browser.

declare global {
  interface Window {
    GetParentResourceName?: () => string;
    __nzMock?: (name: string, data: unknown) => Promise<unknown>;
  }
}

export const IS_MOCK = typeof window.GetParentResourceName !== 'function';

const resource = (): string => {
  try { return window.GetParentResourceName ? window.GetParentResourceName() : 'nayzeee-multicharacter'; }
  catch { return 'nayzeee-multicharacter'; }
};

export async function post<T = unknown>(name: string, data: unknown = {}): Promise<T> {
  if (IS_MOCK) {
    if (!window.__nzMock) return true as T;
    return (await window.__nzMock(name, data)) as T;
  }
  try {
    const res = await fetch(`https://${resource()}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data ?? {}),
    });
    const txt = await res.text();
    if (!txt) return true as T;
    try { return JSON.parse(txt) as T; } catch { return txt as unknown as T; }
  } catch {
    return null as T;
  }
}

export interface NuiMessage { action: string; data?: any }

/** Dispatch a fake Lua → NUI message (mock / dev tools). */
export function emit(action: string, data: unknown = {}) {
  window.postMessage({ action, data }, '*');
}
