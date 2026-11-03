/**
 * Vehicle props catalogue for the props editor: categories, fields (ox_lib property names),
 * defaults, GTA colour / enum tables, and helpers to count and describe non-default values.
 */
import { t } from '@/lib/i18n';
import type { IconName } from '@/components/ui';
import { bool, num } from '../util';

export type Props = Record<string, unknown>;
export type Rgb = [number, number, number];

export type FieldDef =
  | { key: string; kind: 'mod'; label: () => string; levels: number; prefix: 'level' | 'option' | 'rim' }
  | { key: string; kind: 'toggle'; label: () => string }
  | { key: string; kind: 'colour'; label: () => string }
  | { key: string; kind: 'paint'; label: () => string }
  | { key: string; kind: 'rgb'; label: () => string; fallback: Rgb }
  | { key: string; kind: 'enum'; label: () => string; options: () => { value: number; label: string }[]; fallback: number }
  | { key: string; kind: 'float'; label: () => string; min: number; max: number; step: number }
  | { key: string; kind: 'neon'; label: () => string }
  | { key: string; kind: 'extras'; label: () => string };

export interface Category {
  id: string;
  label: () => string;
  description: () => string;
  icon: IconName;
  fields: FieldDef[];
}

/* ───────────────────────── tables ───────────────────────── */

/** A selection of the GTA paint palette (index → name, approximate swatch). */
export const GTA_COLOURS: { index: number; name: string; hex: string }[] = [
  { index: 0, name: 'Metallic Black', hex: '#0d1116' },
  { index: 1, name: 'Metallic Graphite Black', hex: '#1c1d21' },
  { index: 2, name: 'Metallic Black Steel', hex: '#32383d' },
  { index: 3, name: 'Metallic Dark Silver', hex: '#454b4f' },
  { index: 4, name: 'Metallic Silver', hex: '#999da0' },
  { index: 5, name: 'Metallic Blue Silver', hex: '#c2c4c6' },
  { index: 6, name: 'Metallic Steel Grey', hex: '#979a97' },
  { index: 7, name: 'Metallic Shadow Silver', hex: '#637380' },
  { index: 11, name: 'Metallic Anthracite Grey', hex: '#1d2129' },
  { index: 12, name: 'Matte Black', hex: '#13181f' },
  { index: 13, name: 'Matte Grey', hex: '#26282a' },
  { index: 27, name: 'Metallic Red', hex: '#c00e1a' },
  { index: 28, name: 'Metallic Torino Red', hex: '#da1918' },
  { index: 29, name: 'Metallic Formula Red', hex: '#b6111b' },
  { index: 34, name: 'Metallic Cabernet Red', hex: '#6b0f19' },
  { index: 36, name: 'Metallic Sunrise Orange', hex: '#f78616' },
  { index: 37, name: 'Metallic Classic Gold', hex: '#c2944f' },
  { index: 38, name: 'Metallic Orange', hex: '#f8a42b' },
  { index: 49, name: 'Metallic Dark Green', hex: '#132428' },
  { index: 50, name: 'Metallic Racing Green', hex: '#122e2b' },
  { index: 53, name: 'Metallic Green', hex: '#155c2d' },
  { index: 55, name: 'Matte Lime Green', hex: '#66b81f' },
  { index: 61, name: 'Metallic Midnight Blue', hex: '#222e46' },
  { index: 62, name: 'Metallic Dark Blue', hex: '#233155' },
  { index: 64, name: 'Metallic Blue', hex: '#2354a1' },
  { index: 70, name: 'Metallic Bright Blue', hex: '#0b9cf1' },
  { index: 73, name: 'Metallic Ultra Blue', hex: '#2446a8' },
  { index: 88, name: 'Metallic Taxi Yellow', hex: '#ffcf20' },
  { index: 89, name: 'Metallic Race Yellow', hex: '#fbe212' },
  { index: 93, name: 'Metallic Champagne', hex: '#e9dcb5' },
  { index: 96, name: 'Metallic Chocolate Brown', hex: '#221b19' },
  { index: 111, name: 'Metallic Frost White', hex: '#fffff6' },
  { index: 112, name: 'Metallic White', hex: '#eaeaea' },
  { index: 120, name: 'Chrome', hex: '#b0b0b0' },
  { index: 135, name: 'Hot Pink', hex: '#f21f99' },
  { index: 137, name: 'Metallic Vermillion Pink', hex: '#df5891' },
  { index: 145, name: 'Metallic Purple', hex: '#621276' },
  { index: 147, name: 'Carbon Black', hex: '#0b0b0d' },
  { index: 156, name: 'Default Alloy', hex: '#c9c9c9' },
  { index: 158, name: 'Pure Gold', hex: '#7a6440' },
  { index: 159, name: 'Brushed Gold', hex: '#7f6a48' },
];

export const colourByIndex = (i: number) => GTA_COLOURS.find((c) => c.index === i) ?? null;

const WHEEL_TYPES = () => [
  { value: 0, label: t('Sport') },
  { value: 1, label: t('Muscle') },
  { value: 2, label: t('Lowrider') },
  { value: 3, label: t('SUV') },
  { value: 4, label: t('Offroad') },
  { value: 5, label: t('Tuner') },
  { value: 6, label: t('Bike') },
  { value: 7, label: t('High end') },
  { value: 8, label: t("Benny's Original") },
  { value: 9, label: t("Benny's Bespoke") },
  { value: 10, label: t('Open wheel') },
  { value: 11, label: t('Street') },
  { value: 12, label: t('Track') },
];

const PLATE_STYLES = () => [
  { value: 0, label: t('Blue on white 1') },
  { value: 1, label: t('Yellow on black') },
  { value: 2, label: t('Yellow on blue') },
  { value: 3, label: t('Blue on white 2') },
  { value: 4, label: t('Blue on white 3') },
  { value: 5, label: t('North Yankton') },
];

const WINDOW_TINTS = () => [
  { value: -1, label: t('Stock') },
  { value: 0, label: t('None') },
  { value: 1, label: t('Pure black') },
  { value: 2, label: t('Dark smoke') },
  { value: 3, label: t('Light smoke') },
  { value: 4, label: t('Stock tint') },
  { value: 5, label: t('Limo') },
  { value: 6, label: t('Green') },
];

const XENON_COLOURS = () => [
  { value: 255, label: t('Default') },
  { value: 0, label: t('White') },
  { value: 1, label: t('Blue') },
  { value: 2, label: t('Electric blue') },
  { value: 3, label: t('Mint green') },
  { value: 4, label: t('Lime green') },
  { value: 5, label: t('Yellow') },
  { value: 6, label: t('Golden shower') },
  { value: 7, label: t('Orange') },
  { value: 8, label: t('Red') },
  { value: 9, label: t('Pony pink') },
  { value: 10, label: t('Hot pink') },
  { value: 11, label: t('Purple') },
  { value: 12, label: t('Blacklight') },
];

const LIVERIES = () => [{ value: -1, label: t('None') }, ...Array.from({ length: 12 }, (_, i) => ({ value: i, label: t('Livery {n}', { n: i + 1 }) }))];

/* ───────────────────────── categories ───────────────────────── */

const mod = (key: string, label: () => string, levels: number, prefix: 'level' | 'option' | 'rim' = 'option'): FieldDef => ({
  key,
  kind: 'mod',
  label,
  levels,
  prefix,
});

const cosmetic = (key: string, label: () => string) => mod(key, label, 10, 'option');

export const CATEGORIES: Category[] = [
  {
    id: 'colours',
    label: () => t('Colours'),
    description: () => t('Paint, pearlescent and interior'),
    icon: 'palette',
    fields: [
      { key: 'color1', kind: 'paint', label: () => t('Primary colour') },
      { key: 'color2', kind: 'paint', label: () => t('Secondary colour') },
      { key: 'pearlescentColor', kind: 'colour', label: () => t('Pearlescent') },
      { key: 'wheelColor', kind: 'colour', label: () => t('Wheel colour') },
      { key: 'interiorColor', kind: 'colour', label: () => t('Interior colour') },
      { key: 'dashboardColor', kind: 'colour', label: () => t('Dashboard colour') },
    ],
  },
  {
    id: 'performance',
    label: () => t('Performance'),
    description: () => t('Engine, brakes, suspension and more'),
    icon: 'gauge',
    fields: [
      mod('modEngine', () => t('Engine'), 4, 'level'),
      mod('modBrakes', () => t('Brakes'), 3, 'level'),
      mod('modTransmission', () => t('Transmission'), 3, 'level'),
      mod('modSuspension', () => t('Suspension'), 4, 'level'),
      mod('modArmor', () => t('Armour'), 5, 'level'),
      { key: 'modTurbo', kind: 'toggle', label: () => t('Turbo') },
    ],
  },
  {
    id: 'cosmetics',
    label: () => t('Cosmetics'),
    description: () => t('Body kits, spoilers and styling'),
    icon: 'spray',
    fields: [
      cosmetic('modSpoilers', () => t('Spoiler')),
      cosmetic('modFrontBumper', () => t('Front bumper')),
      cosmetic('modRearBumper', () => t('Rear bumper')),
      cosmetic('modSideSkirt', () => t('Side skirts')),
      cosmetic('modExhaust', () => t('Exhaust')),
      cosmetic('modFrame', () => t('Roll cage')),
      cosmetic('modGrille', () => t('Grille')),
      cosmetic('modHood', () => t('Hood')),
      cosmetic('modFender', () => t('Left fender')),
      cosmetic('modRightFender', () => t('Right fender')),
      cosmetic('modRoof', () => t('Roof')),
      cosmetic('modHorns', () => t('Horn')),
      cosmetic('modVanityPlate', () => t('Vanity plate')),
      cosmetic('modTrimA', () => t('Trim')),
      cosmetic('modOrnaments', () => t('Ornaments')),
      cosmetic('modDashboard', () => t('Dashboard')),
      cosmetic('modDial', () => t('Dials')),
      cosmetic('modDoorSpeaker', () => t('Door speakers')),
      cosmetic('modSeats', () => t('Seats')),
      cosmetic('modSteeringWheel', () => t('Steering wheel')),
      cosmetic('modShifterLeavers', () => t('Shifter')),
      cosmetic('modAPlate', () => t('Plate holder')),
      cosmetic('modSpeakers', () => t('Speakers')),
      cosmetic('modTrunk', () => t('Trunk')),
      cosmetic('modHydrolic', () => t('Hydraulics')),
      cosmetic('modEngineBlock', () => t('Engine block')),
      cosmetic('modAirFilter', () => t('Air filter')),
      cosmetic('modStruts', () => t('Struts')),
      cosmetic('modArchCover', () => t('Arch covers')),
      cosmetic('modAerials', () => t('Aerials')),
      cosmetic('modTrimB', () => t('Wings')),
      cosmetic('modTank', () => t('Fuel tank')),
      cosmetic('modWindows', () => t('Windows')),
    ],
  },
  {
    id: 'wheels',
    label: () => t('Wheels'),
    description: () => t('Wheel type, rims and tyres'),
    icon: 'wheel',
    fields: [
      { key: 'wheels', kind: 'enum', label: () => t('Wheel type'), options: WHEEL_TYPES, fallback: 0 },
      mod('modFrontWheels', () => t('Front rims'), 30, 'rim'),
      mod('modBackWheels', () => t('Rear rims'), 30, 'rim'),
      { key: 'modCustomTiresF', kind: 'toggle', label: () => t('Custom tyres') },
      { key: 'wheelWidth', kind: 'float', label: () => t('Wheel width'), min: 0, max: 2, step: 0.01 },
      { key: 'wheelSize', kind: 'float', label: () => t('Wheel size'), min: 0, max: 2, step: 0.01 },
    ],
  },
  {
    id: 'liveries',
    label: () => t('Liveries and glass'),
    description: () => t('Liveries, plate and window tint'),
    icon: 'layers',
    fields: [
      mod('modLivery', () => t('Livery (mod)'), 12, 'option'),
      { key: 'livery', kind: 'enum', label: () => t('Livery'), options: LIVERIES, fallback: -1 },
      { key: 'plateIndex', kind: 'enum', label: () => t('Plate style'), options: PLATE_STYLES, fallback: 0 },
      { key: 'windowTint', kind: 'enum', label: () => t('Window tint'), options: WINDOW_TINTS, fallback: -1 },
    ],
  },
  {
    id: 'lights',
    label: () => t('Lights and tyres'),
    description: () => t('Xenons, neon and tyre smoke'),
    icon: 'bulb',
    fields: [
      { key: 'modXenon', kind: 'toggle', label: () => t('Xenon headlights') },
      { key: 'xenonColor', kind: 'enum', label: () => t('Xenon colour'), options: XENON_COLOURS, fallback: 255 },
      { key: 'neonEnabled', kind: 'neon', label: () => t('Neon') },
      { key: 'neonColor', kind: 'rgb', label: () => t('Neon colour'), fallback: [255, 0, 255] },
      { key: 'modSmokeEnabled', kind: 'toggle', label: () => t('Tyre smoke') },
      { key: 'tyreSmokeColor', kind: 'rgb', label: () => t('Tyre smoke colour'), fallback: [255, 255, 255] },
    ],
  },
  {
    id: 'extras',
    label: () => t('Extras'),
    description: () => t('Toggle factory extras on or off'),
    icon: 'sliders',
    fields: [{ key: 'extras', kind: 'extras', label: () => t('Extras') }],
  },
];

/* ───────────────────────── value helpers ───────────────────────── */

export const isRgb = (v: unknown): v is Rgb =>
  Array.isArray(v) && v.length >= 3 && v.slice(0, 3).every((x) => typeof x === 'number' && Number.isFinite(x));

export const rgbToHex = (c: Rgb) =>
  `#${c
    .slice(0, 3)
    .map((x) => Math.max(0, Math.min(255, Math.round(x))).toString(16).padStart(2, '0'))
    .join('')}`;

export function hexToRgb(hex: string): Rgb | null {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex.trim());
  if (!m) return null;
  const n = parseInt(m[1], 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

export function neonList(v: unknown): [boolean, boolean, boolean, boolean] {
  const a = Array.isArray(v) ? v : [];
  return [bool(a[0]), bool(a[1]), bool(a[2]), bool(a[3])];
}

/**
 * Extras as { id: on }. Booleans are taken as-is; numbers follow ox_lib (0 = on, 1 = off).
 * A Lua table with keys 1..n arrives as a JSON array, so arrays map index i → id i + 1.
 */
export function extrasMap(v: unknown): Record<string, boolean> {
  if (!v || typeof v !== 'object') return {};
  const entries: [string, unknown][] = Array.isArray(v)
    ? v.map((x, i) => [String(i + 1), x] as [string, unknown]).filter(([, x]) => x !== null && x !== undefined)
    : Object.entries(v as Record<string, unknown>);
  const out: Record<string, boolean> = {};
  for (const [k, x] of entries) out[k] = typeof x === 'number' ? x === 0 : bool(x);
  return out;
}

/** True when the vehicle stores extras the ox_lib way (numbers) rather than booleans. */
export function extrasNumeric(v: unknown): boolean {
  const vals = Array.isArray(v) ? v : v && typeof v === 'object' ? Object.values(v as object) : [];
  return vals.some((x) => typeof x === 'number');
}

/** Whether a field holds a non-default value (drives the category count badges). */
export function isSet(f: FieldDef, props: Props): boolean {
  const v = props[f.key];
  switch (f.kind) {
    case 'mod':
      return num(v) >= 0;
    case 'toggle':
      return bool(v);
    case 'colour':
      return v !== undefined && num(v, 0) !== 0;
    case 'paint':
      return isRgb(v) || (v !== undefined && num(v, 0) !== 0);
    case 'rgb':
      return isRgb(v) && rgbToHex(v as Rgb) !== rgbToHex(f.fallback);
    case 'enum':
      return v !== undefined && num(v, f.fallback) !== f.fallback;
    case 'float':
      return typeof v === 'number';
    case 'neon':
      return neonList(v).some(Boolean);
    case 'extras':
      return Object.values(extrasMap(v)).some(Boolean);
  }
}

export function countSet(cat: Category, props: Props): number {
  if (cat.id === 'extras') return Object.values(extrasMap(props.extras)).filter(Boolean).length;
  return cat.fields.filter((f) => isSet(f, props)).length;
}

export function modOptionLabel(prefix: 'level' | 'option' | 'rim', i: number): string {
  if (prefix === 'level') return t('Level {n}', { n: i + 1 });
  if (prefix === 'rim') return t('Rim {n}', { n: i + 1 });
  return t('Option {n}', { n: i + 1 });
}

/** Short human description of a field value ("Level 3", "Metallic Black", "#08AFA2"…). */
export function describe(f: FieldDef, props: Props): string {
  const v = props[f.key];
  switch (f.kind) {
    case 'mod': {
      const n = num(v);
      if (n < 0) return t('Stock');
      return n < f.levels ? modOptionLabel(f.prefix, n) : t('Custom ({n})', { n });
    }
    case 'toggle':
      return bool(v) ? t('On') : t('Off');
    case 'colour':
    case 'paint': {
      if (isRgb(v)) return rgbToHex(v).toUpperCase();
      const n = num(v, 0);
      return colourByIndex(n)?.name ?? t('Colour #{n}', { n });
    }
    case 'rgb':
      return isRgb(v) ? rgbToHex(v).toUpperCase() : rgbToHex(f.fallback).toUpperCase();
    case 'enum': {
      const n = num(v, f.fallback);
      return f.options().find((o) => o.value === n)?.label ?? t('Custom ({n})', { n });
    }
    case 'float':
      return typeof v === 'number' ? v.toFixed(2) : t('Default');
    case 'neon': {
      const names = [t('Left'), t('Right'), t('Front'), t('Back')];
      const on = neonList(v)
        .map((b, i) => (b ? names[i] : null))
        .filter(Boolean);
      return on.length ? on.join(', ') : t('Off');
    }
    case 'extras': {
      const on = Object.entries(extrasMap(v))
        .filter(([, b]) => b)
        .map(([k]) => k);
      return on.length ? t('Extras {list}', { list: on.join(', ') }) : t('None');
    }
  }
}
