/**
 * Admin B mocks (browser dev only): player vehicles, interiors and settings pages.
 *
 * Data: 22 characters, 60+ owned vehicles (34 for Jordan Vale) with props, finance, impound,
 * ownership and service history. Interiors / settings read and write `adminMockDb` from
 * ./admin so admin:refresh stays consistent.
 *
 * Scenarios: admin-interiors, admin-interiors-create, admin-interiors-empty, admin-vehicles,
 * admin-vehicles-results, admin-vehicles-player, admin-vehicles-detail (+ one per dossier tab:
 * -condition, -upgrades, -finance, -history, -activity, -data), admin-vehicles-impounded,
 * admin-vehicles-damaged, admin-vehicles-nostats, admin-vehicles-props, admin-settings,
 * admin-settings-interface.
 *
 * mockNui: admin:players:search, admin:players:vehicles, admin:vehicle:get|assign|update|delete|activity,
 * admin:interior:create|edit|toggle|delete, admin:settings:save, admin:pickPosition.
 * Like the real bridge, update/save handlers drop JSON nulls (nil in Lua), so a UI that relies
 * on null to clear something shows up as "nothing changed" here too.
 */
import { registerMock } from '../registry';
import { emitNuiMessage, mockNui } from '../../lib/nui';
import { adminMockDb } from './admin';
import type { AdminBDevHint } from '../../apps/admin/vehicles/devHint';
import { ALL_ROW_IDS } from '../../apps/admin/settings/schema';
import type {
  AdminOpenData,
  AdminPage,
  AdminVehicleDetail,
  AdminVehicleRow,
  DamageSummary,
  Finance,
  ImpoundInfo,
  Interior,
  OwnershipEntry,
  PlayerSearchRow,
  ServiceEntry,
  Settings,
  VehicleActivity,
  VehicleLabel,
  VehicleState,
  VehicleType,
} from '../../lib/types';

/* ───────────────────────── helpers ───────────────────────── */

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
const clone = <T,>(v: T): T => JSON.parse(JSON.stringify(v)) as T;
const nowS = () => Math.floor(Date.now() / 1000);
const DAY = 86400;
const fail = (error: string) => ({ ok: false as const, error });

/** Deterministic PRNG so screenshots are stable. */
function rng(seed: number) {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

function fakeHash(model: string): number {
  let h = 0;
  for (let i = 0; i < model.length; i++) h = (Math.imul(h, 31) + model.charCodeAt(i)) | 0;
  return h;
}

/* ───────────────────────── reference data ───────────────────────── */

interface Person { identifier: string; name: string; online: boolean }

const PEOPLE: Person[] = [
  { identifier: 'NZV41207', name: 'Jordan Vale', online: true },
  { identifier: 'QX55821', name: 'Lena Ortiz', online: true },
  { identifier: 'KT90344', name: 'Kenji Tanaka', online: false },
  { identifier: 'AB10077', name: 'Ava Brooks', online: true },
  { identifier: 'PS44120', name: 'Priya Shah', online: false },
  { identifier: 'MR73315', name: 'Marcus Reid', online: true },
  { identifier: 'CM20981', name: 'Chloe Martin', online: false },
  { identifier: 'DV66012', name: 'Dmitri Volkov', online: false },
  { identifier: 'JV10233', name: 'Jordan Valdez', online: false },
  { identifier: 'SR38410', name: 'Sofia Romero', online: true },
  { identifier: 'EC72290', name: 'Ethan Clarke', online: false },
  { identifier: 'NF51176', name: 'Noah Fischer', online: false },
  { identifier: 'MC80412', name: 'Maya Chen', online: true },
  { identifier: 'OG29935', name: 'Oliver Grant', online: false },
  { identifier: 'IM64018', name: 'Isla Murphy', online: false },
  { identifier: 'LM47723', name: 'Lucas Moreau', online: true },
  { identifier: 'HS15590', name: 'Hana Sato', online: false },
  { identifier: 'DA90871', name: 'Diego Alvarez', online: false },
  { identifier: 'ZK33064', name: 'Zara Khan', online: true },
  { identifier: 'TL70218', name: 'Theo Lambert', online: false },
  { identifier: 'RW58842', name: 'Ruby Walsh', online: false },
  { identifier: 'JO12907', name: 'Jordan O\'Neill', online: true },
];

const personOf = (identifier: string | null) => PEOPLE.find((p) => p.identifier === identifier) ?? null;

interface Model { model: string; make: string; name: string; type: VehicleType }

const MODELS: Model[] = [
  { model: 'sultan', make: 'Karin', name: 'Sultan', type: 'car' },
  { model: 'sultanrs', make: 'Karin', name: 'Sultan RS', type: 'car' },
  { model: 'elegy', make: 'Annis', name: 'Elegy Retro Custom', type: 'car' },
  { model: 'elegy2', make: 'Annis', name: 'Elegy RH8', type: 'car' },
  { model: 'zentorno', make: 'Pegassi', name: 'Zentorno', type: 'car' },
  { model: 'adder', make: 'Truffade', name: 'Adder', type: 'car' },
  { model: 'comet2', make: 'Pfister', name: 'Comet', type: 'car' },
  { model: 'jester', make: 'Dinka', name: 'Jester', type: 'car' },
  { model: 'banshee', make: 'Bravado', name: 'Banshee', type: 'car' },
  { model: 'buffalo', make: 'Bravado', name: 'Buffalo', type: 'car' },
  { model: 'dominator', make: 'Vapid', name: 'Dominator', type: 'car' },
  { model: 'kuruma', make: 'Karin', name: 'Kuruma', type: 'car' },
  { model: 'schafter2', make: 'Benefactor', name: 'Schafter', type: 'car' },
  { model: 'baller', make: 'Gallivanter', name: 'Baller', type: 'car' },
  { model: 'granger', make: 'Declasse', name: 'Granger', type: 'car' },
  { model: 'sandking', make: 'Vapid', name: 'Sandking XL', type: 'car' },
  { model: 'bison', make: 'Bravado', name: 'Bison', type: 'car' },
  { model: 'cypher', make: 'Übermacht', name: 'Cypher', type: 'car' },
  { model: 'euros', make: 'Annis', name: 'Euros', type: 'car' },
  { model: 'zr350', make: 'Annis', name: 'ZR350', type: 'car' },
  { model: 'futo', make: 'Karin', name: 'Futo', type: 'car' },
  { model: 'issi2', make: 'Weeny', name: 'Issi', type: 'car' },
  { model: 't20', make: 'Progen', name: 'T20', type: 'car' },
  { model: 'turismor', make: 'Grotti', name: 'Turismo R', type: 'car' },
  { model: 'infernus', make: 'Pegassi', name: 'Infernus', type: 'car' },
  { model: 'feltzer2', make: 'Benefactor', name: 'Feltzer', type: 'car' },
  { model: 'ninef', make: 'Obey', name: '9F', type: 'car' },
  { model: 'rapidgt', make: 'Dewbauchee', name: 'Rapid GT', type: 'car' },
  { model: 'bati', make: 'Pegassi', name: 'Bati 801', type: 'car' },
  { model: 'sanchez', make: 'Maibatsu', name: 'Sanchez', type: 'car' },
  { model: 'jetmax', make: 'Shitzu', name: 'Jetmax', type: 'sea' },
  { model: 'speeder', make: 'Pegassi', name: 'Speeder', type: 'sea' },
  { model: 'dinghy', make: 'Nagasaki', name: 'Dinghy', type: 'sea' },
  { model: 'seashark', make: 'Speedophile', name: 'Seashark', type: 'sea' },
  { model: 'luxor', make: 'Buckingham', name: 'Luxor', type: 'air' },
  { model: 'frogger', make: 'Maibatsu', name: 'Frogger', type: 'air' },
  { model: 'swift', make: 'Buckingham', name: 'Swift', type: 'air' },
  { model: 'mammatus', make: 'JoBuilt', name: 'Mammatus', type: 'air' },
];

const modelOf = (model: string): Model =>
  MODELS.find((m) => m.model === model) ?? {
    model,
    make: '',
    name: model.charAt(0).toUpperCase() + model.slice(1),
    type: 'car',
  };

/** What the client adds from the model info (class + estimated performance). Unknown models get nothing. */
// model: [classId, classLabel, topSpeed km/h, speed, acceleration, braking, traction, seats]
const MODEL_INFO: Record<string, [number, string, number, number, number, number, number, number]> = {
  sultan: [6, 'Sports', 189, 74, 64, 41, 72, 4],
  sultanrs: [7, 'Super', 197, 78, 79, 42, 76, 2],
  elegy: [6, 'Sports', 212, 82, 76, 45, 78, 2],
  elegy2: [6, 'Sports', 204, 80, 72, 40, 77, 2],
  zentorno: [7, 'Super', 222, 87, 86, 47, 83, 2],
  adder: [7, 'Super', 225, 88, 81, 42, 79, 2],
  comet2: [6, 'Sports', 198, 78, 70, 40, 74, 2],
  jester: [6, 'Sports', 201, 79, 74, 41, 78, 2],
  banshee: [6, 'Sports', 199, 78, 73, 39, 75, 2],
  buffalo: [6, 'Sports', 186, 73, 62, 38, 71, 4],
  dominator: [4, 'Muscle', 193, 76, 70, 33, 66, 2],
  kuruma: [6, 'Sports', 184, 72, 64, 36, 74, 4],
  schafter2: [1, 'Sedans', 181, 71, 60, 34, 70, 4],
  baller: [2, 'SUVs', 167, 65, 52, 30, 66, 4],
  granger: [2, 'SUVs', 160, 62, 47, 28, 63, 8],
  sandking: [9, 'Off-road', 155, 60, 50, 28, 70, 4],
  bison: [12, 'Vans', 158, 61, 45, 27, 64, 4],
  cypher: [6, 'Sports', 203, 80, 75, 42, 77, 2],
  euros: [6, 'Sports', 200, 79, 72, 41, 76, 2],
  zr350: [6, 'Sports', 199, 78, 73, 40, 77, 2],
  futo: [6, 'Sports', 176, 69, 56, 33, 61, 2],
  issi2: [0, 'Compacts', 160, 62, 49, 30, 62, 2],
  t20: [7, 'Super', 224, 88, 87, 46, 82, 2],
  turismor: [7, 'Super', 221, 87, 84, 45, 81, 2],
  infernus: [7, 'Super', 214, 84, 78, 41, 78, 2],
  feltzer2: [6, 'Sports', 196, 77, 72, 40, 75, 2],
  ninef: [6, 'Sports', 199, 78, 73, 41, 76, 2],
  rapidgt: [6, 'Sports', 197, 77, 70, 40, 75, 2],
  bati: [8, 'Motorcycles', 214, 84, 82, 38, 60, 2],
  sanchez: [8, 'Motorcycles', 154, 60, 58, 32, 55, 2],
  jetmax: [14, 'Boats', 129, 50, 62, 20, 30, 4],
  speeder: [14, 'Boats', 137, 54, 66, 22, 32, 4],
  dinghy: [14, 'Boats', 112, 44, 48, 18, 28, 4],
  seashark: [14, 'Boats', 118, 46, 60, 18, 26, 2],
  luxor: [16, 'Planes', 380, 100, 40, 10, 50, 10],
  frogger: [15, 'Helicopters', 260, 100, 55, 30, 60, 4],
  swift: [15, 'Helicopters', 270, 100, 58, 32, 62, 6],
  mammatus: [16, 'Planes', 245, 96, 35, 15, 40, 4],
};

function labelExtras(model: string): Pick<VehicleLabel, 'classId' | 'classLabel' | 'stats'> {
  const i = MODEL_INFO[model];
  if (!i) return {};
  return {
    classId: i[0],
    classLabel: i[1],
    stats: { topSpeed: i[2], speed: i[3], acceleration: i[4], braking: i[5], traction: i[6], seats: i[7] },
  };
}

const GARAGES: Record<VehicleType, { key: string; name: string }[]> = {
  car: [
    { key: 'L1', name: 'Legion Square' },
    { key: 'L2', name: 'Alta Street' },
    { key: 'L3', name: 'Mirror Park' },
    { key: 'L7', name: 'Harmony' },
    { key: 'L9', name: 'Paleto Bay' },
    { key: 'L16', name: 'Vinewood Hills Estate' },
  ],
  sea: [{ key: 'L12', name: 'Puerto Del Sol Marina' }],
  air: [{ key: 'L11', name: 'LSIA Hangar' }],
};

const SHOPS = ['Los Santos Customs', "Benny's Original Motor Works", 'Hayes Autos', "Beeker's Garage", 'Rally Mechanics'];
const SERVICE_ITEMS = ['Engine oil', 'Spark plugs', 'Air filter', 'Brake pads', 'Tyres', 'Suspension', 'Coolant', 'Clutch'];

/* ───────────────────────── vehicle records ───────────────────────── */

interface MockVehicle {
  row: AdminVehicleRow;
  owner: string | null;
  ownerType: 'player' | 'job' | 'gang';
  job: string | null;
  gang: string | null;
  nickname: string | null;
  mileage: number;
  props: Record<string, unknown>;
  impound: ImpoundInfo | null;
  finance: Finance | null;
  ownership: OwnershipEntry[];
  service: ServiceEntry[];
  /** DamageSummary as Lua sends it (empty lists may be {}), or null = no damage data. */
  damage: unknown;
  lastUsed: number | null;
}

const COSMETIC_KEYS = [
  'modSpoilers', 'modFrontBumper', 'modRearBumper', 'modSideSkirt', 'modExhaust', 'modFrame', 'modGrille', 'modHood',
  'modFender', 'modRightFender', 'modRoof', 'modHorns', 'modVanityPlate', 'modTrimA', 'modOrnaments', 'modDashboard',
  'modDial', 'modDoorSpeaker', 'modSeats', 'modSteeringWheel', 'modShifterLeavers', 'modAPlate', 'modSpeakers',
  'modTrunk', 'modHydrolic', 'modEngineBlock', 'modAirFilter', 'modStruts', 'modArchCover', 'modAerials', 'modTrimB',
  'modTank', 'modWindows',
];

/** ox_lib-style property table (every mod key present, -1 = stock). */
function baseProps(plate: string, model: string, rand: () => number): Record<string, unknown> {
  const pick = <T,>(list: T[]) => list[Math.floor(rand() * list.length)];
  const props: Record<string, unknown> = {
    model: fakeHash(model),
    plate,
    plateIndex: pick([0, 0, 0, 1, 3, 4]),
    bodyHealth: 1000,
    engineHealth: 1000,
    tankHealth: 1000,
    fuelLevel: 100,
    dirtLevel: Math.round(rand() * 8),
    color1: pick([0, 1, 4, 12, 27, 28, 38, 49, 62, 64, 88, 111, 120]),
    color2: pick([0, 1, 4, 12, 111, 120]),
    pearlescentColor: pick([0, 4, 5, 111, 70]),
    interiorColor: 0,
    dashboardColor: 0,
    wheelColor: pick([0, 1, 156, 120]),
    wheels: pick([0, 1, 5, 7]),
    windowTint: pick([-1, -1, -1, 1, 3]),
    xenonColor: 255,
    neonEnabled: [false, false, false, false],
    neonColor: [255, 0, 255],
    tyreSmokeColor: [255, 255, 255],
    extras: {} as Record<string, boolean>,
    modEngine: -1,
    modBrakes: -1,
    modTransmission: -1,
    modSuspension: -1,
    modArmor: -1,
    modTurbo: false,
    modXenon: false,
    modSmokeEnabled: false,
    modFrontWheels: -1,
    modBackWheels: -1,
    modCustomTiresF: false,
    modLivery: -1,
    livery: -1,
  };
  for (const k of COSMETIC_KEYS) props[k] = -1;
  return props;
}

const vehicles = new Map<string, MockVehicle>();

function plateFrom(rand: () => number): string {
  const L = 'ABCDEFGHJKLMNPRSTUVWXYZ';
  const d = () => String(Math.floor(rand() * 10));
  const l = () => L[Math.floor(rand() * L.length)];
  return `${d()}${d()}${l()}${l()}${l()}${d()}${d()}${d()}`;
}

function addVehicle(
  owner: string,
  model: string,
  opts: Partial<{
    plate: string;
    state: VehicleState;
    garage: { key: string; name: string } | null;
    financed: boolean;
    fuel: number;
    engine: number;
    body: number;
    blocked: boolean;
    nickname: string;
    mileage: number;
    seed: number;
  }> = {},
): MockVehicle {
  const rand = rng(opts.seed ?? vehicles.size * 7919 + 17);
  const m = modelOf(model);
  let plate = opts.plate ?? plateFrom(rand);
  while (vehicles.has(plate)) plate = plateFrom(rand);
  const garages = GARAGES[m.type];
  const garage = opts.garage === undefined ? garages[Math.floor(rand() * garages.length)] : opts.garage;
  const fuel = opts.fuel ?? Math.round(55 + rand() * 45);
  const engine = opts.engine ?? (rand() < 0.8 ? 100 : Math.round(60 + rand() * 40));
  const body = opts.body ?? (rand() < 0.75 ? 100 : Math.round(55 + rand() * 45));
  const state = opts.state ?? 'garaged';
  const now = nowS();
  const person = personOf(owner);
  const mileage = opts.mileage ?? Math.round(800 + rand() * 24000);
  const boughtAt = now - Math.round((20 + rand() * 300) * DAY);

  const rec: MockVehicle = {
    row: {
      plate,
      model: m.model,
      hash: fakeHash(m.model),
      vehicleType: m.type,
      label: m.make ? `${m.make} ${m.name}` : m.name,
      make: m.make,
      image: m.model,
      ...labelExtras(m.model),
      garageKey: garage?.key ?? null,
      garageName: garage?.name ?? null,
      state,
      financed: !!opts.financed,
      fuel,
      engine,
      body,
      blocked: !!opts.blocked,
    },
    owner,
    ownerType: 'player',
    job: null,
    gang: null,
    nickname: opts.nickname ?? null,
    mileage,
    props: baseProps(plate, m.model, rand),
    impound: null,
    finance: null,
    ownership: [
      { identifier: owner, name: person?.name ?? owner, via: 'dealership', at: boughtAt, price: Math.round((40 + rand() * 900) * 1000) },
    ],
    service: [],
    damage: null,
    lastUsed: null,
  };

  // Boats / aircraft and a few old records were never stored with damage saving on.
  if (m.type === 'car' && rand() > 0.12) {
    const h = (pct: number) => Math.round(pct * 10);
    rec.damage = {
      engine: h(engine),
      body: h(body),
      tank: 1000,
      // Lua encodes empty tables as {} (or []): the UI must cope with both.
      doors: rand() < 0.5 ? {} : [],
      windows: body < 70 ? [Math.floor(rand() * 4)] : {},
      tyres: [],
      deformed: body < 90,
    };
  }
  rec.lastUsed =
    state === 'out'
      ? now - Math.round((5 + rand() * 170) * 60)
      : opts.mileage === 0
        ? null
        : now - Math.round((1 + rand() * 480) * 3600);

  if (opts.financed) {
    const total = 24 + Math.floor(rand() * 4) * 6;
    const left = Math.max(1, Math.round(total * (0.25 + rand() * 0.6)));
    const payment = Math.round((4 + rand() * 30)) * 1000;
    rec.finance = {
      balance: payment * left,
      payment,
      paymentsLeft: left,
      paymentsTotal: total,
      intervalHours: 24,
      nextPaymentHours: Math.round(rand() * 2300) / 100,
      overdue: false,
    };
  }

  if (state === 'impounded') {
    rec.impound = {
      locationId: 18,
      locationName: 'Davis Impound',
      reason: 'Abandoned on the freeway shoulder',
      fee: 750,
      by: 'KT90344',
      byName: 'Kenji Tanaka',
      at: now - Math.round(rand() * 20) * 3600,
      releaseAt: now + 6 * 3600,
      retrievable: true,
    };
    rec.row.garageKey = null;
    rec.row.garageName = null;
    rec.lastUsed = rec.impound.at - 3600;
  }

  const services = Math.floor(rand() * 4);
  for (let i = 0; i < services; i++) {
    rec.service.push({
      id: 1000 + vehicles.size * 10 + i,
      item: SERVICE_ITEMS[Math.floor(rand() * SERVICE_ITEMS.length)],
      shop: SHOPS[Math.floor(rand() * SHOPS.length)],
      mileage: Math.max(0, mileage - i * 420 - Math.round(rand() * 200)),
      at: now - (i * 9 + 2) * DAY,
    });
  }

  vehicles.set(plate, rec);
  return rec;
}

/* Jordan Vale — the showcase account (34 vehicles). */
function seedJordan() {
  const me = 'NZV41207';
  const showcase = addVehicle(me, 'elegy', {
    plate: 'NZ ELEGY',
    garage: GARAGES.car[2],
    financed: true,
    fuel: 81,
    engine: 100,
    body: 96,
    nickname: 'Midnight',
    mileage: 11048,
    seed: 42,
  });
  const p = showcase.props;
  Object.assign(p, {
    color1: [12, 14, 18],
    color2: 120,
    pearlescentColor: 70,
    interiorColor: 93,
    dashboardColor: 111,
    wheelColor: 156,
    wheels: 5,
    modFrontWheels: 14,
    modBackWheels: -1,
    modCustomTiresF: true,
    wheelWidth: 0.68,
    wheelSize: 0.72,
    modEngine: 3,
    modBrakes: 2,
    modTransmission: 2,
    modSuspension: 1,
    modArmor: -1,
    modTurbo: true,
    modSpoilers: 4,
    modFrontBumper: 2,
    modSideSkirt: 1,
    modExhaust: 3,
    modHood: 6,
    modRoof: 0,
    modSeats: 2,
    modSteeringWheel: 9,
    windowTint: 2,
    plateIndex: 1,
    modXenon: true,
    xenonColor: 1,
    neonEnabled: [true, true, false, true],
    neonColor: [8, 175, 162],
    modSmokeEnabled: true,
    tyreSmokeColor: [20, 20, 20],
    extras: { '1': true, '2': false, '5': true },
  });
  showcase.finance = {
    balance: 324000,
    payment: 18000,
    paymentsLeft: 18,
    paymentsTotal: 30,
    intervalHours: 24,
    nextPaymentHours: 9.6,
    overdue: false,
  };
  const now = nowS();
  showcase.ownership = [
    { identifier: me, name: 'Jordan Vale', via: 'sale', at: now - 41 * DAY, price: 465000 },
    { identifier: 'AB10077', name: 'Ava Brooks', via: 'transfer', at: now - 172 * DAY },
    { identifier: 'DV66012', name: 'Dmitri Volkov', via: 'sale', at: now - 260 * DAY, price: 510000 },
    { identifier: 'MC80412', name: 'Maya Chen', via: 'dealership', at: now - 388 * DAY, price: 540000 },
  ];
  showcase.service = [
    { id: 1, item: 'Engine oil', shop: 'Los Santos Customs', mileage: 10956, at: now - 3 * DAY },
    { id: 2, item: 'Spark plugs', shop: 'Los Santos Customs', mileage: 10951, at: now - 3 * DAY },
    { id: 3, item: 'Air filter', shop: "Benny's Original Motor Works", mileage: 9212, at: now - 26 * DAY },
    { id: 4, item: 'Brake pads', shop: "Benny's Original Motor Works", mileage: 9208, at: now - 26 * DAY },
    { id: 5, item: 'Tyres', shop: 'Hayes Autos', mileage: 6120, at: now - 74 * DAY },
    { id: 6, item: 'Suspension', shop: "Beeker's Garage", mileage: 2205, at: now - 160 * DAY },
  ];
  // One smashed window and a saved body deformation; empty lists the way Lua sends them.
  showcase.damage = { engine: 1000, body: 958, tank: 1000, doors: {}, windows: [3], tyres: {}, deformed: true };
  showcase.lastUsed = now - 5 * 3600 - 12 * 60;

  const list: [string, Parameters<typeof addVehicle>[2]][] = [
    ['sultanrs', { plate: 'VALE 01', financed: true }],
    ['zentorno', { state: 'out', fuel: 34 }],
    ['adder', { plate: 'GOLDRUSH', blocked: true }],
    ['comet2', {}],
    ['jester', { state: 'impounded', engine: 41, body: 22 }],
    ['banshee', { fuel: 18 }],
    ['buffalo', {}],
    ['dominator', { nickname: 'Daily' }],
    ['kuruma', { financed: true, state: 'out' }],
    ['schafter2', {}],
    ['baller', { engine: 47 }],
    ['granger', {}],
    ['sandking', { state: 'out', body: 38 }],
    ['bison', { fuel: 65 }],
    ['cypher', { financed: true }],
    ['euros', {}],
    ['zr350', { plate: 'CLUB 23' }],
    ['futo', { plate: 'DRIFT 86' }],
    ['issi2', {}],
    ['t20', {}],
    ['turismor', { plate: 'COAST 87' }],
    ['infernus', { state: 'out' }],
    ['feltzer2', {}],
    ['ninef', {}],
    ['rapidgt', {}],
    ['bati', { fuel: 22 }],
    ['sanchez', { body: 64 }],
    ['jetmax', {}],
    ['speeder', {}],
    ['dinghy', {}],
    ['luxor', { state: 'out', fuel: 65 }],
    ['frogger', {}],
    ['swift', { state: 'impounded' }],
  ];
  const made = new Map<string, MockVehicle>();
  list.forEach(([model, opts]) => made.set(model, addVehicle(me, model, opts)));

  // Wrecked and impounded.
  const jester = made.get('jester');
  if (jester) {
    jester.damage = {
      engine: 410,
      body: 220,
      tank: 640,
      doors: [0, 4],
      windows: [0, 1, 6],
      tyres: [
        { index: 1, state: 1 },
        { index: 4, state: 2 },
      ],
      deformed: true,
    };
    if (jester.impound) jester.impound.reason = 'Wrecked after a pursuit on Del Perro Freeway';
  }
  // Out in the world with body damage.
  const sandking = made.get('sandking');
  if (sandking) sandking.damage = { engine: 880, body: 380, tank: 1000, doors: [1, 3, 5], windows: {}, tyres: [{ index: 5, state: 1 }], deformed: true };
  // Engine below the service threshold.
  const baller = made.get('baller');
  if (baller) baller.damage = { engine: 470, body: 1000, tank: 1000, doors: [], windows: [], tyres: [], deformed: false };

  // An add-on model the client cannot identify: no class, no stats, no props yet.
  const proto = addVehicle(me, 'nzproto', { plate: 'PROTO 1', garage: GARAGES.car[0], mileage: 214, fuel: 92 });
  proto.row.label = 'nzproto';
  proto.row.make = '';
  proto.props = {};
  proto.damage = null;
}

function seedOthers() {
  const spread: [string, string[]][] = [
    ['QX55821', ['elegy2', 'futo', 'seashark', 'baller', 'issi2']],
    ['KT90344', ['kuruma', 'granger', 'buffalo', 'mammatus', 'comet2', 'bati']],
    ['AB10077', ['euros', 'zr350', 'panto']],
    ['PS44120', ['ninef', 'schafter2']],
    ['MR73315', ['dominator', 'sandking', 'bison', 'jester']],
    ['CM20981', ['rapidgt', 'feltzer2']],
    ['DV66012', ['infernus', 'speeder', 'turismor']],
    ['JV10233', ['sultan']],
    ['SR38410', ['t20', 'cypher']],
    ['MC80412', ['adder']],
    ['LM47723', ['banshee']],
    ['ZK33064', ['jetmax', 'euros']],
  ];
  spread.forEach(([owner, models], i) =>
    models.forEach((model, j) =>
      addVehicle(owner, model, { financed: (i + j) % 5 === 2, state: (i + j) % 7 === 3 ? 'out' : 'garaged' }),
    ),
  );
}

seedJordan();
seedOthers();

/* ───────────────────────── views ───────────────────────── */

function rowsOf(identifier: string): AdminVehicleRow[] {
  return [...vehicles.values()]
    .filter((v) => v.owner === identifier && v.ownerType === 'player')
    .map((v) => ({ ...clone(v.row), financed: !!v.finance }))
    .sort((a, b) => a.plate.localeCompare(b.plate));
}

function ownerName(v: MockVehicle): string {
  if (v.ownerType === 'job') return adminMockDb.jobs.find((j) => j.name === v.job)?.label ?? v.job ?? '';
  if (v.ownerType === 'gang') return adminMockDb.gangs.find((g) => g.name === v.gang)?.label ?? v.gang ?? '';
  return personOf(v.owner)?.name ?? v.owner ?? '';
}

function garageChoices(): { key: string; name: string }[] {
  const list = adminMockDb.locations
    .filter((l) => l.kind !== 'impound' && l.id !== null)
    .map((l) => ({ key: `L${l.id}`, name: l.name }));
  return list;
}

function detailOf(v: MockVehicle): AdminVehicleDetail {
  return clone({
    vehicle: {
      ...v.row,
      financed: !!v.finance,
      owner: v.owner,
      ownerName: ownerName(v),
      ownerType: v.ownerType,
      job: v.job,
      gang: v.gang,
      nickname: v.nickname,
      mileage: v.mileage,
      props: v.props,
    },
    impound: v.impound,
    finance: v.finance,
    ownership: v.ownership,
    service: [...v.service].sort((a, b) => b.at - a.at),
    garages: garageChoices(),
    impounds: adminMockDb.locations.filter((l) => l.kind === 'impound').map((l) => ({ id: l.id as number, name: l.name })),
    damage: v.damage as DamageSummary | null,
    lastUsed: v.lastUsed,
  });
}

/** false and {} mean "clear" (server/admin.lua isClear); null never arrives (see stripNulls). */
const isClear = (v: unknown) => v === false || (typeof v === 'object' && v !== null && Object.keys(v as object).length === 0);

/* ───────────────────────── activity (nz_logs) ───────────────────────── */

const ACTIVITY_PAGE = 25;
const STAFF = { identifier: 'MR73315', name: 'Marcus Reid' };
const activity = new Map<string, VehicleActivity[]>();
let activitySeq = 90000;

type Draft = Omit<VehicleActivity, 'id'>;

/** Player action (actorName enrichment like NZ.Logs.add). */
function byPlayer(event: string, at: number, who: { identifier: string | null; name: string }, data: Record<string, unknown>): Draft {
  return { event, at, actor: who.identifier, actorName: who.name, data: { ...data, actorName: who.name } };
}

/** Server / export action (no actor). */
function byServer(event: string, at: number, data: Record<string, unknown>): Draft {
  return { event, at, actor: null, actorName: null, data };
}

const GARAGE_NAMES: Record<string, string> = Object.fromEntries(Object.values(GARAGES).flat().map((g) => [g.key, g.name]));

/** Retrieve / store pairs at a garage, `count` trips ending `endAt`. */
function trips(plate: string, who: { identifier: string; name: string }, key: string, endAt: number, count: number, rand: () => number, mileage: number): Draft[] {
  const out: Draft[] = [];
  let t = endAt;
  let km = mileage;
  for (let i = 0; i < count; i++) {
    const stored = t;
    const taken = stored - Math.round((0.4 + rand() * 3) * 3600);
    out.push(byPlayer('vehicle.store', stored, who, { plate, garage: key, garageName: GARAGE_NAMES[key] ?? key, owner: who.identifier, mileage: Math.round(km), fuel: Math.round(40 + rand() * 60) }));
    out.push(byPlayer('vehicle.retrieve', taken, who, { plate, garage: key, fee: 0, fromImpound: false, fromInterior: false, serverSpawn: true }));
    km -= 20 + rand() * 90;
    t = taken - Math.round((6 + rand() * 60) * 3600);
  }
  return out;
}

function showcaseActivity(v: MockVehicle): Draft[] {
  const plate = v.row.plate;
  const now = nowS();
  const H = 3600;
  const me = { identifier: 'NZV41207', name: 'Jordan Vale' };
  const ava = { identifier: 'AB10077', name: 'Ava Brooks' };
  const dmitri = { identifier: 'DV66012', name: 'Dmitri Volkov' };
  const maya = { identifier: 'MC80412', name: 'Maya Chen' };
  const kenji = { identifier: 'KT90344', name: 'Kenji Tanaka' };
  const rand = rng(7);
  const list: Draft[] = [
    byPlayer('vehicle.store', now - 5 * H + 1400, me, { plate, garage: 'L3', garageName: 'Mirror Park', owner: me.identifier, mileage: 11048, fuel: 81, engine: 100, body: 96, trailer: false }),
    byPlayer('vehicle.retrieve', now - 5 * H - 12 * 60, me, { plate, garage: 'L3', fee: 0, fromImpound: false, fromInterior: true, serverSpawn: true }),
    byPlayer('racing.lapRecord', now - 26 * H, me, { plate, track: 'Vinewood Bowl', lap: '1:12.48', position: 1, entrants: 9 }),
    byPlayer('vehicle.favourite', now - 27 * H, me, { plate, value: true }),
    byServer('vehicle.service', now - 3 * DAY, { plate, item: 'Spark plugs', shop: 'Los Santos Customs', mileage: 10951 }),
    byServer('vehicle.service', now - 3 * DAY - 600, { plate, item: 'Engine oil', shop: 'Los Santos Customs', mileage: 10956 }),
    byPlayer('vehicle.finance', now - 4 * DAY, me, { plate, amount: 18000, paidOff: false, balance: 324000 }),
    byPlayer('vehicle.share', now - 6 * DAY, me, { plate, action: 'add', target: 'QX55821', targetName: 'Lena Ortiz' }),
    byPlayer('vehicle.recover', now - 8 * DAY, me, { plate, garage: 'L3', garageName: 'Mirror Park', fee: 250, owner: me.identifier, removedEntity: true }),
    byPlayer('admin.vehicle.update', now - 12 * DAY, STAFF, { plate, changed: ['finance', 'details'], removedEntity: false }),
    byPlayer('vehicle.transfer', now - 14 * DAY, me, { plate, type: 'garage', from: 'L1', to: 'L3', toName: 'Mirror Park', fee: 250 }),
    byPlayer('impound.retrieve', now - 19 * DAY, me, { plate, owner: me.identifier, impound: 18, impoundName: 'Davis Impound', fee: 500, staff: false, impoundedBy: 'Kenji Tanaka', reason: 'Parked in a red zone' }),
    byPlayer('impound.add', now - 20 * DAY, kenji, { plate, owner: me.identifier, previousState: 'out', impound: 18, impoundName: 'Davis Impound', reason: 'Parked in a red zone', fee: 500, hours: 2, retrievable: true, by: kenji.identifier, byName: kenji.name, removedEntity: true }),
    byPlayer('vehicle.finance', now - 24 * DAY, me, { plate, amount: 18000, paidOff: false, balance: 342000 }),
    byPlayer('impound.release', now - 30 * DAY + 2 * H, STAFF, { plate, mode: 'garage', owner: me.identifier, impound: 18, impoundName: 'Davis Impound', garage: 'L1', garageName: 'Legion Square', previousGarage: 'L3' }),
    byServer('impound.add', now - 30 * DAY, { plate, npc: true, impound: 18, impoundName: 'Davis Impound', reason: 'Abandoned vehicle', by: null, byName: 'Tow service' }),
    byPlayer('vehicle.rename', now - 40 * DAY, me, { plate, from: null, to: 'Midnight' }),
    byPlayer('vehicle.sell', now - 41 * DAY, me, { plate, action: 'sold', price: 465000, seller: ava.identifier, sellerName: ava.name, buyer: me.identifier, buyerName: me.name }),
    byPlayer('vehicle.sell', now - 41 * DAY - 900, ava, { plate, action: 'offer', price: 465000, buyer: me.identifier, buyerName: me.name }),
    byPlayer('vehicle.transfer', now - 172 * DAY, dmitri, { plate, type: 'player', fee: 2500, from: dmitri.identifier, fromName: dmitri.name, to: ava.identifier, toName: ava.name }),
    byPlayer('vehicle.sell', now - 260 * DAY, dmitri, { plate, action: 'sold', price: 510000, seller: maya.identifier, sellerName: maya.name, buyer: dmitri.identifier, buyerName: dmitri.name }),
    byPlayer('vehicle.sell', now - 262 * DAY, maya, { plate, action: 'declined', price: 560000, seller: maya.identifier, buyer: 'SR38410' }),
    byServer('vehicle.add', now - 388 * DAY, { plate, owner: maya.identifier, ownerName: maya.name, model: 'elegy', garageKey: 'L3', vehicleType: 'car' }),
  ];
  // Everyday garage use between the notable events.
  list.push(...trips(plate, me, 'L3', now - 2 * DAY, 6, rand, 10900));
  list.push(...trips(plate, me, 'L1', now - 15 * DAY, 4, rand, 9600));
  list.push(...trips(plate, ava, 'L2', now - 60 * DAY, 3, rand, 6200));
  return list;
}

function generatedActivity(v: MockVehicle): Draft[] {
  const plate = v.row.plate;
  const rand = rng(fakeHash(plate) >>> 0);
  const owner = personOf(v.owner) ?? { identifier: v.owner ?? 'unknown', name: v.owner ?? 'Unknown', online: false };
  const who = { identifier: owner.identifier, name: owner.name };
  const key = v.row.garageKey ?? GARAGES[v.row.vehicleType][0].key;
  const now = nowS();
  const list: Draft[] = [];
  const bought = v.ownership[v.ownership.length - 1]?.at ?? now - 90 * DAY;
  list.push(byServer('vehicle.add', bought, { plate, owner: who.identifier, ownerName: who.name, model: v.row.model, garageKey: key, vehicleType: v.row.vehicleType }));
  const end = v.lastUsed ?? now - 3 * DAY;
  const n = 2 + Math.floor(rand() * 7);
  list.push(...trips(plate, who, key, v.row.state === 'out' ? end - 2 * DAY : end + 2 * 3600, n, rand, v.mileage));
  if (v.row.state === 'out' && v.lastUsed) {
    list.push(byPlayer('vehicle.retrieve', v.lastUsed, who, { plate, garage: key, fee: 0, fromImpound: false, fromInterior: false, serverSpawn: true }));
  }
  for (const sv of v.service) list.push(byServer('vehicle.service', sv.at, { plate, item: sv.item, shop: sv.shop, mileage: sv.mileage }));
  if (rand() < 0.35) list.push(byPlayer('vehicle.share', end - Math.round(rand() * 20) * DAY, who, { plate, action: 'add', target: 'SR38410', targetName: 'Sofia Romero' }));
  if (rand() < 0.3) list.push(byPlayer('fuel.refill', end - Math.round(rand() * 9) * DAY - 3600, who, { plate, station: 'Ron Alternates, Grove Street', litres: Math.round(20 + rand() * 40) }));
  if (v.finance) list.push(byPlayer('vehicle.finance', end - DAY, who, { plate, amount: v.finance.payment, paidOff: false, balance: v.finance.balance }));
  if (v.impound) {
    list.push(
      byPlayer('impound.add', v.impound.at, { identifier: v.impound.by, name: v.impound.byName }, {
        plate, owner: who.identifier, previousState: 'out', impound: v.impound.locationId, impoundName: v.impound.locationName,
        reason: v.impound.reason, fee: v.impound.fee, hours: 6, retrievable: v.impound.retrievable, by: v.impound.by, byName: v.impound.byName, removedEntity: true,
      }),
    );
  }
  if (v.row.blocked) list.push(byPlayer('admin.vehicle.update', now - 2 * DAY, STAFF, { plate, changed: ['blocked'] }));
  if (rand() < 0.15) list.push(byPlayer('security.dupe', end - 4 * DAY, who, { plate, reason: 'retrieve while an occupied copy exists' }));
  return list;
}

/** Newest first, ids assigned once. */
function activityOf(v: MockVehicle): VehicleActivity[] {
  let list = activity.get(v.row.plate);
  if (!list) {
    const drafts = v.row.plate === 'NZ ELEGY' ? showcaseActivity(v) : v.row.model === 'nzproto' ? [] : generatedActivity(v);
    list = drafts.sort((a, b) => b.at - a.at).map((d) => ({ ...d, id: ++activitySeq }));
    activity.set(v.row.plate, list);
  }
  return list;
}

function logActivity(plate: string, event: string, data: Record<string, unknown>) {
  const v = vehicles.get(plate);
  if (!v) return;
  const list = activityOf(v);
  list.unshift({ id: ++activitySeq, event, at: nowS(), actor: 'NZV41207', actorName: 'Admin (you)', data: { plate, ...data, actorName: 'Admin (you)' } });
}

/* ───────────────────────── handlers: players & vehicles ───────────────────────── */

const PAGE_SIZE = 10;

mockNui('admin:players:search', async ({ query, page }) => {
  await wait(420);
  const q = (query ?? '').trim().toLowerCase();
  const plateQ = q.toUpperCase();
  const platesOf = new Map<string, string[]>();
  if (plateQ.length >= 2) {
    for (const v of vehicles.values()) {
      if (v.owner && v.row.plate.includes(plateQ)) {
        platesOf.set(v.owner, [...(platesOf.get(v.owner) ?? []), v.row.plate]);
      }
    }
  }
  const byPlate = PEOPLE.filter((p) => platesOf.has(p.identifier));
  const byName = PEOPLE.filter(
    (p) => !platesOf.has(p.identifier) && (!q || p.name.toLowerCase().includes(q) || p.identifier.toLowerCase().includes(q)),
  );
  const all = [...byPlate, ...byName];
  const pageN = Math.max(1, page || 1);
  const rows: PlayerSearchRow[] = all.slice((pageN - 1) * PAGE_SIZE, pageN * PAGE_SIZE).map((p) => ({
    identifier: p.identifier,
    name: p.name,
    online: p.online,
    matchedPlates: platesOf.get(p.identifier) ?? [],
  }));
  return { rows, total: all.length, page: pageN, pageSize: PAGE_SIZE };
});

mockNui('admin:players:vehicles', async ({ identifier }) => {
  await wait(380);
  const p = personOf(identifier);
  if (!p) return fail('Character not found');
  return { player: { ...p }, vehicles: rowsOf(identifier) };
});

mockNui('admin:vehicle:get', async ({ plate }) => {
  await wait(360);
  const v = vehicles.get(plate);
  if (!v) return fail('Vehicle not found');
  return detailOf(v);
});

mockNui('admin:vehicle:activity', async ({ plate, page }) => {
  await wait(300);
  const v = vehicles.get(plate);
  if (!v) return fail('Vehicle not found');
  const list = activityOf(v);
  const p = Math.max(1, Math.floor(page || 1));
  const rows = list.slice((p - 1) * ACTIVITY_PAGE, p * ACTIVITY_PAGE);
  // Lua encodes an empty rows table as {}.
  return { rows: (rows.length ? clone(rows) : {}) as VehicleActivity[], total: list.length, page: p, pageSize: ACTIVITY_PAGE };
});

mockNui('admin:vehicle:assign', async ({ identifier, model, plate, garageKey }) => {
  await wait(520);
  const m = (model ?? '').trim().toLowerCase();
  if (!/^[a-z0-9_]{2,32}$/.test(m)) return fail('Enter a valid model name (letters, digits and underscores)');
  if (!personOf(identifier)) return fail('Character not found');
  const garage = garageChoices().find((g) => g.key === garageKey);
  if (!garage) return fail('Select a garage');
  const wanted = (plate ?? '').trim().toUpperCase();
  if (wanted && !/^[A-Z0-9 ]{1,8}$/.test(wanted)) return fail('Plates have 1 to 8 letters, digits or spaces');
  if (wanted && vehicles.has(wanted)) return fail('This plate is already in use');
  const loc = adminMockDb.locations.find((l) => `L${l.id}` === garageKey);
  const rec = addVehicle(identifier, m, {
    plate: wanted || undefined,
    garage,
    fuel: 100,
    engine: 100,
    body: 100,
    mileage: 0,
    seed: Date.now() % 100000,
  });
  rec.row.vehicleType = loc?.vehicleType ?? rec.row.vehicleType;
  rec.service = [];
  rec.ownership = [{ identifier, name: personOf(identifier)?.name ?? identifier, via: 'admin', at: nowS() }];
  activity.set(rec.row.plate, []);
  logActivity(rec.row.plate, 'admin.vehicle.assign', { model: m, identifier, garage: garage.key });
  return clone(rec.row);
});

/** JSON null decodes to nil in Lua (= key absent): drop nulls like the real bridge does. */
function stripNulls<T>(v: T): T {
  if (Array.isArray(v)) return v.map(stripNulls) as unknown as T;
  if (v && typeof v === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, x] of Object.entries(v)) if (x !== null) out[k] = stripNulls(x);
    return out as T;
  }
  return v;
}

mockNui('admin:vehicle:update', async ({ plate, patch: raw }) => {
  await wait(460);
  const patch = stripNulls(raw);
  const v = vehicles.get(plate);
  if (!v) return fail('Vehicle not found');
  const next = clone(v);

  if (patch.plate !== undefined) {
    const p = String(patch.plate).trim().toUpperCase();
    if (!/^[A-Z0-9 ]{1,8}$/.test(p)) return fail('Plates have 1 to 8 letters, digits or spaces');
    if (p !== plate) {
      if (v.row.state === 'out') return fail('Store the vehicle before changing its plate');
      if (vehicles.has(p)) return fail('This plate is already in use');
      next.row.plate = p;
      next.props.plate = p;
    }
  }

  const d = patch.details;
  if (d) {
    if (d.garageKey !== undefined) {
      const g = garageChoices().find((x) => x.key === d.garageKey);
      if (d.garageKey && !g) return fail('Garage not found');
      next.row.garageKey = g?.key ?? null;
      next.row.garageName = g?.name ?? null;
    }
    if (d.state !== undefined) {
      if (d.state === 'impounded' && !next.impound && !patch.impound) return fail('Choose the impound for this vehicle');
      next.row.state = d.state;
    }
    if (d.nickname !== undefined) next.nickname = d.nickname ? String(d.nickname).slice(0, 32) : null;
    if (d.mileage !== undefined) next.mileage = Math.round(Math.max(0, d.mileage) * 100) / 100;
    for (const k of ['fuel', 'engine', 'body'] as const) {
      const val = d[k];
      if (val !== undefined) {
        if (val < 0 || val > 100) return fail('Fuel, engine and body must be between 0 and 100');
        next.row[k] = Math.round(val * 10) / 10;
      }
    }
  }

  if (patch.owner) {
    const o = patch.owner;
    if (o.type === 'player') {
      const p = personOf(o.identifier ?? '');
      if (!p) return fail('Character not found');
      if (p.identifier !== v.owner || v.ownerType !== 'player') {
        next.ownership.unshift({ identifier: p.identifier, name: p.name, via: 'admin', at: nowS() });
      }
      next.owner = p.identifier;
      next.ownerType = 'player';
      next.job = null;
      next.gang = null;
    } else {
      const name = o.type === 'gang' ? o.gang : o.job;
      const list = o.type === 'gang' ? adminMockDb.gangs : adminMockDb.jobs;
      const info = list.find((j) => j.name === name);
      if (!info) return fail(o.type === 'gang' ? 'Select a gang' : 'Select a job');
      next.ownerType = o.type;
      next.job = o.type === 'job' ? info.name : null;
      next.gang = o.type === 'gang' ? info.name : null;
      next.ownership.unshift({ identifier: v.owner, name: info.label, via: 'admin', at: nowS() });
    }
  }

  if (patch.props !== undefined) {
    if (!patch.props || typeof patch.props !== 'object' || Array.isArray(patch.props)) {
      return fail('Vehicle properties must be an object');
    }
    next.props = { ...clone(patch.props), plate: next.row.plate, model: v.row.hash };
  }

  if (patch.impound !== undefined) {
    const imp = patch.impound;
    if (imp === false || isClear(imp)) {
      next.impound = null;
      if (next.row.state === 'impounded') {
        next.row.state = 'garaged';
        if (!next.row.garageKey) {
          const g = GARAGES[next.row.vehicleType][0];
          next.row.garageKey = g.key;
          next.row.garageName = g.name;
        }
      }
    } else {
      const loc = adminMockDb.locations.find((l) => l.id === imp.locationId && l.kind === 'impound');
      if (!loc) return fail('Select an impound');
      const now = nowS();
      next.impound = {
        locationId: loc.id as number,
        locationName: loc.name,
        reason: imp.reason ?? next.impound?.reason ?? '',
        fee: Math.max(0, Math.round(imp.fee ?? 0)),
        by: 'NZV41207',
        byName: 'Admin (you)',
        at: now,
        releaseAt: Math.max(now, imp.releaseAt ?? now),
        retrievable: imp.retrievable !== false,
      };
      next.row.state = 'impounded';
    }
  }

  if (patch.finance !== undefined) {
    if (patch.finance === false || isClear(patch.finance) || patch.finance.balance <= 0) next.finance = null;
    else next.finance = clone(patch.finance);
  }
  next.row.financed = !!next.finance;

  if (patch.blocked !== undefined) next.row.blocked = !!patch.blocked;

  if (patch.service !== undefined) {
    next.service = patch.service
      .filter((s) => s.item && s.item.trim())
      .map((s, i) => ({ ...s, id: s.id ?? 5000 + i, item: s.item.trim().slice(0, 64), shop: (s.shop ?? '').slice(0, 64) }));
  }

  const changed = ['plate', 'details', 'owner', 'props', 'impound', 'finance', 'blocked', 'service'].filter((k) =>
    k === 'plate' ? next.row.plate !== plate : (patch as Record<string, unknown>)[k] !== undefined,
  );
  const history = activityOf(v);
  vehicles.delete(plate);
  vehicles.set(next.row.plate, next);
  if (next.row.plate !== plate) {
    activity.delete(plate);
    activity.set(next.row.plate, history);
  }
  if (patch.impound === false || isClear(patch.impound)) {
    if (v.impound) logActivity(next.row.plate, 'impound.release', { mode: 'garage', impound: v.impound.locationId, impoundName: v.impound.locationName, garage: next.row.garageKey, garageName: next.row.garageName });
  } else if (patch.impound && next.impound && !v.impound) {
    logActivity(next.row.plate, 'impound.add', { impound: next.impound.locationId, impoundName: next.impound.locationName, reason: next.impound.reason, fee: next.impound.fee, by: 'NZV41207', byName: 'Admin (you)' });
  }
  logActivity(next.row.plate, 'admin.vehicle.update', { newPlate: next.row.plate !== plate ? next.row.plate : undefined, changed });
  return detailOf(next);
});

mockNui('admin:vehicle:delete', async ({ plate }) => {
  await wait(420);
  if (!vehicles.delete(plate)) return fail('Vehicle not found');
  return null;
});

/* ───────────────────────── handlers: interiors ───────────────────────── */

mockNui('admin:interior:create', async ({ name, profile, coords }) => {
  await wait(300);
  if (!name || !name.trim()) return fail('Enter a name');
  const prof = profile ? adminMockDb.profiles.find((p) => p.key === profile) : null;
  if (profile && !prof) return fail('Unknown interior profile');
  const entry = prof?.coords ?? (coords ? { ...coords, w: 0 } : { x: 215.8, y: -810.1, z: 30.7, w: 157.5 });
  const interior: Interior = {
    id: null,
    name: name.trim(),
    enabled: true,
    profile: prof?.key ?? null,
    options: Object.fromEntries((prof?.options ?? []).map((o) => [o.key, o.default])),
    entry,
    gtaInteriorId: null,
    cutscene: { enabled: false, transition: 3000, returnTime: 1000, points: [] },
    slots: [],
    exit: null,
  };
  // Lua closes the admin panel and starts the in-world creator.
  emitNuiMessage({ action: 'close', data: { app: 'admin' } });
  emitNuiMessage({
    action: 'open',
    data: { app: 'creator', data: { mode: 'create', interior, profiles: clone(adminMockDb.profiles), gtaInteriorName: null } },
  });
  return null;
});

mockNui('admin:interior:edit', async ({ id }) => {
  await wait(260);
  const interior = adminMockDb.interiors.find((i) => i.id === id);
  if (!interior) return fail('Interior not found');
  emitNuiMessage({ action: 'close', data: { app: 'admin' } });
  emitNuiMessage({
    action: 'open',
    data: {
      app: 'creator',
      data: { mode: 'edit', interior: clone(interior), profiles: clone(adminMockDb.profiles), gtaInteriorName: 'int_garage_mod' },
    },
  });
  return null;
});

mockNui('admin:interior:toggle', async ({ id, enabled }) => {
  await wait(320);
  const interior = adminMockDb.interiors.find((i) => i.id === id);
  if (!interior) return fail('Interior not found');
  interior.enabled = enabled;
  return null;
});

mockNui('admin:interior:delete', async ({ id }) => {
  await wait(420);
  const before = adminMockDb.interiors.length;
  adminMockDb.interiors = adminMockDb.interiors.filter((i) => i.id !== id);
  if (adminMockDb.interiors.length === before) return fail('Interior not found');
  adminMockDb.locations.forEach((l) => {
    if ('access' in l && l.access.interiorId === id) l.access = { mode: 'quick', interiorId: null };
  });
  return null;
});

mockNui('admin:pickPosition', async () => {
  await wait(220);
  const j = () => Math.round((Math.random() - 0.5) * 400) / 100;
  return { x: Math.round((215.82 + j()) * 100) / 100, y: Math.round((-810.06 + j()) * 100) / 100, z: 30.73, w: 157.5 };
});

/* ───────────────────────── handlers: settings ───────────────────────── */

mockNui('admin:settings:save', async ({ settings }) => {
  await wait(560);
  const s = stripNulls(clone(settings)) as Settings;
  if (s.garages.restartImpound === undefined) s.garages.restartImpound = null;
  if (!s.interface.currency.trim()) return fail('Enter a currency symbol');
  if (s.interface.showImages && !s.interface.imageUrl.includes('{model}')) return fail('The image URL must contain {model}');
  if (s.garages.outOnRestart === 'impound' && !s.garages.restartImpound) return fail('Choose the impound used at restart');
  if (!s.vehicles.saveDamage) s.vehicles.saveDeformation = false;
  adminMockDb.settings = s;
  // Lua pushes the interface part to every open NUI (accent, units, images…).
  emitNuiMessage({ action: 'settings', data: clone(s.interface) });
  return clone(s);
});

/* ───────────────────────── self-check ───────────────────────── */

// Every Settings field must have a row on the Settings page.
{
  const ids = new Set(ALL_ROW_IDS);
  const missing = Object.entries(adminMockDb.settings).flatMap(([section, values]) =>
    Object.keys(values as object)
      .map((k) => `${section}.${k}`)
      .filter((id) => !ids.has(id)),
  );
  if (missing.length) console.warn('[mocks] Settings fields without a row on the Settings page:', missing.join(', '));
}

/* ───────────────────────── scenarios ───────────────────────── */

function open(page: AdminPage, extra: Partial<AdminOpenData> & { __adminB?: AdminBDevHint } = {}) {
  return {
    action: 'open' as const,
    data: { app: 'admin' as const, data: { ...clone(adminMockDb), page, ...extra } },
  };
}

const G = 'Admin · vehicles, interiors, settings';

/** IPL profiles + two without quick-teleport coordinates (hidden in the create modal). */
const profilesWithHidden = () => [
  ...clone(adminMockDb.profiles),
  { key: 'arcade_basement', label: 'Arcade basement', coords: null, slots: 4, options: [] },
  { key: 'facility_hangar', label: 'Facility hangar', coords: null, slots: 8, options: [] },
];

registerMock({ id: 'admin-interiors', group: G, label: 'Interiors table', messages: [open('interiors', { profiles: profilesWithHidden() })] });
registerMock({
  id: 'admin-interiors-create',
  group: G,
  label: 'Interiors — create modal',
  messages: [open('interiors', { profiles: profilesWithHidden(), __adminB: { create: true } })],
});
registerMock({
  id: 'admin-interiors-empty',
  group: G,
  label: 'Interiors — none yet',
  messages: [open('interiors', { interiors: [] })],
});
registerMock({ id: 'admin-vehicles', group: G, label: 'Player vehicles — search', messages: [open('vehicles')] });
registerMock({
  id: 'admin-vehicles-results',
  group: G,
  label: 'Player vehicles — results ("jor")',
  messages: [open('vehicles', { __adminB: { search: 'jor' } })],
});
registerMock({
  id: 'admin-vehicles-player',
  group: G,
  label: 'Player vehicles — Jordan Vale (34)',
  messages: [open('vehicles', { __adminB: { search: 'jor', player: 'NZV41207' } })],
});
registerMock({
  id: 'admin-vehicles-detail',
  group: G,
  label: 'Vehicle dossier — overview',
  messages: [open('vehicles', { __adminB: { search: 'jor', player: 'NZV41207', plate: 'NZ ELEGY' } })],
});
(
  [
    ['condition', 'condition'],
    ['upgrades', 'upgrades & paint'],
    ['finance', 'finance'],
    ['history', 'history'],
    ['activity', 'activity log'],
    ['data', 'props JSON'],
  ] as const
).forEach(([tab, label]) =>
  registerMock({
    id: `admin-vehicles-${tab}`,
    group: G,
    label: `Vehicle dossier — ${label}`,
    messages: [open('vehicles', { __adminB: { player: 'NZV41207', plate: 'NZ ELEGY', dossierTab: tab } })],
  }),
);
registerMock({
  id: 'admin-vehicles-damaged',
  group: G,
  label: 'Vehicle dossier — wrecked (condition)',
  messages: [open('vehicles', { __adminB: { player: 'NZV41207', plate: [...vehicles.values()].find((v) => v.owner === 'NZV41207' && v.row.model === 'jester')?.row.plate, dossierTab: 'condition' } })],
});
registerMock({
  id: 'admin-vehicles-nostats',
  group: G,
  label: 'Vehicle dossier — add-on model (no stats, no props)',
  messages: [open('vehicles', { __adminB: { player: 'NZV41207', plate: 'PROTO 1' } })],
});
registerMock({
  id: 'admin-vehicles-impounded',
  group: G,
  label: 'Vehicle detail — impounded',
  messages: [open('vehicles', { __adminB: { player: 'NZV41207', plate: [...vehicles.values()].find((v) => v.owner === 'NZV41207' && v.row.model === 'jester')?.row.plate } })],
});
registerMock({
  id: 'admin-vehicles-props',
  group: G,
  label: 'Vehicle detail — props editor',
  messages: [open('vehicles', { __adminB: { player: 'NZV41207', plate: 'NZ ELEGY', props: true } })],
});
registerMock({ id: 'admin-settings', group: G, label: 'Settings', messages: [open('settings')] });
registerMock({
  id: 'admin-settings-interface',
  group: G,
  label: 'Settings — interface tab',
  messages: [open('settings', { __adminB: { tab: 'interface' } })],
});
