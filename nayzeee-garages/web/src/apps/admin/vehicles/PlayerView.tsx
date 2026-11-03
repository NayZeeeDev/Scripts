/**
 * Player vehicles — level 2: one player's vehicles (admin:players:vehicles), filter, status
 * chips, assign a new vehicle.
 */
import { useMemo, useState } from 'react';
import { Avatar, Button, Chip, EmptyState, IconButton, Pagination, PlateTag, SearchInput, Skeleton, Table, VehicleImage } from '@/components/ui';
import type { TableColumn } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { AdminOpenData, AdminVehicleRow } from '@/lib/types';
import { Condition, Highlight, OnlineDot, StatusBadges } from './common';
import { AssignVehicleModal } from './AssignVehicleModal';
import { matches } from './util';

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

export function PlayerView({ data, identifier, fallbackName, player, loading, error, ui, onUi, onBack, onRetry, onOpen, onAssigned }: Props) {
  const [assign, setAssign] = useState(false);
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

  const columns: TableColumn<AdminVehicleRow>[] = [
    {
      key: 'vehicle',
      header: t('Vehicle'),
      width: '27%',
      render: (v) => (
        <span className="nz-aveh-vcell">
          <VehicleImage image={v.image} vehicleType={v.vehicleType} className="nz-aveh-vcell__img" />
          <b className="nz-aveh-ellipsis">
            <Highlight text={v.label || v.model} query={ui.filter} />
          </b>
        </span>
      ),
    },
    { key: 'model', header: t('Spawn code'), width: '12%', className: 'nz-aveh-mono', render: (v) => <Highlight text={v.model} query={ui.filter} /> },
    { key: 'plate', header: t('Plate'), width: 104, render: (v) => <PlateTag plate={v.plate} /> },
    {
      key: 'garage',
      header: t('Garage'),
      width: '17%',
      render: (v) => (v.garageName ? <Highlight text={v.garageName} query={ui.filter} /> : <span className="nz-aveh-muted">—</span>),
    },
    { key: 'status', header: t('Status'), width: '17%', render: (v) => <StatusBadges row={v} /> },
    { key: 'cond', header: t('Condition'), width: 196, render: (v) => <Condition fuel={v.fuel} engine={v.engine} body={v.body} /> },
  ];

  const chips: { value: StatusFilter; label: string }[] = [
    { value: 'all', label: t('All') },
    { value: 'garaged', label: t('In garage') },
    { value: 'out', label: t('Not in garage') },
    { value: 'impounded', label: t('Impounded') },
    { value: 'financed', label: t('Financed') },
    { value: 'blocked', label: t('Blocked') },
  ];

  const empty = error ? (
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
  ) : list.length === 0 ? (
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
  ) : (
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

  return (
    <div className="nz-aveh-view">
      <div className="nz-aveh-toolbar">
        <IconButton icon="arrowLeft" label={t('Back to search')} variant="line" onClick={onBack} />
        <div className="nz-aveh-who">
          <span className="nz-aveh-player__av">
            <Avatar name={name} size={34} />
            {player && <OnlineDot online={player.player.online} />}
          </span>
          <div className="nz-aveh-who__text">
            <b className="nz-aveh-ellipsis">{name}</b>
            <span className="nz-aveh-mono">{identifier}</span>
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

      <div className="nz-aveh-chips">
        {loading && !player ? (
          <>
            <Skeleton width={64} height={28} radius={999} />
            <Skeleton width={92} height={28} radius={999} />
            <Skeleton width={104} height={28} radius={999} />
          </>
        ) : (
          chips
            .filter((c) => c.value === 'all' || c.value === ui.status || counts[c.value] > 0)
            .map((c) => (
              <Chip key={c.value} active={ui.status === c.value} count={counts[c.value]} onClick={() => onUi({ status: c.value, page: 1 })}>
                {c.label}
              </Chip>
            ))
        )}
      </div>

      <div className="nz-aveh-card">
        <Table
          columns={columns}
          rows={error ? [] : rows}
          rowKey={(v) => v.plate}
          onRowClick={onOpen}
          loading={loading && !player}
          skeletonRows={8}
          empty={empty}
        />
        {filtered.length > 0 && (
          <div className="nz-aveh-card__foot">
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
