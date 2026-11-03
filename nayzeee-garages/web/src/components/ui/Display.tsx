/**
 * Display components: Chip, Badge, PlateTag, Stat, Bar, Ring, Pips, Meter, Avatar,
 * BrandMark, Spinner, Skeleton, SkeletonRows, EmptyState.
 */
import type { CSSProperties, ReactNode } from 'react';
import clsx from 'clsx';
import { t } from '@/lib/i18n';
import { Icon } from '../icons';
import type { IconName } from '../icons';

export type Tone = 'teal' | 'amber' | 'red' | 'white' | 'blue' | 'neutral';

/** teal ≥ 50, amber ≥ 25, red below (fuel / engine / body). */
export function autoTone(pct: number): 'teal' | 'amber' | 'red' {
  if (pct >= 50) return 'teal';
  if (pct >= 25) return 'amber';
  return 'red';
}

const pct = (value: number, max = 100) => {
  const v = Number(value) || 0;
  const m = Number(max) || 100;
  return Math.max(0, Math.min(100, (v / m) * 100));
};

const px = (v: number | string | undefined) => (typeof v === 'number' ? `${v}px` : v);

/* ── Chip ─────────────────────────────────────────────────────────────── */

export interface ChipProps {
  active?: boolean;
  onClick?: () => void;
  icon?: IconName;
  count?: number;
  disabled?: boolean;
  className?: string;
  children: ReactNode;
}

/** Filter chip (design sheet): inset pill, teal tint when active. */
export function Chip({ active = false, onClick, icon, count, disabled, className, children }: ChipProps) {
  const inner = (
    <>
      {icon && <Icon name={icon} size={14} strokeWidth={1.7} className="nz-chip__icon" />}
      <span className="nz-chip__label">{children}</span>
      {count !== undefined && <span className="nz-chip__count">{count}</span>}
    </>
  );
  const cls = clsx('nz-chip', active && 'is-active', onClick && 'nz-chip--button', className);
  if (!onClick) return <span className={cls}>{inner}</span>;
  return (
    <button type="button" className={cls} onClick={onClick} disabled={disabled} aria-pressed={active}>
      {inner}
    </button>
  );
}

/* ── Badge ────────────────────────────────────────────────────────────── */

export interface BadgeProps {
  tone?: 'teal' | 'amber' | 'red' | 'neutral' | 'white' | 'blue';
  icon?: IconName;
  size?: 'sm' | 'md';
  /** Glowing status dot instead of an icon. */
  dot?: boolean;
  title?: string;
  className?: string;
  children: ReactNode;
}

export function Badge({ tone = 'neutral', icon, size = 'md', dot = false, title, className, children }: BadgeProps) {
  return (
    <span className={clsx('nz-badge', `nz-badge--${tone}`, `nz-badge--${size}`, className)} title={title}>
      {dot && <span className="nz-badge__dot" />}
      {icon && <Icon name={icon} size={size === 'sm' ? 10 : 11} strokeWidth={2} />}
      <span className="nz-badge__text">{children}</span>
    </span>
  );
}

/* ── PlateTag ─────────────────────────────────────────────────────────── */

export interface PlateTagProps {
  plate: string;
  size?: 'sm' | 'md';
  className?: string;
}

export function PlateTag({ plate, size = 'md', className }: PlateTagProps) {
  const text = (plate ?? '').trim().toUpperCase() || '—';
  return (
    <span className={clsx('nz-plate', `nz-plate--${size}`, className)} title={text}>
      {text}
    </span>
  );
}

/* ── Bar / Ring / Pips ────────────────────────────────────────────────── */

export type MeterTone = Tone | 'auto';

const resolveTone = (tone: MeterTone | undefined, p: number): Tone =>
  tone === 'auto' ? autoTone(p) : tone ?? 'teal';

export interface BarProps {
  value: number;
  max?: number;
  tone?: MeterTone;
  height?: number;
  className?: string;
}

export function Bar({ value, max = 100, tone = 'teal', height = 3, className }: BarProps) {
  const p = pct(value, max);
  return (
    <div
      className={clsx('nz-bar', `nz-tone--${resolveTone(tone, p)}`, className)}
      style={{ height }}
      role="progressbar"
      aria-valuenow={Math.round(p)}
      aria-valuemin={0}
      aria-valuemax={100}
    >
      <div className="nz-bar__fill" style={{ width: `${p}%` }} />
    </div>
  );
}

export interface RingProps {
  value: number;
  max?: number;
  size?: number;
  stroke?: number;
  tone?: MeterTone;
  className?: string;
  children?: ReactNode;
}

export function Ring({ value, max = 100, size = 34, stroke = 3, tone = 'teal', className, children }: RingProps) {
  const p = pct(value, max);
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  return (
    <span
      className={clsx('nz-ring', `nz-tone--${resolveTone(tone, p)}`, className)}
      style={{ width: size, height: size }}
      role="progressbar"
      aria-valuenow={Math.round(p)}
    >
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`}>
        <circle className="nz-ring__track" cx={size / 2} cy={size / 2} r={r} strokeWidth={stroke} />
        <circle
          className="nz-ring__arc"
          cx={size / 2}
          cy={size / 2}
          r={r}
          strokeWidth={stroke}
          strokeDasharray={`${(c * p) / 100} ${c}`}
        />
      </svg>
      {children !== undefined && <span className="nz-ring__inner">{children}</span>}
    </span>
  );
}

export interface PipsProps {
  total: number;
  done: number;
  tone?: MeterTone;
  className?: string;
}

/** Segmented progress (e.g. finance payments 8 / 24). Falls back to a bar above 40 segments. */
export function Pips({ total, done, tone = 'teal', className }: PipsProps) {
  const n = Math.max(0, Math.floor(total || 0));
  const d = Math.max(0, Math.min(n, Math.floor(done || 0)));
  const p = n ? (d / n) * 100 : 0;
  const cls = clsx('nz-pips', `nz-tone--${resolveTone(tone, p)}`, className);
  if (n === 0) return <div className={cls} />;
  if (n > 40) return <Bar value={d} max={n} tone={tone} height={6} className={className} />;
  return (
    <div className={cls} role="progressbar" aria-valuenow={d} aria-valuemax={n}>
      {Array.from({ length: n }, (_, i) => (
        <span key={i} className={clsx('nz-pips__pip', i < d && 'is-done')} />
      ))}
    </div>
  );
}

/* ── Stat ─────────────────────────────────────────────────────────────── */

export interface StatProps {
  label: ReactNode;
  icon?: IconName;
  value: number;
  suffix?: string;
  tone?: 'auto' | 'teal' | 'amber' | 'red';
  /** Rendered at the top-right (e.g. a "Needs service" badge). */
  extra?: ReactNode;
  className?: string;
}

/** Fuel / engine / body card: label + icon, big value + suffix, bar under it. */
export function Stat({ label, icon, value, suffix = '%', tone = 'auto', extra, className }: StatProps) {
  const v = Math.round(Number(value) || 0);
  const p = Math.max(0, Math.min(100, v));
  const resolved = tone === 'auto' ? autoTone(p) : tone;
  return (
    <div className={clsx('nz-stat', `nz-tone--${resolved}`, className)}>
      <div className="nz-stat__head">
        {icon && <Icon name={icon} size={13} strokeWidth={1.7} className="nz-stat__icon" />}
        <span className="nz-stat__label">{label}</span>
        {extra && <span className="nz-stat__extra">{extra}</span>}
      </div>
      <div className="nz-stat__value">
        <b>{v.toLocaleString('en-US')}</b>
        {suffix && <span>{suffix}</span>}
      </div>
      <Bar value={p} tone={resolved} height={3} />
    </div>
  );
}

/* ── Meter ────────────────────────────────────────────────────────────── */

export interface MeterProps {
  label: ReactNode;
  icon?: IconName;
  used: number;
  /** null / 0 / Infinity = unlimited. */
  total: number | null;
  className?: string;
}

/** Capacity readout: "Your spaces 6/12" with a mini bar. */
export function Meter({ label, icon, used, total, className }: MeterProps) {
  const unlimited = !total || !Number.isFinite(total);
  const p = unlimited ? 0 : pct(used, total as number);
  const tone: Tone = unlimited ? 'teal' : p >= 100 ? 'red' : p >= 80 ? 'amber' : 'teal';
  return (
    <span className={clsx('nz-meter', `nz-tone--${tone}`, className)}>
      {icon && <Icon name={icon} size={13} strokeWidth={1.7} className="nz-meter__icon" />}
      <span className="nz-meter__label">{label}</span>
      <span className="nz-meter__value">
        <b>{used}</b>
        <span>/{unlimited ? '∞' : total}</span>
      </span>
      {!unlimited && (
        <span className="nz-meter__track">
          <span className="nz-meter__fill" style={{ width: `${p}%` }} />
        </span>
      )}
    </span>
  );
}

/* ── Avatar / BrandMark ───────────────────────────────────────────────── */

export interface AvatarProps {
  name: string;
  size?: number;
  className?: string;
}

export function initials(name: string): string {
  const parts = (name ?? '').trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return '?';
  const a = parts[0][0] ?? '';
  const b = parts.length > 1 ? parts[parts.length - 1][0] ?? '' : parts[0][1] ?? '';
  return (a + b).toUpperCase();
}

export function Avatar({ name, size = 32, className }: AvatarProps) {
  return (
    <span
      className={clsx('nz-avatar', className)}
      style={{ width: size, height: size, fontSize: Math.max(9, Math.round(size * 0.34)) }}
      title={name}
      aria-hidden="true"
    >
      {initials(name)}
    </span>
  );
}

export interface BrandMarkProps {
  size?: 'sm' | 'md' | 'lg';
  className?: string;
}

/** The NayZeee mark: the window silhouette (chamfer) in teal, with a cut-out bar. */
export function BrandMark({ size = 'md', className }: BrandMarkProps) {
  return (
    <span className={clsx('nz-mark', `nz-mark--${size}`, className)} aria-hidden="true">
      <span className="nz-mark__shape" />
    </span>
  );
}

/* ── Spinner / Skeleton ───────────────────────────────────────────────── */

export interface SpinnerProps {
  size?: number;
  className?: string;
}

export function Spinner({ size = 16, className }: SpinnerProps) {
  return (
    <svg
      className={clsx('nz-spinner', className)}
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      role="status"
      aria-label={t('Loading')}
    >
      <circle cx="12" cy="12" r="9" stroke="currentColor" strokeOpacity=".2" strokeWidth="2.6" />
      <path d="M21 12a9 9 0 0 0-9-9" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" />
    </svg>
  );
}

export interface SkeletonProps {
  width?: number | string;
  height?: number | string;
  radius?: number | string;
  className?: string;
  style?: CSSProperties;
}

export function Skeleton({ width = '100%', height = 10, radius, className, style }: SkeletonProps) {
  return (
    <span
      className={clsx('nz-skel', className)}
      style={{ width: px(width), height: px(height), borderRadius: px(radius), ...style }}
      aria-hidden="true"
    />
  );
}

export interface SkeletonRowsProps {
  count?: number;
  className?: string;
}

const SKEL_WIDTHS: [number, number][] = [
  [52, 32],
  [66, 40],
  [44, 28],
  [58, 36],
  [48, 24],
];

/** v5 loading rows: tile + two lines. */
export function SkeletonRows({ count = 3, className }: SkeletonRowsProps) {
  return (
    <div className={clsx('nz-skelrows', className)} aria-busy="true" aria-label={t('Loading')}>
      {Array.from({ length: count }, (_, i) => {
        const [a, b] = SKEL_WIDTHS[i % SKEL_WIDTHS.length];
        return (
          <div key={i} className="nz-skelrows__row">
            <Skeleton width={30} height={30} radius={6} />
            <div className="nz-skelrows__lines">
              <Skeleton width={`${a}%`} height={9} />
              <Skeleton width={`${b}%`} height={7} />
            </div>
          </div>
        );
      })}
    </div>
  );
}

/* ── EmptyState ───────────────────────────────────────────────────────── */

export interface EmptyStateProps {
  icon?: IconName;
  title: ReactNode;
  description?: ReactNode;
  action?: ReactNode;
  compact?: boolean;
  className?: string;
}

export function EmptyState({ icon = 'layers', title, description, action, compact = false, className }: EmptyStateProps) {
  return (
    <div className={clsx('nz-empty', compact && 'nz-empty--compact', className)}>
      <span className="nz-empty__icon">
        <Icon name={icon} size={compact ? 16 : 20} strokeWidth={1.5} />
      </span>
      <b className="nz-empty__title">{title}</b>
      {description && <span className="nz-empty__desc">{description}</span>}
      {action && <div className="nz-empty__action">{action}</div>}
    </div>
  );
}
