/**
 * Compact vehicle identity strip used at the top of the garage modals.
 */
import type { ReactNode } from 'react';
import { PlateTag, VehicleImage } from '@/components/ui';
import type { GarageVehicle } from '@/lib/types';
import { displayName } from '../model';

export function ModalVehicle({ v, aside }: { v: GarageVehicle; aside?: ReactNode }) {
  const name = displayName(v);
  return (
    <div className="nz-garage__mv">
      <div className="nz-garage__mv-img">
        <VehicleImage image={v.image} vehicleType={v.vehicleType} alt={v.label} className="nz-garage__img" />
      </div>
      <div className="nz-garage__mv-text">
        <b title={name}>{name}</b>
        <span>
          <PlateTag plate={v.plate} size="sm" />
          {v.nickname && <em title={v.label}>{v.label}</em>}
        </span>
      </div>
      {aside && <div className="nz-garage__mv-aside">{aside}</div>}
    </div>
  );
}
