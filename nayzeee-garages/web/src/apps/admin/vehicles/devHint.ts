/**
 * Dev-only deep links for the Admin B pages (player vehicles, interiors, settings).
 * Browser mocks put `__adminB` on AdminOpenData so a scenario can open a nested view
 * directly; Lua never sends it and it is ignored inside FiveM.
 */
import { isBrowser } from '@/lib/nui';
import type { AdminOpenData } from '@/lib/types';

export interface AdminBDevHint {
  /** PlayerVehiclesPage: pre-run a search. */
  search?: string;
  /** PlayerVehiclesPage: open this player's vehicle list. */
  player?: string;
  /** PlayerVehiclesPage: open this vehicle detail (needs `player`). */
  plate?: string;
  /** PlayerVehiclesPage: open the props editor on the detail. */
  props?: boolean;
  /** PlayerVehiclesPage: initial dossier tab ('overview', 'condition', 'upgrades', 'finance', 'history', 'activity', 'data'). */
  dossierTab?: string;
  /** InteriorsPage: open the create modal. */
  create?: boolean;
  /** SettingsPage: initial tab. */
  tab?: string;
}

export function devHint(data: AdminOpenData): AdminBDevHint {
  if (!isBrowser) return {};
  return (data as AdminOpenData & { __adminB?: AdminBDevHint }).__adminB ?? {};
}
