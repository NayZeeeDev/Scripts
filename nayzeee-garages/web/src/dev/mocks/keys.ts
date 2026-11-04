/**
 * Key ring mocks (browser dev only). Scenarios (?mock=<id>):
 *   keys-physical   many keys: owned key / fob items, a shared garage car, temporary keys, a
 *                   key item of someone else's car, a vehicle on the tow truck
 *   keys-virtual    virtual mode, the owner's car selected: key holders with Revoke
 *   keys-temp       a hotwired car selected: temporary key counting down (under 10 minutes)
 *   keys-tracking   a high-end car across town located: live tracker readout, alarm sounding
 *   keys-range      a car 46 m away with a plain key: pressing Lock gets the server's range answer
 *   keys-share      a key item selected (Hand over opens the share picker)
 *   keys-towing     the selected car is on the impound tow truck
 *   keys-empty      no keys at all
 * Stateful handlers answer keys:* like the server would (range rules, alarm cooldown, holders).
 */
import { registerMock } from '../registry';
import { emitNuiMessage, mockNui, onNuiMessage } from '../../lib/nui';
import { defaultInterface } from '../../lib/store';
import type { KeyEntry, KeyHolder, KeyRingPlayer, KeysOpenData, NuiMessage } from '../../lib/types';
import { joaat, modelInfo } from './garage';

const clone = <T>(v: T): T => JSON.parse(JSON.stringify(v)) as T;
const H = 3600;

const RANGES = { key: 5, fob: 30, give: 3 };

interface KeyOpts extends Partial<KeyEntry> {
  make?: string;
}

function key(model: string, label: string, make: string, plate: string, extra: KeyOpts = {}): KeyEntry {
  const highend = extra.profile === 'highend';
  return {
    label,
    make,
    image: model,
    ...modelInfo(model),
    plate,
    model,
    hash: joaat(model),
    vehicleType: 'car',
    nickname: null,
    kind: 'item',
    group: 'owned',
    keyType: highend ? 'fob' : 'key',
    profile: highend ? 'highend' : 'standard',
    profileLabel: highend ? 'High-end' : 'Standard',
    remote: highend,
    expiresIn: null,
    reason: null,
    isOwner: true,
    spawned: false,
    netId: null,
    locked: null,
    distance: null,
    tracker: highend,
    trackable: false,
    towing: false,
    alarm: false,
    canShare: true,
    holders: null,
    ...extra,
  };
}

function physical(): KeysOpenData {
  return {
    mode: 'physical',
    ranges: RANGES,
    tracker: true,
    nearbyPlayers: [],
    keys: [
      key('jester4', 'Jester RR', 'Dinka', '52MZL952', { kind: 'item', spawned: true, netId: 101, locked: true, distance: 4 }),
      key('italigto', 'Itali GTO', 'Grotti', 'GTO 88', {
        kind: 'fob',
        profile: 'highend',
        nickname: 'Red Rocket',
        spawned: true,
        netId: 102,
        locked: false,
        distance: 1240,
        trackable: true,
      }),
      key('kuruma', 'Kuruma', 'Karin', 'KRM 404', { kind: 'item', spawned: false }),
      key('elegy', 'Elegy Retro Custom', 'Annis', 'RETRO 6', {
        kind: 'item',
        nickname: 'Rusty',
        spawned: true,
        netId: 103,
        locked: true,
        distance: 46,
      }),
      key('baller7', 'Baller ST', 'Gallivanter', 'FAM 2024', {
        kind: 'owner',
        group: 'shared',
        isOwner: false,
        canShare: false,
        spawned: true,
        netId: 104,
        locked: true,
        distance: null,
      }),
      key('asea', 'Asea', 'Declasse', '83YBY323', {
        kind: 'temp',
        group: 'temp',
        isOwner: false,
        canShare: false,
        expiresIn: 23 * H + 12 * 60,
        reason: 'hotwire',
        spawned: true,
        netId: 105,
        locked: false,
        distance: 12,
      }),
      key('sultan2', 'Sultan Classic', 'Karin', 'MESA RS', {
        kind: 'temp',
        group: 'temp',
        isOwner: false,
        canShare: false,
        expiresIn: 7 * 60 + 41,
        reason: 'robbery',
        spawned: true,
        netId: 106,
        locked: false,
        distance: 230,
      }),
      key('buffalo4', 'Buffalo STX', 'Bravado', 'LSPD 11', {
        kind: 'temp',
        group: 'temp',
        isOwner: false,
        canShare: false,
        expiresIn: 5 * H,
        reason: 'spawner',
        spawned: false,
      }),
      key('neon', 'Neon', 'Pfister', 'NEON 7', {
        kind: 'fob',
        group: 'items',
        isOwner: false,
        profile: 'highend',
        spawned: false,
        trackable: false,
      }),
      key('vigero2', 'Vigero ZX', 'Declasse', 'VGR 22', {
        kind: 'item',
        towing: true,
        spawned: true,
        netId: 107,
        locked: true,
        distance: 88,
      }),
    ],
  };
}

function virtual(): KeysOpenData {
  return {
    mode: 'virtual',
    ranges: RANGES,
    tracker: true,
    nearbyPlayers: [],
    keys: [
      key('torero2', 'Torero XO', 'Pegassi', 'XO 1', {
        kind: 'owner',
        profile: 'highend',
        nickname: 'Midnight',
        spawned: true,
        netId: 201,
        locked: true,
        distance: 18,
        trackable: true,
        holders: 3,
      }),
      key('schafter3', 'Schafter V12', 'Benefactor', 'SCH 12', { kind: 'owner', spawned: false }),
      key('rebla', 'Rebla GTS', 'Übermacht', 'FAM 7', { kind: 'owner', spawned: true, netId: 202, locked: false, distance: 7 }),
      key('comet7', 'Comet S2', 'Pfister', 'CMT 911', {
        kind: 'virtual',
        group: 'shared',
        isOwner: false,
        canShare: false,
        profile: 'highend',
        spawned: true,
        netId: 203,
        locked: true,
        distance: 640,
        trackable: true,
      }),
      key('granger2', 'Granger 3600LX', 'Declasse', 'GR 3600', {
        kind: 'owner',
        group: 'shared',
        isOwner: false,
        canShare: false,
        spawned: false,
      }),
      key('panto', 'Panto', 'Benefactor', 'PANTO 1', {
        kind: 'temp',
        group: 'temp',
        isOwner: false,
        canShare: false,
        expiresIn: 2 * H + 40 * 60,
        reason: 'garage',
        spawned: true,
        netId: 204,
        locked: false,
        distance: 3,
      }),
    ],
  };
}

const HOLDERS: Record<string, KeyHolder[]> = {
  'XO 1': [
    { identifier: 'CID-AVA', name: 'Ava Brooks', kind: 'virtual', grantedBy: 'NZV41207', agoSeconds: 3 * 86400, expiresIn: null },
    { identifier: 'CID-LENA', name: 'Lena Ortiz', kind: 'virtual', grantedBy: 'NZV41207', agoSeconds: 2 * H, expiresIn: null },
    { identifier: 'CID-SAM', name: 'Sam Carter', kind: 'temp', grantedBy: null, agoSeconds: 25 * 60, expiresIn: 23 * H + 35 * 60 },
  ],
};

const PLAYERS: KeyRingPlayer[] = [
  { serverId: 12, name: 'Lena Ortiz', distance: 1.4 },
  { serverId: 41, name: 'Sam Carter', distance: 2.6 },
];

let current: KeysOpenData | null = null;
let holders: Record<string, KeyHolder[]> = clone(HOLDERS);
const alarmUntil: Record<string, number> = {};

onNuiMessage((msg) => {
  if (msg.action === 'open' && msg.data.app === 'keys') {
    current = clone(msg.data.data as KeysOpenData);
    holders = clone(HOLDERS);
  }
  if (msg.action === 'update' && msg.data.app === 'keys' && current) current = { ...current, ...(msg.data.data as Partial<KeysOpenData>) };
});

const find = (plate: string) => current?.keys.find((k) => k.plate === plate) ?? null;
const update = (data: Partial<KeysOpenData>) => emitNuiMessage({ action: 'update', data: { app: 'keys', data } });

mockNui('keys:refresh', () => (current ? { ...clone(current), focus: null } : { ok: false, error: 'Nothing open' }));

mockNui('keys:lock', ({ plate }) => {
  const k = find(plate);
  if (!k) return { ok: false, error: 'You do not have the keys of this vehicle' };
  if (k.towing) return { ok: false, error: 'This vehicle is being towed' };
  if (!k.spawned) return { ok: false, error: 'The vehicle is not out' };
  const range = k.remote ? RANGES.fob : RANGES.key;
  if (k.distance === null || k.distance > range) return { ok: false, error: 'The vehicle is too far away' };
  k.locked = !k.locked;
  return { plate, locked: k.locked };
});

mockNui('keys:locate', ({ plate, stop }) => {
  const k = find(plate);
  if (stop) {
    update({ tracking: { plate, distance: null, live: false, stopped: true } });
    return { distance: null };
  }
  if (!k || !k.trackable) return { ok: false, error: 'This vehicle has no tracker' };
  window.setTimeout(() => update({ tracking: { plate, distance: k.distance, live: false } }), 300);
  return { distance: k.distance };
});

mockNui('keys:alarm', ({ plate }) => {
  const k = find(plate);
  if (!k || !k.trackable) return { ok: false, error: 'This vehicle has no tracker' };
  if (k.alarm) {
    k.alarm = false;
    return { alarm: false, seconds: null, cooldown: Math.max(0, Math.ceil(((alarmUntil[plate] ?? 0) - Date.now()) / 1000)) };
  }
  const left = Math.ceil(((alarmUntil[plate] ?? 0) - Date.now()) / 1000);
  if (left > 0) return { ok: false, error: `The alarm can be triggered again in ${left} s` };
  k.alarm = true;
  alarmUntil[plate] = Date.now() + 60000;
  return { alarm: true, seconds: 20, cooldown: 60 };
});

mockNui('keys:players', () => clone(PLAYERS));
mockNui('keys:share', ({ target }) =>
  PLAYERS.some((p) => p.serverId === target) ? null : { ok: false, error: 'That player is too far away' },
);
mockNui('keys:holders', ({ plate }) => clone(holders[plate] ?? []));
mockNui('keys:revoke', ({ plate, identifier }) => {
  holders[plate] = (holders[plate] ?? []).filter((h) => h.identifier !== identifier);
  return clone(holders[plate]);
});

/* ── scenarios ─────────────────────────────────────────────────────── */

const init: NuiMessage = {
  action: 'init',
  data: { locale: {}, settings: { ...defaultInterface, distanceUnit: 'km' }, resource: 'nayzeee-garages' },
};
const open = (data: KeysOpenData): NuiMessage => ({ action: 'open', data: { app: 'keys', data } });

registerMock({ id: 'keys-physical', group: 'Key ring', label: 'Physical keys (many)', messages: [init, open(physical())] });

registerMock({
  id: 'keys-virtual',
  group: 'Key ring',
  label: 'Virtual keys · holders',
  messages: [init, open({ ...virtual(), focus: 'XO 1' })],
});

registerMock({
  id: 'keys-temp',
  group: 'Key ring',
  label: 'Temporary key countdown',
  messages: [init, open({ ...physical(), focus: 'MESA RS' })],
});

const tracked = (): KeysOpenData => {
  const d = physical();
  const k = d.keys.find((x) => x.plate === 'GTO 88')!;
  k.alarm = true;
  return { ...d, focus: 'GTO 88' };
};
registerMock({
  id: 'keys-tracking',
  group: 'Key ring',
  label: 'Tracker: located, alarm',
  messages: [
    init,
    open(tracked()),
    { action: 'update', data: { app: 'keys', data: { tracking: { plate: 'GTO 88', distance: 1187, live: false } } } },
  ],
});

registerMock({
  id: 'keys-range',
  group: 'Key ring',
  label: 'Out of range answer',
  messages: [init, open({ ...physical(), focus: 'RETRO 6' })],
});

registerMock({
  id: 'keys-share',
  group: 'Key ring',
  label: 'Hand over a key item',
  messages: [init, open({ ...physical(), focus: 'KRM 404' })],
});

registerMock({
  id: 'keys-towing',
  group: 'Key ring',
  label: 'Vehicle on the tow truck',
  messages: [init, open({ ...physical(), focus: 'VGR 22' })],
});

registerMock({
  id: 'keys-empty',
  group: 'Key ring',
  label: 'Empty key ring',
  messages: [init, open({ mode: 'physical', ranges: RANGES, tracker: true, nearbyPlayers: [], keys: [] })],
});
