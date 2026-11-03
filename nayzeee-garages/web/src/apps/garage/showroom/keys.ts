/**
 * Showroom keyboard: ↑/↓ move the selection, Enter drives, F favourites, R renames,
 * "/" focuses the search. Escape stays with the escape stack (modal → app).
 * Ignored while typing (except ↑/↓ from the search box), inside popovers / modals, with
 * modifier keys, and Enter on a focused button keeps its native click.
 */
import { useEffect, useRef } from 'react';

export interface ShowroomKeys {
  move: (dir: 1 | -1) => void;
  enter?: () => void;
  favourite?: () => void;
  rename?: () => void;
  focusSearch?: () => void;
}

const isTyping = (el: HTMLElement | null) =>
  !!el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable);

export function useShowroomKeys(active: boolean, keys: ShowroomKeys) {
  const ref = useRef(keys);
  ref.current = keys;
  useEffect(() => {
    if (!active) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.defaultPrevented || e.ctrlKey || e.metaKey || e.altKey) return;
      const target = e.target instanceof HTMLElement ? e.target : null;
      if (target?.closest('.nz-pop, .nz-modal, .nz-modal-overlay')) return;
      const typing = isTyping(target);
      const k = ref.current;
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        if (typing && !target?.closest('.nz-garage__search')) return;
        e.preventDefault();
        k.move(e.key === 'ArrowDown' ? 1 : -1);
        return;
      }
      if (typing) return;
      if (e.key === 'Enter') {
        if (target && target.closest('button, a, [role="button"], [role="radio"], [role="tab"]')) return;
        if (!k.enter) return;
        e.preventDefault();
        k.enter();
        return;
      }
      if (e.repeat) return;
      const key = e.key.toLowerCase();
      if (key === '/' && k.focusSearch) {
        e.preventDefault();
        k.focusSearch();
      } else if (key === 'f' && k.favourite) {
        e.preventDefault();
        k.favourite();
      } else if (key === 'r' && k.rename) {
        e.preventDefault();
        k.rename();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [active]);
}
