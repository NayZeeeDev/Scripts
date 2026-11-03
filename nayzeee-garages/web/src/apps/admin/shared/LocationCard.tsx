/**
 * LocationCard — one location in the Map command directory (not a table row).
 *
 *   <LocationCard loc tags stats kind selected hovered busy warning? onSelect onEdit onHover onToggle />
 *
 * Type icon tile (car / boat / plane, tinted per type; grey when disabled), name + mono #id,
 * tags (access, mode, capacity… from the page spec), a vehicles line (parked · out · impounded,
 * or held for impounds) and the enabled Toggle. Selected: teal edge + glowing left bar.
 * Disabled cards are dimmed. Click selects, double-click edits; keyboard is handled by the list.
 */
import { memo } from 'react';
import { Icon, Toggle, Tooltip, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { Location, LocationKind, LocationStats } from '@/lib/types';
import type { CardTag } from './commandTypes';
import { vehicleTypeIcon, vehicleTypeLabel } from './labels';

export interface LocationCardProps {
  loc: Location;
  kind: LocationKind;
  tags: CardTag[];
  stats: LocationStats;
  selected: boolean;
  hovered: boolean;
  busy: boolean;
  /** Amber flag shown next to the name (e.g. no interaction point yet). */
  warning?: string | null;
  onSelect: (loc: Location) => void;
  onEdit: (loc: Location) => void;
  onHover: (id: string | number | null) => void;
  onToggle: (loc: Location) => void;
}

const fmt = (n: number) => n.toLocaleString('en-US');

export function VehicleLine({
  stats,
  kind,
  spawner = false,
  compact = false,
}: {
  stats: LocationStats;
  kind: LocationKind;
  /** Spawner location: its vehicles are taken out on demand and never stored. */
  spawner?: boolean;
  compact?: boolean;
}) {
  if (kind === 'impound') {
    return (
      <span className={cx('nz-admin-cmd__vline', compact && 'is-compact')}>
        <span className={cx('nz-admin-cmd__vstat', 'is-held', !stats.held && 'is-zero')}>
          <i />
          <b>{fmt(stats.held)}</b> {t('held')}
        </span>
      </span>
    );
  }
  const total = stats.parked + stats.out + stats.impounded;
  if (!total && spawner) {
    return (
      <span className={cx('nz-admin-cmd__vline', 'is-empty', compact && 'is-compact')}>
        <span className="nz-admin-cmd__vstat is-spawner">
          <Icon name="key" size={11} strokeWidth={2} />
          {t('Vehicles spawn on demand')}
        </span>
      </span>
    );
  }
  if (!total) {
    return (
      <span className={cx('nz-admin-cmd__vline', 'is-empty', compact && 'is-compact')}>
        <span className="nz-admin-cmd__vstat is-zero">
          <i />
          {t('No vehicles yet')}
        </span>
      </span>
    );
  }
  return (
    <span className={cx('nz-admin-cmd__vline', compact && 'is-compact')}>
      <span className={cx('nz-admin-cmd__vstat', 'is-parked', !stats.parked && 'is-zero')}>
        <i />
        <b>{fmt(stats.parked)}</b> {t('parked')}
      </span>
      <span className={cx('nz-admin-cmd__vstat', 'is-out', !stats.out && 'is-zero')}>
        <i />
        <b>{fmt(stats.out)}</b> {t('out')}
      </span>
      {stats.impounded > 0 && (
        <span className="nz-admin-cmd__vstat is-impounded">
          <i />
          <b>{fmt(stats.impounded)}</b> {t('impounded')}
        </span>
      )}
    </span>
  );
}

export const LocationCard = memo(function LocationCard({
  loc,
  kind,
  tags,
  stats,
  selected,
  hovered,
  busy,
  warning,
  onSelect,
  onEdit,
  onHover,
  onToggle,
}: LocationCardProps) {
  const id = loc.id ?? loc.name;
  return (
    <div
      role="option"
      aria-selected={selected}
      tabIndex={selected ? 0 : -1}
      data-loc={String(id)}
      className={cx('nz-admin-cmd__card', selected && 'is-selected', hovered && 'is-hover', !loc.enabled && 'is-off')}
      onClick={() => onSelect(loc)}
      onDoubleClick={(e) => {
        if ((e.target as HTMLElement).closest('.nz-toggle')) return;
        onEdit(loc);
      }}
      onMouseEnter={() => onHover(loc.id)}
      onMouseLeave={() => onHover(null)}
    >
      <span className={cx('nz-admin-cmd__type', `is-${loc.enabled ? loc.vehicleType : 'off'}`)} title={vehicleTypeLabel(loc.vehicleType)}>
        <Icon name={vehicleTypeIcon(loc.vehicleType)} size={17} strokeWidth={1.6} />
      </span>

      <span className="nz-admin-cmd__card-main">
        <span className="nz-admin-cmd__card-top">
          <b className="nz-admin-cmd__card-name" title={loc.name}>
            {loc.name}
          </b>
          {loc.id !== null && <span className="nz-admin-cmd__card-id">#{loc.id}</span>}
          {warning && (
            <Tooltip content={warning}>
              <span className="nz-admin-cmd__card-warn" role="img" aria-label={warning}>
                <Icon name="warning" size={11} strokeWidth={2} />
              </span>
            </Tooltip>
          )}
        </span>
        <span className="nz-admin-cmd__tags">
          {!loc.enabled && (
            <span className="nz-admin-cmd__tag is-muted">
              <Icon name="ban" size={11} strokeWidth={1.9} />
              <span>{t('Disabled')}</span>
            </span>
          )}
          {tags.map((tag, i) => (
            <span key={i} className={cx('nz-admin-cmd__tag', `is-${tag.tone ?? 'neutral'}`)} title={tag.title ?? tag.label}>
              {tag.icon && <Icon name={tag.icon} size={11} strokeWidth={1.9} />}
              <span className={cx(tag.short && 'nz-admin-cmd__tag-long')}>{tag.label}</span>
              {tag.short && <span className="nz-admin-cmd__tag-short">{tag.short}</span>}
            </span>
          ))}
        </span>
        <VehicleLine stats={stats} kind={kind} spawner={(loc.kind === 'garage' || loc.kind === 'job') && loc.source === 'spawner'} />
      </span>

      <span className="nz-admin-cmd__card-side" onClick={(e) => e.stopPropagation()} onDoubleClick={(e) => e.stopPropagation()}>
        <Tooltip content={loc.enabled ? t('Enabled: click to disable') : t('Disabled: click to enable')} side="left">
          <Toggle size="sm" checked={loc.enabled} disabled={busy} onChange={() => onToggle(loc)} />
        </Tooltip>
      </span>
    </div>
  );
});
