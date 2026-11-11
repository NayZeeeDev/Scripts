/**
 * A player's keys (nz:carlock:admin:player): header (back, name, online, identifier, filter,
 * + Give key), totals (keys, vehicles, shared in, shared out), type chips and the key table
 * (fob render or access glyph, vehicle, spawn code, plate → plate view, type, from, custody,
 * vehicle spawned + distance, actions give / track / delete). The page size follows the
 * height the table gets (ResizeObserver), so every screen shows whole pages.
 */
import { useEffect, useMemo, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import {
  Avatar,
  Badge,
  Button,
  Chip,
  ConfirmDialog,
  EmptyState,
  Icon,
  IconButton,
  Pagination,
  SearchInput,
  Skeleton,
  Table,
  Tooltip,
  cx,
} from '@/components/ui';
import type { TableColumn } from '@/components/ui';
import { FobArt } from '@/components/fob/FobArt';
import { t } from '@/lib/i18n';
import { request } from '@/lib/nui';
import { toast, useSettings } from '@/lib/store';
import type { KeyAdminPlayerData, KeyAdminRow } from '@/lib/types';
import { GiveKeyModal } from './GiveKeyModal';
import type { GivePreset } from './GiveKeyModal';
import type { Nav } from './ManageKeys';
import { custodyOf, deleteMessage, duration, filterOf, meters, originLabel, secondsLeft, typeOf } from './model';
import type { RowFilter } from './model';

const ROW_H = 57;
const HEAD_H = 36;

/** true while the window is narrower than `px` (the spawn code column folds away). */
function useNarrow(px: number): boolean {
  const query = `(max-width: ${px}px)`;
  const [narrow, setNarrow] = useState(() => typeof window.matchMedia === 'function' && window.matchMedia(query).matches);
  useEffect(() => {
    if (typeof window.matchMedia !== 'function') return;
    const mq = window.matchMedia(query);
    const on = () => setNarrow(mq.matches);
    on();
    mq.addEventListener('change', on);
    return () => mq.removeEventListener('change', on);
  }, [query]);
  return narrow;
}

interface Props {
  identifier: string;
  initialName?: string;
  fobDesign: string | null;
  tempKeyHours: number;
  active: boolean;
  changeTick: number;
  onBack: () => void;
  onLoaded: (identifier: string, name: string) => void;
  nav: Nav;
}

export function PlayerView({ identifier, initialName, fobDesign, tempKeyHours, active, changeTick, onBack, onLoaded, nav }: Props) {
  const { distanceUnit } = useSettings();
  const narrow = useNarrow(1400);
  const [data, setData] = useState<KeyAdminPlayerData | null>(null);
  const [failed, setFailed] = useState(false);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<RowFilter>('all');
  const [text, setText] = useState('');
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(7);
  const [give, setGive] = useState<GivePreset | null>(null);
  const [confirm, setConfirm] = useState<KeyAdminRow | null>(null);
  const [busy, setBusy] = useState(false);
  const tableRef = useRef<HTMLDivElement>(null);
  const seq = useRef(0);

  const load = async () => {
    const id = ++seq.current;
    setLoading(true);
    const res = await request('keyadmin:player', { identifier });
    if (id !== seq.current) return;
    setLoading(false);
    if (!res.ok || !res.data) {
      setFailed(true);
      return;
    }
    setFailed(false);
    setData(res.data);
    onLoaded(identifier, res.data.player.name);
  };

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [identifier, changeTick]);

  // rows per page from the room the table gets
  useEffect(() => {
    const el = tableRef.current;
    if (!el || typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver(() => {
      const h = el.clientHeight;
      if (h > 0) setPageSize(Math.max(3, Math.floor((h - HEAD_H) / ROW_H)));
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, [data === null]);

  const rows = data?.keys ?? [];
  const counts = useMemo(() => {
    const c: Record<RowFilter, number> = { all: rows.length, items: 0, access: 0, temp: 0, owned: 0 };
    for (const r of rows) c[filterOf(r)]++;
    return c;
  }, [rows]);

  const shown = useMemo(() => {
    const q = text.trim().toLowerCase();
    return rows.filter((r) => {
      if (filter !== 'all' && filterOf(r) !== filter) return false;
      if (!q) return true;
      return [r.plate, r.model ?? '', r.label ?? '', r.make ?? '', originLabel(r.origin), typeOf(r).label, custodyOf(r.custody).label]
        .join(' ')
        .toLowerCase()
        .includes(q);
    });
  }, [rows, filter, text]);

  const pageCount = Math.max(1, Math.ceil(shown.length / pageSize));
  useEffect(() => {
    if (page > pageCount) setPage(pageCount);
  }, [page, pageCount]);
  useEffect(() => setPage(1), [filter, text]);
  const pageRows = shown.slice((page - 1) * pageSize, page * pageSize);

  const ownedPlates = useMemo(() => rows.filter((r) => r.type === 'owner' && r.origin === 'owner').map((r) => r.plate), [rows]);
  const online = data?.player.online ?? false;

  const doDelete = async () => {
    if (!confirm || busy) return;
    setBusy(true);
    const res = await request('keyadmin:delete', { identifier, id: confirm.id });
    setBusy(false);
    if (!res.ok || !res.data) return;
    setData(res.data);
    toast({ type: 'success', message: t('Key of {plate} deleted', { plate: confirm.plate }) });
    setConfirm(null);
  };

  const columns: TableColumn<KeyAdminRow>[] = [
    {
      key: 'key',
      header: t('Key'),
      width: '23%',
      render: (r) => <KeyCell row={r} fobDesign={fobDesign} />,
    },
    {
      key: 'model',
      header: t('Spawn code'),
      width: '10%',
      render: (r) => (r.model ? <span className="nz-kadm-mono nz-kadm-code">{r.model}</span> : <span className="nz-kadm-none">—</span>),
    },
    {
      key: 'plate',
      header: t('Plate'),
      width: 104,
      render: (r) => (
        <button type="button" className="nz-kadm-plate" onClick={() => nav.openPlate(r.plate)} title={t('Every key of {plate}', { plate: r.plate })}>
          {r.plate}
        </button>
      ),
    },
    {
      key: 'type',
      header: t('Type'),
      width: 118,
      render: (r) => <TypeCell row={r} />,
    },
    {
      key: 'from',
      header: t('From'),
      width: '12%',
      render: (r) => <span className="nz-kadm-from">{originLabel(r.origin)}</span>,
    },
    {
      key: 'custody',
      header: t('Custody'),
      width: '15%',
      render: (r) => <CustodyCell row={r} />,
    },
    {
      key: 'vehicle',
      header: t('Vehicle'),
      width: 112,
      render: (r) => <VehicleCell row={r} unit={distanceUnit} />,
    },
    {
      key: 'actions',
      header: <span className="nz-kadm-sr">{t('Actions')}</span>,
      width: 112,
      align: 'right',
      render: (r) => (
        <span className="nz-kadm-actions">
          <IconButton
            icon="userPlus"
            size="sm"
            label={t('Give another key of {plate}', { plate: r.plate })}
            onClick={() => setGive({ plate: r.plate, type: online ? 'item' : 'temp', keyKind: r.type === 'fob' ? 'fob' : r.type === 'key' ? 'key' : undefined })}
          />
          <IconButton
            icon="route"
            size="sm"
            label={r.spawned ? t('Track {plate}', { plate: r.plate }) : t('The vehicle is not out')}
            disabled={!r.spawned}
            onClick={() => nav.track(r.plate, r.label)}
          />
          <IconButton
            icon="trash"
            size="sm"
            variant="ghost"
            className="nz-kadm-del"
            label={r.deletable ? t('Delete this key') : r.type === 'owner' ? t('Ownership is not a key: transfer the vehicle instead') : t('This key cannot be deleted')}
            disabled={!r.deletable}
            onClick={() => setConfirm(r)}
          />
        </span>
      ),
    },
  ];

  const shownColumns = narrow ? columns.filter((c) => c.key !== 'model') : columns;
  const name = data?.player.name ?? initialName ?? t('Player');

  if (failed && !data) {
    return (
      <div className="nz-kadm-player">
        <PlayerHead name={name} identifier={identifier} onBack={onBack} />
        <EmptyState
          icon="warning"
          title={t('The keys of this player could not be loaded')}
          description={t('The server did not answer. Try again in a moment.')}
          action={
            <Button size="sm" icon="refresh" onClick={() => void load()}>
              {t('Try again')}
            </Button>
          }
        />
      </div>
    );
  }

  return (
    <div className="nz-kadm-player">
      <PlayerHead
        name={name}
        identifier={identifier}
        online={data?.player.online}
        serverId={data?.player.serverId}
        onBack={onBack}
        extra={
          <>
            <SearchInput value={text} onChange={setText} placeholder={t('Filter keys')} size="sm" className="nz-kadm-player__filter" />
            <IconButton icon="refresh" label={t('Reload')} onClick={() => void load()} disabled={loading} />
            <Button variant="teal" icon="plus" onClick={() => setGive({ type: online ? 'item' : 'temp' })} disabled={!data}>
              {t('Give key')}
            </Button>
          </>
        }
      />

      <div className="nz-kadm-totals">
        <Total icon="key" label={t('Keys')} value={data?.totals.keys} />
        <Total icon="car" label={t('Vehicles owned')} value={data?.totals.vehicles} />
        <Total icon="import" label={t('Shared with them')} value={data?.totals.sharedIn} />
        <Total icon="transfer" label={t('Shared by them')} value={data?.totals.sharedOut} />
      </div>

      <div className="nz-kadm-chips">
        <Chip active={filter === 'all'} onClick={() => setFilter('all')} count={counts.all}>
          {t('All')}
        </Chip>
        <Chip active={filter === 'items'} onClick={() => setFilter('items')} count={counts.items} icon="key">
          {t('Key items')}
        </Chip>
        <Chip active={filter === 'access'} onClick={() => setFilter('access')} count={counts.access} icon="link">
          {t('Virtual')}
        </Chip>
        <Chip active={filter === 'temp'} onClick={() => setFilter('temp')} count={counts.temp} icon="clock">
          {t('Temporary')}
        </Chip>
        <Chip active={filter === 'owned'} onClick={() => setFilter('owned')} count={counts.owned} icon="crown">
          {t('Owned / garage')}
        </Chip>
        {!online && data && (
          <span className="nz-kadm-chips__note">
            <Icon name="info" size={13} strokeWidth={1.7} />
            {t('Offline: pockets are not read, key items show their last known place')}
          </span>
        )}
      </div>

      <div className="nz-kadm-tablebox" ref={tableRef}>
        <Table<KeyAdminRow>
          className="nz-kadm-table"
          columns={shownColumns}
          rows={pageRows}
          rowKey={(r) => r.id}
          loading={loading && !data}
          skeletonRows={Math.min(pageSize, 6)}
          empty={
            rows.length === 0 ? (
              <EmptyState
                icon="key"
                title={t('{name} has no keys', { name })}
                description={t('No vehicles, shares, key items or temporary keys.')}
                action={
                  <Button size="sm" icon="plus" onClick={() => setGive({ type: online ? 'item' : 'temp' })}>
                    {t('Give key')}
                  </Button>
                }
                compact
              />
            ) : (
              <EmptyState
                icon="filter"
                title={t('No keys match this filter')}
                action={
                  <Button
                    size="sm"
                    onClick={() => {
                      setFilter('all');
                      setText('');
                    }}
                  >
                    {t('Show all keys')}
                  </Button>
                }
                compact
              />
            )
          }
        />
      </div>
      <Pagination
        className="nz-kadm-pager"
        page={page}
        pageCount={pageCount}
        onChange={setPage}
        total={shown.length}
        pageSize={pageSize}
      />

      {give && data && (
        <GiveKeyModal
          preset={give}
          player={data.player}
          ownedPlates={ownedPlates}
          fobDesign={fobDesign}
          tempKeyHours={tempKeyHours}
          onClose={() => setGive(null)}
          onDone={(next) => {
            setData(next);
            setGive(null);
          }}
        />
      )}
      <ConfirmDialog
        open={!!confirm && active}
        tone="red"
        icon="trash"
        title={confirm ? t('Delete the {type} of {plate}?', { type: typeOf(confirm).label.toLowerCase(), plate: confirm.plate }) : ''}
        message={confirm ? deleteMessage(confirm, online) : ''}
        confirmLabel={t('Delete key')}
        busy={busy}
        onConfirm={() => void doDelete()}
        onCancel={() => setConfirm(null)}
      />
    </div>
  );
}

/* ── parts ───────────────────────────────────────────────────────────── */

function PlayerHead({
  name,
  identifier,
  online,
  serverId,
  onBack,
  extra,
}: {
  name: string;
  identifier: string;
  online?: boolean;
  serverId?: number | null;
  onBack: () => void;
  extra?: ReactNode;
}) {
  return (
    <div className="nz-kadm-phead">
      <IconButton icon="arrowLeft" label={t('Back to the search')} variant="line" onClick={onBack} />
      <span className="nz-kadm-phead__avatar">
        <Avatar name={name} size={38} />
        {online !== undefined && <i className={cx('nz-kadm-dot', online && 'is-on')} />}
      </span>
      <div className="nz-kadm-phead__who">
        <div className="nz-kadm-phead__name">
          <b>{name}</b>
          {online !== undefined &&
            (online ? (
              <Badge tone="teal" size="sm" dot>
                {serverId ? t('Online · ID {id}', { id: serverId }) : t('Online')}
              </Badge>
            ) : (
              <Badge tone="neutral" size="sm">
                {t('Offline')}
              </Badge>
            ))}
        </div>
        <span className="nz-kadm-mono">{identifier}</span>
      </div>
      <div className="nz-kadm-phead__extra">{extra}</div>
    </div>
  );
}

function Total({ icon, label, value }: { icon: 'key' | 'car' | 'import' | 'transfer'; label: string; value: number | undefined }) {
  return (
    <div className="nz-kadm-total">
      <span className="nz-kadm-total__icon">
        <Icon name={icon} size={16} strokeWidth={1.7} />
      </span>
      <span className="nz-kadm-total__text">
        {value === undefined ? <Skeleton width={28} height={18} /> : <b>{value}</b>}
        <span>{label}</span>
      </span>
    </div>
  );
}

/** Fob render for key items, an access glyph for keys without an item. */
export function KeyGlyph({ type, design, brand, size = 34 }: { type: KeyAdminRow['type']; design: string | null; brand?: string | null; size?: number }) {
  if (type === 'key' || type === 'fob') {
    return (
      <span className="nz-kadm-glyph is-item" style={{ width: size, height: size }}>
        <FobArt design={type === 'key' ? 'key' : design ?? undefined} kind={type} brand={brand ?? null} size={size - 4} />
      </span>
    );
  }
  const icon = type === 'virtual' ? 'link' : type === 'temp' ? 'clock' : 'crown';
  return (
    <span className={cx('nz-kadm-glyph', `is-${type}`)} style={{ width: size, height: size }}>
      <Icon name={icon} size={Math.round(size * 0.45)} strokeWidth={1.7} />
    </span>
  );
}

function KeyCell({ row, fobDesign }: { row: KeyAdminRow; fobDesign: string | null }) {
  const title = row.label || row.model || t('Unknown vehicle');
  return (
    <span className="nz-kadm-keycell">
      <KeyGlyph type={row.type} design={fobDesign} brand={row.make} />
      <span className="nz-kadm-keycell__text">
        <b title={title}>{title}</b>
        <span>{row.make || (row.model ? row.model : t('Model unknown'))}</span>
      </span>
    </span>
  );
}

function TypeCell({ row }: { row: KeyAdminRow }) {
  const info = typeOf(row);
  const left = row.type === 'temp' ? secondsLeft(row.expires) : null;
  return (
    <span className="nz-kadm-type">
      <Badge tone={info.tone} size="sm">
        {info.label}
      </Badge>
      {row.current === false && (
        <Tooltip content={t('Cut for older locks: this key no longer opens the vehicle')}>
          <Badge tone="red" size="sm">
            {t('Old')}
          </Badge>
        </Tooltip>
      )}
      {left !== null && <em className={cx(left < 3600 && 'is-soon')}>{left > 0 ? duration(left) : t('ending')}</em>}
      {row.shared === 'in' && row.type !== 'virtual' && <em>{t('shared')}</em>}
    </span>
  );
}

function CustodyCell({ row }: { row: KeyAdminRow }) {
  const c = custodyOf(row.custody);
  return (
    <span className={cx('nz-kadm-custody', `is-${c.tone}`)}>
      <Icon name={c.icon} size={14} strokeWidth={1.7} />
      <span>
        {c.label}
        {c.detail && <em> · {c.detail}</em>}
      </span>
    </span>
  );
}

function VehicleCell({ row, unit }: { row: KeyAdminRow; unit: 'mi' | 'km' }) {
  if (!row.spawned) {
    return (
      <span className="nz-kadm-veh">
        <i className="nz-kadm-dot" />
        {t('Not out')}
      </span>
    );
  }
  return (
    <span className="nz-kadm-veh is-out">
      <i className="nz-kadm-dot is-on" />
      {row.distance !== null && row.distance !== undefined ? meters(row.distance, unit) : t('Out')}
    </span>
  );
}
