/**
 * Admin shared labels & small pure helpers (no React).
 *
 * API
 * - vehicleTypeOptions(withAll?)       Select options for car/sea/air (+ 'all').
 * - vehicleTypeLabel(vt) / vehicleTypeIcon(vt)
 * - KIND_PAGE, kindTitle(kind), kindNoun(kind)       page ↔ kind mapping and nouns.
 * - accessModeLabel(mode), accessModeOptions()
 * - restrictionTypeLabel(type)
 * - findGroupInfo(list, name)          JobInfo by name.
 * - ruleLabel(rule, list)              "LSPD 2+" / "Mechanic".
 * - rulesSummary(rules, list)          "LSPD, Mechanic 1+" or '' when empty.
 * - locationAnchor(loc)                first open point (else first spawn point) or null.
 * - coordsText(v)                      "215.8, -810.1, 30.7".
 * - gradeOptions(info)                 Select options for a job's grades.
 * All strings go through t() at call time.
 */
import { t } from '@/lib/i18n';
import type { IconName } from '@/components/ui';
import type { AccessConfig, AdminPage, JobInfo, JobRule, Location, LocationKind, RestrictionConfig, Vec3, VehicleType } from '@/lib/types';

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
