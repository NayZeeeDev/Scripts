/**
 * Key ring model: grouping, labels, countdowns, distances, sorting (the player's key order) and
 * range status of KeyEntry rows. Pure helpers (no React). Everything the server decides stays
 * the server's (lock range, shareability, tracker access): these only describe what the data says.
 */
import { t } from '@/lib/i18n';
import type { ImmobiliserLevel, KeyEntry, KeyGroup, KeyLive, KeyMode, KeyTracking, KeysOpenData, PlayerKeySettings } from '@/lib/types';

export const GROUPS: KeyGroup[] = ['owned', 'shared', 'temp', 'items'];

export type KeyFilter = 'all' | KeyGroup;
export type KeyOrder = PlayerKeySettings['keyOrder'];
/** Distance unit of the key ring: the player's setting (metric / imperial) as the format unit. */
export type Unit = 'km' | 'mi';

export const unitOf = (units: PlayerKeySettings['units'] | null | undefined, fallback: Unit): Unit =>
  units === 'imperial' ? 'mi' : units === 'metric' ? 'km' : fallback;

export function chipLabel(g: KeyFilter): string {
  switch (g) {
    case 'all':
      return t('All');
    case 'owned':
      return t('Owned');
    case 'shared':
      return t('Shared');
    case 'temp':
      return t('Temporary');
    default:
      return t('Items');
  }
}

/** Where the key sits, as the detail pane says it. */
export function groupLabel(g: KeyGroup): string {
  switch (g) {
    case 'owned':
      return t('Owned');
    case 'shared':
      return t('Shared with you');
    case 'temp':
      return t('Temporary');
    default:
      return t('Key item');
  }
}

export function orderLabel(o: KeyOrder): string {
  switch (o) {
    case 'name':
      return t('Name');
    case 'plate':
      return t('Plate');
    case 'distance':
      return t('Distance');
    default:
      return t('Recently used');
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
  glyph: Glyph;
  tone: 'white' | 'teal' | 'amber' | 'neutral';
}

/** Badge of a key: Key / Fob (physical items), Temporary, Virtual (owner access or given). */
export function kindInfo(k: Pick<KeyEntry, 'kind'>): KindInfo {
  switch (k.kind) {
    case 'item':
      return { label: t('Key'), glyph: 'key', tone: 'white' };
    case 'fob':
      return { label: t('Fob'), glyph: 'fob', tone: 'teal' };
    case 'temp':
      return { label: t('Temporary'), glyph: 'clock', tone: 'amber' };
    default:
      return { label: t('Virtual'), glyph: 'link', tone: 'neutral' };
  }
}

/** Fob artwork of a key: a plain key for keys of standard profiles, else the key's design. */
export function fobOf(k: Pick<KeyEntry, 'keyType' | 'design' | 'kind'>): { design: string; kind: 'key' | 'fob' } {
  const fob = k.keyType === 'fob' || k.kind === 'fob';
  return { design: fob ? (k.design || 'classic') : 'key', kind: fob ? 'fob' : 'key' };
}

export function immobiliserLabel(level: ImmobiliserLevel | null | undefined): string {
  switch (level) {
    case 'ghost':
      return t('Ghost PIN');
    case 'standard':
      return t('Standard');
    default:
      return t('None');
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
  if (s < 10) return t('just now');
  if (s < 60) return t('{n} s ago', { n: s });
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
    case 'share':
      return t('Shared by the owner');
    case 'compat':
    case 'export':
      return t('Given by another service');
    default:
      return t('Temporary access');
  }
}

/** Metres in, "12 m" / "1.4 km" or "40 ft" / "0.9 mi" out. */
export function meters(m: number | null | undefined, unit: Unit): string {
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
    engine: k.engine ?? null,
    immobiliser: k.immobiliser ?? 'none',
    usedAt: k.usedAt ?? null,
  };
  if (l) {
    out = {
      ...out,
      spawned: true,
      distance: l.distance ?? out.distance,
      locked: l.locked ?? out.locked,
      alarm: l.alarm ?? out.alarm,
      engine: l.engine ?? out.engine,
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

export function matchesQuery(k: KeyEntry, q: string): boolean {
  const query = q.trim().toLowerCase();
  if (!query) return true;
  const hay = [k.plate, k.nickname ?? '', k.label ?? '', k.make ?? '', k.model ?? '', k.classLabel ?? '', k.profileLabel]
    .join(' ')
    .toLowerCase();
  return query.split(/\s+/).every((part) => hay.includes(part) || hay.replace(/\s+/g, '').includes(part));
}

const byName = (a: KeyEntry, b: KeyEntry) => displayName(a).localeCompare(displayName(b)) || a.plate.localeCompare(b.plate);

/** Vehicles out and near first, then out far, then not out (distance order, and the tie break of the others). */
function byDistance(a: KeyEntry, b: KeyEntry): number {
  const rank = (k: KeyEntry) => (k.towing ? 3 : !k.spawned ? 4 : k.distance === null ? 2 : 1);
  const r = rank(a) - rank(b);
  if (r !== 0) return r;
  if (a.distance !== null && b.distance !== null && a.distance !== b.distance) return a.distance - b.distance;
  return byName(a, b);
}

/** The ring in the player's key order (PlayerKeySettings.keyOrder). */
export function sortKeys(list: KeyEntry[], order: KeyOrder): KeyEntry[] {
  const out = [...list];
  switch (order) {
    case 'name':
      return out.sort(byName);
    case 'plate':
      return out.sort((a, b) => a.plate.localeCompare(b.plate));
    case 'distance':
      return out.sort(byDistance);
    default:
      // recently used first; keys never used keep the distance order behind them
      return out.sort((a, b) => {
        const ua = a.usedAt ?? 0;
        const ub = b.usedAt ?? 0;
        if (ua !== ub) return ub - ua;
        return byDistance(a, b);
      });
  }
}

/** Seconds left on a temporary key now, from the seconds left when the data arrived. */
export function leftNow(k: Pick<KeyEntry, 'expiresIn'>, receivedAt: number, now: number): number | null {
  if (k.expiresIn === null || k.expiresIn === undefined) return null;
  return Math.max(0, k.expiresIn - Math.floor((now - receivedAt) / 1000));
}

/** What sharing does in this key mode (docs/V2_CHANGES.md G.1). */
export function shareInfo(k: KeyEntry, mode: KeysOpenData['mode'], keyMode: KeyMode | null | undefined) {
  if (mode === 'virtual' || keyMode === 'virtual') {
    return {
      action: t('Share access'),
      title: t('Share access'),
      what: t('A virtual key of this vehicle'),
      effect: t('They can lock, unlock and drive it until you revoke the key. You keep yours.'),
      done: (name: string, vehicle: string) => t('{name} has a key of {vehicle} now.', { name, vehicle }),
    };
  }
  if (keyMode === 'limited') {
    return {
      action: t('Hand over'),
      title: t('Hand your key over'),
      what: k.kind === 'fob' ? t('Your fob item') : t('Your key item'),
      effect: t('The item leaves your pockets: you need another key to use the vehicle.'),
      done: (name: string, vehicle: string) => t('You handed the key of {vehicle} to {name}.', { name, vehicle }),
    };
  }
  return {
    action: t('Give a copy'),
    title: t('Give keys'),
    what: k.kind === 'fob' ? t('A copy of your fob') : t('A copy of your key'),
    effect: t('They get their own copy. You keep yours.'),
    done: (name: string, vehicle: string) => t('{name} got a copy of the key of {vehicle}.', { name, vehicle }),
  };
}

/** Engine / windows from the fob need an electronic fob (server rule: nz:carlock:remote). */
export function remoteCapable(k: KeyEntry): boolean {
  if (k.towing || !k.spawned) return false;
  if (k.kind === 'fob') return true;
  if (k.kind === 'item') return false; // a plain key item never works remotely
  // a crime's temporary key (hotwire, robbery...) is no fob; a service's is
  if (k.kind === 'temp' && !SERVICE_REASONS.has(k.reason ?? '')) return false;
  return k.keyType === 'fob';
}

/** Temporary key reasons of a service (server: CarLock.isServiceKey). */
const SERVICE_REASONS = new Set(['garage', 'spawner', 'admin', 'contract', 'export', 'assist', 'rekey', 'share']);
