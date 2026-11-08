/**
 * LocationListPage — the "Map command": shared body of the four location pages (garages, job &
 * gang, private, impounds). Map-first, not a table.
 *
 * API
 *   <LocationListPage kind data refresh setData kindLabel tags facts factsTitle kpis
 *                     searchText? warning? importable? withGroups? emptyTitle emptyDescription emptyIcon? />
 *   The page spec callbacks receive a LocationPageContext (data, per-location stats, owned
 *   copies of private locations) — see commandTypes.ts.
 *
 * Layout
 *   KPI strip (4 tiles from the spec), then the directory (left, ≈ 400px: search, Import,
 *   Create, vehicle-type Segmented, status / sort Selects, scrollable LocationCards) and the
 *   MapView (fills the rest). The Inspector slides over the bottom of the map when a location
 *   is selected and carries the actions (Edit, Teleport, Points, Enable/Disable, Delete).
 *
 * Interaction
 *   Card hover ↔ pin highlight; card click selects + flies to its pin; pin click selects +
 *   scrolls its card into view; click on empty map deselects; double-click card / pin edits.
 *   Keyboard: "/" search, ↑/↓ move through the cards (list focused), Enter edits and Delete
 *   asks to delete the selected location from anywhere on the page (list, map, pin), Esc
 *   closes the inspector (then the panel). Filter changes refit the map (MapView fitKey).
 *   Fit all with the inspector open folds it to its header row when the pins need the room
 *   (MapView onMakeRoom); any new selection or its chevron unfolds it.
 *
 * Flows kept from the table version: create / edit (LocationEditor, opened exactly as before),
 * delete (ConfirmDialog), enable toggle, teleport (admin:location:teleport), import
 * (ImportModal, `importable`), refresh after changes. New: in-world point manager straight from
 * the inspector (requestPoints → admin:location:save with the new points).
 * Private pages pass `withGroups`: owned copies are loaded per location (shared/groups.ts).
 */
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import type { KeyboardEvent as ReactKeyboardEvent } from 'react';
import { Button, ConfirmDialog, EmptyState, Icon, KeyHint, Menu, SearchInput, Segmented, Select, cx } from '@/components/ui';
import type { IconName } from '@/components/ui';
import { request, isBrowser } from '@/lib/nui';
import { toast } from '@/lib/store';
import { useEscape } from '@/lib/escape';
import { t } from '@/lib/i18n';
import type { AdminOpenData, AdminPageProps, CapacityConfig, InteractionPoint, Location, Vec4 } from '@/lib/types';
import { MapView } from './MapView';
import type { MapPin } from './MapView';
import { KpiStrip } from './KpiStrip';
import { LocationCard } from './LocationCard';
import { Inspector } from './Inspector';
import type { InspectorBusy, PointKind } from './Inspector';
import type { CardTag, Fact, Kpi, LocationPageContext } from './commandTypes';
import { usePrivateGroups, groupsCooldown } from './groups';
import { isAdminHidden, requestPoints } from './away';
import { kindNoun, locationAnchor, plural, statsOf, vehicleTotal, vehicleTypeIcon, vehicleTypeLabel } from './labels';
import type { LocationPageKind, VehicleFilter } from './labels';
import { LocationEditor } from '../locations/LocationEditor';
import { ImportModal } from '../locations/ImportModal';
import './command.css';
import './map.css';

export interface LocationListPageProps<L extends Location> extends AdminPageProps {
  kind: L['kind'] & LocationPageKind;
  /** "Public garage", "Job garage", "Gang garage"… (inspector subtitle, pin tooltip). */
  kindLabel: (loc: L) => string;
  /** Tags on the directory card. */
  tags: (loc: L, ctx: LocationPageContext) => CardTag[];
  /** Rows of the inspector's kind section. */
  facts: (loc: L, ctx: LocationPageContext) => Fact[];
  /** Heading of that section ("Access", "Operation", "Sale & copies"). */
  factsTitle: string;
  /** The 4 KPI tiles (from every location of this kind, unfiltered). */
  kpis: (all: L[], ctx: LocationPageContext) => Kpi[];
  /** Extra text matched by the search box. */
  searchText?: (loc: L) => string;
  /** Amber flag next to the name (missing jobs…). The missing-point flag is built in. */
  warning?: (loc: L) => string | null;
  importable?: boolean;
  /** Load the owned copies of every location (private garages). */
  withGroups?: boolean;
  emptyTitle: string;
  emptyDescription: string;
  emptyIcon?: IconName;
}

type Id = string | number;
type StatusFilter = 'all' | 'enabled' | 'disabled';
type SortKey = 'name' | 'vehicles' | 'id';

/** Dev harness only (src/dev/mocks/admin.ts). */
type DevHint = { __devEdit?: number | 'new'; __devSelect?: number };

interface EditorState<L> {
  open: boolean;
  seed: L | null;
  session: number;
}

const SORTS: { value: SortKey; label: () => string; icon: IconName }[] = [
  { value: 'name', label: () => t('Name'), icon: 'sort' },
  { value: 'vehicles', label: () => t('Most vehicles'), icon: 'car' },
  { value: 'id', label: () => t('Id'), icon: 'hash' },
];

const byName = (a: Location, b: Location) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base', numeric: true });

function hasCapacity(l: Location): l is Location & { capacity: CapacityConfig } {
  return l.kind !== 'impound';
}

export function LocationListPage<L extends Location>({
  kind,
  data,
  refresh,
  setData,
  kindLabel,
  tags,
  facts,
  factsTitle,
  kpis,
  searchText,
  warning,
  importable = false,
  withGroups = false,
  emptyTitle,
  emptyDescription,
  emptyIcon = 'garage',
}: LocationListPageProps<L>) {
  const [query, setQuery] = useState('');
  const [vehicle, setVehicle] = useState<VehicleFilter>('all');
  const [status, setStatus] = useState<StatusFilter>('all');
  const [sort, setSort] = useState<SortKey>('name');
  const [hoverId, setHoverId] = useState<Id | null>(null);
  const [selectedId, setSelectedId] = useState<Id | null>(null);
  const [focusTick, setFocusTick] = useState(0);
  const [busy, setBusy] = useState<Record<string, Exclude<InspectorBusy, null>>>({});
  const [confirm, setConfirm] = useState<L | null>(null);
  const [deleting, setDeleting] = useState(false);
  const [importOpen, setImportOpen] = useState(false);
  const [editor, setEditor] = useState<EditorState<L>>({ open: false, seed: null, session: 0 });
  const [inset, setInset] = useState(0);
  /** Inspector folded to its header row (Fit all needed the room). */
  const [inspFolded, setInspFolded] = useState(false);
  const listRef = useRef<HTMLDivElement>(null);
  const toolbarRef = useRef<HTMLDivElement>(null);
  const inspRef = useRef<HTMLElement>(null);

  const all = useMemo(() => (data.locations.filter((l) => l.kind === kind) as L[]).sort(byName), [data.locations, kind]);

  /* ── private: owned copies ── */
  const privateIds = useMemo(() => (withGroups ? all.flatMap((l) => (typeof l.id === 'number' ? [l.id] : [])) : []), [all, withGroups]);
  const groups = usePrivateGroups(privateIds, {
    enabled: withGroups,
    paused: editor.open,
    priority: typeof selectedId === 'number' ? selectedId : null,
  });

  const ctx = useMemo<LocationPageContext>(
    () => ({ data, stats: (l) => statsOf(data, l), groups: groups.get, groupsComplete: groups.complete }),
    [data, groups.get, groups.complete],
  );

  /* ── filter + sort ── */
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    const list = all.filter((l) => {
      if (vehicle !== 'all' && l.vehicleType !== vehicle) return false;
      if (status === 'enabled' && !l.enabled) return false;
      if (status === 'disabled' && l.enabled) return false;
      if (!q) return true;
      const hay = `${l.name} #${l.id} ${l.id} ${searchText ? searchText(l) : ''}`.toLowerCase();
      return hay.includes(q);
    });
    if (sort === 'id') return [...list].sort((a, b) => (a.id ?? 0) - (b.id ?? 0));
    if (sort === 'vehicles') {
      return [...list].sort((a, b) => vehicleTotal(statsOf(data, b), kind) - vehicleTotal(statsOf(data, a), kind) || byName(a, b));
    }
    return list;
  }, [all, query, vehicle, status, sort, searchText, data, kind]);

  const selected = useMemo(() => (selectedId === null ? null : all.find((l) => l.id === selectedId) ?? null), [all, selectedId]);

  // The map brings off-screen matches into view when the filters change (search: once typing pauses).
  const [fitQuery, setFitQuery] = useState('');
  useEffect(() => {
    const timer = window.setTimeout(() => setFitQuery(query.trim().toLowerCase()), 250);
    return () => window.clearTimeout(timer);
  }, [query]);
  const fitKey = `${vehicle}|${status}|${fitQuery}`;

  // A selection hidden by the filters (or deleted elsewhere) closes the inspector.
  useEffect(() => {
    if (selectedId !== null && !filtered.some((l) => l.id === selectedId)) setSelectedId(null);
  }, [filtered, selectedId]);

  // A new selection opens the inspector unfolded.
  useEffect(() => setInspFolded(false), [selectedId]);

  /* ── inspector height → map inset ── */
  useLayoutEffect(() => {
    const el = inspRef.current;
    if (!el) {
      setInset(0);
      return;
    }
    const measure = () => setInset(el.offsetHeight + 12);
    measure();
    if (typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, [selected !== null]);

  /* ── editor ── */
  // Not cleared on unmount: React's StrictMode remount would cancel a dev-harness open, and a
  // late setState after a real unmount is a no-op.
  const openTimer = useRef<number>();
  const openEditor = useCallback(
    (seed: L | null) => {
      const go = () => setEditor((e) => ({ open: true, seed, session: e.session + 1 }));
      // The editor of a saved private garage loads its owners right away: keep clear of the
      // server's admin:groups rate limit (this page may have just asked for them).
      const wait = withGroups && seed && seed.id !== null ? groupsCooldown() : 0;
      window.clearTimeout(openTimer.current);
      if (wait > 0) openTimer.current = window.setTimeout(go, wait);
      else go();
    },
    [withGroups],
  );

  const closeEditor = () => {
    setEditor((e) => ({ ...e, open: false }));
    // Owners may have changed in the editor's "Owners & copies" tab.
    const id = editor.seed?.id;
    if (withGroups && typeof id === 'number') groups.reload(id);
  };

  /* dev harness: ?mock=admin-edit-… opens the editor, ?mock=admin-…-selected selects */
  const devHandled = useRef(false);
  useEffect(() => {
    if (!isBrowser || devHandled.current) return;
    const hint = data as AdminOpenData & DevHint;
    if (hint.__devEdit === undefined && hint.__devSelect === undefined) return;
    devHandled.current = true;
    if (hint.__devSelect !== undefined) {
      setSelectedId(hint.__devSelect);
      setFocusTick((n) => n + 1);
    }
    if (hint.__devEdit === 'new') openEditor(null);
    else if (hint.__devEdit !== undefined) {
      const loc = all.find((l) => l.id === hint.__devEdit);
      if (loc) openEditor(loc);
    }
  }, [data]);

  /* ── selection ── */
  const selectCard = useCallback((l: Location) => {
    if (l.id === null) return;
    setSelectedId(l.id);
    setInspFolded(false);
    setFocusTick((n) => n + 1);
  }, []);

  const selectFromMap = useCallback((id: Id | null) => {
    setSelectedId(id);
    if (id !== null) setInspFolded(false);
  }, []);
  const foldInspector = useCallback(() => setInspFolded(true), []);

  // Bring the selected card into view (after a pin click, keyboard move or save).
  useEffect(() => {
    if (selectedId === null) return;
    const raf = requestAnimationFrame(() => {
      const el = listRef.current?.querySelector<HTMLElement>(`[data-loc="${String(selectedId)}"]`);
      el?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    });
    return () => cancelAnimationFrame(raf);
  }, [selectedId]);

  /* ── actions ── */
  const setBusyFor = (id: Id, v: InspectorBusy) =>
    setBusy((b) => {
      const n = { ...b };
      if (v) n[String(id)] = v;
      else delete n[String(id)];
      return n;
    });

  const toggle = useCallback(
    async (l: Location) => {
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
    },
    [setData],
  );

  const teleport = async (l: L) => {
    const a = locationAnchor(l);
    if (!a || l.id === null) return;
    setBusyFor(l.id, 'teleport');
    const res = await request('admin:location:teleport', { coords: a });
    setBusyFor(l.id, null);
    if (res.ok) toast({ type: 'success', message: t('Teleported to {name}', { name: l.name }) });
  };

  const managePoints = async (l: L, which: PointKind) => {
    if (l.id === null) return;
    const id = l.id;
    const key = which === 'spawn' ? 'spawnPoints' : which === 'open' ? 'openPoints' : 'storePoints';
    const points = l[key] as Vec4[] | InteractionPoint[];
    const model =
      which === 'spawn' && (l.kind === 'garage' || l.kind === 'job') && l.source === 'spawner' ? l.spawner[0]?.model || undefined : undefined;
    setBusyFor(id, 'points');
    const res = await requestPoints({ kind: which, vehicleType: l.vehicleType, points, ...(model ? { model } : {}) });
    // null = the admin cancelled the tool: nothing changed.
    if (!res.ok || !Array.isArray(res.data) || JSON.stringify(res.data) === JSON.stringify(points)) {
      setBusyFor(id, null);
      return;
    }
    if (which !== 'store' && res.data.length === 0) {
      setBusyFor(id, null);
      toast({
        type: 'warning',
        message: which === 'open' ? t('Keep at least one open interaction: nothing was saved') : t('Keep at least one spawn point: nothing was saved'),
      });
      return;
    }
    const next = { ...l, [key]: res.data } as Location;
    const saved = await request('admin:location:save', { location: next });
    setBusyFor(id, null);
    if (!saved.ok) return;
    const loc = saved.data ?? next;
    setData((d) => ({ ...d, locations: d.locations.map((x) => (x.id === id ? loc : x)) }));
    toast({ type: 'success', message: t('Points of {name} were saved', { name: l.name }) });
    void refresh();
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
    closeEditor();
    if (saved.id !== null) {
      setSelectedId(saved.id);
      setFocusTick((n) => n + 1);
    }
    void refresh();
  };

  /* ── keyboard ── */
  const anyModal = editor.open || !!confirm || importOpen;
  // Esc closes the inspector first (never while a dialog is open: those own Escape).
  useEscape(() => setSelectedId(null), selectedId !== null && !anyModal);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== '/' || anyModal || isAdminHidden() || e.ctrlKey || e.metaKey || e.altKey) return;
      const el = e.target as HTMLElement | null;
      if (el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable)) return;
      const input = toolbarRef.current?.querySelector<HTMLInputElement>('input');
      if (!input) return;
      e.preventDefault();
      input.focus();
      input.select();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [anyModal]);

  // Enter edits / Delete asks to delete the selected location wherever the focus is on the page
  // (list, map, a map pin…), except in fields, on other buttons and while a dialog or menu is open.
  const keyState = useRef({ selected, anyModal, openEditor });
  keyState.current = { selected, anyModal, openEditor };
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Enter' && e.key !== 'Delete') return;
      const { selected: sel, anyModal: modal, openEditor: edit } = keyState.current;
      if (!sel || modal || isAdminHidden() || e.defaultPrevented || e.repeat) return;
      if (e.ctrlKey || e.metaKey || e.altKey || e.shiftKey) return;
      const el = e.target as HTMLElement | null;
      if (el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT' || el.isContentEditable)) return;
      if (document.querySelector('.nz-menu')) return;
      const pin = el?.closest<HTMLElement>('[data-pin]');
      // A focused pin of another location: Enter selects it (its own click), not an edit.
      if (pin && pin.dataset.pin !== String(sel.id)) return;
      if (!pin && el?.closest('button, a, [role="button"], [role="menuitem"], [role="switch"], .nz-toggle')) return;
      e.preventDefault();
      if (e.key === 'Enter') edit(sel);
      else setConfirm(sel);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const focusCard = (id: Id) =>
    requestAnimationFrame(() => listRef.current?.querySelector<HTMLElement>(`[data-loc="${String(id)}"]`)?.focus({ preventScroll: true }));

  const onListKey = (e: ReactKeyboardEvent<HTMLDivElement>) => {
    if ((e.target as HTMLElement).closest('.nz-toggle')) return;
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      if (!filtered.length) return;
      const i = filtered.findIndex((l) => l.id === selectedId);
      const next = e.key === 'ArrowDown' ? (i < 0 ? 0 : Math.min(filtered.length - 1, i + 1)) : i < 0 ? filtered.length - 1 : Math.max(0, i - 1);
      const l = filtered[next];
      if (l.id === null) return;
      setSelectedId(l.id);
      setFocusTick((n) => n + 1);
      focusCard(l.id);
    } else if (e.key === ' ' && selected) {
      // Enter / Delete: the page-wide handler above.
      e.preventDefault();
    }
  };

  /* ── map pins ── */
  const pins: MapPin[] = useMemo(
    () =>
      filtered.flatMap((l) => {
        const a = locationAnchor(l);
        if (!a || l.id === null) return [];
        const s = statsOf(data, l);
        const stat =
          kind === 'impound'
            ? plural(s.held, '{count} vehicle held', '{count} vehicles held')
            : s.parked + s.out + s.impounded > 0
              ? `${plural(s.parked, '{count} parked', '{count} parked')} · ${plural(s.out, '{count} out', '{count} out')}`
              : t('No vehicles yet');
        return [
          {
            id: l.id,
            x: a.x,
            y: a.y,
            label: l.name,
            type: l.vehicleType,
            muted: !l.enabled,
            meta: l.enabled ? `${vehicleTypeLabel(l.vehicleType)} · ${kindLabel(l)}` : `${t('Disabled')} · ${kindLabel(l)}`,
            stat,
            zone: l.zone?.points ?? null,
          },
        ];
      }),
    [filtered, data, kind, kindLabel],
  );

  const kpiItems = useMemo(() => kpis(all, ctx), [kpis, all, ctx]);
  const noun = kindNoun(kind);
  const hasAny = all.length > 0;
  const filteredOut = hasAny && filtered.length === 0;
  const filtersActive = query.trim() !== '' || vehicle !== 'all' || status !== 'all';
  const clearFilters = () => {
    setQuery('');
    setVehicle('all');
    setStatus('all');
  };

  const selBusy = selected && selected.id !== null ? busy[String(selected.id)] ?? null : null;

  return (
    <div className="nz-admin-cmd">
      <KpiStrip items={kpiItems} />

      <div className="nz-admin-cmd__body">
        {/* ── directory ── */}
        <aside className="nz-admin-cmd__dir" aria-label={t('Directory')}>
          <div className="nz-admin-cmd__toolbar" ref={toolbarRef}>
            <div className="nz-admin-cmd__toolbar-row">
              <SearchInput value={query} onChange={setQuery} placeholder={t('Search locations')} shortcut="/" className="nz-admin-cmd__search" />
              {importable && (
                <Button icon="import" onClick={() => setImportOpen(true)} title={t('Import from another garage script')} className="nz-admin-cmd__import">
                  {t('Import')}
                </Button>
              )}
              <Button variant="teal" icon="plus" onClick={() => openEditor(null)}>
                {t('Create')}
              </Button>
            </div>
            <div className="nz-admin-cmd__toolbar-row">
              <Segmented<VehicleFilter>
                size="sm"
                iconOnly
                value={vehicle}
                onChange={setVehicle}
                options={[
                  { value: 'all', label: t('All') },
                  { value: 'car', label: vehicleTypeLabel('car'), icon: vehicleTypeIcon('car') },
                  { value: 'sea', label: vehicleTypeLabel('sea'), icon: vehicleTypeIcon('sea') },
                  { value: 'air', label: vehicleTypeLabel('air'), icon: vehicleTypeIcon('air') },
                ]}
              />
              <Select<StatusFilter>
                size="sm"
                value={status}
                onChange={setStatus}
                className="nz-admin-cmd__select"
                options={[
                  { value: 'all', label: t('Status'), hint: t('Any'), icon: 'filter' },
                  { value: 'enabled', label: t('Enabled'), icon: 'checkCircle' },
                  { value: 'disabled', label: t('Disabled'), icon: 'ban' },
                ]}
              />
            </div>
          </div>

          <div className="nz-admin-cmd__dir-head">
            <span>
              {filtersActive
                ? t('{shown} of {total} shown', { shown: filtered.length, total: all.length })
                : plural(all.length, '{count} location', '{count} locations')}
            </span>
            {filtersActive && (
              <button type="button" className="nz-admin-cmd__link" onClick={clearFilters}>
                {t('Clear')}
              </button>
            )}
            <span className="nz-admin-cmd__grow" />
            {hasAny && (
              <Menu
                align="right"
                className="nz-admin-cmd__sort"
                items={SORTS.map((o) => ({
                  label: o.label(),
                  icon: o.value === sort ? 'check' : o.icon,
                  onSelect: () => setSort(o.value),
                }))}
                trigger={
                  <button type="button" className="nz-admin-cmd__sort-btn" aria-label={t('Sort by')}>
                    <Icon name="sort" size={12} strokeWidth={1.9} />
                    {SORTS.find((o) => o.value === sort)?.label()}
                    <Icon name="chevronDown" size={11} strokeWidth={2} />
                  </button>
                }
              />
            )}
          </div>

          <div
            ref={listRef}
            className={cx('nz-admin-cmd__list', !(hasAny && !filteredOut) && 'is-empty')}
            role="listbox"
            aria-label={t('Locations')}
            tabIndex={selectedId === null && filtered.length ? 0 : -1}
            onKeyDown={onListKey}
          >
            {hasAny && !filteredOut ? (
              filtered.map((l) => {
                const s = statsOf(data, l);
                const anchor = locationAnchor(l);
                const warn = !anchor ? t('No interaction point yet: edit it to place one') : warning?.(l) ?? null;
                return (
                  <LocationCard
                    key={l.id ?? l.name}
                    loc={l}
                    kind={kind}
                    tags={tags(l, ctx)}
                    stats={s}
                    selected={l.id === selectedId}
                    hovered={l.id === hoverId}
                    busy={l.id !== null && busy[String(l.id)] === 'toggle'}
                    warning={warn}
                    onSelect={selectCard}
                    onEdit={(x) => openEditor(x as L)}
                    onHover={setHoverId}
                    onToggle={(x) => void toggle(x)}
                  />
                );
              })
            ) : filteredOut ? (
              <EmptyState
                className="nz-admin-cmd__empty"
                icon="search"
                title={t('No matches')}
                description={t('Nothing matches your search or filters.')}
                action={
                  <Button size="sm" onClick={clearFilters}>
                    {t('Clear filters')}
                  </Button>
                }
              />
            ) : (
              <EmptyState
                className="nz-admin-cmd__empty"
                icon={emptyIcon}
                title={emptyTitle}
                description={emptyDescription}
                action={
                  <span className="nz-admin-cmd__empty-actions">
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

          {hasAny && (
            <div className="nz-admin-cmd__dir-foot" aria-hidden="true">
              <KeyHint keys={['ArrowUp', 'ArrowDown']} label={t('Select')} />
              <KeyHint keys={['Enter']} label={t('Edit')} />
              <KeyHint keys={['Delete']} label={t('Delete')} />
              <KeyHint keys={['/']} label={t('Search')} />
            </div>
          )}
        </aside>

        {/* ── map + inspector ── */}
        <div className="nz-admin-cmd__stage">
          <MapView
            className="nz-admin-cmd__map"
            pins={pins}
            selectedId={selectedId}
            hoverId={hoverId}
            onHover={setHoverId}
            onSelect={selectFromMap}
            onActivate={(id) => {
              const l = all.find((x) => x.id === id);
              if (l) openEditor(l);
            }}
            onMakeRoom={foldInspector}
            focusTick={focusTick}
            fitKey={fitKey}
            bottomInset={selected ? inset : 0}
            distanceUnit={data.settings?.interface?.distanceUnit === 'mi' ? 'mi' : 'km'}
            emptyText={
              hasAny ? (
                filteredOut ? t('No locations match the filters') : t('None of these locations has a point placed yet')
              ) : (
                <>
                  <b>{emptyTitle}</b>
                  <small>{t('Locations you create appear here.')}</small>
                </>
              )
            }
          />
          {selected && (
            <Inspector
              ref={inspRef}
              loc={selected}
              kindLabel={kindLabel(selected)}
              facts={facts(selected, ctx)}
              factsTitle={factsTitle}
              stats={statsOf(data, selected)}
              showOwners={withGroups}
              owners={withGroups ? groups.get(typeof selected.id === 'number' ? selected.id : null) : undefined}
              onRetryOwners={typeof selected.id === 'number' ? () => groups.reload(selected.id as number) : undefined}
              capacity={hasCapacity(selected) ? selected.capacity : undefined}
              capacityMeter={kind !== 'private'}
              spawner={(selected.kind === 'garage' || selected.kind === 'job') && selected.source === 'spawner' ? selected.spawner.length : null}
              busy={selBusy}
              folded={inspFolded}
              onUnfold={() => setInspFolded(false)}
              onClose={() => setSelectedId(null)}
              onEdit={() => openEditor(selected)}
              onTeleport={() => void teleport(selected)}
              onPoints={(k) => void managePoints(selected, k)}
              onToggle={() => void toggle(selected)}
              onDelete={() => setConfirm(selected)}
            />
          )}
        </div>
      </div>

      <LocationEditor
        key={editor.session}
        open={editor.open}
        kind={kind}
        seed={editor.seed}
        data={data}
        onClose={closeEditor}
        onSaved={onSaved}
      />

      {importable && (
        <ImportModal
          open={importOpen}
          sources={data.importSources}
          onClose={() => setImportOpen(false)}
          onImported={() => {
            setImportOpen(false);
            void refresh();
          }}
        />
      )}

      <ConfirmDialog
        open={!!confirm}
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

export type { CardTag, Fact, Kpi, LocationPageContext } from './commandTypes';
