/**
 * Small presentational pieces shared by the player-vehicles views:
 * Highlight, OnlineDot, StatusBadges, MiniCondition, moveFocus.
 */
import type { KeyboardEvent, ReactNode } from 'react';
import { Badge, Icon, Tooltip, autoTone, cx } from '@/components/ui';
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

/** Fuel / engine / body as three mini bars with % (roster rows). */
export function MiniCondition({ fuel, engine, body }: { fuel: number; engine: number; body: number }) {
  const items: { icon: IconName; label: string; value: number }[] = [
    { icon: 'fuel', label: t('Fuel'), value: fuel },
    { icon: 'engine', label: t('Engine'), value: engine },
    { icon: 'shield', label: t('Body'), value: body },
  ];
  return (
    <span className="nz-aveh-mini">
      {items.map((it) => {
        const v = percent(it.value);
        return (
          <Tooltip key={it.label} content={`${it.label} ${v}%`}>
            <span className={cx('nz-aveh-mini__item', `is-${autoTone(v)}`)}>
              <Icon name={it.icon} size={11} strokeWidth={1.8} />
              <i>
                <i style={{ width: `${v}%` }} />
              </i>
            </span>
          </Tooltip>
        );
      })}
    </span>
  );
}

/**
 * Arrow-key focus movement between `selector` items inside `root` (lists and grids).
 * Returns true when it handled the key.
 */
export function moveFocus(e: KeyboardEvent<HTMLElement>, root: HTMLElement | null, selector: string): boolean {
  if (!root || !['ArrowDown', 'ArrowUp', 'ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(e.key)) return false;
  const items = Array.from(root.querySelectorAll<HTMLElement>(selector));
  if (!items.length) return false;
  const i = items.indexOf(document.activeElement as HTMLElement);
  // Columns of a CSS grid (1 for lists).
  const parent = items[0].parentElement;
  const cols = parent ? Math.max(1, getComputedStyle(parent).gridTemplateColumns.split(' ').filter(Boolean).length || 1) : 1;
  let next = i;
  if (e.key === 'Home') next = 0;
  else if (e.key === 'End') next = items.length - 1;
  else if (i < 0) next = 0;
  else if (e.key === 'ArrowDown') next = Math.min(items.length - 1, i + cols);
  else if (e.key === 'ArrowUp') next = i - cols < 0 ? -1 : i - cols;
  else if (e.key === 'ArrowRight') next = Math.min(items.length - 1, i + 1);
  else if (e.key === 'ArrowLeft') next = Math.max(0, i - 1);
  e.preventDefault();
  if (next < 0) return false;
  items[next].focus();
  items[next].scrollIntoView({ block: 'nearest' });
  return true;
}
