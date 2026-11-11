/**
 * Lockpick (G.6): the 3D five-pin lock drawn over the door. Lazy chunk (three.js).
 * Keys: A / D move between pins, W / S lift / lower, Space (hold) tension, H help, Esc exit.
 * The simulation (model.ts) runs on requestAnimationFrame; the WebGL scene renders only while
 * something moves. Lua gets { success, answer: the pins in the order set } or
 * { success: false, snapped: true } (overset) or { cancelled: true } (Esc).
 */
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { t } from '@/lib/i18n';
import { useEscape } from '@/lib/escape';
import { useUi } from '@/lib/store';
import type { MinigameOpenData } from '@/lib/types';
import { Icon } from '@/components/ui';
import { HelpCard, PromptBar, TimeLeft, clamp, useFinish, useStarted } from '../shared';
import { sfx } from '../sound';
import { createLock, movePick, setLifting, setLowering, setTension, step } from './model';
import type { LockEvent, LockState } from './model';
import { createLockView } from './lockScene';
import type { LockView } from './lockScene';

type PinsData = Extract<MinigameOpenData, { game: 'pins' }>;

const OPEN_HOLD_MS = 1100; // the plug turns before the result goes out
const SNAP_HOLD_MS = 1300;

interface Ui {
  setCount: number;
  pick: number;
  tension: boolean;
  lifting: boolean;
  lowering: boolean;
  zone: boolean;
  status: LockState['status'];
  message: 'idle' | 'tension' | 'click' | 'set' | 'drop' | 'open' | 'far' | 'fast';
}

/** Size and place of the lock: over the door handle (anchor) or centred. */
function useBox(anchor: PinsData['anchor']) {
  const [vw, setVw] = useState(window.innerWidth);
  const [vh, setVh] = useState(window.innerHeight);
  useEffect(() => {
    const on = () => {
      setVw(window.innerWidth);
      setVh(window.innerHeight);
    };
    window.addEventListener('resize', on);
    return () => window.removeEventListener('resize', on);
  }, []);
  const w = Math.round(clamp(vw * 0.34, 420, 660));
  const h = Math.round(w * 0.74);
  const bottomSafe = 96; // prompt bar
  let left: number;
  let top: number;
  if (anchor && Number.isFinite(anchor.x) && Number.isFinite(anchor.y)) {
    left = anchor.x * vw - w * 0.42;
    top = anchor.y * vh - h * 0.5;
  } else {
    left = (vw - w) / 2;
    top = vh * 0.43 - h / 2;
  }
  left = clamp(left, 16, Math.max(16, vw - w - 16));
  top = clamp(top, 16, Math.max(16, vh - h - bottomSafe));
  return { w, h, left, top };
}

export default function LockGame({ data }: { data: PinsData }) {
  const finish = useFinish(data.token);
  const lock = useMemo(() => createLock(data.puzzle), [data.puzzle]);
  const [webgl, setWebgl] = useState<boolean | null>(lock ? null : false);
  useStarted(data.token, webgl);

  const canvasRef = useRef<HTMLCanvasElement>(null);
  const viewRef = useRef<LockView | null>(null);
  const dirty = useRef(true);
  const done = useRef(false);
  const [help, setHelp] = useState(false);
  const [flash, setFlash] = useState<'set' | 'snap' | 'drop' | null>(null);
  const [ui, setUi] = useState<Ui>({
    setCount: 0,
    pick: 0,
    tension: false,
    lifting: false,
    lowering: false,
    zone: false,
    status: 'play',
    message: 'idle',
  });
  const anchor = useUi((s) => (s.apps.minigame.data as PinsData | null)?.anchor ?? data.anchor);
  const box = useBox(anchor);

  /* ── WebGL scene ── */
  useLayoutEffect(() => {
    if (!lock || !canvasRef.current) return;
    let view: LockView;
    try {
      view = createLockView(canvasRef.current, lock);
    } catch {
      setWebgl(false);
      return;
    }
    viewRef.current = view;
    setWebgl(true);
    const canvas = canvasRef.current;
    const onLost = (e: Event) => {
      e.preventDefault();
      if (!done.current) {
        done.current = true;
        finish({ success: false, cancelled: true });
      }
    };
    canvas.addEventListener('webglcontextlost', onLost);
    return () => {
      canvas.removeEventListener('webglcontextlost', onLost);
      viewRef.current = null;
      view.dispose();
    };
  }, [lock, finish]);

  useLayoutEffect(() => {
    viewRef.current?.resize(box.w, box.h);
    dirty.current = true;
  }, [box.w, box.h, webgl]);

  /* ── simulation loop + input ── */
  useEffect(() => {
    if (!lock || webgl !== true) return;
    const s = lock;
    let raf = 0;
    let last = performance.now();
    let flashTimer = 0;

    const sync = (message?: Ui['message']) =>
      setUi((prev) => {
        const next: Ui = {
          setCount: s.setOrder.length,
          pick: s.pick,
          tension: s.tension,
          lifting: s.lifting,
          lowering: s.lowering,
          zone: s.zone,
          status: s.status,
          message: message ?? prev.message,
        };
        const same = (Object.keys(next) as (keyof Ui)[]).every((k) => next[k] === prev[k]);
        return same ? prev : next;
      });

    const pulse = (kind: 'set' | 'snap' | 'drop') => {
      setFlash(kind);
      window.clearTimeout(flashTimer);
      flashTimer = window.setTimeout(() => setFlash(null), kind === 'snap' ? 700 : 380);
    };

    const handle = (events: LockEvent[]) => {
      if (!events.length) return;
      dirty.current = true;
      let message: Ui['message'] | undefined;
      for (const e of events) {
        switch (e.type) {
          case 'click':
            sfx.click();
            viewRef.current?.shake(0.25);
            message = 'click';
            break;
          case 'set':
            sfx.set();
            viewRef.current?.shake(0.45);
            pulse('set');
            message = 'set';
            break;
          case 'drop':
            sfx.drop(e.count);
            pulse('drop');
            message = 'drop';
            break;
          case 'spring':
            sfx.spring();
            break;
          case 'tension':
            if (e.on) sfx.tension();
            message = e.on ? 'tension' : message ?? 'idle';
            break;
          case 'overset':
            sfx.snap();
            viewRef.current?.snap();
            pulse('snap');
            message = e.reason;
            if (!done.current) {
              done.current = true;
              window.setTimeout(() => finish({ success: false, snapped: true }), SNAP_HOLD_MS);
            }
            break;
          case 'open':
            sfx.open();
            message = 'open';
            if (!done.current) {
              done.current = true;
              const answer = [...s.setOrder];
              window.setTimeout(() => finish({ success: true, answer }), OPEN_HOLD_MS);
            }
            break;
          case 'move':
            break;
        }
      }
      sync(message);
    };

    const loop = (now: number) => {
      const dt = now - last;
      last = now;
      handle(step(s, dt));
      const view = viewRef.current;
      if (view) {
        const moving = view.frame(s, dt);
        if (moving || dirty.current) {
          view.render();
          dirty.current = false;
        }
      }
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);

    const down = (e: KeyboardEvent) => {
      if (e.key === 'Escape') return; // the escape stack handles it
      const k = e.code;
      if (['KeyA', 'KeyD', 'KeyW', 'KeyS', 'Space', 'KeyH', 'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(k)) e.preventDefault();
      if (e.repeat) return;
      sfx.unlock();
      if (k === 'KeyH') {
        setHelp((v) => !v);
        return;
      }
      if (s.status !== 'play') return;
      if (k === 'KeyA' || k === 'ArrowLeft') handle(movePick(s, -1));
      else if (k === 'KeyD' || k === 'ArrowRight') handle(movePick(s, 1));
      else if (k === 'KeyW' || k === 'ArrowUp') handle(setLifting(s, true));
      else if (k === 'KeyS' || k === 'ArrowDown') setLowering(s, true);
      else if (k === 'Space') handle(setTension(s, true));
      sync();
    };
    const up = (e: KeyboardEvent) => {
      const k = e.code;
      if (k === 'KeyW' || k === 'ArrowUp') setLifting(s, false);
      else if (k === 'KeyS' || k === 'ArrowDown') setLowering(s, false);
      else if (k === 'Space') handle(setTension(s, false));
      sync();
    };
    // focus lost (alt-tab, another window): let go of everything, the pins drop
    const blur = () => {
      setLifting(s, false);
      setLowering(s, false);
      handle(setTension(s, false));
      sync();
    };
    window.addEventListener('keydown', down);
    window.addEventListener('keyup', up);
    window.addEventListener('blur', blur);
    return () => {
      cancelAnimationFrame(raf);
      window.clearTimeout(flashTimer);
      window.removeEventListener('keydown', down);
      window.removeEventListener('keyup', up);
      window.removeEventListener('blur', blur);
    };
  }, [lock, webgl, finish]);

  useEscape(() => {
    if (done.current) return;
    done.current = true;
    finish({ success: false, cancelled: true });
  }, webgl !== false);

  if (!lock || webgl === false) {
    // Lua falls back to skill checks (minigame:started ok = false)
    return null;
  }

  const total = lock.pins.length;
  const status: { text: string; tone: 'teal' | 'red' | 'ink' } = (() => {
    switch (ui.message) {
      case 'tension':
        return { text: t('Tension on: find the stiff pin'), tone: 'ink' };
      case 'click':
        return { text: t('Click. Let go of W to set it'), tone: 'teal' };
      case 'set':
        return { text: t('Pin set: keep the tension, find the next one'), tone: 'teal' };
      case 'drop':
        return { text: t('Tension released: the pins dropped'), tone: 'red' };
      case 'open':
        return { text: t('The lock turns'), tone: 'teal' };
      case 'far':
        return { text: t('Pushed too far: the pick snapped'), tone: 'red' };
      case 'fast':
        return { text: t('Too much force: the pick snapped'), tone: 'red' };
      default:
        return { text: t('Hold Space for tension, then lift the pins'), tone: 'ink' };
    }
  })();
  const vehicle = [data.vehicle?.label, data.vehicle?.plate].filter(Boolean).join(' · ');
  const playing = ui.status === 'play';

  return (
    <div className="nz-mg-lock" data-status={ui.status}>
      <div
        className={`nz-mg-lock__stage${flash ? ` is-${flash}` : ''}`}
        style={{ left: box.left, top: box.top, width: box.w, height: box.h }}
      >
        <span className="nz-mg-lock__shadow" aria-hidden="true" />
        <canvas ref={canvasRef} className="nz-mg-lock__canvas" width={box.w} height={box.h} />
        <div className="nz-mg-lock__card">
          <div className="nz-mg-lock__head">
            <span className="nz-mg-lock__title">{t('Pick the lock')}</span>
            {vehicle && <span className="nz-mg-lock__vehicle">{vehicle}</span>}
            <TimeLeft limit={data.timeLimit} paused={!playing} />
          </div>
          <div className="nz-mg-lock__pins" aria-label={t('{done} of {total} pins set', { done: ui.setCount, total })}>
            {lock.pins.map((p, i) => (
              <span
                key={i}
                className={`nz-mg-lock__pin${p.set ? ' is-set' : ''}${ui.pick === i ? ' is-current' : ''}`}
              >
                {i + 1}
              </span>
            ))}
            <span className={`nz-mg-lock__tension${ui.tension ? ' is-on' : ''}`}>
              <Icon name="wrench" size={12} strokeWidth={1.9} />
              {ui.tension ? t('Tension') : t('No tension')}
            </span>
          </div>
          <div className={`nz-mg-lock__status is-${status.tone}`} role="status">
            {status.text}
          </div>
        </div>
        {help && (
          <HelpCard
            className="nz-mg-lock__help"
            title={t('Picking a pin lock')}
            steps={[
              t('Hold Space to put tension on the plug. Let go and every set pin drops.'),
              t('A / D move the pick under a pin. Under tension one pin binds: it feels stiff and stays where you leave it.'),
              t('Lift it with short presses of W. At the shear line it clicks: let go of W and it sets.'),
              t('Holding W speeds the pick up. Too fast or too far past the line oversets the pin and can snap the pick.'),
              t('Set every pin in the order they bind and the lock turns.'),
            ]}
            footer={t('Snap chance on an overset: {chance}%', { chance: Math.round(data.snapChance) })}
          />
        )}
      </div>
      <PromptBar
        items={[
          { keys: ['A', 'D'], label: t('Move') },
          { keys: ['W', 'S'], label: t('Lift'), active: playing && (ui.lifting || ui.lowering) },
          { keys: ['Space'], label: t('Tension'), active: playing && ui.tension },
          { keys: ['H'], label: help ? t('Hide help') : t('Help'), active: help },
          { keys: ['Escape'], label: t('Exit') },
        ]}
      />
    </div>
  );
}
