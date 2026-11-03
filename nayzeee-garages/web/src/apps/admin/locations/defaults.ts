/**
 * New-location defaults per kind (docs/ARCHITECTURE.md §4.2 / NZ.Locations.normalize).
 *
 * API
 * - newLocation(kind, data)         a complete, unsaved Location (id null) of that kind.
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

export function newSpawnerVehicle(): SpawnerVehicle {
  return { model: '', label: '', plate: '', grades: [], livery: -1, extras: {}, maxMods: false, price: 0 };
}
