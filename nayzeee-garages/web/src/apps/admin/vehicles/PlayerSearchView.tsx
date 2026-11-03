/**
 * Player vehicles — level 1: search characters by name, identifier or plate
 * (admin:players:search, server-paged).
 */
import { useRef } from 'react';
import type { KeyboardEvent } from 'react';
import { Avatar, Button, EmptyState, KeyHint, Pagination, SearchInput, Table } from '@/components/ui';
import type { TableColumn } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { Paged, PlayerSearchRow } from '@/lib/types';
import { Highlight, OnlineDot, PlateList } from './common';

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
  onSearch: (page: number) => void;
  onOpen: (row: PlayerSearchRow) => void;
}

export function PlayerSearchView({ state, onQuery, onSearch, onOpen }: Props) {
  const wrapRef = useRef<HTMLDivElement>(null);
  const { result, submitted, loading } = state;
  const q = submitted ?? '';

  const columns: TableColumn<PlayerSearchRow>[] = [
    {
      key: 'player',
      header: t('Player'),
      width: '38%',
      render: (r) => (
        <span className="nz-aveh-player">
          <span className="nz-aveh-player__av">
            <Avatar name={r.name} size={28} />
            <OnlineDot online={r.online} />
          </span>
          <b className="nz-aveh-ellipsis">
            <Highlight text={r.name} query={q} />
          </b>
        </span>
      ),
    },
    {
      key: 'identifier',
      header: t('Identifier'),
      width: '24%',
      className: 'nz-aveh-mono',
      render: (r) => <Highlight text={r.identifier} query={q} />,
    },
    {
      key: 'plates',
      header: t('Matched plates'),
      render: (r) => <PlateList plates={r.matchedPlates} query={q} />,
    },
  ];

  // ↓ from the search field jumps into the results.
  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    if (e.key !== 'ArrowDown' || (e.target as HTMLElement).tagName !== 'INPUT') return;
    const first = wrapRef.current?.querySelector<HTMLElement>('.nz-table tbody tr[tabindex]');
    if (first) {
      e.preventDefault();
      first.focus();
    }
  };

  const pageCount = result ? Math.max(1, Math.ceil(result.total / Math.max(1, result.pageSize))) : 1;
  const showIntro = !result && !loading;

  return (
    <div className="nz-aveh-view" ref={wrapRef} onKeyDown={onKeyDown}>
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
        <div className="nz-aveh-card nz-aveh-card--fill">
          <Table
            columns={columns}
            rows={result?.rows ?? []}
            rowKey={(r) => r.identifier}
            onRowClick={onOpen}
            loading={loading}
            skeletonRows={6}
            empty={
              <EmptyState
                icon="search"
                compact
                title={t('No players found')}
                description={
                  q
                    ? t('Nothing matches “{query}”. Try part of a name, the full identifier or at least two plate characters.', { query: q })
                    : t('There are no characters yet.')
                }
              />
            }
          />
          {result && result.total > 0 && (
            <div className="nz-aveh-card__foot">
              <Pagination
                page={result.page}
                pageCount={pageCount}
                total={result.total}
                pageSize={result.pageSize}
                onChange={(p) => onSearch(p)}
              />
            </div>
          )}
        </div>
      )}
    </div>
  );
}
