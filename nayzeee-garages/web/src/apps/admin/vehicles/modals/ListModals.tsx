/**
 * Read-only "View all" modals of the vehicle detail: ownership history, service history and
 * every installed modification.
 */
import { Button, EmptyState, Icon, Modal } from '@/components/ui';
import { t } from '@/lib/i18n';
import { date, distance, money } from '@/lib/format';
import type { AdminVehicleDetail } from '@/lib/types';
import { Timeline } from '../common';
import { viaLabel } from '../util';
import { CATEGORIES, describe, isSet } from '../props/catalog';

interface Base {
  open: boolean;
  detail: AdminVehicleDetail;
  onClose: () => void;
}

export function OwnershipModal({ open, detail, onClose }: Base) {
  const list = detail.ownership;
  return (
    <Modal
      open={open}
      onClose={onClose}
      icon="history"
      title={t('Ownership history')}
      subtitle={t('{vehicle} · {n} owners', { vehicle: detail.vehicle.label, n: list.length })}
      width={480}
      footer={<Button onClick={onClose}>{t('Close')}</Button>}
    >
      {list.length === 0 ? (
        <EmptyState compact icon="history" title={t('No ownership records')} />
      ) : (
        <Timeline
          className="is-roomy"
          items={list.map((o, i) => ({
            key: `${o.identifier ?? 'x'}-${o.at}-${i}`,
            current: i === 0,
            title: (
              <>
                {o.name || t('Unknown')}
                {i === 0 && <em className="nz-aveh-tl__now">{t('Current')}</em>}
              </>
            ),
            meta: `${viaLabel(o.via)} · ${date(o.at)}${o.identifier ? ` · ${o.identifier}` : ''}`,
            aside: o.price ? money(o.price) : undefined,
          }))}
        />
      )}
    </Modal>
  );
}

export function ServiceListModal({ open, detail, onClose, onEdit }: Base & { onEdit: () => void }) {
  const list = [...detail.service].sort((a, b) => b.at - a.at);
  return (
    <Modal
      open={open}
      onClose={onClose}
      icon="wrench"
      title={t('Service history')}
      subtitle={t('{vehicle} · {n} entries', { vehicle: detail.vehicle.label, n: list.length })}
      width={500}
      footer={
        <>
          <Button variant="line" icon="edit" onClick={onEdit} className="nz-aveh-foot-left">
            {t('Edit history')}
          </Button>
          <Button onClick={onClose}>{t('Close')}</Button>
        </>
      }
    >
      {list.length === 0 ? (
        <EmptyState compact icon="wrench" title={t('No service records')} />
      ) : (
        <Timeline
          className="is-roomy"
          items={list.map((s, i) => ({
            key: s.id ?? `${s.at}-${i}`,
            current: i === 0,
            title: s.item,
            meta: `${s.shop || t('Unknown shop')} · ${date(s.at)}`,
            aside: <span className="nz-aveh-mono">{distance(s.mileage)}</span>,
          }))}
        />
      )}
    </Modal>
  );
}

export function ModsModal({ open, detail, onClose, onEdit }: Base & { onEdit: () => void }) {
  const props = detail.vehicle.props ?? {};
  const groups = CATEGORIES.map((c) => ({ c, fields: c.fields.filter((f) => isSet(f, props)) })).filter((g) => g.fields.length > 0);
  return (
    <Modal
      open={open}
      onClose={onClose}
      icon="sliders"
      title={t('Installed modifications')}
      subtitle={detail.vehicle.label}
      width={520}
      footer={
        <>
          <Button variant="line" icon="edit" onClick={onEdit} className="nz-aveh-foot-left">
            {t('Edit props')}
          </Button>
          <Button onClick={onClose}>{t('Close')}</Button>
        </>
      }
    >
      {groups.length === 0 ? (
        <EmptyState compact icon="sliders" title={t('Stock vehicle')} description={t('No modifications are saved for this vehicle.')} />
      ) : (
        <div className="nz-aveh-modlist">
          {groups.map(({ c, fields }) => (
            <section key={c.id}>
              <h4>
                <Icon name={c.icon} size={13} strokeWidth={1.7} />
                {c.label()}
                <span>{fields.length}</span>
              </h4>
              <dl>
                {fields.map((f) => (
                  <div key={f.key}>
                    <dt>{f.label()}</dt>
                    <dd>{describe(f, props)}</dd>
                  </div>
                ))}
              </dl>
            </section>
          ))}
        </div>
      )}
    </Modal>
  );
}
