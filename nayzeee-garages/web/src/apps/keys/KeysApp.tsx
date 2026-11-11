/**
 * Key ring app (app 'keys', docs/CARLOCK.md §10, docs/V2_CHANGES.md G.3 / G.5 / G.8 / G.10 /
 * G.11). One window with two tabs:
 * - Keys: a grid of fob renders (search, filters Owned / Shared / Temporary / Items, the
 *   player's key order) and the detail pane of the selected key (KeyDetail): status, the hold
 *   button (tap = lock / unlock via keys:lock, hold = engine, keep holding = windows via
 *   keys:remote), Inspect, Track (TrackModal), Share (ShareModal), Drop / Give back / Access.
 * - Settings: the player's key settings (SettingsView).
 * Lua can also open a dialog on its own (view 'dialog': a key picked up from the ground, the
 * Ghost PIN pad, the give keys picker, track) or push one over the ring (`dialog`).
 * Every action asks Lua -> the server; Lua pushes `live` (what this client sees), `tracking`
 * and fresh data after key changes ('update'). Action results are kept as patches on top of
 * the server data (the temporary key countdowns stay anchored to the moment the data arrived).
 * Keyboard: arrows select, Space / Enter hold the key (tap / hold / keep holding), T track,
 * I inspect, / search, Esc or the key ring keybind (data.closeKey) close.
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ConfirmDialog, EmptyState, Icon, IconButton, KeyHint, Tabs, Window, cx } from '@/components/ui';
import { useApp, useSettings, useUi, toast } from '@/lib/store';
import { useEscape } from '@/lib/escape';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import type { KeyDialog, KeyEntry, KeyGroup, KeyInspectInfo, KeyPinPad, KeyRingPlayer, KeysOpenData, PlayerKeySettings } from '@/lib/types';
import { AccessModal } from './AccessModal';
import type { HoldHandle, HoldStage } from './HoldButton';
import { InspectCard, InspectModal } from './InspectCard';
import { KeyDetail } from './KeyDetail';
import type { Answer } from './KeyDetail';
import { KeyGrid, KeyToolbar } from './KeyGrid';
import { PinPad } from './PinPad';
import { SettingsView } from './SettingsView';
import { ShareModal } from './ShareModal';
import { TrackModal } from './TrackModal';
import { FobGlyph } from './glyphs';
import { GROUPS, displayName, leftNow, matchesQuery, merged, shareInfo, sortKeys, unitOf } from './model';
import type { KeyFilter, KeyOrder, Unit } from './model';
import './keys.css';

export function KeysApp() {
  const { open, data, close } = useApp('keys');
  // a dialog alone handles its own Escape (Modal / InspectCard); the ring closes on Escape
  useEscape(close, open && !!data && data.view !== 'dialog');
  if (!open || !data) return null;
  if (data.view === 'dialog') return <DialogAlone data={data} close={close} />;
  return <KeyRing data={data} close={close} />;
}

const isOpen = () => useUi.getState().apps.keys.open;

/** Does a keydown match the key ring keybind (ox_lib key name: 'F7', 'K', '1'...)? */
const isCloseKey = (e: KeyboardEvent, closeKey: string | null | undefined) =>
  !!closeKey && !e.repeat && e.key.length > 0 && e.key.toUpperCase() === closeKey.toUpperCase();

const useUnit = (data: KeysOpenData, prefsUnits?: PlayerKeySettings['units'] | null): Unit => {
  const settings = useSettings();
  return unitOf(prefsUnits ?? data.prefs?.units, settings.distanceUnit === 'km' ? 'km' : 'mi');
};

/* ── a dialog on its own (no window) ─────────────────────────────────── */

function DialogAlone({ data, close }: { data: KeysOpenData; close: () => void }) {
  const unit = useUnit(data);
  const d = data.dialog;
  // nothing to show: never leave an invisible app holding the focus
  useEffect(() => {
    if (!d) close();
  }, [d, close]);
  if (!d) return null;
  switch (d.kind) {
    case 'inspect':
      return <InspectCard source={d.source} id={d.source === 'ground' ? d.id : undefined} info={d.info} onClose={close} />;
    case 'pin':
      return <PinPad pad={d.pad} onClose={close} />;
    case 'track':
      return <TrackModal plate={d.plate} unit={unit} onClose={close} />;
    case 'give': {
      const k = (data.keys ?? []).map((x) => merged(x, data.live, data.tracking)).find((x) => x.plate === d.plate) ?? null;
      return (
        <ShareModal
          k={k}
          mode={data.mode}
          keyMode={data.keyMode}
          giveRange={data.ranges.give}
          unit={unit}
          onClose={close}
          onDone={(player) => {
            if (k) toast({ type: 'success', message: shareInfo(k, data.mode, data.keyMode).done(player.name, displayName(k)) });
            close();
          }}
        />
      );
    }
    default:
      return null;
  }
}

/* ── the key ring window ─────────────────────────────────────────────── */

type Confirm = { plate: string; action: 'drop' | 'leave' } | null;

function KeyRing({ data, close }: { data: KeysOpenData; close: () => void }) {
  const [tab, setTab] = useState<'keys' | 'settings'>(data.view === 'settings' ? 'settings' : 'keys');
  const [prefs, setPrefs] = useState<{ keyOrder: KeyOrder; units: PlayerKeySettings['units'] | null }>({
    keyOrder: data.prefs?.keyOrder ?? 'recent',
    units: data.prefs?.units ?? null,
  });
  const unit = useUnit(data, prefs.units);
  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState<KeyFilter>('all');
  const [selected, setSelected] = useState<string | null>(data.focus ?? null);
  const [now, setNow] = useState(() => Date.now());
  const [busy, setBusy] = useState<string | null>(null);
  const [answers, setAnswers] = useState<Record<string, Answer>>({});
  const [cooldowns, setCooldowns] = useState<Record<string, number>>({});
  const [stage, setStage] = useState<{ plate: string; stage: HoldStage } | null>(null);
  const [windowsDown, setWindowsDown] = useState<Record<string, boolean>>({});
  const [refreshing, setRefreshing] = useState(false);
  // modals of the ring
  const [track, setTrack] = useState<string | null>(null);
  const [sharing, setSharing] = useState<string | null>(null);
  const [access, setAccess] = useState<string | null>(null);
  const [inspect, setInspect] = useState<{ info: KeyInspectInfo; plate: string } | null>(null);
  const [confirm, setConfirm] = useState<Confirm>(null);
  const [confirmBusy, setConfirmBusy] = useState(false);
  const [pin, setPin] = useState<KeyPinPad | null>(null);
  // what the last actions changed (lock state, engine...), on top of the server data
  const [patches, setPatches] = useState<Record<string, Partial<KeyEntry>>>({});
  const holdRef = useRef<HoldHandle>(null);
  const bodyRef = useRef<HTMLDivElement>(null);

  const receivedAt = useMemo(() => Date.now(), [data.keys]);
  useEffect(() => setPatches({}), [data.keys]);
  const patchKey = (plate: string, patch: Partial<KeyEntry>) => setPatches((p) => ({ ...p, [plate]: { ...p[plate], ...patch } }));

  // a key asked for by Lua (fob used, OpenKeys(plate))
  useEffect(() => {
    if (data.focus) {
      setSelected(data.focus);
      setFilter('all');
      setQuery('');
      setTab('keys');
    }
  }, [data.focus]);
  useEffect(() => {
    if (data.view === 'settings') setTab('settings');
  }, [data.view]);
  useEffect(() => {
    if (data.prefs) setPrefs({ keyOrder: data.prefs.keyOrder, units: data.prefs.units });
  }, [data.prefs?.keyOrder, data.prefs?.units]);

  /* ── merge, filter, sort ── */
  const keys = useMemo(
    () =>
      (Array.isArray(data.keys) ? data.keys : []).map((k) =>
        merged(patches[k.plate] ? { ...k, ...patches[k.plate] } : k, data.live, data.tracking),
      ),
    [data.keys, data.live, data.tracking, patches],
  );
  const hasTemp = keys.some((k) => k.kind === 'temp' && k.expiresIn !== null);
  const anyCooldown = Object.values(cooldowns).some((until) => until > now);
  useEffect(() => {
    if (!hasTemp && !anyCooldown) return;
    const id = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(id);
  }, [hasTemp, anyCooldown]);

  const searched = useMemo(() => keys.filter((k) => matchesQuery(k, query)), [keys, query]);
  const present = useMemo(() => GROUPS.filter((g) => keys.some((k) => k.group === g)), [keys]);
  const counts = useMemo(() => {
    const c: Record<KeyFilter, number> = { all: searched.length, owned: 0, shared: 0, temp: 0, items: 0 };
    for (const k of searched) c[k.group]++;
    return c;
  }, [searched]);
  const activeFilter: KeyFilter = filter === 'all' || present.includes(filter as KeyGroup) ? filter : 'all';
  const list = useMemo(
    () => sortKeys(searched.filter((k) => activeFilter === 'all' || k.group === activeFilter), prefs.keyOrder),
    [searched, activeFilter, prefs.keyOrder],
  );
  const current = selected && list.some((x) => x.plate === selected) ? selected : (list[0]?.plate ?? null);
  const k = current ? (keys.find((x) => x.plate === current) ?? null) : null;
  const leftOf = useCallback((x: KeyEntry) => leftNow(x, receivedAt, now), [receivedAt, now]);

  // a hold never continues on another key
  useEffect(() => {
    holdRef.current?.cancel();
  }, [current]);

  /* ── answers ── */
  const say = (plate: string, tone: Answer['tone'], title: string, text: string) => {
    setAnswers((a) => ({ ...a, [plate]: { tone, title, text, at: Date.now() } }));
  };

  /* ── actions ── */
  const lock = async (key: KeyEntry) => {
    if (busy) return;
    setBusy(key.plate);
    const res = await request('keys:lock', { plate: key.plate }, { toastError: false });
    setBusy(null);
    if (!res.ok) return say(key.plate, 'red', t('Refused.'), res.error);
    if (res.data?.refused === 'range') {
      return say(key.plate, 'amber', t('Out of range.'), res.data.message || t('The vehicle is too far away'));
    }
    const plate = res.data?.plate ?? key.plate;
    const locked = res.data?.locked === true;
    patchKey(plate, { locked, usedAt: Math.floor(Date.now() / 1000) });
    say(plate, 'teal', locked ? t('Locked.') : t('Unlocked.'), displayName(keys.find((x) => x.plate === plate) ?? key));
  };

  const remote = async (key: KeyEntry, action: 'engine' | 'windows') => {
    if (busy) return;
    const on = action === 'engine' ? key.engine !== true : !windowsDown[key.plate];
    setBusy(key.plate);
    const res = await request('keys:remote', { plate: key.plate, action, on }, { toastError: false });
    setBusy(null);
    if (!res.ok) return say(key.plate, 'red', action === 'engine' ? t('Engine.') : t('Windows.'), res.error);
    if (res.data?.refused === 'range') {
      return say(key.plate, 'amber', t('Out of range.'), res.data.message || t('The vehicle is too far away'));
    }
    const done = res.data?.on ?? on;
    if (action === 'engine') {
      patchKey(key.plate, { engine: done, usedAt: Math.floor(Date.now() / 1000) });
      say(key.plate, 'teal', done ? t('Engine started.') : t('Engine stopped.'), t('From the fob.'));
    } else {
      setWindowsDown((w) => ({ ...w, [key.plate]: done }));
      say(key.plate, 'teal', done ? t('Windows down.') : t('Windows up.'), t('Hold again to roll them back.'));
    }
  };

  const openInspect = async (key: KeyEntry) => {
    if (busy) return;
    if (key.slot != null || key.keyId) {
      setBusy(key.plate);
      const res = await request('keys:inspect', { plate: key.plate }, { toastError: false });
      setBusy(null);
      if (!res.ok || !res.data) return say(key.plate, 'red', t('Inspect.'), res.ok ? t('Something went wrong') : res.error);
      setInspect({ info: res.data, plate: key.plate });
      return;
    }
    // a key that is no item: what the ring knows about it
    setInspect({
      plate: key.plate,
      info: {
        plate: key.plate,
        keyKind: key.keyType,
        keyLabel:
          key.kind === 'temp'
            ? t('Temporary key')
            : key.kind === 'owner'
              ? key.isOwner
                ? t('Owner access')
                : t('Shared access')
              : t('Virtual key'),
        model: key.model || null,
        hash: key.hash,
        design: key.design ?? 'classic',
        kind: 'item',
        valid: null,
        origin: key.reason,
        label: key.label,
        make: key.make,
        image: key.image,
      },
    });
  };

  const waypoint = async (key: KeyEntry) => {
    const res = await request('keys:locate', { plate: key.plate }, { toastError: false });
    if (!res.ok) return say(key.plate, 'red', t('Tracker.'), res.error);
    say(key.plate, 'teal', t('Waypoint set.'), t('The blip follows {vehicle} for a while.', { vehicle: displayName(key) }));
  };

  const alarm = async (key: KeyEntry) => {
    if (busy) return;
    setBusy(key.plate);
    const res = await request('keys:alarm', { plate: key.plate }, { toastError: false });
    setBusy(null);
    if (!res.ok) return say(key.plate, 'red', t('Alarm.'), res.error);
    if (res.data?.refused === 'cooldown') {
      const left = Math.max(0, Number(res.data.cooldown) || 0);
      if (left > 0) setCooldowns((c) => ({ ...c, [key.plate]: Date.now() + left * 1000 }));
      return say(key.plate, 'amber', t('Not yet.'), res.data.message || t('Alarm ready again in {s}s', { s: left }));
    }
    const on = res.data?.alarm === true;
    patchKey(key.plate, { alarm: on });
    const cd = res.data?.cooldown ?? 0;
    if (cd > 0) setCooldowns((c) => ({ ...c, [key.plate]: Date.now() + cd * 1000 }));
    say(key.plate, 'teal', t('Alarm.'), on ? t('Sounding for {s} s.', { s: res.data?.seconds ?? 0 }) : t('Silenced.'));
  };

  const openPin = async (key: KeyEntry) => {
    const res = await request('keys:immobiliser', { plate: key.plate }, { toastError: false });
    if (!res.ok || !res.data) return say(key.plate, 'red', t('Ghost PIN.'), res.ok ? t('Something went wrong') : res.error);
    setPin({ id: 0, mode: 'set', plate: key.plate, vehicle: displayName(key), pinSet: res.data.pinSet, length: 4 });
  };

  const refresh = async () => {
    if (refreshing) return;
    setRefreshing(true);
    const res = await request('keys:refresh', {});
    setRefreshing(false);
    if (res.ok && res.data && isOpen()) useUi.getState().updateApp('keys', { ...res.data, focus: null, view: null, dialog: null });
  };

  const shared = (player: KeyRingPlayer) => {
    const key = keys.find((x) => x.plate === sharing);
    setSharing(null);
    if (!key) return;
    toast({ type: 'success', message: shareInfo(key, data.mode, data.keyMode).done(player.name, displayName(key)) });
    void refresh();
  };

  const runConfirm = async () => {
    if (!confirm || confirmBusy) return;
    const key = keys.find((x) => x.plate === confirm.plate);
    setConfirmBusy(true);
    const res =
      confirm.action === 'drop'
        ? await request('keys:drop', { plate: confirm.plate }, { toastError: false })
        : await request('keys:leave', { plate: confirm.plate }, { toastError: false });
    setConfirmBusy(false);
    setConfirm(null);
    if (!res.ok) return say(confirm.plate, 'red', confirm.action === 'drop' ? t('Drop.') : t('Give back.'), res.error);
    toast({
      type: 'success',
      message:
        confirm.action === 'drop'
          ? t('You dropped the key of {vehicle}.', { vehicle: key ? displayName(key) : confirm.plate })
          : t('You gave back the key of {vehicle}.', { vehicle: key ? displayName(key) : confirm.plate }),
    });
    void refresh();
  };

  const saveOrder = (o: KeyOrder) => {
    setPrefs((p) => ({ ...p, keyOrder: o }));
    void request('keys:saveSettings', { settings: { keyOrder: o } }, { toastError: true });
  };

  /* ── a dialog Lua pushed over the ring ── */
  const luaDialog: KeyDialog | null = data.dialog ?? null;
  const clearLuaDialog = () => {
    if (isOpen()) useUi.getState().updateApp('keys', { dialog: null });
  };
  const luaPin = luaDialog?.kind === 'pin' ? luaDialog.pad : null;
  const luaGive = luaDialog?.kind === 'give' ? luaDialog.plate : null;
  const luaTrack = luaDialog?.kind === 'track' ? luaDialog.plate : null;
  const luaInspect = luaDialog?.kind === 'inspect' ? luaDialog : null;

  /* ── keyboard ── */
  const modalOpen = !!(track || sharing || access || inspect || confirm || pin || luaDialog);
  const kRef = useRef(k);
  kRef.current = k;
  useEffect(() => {
    if (modalOpen || tab !== 'keys') return;
    const onKey = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement | null;
      const typing = !!target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA');
      if (isCloseKey(e, data.closeKey) && (!typing || e.key.length > 1)) {
        e.preventDefault();
        close();
        return;
      }
      if (e.key.startsWith('Arrow')) {
        if (typing && (e.key === 'ArrowLeft' || e.key === 'ArrowRight')) return;
        if (!list.length) return;
        e.preventDefault();
        const i = current ? list.findIndex((x) => x.plate === current) : -1;
        const grid = bodyRef.current?.querySelector<HTMLElement>('.nz-keys__grid');
        const cols = grid ? Math.max(1, getComputedStyle(grid).gridTemplateColumns.split(' ').filter(Boolean).length) : 1;
        const step = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : e.key === 'ArrowDown' ? cols : -cols;
        const next = Math.max(0, Math.min(list.length - 1, i + step));
        setSelected(list[next].plate);
        return;
      }
      if (typing) {
        if (e.key === 'Enter') target!.blur();
        return;
      }
      // a focused control (a chip, an action) does what it says: Space / Enter click it
      const onControl = !!target?.closest('button:not([role="radio"]), a, [role="switch"], [role="tab"], [role="menuitem"]');
      if ((e.key === ' ' || e.key === 'Enter') && !onControl) {
        e.preventDefault();
        if (!e.repeat) holdRef.current?.press();
      } else if ((e.key === 't' || e.key === 'T') && kRef.current && !e.repeat) {
        const x = kRef.current;
        if (data.tracker && x.tracker && x.trackerAccess) {
          e.preventDefault();
          setTrack(x.plate);
        }
      } else if ((e.key === 'i' || e.key === 'I') && kRef.current && !e.repeat) {
        e.preventDefault();
        void openInspect(kRef.current);
      } else if (e.key === '/') {
        e.preventDefault();
        bodyRef.current?.querySelector<HTMLInputElement>('.nz-keys__search input')?.focus();
      }
    };
    const onUp = (e: KeyboardEvent) => {
      if (e.key === ' ' || e.key === 'Enter') holdRef.current?.release();
    };
    window.addEventListener('keydown', onKey);
    window.addEventListener('keyup', onUp);
    return () => {
      window.removeEventListener('keydown', onKey);
      window.removeEventListener('keyup', onUp);
      holdRef.current?.cancel();
    };
  }, [modalOpen, tab, list, current, data.closeKey, data.tracker, close]);

  /* ── header / footer ── */
  const total = keys.length;
  const outCount = keys.filter((x) => x.spawned).length;
  const virtual = data.mode === 'virtual';
  const filtered = query.trim() !== '' || activeFilter !== 'all';
  const shareKey = sharing ? (keys.find((x) => x.plate === sharing) ?? null) : luaGive ? (keys.find((x) => x.plate === luaGive) ?? null) : null;
  const accessKey = access ? (keys.find((x) => x.plate === access) ?? null) : null;
  const confirmKey = confirm ? (keys.find((x) => x.plate === confirm.plate) ?? null) : null;
  const trackPlate = track ?? luaTrack;
  const trackKey = trackPlate ? (keys.find((x) => x.plate === trackPlate) ?? null) : null;

  const headerExtra = (
    <>
      <Tabs<'keys' | 'settings'>
        value={tab}
        onChange={setTab}
        items={[
          { value: 'keys', label: t('Keys'), icon: 'key', count: total },
          { value: 'settings', label: t('Settings'), icon: 'cog' },
        ]}
        className="nz-keys__tabs"
      />
      <span className={cx('nz-keys__modepill', virtual ? 'is-virtual' : 'is-physical')} title={virtual ? t('Keys live on the server') : t('Keys are items in your inventory')}>
        {virtual ? <Icon name="link" size={12} strokeWidth={1.9} /> : <FobGlyph size={13} strokeWidth={1.8} />}
        {virtual ? t('Virtual keys') : data.keyMode === 'limited' ? t('Limited keys') : t('Key items')}
      </span>
      <IconButton icon="refresh" label={t('Refresh')} variant="ghost" size="sm" onClick={() => void refresh()} disabled={refreshing} />
    </>
  );

  return (
    <>
      <Window
        className="nz-keys"
        bodyClassName="nz-keys__body"
        width="min(1280px, 95vw)"
        height="min(860px, 93vh)"
        title={t('Key ring')}
        icon="key"
        headerExtra={headerExtra}
        onClose={close}
        footer={
          tab === 'keys' ? (
            <>
              <span>
                <b>{total}</b> {t('key(s)')}
                {outCount > 0 && (
                  <>
                    {' · '}
                    <b>{outCount}</b> {t('out')}
                  </>
                )}
                {filtered && total > 0 && (
                  <>
                    {' · '}
                    <button
                      type="button"
                      className="nz-keys__clear"
                      onClick={() => {
                        setQuery('');
                        setFilter('all');
                      }}
                    >
                      {t('showing {count} · clear filters', { count: list.length })}
                    </button>
                  </>
                )}
              </span>
              <span className="nz-keys__spacer" />
              {list.length > 1 && <KeyHint keys={['←', '→']} label={t('Select')} />}
              {k && <KeyHint keys={['Space']} label={t('Tap · hold')} />}
              {k && data.tracker && k.tracker && k.trackerAccess && <KeyHint keys={['T']} label={t('Track')} />}
              {total > 0 && <KeyHint keys={['/']} label={t('Search')} />}
              <KeyHint keys={data.closeKey && data.closeKey.toUpperCase() !== 'ESC' ? ['Esc', data.closeKey] : ['Esc']} label={t('Close')} />
            </>
          ) : (
            <>
              <span>{t('Your key settings')}</span>
              <span className="nz-keys__spacer" />
              <KeyHint keys={['Esc']} label={t('Close')} />
            </>
          )
        }
      >
        <div ref={bodyRef} className={cx('nz-keys__layout', tab === 'settings' && 'is-settings')}>
          {tab === 'settings' ? (
            <SettingsView onPrefs={(p) => setPrefs({ keyOrder: p.keyOrder, units: p.units })} />
          ) : (
            <>
              <section className="nz-keys__main" aria-label={t('Your keys')}>
                {total > 0 && (
                  <KeyToolbar
                    query={query}
                    onQuery={setQuery}
                    filter={activeFilter}
                    onFilter={setFilter}
                    counts={counts}
                    present={present}
                    order={prefs.keyOrder}
                    onOrder={saveOrder}
                  />
                )}
                {total === 0 ? (
                  <EmptyRing virtual={virtual} />
                ) : list.length === 0 ? (
                  <div className="nz-keys__nomatch">
                    <EmptyState
                      icon="search"
                      title={query.trim() ? t('No keys match “{query}”', { query: query.trim() }) : t('No keys match')}
                      description={t('Try a plate, a nickname or a model.')}
                    />
                  </div>
                ) : (
                  <KeyGrid
                    keys={list}
                    selected={current}
                    onSelect={setSelected}
                    onActivate={(plate) => {
                      const x = keys.find((y) => y.plate === plate);
                      if (x && x.spawned && !x.towing) void lock(x);
                    }}
                    leftOf={leftOf}
                    unit={unit}
                    pressed={stage && stage.stage === 'tap' && k ? { plate: stage.plate, button: k.locked === true ? 'unlock' : 'lock' } : null}
                  />
                )}
              </section>
              <aside className="nz-keys__side">
                {k ? (
                  <KeyDetail
                    k={k}
                    data={data}
                    left={leftOf(k)}
                    unit={unit}
                    busy={busy === k.plate}
                    answer={answers[k.plate] ?? null}
                    stage={stage && stage.plate === k.plate ? stage.stage : 'idle'}
                    holdRef={holdRef}
                    alarmCooldown={Math.max(0, Math.ceil(((cooldowns[k.plate] ?? 0) - now) / 1000))}
                    onStage={(s) => setStage(s === 'idle' ? null : { plate: k.plate, stage: s })}
                    onTap={() => void lock(k)}
                    onEngine={() => void remote(k, 'engine')}
                    onWindows={() => void remote(k, 'windows')}
                    onInspect={() => void openInspect(k)}
                    onTrack={() => setTrack(k.plate)}
                    onShare={() => setSharing(k.plate)}
                    onSide={(a) => (a === 'access' ? setAccess(k.plate) : setConfirm({ plate: k.plate, action: a }))}
                    onWaypoint={() => void waypoint(k)}
                    onAlarm={() => void alarm(k)}
                    onPin={() => void openPin(k)}
                  />
                ) : (
                  <div className="nz-keys__sideempty">
                    <Icon name="key" size={22} strokeWidth={1.4} />
                    <span>{total === 0 ? t('No key selected') : t('Pick a key')}</span>
                  </div>
                )}
              </aside>
            </>
          )}
        </div>
      </Window>

      <TrackModal plate={trackPlate} title={trackKey ? displayName(trackKey) : null} unit={unit} onClose={() => (track ? setTrack(null) : clearLuaDialog())} />
      <ShareModal
        k={shareKey}
        mode={data.mode}
        keyMode={data.keyMode}
        giveRange={data.ranges.give}
        unit={unit}
        onClose={() => (sharing ? setSharing(null) : clearLuaDialog())}
        onDone={(player) => {
          if (luaGive && !sharing) clearLuaDialog();
          shared(player);
        }}
      />
      <AccessModal k={accessKey} onClose={() => setAccess(null)} onCount={(plate, n) => patchKey(plate, { holders: n })} />
      <InspectModal
        info={inspect?.info ?? (luaInspect ? luaInspect.info : null)}
        entry={inspect ? keys.find((x) => x.plate === inspect.plate) : null}
        onClose={() => (inspect ? setInspect(null) : clearLuaDialog())}
      />
      <PinPad
        pad={pin ?? luaPin}
        onClose={() => {
          if (pin) setPin(null);
          else clearLuaDialog();
        }}
      />
      <ConfirmDialog
        open={!!confirm}
        tone="red"
        icon={confirm?.action === 'drop' ? 'arrowRight' : 'logout'}
        title={confirm?.action === 'drop' ? t('Drop this key?') : t('Give this key back?')}
        message={
          confirmKey
            ? confirm?.action === 'drop'
              ? t('The key of {vehicle} lands at your feet. Anyone can pick it up.', { vehicle: displayName(confirmKey) })
              : t('You can no longer lock, unlock or start {vehicle}. The owner can give you a key again.', { vehicle: displayName(confirmKey) })
            : ''
        }
        confirmLabel={confirm?.action === 'drop' ? t('Drop key') : t('Give back')}
        busy={confirmBusy}
        onConfirm={() => void runConfirm()}
        onCancel={() => setConfirm(null)}
      />
    </>
  );
}

/* ── empty key ring ──────────────────────────────────────────────────── */

function EmptyRing({ virtual }: { virtual: boolean }) {
  const steps = [
    { icon: 'garage' as const, text: t('Take one of your vehicles out of a garage: its key lands on your ring.') },
    {
      icon: 'key' as const,
      text: virtual ? t('Owners can give you a key from their key ring.') : t('A locksmith cuts spare keys and fobs for your vehicles.'),
    },
    {
      icon: 'userPlus' as const,
      text: virtual ? t('Keys someone gave you stay until they take them back.') : t('Someone can hand you their key item.'),
    },
  ];
  return (
    <div className="nz-keys__empty">
      <div className="nz-keys__empty-ring" aria-hidden="true">
        <span className="nz-keys__empty-loop" />
        <Icon name="key" size={26} strokeWidth={1.4} />
      </div>
      <b className="nz-keys__empty-title">{t('Your key ring is empty')}</b>
      <span className="nz-keys__empty-text">{t('Keys of the vehicles you can open and start show up here.')}</span>
      <div className="nz-keys__steps">
        {steps.map((s, i) => (
          <div key={i} className="nz-keys__step">
            <span className="nz-keys__step-n">{i + 1}</span>
            <Icon name={s.icon} size={15} strokeWidth={1.7} />
            <span>{s.text}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
