/**
 * minigame app (docs/V2_CHANGES.md G.6 / G.7): the lock pick (3D pin lock, lazy three.js chunk),
 * the hotwire wires and the signal reader. client/carlock/minigame.lua opens it with the
 * server's puzzle and waits for minigame:finish; the server checks the answer.
 * On mount the page tells Lua it can play them (minigame:ready): until then Lua asks the server
 * for skill checks instead.
 */
import { Component, Suspense, lazy, useEffect } from 'react';
import type { ReactNode } from 'react';
import { useApp } from '@/lib/store';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import { Spinner } from '@/components/ui';
import { WiresGame } from './wires/WiresGame';
import { ReaderGame } from './reader/ReaderGame';
import './minigame.css';

const LockGame = lazy(() => import('./pins/LockGame'));

const READY_TRIES = 8;
const READY_RETRY_MS = 2500;

function useReadyPing() {
  useEffect(() => {
    let stop = false;
    let timer = 0;
    const ping = async (n: number) => {
      const res = await request('minigame:ready', {}, { toastError: false });
      if (stop || res.ok || n + 1 >= READY_TRIES) return;
      timer = window.setTimeout(() => void ping(n + 1), READY_RETRY_MS);
    };
    void ping(0);
    return () => {
      stop = true;
      window.clearTimeout(timer);
    };
  }, []);
}

/** The lock chunk failed to load or draw: Lua falls back to skill checks (started ok = false). */
class GameBoundary extends Component<{ token: number; children: ReactNode }, { failed: boolean }> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  componentDidCatch() {
    void request('minigame:started', { token: this.props.token, ok: false }, { toastError: false });
  }
  render() {
    return this.state.failed ? null : this.props.children;
  }
}

function Loading() {
  return (
    <div className="nz-mg-loading" role="status">
      <Spinner size={16} />
      <span>{t('Loading the lock...')}</span>
    </div>
  );
}

export function MinigameApp() {
  const app = useApp('minigame');
  useReadyPing();
  if (!app.open || !app.data) return null;
  const data = app.data;
  switch (data.game) {
    case 'pins':
      return (
        <GameBoundary key={data.token} token={data.token}>
          <Suspense fallback={<Loading />}>
            <LockGame data={data} />
          </Suspense>
        </GameBoundary>
      );
    case 'wires':
      return (
        <GameBoundary key={data.token} token={data.token}>
          <WiresGame data={data} />
        </GameBoundary>
      );
    case 'reader':
      return (
        <GameBoundary key={data.token} token={data.token}>
          <ReaderGame data={data} />
        </GameBoundary>
      );
    default:
      return null;
  }
}
