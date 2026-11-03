/**
 * "Edit vehicle props" modal: Visual tab (categories → field editors) and JSON tab
 * (validated raw editor). Save → admin:vehicle:update { plate, patch: { props } }.
 */
import { useEffect, useMemo, useRef, useState } from 'react';
import { Badge, Button, Icon, IconButton, Modal, Tabs, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import { useEscape } from '@/lib/escape';
import type { AdminVehiclePatch } from '@/lib/types';
import { CATEGORIES, countSet } from './catalog';
import type { Category, Props } from './catalog';
import { PropField } from './fields';

interface Props_ {
  open: boolean;
  props: Props;
  vehicleLabel: string;
  onClose: () => void;
  onSave: (patch: AdminVehiclePatch, message: string) => Promise<boolean>;
  /** Open straight into a category. */
  initialCategory?: string | null;
}

type Tab = 'visual' | 'json';

const stable = (v: unknown) => JSON.stringify(v);

/** "Unexpected token } in JSON at position 120" → "line 7, column 3". */
function parseError(text: string, e: unknown): string {
  const msg = e instanceof Error ? e.message : String(e);
  const m = /position (\d+)/.exec(msg);
  if (m) {
    const pos = Number(m[1]);
    const before = text.slice(0, pos).split('\n');
    return t('{message} (line {line}, column {col})', {
      message: msg.replace(/^JSON\.parse: /, '').replace(/ in JSON at position \d+.*$/, ''),
      line: before.length,
      col: before[before.length - 1].length + 1,
    });
  }
  return msg;
}

export function PropsEditor({ open, props, vehicleLabel, onClose, onSave, initialCategory = null }: Props_) {
  const [tab, setTab] = useState<Tab>('visual');
  const [draft, setDraft] = useState<Props>(props);
  const [cat, setCat] = useState<string | null>(initialCategory);
  const [text, setText] = useState('');
  const [jsonError, setJsonError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const bodyRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    setDraft(JSON.parse(JSON.stringify(props ?? {})) as Props);
    setTab('visual');
    setCat(initialCategory);
    setJsonError(null);
  }, [open, props, initialCategory]);

  useEffect(() => {
    bodyRef.current?.scrollTo({ top: 0 });
  }, [cat, tab]);

  // Escape inside a category goes back to the list first (the modal's own handler is below this one).
  useEscape(() => setCat(null), open && tab === 'visual' && cat !== null && !busy);

  const dirty = useMemo(() => stable(draft) !== stable(props), [draft, props]);
  const category: Category | null = CATEGORIES.find((c) => c.id === cat) ?? null;

  const set = (key: string, value: unknown) =>
    setDraft((d) => {
      const next = { ...d };
      if (value === undefined) delete next[key];
      else next[key] = value;
      return next;
    });

  const switchTab = (next: Tab) => {
    if (next === tab) return;
    if (next === 'json') {
      setText(JSON.stringify(draft, null, 2));
      setJsonError(null);
      setTab('json');
      return;
    }
    if (jsonError) return; // stay on JSON until it parses
    setTab('visual');
  };

  const onText = (value: string) => {
    setText(value);
    try {
      const parsed: unknown = JSON.parse(value);
      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
        setJsonError(t('Vehicle properties must be a JSON object { … }'));
        return;
      }
      setJsonError(null);
      setDraft(parsed as Props);
    } catch (e) {
      setJsonError(parseError(value, e));
    }
  };

  const save = async () => {
    if (busy || jsonError || !dirty) return;
    setBusy(true);
    const ok = await onSave({ props: draft }, t('Vehicle props saved'));
    setBusy(false);
    if (ok) onClose();
  };

  const resetCategory = (c: Category) =>
    setDraft((d) => {
      const next = { ...d };
      for (const f of c.fields) {
        if (f.kind === 'mod') next[f.key] = -1;
        else if (f.kind === 'toggle') next[f.key] = false;
        else if (f.kind === 'enum') next[f.key] = f.fallback;
        else if (f.kind === 'rgb') next[f.key] = f.fallback;
        else if (f.kind === 'neon') next[f.key] = [false, false, false, false];
        else if (f.kind === 'float') delete next[f.key];
      }
      return next;
    });

  const resettable = category && category.fields.some((f) => f.kind === 'mod' || f.kind === 'toggle' || f.kind === 'enum' || f.kind === 'neon' || f.kind === 'float');

  return (
    <Modal
      open={open}
      onClose={onClose}
      locked={busy}
      icon="sliders"
      title={t('Edit vehicle props')}
      subtitle={vehicleLabel}
      width={620}
      className="nz-aveh-props"
      bodyClassName="nz-aveh-props__body"
      footer={
        <>
          <span className={cx('nz-aveh-props__state', dirty && 'is-dirty')}>
            {jsonError ? (
              <>
                <Icon name="warning" size={13} />
                {t('Fix the JSON to save')}
              </>
            ) : dirty ? (
              <>
                <i />
                {t('Unsaved changes')}
              </>
            ) : (
              t('No changes')
            )}
          </span>
          {dirty && !jsonError && (
            <Button variant="ghost" icon="refresh" onClick={() => setDraft(JSON.parse(JSON.stringify(props)) as Props)} disabled={busy}>
              {t('Revert')}
            </Button>
          )}
          <Button variant="line" onClick={onClose} disabled={busy}>
            {t('Cancel')}
          </Button>
          <Button variant="teal" icon="save" onClick={save} loading={busy} disabled={!dirty || !!jsonError}>
            {t('Save')}
          </Button>
        </>
      }
    >
      <div className="nz-aveh-props__top">
        <Tabs<Tab>
          value={tab}
          onChange={switchTab}
          items={[
            { value: 'visual', label: t('Visual'), icon: 'grid' },
            { value: 'json', label: t('JSON'), icon: 'code', disabled: false },
          ]}
        />
        {tab === 'json' && (
          <Button
            size="sm"
            variant="ghost"
            icon="code"
            disabled={!!jsonError}
            onClick={() => setText(JSON.stringify(draft, null, 2))}
          >
            {t('Format')}
          </Button>
        )}
      </div>

      <div className="nz-aveh-props__pane" ref={bodyRef}>
        {tab === 'json' ? (
          <div className={cx('nz-aveh-json', jsonError && 'is-invalid')}>
            <textarea
              value={text}
              onChange={(e) => onText(e.target.value)}
              spellCheck={false}
              aria-label={t('Vehicle properties (JSON)')}
              aria-invalid={!!jsonError}
              onKeyDown={(e) => {
                if (e.key === 'Tab') {
                  e.preventDefault();
                  const el = e.currentTarget;
                  const s = el.selectionStart;
                  const next = `${text.slice(0, s)}  ${text.slice(el.selectionEnd)}`;
                  onText(next);
                  requestAnimationFrame(() => el.setSelectionRange(s + 2, s + 2));
                }
              }}
            />
            <div className="nz-aveh-json__status" role={jsonError ? 'alert' : undefined}>
              {jsonError ? (
                <>
                  <Icon name="warning" size={13} strokeWidth={1.8} />
                  <span>{jsonError}</span>
                </>
              ) : (
                <>
                  <Icon name="checkCircle" size={13} strokeWidth={1.8} />
                  <span>{t('Valid JSON · {n} properties', { n: Object.keys(draft).length })}</span>
                </>
              )}
            </div>
          </div>
        ) : category ? (
          <div className="nz-aveh-pcat" key={category.id}>
            <div className="nz-aveh-pcat__head">
              <IconButton icon="arrowLeft" label={t('Back to categories')} variant="line" size="sm" onClick={() => setCat(null)} />
              <span className="nz-aveh-pcat__icon">
                <Icon name={category.icon} size={15} strokeWidth={1.7} />
              </span>
              <div className="nz-aveh-pcat__title">
                <b>{category.label()}</b>
                <span>{category.description()}</span>
              </div>
              {resettable && (
                <Button size="sm" variant="ghost" icon="refresh" onClick={() => resetCategory(category)} disabled={countSet(category, draft) === 0}>
                  {t('Reset to stock')}
                </Button>
              )}
            </div>
            <div className="nz-aveh-pcat__rows">
              {category.fields.map((f) => (
                <PropField key={f.key} f={f} props={draft} set={set} />
              ))}
            </div>
          </div>
        ) : (
          <div className="nz-aveh-pcats">
            {CATEGORIES.map((c) => {
              const n = countSet(c, draft);
              return (
                <button key={c.id} type="button" className={cx('nz-aveh-pcats__row', n > 0 && 'has-set')} onClick={() => setCat(c.id)}>
                  <span className="nz-aveh-pcats__icon">
                    <Icon name={c.icon} size={16} strokeWidth={1.6} />
                  </span>
                  <span className="nz-aveh-pcats__text">
                    <b>{c.label()}</b>
                    <span>{c.description()}</span>
                  </span>
                  {n > 0 && (
                    <Badge tone="teal" size="sm" title={t('{n} non-default values', { n })}>
                      {n}
                    </Badge>
                  )}
                  <Icon name="chevronRight" size={14} strokeWidth={1.8} className="nz-aveh-pcats__chev" />
                </button>
              );
            })}
          </div>
        )}
      </div>
    </Modal>
  );
}
