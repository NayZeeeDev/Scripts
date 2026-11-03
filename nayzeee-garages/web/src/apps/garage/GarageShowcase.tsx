/**
 * Garage showcase (right pane): the selected vehicle on the stage, the status strip, the
 * detail sections (impound, finance, condition + damage glyph, performance, upgrades,
 * details) and the action dock. Also the spawner showcase and the empty turntable.
 */
import { useCallback, useEffect, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import { Badge, Button, Icon, IconButton, Kbd, Tooltip, cx } from '@/components/ui';
import type { IconName } from '@/components/ui';
import { t } from '@/lib/i18n';
import { dateTime, distance, money } from '@/lib/format';
import type { GarageOptions, GarageSummary, GarageVehicle, SpawnerVehicleView } from '@/lib/types';
import { ago, modelName, normDamage, platePreview, primaryKind, vehicleIcon, vehicleStatus } from './model';
import { ClassTag, Plate, Stage, StageTitle } from './showroom/Stage';
import { glyphShape } from './showroom/DamageGlyph';
import {
  Block,
  Callout,
  ConditionBlock,
  Fact,
  FinanceBlock,
  ImpoundBlock,
  PerformanceBlock,
  StripCell,
  UpgradesBlock,
} from './showroom/blocks';

/* ── shared layout ───────────────────────────────────────────────────── */

export function ShowcaseFrame({
  stage,
  strip,
  children,
  dock,
  id,
}: {
  stage: ReactNode;
  strip?: ReactNode;
  children?: ReactNode;
  dock?: ReactNode;
  /** Re-keys the scroll area so it starts at the top for each vehicle. */
  id: string;
}) {
  return (
    <div className="nz-garage__show">
      {stage}
      {strip && <div className="nz-garage__strip">{strip}</div>}
      <Sections key={id}>{children}</Sections>
      {dock && <div className="nz-garage__dock">{dock}</div>}
    </div>
  );
}

/**
 * The scrolling detail sections. When blocks sit below the fold, a small pill names them
 * ("Upgrades · Details") and scrolls down on click; the bottom fade only shows then.
 */
function Sections({ children }: { children?: ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  const [below, setBelow] = useState<string[]>([]);

  const measure = useCallback(() => {
    const el = ref.current;
    if (!el) return;
    const more = el.scrollHeight > el.clientHeight + 8 && el.scrollTop + el.clientHeight < el.scrollHeight - 8;
    if (!more) {
      setBelow((prev) => (prev.length ? [] : prev));
      return;
    }
    const fold = el.getBoundingClientRect().bottom - 24;
    const names: string[] = [];
    el.querySelectorAll<HTMLElement>(':scope > .nz-garage__blk').forEach((blk) => {
      // A block counts as hidden when less than its heading is in view.
      if (blk.getBoundingClientRect().top + 30 > fold) {
        const h = blk.querySelector('h4')?.textContent?.trim();
        if (h && !names.includes(h)) names.push(h);
      }
    });
    if (!names.length) names.push(t('More'));
    setBelow((prev) => (prev.join('|') === names.join('|') ? prev : names));
  }, []);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    // Re-measure when the pane or a block changes size, and when blocks come or go.
    const ro = typeof ResizeObserver !== 'undefined' ? new ResizeObserver(measure) : null;
    const observeAll = () => {
      if (ro) {
        ro.disconnect();
        ro.observe(el);
        Array.from(el.children).forEach((c) => ro.observe(c));
      }
      measure();
    };
    observeAll();
    const mo = typeof MutationObserver !== 'undefined' ? new MutationObserver(observeAll) : null;
    mo?.observe(el, { childList: true });
    el.addEventListener('scroll', measure, { passive: true });
    return () => {
      ro?.disconnect();
      mo?.disconnect();
      el.removeEventListener('scroll', measure);
    };
  }, [measure]);

  const more = below.length > 0;
  return (
    <div className="nz-garage__secwrap">
      <div ref={ref} className={cx('nz-garage__sections', more && 'is-more')}>
        {children}
      </div>
      {more && (
        <button
          type="button"
          className="nz-garage__more"
          onClick={() => ref.current?.scrollTo({ top: ref.current.scrollHeight, behavior: 'smooth' })}
        >
          <span>{below.slice(0, 3).join(' · ')}</span>
          <Icon name="chevronDown" size={12} strokeWidth={2.2} />
        </button>
      )}
    </div>
  );
}

/** Secondary dock action: icon + label, grouped in an inset toolbar. */
export function Tool({
  icon,
  label,
  onClick,
  disabled,
  badge,
  tip,
}: {
  icon: IconName;
  label: string;
  onClick: () => void;
  disabled?: boolean;
  badge?: ReactNode;
  tip?: string;
}) {
  const btn = (
    <button type="button" className="nz-garage__tool" onClick={onClick} disabled={disabled} aria-label={tip ?? label}>
      <Icon name={icon} size={14} strokeWidth={1.8} />
      <span>{label}</span>
      {badge !== undefined && badge !== null && <b>{badge}</b>}
    </button>
  );
  return tip ? <Tooltip content={tip}>{btn}</Tooltip> : btn;
}

/** "Drive out ⏎": the primary label with its Enter keycap. */
export function PrimaryLabel({ children, keycap = true }: { children: ReactNode; keycap?: boolean }) {
  return (
    <span className="nz-garage__primary">
      {children}
      {keycap && (
        <Kbd size="sm" className="nz-garage__primary-key">
          Enter
        </Kbd>
      )}
    </span>
  );
}

/* ── owned vehicle ───────────────────────────────────────────────────── */

export interface VehicleShowcaseProps {
  v: GarageVehicle;
  garage: GarageSummary;
  options: GarageOptions;
  /** Plate currently spawning (any vehicle). */
  driving: string | null;
  recovering: boolean;
  tracking: boolean;
  onDrive: () => void;
  onRecover: () => void;
  onTrack: () => void;
  onRename: () => void;
  onTransfer: () => void;
  onShare: () => void;
  onSell: () => void;
  onFavourite: () => void;
  onPay: (full: boolean) => void;
}

function locationCell(v: GarageVehicle, garage: GarageSummary) {
  const st = vehicleStatus(v);
  switch (st.key) {
    case 'blocked':
      return { value: v.garageName ?? t('Unknown'), sub: t('Blocked by staff'), tone: 'grey' as const };
    case 'impounded':
      return { value: v.impound?.locationName ?? v.garageName ?? t('Impound'), sub: t('Impounded'), tone: 'red' as const };
    case 'out':
      return { value: t('Out in the city'), sub: t('Not in a garage'), tone: 'amber' as const };
    case 'lost':
      return { value: t('Out in the city'), sub: t('Position unknown'), tone: 'amber' as const };
    case 'elsewhere':
      return { value: v.garageName ?? t('Another garage'), sub: t('Another garage'), tone: undefined };
    default:
      return { value: garage.name, sub: t('Parked here'), tone: 'teal' as const };
  }
}

function sharingCell(v: GarageVehicle, garage: GarageSummary): { label: string; value: string; sub: string; icon: IconName } {
  if (v.sharedBy) return { label: t('Sharing'), value: t('Shared by {name}', { name: v.sharedBy }), sub: t('You can drive it'), icon: 'users' };
  if (!v.isOwner) {
    const sub = garage.kind === 'job' ? t('Job vehicle') : garage.isPrivate ? t('Garage member') : t('You have a key');
    return { label: t('Owner'), value: v.ownerName || t('Unknown'), sub, icon: garage.kind === 'job' ? 'briefcase' : 'user' };
  }
  if (v.sharedWith > 0) {
    return {
      label: t('Sharing'),
      value: v.sharedWith === 1 ? t('Shared with 1') : t('Shared with {n}', { n: v.sharedWith }),
      sub: v.sharedWith === 1 ? t('player has a key') : t('players have a key'),
      icon: 'users',
    };
  }
  return { label: t('Sharing'), value: t('Private'), sub: t('Only you'), icon: 'lock' };
}

function ghostNote(v: GarageVehicle): string | null {
  if (v.state === 'out') return t('Out in the city');
  if (v.state === 'impounded') return t('At {place}', { place: v.impound?.locationName ?? t('the impound') });
  if (!v.here) return t('Parked at {garage}', { garage: v.garageName ?? t('another garage') });
  return null;
}

export function VehicleShowcase(props: VehicleShowcaseProps) {
  const { v, garage } = props;
  const damage = normDamage(v.damage);
  const loc = locationCell(v, garage);
  const share = sharingCell(v, garage);
  // A vehicle that can be driven from here is never drawn as a ghost (retrieveMode 'anywhere').
  const note = v.canDrive ? null : ghostNote(v);
  const name = modelName(v);
  const isDriving = props.driving === v.plate;
  const busy = props.driving !== null || props.recovering;

  return (
    <ShowcaseFrame
      id={v.plate}
      stage={
        <Stage
          id={v.plate}
          image={v.image}
          vehicleType={v.vehicleType}
          alt={v.label}
          ghost={!!note}
          note={
            note ? (
              <>
                <Icon name={v.state === 'impounded' ? 'impound' : v.state === 'out' ? 'route' : 'pin'} size={12} strokeWidth={1.9} />
                {note}
              </>
            ) : undefined
          }
          topLeft={
            <>
              <ClassTag icon={<Icon name={vehicleIcon(v)} size={13} strokeWidth={1.8} />} label={v.classLabel || t('Other')} />
              {v.blocked && (
                <Badge tone="red" icon="ban" size="sm">
                  {t('Blocked')}
                </Badge>
              )}
            </>
          }
          topRight={
            <>
              {v.sharedBy && (
                <Badge tone="blue" icon="users" size="sm">
                  {t('Shared by {name}', { name: v.sharedBy })}
                </Badge>
              )}
              <IconButton
                icon={v.favourite ? 'starFilled' : 'star'}
                label={v.favourite ? t('Remove from favourites') : t('Add to favourites')}
                variant="line"
                size="sm"
                active={v.favourite}
                className={cx('nz-garage__stage-fav', v.favourite && 'is-on')}
                onClick={props.onFavourite}
              />
            </>
          }
          title={<StageTitle make={v.make} name={name} nickname={v.nickname} />}
          plate={<Plate plate={v.plate} />}
        />
      }
      strip={
        <>
          <StripCell icon="pin" label={t('Location')} value={loc.value} sub={loc.sub} tone={loc.tone} />
          <StripCell icon="gauge" label={t('Mileage')} value={distance(v.mileage)} sub={t('On the clock')} />
          <StripCell icon="history" label={t('Last driven')} value={ago(v.lastUsed)} sub={v.lastUsed ? dateTime(v.lastUsed) : t('Not yet')} />
          <StripCell icon={share.icon} label={share.label} value={share.value} sub={share.sub} />
        </>
      }
      dock={<GarageDock {...props} isDriving={isDriving} busy={busy} />}
    >
      {v.state === 'impounded' && v.impound && <ImpoundBlock info={v.impound} />}
      {v.finance && (
        <FinanceBlock
          finance={v.finance}
          onPay={props.onPay}
          disabled={!v.isOwner || busy}
          // The dock already explains an overdue lock when paying is its primary action.
          lockNote={primaryKind(v) !== 'pay'}
        />
      )}
      <ConditionBlock
        engine={v.engine}
        body={v.body}
        fuel={v.fuel}
        damage={damage}
        shape={glyphShape(v.vehicleType, v.classId, v.model)}
        needsService={v.needsService}
      />
      {v.stats && <PerformanceBlock stats={v.stats} />}
      <UpgradesBlock mods={v.mods} />
      <Block title={t('Details')} icon="info" wide={!v.stats}>
        <div className={cx('nz-garage__facts', !v.stats && 'is-cols')}>
          <Fact label={t('Model')} mono>
            {v.model}
          </Fact>
          <Fact label={t('Make')}>{v.make || '—'}</Fact>
          <Fact label={t('Owner')}>{v.isOwner ? t('You') : v.ownerName || t('Unknown')}</Fact>
          <Fact label={t('Plate')} mono>
            {v.plate}
          </Fact>
        </div>
        {v.trailer && (
          <Callout tone="teal" icon="trailer" className="nz-garage__blk-callout">
            {t('Trailer stored with it:')} <b>{v.trailer.label}</b>
          </Callout>
        )}
      </Block>
    </ShowcaseFrame>
  );
}

/* ── dock ────────────────────────────────────────────────────────────── */

function GarageDock({
  v,
  options,
  recovering,
  tracking,
  isDriving,
  busy,
  onDrive,
  onRecover,
  onTrack,
  onRename,
  onTransfer,
  onShare,
  onSell,
  onPay,
}: VehicleShowcaseProps & { isDriving: boolean; busy: boolean }) {
  const parked = v.state === 'garaged';
  const canTransfer = v.isOwner && parked && (options.garageTransfer || options.playerTransfer);
  const canSell = v.isOwner && parked && options.sell;
  const canShare = v.isOwner && options.share;
  // What the server refuses anyway: say so on the button instead of after a filled-in modal.
  const sellLock = v.blocked ? t('Blocked by staff') : v.finance ? t('Pay off the finance first') : null;
  // A financed vehicle can still move garages, only giving it to a player is refused (modal tab).
  const transferLock = v.blocked
    ? t('Blocked by staff')
    : v.finance && !options.garageTransfer
      ? t('Pay off the finance first')
      : null;
  const kind = primaryKind(v);

  let primary: ReactNode;
  let reason: { tone: 'neutral' | 'amber' | 'red'; icon: IconName; text: ReactNode } | null = null;
  let waypointPrimary = false;

  if (kind === 'drive') {
    primary = (
      <Button variant="teal" size="lg" icon="arrowRight" loading={isDriving} disabled={busy && !isDriving} onClick={onDrive} className="nz-garage__go">
        <PrimaryLabel keycap={!isDriving}>{isDriving ? t('Loading vehicle...') : t('Drive out')}</PrimaryLabel>
      </Button>
    );
  } else if (kind === 'recover') {
    primary = (
      <Button variant="white" size="lg" icon="refresh" loading={recovering} disabled={busy && !recovering} onClick={onRecover} className="nz-garage__go">
        <PrimaryLabel>{v.recoverFee > 0 ? t('Recover · {fee}', { fee: money(v.recoverFee) }) : t('Recover')}</PrimaryLabel>
      </Button>
    );
    reason = { tone: 'amber', icon: 'route', text: v.reason ?? t('Its last position is unknown. Recover it to bring it back here.') };
  } else if (kind === 'pay' && v.finance) {
    primary = (
      <Button variant="red" size="lg" icon="money" disabled={!v.isOwner || busy} onClick={() => onPay(false)} className="nz-garage__go">
        <PrimaryLabel keycap={v.isOwner}>{t('Pay {amount}', { amount: money(Math.min(v.finance.payment, v.finance.balance)) })}</PrimaryLabel>
      </Button>
    );
    reason = {
      tone: 'red',
      icon: 'lock',
      text: v.isOwner
        ? t('A finance payment is overdue. The vehicle stays locked until it is paid.')
        : t('A finance payment is overdue. Only the owner can pay it.'),
    };
  } else if (kind === 'waypoint') {
    waypointPrimary = true;
    primary = (
      <Button variant="white" size="lg" icon="map" loading={tracking} onClick={onTrack} className="nz-garage__go">
        <PrimaryLabel keycap={!tracking}>{t('Set waypoint')}</PrimaryLabel>
      </Button>
    );
    if (v.state === 'impounded' && v.impound) {
      reason = {
        tone: 'red',
        icon: 'impound',
        text:
          v.impound.fee > 0
            ? t('Pay {fee} at {place} to get it back.', { fee: money(v.impound.fee), place: v.impound.locationName })
            : t('Collect it at {place}.', { place: v.impound.locationName }),
      };
    } else {
      reason = { tone: v.state === 'out' ? 'amber' : 'neutral', icon: v.state === 'out' ? 'route' : 'pin', text: v.reason ?? t('It is not parked here.') };
    }
  } else {
    primary = (
      <Button variant="teal" size="lg" icon="arrowRight" disabled className="nz-garage__go">
        {t('Drive out')}
      </Button>
    );
    reason = { tone: v.blocked ? 'red' : 'neutral', icon: v.blocked ? 'ban' : 'info', text: v.reason ?? t('This vehicle cannot be driven from here.') };
  }

  return (
    <>
      <div className="nz-garage__dock-main">
        {primary}
        {reason && (
          <span className={cx('nz-garage__dock-reason', `is-${reason.tone}`)}>
            <Icon name={reason.icon} size={13} strokeWidth={1.9} />
            <span>{reason.text}</span>
          </span>
        )}
      </div>
      <div className="nz-garage__tools" role="toolbar" aria-label={t('Vehicle actions')}>
        {v.isOwner && <Tool icon="edit" label={t('Rename')} onClick={onRename} disabled={busy} />}
        {canTransfer && (
          <Tool icon="transfer" label={t('Transfer')} onClick={onTransfer} disabled={busy || !!transferLock} tip={transferLock ?? undefined} />
        )}
        {canShare && <Tool icon="userPlus" label={t('Share')} onClick={onShare} disabled={busy} badge={v.sharedWith > 0 ? v.sharedWith : undefined} />}
        {canSell && <Tool icon="tag" label={t('Sell')} onClick={onSell} disabled={busy || !!sellLock} tip={sellLock ?? undefined} />}
        {!waypointPrimary && <Tool icon="map" label={t('Track')} onClick={onTrack} tip={t('Set a waypoint to this vehicle')} />}
      </div>
    </>
  );
}

/* ── spawner vehicle ─────────────────────────────────────────────────── */

export function SpawnerShowcase({
  s,
  garage,
  spawning,
  onSpawn,
}: {
  s: SpawnerVehicleView;
  garage: GarageSummary;
  spawning: number | null;
  onSpawn: () => void;
}) {
  const loading = spawning === s.index;
  const tpl = platePreview(s.plate);
  const key = `s${s.index}`;
  return (
    <ShowcaseFrame
      id={key}
      stage={
        <Stage
          id={key}
          image={s.image}
          vehicleType={s.vehicleType}
          alt={s.label}
          topLeft={<ClassTag icon={<Icon name={vehicleIcon(s)} size={13} strokeWidth={1.8} />} label={s.classLabel || t('Other')} />}
          topRight={
            garage.jobLabel ? (
              <Badge tone="teal" icon="briefcase" size="sm">
                {garage.jobLabel}
              </Badge>
            ) : undefined
          }
          title={<StageTitle make={s.make} name={modelName(s)} />}
          plate={
            <Plate
              plate={tpl ? tpl.text : t('Random')}
              caption={garage.jobLabel ?? t('Fleet')}
              muted={!tpl}
              title={tpl?.random ? t('Plate format — the • characters are filled in randomly') : undefined}
            />
          }
        />
      }
      strip={
        <>
          <StripCell icon="garage" label={t('Garage')} value={garage.name} sub={garage.jobLabel ?? t('Fleet vehicle')} tone="teal" />
          <StripCell
            icon="money"
            label={t('Price')}
            value={s.price > 0 ? money(s.price) : t('Free')}
            sub={s.price > 0 ? t('Paid when you take it out') : t('No charge')}
          />
          <StripCell
            icon="hash"
            label={t('Plate')}
            value={tpl ? tpl.text : t('Random')}
            sub={tpl ? (tpl.random ? t('Partly random') : t('Fixed plate')) : t('Generated on spawn')}
          />
          <StripCell
            icon="users"
            label={t('Seats')}
            value={s.stats && s.stats.seats > 0 ? String(s.stats.seats) : '—'}
            sub={s.classLabel ?? t('Vehicle')}
          />
        </>
      }
      dock={
        <>
          <div className="nz-garage__dock-main">
            <Button variant="teal" size="lg" icon="arrowRight" loading={loading} disabled={spawning !== null && !loading} onClick={onSpawn} className="nz-garage__go">
              <PrimaryLabel keycap={!loading}>
                {loading ? t('Loading vehicle...') : s.price > 0 ? t('Take out · {price}', { price: money(s.price) }) : t('Take out')}
              </PrimaryLabel>
            </Button>
            <span className="nz-garage__dock-reason is-neutral">
              <Icon name="info" size={13} strokeWidth={1.9} />
              <span>
                {garage.jobLabel
                  ? t('{job} vehicle. Store it back here when your shift is over.', { job: garage.jobLabel })
                  : t('Store it back here when you are done.')}
              </span>
            </span>
          </div>
        </>
      }
    >
      {s.stats ? (
        <PerformanceBlock stats={s.stats} />
      ) : (
        <Block title={t('Performance')} icon="gauge">
          <p className="nz-garage__nodata">
            <Icon name="info" size={13} strokeWidth={1.8} />
            {t('No performance data for this model.')}
          </p>
        </Block>
      )}
      <Block title={t('Details')} icon="info">
        <div className="nz-garage__facts">
          <Fact label={t('Model')} mono>
            {s.model}
          </Fact>
          <Fact label={t('Make')}>{s.make || '—'}</Fact>
          <Fact label={t('Class')}>{s.classLabel || t('Other')}</Fact>
          <Fact label={t('Plate format')} mono>
            {tpl ? tpl.text : t('Random')}
          </Fact>
        </div>
        <Callout tone="neutral" icon="info" className="nz-garage__blk-callout">
          {garage.jobLabel
            ? t('Fleet vehicles are not yours to keep: store them here again when you are done.')
            : t('This vehicle is lent to you: store it here again when you are done.')}
        </Callout>
      </Block>
    </ShowcaseFrame>
  );
}

/* ── empty turntable ─────────────────────────────────────────────────── */

export function EmptyShowcase({
  icon,
  title,
  description,
  steps,
  action,
}: {
  icon: IconName;
  title: string;
  description?: string;
  steps?: { icon: IconName; text: ReactNode }[];
  action?: ReactNode;
}) {
  return (
    <div className="nz-garage__show is-empty">
      <Stage id="empty" image={null} vehicleType="car" alt="" empty>
        <div className="nz-garage__vacant">
          <span className="nz-garage__vacant-icon">
            <Icon name={icon} size={20} strokeWidth={1.5} />
          </span>
          <b>{title}</b>
          {description && <p>{description}</p>}
          {action}
        </div>
      </Stage>
      {steps && steps.length > 0 && (
        <ol className="nz-garage__steps">
          {steps.map((s, i) => (
            <li key={i}>
              <span className="nz-garage__steps-n">{i + 1}</span>
              <Icon name={s.icon} size={15} strokeWidth={1.7} />
              <span>{s.text}</span>
            </li>
          ))}
        </ol>
      )}
    </div>
  );
}
