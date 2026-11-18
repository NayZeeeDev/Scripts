import { createContext, lazy, Suspense, useContext, useEffect, useState, type ReactNode } from 'react';
import { useStore } from './lib/store';
import { IS_MOCK } from './lib/nui';
import { cx } from './components/ui';
import StartScreen from './screens/StartScreen';
import Lobby from './screens/Lobby';
import Create from './screens/Create';
import Spawn from './screens/Spawn';
import Cutscene from './screens/Cutscene';
import Overlays from './screens/Overlays';
import Plates from './screens/Plates';

const DevTools = IS_MOCK ? lazy(() => import('./dev/DevTools')) : null;

const BASE_W = 1920;
const BASE_H = 1080;

export const StageCtx = createContext({ W: BASE_W, H: BASE_H });
export const useStage = () => useContext(StageCtx);

function Stage({ children }: { children: ReactNode }) {
  const cfgScale = useStore((s) => s.cfg?.ui?.scale ?? 1);
  const userScale = useStore((s) => s.settings.scale ?? 1);
  const [win, setWin] = useState({ w: window.innerWidth, h: window.innerHeight });

  useEffect(() => {
    const on = () => setWin({ w: window.innerWidth, h: window.innerHeight });
    window.addEventListener('resize', on);
    return () => window.removeEventListener('resize', on);
  }, []);

  // Fit 1920x1080 into the window (keep aspect), then apply config + user scale.
  // The stage itself spans the whole window so edge-anchored panels hug the real edges on ultrawide.
  const s = Math.min(win.w / BASE_W, win.h / BASE_H) * cfgScale * userScale;
  const W = win.w / s;
  const H = win.h / s;

  return (
    <StageCtx.Provider value={{ W, H }}>
      <div
        className="absolute left-0 top-0 origin-top-left overflow-hidden"
        style={{ width: W, height: H, transform: `scale(${s})` }}
      >
        {children}
      </div>
    </StageCtx.Provider>
  );
}

export default function App() {
  const ready = useStore((s) => !!s.cfg);
  const view = useStore((s) => s.view);
  const perf = useStore((s) => s.settings.perf);

  useEffect(() => {
    if (!IS_MOCK) return;
    const bg = new URLSearchParams(location.search).get('bg');
    const b = document.body.style;
    // Dev preview backdrop only (never in game): a photo via ?bg=<url> or a dark scene-like gradient.
    b.setProperty('background', bg
      ? `#0b0d0f url("${bg}") center/cover no-repeat`
      : 'radial-gradient(ellipse at 50% 70%, #2a3238 0%, #12161a 55%, #07090a 100%)', 'important');
  }, []);

  if (!ready) return DevTools ? <Suspense fallback={null}><DevTools /></Suspense> : null;

  return (
    <>
      <Stage>
        <div className={cx('absolute inset-0', perf && 'perf')}>
          {view === 'lobby' && <Plates />}
          {view === 'start' && <StartScreen />}
          {view === 'lobby' && <Lobby />}
          {view === 'create' && <Create />}
          {view === 'spawn' && <Spawn />}
          <Cutscene />
          {view !== 'none' && <Overlays />}
        </div>
      </Stage>
      {DevTools && <Suspense fallback={null}><DevTools /></Suspense>}
    </>
  );
}
