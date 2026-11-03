/**
 * MapView — interactive world map of the admin location pages ("Map command").
 *
 * API
 *   <MapView pins selectedId? hoverId? onSelect?(id|null) onHover?(id|null) onActivate?(id)
 *            focusTick? bottomInset? distanceUnit? emptyText? className? />
 *   MapPin { id, x, y (world), label, type: VehicleType, muted?, meta?, stat? }
 *
 * - Built on the three calibrated images in web/public/maps (see mapGeo.ts). Style switcher
 *   (Satellite / Dark / Atlas) top-left, remembered per viewer; styles cross-fade.
 * - One view { k, cx, cy } (screen px per image px, image px at the viewport centre) drives
 *   both the image (a single GPU transform) and the pins (screen positions), so they never
 *   drift apart. Motion is JS-driven (rAF): fly-to (ease in-out, log-zoom), smooth wheel zoom
 *   around the cursor, drag to pan with a short fling. Reduced motion → instant.
 * - Controls top-right: Fit all, Reset, zoom −/+ with the zoom factor. Keyboard (map focused):
 *   + / − zoom, arrows pan, F fit all, 0 reset.
 * - Pins: type-coloured chamfer tiles with the vehicle-type icon on a stem + ground dot.
 *   Muted (disabled) pins are grey. Close pins cluster into a count bubble (click → zoom in);
 *   the selected / hovered pin never clusters. Selected: larger, pulse ring, name label.
 *   Hover: tooltip card (label, meta, stat). Click empty map → onSelect(null);
 *   double-click a pin → onActivate(id); double-click the map → zoom in there.
 * - bottomInset: px covered by an overlay at the bottom (the inspector). Bottom overlays
 *   (legend, scale, cursor coordinates) sit above it and focusing centres in the visible part.
 * - focusTick: change it to fly to the selected pin (zooming in to a moderate level).
 */
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import type { CSSProperties, KeyboardEvent, MouseEvent as ReactMouseEvent, PointerEvent as ReactPointerEvent, ReactNode } from 'react';
import { Icon, IconButton, Segmented, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { VehicleType } from '@/lib/types';
import { MAP_H, MAP_STYLES, MAP_W, IMAGE_PX_PER_WORLD, formatCoord, imageToWorld, readMapStyle, scaleBar, worldToImage, writeMapStyle } from './mapGeo';
import type { MapStyle } from './mapGeo';
import { vehicleTypeIcon, vehicleTypeLabel } from './labels';

type Id = string | number;

export interface MapPin {
  id: Id;
  x: number;
  y: number;
  label: string;
  type: VehicleType;
  /** Disabled location: grey pin, drawn under the others. */
  muted?: boolean;
  /** Tooltip second line, e.g. "Car · Public garage". */
  meta?: string;
  /** Tooltip third line, e.g. "46 parked · 9 out". */
  stat?: string;
}

export interface MapViewProps {
  pins: MapPin[];
  selectedId?: Id | null;
  hoverId?: Id | null;
  onSelect?: (id: Id | null) => void;
  onHover?: (id: Id | null) => void;
  /** Double-click on a pin. */
  onActivate?: (id: Id) => void;
  /** Change this number to fly to the selected pin. */
  focusTick?: number;
  /** Height in px covered by an overlay along the bottom edge (the inspector). */
  bottomInset?: number;
  distanceUnit?: 'km' | 'mi';
  emptyText?: ReactNode;
  className?: string;
}

interface View {
  k: number;
  cx: number;
  cy: number;
}

type Anim =
  | { kind: 'fly'; from: View; to: View; t0: number; dur: number; anchor?: { ix: number; iy: number; sx: number; sy: number } }
  | { kind: 'zoom'; target: number; ix: number; iy: number; sx: number; sy: number; last: number }
  | { kind: 'fling'; vx: number; vy: number; last: number };

/** Screen px per image px. The images are upscaled from smaller sources: beyond ~1.6 they blur. */
const MAX_K = 1.6;
/** Fit-all never zooms in further than this. */
const FIT_MAX_K = 0.62;
/** Flying to a selected location zooms in to at least this. */
const FOCUS_K = 0.72;
const CLUSTER_PX = 30;

const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));
const lerp = (a: number, b: number, p: number) => a + (b - a) * p;
const easeInOut = (p: number) => (p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2);
const easeOut = (p: number) => 1 - Math.pow(1 - p, 3);

const reducedMotion = () => {
  try {
    return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  } catch {
    return false;
  }
};

interface PlacedPin {
  pin: MapPin;
  ix: number;
  iy: number;
}

interface Cluster {
  key: string;
  ix: number;
  iy: number;
  members: PlacedPin[];
}

export function MapView({
  pins,
  selectedId = null,
  hoverId = null,
  onSelect,
  onHover,
  onActivate,
  focusTick,
  bottomInset = 0,
  distanceUnit = 'km',
  emptyText,
  className,
}: MapViewProps) {
  const wrapRef = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ w: 0, h: 0 });
  const [view, setViewState] = useState<View>({ k: 0, cx: MAP_W / 2, cy: MAP_H / 2 });
  const viewRef = useRef(view);
  const sizeRef = useRef(size);
  sizeRef.current = size;
  const insetRef = useRef(bottomInset);
  insetRef.current = bottomInset;
  const anim = useRef<Anim | null>(null);
  const raf = useRef(0);
  const [dragging, setDragging] = useState(false);
  const [cursor, setCursor] = useState<{ x: number; y: number } | null>(null);
  const [style, setStyle] = useState<MapStyle>(readMapStyle);
  const [mounted, setMounted] = useState<MapStyle[]>(() => [readMapStyle()]);
  const [loaded, setLoaded] = useState<Partial<Record<MapStyle, 'ok' | 'error'>>>({});
  const [shown, setShown] = useState<MapStyle | null>(null);
  const [clusterHover, setClusterHover] = useState<string | null>(null);
  const drag = useRef<{
    id: number;
    x: number;
    y: number;
    view: View;
    moved: boolean;
    samples: { t: number; x: number; y: number }[];
  } | null>(null);
  const suppressClick = useRef(false);

  /* ── size ── */
  useLayoutEffect(() => {
    const el = wrapRef.current;
    if (!el) return;
    const measure = () => setSize({ w: el.clientWidth, h: el.clientHeight });
    measure();
    if (typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  /** Whole image visible. */
  const fullK = size.w && size.h ? Math.min(size.w / MAP_W, size.h / MAP_H) : 0;
  const minK = fullK * 0.9;

  const clampView = useCallback(
    (v: View): View => {
      const { w, h } = sizeRef.current;
      const lo = Math.min(w / MAP_W, h / MAP_H) * 0.9;
      const k = clamp(v.k, lo, MAX_K);
      return { k, cx: clamp(v.cx, 0, MAP_W), cy: clamp(v.cy, 0, MAP_H) };
    },
    [],
  );

  const setView = useCallback(
    (v: View) => {
      const next = clampView(v);
      viewRef.current = next;
      setViewState(next);
    },
    [clampView],
  );

  /* ── animation loop ── */
  const tick = useCallback(
    (now: number) => {
      raf.current = 0;
      const a = anim.current;
      if (!a) return;
      const { w, h } = sizeRef.current;
      const v = viewRef.current;
      let next: View = v;
      let done = false;
      if (a.kind === 'fly') {
        const p = a.dur <= 0 ? 1 : clamp((now - a.t0) / a.dur, 0, 1);
        const e = a.anchor ? easeOut(p) : easeInOut(p);
        const k = Math.exp(lerp(Math.log(a.from.k), Math.log(a.to.k), e));
        if (a.anchor) {
          next = { k, cx: a.anchor.ix - (a.anchor.sx - w / 2) / k, cy: a.anchor.iy - (a.anchor.sy - h / 2) / k };
        } else {
          next = { k, cx: lerp(a.from.cx, a.to.cx, e), cy: lerp(a.from.cy, a.to.cy, e) };
        }
        done = p >= 1;
      } else if (a.kind === 'zoom') {
        const dt = Math.min(64, now - a.last);
        a.last = now;
        const f = 1 - Math.exp(-dt / 65);
        let k = Math.exp(lerp(Math.log(v.k), Math.log(a.target), f));
        if (Math.abs(Math.log(k / a.target)) < 0.003) {
          k = a.target;
          done = true;
        }
        next = { k, cx: a.ix - (a.sx - w / 2) / k, cy: a.iy - (a.sy - h / 2) / k };
      } else {
        const dt = Math.min(64, now - a.last);
        a.last = now;
        next = { k: v.k, cx: v.cx - (a.vx * dt) / v.k, cy: v.cy - (a.vy * dt) / v.k };
        const decay = Math.exp(-dt / 210);
        a.vx *= decay;
        a.vy *= decay;
        done = Math.hypot(a.vx, a.vy) < 0.015;
      }
      setView(next);
      if (done) anim.current = null;
      else raf.current = requestAnimationFrame(tick);
    },
    [setView],
  );

  const start = useCallback(
    (a: Anim) => {
      anim.current = a;
      if (!raf.current) raf.current = requestAnimationFrame(tick);
    },
    [tick],
  );

  const stop = useCallback(() => {
    anim.current = null;
    if (raf.current) cancelAnimationFrame(raf.current);
    raf.current = 0;
  }, []);

  useEffect(() => stop, [stop]);

  const flyTo = useCallback(
    (to: View, dur = 420, anchor?: { ix: number; iy: number; sx: number; sy: number }) => {
      const target = clampView(to);
      if (reducedMotion() || !viewRef.current.k) {
        stop();
        setView(target);
        return;
      }
      start({ kind: 'fly', from: viewRef.current, to: target, t0: performance.now(), dur, anchor });
    },
    [clampView, setView, start, stop],
  );

  /* ── placement ── */
  const placed = useMemo<PlacedPin[]>(
    () =>
      pins.map((pin) => {
        const p = worldToImage(pin.x, pin.y);
        return { pin, ix: p.x, iy: p.y };
      }),
    [pins],
  );

  /** View that fits the pins (or the whole map) into the area above the inset. */
  const fitView = useCallback(
    (list: PlacedPin[], maxK = FIT_MAX_K): View => {
      const { w, h } = sizeRef.current;
      const inset = insetRef.current;
      const vh = Math.max(120, h - inset);
      if (!list.length) return { k: Math.min(w / MAP_W, h / MAP_H), cx: MAP_W / 2, cy: MAP_H / 2 };
      let x0 = Infinity;
      let y0 = Infinity;
      let x1 = -Infinity;
      let y1 = -Infinity;
      for (const p of list) {
        x0 = Math.min(x0, p.ix);
        y0 = Math.min(y0, p.iy);
        x1 = Math.max(x1, p.ix);
        y1 = Math.max(y1, p.iy);
      }
      const padX = 70;
      const padTop = 74;
      const padBottom = 46;
      const bw = Math.max(x1 - x0, 1);
      const bh = Math.max(y1 - y0, 1);
      const lo = Math.min(w / MAP_W, h / MAP_H) * 0.9;
      const k = clamp(Math.min((w - padX * 2) / bw, (vh - padTop - padBottom) / bh), lo, maxK);
      // Centre of the box sits at the centre of the visible area (shifted for asymmetric padding).
      const cxImg = (x0 + x1) / 2;
      const cyImg = (y0 + y1) / 2;
      const visibleCentre = (padTop + (vh - padBottom)) / 2;
      return { k, cx: cxImg, cy: cyImg + (h / 2 - visibleCentre) / k };
    },
    [],
  );

  const fullView = useCallback((): View => {
    const { w, h } = sizeRef.current;
    return { k: Math.min(w / MAP_W, h / MAP_H), cx: MAP_W / 2, cy: MAP_H / 2 };
  }, []);

  // First measurement → fit everything (no animation).
  const initialised = useRef(false);
  useLayoutEffect(() => {
    if (!size.w || !size.h) return;
    if (!initialised.current) {
      initialised.current = true;
      setView(fitView(placed));
      return;
    }
    setView(viewRef.current);
  }, [size.w, size.h]);

  /* ── wheel (native: React's listener is passive) ── */
  useEffect(() => {
    const el = wrapRef.current;
    if (!el) return;
    const onWheel = (e: WheelEvent) => {
      e.preventDefault();
      const { w, h } = sizeRef.current;
      if (!w || !h) return;
      const rect = el.getBoundingClientRect();
      const sx = e.clientX - rect.left;
      const sy = e.clientY - rect.top;
      const unit = e.deltaMode === 1 ? 0.06 : e.deltaMode === 2 ? 1 : 0.0024;
      const factor = clamp(Math.exp(-e.deltaY * unit), 0.5, 2);
      const v = viewRef.current;
      const a = anim.current;
      const base = a && a.kind === 'zoom' ? a.target : v.k;
      const lo = Math.min(w / MAP_W, h / MAP_H) * 0.9;
      const target = clamp(base * factor, lo, MAX_K);
      const ix = v.cx + (sx - w / 2) / v.k;
      const iy = v.cy + (sy - h / 2) / v.k;
      if (reducedMotion()) {
        stop();
        setView({ k: target, cx: ix - (sx - w / 2) / target, cy: iy - (sy - h / 2) / target });
        return;
      }
      start({ kind: 'zoom', target, ix, iy, sx, sy, last: performance.now() });
    };
    el.addEventListener('wheel', onWheel, { passive: false });
    return () => el.removeEventListener('wheel', onWheel);
  }, [setView, start, stop]);

  const zoomBy = useCallback(
    (factor: number, sx?: number, sy?: number) => {
      const { w, h } = sizeRef.current;
      const v = viewRef.current;
      const px = sx ?? w / 2;
      const py = sy ?? h / 2;
      const ix = v.cx + (px - w / 2) / v.k;
      const iy = v.cy + (py - h / 2) / v.k;
      const k = clampView({ ...v, k: v.k * factor }).k;
      flyTo({ k, cx: ix - (px - w / 2) / k, cy: iy - (py - h / 2) / k }, 260, { ix, iy, sx: px, sy: py });
    },
    [clampView, flyTo],
  );

  /* ── focus the selected pin ── */
  const selected = useMemo(() => placed.find((p) => p.pin.id === selectedId) ?? null, [placed, selectedId]);
  const lastFocus = useRef(focusTick);
  useEffect(() => {
    if (!selected || !size.w || !viewRef.current.k) return;
    const force = focusTick !== lastFocus.current;
    lastFocus.current = focusTick;
    // Mid-flight (e.g. the inspector's height arrived during the fly): judge the destination.
    const running = anim.current;
    const v = running && running.kind === 'fly' ? running.to : viewRef.current;
    const { w, h } = size;
    const sx = w / 2 + (selected.ix - v.cx) * v.k;
    const sy = h / 2 + (selected.iy - v.cy) * v.k;
    const vh = h - bottomInset;
    const outside = sx < 60 || sx > w - 60 || sy < 70 || sy > vh - 40;
    if (!force && !outside) return;
    const k = force ? Math.max(v.k, Math.min(FOCUS_K, MAX_K)) : v.k;
    // Centre in the visible area (above the inspector).
    flyTo({ k, cx: selected.ix, cy: selected.iy + (h / 2 - vh / 2) / k }, force ? 560 : 380);
  }, [selected?.pin.id, focusTick, bottomInset, size.w, size.h]);

  /* ── pointer: drag to pan, click to deselect ── */
  const onPointerDown = (e: ReactPointerEvent<HTMLDivElement>) => {
    if (e.button !== 0) return;
    if ((e.target as HTMLElement).closest('.nz-admin-map__ui')) return;
    stop();
    suppressClick.current = false;
    drag.current = {
      id: e.pointerId,
      x: e.clientX,
      y: e.clientY,
      view: viewRef.current,
      moved: false,
      samples: [{ t: performance.now(), x: e.clientX, y: e.clientY }],
    };
  };

  const onPointerMove = (e: ReactPointerEvent<HTMLDivElement>) => {
    const el = wrapRef.current;
    const { w, h } = sizeRef.current;
    if (el && w) {
      const rect = el.getBoundingClientRect();
      const v = viewRef.current;
      const ix = v.cx + (e.clientX - rect.left - w / 2) / v.k;
      const iy = v.cy + (e.clientY - rect.top - h / 2) / v.k;
      setCursor(ix >= 0 && iy >= 0 && ix <= MAP_W && iy <= MAP_H ? imageToWorld(ix, iy) : null);
    }
    const d = drag.current;
    if (!d) return;
    const dx = e.clientX - d.x;
    const dy = e.clientY - d.y;
    if (!d.moved && Math.abs(dx) + Math.abs(dy) < 4) return;
    if (!d.moved) {
      d.moved = true;
      suppressClick.current = true;
      setDragging(true);
      try {
        el?.setPointerCapture(d.id);
      } catch {
        /* pointer already gone */
      }
      if (hoverId !== null) onHover?.(null);
    }
    const now = performance.now();
    d.samples.push({ t: now, x: e.clientX, y: e.clientY });
    if (d.samples.length > 6) d.samples.shift();
    setView({ k: d.view.k, cx: d.view.cx - dx / d.view.k, cy: d.view.cy - dy / d.view.k });
  };

  const endDrag = (e: ReactPointerEvent<HTMLDivElement>, cancelled = false) => {
    const d = drag.current;
    drag.current = null;
    if (!d) return;
    if (d.moved) {
      setDragging(false);
      try {
        wrapRef.current?.releasePointerCapture(d.id);
      } catch {
        /* already released */
      }
      const now = performance.now();
      const recent = d.samples.filter((s) => now - s.t < 90);
      if (!cancelled && recent.length >= 2 && !reducedMotion()) {
        const a = recent[0];
        const b = recent[recent.length - 1];
        const dt = Math.max(16, b.t - a.t);
        const vx = (b.x - a.x) / dt;
        const vy = (b.y - a.y) / dt;
        if (Math.hypot(vx, vy) > 0.25) start({ kind: 'fling', vx: clamp(vx, -3, 3), vy: clamp(vy, -3, 3), last: now });
      }
      return;
    }
    if (cancelled) return;
    // A plain click on the map surface (not on a pin / cluster) deselects.
    const target = e.target as HTMLElement;
    if (!target.closest('.nz-admin-map__pin, .nz-admin-map__cluster, .nz-admin-map__ui')) onSelect?.(null);
  };

  const onDoubleClick = (e: ReactMouseEvent<HTMLDivElement>) => {
    const target = e.target as HTMLElement;
    if (target.closest('.nz-admin-map__pin, .nz-admin-map__cluster, .nz-admin-map__ui')) return;
    const rect = wrapRef.current?.getBoundingClientRect();
    if (rect) zoomBy(2, e.clientX - rect.left, e.clientY - rect.top);
  };

  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    if (e.target !== e.currentTarget) return;
    const v = viewRef.current;
    const step = 90 / v.k;
    switch (e.key) {
      case '+':
      case '=':
        zoomBy(1.6);
        break;
      case '-':
      case '_':
        zoomBy(1 / 1.6);
        break;
      case '0':
        flyTo(fullView());
        break;
      case 'f':
      case 'F':
        flyTo(fitView(placed));
        break;
      case 'ArrowLeft':
        flyTo({ ...v, cx: v.cx - step }, 180);
        break;
      case 'ArrowRight':
        flyTo({ ...v, cx: v.cx + step }, 180);
        break;
      case 'ArrowUp':
        flyTo({ ...v, cy: v.cy - step }, 180);
        break;
      case 'ArrowDown':
        flyTo({ ...v, cy: v.cy + step }, 180);
        break;
      default:
        return;
    }
    e.preventDefault();
  };

  /* ── styles ── */
  const changeStyle = (s: MapStyle) => {
    setStyle(s);
    writeMapStyle(s);
    setMounted((m) => (m.includes(s) ? m : [...m, s]));
  };
  useEffect(() => {
    if (loaded[style]) setShown(style);
  }, [loaded, style]);

  /* ── clusters (image space, depends on zoom only) ── */
  const k = view.k;
  const clusters = useMemo(() => {
    const singles: PlacedPin[] = [];
    const groups: Cluster[] = [];
    if (!k) return { singles, groups };
    const r = CLUSTER_PX / k;
    const free = placed
      .filter((p) => p.pin.id !== selectedId && p.pin.id !== hoverId)
      .sort((a, b) => String(a.pin.id).localeCompare(String(b.pin.id), undefined, { numeric: true }));
    const used = new Set<Id>();
    for (const seed of free) {
      if (used.has(seed.pin.id)) continue;
      const members = free.filter((p) => !used.has(p.pin.id) && Math.hypot(p.ix - seed.ix, p.iy - seed.iy) <= r);
      members.forEach((m) => used.add(m.pin.id));
      if (members.length === 1) singles.push(seed);
      else {
        const ix = members.reduce((s, m) => s + m.ix, 0) / members.length;
        const iy = members.reduce((s, m) => s + m.iy, 0) / members.length;
        groups.push({ key: members.map((m) => String(m.pin.id)).join('-'), ix, iy, members });
      }
    }
    for (const p of placed) if (p.pin.id === selectedId || p.pin.id === hoverId) singles.push(p);
    return { singles, groups };
  }, [placed, k, selectedId, hoverId]);

  const { w, h } = size;
  const toScreen = (ix: number, iy: number) => ({ x: w / 2 + (ix - view.cx) * k, y: h / 2 + (iy - view.cy) * k });
  const onScreen = (s: { x: number; y: number }, m = 60) => s.x > -m && s.x < w + m && s.y > -m && s.y < h + m;

  // Draw order: muted first, then north → south so southern pins overlap like on paper.
  const singles = [...clusters.singles].sort(
    (a, b) => Number(!a.pin.muted) - Number(!b.pin.muted) || a.iy - b.iy,
  );

  const layerStyle: CSSProperties | undefined = k
    ? { transform: `translate3d(${w / 2 - view.cx * k}px, ${h / 2 - view.cy * k}px, 0) scale(${k})` }
    : undefined;

  const hovered = hoverId !== null ? placed.find((p) => p.pin.id === hoverId) ?? null : null;
  const hoverPos = hovered ? toScreen(hovered.ix, hovered.iy) : null;
  /** Cards sit beside the pin head (right, or left near the right edge), kept inside the map. */
  const cardSpot = (sx: number, sy: number, lift: number) => ({
    left: sx,
    top: clamp(sy - lift, 76, Math.max(76, h - bottomInset - 70)),
  });
  const hoveredCluster = clusterHover ? clusters.groups.find((g) => g.key === clusterHover) ?? null : null;

  const bar = k ? scaleBar(k * IMAGE_PX_PER_WORLD, distanceUnit) : null;
  const zoomFactor = fullK ? k / fullK : 1;
  const activeError = loaded[style] === 'error';

  const counts = useMemo(() => {
    const c = { car: 0, sea: 0, air: 0, off: 0 };
    for (const p of pins) {
      if (p.muted) c.off += 1;
      else c[p.type] += 1;
    }
    return c;
  }, [pins]);

  return (
    <div
      ref={wrapRef}
      className={cx('nz-admin-map', `is-${style}`, dragging && 'is-dragging', className)}
      style={{ '--map-inset': `${bottomInset}px` } as CSSProperties}
      tabIndex={0}
      role="application"
      aria-label={t('Map of locations')}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={(e) => endDrag(e)}
      onPointerCancel={(e) => endDrag(e, true)}
      onPointerLeave={() => setCursor(null)}
      onDoubleClick={onDoubleClick}
      onKeyDown={onKeyDown}
    >
      <div className="nz-admin-map__layer" style={layerStyle} aria-hidden="true">
        {mounted.map((s) => {
          const info = MAP_STYLES.find((m) => m.value === s)!;
          const on = loaded[s] === 'ok' && (s === style || (s === shown && loaded[style] !== 'ok'));
          return (
            <img
              key={s}
              className={cx('nz-admin-map__img', on && 'is-on', s === style && 'is-active')}
              src={info.src}
              alt=""
              width={MAP_W}
              height={MAP_H}
              draggable={false}
              decoding="async"
              onLoad={() => setLoaded((l) => ({ ...l, [s]: 'ok' }))}
              onError={() => setLoaded((l) => ({ ...l, [s]: 'error' }))}
            />
          );
        })}
      </div>
      <div className="nz-admin-map__shade" aria-hidden="true" />

      {/* clusters */}
      {k > 0 &&
        clusters.groups.map((g) => {
          const s = toScreen(g.ix, g.iy);
          if (!onScreen(s)) return null;
          const live = g.members.filter((m) => !m.pin.muted);
          const types = new Set(live.map((m) => m.pin.type));
          const tone = live.length === 0 ? 'off' : types.size === 1 ? [...types][0] : 'mixed';
          return (
            <button
              key={g.key}
              type="button"
              className={cx('nz-admin-map__cluster', `is-${tone}`)}
              style={{ transform: `translate3d(${s.x}px, ${s.y}px, 0)` }}
              aria-label={t('{count} locations here: zoom in', { count: g.members.length })}
              onMouseEnter={() => setClusterHover(g.key)}
              onMouseLeave={() => setClusterHover(null)}
              onClick={() => {
                if (suppressClick.current) return;
                setClusterHover(null);
                // Zoom in just enough to split the bubble (never past "fit these members").
                let d = Infinity;
                g.members.forEach((a, i) => g.members.slice(i + 1).forEach((b) => (d = Math.min(d, Math.hypot(a.ix - b.ix, a.iy - b.iy)))));
                const split = d > 0 && d < Infinity ? ((CLUSTER_PX + 18) / d) * 1.15 : MAX_K;
                const fit = fitView(g.members, MAX_K);
                const k = Math.min(fit.k, Math.max(viewRef.current.k * 1.8, split));
                const { h: vh0 } = sizeRef.current;
                const vh = vh0 - insetRef.current;
                flyTo({ k, cx: g.ix, cy: g.iy + (vh0 / 2 - vh / 2) / k });
              }}
            >
              <span className="nz-admin-map__cluster-ring" />
              <b>{g.members.length}</b>
            </button>
          );
        })}

      {/* pins */}
      {k > 0 &&
        singles.map(({ pin, ix, iy }) => {
          const s = toScreen(ix, iy);
          if (!onScreen(s)) return null;
          const isSel = pin.id === selectedId;
          const isHover = pin.id === hoverId;
          return (
            <button
              key={pin.id}
              type="button"
              className={cx(
                'nz-admin-map__pin',
                `is-${pin.type}`,
                pin.muted && 'is-muted',
                isSel && 'is-selected',
                isHover && 'is-hover',
              )}
              style={{ transform: `translate3d(${s.x}px, ${s.y}px, 0)` }}
              aria-label={pin.label}
              aria-pressed={isSel}
              onClick={() => {
                if (suppressClick.current) return;
                onSelect?.(pin.id);
              }}
              onDoubleClick={() => onActivate?.(pin.id)}
              onMouseEnter={() => !drag.current?.moved && onHover?.(pin.id)}
              onMouseLeave={() => onHover?.(null)}
              onFocus={() => onHover?.(pin.id)}
              onBlur={() => onHover?.(null)}
            >
              <span className="nz-admin-map__ground" />
              {isSel && <span className="nz-admin-map__pulse" />}
              <span className="nz-admin-map__stem" />
              <span className="nz-admin-map__tile">
                <Icon name={pin.muted ? 'ban' : vehicleTypeIcon(pin.type)} size={isSel ? 15 : 13} strokeWidth={2} />
              </span>
              {isSel && !isHover && <span className="nz-admin-map__name">{pin.label}</span>}
            </button>
          );
        })}

      {/* hover card */}
      {hovered && hoverPos && onScreen(hoverPos, 0) && !dragging && (
        <div
          className={cx('nz-admin-map__card', hoverPos.x > w - 300 && 'is-left', hovered.pin.id === selectedId && 'is-big')}
          style={cardSpot(hoverPos.x, hoverPos.y, hovered.pin.id === selectedId ? 31 : 26)}
          role="tooltip"
        >
          <b>{hovered.pin.label}</b>
          <span className="nz-admin-map__card-meta">
            <i className={cx('nz-admin-map__swatch', `is-${hovered.pin.muted ? 'off' : hovered.pin.type}`)} />
            {hovered.pin.meta ?? vehicleTypeLabel(hovered.pin.type)}
          </span>
          {hovered.pin.stat && <span className="nz-admin-map__card-stat">{hovered.pin.stat}</span>}
        </div>
      )}
      {hoveredCluster && !dragging && (() => {
        const s = toScreen(hoveredCluster.ix, hoveredCluster.iy);
        const names = hoveredCluster.members.map((m) => m.pin.label).sort((a, b) => a.localeCompare(b));
        return (
          <div
            className={cx('nz-admin-map__card', 'is-cluster', s.x > w - 300 && 'is-left')}
            style={cardSpot(s.x, s.y, 0)}
            role="tooltip"
          >
            <b>{t('{count} locations', { count: names.length })}</b>
            {names.slice(0, 4).map((n) => (
              <span key={n} className="nz-admin-map__card-meta">
                {n}
              </span>
            ))}
            {names.length > 4 && <span className="nz-admin-map__card-stat">{t('+{count} more', { count: names.length - 4 })}</span>}
            <span className="nz-admin-map__card-hint">{t('Click to zoom in')}</span>
          </div>
        );
      })()}

      {pins.length === 0 && (
        <div className="nz-admin-map__empty">
          <Icon name="pin" size={18} strokeWidth={1.6} />
          <span>{emptyText ?? t('No locations to show')}</span>
        </div>
      )}

      {activeError && (
        <div className="nz-admin-map__missing">
          <Icon name="warning" size={13} strokeWidth={1.8} />
          {t('Map image not found: rebuild the interface (web/dist/maps)')}
        </div>
      )}

      {/* ── overlays ── */}
      <div className="nz-admin-map__ui nz-admin-map__styles">
        <Segmented<MapStyle>
          size="sm"
          value={style}
          onChange={changeStyle}
          options={MAP_STYLES.map((m) => ({ value: m.value, label: m.label() }))}
        />
      </div>

      <div className="nz-admin-map__ui nz-admin-map__controls">
        <button type="button" className="nz-admin-map__ctl" onClick={() => flyTo(fitView(placed))} disabled={!pins.length}>
          <Icon name="pin" size={13} strokeWidth={1.8} />
          <span>{t('Fit all')}</span>
        </button>
        <button type="button" className="nz-admin-map__ctl" onClick={() => flyTo(fullView())}>
          <Icon name="map" size={13} strokeWidth={1.8} />
          <span>{t('Reset')}</span>
        </button>
        <span className="nz-admin-map__zoom">
          <IconButton icon="minus" label={t('Zoom out')} size="sm" tooltipSide="bottom" disabled={k <= minK * 1.001} onClick={() => zoomBy(1 / 1.6)} />
          <span className="nz-admin-map__zoom-val">{zoomFactor.toFixed(1)}×</span>
          <IconButton icon="plus" label={t('Zoom in')} size="sm" tooltipSide="bottom" disabled={k >= MAX_K * 0.999} onClick={() => zoomBy(1.6)} />
        </span>
      </div>

      {pins.length > 0 && (
      <div className="nz-admin-map__ui nz-admin-map__legend" aria-label={t('Legend')}>
        {(['car', 'sea', 'air'] as VehicleType[]).map((vt) => (
          <span key={vt} className={cx('nz-admin-map__legend-item', !counts[vt] && 'is-zero')}>
            <i className={cx('nz-admin-map__swatch', `is-${vt}`)} />
            {vehicleTypeLabel(vt)}
            <em>{counts[vt]}</em>
          </span>
        ))}
        <span className={cx('nz-admin-map__legend-item', !counts.off && 'is-zero')}>
          <i className="nz-admin-map__swatch is-off" />
          {t('Disabled')}
          <em>{counts.off}</em>
        </span>
      </div>
      )}

      <div className="nz-admin-map__ui nz-admin-map__readout" aria-live="off">
        {bar && (
          <span className="nz-admin-map__scale">
            <i style={{ width: Math.round(bar.px) }} />
            {bar.label}
          </span>
        )}
        <span className={cx('nz-admin-map__coords', !cursor && 'is-idle')}>
          {cursor ? (
            <>
              <span>X</span> {formatCoord(cursor.x)} <span className="nz-admin-map__dot">·</span> <span>Y</span> {formatCoord(cursor.y)}
            </>
          ) : (
            t('Drag to pan · Scroll to zoom')
          )}
        </span>
      </div>
    </div>
  );
}
