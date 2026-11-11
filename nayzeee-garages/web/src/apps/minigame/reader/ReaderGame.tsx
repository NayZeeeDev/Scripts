/**
 * Signal reader (G.7): a handheld device (original design in the owner's style: graphite body
 * with the chamfered corner, grain, teal brand mark, teal phosphor screen). Tune the input's
 * frequency and phase until it lies on the ignition's reference wave, then verify.
 * Keys: ↑ / ↓ select, ← / → tune (hold to speed up, Shift = coarse), Enter verify, H help,
 * Esc cancel. The device's buttons work with the mouse too. Three verifies at most.
 */
import { useCallback, useEffect, useRef, useState } from 'react';
import type { PointerEvent as ReactPointerEvent } from 'react';
import { t } from '@/lib/i18n';
import { useEscape } from '@/lib/escape';
import type { MinigameOpenData } from '@/lib/types';
import { BrandMark, Icon } from '@/components/ui';
import { HelpCard, PromptBar, TimeLeft, clamp, useFinish, useStarted } from '../shared';
import { sfx } from '../sound';
import { clampFreq, cyclesOf, inTolerance, matchOf, startOf, wrapPhase } from './signal';

type ReaderData = Extract<MinigameOpenData, { game: 'reader' }>;
type Row = 0 | 1 | 2;
type Mode = 'tune' | 'verifying' | 'locked' | 'denied' | 'failed';

const ATTEMPTS = 3;
const VERIFY_MS = 1100;
const DENIED_MS = 900;
const RESULT_HOLD_MS = 900;
const HOLD_DELAY_MS = 260;
const DEVICE_W = 384;
const DEVICE_H = 676;
const SEGMENTS = 20;

/** tap step / hold speed (per second, ramping up) per tuned value; Shift multiplies */
const TUNE = {
  freq: { tap: 0.5, coarse: 10, from: 6, to: 110, ramp: 1800, shift: 4 },
  phase: { tap: 1, coarse: 15, from: 18, to: 170, ramp: 1500, shift: 3 },
};

function cssVar(name: string, fallback: string) {
  const v = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  return v || fallback;
}

function useScale() {
  const calc = () => clamp(Math.min((window.innerHeight - 150) / DEVICE_H, (window.innerWidth - 32) / DEVICE_W), 0.55, 1.15);
  const [scale, setScale] = useState(calc);
  useEffect(() => {
    const on = () => setScale(calc());
    window.addEventListener('resize', on);
    return () => window.removeEventListener('resize', on);
  }, []);
  return scale;
}

export function ReaderGame({ data }: { data: ReaderData }) {
  const ref = data.puzzle;
  const valid = Number.isFinite(ref?.frequency) && Number.isFinite(ref?.phase);
  useStarted(data.token, valid);
  const finish = useFinish(data.token);
  const scale = useScale();

  const [start] = useState(() => (valid ? startOf(ref) : { freq: 600, phase: 0 }));
  const [freq, setFreq] = useState(start.freq);
  const [phase, setPhase] = useState(start.phase);
  const [row, setRow] = useState<Row>(0);
  const [mode, setMode] = useState<Mode>('tune');
  const [attempts, setAttempts] = useState(ATTEMPTS);
  const [help, setHelp] = useState(false);
  const [held, setHeld] = useState<'left' | 'right' | 'up' | 'down' | 'enter' | null>(null);

  const live = useRef({ freq: start.freq, phase: start.phase, mode: 'tune' as Mode, attempts: ATTEMPTS, row: 0 as Row });
  live.current = { freq, phase, mode, attempts, row };
  const done = useRef(false);
  const timers = useRef<number[]>([]);
  const later = (fn: () => void, ms: number) => timers.current.push(window.setTimeout(fn, ms));
  useEffect(() => () => timers.current.forEach((id) => window.clearTimeout(id)), []);

  const match = valid ? matchOf(freq, phase, ref) : 0;

  /* ── tuning ── */
  const nudge = useCallback((target: 0 | 1, dir: -1 | 1, amount: number) => {
    if (target === 0) setFreq((f) => clampFreq(f + dir * amount));
    else setPhase((p) => wrapPhase(p + dir * amount));
  }, []);

  const hold = useRef<{ dir: -1 | 1; since: number; shift: boolean; acc: number } | null>(null);
  useEffect(() => {
    let raf = 0;
    let last = performance.now();
    let tickAcc = 0;
    const loop = (now: number) => {
      const dt = Math.min(60, now - last);
      last = now;
      const h = hold.current;
      const r = live.current.row;
      if (h && live.current.mode === 'tune' && r !== 2) {
        const held = now - h.since;
        if (held > HOLD_DELAY_MS) {
          const cfg = r === 0 ? TUNE.freq : TUNE.phase;
          const k = Math.min(1, (held - HOLD_DELAY_MS) / cfg.ramp);
          const speed = (cfg.from + (cfg.to - cfg.from) * k * k) * (h.shift ? cfg.shift : 1);
          h.acc += (speed * dt) / 1000;
          const unit = r === 0 ? 0.1 : 1;
          const steps = Math.floor(h.acc / unit);
          if (steps > 0) {
            h.acc -= steps * unit;
            nudge(r as 0 | 1, h.dir, steps * unit);
            tickAcc += dt;
            if (tickAcc > 70) {
              tickAcc = 0;
              sfx.tick();
            }
          }
        }
      }
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [nudge]);

  /* ── verify ── */
  const verify = useCallback(() => {
    const cur = live.current;
    if (cur.mode !== 'tune' || done.current) return;
    sfx.verify();
    setMode('verifying');
    const ok = valid && inTolerance(cur.freq, cur.phase, ref);
    const answer = { frequency: cur.freq, phase: cur.phase };
    later(() => {
      if (ok) {
        sfx.locked();
        setMode('locked');
        done.current = true;
        later(() => finish({ success: true, answer }), RESULT_HOLD_MS);
        return;
      }
      sfx.denied();
      const left = cur.attempts - 1;
      setAttempts(left);
      if (left <= 0) {
        setMode('failed');
        done.current = true;
        later(() => finish({ success: false }), RESULT_HOLD_MS + 300);
        return;
      }
      setMode('denied');
      later(() => setMode((m) => (m === 'denied' ? 'tune' : m)), DENIED_MS);
    }, VERIFY_MS);
  }, [finish, ref, valid]);

  /* ── input (keyboard + device buttons share these) ── */
  const press = useCallback(
    (key: 'left' | 'right' | 'up' | 'down' | 'enter', shift = false) => {
      sfx.unlock();
      const cur = live.current;
      if (cur.mode !== 'tune') return;
      if (key === 'up' || key === 'down') {
        const next = clamp(cur.row + (key === 'up' ? -1 : 1), 0, 2) as Row;
        if (next !== cur.row) {
          setRow(next);
          sfx.select();
        }
        return;
      }
      if (key === 'enter' || (cur.row === 2 && key === 'right')) {
        verify();
        return;
      }
      if (cur.row === 2) return;
      const dir = key === 'left' ? -1 : 1;
      const cfg = cur.row === 0 ? TUNE.freq : TUNE.phase;
      nudge(cur.row as 0 | 1, dir, shift ? cfg.coarse : cfg.tap);
      sfx.tick();
      hold.current = { dir, since: performance.now(), shift, acc: 0 };
    },
    [nudge, verify],
  );
  const release = useCallback(() => {
    hold.current = null;
    setHeld(null);
  }, []);

  useEffect(() => {
    const map: Record<string, 'left' | 'right' | 'up' | 'down' | 'enter'> = {
      ArrowLeft: 'left',
      KeyA: 'left',
      ArrowRight: 'right',
      KeyD: 'right',
      ArrowUp: 'up',
      KeyW: 'up',
      ArrowDown: 'down',
      KeyS: 'down',
      Enter: 'enter',
      NumpadEnter: 'enter',
      Space: 'enter',
    };
    const down = (e: KeyboardEvent) => {
      if (e.key === 'Escape') return;
      if (e.code === 'KeyH') {
        e.preventDefault();
        if (!e.repeat) setHelp((v) => !v);
        return;
      }
      const key = map[e.code];
      if (!key) return;
      e.preventDefault();
      if (e.repeat) return;
      setHeld(key);
      press(key, e.shiftKey);
    };
    const up = (e: KeyboardEvent) => {
      const key = map[e.code];
      if (key) release();
    };
    window.addEventListener('keydown', down);
    window.addEventListener('keyup', up);
    window.addEventListener('blur', release);
    return () => {
      window.removeEventListener('keydown', down);
      window.removeEventListener('keyup', up);
      window.removeEventListener('blur', release);
    };
  }, [press, release]);

  useEscape(() => {
    if (done.current) return;
    done.current = true;
    finish({ success: false, cancelled: true });
  }, valid);

  /* ── waveform ── */
  const canvasRef = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !valid) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    const teal = cssVar('--teal', '#08afa2');
    const tealHi = cssVar('--teal-hi', '#0fd4c4');
    const red = cssVar('--red', '#e5484d');
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    let raf = 0;
    let lastDraw = 0;
    const draw = (now: number) => {
      raf = requestAnimationFrame(draw);
      if (now - lastDraw < 33) return; // ~30 fps is plenty for a scope
      lastDraw = now;
      const w = canvas.clientWidth;
      const h = canvas.clientHeight;
      if (canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(h * dpr)) {
        canvas.width = Math.round(w * dpr);
        canvas.height = Math.round(h * dpr);
      }
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, w, h);
      // grid
      ctx.strokeStyle = 'rgba(255,255,255,0.05)';
      ctx.lineWidth = 1;
      ctx.beginPath();
      for (let i = 1; i < 10; i++) {
        const x = Math.round((w * i) / 10) + 0.5;
        ctx.moveTo(x, 0);
        ctx.lineTo(x, h);
      }
      for (let i = 1; i < 4; i++) {
        const y = Math.round((h * i) / 4) + 0.5;
        ctx.moveTo(0, y);
        ctx.lineTo(w, y);
      }
      ctx.stroke();

      const cur = live.current;
      const scroll = (now / 1000) * 2.2;
      const amp = h * 0.34;
      const mid = h / 2;
      const steps = Math.max(120, Math.floor(w));
      const wave = (f: number, p: number, x: number) =>
        Math.sin((x / w) * cyclesOf(f) * Math.PI * 2 + (p * Math.PI) / 180 + scroll);
      const path = (fn: (x: number) => number) => {
        ctx.beginPath();
        for (let i = 0; i <= steps; i++) {
          const x = (i / steps) * w;
          const y = mid - fn(x) * amp;
          if (i === 0) ctx.moveTo(x, y);
          else ctx.lineTo(x, y);
        }
      };
      // residual (reference - input): flat when matched
      path((x) => (wave(ref.frequency, ref.phase, x) - wave(cur.freq, cur.phase, x)) * 0.5);
      ctx.strokeStyle = cur.mode === 'denied' || cur.mode === 'failed' ? red : 'rgba(255,255,255,0.22)';
      ctx.lineWidth = 1;
      ctx.setLineDash([]);
      ctx.stroke();
      // reference
      path((x) => wave(ref.frequency, ref.phase, x));
      ctx.strokeStyle = 'rgba(255,255,255,0.62)';
      ctx.lineWidth = 1.4;
      ctx.setLineDash([5, 4]);
      ctx.stroke();
      ctx.setLineDash([]);
      // input (glow + line)
      path((x) => wave(cur.freq, cur.phase, x));
      ctx.strokeStyle = teal;
      ctx.globalAlpha = 0.22;
      ctx.lineWidth = 6;
      ctx.stroke();
      ctx.globalAlpha = 1;
      ctx.strokeStyle = cur.mode === 'locked' ? tealHi : teal;
      ctx.lineWidth = 2;
      ctx.stroke();
    };
    raf = requestAnimationFrame(draw);
    return () => cancelAnimationFrame(raf);
  }, [ref, valid]);

  if (!valid) return null;

  const button = (key: 'left' | 'right' | 'up' | 'down' | 'enter') => ({
    onPointerDown: (e: ReactPointerEvent) => {
      e.preventDefault();
      setHeld(key);
      press(key, e.shiftKey);
    },
    onPointerUp: release,
    onPointerLeave: release,
    className: held === key ? 'is-held' : undefined,
  });

  const modeText: Record<Mode, string> = {
    tune: t('Tune'),
    verifying: t('Verifying'),
    locked: t('Signal locked'),
    denied: t('No lock'),
    failed: t('Reader blocked'),
  };
  const lit = Math.round((match / 100) * SEGMENTS);
  const vehicle = [data.vehicle?.label, data.vehicle?.plate].filter(Boolean).join(' · ');

  return (
    <div className="nz-mg-reader-wrap">
      <div
        className={`nz-mg-reader is-${mode}`}
        style={{ width: DEVICE_W, height: DEVICE_H, transform: `translate(-50%, -50%) scale(${scale})` }}
        role="dialog"
        aria-label={t('Signal reader')}
      >
        <span className="nz-mg-reader__antenna" aria-hidden="true" />
        <div className="nz-mg-reader__frame">
          <div className="nz-mg-reader__body">
            <header className="nz-mg-reader__brand">
              <BrandMark size="sm" />
              <span className="nz-mg-reader__name">{t('Signal reader')}</span>
              <span className="nz-mg-reader__model">SR-4</span>
              <span className={`nz-mg-reader__led is-${mode}`} aria-hidden="true" />
            </header>

            <div className="nz-mg-reader__screen">
              <div className="nz-mg-reader__status">
                <span className="nz-mg-reader__mode">{modeText[mode]}</span>
                <span className="nz-mg-reader__tries" title={t('Verifies left')}>
                  {Array.from({ length: ATTEMPTS }, (_, i) => (
                    <span key={i} className={i < attempts ? 'is-left' : undefined} />
                  ))}
                </span>
                <TimeLeft limit={data.timeLimit} paused={mode === 'locked' || mode === 'failed'} />
              </div>
              <canvas ref={canvasRef} className="nz-mg-reader__scope" />
              <div className="nz-mg-reader__legend">
                <span className="is-ref">{t('Ignition')}</span>
                <span className="is-in">{t('Input')}</span>
                <span className="is-diff">{t('Difference')}</span>
              </div>

              <div className="nz-mg-reader__rows">
                <div className={`nz-mg-reader__row${row === 0 ? ' is-selected' : ''}`}>
                  <span className="nz-mg-reader__label">{t('Freq')}</span>
                  <span className="nz-mg-reader__value">{freq.toFixed(1)}</span>
                  <span className="nz-mg-reader__unit">MHz</span>
                </div>
                <div className={`nz-mg-reader__row${row === 1 ? ' is-selected' : ''}`}>
                  <span className="nz-mg-reader__label">{t('Phase')}</span>
                  <span className="nz-mg-reader__value">{String(phase).padStart(3, '0')}</span>
                  <span className="nz-mg-reader__unit">°</span>
                </div>
                <div className={`nz-mg-reader__row nz-mg-reader__row--verify${row === 2 ? ' is-selected' : ''}`}>
                  <span className="nz-mg-reader__label">{t('Verify')}</span>
                  <span className="nz-mg-reader__progress">
                    <span key={mode === 'verifying' ? 'run' : 'idle'} className={mode === 'verifying' ? 'is-running' : undefined} />
                  </span>
                </div>
              </div>

              <div className="nz-mg-reader__match">
                <span className="nz-mg-reader__label">{t('Match')}</span>
                <span className="nz-mg-reader__pct">
                  {match}
                  <small>%</small>
                </span>
                <span className="nz-mg-reader__segs" aria-hidden="true">
                  {Array.from({ length: SEGMENTS }, (_, i) => (
                    <span key={i} className={i < lit ? 'is-lit' : undefined} />
                  ))}
                </span>
              </div>
            </div>

            <div className="nz-mg-reader__controls">
              <div className="nz-mg-reader__pad">
                <button type="button" aria-label={t('Select up')} data-dir="up" {...button('up')}>
                  <Icon name="chevronUp" size={16} strokeWidth={2.2} />
                </button>
                <button type="button" aria-label={t('Tune down')} data-dir="left" {...button('left')}>
                  <Icon name="chevronLeft" size={16} strokeWidth={2.2} />
                </button>
                <span className="nz-mg-reader__hub" aria-hidden="true" />
                <button type="button" aria-label={t('Tune up')} data-dir="right" {...button('right')}>
                  <Icon name="chevronRight" size={16} strokeWidth={2.2} />
                </button>
                <button type="button" aria-label={t('Select down')} data-dir="down" {...button('down')}>
                  <Icon name="chevronDown" size={16} strokeWidth={2.2} />
                </button>
              </div>
              <div className="nz-mg-reader__keys">
                <button type="button" {...button('enter')} className={`nz-mg-reader__verify${held === 'enter' ? ' is-held' : ''}`}>
                  <Icon name="check" size={15} strokeWidth={2.2} />
                  {t('Verify')}
                </button>
                <button
                  type="button"
                  className="nz-mg-reader__cancel"
                  onClick={() => {
                    if (done.current) return;
                    done.current = true;
                    finish({ success: false, cancelled: true });
                  }}
                >
                  {t('Cancel')}
                </button>
              </div>
            </div>
            {vehicle && <div className="nz-mg-reader__plate">{vehicle}</div>}
            <span className="nz-mg-reader__grille" aria-hidden="true" />
          </div>
        </div>
      </div>
      {help && (
        <HelpCard
          className="nz-mg-reader__help"
          title={t('Reading the ignition')}
          steps={[
            t('The dashed wave is the ignition signal, the teal wave is your input.'),
            t('↑ / ↓ select Freq or Phase, ← / → tune it. Hold to speed up, Shift for big steps.'),
            t('Match the number of waves with Freq, then slide them on top of each other with Phase. The faint difference line goes flat.'),
            t('At 100% press Enter to verify. You have {count} verifies.', { count: ATTEMPTS }),
          ]}
        />
      )}
      <PromptBar
        items={[
          { keys: ['ArrowUp', 'ArrowDown'], label: t('Select'), active: held === 'up' || held === 'down' },
          { keys: ['ArrowLeft', 'ArrowRight'], label: t('Tune'), active: held === 'left' || held === 'right' },
          { keys: ['Enter'], label: t('Verify'), active: held === 'enter' },
          { keys: ['H'], label: help ? t('Hide help') : t('Help'), active: help },
          { keys: ['Escape'], label: t('Cancel') },
        ]}
      />
    </div>
  );
}
