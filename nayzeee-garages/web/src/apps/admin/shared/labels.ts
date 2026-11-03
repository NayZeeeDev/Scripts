/**
 * Admin shared labels & small pure helpers (no React).
 *
 * API
 * - vehicleTypeOptions(withAll?)       Select options for car/sea/air (+ 'all').
 * - vehicleTypeLabel(vt) / vehicleTypeIcon(vt)
 * - KIND_PAGE, kindTitle(kind), kindNoun(kind)       page ↔ kind mapping and nouns.
 * - accessModeLabel(mode), accessModeShort(mode), accessModeOptions()
 * - restrictionTypeLabel(type)
 * - findGroupInfo(list, name)          JobInfo by name.
 * - ruleLabel(rule, list)              "LSPD 2+" / "Mechanic".
 * - rulesSummary(rules, list)          "LSPD, Mechanic 1+" or '' when empty.
 * - locationAnchor(loc)                first open point (else first spawn point) or null.
 * - coordsText(v)                      "215.8, -810.1, 30.7".
 * - gradeOptions(info)                 Select options for a job's grades.
 * - plural(n, one, many)               t(one|many, { count: n }).
 * - capacityLabel(cap)                 "Unlimited" / "8 per player" / "20 in total".
 * - capacityTag(cap)                   directory card tag: { icon, label, short ("8" / "∞"), title }.
 * - restrictionSummary(r, data)        { type, detail } e.g. { 'Job', 'LSPD 2+, Mechanic' }.
 * - statsOf(data, loc)                 LocationStats (zeros when absent).
 * - vehicleTotal(stats, kind)          parked + out + impounded (impounds: held).
 * - stateLabel(loc)                    "Enabled" / "Disabled".
 * All strings go through t() at call time.
 */
import { t } from '@/lib/i18n';
import type { IconName } from '@/components/ui';
import type {
  AccessConfig,
  AdminOpenData,
  AdminPage,
  CapacityConfig,
  JobInfo,
  JobRule,
  Location,
  LocationKind,
  LocationStats,
  RestrictionConfig,
  Vec3,
  VehicleType,
} from '@/lib/types';

export type VehicleFilter = VehicleType | 'all';

export function vehicleTypeLabel(vt: VehicleType): string {
  return vt === 'sea' ? t('Sea') : vt === 'air' ? t('Air') : t('Car');
}

export function vehicleTypeIcon(vt: VehicleType): IconName {
  return vt === 'sea' ? 'boat' : vt === 'air' ? 'plane' : 'car';
}

export function vehicleTypeOptions(): { value: VehicleType; label: string; icon: IconName }[];
export function vehicleTypeOptions(withAll: true): { value: VehicleFilter; label: string; icon?: IconName }[];
export function vehicleTypeOptions(withAll = false) {
  const list = (['car', 'sea', 'air'] as VehicleType[]).map((v) => ({ value: v, label: vehicleTypeLabel(v), icon: vehicleTypeIcon(v) }));
  return withAll ? [{ value: 'all' as const, label: t('All vehicles'), icon: 'layers' as IconName }, ...list] : list;
}

export type LocationPageKind = Exclude<LocationKind, 'house'>;

export const KIND_PAGE: Record<LocationPageKind, AdminPage> = {
  garage: 'garages',
  job: 'jobs',
  private: 'private',
  impound: 'impounds',
};

/** "Garage", "Job garage", "Private garage", "Impound". */
export function kindNoun(kind: LocationKind): string {
  switch (kind) {
    case 'job':
      return t('Job garage');
    case 'private':
      return t('Private garage');
    case 'impound':
      return t('Impound');
    default:
      return t('Garage');
  }
}

export function kindTitle(kind: LocationKind): string {
  switch (kind) {
    case 'job':
      return t('Job & gang garages');
    case 'private':
      return t('Private garages');
    case 'impound':
      return t('Impounds');
    default:
      return t('Garages');
  }
}

export function accessModeLabel(mode: AccessConfig['mode']): string {
  return mode === 'interior' ? t('Interior') : mode === 'both' ? t('Interior & quick access') : t('Quick access');
}

/** Short form for table cells: "Quick menu", "Interior", "Interior + menu". */
export function accessModeShort(mode: AccessConfig['mode']): string {
  return mode === 'interior' ? t('Interior') : mode === 'both' ? t('Interior + menu') : t('Quick menu');
}

export function accessModeOptions(): { value: AccessConfig['mode']; label: string; hint: string; icon: IconName }[] {
  return [
    { value: 'quick', label: accessModeLabel('quick'), hint: t('Menu at the entrance'), icon: 'list' },
    { value: 'interior', label: accessModeLabel('interior'), hint: t('Walk-in garage only'), icon: 'door' },
    { value: 'both', label: accessModeLabel('both'), hint: t('Menu + Go inside'), icon: 'building' },
  ];
}

export function restrictionTypeLabel(type: RestrictionConfig['type']): string {
  switch (type) {
    case 'job':
      return t('Job');
    case 'gang':
      return t('Gang');
    case 'identifier':
      return t('Specific players');
    default:
      return t('Everyone');
  }
}

export function findGroupInfo(list: JobInfo[], name: string): JobInfo | undefined {
  return list.find((j) => j.name === name);
}

export function ruleLabel(rule: JobRule, list: JobInfo[]): string {
  const info = findGroupInfo(list, rule.name);
  const name = info?.label || rule.name;
  return rule.minGrade > 0 ? `${name} ${rule.minGrade}+` : name;
}

export function rulesSummary(rules: JobRule[], list: JobInfo[]): string {
  return rules.map((r) => ruleLabel(r, list)).join(', ');
}

export function gradeOptions(info: JobInfo | undefined): { value: number; label: string; hint?: string }[] {
  if (!info || !info.grades.length) return [{ value: 0, label: t('Any grade') }];
  return [...info.grades]
    .sort((a, b) => a.grade - b.grade)
    .map((g) => ({ value: g.grade, label: `${g.grade} · ${g.label}` }));
}

export function locationAnchor(loc: Location): Vec3 | null {
  const open = loc.openPoints?.[0]?.coords;
  if (open) return open;
  const spawn = loc.spawnPoints?.[0];
  return spawn ? { x: spawn.x, y: spawn.y, z: spawn.z } : null;
}

const fx = (n: number) => (Math.round(n * 10) / 10).toFixed(1);

export function coordsText(v: Vec3 | null | undefined): string {
  if (!v) return '—';
  return `${fx(v.x)}, ${fx(v.y)}, ${fx(v.z)}`;
}

export function plural(n: number, one: string, many: string): string {
  return t(n === 1 ? one : many, { count: n.toLocaleString('en-US') });
}

export function capacityLabel(cap: CapacityConfig): string {
  if (cap.mode !== 'limited') return t('Unlimited');
  return cap.appliesTo === 'total' ? t('{count} in total', { count: cap.spaces }) : t('{count} per player', { count: cap.spaces });
}

/** Capacity tag of a directory card; narrow screens show `short` (the number, or ∞). */
export function capacityTag(cap: CapacityConfig): { icon: IconName; label: string; short: string; title: string } {
  const label = capacityLabel(cap);
  return {
    icon: 'parking',
    label,
    short: cap.mode !== 'limited' ? '∞' : String(cap.spaces),
    title: t('Capacity: {value}', { value: label }),
  };
}

/** Who may use a public garage: type label + the rules / player count. */
export function restrictionSummary(r: RestrictionConfig, data: Pick<AdminOpenData, 'jobs' | 'gangs'>): { type: string; detail: string } {
  if (r.type === 'everyone') return { type: restrictionTypeLabel('everyone'), detail: '' };
  if (r.type === 'identifier') return { type: restrictionTypeLabel('identifier'), detail: plural(r.identifiers.length, '{count} player', '{count} players') };
  return { type: restrictionTypeLabel(r.type), detail: rulesSummary(r.rules, r.type === 'gang' ? data.gangs : data.jobs) };
}

const NO_STATS: LocationStats = { parked: 0, out: 0, impounded: 0, held: 0 };

export function statsOf(data: Pick<AdminOpenData, 'locationStats'>, loc: Location): LocationStats {
  if (loc.id === null) return NO_STATS;
  const s = data.locationStats?.[String(loc.id)];
  if (!s) return NO_STATS;
  return {
    parked: Number(s.parked) || 0,
    out: Number(s.out) || 0,
    impounded: Number(s.impounded) || 0,
    held: Number(s.held) || 0,
  };
}

export function vehicleTotal(s: LocationStats, kind: LocationKind): number {
  return kind === 'impound' ? s.held : s.parked + s.out + s.impounded;
}

export function stateLabel(loc: Pick<Location, 'enabled'>): string {
  return loc.enabled ? t('Enabled') : t('Disabled');
}
