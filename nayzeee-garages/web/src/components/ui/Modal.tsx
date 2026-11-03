/**
 * Modal (portal into .nz-root, dims the screen, Escape closes, focus first input, Tab trap)
 * and ConfirmDialog.
 */
import { useEffect, useRef } from 'react';
import type { KeyboardEvent, MouseEvent, ReactNode } from 'react';
import clsx from 'clsx';
import { t } from '@/lib/i18n';
import { useEscape } from '@/lib/escape';
import { Icon } from '../icons';
import type { IconName } from '../icons';
import { Button, IconButton } from './Button';
import { Portal, usePresence, useUid } from './internal';

export interface ModalProps {
  open: boolean;
  title: ReactNode;
  icon?: IconName;
  /** Tone of the header icon tile. */
  iconTone?: 'teal' | 'red' | 'amber' | 'neutral';
  /** Small grey line under the title. */
  subtitle?: ReactNode;
  onClose: () => void;
  width?: number;
  footer?: ReactNode;
  /** Ignore Escape / backdrop / X while true (e.g. a request is running). */
  locked?: boolean;
  className?: string;
  bodyClassName?: string;
  children?: ReactNode;
}

const FOCUSABLE =
  'button:not([disabled]), [href], input:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

export function Modal({
  open,
  title,
  icon,
  iconTone = 'teal',
  subtitle,
  onClose,
  width = 420,
  footer,
  locked = false,
  className,
  bodyClassName,
  children,
}: ModalProps) {
  const { mounted, closing } = usePresence(open, 170);
  const panelRef = useRef<HTMLDivElement>(null);
  const downOnOverlay = useRef(false);
  const titleId = useUid('nz-modal');
  // Keep the last content while animating out (callers often clear state on close).
  const last = useRef({ title, icon, subtitle, footer, children });
  if (open) last.current = { title, icon, subtitle, footer, children };
  const view = last.current;

  const requestClose = () => {
    if (!locked) onClose();
  };
  useEscape(requestClose, open);

  useEffect(() => {
    if (!open) return;
    const prev = document.activeElement as HTMLElement | null;
    const raf = requestAnimationFrame(() => {
      const panel = panelRef.current;
      if (!panel) return;
      if (panel.contains(document.activeElement)) return;
      const target =
        panel.querySelector<HTMLElement>('[data-autofocus]') ??
        panel.querySelector<HTMLElement>('.nz-modal__body input:not([disabled]), .nz-modal__body textarea:not([disabled])') ??
        panel;
      target.focus();
    });
    return () => {
      cancelAnimationFrame(raf);
      if (prev && document.body.contains(prev)) prev.focus();
    };
  }, [open]);

  if (!mounted) return null;

  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    if (e.key !== 'Tab' || !panelRef.current) return;
    const items = Array.from(panelRef.current.querySelectorAll<HTMLElement>(FOCUSABLE)).filter(
      (el) => el.offsetParent !== null,
    );
    if (!items.length) return;
    const first = items[0];
    const lastEl = items[items.length - 1];
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      lastEl.focus();
    } else if (!e.shiftKey && document.activeElement === lastEl) {
      e.preventDefault();
      first.focus();
    }
  };

  return (
    <Portal>
      <div
        className={clsx('nz-modal-overlay', closing && 'is-closing')}
        onMouseDown={(e: MouseEvent) => {
          downOnOverlay.current = e.target === e.currentTarget;
        }}
        onMouseUp={(e: MouseEvent) => {
          // While closing, the panel is inert (CSS) and the overlay only swallows clicks.
          if (!closing && downOnOverlay.current && e.target === e.currentTarget) requestClose();
          downOnOverlay.current = false;
        }}
      >
        <div
          ref={panelRef}
          role="dialog"
          aria-modal="true"
          aria-labelledby={titleId}
          tabIndex={-1}
          className={clsx('nz-modal', className)}
          style={{ width }}
          onKeyDown={onKeyDown}
        >
          <div className="nz-modal__head">
            {view.icon && (
              <span className={clsx('nz-modal__icon', `nz-modal__icon--${iconTone}`)}>
                <Icon name={view.icon} size={16} strokeWidth={1.7} />
              </span>
            )}
            <div className="nz-modal__titles">
              <h3 id={titleId} className="nz-modal__title">
                {view.title}
              </h3>
              {view.subtitle && <p className="nz-modal__subtitle">{view.subtitle}</p>}
            </div>
            <IconButton icon="close" label={t('Close')} size="sm" onClick={requestClose} disabled={locked} className="nz-modal__x" />
          </div>
          <div className={clsx('nz-modal__body', bodyClassName)}>{view.children}</div>
          {view.footer && <div className="nz-modal__foot">{view.footer}</div>}
        </div>
      </div>
    </Portal>
  );
}

/* ── ConfirmDialog ────────────────────────────────────────────────────── */

export interface ConfirmDialogProps {
  open: boolean;
  title: ReactNode;
  message: ReactNode;
  confirmLabel: string;
  cancelLabel?: string;
  tone?: 'teal' | 'red';
  icon?: IconName;
  onConfirm: () => void;
  onCancel: () => void;
  busy?: boolean;
  /** Extra content under the message (summary rows, a price…). */
  children?: ReactNode;
  className?: string;
}

export function ConfirmDialog({
  open,
  title,
  message,
  confirmLabel,
  cancelLabel,
  tone = 'teal',
  icon,
  onConfirm,
  onCancel,
  busy = false,
  children,
  className,
}: ConfirmDialogProps) {
  const ico = icon ?? (tone === 'red' ? 'warning' : 'info');
  return (
    <Modal
      open={open}
      title={title}
      icon={ico}
      iconTone={tone}
      onClose={onCancel}
      locked={busy}
      width={400}
      className={clsx('nz-confirm', className)}
      footer={
        <>
          <Button variant="line" onClick={onCancel} disabled={busy}>
            {cancelLabel ?? t('Cancel')}
          </Button>
          <Button variant={tone} onClick={onConfirm} loading={busy} autoFocus>
            {confirmLabel}
          </Button>
        </>
      }
    >
      <div className="nz-confirm__message">{message}</div>
      {children}
    </Modal>
  );
}
