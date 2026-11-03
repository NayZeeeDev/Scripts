/**
 * Small presentational pieces shared by the player-vehicles views:
 * Highlight, OnlineDot, StatusBadges, Condition, PlateList.
 */
import type { ReactNode } from 'react';
import { Badge, Icon, PlateTag, Tooltip, autoTone, cx } from '@/components/ui';
import type { IconName } from '@/components/ui';
import { t } from '@/lib/i18n';
import { percent } from '@/lib/format';
import type { AdminVehicleRow } from '@/lib/types';

/** Wraps every case-insensitive occurrence of `query` in a <mark>. */
export function Highlight({ text, query }: { text: string; query: string }) {
  const q = query.trim();
  if (!q) return <>{text}</>;
  const lower = text.toLowerCase();
  const needle = q.toLowerCase();
  const out: ReactNode[] = [];
  let i = 0;
  let k = 0;
  while (i < text.length) {
    const at = lower.indexOf(needle, i);
    if (at < 0) {
      out.push(text.slice(i));
      break;
    }
    if (at > i) out.push(text.slice(i, at));
    out.push(
      <mark key={k++} className="nz-aveh-mark">
        {text.slice(at, at + needle.length)}
      </mark>,
    );
    i = at + needle.length;
  }
  return <>{out}</>;
}

export function OnlineDot({ online, label = false }: { online: boolean; label?: boolean }) {
  return (
    <span className={cx('nz-aveh-online', online && 'is-on')} title={online ? t('Online') : t('Offline')}>
      <i />
      {label && <span>{online ? t('Online') : t('Offline')}</span>}
    </span>
  );
}

/** In garage (teal) / Not in garage (neutral) / Impounded (red) + Financed + Blocked. */
export function StatusBadges({ row }: { row: Pick<AdminVehicleRow, 'state' | 'financed' | 'blocked'> }) {
  return (
    <span className="nz-aveh-badges">
      {row.state === 'garaged' && (
        <Badge tone="teal" size="sm">
          {t('In garage')}
        </Badge>
      )}
      {row.state === 'out' && (
        <Badge tone="neutral" size="sm">
          {t('Not in garage')}
        </Badge>
      )}
      {row.state === 'impounded' && (
        <Badge tone="red" size="sm" icon="impound">
          {t('Impounded')}
        </Badge>
      )}
      {row.financed && (
        <Badge tone="blue" size="sm" icon="money">
          {t('Financed')}
        </Badge>
      )}
      {row.blocked && (
        <Badge tone="red" size="sm" icon="ban">
          {t('Blocked')}
        </Badge>
      )}
    </span>
  );
}

function CondItem({ icon, value, label }: { icon: IconName; value: number; label: string }) {
  const v = percent(value);
  const tone = autoTone(v);
  return (
    <Tooltip content={`${label} ${v}%`}>
      <span className={cx('nz-aveh-cond__item', `is-${tone}`)}>
        <Icon name={icon} size={12} strokeWidth={1.7} />
        <b>{v}%</b>
      </span>
    </Tooltip>
  );
}

/** Fuel / engine / body percentages (amber below 50, red below 25). */
export function Condition({ fuel, engine, body }: { fuel: number; engine: number; body: number }) {
  return (
    <span className="nz-aveh-cond">
      <CondItem icon="fuel" value={fuel} label={t('Fuel')} />
      <CondItem icon="engine" value={engine} label={t('Engine')} />
      <CondItem icon="shield" value={body} label={t('Body')} />
    </span>
  );
}

/** Plate tags, collapsing after `max` into "+n". */
export function PlateList({ plates, max = 3, query = '' }: { plates: string[]; max?: number; query?: string }) {
  if (!plates.length) return <span className="nz-aveh-muted">—</span>;
  const shown = plates.slice(0, max);
  const rest = plates.length - shown.length;
  return (
    <span className="nz-aveh-plates">
      {shown.map((p) => (
        <span key={p} className={cx('nz-aveh-plates__tag', query && p.includes(query.trim().toUpperCase()) && 'is-hit')}>
          <PlateTag plate={p} size="sm" />
        </span>
      ))}
      {rest > 0 && (
        <Tooltip content={plates.slice(max).join(', ')}>
          <span className="nz-aveh-plates__more">+{rest}</span>
        </Tooltip>
      )}
    </span>
  );
}
