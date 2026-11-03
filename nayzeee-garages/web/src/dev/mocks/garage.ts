/**
 * Garage app mocks (browser dev only): scenarios for every garage flavour and stateful
 * mockNui handlers for every garage:* callback, so the whole menu is clickable.
 * Vehicles carry what the client adds in game (class label, model stats) plus stored
 * upgrades (mods) and damage, so the showroom can be judged with realistic data.
 * Scenario ids: garage-grid, garage-list, garage-empty, garage-full, garage-private,
 * garage-private-long, garage-spawner, garage-air, garage-sea, garage-damaged, garage-finance,
 * garage-house, garage-job, garage-rental, garage-big.
 */
import { registerMock } from '../registry';
import { emitNuiMessage, mockNui, onNuiMessage } from '../../lib/nui';
import { defaultInterface, toast } from '../../lib/store';
import type {
  DamageSummary,
  Finance,
  GarageOpenData,
  GarageOptions,
  GarageSummary,
  GarageVehicle,
  ImpoundInfo,
  MemberData,
  ModSummary,
  NuiMessage,
  PlayerOption,
  Role,
  SpawnerVehicleView,
  VehicleStats,
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

/**
 * What NZ.Veh.modelInfo reads in game: [classId, classLabel, topSpeed km/h, speed, acceleration,
 * braking, traction, seats]. Models missing here behave like unknown add-ons (no class / stats).
 */
const MODEL_INFO: Record<string, [number, string, number, number, number, number, number, number]> = {
  // compacts / sedans / coupes
  blista: [0, 'Compacts', 166, 69, 56, 48, 73, 2],
  issi2: [0, 'Compacts', 158, 66, 54, 47, 72, 2],
  panto: [0, 'Compacts', 148, 62, 47, 44, 70, 2],
  asea: [1, 'Sedans', 162, 68, 50, 45, 70, 4],
  schafter3: [1, 'Sedans', 186, 78, 69, 55, 78, 4],
  tailgater2: [1, 'Sedans', 189, 79, 69, 55, 79, 4],
  kanjosj: [3, 'Coupes', 181, 75, 66, 53, 78, 2],
  felon: [3, 'Coupes', 184, 77, 64, 52, 77, 4],
  // SUVs / off-road / vans / commercial
  granger2: [2, 'SUVs', 166, 69, 52, 44, 71, 4],
  baller7: [2, 'SUVs', 178, 74, 60, 47, 73, 4],
  rebla: [2, 'SUVs', 181, 75, 63, 49, 76, 4],
  rebel2: [9, 'Off-road', 158, 66, 54, 42, 74, 2],
  bodhi2: [9, 'Off-road', 152, 63, 48, 40, 71, 4],
  sanchez: [8, 'Motorcycles', 168, 70, 68, 49, 72, 2],
  bison: [12, 'Vans', 151, 63, 38, 34, 62, 4],
  rumpo: [12, 'Vans', 146, 61, 36, 32, 58, 4],
  mule: [20, 'Commercial', 128, 53, 27, 28, 56, 2],
  // muscle / sports / super
  buffalo4: [4, 'Muscle', 199, 83, 76, 57, 80, 4],
  dominator3: [4, 'Muscle', 196, 82, 74, 56, 79, 2],
  gauntlet4: [4, 'Muscle', 195, 81, 75, 54, 77, 2],
  vigero2: [4, 'Muscle', 197, 82, 77, 57, 80, 2],
  elegy: [6, 'Sports', 196, 82, 74, 61, 84, 2],
  jester4: [6, 'Sports', 201, 84, 78, 63, 86, 2],
  paragon: [6, 'Sports', 199, 83, 76, 58, 81, 2],
  comet7: [6, 'Sports', 198, 83, 75, 62, 85, 2],
  italigto: [6, 'Sports', 205, 86, 81, 66, 87, 2],
  tenf2: [6, 'Sports', 200, 84, 77, 64, 86, 2],
  zr350: [6, 'Sports', 192, 80, 71, 57, 80, 4],
  euros: [6, 'Sports', 194, 81, 73, 58, 82, 2],
  sultan2: [6, 'Sports', 188, 79, 70, 56, 83, 4],
  neon: [6, 'Sports', 197, 82, 79, 60, 84, 4],
  kuruma: [6, 'Sports', 182, 76, 64, 52, 80, 4],
  coquette4: [6, 'Sports', 203, 85, 79, 64, 85, 2],
  turismo3: [7, 'Super', 209, 87, 82, 67, 88, 2],
  torero2: [7, 'Super', 212, 89, 83, 70, 90, 2],
  t20: [7, 'Super', 214, 89, 86, 71, 91, 2],
  banshee2: [7, 'Super', 207, 86, 80, 66, 86, 2],
  entityxf: [7, 'Super', 210, 88, 82, 68, 88, 2],
  // bikes
  bati: [8, 'Motorcycles', 211, 88, 82, 60, 76, 2],
  hakuchou2: [8, 'Motorcycles', 219, 91, 88, 58, 74, 1],
  faggio: [8, 'Motorcycles', 92, 38, 34, 30, 52, 2],
  // air
  luxor2: [16, 'Planes', 330, 100, 64, 22, 30, 10],
  shamal: [16, 'Planes', 320, 100, 61, 21, 30, 10],
  mammatus: [16, 'Planes', 210, 88, 40, 18, 28, 4],
  buzzard2: [15, 'Helicopters', 160, 67, 72, 40, 50, 4],
  frogger: [15, 'Helicopters', 156, 65, 66, 38, 50, 4],
  swift: [15, 'Helicopters', 164, 68, 70, 40, 50, 4],
  // sea
  speeder: [14, 'Boats', 118, 49, 70, 20, 40, 4],
  jetmax: [14, 'Boats', 124, 52, 74, 22, 42, 4],
  seashark: [14, 'Boats', 104, 43, 79, 26, 48, 2],
  toro: [14, 'Boats', 121, 50, 72, 21, 41, 4],
  tropic: [14, 'Boats', 96, 40, 58, 18, 36, 4],
  // emergency
  police: [18, 'Emergency', 176, 73, 58, 50, 72, 4],
  police2: [18, 'Emergency', 182, 76, 63, 53, 75, 4],
  police3: [18, 'Emergency', 187, 78, 66, 55, 77, 4],
  police4: [18, 'Emergency', 179, 74, 60, 51, 73, 4],
  policeb: [18, 'Emergency', 172, 72, 69, 51, 70, 1],
  policet: [18, 'Emergency', 148, 62, 37, 34, 60, 8],
  fbi2: [18, 'Emergency', 171, 71, 55, 46, 71, 4],
  riot: [18, 'Emergency', 141, 59, 30, 31, 58, 4],
  ambulance: [18, 'Emergency', 152, 63, 41, 38, 63, 4],
  lguard: [18, 'Emergency', 164, 68, 52, 44, 70, 4],
  firetruk: [18, 'Emergency', 139, 58, 29, 30, 60, 4],
};

/** Class label + model stats the client enrichment adds (absent for unknown models). */
export function modelInfo(model: string): { classId?: number; classLabel?: string; stats?: VehicleStats } {
  const m = MODEL_INFO[model.toLowerCase()];
  if (!m) return {};
  const [classId, classLabel, topSpeed, speed, acceleration, braking, traction, seats] = m;
  return { classId, classLabel, stats: { topSpeed, speed, acceleration, braking, traction, seats } };
}

/** Installed upgrades (level 0 = stock). */
export const mods = (engine: number, brakes: number, transmission: number, suspension: number, armor: number, turbo = false): ModSummary => ({
  engine,
  brakes,
  transmission,
  suspension,
  armor,
  turbo,
});

/** Stored damage summary (health 0–1000, part indexes as in types.ts). */
export const dmg = (d: Partial<DamageSummary> = {}): DamageSummary => ({
  engine: 1000,
  body: 1000,
  tank: 1000,
  doors: [],
  windows: [],
  tyres: [],
  deformed: false,
  ...d,
});

/** Lua encodes an empty list as an object: the interface has to cope with `{}`. */
const luaEmpty = {} as unknown as number[];

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
    ...modelInfo(model),
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
    damage: dmg({ engine: 970, body: 940 }),
    mods: mods(0, 0, 0, 0, 0),
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
    // "Your spaces": the 16 vehicles you own parked here (the shared Sultan is Marcus's).
    capacity: { mode: 'limited', appliesTo: 'player', used: 16, total: 20 },
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
        damage: dmg({ engine: 410, body: 880, windows: [6] }),
        mods: mods(4, 3, 3, 2, 0, true),
      }),
      veh('jester4', 'Dinka Jester RR', 'Dinka', 'MIDNIGHT', {
        ...elsewhere('L4', 'Mirror Park Garage'),
        favourite: true,
        mileage: 12482,
        engine: 63,
        needsService: true,
        damage: dmg({ engine: 630, body: 910 }),
        mods: mods(3, 2, 2, 1, 0, true),
      }),
      veh('paragon', 'Enus Paragon R', 'Enus', 'ENUS 1', {
        ...outInCity(),
        favourite: true,
        mileage: 7620,
        fuel: 54,
        lastUsed: t - 40 * 60,
        mods: mods(2, 1, 1, 0, 3),
      }),
      veh('comet7', 'Pfister Comet S2 Cabrio', 'Pfister', 'PACIFIC', {
        ...elsewhere('L9', 'Paleto Bay Garage'),
        favourite: true,
        sharedWith: 2,
        mileage: 3240,
        mods: mods(4, 3, 3, 3, 0, true),
      }),
      veh('bison', 'Bravado Bison', 'Bravado', 'BGLMK537', {
        trailer: { model: 'boattrailer', label: 'Boat Trailer' },
        mileage: 1240,
        fuel: 64,
        body: 81,
        damage: dmg({ body: 810, doors: [5], deformed: true }),
      }),
      veh('italigto', 'Grotti Itali GTO', 'Grotti', 'GTO 88', {
        finance: finance({}),
        fuel: 98,
        mileage: 1842,
        lastUsed: t - 26 * H,
        mods: mods(4, 3, 3, 4, 2, true),
      }),
      veh('turismo3', 'Grotti Turismo Omaggio', 'Grotti', 'OMAGGIO', {
        nickname: 'Sunday Driver',
        mileage: 326,
        fuel: 91,
        mods: mods(1, 1, 1, 1, 0),
      }),
      veh('tenf2', 'Obey 10F Widebody', 'Obey', 'WIDE 10', { mileage: 3249, lastUsed: t - 6 * D, mods: null }),
      veh('torero2', 'Pegassi Torero XO', 'Pegassi', 'XO CLUB', {
        mileage: 484,
        body: 71,
        damage: dmg({ body: 710, doors: [1], windows: [1] }),
        mods: mods(3, 3, 2, 2, 1, true),
      }),
      veh('zr350', 'Annis ZR350', 'Annis', 'ZR 350', {
        ...impounded(impoundInfo({ releaseAt: t + 2 * H + 14 * 60, reason: 'Parked in a fire lane outside Pillbox Medical' })),
        mileage: 18320,
        body: 46,
        damage: dmg({ body: 460, doors: [0], windows: [0, 6], tyres: [{ index: 1, state: 1 }], deformed: true }),
        mods: mods(2, 2, 2, 3, 0, true),
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
        mods: mods(3, 2, 3, 2, 0, true),
      }),
      veh('neon', 'Pfister Neon', 'Pfister', 'SILENT', { ...outInCity(750), mileage: 4173, fuel: 34, lastUsed: t - 3 * D }),
      veh('kuruma', 'Karin Kuruma', 'Karin', 'KRM 404', {
        finance: finance({ balance: 42000, payment: 7000, paymentsLeft: 6, paymentsTotal: null, intervalHours: 24, nextPaymentHours: 12 }),
        mileage: 22140,
        mods: mods(1, 1, 1, 1, 5),
      }),
      veh('buffalo4', 'Bravado Buffalo STX', 'Bravado', 'BUFF 4', {
        finance: finance({ balance: 186000, payment: 31000, paymentsLeft: 6, paymentsTotal: 12, intervalHours: 72, nextPaymentHours: 0, overdue: true }),
        canDrive: false,
        reason: 'A finance payment is overdue',
        mileage: 9312,
      }),
      veh('granger2', 'Declasse Granger 3600LX', 'Declasse', 'FAMILY 3', { nickname: 'The Tank', mileage: 41230, fuel: 47, mods: mods(1, 1, 0, 2, 4) }),
      veh('sanchez', 'Maibatsu Sanchez', 'Maibatsu', 'DIRT 77', {
        fuel: 18,
        body: 54,
        engine: 72,
        mileage: 6620,
        damage: dmg({ engine: 720, body: 540, tyres: [{ index: 4, state: 2 }] }),
      }),
      veh('bati', 'Pegassi Bati 801', 'Pegassi', 'BATI 801', { ...elsewhere('L3', 'Del Perro Pier'), mileage: 11050 }),
      veh('coquette4', 'Invetero Coquette D10', 'Invetero', 'D10 GOLD', { mileage: 2215, lastUsed: t - 34 * D, mods: mods(4, 3, 3, 4, 0, true) }),
      veh('baller7', 'Gallivanter Baller ST', 'Gallivanter', 'BALLER', {
        blocked: true,
        canDrive: false,
        reason: 'Blocked by server staff — contact an admin',
        mileage: 30110,
      }),
      veh('dominator3', 'Vapid Dominator GTX', 'Vapid', 'GTX 69', { sharedWith: 1, mileage: 15900, lastUsed: t - 9 * H, mods: mods(3, 2, 2, 1, 0) }),
      veh('rebla', 'Übermacht Rebla GTS', 'Übermacht', 'REBLA', { ...elsewhere('L2', 'Pillbox Hill Parking'), mileage: 5240 }),
      veh('hakuchou2', 'Shitzu Hakuchou Drag', 'Shitzu', 'HAKU 2', {
        needsService: true,
        engine: 22,
        mileage: 19870,
        fuel: 66,
        damage: dmg({ engine: 220, body: 900 }),
        mods: mods(4, 2, 3, 0, 0, true),
      }),
      veh('rumpo', 'Bravado Rumpo', 'Bravado', 'DELIVER', { nickname: 'Work Van', mileage: 94210, body: 63, lastUsed: t - 12 * D, damage: null, mods: null }),
      // Add-on model the server no longer streams: no class / stats, never stored with damage saving.
      veh('sultanrsv8', 'Karin Sultan RS V8', 'Karin', 'RSV8', { mileage: 640, lastUsed: t - 20 * D, damage: null, mods: null, image: null }),
    ],
  };
}

function lsiaHangar(): GarageOpenData {
  const t = nowS();
  const air = (model: string, label: string, make: string, plate: string, extra: Partial<GarageVehicle> = {}) =>
    veh(model, label, make, plate, { vehicleType: 'air', garageKey: 'A1', garageName: 'LSIA Hangar', mods: null, ...extra });
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
    veh(model, label, make, plate, { vehicleType: 'sea', garageKey: 'S1', garageName: 'Puerto Del Sol Marina', mods: null, ...extra });
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
      veh('jester4', 'Dinka Jester RR', 'Dinka', 'MIDNIGHT', { ...here, favourite: true, mileage: 12482, mods: mods(3, 2, 2, 1, 0, true) }),
      veh('t20', 'Progen T20', 'Progen', 'T20 PRO', { ...here, mileage: 3410, mods: mods(4, 3, 3, 3, 2, true) }),
      veh('banshee2', 'Bravado Banshee 900R', 'Bravado', 'BNSHEE', {
        ...here,
        mileage: 8812,
        engine: 39,
        needsService: true,
        damage: dmg({ engine: 390, body: 860, windows: [6, 7] }),
      }),
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
      veh('elegy', 'Annis Elegy Retro Custom', 'Annis', 'MESA R6', { ...base, mileage: 26520, mods: mods(4, 3, 3, 3, 0, true) }),
      veh('zr350', 'Annis ZR350', 'Annis', 'MESA RX', { ...base, mileage: 16915, engine: 44, needsService: true, damage: dmg({ engine: 440, body: 900 }) }),
      veh('jester4', 'Dinka Jester RR', 'Dinka', 'MESA RR', { ...base, isOwner: false, ownerName: 'Ava Brooks', mileage: 10820 }),
      veh('sultan2', 'Karin Sultan Classic', 'Karin', 'MESA RS', { ...base, isOwner: false, ownerName: 'Ava Brooks', mileage: 7860, favourite: true }),
    ],
  };
}

/* damaged vehicles after a rough night in Sandy Shores (first one is selected on open) */
function sandyShores(): GarageOpenData {
  const t = nowS();
  const here = { garageKey: 'L7', garageName: 'Sandy Shores Garage' };
  return {
    garage: summary({ key: 'L7', locationId: 7, name: 'Sandy Shores Garage', canGoInside: false }),
    capacity: { mode: 'limited', appliesTo: 'player', used: 5, total: 8 },
    options: { ...OPTIONS, retrieveMode: 'anywhere' },
    spawner: [],
    vehicles: [
      veh('rebel2', 'Karin Rebel', 'Karin', 'DUST 4X4', {
        ...here,
        favourite: true,
        nickname: 'Rust Bucket',
        fuel: 12,
        engine: 23,
        body: 31,
        needsService: true,
        mileage: 148320,
        lastUsed: t - 50 * 60,
        damage: dmg({
          engine: 230,
          body: 310,
          tank: 640,
          doors: [0, 3, 4],
          windows: [0, 1, 6],
          tyres: [
            { index: 0, state: 1 },
            { index: 5, state: 2 },
          ],
          deformed: true,
        }),
        mods: mods(1, 0, 0, 3, 2),
      }),
      veh('mule', 'Maibatsu Mule', 'Maibatsu', 'HAUL 66', {
        ...here,
        fuel: 58,
        engine: 74,
        body: 62,
        mileage: 64210,
        damage: dmg({ engine: 740, body: 620, doors: [5], windows: [4, 7], tyres: [{ index: 45, state: 1 }] }),
      }),
      veh('bodhi2', 'Canis Bodhi', 'Canis', 'BODHI', {
        ...here,
        engine: 88,
        body: 79,
        mileage: 32040,
        // Lua sent empty lists as objects
        damage: { ...dmg({ engine: 880, body: 790, windows: [2] }), doors: luaEmpty, tyres: {} as unknown as DamageSummary['tyres'] },
        mods: mods(2, 1, 1, 4, 0),
      }),
      veh('sanchez', 'Maibatsu Sanchez', 'Maibatsu', 'MUDDY', {
        ...here,
        fuel: 40,
        engine: 66,
        body: 48,
        mileage: 9120,
        damage: dmg({ engine: 660, body: 480, tyres: [{ index: 0, state: 1 }] }),
      }),
      veh('dominator3', 'Vapid Dominator GTX', 'Vapid', 'GTX 70', {
        ...elsewhere('L1', 'Legion Square'),
        canDrive: true,
        reason: null,
        mileage: 15900,
        mods: mods(3, 2, 2, 1, 0),
      }),
    ],
  };
}

/* financed vehicles: the overdue one is selected on open */
function financeLot(): GarageOpenData {
  const here = { garageKey: 'L5', garageName: 'Grove Street Garage' };
  return {
    garage: summary({ key: 'L5', locationId: 5, name: 'Grove Street Garage', canGoInside: false }),
    capacity: { mode: 'limited', appliesTo: 'player', used: 3, total: 6 },
    options: OPTIONS,
    spawner: [],
    vehicles: [
      veh('buffalo4', 'Bravado Buffalo STX', 'Bravado', 'BUFF 4', {
        ...here,
        favourite: true,
        finance: finance({ balance: 186000, payment: 31000, paymentsLeft: 6, paymentsTotal: 12, intervalHours: 72, nextPaymentHours: 0, overdue: true }),
        canDrive: false,
        reason: 'A finance payment is overdue',
        mileage: 9312,
        mods: mods(3, 2, 2, 2, 1, true),
      }),
      veh('italigto', 'Grotti Itali GTO', 'Grotti', 'GTO 88', { ...here, finance: finance({}), fuel: 98, mileage: 1842, mods: mods(4, 3, 3, 4, 2, true) }),
      veh('kuruma', 'Karin Kuruma', 'Karin', 'KRM 404', {
        ...here,
        finance: finance({ balance: 42000, payment: 7000, paymentsLeft: 6, paymentsTotal: null, intervalHours: 24, nextPaymentHours: 12 }),
        mileage: 22140,
        mods: mods(1, 1, 1, 1, 5),
      }),
    ],
  };
}

/* housing integration: a house garage (key H…) */
function houseGarage(): GarageOpenData {
  const here = { garageKey: 'H3671', garageName: '3671 Whispymound Dr' };
  return {
    garage: summary({ key: 'H3671', locationId: 'H3671', kind: 'house', name: '3671 Whispymound Dr', canGoInside: false }),
    capacity: { mode: 'limited', appliesTo: 'total', used: 3, total: 4 },
    options: OPTIONS,
    spawner: [],
    vehicles: [
      veh('tailgater2', 'Obey Tailgater S', 'Obey', 'HOME 1', { ...here, favourite: true, mileage: 8840, mods: mods(2, 2, 1, 1, 0) }),
      veh('felon', 'Lampadati Felon', 'Lampadati', 'FELON', { ...here, isOwner: false, ownerName: 'Ava Brooks', sharedBy: 'Ava Brooks', mileage: 21980 }),
      veh('faggio', 'Pegassi Faggio', 'Pegassi', 'ZOOM', { ...here, nickname: 'Errand Runner', fuel: 31, mileage: 1430 }),
    ],
  };
}

/* job garage with a persistent fleet (owned by the job) */
function emsFleet(): GarageOpenData {
  const t = nowS();
  const fleet = { garageKey: 'J8', garageName: 'Pillbox Medical Fleet', isOwner: false, ownerName: 'Los Santos EMS' };
  return {
    garage: summary({ key: 'J8', locationId: 8, kind: 'job', name: 'Pillbox Medical Fleet', source: 'owned', canGoInside: false, jobLabel: 'EMS' }),
    capacity: { mode: 'limited', appliesTo: 'total', used: 4, total: 10 },
    options: { ...OPTIONS, garageTransfer: false, playerTransfer: false, sell: false, share: false },
    spawner: [],
    vehicles: [
      veh('ambulance', 'Brute Ambulance', 'Brute', 'EMS 01', { ...fleet, mileage: 40320, lastUsed: t - 4 * H, mods: mods(2, 2, 2, 1, 0) }),
      veh('ambulance', 'Brute Ambulance', 'Brute', 'EMS 02', {
        ...fleet,
        mileage: 51280,
        engine: 46,
        needsService: true,
        damage: dmg({ engine: 460, body: 820, windows: [6] }),
      }),
      veh('lguard', 'Declasse Lifeguard', 'Declasse', 'EMS 07', { ...fleet, mileage: 12010 }),
      veh('firetruk', 'MTL Fire Truck', 'MTL', 'LSFD 3', { ...fleet, ...outInCity(), mileage: 9020 }),
    ],
  };
}

function spawnerVehicle(index: number, model: string, label: string, make: string, plate: string, price = 0): SpawnerVehicleView {
  return {
    index,
    model,
    hash: joaat(model),
    plate,
    price,
    vehicleType: 'car' as VehicleType,
    label,
    make,
    image: model,
    ...modelInfo(model),
  };
}

function policeSpawner(): GarageOpenData {
  const s = spawnerVehicle;
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

/* public spawner (rental lot) */
function rentalLot(): GarageOpenData {
  const s = spawnerVehicle;
  return {
    garage: summary({ key: 'L12', locationId: 12, name: 'Del Perro Rentals', source: 'spawner', canGoInside: false }),
    capacity: null,
    options: OPTIONS,
    vehicles: [],
    spawner: [
      s(1, 'panto', 'Benefactor Panto', 'Benefactor', 'RENT####', 150),
      s(2, 'blista', 'Dinka Blista', 'Dinka', 'RENT####', 250),
      s(3, 'issi2', 'Weeny Issi', 'Weeny', 'RENT####', 250),
      s(4, 'asea', 'Declasse Asea', 'Declasse', 'RENT####', 300),
      s(5, 'faggio', 'Pegassi Faggio', 'Pegassi', '', 90),
      s(6, 'bison', 'Bravado Bison', 'Bravado', 'RENT##@@', 600),
      s(7, 'rumpo', 'Bravado Rumpo', 'Bravado', 'RENT##@@', 650),
    ],
  };
}

/* a big collection (40 spaces) to check the compact capacity bar */
function bigCollection(): GarageOpenData {
  const d = legionSquare();
  const used = d.vehicles.filter((v) => v.isOwner && v.here && v.state === 'garaged').length;
  return {
    ...d,
    garage: { ...d.garage, key: 'L20', name: 'Vinewood Car Club', canGoInside: true },
    capacity: { mode: 'limited', appliesTo: 'player', used, total: 40 },
  };
}

/* private garage with a long name, 20 spaces and two copies: the busiest header there is */
function laMesaLong(): GarageOpenData {
  const d = laMesa();
  return {
    ...d,
    garage: {
      ...d.garage,
      name: 'Vinewood Hills Motor Club & Collectors Lounge — East Wing',
      groups: [
        { id: 12, label: 'Vinewood Hills Motor Club & Collectors Lounge — East Wing #1' },
        { id: 31, label: 'Vinewood Hills Motor Club & Collectors Lounge — East Wing #2' },
      ],
    },
    capacity: { mode: 'limited', appliesTo: 'total', used: 4, total: 20 },
  };
}

/* ───────────────────────── stateful mock backend ───────────────────────── */

const state: { data: GarageOpenData | null } = { data: null };

onNuiMessage((msg: NuiMessage) => {
  if (msg.action === 'open' && msg.data.app === 'garage') state.data = clone(msg.data.data as GarageOpenData);
});

const find = (plate: string) => state.data?.vehicles.find((v) => v.plate === plate) ?? null;
/** In game Lua shows these through the notify integration; the browser harness logs them. */
const notify = (type: 'success' | 'error' | 'info' | 'warning', message: string, title?: string) =>
  toast({ type, message, title });
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

const km: NuiMessage = { action: 'settings', data: { ...defaultInterface, defaultView: 'grid', distanceUnit: 'km' } };

registerMock({ id: 'garage-grid', group: 'Garage', label: 'Public garage — comfortable rows (25 vehicles)', messages: [view('grid'), open(legionSquare())] });
registerMock({ id: 'garage-list', group: 'Garage', label: 'Public garage — compact rows', messages: [view('list'), open(legionSquare())] });
registerMock({ id: 'garage-empty', group: 'Garage', label: 'Empty garage', messages: [view('grid'), open(pillboxEmpty())] });
registerMock({ id: 'garage-full', group: 'Garage', label: 'Full garage (6/6)', messages: [view('grid'), open(mirrorParkFull())] });
registerMock({ id: 'garage-big', group: 'Garage', label: 'Big collection (16/40 spaces)', messages: [view('grid'), open(bigCollection())] });
registerMock({ id: 'garage-damaged', group: 'Garage', label: 'Damaged vehicles (wreck selected)', messages: [km, open(sandyShores())] });
registerMock({ id: 'garage-finance', group: 'Garage', label: 'Financed vehicles (overdue selected)', messages: [view('grid'), open(financeLot())] });
registerMock({ id: 'garage-private', group: 'Garage', label: 'Private garage (members, 2 copies)', messages: [view('grid'), open(laMesa())] });
registerMock({ id: 'garage-private-long', group: 'Garage', label: 'Private garage — long name, 20 spaces', messages: [view('grid'), open(laMesaLong())] });
registerMock({ id: 'garage-house', group: 'Garage', label: 'House garage (housing integration)', messages: [view('grid'), open(houseGarage())] });
registerMock({ id: 'garage-job', group: 'Garage', label: 'Job garage — owned fleet (EMS)', messages: [view('grid'), open(emsFleet())] });
registerMock({ id: 'garage-spawner', group: 'Garage', label: 'Job spawner (LSPD)', messages: [view('list'), open(policeSpawner())] });
registerMock({ id: 'garage-rental', group: 'Garage', label: 'Public spawner (rentals, prices)', messages: [view('grid'), open(rentalLot())] });
registerMock({ id: 'garage-air', group: 'Garage', label: 'Air hangar (km/h)', messages: [km, open(lsiaHangar())] });
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
