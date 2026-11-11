/**
 * fob app (docs/V2_CHANGES.md G.4 / G.5, client/carlock/fob.lua): the on-screen key fob.
 *  - hud (no focus): the fob of the key you are using, where the player put it, its buttons
 *    light up and beep on presses; with the key in your hand the side prompts show the keys
 *    of Throw / Inspect / Move / Help / Close (Lua handles those keys).
 *  - edit (focus): drag the fob to move it, drag a corner to resize, toggle the keybind
 *    prompts, Reset / Save (player setting fobPosition; the prompts toggle is kept in this
 *    browser's storage).
 *  - help (focus): what every control does.
 *  - inspect (focus): a key on the ground (Keep / Return to ground) or one you carry, with the
 *    spinning 3D brand logo.
 */
import { useCallback, useEffect, useMemo, useRef, useState, type PointerEvent as ReactPointerEvent } from 'react';
import { useApp } from '@/lib/store';
import { request } from '@/lib/nui';
import { useEscape } from '@/lib/escape';
import { t } from '@/lib/i18n';
import type { FobButtonName, FobHudData, FobHudKey, FobInspect, FobKeyBinds, FobLayout } from '@/lib/types';
import { Badge, Button, Icon, KeyHint, PlateTag, Toggle, Window } from '@/components/ui';
import { FobArt, fobAspect } from '@/components/fob/FobArt';
import { BrandLogo3D } from '@/components/fob/BrandLogo3D';
import { fobBeep } from './beep';
import './fob.css';

/** Fob height in px at 1080p and scale 1. */
const BASE_H = 210;
const MIN_SCALE = 0.5;
const MAX_SCALE = 2;
const EDGE = 12;
const PROMPTS_KEY = 'nz-fob-prompts';

const clamp = (v: number, min: number, max: number) => Math.min(max, Math.max(min, v));
const round = (v: number, d = 3) => Math.round(v * 10 ** d) / 10 ** d;

function readPrompts(): boolean {
  try {
    return window.localStorage.getItem(PROMPTS_KEY) !== '0';
  } catch {
    return true;
  }
}
function writePrompts(on: boolean) {
  try {
    window.localStorage.setItem(PROMPTS_KEY, on ? '1' : '0');
  } catch {
    /* private storage: only this session */
  }
}

function useViewport() {
  const [vp, setVp] = useState(() => ({ w: window.innerWidth, h: window.innerHeight }));
  useEffect(() => {
    const on = () => setVp({ w: window.innerWidth, h: window.innerHeight });
    window.addEventListener('resize', on);
    return () => window.removeEventListener('resize', on);
  }, []);
  return vp;
}

interface Box { left: number; top: number; w: number; h: number; cx: number; cy: number }

function boxOf(layout: FobLayout, aspect: number, vw: number, vh: number): Box {
  const h = BASE_H * (vh / 1080) * clamp(layout.scale, MIN_SCALE, MAX_SCALE);
  const w = h * aspect;
  const cx = clamp(layout.x * vw, w / 2 + EDGE, Math.max(w / 2 + EDGE, vw - w / 2 - EDGE));
  const cy = clamp(layout.y * vh, h / 2 + EDGE, Math.max(h / 2 + EDGE, vh - h / 2 - EDGE));
  return { left: cx - w / 2, top: cy - h / 2, w, h, cx, cy };
}

/** The button lit by the last press (seq), for a moment. */
function usePressed(press: FobHudData['press']): FobButtonName | null {
  const [lit, setLit] = useState<FobButtonName | null>(null);
  const seen = useRef<number | null>(null);
  useEffect(() => {
    if (!press || press.seq === seen.current) return;
    seen.current = press.seq;
    setLit(press.button);
    if (press.beep) fobBeep(press.button === 'panic');
    const id = window.setTimeout(() => setLit(null), press.button === 'panic' ? 1400 : 700);
    return () => window.clearTimeout(id);
  }, [press]);
  return lit;
}

/* ───────────────────────────── pieces ───────────────────────────── */

type PromptAction = 'throw' | 'inspect' | 'move' | 'help' | 'close';

function SidePrompts({ keys, side, onAction }: { keys: FobKeyBinds; side: 'left' | 'right'; onAction?: (a: PromptAction) => void }) {
  const rows: { action: PromptAction; label: string; key: string }[] = [
    { action: 'throw', label: t('Throw'), key: keys.throw },
    { action: 'inspect', label: t('Inspect'), key: keys.inspect },
    { action: 'move', label: t('Move'), key: keys.move },
    { action: 'help', label: t('Help'), key: keys.help },
    { action: 'close', label: t('Close'), key: keys.close },
  ];
  return (
    <ul className={`nz-fob__prompts nz-fob__prompts--${side}`}>
      {rows.map((r) =>
        onAction ? (
          <li key={r.action}>
            <button type="button" className="nz-fob__prompt" onClick={() => onAction(r.action)}>
              <span className="nz-fob__prompt-label">{r.label}</span>
              <kbd className="nz-fob__key">{r.key || '—'}</kbd>
            </button>
          </li>
        ) : (
          <li key={r.action} className="nz-fob__prompt">
            <span className="nz-fob__prompt-label">{r.label}</span>
            <kbd className="nz-fob__key">{r.key || '—'}</kbd>
          </li>
        ),
      )}
    </ul>
  );
}

function Caption({ fobKey }: { fobKey: FobHudKey }) {
  return (
    <div className="nz-fob__caption">
      {fobKey.locked != null && (
        <span className={`nz-fob__lock${fobKey.locked ? ' is-locked' : ''}`}>
          <Icon name={fobKey.locked ? 'lock' : 'unlock'} size={11} strokeWidth={2} />
        </span>
      )}
      <span className="nz-fob__name">{fobKey.label}</span>
      <PlateTag plate={fobKey.plate} size="sm" />
    </div>
  );
}

/* ───────────────────────────── edit mode ───────────────────────────── */

type Drag = { kind: 'move'; px: number; py: number; cx: number; cy: number } | { kind: 'resize'; ax: number; ay: number; sx: number; sy: number };

function EditOverlay({
  data, keys, prompts, setPrompts, onSave, onCancel, onAction,
}: {
  data: FobHudData; keys: FobKeyBinds; prompts: boolean; setPrompts: (on: boolean) => void;
  onSave: (l: FobLayout) => void; onCancel: () => void; onAction: (a: PromptAction) => void;
}) {
  const vp = useViewport();
  const fobKey = data.key;
  const aspect = fobAspect(fobKey?.design, fobKey?.kind);
  const [draft, setDraft] = useState<FobLayout>(data.layout);
  const [saving, setSaving] = useState(false);
  const drag = useRef<Drag | null>(null);
  const box = boxOf(draft, aspect, vp.w, vp.h);

  useEffect(() => setDraft(data.layout), [data.layout]);

  const setCenter = useCallback((cx: number, cy: number, scale: number) => {
    setDraft({ x: round(clamp(cx / vp.w, 0, 1)), y: round(clamp(cy / vp.h, 0, 1)), scale: round(clamp(scale, MIN_SCALE, MAX_SCALE), 2) });
  }, [vp.w, vp.h]);

  const onFramePointerDown = (e: ReactPointerEvent<HTMLDivElement>) => {
    if (e.button !== 0) return;
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    drag.current = { kind: 'move', px: e.clientX, py: e.clientY, cx: box.cx, cy: box.cy };
  };
  const onHandlePointerDown = (sx: number, sy: number) => (e: ReactPointerEvent<HTMLSpanElement>) => {
    if (e.button !== 0) return;
    e.stopPropagation();
    (e.currentTarget.parentElement as HTMLElement).setPointerCapture(e.pointerId);
    // the opposite corner stays where it is
    drag.current = { kind: 'resize', ax: box.cx - (sx * box.w) / 2, ay: box.cy - (sy * box.h) / 2, sx, sy };
  };
  const onPointerMove = (e: ReactPointerEvent<HTMLDivElement>) => {
    const d = drag.current;
    if (!d) return;
    if (d.kind === 'move') {
      setCenter(d.cx + e.clientX - d.px, d.cy + e.clientY - d.py, draft.scale);
      return;
    }
    const unit = BASE_H * (vp.h / 1080);
    const hFromY = Math.abs(e.clientY - d.ay);
    const hFromX = Math.abs(e.clientX - d.ax) / aspect;
    const h = clamp(Math.max(hFromY, hFromX), unit * MIN_SCALE, unit * MAX_SCALE);
    const w = h * aspect;
    setCenter(d.ax + (d.sx * w) / 2, d.ay + (d.sy * h) / 2, h / unit);
  };
  const onPointerUp = () => {
    drag.current = null;
  };

  // keyboard: arrows move, +/- resize, Enter saves
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement | null;
      if (target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA')) return;
      const step = e.shiftKey ? 0.02 : 0.005;
      let handled = true;
      if (e.key === 'ArrowLeft') setDraft((l) => ({ ...l, x: round(clamp(l.x - step, 0, 1)) }));
      else if (e.key === 'ArrowRight') setDraft((l) => ({ ...l, x: round(clamp(l.x + step, 0, 1)) }));
      else if (e.key === 'ArrowUp') setDraft((l) => ({ ...l, y: round(clamp(l.y - step, 0, 1)) }));
      else if (e.key === 'ArrowDown') setDraft((l) => ({ ...l, y: round(clamp(l.y + step, 0, 1)) }));
      else if (e.key === '+' || e.key === '=') setDraft((l) => ({ ...l, scale: round(clamp(l.scale + 0.05, MIN_SCALE, MAX_SCALE), 2) }));
      else if (e.key === '-' || e.key === '_') setDraft((l) => ({ ...l, scale: round(clamp(l.scale - 0.05, MIN_SCALE, MAX_SCALE), 2) }));
      else handled = false;
      if (handled) e.preventDefault();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const save = async () => {
    setSaving(true);
    onSave(draft);
  };
  useEffect(() => {
    if (data.mode !== 'edit') setSaving(false);
  }, [data.mode]);

  const side = box.cx > vp.w / 2 ? 'left' : 'right';
  // the panel goes to the half of the screen away from the fob
  const panelLeft = box.cx > vp.w / 2;
  const changed = draft.x !== data.layout.x || draft.y !== data.layout.y || draft.scale !== data.layout.scale;
  const isDefault = draft.x === data.defaults.x && draft.y === data.defaults.y && draft.scale === data.defaults.scale;

  return (
    <div className="nz-fob__edit-layer">
      <div
        className="nz-fob__frame"
        style={{ left: box.left - 8, top: box.top - 8, width: box.w + 16, height: box.h + 16 }}
        onPointerDown={onFramePointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
        aria-label={t('Drag to move the key fob')}
      >
        <div className="nz-fob__frame-art">
          <FobArt design={fobKey?.design} kind={fobKey?.kind} brand={fobKey?.make || null} size={box.h} />
        </div>
        {([[-1, -1], [1, -1], [-1, 1], [1, 1]] as const).map(([sx, sy]) => (
          <span
            key={`${sx}${sy}`}
            className={`nz-fob__handle nz-fob__handle--${sy < 0 ? 't' : 'b'}${sx < 0 ? 'l' : 'r'}`}
            onPointerDown={onHandlePointerDown(sx, sy)}
          />
        ))}
        <span className="nz-fob__size">{Math.round(draft.scale * 100)}%</span>
        {prompts && <SidePrompts keys={keys} side={side} onAction={onAction} />}
      </div>

      <Window
        title={t('Edit mode')}
        icon="sliders"
        subtitle={t('Key fob')}
        width={380}
        onClose={onCancel}
        className={`nz-fob__edit-panel${panelLeft ? ' is-left' : ' is-right'}`}
        footer={
          <div className="nz-fob__edit-foot">
            <KeyHint keys={['←', '→', '↑', '↓']} label={t('Nudge')} />
            <KeyHint keys={['+', '-']} label={t('Size')} />
            <KeyHint keys={['Esc']} label={t('Cancel')} />
          </div>
        }
      >
        <div className="nz-fob__edit-body">
          <p className="nz-fob__edit-text">
            {t('Drag the outlined fob to move it, or drag a corner to resize it. The position and size apply to every key you use.')}
          </p>
          <Toggle checked={prompts} onChange={setPrompts} label={t('Show keybind prompts')} description={t('Throw, Inspect, Move, Help and Close next to the fob')} />
          <div className="nz-fob__edit-actions">
            <Button variant="line" icon="refresh" disabled={isDefault} onClick={() => setDraft(data.defaults)}>
              {t('Reset')}
            </Button>
            <Button variant="teal" icon="save" loading={saving} disabled={!changed && !saving} onClick={save}>
              {t('Save')}
            </Button>
          </div>
        </div>
      </Window>
    </div>
  );
}

/* ───────────────────────────── help ───────────────────────────── */

function HelpWindow({ keys, onClose }: { keys: FobKeyBinds; onClose: () => void }) {
  const row = (k: string[], label: string, text: string) => (
    <div className="nz-fob__help-row">
      <KeyHint keys={k} label={label} size="md" />
      <p>{text}</p>
    </div>
  );
  return (
    <Window title={t('Key fob')} subtitle={t('Controls')} icon="key" width={560} onClose={onClose} className="nz-fob__help">
      <div className="nz-fob__help-body">
        <h3 className="nz-fob__h">{t('In your hand')}</h3>
        {row([keys.throw], t('Throw'), t('Aim at a player a few steps away and throw the key; they have a moment to catch it, a missed key lands on the ground. In the driver seat it goes out of the window (bikes and quads: beside you).'))}
        {row([keys.inspect], t('Inspect'), t('Look at the key: vehicle, plate and whether it still fits the locks.'))}
        {row([keys.move], t('Move'), t('Edit mode: drag the fob, resize it, turn the prompts on or off.'))}
        {row([keys.close || 'Esc'], t('Close'), t('Put the key away.'))}
        <h3 className="nz-fob__h">{t('On the ground')}</h3>
        {row(['E'], t('Place'), t('Put the key down where the outline shows it.'))}
        {row(['H'], t('Hold in hand'), t('Keep it in your hand instead (throw it from there).'))}
        {row(['Scroll'], t('Rotate'), t('Turn the key before you place it.'))}
        {row(['G'], t('Cancel'), t('Keep the key in your pocket.'))}
        <h3 className="nz-fob__h">{t('Keys you find')}</h3>
        <p className="nz-fob__help-text">{t('Walk up to a key on the ground and inspect it: keep it, or put it back for its owner.')}</p>
      </div>
    </Window>
  );
}

/* ───────────────────────────── inspect ───────────────────────────── */

const INSPECT_HOLD_S = 20;

function agoLabel(seconds: number): string {
  if (seconds < 60) return t('just now');
  const m = Math.floor(seconds / 60);
  if (m < 60) return t('{n} min ago', { n: m });
  return t('{n} h ago', { n: Math.floor(m / 60) });
}

function InspectWindow({ info, onClose }: { info: FobInspect; onClose: () => void }) {
  const [busy, setBusy] = useState<'keep' | 'return' | null>(null);
  const [held, setHeld] = useState(INSPECT_HOLD_S);
  const ground = info.source === 'ground' && !!info.id;

  useEffect(() => {
    if (!ground) return;
    setHeld(INSPECT_HOLD_S);
    const started = Date.now();
    const id = window.setInterval(() => setHeld(Math.max(0, INSPECT_HOLD_S - Math.floor((Date.now() - started) / 1000))), 500);
    return () => window.clearInterval(id);
  }, [ground, info.id]);

  const act = async (what: 'keep' | 'return') => {
    if (!info.id) return;
    setBusy(what);
    const res = await request(what === 'keep' ? 'fob:keep' : 'fob:return', { id: info.id });
    if (!res.ok) setBusy(null);
  };

  const origin = info.origin === 'locksmith' ? t('Back-alley copy') : info.origin === 'search' ? t('Spare key found in a vehicle') : null;
  return (
    <Window
      title={ground ? t('Key on the ground') : t('Your key')}
      subtitle={t('Inspect')}
      icon="key"
      width={600}
      onClose={ground ? () => void act('return') : onClose}
      closeLabel={ground ? t('Leave it') : undefined}
      className="nz-fob__inspect"
      footer={
        ground ? (
          <div className="nz-fob__inspect-foot">
            <span className={`nz-fob__held${held === 0 ? ' is-over' : ''}`}>
              <Icon name="clock" size={12} />
              {held > 0 ? t('Held for you · {s} s', { s: held }) : t('Anyone can pick it up again')}
            </span>
            <Button variant="line" icon="arrowLeft" disabled={!!busy} loading={busy === 'return'} onClick={() => void act('return')}>
              {t('Return to ground')}
            </Button>
            <Button variant="teal" icon="check" disabled={!!busy} loading={busy === 'keep'} onClick={() => void act('keep')}>
              {t('Keep')}
            </Button>
          </div>
        ) : (
          <div className="nz-fob__inspect-foot">
            <KeyHint keys={['Esc']} label={t('Close')} />
          </div>
        )
      }
    >
      <div className="nz-fob__inspect-body">
        <div className="nz-fob__stage">
          <span className="nz-fob__stage-glow" />
          <FobArt design={info.design} kind={info.kind} brand={info.make || null} size={232} className="nz-fob__stage-art" />
          <span className="nz-fob__stage-logo">
            <BrandLogo3D brand={info.make || null} size={104} />
          </span>
        </div>
        <div className="nz-fob__facts">
          <div className="nz-fob__eyebrow">{info.kind === 'fob' ? t('Electronic fob') : t('Metal key')}</div>
          <h2 className="nz-fob__vehicle">{info.vehicle || t('Unknown vehicle')}</h2>
          <div className="nz-fob__facts-plate">
            <PlateTag plate={info.plate} />
            {info.temp && <Badge tone="amber" icon="clock">{t('Temporary key')}</Badge>}
            {info.valid === true && <Badge tone="teal" icon="check">{t('Fits the locks')}</Badge>}
            {info.valid === false && <Badge tone="red" icon="ban">{t('Locks were changed')}</Badge>}
          </div>
          <dl className="nz-fob__list">
            <div>
              <dt>{t('Key')}</dt>
              <dd>{info.keyLabel}</dd>
            </div>
            {origin && (
              <div>
                <dt>{t('Origin')}</dt>
                <dd>{origin}</dd>
              </div>
            )}
            {info.droppedAgo != null && (
              <div>
                <dt>{t('On the ground')}</dt>
                <dd>{agoLabel(info.droppedAgo)}</dd>
              </div>
            )}
          </dl>
          {info.temp && <p className="nz-fob__note">{t('A key someone dropped and ran from: keeping it gives you a temporary key of this vehicle.')}</p>}
          {info.valid === false && <p className="nz-fob__note is-red">{t('This key was cut before the locks were changed and no longer opens the vehicle.')}</p>}
        </div>
      </div>
    </Window>
  );
}

/* ───────────────────────────── root ───────────────────────────── */

export function FobApp() {
  const app = useApp('fob');
  const data = app.data;
  const vp = useViewport();
  const [prompts, setPromptsState] = useState(readPrompts);
  const lit = usePressed(data?.press ?? null);
  const focused = !!data && app.open && data.mode !== 'hud';

  const setPrompts = (on: boolean) => {
    setPromptsState(on);
    writePrompts(on);
  };
  const cancel = useCallback(() => {
    void request('fob:cancel', {});
  }, []);
  useEscape(cancel, focused);

  const onAction = (action: PromptAction) => {
    if (action === 'close' || action === 'move') {
      cancel();
      return;
    }
    void request('fob:action', { action });
  };

  const fobKey = data?.key ?? null;
  const aspect = useMemo(() => fobAspect(fobKey?.design, fobKey?.kind), [fobKey?.design, fobKey?.kind]);
  if (!app.open || !data) return null;

  const box = boxOf(data.layout, aspect, vp.w, vp.h);
  const side = box.cx > vp.w / 2 ? 'left' : 'right';
  const showHud = data.mode === 'hud' || data.mode === 'help';

  return (
    <div className={`nz-fob${focused ? ' is-focused' : ''}`}>
      {showHud && fobKey && (
        <div className={`nz-fob__hud${data.holding ? ' is-holding' : ''}`} style={{ left: box.left, top: box.top, width: box.w, height: box.h }}>
          <FobArt design={fobKey.design} kind={fobKey.kind} brand={fobKey.make || null} size={box.h} active={lit} className="nz-fob__art" />
          {data.holding && prompts && <SidePrompts keys={data.keys} side={side} />}
          <Caption fobKey={fobKey} />
        </div>
      )}
      {data.mode === 'edit' && (
        <EditOverlay
          data={data}
          keys={data.keys}
          prompts={prompts}
          setPrompts={setPrompts}
          onCancel={cancel}
          onAction={onAction}
          onSave={(layout) => void request('fob:save', layout)}
        />
      )}
      {data.mode === 'help' && <HelpWindow keys={data.keys} onClose={cancel} />}
      {data.mode === 'inspect' && data.inspect && <InspectWindow info={data.inspect} onClose={cancel} />}
    </div>
  );
}
