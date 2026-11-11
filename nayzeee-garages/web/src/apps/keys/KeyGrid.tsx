/**
 * Key ring grid: the toolbar (search, filter chips Owned / Shared / Temporary / Items with
 * counts, the player's key order) and the fob cards. Each card draws the key with FobArt (its
 * design, the vehicle's brand badge), the vehicle name, plate, kind badge and a status corner
 * (lock state, distance or "not out", temporary key countdown). Cards are radio options:
 * click selects, double click uses the key (tap = lock / unlock).
 */
import { memo, useEffect, useRef } from 'react';
import { Chip, Icon, PlateTag, SearchInput, Select, cx } from '@/components/ui';
import { FobArt } from '@/components/fob/FobArt';
import { t } from '@/lib/i18n';
import type { KeyEntry, KeyGroup } from '@/lib/types';
import { KindGlyph } from './glyphs';
import { chipLabel, countdown, displayName, fobOf, kindInfo, meters, orderLabel } from './model';
import type { KeyFilter, KeyOrder, Unit } from './model';

const ORDERS: KeyOrder[] = ['recent', 'name', 'plate', 'distance'];

export interface KeyToolbarProps {
  query: string;
  onQuery: (q: string) => void;
  filter: KeyFilter;
  onFilter: (f: KeyFilter) => void;
  counts: Record<KeyFilter, number>;
  present: KeyGroup[];
  order: KeyOrder;
  onOrder: (o: KeyOrder) => void;
}

export function KeyToolbar({ query, onQuery, filter, onFilter, counts, present, order, onOrder }: KeyToolbarProps) {
  const chips: KeyFilter[] = ['all', 'owned', 'shared', 'temp', 'items'];
  return (
    <div className="nz-keys__toolbar">
      <div className="nz-keys__search">
        <SearchInput value={query} onChange={onQuery} placeholder={t('Search plate, name or model')} shortcut="/" />
      </div>
      <div className="nz-keys__chips" role="group" aria-label={t('Filter keys')}>
        {chips.map((c) => (
          <Chip
            key={c}
            active={filter === c}
            count={counts[c]}
            disabled={c !== 'all' && !present.includes(c as KeyGroup)}
            onClick={() => onFilter(c)}
          >
            {chipLabel(c)}
          </Chip>
        ))}
      </div>
      <div className="nz-keys__order" title={t('Key order (your settings)')}>
        <Select<KeyOrder>
          size="sm"
          icon="sort"
          value={order}
          onChange={onOrder}
          options={ORDERS.map((o) => ({ value: o, label: orderLabel(o) }))}
        />
      </div>
    </div>
  );
}

export interface KeyGridProps {
  keys: KeyEntry[];
  selected: string | null;
  onSelect: (plate: string) => void;
  onActivate: (plate: string) => void;
  leftOf: (k: KeyEntry) => number | null;
  unit: Unit;
  /** the fob art of this plate shows a pressed button (hold stage) */
  pressed: { plate: string; button: string } | null;
}

export function KeyGrid({ keys, selected, onSelect, onActivate, leftOf, unit, pressed }: KeyGridProps) {
  const ref = useRef<HTMLDivElement>(null);
  // keep the selected card in view (keyboard selection)
  useEffect(() => {
    if (!selected) return;
    const el = ref.current?.querySelector<HTMLElement>(`[data-plate="${CSS.escape(selected)}"]`);
    el?.scrollIntoView({ block: 'nearest' });
  }, [selected]);
  return (
    <div ref={ref} className="nz-keys__grid" role="radiogroup" aria-label={t('Your keys')}>
      {keys.map((k) => (
        <KeyCard
          key={k.plate}
          k={k}
          on={k.plate === selected}
          left={leftOf(k)}
          unit={unit}
          active={pressed && pressed.plate === k.plate ? pressed.button : null}
          onSelect={onSelect}
          onActivate={onActivate}
        />
      ))}
    </div>
  );
}

interface KeyCardProps {
  k: KeyEntry;
  on: boolean;
  left: number | null;
  unit: Unit;
  active: string | null;
  onSelect: (plate: string) => void;
  onActivate: (plate: string) => void;
}

const KeyCard = memo(function KeyCard({ k, on, left, unit, active, onSelect, onActivate }: KeyCardProps) {
  const kind = kindInfo(k);
  const fob = fobOf(k);
  const status = statusOf(k, unit);
  return (
    <button
      type="button"
      role="radio"
      aria-checked={on}
      data-plate={k.plate}
      tabIndex={on ? 0 : -1}
      className={cx('nz-keys-card', on && 'is-on', (!k.spawned || k.towing) && 'is-away', k.alarm && 'is-alarm')}
      onClick={() => onSelect(k.plate)}
      onDoubleClick={() => onActivate(k.plate)}
    >
      <span className={cx('nz-keys-card__kind', `is-${kind.tone}`)} title={kind.label}>
        <KindGlyph glyph={kind.glyph} size={11} strokeWidth={2} />
        {k.kind === 'temp' && left !== null ? countdown(left) : kind.label}
      </span>
      <span className={cx('nz-keys-card__status', `is-${status.tone}`)} title={status.title}>
        {status.icon && <Icon name={status.icon} size={11} strokeWidth={2} />}
        {status.text}
      </span>
      <span className="nz-keys-card__stage" aria-hidden="true">
        <FobArt design={fob.design} kind={fob.kind} brand={k.make || null} size={112} active={active} className="nz-keys-card__art" />
      </span>
      <span className="nz-keys-card__name" title={displayName(k)}>
        {displayName(k)}
      </span>
      <span className="nz-keys-card__sub">
        <PlateTag plate={k.plate} size="sm" />
        {k.nickname && k.label && <small title={k.label}>{k.label}</small>}
      </span>
    </button>
  );
});

function statusOf(k: KeyEntry, unit: Unit): { text: string; tone: 'teal' | 'amber' | 'red' | 'grey'; icon?: 'lock' | 'unlock' | 'impound'; title: string } {
  if (k.towing) return { text: t('Towed'), tone: 'red', icon: 'impound', title: t('On the impound tow truck') };
  if (!k.spawned) return { text: t('Not out'), tone: 'grey', title: t('Parked or stored') };
  const where = k.distance !== null ? meters(k.distance, unit) : t('Out');
  if (k.locked === true) return { text: where, tone: 'teal', icon: 'lock', title: t('Locked') };
  if (k.locked === false) return { text: where, tone: 'amber', icon: 'unlock', title: t('Unlocked') };
  return { text: where, tone: 'grey', title: t('Out in the city') };
}
