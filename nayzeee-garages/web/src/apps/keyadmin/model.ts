/**
 * Admin key manager: labels, formatters and the settings layout (no React).
 *
 * - meters / timeLeft / custodyOf / typeOf / originLabel: how a key row reads.
 * - Settings: TAB_ICONS, GROUPS (UI grouping of the server schema; unknown ids land in a
 *   per-tab "More" group so a new server setting always shows), optionLabel, splitUnit,
 *   idleReason (a setting that only matters with another one), parseColor / formatColor.
 * - Recent players (per viewer, localStorage in try/catch: a convenience only).
 */
import type { IconName } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { KeyAdminRow, KeyCustody, KeySetting, KeySettingValue, KeySettingsTab } from '@/lib/types';

/** Lua sends an empty table as {} or []: lists are read through this. */
export const list = <T,>(v: T[] | null | undefined | Record<string, never>): T[] => (Array.isArray(v) ? v : []);

/* ── distances / times ───────────────────────────────────────────────── */

/** Metres in, "12 m" / "1.4 km" or "40 ft" / "0.9 mi" out (interface distance unit). */
export function meters(m: number | null | undefined, unit: 'mi' | 'km'): string {
  if (m === null || m === undefined || !Number.isFinite(m)) return '—';
  const v = Math.max(0, m);
  if (unit === 'mi') {
    const ft = v * 3.28084;
    if (ft < 1000) return t('{n} ft', { n: Math.round(ft) });
    return t('{n} mi', { n: (v / 1609.344).toFixed(v < 16093 ? 1 : 0) });
  }
  if (v < 1000) return t('{n} m', { n: Math.round(v) });
  return t('{n} km', { n: (v / 1000).toFixed(v < 10000 ? 1 : 0) });
}

/** "3h 12m" / "2d 4h" / "45s" from seconds; null when over. */
export function duration(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds));
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (d > 0) return t('{d}d {h}h', { d, h });
  if (h > 0) return t('{h}h {m}m', { h, m: String(m).padStart(2, '0') });
  if (m > 0) return t('{m}m', { m });
  return t('{s}s', { s });
}

/** Seconds left until a unix time (server os.time()), null without one. */
export function secondsLeft(unix: number | null | undefined, nowMs = Date.now()): number | null {
  if (!unix) return null;
  return Math.floor(unix - nowMs / 1000);
}

/** "Nov 12, 14:05" */
export function stamp(unix: number | null | undefined): string {
  if (!unix) return '—';
  const d = new Date(unix * 1000);
  const month = t(['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.getMonth()]);
  return `${month} ${d.getDate()}, ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

/* ── key rows ────────────────────────────────────────────────────────── */

export type RowFilter = 'all' | 'items' | 'access' | 'temp' | 'owned';

export function filterOf(row: Pick<KeyAdminRow, 'type'>): Exclude<RowFilter, 'all'> {
  if (row.type === 'key' || row.type === 'fob') return 'items';
  if (row.type === 'temp') return 'temp';
  if (row.type === 'virtual') return 'access';
  return 'owned';
}

export interface TypeInfo {
  label: string;
  tone: 'teal' | 'amber' | 'neutral' | 'white' | 'blue';
  icon: IconName;
}

export function typeOf(row: Pick<KeyAdminRow, 'type' | 'origin'>): TypeInfo {
  switch (row.type) {
    case 'fob':
      return { label: t('Fob'), tone: 'teal', icon: 'key' };
    case 'key':
      return { label: t('Key'), tone: 'white', icon: 'key' };
    case 'virtual':
      return { label: t('Virtual'), tone: 'blue', icon: 'link' };
    case 'temp':
      return { label: t('Temporary'), tone: 'amber', icon: 'clock' };
    default:
      return row.origin === 'share'
        ? { label: t('Garage share'), tone: 'neutral', icon: 'users' }
        : { label: t('Owner'), tone: 'neutral', icon: 'crown' };
  }
}

const ORIGINS: Record<string, string> = {
  owner: 'Owns the vehicle',
  share: 'Shared by the owner',
  virtual: 'Shared key',
  key: 'Registered key',
  garage: 'Garage retrieval',
  paid: 'Locksmith copy',
  limited: 'Starting set',
  loader: 'Character load',
  admin: 'Staff',
  hotwire: 'Hotwired',
  robbery: 'Hold-up',
  assist: 'Requested from an NPC',
  abandoned: 'Abandoned vehicle',
  rekey: 'New locks',
  locksmith: 'Back-alley copy',
  search: 'Found in the vehicle',
  spawner: 'Job spawner',
  compat: 'Another key script',
  export: 'Another script',
  other: 'Other',
};

/** Where a key came from, readable. */
export function originLabel(origin: string | null | undefined): string {
  if (!origin) return '—';
  const known = ORIGINS[origin];
  if (known) return t(known);
  const s = origin.replace(/[_-]+/g, ' ');
  return s.charAt(0).toUpperCase() + s.slice(1);
}

export interface CustodyInfo {
  icon: IconName;
  label: string;
  detail?: string;
  tone: 'teal' | 'amber' | 'red' | 'neutral';
}

/** Where a key is: pocket slot, glovebox / trunk / stash, ground, the server (access only). */
export function custodyOf(c: KeyCustody | null | undefined): CustodyInfo {
  if (!c) return { icon: 'info', label: t('Unknown'), tone: 'neutral' };
  switch (c.kind) {
    case 'inventory':
      return { icon: 'user', label: t('Pockets'), detail: c.slot ? t('slot {n}', { n: c.slot }) : undefined, tone: 'teal' };
    case 'stash': {
      const stash = c.stash ?? '';
      const glove = stash.match(/^glovebox:(.+)$/i);
      if (glove) return { icon: 'car', label: t('Glovebox'), detail: glove[1], tone: 'neutral' };
      const trunk = stash.match(/^trunk:(.+)$/i);
      if (trunk) return { icon: 'car', label: t('Trunk'), detail: trunk[1], tone: 'neutral' };
      const other = stash.match(/^([^:]+):(.+)$/);
      return { icon: 'layers', label: t('Stash'), detail: other ? `${other[1]} · ${other[2]}` : stash || undefined, tone: 'neutral' };
    }
    case 'ground':
      return { icon: 'pin', label: t('On the ground'), detail: c.groundId ?? undefined, tone: 'amber' };
    case 'server':
      return { icon: 'shield', label: t('Server'), detail: t('no item'), tone: 'neutral' };
    case 'lost':
      return { icon: 'ban', label: t('Lost'), tone: 'red' };
    case 'flight':
      return { icon: 'route', label: t('Thrown'), detail: t('in the air'), tone: 'amber' };
    default:
      return { icon: 'info', label: t('Unknown'), detail: t('left a pocket'), tone: 'neutral' };
  }
}

/** What deleting a row does (confirm dialog). */
export function deleteMessage(row: Pick<KeyAdminRow, 'type' | 'custody' | 'plate'>, online: boolean): string {
  if (row.type === 'virtual') return t('The shared access to {plate} is revoked. The owner can share it again.', { plate: row.plate });
  if (row.type === 'temp') return t('The temporary key of {plate} ends now.', { plate: row.plate });
  const c = row.custody?.kind;
  if (c === 'inventory' && online) return t('The key item is taken out of their pockets and stops working.');
  if (c === 'stash') return t('The key item is taken out of the stash it sits in and stops working.');
  if (c === 'ground') return t('The key on the ground is removed and stops working.');
  return t('Nobody can reach this key item right now: it is marked lost and no longer counts as a copy. Change the locks to be sure it never works again.');
}

/* ── GTA vehicle classes (GetVehicleClass) ───────────────────────────── */

export const CLASS_NAMES = [
  'Compacts', 'Sedans', 'SUVs', 'Coupes', 'Muscle', 'Sports classics', 'Sports', 'Super', 'Motorcycles',
  'Off-road', 'Industrial', 'Utility', 'Vans', 'Cycles', 'Boats', 'Helicopters', 'Planes', 'Service',
  'Emergency', 'Military', 'Commercial', 'Trains', 'Open wheel',
];

export const classLabel = (n: number) => (CLASS_NAMES[n] ? t(CLASS_NAMES[n]) : t('Class {n}', { n }));

/* ── settings layout ─────────────────────────────────────────────────── */

export const TAB_ICONS: Record<string, IconName> = {
  keys: 'key',
  ground: 'pin',
  vehicles: 'car',
  lockpicking: 'lock',
  hotwiring: 'engine',
  npc: 'users',
  jobs: 'briefcase',
  security: 'shield',
};

export interface GroupDef {
  id: string;
  tab: KeySettingsTab;
  title: string;
  icon: IconName;
  ids: string[];
}

/** UI grouping of the server's settings (labels go through t() when drawn). */
export const GROUPS: GroupDef[] = [
  { id: 'keys.policy', tab: 'keys', title: 'Key policy', icon: 'key', ids: ['keys.mode', 'keys.limitedKeys', 'keys.giveKeyOnRetrieve', 'keys.ownerHasKey', 'keys.tempKeyHours'] },
  { id: 'keys.fob', tab: 'keys', title: 'Key fob and ranges', icon: 'gauge', ids: ['keys.defaultFob', 'keys.remoteRange', 'keys.keyRange', 'keys.giveRange', 'keys.lockPrefer'] },
  { id: 'keys.sharing', tab: 'keys', title: 'Sharing and tracking', icon: 'userPlus', ids: ['keys.maxShares', 'keys.maxCopies', 'keys.shareHours', 'keys.trackWho'] },
  { id: 'keys.keyless', tab: 'keys', title: 'Keyless entry', icon: 'unlock', ids: ['keys.keyless', 'keys.keylessMin', 'keys.keylessMax'] },
  { id: 'ground.main', tab: 'ground', title: 'Keys on the ground', icon: 'pin', ids: ['ground.enabled', 'ground.animateDrops', 'ground.persist', 'ground.removeAfter'] },
  { id: 'ground.reach', tab: 'ground', title: 'Throwing and catching', icon: 'route', ids: ['ground.pickupRange', 'ground.throwRange', 'ground.catchWindow'] },
  { id: 'ground.marker', tab: 'ground', title: 'Dropped key markers', icon: 'sparkle', ids: ['ground.markerStyle', 'ground.markerColor', 'ground.markerSize', 'ground.markerHeight'] },
  { id: 'vehicles.ignition', tab: 'vehicles', title: 'Ignition', icon: 'engine', ids: ['vehicles.requireKey', 'vehicles.keepEngineRunning', 'vehicles.allowRunningEngine', 'vehicles.bypassClasses', 'vehicles.bypassModels'] },
  { id: 'vehicles.security', tab: 'vehicles', title: 'Security profiles', icon: 'shield', ids: ['vehicles.highendClasses', 'vehicles.immobiliser', 'vehicles.lockNotify'] },
  { id: 'lockpick.main', tab: 'lockpicking', title: 'Lock picking', icon: 'lock', ids: ['lockpick.style', 'lockpick.pins', 'lockpick.snapChance', 'lockpick.alarmOnSnap'] },
  { id: 'hotwire.method', tab: 'hotwiring', title: 'Method', icon: 'engine', ids: ['hotwire.style', 'hotwire.kitRequired'] },
  { id: 'hotwire.reader', tab: 'hotwiring', title: 'Signal reader and wires', icon: 'sliders', ids: ['hotwire.readerClasses', 'hotwire.readerModels', 'hotwire.wireModels'] },
  { id: 'npc.holdups', tab: 'npc', title: 'Hold-ups', icon: 'warning', ids: ['npc.robbery', 'npc.policeRequired', 'npc.dispatchDelay', 'npc.alertChance', 'npc.robTime', 'npc.cooldown', 'npc.deadDriverKeys'] },
  { id: 'npc.reactions', tab: 'npc', title: 'Driver reactions', icon: 'users', ids: ['npc.handover', 'npc.drop', 'npc.fight', 'npc.flee'] },
  { id: 'jobs.main', tab: 'jobs', title: 'Job vehicles', icon: 'briefcase', ids: ['jobs.bypass', 'jobs.keyHours', 'jobs.assistJobs'] },
  { id: 'security.items', tab: 'security', title: 'Key items and other scripts', icon: 'code', ids: ['security.trustUnsignedKeys', 'security.compat', 'security.compatAmbient', 'security.clientGiveKey'] },
  { id: 'security.pin', tab: 'security', title: 'Ghost PIN and alarms', icon: 'shield', ids: ['security.pinAttempts', 'security.pinCooldown', 'security.pinSession', 'security.alarmAlertChance'] },
];

export interface Group {
  id: string;
  title: string;
  icon: IconName;
  settings: KeySetting[];
}

/** The groups of one tab, built from the server list (settings the UI does not know go last). */
export function groupsOf(tab: string, settings: KeySetting[]): Group[] {
  const inTab = settings.filter((s) => s.tab === tab);
  const byId = new Map(inTab.map((s) => [s.id, s]));
  const used = new Set<string>();
  const out: Group[] = [];
  for (const g of GROUPS) {
    if (g.tab !== tab) continue;
    const list = g.ids.map((id) => byId.get(id)).filter((s): s is KeySetting => !!s);
    list.forEach((s) => used.add(s.id));
    if (list.length) out.push({ id: g.id, title: t(g.title), icon: g.icon, settings: list });
  }
  const rest = inTab.filter((s) => !used.has(s.id));
  if (rest.length) out.push({ id: `${tab}.more`, title: t('More'), icon: 'sliders', settings: rest });
  return out;
}

/** Two balanced columns of groups (row count; list settings weigh more). */
export function columnsOf(groups: Group[]): [Group[], Group[]] {
  const weight = (g: Group) => 1.4 + g.settings.reduce((n, s) => n + (isList(s) ? 1.7 : 1), 0);
  const total = groups.reduce((n, g) => n + weight(g), 0);
  const left: Group[] = [];
  const right: Group[] = [];
  let acc = 0;
  for (const g of groups) {
    // keep the order: fill the left column up to about half, the rest goes right
    if (acc < total / 2 && (left.length === 0 || acc + weight(g) / 2 <= total / 2)) {
      left.push(g);
      acc += weight(g);
    } else right.push(g);
  }
  return [left, right];
}

export const isList = (s: Pick<KeySetting, 'type'>) => s.type === 'classes' || s.type === 'models' || s.type === 'strings';

const OPTION_LABELS: Record<string, Record<string, [string, string?]>> = {
  'keys.mode': {
    flexible: ['Flexible', 'Key items; sharing makes a copy'],
    limited: ['Limited', 'A fixed set of key items; sharing hands yours over'],
    virtual: ['Virtual', 'No items; the server issues access'],
  },
  'keys.ownerHasKey': {
    auto: ['Automatic', 'Yes with virtual keys, no with key items'],
    yes: ['Always'],
    no: ['Never', 'Owners need a key item'],
  },
  'keys.lockPrefer': {
    nearest: ['Nearest vehicle'],
    owned: ['Own vehicles first'],
    last: ['Last used first'],
  },
  'keys.trackWho': {
    real: ['Owners, shares and real keys'],
    any: ['Every key holder'],
    owner: ['Owners and garage shares'],
  },
  'ground.markerStyle': { none: ['No marker'], chevron: ['Chevron'], ring: ['Ring'], dot: ['Dot'] },
  'lockpick.style': { skillcheck: ['Skill checks'], pins: ['Pin lock', 'The five-pin lock minigame'] },
  'hotwire.style': { profile: ['Per security profile'], wires: ['Wires and reader', 'Splice wires; reader classes tune the signal'] },
};

/** Readable option of an enum setting (fallback: the value, capitalised). */
export function optionLabel(id: string, value: string): { label: string; hint?: string } {
  const known = OPTION_LABELS[id]?.[value];
  if (known) return { label: t(known[0]), hint: known[1] ? t(known[1]) : undefined };
  const s = value.replace(/[_-]+/g, ' ');
  return { label: s.charAt(0).toUpperCase() + s.slice(1) };
}

const UNITS: Record<string, string> = {
  m: 'm', '%': '%', s: 's', ms: 'ms', hours: 'h', minutes: 'min', h: 'h', min: 'min',
};

/** "Remote range (m)" → { label: 'Remote range', unit: 'm' } (unknown units stay in the label). */
export function splitUnit(label: string): { label: string; unit?: string } {
  const m = label.match(/^(.*\S)\s*\(([^()]{1,12})\)\s*$/);
  if (!m) return { label };
  const unit = UNITS[m[2].trim().toLowerCase()];
  return unit ? { label: m[1], unit: t(unit) } : { label };
}

type Values = Record<string, KeySettingValue>;

/** Why a setting does nothing with the current draft (dimmed row + note), else null. */
export function idleReason(id: string, v: Values): string | null {
  const is = (k: string, x: KeySettingValue) => v[k] !== undefined && v[k] === x;
  const off = (k: string) => v[k] === false;
  if (id === 'keys.limitedKeys' && v['keys.mode'] !== undefined && !is('keys.mode', 'limited')) return t('Only used in the limited key mode');
  if ((id === 'keys.giveKeyOnRetrieve' || id === 'keys.maxCopies') && v['keys.mode'] !== undefined && !is('keys.mode', 'flexible'))
    return t('Only used in the flexible key mode');
  if ((id === 'keys.keylessMin' || id === 'keys.keylessMax') && off('keys.keyless')) return t('Keyless entry is off');
  if (id.startsWith('ground.') && id !== 'ground.enabled' && off('ground.enabled')) return t('Keys on the ground are off');
  if (['ground.markerColor', 'ground.markerSize', 'ground.markerHeight'].includes(id) && is('ground.markerStyle', 'none')) return t('No marker is drawn');
  if (['lockpick.pins', 'lockpick.snapChance', 'lockpick.alarmOnSnap'].includes(id) && is('lockpick.style', 'skillcheck')) return t('Only used with the pin lock');
  if (id === 'hotwire.readerClasses' && is('hotwire.style', 'profile')) return t('Only used with wires and reader');
  if (id.startsWith('npc.') && id !== 'npc.robbery' && id !== 'npc.deadDriverKeys' && off('npc.robbery')) return t('Hold-ups are off');
  if (['security.pinAttempts', 'security.pinCooldown', 'security.pinSession'].includes(id) && off('vehicles.immobiliser')) return t('Immobilisers are off');
  return null;
}

/* ── colours ─────────────────────────────────────────────────────────── */

export const isHexColor = (v: unknown, alpha: boolean): v is string =>
  typeof v === 'string' && (alpha ? /^#[0-9a-f]{6}([0-9a-f]{2})?$/i : /^#[0-9a-f]{6}$/i).test(v);

/** '#rrggbb' or '#rrggbbaa' → hex + opacity 0-100 (no alpha: the marker's 180/255 ≈ 71%). */
export function parseColor(v: unknown): { hex: string; alpha: number | null } {
  if (typeof v !== 'string') return { hex: '#2dd4bf', alpha: null };
  const m = v.match(/^#([0-9a-f]{6})([0-9a-f]{2})?$/i);
  if (!m) return { hex: '#2dd4bf', alpha: null };
  return { hex: `#${m[1].toLowerCase()}`, alpha: m[2] ? Math.round((parseInt(m[2], 16) / 255) * 100) : null };
}

export function formatColor(hex: string, alpha: number | null): string {
  if (alpha === null) return hex.toLowerCase();
  const a = Math.round((Math.max(0, Math.min(100, alpha)) / 100) * 255);
  return `${hex.toLowerCase()}${a.toString(16).padStart(2, '0')}`;
}

export function rgba(hex: string, alpha: number): string {
  const n = parseInt(hex.slice(1, 7), 16);
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${Math.max(0, Math.min(1, alpha))})`;
}

/** The marker's default opacity (client/carlock/lock.lua draws with alpha 180). */
export const MARKER_ALPHA = Math.round((180 / 255) * 100);

/* ── values ──────────────────────────────────────────────────────────── */

export const same = (a: KeySettingValue | undefined, b: KeySettingValue | undefined) => JSON.stringify(a) === JSON.stringify(b);

export function valueText(s: KeySetting, v: KeySettingValue): string {
  if (s.type === 'bool') return v ? t('On') : t('Off');
  if (s.type === 'enum') return optionLabel(s.id, String(v)).label;
  if (s.type === 'classes') return Array.isArray(v) && v.length ? (v as number[]).map((n) => classLabel(n)).join(', ') : t('None');
  if (s.type === 'models' || s.type === 'strings') return Array.isArray(v) && v.length ? (v as string[]).join(', ') : t('None');
  if (s.type === 'number') {
    const { unit } = splitUnit(s.label);
    return unit ? `${v} ${unit}` : String(v);
  }
  return String(v);
}

/** Client copy of the server's checks (shared/carlock.lua validateSetting): error text or null. */
export function validate(s: KeySetting, v: KeySettingValue): string | null {
  switch (s.type) {
    case 'bool':
      return typeof v === 'boolean' ? null : t('Expected on / off');
    case 'number': {
      if (typeof v !== 'number' || !Number.isFinite(v)) return t('Enter a number');
      if ((s.min !== undefined && v < s.min) || (s.max !== undefined && v > s.max))
        return t('Between {min} and {max}', { min: s.min ?? '−∞', max: s.max ?? '∞' });
      if (s.integer && !Number.isInteger(v)) return t('Use a whole number');
      return null;
    }
    case 'enum':
      return typeof v === 'string' && (s.options ?? []).includes(v) ? null : t('Pick an option');
    case 'color':
      return isHexColor(v, !!s.alpha) ? null : t('Use a hex colour like #2DD4BF');
    case 'classes':
      return Array.isArray(v) && v.every((n) => Number.isInteger(n) && (n as number) >= 0 && (n as number) <= 22) ? null : t('Pick vehicle classes');
    case 'models':
      return Array.isArray(v) && v.length <= 200 && v.every((x) => typeof x === 'string' && /^[\w-]{1,32}$/.test(x)) ? null : t('Model names use letters, digits, _ and -');
    case 'strings':
      return Array.isArray(v) && v.length <= 50 && v.every((x) => typeof x === 'string' && /^[\w-]{1,32}$/.test(x)) ? null : t('Names use letters, digits, _ and -');
    default:
      return null;
  }
}

/* ── recent players (per viewer) ─────────────────────────────────────── */

export interface RecentPlayer {
  identifier: string;
  name: string;
}

const RECENT_KEY = 'nz-keyadmin-recent';

export function readRecent(): RecentPlayer[] {
  try {
    const raw = JSON.parse(window.localStorage.getItem(RECENT_KEY) ?? '[]') as unknown;
    if (!Array.isArray(raw)) return [];
    return raw
      .filter((x): x is RecentPlayer => !!x && typeof x.identifier === 'string' && typeof x.name === 'string')
      .slice(0, 6);
  } catch {
    return [];
  }
}

export function pushRecent(p: RecentPlayer): RecentPlayer[] {
  const next = [p, ...readRecent().filter((x) => x.identifier !== p.identifier)].slice(0, 6);
  try {
    window.localStorage.setItem(RECENT_KEY, JSON.stringify(next));
  } catch {
    /* storage unavailable */
  }
  return next;
}
