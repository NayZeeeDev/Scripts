import { create } from 'zustand';
import type {
  CharacterNui, LobbyPayload, Plate, Section, Settings, SpawnOption, SquadNui, StartData, Toast, UiConfig, View,
} from './types';
import { post } from './nui';
import { configureAudio, cue, setAmbience, shutdownAudio } from './audio';
import { setLocale } from '../i18n';
import { resolveAccent, setFormat } from './format';

export const DEFAULT_SETTINGS: Settings = {
  scale: 1, muted: false, uiVolume: 0.6, ambientVolume: 0.35, sway: true, dof: true, plates: true, perf: false, bars: true,
};

const EMPTY_SQUAD: SquadNui = { links: [], incoming: [], outgoing: [] };

export type Modal =
  | null
  | { kind: 'settings' }
  | { kind: 'quit' }
  | { kind: 'delete'; slot: number }
  | { kind: 'removeLink'; id: number; name: string };

interface State {
  cfg: UiConfig | null;
  view: View;
  prevView: View;
  start: StartData | null;
  lobby: LobbyPayload | null;
  selected: number;
  squad: SquadNui;
  plates: Plate[];
  camera: string;
  busy: { on: boolean; text?: string };
  toasts: Toast[];
  createSlot: number;
  spawn: { options: SpawnOption[]; selected?: string } | null;
  cutscene: boolean;
  settings: Settings;
  section: Section;
  modal: Modal;
  ambience: { ambience?: string | null; url?: string; theme?: string } | null;
  /** Black UI cover for the loading-screen hand-off. On from the very first paint until Lua lifts it. */
  veil: { on: boolean; ms: number };
  /** Frozen game frame covering a scene rebuild: id of the capture request, fading = crossfading away */
  freeze: { id: number; fading: boolean; ms: number } | null;

  boot: (cfg: UiConfig) => void;
  onMessage: (action: string, data: any) => void;
  setSection: (s: Section) => void;
  setModal: (m: Modal) => void;
  toast: (type: Toast['type'], text: string) => void;
  dismissToast: (id: number) => void;
  setSettings: (patch: Partial<Settings>) => void;
  selectSlot: (slot: number) => void;
  setCamera: (mode: string) => void;
  character: () => CharacterNui | undefined;
  patchCharacter: (slot: number, c: Partial<CharacterNui>) => void;
}

let toastId = 1;

function applyAccent(cfg: UiConfig) {
  const [hi, base, lo] = resolveAccent(cfg.ui?.accent, cfg.ui?.accents);
  const r = document.documentElement.style;
  r.setProperty('--accent-hi', hi);
  r.setProperty('--accent', base);
  r.setProperty('--accent-lo', lo);
}

function audioFrom(cfg: UiConfig | null, s: Settings) {
  configureAudio({
    muted: s.muted,
    uiVolume: s.uiVolume,
    ambVolume: s.ambientVolume,
    uiEnabled: cfg?.audio?.uiSounds !== false,
    ambEnabled: cfg?.audio?.ambience !== false,
  });
}

export const useStore = create<State>((set, get) => ({
  cfg: null,
  view: 'none',
  prevView: 'none',
  start: null,
  lobby: null,
  selected: 1,
  squad: EMPTY_SQUAD,
  plates: [],
  camera: 'squad',
  busy: { on: false },
  toasts: [],
  createSlot: 0,
  spawn: null,
  cutscene: false,
  settings: DEFAULT_SETTINGS,
  section: 'characters',
  modal: null,
  ambience: null,
  veil: { on: true, ms: 0 },
  freeze: null,

  boot: (cfg) => {
    setLocale(cfg.locale);
    setFormat(cfg.ui?.currency, cfg.ui?.dateFormat);
    applyAccent(cfg);
    const settings = { ...DEFAULT_SETTINGS, ...(cfg.settings || {}) };
    audioFrom(cfg, settings);
    set({ cfg, settings, ...(cfg.veil === false ? { veil: { on: false, ms: 0 } } : {}) });
  },

  onMessage: (action, d) => {
    const s = get();
    switch (action) {
      case 'start':
        set({ start: d || {}, view: 'start', cutscene: false, modal: null });
        break;
      case 'lobby': {
        const p = d as LobbyPayload;
        set({
          lobby: p, selected: p.selected ?? s.selected, squad: p.squad || EMPTY_SQUAD, camera: p.camera || s.camera,
          view: 'lobby', cutscene: false, section: 'characters', busy: { on: false },
        });
        cue('whoosh');
        break;
      }
      case 'data': {
        const p = d as LobbyPayload;
        set({ lobby: p, selected: p.selected ?? s.selected, squad: p.squad || s.squad, camera: p.camera || s.camera });
        break;
      }
      case 'select':
        set({ selected: d?.slot ?? s.selected });
        break;
      case 'squad':
        set({ squad: { ...EMPTY_SQUAD, ...(d || {}) } });
        break;
      case 'plates':
        set({ plates: d?.items || [] });
        break;
      case 'camera':
        set({ camera: d?.mode || s.camera });
        break;
      case 'busy':
        set({ busy: { on: !!d?.on, text: d?.text } });
        break;
      case 'toast':
        if (d?.text) get().toast(d.type || 'info', d.text);
        break;
      case 'create':
        set({ createSlot: d?.slot ?? s.createSlot, view: 'create', modal: null, busy: { on: false }, plates: [] });
        cue('whoosh');
        break;
      case 'spawn':
        set({ spawn: { options: d?.options || [], selected: d?.selected }, view: 'spawn', modal: null, busy: { on: false }, plates: [] });
        cue('whoosh');
        break;
      case 'cutscene':
        if (d?.on) set({ cutscene: true, prevView: s.view === 'cutscene' ? s.prevView : s.view, view: 'cutscene', modal: null, busy: { on: false }, plates: [] });
        else set({ cutscene: false, view: s.prevView === 'cutscene' ? 'none' : s.prevView });
        break;
      case 'hide':
        set({ view: 'hidden', modal: null, busy: { on: false }, plates: [] });
        break;
      case 'close':
        set({ view: 'none', modal: null, busy: { on: false }, plates: [], cutscene: false, toasts: [], section: 'characters', freeze: null, veil: { on: false, ms: 0 } });
        shutdownAudio();
        break;
      case 'audio': {
        // ambience = procedural preset key ('city', 'skydive' ...), theme = theme id, url = optional audio file
        const amb = { ambience: d?.ambience ?? null, url: d?.url || undefined, theme: d?.theme };
        set({ ambience: amb });
        const muted = typeof d?.muted === 'boolean' ? d.muted || s.settings.muted : s.settings.muted;
        setAmbience({ ...amb, muted }, s.cfg?.themes);
        break;
      }
      case 'veil':
        set({ veil: { on: !!d?.on, ms: Math.max(0, Number(d?.ms) || 0) } });
        break;
      case 'freeze':
        set({ freeze: { id: Number(d?.id) || 0, fading: false, ms: 0 } });
        break;
      case 'unfreeze':
        if (s.freeze) set({ freeze: { ...s.freeze, fading: true, ms: Math.max(0, Number(d?.ms) || 900) } });
        break;
      case 'settings': {
        const settings = { ...s.settings, ...(d || {}) };
        set({ settings });
        audioFrom(s.cfg, settings);
        break;
      }
    }
  },

  setSection: (section) => {
    if (section === get().section) return;
    set({ section });
  },

  setModal: (modal) => set({ modal }),

  toast: (type, text) => {
    const id = toastId++;
    set({ toasts: [...get().toasts.slice(-3), { id, type, text }] });
    if (type === 'error') cue('error');
    window.setTimeout(() => get().dismissToast(id), type === 'error' ? 5200 : 3800);
  },
  dismissToast: (id) => set({ toasts: get().toasts.filter((x) => x.id !== id) }),

  setSettings: (patch) => {
    const settings = { ...get().settings, ...patch };
    set({ settings });
    audioFrom(get().cfg, settings);
    if ('muted' in patch && get().ambience) setAmbience({ ...get().ambience!, muted: settings.muted }, get().cfg?.themes);
    post<Settings>('settings', { settings }).then((r) => {
      if (r && typeof r === 'object' && 'scale' in r) set({ settings: { ...get().settings, ...r } });
    });
  },

  selectSlot: (slot) => {
    if (slot === get().selected) return;
    set({ selected: slot });
    cue('tick');
    post('select', { slot });
  },

  setCamera: (mode) => {
    if (mode === get().camera) return;
    set({ camera: mode });
    cue('tick');
    post('camera', { mode });
  },

  character: () => {
    const { lobby, selected } = get();
    return lobby?.characters.find((c) => c.slot === selected);
  },

  patchCharacter: (slot, c) => {
    const lobby = get().lobby;
    if (!lobby) return;
    set({ lobby: { ...lobby, characters: lobby.characters.map((x) => (x.slot === slot ? { ...x, ...c } : x)) } });
  },
}));

export const useChar = () => useStore((s) => s.lobby?.characters.find((c) => c.slot === s.selected));
