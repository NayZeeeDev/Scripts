/**
 * LocationEditor — create / edit modal for every location kind (garage, job, private, impound).
 *
 * API
 *   <LocationEditor open kind seed data onClose onSaved(location) />
 *   - seed: the location to edit, or null to create one (defaults from ./defaults).
 *   Mount it with a new `key` per editing session; keep it mounted while closing so the exit
 *   animation plays.
 *
 * Sections: vehicle source (garage/job), general, locations (in-world point manager via
 * requestPoints → admin:points: the whole admin UI is hidden by CSS while it runs and this
 * modal stays mounted, so the draft, scroll position and focus survive), spawner vehicles +
 * vehicle rules, parking
 * capacity, garage access, access restriction (garage), sale & copies (private), impound
 * settings, map blip. Saved private locations get two tabs: Settings and Owners & copies
 * (live, see OwnersSection — those changes do not wait for Save).
 * Save → admin:location:save { location } → toast → onSaved (the page refreshes).
 * Validation is inline (name, ≥1 open point, ≥1 spawn point, …); Ctrl+S / Enter in the name
 * field saves; closing with unsaved changes asks first.
 */
import { useEffect, useMemo, useRef, useState } from 'react';
import type { KeyboardEvent, ReactNode } from 'react';
import {
  Button,
  ConfirmDialog,
  Field,
  Icon,
  InfoDot,
  Input,
  Modal,
  NumberInput,
  OptionRow,
  Section,
  Segmented,
  Select,
  Slider,
  Tabs,
  Toggle,
  cx,
} from '@/components/ui';
import type { IconName } from '@/components/ui';
import { isBrowser, request } from '@/lib/nui';
import { toast, useSettings } from '@/lib/store';
import { t } from '@/lib/i18n';
import { money } from '@/lib/format';
import type {
  AccessConfig,
  AdminOpenData,
  CapacityConfig,
  GarageLocation,
  ImpoundLocation,
  InteractionPoint,
  JobLocation,
  Location,
  PrivateLocation,
  RestrictionConfig,
  Vec3,
  Vec4,
  VehicleType,
} from '@/lib/types';
import { requestPoints } from '../shared/away';
import { RulesEditor } from '../shared/RulesEditor';
import { TagInput } from '../shared/TagInput';
import { accessModeOptions, coordsText, kindNoun, vehicleTypeOptions } from '../shared/labels';
import type { LocationPageKind } from '../shared/labels';
import { defaultBlipSprite, newLocation, normalizeLocation } from './defaults';
import { SpawnerEditor } from './SpawnerEditor';
import { OwnersSection } from './OwnersSection';

export interface LocationEditorProps {
  open: boolean;
  kind: LocationPageKind;
  seed: Location | null;
  data: AdminOpenData;
  onClose: () => void;
  onSaved: (location: Location) => void;
}

type PointKind = 'spawn' | 'open' | 'store';
type Errors = Partial<Record<'name' | 'spawn' | 'open' | 'store' | 'jobs' | 'spawner' | 'interior' | 'restriction', string>>;

const KIND_ICON: Record<LocationPageKind, IconName> = { garage: 'garage', job: 'briefcase', private: 'users', impound: 'impound' };


/** Approximate GTA blip colours for the preview swatch (ids 0–85). */
const BLIP_COLOURS: Record<number, string> = {
  0: '#fefefe', 1: '#e03232', 2: '#71cb71', 3: '#5db6e5', 4: '#f0f0f0', 5: '#eec64e', 6: '#c25050', 7: '#9c6eaf',
  8: '#fe7ac3', 9: '#f59d79', 10: '#b18f83', 11: '#8dce9e', 12: '#70a8ae', 13: '#d3d1e7', 14: '#8f7e98', 15: '#6ac4bf',
  16: '#d5c398', 17: '#ea8e50', 18: '#97cae9', 19: '#b26287', 20: '#8f8d79', 21: '#a6755e', 22: '#afa8a8', 23: '#e88e9b',
  24: '#bbd65b', 25: '#0c7b56', 26: '#7ac3fe', 27: '#ab3ce6', 28: '#cda80c', 29: '#4561ab', 30: '#29a5b8', 31: '#b89b7b',
  32: '#c8e0fe', 33: '#f0f096', 34: '#ed8ca1', 35: '#f98a8a', 36: '#fbeea5', 37: '#ffffff', 38: '#2c6db8', 39: '#9a9a9a',
  40: '#4c4c4c', 46: '#eec64e', 47: '#f4a73f', 48: '#e85bd5', 49: '#f17f7f', 50: '#7e6bcc', 51: '#e36b51', 52: '#4f9e38',
  53: '#a6d2f0', 54: '#2d9fcc', 55: '#2e4fa5', 56: '#ce6e5f', 57: '#3fb0bb', 58: '#874aa7', 59: '#c9342f', 60: '#d8d82c',
  61: '#b5568a', 62: '#3f3f3f', 63: '#1c8bcd', 64: '#e05e36', 66: '#efc84c', 69: '#2fa86b', 81: '#f2a240', 83: '#9f5fdb', 84: '#3586d8', 85: '#1f1f1f',
};

const plural = (n: number, one: string, many: string) => t(n === 1 ? one : many, { count: n });

type EditorTab = 'settings' | 'owners';
/** Dev harness only (src/dev/mocks/admin.ts): open the editor of __devEdit on __devTab. */
type DevTab = { __devEdit?: number | 'new'; __devTab?: EditorTab };

export function LocationEditor({ open, kind, seed, data, onClose, onSaved }: LocationEditorProps) {
  const settings = useSettings();
  const [initial] = useState<Location>(() => (seed ? normalizeLocation(seed, data) : newLocation(kind, data)));
  const [draft, setDraft] = useState<Location>(initial);
  const [tried, setTried] = useState(false);
  const [saving, setSaving] = useState(false);
  const [pointsBusy, setPointsBusy] = useState<PointKind | null>(null);
  const [updated, setUpdated] = useState<PointKind | null>(null);
  const [confirmDiscard, setConfirmDiscard] = useState(false);
  const [tab, setTab] = useState<EditorTab>(() => {
    const dev = data as AdminOpenData & DevTab;
    return isBrowser && dev.__devTab && seed && dev.__devEdit === seed.id ? dev.__devTab : 'settings';
  });
  const [ownerCount, setOwnerCount] = useState<number | null>(null);
  const formRef = useRef<HTMLDivElement>(null);

  const isNew = initial.id === null;
  const hasOwners = initial.kind === 'private' && initial.id !== null;
  const noun = kindNoun(kind);
  const dirty = useMemo(() => JSON.stringify(draft) !== JSON.stringify(initial), [draft, initial]);

  const set = (patch: Record<string, unknown>) => setDraft((d) => ({ ...d, ...patch }) as Location);

  // Briefly highlight the points row the in-world tool just changed.
  useEffect(() => {
    if (!updated) return;
    const id = window.setTimeout(() => setUpdated(null), 1600);
    return () => window.clearTimeout(id);
  }, [updated]);

  /* ── validation ── */
  const errors: Errors = useMemo(() => {
    const e: Errors = {};
    if (!draft.name.trim()) e.name = t('Give this location a name');
    if (!draft.openPoints.length) e.open = t('Place at least one open interaction');
    if (!draft.spawnPoints.length) e.spawn = t('Place at least one spawn point');
    if (draft.kind !== 'impound' && !draft.useOpenForStore && !draft.storePoints.length) {
      e.store = t('Place a store interaction, or store at the open interactions');
    }
    if (draft.kind === 'job' && !draft.jobs.length) {
      e.jobs = draft.owner === 'gang' ? t('Add the gang that may use this garage') : t('Add at least one job');
    }
    if ((draft.kind === 'garage' || draft.kind === 'job') && draft.source === 'spawner' && !draft.spawner.length) {
      e.spawner = t('Add at least one vehicle to the spawner');
    }
    if ((draft.kind === 'garage' || draft.kind === 'job' || draft.kind === 'private') && draft.access.mode !== 'quick' && !draft.access.interiorId) {
      e.interior = t('Choose the interior players walk into');
    }
    if (draft.kind === 'garage') {
      const r = draft.restriction;
      if ((r.type === 'job' || r.type === 'gang') && !r.rules.length) e.restriction = r.type === 'gang' ? t('Add at least one gang') : t('Add at least one job');
      if (r.type === 'identifier' && !r.identifiers.length) e.restriction = t('Add at least one player identifier');
    }
    return e;
  }, [draft]);

  const shown: Errors = tried ? errors : {};
  const errorCount = Object.keys(errors).length;

  /* ── actions ── */
  const requestClose = () => {
    if (saving) return;
    if (dirty) setConfirmDiscard(true);
    else onClose();
  };

  const save = async () => {
    if (saving) return;
    setTried(true);
    if (errorCount) {
      if (tab !== 'settings') setTab('settings');
      requestAnimationFrame(() => {
        const el = formRef.current?.querySelector<HTMLElement>('[data-invalid="true"]');
        el?.scrollIntoView({ block: 'center', behavior: 'smooth' });
      });
      return;
    }
    const location = { ...draft, name: draft.name.trim() } as Location;
    setSaving(true);
    const res = await request('admin:location:save', { location });
    setSaving(false);
    if (!res.ok) return;
    toast({
      type: 'success',
      message: isNew ? t('{name} was created', { name: location.name }) : t('{name} was saved', { name: location.name }),
    });
    onSaved(res.data ?? location);
  };

  const managePoints = async (which: PointKind) => {
    if (pointsBusy) return;
    const key = which === 'spawn' ? 'spawnPoints' : which === 'open' ? 'openPoints' : 'storePoints';
    const points = draft[key] as Vec4[] | InteractionPoint[];
    const model =
      which === 'spawn' && (draft.kind === 'garage' || draft.kind === 'job') && draft.source === 'spawner'
        ? draft.spawner[0]?.model || undefined
        : undefined;
    setPointsBusy(which);
    const res = await requestPoints({ kind: which, vehicleType: draft.vehicleType, points, ...(model ? { model } : {}) });
    setPointsBusy(null);
    // null = the admin cancelled the tool: keep the current points.
    if (!res.ok || !Array.isArray(res.data)) return;
    if (JSON.stringify(res.data) !== JSON.stringify(points)) {
      set({ [key]: res.data });
      setUpdated(which);
    }
  };

  // Keyboard: Ctrl+S anywhere, Enter in any field of the form (not in the live Owners tab and
  // not in portalled popovers / the vehicle dialog, whose events also bubble here). Deferred a
  // tick so a NumberInput that commits its value on Enter is saved with that value.
  const saveRef = useRef(save);
  saveRef.current = save;
  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') {
      e.preventDefault();
      window.setTimeout(() => void saveRef.current(), 0);
      return;
    }
    if (e.key !== 'Enter' || e.defaultPrevented || e.shiftKey || e.altKey || e.ctrlKey || e.metaKey) return;
    const el = e.target as HTMLElement;
    if (el.tagName !== 'INPUT' || !formRef.current?.contains(el) || el.closest('.nz-admin-owners')) return;
    e.preventDefault();
    window.setTimeout(() => void saveRef.current(), 0);
  };

  const setVehicleType = (vt: VehicleType) => {
    setDraft((d) => {
      const blip = d.blip.sprite === defaultBlipSprite(kind, d.vehicleType) ? { ...d.blip, sprite: defaultBlipSprite(kind, vt) } : d.blip;
      return { ...d, vehicleType: vt, blip } as Location;
    });
  };

  /* ── per-kind helpers ── */
  const hasCapacity = draft.kind === 'garage' || draft.kind === 'job' || draft.kind === 'private';
  const sourceSpawner = (draft.kind === 'garage' || draft.kind === 'job') && draft.source === 'spawner';

  const jobGrades = useMemo(() => {
    if (draft.kind !== 'job') return undefined;
    const list = draft.owner === 'gang' ? data.gangs : data.jobs;
    const map = new Map<number, string>();
    for (const rule of draft.jobs) {
      const info = list.find((j) => j.name === rule.name);
      info?.grades.forEach((g) => {
        if (!map.has(g.grade)) map.set(g.grade, draft.jobs.length > 1 ? `${g.grade} · ${g.label} (${info.label})` : `${g.grade} · ${g.label}`);
      });
    }
    if (!map.size) for (let g = 0; g <= 4; g++) map.set(g, t('Grade {grade}', { grade: g }));
    return [...map.entries()].sort((a, b) => a[0] - b[0]).map(([value, label]) => ({ value, label }));
  }, [draft, data.gangs, data.jobs]);

  const title = isNew
    ? kind === 'job'
      ? t('Create job / gang garage')
      : t('Create {noun}', { noun: noun.toLowerCase() })
    : t('Edit {name}', { name: initial.name });

  return (
    <>
      <Modal
        open={open}
        onClose={requestClose}
        locked={saving}
        icon={KIND_ICON[kind]}
        title={title}
        subtitle={isNew ? t('Fill in the details, then place the points in the world') : `${noun} · #${initial.id}`}
        width={720}
        className="nz-admin-editor"
        bodyClassName="nz-admin-editor__body"
        footer={
          <>
            <span className="nz-admin-editor__status">
              {tried && errorCount > 0 ? (
                <span className="is-error">
                  <Icon name="warning" size={13} strokeWidth={1.8} />
                  {plural(errorCount, '{count} field needs attention', '{count} fields need attention')}
                </span>
              ) : dirty ? (
                <span className="is-dirty">
                  <i />
                  {t('Unsaved changes')}
                </span>
              ) : (
                <span>{isNew ? t('New {noun}', { noun: noun.toLowerCase() }) : t('No changes')}</span>
              )}
            </span>
            <Button variant="line" onClick={requestClose} disabled={saving}>
              {t('Cancel')}
            </Button>
            <Button variant="teal" icon="save" loading={saving} onClick={() => void save()}>
              {isNew ? t('Create') : t('Save')}
            </Button>
          </>
        }
      >
        <div ref={formRef} className="nz-admin-editor__form" onKeyDown={onKeyDown}>
          {hasOwners && (
            <Tabs<EditorTab>
              className="nz-admin-editor__tabs"
              variant="underline"
              value={tab}
              onChange={(next) => {
                setTab(next);
                const body = formRef.current?.parentElement;
                if (body) body.scrollTop = 0;
              }}
              items={[
                { value: 'settings', label: t('Settings'), icon: 'sliders' },
                { value: 'owners', label: t('Owners & copies'), icon: 'users', count: ownerCount ?? undefined },
              ]}
            />
          )}
          <div className="nz-admin-editor__pane" hidden={tab !== 'settings'}>
          {/* ── source ── */}
          {draft.kind === 'garage' && (
            <SourcePicker
              value={draft.source}
              onChange={(source) => set({ source })}
              options={[
                {
                  value: 'personal',
                  icon: 'car',
                  label: t('Personal vehicles'),
                  text: t('Players park and take out their own vehicles'),
                  info: t('Owned vehicles are stored here and taken out again. Capacity, transfers and the interior apply.'),
                },
                {
                  value: 'spawner',
                  icon: 'key',
                  label: t('Spawner vehicles'),
                  text: t('A fixed list players can take out (rentals, free cars)'),
                  info: t('Vehicles come from the list below and are never owned. Players return them here when done.'),
                },
              ]}
            />
          )}
          {draft.kind === 'job' && (
            <SourcePicker
              value={draft.source}
              onChange={(source) => set({ source })}
              options={[
                {
                  value: 'owned',
                  icon: 'briefcase',
                  label: t('Job-owned vehicles'),
                  text: t('A persistent fleet shared by the members'),
                  info: t('Vehicles owned by the job or gang are stored here with their damage, fuel and mods.'),
                },
                {
                  value: 'spawner',
                  icon: 'key',
                  label: t('Spawner vehicles'),
                  text: t('Members take out vehicles from a list, by grade'),
                  info: t('Nothing is stored: vehicles are spawned on demand and removed when returned.'),
                },
              ]}
            />
          )}

          {/* ── general ── */}
          <Section title={t('General')}>
            <div className={cx('nz-admin-form__grid', draft.kind === 'job' && 'is-3')}>
              <Field label={t('Name')} required error={shown.name}>
                <Input
                  value={draft.name}
                  onChange={(name) => set({ name })}
                  maxLength={60}
                  placeholder={kind === 'impound' ? t('e.g. Davis Impound') : t('e.g. Legion Square')}
                  onEnter={() => void save()}
                  autoFocus={isNew}
                />
              </Field>
              {draft.kind === 'job' && (
                <Field label={t('Vehicle owner')}>
                  <Select<'job' | 'gang'>
                    value={draft.owner}
                    onChange={(owner) => set({ owner, jobs: [] })}
                    options={[
                      { value: 'job', label: t('Job'), icon: 'briefcase' },
                      {
                        value: 'gang',
                        label: t('Gang'),
                        icon: 'users',
                        disabled: !data.gangsSupported,
                        hint: data.gangsSupported ? undefined : t('Not supported by this framework'),
                      },
                    ]}
                  />
                </Field>
              )}
              <Field label={t('Vehicle type')}>
                <Select<VehicleType> value={draft.vehicleType} onChange={setVehicleType} options={vehicleTypeOptions()} />
              </Field>
            </div>

            {draft.kind === 'job' && (
              <div className="nz-admin-form__block" data-invalid={!!shown.jobs}>
                <div className="nz-admin-form__label-row">
                  <span className="nz-admin-form__label">{draft.owner === 'gang' ? t('Gangs') : t('Jobs')}</span>
                  <InfoDot text={t('Members of these jobs (from the minimum grade up) can use this garage.')} />
                </div>
                <RulesEditor
                  value={draft.jobs}
                  onChange={(jobs) => set({ jobs })}
                  options={draft.owner === 'gang' ? data.gangs : data.jobs}
                  noun={draft.owner}
                  invalid={!!shown.jobs}
                />
                {shown.jobs && <FormError>{shown.jobs}</FormError>}
              </div>
            )}

            <Toggle
              checked={draft.enabled}
              onChange={(enabled) => set({ enabled })}
              label={t('Enabled')}
              description={t('Disabled locations are hidden from players but keep every setting.')}
            />
          </Section>

          {/* ── locations ── */}
          <Section title={t('Locations')}>
            <div className="nz-admin-points">
              <PointsRow
                icon="car"
                label={t('Spawn points')}
                info={t('Where vehicles appear when taken out. Add several so players do not block each other.')}
                count={plural(draft.spawnPoints.length, '{count} spawn point', '{count} spawn points')}
                first={draft.spawnPoints[0]}
                action={t('Manage spawn points')}
                busy={pointsBusy === 'spawn'}
                flash={updated === 'spawn'}
                disabled={pointsBusy !== null}
                error={shown.spawn}
                onManage={() => void managePoints('spawn')}
              />
              <PointsRow
                icon="pin"
                label={t('Open interactions')}
                info={t('Where players open this menu (prompt or target).')}
                count={plural(draft.openPoints.length, '{count} location', '{count} locations')}
                first={draft.openPoints[0]?.coords}
                radius={draft.openPoints[0]?.radius}
                action={t('Manage locations')}
                busy={pointsBusy === 'open'}
                flash={updated === 'open'}
                disabled={pointsBusy !== null}
                error={shown.open}
                onManage={() => void managePoints('open')}
              />
              {draft.kind !== 'impound' && (
                <>
                  <Toggle
                    checked={draft.useOpenForStore}
                    onChange={(useOpenForStore) => set({ useOpenForStore })}
                    label={t('Use open interactions for storing vehicles')}
                    description={t('Players park at the same spots where they open the menu.')}
                  />
                  {!draft.useOpenForStore && (
                    <PointsRow
                      icon="parking"
                      label={t('Store interactions')}
                      info={t('Where players drive in to park their vehicle.')}
                      count={plural(draft.storePoints.length, '{count} location', '{count} locations')}
                      first={draft.storePoints[0]?.coords}
                      radius={draft.storePoints[0]?.radius}
                      action={t('Manage locations')}
                      busy={pointsBusy === 'store'}
                      flash={updated === 'store'}
                      disabled={pointsBusy !== null}
                      error={shown.store}
                      onManage={() => void managePoints('store')}
                    />
                  )}
                  <OptionRow
                    label={
                      <span className="nz-admin-form__inline">
                        {t('Return to garage entrance after parking')}
                        <InfoDot text={t('After storing a vehicle, the player is placed at the first open interaction (useful for parking lots).')} />
                      </span>
                    }
                    control={<Toggle checked={draft.returnToEntrance} onChange={(returnToEntrance) => set({ returnToEntrance })} />}
                  />
                </>
              )}
            </div>
          </Section>

          {/* ── spawner ── */}
          {(draft.kind === 'garage' || draft.kind === 'job') && sourceSpawner && (
            <Section title={t('Spawner vehicles')}>
              <div data-invalid={!!shown.spawner}>
                <SpawnerEditor
                  value={draft.spawner}
                  onChange={(spawner) => set({ spawner })}
                  grades={draft.kind === 'job' ? jobGrades : undefined}
                  invalid={!!shown.spawner}
                />
                {shown.spawner && <FormError>{shown.spawner}</FormError>}
              </div>
            </Section>
          )}

          {draft.kind === 'job' && (
            <Section title={t('Vehicle rules')}>
              <Toggle
                checked={draft.infiniteSpawns}
                onChange={(infiniteSpawns) => set({ infiniteSpawns })}
                disabled={draft.source !== 'spawner'}
                label={t('Infinite spawns')}
                description={
                  draft.source === 'spawner'
                    ? t('Members may take out another vehicle while their previous one is still out.')
                    : t('Only for spawner vehicles.')
                }
              />
              <Toggle
                checked={draft.setupMenu}
                onChange={(setupMenu) => set({ setupMenu })}
                label={t('Liveries / extras menu')}
                description={t('Let members pick a livery and extras before driving off.')}
              />
            </Section>
          )}

          {/* ── private sale ── */}
          {draft.kind === 'private' && <PrivateSale draft={draft} set={set} currency={settings.currency} saved={hasOwners} />}

          {/* ── impound ── */}
          {draft.kind === 'impound' && <ImpoundFields draft={draft} set={set} data={data} currency={settings.currency} />}

          {/* ── capacity ── */}
          {hasCapacity && (
            <Section title={t('Parking capacity')}>
              <CapacityFields
                value={(draft as GarageLocation | JobLocation | PrivateLocation).capacity}
                kind={kind}
                onChange={(capacity) => set({ capacity })}
              />
            </Section>
          )}

          {/* ── access ── */}
          {hasCapacity && (
            <Section title={t('Garage access')}>
              <AccessFields
                value={(draft as GarageLocation | JobLocation | PrivateLocation).access}
                data={data}
                error={shown.interior}
                onChange={(access) => set({ access })}
              />
            </Section>
          )}

          {/* ── restriction ── */}
          {draft.kind === 'garage' && (
            <Section title={t('Access restriction')}>
              <RestrictionFields value={draft.restriction} data={data} error={shown.restriction} onChange={(restriction) => set({ restriction })} />
            </Section>
          )}

          {/* ── blip ── */}
          <Section title={t('Map blip')}>
            <Toggle
              checked={draft.blip.enabled}
              onChange={(enabled) => set({ blip: { ...draft.blip, enabled } })}
              label={t('Show on the map')}
              description={t('Players see this location on the pause map and minimap.')}
            />
            <div className={cx('nz-admin-form__grid is-3', !draft.blip.enabled && 'is-muted')}>
              <Field label={t('Sprite')} hint={t('GTA blip id')}>
                <NumberInput
                  value={draft.blip.sprite}
                  onChange={(sprite) => set({ blip: { ...draft.blip, sprite: Math.round(sprite) } })}
                  min={1}
                  max={1000}
                  disabled={!draft.blip.enabled}
                />
              </Field>
              <Field label={t('Colour')} hint={t('GTA colour id (0–85)')}>
                <div className="nz-admin-form__swatch-row">
                  <span
                    className="nz-admin-form__swatch"
                    style={{ background: BLIP_COLOURS[draft.blip.color] ?? 'transparent' }}
                    aria-hidden="true"
                  />
                  <NumberInput
                    className="nz-admin-form__swatch-input"
                    value={draft.blip.color}
                    onChange={(color) => set({ blip: { ...draft.blip, color: Math.round(color) } })}
                    min={0}
                    max={85}
                    disabled={!draft.blip.enabled}
                  />
                </div>
              </Field>
              <Field label={t('Scale')}>
                <Slider
                  value={draft.blip.scale}
                  onChange={(scale) => set({ blip: { ...draft.blip, scale } })}
                  min={0.1}
                  max={2}
                  step={0.05}
                  disabled={!draft.blip.enabled}
                  format={(n) => n.toFixed(2)}
                />
              </Field>
            </div>
          </Section>

          </div>

          {/* ── owners (live, saved private locations) ── */}
          {hasOwners && initial.id !== null && (
            <div className="nz-admin-editor__pane" hidden={tab !== 'owners'}>
              <OwnersSection
                locationId={initial.id}
                maxCopies={(initial as PrivateLocation).maxCopies}
                purchasable={draft.kind === 'private' ? draft.purchasable : true}
                onCount={setOwnerCount}
              />
            </div>
          )}
        </div>
      </Modal>

      <ConfirmDialog
        open={confirmDiscard}
        tone="red"
        icon="warning"
        title={t('Discard your changes?')}
        message={t('The changes you made to this {noun} have not been saved.', { noun: noun.toLowerCase() })}
        confirmLabel={t('Discard')}
        cancelLabel={t('Keep editing')}
        onConfirm={() => {
          setConfirmDiscard(false);
          onClose();
        }}
        onCancel={() => setConfirmDiscard(false)}
      />
    </>
  );
}

/* ───────────────────────── parts ───────────────────────── */

function FormError({ children }: { children: ReactNode }) {
  return (
    <span className="nz-admin-form__error" role="alert">
      <Icon name="warning" size={12} strokeWidth={1.8} />
      {children}
    </span>
  );
}

interface SourceOption<T extends string> {
  value: T;
  icon: IconName;
  label: string;
  text: string;
  info: string;
}

function SourcePicker<T extends string>({ value, onChange, options }: { value: T; onChange: (v: T) => void; options: SourceOption<T>[] }) {
  return (
    <div className="nz-admin-source" role="radiogroup" aria-label={t('Vehicle source')}>
      {options.map((o) => {
        const on = o.value === value;
        return (
          <div key={o.value} className={cx('nz-admin-source__opt', on && 'is-on')}>
            <button type="button" role="radio" aria-checked={on} className="nz-admin-source__btn" onClick={() => onChange(o.value)}>
              <span className="nz-admin-source__icon">
                <Icon name={o.icon} size={16} strokeWidth={1.7} />
              </span>
              <span className="nz-admin-source__text">
                <b>{o.label}</b>
                <small>{o.text}</small>
              </span>
              <span className="nz-admin-source__radio" aria-hidden="true" />
            </button>
            <InfoDot text={o.info} className="nz-admin-source__info" />
          </div>
        );
      })}
    </div>
  );
}

interface PointsRowProps {
  icon: IconName;
  label: string;
  info: string;
  count: string;
  first?: Vec3 | Vec4;
  radius?: number;
  action: string;
  busy: boolean;
  /** Just changed by the in-world tool. */
  flash?: boolean;
  disabled: boolean;
  error?: string;
  onManage: () => void;
}

function PointsRow({ icon, label, info, count, first, radius, action, busy, flash, disabled, error, onManage }: PointsRowProps) {
  return (
    <div className="nz-admin-points__item" data-invalid={!!error}>
      <div className="nz-admin-form__label-row">
        <span className="nz-admin-form__label">{label}</span>
        <InfoDot text={info} />
      </div>
      <div className={cx('nz-admin-points__row', error && 'is-invalid', !first && 'is-empty', flash && 'is-updated')}>
        <span className="nz-admin-points__icon">
          <Icon name={icon} size={15} strokeWidth={1.7} />
        </span>
        <span className="nz-admin-points__text">
          <b>{count}</b>
          <small>
            {first
              ? `${coordsText(first)}${'w' in first ? ` · ${Math.round(first.w)}°` : ''}${radius ? ` · ${radius} m` : ''}`
              : t('Nothing placed yet')}
          </small>
        </span>
        <Button size="sm" variant={first ? 'line' : 'white'} icon="pin" loading={busy} disabled={disabled && !busy} onClick={onManage}>
          {action}
        </Button>
      </div>
      {error && <FormError>{error}</FormError>}
    </div>
  );
}

function CapacityFields({ value, kind, onChange }: { value: CapacityConfig; kind: LocationPageKind; onChange: (c: CapacityConfig) => void }) {
  const unlimited = value.mode === 'unlimited';
  const scope = kind === 'private' ? t('per copy of the garage') : '';
  const summary = unlimited
    ? t('No limit on how many vehicles can be parked here.')
    : value.appliesTo === 'player'
      ? t('Each player can park up to {n} vehicles here.', { n: value.spaces })
      : t('Up to {n} vehicles in total, shared by everyone.', { n: value.spaces });
  return (
    <>
      <div className="nz-admin-form__grid is-3">
        <Field label={t('Capacity')}>
          <Select<CapacityConfig['mode']>
            value={value.mode}
            onChange={(mode) => onChange({ ...value, mode })}
            options={[
              { value: 'unlimited', label: t('Unlimited'), icon: 'layers' },
              { value: 'limited', label: t('Limited'), icon: 'parking' },
            ]}
          />
        </Field>
        <Field label={t('Applies to')}>
          <Select<CapacityConfig['appliesTo']>
            value={value.appliesTo}
            onChange={(appliesTo) => onChange({ ...value, appliesTo })}
            disabled={unlimited}
            options={[
              { value: 'player', label: t('Each player'), icon: 'user' },
              { value: 'total', label: t('In total'), icon: 'users' },
            ]}
          />
        </Field>
        <Field label={t('Spaces')}>
          <NumberInput value={value.spaces} onChange={(spaces) => onChange({ ...value, spaces: Math.round(spaces) })} min={1} max={1000} disabled={unlimited} />
        </Field>
      </div>
      <p className="nz-admin-form__hint is-block">
        <Icon name="info" size={12} strokeWidth={1.8} />
        {summary}
        {scope && !unlimited ? ` (${scope})` : ''}
      </p>
    </>
  );
}

function AccessFields({ value, data, error, onChange }: { value: AccessConfig; data: AdminOpenData; error?: string; onChange: (a: AccessConfig) => void }) {
  const hasInteriors = data.interiors.length > 0;
  const modes = accessModeOptions().map((o) =>
    o.value !== 'quick' && !hasInteriors ? { ...o, disabled: true, hint: t('Create an interior first') } : o,
  );
  const interiorOptions = data.interiors
    .filter((i) => i.id !== null)
    .map((i) => ({
      value: i.id as number,
      label: i.name,
      hint: i.enabled ? i.slots.length === 1 ? t('1 slot') : t('{count} slots', { count: i.slots.length }) : t('Disabled'),
      icon: 'building' as IconName,
    }));
  const quick = value.mode === 'quick';
  return (
    <div className="nz-admin-form__grid" data-invalid={!!error}>
      <Field label={t('Access mode')}>
        <Select<AccessConfig['mode']>
          value={value.mode}
          onChange={(mode) =>
            onChange({ mode, interiorId: mode === 'quick' ? value.interiorId : value.interiorId ?? (interiorOptions[0]?.value ?? null) })
          }
          options={modes}
        />
      </Field>
      <Field label={t('Interior')} error={error} hint={quick ? t('Only used with an interior access mode') : undefined}>
        <Select<number>
          value={quick ? null : value.interiorId}
          onChange={(interiorId) => onChange({ ...value, interiorId })}
          options={interiorOptions}
          disabled={quick || !hasInteriors}
          placeholder={hasInteriors ? t('Choose an interior') : t('No interiors yet')}
          searchable={interiorOptions.length > 8}
        />
      </Field>
    </div>
  );
}

function RestrictionFields({
  value,
  data,
  error,
  onChange,
}: {
  value: RestrictionConfig;
  data: AdminOpenData;
  error?: string;
  onChange: (r: RestrictionConfig) => void;
}) {
  return (
    <div className="nz-admin-form__stack" data-invalid={!!error}>
      <Field label={t('Who can use this garage')}>
        <Select<RestrictionConfig['type']>
          value={value.type}
          onChange={(type) => onChange({ type, rules: type === value.type ? value.rules : [], identifiers: value.identifiers })}
          options={[
            { value: 'everyone', label: t('Everyone'), icon: 'users' },
            { value: 'job', label: t('Job'), icon: 'briefcase', hint: t('Members of chosen jobs') },
            {
              value: 'gang',
              label: t('Gang'),
              icon: 'shield',
              disabled: !data.gangsSupported,
              hint: data.gangsSupported ? t('Members of chosen gangs') : t('Not supported by this framework'),
            },
            { value: 'identifier', label: t('Specific players'), icon: 'user', hint: t('By identifier') },
          ]}
        />
      </Field>
      {(value.type === 'job' || value.type === 'gang') && (
        <RulesEditor
          value={value.rules}
          onChange={(rules) => onChange({ ...value, rules })}
          options={value.type === 'gang' ? data.gangs : data.jobs}
          noun={value.type}
          invalid={!!error}
        />
      )}
      {value.type === 'identifier' && (
        <Field label={t('Player identifiers')} hint={t('Press Enter after each identifier, or paste a list.')}>
          <TagInput
            value={value.identifiers}
            onChange={(identifiers) => onChange({ ...value, identifiers })}
            placeholder={t('e.g. ABC12345')}
            invalid={!!error}
          />
        </Field>
      )}
      {error && <FormError>{error}</FormError>}
    </div>
  );
}

function PrivateSale({
  draft,
  set,
  currency,
  saved,
}: {
  draft: PrivateLocation;
  set: (p: Record<string, unknown>) => void;
  currency: string;
  saved: boolean;
}) {
  const refund = Math.round((draft.price * draft.sellRefund) / 100);
  return (
    <Section title={t('Sale & copies')}>
      <Toggle
        checked={draft.purchasable}
        onChange={(purchasable) => set({ purchasable })}
        label={t('Purchasable')}
        description={
          draft.purchasable
            ? t('Players can buy a copy at the garage. Admins can still assign copies.')
            : saved
              ? t('Only admins assign this garage, in the Owners & copies tab.')
              : t('Only admins assign this garage, in the Owners & copies tab once it is saved.')
        }
      />
      <div className="nz-admin-form__grid">
        <Field label={t('Price')} hint={draft.purchasable ? undefined : t('Not for sale')}>
          <NumberInput
            value={draft.price}
            onChange={(price) => set({ price: Math.round(price) })}
            min={0}
            max={100000000}
            step={1000}
            prefix={currency}
            disabled={!draft.purchasable}
          />
        </Field>
        <Field label={t('Max copies')} hint={draft.maxCopies === 0 ? t('0 = unlimited copies') : t('How many players can own one')}>
          <NumberInput
            value={draft.maxCopies}
            onChange={(maxCopies) => set({ maxCopies: Math.round(maxCopies) })}
            min={0}
            max={1000}
            suffix={draft.maxCopies === 0 ? t('unlimited') : undefined}
          />
        </Field>
      </div>
      <OptionRow
        label={t('Storage')}
        description={
          draft.storage === 'shared'
            ? t('Every member sees and may drive every vehicle parked in the copy.')
            : t('Members only see their own vehicles in the copy.')
        }
        control={
          <Segmented<PrivateLocation['storage']>
            value={draft.storage}
            onChange={(storage) => set({ storage })}
            size="sm"
            options={[
              { value: 'shared', label: t('Shared vehicles'), icon: 'users' },
              { value: 'personal', label: t('Personal'), icon: 'user' },
            ]}
          />
        }
      />
      <OptionRow
        stacked
        label={t('Sell refund')}
        description={
          draft.purchasable && draft.price > 0
            ? t('Owners selling an empty garage get {amount} back.', { amount: money(refund) })
            : t('Share of the price refunded when an owner sells an empty garage.')
        }
        control={<Slider value={draft.sellRefund} onChange={(sellRefund) => set({ sellRefund })} min={0} max={100} step={5} suffix="%" />}
      />
    </Section>
  );
}

function ImpoundFields({
  draft,
  set,
  data,
  currency,
}: {
  draft: ImpoundLocation;
  set: (p: Record<string, unknown>) => void;
  data: AdminOpenData;
  currency: string;
}) {
  return (
    <Section title={t('Impound')}>
      <div className="nz-admin-form__block">
        <div className="nz-admin-form__label-row">
          <span className="nz-admin-form__label">{t('Impound jobs')}</span>
          <InfoDot text={t('Members of these jobs may impound vehicles here and release them. Leave empty to only allow admins.')} />
        </div>
        <RulesEditor value={draft.jobs} onChange={(jobs) => set({ jobs })} options={data.jobs} noun="job" emptyText={t('No jobs yet — only admins can impound here')} />
      </div>
      <div className="nz-admin-form__grid is-3">
        <Field label={t('Society fund')} hint={t('Account receiving the fees (empty = none)')}>
          <Input
            value={draft.society}
            onChange={(society) => set({ society: society.replace(/[^\w-]/g, '') })}
            mono
            maxLength={64}
            placeholder={t('e.g. police')}
          />
        </Field>
        <Field label={t('Default fee')} hint={t('Pre-filled when impounding')}>
          <NumberInput value={draft.defaultFee} onChange={(defaultFee) => set({ defaultFee: Math.round(defaultFee) })} min={0} max={10000000} step={50} prefix={currency} />
        </Field>
        <Field label={t('Default hold time')} hint={draft.defaultHours === 0 ? t('0 = retrievable right away') : t('Hours before release')}>
          <NumberInput value={draft.defaultHours} onChange={(defaultHours) => set({ defaultHours })} min={0} max={720} step={1} suffix={t('h')} />
        </Field>
      </div>
    </Section>
  );
}
