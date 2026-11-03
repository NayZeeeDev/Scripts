/**
 * Player vehicles — level 1: search characters by name, identifier or plate
 * (admin:players:search, server-paged). Results are player cards (arrow keys + Enter).
 */
import { useRef } from 'react';
import type { KeyboardEvent } from 'react';
import { Avatar, Button, EmptyState, Icon, KeyHint, Pagination, SearchInput, Skeleton, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { Paged, PlayerSearchRow } from '@/lib/types';
import { Highlight, OnlineDot, moveFocus } from './common';
import { Plate } from './dossier/parts';

export interface SearchState {
  /** What is typed. */
  query: string;
  /** Query of the last search (results belong to it). */
  submitted: string | null;
  result: Paged<PlayerSearchRow> | null;
  loading: boolean;
  error: string | null;
}

export const emptySearch: SearchState = { query: '', submitted: null, result: null, loading: false, error: null };

interface Props {
  state: SearchState;
  onQuery: (q: string) => void;
  /** Run a new search with what is typed (Enter / Search button). */
  onSearch: (page: number) => void;
  /** Another page of the current results: must reuse the submitted query, not what is typed. */
  onPage: (page: number) => void;
  onOpen: (row: PlayerSearchRow) => void;
}

const MAX_PLATES = 3;

function PlayerCard({ row, query, onOpen }: { row: PlayerSearchRow; query: string; onOpen: () => void }) {
  const plates = row.matchedPlates;
  return (
    <button type="button" className={cx('nz-aveh-pcard', row.online && 'is-online')} onClick={onOpen}>
      <span className="nz-aveh-pcard__top">
        <span className="nz-aveh-player__av">
          <Avatar name={row.name} size={38} />
          <OnlineDot online={row.online} />
        </span>
        <span className="nz-aveh-pcard__id">
          <b className="nz-aveh-ellipsis">
            <Highlight text={row.name} query={query} />
          </b>
          <span className="nz-aveh-mono nz-aveh-ellipsis">
            <Highlight text={row.identifier} query={query} />
          </span>
        </span>
        <span className={cx('nz-aveh-pcard__state', row.online && 'is-on')}>{row.online ? t('Online') : t('Offline')}</span>
      </span>
      <span className="nz-aveh-pcard__foot">
        {plates.length > 0 ? (
          <>
            <span className="nz-aveh-pcard__label">{plates.length === 1 ? t('Plate match') : t('{n} plate matches', { n: plates.length })}</span>
            <span className="nz-aveh-pcard__plates">
              {plates.slice(0, MAX_PLATES).map((p) => (
                <Plate key={p} plate={p} size="sm" />
              ))}
              {plates.length > MAX_PLATES && <em>+{plates.length - MAX_PLATES}</em>}
            </span>
          </>
        ) : (
          <span className="nz-aveh-pcard__label">{query ? t('Matched by name or identifier') : t('Character')}</span>
        )}
        <span className="nz-aveh-pcard__open">
          {t('Vehicles')}
          <Icon name="arrowRight" size={13} strokeWidth={1.8} />
        </span>
      </span>
    </button>
  );
}

export function PlayerSearchView({ state, onQuery, onSearch, onPage, onOpen }: Props) {
  const gridRef = useRef<HTMLDivElement>(null);
  const { result, submitted, loading } = state;
  const q = submitted ?? '';

  // ↓ from the search field jumps into the results; arrows move between cards.
  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    const target = e.target as HTMLElement;
    if (target.tagName === 'INPUT') {
      if (e.key !== 'ArrowDown') return;
      const first = gridRef.current?.querySelector<HTMLElement>('.nz-aveh-pcard');
      if (first) {
        e.preventDefault();
        first.focus();
      }
      return;
    }
    if (target.classList.contains('nz-aveh-pcard')) moveFocus(e, gridRef.current, '.nz-aveh-pcard');
  };

  const pageCount = result ? Math.max(1, Math.ceil(result.total / Math.max(1, result.pageSize))) : 1;
  const showIntro = !result && !loading;
  const rows = result?.rows ?? [];

  return (
    <div className="nz-aveh-view" onKeyDown={onKeyDown}>
      <div className="nz-aveh-toolbar">
        <SearchInput
          value={state.query}
          onChange={onQuery}
          onEnter={() => onSearch(1)}
          shortcut="Enter"
          autoFocus
          loading={loading}
          placeholder={t('Search by player name, identifier, or plate')}
          className="nz-aveh-grow"
        />
        <Button variant="white" icon="search" onClick={() => onSearch(1)} loading={loading}>
          {t('Search')}
        </Button>
      </div>

      {showIntro ? (
        <div className="nz-aveh-intro">
          <EmptyState
            icon="users"
            title={t('Search for a player')}
            description={t('Type a player name, identifier or vehicle plate above and press Enter to see matching players. Press Enter on an empty search to list everyone.')}
          />
          <div className="nz-aveh-intro__keys">
            <KeyHint keys={['Enter']} label={t('Search')} />
            <KeyHint keys={['ArrowDown']} label={t('Jump to results')} />
            <KeyHint keys={['Esc']} label={t('Clear')} />
          </div>
        </div>
      ) : (
        <div className="nz-aveh-card nz-aveh-card--fill nz-aveh-results">
          <div className="nz-aveh-results__head">
            <span>
              {loading && !result
                ? t('Searching…')
                : q
                  ? t('{n} players match “{query}”', { n: result?.total ?? 0, query: q })
                  : t('{n} players', { n: result?.total ?? 0 })}
            </span>
            {rows.length > 0 && <span className="nz-aveh-results__keys">{t('Arrow keys to move · Enter to open')}</span>}
          </div>
          <div className={cx('nz-aveh-results__scroll', loading && result && 'is-loading')}>
            {loading && !result ? (
              <div className="nz-aveh-pgrid">
                {Array.from({ length: 6 }, (_, i) => (
                  <div key={i} className="nz-aveh-pcard is-skel">
                    <span className="nz-aveh-pcard__top">
                      <Skeleton width={38} height={38} radius={8} />
                      <span className="nz-aveh-pcard__id">
                        <Skeleton width="62%" height={12} />
                        <Skeleton width="40%" height={9} style={{ marginTop: 7 }} />
                      </span>
                    </span>
                    <Skeleton width="48%" height={9} />
                  </div>
                ))}
              </div>
            ) : rows.length === 0 ? (
              <EmptyState
                icon="search"
                title={t('No players found')}
                description={
                  q
                    ? t('Nothing matches “{query}”. Try part of a name, the full identifier or at least two plate characters.', { query: q })
                    : t('There are no characters yet.')
                }
              />
            ) : (
              <div className="nz-aveh-pgrid" ref={gridRef}>
                {rows.map((r) => (
                  <PlayerCard key={r.identifier} row={r} query={q} onOpen={() => onOpen(r)} />
                ))}
              </div>
            )}
          </div>
          {result && result.total > 0 && (
            <div className="nz-aveh-card__foot">
              <Pagination page={result.page} pageCount={pageCount} total={result.total} pageSize={result.pageSize} onChange={(p) => onPage(p)} />
            </div>
          )}
        </div>
      )}
    </div>
  );
}
