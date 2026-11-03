/**
 * NUI entry. Fonts and global styles are bundled locally (no CDN at runtime).
 */
import React from 'react';
import ReactDOM from 'react-dom/client';
import '@fontsource/lexend/300.css';
import '@fontsource/lexend/400.css';
import '@fontsource/lexend/500.css';
import '@fontsource/lexend/600.css';
import '@fontsource/lexend/700.css';
import '@fontsource/jetbrains-mono/500.css';
import '@fontsource/jetbrains-mono/700.css';
import './styles/tokens.css';
import './styles/base.css';
import { App } from './App';
import { fetchNui, isBrowser } from './lib/nui';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);

if (isBrowser) {
  void import('./dev').then((m) => m.startDev());
} else {
  void fetchNui('ready', {});
}
