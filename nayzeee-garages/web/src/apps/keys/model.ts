/**
 * Key ring model: grouping, labels, countdowns, distances and range status of KeyEntry rows.
 * Pure helpers (no React). Everything the server decides stays the server's (lock range,
 * shareability): these only describe what the data says.
 */
import { t } from '@/lib/i18n';
import type { KeyEntry, KeyGroup, KeyLive, KeyTracking, KeysOpenData } from '@/lib/types';

export const GROUPS: KeyGroup[] = ['owned', 'shared', 'temp', 'items'];

export type KeyFilter = 'all' | KeyGroup;

export function groupLabel(g: KeyGroup): string {
  switch (g) {
    case 'owned':
      return t('Owned');
    case 'shared':
      return t('Shared with you');
    case 'temp':
      return t('Temporary');
    default:
      return t('Key items');
  }
}

export function chipLabel(g: KeyFilter): string {
  switch (g) {
    case 'all':
      return t('All');
    case 'owned':
      return t('Owned');
    case 'shared':
      return t('Shared');
    case 'temp':
      return t('Temp');
    default:
      return t('Items');
  }
}

/** Nickname, else the model label, else a neutral word (a temporary key of a car not out). */
export function displayName(k: { nickname?: string | null; label?: string | null }): string {
  const nick = (k.nickname ?? '').trim();
  if (nick) return nick;
  const label = (k.label ?? '').trim();
  return label || t('Unknown vehicle');
}

export type Glyph = 'key' | 'fob' | 'clock' | 'link';

export interface KindInfo {
  label: string;
  short: string;
  glyph: Glyph;
  tone: 'white' | 'teal' | 'amber' | 'blue';
}

/** Badge of a key: Key / Fob (physical items), Temporary, Virtual (owner access or given). */
export function kindInfo(k: Pick<KeyEntry, 'kind'>): KindInfo {
  switch (k.kind) {
    case 'item':
      return { label: t('Key'), short: t('Key'), glyph: 'key', tone: 'white' };
    case 'fob':
      return { label: t('Fob'), short: t('Fob'), glyph: 'fob', tone: 'teal' };
    case 'temp':
      return { label: t('Temporary'), short: t('Temp'), glyph: 'clock', tone: 'amber' };
    default:
      return { label: t('Virtual'), short: t('Virtual'), glyph: 'link', tone: 'blue' };
  }
}

/** "2h 14m", "14m 05s", "45s"; long keys "3d 4h". */
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

/** "just now", "5 min ago", "3 h ago", "2 days ago". */
export function ago(seconds: number | null | undefined): string {
  if (seconds === null || seconds === undefined) return t('some time ago');
  const s = Math.max(0, Math.floor(seconds));
  if (s < 60) return t('just now');
  if (s < 3600) return t('{n} min ago', { n: Math.floor(s / 60) });
  if (s < 86400) return t('{n} h ago', { n: Math.floor(s / 3600) });
  const d = Math.floor(s / 86400);
  return d === 1 ? t('yesterday') : t('{n} days ago', { n: d });
}

/** How a key was obtained: a temporary key's reason or a key item's crime origin. */
export function reasonLabel(reason: string | null | undefined): string {
  switch (reason) {
    case 'hotwire':
      return t('Hotwired');
    case 'robbery':
      return t('Taken from the driver');
    case 'assist':
      return t('Handed over by the driver');
    case 'search':
      return t('Spare key found inside');
    case 'admin':
      return t('Given by staff');
    case 'garage':
      return t('Garage hand-out');
    case 'spawner':
      return t('Job / rental vehicle');
    case 'locksmith':
      return t('Cut by a back-alley locksmith');
    case 'rekey':
      return t('Temporary key after new locks');
    case 'contract':
      return t('Sale contract');
    case 'compat':
    case 'export':
      return t('Given by another service');
    default:
      return t('Temporary access');
  }
}

/** How the player got this key, for keys that came with a reason (a temporary key, a crime's
 *  key item: back-alley copy, spare key found in a search). */
export function howObtained(k: Pick<KeyEntry, 'kind' | 'reason'>): string {
  if (k.kind === 'temp' || k.reason === 'locksmith' || k.reason === 'search') return reasonLabel(k.reason);
  return t('Key of unknown origin');
}

/** Metres in, "12 m" / "1.4 km" or "40 ft" / "0.9 mi" out (settings distance unit). */
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

/** The entry with what this client sees right now (live) and the tracker's readout on top. */
export function merged(k: KeyEntry, live: KeysOpenData['live'], tracking: KeyTracking | null | undefined): KeyEntry {
  const l: KeyLive | undefined = live && !Array.isArray(live) ? live[k.plate] : undefined;
  // Lua drops nil fields: unknown values arrive missing, the UI works with null
  let out: KeyEntry = {
    ...k,
    nickname: k.nickname ?? null,
    netId: k.netId ?? null,
    locked: k.locked ?? null,
    distance: k.distance ?? null,
    expiresIn: k.expiresIn ?? null,
    reason: k.reason ?? null,
    image: k.image ?? null,
    label: k.label ?? '',
    make: k.make ?? '',
    trackerAccess: k.trackerAccess !== false,
  };
  if (l) {
    out = {
      ...out,
      spawned: true,
      distance: l.distance ?? out.distance,
      locked: l.locked ?? out.locked,
      alarm: l.alarm ?? out.alarm,
    };
  }
  if (tracking && tracking.plate === k.plate && !tracking.lost && !tracking.stopped && tracking.distance !== null && !l) {
    out = { ...out, distance: tracking.distance };
  }
  return out;
}

/** Lock range of a key: fob range for remote profiles, else the key range (server rule). */
export function rangeOf(k: Pick<KeyEntry, 'remote'>, ranges: KeysOpenData['ranges']): number {
  return k.remote ? ranges.fob : ranges.key;
}

export type RangeState = 'in' | 'out' | 'unknown' | 'none';

/** Is the vehicle within lock range as far as this client knows? (the server decides) */
export function rangeState(k: KeyEntry, ranges: KeysOpenData['ranges'], seatPlate?: string | false | null): RangeState {
  if (!k.spawned || k.towing) return 'none';
  if (seatPlate && seatPlate === k.plate) return 'in';
  if (k.distance === null || k.distance === undefined) return 'unknown';
  return k.distance <= rangeOf(k, ranges) ? 'in' : 'out';
}

export function matchesQuery(k: KeyEntry, q: string): boolean {
  const query = q.trim().toLowerCase();
  if (!query) return true;
  const hay = [k.plate, k.nickname ?? '', k.label ?? '', k.make ?? '', k.model ?? '', k.classLabel ?? '', k.profileLabel]
    .join(' ')
    .toLowerCase();
  return query.split(/\s+/).every((part) => hay.includes(part) || hay.replace(/\s+/g, '').includes(part));
}

/** Out and near first, then out far, then not out; by name inside. */
export function sortKeys(list: KeyEntry[]): KeyEntry[] {
  const rank = (k: KeyEntry) => (k.towing ? 3 : !k.spawned ? 4 : k.distance === null ? 2 : 1);
  return [...list].sort((a, b) => {
    const r = rank(a) - rank(b);
    if (r !== 0) return r;
    if (a.distance !== null && b.distance !== null && a.distance !== b.distance) return a.distance - b.distance;
    return displayName(a).localeCompare(displayName(b));
  });
}

/** Seconds left on a temporary key now, from the seconds left when the data arrived. */
export function leftNow(k: Pick<KeyEntry, 'expiresIn'>, receivedAt: number, now: number): number | null {
  if (k.expiresIn === null || k.expiresIn === undefined) return null;
  return Math.max(0, k.expiresIn - Math.floor((now - receivedAt) / 1000));
}
