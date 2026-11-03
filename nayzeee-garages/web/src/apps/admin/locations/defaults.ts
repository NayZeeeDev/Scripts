/**
 * New-location defaults per kind (docs/ARCHITECTURE.md §4.2 / NZ.Locations.normalize).
 *
 * API
 * - newLocation(kind, data)         a complete, unsaved Location (id null) of that kind.
 * - normalizeLocation(loc, data)    a deep copy of a Location from Lua with every field present:
 *                                   Lua drops nil fields (interiorId…) and may encode empty
 *                                   tables as {} or [] — the editor always works on full shapes.
 * - newSpawnerVehicle()             an empty SpawnerVehicle.
 * - defaultBlipSprite(kind, vt)     357 car / 356 sea / 359 air, 68 for impounds.
 * - DEFAULT_BLIP_COLOUR[kind]       3 garage, 38 job, 5 private, 1 impound.
 * - OPEN_RADIUS / STORE_RADIUS      Config.Interaction defaults (2.0 / 4.0 m).
 * - defaultInteraction()            { mode: 'default', ped: null } (follow the server setting, no NPC).
 * - normalizeInteraction(raw, scenario?)
 *                                   a complete LocationInteraction from whatever Lua sent (absent = defaults).
 * - pedDefaults(data)               { model, scenario }: Config.Peds defaults from the admin data
 *                                   (`peds`, when the server sends it), else the shipped values.
 * - PED_DEFAULT_MODEL / PED_DEFAULT_SCENARIO / PED_SCENARIOS / PED_MODEL_PRESETS
 *                                   NPC defaults (Config.Peds) and the choices offered in the editor.
 */
import type {
  AccessConfig,
  AdminOpenData,
  BlipConfig,
  CapacityConfig,
  GarageLocation,
  ImpoundLocation,
  JobLocation,
  Location,
  LocationBase,
  LocationInteraction,
  PrivateLocation,
  SpawnerVehicle,
  VehicleType,
} from '@/lib/types';
import type { LocationPageKind } from '../shared/labels';

export const OPEN_RADIUS = 2;
export const STORE_RADIUS = 4;

const SPRITES: Record<VehicleType, number> = { car: 357, sea: 356, air: 359 };
export const IMPOUND_SPRITE = 68;

export const DEFAULT_BLIP_COLOUR: Record<LocationPageKind, number> = {
  garage: 3,
  job: 38,
  private: 5,
  impound: 1,
};

export function defaultBlipSprite(kind: LocationPageKind, vt: VehicleType): number {
  return kind === 'impound' ? IMPOUND_SPRITE : SPRITES[vt] ?? SPRITES.car;
}

export function defaultBlip(kind: LocationPageKind, vt: VehicleType = 'car'): BlipConfig {
  return { enabled: true, sprite: defaultBlipSprite(kind, vt), color: DEFAULT_BLIP_COLOUR[kind], scale: 0.7 };
}

/** Shipped Config.Peds.defaultModel / defaultScenario (config/config.lua), used until the
 *  server sends its own (pedDefaults). */
export const PED_DEFAULT_MODEL = 's_m_y_valet_01';
export const PED_DEFAULT_SCENARIO = 'WORLD_HUMAN_CLIPBOARD';
/** Same rule as the server (server/locations.lua): letters, digits and _, max 32. */
export const PED_MODEL_MAX = 32;

/** Config.Peds defaults of this server: AdminOpenData.peds when present (validated like the
 *  server validates location NPCs), else the shipped values. */
export function pedDefaults(data: AdminOpenData): { model: string; scenario: string } {
  const raw = (data as AdminOpenData & { peds?: { defaultModel?: unknown; defaultScenario?: unknown } | null }).peds;
  const model = raw?.defaultModel;
  const scenario = raw?.defaultScenario;
  return {
    model: typeof model === 'string' && /^[A-Za-z0-9_]{1,32}$/.test(model) ? model : PED_DEFAULT_MODEL,
    scenario: typeof scenario === 'string' && /^[A-Za-z0-9_]{0,64}$/.test(scenario) ? scenario : PED_DEFAULT_SCENARIO,
  };
}

/** Scenarios offered for location NPCs ('' = stands idle). Labels are translated where shown. */
export const PED_SCENARIOS: { value: string; label: string }[] = [
  { value: 'WORLD_HUMAN_CLIPBOARD', label: 'Holding a clipboard' },
  { value: 'WORLD_HUMAN_STAND_IMPATIENT', label: 'Waiting impatiently' },
  { value: 'WORLD_HUMAN_SMOKING', label: 'Smoking' },
  { value: 'WORLD_HUMAN_GUARD_STAND', label: 'Standing guard' },
  { value: 'WORLD_HUMAN_AA_COFFEE', label: 'Drinking coffee' },
  { value: 'WORLD_HUMAN_STAND_MOBILE', label: 'On the phone' },
  { value: '', label: 'None (stands still)' },
];

/** Quick picks for the NPC model field (base-game ped models). */
export const PED_MODEL_PRESETS: { value: string; label: string }[] = [
  { value: 's_m_y_valet_01', label: 'Valet' },
  { value: 's_m_m_autoshop_01', label: 'Mechanic' },
  { value: 's_m_m_security_01', label: 'Security' },
  { value: 's_m_y_cop_01', label: 'Police officer' },
  { value: 's_m_y_airworker', label: 'Airport crew' },
  { value: 's_m_m_dockwork_01', label: 'Dock worker' },
];

export const defaultInteraction = (): LocationInteraction => ({ mode: 'default', ped: null });

const INTERACTION_MODES: LocationInteraction['mode'][] = ['default', 'prompt', 'target', 'both'];

/** Complete LocationInteraction from Lua (the field is absent on locations using the defaults).
 *  `scenario` fills an NPC without one (the server always sends it). */
export function normalizeInteraction(raw: unknown, scenario: string = PED_DEFAULT_SCENARIO): LocationInteraction {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return defaultInteraction();
  const src = raw as Partial<LocationInteraction> & { ped?: unknown };
  const mode = INTERACTION_MODES.includes(src.mode as LocationInteraction['mode']) ? (src.mode as LocationInteraction['mode']) : 'default';
  let ped: LocationInteraction['ped'] = null;
  if (src.ped && typeof src.ped === 'object' && !Array.isArray(src.ped)) {
    const p = src.ped as { model?: unknown; scenario?: unknown };
    ped = {
      model: typeof p.model === 'string' ? p.model : '',
      scenario: typeof p.scenario === 'string' ? p.scenario : scenario,
    };
  }
  return { mode, ped };
}

const capacity = (): CapacityConfig => ({ mode: 'unlimited', appliesTo: 'player', spaces: 8 });
const access = (): AccessConfig => ({ mode: 'quick', interiorId: null });

function base(kind: LocationPageKind): Omit<LocationBase, 'kind'> {
  return {
    id: null,
    name: '',
    vehicleType: 'car',
    enabled: true,
    spawnPoints: [],
    openPoints: [],
    useOpenForStore: true,
    storePoints: [],
    returnToEntrance: false,
    blip: defaultBlip(kind, 'car'),
    interaction: defaultInteraction(),
  };
}

export function newLocation(kind: LocationPageKind, data: AdminOpenData): Location {
  switch (kind) {
    case 'job': {
      const loc: JobLocation = {
        ...base(kind),
        kind: 'job',
        source: 'spawner',
        owner: 'job',
        jobs: [],
        spawner: [],
        infiniteSpawns: false,
        setupMenu: true,
        capacity: capacity(),
        access: access(),
      };
      return loc;
    }
    case 'private': {
      const loc: PrivateLocation = {
        ...base(kind),
        kind: 'private',
        purchasable: true,
        price: 50000,
        maxCopies: 1,
        storage: 'shared',
        sellRefund: 50,
        capacity: capacity(),
        access: access(),
      };
      return loc;
    }
    case 'impound': {
      const loc: ImpoundLocation = {
        ...base(kind),
        kind: 'impound',
        jobs: [],
        society: '',
        defaultFee: data.settings?.impound?.defaultFee ?? 500,
        defaultHours: data.settings?.impound?.defaultHours ?? 0,
      };
      return loc;
    }
    default: {
      const loc: GarageLocation = {
        ...base('garage'),
        kind: 'garage',
        source: 'personal',
        spawner: [],
        capacity: capacity(),
        access: access(),
        restriction: { type: 'everyone', rules: [], identifiers: [] },
      };
      return loc;
    }
  }
}

const arr = <T,>(v: unknown): T[] => (Array.isArray(v) ? (v as T[]) : []);
const obj = <T extends object>(v: unknown, fallback: T): T =>
  v && typeof v === 'object' && !Array.isArray(v) ? ({ ...fallback, ...(v as Partial<T>) } as T) : fallback;

function normalizeSpawner(list: unknown): SpawnerVehicle[] {
  return arr<Partial<SpawnerVehicle>>(list).map((v) => {
    const base = newSpawnerVehicle();
    const extras = v.extras && typeof v.extras === 'object' && !Array.isArray(v.extras) ? { ...v.extras } : {};
    return { ...base, ...v, grades: arr<number>(v.grades), extras };
  });
}

/** Complete, deep-copied Location from whatever Lua sent (see the header). */
export function normalizeLocation(raw: Location, data: AdminOpenData): Location {
  const src = JSON.parse(JSON.stringify(raw)) as Location & Record<string, unknown>;
  const kind = ((src.kind as string) === 'house' ? 'garage' : src.kind) as LocationPageKind;
  const defaults = newLocation(kind, data) as Location & Record<string, unknown>;
  const out = { ...defaults, ...src } as Location & Record<string, unknown>;
  out.id = typeof src.id === 'number' ? src.id : null;
  out.spawnPoints = arr(src.spawnPoints);
  out.openPoints = arr(src.openPoints);
  out.storePoints = arr(src.storePoints);
  out.blip = obj(src.blip, defaults.blip);
  out.interaction = normalizeInteraction(src.interaction, pedDefaults(data).scenario);
  if (out.kind === 'garage' || out.kind === 'job' || out.kind === 'private') {
    const d = defaults as GarageLocation;
    const capacity = obj(src.capacity, d.capacity);
    const access = obj(src.access, d.access);
    out.capacity = capacity;
    out.access = { mode: access.mode ?? 'quick', interiorId: typeof access.interiorId === 'number' ? access.interiorId : null };
  }
  if (out.kind === 'garage') {
    const r = obj(src.restriction, (defaults as GarageLocation).restriction);
    out.restriction = { type: r.type ?? 'everyone', rules: arr(r.rules), identifiers: arr(r.identifiers) };
    out.spawner = normalizeSpawner(src.spawner);
  }
  if (out.kind === 'job') {
    out.jobs = arr(src.jobs);
    out.spawner = normalizeSpawner(src.spawner);
  }
  if (out.kind === 'impound') {
    out.jobs = arr(src.jobs);
    out.society = typeof src.society === 'string' ? src.society : '';
  }
  return out as Location;
}

export function newSpawnerVehicle(): SpawnerVehicle {
  return { model: '', label: '', plate: '', grades: [], livery: -1, extras: {}, maxMods: false, price: 0 };
}
