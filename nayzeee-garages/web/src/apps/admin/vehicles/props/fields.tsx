/**
 * Editors for one vehicle-props field (used by PropsEditor): mod index (Select + raw index
 * kept in sync), toggles, GTA palette colours, RGB colours, enums, floats, neon and extras.
 */
import { useRef, useState } from 'react';
import type { CSSProperties, ReactNode } from 'react';
import { Button, Chip, ColorSwatches, IconButton, NumberInput, Segmented, Select, Toggle, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import { bool, num } from '../util';
import type { FieldDef, Props, Rgb } from './catalog';
import { GTA_COLOURS, colourByIndex, extrasMap, extrasNumeric, hexToRgb, isRgb, isSet, modOptionLabel, neonList, rgbToHex } from './catalog';

const CUSTOM = -9999;

const RGB_PRESETS = ['#ffffff', '#ff2a2a', '#ff8a00', '#ffd400', '#2bff6a', '#00d5ff', '#2a5bff', '#b026ff', '#ff3fb4', '#111111'];

type SetFn = (key: string, value: unknown) => void;

function Row({ label, set, children, stacked, aside }: { label: string; set: boolean; children: ReactNode; stacked?: boolean; aside?: ReactNode }) {
  return (
    <div className={cx('nz-aveh-prow', stacked && 'is-stacked')}>
      <div className="nz-aveh-prow__label">
        <span className={cx('nz-aveh-prow__dot', set && 'is-set')} aria-hidden="true" />
        <span className="nz-aveh-ellipsis">{label}</span>
        {aside}
      </div>
      <div className="nz-aveh-prow__ctl">{children}</div>
    </div>
  );
}

/** Select of named options + "Custom", with the raw index beside it. */
function IndexControl({
  value,
  options,
  onChange,
  min,
  max,
  swatch,
}: {
  value: number;
  options: { value: number; label: string }[];
  onChange: (n: number) => void;
  min: number;
  max: number;
  swatch?: string | null;
}) {
  const known = options.some((o) => o.value === value);
  const rawRef = useRef<HTMLDivElement>(null);
  const opts = [...options, { value: CUSTOM, label: known ? t('Custom…') : t('Custom ({n})', { n: value }) }];
  return (
    <>
      {swatch !== undefined && (
        <span className={cx('nz-aveh-swatch', !swatch && 'is-unknown')} style={swatch ? ({ '--sw': swatch } as CSSProperties) : undefined} />
      )}
      <Select
        size="sm"
        value={known ? value : CUSTOM}
        options={opts}
        searchable={opts.length > 12}
        className="nz-aveh-prow__select"
        onChange={(v) => {
          if (v === CUSTOM) {
            const next = known ? Math.min(max, Math.max(options.reduce((m, o) => Math.max(m, o.value), min) + 1, min)) : value;
            onChange(next);
            requestAnimationFrame(() => rawRef.current?.querySelector('input')?.focus());
          } else onChange(v);
        }}
      />
      <div ref={rawRef} className="nz-aveh-prow__raw">
        <NumberInput size="sm" value={value} min={min} max={max} onChange={(n) => onChange(Math.round(n))} />
      </div>
    </>
  );
}

function ModField({ f, props, set }: { f: Extract<FieldDef, { kind: 'mod' }>; props: Props; set: SetFn }) {
  const v = num(props[f.key]);
  const options = [{ value: -1, label: t('Stock') }, ...Array.from({ length: f.levels }, (_, i) => ({ value: i, label: modOptionLabel(f.prefix, i) }))];
  return (
    <Row label={f.label()} set={isSet(f, props)}>
      <IndexControl value={v} options={options} min={-1} max={255} onChange={(n) => set(f.key, n)} />
    </Row>
  );
}

function ColourIndex({ value, onChange }: { value: number; onChange: (n: number) => void }) {
  const options = GTA_COLOURS.map((c) => ({ value: c.index, label: t(c.name) }));
  return <IndexControl value={value} options={options} min={0} max={160} onChange={onChange} swatch={colourByIndex(value)?.hex ?? null} />;
}

function RgbControl({ value, fallback, onChange }: { value: unknown; fallback: Rgb; onChange: (c: Rgb) => void }) {
  const hex = rgbToHex(isRgb(value) ? value : fallback);
  return (
    <ColorSwatches
      value={hex}
      colors={RGB_PRESETS}
      onChange={(h) => {
        const c = hexToRgb(h);
        if (c) onChange(c);
      }}
      className="nz-aveh-prow__swatches"
    />
  );
}

function PaintField({ f, props, set }: { f: Extract<FieldDef, { kind: 'paint' }>; props: Props; set: SetFn }) {
  const v = props[f.key];
  const custom = isRgb(v);
  const [lastIndex, setLastIndex] = useState(() => (custom ? 0 : num(v, 0)));
  const [lastRgb, setLastRgb] = useState<Rgb>(() => (custom ? (v as Rgb) : hexToRgb(colourByIndex(num(v, 0))?.hex ?? '#ffffff') ?? [255, 255, 255]));
  return (
    <Row
      label={f.label()}
      set={isSet(f, props)}
      stacked
      aside={
        <Segmented
          size="sm"
          value={custom ? 'rgb' : 'palette'}
          options={[
            { value: 'palette', label: t('Palette') },
            { value: 'rgb', label: t('Custom RGB') },
          ]}
          onChange={(mode) => set(f.key, mode === 'rgb' ? lastRgb : lastIndex)}
          className="nz-aveh-prow__mode"
        />
      }
    >
      {custom ? (
        <RgbControl
          value={v}
          fallback={lastRgb}
          onChange={(c) => {
            setLastRgb(c);
            set(f.key, c);
          }}
        />
      ) : (
        <div className="nz-aveh-prow__line">
          <ColourIndex
            value={num(v, 0)}
            onChange={(n) => {
              setLastIndex(n);
              set(f.key, n);
            }}
          />
        </div>
      )}
    </Row>
  );
}

function NeonField({ props, set, f }: { f: FieldDef; props: Props; set: SetFn }) {
  const list = neonList(props.neonEnabled);
  const names = [t('Left'), t('Right'), t('Front'), t('Back')];
  const all = list.every(Boolean);
  return (
    <Row
      label={f.label()}
      set={isSet(f, props)}
      stacked
      aside={
        <Button size="sm" variant="ghost" onClick={() => set('neonEnabled', [!all, !all, !all, !all])}>
          {all ? t('All off') : t('All on')}
        </Button>
      }
    >
      <div className="nz-aveh-prow__chips">
        {names.map((n, i) => (
          <Chip
            key={n}
            active={list[i]}
            icon={list[i] ? 'check' : undefined}
            onClick={() => {
              const next = [...list];
              next[i] = !next[i];
              set('neonEnabled', next);
            }}
          >
            {n}
          </Chip>
        ))}
      </div>
    </Row>
  );
}

function ExtrasField({ props, set }: { props: Props; set: SetFn }) {
  const map = extrasMap(props.extras);
  const numeric = extrasNumeric(props.extras);
  const ids = Object.keys(map).sort((a, b) => Number(a) - Number(b));
  const [newId, setNewId] = useState(() => {
    for (let i = 1; i <= 20; i++) if (!(String(i) in map)) return i;
    return 0;
  });
  const write = (next: Record<string, boolean>) => {
    const out: Record<string, boolean | number> = {};
    for (const [k, on] of Object.entries(next)) out[k] = numeric ? (on ? 0 : 1) : on;
    set('extras', out);
  };
  return (
    <div className="nz-aveh-extras">
      {ids.length === 0 && <p className="nz-aveh-note">{t('No extras are saved for this vehicle. Add the extra IDs the model supports.')}</p>}
      {ids.map((id) => (
        <div key={id} className="nz-aveh-prow">
          <div className="nz-aveh-prow__label">
            <span className={cx('nz-aveh-prow__dot', map[id] && 'is-set')} aria-hidden="true" />
            <span>{t('Extra {n}', { n: id })}</span>
          </div>
          <div className="nz-aveh-prow__ctl">
            <Toggle checked={map[id]} onChange={(on) => write({ ...map, [id]: on })} />
            <IconButton
              icon="trash"
              size="sm"
              label={t('Remove')}
              onClick={() => {
                const next = { ...map };
                delete next[id];
                write(next);
              }}
            />
          </div>
        </div>
      ))}
      <div className="nz-aveh-extras__add">
        <span>{t('Add extra')}</span>
        <NumberInput size="sm" value={newId} min={0} max={20} onChange={(n) => setNewId(Math.round(n))} className="nz-aveh-prow__raw" />
        <Button
          size="sm"
          icon="plus"
          disabled={String(newId) in map}
          onClick={() => {
            write({ ...map, [String(newId)]: true });
            setNewId((n) => Math.min(20, n + 1));
          }}
        >
          {t('Add')}
        </Button>
      </div>
    </div>
  );
}

export function PropField({ f, props, set }: { f: FieldDef; props: Props; set: SetFn }) {
  switch (f.kind) {
    case 'mod':
      return <ModField f={f} props={props} set={set} />;
    case 'toggle':
      return (
        <Row label={f.label()} set={isSet(f, props)}>
          <Toggle checked={bool(props[f.key])} onChange={(b) => set(f.key, b)} />
        </Row>
      );
    case 'colour':
      return (
        <Row label={f.label()} set={isSet(f, props)}>
          <ColourIndex value={num(props[f.key], 0)} onChange={(n) => set(f.key, n)} />
        </Row>
      );
    case 'paint':
      return <PaintField f={f} props={props} set={set} />;
    case 'rgb':
      return (
        <Row label={f.label()} set={isSet(f, props)} stacked>
          <RgbControl value={props[f.key]} fallback={f.fallback} onChange={(c) => set(f.key, c)} />
        </Row>
      );
    case 'enum':
      return (
        <Row label={f.label()} set={isSet(f, props)}>
          <IndexControl value={num(props[f.key], f.fallback)} options={f.options()} min={-1} max={255} onChange={(n) => set(f.key, n)} />
        </Row>
      );
    case 'float': {
      const v = props[f.key];
      const has = typeof v === 'number';
      return (
        <Row label={f.label()} set={has}>
          <span className="nz-aveh-prow__hint">{has ? '' : t('Model default')}</span>
          <div className="nz-aveh-prow__raw is-wide">
            <NumberInput size="sm" value={has ? (v as number) : Number.NaN} min={f.min} max={f.max} step={f.step} onChange={(n) => set(f.key, n)} />
          </div>
          <IconButton icon="refresh" size="sm" label={t('Use model default')} disabled={!has} onClick={() => set(f.key, undefined)} />
        </Row>
      );
    }
    case 'neon':
      return <NeonField f={f} props={props} set={set} />;
    case 'extras':
      return <ExtrasField props={props} set={set} />;
  }
}
