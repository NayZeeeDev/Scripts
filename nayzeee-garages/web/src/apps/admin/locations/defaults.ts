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
