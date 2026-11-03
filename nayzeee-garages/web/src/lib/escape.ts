/**
 * Escape key stack. The most recently registered *active* handler wins, so a modal closes
 * before its window, and a window closes before the app. App roots register a handler that
 * closes the app; Modal registers one that closes itself.
 */
import { useEffect, useRef } from 'react';

type Handler = () => void;
const stack: { id: number; fn: { current: Handler } }[] = [];
let seq = 0;

window.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  const top = stack[stack.length - 1];
  if (!top) return;
  e.preventDefault();
  e.stopPropagation();
  top.fn.current();
});

/** Register an Escape handler while `active` is true. */
export function useEscape(handler: Handler, active = true) {
  const ref = useRef(handler);
  ref.current = handler;
  useEffect(() => {
    if (!active) return;
    const id = ++seq;
    stack.push({ id, fn: ref });
    return () => {
      const i = stack.findIndex((s) => s.id === id);
      if (i >= 0) stack.splice(i, 1);
    };
  }, [active]);
}
