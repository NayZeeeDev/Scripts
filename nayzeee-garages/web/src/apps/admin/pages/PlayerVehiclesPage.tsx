/**
 * Admin › Player vehicles. Three in-page levels with back navigation (Escape goes back):
 *   search (admin:players:search) → player (admin:players:vehicles) → vehicle (admin:vehicle:*).
 * Search results and the player list survive going back and forth.
 */
import { useCallback, useEffect, useRef, useState } from 'react';
import { request } from '@/lib/nui';
import { useEscape } from '@/lib/escape';
import type { AdminPageProps, AdminVehicleRow, PlayerSearchRow } from '@/lib/types';
import { PlayerSearchView, emptySearch } from '../vehicles/PlayerSearchView';
import type { SearchState } from '../vehicles/PlayerSearchView';
import { PlayerView, emptyPlayerUi } from '../vehicles/PlayerView';
import type { PlayerData, PlayerUi } from '../vehicles/PlayerView';
import { VehicleDetailView } from '../vehicles/VehicleDetailView';
import { devHint } from '../vehicles/devHint';
import '../vehicles/vehicles.css';

type View =
  | { level: 'search' }
  | { level: 'player'; identifier: string; name: string }
  | { level: 'vehicle'; identifier: string; name: string; plate: string };

export function PlayerVehiclesPage({ data }: AdminPageProps) {
  const [hint] = useState(() => devHint(data));
  const [view, setView] = useState<View>(() =>
    hint.player
      ? hint.plate
        ? { level: 'vehicle', identifier: hint.player, name: '', plate: hint.plate }
        : { level: 'player', identifier: hint.player, name: '' }
      : { level: 'search' },
  );
  const [search, setSearch] = useState<SearchState>(() => ({ ...emptySearch, query: hint.search ?? '' }));
  const [player, setPlayer] = useState<PlayerData | null>(null);
  const [playerLoading, setPlayerLoading] = useState(false);
  const [playerError, setPlayerError] = useState<string | null>(null);
  const [ui, setUi] = useState<PlayerUi>(emptyPlayerUi);
  // Dev deep link "open the props editor" applies to the first vehicle view only.
  const [propsHint, setPropsHint] = useState(!!hint.props);
  const searchSeq = useRef(0);
  const playerSeq = useRef(0);

  /* ── search ── */
  const runSearch = useCallback(
    async (page: number, query?: string) => {
      const q = (query ?? search.query).trim();
      const id = ++searchSeq.current;
      setSearch((s) => ({ ...s, loading: true, error: null }));
      const res = await request('admin:players:search', { query: q, page });
      if (id !== searchSeq.current) return;
      setSearch((s) => ({
        ...s,
        loading: false,
        submitted: q,
        result: res.ok ? res.data : s.result,
        error: res.ok ? null : res.error,
      }));
    },
    [search.query],
  );

  /* ── player list ── */
  const loadPlayer = useCallback(async (identifier: string) => {
    const id = ++playerSeq.current;
    setPlayerLoading(true);
    setPlayerError(null);
    const res = await request('admin:players:vehicles', { identifier }, { toastError: false });
    if (id !== playerSeq.current) return;
    setPlayerLoading(false);
    if (res.ok) setPlayer(res.data);
    else setPlayerError(res.error);
  }, []);

  // Dev deep links (browser mocks only).
  useEffect(() => {
    if (hint.search !== undefined) void runSearch(1, hint.search);
    if (hint.player) void loadPlayer(hint.player);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const openPlayer = (row: PlayerSearchRow) => {
    if (player?.player.identifier !== row.identifier) {
      setPlayer(null);
      setUi(emptyPlayerUi);
      void loadPlayer(row.identifier);
    }
    setView({ level: 'player', identifier: row.identifier, name: row.name });
  };

  const openVehicle = (row: AdminVehicleRow) => {
    if (view.level === 'search') return;
    setView({ level: 'vehicle', identifier: view.identifier, name: view.name, plate: row.plate });
  };

  const back = () => {
    setPropsHint(false);
    if (view.level === 'vehicle') setView({ level: 'player', identifier: view.identifier, name: view.name });
    else if (view.level === 'player') setView({ level: 'search' });
  };
  useEscape(back, view.level !== 'search');

  /* ── keep the player list in sync with edits made on the detail ── */
  const onRowChange = useCallback((oldPlate: string, row: AdminVehicleRow | null) => {
    setPlayer((p) => {
      if (!p) return p;
      const vehicles = row
        ? p.vehicles.some((v) => v.plate === oldPlate)
          ? p.vehicles.map((v) => (v.plate === oldPlate ? row : v))
          : [...p.vehicles, row]
        : p.vehicles.filter((v) => v.plate !== oldPlate);
      return { ...p, vehicles };
    });
  }, []);

  const onPlateChange = useCallback((plate: string) => {
    setView((v) => (v.level === 'vehicle' ? { ...v, plate } : v));
  }, []);

  const onAssigned = (row: AdminVehicleRow) => {
    setPlayer((p) => (p ? { ...p, vehicles: [...p.vehicles, row].sort((a, b) => a.plate.localeCompare(b.plate)) } : p));
  };

  const fallbackName = view.level === 'search' ? '' : view.name || search.result?.rows.find((r) => r.identifier === view.identifier)?.name || view.identifier;

  return (
    <div className="nz-aveh" key={view.level} data-level={view.level}>
      {view.level === 'search' && (
        <PlayerSearchView
          state={search}
          onQuery={(query) => setSearch((s) => ({ ...s, query }))}
          onSearch={(page) => void runSearch(page)}
          onOpen={openPlayer}
        />
      )}
      {view.level === 'player' && (
        <PlayerView
          data={data}
          identifier={view.identifier}
          fallbackName={fallbackName}
          player={player?.player.identifier === view.identifier ? player : null}
          loading={playerLoading}
          error={playerError}
          ui={ui}
          onUi={(patch) => setUi((u) => ({ ...u, ...patch }))}
          onBack={back}
          onRetry={() => void loadPlayer(view.identifier)}
          onOpen={openVehicle}
          onAssigned={onAssigned}
        />
      )}
      {view.level === 'vehicle' && (
        <VehicleDetailView
          data={data}
          plate={view.plate}
          identifier={view.identifier}
          initialModal={propsHint ? 'props' : null}
          onBack={back}
          onRowChange={onRowChange}
          onPlateChange={onPlateChange}
        />
      )}
    </div>
  );
}
