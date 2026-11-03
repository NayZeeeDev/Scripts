/**
 * Read-only "All modifications" modal of the dossier (Upgrades & paint tab): every
 * installed modification grouped by props-editor category.
 */
import { Button, EmptyState, Icon, Modal } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { AdminVehicleDetail } from '@/lib/types';
import { CATEGORIES, describe, isSet } from '../props/catalog';

interface Base {
  open: boolean;
  detail: AdminVehicleDetail;
  onClose: () => void;
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
