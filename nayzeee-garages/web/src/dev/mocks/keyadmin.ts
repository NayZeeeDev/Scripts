/**
 * Admin key manager mocks (browser dev only). Scenarios (?mock=<id>):
 *   keyadmin-search        empty search page (recently opened players come from localStorage)
 *   keyadmin-results       a search for "ma" with several players and matched plates
 *   keyadmin-noresults     a search nobody matches
 *   keyadmin-player        an online player with many keys (every custody and type, pages)
 *   keyadmin-offline       an offline player (key items cannot be given)
 *   keyadmin-nokeys        a player without any key
 *   keyadmin-plate         the plate view of a high-end car (items, access holders, ground key)
 *   (track dialog: open keyadmin-player and press a row's Track button)
 *   keyadmin-settings      settings, Keys tab (one admin value stored)
 *   keyadmin-ground        settings, Ground keys tab (marker preview, colour + opacity)
 *   keyadmin-npc           settings, NPC keys tab (reaction share)
 *   keyadmin-vehicles      settings, Vehicles tab (classes, model lists)
 * Stateful handlers answer keyadmin:* like the server would: give (item needs the player
 * online), delete, plate, track, settings (all-or-nothing validation, resets).
 */
import { registerMock } from '../registry';
import { mockNui } from '../../lib/nui';
import { defaultInterface } from '../../lib/store';
import type {
  KeyAdminOpenData,
  KeyAdminPlateData,
  KeyAdminPlayer,
  KeyAdminPlayerData,
  KeyAdminRow,
  KeySetting,
  KeySettingValue,
  KeySettings,
  NuiMessage,
} from '../../lib/types';

const clone = <T>(v: T): T => JSON.parse(JSON.stringify(v)) as T;
const now = () => Math.floor(Date.now() / 1000);
const H = 3600;

/* ── players and keys ────────────────────────────────────────────────── */

interface MockPlayer extends Omit<KeyAdminPlayer, 'matchedPlates'> {
  plates: string[];
}

const PLAYERS: MockPlayer[] = [
  { identifier: 'char1:MQ48X2KD', name: 'Mara Quinn', online: true, serverId: 12, plates: ['52MZL952', 'RETRO 6', 'GTO 88', 'NITE 77', 'VGR 22'] },
  { identifier: 'char2:TB90LKE1', name: 'Theo Brandt', online: false, serverId: null, plates: ['FAM 2024', 'TB 4X4'] },
  { identifier: 'char1:IM11ZQ07', name: 'Ivy Moreno', online: true, serverId: 7, plates: ['IVY 7'] },
  { identifier: 'char3:MA77PLX0', name: 'Marcus Adeyemi', online: false, serverId: null, plates: [] },
  { identifier: 'char1:DV03RRA9', name: 'Dmitri Volkov', online: true, serverId: 31, plates: [] },
];

const VEH: Record<string, { model: string; label: string; make: string }> = {
  '52MZL952': { model: 'jester4', label: 'Jester RR', make: 'Dinka' },
  'RETRO 6': { model: 'elegy', label: 'Elegy Retro Custom', make: 'Annis' },
  'GTO 88': { model: 'italigto', label: 'Itali GTO', make: 'Grotti' },
  'NITE 77': { model: 'comet6', label: 'Comet S2', make: 'Pfister' },
  'VGR 22': { model: 'vigero2', label: 'Vigero ZX', make: 'Declasse' },
  'FAM 2024': { model: 'baller7', label: 'Baller ST', make: 'Gallivanter' },
  'TB 4X4': { model: 'sandking', label: 'Sandking XL', make: 'Vapid' },
  'IVY 7': { model: 'kuruma', label: 'Kuruma', make: 'Karin' },
  '83YBY323': { model: 'asea', label: 'Asea', make: 'Declasse' },
  'HOT 666': { model: 'zentorno', label: 'Zentorno', make: 'Pegassi' },
  'MESA RS': { model: 'sultan2', label: 'Sultan Classic', make: 'Karin' },
  '07BUF4X': { model: 'buffalo4', label: 'Buffalo STX', make: 'Bravado' },
};

const spawned: Record<string, number> = { '52MZL952': 4, 'GTO 88': 1240, 'FAM 2024': 18, 'HOT 666': 34, 'MESA RS': 230 };

function row(id: string, plate: string, extra: Partial<KeyAdminRow>): KeyAdminRow {
  const v = VEH[plate];
  const dist = spawned[plate];
  return {
    id,
    plate,
    model: v?.model ?? null,
    label: v?.label ?? null,
    make: v?.make ?? null,
    hash: null,
    type: 'key',
    origin: 'key',
    custody: { kind: 'server' },
    spawned: dist !== undefined,
    netId: dist !== undefined ? 400 + plate.length : null,
    distance: dist ?? null,
    deletable: true,
    ...extra,
  };
}

function maraKeys(): KeyAdminRow[] {
  const t0 = now();
  return [
    row('owner:52MZL952', '52MZL952', { type: 'owner', origin: 'owner', deletable: false }),
    row('owner:GTO 88', 'GTO 88', { type: 'owner', origin: 'owner', deletable: false }),
    row('owner:NITE 77', 'NITE 77', { type: 'owner', origin: 'owner', deletable: false }),
    row('owner:RETRO 6', 'RETRO 6', { type: 'owner', origin: 'owner', deletable: false }),
    row('owner:VGR 22', 'VGR 22', { type: 'owner', origin: 'owner', deletable: false }),
    row('item:52MZL952:k8a2', '52MZL952', { type: 'key', origin: 'garage', current: true, custody: { kind: 'inventory', slot: 3 } }),
    row('item:GTO 88:f1c9', 'GTO 88', { type: 'fob', origin: 'garage', current: true, custody: { kind: 'inventory', slot: 7 } }),
    row('item:GTO 88:f7d0', 'GTO 88', { type: 'fob', origin: 'paid', current: true, custody: { kind: 'stash', stash: 'glovebox:GTO 88' } }),
    row('item:NITE 77:f2b4', 'NITE 77', { type: 'fob', origin: 'garage', current: true, custody: { kind: 'stash', stash: 'trunk:NITE 77' } }),
    row('item:RETRO 6:k0e1', 'RETRO 6', { type: 'key', origin: 'key', current: false, custody: { kind: 'inventory', slot: 21 } }),
    row('item:RETRO 6:k5f3', 'RETRO 6', { type: 'key', origin: 'paid', current: true, custody: { kind: 'stash', stash: 'property:apartment_3' } }),
    row('item:VGR 22:k9a7', 'VGR 22', { type: 'key', origin: 'garage', current: true, custody: { kind: 'ground', groundId: 'g4f81' } }),
    row('item:NITE 77:f6aa', 'NITE 77', { type: 'fob', origin: 'garage', current: true, custody: { kind: 'unknown' } }),
    row('share:FAM 2024', 'FAM 2024', { type: 'owner', origin: 'share', shared: 'in', deletable: false }),
    row('virtual:IVY 7', 'IVY 7', { type: 'virtual', origin: 'virtual', shared: 'in' }),
    row('temp:83YBY323', '83YBY323', { type: 'temp', origin: 'hotwire', expires: t0 + 23 * H + 12 * 60 }),
    row('temp:HOT 666', 'HOT 666', { type: 'temp', origin: 'robbery', expires: t0 + 20 * 60 }),
    row('temp:MESA RS', 'MESA RS', { type: 'temp', origin: 'admin', expires: t0 + 3 * 24 * H }),
    row('item:07BUF4X:k3c3', '07BUF4X', { type: 'key', origin: 'locksmith', current: true, custody: { kind: 'flight' } }),
  ];
}

const keysOf: Record<string, KeyAdminRow[]> = {
  'char1:MQ48X2KD': maraKeys(),
  'char2:TB90LKE1': [
    row('owner:FAM 2024', 'FAM 2024', { type: 'owner', origin: 'owner', deletable: false }),
    row('owner:TB 4X4', 'TB 4X4', { type: 'owner', origin: 'owner', deletable: false }),
    row('item:FAM 2024:f001', 'FAM 2024', { type: 'fob', origin: 'garage', current: true, custody: { kind: 'stash', stash: 'glovebox:FAM 2024' } }),
    row('item:TB 4X4:k002', 'TB 4X4', { type: 'key', origin: 'garage', current: true, custody: { kind: 'unknown' } }),
  ],
  'char1:IM11ZQ07': [row('owner:IVY 7', 'IVY 7', { type: 'owner', origin: 'owner', deletable: false })],
  'char3:MA77PLX0': [],
  'char1:DV03RRA9': [],
};

function playerData(identifier: string): KeyAdminPlayerData | null {
  const p = PLAYERS.find((x) => x.identifier === identifier);
  if (!p) return null;
  const keys = keysOf[identifier] ?? [];
  const vehicles = keys.filter((k) => k.type === 'owner' && k.origin === 'owner').length;
  const sharedIn = keys.filter((k) => k.shared === 'in').length;
  const sharedOut = identifier === 'char1:MQ48X2KD' ? 2 : 0;
  const { plates: _p, ...player } = p;
  void _p;
  return { player, keys: clone(keys).sort((a, b) => (a.plate === b.plate ? a.id.localeCompare(b.id) : a.plate.localeCompare(b.plate))), totals: { keys: keys.length, vehicles, sharedIn, sharedOut } };
}

mockNui('keyadmin:search', ({ query }) => {
  const q = String(query ?? '').trim().toLowerCase();
  const rows: KeyAdminPlayer[] = [];
  for (const p of PLAYERS) {
    const plates = p.plates.filter((pl) => pl.toLowerCase().includes(q));
    const hit =
      p.name.toLowerCase().includes(q) || p.identifier.toLowerCase().includes(q) || String(p.serverId ?? '') === q || plates.length > 0;
    if (hit) rows.push({ identifier: p.identifier, name: p.name, online: p.online, serverId: p.serverId, matchedPlates: plates });
  }
  return { rows };
});

mockNui('keyadmin:player', ({ identifier }) => {
  const d = playerData(identifier);
  return d ?? { ok: false, error: 'Invalid identifier' };
});

mockNui('keyadmin:give', ({ identifier, plate, type, keyKind, hours }) => {
  const p = PLAYERS.find((x) => x.identifier === identifier);
  if (!p) return { ok: false, error: 'Invalid request' };
  if (type === 'item' && !p.online) return { ok: false, error: 'The player must be online for a key item' };
  if (type === 'virtual' && !VEH[plate]) return { ok: false, error: 'Only registered vehicles have virtual keys' };
  const list = (keysOf[identifier] = keysOf[identifier] ?? []);
  if (type === 'item') {
    const id = Math.random().toString(16).slice(2, 6);
    list.push(row(`item:${plate}:${id}`, plate, { type: keyKind === 'key' ? 'key' : 'fob', origin: 'admin', current: true, custody: { kind: 'inventory', slot: 30 + list.length } }));
  } else if (type === 'temp') {
    const rest = list.filter((k) => k.id !== `temp:${plate}`);
    rest.push(row(`temp:${plate}`, plate, { type: 'temp', origin: 'admin', expires: now() + Math.round((hours ?? 24) * H) }));
    keysOf[identifier] = rest;
  } else {
    if (!list.some((k) => k.id === `virtual:${plate}`)) list.push(row(`virtual:${plate}`, plate, { type: 'virtual', origin: 'virtual', shared: 'in' }));
  }
  return playerData(identifier)!;
});

mockNui('keyadmin:delete', ({ identifier, id }) => {
  for (const [who, list] of Object.entries(keysOf)) {
    if (who !== identifier && !id.startsWith('item:') && !id.startsWith('ground:')) continue;
    keysOf[who] = list.filter((k) => k.id !== id && !(id.startsWith('ground:') && k.custody.groundId === id.slice(7)));
  }
  const ground = id.startsWith('ground:') ? id.slice(7) : null;
  if (ground) plateGround = plateGround.filter((g) => g.id !== ground);
  return playerData(identifier) ?? playerData('char1:MQ48X2KD')!;
});

let plateGround: KeyAdminPlateData['ground'] = [
  { id: 'g4f81', plate: 'VGR 22', kind: 'item', keyKind: 'key', coords: { x: 215.4, y: -810.2, z: 30.7 }, bucket: 0, droppedBy: 'char1:MQ48X2KD', createdAt: now() - 640, expiresAt: now() + 1160 },
];

mockNui('keyadmin:plate', ({ plate }) => {
  const v = VEH[plate];
  const owner = PLAYERS.find((p) => p.plates.includes(plate)) ?? null;
  const custody: KeyAdminPlateData['custody'] = [];
  const holders: KeyAdminPlateData['holders'] = [];
  for (const [who, list] of Object.entries(keysOf)) {
    const name = PLAYERS.find((p) => p.identifier === who)?.name ?? 'Unknown';
    for (const k of list) {
      if (k.plate !== plate) continue;
      if (k.type === 'key' || k.type === 'fob')
        custody.push({ id: k.id, type: k.type, origin: k.origin, current: k.current !== false, custody: k.custody, holder: k.custody.kind === 'inventory' ? who : null, holderName: k.custody.kind === 'inventory' ? name : null });
      if (k.type === 'virtual' || k.type === 'temp') holders.push({ identifier: who, name, type: k.type, origin: k.origin, expires: k.expires ?? null });
    }
  }
  if (plate === 'GTO 88') {
    holders.push({ identifier: 'char1:IM11ZQ07', name: 'Ivy Moreno', type: 'virtual', origin: null, expires: null });
    holders.push({ identifier: 'char1:DV03RRA9', name: 'Dmitri Volkov', type: 'temp', origin: 'hotwire', expires: now() + 2 * H + 300 });
  }
  return {
    plate,
    owned: !!owner,
    owner: owner?.identifier ?? null,
    ownerName: owner?.name ?? null,
    model: v?.model ?? null,
    label: v?.label ?? null,
    make: v?.make ?? null,
    version: plate === 'RETRO 6' ? 3 : 1,
    live: custody.filter((c) => c.current && c.custody.kind !== 'lost').length,
    immobiliser: plate === 'GTO 88' ? { level: 'ghost', pinSet: true } : plate === '52MZL952' ? { level: 'standard', pinSet: false } : { level: 'none', pinSet: false },
    spawned: spawned[plate] !== undefined,
    netId: spawned[plate] !== undefined ? 412 : null,
    distance: spawned[plate] ?? null,
    custody,
    holders,
    ground: plateGround.filter((g) => g.plate === plate),
  } satisfies KeyAdminPlateData;
});

const POS: Record<string, { x: number; y: number; z: number; bucket: number }> = {
  '52MZL952': { x: 218.6, y: -805.1, z: 30.6, bucket: 0 },
  'GTO 88': { x: -1186.2, y: -1508.4, z: 4.4, bucket: 0 },
  'FAM 2024': { x: 236.1, y: -785.9, z: 30.6, bucket: 0 },
  'HOT 666': { x: 1702.8, y: 3596.0, z: 35.4, bucket: 4 },
  'MESA RS': { x: 431.2, y: -1015.7, z: 28.8, bucket: 0 },
};

const trackOf = (plate: string) => {
  const p = POS[plate];
  if (!p) return { plate, spawned: false };
  return { plate, spawned: true, bucket: p.bucket, coords: { x: p.x, y: p.y, z: p.z }, distance: spawned[plate] ?? null };
};
mockNui('keyadmin:track', ({ plate }) => trackOf(plate));
mockNui('keyadmin:waypoint', ({ plate }) => (POS[plate] ? trackOf(plate) : { ok: false, error: 'The vehicle is not out' }));

/* ── settings ────────────────────────────────────────────────────────── */

const TABS: KeySettings['tabs'] = [
  { id: 'keys', label: 'Keys' },
  { id: 'ground', label: 'Ground keys' },
  { id: 'vehicles', label: 'Vehicles' },
  { id: 'lockpicking', label: 'Lockpicking' },
  { id: 'hotwiring', label: 'Hotwiring' },
  { id: 'npc', label: 'NPC keys' },
  { id: 'jobs', label: 'Job vehicles' },
  { id: 'security', label: 'Security' },
];

// shared/carlock.lua SETTINGS (labels and ranges), defaults as in config/carlock.lua
const SCHEMA: (Omit<KeySetting, 'value' | 'overridden'>)[] = [
  {"id": "keys.mode", "tab": "keys", "type": "enum", "label": "Key mode", "description": "Flexible: key items, sharing makes a copy. Limited: a fixed set of key items per vehicle, sharing gives yours away. Virtual: no items, the server issues access.", "options": ["flexible", "limited", "virtual"], "default": "flexible"},
  {"id": "keys.limitedKeys", "tab": "keys", "type": "number", "label": "Limited: keys per vehicle", "description": "Starting set of each vehicle in the limited key mode.", "min": 1, "max": 10, "step": 1, "integer": true, "default": 2},
  {"id": "keys.giveKeyOnRetrieve", "tab": "keys", "type": "bool", "label": "Cut a key on retrieval", "description": "Flexible mode: a garage retrieval cuts a key when the owner has none.", "default": true},
  {"id": "keys.ownerHasKey", "tab": "keys", "type": "enum", "label": "Owners always have a key", "description": "Auto: yes with virtual keys, no with key items (owners need the item).", "options": ["auto", "yes", "no"], "default": "auto"},
  {"id": "keys.tempKeyHours", "tab": "keys", "type": "number", "label": "Temporary keys last (hours)", "description": "Hotwired, robbed, staff and other scripts' keys.", "min": 0.05, "max": 720, "step": 0.05, "default": 24},
  {"id": "keys.defaultFob", "tab": "keys", "type": "enum", "label": "Default fob design", "description": "Fob drawn for keys that have no design of their own.", "options": ["classic", "slim", "card", "sport", "retro"], "default": "classic"},
  {"id": "keys.remoteRange", "tab": "keys", "type": "number", "label": "Remote range (m)", "description": "Fobs lock, unlock and start from this far.", "min": 5, "max": 150, "step": 1, "default": 30},
  {"id": "keys.keyRange", "tab": "keys", "type": "number", "label": "Key range (m)", "description": "A plain key works from this far.", "min": 1, "max": 20, "step": 0.5, "default": 5},
  {"id": "keys.giveRange", "tab": "keys", "type": "number", "label": "Hand-over range (m)", "description": "Players this close can be given a key.", "min": 1, "max": 10, "step": 0.5, "default": 3},
  {"id": "keys.lockPrefer", "tab": "keys", "type": "enum", "label": "Lock selection", "description": "Which vehicle the lock key picks when several are in range.", "options": ["nearest", "owned", "last"], "default": "nearest"},
  {"id": "keys.maxShares", "tab": "keys", "type": "number", "label": "Virtual shares per vehicle", "description": "Players one owner can give a virtual key of one vehicle.", "min": 1, "max": 50, "step": 1, "integer": true, "default": 5},
  {"id": "keys.maxCopies", "tab": "keys", "type": "number", "label": "Key copies per vehicle", "description": "Flexible mode: copies of the current locks that may exist.", "min": 1, "max": 50, "step": 1, "integer": true, "default": 10},
  {"id": "keys.shareHours", "tab": "keys", "type": "number", "label": "Shared keys last (hours)", "description": "0 = until revoked.", "min": 0, "max": 720, "step": 1, "default": 0},
  {"id": "keys.trackWho", "tab": "keys", "type": "enum", "label": "Who can track", "description": "Real: owners, shares and real keys. Any: every key. Owner: owners and garage shares only.", "options": ["real", "any", "owner"], "default": "real"},
  {"id": "keys.keyless", "tab": "keys", "type": "bool", "label": "Keyless entry and exit", "description": "Fob keys unlock on entry and lock when the player walks away.", "default": true},
  {"id": "keys.keylessMin", "tab": "keys", "type": "number", "label": "Keyless: shortest lock distance (m)", "description": "Players cannot pick a shorter auto-lock distance.", "min": 1, "max": 50, "step": 0.5, "default": 3},
  {"id": "keys.keylessMax", "tab": "keys", "type": "number", "label": "Keyless: longest lock distance (m)", "description": "Players cannot pick a longer auto-lock distance.", "min": 2, "max": 100, "step": 0.5, "default": 30},
  {"id": "ground.enabled", "tab": "ground", "type": "bool", "label": "Keys on the ground", "description": "Drop, throw and toss key items; anyone can pick them up.", "default": true},
  {"id": "ground.animateDrops", "tab": "ground", "type": "bool", "label": "Animate drops", "description": "Players play an animation when they drop or throw a key.", "default": true},
  {"id": "ground.persist", "tab": "ground", "type": "bool", "label": "Keep after a restart", "description": "Keys on the ground survive a server restart (database).", "default": false},
  {"id": "ground.removeAfter", "tab": "ground", "type": "number", "label": "Remove after (minutes)", "description": "An untouched key on the ground is gone after this long. 0 = never.", "min": 0, "max": 10080, "step": 1, "integer": true, "default": 30},
  {"id": "ground.pickupRange", "tab": "ground", "type": "number", "label": "Pick-up range (m)", "description": "Distance from the player to a key on the ground.", "min": 0.5, "max": 5, "step": 0.1, "default": 2},
  {"id": "ground.throwRange", "tab": "ground", "type": "number", "label": "Throw range (m)", "description": "Keys can be thrown to a player this far away.", "min": 2, "max": 20, "step": 0.5, "default": 8},
  {"id": "ground.catchWindow", "tab": "ground", "type": "number", "label": "Catch window (ms)", "description": "Time to catch a thrown key before it falls.", "min": 500, "max": 5000, "step": 100, "integer": true, "default": 1800},
  {"id": "ground.markerStyle", "tab": "ground", "type": "enum", "label": "Marker style", "description": "Shape drawn above keys on the ground.", "options": ["none", "chevron", "ring", "dot"], "default": "chevron"},
  {"id": "ground.markerColor", "tab": "ground", "type": "color", "label": "Marker colour", "description": "Colour of the marker.", "default": "#2dd4bf", "alpha": true},
  {"id": "ground.markerSize", "tab": "ground", "type": "number", "label": "Marker size", "description": "Size of the marker (m).", "min": 0.05, "max": 2, "step": 0.05, "default": 0.25},
  {"id": "ground.markerHeight", "tab": "ground", "type": "number", "label": "Marker height", "description": "Height of the marker above the key (m).", "min": 0, "max": 2, "step": 0.05, "default": 0.35},
  {"id": "vehicles.requireKey", "tab": "vehicles", "type": "bool", "label": "Engine needs a key", "description": "Without a key the engine stays off.", "default": true},
  {"id": "vehicles.keepEngineRunning", "tab": "vehicles", "type": "bool", "label": "Engine may keep running", "description": "Players may leave the engine running when they get out (their own setting).", "default": true},
  {"id": "vehicles.allowRunningEngine", "tab": "vehicles", "type": "bool", "label": "Drive a running car without a key", "description": "A car left running can be driven away.", "default": true},
  {"id": "vehicles.bypassClasses", "tab": "vehicles", "type": "classes", "label": "Classes without a key", "description": "These classes start without a key (13 = cycles).", "default": [13]},
  {"id": "vehicles.bypassModels", "tab": "vehicles", "type": "models", "label": "Models without a key", "description": "These models start without a key.", "default": ["bmx", "tribike"]},
  {"id": "vehicles.highendClasses", "tab": "vehicles", "type": "classes", "label": "High-end classes", "description": "Classes that use the high-end profile (fob, remote range, tracker).", "default": [6, 7]},
  {"id": "vehicles.lockNotify", "tab": "vehicles", "type": "bool", "label": "Lock notifications", "description": "Show \"Vehicle locked / unlocked\".", "default": true},
  {"id": "vehicles.immobiliser", "tab": "vehicles", "type": "bool", "label": "Immobilisers", "description": "Standard immobilisers block hotwiring; Ghost asks for a PIN.", "default": true},
  {"id": "lockpick.style", "tab": "lockpicking", "type": "enum", "label": "Lock picking", "description": "Skill checks, or the five-pin lock (players whose client cannot show the pin lock get skill checks).", "options": ["skillcheck", "pins"], "default": "skillcheck"},
  {"id": "lockpick.pins", "tab": "lockpicking", "type": "number", "label": "Pins", "description": "Pins of the pin lock.", "min": 3, "max": 7, "step": 1, "integer": true, "default": 5},
  {"id": "lockpick.snapChance", "tab": "lockpicking", "type": "number", "label": "Snap chance (%)", "description": "Chance the pick snaps when a pin is overset.", "min": 0, "max": 100, "step": 1, "integer": true, "default": 35},
  {"id": "lockpick.alarmOnSnap", "tab": "lockpicking", "type": "bool", "label": "Alarm on a snapped pick", "description": "A snapped pick sets the alarm off.", "default": true},
  {"id": "hotwire.style", "tab": "hotwiring", "type": "enum", "label": "Hotwiring", "description": "Each profile's method, or splicing wires (players whose client cannot show the minigame get the profile's method, but still need the reader / kit).", "options": ["profile", "wires"], "default": "profile"},
  {"id": "hotwire.kitRequired", "tab": "hotwiring", "type": "bool", "label": "Wires need a hotwire kit", "description": "Splicing wires needs the hotwire_kit item (also when the client falls back to another minigame).", "default": false},
  {"id": "hotwire.readerClasses", "tab": "hotwiring", "type": "classes", "label": "Classes that need the reader", "description": "Only with Hotwiring = wires: these classes are started with the signal reader.", "default": [6, 7]},
  {"id": "hotwire.readerModels", "tab": "hotwiring", "type": "models", "label": "Models that need the reader", "description": "Model overrides: always the signal reader.", "default": []},
  {"id": "hotwire.wireModels", "tab": "hotwiring", "type": "models", "label": "Models with wires", "description": "Model overrides: always wires.", "default": []},
  {"id": "npc.robbery", "tab": "npc", "type": "bool", "label": "Hold-ups", "description": "Aim at an NPC driver to get the key.", "default": true},
  {"id": "npc.handover", "tab": "npc", "type": "number", "label": "Hands the key over", "description": "Weight of this reaction.", "min": 0, "max": 100, "step": 1, "integer": true, "default": 55},
  {"id": "npc.drop", "tab": "npc", "type": "number", "label": "Drops the key and runs", "description": "Weight of this reaction.", "min": 0, "max": 100, "step": 1, "integer": true, "default": 20},
  {"id": "npc.fight", "tab": "npc", "type": "number", "label": "Fights back", "description": "Weight of this reaction.", "min": 0, "max": 100, "step": 1, "integer": true, "default": 10},
  {"id": "npc.flee", "tab": "npc", "type": "number", "label": "Drives away", "description": "Weight of this reaction.", "min": 0, "max": 100, "step": 1, "integer": true, "default": 15},
  {"id": "npc.policeRequired", "tab": "npc", "type": "number", "label": "Police needed", "description": "On-duty officers needed for a hold-up.", "min": 0, "max": 50, "step": 1, "integer": true, "default": 0},
  {"id": "npc.dispatchDelay", "tab": "npc", "type": "number", "label": "Dispatch delay (s)", "description": "Seconds before the police alert of a hold-up goes out.", "min": 0, "max": 600, "step": 1, "integer": true, "default": 20},
  {"id": "npc.robTime", "tab": "npc", "type": "number", "label": "Hand-over time (ms)", "description": "Aiming time before the key is handed over.", "min": 500, "max": 30000, "step": 100, "integer": true, "default": 3500},
  {"id": "npc.alertChance", "tab": "npc", "type": "number", "label": "Alert chance (%)", "description": "Chance a hold-up alerts the police.", "min": 0, "max": 100, "step": 1, "integer": true, "default": 60},
  {"id": "npc.cooldown", "tab": "npc", "type": "number", "label": "Cooldown (s)", "description": "Seconds between hold-ups per player.", "min": 0, "max": 3600, "step": 1, "integer": true, "default": 120},
  {"id": "npc.deadDriverKeys", "tab": "npc", "type": "bool", "label": "Search dead drivers", "description": "The key can be taken from the original driver's body.", "default": true},
  {"id": "jobs.bypass", "tab": "jobs", "type": "bool", "label": "Fleet vehicles start without a key", "description": "On-duty job / gang members in their fleet vehicles.", "default": true},
  {"id": "jobs.keyHours", "tab": "jobs", "type": "number", "label": "Spawner keys last (hours)", "description": "0 = like other temporary keys.", "min": 0, "max": 720, "step": 0.5, "default": 0},
  {"id": "jobs.assistJobs", "tab": "jobs", "type": "strings", "label": "Jobs that can request vehicles", "description": "These jobs (on duty) ask NPC drivers for their vehicle.", "default": ["police", "ambulance"]},
  {"id": "security.trustUnsignedKeys", "tab": "security", "type": "bool", "label": "Accept unsigned key items", "description": "Not recommended: anyone able to write item metadata could make keys.", "default": false},
  {"id": "security.compat", "tab": "security", "type": "bool", "label": "Other scripts' key events", "description": "Answer the key events of other key resources.", "default": true},
  {"id": "security.compatAmbient", "tab": "security", "type": "bool", "label": "Client events on traffic cars", "description": "Other scripts' client events may give keys of NPC cars.", "default": false},
  {"id": "security.clientGiveKey", "tab": "security", "type": "bool", "label": "Client GiveKey export", "description": "Client code may ask for temporary keys.", "default": false},
  {"id": "security.pinAttempts", "tab": "security", "type": "number", "label": "Ghost PIN attempts", "description": "Wrong PINs before the alarm and the cooldown.", "min": 1, "max": 10, "step": 1, "integer": true, "default": 3},
  {"id": "security.pinCooldown", "tab": "security", "type": "number", "label": "Ghost PIN cooldown (s)", "description": "No PIN attempts this long after too many wrong ones.", "min": 10, "max": 3600, "step": 5, "integer": true, "default": 120},
  {"id": "security.pinSession", "tab": "security", "type": "number", "label": "Ghost PIN valid (s)", "description": "A correct PIN stays valid this long for that driver.", "min": 30, "max": 86400, "step": 30, "integer": true, "default": 600},
  {"id": "security.alarmAlertChance", "tab": "security", "type": "number", "label": "Car alarm alert chance (%)", "description": "Chance a car alarm alerts the police.", "min": 0, "max": 100, "step": 1, "integer": true, "default": 35},
];

/** stored admin values (the database) */
const stored: Record<string, KeySettingValue> = { 'keys.remoteRange': 45, 'ground.markerColor': '#f5a524cc' };

function schema(): KeySettings {
  return {
    tabs: TABS,
    settings: SCHEMA.map((s) => ({ ...clone(s), value: clone(stored[s.id] ?? s.default), overridden: stored[s.id] !== undefined })),
  };
}

function valid(s: Omit<KeySetting, 'value' | 'overridden'>, v: KeySettingValue): boolean {
  switch (s.type) {
    case 'bool':
      return typeof v === 'boolean';
    case 'number':
      return typeof v === 'number' && (s.min === undefined || v >= s.min) && (s.max === undefined || v <= s.max) && (!s.integer || Number.isInteger(v));
    case 'enum':
      return typeof v === 'string' && (s.options ?? []).includes(v);
    case 'color':
      return typeof v === 'string' && /^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(v);
    default:
      return Array.isArray(v);
  }
}

mockNui('keyadmin:settings', () => schema());
mockNui('keyadmin:saveSettings', ({ values, reset }) => {
  for (const [id, v] of Object.entries(values ?? {})) {
    const s = SCHEMA.find((x) => x.id === id);
    if (!s) return { ok: false, error: 'Unknown setting' };
    if (!valid(s, v)) return { ok: false, error: `Invalid value: ${s.label}` };
  }
  for (const id of reset ?? []) delete stored[id];
  Object.assign(stored, clone(values ?? {}));
  return schema();
});

/* ── scenarios ───────────────────────────────────────────────────────── */

const init: NuiMessage = {
  action: 'init',
  data: { locale: {}, settings: { ...defaultInterface, distanceUnit: 'km' }, resource: 'nayzeee-garages' },
};
const open = (data: KeyAdminOpenData): NuiMessage => ({
  action: 'open',
  data: { app: 'keyadmin', data: { fobDesign: 'classic', tempKeyHours: 24, keyMode: 'flexible', ...data } },
});

const G = 'Key manager';
registerMock({ id: 'keyadmin-search', group: G, label: 'Search (empty)', messages: [init, open({})] });
registerMock({ id: 'keyadmin-results', group: G, label: 'Search results', messages: [init, open({ query: 'ma' })] });
registerMock({ id: 'keyadmin-noresults', group: G, label: 'No results', messages: [init, open({ query: 'zzz' })] });
registerMock({ id: 'keyadmin-player', group: G, label: 'Player with many keys', messages: [init, open({ identifier: 'char1:MQ48X2KD' })] });
registerMock({ id: 'keyadmin-offline', group: G, label: 'Offline player', messages: [init, open({ identifier: 'char2:TB90LKE1' })] });
registerMock({ id: 'keyadmin-nokeys', group: G, label: 'Player without keys', messages: [init, open({ identifier: 'char1:DV03RRA9' })] });
registerMock({ id: 'keyadmin-plate', group: G, label: 'Plate view', messages: [init, open({ identifier: 'char1:MQ48X2KD', plate: 'GTO 88' })] });
registerMock({ id: 'keyadmin-settings', group: G, label: 'Settings: keys', messages: [init, open({ page: 'settings', settingsTab: 'keys' })] });
registerMock({ id: 'keyadmin-ground', group: G, label: 'Settings: ground keys', messages: [init, open({ page: 'settings', settingsTab: 'ground' })] });
registerMock({ id: 'keyadmin-npc', group: G, label: 'Settings: NPC keys', messages: [init, open({ page: 'settings', settingsTab: 'npc' })] });
registerMock({ id: 'keyadmin-vehicles', group: G, label: 'Settings: vehicles', messages: [init, open({ page: 'settings', settingsTab: 'vehicles' })] });
