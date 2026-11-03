/**
 * Admin › Settings — server-wide rules (Settings type) in five tabs.
 *
 * Toolbar: tabs, a search box that filters option rows across every tab (results grouped by
 * tab while searching), Discard and a teal Save (disabled until something changed; a dot marks
 * unsaved changes). Save → admin:settings:save { settings } → toast + setData with the saved
 * settings (Lua also pushes the interface part to every NUI, re-theming the accent).
 * Escape with unsaved changes asks before closing the panel; Enter in a field saves.
 */
import { useCallback, useEffect, useMemo, useState } from 'react';
import { Button, ConfirmDialog, EmptyState, Icon, Kbd, OptionRow, SearchInput, Tabs, cx } from '@/components/ui';
import { request } from '@/lib/nui';
import { toast, useApp, useSettings } from '@/lib/store';
import { useEscape } from '@/lib/escape';
import { t } from '@/lib/i18n';
import type { AdminPageProps, Settings } from '@/lib/types';
import { useAdminShell } from '../shared/shell';
import { TABS } from '../settings/schema';
import type { Ctx, PanelDef, RowDef, TabDef, TabId } from '../settings/schema';
import { imageUrlError } from '../settings/fields';
import { isHex } from '../settings/accent';
import { Highlight } from '../vehicles/common';
import { devHint } from '../vehicles/devHint';
import '../settings/settings.css';

const clone = <T,>(v: T): T => JSON.parse(JSON.stringify(v)) as T;
const TAB_KEY = 'nz-admin-settings-tab';

function readTab(): TabId | null {
  try {
    const v = window.localStorage.getItem(TAB_KEY);
    return TABS.some((x) => x.id === v) ? (v as TabId) : null;
  } catch {
    return null;
  }
}

function writeTab(v: TabId) {
  try {
    window.localStorage.setItem(TAB_KEY, v);
  } catch {
    /* storage unavailable */
  }
}

/** Server-side rules mirrored for instant feedback (server/settings.lua validates again). */
function validate(s: Settings, impoundIds: number[]): Record<string, string> {
  const e: Record<string, string> = {};
  if (!s.interface.currency.trim()) e['interface.currency'] = t('Enter a currency symbol');
  const img = s.interface.showImages ? imageUrlError(s.interface.imageUrl, true) : null;
  if (img) e['interface.imageUrl'] = img;
  if (!isHex(s.interface.accent)) e['interface.accent'] = t('Use a hex colour like #08AFA2');
  if (s.garages.outOnRestart === 'impound' && (s.garages.restartImpound === null || !impoundIds.includes(s.garages.restartImpound))) {
    e['garages.restartImpound'] = t('Choose the impound that receives vehicles left out');
  }
  return e;
}

interface Match {
  tab: TabDef;
  panels: { panel: PanelDef; rows: RowDef[] }[];
}

export function SettingsPage({ data, setData }: AdminPageProps) {
  const shell = useAdminShell();
  const app = useApp('admin');
  const iface = useSettings();
  const [hint] = useState(() => devHint(data));
  const [tab, setTab] = useState<TabId>(() => (TABS.some((x) => x.id === hint.tab) ? (hint.tab as TabId) : readTab() ?? 'vehicles'));
  const [query, setQuery] = useState('');
  const [base, setBase] = useState<Settings>(() => clone(data.settings));
  const [draft, setDraft] = useState<Settings>(() => clone(data.settings));
  const [saving, setSaving] = useState(false);
  const [leave, setLeave] = useState(false);

  // Settings changed elsewhere (refresh, another admin) while nothing is being edited.
  const dirty = useMemo(() => JSON.stringify(draft) !== JSON.stringify(base), [draft, base]);
  useEffect(() => {
    if (JSON.stringify(data.settings) === JSON.stringify(base)) return;
    setBase(clone(data.settings));
    if (!dirty) setDraft(clone(data.settings));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [data.settings]);

  const impoundIds = useMemo(
    () => data.locations.filter((l) => l.kind === 'impound' && l.id !== null).map((l) => l.id as number),
    [data.locations],
  );
  const errors = useMemo(() => validate(draft, impoundIds), [draft, impoundIds]);
  const errorCount = Object.keys(errors).length;

  const changed = useMemo(() => {
    const out = new Set<string>();
    for (const section of Object.keys(draft) as (keyof Settings)[]) {
      const a = draft[section] as unknown as Record<string, unknown>;
      const b = base[section] as unknown as Record<string, unknown>;
      for (const key of Object.keys(a)) if (JSON.stringify(a[key]) !== JSON.stringify(b?.[key])) out.add(`${section}.${key}`);
    }
    return out;
  }, [draft, base]);

  const set = useCallback<Ctx['set']>((section, key, value) => {
    setDraft((d) => ({ ...d, [section]: { ...d[section], [key]: value } }));
  }, []);

  const save = useCallback(async () => {
    if (!dirty || saving) return;
    if (errorCount) {
      const first = Object.keys(errors)[0];
      const owner = TABS.find((x) => x.columns.flat().some((p) => p.rows.some((r) => r.id === first)));
      if (owner && !query) setTab(owner.id);
      toast({ type: 'error', message: errors[first] });
      return;
    }
    setSaving(true);
    const payload = clone(draft);
    if (!payload.vehicles.saveDamage) payload.vehicles.saveDeformation = false;
    const res = await request('admin:settings:save', { settings: payload });
    setSaving(false);
    if (!res.ok) return;
    const saved = { ...payload, ...(res.data ?? {}) } as Settings;
    setBase(clone(saved));
    setDraft(clone(saved));
    setData((d) => ({ ...d, settings: saved }));
    toast({ type: 'success', title: t('Settings saved'), message: t('Changes apply to every player right away.') });
  }, [dirty, saving, errorCount, errors, draft, query, setData]);

  const discard = () => setDraft(clone(base));

  useEscape(() => setLeave(true), dirty && !shell.hidden && !leave);

  // Ctrl/Cmd + S saves from anywhere on the page.
  useEffect(() => {
    if (!dirty) return;
    const onKey = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') {
        e.preventDefault();
        void save();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [dirty, save]);

  const ctx: Ctx = {
    s: draft,
    set,
    data,
    currency: draft.interface.currency || iface.currency,
    errors,
    save: () => void save(),
    go: shell.go,
  };

  const pickTab = (id: TabId) => {
    setTab(id);
    writeTab(id);
    setQuery('');
  };

  /* ── search ── */
  const q = query.trim().toLowerCase();
  const matches = useMemo<Match[] | null>(() => {
    if (!q) return null;
    const hit = (r: RowDef, p: PanelDef, tb: TabDef) => {
      const desc = r.description(ctx);
      const text = [r.label(), typeof desc === 'string' ? desc : '', r.keywords?.() ?? '', p.title(), tb.label()].join(' ').toLowerCase();
      return q.split(/\s+/).every((w) => text.includes(w));
    };
    return TABS.map((tb) => ({
      tab: tb,
      panels: tb.columns
        .flat()
        .map((panel) => ({ panel, rows: panel.rows.filter((r) => hit(r, panel, tb)) }))
        .filter((x) => x.rows.length > 0),
    })).filter((m) => m.panels.length > 0);
    // ctx changes with every draft edit; descriptions depend on it.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q, draft]);

  const tabErrors = (tb: TabDef) => tb.columns.flat().some((p) => p.rows.some((r) => errors[r.id]));
  const tabChanged = (tb: TabDef) => tb.columns.flat().reduce((n, p) => n + p.rows.filter((r) => changed.has(r.id)).length, 0);

  const renderRow = (r: RowDef) => {
    const disabled = r.disabled?.(draft) ?? false;
    const err = errors[r.id];
    const desc = r.description(ctx);
    return (
      <OptionRow
        key={r.id}
        stacked={r.stacked}
        className={cx('nz-aset-row', disabled && 'is-disabled', err && 'has-error', changed.has(r.id) && 'is-changed')}
        label={
          <>
            {changed.has(r.id) && <i className="nz-aset-row__dot" title={t('Changed')} />}
            {q ? <Highlight text={r.label()} query={query} /> : r.label()}
          </>
        }
        description={<span className={cx(err && desc === err && 'nz-aset-err')}>{desc}</span>}
        control={r.control(ctx, disabled)}
      />
    );
  };

  const renderPanel = (panel: PanelDef, rows: RowDef[], withFooter: boolean) => (
    <section key={panel.id} className="nz-aset-panel">
      <h4 className="nz-aset-panel__title">
        <Icon name={panel.icon} size={13} strokeWidth={1.7} />
        {q ? <Highlight text={panel.title()} query={query} /> : panel.title()}
      </h4>
      <div className="nz-aset-panel__card">
        {rows.map(renderRow)}
        {withFooter && panel.footer?.(ctx)}
      </div>
    </section>
  );

  const current = TABS.find((x) => x.id === tab) ?? TABS[0];

  return (
    <div className={cx('nz-aset', (dirty || errorCount > 0) && 'has-status')}>
      <div className="nz-aset__toolbar">
        <Tabs<TabId>
          value={q ? ('' as TabId) : tab}
          onChange={pickTab}
          className="nz-aset__tabs"
          items={TABS.map((tb) => ({
            value: tb.id,
            label: tb.label(),
            icon: tb.icon,
            count: tabChanged(tb) || undefined,
          }))}
        />
        <SearchInput value={query} onChange={setQuery} placeholder={t('Search settings')} className="nz-aset__search" />
        {dirty && (
          <Button variant="ghost" icon="refresh" onClick={discard} disabled={saving}>
            {t('Discard')}
          </Button>
        )}
        <Button
          variant="teal"
          icon="save"
          onClick={() => void save()}
          loading={saving}
          disabled={!dirty}
          className={cx('nz-aset__save', dirty && 'is-dirty')}
          title={dirty ? (errorCount ? t('Fix the highlighted settings first') : t('Save changes')) : t('No changes to save')}
        >
          {t('Save')}
        </Button>
      </div>

      <div className="nz-aset__body" key={q ? 'search' : tab}>
        {matches ? (
          matches.length === 0 ? (
            <EmptyState
              className="nz-aset__empty"
              icon="search"
              title={t('No settings match “{query}”', { query: query.trim() })}
              description={t('Try another word, like fee, blips, damage or colour.')}
              action={
                <Button size="sm" onClick={() => setQuery('')}>
                  {t('Clear search')}
                </Button>
              }
            />
          ) : (
            <div className="nz-aset-results">
              {matches.map((m) => (
                <div key={m.tab.id} className="nz-aset-group">
                  <button type="button" className="nz-aset-group__head" onClick={() => pickTab(m.tab.id)}>
                    <Icon name={m.tab.icon} size={14} strokeWidth={1.7} />
                    <b>{m.tab.label()}</b>
                    <span>{t('{n} result(s)', { n: m.panels.reduce((n, p) => n + p.rows.length, 0) })}</span>
                    <em>
                      {t('Open tab')}
                      <Icon name="arrowRight" size={12} strokeWidth={1.8} />
                    </em>
                  </button>
                  <div className="nz-aset-cols">{m.panels.map(({ panel, rows }) => renderPanel(panel, rows, false))}</div>
                </div>
              ))}
            </div>
          )
        ) : (
          <div className="nz-aset-cols">
            {current.columns.map((col, i) => (
              <div key={i} className="nz-aset-col">
                {col.map((panel) => renderPanel(panel, panel.rows, true))}
              </div>
            ))}
          </div>
        )}
      </div>

      {(dirty || errorCount > 0) && (
        <div className={cx('nz-aset__status', errorCount > 0 && 'has-error')} role="status">
          {errorCount > 0 ? (
            <>
              <Icon name="warning" size={13} strokeWidth={1.8} />
              {t('{n} setting(s) need attention before saving', { n: errorCount })}
              {TABS.filter(tabErrors).map((tb) => (
                <button key={tb.id} type="button" onClick={() => pickTab(tb.id)}>
                  {tb.label()}
                </button>
              ))}
            </>
          ) : (
            <>
              <i className="nz-aset__status-dot" />
              {t('{n} unsaved change(s)', { n: changed.size })}
              <span className="nz-aset__status-keys">
                <Kbd>Ctrl</Kbd>
                <Kbd>S</Kbd> {t('to save')}
              </span>
            </>
          )}
        </div>
      )}

      <ConfirmDialog
        open={leave && !shell.hidden}
        tone="red"
        icon="warning"
        title={t('Discard unsaved changes?')}
        message={t('You changed {n} setting(s). Close the admin panel without saving them?', { n: changed.size })}
        confirmLabel={t('Close without saving')}
        cancelLabel={t('Keep editing')}
        onConfirm={() => {
          setLeave(false);
          app.close();
        }}
        onCancel={() => setLeave(false)}
      />
    </div>
  );
}
