/**
 * Types shared by the "Map command" location pages (LocationListPage + the four page specs).
 *
 * - CardTag   small labelled tag on a directory card ("Everyone", "Interior + menu", "8 per player").
 * - Fact      one label / value row in the inspector's kind section.
 * - Kpi       one tile of the KPI strip. value null = still loading (skeleton).
 * - LocationPageContext  what spec callbacks receive: the admin data, per-location stats and
 *             the owned copies of private locations (undefined = loading, 'error' = failed).
 */
import type { ReactNode } from 'react';
import type { IconName } from '@/components/ui';
import type { AdminOpenData, GroupInfo, Location, LocationStats } from '@/lib/types';

export type TagTone = 'neutral' | 'teal' | 'amber' | 'blue' | 'red' | 'white';

export interface CardTag {
  icon?: IconName;
  label: string;
  tone?: TagTone;
  /** Tooltip with the full text (tags are truncated). */
  title?: string;
}

export interface Fact {
  label: string;
  value: ReactNode;
  tone?: 'amber' | 'muted';
  /** Full text for truncated values. */
  title?: string;
}

export interface Kpi {
  key: string;
  icon: IconName;
  label: string;
  /** null = loading. */
  value: string | number | null;
  /** Small text right after the value ("/ 12"). */
  unit?: string;
  /** Second line ("11 enabled · 1 disabled"). */
  sub?: string;
  /** 0–1: thin bar along the bottom of the tile. */
  ratio?: number | null;
  tone?: 'teal' | 'blue' | 'amber' | 'red';
}

export interface LocationPageContext {
  data: AdminOpenData;
  stats: (loc: Location) => LocationStats;
  /** Private locations only: owned copies. undefined while loading. */
  groups: (id: number | null) => GroupInfo[] | 'error' | undefined;
}
