/**
 * Garage app (app 'garage'): the player's garage menu.
 * Header: garage name + type icon, Private / job badges, capacity meter, more menu.
 * Toolbar: group switcher, search, grid/list, Manage, Go inside. Filter chips + sort.
 * Vehicles in a grid or list with an inline detail panel; spawner garages list spawnable
 * vehicles instead. Modals: rename, transfer, share, sell, members, confirmations.
 */
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import {
  Button,
  Chip,
  ConfirmDialog,
  EmptyState,
  Badge,
  Icon,
  KeyHint,
  Menu,
  Meter,
  SearchInput,
  Segmented,
  Select,
  Window,
  cx,
} from '@/components/ui';
import type { MenuItem, SelectOption } from '@/components/ui';
import { useApp, useUi, toast } from '@/lib/store';
import { useEscape } from '@/lib/escape';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import { money } from '@/lib/format';
import type { GarageOpenData, GarageVehicle, SpawnerVehicleView } from '@/lib/types';
import {
  displayName,
  isAppOpen,
  isShared,
  kindLabel,
  matchesFilter,
  matchesQuery,
  sortVehicles,
  useSessionView,
  vehicleTypeIcon,
} from './model';
import type { GarageFilter, GarageSort, ViewMode } from './model';
import { VehicleCollection } from './VehicleCollection';
import { GarageCard, GarageRow } from './VehicleTiles';
import { VehicleDetail } from './VehicleDetail';
import { SpawnerCard, SpawnerRow } from './SpawnerTiles';
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

/* ── window ──────────────────────────────────────────────────────────── */

function GarageWindow({ data, close }: { data: GarageOpenData; close: () => void }) {
  const { garage, capacity, vehicles, spawner, options } = data;
  const spawnerMode = garage.source === 'spawner';

  const [view, setView] = useSessionView('garage');
  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState<GarageFilter>('all');
  const [sort, setSort] = useState<GarageSort>('relevance');
  const [expanded, setExpanded] = useState<string | null>(null);
  const [driving, setDriving] = useState<string | null>(null);
  const [spawning, setSpawning] = useState<number | null>(null);
  const [recovering, setRecovering] = useState<string | null>(null);
  const [modal, setModal] = useState<{ kind: ModalKind; plate: string } | null>(null);
  const [members, setMembers] = useState(false);
  const [pay, setPay] = useState<{ plate: string; full: boolean } | null>(null);
  const [paying, setPaying] = useState(false);
  const [sellGarage, setSellGarage] = useState(false);
  const [headerBusy, setHeaderBusy] = useState<HeaderBusy>(null);
  const driveTimer = useRef<number>();

  useEscape(() => setExpanded(null), expanded !== null);
  useEffect(() => () => window.clearTimeout(driveTimer.current), []);

  const byPlate = (plate: string | null | undefined) => (plate ? vehicles.find((v) => v.plate === plate) ?? null : null);

  /* ── derived lists ── */
  const searched = useMemo(() => vehicles.filter((v) => matchesQuery(v, query)), [vehicles, query]);
  const counts = useMemo(() => {
    const c: Record<GarageFilter, number> = { all: 0, favourites: 0, here: 0, shared: 0, impounded: 0, out: 0 };
    for (const v of searched) {
      c.all++;
      if (v.favourite) c.favourites++;
      if (matchesFilter(v, 'here')) c.here++;
      if (isShared(v)) c.shared++;
      if (v.state === 'impounded') c.impounded++;
      if (v.state === 'out') c.out++;
    }
    return c;
  }, [searched]);
  const anyOf = useMemo(
    () => ({
      shared: vehicles.some(isShared),
      impounded: vehicles.some((v) => v.state === 'impounded'),
      out: vehicles.some((v) => v.state === 'out'),
    }),
    [vehicles],
  );
  const chips: { value: GarageFilter; label: string }[] = [
    { value: 'all', label: t('All') },
    { value: 'favourites', label: t('Favourites') },
    { value: 'here', label: t('Parked here') },
  ];
  if (anyOf.shared) chips.push({ value: 'shared', label: t('Shared') });
  if (anyOf.impounded) chips.push({ value: 'impounded', label: t('Impounded') });
  if (anyOf.out) chips.push({ value: 'out', label: t('Out') });
  const activeFilter: GarageFilter = chips.some((c) => c.value === filter) ? filter : 'all';

  const shown = useMemo(
    () => sortVehicles(searched.filter((v) => matchesFilter(v, activeFilter)), sort),
    [searched, activeFilter, sort],
  );
  const shownSpawner = useMemo(
    () =>
      spawner
        .filter((s) => matchesQuery({ ...s, nickname: null }, query))
        .sort((a, b) => a.index - b.index),
    [spawner, query],
  );

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
    toast({
      type: 'success',
      title: t('Vehicle recovered'),
      message: v.recoverFee > 0
        ? t('{vehicle} is back for {fee}.', { vehicle: displayName(v), fee: money(v.recoverFee) })
        : t('{vehicle} is back.', { vehicle: displayName(v) }),
    });
    void refreshGarage();
  };

  const track = async (v: GarageVehicle) => {
    await request('garage:track', { plate: v.plate });
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

  /* ── header ── */
  const limited = !!capacity && capacity.mode === 'limited' && capacity.total > 0;
  const isFull = limited && capacity!.used >= capacity!.total;
  const menuItems: MenuItem[] = [];
  if (garage.isPrivate) {
    menuItems.push({
      label: garage.canManage ? t('Manage members') : t('View members'),
      icon: 'users',
      onSelect: () => setMembers(true),
    });
  }
  if (isFull && !spawnerMode) {
    menuItems.push({ label: t('Find a garage with space'), icon: 'route', onSelect: () => void directions() });
  }
  if (garage.canSellGarage) {
    menuItems.push({ label: t('Sell garage'), icon: 'tag', danger: true, onSelect: () => setSellGarage(true) });
  }

  const subtitle = [
    kindLabel(garage.kind, garage.vehicleType),
    garage.groups.length > 1 ? garage.groups.find((g) => g.id === garage.groupId)?.label : null,
    garage.role === 'owner' ? t('Owner') : garage.role === 'member' ? t('Member') : null,
    spawnerMode ? t('Spawner') : null,
  ]
    .filter(Boolean)
    .join(' · ');

  const badges =
    garage.isPrivate || garage.jobLabel ? (
      <span className="nz-garage__badges">
        {garage.isPrivate && (
          <Badge tone="neutral" icon="lock">
            {t('Private')}
          </Badge>
        )}
        {garage.jobLabel && (
          <Badge tone="teal" icon="briefcase">
            {garage.jobLabel}
          </Badge>
        )}
      </span>
    ) : undefined;

  const headerExtra = (
    <>
      {limited && (
        <Meter
          label={capacity!.appliesTo === 'player' ? t('Your spaces') : t('Spaces')}
          icon="parking"
          used={capacity!.used}
          total={capacity!.total}
        />
      )}
      {menuItems.length > 0 && <Menu items={menuItems} label={t('Garage options')} />}
    </>
  );

  /* ── toolbar ── */
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
  const viewOptions: { value: ViewMode; label: string; icon: 'grid' | 'list' }[] = [
    { value: 'grid', label: t('Grid view'), icon: 'grid' },
    { value: 'list', label: t('List view'), icon: 'list' },
  ];
  const sortOptions: SelectOption<GarageSort>[] = [
    { value: 'relevance', label: t('Relevance') },
    { value: 'name', label: t('Name') },
    { value: 'mileage', label: t('Mileage') },
    { value: 'condition', label: t('Condition') },
    { value: 'lastUsed', label: t('Last used') },
  ];

  const total = spawnerMode ? spawner.length : vehicles.length;
  const count = spawnerMode ? shownSpawner.length : shown.length;

  /* ── body content ── */
  let content: JSX.Element;
  if (spawnerMode) {
    content =
      spawner.length === 0 ? (
        <EmptyState
          icon={vehicleTypeIcon(garage.vehicleType)}
          title={t('No vehicles available')}
          description={t('There are no vehicles for your rank at this garage. Ask a supervisor if you need access.')}
        />
      ) : shownSpawner.length === 0 ? (
        <SearchEmpty query={query} onClear={() => setQuery('')} />
      ) : (
        <VehicleCollection<SpawnerVehicleView>
          items={shownSpawner}
          view={view}
          getKey={(s) => String(s.index)}
          renderCard={(s) => <SpawnerCard s={s} spawning={spawning} onDrive={() => void spawn(s)} />}
          renderRow={(s) => <SpawnerRow s={s} spawning={spawning} onDrive={() => void spawn(s)} />}
          className="nz-garage__collection--spawner"
        />
      );
  } else if (vehicles.length === 0) {
    content = (
      <EmptyState
        icon="garage"
        title={t('No vehicles here yet')}
        description={t('Drive a vehicle you own up to {garage} and store it — it will show up here.', { garage: garage.name })}
      />
    );
  } else if (shown.length === 0) {
    content = query ? (
      <SearchEmpty query={query} onClear={() => setQuery('')} />
    ) : (
      <FilterEmpty filter={activeFilter} onReset={() => setFilter('all')} />
    );
  } else {
    content = (
      <VehicleCollection<GarageVehicle>
        items={shown}
        view={view}
        getKey={(v) => v.plate}
        expandedKey={expanded}
        onToggle={(plate) => setExpanded((cur) => (cur === plate ? null : plate))}
        itemClass={(v) => (v.state === 'impounded' || v.blocked ? 'is-alert' : v.state === 'out' ? 'is-out' : undefined)}
        renderCard={(v) => <GarageCard v={v} onFavourite={() => void toggleFavourite(v)} />}
        renderRow={(v, open) => <GarageRow v={v} open={open} onFavourite={() => void toggleFavourite(v)} />}
        renderDetail={(v) => (
          <VehicleDetail
            v={v}
            options={options}
            variant={view}
            driving={driving}
            recovering={recovering === v.plate}
            onCollapse={view === 'grid' ? () => setExpanded(null) : undefined}
            onDrive={() => void drive(v)}
            onRecover={() => void recover(v)}
            onTransfer={() => setModal({ kind: 'transfer', plate: v.plate })}
            onSell={() => setModal({ kind: 'sell', plate: v.plate })}
            onShare={() => setModal({ kind: 'share', plate: v.plate })}
            onRename={() => setModal({ kind: 'rename', plate: v.plate })}
            onTrack={() => void track(v)}
            onFavourite={() => void toggleFavourite(v)}
            onPay={(full) => setPay({ plate: v.plate, full })}
          />
        )}
      />
    );
  }

  const modalVehicle = (kind: ModalKind) => (modal?.kind === kind ? byPlate(modal.plate) : null);
  const payVehicle = byPlate(pay?.plate);

  return (
    <>
      <Window
        className="nz-garage"
        bodyClassName="nz-garage__body"
        width={736}
        style={{ maxHeight: '86vh' }}
        title={garage.name}
        icon={vehicleTypeIcon(garage.vehicleType)}
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
            </span>
            {isFull && !spawnerMode && (
              <span className="nz-garage__foot-warn">
                <Icon name="warning" size={12} strokeWidth={1.8} />
                {t('Garage full')}
              </span>
            )}
            <span className="nz-garage__spacer" />
            {!spawnerMode && vehicles.length > 0 && <KeyHint keys={['Enter']} label={t('Details')} />}
            <KeyHint keys={['Esc']} label={expanded ? t('Collapse') : t('Close')} />
          </>
        }
      >
        <div className="nz-garage__toolbar">
          {garage.groups.length > 1 && (
            <Select<number>
              value={garage.groupId}
              onChange={(id) => void switchGroup(id)}
              options={groupOptions}
              icon="key"
              disabled={headerBusy === 'group'}
              className="nz-garage__group"
            />
          )}
          <SearchInput
            value={query}
            onChange={setQuery}
            placeholder={spawnerMode ? t('Search by name or model') : t('Search name or plate')}
            className="nz-garage__search"
          />
          <Segmented<ViewMode> value={view} onChange={setView} options={viewOptions} iconOnly />
          {garage.isPrivate && (
            <Button icon="users" onClick={() => setMembers(true)}>
              {garage.canManage ? t('Manage') : t('Members')}
            </Button>
          )}
          {garage.canGoInside && (
            <Button variant="white" icon="walk" loading={headerBusy === 'inside'} disabled={!!headerBusy && headerBusy !== 'inside'} onClick={() => void goInside()}>
              {t('Go inside')}
            </Button>
          )}
        </div>

        {!spawnerMode && vehicles.length > 0 && (
          <div className="nz-garage__filters">
            <ChipStrip label={t('Filter vehicles')}>
              {chips.map((c) => (
                <Chip key={c.value} active={activeFilter === c.value} onClick={() => setFilter(c.value)} count={counts[c.value]}>
                  {c.label}
                </Chip>
              ))}
            </ChipStrip>
            <Select<GarageSort> value={sort} onChange={setSort} options={sortOptions} icon="sort" size="sm" className="nz-garage__sort" />
          </div>
        )}
        {spawnerMode && spawner.length > 0 && (
          <div className="nz-garage__hintbar">
            <Icon name="info" size={13} strokeWidth={1.8} />
            <span>
              {garage.jobLabel
                ? t('{job} vehicles. Store them back here when your shift is over.', { job: garage.jobLabel })
                : t('Pick a vehicle to take out. Store it back here when you are done.')}
            </span>
          </div>
        )}

        <div className={cx('nz-garage__scroll', `is-${view}`)}>
          {isFull && !spawnerMode && vehicles.length > 0 && (
            <div className="nz-garage__notice">
              <Icon name="parking" size={15} strokeWidth={1.8} />
              <span>
                <b>{t('This garage is full.')}</b> {t('You can still take vehicles out, but nothing more can be stored here.')}
              </span>
              <Button size="sm" variant="line" icon="route" loading={headerBusy === 'directions'} onClick={() => void directions()}>
                {t('Find space')}
              </Button>
            </div>
          )}
          {content}
        </div>
      </Window>

      <RenameModal vehicle={modalVehicle('rename')} onClose={() => setModal(null)} onSave={(v, name) => void rename(v, name)} />
      <TransferModal vehicle={modalVehicle('transfer')} options={options} onClose={() => setModal(null)} onDone={() => void refreshGarage()} />
      <ShareModal vehicle={modalVehicle('share')} onClose={() => setModal(null)} onChanged={() => void refreshGarage()} />
      <SellModal vehicle={modalVehicle('sell')} onClose={() => setModal(null)} />
      <MembersModal open={members} garageName={garage.name} onClose={() => setMembers(false)} onChanged={() => void refreshGarage()} />

      <ConfirmDialog
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
        confirmLabel={pay?.full ? t('Pay {amount}', { amount: money(payVehicle?.finance?.balance ?? 0) }) : t('Pay {amount}', { amount: money(Math.min(payVehicle?.finance?.payment ?? 0, payVehicle?.finance?.balance ?? 0)) })}
        busy={paying}
        onConfirm={() => void confirmPay()}
        onCancel={() => setPay(null)}
      />
      <ConfirmDialog
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

/* ── chip strip: scrolls sideways (fade at the edge) only when it overflows ── */

function ChipStrip({ label, children }: { label: string; children: ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  const [overflow, setOverflow] = useState(false);
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const measure = () => setOverflow(el.scrollWidth > el.clientWidth + 1);
    measure();
    if (typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    Array.from(el.children).forEach((c) => ro.observe(c));
    return () => ro.disconnect();
  });
  return (
    <div
      ref={ref}
      className={cx('nz-garage__chips', overflow && 'is-overflow')}
      role="toolbar"
      aria-label={label}
      onWheel={(e) => {
        if (overflow && ref.current && Math.abs(e.deltaY) > Math.abs(e.deltaX)) ref.current.scrollLeft += e.deltaY;
      }}
    >
      {children}
    </div>
  );
}

/* ── empty states ────────────────────────────────────────────────────── */

function SearchEmpty({ query, onClear }: { query: string; onClear: () => void }) {
  return (
    <EmptyState
      icon="search"
      title={t('No vehicles match “{query}”', { query: query.trim() })}
      description={t('Try a name, nickname, model or plate.')}
      action={
        <Button size="sm" icon="close" onClick={onClear}>
          {t('Clear search')}
        </Button>
      }
    />
  );
}

function FilterEmpty({ filter, onReset }: { filter: GarageFilter; onReset: () => void }) {
  const copy: Record<GarageFilter, { icon: 'star' | 'parking' | 'users' | 'impound' | 'route' | 'garage'; title: string; desc: string }> = {
    all: { icon: 'garage', title: t('No vehicles'), desc: '' },
    favourites: {
      icon: 'star',
      title: t('No favourites yet'),
      desc: t('Tap the star on a vehicle to keep it at the top of your list.'),
    },
    here: {
      icon: 'parking',
      title: t('Nothing parked here'),
      desc: t('Your vehicles are stored at other garages or are out right now.'),
    },
    shared: { icon: 'users', title: t('No shared vehicles'), desc: t('Vehicles you share or that are shared with you show up here.') },
    impounded: { icon: 'impound', title: t('Nothing impounded'), desc: t('None of your vehicles are at an impound lot.') },
    out: { icon: 'route', title: t('Nothing out'), desc: t('All of your vehicles are parked.') },
  };
  const c = copy[filter];
  return (
    <EmptyState
      icon={c.icon}
      title={c.title}
      description={c.desc || undefined}
      action={
        <Button size="sm" icon="layers" onClick={onReset}>
          {t('Show all vehicles')}
        </Button>
      }
    />
  );
}
