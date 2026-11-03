/**
 * Toast stack (top-center, max 5): HUD-note style — glowing colour rail, icon tile,
 * title + message and a progress bar that runs out over the duration. Hover pauses,
 * click dismisses. Never takes focus.
 */
import { useState } from 'react';
import clsx from 'clsx';
import { useUi } from '@/lib/store';
import type { Toast, ToastType } from '@/lib/types';
import { Icon } from './icons';
import type { IconName } from './icons';
import './ui/ui.css';

const ICON: Record<ToastType, IconName> = {
  success: 'check',
  error: 'close',
  info: 'info',
  warning: 'warning',
};

const DEFAULT_DURATION = 4500;

function ToastItem({ toast, onDone }: { toast: Toast & { id: string }; onDone: (id: string) => void }) {
  const [leaving, setLeaving] = useState(false);
  const type: ToastType = ICON[toast.type] ? toast.type : 'info';
  const duration = toast.duration ?? DEFAULT_DURATION;
  const sticky = !(duration > 0);

  const dismiss = () => {
    if (leaving) return;
    setLeaving(true);
    window.setTimeout(() => onDone(toast.id), 200);
  };

  return (
    <div
      className={clsx('nz-toast', `nz-toast--${type}`, leaving && 'is-leaving')}
      role={type === 'error' ? 'alert' : 'status'}
      onClick={dismiss}
    >
      <span className="nz-toast__rail" />
      <span className="nz-toast__icon">
        <Icon name={ICON[type]} size={15} strokeWidth={2} />
      </span>
      <div className="nz-toast__text">
        {toast.title && <b>{toast.title}</b>}
        {toast.message && <p>{toast.message}</p>}
      </div>
      {!sticky && (
        <span
          className="nz-toast__bar"
          style={{ animationDuration: `${duration}ms` }}
          onAnimationEnd={dismiss}
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
