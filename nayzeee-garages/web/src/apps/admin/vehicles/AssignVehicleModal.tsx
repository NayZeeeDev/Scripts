/**
 * Assign vehicle modal: give a player a new vehicle (admin:vehicle:assign).
 */
import { useEffect, useMemo, useState } from 'react';
import { Button, Field, Input, Modal, Select } from '@/components/ui';
import { request } from '@/lib/nui';
import { toast } from '@/lib/store';
import { t } from '@/lib/i18n';
import type { AdminOpenData, AdminVehicleRow } from '@/lib/types';
import { useAdminShell } from '../shared/shell';
import { assignableGarages } from './util';

interface Props {
  open: boolean;
  data: AdminOpenData;
  identifier: string;
  playerName: string;
  onClose: () => void;
  onAssigned: (row: AdminVehicleRow) => void;
}

const MODEL_RE = /^[a-z0-9_]{2,32}$/;
const PLATE_RE = /^[A-Z0-9 ]{1,8}$/;

export function AssignVehicleModal({ open, data, identifier, playerName, onClose, onAssigned }: Props) {
  const shell = useAdminShell();
  const garages = useMemo(() => assignableGarages(data), [data]);
  const [model, setModel] = useState('');
  const [plate, setPlate] = useState('');
  const [garage, setGarage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [touched, setTouched] = useState(false);

  useEffect(() => {
    if (!open) return;
    setModel('');
    setPlate('');
    setTouched(false);
    setGarage((g) => (g && garages.some((x) => x.value === g) ? g : garages[0]?.value ?? null));
  }, [open, garages]);

  const m = model.trim().toLowerCase();
  const p = plate.trim().toUpperCase();
  const modelError = !touched ? null : !m ? t('Enter the spawn code of the vehicle') : !MODEL_RE.test(m) ? t('Use the spawn code: letters, digits and underscores') : null;
  const plateError = p && !PLATE_RE.test(p) ? t('Plates have 1 to 8 letters, digits or spaces') : null;
  const valid = MODEL_RE.test(m) && !plateError && !!garage;

  const submit = async () => {
    setTouched(true);
    if (!valid || busy || !garage) return;
    setBusy(true);
    const res = await request('admin:vehicle:assign', { identifier, model: m, plate: p, garageKey: garage });
    setBusy(false);
    if (!res.ok) return;
    toast({ type: 'success', title: t('Vehicle assigned'), message: t('{vehicle} ({plate}) was added to {player}.', { vehicle: res.data.label || res.data.model, plate: res.data.plate, player: playerName }) });
    onAssigned(res.data);
    onClose();
  };

  return (
    <Modal
      open={open && !shell.hidden}
      onClose={onClose}
      locked={busy}
      icon="userPlus"
      title={t('Assign vehicle')}
      subtitle={t('Add a vehicle to {player}', { player: playerName })}
      width={440}
      footer={
        <>
          <Button variant="line" onClick={onClose} disabled={busy}>
            {t('Cancel')}
          </Button>
          <Button variant="teal" icon="plus" onClick={submit} loading={busy} disabled={!valid && touched}>
            {t('Assign')}
          </Button>
        </>
      }
    >
      <Field label={t('Model')} required error={modelError} hint={t('The spawn code, e.g. sultan or adder.')}>
        <Input value={model} onChange={(v) => setModel(v.replace(/\s+/g, ''))} placeholder="sultan" mono icon="car" maxLength={32} onEnter={submit} onBlur={() => model && setTouched(true)} />
      </Field>
      <Field label={t('Vehicle plate')} error={plateError} hint={t('Optional — leave blank for a random free plate.')}>
        <Input value={plate} onChange={setPlate} placeholder={t('Random')} mono uppercase maxLength={8} icon="tag" onEnter={submit} />
      </Field>
      <Field label={t('Garage')} required hint={garages.length ? undefined : t('Create a garage first — vehicles must be parked somewhere.')}>
        <Select value={garage} onChange={setGarage} options={garages} placeholder={t('Choose a garage')} disabled={!garages.length} searchable={garages.length > 6} />
      </Field>
    </Modal>
  );
}
