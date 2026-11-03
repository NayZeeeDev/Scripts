/**
 * Impound form (app 'impoundForm'): staff impound the vehicle in front of them.
 * Vehicle + plate (read-only), impound lot, reason, fee, hold time and
 * "retrievable by owner". Vehicles without an owner are simply removed.
 */
import { useMemo, useState } from 'react';
import { Button, Field, Icon, Input, NumberInput, PlateTag, Select, Toggle, Window, Badge } from '@/components/ui';
import type { SelectOption } from '@/components/ui';
import { useApp, useSettings, toast } from '@/lib/store';
import { useEscape } from '@/lib/escape';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import { hoursLabel, money } from '@/lib/format';
import type { ImpoundFormData } from '@/lib/types';
import './impound.css';

const REASON_MAX = 120;
const MAX_FEE = 1_000_000;
const MAX_HOURS = 720;

export function ImpoundFormApp() {
  const { open, data, close } = useApp('impoundForm');
  useEscape(close, open);
  if (!open || !data) return null;
  return <ImpoundForm key={`${data.plate}:${data.netId ?? ''}`} data={data} close={close} />;
}

function ImpoundForm({ data, close }: { data: ImpoundFormData; close: () => void }) {
  const currency = useSettings().currency;
  const [impoundId, setImpoundId] = useState<number | null>(data.defaults.impoundId ?? data.impounds[0]?.id ?? null);
  const [reason, setReason] = useState('');
  const [fee, setFee] = useState(Math.max(0, data.defaults.fee || 0));
  const [hours, setHours] = useState(Math.max(0, data.defaults.hours || 0));
  const [retrievable, setRetrievable] = useState(true);
  const [busy, setBusy] = useState(false);
  const [tried, setTried] = useState(false);

  const impoundOptions: SelectOption<number>[] = useMemo(
    () => data.impounds.map((i) => ({ value: i.id, label: i.name, icon: 'impound' })),
    [data.impounds],
  );

  const noImpounds = data.impounds.length === 0;
  const valid = impoundId !== null || !data.owned;

  const submit = async () => {
    setTried(true);
    if (busy || !valid) return;
    setBusy(true);
    const res = await request('impoundForm:submit', {
      plate: data.plate,
      netId: data.netId,
      impoundId: impoundId ?? data.impounds[0]?.id ?? 0,
      reason: reason.trim(),
      fee: data.owned ? fee : 0,
      hours: data.owned ? hours : 0,
      retrievable: data.owned ? retrievable : false,
    });
    setBusy(false);
    if (!res.ok) return;
    const place = data.impounds.find((i) => i.id === impoundId)?.name ?? '';
    toast({
      type: 'success',
      title: data.owned ? t('Vehicle impounded') : t('Vehicle removed'),
      message: data.owned
        ? t('{plate} was sent to {place}.', { plate: data.plate, place })
        : t('{plate} had no owner and was removed.', { plate: data.plate }),
    });
    close();
  };

  return (
    <Window
      className="nz-impound-form"
      bodyClassName="nz-impound-form__body"
      width={460}
      title={t('Impound vehicle')}
      icon="impound"
      onClose={close}
    >
      <div className="nz-impound-form__vehicle">
        <span className="nz-impound-form__tile">
          <Icon name="car" size={18} strokeWidth={1.6} />
        </span>
        <div className="nz-impound-form__text">
          <b title={data.label}>{data.label || t('Unknown vehicle')}</b>
          <span>
            <PlateTag plate={data.plate} />
            {data.owned ? (
              <Badge tone="neutral" icon="user" size="sm">
                {t('Player owned')}
              </Badge>
            ) : (
              <Badge tone="amber" icon="info" size="sm">
                {t('No owner')}
              </Badge>
            )}
          </span>
        </div>
      </div>

      {!data.owned && (
        <div className="nz-impound-form__notice">
          <Icon name="warning" size={15} strokeWidth={1.8} />
          <span>
            {t('This vehicle has no owner and will be removed.')}
            <small>{t('Fees, hold time and release options only apply to player-owned vehicles.')}</small>
          </span>
        </div>
      )}

      {data.owned && (
        <Field
          label={t('Impound')}
          required
          error={tried && impoundId === null ? t('Choose where the vehicle goes.') : undefined}
          hint={noImpounds ? t('No impound lots are set up for your job.') : undefined}
        >
          <Select<number>
            value={impoundId}
            onChange={setImpoundId}
            options={impoundOptions}
            placeholder={t('Choose an impound')}
            icon="impound"
            disabled={noImpounds}
          />
        </Field>
      )}

      <Field
        label={t('Reason')}
        hint={data.owned ? t('Optional — the owner sees this when they collect the vehicle.') : t('Optional — kept in the impound log.')}
      >
        <Input
          value={reason}
          onChange={setReason}
          placeholder={t('e.g. Parked in a fire lane')}
          maxLength={REASON_MAX}
          icon="edit"
          autoFocus
          onEnter={() => void submit()}
        />
      </Field>

      {data.owned && (
        <>
          <div className="nz-impound-form__row">
            <Field label={t('Retrieval fee')} hint={fee > 0 ? t('Owner pays {fee}', { fee: money(fee) }) : t('Free to collect')}>
              <NumberInput value={fee} onChange={setFee} min={0} max={MAX_FEE} step={50} prefix={currency} onEnter={() => void submit()} />
            </Field>
            <Field label={t('Hold time')} hint={hours > 0 ? t('Available after {time}', { time: hoursLabel(hours) }) : t('0 = available immediately')}>
              <NumberInput value={hours} onChange={setHours} min={0} max={MAX_HOURS} step={1} suffix={t('hours')} onEnter={() => void submit()} />
            </Field>
          </div>
          <div className="nz-impound-form__toggle">
            <Toggle
              checked={retrievable}
              onChange={setRetrievable}
              label={t('Retrievable by owner')}
              description={
                retrievable
                  ? t('The owner can pay the fee and drive it away once the hold time is over.')
                  : t('Staff must release it first — use this for evidence or serious offences.')
              }
            />
          </div>
        </>
      )}

      <div className="nz-impound-form__actions">
        <Button variant="line" onClick={close} disabled={busy}>
          {t('Cancel')}
        </Button>
        <Button variant="red" icon="impound" loading={busy} disabled={data.owned && noImpounds} onClick={() => void submit()}>
          {t('Impound vehicle')}
        </Button>
      </div>
    </Window>
  );
}
