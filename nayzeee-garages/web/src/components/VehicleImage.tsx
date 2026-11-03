/**
 * Vehicle picture with a fallback chain:
 *   settings.imageUrl template → ./vehicles/<model>.png → original SVG silhouette.
 * Fixed aspect box (no layout shift), object-fit: contain, fades in once loaded.
 */
import { useEffect, useMemo, useState } from 'react';
import clsx from 'clsx';
import { useSettings } from '@/lib/store';
import { localVehicleImage, vehicleImageUrl } from '@/lib/format';
import type { VehicleType } from '@/lib/types';
import { VehicleSilhouette, silhouetteFor } from './icons';

export interface VehicleImageProps {
  image: string | null;
  vehicleType: VehicleType;
  alt?: string;
  className?: string;
}

export function VehicleImage({ image, vehicleType, alt, className }: VehicleImageProps) {
  const settings = useSettings();
  const sources = useMemo(() => {
    const list = [vehicleImageUrl(image), localVehicleImage(image)].filter((s): s is string => !!s);
    return Array.from(new Set(list));
    // settings (template + showImages) are read inside vehicleImageUrl
  }, [image, settings.imageUrl, settings.showImages]);
  const [index, setIndex] = useState(0);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    setIndex(0);
    setLoaded(false);
  }, [sources]);

  const src = sources[index];
  const failed = !src;
  const kind = silhouetteFor(vehicleType, image);

  return (
    <div className={clsx('nz-vimg', loaded && 'is-loaded', failed && 'is-fallback', className)}>
      <VehicleSilhouette kind={kind} className="nz-vimg__sil" />
      {src && (
        <img
          key={src}
          src={src}
          alt={alt ?? ''}
          draggable={false}
          loading="lazy"
          decoding="async"
          className="nz-vimg__img"
          onLoad={() => setLoaded(true)}
          onError={() => {
            setLoaded(false);
            setIndex((i) => i + 1);
          }}
        />
      )}
    </div>
  );
}
