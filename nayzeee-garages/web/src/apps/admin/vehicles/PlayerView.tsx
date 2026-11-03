/**
 * Player vehicles — level 2: one player's garage roster (admin:players:vehicles).
 * Player band (back, identity, filter, assign), status tiles that filter the list, rich
 * vehicle rows (thumbnail, plate, location, condition) with ↑/↓ + Enter, and pagination.
 */
import { useEffect, useMemo, useRef, useState } from 'react';
import type { KeyboardEvent } from 'react';
import { Avatar, Badge, Button, EmptyState, Icon, IconButton, Pagination, SearchInput, Skeleton, VehicleImage, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { AdminOpenData, AdminVehicleRow } from '@/lib/types';
import { Highlight, MiniCondition, OnlineDot, moveFocus } from './common';
import { AssignVehicleModal } from './AssignVehicleModal';
import { matches, stateLabel, vehicleTypeIcon } from './util';
import { Plate } from './dossier/parts';

export type StatusFilter = 'all' | 'garaged' | 'out' | 'impounded' | 'financed' | 'blocked';

export interface PlayerData {
  player: { identifier: string; name: string; online: boolean };
  vehicles: AdminVehicleRow[];
}

export interface PlayerUi {
  filter: string;
  status: StatusFilter;
  page: number;
}

export const emptyPlayerUi: PlayerUi = { filter: '', status: 'all', page: 1 };

const PAGE_SIZE = 10;

interface Props {
  data: AdminOpenData;
  identifier: string;
  /** Name known from the search results while the list loads. */
  fallbackName: string;
  player: PlayerData | null;
  loading: boolean;
  error: string | null;
  ui: PlayerUi;
  onUi: (patch: Partial<PlayerUi>) => void;
  onBack: () => void;
  onRetry: () => void;
  onOpen: (row: AdminVehicleRow) => void;
  onAssigned: (row: AdminVehicleRow) => void;
  /** Plate of the vehicle last opened: its row gets the focus when coming back (↑/↓ keep working). */
  focusPlate?: string | null;
}

function statusOf(row: AdminVehicleRow, s: StatusFilter): boolean {
  switch (s) {
    case 'garaged':
    case 'out':
    case 'impounded':
      return row.state === s;
    case 'financed':
      return row.financed;
    case 'blocked':
      return row.blocked;
    default:
      return true;
  }
}

function VehicleRowItem({ v, query, onOpen }: { v: AdminVehicleRow; query: string; onOpen: () => void }) {
  const sub = v.classLabel ?? '';
  const where = v.state === 'garaged' ? v.garageName ?? t('No garage') : stateLabel(v.state);
  return (
    <li>
      <button type="button" className={cx('nz-aveh-vrow', v.blocked && 'is-blocked')} onClick={onOpen} data-plate={v.plate}>
        <span className="nz-aveh-vrow__thumb">
          <VehicleImage image={v.image} vehicleType={v.vehicleType} />
        </span>
        <span className="nz-aveh-vrow__name">
          <b className="nz-aveh-ellipsis">
            <Highlight text={v.label || v.model} query={query} />
          </b>
          <span className="nz-aveh-ellipsis">
            <Icon name={vehicleTypeIcon(v.vehicleType)} size={11} strokeWidth={1.8} />
            {sub ? `${sub} · ` : ''}
            <span className="nz-aveh-mono">
              <Highlight text={v.model} query={query} />
            </span>
          </span>
        </span>
        <Plate plate={v.plate} size="sm" className={cx(query && v.plate.includes(query.trim().toUpperCase()) && 'is-hit')} />
        <span className={cx('nz-aveh-vrow__where', `is-${v.state}`)}>
          <i />
          <span className="nz-aveh-ellipsis">
            {v.state === 'garaged' && v.garageName ? <Highlight text={v.garageName} query={query} /> : where}
          </span>
        </span>
        <MiniCondition fuel={v.fuel} engine={v.engine} body={v.body} />
        <span className="nz-aveh-vrow__tags">
          {v.financed && (
            <Badge tone="blue" size="sm" icon="money">
              {t('Financed')}
            </Badge>
          )}
          {v.blocked && (
            <Badge tone="red" size="sm" icon="ban">
              {t('Blocked')}
            </Badge>
          )}
        </span>
        <Icon name="chevronRight" size={15} strokeWidth={1.8} className="nz-aveh-vrow__chev" />
      </button>
    </li>
  );
}

export function PlayerView({ data, identifier, fallbackName, player, loading, error, ui, onUi, onBack, onRetry, onOpen, onAssigned, focusPlate = null }: Props) {
  const [assign, setAssign] = useState(false);
  const listRef = useRef<HTMLUListElement>(null);
  const refocused = useRef(false);
  const name = player?.player.name ?? fallbackName;
  const list = useMemo(() => player?.vehicles ?? [], [player]);

  const counts = useMemo(() => {
    const c: Record<StatusFilter, number> = { all: list.length, garaged: 0, out: 0, impounded: 0, financed: 0, blocked: 0 };
    list.forEach((v) => {
      c[v.state] += 1;
      if (v.financed) c.financed += 1;
      if (v.blocked) c.blocked += 1;
    });
    return c;
  }, [list]);

  const filtered = useMemo(
    () => list.filter((v) => statusOf(v, ui.status) && matches(ui.filter, v.plate, v.model, v.label, v.garageName)),
    [list, ui.status, ui.filter],
  );
  const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const page = Math.min(ui.page, pageCount);
  const rows = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  const tiles: { value: StatusFilter; label: string; icon: 'car' | 'garage' | 'route' | 'impound' | 'money' | 'ban'; tone?: 'red' | 'amber' | 'blue' }[] = [
    { value: 'all', label: t('All vehicles'), icon: 'car' },
    { value: 'garaged', label: t('In garage'), icon: 'garage' },
    { value: 'out', label: t('Not in garage'), icon: 'route', tone: 'amber' },
    { value: 'impounded', label: t('Impounded'), icon: 'impound', tone: 'red' },
    { value: 'financed', label: t('Financed'), icon: 'money', tone: 'blue' },
    { value: 'blocked', label: t('Blocked'), icon: 'ban', tone: 'red' },
  ];

  // Back from the dossier: show the page holding the vehicle just viewed and focus its row,
  // so ↑/↓ and Enter keep working without a click.
  useEffect(() => {
    if (refocused.current || !focusPlate || !player) return;
    const index = filtered.findIndex((v) => v.plate === focusPlate);
    const target = index < 0 ? page : Math.floor(index / PAGE_SIZE) + 1;
    if (target !== page) {
      onUi({ page: target });
      return;
    }
    refocused.current = true;
    const row = Array.from(listRef.current?.querySelectorAll<HTMLElement>('.nz-aveh-vrow') ?? []).find((el) => el.dataset.plate === focusPlate);
    if (row) {
      row.focus({ preventScroll: true });
      row.scrollIntoView({ block: 'nearest' });
    }
  }, [focusPlate, player, filtered, page, onUi]);

  const onListKey = (e: KeyboardEvent<HTMLElement>) => {
    moveFocus(e, listRef.current, '.nz-aveh-vrow');
  };

  // ↓ from the filter field jumps into the list.
  const onBandKey = (e: KeyboardEvent<HTMLDivElement>) => {
    if (e.key !== 'ArrowDown' || (e.target as HTMLElement).tagName !== 'INPUT') return;
    const first = listRef.current?.querySelector<HTMLElement>('.nz-aveh-vrow');
    if (first) {
      e.preventDefault();
      first.focus();
    }
  };

  let body;
  if (error) {
    body = (
      <EmptyState
        icon="warning"
        title={t('Could not load vehicles')}
        description={error}
        action={
          <Button size="sm" icon="refresh" onClick={onRetry}>
            {t('Try again')}
          </Button>
        }
      />
    );
  } else if (loading && !player) {
    body = (
      <ul className="nz-aveh-vlist">
        {Array.from({ length: 7 }, (_, i) => (
          <li key={i} className="nz-aveh-vrow is-skel">
            <Skeleton width={84} height={46} radius={7} />
            <span className="nz-aveh-vrow__name">
              <Skeleton width={`${50 + ((i * 13) % 35)}%`} height={11} />
              <Skeleton width="34%" height={8} style={{ marginTop: 7 }} />
            </span>
            <Skeleton width={88} height={28} radius={6} />
            <Skeleton width="60%" height={10} />
          </li>
        ))}
      </ul>
    );
  } else if (list.length === 0) {
    body = (
      <EmptyState
        icon="car"
        title={t('No vehicles yet')}
        description={t('{player} does not own any vehicles.', { player: name })}
        action={
          <Button size="sm" variant="teal" icon="plus" onClick={() => setAssign(true)}>
            {t('Assign vehicle')}
          </Button>
        }
      />
    );
  } else if (filtered.length === 0) {
    body = (
      <EmptyState
        icon="filter"
        compact
        title={t('No vehicles match')}
        description={t('Nothing matches the current filter.')}
        action={
          <Button size="sm" icon="close" onClick={() => onUi({ filter: '', status: 'all', page: 1 })}>
            {t('Clear filters')}
          </Button>
        }
      />
    );
  } else {
    body = (
      <ul className="nz-aveh-vlist" ref={listRef} onKeyDown={onListKey}>
        {rows.map((v) => (
          <VehicleRowItem key={v.plate} v={v} query={ui.filter} onOpen={() => onOpen(v)} />
        ))}
      </ul>
    );
  }

  return (
    <div className="nz-aveh-view nz-aveh-roster">
      <div className="nz-aveh-band" onKeyDown={onBandKey}>
        <IconButton icon="arrowLeft" label={t('Back to search (Esc)')} variant="line" onClick={onBack} />
        <div className="nz-aveh-who">
          <span className="nz-aveh-player__av">
            <Avatar name={name} size={40} />
            {player && <OnlineDot online={player.player.online} />}
          </span>
          <div className="nz-aveh-who__text">
            <b className="nz-aveh-ellipsis">{name}</b>
            <span>
              <span className="nz-aveh-mono">{identifier}</span>
              {player && <OnlineDot online={player.player.online} label />}
            </span>
          </div>
        </div>
        <SearchInput
          value={ui.filter}
          onChange={(filter) => onUi({ filter, page: 1 })}
          placeholder={t('Filter by plate, model or garage')}
          className="nz-aveh-grow"
          disabled={!list.length}
        />
        <Button variant="teal" icon="plus" onClick={() => setAssign(true)} disabled={!player}>
          {t('Assign vehicle')}
        </Button>
      </div>

      <div className="nz-aveh-tiles" role="tablist" aria-label={t('Filter by status')}>
        {tiles.map((tile) => {
          const n = counts[tile.value];
          const on = ui.status === tile.value;
          return (
            <button
              key={tile.value}
              type="button"
              role="tab"
              aria-selected={on}
              className={cx('nz-aveh-tile', on && 'is-on', tile.tone && n > 0 && `is-${tile.tone}`)}
              disabled={!player || (n === 0 && tile.value !== 'all' && !on)}
              onClick={() => onUi({ status: tile.value, page: 1 })}
            >
              <span className="nz-aveh-tile__label">
                <Icon name={tile.icon} size={12} strokeWidth={1.8} />
                {tile.label}
              </span>
              {player ? <b>{n}</b> : <Skeleton width={26} height={18} />}
            </button>
          );
        })}
      </div>

      <div className="nz-aveh-card nz-aveh-card--fill nz-aveh-roster__list">
        <div className="nz-aveh-roster__scroll">{body}</div>
        {filtered.length > 0 && !error && (
          <div className="nz-aveh-card__foot">
            <span className="nz-aveh-roster__hint">{t('↑ ↓ to move · Enter to open')}</span>
            <Pagination page={page} pageCount={pageCount} total={filtered.length} pageSize={PAGE_SIZE} onChange={(p) => onUi({ page: p })} />
          </div>
        )}
      </div>

      <AssignVehicleModal
        open={assign}
        data={data}
        identifier={identifier}
        playerName={name}
        onClose={() => setAssign(false)}
        onAssigned={onAssigned}
      />
    </div>
  );
}
