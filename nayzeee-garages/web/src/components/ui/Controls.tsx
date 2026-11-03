/**
 * Selection controls: Toggle, Segmented, Tabs, Slider, ColorSwatches.
 */
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import type { CSSProperties, KeyboardEvent, ReactNode } from 'react';
import clsx from 'clsx';
import { t } from '@/lib/i18n';
import { Icon } from '../icons';
import type { IconName } from '../icons';
import { useFieldContext } from './Field';
import { useUid } from './internal';

/* ── Toggle ───────────────────────────────────────────────────────────── */

export interface ToggleProps {
  checked: boolean;
  onChange: (checked: boolean) => void;
  disabled?: boolean;
  label?: ReactNode;
  description?: ReactNode;
  size?: 'sm' | 'md';
  className?: string;
}

/** Design-sheet switch: white knob → dark knob on a solid accent track. */
export function Toggle({ checked, onChange, disabled = false, label, description, size = 'md', className }: ToggleProps) {
  const id = useUid('nz-tg');
  const sw = (
    <button
      type="button"
      role="switch"
      id={id}
      aria-checked={checked}
      aria-labelledby={label ? `${id}-l` : undefined}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className={clsx('nz-toggle', `nz-toggle--${size}`, checked && 'is-on', !label && className)}
    >
      <i />
    </button>
  );
  if (!label) return sw;
  return (
    <div className={clsx('nz-option', 'nz-toggle-row', disabled && 'is-disabled', className)}>
      <div className="nz-option__text" onClick={() => !disabled && onChange(!checked)}>
        <b id={`${id}-l`}>{label}</b>
        {description && <small>{description}</small>}
      </div>
      <div className="nz-option__control">{sw}</div>
    </div>
  );
}

/* ── shared sliding indicator ─────────────────────────────────────────── */

function useIndicator(activeKey: string | number | null) {
  const wrapRef = useRef<HTMLDivElement>(null);
  const [ind, setInd] = useState<CSSProperties | null>(null);
  const measure = useCallback(() => {
    const wrap = wrapRef.current;
    if (!wrap) return;
    const el = wrap.querySelector<HTMLElement>('[data-active="true"]');
    if (!el) {
      setInd(null);
      return;
    }
    setInd({ width: el.offsetWidth, transform: `translateX(${el.offsetLeft}px)` });
  }, []);
  useLayoutEffect(measure, [measure, activeKey]);
  useEffect(() => {
    const wrap = wrapRef.current;
    if (!wrap || typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver(() => measure());
    ro.observe(wrap);
    wrap.querySelectorAll('button').forEach((b) => ro.observe(b));
    void document.fonts?.ready.then(measure);
    return () => ro.disconnect();
  }, [measure]);
  return { wrapRef, ind };
}

const arrowNav = <T,>(e: KeyboardEvent, items: { value: T; disabled?: boolean }[], value: T, onChange: (v: T) => void) => {
  if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
  e.preventDefault();
  const enabled = items.filter((i) => !i.disabled);
  const idx = enabled.findIndex((i) => i.value === value);
  const next = enabled[(idx + (e.key === 'ArrowRight' ? 1 : -1) + enabled.length) % enabled.length];
  if (next) {
    onChange(next.value);
    const parent = (e.currentTarget as HTMLElement).parentElement;
    requestAnimationFrame(() => parent?.querySelector<HTMLElement>('[data-active="true"]')?.focus());
  }
};

/* ── Segmented ────────────────────────────────────────────────────────── */

export interface SegmentedOption<T extends string | number> {
  value: T;
  label: string;
  icon?: IconName;
  disabled?: boolean;
}

export interface SegmentedProps<T extends string | number> {
  value: T;
  onChange: (v: T) => void;
  options: SegmentedOption<T>[];
  size?: 'sm' | 'md';
  /** Stretch segments to fill the container. */
  full?: boolean;
  /** Show icons only (labels become tooltips / aria-labels). */
  iconOnly?: boolean;
  disabled?: boolean;
  className?: string;
}

/** Pill segmented control — the active segment is a white pill that slides. */
export function Segmented<T extends string | number>({
  value,
  onChange,
  options,
  size = 'md',
  full = false,
  iconOnly = false,
  disabled = false,
  className,
}: SegmentedProps<T>) {
  const { wrapRef, ind } = useIndicator(value);
  return (
    <div
      ref={wrapRef}
      role="radiogroup"
      className={clsx('nz-seg', `nz-seg--${size}`, full && 'nz-seg--full', ind && 'is-ready', disabled && 'is-disabled', className)}
    >
      <span className="nz-seg__ind" style={ind ?? undefined} aria-hidden="true" />
      {options.map((o) => {
        const on = o.value === value;
        return (
          <button
            key={String(o.value)}
            type="button"
            role="radio"
            aria-checked={on}
            data-active={on}
            tabIndex={on ? 0 : -1}
            disabled={disabled || o.disabled}
            className={clsx('nz-seg__btn', on && 'is-on', iconOnly && o.icon && 'nz-seg__btn--icon')}
            onClick={() => onChange(o.value)}
            onKeyDown={(e) => arrowNav(e, options, value, onChange)}
            title={iconOnly ? o.label : undefined}
            aria-label={iconOnly ? o.label : undefined}
          >
            {o.icon && <Icon name={o.icon} size={size === 'sm' ? 13 : 15} strokeWidth={1.8} />}
            {!(iconOnly && o.icon) && o.label && <span>{o.label}</span>}
          </button>
        );
      })}
    </div>
  );
}

/* ── Tabs ─────────────────────────────────────────────────────────────── */

export interface TabItem<T extends string | number> {
  value: T;
  label: string;
  icon?: IconName;
  count?: number;
  disabled?: boolean;
}

export interface TabsProps<T extends string | number> {
  value: T;
  onChange: (v: T) => void;
  items: TabItem<T>[];
  variant?: 'pill' | 'underline';
  className?: string;
}

export function Tabs<T extends string | number>({ value, onChange, items, variant = 'pill', className }: TabsProps<T>) {
  const { wrapRef, ind } = useIndicator(variant === 'underline' ? value : null);
  return (
    <div
      ref={variant === 'underline' ? wrapRef : undefined}
      role="tablist"
      className={clsx('nz-tabs', `nz-tabs--${variant}`, ind && 'is-ready', className)}
    >
      {variant === 'underline' && <span className="nz-tabs__ind" style={ind ?? undefined} aria-hidden="true" />}
      {items.map((it) => {
        const on = it.value === value;
        return (
          <button
            key={String(it.value)}
            type="button"
            role="tab"
            aria-selected={on}
            data-active={on}
            tabIndex={on ? 0 : -1}
            disabled={it.disabled}
            className={clsx('nz-tabs__tab', on && 'is-on')}
            onClick={() => onChange(it.value)}
            onKeyDown={(e) => arrowNav(e, items, value, onChange)}
          >
            {it.icon && <Icon name={it.icon} size={14} strokeWidth={1.7} />}
            <span className="nz-tabs__label">{it.label}</span>
            {it.count !== undefined && <span className="nz-tabs__count">{it.count}</span>}
          </button>
        );
      })}
    </div>
  );
}

/* ── Slider ───────────────────────────────────────────────────────────── */

export interface SliderProps {
  value: number;
  onChange: (n: number) => void;
  min: number;
  max: number;
  step?: number;
  suffix?: string;
  disabled?: boolean;
  /** Custom value readout. */
  format?: (n: number) => ReactNode;
  className?: string;
}

export function Slider({ value, onChange, min, max, step = 1, suffix, disabled = false, format, className }: SliderProps) {
  const field = useFieldContext();
  const span = max - min || 1;
  const p = Math.max(0, Math.min(100, ((value - min) / span) * 100));
  return (
    <div className={clsx('nz-slider', disabled && 'is-disabled', className)}>
      <input
        id={field?.id}
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        disabled={disabled}
        onChange={(e) => onChange(Number(e.target.value))}
        style={{ '--pct': `${p}%` } as CSSProperties}
        className="nz-slider__input"
      />
      <span className="nz-slider__value">
        {format ? format(value) : value}
        {suffix && <span>{suffix}</span>}
      </span>
    </div>
  );
}

/* ── ColorSwatches ────────────────────────────────────────────────────── */

export interface ColorSwatchesProps {
  value: string;
  onChange: (hex: string) => void;
  colors: string[];
  /** Hide the hex input. */
  noInput?: boolean;
  className?: string;
}

const HEX = /^#?([0-9a-f]{6})$/i;
const normHex = (v: string) => {
  const m = HEX.exec(v.trim());
  return m ? `#${m[1].toLowerCase()}` : null;
};

export function ColorSwatches({ value, onChange, colors, noInput = false, className }: ColorSwatchesProps) {
  const current = normHex(value ?? '') ?? '';
  const [text, setText] = useState(current.toUpperCase());
  useEffect(() => setText(current.toUpperCase()), [current]);
  const commit = () => {
    const n = normHex(text);
    if (n) {
      if (n !== current) onChange(n);
      setText(n.toUpperCase());
    } else setText(current.toUpperCase());
  };
  return (
    <div className={clsx('nz-swatches', className)} role="radiogroup">
      {colors.map((c) => {
        const n = normHex(c) ?? c;
        const on = n.toLowerCase() === current;
        return (
          <button
            key={c}
            type="button"
            role="radio"
            aria-checked={on}
            aria-label={n.toUpperCase()}
            title={n.toUpperCase()}
            className={clsx('nz-swatch', on && 'is-on')}
            style={{ '--sw': n } as CSSProperties}
            onClick={() => onChange(n)}
          >
            {on && <Icon name="check" size={12} strokeWidth={2.6} />}
          </button>
        );
      })}
      {!noInput && (
        <label className="nz-input nz-input--sm nz-swatches__hex">
          <span className="nz-swatches__preview" style={{ background: normHex(text) ?? current ?? 'transparent' }} />
          <input
            className="nz-input__el"
            value={text}
            maxLength={7}
            spellCheck={false}
            aria-label={t('Hex colour')}
            onChange={(e) => {
              const v = e.target.value.toUpperCase();
              if (!/^#?[0-9A-F]{0,6}$/.test(v)) return;
              setText(v.startsWith('#') || v === '' ? v : `#${v}`);
              const n = normHex(v);
              if (n && n !== current) onChange(n);
            }}
            onBlur={commit}
            onKeyDown={(e) => {
              if (e.key === 'Enter') commit();
            }}
          />
        </label>
      )}
    </div>
  );
}
