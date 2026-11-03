/**
 * Settings controls that need more than a plain kit input: accent colour with a live preview,
 * vehicle image URL template with a sample image, currency symbol with a sample amount.
 */
import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import { Badge, Button, Chip, ColorSwatches, Icon, Input, Toggle, VehicleSilhouette, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import { hoursLabel, money } from '@/lib/format';
import type { AdminOpenData, AdminPage, ImpoundLocation } from '@/lib/types';
import { ACCENT_PRESETS, DEFAULT_ACCENT, accentVars, contrastOnBase, isHex } from './accent';

/* ── accent ──────────────────────────────────────────────────────────── */

export function AccentField({ value, onChange }: { value: string; onChange: (hex: string) => void }) {
  const valid = isHex(value);
  const low = valid && contrastOnBase(value) < 3;
  return (
    <div className="nz-aset-accent">
      <ColorSwatches value={value} onChange={onChange} colors={ACCENT_PRESETS} />
      {low && (
        <p className="nz-aset-inline-warn">
          <Icon name="warning" size={13} strokeWidth={1.8} />
          {t('This colour is hard to read on the dark background.')}
        </p>
      )}
    </div>
  );
}

/** Real kit components re-themed with the unsaved accent. */
export function AccentPreview({ value }: { value: string }) {
  const [on, setOn] = useState(true);
  const hex = isHex(value) ? value : DEFAULT_ACCENT;
  return (
    <div className="nz-aset-preview" style={accentVars(hex)} aria-label={t('Accent preview')}>
      <div className="nz-aset-preview__bar">
        <span className="nz-aset-preview__mark" />
        <b>{t('Garage')}</b>
        <span className="nz-aset-preview__hex">{hex.toUpperCase()}</span>
      </div>
      <div className="nz-aset-preview__body">
        <div className="nz-aset-preview__row">
          <Button size="sm" variant="teal" icon="car">
            {t('Drive')}
          </Button>
          <Chip active count={4}>
            {t('Favourites')}
          </Chip>
          <Badge tone="teal" size="sm" dot>
            {t('In garage')}
          </Badge>
        </div>
        <div className="nz-aset-preview__row">
          <Toggle checked={on} onChange={setOn} size="sm" />
          <span className="nz-aset-preview__meter">
            <i style={{ width: '72%' }} />
          </span>
          <span className="nz-aset-preview__pct">72%</span>
        </div>
      </div>
    </div>
  );
}

/* ── image url ───────────────────────────────────────────────────────── */

export const DEFAULT_IMAGE_URL = 'https://docs.fivem.net/vehicles/{model}.webp';
const SAMPLE_MODEL = 'adder';

type ImgState = 'loading' | 'ok' | 'error';

export function imageUrlError(url: string, required: boolean): string | null {
  const v = url.trim();
  if (!v) return required ? t('Enter an image URL or turn vehicle images off') : null;
  if (!v.includes('{model}')) return t('The URL must contain {model}', { model: '{model}' });
  if (!/^(https?|nui):\/\//i.test(v) && !v.startsWith('./')) return t('Use an http(s):// or nui:// address');
  return null;
}

export function ImageUrlField({
  value,
  onChange,
  disabled,
  onEnter,
}: {
  value: string;
  onChange: (v: string) => void;
  disabled: boolean;
  onEnter: () => void;
}) {
  const error = disabled ? null : imageUrlError(value, true);
  const sample = value.trim().replace('{model}', SAMPLE_MODEL);
  const [state, setState] = useState<ImgState>('loading');

  useEffect(() => {
    if (error || disabled) return;
    setState('loading');
    const timer = window.setTimeout(() => setState((s) => (s === 'loading' ? 'error' : s)), 6000);
    return () => window.clearTimeout(timer);
  }, [sample, error, disabled]);

  let status: ReactNode;
  if (disabled) status = <span>{t('Vehicle images are turned off — silhouettes are shown instead.')}</span>;
  else if (error) status = <span className="is-error">{error}</span>;
  else if (state === 'ok') status = <span className="is-ok">{t('Sample image loaded')}</span>;
  else if (state === 'error')
    status = <span className="is-warn">{t('Sample image could not be loaded — players see a local image or a silhouette instead.')}</span>;
  else status = <span>{t('Loading the sample image…')}</span>;

  return (
    <div className={cx('nz-aset-img', disabled && 'is-disabled')}>
      <div className="nz-aset-img__row">
        <Input
          value={value}
          onChange={onChange}
          mono
          icon="link"
          maxLength={300}
          disabled={disabled}
          placeholder={DEFAULT_IMAGE_URL}
          onEnter={onEnter}
          className="nz-aset-img__input"
        />
        <Button size="sm" variant="ghost" icon="refresh" disabled={disabled || value === DEFAULT_IMAGE_URL} onClick={() => onChange(DEFAULT_IMAGE_URL)}>
          {t('Default')}
        </Button>
      </div>
      <div className="nz-aset-img__sample">
        <div className={cx('nz-aset-img__thumb', state === 'ok' && !disabled && !error && 'is-loaded')}>
          {!disabled && !error && (
            <img
              key={sample}
              src={sample}
              alt=""
              onLoad={() => setState('ok')}
              onError={() => setState('error')}
              style={state === 'ok' ? undefined : { display: 'none' }}
            />
          )}
          {(disabled || error || state !== 'ok') && <VehicleSilhouette kind="car" className="nz-aset-img__sil" />}
        </div>
        <div className="nz-aset-img__meta">
          <span className="nz-aset-img__label">
            {t('Sample')} · <b>{SAMPLE_MODEL}</b>
          </span>
          <code title={sample}>{disabled || error ? '—' : sample}</code>
          <div className="nz-aset-img__status">{status}</div>
        </div>
      </div>
    </div>
  );
}

/* ── currency ────────────────────────────────────────────────────────── */

export function CurrencyField({ value, onChange, onEnter }: { value: string; onChange: (v: string) => void; onEnter: () => void }) {
  const symbol = value || '?';
  return (
    <div className="nz-aset-currency">
      <Input value={value} onChange={(v) => onChange(v.slice(0, 8))} maxLength={8} placeholder="$" onEnter={onEnter} className="nz-aset-currency__input" />
      <span className="nz-aset-currency__sample">
        {symbol}
        {(12500).toLocaleString('en-US')}
      </span>
    </div>
  );
}

/* ── impound lots overview ───────────────────────────────────────────── */

/** Read-only list of impound lots with their own fee / time (managed on the Impounds page). */
export function ImpoundLots({ c }: { c: { data: AdminOpenData; currency: string; go: (page: AdminPage) => void } }) {
  const lots = c.data.locations.filter((l): l is ImpoundLocation => l.kind === 'impound');
  if (!lots.length) {
    return (
      <div className="nz-aset-lots__empty">
        <span>{t('No impound lots yet — impounding needs at least one.')}</span>
        <Button size="sm" icon="plus" onClick={() => c.go('impounds')}>
          {t('Create')}
        </Button>
      </div>
    );
  }
  return (
    <ul className="nz-aset-lots">
      {lots.map((l) => (
        <li key={String(l.id)} className={cx(!l.enabled && 'is-off')}>
          <Icon name="impound" size={13} strokeWidth={1.6} />
          <span className="nz-aset-lots__name" title={l.name}>
            {l.name}
          </span>
          {!l.enabled && (
            <Badge size="sm" tone="neutral">
              {t('Disabled')}
            </Badge>
          )}
          <span className="nz-aset-lots__val">{money(l.defaultFee)}</span>
          <span className="nz-aset-lots__val is-dim">{l.defaultHours ? hoursLabel(l.defaultHours) : t('Instant')}</span>
        </li>
      ))}
      <li className="nz-aset-lots__foot">
        <Button size="sm" variant="ghost" iconRight="arrowRight" onClick={() => c.go('impounds')}>
          {t('Manage impounds')}
        </Button>
      </li>
    </ul>
  );
}
