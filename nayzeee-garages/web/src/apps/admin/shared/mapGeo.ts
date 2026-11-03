/**
 * World map geometry for the admin map (web/public/maps/*.webp, docs/REDESIGN.md §4).
 *
 * All three map images (1500×2000) share one frame. World (GTA x/y) ↔ image pixels:
 *   px = 0.16576 · x + 690.4        py = 1348.4 − 0.164 · y
 *
 * API
 * - MAP_W, MAP_H                    image size in px.
 * - worldToImage(x, y)              → { x, y } image px (origin top-left).
 * - imageToWorld(px, py)            → { x, y } world.
 * - MAP_STYLES / MapStyle           'satellite' | 'dark' | 'atlas' with label, file and sea colour.
 * - readMapStyle() / writeMapStyle  remembered per viewer (localStorage, try/catch).
 * - scaleBar(pxPerWorld, unit)      a round distance for the scale bar ({ px, label }).
 * - formatCoord(n)                  "215.4" / "−810.2" (true minus sign, one decimal).
 * No React here.
 */
import { t } from '@/lib/i18n';

export const MAP_W = 1500;
export const MAP_H = 2000;

const AX = 0.16576;
const BX = 690.4;
const AY = 0.164;
const BY = 1348.4;

/** World units per image px (horizontal); used to size distances on screen. */
export const IMAGE_PX_PER_WORLD = AX;

export function worldToImage(x: number, y: number): { x: number; y: number } {
  return { x: AX * x + BX, y: BY - AY * y };
}

export function imageToWorld(px: number, py: number): { x: number; y: number } {
  return { x: (px - BX) / AX, y: (BY - py) / AY };
}

export type MapStyle = 'satellite' | 'dark' | 'atlas';

export interface MapStyleInfo {
  value: MapStyle;
  label: () => string;
  src: string;
}

export const MAP_STYLES: MapStyleInfo[] = [
  { value: 'satellite', label: () => t('Satellite'), src: './maps/satellite.webp' },
  { value: 'dark', label: () => t('Dark'), src: './maps/dark.webp' },
  { value: 'atlas', label: () => t('Atlas'), src: './maps/atlas.webp' },
];

const STYLE_KEY = 'nz-admin-map-style';

export function readMapStyle(): MapStyle {
  try {
    const v = window.localStorage.getItem(STYLE_KEY);
    if (v === 'satellite' || v === 'dark' || v === 'atlas') return v;
  } catch {
    /* storage unavailable */
  }
  return 'dark';
}

export function writeMapStyle(v: MapStyle) {
  try {
    window.localStorage.setItem(STYLE_KEY, v);
  } catch {
    /* storage unavailable */
  }
}

const METRIC = [25, 50, 100, 250, 500, 1000, 2000, 5000];
const IMPERIAL_FT = [100, 250, 500, 1000, 2000];
const IMPERIAL_MI = [0.5, 1, 2, 5];
const FT = 0.3048;
const MI = 1609.344;

/**
 * Pick a round distance whose bar is between ~56 and ~130 screen px.
 * `pxPerWorld`: screen px per world unit (1 world unit ≈ 1 metre in GTA).
 */
export function scaleBar(pxPerWorld: number, unit: 'km' | 'mi'): { px: number; label: string } {
  const target = 96;
  if (unit === 'mi') {
    const options = [...IMPERIAL_FT.map((f) => ({ m: f * FT, label: `${f} ft` })), ...IMPERIAL_MI.map((m) => ({ m: m * MI, label: `${m} mi` }))];
    let best = options[0];
    for (const o of options) if (Math.abs(o.m * pxPerWorld - target) < Math.abs(best.m * pxPerWorld - target)) best = o;
    return { px: best.m * pxPerWorld, label: best.label };
  }
  let best = METRIC[0];
  for (const m of METRIC) if (Math.abs(m * pxPerWorld - target) < Math.abs(best * pxPerWorld - target)) best = m;
  return { px: best * pxPerWorld, label: best >= 1000 ? `${best / 1000} km` : `${best} m` };
}

export function formatCoord(n: number): string {
  const s = (Math.round(n * 10) / 10).toFixed(1);
  return s.startsWith('-') ? `−${s.slice(1)}` : s;
}
