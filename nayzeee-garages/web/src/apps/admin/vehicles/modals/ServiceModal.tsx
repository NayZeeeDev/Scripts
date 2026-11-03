/**
 * Service history editor: edit / delete each entry, add entries, save the whole list
 * (admin:vehicle:update { patch: { service } }).
 */
import { useEffect, useMemo, useState } from 'react';
import { Button, EmptyState, Field, IconButton, Input, Modal, NumberInput, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import { date, distance, distanceValue, toKm } from '@/lib/format';
import { useSettings } from '@/lib/store';
import type { AdminVehicleDetail, AdminVehiclePatch, ServiceEntry } from '@/lib/types';
import { isoDay, parseIsoDay } from '../util';

interface Props {
  open: boolean;
  detail: AdminVehicleDetail;
  onClose: () => void;
  onSave: (patch: AdminVehiclePatch, message: string) => Promise<boolean>;
}

interface Row extends ServiceEntry {
  /** Local key (entries may not have an id yet). */
  key: string;
}

interface Form {
  item: string;
  shop: string;
  mileage: number;
  day: string;
}

let seq = 0;
const SUGGEST = ['Engine oil', 'Spark plugs', 'Air filter', 'Brake pads', 'Tyres', 'Suspension', 'Coolant', 'Clutch'];

export function ServiceModal({ open, detail, onClose, onSave }: Props) {
  const unit = useSettings().distanceUnit;
  const [rows, setRows] = useState<Row[]>([]);
  const [editing, setEditing] = useState<string | null>(null);
  const [form, setForm] = useState<Form>({ item: '', shop: '', mileage: 0, day: isoDay(0) });
  const [busy, setBusy] = useState(false);

  const original = useMemo(() => [...detail.service].sort((a, b) => b.at - a.at), [detail.service]);

  useEffect(() => {
    if (!open) return;
    setRows(original.map((s) => ({ ...s, key: `s${s.id ?? ++seq}` })));
    setEditing(null);
  }, [open, original]);

  const dirty = JSON.stringify(rows.map(({ key: _k, ...s }) => s)) !== JSON.stringify(original);

  const startEdit = (r: Row) => {
    setEditing(r.key);
    setForm({ item: r.item, shop: r.shop, mileage: Math.round(distanceValue(r.mileage)), day: isoDay(r.at) });
  };

  const startAdd = () => {
    const key = `new${++seq}`;
    const row: Row = { key, item: '', shop: rows[0]?.shop ?? '', mileage: detail.vehicle.mileage, at: Math.floor(Date.now() / 1000) };
    setRows((list) => [row, ...list]);
    setEditing(key);
    setForm({ item: '', shop: row.shop, mileage: Math.round(distanceValue(detail.vehicle.mileage)), day: isoDay(row.at) });
  };

  const dayAt = parseIsoDay(form.day);
  const formError = !form.item.trim() ? t('Enter what was serviced') : dayAt === null ? t('Use the format YYYY-MM-DD') : null;

  const apply = () => {
    if (!editing || formError || dayAt === null) return;
    setRows((list) =>
      list
        .map((r) => (r.key === editing ? { ...r, item: form.item.trim(), shop: form.shop.trim(), mileage: Math.round(toKm(form.mileage) * 10) / 10, at: dayAt } : r))
        .sort((a, b) => b.at - a.at),
    );
    setEditing(null);
  };

  const cancelEdit = () => {
    // A brand-new entry that was never applied is dropped.
    setRows((list) => list.filter((r) => !(r.key === editing && !r.item)));
    setEditing(null);
  };

  const submit = async () => {
    if (busy || !dirty || editing) return;
    setBusy(true);
    const ok = await onSave({ service: rows.map(({ key: _k, ...s }) => s) }, t('Service history saved'));
    setBusy(false);
    if (ok) onClose();
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      locked={busy}
      icon="wrench"
      title={t('Service history')}
      subtitle={`${detail.vehicle.label} · ${t('{n} entries', { n: rows.filter((r) => r.item).length })}`}
      width={560}
      bodyClassName="nz-aveh-svc__body"
      footer={
        <>
          <Button variant="line" icon="plus" onClick={startAdd} disabled={!!editing || busy} className="nz-aveh-foot-left">
            {t('Add entry')}
          </Button>
          <Button variant="line" onClick={onClose} disabled={busy}>
            {t('Cancel')}
          </Button>
          <Button variant="teal" icon="save" onClick={submit} loading={busy} disabled={!dirty || !!editing}>
            {t('Save')}
          </Button>
        </>
      }
    >
      {rows.length === 0 ? (
        <EmptyState
          icon="wrench"
          title={t('No service records')}
          description={t('Add the first entry to start the history of this vehicle.')}
          action={
            <Button size="sm" variant="teal" icon="plus" onClick={startAdd}>
              {t('Add entry')}
            </Button>
          }
        />
      ) : (
        <ul className="nz-aveh-svc">
          {rows.map((r) =>
            r.key === editing ? (
              <li key={r.key} className="nz-aveh-svc__form">
                <div className="nz-aveh-form2">
                  <Field label={t('Item')} required>
                    <Input value={form.item} onChange={(item) => setForm((f) => ({ ...f, item }))} placeholder={t('e.g. Engine oil')} maxLength={64} autoFocus onEnter={apply} />
                  </Field>
                  <Field label={t('Shop')}>
                    <Input value={form.shop} onChange={(shop) => setForm((f) => ({ ...f, shop }))} placeholder={t('e.g. Los Santos Customs')} maxLength={64} onEnter={apply} />
                  </Field>
                  <Field label={t('Mileage')}>
                    <NumberInput value={form.mileage} onChange={(mileage) => setForm((f) => ({ ...f, mileage }))} min={0} max={9999999} suffix={unit} onEnter={apply} />
                  </Field>
                  <Field label={t('Date')} error={form.day && dayAt === null ? t('Use the format YYYY-MM-DD') : undefined}>
                    <Input value={form.day} onChange={(day) => setForm((f) => ({ ...f, day }))} placeholder="YYYY-MM-DD" mono maxLength={10} icon="calendar" onEnter={apply} />
                  </Field>
                </div>
                <div className="nz-aveh-svc__suggest">
                  {SUGGEST.map((s) => (
                    <button key={s} type="button" className={cx('nz-aveh-svc__pill', form.item === t(s) && 'is-on')} onClick={() => setForm((f) => ({ ...f, item: t(s) }))}>
                      {t(s)}
                    </button>
                  ))}
                </div>
                <div className="nz-aveh-svc__formfoot">
                  <Button size="sm" variant="ghost" onClick={cancelEdit}>
                    {t('Cancel')}
                  </Button>
                  <Button size="sm" variant="white" icon="check" onClick={apply} disabled={!!formError}>
                    {t('Apply')}
                  </Button>
                </div>
              </li>
            ) : (
              <li key={r.key} className="nz-aveh-svc__row">
                <span className="nz-aveh-svc__dot" aria-hidden="true" />
                <div className="nz-aveh-svc__text">
                  <b>
                    {r.item}
                    <span className="nz-aveh-mono">{distance(r.mileage)}</span>
                  </b>
                  <span>
                    {r.shop || t('Unknown shop')} · {date(r.at)}
                  </span>
                </div>
                <IconButton icon="edit" size="sm" label={t('Edit')} onClick={() => startEdit(r)} disabled={!!editing} />
                <IconButton icon="trash" size="sm" variant="red" label={t('Delete')} onClick={() => setRows((list) => list.filter((x) => x.key !== r.key))} disabled={!!editing} />
              </li>
            ),
          )}
        </ul>
      )}
    </Modal>
  );
}
