/**
 * Finance editor: create or change a vehicle's finance agreement.
 */
import { useEffect, useState } from 'react';
import { Button, Field, Modal, NumberInput, Toggle } from '@/components/ui';
import { t } from '@/lib/i18n';
import { money } from '@/lib/format';
import { useSettings } from '@/lib/store';
import type { AdminVehicleDetail, AdminVehiclePatch, Finance } from '@/lib/types';

interface Props {
  open: boolean;
  detail: AdminVehicleDetail;
  onClose: () => void;
  onSave: (patch: AdminVehiclePatch, message: string) => Promise<boolean>;
}

const blank = (): Finance => ({
  balance: 0,
  payment: 0,
  paymentsLeft: 12,
  paymentsTotal: 12,
  intervalHours: 24,
  nextPaymentHours: 24,
  overdue: false,
});

export function FinanceModal({ open, detail, onClose, onSave }: Props) {
  const currency = useSettings().currency;
  const existing = detail.finance;
  const [f, setF] = useState<Finance>(existing ?? blank());
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (open) setF(existing ? { ...existing } : blank());
  }, [open, existing]);

  const set = <K extends keyof Finance>(k: K, v: Finance[K]) => setF((x) => ({ ...x, [k]: v }));
  const total = f.paymentsTotal ?? 0;
  const made = total ? Math.max(0, total - f.paymentsLeft) : null;
  const errors = {
    balance: f.balance <= 0 ? t('The balance must be above 0 — delete the finance instead to clear it.') : null,
    payments: total > 0 && f.paymentsLeft > total ? t('More payments left than in total') : null,
  };
  const valid = !errors.balance && !errors.payments;
  const covered = f.payment * f.paymentsLeft;

  const submit = async () => {
    if (!valid || busy) return;
    setBusy(true);
    const ok = await onSave(
      { finance: { ...f, paymentsTotal: total > 0 ? total : null, intervalHours: f.intervalHours || null, nextPaymentHours: f.nextPaymentHours ?? null } },
      existing ? t('Finance updated') : t('Finance added'),
    );
    setBusy(false);
    if (ok) onClose();
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      locked={busy}
      icon="money"
      title={existing ? t('Edit finance') : t('Add finance')}
      subtitle={`${detail.vehicle.label} · ${detail.vehicle.plate}`}
      width={500}
      footer={
        <>
          <Button variant="line" onClick={onClose} disabled={busy}>
            {t('Cancel')}
          </Button>
          <Button variant="teal" icon="save" onClick={submit} loading={busy} disabled={!valid}>
            {t('Save')}
          </Button>
        </>
      }
    >
      <div className="nz-aveh-form2">
        <Field label={t('Remaining balance')} error={errors.balance}>
          <NumberInput value={f.balance} onChange={(n) => set('balance', n)} min={0} max={100000000} step={1000} prefix={currency} onEnter={submit} />
        </Field>
        <Field label={t('Payment')}>
          <NumberInput value={f.payment} onChange={(n) => set('payment', n)} min={0} max={10000000} step={500} prefix={currency} onEnter={submit} />
        </Field>
        <Field label={t('Payments left')} error={errors.payments}>
          <NumberInput value={f.paymentsLeft} onChange={(n) => set('paymentsLeft', Math.round(n))} min={0} max={1000} onEnter={submit} />
        </Field>
        <Field label={t('Total payments')} hint={t('0 = open-ended')}>
          <NumberInput value={total} onChange={(n) => set('paymentsTotal', Math.round(n))} min={0} max={1000} onEnter={submit} />
        </Field>
        <Field label={t('Payment every')}>
          <NumberInput value={f.intervalHours ?? 0} onChange={(n) => set('intervalHours', n)} min={0} max={8760} suffix={t('hours')} onEnter={submit} />
        </Field>
        <Field label={t('Next payment in')}>
          <NumberInput value={f.nextPaymentHours ?? 0} onChange={(n) => set('nextPaymentHours', n)} min={0} max={8760} step={0.5} suffix={t('hours')} onEnter={submit} />
        </Field>
      </div>
      <Toggle
        checked={f.overdue}
        onChange={(b) => set('overdue', b)}
        label={t('Overdue')}
        description={t('Marks a missed payment. Your finance script decides what happens next.')}
      />
      <div className="nz-aveh-sum">
        <span>
          {made !== null ? t('{made} of {total} payments made', { made, total }) : t('Open-ended agreement')}
        </span>
        <span>
          {t('Scheduled payments cover')} <b>{money(covered)}</b>
          {covered !== f.balance && f.payment > 0 && <em>{covered > f.balance ? t(' (more than the balance)') : t(' (less than the balance)')}</em>}
        </span>
      </div>
    </Modal>
  );
}
