/**
 * Menu: "⋯" action menu rendered in a portal popover (keyboard: ↑/↓, Enter, Escape).
 */
import { useEffect, useRef, useState } from 'react';
import type { KeyboardEvent, ReactNode } from 'react';
import clsx from 'clsx';
import { t } from '@/lib/i18n';
import { useEscape } from '@/lib/escape';
import { Icon } from '../icons';
import type { IconName } from '../icons';
import { IconButton } from './Button';
import { Portal, useFloating, useOutsideClick, useUid } from './internal';

export interface MenuItem {
  label: string;
  icon?: IconName;
  onSelect: () => void;
  danger?: boolean;
  disabled?: boolean;
  /** Small grey text on the right (a price, a shortcut…). */
  hint?: string;
}

export interface MenuProps {
  items: MenuItem[];
  /** Custom trigger (defaults to a "⋯" icon button). */
  trigger?: ReactNode;
  align?: 'left' | 'right';
  /** Accessible name of the default trigger. */
  label?: string;
  className?: string;
}

export function Menu({ items, trigger, align = 'right', label, className }: MenuProps) {
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(-1);
  const anchorRef = useRef<HTMLSpanElement>(null);
  const popRef = useRef<HTMLDivElement>(null);
  const id = useUid('nz-menu');
  const { style, placement } = useFloating(open, anchorRef, popRef, {
    side: 'bottom',
    align: align === 'right' ? 'end' : 'start',
    offset: 6,
  });

  const focusAnchor = () => anchorRef.current?.querySelector<HTMLElement>('button, [tabindex]')?.focus();
  const close = (refocus = true) => {
    setOpen(false);
    setActive(-1);
    if (refocus) focusAnchor();
  };
  useEscape(() => close(), open);
  useOutsideClick(open, [anchorRef, popRef], () => close(false));

  useEffect(() => {
    if (open) popRef.current?.focus();
  }, [open]);

  const enabled = (i: number) => !!items[i] && !items[i].disabled;
  const move = (dir: 1 | -1) => {
    if (!items.length) return;
    let i = active;
    for (let n = 0; n < items.length; n++) {
      i = (i + dir + items.length) % items.length;
      if (enabled(i)) {
        setActive(i);
        return;
      }
    }
  };

  const select = (i: number) => {
    const it = items[i];
    if (!it || it.disabled) return;
    close();
    it.onSelect();
  };

  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      move(1);
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      move(-1);
    } else if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      if (active >= 0) select(active);
    } else if (e.key === 'Tab') {
      close(false);
    }
  };

  return (
    <>
      <span
        ref={anchorRef}
        className={clsx('nz-menu-anchor', className)}
        aria-haspopup="menu"
        aria-expanded={open}
        aria-controls={open ? id : undefined}
        onClick={(e) => {
          e.stopPropagation();
          setOpen((o) => !o);
          setActive(-1);
        }}
        onKeyDown={(e) => {
          if (!open && e.key === 'ArrowDown') {
            e.preventDefault();
            setOpen(true);
            setActive(items.findIndex((it) => !it.disabled));
          }
        }}
      >
        {trigger ?? <IconButton icon="more" label={label ?? t('More actions')} active={open} />}
      </span>
      {open && (
        <Portal>
          <div
            ref={popRef}
            id={id}
            role="menu"
            tabIndex={-1}
            className={clsx('nz-pop', 'nz-menu', `nz-pop--${placement}`)}
            style={style}
            onKeyDown={onKeyDown}
            onClick={(e) => e.stopPropagation()}
          >
            {items.map((it, i) => (
              <button
                key={`${it.label}-${i}`}
                type="button"
                role="menuitem"
                disabled={it.disabled}
                tabIndex={-1}
                className={clsx('nz-menu__item', it.danger && 'is-danger', i === active && 'is-active')}
                onMouseMove={() => !it.disabled && active !== i && setActive(i)}
                onMouseLeave={() => setActive(-1)}
                onClick={() => select(i)}
              >
                {it.icon ? <Icon name={it.icon} size={15} strokeWidth={1.7} /> : <span className="nz-menu__noicon" />}
                <span className="nz-menu__label">{it.label}</span>
                {it.hint && <span className="nz-menu__hint">{it.hint}</span>}
              </button>
            ))}
          </div>
        </Portal>
      )}
    </>
  );
}
