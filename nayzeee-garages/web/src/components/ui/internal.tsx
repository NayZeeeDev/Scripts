/**
 * UI kit internals: portal target, anchored floating positioning (flip + clamp),
 * outside-click detection and mount/unmount presence for exit animations.
 * Not exported from the barrel — app code uses the components only.
 */
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import type { CSSProperties, ReactNode, RefObject } from 'react';
import { createPortal } from 'react-dom';

/** Overlays render into .nz-root (stacks above every window); body as a fallback. */
export function portalRoot(): HTMLElement {
  return (document.querySelector('.nz-root') as HTMLElement | null) ?? document.body;
}

export function Portal({ children }: { children: ReactNode }) {
  return createPortal(children, portalRoot());
}

export const clamp = (v: number, min: number, max: number) => Math.max(min, Math.min(max, v));

/** Keeps a component mounted for `ms` after `open` turns false so it can animate out. */
export function usePresence(open: boolean, ms = 160) {
  const [mounted, setMounted] = useState(open);
  useEffect(() => {
    if (open) {
      setMounted(true);
      return;
    }
    const id = window.setTimeout(() => setMounted(false), ms);
    return () => window.clearTimeout(id);
  }, [open, ms]);
  return { mounted: open || mounted, closing: !open && mounted };
}

export type Side = 'top' | 'bottom' | 'left' | 'right';

interface FloatingOptions {
  /** Preferred side; flips to the opposite one when there is no room. */
  side?: Side;
  /** Horizontal alignment for top/bottom placement. */
  align?: 'start' | 'end' | 'center';
  offset?: number;
  /** Popover is at least as wide as the anchor. */
  matchWidth?: boolean;
  /** Cap for the popover height (it also never exceeds the free space). */
  maxHeight?: number;
}

// Measured off-screen-transparent (not visibility:hidden) so autoFocus inside the popover works.
const HIDDEN: CSSProperties = { position: 'fixed', top: 0, left: 0, opacity: 0 };

/**
 * Positions `floatRef` (position: fixed, portal) next to `anchorRef`. Recomputes on scroll
 * (any scroll container), resize and when the floating element changes size.
 */
export function useFloating(
  open: boolean,
  anchorRef: RefObject<HTMLElement>,
  floatRef: RefObject<HTMLElement>,
  opts: FloatingOptions = {},
) {
  const { side = 'bottom', align = 'start', offset = 6, matchWidth = false, maxHeight } = opts;
  const [style, setStyle] = useState<CSSProperties>(HIDDEN);
  const [placed, setPlaced] = useState<Side>(side);

  const update = useCallback(() => {
    const a = anchorRef.current;
    const f = floatRef.current;
    if (!a || !f) return;
    const r = a.getBoundingClientRect();
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    const m = 8;
    if (matchWidth) f.style.minWidth = `${Math.round(r.width)}px`;
    f.style.maxHeight = '';
    const fw = f.offsetWidth;
    let fh = f.offsetHeight;
    let top = 0;
    let left = 0;
    let final: Side = side;
    let mh: number | undefined;

    if (side === 'top' || side === 'bottom') {
      const below = vh - r.bottom - offset - m;
      const above = r.top - offset - m;
      const want = maxHeight ? Math.min(fh, maxHeight) : fh;
      if (side === 'bottom') final = want <= below || below >= above ? 'bottom' : 'top';
      else final = want <= above || above >= below ? 'top' : 'bottom';
      const room = final === 'bottom' ? below : above;
      const cap = Math.max(120, Math.min(maxHeight ?? Infinity, room));
      if (fh > cap) {
        mh = cap;
        fh = cap;
      }
      top = final === 'bottom' ? r.bottom + offset : r.top - offset - fh;
      if (align === 'end') left = r.right - fw;
      else if (align === 'center') left = r.left + r.width / 2 - fw / 2;
      else left = r.left;
      left = clamp(left, m, Math.max(m, vw - fw - m));
      top = clamp(top, m, Math.max(m, vh - fh - m));
    } else {
      const rightRoom = vw - r.right - offset - m;
      const leftRoom = r.left - offset - m;
      if (side === 'right') final = fw <= rightRoom || rightRoom >= leftRoom ? 'right' : 'left';
      else final = fw <= leftRoom || leftRoom >= rightRoom ? 'left' : 'right';
      left = final === 'right' ? r.right + offset : r.left - offset - fw;
      top = clamp(r.top + r.height / 2 - fh / 2, m, Math.max(m, vh - fh - m));
      left = clamp(left, m, Math.max(m, vw - fw - m));
    }

    // max-height is driven on the DOM node directly (it is reset above to measure).
    f.style.maxHeight = mh ? `${Math.floor(mh)}px` : '';
    setPlaced(final);
    setStyle({
      position: 'fixed',
      top: Math.round(top),
      left: Math.round(left),
      minWidth: matchWidth ? Math.round(r.width) : undefined,
    });
  }, [anchorRef, floatRef, side, align, offset, matchWidth, maxHeight]);

  useLayoutEffect(() => {
    if (!open) {
      setStyle(HIDDEN);
      return;
    }
    update();
    let raf = 0;
    const schedule = () => {
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(update);
    };
    window.addEventListener('scroll', schedule, true);
    window.addEventListener('resize', schedule);
    let ro: ResizeObserver | null = null;
    if (typeof ResizeObserver !== 'undefined') {
      ro = new ResizeObserver(schedule);
      if (floatRef.current) ro.observe(floatRef.current);
      if (anchorRef.current) ro.observe(anchorRef.current);
    }
    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener('scroll', schedule, true);
      window.removeEventListener('resize', schedule);
      ro?.disconnect();
    };
  }, [open, update, anchorRef, floatRef]);

  return { style, placement: placed, update };
}

/** Calls `onOutside` on a mousedown outside every given element while active. */
export function useOutsideClick(active: boolean, refs: RefObject<HTMLElement>[], onOutside: () => void) {
  const cb = useRef(onOutside);
  cb.current = onOutside;
  useEffect(() => {
    if (!active) return;
    const onDown = (e: MouseEvent) => {
      const target = e.target as Node | null;
      if (!target) return;
      if (refs.some((r) => r.current && r.current.contains(target))) return;
      cb.current();
    };
    document.addEventListener('mousedown', onDown, true);
    return () => document.removeEventListener('mousedown', onDown, true);
    // refs are stable ref objects
  }, [active]);
}

/** Scrolls `item` into view inside `list` without touching any outer scroll container. */
export function scrollIntoList(list: HTMLElement | null, item: HTMLElement | null) {
  if (!list || !item) return;
  const top = item.offsetTop;
  const bottom = top + item.offsetHeight;
  if (top < list.scrollTop + 4) list.scrollTop = Math.max(0, top - 4);
  else if (bottom > list.scrollTop + list.clientHeight - 4) list.scrollTop = bottom - list.clientHeight + 4;
}

let idSeq = 0;
/** Stable unique id (React 18 useId would do, but this keeps ids readable: nz-12). */
export function useUid(prefix = 'nz') {
  const ref = useRef<string>();
  if (!ref.current) ref.current = `${prefix}-${++idSeq}`;
  return ref.current;
}

/** Human key labels for keycaps. */
const KEY_LABELS: Record<string, string> = {
  arrowup: '↑',
  arrowdown: '↓',
  arrowleft: '←',
  arrowright: '→',
  up: '↑',
  down: '↓',
  left: '←',
  right: '→',
  escape: 'Esc',
  esc: 'Esc',
  return: 'Enter',
  space: 'Space',
  spacebar: 'Space',
  shift: 'Shift',
  control: 'Ctrl',
  ctrl: 'Ctrl',
  backspace: '⌫',
  delete: 'Del',
  tab: 'Tab',
};

export function keyLabel(key: string): string {
  const k = key.trim();
  const mapped = KEY_LABELS[k.toLowerCase()];
  if (mapped) return mapped;
  return k.length === 1 ? k.toUpperCase() : k;
}
