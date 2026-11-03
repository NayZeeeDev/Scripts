/**
 * Admin B mocks (browser dev only): player vehicles, interiors and settings pages.
 *
 * Data: 22 characters, 60+ owned vehicles (34 for Jordan Vale) with props, finance, impound,
 * ownership and service history. Interiors / settings read and write `adminMockDb` from
 * ./admin so admin:refresh stays consistent.
 *
 * Scenarios: admin-interiors, admin-interiors-create, admin-interiors-empty, admin-vehicles,
 * admin-vehicles-results, admin-vehicles-player, admin-vehicles-detail,
 * admin-vehicles-impounded, admin-vehicles-props, admin-settings, admin-settings-interface.
 *
 * mockNui: admin:players:search, admin:players:vehicles, admin:vehicle:get|assign|update|delete,
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
  Finance,
  ImpoundInfo,
  Interior,
  OwnershipEntry,
  PlayerSearchRow,
  ServiceEntry,
  Settings,
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
  };

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
  list.forEach(([model, opts]) => addVehicle(me, model, opts));
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
  });
}

/** false and {} mean "clear" (server/admin.lua isClear); null never arrives (see stripNulls). */
const isClear = (v: unknown) => v === false || (typeof v === 'object' && v !== null && Object.keys(v as object).length === 0);

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

  vehicles.delete(plate);
  vehicles.set(next.row.plate, next);
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
  label: 'Vehicle detail (finance, mods, history)',
  messages: [open('vehicles', { __adminB: { search: 'jor', player: 'NZV41207', plate: 'NZ ELEGY' } })],
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
