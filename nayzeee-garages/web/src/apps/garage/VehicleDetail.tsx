/**
 * Expanded vehicle panel: identity, condition stats, finance, impound info, trailer,
 * the reason it cannot be driven, and the action bar (Drive, Recover, Transfer, Sell,
 * Share, favourite, more menu).
 */
import type { ReactNode } from 'react';
import { Badge, Button, Icon, IconButton, Menu, Pips, PlateTag, Stat, cx } from '@/components/ui';
import type { MenuItem } from '@/components/ui';
import { t } from '@/lib/i18n';
import { dateTime, distance, hoursLabel, money } from '@/lib/format';
import type { Finance, GarageOptions, GarageVehicle, ImpoundInfo } from '@/lib/types';
import { ago, countdown, displayName, useNow } from './model';
import { FavouriteToggle, SharedByBadge, StatusBadge } from './VehicleTiles';

export interface VehicleDetailProps {
  v: GarageVehicle;
  options: GarageOptions;
  /** grid: full identity header (the card is above); list: the row already shows it. */
  variant: 'grid' | 'list';
  /** Plate currently being spawned (any vehicle). */
  driving: string | null;
  recovering: boolean;
  onCollapse?: () => void;
  onDrive: () => void;
  onRecover: () => void;
  onTransfer: () => void;
  onSell: () => void;
  onShare: () => void;
  onRename: () => void;
  onTrack: () => void;
  onFavourite: () => void;
  onPay: (full: boolean) => void;
}

function InfoCell({ label, children, tone }: { label: string; children: ReactNode; tone?: 'teal' | 'amber' | 'red' }) {
  return (
    <div className={cx('nz-garage__cell', tone && `is-${tone}`)}>
      <span className="nz-garage__cell-label">{label}</span>
      <span className="nz-garage__cell-value">{children}</span>
    </div>
  );
}

export function FinanceBlock({
  finance,
  onPay,
  disabled,
}: {
  finance: Finance;
  onPay: (full: boolean) => void;
  disabled?: boolean;
}) {
  const total = finance.paymentsTotal;
  const done = total ? Math.max(0, total - finance.paymentsLeft) : 0;
  const nextPayment = Math.min(finance.payment, finance.balance);
  return (
    <div className={cx('nz-garage__block', finance.overdue && 'is-danger')}>
      <div className="nz-garage__block-head">
        <span className="nz-garage__block-title">
          <Icon name="receipt" size={13} strokeWidth={1.8} />
          {t('Finance')}
        </span>
        {finance.overdue ? (
          <Badge tone="red" icon="warning" size="sm">
            {t('Payment overdue')}
          </Badge>
        ) : (
          <Badge tone="neutral" size="sm">
            {t('{n} payment(s) left', { n: finance.paymentsLeft })}
          </Badge>
        )}
      </div>
      <div className="nz-garage__cells nz-garage__cells--3">
        <InfoCell label={t('Recurring payment')}>{money(finance.payment)}</InfoCell>
        <InfoCell label={t('Remaining balance')}>{money(finance.balance)}</InfoCell>
        <InfoCell label={t('Payments')}>
          {total ? (
            <>
              {done}
              <small>/{total}</small>
            </>
          ) : (
            t('{n} left', { n: finance.paymentsLeft })
          )}
        </InfoCell>
      </div>
      {total ? <Pips total={total} done={done} tone={finance.overdue ? 'red' : 'teal'} className="nz-garage__pips" /> : null}
      <div className="nz-garage__block-foot">
        <span className="nz-garage__block-note">
          <Icon name="clock" size={12} strokeWidth={1.8} />
          {finance.overdue ? (
            <span className="nz-garage__red">{t('A payment is overdue — the vehicle stays locked until you pay.')}</span>
          ) : (
            <span>
              {finance.intervalHours ? (
                <>
                  {t('Every')} <b>{hoursLabel(finance.intervalHours)}</b>
                  {finance.nextPaymentHours !== null && ' · '}
                </>
              ) : null}
              {finance.nextPaymentHours !== null && (
                <>
                  {t('Next payment in')} <b>{hoursLabel(finance.nextPaymentHours)}</b>
                </>
              )}
            </span>
          )}
        </span>
        <span className="nz-garage__block-actions">
          <Button size="sm" variant={finance.overdue ? 'red' : 'line'} icon="money" badge={money(nextPayment)} disabled={disabled} onClick={() => onPay(false)}>
            {t('Make payment')}
          </Button>
          <Button size="sm" variant="line" disabled={disabled} onClick={() => onPay(true)}>
            {t('Pay in full')}
          </Button>
        </span>
      </div>
    </div>
  );
}

/** Availability of an impounded vehicle (live). */
export function useAvailability(info: ImpoundInfo | null) {
  const waiting = !!info && info.retrievable && info.releaseAt > Math.floor(Date.now() / 1000);
  const now = useNow(waiting);
  if (!info) return null;
  if (!info.retrievable) return { state: 'release' as const, seconds: 0 };
  const seconds = info.releaseAt - now;
  if (seconds > 0) return { state: 'waiting' as const, seconds };
  return { state: 'now' as const, seconds: 0 };
}

export function AvailabilityBadge({ info, size = 'md' }: { info: ImpoundInfo; size?: 'sm' | 'md' }) {
  const a = useAvailability(info);
  if (!a) return null;
  if (a.state === 'release') {
    return (
      <Badge tone="red" icon="lock" size={size}>
        {t('Release required')}
      </Badge>
    );
  }
  if (a.state === 'waiting') {
    return (
      <Badge tone="amber" icon="clock" size={size} title={t('Available in {time}', { time: countdown(a.seconds) })}>
        {t('Available {date}', { date: dateTime(info.releaseAt) })}
      </Badge>
    );
  }
  return (
    <Badge tone="teal" icon="checkCircle" size={size}>
      {t('Available now')}
    </Badge>
  );
}

export function AvailabilityText({ info }: { info: ImpoundInfo }) {
  const a = useAvailability(info);
  if (!a) return null;
  if (a.state === 'release') return <span className="nz-garage__red">{t('Release required')}</span>;
  if (a.state === 'waiting') {
    return (
      <span className="nz-garage__avail">
        <span className="nz-garage__amber">{t('In {time}', { time: countdown(a.seconds) })}</span>
        <small>{dateTime(info.releaseAt)}</small>
      </span>
    );
  }
  return <span className="nz-garage__teal">{t('Available now')}</span>;
}

function ImpoundBlock({ info }: { info: ImpoundInfo }) {
  return (
    <div className="nz-garage__block is-danger">
      <div className="nz-garage__block-head">
        <span className="nz-garage__block-title">
          <Icon name="impound" size={13} strokeWidth={1.8} />
          {t('Impounded at {place}', { place: info.locationName })}
        </span>
        <AvailabilityBadge info={info} size="sm" />
      </div>
      <div className="nz-garage__cells nz-garage__cells--4">
        <InfoCell label={t('Impounded by')}>{info.byName || t('Unknown')}</InfoCell>
        <InfoCell label={t('Reason')}>
          <span className="nz-garage__clamp" title={info.reason}>
            {info.reason || t('No reason given')}
          </span>
        </InfoCell>
        <InfoCell label={t('Retrieval fee')}>{info.fee > 0 ? money(info.fee) : t('Free')}</InfoCell>
        <InfoCell label={t('Available')}>
          <AvailabilityText info={info} />
        </InfoCell>
      </div>
      <div className="nz-garage__block-foot">
        <span className="nz-garage__block-note">
          <Icon name="map" size={12} strokeWidth={1.8} />
          <span>{t('Pay the fee at {place} to get it back.', { place: info.locationName })}</span>
        </span>
      </div>
    </div>
  );
}

export function VehicleDetail({
  v,
  options,
  variant,
  driving,
  recovering,
  onCollapse,
  onDrive,
  onRecover,
  onTransfer,
  onSell,
  onShare,
  onRename,
  onTrack,
  onFavourite,
  onPay,
}: VehicleDetailProps) {
  const name = displayName(v);
  const isDriving = driving === v.plate;
  const busy = driving !== null || recovering;
  const canTransfer = v.isOwner && (options.garageTransfer || options.playerTransfer);
  const canSell = v.isOwner && options.sell;
  const canShare = v.isOwner && options.share;

  const menu: MenuItem[] = [];
  if (v.isOwner) menu.push({ label: t('Rename'), icon: 'edit', onSelect: onRename });
  menu.push({ label: t('Track vehicle'), icon: 'map', onSelect: onTrack });

  const reasonTone = v.state === 'impounded' || v.blocked || v.finance?.overdue ? 'red' : v.state === 'out' ? 'amber' : 'neutral';

  return (
    <div className="nz-garage__dv">
      <div className="nz-garage__dv-head">
        <div className="nz-garage__dv-title">
          {variant === 'grid' && (
            <div className="nz-garage__dv-name">
              <b title={name}>{name}</b>
              {v.nickname && <span title={v.label}>{v.label}</span>}
            </div>
          )}
          <div className="nz-garage__dv-meta">
            {variant === 'grid' && (
              <>
                <PlateTag plate={v.plate} />
                <span className="nz-garage__mileage">
                  <Icon name="gauge" size={12} strokeWidth={1.8} />
                  {distance(v.mileage)}
                </span>
              </>
            )}
            <span className="nz-garage__mileage" title={v.lastUsed ? dateTime(v.lastUsed) : undefined}>
              <Icon name="history" size={12} strokeWidth={1.8} />
              {t('Last used')} <b>{ago(v.lastUsed)}</b>
            </span>
            {!v.isOwner && !v.sharedBy && v.ownerName && (
              <span className="nz-garage__mileage">
                <Icon name="user" size={12} strokeWidth={1.8} />
                {t('Owner')} <b>{v.ownerName}</b>
              </span>
            )}
          </div>
        </div>
        <div className="nz-garage__dv-badges">
          {variant === 'grid' && <SharedByBadge v={v} />}
          {variant === 'grid' && <StatusBadge v={v} />}
          {v.here && v.state === 'garaged' && !v.blocked && (
            <Badge tone="teal" icon="parking">
              {t('Parked here')}
            </Badge>
          )}
          {onCollapse && <IconButton icon="close" label={t('Collapse')} size="sm" onClick={onCollapse} />}
        </div>
      </div>

      <div className="nz-garage__stats">
        <Stat label={t('Fuel')} icon="fuel" value={v.fuel} />
        <Stat
          label={t('Engine')}
          icon="engine"
          value={v.engine}
          extra={
            v.needsService ? (
              <Badge tone="amber" icon="wrench" size="sm">
                {t('Needs service')}
              </Badge>
            ) : undefined
          }
        />
        <Stat label={t('Body')} icon="shield" value={v.body} />
      </div>

      {v.finance && <FinanceBlock finance={v.finance} onPay={onPay} disabled={!v.isOwner || busy} />}
      {v.state === 'impounded' && v.impound && <ImpoundBlock info={v.impound} />}

      {(v.trailer || (v.isOwner && v.sharedWith > 0)) && (
        <div className="nz-garage__lines">
          {v.trailer && (
            <span className="nz-garage__line">
              <Icon name="trailer" size={13} strokeWidth={1.8} />
              {t('Stored with {trailer} attached', { trailer: v.trailer.label })}
            </span>
          )}
          {v.isOwner && v.sharedWith > 0 && (
            <span className="nz-garage__line">
              <Icon name="users" size={13} strokeWidth={1.8} />
              {t('Shared with {count} player(s)', { count: v.sharedWith })}
            </span>
          )}
        </div>
      )}

      {!v.canDrive && v.reason && (
        <div className={cx('nz-garage__reason', `is-${reasonTone}`)}>
          <Icon name={reasonTone === 'neutral' ? 'info' : 'warning'} size={14} strokeWidth={1.8} />
          <span>{v.reason}</span>
        </div>
      )}

      <div className="nz-garage__actions">
        <div className="nz-garage__actions-main">
          <Button
            variant="teal"
            icon="arrowRight"
            loading={isDriving}
            disabled={!v.canDrive || (busy && !isDriving)}
            title={!v.canDrive ? v.reason ?? t('This vehicle cannot be driven from here') : undefined}
            onClick={onDrive}
          >
            {isDriving ? t('Loading vehicle...') : t('Drive')}
          </Button>
          {v.canRecover && (
            <Button
              variant="white"
              icon="refresh"
              loading={recovering}
              disabled={busy && !recovering}
              badge={v.recoverFee > 0 ? money(v.recoverFee) : undefined}
              onClick={onRecover}
            >
              {t('Recover')}
            </Button>
          )}
          {canTransfer && (
            <Button icon="transfer" onClick={onTransfer} disabled={busy}>
              {t('Transfer')}
            </Button>
          )}
          {canSell && (
            <Button icon="tag" onClick={onSell} disabled={busy}>
              {t('Sell')}
            </Button>
          )}
          {canShare && (
            <Button icon="users" onClick={onShare} disabled={busy} badge={v.sharedWith > 0 ? v.sharedWith : undefined}>
              {t('Share')}
            </Button>
          )}
        </div>
        <div className="nz-garage__actions-side">
          <FavouriteToggle on={v.favourite} onToggle={onFavourite} className="nz-garage__fav--lg" />
          <Menu items={menu} label={t('More actions')} />
        </div>
      </div>
    </div>
  );
}
