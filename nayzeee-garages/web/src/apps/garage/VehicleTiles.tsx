/**
 * Garage vehicle card (grid) and row (list) contents + the small shared pieces:
 * status badge, favourite star, meta icons (service / finance / trailer / shared).
 */
import type { MouseEvent, ReactNode } from 'react';
import { Badge, Icon, PlateTag, Ring, Tooltip, VehicleImage, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import { distance } from '@/lib/format';
import type { GarageVehicle } from '@/lib/types';
import { displayName } from './model';

/** Where the vehicle is / why it is not here. Null when parked here and fine. */
export function StatusBadge({ v, size = 'md' }: { v: GarageVehicle; size?: 'sm' | 'md' }) {
  if (v.blocked) {
    return (
      <Badge tone="red" icon="ban" size={size}>
        {t('Blocked')}
      </Badge>
    );
  }
  if (v.state === 'impounded') {
    return (
      <Badge tone="red" icon="impound" size={size}>
        {t('Impounded')}
      </Badge>
    );
  }
  if (v.state === 'out') {
    return (
      <Badge tone="amber" icon="route" size={size} title={v.canRecover ? t('Lost — can be recovered') : undefined}>
        {v.canRecover ? t('Out · Lost') : t('Out')}
      </Badge>
    );
  }
  if (!v.here) {
    return (
      <Badge tone="neutral" icon="pin" size={size} title={v.garageName ?? undefined}>
        {v.garageName ?? t('Another garage')}
      </Badge>
    );
  }
  return null;
}

export function SharedByBadge({ v, size = 'md' }: { v: GarageVehicle; size?: 'sm' | 'md' }) {
  if (!v.sharedBy) return null;
  return (
    <Badge tone="blue" icon="users" size={size} title={t('Shared with you by {name}', { name: v.sharedBy })}>
      {t('Shared by {name}', { name: v.sharedBy })}
    </Badge>
  );
}

export function FavouriteToggle({
  on,
  onToggle,
  className,
}: {
  on: boolean;
  onToggle: () => void;
  className?: string;
}) {
  const label = on ? t('Remove from favourites') : t('Add to favourites');
  return (
    <Tooltip content={label}>
      <button
        type="button"
        className={cx('nz-garage__fav', on && 'is-on', className)}
        aria-label={label}
        aria-pressed={on}
        onClick={(e: MouseEvent) => {
          e.stopPropagation();
          onToggle();
        }}
        onKeyDown={(e) => e.stopPropagation()}
      >
        <Icon name={on ? 'starFilled' : 'star'} size={14} strokeWidth={1.8} />
      </button>
    </Tooltip>
  );
}

function MetaIcon({ icon, tone, tip, children }: { icon: 'wrench' | 'receipt' | 'trailer' | 'users'; tone?: string; tip: string; children?: ReactNode }) {
  return (
    <Tooltip content={tip}>
      <span className={cx('nz-garage__metaicon', tone && `is-${tone}`)} aria-label={tip} role="img">
        <Icon name={icon} size={13} strokeWidth={1.8} />
        {children}
      </span>
    </Tooltip>
  );
}

/** Small state icons shown at the end of the meta line. */
export function MetaIcons({ v }: { v: GarageVehicle }) {
  return (
    <span className="nz-garage__metaicons">
      {v.trailer && <MetaIcon icon="trailer" tip={t('With {trailer}', { trailer: v.trailer.label })} />}
      {v.finance && (
        <MetaIcon
          icon="receipt"
          tone={v.finance.overdue ? 'red' : undefined}
          tip={v.finance.overdue ? t('Finance payment overdue') : t('Financed')}
        />
      )}
      {v.isOwner && v.sharedWith > 0 && (
        <MetaIcon icon="users" tone="teal" tip={t('Shared with {count} player(s)', { count: v.sharedWith })}>
          <b>{v.sharedWith}</b>
        </MetaIcon>
      )}
      {v.needsService && <MetaIcon icon="wrench" tone="amber" tip={t('Needs service')} />}
    </span>
  );
}

/** Fuel / engine / body as three small rings (list rows). */
export function ConditionRings({ v }: { v: { fuel: number; engine: number; body: number } }) {
  const items = [
    { key: 'fuel', icon: 'fuel' as const, value: v.fuel, label: t('Fuel') },
    { key: 'engine', icon: 'engine' as const, value: v.engine, label: t('Engine') },
    { key: 'body', icon: 'shield' as const, value: v.body, label: t('Body') },
  ];
  return (
    <span className="nz-garage__rings">
      {items.map((it) => (
        <Tooltip key={it.key} content={`${it.label} ${Math.round(it.value)}%`}>
          <Ring value={it.value} size={26} stroke={2.5} tone="auto">
            <Icon name={it.icon} size={11} strokeWidth={1.9} />
          </Ring>
        </Tooltip>
      ))}
    </span>
  );
}

function Mileage({ km }: { km: number }) {
  return (
    <span className="nz-garage__mileage">
      <Icon name="gauge" size={12} strokeWidth={1.8} />
      {distance(km)}
    </span>
  );
}

export function GarageCard({ v, onFavourite }: { v: GarageVehicle; onFavourite: () => void }) {
  const name = displayName(v);
  const status = <StatusBadge v={v} />;
  return (
    <>
      <div className="nz-garage__media">
        <VehicleImage image={v.image} vehicleType={v.vehicleType} alt={v.label} className="nz-garage__img" />
        <div className="nz-garage__overlay">
          <span className="nz-garage__backing">{status}</span>
          <span className="nz-garage__backing">
            <SharedByBadge v={v} />
          </span>
        </div>
        <FavouriteToggle on={v.favourite} onToggle={onFavourite} className="nz-garage__fav--float" />
      </div>
      <div className="nz-garage__cardbody">
        <b className="nz-garage__name" title={name}>
          {name}
        </b>
        {v.nickname && (
          <span className="nz-garage__sub" title={v.label}>
            {v.label}
          </span>
        )}
        <div className="nz-garage__meta">
          <PlateTag plate={v.plate} size="sm" />
          <Mileage km={v.mileage} />
          <MetaIcons v={v} />
        </div>
      </div>
    </>
  );
}

export function GarageRow({ v, open, onFavourite }: { v: GarageVehicle; open: boolean; onFavourite: () => void }) {
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
          {v.nickname && (
            <span className="nz-garage__sub" title={v.label}>
              {v.label}
            </span>
          )}
          {v.trailer && <span className="nz-garage__plus">+ {v.trailer.label}</span>}
        </span>
        <span className="nz-garage__meta">
          <PlateTag plate={v.plate} size="sm" />
          <Mileage km={v.mileage} />
          <MetaIcons v={v} />
        </span>
      </div>
      <div className="nz-garage__rowside">
        <SharedByBadge v={v} />
        <StatusBadge v={v} />
        <ConditionRings v={v} />
        <FavouriteToggle on={v.favourite} onToggle={onFavourite} />
        <Icon name="chevronDown" size={15} strokeWidth={1.8} className={cx('nz-garage__chev', open && 'is-open')} />
      </div>
    </>
  );
}
