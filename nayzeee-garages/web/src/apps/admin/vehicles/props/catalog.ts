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

/** The classic GTA paint palette (index → name, approximate swatch colour). Indexes above 159 show as "Colour #n". */
export const GTA_COLOURS: { index: number; name: string; hex: string }[] = [
  { index: 0, name: 'Metallic Black', hex: '#0d1116' },
  { index: 1, name: 'Metallic Graphite Black', hex: '#1c1d21' },
  { index: 2, name: 'Metallic Black Steel', hex: '#32383d' },
  { index: 3, name: 'Metallic Dark Silver', hex: '#454b4f' },
  { index: 4, name: 'Metallic Silver', hex: '#999da0' },
  { index: 5, name: 'Metallic Blue Silver', hex: '#c2c4c6' },
  { index: 6, name: 'Metallic Steel Grey', hex: '#979a97' },
  { index: 7, name: 'Metallic Shadow Silver', hex: '#637380' },
  { index: 8, name: 'Metallic Stone Silver', hex: '#63625c' },
  { index: 9, name: 'Metallic Midnight Silver', hex: '#3c3f47' },
  { index: 10, name: 'Metallic Gun Metal', hex: '#444e54' },
  { index: 11, name: 'Metallic Anthracite Grey', hex: '#1d2129' },
  { index: 12, name: 'Matte Black', hex: '#13181f' },
  { index: 13, name: 'Matte Grey', hex: '#26282a' },
  { index: 14, name: 'Matte Light Grey', hex: '#515554' },
  { index: 15, name: 'Util Black', hex: '#151921' },
  { index: 16, name: 'Util Black Poly', hex: '#1e2429' },
  { index: 17, name: 'Util Dark Silver', hex: '#333a3c' },
  { index: 18, name: 'Util Silver', hex: '#8c9095' },
  { index: 19, name: 'Util Gun Metal', hex: '#39434d' },
  { index: 20, name: 'Util Shadow Silver', hex: '#506272' },
  { index: 21, name: 'Worn Black', hex: '#1e232f' },
  { index: 22, name: 'Worn Graphite', hex: '#363a3f' },
  { index: 23, name: 'Worn Silver Grey', hex: '#a0a199' },
  { index: 24, name: 'Worn Silver', hex: '#d3d3d3' },
  { index: 25, name: 'Worn Blue Silver', hex: '#b7bfca' },
  { index: 26, name: 'Worn Shadow Silver', hex: '#778794' },
  { index: 27, name: 'Metallic Red', hex: '#c00e1a' },
  { index: 28, name: 'Metallic Torino Red', hex: '#da1918' },
  { index: 29, name: 'Metallic Formula Red', hex: '#b6111b' },
  { index: 30, name: 'Metallic Blaze Red', hex: '#a51e23' },
  { index: 31, name: 'Metallic Graceful Red', hex: '#7b1a22' },
  { index: 32, name: 'Metallic Garnet Red', hex: '#8e1b1f' },
  { index: 33, name: 'Metallic Desert Red', hex: '#6f1818' },
  { index: 34, name: 'Metallic Cabernet Red', hex: '#6b0f19' },
  { index: 35, name: 'Metallic Candy Red', hex: '#b60f25' },
  { index: 36, name: 'Metallic Sunrise Orange', hex: '#f78616' },
  { index: 37, name: 'Metallic Classic Gold', hex: '#c2944f' },
  { index: 38, name: 'Metallic Orange', hex: '#f8a42b' },
  { index: 39, name: 'Matte Red', hex: '#cf1f21' },
  { index: 40, name: 'Matte Dark Red', hex: '#732021' },
  { index: 41, name: 'Matte Orange', hex: '#f27d20' },
  { index: 42, name: 'Matte Yellow', hex: '#ffc91f' },
  { index: 43, name: 'Util Red', hex: '#9c1016' },
  { index: 44, name: 'Util Bright Red', hex: '#de0f18' },
  { index: 45, name: 'Util Garnet Red', hex: '#8f1e17' },
  { index: 46, name: 'Worn Red', hex: '#a94744' },
  { index: 47, name: 'Worn Golden Red', hex: '#b16c51' },
  { index: 48, name: 'Worn Dark Red', hex: '#371c25' },
  { index: 49, name: 'Metallic Dark Green', hex: '#132428' },
  { index: 50, name: 'Metallic Racing Green', hex: '#122e2b' },
  { index: 51, name: 'Metallic Sea Green', hex: '#12383c' },
  { index: 52, name: 'Metallic Olive Green', hex: '#31423f' },
  { index: 53, name: 'Metallic Green', hex: '#155c2d' },
  { index: 54, name: 'Metallic Gasoline Blue Green', hex: '#1b6770' },
  { index: 55, name: 'Matte Lime Green', hex: '#66b81f' },
  { index: 56, name: 'Util Dark Green', hex: '#22383e' },
  { index: 57, name: 'Util Green', hex: '#1d5a3f' },
  { index: 58, name: 'Worn Dark Green', hex: '#2d423f' },
  { index: 59, name: 'Worn Green', hex: '#45594b' },
  { index: 60, name: 'Worn Sea Wash', hex: '#65867f' },
  { index: 61, name: 'Metallic Midnight Blue', hex: '#222e46' },
  { index: 62, name: 'Metallic Dark Blue', hex: '#233155' },
  { index: 63, name: 'Metallic Saxony Blue', hex: '#304c7e' },
  { index: 64, name: 'Metallic Blue', hex: '#2354a1' },
  { index: 65, name: 'Metallic Mariner Blue', hex: '#637ba7' },
  { index: 66, name: 'Metallic Harbor Blue', hex: '#394762' },
  { index: 67, name: 'Metallic Diamond Blue', hex: '#d6e7f1' },
  { index: 68, name: 'Metallic Surf Blue', hex: '#76afbe' },
  { index: 69, name: 'Metallic Nautical Blue', hex: '#345e72' },
  { index: 70, name: 'Metallic Bright Blue', hex: '#0b9cf1' },
  { index: 71, name: 'Metallic Purple Blue', hex: '#2f2d52' },
  { index: 72, name: 'Metallic Spinnaker Blue', hex: '#282c4d' },
  { index: 73, name: 'Metallic Ultra Blue', hex: '#2446a8' },
  { index: 74, name: 'Metallic Light Blue', hex: '#6ea3c6' },
  { index: 75, name: 'Util Dark Blue', hex: '#112552' },
  { index: 76, name: 'Util Midnight Blue', hex: '#1b203e' },
  { index: 77, name: 'Util Blue', hex: '#275190' },
  { index: 78, name: 'Util Sea Foam Blue', hex: '#608592' },
  { index: 79, name: 'Util Lightning Blue', hex: '#2446a8' },
  { index: 80, name: 'Util Maui Blue Poly', hex: '#4271e1' },
  { index: 81, name: 'Util Bright Blue', hex: '#3b39e0' },
  { index: 82, name: 'Matte Dark Blue', hex: '#1f2852' },
  { index: 83, name: 'Matte Blue', hex: '#253aa7' },
  { index: 84, name: 'Matte Midnight Blue', hex: '#1c3551' },
  { index: 85, name: 'Worn Dark Blue', hex: '#4c5f81' },
  { index: 86, name: 'Worn Blue', hex: '#58688e' },
  { index: 87, name: 'Worn Light Blue', hex: '#74b5d8' },
  { index: 88, name: 'Metallic Taxi Yellow', hex: '#ffcf20' },
  { index: 89, name: 'Metallic Race Yellow', hex: '#fbe212' },
  { index: 90, name: 'Metallic Bronze', hex: '#916532' },
  { index: 91, name: 'Metallic Yellow Bird', hex: '#e0e13d' },
  { index: 92, name: 'Metallic Lime', hex: '#98d223' },
  { index: 93, name: 'Metallic Champagne', hex: '#e9dcb5' },
  { index: 94, name: 'Metallic Pueblo Beige', hex: '#503218' },
  { index: 95, name: 'Metallic Dark Ivory', hex: '#473f2b' },
  { index: 96, name: 'Metallic Chocolate Brown', hex: '#221b19' },
  { index: 97, name: 'Metallic Golden Brown', hex: '#653f23' },
  { index: 98, name: 'Metallic Light Brown', hex: '#775c3e' },
  { index: 99, name: 'Metallic Straw Beige', hex: '#ac9975' },
  { index: 100, name: 'Metallic Moss Brown', hex: '#6c6b4b' },
  { index: 101, name: 'Metallic Biston Brown', hex: '#402e2b' },
  { index: 102, name: 'Metallic Beechwood', hex: '#a4965f' },
  { index: 103, name: 'Metallic Dark Beechwood', hex: '#46231a' },
  { index: 104, name: 'Metallic Choco Orange', hex: '#752b19' },
  { index: 105, name: 'Metallic Beach Sand', hex: '#bfae7b' },
  { index: 106, name: 'Metallic Sun Bleached Sand', hex: '#dfd5b2' },
  { index: 107, name: 'Metallic Cream', hex: '#f7edd5' },
  { index: 108, name: 'Util Brown', hex: '#3a2a1b' },
  { index: 109, name: 'Util Medium Brown', hex: '#785f33' },
  { index: 110, name: 'Util Light Brown', hex: '#b5a079' },
  { index: 111, name: 'Metallic White', hex: '#fffff6' },
  { index: 112, name: 'Metallic Frost White', hex: '#eaeaea' },
  { index: 113, name: 'Worn Honey Beige', hex: '#b0ab94' },
  { index: 114, name: 'Worn Brown', hex: '#453831' },
  { index: 115, name: 'Worn Dark Brown', hex: '#2a282b' },
  { index: 116, name: 'Worn Straw Beige', hex: '#726c57' },
  { index: 117, name: 'Brushed Steel', hex: '#6a747c' },
  { index: 118, name: 'Brushed Black Steel', hex: '#354158' },
  { index: 119, name: 'Brushed Aluminium', hex: '#9ba0a8' },
  { index: 120, name: 'Chrome', hex: '#b0b0b0' },
  { index: 121, name: 'Worn Off White', hex: '#eae6de' },
  { index: 122, name: 'Util Off White', hex: '#dfddd0' },
  { index: 123, name: 'Worn Orange', hex: '#f2ad2e' },
  { index: 124, name: 'Worn Light Orange', hex: '#f9a458' },
  { index: 125, name: 'Metallic Securicor Green', hex: '#83c566' },
  { index: 126, name: 'Worn Taxi Yellow', hex: '#f1cc40' },
  { index: 127, name: 'Police Car Blue', hex: '#4cc3da' },
  { index: 128, name: 'Matte Green', hex: '#4e6443' },
  { index: 129, name: 'Matte Brown', hex: '#bcac8f' },
  { index: 130, name: 'Worn Pale Orange', hex: '#f8b658' },
  { index: 131, name: 'Matte White', hex: '#fcf9f1' },
  { index: 132, name: 'Worn White', hex: '#fffffb' },
  { index: 133, name: 'Worn Olive Army Green', hex: '#81844c' },
  { index: 134, name: 'Pure White', hex: '#ffffff' },
  { index: 135, name: 'Hot Pink', hex: '#f21f99' },
  { index: 136, name: 'Salmon Pink', hex: '#fdd6cd' },
  { index: 137, name: 'Metallic Vermillion Pink', hex: '#df5891' },
  { index: 138, name: 'Orange', hex: '#f6ae20' },
  { index: 139, name: 'Green', hex: '#b0ee6e' },
  { index: 140, name: 'Blue', hex: '#08e9fa' },
  { index: 141, name: 'Metallic Black Blue', hex: '#0a0c17' },
  { index: 142, name: 'Metallic Black Purple', hex: '#0c0d18' },
  { index: 143, name: 'Metallic Black Red', hex: '#0e0d14' },
  { index: 144, name: 'Hunter Green', hex: '#9f9e8a' },
  { index: 145, name: 'Metallic Purple', hex: '#621276' },
  { index: 146, name: 'Metallic Very Dark Blue', hex: '#0b1421' },
  { index: 147, name: 'Carbon Black', hex: '#0b0b0d' },
  { index: 148, name: 'Matte Purple', hex: '#6b1f7b' },
  { index: 149, name: 'Matte Dark Purple', hex: '#1e1d22' },
  { index: 150, name: 'Metallic Lava Red', hex: '#bc1917' },
  { index: 151, name: 'Matte Forest Green', hex: '#2d362a' },
  { index: 152, name: 'Matte Olive Drab', hex: '#696748' },
  { index: 153, name: 'Matte Desert Brown', hex: '#7a6c55' },
  { index: 154, name: 'Matte Desert Tan', hex: '#c3b492' },
  { index: 155, name: 'Matte Foliage Green', hex: '#5a6352' },
  { index: 156, name: 'Default Alloy', hex: '#c9c9c9' },
  { index: 157, name: 'Epsilon Blue', hex: '#afd6e4' },
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
      const c = colourByIndex(n);
      return c ? t(c.name) : t('Colour #{n}', { n });
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
