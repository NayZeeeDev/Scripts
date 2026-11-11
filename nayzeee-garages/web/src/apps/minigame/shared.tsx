/**
 * Pieces shared by the three minigames: the owner's prompt bar (bottom centre, key chips that
 * light up white while held), the help card, and the finish / started calls to Lua.
 */
import { useCallback, useEffect, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import { Icon } from '@/components/ui';
import type { MinigameFinish } from '@/lib/types';

const KEY_LABELS: Record<string, string> = {
  ' ': 'Space',
  Space: 'Space',
  Escape: 'Esc',
  ArrowUp: '↑',
  ArrowDown: '↓',
  ArrowLeft: '←',
  ArrowRight: '→',
  Enter: 'Enter',
  Shift: 'Shift',
  Mouse: 'Mouse',
};

export const keyText = (k: string) => KEY_LABELS[k] ?? (k.length === 1 ? k.toUpperCase() : k);

export interface PromptItem {
  keys: string[];
  label: string;
  /** chips drawn white while true (the key is held / the mode is on) */
  active?: boolean;
}

/** The owner's control bar: a dark rounded bar, bordered key chips and white labels. */
export function PromptBar({ items, title }: { items: PromptItem[]; title?: string }) {
  return (
    <div className="nz-mg-prompt" role="note">
      <div className="nz-mg-prompt__bar">
        {title && (
          <span className="nz-mg-prompt__title">
            <Icon name="info" size={13} strokeWidth={1.9} />
            <span>{title}</span>
          </span>
        )}
        {items.map((item) => (
          <span key={item.label} className="nz-mg-prompt__group">
            <span className="nz-mg-prompt__caps">
              {item.keys.map((k) => {
                const text = keyText(k);
                return (
                  <kbd
                    key={k}
                    className={`nz-mg-key${text.length > 2 ? ' nz-mg-key--word' : ''}${item.active ? ' is-active' : ''}`}
                  >
                    {text}
                  </kbd>
                );
              })}
            </span>
            <span className="nz-mg-prompt__label">{item.label}</span>
          </span>
        ))}
      </div>
    </div>
  );
}

/** Help card (H): numbered steps in a HUD panel. */
export function HelpCard({ title, steps, footer, className }: { title: string; steps: ReactNode[]; footer?: ReactNode; className?: string }) {
  return (
    <aside className={`nz-mg-help${className ? ` ${className}` : ''}`} aria-label={title}>
      <header className="nz-mg-help__head">
        <span className="nz-mg-help__title">{title}</span>
        <span className="nz-mg-help__close">
          <kbd className="nz-mg-key">H</kbd>
          <span>{t('Hide')}</span>
        </span>
      </header>
      <ol className="nz-mg-help__steps">
        {steps.map((s, i) => (
          <li key={i}>
            <span className="nz-mg-help__num">{i + 1}</span>
            <span>{s}</span>
          </li>
        ))}
      </ol>
      {footer && <div className="nz-mg-help__foot">{footer}</div>}
    </aside>
  );
}

/**
 * finish(): sends the result to Lua once (later calls are ignored). Lua closes the app,
 * checks nothing itself and hands the answer to the server, which decides.
 */
export function useFinish(token: number) {
  const sent = useRef(false);
  return useCallback(
    (result: Omit<MinigameFinish, 'token'>) => {
      if (sent.current) return;
      sent.current = true;
      void request('minigame:finish', { token, ...result }, { toastError: false });
    },
    [token],
  );
}

/** Tell Lua the game is on screen (ok = false: it cannot be drawn: Lua falls back to skill checks). */
export function useStarted(token: number, ok: boolean | null) {
  const told = useRef(false);
  useEffect(() => {
    if (ok === null || told.current) return;
    told.current = true;
    void request('minigame:started', { token, ok }, { toastError: false });
  }, [token, ok]);
}

/** Seconds left of the attempt (Lua ends it at `limit`); red in the last 15 s. */
export function TimeLeft({ limit, paused = false }: { limit: number; paused?: boolean }) {
  const start = useRef(performance.now());
  const [, tick] = useState(0);
  useEffect(() => {
    if (paused) return;
    const id = window.setInterval(() => tick((n) => n + 1), 1000);
    return () => window.clearInterval(id);
  }, [paused]);
  const max = Number.isFinite(limit) && limit > 0 ? limit : 85;
  const left = Math.max(0, Math.ceil(max - (performance.now() - start.current) / 1000));
  const text = `${Math.floor(left / 60)}:${String(left % 60).padStart(2, '0')}`;
  return (
    <span className={`nz-mg-time${left <= 15 ? ' is-low' : ''}`} title={t('Time left')}>
      <Icon name="clock" size={11} strokeWidth={2} />
      {text}
    </span>
  );
}

export const clamp = (v: number, min: number, max: number) => Math.max(min, Math.min(max, v));
