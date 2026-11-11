/**
 * The player's key settings (docs/V2_CHANGES.md G.11), a tab of the key ring window:
 * Vehicle (keyless entry, ignition), Key fob (beep, hints, HUD position and size), Interface
 * (key order, combined key ring, ground key prompts, units) and Notifications (alerts, share
 * recall). Search finds a setting in every tab. Loads with keys:settings, saves every change
 * at once (keys:saveSettings, debounced: a slider drag is one save), shows Saving / Saved and
 * rolls back a refused change. What the server switched off (keyless, keep engine running,
 * ground keys) is shown disabled with the reason.
 */
import { useEffect, useMemo, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import { Button, EmptyState, Icon, OptionRow, SearchInput, Segmented, Select, Skeleton, Slider, Tabs, Toggle, cx } from '@/components/ui';
import type { IconName } from '@/components/ui';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import type { PlayerKeySettings, PlayerKeySettingsData } from '@/lib/types';
import { FobGlyph } from './glyphs';
import { orderLabel } from './model';

type Tab = 'vehicle' | 'fob' | 'interface' | 'alerts';

const SAVE_DELAY = 450;

/** Fob HUD spots offered in the select (share of the screen); anything else is "Custom". */
const SPOTS: { value: string; label: () => string; x: number; y: number }[] = [
  { value: 'br', label: () => t('Bottom right'), x: 0.86, y: 0.72 },
  { value: 'bl', label: () => t('Bottom left'), x: 0.14, y: 0.72 },
  { value: 'mr', label: () => t('Middle right'), x: 0.9, y: 0.45 },
  { value: 'tr', label: () => t('Top right'), x: 0.86, y: 0.2 },
  { value: 'tl', label: () => t('Top left'), x: 0.14, y: 0.2 },
];

const spotOf = (p: PlayerKeySettings['fobPosition']) =>
  SPOTS.find((s) => Math.abs(s.x - p.x) < 0.02 && Math.abs(s.y - p.y) < 0.02)?.value ?? 'custom';

interface Row {
  id: string;
  tab: Tab;
  section: string;
  label: string;
  description: string;
  control: ReactNode;
  /** stacked: the control under the text (sliders) */
  stacked?: boolean;
}

export interface SettingsViewProps {
  /** a saved change of the key order / units (the ring uses them at once) */
  onPrefs: (prefs: Pick<PlayerKeySettings, 'keyOrder' | 'units'>) => void;
}

export function SettingsView({ onPrefs }: SettingsViewProps) {
  const [data, setData] = useState<PlayerKeySettingsData | null>(null);
  const [draft, setDraft] = useState<PlayerKeySettings | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [tab, setTab] = useState<Tab>('vehicle');
  const [query, setQuery] = useState('');
  const [saving, setSaving] = useState<'idle' | 'saving' | 'saved' | 'error'>('idle');
  const pending = useRef<Partial<PlayerKeySettings>>({});
  const timer = useRef<number | undefined>(undefined);
  const savedTimer = useRef<number | undefined>(undefined);

  const load = async () => {
    setError(null);
    const res = await request('keys:settings', {}, { toastError: false });
    if (!res.ok || !res.data) {
      setError(res.ok ? t('Something went wrong') : res.error);
      return;
    }
    setData(res.data);
    setDraft(res.data.settings);
  };
  useEffect(() => {
    void load();
    return () => {
      window.clearTimeout(timer.current);
      window.clearTimeout(savedTimer.current);
      // closed right after a change: it is still saved
      if (Object.keys(pending.current).length > 0) {
        void request('keys:saveSettings', { settings: pending.current }, { toastError: true });
        pending.current = {};
      }
    };
  }, []);

  const flush = async () => {
    const partial = pending.current;
    pending.current = {};
    if (Object.keys(partial).length === 0) return;
    setSaving('saving');
    const res = await request('keys:saveSettings', { settings: partial }, { toastError: false });
    if (!res.ok || !res.data) {
      setSaving('error');
      setError(res.ok ? t('Something went wrong') : res.error);
      // roll back to what the server has
      if (data) setDraft(data.settings);
      return;
    }
    setData(res.data);
    setDraft((d) => ({ ...res.data!.settings, ...(d ? pickPending(d, pending.current) : {}) }));
    setError(null);
    setSaving('saved');
    onPrefs({ keyOrder: res.data.settings.keyOrder, units: res.data.settings.units });
    window.clearTimeout(savedTimer.current);
    savedTimer.current = window.setTimeout(() => setSaving('idle'), 1600);
  };

  const set = <K extends keyof PlayerKeySettings>(key: K, value: PlayerKeySettings[K]) => {
    setDraft((d) => (d ? { ...d, [key]: value } : d));
    pending.current = { ...pending.current, [key]: value };
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => void flush(), SAVE_DELAY);
  };

  const restore = () => {
    if (!data || !draft) return;
    const changed: Partial<PlayerKeySettings> = {};
    (Object.keys(data.defaults) as (keyof PlayerKeySettings)[]).forEach((k) => {
      if (JSON.stringify(data.defaults[k]) !== JSON.stringify(draft[k])) (changed as Record<string, unknown>)[k] = data.defaults[k];
    });
    if (Object.keys(changed).length === 0) return;
    setDraft({ ...draft, ...changed });
    pending.current = { ...pending.current, ...changed };
    window.clearTimeout(timer.current);
    void flush();
  };

  const rows = useMemo<Row[]>(() => {
    if (!draft || !data) return [];
    const s = draft;
    const srv = data.server;
    const imperial = s.units === 'imperial';
    const fmtDist = (m: number) => (imperial ? t('{n} ft', { n: Math.round(m * 3.28084) }) : t('{n} m', { n: Math.round(m * 10) / 10 }));
    const keylessOff = !srv.keyless;
    const keylessNote = keylessOff ? ` ${t('(switched off on this server)')}` : '';
    const spot = spotOf(s.fobPosition);
    const list: Row[] = [
      {
        id: 'keylessUnlock',
        tab: 'vehicle',
        section: t('Keyless entry'),
        label: t('Auto-unlock when entering'),
        description: t('With the fob on you, a locked car unlocks as you get in.') + keylessNote,
        control: <Toggle checked={s.keylessUnlock && !keylessOff} disabled={keylessOff} onChange={(v) => set('keylessUnlock', v)} />,
      },
      {
        id: 'keylessLock',
        tab: 'vehicle',
        section: t('Keyless entry'),
        label: t('Auto-lock when walking away'),
        description: t('The car locks itself once you are far enough away.') + keylessNote,
        control: <Toggle checked={s.keylessLock && !keylessOff} disabled={keylessOff} onChange={(v) => set('keylessLock', v)} />,
      },
      {
        id: 'keylessDistance',
        tab: 'vehicle',
        section: t('Keyless entry'),
        label: t('Auto-lock distance'),
        description: t('How far you walk before it locks.'),
        stacked: true,
        control: (
          <Slider
            value={s.keylessDistance}
            min={data.limits.keylessMin}
            max={data.limits.keylessMax}
            step={0.5}
            disabled={keylessOff || !s.keylessLock}
            format={fmtDist}
            onChange={(v) => set('keylessDistance', v)}
          />
        ),
      },
      {
        id: 'engineOnEnter',
        tab: 'vehicle',
        section: t('Ignition'),
        label: t('Start engine when entering'),
        description: t('The engine starts as you sit down with a key.'),
        control: <Toggle checked={s.engineOnEnter} onChange={(v) => set('engineOnEnter', v)} />,
      },
      {
        id: 'keepEngineRunning',
        tab: 'vehicle',
        section: t('Ignition'),
        label: t('Keep engine running on exit'),
        description: srv.keepEngineRunning
          ? t('The engine keeps running when you get out. Hold the exit key to switch it off.')
          : t('Switched off on this server.'),
        control: (
          <Toggle checked={s.keepEngineRunning && srv.keepEngineRunning} disabled={!srv.keepEngineRunning} onChange={(v) => set('keepEngineRunning', v)} />
        ),
      },
      {
        id: 'fobBeep',
        tab: 'fob',
        section: t('Key fob'),
        label: t('Fob beep'),
        description: t('A beep only you hear when you press the fob.'),
        control: <Toggle checked={s.fobBeep} onChange={(v) => set('fobBeep', v)} />,
      },
      {
        id: 'hints',
        tab: 'fob',
        section: t('Key fob'),
        label: t('Fob hints'),
        description: t('Key prompts next to the on-screen fob.'),
        control: <Toggle checked={s.hints} onChange={(v) => set('hints', v)} />,
      },
      {
        id: 'fobPosition',
        tab: 'fob',
        section: t('On-screen fob'),
        label: t('Fob position'),
        description: spot === 'custom' ? t('Placed by hand in the fob edit mode.') : t('Where the fob sits on your screen.'),
        control: (
          <div className="nz-keys-set__select">
            <Select<string>
              size="sm"
              value={spot}
              onChange={(v) => {
                const p = SPOTS.find((x) => x.value === v);
                if (p) set('fobPosition', { ...s.fobPosition, x: p.x, y: p.y });
              }}
              options={[
                ...SPOTS.map((x) => ({ value: x.value, label: x.label() })),
                { value: 'custom', label: t('Custom'), disabled: true },
              ]}
            />
          </div>
        ),
      },
      {
        id: 'fobScale',
        tab: 'fob',
        section: t('On-screen fob'),
        label: t('Fob size'),
        description: t('Size of the on-screen fob.'),
        stacked: true,
        control: (
          <Slider
            value={Math.round(s.fobPosition.scale * 100)}
            min={50}
            max={200}
            step={5}
            suffix="%"
            onChange={(v) => set('fobPosition', { ...s.fobPosition, scale: v / 100 })}
          />
        ),
      },
      {
        id: 'keyOrder',
        tab: 'interface',
        section: t('Key ring'),
        label: t('Key order'),
        description: t('How the key ring sorts your keys.'),
        control: (
          <div className="nz-keys-set__select">
            <Select<PlayerKeySettings['keyOrder']>
              size="sm"
              value={s.keyOrder}
              onChange={(v) => set('keyOrder', v)}
              options={(['recent', 'name', 'plate', 'distance'] as const).map((o) => ({ value: o, label: orderLabel(o) }))}
            />
          </div>
        ),
      },
      {
        id: 'combinedKeyring',
        tab: 'interface',
        section: t('Key ring'),
        label: t('Add new keys to my key ring'),
        description: t('Keys you receive join your key ring instead of staying loose items.'),
        control: <Toggle checked={s.combinedKeyring} onChange={(v) => set('combinedKeyring', v)} />,
      },
      {
        id: 'groundPrompts',
        tab: 'interface',
        section: t('Key ring'),
        label: t('Ground key prompts'),
        description: srv.ground ? t('Show the pick-up prompt at keys on the ground.') : t('Keys on the ground are switched off on this server.'),
        control: <Toggle checked={s.groundPrompts && srv.ground} disabled={!srv.ground} onChange={(v) => set('groundPrompts', v)} />,
      },
      {
        id: 'units',
        tab: 'interface',
        section: t('Key ring'),
        label: t('Distance units'),
        description: t('Metres and kilometres, or feet and miles.'),
        control: (
          <Segmented<PlayerKeySettings['units']>
            size="sm"
            value={s.units}
            onChange={(v) => set('units', v)}
            options={[
              { value: 'metric', label: t('Metres') },
              { value: 'imperial', label: t('Feet / miles') },
            ]}
          />
        ),
      },
      {
        id: 'alertLock',
        tab: 'alerts',
        section: t('Alerts'),
        label: t('Lock alerts'),
        description: t('When a car of yours locks itself behind you.'),
        control: <Toggle checked={s.alertLock} onChange={(v) => set('alertLock', v)} />,
      },
      {
        id: 'alertEngine',
        tab: 'alerts',
        section: t('Alerts'),
        label: t('Engine alerts'),
        description: t('When the engine starts as you get in or from the fob. Never for a manual toggle.'),
        control: <Toggle checked={s.alertEngine} onChange={(v) => set('alertEngine', v)} />,
      },
      {
        id: 'alertShare',
        tab: 'alerts',
        section: t('Alerts'),
        label: t('Sharing alerts'),
        description: t('When someone gives you a key.'),
        control: <Toggle checked={s.alertShare} onChange={(v) => set('alertShare', v)} />,
      },
      {
        id: 'shareRecall',
        tab: 'alerts',
        section: t('Reminders'),
        label: t('Share recall reminder'),
        description: t('When you log in: which of your vehicles still have keys out with other players.'),
        control: <Toggle checked={s.shareRecall} onChange={(v) => set('shareRecall', v)} />,
      },
    ];
    return list;
  }, [draft, data]);

  const tabs: { value: Tab; label: string; icon: IconName }[] = [
    { value: 'vehicle', label: t('Vehicle'), icon: 'car' },
    { value: 'fob', label: t('Key fob'), icon: 'key' },
    { value: 'interface', label: t('Interface'), icon: 'sliders' },
    { value: 'alerts', label: t('Notifications'), icon: 'info' },
  ];
  const q = query.trim().toLowerCase();
  const shown = q ? rows.filter((r) => `${r.label} ${r.description} ${r.section}`.toLowerCase().includes(q)) : rows.filter((r) => r.tab === tab);
  const sections: { key: string; title: string; tab: Tab; rows: Row[] }[] = [];
  for (const r of shown) {
    const key = `${r.tab}|${r.section}`;
    let s = sections.find((x) => x.key === key);
    if (!s) {
      s = { key, title: r.section, tab: r.tab, rows: [] };
      sections.push(s);
    }
    s.rows.push(r);
  }

  return (
    <div className="nz-keys-set">
      <div className="nz-keys-set__bar">
        <Tabs<Tab> value={tab} onChange={(v) => {
          setTab(v);
          setQuery('');
        }} items={tabs} />
        <span className={cx('nz-keys-set__state', `is-${saving}`)} role="status">
          {saving === 'saving' ? t('Saving…') : saving === 'saved' ? (
            <>
              <Icon name="check" size={12} strokeWidth={2.2} />
              {t('Saved')}
            </>
          ) : saving === 'error' ? t('Not saved') : ''}
        </span>
        <div className="nz-keys-set__search">
          <SearchInput value={query} onChange={setQuery} placeholder={t('Search settings')} />
        </div>
      </div>

      {error && (
        <div className="nz-keys-set__error" role="alert">
          <Icon name="warning" size={14} strokeWidth={1.8} />
          <span>{error}</span>
          {!data && (
            <Button size="sm" variant="line" icon="refresh" onClick={() => void load()}>
              {t('Try again')}
            </Button>
          )}
        </div>
      )}

      {!data ? (
        !error && (
          <div className="nz-keys-set__grid">
            {[0, 1].map((i) => (
              <div key={i} className="nz-keys-set__card">
                <Skeleton width={110} height={10} />
                {[0, 1, 2].map((j) => (
                  <div key={j} className="nz-keys-set__skel">
                    <Skeleton width={180} height={11} />
                    <Skeleton width={36} height={20} radius={10} />
                  </div>
                ))}
              </div>
            ))}
          </div>
        )
      ) : sections.length === 0 ? (
        <div className="nz-keys-set__none">
          <EmptyState icon="search" title={t('No setting matches “{query}”', { query: query.trim() })} description={t('Try another word.')} compact />
        </div>
      ) : (
        <div className="nz-keys-set__grid">
          {sections.map((s) => (
            <section key={s.key} className="nz-keys-set__card">
              <h3 className="nz-keys-set__title">
                {s.tab === 'fob' && <FobGlyph size={13} strokeWidth={1.8} />}
                {s.title}
                {q && <small>{tabs.find((x) => x.value === s.tab)?.label}</small>}
              </h3>
              {s.rows.map((r) => (
                <OptionRow key={r.id} label={r.label} description={r.description} control={r.control} stacked={r.stacked} className="nz-keys-set__row" />
              ))}
            </section>
          ))}
        </div>
      )}

      {data && (
        <div className="nz-keys-set__foot">
          <span>{t('Saved on the server for this character.')}</span>
          <Button size="sm" variant="ghost" icon="refresh" onClick={restore}>
            {t('Restore defaults')}
          </Button>
        </div>
      )}
    </div>
  );
}

function pickPending(d: PlayerKeySettings, pending: Partial<PlayerKeySettings>): Partial<PlayerKeySettings> {
  const out: Partial<PlayerKeySettings> = {};
  (Object.keys(pending) as (keyof PlayerKeySettings)[]).forEach((k) => {
    (out as Record<string, unknown>)[k] = d[k];
  });
  return out;
}
