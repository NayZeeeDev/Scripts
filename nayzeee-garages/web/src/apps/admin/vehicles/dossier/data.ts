/**
 * Dossier helpers (no React): damage normalisation and part tables, relative time, speed
 * labels, garage-key names and colour helpers for the paint swatches.
 */
import { t } from '@/lib/i18n';
import { date } from '@/lib/format';
import type { AdminOpenData, AdminVehicleDetail, DamageSummary } from '@/lib/types';
import { colourByIndex, isRgb, rgbToHex } from '../props/catalog';
import { num } from '../util';

/* ───────────────────────── Lua list normalisation ───────────────────────── */

/** Lua sends empty tables as {} and sparse lists as objects keyed "1", "2"…: always return an array. */
export function asList<T>(v: unknown): T[] {
  if (Array.isArray(v)) return v.filter((x) => x !== null && x !== undefined) as T[];
  if (v && typeof v === 'object') return Object.values(v as Record<string, unknown>).filter((x) => x !== null && x !== undefined) as T[];
  return [];
}

const health = (v: unknown) => Math.max(0, Math.min(1000, num(v, 1000)));

/** A DamageSummary with real arrays, or null when there is no damage data. */
export function normDamage(raw: unknown): DamageSummary | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const d = raw as Record<string, unknown>;
  const ints = (v: unknown) => asList<unknown>(v).map((x) => num(x, -1)).filter((x) => x >= 0);
  const tyres = asList<Record<string, unknown>>(d.tyres)
    .map((x) => ({ index: num(x?.index, -1), state: (num(x?.state, 1) === 2 ? 2 : 1) as 1 | 2 }))
    .filter((x) => x.index >= 0);
  return {
    engine: health(d.engine),
    body: health(d.body),
    tank: health(d.tank),
    doors: ints(d.doors),
    windows: ints(d.windows),
    tyres,
    deformed: d.deformed === true || d.deformed === 1,
  };
}

/* ───────────────────────── damage parts ───────────────────────── */

export type PartGroup = 'doors' | 'windows' | 'tyres';
export type PartState = 'ok' | 'bad' | 'burst' | 'rim';

export interface Part {
  /** Stable id used by the diagram ('door0', 'win6', 'tyre4'…). */
  id: string;
  group: PartGroup;
  label: () => string;
  /** Label inside its group ("Front left"). */
  short: () => string;
  /** Only listed when damaged (middle windows / tyres of long vehicles). */
  optional?: boolean;
}

export const PARTS: Part[] = [
  { id: 'door0', group: 'doors', label: () => t('Front left door'), short: () => t('Front left') },
  { id: 'door1', group: 'doors', label: () => t('Front right door'), short: () => t('Front right') },
  { id: 'door2', group: 'doors', label: () => t('Rear left door'), short: () => t('Rear left') },
  { id: 'door3', group: 'doors', label: () => t('Rear right door'), short: () => t('Rear right') },
  { id: 'door4', group: 'doors', label: () => t('Bonnet'), short: () => t('Bonnet') },
  { id: 'door5', group: 'doors', label: () => t('Boot'), short: () => t('Boot') },
  { id: 'win6', group: 'windows', label: () => t('Windscreen'), short: () => t('Windscreen') },
  { id: 'win7', group: 'windows', label: () => t('Rear window'), short: () => t('Rear screen') },
  { id: 'win0', group: 'windows', label: () => t('Front left window'), short: () => t('Front left') },
  { id: 'win1', group: 'windows', label: () => t('Front right window'), short: () => t('Front right') },
  { id: 'win2', group: 'windows', label: () => t('Rear left window'), short: () => t('Rear left') },
  { id: 'win3', group: 'windows', label: () => t('Rear right window'), short: () => t('Rear right') },
  { id: 'win4', group: 'windows', label: () => t('Middle left window'), short: () => t('Middle left'), optional: true },
  { id: 'win5', group: 'windows', label: () => t('Middle right window'), short: () => t('Middle right'), optional: true },
  { id: 'tyre0', group: 'tyres', label: () => t('Front left tyre'), short: () => t('Front left') },
  { id: 'tyre1', group: 'tyres', label: () => t('Front right tyre'), short: () => t('Front right') },
  { id: 'tyre4', group: 'tyres', label: () => t('Rear left tyre'), short: () => t('Rear left') },
  { id: 'tyre5', group: 'tyres', label: () => t('Rear right tyre'), short: () => t('Rear right') },
  { id: 'tyre2', group: 'tyres', label: () => t('Middle left tyre'), short: () => t('Middle left'), optional: true },
  { id: 'tyre3', group: 'tyres', label: () => t('Middle right tyre'), short: () => t('Middle right'), optional: true },
];

/** GTA tyre index → diagram slot (45 / 47 are the middle wheels of 6-wheelers). */
const tyreSlot = (i: number) => (i === 45 ? 2 : i === 47 ? 3 : i);

/** State of every part ('ok' for intact). */
export function partStates(d: DamageSummary | null): Record<string, PartState> {
  const out: Record<string, PartState> = {};
  for (const p of PARTS) out[p.id] = 'ok';
  if (!d) return out;
  for (const i of d.doors) if (i >= 0 && i <= 5) out[`door${i}`] = 'bad';
  for (const i of d.windows) if (i >= 0 && i <= 7) out[`win${i}`] = 'bad';
  for (const ty of d.tyres) {
    const s = tyreSlot(ty.index);
    if (s >= 0 && s <= 5) out[`tyre${s}`] = ty.state === 2 ? 'rim' : 'burst';
  }
  return out;
}

export interface DamageCounts {
  doors: number;
  windows: number;
  burst: number;
  rim: number;
}

export function damageCounts(d: DamageSummary | null): DamageCounts {
  if (!d) return { doors: 0, windows: 0, burst: 0, rim: 0 };
  return {
    doors: new Set(d.doors).size,
    windows: new Set(d.windows).size,
    burst: d.tyres.filter((x) => x.state !== 2).length,
    rim: d.tyres.filter((x) => x.state === 2).length,
  };
}

/** "2 windows smashed · 1 tyre burst" / "No visible damage" / "No damage data". */
export function damageCaption(d: DamageSummary | null): string {
  if (!d) return t('No damage data');
  const c = damageCounts(d);
  const parts: string[] = [];
  if (c.doors) parts.push(c.doors === 1 ? t('1 panel damaged') : t('{n} panels damaged', { n: c.doors }));
  if (c.windows) parts.push(c.windows === 1 ? t('1 window smashed') : t('{n} windows smashed', { n: c.windows }));
  if (c.burst) parts.push(c.burst === 1 ? t('1 tyre burst') : t('{n} tyres burst', { n: c.burst }));
  if (c.rim) parts.push(c.rim === 1 ? t('1 tyre on the rim') : t('{n} tyres on the rim', { n: c.rim }));
  if (d.deformed) parts.push(t('body deformed'));
  if (!parts.length) return t('No visible damage');
  const s = parts.join(' · ');
  return s.charAt(0).toUpperCase() + s.slice(1);
}

export function hasVisibleDamage(d: DamageSummary | null): boolean {
  if (!d) return false;
  return d.doors.length > 0 || d.windows.length > 0 || d.tyres.length > 0 || d.deformed;
}

/* ───────────────────────── time ───────────────────────── */

export const nowS = () => Math.floor(Date.now() / 1000);

/** "just now", "12 min ago", "3 h ago", "yesterday", "5 days ago", then the date. */
export function ago(unix: number | null | undefined): string {
  if (!unix) return t('Never');
  const s = nowS() - unix;
  if (s < 0) return inTime(unix);
  if (s < 60) return t('just now');
  const m = Math.floor(s / 60);
  if (m < 60) return t('{n} min ago', { n: m });
  const h = Math.floor(m / 60);
  if (h < 24) return t('{n} h ago', { n: h });
  const d = Math.floor(h / 24);
  if (d === 1) return t('yesterday');
  if (d < 30) return t('{n} days ago', { n: d });
  return date(unix);
}

/** "in 9h 36m" / "in 1d 10h" / "in 5 days". */
export function inTime(unix: number): string {
  const s = Math.max(0, unix - nowS());
  const totalMin = Math.round(s / 60);
  const h = Math.floor(totalMin / 60);
  const m = totalMin % 60;
  if (h < 24) {
    if (h === 0) return t('in {m}m', { m });
    return m ? t('in {h}h {m}m', { h, m }) : t('in {h}h', { h });
  }
  const d = Math.floor(h / 24);
  if (d < 3) return h % 24 ? t('in {d}d {h}h', { d, h: h % 24 }) : t('in {d}d', { d });
  return t('in {n} days', { n: Math.round(h / 24) });
}

/* ───────────────────────── units ───────────────────────── */

/** "212 km/h" or "132 mph". */
export function speedLabel(kmh: number, unit: 'km' | 'mi'): string {
  const v = unit === 'mi' ? kmh * 0.621371 : kmh;
  return unit === 'mi' ? t('{n} mph', { n: Math.round(v) }) : t('{n} km/h', { n: Math.round(v) });
}

/* ───────────────────────── names ───────────────────────── */

/** Readable name for a garage key ('L12', 'G3', 'J…'), falling back to the key itself. */
export function garageName(key: unknown, detail: AdminVehicleDetail | null, data: AdminOpenData): string | null {
  if (typeof key !== 'string' && typeof key !== 'number') return null;
  const k = String(key);
  const fromDetail = detail?.garages.find((g) => g.key === k)?.name;
  if (fromDetail) return fromDetail;
  const m = /^[A-Za-z](\d+)$/.exec(k);
  if (m) {
    const id = Number(m[1]);
    if (k[0] === 'L' || k[0] === 'l') {
      const loc = data.locations.find((l) => l.id === id);
      if (loc) return loc.name;
    }
    if (k[0] === 'G' || k[0] === 'g') return t('Private garage #{id}', { id });
  }
  if (typeof key === 'number') {
    const loc = data.locations.find((l) => l.id === key);
    if (loc) return loc.name;
  }
  return k;
}

export function impoundName(id: unknown, detail: AdminVehicleDetail | null, data: AdminOpenData): string | null {
  const n = num(id, -1);
  if (n < 0) return null;
  return detail?.impounds.find((i) => i.id === n)?.name ?? data.locations.find((l) => l.id === n)?.name ?? t('Impound #{id}', { id: n });
}

/** Job / gang label of a vehicle (or its job/gang tag for player vehicles). */
export function groupLabel(detail: AdminVehicleDetail, data: AdminOpenData): string | null {
  const v = detail.vehicle;
  if (v.ownerType === 'job') return data.jobs.find((j) => j.name === v.job)?.label ?? v.job;
  if (v.ownerType === 'gang') return data.gangs.find((g) => g.name === v.gang)?.label ?? v.gang;
  const job = v.job ? data.jobs.find((j) => j.name === v.job)?.label ?? v.job : null;
  const gang = v.gang ? data.gangs.find((g) => g.name === v.gang)?.label ?? v.gang : null;
  return job ?? gang;
}

/* ───────────────────────── colours ───────────────────────── */

export interface Swatch {
  /** CSS colour, or null when the index is not in the catalogue. */
  hex: string | null;
  name: string;
  /** "#12" for palette indexes, "RGB" for custom paint. */
  code: string;
  custom: boolean;
}

/** A props colour value (palette index or [r, g, b]) → swatch. */
export function swatchOf(v: unknown, fallbackIndex = 0): Swatch {
  if (isRgb(v)) {
    const hex = rgbToHex(v);
    return { hex, name: t('Custom {hex}', { hex: hex.toUpperCase() }), code: 'RGB', custom: true };
  }
  const n = num(v, fallbackIndex);
  const c = colourByIndex(n);
  return { hex: c?.hex ?? null, name: c ? t(c.name) : t('Colour #{n}', { n }), code: `#${n}`, custom: false };
}

/** Approximate light colour of the GTA xenon presets (255 = stock). */
export const XENON_HEX: Record<number, string> = {
  255: '#f4f1e1',
  0: '#f3f6ff',
  1: '#3b6dff',
  2: '#19c8ff',
  3: '#62ffb4',
  4: '#9cff3c',
  5: '#ffe53b',
  6: '#ffc232',
  7: '#ff8a20',
  8: '#ff2b2b',
  9: '#ff80d2',
  10: '#ff2fa8',
  11: '#9c3dff',
  12: '#5a33ff',
};

/** Window tint → glass darkness (0-1) and tint colour for the glass swatch. */
export function tintLook(i: number): { alpha: number; rgb: string } {
  switch (i) {
    case 1:
      return { alpha: 0.94, rgb: '6,7,8' };
    case 2:
      return { alpha: 0.78, rgb: '10,12,14' };
    case 3:
      return { alpha: 0.48, rgb: '14,16,18' };
    case 4:
      return { alpha: 0.3, rgb: '14,16,18' };
    case 5:
      return { alpha: 0.86, rgb: '8,9,10' };
    case 6:
      return { alpha: 0.5, rgb: '20,70,40' };
    default:
      return { alpha: 0.08, rgb: '160,190,200' };
  }
}
