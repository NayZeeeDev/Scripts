/**
 * Impound editor: put a vehicle in an impound (or change the impound record) and release it.
 */
import { useMemo, useState } from 'react';
import { Button, ConfirmDialog, Field, Input, Modal, NumberInput, Select, Toggle } from '@/components/ui';
import { t } from '@/lib/i18n';
import { useSettings } from '@/lib/store';
import type { AdminOpenData, AdminVehicleDetail, AdminVehiclePatch } from '@/lib/types';

interface Props {
  open: boolean;
  data: AdminOpenData;
  detail: AdminVehicleDetail;
  onClose: () => void;
  onSave: (patch: AdminVehiclePatch, message: string) => Promise<boolean>;
}

const nowS = () => Math.floor(Date.now() / 1000);

export function ImpoundModal({ open, data, detail, onClose, onSave }: Props) {
  const currency = useSettings().currency;
  const cur = detail.impound;
  const defaults = (id: number | null) => {
    const loc = data.locations.find((l) => l.kind === 'impound' && l.id === id);
    return loc && loc.kind === 'impound' ? { fee: loc.defaultFee, hours: loc.defaultHours } : { fee: data.settings.impound.defaultFee, hours: data.settings.impound.defaultHours };
  };

  // Initial values (the parent remounts this modal on every open).
  const [init] = useState(() => {
    if (cur) {
      return {
        impound: cur.locationId as number | null,
        reason: cur.reason,
        fee: cur.fee,
        hours: Math.max(0, Math.ceil((cur.releaseAt - nowS()) / 3600)),
        retrievable: cur.retrievable,
      };
    }
    const first = detail.impounds[0]?.id ?? null;
    const d = defaults(first);
    return { impound: first, reason: '', fee: d.fee, hours: d.hours, retrievable: true };
  });
  const [impound, setImpound] = useState<number | null>(init.impound);
  const [reason, setReason] = useState(init.reason);
  const [fee, setFee] = useState(init.fee);
  const [hours, setHours] = useState(init.hours);
  const [retrievable, setRetrievable] = useState(init.retrievable);
  const [busy, setBusy] = useState<'save' | 'release' | null>(null);
  const [confirmRelease, setConfirmRelease] = useState(false);

  const options = useMemo(() => detail.impounds.map((i) => ({ value: i.id, label: i.name, icon: 'impound' as const })), [detail.impounds]);

  const submit = async () => {
    if (busy || impound === null) return;
    setBusy('save');
    const ok = await onSave(
      { impound: { locationId: impound, reason: reason.trim(), fee, releaseAt: nowS() + Math.round(hours * 3600), retrievable } },
      cur ? t('Impound record updated') : t('Vehicle impounded'),
    );
    setBusy(null);
    if (ok) onClose();
  };

  const release = async () => {
    setBusy('release');
    const ok = await onSave({ impound: false }, t('Vehicle released from the impound'));
    setBusy(null);
    setConfirmRelease(false);
    if (ok) onClose();
  };

  return (
    <>
      <Modal
        open={open && !confirmRelease}
        onClose={onClose}
        locked={!!busy}
        icon="impound"
        title={cur ? t('Edit impound') : t('Impound vehicle')}
        subtitle={`${detail.vehicle.label} · ${detail.vehicle.plate}`}
        width={480}
        footer={
          <>
            {cur && (
              <Button variant="red" icon="unlock" onClick={() => setConfirmRelease(true)} disabled={!!busy} className="nz-aveh-foot-left">
                {t('Release')}
              </Button>
            )}
            <Button variant="line" onClick={onClose} disabled={!!busy}>
              {t('Cancel')}
            </Button>
            <Button variant="teal" icon={cur ? 'save' : 'impound'} onClick={submit} loading={busy === 'save'} disabled={impound === null}>
              {cur ? t('Save') : t('Impound')}
            </Button>
          </>
        }
      >
        <Field label={t('Impound')} required hint={options.length ? undefined : t('Create an impound location first.')}>
          <Select
            value={impound}
            onChange={(id) => {
              setImpound(id);
              if (!cur) {
                const d = defaults(id);
                setFee(d.fee);
                setHours(d.hours);
              }
            }}
            options={options}
            placeholder={t('Choose an impound')}
            disabled={!options.length}
          />
        </Field>
        <Field label={t('Reason')}>
          <Input value={reason} onChange={setReason} placeholder={t('e.g. Parked on the sidewalk')} maxLength={120} onEnter={submit} />
        </Field>
        <div className="nz-aveh-form2">
          <Field label={t('Fee')}>
            <NumberInput value={fee} onChange={setFee} min={0} max={10000000} step={50} prefix={currency} onEnter={submit} />
          </Field>
          <Field label={t('Retrievable in')} hint={t('0 = right away')}>
            <NumberInput value={hours} onChange={setHours} min={0} max={720} step={1} suffix={t('hours')} onEnter={submit} />
          </Field>
        </div>
        <Toggle
          checked={retrievable}
          onChange={setRetrievable}
          label={t('Owner can retrieve it')}
          description={t('When off, only impound staff can release this vehicle.')}
        />
      </Modal>
      <ConfirmDialog
        open={open && confirmRelease}
        tone="red"
        icon="unlock"
        title={t('Release vehicle?')}
        message={t('{vehicle} leaves {impound} without paying the fee and goes back to its garage.', {
          vehicle: detail.vehicle.label,
          impound: cur?.locationName ?? t('the impound'),
        })}
        confirmLabel={t('Release')}
        busy={busy === 'release'}
        onConfirm={release}
        onCancel={() => setConfirmRelease(false)}
      />
    </>
  );
}
