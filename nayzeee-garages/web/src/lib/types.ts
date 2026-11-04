/**
 * nayzeee-garages — shared data contracts between Lua and the NUI.
 * Mirrors docs/ARCHITECTURE.md. Lua tables use exactly these camelCase keys.
 * Do not rename fields; add optional fields only when the Lua side sends them too.
 */

/* ───────────────────────── primitives ───────────────────────── */

export type LocationId = number | string;
export type VehicleType = 'car' | 'sea' | 'air';
export type LocationKind = 'garage' | 'job' | 'private' | 'impound' | 'house';
export type VehicleState = 'garaged' | 'out' | 'impounded';
export type Role = 'owner' | 'member';

export interface Vec3 { x: number; y: number; z: number }
export interface Vec4 extends Vec3 { w: number }

/** Every NUI callback resolves to this shape. */
export type ApiResult<T = unknown> = { ok: true; data: T } | { ok: false; error: string };

/* ───────────────────────── locations ───────────────────────── */

export interface InteractionPoint { coords: Vec3; radius: number }
export interface JobRule { name: string; minGrade: number }
export interface BlipConfig { enabled: boolean; sprite: number; color: number; scale: number }
export interface CapacityConfig { mode: 'unlimited' | 'limited'; appliesTo: 'player' | 'total'; spaces: number }
export interface AccessConfig { mode: 'quick' | 'interior' | 'both'; interiorId: number | null }
export interface RestrictionConfig {
  type: 'everyone' | 'job' | 'gang' | 'identifier';
  rules: JobRule[];
  identifiers: string[];
}

export interface SpawnerVehicle {
  model: string;
  /** Display name override ('' = automatic). */
  label: string;
  /** '' = random, else template: '#' digit, '@' letter, '*' either, other chars literal (max 8). */
  plate: string;
  /** Allowed grades; empty = every grade. */
  grades: number[];
  /** -1 = default livery. */
  livery: number;
  extras: Record<string, boolean>;
  maxMods: boolean;
  price: number;
}

export interface LocationBase {
  /** null while creating a new location in the admin panel. */
  id: number | null;
  kind: LocationKind;
  name: string;
  vehicleType: VehicleType;
  enabled: boolean;
  spawnPoints: Vec4[];
  openPoints: InteractionPoint[];
  useOpenForStore: boolean;
  storePoints: InteractionPoint[];
  returnToEntrance: boolean;
  blip: BlipConfig;
  /** Per-location interaction override and optional NPC (target mode). Absent = defaults. */
  interaction?: LocationInteraction;
}

export interface LocationInteraction {
  /** 'default' follows settings.interface.interaction. */
  mode: 'default' | 'prompt' | 'target' | 'both';
  /** NPC standing at the first open point (target option on the ped). null = none. */
  ped: { model: string; scenario: string } | null;
}

export interface GarageLocation extends LocationBase {
  kind: 'garage';
  source: 'personal' | 'spawner';
  spawner: SpawnerVehicle[];
  capacity: CapacityConfig;
  access: AccessConfig;
  restriction: RestrictionConfig;
}

export interface JobLocation extends LocationBase {
  kind: 'job';
  source: 'owned' | 'spawner';
  owner: 'job' | 'gang';
  jobs: JobRule[];
  spawner: SpawnerVehicle[];
  infiniteSpawns: boolean;
  setupMenu: boolean;
  capacity: CapacityConfig;
  access: AccessConfig;
}

export interface PrivateLocation extends LocationBase {
  kind: 'private';
  purchasable: boolean;
  price: number;
  /** 0 = unlimited copies. */
  maxCopies: number;
  storage: 'shared' | 'personal';
  /** Percent of the price refunded when an owner sells the (empty) garage. */
  sellRefund: number;
  capacity: CapacityConfig;
  access: AccessConfig;
}

export interface ImpoundLocation extends LocationBase {
  kind: 'impound';
  jobs: JobRule[];
  /** Society account receiving fees ('' = none). */
  society: string;
  defaultFee: number;
  defaultHours: number;
}

export type Location = GarageLocation | JobLocation | PrivateLocation | ImpoundLocation;

/* ───────────────────────── vehicles ───────────────────────── */

export interface Finance {
  balance: number;
  payment: number;
  paymentsLeft: number;
  paymentsTotal: number | null;
  intervalHours: number | null;
  nextPaymentHours: number | null;
  overdue: boolean;
}

export interface ImpoundInfo {
  locationId: number;
  locationName: string;
  reason: string;
  fee: number;
  by: string | null;
  byName: string;
  /** unix seconds */
  at: number;
  /** unix seconds — retrievable after this moment */
  releaseAt: number;
  retrievable: boolean;
}

/** Model performance read by the client from the model info (NZ.Veh.modelInfo). */
export interface VehicleStats {
  /** Estimated top speed in km/h (convert with settings.distanceUnit for display). */
  topSpeed: number;
  /** 0-100 ratings against fixed reference maxima. */
  speed: number;
  acceleration: number;
  braking: number;
  traction: number;
  seats: number;
}

/** Added by the client (NZ.Veh.enrichDeep) to every table with a numeric `hash`. */
export interface VehicleLabel {
  /** "Make Name", e.g. "Annis Elegy Retro Custom" */
  label: string;
  make: string;
  /** Lower-case model name used to build image URLs (settings.interface.imageUrl). */
  image: string | null;
  /** GTA vehicle class id (0-22) and its translated name ("Super", "SUVs"...). Absent for unknown models. */
  classId?: number;
  classLabel?: string;
  stats?: VehicleStats;
}

/**
 * Stored damage, summarised by the server (NZ.Vehicles.damageSummary).
 * Doors: 0 front left, 1 front right, 2 rear left, 3 rear right, 4 bonnet, 5 boot.
 * Windows: 0 front left, 1 front right, 2 rear left, 3 rear right, 4/5 middle, 6 windscreen, 7 rear windscreen.
 * Tyres: 0 front left, 1 front right, 2/45 middle left, 3/47 middle right, 4 rear left, 5 rear right.
 */
export interface DamageSummary {
  /** 0-1000 health values */
  engine: number;
  body: number;
  tank: number;
  /** damaged / missing doors */
  doors: number[];
  /** smashed windows */
  windows: number[];
  /** 1 = burst, 2 = on the rim */
  tyres: { index: number; state: 1 | 2 }[];
  deformed: boolean;
}

/** Installed performance upgrades (NZ.Vehicles.modSummary). Level 0 = stock. */
export interface ModSummary {
  engine: number;
  brakes: number;
  transmission: number;
  suspension: number;
  armor: number;
  turbo: boolean;
}

export interface GarageVehicle extends VehicleLabel {
  plate: string;
  model: string;
  hash: number;
  vehicleType: VehicleType;
  nickname: string | null;
  state: VehicleState;
  garageKey: string | null;
  garageName: string | null;
  /** Parked at the garage currently open. */
  here: boolean;
  fuel: number;
  engine: number;
  body: number;
  /** kilometres */
  mileage: number;
  favourite: boolean;
  isOwner: boolean;
  ownerName: string;
  /** Owner name when someone shared this vehicle with the viewer. */
  sharedBy: string | null;
  /** How many players the owner shared it with. */
  sharedWith: number;
  finance: Finance | null;
  impound: ImpoundInfo | null;
  trailer: { model: string; label: string } | null;
  canDrive: boolean;
  /** Why it cannot be driven from here (already translated), e.g. "Parked at Mirror Park". */
  reason: string | null;
  /** Out but the entity no longer exists. */
  canRecover: boolean;
  recoverFee: number;
  needsService: boolean;
  blocked: boolean;
  lastUsed: number | null;
  /** null when the vehicle was never stored with damage saving on. Empty lists arrive as [] or {}: use asList(). */
  damage: DamageSummary | null;
  /** null when no props are stored. */
  mods: ModSummary | null;
}

export interface SpawnerVehicleView extends VehicleLabel {
  index: number;
  model: string;
  hash: number;
  plate: string;
  price: number;
  vehicleType: VehicleType;
}

/* ───────────────────────── garage app ───────────────────────── */

export interface GarageSummary {
  key: string;
  locationId: LocationId;
  kind: LocationKind;
  name: string;
  vehicleType: VehicleType;
  source: 'personal' | 'spawner' | 'owned';
  isPrivate: boolean;
  groupId: number | null;
  groups: { id: number; label: string }[];
  role: Role | null;
  canGoInside: boolean;
  canManage: boolean;
  canSellGarage: boolean;
  jobLabel: string | null;
}

export interface CapacityInfo {
  mode: 'unlimited' | 'limited';
  appliesTo: 'player' | 'total';
  used: number;
  total: number;
}

export interface GarageOptions {
  retrieveMode: 'anywhere' | 'last';
  garageTransfer: boolean;
  playerTransfer: boolean;
  sell: boolean;
  share: boolean;
  garageFee: number;
  playerFee: number;
}

export interface GarageOpenData {
  garage: GarageSummary;
  capacity: CapacityInfo | null;
  vehicles: GarageVehicle[];
  spawner: SpawnerVehicleView[];
  options: GarageOptions;
}

export interface PlayerOption { serverId: number; name: string }

export interface TransferOptions {
  garages: { key: string; name: string; spacesLeft: number | null; fee: number }[];
  players: PlayerOption[];
  garageFee: number;
  playerFee: number;
}

export interface ShareData {
  sharedWith: { identifier: string; name: string }[];
  players: PlayerOption[];
  max: number;
}

export interface MemberData {
  members: { identifier: string; name: string; role: Role; you: boolean; online: boolean }[];
  players: PlayerOption[];
  canManage: boolean;
}

export interface ForSaleData {
  locationId: number;
  name: string;
  price: number;
  /** Copies still available. */
  available: number;
  /** 0 = unlimited */
  total: number;
  storage: 'shared' | 'personal';
  spaces: number | null;
  interiorName: string | null;
  canTour: boolean;
  canAfford: boolean;
}

/* ───────────────────────── impound ───────────────────────── */

export type ImpoundedVehicle = GarageVehicle & { impound: ImpoundInfo };

export interface ImpoundOpenData {
  impound: { id: number; name: string; vehicleType: VehicleType };
  /** Viewer is impound staff (sees every vehicle, can release). */
  staff: boolean;
  /** Staff take vehicles out without paying (settings.impound.staffBypassFee). */
  feeWaived?: boolean;
  vehicles: ImpoundedVehicle[];
}

export interface ImpoundFormData {
  plate: string;
  netId: number | null;
  label: string;
  /** Whether the plate belongs to a player-owned vehicle. */
  owned: boolean;
  impounds: { id: number; name: string }[];
  defaults: { fee: number; hours: number; impoundId: number | null };
}

/* ───────────────────────── interior / in-world ───────────────────────── */

export interface HudVehicle extends VehicleLabel {
  plate: string;
  model: string;
  vehicleType: VehicleType;
  mileage: number;
  fuel: number;
  engine: number;
  body: number;
  ownerName?: string;
  canDrive?: boolean;
}

export interface InteriorPanelData {
  garageName: string;
  page: number;
  pages: number;
  vehicles: number;
  slots: number;
  role: 'owner' | 'member' | 'guest';
  members: { serverId: number; name: string; role: 'owner' | 'member' | 'guest'; you: boolean }[];
  canInvite: boolean;
}

export interface SetupData {
  label: string;
  liveries: { index: number; label: string }[];
  livery: number;
  extras: { id: number; enabled: boolean }[];
}

export interface PromptData { key: string; label: string }
export interface HintData { title?: string; keys: { keys: string[]; label: string }[] }

/** Notification raised by the interface (NUI callback 'notify'). Lua decides where it is drawn:
 *  back inside the interface while a window holds focus, otherwise through the configured notify
 *  integration (ox_lib, framework, okokNotify, ...). */
export type NotifyType = 'success' | 'error' | 'info' | 'warning';
export interface NotifyRequest {
  type: NotifyType;
  /** plain text, max 300 characters */
  message: string;
  /** max 60 characters; defaults to Config.Notify.title */
  title?: string;
}

/** Lua -> NUI 'notify': a notification drawn inside the interface (<Toasts />). Lua sends it only
 *  while one of our windows holds NUI focus: FiveM then draws our page above every other
 *  resource's NUI, so the notify resource would be hidden behind the window
 *  (Config.Notify.inInterface). Text is plain and already capped by Lua. */
export interface Toast {
  type: NotifyType;
  message: string;
  /** only an explicit title (the generic Config.Notify.title is not repeated inside the window) */
  title?: string;
  /** ms, 1000-30000 from Lua (Config.Notify.duration unless the sender chose one); 0 = until clicked */
  duration?: number;
}

/* ───────────────────────── interiors & creator ───────────────────────── */

export interface CameraPoint { coords: Vec3; rot: Vec3; fov: number }

export interface Cutscene {
  enabled: boolean;
  /** ms per transition between points */
  transition: number;
  /** ms to return to the player camera */
  returnTime: number;
  points: CameraPoint[];
}

export interface Interior {
  id: number | null;
  name: string;
  enabled: boolean;
  profile: string | null;
  options: Record<string, string>;
  entry: Vec4;
  gtaInteriorId: number | null;
  cutscene: Cutscene;
  slots: Vec4[];
  exit: Vec4 | null;
}

export interface IplProfileOption {
  key: string;
  label: string;
  default: string;
  choices: { value: string; label: string }[];
}

export interface IplProfile {
  key: string;
  label: string;
  /** null = no quick-teleport coordinates known (hidden from the create modal). */
  coords: Vec4 | null;
  slots: number;
  options: IplProfileOption[];
}

export interface CreatorData {
  mode: 'create' | 'edit';
  interior: Interior;
  profiles: IplProfile[];
  gtaInteriorName: string | null;
}

/* ───────────────────────── settings ───────────────────────── */

export interface InterfaceSettings {
  defaultView: 'grid' | 'list';
  distanceUnit: 'mi' | 'km';
  currency: string;
  /** Template with {model}. */
  imageUrl: string;
  showImages: boolean;
  /** Hex accent colour, default #08afa2. */
  accent: string;
  /** 'both': prompt and target zones together. */
  interaction: 'prompt' | 'target' | 'both';
}

export interface Settings {
  vehicles: {
    spawnOutside: boolean;
    saveMods: boolean;
    checkModel: boolean;
    serverSpawn: boolean;
    saveDamage: boolean;
    saveDeformation: boolean;
    trailers: boolean;
    giveKeys: boolean;
    needsServiceBelow: number;
  };
  garages: {
    retrieveMode: 'anywhere' | 'last';
    showBlips: boolean;
    suggestWhenFull: boolean;
    outOnRestart: 'garage' | 'impound' | 'keep';
    restartImpound: number | null;
    recoverFee: number;
    storeOnlyOwned: boolean;
    maxDistance: number;
  };
  transfers: {
    garageEnabled: boolean;
    garageFee: number;
    playerEnabled: boolean;
    playerFee: number;
    sellEnabled: boolean;
    shareEnabled: boolean;
    maxShares: number;
  };
  impound: {
    defaultFee: number;
    defaultHours: number;
    staffBypassFee: boolean;
  };
  economy: {
    account: 'bank' | 'cash' | 'both';
  };
  interface: InterfaceSettings;
}

/* ───────────────────────── admin ───────────────────────── */

export type AdminPage = 'garages' | 'jobs' | 'private' | 'impounds' | 'interiors' | 'vehicles' | 'settings';

export interface JobInfo { name: string; label: string; grades: { grade: number; label: string }[] }

export interface GroupInfo {
  id: number;
  locationId: number;
  label: string;
  owner: string;
  ownerName: string;
  members: { identifier: string; name: string; role: Role }[];
  vehicles: number;
  createdAt: number;
}

/** Vehicles counted per location (DB.garageStats, cached 30 s on the server). */
export interface LocationStats {
  /** vehicles parked at this location (all owned copies for private locations) */
  parked: number;
  /** vehicles taken out from here and still out */
  out: number;
  /** vehicles last parked here that are impounded now */
  impounded: number;
  /** impound locations: vehicles held here */
  held: number;
}

export interface AdminOpenData {
  /** Keyed by String(location.id). Locations without vehicles are absent. */
  locationStats: Record<string, LocationStats>;
  page: AdminPage;
  settings: Settings;
  locations: Location[];
  interiors: Interior[];
  profiles: IplProfile[];
  jobs: JobInfo[];
  gangs: JobInfo[];
  framework: 'qb' | 'qbx' | 'esx' | 'standalone';
  gangsSupported: boolean;
  importSources: { key: string; label: string; available: boolean }[];
}

/** Props passed by AdminApp (shell) to every page component. */
export interface AdminPageProps {
  data: AdminOpenData;
  /** Re-fetch AdminOpenData from Lua (admin:refresh). */
  refresh: () => Promise<void>;
  /** Locally patch AdminOpenData (optimistic updates). */
  setData: (updater: (prev: AdminOpenData) => AdminOpenData) => void;
}

export interface Paged<T> { rows: T[]; total: number; page: number; pageSize: number }

export interface PlayerSearchRow { identifier: string; name: string; online: boolean; matchedPlates: string[] }

export interface AdminVehicleRow extends VehicleLabel {
  plate: string;
  model: string;
  hash: number;
  vehicleType: VehicleType;
  garageKey: string | null;
  garageName: string | null;
  state: VehicleState;
  financed: boolean;
  fuel: number;
  engine: number;
  body: number;
  blocked: boolean;
}

export interface ServiceEntry { id?: number; item: string; mileage: number; shop: string; at: number }
export interface OwnershipEntry { identifier: string | null; name: string; via: string; at: number; price?: number }

export interface AdminVehicleDetail {
  vehicle: AdminVehicleRow & {
    owner: string | null;
    ownerName: string;
    ownerType: 'player' | 'job' | 'gang';
    job: string | null;
    gang: string | null;
    nickname: string | null;
    mileage: number;
    props: Record<string, unknown>;
  };
  impound: ImpoundInfo | null;
  finance: Finance | null;
  ownership: OwnershipEntry[];
  service: ServiceEntry[];
  garages: { key: string; name: string }[];
  impounds: { id: number; name: string }[];
  damage: DamageSummary | null;
  /** unix seconds the vehicle was last taken out */
  lastUsed: number | null;
}

/** One nz_logs row of a vehicle (admin:vehicle:activity). Event names: 'vehicle.retrieve', 'vehicle.store',
 * 'vehicle.transfer', 'vehicle.share', 'vehicle.sell', 'vehicle.rename', 'vehicle.recover', 'vehicle.garage',
 * 'vehicle.finance', 'vehicle.service', 'vehicle.add', 'impound.add', 'impound.release', 'impound.retrieve',
 * 'interior.driveOut', 'admin.vehicle.update', 'admin.vehicle.assign', 'security.*' ... (unknown names must still render). */
export interface VehicleActivity {
  id: number;
  event: string;
  /** unix seconds */
  at: number;
  /** identifier of the acting player, null for the server */
  actor: string | null;
  actorName: string | null;
  /** free-form details (garage, fee, target, actorName...) */
  data: Record<string, unknown> | null;
}

/**
 * NOTE: JSON null never reaches Lua (it decodes to nil = "field absent").
 * To CLEAR a value send `false` (impound, finance) or '' (nickname, garageKey).
 */
export interface AdminVehiclePatch {
  plate?: string;
  owner?: { type: 'player' | 'job' | 'gang'; identifier?: string; job?: string; gang?: string };
  details?: {
    /** '' clears the garage */
    garageKey?: string;
    state?: VehicleState;
    /** '' clears the nickname */
    nickname?: string;
    mileage?: number;
    fuel?: number;
    engine?: number;
    body?: number;
  };
  props?: Record<string, unknown>;
  /** false = release from impound. `hours` (hold time from now) is preferred over releaseAt. */
  impound?: (Partial<ImpoundInfo> & { locationId: number; hours?: number }) | false;
  /** false = remove finance */
  finance?: Finance | false;
  blocked?: boolean;
  service?: ServiceEntry[];
}

/* ───────────────────────── car lock: key ring, locksmith, contracts ───────────────────────── */

/** How the player holds a key (docs/CARLOCK.md §3). */
export type KeyKind = 'owner' | 'item' | 'fob' | 'temp' | 'virtual';

export interface KeyEntry extends VehicleLabel {
  plate: string;
  model: string;
  hash: number;
  vehicleType: VehicleType;
  nickname: string | null;
  kind: KeyKind;
  /** security profile id and label ('standard' / 'highend' ...) */
  profile: string;
  profileLabel: string;
  /** electronic fob: remote locking from ranges.fob */
  remote: boolean;
  /** unix seconds (temporary keys), else null */
  expiresAt: number | null;
  isOwner: boolean;
  /** the vehicle exists in the player's routing bucket */
  spawned: boolean;
  netId: number | null;
  locked: boolean | null;
  /** metres from the player (client computed), null when not spawned */
  distance: number | null;
  /** tracker eligible and spawned */
  trackable: boolean;
  /** virtual: give a key to a nearby player; physical: hand the item over */
  canShare: boolean;
  /** virtual key holders (owner only) */
  holders: number;
}

export interface KeysOpenData {
  mode: 'physical' | 'virtual';
  keys: KeyEntry[];
  nearbyPlayers: PlayerOption[];
  ranges: { key: number; fob: number };
}

export interface KeyHolder { identifier: string; name: string; grantedBy: string | null; at: number }

export type LocksmithServiceId = 'duplicate' | 'program' | 'rekey';

export interface LocksmithService {
  id: LocksmithServiceId;
  enabled: boolean;
  price: number;
  materials: { item: string; label: string; count: number; have: number }[];
}

export interface LocksmithVehicle extends VehicleLabel {
  plate: string;
  model: string;
  hash: number;
  vehicleType: VehicleType;
  nickname: string | null;
  isOwner: boolean;
  hasKey: boolean;
  /** within range of the locksmith (program / rekey need the vehicle nearby) */
  nearby: boolean;
  distance: number | null;
}

export interface LocksmithOpenData {
  id: number;
  name: string;
  illegal: boolean;
  account: 'cash' | 'bank';
  services: LocksmithService[];
  vehicles: LocksmithVehicle[];
}

export interface ContractVehicle extends VehicleLabel {
  plate: string;
  model: string;
  hash: number;
  vehicleType: VehicleType;
  nickname: string | null;
  /** kilometres */
  mileage: number;
  engine: number;
  body: number;
}

export interface ContractParty { name: string; serverId?: number }

/** Signature = SVG path data ("M x y L x y ..."), at most 4000 characters, in a 400x140 box. */
export type Signature = string;

export type ContractOpenData =
  | { mode: 'draft'; seller: ContractParty; vehicles: ContractVehicle[]; buyers: PlayerOption[]; maxPrice: number; account: 'bank' | 'cash' }
  | { mode: 'review'; contractId: string; vehicle: ContractVehicle; seller: ContractParty; buyer: ContractParty; price: number; terms: string;
      sellerSignature: Signature; expiresAt: number; canAfford: boolean; account: 'bank' | 'cash' }
  | { mode: 'view'; vehicle: ContractVehicle; seller: ContractParty; buyer: ContractParty; price: number; terms: string;
      sellerSignature: Signature; buyerSignature: Signature; signedAt: number };

/* ───────────────────────── NUI protocol ───────────────────────── */

export type AppName = 'garage' | 'impound' | 'impoundForm' | 'forSale' | 'admin' | 'creator' | 'setup' | 'interior'
  | 'keys' | 'locksmith' | 'contract';

export interface AppDataMap {
  garage: GarageOpenData;
  impound: ImpoundOpenData;
  impoundForm: ImpoundFormData;
  forSale: ForSaleData;
  admin: AdminOpenData;
  creator: CreatorData;
  setup: SetupData;
  interior: InteriorPanelData;
  keys: KeysOpenData;
  locksmith: LocksmithOpenData;
  contract: ContractOpenData;
}

/** Lua -> NUI messages ({ action, data }). */
export type NuiMessage =
  | { action: 'init'; data: { locale: Record<string, string>; settings: InterfaceSettings; resource: string } }
  | { action: 'settings'; data: InterfaceSettings }
  | { action: 'open'; data: { app: AppName; data: unknown } }
  | { action: 'update'; data: { app: AppName; data: unknown } }
  | { action: 'close'; data: { app?: AppName | null } }
  | { action: 'hud'; data: HudVehicle | null }
  | { action: 'prompt'; data: PromptData | null }
  | { action: 'hint'; data: HintData | null }
  | { action: 'notify'; data: Toast };

type Cb<Req, Res> = { req: Req; res: Res };

/** NUI -> Lua callbacks. Request payload + response `data` type. */
export interface NuiCallbacks {
  ready: Cb<Record<string, never>, null>;
  close: Cb<{ app: AppName }, null>;
  notify: Cb<NotifyRequest, null>;

  'garage:refresh': Cb<Record<string, never>, GarageOpenData>;
  'garage:drive': Cb<{ plate: string }, null>;
  'garage:spawner': Cb<{ index: number }, null>;
  'garage:favourite': Cb<{ plate: string; value: boolean }, null>;
  'garage:rename': Cb<{ plate: string; name: string | null }, null>;
  'garage:transferOptions': Cb<{ plate: string }, TransferOptions>;
  'garage:transfer': Cb<{ plate: string; type: 'garage' | 'player'; target: string | number }, null>;
  'garage:shares': Cb<{ plate: string }, ShareData>;
  'garage:share': Cb<{ plate: string; serverId: number }, ShareData>;
  'garage:unshare': Cb<{ plate: string; identifier: string }, ShareData>;
  'garage:sell': Cb<{ plate: string; serverId: number; price: number }, null>;
  'garage:track': Cb<{ plate: string }, null>;
  'garage:recover': Cb<{ plate: string }, null>;
  'garage:payFinance': Cb<{ plate: string; full: boolean }, Finance | null>;
  'garage:goInside': Cb<Record<string, never>, null>;
  'garage:directions': Cb<Record<string, never>, null>;
  'garage:members': Cb<Record<string, never>, MemberData>;
  'garage:memberAdd': Cb<{ serverId: number; role: Role }, MemberData>;
  'garage:memberRole': Cb<{ identifier: string; role: Role }, MemberData>;
  'garage:memberRemove': Cb<{ identifier: string }, MemberData>;
  'garage:sellGarage': Cb<Record<string, never>, null>;
  'garage:switchGroup': Cb<{ groupId: number }, GarageOpenData>;

  'forSale:tour': Cb<{ locationId: number }, null>;
  'forSale:buy': Cb<{ locationId: number }, null>;

  'impound:refresh': Cb<Record<string, never>, ImpoundOpenData>;
  'impound:retrieve': Cb<{ plate: string }, null>;
  'impound:release': Cb<{ plate: string; mode: 'owner' | 'garage' }, ImpoundOpenData>;
  'impoundForm:submit': Cb<{
    plate: string;
    netId: number | null;
    impoundId: number;
    reason: string;
    fee: number;
    hours: number;
    retrievable: boolean;
  }, { impoundName?: string } | null>;

  'setup:livery': Cb<{ index: number }, null>;
  'setup:extra': Cb<{ id: number; enabled: boolean }, null>;
  'setup:drive': Cb<Record<string, never>, null>;

  'interior:page': Cb<{ page: number }, null>;
  'interior:invite': Cb<{ serverId: number }, null>;
  'interior:kick': Cb<{ serverId: number }, null>;
  'interior:players': Cb<Record<string, never>, PlayerOption[]>;
  'interior:leave': Cb<Record<string, never>, null>;

  'creator:pickEntry': Cb<Record<string, never>, { entry: Vec4; gtaInteriorId: number | null; gtaInteriorName: string | null }>;
  'creator:applyProfile': Cb<{ profile: string | null; options: Record<string, string> }, { entry: Vec4 | null }>;
  'creator:addCameraPoint': Cb<Record<string, never>, CameraPoint>;
  'creator:previewCutscene': Cb<{ cutscene: Cutscene }, null>;
  'creator:placeSlot': Cb<{ index: number | null; slot: Vec4 | null }, Vec4 | null>;
  'creator:showSlots': Cb<{ slots: Vec4[] }, null>;
  'creator:pickExit': Cb<Record<string, never>, Vec4>;
  'creator:teleport': Cb<{ coords: Vec3 | Vec4 }, null>;
  'creator:walk': Cb<Record<string, never>, null>;
  'creator:save': Cb<{ interior: Interior }, Interior>;
  'creator:cancel': Cb<Record<string, never>, null>;

  'admin:refresh': Cb<Record<string, never>, AdminOpenData>;
  'admin:location:save': Cb<{ location: Location }, Location>;
  'admin:location:delete': Cb<{ id: number }, null>;
  'admin:location:toggle': Cb<{ id: number; enabled: boolean }, null>;
  'admin:location:teleport': Cb<{ coords: Vec3 | Vec4 }, null>;
  'admin:location:import': Cb<{ source: string; json?: string }, { imported: number; skipped: number }>;
  'admin:points': Cb<
    { kind: 'spawn' | 'open' | 'store'; vehicleType: VehicleType; points: Vec4[] | InteractionPoint[]; model?: string },
    Vec4[] | InteractionPoint[] | null
  >;
  'admin:pickPosition': Cb<Record<string, never>, Vec4>;
  'admin:groups': Cb<{ locationId: number }, GroupInfo[]>;
  'admin:group:save': Cb<{ group: { id?: number; locationId: number; label: string; owner: string } }, GroupInfo>;
  'admin:group:delete': Cb<{ id: number }, null>;
  'admin:group:member': Cb<{ groupId: number; identifier: string; role: Role | null }, GroupInfo>;
  'admin:interior:create': Cb<{ name: string; profile: string | null; coords: Vec3 | null }, null>;
  'admin:interior:edit': Cb<{ id: number }, null>;
  'admin:interior:delete': Cb<{ id: number }, null>;
  'admin:interior:toggle': Cb<{ id: number; enabled: boolean }, null>;
  'admin:settings:save': Cb<{ settings: Settings }, Settings>;
  'admin:players:search': Cb<{ query: string; page: number }, Paged<PlayerSearchRow>>;
  'admin:players:vehicles': Cb<
    { identifier: string },
    { player: { identifier: string; name: string; online: boolean }; vehicles: AdminVehicleRow[] }
  >;
  'admin:vehicle:get': Cb<{ plate: string }, AdminVehicleDetail>;
  'admin:vehicle:assign': Cb<{ identifier: string; model: string; plate: string; garageKey: string }, AdminVehicleRow>;
  'admin:vehicle:update': Cb<{ plate: string; patch: AdminVehiclePatch }, AdminVehicleDetail>;
  'admin:vehicle:delete': Cb<{ plate: string }, null>;
  'admin:vehicle:activity': Cb<{ plate: string; page: number }, Paged<VehicleActivity>>;

  'keys:refresh': Cb<Record<string, never>, KeysOpenData>;
  'keys:lock': Cb<{ plate: string }, { locked: boolean }>;
  'keys:locate': Cb<{ plate: string }, null>;
  'keys:alarm': Cb<{ plate: string }, null>;
  'keys:share': Cb<{ plate: string; target: number }, null>;
  'keys:holders': Cb<{ plate: string }, KeyHolder[]>;
  'keys:revoke': Cb<{ plate: string; identifier: string }, null>;

  'locksmith:service': Cb<{ locksmithId: number; service: LocksmithServiceId; plate: string }, { message: string }>;

  'contract:send': Cb<{ plate: string; buyer: number; price: number; terms: string; signature: Signature }, { contractId: string }>;
  'contract:sign': Cb<{ contractId: string; signature: Signature }, null>;
  'contract:decline': Cb<{ contractId: string }, null>;
}

export type NuiCallbackName = keyof NuiCallbacks;
