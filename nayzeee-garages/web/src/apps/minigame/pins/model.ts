/**
 * Pin tumbler lock: the simulation (no three.js, no React). The server's puzzle gives the pin
 * count, the binding order and each pin's height; this file turns key input into lifts, sets,
 * drops and the overset that snaps the pick.
 *
 *   - Tension (Space) must be held for anything to set. Releasing it drops every set pin.
 *   - Under tension only ONE pin binds: the next one of the puzzle's order. It is stiff (lifts
 *     slower, the pick trembles) and friction holds it where you leave it; the others are
 *     springy and fall back the moment you stop lifting.
 *   - Lifting the binding pin to its shear line clicks; stop lifting (release W) inside the set
 *     zone and it sets: the driver pin stays above the shear line, the plug turns a little.
 *   - Pushing it more than OVERSET past the shear line, or crossing the shear line faster than
 *     MAX_SET_SPEED (W held too long: the lift speeds up), oversets it: the pick snaps.
 *   - Every pin set (in the binding order) opens the lock. answer = the pins in the order set.
 */

/** lift units: the key pin's travel; the shear line of pin i is at lift need[i] */
export const LIFT_MAX = 1.3;
/** past the shear line: overset (snap) */
export const OVERSET = 0.17;
/** below the shear line that still sets on release */
export const SET_EARLY = 0.035;
/** speed (lift / s) at which crossing the shear line oversets */
export const MAX_SET_SPEED = 1.05;
/** first press nudge, then the hold speeds up from SPEED_START to SPEED_END over RAMP_MS */
export const NUDGE = 0.045;
export const SPEED_START = 0.3;
export const SPEED_END = 1.6;
export const RAMP_MS = 700;
/** the binding pin is stiff */
export const BIND_FACTOR = 0.72;
export const LOWER_SPEED = 1.2;
export const SPRING_SPEED = 3.2;

export type LockStatus = 'play' | 'open' | 'snapped';

export interface PinState {
  /** lift at which the key pin's top meets the shear line */
  need: number;
  /** current lift of the key pin (0 = resting) */
  lift: number;
  set: boolean;
}

export interface LockState {
  pins: PinState[];
  /** 0-based pin indices in binding order */
  order: number[];
  /** 1-based pin numbers in the order they were set (the answer) */
  setOrder: number[];
  /** 0-based pin under the pick */
  pick: number;
  tension: boolean;
  lifting: boolean;
  lowering: boolean;
  /** ms W has been held (the lift speeds up) */
  holdMs: number;
  /** the binding pin under the pick is at its shear line (clicked, waiting for release) */
  zone: boolean;
  status: LockStatus;
  /** last lift speed of the pin under the pick (lift / s), for the tremble */
  speed: number;
}

export type LockEvent =
  | { type: 'click'; pin: number }
  | { type: 'set'; pin: number }
  | { type: 'drop'; count: number }
  | { type: 'spring'; pin: number }
  | { type: 'overset'; pin: number; reason: 'far' | 'fast' }
  | { type: 'open' }
  | { type: 'move'; pin: number }
  | { type: 'tension'; on: boolean };

/** Shear-line lift of a pin from the server's height (0.25..0.90). */
export const needOf = (height: number) => 0.38 + Math.max(0, Math.min(1, height)) * 0.62;

/** Validates the server puzzle; null when it cannot be played. */
export function createLock(puzzle: { pins: number; order: number[]; heights: number[] }): LockState | null {
  const n = Math.floor(Number(puzzle?.pins));
  if (!Number.isFinite(n) || n < 3 || n > 7) return null;
  if (!Array.isArray(puzzle.order) || puzzle.order.length !== n) return null;
  if (!Array.isArray(puzzle.heights) || puzzle.heights.length !== n) return null;
  const seen = new Set<number>();
  const order: number[] = [];
  for (const raw of puzzle.order) {
    const p = Math.floor(Number(raw));
    if (!Number.isFinite(p) || p < 1 || p > n || seen.has(p)) return null;
    seen.add(p);
    order.push(p - 1);
  }
  const pins: PinState[] = puzzle.heights.map((h) => ({ need: needOf(Number(h) || 0.5), lift: 0, set: false }));
  return {
    pins,
    order,
    setOrder: [],
    pick: 0,
    tension: false,
    lifting: false,
    lowering: false,
    holdMs: 0,
    zone: false,
    status: 'play',
    speed: 0,
  };
}

/** The pin that binds now (0-based), or -1 without tension / when all are set. */
export function bindingPin(s: LockState): number {
  if (!s.tension || s.status !== 'play') return -1;
  const next = s.order[s.setOrder.length];
  return next === undefined ? -1 : next;
}

function dropAll(s: LockState, events: LockEvent[]) {
  let count = 0;
  for (const p of s.pins) {
    if (p.set) count++;
    p.set = false;
  }
  s.setOrder = [];
  s.zone = false;
  if (count > 0) events.push({ type: 'drop', count });
}

/** Input: tension on / off. */
export function setTension(s: LockState, on: boolean): LockEvent[] {
  const events: LockEvent[] = [];
  if (s.status !== 'play' || s.tension === on) return events;
  s.tension = on;
  events.push({ type: 'tension', on });
  if (!on) dropAll(s, events);
  return events;
}

/** Input: move the pick by -1 / +1 pin. The pin it leaves falls back unless it is set or binding. */
export function movePick(s: LockState, dir: -1 | 1): LockEvent[] {
  if (s.status !== 'play') return [];
  const next = Math.max(0, Math.min(s.pins.length - 1, s.pick + dir));
  if (next === s.pick) return [];
  s.pick = next;
  s.zone = false;
  s.holdMs = 0;
  return [{ type: 'move', pin: next }];
}

/** Input: W pressed / released. A press nudges the pin up at once (fine control by tapping). */
export function setLifting(s: LockState, on: boolean): LockEvent[] {
  if (s.status !== 'play' || s.lifting === on) return [];
  s.lifting = on;
  s.holdMs = 0;
  if (!on) return [];
  return liftBy(s, NUDGE, NUDGE / 0.05);
}

export function setLowering(s: LockState, on: boolean) {
  if (s.status !== 'play') return;
  s.lowering = on;
}

/** Move the pin under the pick up by `delta` at `speed` (lift / s); checks click / overset. */
function liftBy(s: LockState, delta: number, speed: number): LockEvent[] {
  const events: LockEvent[] = [];
  const i = s.pick;
  const pin = s.pins[i];
  const before = pin.lift;
  if (pin.set) {
    // a set pin's key pin rises freely to the shear line (the driver is held above it)
    pin.lift = Math.min(pin.need, pin.lift + delta);
    return events;
  }
  const binding = bindingPin(s) === i;
  pin.lift = Math.min(LIFT_MAX, pin.lift + delta);
  if (!binding) {
    if (before < 0.02 && pin.lift >= 0.02) events.push({ type: 'spring', pin: i });
    return events;
  }
  if (before < pin.need && pin.lift >= pin.need) {
    if (speed > MAX_SET_SPEED) {
      s.status = 'snapped';
      events.push({ type: 'overset', pin: i, reason: 'fast' });
      return events;
    }
    s.zone = true;
    events.push({ type: 'click', pin: i });
  }
  if (pin.lift > pin.need + OVERSET) {
    s.status = 'snapped';
    events.push({ type: 'overset', pin: i, reason: 'far' });
  }
  return events;
}

/** Advance the simulation by dt ms. */
export function step(s: LockState, dtMs: number): LockEvent[] {
  if (s.status !== 'play') return [];
  const dt = Math.max(0, Math.min(60, dtMs)) / 1000;
  const events: LockEvent[] = [];
  const binding = bindingPin(s);
  const cur = s.pins[s.pick];

  if (s.lifting) {
    s.holdMs += dtMs;
    const ramp = Math.min(1, s.holdMs / RAMP_MS);
    let speed = SPEED_START + (SPEED_END - SPEED_START) * ramp * ramp;
    if (binding === s.pick) speed *= BIND_FACTOR;
    s.speed = speed;
    events.push(...liftBy(s, speed * dt, speed));
    if (s.status !== 'play') return events;
  } else if (s.lowering) {
    s.speed = 0;
    cur.lift = Math.max(0, cur.lift - LOWER_SPEED * dt);
    if (s.zone && cur.lift < cur.need - SET_EARLY) s.zone = false;
  } else {
    s.speed = 0;
    // released: the binding pin in its set zone sets
    if (binding === s.pick && !cur.set && cur.lift >= cur.need - SET_EARLY && cur.lift <= cur.need + OVERSET) {
      cur.set = true;
      s.zone = false;
      s.setOrder.push(s.pick + 1);
      events.push({ type: 'set', pin: s.pick });
      if (s.setOrder.length === s.pins.length) {
        s.status = 'open';
        events.push({ type: 'open' });
        return events;
      }
    }
  }

  // springs: free pins fall back; the binding pin is held by friction (under tension)
  const bindNow = bindingPin(s);
  s.pins.forEach((p, i) => {
    const held = i === s.pick && (s.lifting || s.lowering);
    if (held || p.lift <= 0) return;
    if (!p.set && i === bindNow) return; // friction holds the binding pin where it was left
    p.lift = Math.max(0, p.lift - SPRING_SPEED * dt);
  });
  return events;
}

/** Display offsets of a pin: key pin lift and driver pin lift (a set driver stays at the shear line). */
export function pinOffsets(p: PinState): { key: number; driver: number } {
  if (p.set) return { key: p.lift, driver: p.need };
  return { key: p.lift, driver: p.lift };
}
