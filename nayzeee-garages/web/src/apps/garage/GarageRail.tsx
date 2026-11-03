/**
 * Garage rail content: the toolbar (search with "/" keycap, filter chips with counts, sort,
 * group-by and density) and the row bodies for owned vehicles and spawner vehicles.
 */
import type { ReactNode } from 'react';
import { Chip, Icon, PlateTag, SearchInput, Segmented, Select, Tooltip, cx } from '@/components/ui';
import type { IconName, SelectOption } from '@/components/ui';
import { t } from '@/lib/i18n';
import { money } from '@/lib/format';
import type { GarageVehicle, SpawnerVehicleView } from '@/lib/types';
import { modelName, platePreview, vehicleStatus } from './model';
import type { GarageFilter, GarageSort, GroupBy, ViewMode } from './model';
import { FavStar, RowBody, StatusDot } from './showroom/Rail';

/* ── toolbar ─────────────────────────────────────────────────────────── */

export interface RailToolbarProps {
  query: string;
  onQuery: (q: string) => void;
  placeholder: string;
  chips?: { value: GarageFilter; label: string; icon?: IconName; count: number }[];
  filter?: GarageFilter;
  onFilter?: (f: GarageFilter) => void;
  sort?: GarageSort;
  onSort?: (s: GarageSort) => void;
  groupBy?: GroupBy;
  onGroupBy?: (g: GroupBy) => void;
  groupOptions?: SelectOption<GroupBy>[];
  view: ViewMode;
  onView: (v: ViewMode) => void;
  /** Extra line under the controls (garage full notice, job hint). */
  notice?: ReactNode;
  /** Only the search box (empty collection). */
  bare?: boolean;
}

export function RailToolbar({
  query,
  onQuery,
  placeholder,
  chips,
  filter,
  onFilter,
  sort,
  onSort,
  groupBy,
  onGroupBy,
  groupOptions,
  view,
  onView,
  notice,
  bare = false,
}: RailToolbarProps) {
  const sortOptions: SelectOption<GarageSort>[] = [
    { value: 'relevance', label: t('Relevance'), icon: 'sparkle' },
    { value: 'name', label: t('Name'), icon: 'sort' },
    { value: 'mileage', label: t('Mileage'), icon: 'gauge' },
    { value: 'condition', label: t('Condition'), icon: 'wrench' },
    { value: 'lastUsed', label: t('Last driven'), icon: 'history' },
  ];
  const groups: SelectOption<GroupBy>[] = groupOptions ?? [
    { value: 'class', label: t('By class'), icon: 'layers' },
    { value: 'status', label: t('By status'), icon: 'pin' },
    { value: 'none', label: t('No groups'), icon: 'list' },
  ];
  return (
    <div className="nz-garage__railtop">
      <SearchInput value={query} onChange={onQuery} placeholder={placeholder} shortcut="/" className="nz-garage__search" />
      {chips && chips.length > 1 && onFilter && (
        <div className="nz-garage__chips" role="toolbar" aria-label={t('Filter vehicles')}>
          {chips.map((c) => (
            <Chip key={c.value} active={filter === c.value} onClick={() => onFilter(c.value)} count={c.count} icon={c.icon}>
              {c.label}
            </Chip>
          ))}
        </div>
      )}
      {!bare && (
      <div className="nz-garage__railctl">
        {sort && onSort && (
          <Select<GarageSort> value={sort} onChange={onSort} options={sortOptions} size="sm" icon="sort" className="nz-garage__ctl-sort" />
        )}
        {groupBy && onGroupBy && (
          <Select<GroupBy>
            value={groupBy}
            onChange={onGroupBy}
            options={groups}
            size="sm"
            className={cx('nz-garage__ctl-group', !sort && 'is-wide')}
          />
        )}
        <span className="nz-garage__spacer" />
        <Segmented<ViewMode>
          value={view}
          onChange={onView}
          size="sm"
          iconOnly
          options={[
            { value: 'grid', label: t('Comfortable rows'), icon: 'grid' },
            { value: 'list', label: t('Compact rows'), icon: 'list' },
          ]}
          className="nz-garage__ctl-density"
        />
      </div>
      )}
      {notice}
    </div>
  );
}

/* ── rows ────────────────────────────────────────────────────────────── */

function Mark({ icon, tone, tip }: { icon: IconName; tone?: 'amber' | 'red' | 'teal'; tip: string }) {
  return (
    <Tooltip content={tip}>
      <span className={cx('nz-garage__mark', tone && `is-${tone}`)} role="img" aria-label={tip}>
        <Icon name={icon} size={12} strokeWidth={1.9} />
      </span>
    </Tooltip>
  );
}

/** Small state marks after the status (service, finance, trailer, shared). */
function Marks({ v }: { v: GarageVehicle }) {
  const marks: ReactNode[] = [];
  if (v.needsService) marks.push(<Mark key="s" icon="wrench" tone="amber" tip={t('Needs service')} />);
  if (v.finance) {
    marks.push(
      <Mark
        key="f"
        icon="receipt"
        tone={v.finance.overdue ? 'red' : undefined}
        tip={v.finance.overdue ? t('Finance payment overdue') : t('Financed')}
      />,
    );
  }
  if (v.trailer) marks.push(<Mark key="t" icon="trailer" tip={t('With {trailer}', { trailer: v.trailer.label })} />);
  if (v.sharedBy) marks.push(<Mark key="u" icon="users" tone="teal" tip={t('Shared with you by {name}', { name: v.sharedBy })} />);
  else if (v.isOwner && v.sharedWith > 0) marks.push(<Mark key="u" icon="users" tip={t('Shared with {count} player(s)', { count: v.sharedWith })} />);
  if (!marks.length) return null;
  return <span className="nz-garage__marks">{marks}</span>;
}

export function GarageRow({ v, compact, onFavourite }: { v: GarageVehicle; compact: boolean; onFavourite: () => void }) {
  const st = vehicleStatus(v);
  const nick = (v.nickname ?? '').trim();
  return (
    <RowBody
      image={v.image}
      vehicleType={v.vehicleType}
      alt={v.label}
      compact={compact}
      title={nick || modelName(v)}
      aside={nick ? modelName(v) : undefined}
      dot={st.tone}
      meta={
        compact ? (
          <PlateTag plate={v.plate} size="sm" />
        ) : (
          <>
            <PlateTag plate={v.plate} size="sm" />
            <StatusDot tone={st.tone} label={st.label} />
            <Marks v={v} />
          </>
        )
      }
      side={<FavStar on={v.favourite} onToggle={onFavourite} />}
      health={v.engine}
    />
  );
}

export function SpawnerPlate({ template, size = 'sm' }: { template: string; size?: 'sm' | 'md' }) {
  const p = platePreview(template);
  if (!p) {
    return (
      <span className="nz-garage__randplate">
        <Icon name="hash" size={11} strokeWidth={2} />
        {t('Random plate')}
      </span>
    );
  }
  return <PlateTag plate={p.text} size={size} />;
}

export function SpawnerRow({ s, compact }: { s: SpawnerVehicleView; compact: boolean }) {
  return (
    <RowBody
      image={s.image}
      vehicleType={s.vehicleType}
      alt={s.label}
      compact={compact}
      title={modelName(s)}
      meta={
        compact ? (
          <SpawnerPlate template={s.plate} />
        ) : (
          <>
            <SpawnerPlate template={s.plate} />
            {s.make && <span className="nz-garage__rowmake">{s.make}</span>}
          </>
        )
      }
      side={s.price > 0 ? <span className="nz-garage__price">{money(s.price)}</span> : undefined}
    />
  );
}
