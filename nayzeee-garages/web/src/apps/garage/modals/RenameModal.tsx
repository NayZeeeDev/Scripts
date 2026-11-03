/**
 * Rename (nickname) modal. Empty input resets to the default vehicle name.
 */
import { useEffect, useState } from 'react';
import { Button, Field, Input, Modal } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { GarageVehicle } from '@/lib/types';
import { ModalVehicle } from './ModalVehicle';

export const NICKNAME_MAX = 32;

export function RenameModal({
  vehicle,
  onClose,
  onSave,
}: {
  vehicle: GarageVehicle | null;
  onClose: () => void;
  /** null = reset to default. Resolves when saved (optimistic in the caller). */
  onSave: (v: GarageVehicle, name: string | null) => void;
}) {
  const [value, setValue] = useState('');
  useEffect(() => {
    if (vehicle) setValue(vehicle.nickname ?? '');
  }, [vehicle]);

  const trimmed = value.trim();
  const unchanged = vehicle ? trimmed === (vehicle.nickname ?? '').trim() : true;
  const submit = () => {
    if (!vehicle || unchanged) return;
    onSave(vehicle, trimmed ? trimmed : null);
  };

  return (
    <Modal
      open={!!vehicle}
      title={t('Rename vehicle')}
      icon="edit"
      onClose={onClose}
      width={420}
      footer={
        <>
          {vehicle?.nickname && (
            <Button variant="ghost" icon="refresh" className="nz-garage__foot-left" onClick={() => vehicle && onSave(vehicle, null)}>
              {t('Reset name')}
            </Button>
          )}
          <Button variant="line" onClick={onClose}>
            {t('Cancel')}
          </Button>
          <Button variant="teal" icon="check" disabled={unchanged} onClick={submit}>
            {t('Save')}
          </Button>
        </>
      }
    >
      {vehicle && (
        <>
          <ModalVehicle v={vehicle} />
          <Field label={t('Nickname')} hint={t('Leave empty to use the default name ({name}).', { name: vehicle.label })}>
            <Input
              value={value}
              onChange={setValue}
              placeholder={vehicle.label}
              maxLength={NICKNAME_MAX}
              autoFocus
              icon="edit"
              onEnter={submit}
            />
          </Field>
        </>
      )}
    </Modal>
  );
}
