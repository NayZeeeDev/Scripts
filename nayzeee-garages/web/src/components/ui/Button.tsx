/**
 * Buttons & keycaps: Button, IconButton, PillClose, Kbd, KeyHint.
 */
import { forwardRef } from 'react';
import type { MouseEvent, ReactNode } from 'react';
import clsx from 'clsx';
import { t } from '@/lib/i18n';
import { Icon } from '../icons';
import type { IconName } from '../icons';
import { Tooltip } from './Tooltip';
import { Spinner } from './Display';
import { keyLabel } from './internal';
import type { Side } from './internal';

export type ButtonVariant = 'teal' | 'white' | 'line' | 'red' | 'ghost';
export type ButtonSize = 'sm' | 'md' | 'lg';

export interface ButtonProps {
  variant?: ButtonVariant;
  size?: ButtonSize;
  icon?: IconName;
  iconRight?: IconName;
  /** Small pill inside the button (a count, a price…). */
  badge?: ReactNode;
  loading?: boolean;
  disabled?: boolean;
  /** Stretch to the container width. */
  full?: boolean;
  type?: 'button' | 'submit' | 'reset';
  onClick?: (e: MouseEvent<HTMLButtonElement>) => void;
  title?: string;
  autoFocus?: boolean;
  className?: string;
  children?: ReactNode;
}

const ICON_SIZE: Record<ButtonSize, number> = { sm: 13, md: 14, lg: 16 };

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  {
    variant = 'line',
    size = 'md',
    icon,
    iconRight,
    badge,
    loading = false,
    disabled = false,
    full = false,
    type = 'button',
    onClick,
    title,
    autoFocus,
    className,
    children,
  },
  ref,
) {
  const isize = ICON_SIZE[size];
  return (
    <button
      ref={ref}
      type={type}
      title={title}
      autoFocus={autoFocus}
      disabled={disabled || loading}
      aria-busy={loading || undefined}
      onClick={onClick}
      className={clsx(
        'nz-btn',
        `nz-btn--${variant}`,
        `nz-btn--${size}`,
        full && 'nz-btn--full',
        loading && 'nz-btn--loading',
        !children && 'nz-btn--icon-only',
        className,
      )}
    >
      {loading ? <Spinner size={isize} /> : icon ? <Icon name={icon} size={isize} strokeWidth={1.8} /> : null}
      {children !== undefined && children !== null && children !== false && <span className="nz-btn__label">{children}</span>}
      {badge !== undefined && badge !== null && badge !== false && <span className="nz-btn__badge">{badge}</span>}
      {iconRight && <Icon name={iconRight} size={isize} strokeWidth={1.8} className="nz-btn__icon-right" />}
    </button>
  );
});

export interface IconButtonProps {
  icon: IconName;
  /** Tooltip + accessible name. */
  label: string;
  variant?: 'ghost' | 'line' | 'teal' | 'red';
  size?: 'sm' | 'md';
  active?: boolean;
  disabled?: boolean;
  onClick?: (e: MouseEvent<HTMLButtonElement>) => void;
  tooltipSide?: Side;
  className?: string;
}

export const IconButton = forwardRef<HTMLButtonElement, IconButtonProps>(function IconButton(
  { icon, label, variant = 'ghost', size = 'md', active = false, disabled = false, onClick, tooltipSide = 'top', className },
  ref,
) {
  return (
    <Tooltip content={label} side={tooltipSide} disabled={disabled}>
      <button
        ref={ref}
        type="button"
        aria-label={label}
        aria-pressed={active || undefined}
        disabled={disabled}
        onClick={onClick}
        className={clsx('nz-ibtn', `nz-ibtn--${variant}`, `nz-ibtn--${size}`, active && 'is-active', className)}
      >
        <Icon name={icon} size={size === 'sm' ? 14 : 16} strokeWidth={1.7} />
      </button>
    </Tooltip>
  );
});

export interface PillCloseProps {
  onClick: () => void;
  label?: string;
  className?: string;
}

/** The red "Close" pill at the far right of every window header. */
export function PillClose({ onClick, label, className }: PillCloseProps) {
  return (
    <button type="button" className={clsx('nz-pill-close', className)} onClick={onClick}>
      {label ?? t('Close')}
    </button>
  );
}

export interface KbdProps {
  children: ReactNode;
  size?: 'sm' | 'md';
  className?: string;
}

/** Keycap. String children are normalised (ArrowUp → ↑, Escape → Esc). */
export function Kbd({ children, size = 'md', className }: KbdProps) {
  const content = typeof children === 'string' ? keyLabel(children) : children;
  return <kbd className={clsx('nz-kbd', `nz-kbd--${size}`, className)}>{content}</kbd>;
}

export interface KeyHintProps {
  keys: string[];
  label: ReactNode;
  size?: 'sm' | 'md';
  className?: string;
}

/** Keycaps followed by a label: [Esc] Close */
export function KeyHint({ keys, label, size = 'sm', className }: KeyHintProps) {
  return (
    <span className={clsx('nz-keyhint', `nz-keyhint--${size}`, className)}>
      <span className="nz-keyhint__keys">
        {keys.map((k, i) => (
          <Kbd key={`${k}-${i}`} size={size}>
            {k}
          </Kbd>
        ))}
      </span>
      <span className="nz-keyhint__label">{label}</span>
    </span>
  );
}
