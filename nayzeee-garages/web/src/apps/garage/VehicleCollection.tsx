/**
 * Grid / list of vehicles with an inline detail panel.
 * Grid: a full-width panel is inserted after the clicked card's row (with a pointer to it).
 * List: the panel expands under the row. Shared by the garage and impound apps.
 */
import { Fragment, useEffect, useRef } from 'react';
import type { CSSProperties, KeyboardEvent, ReactNode } from 'react';
import { cx } from '@/components/ui';
import type { ViewMode } from './model';

export const GRID_COLUMNS = 3;

export interface VehicleCollectionProps<T> {
  items: T[];
  view: ViewMode;
  getKey: (item: T) => string;
  expandedKey?: string | null;
  onToggle?: (key: string) => void;
  /** Card content (grid). */
  renderCard: (item: T, open: boolean) => ReactNode;
  /** Row content (list). */
  renderRow: (item: T, open: boolean) => ReactNode;
  /** Expanded panel; omit for non-expandable collections (spawner). */
  renderDetail?: (item: T) => ReactNode;
  /** Extra class per item (state tints). */
  itemClass?: (item: T) => string | undefined;
  className?: string;
}

/** Enter / Space activates a role="button" element (ignores keys from nested controls). */
export function activateOnKey(e: KeyboardEvent<HTMLElement>, fn: () => void) {
  if (e.target !== e.currentTarget) return;
  if (e.key === 'Enter' || e.key === ' ') {
    e.preventDefault();
    fn();
  }
}

export function VehicleCollection<T>({
  items,
  view,
  getKey,
  expandedKey = null,
  onToggle,
  renderCard,
  renderRow,
  renderDetail,
  itemClass,
  className,
}: VehicleCollectionProps<T>) {
  const detailRef = useRef<HTMLDivElement>(null);
  const expandable = !!renderDetail && !!onToggle;
  const openIndex = expandedKey ? items.findIndex((it) => getKey(it) === expandedKey) : -1;
  const openItem = openIndex >= 0 ? items[openIndex] : null;

  // Bring a freshly opened panel into view — only as far as needed, and never so far that
  // the card / row it belongs to scrolls out of sight above it.
  useEffect(() => {
    if (!expandedKey) return;
    const raf = requestAnimationFrame(() => {
      const el = detailRef.current;
      const scroller = el?.closest<HTMLElement>('.nz-garage__scroll');
      if (!el || !scroller) return;
      const er = el.getBoundingClientRect();
      const sr = scroller.getBoundingClientRect();
      const keepAbove = view === 'grid' ? 96 : 70;
      let shift = 0;
      if (er.bottom > sr.bottom) shift = Math.min(er.bottom - sr.bottom + 14, er.top - sr.top - keepAbove);
      else if (er.top - keepAbove < sr.top) shift = er.top - keepAbove - sr.top;
      if (Math.abs(shift) > 1) scroller.scrollBy({ top: shift, behavior: 'smooth' });
    });
    return () => cancelAnimationFrame(raf);
    // openIndex: follow the open vehicle when a rename / favourite re-sorts the list.
  }, [expandedKey, view, openIndex]);

  const interactive = (key: string) =>
    expandable
      ? {
          role: 'button' as const,
          tabIndex: 0,
          'aria-expanded': key === expandedKey,
          onClick: () => onToggle!(key),
          onKeyDown: (e: KeyboardEvent<HTMLElement>) => activateOnKey(e, () => onToggle!(key)),
        }
      : {};

  if (view === 'grid') {
    const col = openIndex >= 0 ? openIndex % GRID_COLUMNS : 0;
    const rowEnd = openIndex >= 0 ? Math.min(items.length - 1, openIndex - col + GRID_COLUMNS - 1) : -1;
    return (
      <div className={cx('nz-garage__grid', className)}>
        {items.map((it, i) => {
          const key = getKey(it);
          const open = key === expandedKey;
          return (
            <Fragment key={key}>
              <div
                className={cx('nz-garage__card', expandable && 'is-clickable', open && 'is-open', itemClass?.(it))}
                {...interactive(key)}
              >
                {renderCard(it, open)}
              </div>
              {openItem && renderDetail && i === rowEnd && (
                <div
                  ref={detailRef}
                  key={`detail-${getKey(openItem)}`}
                  className="nz-garage__detail nz-garage__detail--grid"
                  style={{ '--ptr-col': col } as CSSProperties}
                >
                  {renderDetail(openItem)}
                </div>
              )}
            </Fragment>
          );
        })}
      </div>
    );
  }

  return (
    <div className={cx('nz-garage__list', className)}>
      {items.map((it) => {
        const key = getKey(it);
        const open = key === expandedKey;
        return (
          <div key={key} className={cx('nz-garage__item', open && 'is-open', itemClass?.(it))}>
            <div className={cx('nz-garage__row', expandable && 'is-clickable')} {...interactive(key)}>
              {renderRow(it, open)}
            </div>
            {open && renderDetail && (
              <div ref={detailRef} className="nz-garage__detail nz-garage__detail--list">
                {renderDetail(it)}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}
