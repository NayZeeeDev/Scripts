/**
 * The key ring's main action (docs/V2_CHANGES.md G.3): TAP = lock / unlock, HOLD = start (or
 * stop) the engine, KEEP HOLDING = roll the windows down. A ring around the key glyph fills
 * while the button is held, with a mark where the engine stage starts; the label says what
 * releasing does right now. Mouse / touch (pointer capture) and keyboard (Space / Enter on the
 * button, or the key ring's own Space / Enter while no other control has focus: see
 * `holdRef`). The progress is written straight into the SVG (requestAnimationFrame + a ref),
 * React only re-renders when the stage changes. Escape, losing focus or the window losing
 * focus cancels a hold without doing anything.
 */
import { forwardRef, useCallback, useEffect, useImperativeHandle, useRef, useState } from 'react';
import type { KeyboardEvent, PointerEvent } from 'react';
import { Icon, Spinner, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import { EngineGlyph, WindowGlyph } from './glyphs';

/** ms: released before this = tap (lock / unlock). */
export const ENGINE_MS = 650;
/** ms: held this long = windows (fires without waiting for the release). */
export const WINDOWS_MS = 1500;
/** ms: a press shorter than this never shows the ring (no flicker on a tap). */
const RING_DELAY = 120;

export type HoldStage = 'idle' | 'tap' | 'engine' | 'windows';

export interface HoldButtonProps {
  /** the vehicle is locked (label of the tap) */
  locked: boolean | null;
  /** engine running (label of the hold) */
  engine: boolean | null;
  /** tap allowed (the vehicle is out, not towed...) */
  canTap: boolean;
  /** hold stages allowed (an electronic fob, vehicle out) */
  canRemote: boolean;
  /** why nothing works (shown under the button) */
  reason?: string | null;
  busy: boolean;
  onTap: () => void;
  onEngine: () => void;
  onWindows: () => void;
  /** stage changes (the fob art lights the matching button) */
  onStage?: (stage: HoldStage) => void;
}

export interface HoldHandle {
  /** start a hold from the keyboard (the ring's Space / Enter) */
  press: () => void;
  release: () => void;
  cancel: () => void;
}

const R = 15;
const C = 2 * Math.PI * R;

export const HoldButton = forwardRef<HoldHandle, HoldButtonProps>(function HoldButton(
  { locked, engine, canTap, canRemote, reason, busy, onTap, onEngine, onWindows, onStage },
  ref,
) {
  const [stage, setStageState] = useState<HoldStage>('idle');
  const stageRef = useRef<HoldStage>('idle');
  const startRef = useRef<number | null>(null);
  const rafRef = useRef<number | null>(null);
  const firedRef = useRef(false);
  const arcRef = useRef<SVGCircleElement>(null);
  const btnRef = useRef<HTMLButtonElement>(null);
  const props = useRef({ canTap, canRemote, busy, onTap, onEngine, onWindows, onStage });
  props.current = { canTap, canRemote, busy, onTap, onEngine, onWindows, onStage };

  const setStage = useCallback((s: HoldStage) => {
    if (stageRef.current === s) return;
    stageRef.current = s;
    setStageState(s);
    props.current.onStage?.(s);
  }, []);

  const paint = (fraction: number) => {
    const arc = arcRef.current;
    if (arc) arc.style.strokeDashoffset = String(C * (1 - Math.max(0, Math.min(1, fraction))));
  };

  const stop = useCallback(() => {
    if (rafRef.current !== null) cancelAnimationFrame(rafRef.current);
    rafRef.current = null;
    startRef.current = null;
    firedRef.current = false;
    paint(0);
    btnRef.current?.classList.remove('is-holding');
    setStage('idle');
  }, [setStage]);

  const tick = useCallback(() => {
    const start = startRef.current;
    if (start === null) return;
    const held = performance.now() - start;
    const { canRemote: remote } = props.current;
    if (held >= RING_DELAY) btnRef.current?.classList.add('is-holding');
    if (!remote) {
      // a plain key: the ring only shows the tap; holding longer still locks / unlocks on release
      paint(Math.min(held / ENGINE_MS, 1) * 0.999);
      setStage('tap');
    } else if (held < ENGINE_MS) {
      paint((held / ENGINE_MS) * (ENGINE_MS / WINDOWS_MS));
      setStage('tap');
    } else if (held < WINDOWS_MS) {
      paint(held / WINDOWS_MS);
      setStage('engine');
    } else {
      paint(1);
      setStage('windows');
      if (!firedRef.current) {
        // keep holding: the windows go down right away (no need to let go)
        firedRef.current = true;
        props.current.onWindows();
      }
      rafRef.current = null;
      return;
    }
    rafRef.current = requestAnimationFrame(tick);
  }, [setStage]);

  const press = useCallback(() => {
    const p = props.current;
    if (p.busy || startRef.current !== null || (!p.canTap && !p.canRemote)) return;
    startRef.current = performance.now();
    firedRef.current = false;
    rafRef.current = requestAnimationFrame(tick);
  }, [tick]);

  const release = useCallback(() => {
    const start = startRef.current;
    if (start === null) return;
    const held = performance.now() - start;
    const fired = firedRef.current;
    const p = props.current;
    stop();
    if (fired) return; // the windows already went
    if (p.canRemote && held >= ENGINE_MS) p.onEngine();
    else if (p.canTap) p.onTap();
  }, [stop]);

  useImperativeHandle(ref, () => ({ press, release, cancel: stop }), [press, release, stop]);

  // a hold never outlives the button / the window focus
  useEffect(() => {
    const onBlur = () => stop();
    window.addEventListener('blur', onBlur);
    return () => {
      window.removeEventListener('blur', onBlur);
      if (rafRef.current !== null) cancelAnimationFrame(rafRef.current);
    };
  }, [stop]);

  const onPointerDown = (e: PointerEvent<HTMLButtonElement>) => {
    if (e.button !== 0) return;
    e.preventDefault();
    e.currentTarget.setPointerCapture?.(e.pointerId);
    e.currentTarget.focus();
    press();
  };
  const onKeyDown = (e: KeyboardEvent<HTMLButtonElement>) => {
    if (e.key === 'Escape' && startRef.current !== null) {
      e.preventDefault();
      e.stopPropagation();
      stop();
      return;
    }
    if (e.key !== ' ' && e.key !== 'Enter') return;
    e.preventDefault();
    e.stopPropagation();
    if (!e.repeat) press();
  };
  const onKeyUp = (e: KeyboardEvent<HTMLButtonElement>) => {
    if (e.key !== ' ' && e.key !== 'Enter') return;
    e.preventDefault();
    e.stopPropagation();
    release();
  };

  const disabled = !canTap && !canRemote;
  const tapLabel = locked === true ? t('Unlock') : t('Lock');
  const label =
    stage === 'engine'
      ? engine === true
        ? t('Release: stop the engine')
        : t('Release: start the engine')
      : stage === 'windows'
        ? t('Windows down')
        : stage === 'tap'
          ? canRemote
            ? t('Keep holding: engine')
            : tapLabel
          : t('Use key');

  return (
    <div className={cx('nz-keys-hold', disabled && 'is-disabled')}>
      <button
        ref={btnRef}
        type="button"
        className={cx('nz-keys-hold__btn', `is-${stage}`)}
        disabled={disabled}
        aria-label={t('Use key: tap to lock or unlock, hold to start the engine, keep holding to roll the windows down')}
        onPointerDown={onPointerDown}
        onPointerUp={release}
        onPointerCancel={stop}
        onLostPointerCapture={() => {
          if (startRef.current !== null) release();
        }}
        onKeyDown={onKeyDown}
        onKeyUp={onKeyUp}
        onBlur={() => {
          if (startRef.current !== null) stop();
        }}
        onContextMenu={(e) => e.preventDefault()}
      >
        <span className="nz-keys-hold__ring" aria-hidden="true">
          <svg viewBox="0 0 36 36" width="36" height="36">
            <circle className="nz-keys-hold__track" cx="18" cy="18" r={R} />
            <circle
              ref={arcRef}
              className="nz-keys-hold__arc"
              cx="18"
              cy="18"
              r={R}
              strokeDasharray={C}
              strokeDashoffset={C}
              transform="rotate(-90 18 18)"
            />
            {canRemote && (
              <line
                className="nz-keys-hold__mark"
                x1="18"
                y1="0.8"
                x2="18"
                y2="5.4"
                transform={`rotate(${(ENGINE_MS / WINDOWS_MS) * 360} 18 18)`}
              />
            )}
          </svg>
          <span className="nz-keys-hold__glyph">
            {busy ? (
              <Spinner size={14} />
            ) : stage === 'engine' ? (
              <EngineGlyph size={15} strokeWidth={1.8} />
            ) : stage === 'windows' ? (
              <WindowGlyph size={15} strokeWidth={1.8} />
            ) : (
              <Icon name={locked === true ? 'unlock' : 'lock'} size={15} strokeWidth={1.8} />
            )}
          </span>
        </span>
        <span className="nz-keys-hold__label">{label}</span>
      </button>
      <div className="nz-keys-hold__legend" aria-hidden="true">
        <span className={cx(stage === 'tap' && 'is-on', !canTap && 'is-off')}>
          <b>{t('Tap')}</b>
          {tapLabel}
        </span>
        <span className={cx(stage === 'engine' && 'is-on', !canRemote && 'is-off')}>
          <b>{t('Hold')}</b>
          {engine === true ? t('Engine off') : t('Engine on')}
        </span>
        <span className={cx(stage === 'windows' && 'is-on', !canRemote && 'is-off')}>
          <b>{t('Keep holding')}</b>
          {t('Windows')}
        </span>
      </div>
      {reason && <div className="nz-keys-hold__why">{reason}</div>}
    </div>
  );
});
