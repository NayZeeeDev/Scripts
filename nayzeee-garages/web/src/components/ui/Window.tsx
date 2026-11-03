/**
 * Layout: Window (v5 frame, chamfer, grain, teal rail, red Close pill), Panel, Section,
 * OptionRow, Divider.
 */
import type { CSSProperties, ReactNode } from 'react';
import clsx from 'clsx';
import { Icon } from '../icons';
import type { IconName } from '../icons';
import { BrandMark } from './Display';
import { PillClose } from './Button';

const size = (v: number | string | undefined) => (typeof v === 'number' ? `${v}px` : v);

/* ── Window ───────────────────────────────────────────────────────────── */

export interface WindowProps {
  title: ReactNode;
  icon?: IconName;
  subtitle?: ReactNode;
  badge?: ReactNode;
  headerExtra?: ReactNode;
  onClose?: () => void;
  /** Close pill label (default "Close"). */
  closeLabel?: string;
  width?: number | string;
  height?: number | string;
  footer?: ReactNode;
  /** Large faint brand silhouette in the bottom-right corner of the body. */
  watermark?: boolean;
  className?: string;
  bodyClassName?: string;
  style?: CSSProperties;
  children?: ReactNode;
}

/**
 * Opaque app window. Centered (position: fixed) unless `className` positions it.
 * The body scrolls; `footer` renders as a status strip (inset background, keycaps).
 */
export function Window({
  title,
  icon,
  subtitle,
  badge,
  headerExtra,
  onClose,
  closeLabel,
  width = 960,
  height,
  footer,
  watermark = false,
  className,
  bodyClassName,
  style,
  children,
}: WindowProps) {
  return (
    <section
      role="dialog"
      aria-label={typeof title === 'string' ? title : undefined}
      className={clsx('nz-window', height !== undefined && 'nz-window--fixed-h', className)}
      style={{ width: size(width), height: size(height), ...style }}
    >
      <div className="nz-window__frame">
        <div className="nz-window__shell">
          {watermark && <span className="nz-window__watermark" aria-hidden="true" />}
          <header className="nz-window__bar">
            <div className="nz-window__brand">
              <BrandMark size="sm" />
              <div className="nz-window__titles">
                <div className="nz-window__title-row">
                  {icon && <Icon name={icon} size={15} strokeWidth={1.7} className="nz-window__icon" />}
                  <h2 className="nz-window__title">{title}</h2>
                  {badge && <span className="nz-window__badge">{badge}</span>}
                </div>
                {subtitle && <div className="nz-window__subtitle">{subtitle}</div>}
              </div>
            </div>
            <div className="nz-window__extra">{headerExtra}</div>
            {onClose && <PillClose onClick={onClose} label={closeLabel} />}
          </header>
          <div className={clsx('nz-window__body', bodyClassName)}>{children}</div>
          {footer && <footer className="nz-window__footer">{footer}</footer>}
        </div>
      </div>
    </section>
  );
}

/* ── Panel ────────────────────────────────────────────────────────────── */

export interface PanelProps {
  title?: ReactNode;
  subtitle?: ReactNode;
  icon?: IconName;
  actions?: ReactNode;
  padded?: boolean;
  className?: string;
  bodyClassName?: string;
  children?: ReactNode;
}

/** Card surface (--panel) with an optional header row. */
export function Panel({ title, subtitle, icon, actions, padded = true, className, bodyClassName, children }: PanelProps) {
  const hasHead = title !== undefined || actions !== undefined;
  return (
    <div className={clsx('nz-panel', className)}>
      {hasHead && (
        <div className="nz-panel__head">
          <div className="nz-panel__titles">
            {title !== undefined && (
              <h3 className="nz-panel__title">
                {icon && <Icon name={icon} size={14} strokeWidth={1.7} />}
                {title}
              </h3>
            )}
            {subtitle && <p className="nz-panel__subtitle">{subtitle}</p>}
          </div>
          {actions && <div className="nz-panel__actions">{actions}</div>}
        </div>
      )}
      <div className={clsx('nz-panel__body', padded && 'nz-panel__body--padded', bodyClassName)}>{children}</div>
    </div>
  );
}

/* ── Section ──────────────────────────────────────────────────────────── */

export interface SectionProps {
  title?: ReactNode;
  description?: ReactNode;
  actions?: ReactNode;
  className?: string;
  children?: ReactNode;
}

/** Uppercase heading block; consecutive sections are separated by a hairline. */
export function Section({ title, description, actions, className, children }: SectionProps) {
  return (
    <section className={clsx('nz-section', className)}>
      {(title || actions) && (
        <div className="nz-section__head">
          {title && <h4 className="nz-section__title">{title}</h4>}
          {actions && <div className="nz-section__actions">{actions}</div>}
        </div>
      )}
      {description && <p className="nz-section__desc">{description}</p>}
      {children}
    </section>
  );
}

/* ── OptionRow ────────────────────────────────────────────────────────── */

export interface OptionRowProps {
  label: ReactNode;
  description?: ReactNode;
  control: ReactNode;
  /** Stack the control under the text (sliders, wide inputs). */
  stacked?: boolean;
  className?: string;
}

export function OptionRow({ label, description, control, stacked = false, className }: OptionRowProps) {
  return (
    <div className={clsx('nz-option', stacked && 'nz-option--stacked', className)}>
      <div className="nz-option__text">
        <b>{label}</b>
        {description && <small>{description}</small>}
      </div>
      <div className="nz-option__control">{control}</div>
    </div>
  );
}

/* ── Divider ──────────────────────────────────────────────────────────── */

export interface DividerProps {
  vertical?: boolean;
  /** Optional centered caption. */
  label?: ReactNode;
  className?: string;
}

export function Divider({ vertical = false, label, className }: DividerProps) {
  if (label) {
    return (
      <div className={clsx('nz-divider', 'nz-divider--label', className)} role="separator">
        <span>{label}</span>
      </div>
    );
  }
  return <div className={clsx('nz-divider', vertical && 'nz-divider--v', className)} role="separator" />;
}
