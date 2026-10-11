import { useEffect, useRef } from 'react';

// Esc closes the open popup instead of the whole inventory: a capture listener on
// window runs before ox's exit listener and swallows the key.
export const useEscapeClose = (open: boolean, onClose: () => void) => {
  const closeRef = useRef(onClose);
  closeRef.current = onClose;

  useEffect(() => {
    if (!open) return;

    const handler = (e: KeyboardEvent) => {
      if (e.code !== 'Escape') return;
      e.stopImmediatePropagation();
      closeRef.current();
    };

    window.addEventListener('keyup', handler, true);
    return () => window.removeEventListener('keyup', handler, true);
  }, [open]);
};
