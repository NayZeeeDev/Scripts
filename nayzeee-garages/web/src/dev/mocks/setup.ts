/**
 * Mock scenarios for the vehicle setup app (liveries / extras after a job vehicle spawns).
 * mockNui answers setup:* like the Lua side: extras 1 and 2 are mutually exclusive (the
 * game switches one off), the real state comes back through an `update` message. Livery 7
 * ("K-9 Unit") fails like a livery that is not streamed. setup:camera only logs (there is no
 * game camera in the browser).
 */
import { emitNuiMessage, mockNui } from '../../lib/nui';
import { useUi } from '../../lib/store';
import type { SetupData, SetupMod } from '../../lib/types';
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

const stockMods: SetupMod[] = [
  { id: 'engine', level: 0, max: 4 },
  { id: 'brakes', level: 0, max: 3 },
  { id: 'transmission', level: 0, max: 3 },
  { id: 'suspension', level: 0, max: 4 },
  { id: 'armour', level: 0, max: 5 },
  { id: 'turbo', level: 0, max: 1 },
];
const maxedMods: SetupMod[] = stockMods.map((m) => ({ ...m, level: m.max }));

const full: SetupData = {
  label: 'Vapid Stanier Police Cruiser',
  model: 'police',
  plate: 'LSPD4821',
  plateTemplate: 'LSPD####',
  garage: 'Mission Row PD Garage',
  liveryMode: 'livery',
  maxMods: true,
  mods: maxedMods,
  camera: true,
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
          model: 'police5',
          plate: '72KQX194',
          plateTemplate: '',
          garage: 'Vespucci Police Station',
          liveryMode: null,
          maxMods: false,
          mods: [
            { id: 'engine', level: 2, max: 4 },
            { id: 'brakes', level: 3, max: 3 },
            { id: 'transmission', level: 0, max: 3 },
            { id: 'turbo', level: 1, max: 1 },
          ],
          camera: true,
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
          model: 'ambulance',
          plate: 'EMS 0417',
          plateTemplate: 'EMS ####',
          garage: 'Pillbox Hill Medical',
          liveryMode: 'mod',
          maxMods: false,
          mods: stockMods.slice(0, 3).concat([{ id: 'turbo', level: 0, max: 1 }]),
          camera: false,
          liveries: [{ index: -1, label: 'Default' }, ...['Los Santos Medical', 'Pillbox Hill', 'Sandy Shores Rescue'].map((label, index) => ({ index, label }))],
          livery: -1,
          extras: [],
        } satisfies SetupData,
      },
    },
  ],
});

registerMock({
  id: 'setup-many',
  group: 'Vehicle setup',
  label: 'Many liveries + extras (scrolling)',
  messages: [
    {
      action: 'open',
      data: {
        app: 'setup',
        data: {
          ...full,
          label: 'Declasse Alamo Sheriff SUV (Blaine County Fleet Edition)',
          model: 'sheriff2',
          plate: 'BCSO 112',
          plateTemplate: 'BCSO ###',
          garage: 'Sandy Shores Sheriff',
          maxMods: false,
          mods: stockMods.map((m, i) => ({ ...m, level: i % 2 ? m.max : Math.floor(m.max / 2) })),
          liveries: Array.from({ length: 22 }, (_, index) => ({ index, label: index === 0 ? 'Sheriff Classic Two-Tone' : `Sheriff Pattern ${index + 1}` })),
          livery: 13,
          extras: Array.from({ length: 11 }, (_, i) => ({ id: i + 1, enabled: i % 3 === 0 })),
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
  if (index === 6) return { ok: false, error: 'This livery is not available' };
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

mockNui('setup:camera', (input) => {
  console.info('[mock] setup:camera', input);
  return null;
});

mockNui('setup:drive', async () => {
  await wait(420);
  emitNuiMessage({ action: 'close', data: { app: 'setup' } });
  return null;
});
