/**
 * Impound app (app 'impound'): impounded vehicles at one impound lot.
 * Owners see their vehicles with the fee and a live availability countdown and can pay +
 * drive. Staff see every vehicle (with the owner) and can release it to the owner or send
 * it back to its garage. Reuses the garage collection (grid / list + inline panel).
 */
import { useEffect, useMemo, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import {
  Badge,
  Button,
  ConfirmDialog,
  EmptyState,
  Icon,
  KeyHint,
  PlateTag,
  SearchInput,
  Segmented,
  VehicleImage,
  Window,
  cx,
} from '@/components/ui';
import { useApp, useUi, toast } from '@/lib/store';
import { useEscape } from '@/lib/escape';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import { date, dateTime, distance, money } from '@/lib/format';
import type { ImpoundOpenData, ImpoundedVehicle } from '@/lib/types';
import { countdown, displayName, isAppOpen, matchesQuery, useNow, useSessionView } from '../garage/model';
import type { ViewMode } from '../garage/model';
import { VehicleCollection } from '../garage/VehicleCollection';
import { ConditionRings } from '../garage/VehicleTiles';
import { AvailabilityBadge, AvailabilityText, useAvailability } from '../garage/VehicleDetail';
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

function ImpoundWindow({ data, close }: { data: ImpoundOpenData; close: () => void }) {
  const { impound, staff, vehicles } = data;
  const [view, setView] = useSessionView('impound');
  const [query, setQuery] = useState('');
  const [expanded, setExpanded] = useState<string | null>(null);
  const [retrieving, setRetrieving] = useState<string | null>(null);
  const [releasing, setReleasing] = useState<{ plate: string; mode: 'owner' | 'garage' } | null>(null);
  const [confirmGarage, setConfirmGarage] = useState<string | null>(null);
  const timer = useRef<number>();

  useEscape(() => setExpanded(null), expanded !== null);
  useEffect(() => () => window.clearTimeout(timer.current), []);

  // Re-sort when a countdown finishes (once a minute is plenty for ordering).
  const minute = useNow(true, 60000);
  const shown = useMemo(() => {
    const now = Math.floor(Date.now() / 1000);
    return vehicles
      .filter((v) => matchesQuery(v, query) || (staff && v.ownerName.toLowerCase().includes(query.trim().toLowerCase())))
      .sort(
        (a, b) =>
          availabilityRank(a, now) - availabilityRank(b, now) ||
          a.impound.releaseAt - b.impound.releaseAt ||
          displayName(a).localeCompare(displayName(b)),
      );
    // `minute` re-runs the sort as vehicles become available.
  }, [vehicles, query, staff, minute]);

  const retrieve = async (v: ImpoundedVehicle) => {
    if (retrieving) return;
    setRetrieving(v.plate);
    const res = await request('impound:retrieve', { plate: v.plate });
    if (!res.ok) {
      setRetrieving(null);
      return;
    }
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setRetrieving(null), DRIVE_TIMEOUT);
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

  const viewOptions: { value: ViewMode; label: string; icon: 'grid' | 'list' }[] = [
    { value: 'grid', label: t('Grid view'), icon: 'grid' },
    { value: 'list', label: t('List view'), icon: 'list' },
  ];

  const confirmVehicle = vehicles.find((v) => v.plate === confirmGarage) ?? null;

  let content: JSX.Element;
  if (vehicles.length === 0) {
    content = (
      <EmptyState
        icon="impound"
        title={t('No impounded vehicles')}
        description={
          staff
            ? t('Nothing is being held at {place} right now.', { place: impound.name })
            : t('None of your vehicles are being held at {place}.', { place: impound.name })
        }
      />
    );
  } else if (shown.length === 0) {
    content = (
      <EmptyState
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
  } else {
    content = (
      <VehicleCollection<ImpoundedVehicle>
        items={shown}
        view={view}
        getKey={(v) => v.plate}
        expandedKey={expanded}
        onToggle={(plate) => setExpanded((cur) => (cur === plate ? null : plate))}
        renderCard={(v) => <ImpoundCard v={v} staff={staff} />}
        renderRow={(v, open) => <ImpoundRow v={v} staff={staff} open={open} />}
        renderDetail={(v) => (
          <ImpoundDetail
            feeWaived={!!data.feeWaived}
            v={v}
            staff={staff}
            variant={view}
            retrieving={retrieving}
            releasing={releasing}
            onCollapse={view === 'grid' ? () => setExpanded(null) : undefined}
            onRetrieve={() => void retrieve(v)}
            onReleaseOwner={() => void release(v, 'owner')}
            onReturnGarage={() => setConfirmGarage(v.plate)}
          />
        )}
      />
    );
  }

  return (
    <>
      <Window
        className="nz-garage nz-impound"
        bodyClassName="nz-garage__body"
        width={736}
        style={{ maxHeight: '86vh' }}
        title={impound.name}
        icon="warning"
        subtitle={staff ? t('Staff view — every vehicle held here') : t('Your impounded vehicles')}
        badge={
          staff ? (
            <span className="nz-garage__badges">
              <Badge tone="teal" icon="shield">
                {t('Staff')}
              </Badge>
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
            <span className="nz-garage__spacer" />
            {vehicles.length > 0 && <KeyHint keys={['Enter']} label={t('Details')} />}
            <KeyHint keys={['Esc']} label={expanded ? t('Collapse') : t('Close')} />
          </>
        }
      >
        <div className="nz-garage__toolbar nz-impound__toolbar">
          <SearchInput
            value={query}
            onChange={setQuery}
            placeholder={staff ? t('Search name, plate or owner') : t('Search name or plate')}
            className="nz-garage__search"
          />
          <Segmented<ViewMode> value={view} onChange={setView} options={viewOptions} iconOnly />
        </div>
        <div className={cx('nz-garage__scroll', 'nz-impound__scroll', `is-${view}`)}>{content}</div>
      </Window>

      <ConfirmDialog
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
    </>
  );
}

/* ── tiles ───────────────────────────────────────────────────────────── */

function ImpoundCard({ v, staff }: { v: ImpoundedVehicle; staff: boolean }) {
  const name = displayName(v);
  return (
    <>
      <div className="nz-garage__media">
        <VehicleImage image={v.image} vehicleType={v.vehicleType} alt={v.label} className="nz-garage__img" />
        <div className="nz-garage__overlay">
          <span className="nz-garage__backing">
            <AvailabilityBadge info={v.impound} />
          </span>
        </div>
      </div>
      <div className="nz-garage__cardbody">
        <b className="nz-garage__name" title={name}>
          {name}
        </b>
        {staff ? (
          <span className="nz-garage__sub nz-impound__owner">
            <Icon name="user" size={11} strokeWidth={1.8} />
            {v.isOwner ? t('You') : v.ownerName}
          </span>
        ) : (
          v.nickname && <span className="nz-garage__sub">{v.label}</span>
        )}
        <div className="nz-garage__meta">
          <PlateTag plate={v.plate} size="sm" />
          <span className="nz-garage__mileage">
            <Icon name="money" size={12} strokeWidth={1.8} />
            {v.impound.fee > 0 ? money(v.impound.fee) : t('Free')}
          </span>
        </div>
      </div>
    </>
  );
}

function ImpoundRow({ v, staff, open }: { v: ImpoundedVehicle; staff: boolean; open: boolean }) {
  const name = displayName(v);
  return (
    <>
      <div className="nz-garage__thumb">
        <VehicleImage image={v.image} vehicleType={v.vehicleType} alt={v.label} className="nz-garage__img" />
      </div>
      <div className="nz-garage__rowtext">
        <span className="nz-garage__rowtitle">
          <b className="nz-garage__name" title={name}>
            {name}
          </b>
          {staff ? (
            <span className="nz-garage__sub nz-impound__owner">
              <Icon name="user" size={11} strokeWidth={1.8} />
              {v.isOwner ? t('You') : v.ownerName}
            </span>
          ) : (
            v.nickname && <span className="nz-garage__sub">{v.label}</span>
          )}
        </span>
        <span className="nz-garage__meta">
          <PlateTag plate={v.plate} size="sm" />
          <span className="nz-garage__mileage">
            <Icon name="gauge" size={12} strokeWidth={1.8} />
            {distance(v.mileage)}
          </span>
          <span className="nz-garage__mileage">
            <Icon name="money" size={12} strokeWidth={1.8} />
            {v.impound.fee > 0 ? money(v.impound.fee) : t('Free')}
          </span>
        </span>
      </div>
      <div className="nz-garage__rowside">
        <AvailabilityBadge info={v.impound} />
        <Icon name="chevronDown" size={15} strokeWidth={1.8} className={cx('nz-garage__chev', open && 'is-open')} />
      </div>
    </>
  );
}

/* ── detail ──────────────────────────────────────────────────────────── */

function Cell({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="nz-garage__cell">
      <span className="nz-garage__cell-label">{label}</span>
      <span className="nz-garage__cell-value">{children}</span>
    </div>
  );
}

function ImpoundDetail({
  v,
  staff,
  variant,
  retrieving,
  releasing,
  onCollapse,
  onRetrieve,
  onReleaseOwner,
  onReturnGarage,
  feeWaived = false,
}: {
  v: ImpoundedVehicle;
  staff: boolean;
  feeWaived?: boolean;
  variant: ViewMode;
  retrieving: string | null;
  releasing: { plate: string; mode: 'owner' | 'garage' } | null;
  onCollapse?: () => void;
  onRetrieve: () => void;
  onReleaseOwner: () => void;
  onReturnGarage: () => void;
}) {
  const info = v.impound;
  const a = useAvailability(info);
  const name = displayName(v);
  const canCollect = !staff || v.isOwner;
  const available = a?.state === 'now';
  // The server's verdict (blocked, overdue finance, wrong vehicle type, staff override) wins.
  const serverAllows = v.canDrive !== false;
  const canDriveNow = serverAllows && (available || staff);
  const fee = staff && feeWaived ? 0 : info.fee;
  const isRetrieving = retrieving === v.plate;
  const busy = retrieving !== null || releasing !== null;

  return (
    <div className="nz-garage__dv">
      <div className="nz-garage__dv-head">
        <div className="nz-garage__dv-title">
          {variant === 'grid' && (
            <div className="nz-garage__dv-name">
              <b title={name}>{name}</b>
              {v.nickname && <span>{v.label}</span>}
            </div>
          )}
          <div className="nz-garage__dv-meta">
            {variant === 'grid' && <PlateTag plate={v.plate} />}
            {staff && (
              <span className="nz-garage__mileage">
                <Icon name="user" size={12} strokeWidth={1.8} />
                {t('Owner')} <b>{v.isOwner ? t('You') : v.ownerName}</b>
              </span>
            )}
            <span className="nz-garage__mileage" title={dateTime(info.at)}>
              <Icon name="calendar" size={12} strokeWidth={1.8} />
              {t('Impounded')} <b>{date(info.at)}</b>
            </span>
          </div>
        </div>
        <div className="nz-garage__dv-badges">
          <ConditionRings v={v} />
          {onCollapse && <Button variant="ghost" size="sm" icon="close" onClick={onCollapse} title={t('Collapse')} />}
        </div>
      </div>

      <div className="nz-garage__block is-danger">
        <div className="nz-garage__cells nz-garage__cells--4">
          <Cell label={t('Impounded by')}>{info.byName || t('Unknown')}</Cell>
          <Cell label={t('Reason')}>
            <span className="nz-garage__clamp" title={info.reason}>
              {info.reason || t('No reason given')}
            </span>
          </Cell>
          <Cell label={t('Retrieval fee')}>{info.fee > 0 ? money(info.fee) : t('Free')}</Cell>
          <Cell label={t('Available')}>
            <AvailabilityText info={info} />
          </Cell>
        </div>
      </div>

      {canCollect && !available && a && (
        <div className={cx('nz-garage__reason', a.state === 'release' ? 'is-red' : 'is-amber')}>
          <Icon name={a.state === 'release' ? 'lock' : 'clock'} size={14} strokeWidth={1.8} />
          <span>
            {a.state === 'release'
              ? t('Impound staff have to release this vehicle before you can pay the fee and drive it.')
              : t('You can collect it in {time} — on {date}.', { time: countdown(a.seconds), date: dateTime(info.releaseAt) })}
          </span>
        </div>
      )}

      {canCollect && available && !serverAllows && v.reason && (
        <div className="nz-garage__reason is-red">
          <Icon name="ban" size={14} strokeWidth={1.8} />
          <span>{v.reason}</span>
        </div>
      )}

      <div className="nz-garage__actions">
        <div className="nz-garage__actions-main">
          {canCollect && (
            <Button
              variant="teal"
              icon="arrowRight"
              loading={isRetrieving}
              disabled={!canDriveNow || (busy && !isRetrieving)}
              badge={!isRetrieving && fee > 0 ? money(fee) : undefined}
              onClick={onRetrieve}
            >
              {isRetrieving ? t('Loading vehicle...') : t('Drive')}
            </Button>
          )}
          {staff && (
            <>
              <Button
                variant={canCollect ? 'line' : 'white'}
                icon="unlock"
                loading={releasing?.plate === v.plate && releasing.mode === 'owner'}
                disabled={available || (busy && releasing?.plate !== v.plate)}
                title={available ? t('Already available to the owner') : undefined}
                onClick={onReleaseOwner}
              >
                {t('Release to owner')}
              </Button>
              <Button icon="garage" disabled={busy} onClick={onReturnGarage}>
                {t('Return to garage')}
              </Button>
            </>
          )}
        </div>
        {staff && !canCollect && (
          <span className="nz-impound__note">
            <Icon name="info" size={12} strokeWidth={1.8} />
            {available ? t('The owner can collect it now.') : t('Releasing makes it available right away.')}
          </span>
        )}
      </div>
    </div>
  );
}
