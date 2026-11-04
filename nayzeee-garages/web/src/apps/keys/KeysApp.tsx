/**
 * Key ring app (app 'keys', docs/CARLOCK.md §10). Two panes like the garage Showroom:
 * left the keys grouped Owned · Shared with you · Temporary · Key items (kind badge, plate,
 * lock state and distance of vehicles that are out), right the selected key (KeyShow):
 * stage, status strip, remote range gauge with the server's answer, tracker, key details,
 * key holders (owner, virtual mode) and the dock: Lock / Unlock, Locate, Alarm, Share.
 * Every action asks Lua -> the server (keys:*); Lua pushes `live` (what this client sees),
 * `tracking` (the located vehicle) and fresh data after key changes ('update').
 * Keyboard: ↑ ↓ select, Enter lock / unlock, L locate, / search, Esc close.
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ConfirmDialog, EmptyState, Icon, IconButton, KeyHint, Window, cx } from '@/components/ui';
import { useApp, useSettings, useUi, toast } from '@/lib/store';
import { useEscape } from '@/lib/escape';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import type { KeyEntry, KeyGroup, KeyHolder, KeyRingPlayer, KeysOpenData } from '@/lib/types';
import { KeyList, KeyToolbar } from './KeyRail';
import type { RailGroup } from './KeyRail';
import { KeyShow } from './KeyShow';
import type { Answer, HolderState } from './KeyShow';
import { ShareModal } from './ShareModal';
import { FobGlyph } from './glyphs';
import { GROUPS, displayName, leftNow, matchesQuery, merged, sortKeys } from './model';
import type { KeyFilter } from './model';
import './keys.css';

export function KeysApp() {
  const { open, data, close } = useApp('keys');
  useEscape(close, open);
  if (!open || !data) return null;
  return <KeyRing data={data} close={close} />;
}

const patchKey = (plate: string, patch: Partial<KeyEntry>) => {
  const d = useUi.getState().apps.keys.data;
  if (!d || !Array.isArray(d.keys)) return;
  useUi.getState().updateApp('keys', { keys: d.keys.map((k) => (k.plate === plate ? { ...k, ...patch } : k)) });
};

const isOpen = () => useUi.getState().apps.keys.open;

function KeyRing({ data, close }: { data: KeysOpenData; close: () => void }) {
  const settings = useSettings();
  const unit = settings.distanceUnit;
  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState<KeyFilter>('all');
  const [selected, setSelected] = useState<string | null>(data.focus ?? null);
  const [now, setNow] = useState(() => Date.now());
  const [busy, setBusy] = useState<{ lock: string | null; locate: string | null; alarm: string | null }>({
    lock: null,
    locate: null,
    alarm: null,
  });
  const [answers, setAnswers] = useState<Record<string, Answer>>({});
  const [locating, setLocating] = useState<string | null>(null);
  const [cooldowns, setCooldowns] = useState<Record<string, number>>({});
  const [holders, setHolders] = useState<Record<string, HolderState>>({});
  const [holdersAt, setHoldersAt] = useState<Record<string, number>>({});
  const [sharing, setSharing] = useState<string | null>(null);
  const [revoke, setRevoke] = useState<{ plate: string; holder: KeyHolder } | null>(null);
  const [revoking, setRevoking] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const bodyRef = useRef<HTMLDivElement>(null);

  // Temporary keys count down from the moment their data arrived (server clock independent).
  const receivedAt = useMemo(() => Date.now(), [data.keys]);

  // a key asked for by Lua (fob used, OpenKeys(plate))
  useEffect(() => {
    if (data.focus) {
      setSelected(data.focus);
      setFilter('all');
      setQuery('');
    }
  }, [data.focus]);

  // the tracker stops / loses the located vehicle
  useEffect(() => {
    const tr = data.tracking;
    if (tr && (tr.lost || tr.stopped) && locating === tr.plate) {
      setLocating(null);
      if (tr.lost) {
        setAnswers((a) => ({
          ...a,
          [tr.plate]: {
            tone: 'amber',
            title: t('Signal lost'),
            text: tr.towing ? t('The tracker lost the vehicle: it is being towed.') : t('The tracker lost the vehicle.'),
            at: Date.now(),
          },
        }));
      }
    }
  }, [data.tracking, locating]);

  // located by the key ring (this window) or still followed by the tracker (Lua's readout)
  const followed = data.tracking && !data.tracking.lost && !data.tracking.stopped ? data.tracking.plate : null;
  const locatingPlate = locating ?? followed;

  /* ── merge live data, filter, group ── */
  const keys = useMemo(
    () => (Array.isArray(data.keys) ? data.keys : []).map((k) => merged(k, data.live, data.tracking)),
    [data.keys, data.live, data.tracking],
  );
  const hasTemp = keys.some((k) => k.kind === 'temp' && k.expiresIn !== null);
  const anyCooldown = Object.values(cooldowns).some((until) => until > now);

  useEffect(() => {
    if (!hasTemp && !anyCooldown && Object.keys(answers).length === 0) return;
    const id = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(id);
  }, [hasTemp, anyCooldown, answers]);

  const searched = useMemo(() => keys.filter((k) => matchesQuery(k, query)), [keys, query]);
  const present = useMemo(() => GROUPS.filter((g) => keys.some((k) => k.group === g)), [keys]);
  const counts = useMemo(() => {
    const c: Record<KeyFilter, number> = { all: searched.length, owned: 0, shared: 0, temp: 0, items: 0 };
    for (const k of searched) c[k.group]++;
    return c;
  }, [searched]);
  const activeFilter: KeyFilter = filter === 'all' || present.includes(filter as KeyGroup) ? filter : 'all';
  const groups: RailGroup[] = useMemo(
    () =>
      GROUPS.map((g) => ({
        key: g,
        items: sortKeys(searched.filter((k) => k.group === g && (activeFilter === 'all' || activeFilter === g))),
      })).filter((g) => g.items.length > 0),
    [searched, activeFilter],
  );
  const flat = useMemo(() => groups.flatMap((g) => g.items.map((k) => k.plate)), [groups]);
  const current = selected && flat.includes(selected) ? selected : (flat[0] ?? null);
  const k = current ? (keys.find((x) => x.plate === current) ?? null) : null;
  const leftOf = useCallback((x: KeyEntry) => leftNow(x, receivedAt, now), [receivedAt, now]);

  /* ── holders of the selected key (owner, virtual mode) ── */
  const loadHolders = useCallback(async (plate: string) => {
    setHolders((h) => ({ ...h, [plate]: 'loading' }));
    const res = await request('keys:holders', { plate }, { toastError: false });
    setHolders((h) => ({ ...h, [plate]: res.ok ? (Array.isArray(res.data) ? res.data : []) : 'error' }));
    setHoldersAt((h) => ({ ...h, [plate]: Date.now() }));
  }, []);
  const wantHolders = !!k && data.mode === 'virtual' && k.isOwner;
  useEffect(() => {
    if (wantHolders && k && holders[k.plate] === undefined) void loadHolders(k.plate);
  }, [wantHolders, k, holders, loadHolders]);

  /* ── actions ── */
  const say = (plate: string, tone: Answer['tone'], title: string, text: string) =>
    setAnswers((a) => ({ ...a, [plate]: { tone, title, text, at: Date.now() } }));

  const lock = async (key: KeyEntry) => {
    if (busy.lock) return;
    setBusy((b) => ({ ...b, lock: key.plate }));
    const res = await request('keys:lock', { plate: key.plate }, { toastError: false });
    setBusy((b) => ({ ...b, lock: null }));
    if (!res.ok) {
      // the server's own (translated) words for "out of range"
      const far = res.error === t('The vehicle is too far away');
      say(key.plate, far ? 'amber' : 'red', far ? t('Out of range') : t('Refused'), res.error);
      return;
    }
    const plate = res.data?.plate ?? key.plate;
    const locked = res.data?.locked === true;
    patchKey(plate, { locked });
    say(
      plate,
      'teal',
      locked ? t('Locked') : t('Unlocked'),
      locked ? t('{vehicle} is locked.', { vehicle: displayName(key) }) : t('{vehicle} is unlocked.', { vehicle: displayName(key) }),
    );
  };

  const locate = async (key: KeyEntry) => {
    if (busy.locate) return;
    setBusy((b) => ({ ...b, locate: key.plate }));
    const res = await request('keys:locate', { plate: key.plate }, { toastError: false });
    setBusy((b) => ({ ...b, locate: null }));
    if (!res.ok) {
      say(key.plate, 'red', t('Tracker'), res.error);
      return;
    }
    setLocating(key.plate);
    if (res.data && res.data.distance !== null && res.data.distance !== undefined) patchKey(key.plate, { distance: res.data.distance });
    toast({ type: 'success', message: t('Waypoint set to {vehicle}.', { vehicle: displayName(key) }) });
  };

  const stopLocate = async (key: KeyEntry) => {
    setLocating(null);
    await request('keys:locate', { plate: key.plate, stop: true }, { toastError: false });
  };

  const alarm = async (key: KeyEntry) => {
    if (busy.alarm) return;
    setBusy((b) => ({ ...b, alarm: key.plate }));
    const res = await request('keys:alarm', { plate: key.plate }, { toastError: false });
    setBusy((b) => ({ ...b, alarm: null }));
    if (!res.ok) {
      const m = res.error.match(/(\d+)\s*s\b/);
      if (m) setCooldowns((c) => ({ ...c, [key.plate]: Date.now() + Number(m[1]) * 1000 }));
      say(key.plate, 'amber', m ? t('Not yet') : t('Alarm'), res.error);
      return;
    }
    const on = res.data?.alarm === true;
    patchKey(key.plate, { alarm: on });
    const cd = res.data?.cooldown ?? 0;
    if (cd > 0) setCooldowns((c) => ({ ...c, [key.plate]: Date.now() + cd * 1000 }));
    say(key.plate, 'teal', t('Alarm'), on ? t('Alarm sounding for {s} s.', { s: res.data?.seconds ?? 0 }) : t('Alarm silenced.'));
  };

  const refresh = async () => {
    if (refreshing) return;
    setRefreshing(true);
    const res = await request('keys:refresh', {});
    setRefreshing(false);
    if (res.ok && res.data && isOpen()) {
      useUi.getState().updateApp('keys', { ...res.data, focus: null });
      setHolders({});
    }
  };

  const shared = (player: KeyRingPlayer) => {
    const key = keys.find((x) => x.plate === sharing);
    setSharing(null);
    if (!key) return;
    toast({
      type: 'success',
      message:
        data.mode === 'virtual'
          ? t('{name} has a key of {vehicle} now.', { name: player.name, vehicle: displayName(key) })
          : t('You handed the key of {vehicle} to {name}.', { name: player.name, vehicle: displayName(key) }),
    });
    setHolders((h) => ({ ...h, [key.plate]: undefined }));
    void refresh();
  };

  const confirmRevoke = async () => {
    if (!revoke || revoking) return;
    const { plate, holder } = revoke;
    setRevoking(holder.identifier);
    const res = await request('keys:revoke', { plate, identifier: holder.identifier });
    setRevoking(null);
    setRevoke(null);
    if (!res.ok) return;
    if (Array.isArray(res.data)) {
      setHolders((h) => ({ ...h, [plate]: res.data as KeyHolder[] }));
      setHoldersAt((h) => ({ ...h, [plate]: Date.now() }));
    } else {
      void loadHolders(plate);
    }
    toast({ type: 'success', message: t('{name} no longer has a key.', { name: holder.name }) });
  };

  /* ── keyboard ── */
  const modalOpen = !!sharing || !!revoke;
  useEffect(() => {
    if (modalOpen) return;
    const onKey = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement | null;
      const typing = !!target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA');
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        if (!flat.length) return;
        e.preventDefault();
        const i = current ? flat.indexOf(current) : -1;
        const next = Math.max(0, Math.min(flat.length - 1, i + (e.key === 'ArrowDown' ? 1 : -1)));
        setSelected(flat[next]);
        return;
      }
      if (typing) {
        if (e.key === 'Enter' && k) (target as HTMLInputElement).blur();
        return;
      }
      if (e.key === 'Enter' && k) {
        e.preventDefault();
        if (canLockNow(k)) void lock(k);
      } else if ((e.key === 'l' || e.key === 'L') && k?.trackable) {
        e.preventDefault();
        if (locatingPlate === k.plate) void stopLocate(k);
        else void locate(k);
      } else if (e.key === '/') {
        e.preventDefault();
        bodyRef.current?.querySelector<HTMLInputElement>('.nz-keys__railtop input')?.focus();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [modalOpen, flat, current, k, locatingPlate, busy]);

  /** The dock's Lock button is enabled (out, not towed, not sitting in another vehicle). */
  const canLockNow = (x: KeyEntry) => x.spawned && !x.towing && !(data.seatPlate && data.seatPlate !== x.plate);

  /* ── header / footer ── */
  const total = keys.length;
  const outCount = keys.filter((x) => x.spawned).length;
  const tempCount = keys.filter((x) => x.kind === 'temp').length;
  const virtual = data.mode === 'virtual';
  const subtitle = virtual ? t('Virtual keys') : t('Physical keys');

  const headerExtra = (
    <>
      <span
        className={cx('nz-keys__modepill', virtual ? 'is-virtual' : 'is-physical')}
        title={virtual ? t('Keys live on the server') : t('Keys are items in your inventory')}
      >
        {virtual ? <Icon name="link" size={12} strokeWidth={1.9} /> : <FobGlyph size={13} strokeWidth={1.8} />}
        {virtual ? t('Virtual') : t('Physical')}
        <b>{total}</b>
      </span>
      <IconButton icon="refresh" label={t('Refresh')} variant="ghost" size="sm" onClick={() => void refresh()} disabled={refreshing} />
    </>
  );

  const filtered = query.trim() !== '' || activeFilter !== 'all';
  const shareKey = sharing ? (keys.find((x) => x.plate === sharing) ?? null) : null;

  return (
    <>
      <Window
        className="nz-keys"
        bodyClassName="nz-keys__body"
        width="min(1180px, 94vw)"
        height="min(880px, 92vh)"
        title={t('Key ring')}
        icon="key"
        subtitle={subtitle}
        headerExtra={headerExtra}
        onClose={close}
        footer={
          <>
            <span>
              <b>{total}</b> {t('key(s)')}
              {outCount > 0 && (
                <>
                  {' · '}
                  <b>{outCount}</b> {t('out')}
                </>
              )}
              {tempCount > 0 && (
                <>
                  {' · '}
                  <b>{tempCount}</b> {t('temporary')}
                </>
              )}
            </span>
            <span className="nz-keys__spacer" />
            {flat.length > 0 && <KeyHint keys={['ArrowUp', 'ArrowDown']} label={t('Select')} />}
            {k && canLockNow(k) && <KeyHint keys={['Enter']} label={k.locked === true ? t('Unlock') : t('Lock')} />}
            {k?.trackable && <KeyHint keys={['L']} label={t('Locate')} />}
            {total > 0 && <KeyHint keys={['/']} label={t('Search')} />}
            <KeyHint keys={['Esc']} label={t('Close')} />
          </>
        }
      >
        <div ref={bodyRef} className="nz-keys__layout">
          <aside className="nz-keys__rail" aria-label={t('Your keys')}>
            {total > 0 && (
              <KeyToolbar query={query} onQuery={setQuery} filter={activeFilter} onFilter={setFilter} counts={counts} present={present} />
            )}
            {total === 0 ? (
              <div className="nz-keys__vacant">
                <span className="nz-keys__vacant-line">{t('0 keys')}</span>
                {[1, 2, 3, 4].map((i) => (
                  <span key={i} className="nz-keys__hook" aria-hidden="true">
                    <Icon name="key" size={14} strokeWidth={1.4} />
                  </span>
                ))}
              </div>
            ) : groups.length === 0 ? (
              <div className="nz-keys__vacant">
                <span className="nz-keys__vacant-line">{t('No matches')}</span>
              </div>
            ) : (
              <KeyList
                groups={groups}
                selected={current}
                onSelect={setSelected}
                onActivate={(plate) => {
                  const x = keys.find((y) => y.plate === plate);
                  if (x && canLockNow(x)) void lock(x);
                }}
                leftOf={leftOf}
                unit={unit}
                locating={locatingPlate}
              />
            )}
            {filtered && total > 0 && (
              <button
                type="button"
                className="nz-keys__railfoot"
                onClick={() => {
                  setQuery('');
                  setFilter('all');
                }}
              >
                <Icon name="close" size={11} strokeWidth={2} />
                {t('Showing {count} of {total} · clear filters', { count: flat.length, total })}
              </button>
            )}
          </aside>
          <main className="nz-keys__main">
            {k ? (
              <KeyShow
                k={k}
                data={data}
                left={leftOf(k)}
                unit={unit}
                busy={{ lock: busy.lock === k.plate, locate: busy.locate === k.plate, alarm: busy.alarm === k.plate }}
                answer={answers[k.plate] ?? null}
                tracking={data.tracking && data.tracking.plate === k.plate ? data.tracking : null}
                locating={locatingPlate === k.plate}
                alarmCooldown={Math.max(0, Math.ceil(((cooldowns[k.plate] ?? 0) - now) / 1000))}
                holders={holders[k.plate]}
                holdersAt={holdersAt[k.plate] ?? now}
                revoking={revoking}
                now={now}
                onLock={() => void lock(k)}
                onLocate={() => void locate(k)}
                onStopLocate={() => void stopLocate(k)}
                onAlarm={() => void alarm(k)}
                onShare={() => setSharing(k.plate)}
                onRevoke={(h) => setRevoke({ plate: k.plate, holder: h })}
                onReloadHolders={() => void loadHolders(k.plate)}
              />
            ) : total === 0 ? (
              <EmptyRing virtual={virtual} />
            ) : (
              <div className="nz-keys__nomatch">
                <EmptyState
                  icon="search"
                  title={query.trim() ? t('No keys match “{query}”', { query: query.trim() }) : t('No keys match')}
                  description={t('Try a plate, a nickname or a model.')}
                />
              </div>
            )}
          </main>
        </div>
      </Window>

      <ShareModal k={shareKey} mode={data.mode} giveRange={data.ranges.give} unit={unit} onClose={() => setSharing(null)} onDone={shared} />
      <ConfirmDialog
        className="nz-keys-modal"
        open={!!revoke}
        tone="red"
        icon="ban"
        title={t('Revoke the key of {name}?', { name: revoke?.holder.name ?? '' })}
        message={
          revoke ? (
            <>
              {t('They can no longer lock, unlock or start')}{' '}
              <b>{displayName(keys.find((x) => x.plate === revoke.plate) ?? { label: revoke.plate })}</b>.{' '}
              {revoke.holder.kind === 'temp' ? t('Their temporary key ends now.') : t('You can give them a new key later.')}
            </>
          ) : null
        }
        confirmLabel={t('Revoke key')}
        busy={!!revoking}
        onConfirm={() => void confirmRevoke()}
        onCancel={() => setRevoke(null)}
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
