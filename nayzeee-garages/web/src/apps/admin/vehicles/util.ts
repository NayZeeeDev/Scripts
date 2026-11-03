/**
 * Player-vehicles admin helpers (no React): labels, garage options, row/detail conversion
 * and the installed-mod summary.
 *
 * Clearing values in AdminVehiclePatch: JSON null never reaches Lua (it decodes to nil =
 * "unchanged"), so clears are sent as `false` (impound, finance) or '' (nickname, garageKey).
 */
import { t } from '@/lib/i18n';
import type { IconName } from '@/components/ui';
import type { AdminOpenData, AdminVehicleDetail, AdminVehicleRow, VehicleState, VehicleType } from '@/lib/types';

export function vehicleTypeIcon(vt: VehicleType): IconName {
  return vt === 'sea' ? 'boat' : vt === 'air' ? 'plane' : 'car';
}

export function stateLabel(state: VehicleState): string {
  return state === 'garaged' ? t('In garage') : state === 'impounded' ? t('Impounded') : t('Not in garage');
}

/** "Yes" / "No" / "Impounded" for the detail panel. */
export function inGarageLabel(state: VehicleState): string {
  return state === 'garaged' ? t('Yes') : state === 'impounded' ? t('Impounded') : t('No');
}

export function ownerTypeLabel(type: 'player' | 'job' | 'gang'): string {
  return type === 'job' ? t('Job') : type === 'gang' ? t('Gang') : t('Player');
}

/** Ownership record source ("via") → readable label. */
export function viaLabel(via: string): string {
  switch (via) {
    case 'dealership':
      return t('Dealership');
    case 'admin':
      return t('Admin');
    case 'transfer':
      return t('Transfer');
    case 'sale':
      return t('Player sale');
    case 'purchase':
      return t('Purchase');
    case 'gift':
      return t('Gift');
    case 'import':
      return t('Import');
    case 'unknown':
    case '':
      return t('Unknown');
    default:
      return via.charAt(0).toUpperCase() + via.slice(1).replace(/[_-]+/g, ' ');
  }
}

export interface GarageOption {
  value: string;
  label: string;
  hint?: string;
  icon?: IconName;
}

/** Garages a vehicle can be assigned to: locations of kind garage / private as 'L<id>'. */
export function assignableGarages(data: AdminOpenData): GarageOption[] {
  return data.locations
    // Private garages store under group keys (G<id>) and spawner garages hold no personal
    // vehicles, so only public personal garages are valid 'L<id>' destinations here.
    .filter((l) => l.kind === 'garage' && l.source !== 'spawner' && l.id != null)
    .map((l) => ({
      value: `L${l.id}`,
      label: l.name,
      hint: [l.kind === 'private' ? t('Private') : t('Public'), l.vehicleType === 'sea' ? t('Boats') : l.vehicleType === 'air' ? t('Aircraft') : t('Cars')]
        .concat(l.enabled ? [] : [t('Disabled')])
        .join(' · '),
      icon: vehicleTypeIcon(l.vehicleType),
    }));
}

/**
 * The table row embedded in a detail response: every row field, including the VehicleLabel
 * extras (classId, classLabel, stats) the player list shows under the name.
 */
export function rowFromDetail(detail: AdminVehicleDetail): AdminVehicleRow {
  const { owner, ownerName, ownerType, job, gang, nickname, mileage, props, ...row } = detail.vehicle;
  return { ...row, financed: !!detail.finance };
}

/* ───────────────────────── installed mods ───────────────────────── */

export interface PerfMod {
  key: string;
  label: () => string;
  /** Number of upgrade levels (index 0..max-1); 0 = on/off toggle. */
  max: number;
}

export const PERF_MODS: PerfMod[] = [
  { key: 'modEngine', label: () => t('Engine'), max: 4 },
  { key: 'modBrakes', label: () => t('Brakes'), max: 3 },
  { key: 'modTransmission', label: () => t('Transmission'), max: 3 },
  { key: 'modSuspension', label: () => t('Suspension'), max: 4 },
  { key: 'modTurbo', label: () => t('Turbo'), max: 0 },
  { key: 'modArmor', label: () => t('Armour'), max: 5 },
];

export const num = (v: unknown, fallback = -1): number => {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string' && v.trim() !== '' && Number.isFinite(Number(v))) return Number(v);
  return fallback;
};

export const bool = (v: unknown): boolean => v === true || v === 1 || v === 'true';

/** Every `mod*` property that is installed (index ≥ 0 or switched on). */
export function installedModCount(props: Record<string, unknown>): number {
  let n = 0;
  for (const [k, v] of Object.entries(props)) {
    if (!k.startsWith('mod')) continue;
    if (typeof v === 'boolean' ? v : typeof v === 'number' && v >= 0) n++;
  }
  return n;
}

/** "Stock" / "Level 3" / "Installed" / "None". */
export function perfModValue(mod: PerfMod, props: Record<string, unknown>): { text: string; level: number; on: boolean } {
  const raw = props[mod.key];
  if (mod.max === 0) {
    const on = bool(raw);
    return { text: on ? t('Installed') : t('None'), level: on ? 1 : 0, on };
  }
  const v = num(raw);
  if (v < 0) return { text: t('Stock'), level: 0, on: false };
  return { text: t('Level {n}', { n: v + 1 }), level: v + 1, on: true };
}

/* ───────────────────────── misc ───────────────────────── */

/** Case-insensitive "contains" across several strings. */
export function matches(query: string, ...fields: (string | null | undefined)[]): boolean {
  const q = query.trim().toLowerCase();
  if (!q) return true;
  return fields.some((f) => !!f && f.toLowerCase().includes(q));
}

/** Unix seconds → "YYYY-MM-DD" (local time). */
export function isoDay(unix: number): string {
  const d = new Date((unix || Date.now() / 1000) * 1000);
  const p = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

/** "YYYY-MM-DD" → unix seconds at local noon, or null when invalid. */
export function parseIsoDay(text: string): number | null {
  const m = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(text.trim());
  if (!m) return null;
  const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), 12, 0, 0);
  if (d.getMonth() !== Number(m[2]) - 1 || d.getDate() !== Number(m[3])) return null;
  return Math.floor(d.getTime() / 1000);
}
