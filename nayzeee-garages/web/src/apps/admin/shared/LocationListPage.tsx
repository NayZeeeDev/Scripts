/**
 * LocationListPage — the shared body of the four location pages (garages, job, private, impounds).
 *
 * API
 *   <LocationListPage kind data refresh setData columns nameExtra? searchText? importable?
 *                     emptyTitle emptyDescription emptyIcon? />
 *   LocationColumn<L> { key, header, width?, align?, render(loc) }   columns between Vehicle and actions
 *
 * Layout: toolbar (search, vehicle filter, Import?, + Create) and a paginated table (10 per page)
 * on the left (~62%), MapView on the right. Name + Vehicle columns and the row actions (edit,
 * teleport, enable/disable, delete) are built in. Hovering a row highlights its pin, clicking a
 * pin (or a name) selects the row and brings it into view. Disabled rows are dimmed.
 * Create / edit opens LocationEditor; GaragesPage passes `importable` for the Import modal.
 */
import { useEffect, useMemo, useRef, useState } from 'react';
import type { MouseEvent as ReactMouseEvent, ReactNode } from 'react';
import {
  Badge,
  Button,
  ConfirmDialog,
  EmptyState,
  Icon,
  IconButton,
  Pagination,
  SearchInput,
  Select,
  Table,
  Tooltip,
  cx,
} from '@/components/ui';
import type { IconName, TableColumn } from '@/components/ui';
import { request, isBrowser } from '@/lib/nui';
import { toast } from '@/lib/store';
import { t } from '@/lib/i18n';
import type { AdminOpenData, AdminPageProps, Location } from '@/lib/types';
import { MapView } from './MapView';
import type { MapPin } from './MapView';
import { kindNoun, locationAnchor, vehicleTypeIcon, vehicleTypeLabel, vehicleTypeOptions } from './labels';
import type { LocationPageKind, VehicleFilter } from './labels';
import { useAdminShell } from './shell';
import { LocationEditor } from '../locations/LocationEditor';
import { ImportModal } from '../locations/ImportModal';

export interface LocationColumn<L extends Location> {
  key: string;
  header: ReactNode;
  width?: number | string;
  align?: 'left' | 'right' | 'center';
  render: (loc: L) => ReactNode;
}

export interface LocationListPageProps<L extends Location> extends AdminPageProps {
  kind: L['kind'] & LocationPageKind;
  columns: LocationColumn<L>[];
  /** Badges after the name (e.g. "Spawner"). */
  nameExtra?: (loc: L) => ReactNode;
  /** Extra text matched by the search box. */
  searchText?: (loc: L) => string;
  importable?: boolean;
  emptyTitle: string;
  emptyDescription: string;
  emptyIcon?: IconName;
}

const PAGE_SIZE = 10;

type DevHint = { __devEdit?: number | 'new' };
type Id = string | number;

interface EditorState<L> {
  open: boolean;
  seed: L | null;
  session: number;
}

export function LocationListPage<L extends Location>({
  kind,
  data,
  refresh,
  setData,
  columns,
  nameExtra,
  searchText,
  importable = false,
  emptyTitle,
  emptyDescription,
  emptyIcon = 'garage',
}: LocationListPageProps<L>) {
  const shell = useAdminShell();
  const [query, setQuery] = useState('');
  const [vehicle, setVehicle] = useState<VehicleFilter>('all');
  const [page, setPage] = useState(1);
  const [hoverId, setHoverId] = useState<Id | null>(null);
  const [selectedId, setSelectedId] = useState<Id | null>(null);
  const [focusTick, setFocusTick] = useState(0);
  const [busy, setBusy] = useState<Record<string, 'toggle' | 'teleport'>>({});
  const [confirm, setConfirm] = useState<L | null>(null);
  const [deleting, setDeleting] = useState(false);
  const [importOpen, setImportOpen] = useState(false);
  const [editor, setEditor] = useState<EditorState<L>>({ open: false, seed: null, session: 0 });
  const tableRef = useRef<HTMLDivElement>(null);

  const all = useMemo(
    () =>
      (data.locations.filter((l) => l.kind === kind) as L[]).sort((a, b) =>
        a.name.localeCompare(b.name, undefined, { sensitivity: 'base', numeric: true }),
      ),
    [data.locations, kind],
  );

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return all.filter((l) => {
      if (vehicle !== 'all' && l.vehicleType !== vehicle) return false;
      if (!q) return true;
      const hay = `${l.name} #${l.id} ${searchText ? searchText(l) : ''}`.toLowerCase();
      return hay.includes(q);
    });
  }, [all, query, vehicle, searchText]);

  const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const cur = Math.min(page, pageCount);
  const rows = filtered.slice((cur - 1) * PAGE_SIZE, cur * PAGE_SIZE);

  useEffect(() => setPage(1), [query, vehicle]);

  /* dev harness: ?mock=admin-edit-… opens the editor straight away */
  const devHandled = useRef(false);
  useEffect(() => {
    if (!isBrowser || devHandled.current) return;
    const hint = (data as AdminOpenData & DevHint).__devEdit;
    if (hint === undefined) return;
    devHandled.current = true;
    if (hint === 'new') openEditor(null);
    else {
      const loc = all.find((l) => l.id === hint);
      if (loc) openEditor(loc);
    }
  }, [data]);

  /* bring the selected row into view after paging */
  useEffect(() => {
    if (selectedId === null) return;
    const raf = requestAnimationFrame(() => {
      const el = tableRef.current?.querySelector<HTMLElement>(`[data-loc="${String(selectedId)}"]`);
      el?.closest('tr')?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    });
    return () => cancelAnimationFrame(raf);
  }, [selectedId, cur]);

  const pins: MapPin[] = useMemo(
    () =>
      filtered.flatMap((l) => {
        const a = locationAnchor(l);
        if (!a || l.id === null) return [];
        return [
          {
            id: l.id,
            x: a.x,
            y: a.y,
            label: l.name,
            sublabel: l.enabled ? vehicleTypeLabel(l.vehicleType) : t('Disabled'),
            muted: !l.enabled,
          },
        ];
      }),
    [filtered],
  );

  function openEditor(seed: L | null) {
    setEditor((e) => ({ open: true, seed, session: e.session + 1 }));
  }

  const selectFromMap = (id: Id) => {
    setSelectedId(id);
    const i = filtered.findIndex((l) => l.id === id);
    if (i >= 0) setPage(Math.floor(i / PAGE_SIZE) + 1);
  };

  const selectRow = (l: L) => {
    if (l.id === null) return;
    setSelectedId(l.id);
    setFocusTick((n) => n + 1);
  };

  const onTableHover = (e: ReactMouseEvent<HTMLDivElement>) => {
    const tr = (e.target as HTMLElement).closest('tr');
    const marker = tr?.querySelector<HTMLElement>('[data-loc]');
    const raw = marker?.dataset.loc ?? null;
    const id = raw === null ? null : Number.isNaN(Number(raw)) ? raw : Number(raw);
    if (id !== hoverId) setHoverId(id);
  };

  const setBusyFor = (id: Id, v: 'toggle' | 'teleport' | null) =>
    setBusy((b) => {
      const n = { ...b };
      if (v) n[String(id)] = v;
      else delete n[String(id)];
      return n;
    });

  const toggle = async (l: L) => {
    if (l.id === null) return;
    const id = l.id;
    const enabled = !l.enabled;
    setBusyFor(id, 'toggle');
    setData((d) => ({ ...d, locations: d.locations.map((x) => (x.id === id ? ({ ...x, enabled } as Location) : x)) }));
    const res = await request('admin:location:toggle', { id, enabled });
    setBusyFor(id, null);
    if (!res.ok) {
      setData((d) => ({ ...d, locations: d.locations.map((x) => (x.id === id ? ({ ...x, enabled: !enabled } as Location) : x)) }));
      return;
    }
    toast({
      type: enabled ? 'success' : 'info',
      message: enabled ? t('{name} is enabled again', { name: l.name }) : t('{name} is disabled', { name: l.name }),
    });
  };

  const teleport = async (l: L) => {
    const a = locationAnchor(l);
    if (!a || l.id === null) return;
    setBusyFor(l.id, 'teleport');
    const res = await request('admin:location:teleport', { coords: a });
    setBusyFor(l.id, null);
    if (res.ok) toast({ type: 'success', message: t('Teleported to {name}', { name: l.name }) });
  };

  const doDelete = async () => {
    if (!confirm || confirm.id === null) return;
    const id = confirm.id;
    setDeleting(true);
    const res = await request('admin:location:delete', { id });
    setDeleting(false);
    if (!res.ok) return;
    toast({ type: 'success', message: t('{name} was deleted', { name: confirm.name }) });
    setConfirm(null);
    if (selectedId === id) setSelectedId(null);
    setData((d) => ({ ...d, locations: d.locations.filter((x) => x.id !== id) }));
    void refresh();
  };

  const onSaved = (saved: Location) => {
    setData((d) => {
      const exists = d.locations.some((x) => x.id === saved.id);
      return {
        ...d,
        locations: exists ? d.locations.map((x) => (x.id === saved.id ? saved : x)) : [...d.locations, saved],
      };
    });
    setEditor((e) => ({ ...e, open: false }));
    if (saved.id !== null) {
      setSelectedId(saved.id);
      setFocusTick((n) => n + 1);
      const list = [...all.filter((x) => x.id !== saved.id), saved as L].sort((a, b) =>
        a.name.localeCompare(b.name, undefined, { sensitivity: 'base', numeric: true }),
      );
      const i = list.findIndex((x) => x.id === saved.id);
      if (i >= 0 && !query && vehicle === 'all') setPage(Math.floor(i / PAGE_SIZE) + 1);
    }
    void refresh();
  };

  const noun = kindNoun(kind);

  const tableColumns: TableColumn<L>[] = [
    {
      key: 'name',
      header: t('Name'),
      render: (l) => {
        const anchor = locationAnchor(l);
        return (
          <span className="nz-admin-locs__name-cell">
            <button
              type="button"
              className={cx('nz-admin-locs__name', !l.enabled && 'is-off')}
              data-loc={l.id ?? ''}
              onClick={() => selectRow(l)}
              title={l.name}
            >
              {l.name}
            </button>
            {!l.enabled && (
              <Badge tone="neutral" size="sm" icon="ban">
                {t('Disabled')}
              </Badge>
            )}
            {nameExtra?.(l)}
            {!anchor && (
              <Tooltip content={t('No interaction point yet — edit it to place one')}>
                <span className="nz-admin-locs__warn">
                  <Icon name="warning" size={13} strokeWidth={1.8} />
                </span>
              </Tooltip>
            )}
          </span>
        );
      },
    },
    {
      key: 'vehicle',
      header: t('Vehicle'),
      width: 70,
      render: (l) => (
        <span className={cx('nz-admin-locs__cell nz-admin-locs__vt', !l.enabled && 'is-off')}>
          <Icon name={vehicleTypeIcon(l.vehicleType)} size={14} strokeWidth={1.6} />
          {vehicleTypeLabel(l.vehicleType)}
        </span>
      ),
    },
    ...columns.map<TableColumn<L>>((c) => ({
      key: c.key,
      header: c.header,
      width: c.width,
      align: c.align,
      render: (l) => <span className={cx('nz-admin-locs__cell', !l.enabled && 'is-off')}>{c.render(l)}</span>,
    })),
    {
      key: 'actions',
      header: <span className="nz-admin-locs__sr">{t('Actions')}</span>,
      width: 126,
      align: 'right',
      className: 'nz-admin-locs__actions-col',
      render: (l) => {
        const b = l.id !== null ? busy[String(l.id)] : undefined;
        const anchor = locationAnchor(l);
        return (
          <span className="nz-admin-locs__actions">
            <IconButton icon="edit" size="sm" label={t('Edit')} onClick={() => openEditor(l)} />
            <IconButton
              icon="pin"
              size="sm"
              label={anchor ? t('Teleport here') : t('No interaction point to teleport to')}
              disabled={!anchor || b === 'teleport'}
              onClick={() => void teleport(l)}
            />
            <IconButton
              icon="ban"
              size="sm"
              label={l.enabled ? t('Disable') : t('Enable')}
              active={!l.enabled}
              disabled={b === 'toggle'}
              onClick={() => void toggle(l)}
            />
            <IconButton icon="trash" size="sm" label={t('Delete')} className="nz-admin-locs__del" onClick={() => setConfirm(l)} />
          </span>
        );
      },
    },
  ];

  const hasAny = all.length > 0;
  const filteredOut = hasAny && filtered.length === 0;

  return (
    <div className="nz-admin-locs">
      <div className="nz-admin-locs__left">
        <div className="nz-admin-locs__toolbar">
          <SearchInput
            value={query}
            onChange={setQuery}
            placeholder={t('Search by name or #id')}
            className="nz-admin-locs__search"
          />
          <Select<VehicleFilter>
            value={vehicle}
            onChange={setVehicle}
            options={vehicleTypeOptions(true)}
            className="nz-admin-locs__filter"
          />
          {importable && (
            <Button icon="import" onClick={() => setImportOpen(true)}>
              {t('Import')}
            </Button>
          )}
          <Button variant="teal" icon="plus" onClick={() => openEditor(null)}>
            {t('Create')}
          </Button>
        </div>

        <div
          className={cx('nz-admin-locs__table', !(hasAny && !filteredOut) && 'is-empty')}
          ref={tableRef}
          onMouseOver={onTableHover}
          onMouseLeave={() => setHoverId(null)}
        >
          {hasAny && !filteredOut ? (
            <Table<L>
              columns={tableColumns}
              rows={rows}
              rowKey={(l) => l.id ?? l.name}
              activeKey={selectedId}
              dense
            />
          ) : filteredOut ? (
            <EmptyState
              className="nz-admin-locs__empty"
              icon="search"
              title={t('No matches')}
              description={t('Nothing matches your search or filter.')}
              action={
                <Button
                  size="sm"
                  onClick={() => {
                    setQuery('');
                    setVehicle('all');
                  }}
                >
                  {t('Clear filters')}
                </Button>
              }
            />
          ) : (
            <EmptyState
              className="nz-admin-locs__empty"
              icon={emptyIcon}
              title={emptyTitle}
              description={emptyDescription}
              action={
                <span className="nz-admin-locs__empty-actions">
                  <Button variant="teal" size="sm" icon="plus" onClick={() => openEditor(null)}>
                    {t('Create {noun}', { noun: noun.toLowerCase() })}
                  </Button>
                  {importable && (
                    <Button size="sm" icon="import" onClick={() => setImportOpen(true)}>
                      {t('Import')}
                    </Button>
                  )}
                </span>
              }
            />
          )}
        </div>

        {filtered.length > 0 && (
          <Pagination page={cur} pageCount={pageCount} onChange={setPage} total={filtered.length} pageSize={PAGE_SIZE} />
        )}
      </div>

      <MapView
        className="nz-admin-locs__map"
        pins={pins}
        selectedId={selectedId}
        hoverId={hoverId}
        onHover={setHoverId}
        onSelect={selectFromMap}
        focusTick={focusTick}
        emptyText={hasAny ? t('No locations match') : t('No locations yet')}
      />

      <LocationEditor
        key={editor.session}
        open={editor.open}
        kind={kind}
        seed={editor.seed}
        data={data}
        onClose={() => setEditor((e) => ({ ...e, open: false }))}
        onSaved={onSaved}
      />

      {importable && (
        <ImportModal
          open={importOpen && !shell.hidden}
          sources={data.importSources}
          onClose={() => setImportOpen(false)}
          onImported={() => {
            setImportOpen(false);
            void refresh();
          }}
        />
      )}

      <ConfirmDialog
        open={!!confirm && !shell.hidden}
        tone="red"
        icon="trash"
        title={t('Delete {name}?', { name: confirm?.name ?? '' })}
        message={
          kind === 'private'
            ? t('Every copy of this garage and its members will be removed. Vehicles parked inside must be moved first. This cannot be undone.')
            : t('Players will no longer see this {noun}. Vehicles stored here keep their record and can be moved by an admin. This cannot be undone.', {
                noun: noun.toLowerCase(),
              })
        }
        confirmLabel={t('Delete')}
        busy={deleting}
        onConfirm={() => void doDelete()}
        onCancel={() => setConfirm(null)}
      />
    </div>
  );
}
