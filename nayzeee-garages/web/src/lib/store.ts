/**
 * Global UI state: which apps are open and their data, HUD widgets, toasts, settings.
 * Apps read their slot with useApp('<name>'); nothing else should hold app data globally.
 */
import { create } from 'zustand';
import { fetchNui, onNuiMessage, setErrorReporter } from './nui';
import { applyAccent } from './theme';
import type {
  AppDataMap,
  AppName,
  HintData,
  HudVehicle,
  InterfaceSettings,
  NuiMessage,
  PromptData,
  Toast,
} from './types';

export const defaultInterface: InterfaceSettings = {
  defaultView: 'grid',
  distanceUnit: 'mi',
  currency: '$',
  imageUrl: 'https://docs.fivem.net/vehicles/{model}.webp',
  showImages: true,
  accent: '#08afa2',
  interaction: 'prompt',
};

type Slots = { [K in AppName]: { open: boolean; data: AppDataMap[K] | null } };

const emptySlots = (): Slots => ({
  garage: { open: false, data: null },
  impound: { open: false, data: null },
  impoundForm: { open: false, data: null },
  forSale: { open: false, data: null },
  admin: { open: false, data: null },
  creator: { open: false, data: null },
  setup: { open: false, data: null },
  interior: { open: false, data: null },
});

export interface UiState {
  ready: boolean;
  locale: Record<string, string>;
  settings: InterfaceSettings;
  apps: Slots;
  hud: HudVehicle | null;
  prompt: PromptData | null;
  hint: HintData | null;
  toasts: (Toast & { id: string })[];
  openApp: <K extends AppName>(app: K, data: AppDataMap[K]) => void;
  updateApp: <K extends AppName>(app: K, partial: Partial<AppDataMap[K]>) => void;
  /** Close locally only (Lua already knows). Use closeApp() to also tell Lua. */
  hideApp: (app?: AppName | null) => void;
  pushToast: (t: Toast) => void;
  dismissToast: (id: string) => void;
}

let toastSeq = 0;

export const useUi = create<UiState>((set) => ({
  ready: false,
  locale: {},
  settings: defaultInterface,
  apps: emptySlots(),
  hud: null,
  prompt: null,
  hint: null,
  toasts: [],
  openApp: (app, data) =>
    set((s) => ({ apps: { ...s.apps, [app]: { open: true, data } } })),
  updateApp: (app, partial) =>
    set((s) => {
      const slot = s.apps[app];
      if (!slot.data) return s;
      // A complete garage payload replaces the old one: Lua omits nil fields (e.g. capacity),
      // so a shallow merge would keep stale values.
      const full = app === 'garage' && partial && 'garage' in partial && 'vehicles' in partial;
      const data = full ? (partial as AppDataMap[typeof app]) : { ...slot.data, ...partial };
      return { apps: { ...s.apps, [app]: { ...slot, data } } };
    }),
  hideApp: (app) =>
    set((s) => {
      if (!app) return { apps: emptySlots() };
      return { apps: { ...s.apps, [app]: { open: false, data: s.apps[app].data } } };
    }),
  pushToast: (t) =>
    set((s) => {
      const id = t.id ?? `t${++toastSeq}`;
      const next = [...s.toasts.filter((x) => x.id !== id), { ...t, id }];
      return { toasts: next.slice(-5) };
    }),
  dismissToast: (id) => set((s) => ({ toasts: s.toasts.filter((t) => t.id !== id) })),
}));

/** Show a toast from anywhere (React or not). */
export function toast(t: Toast) {
  useUi.getState().pushToast(t);
}

setErrorReporter((message) => toast({ type: 'error', message }));

/** Close an app: tell Lua (releases focus / cleans up) and hide it locally. */
export function closeApp(app: AppName) {
  useUi.getState().hideApp(app);
  void fetchNui('close', { app });
}

/** Read + control one app slot. */
export function useApp<K extends AppName>(app: K) {
  const slot = useUi((s) => s.apps[app]) as { open: boolean; data: AppDataMap[K] | null };
  return {
    open: slot.open,
    data: slot.data,
    close: () => closeApp(app),
    update: (partial: Partial<AppDataMap[K]>) => useUi.getState().updateApp(app, partial),
    replace: (data: AppDataMap[K]) => useUi.getState().openApp(app, data),
  };
}

export function useSettings() {
  return useUi((s) => s.settings);
}

function handleMessage(msg: NuiMessage) {
  const st = useUi.getState();
  switch (msg.action) {
    case 'init': {
      const settings = { ...defaultInterface, ...msg.data.settings };
      applyAccent(settings.accent);
      useUi.setState({ ready: true, locale: msg.data.locale ?? {}, settings });
      break;
    }
    case 'settings': {
      const settings = { ...defaultInterface, ...msg.data };
      applyAccent(settings.accent);
      useUi.setState({ settings });
      break;
    }
    case 'open':
      st.openApp(msg.data.app, msg.data.data as never);
      break;
    case 'update':
      st.updateApp(msg.data.app, msg.data.data as never);
      break;
    case 'close':
      st.hideApp(msg.data?.app ?? null);
      break;
    case 'hud':
      useUi.setState({ hud: msg.data });
      break;
    case 'prompt':
      useUi.setState({ prompt: msg.data });
      break;
    case 'hint':
      useUi.setState({ hint: msg.data });
      break;
    case 'notify':
      st.pushToast(msg.data);
      break;
  }
}

onNuiMessage(handleMessage);
