/**
 * Settings page layout: tabs → two columns of panels → option rows. Every field of the
 * `Settings` type has exactly one row here (checked by `ALL_ROW_IDS` in the dev harness).
 *
 * A row knows its label, helper text and how to render its control from the draft. `disabled`
 * dims dependent rows (e.g. body deformation needs vehicle damage); search matches the label,
 * helper text and extra keywords.
 */
import type { ReactNode } from 'react';
import { Button, NumberInput, Segmented, Select, Slider, Toggle } from '@/components/ui';
import type { IconName } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { AdminOpenData, AdminPage, Settings } from '@/lib/types';
import { AccentField, AccentPreview, CurrencyField, ImageUrlField, ImpoundLots } from './fields';

export type TabId = 'vehicles' | 'garages' | 'transfers' | 'impound' | 'interface';

export interface Ctx {
  s: Settings;
  set: <S extends keyof Settings, K extends keyof Settings[S]>(section: S, key: K, value: Settings[S][K]) => void;
  data: AdminOpenData;
  currency: string;
  errors: Partial<Record<string, string>>;
  save: () => void;
  go: (page: AdminPage) => void;
}

export interface RowDef {
  /** "section.key" of the Settings field. */
  id: string;
  label: () => string;
  description: (c: Ctx) => ReactNode;
  /** Extra words the search box matches. */
  keywords?: () => string;
  stacked?: boolean;
  disabled?: (s: Settings) => boolean;
  control: (c: Ctx, disabled: boolean) => ReactNode;
}

export interface PanelDef {
  id: string;
  title: () => string;
  icon: IconName;
  rows: RowDef[];
  /** Extra content under the rows (not searchable). */
  footer?: (c: Ctx) => ReactNode;
}

export interface TabDef {
  id: TabId;
  label: () => string;
  icon: IconName;
  columns: PanelDef[][];
}

/* ── control helpers ─────────────────────────────────────────────────── */

type BoolKeys<S extends keyof Settings> = { [K in keyof Settings[S]]: Settings[S][K] extends boolean ? K : never }[keyof Settings[S]];
type NumKeys<S extends keyof Settings> = { [K in keyof Settings[S]]: Settings[S][K] extends number ? K : never }[keyof Settings[S]];

function toggle<S extends keyof Settings>(section: S, key: BoolKeys<S>) {
  return (c: Ctx, disabled: boolean) => (
    <Toggle
      checked={!!c.s[section][key]}
      disabled={disabled}
      onChange={(b) => c.set(section, key, b as Settings[S][BoolKeys<S>])}
    />
  );
}

function money<S extends keyof Settings>(section: S, key: NumKeys<S>, step = 50) {
  return (c: Ctx, disabled: boolean) => (
    <NumberInput
      className="nz-aset-num"
      value={Number(c.s[section][key]) || 0}
      min={0}
      max={10000000}
      step={step}
      prefix={c.currency}
      disabled={disabled}
      onEnter={c.save}
      onChange={(n) => c.set(section, key, Math.max(0, Math.round(n)) as Settings[S][NumKeys<S>])}
    />
  );
}

function count<S extends keyof Settings>(section: S, key: NumKeys<S>, min: number, max: number, suffix?: string, step = 1, int = true) {
  return (c: Ctx, disabled: boolean) => (
    <NumberInput
      className="nz-aset-num"
      value={Number(c.s[section][key]) || 0}
      min={min}
      max={max}
      step={step}
      suffix={suffix}
      disabled={disabled}
      onEnter={c.save}
      onChange={(n) => {
        const v = Math.min(max, Math.max(min, int ? Math.round(n) : Math.round(n * 10) / 10));
        c.set(section, key, v as Settings[S][NumKeys<S>]);
      }}
    />
  );
}

/* ── tabs ────────────────────────────────────────────────────────────── */

export const TABS: TabDef[] = [
  {
    id: 'vehicles',
    label: () => t('Vehicles'),
    icon: 'car',
    columns: [
      [
        {
          id: 'spawning',
          title: () => t('Spawning and storing'),
          icon: 'parking',
          rows: [
            {
              id: 'vehicles.spawnOutside',
              label: () => t('Spawn outside the vehicle'),
              description: () => t('Players are placed next to the vehicle instead of in the driver seat.'),
              control: toggle('vehicles', 'spawnOutside'),
            },
            {
              id: 'vehicles.saveMods',
              label: () => t('Save vehicle modifications'),
              description: () => t('Paint, upgrades, wheels and extras are saved every time a vehicle is stored.'),
              keywords: () => t('props tuning upgrades'),
              control: toggle('vehicles', 'saveMods'),
            },
            {
              id: 'vehicles.checkModel',
              label: () => t('Check vehicle model'),
              description: () => t('Verifies the stored model before accepting a vehicle, so swapped vehicles cannot be stored.'),
              keywords: () => t('anti cheat exploit'),
              control: toggle('vehicles', 'checkModel'),
            },
            {
              id: 'vehicles.serverSpawn',
              label: () => t('Spawn vehicles on the server'),
              description: () => t('Uses server-created vehicles. Test with your server’s vehicle scripts before enabling.'),
              keywords: () => t('onesync entity'),
              control: toggle('vehicles', 'serverSpawn'),
            },
            {
              id: 'vehicles.trailers',
              label: () => t('Store trailers with their vehicle'),
              description: () => t('A trailer attached while storing is saved and comes back with the vehicle.'),
              control: toggle('vehicles', 'trailers'),
            },
            {
              id: 'vehicles.giveKeys',
              label: () => t('Give keys on spawn'),
              description: () => t('Hands the keys to the player through the detected keys resource.'),
              keywords: () => t('vehicle keys lock'),
              control: toggle('vehicles', 'giveKeys'),
            },
          ],
        },
      ],
      [
        {
          id: 'damage',
          title: () => t('Vehicle damage'),
          icon: 'wrench',
          rows: [
            {
              id: 'vehicles.saveDamage',
              label: () => t('Save vehicle damage'),
              description: () => t('Engine, body and tank health, doors, windows and tyres are restored on spawn.'),
              keywords: () => t('health condition'),
              control: toggle('vehicles', 'saveDamage'),
            },
            {
              id: 'vehicles.saveDeformation',
              label: () => t('Save body deformation'),
              description: (c) =>
                c.s.vehicles.saveDamage ? t('Dents and bent panels look the same after the vehicle is stored.') : t('Requires Save vehicle damage.'),
              keywords: () => t('dents damage'),
              disabled: (s) => !s.vehicles.saveDamage,
              control: (c, disabled) => (
                <Toggle checked={c.s.vehicles.saveDamage && c.s.vehicles.saveDeformation} disabled={disabled} onChange={(b) => c.set('vehicles', 'saveDeformation', b)} />
              ),
            },
            {
              id: 'vehicles.needsServiceBelow',
              label: () => t('Needs service below'),
              description: () => t('Vehicles with less engine health than this show a needs-service badge. 0 turns the badge off.'),
              keywords: () => t('engine health badge'),
              stacked: true,
              control: (c) => (
                <Slider
                  value={c.s.vehicles.needsServiceBelow}
                  onChange={(n) => c.set('vehicles', 'needsServiceBelow', Math.round(n))}
                  min={0}
                  max={100}
                  step={5}
                  format={(n) => (n === 0 ? t('Off') : `${n}%`)}
                />
              ),
            },
          ],
        },
      ],
    ],
  },
  {
    id: 'garages',
    label: () => t('Garages'),
    icon: 'garage',
    columns: [
      [
        {
          id: 'retrieving',
          title: () => t('Using garages'),
          icon: 'garage',
          rows: [
            {
              id: 'garages.retrieveMode',
              label: () => t('Take vehicles out'),
              description: (c) =>
                c.s.garages.retrieveMode === 'anywhere'
                  ? t('From any garage of the right vehicle type.')
                  : t('Only from the garage the vehicle was stored in. Others show where it is parked.'),
              keywords: () => t('retrieve anywhere last garage'),
              control: (c) => (
                <Segmented<Settings['garages']['retrieveMode']>
                  size="sm"
                  value={c.s.garages.retrieveMode}
                  onChange={(v) => c.set('garages', 'retrieveMode', v)}
                  options={[
                    { value: 'last', label: t('Last garage') },
                    { value: 'anywhere', label: t('Anywhere') },
                  ]}
                />
              ),
            },
            {
              id: 'garages.storeOnlyOwned',
              label: () => t('Only store own vehicles'),
              description: () => t('Players can store vehicles they own, that are shared with them, or of their job.'),
              keywords: () => t('stolen npc'),
              control: toggle('garages', 'storeOnlyOwned'),
            },
            {
              id: 'garages.suggestWhenFull',
              label: () => t('Suggest a garage when full'),
              description: () => t('Offers directions to the nearest garage with free space.'),
              keywords: () => t('capacity waypoint'),
              control: toggle('garages', 'suggestWhenFull'),
            },
            {
              id: 'garages.showBlips',
              label: () => t('Show map blips'),
              description: () => t('Shows garages on the map. Each location can still hide its own blip.'),
              keywords: () => t('map icon'),
              control: toggle('garages', 'showBlips'),
            },
            {
              id: 'garages.maxDistance',
              label: () => t('Interaction distance'),
              description: () => t('How close players must be to a garage point for any garage action (5 – 100 m).'),
              keywords: () => t('range radius security'),
              control: count('garages', 'maxDistance', 5, 100, 'm', 1, false),
            },
          ],
        },
      ],
      [
        {
          id: 'restart',
          title: () => t('Server restart'),
          icon: 'refresh',
          rows: [
            {
              id: 'garages.outOnRestart',
              label: () => t('Vehicles left out'),
              description: () => t('What happens to vehicles that are still out when the server starts.'),
              keywords: () => t('restart reboot'),
              control: (c) => (
                <Select<Settings['garages']['outOnRestart']>
                  size="sm"
                  className="nz-aset-select"
                  value={c.s.garages.outOnRestart}
                  onChange={(v) => {
                    c.set('garages', 'outOnRestart', v);
                    if (v === 'impound' && c.s.garages.restartImpound === null) {
                      const first = c.data.locations.find((l) => l.kind === 'impound');
                      if (first && first.id !== null) c.set('garages', 'restartImpound', first.id);
                    }
                  }}
                  options={[
                    { value: 'garage', label: t('Back to their garage'), icon: 'garage' },
                    { value: 'impound', label: t('Impounded'), icon: 'impound' },
                    { value: 'keep', label: t('Stay out'), hint: t('Recover fee applies'), icon: 'route' },
                  ]}
                />
              ),
            },
            {
              id: 'garages.restartImpound',
              label: () => t('Restart impound'),
              description: (c) =>
                c.s.garages.outOnRestart !== 'impound'
                  ? t('Only used when vehicles left out are impounded.')
                  : c.errors['garages.restartImpound'] ?? t('Impound lot that receives them, with the recover fee as release fee.'),
              keywords: () => t('impound lot'),
              disabled: (s) => s.garages.outOnRestart !== 'impound',
              control: (c, disabled) => {
                const impounds = c.data.locations.filter((l) => l.kind === 'impound' && l.id !== null);
                return impounds.length ? (
                  <Select<number>
                    size="sm"
                    className="nz-aset-select"
                    value={c.s.garages.restartImpound}
                    onChange={(v) => c.set('garages', 'restartImpound', v)}
                    options={impounds.map((l) => ({ value: l.id as number, label: l.name, icon: 'impound' as const, hint: l.enabled ? undefined : t('Disabled') }))}
                    placeholder={t('Choose an impound')}
                    disabled={disabled}
                  />
                ) : (
                  <Button size="sm" icon="plus" disabled={disabled} onClick={() => c.go('impounds')}>
                    {t('Create an impound')}
                  </Button>
                );
              },
            },
            {
              id: 'garages.recoverFee',
              label: () => t('Recover fee'),
              description: () => t('Paid to get back a vehicle that is out but no longer exists in the world. 0 = free.'),
              keywords: () => t('lost destroyed price'),
              control: money('garages', 'recoverFee'),
            },
          ],
        },
        {
          id: 'economy',
          title: () => t('Economy'),
          icon: 'money',
          rows: [
            {
              id: 'economy.account',
              label: () => t('Pay from'),
              description: (c) =>
                c.s.economy.account === 'both'
                  ? t('Cash first, then the bank account. Used for every fee and purchase.')
                  : t('Account used for every fee and purchase (transfers, impound, recover, private garages).'),
              keywords: () => t('money bank cash account payment'),
              control: (c) => (
                <Segmented<Settings['economy']['account']>
                  size="sm"
                  value={c.s.economy.account}
                  onChange={(v) => c.set('economy', 'account', v)}
                  options={[
                    { value: 'bank', label: t('Bank') },
                    { value: 'cash', label: t('Cash') },
                    { value: 'both', label: t('Both') },
                  ]}
                />
              ),
            },
          ],
        },
      ],
    ],
  },
  {
    id: 'transfers',
    label: () => t('Transfers'),
    icon: 'transfer',
    columns: [
      [
        {
          id: 'garageTransfers',
          title: () => t('Between garages'),
          icon: 'garage',
          rows: [
            {
              id: 'transfers.garageEnabled',
              label: () => t('Move to another garage'),
              description: () => t('Players can send a stored vehicle to another garage they can use.'),
              control: toggle('transfers', 'garageEnabled'),
            },
            {
              id: 'transfers.garageFee',
              label: () => t('Garage transfer fee'),
              description: (c) => (c.s.transfers.garageEnabled ? t('0 = free.') : t('Requires Move to another garage.')),
              disabled: (s) => !s.transfers.garageEnabled,
              control: money('transfers', 'garageFee'),
            },
          ],
        },
        {
          id: 'sharing',
          title: () => t('Sharing'),
          icon: 'key',
          rows: [
            {
              id: 'transfers.shareEnabled',
              label: () => t('Share vehicles'),
              description: () => t('Owners can let other players drive a vehicle without giving it away.'),
              keywords: () => t('keys friends'),
              control: toggle('transfers', 'shareEnabled'),
            },
            {
              id: 'transfers.maxShares',
              label: () => t('Players per vehicle'),
              description: (c) => (c.s.transfers.shareEnabled ? t('How many players one vehicle can be shared with.') : t('Requires Share vehicles.')),
              disabled: (s) => !s.transfers.shareEnabled,
              control: count('transfers', 'maxShares', 0, 50),
            },
          ],
        },
      ],
      [
        {
          id: 'playerTransfers',
          title: () => t('Between players'),
          icon: 'users',
          rows: [
            {
              id: 'transfers.playerEnabled',
              label: () => t('Give to another player'),
              description: () => t('Owners can transfer a vehicle to another player.'),
              keywords: () => t('ownership gift'),
              control: toggle('transfers', 'playerEnabled'),
            },
            {
              id: 'transfers.playerFee',
              label: () => t('Player transfer fee'),
              description: (c) => (c.s.transfers.playerEnabled ? t('Paid by the current owner. 0 = free.') : t('Requires Give to another player.')),
              disabled: (s) => !s.transfers.playerEnabled,
              control: money('transfers', 'playerFee'),
            },
            {
              id: 'transfers.sellEnabled',
              label: () => t('Sell to players'),
              description: () => t('Owners can offer a vehicle to a nearby player for a price; the buyer has to accept.'),
              keywords: () => t('sale price buyer'),
              control: toggle('transfers', 'sellEnabled'),
            },
          ],
        },
      ],
    ],
  },
  {
    id: 'impound',
    label: () => t('Impound'),
    icon: 'impound',
    columns: [
      [
        {
          id: 'impoundDefaults',
          title: () => t('Defaults'),
          icon: 'impound',
          rows: [
            {
              id: 'impound.defaultFee',
              label: () => t('Default release fee'),
              description: () => t('Suggested in the impound form. Each impound lot can set its own.'),
              keywords: () => t('price cost'),
              control: money('impound', 'defaultFee'),
            },
            {
              id: 'impound.defaultHours',
              label: () => t('Default impound time'),
              description: () => t('Hours before the owner can get the vehicle back. 0 = right away.'),
              keywords: () => t('duration wait hours'),
              control: count('impound', 'defaultHours', 0, 720, t('h'), 1, false),
            },
          ],
        },
      ],
      [
        {
          id: 'impoundStaff',
          title: () => t('Staff'),
          icon: 'shield',
          rows: [
            {
              id: 'impound.staffBypassFee',
              label: () => t('Staff release for free'),
              description: () => t('Impound staff can take vehicles out without paying the fee.'),
              keywords: () => t('police mechanic job'),
              control: toggle('impound', 'staffBypassFee'),
            },
          ],
        },
        {
          id: 'impoundLots',
          title: () => t('Impound lots'),
          icon: 'map',
          rows: [],
          footer: (c) => <ImpoundLots c={c} />,
        },
      ],
    ],
  },
  {
    id: 'interface',
    label: () => t('Interface'),
    icon: 'palette',
    columns: [
      [
        {
          id: 'look',
          title: () => t('Look'),
          icon: 'palette',
          rows: [
            {
              id: 'interface.accent',
              label: () => t('Accent colour'),
              description: () => t('Buttons, highlights and gauges in every menu. Players see it after saving.'),
              keywords: () => t('color theme brand teal'),
              stacked: true,
              control: (c) => <AccentField value={c.s.interface.accent} onChange={(v) => c.set('interface', 'accent', v)} />,
            },
            {
              id: 'interface.defaultView',
              label: () => t('Default garage view'),
              description: () => t('How the garage menu opens. Players can switch, and it is remembered per player.'),
              keywords: () => t('grid list layout'),
              control: (c) => (
                <Segmented<Settings['interface']['defaultView']>
                  size="sm"
                  value={c.s.interface.defaultView}
                  onChange={(v) => c.set('interface', 'defaultView', v)}
                  options={[
                    { value: 'grid', label: t('Grid'), icon: 'grid' },
                    { value: 'list', label: t('List'), icon: 'list' },
                  ]}
                />
              ),
            },
          ],
          footer: (c) => <AccentPreview value={c.s.interface.accent} />,
        },
      ],
      [
        {
          id: 'images',
          title: () => t('Vehicle images'),
          icon: 'camera',
          rows: [
            {
              id: 'interface.showImages',
              label: () => t('Show vehicle images'),
              description: () => t('When off, every vehicle uses a silhouette of its type.'),
              keywords: () => t('pictures photos'),
              control: toggle('interface', 'showImages'),
            },
            {
              id: 'interface.imageUrl',
              label: () => t('Image URL'),
              description: () => t('{model} is replaced by the lower-case model name. Missing images fall back to web/public/vehicles, then a silhouette.', { model: '{model}' }),
              keywords: () => t('link template cdn'),
              stacked: true,
              disabled: (s) => !s.interface.showImages,
              control: (c, disabled) => (
                <ImageUrlField value={c.s.interface.imageUrl} onChange={(v) => c.set('interface', 'imageUrl', v)} disabled={disabled} onEnter={c.save} />
              ),
            },
          ],
        },
        {
          id: 'units',
          title: () => t('Units and controls'),
          icon: 'sliders',
          rows: [
            {
              id: 'interface.distanceUnit',
              label: () => t('Distance unit'),
              description: () => t('Used for mileage and distances.'),
              keywords: () => t('miles kilometres km mi'),
              control: (c) => (
                <Segmented<Settings['interface']['distanceUnit']>
                  size="sm"
                  value={c.s.interface.distanceUnit}
                  onChange={(v) => c.set('interface', 'distanceUnit', v)}
                  options={[
                    { value: 'mi', label: t('Miles') },
                    { value: 'km', label: t('Kilometres') },
                  ]}
                />
              ),
            },
            {
              id: 'interface.currency',
              label: () => t('Currency symbol'),
              description: (c) => c.errors['interface.currency'] ?? t('Shown before every price.'),
              keywords: () => t('money dollar euro'),
              control: (c) => <CurrencyField value={c.s.interface.currency} onChange={(v) => c.set('interface', 'currency', v)} onEnter={c.save} />,
            },
            {
              id: 'interface.interaction',
              label: () => t('Interaction'),
              description: (c) =>
                c.s.interface.interaction === 'target'
                  ? t('Garages are opened with your target resource (ox_target / qb-target).')
                  : t('Players press a key near a garage point.'),
              keywords: () => t('target prompt key E ox_target qb-target'),
              control: (c) => (
                <Segmented<Settings['interface']['interaction']>
                  size="sm"
                  value={c.s.interface.interaction}
                  onChange={(v) => c.set('interface', 'interaction', v)}
                  options={[
                    { value: 'prompt', label: t('Press E') },
                    { value: 'target', label: t('Target') },
                  ]}
                />
              ),
            },
          ],
        },
      ],
    ],
  },
];

/** Every row id — the dev harness checks it covers every field of Settings. */
export const ALL_ROW_IDS = TABS.flatMap((tab) => tab.columns.flat().flatMap((p) => p.rows.map((r) => r.id)));
