/**
 * Track vehicle modal (docs/V2_CHANGES.md G.10), from the key ring and the garage showcase.
 * keys:track { plate } is asked when it opens and every POLL_MS while it stays open (the
 * server answers with the tracker's position only for trackable vehicles; Lua adds the street,
 * its own live position when the vehicle is in scope and the player's position). Shows the
 * live map, street + distance + last seen, and the facts: plate, lock status, engine, tracking,
 * alarm, immobiliser. Set waypoint = keys:locate (waypoint + a blip that follows it).
 * `onFallback` (garage): a waypoint the garage can give when the tracker cannot (no tracker,
 * keys handled by another script).
 */
import { useEffect, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import { Button, Icon, Modal, PlateTag, Skeleton, cx } from '@/components/ui';
import type { IconName } from '@/components/ui';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import { toast } from '@/lib/store';
import type { KeyTrackData } from '@/lib/types';
import { EngineGlyph, KeypadGlyph, SignalGlyph } from './glyphs';
import { ago, displayName, immobiliserLabel, meters } from './model';
import type { Unit } from './model';
import { TrackMap } from './TrackMap';

const POLL_MS = 2500;

export interface TrackModalProps {
  /** plate to track; null = closed */
  plate: string | null;
  /** name shown while the first answer loads */
  title?: string | null;
  unit: Unit;
  onClose: () => void;
  /** garage: set a waypoint its own way when the tracker cannot */
  onFallback?: () => void;
}

export function TrackModal({ plate, title, unit, onClose, onFallback }: TrackModalProps) {
  const open = !!plate;
  const [data, setData] = useState<KeyTrackData | null>(null);
  const [error, setError] = useState<string | null>(null);
  // when the last position arrived (Date.now), and the last one known (kept when the signal goes)
  const [seenAt, setSeenAt] = useState<number | null>(null);
  const [lastPos, setLastPos] = useState<{ x: number; y: number; heading: number | null } | null>(null);
  const [now, setNow] = useState(() => Date.now());
  const [waypointBusy, setWaypointBusy] = useState(false);
  const alive = useRef(0);

  useEffect(() => {
    if (!plate) return;
    const session = ++alive.current;
    setData(null);
    setError(null);
    setSeenAt(null);
    setLastPos(null);
    let timer: number | undefined;
    const poll = async () => {
      const res = await request('keys:track', { plate }, { toastError: false });
      if (alive.current !== session) return;
      if (res.ok && res.data) {
        const d = res.data;
        setData(d);
        setError(null);
        if (d.coords) {
          setSeenAt(Date.now());
          setLastPos({ x: d.coords.x, y: d.coords.y, heading: d.heading ?? null });
        }
      } else if (!res.ok) {
        setError(res.error);
      }
      timer = window.setTimeout(() => void poll(), POLL_MS);
    };
    void poll();
    const clock = window.setInterval(() => setNow(Date.now()), 1000);
    return () => {
      alive.current++;
      window.clearTimeout(timer);
      window.clearInterval(clock);
    };
  }, [plate]);

  const waypoint = async () => {
    if (!plate || waypointBusy) return;
    if (!data?.trackable && onFallback) {
      onFallback();
      return;
    }
    setWaypointBusy(true);
    const res = await request('keys:locate', { plate }, { toastError: true });
    setWaypointBusy(false);
    if (res.ok) toast({ type: 'success', message: t('Waypoint set to {vehicle}.', { vehicle: displayName(data ?? { label: title ?? plate }) }) });
  };

  const name = data ? displayName(data) : (title ?? plate ?? '');
  const pos = data?.coords ? { x: data.coords.x, y: data.coords.y, heading: data.heading } : lastPos;
  const stale = !data?.coords && !!lastPos;
  const since = seenAt !== null ? Math.max(0, Math.floor((now - seenAt) / 1000)) : null;

  const veil = !data
    ? error
      ? { icon: 'warning' as const, title: t('Cannot track this vehicle'), text: error }
      : null
    : !data.coords && !lastPos
      ? veilOf(data)
      : null;

  const signal: { text: string; tone: 'live' | 'teal' | 'amber' | 'grey' } = !data
    ? { text: t('Connecting'), tone: 'grey' }
    : data.coords
      ? data.live
        ? { text: t('Live'), tone: 'live' }
        : { text: t('Tracker'), tone: 'teal' }
      : lastPos
        ? { text: t('Signal lost'), tone: 'amber' }
        : { text: t('No signal'), tone: 'grey' };

  const canWaypoint = !!data?.trackable || !!onFallback;

  return (
    <Modal
      open={open}
      onClose={onClose}
      width={780}
      icon="map"
      title={
        <span className="nz-keys-track__title">
          {t('Track vehicle')} <em>{name}</em>
        </span>
      }
      className="nz-keys-modal nz-keys-track"
      footer={
        <>
          <span className="nz-keys-track__foot-note">
            {data?.trackable
              ? t('The waypoint follows the vehicle for a while.')
              : onFallback
                ? t('No live signal: the waypoint goes to its last known place.')
                : ''}
          </span>
          <Button variant="ghost" onClick={onClose}>
            {t('Close')}
          </Button>
          <Button variant="white" icon="route" loading={waypointBusy} disabled={!canWaypoint} onClick={() => void waypoint()}>
            {t('Set waypoint')}
          </Button>
        </>
      }
    >
      <div className="nz-keys-track__mapbox">
        <TrackMap target={pos} heading={pos?.heading ?? null} me={data?.me ?? null} live={!!data?.live && !!data.coords} veil={veil} stale={stale} />
        <div className="nz-keys-track__where">
          <Icon name="pin" size={14} strokeWidth={1.9} />
          <span>
            <b>{data ? (data.street ?? (data.coords ? t('Unknown street') : t('Position unknown'))) : <Skeleton width={120} height={11} />}</b>
            <small>
              {data?.area && `${data.area} · `}
              {data?.distance != null ? meters(data.distance, unit) : '—'}
              {' · '}
              {since !== null ? (since < 4 ? t('just now') : t('seen {ago}', { ago: ago(since) })) : t('never seen')}
            </small>
          </span>
        </div>
        <span className={cx('nz-keys-track__signal', `is-${signal.tone}`)}>
          <i />
          {signal.text}
        </span>
      </div>

      <div className="nz-keys-track__facts">
        <TrackFact icon="tag" label={t('Plate')}>
          {plate ? <PlateTag plate={plate} size="sm" /> : '—'}
        </TrackFact>
        <TrackFact icon={data?.locked === false ? 'unlock' : 'lock'} label={t('Lock status')} tone={data?.locked === false ? 'amber' : data?.locked ? 'teal' : undefined}>
          {!data ? '—' : !data.spawned ? t('Not out') : data.locked === true ? t('Locked') : data.locked === false ? t('Unlocked') : t('Unknown')}
        </TrackFact>
        <TrackFact glyph={<EngineGlyph size={16} strokeWidth={1.7} />} label={t('Engine')} tone={data?.engine ? 'teal' : undefined}>
          {!data || !data.spawned ? '—' : data.engine === true ? t('Running') : data.engine === false ? t('Engine off') : t('Unknown')}
        </TrackFact>
        <TrackFact glyph={<SignalGlyph size={16} strokeWidth={1.7} />} label={t('Tracking')} tone={data?.trackable ? 'teal' : undefined}>
          {!data
            ? '—'
            : data.trackable
              ? data.live
                ? t('Live GPS')
                : t('Tracker signal')
              : !data.tracker
                ? t('No tracker')
                : !data.trackerAccess
                  ? t('No access')
                  : t('Offline')}
        </TrackFact>
        <TrackFact icon="warning" label={t('Alarm')} tone={data?.alarm ? 'red' : undefined}>
          {!data ? '—' : data.alarm ? t('Sounding') : t('Quiet')}
        </TrackFact>
        <TrackFact glyph={<KeypadGlyph size={16} strokeWidth={1.7} />} label={t('Immobiliser')} tone={data?.immobiliser === 'ghost' ? 'teal' : undefined}>
          {data ? immobiliserLabel(data.immobiliser) : '—'}
        </TrackFact>
      </div>
    </Modal>
  );
}

function veilOf(d: KeyTrackData): { icon: 'warning' | 'info' | 'ban'; title: string; text?: string } {
  switch (d.reason) {
    case 'notracker':
      return { icon: 'info', title: t('No tracker fitted'), text: t('Vehicles with a high-end security profile carry a tracker.') };
    case 'noaccess':
      return { icon: 'ban', title: t('No tracker access'), text: t('This key does not unlock the tracker of this vehicle.') };
    case 'towing':
      return { icon: 'warning', title: t('On the tow truck'), text: t('The vehicle is on its way to the impound.') };
    case 'disabled':
      return { icon: 'info', title: t('Tracker switched off'), text: t('The vehicle tracker is not available on this server.') };
    default:
      return { icon: 'info', title: t('Not out'), text: t('The vehicle is parked or stored: there is nothing to track.') };
  }
}

function TrackFact({
  icon,
  glyph,
  label,
  tone,
  children,
}: {
  icon?: IconName;
  glyph?: ReactNode;
  label: string;
  tone?: 'teal' | 'amber' | 'red';
  children: ReactNode;
}) {
  return (
    <div className={cx('nz-keys-track__fact', tone && `is-${tone}`)}>
      <span className="nz-keys-track__fact-icon">{glyph ?? (icon && <Icon name={icon} size={16} strokeWidth={1.7} />)}</span>
      <span className="nz-keys-track__fact-text">
        <small>{label}</small>
        <b>{children}</b>
      </span>
    </div>
  );
}
