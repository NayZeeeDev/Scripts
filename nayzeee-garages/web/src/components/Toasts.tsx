/**
 * In-interface notifications (top-center, max 5): HUD-note style — glowing colour rail, icon
 * tile, title + message and a progress bar that runs out over the duration. Hover pauses,
 * click dismisses. Never takes focus.
 *
 * Lua decides what lands here (bridge/client/notify.lua): only notifications raised while one
 * of our windows holds NUI focus. FiveM draws the focused page above every other resource's
 * NUI, so the configured notify resource would be hidden behind the window; everything else is
 * shown by that resource. toast() never draws directly in game, it always asks Lua.
 */
import { useEffect, useRef, useState } from 'react';
import type { CSSProperties } from 'react';
import clsx from 'clsx';
import { useUi } from '@/lib/store';
import type { NotifyType, Toast } from '@/lib/types';
import { Icon } from './icons';
import type { IconName } from './icons';
import './ui/ui.css';

const ICON: Record<NotifyType, IconName> = {
  success: 'check',
  error: 'close',
  info: 'info',
  warning: 'warning',
};

const DEFAULT_DURATION = 5000;

function ToastItem({ toast, onDone }: { toast: Toast & { id: string }; onDone: (id: string) => void }) {
  const [leaving, setLeaving] = useState(false);
  const [paused, setPaused] = useState(false);
  const type: NotifyType = ICON[toast.type] ? toast.type : 'info';
  const duration = typeof toast.duration === 'number' ? toast.duration : DEFAULT_DURATION;
  const sticky = !(duration > 0);
  const gone = useRef(false);
  const remaining = useRef(duration);
  const startedAt = useRef(0);
  const timer = useRef<number>();

  const dismiss = () => {
    if (gone.current) return;
    gone.current = true;
    window.clearTimeout(timer.current);
    setLeaving(true);
    window.setTimeout(() => onDone(toast.id), 200);
  };
  const dismissRef = useRef(dismiss);
  dismissRef.current = dismiss;

  // The timer is the source of truth (the bar is only a visual): robust with reduced motion.
  const run = () => {
    if (sticky || gone.current) return;
    startedAt.current = Date.now();
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => dismissRef.current(), Math.max(0, remaining.current));
  };
  const pause = () => {
    if (sticky || gone.current) return;
    window.clearTimeout(timer.current);
    remaining.current -= Date.now() - startedAt.current;
    setPaused(true);
  };
  const resume = () => {
    setPaused(false);
    run();
  };

  useEffect(() => {
    run();
    return () => window.clearTimeout(timer.current);
    // start once per toast
  }, []);

  return (
    <div
      className={clsx('nz-toast', `nz-toast--${type}`, leaving && 'is-leaving', paused && 'is-paused')}
      role={type === 'error' ? 'alert' : 'status'}
      onClick={dismiss}
      onMouseEnter={pause}
      onMouseLeave={resume}
    >
      <span className="nz-toast__rail" />
      <span className="nz-toast__icon">
        <Icon name={ICON[type]} size={15} strokeWidth={2} />
      </span>
      <div className="nz-toast__text">
        {toast.title && <b>{toast.title}</b>}
        <p>{toast.message}</p>
      </div>
      {!sticky && (
        <span
          className="nz-toast__bar"
          style={{ animationDuration: `${duration}ms`, '--nz-toast-d': `${duration}ms` } as CSSProperties}
        />
      )}
    </div>
  );
}

export function Toasts() {
  const toasts = useUi((s) => s.toasts);
  const dismissToast = useUi((s) => s.dismissToast);
  if (!toasts.length) return null;
  return (
    <div className="nz-toasts" aria-live="polite">
      {toasts.map((tt) => (
        <ToastItem key={tt.id} toast={tt} onDone={dismissToast} />
      ))}
    </div>
  );
}
