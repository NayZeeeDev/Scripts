/**
 * Interior stats HUD (no focus, never interactive): top-right HUD panel shown while the
 * player sits in a display vehicle inside a garage interior. Driven by the `hud` NUI
 * message (HudVehicle | null). Shows the vehicle picture, name, plate, mileage, owner,
 * fuel / engine / body tiles and whether accelerating drives the vehicle out.
 */
import { useEffect, useState } from 'react';
import { useUi } from '@/lib/store';
import { t } from '@/lib/i18n';
import { distance, percent } from '@/lib/format';
import type { HudVehicle } from '@/lib/types';
import { Bar, Icon, Kbd, PlateTag, VehicleImage, autoTone, cx } from '@/components/ui';
import type { IconName } from '@/components/ui';
import './interior.css';

/** Keeps the HUD mounted for `ms` after it is hidden so it can slide out. */
function useLeaving(visible: boolean, ms: number) {
  const [mounted, setMounted] = useState(visible);
  useEffect(() => {
    if (visible) {
      setMounted(true);
      return;
    }
    const id = window.setTimeout(() => setMounted(false), ms);
    return () => window.clearTimeout(id);
  }, [visible, ms]);
  return { mounted: visible || mounted, leaving: !visible && mounted };
}

/** "Pfister Neon" + make "Pfister" -> { make: 'Pfister', name: 'Neon' }. */
function splitLabel(label: string, make: string) {
  const l = (label ?? '').trim();
  const m = (make ?? '').trim();
  if (m && l.toLowerCase().startsWith(`${m.toLowerCase()} `)) return { make: m, name: l.slice(m.length + 1) };
  return { make: m, name: l || t('Vehicle') };
}

function MiniStat({ label, icon, value }: { label: string; icon: IconName; value: number }) {
  const v = percent(value);
  const tone = autoTone(v);
  return (
    <div className={cx('nz-ihud__stat', `nz-ihud__stat--${tone}`)}>
      <div className="nz-ihud__stat-head">
        <Icon name={icon} size={12} strokeWidth={1.8} />
        <span>{label}</span>
      </div>
      <div className="nz-ihud__stat-value">
        <b>{v}</b>
        <span>%</span>
      </div>
      <Bar value={v} tone={tone} height={3} />
    </div>
  );
}

export function InteriorHud() {
  const hud = useUi((s) => s.hud);
  const [shown, setShown] = useState<HudVehicle | null>(hud);
  const { mounted, leaving } = useLeaving(!!hud, 200);

  useEffect(() => {
    if (hud) setShown(hud);
  }, [hud]);

  if (!mounted || !shown) return null;
  const v = shown;
  const { make, name } = splitLabel(v.label, v.make);
  const key = `${v.plate}|${v.model}`;

  return (
    <div className="nz-ihud" aria-hidden="true">
      <div key={key} className={cx('nz-ihud__panel', leaving && 'is-leaving')}>
        <div className="nz-ihud__top">
          <div className="nz-ihud__thumb">
            <VehicleImage image={v.image ?? v.model} vehicleType={v.vehicleType} alt={v.label} className="nz-ihud__img" />
          </div>
          <div className="nz-ihud__id">
            {make && <span className="nz-ihud__make">{make}</span>}
            <b className="nz-ihud__name" title={v.label}>
              {name}
            </b>
            <div className="nz-ihud__meta">
              <PlateTag plate={v.plate} size="sm" />
              <span className="nz-ihud__miles">
                <Icon name="gauge" size={12} strokeWidth={1.8} />
                {distance(v.mileage)}
              </span>
            </div>
          </div>
        </div>

        {v.ownerName && (
          <div className="nz-ihud__owner">
            <Icon name="user" size={12} strokeWidth={1.8} />
            <span className="nz-ihud__owner-label">{t('Owner')}</span>
            <b>{v.ownerName}</b>
          </div>
        )}

        <div className="nz-ihud__stats">
          <MiniStat label={t('Fuel')} icon="fuel" value={v.fuel} />
          <MiniStat label={t('Engine')} icon="engine" value={v.engine} />
          <MiniStat label={t('Body')} icon="shield" value={v.body} />
        </div>

        {v.canDrive ? (
          <div className="nz-ihud__hint">
            <Kbd className="nz-ihud__key">W</Kbd>
            <span>{t('Accelerate to drive out')}</span>
            <Icon name="arrowRight" size={14} strokeWidth={1.9} className="nz-ihud__hint-arrow" />
          </div>
        ) : (
          <div className="nz-ihud__hint nz-ihud__hint--locked">
            <Icon name="lock" size={13} strokeWidth={1.8} />
            <span>{t('Display only, you cannot drive this vehicle')}</span>
          </div>
        )}
      </div>
    </div>
  );
}
