/**
 * Admin › Garages: public garages (kind 'garage') — table + map, import, create/edit.
 * Columns: Name, Vehicle, Access restriction, Access mode.
 */
import { Badge } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { AdminPageProps, GarageLocation } from '@/lib/types';
import { LocationListPage } from '../shared/LocationListPage';
import type { LocationColumn } from '../shared/LocationListPage';
import { accessModeLabel, restrictionTypeLabel, rulesSummary } from '../shared/labels';

export function GaragesPage(props: AdminPageProps) {
  const { data } = props;

  const restriction = (l: GarageLocation) => {
    const r = l.restriction;
    if (r.type === 'everyone') return { main: restrictionTypeLabel('everyone'), detail: '' };
    if (r.type === 'identifier') {
      return { main: restrictionTypeLabel('identifier'), detail: t('{count} players', { count: r.identifiers.length }) };
    }
    const list = r.type === 'gang' ? data.gangs : data.jobs;
    return { main: restrictionTypeLabel(r.type), detail: rulesSummary(r.rules, list) || t('none set') };
  };

  const interiorName = (id: number | null) => data.interiors.find((i) => i.id === id)?.name ?? null;

  const columns: LocationColumn<GarageLocation>[] = [
    {
      key: 'restriction',
      header: t('Access restriction'),
      width: '24%',
      render: (l) => {
        const r = restriction(l);
        return (
          <span title={r.detail ? `${r.main}: ${r.detail}` : r.main}>
            <b className="nz-admin-locs__strong">{r.main}</b>
            {r.detail && <span className="nz-admin-locs__detail"> · {r.detail}</span>}
          </span>
        );
      },
    },
    {
      key: 'access',
      header: t('Access mode'),
      width: '18%',
      render: (l) => {
        const name = l.access.mode !== 'quick' ? interiorName(l.access.interiorId) : null;
        return (
          <span title={name ? `${accessModeLabel(l.access.mode)} · ${name}` : accessModeLabel(l.access.mode)}>
            {accessModeLabel(l.access.mode)}
          </span>
        );
      },
    },
  ];

  return (
    <LocationListPage<GarageLocation>
      {...props}
      kind="garage"
      columns={columns}
      importable
      nameExtra={(l) =>
        l.source === 'spawner' ? (
          <Badge tone="blue" size="sm">
            {t('Spawner')}
          </Badge>
        ) : null
      }
      searchText={(l) => `${restriction(l).main} ${restriction(l).detail} ${l.restriction.identifiers.join(' ')}`}
      emptyIcon="garage"
      emptyTitle={t('No garages yet')}
      emptyDescription={t('Create your first public garage, or import the garages of the script you used before.')}
    />
  );
}
