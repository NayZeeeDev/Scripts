/** Dossier tabs (order = keyboard shortcuts 1-7). */
import { t } from '@/lib/i18n';
import type { IconName } from '@/components/ui';

export type DossierTab = 'overview' | 'condition' | 'upgrades' | 'finance' | 'history' | 'activity' | 'data';

export const DOSSIER_TABS: { value: DossierTab; label: () => string; icon: IconName }[] = [
  { value: 'overview', label: () => t('Overview'), icon: 'eye' },
  { value: 'condition', label: () => t('Condition'), icon: 'gauge' },
  { value: 'upgrades', label: () => t('Upgrades & paint'), icon: 'palette' },
  { value: 'finance', label: () => t('Finance'), icon: 'money' },
  { value: 'history', label: () => t('History'), icon: 'history' },
  { value: 'activity', label: () => t('Activity'), icon: 'list' },
  { value: 'data', label: () => t('Data'), icon: 'code' },
];

export const isDossierTab = (v: unknown): v is DossierTab => DOSSIER_TABS.some((x) => x.value === v);
