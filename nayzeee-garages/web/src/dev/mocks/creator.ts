/**
 * Mock scenarios for the interior creator (app 'creator'). mockNui answers every
 * creator:* callback like the Lua editor: picks positions around a simulated player,
 * loads profiles (teleport), records camera points, runs the ghost placement tool and the
 * cutscene preview with their key hints, walk mode (press E to come back), save / cancel.
 * Browser-only keys while a world action runs: Enter confirms, Esc / Backspace cancels.
 */
import { emitNuiMessage, mockNui } from '../../lib/nui';
import { toast, useUi } from '../../lib/store';
import type { CameraPoint, CreatorData, Interior, IplProfile, Vec3, Vec4 } from '../../lib/types';
import { registerMock } from '../registry';

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
const r3 = (n: number) => Math.round(n * 1000) / 1000;
const jitter = (n: number, amount: number) => r3(n + (Math.random() - 0.5) * amount);

const profiles: IplProfile[] = [
  {
    key: 'vinewood_car_club',
    label: 'Vinewood Car Club',
    coords: { x: 1202.452, y: -3251.384, z: -48.997, w: 90 },
    slots: 10,
    options: [
      {
        key: 'style',
        label: 'Style',
        default: 'club',
        choices: [
          { value: 'club', label: 'Club' },
          { value: 'showroom', label: 'Showroom' },
          { value: 'workshop', label: 'Workshop' },
        ],
      },
      {
        key: 'stairs',
        label: 'Stairs',
        default: 'enabled',
        choices: [
          { value: 'enabled', label: 'Enabled' },
          { value: 'disabled', label: 'Disabled' },
        ],
      },
    ],
  },
  {
    key: 'eclipse_garage',
    label: 'Eclipse Boulevard Garage',
    coords: { x: -1071.552, y: -70.884, z: -94.6, w: 180 },
    slots: 20,
    options: [
      {
        key: 'lighting',
        label: 'Lighting',
        default: 'warm',
        choices: [
          { value: 'warm', label: 'Warm' },
          { value: 'neon', label: 'Neon' },
          { value: 'industrial', label: 'Industrial' },
        ],
      },
      {
        key: 'floor',
        label: 'Floor',
        default: 'concrete',
        choices: [
          { value: 'concrete', label: 'Concrete' },
          { value: 'checker', label: 'Checker plate' },
          { value: 'epoxy', label: 'Epoxy' },
        ],
      },
    ],
  },
  {
    key: 'arcadius_ceo',
    label: 'Arcadius CEO Garage',
    coords: { x: -191.03, y: -579.12, z: 135.0, w: 270 },
    slots: 16,
    options: [
      {
        key: 'decor',
        label: 'Decor',
        default: 'modern',
        choices: [
          { value: 'modern', label: 'Modern' },
          { value: 'classic', label: 'Classic' },
          { value: 'vintage', label: 'Vintage' },
        ],
      },
    ],
  },
  { key: 'mid_garage', label: 'Mid-size Garage (6 cars)', coords: null, slots: 6, options: [] },
];

const blank: Interior = {
  id: null,
  name: '',
  enabled: true,
  profile: null,
  options: {},
  entry: { x: 215.124, y: -810.441, z: 30.727, w: 157.3 },
  gtaInteriorId: null,
  cutscene: { enabled: false, transition: 3000, returnTime: 1000, points: [] },
  slots: [],
  exit: null,
};

const club = profiles[0].coords!;
const slotRow = (i: number): Vec4 => ({
  x: r3(club.x - 6 + (i % 3) * 4.2),
  y: r3(club.y + 4 + Math.floor(i / 3) * 6.5),
  z: r3(club.z + 0.02),
  w: i % 2 ? 270 : 90,
});

const edited: Interior = {
  id: 3,
  name: 'Executive Collection',
  enabled: true,
  profile: 'vinewood_car_club',
  options: { style: 'showroom', stairs: 'enabled' },
  entry: { ...club },
  gtaInteriorId: 291841,
  cutscene: {
    enabled: true,
    transition: 3500,
    returnTime: 1200,
    points: [
      { coords: { x: 1189.204, y: -3262.71, z: -45.31 }, rot: { x: -12.5, y: 0, z: 312.4 }, fov: 55 },
      { coords: { x: 1206.889, y: -3240.05, z: -46.82 }, rot: { x: -6.25, y: 0, z: 201.75 }, fov: 48 },
      { coords: { x: 1214.37, y: -3255.6, z: -47.94 }, rot: { x: -3.0, y: 0, z: 118.9 }, fov: 42 },
    ],
  },
  slots: Array.from({ length: 6 }, (_, i) => slotRow(i)),
  exit: { x: 1199.871, y: -3254.03, z: -48.997, w: 270 },
};

registerMock({
  id: 'creator-create',
  group: 'Interior creator',
  label: 'Create interior (blank)',
  messages: [
    {
      action: 'open',
      data: { app: 'creator', data: { mode: 'create', interior: blank, profiles, gtaInteriorName: null } satisfies CreatorData },
    },
  ],
});

registerMock({
  id: 'creator-edit',
  group: 'Interior creator',
  label: 'Edit interior (slots + camera points)',
  messages: [
    {
      action: 'open',
      data: { app: 'creator', data: { mode: 'edit', interior: edited, profiles, gtaInteriorName: 'Car Meet' } satisfies CreatorData },
    },
  ],
});

/* ───────────── simulated world ───────────── */

let here: Vec4 = { ...blank.entry };
let session: unknown = null;

/** The simulated player starts at the entry of the interior that was just opened. */
function syncWorld() {
  const data = useUi.getState().apps.creator.data;
  if (data && data !== session) {
    session = data;
    here = { ...data.interior.entry };
    loadedProfile = data.interior.profile;
    placed = 0;
  }
}

/** Resolves true on Enter / timeout, false on Esc / Backspace (browser stand-in for the game keys). */
function worldAction(ms: number): Promise<boolean> {
  return new Promise((resolve) => {
    const done = (ok: boolean) => {
      window.clearTimeout(timer);
      window.removeEventListener('keydown', onKey, true);
      resolve(ok);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Enter') done(true);
      else if (e.key === 'Escape' || e.key === 'Backspace') {
        e.stopPropagation();
        done(false);
      }
    };
    const timer = window.setTimeout(() => done(true), ms);
    window.addEventListener('keydown', onKey, true);
  });
}

mockNui('creator:pickEntry', async () => {
  syncWorld();
  await wait(260);
  const entry: Vec4 = { x: jitter(here.x, 1.6), y: jitter(here.y, 1.6), z: r3(here.z), w: Math.round(Math.random() * 3600) / 10 };
  here = entry;
  const inside = here.z < -20 || here.z > 100;
  return {
    entry,
    gtaInteriorId: inside ? 291841 : Math.random() > 0.5 ? 285441 : null,
    gtaInteriorName: inside ? 'Car Meet' : null,
  };
});

let loadedProfile: string | null = null;
mockNui('creator:applyProfile', async ({ profile }) => {
  syncWorld();
  await wait(700);
  if (!profile) {
    loadedProfile = null;
    return { entry: null };
  }
  const p = profiles.find((x) => x.key === profile);
  if (!p) return { ok: false, error: 'Unknown interior profile' };
  const changed = profile !== loadedProfile;
  loadedProfile = profile;
  if (!changed || !p.coords) return { entry: null };
  here = { ...p.coords };
  return { entry: { ...p.coords } };
});

mockNui('creator:addCameraPoint', async (): Promise<CameraPoint> => {
  syncWorld();
  await wait(220);
  return {
    coords: { x: jitter(here.x, 14), y: jitter(here.y, 14), z: r3(here.z + 1.5 + Math.random() * 3) },
    rot: { x: Math.round((-4 - Math.random() * 14) * 100) / 100, y: 0, z: Math.round(Math.random() * 36000) / 100 },
    fov: Math.round((40 + Math.random() * 20) * 100) / 100,
  };
});

mockNui('creator:previewCutscene', async ({ cutscene }) => {
  if (!cutscene.points.length) return { ok: false, error: 'Add at least one camera point first' };
  emitNuiMessage({ action: 'hint', data: { title: 'Cutscene preview', keys: [{ keys: ['Esc'], label: 'Stop preview' }] } });
  await worldAction(Math.min(4000, 900 * cutscene.points.length + 600));
  emitNuiMessage({ action: 'hint', data: null });
  return null;
});

let placed = 0;
mockNui('creator:placeSlot', async ({ slot }) => {
  syncWorld();
  emitNuiMessage({
    action: 'hint',
    data: {
      title: 'Place vehicle',
      keys: [
        { keys: ['W', 'A', 'S', 'D'], label: 'Move' },
        { keys: ['Scroll'], label: 'Rotate' },
        { keys: ['R'], label: 'Up' },
        { keys: ['F'], label: 'Down' },
        { keys: ['Shift'], label: 'Faster' },
        { keys: ['Enter'], label: 'Confirm' },
        { keys: ['Esc'], label: 'Cancel' },
      ],
    },
  });
  const ok = await worldAction(2200);
  emitNuiMessage({ action: 'hint', data: null });
  if (!ok) return null;
  if (slot) return { x: jitter(slot.x, 0.8), y: jitter(slot.y, 0.8), z: slot.z, w: Math.round((slot.w + 15) % 360) };
  placed += 1;
  return { x: jitter(here.x + 3 * placed, 0.4), y: jitter(here.y + 2, 0.4), z: r3(here.z), w: (90 + placed * 45) % 360 };
});

mockNui('creator:showSlots', () => null);

mockNui('creator:pickExit', async (): Promise<Vec4> => {
  syncWorld();
  await wait(240);
  return { x: jitter(here.x, 6), y: jitter(here.y, 6), z: r3(here.z), w: Math.round(Math.random() * 3600) / 10 };
});

mockNui('creator:teleport', async ({ coords }) => {
  syncWorld();
  await wait(650);
  const c = coords as Vec3 & { w?: number };
  here = { x: c.x, y: c.y, z: c.z, w: c.w ?? here.w };
  return null;
});

mockNui('creator:walk', async () => {
  emitNuiMessage({ action: 'hint', data: { keys: [{ keys: ['E'], label: 'Open editor' }] } });
  const back = () => {
    window.clearTimeout(timer);
    window.removeEventListener('keydown', onKey, true);
    emitNuiMessage({ action: 'hint', data: null });
  };
  const onKey = (e: KeyboardEvent) => {
    if (e.key === 'e' || e.key === 'E') back();
  };
  const timer = window.setTimeout(back, 6000);
  window.addEventListener('keydown', onKey, true);
  return null;
});

mockNui('creator:save', async ({ interior }) => {
  await wait(650);
  if (/taken/i.test(interior.name)) return { ok: false, error: 'An interior with this name already exists' };
  emitNuiMessage({ action: 'close', data: { app: 'creator' } });
  toast({ type: 'success', message: 'Interior saved' });
  return { ...interior, id: interior.id ?? 12 };
});

mockNui('creator:cancel', async () => {
  await wait(260);
  emitNuiMessage({ action: 'close', data: { app: 'creator' } });
  return null;
});
