/**
 * Garage app mocks (browser dev only): scenarios for every garage flavour and stateful
 * mockNui handlers for every garage:* callback, so the whole menu is clickable.
 * Scenario ids: garage-grid, garage-list, garage-empty, garage-private, garage-spawner,
 * garage-air, garage-sea, garage-full.
 */
import { registerMock } from '../registry';
import { emitNuiMessage, mockNui, onNuiMessage } from '../../lib/nui';
import { defaultInterface } from '../../lib/store';
import type {
  Finance,
  GarageOpenData,
  GarageOptions,
  GarageSummary,
  GarageVehicle,
  ImpoundInfo,
  MemberData,
  NuiMessage,
  PlayerOption,
  Role,
  SpawnerVehicleView,
  VehicleType,
} from '../../lib/types';

/* ───────────────────────── helpers ───────────────────────── */

export const nowS = () => Math.floor(Date.now() / 1000);
const H = 3600;
const D = 86400;
const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
const clone = <T,>(v: T): T => JSON.parse(JSON.stringify(v)) as T;

/** GTA "one at a time" hash (signed), so mock hashes look real. */
export function joaat(text: string): number {
  let h = 0;
  for (const ch of text.toLowerCase()) {
    h = (h + ch.charCodeAt(0)) >>> 0;
    h = (h + (h << 10)) >>> 0;
    h = (h ^ (h >>> 6)) >>> 0;
  }
  h = (h + (h << 3)) >>> 0;
  h = (h ^ (h >>> 11)) >>> 0;
  h = (h + (h << 15)) >>> 0;
  return h | 0;
}

export const ME = { identifier: 'NZV41207', name: 'Jordan Vale' };

export const ONLINE_PLAYERS: PlayerOption[] = [
  { serverId: 7, name: 'Ava Brooks' },
  { serverId: 12, name: 'Lena Ortiz' },
  { serverId: 15, name: 'Dmitri Volkov' },
  { serverId: 21, name: 'Kenji Tanaka' },
  { serverId: 33, name: 'Priya Shah' },
  { serverId: 41, name: 'Sam Carter' },
  { serverId: 48, name: 'Noah Fischer' },
  { serverId: 56, name: 'Isabella Rossi' },
  { serverId: 63, name: 'Marcus Reid' },
  { serverId: 72, name: 'Chloe Martin' },
  { serverId: 85, name: 'Tomás Herrera' },
  { serverId: 90, name: 'Grace Okafor' },
];

/** Vehicle factory with sensible defaults (parked here, healthy, owned by ME). */
export function veh(
  model: string,
  label: string,
  make: string,
  plate: string,
  extra: Partial<GarageVehicle> = {},
): GarageVehicle {
  return {
    label,
    make,
    image: model.toLowerCase(),
    plate,
    model,
    hash: joaat(model),
    vehicleType: 'car',
    nickname: null,
    state: 'garaged',
    garageKey: 'L1',
    garageName: 'Legion Square',
    here: true,
    fuel: 82,
    engine: 97,
    body: 94,
    mileage: 12840,
    favourite: false,
    isOwner: true,
    ownerName: ME.name,
    sharedBy: null,
    sharedWith: 0,
    finance: null,
    impound: null,
    trailer: null,
    canDrive: true,
    reason: null,
    canRecover: false,
    recoverFee: 0,
    needsService: false,
    blocked: false,
    lastUsed: nowS() - 2 * D,
    ...extra,
  };
}

/** Parked at another garage (retrieveMode 'last' → cannot be driven from here). */
const elsewhere = (garageKey: string, garageName: string): Partial<GarageVehicle> => ({
  here: false,
  garageKey,
  garageName,
  canDrive: false,
  reason: `Parked at ${garageName}`,
});

const outInCity = (recoverFee = 0): Partial<GarageVehicle> => ({
  state: 'out',
  here: false,
  canDrive: false,
  canRecover: recoverFee > 0,
  recoverFee,
  reason: recoverFee > 0 ? 'Out — its last position is unknown. Recover it to bring it back here.' : 'Already out in the city',
});

export function impoundInfo(extra: Partial<ImpoundInfo> = {}): ImpoundInfo {
  return {
    locationId: 5,
    locationName: 'Davis Impound',
    reason: 'Parked in a fire lane',
    fee: 500,
    by: 'NZP00071',
    byName: 'Officer Hayes',
    at: nowS() - 5 * H,
    releaseAt: nowS() - 30 * 60,
    retrievable: true,
    ...extra,
  };
}

const impounded = (info: ImpoundInfo): Partial<GarageVehicle> => ({
  state: 'impounded',
  here: false,
  garageKey: null,
  garageName: info.locationName,
  impound: info,
  canDrive: false,
  reason: `Impounded at ${info.locationName}`,
});

const finance = (f: Partial<Finance>): Finance => ({
  balance: 960000,
  payment: 60000,
  paymentsLeft: 16,
  paymentsTotal: 24,
  intervalHours: 168,
  nextPaymentHours: 71,
  overdue: false,
  ...f,
});

const OPTIONS: GarageOptions = {
  retrieveMode: 'last',
  garageTransfer: true,
  playerTransfer: true,
  sell: true,
  share: true,
  garageFee: 2500,
  playerFee: 5000,
};

function summary(extra: Partial<GarageSummary>): GarageSummary {
  return {
    key: 'L1',
    locationId: 1,
    kind: 'garage',
    name: 'Legion Square',
    vehicleType: 'car',
    source: 'personal',
    isPrivate: false,
    groupId: null,
    groups: [],
    role: null,
    canGoInside: true,
    canManage: false,
    canSellGarage: false,
    jobLabel: null,
    ...extra,
  };
}

/* ───────────────────────── data sets ───────────────────────── */

export function legionSquare(): GarageOpenData {
  const t = nowS();
  return {
    garage: summary({}),
    capacity: { mode: 'limited', appliesTo: 'player', used: 9, total: 12 },
    options: OPTIONS,
    spawner: [],
    vehicles: [
      veh('elegy', 'Annis Elegy Retro Custom', 'Annis', 'RETRO 6', {
        favourite: true,
        fuel: 76,
        engine: 41,
        body: 88,
        needsService: true,
        mileage: 28360,
        lastUsed: t - 3 * H,
      }),
      veh('jester4', 'Dinka Jester RR', 'Dinka', 'MIDNIGHT', {
        ...elsewhere('L4', 'Mirror Park Garage'),
        favourite: true,
        mileage: 12482,
        engine: 63,
        needsService: true,
      }),
      veh('paragon', 'Enus Paragon R', 'Enus', 'ENUS 1', { ...outInCity(), favourite: true, mileage: 7620, fuel: 54, lastUsed: t - 40 * 60 }),
      veh('comet7', 'Pfister Comet S2 Cabrio', 'Pfister', 'PACIFIC', {
        ...elsewhere('L9', 'Paleto Bay Garage'),
        favourite: true,
        sharedWith: 2,
        mileage: 3240,
      }),
      veh('bison', 'Bravado Bison', 'Bravado', 'BGLMK537', {
        trailer: { model: 'boattrailer', label: 'Boat Trailer' },
        mileage: 1240,
        fuel: 64,
      }),
      veh('italigto', 'Grotti Itali GTO', 'Grotti', 'GTO 88', {
        finance: finance({}),
        fuel: 98,
        mileage: 1842,
        lastUsed: t - 26 * H,
      }),
      veh('turismo3', 'Grotti Turismo Omaggio', 'Grotti', 'OMAGGIO', { nickname: 'Sunday Driver', mileage: 326, fuel: 91, favourite: false }),
      veh('tenf2', 'Obey 10F Widebody', 'Obey', 'WIDE 10', { mileage: 3249, lastUsed: t - 6 * D }),
      veh('torero2', 'Pegassi Torero XO', 'Pegassi', 'XO CLUB', { mileage: 484, body: 71 }),
      veh('zr350', 'Annis ZR350', 'Annis', 'ZR 350', {
        ...impounded(impoundInfo({ releaseAt: t + 2 * H + 14 * 60, reason: 'Parked in a fire lane outside Pillbox Medical' })),
        mileage: 18320,
        body: 46,
      }),
      veh('euros', 'Annis Euros', 'Annis', 'DVS 23', {
        ...impounded(
          impoundInfo({
            fee: 2500,
            retrievable: false,
            reason: 'Held as evidence in an ongoing investigation',
            byName: 'Sgt. Morales',
            releaseAt: t - H,
          }),
        ),
        mileage: 15430,
      }),
      veh('sultan2', 'Karin Sultan Classic', 'Karin', 'MESA RS', {
        isOwner: false,
        ownerName: 'Marcus Reid',
        sharedBy: 'Marcus Reid',
        mileage: 7860,
      }),
      veh('neon', 'Pfister Neon', 'Pfister', 'SILENT', { ...outInCity(750), mileage: 4173, fuel: 34, lastUsed: t - 3 * D }),
      veh('kuruma', 'Karin Kuruma', 'Karin', 'KRM 404', {
        finance: finance({ balance: 42000, payment: 7000, paymentsLeft: 6, paymentsTotal: null, intervalHours: 24, nextPaymentHours: 12 }),
        mileage: 22140,
      }),
      veh('buffalo4', 'Bravado Buffalo STX', 'Bravado', 'BUFF 4', {
        finance: finance({ balance: 186000, payment: 31000, paymentsLeft: 6, paymentsTotal: 12, intervalHours: 72, nextPaymentHours: 0, overdue: true }),
        canDrive: false,
        reason: 'A finance payment is overdue',
        mileage: 9312,
      }),
      veh('granger2', 'Declasse Granger 3600LX', 'Declasse', 'FAMILY 3', { nickname: 'The Tank', mileage: 41230, fuel: 47 }),
      veh('sanchez', 'Maibatsu Sanchez', 'Maibatsu', 'DIRT 77', { fuel: 18, body: 54, engine: 72, mileage: 6620 }),
      veh('bati', 'Pegassi Bati 801', 'Pegassi', 'BATI 801', { ...elsewhere('L3', 'Del Perro Pier'), mileage: 11050 }),
      veh('coquette4', 'Invetero Coquette D10', 'Invetero', 'D10 GOLD', { mileage: 2215, lastUsed: t - 34 * D }),
      veh('baller7', 'Gallivanter Baller ST', 'Gallivanter', 'BALLER', {
        blocked: true,
        canDrive: false,
        reason: 'Blocked by server staff — contact an admin',
        mileage: 30110,
      }),
      veh('dominator3', 'Vapid Dominator GTX', 'Vapid', 'GTX 69', { sharedWith: 1, mileage: 15900, lastUsed: t - 9 * H }),
      veh('rebla', 'Übermacht Rebla GTS', 'Übermacht', 'REBLA', { ...elsewhere('L2', 'Pillbox Hill Parking'), mileage: 5240 }),
      veh('hakuchou2', 'Shitzu Hakuchou Drag', 'Shitzu', 'HAKU 2', { needsService: true, engine: 22, mileage: 19870, fuel: 66 }),
      veh('rumpo', 'Bravado Rumpo', 'Bravado', 'DELIVER', { nickname: 'Work Van', mileage: 94210, body: 63, lastUsed: t - 12 * D }),
    ],
  };
}

function lsiaHangar(): GarageOpenData {
  const t = nowS();
  const air = (model: string, label: string, make: string, plate: string, extra: Partial<GarageVehicle> = {}) =>
    veh(model, label, make, plate, { vehicleType: 'air', garageKey: 'A1', garageName: 'LSIA Hangar', ...extra });
  return {
    garage: summary({ key: 'A1', locationId: 14, name: 'LSIA Hangar', vehicleType: 'air', canGoInside: false }),
    capacity: { mode: 'limited', appliesTo: 'player', used: 3, total: 4 },
    options: OPTIONS,
    spawner: [],
    vehicles: [
      air('luxor2', 'Buckingham Luxor Deluxe', 'Buckingham', '83YBY323', { favourite: true, fuel: 65, mileage: 1820, lastUsed: t - 5 * H }),
      air('shamal', 'Buckingham Shamal', 'Buckingham', 'SHAMAL 1', { mileage: 6420, engine: 88 }),
      air('buzzard2', 'Nagasaki Buzzard', 'Nagasaki', 'HELI 22', { fuel: 41, mileage: 980, favourite: true }),
      air('frogger', 'Maibatsu Frogger', 'Maibatsu', 'FROG 7', { ...elsewhere('A3', 'Sandy Shores Airfield'), mileage: 2290 }),
      air('mammatus', 'Jobuilt Mammatus', 'Jobuilt', 'CROP 41', { ...outInCity(), mileage: 640 }),
      air('swift', 'Buckingham Swift', 'Buckingham', 'SWIFT', {
        finance: finance({ balance: 380000, payment: 47500, paymentsLeft: 8, paymentsTotal: 10, intervalHours: 168, nextPaymentHours: 140 }),
        mileage: 410,
      }),
    ],
  };
}

function marina(): GarageOpenData {
  const sea = (model: string, label: string, make: string, plate: string, extra: Partial<GarageVehicle> = {}) =>
    veh(model, label, make, plate, { vehicleType: 'sea', garageKey: 'S1', garageName: 'Puerto Del Sol Marina', ...extra });
  return {
    garage: summary({ key: 'S1', locationId: 18, name: 'Puerto Del Sol Marina', vehicleType: 'sea', canGoInside: false }),
    capacity: { mode: 'unlimited', appliesTo: 'player', used: 4, total: 0 },
    options: OPTIONS,
    spawner: [],
    vehicles: [
      sea('speeder', 'Pegassi Speeder', 'Pegassi', 'WAVE 1', { favourite: true, mileage: 380 }),
      sea('jetmax', 'Shitzu Jetmax', 'Shitzu', 'JETMAX', { nickname: 'Salt Life', mileage: 1210 }),
      sea('seashark', 'Speedophile Seashark', 'Speedophile', 'SHARK 9', { fuel: 23, mileage: 96 }),
      sea('toro', 'Lampadati Toro', 'Lampadati', 'TORO', { ...elsewhere('S2', 'Paleto Cove Dock'), mileage: 744 }),
      sea('tropic', 'Shitzu Tropic', 'Shitzu', 'TROPIC 4', { ...outInCity(500), mileage: 2003 }),
    ],
  };
}

function pillboxEmpty(): GarageOpenData {
  return {
    garage: summary({ key: 'L2', locationId: 2, name: 'Pillbox Hill Parking', canGoInside: false }),
    capacity: { mode: 'limited', appliesTo: 'player', used: 0, total: 10 },
    options: OPTIONS,
    spawner: [],
    vehicles: [],
  };
}

function mirrorParkFull(): GarageOpenData {
  const here = { garageKey: 'L4', garageName: 'Mirror Park Garage' };
  return {
    garage: summary({ key: 'L4', locationId: 4, name: 'Mirror Park Garage', canGoInside: false }),
    capacity: { mode: 'limited', appliesTo: 'total', used: 6, total: 6 },
    options: { ...OPTIONS, sell: false, share: false },
    spawner: [],
    vehicles: [
      veh('jester4', 'Dinka Jester RR', 'Dinka', 'MIDNIGHT', { ...here, favourite: true, mileage: 12482 }),
      veh('t20', 'Progen T20', 'Progen', 'T20 PRO', { ...here, mileage: 3410 }),
      veh('banshee2', 'Bravado Banshee 900R', 'Bravado', 'BNSHEE', { ...here, mileage: 8812, engine: 39, needsService: true }),
      veh('schafter3', 'Benefactor Schafter V12', 'Benefactor', 'SCHFTR', { ...here, mileage: 25120 }),
      veh('gauntlet4', 'Bravado Gauntlet Hellfire', 'Bravado', 'HELLFIRE', { ...here, mileage: 6050, fuel: 29 }),
      veh('entityxf', 'Överflöd Entity XF', 'Överflöd', 'ENTITY', { ...here, mileage: 1999 }),
    ],
  };
}

/* private garage with two copies (groups) */
function laMesa(groupId = 12): GarageOpenData {
  const groups = [
    { id: 12, label: 'La Mesa Motor Club #1' },
    { id: 31, label: 'La Mesa Motor Club #2' },
  ];
  const base = { garageKey: `G${groupId}`, garageName: 'La Mesa Motor Club' };
  if (groupId === 31) {
    return {
      garage: summary({
        key: 'G31',
        locationId: 22,
        kind: 'private',
        name: 'La Mesa Motor Club',
        isPrivate: true,
        groupId: 31,
        groups,
        role: 'member',
        canGoInside: true,
        canManage: false,
        canSellGarage: false,
      }),
      capacity: { mode: 'limited', appliesTo: 'total', used: 2, total: 8 },
      options: OPTIONS,
      spawner: [],
      vehicles: [
        veh('vigero2', 'Declasse Vigero ZX', 'Declasse', 'ZX MESA', { ...base, isOwner: false, ownerName: 'Lena Ortiz', mileage: 4420 }),
        veh('kanjosj', 'Dinka Kanjo SJ', 'Dinka', 'KANJO', { ...base, mileage: 1260, favourite: true }),
      ],
    };
  }
  return {
    garage: summary({
      key: 'G12',
      locationId: 22,
      kind: 'private',
      name: 'La Mesa Motor Club',
      isPrivate: true,
      groupId: 12,
      groups,
      role: 'owner',
      canGoInside: true,
      canManage: true,
      canSellGarage: true,
    }),
    capacity: { mode: 'limited', appliesTo: 'total', used: 4, total: 8 },
    options: OPTIONS,
    spawner: [],
    vehicles: [
      veh('elegy', 'Annis Elegy Retro Custom', 'Annis', 'MESA R6', { ...base, mileage: 26520 }),
      veh('zr350', 'Annis ZR350', 'Annis', 'MESA RX', { ...base, mileage: 16915, engine: 44, needsService: true }),
      veh('jester4', 'Dinka Jester RR', 'Dinka', 'MESA RR', { ...base, isOwner: false, ownerName: 'Ava Brooks', mileage: 10820 }),
      veh('sultan2', 'Karin Sultan Classic', 'Karin', 'MESA RS', { ...base, isOwner: false, ownerName: 'Ava Brooks', mileage: 7860, favourite: true }),
    ],
  };
}

function policeSpawner(): GarageOpenData {
  const s = (index: number, model: string, label: string, make: string, plate: string, price = 0): SpawnerVehicleView => ({
    index,
    model,
    hash: joaat(model),
    plate,
    price,
    vehicleType: 'car' as VehicleType,
    label,
    make,
    image: model,
  });
  return {
    garage: summary({
      key: 'J3',
      locationId: 31,
      kind: 'job',
      name: 'Mission Row PD',
      source: 'spawner',
      canGoInside: false,
      jobLabel: 'LSPD',
    }),
    capacity: null,
    options: OPTIONS,
    vehicles: [],
    spawner: [
      s(1, 'police', 'Vapid Police Cruiser', 'Vapid', 'LSPD####'),
      s(2, 'police2', 'Bravado Buffalo Police Cruiser', 'Bravado', 'LSPD####'),
      s(3, 'police3', 'Vapid Police Interceptor', 'Vapid', 'LSPD##@@'),
      s(4, 'police4', 'Vapid Unmarked Cruiser', 'Vapid', ''),
      s(5, 'policeb', 'Western Police Bike', 'Western', 'LSPDB###'),
      s(6, 'policet', 'Declasse Police Transporter', 'Declasse', 'LSPD-T1'),
      s(7, 'fbi2', 'Declasse Granger FIB', 'Declasse', ''),
      s(8, 'riot', 'Brute Police Riot', 'Brute', 'SWAT 01', 1500),
    ],
  };
}

/* ───────────────────────── stateful mock backend ───────────────────────── */

const state: { data: GarageOpenData | null } = { data: null };

onNuiMessage((msg: NuiMessage) => {
  if (msg.action === 'open' && msg.data.app === 'garage') state.data = clone(msg.data.data as GarageOpenData);
});

const find = (plate: string) => state.data?.vehicles.find((v) => v.plate === plate) ?? null;
const notify = (type: 'success' | 'error' | 'info' | 'warning', message: string, title?: string) =>
  emitNuiMessage({ action: 'notify', data: { type, message, title } });
const closeGarage = () => emitNuiMessage({ action: 'close', data: { app: 'garage' } });

const shares = new Map<string, { identifier: string; name: string }[]>([
  [
    'PACIFIC',
    [
      { identifier: 'NZV10007', name: 'Ava Brooks' },
      { identifier: 'NZV10012', name: 'Lena Ortiz' },
    ],
  ],
  ['GTX 69', [{ identifier: 'NZV10021', name: 'Kenji Tanaka' }]],
]);
const MAX_SHARES = 3;

let members: MemberData['members'] = [
  { identifier: ME.identifier, name: ME.name, role: 'owner', you: true, online: true },
  { identifier: 'NZV10007', name: 'Ava Brooks', role: 'member', you: false, online: true },
  { identifier: 'NZV10063', name: 'Marcus Reid', role: 'member', you: false, online: false },
];

const memberData = (): MemberData => ({
  members: clone(members),
  players: ONLINE_PLAYERS.filter((p) => !members.some((m) => m.name === p.name)),
  canManage: !!state.data?.garage.canManage,
});

const shareData = (plate: string): ShareDataLike => {
  const list = shares.get(plate) ?? [];
  return {
    sharedWith: clone(list),
    players: ONLINE_PLAYERS.filter((p) => !list.some((s) => s.name === p.name)),
    max: MAX_SHARES,
  };
};
type ShareDataLike = { sharedWith: { identifier: string; name: string }[]; players: PlayerOption[]; max: number };

mockNui('garage:refresh', async () => {
  await wait(150);
  return state.data ? clone(state.data) : { ok: false, error: 'No garage open' };
});

mockNui('garage:drive', async ({ plate }) => {
  const v = find(plate);
  await wait(900);
  if (!v) return { ok: false, error: 'Vehicle not found' };
  if (!v.canDrive) return { ok: false, error: v.reason ?? 'You cannot drive this vehicle' };
  if (v.trailer) return { ok: false, error: 'There is not enough room to unhitch the trailer here. Try another spot.' };
  setTimeout(() => {
    closeGarage();
    notify('success', `Your ${v.nickname ?? v.label} is waiting outside.`, 'Vehicle ready');
  }, 900);
  return null;
});

mockNui('garage:spawner', async ({ index }) => {
  const s = state.data?.spawner.find((x) => x.index === index);
  await wait(900);
  if (!s) return { ok: false, error: 'Vehicle not found' };
  if (s.price > 0) notify('info', `A deposit of $${s.price.toLocaleString('en-US')} was taken from your bank.`);
  setTimeout(() => {
    closeGarage();
    notify('success', `${s.label} is ready. Store it here when you are done.`, 'Vehicle ready');
  }, 700);
  return null;
});

mockNui('garage:favourite', ({ plate, value }) => {
  const v = find(plate);
  if (v) v.favourite = value;
  return null;
});

mockNui('garage:rename', ({ plate, name }) => {
  const v = find(plate);
  if (!v) return { ok: false, error: 'Vehicle not found' };
  v.nickname = name && name.trim() ? name.trim().slice(0, 32) : null;
  return null;
});

mockNui('garage:transferOptions', async ({ plate }) => {
  await wait(450);
  const current = state.data?.garage.key;
  const garages = [
    { key: 'L1', name: 'Legion Square', spacesLeft: 3, fee: 2500 },
    { key: 'L2', name: 'Pillbox Hill Parking', spacesLeft: 7, fee: 2500 },
    { key: 'L4', name: 'Mirror Park Garage', spacesLeft: 0, fee: 2500 },
    { key: 'L3', name: 'Del Perro Pier', spacesLeft: 1, fee: 3000 },
    { key: 'L5', name: 'Grove Street Garage', spacesLeft: 10, fee: 2000 },
    { key: 'L9', name: 'Paleto Bay Garage', spacesLeft: null, fee: 4500 },
    { key: 'L7', name: 'Sandy Shores Garage', spacesLeft: null, fee: 3500 },
  ].filter((g) => g.key !== current && g.key !== find(plate)?.garageKey);
  return { garages, players: ONLINE_PLAYERS, garageFee: 2500, playerFee: 5000 };
});

mockNui('garage:transfer', async ({ plate, type, target }) => {
  await wait(600);
  const d = state.data;
  const v = find(plate);
  if (!d || !v) return { ok: false, error: 'Vehicle not found' };
  if (type === 'player') {
    d.vehicles = d.vehicles.filter((x) => x.plate !== plate);
    return null;
  }
  const names: Record<string, string> = {
    L1: 'Legion Square',
    L2: 'Pillbox Hill Parking',
    L3: 'Del Perro Pier',
    L5: 'Grove Street Garage',
    L7: 'Sandy Shores Garage',
    L9: 'Paleto Bay Garage',
  };
  if (target === 'L4') return { ok: false, error: 'Mirror Park Garage is full' };
  Object.assign(v, elsewhere(String(target), names[String(target)] ?? 'another garage'));
  return null;
});

mockNui('garage:shares', async ({ plate }) => {
  await wait(350);
  return shareData(plate);
});

mockNui('garage:share', async ({ plate, serverId }) => {
  await wait(400);
  const p = ONLINE_PLAYERS.find((x) => x.serverId === serverId);
  if (!p) return { ok: false, error: 'That player is no longer online' };
  const list = shares.get(plate) ?? [];
  if (list.length >= MAX_SHARES) return { ok: false, error: `You can share a vehicle with ${MAX_SHARES} players at most` };
  list.push({ identifier: `NZV1${String(serverId).padStart(4, '0')}`, name: p.name });
  shares.set(plate, list);
  const v = find(plate);
  if (v) v.sharedWith = list.length;
  return shareData(plate);
});

mockNui('garage:unshare', async ({ plate, identifier }) => {
  await wait(350);
  const list = (shares.get(plate) ?? []).filter((s) => s.identifier !== identifier);
  shares.set(plate, list);
  const v = find(plate);
  if (v) v.sharedWith = list.length;
  return shareData(plate);
});

mockNui('garage:sell', async ({ serverId, price }) => {
  await wait(500);
  if (serverId === 15) return { ok: false, error: 'Dmitri Volkov is too far away to receive an offer' };
  if (price > 5_000_000) return { ok: false, error: 'That price is above the server limit' };
  return null;
});

mockNui('garage:track', async ({ plate }) => {
  await wait(250);
  const v = find(plate);
  if (v?.state === 'impounded') notify('success', `Waypoint set to ${v.impound?.locationName ?? 'the impound'}.`, 'Waypoint set');
  else if (v?.state === 'out' && v.canRecover) return { ok: false, error: 'The vehicle could not be located' };
  else notify('success', `Waypoint set to your ${v?.nickname ?? v?.label ?? 'vehicle'}.`, 'Waypoint set');
  return null;
});

mockNui('garage:recover', async ({ plate }) => {
  await wait(700);
  const v = find(plate);
  if (!v) return { ok: false, error: 'Vehicle not found' };
  Object.assign(v, {
    state: 'garaged',
    here: true,
    garageKey: state.data?.garage.key ?? null,
    garageName: state.data?.garage.name ?? null,
    canDrive: true,
    canRecover: false,
    recoverFee: 0,
    reason: null,
  });
  return null;
});

mockNui('garage:payFinance', async ({ plate, full }) => {
  await wait(600);
  const v = find(plate);
  if (!v?.finance) return { ok: false, error: 'This vehicle is not financed' };
  if (full) {
    if (v.finance.balance > 500000) return { ok: false, error: 'You do not have enough money in your bank account' };
    v.finance = null;
    if (v.reason === 'A finance payment is overdue') Object.assign(v, { canDrive: true, reason: null });
    return null;
  }
  const f = v.finance;
  const paid = Math.min(f.payment, f.balance);
  f.balance -= paid;
  f.paymentsLeft = Math.max(0, f.paymentsLeft - 1);
  f.nextPaymentHours = f.intervalHours;
  if (f.overdue) {
    f.overdue = false;
    Object.assign(v, { canDrive: true, reason: null });
  }
  if (f.balance <= 0 || f.paymentsLeft === 0) v.finance = null;
  return v.finance ? clone(v.finance) : null;
});

mockNui('garage:goInside', async () => {
  await wait(700);
  const name = state.data?.garage.name ?? 'the garage';
  closeGarage();
  notify('info', `Entering ${name}…`);
  return null;
});

mockNui('garage:directions', async () => {
  await wait(300);
  notify('success', 'Pillbox Hill Parking has 7 free spaces.', 'Waypoint set');
  return null;
});

mockNui('garage:members', async () => {
  await wait(400);
  return memberData();
});

mockNui('garage:memberAdd', async ({ serverId, role }) => {
  await wait(400);
  const p = ONLINE_PLAYERS.find((x) => x.serverId === serverId);
  if (!p) return { ok: false, error: 'That player is no longer online' };
  members = [...members, { identifier: `NZV1${String(serverId).padStart(4, '0')}`, name: p.name, role, you: false, online: true }];
  return memberData();
});

mockNui('garage:memberRole', async ({ identifier, role }: { identifier: string; role: Role }) => {
  await wait(350);
  const owners = members.filter((m) => m.role === 'owner');
  const m = members.find((x) => x.identifier === identifier);
  if (!m) return { ok: false, error: 'Member not found' };
  if (m.role === 'owner' && role === 'member' && owners.length <= 1) return { ok: false, error: 'A garage needs at least one owner' };
  members = members.map((x) => (x.identifier === identifier ? { ...x, role } : x));
  return memberData();
});

mockNui('garage:memberRemove', async ({ identifier }) => {
  await wait(350);
  members = members.filter((m) => m.identifier !== identifier);
  return memberData();
});

mockNui('garage:sellGarage', async () => {
  await wait(600);
  const d = state.data;
  if (d && d.vehicles.length > 0) return { ok: false, error: `Empty the garage before selling it (${d.vehicles.length} vehicles inside)` };
  closeGarage();
  notify('success', 'You sold La Mesa Motor Club and received $25,000.', 'Garage sold');
  return null;
});

mockNui('garage:switchGroup', async ({ groupId }) => {
  await wait(400);
  const next = laMesa(groupId);
  state.data = clone(next);
  return next;
});

/* ───────────────────────── scenarios ───────────────────────── */

const view = (defaultView: 'grid' | 'list'): NuiMessage => ({ action: 'settings', data: { ...defaultInterface, defaultView } });
const open = (data: GarageOpenData): NuiMessage => ({ action: 'open', data: { app: 'garage', data } });

registerMock({ id: 'garage-grid', group: 'Garage', label: 'Public garage — grid (24 vehicles)', messages: [view('grid'), open(legionSquare())] });
registerMock({ id: 'garage-list', group: 'Garage', label: 'Public garage — list', messages: [view('list'), open(legionSquare())] });
registerMock({ id: 'garage-empty', group: 'Garage', label: 'Empty garage', messages: [view('grid'), open(pillboxEmpty())] });
registerMock({ id: 'garage-full', group: 'Garage', label: 'Full garage (6/6)', messages: [view('grid'), open(mirrorParkFull())] });
registerMock({ id: 'garage-private', group: 'Garage', label: 'Private garage (members, 2 copies)', messages: [view('grid'), open(laMesa())] });
registerMock({ id: 'garage-spawner', group: 'Garage', label: 'Job spawner (LSPD)', messages: [view('list'), open(policeSpawner())] });
registerMock({ id: 'garage-air', group: 'Garage', label: 'Air hangar', messages: [view('grid'), open(lsiaHangar())] });
registerMock({ id: 'garage-sea', group: 'Garage', label: 'Boat marina (unlimited)', messages: [view('list'), open(marina())] });

/** Used by the for-sale mocks: the garage menu that opens after buying. */
export function boughtGarage(): GarageOpenData {
  const d = laMesa();
  return {
    ...d,
    garage: { ...d.garage, key: 'G44', groupId: 44, groups: [{ id: 44, label: 'La Mesa Motor Club #3' }] },
    capacity: { mode: 'limited', appliesTo: 'total', used: 0, total: 8 },
    vehicles: [],
  };
}
