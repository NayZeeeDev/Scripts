/**
 * Interior creator (app 'creator', takes focus): left-docked editor window with an icon tab
 * bar (Details / Cutscene / Vehicles / Exit) over a local draft of the Interior. Lua does
 * the in-world work (positions, ghosts, camera); this app keeps the draft, validates and
 * saves. Escape does not close: it asks Lua to drop focus so the admin can walk around
 * (creator:walk); the app stays visible and dims until the editor key brings focus back.
 */
import { useCallback, useEffect, useRef, useState } from 'react';
import { useApp, useUi } from '@/lib/store';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import { useEscape } from '@/lib/escape';
import type { Cutscene, Interior, Vec4 } from '@/lib/types';
import { Button, ConfirmDialog, Icon, Window, cx } from '@/components/ui';
import type { IconName } from '@/components/ui';
import { DetailsTab } from './DetailsTab';
import { CutsceneTab } from './CutsceneTab';
import { VehiclesTab } from './VehiclesTab';
import { ExitTab } from './ExitTab';
import { isSet } from './parts';
import type { CreatorErrors, CreatorTab, PendingKey, RunFn, TabProps } from './parts';
import './creator.css';

const clone = <T,>(v: T): T => JSON.parse(JSON.stringify(v)) as T;

/** Fill the fields the editor relies on (Lua normalises too; keeps the dirty check stable). */
function normalize(raw: Interior): Interior {
  const cut = raw.cutscene ?? ({} as Partial<Cutscene>);
  return {
    id: raw.id ?? null,
    name: raw.name ?? '',
    enabled: raw.enabled !== false,
    profile: raw.profile || null,
    options: { ...(raw.options ?? {}) },
    entry: raw.entry,
    gtaInteriorId: raw.gtaInteriorId ?? null,
    cutscene: {
      enabled: cut.enabled === true,
      transition: Number.isFinite(cut.transition) ? (cut.transition as number) : 3000,
      returnTime: Number.isFinite(cut.returnTime) ? (cut.returnTime as number) : 1000,
      points: Array.isArray(cut.points) ? clone(cut.points) : [],
    },
    slots: Array.isArray(raw.slots) ? clone(raw.slots) : [],
    exit: raw.exit ?? null,
  };
}

function validate(d: Interior): CreatorErrors {
  const e: CreatorErrors = {};
  if (!d.name.trim()) e.name = t('Give the interior a name.');
  if (!isSet(d.entry)) e.entry = t('Set the entry point.');
  if (!d.slots.length) e.slots = t('Add at least one vehicle position.');
  return e;
}

const ERROR_TAB: Record<keyof CreatorErrors, CreatorTab> = { name: 'details', entry: 'details', slots: 'vehicles' };
/** Lua takes focus away while these run (ghost placement, camera preview). */
const AWAY: PendingKey[] = ['placeSlot', 'preview'];

export function CreatorApp() {
  const { open, data } = useApp('creator');
  const hint = useUi((s) => s.hint);
  const [draft, setDraft] = useState<Interior | null>(null);
  const [tab, setTab] = useState<CreatorTab>('details');
  const [pending, setPending] = useState<PendingKey | null>(null);
  const [errors, setErrors] = useState<CreatorErrors>({});
  const [submitted, setSubmitted] = useState(false);
  const [confirmCancel, setConfirmCancel] = useState(false);
  const [walking, setWalking] = useState(false);
  const [gtaName, setGtaName] = useState<string | null>(null);
  const initial = useRef('');
  /** Interior object the current draft was made from (avoids a frame of a previous session). */
  const source = useRef<Interior | null>(null);
  const pendingRef = useRef<PendingKey | null>(null);
  const openRef = useRef(open);
  openRef.current = open;

  // New editor session whenever Lua opens the app with an interior.
  useEffect(() => {
    if (!open || !data?.interior) return;
    const d = normalize(data.interior);
    source.current = data.interior;
    initial.current = JSON.stringify(d);
    setDraft(d);
    setTab('details');
    setErrors({});
    setSubmitted(false);
    setConfirmCancel(false);
    setWalking(false);
    setPending(null);
    pendingRef.current = null;
    setGtaName(data.gtaInteriorName ?? null);
  }, [open, data?.interior]);

  const run: RunFn = useCallback(async (key, name, payload) => {
    if (pendingRef.current) return null;
    pendingRef.current = key;
    setPending(key);
    const res = await request(name, payload);
    pendingRef.current = null;
    if (!openRef.current) return null;
    setPending(null);
    return res;
  }, []);

  const patch = useCallback((p: Partial<Interior>) => setDraft((d) => (d ? { ...d, ...p } : d)), []);
  const patchCutscene = useCallback(
    (p: Partial<Cutscene>) => setDraft((d) => (d ? { ...d, cutscene: { ...d.cutscene, ...p } } : d)),
    [],
  );
  const setSlots = useCallback((slots: Vec4[]) => {
    setDraft((d) => (d ? { ...d, slots } : d));
    void request('creator:showSlots', { slots });
  }, []);

  // Live validation once the admin tried to save.
  useEffect(() => {
    if (submitted && draft) setErrors(validate(draft));
  }, [submitted, draft]);

  // Walk mode ends when Lua clears its "open editor" hint (focus is back).
  const hintSeen = useRef(false);
  useEffect(() => {
    if (!walking) {
      hintSeen.current = false;
      return;
    }
    if (hint) hintSeen.current = true;
    else if (hintSeen.current) setWalking(false);
  }, [walking, hint]);

  const walk = async () => {
    if (walking) return;
    const res = await run('walk', 'creator:walk', {});
    if (res?.ok) setWalking(true);
  };

  useEscape(() => {
    if (!pendingRef.current) void walk();
  }, open && !!draft && !confirmCancel);

  if (!open || !data || !draft || source.current !== data.interior) return null;

  const dirty = JSON.stringify(draft) !== initial.current;
  const away = (pending !== null && AWAY.includes(pending)) || walking;
  const busy = pending !== null;

  const save = async () => {
    if (busy) return;
    const e = validate(draft);
    setErrors(e);
    setSubmitted(true);
    const first = (Object.keys(e) as (keyof CreatorErrors)[])[0];
    if (first) {
      setTab(ERROR_TAB[first]);
      if (first === 'name') {
        requestAnimationFrame(() => document.querySelector<HTMLInputElement>('.nz-creator__scroll input')?.focus());
      }
      return;
    }
    const res = await run('save', 'creator:save', { interior: { ...draft, name: draft.name.trim() } });
    // Lua closes the editor and reopens the admin panel on success.
    if (res?.ok) useUi.getState().hideApp('creator');
  };

  const doCancel = async () => {
    const res = await run('cancel', 'creator:cancel', {});
    setConfirmCancel(false);
    if (res?.ok) useUi.getState().hideApp('creator');
  };

  const cancel = () => {
    if (busy) return;
    if (dirty) setConfirmCancel(true);
    else void doCancel();
  };

  const tabErrors: Record<CreatorTab, boolean> = {
    details: !!(errors.name || errors.entry),
    cutscene: false,
    vehicles: !!errors.slots,
    exit: false,
  };

  const tabs: { value: CreatorTab; label: string; icon: IconName; count?: number; done?: boolean }[] = [
    { value: 'details', label: t('Details'), icon: 'edit' },
    { value: 'cutscene', label: t('Cutscene'), icon: 'camera', count: draft.cutscene.points.length || undefined },
    { value: 'vehicles', label: t('Vehicles'), icon: 'car', count: draft.slots.length || undefined },
    { value: 'exit', label: t('Exit'), icon: 'door', done: isSet(draft.exit) },
  ];

  const props: TabProps = {
    draft,
    patch,
    patchCutscene,
    setSlots,
    run,
    pending,
    errors,
    profiles: data.profiles ?? [],
    gtaName,
    setGtaName,
  };

  const footer = (
    <>
      <span className={cx('nz-creator__status', dirty && 'is-dirty')}>
        <i />
        {dirty ? t('Unsaved changes') : t('No unsaved changes')}
      </span>
      <span className="nz-creator__status-id">{draft.id ? t('Interior #{id}', { id: draft.id }) : t('New interior')}</span>
    </>
  );

  return (
    <>
      <Window
        title={data.mode === 'edit' ? t('Edit interior') : t('Create interior')}
        subtitle={draft.name.trim() || t('Untitled interior')}
        onClose={cancel}
        width={356}
        footer={footer}
        className={cx('nz-creator', away && 'is-away')}
        bodyClassName="nz-creator__body"
      >
        <div
          className="nz-creator__tabs"
          role="tablist"
          aria-label={t('Interior editor')}
          onKeyDown={(e) => {
            if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
            e.preventDefault();
            const i = tabs.findIndex((x) => x.value === tab);
            const next = tabs[(i + (e.key === 'ArrowRight' ? 1 : -1) + tabs.length) % tabs.length];
            setTab(next.value);
            // React clears e.currentTarget after dispatch: capture the list before the rAF.
            const list = e.currentTarget;
            requestAnimationFrame(() => list.querySelector<HTMLElement>('[aria-selected="true"]')?.focus());
          }}
        >
          {tabs.map((x) => {
            const on = x.value === tab;
            return (
              <button
                key={x.value}
                type="button"
                role="tab"
                aria-selected={on}
                tabIndex={on ? 0 : -1}
                className={cx('nz-creator__tab', on && 'is-on', tabErrors[x.value] && 'has-error')}
                onClick={() => setTab(x.value)}
              >
                <span className="nz-creator__tab-icon">
                  <Icon name={x.icon} size={17} strokeWidth={1.7} />
                  {tabErrors[x.value] ? (
                    <i className="nz-creator__tab-flag is-error" aria-label={t('Needs attention')} />
                  ) : x.count ? (
                    <i className="nz-creator__tab-flag">{x.count}</i>
                  ) : x.done ? (
                    <i className="nz-creator__tab-flag is-done">
                      <Icon name="check" size={8} strokeWidth={3} />
                    </i>
                  ) : null}
                </span>
                <span className="nz-creator__tab-label">{x.label}</span>
              </button>
            );
          })}
        </div>

        <div className="nz-creator__scroll" key={tab}>
          {tab === 'details' && (
            <DetailsTab
              {...props}
              onSubmit={() => void save()}
              autoFocusName={data.mode === 'create' && !draft.name}
              goTo={setTab}
            />
          )}
          {tab === 'cutscene' && <CutsceneTab {...props} />}
          {tab === 'vehicles' && <VehiclesTab {...props} />}
          {tab === 'exit' && <ExitTab {...props} />}
        </div>

        <div className="nz-creator__actions">
          <Button variant="line" onClick={cancel} disabled={busy} loading={pending === 'cancel'} full>
            {t('Cancel')}
          </Button>
          <Button variant="teal" icon="save" onClick={() => void save()} disabled={busy && pending !== 'save'} loading={pending === 'save'} full>
            {t('Save')}
          </Button>
        </div>
      </Window>

      {!away && !hint && !confirmCancel && (
        <div className="nz-creator-pill" aria-hidden="true">
          <span className="nz-creator-pill__icon">
            <Icon name="walk" size={13} strokeWidth={1.9} />
          </span>
          <span>{t('Press ESC to walk around')}</span>
        </div>
      )}

      <ConfirmDialog
        open={confirmCancel}
        tone="red"
        icon="warning"
        title={t('Discard changes?')}
        message={
          data.mode === 'edit'
            ? t('Your changes to this interior will be lost.')
            : t('This interior has not been saved yet and will be lost.')
        }
        confirmLabel={t('Discard')}
        cancelLabel={t('Keep editing')}
        busy={pending === 'cancel'}
        onConfirm={() => void doCancel()}
        onCancel={() => setConfirmCancel(false)}
      />
    </>
  );
}
