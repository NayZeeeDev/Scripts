import { useCallback, useEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react';
import { ChevronRight, X } from 'lucide-react';
import { cue } from '../lib/audio';
import { useStore } from '../lib/store';
import { t } from '../i18n';

export const cx = (...a: (string | false | null | undefined)[]) => a.filter(Boolean).join(' ');

export const isTyping = () => {
  const el = document.activeElement as HTMLElement | null;
  return !!el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable);
};

export function Kbd({ children, className }: { children: ReactNode; className?: string }) {
  return <span className={cx('kbd', className)}>{children}</span>;
}

/** MW4-style micro technical label, e.g. SYSTEM_ONLINE_C21 */
export function Micro({ children, className, style }: { children: ReactNode; className?: string; style?: CSSProperties }) {
  return <div className={cx('micro text-fg-3', className)} style={style}>{children}</div>;
}

/** "| PARTY ............ 3/6" section header */
export function SectionHead({ title, right, code, className }: { title: ReactNode; right?: ReactNode; code?: string; className?: string }) {
  return (
    <div className={cx('relative', className)}>
      {code && <div className="micro text-[8px] text-fg-4 mb-[3px] pl-[11px]">{code}</div>}
      <div className="flex items-center gap-2">
        <span className="w-[3px] h-[14px] bg-accent rounded-[1px] shadow-[0_0_10px_rgb(var(--accent)/.6)]" />
        <span className="label text-[13px] text-fg">{title}</span>
        <span className="flex-1 divider ml-2 opacity-60" />
        {right != null && <span className="micro text-fg-2 text-[11px] tracking-[.08em]">{right}</span>}
      </div>
    </div>
  );
}

export function Panel({ children, className, style, edge = true }: { children: ReactNode; className?: string; style?: CSSProperties; edge?: boolean }) {
  return <div className={cx('glass cut', edge && 'cut-edge', className)} style={style}>{children}</div>;
}

export function Toggle({ on, onChange, label }: { on: boolean; onChange: (v: boolean) => void; label?: string }) {
  return (
    <button
      aria-label={label}
      onClick={() => { cue('tick'); onChange(!on); }}
      className={cx(
        'relative w-[38px] h-[20px] rounded-full transition-colors duration-200 shrink-0',
        on ? 'bg-accent/90 shadow-[0_0_14px_-2px_rgb(var(--accent)/.7)]' : 'bg-white/10 border border-white/10',
      )}
    >
      <span className={cx('absolute top-[3px] w-[14px] h-[14px] rounded-full bg-white shadow transition-[left] duration-200 ease-out', on ? 'left-[21px]' : 'left-[3px]')} />
    </button>
  );
}

export function Slider({ value, min, max, step, onChange, format }: {
  value: number; min: number; max: number; step: number; onChange: (v: number) => void; format?: (v: number) => string;
}) {
  const p = ((value - min) / (max - min)) * 100;
  return (
    <div className="flex items-center gap-3 w-full">
      <input
        type="range" className="range" min={min} max={max} step={step} value={value}
        style={{ ['--p' as string]: `${p}%` }}
        onChange={(e) => onChange(parseFloat(e.target.value))}
      />
      <span className="micro text-fg w-[44px] text-right text-[11px] tracking-[.04em]">{format ? format(value) : value}</span>
    </div>
  );
}

export function Segmented<T extends string>({ items, value, onChange, className }: {
  items: { id: T; label: ReactNode; disabled?: boolean }[]; value: T; onChange: (v: T) => void; className?: string;
}) {
  return (
    <div className={cx('flex p-[3px] gap-[2px] rounded-[6px] bg-black/40 border border-white/[.06]', className)}>
      {items.map((it) => (
        <button
          key={it.id}
          disabled={it.disabled}
          onMouseEnter={() => !it.disabled && cue('hover')}
          onClick={() => onChange(it.id)}
          className={cx(
            'flex-1 h-[30px] px-3 rounded-[4px] label text-[12px] transition-all duration-200',
            it.id === value ? 'bg-white/[.1] text-fg shadow-[inset_0_1px_0_rgba(255,255,255,.08),0_0_0_1px_rgb(var(--accent)/.35)]' : 'text-fg-3 hover:text-fg-2',
            it.disabled && 'opacity-30 cursor-not-allowed',
          )}
        >
          {it.label}
        </button>
      ))}
    </div>
  );
}

export function IconBtn({ children, onClick, title, active, className, badge, danger }: {
  children: ReactNode; onClick?: () => void; title?: string; active?: boolean; className?: string; badge?: number; danger?: boolean;
}) {
  return (
    <button
      title={title}
      onMouseEnter={() => cue('hover')}
      onClick={(e) => { e.stopPropagation(); cue('click'); onClick?.(); }}
      className={cx(
        'relative grid place-items-center w-[34px] h-[34px] rounded-full transition-all duration-200',
        active ? 'text-accent-hi bg-accent/15' : danger ? 'text-fg-3 hover:text-bad hover:bg-bad/10' : 'text-fg-2 hover:text-fg hover:bg-white/[.07]',
        className,
      )}
    >
      {children}
      {!!badge && (
        <span className="absolute -top-[1px] -right-[1px] min-w-[15px] h-[15px] px-[3px] rounded-full bg-accent text-[9px] font-bold text-black grid place-items-center font-mono shadow-[0_0_10px_rgb(var(--accent)/.8)]">
          {badge}
        </span>
      )}
    </button>
  );
}

// ── Hold-to-confirm button ─────────────────────────────────────────────────
export function HoldButton({
  label, sub, onComplete, hotkey = true, duration = 900, disabled, busy, className, size = 'lg', keyLabel = 'Enter', icon,
}: {
  label: ReactNode; sub?: ReactNode; onComplete: () => void; hotkey?: boolean; duration?: number; disabled?: boolean; busy?: boolean;
  className?: string; size?: 'md' | 'lg'; keyLabel?: string; icon?: ReactNode;
}) {
  const [p, setP] = useState(0);
  const [holding, setHolding] = useState(false);
  const raf = useRef(0);
  const t0 = useRef(0);
  const done = useRef(false);
  const blocked = disabled || busy;

  const stop = useCallback((complete = false) => {
    cancelAnimationFrame(raf.current);
    setHolding(false);
    if (!complete) setP(0);
  }, []);

  const begin = useCallback(() => {
    if (blocked || holding) return;
    done.current = false;
    setHolding(true);
    cue('tick');
    t0.current = performance.now();
    const step = () => {
      const k = Math.min(1, (performance.now() - t0.current) / duration);
      setP(k);
      if (k >= 1) {
        if (!done.current) {
          done.current = true;
          stop(true);
          cue('deploy');
          onComplete();
          window.setTimeout(() => setP(0), 500);
        }
        return;
      }
      raf.current = requestAnimationFrame(step);
    };
    raf.current = requestAnimationFrame(step);
  }, [blocked, holding, duration, onComplete, stop]);

  useEffect(() => {
    if (!hotkey) return;
    const down = (e: KeyboardEvent) => {
      if (e.key !== 'Enter' || e.repeat || isTyping() || useStore.getState().modal) return;
      e.preventDefault();
      begin();
    };
    const up = (e: KeyboardEvent) => { if (e.key === 'Enter' && !done.current) stop(); };
    window.addEventListener('keydown', down);
    window.addEventListener('keyup', up);
    return () => { window.removeEventListener('keydown', down); window.removeEventListener('keyup', up); };
  }, [hotkey, begin, stop]);

  useEffect(() => () => cancelAnimationFrame(raf.current), []);

  const h = size === 'lg' ? 'h-[64px]' : 'h-[54px]';
  return (
    <button
      onMouseEnter={() => !blocked && cue('hover')}
      onPointerDown={(e) => { if (e.button === 0) begin(); }}
      onPointerUp={() => { if (!done.current) stop(); }}
      onPointerLeave={() => { if (holding && !done.current) stop(); }}
      className={cx(
        'group relative w-full overflow-hidden cut text-left select-none',
        h,
        blocked ? 'opacity-55 cursor-not-allowed' : 'cursor-pointer',
        className,
      )}
      style={{ ['--cut' as string]: '16px' }}
    >
      <div className={cx('absolute inset-0 accent-block transition-[filter] duration-200', !blocked && 'group-hover:brightness-110')} />
      {/* progress fill */}
      <div
        className="absolute inset-y-0 left-0 bg-white/30 mix-blend-overlay"
        style={{ width: `${p * 100}%`, transition: holding ? 'none' : 'width .28s cubic-bezier(.22,.8,.26,1)' }}
      />
      <div
        className="absolute bottom-0 left-0 h-[3px] bg-white shadow-[0_0_12px_rgba(255,255,255,.9)]"
        style={{ width: `${p * 100}%`, transition: holding ? 'none' : 'width .28s cubic-bezier(.22,.8,.26,1)' }}
      />
      {/* sheen */}
      <div className="absolute inset-y-0 -left-1/4 w-1/4 bg-gradient-to-r from-transparent via-white/20 to-transparent opacity-0 group-hover:opacity-100 group-hover:[animation:sheen_1.1s_ease-out_1]" />
      <div className="relative h-full flex items-center px-6 gap-4">
        {icon}
        <div className="flex-1 min-w-0">
          <div className={cx('display text-white drop-shadow-[0_1px_1px_rgba(0,0,0,.35)] tracking-[.06em]', size === 'lg' ? 'text-[30px]' : 'text-[24px]')}>
            {busy ? t('working') : label}
          </div>
          {sub && <div className="micro text-[9px] text-black/55 mt-[3px] font-medium">{sub}</div>}
        </div>
        <div className="flex items-center gap-2 text-black/70">
          <span className="micro text-[9px] font-semibold text-black/60">{t('hold')}</span>
          <span className="kbd !border-black/25 !bg-black/15 !text-white !shadow-none">{keyLabel}</span>
          <ChevronRight size={18} className="text-white/90" strokeWidth={2.4} />
        </div>
      </div>
    </button>
  );
}

// ── Modal shell ───────────────────────────────────────────────────────────
export function Modal({ children, onClose, width = 520, title, code }: {
  children: ReactNode; onClose: () => void; width?: number; title?: ReactNode; code?: string;
}) {
  return (
    <div className="absolute inset-0 z-[60] a-fade" onPointerDown={(e) => { if (e.target === e.currentTarget) onClose(); }}
      style={{ background: 'radial-gradient(ellipse at center, rgba(4,5,6,.55) 0%, rgba(4,5,6,.82) 100%)' }}>
      <div className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2">
        <Panel className="a-zoom p-0" style={{ width }}>
          {title && (
            <div className="flex items-start justify-between px-7 pt-6 pb-4">
              <div>
                {code && <Micro className="text-[9px] mb-1 text-accent-hi/70">{code}</Micro>}
                <div className="display text-[30px] text-fg">{title}</div>
              </div>
              <IconBtn onClick={onClose} title={t('close')}><X size={18} /></IconBtn>
            </div>
          )}
          {children}
        </Panel>
      </div>
    </div>
  );
}

export function Btn({ children, onClick, variant = 'ghost', className, disabled, small }: {
  children: ReactNode; onClick?: () => void; variant?: 'ghost' | 'accent' | 'danger' | 'line'; className?: string; disabled?: boolean; small?: boolean;
}) {
  return (
    <button
      disabled={disabled}
      onMouseEnter={() => !disabled && cue('hover')}
      onClick={(e) => { e.stopPropagation(); if (disabled) return; cue('click'); onClick?.(); }}
      className={cx(
        'label inline-flex items-center justify-center gap-2 rounded-[4px] transition-all duration-200 whitespace-nowrap',
        small ? 'h-[28px] px-3 text-[11px]' : 'h-[40px] px-5 text-[13px]',
        variant === 'accent' && 'bg-accent text-black font-bold hover:bg-accent-hi shadow-[0_0_20px_-6px_rgb(var(--accent)/.8)]',
        variant === 'danger' && 'bg-bad/90 text-white hover:bg-bad',
        variant === 'ghost' && 'bg-white/[.06] text-fg-2 hover:text-fg hover:bg-white/[.1] border border-white/[.06]',
        variant === 'line' && 'border border-white/15 text-fg-2 hover:text-fg hover:border-white/30',
        disabled && 'opacity-35 pointer-events-none',
        className,
      )}
    >
      {children}
    </button>
  );
}

export function Dot({ online }: { online?: boolean | null }) {
  if (online == null) return null;
  return (
    <span className={cx('inline-block w-[7px] h-[7px] rounded-full shrink-0', online ? 'bg-ok shadow-[0_0_8px_rgba(61,220,132,.8)]' : 'bg-fg-4')} />
  );
}

export function Avatar({ name, size = 36, ring, className }: { name: string; size?: number; ring?: 'accent' | 'love' | null; className?: string }) {
  const ini = (name || '?').trim().split(/\s+/).map((p) => p[0]).slice(0, 2).join('').toUpperCase();
  return (
    <div
      className={cx(
        'grid place-items-center rounded-full font-display font-bold text-fg shrink-0',
        ring === 'accent' && 'ring-[1.5px] ring-accent/80',
        ring === 'love' && 'ring-[1.5px] ring-love/80',
        className,
      )}
      style={{
        width: size, height: size, fontSize: size * 0.4,
        background: 'linear-gradient(145deg, rgba(255,255,255,.16), rgba(255,255,255,.03))',
        boxShadow: 'inset 0 1px 0 rgba(255,255,255,.12)',
      }}
    >
      {ini}
    </div>
  );
}
