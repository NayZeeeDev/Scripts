/**
 * Form fields: Field (label / hint / error wrapper), Input, NumberInput, SearchInput.
 * All inputs are controlled. Inside a <Field>, inputs pick up the label id and error state.
 */
import { createContext, forwardRef, useContext, useEffect, useRef, useState } from 'react';
import type { KeyboardEvent, ReactNode } from 'react';
import clsx from 'clsx';
import { t } from '@/lib/i18n';
import { Icon } from '../icons';
import type { IconName } from '../icons';
import { Kbd } from './Button';
import { useUid } from './internal';

interface FieldCtx {
  id: string;
  invalid: boolean;
  describedBy?: string;
}

export const FieldContext = createContext<FieldCtx | null>(null);
export const useFieldContext = () => useContext(FieldContext);

/* ── Field ────────────────────────────────────────────────────────────── */

export interface FieldProps {
  label?: ReactNode;
  hint?: ReactNode;
  error?: ReactNode;
  required?: boolean;
  /** Extra content on the right of the label row (e.g. an InfoDot or a small action). */
  aside?: ReactNode;
  className?: string;
  children: ReactNode;
}

export function Field({ label, hint, error, required, aside, className, children }: FieldProps) {
  const id = useUid('nz-field');
  const msgId = `${id}-msg`;
  const invalid = !!error;
  return (
    <FieldContext.Provider value={{ id, invalid, describedBy: error || hint ? msgId : undefined }}>
      <div className={clsx('nz-field', invalid && 'nz-field--error', className)}>
        {(label || aside) && (
          <div className="nz-field__top">
            {label && (
              <label className="nz-field__label" htmlFor={id}>
                {label}
                {required && <span className="nz-field__req" aria-hidden="true">*</span>}
              </label>
            )}
            {aside && <span className="nz-field__aside">{aside}</span>}
          </div>
        )}
        {children}
        {error ? (
          <span className="nz-field__error" id={msgId} role="alert">
            <Icon name="warning" size={12} strokeWidth={1.8} />
            {error}
          </span>
        ) : hint ? (
          <span className="nz-field__hint" id={msgId}>
            {hint}
          </span>
        ) : null}
      </div>
    </FieldContext.Provider>
  );
}

/* ── Input ────────────────────────────────────────────────────────────── */

export interface InputProps {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  icon?: IconName;
  mono?: boolean;
  suffix?: ReactNode;
  maxLength?: number;
  disabled?: boolean;
  autoFocus?: boolean;
  onEnter?: () => void;
  onBlur?: () => void;
  type?: 'text' | 'password' | 'email' | 'url' | 'tel';
  /** Upper-case what the user types (plates). */
  uppercase?: boolean;
  size?: 'sm' | 'md';
  id?: string;
  className?: string;
}

export const Input = forwardRef<HTMLInputElement, InputProps>(function Input(
  {
    value,
    onChange,
    placeholder,
    icon,
    mono = false,
    suffix,
    maxLength,
    disabled = false,
    autoFocus,
    onEnter,
    onBlur,
    type = 'text',
    uppercase = false,
    size = 'md',
    id,
    className,
  },
  ref,
) {
  const field = useFieldContext();
  const onKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter' && onEnter) {
      e.preventDefault();
      onEnter();
    }
  };
  return (
    <div
      className={clsx(
        'nz-input',
        `nz-input--${size}`,
        mono && 'nz-input--mono',
        disabled && 'is-disabled',
        field?.invalid && 'is-invalid',
        className,
      )}
    >
      {icon && <Icon name={icon} size={14} strokeWidth={1.7} className="nz-input__icon" />}
      <input
        ref={ref}
        id={id ?? field?.id}
        type={type}
        value={value ?? ''}
        placeholder={placeholder}
        maxLength={maxLength}
        disabled={disabled}
        autoFocus={autoFocus}
        spellCheck={false}
        autoComplete="off"
        aria-invalid={field?.invalid || undefined}
        aria-describedby={field?.describedBy}
        onChange={(e) => onChange(uppercase ? e.target.value.toUpperCase() : e.target.value)}
        onKeyDown={onKeyDown}
        onBlur={onBlur}
        className={clsx('nz-input__el', uppercase && 'nz-input__el--upper')}
      />
      {maxLength !== undefined && maxLength > 0 && !suffix && value && value.length > maxLength * 0.75 && (
        <span className="nz-input__count">
          {value.length}/{maxLength}
        </span>
      )}
      {suffix !== undefined && suffix !== null && <span className="nz-input__suffix">{suffix}</span>}
    </div>
  );
});

/* ── NumberInput ──────────────────────────────────────────────────────── */

export interface NumberInputProps {
  value: number;
  onChange: (n: number) => void;
  min?: number;
  max?: number;
  step?: number;
  suffix?: ReactNode;
  /** Shown before the value, e.g. the currency symbol. */
  prefix?: ReactNode;
  disabled?: boolean;
  onEnter?: () => void;
  size?: 'sm' | 'md';
  id?: string;
  className?: string;
}

const decimals = (n: number) => {
  const s = String(n);
  const i = s.indexOf('.');
  return i < 0 ? 0 : s.length - i - 1;
};

export function NumberInput({
  value,
  onChange,
  min,
  max,
  step = 1,
  suffix,
  prefix,
  disabled = false,
  onEnter,
  size = 'md',
  id,
  className,
}: NumberInputProps) {
  const field = useFieldContext();
  const [text, setText] = useState(() => (Number.isFinite(value) ? String(value) : ''));
  const focused = useRef(false);
  const dp = decimals(step);
  // Enter runs the parent's handler only after the committed (clamped / rounded) value has
  // re-rendered the parent, so the handler reads that value instead of a stale closure.
  const onEnterRef = useRef(onEnter);
  onEnterRef.current = onEnter;
  const enterTimer = useRef<number>();

  useEffect(() => {
    if (!focused.current) setText(Number.isFinite(value) ? String(value) : '');
  }, [value]);
  useEffect(() => () => window.clearTimeout(enterTimer.current), []);

  const clampN = (n: number) => {
    let v = n;
    if (min !== undefined) v = Math.max(min, v);
    if (max !== undefined) v = Math.min(max, v);
    return Number(v.toFixed(dp));
  };

  const commit = (raw: string) => {
    const n = parseFloat(raw.replace(',', '.'));
    if (!Number.isFinite(n)) {
      setText(Number.isFinite(value) ? String(value) : '');
      return;
    }
    const v = clampN(n);
    setText(String(v));
    if (v !== value) onChange(v);
  };

  const bump = (dir: 1 | -1, mult = 1) => {
    const base = Number.isFinite(value) ? value : min ?? 0;
    const v = clampN(base + dir * step * mult);
    setText(String(v));
    if (v !== value) onChange(v);
  };

  const onKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'ArrowUp') {
      e.preventDefault();
      bump(1, e.shiftKey ? 10 : 1);
    } else if (e.key === 'ArrowDown') {
      e.preventDefault();
      bump(-1, e.shiftKey ? 10 : 1);
    } else if (e.key === 'Enter') {
      commit(text);
      if (onEnter) {
        window.clearTimeout(enterTimer.current);
        enterTimer.current = window.setTimeout(() => onEnterRef.current?.(), 0);
      }
    }
  };

  const atMin = min !== undefined && value <= min;
  const atMax = max !== undefined && value >= max;

  return (
    <div
      className={clsx(
        'nz-input',
        'nz-num',
        `nz-input--${size}`,
        disabled && 'is-disabled',
        field?.invalid && 'is-invalid',
        className,
      )}
    >
      {prefix !== undefined && <span className="nz-input__prefix">{prefix}</span>}
      <input
        id={id ?? field?.id}
        type="text"
        inputMode="decimal"
        value={text}
        disabled={disabled}
        spellCheck={false}
        autoComplete="off"
        aria-invalid={field?.invalid || undefined}
        aria-describedby={field?.describedBy}
        onFocus={() => {
          focused.current = true;
        }}
        onBlur={() => {
          focused.current = false;
          commit(text);
        }}
        onChange={(e) => {
          const raw = e.target.value;
          if (!/^-?\d*[.,]?\d*$/.test(raw)) return;
          setText(raw);
          const n = parseFloat(raw.replace(',', '.'));
          if (Number.isFinite(n) && (min === undefined || n >= min) && (max === undefined || n <= max)) onChange(n);
        }}
        onKeyDown={onKeyDown}
        className="nz-input__el"
      />
      {suffix !== undefined && suffix !== null && <span className="nz-input__suffix">{suffix}</span>}
      <span className="nz-num__steps">
        <button
          type="button"
          tabIndex={-1}
          className="nz-num__step"
          disabled={disabled || atMin}
          aria-label={t('Decrease')}
          onClick={() => bump(-1)}
        >
          <Icon name="minus" size={12} strokeWidth={2} />
        </button>
        <button
          type="button"
          tabIndex={-1}
          className="nz-num__step"
          disabled={disabled || atMax}
          aria-label={t('Increase')}
          onClick={() => bump(1)}
        >
          <Icon name="plus" size={12} strokeWidth={2} />
        </button>
      </span>
    </div>
  );
}

/* ── SearchInput ──────────────────────────────────────────────────────── */

export interface SearchInputProps {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  onEnter?: () => void;
  /** Keycap shown while the field is empty, e.g. 'Enter'. */
  shortcut?: string;
  autoFocus?: boolean;
  disabled?: boolean;
  /** Shows a spinner instead of the search glyph. */
  loading?: boolean;
  size?: 'sm' | 'md';
  className?: string;
}

export function SearchInput({
  value,
  onChange,
  placeholder,
  onEnter,
  shortcut,
  autoFocus,
  disabled,
  loading,
  size = 'md',
  className,
}: SearchInputProps) {
  const ref = useRef<HTMLInputElement>(null);
  const field = useFieldContext();
  const onKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter' && onEnter) {
      e.preventDefault();
      onEnter();
    } else if (e.key === 'Escape' && value) {
      // First Escape clears the query; the next one reaches the window/app.
      e.preventDefault();
      e.stopPropagation();
      e.nativeEvent.stopImmediatePropagation();
      onChange('');
    }
  };
  return (
    <div
      className={clsx('nz-input', 'nz-search', `nz-input--${size}`, disabled && 'is-disabled', className)}
      onMouseDown={(e) => {
        if (e.target !== ref.current) {
          e.preventDefault();
          ref.current?.focus();
        }
      }}
    >
      <span className="nz-input__icon">
        {loading ? (
          <svg className="nz-spinner" width={14} height={14} viewBox="0 0 24 24" fill="none" aria-hidden="true">
            <circle cx="12" cy="12" r="9" stroke="currentColor" strokeOpacity=".2" strokeWidth="2.6" />
            <path d="M21 12a9 9 0 0 0-9-9" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" />
          </svg>
        ) : (
          <Icon name="search" size={14} strokeWidth={1.8} />
        )}
      </span>
      <input
        ref={ref}
        id={field?.id}
        type="text"
        value={value ?? ''}
        placeholder={placeholder ?? t('Search')}
        autoFocus={autoFocus}
        disabled={disabled}
        spellCheck={false}
        autoComplete="off"
        onChange={(e) => onChange(e.target.value)}
        onKeyDown={onKeyDown}
        className="nz-input__el"
      />
      {value ? (
        <button
          type="button"
          className="nz-search__clear"
          aria-label={t('Clear search')}
          onClick={() => {
            onChange('');
            ref.current?.focus();
          }}
        >
          <Icon name="close" size={12} strokeWidth={2} />
        </button>
      ) : shortcut ? (
        <Kbd size="sm" className="nz-search__key">
          {shortcut}
        </Kbd>
      ) : null}
    </div>
  );
}
