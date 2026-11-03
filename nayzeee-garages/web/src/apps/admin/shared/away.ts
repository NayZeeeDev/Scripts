/**
 * Admin "away" state — hides the admin UI while an in-world tool runs.
 *
 * While request('admin:points', …) is pending, Lua releases NUI focus and runs the in-world
 * point manager. The admin app stays OPEN (so unsaved editor state survives), it only has to be
 * invisible. Nothing unmounts: the admin window and every overlay portal (modals, dropdowns,
 * tooltips) get `visibility: hidden; opacity: 0; pointer-events: none` through the
 * `nz-admin-away` class on <html> (rules in admin.css), and come back with their enter
 * animation when the request resolves.
 *
 * API
 * - requestPoints(payload)   request('admin:points', payload) with the admin UI hidden while it
 *                            is pending. Use it for EVERY admin:points call.
 * - runAway(fn)              same for any other in-world tool: hide, await fn(), show again and
 *                            return fn's result. Nested / parallel calls are counted.
 * - useAdminHidden()         React hook: true while hidden.
 * - isAdminHidden()          non-React read.
 * - useAdminAway             the underlying zustand store ({ pending }).
 * Focus: the focused element is blurred while hidden (typing must not reach a hidden input)
 * and focused again afterwards when it is still on screen.
 */
import { create } from 'zustand';
import { request } from '@/lib/nui';
import type { NuiCallbacks } from '@/lib/types';

interface AwayState {
  /** Number of in-world tools currently running. */
  pending: number;
}

export const useAdminAway = create<AwayState>(() => ({ pending: 0 }));

const AWAY_CLASS = 'nz-admin-away';

useAdminAway.subscribe((s) => {
  document.documentElement.classList.toggle(AWAY_CLASS, s.pending > 0);
});

export function useAdminHidden(): boolean {
  return useAdminAway((s) => s.pending > 0);
}

export function isAdminHidden(): boolean {
  return useAdminAway.getState().pending > 0;
}

/**
 * Focus `el` again once the UI is visible. The button that started the tool is usually still
 * in its loading (disabled) state for a frame or two, so retry for a short while.
 */
function restoreFocus(el: HTMLElement) {
  let tries = 0;
  const attempt = () => {
    if (isAdminHidden() || !document.body.contains(el)) return;
    const focused = document.activeElement;
    // The user (or the page) already moved focus somewhere meaningful: leave it.
    if (focused && focused !== document.body && focused !== el) return;
    if (!el.matches(':disabled')) {
      el.focus({ preventScroll: true });
      return;
    }
    if (++tries < 20) requestAnimationFrame(attempt);
  };
  requestAnimationFrame(attempt);
}

/** Hide the admin UI while `fn` runs; always shows it again, even when `fn` throws. */
export async function runAway<T>(fn: () => Promise<T>): Promise<T> {
  const active = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  if (active && active !== document.body) active.blur();
  useAdminAway.setState((s) => ({ pending: s.pending + 1 }));
  try {
    return await fn();
  } finally {
    useAdminAway.setState((s) => ({ pending: Math.max(0, s.pending - 1) }));
    if (!isAdminHidden() && active && active !== document.body) restoreFocus(active);
  }
}

type PointsReq = NuiCallbacks['admin:points']['req'];

/** request('admin:points', payload) while the admin UI is hidden (see file header). */
export function requestPoints(payload: PointsReq) {
  return runAway(() => request('admin:points', payload));
}
