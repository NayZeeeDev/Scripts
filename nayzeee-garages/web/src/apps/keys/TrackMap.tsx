/**
 * Live map of the track vehicle modal, on the calibrated map images (web/public/maps,
 * docs/REDESIGN.md §4, geometry from the admin map: apps/admin/shared/mapGeo.ts). One scaled
 * image layer moved with a CSS transform: drag to pan, wheel / buttons to zoom, Recenter
 * follows the vehicle again. Markers: the vehicle (teal, heading arrow, pulse while live) and
 * the player. No per-frame work: the layer only moves when the data or the view changes.
 */
import { useEffect, useRef, useState } from 'react';
import type { PointerEvent, WheelEvent } from 'react';
import { Icon, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import { MAP_H, MAP_STYLES, MAP_W, readMapStyle, worldToImage, writeMapStyle } from '@/apps/admin/shared/mapGeo';
import type { MapStyle } from '@/apps/admin/shared/mapGeo';

const ZOOM_MIN = 0.6;
const ZOOM_MAX = 7;
const ZOOM_DEFAULT = 3.2;
const SEA: Record<MapStyle, string> = { satellite: '#143e6b', dark: '#394a51', atlas: '#1662ad' };

export interface TrackMapProps {
  /** world position of the vehicle, null = unknown */
  target: { x: number; y: number } | null;
  /** GTA heading of the vehicle (degrees, counter-clockwise from north) */
  heading: number | null;
  /** the player */
  me: { x: number; y: number } | null;
  live: boolean;
  /** dims the map with this message (no signal...) */
  veil?: { icon: 'warning' | 'info' | 'ban'; title: string; text?: string } | null;
  /** the position is an old one (signal lost) */
  stale?: boolean;
}

export function TrackMap({ target, heading, me, live, veil, stale }: TrackMapProps) {
  const boxRef = useRef<HTMLDivElement>(null);
  const [style, setStyle] = useState<MapStyle>(() => readMapStyle());
  const [zoom, setZoom] = useState(ZOOM_DEFAULT);
  // image px at the centre of the view; null = follow the vehicle (or the player)
  const [pan, setPan] = useState<{ x: number; y: number } | null>(null);
  const [size, setSize] = useState({ w: 640, h: 320 });
  const drag = useRef<{ x: number; y: number; from: { x: number; y: number }; moved: boolean } | null>(null);

  useEffect(() => {
    const el = boxRef.current;
    if (!el) return;
    const measure = () => setSize({ w: el.clientWidth || 640, h: el.clientHeight || 320 });
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const targetPx = target ? worldToImage(target.x, target.y) : null;
  const mePx = me ? worldToImage(me.x, me.y) : null;
  const follow = targetPx ?? mePx ?? { x: MAP_W * 0.46, y: MAP_H * 0.62 };
  const centre = pan ?? follow;
  const left = size.w / 2 - centre.x * zoom;
  const top = size.h / 2 - centre.y * zoom;

  const zoomBy = (f: number) => setZoom((z) => Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, z * f)));

  const onPointerDown = (e: PointerEvent<HTMLDivElement>) => {
    if (e.button !== 0) return;
    e.currentTarget.setPointerCapture?.(e.pointerId);
    drag.current = { x: e.clientX, y: e.clientY, from: centre, moved: false };
  };
  const onPointerMove = (e: PointerEvent<HTMLDivElement>) => {
    const d = drag.current;
    if (!d) return;
    const dx = e.clientX - d.x;
    const dy = e.clientY - d.y;
    if (!d.moved && Math.abs(dx) + Math.abs(dy) < 3) return;
    d.moved = true;
    setPan({
      x: Math.min(MAP_W, Math.max(0, d.from.x - dx / zoom)),
      y: Math.min(MAP_H, Math.max(0, d.from.y - dy / zoom)),
    });
  };
  const onPointerUp = () => {
    drag.current = null;
  };
  const onWheel = (e: WheelEvent<HTMLDivElement>) => {
    zoomBy(e.deltaY < 0 ? 1.2 : 1 / 1.2);
  };
  const pickStyle = (s: MapStyle) => {
    setStyle(s);
    writeMapStyle(s);
  };
  const src = MAP_STYLES.find((m) => m.value === style)?.src ?? './maps/dark.webp';
  // GTA heading turns counter-clockwise from north; CSS rotates clockwise
  const rot = heading !== null && Number.isFinite(heading) ? -heading : null;

  return (
    <div
      ref={boxRef}
      className={cx('nz-keys-map', drag.current?.moved && 'is-dragging')}
      style={{ background: SEA[style] }}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      onPointerCancel={onPointerUp}
      onWheel={onWheel}
    >
      {/* the image scales on the GPU; the markers sit on an unscaled layer (crisp at any zoom) */}
      <div className="nz-keys-map__layer" style={{ width: MAP_W, height: MAP_H, transform: `translate(${left}px, ${top}px) scale(${zoom})` }}>
        <img className="nz-keys-map__img" src={src} alt="" draggable={false} />
      </div>
      <div className="nz-keys-map__pins" style={{ transform: `translate(${left}px, ${top}px)` }}>
        {mePx && (
          <span className="nz-keys-map__me" style={{ left: mePx.x * zoom, top: mePx.y * zoom }} title={t('You')}>
            <i />
          </span>
        )}
        {targetPx && (
          <span
            className={cx('nz-keys-map__car', live && 'is-live', stale && 'is-stale')}
            style={{ left: targetPx.x * zoom, top: targetPx.y * zoom }}
          >
            <i className="nz-keys-map__pulse" />
            {rot !== null && <i className="nz-keys-map__dir" style={{ transform: `rotate(${rot}deg)` }} />}
            <i className="nz-keys-map__dot" />
          </span>
        )}
      </div>

      {veil && (
        <div className="nz-keys-map__veil">
          <Icon name={veil.icon} size={20} strokeWidth={1.6} />
          <b>{veil.title}</b>
          {veil.text && <span>{veil.text}</span>}
        </div>
      )}

      <div className="nz-keys-map__styles" role="group" aria-label={t('Map style')} onPointerDown={(e) => e.stopPropagation()}>
        {MAP_STYLES.map((m) => (
          <button key={m.value} type="button" className={cx(style === m.value && 'is-on')} onClick={() => pickStyle(m.value)}>
            {m.label()}
          </button>
        ))}
      </div>

      <div className="nz-keys-map__zoom" onPointerDown={(e) => e.stopPropagation()}>
        <button type="button" onClick={() => setPan(null)} title={t('Recenter')} aria-label={t('Recenter')} className={cx(pan === null && 'is-on')}>
          <Icon name="pin" size={14} strokeWidth={1.9} />
        </button>
        <button type="button" onClick={() => zoomBy(1.4)} title={t('Zoom in')} aria-label={t('Zoom in')}>
          <Icon name="plus" size={14} strokeWidth={2} />
        </button>
        <button type="button" onClick={() => zoomBy(1 / 1.4)} title={t('Zoom out')} aria-label={t('Zoom out')}>
          <Icon name="minus" size={14} strokeWidth={2} />
        </button>
      </div>
    </div>
  );
}
