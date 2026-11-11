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
/** Horizontal point of a garage zone (world x / y). */
export interface ZonePoint { x: number; y: number }
/**
 * Garage zone: a polygon (3–40 corners, edges never cross) and a height range, drawn in the
 * world by an admin. Inside it players open the garage and store the vehicle they drive
 * anywhere (no store circle). Validated by the server: area 10–40 000 m², at most 250 m
 * across, 2–100 m high, at most 30 m from an open interaction.
 */
export interface LocationZone { points: ZonePoint[]; minZ: number; maxZ: number }
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
  /** Optional garage zone (absent / null = point-based location). */
  zone?: LocationZone | null;
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
  /** unix seconds the next payment is due (wall clock) */
  nextPaymentAt?: number | null;
  /** payments missed so far on this plan */
  missed?: number;
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
  /** Bumped by Lua ('update') when the 3D preview ended on its own (death, …): show the image. */
  previewStopped?: number;
}

/* ── 3D vehicle preview (client/preview.lua) ── */

/** Stage box the preview car is framed in: CSS px of a vw × vh viewport. */
export interface PreviewRect { x: number; y: number; w: number; h: number; vw: number; vh: number; dpr: number }
/** Owned / impounded vehicle by plate, spawner vehicle by index; neither = stop the preview. */
export interface PreviewRequest { app: 'garage' | 'impound'; plate?: string; index?: number; rect?: PreviewRect }
/** shown: the car is on screen (stage goes transparent); disabled: preview turned off; stale: superseded. */
export interface PreviewResult { shown: boolean; disabled?: boolean; stale?: boolean }

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
  /** See GarageOpenData.previewStopped. */
  previewStopped?: number;
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
  /** Interior, on foot next to a display vehicle: draw the vehicle card floating above the car
   *  at this screen point (x / y = 0-1 of the viewport, scale = 0.82-1, smaller further away)
   *  instead of the seated stats HUD. Lua re-sends it while the car moves on screen. */
  anchor?: HudAnchor | null;
}

export interface HudAnchor { x: number; y: number; scale: number }

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

export type SetupModId = 'engine' | 'brakes' | 'transmission' | 'suspension' | 'armour' | 'turbo';
/** A performance mod as fitted: level 0 = stock, max = levels the model offers (turbo: 0/1). */
export interface SetupMod { id: SetupModId; level: number; max: number }
/** Orbit camera presets of the setup menu ('reset' = the opening view). */
export type SetupView = 'reset' | 'front' | 'rear' | 'side' | 'top';

export interface SetupData {
  label: string;
  liveries: { index: number; label: string }[];
  livery: number;
  extras: { id: number; enabled: boolean }[];
  /* Detail (all optional, read on the client when the menu opens). */
  /** Spawn name, e.g. 'police3'. */
  model?: string;
  /** Plate on the vehicle. */
  plate?: string;
  /** Spawner plate template ('#' digit, '@' letter, '*' either); '' = random plate. */
  plateTemplate?: string;
  /** Garage the vehicle came from. */
  garage?: string;
  /** 'livery' = livery natives, 'mod' = livery mod kit (index -1 = default), null = none. */
  liveryMode?: 'livery' | 'mod' | null;
  /** The spawner fitted max performance mods. */
  maxMods?: boolean;
  mods?: SetupMod[];
  /** The orbit camera is running (false while another camera is in use). */
  camera?: boolean;
}

/**
 * Orbit camera input of the setup menu. Deltas are added to the camera target (Lua clamps
 * them): yaw / pitch in degrees, zoom in wheel steps (+ = farther). `hold` is the state of the
 * held keys (-1 | 0 | 1 each); Lua drops it when it is not re-sent within a second.
 * `frame` is the menu's top edge as a fraction of the screen height (sent on open / resize):
 * Lua aims the camera so the vehicle sits in the middle of the free space above the menu.
 */
export interface SetupCameraInput {
  yaw?: number;
  pitch?: number;
  zoom?: number;
  hold?: { yaw: number; pitch: number; zoom: number };
  view?: SetupView;
  frame?: number;
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
  /** 3D preview of the selected vehicle in the garage / impound stage (client/preview.lua); default on. */
  vehiclePreview?: boolean;
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
  /** Config.Peds defaults (the location editor's NPC fields); older servers leave it out. */
  peds?: { defaultModel: string; defaultScenario: string };
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

/** How the player holds a key (docs/CARLOCK.md §3): 'owner' = through ownership / a garage share
 *  / fleet access (a virtual key), 'item' / 'fob' = a physical key item, 'temp' = a temporary key,
 *  'virtual' = a persistent key someone gave you. */
export type KeyKind = 'owner' | 'item' | 'fob' | 'temp' | 'virtual';

/** Where a key sits on the ring: your vehicles, keys others shared with you, temporary keys,
 *  key items of vehicles you do not own. */
export type KeyGroup = 'owned' | 'shared' | 'temp' | 'items';

export interface KeyEntry extends VehicleLabel {
  plate: string;
  /** spawn name, '' when unknown */
  model: string;
  /** model hash, 0 when unknown (a temporary key of a vehicle that is not out) */
  hash: number;
  vehicleType: VehicleType;
  nickname: string | null;
  kind: KeyKind;
  group: KeyGroup;
  /** physical key of the vehicle's security profile */
  keyType: 'key' | 'fob';
  /** security profile id and label ('standard' / 'highend' ...) */
  profile: string;
  profileLabel: string;
  /** electronic fob: remote locking from ranges.fob */
  remote: boolean;
  /** temporary keys: seconds left when the data was sent, else null */
  expiresIn: number | null;
  /** how the key was obtained: a temporary key's reason ('hotwire', 'robbery', 'garage',
   *  'locksmith' ...), or the crime origin of a key item ('locksmith' = cut by a back-alley
   *  locksmith, 'search' = spare key found in a vehicle); null for every other key */
  reason: string | null;
  isOwner: boolean;
  /** the vehicle exists in the player's routing bucket */
  spawned: boolean;
  netId: number | null;
  locked: boolean | null;
  /** metres from the player (this client, or the tracker for trackable vehicles), null when unknown */
  distance: number | null;
  /** the security profile carries a tracker */
  tracker: boolean;
  /** the key gives tracker access: false for a crime's key (a temporary key from a hotwire,
   *  a robbery, another script; a back-alley or found key item) unless the server allows it */
  trackerAccess: boolean;
  /** tracker eligible, tracker access and spawned (locate, remote alarm) */
  trackable: boolean;
  /** on the impound tow truck: nothing works */
  towing: boolean;
  /** the alarm sounds right now */
  alarm: boolean;
  /** virtual: give a key to a nearby player (owner); physical: hand the item over */
  canShare: boolean;
  /** key holders (owner, loaded with keys:holders), null = not loaded */
  holders: number | null;
  /** fob artwork: the key's own design, else the admin default (keys.defaultFob); 'key' = a plain key */
  design?: string | null;
  /** immobiliser of the vehicle (server) */
  immobiliser?: ImmobiliserLevel | null;
  /** engine running (this client sees the vehicle), null = unknown */
  engine?: boolean | null;
  /** os.time() this player last used the key / drove the vehicle (this client), null = never */
  usedAt?: number | null;
  /** key items: inventory slot and key id (drop / inspect / give use them) */
  slot?: number | null;
  keyId?: string | null;
}

/** What this client sees itself, pushed every second while the key ring is open. */
export interface KeyLive { distance: number | null; locked: boolean | null; alarm?: boolean; engine?: boolean | null }

/** Live readout of the located vehicle (tracker). */
export interface KeyTracking {
  plate: string;
  distance: number | null;
  /** true: measured on this client; false: the tracker's last server position */
  live: boolean;
  /** the signal is gone (stored, towed, left the routing bucket) */
  lost?: boolean;
  /** the blip stopped following it */
  stopped?: boolean;
  towing?: boolean;
}

export interface KeysOpenData {
  mode: 'physical' | 'virtual';
  keys: KeyEntry[];
  nearbyPlayers: KeyRingPlayer[];
  ranges: { key: number; fob: number; give: number };
  /** the vehicle tracker is switched on */
  tracker: boolean;
  /** plate to select (a fob used far from its vehicle, OpenKeys(plate)) */
  focus?: string | null;
  /** plate of the vehicle the player sits in (false / null: on foot) */
  seatPlate?: string | false | null;
  live?: Record<string, KeyLive> | null;
  tracking?: KeyTracking | null;
  /** the key ring keybind ('F7'): pressing it again while the ring is open closes it */
  closeKey?: string | null;
  /** what the window shows: the key ring, the player's key settings, or one dialog on its own
   *  (a ground key picked up, the Ghost PIN pad, the give keys picker...); default 'ring' */
  view?: KeysView | null;
  /** a dialog over the ring (or alone with view 'dialog'); null clears it */
  dialog?: KeyDialog | null;
  /** key policy (flexible: sharing gives a copy; limited: hands yours over; virtual: access) */
  keyMode?: KeyMode | null;
  /** the player's key ring preferences (PlayerKeySettings.keyOrder / units) */
  prefs?: { keyOrder: PlayerKeySettings['keyOrder']; units: PlayerKeySettings['units'] } | null;
}

export type KeysView = 'ring' | 'settings' | 'dialog';

/** Dialogs of the keys app (docs/V2_CHANGES.md G.5 / G.8 / G.10). */
export type KeyDialog =
  /** a key on the ground (held for 20 s by the server): Keep (keys:groundKeep) / Return (keys:groundReturn) */
  | { kind: 'inspect'; source: 'ground'; id: string; info: KeyInspectInfo }
  /** a key the player carries (nz:carlock:inspect) */
  | { kind: 'inspect'; source: 'carried'; info: KeyInspectInfo }
  /** give keys picker of one key (keys:players / keys:share) */
  | { kind: 'give'; plate: string }
  /** the Ghost immobiliser keypad */
  | { kind: 'pin'; pad: KeyPinPad }
  /** track vehicle modal (keys:track) */
  | { kind: 'track'; plate: string };

/** A key looked at up close (ground key or carried key), vehicle name enriched from `hash`. */
export interface KeyInspectInfo extends VehicleLabel {
  plate: string;
  keyKind: 'key' | 'fob';
  /** the key's own name (its item label) */
  keyLabel: string;
  /** spawn name, null when unknown */
  model: string | null;
  hash: number;
  design: string;
  /** 'temp' = a robbed driver's key on the ground (picking it up gives a temporary key) */
  kind: 'item' | 'temp';
  /** carried keys: fits the current locks (null = not checked: ground keys) */
  valid?: boolean | null;
  reason?: CarriedKeyInfo['reason'];
  /** crime origin of a carried key item ('locksmith' | 'search'), else null */
  origin?: string | null;
  /** ground keys: seconds since it was dropped */
  droppedAgo?: number | null;
}

/** Ghost immobiliser keypad. enter: the driver's PIN (keys:pinEnter, the pad shows the
 *  server's answer); set: the owner sets / changes the PIN (keys:pinSet, the current PIN first
 *  when pinSet); collect: digits returned to Lua (CarLock.pinPrompt). keys:pinDone closes it. */
export interface KeyPinPad {
  /** session id: answers of an older pad are ignored */
  id: number;
  mode: 'enter' | 'set' | 'collect';
  plate: string;
  /** vehicle name when known */
  vehicle?: string | null;
  attemptsLeft?: number | null;
  /** seconds of the wrong-PIN cooldown left */
  cooldown?: number | null;
  /** set: a PIN exists (the current PIN is asked first) */
  pinSet?: boolean;
  length: number;
}

/** keys:track { plate }: the track vehicle modal (polled every few seconds while open).
 *  Positions only for trackable vehicles (tracker fitted, tracker access, out, not towed). */
export interface KeyTrackData extends VehicleLabel {
  plate: string;
  model: string;
  hash: number;
  nickname: string | null;
  profileLabel: string;
  tracker: boolean;
  trackerAccess: boolean;
  trackable: boolean;
  spawned: boolean;
  towing: boolean;
  coords: { x: number; y: number; z: number } | null;
  /** degrees (GTA heading: 0 = north, counter-clockwise), null when unknown */
  heading: number | null;
  street: string | null;
  area: string | null;
  /** metres from the player */
  distance: number | null;
  /** measured on this client (vehicle in scope), else the tracker's server position */
  live: boolean;
  locked: boolean | null;
  engine: boolean | null;
  alarm: boolean;
  immobiliser: ImmobiliserLevel;
  /** the player's own position (the "you" marker) */
  me: { x: number; y: number } | null;
  /** why there is no position */
  reason: 'notracker' | 'noaccess' | 'notout' | 'towing' | 'disabled' | null;
}

/** keys:remote: hold = engine, keep holding = windows (nz:carlock:remote, fob only). */
export interface KeyRemoteAnswer {
  action: 'engine' | 'windows';
  on: boolean;
  plate: string;
  /** out of the fob's range: the server's words in message */
  refused?: 'range' | null;
  message?: string | null;
}

/** A nearby player for the share picker (server distance in metres). anonymous: the server
 *  does not send character names (Config.CarLock.sharePicker.names): name = 'Player <id>'. */
export interface KeyRingPlayer extends PlayerOption { distance?: number; anonymous?: boolean }

export interface KeyHolder {
  /** opaque id from the server (identifiers never reach the interface); revoke with it */
  id: string;
  /** character name, or 'Unknown holder' when masked */
  name: string;
  kind: 'virtual' | 'temp';
  /** temporary keys: how it was obtained ('hotwire', 'robbery', 'garage'...), else null */
  reason: string | null;
  /** a temporary key that is not a service's (a crime, another script): the name is not shown */
  masked: boolean;
  /** seconds since the key was given (server clock), null when unknown */
  agoSeconds: number | null;
  /** temporary keys: seconds left */
  expiresIn: number | null;
}

export type LocksmithServiceId = 'duplicate' | 'program' | 'rekey';

export interface LocksmithMaterial { item: string; label: string; count: number; have: number }

export interface LocksmithService {
  id: LocksmithServiceId;
  /** offered at this location (config) */
  enabled: boolean;
  /** available in this key mode (virtual: no duplicate; no program at a legal shop) */
  offered: boolean;
  reason?: string | null;
  price: number;
  materials: LocksmithMaterial[];
}

export interface LocksmithVehicle extends VehicleLabel {
  plate: string;
  model?: string | null;
  hash?: number | null;
  vehicleType: VehicleType;
  nickname?: string | null;
  isOwner: boolean;
  /** a row in the vehicle table (a player's vehicle) */
  owned: boolean;
  hasKey: boolean;
  keyKind?: 'owner' | 'item' | 'temp' | 'virtual' | null;
  /** valid key items of this plate the player carries */
  keyItems: number;
  /** every key item carried is a crime's (back-alley copy, found key): opens the vehicle, but
   *  a legal shop never programs a registered key from it */
  unregistered?: boolean;
  /** what a key cut for it is */
  keyType: 'key' | 'fob';
  /** within range of the locksmith (program / rekey need the vehicle nearby) */
  nearby: boolean;
  /** metres from the locksmith */
  distance?: number | null;
  towing: boolean;
  /** per service: why it is not possible (translated); missing = available */
  blocked: Partial<Record<LocksmithServiceId, string>>;
}

export interface LocksmithOpenData {
  id: number;
  name: string;
  illegal: boolean;
  account: 'cash' | 'bank';
  mode: 'physical' | 'virtual';
  /** balance of `account` */
  money: number;
  /** temporary key lifetime (virtual program) */
  tempHours: number;
  /** metres: vehicles this close to the locksmith count as nearby */
  range: number;
  services: LocksmithService[];
  vehicles: LocksmithVehicle[];
}

/* ───────────── car lock v2 (docs/CARLOCK.md §15-§19): data of the server callbacks ─────────────
 * Server callbacks (lib.callback, { ok, data, error }) the coming screens forward to; the
 * Lua names are given on each type. Nothing here is a NuiCallbacks entry yet (the UI wave adds
 * the NUI names together with their client handlers). */

/** Key policy (Config.CarLock.keyMode / admin setting keys.mode). */
export type KeyMode = 'flexible' | 'limited' | 'virtual';
/** Immobiliser of a vehicle: standard blocks hotwiring, ghost also asks for a 4-digit PIN. */
export type ImmobiliserLevel = 'none' | 'standard' | 'ghost';

/** nz:carlock:immobiliser { plate } / nz:carlock:setPin { plate, pin, oldPin? } */
export interface ImmobiliserInfo {
  plate: string;
  level: ImmobiliserLevel;
  /** a Ghost PIN is set (no PIN yet: the Ghost acts like a standard immobiliser) */
  pinSet: boolean;
  /** this player still has to enter the PIN before the engine starts */
  pinRequired: boolean;
  /** seconds left of the wrong-PIN cooldown (0 = none) */
  cooldown: number;
  /** false with a Ghost immobiliser */
  remoteStart: boolean;
}

/** nz:carlock:pin { netId, pin } (driver seat) */
export interface PinResult {
  success: boolean;
  error?: string;
  attemptsLeft?: number;
  /** seconds of the cooldown after too many wrong PINs */
  cooldown?: number;
  /** the alarm went off */
  alarm?: boolean;
}

/** Server pin info in nz:carlock:hasKey / nz:carlock:engine answers (Ghost PIN missing). */
export interface PinRequest { required: true; cooldown: number; plate: string }

/** Per-player key settings (nz:carlock:playerSettings {} / nz:carlock:savePlayerSettings
 *  { settings: Partial<PlayerKeySettings> }). */
export interface PlayerKeySettings {
  keylessUnlock: boolean;
  keylessLock: boolean;
  /** metres, within PlayerKeySettingsData.limits */
  keylessDistance: number;
  engineOnEnter: boolean;
  keepEngineRunning: boolean;
  /** the fob beep only this player hears (the click animation always plays) */
  fobBeep: boolean;
  hints: boolean;
  /** fob HUD: share of the screen (0-1) and scale (0.5-2) */
  fobPosition: { x: number; y: number; scale: number };
  keyOrder: 'recent' | 'name' | 'plate' | 'distance';
  combinedKeyring: boolean;
  groundPrompts: boolean;
  units: 'metric' | 'imperial';
  alertLock: boolean;
  /** engine started on entering / remotely (a manual toggle never notifies) */
  alertEngine: boolean;
  alertShare: boolean;
  /** on character load: which owned vehicles still have keys out with other players */
  shareRecall: boolean;
}

export interface PlayerKeySettingsData {
  settings: PlayerKeySettings;
  defaults: PlayerKeySettings;
  limits: { keylessMin: number; keylessMax: number };
  /** what the server allows (admin settings) */
  server: { keyless: boolean; keepEngineRunning: boolean; ground: boolean };
}

export type KeySettingsTab = 'keys' | 'ground' | 'vehicles' | 'lockpicking' | 'hotwiring' | 'npc' | 'jobs' | 'security';
export type KeySettingType = 'bool' | 'number' | 'enum' | 'color' | 'classes' | 'models' | 'strings';
export type KeySettingValue = boolean | number | string | number[] | string[];

/** One admin key setting (schema: shared/carlock.lua; labels translated by the server). */
export interface KeySetting {
  /** e.g. 'keys.mode', 'ground.removeAfter', 'npc.drop' */
  id: string;
  tab: KeySettingsTab;
  type: KeySettingType;
  label: string;
  description: string;
  /** the value in use (admin value, else the config file's) */
  value: KeySettingValue;
  /** the config file's value */
  default: KeySettingValue;
  /** an admin value is stored */
  overridden: boolean;
  options?: string[];
  min?: number;
  max?: number;
  step?: number;
  integer?: boolean;
  /** colour settings: the server also accepts an opacity ('#rrggbbaa'); without it the
   *  picker only edits '#rrggbb' */
  alpha?: boolean;
}

/** nz:carlock:admin:settings {} and nz:carlock:admin:saveSettings
 *  { values: Record<id, value>, reset?: id[] } (admin only; all or nothing). */
export interface KeySettings {
  tabs: { id: KeySettingsTab; label: string }[];
  settings: KeySetting[];
}

/** nz:carlock:ground:list {} (keys on the ground in the player's routing bucket); also pushed
 *  to clients as 'nz:client:carlock:ground' { add } | { remove }. */
export interface GroundKey {
  id: string;
  keyKind: 'key' | 'fob';
  x: number;
  y: number;
  z: number;
  /** network id of the prop when it exists */
  netId?: number | null;
}

/** nz:carlock:ground:inspect { id } (held for the inspector for 20 s; keep with
 *  nz:carlock:ground:pickup { id }, return with nz:carlock:ground:release { id }). */
export interface GroundKeyInfo {
  id: string;
  plate: string;
  keyKind: 'key' | 'fob';
  /** 'item' = a key item; 'temp' = a robbed NPC's key (picking it up gives a temporary key) */
  kind: 'item' | 'temp';
  label: string;
  model: string | null;
  /** os.time() when it was dropped */
  droppedAt: number;
}

/** nz:carlock:inspect { slot } | { keyId, plate } (a key the player carries). */
export interface CarriedKeyInfo {
  plate: string;
  keyKind: 'key' | 'fob';
  label: string;
  model: string | null;
  /** fits the current locks */
  valid: boolean;
  reason?: 'invalid' | 'plate' | 'version' | 'error' | null;
  /** crime origin ('locksmith' | 'search'), null for a registered key */
  origin: string | null;
  slot: number | null;
  keyId: string | null;
}

/** Where a key is (admin key manager). */
export interface KeyCustody {
  kind: 'inventory' | 'stash' | 'ground' | 'server' | 'unknown' | 'lost' | 'flight';
  slot?: number | null;
  /** 'glovebox:PLATE' | 'trunk:PLATE' | '<type>:<id>' (ox_inventory reports these) */
  stash?: string | null;
  groundId?: string | null;
}

export interface KeyAdminPlayer {
  identifier: string;
  name: string;
  online: boolean;
  serverId?: number | null;
  matchedPlates: string[];
}

/** One key of a player in the admin key manager (nz:carlock:admin:player { identifier }). */
export interface KeyAdminRow {
  /** 'owner:PLATE' | 'share:PLATE' | 'virtual:PLATE' | 'temp:PLATE' | 'item:PLATE:KEYID' |
   *  'ground:ID'; delete with nz:carlock:admin:delete { identifier, id } */
  id: string;
  plate: string;
  model?: string | null;
  type: 'key' | 'fob' | 'virtual' | 'temp' | 'owner';
  /** 'owner' | 'share' | 'virtual' | a temporary key reason | a key item origin | 'key' */
  origin: string;
  custody: KeyCustody;
  spawned: boolean;
  netId?: number | null;
  /** metres from the player (online), null when unknown */
  distance?: number | null;
  /** temporary keys: os.time() when it ends */
  expires?: number | null;
  /** key items: cut for the current locks */
  current?: boolean;
  shared?: 'in' | 'out';
  deletable: boolean;
  /** added by the client (client/carlock/keyadmin.lua): model hash, display label and make
   *  (GetMakeNameFromVehicleModel) when the model is known */
  hash?: number | null;
  label?: string | null;
  make?: string | null;
}

export interface KeyAdminTotals { keys: number; vehicles: number; sharedIn: number; sharedOut: number }

/** nz:carlock:admin:player, :give { identifier, plate, type: 'item'|'temp'|'virtual',
 *  keyKind?, hours? } and :delete answer with this. */
export interface KeyAdminPlayerData {
  player: Omit<KeyAdminPlayer, 'matchedPlates'>;
  keys: KeyAdminRow[];
  totals: KeyAdminTotals;
}

/** nz:carlock:admin:search { query } (name, citizen id, plate or server id). */
export interface KeyAdminSearch { rows: KeyAdminPlayer[] }

/** nz:carlock:admin:plate { plate }: every key of one vehicle. */
export interface KeyAdminPlateData {
  plate: string;
  owned: boolean;
  owner: string | null;
  ownerName: string | null;
  model: string | null;
  /** current key version (nil: database unreadable) */
  version: number | null;
  /** copies of the current locks that exist somewhere (limited mode) */
  live: number | null;
  immobiliser: { level: ImmobiliserLevel; pinSet: boolean };
  spawned: boolean;
  netId: number | null;
  distance: number | null;
  custody: { id: string; type: 'key' | 'fob'; origin: string; current: boolean; custody: KeyCustody; holder?: string | null; holderName?: string | null }[];
  holders: { identifier: string; name: string; type: 'virtual' | 'temp'; origin?: string | null; expires?: number | null }[];
  ground: { id: string; plate: string; kind: 'item' | 'temp'; keyKind: 'key' | 'fob'; coords: { x: number; y: number; z: number }; bucket: number; droppedBy?: string | null; createdAt: number; expiresAt?: number | null }[];
  /** added by the client: display label and make of `model` */
  label?: string | null;
  make?: string | null;
}

/** nz:carlock:admin:track { plate } */
export interface KeyAdminTrack { plate: string; spawned: boolean; bucket?: number; coords?: { x: number; y: number; z: number }; distance?: number | null }

/** Admin key manager window ('keyadmin' app, /vehiclekeysadmin → CarLock.openKeyAdmin(opts)).
 *  Every field is optional: page / settingsTab pick the start page, identifier opens a player,
 *  plate opens the plate view, query runs a search. */
export interface KeyAdminOpenData {
  page?: 'keys' | 'settings';
  settingsTab?: KeySettingsTab | null;
  identifier?: string | null;
  plate?: string | null;
  query?: string | null;
  /** Config.CarLock.fob.defaultDesign (fob renders of key items) */
  fobDesign?: string | null;
  /** Config.CarLock.tempKeyHours (default of a temporary key in the give dialog) */
  tempKeyHours?: number | null;
  /** NZ.CarLock.keyMode() */
  keyMode?: KeyMode | null;
}

/** keyadmin:give request (nz:carlock:admin:give) */
export interface KeyAdminGive {
  identifier: string;
  plate: string;
  type: 'item' | 'temp' | 'virtual';
  keyKind?: 'key' | 'fob';
  hours?: number;
}

/** nz:carlock:remote { netId? | plate?, action, on? } (fob only; Ghost: no remote start). */
export interface RemoteResult { action: 'engine' | 'windows'; on: boolean; netId: number; plate: string }

/** The NUI minigames a client can play: sent as `minigames` with every lockpick / hotwire
 *  start. The server only hands out 'pins' / 'wires' / 'reader' to a client that lists them,
 *  else skill checks (lockpick) / the profile's method (hotwire). */
export interface MinigameSupport { pins?: boolean; wires?: boolean; reader?: boolean }

/** Lockpick / hotwire minigame puzzles (nz:carlock:lockpick / hotwire start answers);
 *  finish with { id, success, answer, snapped? }. Skill-gated, not cheat-proof: the client gets
 *  what it needs to draw the puzzle; the server checks the answer and the minimum play time. */
export interface PinsPuzzle { pins: number; order: number[]; heights: number[] }
export interface WiresPuzzle { left: string[]; right: string[] }
export interface ReaderPuzzle { frequency: number; phase: number; tolerance: { frequency: number; phase: number } }

/* ── minigame app (client/carlock/minigame.lua, docs/V2_CHANGES.md G.6 / G.7) ── */

export type MinigameGame = 'pins' | 'wires' | 'reader';

interface MinigameBase {
  /** Lua's id of this play: echoed by minigame:started / minigame:finish */
  token: number;
  /** seconds the player has before Lua ends the attempt (the server session is shorter than 90 s) */
  timeLimit: number;
  /** display only: vehicle name and plate text */
  vehicle?: { label?: string | null; plate?: string | null } | null;
}

/** Where the lock is drawn: the door handle on screen (shares of the screen, 0..1); null = centred. */
export interface MinigameAnchor { x: number; y: number }

export type MinigameOpenData =
  | (MinigameBase & {
      game: 'pins';
      puzzle: PinsPuzzle;
      /** % chance an overset pin snaps the pick (the server rolls it) */
      snapChance: number;
      anchor?: MinigameAnchor | null;
      /** the tool's item label */
      tool?: string | null;
    })
  | (MinigameBase & { game: 'wires'; puzzle: WiresPuzzle })
  | (MinigameBase & { game: 'reader'; puzzle: ReaderPuzzle });

/** Lua -> NUI 'update' while a lock is open: the door handle moved on screen. */
export interface MinigameUpdate { anchor?: MinigameAnchor | null }

/** pins: the pin numbers in the order they were set; wires: answer[i] = right position (1-3) of
 *  left wire i; reader: the tuned signal. */
export type MinigameAnswer = number[] | { frequency: number; phase: number };

export interface MinigameFinish {
  token: number;
  success: boolean;
  answer?: MinigameAnswer | null;
  /** pins: a pin was overset (too far / too fast): the server rolls snapChance for the pick */
  snapped?: boolean;
  /** Esc / Close: the player gave up */
  cancelled?: boolean;
}

export interface ContractVehicle extends VehicleLabel {
  plate: string;
  model: string;
  hash: number;
  vehicleType: VehicleType;
  nickname?: string | null;
  /** kilometres */
  mileage: number;
  /** percent 0-100 */
  engine: number;
  body: number;
  /** draft: metres from the seller (server measured) */
  distance?: number | null;
  /** draft: why this vehicle cannot be sold right now (translated); absent when it can */
  blocked?: string | null;
}

export interface ContractParty { name: string; serverId?: number }

/** Signature = SVG path data ("M x y L x y ..."), at most 4000 characters, in a 400x140 box. */
export type Signature = string;

/** Outcome of a sent contract, pushed into the open window ('update' { status }). */
export type ContractStatus = 'pending' | 'signed' | 'declined' | 'expired' | 'withdrawn' | 'cancelled' | 'failed';

/** How the buyer got the keys: a key item (physical car lock), a temporary key, the keys of
 *  an external key resource; null = no key system. */
export type ContractKeyKind = 'item' | 'temp' | 'external';

/** A contract the seller already sent (the draft reopened by using a blank contract again). */
export interface ContractSent {
  id: string;
  /** seconds left to sign (count down from receipt) */
  expiresIn: number;
  buyer: PlayerOption;
  plate: string;
  price: number;
  terms: string;
  signature: Signature;
}

/** The seller drafts a contract (blank contract item used next to their vehicle). */
export interface ContractDraftData {
  mode: 'draft';
  seller: ContractParty;
  vehicles: ContractVehicle[];
  buyers: PlayerOption[];
  maxPrice: number;
  /** the buyer pays from / the seller is paid into */
  account: 'bank' | 'cash';
  /** seconds the buyer has to sign once the contract is sent */
  expireSeconds: number;
  /** the seller's contract still waiting for the buyer: the window opens in its sent state */
  sent?: ContractSent | null;
  /** set by Lua after sending (outcome of the sent contract) */
  status?: ContractStatus;
  /** with status 'signed': the seller's signed copy is in their inventory */
  copy?: boolean;
  /** with status 'declined' / 'expired': seconds before this buyer can get a new contract from
   *  the seller (Config.Contracts.resendCooldown, counted from receipt); another buyer can now */
  resendIn?: number | null;
}

/** The buyer reads, signs and pays. */
export interface ContractReviewData {
  mode: 'review';
  contractId: string;
  vehicle: ContractVehicle;
  seller: ContractParty;
  buyer: ContractParty;
  price: number;
  terms: string;
  sellerSignature: Signature;
  /** unix seconds (server) */
  createdAt: number;
  /** seconds left to sign when the message was sent (count down from receipt: no clock skew) */
  expiresIn: number;
  canAfford: boolean;
  account: 'bank' | 'cash';
  status?: ContractStatus;
}

/** A signed copy (signed_contract item), read-only. */
export interface ContractViewData {
  mode: 'view';
  contractId: string;
  /** whose copy this item is */
  copy?: 'seller' | 'buyer' | null;
  vehicle: ContractVehicle;
  seller: ContractParty;
  buyer: ContractParty;
  price: number;
  account?: 'bank' | 'cash';
  terms: string;
  sellerSignature: Signature;
  buyerSignature: Signature;
  createdAt?: number;
  /** unix seconds */
  signedAt: number;
  /** the ownership history of the plate holds this contract */
  verified: boolean;
}

export type ContractOpenData = ContractDraftData | ContractReviewData | ContractViewData;

/* ───────────── fob HUD (docs/V2_CHANGES.md G.4 / G.5): the 'fob' app, client/carlock/fob.lua ───────────── */

export type FobButtonName = 'lock' | 'unlock' | 'trunk' | 'panic';

/** The key drawn on the HUD. */
export interface FobHudKey {
  plate: string;
  /** vehicle name ('Dinka Jester'), else the key's label */
  label: string;
  /** vehicle make for the brand badge (translated label or GTA make key), '' when unknown */
  make: string;
  /** FobArt design ('classic', 'sport' … or 'key') */
  design: string;
  kind: 'key' | 'fob';
  locked?: boolean | null;
}

/** HUD placement: centre of the fob as a share of the screen (0-1) and its scale (0.5-2);
 *  PlayerKeySettings.fobPosition. */
export interface FobLayout { x: number; y: number; scale: number }

/** Current keys of the side prompts (rebindable key mappings; ESC always closes). */
export interface FobKeyBinds { throw: string; inspect: string; move: string; help: string; close: string }

/** A button press to animate; seq changes with every press. beep: the NUI plays the fob beep
 *  (presses the game does not beep for itself, player setting fobBeep). */
export interface FobPress { button: FobButtonName; seq: number; beep: boolean }

/** Inspect card: a key on the ground (server nz:carlock:ground:inspect) or one you carry
 *  (nz:carlock:inspect). Everything comes from the server's answer. */
export interface FobInspect {
  source: 'ground' | 'carried';
  /** ground key id (Keep / Return to ground) */
  id?: string | null;
  plate: string;
  /** vehicle name ('' when the server does not know the model) */
  vehicle: string;
  /** the key's own label ('Vehicle key ABC123') */
  keyLabel: string;
  make: string;
  design: string;
  kind: 'key' | 'fob';
  /** carried: cut for the current locks */
  valid?: boolean | null;
  /** ground: an NPC's key (picking it up gives a temporary key) */
  temp?: boolean;
  /** ground: seconds since it was dropped (server clock) */
  droppedAgo?: number | null;
  /** carried: crime origin ('locksmith' | 'search'), null for a registered key */
  origin?: string | null;
}

/** hud: no focus, the fob on screen · edit: move / resize (focus) · help · inspect (focus) */
export type FobMode = 'hud' | 'edit' | 'help' | 'inspect';

export interface FobHudData {
  mode: FobMode;
  key: FobHudKey | null;
  layout: FobLayout;
  /** the configured default layout (Reset) */
  defaults: FobLayout;
  /** the key is in the player's hand: the side prompts work */
  holding: boolean;
  keys: FobKeyBinds;
  press?: FobPress | null;
  inspect?: FobInspect | null;
}

/* ───────────────────────── NUI protocol ───────────────────────── */

export type AppName = 'garage' | 'impound' | 'impoundForm' | 'forSale' | 'admin' | 'creator' | 'setup' | 'interior'
  | 'keys' | 'locksmith' | 'contract' | 'fob' | 'minigame' | 'keyadmin';

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
  /** on-screen key fob HUD, edit mode, help and the key inspect card */
  fob: FobHudData;
  /** lockpick / hotwire / reader minigames */
  minigame: MinigameOpenData;
  /** admin key manager + admin key settings */
  keyadmin: KeyAdminOpenData;
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
  'garage:preview': Cb<PreviewRequest, PreviewResult>;
  'garage:previewRect': Cb<PreviewRect, null>;

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
  'setup:camera': Cb<SetupCameraInput, null>;

  'interior:page': Cb<{ page: number }, null>;
  'interior:invite': Cb<{ serverId: number }, null>;
  'interior:kick': Cb<{ serverId: number }, null>;
  'interior:players': Cb<Record<string, never>, PlayerOption[]>;
  'interior:leave': Cb<Record<string, never>, null>;

  'creator:pickEntry': Cb<Record<string, never>, { entry: Vec4; gtaInteriorId: number | null; gtaInteriorName: string | null }>;
  /** `slots`: the profile's preset vehicle positions, sent when the draft had none yet. */
  'creator:applyProfile': Cb<{ profile: string | null; options: Record<string, string> }, { entry: Vec4 | null; slots?: Vec4[] | null }>;
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
  /** kind 'zone': the in-world zone tool (null = cancelled; the server validates on save). */
  'admin:points': Cb<
    | { kind: 'spawn' | 'open' | 'store'; vehicleType: VehicleType; points: Vec4[] | InteractionPoint[]; model?: string }
    | { kind: 'zone'; vehicleType: VehicleType; zone: LocationZone | null; openPoints: InteractionPoint[]; spawnPoints: Vec4[] },
    Vec4[] | InteractionPoint[] | LocationZone | null
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
  /** refused = 'range': the server's out-of-range answer (message = its words), locked absent */
  'keys:lock': Cb<{ plate: string }, { plate: string; locked?: boolean; refused?: 'range' | null; message?: string | null }>;
  'keys:locate': Cb<{ plate: string; stop?: boolean }, { distance: number | null }>;
  /** refused = 'cooldown': not yet, cooldown = seconds left (message = the server's words) */
  'keys:alarm': Cb<
    { plate: string; on?: boolean },
    { alarm: boolean; seconds: number | null; cooldown: number; refused?: 'cooldown' | null; message?: string | null }
  >;
  'keys:players': Cb<Record<string, never>, KeyRingPlayer[]>;
  'keys:share': Cb<{ plate: string; target: number }, null>;
  'keys:holders': Cb<{ plate: string }, KeyHolder[]>;
  'keys:revoke': Cb<{ plate: string; id: string }, KeyHolder[]>;
  /** hold = engine (on), keep holding = windows (on = down) */
  'keys:remote': Cb<{ plate: string; action: 'engine' | 'windows'; on: boolean }, KeyRemoteAnswer>;
  'keys:track': Cb<{ plate: string }, KeyTrackData>;
  /** a key item of the ring up close (nz:carlock:inspect by its slot / key id) */
  'keys:inspect': Cb<{ plate: string }, KeyInspectInfo>;
  /** drop a key item at your feet (nz:carlock:ground:drop) */
  'keys:drop': Cb<{ plate: string }, { plate: string }>;
  /** give back a virtual / temporary key someone gave you (nz:carlock:leaveKey) */
  'keys:leave': Cb<{ plate: string }, null>;
  'keys:groundKeep': Cb<{ id: string }, { plate: string }>;
  'keys:groundReturn': Cb<{ id: string }, null>;
  'keys:settings': Cb<Record<string, never>, PlayerKeySettingsData>;
  'keys:saveSettings': Cb<{ settings: Partial<PlayerKeySettings> }, PlayerKeySettingsData>;
  'keys:immobiliser': Cb<{ plate: string }, ImmobiliserInfo>;
  /** the open 'enter' pad: the driver's PIN for the vehicle Lua asked about */
  'keys:pinEnter': Cb<{ id: number; pin: string }, PinResult>;
  'keys:pinSet': Cb<{ plate: string; pin: string; oldPin?: string | null }, ImmobiliserInfo>;
  /** the pad closed: success (enter / set) or the digits (collect), nothing = cancelled */
  'keys:pinDone': Cb<{ id: number; pin?: string | null; success?: boolean }, null>;

  /** admin key manager (client/carlock/keyadmin.lua → nz:carlock:admin:*; admin only) */
  'keyadmin:search': Cb<{ query: string }, KeyAdminSearch>;
  'keyadmin:player': Cb<{ identifier: string }, KeyAdminPlayerData>;
  'keyadmin:give': Cb<KeyAdminGive, KeyAdminPlayerData>;
  'keyadmin:delete': Cb<{ identifier: string; id: string }, KeyAdminPlayerData>;
  'keyadmin:plate': Cb<{ plate: string }, KeyAdminPlateData>;
  'keyadmin:track': Cb<{ plate: string }, KeyAdminTrack>;
  /** asks the server where the vehicle is and sets the map waypoint there */
  'keyadmin:waypoint': Cb<{ plate: string }, KeyAdminTrack>;
  'keyadmin:settings': Cb<Record<string, never>, KeySettings>;
  'keyadmin:saveSettings': Cb<{ values: Record<string, KeySettingValue>; reset?: string[] }, KeySettings>;

  'locksmith:refresh': Cb<{ locksmithId: number }, LocksmithOpenData>;
  'locksmith:service': Cb<{ locksmithId: number; service: LocksmithServiceId; plate: string }, { message: string; data: LocksmithOpenData }>;

  /** the minigame screens loaded: Lua offers the NUI minigames to the server from now on */
  'minigame:ready': Cb<Record<string, never>, null>;
  /** the game of `token` is on screen (ok = false: it cannot be drawn, e.g. no WebGL) */
  'minigame:started': Cb<{ token: number; ok: boolean }, null>;
  'minigame:finish': Cb<MinigameFinish, null>;

  'contract:refresh': Cb<Record<string, never>, { vehicles: ContractVehicle[]; buyers: PlayerOption[] }>;
  'contract:send': Cb<{ plate: string; buyer: number; price: number; terms: string; signature: Signature }, { contractId: string; expiresIn: number }>;
  /** key = how the buyer got the keys (null: no key system), copy = their signed copy was given */
  'contract:sign': Cb<{ contractId: string; signature: Signature }, { signedAt: number; key?: ContractKeyKind | null; copy?: boolean }>;
  /** the buyer's review: can they pay now (polled while the contract is pending) */
  'contract:balance': Cb<{ contractId: string }, { canAfford: boolean }>;
  /** the buyer declines, or the seller withdraws a sent contract */
  'contract:decline': Cb<{ contractId: string }, null>;

  /** fob HUD (client/carlock/fob.lua): save the layout (player setting fobPosition), leave a
   *  focused mode, side prompt clicks, inspect card Keep / Return to ground */
  'fob:save': Cb<FobLayout, FobLayout>;
  'fob:cancel': Cb<Record<string, never>, null>;
  'fob:action': Cb<{ action: 'throw' | 'inspect' | 'move' | 'help' | 'close' }, null>;
  'fob:keep': Cb<{ id: string }, null>;
  'fob:return': Cb<{ id: string }, null>;
}

export type NuiCallbackName = keyof NuiCallbacks;
