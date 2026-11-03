/**
 * MapView — world-coordinate plot for admin location pages.
 *
 * API
 *   <MapView pins selectedId? hoverId? onSelect?(id) onHover?(id|null) focusTick? emptyText? className? />
 *   MapPin { id, x, y (world), label, sublabel?, muted? }
 *
 * - World box: x ∈ [-4000, 4500], y ∈ [-4200, 8200], north up (MAP_BOUNDS).
 * - No Rockstar art is shipped: the land is an original, simplified silhouette (with the Alamo
 *   Sea, a few highways and the Los Santos street texture) drawn on a dark grid.
 * - Owners may drop their own map at `web/dist/map.png` (`./map.png`): it is stretched over the
 *   exact world box above and replaces the silhouette; a missing file is silently ignored.
 * - Zoom: +/− buttons, mouse wheel (around the cursor), double click, keyboard +/−/0 and arrows.
 *   Pan: drag. Fit: the frame button. Pins are teal (muted = grey), hover/selected show a name
 *   tag; the selected pin is panned into view (and re-centred whenever `focusTick` changes).
 */
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import type { CSSProperties, KeyboardEvent, PointerEvent as ReactPointerEvent } from 'react';
import { IconButton, cx } from '@/components/ui';
import { t } from '@/lib/i18n';

export interface MapPin {
  id: string | number;
  x: number;
  y: number;
  label: string;
  sublabel?: string;
  muted?: boolean;
}

export interface MapViewProps {
  pins: MapPin[];
  selectedId?: string | number | null;
  hoverId?: string | number | null;
  onSelect?: (id: string | number) => void;
  onHover?: (id: string | number | null) => void;
  /** Change this number to re-centre the map on the selected pin. */
  focusTick?: number;
  emptyText?: string;
  className?: string;
}

export const MAP_BOUNDS = { minX: -4000, maxX: 4500, minY: -4200, maxY: 8200 };
const W = MAP_BOUNDS.maxX - MAP_BOUNDS.minX;
const H = MAP_BOUNDS.maxY - MAP_BOUNDS.minY;
const MIN_K = 1;
const MAX_K = 9;

/** World → map units (origin top-left, y down). */
const mx = (x: number) => x - MAP_BOUNDS.minX;
const my = (y: number) => MAP_BOUNDS.maxY - y;

type P = [number, number];

const pathOf = (pts: P[], closed = true) =>
  pts.map(([x, y], i) => `${i ? 'L' : 'M'}${Math.round(mx(x))} ${Math.round(my(y))}`).join('') + (closed ? 'Z' : '');

/* ── original stylised geography (world coordinates) ─────────────────── */

const LAND: P[] = [
  [-200, 7650], [250, 7600], [700, 7250], [1200, 6850], [1700, 6720], [2300, 6600], [2850, 6300], [3300, 5900],
  [3650, 5350], [3850, 4700], [3900, 4100], [3780, 3500], [3600, 2900], [3380, 2300], [3150, 1700], [2950, 1050],
  [2900, 400], [2800, -250], [2600, -900], [2300, -1500], [1900, -2050], [1550, -2450], [1400, -2900], [1250, -3300],
  [900, -3500], [450, -3420], [100, -3300], [-150, -3050], [-400, -3150], [-650, -3450], [-1000, -3650],
  [-1500, -3720], [-1950, -3550], [-2150, -3200], [-2050, -2850], [-1850, -2600], [-1650, -2250], [-1450, -1850],
  [-1600, -1450], [-1900, -1050], [-2150, -650], [-2500, -250], [-2900, 150], [-3200, 600], [-3350, 1100],
  [-3300, 1650], [-3150, 2250], [-2950, 2850], [-2700, 3350], [-2350, 3950], [-1950, 4550], [-1500, 5100],
  [-1050, 5650], [-650, 6200], [-450, 6800], [-500, 7300],
];

const LAKE: P[] = [
  [160, 4200], [400, 4040], [760, 3930], [1150, 3870], [1520, 3850], [1880, 3860], [2240, 3910], [2500, 4010],
  [2610, 4170], [2500, 4330], [2220, 4430], [1860, 4470], [1480, 4480], [1100, 4450], [740, 4400], [400, 4330],
];

const CITY: P[] = [
  [-1650, -2250], [-1400, -1800], [-1550, -1300], [-1900, -900], [-2050, -500], [-1400, 200], [-600, 350],
  [300, 250], [1200, 0], [1400, -700], [1450, -1800], [1300, -2400], [900, -3200], [100, -3250], [-400, -3100],
  [-900, -2700], [-1400, -2500],
];

const ROADS: P[][] = [
  [[-1800, -1000], [-2400, -350], [-3050, 400], [-3200, 1300], [-2900, 2500], [-2500, 3300], [-1900, 4300], [-1100, 5300],
    [-400, 6100], [300, 6500], [1100, 6450], [1900, 6350], [2600, 5900], [3100, 5100], [3250, 4300]],
  [[1200, -800], [2100, -300], [2500, 600], [2700, 1700], [2550, 2700], [2400, 3400], [2850, 3950], [3250, 4300]],
  [[-2650, 2700], [-1700, 2300], [-600, 2500], [400, 2650], [1200, 2650], [1900, 2850], [2550, 2900]],
  [[-1450, -500], [-500, -700], [500, -800], [1200, -800]],
  [[-200, 250], [100, -1900], [400, -2700]],
];

const LABELS: { text: () => string; x: number; y: number; water?: boolean }[] = [
  { text: () => t('Los Santos'), x: -350, y: -2550 },
  { text: () => t('Blaine County'), x: -650, y: 3150 },
  { text: () => t('Alamo Sea'), x: 1050, y: 4160, water: true },
  { text: () => t('Mount Chiliad'), x: 480, y: 5560 },
];

const CITY_LINES = (() => {
  const xs: number[] = [];
  const ys: number[] = [];
  for (let x = -2100; x <= 1500; x += 140) xs.push(x);
  for (let y = -3300; y <= 400; y += 140) ys.push(y);
  return { xs, ys };
})();

const GRID = (() => {
  const xs: number[] = [];
  const ys: number[] = [];
  for (let x = -4000; x <= 4500; x += 1000) xs.push(x);
  for (let y = -4000; y <= 8200; y += 1000) ys.push(y);
  return { xs, ys };
})();

/* ── component ───────────────────────────────────────────────────────── */

interface View {
  k: number;
  /** centre in map units */
  cx: number;
  cy: number;
}

const FIT: View = { k: 1, cx: W / 2 + 120, cy: H / 2 + 300 };

const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));
const fmt = (n: number) => Math.round(n).toLocaleString('en-US');

export function MapView({
  pins,
  selectedId = null,
  hoverId = null,
  onSelect,
  onHover,
  focusTick,
  emptyText,
  className,
}: MapViewProps) {
  const wrapRef = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ w: 0, h: 0 });
  const [view, setView] = useState<View>(FIT);
  const [easing, setEasing] = useState(false);
  const [dragging, setDragging] = useState(false);
  const [cursor, setCursor] = useState<{ x: number; y: number } | null>(null);
  const [image, setImage] = useState<'loading' | 'ok' | 'none'>('loading');
  const drag = useRef<{ x: number; y: number; cx: number; cy: number; moved: boolean; id: number } | null>(null);
  const easeTimer = useRef<number>();
  const viewRef = useRef(view);
  viewRef.current = view;

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

  useEffect(() => () => window.clearTimeout(easeTimer.current), []);

  /** px per map unit at k = 1 */
  const s0 = size.w && size.h ? Math.min(size.w / W, size.h / H) * 0.97 : 0;

  const clampView = useCallback((v: View): View => {
    const k = clamp(v.k, MIN_K, MAX_K);
    return { k, cx: clamp(v.cx, W * 0.08, W * 0.92), cy: clamp(v.cy, H * 0.06, H * 0.94) };
  }, []);

  const animateTo = useCallback(
    (v: View) => {
      window.clearTimeout(easeTimer.current);
      setEasing(true);
      setView(clampView(v));
      easeTimer.current = window.setTimeout(() => setEasing(false), 260);
    },
    [clampView],
  );

  const toScreen = useCallback(
    (ux: number, uy: number, v: View = viewRef.current) => ({
      x: size.w / 2 + (ux - v.cx) * s0 * v.k,
      y: size.h / 2 + (uy - v.cy) * s0 * v.k,
    }),
    [s0, size.w, size.h],
  );

  const toUnits = useCallback(
    (sx: number, sy: number, v: View = viewRef.current) => ({
      x: v.cx + (sx - size.w / 2) / (s0 * v.k),
      y: v.cy + (sy - size.h / 2) / (s0 * v.k),
    }),
    [s0, size.w, size.h],
  );

  const zoomAt = useCallback(
    (factor: number, sx?: number, sy?: number, animate = true) => {
      const v = viewRef.current;
      const k = clamp(v.k * factor, MIN_K, MAX_K);
      if (k === v.k) return;
      const px = sx ?? size.w / 2;
      const py = sy ?? size.h / 2;
      const anchor = toUnits(px, py, v);
      const next: View = {
        k,
        cx: anchor.x - (px - size.w / 2) / (s0 * k),
        cy: anchor.y - (py - size.h / 2) / (s0 * k),
      };
      if (animate) animateTo(next);
      else setView(clampView(next));
    },
    [animateTo, clampView, s0, size.w, size.h, toUnits],
  );

  // Native non-passive wheel listener (React's is passive).
  useEffect(() => {
    const el = wrapRef.current;
    if (!el || !s0) return;
    const onWheel = (e: WheelEvent) => {
      e.preventDefault();
      const rect = el.getBoundingClientRect();
      zoomAt(e.deltaY < 0 ? 1.25 : 0.8, e.clientX - rect.left, e.clientY - rect.top, false);
    };
    el.addEventListener('wheel', onWheel, { passive: false });
    return () => el.removeEventListener('wheel', onWheel);
  }, [s0, zoomAt]);

  /* keep the selected pin in view */
  const selected = useMemo(() => pins.find((p) => p.id === selectedId) ?? null, [pins, selectedId]);
  const lastFocus = useRef(focusTick);
  useEffect(() => {
    if (!selected || !s0) return;
    const force = focusTick !== lastFocus.current;
    lastFocus.current = focusTick;
    const ux = mx(selected.x);
    const uy = my(selected.y);
    const p = toScreen(ux, uy);
    const mxg = size.w * 0.14;
    const myg = size.h * 0.14;
    const outside = p.x < mxg || p.x > size.w - mxg || p.y < myg || p.y > size.h - myg;
    if (force || outside) {
      const v = viewRef.current;
      animateTo({ k: force ? Math.max(v.k, 2.4) : v.k, cx: ux, cy: uy });
    }
  }, [selected?.id, focusTick, s0]);

  /* pointer: drag to pan */
  const onPointerDown = (e: ReactPointerEvent<HTMLDivElement>) => {
    if (e.button !== 0) return;
    if ((e.target as HTMLElement).closest('button')) return;
    drag.current = { x: e.clientX, y: e.clientY, cx: view.cx, cy: view.cy, moved: false, id: e.pointerId };
  };

  const onPointerMove = (e: ReactPointerEvent<HTMLDivElement>) => {
    const rect = wrapRef.current?.getBoundingClientRect();
    if (rect && s0) {
      const u = toUnits(e.clientX - rect.left, e.clientY - rect.top);
      setCursor({ x: u.x + MAP_BOUNDS.minX, y: MAP_BOUNDS.maxY - u.y });
    }
    const d = drag.current;
    if (!d || !s0) return;
    const dx = e.clientX - d.x;
    const dy = e.clientY - d.y;
    if (!d.moved && Math.abs(dx) + Math.abs(dy) < 4) return;
    if (!d.moved) {
      d.moved = true;
      setDragging(true);
      wrapRef.current?.setPointerCapture(d.id);
    }
    setView((v) => clampView({ k: v.k, cx: d.cx - dx / (s0 * v.k), cy: d.cy - dy / (s0 * v.k) }));
  };

  const endDrag = () => {
    const d = drag.current;
    drag.current = null;
    if (d?.moved) {
      setDragging(false);
      try {
        wrapRef.current?.releasePointerCapture(d.id);
      } catch {
        /* already released */
      }
    }
  };

  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    if (!s0) return;
    const step = 80 / (s0 * view.k);
    const v = view;
    switch (e.key) {
      case '+':
      case '=':
        zoomAt(1.4);
        break;
      case '-':
      case '_':
        zoomAt(1 / 1.4);
        break;
      case '0':
        animateTo(FIT);
        break;
      case 'ArrowLeft':
        animateTo({ ...v, cx: v.cx - step });
        break;
      case 'ArrowRight':
        animateTo({ ...v, cx: v.cx + step });
        break;
      case 'ArrowUp':
        animateTo({ ...v, cy: v.cy - step });
        break;
      case 'ArrowDown':
        animateTo({ ...v, cy: v.cy + step });
        break;
      default:
        return;
    }
    e.preventDefault();
  };

  const world = s0
    ? (() => {
        const o = toScreen(0, 0);
        return { left: o.x, top: o.y, width: W * s0 * view.k, height: H * s0 * view.k };
      })()
    : null;

  // Draw order: muted pins under active ones (hover / selection stack with z-index only, so
  // hovering never moves DOM nodes under the cursor).
  const ordered = useMemo(() => [...pins].sort((a, b) => Number(!a.muted) - Number(!b.muted)), [pins]);

  return (
    <div
      ref={wrapRef}
      className={cx('nz-admin-map', easing && 'is-easing', dragging && 'is-dragging', className)}
      tabIndex={0}
      role="application"
      aria-label={t('Map of locations')}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={endDrag}
      onPointerCancel={endDrag}
      onPointerLeave={() => setCursor(null)}
      onDoubleClick={(e) => {
        if ((e.target as HTMLElement).closest('button')) return;
        const rect = wrapRef.current?.getBoundingClientRect();
        if (rect) zoomAt(1.8, e.clientX - rect.left, e.clientY - rect.top);
      }}
      onKeyDown={onKeyDown}
    >
      {world && (
        <div className="nz-admin-map__world" style={world as CSSProperties}>
          {image !== 'none' && (
            <img
              className={cx('nz-admin-map__img', image === 'ok' && 'is-on')}
              src="./map.png"
              alt=""
              draggable={false}
              onLoad={() => setImage('ok')}
              onError={() => setImage('none')}
            />
          )}
          <svg className="nz-admin-map__svg" viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" aria-hidden="true">
            <defs>
              <clipPath id="nz-admin-map-city">
                <path d={pathOf(CITY)} />
              </clipPath>
              <linearGradient id="nz-admin-map-land" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0" stopColor="#ffffff" stopOpacity=".05" />
                <stop offset="1" stopColor="#ffffff" stopOpacity=".075" />
              </linearGradient>
            </defs>
            <g className="nz-admin-map__grid">
              {GRID.xs.map((x) => (
                <line key={`gx${x}`} x1={mx(x)} y1={0} x2={mx(x)} y2={H} />
              ))}
              {GRID.ys.map((y) => (
                <line key={`gy${y}`} x1={0} y1={my(y)} x2={W} y2={my(y)} />
              ))}
            </g>
            {image !== 'ok' && (
              <g>
                <path className="nz-admin-map__coast" d={pathOf(LAND) + pathOf(LAKE)} fillRule="evenodd" />
                <path className="nz-admin-map__land" d={pathOf(LAND) + pathOf(LAKE)} fillRule="evenodd" fill="url(#nz-admin-map-land)" />
                <g className="nz-admin-map__city" clipPath="url(#nz-admin-map-city)">
                  {CITY_LINES.xs.map((x) => (
                    <line key={`cx${x}`} x1={mx(x)} y1={my(500)} x2={mx(x)} y2={my(-3400)} />
                  ))}
                  {CITY_LINES.ys.map((y) => (
                    <line key={`cy${y}`} x1={mx(-2200)} y1={my(y)} x2={mx(1600)} y2={my(y)} />
                  ))}
                </g>
                <g className="nz-admin-map__roads">
                  {ROADS.map((r, i) => (
                    <path key={i} d={pathOf(r, false)} />
                  ))}
                </g>
                <g className="nz-admin-map__peaks">
                  {[260, 520, 780].map((r) => (
                    <circle key={r} cx={mx(480)} cy={my(5560)} r={r} />
                  ))}
                </g>
              </g>
            )}
          </svg>
        </div>
      )}

      {world && image !== 'ok' && view.k < 3.2 && (
        <div className="nz-admin-map__labels" aria-hidden="true">
          {LABELS.map((l) => {
            const p = toScreen(mx(l.x), my(l.y));
            return (
              <span
                key={l.x}
                className={cx('nz-admin-map__region', l.water && 'is-water')}
                style={{ left: p.x, top: p.y }}
              >
                {l.text()}
              </span>
            );
          })}
        </div>
      )}

      {world &&
        ordered.map((pin) => {
          const p = toScreen(mx(pin.x), my(pin.y));
          const isSel = pin.id === selectedId;
          const isHover = pin.id === hoverId;
          return (
            <button
              key={pin.id}
              type="button"
              className={cx(
                'nz-admin-map__pin',
                pin.muted && 'is-muted',
                isSel && 'is-selected',
                isHover && 'is-hover',
                p.y < 64 && 'is-low',
              )}
              style={{ left: p.x, top: p.y }}
              aria-label={pin.label}
              aria-pressed={isSel}
              onClick={() => onSelect?.(pin.id)}
              onMouseEnter={() => onHover?.(pin.id)}
              onMouseLeave={() => onHover?.(null)}
              onFocus={() => onHover?.(pin.id)}
              onBlur={() => onHover?.(null)}
            >
              {isSel && <span className="nz-admin-map__pulse" />}
              <svg className="nz-admin-map__glyph" width="22" height="28" viewBox="0 0 22 28" aria-hidden="true">
                <path d="M11 1C5.5 1 1 5.3 1 10.7c0 6.9 8.4 15.3 9.3 16.1a1 1 0 0 0 1.4 0C12.6 26 21 17.6 21 10.7 21 5.3 16.5 1 11 1z" />
                <circle cx="11" cy="10.6" r="3.6" />
              </svg>
              {(isSel || isHover) && (
                <span className="nz-admin-map__tag">
                  <b>{pin.label}</b>
                  {pin.sublabel && <small>{pin.sublabel}</small>}
                </span>
              )}
            </button>
          );
        })}

      <span className="nz-admin-map__north" aria-hidden="true">
        <svg width="10" height="12" viewBox="0 0 10 12">
          <path d="M5 0 10 12 5 9 0 12z" />
        </svg>
        N
      </span>

      {pins.length === 0 && <div className="nz-admin-map__empty">{emptyText ?? t('No locations to show')}</div>}

      <div className="nz-admin-map__foot" aria-hidden="true">
        {cursor ? (
          <span className="nz-admin-map__coords">
            <span>X</span> {fmt(cursor.x)} <span>Y</span> {fmt(cursor.y)}
          </span>
        ) : (
          <span className="nz-admin-map__hint">{t('Drag to move · Scroll to zoom')}</span>
        )}
      </div>

      <div className="nz-admin-map__controls">
        <IconButton icon="plus" label={t('Zoom in')} size="sm" variant="line" tooltipSide="left" className="nz-admin-map__btn" disabled={view.k >= MAX_K} onClick={() => zoomAt(1.5)} />
        <IconButton icon="minus" label={t('Zoom out')} size="sm" variant="line" tooltipSide="left" className="nz-admin-map__btn" disabled={view.k <= MIN_K} onClick={() => zoomAt(1 / 1.5)} />
        <IconButton icon="map" label={t('Show whole map')} size="sm" variant="line" tooltipSide="left" className="nz-admin-map__btn" onClick={() => animateTo(FIT)} />
      </div>
    </div>
  );
}
