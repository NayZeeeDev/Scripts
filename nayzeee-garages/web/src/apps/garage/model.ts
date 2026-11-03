/**
 * Garage app helpers: display names, search / filter / sort, view memory, plate templates,
 * countdowns and a live clock. Pure functions + two tiny hooks; no UI.
 * Also used by the impound app (same owner).
 */
import { useEffect, useReducer, useState } from 'react';
import { useSettings, useUi } from '@/lib/store';
import { t } from '@/lib/i18n';
import type { IconName } from '@/components/ui';
import type { AppName, GarageVehicle, LocationKind, VehicleType } from '@/lib/types';

export type ViewMode = 'grid' | 'list';
export type GarageFilter = 'all' | 'favourites' | 'here' | 'shared' | 'impounded' | 'out';
export type GarageSort = 'relevance' | 'name' | 'mileage' | 'condition' | 'lastUsed';

export const vehicleTypeIcon = (type: VehicleType): IconName =>
  type === 'sea' ? 'boat' : type === 'air' ? 'plane' : 'car';

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

const norm = (s: string | null | undefined) => (s ?? '').toLowerCase();
const compact = (s: string | null | undefined) => norm(s).replace(/\s+/g, '');

/** Search by name, nickname, make, model and plate (plates ignore spaces). */
export function matchesQuery(
  v: { label: string; make?: string; model: string; plate: string; nickname?: string | null },
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
    compact(v.plate).includes(qc)
  );
}

export const isShared = (v: GarageVehicle) => !!v.sharedBy || v.sharedWith > 0;

export function matchesFilter(v: GarageVehicle, filter: GarageFilter): boolean {
  switch (filter) {
    case 'favourites':
      return v.favourite;
    case 'here':
      return v.here && v.state === 'garaged';
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
      // Relevance: parked here first, then favourites, then by name.
      const rank = (v: GarageVehicle) => (v.here && v.state === 'garaged' ? 0 : 2) + (v.favourite ? 0 : 1);
      return out.sort((a, b) => rank(a) - rank(b) || byName(a, b));
    }
  }
}

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

/** "2d 4h", "3h 12m", "12m 05s", "45s". */
export function countdown(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds));
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${String(m).padStart(2, '0')}m`;
  if (m > 0) return `${m}m ${String(sec).padStart(2, '0')}s`;
  return `${sec}s`;
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

/* ── list / grid choice remembered for the session (per app) ───────────── */

const viewMemory: Partial<Record<string, { view: ViewMode; basis: ViewMode }>> = {};

/**
 * View mode: settings.defaultView until the player picks one; the pick is remembered
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

/** Whether an app is still open (guards async results arriving after close). */
export const isAppOpen = (app: AppName) => useUi.getState().apps[app].open;
