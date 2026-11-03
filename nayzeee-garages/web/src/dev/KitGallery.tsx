/**
 * UI kit gallery (?kit=1, browser dev only): every component in every state, laid out in
 * real <Window>s so the kit can be judged (and screenshotted) the way apps will use it.
 * Extra params: &modal=1 opens the form modal, &confirm=1 opens the red confirm dialog.
 */
import { useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import {
  Avatar,
  Badge,
  Bar,
  BrandMark,
  Button,
  Chip,
  ColorSwatches,
  ConfirmDialog,
  Divider,
  EmptyState,
  Field,
  ICON_NAMES,
  Icon,
  IconButton,
  InfoDot,
  Input,
  Kbd,
  KeyHint,
  Menu,
  Meter,
  Modal,
  MultiSelect,
  NumberInput,
  OptionRow,
  Pagination,
  Panel,
  Pips,
  PillClose,
  PlateTag,
  Ring,
  SearchInput,
  Section,
  Segmented,
  Select,
  Skeleton,
  SkeletonRows,
  Slider,
  Spinner,
  Stat,
  Table,
  Tabs,
  Toggle,
  Tooltip,
  VehicleImage,
  VehicleSilhouette,
  Window,
} from '@/components/ui';
import type { SelectOption, TableColumn } from '@/components/ui';
import { t } from '@/lib/i18n';
import { toast, useUi } from '@/lib/store';
import { applyAccent } from '@/lib/theme';
import { useEscape } from '@/lib/escape';
import { Portal } from '@/components/ui/internal';
import { money } from '@/lib/format';
import type { VehicleState, VehicleType } from '@/lib/types';

const params = new URLSearchParams(window.location.search);

const GALLERY_CSS = `
#nz-kit { position: fixed; inset: 0; z-index: 1; overflow: auto; }
.nz-kitgal { padding: 34px 28px 90px; }
.nz-kitgal__wrap { max-width: 1360px; margin: 0 auto; display: flex; flex-direction: column; gap: 26px; }
.nz-kitgal__head { display: flex; align-items: center; gap: 16px; padding: 4px 4px 0; }
.nz-kitgal__head h1 { font-size: 22px; font-weight: 600; letter-spacing: -.025em; color: #fff; }
.nz-kitgal__head p { margin-top: 4px; font-size: 12px; font-weight: 300; color: var(--ink-2); }
.nz-kitgal__accent { margin-left: auto; display: flex; align-items: center; gap: 12px; padding: 10px 14px;
  background: var(--hud); border: 1px solid var(--hud-line); border-radius: 12px; }
.nz-kitgal__accent span { font-size: 11px; font-weight: 700; letter-spacing: .12em; text-transform: uppercase; color: var(--ink-3); }
.nz-kitgal__grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(600px, 1fr)); gap: 26px; align-items: start; }
.nz-kitgal .nz-window { position: relative; inset: auto; margin: 0; max-height: none; max-width: 100%; z-index: auto; width: 100% !important; }
.nz-kitgal .nz-window--span { grid-column: 1 / -1; }
.kg-row { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; }
.kg-row + .kg-row { margin-top: 10px; }
.kg-cols { display: grid; grid-template-columns: 1fr 1fr; gap: 14px 18px; }
.kg-cols3 { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; }
.kg-label { min-width: 74px; font-size: 11px; color: var(--ink-3); font-weight: 300; }
.kg-icons { display: grid; grid-template-columns: repeat(auto-fill, minmax(96px, 1fr)); gap: 6px; }
.kg-icon { display: flex; flex-direction: column; align-items: center; gap: 8px; padding: 13px 6px 9px; border-radius: 8px;
  background: var(--inset); border: 1px solid var(--line-hair); color: var(--ink); transition: border-color var(--fast), color var(--fast); }
.kg-icon:hover { border-color: var(--teal-edge); color: var(--teal); }
.kg-icon span { font-size: 10px; color: var(--ink-3); font-family: var(--mono); }
.kg-vimgs { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; }
.kg-vcard { background: var(--panel); border: 1px solid var(--line-soft); border-radius: 10px; padding: 8px 10px 10px; display: flex; flex-direction: column; gap: 6px; }
.kg-vcard b { font-size: 12.5px; font-weight: 600; color: #fff; }
.kg-vcard small { font-size: 10.5px; color: var(--ink-3); }
.kg-modal-static { position: relative; max-width: 420px; animation: none; }
.kg-swatch-tok { display: grid; grid-template-columns: repeat(auto-fill, minmax(104px, 1fr)); gap: 8px; }
.kg-tok { border: 1px solid var(--line-soft); border-radius: 6px; overflow: hidden; }
.kg-tok i { display: block; height: 34px; }
.kg-tok p { padding: 6px 8px; font-size: 9.5px; color: var(--ink-3); background: var(--base); line-height: 1.5; font-family: var(--mono); }
.kg-tok p b { display: block; color: var(--ink-2); font-size: 10.5px; font-family: var(--font); font-weight: 500; }
.kg-fill { flex: 1 1 auto; min-width: 0; }
.kg-sel { width: 300px; flex: none; }
.kg-stack { display: flex; flex-direction: column; gap: 10px; }
@media (max-width: 1340px) { .nz-kitgal__grid { grid-template-columns: 1fr; } }
`;

/* ── demo data ────────────────────────────────────────────────────────── */

interface DemoVehicle {
  plate: string;
  label: string;
  model: string;
  garage: string;
  state: VehicleState;
  fuel: number;
  type: VehicleType;
}

const VEHICLES: DemoVehicle[] = [
  { plate: 'RETRO 6', label: 'Annis Elegy Retro Custom', model: 'elegy', garage: 'Legion Square', state: 'garaged', fuel: 76, type: 'car' },
  { plate: 'MIDNIGHT', label: 'Dinka Jester RR', model: 'jester4', garage: 'Mirror Park', state: 'out', fuel: 41, type: 'car' },
  { plate: 'ENUS 1', label: 'Enus Paragon R', model: 'paragon', garage: 'Pillbox Hill', state: 'impounded', fuel: 12, type: 'car' },
  { plate: 'PACIFIC', label: 'Pfister Comet S2 Cabrio', model: 'comet7', garage: 'Great Ocean Hwy', state: 'garaged', fuel: 93, type: 'car' },
  { plate: 'SEA 04', label: 'Shitzu Longfin', model: 'longfin', garage: 'Puerto Del Sol Marina', state: 'garaged', fuel: 64, type: 'sea' },
];

const STATE_BADGE: Record<VehicleState, ReactNode> = {
  garaged: (
    <Badge tone="teal" dot size="sm">
      {t('Stored')}
    </Badge>
  ),
  out: (
    <Badge tone="amber" dot size="sm">
      {t('Out')}
    </Badge>
  ),
  impounded: (
    <Badge tone="red" dot size="sm">
      {t('Impounded')}
    </Badge>
  ),
};

const GARAGES: SelectOption<string>[] = [
  { value: 'legion', label: 'Legion Square Parking', hint: t('{n} spaces left', { n: 6 }), icon: 'garage' },
  { value: 'mirror', label: 'Mirror Park Garage', hint: t('{n} spaces left', { n: 2 }), icon: 'garage' },
  { value: 'pillbox', label: 'Pillbox Hill Underground', hint: t('Full'), icon: 'garage', disabled: true },
  { value: 'marina', label: 'Puerto Del Sol Marina', hint: t('Boats only'), icon: 'boat' },
  { value: 'hangar', label: 'LSIA Hangar 3', hint: t('Aircraft only'), icon: 'plane' },
];

const JOBS: SelectOption<string>[] = [
  { value: 'police', label: 'Police' },
  { value: 'ambulance', label: 'EMS' },
  { value: 'mechanic', label: 'Mechanic' },
  { value: 'taxi', label: 'Taxi' },
  { value: 'realestate', label: 'Real estate' },
  { value: 'cardealer', label: 'Car dealer' },
  { value: 'tow', label: 'Tow service' },
  { value: 'news', label: 'Weazel News' },
  { value: 'judge', label: 'Judge' },
];

const ACCENTS = ['#08afa2', '#22d3ee', '#60a5fa', '#a78bfa', '#f472b6', '#fb7185', '#facc15', '#f5f5f5'];

/* ── gallery ──────────────────────────────────────────────────────────── */

export function KitGallery() {
  const [accent, setAccent] = useState('#08afa2');
  const [btnLoading, setBtnLoading] = useState(false);

  // inputs
  const [name, setName] = useState('Grotti Itali GTO');
  const [plate, setPlate] = useState('GTO 88');
  const [fee, setFee] = useState(2500);
  const [hours, setHours] = useState(24);
  const [search, setSearch] = useState('');
  const [search2, setSearch2] = useState('elegy');
  const [garage, setGarage] = useState<string | null>('legion');
  const [garageEmpty, setGarageEmpty] = useState<string | null>(null);
  const [jobs, setJobs] = useState<string[]>(['police', 'ambulance', 'mechanic', 'tow']);
  const [scale, setScale] = useState(100);
  const [color, setColor] = useState('#08afa2');
  const [tg1, setTg1] = useState(true);
  const [tg2, setTg2] = useState(false);
  const [tg3] = useState(true);

  // navigation
  const [tab, setTab] = useState('fav');
  const [tab2, setTab2] = useState('details');
  const [view, setView] = useState<'list' | 'grid'>('grid');
  const [unit, setUnit] = useState<'mi' | 'km'>('mi');
  const [mode, setMode] = useState('garage');
  const [chips, setChips] = useState<string[]>(['fav']);
  const [page, setPage] = useState(1);
  const [page2, setPage2] = useState(6);

  // table
  const [activeRow, setActiveRow] = useState<string | null>('MIDNIGHT');

  // overlays
  const [modalOpen, setModalOpen] = useState(params.get('modal') === '1');
  const [confirmOpen, setConfirmOpen] = useState(params.get('confirm') === '1');
  const [confirmBusy, setConfirmBusy] = useState(false);
  const [buyOpen, setBuyOpen] = useState(false);
  const [floatOpen, setFloatOpen] = useState(params.get('window') === '1');
  useEscape(() => setFloatOpen(false), floatOpen);
  const [rename, setRename] = useState('Grotti Itali GTO');

  const toggleChip = (c: string) => setChips((s) => (s.includes(c) ? s.filter((x) => x !== c) : [...s, c]));

  const columns = useMemo<TableColumn<DemoVehicle>[]>(
    () => [
      {
        key: 'label',
        header: t('Vehicle'),
        width: '34%',
        render: (v) => (
          <span className="nz-row nz-gap-10">
            <Icon name={v.type === 'sea' ? 'boat' : 'car'} size={15} className="nz-muted" />
            <b className="nz-ellipsis">{v.label}</b>
          </span>
        ),
      },
      { key: 'plate', header: t('Plate'), width: 110, render: (v) => <PlateTag plate={v.plate} /> },
      { key: 'garage', header: t('Garage'), render: (v) => v.garage },
      { key: 'state', header: t('State'), width: 110, render: (v) => STATE_BADGE[v.state] },
      {
        key: 'fuel',
        header: t('Fuel'),
        width: 120,
        align: 'right',
        render: (v) => (
          <span className="nz-row nz-gap-8" style={{ justifyContent: 'flex-end' }}>
            <Bar value={v.fuel} tone="auto" height={3} className="kg-fill" />
            <span style={{ width: 32, textAlign: 'right' }}>{v.fuel}%</span>
          </span>
        ),
      },
    ],
    [],
  );

  const fireToasts = () => {
    toast({ type: 'success', title: t('Vehicle stored'), message: t('Your Elegy is parked at Legion Square.') });
    toast({ type: 'info', message: t('Waypoint set to the nearest garage.') });
    toast({ type: 'warning', title: t('Payment due'), message: t('Next finance payment in 6 hours.') });
    toast({ type: 'error', title: t('Not enough money'), message: t('You need {amount} in your bank.', { amount: money(4250) }) });
  };

  return (
    <div className="nz-kitgal">
      <style>{GALLERY_CSS}</style>
      <div className="nz-kitgal__wrap">
        <header className="nz-kitgal__head">
          <BrandMark size="lg" />
          <div>
            <h1>{t('NayZeee UI kit')}</h1>
            <p>{t('nayzeee-garages design system — every component, every state.')}</p>
          </div>
          <div className="nz-kitgal__accent">
            <span>{t('Accent')}</span>
            <ColorSwatches
              value={accent}
              colors={ACCENTS}
              onChange={(c) => {
                setAccent(c);
                applyAccent(c);
              }}
            />
          </div>
        </header>

        {/* ── Window anatomy ─────────────────────────────────────────── */}
        <Window
          className="nz-window--span"
          title={t('Legion Square Parking')}
          icon="garage"
          subtitle={t('Public garage · Cars & bikes')}
          badge={
            <Badge tone="teal" size="sm" icon="lock">
              {t('Private')}
            </Badge>
          }
          headerExtra={
            <>
              <Meter label={t('Your spaces')} icon="parking" used={6} total={12} />
              <Segmented
                size="sm"
                iconOnly
                value={view}
                onChange={setView}
                options={[
                  { value: 'list', label: t('List view'), icon: 'list' },
                  { value: 'grid', label: t('Grid view'), icon: 'grid' },
                ]}
              />
              <Button variant="white" size="sm" icon="walk">
                {t('Go inside')}
              </Button>
            </>
          }
          onClose={() => toast({ type: 'info', message: t('Close clicked') })}
          watermark
          footer={
            <>
              <KeyHint keys={['Esc']} label={t('Close')} />
              <KeyHint keys={['Enter']} label={t('Drive')} />
              <KeyHint keys={['F']} label={t('Favourite')} />
              <span style={{ marginLeft: 'auto' }}>
                <b>4</b> {t('vehicle(s)')}
              </span>
            </>
          }
        >
          <div className="kg-stack">
            <div className="kg-row">
              <SearchInput value={search} onChange={setSearch} placeholder={t('Search by name or plate')} shortcut="/" className="kg-fill" />
              <Select
                value={garage}
                onChange={setGarage}
                options={GARAGES}
                className="kg-sel"
                size="md"
                placeholder={t('Choose a garage')}
              />
            </div>
            <Tabs
              value={tab}
              onChange={setTab}
              items={[
                { value: 'all', label: t('All'), count: 30 },
                { value: 'fav', label: t('Favourites'), count: 4, icon: 'star' },
                { value: 'here', label: t('Parked here'), count: 7 },
                { value: 'imp', label: t('Impounded'), count: 3 },
              ]}
            />
            <div className="kg-cols3">
              <Stat label={t('Fuel')} icon="fuel" value={76} />
              <Stat
                label={t('Engine')}
                icon="engine"
                value={41}
                extra={
                  <Badge tone="amber" size="sm" icon="wrench">
                    {t('Needs service')}
                  </Badge>
                }
              />
              <Stat label={t('Body')} icon="shield" value={18} />
            </div>
            <div className="kg-row">
              <Button variant="teal" icon="car" badge={money(250)}>
                {t('Drive')}
              </Button>
              <Button icon="transfer">{t('Transfer')}</Button>
              <Button icon="tag">{t('Sell')}</Button>
              <Button icon="users">{t('Share')}</Button>
              <span className="kg-fill" />
              <IconButton icon="starFilled" label={t('Favourite')} active />
              <Menu
                items={[
                  { label: t('Rename'), icon: 'edit', onSelect: () => setModalOpen(true) },
                  { label: t('Track vehicle'), icon: 'route', onSelect: () => undefined },
                  { label: t('Copy plate'), icon: 'copy', onSelect: () => undefined, hint: 'GTO 88' },
                  { label: t('Recover'), icon: 'refresh', onSelect: () => undefined, disabled: true },
                  { label: t('Delete vehicle'), icon: 'trash', onSelect: () => setConfirmOpen(true), danger: true },
                ]}
              />
            </div>
          </div>
        </Window>

        <div className="nz-kitgal__grid">
          {/* ── Buttons ─────────────────────────────────────────────── */}
          <Window title={t('Buttons')} icon="sparkle" subtitle={t('Variants, sizes, icons, states')}>
            <Section title={t('Variants')}>
              <div className="kg-row">
                <Button variant="teal" icon="check">
                  {t('Save changes')}
                </Button>
                <Button variant="white">{t('Confirm')}</Button>
                <Button variant="line">{t('Cancel')}</Button>
                <Button variant="red" icon="trash">
                  {t('Delete')}
                </Button>
                <Button variant="ghost" icon="refresh">
                  {t('Refresh')}
                </Button>
              </div>
            </Section>
            <Section title={t('Sizes')}>
              <div className="kg-row">
                <Button variant="teal" size="sm">
                  {t('Small')}
                </Button>
                <Button variant="teal" size="md">
                  {t('Medium')}
                </Button>
                <Button variant="teal" size="lg">
                  {t('Large')}
                </Button>
                <Button size="sm" icon="plus">
                  {t('Add')}
                </Button>
                <Button size="lg" iconRight="arrowRight">
                  {t('Continue')}
                </Button>
              </div>
            </Section>
            <Section title={t('Icons, badges, loading')}>
              <div className="kg-row">
                <Button variant="teal" icon="car" badge={money(250)}>
                  {t('Drive')}
                </Button>
                <Button variant="white" icon="walk">
                  {t('Go inside')}
                </Button>
                <Button icon="users" badge={3}>
                  {t('Members')}
                </Button>
                <Button
                  variant="teal"
                  loading={btnLoading}
                  onClick={() => {
                    setBtnLoading(true);
                    window.setTimeout(() => setBtnLoading(false), 1600);
                  }}
                >
                  {t('Click to load')}
                </Button>
                <Button variant="line" loading>
                  {t('Saving')}
                </Button>
              </div>
            </Section>
            <Section title={t('Disabled')}>
              <div className="kg-row">
                <Button variant="teal" disabled>
                  {t('Drive')}
                </Button>
                <Button variant="white" disabled>
                  {t('Confirm')}
                </Button>
                <Button disabled>{t('Cancel')}</Button>
                <Button variant="red" disabled>
                  {t('Delete')}
                </Button>
                <Button variant="ghost" disabled>
                  {t('Ghost')}
                </Button>
              </div>
            </Section>
            <Section title={t('Icon buttons')}>
              <div className="kg-row">
                <IconButton icon="edit" label={t('Edit')} />
                <IconButton icon="cog" label={t('Settings')} variant="line" />
                <IconButton icon="pin" label={t('Teleport')} variant="teal" />
                <IconButton icon="trash" label={t('Delete')} variant="red" />
                <IconButton icon="star" label={t('Favourite')} active />
                <IconButton icon="lock" label={t('Locked')} disabled />
                <Divider vertical />
                <IconButton icon="edit" label={t('Edit')} size="sm" />
                <IconButton icon="cog" label={t('Settings')} variant="line" size="sm" />
                <IconButton icon="pin" label={t('Teleport')} variant="teal" size="sm" />
                <IconButton icon="trash" label={t('Delete')} variant="red" size="sm" />
              </div>
            </Section>
            <Section title={t('Close pill, keycaps, menu')}>
              <div className="kg-row">
                <PillClose onClick={() => undefined} />
                <Kbd>E</Kbd>
                <Kbd>Esc</Kbd>
                <Kbd>Enter</Kbd>
                <Kbd>ArrowUp</Kbd>
                <Kbd>Shift</Kbd>
                <Kbd size="sm">F</Kbd>
                <KeyHint keys={['Esc']} label={t('Close')} />
                <KeyHint keys={['Shift', 'R']} label={t('Reset')} size="md" />
                <Menu
                  align="left"
                  trigger={
                    <Button size="sm" iconRight="chevronDown">
                      {t('Actions')}
                    </Button>
                  }
                  items={[
                    { label: t('Teleport'), icon: 'pin', onSelect: () => undefined },
                    { label: t('Duplicate'), icon: 'copy', onSelect: () => undefined },
                    { label: t('Delete'), icon: 'trash', onSelect: () => undefined, danger: true },
                  ]}
                />
              </div>
            </Section>
          </Window>

          {/* ── Inputs ──────────────────────────────────────────────── */}
          <Window title={t('Inputs')} icon="edit" subtitle={t('Fields, numbers, search, dropdowns')}>
            <div className="kg-cols">
              <Field label={t('Nickname')} hint={t('Shown instead of the model name.')}>
                <Input value={name} onChange={setName} icon="car" maxLength={24} placeholder={t('Grotti Itali GTO')} />
              </Field>
              <Field label={t('Plate')} required>
                <Input value={plate} onChange={setPlate} mono uppercase maxLength={8} icon="hash" />
              </Field>
              <Field label={t('Impound fee')} aside={<InfoDot text={t('Paid by the owner when retrieving the vehicle.')} />}>
                <NumberInput value={fee} onChange={setFee} min={0} max={100000} step={250} prefix="$" />
              </Field>
              <Field label={t('Hold time')} error={hours > 72 ? t('Maximum is 72 hours.') : undefined}>
                <NumberInput value={hours} onChange={setHours} min={0} max={100} suffix={t('hours')} />
              </Field>
              <Field label={t('Search')}>
                <SearchInput value={search2} onChange={setSearch2} placeholder={t('Search by name or plate')} />
              </Field>
              <Field label={t('Disabled')}>
                <Input value={t('Read only')} onChange={() => undefined} disabled icon="lock" />
              </Field>
              <Field label={t('Destination garage')}>
                <Select value={garage} onChange={setGarage} options={GARAGES} searchable />
              </Field>
              <Field label={t('Select (empty, small)')}>
                <Select
                  value={garageEmpty}
                  onChange={setGarageEmpty}
                  options={GARAGES}
                  size="sm"
                  icon="garage"
                  placeholder={t('Choose a garage')}
                />
              </Field>
              <Field label={t('Allowed jobs')}>
                <MultiSelect value={jobs} onChange={setJobs} options={JOBS} placeholder={t('Everyone')} />
              </Field>
              <Field label={t('Select (disabled)')}>
                <Select value="legion" onChange={() => undefined} options={GARAGES} disabled />
              </Field>
            </div>
            <Divider />
            <Section title={t('Settings controls')}>
              <OptionRow
                label={t('Interface scale')}
                description={t('On top of the global HUD scale')}
                stacked
                control={<Slider value={scale} onChange={setScale} min={50} max={150} step={5} suffix="%" />}
              />
              <Toggle checked={tg1} onChange={setTg1} label={t('Show vehicle images')} description={t('Load pictures from the image URL')} />
              <Toggle checked={tg2} onChange={setTg2} label={t('Spawn outside')} description={t('Vehicles appear at the nearest free spot')} />
              <Toggle checked={tg3} onChange={() => undefined} label={t('Locked setting')} description={t('Controlled by the server config')} disabled />
              <OptionRow
                label={t('Accent colour')}
                description={t('Primary colour of every window')}
                control={<ColorSwatches value={color} onChange={setColor} colors={ACCENTS.slice(0, 6)} />}
              />
              <div className="kg-row">
                <Toggle checked onChange={() => undefined} />
                <Toggle checked={false} onChange={() => undefined} />
                <Toggle checked size="sm" onChange={() => undefined} />
                <Toggle checked={false} size="sm" onChange={() => undefined} />
                <Toggle checked disabled onChange={() => undefined} />
              </div>
            </Section>
          </Window>

          {/* ── Navigation ─────────────────────────────────────────── */}
          <Window title={t('Navigation')} icon="sliders" subtitle={t('Tabs, segmented, chips, pagination')}>
            <Section title={t('Tabs — pill')}>
              <Tabs
                value={tab}
                onChange={setTab}
                items={[
                  { value: 'all', label: t('All'), count: 30 },
                  { value: 'fav', label: t('Favourites'), count: 4 },
                  { value: 'here', label: t('Parked here'), count: 7 },
                  { value: 'imp', label: t('Impounded'), count: 3 },
                  { value: 'shared', label: t('Shared'), count: 0, disabled: true },
                ]}
              />
            </Section>
            <Section title={t('Tabs — underline')}>
              <Tabs
                variant="underline"
                value={tab2}
                onChange={setTab2}
                items={[
                  { value: 'details', label: t('Details'), icon: 'edit' },
                  { value: 'cutscene', label: t('Cutscene'), icon: 'camera', count: 4 },
                  { value: 'slots', label: t('Vehicle slots'), icon: 'car', count: 12 },
                  { value: 'exit', label: t('Exit'), icon: 'door' },
                ]}
              />
            </Section>
            <Section title={t('Segmented')}>
              <div className="kg-row">
                <Segmented
                  value={mode}
                  onChange={setMode}
                  options={[
                    { value: 'garage', label: t('Garage'), icon: 'garage' },
                    { value: 'player', label: t('Player'), icon: 'user' },
                  ]}
                />
                <Segmented
                  value={unit}
                  onChange={setUnit}
                  size="sm"
                  options={[
                    { value: 'mi', label: t('Miles') },
                    { value: 'km', label: t('Kilometres') },
                  ]}
                />
                <Segmented
                  value={view}
                  onChange={setView}
                  iconOnly
                  options={[
                    { value: 'list', label: t('List view'), icon: 'list' },
                    { value: 'grid', label: t('Grid view'), icon: 'grid' },
                  ]}
                />
                <Segmented value="a" onChange={() => undefined} disabled options={[{ value: 'a', label: t('Disabled') }, { value: 'b', label: t('Off') }]} />
              </div>
            </Section>
            <Section title={t('Chips')}>
              <div className="kg-row">
                <Chip active={chips.includes('fav')} onClick={() => toggleChip('fav')} icon="star" count={4}>
                  {t('Favourites')}
                </Chip>
                <Chip active={chips.includes('car')} onClick={() => toggleChip('car')} icon="car">
                  {t('Cars')}
                </Chip>
                <Chip active={chips.includes('boat')} onClick={() => toggleChip('boat')} icon="boat">
                  {t('Boats')}
                </Chip>
                <Chip active={chips.includes('fin')} onClick={() => toggleChip('fin')} icon="money" count={2}>
                  {t('Financed')}
                </Chip>
                <Chip onClick={() => undefined} disabled>
                  {t('Disabled')}
                </Chip>
                <Chip icon="pin">{t('Static chip')}</Chip>
              </div>
            </Section>
            <Section title={t('Pagination')}>
              <Pagination page={page} pageCount={4} onChange={setPage} total={34} pageSize={10} />
              <Pagination page={page2} pageCount={18} onChange={setPage2} />
            </Section>
          </Window>

          {/* ── Display ─────────────────────────────────────────────── */}
          <Window title={t('Data display')} icon="gauge" subtitle={t('Stats, meters, badges, identity')}>
            <Section title={t('Stats (auto tone)')}>
              <div className="kg-cols3">
                <Stat label={t('Fuel')} icon="fuel" value={88} />
                <Stat label={t('Engine')} icon="engine" value={34} extra={<InfoDot text={t('Below 50% — service recommended.')} />} />
                <Stat label={t('Body')} icon="shield" value={9} />
              </div>
            </Section>
            <Section title={t('Bars, rings, pips, meters')}>
              <div className="kg-stack">
                <div className="kg-row">
                  <span className="kg-label">{t('Bars')}</span>
                  <div className="kg-fill kg-stack" style={{ gap: 8 }}>
                    <Bar value={82} />
                    <Bar value={46} tone="auto" />
                    <Bar value={14} tone="auto" height={5} />
                    <Bar value={60} tone="blue" height={2} />
                  </div>
                </div>
                <div className="kg-row">
                  <span className="kg-label">{t('Rings')}</span>
                  <Ring value={76}>
                    <Icon name="fuel" size={13} />
                  </Ring>
                  <Ring value={38} tone="auto">
                    <Icon name="engine" size={13} />
                  </Ring>
                  <Ring value={12} tone="auto">
                    <Icon name="shield" size={13} />
                  </Ring>
                  <Ring value={64} size={46} stroke={4} tone="white">
                    64
                  </Ring>
                  <Ring value={90} size={46} stroke={4} tone="blue">
                    90
                  </Ring>
                </div>
                <div className="kg-row">
                  <span className="kg-label">{t('Pips')}</span>
                  <div className="kg-fill kg-stack" style={{ gap: 8 }}>
                    <Pips total={24} done={8} />
                    <Pips total={12} done={10} tone="amber" />
                  </div>
                </div>
                <div className="kg-row">
                  <span className="kg-label">{t('Meters')}</span>
                  <Meter label={t('Your spaces')} icon="parking" used={6} total={12} />
                  <Meter label={t('Spaces')} used={11} total={12} />
                  <Meter label={t('Spaces')} used={12} total={12} />
                  <Meter label={t('Members')} icon="users" used={3} total={0} />
                </div>
              </div>
            </Section>
            <Section title={t('Badges & plates')}>
              <div className="kg-row">
                <Badge tone="teal" dot>
                  {t('Stored')}
                </Badge>
                <Badge tone="amber" icon="clock">
                  {t('Out')}
                </Badge>
                <Badge tone="red" icon="ban">
                  {t('Blocked')}
                </Badge>
                <Badge tone="blue" icon="users">
                  {t('Shared')}
                </Badge>
                <Badge tone="neutral" icon="pin">
                  {t('Vinewood')}
                </Badge>
                <Badge tone="white">{t('New')}</Badge>
              </div>
              <div className="kg-row">
                <Badge size="sm" tone="teal">
                  {t('Private')}
                </Badge>
                <Badge size="sm" tone="amber" icon="wrench">
                  {t('Needs service')}
                </Badge>
                <Badge size="sm" tone="red">
                  {t('Overdue')}
                </Badge>
                <Badge size="sm" tone="blue">
                  {t('Job')}
                </Badge>
                <Badge size="sm" tone="neutral">
                  v1.0.0
                </Badge>
                <PlateTag plate="RETRO 6" />
                <PlateTag plate="midnight" />
                <PlateTag plate="ENUS 1" size="sm" />
              </div>
            </Section>
            <Section title={t('Identity & loading')}>
              <div className="kg-row">
                <Avatar name="John Doe" />
                <Avatar name="Maya Reyes" size={28} />
                <Avatar name="theo" size={40} />
                <BrandMark size="sm" />
                <BrandMark />
                <BrandMark size="lg" />
                <Spinner size={14} />
                <Spinner />
                <Spinner size={22} className="nz-muted" />
                <Skeleton width={90} height={10} />
                <Skeleton width={36} height={36} radius={8} />
              </div>
            </Section>
          </Window>

          {/* ── Table ───────────────────────────────────────────────── */}
          <Window title={t('Table')} icon="list" subtitle={t('Clickable rows, active row, pagination')} className="nz-window--span">
            <Table
              columns={columns}
              rows={VEHICLES}
              rowKey={(v) => v.plate}
              activeKey={activeRow}
              onRowClick={(v) => setActiveRow(v.plate)}
            />
            <Pagination page={page} pageCount={4} onChange={setPage} total={34} pageSize={10} />
          </Window>

          <Window title={t('Table — loading')} icon="refresh" subtitle={t('Skeleton rows while a request runs')}>
            <Table columns={columns.slice(0, 4)} rows={[]} rowKey={(v) => v.plate} loading skeletonRows={4} dense />
          </Window>

          <Window title={t('Table — empty')} icon="search" subtitle={t('Empty states')}>
            <Table
              columns={columns.slice(0, 4)}
              rows={[]}
              rowKey={(v) => v.plate}
              empty={
                <EmptyState
                  icon="search"
                  title={t('No vehicles match “zentorno”')}
                  description={t('Try another name or plate, or clear the filters.')}
                  action={
                    <Button size="sm" icon="close">
                      {t('Clear filters')}
                    </Button>
                  }
                  compact
                />
              }
            />
          </Window>

          {/* ── Panels & loading ─────────────────────────────────────── */}
          <Window title={t('Panels & states')} icon="layers" subtitle={t('Panel, section, empty, skeleton')}>
            <div className="kg-cols">
              <Panel
                title={t('Members')}
                subtitle={t('People with access')}
                icon="users"
                actions={
                  <Button size="sm" icon="userPlus">
                    {t('Add')}
                  </Button>
                }
              >
                <SkeletonRows count={3} />
              </Panel>
              <Panel title={t('Service history')} icon="history">
                <EmptyState
                  icon="wrench"
                  title={t('No services yet')}
                  description={t('Repairs and maintenance done at shops will appear here.')}
                  compact
                />
              </Panel>
            </div>
            <Divider label={t('or')} />
            <EmptyState
              icon="garage"
              title={t('This garage is empty')}
              description={t('Store a vehicle here and it will show up in this list.')}
              action={
                <Button variant="teal" size="sm" icon="route">
                  {t('Nearest garage with space')}
                </Button>
              }
            />
          </Window>

          {/* ── Overlays ────────────────────────────────────────────── */}
          <Window title={t('Overlays')} icon="layers" subtitle={t('Tooltips, menus, modals, toasts')}>
            <Section title={t('Tooltips')}>
              <div className="kg-row">
                {(['top', 'bottom', 'left', 'right'] as const).map((s) => (
                  <Tooltip key={s} content={t('Tooltip on the {side}', { side: s })} side={s}>
                    <Button size="sm">{s}</Button>
                  </Tooltip>
                ))}
                <InfoDot text={t('Info dots explain a setting in one or two sentences.')} />
              </div>
            </Section>
            <Section title={t('Dialogs')}>
              <div className="kg-row">
                <Button icon="edit" onClick={() => setModalOpen(true)}>
                  {t('Open modal')}
                </Button>
                <Button variant="red" icon="trash" onClick={() => setConfirmOpen(true)}>
                  {t('Confirm (red)')}
                </Button>
                <Button variant="teal" icon="cart" onClick={() => setBuyOpen(true)}>
                  {t('Confirm (teal)')}
                </Button>
                <Button icon="sidebar" onClick={() => setFloatOpen(true)}>
                  {t('Floating window')}
                </Button>
              </div>
            </Section>
            <Section title={t('Toasts & HUD')}>
              <div className="kg-row">
                <Button icon="sparkle" onClick={fireToasts}>
                  {t('Fire 4 toasts')}
                </Button>
                <Button
                  icon="key"
                  onClick={() => {
                    const has = !!useUi.getState().prompt;
                    useUi.setState({ prompt: has ? null : { key: 'E', label: t('Open garage') } });
                  }}
                >
                  {t('Toggle prompt')}
                </Button>
                <Button
                  icon="sliders"
                  onClick={() => {
                    const has = !!useUi.getState().hint;
                    useUi.setState({
                      hint: has
                        ? null
                        : {
                            title: t('Fine-tune vehicle position'),
                            keys: [
                              { keys: ['W', 'A', 'S', 'D'], label: t('Move') },
                              { keys: ['Scroll'], label: t('Rotate') },
                              { keys: ['Enter'], label: t('Confirm') },
                              { keys: ['Esc'], label: t('Cancel') },
                            ],
                          },
                    });
                  }}
                >
                  {t('Toggle hint')}
                </Button>
              </div>
            </Section>
            <Section title={t('Modal (static preview)')}>
              <div className="nz-modal kg-modal-static">
                <div className="nz-modal__head">
                  <span className="nz-modal__icon nz-modal__icon--red">
                    <Icon name="warning" size={16} />
                  </span>
                  <div className="nz-modal__titles">
                    <h3 className="nz-modal__title">{t('Sell this garage?')}</h3>
                  </div>
                  <IconButton icon="close" label={t('Close')} size="sm" />
                </div>
                <div className="nz-modal__body">
                  <div className="nz-confirm__message">
                    {t('You will receive')} <b>{money(87500)}</b> {t('(70% of the price). The garage must be empty.')}
                  </div>
                </div>
                <div className="nz-modal__foot">
                  <Button>{t('Keep garage')}</Button>
                  <Button variant="red">{t('Sell garage')}</Button>
                </div>
              </div>
            </Section>
          </Window>

          {/* ── Vehicle images ──────────────────────────────────────── */}
          <Window title={t('Vehicle images')} icon="camera" subtitle={t('Image URL → local file → silhouette')} className="nz-window--span">
            <div className="kg-vimgs">
              {[
                { image: 'elegy', type: 'car' as VehicleType, label: 'Annis Elegy Retro Custom', note: t('Remote image') },
                { image: 'nz_missing_model', type: 'car' as VehicleType, label: 'Unknown car', note: t('Fallback: car') },
                { image: 'longfin', type: 'sea' as VehicleType, label: 'Shitzu Longfin', note: t('Boat') },
                { image: null, type: 'sea' as VehicleType, label: 'No image', note: t('Fallback: boat') },
                { image: 'luxor', type: 'air' as VehicleType, label: 'Buckingham Luxor', note: t('Plane') },
                { image: null, type: 'air' as VehicleType, label: 'No image', note: t('Fallback: plane') },
                { image: 'nz_buzzard_x', type: 'air' as VehicleType, label: 'Buzzard (missing)', note: t('Fallback: helicopter') },
                { image: null, type: 'car' as VehicleType, label: 'No image', note: t('Fallback: car') },
              ].map((v, i) => (
                <div key={i} className="kg-vcard">
                  <VehicleImage image={v.image} vehicleType={v.type} alt={v.label} />
                  <b className="nz-ellipsis">{v.label}</b>
                  <small>{v.note}</small>
                </div>
              ))}
            </div>
            <Divider />
            <div className="kg-row">
              {(['car', 'boat', 'plane', 'heli'] as const).map((k) => (
                <div key={k} className="kg-vcard" style={{ width: 200 }}>
                  <VehicleSilhouette kind={k} />
                  <small className="nz-mono">{k}</small>
                </div>
              ))}
            </div>
          </Window>

          {/* ── Icons ───────────────────────────────────────────────── */}
          <Window
            title={t('Icons')}
            icon="grid"
            subtitle={t('{count} original 24×24 stroke icons', { count: ICON_NAMES.length })}
            className="nz-window--span"
          >
            <div className="kg-icons">
              {ICON_NAMES.map((n) => (
                <div key={n} className="kg-icon" title={n}>
                  <Icon name={n} size={22} />
                  <span>{n}</span>
                </div>
              ))}
            </div>
            <Divider />
            <div className="kg-row">
              {ICON_NAMES.slice(0, 32).map((n) => (
                <Icon key={n} name={n} size={16} className="nz-dim" />
              ))}
            </div>
          </Window>

          {/* ── Tokens ──────────────────────────────────────────────── */}
          <Window title={t('Tokens')} icon="palette" subtitle={t('Surfaces, ink and accents')} className="nz-window--span">
            <div className="kg-swatch-tok">
              {[
                ['Void', 'var(--void)', '#000000'],
                ['Base', 'var(--base)', '#08090a'],
                ['Panel', 'var(--panel)', '#0e1011'],
                ['Raise', 'var(--raise)', '#15181a'],
                ['Raise 2', 'var(--raise-2)', '#1c2023'],
                ['Inset', 'var(--inset)', '#0b0c0d'],
                ['Teal', 'var(--teal)', '--teal'],
                ['Teal hi', 'var(--teal-hi)', '--teal-hi'],
                ['Teal lo', 'var(--teal-lo)', '--teal-lo'],
                ['Red', 'var(--red)', '#e5484d'],
                ['Amber', 'var(--amber)', '#e5a50a'],
                ['Blue', 'var(--blue)', '#58a6ff'],
                ['Ink', 'var(--ink)', '#f2f4f5'],
                ['Ink 2', 'var(--ink-2)', '#9ea5aa'],
                ['Ink 3', 'var(--ink-3)', '#63696d'],
                ['HUD', 'var(--hud)', 'rgba(12,13,16,.78)'],
              ].map(([n, v, h]) => (
                <div key={n} className="kg-tok">
                  <i style={{ background: v }} />
                  <p>
                    <b>{n}</b>
                    {h}
                  </p>
                </div>
              ))}
            </div>
          </Window>
        </div>
      </div>

      {floatOpen && (
        <Portal>
        <Window
          title={t('Floating window')}
          icon="garage"
          subtitle={t('Centered, fixed, body scrolls, Escape closes')}
          width={760}
          watermark
          onClose={() => setFloatOpen(false)}
          headerExtra={<Meter label={t('Spaces')} icon="parking" used={11} total={12} />}
          footer={
            <>
              <KeyHint keys={['Esc']} label={t('Close')} />
              <KeyHint keys={['Enter']} label={t('Open')} />
              <span style={{ marginLeft: 'auto' }}>
                <b>{VEHICLES.length * 6}</b> {t('vehicle(s)')}
              </span>
            </>
          }
        >
          <Table
            columns={columns}
            rows={Array.from({ length: 6 }, (_, i) => VEHICLES.map((v) => ({ ...v, plate: `${v.plate.slice(0, 5)}${i}` }))).flat()}
            rowKey={(v) => v.plate}
            onRowClick={() => setModalOpen(true)}
            dense
          />
        </Window>
        </Portal>
      )}

      <Modal
        open={modalOpen}
        title={t('Rename vehicle')}
        subtitle={t('Only you see this name')}
        icon="edit"
        onClose={() => setModalOpen(false)}
        footer={
          <>
            <Button onClick={() => setRename('')}>{t('Reset to model name')}</Button>
            <Button
              variant="teal"
              icon="check"
              onClick={() => {
                setModalOpen(false);
                toast({ type: 'success', message: t('Nickname saved.') });
              }}
            >
              {t('Save')}
            </Button>
          </>
        }
      >
        <Field label={t('Nickname')} hint={t('Up to 24 characters. Leave empty to use the model name.')}>
          <Input
            value={rename}
            onChange={setRename}
            maxLength={24}
            icon="car"
            placeholder={t('Grotti Itali GTO')}
            onEnter={() => setModalOpen(false)}
          />
        </Field>
        <Field label={t('Garage')}>
          <Select value={garage} onChange={setGarage} options={GARAGES} />
        </Field>
      </Modal>

      <ConfirmDialog
        open={confirmOpen}
        tone="red"
        title={t('Delete this vehicle?')}
        message={
          <>
            <b>Dinka Jester RR</b> ({t('plate')} <b>MIDNIGHT</b>) {t('will be removed from the owner. This cannot be undone.')}
          </>
        }
        confirmLabel={t('Delete vehicle')}
        busy={confirmBusy}
        onCancel={() => setConfirmOpen(false)}
        onConfirm={() => {
          setConfirmBusy(true);
          window.setTimeout(() => {
            setConfirmBusy(false);
            setConfirmOpen(false);
            toast({ type: 'success', message: t('Vehicle deleted.') });
          }, 1200);
        }}
      />

      <ConfirmDialog
        open={buyOpen}
        title={t('Buy Mirror Park Garage?')}
        icon="cart"
        message={
          <>
            {t('The price of')} <b>{money(125000)}</b> {t('will be taken from your bank account.')}
          </>
        }
        confirmLabel={t('Buy for {price}', { price: money(125000) })}
        onCancel={() => setBuyOpen(false)}
        onConfirm={() => setBuyOpen(false)}
      />
    </div>
  );
}
