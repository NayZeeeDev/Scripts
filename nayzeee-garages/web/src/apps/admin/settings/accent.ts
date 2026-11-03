/**
 * Accent preview helpers for Settings › Interface: the same --teal* variable family that
 * lib/theme.ts writes on :root, but returned as inline CSS variables so a preview box can show
 * an unsaved accent without recolouring the whole UI.
 */
import type { CSSProperties } from 'react';

export const DEFAULT_ACCENT = '#08afa2';

/** NayZeee teal first, then seven alternatives that read well on the dark surfaces. */
export const ACCENT_PRESETS = ['#08afa2', '#3b82f6', '#8b5cf6', '#ec4899', '#ef4444', '#f97316', '#eab308', '#22c55e'];

const HEX = /^#?([0-9a-f]{6})$/i;

export function isHex(v: string): boolean {
  return HEX.test(v.trim());
}

function parse(hex: string): [number, number, number] | null {
  const m = HEX.exec(hex.trim());
  if (!m) return null;
  const n = parseInt(m[1], 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

const toHex = (r: number, g: number, b: number) =>
  `#${[r, g, b].map((v) => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0')).join('')}`;

const mix = ([r, g, b]: [number, number, number], target: number, amount: number) =>
  toHex(r + (target - r) * amount, g + (target - g) * amount, b + (target - b) * amount);

/** Inline style that re-themes a subtree with `hex` (falls back to the default teal). */
export function accentVars(hex: string): CSSProperties {
  const rgb = parse(hex) ?? parse(DEFAULT_ACCENT)!;
  const [r, g, b] = rgb;
  const lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  return {
    '--teal': toHex(r, g, b),
    '--teal-hi': mix(rgb, 255, 0.22),
    '--teal-lo': mix(rgb, 0, 0.29),
    '--teal-rgb': `${r},${g},${b}`,
    '--teal-wash': `rgba(${r},${g},${b},.11)`,
    '--teal-edge': `rgba(${r},${g},${b},.34)`,
    '--on-teal': lum > 90 ? '#00201d' : '#ffffff',
  } as CSSProperties;
}

/** WCAG contrast of the accent against the window background (#08090a). */
export function contrastOnBase(hex: string): number {
  const rgb = parse(hex);
  if (!rgb) return 0;
  const lin = (c: number) => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  const l = 0.2126 * lin(rgb[0]) + 0.7152 * lin(rgb[1]) + 0.0722 * lin(rgb[2]);
  const base = 0.2126 * lin(8) + 0.7152 * lin(9) + 0.0722 * lin(10);
  return (l + 0.05) / (base + 0.05);
}
