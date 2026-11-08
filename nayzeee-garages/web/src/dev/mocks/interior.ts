/**
 * Mock scenarios for the garage interior: stats HUD (no focus) and the control panel
 * (app 'interior'). mockNui answers every interior:* callback with plausible data and
 * emits the `update` / `close` messages Lua would send.
 */
import { emitNuiMessage, mockNui } from '../../lib/nui';
import { useUi } from '../../lib/store';
import type { HudVehicle, InteriorPanelData, PlayerOption } from '../../lib/types';
import { registerMock } from '../registry';

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

const hudNeon: HudVehicle = {
  plate: 'SILENT',
  model: 'neon',
  label: 'Pfister Neon',
  make: 'Pfister',
  image: 'neon',
  vehicleType: 'car',
  mileage: 4168,
  fuel: 65,
  engine: 100,
  body: 92,
  ownerName: 'Kai Moreno',
  canDrive: true,
};

const hudWorn: HudVehicle = {
  plate: '82KLM441',
  model: 'elegy',
  label: 'Annis Elegy Retro Custom',
  make: 'Annis',
  image: 'elegy',
  vehicleType: 'car',
  mileage: 61240,
  fuel: 18,
  engine: 41,
  body: 73,
  ownerName: 'Marisol "Mari" Quintero-Valdez',
  canDrive: false,
};

const ownerPanel: InteriorPanelData = {
  garageName: 'Vinewood Car Club',
  page: 2,
  pages: 3,
  vehicles: 8,
  slots: 10,
  role: 'owner',
  canInvite: true,
  members: [
    { serverId: 12, name: 'Kai Moreno', role: 'owner', you: true },
    { serverId: 7, name: 'Dana Whitfield', role: 'member', you: false },
    { serverId: 31, name: 'Leon "Sparks" Okafor', role: 'guest', you: false },
    { serverId: 44, name: 'Priya Natarajan-Holloway', role: 'guest', you: false },
  ],
};

const memberPanel: InteriorPanelData = {
  ...ownerPanel,
  page: 1,
  role: 'member',
  members: [
    { serverId: 12, name: 'Kai Moreno', role: 'owner', you: false },
    { serverId: 7, name: 'Dana Whitfield', role: 'member', you: true },
  ],
};

const guestPanel: InteriorPanelData = {
  garageName: 'Del Perro Heights Garage',
  page: 1,
  pages: 2,
  vehicles: 6,
  slots: 6,
  role: 'guest',
  canInvite: false,
  members: [
    { serverId: 3, name: 'Theo Lindqvist', role: 'owner', you: false },
    { serverId: 31, name: 'Leon "Sparks" Okafor', role: 'guest', you: true },
  ],
};

const nearby: PlayerOption[] = [
  { serverId: 18, name: 'Ava Castellanos' },
  { serverId: 23, name: 'Bram de Vries' },
  { serverId: 52, name: 'Jules Ndiaye' },
];

registerMock({
  id: 'hud-interior',
  group: 'Interior',
  label: 'Stats HUD (drivable, owner)',
  messages: [{ action: 'hud', data: hudNeon }],
});

registerMock({
  id: 'hud-interior-locked',
  group: 'Interior',
  label: 'Stats HUD (display only, worn)',
  messages: [{ action: 'hud', data: hudWorn }],
});

registerMock({
  id: 'hud-interior-seated',
  group: 'Interior',
  label: 'Seated: stats HUD + drive-out prompt',
  messages: [
    { action: 'hud', data: hudNeon },
    { action: 'prompt', data: { key: 'W', label: 'Accelerate to leave the garage' } },
  ],
});

registerMock({
  id: 'hud-interior-tag',
  group: 'Interior',
  label: 'On foot: vehicle card above the car',
  messages: [{ action: 'hud', data: { ...hudNeon, anchor: { x: 0.5, y: 0.44, scale: 1 } } }],
});

registerMock({
  id: 'hud-interior-tag-far',
  group: 'Interior',
  label: 'On foot: card further away (smaller), display only',
  messages: [{ action: 'hud', data: { ...hudWorn, anchor: { x: 0.36, y: 0.5, scale: 0.84 } } }],
});

registerMock({
  id: 'hud-interior-tag-edge',
  group: 'Interior',
  label: 'On foot: car at the screen edge (card slides in, stem stays on the car)',
  messages: [{ action: 'hud', data: { ...hudNeon, ownerName: undefined, anchor: { x: 0.985, y: 0.3, scale: 0.9 } } }],
});

registerMock({
  id: 'hud-interior-tag-follow',
  group: 'Interior',
  label: 'On foot: card following a car (walking past it)',
  messages: [{ action: 'hud', data: { ...hudNeon, anchor: { x: 0.3, y: 0.46, scale: 0.9 } } }],
});

/** Lua re-sends the anchor while the car moves on screen: simulate walking past it. */
let followTimer = 0;
const startFollow = () => {
  window.clearInterval(followTimer);
  const t0 = performance.now();
  followTimer = window.setInterval(() => {
    const hud = useUi.getState().hud;
    if (!hud?.anchor || hud.plate !== hudNeon.plate) {
      window.clearInterval(followTimer);
      return;
    }
    const t = (performance.now() - t0) / 1000;
    const x = 0.5 + Math.sin(t * 0.6) * 0.28;
    const scale = 0.91 + Math.cos(t * 0.6) * 0.08;
    emitNuiMessage({ action: 'hud', data: { ...hudNeon, anchor: { x, y: 0.46 + Math.cos(t * 0.6) * 0.04, scale } } });
  }, 33);
};
if (new URLSearchParams(window.location.search).get('mock') === 'hud-interior-tag-follow') {
  window.setTimeout(startFollow, 200);
}

registerMock({
  id: 'interior-panel',
  group: 'Interior',
  label: 'Control panel (owner with guests)',
  messages: [
    { action: 'hud', data: hudNeon },
    { action: 'open', data: { app: 'interior', data: ownerPanel } },
  ],
});

registerMock({
  id: 'interior-panel-solo',
  group: 'Interior',
  label: 'Control panel (per-player copy, default)',
  messages: [
    {
      action: 'open',
      data: {
        app: 'interior',
        data: { ...ownerPanel, page: 1, pages: 2, canInvite: false, members: [{ serverId: 12, name: 'Kai Moreno', role: 'owner', you: true }] },
      },
    },
  ],
});

registerMock({
  id: 'interior-panel-member',
  group: 'Interior',
  label: 'Control panel (member)',
  messages: [{ action: 'open', data: { app: 'interior', data: memberPanel } }],
});

registerMock({
  id: 'interior-panel-guest',
  group: 'Interior',
  label: 'Control panel (guest on a tour)',
  messages: [
    { action: 'hud', data: { ...hudNeon, ownerName: 'Theo Lindqvist', canDrive: false } },
    { action: 'open', data: { app: 'interior', data: guestPanel } },
  ],
});

/* ───────────── callbacks ───────────── */

const current = () => useUi.getState().apps.interior.data;

mockNui('interior:page', async ({ page }) => {
  await wait(380);
  const data = current();
  if (!data) return { ok: false, error: 'You are not inside a garage' };
  if (data.role === 'guest') return { ok: false, error: 'Only the garage owner and members can do that' };
  if (page < 1 || page > data.pages) return { ok: false, error: 'Invalid page' };
  const vehicles = page === data.pages ? Math.max(1, data.slots - 7) : data.slots - (page % 2);
  setTimeout(() => emitNuiMessage({ action: 'update', data: { app: 'interior', data: { page, vehicles } } }), 120);
  return null;
});

let playersCall = 0;
mockNui('interior:players', async () => {
  await wait(520);
  playersCall += 1;
  // Every third refresh nobody is around (shows the empty state).
  return playersCall % 3 === 0 ? [] : nearby;
});

mockNui('interior:invite', async ({ serverId }) => {
  await wait(450);
  if (serverId === 52) return { ok: false, error: 'That player is not near the garage entrance' };
  return null;
});

mockNui('interior:kick', async ({ serverId }) => {
  await wait(420);
  const data = current();
  if (!data) return { ok: false, error: 'You are not inside a garage' };
  setTimeout(
    () =>
      emitNuiMessage({
        action: 'update',
        data: { app: 'interior', data: { members: data.members.filter((m) => m.serverId !== serverId) } },
      }),
    150,
  );
  return null;
});

mockNui('interior:leave', async () => {
  await wait(500);
  emitNuiMessage({ action: 'close', data: { app: 'interior' } });
  emitNuiMessage({ action: 'hud', data: null });
  return null;
});
