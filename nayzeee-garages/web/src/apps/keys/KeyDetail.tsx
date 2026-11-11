/**
 * Detail pane of the selected key: vehicle name, plate and ownership chips, the fob art (the
 * pressed button follows the hold), the status trio (lock / engine / distance), the main
 * action (HoldButton: tap = lock, hold = engine, keep holding = windows) and the actions
 * Inspect, Track, Share and Drop (key items) / Give back (a key someone gave you) / Manage
 * access (the owner's virtual keys). More: waypoint, remote alarm, Ghost PIN. The last answer
 * of the server stays under the actions.
 */
import type { ReactNode, Ref } from 'react';
import { Icon, Menu, PlateTag, cx } from '@/components/ui';
import type { IconName, MenuItem } from '@/components/ui';
import { FobArt } from '@/components/fob/FobArt';
import { t } from '@/lib/i18n';
import type { KeyEntry, KeysOpenData } from '@/lib/types';
import { HoldButton } from './HoldButton';
import type { HoldHandle, HoldStage } from './HoldButton';
import { EngineGlyph, KeypadGlyph, KindGlyph, SignalGlyph } from './glyphs';
import { countdown, displayName, fobOf, groupLabel, kindInfo, meters, rangeOf, reasonLabel, remoteCapable, shareInfo } from './model';
import type { Unit } from './model';

export interface Answer {
  tone: 'teal' | 'amber' | 'red';
  title: string;
  text: string;
  at: number;
}

export type SideAction = 'drop' | 'leave' | 'access' | null;

export interface KeyDetailProps {
  k: KeyEntry;
  data: KeysOpenData;
  left: number | null;
  unit: Unit;
  busy: boolean;
  answer: Answer | null;
  stage: HoldStage;
  holdRef: Ref<HoldHandle>;
  alarmCooldown: number;
  onStage: (s: HoldStage) => void;
  onTap: () => void;
  onEngine: () => void;
  onWindows: () => void;
  onInspect: () => void;
  onTrack: () => void;
  onShare: () => void;
  onSide: (a: Exclude<SideAction, null>) => void;
  onWaypoint: () => void;
  onAlarm: () => void;
  onPin: () => void;
}

/** What the fourth action button does for this key. */
export function sideActionOf(k: KeyEntry, mode: KeysOpenData['mode']): SideAction {
  if ((k.kind === 'item' || k.kind === 'fob') && (k.slot != null || k.keyId)) return 'drop';
  if (mode === 'virtual' && k.isOwner && k.kind !== 'temp') return 'access';
  if (!k.isOwner && (k.kind === 'virtual' || k.kind === 'temp')) return 'leave';
  return null;
}

export function KeyDetail(p: KeyDetailProps) {
  const { k, data, left, unit } = p;
  const kind = kindInfo(k);
  const fob = fobOf(k);
  const seatElsewhere = !!data.seatPlate && data.seatPlate !== k.plate;
  const canTap = k.spawned && !k.towing && !seatElsewhere;
  const remote = remoteCapable(k);
  const ghost = k.immobiliser === 'ghost';
  const canRemote = canTap && remote;
  const reason = k.towing
    ? t('The vehicle is on the impound tow truck.')
    : !k.spawned
      ? t('The vehicle is not out. Take it out of a garage first.')
      : seatElsewhere
        ? t('Get out of your vehicle to use another key.')
        : !remote
          ? t('A plain key locks within {range}. Engine and windows need a fob.', { range: meters(rangeOf(k, data.ranges), unit) })
          : ghost
            ? t('The Ghost immobiliser blocks the remote start.')
            : null;
  const side = sideActionOf(k, data.mode);
  const share = shareInfo(k, data.mode, data.keyMode);
  const trackTip = !data.tracker
    ? t('The vehicle tracker is switched off')
    : !k.tracker
      ? t('No tracker fitted')
      : !k.trackerAccess
        ? t('This key has no tracker access')
        : undefined;
  // the fob's lock / unlock button lights up while the tap is armed
  const pressed = p.stage === 'tap' ? (k.locked === true ? 'unlock' : 'lock') : null;

  const more: MenuItem[] = [];
  if (k.trackable)
    more.push({ label: t('Set waypoint'), icon: 'map', onSelect: p.onWaypoint });
  if (k.trackable)
    more.push({
      label: k.alarm ? t('Silence the alarm') : t('Sound the alarm'),
      icon: 'warning',
      onSelect: p.onAlarm,
      disabled: !k.alarm && p.alarmCooldown > 0,
      hint: !k.alarm && p.alarmCooldown > 0 ? t('{s}s', { s: p.alarmCooldown }) : undefined,
    });
  if (k.isOwner && ghost) more.push({ label: t('Ghost PIN'), icon: 'lock', onSelect: p.onPin });

  return (
    <div className="nz-keys-detail">
      <header className="nz-keys-detail__head">
        <div className="nz-keys-detail__titles">
          {k.make && <span className="nz-keys-detail__make">{k.make}</span>}
          <h2 className="nz-keys-detail__name" title={displayName(k)}>
            {displayName(k)}
          </h2>
          <div className="nz-keys-detail__chips">
            <PlateTag plate={k.plate} size="sm" />
            <span className={cx('nz-keys-chip', `is-${kind.tone}`)}>
              <KindGlyph glyph={kind.glyph} size={11} strokeWidth={2} />
              {kind.label}
            </span>
            <span className="nz-keys-chip">{groupLabel(k.group)}</span>
            {k.immobiliser && k.immobiliser !== 'none' && (
              <span className={cx('nz-keys-chip', ghost && 'is-teal')} title={ghost ? t('Ghost immobiliser: PIN before the engine starts') : t('Immobiliser: no hotwiring')}>
                <KeypadGlyph size={11} strokeWidth={1.9} />
                {ghost ? t('Ghost') : t('Immobiliser')}
              </span>
            )}
          </div>
        </div>
        {more.length > 0 && <Menu items={more} align="right" label={t('More')} />}
      </header>

      <div className={cx('nz-keys-detail__stage', k.alarm && 'is-alarm')}>
        <span className="nz-keys-detail__halo" aria-hidden="true" />
        <FobArt design={fob.design} kind={fob.kind} brand={k.make || null} size={200} active={pressed} className="nz-keys-detail__art" />
        {k.kind === 'temp' && left !== null && (
          <span className={cx('nz-keys-detail__timer', left < 600 && 'is-low')}>
            <Icon name="clock" size={12} strokeWidth={1.9} />
            {t('{time} left', { time: countdown(left) })}
          </span>
        )}
        {k.reason && <span className="nz-keys-detail__origin">{reasonLabel(k.reason)}</span>}
      </div>

      <div className="nz-keys-detail__trio">
        <Fact
          icon={k.locked === false ? 'unlock' : 'lock'}
          label={t('Doors')}
          tone={!k.spawned ? 'grey' : k.locked === true ? 'teal' : k.locked === false ? 'amber' : 'grey'}
          value={!k.spawned ? '—' : k.locked === true ? t('Locked') : k.locked === false ? t('Unlocked') : t('Unknown')}
        />
        <Fact
          glyph={<EngineGlyph size={15} strokeWidth={1.7} />}
          label={t('Engine')}
          tone={k.engine === true ? 'teal' : 'grey'}
          value={!k.spawned ? '—' : k.engine === true ? t('Running') : k.engine === false ? t('Off') : t('Unknown')}
        />
        <Fact
          icon="pin"
          label={t('Distance')}
          tone={k.towing ? 'red' : !k.spawned ? 'grey' : 'white'}
          value={k.towing ? t('Towed') : !k.spawned ? t('Not out') : k.distance !== null ? meters(k.distance, unit) : t('Out')}
        />
      </div>

      <HoldButton
        ref={p.holdRef}
        locked={k.locked}
        engine={k.engine ?? null}
        canTap={canTap}
        canRemote={canRemote && !ghost}
        reason={reason}
        busy={p.busy}
        onTap={p.onTap}
        onEngine={p.onEngine}
        onWindows={p.onWindows}
        onStage={p.onStage}
      />

      <div className="nz-keys-detail__actions">
        <Action icon="eye" label={t('Inspect')} onClick={p.onInspect} />
        <Action
          glyph={<SignalGlyph size={15} strokeWidth={1.7} />}
          label={t('Track')}
          onClick={p.onTrack}
          disabled={!!trackTip}
          tip={trackTip}
        />
        <Action
          icon="userPlus"
          label={share.action}
          onClick={p.onShare}
          disabled={!k.canShare}
          tip={!k.canShare ? (k.kind === 'temp' ? t('You cannot lend a temporary key') : t('Only the owner can share this key')) : undefined}
        />
        {side === 'drop' ? (
          <Action icon="arrowRight" label={t('Drop')} tone="red" onClick={() => p.onSide('drop')} tip={t('Drop it on the ground: anyone can pick it up')} />
        ) : side === 'leave' ? (
          <Action icon="logout" label={t('Give back')} tone="red" onClick={() => p.onSide('leave')} tip={t('Give this key back: you lose access')} />
        ) : side === 'access' ? (
          <Action
            icon="users"
            label={t('Access')}
            onClick={() => p.onSide('access')}
            badge={k.holders ?? undefined}
            tip={t('Who has a key of this vehicle: revoke them')}
          />
        ) : (
          <Action icon="arrowRight" label={t('Drop')} disabled tip={t('This key is not an item: nothing to drop')} />
        )}
      </div>

      {p.answer && (
        <div className={cx('nz-keys-detail__answer', `is-${p.answer.tone}`)} role="status">
          <Icon name={p.answer.tone === 'teal' ? 'checkCircle' : p.answer.tone === 'amber' ? 'info' : 'warning'} size={14} strokeWidth={1.8} />
          <span>
            <b>{p.answer.title}</b> {p.answer.text}
          </span>
        </div>
      )}
    </div>
  );
}

function Fact({
  icon,
  glyph,
  label,
  value,
  tone,
}: {
  icon?: IconName;
  glyph?: ReactNode;
  label: string;
  value: string;
  tone: 'teal' | 'amber' | 'red' | 'grey' | 'white';
}) {
  return (
    <div className={cx('nz-keys-fact', `is-${tone}`)}>
      <span className="nz-keys-fact__icon">{glyph ?? (icon && <Icon name={icon} size={15} strokeWidth={1.7} />)}</span>
      <b className="nz-keys-fact__value">{value}</b>
      <small className="nz-keys-fact__label">{label}</small>
    </div>
  );
}

function Action({
  icon,
  glyph,
  label,
  onClick,
  disabled,
  tip,
  tone,
  badge,
}: {
  icon?: IconName;
  glyph?: ReactNode;
  label: string;
  onClick?: () => void;
  disabled?: boolean;
  tip?: string;
  tone?: 'red';
  badge?: number;
}) {
  return (
    <button
      type="button"
      className={cx('nz-keys-action', tone === 'red' && 'is-red')}
      onClick={onClick}
      disabled={disabled}
      title={tip}
    >
      {glyph ?? (icon && <Icon name={icon} size={15} strokeWidth={1.7} />)}
      <span>{label}</span>
      {badge !== undefined && badge > 0 && <i className="nz-keys-action__badge">{badge}</i>}
    </button>
  );
}
