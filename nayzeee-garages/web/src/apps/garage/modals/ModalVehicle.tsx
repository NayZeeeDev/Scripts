/**
 * Vehicle identity strip at the top of the garage modals: the vehicle on a small stage,
 * make + name (nickname in quotes) and its plate — the showroom look in miniature.
 */
import type { ReactNode } from 'react';
import { PlateTag, VehicleImage } from '@/components/ui';
import type { GarageVehicle } from '@/lib/types';
import { modelName } from '../model';

export function ModalVehicle({ v, aside }: { v: GarageVehicle; aside?: ReactNode }) {
  const nick = (v.nickname ?? '').trim();
  const name = modelName(v);
  return (
    <div className="nz-garage__mv">
      <div className="nz-garage__mv-img">
        <VehicleImage image={v.image} vehicleType={v.vehicleType} alt={v.label} className="nz-garage__img" />
      </div>
      <div className="nz-garage__mv-text">
        {v.make && <small>{v.make}</small>}
        <b title={nick ? `${name} “${nick}”` : name}>
          {name}
          {nick && <em> “{nick}”</em>}
        </b>
        <span>
          <PlateTag plate={v.plate} size="sm" />
          {v.classLabel && <i>{v.classLabel}</i>}
        </span>
      </div>
      {aside && <div className="nz-garage__mv-aside">{aside}</div>}
    </div>
  );
}
