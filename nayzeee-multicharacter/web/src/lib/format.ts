import { t } from '../i18n';

let cur = { locale: 'en-US', code: 'USD' };
let dateFmt = 'MM/DD/YYYY';

export function setFormat(currency?: { locale?: string; code?: string }, dateFormat?: string) {
  cur = { locale: currency?.locale || 'en-US', code: currency?.code || 'USD' };
  if (dateFormat) dateFmt = dateFormat;
}

export function money(n?: number): string {
  try {
    return new Intl.NumberFormat(cur.locale, { style: 'currency', currency: cur.code, maximumFractionDigits: 0 }).format(n || 0);
  } catch { return `$${Math.round(n || 0)}`; }
}

export function moneyCompact(n?: number): string {
  try {
    return new Intl.NumberFormat(cur.locale, {
      style: 'currency', currency: cur.code, notation: 'compact', maximumFractionDigits: (n || 0) >= 1e6 ? 2 : 1,
    }).format(n || 0);
  } catch { return money(n); }
}

const pad = (n: number) => String(n).padStart(2, '0');

/** 'YYYY-MM-DD' -> display format from Config.UI.dateFormat */
export function dateDisplay(iso?: string): string {
  if (!iso) return '—';
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso);
  if (!m) return iso;
  const [, y, mo, d] = m;
  if (dateFmt === 'DD/MM/YYYY') return `${d}/${mo}/${y}`;
  if (dateFmt === 'YYYY-MM-DD') return `${y}-${mo}-${d}`;
  return `${mo}/${d}/${y}`;
}

const toMs = (ts: number) => (ts < 1e12 ? ts * 1000 : ts);

export function relTime(ts?: number): string {
  if (!ts) return t('never_played');
  const diff = Math.max(0, Date.now() - toMs(ts)) / 1000;
  if (diff < 60) return t('just_now');
  if (diff < 3600) return t('min_ago', Math.floor(diff / 60));
  if (diff < 86400) return t('hours_ago', Math.floor(diff / 3600));
  if (diff < 86400 * 30) return t('days_ago', Math.floor(diff / 86400));
  return t('months_ago', Math.floor(diff / (86400 * 30)));
}

export function playtime(sec?: number): string {
  const s = sec || 0;
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  return h > 0 ? `${h}h ${pad(m)}m` : `${m}m`;
}

export function ageFrom(y: number, m: number, d: number): number {
  const now = new Date();
  let a = now.getFullYear() - y;
  if (now.getMonth() + 1 < m || (now.getMonth() + 1 === m && now.getDate() < d)) a--;
  return a;
}

export const two = (n: number) => pad(n);

export function initials(name?: string): string {
  if (!name) return '?';
  const p = name.trim().split(/\s+/);
  return ((p[0]?.[0] || '') + (p.length > 1 ? p[p.length - 1][0] : '')).toUpperCase();
}

export function hexToRgb(h: string): string | null {
  const m = /^#?([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(h.trim());
  if (!m) return null;
  let s = m[1];
  if (s.length === 3) s = s.split('').map((c) => c + c).join('');
  const n = parseInt(s, 16);
  return `${(n >> 16) & 255} ${(n >> 8) & 255} ${n & 255}`;
}

function shade(rgb: string, f: number): string {
  const [r, g, b] = rgb.split(' ').map(Number);
  const c = (v: number) => Math.max(0, Math.min(255, Math.round(f > 0 ? v + (255 - v) * f : v * (1 + f))));
  return `${c(r)} ${c(g)} ${c(b)}`;
}

/** Resolve Config.UI.accent ('teal' key or raw hex) into [hi, base, lo] "r g b" triplets. */
export function resolveAccent(accent?: string, accents?: Record<string, string[]>): [string, string, string] {
  const fallback: [string, string, string] = ['15 212 196', '8 175 162', '6 125 116'];
  if (!accent) return fallback;
  const set = accents?.[accent];
  if (set && set.length >= 2) {
    const base = hexToRgb(set[1]) || fallback[1];
    return [hexToRgb(set[0]) || shade(base, 0.25), base, hexToRgb(set[2] || '') || shade(base, -0.3)];
  }
  const base = hexToRgb(accent);
  if (!base) return fallback;
  return [shade(base, 0.25), base, shade(base, -0.3)];
}
