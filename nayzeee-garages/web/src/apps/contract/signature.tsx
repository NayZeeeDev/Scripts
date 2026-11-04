/**
 * Signature pad + read-only signature. A signature is SVG path data in a 400x140 box
 * ("M x y L x y ..." with whole numbers, at most 4000 characters): exactly what the server
 * accepts and rebuilds (server/contracts.lua cleanSignature).
 */
import { useRef, useState } from 'react';
import type { PointerEvent as ReactPointerEvent } from 'react';
import clsx from 'clsx';
import { t } from '@/lib/i18n';

export const SIG_W = 400;
export const SIG_H = 140;
export const SIG_MAX = 4000;
/** Total stroke length (pad units) the server asks for: a dot or a tick is not a signature. */
export const MIN_INK = 48;
/** Pad units between two kept points (keeps the path short and smooth). */
const MIN_STEP = 2.4;

export type Stroke = [number, number][];

export function strokesToPath(strokes: Stroke[]): string {
  let out = '';
  for (const stroke of strokes) {
    if (stroke.length < 2) continue;
    stroke.forEach(([x, y], i) => {
      out += `${i === 0 ? 'M' : 'L'}${x} ${y}`;
    });
  }
  return out;
}

export function inkLength(strokes: Stroke[]): number {
  let ink = 0;
  for (const stroke of strokes) {
    for (let i = 1; i < stroke.length; i++) {
      ink += Math.hypot(stroke[i][0] - stroke[i - 1][0], stroke[i][1] - stroke[i - 1][1]);
    }
  }
  return ink;
}

/** A signature the server will accept. */
export function signatureReady(strokes: Stroke[]): boolean {
  return inkLength(strokes) >= MIN_INK && strokesToPath(strokes).length <= SIG_MAX;
}

/** Only M / L commands with numbers inside the box are drawn (data from item metadata). */
function safePath(path: string): string {
  if (typeof path !== 'string' || path.length > SIG_MAX) return '';
  return /^[ML0-9 .,-]*$/.test(path) ? path : '';
}

/* ── read-only ─────────────────────────────────────────────────────────── */

export function SignatureView({ path, className }: { path: string; className?: string }) {
  const d = safePath(path);
  return (
    <svg className={clsx('nz-contract__sig-svg', className)} viewBox={`0 0 ${SIG_W} ${SIG_H}`} aria-hidden="true">
      {d && <path className="nz-contract__ink" d={d} />}
    </svg>
  );
}

/* ── pad ───────────────────────────────────────────────────────────────── */

export interface SignaturePadProps {
  strokes: Stroke[];
  onChange: (strokes: Stroke[]) => void;
  disabled?: boolean;
  /** shown in the empty pad */
  placeholder?: string;
}

export function SignaturePad({ strokes, onChange, disabled = false, placeholder }: SignaturePadProps) {
  const svg = useRef<SVGSVGElement>(null);
  const drawing = useRef(false);
  // pointer events can arrive faster than renders: always build on the newest strokes
  const latest = useRef(strokes);
  latest.current = strokes;
  const [full, setFull] = useState(false);
  const empty = strokes.length === 0;

  const commit = (next: Stroke[]) => {
    latest.current = next;
    onChange(next);
  };

  const point = (e: ReactPointerEvent<SVGSVGElement>): [number, number] => {
    const rect = svg.current!.getBoundingClientRect();
    const x = ((e.clientX - rect.left) / Math.max(rect.width, 1)) * SIG_W;
    const y = ((e.clientY - rect.top) / Math.max(rect.height, 1)) * SIG_H;
    return [Math.round(Math.max(0, Math.min(SIG_W, x))), Math.round(Math.max(0, Math.min(SIG_H, y)))];
  };

  const onDown = (e: ReactPointerEvent<SVGSVGElement>) => {
    if (disabled || e.button !== 0) return;
    e.preventDefault();
    const next = [...latest.current, [point(e)] as Stroke];
    if (strokesToPath(next).length + 12 > SIG_MAX) {
      setFull(true);
      return;
    }
    svg.current?.setPointerCapture(e.pointerId);
    drawing.current = true;
    commit(next);
  };

  const onMove = (e: ReactPointerEvent<SVGSVGElement>) => {
    if (!drawing.current || disabled) return;
    const p = point(e);
    const all = latest.current;
    const current = all[all.length - 1];
    if (!current) return;
    const last = current[current.length - 1];
    if (Math.hypot(p[0] - last[0], p[1] - last[1]) < MIN_STEP) return;
    const next = [...all.slice(0, -1), [...current, p] as Stroke];
    if (strokesToPath(next).length > SIG_MAX) {
      drawing.current = false;
      setFull(true);
      return;
    }
    commit(next);
  };

  const onUp = (e: ReactPointerEvent<SVGSVGElement>) => {
    if (!drawing.current) return;
    drawing.current = false;
    if (svg.current?.hasPointerCapture(e.pointerId)) svg.current.releasePointerCapture(e.pointerId);
    // a single click leaves a one-point stroke: drop it
    const all = latest.current;
    const current = all[all.length - 1];
    if (current && current.length < 2) commit(all.slice(0, -1));
  };

  const clear = () => {
    setFull(false);
    commit([]);
  };

  return (
    <div className={clsx('nz-contract__pad', disabled && 'is-disabled', !empty && 'has-ink')}>
      <svg
        ref={svg}
        className="nz-contract__sig-svg nz-contract__pad-svg"
        viewBox={`0 0 ${SIG_W} ${SIG_H}`}
        onPointerDown={onDown}
        onPointerMove={onMove}
        onPointerUp={onUp}
        onPointerCancel={onUp}
        role="img"
        aria-label={t('Signature pad')}
      >
        <path className="nz-contract__ink" d={strokesToPath(strokes)} />
      </svg>
      {empty && !disabled && (
        <span className="nz-contract__pad-hint" aria-hidden="true">
          {placeholder ?? t('Sign here')}
        </span>
      )}
      {!empty && !disabled && (
        <button type="button" className="nz-contract__pad-clear" onClick={clear}>
          {t('Clear')}
        </button>
      )}
      {full && <span className="nz-contract__pad-full">{t('The pad is full: clear it and sign a little smaller')}</span>}
    </div>
  );
}
