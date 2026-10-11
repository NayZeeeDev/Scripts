import { createSlice, PayloadAction } from '@reduxjs/toolkit';
import type { RootState } from '.';

export type Rarity = 'common' | 'uncommon' | 'rare' | 'epic' | 'legendary' | 'mythic';
export type FontChoice = 'default' | 'roboto' | 'manrope' | 'montserrat' | 'inter';

export interface Settings {
  layout: 'default' | 'perspective';
  view: 'fullscreen' | 'compact';
  font: FontChoice;
  brand: boolean;
  accent: string;
  opacity: number;
  hotbarStyle: 'normal' | 'hexagon';
  notifyStyle: 'default' | 'modern';
  slotShape: 'square' | 'hexagon';
}

export interface PlayerInfo {
  name?: string;
  id?: number;
  wallet?: number;
  bank?: number;
  job?: string;
  grade?: string;
  avatar?: string;
}

export interface UiConfig {
  brandName: string;
  brandLogo?: string;
  brandTagline?: string;
  playerCard: boolean;
  showBank: boolean;
  showJob: boolean;
  giveMenu: boolean;
  clothing: boolean;
  colors: string[];
  currency: string;
}

export interface GiveRequest {
  slot: number;
  count: number;
}

export const defaultSettings: Settings = {
  layout: 'default',
  view: 'fullscreen',
  font: 'default',
  brand: true,
  accent: '#c4f82a',
  opacity: 90,
  hotbarStyle: 'normal',
  notifyStyle: 'default',
  slotShape: 'square',
};

export const defaultConfig: UiConfig = {
  brandName: 'NAYZEE',
  brandTagline: 'Inventory',
  playerCard: true,
  showBank: true,
  showJob: true,
  giveMenu: true,
  clothing: true,
  colors: ['#c4f82a', '#ff3b3b', '#1fd6f2', '#8a5cff', '#ff4fd8', '#ffb31a'],
  currency: '$',
};

interface UiState {
  settings: Settings;
  draft: Settings | null;
  config: UiConfig;
  player: PlayerInfo | null;
  search: string;
  searchOpen: boolean;
  clothingOpen: boolean;
  settingsOpen: boolean;
  give: GiveRequest | null;
}

const initialState: UiState = {
  settings: defaultSettings,
  draft: null,
  config: defaultConfig,
  player: null,
  search: '',
  searchOpen: false,
  clothingOpen: false,
  settingsOpen: false,
  give: null,
};

export const uiSlice = createSlice({
  name: 'ui',
  initialState,
  reducers: {
    loadSettings(state, action: PayloadAction<Partial<Settings> | undefined>) {
      state.settings = { ...defaultSettings, ...(action.payload || {}) };
    },
    setConfig(state, action: PayloadAction<Partial<UiConfig> | undefined>) {
      state.config = { ...defaultConfig, ...(action.payload || {}) };
    },
    setPlayer(state, action: PayloadAction<PlayerInfo | null>) {
      state.player = action.payload;
    },
    setWallet(state, action: PayloadAction<number>) {
      if (state.player) state.player.wallet = action.payload;
    },
    setSearch(state, action: PayloadAction<string>) {
      state.search = action.payload;
    },
    setSearchOpen(state, action: PayloadAction<boolean>) {
      state.searchOpen = action.payload;
      if (!action.payload) state.search = '';
    },
    toggleView(state) {
      state.settings.view = state.settings.view === 'fullscreen' ? 'compact' : 'fullscreen';
    },
    setClothingOpen(state, action: PayloadAction<boolean>) {
      state.clothingOpen = action.payload;
    },
    openSettings(state) {
      state.settingsOpen = true;
      state.draft = { ...state.settings };
    },
    closeSettings(state) {
      state.settingsOpen = false;
      state.draft = null;
    },
    updateDraft(state, action: PayloadAction<Partial<Settings>>) {
      if (state.draft) state.draft = { ...state.draft, ...action.payload };
    },
    restoreDraft(state) {
      if (state.draft) state.draft = { ...defaultSettings, view: state.draft.view };
    },
    commitDraft(state) {
      if (state.draft) state.settings = { ...state.draft };
    },
    openGive(state, action: PayloadAction<GiveRequest>) {
      state.give = action.payload;
    },
    closeGive(state) {
      state.give = null;
    },
    resetUi(state) {
      state.give = null;
      state.settingsOpen = false;
      state.draft = null;
      state.searchOpen = false;
      state.search = '';
      state.clothingOpen = false;
    },
  },
});

export const {
  loadSettings,
  setConfig,
  setPlayer,
  setWallet,
  setSearch,
  setSearchOpen,
  toggleView,
  setClothingOpen,
  openSettings,
  closeSettings,
  updateDraft,
  restoreDraft,
  commitDraft,
  openGive,
  closeGive,
  resetUi,
} = uiSlice.actions;

export const selectSettings = (state: RootState) => state.ui.draft ?? state.ui.settings;
export const selectConfig = (state: RootState) => state.ui.config;

export default uiSlice.reducer;
