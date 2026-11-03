/**
 * Garage app (app 'garage'): the player's garage as a two-pane "Showroom".
 * Left: the collection rail (search, filter chips, sort, group-by, density, rows grouped by
 * class or status). Right: the showcase of the selected vehicle (stage, status strip,
 * condition + damage glyph, performance, upgrades, finance / impound / trailer, action dock).
 * Spawner garages list spawnable vehicles in the same layout. Header: capacity slot strip,
 * private garage controls, Enter interior. Modals: rename, transfer, share, sell, members,
 * finance payment and sell-garage confirmations.
 */
import { useEffect, useMemo, useRef, useState } from 'react';
import {
  Badge,
  Button,
  ConfirmDialog,
  Icon,
  KeyHint,
  Menu,
  Select,
  Window,
  cx,
} from '@/components/ui';
import type { IconName, MenuItem, SelectOption } from '@/components/ui';
import { useApp, useUi, toast } from '@/lib/store';
import { useEscape } from '@/lib/escape';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import { money } from '@/lib/format';
import type { GarageOpenData, GarageVehicle, SpawnerVehicleView } from '@/lib/types';
import {
  classGroup,
  displayName,
  groupItems,
  isAppOpen,
  isHere,
  isShared,
  kindLabel,
  matchesFilter,
  matchesQuery,
  primaryKind,
  sortVehicles,
  statusGroup,
  useSessionChoice,
  useSessionView,
  vehicleTypeIcon,
} from './model';
import type { GarageFilter, GarageSort, GroupBy, ItemGroup, PrimaryKind } from './model';
import { RailList, RailSkeleton, RailVacant } from './showroom/Rail';
import { SlotStrip } from './showroom/SlotStrip';
import { useShowroomKeys } from './showroom/keys';
import { GarageRow, RailToolbar, SpawnerRow } from './GarageRail';
import { EmptyShowcase, SpawnerShowcase, VehicleShowcase } from './GarageShowcase';
import { RenameModal } from './modals/RenameModal';
import { TransferModal } from './modals/TransferModal';
import { ShareModal } from './modals/ShareModal';
import { SellModal } from './modals/SellModal';
import { MembersModal } from './modals/MembersModal';
import './garage.css';

type ModalKind = 'rename' | 'transfer' | 'share' | 'sell';
type HeaderBusy = 'inside' | 'group' | 'sellGarage' | 'directions' | null;

/** Keeps the Drive button in its loading state while Lua spawns the vehicle and closes the menu. */
const DRIVE_TIMEOUT = 15000;

export function GarageApp() {
  const { open, data, close } = useApp('garage');
  useEscape(close, open);
  if (!open || !data) return null;
  return <GarageWindow key={data.garage.key} data={data} close={close} />;
}

/* ── state helpers that always read the latest store data ─────────────── */

const current = () => useUi.getState().apps.garage.data;

function patchVehicle(plate: string, patch: Partial<GarageVehicle>) {
  const d = current();
  if (!d) return;
  useUi.getState().updateApp('garage', {
    vehicles: d.vehicles.map((v) => (v.plate === plate ? { ...v, ...patch } : v)),
  });
}

/** Re-fetch after an action. Quiet: Lua usually already pushed an 'update' and the
 *  server rate-limits refreshes, so a refused refresh is not worth an error toast. */
async function refreshGarage() {
  const res = await request('garage:refresh', {}, { toastError: false });
  if (res.ok && res.data && isAppOpen('garage')) useUi.getState().openApp('garage', res.data);
}

const typeWord = (type: GarageOpenData['garage']['vehicleType']) =>
  type === 'air' ? t('aircraft') : type === 'sea' ? t('boat') : t('vehicle');

/* ── window ──────────────────────────────────────────────────────────── */

function GarageWindow({ data, close }: { data: GarageOpenData; close: () => void }) {
  const { garage, capacity, vehicles, spawner, options } = data;
  const spawnerMode = garage.source === 'spawner';
  const bodyRef = useRef<HTMLDivElement>(null);

  const [view, setView] = useSessionView('garage');
  const compact = view === 'list';
  const [groupBy, setGroupBy] = useSessionChoice<GroupBy>('garage:groupBy', 'class');
  const [sort, setSort] = useSessionChoice<GarageSort>('garage:sort', 'relevance');
  const [query, setQueryRaw] = useState('');
  const [filter, setFilterRaw] = useState<GarageFilter>('all');
  const [selected, setSelected] = useState<string | null>(null);
  const lastIndex = useRef(0);

  const [driving, setDriving] = useState<string | null>(null);
  const [spawning, setSpawning] = useState<number | null>(null);
  const [recovering, setRecovering] = useState<string | null>(null);
  const [tracking, setTracking] = useState<string | null>(null);
  const [modal, setModal] = useState<{ kind: ModalKind; plate: string } | null>(null);
  const [members, setMembers] = useState(false);
  const [pay, setPay] = useState<{ plate: string; full: boolean } | null>(null);
  const [confirmRecover, setConfirmRecover] = useState<string | null>(null);
  const [paying, setPaying] = useState(false);
  const [sellGarage, setSellGarage] = useState(false);
  const [headerBusy, setHeaderBusy] = useState<HeaderBusy>(null);
  const driveTimer = useRef<number>();

  useEffect(() => () => window.clearTimeout(driveTimer.current), []);

  const setQuery = (q: string) => {
    lastIndex.current = 0;
    setQueryRaw(q);
  };
  const setFilter = (f: GarageFilter) => {
    lastIndex.current = 0;
    setFilterRaw(f);
  };

  const byPlate = (plate: string | null | undefined) => (plate ? vehicles.find((v) => v.plate === plate) ?? null : null);

  /* ── owned vehicles: search → filter → sort → group ── */
  const searched = useMemo(() => vehicles.filter((v) => matchesQuery(v, query)), [vehicles, query]);
  const counts = useMemo(() => {
    const c: Record<GarageFilter, number> = { all: 0, favourites: 0, here: 0, shared: 0, impounded: 0, out: 0 };
    for (const v of searched) {
      c.all++;
      if (v.favourite) c.favourites++;
      if (isHere(v)) c.here++;
      if (isShared(v)) c.shared++;
      if (v.state === 'impounded') c.impounded++;
      if (v.state === 'out') c.out++;
    }
    return c;
  }, [searched]);
  // Chips exist when the whole collection has such vehicles (they do not vanish while typing).
  const present = useMemo(
    () => ({
      favourites: vehicles.some((v) => v.favourite),
      here: vehicles.some(isHere),
      shared: vehicles.some(isShared),
      impounded: vehicles.some((v) => v.state === 'impounded'),
      out: vehicles.some((v) => v.state === 'out'),
    }),
    [vehicles],
  );
  const chips = (
    [
      { value: 'all', label: t('All'), on: true },
      { value: 'favourites', label: t('Favourites'), icon: 'star', on: present.favourites },
      { value: 'here', label: t('Here'), on: present.here },
      { value: 'shared', label: t('Shared'), on: present.shared },
      { value: 'impounded', label: t('Impounded'), on: present.impounded },
      { value: 'out', label: t('Out'), on: present.out },
    ] as { value: GarageFilter; label: string; icon?: IconName; on: boolean }[]
  )
    .filter((c) => c.on)
    .map((c) => ({ value: c.value, label: c.label, icon: c.icon, count: counts[c.value] }));
  const activeFilter: GarageFilter = chips.some((c) => c.value === filter) ? filter : 'all';

  const shown = useMemo(
    () => sortVehicles(searched.filter((v) => matchesFilter(v, activeFilter)), sort),
    [searched, activeFilter, sort],
  );
  const groups: ItemGroup<GarageVehicle>[] = useMemo(() => {
    if (groupBy === 'none') return [{ key: 'all', label: '', items: shown }];
    return groupItems(shown, groupBy === 'status' ? statusGroup : classGroup);
  }, [shown, groupBy]);

  /* ── spawner vehicles ── */
  const shownSpawner = useMemo(
    () =>
      spawner
        .filter((s) => matchesQuery({ ...s, nickname: null }, query))
        .sort((a, b) => a.index - b.index),
    [spawner, query],
  );
  const spawnerGroups: ItemGroup<SpawnerVehicleView>[] = useMemo(() => {
    if (groupBy === 'none') return [{ key: 'all', label: '', items: shownSpawner }];
    return groupItems(shownSpawner, classGroup);
  }, [shownSpawner, groupBy]);

  /* ── selection (always a visible row; falls back to the same position) ── */
  const flatKeys = useMemo(
    () =>
      spawnerMode
        ? spawnerGroups.flatMap((g) => g.items.map((s) => String(s.index)))
        : groups.flatMap((g) => g.items.map((v) => v.plate)),
    [spawnerMode, spawnerGroups, groups],
  );
  const currentKey =
    selected !== null && flatKeys.includes(selected)
      ? selected
      : flatKeys[Math.min(lastIndex.current, flatKeys.length - 1)] ?? null;
  useEffect(() => {
    const i = currentKey ? flatKeys.indexOf(currentKey) : -1;
    if (i >= 0) lastIndex.current = i;
  }, [currentKey, flatKeys]);

  const sv = !spawnerMode ? byPlate(currentKey) : null;
  const ss = spawnerMode ? spawner.find((s) => String(s.index) === currentKey) ?? null : null;

  /* ── actions ── */
  const toggleFavourite = async (v: GarageVehicle) => {
    const value = !v.favourite;
    patchVehicle(v.plate, { favourite: value });
    const res = await request('garage:favourite', { plate: v.plate, value });
    if (!res.ok) patchVehicle(v.plate, { favourite: !value });
  };

  const drive = async (v: GarageVehicle) => {
    if (driving || !v.canDrive) return;
    setDriving(v.plate);
    const res = await request('garage:drive', { plate: v.plate });
    if (!res.ok) {
      setDriving(null);
      return;
    }
    // Lua closes the menu once the vehicle is out; release the button if it does not.
    window.clearTimeout(driveTimer.current);
    driveTimer.current = window.setTimeout(() => setDriving(null), DRIVE_TIMEOUT);
  };

  const spawn = async (s: SpawnerVehicleView) => {
    if (spawning !== null) return;
    setSpawning(s.index);
    const res = await request('garage:spawner', { index: s.index });
    if (!res.ok) {
      setSpawning(null);
      return;
    }
    window.clearTimeout(driveTimer.current);
    driveTimer.current = window.setTimeout(() => setSpawning(null), DRIVE_TIMEOUT);
  };

  const recover = async (v: GarageVehicle) => {
    if (recovering) return;
    setRecovering(v.plate);
    const res = await request('garage:recover', { plate: v.plate });
    setRecovering(null);
    if (!res.ok) return;
    setConfirmRecover(null);
    toast({
      type: 'success',
      title: t('Vehicle recovered'),
      message:
        v.recoverFee > 0
          ? t('{vehicle} is back for {fee}.', { vehicle: displayName(v), fee: money(v.recoverFee) })
          : t('{vehicle} is back.', { vehicle: displayName(v) }),
    });
    void refreshGarage();
  };

  /** Recovering costs money: confirm first (the same way a finance payment does). */
  const askRecover = (v: GarageVehicle) => {
    if (recovering || !v.canRecover) return;
    if (v.recoverFee > 0) setConfirmRecover(v.plate);
    else void recover(v);
  };

  const track = async (v: GarageVehicle) => {
    if (tracking) return;
    setTracking(v.plate);
    await request('garage:track', { plate: v.plate });
    setTracking(null);
  };

  const rename = async (v: GarageVehicle, name: string | null) => {
    const before = v.nickname;
    setModal(null);
    patchVehicle(v.plate, { nickname: name });
    const res = await request('garage:rename', { plate: v.plate, name });
    if (!res.ok) {
      patchVehicle(v.plate, { nickname: before });
      return;
    }
    toast({ type: 'success', message: name ? t('Renamed to {name}.', { name }) : t('Name reset to {name}.', { name: v.label }) });
    void refreshGarage();
  };

  const confirmPay = async () => {
    const v = byPlate(pay?.plate);
    if (!pay || !v || paying) return;
    setPaying(true);
    const res = await request('garage:payFinance', { plate: pay.plate, full: pay.full });
    setPaying(false);
    if (!res.ok) return;
    patchVehicle(pay.plate, { finance: pay.full ? null : res.data ?? null });
    toast({
      type: 'success',
      title: pay.full ? t('Finance paid off') : t('Payment made'),
      message: pay.full
        ? t('{vehicle} is fully paid off.', { vehicle: displayName(v) })
        : t('Paid {amount} towards {vehicle}.', { amount: money(v.finance?.payment ?? 0), vehicle: displayName(v) }),
    });
    setPay(null);
    void refreshGarage();
  };

  const goInside = async () => {
    if (headerBusy) return;
    setHeaderBusy('inside');
    const res = await request('garage:goInside', {});
    if (!res.ok || isAppOpen('garage')) setHeaderBusy(null);
  };

  const switchGroup = async (groupId: number) => {
    if (groupId === garage.groupId || headerBusy) return;
    setHeaderBusy('group');
    const res = await request('garage:switchGroup', { groupId });
    setHeaderBusy(null);
    if (res.ok && res.data && isAppOpen('garage')) useUi.getState().openApp('garage', res.data);
  };

  const directions = async () => {
    if (headerBusy) return;
    setHeaderBusy('directions');
    await request('garage:directions', {});
    setHeaderBusy(null);
  };

  const confirmSellGarage = async () => {
    setHeaderBusy('sellGarage');
    const res = await request('garage:sellGarage', {});
    setHeaderBusy(null);
    if (res.ok) setSellGarage(false);
  };

  /* ── keyboard ── */
  const anyModal = !!modal || members || !!pay || sellGarage || !!confirmRecover;
  // What Enter does for the selection (the dock's primary action); null → nothing.
  const primary: PrimaryKind | 'spawn' = ss ? 'spawn' : sv ? primaryKind(sv) : null;
  const enterKind = primary === 'pay' && !sv?.isOwner ? null : primary;
  const enterLabel: Record<NonNullable<PrimaryKind> | 'spawn', string> = {
    spawn: t('Take out'),
    drive: t('Drive'),
    recover: t('Recover'),
    pay: t('Pay'),
    waypoint: t('Set waypoint'),
  };
  const focusSearch = () => bodyRef.current?.querySelector<HTMLInputElement>('.nz-garage__search input')?.focus();
  useShowroomKeys(!anyModal, {
    move: (dir) => {
      if (!flatKeys.length) return;
      const i = currentKey ? flatKeys.indexOf(currentKey) : -1;
      setSelected(flatKeys[Math.max(0, Math.min(flatKeys.length - 1, i + dir))]);
    },
    enter: () => {
      if (ss) void spawn(ss);
      if (!sv) return;
      if (enterKind === 'drive') void drive(sv);
      else if (enterKind === 'recover') askRecover(sv);
      else if (enterKind === 'pay') setPay({ plate: sv.plate, full: false });
      else if (enterKind === 'waypoint') void track(sv);
    },
    favourite: spawnerMode ? undefined : () => sv && void toggleFavourite(sv),
    rename: spawnerMode ? undefined : () => sv?.isOwner && setModal({ kind: 'rename', plate: sv.plate }),
    focusSearch,
  });

  /* ── header ── */
  const limited = !!capacity && capacity.mode === 'limited' && capacity.total > 0;
  const isFull = limited && capacity!.used >= capacity!.total && !spawnerMode;
  // "Find a garage with space" lives in the rail's Garage full notice (shown whenever it is full).
  const menuItems: MenuItem[] = [];
  if (garage.canSellGarage) menuItems.push({ label: t('Sell garage'), icon: 'tag', danger: true, onSelect: () => setSellGarage(true) });

  // Group labels usually repeat the garage name ("La Mesa Motor Club #2"): show the distinct part.
  const groupLabel = (label: string) => {
    const rest = label.startsWith(garage.name) ? label.slice(garage.name.length).trim() : '';
    if (!rest) return label;
    return rest.startsWith('#') ? t('Copy {n}', { n: rest }) : rest;
  };
  const groupOptions: SelectOption<number>[] = garage.groups.map((g) => ({
    value: g.id,
    label: groupLabel(g.label),
    hint: groupLabel(g.label) !== g.label ? g.label : undefined,
    icon: 'key',
  }));
  const activeGroup = garage.groups.find((g) => g.id === garage.groupId);

  const subtitle = [
    kindLabel(garage.kind, garage.vehicleType),
    garage.isPrivate && activeGroup && garage.groups.length > 1 ? groupLabel(activeGroup.label) : null,
    garage.role === 'owner' ? t('Owner') : garage.role === 'member' ? t('Member') : null,
    garage.jobLabel,
    spawnerMode ? t('Fleet') : null,
  ]
    .filter(Boolean)
    .join(' · ');

  const badges =
    garage.isPrivate || garage.kind === 'house' ? (
      <span className="nz-garage__badges">
        {garage.isPrivate && (
          <Badge tone="neutral" icon="lock" size="sm">
            {t('Private')}
          </Badge>
        )}
        {garage.kind === 'house' && (
          <Badge tone="neutral" icon="key" size="sm">
            {t('Home')}
          </Badge>
        )}
      </span>
    ) : undefined;

  // Private garage controls share the header with the slot strip: keep everything compact.
  const busyHeader = garage.isPrivate || garage.groups.length > 1;
  const headerExtra = (
    <>
      {garage.groups.length > 1 && (
        <Select<number>
          value={garage.groupId}
          onChange={(id) => void switchGroup(id)}
          options={groupOptions}
          icon="key"
          size="sm"
          disabled={!!headerBusy}
          className="nz-garage__groupsel"
        />
      )}
      {garage.isPrivate && (
        <Button size="sm" icon="users" onClick={() => setMembers(true)} className="nz-garage__members" title={t('Members')}>
          {t('Members')}
        </Button>
      )}
      {menuItems.length > 0 && <Menu items={menuItems} label={t('Garage options')} />}
      {!spawnerMode && <SlotStrip capacity={capacity} stored={vehicles.filter(isHere).length} compact={busyHeader} />}
      {garage.canGoInside && (
        <Button
          size="sm"
          variant="line"
          icon="walk"
          loading={headerBusy === 'inside'}
          disabled={!!headerBusy && headerBusy !== 'inside'}
          onClick={() => void goInside()}
          className="nz-garage__inside"
          title={t('Enter interior')}
        >
          {t('Enter interior')}
        </Button>
      )}
    </>
  );

  /* ── rail ── */
  const total = spawnerMode ? spawner.length : vehicles.length;
  const count = spawnerMode ? shownSpawner.length : shown.length;
  const clearAll = () => {
    setQuery('');
    setFilter('all');
  };
  const filtered = query.trim() !== '' || activeFilter !== 'all';

  const fullNotice = isFull ? (
    <div className="nz-garage__notice">
      <Icon name="parking" size={14} strokeWidth={1.8} />
      <span>
        <b>{t('Garage full.')}</b> {t('You can still take vehicles out.')}
      </span>
      <Button size="sm" variant="ghost" icon="route" loading={headerBusy === 'directions'} onClick={() => void directions()}>
        {t('Find space')}
      </Button>
    </div>
  ) : null;

  let railList: JSX.Element;
  if (headerBusy === 'group') {
    railList = <RailSkeleton compact={compact} />;
  } else if (spawnerMode) {
    railList =
      spawner.length === 0 ? (
        <RailVacant label={t('0 vehicles for your rank')} />
      ) : shownSpawner.length === 0 ? (
        <RailVacant icon="search" label={t('No matches')} bays={false} />
      ) : (
        <RailList<SpawnerVehicleView>
          groups={spawnerGroups}
          getKey={(s) => String(s.index)}
          selected={currentKey}
          onSelect={setSelected}
          onActivate={(k) => {
            const s = spawner.find((x) => String(x.index) === k);
            if (s) void spawn(s);
          }}
          compact={compact}
          label={t('Vehicles')}
          renderRow={(s) => <SpawnerRow s={s} compact={compact} />}
        />
      );
  } else if (vehicles.length === 0) {
    railList = <RailVacant label={t('0 vehicles stored')} />;
  } else if (shown.length === 0) {
    // The showcase explains it (and offers Clear filters): the rail only says so.
    railList = <RailVacant icon={query.trim() ? 'search' : 'filter'} label={t('No matches')} bays={false} />;
  } else {
    railList = (
      <RailList<GarageVehicle>
        groups={groups}
        getKey={(v) => v.plate}
        selected={currentKey}
        onSelect={setSelected}
        onActivate={(plate) => {
          const v = byPlate(plate);
          if (v?.canDrive) void drive(v);
        }}
        compact={compact}
        label={t('Vehicles')}
        rowClass={(v) => cx(`is-${v.state}`, !v.canDrive && 'is-locked')}
        renderRow={(v) => <GarageRow v={v} compact={compact} onFavourite={() => void toggleFavourite(v)} />}
      />
    );
  }

  /* ── showcase ── */
  let showcase: JSX.Element;
  if (spawnerMode) {
    showcase = ss ? (
      <SpawnerShowcase s={ss} garage={garage} spawning={spawning} onSpawn={() => void spawn(ss)} />
    ) : spawner.length === 0 ? (
      <EmptyShowcase
        icon="lock"
        title={t('Nothing to take out')}
        description={t('There are no vehicles for your rank at this garage. Ask a supervisor if you need access.')}
      />
    ) : (
      <NoMatch query={query} onClear={clearAll} spawner />
    );
  } else if (sv) {
    showcase = (
      <VehicleShowcase
        v={sv}
        garage={garage}
        options={options}
        driving={driving}
        recovering={recovering === sv.plate}
        tracking={tracking === sv.plate}
        onDrive={() => void drive(sv)}
        onRecover={() => askRecover(sv)}
        onTrack={() => void track(sv)}
        onRename={() => setModal({ kind: 'rename', plate: sv.plate })}
        onTransfer={() => setModal({ kind: 'transfer', plate: sv.plate })}
        onShare={() => setModal({ kind: 'share', plate: sv.plate })}
        onSell={() => setModal({ kind: 'sell', plate: sv.plate })}
        onFavourite={() => void toggleFavourite(sv)}
        onPay={(full) => setPay({ plate: sv.plate, full })}
      />
    );
  } else if (vehicles.length === 0) {
    const word = typeWord(garage.vehicleType);
    showcase = (
      <EmptyShowcase
        icon="garage"
        title={t('Your showroom is empty')}
        description={t('Nothing is parked at {garage} yet.', { garage: garage.name })}
        steps={[
          { icon: vehicleTypeIcon(garage.vehicleType), text: t('Bring a {type} you own (or one shared with you) to {garage}.', { type: word, garage: garage.name }) },
          { icon: 'parking', text: t('Stop at the marked store point and use the store prompt.') },
          { icon: 'arrowRight', text: t('It appears here, ready to drive out again.') },
        ]}
      />
    );
  } else {
    showcase = <NoMatch query={query} filter={activeFilter} onClear={clearAll} />;
  }

  const modalVehicle = (kind: ModalKind) => (modal?.kind === kind ? byPlate(modal.plate) : null);
  const payVehicle = byPlate(pay?.plate);
  const recoverVehicle = byPlate(confirmRecover);
  const hereCount = vehicles.filter(isHere).length;

  return (
    <>
      <Window
        className={cx('nz-garage', busyHeader && 'is-busyhead')}
        bodyClassName="nz-garage__body"
        width="min(1240px, 94vw)"
        height="min(930px, 92vh)"
        title={garage.name}
        icon={garage.kind === 'house' ? 'building' : spawnerMode || garage.kind === 'job' ? 'briefcase' : vehicleTypeIcon(garage.vehicleType)}
        subtitle={subtitle}
        badge={badges}
        headerExtra={headerExtra}
        onClose={close}
        footer={
          <>
            <span>
              {count === total ? (
                <>
                  <b>{count}</b> {t('vehicle(s)')}
                </>
              ) : (
                <>
                  <b>{count}</b> {t('of {total} vehicle(s)', { total })}
                </>
              )}
              {!spawnerMode && hereCount > 0 && (
                <>
                  {' · '}
                  <b>{hereCount}</b> {t('parked here')}
                </>
              )}
            </span>
            {isFull && (
              <span className="nz-garage__foot-warn">
                <Icon name="warning" size={12} strokeWidth={1.8} />
                {t('Garage full')}
              </span>
            )}
            <span className="nz-garage__spacer" />
            {count > 0 && <KeyHint keys={['ArrowUp', 'ArrowDown']} label={t('Select')} />}
            {enterKind && <KeyHint keys={['Enter']} label={enterLabel[enterKind]} />}
            {sv && <KeyHint keys={['F']} label={t('Favourite')} />}
            {sv?.isOwner && <KeyHint keys={['R']} label={t('Rename')} />}
            {total > 0 && <KeyHint keys={['/']} label={t('Search')} />}
            <KeyHint keys={['Esc']} label={t('Close')} />
          </>
        }
      >
        <div ref={bodyRef} className={cx('nz-garage__layout', headerBusy === 'group' && 'is-busy')}>
          <aside className="nz-garage__rail" aria-label={t('Your vehicles')}>
            <RailToolbar
              query={query}
              onQuery={setQuery}
              placeholder={spawnerMode ? t('Search name or model') : t('Search name, plate or class')}
              bare={spawnerMode ? spawner.length === 0 : vehicles.length === 0}
              chips={spawnerMode || vehicles.length === 0 ? undefined : chips}
              filter={activeFilter}
              onFilter={setFilter}
              sort={spawnerMode ? undefined : sort}
              onSort={setSort}
              groupBy={spawnerMode && groupBy === 'status' ? 'class' : groupBy}
              onGroupBy={setGroupBy}
              groupOptions={
                spawnerMode
                  ? [
                      { value: 'class', label: t('By class'), icon: 'layers' },
                      { value: 'none', label: t('No groups'), icon: 'list' },
                    ]
                  : undefined
              }
              view={view}
              onView={setView}
              notice={fullNotice}
            />
            {railList}
            {filtered && count > 0 && (
              <button type="button" className="nz-garage__railfoot" onClick={clearAll}>
                <Icon name="close" size={11} strokeWidth={2} />
                {t('Showing {count} of {total} · clear filters', { count, total })}
              </button>
            )}
          </aside>
          <main className="nz-garage__stagearea">{showcase}</main>
        </div>
      </Window>

      <RenameModal vehicle={modalVehicle('rename')} onClose={() => setModal(null)} onSave={(v, name) => void rename(v, name)} />
      <TransferModal vehicle={modalVehicle('transfer')} options={options} onClose={() => setModal(null)} onDone={() => void refreshGarage()} />
      <ShareModal vehicle={modalVehicle('share')} onClose={() => setModal(null)} onChanged={() => void refreshGarage()} />
      <SellModal vehicle={modalVehicle('sell')} onClose={() => setModal(null)} />
      <MembersModal open={members} garageName={garage.name} onClose={() => setMembers(false)} onChanged={() => void refreshGarage()} />

      <ConfirmDialog
        className="nz-garage-modal"
        open={!!pay && !!payVehicle?.finance}
        tone="teal"
        icon="money"
        title={pay?.full ? t('Pay off the finance?') : t('Make a payment?')}
        message={
          payVehicle?.finance ? (
            pay?.full ? (
              <>
                {t('Pay the remaining balance of')} <b>{money(payVehicle.finance.balance)}</b> {t('for')}{' '}
                <b>{displayName(payVehicle)}</b>. {t('No more payments will be taken.')}
              </>
            ) : (
              <>
                {t('Pay')} <b>{money(Math.min(payVehicle.finance.payment, payVehicle.finance.balance))}</b> {t('towards')}{' '}
                <b>{displayName(payVehicle)}</b>.{' '}
                {payVehicle.finance.paymentsLeft > 1
                  ? t('{n} payment(s) will be left after this one.', { n: payVehicle.finance.paymentsLeft - 1 })
                  : t('This is the last payment.')}
              </>
            )
          ) : null
        }
        confirmLabel={
          pay?.full
            ? t('Pay {amount}', { amount: money(payVehicle?.finance?.balance ?? 0) })
            : t('Pay {amount}', { amount: money(Math.min(payVehicle?.finance?.payment ?? 0, payVehicle?.finance?.balance ?? 0)) })
        }
        busy={paying}
        onConfirm={() => void confirmPay()}
        onCancel={() => setPay(null)}
      />
      <ConfirmDialog
        className="nz-garage-modal"
        open={!!recoverVehicle && recoverVehicle.canRecover}
        tone="teal"
        icon="refresh"
        title={t('Recover {vehicle}?', { vehicle: recoverVehicle ? displayName(recoverVehicle) : '' })}
        message={
          recoverVehicle ? (
            <>
              {t('Its last position is unknown.')} {t('Pay')} <b>{money(recoverVehicle.recoverFee)}</b>{' '}
              {t('and it is brought back to')} <b>{garage.name}</b>.
            </>
          ) : null
        }
        confirmLabel={t('Pay {fee}', { fee: money(recoverVehicle?.recoverFee ?? 0) })}
        busy={!!recovering}
        onConfirm={() => recoverVehicle && void recover(recoverVehicle)}
        onCancel={() => setConfirmRecover(null)}
      />
      <ConfirmDialog
        className="nz-garage-modal"
        open={sellGarage}
        tone="red"
        icon="tag"
        title={t('Sell this garage?')}
        message={
          <>
            {t('You are about to sell')} <b>{garage.name}</b>.{' '}
            {t('It has to be empty first. Every member loses access and part of the price is refunded to you.')}
          </>
        }
        confirmLabel={t('Sell garage')}
        busy={headerBusy === 'sellGarage'}
        onConfirm={() => void confirmSellGarage()}
        onCancel={() => setSellGarage(false)}
      />
    </>
  );
}

/* ── search / filter empty state (showcase) ─────────────────────────── */

function NoMatch({
  query,
  filter = 'all',
  onClear,
  spawner = false,
}: {
  query: string;
  filter?: GarageFilter;
  onClear: () => void;
  spawner?: boolean;
}) {
  const q = query.trim();
  const copy: Partial<Record<GarageFilter, string>> = {
    favourites: t('Tap the star on a vehicle to keep it at the top of your list.'),
    here: t('Your vehicles are stored at other garages or are out right now.'),
    shared: t('Vehicles you share or that are shared with you show up here.'),
    impounded: t('None of your vehicles are at an impound lot.'),
    out: t('All of your vehicles are parked.'),
  };
  return (
    <EmptyShowcase
      icon={q ? 'search' : 'filter'}
      title={q ? t('No vehicles match “{query}”', { query: q }) : t('No vehicles match')}
      description={
        spawner
          ? t('Try another name or model.')
          : q
            ? t('Try a name, nickname, model, class or plate.')
            : copy[filter] ?? t('Nothing in your collection fits this search or filter.')
      }
      action={
        <Button size="sm" icon="close" onClick={onClear}>
          {spawner ? t('Clear search') : t('Clear filters')}
        </Button>
      }
    />
  );
}
