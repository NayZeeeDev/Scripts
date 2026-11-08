/**
 * 3D preview of the selected vehicle (client/preview.lua): Lua spawns a local copy of the car
 * at a hidden studio spot and points a scripted camera at it, framed inside the stage box this
 * hook reports ('garage:previewRect'). While Lua says the car is on screen (`live`), the stage
 * and the window behind it turn transparent so the game render shows through, and a veil dims
 * the rest of the screen around the window (the camera shows the studio there, not the
 * player). Otherwise — browser dev harness, preview turned off, model / data not loadable —
 * the stage keeps drawing the vehicle image.
 */
import { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react';
import type { CSSProperties } from 'react';
import { fetchNui, request } from '@/lib/nui';
import { useSettings } from '@/lib/store';
import type { PreviewRect } from '@/lib/types';

export interface PreviewTarget {
  plate?: string;
  index?: number;
}

interface StageBox {
  left: number;
  top: number;
  width: number;
  height: number;
}

export interface PreviewState {
  /** The car is rendered by the game behind the stage. */
  live: boolean;
  /** A preview request is on its way (first load or swap). */
  loading: boolean;
  /** Attach to the stage root (measured for the camera framing and the veil). */
  stageRef: (el: HTMLDivElement | null) => void;
  /** Stage rectangle on screen (for the veil), null until measured. */
  box: StageBox | null;
}

const idle: PreviewState = { live: false, loading: false, stageRef: () => undefined, box: null };

/** Read by <Stage>: whether to go transparent, and where to report its size. */
export const PreviewContext = createContext<PreviewState>(idle);
export const usePreviewStage = () => useContext(PreviewContext);

/**
 * Car box inside the stage, in px: the class tag / favourite row at the top and the title +
 * plate strip at the bottom stay clear of the car; 5% each side.
 */
const BOX_TOP = 46;
const BOX_BOTTOM = 70;
const BOX_SIDE = 0.05;
/** Arrow keys move the selection quickly: only ask Lua once the selection rests. */
const DEBOUNCE = 160;
/** After Lua ended the preview on its own (downed, …): ask again this often, this many
 * times, until it shows (revived with the menu still open) — Lua answers shown = false while
 * the player is still down. */
const STOP_RETRY = 1500;
const STOP_RETRIES = 40;
/** Short stages (720p): the class tag and title strip get thinner insets. */
const SHORT_STAGE = 220;
const SHORT_TOP = 40;
const SHORT_BOTTOM = 62;

const keyOf = (t: PreviewTarget | null) =>
  !t ? '' : t.plate ? `p:${t.plate}` : typeof t.index === 'number' ? `s:${t.index}` : '';

function carBox(el: HTMLElement): PreviewRect | null {
  const r = el.getBoundingClientRect();
  if (r.width < 40 || r.height < 40) return null;
  let top = BOX_TOP;
  let bottom = BOX_BOTTOM;
  if (r.height < SHORT_STAGE) {
    // keep the tag row and the title strip clear even if the car box gets short:
    // the Lua framing fits any box, a short one just gives a smaller car
    top = SHORT_TOP;
    bottom = SHORT_BOTTOM;
  } else if (r.height - top - bottom < r.height * 0.4) {
    top = r.height * 0.12;
    bottom = r.height * 0.22;
  }
  if (r.height - top - bottom < 24) return null;
  const side = r.width * BOX_SIDE;
  return {
    x: Math.round(r.left + side),
    y: Math.round(r.top + top),
    w: Math.round(r.width - side * 2),
    h: Math.round(r.height - top - bottom),
    vw: window.innerWidth,
    vh: window.innerHeight,
    dpr: window.devicePixelRatio || 1,
  };
}

/**
 * Drives the preview for one showroom window. `target` = the selected vehicle (null when the
 * selection shows nothing 3D: empty showroom, ghost vehicle). `stopSignal` = the app data's
 * `previewStopped` (Lua ended the preview on its own).
 */
export function useVehiclePreview(
  app: 'garage' | 'impound',
  target: PreviewTarget | null,
  stopSignal: number | undefined,
): PreviewState {
  const [live, setLive] = useState(false);
  const [loading, setLoading] = useState(false);
  const [disabled, setDisabled] = useState(false);
  const [retry, setRetry] = useState(0);
  const previewSetting = useSettings().vehiclePreview;
  const retriesLeft = useRef(0);
  const retryTimer = useRef<number | undefined>(undefined);
  const [stage, setStage] = useState<HTMLDivElement | null>(null);
  const [box, setBox] = useState<StageBox | null>(null);
  const seq = useRef(0);
  const rect = useRef<PreviewRect | null>(null);
  const sentRect = useRef('');
  const key = keyOf(target);

  /* ── stage rectangle → Lua (camera framing) and the veil ── */
  const measure = useCallback(() => {
    if (!stage) return;
    const r = stage.getBoundingClientRect();
    setBox((prev) =>
      prev && prev.left === r.left && prev.top === r.top && prev.width === r.width && prev.height === r.height
        ? prev
        : { left: r.left, top: r.top, width: r.width, height: r.height },
    );
    const next = carBox(stage);
    if (!next) return;
    rect.current = next;
    const sig = `${next.x},${next.y},${next.w},${next.h},${next.vw},${next.vh}`;
    if (sig === sentRect.current) return;
    sentRect.current = sig;
    void fetchNui('garage:previewRect', next);
  }, [stage]);

  useEffect(() => {
    if (!stage) return;
    measure();
    const ro = typeof ResizeObserver !== 'undefined' ? new ResizeObserver(measure) : null;
    ro?.observe(stage);
    window.addEventListener('resize', measure);
    // the window slides in: measure again once it has settled
    const t1 = window.setTimeout(measure, 260);
    const t2 = window.setTimeout(measure, 700);
    return () => {
      ro?.disconnect();
      window.removeEventListener('resize', measure);
      window.clearTimeout(t1);
      window.clearTimeout(t2);
    };
  }, [stage, measure]);

  /* ── the setting or the window changed: a 'disabled' answer may no longer hold ── */
  useEffect(() => {
    setDisabled(false);
  }, [app, previewSetting]);

  /* ── selection → Lua ── */
  useEffect(() => {
    if (disabled) return;
    const my = ++seq.current;
    if (!key) {
      setLoading(false);
      setLive(false);
      void fetchNui('garage:preview', { app });
      return;
    }
    setLoading(true);
    const timer = window.setTimeout(async () => {
      const res = await request(
        'garage:preview',
        { app, plate: target?.plate, index: target?.plate ? undefined : target?.index, rect: rect.current ?? undefined },
        { toastError: false },
      );
      if (my !== seq.current) return;
      setLoading(false);
      if (!res.ok || !res.data) {
        setLive(false);
        return;
      }
      if (res.data.stale) return;
      if (res.data.disabled) setDisabled(true);
      const shown = res.data.shown === true;
      setLive(shown);
      if (shown || res.data.disabled) retriesLeft.current = 0;
      else if (retriesLeft.current > 0) {
        retriesLeft.current--;
        window.clearTimeout(retryTimer.current);
        retryTimer.current = window.setTimeout(() => setRetry((n) => n + 1), STOP_RETRY);
      }
    }, DEBOUNCE);
    return () => window.clearTimeout(timer);
    // target fields are folded into `key`
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [app, key, disabled, retry]);

  /* ── Lua ended it (death, …) ── */
  const lastStop = useRef(stopSignal);
  useEffect(() => {
    if (stopSignal === undefined || stopSignal === lastStop.current) return;
    lastStop.current = stopSignal;
    seq.current++;
    setLive(false);
    setLoading(false);
    retriesLeft.current = STOP_RETRIES;
    window.clearTimeout(retryTimer.current);
    retryTimer.current = window.setTimeout(() => setRetry((n) => n + 1), STOP_RETRY);
  }, [stopSignal]);
  useEffect(() => () => window.clearTimeout(retryTimer.current), []);

  /* ── window closed: Lua cleans up on close too; this covers a re-keyed window ── */
  useEffect(
    () => () => {
      seq.current++;
      void fetchNui('garage:preview', { app });
    },
    [app],
  );

  return { live: live && !disabled, loading: loading && live, stageRef: setStage, box };
}

/**
 * Dims everything around the stage while the preview is live: the scripted camera fills the
 * whole screen with the studio, so only the stage hole may show it. Sits under the window.
 */
export function PreviewVeil({ state }: { state: PreviewState }) {
  if (!state.box) return null;
  const style: CSSProperties = {
    left: state.box.left,
    top: state.box.top,
    width: state.box.width,
    height: state.box.height,
  };
  return <div className={`nz-garage-veil${state.live ? ' is-on' : ''}`} style={style} aria-hidden="true" />;
}
