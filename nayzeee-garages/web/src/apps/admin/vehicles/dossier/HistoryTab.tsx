/**
 * History tab: one timeline merging ownership and service records (filter chips All /
 * Ownership / Service) next to a short summary of both. Edits use the existing modals.
 */
import { useMemo, useState } from 'react';
import { Button, Chip, EmptyState, Icon, Tooltip, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import { date, distance, money } from '@/lib/format';
import type { AdminVehicleDetail } from '@/lib/types';
import { viaLabel } from '../util';
import { ago } from './data';
import { Fact, Heading } from './parts';

type Filter = 'all' | 'owner' | 'service';

interface Entry {
  key: string;
  kind: 'owner' | 'service';
  at: number;
  title: string;
  meta: string;
  aside: string | null;
  current?: boolean;
}

interface Props {
  detail: AdminVehicleDetail;
  onOwner: () => void;
  onService: () => void;
}

const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

export function HistoryTab({ detail, onOwner, onService }: Props) {
  const [filter, setFilter] = useState<Filter>('all');
  const v = detail.vehicle;
  const owners = detail.ownership;
  const services = useMemo(() => [...detail.service].sort((a, b) => b.at - a.at), [detail.service]);

  const entries = useMemo<Entry[]>(() => {
    const list: Entry[] = [
      ...owners.map((o, i) => ({
        key: `o-${o.identifier ?? 'x'}-${o.at}-${i}`,
        kind: 'owner' as const,
        at: o.at,
        title: o.name || t('Unknown'),
        meta: [viaLabel(o.via), o.identifier].filter(Boolean).join(' · '),
        aside: o.price ? money(o.price) : null,
        current: i === 0,
      })),
      ...services.map((s, i) => ({
        key: `s-${s.id ?? i}-${s.at}`,
        kind: 'service' as const,
        at: s.at,
        title: s.item,
        meta: s.shop || t('Unknown shop'),
        aside: distance(s.mileage),
      })),
    ];
    return list.sort((a, b) => b.at - a.at);
  }, [owners, services]);

  const shown = entries.filter((e) => filter === 'all' || e.kind === filter);

  // Month headings ("November 2026").
  const groups: { label: string; rows: Entry[] }[] = [];
  for (const e of shown) {
    const d = new Date(e.at * 1000);
    const label = t('{month} {year}', { month: t(MONTHS[d.getMonth()]), year: d.getFullYear() });
    const last = groups[groups.length - 1];
    if (last && last.label === label) last.rows.push(e);
    else groups.push({ label, rows: [e] });
  }

  const lastService = services[0] ?? null;
  const sinceService = lastService ? Math.max(0, v.mileage - lastService.mileage) : null;
  const first = owners[owners.length - 1] ?? null;
  const prices = owners.filter((o) => o.price).map((o) => o.price as number);

  return (
    <div className="nz-dos-pane">
      <div className="nz-dos-sheet nz-dos-hist">
        <section className="nz-dos-col nz-dos-hist__timeline">
          <div className="nz-dos-hist__chips">
            <Chip active={filter === 'all'} count={entries.length} onClick={() => setFilter('all')}>
              {t('All')}
            </Chip>
            <Chip active={filter === 'owner'} count={owners.length} icon="user" onClick={() => setFilter('owner')}>
              {t('Ownership')}
            </Chip>
            <Chip active={filter === 'service'} count={services.length} icon="wrench" onClick={() => setFilter('service')}>
              {t('Service')}
            </Chip>
          </div>
          {shown.length === 0 ? (
            <EmptyState
              compact
              icon={filter === 'service' ? 'wrench' : 'history'}
              title={filter === 'service' ? t('No service records') : filter === 'owner' ? t('No ownership records') : t('No history yet')}
              description={filter === 'owner' ? t('Ownership records are added when the vehicle is bought, sold, transferred or given by an admin.') : undefined}
              action={
                filter !== 'owner' ? (
                  <Button size="sm" variant="teal" icon="plus" onClick={onService}>
                    {t('Add service record')}
                  </Button>
                ) : (
                  <Button size="sm" variant="line" icon="transfer" onClick={onOwner}>
                    {t('Change owner')}
                  </Button>
                )
              }
            />
          ) : (
            <div className="nz-dos-tl">
              {groups.map((g, gi) => (
                <section key={`${g.label}-${gi}`}>
                  <h5>{g.label}</h5>
                  <ol>
                    {g.rows.map((e) => (
                      <li key={e.key} className={cx('nz-dos-tl__item', `is-${e.kind}`, e.current && 'is-current')}>
                        <span className="nz-dos-tl__date">
                          <b>{new Date(e.at * 1000).getDate()}</b>
                          <small>{t(MONTHS[new Date(e.at * 1000).getMonth()].slice(0, 3))}</small>
                        </span>
                        <span className="nz-dos-tl__node" aria-hidden="true">
                          <Icon name={e.kind === 'owner' ? 'user' : 'wrench'} size={12} strokeWidth={1.8} />
                        </span>
                        <span className="nz-dos-tl__text">
                          <b>
                            {e.title}
                            {e.current && <em>{t('Current owner')}</em>}
                          </b>
                          <span>{e.meta}</span>
                        </span>
                        <span className={cx('nz-dos-tl__aside', e.kind === 'service' && 'is-mono')}>{e.aside ?? ''}</span>
                        {e.kind === 'service' ? (
                          <Tooltip content={t('Edit service history')} side="left">
                            <button type="button" className="nz-dos-tl__edit" onClick={onService} aria-label={t('Edit service history')}>
                              <Icon name="edit" size={13} strokeWidth={1.7} />
                            </button>
                          </Tooltip>
                        ) : (
                          <span aria-hidden="true" />
                        )}
                      </li>
                    ))}
                  </ol>
                </section>
              ))}
            </div>
          )}
        </section>

        <section className="nz-dos-col nz-dos-hist__side">
          <Heading count={owners.length}>{t('Ownership')}</Heading>
          <div className="nz-dos-facts">
            <Fact label={t('Current owner')} icon="user">
              {v.ownerName || t('No owner')}
            </Fact>
            <Fact label={t('Owner since')} icon="calendar" tone={owners[0] ? undefined : 'muted'}>
              {owners[0] ? date(owners[0].at) : t('Unknown')}
            </Fact>
            <Fact label={t('First registered')} icon="history" tone={first ? undefined : 'muted'}>
              {first ? `${date(first.at)} · ${viaLabel(first.via)}` : t('Unknown')}
            </Fact>
            <Fact label={t('Highest price')} icon="money" tone={prices.length ? undefined : 'muted'}>
              {prices.length ? money(Math.max(...prices)) : t('None recorded')}
            </Fact>
          </div>

          <Heading className="nz-dos-h--gap" count={services.length}>
            {t('Service')}
          </Heading>
          <div className="nz-dos-facts">
            <Fact label={t('Last service')} icon="wrench" tone={lastService ? undefined : 'muted'}>
              {lastService ? `${lastService.item} · ${ago(lastService.at)}` : t('Never')}
            </Fact>
            <Fact label={t('Since last service')} icon="route" tone={sinceService === null ? 'muted' : undefined}>
              {sinceService === null ? '—' : distance(sinceService)}
            </Fact>
            <Fact label={t('Usual shop')} icon="building" tone={services.length ? undefined : 'muted'}>
              {usualShop(services.map((s) => s.shop)) ?? t('None')}
            </Fact>
          </div>
        </section>
      </div>
    </div>
  );
}

/** Most frequent non-empty shop name. */
function usualShop(shops: string[]): string | null {
  const counts = new Map<string, number>();
  for (const s of shops) if (s) counts.set(s, (counts.get(s) ?? 0) + 1);
  let best: string | null = null;
  let n = 0;
  for (const [s, c] of counts) {
    if (c > n) {
      best = s;
      n = c;
    }
  }
  return best;
}
