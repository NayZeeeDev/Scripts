/**
 * Manage keys: the player search (empty state, results with matched plates, recently opened
 * players) and a player's key page. The plate view and the track dialog open over both.
 * Search runs on Enter and 450 ms after typing (2+ characters); late answers of an older
 * query are dropped.
 */
import { useCallback, useEffect, useRef, useState } from 'react';
import { Avatar, Badge, Button, EmptyState, Icon, Kbd, SearchInput, SkeletonRows, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import { request } from '@/lib/nui';
import type { KeyAdminOpenData, KeyAdminPlayer } from '@/lib/types';
import { PlayerView } from './PlayerView';
import { PlateModal } from './PlateModal';
import { TrackModal } from './TrackModal';
import { list, pushRecent, readRecent } from './model';
import type { RecentPlayer } from './model';

const DEBOUNCE_MS = 450;

export interface Nav {
  openPlayer: (identifier: string, name?: string) => void;
  openPlate: (plate: string) => void;
  track: (plate: string, label?: string | null) => void;
}

export function ManageKeys({ data, active }: { data: KeyAdminOpenData; active: boolean }) {
  const [query, setQuery] = useState(data.query ?? '');
  const [results, setResults] = useState<KeyAdminPlayer[] | null>(null);
  const [searched, setSearched] = useState('');
  const [loading, setLoading] = useState(false);
  const [player, setPlayer] = useState<{ identifier: string; name?: string } | null>(
    data.identifier ? { identifier: data.identifier } : null,
  );
  const [plate, setPlate] = useState<string | null>(data.plate ?? null);
  const [track, setTrack] = useState<{ plate: string; label?: string | null } | null>(null);
  const [recent, setRecent] = useState<RecentPlayer[]>(() => readRecent());
  /** bumped when the plate view changed keys: the player page reloads */
  const [changeTick, setChangeTick] = useState(0);
  const seq = useRef(0);
  const timer = useRef<number>();

  const search = useCallback(async (raw: string) => {
    window.clearTimeout(timer.current);
    const q = raw.trim();
    if (q.length < 1) return;
    const id = ++seq.current;
    setLoading(true);
    const res = await request('keyadmin:search', { query: q });
    if (id !== seq.current) return;
    setLoading(false);
    setSearched(q);
    setResults(res.ok ? list(res.data?.rows).map((p) => ({ ...p, matchedPlates: list(p.matchedPlates) })) : []);
  }, []);

  // live search while typing
  useEffect(() => {
    window.clearTimeout(timer.current);
    const q = query.trim();
    if (q.length < 2 || q === searched) return;
    timer.current = window.setTimeout(() => void search(q), DEBOUNCE_MS);
    return () => window.clearTimeout(timer.current);
  }, [query, searched, search]);

  // an initial query from the open data runs at once
  useEffect(() => {
    if (data.query) void search(data.query);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const nav: Nav = {
    openPlayer: (identifier, name) => {
      setPlate(null);
      setPlayer({ identifier, name });
    },
    openPlate: (p) => setPlate(p),
    track: (p, label) => setTrack({ plate: p, label }),
  };

  const onPlayerLoaded = useCallback((identifier: string, name: string) => {
    setRecent(pushRecent({ identifier, name }));
  }, []);

  const clear = () => {
    seq.current++;
    setQuery('');
    setResults(null);
    setSearched('');
    setLoading(false);
  };

  return (
    <div className="nz-kadm-keys">
      {player ? (
        <PlayerView
          key={player.identifier}
          identifier={player.identifier}
          initialName={player.name}
          fobDesign={data.fobDesign ?? null}
          tempKeyHours={data.tempKeyHours ?? 24}
          active={active && !plate && !track}
          changeTick={changeTick}
          onBack={() => setPlayer(null)}
          onLoaded={onPlayerLoaded}
          nav={nav}
        />
      ) : (
        <div className="nz-kadm-search">
          <SearchInput
            value={query}
            onChange={setQuery}
            onEnter={() => void search(query)}
            placeholder={t('Search a player by name, citizen ID, server ID or plate')}
            shortcut="Enter"
            loading={loading}
            autoFocus
            className="nz-kadm-search__input"
          />
          <div className="nz-kadm-search__body">
            {results === null ? (
              <div className="nz-kadm-search__intro">
                <EmptyState
                  icon="users"
                  title={t('Search for a player')}
                  description={t('Type a name, a citizen ID, a server ID or a plate and press Enter. Plates find the vehicle owner.')}
                />
                {recent.length > 0 && (
                  <div className="nz-kadm-recent">
                    <h4 className="nz-kadm-heading">{t('Recently opened')}</h4>
                    <div className="nz-kadm-recent__list">
                      {recent.map((r) => (
                        <button key={r.identifier} type="button" className="nz-kadm-recent__item" onClick={() => nav.openPlayer(r.identifier, r.name)}>
                          <Avatar name={r.name} size={24} />
                          <span className="nz-kadm-recent__name">{r.name}</span>
                          <Icon name="chevronRight" size={13} strokeWidth={1.8} />
                        </button>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            ) : loading && results.length === 0 ? (
              <SkeletonRows count={5} />
            ) : results.length === 0 ? (
              <EmptyState
                icon="search"
                title={t('Nobody matches “{query}”', { query: searched })}
                description={t('Check the spelling, or search the plate or citizen ID instead.')}
                action={
                  <Button size="sm" icon="close" onClick={clear}>
                    {t('Clear search')}
                  </Button>
                }
              />
            ) : (
              <div className={cx('nz-kadm-results', loading && 'is-loading')}>
                <h4 className="nz-kadm-heading">
                  {t('{n} player(s)', { n: results.length })}
                  <span>{t('for “{query}”', { query: searched })}</span>
                </h4>
                <div className="nz-kadm-results__list" role="list">
                  {results.map((p) => (
                    <div key={p.identifier} className="nz-kadm-result" role="listitem">
                      <button type="button" className="nz-kadm-result__main" onClick={() => nav.openPlayer(p.identifier, p.name)}>
                        <span className="nz-kadm-result__avatar">
                          <Avatar name={p.name} size={34} />
                          <i className={cx('nz-kadm-dot', p.online && 'is-on')} />
                        </span>
                        <span className="nz-kadm-result__who">
                          <b>{p.name}</b>
                          <span className="nz-kadm-mono">{p.identifier}</span>
                        </span>
                        {p.online ? (
                          <Badge tone="teal" size="sm" dot>
                            {p.serverId ? t('Online · ID {id}', { id: p.serverId }) : t('Online')}
                          </Badge>
                        ) : (
                          <Badge tone="neutral" size="sm">
                            {t('Offline')}
                          </Badge>
                        )}
                      </button>
                      {p.matchedPlates.length > 0 && (
                        <div className="nz-kadm-result__plates">
                          <span>{t('Plates')}</span>
                          {p.matchedPlates.slice(0, 6).map((pl) => (
                            <button key={pl} type="button" className="nz-kadm-plate" onClick={() => nav.openPlate(pl)} title={t('Open the plate view')}>
                              {pl}
                            </button>
                          ))}
                          {p.matchedPlates.length > 6 && <em>+{p.matchedPlates.length - 6}</em>}
                        </div>
                      )}
                      <button type="button" className="nz-kadm-result__go" onClick={() => nav.openPlayer(p.identifier, p.name)} aria-label={t('Open')}>
                        <Icon name="chevronRight" size={15} strokeWidth={1.8} />
                      </button>
                    </div>
                  ))}
                </div>
                <p className="nz-kadm-results__hint">
                  <Kbd>Enter</Kbd> {t('searches again')} · {t('at most 50 players are listed')}
                </p>
              </div>
            )}
          </div>
        </div>
      )}

      {plate && (
        <PlateModal
          plate={plate}
          fobDesign={data.fobDesign ?? null}
          onClose={() => setPlate(null)}
          onChanged={() => setChangeTick((n) => n + 1)}
          nav={nav}
        />
      )}
      {track && <TrackModal plate={track.plate} label={track.label} onClose={() => setTrack(null)} />}
    </div>
  );
}
