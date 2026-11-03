/**
 * Admin › Impounds (kind 'impound') in the Map command (shared/LocationListPage).
 * Cards: operating jobs, default fee, release wait, society. KPIs: impounds, vehicles held,
 * job-restricted, default fee range.
 */
import { useCallback, useMemo } from 'react';
import { t } from '@/lib/i18n';
import { hoursLabel, money } from '@/lib/format';
import type { AdminPageProps, ImpoundLocation } from '@/lib/types';
import { LocationListPage } from '../shared/LocationListPage';
import type { CardTag, Fact, Kpi, LocationPageContext } from '../shared/LocationListPage';
import { plural, rulesSummary } from '../shared/labels';

const fmt = (n: number) => n.toLocaleString('en-US');

export function ImpoundsPage(props: AdminPageProps) {
  const { data } = props;
  const jobs = useCallback((l: ImpoundLocation) => rulesSummary(l.jobs, data.jobs), [data.jobs]);
  const waitText = (h: number) => (h > 0 ? t('{time} wait', { time: hoursLabel(h) }) : t('No wait'));

  const tags = useCallback(
    (l: ImpoundLocation): CardTag[] => {
      const s = jobs(l);
      const list: CardTag[] = [
        s ? { icon: 'shield', label: s, tone: 'blue' } : { icon: 'warning', label: t('No jobs set'), tone: 'red' },
        { icon: 'money', label: money(l.defaultFee), tone: 'teal', title: t('Default release fee') },
        { icon: 'clock', label: waitText(l.defaultHours) },
      ];
      if (l.society) list.push({ icon: 'briefcase', label: l.society, title: t('Fees go to the {society} society account', { society: l.society }) });
      return list;
    },
    [jobs],
  );

  const facts = useCallback(
    (l: ImpoundLocation): Fact[] => {
      const s = jobs(l);
      return [
        { label: t('Operated by'), value: s || t('No jobs set'), tone: s ? undefined : 'amber' },
        { label: t('Default fee'), value: money(l.defaultFee) },
        { label: t('Release wait'), value: l.defaultHours > 0 ? hoursLabel(l.defaultHours) : t('None') },
        { label: t('Fees go to'), value: l.society ? t('Society · {name}', { name: l.society }) : t('Nobody (removed)'), tone: l.society ? undefined : 'muted' },
      ];
    },
    [jobs],
  );

  const kpis = useCallback((all: ImpoundLocation[], ctx: LocationPageContext): Kpi[] => {
    let held = 0;
    let lots = 0;
    for (const l of all) {
      const h = ctx.stats(l).held;
      held += h;
      if (h > 0) lots += 1;
    }
    const enabled = all.filter((l) => l.enabled).length;
    const restricted = all.filter((l) => l.jobs.length > 0).length;
    const fees = all.map((l) => l.defaultFee);
    const lo = fees.length ? Math.min(...fees) : 0;
    const hi = fees.length ? Math.max(...fees) : 0;
    const hours = all.map((l) => l.defaultHours);
    const hLo = hours.length ? Math.min(...hours) : 0;
    const hHi = hours.length ? Math.max(...hours) : 0;
    return [
      {
        key: 'impounds',
        icon: 'impound',
        label: t('Impounds'),
        value: fmt(enabled),
        unit: `/ ${fmt(all.length)}`,
        sub: t('enabled'),
        ratio: all.length ? enabled / all.length : null,
      },
      {
        key: 'held',
        icon: 'lock',
        label: t('Vehicles held'),
        value: fmt(held),
        sub: plural(lots, 'in {count} lot', 'in {count} lots'),
        tone: 'red',
      },
      {
        key: 'restricted',
        icon: 'shield',
        label: t('Job-restricted'),
        value: fmt(restricted),
        unit: `/ ${fmt(all.length)}`,
        sub: all.length - restricted > 0 ? plural(all.length - restricted, '{count} without jobs', '{count} without jobs') : t('all have jobs'),
        tone: 'blue',
        ratio: all.length ? restricted / all.length : null,
      },
      {
        key: 'fees',
        icon: 'money',
        label: t('Default fee range'),
        value: fees.length ? (lo === hi ? money(lo) : `${money(lo)} – ${money(hi)}`) : '—',
        sub: !fees.length ? '' : hHi === 0 ? t('no wait') : hLo === hHi ? t('{time} wait', { time: hoursLabel(hLo) }) : t('wait {from} – {to}', { from: hoursLabel(hLo), to: hoursLabel(hHi) }),
        tone: 'amber',
      },
    ];
  }, []);

  const searchText = useCallback((l: ImpoundLocation) => `${jobs(l)} ${l.jobs.map((j) => j.name).join(' ')} ${l.society}`, [jobs]);
  const warning = useCallback((l: ImpoundLocation) => (l.jobs.length ? null : t('No jobs set: only admins can operate it')), []);
  const kindLabel = useMemo(() => () => t('Impound lot'), []);

  return (
    <LocationListPage<ImpoundLocation>
      {...props}
      kind="impound"
      kindLabel={kindLabel}
      tags={tags}
      facts={facts}
      factsTitle={t('Operation')}
      kpis={kpis}
      searchText={searchText}
      warning={warning}
      emptyIcon="impound"
      emptyTitle={t('No impounds yet')}
      emptyDescription={t('Create an impound lot so staff can impound vehicles and owners can get them back.')}
    />
  );
}
