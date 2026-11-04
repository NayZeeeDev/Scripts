/**
 * Locksmith mocks (browser dev only). Scenarios (?mock=<id>):
 *   locksmith-legal      licensed shop, physical keys: owned cars parked nearby (with / without a key),
 *                        a fob far away, a hotwired car (temporary key: refused), a garage share
 *                        (shared access: refused), a back-alley fob (unregistered: copy only)
 *   locksmith-illegal    back-alley shop: strangers' cars parked nearby get keys, police risk
 *   locksmith-materials  Program a key without a key blank in the pockets
 *   locksmith-broke      not enough cash for the service
 *   locksmith-unregistered  a back-alley fob selected at a licensed shop: copies, never registers
 *   locksmith-virtual    virtual keys at a licensed shop: no duplicate, no program, rekey owners only
 *   locksmith-shared     a garage share car selected: 'Shared access', refused for a new key
 *   locksmith-empty      nothing parked nearby, no keys
 * locksmith:service answers like the server (blocked / materials / money) and returns fresh data.
 */
import { registerMock } from '../registry';
import { mockNui, onNuiMessage } from '../../lib/nui';
import { defaultInterface } from '../../lib/store';
import type { LocksmithOpenData, LocksmithService, LocksmithVehicle, NuiMessage } from '../../lib/types';
import { joaat, modelInfo } from './garage';

const clone = <T>(v: T): T => JSON.parse(JSON.stringify(v)) as T;

function car(model: string, label: string, make: string, plate: string, extra: Partial<LocksmithVehicle> = {}): LocksmithVehicle {
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
    isOwner: false,
    owned: false,
    hasKey: false,
    keyKind: null,
    keyItems: 0,
    keyType: 'key',
    nearby: false,
    distance: null,
    towing: false,
    blocked: {},
    ...extra,
  };
}

const blank = (have: number) => ({ item: 'key_blank', label: 'Key blank', count: 1, have });

function services(opts: { blanks: number; illegal?: boolean; virtual?: boolean }): LocksmithService[] {
  const { blanks, illegal = false, virtual = false } = opts;
  return [
    {
      id: 'duplicate',
      enabled: true,
      offered: !virtual,
      reason: virtual ? 'Give virtual keys from your key ring' : null,
      price: illegal ? 600 : 250,
      materials: [],
    },
    {
      id: 'program',
      enabled: true,
      // virtual mode: owners give keys from the key ring, a licensed shop programs none
      offered: !(virtual && !illegal),
      reason: virtual && !illegal ? 'Owners give keys from the key ring' : null,
      price: illegal ? 3500 : 500,
      materials: illegal ? [] : [blank(blanks)],
    },
    { id: 'rekey', enabled: !illegal, offered: true, price: 1500, materials: [] },
  ];
}

const PARK = 'Park the vehicle near the locksmith';

function legal(blanks = 1, cash = 9250): LocksmithOpenData {
  return {
    id: 1,
    name: 'Los Santos Locksmith',
    illegal: false,
    account: 'cash',
    mode: 'physical',
    money: cash,
    tempHours: 24,
    range: 25,
    services: services({ blanks }),
    vehicles: [
      car('jester4', 'Jester RR', 'Dinka', '52MZL952', {
        isOwner: true,
        owned: true,
        hasKey: true,
        keyKind: 'item',
        keyItems: 1,
        nearby: true,
        distance: 8,
      }),
      car('elegy', 'Elegy Retro Custom', 'Annis', 'RETRO 6', {
        nickname: 'Rusty',
        isOwner: true,
        owned: true,
        nearby: true,
        distance: 14,
        blocked: {},
      }),
      car('asea', 'Asea', 'Declasse', '83YBY323', {
        hasKey: true,
        keyKind: 'temp',
        nearby: true,
        distance: 19,
        blocked: {
          duplicate: 'Bring a key or the papers of this vehicle',
          program: 'A temporary key is not enough: only the owner or a key holder',
          rekey: 'Only the owner can change the locks',
        },
      }),
      car('italigto', 'Itali GTO', 'Grotti', 'GTO 88', {
        nickname: 'Red Rocket',
        isOwner: true,
        owned: true,
        hasKey: true,
        keyKind: 'item',
        keyItems: 2,
        keyType: 'fob',
        blocked: { program: PARK, rekey: PARK },
      }),
      car('kuruma', 'Kuruma', 'Karin', 'KRM 404', {
        isOwner: true,
        owned: true,
        blocked: { program: PARK, rekey: PARK },
      }),
      car('pariah', 'Pariah', 'Ocelot', 'DEN 404', {
        owned: true,
        hasKey: true,
        keyKind: 'item',
        keyItems: 1,
        keyType: 'fob',
        // cut by a back-alley locksmith: it opens the car, a licensed shop only copies it
        unregistered: true,
        nearby: true,
        distance: 21,
        blocked: {
          program: 'An unregistered key is not enough: only the owner or a key holder',
          rekey: 'Only the owner can change the locks',
        },
      }),
      car('baller7', 'Baller ST', 'Gallivanter', 'FAM 2024', {
        owned: true,
        hasKey: true,
        keyKind: 'owner',
        nearby: true,
        distance: 23,
        blocked: {
          duplicate: 'Bring a key or the papers of this vehicle',
          program: 'Garage or job access is not enough: only the owner or a key holder',
          rekey: 'Only the owner can change the locks',
        },
      }),
    ],
  };
}

function illegal(): LocksmithOpenData {
  const stranger = { duplicate: 'Bring a key of this vehicle to copy', rekey: 'Not offered here' };
  return {
    id: 2,
    name: 'Back-alley Keys',
    illegal: true,
    account: 'cash',
    mode: 'physical',
    money: 12400,
    tempHours: 24,
    range: 20,
    services: services({ blanks: 0, illegal: true }),
    vehicles: [
      car('t20', 'T20', 'Progen', 'BLK 220', { owned: true, nearby: true, distance: 6, keyType: 'fob', blocked: stranger }),
      car('baller7', 'Baller ST', 'Gallivanter', '46QJK118', { nearby: true, distance: 11, blocked: stranger }),
      car('rumpo', 'Rumpo', 'Bravado', 'DOCK 31', { owned: true, nearby: true, distance: 17, blocked: stranger }),
      car('jester4', 'Jester RR', 'Dinka', '52MZL952', {
        isOwner: true,
        owned: true,
        hasKey: true,
        keyKind: 'item',
        keyItems: 1,
        blocked: { program: PARK, rekey: 'Not offered here' },
      }),
    ],
  };
}

function virtual(): LocksmithOpenData {
  const d = legal(1, 6400);
  d.mode = 'virtual';
  d.services = services({ blanks: 1, virtual: true });
  d.vehicles = d.vehicles
    .filter((v) => v.plate !== 'DEN 404')
    .map((v) => ({
      ...v,
      keyItems: 0,
      unregistered: false,
      keyKind: v.isOwner ? 'owner' : v.keyKind,
      hasKey: v.isOwner || v.hasKey,
      blocked: {
        ...v.blocked,
        duplicate: 'Give virtual keys from your key ring',
        program: 'Owners give keys from the key ring',
      },
    }));
  // (a licensed shop never lists strangers' cars: the server only sends vehicles you own or
  // hold a key for)
  return d;
}

/* ── stateful service answers ─────────────────────────────────────── */

let current: LocksmithOpenData | null = null;
onNuiMessage((msg) => {
  if (msg.action === 'open' && msg.data.app === 'locksmith') current = clone(msg.data.data as LocksmithOpenData);
});

mockNui('locksmith:refresh', () => (current ? clone(current) : { ok: false, error: 'Invalid request' }));

mockNui('locksmith:service', ({ service, plate }) => {
  const d = current;
  if (!d) return { ok: false, error: 'You are too far from the locksmith' };
  const v = d.vehicles.find((x) => x.plate === plate);
  const s = d.services.find((x) => x.id === service);
  if (!v || !s || !s.enabled) return { ok: false, error: 'Invalid request' };
  const blocked = !s.offered ? s.reason : (v.blocked ?? {})[s.id];
  if (blocked) return { ok: false, error: blocked };
  const missing = s.materials.filter((m) => m.have < m.count);
  if (missing.length) return { ok: false, error: `Missing materials: ${missing.map((m) => `${m.count - m.have}x ${m.label}`).join(', ')}` };
  if (s.price > d.money) return { ok: false, error: 'You cannot afford this' };
  d.money -= s.price;
  for (const m of s.materials) m.have -= m.count;
  for (const x of d.services)
    for (const m of x.materials) if (m.item === 'key_blank') m.have = s.materials.find((y) => y.item === m.item)?.have ?? m.have;
  const fob = v.keyType === 'fob';
  let message: string;
  if (service === 'duplicate') {
    v.keyItems += 1;
    message = `Spare ${fob ? 'fob' : 'key'} for ${plate} cut`;
  } else if (service === 'program') {
    if (d.mode === 'virtual') {
      v.hasKey = true;
      v.keyKind = 'temp';
      message = `Temporary key for ${plate} programmed (${d.tempHours} h)`;
    } else {
      v.keyItems += 1;
      v.hasKey = true;
      v.keyKind = 'item';
      // a back-alley key is unregistered (unless a registered one is already in the pockets)
      if (d.illegal && v.keyItems === 1) v.unregistered = true;
      message = `New ${fob ? 'fob' : 'key'} for ${plate} programmed`;
    }
    v.blocked = { ...v.blocked, duplicate: undefined };
  } else {
    v.keyItems = d.mode === 'physical' ? 1 : 0;
    message = `Locks of ${plate} changed: every other key stops working`;
  }
  current = d;
  return { message, data: clone(d) };
});

/* ── scenarios ──────────────────────────────────────────────────────── */

const init: NuiMessage = {
  action: 'init',
  data: { locale: {}, settings: { ...defaultInterface, currency: '$' }, resource: 'nayzeee-garages' },
};
const open = (data: LocksmithOpenData): NuiMessage => ({ action: 'open', data: { app: 'locksmith', data } });

registerMock({ id: 'locksmith-legal', group: 'Locksmith', label: 'Licensed shop', messages: [init, open(legal())] });
registerMock({ id: 'locksmith-illegal', group: 'Locksmith', label: 'Back-alley shop', messages: [init, open(illegal())] });

const noBlank = (): LocksmithOpenData => {
  const d = legal(0);
  // the owner's car without a key: Program is the only way
  const elegy = d.vehicles.find((v) => v.plate === 'RETRO 6')!;
  d.vehicles = [elegy, ...d.vehicles.filter((v) => v !== elegy)];
  return d;
};
registerMock({ id: 'locksmith-materials', group: 'Locksmith', label: 'Missing materials', messages: [init, open(noBlank())] });

const broke = (): LocksmithOpenData => {
  const d = legal(1, 120);
  const elegy = d.vehicles.find((v) => v.plate === 'RETRO 6')!;
  d.vehicles = [elegy, ...d.vehicles.filter((v) => v !== elegy)];
  return d;
};
registerMock({ id: 'locksmith-broke', group: 'Locksmith', label: 'Cannot afford', messages: [init, open(broke())] });
registerMock({ id: 'locksmith-virtual', group: 'Locksmith', label: 'Virtual keys', messages: [init, open(virtual())] });

const unregistered = (): LocksmithOpenData => {
  const d = legal();
  const den = d.vehicles.find((v) => v.plate === 'DEN 404')!;
  d.vehicles = [den, ...d.vehicles.filter((v) => v !== den)];
  return d;
};
registerMock({
  id: 'locksmith-unregistered',
  group: 'Locksmith',
  label: 'Back-alley key at a licensed shop',
  messages: [init, open(unregistered())],
});

const shared = (): LocksmithOpenData => {
  const d = legal();
  const share = d.vehicles.find((v) => v.plate === 'FAM 2024')!;
  d.vehicles = [share, ...d.vehicles.filter((v) => v !== share)];
  return d;
};
registerMock({ id: 'locksmith-shared', group: 'Locksmith', label: 'Garage share: shared access', messages: [init, open(shared())] });
registerMock({
  id: 'locksmith-empty',
  group: 'Locksmith',
  label: 'Nothing parked nearby',
  messages: [init, open({ ...legal(), vehicles: [] })],
});
