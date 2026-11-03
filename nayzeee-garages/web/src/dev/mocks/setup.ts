/**
 * Mock scenarios for the vehicle setup app (liveries / extras after a job vehicle spawns).
 * mockNui answers setup:* like the Lua side: extras 1 and 2 are mutually exclusive (the
 * game switches one off), the real state comes back through an `update` message.
 */
import { emitNuiMessage, mockNui } from '../../lib/nui';
import { useUi } from '../../lib/store';
import type { SetupData } from '../../lib/types';
import { registerMock } from '../registry';

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

const liveries = [
  'LSPD Patrol',
  'LSPD Slicktop',
  'Sheriff (Blaine County)',
  'State Patrol',
  'Park Ranger',
  'Unmarked Interceptor',
  'K-9 Unit',
  'Highway Pursuit (Reflective Chevron Pack)',
].map((label, index) => ({ index, label }));

const full: SetupData = {
  label: 'Vapid Stanier Police Cruiser',
  liveries,
  livery: 4,
  extras: [
    { id: 1, enabled: true },
    { id: 2, enabled: false },
    { id: 3, enabled: true },
    { id: 5, enabled: false },
    { id: 7, enabled: true },
    { id: 11, enabled: false },
  ],
};

registerMock({
  id: 'setup-full',
  group: 'Vehicle setup',
  label: 'Liveries + extras',
  messages: [{ action: 'open', data: { app: 'setup', data: full } }],
});

registerMock({
  id: 'setup-extras-only',
  group: 'Vehicle setup',
  label: 'Extras only',
  messages: [
    {
      action: 'open',
      data: {
        app: 'setup',
        data: {
          label: 'Bravado Buffalo STX Unmarked',
          liveries: [],
          livery: -1,
          extras: [
            { id: 1, enabled: false },
            { id: 2, enabled: true },
          ],
        } satisfies SetupData,
      },
    },
  ],
});

registerMock({
  id: 'setup-liveries-only',
  group: 'Vehicle setup',
  label: 'Liveries only (mod liveries)',
  messages: [
    {
      action: 'open',
      data: {
        app: 'setup',
        data: {
          label: 'Brute Ambulance',
          liveries: [{ index: -1, label: 'Default' }, ...['Los Santos Medical', 'Pillbox Hill', 'Sandy Shores Rescue'].map((label, index) => ({ index, label }))],
          livery: -1,
          extras: [],
        } satisfies SetupData,
      },
    },
  ],
});

registerMock({
  id: 'setup-empty',
  group: 'Vehicle setup',
  label: 'Nothing to set up (Drive only)',
  messages: [
    { action: 'open', data: { app: 'setup', data: { label: 'Declasse Granger 3600LX', liveries: [], livery: -1, extras: [] } satisfies SetupData } },
  ],
});

mockNui('setup:livery', async ({ index }) => {
  await wait(90);
  if (index === 6) return { ok: false, error: 'This livery is not streamed on this server' };
  return null;
});

mockNui('setup:extra', async ({ id, enabled }) => {
  await wait(110);
  const data = useUi.getState().apps.setup.data;
  if (!data) return { ok: false, error: 'Vehicle not found' };
  // Extras 1 and 2 share a mount point: turning one on turns the other off.
  const other = id === 1 ? 2 : id === 2 ? 1 : null;
  const extras = data.extras.map((e) => {
    if (e.id === id) return { ...e, enabled };
    if (enabled && other !== null && e.id === other) return { ...e, enabled: false };
    return e;
  });
  setTimeout(() => emitNuiMessage({ action: 'update', data: { app: 'setup', data: { extras } } }), 60);
  return null;
});

mockNui('setup:drive', async () => {
  await wait(420);
  emitNuiMessage({ action: 'close', data: { app: 'setup' } });
  return null;
});
