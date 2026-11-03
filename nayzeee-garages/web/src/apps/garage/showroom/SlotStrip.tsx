/**
 * Capacity readout for the window header: one small rounded cell per space (teal = used,
 * line = free, red when full). Above 24 spaces (12 in a busy header) it becomes a compact bar + "9 / 40";
 * unlimited garages show the number stored with an infinity mark.
 */
import { Icon, Tooltip, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { CapacityInfo } from '@/lib/types';

const MAX_CELLS = 24;
/** Busy headers (private garage controls next to it) switch to the bar sooner. */
const MAX_CELLS_COMPACT = 12;

export function SlotStrip({ capacity, stored, compact = false }: { capacity: CapacityInfo | null; stored: number; compact?: boolean }) {
  const label = capacity?.appliesTo === 'total' ? t('Spaces') : t('Your spaces');
  if (!capacity || capacity.mode !== 'limited' || capacity.total <= 0) {
    return (
      <span className="nz-garage__slots is-unlimited">
        <Icon name="parking" size={13} strokeWidth={1.8} />
        <span className="nz-garage__slots-label">{label}</span>
        <b>
          {capacity ? capacity.used : stored}
          <small> / ∞</small>
        </b>
      </span>
    );
  }
  const { used, total } = capacity;
  const full = used >= total;
  const near = !full && used / total >= 0.8;
  const free = Math.max(0, total - used);
  const tip = full
    ? t('Full: {used} of {total} spaces used', { used, total })
    : t('{free} of {total} spaces free', { free, total });
  return (
    <Tooltip content={tip} side="bottom">
      <span className={cx('nz-garage__slots', full && 'is-full', near && 'is-near')} aria-label={tip}>
        <Icon name="parking" size={13} strokeWidth={1.8} />
        <span className="nz-garage__slots-label">{label}</span>
        {total <= (compact ? MAX_CELLS_COMPACT : MAX_CELLS) ? (
          <span className="nz-garage__slots-cells" aria-hidden="true">
            {Array.from({ length: total }, (_, i) => (
              <i key={i} className={i < used ? 'is-used' : undefined} />
            ))}
          </span>
        ) : (
          <span className="nz-garage__slots-bar" aria-hidden="true">
            <span style={{ width: `${Math.min(100, (used / total) * 100)}%` }} />
          </span>
        )}
        <b>
          {used}
          <small> / {total}</small>
        </b>
      </span>
    </Tooltip>
  );
}
