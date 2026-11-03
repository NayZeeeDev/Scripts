/**
 * InteractionFields — the "Interaction" section of the location editor.
 *
 * API
 *   <InteractionFields draft globalMode onChange(interaction) />
 *   - draft: the location being edited (kind, vehicle type, access mode, points are read to
 *     preview what players get).
 *   - globalMode: settings.interface.interaction (what 'default' resolves to).
 *
 * Parts: the mode Segmented (Default / Press E / Target / Both) with an explainer of the
 * selected mode and, when third-eye applies, the target options players will see here
 * (derived from the location: open / hangar / marina, enter interior, for sale, impound,
 * store). Then the NPC: toggle, ped model (validated like the server: [A-Za-z0-9_], max 32,
 * empty = Config.Peds.defaultModel), quick picks, scenario, where it stands / faces, and a
 * warning with a one-click fix when the mode would never show it.
 */
import { useRef } from 'react';
import type { ReactNode } from 'react';
import { Badge, Button, Chip, Field, Icon, InfoDot, Input, Kbd, Segmented, Select, Toggle, cx } from '@/components/ui';
import type { IconName } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { InterfaceSettings, Location, LocationInteraction, Vec3 } from '@/lib/types';
import { coordsText } from '../shared/labels';
import { PED_DEFAULT_MODEL, PED_DEFAULT_SCENARIO, PED_MODEL_MAX, PED_MODEL_PRESETS, PED_SCENARIOS, normalizeInteraction } from './defaults';
import './interaction.css';

type Mode = LocationInteraction['mode'];
type Effective = InterfaceSettings['interaction'];
type Ped = NonNullable<LocationInteraction['ped']>;

export interface InteractionFieldsProps {
  draft: Location;
  globalMode: Effective;
  onChange: (interaction: LocationInteraction) => void;
}

const modeName = (m: Effective) => (m === 'target' ? t('Target') : m === 'both' ? t('Both') : t('Press E'));

const usesTarget = (m: Effective) => m === 'target' || m === 'both';

/** Same rule as the server (server/locations.lua). */
const cleanModel = (v: string) => v.replace(/[^A-Za-z0-9_]/g, '').slice(0, PED_MODEL_MAX);

interface TargetOption {
  label: string;
  icon: IconName;
  /** who sees it, when not everyone */
  who?: string;
}

/** The third-eye options client/points.lua builds for this location. */
function targetOptions(draft: Location): TargetOption[] {
  if (draft.kind === 'impound') return [{ label: t('Open impound'), icon: 'impound' }];
  const vt = draft.vehicleType;
  const open =
    vt === 'air' ? t('Open hangar') : vt === 'sea' ? t('Open marina') : draft.kind === 'job' ? t('Open job garage') : t('Open garage');
  const openIcon: IconName = vt === 'air' ? 'plane' : vt === 'sea' ? 'boat' : 'garage';
  const access = draft.access.mode;
  const owners = draft.kind === 'private' ? t('owners') : undefined;
  const list: TargetOption[] = [];
  if (draft.kind === 'private' && draft.purchasable) list.push({ label: t('View garage for sale'), icon: 'cart', who: t('everyone else') });
  if (access !== 'interior') list.push({ label: open, icon: openIcon, who: owners });
  if (access !== 'quick') list.push({ label: t('Enter interior'), icon: 'door', who: owners });
  list.push({ label: t('Store vehicle'), icon: 'parking', who: t('in or next to a vehicle') });
  return list;
}

/** GTA heading (0 = north, counter-clockwise) from `from` looking at `to`. */
function headingTo(from: Vec3, to: Vec3): number | null {
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  if (dx * dx + dy * dy < 0.01) return null;
  const h = (Math.atan2(dy, dx) * 180) / Math.PI - 90;
  return ((h % 360) + 360) % 360;
}

export function InteractionFields({ draft, globalMode, onChange }: InteractionFieldsProps) {
  const value = normalizeInteraction(draft.interaction);
  const { mode, ped } = value;
  const effective: Effective = mode === 'default' ? globalMode : mode;
  const target = usesTarget(effective);
  // Remember the NPC set-up while it is switched off, so toggling back restores it.
  const lastPed = useRef<Ped>(ped ?? { model: '', scenario: PED_DEFAULT_SCENARIO });
  if (ped) lastPed.current = ped;

  const setMode = (next: Mode) => onChange({ ...value, mode: next });
  const setPed = (next: Ped | null) => onChange({ ...value, ped: next });

  const explain: Record<Mode, { title: ReactNode; text: string; badge: ReactNode }> = {
    default: {
      title: t('Server default'),
      text: t('Follows Settings → Interface → Interaction, so this location changes with it.'),
      badge: (
        <Badge tone="neutral" size="sm" icon="sliders">
          {t('Now: {mode}', { mode: modeName(globalMode) })}
        </Badge>
      ),
    },
    prompt: {
      title: t('Press E'),
      text:
        draft.kind === 'impound'
          ? t('Players press the key inside the marker to open the impound.')
          : t('Players press the key inside the marker to open the menu, and while driving inside the zone to park.'),
      badge: null,
    },
    target: {
      title: t('Target'),
      text: t('Players use third-eye (ox_target / qb-target) on the point or the NPC. Drivers still park with the key prompt.'),
      badge: null,
    },
    both: {
      title: t('Press E and target'),
      text: t('The key prompt and the third-eye options both work here: players use whichever they prefer.'),
      badge: null,
    },
  };
  const info = explain[mode];

  const openPoint = draft.openPoints[0]?.coords;
  const spawn = draft.spawnPoints[0];
  const facing = openPoint && spawn ? headingTo(openPoint, spawn) : null;
  const options = targetOptions(draft);
  const scenarioOptions = PED_SCENARIOS.map((s) => ({ value: s.value, label: t(s.label) }));
  const pedWarning = !!ped && !target;

  return (
    <div className="nz-admin-interaction">
      {/* ── mode ── */}
      <div className="nz-admin-form__block">
        <div className="nz-admin-form__label-row">
          <span className="nz-admin-form__label">{t('How players interact here')}</span>
          <InfoDot text={t('Without ox_target or qb-target running, every location falls back to the key prompt.')} />
        </div>
        <Segmented<Mode>
          full
          value={mode}
          onChange={setMode}
          options={[
            { value: 'default', label: t('Default') },
            { value: 'prompt', label: t('Press E') },
            { value: 'target', label: t('Target') },
            { value: 'both', label: t('Both') },
          ]}
        />
        <div className={cx('nz-admin-interaction__explain', target && 'is-target')}>
          <span className="nz-admin-interaction__glyph" aria-hidden="true">
            {effective === 'prompt' ? (
              <Kbd>E</Kbd>
            ) : effective === 'target' ? (
              <Icon name="eye" size={16} strokeWidth={1.7} />
            ) : (
              <>
                <Kbd size="sm">E</Kbd>
                <Icon name="eye" size={13} strokeWidth={1.8} />
              </>
            )}
          </span>
          <div className="nz-admin-interaction__explain-text">
            <div className="nz-admin-interaction__explain-head">
              <b>{info.title}</b>
              {info.badge}
            </div>
            <p>{info.text}</p>
            {target ? (
              <div className="nz-admin-interaction__options" aria-label={t('Third-eye options')}>
                <span className="nz-admin-interaction__caption">{t('Third-eye options')}</span>
                <ul>
                  {options.map((o) => (
                    <li key={o.label} title={o.who ? t('Shown to {who}', { who: o.who }) : undefined}>
                      <Icon name={o.icon} size={12} strokeWidth={1.8} />
                      <span>{o.label}</span>
                      {o.who && <small>{o.who}</small>}
                    </li>
                  ))}
                </ul>
              </div>
            ) : (
              <p className="nz-admin-interaction__muted">{t('No third-eye options: players see the key prompt in the marker.')}</p>
            )}
          </div>
        </div>
      </div>

      {/* ── NPC ── */}
      <div className={cx('nz-admin-interaction__npc', !!ped && 'is-on')}>
        <Toggle
          checked={!!ped}
          onChange={(on) => setPed(on ? lastPed.current : null)}
          label={draft.kind === 'impound' ? t('Impound NPC') : t('Garage NPC')}
          description={t('Someone stands at the first open interaction and carries the third-eye options, instead of an invisible zone.')}
        />
        {ped && (
          <div className="nz-admin-interaction__npc-body">
            <div className="nz-admin-form__grid">
              <Field
                label={t('Ped model')}
                hint={ped.model ? t('GTA ped model name') : t('Empty uses the default ({model})', { model: PED_DEFAULT_MODEL })}
              >
                <Input
                  value={ped.model}
                  onChange={(model) => setPed({ ...ped, model: cleanModel(model) })}
                  placeholder={PED_DEFAULT_MODEL}
                  maxLength={PED_MODEL_MAX}
                  icon="user"
                  mono
                />
              </Field>
              <Field
                label={t('Scenario')}
                hint={<span className="nz-admin-interaction__mono">{ped.scenario || t('Stands still')}</span>}
              >
                <Select<string> value={ped.scenario} onChange={(scenario) => setPed({ ...ped, scenario })} options={scenarioOptions} />
              </Field>
            </div>
            <div className="nz-admin-interaction__presets">
              <span className="nz-admin-interaction__caption">{t('Quick picks')}</span>
              <div className="nz-admin-interaction__chips">
                {PED_MODEL_PRESETS.map((p) => (
                  <Chip
                    key={p.value}
                    active={(ped.model || PED_DEFAULT_MODEL) === p.value}
                    onClick={() => setPed({ ...ped, model: p.value })}
                  >
                    {t(p.label)}
                  </Chip>
                ))}
              </div>
            </div>
            <div className={cx('nz-admin-interaction__spot', !openPoint && 'is-empty')}>
              <span className="nz-admin-interaction__spot-icon">
                <Icon name="pin" size={14} strokeWidth={1.7} />
              </span>
              <span className="nz-admin-interaction__spot-text">
                <b>{openPoint ? t('Stands at open interaction #1') : t('Place an open interaction first')}</b>
                <small>
                  {openPoint
                    ? `${coordsText(openPoint)}${facing !== null ? ` · ${t('faces spawn point #1')} (${Math.round(facing)}°)` : ''}`
                    : t('The NPC appears at the first open interaction.')}
                </small>
              </span>
            </div>
          </div>
        )}
        {pedWarning ? (
          <div className="nz-admin-interaction__warn" role="status">
            <Icon name="warning" size={13} strokeWidth={1.8} />
            <span>
              {t('The NPC only appears with Target or Both. This location uses {mode}.', {
                mode: mode === 'default' ? `${t('Default')} · ${modeName(globalMode)}` : modeName(effective),
              })}
            </span>
            <Button size="sm" variant="line" icon="eye" onClick={() => setMode('target')}>
              {t('Use Target')}
            </Button>
          </div>
        ) : (
          <p className="nz-admin-form__hint is-block">
            <Icon name="info" size={12} strokeWidth={1.8} />
            {t('The NPC needs Target or Both mode and is only created for players nearby.')}
          </p>
        )}
      </div>
    </div>
  );
}
