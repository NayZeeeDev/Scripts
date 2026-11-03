/**
 * Garage / impound showroom helpers: display names, status, search / filter / sort / group,
 * session-remembered choices, damage normalisation, plate templates, countdowns and a live
 * clock. Pure functions + tiny hooks; no UI. Also used by the impound app (same owner).
 */
import { useEffect, useReducer, useState } from 'react';
import { useSettings, useUi } from '@/lib/store';
import { t } from '@/lib/i18n';
import type { IconName } from '@/components/ui';
import type { AppName, DamageSummary, GarageVehicle, LocationKind, VehicleType } from '@/lib/types';

/** settings.interface.defaultView: 'grid' = comfortable rows with thumbnails, 'list' = compact rows. */
export type ViewMode = 'grid' | 'list';
export type GarageFilter = 'all' | 'favourites' | 'here' | 'shared' | 'impounded' | 'out';
export type GarageSort = 'relevance' | 'name' | 'mileage' | 'condition' | 'lastUsed';
export type GroupBy = 'class' | 'status' | 'none';

export const vehicleTypeIcon = (type: VehicleType): IconName =>
  type === 'sea' ? 'boat' : type === 'air' ? 'plane' : 'car';

/** Icon for a vehicle: class first (bikes, helicopters, trucks), then its type. */
export function vehicleIcon(v: { vehicleType: VehicleType; classId?: number }): IconName {
  switch (v.classId) {
    case 8:
    case 13:
      return 'bike';
    case 15:
      return 'heli';
    case 16:
      return 'plane';
    case 14:
      return 'boat';
    case 10:
    case 20:
      return 'truck';
    default:
      return vehicleTypeIcon(v.vehicleType);
  }
}

export function kindLabel(kind: LocationKind, vehicleType: VehicleType): string {
  if (kind === 'job') return t('Job garage');
  if (kind === 'private') return t('Private garage');
  if (kind === 'house') return t('House garage');
  if (kind === 'impound') return t('Impound');
  if (vehicleType === 'air') return t('Public hangar');
  if (vehicleType === 'sea') return t('Public marina');
  return t('Public garage');
}

/** Nickname when set, otherwise the full "Make Name" label. */
export function displayName(v: { nickname?: string | null; label: string; model: string }): string {
  const nick = (v.nickname ?? '').trim();
  if (nick) return nick;
  return v.label || v.model.toUpperCase();
}

/** Model name without its make ("Annis Elegy Retro Custom" → "Elegy Retro Custom"). */
export function modelName(v: { label: string; make?: string; model: string }): string {
  const label = (v.label || v.model.toUpperCase()).trim();
  const make = (v.make ?? '').trim();
  if (make && label.toLowerCase().startsWith(`${make.toLowerCase()} `) && label.length > make.length + 1) {
    return label.slice(make.length + 1);
  }
  return label;
}

const norm = (s: string | null | undefined) => (s ?? '').toLowerCase();
const compact = (s: string | null | undefined) => norm(s).replace(/\s+/g, '');

/** Search by name, nickname, make, model, class and plate (plates ignore spaces). */
export function matchesQuery(
  v: { label: string; make?: string; model: string; plate: string; nickname?: string | null; classLabel?: string },
  query: string,
): boolean {
  const q = norm(query).trim();
  if (!q) return true;
  const qc = q.replace(/\s+/g, '');
  return (
    norm(v.label).includes(q) ||
    norm(v.nickname).includes(q) ||
    norm(v.make).includes(q) ||
    norm(v.model).includes(q) ||
    norm(v.classLabel).includes(q) ||
    compact(v.plate).includes(qc)
  );
}

export const isShared = (v: GarageVehicle) => !!v.sharedBy || v.sharedWith > 0;
export const isHere = (v: GarageVehicle) => v.here && v.state === 'garaged';

export function matchesFilter(v: GarageVehicle, filter: GarageFilter): boolean {
  switch (filter) {
    case 'favourites':
      return v.favourite;
    case 'here':
      return isHere(v);
    case 'shared':
      return isShared(v);
    case 'impounded':
      return v.state === 'impounded';
    case 'out':
      return v.state === 'out';
    default:
      return true;
  }
}

/* ── status ─────────────────────────────────────────────────────────── */

export type StatusKey = 'here' | 'overdue' | 'elsewhere' | 'out' | 'lost' | 'impounded' | 'blocked';
export type StatusTone = 'teal' | 'ink' | 'amber' | 'red' | 'grey';

export interface VehicleStatus {
  key: StatusKey;
  tone: StatusTone;
  /** Short row label: "Here", "At Mirror Park Garage", "Out", "Impounded". */
  label: string;
}

/** Where the vehicle is, for the coloured status dot of a row. */
export function vehicleStatus(v: GarageVehicle): VehicleStatus {
  if (v.blocked) return { key: 'blocked', tone: 'grey', label: t('Blocked') };
  if (v.state === 'impounded') return { key: 'impounded', tone: 'red', label: t('Impounded') };
  if (v.state === 'out') {
    return v.canRecover
      ? { key: 'lost', tone: 'amber', label: t('Out · lost') }
      : { key: 'out', tone: 'amber', label: t('Out') };
  }
  if (!v.here) return { key: 'elsewhere', tone: 'ink', label: t('At {garage}', { garage: v.garageName ?? t('another garage') }) };
  if (v.finance?.overdue) return { key: 'overdue', tone: 'red', label: t('Payment overdue') };
  return { key: 'here', tone: 'teal', label: t('Here') };
}

/* ── sort ───────────────────────────────────────────────────────────── */

/** Average of engine and body health (0–100). */
export const condition = (v: { engine: number; body: number }) => (Number(v.engine) + Number(v.body)) / 2;

const byName = (a: GarageVehicle, b: GarageVehicle) =>
  displayName(a).localeCompare(displayName(b), undefined, { sensitivity: 'base' });

export function sortVehicles(list: GarageVehicle[], sort: GarageSort): GarageVehicle[] {
  const out = [...list];
  switch (sort) {
    case 'name':
      return out.sort(byName);
    case 'mileage':
      return out.sort((a, b) => b.mileage - a.mileage || byName(a, b));
    case 'condition':
      return out.sort((a, b) => condition(b) - condition(a) || byName(a, b));
    case 'lastUsed':
      return out.sort((a, b) => (b.lastUsed ?? 0) - (a.lastUsed ?? 0) || byName(a, b));
    default: {
      // Relevance: drivable here first, then favourites, then the rest; by name inside.
      const rank = (v: GarageVehicle) => (isHere(v) ? (v.canDrive ? 0 : 1) : 3) + (v.favourite ? 0 : 1);
      return out.sort((a, b) => rank(a) - rank(b) || byName(a, b));
    }
  }
}

/* ── groups ─────────────────────────────────────────────────────────── */

export interface ItemGroup<T> {
  key: string;
  /** '' = no heading (grouping off). */
  label: string;
  items: T[];
}

/**
 * Splits an already sorted list into groups (items keep their order inside a group).
 * `order` ranks the groups; equal ranks keep the order of their first item, so the group
 * holding the best match of the current sort comes first ("group order follows the sort").
 */
export function groupItems<T>(
  items: T[],
  keyOf: (item: T) => { key: string; label: string; order?: number },
): ItemGroup<T>[] {
  const map = new Map<string, { group: ItemGroup<T>; order: number; first: number }>();
  items.forEach((it, i) => {
    const g = keyOf(it);
    const hit = map.get(g.key);
    if (hit) hit.group.items.push(it);
    else map.set(g.key, { group: { key: g.key, label: g.label, items: [it] }, order: g.order ?? 0, first: i });
  });
  return Array.from(map.values())
    .sort((a, b) => a.order - b.order || a.first - b.first)
    .map((x) => x.group);
}

/** Group by vehicle class ("Super", "SUVs"…); unknown models go to "Other". */
export const classGroup = (v: { classLabel?: string; classId?: number }) => {
  const label = (v.classLabel ?? '').trim();
  return label ? { key: `c:${label.toLowerCase()}`, label } : { key: 'c:other', label: t('Other') };
};

const STATUS_GROUPS: Record<StatusKey, { key: string; label: () => string; order: number }> = {
  here: { key: 's:here', label: () => t('Parked here'), order: 0 },
  overdue: { key: 's:here', label: () => t('Parked here'), order: 0 },
  elsewhere: { key: 's:elsewhere', label: () => t('Other garages'), order: 1 },
  out: { key: 's:out', label: () => t('Out'), order: 2 },
  lost: { key: 's:out', label: () => t('Out'), order: 2 },
  impounded: { key: 's:impounded', label: () => t('Impounded'), order: 3 },
  blocked: { key: 's:blocked', label: () => t('Blocked'), order: 4 },
};

export const statusGroup = (v: GarageVehicle) => {
  const g = STATUS_GROUPS[vehicleStatus(v).key];
  return { key: g.key, label: g.label(), order: g.order };
};

/* ── damage ─────────────────────────────────────────────────────────── */

/** Lua sends empty arrays as {} and sparse ones as objects: always get a plain array back. */
export function asList<T>(value: T[] | Record<string, T> | null | undefined): T[] {
  if (!value) return [];
  if (Array.isArray(value)) return value.filter((x) => x !== null && x !== undefined);
  if (typeof value === 'object') return Object.values(value).filter((x) => x !== null && x !== undefined);
  return [];
}

/** Clean copy of a DamageSummary (lists normalised, numbers coerced); null stays null. */
export function normDamage(d: DamageSummary | null | undefined): DamageSummary | null {
  if (!d || typeof d !== 'object') return null;
  const num = (v: unknown, fb = 1000) => (Number.isFinite(Number(v)) ? Number(v) : fb);
  return {
    engine: num(d.engine),
    body: num(d.body),
    tank: num(d.tank),
    doors: asList<number>(d.doors as never).map(Number).filter(Number.isFinite),
    windows: asList<number>(d.windows as never).map(Number).filter(Number.isFinite),
    tyres: asList<{ index: number; state: 1 | 2 }>(d.tyres as never)
      .filter((x) => x && typeof x === 'object')
      .map((x) => ({ index: Number(x.index), state: (Number(x.state) === 2 ? 2 : 1) as 1 | 2 })),
    deformed: !!d.deformed,
  };
}

/** "2 windows smashed · 1 tyre burst" / "No visible damage" / "No damage data". */
export function damageCaption(d: DamageSummary | null): string {
  if (!d) return t('No damage data');
  const parts: string[] = [];
  const doors = d.doors.filter((i) => i <= 3).length;
  const panels = d.doors.filter((i) => i === 4 || i === 5).length;
  const tyres = d.tyres.length;
  if (doors) parts.push(doors === 1 ? t('1 door damaged') : t('{n} doors damaged', { n: doors }));
  if (panels) parts.push(panels === 1 ? t('1 panel off') : t('{n} panels off', { n: panels }));
  if (d.windows.length) parts.push(d.windows.length === 1 ? t('1 window smashed') : t('{n} windows smashed', { n: d.windows.length }));
  if (tyres) parts.push(tyres === 1 ? t('1 tyre burst') : t('{n} tyres burst', { n: tyres }));
  if (!parts.length && d.deformed) parts.push(t('Bodywork dented'));
  return parts.length ? parts.join(' · ') : t('No visible damage');
}

/* ── spawner plates ─────────────────────────────────────────────────── */

/**
 * Spawner plate template preview: '' → null (random), fixed text stays as is,
 * wildcards ('#' digit, '@' letter, '*' either) become '•'.
 */
export function platePreview(template: string): { text: string; random: boolean } | null {
  const tpl = (template ?? '').trim().toUpperCase();
  if (!tpl) return null;
  const random = /[#@*]/.test(tpl);
  return { text: tpl.replace(/[#@*]/g, '•').slice(0, 8), random };
}

/* ── time ───────────────────────────────────────────────────────────── */

/** "2d 4h", "3h 12m", "12m 05s", "45s". */
export function countdown(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds));
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  if (d > 0) return t('{d}d {h}h', { d, h });
  if (h > 0) return t('{h}h {m}m', { h, m: String(m).padStart(2, '0') });
  if (m > 0) return t('{m}m {s}s', { m, s: String(sec).padStart(2, '0') });
  return t('{s}s', { s: sec });
}

/** "2 days ago" style label for last use. */
export function ago(unix: number | null | undefined): string {
  if (!unix) return t('Never');
  const s = Math.max(0, Math.floor(Date.now() / 1000) - unix);
  if (s < 90) return t('Just now');
  if (s < 3600) return t('{n} min ago', { n: Math.round(s / 60) });
  if (s < 86400) return t('{n}h ago', { n: Math.round(s / 3600) });
  const d = Math.round(s / 86400);
  return d === 1 ? t('Yesterday') : t('{n} days ago', { n: d });
}

/** Current unix time, ticking every `ms` while `active`. */
export function useNow(active: boolean, ms = 1000): number {
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000));
  useEffect(() => {
    if (!active) return;
    setNow(Math.floor(Date.now() / 1000));
    const id = window.setInterval(() => setNow(Math.floor(Date.now() / 1000)), ms);
    return () => window.clearInterval(id);
  }, [active, ms]);
  return now;
}

/* ── choices remembered for the session (per app) ───────────────────── */

const viewMemory: Partial<Record<string, { view: ViewMode; basis: ViewMode }>> = {};

/**
 * Row density: settings.defaultView until the player picks one; the pick is remembered
 * for the rest of the session (dropped again if an admin changes the default).
 */
export function useSessionView(scope: string): [ViewMode, (v: ViewMode) => void] {
  const def = useSettings().defaultView === 'list' ? 'list' : 'grid';
  const [, force] = useReducer((x: number) => x + 1, 0);
  const mem = viewMemory[scope];
  const view = mem && mem.basis === def ? mem.view : def;
  const set = (v: ViewMode) => {
    viewMemory[scope] = { view: v, basis: def };
    force();
  };
  return [view, set];
}

const choiceMemory: Record<string, unknown> = {};

/** useState whose value survives closing and reopening the menu (until the UI reloads). */
export function useSessionChoice<T>(key: string, initial: T): [T, (v: T) => void] {
  const [value, setValue] = useState<T>(() => (key in choiceMemory ? (choiceMemory[key] as T) : initial));
  const set = (v: T) => {
    choiceMemory[key] = v;
    setValue(v);
  };
  return [value, set];
}

/** Whether an app is still open (guards async results arriving after close). */
export const isAppOpen = (app: AppName) => useUi.getState().apps[app].open;

/** Top speed in the configured unit: { value, unit: 'km/h' | 'mph' }. */
export function speedIn(kmh: number, unit: 'mi' | 'km'): { value: number; unit: string } {
  const v = Math.max(0, Number(kmh) || 0);
  return unit === 'mi' ? { value: Math.round(v * 0.621371), unit: t('mph') } : { value: Math.round(v), unit: t('km/h') };
}
