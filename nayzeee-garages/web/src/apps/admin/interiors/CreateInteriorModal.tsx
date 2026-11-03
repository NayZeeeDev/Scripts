/**
 * "Create interior" modal: name, IPL profile (or manual coordinates) → admin:interior:create.
 * Lua closes the admin panel and starts the in-world creator, so on success we only close.
 *
 * IPL profiles without known quick-teleport coordinates (coords === null) cannot be used as a
 * starting point and are hidden; a helper line says so.
 */
import { useEffect, useMemo, useState } from 'react';
import { Button, Field, Icon, Input, Modal, NumberInput, Select } from '@/components/ui';
import type { SelectOption } from '@/components/ui';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import type { IplProfile, Vec3 } from '@/lib/types';
import { useAdminShell } from '../shared/shell';

interface Props {
  open: boolean;
  profiles: IplProfile[];
  /** Existing names, to warn about duplicates. */
  names: string[];
  onClose: () => void;
}

const MANUAL = '';
const round2 = (n: number) => Math.round(n * 100) / 100;

export function CreateInteriorModal({ open, profiles, names, onClose }: Props) {
  const shell = useAdminShell();
  const [name, setName] = useState('');
  const [profile, setProfile] = useState<string>(MANUAL);
  const [coords, setCoords] = useState<Vec3>({ x: 0, y: 0, z: 0 });
  const [touched, setTouched] = useState(false);
  const [busy, setBusy] = useState<'create' | 'pick' | null>(null);

  useEffect(() => {
    if (!open) return;
    setName('');
    setProfile(MANUAL);
    setCoords({ x: 0, y: 0, z: 0 });
    setTouched(false);
    setBusy(null);
  }, [open]);

  const usable = useMemo(() => profiles.filter((p) => p.coords), [profiles]);
  const hidden = profiles.length - usable.length;
  const selected = usable.find((p) => p.key === profile) ?? null;

  const options = useMemo<SelectOption<string>[]>(
    () => [
      { value: MANUAL, label: t('Manual coordinates'), hint: t('Any MLO or location'), icon: 'pin' },
      ...usable.map((p) => ({
        value: p.key,
        label: p.label,
        hint: p.slots ? t('{n} slots', { n: p.slots }) : undefined,
        icon: 'building' as const,
      })),
    ],
    [usable],
  );

  const trimmed = name.trim();
  const nameError = touched && !trimmed ? t('Enter a name') : null;
  const duplicate = trimmed && names.some((n) => n.toLowerCase() === trimmed.toLowerCase());
  const zero = !selected && coords.x === 0 && coords.y === 0 && coords.z === 0;
  const coordsError = touched && zero ? t('Type the coordinates or use your current position') : null;
  const valid = !!trimmed && (!!selected || !zero);

  const pick = async () => {
    setBusy('pick');
    const res = await request('admin:pickPosition', {});
    setBusy(null);
    if (res.ok && res.data) setCoords({ x: round2(res.data.x), y: round2(res.data.y), z: round2(res.data.z) });
  };

  const submit = async () => {
    setTouched(true);
    if (!valid || busy) return;
    setBusy('create');
    const res = await request('admin:interior:create', {
      name: trimmed,
      profile: selected ? selected.key : null,
      coords: selected ? null : coords,
    });
    setBusy(null);
    if (res.ok) onClose();
  };

  const setAxis = (axis: keyof Vec3) => (n: number) => setCoords((c) => ({ ...c, [axis]: n }));

  return (
    <Modal
      open={open && !shell.hidden}
      onClose={onClose}
      locked={busy === 'create'}
      icon="building"
      title={t('Create interior')}
      subtitle={t('Set the starting point, then build it in the world')}
      width={460}
      footer={
        <>
          <Button variant="line" onClick={onClose} disabled={busy === 'create'}>
            {t('Cancel')}
          </Button>
          <Button variant="teal" iconRight="arrowRight" onClick={() => void submit()} loading={busy === 'create'} disabled={touched && !valid}>
            {t('Start creator')}
          </Button>
        </>
      }
    >
      <Field label={t('Name')} required error={nameError} hint={duplicate ? t('Another interior already uses this name.') : undefined}>
        <Input
          value={name}
          onChange={setName}
          placeholder={t('e.g. Executive Collection')}
          maxLength={64}
          autoFocus
          onEnter={() => void submit()}
          onBlur={() => name && setTouched(true)}
        />
      </Field>

      <Field
        label={t('IPL profile')}
        hint={hidden > 0 ? t('Some IPL profiles are hidden because no quick-teleport coordinates are known.') : undefined}
      >
        <Select<string> value={profile} onChange={setProfile} options={options} searchable={options.length > 8} />
      </Field>

      {selected ? (
        <div className="nz-aint-profile">
          <span className="nz-aint-profile__icon">
            <Icon name="building" size={16} strokeWidth={1.6} />
          </span>
          <div className="nz-aint-profile__text">
            <b>{selected.label}</b>
            <span>
              {[
                selected.slots ? t('{n} vehicle slots suggested', { n: selected.slots }) : null,
                selected.options.length ? t('{n} style options', { n: selected.options.length }) : null,
              ]
                .filter(Boolean)
                .join(' · ') || t('Loaded automatically')}
            </span>
          </div>
          <span className="nz-aint-profile__coords">
            {selected.coords ? `${selected.coords.x.toFixed(1)}, ${selected.coords.y.toFixed(1)}, ${selected.coords.z.toFixed(1)}` : ''}
          </span>
        </div>
      ) : (
        <div className="nz-aint-coords">
          <div className="nz-aint-coords__grid">
            <Field label="X">
              <NumberInput value={coords.x} onChange={setAxis('x')} min={-20000} max={20000} step={0.01} onEnter={() => void submit()} />
            </Field>
            <Field label="Y">
              <NumberInput value={coords.y} onChange={setAxis('y')} min={-20000} max={20000} step={0.01} onEnter={() => void submit()} />
            </Field>
            <Field label="Z">
              <NumberInput value={coords.z} onChange={setAxis('z')} min={-2000} max={3000} step={0.01} onEnter={() => void submit()} />
            </Field>
          </div>
          <div className="nz-aint-coords__foot">
            <Button size="sm" variant="white" icon="pin" onClick={() => void pick()} loading={busy === 'pick'} disabled={busy === 'create'}>
              {t('Use current position')}
            </Button>
            {coordsError ? (
              <span className="nz-aint-coords__error" role="alert">
                {coordsError}
              </span>
            ) : (
              <span className="nz-aint-coords__hint">{t('You are teleported here to place the entry.')}</span>
            )}
          </div>
        </div>
      )}
    </Modal>
  );
}
