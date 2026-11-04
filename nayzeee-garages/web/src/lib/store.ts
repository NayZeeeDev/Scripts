/**
 * Global UI state: which apps are open and their data, HUD widgets, in-interface toasts, settings.
 * Apps read their slot with useApp('<name>'); nothing else should hold app data globally.
 * toast() hands every notification to Lua, which decides where it is drawn (see below).
 */
import { create } from 'zustand';
import { fetchNui, isBrowser, onNuiMessage, setErrorReporter } from './nui';
import { applyAccent } from './theme';
import type {
  AppDataMap,
  AppName,
  HintData,
  HudVehicle,
  InterfaceSettings,
  NotifyRequest,
  NotifyType,
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
  keys: { open: false, data: null },
  locksmith: { open: false, data: null },
  contract: { open: false, data: null },
});

export interface UiState {
  ready: boolean;
  locale: Record<string, string>;
  settings: InterfaceSettings;
  apps: Slots;
  hud: HudVehicle | null;
  prompt: PromptData | null;
  hint: HintData | null;
  /** Notifications drawn inside the interface (Lua 'notify' message), newest last, max 5. */
  toasts: (Toast & { id: string })[];
  openApp: <K extends AppName>(app: K, data: AppDataMap[K]) => void;
  updateApp: <K extends AppName>(app: K, partial: Partial<AppDataMap[K]>) => void;
  /** Close locally only (Lua already knows). Use closeApp() to also tell Lua. */
  hideApp: (app?: AppName | null) => void;
  /** Draw a notification inside the interface. Use toast() to raise one: Lua decides where. */
  pushToast: (t: Toast) => void;
  dismissToast: (id: string) => void;
}

/** Most toasts on screen at once; the oldest is dropped. */
const MAX_TOASTS = 5;
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
      if (!t || typeof t.message !== 'string' || !t.message.trim()) return s;
      const next = [...s.toasts, { ...t, id: `t${++toastSeq}` }];
      return { toasts: next.slice(-MAX_TOASTS) };
    }),
  dismissToast: (id) => set((s) => ({ toasts: s.toasts.filter((t) => t.id !== id) })),
}));

/* ───────────────────────── notifications ───────────────────────── */

/** Limits of the Lua 'notify' callback, in characters (code points). */
const NOTIFY_MAX_MESSAGE = 300;
const NOTIFY_MAX_TITLE = 60;
const NOTIFY_TYPES: readonly NotifyType[] = ['success', 'error', 'info', 'warning'];

/** Collapse whitespace and cap to `max` characters, ending with an ellipsis when cut. */
function clipText(value: unknown, max: number): string {
  const text = String(value ?? '')
    .replace(/\s+/g, ' ')
    .trim();
  const chars = Array.from(text);
  return chars.length > max ? `${chars.slice(0, max - 1).join('').trimEnd()}…` : text;
}

/**
 * Raise a notification from anywhere (React or not). It always goes to Lua (NUI callback
 * 'notify'), which decides where it is drawn: while one of our windows holds NUI focus it comes
 * straight back as a 'notify' message and <Toasts /> draws it (FiveM draws the focused page above
 * every other resource's NUI, so the notify resource would be hidden behind the window);
 * otherwise it goes through the configured notify integration (Config.Integrations.notify).
 * The browser dev harness behaves like a focused window: it draws the toast and logs it.
 */
export function toast(n: NotifyRequest) {
  const message = clipText(n.message, NOTIFY_MAX_MESSAGE);
  if (!message) return;
  const title = n.title ? clipText(n.title, NOTIFY_MAX_TITLE) : '';
  const type: NotifyType = NOTIFY_TYPES.includes(n.type) ? n.type : 'info';
  const payload: NotifyRequest = title ? { type, title, message } : { type, message };
  if (isBrowser) {
    console.info(`[notify:${type}] ${title ? `${title} · ` : ''}${message}`);
    useUi.getState().pushToast(payload);
    return;
  }
  void fetchNui('notify', payload);
}

// Failed request() calls are reported the same way (see lib/nui.ts).
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
