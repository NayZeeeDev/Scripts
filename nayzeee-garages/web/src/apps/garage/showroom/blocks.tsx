/**
 * Showcase building blocks: section block (uppercase heading), status strip cells,
 * segmented 10-cell gauges, rating bars, upgrade level pips, callouts, fact rows — and the
 * detail sections built from them: Condition (gauges + damage glyph), Performance, Upgrades,
 * Finance, Impound and Details.
 */
import type { ReactNode } from 'react';
import { Badge, Button, Icon, Pips, cx } from '@/components/ui';
import type { IconName } from '@/components/ui';
import { t } from '@/lib/i18n';
import { dateTime, hoursLabel, money } from '@/lib/format';
import { useSettings } from '@/lib/store';
import type { DamageSummary, Finance, ImpoundInfo, ModSummary, VehicleStats } from '@/lib/types';
import { countdown, damageCaption, intervalLabel, speedIn, useNow } from '../model';
import { DamageGlyph } from './DamageGlyph';
import type { GlyphShape } from './DamageGlyph';

type Tone = 'teal' | 'amber' | 'red';
const autoTone = (v: number): Tone => (v >= 50 ? 'teal' : v >= 25 ? 'amber' : 'red');
const clampPct = (v: number) => Math.max(0, Math.min(100, Math.round(Number(v) || 0)));

/* ── primitives ──────────────────────────────────────────────────────── */

export function Block({
  title,
  icon,
  aside,
  tone,
  wide = false,
  className,
  children,
}: {
  title: string;
  icon?: IconName;
  aside?: ReactNode;
  tone?: 'red' | 'amber' | 'teal';
  wide?: boolean;
  className?: string;
  children: ReactNode;
}) {
  return (
    <section className={cx('nz-garage__blk', wide && 'is-wide', tone && `is-${tone}`, className)}>
      <header className="nz-garage__blk-head">
        <h4>
          {icon && <Icon name={icon} size={12} strokeWidth={2} />}
          {title}
        </h4>
        {aside && <div className="nz-garage__blk-aside">{aside}</div>}
      </header>
      <div className="nz-garage__blk-body">{children}</div>
    </section>
  );
}

/** One cell of the status strip under the stage. */
export function StripCell({
  icon,
  label,
  value,
  sub,
  tone,
}: {
  icon: IconName;
  label: string;
  value: ReactNode;
  sub?: ReactNode;
  tone?: 'teal' | 'amber' | 'red' | 'grey';
}) {
  return (
    <div className={cx('nz-garage__cell', tone && `is-${tone}`)}>
      <span className="nz-garage__cell-label">
        <Icon name={icon} size={11} strokeWidth={2} />
        {label}
      </span>
      <span className="nz-garage__cell-line">
        <span className="nz-garage__cell-value">{value}</span>
        {sub && <span className="nz-garage__cell-sub">{sub}</span>}
      </span>
    </div>
  );
}

/** Segmented 10-cell gauge (engine / body / fuel). */
function Gauge({ label, icon, value }: { label: string; icon: IconName; value: number }) {
  const v = clampPct(value);
  const lit = v === 0 ? 0 : Math.max(1, Math.round(v / 10));
  return (
    <div className={cx('nz-garage__gauge', `is-${autoTone(v)}`)} role="meter" aria-label={label} aria-valuenow={v} aria-valuemin={0} aria-valuemax={100}>
      <span className="nz-garage__gauge-label">
        <Icon name={icon} size={13} strokeWidth={1.8} />
        {label}
      </span>
      <span className="nz-garage__gauge-cells" aria-hidden="true">
        {Array.from({ length: 10 }, (_, i) => (
          <i key={i} className={i < lit ? 'is-on' : undefined} />
        ))}
      </span>
      <b className="nz-garage__gauge-val">
        {v}
        <small>%</small>
      </b>
    </div>
  );
}

/** 0–100 rating bar with quarter ticks. */
function Rating({ label, value }: { label: string; value: number }) {
  const v = clampPct(value);
  return (
    <div className="nz-garage__rating">
      <span>{label}</span>
      <span className="nz-garage__rating-track" aria-hidden="true">
        <span style={{ width: `${v}%` }} />
      </span>
      <b>{v}</b>
    </div>
  );
}

/** Upgrade level: one pip per level, "Stock" at 0. */
function LevelRow({ label, icon, level, max }: { label: string; icon: IconName; level: number; max: number }) {
  const lv = Math.max(0, Math.floor(Number(level) || 0));
  const total = Math.max(max, lv);
  return (
    <div className={cx('nz-garage__lvl', lv === 0 && 'is-stock', lv >= total && lv > 0 && 'is-max')}>
      <span className="nz-garage__lvl-label">
        <Icon name={icon} size={13} strokeWidth={1.8} />
        {label}
      </span>
      <span className="nz-garage__lvl-pips" aria-hidden="true">
        {Array.from({ length: total }, (_, i) => (
          <i key={i} className={i < lv ? 'is-on' : undefined} />
        ))}
      </span>
      <b>{lv === 0 ? t('Stock') : lv >= total ? t('Max') : t('Lv {n}', { n: lv })}</b>
    </div>
  );
}

export function Callout({
  tone = 'neutral',
  icon,
  children,
  action,
  className,
}: {
  tone?: 'neutral' | 'amber' | 'red' | 'teal';
  icon: IconName;
  children: ReactNode;
  action?: ReactNode;
  className?: string;
}) {
  return (
    <div className={cx('nz-garage__callout', `is-${tone}`, className)}>
      <Icon name={icon} size={14} strokeWidth={1.8} />
      <span className="nz-garage__callout-text">{children}</span>
      {action}
    </div>
  );
}

/** Label / value row of the Details and Impound blocks. */
export function Fact({ label, children, mono = false, wrap = false }: { label: string; children: ReactNode; mono?: boolean; wrap?: boolean }) {
  return (
    <div className={cx('nz-garage__fact', wrap && 'is-wrap')}>
      <span>{label}</span>
      <b className={cx(mono && 'is-mono')}>{children}</b>
    </div>
  );
}

/* ── sections ────────────────────────────────────────────────────────── */

export function ConditionBlock({
  engine,
  body,
  fuel,
  damage,
  shape,
  needsService,
}: {
  engine: number;
  body: number;
  fuel: number;
  damage: DamageSummary | null;
  shape: GlyphShape;
  needsService: boolean;
}) {
  const caption = damageCaption(damage);
  const hasDamage = !!damage && (damage.doors.length > 0 || damage.windows.length > 0 || damage.tyres.length > 0 || damage.deformed);
  return (
    <Block
      title={t('Condition')}
      icon="wrench"
      aside={
        needsService ? (
          <Badge tone="amber" icon="wrench" size="sm">
            {t('Needs service')}
          </Badge>
        ) : undefined
      }
    >
      <div className="nz-garage__cond">
        <div className="nz-garage__gauges">
          <Gauge label={t('Engine')} icon="engine" value={engine} />
          <Gauge label={t('Body')} icon="shield" value={body} />
          <Gauge label={t('Fuel')} icon="fuel" value={fuel} />
          <p className={cx('nz-garage__cond-cap', hasDamage && 'is-hit', !damage && 'is-nodata')}>
            <Icon name={hasDamage ? 'warning' : damage ? 'checkCircle' : 'info'} size={12} strokeWidth={1.9} />
            <span>{caption}</span>
          </p>
        </div>
        <DamageGlyph damage={damage} shape={shape} body={body} />
      </div>
    </Block>
  );
}

export function PerformanceBlock({ stats, className }: { stats: VehicleStats; className?: string }) {
  const unit = useSettings().distanceUnit;
  const top = speedIn(stats.topSpeed, unit);
  return (
    <Block title={t('Performance')} icon="gauge" className={className}>
      <div className="nz-garage__perf">
        <div className="nz-garage__perf-top">
          <div className="nz-garage__perf-speed">
            <b>{top.value.toLocaleString('en-US')}</b>
            <span>{top.unit}</span>
          </div>
          <span className="nz-garage__perf-cap">{t('Top speed')}</span>
          {stats.seats > 0 && (
            <span className="nz-garage__perf-seats" title={t('Seats')}>
              <Icon name="users" size={12} strokeWidth={1.9} />
              {stats.seats === 1 ? t('1 seat') : t('{n} seats', { n: stats.seats })}
            </span>
          )}
        </div>
        <div className="nz-garage__ratings">
          <Rating label={t('Speed')} value={stats.speed} />
          <Rating label={t('Acceleration')} value={stats.acceleration} />
          <Rating label={t('Braking')} value={stats.braking} />
          <Rating label={t('Traction')} value={stats.traction} />
        </div>
      </div>
    </Block>
  );
}

/** GTA mod levels (index + 1); armour has 5 levels, engine / suspension 4, brakes / gearbox 3. */
export function UpgradesBlock({ mods }: { mods: ModSummary | null }) {
  return (
    <Block
      title={t('Upgrades')}
      icon="sparkle"
      aside={
        mods ? (
          <span className={cx('nz-garage__turbo', mods.turbo && 'is-on')}>
            <i aria-hidden="true" />
            {mods.turbo ? t('Turbo') : t('No turbo')}
          </span>
        ) : undefined
      }
    >
      {mods ? (
        <div className="nz-garage__lvls">
          <LevelRow label={t('Engine')} icon="engine" level={mods.engine} max={4} />
          <LevelRow label={t('Brakes')} icon="wheel" level={mods.brakes} max={3} />
          <LevelRow label={t('Transmission')} icon="cog" level={mods.transmission} max={3} />
          <LevelRow label={t('Suspension')} icon="sliders" level={mods.suspension} max={4} />
          <LevelRow label={t('Armour')} icon="shield" level={mods.armor} max={5} />
        </div>
      ) : (
        <p className="nz-garage__nodata">
          <Icon name="info" size={13} strokeWidth={1.8} />
          {t('No upgrade data — it is saved the next time the vehicle is stored.')}
        </p>
      )}
    </Block>
  );
}

/**
 * Finance: one compact row (balance · recurring payment · next payment · pay buttons) over
 * the payment pips. `lockNote` adds the "stays locked" line when the dock does not already
 * explain it (overdue vehicle that is not parked here).
 */
export function FinanceBlock({
  finance,
  onPay,
  disabled,
  lockNote = false,
}: {
  finance: Finance;
  onPay: (full: boolean) => void;
  disabled?: boolean;
  lockNote?: boolean;
}) {
  const total = finance.paymentsTotal;
  const done = total ? Math.max(0, total - finance.paymentsLeft) : 0;
  const nextPayment = Math.min(finance.payment, finance.balance);
  return (
    <Block
      title={t('Finance')}
      icon="receipt"
      wide
      tone={finance.overdue ? 'red' : undefined}
      className="nz-garage__blk--fin"
      aside={
        finance.overdue ? (
          <Badge tone="red" icon="warning" size="sm">
            {t('Payment overdue')}
          </Badge>
        ) : (
          <Badge tone="neutral" size="sm">
            {t('{n} payment(s) left', { n: finance.paymentsLeft })}
          </Badge>
        )
      }
    >
      <div className="nz-garage__fin">
        <div className="nz-garage__fin-row">
          <div className="nz-garage__fin-fig">
            <span>{t('Remaining balance')}</span>
            <b>{money(finance.balance)}</b>
          </div>
          <div className="nz-garage__fin-fig">
            <span>{t('Recurring payment')}</span>
            <b>
              {money(finance.payment)}
              {finance.intervalHours ? <small> / {intervalLabel(finance.intervalHours)}</small> : null}
            </b>
          </div>
          <div className="nz-garage__fin-fig">
            <span>{t('Next payment')}</span>
            {finance.overdue ? (
              <b className="is-red">{t('Overdue')}</b>
            ) : finance.nextPaymentHours != null ? (
              <b>{t('in {time}', { time: hoursLabel(finance.nextPaymentHours) })}</b>
            ) : (
              <b>—</b>
            )}
          </div>
          <div className="nz-garage__fin-actions">
            <Button size="sm" variant="line" disabled={disabled} onClick={() => onPay(true)}>
              {t('Pay in full')}
            </Button>
            <Button
              size="sm"
              variant={finance.overdue ? 'red' : 'white'}
              icon="money"
              badge={money(nextPayment)}
              disabled={disabled}
              onClick={() => onPay(false)}
            >
              {t('Make payment')}
            </Button>
          </div>
        </div>
        <div className="nz-garage__fin-progress">
          {total ? (
            <>
              <Pips total={total} done={done} tone={finance.overdue ? 'red' : 'teal'} />
              <span>{t('{done} of {total} paid', { done, total })}</span>
            </>
          ) : (
            <span>{t('{n} payment(s) left', { n: finance.paymentsLeft })}</span>
          )}
        </div>
        {finance.overdue && lockNote && (
          <span className="nz-garage__fin-warn">
            <Icon name="lock" size={12} strokeWidth={1.9} />
            {t('The vehicle stays locked until the overdue payment is made.')}
          </span>
        )}
      </div>
    </Block>
  );
}

/* ── impound availability (live) ─────────────────────────────────────── */

export function useAvailability(info: ImpoundInfo | null) {
  const waiting = !!info && info.retrievable && info.releaseAt > Math.floor(Date.now() / 1000);
  const now = useNow(waiting);
  if (!info) return null;
  if (!info.retrievable) return { state: 'release' as const, seconds: 0 };
  const seconds = info.releaseAt - now;
  if (seconds > 0) return { state: 'waiting' as const, seconds };
  return { state: 'now' as const, seconds: 0 };
}

/** Release countdown pill for the impound block's heading. */
function ReleasePill({ info }: { info: ImpoundInfo }) {
  const a = useAvailability(info);
  if (!a) return null;
  if (a.state === 'release') {
    return (
      <span className="nz-garage__relpill is-red" title={t('Staff have to release it first')}>
        <Icon name="lock" size={12} strokeWidth={1.9} />
        <b>{t('On hold')}</b>
        <span>{t('staff release')}</span>
      </span>
    );
  }
  if (a.state === 'waiting') {
    return (
      <span className="nz-garage__relpill is-amber" title={t('Released {date}', { date: dateTime(info.releaseAt) })}>
        <Icon name="clock" size={12} strokeWidth={1.9} />
        <b>{countdown(a.seconds)}</b>
        <span>{t('until release')}</span>
      </span>
    );
  }
  return (
    <span className="nz-garage__relpill is-teal" title={t('Since {date}', { date: dateTime(info.releaseAt) })}>
      <Icon name="checkCircle" size={12} strokeWidth={1.9} />
      <b>{t('Available now')}</b>
    </span>
  );
}

/**
 * Impound details. `lot`: inside the impound app, where the status strip already shows the
 * date, fee and availability; only the reason, who impounded it and the owner remain.
 */
export function ImpoundBlock({
  info,
  owner,
  lot = false,
}: {
  info: ImpoundInfo;
  owner?: string | null;
  lot?: boolean;
}) {
  return (
    <Block title={t('Impound')} icon="impound" wide tone="red" className="nz-garage__blk--imp" aside={lot ? undefined : <ReleasePill info={info} />}>
      <div className={cx('nz-garage__imp', lot && 'is-lot')}>
        <div className="nz-garage__imp-reason">
          <span>{t('Reason')}</span>
          <p title={info.reason}>{info.reason || t('No reason given')}</p>
        </div>
        <div className="nz-garage__imp-facts">
          <Fact label={t('Impounded by')}>{info.byName || t('Unknown')}</Fact>
          {owner && <Fact label={t('Owner')}>{owner}</Fact>}
          {!lot && <Fact label={t('Impounded on')}>{dateTime(info.at)}</Fact>}
          {!lot && <Fact label={t('Retrieval fee')}>{info.fee > 0 ? money(info.fee) : t('No charge')}</Fact>}
        </div>
      </div>
    </Block>
  );
}
