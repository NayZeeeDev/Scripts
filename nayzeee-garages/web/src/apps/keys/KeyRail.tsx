/**
 * Key ring rail: search, group chips and the keys grouped Owned · Shared with you · Temporary ·
 * Key items. Each row: vehicle thumbnail with the key-kind pip, name, plate, kind badge (Key /
 * Fob / Temporary with time left / Virtual), and on the right the lock state + distance of a
 * vehicle that is out. Selection = v5 nav style (teal wash + glowing left bar).
 */
import { useEffect, useRef } from 'react';
import { Chip, Icon, PlateTag, SearchInput, VehicleImage, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { KeyEntry, KeyGroup } from '@/lib/types';
import { KindGlyph } from './glyphs';
import { chipLabel, countdown, displayName, groupLabel, kindInfo, meters } from './model';
import type { KeyFilter } from './model';

export interface RailGroup {
  key: KeyGroup;
  items: KeyEntry[];
}

interface ToolbarProps {
  query: string;
  onQuery: (q: string) => void;
  filter: KeyFilter;
  onFilter: (f: KeyFilter) => void;
  counts: Record<KeyFilter, number>;
  present: KeyGroup[];
}

export function KeyToolbar({ query, onQuery, filter, onFilter, counts, present }: ToolbarProps) {
  const chips: KeyFilter[] = ['all', ...present];
  return (
    <div className="nz-keys__railtop">
      <SearchInput value={query} onChange={onQuery} placeholder={t('Search plate, name or model')} shortcut="/" />
      {present.length > 1 && (
        <div className="nz-keys__chips" role="tablist" aria-label={t('Key groups')}>
          {chips.map((c) => (
            <Chip key={c} active={filter === c} count={counts[c]} onClick={() => onFilter(c)}>
              {chipLabel(c)}
            </Chip>
          ))}
        </div>
      )}
    </div>
  );
}

interface ListProps {
  groups: RailGroup[];
  selected: string | null;
  onSelect: (plate: string) => void;
  onActivate: (plate: string) => void;
  /** seconds left of a temporary key right now */
  leftOf: (k: KeyEntry) => number | null;
  unit: 'mi' | 'km';
  locating: string | null;
}

export function KeyList({ groups, selected, onSelect, onActivate, leftOf, unit, locating }: ListProps) {
  const scrollRef = useRef<HTMLDivElement>(null);
  const rows = useRef(new Map<string, HTMLDivElement>());

  // keep the selected row in view below the sticky heading
  useEffect(() => {
    const scroller = scrollRef.current;
    const row = selected ? rows.current.get(selected) : null;
    if (!scroller || !row) return;
    const sr = scroller.getBoundingClientRect();
    const rr = row.getBoundingClientRect();
    const head = 38;
    if (rr.top < sr.top + head) scroller.scrollBy({ top: rr.top - sr.top - head - 4 });
    else if (rr.bottom > sr.bottom - 6) scroller.scrollBy({ top: rr.bottom - sr.bottom + 6 });
  }, [selected]);

  return (
    <div ref={scrollRef} className="nz-keys__list" role="listbox" aria-label={t('Your keys')}>
      {groups.map((g) => (
        <div key={g.key} className="nz-keys__group" role="group" aria-label={groupLabel(g.key)}>
          <div className="nz-keys__grouphead">
            <span>{groupLabel(g.key)}</span>
            <b>{g.items.length}</b>
          </div>
          {g.items.map((k) => (
            <div
              key={k.plate}
              ref={(el) => {
                if (el) rows.current.set(k.plate, el);
                else rows.current.delete(k.plate);
              }}
              role="option"
              aria-selected={k.plate === selected}
              tabIndex={-1}
              className={cx('nz-keys__row', k.plate === selected && 'is-selected', !k.spawned && 'is-away', k.towing && 'is-towing')}
              onClick={() => onSelect(k.plate)}
              onDoubleClick={() => onActivate(k.plate)}
            >
              <KeyRow k={k} left={leftOf(k)} unit={unit} locating={locating === k.plate} />
            </div>
          ))}
        </div>
      ))}
    </div>
  );
}

function KeyRow({ k, left, unit, locating }: { k: KeyEntry; left: number | null; unit: 'mi' | 'km'; locating: boolean }) {
  const kind = kindInfo(k);
  const name = displayName(k);
  const nick = (k.nickname ?? '').trim();
  return (
    <>
      <span className="nz-keys__thumb">
        <VehicleImage image={k.image} vehicleType={k.vehicleType} alt={name} className="nz-keys__thumb-img" />
        <span className={cx('nz-keys__pip', `is-${kind.tone}`)} title={kind.label}>
          <KindGlyph glyph={kind.glyph} size={11} strokeWidth={2} />
        </span>
      </span>
      <span className="nz-keys__rowtext">
        <span className="nz-keys__rowname">
          <b title={name}>{name}</b>
          {k.alarm && <i className="nz-keys__alarmdot" title={t('Alarm sounding')} />}
          {nick && k.label && <em title={k.label}>{k.label}</em>}
        </span>
        <span className="nz-keys__rowmeta">
          <PlateTag plate={k.plate} size="sm" />
          <span className={cx('nz-keys__kind', `is-${kind.tone}`)}>
            {k.kind === 'temp' && left !== null ? (
              <>
                <Icon name="clock" size={10} strokeWidth={2.2} />
                {countdown(left)}
              </>
            ) : (
              kind.label
            )}
          </span>
        </span>
      </span>
      <span className="nz-keys__rowside">
        {k.towing ? (
          <>
            <span className="nz-keys__lockpip is-towed" title={t('Being towed to the impound')}>
              <Icon name="impound" size={11} strokeWidth={1.9} />
            </span>
            <span className="nz-keys__where is-red">{t('Towed')}</span>
          </>
        ) : k.spawned ? (
          <>
            {k.locked !== null && (
              <span className={cx('nz-keys__lockpip', k.locked ? 'is-locked' : 'is-open')} title={k.locked ? t('Locked') : t('Unlocked')}>
                <Icon name={k.locked ? 'lock' : 'unlock'} size={11} strokeWidth={2} />
              </span>
            )}
            <span className={cx('nz-keys__where', locating && 'is-teal')}>{k.distance !== null ? meters(k.distance, unit) : t('Out')}</span>
          </>
        ) : (
          <span className="nz-keys__where is-grey">{t('Not out')}</span>
        )}
      </span>
    </>
  );
}
