/**
 * Admin › Private garages (kind 'private') in the Map command (shared/LocationListPage).
 * Owned copies (GroupInfo) are loaded per location (withGroups) for the cards, the KPIs and the
 * inspector's Owners section; owners themselves are still managed in the editor.
 * KPIs: locations, owned copies, vehicles parked, for sale.
 */
import { useCallback, useMemo } from 'react';
import { t } from '@/lib/i18n';
import { money } from '@/lib/format';
import type { AdminPageProps, PrivateLocation } from '@/lib/types';
import { LocationListPage } from '../shared/LocationListPage';
import type { CardTag, Fact, Kpi, LocationPageContext } from '../shared/LocationListPage';
import { accessModeShort, capacityLabel, plural } from '../shared/labels';

const fmt = (n: number) => n.toLocaleString('en-US');

function copiesText(l: PrivateLocation, owned: number | null): string {
  if (owned === null) return l.maxCopies > 0 ? t('Max {count} copies', { count: l.maxCopies }) : t('Unlimited copies');
  return l.maxCopies > 0 ? t('{owned} of {max} owned', { owned, max: l.maxCopies }) : t('{owned} owned', { owned });
}

export function PrivateGaragesPage(props: AdminPageProps) {
  const ownedOf = (l: PrivateLocation, ctx: LocationPageContext): number | null => {
    const g = ctx.groups(l.id);
    return Array.isArray(g) ? g.length : null;
  };

  const tags = useCallback((l: PrivateLocation, ctx: LocationPageContext): CardTag[] => {
    const owned = ownedOf(l, ctx);
    const full = owned !== null && l.maxCopies > 0 && owned >= l.maxCopies;
    const list: CardTag[] = [
      l.purchasable ? { icon: 'tag', label: money(l.price), tone: 'teal', title: t('For sale at {price}', { price: money(l.price) }) } : { icon: 'key', label: t('Assigned') },
      { icon: 'users', label: copiesText(l, owned), tone: full ? 'amber' : 'neutral' },
      { icon: l.storage === 'shared' ? 'link' : 'user', label: l.storage === 'shared' ? t('Shared') : t('Personal') },
    ];
    if (l.access.mode !== 'quick') list.push({ icon: l.access.mode === 'interior' ? 'door' : 'building', label: accessModeShort(l.access.mode) });
    return list;
  }, []);

  const facts = useCallback(
    (l: PrivateLocation, ctx: LocationPageContext): Fact[] => {
      const owned = ownedOf(l, ctx);
      const interior = l.access.mode !== 'quick' ? props.data.interiors.find((i) => i.id === l.access.interiorId)?.name ?? null : null;
      return [
        {
          label: t('Sale'),
          value: l.purchasable ? t('{price} · {refund}% back', { price: money(l.price), refund: l.sellRefund }) : t('Assigned by an admin'),
          title: l.purchasable ? t('For sale at {price}, {refund}% refunded when sold back', { price: money(l.price), refund: l.sellRefund }) : undefined,
        },
        { label: t('Copies'), value: copiesText(l, owned) },
        { label: t('Storage'), value: l.storage === 'shared' ? t('Shared with members') : t('Personal vehicles only') },
        {
          label: t('Garage'),
          value: `${capacityLabel(l.capacity)} · ${interior ? `${accessModeShort(l.access.mode)} · ${interior}` : accessModeShort(l.access.mode)}`,
        },
      ];
    },
    [props.data.interiors],
  );

  const kpis = useCallback((all: PrivateLocation[], ctx: LocationPageContext): Kpi[] => {
    let parked = 0;
    let out = 0;
    let copies = 0;
    let members = 0;
    let loading = false;
    let failed = false;
    for (const l of all) {
      const s = ctx.stats(l);
      parked += s.parked;
      out += s.out;
      const g = ctx.groups(l.id);
      if (g === undefined) loading = true;
      else if (g === 'error') failed = true;
      else {
        copies += g.length;
        members += g.reduce((n, x) => n + x.members.length, 0);
      }
    }
    const enabled = all.filter((l) => l.enabled).length;
    const forSale = all.filter((l) => l.purchasable);
    const prices = forSale.map((l) => l.price);
    const lo = prices.length ? Math.min(...prices) : 0;
    const hi = prices.length ? Math.max(...prices) : 0;
    return [
      {
        key: 'locations',
        icon: 'users',
        label: t('Locations'),
        value: fmt(enabled),
        unit: all.length ? `/ ${fmt(all.length)}` : undefined,
        sub: all.length ? t('enabled') : t('none yet'),
        ratio: all.length ? enabled / all.length : null,
      },
      {
        key: 'copies',
        icon: 'key',
        label: t('Owned copies'),
        value: failed ? '—' : loading && all.length ? null : fmt(copies),
        sub: failed ? t('could not load') : loading && all.length ? t('loading…') : plural(members, '{count} member', '{count} members'),
        tone: 'blue',
      },
      {
        key: 'parked',
        icon: 'parking',
        label: t('Vehicles parked'),
        value: fmt(parked),
        sub: plural(out, '{count} out now', '{count} out now'),
      },
      {
        key: 'sale',
        icon: 'tag',
        label: t('For sale'),
        value: fmt(forSale.length),
        sub: prices.length ? (lo === hi ? money(lo) : `${money(lo)} – ${money(hi)}`) : t('none for sale'),
        tone: 'amber',
      },
    ];
  }, []);

  const searchText = useCallback(
    (l: PrivateLocation) => `${l.purchasable ? 'purchasable for sale' : 'assigned'} ${l.storage} ${l.price}`,
    [],
  );

  const kindLabel = useMemo(() => (l: PrivateLocation) => (l.purchasable ? t('Private garage · for sale') : t('Private garage · assigned')), []);

  return (
    <LocationListPage<PrivateLocation>
      {...props}
      kind="private"
      kindLabel={kindLabel}
      tags={tags}
      facts={facts}
      factsTitle={t('Sale & copies')}
      kpis={kpis}
      searchText={searchText}
      withGroups
      emptyIcon="users"
      emptyTitle={t('No private garages yet')}
      emptyDescription={t('Sell garages to players, or assign them to someone from the garage editor.')}
    />
  );
}
