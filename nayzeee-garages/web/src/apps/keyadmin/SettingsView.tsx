/**
 * Admin key settings, generated from the server schema (nz:carlock:admin:settings: tabs and
 * settings with type, label, description, value, default, overridden, options / range).
 *
 * Toolbar: tabs (count of unsaved changes per tab) and a search over every tab (results
 * grouped by tab). Each tab: two columns of groups (model.ts GROUPS; unknown settings land in
 * "More"). A row: label + (i) tooltip (description, config value, range), "Custom" when an
 * admin value is stored, the control and a reset to the config value. Rows that do nothing
 * with the current draft are dimmed with the reason. Bottom bar while something is unsaved:
 * count, Discard, Save (Ctrl+S). Save sends only the changed values plus the resets (all or
 * nothing on the server); an "Invalid value: <label>" answer marks that row.
 */
import { useCallback, useEffect, useMemo, useState } from 'react';
import { Badge, Button, EmptyState, Icon, IconButton, InfoDot, Kbd, SearchInput, SkeletonRows, Tabs, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import { request } from '@/lib/nui';
import { toast } from '@/lib/store';
import type { KeyMode, KeySetting, KeySettingValue, KeySettings, KeySettingsTab } from '@/lib/types';
import { MarkerPreview, ReactionBar, SettingControl } from './SettingControls';
import { TAB_ICONS, columnsOf, groupsOf, idleReason, isList, list, optionLabel, same, splitUnit, validate, valueText } from './model';
import type { Group } from './model';

type Values = Record<string, KeySettingValue>;

const TAB_KEY = 'nz-keyadmin-settings-tab';

function readTab(): string | null {
  try {
    return window.localStorage.getItem(TAB_KEY);
  } catch {
    return null;
  }
}

function writeTab(v: string) {
  try {
    window.localStorage.setItem(TAB_KEY, v);
  } catch {
    /* storage unavailable */
  }
}

/** Lua's empty tables ({}) become lists where the type is a list. */
function normalize(s: KeySettings): KeySettings {
  const fix = (x: KeySetting, v: KeySettingValue) => (isList(x) ? (list(v as never) as KeySettingValue) : v);
  return {
    tabs: list(s.tabs),
    settings: list(s.settings).map((x) => ({ ...x, options: x.options ? list(x.options) : x.options, value: fix(x, x.value), default: fix(x, x.default) })),
  };
}

const valuesOf = (s: KeySettings): Values => Object.fromEntries(s.settings.map((x) => [x.id, x.value]));

interface Props {
  active: boolean;
  initialTab: KeySettingsTab | null;
  onDirtyChange: (dirty: boolean) => void;
  onKeyMode: (mode: KeyMode) => void;
}

export function SettingsView({ active, initialTab, onDirtyChange, onKeyMode }: Props) {
  const [base, setBase] = useState<KeySettings | null>(null);
  const [draft, setDraft] = useState<Values>({});
  const [resets, setResets] = useState<Set<string>>(() => new Set());
  const [failed, setFailed] = useState(false);
  const [tab, setTab] = useState<string>(() => initialTab ?? readTab() ?? 'keys');
  const [query, setQuery] = useState('');
  const [saving, setSaving] = useState(false);
  const [serverError, setServerError] = useState<{ id: string; text: string } | null>(null);

  const load = useCallback(async () => {
    setFailed(false);
    const res = await request('keyadmin:settings', {});
    if (!res.ok || !res.data) {
      setFailed(true);
      return;
    }
    const data = normalize(res.data);
    setBase(data);
    setDraft(valuesOf(data));
    setResets(new Set());
    setServerError(null);
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const byId = useMemo(() => new Map((base?.settings ?? []).map((s) => [s.id, s])), [base]);
  const tabs = base?.tabs ?? [];
  useEffect(() => {
    if (tabs.length && !tabs.some((x) => x.id === tab)) setTab(tabs[0].id);
  }, [tabs, tab]);

  /** ids whose saved state would change */
  const changed = useMemo(() => {
    const out = new Set<string>();
    for (const s of base?.settings ?? []) {
      if (resets.has(s.id)) {
        if (s.overridden) out.add(s.id);
      } else if (!same(draft[s.id], s.value)) out.add(s.id);
    }
    return out;
  }, [base, draft, resets]);
  const dirty = changed.size > 0;
  useEffect(() => onDirtyChange(dirty), [dirty, onDirtyChange]);
  useEffect(() => () => onDirtyChange(false), [onDirtyChange]);

  const errors = useMemo(() => {
    const out: Record<string, string> = {};
    for (const id of changed) {
      const s = byId.get(id);
      const e = s ? validate(s, draft[id]) : null;
      if (e) out[id] = e;
    }
    if (serverError && changed.has(serverError.id)) out[serverError.id] = serverError.text;
    return out;
  }, [changed, byId, draft, serverError]);
  const errorIds = Object.keys(errors);

  const setValue = (id: string, v: KeySettingValue) => {
    setDraft((d) => ({ ...d, [id]: v }));
    setResets((r) => {
      if (!r.has(id)) return r;
      const next = new Set(r);
      next.delete(id);
      return next;
    });
    if (serverError?.id === id) setServerError(null);
  };

  const reset = (s: KeySetting) => {
    setDraft((d) => ({ ...d, [s.id]: s.default }));
    if (s.overridden) setResets((r) => new Set(r).add(s.id));
  };

  const discard = () => {
    if (!base) return;
    setDraft(valuesOf(base));
    setResets(new Set());
    setServerError(null);
  };

  const save = useCallback(async () => {
    if (!base || !dirty || saving) return;
    if (errorIds.length) {
      const first = byId.get(errorIds[0]);
      if (first && !query) setTab(first.tab);
      toast({ type: 'error', message: `${first?.label ?? errorIds[0]}: ${errors[errorIds[0]]}` });
      return;
    }
    const values: Values = {};
    const reset: string[] = [];
    for (const id of changed) {
      if (resets.has(id)) reset.push(id);
      else values[id] = draft[id];
    }
    setSaving(true);
    const res = await request('keyadmin:saveSettings', { values, reset });
    setSaving(false);
    if (!res.ok || !res.data) {
      const msg = res.ok ? '' : res.error;
      const hit = base.settings.find((s) => msg.endsWith(`: ${s.label}`));
      if (hit) {
        setServerError({ id: hit.id, text: t('The server refused this value') });
        if (!query) setTab(hit.tab);
      }
      return;
    }
    const saved = normalize(res.data);
    setBase(saved);
    setDraft(valuesOf(saved));
    setResets(new Set());
    setServerError(null);
    const mode = saved.settings.find((s) => s.id === 'keys.mode')?.value;
    if (mode === 'flexible' || mode === 'limited' || mode === 'virtual') onKeyMode(mode);
    toast({ type: 'success', title: t('Key settings saved'), message: t('{n} change(s) apply to every player right away.', { n: changed.size }) });
  }, [base, dirty, saving, errorIds, errors, byId, query, changed, resets, draft, onKeyMode]);

  // Ctrl / Cmd + S
  useEffect(() => {
    if (!active || !dirty) return;
    const onKey = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') {
        e.preventDefault();
        void save();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [active, dirty, save]);

  const pickTab = (id: string) => {
    setTab(id);
    writeTab(id);
    setQuery('');
  };

  /* ── search ── */
  const q = query.trim().toLowerCase();
  const matches = useMemo(() => {
    if (!q || !base) return null;
    const words = q.split(/\s+/);
    return base.tabs
      .map((tb) => {
        const groups = groupsOf(tb.id, base.settings)
          .map((g) => ({
            ...g,
            settings: g.settings.filter((s) => {
              const text = [s.label, s.description, s.id, g.title, tb.label, ...(s.options ?? []).map((o) => optionLabel(s.id, o).label)]
                .join(' ')
                .toLowerCase();
              return words.every((w) => text.includes(w));
            }),
          }))
          .filter((g) => g.settings.length > 0);
        return { tab: tb, groups };
      })
      .filter((m) => m.groups.length > 0);
  }, [q, base]);

  const tabCount = (id: string) => (base?.settings ?? []).filter((s) => s.tab === id && changed.has(s.id)).length;

  if (!base) {
    return (
      <div className="nz-kadm-set">
        {failed ? (
          <EmptyState
            icon="warning"
            title={t('The key settings could not be loaded')}
            description={t('Only admins can read them. Try again in a moment.')}
            action={
              <Button size="sm" icon="refresh" onClick={() => void load()}>
                {t('Try again')}
              </Button>
            }
          />
        ) : (
          <div className="nz-kadm-set__loading">
            <SkeletonRows count={8} />
          </div>
        )}
      </div>
    );
  }

  const renderRow = (s: KeySetting) => {
    const v = draft[s.id] ?? s.value;
    const idle = idleReason(s.id, draft);
    const err = errors[s.id];
    const isChanged = changed.has(s.id);
    const pendingReset = resets.has(s.id);
    const canReset = (s.overridden && !pendingReset) || !same(v, s.default);
    const { label } = splitUnit(s.label);
    const range =
      s.type === 'number' && (s.min !== undefined || s.max !== undefined)
        ? t('Range {min} – {max}', { min: s.min ?? '…', max: s.max ?? '…' })
        : null;
    return (
      <div key={s.id} className={cx('nz-kadm-row', isList(s) && 'is-stacked', idle && 'is-idle', isChanged && 'is-changed', err && 'has-error')}>
        <div className="nz-kadm-row__text">
          <div className="nz-kadm-row__label">
            {isChanged && <i className="nz-kadm-row__dot" title={t('Unsaved')} />}
            <b>{q ? <Mark text={label} query={query} /> : label}</b>
            <InfoDot
              text={
                <span className="nz-kadm-tip">
                  <span>{s.description}</span>
                  <span className="nz-kadm-tip__meta">
                    {t('Config value')}: <b>{valueText(s, s.default)}</b>
                    {range && <> · {range}</>}
                  </span>
                  <span className="nz-kadm-tip__id">{s.id}</span>
                </span>
              }
            />
            {s.overridden && !pendingReset && (
              <Badge tone="teal" size="sm" className="nz-kadm-row__custom" title={t('An admin value is stored in the database')}>
                {t('Custom')}
              </Badge>
            )}
            {pendingReset && (
              <Badge tone="amber" size="sm" className="nz-kadm-row__custom">
                {t('Back to config')}
              </Badge>
            )}
          </div>
          <p className="nz-kadm-row__desc">
            {err ? (
              <span className="nz-kadm-row__err">
                <Icon name="warning" size={12} strokeWidth={1.8} />
                {err}
              </span>
            ) : idle ? (
              <span className="nz-kadm-row__idle">{idle}</span>
            ) : (
              s.description
            )}
          </p>
        </div>
        <div className="nz-kadm-row__control">
          <SettingControl setting={s} value={v} onChange={(x) => setValue(s.id, x)} invalid={!!err} />
          <span className="nz-kadm-row__reset">
            {canReset && (
              <IconButton
                icon="refresh"
                size="sm"
                label={t('Reset to the config value ({value})', { value: valueText(s, s.default) })}
                onClick={() => reset(s)}
              />
            )}
          </span>
        </div>
      </div>
    );
  };

  const renderGroup = (g: Group) => (
    <section key={g.id} className="nz-kadm-group">
      <h4 className="nz-kadm-group__title">
        <Icon name={g.icon} size={13} strokeWidth={1.7} />
        {q ? <Mark text={g.title} query={query} /> : g.title}
      </h4>
      <div className="nz-kadm-group__card">
        {g.settings.map(renderRow)}
        {!q && g.id === 'ground.marker' && (
          <MarkerPreview
            style={String(draft['ground.markerStyle'] ?? 'chevron')}
            color={String(draft['ground.markerColor'] ?? '#2dd4bf')}
            size={Number(draft['ground.markerSize'] ?? 0.25)}
            height={Number(draft['ground.markerHeight'] ?? 0.35)}
          />
        )}
        {!q && g.id === 'npc.reactions' && <ReactionBar values={draft} groundOff={draft['ground.enabled'] === false} />}
      </div>
    </section>
  );

  const current = groupsOf(tab, base.settings);
  const [left, right] = columnsOf(current);

  return (
    <div className={cx('nz-kadm-set', dirty && 'has-bar')}>
      <div className="nz-kadm-set__toolbar">
        <Tabs<string>
          value={q ? '' : tab}
          onChange={pickTab}
          className="nz-kadm-set__tabs"
          items={tabs.map((tb) => ({ value: tb.id, label: tb.label, icon: TAB_ICONS[tb.id] ?? 'sliders', count: tabCount(tb.id) || undefined }))}
        />
        <SearchInput value={query} onChange={setQuery} placeholder={t('Search key settings')} size="sm" className="nz-kadm-set__search" />
        <IconButton icon="refresh" label={dirty ? t('Discard the changes first to reload') : t('Reload from the server')} disabled={dirty} onClick={() => void load()} />
      </div>

      <div className="nz-kadm-set__body" key={q ? 'search' : tab}>
        {matches ? (
          matches.length === 0 ? (
            <EmptyState
              icon="search"
              title={t('No key settings match “{query}”', { query: query.trim() })}
              description={t('Try another word, like range, PIN, marker or police.')}
              action={
                <Button size="sm" onClick={() => setQuery('')}>
                  {t('Clear search')}
                </Button>
              }
            />
          ) : (
            <div className="nz-kadm-results-set">
              {matches.map((m) => (
                <div key={m.tab.id} className="nz-kadm-set__hit">
                  <button type="button" className="nz-kadm-set__hit-head" onClick={() => pickTab(m.tab.id)}>
                    <Icon name={TAB_ICONS[m.tab.id] ?? 'sliders'} size={14} strokeWidth={1.7} />
                    <b>{m.tab.label}</b>
                    <span>{t('{n} result(s)', { n: m.groups.reduce((n, g) => n + g.settings.length, 0) })}</span>
                    <em>
                      {t('Open tab')}
                      <Icon name="arrowRight" size={12} strokeWidth={1.8} />
                    </em>
                  </button>
                  <div className="nz-kadm-cols">
                    <div className="nz-kadm-col">{m.groups.filter((_, i) => i % 2 === 0).map(renderGroup)}</div>
                    <div className="nz-kadm-col">{m.groups.filter((_, i) => i % 2 === 1).map(renderGroup)}</div>
                  </div>
                </div>
              ))}
            </div>
          )
        ) : (
          <div className="nz-kadm-cols">
            <div className="nz-kadm-col">{left.map(renderGroup)}</div>
            <div className="nz-kadm-col">{right.map(renderGroup)}</div>
          </div>
        )}
      </div>

      {dirty && (
        <div className={cx('nz-kadm-bar', errorIds.length > 0 && 'has-error')} role="status">
          {errorIds.length > 0 ? (
            <>
              <Icon name="warning" size={14} strokeWidth={1.8} />
              <span>{t('{n} setting(s) need attention before saving', { n: errorIds.length })}</span>
            </>
          ) : (
            <>
              <i className="nz-kadm-bar__dot" />
              <span>{t('{n} unsaved change(s)', { n: changed.size })}</span>
            </>
          )}
          <span className="nz-kadm-bar__keys">
            <Kbd>Ctrl</Kbd>
            <Kbd>S</Kbd>
          </span>
          <Button variant="ghost" size="sm" icon="close" onClick={discard} disabled={saving}>
            {t('Discard')}
          </Button>
          <Button variant="teal" size="sm" icon="save" onClick={() => void save()} loading={saving} disabled={errorIds.length > 0}>
            {t('Save changes')}
          </Button>
        </div>
      )}
    </div>
  );
}

/** Wraps the matches of `query` in <mark>. */
function Mark({ text, query }: { text: string; query: string }) {
  const q = query.trim().toLowerCase();
  if (!q) return <>{text}</>;
  const words = q.split(/\s+/).filter(Boolean);
  const re = new RegExp(`(${words.map((w) => w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|')})`, 'ig');
  return (
    <>
      {text.split(re).map((part, i) =>
        words.includes(part.toLowerCase()) ? (
          <mark key={i} className="nz-kadm-mark">
            {part}
          </mark>
        ) : (
          <span key={i}>{part}</span>
        ),
      )}
    </>
  );
}
