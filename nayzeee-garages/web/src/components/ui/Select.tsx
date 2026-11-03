/**
 * Custom dropdowns (no native <select>): Select and MultiSelect.
 * The list renders in a portal (never clipped by scroll containers), opens below the
 * trigger and flips above when there is no room. Keyboard: ↑/↓, Home/End, Enter, Escape,
 * type-ahead; optional search field.
 */
import { useEffect, useMemo, useRef, useState } from 'react';
import type { KeyboardEvent, ReactNode, RefObject } from 'react';
import clsx from 'clsx';
import { t } from '@/lib/i18n';
import { useEscape } from '@/lib/escape';
import { Icon } from '../icons';
import type { IconName } from '../icons';
import { useFieldContext } from './Field';
import { Portal, scrollIntoList, useFloating, useOutsideClick, useUid } from './internal';

export interface SelectOption<T extends string | number> {
  value: T;
  label: string;
  hint?: string;
  icon?: IconName;
  disabled?: boolean;
}

interface ListState<T extends string | number> {
  open: boolean;
  setOpen: (v: boolean) => void;
  query: string;
  setQuery: (v: string) => void;
  active: number;
  setActive: (i: number) => void;
  filtered: SelectOption<T>[];
}

function useList<T extends string | number>(options: SelectOption<T>[], searchable: boolean): ListState<T> {
  const [open, setOpenRaw] = useState(false);
  const [query, setQuery] = useState('');
  const [active, setActive] = useState(-1);
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!searchable || !q) return options;
    return options.filter(
      (o) => o.label.toLowerCase().includes(q) || (o.hint ?? '').toLowerCase().includes(q) || String(o.value).toLowerCase().includes(q),
    );
  }, [options, query, searchable]);
  const setOpen = (v: boolean) => {
    setOpenRaw(v);
    if (!v) setQuery('');
  };
  return { open, setOpen, query, setQuery, active, setActive, filtered };
}

const nextEnabled = <T extends string | number>(list: SelectOption<T>[], from: number, dir: 1 | -1) => {
  if (!list.length) return -1;
  let i = from;
  for (let n = 0; n < list.length; n++) {
    i = (i + dir + list.length) % list.length;
    if (!list[i].disabled) return i;
  }
  return -1;
};

/* ── shared popover list ──────────────────────────────────────────────── */

interface PopListProps<T extends string | number> {
  id: string;
  anchorRef: RefObject<HTMLElement>;
  state: ListState<T>;
  isSelected: (v: T) => boolean;
  onPick: (o: SelectOption<T>) => void;
  onKeyDown: (e: KeyboardEvent<HTMLElement>) => void;
  searchable: boolean;
  multi?: boolean;
  footer?: ReactNode;
}

function PopList<T extends string | number>({
  id,
  anchorRef,
  state,
  isSelected,
  onPick,
  onKeyDown,
  searchable,
  multi = false,
  footer,
}: PopListProps<T>) {
  const popRef = useRef<HTMLDivElement>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const { style, placement } = useFloating(state.open, anchorRef, popRef, {
    side: 'bottom',
    matchWidth: true,
    maxHeight: 320,
  });

  useEffect(() => {
    if (!state.open || state.active < 0) return;
    const el = listRef.current?.querySelector<HTMLElement>(`[data-index="${state.active}"]`);
    scrollIntoList(listRef.current, el ?? null);
  }, [state.active, state.open]);

  useOutsideClick(state.open, [popRef, anchorRef], () => state.setOpen(false));

  if (!state.open) return null;
  return (
    <Portal>
      <div
        ref={popRef}
        className={clsx('nz-pop', 'nz-select__pop', `nz-pop--${placement}`)}
        style={style}
        onMouseDown={(e) => {
          if ((e.target as HTMLElement).tagName !== 'INPUT') e.preventDefault();
        }}
      >
        {searchable && (
          <div className="nz-select__search">
            <Icon name="search" size={13} strokeWidth={1.8} />
            <input
              autoFocus
              value={state.query}
              placeholder={t('Search')}
              spellCheck={false}
              autoComplete="off"
              onChange={(e) => {
                state.setQuery(e.target.value);
                state.setActive(0);
              }}
              onKeyDown={onKeyDown}
              aria-controls={id}
              aria-activedescendant={state.active >= 0 ? `${id}-${state.active}` : undefined}
            />
          </div>
        )}
        <div ref={listRef} id={id} role="listbox" aria-multiselectable={multi || undefined} className="nz-select__list">
          {state.filtered.length === 0 && <div className="nz-select__empty">{t('No results')}</div>}
          {state.filtered.map((o, i) => {
            const selected = isSelected(o.value);
            return (
              <div
                key={String(o.value)}
                id={`${id}-${i}`}
                data-index={i}
                role="option"
                aria-selected={selected}
                aria-disabled={o.disabled || undefined}
                className={clsx(
                  'nz-select__opt',
                  i === state.active && 'is-active',
                  selected && 'is-selected',
                  o.disabled && 'is-disabled',
                )}
                onMouseMove={() => {
                  if (!o.disabled && state.active !== i) state.setActive(i);
                }}
                onClick={() => {
                  if (!o.disabled) onPick(o);
                }}
              >
                {multi && (
                  <span className={clsx('nz-check', selected && 'is-on')}>
                    <Icon name="check" size={11} strokeWidth={2.6} />
                  </span>
                )}
                {o.icon && <Icon name={o.icon} size={14} strokeWidth={1.7} className="nz-select__opt-icon" />}
                <span className="nz-select__opt-text">
                  <span className="nz-select__opt-label">{o.label}</span>
                  {o.hint && <span className="nz-select__opt-hint">{o.hint}</span>}
                </span>
                {!multi && selected && <Icon name="check" size={14} strokeWidth={2} className="nz-select__tick" />}
              </div>
            );
          })}
        </div>
        {footer}
      </div>
    </Portal>
  );
}

/* ── key handling shared by both ──────────────────────────────────────── */

function useListKeys<T extends string | number>(
  state: ListState<T>,
  pick: (o: SelectOption<T>) => void,
  openAt: () => number,
) {
  const typeahead = useRef({ text: '', at: 0 });
  return (e: KeyboardEvent<HTMLElement>) => {
    const list = state.filtered;
    if (!state.open) {
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp' || e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        state.setOpen(true);
        state.setActive(openAt());
      }
      return;
    }
    switch (e.key) {
      case 'ArrowDown':
        e.preventDefault();
        state.setActive(nextEnabled(list, state.active, 1));
        break;
      case 'ArrowUp':
        e.preventDefault();
        state.setActive(nextEnabled(list, state.active < 0 ? 0 : state.active, -1));
        break;
      case 'Home':
        e.preventDefault();
        state.setActive(nextEnabled(list, -1, 1));
        break;
      case 'End':
        e.preventDefault();
        state.setActive(nextEnabled(list, 0, -1));
        break;
      case 'Enter': {
        e.preventDefault();
        const o = list[state.active];
        if (o && !o.disabled) pick(o);
        break;
      }
      case 'Tab':
        state.setOpen(false);
        break;
      case ' ':
        if ((e.target as HTMLElement).tagName !== 'INPUT') {
          e.preventDefault();
          const o = list[state.active];
          if (o && !o.disabled) pick(o);
        }
        break;
      default:
        if (e.key.length === 1 && (e.target as HTMLElement).tagName !== 'INPUT') {
          const now = Date.now();
          const ta = typeahead.current;
          ta.text = now - ta.at > 700 ? e.key.toLowerCase() : ta.text + e.key.toLowerCase();
          ta.at = now;
          const i = list.findIndex((o) => !o.disabled && o.label.toLowerCase().startsWith(ta.text));
          if (i >= 0) state.setActive(i);
        }
    }
  };
}

/* ── Select ───────────────────────────────────────────────────────────── */

export interface SelectProps<T extends string | number> {
  value: T | null;
  onChange: (v: T) => void;
  options: SelectOption<T>[];
  placeholder?: string;
  icon?: IconName;
  disabled?: boolean;
  size?: 'sm' | 'md';
  /** Adds a filter field at the top of the list (auto when there are more than 10 options). */
  searchable?: boolean;
  id?: string;
  className?: string;
}

export function Select<T extends string | number>({
  value,
  onChange,
  options,
  placeholder,
  icon,
  disabled = false,
  size = 'md',
  searchable,
  id,
  className,
}: SelectProps<T>) {
  const field = useFieldContext();
  const listId = useUid('nz-list');
  const triggerRef = useRef<HTMLButtonElement>(null);
  const canSearch = searchable ?? options.length > 10;
  const state = useList(options, canSearch);
  const selected = options.find((o) => o.value === value) ?? null;

  useEscape(() => {
    state.setOpen(false);
    triggerRef.current?.focus();
  }, state.open);

  const pick = (o: SelectOption<T>) => {
    state.setOpen(false);
    if (o.value !== value) onChange(o.value);
    triggerRef.current?.focus();
  };
  const onKeyDown = useListKeys(state, pick, () => {
    const i = options.findIndex((o) => o.value === value);
    return i >= 0 ? i : nextEnabled(options, -1, 1);
  });

  return (
    <>
      <button
        ref={triggerRef}
        id={id ?? field?.id}
        type="button"
        disabled={disabled}
        aria-haspopup="listbox"
        aria-expanded={state.open}
        aria-controls={state.open ? listId : undefined}
        aria-invalid={field?.invalid || undefined}
        className={clsx(
          'nz-select',
          `nz-select--${size}`,
          state.open && 'is-open',
          field?.invalid && 'is-invalid',
          !selected && 'is-empty',
          className,
        )}
        onClick={() => {
          if (state.open) state.setOpen(false);
          else {
            state.setOpen(true);
            const i = state.filtered.findIndex((o) => o.value === value);
            state.setActive(i >= 0 ? i : nextEnabled(options, -1, 1));
          }
        }}
        onKeyDown={onKeyDown}
      >
        {(selected?.icon ?? icon) && (
          <Icon name={(selected?.icon ?? icon) as IconName} size={14} strokeWidth={1.7} className="nz-select__icon" />
        )}
        <span className="nz-select__value">{selected ? selected.label : placeholder ?? t('Select…')}</span>
        <Icon name="chevronDown" size={14} strokeWidth={1.8} className="nz-select__chev" />
      </button>
      <PopList
        id={listId}
        anchorRef={triggerRef}
        state={state}
        isSelected={(v) => v === value}
        onPick={pick}
        onKeyDown={onKeyDown}
        searchable={canSearch}
      />
    </>
  );
}

/* ── MultiSelect ──────────────────────────────────────────────────────── */

export interface MultiSelectProps<T extends string | number> {
  value: T[];
  onChange: (v: T[]) => void;
  options: SelectOption<T>[];
  placeholder?: string;
  icon?: IconName;
  disabled?: boolean;
  size?: 'sm' | 'md';
  searchable?: boolean;
  /** How many selected labels to show before collapsing to "+N". */
  maxTags?: number;
  id?: string;
  className?: string;
}

export function MultiSelect<T extends string | number>({
  value,
  onChange,
  options,
  placeholder,
  icon,
  disabled = false,
  size = 'md',
  searchable,
  maxTags = 3,
  id,
  className,
}: MultiSelectProps<T>) {
  const field = useFieldContext();
  const listId = useUid('nz-list');
  const triggerRef = useRef<HTMLButtonElement>(null);
  const canSearch = searchable ?? options.length > 8;
  const state = useList(options, canSearch);
  const values = value ?? [];
  const selected = options.filter((o) => values.includes(o.value));

  useEscape(() => {
    state.setOpen(false);
    triggerRef.current?.focus();
  }, state.open);

  const toggle = (o: SelectOption<T>) => {
    if (values.includes(o.value)) onChange(values.filter((v) => v !== o.value));
    else onChange([...values, o.value]);
  };
  const onKeyDown = useListKeys(state, toggle, () => nextEnabled(options, -1, 1));
  const shown = selected.slice(0, maxTags);
  const more = selected.length - shown.length;

  const footer =
    options.length > 3 ? (
      <div className="nz-select__foot">
        <span>{t('{count} selected', { count: selected.length })}</span>
        <span className="nz-select__foot-actions">
          <button type="button" onClick={() => onChange(options.filter((o) => !o.disabled).map((o) => o.value))}>
            {t('All')}
          </button>
          <button type="button" onClick={() => onChange([])} disabled={!values.length}>
            {t('None')}
          </button>
        </span>
      </div>
    ) : null;

  return (
    <>
      <button
        ref={triggerRef}
        id={id ?? field?.id}
        type="button"
        disabled={disabled}
        aria-haspopup="listbox"
        aria-expanded={state.open}
        aria-controls={state.open ? listId : undefined}
        className={clsx(
          'nz-select',
          'nz-select--multi',
          `nz-select--${size}`,
          state.open && 'is-open',
          field?.invalid && 'is-invalid',
          !selected.length && 'is-empty',
          className,
        )}
        onClick={() => {
          state.setOpen(!state.open);
          if (!state.open) state.setActive(nextEnabled(options, -1, 1));
        }}
        onKeyDown={onKeyDown}
      >
        {icon && <Icon name={icon} size={14} strokeWidth={1.7} className="nz-select__icon" />}
        <span className="nz-select__value nz-select__tags">
          {selected.length === 0 && <span className="nz-select__placeholder">{placeholder ?? t('Select…')}</span>}
          {shown.map((o) => (
            <span key={String(o.value)} className="nz-select__tag">
              {o.label}
            </span>
          ))}
          {more > 0 && <span className="nz-select__tag nz-select__tag--more">+{more}</span>}
        </span>
        <Icon name="chevronDown" size={14} strokeWidth={1.8} className="nz-select__chev" />
      </button>
      <PopList
        id={listId}
        anchorRef={triggerRef}
        state={state}
        isSelected={(v) => values.includes(v)}
        onPick={toggle}
        onKeyDown={onKeyDown}
        searchable={canSearch}
        multi
        footer={footer}
      />
    </>
  );
}
