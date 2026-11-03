/**
 * Admin › Garages: public garages (kind 'garage') in the Map command (shared/LocationListPage).
 * Cards: access restriction, access mode, capacity, spawner. KPIs: locations, vehicles parked,
 * out right now, with interior. Import is available here.
 */
import { useCallback, useMemo } from 'react';
import { t } from '@/lib/i18n';
import type { AdminPageProps, GarageLocation } from '@/lib/types';
import { LocationListPage } from '../shared/LocationListPage';
import type { CardTag, Fact, Kpi, LocationPageContext } from '../shared/LocationListPage';
import { accessModeLabel, accessModeShort, capacityLabel, capacityTag, plural, restrictionSummary } from '../shared/labels';

const fmt = (n: number) => n.toLocaleString('en-US');

export function GaragesPage(props: AdminPageProps) {
  const { data } = props;

  const interiorName = useCallback((id: number | null) => data.interiors.find((i) => i.id === id)?.name ?? null, [data.interiors]);

  const restrictionTag = useCallback(
    (l: GarageLocation): CardTag => {
      const r = restrictionSummary(l.restriction, data);
      switch (l.restriction.type) {
        case 'job':
          return { icon: 'briefcase', label: r.detail ? `${r.type} · ${r.detail}` : t('Job · none set'), tone: r.detail ? 'blue' : 'amber' };
        case 'gang':
          return { icon: 'shield', label: r.detail ? `${r.type} · ${r.detail}` : t('Gang · none set'), tone: r.detail ? 'amber' : 'red' };
        case 'identifier':
          return { icon: 'user', label: r.detail, tone: 'white' };
        default:
          return { icon: 'users', label: r.type };
      }
    },
    [data],
  );

  const tags = useCallback(
    (l: GarageLocation): CardTag[] => {
      const list: CardTag[] = [restrictionTag(l)];
      if (l.source === 'spawner') list.push({ icon: 'key', label: t('Spawner · {count}', { count: l.spawner.length }), tone: 'teal', title: t('Spawner: {count} vehicles to take out', { count: l.spawner.length }) });
      list.push({
        icon: l.access.mode === 'quick' ? 'list' : l.access.mode === 'interior' ? 'door' : 'building',
        label: accessModeShort(l.access.mode),
        title: l.access.mode !== 'quick' ? `${accessModeLabel(l.access.mode)} · ${interiorName(l.access.interiorId) ?? t('no interior chosen')}` : undefined,
      });
      list.push(capacityTag(l.capacity));
      return list;
    },
    [restrictionTag, interiorName],
  );

  const facts = useCallback(
    (l: GarageLocation): Fact[] => {
      const r = restrictionSummary(l.restriction, data);
      const name = l.access.mode !== 'quick' ? interiorName(l.access.interiorId) : null;
      return [
        {
          label: t('Who can use it'),
          value: r.detail ? `${r.type} · ${r.detail}` : r.type,
          tone: (l.restriction.type === 'job' || l.restriction.type === 'gang') && !r.detail ? 'amber' : undefined,
        },
        {
          label: t('Access mode'),
          value: l.access.mode === 'quick' ? accessModeLabel('quick') : `${accessModeShort(l.access.mode)} · ${name ?? t('no interior')}`,
          tone: l.access.mode !== 'quick' && !name ? 'amber' : undefined,
        },
        { label: t('Capacity'), value: capacityLabel(l.capacity) },
        l.source === 'spawner'
          ? { label: t('Vehicles'), value: plural(l.spawner.length, 'Spawner · {count} vehicle', 'Spawner · {count} vehicles') }
          : { label: t('Map blip'), value: l.blip.enabled ? t('Shown') : t('Hidden'), tone: l.blip.enabled ? undefined : 'muted' },
      ];
    },
    [data, interiorName],
  );

  const kpis = useCallback((all: GarageLocation[], ctx: LocationPageContext): Kpi[] => {
    let parked = 0;
    let out = 0;
    let impounded = 0;
    let withParked = 0;
    for (const l of all) {
      const s = ctx.stats(l);
      parked += s.parked;
      out += s.out;
      impounded += s.impounded;
      if (s.parked > 0) withParked += 1;
    }
    const enabled = all.filter((l) => l.enabled).length;
    const interior = all.filter((l) => l.access.mode !== 'quick').length;
    return [
      {
        key: 'locations',
        icon: 'garage',
        label: t('Locations'),
        value: fmt(enabled),
        unit: all.length ? `/ ${fmt(all.length)}` : undefined,
        sub: all.length ? t('enabled') : t('none yet'),
        ratio: all.length ? enabled / all.length : null,
      },
      {
        key: 'parked',
        icon: 'parking',
        label: t('Vehicles parked'),
        value: fmt(parked),
        sub: plural(withParked, 'in {count} garage', 'in {count} garages'),
      },
      {
        key: 'out',
        icon: 'route',
        label: t('Out right now'),
        value: fmt(out),
        sub: impounded ? plural(impounded, '{count} impounded', '{count} impounded') : t('none impounded'),
        tone: 'amber',
        ratio: parked + out ? out / (parked + out) : null,
      },
      {
        key: 'interior',
        icon: 'building',
        label: t('With interior'),
        value: fmt(interior),
        sub: plural(ctx.data.interiors.length, '{count} interior built', '{count} interiors built'),
        tone: 'blue',
      },
    ];
  }, []);

  const searchText = useCallback(
    (l: GarageLocation) => {
      const r = restrictionSummary(l.restriction, data);
      return `${r.type} ${r.detail} ${l.restriction.identifiers.join(' ')} ${l.restriction.rules.map((x) => x.name).join(' ')} ${accessModeShort(l.access.mode)} ${l.spawner.map((v) => v.model).join(' ')}`;
    },
    [data],
  );

  const kindLabel = useMemo(() => (l: GarageLocation) => (l.source === 'spawner' ? t('Public spawner') : t('Public garage')), []);

  return (
    <LocationListPage<GarageLocation>
      {...props}
      kind="garage"
      kindLabel={kindLabel}
      tags={tags}
      facts={facts}
      factsTitle={t('Access')}
      kpis={kpis}
      searchText={searchText}
      importable
      emptyIcon="garage"
      emptyTitle={t('No garages yet')}
      emptyDescription={t('Create your first public garage, or import the garages of the script you used before.')}
    />
  );
}
