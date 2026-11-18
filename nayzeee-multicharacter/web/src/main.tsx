import React from 'react';
import ReactDOM from 'react-dom/client';
import '@fontsource/barlow-condensed/latin-500.css';
import '@fontsource/barlow-condensed/latin-600.css';
import '@fontsource/barlow-condensed/latin-700.css';
import '@fontsource/barlow-condensed/latin-700-italic.css';
import '@fontsource/barlow/latin-400.css';
import '@fontsource/barlow/latin-500.css';
import '@fontsource/barlow/latin-600.css';
import '@fontsource/jetbrains-mono/latin-400.css';
import '@fontsource/jetbrains-mono/latin-500.css';
import './index.css';
import App from './App';
import { IS_MOCK, post, type NuiMessage } from './lib/nui';
import { useStore } from './lib/store';
import type { UiConfig } from './lib/types';

// Queue Lua messages until the `ready` reply (UiConfig) has been applied.
const queue: NuiMessage[] = [];
let live = false;

window.addEventListener('message', (e: MessageEvent) => {
  const msg = e.data as NuiMessage;
  if (!msg || typeof msg.action !== 'string') return;
  if (!live) { queue.push(msg); return; }
  useStore.getState().onMessage(msg.action, msg.data);
});

async function boot() {
  if (IS_MOCK) {
    const m = await import('./dev/mock');
    m.installMock();
  }
  let cfg: UiConfig | null = null;
  for (let i = 0; i < 30 && !cfg; i++) {
    const r = await post<UiConfig>('ready', {});
    if (r && typeof r === 'object' && Array.isArray((r as UiConfig).themes)) cfg = r as UiConfig;
    else await new Promise((res) => setTimeout(res, 1000));
  }
  if (!cfg) return;
  useStore.getState().boot(cfg);
  live = true;
  while (queue.length) {
    const m = queue.shift()!;
    useStore.getState().onMessage(m.action, m.data);
  }
  if (IS_MOCK) (await import('./dev/mock')).afterBoot();
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
boot();
