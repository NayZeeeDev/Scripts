/**
 * Spawner entries (job / public spawner garages): card and row contents with a direct
 * Drive button, plate preview ("Random plate" when the template is empty) and price.
 */
import { Badge, Button, Icon, PlateTag, Tooltip, VehicleImage } from '@/components/ui';
import { t } from '@/lib/i18n';
import { money } from '@/lib/format';
import type { SpawnerVehicleView } from '@/lib/types';
import { platePreview } from './model';

export interface SpawnerTileProps {
  s: SpawnerVehicleView;
  /** Index currently spawning (any entry). */
  spawning: number | null;
  onDrive: () => void;
}

function PlateInfo({ plate }: { plate: string }) {
  const p = platePreview(plate);
  if (!p) {
    return (
      <span className="nz-garage__mileage">
        <Icon name="hash" size={12} strokeWidth={1.8} />
        {t('Random plate')}
      </span>
    );
  }
  if (!p.random) return <PlateTag plate={p.text} size="sm" />;
  return (
    <Tooltip content={t('Plate format — the • characters are filled in randomly')}>
      <span className="nz-garage__plate-tpl">
        <PlateTag plate={p.text} size="sm" />
      </span>
    </Tooltip>
  );
}

function PriceBadge({ price }: { price: number }) {
  if (price <= 0) return null;
  return (
    <Badge tone="white" icon="money" size="sm">
      {money(price)}
    </Badge>
  );
}

function DriveButton({ s, spawning, onDrive, full, showPrice }: SpawnerTileProps & { full?: boolean; showPrice?: boolean }) {
  const loading = spawning === s.index;
  return (
    <Button
      variant="teal"
      size="sm"
      icon="arrowRight"
      full={full}
      loading={loading}
      disabled={spawning !== null && !loading}
      badge={showPrice && s.price > 0 && !loading ? money(s.price) : undefined}
      onClick={onDrive}
    >
      {loading ? t('Loading vehicle...') : t('Drive')}
    </Button>
  );
}

export function SpawnerCard(props: SpawnerTileProps) {
  const { s } = props;
  return (
    <>
      <div className="nz-garage__media">
        <VehicleImage image={s.image} vehicleType={s.vehicleType} alt={s.label} className="nz-garage__img" />
        <div className="nz-garage__overlay">
          <span className="nz-garage__backing">
            <PriceBadge price={s.price} />
          </span>
        </div>
      </div>
      <div className="nz-garage__cardbody">
        <b className="nz-garage__name" title={s.label}>
          {s.label || s.model.toUpperCase()}
        </b>
        <div className="nz-garage__meta">
          <PlateInfo plate={s.plate} />
        </div>
        <div className="nz-garage__cardaction">
          <DriveButton {...props} full />
        </div>
      </div>
    </>
  );
}

export function SpawnerRow(props: SpawnerTileProps) {
  const { s } = props;
  return (
    <>
      <div className="nz-garage__thumb">
        <VehicleImage image={s.image} vehicleType={s.vehicleType} alt={s.label} className="nz-garage__img" />
      </div>
      <div className="nz-garage__rowtext">
        <span className="nz-garage__rowtitle">
          <b className="nz-garage__name" title={s.label}>
            {s.label || s.model.toUpperCase()}
          </b>
        </span>
        <span className="nz-garage__meta">
          <PlateInfo plate={s.plate} />
        </span>
      </div>
      <div className="nz-garage__rowside">
        <DriveButton {...props} showPrice />
      </div>
    </>
  );
}
