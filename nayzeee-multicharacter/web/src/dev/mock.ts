// Browser-only mock bridge (loaded with a dynamic import when GetParentResourceName is undefined).
import { emit } from '../lib/nui';
import { useStore } from '../lib/store';
import type { CharacterNui, LobbyPayload, Plate, Settings, SquadNui, UiConfig } from '../lib/types';

const NAT = ['Afghan', 'Albanian', 'Algerian', 'American', 'Argentine', 'Australian', 'Austrian', 'Belgian', 'Brazilian', 'British', 'Canadian', 'Chilean', 'Chinese', 'Colombian', 'Croatian', 'Cuban', 'Czech', 'Danish', 'Dutch', 'Egyptian', 'Filipino', 'Finnish', 'French', 'German', 'Greek', 'Haitian', 'Indian', 'Irish', 'Israeli', 'Italian', 'Jamaican', 'Japanese', 'Korean', 'Lebanese', 'Mexican', 'Moroccan', 'Nigerian', 'Norwegian', 'Polish', 'Portuguese', 'Puerto Rican', 'Romanian', 'Russian', 'Scottish', 'Serbian', 'South African', 'Spanish', 'Swedish', 'Swiss', 'Thai', 'Turkish', 'Ukrainian', 'Venezuelan', 'Vietnamese', 'Welsh'];

const settings: Settings = { scale: 1, muted: false, uiVolume: 0.6, ambientVolume: 0.35, sway: true, dof: true, plates: true, perf: false, bars: true };

const cfg: UiConfig = {
  version: '2.0.0',
  locale: { ui: {} },
  ui: {
    serverName: 'NAYZEEE', tagline: 'Roleplay', logo: '', accent: 'teal',
    accents: { teal: ['#0fd4c4', '#08afa2', '#067d74'], gold: ['#f3d58a', '#d8b35a', '#9c7a2e'], orange: ['#ff8a4c', '#f2622e', '#b8401a'], violet: ['#b79bff', '#8b6cf6', '#5d40c4'], red: ['#ff6b6f', '#e5484d', '#b8262b'] },
    socials: [{ icon: 'discord', label: 'Discord', url: 'https://discord.gg/your-server' }, { icon: 'website', label: 'Website', url: 'https://your-server.com' }, { icon: 'store', label: 'Store', url: 'https://your-store.tebex.io' }],
    keys: { deploy: 'Enter', switch: 'Q / E', camera: 'Tab', customize: 'C', back: 'Esc' },
    scale: 1, currency: { locale: 'en-US', code: 'USD' }, dateFormat: 'MM/DD/YYYY', showOnline: true, nameplates: true,
  },
  start: { enabled: true, prompt: 'Press ENTER to continue', subtitle: 'Connected as %s', orbit: true, music: '' },
  themes: [
    { id: 'supercar', label: 'Supercar · City Dusk', icon: 'car', category: 'luxury', description: 'Leaning on an exotic downtown as the city lights come on.', palette: ['#ff9a4d', '#5b2a86', '#0b0d1a'], ambience: { preset: 'city' } },
    { id: 'penthouse', label: 'Penthouse · Skyline', icon: 'building', category: 'luxury', description: 'A high-rise rooftop over the Vinewood skyline.', palette: ['#f5c56b', '#c2593a', '#14101c'], ambience: { preset: 'rooftop' } },
    { id: 'studio', label: 'Velvet Studio', icon: 'sparkles', category: 'fashion', description: 'Pink and violet neon — made for outfits, hair and detail.', palette: ['#ff5fa2', '#7b5cff', '#120a1a'], moods: ['midnight_neon', 'clean_studio', 'moody_dusk'], ambience: { preset: 'club' } },
    { id: 'boutique', label: 'Vinewood Boutique', icon: 'shopping-bag', category: 'fashion', description: 'Outside the flagship stores on Portola Drive.', palette: ['#e8d3b0', '#8a6f4e', '#151210'], ambience: { preset: 'street' } },
    { id: 'beach', label: 'Del Perro Sunset', icon: 'sun', category: 'lifestyle', description: 'End of the pier, the Pacific burning orange behind you.', palette: ['#ffb36b', '#e0576b', '#1a1430'], ambience: { preset: 'ocean' } },
    { id: 'jet', label: 'Private Jet · LSIA', icon: 'plane', category: 'luxury', description: 'Wheels up from the executive apron at LSIA.', palette: ['#d9e2ec', '#5a7184', '#0c1117'], ambience: { preset: 'airport' } },
    { id: 'helipad', label: 'Tactical Helipad', icon: 'helicopter', category: 'tactical', description: 'Rotors idle, crew ready — La Puerta heliport.', palette: ['#8fb37a', '#3d4a35', '#0c0f0b'], ambience: { preset: 'helipad' } },
    { id: 'garage', label: 'Street Tuner Garage', icon: 'wrench', category: 'lifestyle', description: 'Underground glow, a fresh build and the engine ticking.', palette: ['#3fe0ff', '#ff3d6e', '#090b12'], ambience: { preset: 'garage' } },
    { id: 'skydive', label: 'Infil · Skydive', icon: 'wind', category: 'tactical', description: 'Riding the door of an infil chopper over Los Santos. Jump when ready.', palette: ['#a9c3d9', '#2f4a63', '#070b10'], moods: ['golden_hour', 'moody_dusk', 'clean_studio'], ambience: { preset: 'skydive' } },
  ],
  moods: [
    { id: 'golden_hour', label: 'Golden Hour', icon: 'sunset', swatch: ['#ffb36b', '#e0576b'] },
    { id: 'midnight_neon', label: 'Midnight Neon', icon: 'moon', swatch: ['#ff5fa2', '#7b5cff'] },
    { id: 'clean_studio', label: 'Clean Studio', icon: 'aperture', swatch: ['#ffffff', '#9aa6b2'] },
    { id: 'moody_dusk', label: 'Moody Dusk', icon: 'cloud-moon', swatch: ['#5b6b8c', '#1d2233'] },
  ],
  poses: [
    { id: 'relaxed', label: 'Relaxed', icon: 'user', category: 'lifestyle' },
    { id: 'crossed', label: 'Arms Crossed', icon: 'shield', category: 'lifestyle' },
    { id: 'model', label: 'Model Pose', icon: 'sparkles', category: 'fashion' },
    { id: 'model2', label: 'Editorial', icon: 'camera', category: 'fashion' },
    { id: 'lean_car', label: 'Lean on Car', icon: 'car', category: 'luxury' },
    { id: 'lean_rail', label: 'Lean on Rail', icon: 'waves', category: 'lifestyle' },
    { id: 'phone', label: 'Checking Phone', icon: 'smartphone', category: 'lifestyle', prop: true },
    { id: 'coffee', label: 'Iced Coffee', icon: 'coffee', category: 'lifestyle', prop: true },
    { id: 'shopping', label: 'Shopping Bags', icon: 'shopping-bag', category: 'luxury', prop: true },
    { id: 'smoke', label: 'Smoking', icon: 'flame', category: 'lifestyle' },
    { id: 'tactical', label: 'Tactical Stance', icon: 'crosshair', category: 'tactical' },
    { id: 'guard', label: 'On Guard', icon: 'shield-check', category: 'tactical' },
    { id: 'flex', label: 'Flex', icon: 'dumbbell', category: 'lifestyle' },
    { id: 'sit', label: 'Sit Down', icon: 'armchair', category: 'lifestyle' },
  ],
  couplePoses: [
    { id: 'embrace', label: 'Embrace', icon: 'heart' }, { id: 'kiss', label: 'Kiss', icon: 'heart-handshake' },
    { id: 'side_by_side', label: 'Side by Side', icon: 'users' }, { id: 'back_to_back', label: 'Back to Back', icon: 'repeat' },
    { id: 'lean_together', label: 'Lean Together', icon: 'car' }, { id: 'forehead', label: 'Forehead Lean', icon: 'smile' },
  ],
  pets: [
    { id: 'husky', label: 'Husky', icon: 'dog', kind: 'dog' }, { id: 'shepherd', label: 'Shepherd', icon: 'dog', kind: 'dog' },
    { id: 'rottweiler', label: 'Rottweiler', icon: 'dog', kind: 'dog' }, { id: 'retriever', label: 'Retriever', icon: 'dog', kind: 'dog' },
    { id: 'pug', label: 'Pug', icon: 'dog', kind: 'smalldog' }, { id: 'poodle', label: 'Poodle', icon: 'dog', kind: 'smalldog' },
    { id: 'westy', label: 'Westie', icon: 'dog', kind: 'smalldog' }, { id: 'cat', label: 'Cat', icon: 'cat', kind: 'cat' },
  ],
  petNames: true,
  weapon: { mode: 'inventory', allowNone: true, allowAuto: true, enabled: true },
  registration: {
    nameMin: 2, nameMax: 16, minAge: 18, maxAge: 90,
    height: { enabled: true, min: 150, max: 210, default: 175 },
    nationality: { enabled: true, required: true, default: 'American' },
    backstory: { enabled: false, required: false, min: 20, max: 600 },
    genders: ['m', 'f'],
    blacklist: ['admin', 'staff', 'moderator', 'owner', 'developer', 'police', 'test'],
  },
  nationalities: NAT,
  cameraModes: ['squad', 'duo', 'body', 'face'],
  squad: { enabled: true, maxLinks: 3, searchMin: 3, couples: true },
  audio: { ambience: true, uiSounds: true },
  settings,
  playerPick: true,
  typeToConfirm: true,
};

const now = Math.floor(Date.now() / 1000);
const chars: CharacterNui[] = [
  {
    id: 'NZ4KQ2', slot: 1, firstname: 'Marcus', lastname: 'Vance', name: 'Marcus Vance', dob: '1994-03-16', age: 32, gender: 'm', nationality: 'American', height: 184,
    job: { name: 'police', label: 'LSPD', grade: 3, gradeLabel: 'Sergeant' }, cash: 2450, bank: 184300, lastPlayed: now - 3600 * 5, playtime: 3600 * 212, favorite: true,
    prefs: { theme: 'supercar', mood: 'moody_dusk', pose: 'crossed', couplePose: 'side_by_side', weapon: 'auto', pet: 'husky', petName: 'Ghost' },
    weapons: [{ name: 'WEAPON_CARBINERIFLE', label: 'Carbine Rifle', class: 'rifle' }, { name: 'WEAPON_COMBATPISTOL', label: 'Combat Pistol', class: 'pistol' }, { name: 'WEAPON_NIGHTSTICK', label: 'Nightstick', class: 'melee' }],
    pets: ['husky', 'shepherd', 'pug', 'cat'],
  },
  {
    id: 'NZ8LM1', slot: 2, firstname: 'Sofia', lastname: 'Reyes', name: 'Sofia Reyes', dob: '1999-11-02', age: 27, gender: 'f', nationality: 'Mexican',
    job: { name: 'realestate', label: 'Dynasty 8', grade: 1, gradeLabel: 'Agent' }, cash: 830, bank: 46250, lastPlayed: now - 86400 * 3, playtime: 3600 * 64,
    prefs: { theme: 'penthouse', mood: 'golden_hour', pose: 'phone', weapon: 'none' }, weapons: [], pets: ['poodle', 'cat'],
  },
  {
    id: 'NZ2TX9', slot: 3, firstname: 'Dmitri', lastname: 'Volkov', name: 'Dmitri Volkov', dob: '1988-07-21', age: 38, gender: 'm', nationality: 'Russian',
    job: { name: 'mechanic', label: 'Benny\'s', grade: 2, gradeLabel: 'Lead Tech' }, cash: 12900, bank: 2310000, lastPlayed: now - 86400 * 21, playtime: 3600 * 401,
    prefs: { theme: 'garage', mood: 'midnight_neon', pose: 'lean_car', weapon: 'WEAPON_BAT' }, weapons: [{ name: 'WEAPON_BAT', label: 'Baseball Bat', class: 'melee' }, { name: 'WEAPON_PUMPSHOTGUN', label: 'Pump Shotgun', class: 'shotgun' }], pets: ['rottweiler'],
  },
];

let squad: SquadNui = {
  links: [
    { id: 11, type: 'couple', slot: 2, visible: true, other: { id: 'AX77P0', name: 'Mia Laurent', job: { label: 'Pillbox EMS' }, online: true } },
    { id: 12, type: 'squad', slot: 3, visible: true, other: { id: 'BQ11Z2', name: 'Dre Walker', job: { label: 'Unemployed' }, online: false } },
  ],
  incoming: [{ id: 21, type: 'squad', from: { id: 'KM55R1', name: 'Kai Moreno' }, at: now - 1800 }],
  outgoing: [{ id: 22, type: 'squad', to: { id: 'LO90C3', name: 'Lena Ortiz' }, at: now - 7200 }],
};

let selected = 1;
const slots = { total: 4, used: 3, max: 8, shown: 5 };
let camera = 'squad';

const charOf = (slot: number) => chars.find((c) => c.slot === slot);
const payload = (): LobbyPayload => {
  const c = charOf(selected);
  return {
    characters: chars, slots: { ...slots, used: chars.length }, selected, canDelete: true,
    theme: c?.prefs?.theme || 'supercar', mood: c?.prefs?.mood || 'golden_hour', camera, squad, online: 87, maxPlayers: 128,
  };
};
const pushData = () => emit('data', payload());
const pushSquad = () => { emit('squad', squad); };
const pushAudio = () => emit('audio', { ambience: payload().theme, muted: settings.muted });

// moving nameplates
let plateT = 0;
let plateTimer: number | undefined;
function startPlates() {
  window.clearInterval(plateTimer);
  plateTimer = window.setInterval(() => {
    if (useStore.getState().view !== 'lobby') return;
    plateT += 0.05;
    const c = charOf(selected);
    const sway = Math.sin(plateT) * 0.003;
    const items: Plate[] = [];
    if (c) items.push({ key: 'self', x: 0.5 + sway, y: 0.25, visible: true, name: c.name, sub: c.job?.label, badge: 'self' });
    for (const l of squad.links) {
      if (!l.visible) continue;
      const x = l.slot === 2 ? 0.635 : l.slot === 3 ? 0.375 : 0.72;
      items.push({ key: `l${l.id}`, x: x + sway, y: 0.29, visible: true, name: l.other.name, sub: l.type === 'couple' ? 'Partner' : 'Squad', badge: l.type === 'couple' ? 'partner' : 'squad', online: !!l.other.online });
    }
    if (c?.prefs?.pet && c.prefs.pet !== 'none') items.push({ key: 'pet', x: 0.565 + sway, y: 0.66, visible: true, name: c.prefs.petName || 'Pet', badge: 'pet' });
    emit('plates', { items });
  }, 100);
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const people = ['Kai Moreno', 'Kaito Sato', 'Kaila Brooks', 'Jordan Kane', 'Jade Kim', 'Leo Marsh', 'Lena Ortiz', 'Rhea Kapoor', 'Nina Hayes', 'Omar Haddad'];

async function handler(name: string, d: any): Promise<unknown> {
  await sleep(60);
  switch (name) {
    case 'ready': return cfg;
    case 'startContinue': setTimeout(() => { emit('lobby', payload()); pushAudio(); }, 450); return true;
    case 'select': {
      selected = d.slot;
      const c = charOf(selected);
      if (c) {
        emit('busy', { on: true, text: 'Loading scene' });
        setTimeout(() => { pushData(); pushSquad(); pushAudio(); emit('busy', { on: false }); }, 450);
      } else pushData();
      return true;
    }
    case 'camera': camera = d.mode; return true;
    case 'previewPref': console.debug('[mock] preview', d); return true;
    case 'setPref': {
      const c = charOf(d.slot);
      if (!c) return { ok: false, msg: 'No character' };
      if (d.key === 'favorite') c.favorite = !!d.value;
      else c.prefs = { ...(c.prefs || {}), [d.key]: d.value };
      pushData();
      if (d.key === 'theme') pushAudio();
      return { ok: true };
    }
    case 'play':
      emit('busy', { on: true, text: 'Loading character' });
      setTimeout(() => {
        emit('busy', { on: false });
        emit('spawn', {
          options: [
            { id: 'last', kind: 'last', label: 'Last location', desc: 'Where you logged off' },
            { id: 'house:1', kind: 'house', label: '3671 Whispymound Dr', desc: 'Your property' },
            { id: 'lsia', kind: 'city', label: 'Los Santos Airport', desc: 'Arrivals terminal', icon: 'plane' },
            { id: 'legion', kind: 'city', label: 'Legion Square', desc: 'Downtown Los Santos', icon: 'city' },
            { id: 'pier', kind: 'city', label: 'Del Perro Pier', desc: 'Beachfront, Del Perro', icon: 'beach' },
            { id: 'vinewood', kind: 'city', label: 'Vinewood Boulevard', desc: 'Uptown Vinewood', icon: 'star' },
            { id: 'sandy', kind: 'city', label: 'Sandy Shores', desc: 'Blaine County', icon: 'sun' },
            { id: 'paleto', kind: 'city', label: 'Paleto Bay', desc: 'Northern coast', icon: 'tree' },
            { id: 'mrpd', kind: 'city', label: 'Mission Row PD', desc: 'On duty', icon: 'shield' },
          ],
          selected: 'last',
        });
      }, 900);
      return true;
    case 'spawnHover': return true;
    case 'spawnConfirm':
      emit('cutscene', { on: true });
      setTimeout(() => { emit('close', {}); }, 4000);
      setTimeout(() => { emit('lobby', payload()); pushAudio(); }, 5500);
      return { ok: true };
    case 'createStart': setTimeout(() => emit('create', { slot: d.slot }), 200); return { ok: true };
    case 'createGender': return true;
    case 'createCancel': setTimeout(() => emit('lobby', payload()), 200); return true;
    case 'createSubmit': {
      await sleep(500);
      const f = d.form;
      if (`${f.firstname} ${f.lastname}`.toLowerCase() === 'john doe') return { ok: false, errors: { lastname: 'Someone already uses this name' }, msg: 'Someone already uses this name' };
      emit('hide', {});
      setTimeout(() => emit('toast', { type: 'success', text: 'Character created' }), 300);
      setTimeout(() => handler('play', {}), 2500);
      return { ok: true };
    }
    case 'delete': {
      const i = chars.findIndex((c) => c.slot === d.slot);
      if (i < 0) return { ok: false, msg: 'Not found' };
      if (d.confirm.toLowerCase() !== chars[i].name.toLowerCase()) return { ok: false, msg: 'The name does not match' };
      chars.splice(i, 1);
      if (selected === d.slot) selected = chars[0]?.slot || 1;
      pushData();
      return { ok: true, msg: 'Character deleted' };
    }
    case 'squadSearch': {
      const q = String(d.query).toLowerCase();
      await sleep(250);
      return { results: people.filter((p) => p.toLowerCase().includes(q)).map((p, i) => ({ id: `C${(i * 7919).toString(36).toUpperCase().padStart(5, '0')}`, name: p, online: i % 2 === 0 })) };
    }
    case 'squadRequest': {
      const p = people.find((_x, i) => `C${(i * 7919).toString(36).toUpperCase().padStart(5, '0')}` === d.target) || 'Player';
      squad = { ...squad, outgoing: [...squad.outgoing, { id: Date.now(), type: d.type, to: { id: d.target, name: p }, at: Math.floor(Date.now() / 1000) }] };
      pushSquad();
      return { ok: true, msg: `Request sent to ${p}` };
    }
    case 'squadRespond': {
      const inc = squad.incoming.find((r) => r.id === d.id);
      if (inc) {
        squad = { ...squad, incoming: squad.incoming.filter((r) => r.id !== d.id) };
        if (d.accept) squad.links = [...squad.links, { id: inc.id, type: inc.type, slot: 4, visible: true, other: { id: inc.from!.id, name: inc.from!.name, online: true, job: { label: 'Civilian' } } }];
      } else {
        squad = { ...squad, links: squad.links.map((l) => (l.id === d.id ? { ...l, type: d.accept && l.pendingType ? l.pendingType : l.type, pendingType: null } : l)) };
      }
      pushSquad();
      return { ok: true, msg: d.accept ? 'You are now linked' : 'Declined' };
    }
    case 'squadRemove':
      squad = { links: squad.links.filter((l) => l.id !== d.id), incoming: squad.incoming.filter((l) => l.id !== d.id), outgoing: squad.outgoing.filter((l) => l.id !== d.id) };
      pushSquad();
      return { ok: true };
    case 'squadSwitch':
      squad = { ...squad, links: squad.links.map((l) => (l.id === d.id ? { ...l, pendingType: d.type, pendingByMe: true } : l)) };
      pushSquad();
      return { ok: true, msg: 'Switch requested' };
    case 'squadSlot': {
      const me = squad.links.find((l) => l.id === d.id);
      squad = { ...squad, links: squad.links.map((l) => (l.id === d.id ? { ...l, slot: d.slot } : l.slot === d.slot && me ? { ...l, slot: me.slot } : l)) };
      pushSquad();
      return { ok: true };
    }
    case 'squadVisible':
      squad = { ...squad, links: squad.links.map((l) => (l.id === d.id ? { ...l, visible: d.visible } : l)) };
      return { ok: true };
    case 'settings': Object.assign(settings, d.settings); return { ...settings };
    case 'sound': return true;
    case 'redeem': return String(d.code).toUpperCase() === 'VIP' ? { ok: true, msg: '1 slot(s) added' } : { ok: false, msg: 'Code not found or already used' };
    case 'quit': emit('toast', { type: 'info', text: 'See you soon.' }); return true;
  }
  return true;
}

export function installMock() {
  window.__nzMock = handler;
  // so the in-game cfg.settings stays the source of truth on mock reloads
  (window as any).__nzEmit = emit;
}

/** Open a view from the URL: ?view=start|lobby|create|spawn|cutscene&section=lobby|customize|squad&modal=settings&tab=pet */
export function afterBoot() {
  const q = new URLSearchParams(location.search);
  const view = q.get('view') || 'start';
  startPlates();
  go(view);
  const st = useStore.getState();
  const section = q.get('section');
  if (section) setTimeout(() => st.setSection(section as any), 50);
  const modal = q.get('modal');
  if (modal === 'settings' || modal === 'quit') setTimeout(() => st.setModal({ kind: modal }), 80);
  if (modal === 'delete') setTimeout(() => st.setModal({ kind: 'delete', slot: 2 }), 80);
}

export function go(view: string) {
  switch (view) {
    case 'start': emit('start', { serverName: 'NAYZEEE', playerName: 'nayzeee', prompt: 'Press ENTER to continue', socials: cfg.ui.socials }); break;
    case 'lobby': emit('lobby', payload()); emit('select', { slot: selected }); break;
    case 'create': emit('create', { slot: 4 }); break;
    case 'spawn': handler('play', {}); break;
    case 'cutscene': emit('lobby', payload()); setTimeout(() => emit('cutscene', { on: true }), 100); break;
  }
}
