/**
 * Orbit camera input of the setup menu. The interface owns the pointer and keyboard while
 * the menu holds NUI focus, so it turns them into 'setup:camera' messages for Lua:
 *   - drag / wheel deltas are summed and sent one request at a time (the next one leaves
 *     when the previous answer is back, so a slow frame never queues a backlog);
 *   - held keys (A D W S, Q E) are sent as a state on every change and re-sent every
 *     400 ms while held (Lua drops a hold it has not heard of for a second, so a lost
 *     key-up can never leave the camera spinning);
 *   - presets go out at once; so does the menu's top edge (`frame`, on open and resize), which
 *     Lua uses to keep the vehicle in the free space above the menu.
 * fetchNui (not request): a failed camera call is cosmetic and must never raise a notification.
 */
import { useCallback, useEffect, useRef } from 'react';
import { fetchNui } from '@/lib/nui';
import type { SetupView } from '@/lib/types';

/** Degrees of orbit per dragged pixel. */
const YAW_PER_PX = 0.3;
const PITCH_PER_PX = 0.22;
const HOLD_REPEAT_MS = 400;

type HoldKey = 'left' | 'right' | 'up' | 'down' | 'in' | 'out';
/** Physical keys (event.code), so the WASD block works on any keyboard layout. */
export const HOLD_CODES: Record<string, HoldKey> = {
  KeyA: 'left',
  KeyD: 'right',
  KeyW: 'up',
  KeyS: 'down',
  KeyE: 'in',
  KeyQ: 'out',
};

interface Pending {
  yaw: number;
  pitch: number;
  zoom: number;
}

export interface OrbitInput {
  /** Pointer moved by (dx, dy) px while dragging. */
  drag: (dx: number, dy: number) => void;
  /** Wheel steps: + = farther. */
  zoom: (steps: number) => void;
  /** Key down / up of a HOLD_CODES key. */
  press: (key: HoldKey, down: boolean) => void;
  /** Release every held key (blur, close). */
  releaseAll: () => void;
  view: (view: SetupView) => void;
  /** The menu's top edge as a fraction of the screen height (camera framing). */
  frame: (top: number) => void;
}

export function useOrbitInput(enabled: boolean, onManual: () => void): OrbitInput {
  const pending = useRef<Pending>({ yaw: 0, pitch: 0, zoom: 0 });
  const busy = useRef(false);
  const held = useRef(new Set<HoldKey>());
  const lastHold = useRef('0,0,0');
  const timer = useRef<number | null>(null);
  const manual = useRef(onManual);
  manual.current = onManual;

  const flush = useCallback(() => {
    if (busy.current) return;
    const p = pending.current;
    if (!p.yaw && !p.pitch && !p.zoom) return;
    pending.current = { yaw: 0, pitch: 0, zoom: 0 };
    busy.current = true;
    void fetchNui('setup:camera', { yaw: round(p.yaw), pitch: round(p.pitch), zoom: round(p.zoom) }).finally(() => {
      busy.current = false;
      flush();
    });
  }, []);

  const holdState = () => {
    const h = held.current;
    return {
      yaw: (h.has('right') ? 1 : 0) - (h.has('left') ? 1 : 0),
      pitch: (h.has('up') ? 1 : 0) - (h.has('down') ? 1 : 0),
      zoom: (h.has('out') ? 1 : 0) - (h.has('in') ? 1 : 0),
    };
  };

  const sendHold = useCallback((force: boolean) => {
    const hold = holdState();
    const key = `${hold.yaw},${hold.pitch},${hold.zoom}`;
    if (!force && key === lastHold.current) return;
    lastHold.current = key;
    void fetchNui('setup:camera', { hold });
    const active = key !== '0,0,0';
    if (active && timer.current === null) {
      timer.current = window.setInterval(() => sendHold(true), HOLD_REPEAT_MS);
    } else if (!active && timer.current !== null) {
      window.clearInterval(timer.current);
      timer.current = null;
    }
  }, []);

  const releaseAll = useCallback(() => {
    if (held.current.size === 0 && lastHold.current === '0,0,0') return;
    held.current.clear();
    sendHold(false);
  }, [sendHold]);

  // Closing the menu (or losing the camera) releases every key and stops the repeat timer.
  useEffect(() => {
    if (!enabled) {
      held.current.clear();
      lastHold.current = '0,0,0';
      pending.current = { yaw: 0, pitch: 0, zoom: 0 };
    }
    return () => {
      if (timer.current !== null) window.clearInterval(timer.current);
      timer.current = null;
    };
  }, [enabled]);

  useEffect(() => {
    if (!enabled) return;
    const onBlur = () => releaseAll();
    window.addEventListener('blur', onBlur);
    return () => window.removeEventListener('blur', onBlur);
  }, [enabled, releaseAll]);

  return {
    drag: (dx, dy) => {
      if (!enabled || (!dx && !dy)) return;
      // Drag right = the car turns right under the cursor (the camera goes left round it);
      // drag down = tilt its roof toward you (the camera goes up).
      pending.current.yaw -= dx * YAW_PER_PX;
      pending.current.pitch += dy * PITCH_PER_PX;
      manual.current();
      flush();
    },
    zoom: (steps) => {
      if (!enabled || !steps) return;
      pending.current.zoom += steps;
      manual.current();
      flush();
    },
    press: (key, down) => {
      if (!enabled) return;
      const h = held.current;
      if (down === h.has(key)) return;
      if (down) h.add(key);
      else h.delete(key);
      if (down) manual.current();
      sendHold(false);
    },
    releaseAll,
    view: (view) => {
      if (!enabled) return;
      void fetchNui('setup:camera', { view });
    },
    frame: (top) => {
      if (!enabled || !Number.isFinite(top)) return;
      void fetchNui('setup:camera', { frame: Math.round(top * 1000) / 1000 });
    },
  };
}

const round = (n: number) => Math.round(n * 100) / 100;
