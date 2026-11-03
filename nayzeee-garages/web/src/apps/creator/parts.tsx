/**
 * Interior creator: shared types, coordinate helpers and small building blocks used by
 * the tabs (coordinate readout card, numbered list row, section header).
 */
import type { ReactNode } from 'react';
import { t } from '@/lib/i18n';
import type { ApiResult, Cutscene, Interior, IplProfile, NuiCallbackName, NuiCallbacks, Vec3, Vec4 } from '@/lib/types';
import { cx } from '@/components/ui';

export type CreatorTab = 'details' | 'cutscene' | 'vehicles' | 'exit';

/** Lua actions that run while the editor is open (one at a time — Lua rejects overlaps). */
export type PendingKey =
  | 'pickEntry'
  | 'applyProfile'
  | 'teleport'
  | 'addCameraPoint'
  | 'preview'
  | 'placeSlot'
  | 'pickExit'
  | 'walk'
  | 'save'
  | 'cancel';

export type RunFn = <K extends NuiCallbackName>(
  key: PendingKey,
  name: K,
  data: NuiCallbacks[K]['req'],
) => Promise<ApiResult<NuiCallbacks[K]['res']> | null>;

export interface CreatorErrors {
  name?: string;
  entry?: string;
  slots?: string;
}

/** Props every tab receives from CreatorApp. */
export interface TabProps {
  draft: Interior;
  patch: (p: Partial<Interior>) => void;
  patchCutscene: (p: Partial<Cutscene>) => void;
  setSlots: (slots: Vec4[]) => void;
  run: RunFn;
  pending: PendingKey | null;
  errors: CreatorErrors;
  profiles: IplProfile[];
  gtaName: string | null;
  setGtaName: (name: string | null) => void;
}

export const isNum = (n: unknown): n is number => typeof n === 'number' && Number.isFinite(n);

/** A coordinate counts as set when it is finite and not the 0,0,0 placeholder. */
export function isSet(v: Vec3 | null | undefined): v is Vec3 {
  return !!v && isNum(v.x) && isNum(v.y) && isNum(v.z) && !(v.x === 0 && v.y === 0 && v.z === 0);
}

export const fixed = (n: number | null | undefined, dp = 2) => (isNum(n) ? n.toFixed(dp) : '—');

/** "-1102.4, -1520.7, 4.4" */
export function coordSummary(v: Vec3, dp = 1) {
  return `${fixed(v.x, dp)}, ${fixed(v.y, dp)}, ${fixed(v.z, dp)}`;
}

/** Heading in 0..359 degrees. */
export function headingLabel(w: number | null | undefined) {
  if (!isNum(w)) return '—';
  const h = ((Math.round(w) % 360) + 360) % 360;
  return `${h}°`;
}

/** X / Y / Z / heading mono readout. */
export function CoordCard({ value, invalid, placeholder }: { value: Vec4 | null; invalid?: boolean; placeholder?: ReactNode }) {
  const set = isSet(value);
  const cells: { k: string; v: string }[] = [
    { k: t('X'), v: set ? fixed(value!.x) : '—' },
    { k: t('Y'), v: set ? fixed(value!.y) : '—' },
    { k: t('Z'), v: set ? fixed(value!.z) : '—' },
    { k: t('Heading'), v: set ? headingLabel(value!.w) : '—' },
  ];
  return (
    <div className={cx('nz-creator__coords', !set && 'is-empty', invalid && 'is-invalid')}>
      {cells.map((c) => (
        <div key={c.k} className="nz-creator__coord">
          <span>{c.k}</span>
          <b>{c.v}</b>
        </div>
      ))}
      {!set && placeholder && <div className="nz-creator__coords-note">{placeholder}</div>}
    </div>
  );
}

/** Uppercase section header with an optional count, info and actions. */
export function SectionHead({
  title,
  count,
  info,
  actions,
}: {
  title: ReactNode;
  count?: number;
  info?: ReactNode;
  actions?: ReactNode;
}) {
  return (
    <div className="nz-creator__shead">
      <h4>{title}</h4>
      {count !== undefined && <span className="nz-creator__count">{count}</span>}
      {info}
      {actions && <div className="nz-creator__shead-actions">{actions}</div>}
    </div>
  );
}

/** Numbered list row: [#n] main / sub ... actions */
export function PointRow({
  index,
  main,
  sub,
  actions,
  className,
}: {
  index: number;
  main: ReactNode;
  sub?: ReactNode;
  actions?: ReactNode;
  className?: string;
}) {
  return (
    <li className={cx('nz-creator__row', className)}>
      <span className="nz-creator__num">{index}</span>
      <div className="nz-creator__row-text">
        <b className="nz-mono">{main}</b>
        {sub && <span>{sub}</span>}
      </div>
      {actions && <div className="nz-creator__row-actions">{actions}</div>}
    </li>
  );
}
