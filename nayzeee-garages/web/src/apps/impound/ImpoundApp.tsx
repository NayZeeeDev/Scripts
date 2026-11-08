/**
 * Impound app (app 'impound'): the impound lot as a showroom, same pattern as the garage.
 * Rail: impounded vehicles grouped by availability (available / waiting / on hold), search
 * (staff also by owner). Showcase: the vehicle on the stage, a status strip (impounded,
 * fee, availability, owner / mileage), impound details with a live release countdown,
 * condition + damage glyph, performance; dock: "Pay $fee & drive out" for the owner and
 * "Release to owner" / "Return to garage" for staff.
 */
import { useEffect, useMemo, useRef, useState } from 'react';
import { Badge, Button, ConfirmDialog, Icon, KeyHint, PlateTag, Window, cx } from '@/components/ui';
import type { IconName } from '@/components/ui';
import type { SelectOption } from '@/components/ui';
import { useApp, useUi, toast } from '@/lib/store';
import { useEscape } from '@/lib/escape';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import { dateTime, distance, money } from '@/lib/format';
import type { ImpoundOpenData, ImpoundedVehicle } from '@/lib/types';
import {
  ago,
  classGroup,
  countdown,
  displayName,
  groupItems,
  isAppOpen,
  matchesQuery,
  modelName,
  normDamage,
  useNow,
  useSessionChoice,
  useSessionView,
  vehicleIcon,
} from '../garage/model';
import type { GroupBy, ItemGroup } from '../garage/model';
import { RailList, RailVacant, RowBody, StatusDot } from '../garage/showroom/Rail';
import { ClassTag, Plate, Stage, StageTitle } from '../garage/showroom/Stage';
import { ConditionBlock, ImpoundBlock, PerformanceBlock, StripCell, useAvailability } from '../garage/showroom/blocks';
import { useShowroomKeys } from '../garage/showroom/keys';
import { glyphShape } from '../garage/showroom/DamageGlyph';
import { RailToolbar } from '../garage/GarageRail';
import { EmptyShowcase, PrimaryLabel, ShowcaseFrame, Tool } from '../garage/GarageShowcase';
import { PreviewContext, PreviewVeil, useVehiclePreview } from '../garage/showroom/preview';
import '../garage/garage.css';
import './impound.css';

const DRIVE_TIMEOUT = 15000;

export function ImpoundApp() {
  const { open, data, close } = useApp('impound');
  useEscape(close, open);
  if (!open || !data) return null;
  return <ImpoundWindow key={data.impound.id} data={data} close={close} />;
}

/** 0 = available now, 1 = waiting, 2 = release required. */
function availabilityRank(v: ImpoundedVehicle, now: number) {
  if (!v.impound.retrievable) return 2;
  return v.impound.releaseAt > now ? 1 : 0;
}

const AVAIL_GROUPS = [
  { key: 'a:now', label: () => t('Available now') },
  { key: 'a:wait', label: () => t('Waiting') },
  { key: 'a:hold', label: () => t('On hold') },
];

function ImpoundWindow({ data, close }: { data: ImpoundOpenData; close: () => void }) {
  const { impound, staff, vehicles } = data;
  const bodyRef = useRef<HTMLDivElement>(null);
  const [view, setView] = useSessionView('impound');
  const compact = view === 'list';
  const [groupBy, setGroupBy] = useSessionChoice<GroupBy>('impound:groupBy', 'status');
  const [query, setQueryRaw] = useState('');
  const [selected, setSelected] = useState<string | null>(null);
  const lastIndex = useRef(0);
  const [retrieving, setRetrieving] = useState<string | null>(null);
  const [releasing, setReleasing] = useState<{ plate: string; mode: 'owner' | 'garage' } | null>(null);
  const [confirmGarage, setConfirmGarage] = useState<string | null>(null);
  const [confirmCollect, setConfirmCollect] = useState<string | null>(null);
  const timer = useRef<number>();

  useEffect(() => () => window.clearTimeout(timer.current), []);

  const setQuery = (q: string) => {
    lastIndex.current = 0;
    setQueryRaw(q);
  };

  // Re-sort / regroup when a countdown finishes (once a minute is plenty for ordering).
  const minute = useNow(true, 60000);
  const shown = useMemo(() => {
    const now = Math.floor(Date.now() / 1000);
    const q = query.trim().toLowerCase();
    return vehicles
      .filter((v) => matchesQuery(v, query) || (staff && !!q && (v.ownerName ?? '').toLowerCase().includes(q)))
      .sort(
        (a, b) =>
          availabilityRank(a, now) - availabilityRank(b, now) ||
          a.impound.releaseAt - b.impound.releaseAt ||
          displayName(a).localeCompare(displayName(b)),
      );
    // `minute` re-runs the sort as vehicles become available.
  }, [vehicles, query, staff, minute]);

  const groups: ItemGroup<ImpoundedVehicle>[] = useMemo(() => {
    if (groupBy === 'none') return [{ key: 'all', label: '', items: shown }];
    if (groupBy === 'class') return groupItems(shown, classGroup);
    const now = Math.floor(Date.now() / 1000);
    return groupItems(shown, (v) => {
      const r = availabilityRank(v, now);
      return { key: AVAIL_GROUPS[r].key, label: AVAIL_GROUPS[r].label(), order: r };
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [shown, groupBy, minute]);

  const flatKeys = useMemo(() => groups.flatMap((g) => g.items.map((v) => v.plate)), [groups]);
  const currentKey =
    selected !== null && flatKeys.includes(selected)
      ? selected
      : flatKeys[Math.min(lastIndex.current, flatKeys.length - 1)] ?? null;
  useEffect(() => {
    const i = currentKey ? flatKeys.indexOf(currentKey) : -1;
    if (i >= 0) lastIndex.current = i;
  }, [currentKey, flatKeys]);
  const sv = vehicles.find((v) => v.plate === currentKey) ?? null;

  /* ── 3D preview of the selection ── */
  const previewPlate = sv?.plate ?? null;
  const previewTarget = useMemo(() => (previewPlate ? { plate: previewPlate } : null), [previewPlate]);
  const preview = useVehiclePreview('impound', previewTarget, data.previewStopped);

  const retrieve = async (v: ImpoundedVehicle) => {
    if (retrieving) return;
    setRetrieving(v.plate);
    const res = await request('impound:retrieve', { plate: v.plate });
    if (!res.ok) {
      setRetrieving(null);
      return;
    }
    // Paid: the dock keeps "Loading vehicle..." until Lua closes the menu.
    setConfirmCollect(null);
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setRetrieving(null), DRIVE_TIMEOUT);
  };

  /** The fee the player pays to collect `v` (staff with "fees waived" pay nothing). */
  const feeFor = (v: ImpoundedVehicle) => (staff && data.feeWaived ? 0 : Math.max(0, v.impound.fee));

  /** Collecting costs money: confirm first, the same way the garage's Recover does. */
  const askCollect = (v: ImpoundedVehicle) => {
    if (retrieving) return;
    if (feeFor(v) > 0) setConfirmCollect(v.plate);
    else void retrieve(v);
  };

  const release = async (v: ImpoundedVehicle, mode: 'owner' | 'garage') => {
    if (releasing) return;
    setReleasing({ plate: v.plate, mode });
    const res = await request('impound:release', { plate: v.plate, mode });
    setReleasing(null);
    setConfirmGarage(null);
    if (!res.ok) return;
    toast({
      type: 'success',
      title: mode === 'owner' ? t('Released to owner') : t('Returned to garage'),
      message:
        mode === 'owner'
          ? t('{owner} can now collect {vehicle} here.', { owner: v.ownerName, vehicle: displayName(v) })
          : t('{vehicle} was sent back to its garage, free of charge.', { vehicle: displayName(v) }),
    });
    if (res.data && isAppOpen('impound')) useUi.getState().openApp('impound', res.data);
  };

  // What Enter does: collect (owner, or staff with their own vehicle) or release (staff).
  const nowS = Math.floor(Date.now() / 1000);
  const primary = sv ? impoundPrimary(sv, staff, nowS) : null;

  useShowroomKeys(!confirmGarage && !confirmCollect, {
    move: (dir) => {
      if (!flatKeys.length) return;
      const i = currentKey ? flatKeys.indexOf(currentKey) : -1;
      setSelected(flatKeys[Math.max(0, Math.min(flatKeys.length - 1, i + dir))]);
    },
    enter: () => {
      if (!sv || retrieving || releasing) return;
      const p = impoundPrimary(sv, staff, Math.floor(Date.now() / 1000));
      if (p === 'collect') askCollect(sv);
      else if (p === 'release') void release(sv, 'owner');
    },
    focusSearch: () => bodyRef.current?.querySelector<HTMLInputElement>('.nz-garage__search input')?.focus(),
  });

  const groupOptions: SelectOption<GroupBy>[] = [
    { value: 'status', label: t('By availability'), icon: 'clock' },
    { value: 'class', label: t('By class'), icon: 'layers' },
    { value: 'none', label: t('No groups'), icon: 'list' },
  ];
  const confirmVehicle = vehicles.find((v) => v.plate === confirmGarage) ?? null;
  const collectVehicle = vehicles.find((v) => v.plate === confirmCollect) ?? null;

  let railList: JSX.Element;
  if (vehicles.length === 0) {
    railList = <RailVacant icon="impound" label={t('0 vehicles held')} />;
  } else if (shown.length === 0) {
    railList = <RailVacant icon="search" label={t('No matches')} bays={false} />;
  } else {
    railList = (
      <RailList<ImpoundedVehicle>
        groups={groups}
        getKey={(v) => v.plate}
        selected={currentKey}
        onSelect={setSelected}
        compact={compact}
        label={t('Impounded vehicles')}
        renderRow={(v) => <ImpoundRow v={v} staff={staff} feeWaived={!!data.feeWaived} compact={compact} />}
      />
    );
  }

  const showcase = sv ? (
    <ImpoundShowcase
      v={sv}
      staff={staff}
      feeWaived={!!data.feeWaived}
      retrieving={retrieving}
      releasing={releasing}
      onRetrieve={() => askCollect(sv)}
      onReleaseOwner={() => void release(sv, 'owner')}
      onReturnGarage={() => setConfirmGarage(sv.plate)}
    />
  ) : vehicles.length === 0 ? (
    <EmptyShowcase
      icon="checkCircle"
      title={staff ? t('The lot is empty') : t('Nothing to collect')}
      description={
        staff
          ? t('Vehicles you or your colleagues impound to {place} show up here.', { place: impound.name })
          : t('Your vehicles are not being held here. Check your garages if one is missing.')
      }
    />
  ) : (
    <EmptyShowcase
      icon="search"
      title={t('No vehicles match “{query}”', { query: query.trim() })}
      description={staff ? t('Try a name, plate or owner.') : t('Try a name, model or plate.')}
      action={
        <Button size="sm" icon="close" onClick={() => setQuery('')}>
          {t('Clear search')}
        </Button>
      }
    />
  );

  const now = Math.floor(Date.now() / 1000);
  const readyCount = vehicles.filter((v) => availabilityRank(v, now) === 0).length;

  return (
    <PreviewContext.Provider value={preview}>
      <PreviewVeil state={preview} />
      <Window
        className={cx('nz-garage nz-impound', preview.live && 'is-live')}
        bodyClassName="nz-garage__body"
        width="min(1240px, 94vw)"
        height="min(930px, 92vh)"
        title={impound.name}
        icon="impound"
        subtitle={staff ? t('Impound lot · staff view, every vehicle held here') : t('Impound lot · your vehicles held here')}
        badge={
          staff ? (
            <span className="nz-garage__badges">
              <Badge tone="teal" icon="shield" size="sm">
                {t('Staff')}
              </Badge>
              {data.feeWaived && (
                <Badge tone="neutral" icon="money" size="sm">
                  {t('Fees waived')}
                </Badge>
              )}
            </span>
          ) : undefined
        }
        headerExtra={
          vehicles.length > 0 ? (
            <span className="nz-impound__tally">
              <span>
                <b>{vehicles.length}</b> {t('held')}
              </span>
              <i aria-hidden="true" />
              <span className="is-teal">
                <b>{readyCount}</b> {t('ready')}
              </span>
            </span>
          ) : undefined
        }
        onClose={close}
        footer={
          <>
            <span>
              <b>{shown.length}</b>{' '}
              {shown.length === vehicles.length ? t('vehicle(s)') : t('of {total} vehicle(s)', { total: vehicles.length })}
            </span>
            <span className="nz-garage__keybar">
              {shown.length > 0 && <KeyHint keys={['ArrowUp', 'ArrowDown']} label={t('Select')} />}
              {primary && (
                <KeyHint
                  keys={['Enter']}
                  label={primary === 'release' ? t('Release') : sv && feeFor(sv) > 0 ? t('Pay & drive') : t('Drive out')}
                />
              )}
              {vehicles.length > 0 && <KeyHint keys={['/']} label={t('Search')} />}
              <KeyHint keys={['Esc']} label={t('Close')} />
            </span>
          </>
        }
      >
        <div ref={bodyRef} className="nz-garage__layout">
          <aside className="nz-garage__rail" aria-label={t('Impounded vehicles')}>
            <RailToolbar
              query={query}
              onQuery={setQuery}
              placeholder={staff ? t('Search name, plate or owner') : t('Search name or plate')}
              bare={vehicles.length === 0}
              groupBy={groupBy}
              onGroupBy={setGroupBy}
              groupOptions={groupOptions}
              view={view}
              onView={setView}
            />
            {railList}
          </aside>
          <main className="nz-garage__stagearea">{showcase}</main>
        </div>
      </Window>

      <ConfirmDialog
        className="nz-garage-modal"
        open={!!collectVehicle}
        tone="teal"
        icon="money"
        title={t('Pay {fee} and drive out {vehicle}?', {
          fee: money(collectVehicle ? feeFor(collectVehicle) : 0),
          vehicle: collectVehicle ? displayName(collectVehicle) : '',
        })}
        message={
          collectVehicle ? (
            <>
              {t('The impound fee of')} <b>{money(feeFor(collectVehicle))}</b> {t('is paid now and')}{' '}
              <b>{displayName(collectVehicle)}</b> ({collectVehicle.plate}) {t('is brought out for you to drive.')}
            </>
          ) : null
        }
        confirmLabel={t('Pay {fee}', { fee: money(collectVehicle ? feeFor(collectVehicle) : 0) })}
        busy={!!collectVehicle && retrieving === collectVehicle.plate}
        onConfirm={() => collectVehicle && void retrieve(collectVehicle)}
        onCancel={() => setConfirmCollect(null)}
      />
      <ConfirmDialog
        className="nz-garage-modal"
        open={!!confirmVehicle}
        tone="red"
        icon="garage"
        title={t('Return to garage?')}
        message={
          confirmVehicle ? (
            <>
              <b>{displayName(confirmVehicle)}</b> ({confirmVehicle.plate}) {t('goes back to its last garage.')}{' '}
              {t('The {fee} fee is waived and the impound record is cleared.', {
                fee: money(confirmVehicle.impound.fee),
              })}
            </>
          ) : null
        }
        confirmLabel={t('Return to garage')}
        busy={releasing?.mode === 'garage'}
        onConfirm={() => confirmVehicle && void release(confirmVehicle, 'garage')}
        onCancel={() => setConfirmGarage(null)}
      />
    </PreviewContext.Provider>
  );
}

/* ── row ─────────────────────────────────────────────────────────────── */

/** Dock primary for a vehicle: 'collect' (pay & drive), 'release' (staff, to its owner) or none. */
function impoundPrimary(v: ImpoundedVehicle, staff: boolean, now: number): 'collect' | 'release' | null {
  const available = v.impound.retrievable && v.impound.releaseAt <= now;
  if (!staff || v.isOwner) return v.canDrive !== false && (available || staff) ? 'collect' : null;
  return available ? null : 'release';
}

function ImpoundRow({ v, staff, feeWaived, compact }: { v: ImpoundedVehicle; staff: boolean; feeWaived: boolean; compact: boolean }) {
  const a = useAvailability(v.impound);
  const nick = (v.nickname ?? '').trim();
  const tone = a?.state === 'now' ? 'teal' : a?.state === 'waiting' ? 'amber' : 'red';
  const label = a?.state === 'now' ? t('Available') : a?.state === 'waiting' ? t('In {time}', { time: countdown(a.seconds) }) : t('On hold');
  return (
    <RowBody
      image={v.image}
      vehicleType={v.vehicleType}
      alt={v.label}
      compact={compact}
      title={nick || modelName(v)}
      aside={staff ? (v.isOwner ? t('You') : v.ownerName) : nick ? modelName(v) : undefined}
      dot={tone}
      meta={
        compact ? (
          <PlateTag plate={v.plate} size="sm" />
        ) : (
          <>
            <PlateTag plate={v.plate} size="sm" />
            <StatusDot tone={tone} label={label} />
          </>
        )
      }
      side={
        <span className={cx('nz-garage__price', (v.impound.fee <= 0 || (staff && feeWaived)) && 'is-free')}>
          {v.impound.fee <= 0 ? t('No fee') : staff && feeWaived ? t('Waived') : money(v.impound.fee)}
        </span>
      }
      health={v.body}
    />
  );
}

/* ── showcase ────────────────────────────────────────────────────────── */

function ImpoundShowcase({
  v,
  staff,
  feeWaived,
  retrieving,
  releasing,
  onRetrieve,
  onReleaseOwner,
  onReturnGarage,
}: {
  v: ImpoundedVehicle;
  staff: boolean;
  feeWaived: boolean;
  retrieving: string | null;
  releasing: { plate: string; mode: 'owner' | 'garage' } | null;
  onRetrieve: () => void;
  onReleaseOwner: () => void;
  onReturnGarage: () => void;
}) {
  const info = v.impound;
  const a = useAvailability(info);
  const collect = !staff || v.isOwner;
  const available = a?.state === 'now';
  // The server's verdict (blocked, overdue finance, wrong vehicle type, staff override) wins.
  const serverAllows = v.canDrive !== false;
  const canDriveNow = serverAllows && (available || staff);
  const fee = staff && feeWaived ? 0 : info.fee;
  const isRetrieving = retrieving === v.plate;
  const busy = retrieving !== null || releasing !== null;
  const owner = v.isOwner ? t('You') : v.ownerName;

  let reason: { tone: 'neutral' | 'amber' | 'red'; icon: IconName; text: string } | null = null;
  if (collect && a && !available && !staff) {
    reason =
      a.state === 'release'
        ? { tone: 'red', icon: 'lock', text: t('Impound staff have to release this vehicle before you can pay the fee and drive it.') }
        : { tone: 'amber', icon: 'clock', text: t('You can collect it in {time} — on {date}.', { time: countdown(a.seconds), date: dateTime(info.releaseAt) }) };
  } else if (collect && !serverAllows && v.reason) {
    reason = { tone: 'red', icon: 'ban', text: v.reason };
  } else if (!collect) {
    reason = available
      ? { tone: 'neutral', icon: 'info', text: t('The owner can collect it now, or you can return it to its garage.') }
      : {
          tone: a?.state === 'release' ? 'red' : 'neutral',
          icon: a?.state === 'release' ? 'lock' : 'info',
          text:
            a?.state === 'release'
              ? t('On hold until staff release it. Releasing makes it collectable right away.')
              : t('Releasing makes it collectable right away, without waiting.'),
        };
  }
  const isReleasing = releasing?.plate === v.plate && releasing.mode === 'owner';

  const availValue = !a ? '—' : a.state === 'now' ? t('Now') : a.state === 'waiting' ? countdown(a.seconds) : t('On hold');
  const availTone = !a ? undefined : a.state === 'now' ? ('teal' as const) : a.state === 'waiting' ? ('amber' as const) : ('red' as const);

  return (
    <ShowcaseFrame
      id={v.plate}
      stage={
        <Stage
          id={v.plate}
          image={v.image}
          vehicleType={v.vehicleType}
          alt={v.label}
          className="nz-impound__stage"
          topLeft={
            <>
              <ClassTag icon={<Icon name={vehicleIcon(v)} size={13} strokeWidth={1.8} />} label={v.classLabel || t('Vehicle')} />
              <Badge tone="red" icon="impound" size="sm">
                {t('Impounded')}
              </Badge>
            </>
          }
          topRight={
            staff ? (
              <Badge tone={v.isOwner ? 'white' : 'neutral'} icon="user" size="sm">
                {owner}
              </Badge>
            ) : undefined
          }
          title={<StageTitle make={v.make} name={modelName(v)} nickname={v.nickname} />}
          plate={<Plate plate={v.plate} />}
        />
      }
      strip={
        <>
          <StripCell icon="calendar" label={t('Impounded')} value={ago(info.at)} sub={dateTime(info.at)} />
          <StripCell
            icon="money"
            label={t('Fee')}
            value={fee > 0 ? money(fee) : info.fee > 0 ? t('Waived') : t('No charge')}
            sub={info.fee > 0 && fee === 0 ? t('Normally {fee}', { fee: money(info.fee) }) : fee > 0 ? t('Paid on collection') : t('Nothing to pay')}
            tone={fee > 0 ? undefined : 'teal'}
          />
          <StripCell
            icon="clock"
            label={t('Available')}
            value={availValue}
            sub={a?.state === 'release' ? t('Release required') : dateTime(info.releaseAt)}
            tone={availTone}
          />
          {staff ? (
            <StripCell icon="user" label={t('Owner')} value={owner} sub={v.isOwner ? t('Your vehicle') : t('Player vehicle')} />
          ) : (
            <StripCell icon="gauge" label={t('Mileage')} value={distance(v.mileage)} sub={t('On the clock')} />
          )}
        </>
      }
      dock={
        <>
          <div className="nz-garage__dock-main">
            {!collect &&
              (available ? (
                <Button variant="line" size="lg" icon="checkCircle" disabled className="nz-garage__go">
                  {t('Released')}
                </Button>
              ) : (
                <Button
                  variant="white"
                  size="lg"
                  icon="unlock"
                  loading={isReleasing}
                  disabled={busy && !isReleasing}
                  onClick={onReleaseOwner}
                  className="nz-garage__go"
                >
                  <PrimaryLabel keycap={!isReleasing}>{isReleasing ? t('Releasing...') : t('Release to owner')}</PrimaryLabel>
                </Button>
              ))}
            {collect && (
              <Button
                variant="teal"
                size="lg"
                icon="arrowRight"
                loading={isRetrieving}
                disabled={!canDriveNow || (busy && !isRetrieving)}
                onClick={onRetrieve}
                className="nz-garage__go"
              >
                <PrimaryLabel keycap={!isRetrieving && canDriveNow}>
                  {isRetrieving
                    ? t('Loading vehicle...')
                    : fee > 0
                      ? t('Pay {fee} & drive out', { fee: money(fee) })
                      : t('Drive out')}
                </PrimaryLabel>
              </Button>
            )}
            {reason && (
              <span className={cx('nz-garage__dock-reason', `is-${reason.tone}`)}>
                <Icon name={reason.icon} size={13} strokeWidth={1.9} />
                <span>{reason.text}</span>
              </span>
            )}
          </div>
          {staff && (
            <div className="nz-garage__tools" role="toolbar" aria-label={t('Staff actions')}>
              {collect && (
                <Tool
                  icon="unlock"
                  label={isReleasing ? t('Releasing...') : t('Release')}
                  onClick={onReleaseOwner}
                  disabled={available || busy}
                  tip={available ? t('Already available') : t('Make it collectable right away')}
                />
              )}
              <Tool icon="garage" label={t('Return to garage')} onClick={onReturnGarage} disabled={busy} tip={t('Send it back to its last garage, free')} />
            </div>
          )}
        </>
      }
    >
      <ImpoundBlock info={info} lot />
      <ConditionBlock
        engine={v.engine}
        body={v.body}
        fuel={v.fuel}
        damage={normDamage(v.damage)}
        shape={glyphShape(v.vehicleType, v.classId, v.model)}
        needsService={v.needsService}
      />
      {v.stats && <PerformanceBlock stats={v.stats} />}
    </ShowcaseFrame>
  );
}
