/**
 * KpiStrip — the row of headline numbers above the Map command (4 tiles, v5 stat style).
 *   <KpiStrip items: Kpi[] />
 * A tile: icon tile, label, big tabular value (+ unit) with a short second line next to it, and
 * an optional thin ratio bar along its bottom edge. value null renders a skeleton.
 */
import type { CSSProperties } from 'react';
import { Icon, Skeleton, cx } from '@/components/ui';
import type { Kpi } from './commandTypes';

export function KpiStrip({ items }: { items: Kpi[] }) {
  return (
    <div className="nz-admin-cmd__kpis">
      {items.map((k) => (
        <div key={k.key} className={cx('nz-admin-cmd__kpi', `is-${k.tone ?? 'teal'}`)}>
          <span className="nz-admin-cmd__kpi-icon">
            <Icon name={k.icon} size={16} strokeWidth={1.6} />
          </span>
          <div className="nz-admin-cmd__kpi-text">
            <span className="nz-admin-cmd__kpi-label">{k.label}</span>
            <span className="nz-admin-cmd__kpi-row">
              {k.value === null ? (
                <Skeleton width={58} height={20} radius={4} className="nz-admin-cmd__kpi-skel" />
              ) : (
                <b className="nz-admin-cmd__kpi-value">
                  {k.value}
                  {k.unit && <small>{k.unit}</small>}
                </b>
              )}
              {k.sub && (
                <span className="nz-admin-cmd__kpi-sub" title={k.sub}>
                  {k.sub}
                </span>
              )}
            </span>
          </div>
          {k.ratio !== undefined && k.ratio !== null && (
            <i
              className="nz-admin-cmd__kpi-bar"
              style={{ '--ratio': Math.max(0, Math.min(1, k.ratio)) } as CSSProperties}
              aria-hidden="true"
            />
          )}
        </div>
      ))}
    </div>
  );
}
