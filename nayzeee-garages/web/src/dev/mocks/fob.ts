/**
 * Mock scenarios for the fob app (browser dev only, ?mock=<id>):
 *   fob-hud          the fob after locking (lock button lit, no prompts)
 *   fob-holding      the key in your hand: side prompts Throw / Inspect / Move / Help / Close,
 *                    the buttons press in turn (unlock, trunk, panic with beep)
 *   fob-left         a plain metal key held on the left of the screen (prompts on the right)
 *   fob-edit         edit mode: drag / resize, prompts toggle, Reset / Save
 *   fob-help         the controls help
 *   fob-inspect-ground   a key on the ground: Keep / Return to ground
 *   fob-inspect-temp     an NPC's dropped key (temporary key), unknown make
 *   fob-inspect-carried  a back-alley fob you carry, cut for old locks
 * The handlers answer fob:* like client/carlock/fob.lua (cancel returns to the HUD, save keeps
 * the layout, keep / return close the card).
 */
import type { FobHudData, FobHudKey, FobInspect, FobLayout, NuiMessage } from '../../lib/types';
import { registerMock } from '../registry';
import { emitNuiMessage, mockNui } from '../../lib/nui';

const DEFAULTS: FobLayout = { x: 0.86, y: 0.72, scale: 1 };
const KEYS = { throw: 'T', inspect: 'I', move: 'M', help: 'H', close: 'ESC' };

const jester: FobHudKey = { plate: '46EEK572', label: 'Dinka Jester RR', make: 'DINKA', design: 'classic', kind: 'fob', locked: true };
const tenF: FobHudKey = { plate: 'NZ 4210', label: 'Obey 10F Widebody', make: 'Obey', design: 'luxury', kind: 'fob', locked: false };
const emperor: FobHudKey = { plate: 'OLD 77', label: 'Albany Emperor', make: 'ALBANY', design: 'key', kind: 'key', locked: false };

let state: FobHudData = base(jester);


function base(key: FobHudKey, extra: Partial<FobHudData> = {}): FobHudData {
  return { mode: 'hud', key, layout: { ...DEFAULTS }, defaults: DEFAULTS, holding: false, keys: KEYS, press: null, inspect: null, ...extra };
}

function open(data: FobHudData): NuiMessage {
  return { action: 'open', data: { app: 'fob', data } };
}

function push(partial: Partial<FobHudData>) {
  state = { ...state, ...partial };
  emitNuiMessage({ action: 'update', data: { app: 'fob', data: partial } });
}

let seq = 1;
const press = (button: 'lock' | 'unlock' | 'trunk' | 'panic', beep = false) => ({ button, seq: seq++, beep });

registerMock({
  id: 'fob-hud',
  group: 'Fob HUD',
  label: 'Fob after locking (lock lit)',
  messages: [open(base(jester, { press: press('lock') }))],
});

registerMock({
  id: 'fob-holding',
  group: 'Fob HUD',
  label: 'Key in hand: side prompts, presses',
  messages: [open(base(tenF, { holding: true, layout: { x: 0.84, y: 0.6, scale: 1.1 } }))],
});

registerMock({
  id: 'fob-left',
  group: 'Fob HUD',
  label: 'Plain key held on the left',
  messages: [open(base(emperor, { holding: true, layout: { x: 0.1, y: 0.55, scale: 1 } }))],
});

registerMock({
  id: 'fob-edit',
  group: 'Fob HUD',
  label: 'Edit mode (move / resize / prompts)',
  messages: [open(base(jester, { mode: 'edit', holding: true, layout: { x: 0.8, y: 0.42, scale: 1.15 } }))],
});

registerMock({
  id: 'fob-help',
  group: 'Fob HUD',
  label: 'Controls help',
  messages: [open(base(tenF, { mode: 'help', holding: true }))],
});

const groundKey: FobInspect = {
  source: 'ground', id: 'a1b2c3d4e5f6', plate: '46EEK572', vehicle: 'Dinka Jester RR', keyLabel: 'Vehicle fob 46EEK572',
  make: 'DINKA', design: 'sport', kind: 'fob', droppedAgo: 420,
};
const tempKey: FobInspect = {
  source: 'ground', id: 'ffee0011aabb', plate: '82KLM301', vehicle: '', keyLabel: 'Vehicle key 82KLM301',
  make: '', design: 'key', kind: 'key', temp: true, droppedAgo: 35,
};
const carriedKey: FobInspect = {
  source: 'carried', plate: 'NZ 4210', vehicle: 'Übermacht Zion Classic', keyLabel: 'Vehicle fob NZ 4210',
  make: 'Übermacht', design: 'leather', kind: 'fob', valid: false, origin: 'locksmith',
};

registerMock({ id: 'fob-inspect-ground', group: 'Fob HUD', label: 'Inspect: key on the ground', messages: [open(base(jester, { mode: 'inspect', inspect: groundKey }))] });
registerMock({ id: 'fob-inspect-temp', group: 'Fob HUD', label: "Inspect: an NPC's key (temporary)", messages: [open(base(jester, { mode: 'inspect', inspect: tempKey }))] });
registerMock({ id: 'fob-inspect-carried', group: 'Fob HUD', label: 'Inspect: back-alley fob, old locks', messages: [open(base(tenF, { mode: 'inspect', holding: true, inspect: carriedKey }))] });

// presses while holding (fob-holding): unlock, trunk, panic (beep), then lock
let timer: number | undefined;
window.addEventListener('message', (e: MessageEvent) => {
  const msg = e.data as NuiMessage | undefined;
  if (!msg || msg.action !== 'open' || msg.data.app !== 'fob') return;
  window.clearInterval(timer);
  const data = msg.data.data as FobHudData;
  state = data;
  if (!data.holding || data.mode !== 'hud') return;
  const order = ['unlock', 'trunk', 'panic', 'lock'] as const;
  let i = 0;
  timer = window.setInterval(() => {
    if (state.mode !== 'hud') return;
    push({ press: press(order[i % order.length], order[i % order.length] === 'panic') });
    i += 1;
  }, 1600);
});

mockNui('fob:cancel', () => {
  push({ mode: 'hud', inspect: null });
  return null;
});
mockNui('fob:save', (layout) => {
  push({ mode: 'hud', layout });
  return layout;
});
mockNui('fob:action', ({ action }) => {
  if (action === 'help') push({ mode: 'help' });
  if (action === 'inspect') push({ mode: 'inspect', inspect: carriedKey });
  if (action === 'throw') push({ mode: 'hud' });
  return null;
});
mockNui('fob:keep', () => {
  push({ mode: 'hud', inspect: null });
  return null;
});
mockNui('fob:return', () => {
  push({ mode: 'hud', inspect: null });
  return null;
});
