/**
 * Accent colour support. The default accent is NayZeee teal (#08afa2). Admins can change
 * it in Settings > Interface; we derive the hi/lo/wash/edge variants as CSS variables.
 */

function parseHex(hex: string): [number, number, number] | null {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex.trim());
  if (!m) return null;
  const n = parseInt(m[1], 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function toHex(r: number, g: number, b: number) {
  const c = (v: number) => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0');
  return `#${c(r)}${c(g)}${c(b)}`;
}

function mix([r, g, b]: [number, number, number], target: number, amount: number) {
  return toHex(r + (target - r) * amount, g + (target - g) * amount, b + (target - b) * amount);
}

/** Write --teal, --teal-hi, --teal-lo, --teal-rgb, --teal-wash, --teal-edge, --on-teal on :root. */
export function applyAccent(hex: string) {
  const rgb = parseHex(hex) ?? parseHex('#08afa2')!;
  const root = document.documentElement.style;
  const [r, g, b] = rgb;
  root.setProperty('--teal', toHex(r, g, b));
  root.setProperty('--teal-hi', mix(rgb, 255, 0.22));
  root.setProperty('--teal-lo', mix(rgb, 0, 0.29));
  root.setProperty('--teal-rgb', `${r},${g},${b}`);
  root.setProperty('--teal-wash', `rgba(${r},${g},${b},.11)`);
  root.setProperty('--teal-edge', `rgba(${r},${g},${b},.34)`);
  // Dark text on light accents, white on very dark accents.
  const lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  root.setProperty('--on-teal', lum > 90 ? '#00201d' : '#ffffff');
}
