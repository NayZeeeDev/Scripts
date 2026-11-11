/**
 * Slowly spinning chrome 3D brand logo (web/public/brands/<slug>.glb) on a transparent
 * background, for the inspect card and the key ring detail pane. three.js is loaded lazily
 * (its own chunk, ./brandScene) the first time a logo is shown; until then, and whenever WebGL
 * or the model is not available, the 2D badge (png/<slug>.png) stands in. Unknown makes draw a
 * neutral emblem. The spin pauses while the logo is off screen and with reduced motion.
 */
import { useEffect, useRef, useState } from 'react';
import { brandBadgeUrl, brandModelUrl, brandName, brandSlug } from './brands';
import type { BrandScene } from './brandScene';
import './fob.css';

export interface BrandLogo3DProps {
  /** vehicle make in any form brandSlug() understands ('DINKA', 'Übermacht', 'vom-feuer') */
  brand?: string | null;
  /** square size in px */
  size?: number;
  /** false = a still pose */
  spin?: boolean;
  className?: string;
}

const reducedMotion = () =>
  typeof window.matchMedia === 'function' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

export function BrandLogo3D({ brand, size = 120, spin = true, className }: BrandLogo3DProps) {
  const slug = brandSlug(brand);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const wrapRef = useRef<HTMLSpanElement>(null);
  const sceneRef = useRef<BrandScene | null>(null);
  const [ready, setReady] = useState(false);
  const [badgeOk, setBadgeOk] = useState(true);
  const visibleRef = useRef(true);
  const spinRef = useRef(spin);
  spinRef.current = spin;

  // build the scene once per logo
  useEffect(() => {
    setReady(false);
    setBadgeOk(true);
    if (!slug || !canvasRef.current) return;
    let cancelled = false;
    const canvas = canvasRef.current;
    import('./brandScene')
      .then(({ createBrandScene }) => createBrandScene(canvas, brandModelUrl(slug), size))
      .then((scene) => {
        if (cancelled) {
          scene.dispose();
          return;
        }
        sceneRef.current = scene;
        scene.setSpinning(spinRef.current && visibleRef.current && !reducedMotion());
        setReady(true);
      })
      .catch(() => {
        /* no WebGL / model: the badge stays */
      });
    return () => {
      cancelled = true;
      sceneRef.current?.dispose();
      sceneRef.current = null;
    };
    // size changes are applied by the effect below without rebuilding the scene
  }, [slug]);

  useEffect(() => {
    sceneRef.current?.resize(size);
  }, [size, ready]);

  // pause off screen / in hidden documents
  useEffect(() => {
    const el = wrapRef.current;
    const apply = () => sceneRef.current?.setSpinning(spin && visibleRef.current && !document.hidden && !reducedMotion());
    apply();
    let io: IntersectionObserver | null = null;
    if (el && typeof IntersectionObserver !== 'undefined') {
      io = new IntersectionObserver((entries) => {
        visibleRef.current = entries.some((e) => e.isIntersecting);
        apply();
      });
      io.observe(el);
    }
    document.addEventListener('visibilitychange', apply);
    return () => {
      io?.disconnect();
      document.removeEventListener('visibilitychange', apply);
    };
  }, [spin, ready]);

  const label = slug ? brandName(slug) : undefined;
  return (
    <span
      ref={wrapRef}
      className={`nz-brand3d${ready ? ' is-ready' : ''}${className ? ` ${className}` : ''}`}
      style={{ width: size, height: size }}
      role="img"
      aria-label={label}
    >
      {slug ? (
        <>
          {badgeOk && (
            <img
              className="nz-brand3d__badge"
              src={brandBadgeUrl(slug)}
              alt=""
              draggable={false}
              onError={() => setBadgeOk(false)}
            />
          )}
          <canvas ref={canvasRef} className="nz-brand3d__canvas" />
        </>
      ) : (
        <span className="nz-brand3d__neutral" aria-hidden="true">
          <svg viewBox="-20 -20 40 40" width="100%" height="100%">
            <circle r="15" fill="none" strokeWidth="2" />
            <path d="M-4.5 -4.5 h9 v9 l-3.2 3.2 h-5.8 z" />
          </svg>
        </span>
      )}
    </span>
  );
}
