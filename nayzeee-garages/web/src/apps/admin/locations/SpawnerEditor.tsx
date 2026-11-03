/**
 * SpawnerEditor — the "Spawner vehicles" list of a garage / job location and its vehicle modal.
 *
 * API
 *   <SpawnerEditor value onChange grades? invalid? />
 *   - grades: options for the "Grades" multi-select (job kind); omit for public garages, which
 *     hides the Grades column and field.
 * The table lists spawn code, display name, plate template, grades, setup (livery, extras and
 * max mods as compact markers) and price; rows can be edited, reordered, duplicated and removed. The modal edits one
 * SpawnerVehicle (plate template: '#' digit, '@' letter, '*' either, other characters literal).
 */
import { useMemo, useRef, useState } from 'react';
import type { KeyboardEvent } from 'react';
import {
  Button,
  EmptyState,
  Field,
  IconButton,
  Input,
  Menu,
  Modal,
  MultiSelect,
  NumberInput,
  Table,
  Toggle,
  Tooltip,
  Icon,
  cx,
} from '@/components/ui';
import type { TableColumn } from '@/components/ui';
import { t } from '@/lib/i18n';
import { money } from '@/lib/format';
import { useSettings } from '@/lib/store';
import type { SpawnerVehicle } from '@/lib/types';
import { newSpawnerVehicle } from './defaults';

export interface SpawnerEditorProps {
  value: SpawnerVehicle[];
  onChange: (list: SpawnerVehicle[]) => void;
  grades?: { value: number; label: string }[];
  invalid?: boolean;
}

const EXTRAS = Array.from({ length: 14 }, (_, i) => String(i + 1));
/** Server limit per location (server/locations.lua LIMITS.spawner). */
export const MAX_SPAWNER = 60;
const MODEL_RE = /^[A-Za-z0-9_-]{1,32}$/;
const PLATE_RE = /^[A-Z0-9#@* ]{0,8}$/;

/** Example plate for a template (stable per template). */
export function platePreview(template: string): string {
  if (!template) return '';
  const L = 'ABCDEFGHJKLMNPRSTUVWXYZ';
  let seed = 7;
  for (const ch of template) seed = (seed * 31 + ch.charCodeAt(0)) % 9973;
  const rnd = () => {
    seed = (seed * 48271) % 2147483647;
    return seed;
  };
  return template
    .split('')
    .map((c) => {
      if (c === '#') return String(rnd() % 10);
      if (c === '@') return L[rnd() % L.length];
      if (c === '*') return rnd() % 2 ? String(rnd() % 10) : L[rnd() % L.length];
      return c;
    })
    .join('');
}

const extrasSet = (v: SpawnerVehicle) => Object.keys(v.extras ?? {}).length;

/** Livery / extras / max mods as small markers; "Default" when nothing is customised. */
function SetupCell({ v }: { v: SpawnerVehicle }) {
  const extras = extrasSet(v);
  if (v.livery < 0 && !extras && !v.maxMods) return <span className="nz-admin-spawner__auto">{t('Default')}</span>;
  return (
    <span className="nz-admin-spawner__setup">
      {v.livery >= 0 && (
        <Tooltip content={t('Livery {n}', { n: v.livery })}>
          <span className="nz-admin-spawner__mark">
            <Icon name="palette" size={11} strokeWidth={1.9} />
            {v.livery}
          </span>
        </Tooltip>
      )}
      {extras > 0 && (
        <Tooltip content={t('{count} extras set', { count: extras })}>
          <span className="nz-admin-spawner__mark">
            <Icon name="sliders" size={11} strokeWidth={1.9} />
            {extras}
          </span>
        </Tooltip>
      )}
      {v.maxMods && (
        <Tooltip content={t('Max performance mods')}>
          <span className="nz-admin-spawner__mark is-teal">
            <Icon name="gauge" size={11} strokeWidth={1.9} />
            {t('Max')}
          </span>
        </Tooltip>
      )}
    </span>
  );
}

export function SpawnerEditor({ value, onChange, grades, invalid = false }: SpawnerEditorProps) {
  const [editing, setEditing] = useState<{ index: number | null; draft: SpawnerVehicle; session: number } | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const showGrades = !!grades;

  const gradeText = (v: SpawnerVehicle) => {
    if (!v.grades.length) return t('All');
    const sorted = [...v.grades].sort((a, b) => a - b);
    return sorted.length > 3 ? `${sorted[0]}–${sorted[sorted.length - 1]}` : sorted.join(', ');
  };

  const open = (index: number | null) => {
    setEditing((e) => ({
      index,
      draft: index === null ? newSpawnerVehicle() : JSON.parse(JSON.stringify(value[index])),
      session: (e?.session ?? 0) + 1,
    }));
    setModalOpen(true);
  };

  const commit = (draft: SpawnerVehicle) => {
    if (!editing) return;
    const clean: SpawnerVehicle = { ...draft, model: draft.model.trim(), label: draft.label.trim(), plate: draft.plate.trim() };
    if (editing.index === null) onChange([...value, clean]);
    else onChange(value.map((v, i) => (i === editing.index ? clean : v)));
    setModalOpen(false);
  };

  const move = (i: number, dir: -1 | 1) => {
    const j = i + dir;
    if (j < 0 || j >= value.length) return;
    const next = [...value];
    [next[i], next[j]] = [next[j], next[i]];
    onChange(next);
  };

  type Row = SpawnerVehicle & { __i: number };
  const rows: Row[] = value.map((v, i) => ({ ...v, __i: i }));

  const columns: TableColumn<Row>[] = [
    { key: 'model', header: t('Spawn code'), width: 92, render: (v) => <b className="nz-admin-spawner__code">{v.model}</b> },
    {
      key: 'label',
      header: t('Display name'),
      render: (v) => (v.label ? <span title={v.label}>{v.label}</span> : <span className="nz-admin-spawner__auto">{t('Automatic')}</span>),
    },
    {
      key: 'plate',
      header: t('Plate'),
      width: 86,
      render: (v) => (v.plate ? <span className="nz-admin-spawner__mono">{v.plate}</span> : <span className="nz-admin-spawner__auto">{t('Random')}</span>),
    },
    ...(showGrades ? [{ key: 'grades', header: t('Grades'), width: 70, render: (v: Row) => gradeText(v) }] : []),
    { key: 'setup', header: t('Setup'), width: 128, render: (v) => <SetupCell v={v} /> },
    {
      key: 'price',
      header: t('Price'),
      width: 74,
      align: 'right',
      render: (v) => (v.price > 0 ? money(v.price) : <span className="nz-admin-spawner__auto">{t('Free')}</span>),
    },
    {
      key: 'actions',
      header: '',
      width: 64,
      align: 'right',
      render: (v) => (
        <span className="nz-admin-spawner__actions">
          <IconButton icon="edit" size="sm" label={t('Edit')} onClick={() => open(v.__i)} />
          <Menu
            label={t('More actions')}
            trigger={<IconButton icon="more" size="sm" label={t('More actions')} />}
            items={[
              { label: t('Move up'), icon: 'chevronUp', disabled: v.__i === 0, onSelect: () => move(v.__i, -1) },
              { label: t('Move down'), icon: 'chevronDown', disabled: v.__i === value.length - 1, onSelect: () => move(v.__i, 1) },
              {
                label: t('Duplicate'),
                icon: 'copy',
                disabled: value.length >= MAX_SPAWNER,
                onSelect: () => {
                  const next = [...value];
                  next.splice(v.__i + 1, 0, JSON.parse(JSON.stringify(value[v.__i])));
                  onChange(next);
                },
              },
              { label: t('Remove'), icon: 'trash', danger: true, onSelect: () => onChange(value.filter((_, i) => i !== v.__i)) },
            ]}
          />
        </span>
      ),
    },
  ];

  return (
    <div className={cx('nz-admin-spawner', invalid && 'is-invalid')}>
      {value.length ? (
        <Table<Row> className="nz-admin-spawner__table" columns={columns} rows={rows} rowKey={(v) => v.__i} dense />
      ) : (
        <EmptyState
          className="nz-admin-spawner__empty"
          compact
          icon="car"
          title={t('No vehicles yet')}
          description={t('Add the vehicles players can take out here.')}
        />
      )}
      <div className="nz-admin-spawner__foot">
        <Button size="sm" icon="plus" onClick={() => open(null)} disabled={value.length >= MAX_SPAWNER}>
          {t('Add vehicle')}
        </Button>
        {value.length > 0 && <span className="nz-admin-spawner__count">{value.length === 1
              ? t('1 vehicle')
              : value.length >= MAX_SPAWNER
                ? t('{count} vehicles (the maximum)', { count: value.length })
                : t('{count} vehicles', { count: value.length })}</span>}
      </div>

      {editing && (
        <SpawnerVehicleModal
          key={editing.session}
          open={modalOpen}
          isNew={editing.index === null}
          initial={editing.draft}
          grades={grades}
          taken={value.filter((_, i) => i !== editing.index).map((v) => v.model.toLowerCase())}
          onClose={() => setModalOpen(false)}
          onSave={commit}
        />
      )}
    </div>
  );
}

/* ── vehicle modal ────────────────────────────────────────────────────── */

interface SpawnerVehicleModalProps {
  open: boolean;
  isNew: boolean;
  initial: SpawnerVehicle;
  grades?: { value: number; label: string }[];
  taken: string[];
  onClose: () => void;
  onSave: (v: SpawnerVehicle) => void;
}

function SpawnerVehicleModal({ open, isNew, initial, grades, taken, onClose, onSave }: SpawnerVehicleModalProps) {
  const settings = useSettings();
  const [v, setV] = useState<SpawnerVehicle>(initial);
  const [tried, setTried] = useState(false);
  const set = <K extends keyof SpawnerVehicle>(k: K, val: SpawnerVehicle[K]) => setV((p) => ({ ...p, [k]: val }));

  const modelError = !v.model.trim()
    ? t('Enter the spawn code')
    : !MODEL_RE.test(v.model.trim())
      ? t('Letters, numbers, - and _ only')
      : null;
  const plateError = PLATE_RE.test(v.plate) ? null : t('Use letters, numbers, spaces and # @ * (max 8)');
  const duplicate = !modelError && taken.includes(v.model.trim().toLowerCase());
  const preview = useMemo(() => platePreview(v.plate.trim()), [v.plate]);

  const save = () => {
    setTried(true);
    if (modelError || plateError) return;
    onSave(v);
  };
  // Enter in a number field: it commits its value on Enter (state), so apply a tick later.
  const saveRef = useRef(save);
  saveRef.current = save;
  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    if (e.key !== 'Enter' || e.defaultPrevented || (e.target as HTMLElement).tagName !== 'INPUT') return;
    e.preventDefault();
    window.setTimeout(() => saveRef.current(), 0);
  };

  const cycleExtra = (id: string) => {
    const cur = v.extras[id];
    const next = { ...v.extras };
    if (cur === undefined) next[id] = true;
    else if (cur === true) next[id] = false;
    else delete next[id];
    set('extras', next);
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      icon="car"
      title={isNew ? t('Add vehicle') : t('Edit vehicle')}
      subtitle={v.model.trim() || t('Spawner vehicle')}
      width={540}
      footer={
        <>
          <Button variant="line" onClick={onClose}>
            {t('Cancel')}
          </Button>
          <Button variant="teal" icon="check" onClick={save}>
            {isNew ? t('Add vehicle') : t('Apply')}
          </Button>
        </>
      }
    >
      <div className="nz-admin-vehform" onKeyDown={onKeyDown}>
      <div className="nz-admin-form__grid">
        <Field
          label={t('Spawn code')}
          required
          error={tried ? modelError : null}
          hint={duplicate ? t('This model is already in the list (allowed).') : t('The model name, e.g. police3')}
        >
          <Input value={v.model} onChange={(s) => set('model', s.replace(/\s/g, ''))} mono maxLength={32} placeholder="police3" onEnter={save} autoFocus />
        </Field>
        <Field label={t('Display name')} hint={t('Leave empty to use the game name')}>
          <Input value={v.label} onChange={(s) => set('label', s)} maxLength={60} placeholder={t('Automatic')} onEnter={save} />
        </Field>
        <Field
          label={t('Plate')}
          error={plateError}
          hint={
            <>
              {t('# digit, @ letter, * either')}
              {preview && (
                <>
                  {' · '}
                  {t('e.g.')} <b className="nz-admin-spawner__mono">{preview}</b>
                </>
              )}
            </>
          }
        >
          <Input value={v.plate} onChange={(s) => set('plate', s.toUpperCase())} mono uppercase maxLength={8} placeholder={t('Random')} onEnter={save} />
        </Field>
        <Field label={t('Price')} hint={v.price > 0 ? t('Charged every time it is taken out') : t('Free to take out')}>
          <NumberInput value={v.price} onChange={(n) => set('price', Math.round(n))} min={0} max={10000000} step={50} prefix={settings.currency} />
        </Field>
        {grades && (
          <Field label={t('Grades')} hint={t('Empty = every grade')}>
            <MultiSelect<number> value={v.grades} onChange={(g) => set('grades', [...g].sort((a, b) => a - b))} options={grades} placeholder={t('All grades')} />
          </Field>
        )}
        <Field label={t('Livery')} hint={t('-1 = the default livery')}>
          <NumberInput value={v.livery} onChange={(n) => set('livery', Math.round(n))} min={-1} max={1000} suffix={v.livery < 0 ? t('default') : undefined} />
        </Field>
      </div>

      <Toggle
        checked={v.maxMods}
        onChange={(b) => set('maxMods', b)}
        label={t('Max performance mods')}
        description={t('Engine, brakes, transmission, suspension and turbo at their best level')}
      />

      <div className="nz-admin-extras">
        <div className="nz-admin-extras__head">
          <span className="nz-admin-form__label">{t('Extras')}</span>
          <span className="nz-admin-extras__legend">
            <i className="is-default" /> {t('Default')}
            <i className="is-on" /> {t('On')}
            <i className="is-off" /> {t('Off')}
          </span>
          {Object.keys(v.extras).length > 0 && (
            <button type="button" className="nz-admin-extras__reset" onClick={() => set('extras', {})}>
              {t('Reset')}
            </button>
          )}
        </div>
        <div className="nz-admin-extras__grid" role="group" aria-label={t('Extras')}>
          {EXTRAS.map((id) => {
            const st = v.extras[id];
            const state = st === undefined ? 'default' : st ? 'on' : 'off';
            return (
              <button
                key={id}
                type="button"
                className={cx('nz-admin-extras__chip', `is-${state}`)}
                onClick={() => cycleExtra(id)}
                title={state === 'default' ? t('Extra {id}: vehicle default', { id }) : state === 'on' ? t('Extra {id}: on', { id }) : t('Extra {id}: off', { id })}
              >
                {id}
              </button>
            );
          })}
        </div>
        <span className="nz-admin-form__hint">{t('Click an extra to cycle default → on → off. Extras the model does not have are ignored.')}</span>
      </div>
      </div>
    </Modal>
  );
}
