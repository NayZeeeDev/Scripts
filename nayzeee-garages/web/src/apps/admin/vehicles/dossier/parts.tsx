/**
 * Building blocks of the vehicle dossier: turntable Stage, registration Plate, segmented
 * gauges, section headings, fact rows and attention callouts.
 */
import type { CSSProperties, ReactNode } from 'react';
import { Icon, VehicleImage, autoTone, cx } from '@/components/ui';
import type { IconName } from '@/components/ui';
import { t } from '@/lib/i18n';
import { percent } from '@/lib/format';
import type { VehicleType } from '@/lib/types';

/* ── stage ─────────────────────────────────────────────────────────────── */

interface StageProps {
  image: string | null;
  vehicleType: VehicleType;
  alt: string;
  /** Red stamp across the stage ("IMPOUNDED", "BLOCKED"). */
  stamp?: string | null;
  topLeft?: ReactNode;
  className?: string;
}

/** The vehicle on a small turntable: spotlight, floor grid, teal horizon, floor shadow. */
export function Stage({ image, vehicleType, alt, stamp, topLeft, className }: StageProps) {
  return (
    <div className={cx('nz-dos-stage', `is-${vehicleType}`, className)}>
      <span className="nz-dos-stage__floor" aria-hidden="true" />
      <span className="nz-dos-stage__horizon" aria-hidden="true" />
      <span className="nz-dos-stage__spot" aria-hidden="true" />
      <span className="nz-dos-stage__shadow" aria-hidden="true" />
      <VehicleImage image={image} vehicleType={vehicleType} alt={alt} className="nz-dos-stage__img" />
      {topLeft && <span className="nz-dos-stage__tl">{topLeft}</span>}
      {stamp && (
        <span className="nz-dos-stage__stamp" aria-hidden="true">
          {stamp}
        </span>
      )}
    </div>
  );
}

/* ── plate ─────────────────────────────────────────────────────────────── */

/** San Andreas registration plate (dark inset, mono). */
export function Plate({ plate, size = 'md', className }: { plate: string; size?: 'sm' | 'md'; className?: string }) {
  return (
    <span className={cx('nz-dos-plate', `nz-dos-plate--${size}`, className)} aria-label={t('Plate {plate}', { plate })}>
      <b>{plate}</b>
      <small>{t('SAN ANDREAS')}</small>
    </span>
  );
}

/* ── gauges ────────────────────────────────────────────────────────────── */

/** 10-cell segmented gauge with label + %. Tone: teal ≥ 50, amber ≥ 25, red below. */
export function SegGauge({ icon, label, value, detail, className }: { icon: IconName; label: string; value: number; detail?: ReactNode; className?: string }) {
  const v = percent(value);
  const tone = autoTone(v);
  const lit = v <= 0 ? 0 : Math.max(1, Math.round(v / 10));
  return (
    <div className={cx('nz-dos-gauge', `is-${tone}`, className)}>
      <div className="nz-dos-gauge__top">
        <Icon name={icon} size={13} strokeWidth={1.7} />
        <span>{label}</span>
        {detail && <em>{detail}</em>}
        <b>
          {v}
          <small>%</small>
        </b>
      </div>
      <div className="nz-dos-gauge__cells" role="meter" aria-valuemin={0} aria-valuemax={100} aria-valuenow={v} aria-label={label}>
        {Array.from({ length: 10 }, (_, i) => (
          <i key={i} className={cx(i < lit && 'is-on')} />
        ))}
      </div>
    </div>
  );
}

/** Level pips for an upgrade (0 = stock). */
export function LevelPips({ levels, level }: { levels: number; level: number }) {
  return (
    <span className="nz-dos-lvl" aria-hidden="true">
      {Array.from({ length: levels }, (_, i) => (
        <i key={i} className={cx(i < level && 'is-on')} />
      ))}
    </span>
  );
}

/* ── layout ────────────────────────────────────────────────────────────── */

/** Uppercase section heading (11/700/.12em) with optional count and actions. */
export function Heading({ children, count, actions, className }: { children: ReactNode; count?: ReactNode; actions?: ReactNode; className?: string }) {
  return (
    <div className={cx('nz-dos-h', className)}>
      <h4>
        {children}
        {count !== undefined && count !== null && <span>{count}</span>}
      </h4>
      {actions && <div className="nz-dos-h__actions">{actions}</div>}
    </div>
  );
}

/** One fact line: grey label left, value right. `optional` lines may be hidden on short screens. */
export function Fact({
  label,
  icon,
  children,
  mono,
  tone,
  optional,
}: {
  label: string;
  icon?: IconName;
  children: ReactNode;
  mono?: boolean;
  tone?: 'teal' | 'amber' | 'red' | 'muted';
  optional?: boolean;
}) {
  return (
    <div className={cx('nz-dos-fact', optional && 'is-optional')}>
      <span className="nz-dos-fact__label">
        {icon && <Icon name={icon} size={13} strokeWidth={1.6} />}
        {label}
      </span>
      <span className={cx('nz-dos-fact__value', mono && 'is-mono', tone && `is-${tone}`)}>{children}</span>
    </div>
  );
}

export type CalloutTone = 'teal' | 'amber' | 'red' | 'blue';

/**
 * Attention callout: tinted tile + title + text + optional action. `hint` is the full plain
 * sentence, shown as the tooltip of the (line-clamped) text.
 */
export function Callout({
  tone,
  icon,
  title,
  children,
  action,
  hint,
}: {
  tone: CalloutTone;
  icon: IconName;
  title: ReactNode;
  children?: ReactNode;
  action?: ReactNode;
  hint?: string;
}) {
  return (
    <div className={cx('nz-dos-callout', `is-${tone}`)} role="note">
      <span className="nz-dos-callout__icon">
        <Icon name={icon} size={15} strokeWidth={1.8} />
      </span>
      <div className="nz-dos-callout__text" title={hint}>
        <b>{title}</b>
        {children && <span>{children}</span>}
      </div>
      {action && <div className="nz-dos-callout__action">{action}</div>}
    </div>
  );
}

/** A colour chip (glossy) with an unknown-colour hatch when there is no hex. */
export function ColourChip({ hex, size = 30, glow = false, className }: { hex: string | null; size?: number; glow?: boolean; className?: string }) {
  return (
    <span
      className={cx('nz-dos-chip', !hex && 'is-unknown', glow && 'is-glow', className)}
      style={{ '--nz-chip': `${size}px`, ...(hex ? { background: hex, color: hex } : {}) } as CSSProperties}
      aria-hidden="true"
    />
  );
}
