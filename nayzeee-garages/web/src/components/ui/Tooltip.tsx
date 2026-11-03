/**
 * Tooltip (portal, hover/focus, flips when there is no room) and InfoDot ((i) + tooltip).
 */
import { useEffect, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import clsx from 'clsx';
import { Icon } from '../icons';
import { Portal, useFloating, useUid } from './internal';
import type { Side } from './internal';

export interface TooltipProps {
  content: ReactNode;
  side?: Side;
  /** Show delay in ms. */
  delay?: number;
  disabled?: boolean;
  className?: string;
  children: ReactNode;
}

export function Tooltip({ content, side = 'top', delay = 280, disabled, className, children }: TooltipProps) {
  const [open, setOpen] = useState(false);
  const anchorRef = useRef<HTMLSpanElement>(null);
  const tipRef = useRef<HTMLDivElement>(null);
  const timer = useRef<number>();
  const id = useUid('nz-tip');
  const { style, placement } = useFloating(open, anchorRef, tipRef, {
    side,
    align: 'center',
    offset: 8,
  });

  const show = () => {
    if (disabled || content === null || content === undefined || content === '') return;
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setOpen(true), delay);
  };
  const hide = () => {
    window.clearTimeout(timer.current);
    setOpen(false);
  };

  useEffect(() => () => window.clearTimeout(timer.current), []);
  useEffect(() => {
    if (disabled) hide();
  }, [disabled]);

  return (
    <span
      ref={anchorRef}
      className={clsx('nz-tip-anchor', className)}
      onMouseEnter={show}
      onMouseLeave={hide}
      onFocus={show}
      onBlur={hide}
      onMouseDown={hide}
      aria-describedby={open ? id : undefined}
    >
      {children}
      {open && (
        <Portal>
          <div ref={tipRef} id={id} role="tooltip" className={`nz-tip nz-tip--${placement}`} style={style}>
            {content}
          </div>
        </Portal>
      )}
    </span>
  );
}

export interface InfoDotProps {
  text: ReactNode;
  side?: Side;
  className?: string;
}

/** Small (i) affordance that explains a setting on hover / focus. */
export function InfoDot({ text, side = 'top', className }: InfoDotProps) {
  return (
    <Tooltip content={<span className="nz-tip__text">{text}</span>} side={side} delay={120}>
      <span className={clsx('nz-infodot', className)} tabIndex={0} role="img" aria-label={typeof text === 'string' ? text : undefined}>
        <Icon name="info" size={13} strokeWidth={1.7} />
      </span>
    </Tooltip>
  );
}
