/**
 * Edit vehicle details: garage, state, nickname, mileage (in the configured unit), fuel /
 * engine / body and the plate. Sends only what changed.
 */
import { useEffect, useMemo, useState } from 'react';
import { Button, Field, Icon, Input, Modal, NumberInput, Select, Slider } from '@/components/ui';
import { t } from '@/lib/i18n';
import { distanceValue, toKm } from '@/lib/format';
import { useSettings } from '@/lib/store';
import type { AdminVehicleDetail, AdminVehiclePatch, VehicleState } from '@/lib/types';
import { stateLabel } from '../util';

interface Props {
  open: boolean;
  detail: AdminVehicleDetail;
  onClose: () => void;
  onSave: (patch: AdminVehiclePatch, message: string) => Promise<boolean>;
}

const PLATE_RE = /^[A-Z0-9 ]{1,8}$/;
const round1 = (n: number) => Math.round(n * 10) / 10;

export function DetailsModal({ open, detail, onClose, onSave }: Props) {
  const unit = useSettings().distanceUnit;
  const v = detail.vehicle;
  const [garage, setGarage] = useState<string | null>(v.garageKey);
  const [state, setState] = useState<VehicleState>(v.state);
  const [nickname, setNickname] = useState(v.nickname ?? '');
  const [mileage, setMileage] = useState(round1(distanceValue(v.mileage)));
  const [fuel, setFuel] = useState(Math.round(v.fuel));
  const [engine, setEngine] = useState(Math.round(v.engine));
  const [body, setBody] = useState(Math.round(v.body));
  const [plate, setPlate] = useState(v.plate);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!open) return;
    setGarage(v.garageKey);
    setState(v.state);
    setNickname(v.nickname ?? '');
    setMileage(round1(distanceValue(v.mileage)));
    setFuel(Math.round(v.fuel));
    setEngine(Math.round(v.engine));
    setBody(Math.round(v.body));
    setPlate(v.plate);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, detail]);

  const garageOptions = useMemo(() => {
    const list = detail.garages.map((g) => ({ value: g.key, label: g.name }));
    if (v.garageKey && !list.some((g) => g.value === v.garageKey)) list.push({ value: v.garageKey, label: v.garageName ?? v.garageKey });
    return list;
  }, [detail.garages, v.garageKey, v.garageName]);

  const stateOptions = (['garaged', 'out', 'impounded'] as VehicleState[]).map((s) => ({
    value: s,
    label: stateLabel(s),
    hint: s === 'impounded' && !detail.impound ? t('Use the Impound panel') : undefined,
    disabled: s === 'impounded' && !detail.impound,
  }));

  const p = plate.trim().toUpperCase();
  const plateChanged = p !== v.plate;
  const plateError = !PLATE_RE.test(p) ? t('Plates have 1 to 8 letters, digits or spaces') : null;

  const patch = useMemo<AdminVehiclePatch>(() => {
    const d: NonNullable<AdminVehiclePatch['details']> = {};
    if (garage !== v.garageKey && garage) d.garageKey = garage;
    if (state !== v.state) d.state = state;
    if (nickname.trim() !== (v.nickname ?? '')) d.nickname = nickname.trim(); // '' clears it (server)
    if (Math.abs(mileage - round1(distanceValue(v.mileage))) >= 0.05) d.mileage = Math.round(toKm(mileage) * 100) / 100;
    if (fuel !== Math.round(v.fuel)) d.fuel = fuel;
    if (engine !== Math.round(v.engine)) d.engine = engine;
    if (body !== Math.round(v.body)) d.body = body;
    const out: AdminVehiclePatch = {};
    if (Object.keys(d).length) out.details = d;
    if (plateChanged) out.plate = p;
    return out;
  }, [garage, state, nickname, mileage, fuel, engine, body, plateChanged, p, v]);

  const dirty = Object.keys(patch).length > 0;

  const submit = async () => {
    if (!dirty || busy || plateError) return;
    setBusy(true);
    const ok = await onSave(patch, plateChanged ? t('Details saved — new plate {plate}', { plate: p }) : t('Vehicle details saved'));
    setBusy(false);
    if (ok) onClose();
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      locked={busy}
      icon="edit"
      title={t('Edit details')}
      subtitle={`${v.label} · ${v.plate}`}
      width={540}
      footer={
        <>
          <Button variant="line" onClick={onClose} disabled={busy}>
            {t('Cancel')}
          </Button>
          <Button variant="teal" icon="save" onClick={submit} loading={busy} disabled={!dirty || !!plateError}>
            {t('Save')}
          </Button>
        </>
      }
    >
      <div className="nz-aveh-form2">
        <Field label={t('Garage')}>
          <Select value={garage} onChange={setGarage} options={garageOptions} placeholder={t('No garage')} searchable={garageOptions.length > 8} />
        </Field>
        <Field label={t('State')}>
          <Select value={state} onChange={setState} options={stateOptions} />
        </Field>
        <Field label={t('Nickname')} hint={t('Leave empty to use the model name.')}>
          <Input value={nickname} onChange={setNickname} placeholder={t('None')} maxLength={32} onEnter={submit} />
        </Field>
        <Field label={t('Mileage')}>
          <NumberInput value={mileage} onChange={setMileage} min={0} max={9999999} step={0.1} suffix={unit} onEnter={submit} />
        </Field>
      </div>

      <div className="nz-aveh-sliders">
        <Field label={t('Fuel')}>
          <Slider value={fuel} onChange={setFuel} min={0} max={100} suffix="%" />
        </Field>
        <Field label={t('Engine')}>
          <Slider value={engine} onChange={setEngine} min={0} max={100} suffix="%" />
        </Field>
        <Field label={t('Body')}>
          <Slider value={body} onChange={setBody} min={0} max={100} suffix="%" />
        </Field>
      </div>

      <Field label={t('Plate')} error={plateError}>
        <Input value={plate} onChange={setPlate} uppercase mono maxLength={8} icon="tag" onEnter={submit} />
      </Field>
      {plateChanged && !plateError && (
        <div className="nz-aveh-warn" role="note">
          <Icon name="warning" size={15} strokeWidth={1.8} />
          <span>
            {t('Changing the plate renames this vehicle everywhere (keys, history, shares). The vehicle must be stored first and the new plate must be free.')}
          </span>
        </div>
      )}
    </Modal>
  );
}
