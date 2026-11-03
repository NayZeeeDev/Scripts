/**
 * Admin › Job & gang garages (kind 'job') — table + map, create/edit.
 * Columns: Name, Vehicle, Type (job/gang), Vehicle source, Access (job names).
 */
import { Badge } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { AdminPageProps, JobLocation } from '@/lib/types';
import { LocationListPage } from '../shared/LocationListPage';
import type { LocationColumn } from '../shared/LocationListPage';
import { rulesSummary } from '../shared/labels';

export function JobGaragesPage(props: AdminPageProps) {
  const { data } = props;
  const access = (l: JobLocation) => rulesSummary(l.jobs, l.owner === 'gang' ? data.gangs : data.jobs);

  const columns: LocationColumn<JobLocation>[] = [
    {
      key: 'type',
      header: t('Type'),
      width: 68,
      render: (l) =>
        l.owner === 'gang' ? (
          <Badge tone="amber" size="sm">
            {t('Gang')}
          </Badge>
        ) : (
          <Badge tone="teal" size="sm">
            {t('Job')}
          </Badge>
        ),
    },
    {
      key: 'source',
      header: t('Vehicle source'),
      width: '21%',
      render: (l) =>
        l.source === 'spawner' ? (
          <span>
            {t('Spawner')}
            <span className="nz-admin-locs__detail"> · {l.spawner.length}</span>
          </span>
        ) : (
          t('Job-owned')
        ),
    },
    {
      key: 'access',
      header: t('Access'),
      width: '16%',
      render: (l) => {
        const s = access(l);
        return s ? <span title={s}>{s}</span> : <span className="nz-admin-locs__missing">{t('No jobs set')}</span>;
      },
    },
  ];

  return (
    <LocationListPage<JobLocation>
      {...props}
      kind="job"
      columns={columns}
      searchText={(l) => `${access(l)} ${l.jobs.map((j) => j.name).join(' ')} ${l.spawner.map((v) => v.model).join(' ')}`}
      emptyIcon="briefcase"
      emptyTitle={t('No job or gang garages yet')}
      emptyDescription={t('Give a job or gang its own fleet, or a spawner with vehicles per grade.')}
    />
  );
}
