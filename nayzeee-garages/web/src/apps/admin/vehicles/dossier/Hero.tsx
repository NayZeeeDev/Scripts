/**
 * Dossier hero band: back, turntable stage, identity (make · class, name, nickname, badges,
 * plate, model, top speed), owner card and the record actions.
 */
import { Avatar, Button, Icon, IconButton, Tooltip, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import { useSettings } from '@/lib/store';
import { dateTime, distance } from '@/lib/format';
import type { AdminOpenData, AdminVehicleDetail } from '@/lib/types';
import { StatusBadges } from '../common';
import { ownerTypeLabel } from '../util';
import { ago, groupLabel, shapeIcon, shapeLabel, shapeOf, speedLabel } from './data';
import { Plate, Stage } from './parts';

interface Props {
  detail: AdminVehicleDetail;
  data: AdminOpenData;
  busy: 'block' | 'delete' | 'finance' | 'release' | null;
  onBack: () => void;
  onOwner: () => void;
  onBlock: () => void;
  onImpound: () => void;
  onRelease: () => void;
  onDelete: () => void;
}

export function Hero({ detail, data, busy, onBack, onOwner, onBlock, onImpound, onRelease, onDelete }: Props) {
  const unit = useSettings().distanceUnit;
  const v = detail.vehicle;
  const impounded = v.state === 'impounded' || !!detail.impound;
  const group = groupLabel(detail, data);
  const shape = shapeOf(v);
  const eyebrow = [v.make, v.classLabel].filter(Boolean).join(' · ');
  const name = v.make && v.label.startsWith(`${v.make} `) ? v.label.slice(v.make.length + 1) : v.label || v.model;
  const ownerKind =
    v.ownerType === 'player' ? t('Owner') : v.ownerType === 'job' ? t('Job vehicle') : t('Gang vehicle');

  return (
    <section className="nz-dos-hero" aria-label={t('Vehicle')}>
      <IconButton icon="arrowLeft" label={t('Back to vehicles (Esc)')} variant="line" onClick={onBack} className="nz-dos-hero__back" />

      <Stage
        image={v.image}
        vehicleType={v.vehicleType}
        alt={v.label}
        stamp={impounded ? t('IMPOUNDED') : v.blocked ? t('BLOCKED') : null}
        topLeft={
          <Tooltip content={shapeLabel(shape)}>
            <span className="nz-dos-hero__type">
              <Icon name={shapeIcon(shape)} size={13} strokeWidth={1.7} />
            </span>
          </Tooltip>
        }
        className="nz-dos-hero__stage"
      />

      <div className="nz-dos-hero__id">
        <div className="nz-dos-hero__top">
          {eyebrow && <span className="nz-dos-hero__eyebrow">{eyebrow}</span>}
          <StatusBadges row={{ state: v.state, financed: !!detail.finance, blocked: v.blocked }} />
        </div>
        <div className="nz-dos-hero__name">
          <h2 className="nz-aveh-ellipsis" title={v.label}>
            {name}
          </h2>
          {v.nickname && <span className="nz-dos-hero__nick">“{v.nickname}”</span>}
        </div>
        <div className="nz-dos-hero__reg">
          <Plate plate={v.plate} />
          <div className="nz-dos-hero__specs">
            <span className="nz-aveh-mono" title={t('Spawn code')}>
              {v.model}
            </span>
            {v.stats && (
              <>
                <i />
                <span>
                  <Icon name="gauge" size={12} strokeWidth={1.7} />
                  {speedLabel(v.stats.topSpeed, unit)}
                </span>
                <i />
                <span>
                  <Icon name="users" size={12} strokeWidth={1.7} />
                  {v.stats.seats === 1 ? t('1 seat') : t('{n} seats', { n: v.stats.seats })}
                </span>
              </>
            )}
          </div>
        </div>
        <div className="nz-dos-hero__vitals">
          <span className="is-where" title={t('Location')}>
            <Icon name={detail.impound ? 'impound' : v.state === 'out' ? 'route' : 'garage'} size={13} strokeWidth={1.7} />
            <span className="nz-aveh-ellipsis">
              {detail.impound ? detail.impound.locationName : v.state === 'out' ? t('Out in the world') : v.garageName ?? t('No garage')}
            </span>
          </span>
          <span title={t('Mileage')}>
            <Icon name="route" size={13} strokeWidth={1.7} />
            {distance(v.mileage)}
          </span>
          <Tooltip content={detail.lastUsed ? dateTime(detail.lastUsed) : t('Never taken out')}>
            <span>
              <Icon name="clock" size={13} strokeWidth={1.7} />
              {detail.lastUsed ? t('Driven {when}', { when: ago(detail.lastUsed) }) : t('Never driven')}
            </span>
          </Tooltip>
        </div>
      </div>

      <div className="nz-dos-hero__side">
        <button type="button" className="nz-dos-owner" onClick={onOwner}>
          <span className="nz-dos-owner__kind">{ownerKind}</span>
          <span className="nz-dos-owner__main">
            <Avatar name={v.ownerName || '?'} size={34} />
            <span className="nz-dos-owner__text">
              <b className="nz-aveh-ellipsis">{v.ownerName || t('No owner')}</b>
              <span className="nz-aveh-mono nz-aveh-ellipsis">
                {v.ownerType === 'player' ? v.owner ?? '—' : `${ownerTypeLabel(v.ownerType)} · ${group ?? '—'}`}
              </span>
            </span>
          </span>
          <span className="nz-dos-owner__cta">
            {t('Change owner')}
            <Icon name="chevronRight" size={13} strokeWidth={1.8} />
          </span>
        </button>
        <div className={cx('nz-dos-hero__actions', detail.impound && 'has-split')}>
          <Tooltip content={v.blocked ? t('Players can take this vehicle out again.') : t('Blocked vehicles cannot be taken out of any garage.')} side="bottom">
            <Button size="sm" variant="line" icon={v.blocked ? 'unlock' : 'ban'} onClick={onBlock} loading={busy === 'block'} full>
              {v.blocked ? t('Unblock') : t('Block')}
            </Button>
          </Tooltip>
          {detail.impound ? (
            <span className="nz-dos-hero__split">
              <Button size="sm" variant="line" icon="unlock" onClick={onRelease} loading={busy === 'release'}>
                {t('Release')}
              </Button>
              <IconButton icon="edit" size="sm" variant="line" label={t('Edit impound')} onClick={onImpound} tooltipSide="bottom" />
            </span>
          ) : (
            <Tooltip content={detail.impounds.length ? t('Send this vehicle to an impound.') : t('Create an impound location first.')} side="bottom">
              <Button size="sm" variant="line" icon="impound" onClick={onImpound} disabled={!detail.impounds.length} full>
                {t('Impound')}
              </Button>
            </Tooltip>
          )}
          <Button size="sm" variant="red" icon="trash" onClick={onDelete} full>
            {t('Delete')}
          </Button>
        </div>
      </div>
    </section>
  );
}
