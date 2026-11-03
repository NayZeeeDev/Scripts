/**
 * Data table (v5 style: sticky header, hairline rows, hover, chevron when rows are clickable,
 * skeleton while loading, EmptyState when empty) and Pagination.
 */
import { isValidElement, useLayoutEffect, useRef } from 'react';
import type { KeyboardEvent, ReactNode } from 'react';
import clsx from 'clsx';
import { t } from '@/lib/i18n';
import { Icon } from '../icons';
import { EmptyState, Skeleton } from './Display';
import { IconButton } from './Button';

export interface TableColumn<Row> {
  key: string;
  header: ReactNode;
  width?: number | string;
  align?: 'left' | 'right' | 'center';
  render?: (row: Row) => ReactNode;
  /** Extra class on every cell of this column. */
  className?: string;
}

export interface TableProps<Row> {
  columns: TableColumn<Row>[];
  rows: Row[];
  rowKey: (row: Row) => string | number;
  onRowClick?: (row: Row) => void;
  /** Highlight a row (e.g. the one opened in a side panel). */
  activeKey?: string | number | null;
  /** String → default EmptyState with that title; element → rendered as-is. */
  empty?: ReactNode;
  loading?: boolean;
  dense?: boolean;
  /** Number of skeleton rows while loading. */
  skeletonRows?: number;
  className?: string;
}

const SKEL = ['62%', '44%', '78%', '52%', '36%', '68%'];

export function Table<Row>({
  columns,
  rows,
  rowKey,
  onRowClick,
  activeKey = null,
  empty,
  loading = false,
  dense = false,
  skeletonRows = 6,
  className,
}: TableProps<Row>) {
  const clickable = !!onRowClick;
  const colCount = columns.length + (clickable ? 1 : 0);
  const wrapRef = useRef<HTMLDivElement>(null);

  // Sticky headers stick below the scroll container's padding; offset by it so rows never
  // show through the padding strip above a stuck header.
  useLayoutEffect(() => {
    const wrap = wrapRef.current;
    let el = wrap?.parentElement ?? null;
    while (el && el !== document.body) {
      const cs = getComputedStyle(el);
      if (/(auto|scroll|overlay)/.test(cs.overflowY)) {
        const pt = parseFloat(cs.paddingTop) || 0;
        wrap?.style.setProperty('--nz-th-top', `${-pt}px`);
        return;
      }
      el = el.parentElement;
    }
  }, []);

  const emptyNode =
    empty === undefined || empty === null || typeof empty === 'string' || typeof empty === 'number' ? (
      <EmptyState icon="list" title={empty ? String(empty) : t('Nothing to show yet')} compact />
    ) : isValidElement(empty) ? (
      empty
    ) : (
      <EmptyState icon="list" title={empty} compact />
    );

  const onKey = (e: KeyboardEvent<HTMLTableRowElement>, row: Row) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      onRowClick?.(row);
    }
  };

  return (
    <div ref={wrapRef} className={clsx('nz-table-wrap', className)}>
      <table className={clsx('nz-table', dense && 'nz-table--dense', clickable && 'nz-table--clickable')}>
        <colgroup>
          {columns.map((c) => (
            <col key={c.key} style={{ width: typeof c.width === 'number' ? `${c.width}px` : c.width }} />
          ))}
          {clickable && <col style={{ width: 34 }} />}
        </colgroup>
        <thead>
          <tr>
            {columns.map((c) => (
              <th key={c.key} className={clsx(c.align && `is-${c.align}`, c.className)} scope="col">
                {c.header}
              </th>
            ))}
            {clickable && <th aria-hidden="true" />}
          </tr>
        </thead>
        <tbody>
          {loading &&
            Array.from({ length: skeletonRows }, (_, i) => (
              <tr key={`sk-${i}`} className="nz-table__skel">
                {columns.map((c, j) => (
                  <td key={c.key} className={clsx(c.align && `is-${c.align}`)}>
                    <Skeleton width={j === 0 ? SKEL[(i + 2) % SKEL.length] : SKEL[(i + j) % SKEL.length]} height={j === 0 ? 10 : 8} />
                  </td>
                ))}
                {clickable && <td />}
              </tr>
            ))}
          {!loading && rows.length === 0 && (
            <tr className="nz-table__empty">
              <td colSpan={colCount}>{emptyNode}</td>
            </tr>
          )}
          {!loading &&
            rows.map((row) => {
              const k = rowKey(row);
              return (
                <tr
                  key={k}
                  className={clsx(activeKey !== null && activeKey === k && 'is-active')}
                  onClick={clickable ? () => onRowClick?.(row) : undefined}
                  onKeyDown={clickable ? (e) => onKey(e, row) : undefined}
                  tabIndex={clickable ? 0 : undefined}
                >
                  {columns.map((c) => (
                    <td key={c.key} className={clsx(c.align && `is-${c.align}`, c.className)}>
                      {c.render ? c.render(row) : ((row as unknown as Record<string, unknown>)[c.key] as ReactNode)}
                    </td>
                  ))}
                  {clickable && (
                    <td className="nz-table__chev">
                      <Icon name="chevronRight" size={14} strokeWidth={1.8} />
                    </td>
                  )}
                </tr>
              );
            })}
        </tbody>
      </table>
    </div>
  );
}

/* ── Pagination ───────────────────────────────────────────────────────── */

export interface PaginationProps {
  /** 1-based. */
  page: number;
  pageCount: number;
  onChange: (page: number) => void;
  total?: number;
  pageSize?: number;
  className?: string;
}

function pageList(page: number, count: number): (number | '…')[] {
  if (count <= 7) return Array.from({ length: count }, (_, i) => i + 1);
  const out: (number | '…')[] = [1];
  const start = Math.max(2, page - 1);
  const end = Math.min(count - 1, page + 1);
  if (start > 2) out.push('…');
  for (let i = start; i <= end; i++) out.push(i);
  if (end < count - 1) out.push('…');
  out.push(count);
  return out;
}

export function Pagination({ page, pageCount, onChange, total, pageSize, className }: PaginationProps) {
  const count = Math.max(1, pageCount || 1);
  const cur = Math.max(1, Math.min(count, page || 1));
  let summary: ReactNode;
  if (total !== undefined && pageSize) {
    const from = total === 0 ? 0 : (cur - 1) * pageSize + 1;
    const to = Math.min(total, cur * pageSize);
    summary = (
      <>
        <b>
          {from}–{to}
        </b>{' '}
        {t('of {total} items', { total: total.toLocaleString('en-US') })}
      </>
    );
  } else {
    summary = t('Page {page} of {pages}', { page: cur, pages: count });
  }
  return (
    <div className={clsx('nz-pager', className)}>
      <span className="nz-pager__summary">{summary}</span>
      <div className="nz-pager__nav">
        <IconButton icon="chevronLeft" label={t('Previous page')} size="sm" variant="line" disabled={cur <= 1} onClick={() => onChange(cur - 1)} />
        {pageList(cur, count).map((p, i) =>
          p === '…' ? (
            <span key={`gap-${i}`} className="nz-pager__gap">
              …
            </span>
          ) : (
            <button
              key={p}
              type="button"
              className={clsx('nz-pager__page', p === cur && 'is-on')}
              aria-current={p === cur ? 'page' : undefined}
              onClick={() => p !== cur && onChange(p)}
            >
              {p}
            </button>
          ),
        )}
        <IconButton icon="chevronRight" label={t('Next page')} size="sm" variant="line" disabled={cur >= count} onClick={() => onChange(cur + 1)} />
      </div>
    </div>
  );
}
