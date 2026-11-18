import { useEffect, useRef, useState } from 'react';
import { useStore } from '../lib/store';
import { post } from '../lib/nui';
import { captureFrame, releaseFrame } from '../lib/gameview';

/**
 * Black veil above everything. It is up from the very first paint, so the hand-off from the loading
 * screen is black -> black (never a hard cut or a flash of the world), and it dissolves over the live
 * scene when Lua lifts it. If it stays up for a moment (scene still streaming) a quiet wordmark + loader
 * fades in so the screen never looks frozen.
 */
export function Veil() {
  const veil = useStore((s) => s.veil);
  const cfg = useStore((s) => s.cfg);
  const [gone, setGone] = useState(false);
  const [slow, setSlow] = useState(false);

  useEffect(() => {
    if (veil.on) {
      setGone(false);
      const t = window.setTimeout(() => setSlow(true), 700);
      return () => window.clearTimeout(t);
    }
    const t = window.setTimeout(() => { setGone(true); setSlow(false); }, veil.ms + 50);
    return () => window.clearTimeout(t);
  }, [veil.on, veil.ms]);

  if (gone && !veil.on) return null;
  const name = cfg?.ui?.serverName;

  return (
    <div
      className="veil fixed inset-0 pointer-events-none"
      style={{
        opacity: veil.on ? 1 : 0,
        transition: `opacity ${veil.on ? 0 : veil.ms}ms cubic-bezier(.45,0,.2,1)`,
      }}
    >
      <div className="veil-mark" style={{ opacity: slow && veil.on && name ? 1 : 0 }}>
        {cfg?.ui?.logo
          ? <img src={cfg.ui.logo} alt="" className="max-h-[64px] max-w-[260px] object-contain mx-auto" />
          : <div className="display italic text-[44px] leading-none tracking-[.06em] text-white/90">{name}</div>}
        <div className="veil-bar"><i /></div>
      </div>
    </div>
  );
}

/**
 * Frozen frame of the game shown while Lua rebuilds a scene underneath, then crossfaded away.
 * Sits below the UI (panels stay live) and above the game.
 */
export function FreezeFrame() {
  const freeze = useStore((s) => s.freeze);
  const ref = useRef<HTMLCanvasElement>(null);
  const [shown, setShown] = useState(false);
  const [fading, setFading] = useState(false);

  // Capture as soon as Lua asks, and tell it whether it can rebuild under the frame
  useEffect(() => {
    if (!freeze || freeze.fading || !ref.current) return;
    let alive = true;
    setFading(false);
    captureFrame(ref.current).then((ok) => {
      if (!alive) return;
      setShown(ok);
      if (!ok) useStore.setState({ freeze: null });
      post('frozen', { id: freeze.id, ok });
    });
    return () => { alive = false; };
  }, [freeze?.id]);

  // Crossfade away, then release the frame
  useEffect(() => {
    if (!freeze?.fading) return;
    setFading(true);
    const t = window.setTimeout(() => {
      setShown(false);
      setFading(false);
      releaseFrame();
      useStore.setState({ freeze: null });
    }, freeze.ms + 60);
    return () => window.clearTimeout(t);
  }, [freeze?.fading]);

  // Lobby closed mid-freeze: drop it
  useEffect(() => { if (!freeze && shown) { setShown(false); releaseFrame(); } }, [freeze]);

  return (
    <canvas
      ref={ref}
      className="fixed inset-0 w-screen h-screen pointer-events-none"
      style={{
        visibility: shown ? 'visible' : 'hidden',
        opacity: shown && !fading ? 1 : 0,
        transition: fading ? `opacity ${freeze?.ms ?? 900}ms cubic-bezier(.45,0,.2,1)` : 'none',
      }}
    />
  );
}
