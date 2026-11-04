/**
 * Key ring showcase (right pane): the selected key's vehicle on the turntable stage, a status
 * strip (key · vehicle · doors · lock range), the Remote block (range gauge + the server's last
 * answer), the Tracker block (live distance, alarm), About this key (how it was obtained, time
 * left, sharing rule), Key holders for owners in virtual mode (revoke) and the action dock
 * (Lock / Unlock, Locate, Alarm, Share).
 */
import { useEffect, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import { Avatar, Button, Icon, Ring, Skeleton, Tooltip, VehicleImage, cx } from '@/components/ui';
import type { IconName } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { KeyEntry, KeyHolder, KeyTracking, KeysOpenData } from '@/lib/types';
import { FobGlyph, KindGlyph, SignalGlyph, SirenGlyph } from './glyphs';
import { ago, countdown, howObtained, kindInfo, meters, rangeOf, rangeState, reasonLabel } from './model';

export interface Answer {
  tone: 'teal' | 'amber' | 'red';
  /** short uppercase heading ("Out of range", "Done"...) */
  title: string;
  text: string;
  at: number;
}

export type HolderState = KeyHolder[] | 'loading' | 'error' | undefined;

export interface KeyShowProps {
  k: KeyEntry;
  data: KeysOpenData;
  left: number | null;
  unit: 'mi' | 'km';
  busy: { lock: boolean; locate: boolean; alarm: boolean };
  answer: Answer | null;
  tracking: KeyTracking | null;
  locating: boolean;
  alarmCooldown: number;
  holders: HolderState;
  /** Date.now() when the holder list arrived (temporary holders count down from it) */
  holdersAt: number;
  revoking: string | null;
  now: number;
  onLock: () => void;
  onLocate: () => void;
  onStopLocate: () => void;
  onAlarm: () => void;
  onShare: () => void;
  onRevoke: (h: KeyHolder) => void;
  onReloadHolders: () => void;
}

/* ── small pieces ─────────────────────────────────────────────────────── */

function Block({
  icon,
  glyph,
  title,
  aside,
  wide = false,
  tone,
  className,
  children,
}: {
  icon?: IconName;
  glyph?: ReactNode;
  title: string;
  aside?: ReactNode;
  wide?: boolean;
  tone?: 'red' | 'amber';
  className?: string;
  children: ReactNode;
}) {
  return (
    <section className={cx('nz-keys__blk', wide && 'is-wide', tone && `is-${tone}`, className)}>
      <header className="nz-keys__blk-head">
        <h4>
          {glyph ?? (icon && <Icon name={icon} size={13} strokeWidth={1.8} />)}
          {title}
        </h4>
        {aside && <div className="nz-keys__blk-aside">{aside}</div>}
      </header>
      <div className="nz-keys__blk-body">{children}</div>
    </section>
  );
}

function NoData({
  icon,
  glyph,
  title,
  text,
  tone,
}: {
  icon?: IconName;
  glyph?: ReactNode;
  title: string;
  text: string;
  tone?: 'red' | 'amber';
}) {
  return (
    <div className={cx('nz-keys__nodata', tone && `is-${tone}`)}>
      {glyph ?? (icon && <Icon name={icon} size={18} strokeWidth={1.5} />)}
      <b>{title}</b>
      <span>{text}</span>
    </div>
  );
}

function Cell({
  label,
  icon,
  glyph,
  value,
  sub,
  tone,
}: {
  label: string;
  icon?: IconName;
  glyph?: ReactNode;
  value: ReactNode;
  sub?: ReactNode;
  tone?: 'teal' | 'amber' | 'red' | 'grey';
}) {
  return (
    <div className={cx('nz-keys__cell', tone && `is-${tone}`)}>
      <span className="nz-keys__cell-label">
        {glyph ?? (icon && <Icon name={icon} size={11} strokeWidth={1.9} />)}
        {label}
      </span>
      <span className="nz-keys__cell-value">{value}</span>
      {sub && <span className="nz-keys__cell-sub">{sub}</span>}
    </div>
  );
}

function Fact({ icon, glyph, label, children }: { icon?: IconName; glyph?: ReactNode; label: string; children: ReactNode }) {
  return (
    <div className="nz-keys__fact">
      <span className="nz-keys__fact-label">
        {glyph ?? (icon && <Icon name={icon} size={12} strokeWidth={1.8} />)}
        {label}
      </span>
      <span className="nz-keys__fact-value">{children}</span>
    </div>
  );
}

/* ── stage ────────────────────────────────────────────────────────────── */

function Stage({ k, tracking }: { k: KeyEntry; tracking: KeyTracking | null }) {
  const kind = kindInfo(k);
  const name = k.label || t('Unknown vehicle');
  const nick = (k.nickname ?? '').trim();
  const ghost = !k.spawned || k.towing;
  let note: ReactNode = null;
  if (k.towing) {
    note = (
      <>
        <Icon name="impound" size={13} strokeWidth={1.8} />
        {t('On the tow truck to the impound')}
      </>
    );
  } else if (!k.spawned) {
    note = (
      <>
        <Icon name="parking" size={13} strokeWidth={1.8} />
        {t('Not out right now')}
      </>
    );
  }
  return (
    <div className={cx('nz-keys__stage', ghost && 'is-ghost')}>
      <span className="nz-keys__stage-light" aria-hidden="true" />
      <span className="nz-keys__stage-floor" aria-hidden="true" />
      <span className="nz-keys__stage-horizon" aria-hidden="true" />
      <span className="nz-keys__stage-ring" aria-hidden="true" />
      <div key={k.plate} className="nz-keys__stage-car">
        <span className="nz-keys__stage-shadow" aria-hidden="true" />
        <VehicleImage image={k.image} vehicleType={k.vehicleType} alt={name} className="nz-keys__stage-img" />
      </div>
      {note && <div className="nz-keys__stage-note">{note}</div>}
      {k.alarm && (
        <div className="nz-keys__stage-alarm">
          <SirenGlyph size={13} strokeWidth={1.9} />
          {t('Alarm sounding')}
        </div>
      )}
      <div className="nz-keys__stage-top">
        <div className="nz-keys__stage-tl">
          <span className="nz-keys__tag">
            <Icon name="shield" size={12} strokeWidth={1.9} />
            {k.profileLabel}
          </span>
          {k.tracker && (
            <span
              className={cx(
                'nz-keys__tag',
                !k.trackerAccess && 'is-off',
                k.trackerAccess && tracking && !tracking.lost && !tracking.stopped && 'is-live',
              )}
              title={k.trackerAccess ? undefined : t('This key has no tracker access')}
            >
              <SignalGlyph size={12} strokeWidth={1.9} />
              {t('Tracker')}
            </span>
          )}
        </div>
        <div className="nz-keys__stage-tr">
          <span className={cx('nz-keys__bigkind', `is-${kind.tone}`)}>
            <KindGlyph glyph={kind.glyph} size={13} strokeWidth={1.9} />
            {kind.label}
          </span>
        </div>
      </div>
      <div key={`f-${k.plate}`} className="nz-keys__stage-foot">
        <div className="nz-keys__stage-title">
          {k.make && <span className="nz-keys__st-make">{k.make}</span>}
          <span className="nz-keys__st-line">
            <b className="nz-keys__st-name" title={name}>
              {name}
            </b>
            {nick && <span className="nz-keys__st-nick">“{nick}”</span>}
          </span>
        </div>
        <span className="nz-keys__plate" title={k.plate}>
          <small>{t('San Andreas')}</small>
          <b>{k.plate}</b>
        </span>
      </div>
    </div>
  );
}

/* ── range gauge ──────────────────────────────────────────────────────── */

function RangeGauge({ k, data, unit }: { k: KeyEntry; data: KeysOpenData; unit: 'mi' | 'km' }) {
  const range = rangeOf(k, data.ranges);
  const state = rangeState(k, data.ranges, data.seatPlate);
  const inside = !!data.seatPlate && data.seatPlate === k.plate;
  const dist = k.distance;
  const max = Math.max(range * 2, dist !== null ? Math.min(dist * 1.15, range * 6) : 0);
  const zone = (range / max) * 100;
  const marker = dist !== null ? Math.min(100, (dist / max) * 100) : null;
  return (
    <div className={cx('nz-keys__gauge', `is-${state}`)}>
      <div className="nz-keys__gauge-head">
        <span className="nz-keys__gauge-mode">
          {k.remote ? <FobGlyph size={13} strokeWidth={1.8} /> : <Icon name="key" size={13} strokeWidth={1.8} />}
          {k.remote ? t('Remote locking') : t('Key in hand')}
        </span>
        <span className="nz-keys__gauge-range">{t('up to {range}', { range: meters(range, unit) })}</span>
      </div>
      <div className="nz-keys__gauge-track" aria-hidden="true">
        <span className="nz-keys__gauge-zone" style={{ width: `${zone}%` }} />
        <span className="nz-keys__gauge-tick" style={{ left: `${zone}%` }} />
        {marker !== null && state !== 'none' && <span className="nz-keys__gauge-marker" style={{ left: `${marker}%` }} />}
      </div>
      <div className="nz-keys__gauge-foot">
        {inside ? (
          <span className="is-teal">
            <Icon name="checkCircle" size={12} strokeWidth={1.9} />
            {t('You are inside: it always works')}
          </span>
        ) : state === 'in' ? (
          <span className="is-teal">
            <Icon name="checkCircle" size={12} strokeWidth={1.9} />
            {t('{dist} away · in range', { dist: meters(dist, unit) })}
          </span>
        ) : state === 'out' ? (
          <span className="is-amber">
            <Icon name="warning" size={12} strokeWidth={1.9} />
            {t('{dist} away · get within {range}', { dist: meters(dist, unit), range: meters(range, unit) })}
          </span>
        ) : state === 'unknown' ? (
          <span>
            <Icon name="eyeOff" size={12} strokeWidth={1.9} />
            {t('Out of sight: the server measures the range when you press it')}
          </span>
        ) : (
          <span>
            <Icon name="info" size={12} strokeWidth={1.9} />
            {k.towing ? t('Towed vehicles stay locked') : t('Locks work once the vehicle is out')}
          </span>
        )}
      </div>
    </div>
  );
}

/* ── showcase ─────────────────────────────────────────────────────────── */

export function KeyShow(p: KeyShowProps) {
  const { k, data, left, unit, busy, answer, tracking, locating } = p;
  const kind = kindInfo(k);
  const state = rangeState(k, data.ranges, data.seatPlate);
  const seatOther = !!data.seatPlate && data.seatPlate !== k.plate;
  const virtual = data.mode === 'virtual';

  /* strip */
  let keyValue: ReactNode = kind.label;
  let keySub: ReactNode = null;
  let keyTone: 'teal' | 'amber' | 'red' | 'grey' | undefined;
  if (k.kind === 'temp') {
    keyValue = t('Temporary key');
    keySub = left !== null ? t('{time} left', { time: countdown(left) }) : t('Until the server restarts');
    keyTone = left !== null && left < 600 ? 'red' : 'amber';
  } else if (k.kind === 'item' || k.kind === 'fob') {
    keyValue = k.kind === 'fob' ? t('Fob item') : t('Key item');
    keySub = t('In your pockets');
  } else if (k.kind === 'virtual') {
    keyValue = t('Virtual key');
    keySub = t('Given to you');
    keyTone = 'teal';
  } else {
    keyValue = t('Virtual key');
    keySub = k.isOwner ? t('You own it') : t('Shared access');
    keyTone = 'teal';
  }

  let vehValue: ReactNode;
  let vehSub: ReactNode;
  let vehTone: 'teal' | 'amber' | 'red' | 'grey' | undefined;
  if (k.towing) {
    vehValue = t('Being towed');
    vehSub = t('To the impound');
    vehTone = 'red';
  } else if (k.spawned) {
    vehValue = t('Out');
    vehSub = k.distance !== null ? t('{dist} from you', { dist: meters(k.distance, unit) }) : t('Out of sight');
    vehTone = 'teal';
  } else {
    vehValue = t('Not out');
    vehSub = t('Stored or elsewhere');
    vehTone = 'grey';
  }

  const lockValue = !k.spawned || k.locked === null ? '—' : k.locked ? t('Locked') : t('Unlocked');
  const lockTone = !k.spawned || k.locked === null ? 'grey' : k.locked ? 'teal' : 'amber';
  const range = rangeOf(k, data.ranges);

  /* dock */
  let lockReason: string | null = null;
  if (k.towing) lockReason = t('Towed vehicles stay locked until they are released');
  else if (!k.spawned) lockReason = t('Not out: take it out of a garage first');
  else if (seatOther) lockReason = t('You sit in another vehicle: get out to lock this one');
  const canLock = lockReason === null;
  const willLock = k.locked !== true;

  const trackerReason = !data.tracker
    ? t('The vehicle tracker is offline')
    : !k.tracker
      ? t('No tracker fitted')
      : !k.trackerAccess
        ? t('This key has no tracker access')
        : k.towing
          ? t('This vehicle is being towed')
          : !k.spawned
            ? t('The vehicle is not out')
            : null;
  const alarmLabel = k.alarm ? t('Silence') : p.alarmCooldown > 0 ? t('Alarm {s}s', { s: p.alarmCooldown }) : t('Alarm');

  const shareReason = k.canShare
    ? null
    : k.kind === 'temp'
      ? t('Temporary keys cannot be lent')
      : virtual
        ? t('Only the owner can give keys')
        : t('Only key items can be handed over');

  /* sections below the fold: named in a bar under them (like the garage showroom) */
  const blocksRef = useRef<HTMLDivElement>(null);
  const [more, setMore] = useState<{ dir: 'down' | 'up'; names: string[] } | null>(null);
  useEffect(() => {
    const el = blocksRef.current;
    if (!el) return;
    const check = () => {
      if (el.scrollHeight - el.clientHeight <= 8) {
        setMore(null);
        return;
      }
      if (el.scrollTop + el.clientHeight >= el.scrollHeight - 8) {
        setMore({ dir: 'up', names: [] });
        return;
      }
      const bottom = el.getBoundingClientRect().bottom;
      const names: string[] = [];
      el.querySelectorAll<HTMLElement>(':scope > .nz-keys__blk').forEach((b) => {
        const r = b.getBoundingClientRect();
        if (r.top + 48 > bottom) names.push(b.querySelector('h4')?.textContent ?? '');
      });
      setMore({ dir: 'down', names: names.filter(Boolean) });
    };
    check();
    el.addEventListener('scroll', check, { passive: true });
    const ro = typeof ResizeObserver !== 'undefined' ? new ResizeObserver(check) : null;
    ro?.observe(el);
    el.querySelectorAll(':scope > .nz-keys__blk').forEach((b) => ro?.observe(b));
    return () => {
      el.removeEventListener('scroll', check);
      ro?.disconnect();
    };
  }, [k.plate, p.holders, answer]);

  /* holders */
  const showHolders = virtual && k.isOwner;
  const holders = p.holders;
  const holderList = Array.isArray(holders) ? holders : [];

  return (
    <div className="nz-keys__show">
      <Stage k={k} tracking={tracking} />

      <div className="nz-keys__strip">
        <Cell
          label={t('Key')}
          glyph={<KindGlyph glyph={kind.glyph} size={11} strokeWidth={2} />}
          value={keyValue}
          sub={keySub}
          tone={keyTone}
        />
        <Cell label={t('Vehicle')} icon="car" value={vehValue} sub={vehSub} tone={vehTone} />
        <Cell
          label={t('Doors')}
          icon={k.locked === false ? 'unlock' : 'lock'}
          value={lockValue}
          sub={k.spawned && k.locked !== null ? (k.locked ? t('Nobody gets in') : t('Anyone can get in')) : t('Unknown')}
          tone={lockTone}
        />
        <Cell
          label={t('Lock range')}
          glyph={k.remote ? <FobGlyph size={11} strokeWidth={2} /> : <Icon name="key" size={11} strokeWidth={1.9} />}
          value={meters(range, unit)}
          sub={
            state === 'in'
              ? t('In range')
              : state === 'out'
                ? t('Out of range')
                : state === 'unknown'
                  ? t('Server checks it')
                  : k.remote
                    ? t('Remote fob')
                    : t('Key in hand')
          }
          tone={state === 'in' ? 'teal' : state === 'out' ? 'amber' : undefined}
        />
      </div>

      <div ref={blocksRef} className="nz-keys__blocks">
        <Block
          icon={k.locked === false ? 'unlock' : 'lock'}
          title={t('Remote')}
          aside={answer ? <span className="nz-keys__blk-note">{ago((p.now - answer.at) / 1000)}</span> : undefined}
        >
          <RangeGauge k={k} data={data} unit={unit} />
          {answer && (
            <div key={answer.at} className={cx('nz-keys__answer', `is-${answer.tone}`)} role="status">
              <Icon name={answer.tone === 'teal' ? 'checkCircle' : 'warning'} size={14} strokeWidth={1.8} />
              <span>
                <b>{answer.title}</b>
                {answer.text}
              </span>
            </div>
          )}
        </Block>

        <Block
          glyph={<SignalGlyph size={13} strokeWidth={1.8} />}
          title={t('Tracker')}
          aside={
            k.trackable && locating ? (
              <span className={cx('nz-keys__live', tracking?.live && 'is-on')}>{tracking?.live ? t('Live') : t('GPS')}</span>
            ) : undefined
          }
        >
          {trackerReason ? (
            <NoData
              glyph={<SignalGlyph size={18} strokeWidth={1.5} />}
              title={
                !k.tracker
                  ? t('No tracker fitted')
                  : !data.tracker
                    ? t('Tracker offline')
                    : !k.trackerAccess
                      ? t('No tracker access')
                      : k.towing
                        ? t('Signal lost')
                        : t('No signal')
              }
              text={
                !k.tracker
                  ? t('Vehicles with a high-end security profile carry a tracker.')
                  : !data.tracker
                    ? t('The server has switched the vehicle tracker off.')
                    : !k.trackerAccess
                      ? t('{how}: this key opens the vehicle, it does not reach the tracker. Only the owner and the keys they give do.', {
                          how: howObtained(k),
                        })
                      : k.towing
                        ? t('The vehicle is on the tow truck to the impound.')
                        : t('The vehicle is stored, or not in this part of the world.')
              }
              tone={k.tracker && data.tracker && (k.towing || !k.trackerAccess) ? (k.trackerAccess ? 'red' : 'amber') : undefined}
            />
          ) : (
            <div className="nz-keys__track">
              <div className="nz-keys__track-read">
                <span className="nz-keys__track-num">{k.distance !== null ? meters(k.distance, unit) : '—'}</span>
                <span className="nz-keys__track-cap">{t('from you')}</span>
              </div>
              <div className="nz-keys__track-lines">
                <span className={cx(locating ? 'is-teal' : undefined)}>
                  <Icon name={locating ? 'route' : 'pin'} size={12} strokeWidth={1.9} />
                  {locating
                    ? tracking?.lost
                      ? t('Signal lost')
                      : t('Waypoint set · the blip follows it')
                    : t('Press Locate for a waypoint and a live blip')}
                </span>
                <span className={cx(k.alarm ? 'is-red' : p.alarmCooldown > 0 ? 'is-amber' : undefined)}>
                  <SirenGlyph size={12} strokeWidth={1.9} />
                  {k.alarm
                    ? t('Alarm sounding')
                    : p.alarmCooldown > 0
                      ? t('Alarm ready again in {s}s', { s: p.alarmCooldown })
                      : t('Remote alarm ready')}
                </span>
              </div>
            </div>
          )}
        </Block>

        {showHolders && (
          <Block
            icon="users"
            title={t('Key holders')}
            wide
            aside={
              <>
                {holderList.length > 0 && <span className="nz-keys__count">{holderList.length}</span>}
                <button type="button" className="nz-keys__mini" onClick={p.onReloadHolders} title={t('Refresh')} aria-label={t('Refresh')}>
                  <Icon name="refresh" size={12} strokeWidth={1.9} />
                </button>
              </>
            }
          >
            {holders === 'loading' || holders === undefined ? (
              <div className="nz-keys__holders">
                {[0, 1].map((i) => (
                  <div key={i} className="nz-keys__holder is-skel">
                    <Skeleton width={30} height={30} radius={8} />
                    <span className="nz-keys__holder-text">
                      <Skeleton width={120} height={11} />
                      <Skeleton width={180} height={9} />
                    </span>
                  </div>
                ))}
              </div>
            ) : holders === 'error' ? (
              <NoData icon="warning" title={t('Could not load the key holders')} text={t('Try again in a moment.')} tone="amber" />
            ) : holderList.length === 0 ? (
              <NoData
                icon="users"
                title={t('Only you hold a key')}
                text={t('Give a key to a player next to you with Give key. You can take it back here.')}
              />
            ) : (
              <div className="nz-keys__holders">
                {holderList.map((h) => {
                  const left = h.expiresIn !== null ? countdown(h.expiresIn - (p.now - p.holdersAt) / 1000) : null;
                  return (
                    <div
                      key={h.id}
                      className={cx('nz-keys__holder', h.masked && 'is-masked')}
                      title={h.masked ? t('Someone holds a key from a crime. Revoke it to lock them out.') : undefined}
                    >
                      {h.masked ? (
                        <span className="nz-keys__holder-mask" aria-hidden="true">
                          <Icon name="eyeOff" size={14} strokeWidth={1.8} />
                        </span>
                      ) : (
                        <Avatar name={h.name} size={30} />
                      )}
                      <span className="nz-keys__holder-text">
                        <b>{h.name}</b>
                        <small>
                          {h.kind === 'temp' ? (
                            <span className={h.masked ? 'is-red' : 'is-amber'}>
                              {reasonLabel(h.reason)}
                              {left !== null && ` · ${t('{time} left', { time: left })}`}
                            </span>
                          ) : (
                            <>
                              <span>{t('Virtual key')}</span>
                              {' · '}
                              {t('given {ago}', { ago: ago(h.agoSeconds) })}
                            </>
                          )}
                        </small>
                      </span>
                      <Button
                        size="sm"
                        variant="line"
                        icon="ban"
                        className="nz-keys__revoke"
                        loading={p.revoking === h.id}
                        onClick={() => p.onRevoke(h)}
                      >
                        {t('Revoke')}
                      </Button>
                    </div>
                  );
                })}
              </div>
            )}
          </Block>
        )}
        <Block icon="info" title={t('About this key')} wide>
          <div className="nz-keys__facts">
            <Fact glyph={<KindGlyph glyph={kind.glyph} size={12} strokeWidth={1.9} />} label={t('Key')}>
              {k.kind === 'fob'
                ? t('Fob item · physical')
                : k.kind === 'item'
                  ? t('Key item · physical')
                  : k.kind === 'temp'
                    ? t('Temporary key')
                    : t('Virtual key')}
            </Fact>
            <Fact icon="shield" label={t('Security')}>
              {k.remote
                ? t('{profile} · remote locking within {range}', { profile: k.profileLabel, range: meters(data.ranges.fob, unit) })
                : t('{profile} · key within {range}', { profile: k.profileLabel, range: meters(data.ranges.key, unit) })}
            </Fact>
            <Fact icon="user" label={t('Access')}>
              {k.kind === 'temp' || (k.reason && !k.isOwner)
                ? howObtained(k)
                : k.isOwner
                  ? t('Owner')
                  : k.group === 'shared'
                    ? k.kind === 'virtual'
                      ? t('Key given to you by the owner')
                      : t('Garage share or fleet vehicle')
                    : t('Key item of a vehicle you do not own')}
            </Fact>
            {k.kind === 'temp' && (
              <Fact icon="clock" label={t('Expires')}>
                <span className={cx('nz-keys__expiry', left !== null && left < 600 && 'is-red')}>
                  {left !== null ? (
                    <>
                      <Ring value={Math.min(left, 3600)} max={3600} size={18} stroke={2.5} tone={left < 600 ? 'red' : 'amber'} />
                      {t('in {time}', { time: countdown(left) })}
                    </>
                  ) : (
                    t('When the server restarts')
                  )}
                </span>
              </Fact>
            )}
            <Fact icon="userPlus" label={t('Sharing')}>
              {k.canShare
                ? virtual
                  ? t('Give keys to nearby players · revoke any time')
                  : t('Hand this key item to a player next to you')
                : shareReason}
            </Fact>
          </div>
          {!virtual && k.isOwner && (
            <div className="nz-keys__hintline">
              <Icon name="info" size={13} strokeWidth={1.8} />
              <span>{t('Key items cannot be called back. A locksmith can change the locks: every other copy stops working.')}</span>
            </div>
          )}
        </Block>
      </div>
      {more && (
        <button
          type="button"
          className={cx('nz-keys__more', more.dir === 'up' && 'is-end')}
          onClick={() => {
            const el = blocksRef.current;
            if (!el) return;
            el.scrollTo({ top: more.dir === 'up' ? 0 : el.scrollTop + el.clientHeight * 0.75, behavior: 'smooth' });
          }}
        >
          <span>{more.dir === 'up' ? t('Back to top') : more.names.join(' · ') || t('More below')}</span>
          <Icon name={more.dir === 'up' ? 'chevronUp' : 'chevronDown'} size={12} strokeWidth={2} />
        </button>
      )}

      <footer className="nz-keys__dock">
        <div className="nz-keys__dock-main">
          <Button
            variant="teal"
            size="lg"
            icon={willLock ? 'lock' : 'unlock'}
            className="nz-keys__go"
            disabled={!canLock}
            loading={busy.lock}
            onClick={p.onLock}
          >
            <span className="nz-keys__primary">
              {willLock ? t('Lock') : t('Unlock')}
              <kbd className="nz-kbd nz-keys__primary-key">{t('Enter')}</kbd>
            </span>
          </Button>
          {lockReason ? (
            <span className="nz-keys__dock-reason">
              <Icon name="info" size={14} strokeWidth={1.8} />
              <span>{lockReason}</span>
            </span>
          ) : (
            <span className="nz-keys__dock-reason">
              <Icon
                name={state === 'out' ? 'warning' : 'info'}
                size={14}
                strokeWidth={1.8}
                className={state === 'out' ? 'is-amber' : undefined}
              />
              <span>
                {state === 'out'
                  ? t('Probably too far: get within {range}', { range: meters(range, unit) })
                  : t('Range rules apply: the server checks the distance')}
              </span>
            </span>
          )}
        </div>
        <div className="nz-keys__tools">
          <Tooltip content={trackerReason ?? (locating ? t('Stop following') : t('Waypoint + live blip'))} side="top">
            <button
              type="button"
              className={cx('nz-keys__tool', locating && 'is-on')}
              disabled={!!trackerReason || busy.locate}
              onClick={locating ? p.onStopLocate : p.onLocate}
            >
              {busy.locate ? <span className="nz-keys__spin" /> : <Icon name={locating ? 'close' : 'pin'} size={14} strokeWidth={1.8} />}
              {locating ? t('Stop') : t('Locate')}
            </button>
          </Tooltip>
          <Tooltip content={trackerReason ?? (k.alarm ? t('Silence the alarm') : t('Sound the alarm for a moment'))} side="top">
            <button
              type="button"
              className={cx('nz-keys__tool', k.alarm && 'is-alarm')}
              disabled={!!trackerReason || busy.alarm || (!k.alarm && p.alarmCooldown > 0)}
              onClick={p.onAlarm}
            >
              {busy.alarm ? <span className="nz-keys__spin" /> : <SirenGlyph size={14} strokeWidth={1.8} />}
              {alarmLabel}
            </button>
          </Tooltip>
          <Tooltip content={shareReason ?? (virtual ? t('Give a key to a player next to you') : t('Hand the key item over'))} side="top">
            <button type="button" className="nz-keys__tool" disabled={!k.canShare} onClick={p.onShare}>
              <Icon name="userPlus" size={14} strokeWidth={1.8} />
              {virtual ? t('Give key') : t('Hand over')}
            </button>
          </Tooltip>
        </div>
      </footer>
    </div>
  );
}
