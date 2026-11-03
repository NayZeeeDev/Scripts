/**
 * Admin panel mocks (browser dev only).
 *
 * Exports
 * - `adminMockData`  pristine AdminOpenData (19 locations, 4 interiors, IPL profiles, jobs, gangs,
 *                    settings = config/config.lua defaults). Never mutated — import it freely.
 * - `adminMockDb`    the mutable copy every admin mock handler reads and writes. Other admin mock
 *                    files may patch it (e.g. after admin:settings:save) so admin:refresh reflects it.
 * - `adminMockGroups` private-garage groups (GroupInfo) by location id, mutable.
 *
 * Scenarios: admin-garages, admin-jobs, admin-private, admin-impounds, admin-edit-location,
 * admin-edit-job, admin-edit-private, admin-private-owners, admin-create-impound, admin-empty.
 * admin:points answers after ~1.5 s (the admin UI is hidden meanwhile) and appends one point
 * next to the last one; the in-world key hint is shown while it "runs".
 * mockNui: admin:refresh, admin:location:save|delete|toggle|teleport|import, admin:points,
 * admin:pickPosition, admin:groups, admin:group:save|delete|member.
 */
import { registerMock } from '../registry';
import { emitNuiMessage, mockNui } from '../../lib/nui';
import type {
  AccessConfig,
  AdminOpenData,
  AdminPage,
  BlipConfig,
  CapacityConfig,
  GarageLocation,
  GroupInfo,
  ImpoundLocation,
  InteractionPoint,
  Interior,
  IplProfile,
  JobInfo,
  JobLocation,
  Location,
  PrivateLocation,
  Settings,
  SpawnerVehicle,
  Vec3,
  Vec4,
  VehicleType,
} from '../../lib/types';

/* ───────────────────────── helpers ───────────────────────── */

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
const clone = <T,>(v: T): T => JSON.parse(JSON.stringify(v)) as T;
const nowS = () => Math.floor(Date.now() / 1000);
const DAY = 86400;
const r2 = (n: number) => Math.round(n * 100) / 100;

const v3 = (x: number, y: number, z: number): Vec3 => ({ x, y, z });
const v4 = (x: number, y: number, z: number, w: number): Vec4 => ({ x, y, z, w });
const pt = (x: number, y: number, z: number, radius = 2): InteractionPoint => ({ coords: v3(x, y, z), radius });

const SPRITE: Record<VehicleType, number> = { car: 357, sea: 356, air: 359 };
const COLOUR = { garage: 3, job: 38, private: 5, impound: 1 } as const;

const blip = (kind: keyof typeof COLOUR, vt: VehicleType, enabled = true): BlipConfig => ({
  enabled,
  sprite: kind === 'impound' ? 68 : SPRITE[vt],
  color: COLOUR[kind],
  scale: 0.7,
});

const unlimited = (): CapacityConfig => ({ mode: 'unlimited', appliesTo: 'player', spaces: 8 });
const limited = (spaces: number, appliesTo: 'player' | 'total' = 'player'): CapacityConfig => ({ mode: 'limited', appliesTo, spaces });
const quick = (): AccessConfig => ({ mode: 'quick', interiorId: null });

/** A row of spawn points next to each other along a heading. */
function spawnRow(x: number, y: number, z: number, w: number, count: number, gap = 3.4): Vec4[] {
  const a = ((w + 90) * Math.PI) / 180;
  return Array.from({ length: count }, (_, i) => v4(r2(x + Math.cos(a) * gap * i), r2(y + Math.sin(a) * gap * i), z, w));
}

const veh = (model: string, over: Partial<SpawnerVehicle> = {}): SpawnerVehicle => ({
  model,
  label: '',
  plate: '',
  grades: [],
  livery: -1,
  extras: {},
  maxMods: false,
  price: 0,
  ...over,
});

/* ───────────────────────── reference data ───────────────────────── */

export const mockJobs: JobInfo[] = [
  {
    name: 'police',
    label: 'LSPD',
    grades: [
      { grade: 0, label: 'Recruit' },
      { grade: 1, label: 'Officer' },
      { grade: 2, label: 'Sergeant' },
      { grade: 3, label: 'Lieutenant' },
      { grade: 4, label: 'Chief' },
    ],
  },
  {
    name: 'ambulance',
    label: 'EMS',
    grades: [
      { grade: 0, label: 'EMT' },
      { grade: 1, label: 'Paramedic' },
      { grade: 2, label: 'Doctor' },
      { grade: 3, label: 'Surgeon' },
      { grade: 4, label: 'Chief of Medicine' },
    ],
  },
  {
    name: 'mechanic',
    label: 'Mechanic',
    grades: [
      { grade: 0, label: 'Recruit' },
      { grade: 1, label: 'Novice' },
      { grade: 2, label: 'Experienced' },
      { grade: 3, label: 'Advanced' },
      { grade: 4, label: 'Manager' },
    ],
  },
  {
    name: 'taxi',
    label: 'Downtown Cab Co.',
    grades: [
      { grade: 0, label: 'Driver' },
      { grade: 1, label: 'Senior driver' },
      { grade: 2, label: 'Dispatcher' },
      { grade: 3, label: 'Owner' },
    ],
  },
];

export const mockGangs: JobInfo[] = [
  {
    name: 'ballas',
    label: 'Ballas',
    grades: [
      { grade: 0, label: 'Recruit' },
      { grade: 1, label: 'Enforcer' },
      { grade: 2, label: 'Shot Caller' },
      { grade: 3, label: 'Boss' },
    ],
  },
  {
    name: 'vagos',
    label: 'Vagos',
    grades: [
      { grade: 0, label: 'Soldado' },
      { grade: 1, label: 'Sicario' },
      { grade: 2, label: 'Teniente' },
      { grade: 3, label: 'Jefe' },
    ],
  },
];

export const mockProfiles: IplProfile[] = [
  { key: 'garage_2car', label: 'Low-end garage (2 cars)', coords: v4(173.29, -1003.6, -99.66, 0), slots: 2, options: [] },
  { key: 'garage_6car', label: 'Mid-range garage (6 cars)', coords: v4(197.82, -1002.29, -99.66, 0), slots: 6, options: [] },
  { key: 'garage_10car', label: 'High-end garage (10 cars)', coords: v4(229.96, -981.79, -99.66, 0), slots: 10, options: [] },
  {
    key: 'vehicle_warehouse',
    label: 'Vehicle warehouse (Import/Export)',
    coords: v4(994.59, -3002.59, -39.65, 0),
    slots: 40,
    options: [
      {
        key: 'style',
        label: 'Style',
        default: 'branded',
        choices: [
          { value: 'basic', label: 'Basic' },
          { value: 'branded', label: 'Branded' },
          { value: 'urban', label: 'Urban' },
        ],
      },
    ],
  },
  {
    key: 'tuner_car_meet',
    label: 'LS Car Meet (Tuners)',
    coords: v4(-2000.0, 1113.21, -25.36, 0),
    slots: 20,
    options: [
      {
        key: 'lighting',
        label: 'Lighting',
        default: 'premium',
        choices: [
          { value: 'premium', label: 'Premium' },
          { value: 'budget', label: 'Budget' },
        ],
      },
      {
        key: 'crowd',
        label: 'Crowd',
        default: 'off',
        choices: [
          { value: 'off', label: 'Empty' },
          { value: 'on', label: 'Car meet crowd' },
        ],
      },
    ],
  },
  {
    key: 'tuner_auto_shop',
    label: 'Auto Shop (Tuners)',
    coords: v4(-1350.0, 160.0, -100.0, 0),
    slots: 4,
    options: [
      {
        key: 'style',
        label: 'Style',
        default: 'style_1',
        choices: [
          { value: 'style_1', label: 'Style 1' },
          { value: 'style_2', label: 'Style 2' },
          { value: 'style_3', label: 'Style 3' },
        ],
      },
    ],
  },
];

/** Vehicle slots in rows of `perRow`, facing `w`. */
function slotGrid(origin: Vec4, count: number, perRow = 5): Vec4[] {
  return Array.from({ length: count }, (_, i) => {
    const row = Math.floor(i / perRow);
    const col = i % perRow;
    return v4(r2(origin.x + col * 4.2), r2(origin.y + row * 7.5), origin.z, (origin.w + (row % 2 ? 180 : 0)) % 360);
  });
}

export const mockInteriors: Interior[] = [
  {
    id: 1,
    name: 'Executive Collection',
    enabled: true,
    profile: 'garage_10car',
    options: {},
    entry: v4(229.96, -981.79, -99.66, 0),
    gtaInteriorId: 148225,
    cutscene: {
      enabled: true,
      transition: 3000,
      returnTime: 1000,
      points: [
        { coords: v3(222.4, -1001.2, -97.6), rot: v3(-8, 0, 312), fov: 55 },
        { coords: v3(236.8, -992.5, -97.9), rot: v3(-6, 0, 38), fov: 50 },
        { coords: v3(231.2, -976.4, -98.1), rot: v3(-4, 0, 180), fov: 48 },
      ],
    },
    slots: slotGrid(v4(223.4, -1001.3, -99.66, 270), 10),
    exit: v4(240.75, -1004.88, -99.0, 90),
  },
  {
    id: 2,
    name: 'Hillside Showroom',
    enabled: true,
    profile: 'tuner_car_meet',
    options: { lighting: 'premium', crowd: 'off' },
    entry: v4(-2000.0, 1113.21, -25.36, 0),
    gtaInteriorId: 285697,
    cutscene: { enabled: false, transition: 3000, returnTime: 1000, points: [] },
    slots: slotGrid(v4(-2018.4, 1098.2, -26.1, 90), 12, 6),
    exit: null,
  },
  {
    id: 3,
    name: 'Eclipse Penthouse Garage',
    enabled: true,
    profile: 'garage_6car',
    options: {},
    entry: v4(197.82, -1002.29, -99.66, 0),
    gtaInteriorId: 149761,
    cutscene: { enabled: false, transition: 2500, returnTime: 1000, points: [] },
    slots: slotGrid(v4(193.4, -1004.2, -99.66, 0), 6, 3),
    exit: v4(206.9, -999.1, -99.0, 90),
  },
  {
    id: 4,
    name: 'Docks Warehouse',
    enabled: false,
    profile: 'vehicle_warehouse',
    options: { style: 'urban' },
    entry: v4(994.59, -3002.59, -39.65, 0),
    gtaInteriorId: 252673,
    cutscene: { enabled: false, transition: 3000, returnTime: 1000, points: [] },
    slots: slotGrid(v4(970.2, -3030.4, -39.65, 0), 8, 4),
    exit: null,
  },
];

/** config/config.lua → Config.DefaultSettings */
export const mockSettings: Settings = {
  vehicles: {
    spawnOutside: false,
    saveMods: true,
    checkModel: true,
    serverSpawn: false,
    saveDamage: true,
    saveDeformation: true,
    trailers: true,
    giveKeys: true,
    needsServiceBelow: 60,
  },
  garages: {
    retrieveMode: 'last',
    showBlips: true,
    suggestWhenFull: true,
    outOnRestart: 'garage',
    restartImpound: null,
    recoverFee: 250,
    storeOnlyOwned: true,
    maxDistance: 25,
  },
  transfers: {
    garageEnabled: true,
    garageFee: 2500,
    playerEnabled: true,
    playerFee: 0,
    sellEnabled: true,
    shareEnabled: true,
    maxShares: 5,
  },
  impound: { defaultFee: 500, defaultHours: 0, staffBypassFee: true },
  economy: { account: 'bank' },
  interface: {
    defaultView: 'grid',
    distanceUnit: 'mi',
    currency: '$',
    imageUrl: 'https://docs.fivem.net/vehicles/{model}.webp',
    showImages: true,
    accent: '#08afa2',
    interaction: 'prompt',
  },
};

/* ───────────────────────── locations ───────────────────────── */

type GarageSeed = Omit<GarageLocation, 'kind' | 'blip' | 'storePoints' | 'useOpenForStore' | 'returnToEntrance'> &
  Partial<Pick<GarageLocation, 'blip' | 'storePoints' | 'useOpenForStore' | 'returnToEntrance'>>;

function garage(s: GarageSeed): GarageLocation {
  return {
    useOpenForStore: true,
    storePoints: [],
    returnToEntrance: false,
    blip: blip('garage', s.vehicleType),
    ...s,
    kind: 'garage',
  };
}

const everyone = () => ({ type: 'everyone' as const, rules: [], identifiers: [] });

const publicGarages: GarageLocation[] = [
  garage({
    id: 1,
    name: 'Legion Square',
    vehicleType: 'car',
    enabled: true,
    openPoints: [pt(215.8, -810.06, 30.73)],
    spawnPoints: spawnRow(229.74, -800.12, 30.57, 157.5, 4),
    source: 'personal',
    spawner: [],
    capacity: limited(8),
    access: { mode: 'both', interiorId: 1 },
    restriction: everyone(),
  }),
  garage({
    id: 2,
    name: 'Alta Street',
    vehicleType: 'car',
    enabled: true,
    openPoints: [pt(-297.78, -990.09, 31.08)],
    spawnPoints: spawnRow(-282.12, -997.98, 30.71, 250.6, 3),
    useOpenForStore: false,
    storePoints: [pt(-300.6, -1000.8, 30.9, 4)],
    source: 'personal',
    spawner: [],
    capacity: unlimited(),
    access: quick(),
    restriction: everyone(),
  }),
  garage({
    id: 3,
    name: 'Mirror Park',
    vehicleType: 'car',
    enabled: true,
    openPoints: [pt(1032.84, -765.03, 58.0)],
    spawnPoints: spawnRow(1023.21, -763.42, 57.87, 330.2, 2),
    source: 'personal',
    spawner: [],
    capacity: unlimited(),
    access: quick(),
    restriction: everyone(),
  }),
  garage({
    id: 4,
    name: 'Vespucci Beach Rentals',
    vehicleType: 'car',
    enabled: true,
    openPoints: [pt(-1184.62, -1509.6, 4.65)],
    spawnPoints: spawnRow(-1183.1, -1495.6, 4.38, 125.4, 3, 2.2),
    source: 'spawner',
    spawner: [
      veh('bmx', { label: 'BMX', price: 25 }),
      veh('scorcher', { label: 'Mountain bike', price: 40 }),
      veh('faggio', { label: 'Beach scooter', plate: 'RENT##', price: 150 }),
      veh('blista', { plate: 'VB@@###', price: 450, extras: { '1': true } }),
    ],
    capacity: unlimited(),
    access: quick(),
    restriction: everyone(),
    returnToEntrance: true,
  }),
  garage({
    id: 5,
    name: 'Grove Street',
    vehicleType: 'car',
    enabled: true,
    openPoints: [pt(-56.88, -1838.62, 26.58)],
    spawnPoints: spawnRow(-51.4, -1841.7, 26.2, 319.6, 2),
    source: 'personal',
    spawner: [],
    capacity: limited(4),
    access: quick(),
    restriction: { type: 'gang', rules: [{ name: 'ballas', minGrade: 0 }], identifiers: [] },
  }),
  garage({
    id: 6,
    name: 'Sandy Shores Depot',
    vehicleType: 'car',
    enabled: true,
    openPoints: [pt(1737.93, 3710.2, 34.14)],
    spawnPoints: spawnRow(1737.7, 3718.9, 34.05, 21.4, 3),
    source: 'personal',
    spawner: [],
    capacity: unlimited(),
    access: quick(),
    restriction: { type: 'job', rules: [{ name: 'mechanic', minGrade: 1 }, { name: 'police', minGrade: 0 }], identifiers: [] },
  }),
  garage({
    id: 7,
    name: 'Harmony',
    vehicleType: 'car',
    enabled: false,
    openPoints: [pt(1180.43, 2648.92, 37.8)],
    spawnPoints: spawnRow(1188.2, 2650.4, 37.6, 0.8, 2),
    source: 'personal',
    spawner: [],
    capacity: unlimited(),
    access: quick(),
    restriction: everyone(),
  }),
  garage({
    id: 8,
    name: 'Grapeseed',
    vehicleType: 'car',
    enabled: true,
    openPoints: [pt(1700.93, 4805.62, 41.84)],
    spawnPoints: spawnRow(1691.4, 4785.2, 41.92, 90.1, 2),
    source: 'personal',
    spawner: [],
    capacity: unlimited(),
    access: quick(),
    restriction: everyone(),
  }),
  garage({
    id: 9,
    name: 'Paleto Bay',
    vehicleType: 'car',
    enabled: true,
    openPoints: [pt(105.36, 6613.59, 31.82)],
    spawnPoints: spawnRow(125.7, 6604.2, 31.85, 225.2, 4),
    source: 'personal',
    spawner: [],
    capacity: limited(20, 'total'),
    access: quick(),
    restriction: everyone(),
  }),
  garage({
    id: 10,
    name: 'Chumash Bluffs',
    vehicleType: 'car',
    enabled: true,
    openPoints: [pt(-3150.32, 1090.48, 20.7)],
    spawnPoints: spawnRow(-3143.2, 1100.8, 20.68, 249.2, 2),
    source: 'personal',
    spawner: [],
    capacity: limited(3),
    access: { mode: 'interior', interiorId: 3 },
    restriction: { type: 'identifier', rules: [], identifiers: ['NZV41207', 'QX55821', 'KT90344'] },
  }),
  garage({
    id: 11,
    name: 'LSIA Hangar',
    vehicleType: 'air',
    enabled: true,
    openPoints: [pt(-1274.33, -3384.6, 13.94, 3)],
    spawnPoints: [v4(-1275.1, -3388.2, 13.94, 329.5), v4(-1255.6, -3399.8, 13.94, 329.5)],
    source: 'personal',
    spawner: [],
    capacity: unlimited(),
    access: quick(),
    restriction: everyone(),
  }),
  garage({
    id: 12,
    name: 'Puerto Del Sol Marina',
    vehicleType: 'sea',
    enabled: true,
    openPoints: [pt(-795.17, -1510.76, 1.6)],
    spawnPoints: [v4(-800.42, -1520.91, 0.3, 110.5), v4(-806.6, -1505.3, 0.3, 110.5)],
    source: 'personal',
    spawner: [],
    capacity: unlimited(),
    access: quick(),
    restriction: everyone(),
  }),
];

const jobGarages: JobLocation[] = [
  {
    id: 13,
    kind: 'job',
    name: 'Mission Row PD',
    vehicleType: 'car',
    enabled: true,
    spawnPoints: spawnRow(446.4, -1025.3, 28.64, 4.1, 5, 3.6),
    openPoints: [pt(454.6, -1017.4, 28.43)],
    useOpenForStore: false,
    storePoints: [pt(459.8, -1008.2, 28.27, 5)],
    returnToEntrance: false,
    blip: blip('job', 'car'),
    source: 'spawner',
    owner: 'job',
    jobs: [{ name: 'police', minGrade: 0 }],
    spawner: [
      veh('police', { label: 'Patrol cruiser', plate: 'LSPD####' }),
      veh('police2', { label: 'Buffalo patrol', plate: 'LSPD####', grades: [1, 2, 3, 4], livery: 1 }),
      veh('police3', { label: 'Interceptor', plate: 'LSPD####', grades: [2, 3, 4], extras: { '1': true, '2': false } }),
      veh('policeb', { label: 'Motor unit', plate: 'LSPD@###', grades: [1, 2, 3, 4] }),
      veh('fbi2', { label: 'Command SUV', plate: 'CMD *##', grades: [3, 4], maxMods: true }),
      veh('riot', { label: 'Riot van', grades: [2, 3, 4], livery: 0 }),
    ],
    infiniteSpawns: false,
    setupMenu: true,
    capacity: unlimited(),
    access: quick(),
  },
  {
    id: 14,
    kind: 'job',
    name: 'Pillbox Medical',
    vehicleType: 'car',
    enabled: true,
    spawnPoints: spawnRow(329.4, -557.2, 28.74, 340.2, 3),
    openPoints: [pt(337.2, -580.3, 28.79)],
    useOpenForStore: true,
    storePoints: [],
    returnToEntrance: true,
    blip: blip('job', 'car'),
    source: 'owned',
    owner: 'job',
    jobs: [{ name: 'ambulance', minGrade: 0 }],
    spawner: [],
    infiniteSpawns: false,
    setupMenu: true,
    capacity: limited(12, 'total'),
    access: quick(),
  },
  {
    id: 15,
    kind: 'job',
    name: 'Ballas Hideout',
    vehicleType: 'car',
    enabled: true,
    spawnPoints: spawnRow(92.6, -1964.2, 20.75, 320.4, 2),
    openPoints: [pt(85.53, -1959.61, 20.72)],
    useOpenForStore: true,
    storePoints: [],
    returnToEntrance: false,
    blip: blip('job', 'car', false),
    source: 'owned',
    owner: 'gang',
    jobs: [{ name: 'ballas', minGrade: 1 }],
    spawner: [],
    infiniteSpawns: false,
    setupMenu: false,
    capacity: unlimited(),
    access: quick(),
  },
];

const privateGarages: PrivateLocation[] = [
  {
    id: 16,
    kind: 'private',
    name: 'Vinewood Hills Estate',
    vehicleType: 'car',
    enabled: true,
    spawnPoints: spawnRow(-106.2, 1009.4, 235.76, 110.3, 2),
    openPoints: [pt(-110.04, 1000.12, 235.84)],
    useOpenForStore: true,
    storePoints: [],
    returnToEntrance: false,
    blip: blip('private', 'car'),
    purchasable: true,
    price: 85000,
    maxCopies: 0,
    storage: 'shared',
    sellRefund: 50,
    capacity: limited(10, 'total'),
    access: { mode: 'both', interiorId: 2 },
  },
  {
    id: 17,
    kind: 'private',
    name: 'Eclipse Towers',
    vehicleType: 'car',
    enabled: true,
    spawnPoints: spawnRow(-796.4, 318.2, 85.7, 180.4, 2),
    openPoints: [pt(-796.04, 304.12, 85.7)],
    useOpenForStore: true,
    storePoints: [],
    returnToEntrance: true,
    blip: blip('private', 'car', false),
    purchasable: false,
    price: 0,
    maxCopies: 3,
    storage: 'personal',
    sellRefund: 0,
    capacity: limited(6, 'total'),
    access: { mode: 'interior', interiorId: 3 },
  },
];

const impounds: ImpoundLocation[] = [
  {
    id: 18,
    kind: 'impound',
    name: 'Davis Impound',
    vehicleType: 'car',
    enabled: true,
    spawnPoints: spawnRow(401.8, -1632.4, 29.29, 229.6, 4),
    openPoints: [pt(409.25, -1622.98, 29.29)],
    useOpenForStore: true,
    storePoints: [],
    returnToEntrance: false,
    blip: blip('impound', 'car'),
    jobs: [
      { name: 'police', minGrade: 0 },
      { name: 'mechanic', minGrade: 2 },
    ],
    society: 'police',
    defaultFee: 500,
    defaultHours: 0,
  },
  {
    id: 19,
    kind: 'impound',
    name: 'Paleto Bay Impound',
    vehicleType: 'car',
    enabled: true,
    spawnPoints: spawnRow(-462.4, 6029.8, 31.34, 225.1, 2),
    openPoints: [pt(-458.3, 6016.02, 31.49)],
    useOpenForStore: true,
    storePoints: [],
    returnToEntrance: false,
    blip: blip('impound', 'car'),
    jobs: [{ name: 'police', minGrade: 1 }],
    society: '',
    defaultFee: 750,
    defaultHours: 12,
  },
];

const allLocations: Location[] = [...publicGarages, ...jobGarages, ...privateGarages, ...impounds];

/* ───────────────────────── AdminOpenData ───────────────────────── */

export const adminMockData: AdminOpenData = {
  page: 'garages',
  settings: mockSettings,
  locations: allLocations,
  interiors: mockInteriors,
  profiles: mockProfiles,
  jobs: mockJobs,
  gangs: mockGangs,
  framework: 'qbx',
  gangsSupported: true,
  importSources: [
    { key: 'qb-garages', label: 'QBCore garages (qb-garages)', available: true },
    { key: 'qbx_garages', label: 'Qbox garages (qbx_garages)', available: false },
    { key: 'json', label: 'JSON', available: true },
  ],
};

/** Mutable state behind the admin mock handlers. */
export const adminMockDb: AdminOpenData = clone(adminMockData);

/* ───────────────────────── private groups ───────────────────────── */

const PEOPLE: Record<string, string> = {
  NZV41207: 'Jordan Vale',
  QX55821: 'Lena Ortiz',
  KT90344: 'Kenji Tanaka',
  AB10077: 'Ava Brooks',
  PS44120: 'Priya Shah',
  MR73315: 'Marcus Reid',
  CM20981: 'Chloe Martin',
  DV66012: 'Dmitri Volkov',
};

const member = (identifier: string, role: 'owner' | 'member') => ({ identifier, name: PEOPLE[identifier] ?? identifier, role });

export const adminMockGroups: Record<number, GroupInfo[]> = {
  16: [
    {
      id: 1,
      locationId: 16,
      label: 'Vale Residence',
      owner: 'NZV41207',
      ownerName: 'Jordan Vale',
      members: [member('NZV41207', 'owner'), member('AB10077', 'member')],
      vehicles: 4,
      createdAt: nowS() - 42 * DAY,
    },
    {
      id: 2,
      locationId: 16,
      label: 'Tanaka Collection',
      owner: 'KT90344',
      ownerName: 'Kenji Tanaka',
      members: [member('KT90344', 'owner'), member('PS44120', 'member'), member('MR73315', 'member')],
      vehicles: 7,
      createdAt: nowS() - 18 * DAY,
    },
    {
      id: 3,
      locationId: 16,
      label: 'Ortiz Garage',
      owner: 'QX55821',
      ownerName: 'Lena Ortiz',
      members: [member('QX55821', 'owner')],
      vehicles: 0,
      createdAt: nowS() - 3 * DAY,
    },
  ],
  17: [
    {
      id: 4,
      locationId: 17,
      label: 'Penthouse 31',
      owner: 'CM20981',
      ownerName: 'Chloe Martin',
      members: [member('CM20981', 'owner'), member('DV66012', 'member')],
      vehicles: 2,
      createdAt: nowS() - 64 * DAY,
    },
  ],
};

let groupSeq = 4;

function findGroup(id: number): GroupInfo | null {
  for (const list of Object.values(adminMockGroups)) {
    const g = list.find((x) => x.id === id);
    if (g) return g;
  }
  return null;
}

/* ───────────────────────── handlers ───────────────────────── */

const fail = (error: string) => ({ ok: false as const, error });

mockNui('admin:refresh', async () => {
  await wait(380);
  return clone(adminMockDb);
});

mockNui('admin:location:save', async ({ location }) => {
  await wait(520);
  if (!location || !location.name?.trim()) return fail('A name is required');
  if (/^fail/i.test(location.name.trim())) return fail('Could not save the location (mock failure)');
  const saved = clone(location);
  saved.name = saved.name.trim();
  if (saved.id === null) {
    saved.id = Math.max(0, ...adminMockDb.locations.map((l) => l.id ?? 0)) + 1;
    adminMockDb.locations.push(saved);
  } else {
    const i = adminMockDb.locations.findIndex((l) => l.id === saved.id);
    if (i < 0) return fail('Location not found');
    adminMockDb.locations[i] = saved;
  }
  return clone(saved);
});

mockNui('admin:location:delete', async ({ id }) => {
  await wait(420);
  const i = adminMockDb.locations.findIndex((l) => l.id === id);
  if (i < 0) return fail('Location not found');
  adminMockDb.locations.splice(i, 1);
  delete adminMockGroups[id];
  return null;
});

mockNui('admin:location:toggle', async ({ id, enabled }) => {
  await wait(260);
  const loc = adminMockDb.locations.find((l) => l.id === id);
  if (!loc) return fail('Location not found');
  loc.enabled = enabled;
  return null;
});

mockNui('admin:location:teleport', async () => {
  await wait(200);
  return null;
});

mockNui('admin:location:import', async ({ source, json }) => {
  await wait(900);
  const nextId = () => Math.max(0, ...adminMockDb.locations.map((l) => l.id ?? 0)) + 1;
  const add = (name: string, x: number, y: number, z: number, w: number) => {
    adminMockDb.locations.push(
      garage({
        id: nextId(),
        name,
        vehicleType: 'car',
        enabled: true,
        openPoints: [pt(x, y, z)],
        spawnPoints: spawnRow(x + 6, y + 4, z, w, 2),
        source: 'personal',
        spawner: [],
        capacity: unlimited(),
        access: quick(),
        restriction: everyone(),
      }),
    );
  };
  if (source === 'json') {
    let parsed: unknown;
    try {
      if (!json?.trim()) return fail('Paste the JSON to import');
      parsed = JSON.parse(json);
    } catch {
      return fail('The JSON could not be read');
    }
    const root = parsed as { locations?: unknown };
    const list = Array.isArray(parsed) ? parsed : Array.isArray(root?.locations) ? (root.locations as unknown[]) : [parsed];
    if (!list.length) return fail('The JSON does not contain any location');
    let imported = 0;
    let skipped = 0;
    const existing = new Set(adminMockDb.locations.map((l) => `${l.kind}|${l.name.toLowerCase()}`));
    list.forEach((raw) => {
      const r = raw as {
        kind?: unknown;
        name?: unknown;
        openPoints?: { coords?: { x?: unknown; y?: unknown; z?: unknown } }[];
      };
      const c = Array.isArray(r?.openPoints) ? r.openPoints[0]?.coords : undefined;
      const kind = r?.kind ?? 'garage';
      const ok = typeof r?.name === 'string' && kind === 'garage' && c && typeof c.x === 'number' && typeof c.y === 'number';
      if (ok && !existing.has(`garage|${(r.name as string).toLowerCase()}`)) {
        add(r.name as string, c.x as number, c.y as number, typeof c.z === 'number' ? c.z : 30, 0);
        imported++;
      } else {
        skipped++;
      }
    });
    return { imported, skipped };
  }
  if (source === 'qb-garages') {
    add('Pillbox Garage (imported)', 213.2, -796.1, 30.86, 70);
    add('Spanish Ave (imported)', -1160.8, -741.4, 19.63, 40);
    add('Strawberry Ave (imported)', 69.84, 12.6, 68.96, 160);
    return { imported: 3, skipped: 1 };
  }
  return fail('This resource is not running');
});

/** Simulates the in-world point manager: shows the key hint, then returns the edited list. */
mockNui('admin:points', async ({ kind, points, vehicleType }) => {
  emitNuiMessage({
    action: 'hint',
    data: {
      title: kind === 'spawn' ? 'Spawn points' : kind === 'open' ? 'Open interactions' : 'Store interactions',
      keys: [
        { keys: ['E'], label: 'Add point' },
        { keys: ['W', 'A', 'S', 'D'], label: 'Move' },
        { keys: ['Scroll'], label: 'Rotate' },
        { keys: ['Del'], label: 'Remove' },
        { keys: ['Enter'], label: 'Done' },
        { keys: ['Esc'], label: 'Cancel' },
      ],
    },
  });
  await wait(1500);
  emitNuiMessage({ action: 'hint', data: null });
  const list = (points ?? []) as (Vec4 | InteractionPoint)[];
  const base: Vec3 =
    list.length > 0
      ? 'coords' in list[0]
        ? (list[0] as InteractionPoint).coords
        : (list[0] as Vec4)
      : vehicleType === 'sea'
        ? v3(-795.2, -1510.8, 0.4)
        : vehicleType === 'air'
          ? v3(-1274.3, -3384.6, 13.9)
          : v3(215.8, -810.1, 30.7);
  const n = list.length;
  const jitter = (i: number) => ({ x: r2(base.x + 3.6 * (i + 1)), y: r2(base.y - 1.2 * (i + 1)), z: r2(base.z) });
  if (kind === 'spawn') {
    const existing = list as Vec4[];
    const p = jitter(n);
    return [...existing, v4(p.x, p.y, p.z, r2((existing[0]?.w ?? 157.5) % 360))];
  }
  const existing = list as InteractionPoint[];
  const p = jitter(n);
  return [...existing, { coords: v3(p.x, p.y, p.z), radius: kind === 'store' ? 4 : 2 }];
});

mockNui('admin:pickPosition', async () => {
  await wait(200);
  return v4(215.82, -810.06, 30.73, 157.5);
});

mockNui('admin:groups', async ({ locationId }) => {
  await wait(480);
  return clone(adminMockGroups[locationId] ?? []);
});

mockNui('admin:group:save', async ({ group }) => {
  await wait(420);
  const owner = (group.owner ?? '').trim().toUpperCase();
  if (!owner) return fail('Enter the identifier of the owner');
  if (!PEOPLE[owner]) return fail('Character not found');
  if (group.id !== undefined) {
    const g = findGroup(group.id);
    if (!g) return fail('Garage not found');
    g.label = group.label || g.label;
    return clone(g);
  }
  const loc = adminMockDb.locations.find((l) => l.id === group.locationId);
  if (!loc || loc.kind !== 'private') return fail('Select a private garage location');
  const list = (adminMockGroups[loc.id as number] ??= []);
  if (loc.maxCopies > 0 && list.length >= loc.maxCopies) return fail('No copies of this garage are left');
  const g: GroupInfo = {
    id: ++groupSeq,
    locationId: loc.id as number,
    label: group.label?.trim() || loc.name,
    owner,
    ownerName: PEOPLE[owner],
    members: [member(owner, 'owner')],
    vehicles: 0,
    createdAt: nowS(),
  };
  list.push(g);
  return clone(g);
});

mockNui('admin:group:delete', async ({ id }) => {
  await wait(380);
  const g = findGroup(id);
  if (!g) return fail('Garage not found');
  if (g.vehicles > 0) return fail(`${g.vehicles} vehicles are still parked in this garage. Move them first.`);
  const list = adminMockGroups[g.locationId] ?? [];
  adminMockGroups[g.locationId] = list.filter((x) => x.id !== id);
  return null;
});

mockNui('admin:group:member', async ({ groupId, identifier, role }) => {
  await wait(320);
  const g = findGroup(groupId);
  if (!g) return fail('Garage not found');
  const id = identifier.trim().toUpperCase();
  const existing = g.members.find((m) => m.identifier === id);
  if (role === null) {
    if (id === g.owner) return fail('The owner cannot be removed. Choose a new owner first.');
    if (!existing) return fail('This player is not a member of the garage');
    g.members = g.members.filter((m) => m.identifier !== id);
    return clone(g);
  }
  if (!existing && !PEOPLE[id]) return fail('Character not found');
  if (role === 'owner') {
    g.members = g.members.map((m) => (m.identifier === g.owner ? { ...m, role: 'member' } : m));
    g.owner = id;
    g.ownerName = PEOPLE[id] ?? id;
  } else if (id === g.owner) {
    return fail('Choose a new owner before changing this role');
  }
  if (existing) existing.role = role;
  else g.members.push(member(id, role));
  g.members.sort((a, b) => (a.role === b.role ? a.name.localeCompare(b.name) : a.role === 'owner' ? -1 : 1));
  return clone(g);
});

/* ───────────────────────── scenarios ───────────────────────── */

/** Dev-only hints read by the location pages: open the editor for this id ('new' = create),
 *  optionally on a tab ('owners' for saved private garages). */
type DevHint = { __devEdit?: number | 'new'; __devTab?: 'settings' | 'owners' };

function open(page: AdminPage, extra: Partial<AdminOpenData> & DevHint = {}) {
  return {
    action: 'open' as const,
    data: { app: 'admin' as const, data: { ...clone(adminMockDb), page, ...extra } },
  };
}

registerMock({ id: 'admin-garages', group: 'Admin', label: 'Garages (table + map)', messages: [open('garages')] });
registerMock({ id: 'admin-jobs', group: 'Admin', label: 'Job & gang garages', messages: [open('jobs')] });
registerMock({ id: 'admin-private', group: 'Admin', label: 'Private garages', messages: [open('private')] });
registerMock({ id: 'admin-impounds', group: 'Admin', label: 'Impounds', messages: [open('impounds')] });
registerMock({
  id: 'admin-edit-location',
  group: 'Admin',
  label: 'Edit location (Legion Square)',
  messages: [open('garages', { __devEdit: 1 })],
});
registerMock({
  id: 'admin-edit-job',
  group: 'Admin',
  label: 'Edit job garage (police spawner)',
  messages: [open('jobs', { __devEdit: 13 })],
});
registerMock({
  id: 'admin-edit-private',
  group: 'Admin',
  label: 'Edit private garage (owners)',
  messages: [open('private', { __devEdit: 16 })],
});
registerMock({
  id: 'admin-private-owners',
  group: 'Admin',
  label: 'Private garage owners & copies',
  messages: [open('private', { __devEdit: 16, __devTab: 'owners' })],
});
registerMock({
  id: 'admin-create-impound',
  group: 'Admin',
  label: 'Create impound',
  messages: [open('impounds', { __devEdit: 'new' })],
});
registerMock({
  id: 'admin-empty',
  group: 'Admin',
  label: 'Empty (standalone, no gangs)',
  messages: [
    open('garages', {
      locations: [],
      interiors: [],
      gangs: [],
      gangsSupported: false,
      framework: 'standalone',
    }),
  ],
});
