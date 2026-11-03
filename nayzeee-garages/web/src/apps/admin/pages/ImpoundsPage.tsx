/**
 * Admin › Impounds (kind 'impound') — table + map, create/edit.
 * Columns: Name, Vehicle, Jobs, Default fee.
 */
import { t } from '@/lib/i18n';
import { money } from '@/lib/format';
import type { AdminPageProps, ImpoundLocation } from '@/lib/types';
import { LocationListPage } from '../shared/LocationListPage';
import type { LocationColumn } from '../shared/LocationListPage';
import { rulesSummary } from '../shared/labels';

export function ImpoundsPage(props: AdminPageProps) {
  const { data } = props;
  const columns: LocationColumn<ImpoundLocation>[] = [
    {
      key: 'jobs',
      header: t('Jobs'),
      width: '30%',
      render: (l) => {
        const s = rulesSummary(l.jobs, data.jobs);
        return s ? <span title={s}>{s}</span> : <span className="nz-admin-locs__missing">{t('No jobs set')}</span>;
      },
    },
    {
      key: 'fee',
      header: t('Default fee'),
      width: '17%',
      align: 'right',
      render: (l) => <b className="nz-admin-locs__strong">{money(l.defaultFee)}</b>,
    },
  ];

  return (
    <LocationListPage<ImpoundLocation>
      {...props}
      kind="impound"
      columns={columns}
      searchText={(l) => `${rulesSummary(l.jobs, data.jobs)} ${l.society}`}
      emptyIcon="impound"
      emptyTitle={t('No impounds yet')}
      emptyDescription={t('Create an impound lot so staff can impound vehicles and owners can get them back.')}
    />
  );
}
