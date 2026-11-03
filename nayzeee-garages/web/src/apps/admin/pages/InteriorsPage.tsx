/**
 * Admin › Interiors — walk-in garage interiors.
 *
 * Toolbar (search + Create), a paginated table (Name, Vehicle slots, IPL profile, Status,
 * actions: edit in the creator, enable/disable, delete) and a summary of the selected interior
 * on the right. Create → CreateInteriorModal (admin:interior:create); edit → admin:interior:edit.
 * Both make Lua close the panel and start the in-world creator.
 */
import { useEffect, useMemo, useRef, useState } from 'react';
import {
  Badge,
  Button,
  ConfirmDialog,
  EmptyState,
  Icon,
  IconButton,
  Pagination,
  SearchInput,
  Table,
  Tooltip,
  cx,
} from '@/components/ui';
import type { TableColumn } from '@/components/ui';
import { request } from '@/lib/nui';
import { toast } from '@/lib/store';
import { t } from '@/lib/i18n';
import type { AdminPageProps, Interior, Location } from '@/lib/types';
import { useAdminShell } from '../shared/shell';
import { CreateInteriorModal } from '../interiors/CreateInteriorModal';
import { InteriorDetail, interiorIssues, usersOf } from '../interiors/InteriorDetail';
import { devHint } from '../vehicles/devHint';
import '../interiors/interiors.css';

const PAGE_SIZE = 10;

const byName = (a: Interior, b: Interior) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base', numeric: true });

export function InteriorsPage({ data, refresh, setData }: AdminPageProps) {
  const shell = useAdminShell();
  const [hint] = useState(() => devHint(data));
  const [query, setQuery] = useState('');
  const [page, setPage] = useState(1);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [creating, setCreating] = useState(!!hint.create);
  const [confirm, setConfirm] = useState<Interior | null>(null);
  const [deleting, setDeleting] = useState(false);
  const [busy, setBusy] = useState<Record<number, 'toggle' | 'edit'>>({});
  const tableRef = useRef<HTMLDivElement>(null);

  const all = useMemo(() => [...data.interiors].sort(byName), [data.interiors]);
  const profileLabel = useMemo(() => {
    const map = new Map(data.profiles.map((p) => [p.key, p.label]));
    return (key: string | null) => (key ? map.get(key) ?? key : null);
  }, [data.profiles]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return all;
    return all.filter((i) => `${i.name} #${i.id} ${profileLabel(i.profile) ?? ''} ${i.profile ?? ''}`.toLowerCase().includes(q));
  }, [all, query, profileLabel]);

  const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const cur = Math.min(page, pageCount);
  const rows = filtered.slice((cur - 1) * PAGE_SIZE, cur * PAGE_SIZE);

  useEffect(() => setPage(1), [query]);

  // Keep a sensible selection: the first visible row when nothing (valid) is selected.
  const selected = all.find((i) => i.id === selectedId) ?? null;
  useEffect(() => {
    if (selected && filtered.some((i) => i.id === selected.id)) return;
    setSelectedId(filtered[0]?.id ?? null);
  }, [filtered, selected]);

  const setBusyFor = (id: number, v: 'toggle' | 'edit' | null) =>
    setBusy((b) => {
      const n = { ...b };
      if (v) n[id] = v;
      else delete n[id];
      return n;
    });

  const patchInterior = (id: number, patch: Partial<Interior>) =>
    setData((d) => ({ ...d, interiors: d.interiors.map((x) => (x.id === id ? { ...x, ...patch } : x)) }));

  const toggle = async (i: Interior) => {
    if (i.id === null) return;
    const id = i.id;
    const enabled = !i.enabled;
    setBusyFor(id, 'toggle');
    patchInterior(id, { enabled });
    const res = await request('admin:interior:toggle', { id, enabled });
    setBusyFor(id, null);
    if (!res.ok) {
      patchInterior(id, { enabled: !enabled });
      return;
    }
    toast({
      type: enabled ? 'success' : 'info',
      message: enabled
        ? t('{name} is enabled again', { name: i.name })
        : t('{name} is disabled — anyone inside is sent out', { name: i.name }),
    });
  };

  const edit = async (i: Interior) => {
    if (i.id === null) return;
    setBusyFor(i.id, 'edit');
    await request('admin:interior:edit', { id: i.id });
    setBusyFor(i.id, null);
  };

  const doDelete = async () => {
    if (!confirm || confirm.id === null) return;
    const id = confirm.id;
    setDeleting(true);
    const res = await request('admin:interior:delete', { id });
    setDeleting(false);
    if (!res.ok) return;
    toast({ type: 'success', message: t('{name} was deleted', { name: confirm.name }) });
    setConfirm(null);
    setData((d) => ({
      ...d,
      interiors: d.interiors.filter((x) => x.id !== id),
      locations: d.locations.map((l) =>
        'access' in l && l.access.interiorId === id ? ({ ...l, access: { mode: 'quick', interiorId: null } } as Location) : l,
      ),
    }));
    void refresh();
  };

  const columns: TableColumn<Interior>[] = [
    {
      key: 'name',
      header: t('Name'),
      render: (i) => {
        const issues = interiorIssues(i);
        return (
          <span className="nz-aint-name" data-interior={i.id ?? ''}>
            <b className={cx('nz-aint-name__text', !i.enabled && 'is-off')} title={i.name}>
              {i.name}
            </b>
            {issues.length > 0 && (
              <Tooltip content={issues.join(' ')}>
                <span className="nz-aint-warn">
                  <Icon name="warning" size={13} strokeWidth={1.8} />
                </span>
              </Tooltip>
            )}
          </span>
        );
      },
    },
    {
      key: 'slots',
      header: t('Vehicle slots'),
      width: 100,
      render: (i) => (
        <span className={cx('nz-aint-slots', !i.enabled && 'is-off', !i.slots.length && 'is-zero')}>
          <Icon name="parking" size={13} strokeWidth={1.6} />
          {i.slots.length}
        </span>
      ),
    },
    {
      key: 'profile',
      header: t('IPL profile'),
      width: '27%',
      render: (i) => {
        const label = profileLabel(i.profile);
        return label ? (
          <span className={cx('nz-aint-cell', !i.enabled && 'is-off')} title={label}>
            {label}
          </span>
        ) : (
          <span className="nz-aint-dash">-</span>
        );
      },
    },
    {
      key: 'status',
      header: t('Status'),
      width: 104,
      render: (i) =>
        i.enabled ? (
          <Badge tone="teal" size="sm" dot>
            {t('Enabled')}
          </Badge>
        ) : (
          <Badge tone="neutral" size="sm" dot>
            {t('Disabled')}
          </Badge>
        ),
    },
    {
      key: 'actions',
      header: <span className="nz-aint-sr">{t('Actions')}</span>,
      width: 98,
      align: 'right',
      className: 'nz-aint-actions-col',
      render: (i) => {
        const b = i.id !== null ? busy[i.id] : undefined;
        return (
          <span className="nz-aint-actions">
            <IconButton icon="edit" size="sm" label={t('Edit in creator')} disabled={!!b} onClick={() => void edit(i)} />
            <IconButton
              icon="ban"
              size="sm"
              label={i.enabled ? t('Disable') : t('Enable')}
              active={!i.enabled}
              disabled={!!b}
              onClick={() => void toggle(i)}
            />
            <IconButton icon="trash" size="sm" label={t('Delete')} className="nz-aint-del" onClick={() => setConfirm(i)} />
          </span>
        );
      },
    },
  ];

  const hasAny = all.length > 0;
  const filteredOut = hasAny && filtered.length === 0;
  const confirmUsers = confirm ? usersOf(data.locations, confirm.id) : [];

  return (
    <div className="nz-aint">
      <div className="nz-aint__left">
        <div className="nz-aint__toolbar">
          <SearchInput value={query} onChange={setQuery} placeholder={t('Search by name or IPL profile')} className="nz-aint__search" />
          <Button variant="teal" icon="plus" onClick={() => setCreating(true)}>
            {t('Create')}
          </Button>
        </div>

        <div
          className={cx('nz-aint__table', !(hasAny && !filteredOut) && 'is-empty')}
          ref={tableRef}
          onClick={(e) => {
            // Row click selects (no chevron column: rows open nothing).
            const marker = (e.target as HTMLElement).closest('tr')?.querySelector<HTMLElement>('[data-interior]');
            const id = Number(marker?.dataset.interior);
            if (marker && Number.isFinite(id) && id > 0) setSelectedId(id);
          }}
        >
          {hasAny && !filteredOut ? (
            <Table<Interior>
              columns={columns}
              rows={rows}
              rowKey={(i) => i.id ?? i.name}
              activeKey={selectedId}
              dense
            />
          ) : filteredOut ? (
            <EmptyState
              className="nz-aint__empty"
              icon="search"
              title={t('No matches')}
              description={t('No interior matches “{query}”.', { query: query.trim() })}
              action={
                <Button size="sm" onClick={() => setQuery('')}>
                  {t('Clear search')}
                </Button>
              }
            />
          ) : (
            <EmptyState
              className="nz-aint__empty"
              icon="building"
              title={t('No interiors yet')}
              description={t('Interiors are walk-in garages: players drive in, see their vehicles parked on slots and drive out. Create one from an IPL profile or any MLO.')}
              action={
                <Button variant="teal" size="sm" icon="plus" onClick={() => setCreating(true)}>
                  {t('Create interior')}
                </Button>
              }
            />
          )}
        </div>

        {filtered.length > 0 && (
          <Pagination page={cur} pageCount={pageCount} onChange={setPage} total={filtered.length} pageSize={PAGE_SIZE} />
        )}
      </div>

      <InteriorDetail
        data={data}
        interior={hasAny ? selected : null}
        hasAny={hasAny}
        editing={selected?.id != null && busy[selected.id] === 'edit'}
        onEdit={(i) => void edit(i)}
      />

      <CreateInteriorModal
        open={creating}
        profiles={data.profiles}
        names={data.interiors.map((i) => i.name)}
        onClose={() => setCreating(false)}
      />

      <ConfirmDialog
        open={!!confirm && !shell.hidden}
        tone="red"
        icon="trash"
        title={t('Delete {name}?', { name: confirm?.name ?? '' })}
        message={
          confirmUsers.length
            ? t('Players inside are sent out and {count} garage(s) using it switch to quick access. This cannot be undone.', {
                count: confirmUsers.length,
              })
            : t('Players inside are sent out. No garage uses this interior. This cannot be undone.')
        }
        confirmLabel={t('Delete')}
        busy={deleting}
        onConfirm={() => void doDelete()}
        onCancel={() => setConfirm(null)}
      />
    </div>
  );
}
