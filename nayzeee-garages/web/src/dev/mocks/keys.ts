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
 *   keys-hotwired   a hotwired high-end car: the tracker is fitted, but a crime key has no access
 *   keys-backalley  a fob cut by a back-alley locksmith: it opens the car, no tracker, no nickname
 *   keys-names      the share picker of a server with character names on (sharePicker.names)
 *   keys-empty      no keys at all
 *   keys-settings   the Settings tab (player key settings)
 *   keys-track      the track vehicle modal over the ring (live, then the tracker's position)
 *   keys-track-none the track modal of a car without a tracker
 *   keys-give       the give keys picker on its own (fob HUD Give)
 *   keys-inspect-ground   a key on the ground looked at: Keep / Return to ground
 *   keys-inspect-carried  a key item you carry, cut for old locks
 *   keys-pin-enter  the Ghost PIN pad as the driver (PIN 1234; wrong guesses count down)
 *   keys-pin-cooldown     the pad during the wrong-PIN cooldown
 *   keys-pin-set    the owner changes the Ghost PIN (current PIN 1234 first)
 *   keys-access     the owner's key access list (virtual mode)
 * Stateful handlers answer keys:* like the server would (range rules as refused = 'range',
 * alarm cooldown as refused = 'cooldown', holders by opaque id with a masked thief).
 */
import { registerMock } from '../registry';
import { emitNuiMessage, mockNui, onNuiMessage } from '../../lib/nui';
import { defaultInterface } from '../../lib/store';
import type {
  KeyEntry,
  KeyHolder,
  KeyRingPlayer,
  KeysOpenData,
  KeyTrackData,
  NuiMessage,
  PlayerKeySettings,
  PlayerKeySettingsData,
} from '../../lib/types';
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
    trackerAccess: true,
    trackable: false,
    towing: false,
    alarm: false,
    canShare: true,
    holders: null,
    design: highend ? 'sport' : 'classic',
    immobiliser: 'none',
    engine: extra.spawned ? false : null,
    usedAt: null,
    slot: extra.kind === 'item' || extra.kind === 'fob' ? (slotSeq += 1) : null,
    keyId: extra.kind === 'item' || extra.kind === 'fob' ? `k${slotSeq}` : null,
    ...extra,
  };
}
let slotSeq = 0;
const NOW = Math.floor(Date.now() / 1000);

function physical(): KeysOpenData {
  return {
    mode: 'physical',
    keyMode: 'flexible',
    prefs: { keyOrder: 'recent', units: 'metric' },
    ranges: RANGES,
    tracker: true,
    closeKey: 'F7',
    nearbyPlayers: [],
    keys: [
      key('jester4', 'Jester RR', 'Dinka', '52MZL952', { kind: 'item', spawned: true, netId: 101, locked: true, distance: 4, usedAt: NOW - 300 }),
      key('italigto', 'Itali GTO', 'Grotti', 'GTO 88', {
        kind: 'fob',
        profile: 'highend',
        nickname: 'Red Rocket',
        spawned: true,
        netId: 102,
        locked: false,
        distance: 1240,
        trackable: true,
        engine: true,
        immobiliser: 'ghost',
        design: 'luxury',
        usedAt: NOW - 1200,
      }),
      key('kuruma', 'Kuruma', 'Karin', 'KRM 404', { kind: 'item', spawned: false }),
      key('elegy', 'Elegy Retro Custom', 'Annis', 'RETRO 6', {
        kind: 'item',
        nickname: 'Rusty',
        spawned: true,
        netId: 103,
        locked: true,
        distance: 46,
        usedAt: NOW - 86400,
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
      key('zentorno', 'Zentorno', 'Pegassi', 'HOT 666', {
        kind: 'temp',
        group: 'temp',
        profile: 'highend',
        isOwner: false,
        canShare: false,
        expiresIn: 3 * H + 5 * 60,
        reason: 'hotwire',
        spawned: true,
        netId: 108,
        locked: false,
        distance: 34,
        // a crime key: the tracker is fitted but out of reach
        trackerAccess: false,
        trackable: false,
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
      key('pariah', 'Pariah', 'Ocelot', 'DEN 404', {
        kind: 'fob',
        group: 'items',
        isOwner: false,
        profile: 'highend',
        // cut by a back-alley locksmith: it opens the car, the tracker stays the owner's
        reason: 'locksmith',
        trackerAccess: false,
        trackable: false,
        spawned: true,
        netId: 109,
        locked: true,
        distance: 21,
        design: 'card',
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
    keyMode: 'virtual',
    prefs: { keyOrder: 'name', units: 'metric' },
    ranges: RANGES,
    tracker: true,
    closeKey: 'F7',
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
        holders: 4,
        immobiliser: 'ghost',
        design: 'slim',
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

// ids are opaque server tokens: identifiers never reach the interface
const HOLDERS: Record<string, KeyHolder[]> = {
  'XO 1': [
    { id: '3f9a1c07b2e4', name: 'Ava Brooks', kind: 'virtual', reason: null, masked: false, agoSeconds: 3 * 86400, expiresIn: null },
    { id: '81d0e6a95c3b', name: 'Lena Ortiz', kind: 'virtual', reason: null, masked: false, agoSeconds: 2 * H, expiresIn: null },
    { id: 'c47b20f1d8a6', name: 'Sam Carter', kind: 'temp', reason: 'garage', masked: false, agoSeconds: 40 * 60, expiresIn: 2 * H + 20 * 60 },
    // a hotwired key: the owner sees how it was obtained, never who holds it
    { id: '0e5d93b7a1f2', name: 'Unknown holder', kind: 'temp', reason: 'hotwire', masked: true, agoSeconds: 25 * 60, expiresIn: 23 * H + 35 * 60 },
  ],
};

// the server sends no names of strangers by default (Config.CarLock.sharePicker.names = false)
const ANONYMOUS: KeyRingPlayer[] = [
  { serverId: 12, name: 'Player 12', anonymous: true, distance: 1.4 },
  { serverId: 41, name: 'Player 41', anonymous: true, distance: 2.6 },
];
const NAMED: KeyRingPlayer[] = [
  { serverId: 12, name: 'Lena Ortiz', distance: 1.4 },
  { serverId: 41, name: 'Sam Carter', distance: 2.6 },
];
let players: KeyRingPlayer[] = ANONYMOUS;

let current: KeysOpenData | null = null;
let holders: Record<string, KeyHolder[]> = clone(HOLDERS);
const alarmUntil: Record<string, number> = {};

onNuiMessage((msg) => {
  if (msg.action === 'open' && msg.data.app === 'keys') {
    current = clone(msg.data.data as KeysOpenData);
    holders = clone(HOLDERS);
    // a scenario may bring its own share picker answer (keys-names)
    players = current.nearbyPlayers.length ? current.nearbyPlayers : ANONYMOUS;
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
  // out of range is the server's answer, not an error
  if (k.distance === null || k.distance > range) return { plate, refused: 'range', message: 'The vehicle is too far away' };
  k.locked = !k.locked;
  return { plate, locked: k.locked };
});

mockNui('keys:locate', ({ plate, stop }) => {
  const k = find(plate);
  if (stop) {
    update({ tracking: { plate, distance: null, live: false, stopped: true } });
    return { distance: null };
  }
  if (!k || !k.tracker) return { ok: false, error: 'This vehicle has no tracker' };
  if (!k.trackerAccess) return { ok: false, error: 'This key has no tracker access' };
  if (!k.trackable) return { ok: false, error: 'The vehicle is not out' };
  window.setTimeout(() => update({ tracking: { plate, distance: k.distance, live: false } }), 300);
  return { distance: k.distance };
});

mockNui('keys:alarm', ({ plate }) => {
  const k = find(plate);
  if (!k || !k.tracker) return { ok: false, error: 'This vehicle has no tracker' };
  if (!k.trackerAccess) return { ok: false, error: 'This key has no tracker access' };
  if (!k.trackable) return { ok: false, error: 'The vehicle is not out' };
  if (k.alarm) {
    k.alarm = false;
    return { alarm: false, seconds: null, cooldown: Math.max(0, Math.ceil(((alarmUntil[plate] ?? 0) - Date.now()) / 1000)) };
  }
  const left = Math.ceil(((alarmUntil[plate] ?? 0) - Date.now()) / 1000);
  if (left > 0) {
    return { alarm: false, seconds: null, cooldown: left, refused: 'cooldown', message: `The alarm can be triggered again in ${left} s` };
  }
  k.alarm = true;
  alarmUntil[plate] = Date.now() + 60000;
  return { alarm: true, seconds: 20, cooldown: 60 };
});

mockNui('keys:players', () => clone(players));
mockNui('keys:share', ({ target }) =>
  players.some((p) => p.serverId === target) ? null : { ok: false, error: 'That player is too far away' },
);
mockNui('keys:holders', ({ plate }) => clone(holders[plate] ?? []));
mockNui('keys:revoke', ({ plate, id }) => {
  const list = holders[plate] ?? [];
  if (!list.some((h) => h.id === id)) return { ok: false, error: 'The key holder list is out of date: refresh it' };
  holders[plate] = list.filter((h) => h.id !== id);
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
  id: 'keys-hotwired',
  group: 'Key ring',
  label: 'Hotwired: no tracker access',
  messages: [init, open({ ...physical(), focus: 'HOT 666' })],
});

registerMock({
  id: 'keys-backalley',
  group: 'Key ring',
  label: 'Back-alley key: no tracker',
  messages: [init, open({ ...physical(), focus: 'DEN 404' })],
});

registerMock({
  id: 'keys-names',
  group: 'Key ring',
  label: 'Share picker with names',
  messages: [init, open({ ...physical(), focus: 'KRM 404', nearbyPlayers: NAMED })],
});

registerMock({
  id: 'keys-empty',
  group: 'Key ring',
  label: 'Empty key ring',
  messages: [init, open({ mode: 'physical', ranges: RANGES, tracker: true, nearbyPlayers: [], keys: [] })],
});

/* ── car lock v2: remote, track, inspect, drop, settings, Ghost PIN ── */

const POS: Record<string, { x: number; y: number; heading: number; street: string; area: string }> = {
  'GTO 88': { x: -612.4, y: -1095.2, heading: 82, street: 'Vespucci Boulevard', area: 'Little Seoul' },
  '52MZL952': { x: 212.4, y: -806.1, heading: 160, street: 'San Andreas Avenue', area: 'Pillbox Hill' },
  'XO 1': { x: 221.9, y: -790.3, heading: 250, street: 'Alta Street', area: 'Pillbox Hill' },
  'CMT 911': { x: -1215.6, y: -1460.8, heading: 300, street: 'Del Perro Freeway', area: 'Vespucci Beach' },
};
const ME = { x: 215.2, y: -810.4 };

mockNui('keys:remote', ({ plate, action, on }) => {
  const k = find(plate);
  if (!k || !k.spawned) return { ok: false, error: 'The vehicle of this key is not nearby' };
  if (k.kind === 'item') return { ok: false, error: 'You need the fob of this vehicle' };
  if (k.distance === null || k.distance > RANGES.fob) return { action, on, plate, refused: 'range', message: 'The vehicle is too far away' };
  if (action === 'engine' && on && k.immobiliser === 'ghost') return { ok: false, error: 'Remote start is disabled by the immobiliser' };
  if (action === 'engine') k.engine = on;
  return { action, on, plate };
});

mockNui('keys:track', ({ plate }) => {
  const k = find(plate);
  const pos = POS[plate];
  const base = {
    plate,
    model: k?.model ?? 'italigto',
    hash: k?.hash ?? joaat('italigto'),
    label: k?.label ?? 'Itali GTO',
    make: k?.make ?? 'Grotti',
    image: k?.image ?? 'italigto',
    nickname: k?.nickname ?? null,
    profileLabel: k?.profileLabel ?? 'High-end',
    tracker: k?.tracker ?? true,
    trackerAccess: k?.trackerAccess ?? true,
    spawned: k?.spawned ?? true,
    towing: k?.towing ?? false,
    locked: k?.locked ?? true,
    engine: k?.engine ?? false,
    alarm: k?.alarm ?? false,
    immobiliser: k?.immobiliser ?? 'ghost',
    me: ME,
  };
  const trackable = !!k && k.trackable && !!pos;
  if (!trackable) {
    const reason: KeyTrackData['reason'] = !base.tracker ? 'notracker' : !base.trackerAccess ? 'noaccess' : base.towing ? 'towing' : 'notout';
    return { ...base, trackable: false, coords: null, heading: null, street: null, area: null, distance: null, live: false, reason };
  }
  // drift a little each poll: the marker moves
  pos.x += Math.cos((pos.heading * Math.PI) / 180) * 6;
  pos.y += Math.sin((pos.heading * Math.PI) / 180) * 6;
  const distance = Math.round(Math.hypot(pos.x - ME.x, pos.y - ME.y));
  return {
    ...base,
    trackable: true,
    coords: { x: pos.x, y: pos.y, z: 30 },
    heading: pos.heading,
    street: pos.street,
    area: pos.area,
    distance,
    live: distance < 300,
    reason: null,
  } satisfies KeyTrackData;
});

mockNui('keys:inspect', ({ plate }) => {
  const k = find(plate);
  if (!k) return { ok: false, error: 'You do not carry this key' };
  return {
    plate,
    keyKind: k.keyType,
    keyLabel: k.keyType === 'fob' ? `Fob · ${plate}` : `Key · ${plate}`,
    model: k.model,
    hash: k.hash,
    label: k.label,
    make: k.make,
    image: k.image,
    design: k.design ?? 'classic',
    kind: 'item',
    valid: true,
    reason: null,
    origin: k.reason === 'locksmith' || k.reason === 'search' ? k.reason : null,
  };
});

mockNui('keys:drop', ({ plate }) => {
  if (!current) return { ok: false, error: 'Nothing open' };
  current.keys = current.keys.filter((k) => k.plate !== plate);
  return { plate };
});
mockNui('keys:leave', ({ plate }) => {
  if (!current) return { ok: false, error: 'Nothing open' };
  current.keys = current.keys.filter((k) => k.plate !== plate);
  return null;
});
mockNui('keys:groundKeep', ({ id }) => {
  window.setTimeout(() => emitNuiMessage({ action: 'close', data: { app: 'keys' } }), 200);
  return { plate: id === 'g1' ? '07CWE819' : 'UNKNOWN' };
});
mockNui('keys:groundReturn', () => null);

const DEFAULTS: PlayerKeySettings = {
  keylessUnlock: true,
  keylessLock: true,
  keylessDistance: 10,
  engineOnEnter: false,
  keepEngineRunning: true,
  fobBeep: true,
  hints: true,
  fobPosition: { x: 0.86, y: 0.72, scale: 1 },
  keyOrder: 'recent',
  combinedKeyring: true,
  groundPrompts: true,
  units: 'metric',
  alertLock: true,
  alertEngine: true,
  alertShare: true,
  shareRecall: true,
};
let mySettings: PlayerKeySettings = { ...DEFAULTS, engineOnEnter: true, keylessDistance: 6 };
const settingsData = (): PlayerKeySettingsData => ({
  settings: clone(mySettings),
  defaults: clone(DEFAULTS),
  limits: { keylessMin: 3, keylessMax: 30 },
  server: { keyless: true, keepEngineRunning: true, ground: true },
});
mockNui('keys:settings', () => settingsData());
mockNui('keys:saveSettings', ({ settings }) => {
  mySettings = { ...mySettings, ...settings };
  return settingsData();
});

// Ghost PIN: 1234 (three tries, then a 30 s cooldown with the alarm)
let pinTries = 3;
let pinBlockedUntil = 0;
let storedPin = '1234';
mockNui('keys:immobiliser', ({ plate }) => ({ plate, level: 'ghost', pinSet: true, pinRequired: false, cooldown: 0, remoteStart: false }));
mockNui('keys:pinEnter', ({ pin }) => {
  const left = Math.ceil((pinBlockedUntil - Date.now()) / 1000);
  if (left > 0) return { success: false, error: `Too many wrong PINs: wait ${left} s`, cooldown: left };
  if (pin === storedPin) {
    pinTries = 3;
    return { success: true };
  }
  pinTries -= 1;
  if (pinTries <= 0) {
    pinTries = 3;
    pinBlockedUntil = Date.now() + 30000;
    return { success: false, error: 'Wrong PIN', attemptsLeft: 0, cooldown: 30, alarm: true };
  }
  return { success: false, error: 'Wrong PIN', attemptsLeft: pinTries };
});
mockNui('keys:pinSet', ({ plate, pin, oldPin }) => {
  if (oldPin !== storedPin) return { ok: false, error: 'The current PIN is wrong' };
  storedPin = pin;
  return { plate, level: 'ghost', pinSet: true, pinRequired: false, cooldown: 0, remoteStart: false };
});
mockNui('keys:pinDone', () => null);

const alone = (dialog: KeysOpenData['dialog'], extra: Partial<KeysOpenData> = {}): NuiMessage =>
  open({ mode: 'physical', keyMode: 'flexible', ranges: RANGES, tracker: true, nearbyPlayers: [], keys: [], view: 'dialog', dialog, ...extra });

registerMock({ id: 'keys-settings', group: 'Key ring', label: 'Settings tab', messages: [init, open({ ...physical(), view: 'settings' })] });

registerMock({
  id: 'keys-track',
  group: 'Key ring',
  label: 'Track vehicle (live map)',
  messages: [init, open({ ...physical(), focus: 'GTO 88' }), { action: 'update', data: { app: 'keys', data: { dialog: { kind: 'track', plate: 'GTO 88' } } } }],
});

registerMock({
  id: 'keys-track-none',
  group: 'Key ring',
  label: 'Track: no tracker fitted',
  messages: [init, open({ ...physical(), focus: '52MZL952' }), { action: 'update', data: { app: 'keys', data: { dialog: { kind: 'track', plate: '52MZL952' } } } }],
});

registerMock({
  id: 'keys-give',
  group: 'Key ring',
  label: 'Give keys picker (alone)',
  messages: [init, alone({ kind: 'give', plate: 'KRM 404' }, { keys: physical().keys, nearbyPlayers: NAMED })],
});

registerMock({
  id: 'keys-inspect-ground',
  group: 'Key ring',
  label: 'Inspect a key on the ground',
  messages: [
    init,
    alone({
      kind: 'inspect',
      source: 'ground',
      id: 'g1',
      info: {
        plate: '07CWE819',
        keyKind: 'fob',
        keyLabel: 'Fob · 07CWE819',
        model: 'xls',
        hash: joaat('xls'),
        label: 'XLS',
        make: 'Benefactor',
        image: 'xls',
        design: 'luxury',
        kind: 'item',
        droppedAgo: 95,
      },
    }),
  ],
});

registerMock({
  id: 'keys-inspect-carried',
  group: 'Key ring',
  label: 'Inspect a carried key (old locks)',
  messages: [
    init,
    alone({
      kind: 'inspect',
      source: 'carried',
      info: {
        plate: 'KRM 404',
        keyKind: 'key',
        keyLabel: 'Key · KRM 404',
        model: 'kuruma',
        hash: joaat('kuruma'),
        label: 'Kuruma',
        make: 'Karin',
        image: 'kuruma',
        design: 'key',
        kind: 'item',
        valid: false,
        reason: 'version',
        origin: 'search',
      },
    }),
  ],
});

registerMock({
  id: 'keys-pin-enter',
  group: 'Key ring',
  label: 'Ghost PIN: driver (1234)',
  messages: [init, alone({ kind: 'pin', pad: { id: 7, mode: 'enter', plate: 'GTO 88', vehicle: 'Red Rocket', attemptsLeft: 2, length: 4 } })],
});

registerMock({
  id: 'keys-pin-cooldown',
  group: 'Key ring',
  label: 'Ghost PIN: cooldown',
  messages: [init, alone({ kind: 'pin', pad: { id: 8, mode: 'enter', plate: 'GTO 88', vehicle: 'Red Rocket', cooldown: 42, attemptsLeft: 0, length: 4 } })],
});

registerMock({
  id: 'keys-pin-set',
  group: 'Key ring',
  label: 'Ghost PIN: owner sets it',
  messages: [init, alone({ kind: 'pin', pad: { id: 9, mode: 'set', plate: 'XO 1', vehicle: 'Midnight', pinSet: true, length: 4 } })],
});

registerMock({
  id: 'keys-access',
  group: 'Key ring',
  label: 'Key access (owner, virtual)',
  messages: [init, open({ ...virtual(), focus: 'XO 1' })],
});
