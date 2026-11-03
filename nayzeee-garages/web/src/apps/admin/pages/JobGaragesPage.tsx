/**
 * Admin › Job & gang garages (kind 'job') in the Map command (shared/LocationListPage).
 * Cards: owner (job / gang + allowed groups), vehicle source (fleet / spawner), capacity, mode.
 * KPIs: fleet / spawner garages, fleet vehicles parked, out now, jobs covered.
 */
import { useCallback, useMemo } from 'react';
import { t } from '@/lib/i18n';
import type { AdminPageProps, JobLocation } from '@/lib/types';
import { LocationListPage } from '../shared/LocationListPage';
import type { CardTag, Fact, Kpi, LocationPageContext } from '../shared/LocationListPage';
import { accessModeLabel, accessModeShort, capacityLabel, findGroupInfo, plural, rulesSummary } from '../shared/labels';

const fmt = (n: number) => n.toLocaleString('en-US');

export function JobGaragesPage(props: AdminPageProps) {
  const { data } = props;
  const access = useCallback((l: JobLocation) => rulesSummary(l.jobs, l.owner === 'gang' ? data.gangs : data.jobs), [data]);

  const tags = useCallback(
    (l: JobLocation): CardTag[] => {
      const s = access(l);
      const gang = l.owner === 'gang';
      const list: CardTag[] = [
        s
          ? { icon: gang ? 'shield' : 'briefcase', label: `${gang ? t('Gang') : t('Job')} · ${s}`, tone: gang ? 'amber' : 'blue' }
          : { icon: 'warning', label: t('No jobs set'), tone: 'red' },
        l.source === 'spawner'
          ? { icon: 'key', label: t('Spawner · {count}', { count: l.spawner.length }), tone: 'teal', title: plural(l.spawner.length, '{count} vehicle to take out', '{count} vehicles to take out') }
          : { icon: 'garage', label: t('Shared fleet') },
        { icon: 'parking', label: capacityLabel(l.capacity) },
      ];
      if (l.access.mode !== 'quick') list.push({ icon: l.access.mode === 'interior' ? 'door' : 'building', label: accessModeShort(l.access.mode) });
      return list;
    },
    [access],
  );

  const facts = useCallback(
    (l: JobLocation): Fact[] => {
      const s = access(l);
      const list: Fact[] = [
        { label: l.owner === 'gang' ? t('Gang') : t('Job'), value: s || t('No jobs set'), tone: s ? undefined : 'amber' },
        {
          label: t('Vehicles'),
          value: l.source === 'spawner' ? plural(l.spawner.length, 'Spawner · {count} vehicle', 'Spawner · {count} vehicles') : t('Job-owned fleet'),
        },
      ];
      if (l.source === 'spawner') {
        list.push({ label: t('Spawns'), value: l.infiniteSpawns ? t('Unlimited at once') : t('One per player') });
        list.push({ label: t('Setup menu'), value: l.setupMenu ? t('Liveries & extras') : t('Off'), tone: l.setupMenu ? undefined : 'muted' });
      } else {
        list.push({ label: t('Capacity'), value: capacityLabel(l.capacity) });
        list.push({ label: t('Access mode'), value: accessModeLabel(l.access.mode) });
      }
      return list;
    },
    [access],
  );

  const kpis = useCallback(
    (all: JobLocation[], ctx: LocationPageContext): Kpi[] => {
      let fleetParked = 0;
      let out = 0;
      let impounded = 0;
      const fleets = all.filter((l) => l.source === 'owned');
      for (const l of all) {
        const s = ctx.stats(l);
        if (l.source === 'owned') fleetParked += s.parked;
        out += s.out;
        impounded += s.impounded;
      }
      const names = new Map<string, string>();
      for (const l of all) {
        const list = l.owner === 'gang' ? ctx.data.gangs : ctx.data.jobs;
        for (const r of l.jobs) names.set(`${l.owner}:${r.name}`, findGroupInfo(list, r.name)?.label || r.name);
      }
      const labels = [...names.values()].sort((a, b) => a.localeCompare(b));
      return [
        {
          key: 'garages',
          icon: 'briefcase',
          label: t('Fleet & spawner garages'),
          value: fmt(all.length),
          sub: t('{fleet} fleet · {spawner} spawner', { fleet: fleets.length, spawner: all.length - fleets.length }),
          ratio: all.length ? all.filter((l) => l.enabled).length / all.length : null,
        },
        {
          key: 'parked',
          icon: 'parking',
          label: t('Fleet vehicles parked'),
          value: fmt(fleetParked),
          sub: plural(fleets.length, 'in {count} fleet', 'in {count} fleets'),
        },
        {
          key: 'out',
          icon: 'route',
          label: t('Out now'),
          value: fmt(out),
          sub: impounded ? plural(impounded, '{count} impounded', '{count} impounded') : t('none impounded'),
          tone: 'amber',
        },
        {
          key: 'jobs',
          icon: 'users',
          label: t('Jobs covered'),
          value: fmt(labels.length),
          sub: labels.length ? labels.join(', ') : t('none yet'),
          tone: 'blue',
        },
      ];
    },
    [],
  );

  const searchText = useCallback(
    (l: JobLocation) => `${access(l)} ${l.jobs.map((j) => j.name).join(' ')} ${l.owner} ${l.spawner.map((v) => `${v.model} ${v.label}`).join(' ')}`,
    [access],
  );

  const warning = useCallback((l: JobLocation) => (l.jobs.length ? null : t('No job or gang set: nobody can use it')), []);
  const kindLabel = useMemo(() => (l: JobLocation) => (l.owner === 'gang' ? t('Gang garage') : t('Job garage')), []);

  return (
    <LocationListPage<JobLocation>
      {...props}
      kind="job"
      kindLabel={kindLabel}
      tags={tags}
      facts={facts}
      factsTitle={t('Fleet & access')}
      kpis={kpis}
      searchText={searchText}
      warning={warning}
      emptyIcon="briefcase"
      emptyTitle={t('No job or gang garages yet')}
      emptyDescription={t('Give a job or gang its own fleet, or a spawner with vehicles per grade.')}
    />
  );
}
