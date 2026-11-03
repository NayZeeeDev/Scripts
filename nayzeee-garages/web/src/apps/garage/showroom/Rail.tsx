/**
 * Showroom rail: the grouped, scrollable collection on the left of the garage / impound
 * windows. Sticky uppercase group headings with counts, v5 nav-style selection (teal wash +
 * glowing left bar), smooth scroll-into-view of the selected row, skeleton rows.
 * The row content is rendered by the app (RowBody below covers the common layout).
 */
import { useEffect, useRef } from 'react';
import type { MouseEvent, ReactNode } from 'react';
import { Icon, Skeleton, Tooltip, VehicleImage, cx } from '@/components/ui';
import type { VehicleType } from '@/lib/types';
import { t } from '@/lib/i18n';
import type { ItemGroup, StatusTone } from '../model';

export interface RailListProps<T> {
  groups: ItemGroup<T>[];
  getKey: (item: T) => string;
  selected: string | null;
  onSelect: (key: string) => void;
  /** Double click on a row (drive / take out). */
  onActivate?: (key: string) => void;
  renderRow: (item: T, selected: boolean) => ReactNode;
  rowClass?: (item: T) => string | undefined;
  compact?: boolean;
  label: string;
}

const prefersReducedMotion = () =>
  typeof window !== 'undefined' && !!window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

export function RailList<T>({
  groups,
  getKey,
  selected,
  onSelect,
  onActivate,
  renderRow,
  rowClass,
  compact = false,
  label,
}: RailListProps<T>) {
  const scrollRef = useRef<HTMLDivElement>(null);
  const rows = useRef(new Map<string, HTMLDivElement>());
  const mounted = useRef(false);
  const headed = groups.some((g) => !!g.label);

  // Keep the selected row in view (below the sticky heading), only as far as needed.
  useEffect(() => {
    const scroller = scrollRef.current;
    const row = selected ? rows.current.get(selected) : null;
    if (!scroller || !row) return;
    const first = !mounted.current;
    mounted.current = true;
    const raf = requestAnimationFrame(() => {
      const sr = scroller.getBoundingClientRect();
      const rr = row.getBoundingClientRect();
      const head = headed ? 30 : 0;
      let shift = 0;
      if (rr.top < sr.top + head + 6) shift = rr.top - sr.top - head - 6;
      else if (rr.bottom > sr.bottom - 6) shift = rr.bottom - sr.bottom + 6;
      if (Math.abs(shift) > 1) {
        scroller.scrollBy({ top: shift, behavior: first || prefersReducedMotion() ? 'auto' : 'smooth' });
      }
    });
    return () => cancelAnimationFrame(raf);
  }, [selected, groups, headed]);

  return (
    <div ref={scrollRef} className={cx('nz-garage__list', compact && 'is-compact')} role="listbox" aria-label={label}>
      {groups.map((g) => (
        <div key={g.key} className="nz-garage__group" role="group" aria-label={g.label || undefined}>
          {g.label && (
            <div className="nz-garage__grouphead">
              <span>{g.label}</span>
              <b>{g.items.length}</b>
            </div>
          )}
          {g.items.map((it) => {
            const key = getKey(it);
            const sel = key === selected;
            return (
              <div
                key={key}
                ref={(el) => {
                  if (el) rows.current.set(key, el);
                  else rows.current.delete(key);
                }}
                role="option"
                aria-selected={sel}
                tabIndex={-1}
                className={cx('nz-garage__row', compact && 'is-compact', sel && 'is-selected', rowClass?.(it))}
                onClick={() => onSelect(key)}
                onDoubleClick={() => onActivate?.(key)}
              >
                {renderRow(it, sel)}
              </div>
            );
          })}
        </div>
      ))}
    </div>
  );
}

/** Loading placeholder for the rail (group switch, refresh). */
export function RailSkeleton({ count = 6, compact = false }: { count?: number; compact?: boolean }) {
  const widths = [62, 48, 70, 54, 44, 66, 58];
  return (
    <div className={cx('nz-garage__list', 'is-loading', compact && 'is-compact')} aria-busy="true" aria-label={t('Loading')}>
      <div className="nz-garage__grouphead">
        <Skeleton width={70} height={8} />
      </div>
      {Array.from({ length: count }, (_, i) => (
        <div key={i} className={cx('nz-garage__row', 'is-skel', compact && 'is-compact')}>
          {!compact && <Skeleton width={74} height={44} radius={6} className="nz-garage__thumb-skel" />}
          <span className="nz-garage__rowtext">
            <Skeleton width={`${widths[i % widths.length]}%`} height={9} />
            <Skeleton width={`${widths[(i + 3) % widths.length] - 18}%`} height={7} />
          </span>
        </div>
      ))}
    </div>
  );
}

/* ── row building blocks ─────────────────────────────────────────────── */

export function StatusDot({ tone, label, className }: { tone: StatusTone; label: string; className?: string }) {
  return (
    <span className={cx('nz-garage__status', `is-${tone}`, className)} title={label}>
      <i aria-hidden="true" />
      <span>{label}</span>
    </span>
  );
}

/** Star toggle used on rows (only visible when on, hovered or selected). */
export function FavStar({ on, onToggle, className }: { on: boolean; onToggle: () => void; className?: string }) {
  const label = on ? t('Remove from favourites') : t('Add to favourites');
  return (
    <Tooltip content={label} side="left">
      <button
        type="button"
        className={cx('nz-garage__star', on && 'is-on', className)}
        aria-label={label}
        aria-pressed={on}
        onClick={(e: MouseEvent) => {
          e.stopPropagation();
          onToggle();
        }}
        onDoubleClick={(e) => e.stopPropagation()}
      >
        <Icon name={on ? 'starFilled' : 'star'} size={13} strokeWidth={1.8} />
      </button>
    </Tooltip>
  );
}

export interface RowBodyProps {
  image: string | null;
  vehicleType: VehicleType;
  alt: string;
  compact: boolean;
  title: ReactNode;
  /** Small grey text after the title (model name when a nickname is shown). */
  aside?: ReactNode;
  meta: ReactNode;
  /** Right column (star, price, indicators). */
  side?: ReactNode;
  /** 0–100 → the 3px health bar on the row's bottom edge (omit to hide). */
  health?: number;
  /** Compact rows: status dot shown before the title. */
  dot?: StatusTone;
}

const healthTone = (v: number) => (v >= 50 ? 'teal' : v >= 25 ? 'amber' : 'red');

export function RowBody({ image, vehicleType, alt, compact, title, aside, meta, side, health, dot }: RowBodyProps) {
  return (
    <>
      {!compact && (
        <span className="nz-garage__thumb">
          <VehicleImage image={image} vehicleType={vehicleType} alt={alt} className="nz-garage__thumb-img" />
        </span>
      )}
      {compact && dot && <i className={cx('nz-garage__cdot', `is-${dot}`)} aria-hidden="true" />}
      <span className="nz-garage__rowtext">
        <span className="nz-garage__rowname">
          <b>{title}</b>
          {aside && <em>{aside}</em>}
        </span>
        {!compact && <span className="nz-garage__rowmeta">{meta}</span>}
      </span>
      {compact && <span className="nz-garage__rowmeta is-compact">{meta}</span>}
      {side && <span className="nz-garage__rowside">{side}</span>}
      {health !== undefined && (
        <span className="nz-garage__health" aria-hidden="true">
          <span className={`is-${healthTone(health)}`} style={{ width: `${Math.max(0, Math.min(100, health))}%` }} />
        </span>
      )}
    </>
  );
}
