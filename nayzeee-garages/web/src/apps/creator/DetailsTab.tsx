/**
 * Interior creator — Details tab: name, entry point (pick / teleport, detected GTA
 * interior), IPL profile and its options (each change reloads the profile in game).
 */
import { t } from '@/lib/i18n';
import { Button, Field, Icon, IconButton, InfoDot, Input, Select, Spinner, cx } from '@/components/ui';
import type { SelectOption } from '@/components/ui';
import { CoordCard, SectionHead, isSet } from './parts';
import type { CreatorTab, TabProps } from './parts';
import type { IconName } from '@/components/ui';

const MANUAL = '';

export function DetailsTab({
  draft,
  patch,
  run,
  pending,
  errors,
  profiles,
  gtaName,
  setGtaName,
  onSubmit,
  autoFocusName,
  goTo,
}: TabProps & {
  onSubmit: () => void;
  autoFocusName: boolean;
  goTo: (tab: CreatorTab) => void;
}) {
  const busy = pending !== null;
  const profile = profiles.find((p) => p.key === draft.profile) ?? null;
  const entrySet = isSet(draft.entry);

  const pickEntry = async () => {
    const res = await run('pickEntry', 'creator:pickEntry', {});
    if (!res?.ok || !res.data) return;
    patch({ entry: res.data.entry, gtaInteriorId: res.data.gtaInteriorId ?? null });
    setGtaName(res.data.gtaInteriorName ?? null);
  };

  const teleport = () => {
    if (entrySet) void run('teleport', 'creator:teleport', { coords: draft.entry });
  };

  const applyProfile = async (key: string, options: Record<string, string>) => {
    const res = await run('applyProfile', 'creator:applyProfile', { profile: key === MANUAL ? null : key, options });
    if (!res?.ok) return;
    const entry = res.data?.entry ?? null;
    patch({
      profile: key === MANUAL ? null : key,
      options,
      ...(entry ? { entry, gtaInteriorId: null } : {}),
    });
    if (entry) setGtaName(null);
  };

  const chooseProfile = (key: string) => {
    if (key === (draft.profile ?? MANUAL)) return;
    const next = profiles.find((p) => p.key === key);
    const options: Record<string, string> = {};
    next?.options.forEach((o) => {
      options[o.key] = o.default;
    });
    void applyProfile(key, options);
  };

  const chooseOption = (optKey: string, value: string) => {
    if (!profile || draft.options[optKey] === value) return;
    void applyProfile(profile.key, { ...draft.options, [optKey]: value });
  };

  const profileOptions: SelectOption<string>[] = [
    { value: MANUAL, label: t('Manual coordinates'), hint: t('Any place on the map, no IPL loading'), icon: 'pin' },
    ...profiles.map((p) => ({
      value: p.key,
      label: p.label,
      hint: p.slots ? t('Fits {count} vehicles', { count: p.slots }) : undefined,
      icon: 'building' as const,
    })),
  ];

  const detectedLabel = gtaName || profile?.label || t('GTA interior');

  type Check = { key: string; tab: CreatorTab; icon: IconName; label: string; value: string; state: 'done' | 'missing' | 'optional' };
  const pts = draft.cutscene.points.length;
  const checklist: Check[] = [
    {
      key: 'entry',
      tab: 'details',
      icon: 'pin',
      label: t('Entry point'),
      value: entrySet ? t('Set') : t('Required'),
      state: entrySet ? 'done' : 'missing',
    },
    {
      key: 'slots',
      tab: 'vehicles',
      icon: 'car',
      label: t('Vehicle positions'),
      value: draft.slots.length ? t('{count} placed', { count: draft.slots.length }) : t('Required'),
      state: draft.slots.length ? 'done' : 'missing',
    },
    {
      key: 'cutscene',
      tab: 'cutscene',
      icon: 'camera',
      label: t('Entry cutscene'),
      value: draft.cutscene.enabled ? t('{count} camera points', { count: pts }) : t('Off'),
      state: draft.cutscene.enabled && pts > 0 ? 'done' : 'optional',
    },
    {
      key: 'exit',
      tab: 'exit',
      icon: 'door',
      label: t('Exit point'),
      value: isSet(draft.exit) ? t('Set') : t('Uses the entry'),
      state: isSet(draft.exit) ? 'done' : 'optional',
    },
  ];

  return (
    <div className="nz-creator__stack">
      <Field label={t('Name')} required error={errors.name}>
        <Input
          value={draft.name}
          onChange={(v) => patch({ name: v })}
          placeholder={t('e.g. Executive Collection')}
          maxLength={48}
          icon="edit"
          autoFocus={autoFocusName}
          onEnter={onSubmit}
        />
      </Field>

      <Field
        label={t('Entry point')}
        required
        aside={<InfoDot text={t('Where players appear when they go inside. Stand on the spot, face the way players should look, then use your current position.')} side="right" />}
        error={errors.entry}
      >
        <div className="nz-creator__point">
          <CoordCard value={draft.entry} invalid={!!errors.entry} placeholder={t('No entry point yet')} />
          <div className="nz-creator__point-actions">
            <Button
              size="sm"
              icon="pin"
              loading={pending === 'pickEntry'}
              disabled={busy}
              onClick={() => void pickEntry()}
              className="nz-creator__grow"
            >
              {t('Use current position')}
            </Button>
            <IconButton
              icon="route"
              size="sm"
              variant="line"
              label={t('Teleport to the entry point')}
              disabled={busy || !entrySet}
              onClick={teleport}
            />
          </div>
          {pending === 'teleport' && (
            <div className="nz-creator__detect">
              <Spinner size={12} />
              <span>{t('Teleporting…')}</span>
            </div>
          )}
          {pending !== 'teleport' &&
            (draft.gtaInteriorId ? (
              <div className="nz-creator__detect is-found">
                <Icon name="checkCircle" size={13} strokeWidth={1.9} />
                <span className="nz-creator__detect-name">{detectedLabel}</span>
                <b className="nz-mono">{draft.gtaInteriorId}</b>
              </div>
            ) : (
              <div className="nz-creator__detect">
                <Icon name="info" size={13} strokeWidth={1.8} />
                <span>
                  {profile
                    ? t('Using the {name} profile', { name: profile.label })
                    : t('No GTA interior detected at the entry point')}
                </span>
              </div>
            ))}
        </div>
      </Field>

      <Field
        label={t('Interior profile')}
        aside={<InfoDot text={t('A profile loads the map files (IPLs) and decorations a GTA interior needs. Choose manual coordinates for any other place.')} side="right" />}
        hint={
          profile
            ? profile.coords
              ? t('Choosing a profile takes you to its entry point.')
              : t('Loaded around your entry point.')
            : undefined
        }
      >
        <Select<string>
          value={draft.profile ?? MANUAL}
          onChange={chooseProfile}
          options={profileOptions}
          icon="layers"
          disabled={busy}
        />
      </Field>

      {profile && profile.options.length > 0 && (
        <div className="nz-creator__grid2">
          {profile.options.map((o) => (
            <Field key={o.key} label={o.label}>
              <Select<string>
                size="sm"
                value={draft.options[o.key] ?? o.default}
                onChange={(v) => chooseOption(o.key, v)}
                options={o.choices.map((c) => ({ value: c.value, label: c.label }))}
                disabled={busy}
              />
            </Field>
          ))}
        </div>
      )}
      {pending === 'applyProfile' && (
        <div className="nz-creator__detect">
          <Spinner size={12} />
          <span>{t('Loading the interior…')}</span>
        </div>
      )}

      <div className="nz-creator__block">
        <SectionHead title={t('Overview')} />
        <ul className="nz-creator__checklist">
          {checklist.map((c) => (
            <li key={c.key}>
              <button type="button" className={cx('nz-creator__check', `is-${c.state}`)} onClick={() => goTo(c.tab)}>
                <span className="nz-creator__check-dot">
                  {c.state === 'done' ? <Icon name="check" size={10} strokeWidth={3} /> : null}
                </span>
                <Icon name={c.icon} size={14} strokeWidth={1.7} className="nz-creator__check-icon" />
                <span className="nz-creator__check-label">{c.label}</span>
                <span className="nz-creator__check-value">{c.value}</span>
                <Icon name="chevronRight" size={13} strokeWidth={1.8} className="nz-creator__check-go" />
              </button>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
