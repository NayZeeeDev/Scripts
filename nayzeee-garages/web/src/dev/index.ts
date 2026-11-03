/**
 * Dev harness bootstrap (browser only, never loaded in FiveM).
 */
import { createElement } from 'react';
import { createRoot } from 'react-dom/client';
import { emitNuiMessage } from '../lib/nui';
import { defaultInterface } from '../lib/store';
import { openScenario } from './registry';
import { DevPanel } from './DevPanel';
import './mocks';

export function startDev() {
  emitNuiMessage({ action: 'init', data: { locale: {}, settings: defaultInterface, resource: 'nayzeee-garages' } });
  const params = new URLSearchParams(window.location.search);
  const id = params.get('mock');
  if (id) setTimeout(() => openScenario(id), 60);
  if (params.get('kit')) {
    void import('./KitGallery').then(({ KitGallery }) => {
      const host = document.createElement('div');
      host.id = 'nz-kit';
      document.body.appendChild(host);
      createRoot(host).render(createElement(KitGallery));
    });
  }
  if (params.get('panel') !== '0') {
    const host = document.createElement('div');
    host.id = 'nz-dev';
    document.body.appendChild(host);
    createRoot(host).render(createElement(DevPanel));
  }
}
