/**
 * Showroom stage: the selected vehicle large on a "turntable" — perspective floor grid, thin
 * teal horizon, elliptical floor shadow (all CSS gradients) — with overlay slots in the four
 * corners. Plus the registration plate and the title block.
 * While the 3D preview runs (PreviewContext, see ./preview.tsx) the stage is transparent: the
 * game renders the real car behind it, slowly turning; the image is the fallback.
 */
import type { ReactNode } from 'react';
import { Spinner, VehicleImage, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { VehicleType } from '@/lib/types';
import { usePreviewStage } from './preview';

export interface StageProps {
  image: string | null;
  vehicleType: VehicleType;
  alt: string;
  /** Re-keys the vehicle so it glides in when the selection changes. */
  id: string;
  /** The vehicle is not physically here (out, elsewhere, impounded): drawn as a ghost. */
  ghost?: boolean;
  /** Small label on the floor under a ghost ("Out in the city"). */
  note?: ReactNode;
  topLeft?: ReactNode;
  topRight?: ReactNode;
  title?: ReactNode;
  plate?: ReactNode;
  /** Empty turntable (no vehicle). */
  empty?: boolean;
  className?: string;
  children?: ReactNode;
}

export function Stage({
  image,
  vehicleType,
  alt,
  id,
  ghost = false,
  note,
  topLeft,
  topRight,
  title,
  plate,
  empty = false,
  className,
  children,
}: StageProps) {
  const preview = usePreviewStage();
  // ghosts and the empty turntable never preview (the hook gets no target for them)
  const live = preview.live && !empty && !ghost;
  return (
    <div
      ref={empty ? undefined : preview.stageRef}
      className={cx('nz-garage__stage', ghost && 'is-ghost', empty && 'is-empty', live && 'is-live', className)}
    >
      {live && preview.loading && (
        <span className="nz-garage__stage-busy" aria-label={t('Loading vehicle...')}>
          <Spinner size={14} />
        </span>
      )}
      <span className="nz-garage__stage-floor" aria-hidden="true" />
      <span className="nz-garage__stage-horizon" aria-hidden="true" />
      <span className="nz-garage__stage-ring" aria-hidden="true" />
      {!empty && (
        <div key={id} className="nz-garage__stage-car">
          <span className="nz-garage__stage-shadow" aria-hidden="true" />
          <VehicleImage image={image} vehicleType={vehicleType} alt={alt} className="nz-garage__stage-img" />
        </div>
      )}
      {note && <div className="nz-garage__stage-note">{note}</div>}
      {children}
      {(topLeft || topRight) && (
        <div className="nz-garage__stage-top">
          <div className="nz-garage__stage-tl">{topLeft}</div>
          <div className="nz-garage__stage-tr">{topRight}</div>
        </div>
      )}
      {(title || plate) && (
        <div key={`t-${id}`} className="nz-garage__stage-foot">
          <div className="nz-garage__stage-title">{title}</div>
          {plate}
        </div>
      )}
    </div>
  );
}

/** Make (small caps) over the big name, nickname in quotes. */
export function StageTitle({ make, name, nickname }: { make?: string | null; name: string; nickname?: string | null }) {
  const nick = (nickname ?? '').trim();
  return (
    <>
      {make && <span className="nz-garage__st-make">{make}</span>}
      <span className="nz-garage__st-line">
        <b className="nz-garage__st-name" title={name}>
          {name}
        </b>
        {nick && (
          <span className="nz-garage__st-nick" title={nick}>
            “{nick}”
          </span>
        )}
      </span>
    </>
  );
}

/** Registration plate: dark inset plate, mono white text, tiny state caption. */
export function Plate({ plate, caption, muted = false, title }: { plate: string; caption?: string; muted?: boolean; title?: string }) {
  const text = (plate ?? '').trim().toUpperCase() || '—';
  return (
    <span className={cx('nz-garage__plate', muted && 'is-muted')} title={title ?? text}>
      <small>{caption ?? t('San Andreas')}</small>
      <b>{text}</b>
    </span>
  );
}

/** Class tag for the stage's top-left corner: vehicle-type icon + class label. */
export function ClassTag({ icon, label }: { icon: ReactNode; label: string }) {
  return (
    <span className="nz-garage__classtag">
      {icon}
      <span>{label}</span>
    </span>
  );
}
