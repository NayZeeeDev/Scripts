import { useEffect, useRef } from 'react';
import useNuiEvent from '../../hooks/useNuiEvent';
import { useAppDispatch, useAppSelector } from '../../store';
import {
  loadSettings,
  resetUi,
  selectSettings,
  setConfig,
  setPlayer,
  setWallet,
  Settings,
  UiConfig,
  PlayerInfo,
} from '../../store/ui';
import { setRarityMap } from '../../store/rarity';
import { setStrings } from '../../store/strings';
import { fetchNui } from '../../utils/fetchNui';
import { isEnvBrowser } from '../../utils/misc';
import { hexToRgb } from './format';

const FONTS: Record<Settings['font'], string> = {
  default: "'Outfit', 'Gilroy', sans-serif",
  roboto: "'Roboto', sans-serif",
  manrope: "'Manrope', sans-serif",
  montserrat: "'Montserrat', sans-serif",
  inter: "'Inter', sans-serif",
};

const STORAGE_KEY = 'nz_inventory_settings';

interface ReadyPayload {
  config?: Partial<UiConfig>;
  settings?: Partial<Settings>;
  rarity?: Record<string, string>;
  strings?: Record<string, string>;
}

const readLocal = (): Partial<Settings> | undefined => {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : undefined;
  } catch {
    return undefined;
  }
};

// Glue between the NUI and nz/client.lua plus the CSS theme variables.
// Everything here is event driven; nothing polls.
const Bridge: React.FC = () => {
  const dispatch = useAppDispatch();
  const settings = useAppSelector(selectSettings);
  const saved = useAppSelector((state) => state.ui.settings);
  const loaded = useRef(false);

  const applyReady = (data?: ReadyPayload) => {
    if (!data) return;
    setRarityMap(data.rarity);
    setStrings(data.strings);
    if (data.config) dispatch(setConfig(data.config));
    if (data.settings || !loaded.current) dispatch(loadSettings(data.settings ?? readLocal()));
    loaded.current = true;
  };

  useEffect(() => {
    if (isEnvBrowser()) {
      dispatch(loadSettings(readLocal()));
      loaded.current = true;
      return;
    }
    fetchNui<ReadyPayload>('nz:ready')
      .then(applyReady)
      .catch(() => {
        dispatch(loadSettings(readLocal()));
        loaded.current = true;
      });
  }, []);

  useNuiEvent<ReadyPayload>('nz:init', applyReady);
  useNuiEvent<Record<string, string>>('nz:rarity', (map) => setRarityMap(map));
  useNuiEvent<PlayerInfo>('nz:player', (info) => dispatch(setPlayer(info)));
  useNuiEvent<number>('nz:wallet', (wallet) => dispatch(setWallet(wallet)));

  useNuiEvent('setupInventory', () => {
    fetchNui<PlayerInfo>('nz:getPlayerInfo')
      .then((info) => info && dispatch(setPlayer(info)))
      .catch(() => {});
  });

  useNuiEvent('closeInventory', () => {
    dispatch(resetUi());
    fetchNui('nz:clothing', { action: 'close' }).catch(() => {});
  });

  // persist saved settings (not drafts)
  const first = useRef(true);
  useEffect(() => {
    if (first.current) {
      first.current = false;
      return;
    }
    if (!loaded.current) return;
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(saved));
    } catch {}
    fetchNui('nz:saveSettings', saved).catch(() => {});
  }, [saved]);

  // theme variables
  useEffect(() => {
    const root = document.documentElement.style;
    root.setProperty('--accent', settings.accent);
    root.setProperty('--accent-rgb', hexToRgb(settings.accent));
    root.setProperty('--bg-a', String(Math.min(100, Math.max(0, settings.opacity)) / 100));
    root.setProperty('--font', FONTS[settings.font] || FONTS.default);
    document.body.dataset.notify = settings.notifyStyle;
    document.body.dataset.hotbar = settings.hotbarStyle;
  }, [settings]);

  return null;
};

export default Bridge;
