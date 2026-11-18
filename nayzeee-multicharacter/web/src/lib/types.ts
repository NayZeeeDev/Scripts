// NUI protocol types — mirrors docs/CONTRACT.md §4 / §7

export interface Job { name?: string; label?: string; grade?: number; gradeLabel?: string }

export interface WeaponOpt { name: string; label: string; class?: string }

export interface Prefs {
  theme?: string; mood?: string; pose?: string; couplePose?: string;
  weapon?: string; pet?: string; petName?: string;
}

export interface CharacterNui {
  id: string;
  slot: number;
  firstname?: string;
  lastname?: string;
  name: string;
  dob?: string;
  age?: number;
  gender?: 'm' | 'f';
  nationality?: string;
  height?: number;
  backstory?: string;
  phone?: string;
  job?: Job;
  cash?: number;
  bank?: number;
  lastPlayed?: number;
  playtime?: number;
  createdAt?: number;
  favorite?: boolean;
  disabled?: boolean;
  locked?: boolean;
  prefs?: Prefs;
  weapon?: { name: string; label?: string; class?: string; tint?: number } | null;
  weapons?: WeaponOpt[];
  pet?: { id: string; model?: string; name?: string } | null;
  pets?: string[];
}

export type LinkType = 'squad' | 'couple';

export interface SquadLink {
  id: number;
  type: LinkType;
  slot: number;
  visible: boolean;
  pendingType?: LinkType | null;
  pendingByMe?: boolean;
  other: { id: string; name: string; job?: { label?: string }; online?: boolean; gender?: 'm' | 'f' };
}

export interface SquadReq { id: number; type: LinkType; from?: { id: string; name: string }; to?: { id: string; name: string }; at?: number }

export interface SquadNui { links: SquadLink[]; incoming: SquadReq[]; outgoing: SquadReq[] }

export interface LobbyPayload {
  characters: CharacterNui[];
  slots: { total: number; used: number; max: number; shown: number };
  selected: number;
  canDelete: boolean;
  theme: string;
  mood: string;
  camera: string;
  squad: SquadNui;
  online: number;
  maxPlayers: number;
}

export interface Plate {
  key: string; x: number; y: number; visible: boolean;
  name: string; sub?: string; badge?: 'self' | 'partner' | 'squad' | 'pet';
  online?: boolean | null;
}

export interface SpawnOption { id: string; kind?: string; label: string; desc?: string; icon?: string }

export interface Settings {
  scale: number; muted: boolean; uiVolume: number; ambientVolume: number;
  sway: boolean; dof: boolean; plates: boolean; perf: boolean; bars: boolean;
}

export interface Social { icon: string; label: string; url?: string }

export interface ThemeDef {
  id: string; label: string; description?: string; icon?: string; category?: string;
  palette?: [string, string, string] | string[];
  mood?: string;
  moods?: string[] | null;
  inFlight?: boolean;
  pets?: boolean;
  ambience?: { preset?: string; url?: string };
}

export interface UiConfig {
  version?: string;
  locale?: Record<string, unknown>;
  ui: {
    serverName?: string; tagline?: string; logo?: string;
    accent?: string | string[]; accentKey?: string; accents?: Record<string, string[]>;
    socials?: Social[]; keys?: Record<string, string>;
    scale?: number; currency?: { locale?: string; code?: string };
    dateFormat?: string; showOnline?: boolean; nameplates?: boolean;
  };
  start?: { enabled?: boolean; prompt?: string; subtitle?: string; orbit?: boolean; music?: string };
  themes: ThemeDef[];
  moods: { id: string; label: string; icon?: string; swatch?: string[] }[];
  poses: { id: string; label: string; icon?: string; category?: string; prop?: boolean; weapon?: boolean }[];
  couplePoses: { id: string; label: string; icon?: string }[];
  pets: { id: string; label: string; icon?: string; kind?: string }[];
  petOptions?: { enabled?: boolean; names?: boolean };
  weapon: { mode?: string; allowNone?: boolean; allowAuto?: boolean; enabled?: boolean };
  registration: {
    nameMin: number; nameMax: number; minAge: number; maxAge: number;
    height: { enabled: boolean; min: number; max: number; default: number } | false;
    nationality: { enabled: boolean; required?: boolean; default?: string } | false;
    backstory: { enabled: boolean; required?: boolean; min?: number; max?: number } | false;
    genders: string[];
    blacklist?: string[];
  };
  nationalities: string[];
  cameraModes: string[];
  squad: { enabled: boolean; maxLinks: number; searchMin: number; couples: boolean };
  audio: { ambience: boolean; uiSounds: boolean; volume?: { ui?: number; ambience?: number } };
  settings: Settings;
  scenePick?: boolean;
  typeToConfirm?: boolean;
}

export interface StartData { serverName?: string; playerName?: string; logo?: string; prompt?: string; socials?: Social[]; subtitle?: string; tagline?: string; version?: string }

export type View = 'none' | 'start' | 'lobby' | 'create' | 'spawn' | 'cutscene' | 'hidden';
export type Section = 'characters' | 'lobby' | 'customize' | 'squad';

export interface Toast { id: number; type: 'success' | 'error' | 'info' | 'warning'; text: string }

export interface CreateForm {
  firstname: string; lastname: string; dob: string; nationality: string;
  height: number; backstory: string; gender: 'm' | 'f';
}
