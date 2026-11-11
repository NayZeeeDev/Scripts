/**
 * Controls of the admin key settings, one per schema type:
 *   bool → Toggle · number → NumberInput (+ unit from the label, a readable duration) ·
 *   enum → Segmented (≤ 3 short options) or Select (the default fob design shows its render) ·
 *   color → ColorControl (swatches, hex, opacity when the server takes it, live preview) ·
 *   classes → MultiSelect of the GTA classes · models / strings → TagList (chips + input).
 * Plus the marker preview (ground markers) and the reaction share bar (NPC reactions).
 */
import { useEffect, useRef, useState } from 'react';
import type { KeyboardEvent } from 'react';
import { ColorSwatches, Icon, MultiSelect, NumberInput, Segmented, Select, Slider, Toggle, cx } from '@/components/ui';
import { FobArt } from '@/components/fob/FobArt';
import { useEscape } from '@/lib/escape';
import { t } from '@/lib/i18n';
import type { KeySetting, KeySettingValue } from '@/lib/types';
import { CLASS_NAMES, MARKER_ALPHA, classLabel, duration, formatColor, optionLabel, parseColor, rgba, splitUnit } from './model';

export interface ControlProps {
  setting: KeySetting;
  value: KeySettingValue;
  onChange: (v: KeySettingValue) => void;
  invalid?: boolean;
}

export function SettingControl(p: ControlProps) {
  switch (p.setting.type) {
    case 'bool':
      return <Toggle checked={p.value === true} onChange={(b) => p.onChange(b)} />;
    case 'number':
      return <NumberControl {...p} />;
    case 'enum':
      return <EnumControl {...p} />;
    case 'color':
      return <ColorControl {...p} />;
    case 'classes':
      return (
        <MultiSelect<number>
          value={Array.isArray(p.value) ? (p.value as number[]) : []}
          onChange={(v) => p.onChange([...v].sort((a, b) => a - b))}
          options={CLASS_NAMES.map((_, i) => ({ value: i, label: classLabel(i), hint: String(i) }))}
          placeholder={t('No classes')}
          searchable
          maxTags={4}
          className="nz-kadm-ctl--wide"
        />
      );
    case 'models':
    case 'strings':
      return (
        <TagList
          value={Array.isArray(p.value) ? (p.value as string[]) : []}
          onChange={(v) => p.onChange(v)}
          lower={p.setting.type === 'models'}
          max={p.setting.type === 'models' ? 200 : 50}
          placeholder={p.setting.type === 'models' ? t('Add a spawn name, e.g. police3') : t('Add a name, e.g. mechanic')}
          invalid={p.invalid}
        />
      );
    default:
      return <span className="nz-kadm-none">{String(p.value)}</span>;
  }
}

/* ── number ──────────────────────────────────────────────────────────── */

const SECONDS: Record<string, number> = { s: 1, ms: 0.001, h: 3600, min: 60 };

function NumberControl({ setting, value, onChange }: ControlProps) {
  const { unit } = splitUnit(setting.label);
  const n = typeof value === 'number' ? value : Number(value) || 0;
  const per = unit ? SECONDS[unit] : undefined;
  const secs = per !== undefined ? n * per : null;
  // a readable duration only where it says more than the number (120 s → 2m, 90 min → 1h 30m, 48 h → 2d 0h)
  const worth = secs !== null && (unit === 'h' ? n >= 24 : unit === 'min' ? n >= 60 : unit === 's' ? n >= 120 : false);
  return (
    <div className="nz-kadm-num">
      {worth && secs !== null && <span className="nz-kadm-num__hint">≈ {duration(secs)}</span>}
      {secs === 0 && setting.min === 0 && <span className="nz-kadm-num__hint">{t('off / never')}</span>}
      <NumberInput
        value={n}
        onChange={(v) => onChange(setting.integer ? Math.round(v) : v)}
        min={setting.min}
        max={setting.max}
        step={setting.step ?? (setting.integer ? 1 : 0.1)}
        suffix={unit}
        size="sm"
        className="nz-kadm-num__input"
      />
    </div>
  );
}

/* ── enum ────────────────────────────────────────────────────────────── */

function EnumControl({ setting, value, onChange }: ControlProps) {
  const options = (setting.options ?? []).map((o) => ({ value: o, ...optionLabel(setting.id, o) }));
  const v = typeof value === 'string' ? value : null;
  if (setting.id === 'keys.defaultFob') {
    return (
      <div className="nz-kadm-fobpick">
        <span className="nz-kadm-fobpick__art">
          <FobArt design={v ?? undefined} kind="fob" size={40} />
        </span>
        <Select<string> value={v} onChange={onChange} options={options} size="sm" className="nz-kadm-ctl--select" />
      </div>
    );
  }
  const short = options.length > 0 && options.length <= 3 && options.every((o) => o.label.length <= 11);
  if (short) {
    return <Segmented<string> value={v ?? ''} onChange={onChange} options={options.map((o) => ({ value: o.value, label: o.label }))} size="sm" />;
  }
  return <Select<string> value={v} onChange={onChange} options={options} size="sm" className="nz-kadm-ctl--select" />;
}

/* ── colour + opacity ────────────────────────────────────────────────── */

const MARKER_SWATCHES = ['#2dd4bf', '#08afa2', '#38bdf8', '#a78bfa', '#f472b6', '#f87171', '#fb923c', '#facc15', '#a3e635', '#ffffff'];

function ColorControl({ setting, value, onChange }: ControlProps) {
  const [open, setOpen] = useState(false);
  const wrap = useRef<HTMLDivElement>(null);
  const { hex, alpha } = parseColor(value);
  const opacity = alpha ?? MARKER_ALPHA;
  useEscape(() => setOpen(false), open);

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => {
      if (wrap.current && !wrap.current.contains(e.target as Node)) setOpen(false);
    };
    window.addEventListener('mousedown', onDown);
    return () => window.removeEventListener('mousedown', onDown);
  }, [open]);

  const set = (nextHex: string, nextAlpha: number | null) => onChange(formatColor(nextHex, setting.alpha ? nextAlpha : null));

  return (
    <div className="nz-kadm-color" ref={wrap}>
      <button type="button" className={cx('nz-kadm-color__btn', open && 'is-open')} onClick={() => setOpen((o) => !o)} aria-expanded={open}>
        <span className="nz-kadm-color__chip">
          <span style={{ background: rgba(hex, opacity / 100) }} />
        </span>
        <span className="nz-kadm-mono">{hex.toUpperCase()}</span>
        <em>{opacity}%</em>
        <Icon name={open ? 'chevronUp' : 'chevronDown'} size={13} strokeWidth={1.8} />
      </button>
      {open && (
        <div className="nz-kadm-color__pop" role="dialog" aria-label={t('Colour and opacity')}>
          <h5 className="nz-kadm-heading">{t('Colour')}</h5>
          <ColorSwatches value={hex} onChange={(h) => set(h, alpha ?? MARKER_ALPHA)} colors={MARKER_SWATCHES} />
          <h5 className="nz-kadm-heading">
            {t('Opacity')}
            {!setting.alpha && <span>{t('fixed by the server')}</span>}
          </h5>
          {setting.alpha ? (
            <Slider value={opacity} onChange={(a) => set(hex, a)} min={5} max={100} step={1} suffix="%" />
          ) : (
            <p className="nz-kadm-color__note">
              <Icon name="info" size={12} strokeWidth={1.7} />
              {t('Markers are drawn at {n}% opacity on this server version.', { n: MARKER_ALPHA })}
            </p>
          )}
          <div className="nz-kadm-color__preview">
            <span className="nz-kadm-color__ground" />
            <span className="nz-kadm-color__swatch" style={{ background: rgba(hex, opacity / 100), boxShadow: `0 0 18px ${rgba(hex, opacity / 250)}` }} />
            <span className="nz-kadm-color__label">{t('Over the street')}</span>
          </div>
        </div>
      )}
    </div>
  );
}

/* ── tag list (models / names) ───────────────────────────────────────── */

const NAME_RE = /^[\w-]{1,32}$/;

function TagList({
  value,
  onChange,
  lower,
  max,
  placeholder,
  invalid,
}: {
  value: string[];
  onChange: (v: string[]) => void;
  lower: boolean;
  max: number;
  placeholder: string;
  invalid?: boolean;
}) {
  const [text, setText] = useState('');
  const [bad, setBad] = useState(false);
  const input = useRef<HTMLInputElement>(null);

  const add = (raw: string) => {
    const parts = raw
      .split(/[\s,;]+/)
      .map((s) => (lower ? s.trim().toLowerCase() : s.trim()))
      .filter(Boolean);
    if (!parts.length) return;
    const okParts = parts.filter((s) => NAME_RE.test(s));
    setBad(okParts.length !== parts.length);
    const next = [...value];
    for (const s of okParts) if (!next.includes(s) && next.length < max) next.push(s);
    if (next.length !== value.length) onChange(next);
    setText(okParts.length !== parts.length ? parts.filter((s) => !NAME_RE.test(s)).join(' ') : '');
  };

  const onKey = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter' || e.key === ',' || e.key === ' ') {
      e.preventDefault();
      add(text);
    } else if (e.key === 'Backspace' && text === '' && value.length) {
      onChange(value.slice(0, -1));
    }
  };

  return (
    <div
      className={cx('nz-kadm-tags', (bad || invalid) && 'is-invalid')}
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) {
          e.preventDefault();
          input.current?.focus();
        }
      }}
    >
      {value.map((v) => (
        <span key={v} className="nz-kadm-tag">
          {v}
          <button type="button" aria-label={t('Remove {name}', { name: v })} onClick={() => onChange(value.filter((x) => x !== v))}>
            <Icon name="close" size={10} strokeWidth={2.2} />
          </button>
        </span>
      ))}
      <input
        ref={input}
        value={text}
        onChange={(e) => {
          setText(e.target.value);
          setBad(false);
        }}
        onKeyDown={onKey}
        onBlur={() => text.trim() && add(text)}
        onPaste={(e) => {
          const pasted = e.clipboardData.getData('text');
          if (/[\s,;]/.test(pasted)) {
            e.preventDefault();
            add(`${text} ${pasted}`);
          }
        }}
        placeholder={value.length ? t('Add more…') : placeholder}
        spellCheck={false}
        aria-invalid={bad || invalid || undefined}
      />
      {bad && <span className="nz-kadm-tags__err">{t('Letters, digits, _ and - only')}</span>}
    </div>
  );
}

/* ── previews ────────────────────────────────────────────────────────── */

/** Side view of a dropped key and its marker (style, colour, opacity, size, height). */
export function MarkerPreview({ style, color, size, height }: { style: string; color: string; size: number; height: number }) {
  const { hex, alpha } = parseColor(color);
  const fill = rgba(hex, (alpha ?? MARKER_ALPHA) / 100);
  const px = 120; // px per metre
  const groundY = 112;
  const keyY = groundY - 7;
  const s = Math.max(6, Math.min(2, size) * px);
  const cy = keyY - 8 - Math.min(2, height) * px - s / 2;
  const top = Math.min(0, cy - s / 2 - 6);
  return (
    <div className="nz-kadm-marker">
      <svg viewBox={`0 ${top} 360 ${130 - top}`} width="100%" height="130" preserveAspectRatio="xMidYMax meet" aria-hidden="true">
        <defs>
          <linearGradient id="nz-kadm-ground" x1="0" x2="0" y1="0" y2="1">
            <stop offset="0" stopColor="rgba(255,255,255,.08)" />
            <stop offset="1" stopColor="rgba(255,255,255,0)" />
          </linearGradient>
        </defs>
        <rect x="0" y={groundY} width="360" height="18" fill="url(#nz-kadm-ground)" />
        <line x1="0" x2="360" y1={groundY} y2={groundY} stroke="rgba(255,255,255,.18)" strokeWidth="1" />
        {/* the key on the ground (about 8 cm) */}
        <g transform={`translate(180 ${keyY}) scale(1.6)`} fill="none" stroke="rgba(255,255,255,.8)" strokeWidth="1.2">
          <circle cx="-6" cy="0" r="3.4" />
          <path d="M-2.6 0 H8 M4.6 0 v2.6 M7.4 0 v2.6" />
        </g>
        {/* height guide */}
        {style !== 'none' && (
          <>
            <line x1="236" x2="236" y1={keyY} y2={cy + s / 2} stroke="rgba(255,255,255,.25)" strokeDasharray="2 3" />
            <line x1="230" x2="242" y1={keyY} y2={keyY} stroke="rgba(255,255,255,.25)" />
            <line x1="230" x2="242" y1={cy + s / 2} y2={cy + s / 2} stroke="rgba(255,255,255,.25)" />
          </>
        )}
        {style === 'chevron' && <path d={`M${180 - s / 2} ${cy - s / 4} L180 ${cy + s / 2} L${180 + s / 2} ${cy - s / 4} L180 ${cy + s / 8} Z`} fill={fill} />}
        {style === 'ring' && <ellipse cx="180" cy={cy + s / 2} rx={s / 2} ry={s / 6} fill="none" stroke={fill} strokeWidth={Math.max(2, s / 8)} />}
        {style === 'dot' && <circle cx="180" cy={cy + s / 4} r={s / 3} fill={fill} />}
      </svg>
      <div className="nz-kadm-marker__legend">
        {style === 'none' ? (
          <span>{t('No marker: players only see the key prop')}</span>
        ) : (
          <>
            <span>{optionLabel('ground.markerStyle', style).label}</span>
            <span>{t('{n} m wide', { n: size })}</span>
            <span>{t('{n} m above the key', { n: height })}</span>
          </>
        )}
      </div>
    </div>
  );
}

const REACTIONS: { id: string; label: string; cls: string }[] = [
  { id: 'npc.handover', label: 'Hands over', cls: 'is-a' },
  { id: 'npc.drop', label: 'Drops and runs', cls: 'is-b' },
  { id: 'npc.fight', label: 'Fights back', cls: 'is-c' },
  { id: 'npc.flee', label: 'Drives away', cls: 'is-d' },
];

/** What the reaction weights mean as chances. */
export function ReactionBar({ values, groundOff }: { values: Record<string, KeySettingValue>; groundOff?: boolean }) {
  const weights = REACTIONS.map((r) => Math.max(0, Number(values[r.id]) || 0));
  const total = weights.reduce((a, b) => a + b, 0);
  return (
    <div className="nz-kadm-react">
      <div className="nz-kadm-react__bar">
        {total === 0 ? (
          <span className="nz-kadm-react__empty">{t('All weights are 0: drivers always hand the key over')}</span>
        ) : (
          REACTIONS.map((r, i) =>
            weights[i] > 0 ? <span key={r.id} className={r.cls} style={{ flexGrow: weights[i] }} title={t(r.label)} /> : null,
          )
        )}
      </div>
      <div className="nz-kadm-react__legend">
        {REACTIONS.map((r, i) => (
          <span key={r.id}>
            <i className={r.cls} />
            {t(r.label)}
            <b>{total ? Math.round((weights[i] / total) * 100) : r.id === 'npc.handover' ? 100 : 0}%</b>
          </span>
        ))}
      </div>
      {groundOff && weights[1] > 0 && (
        <p className="nz-kadm-react__note">
          <Icon name="info" size={12} strokeWidth={1.7} />
          {t('Keys on the ground are off: drivers who would drop the key hand it over instead.')}
        </p>
      )}
    </div>
  );
}
