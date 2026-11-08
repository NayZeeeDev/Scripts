/**
 * Interior vehicle HUD (no focus, never interactive), driven by the `hud` NUI message
 * (HudVehicle | null):
 *  - seated in a display vehicle (no `anchor`): stats panel docked top-right (picture, name,
 *    plate, mileage, owner, fuel / engine / body). The prompt bar tells how to drive out.
 *  - on foot next to a display vehicle (`anchor` set): a compact vehicle card floating above
 *    the car, following it on screen; Lua hides it when the car is far or out of sight.
 */
import { memo, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { useUi } from '@/lib/store';
import { t } from '@/lib/i18n';
import { distance, percent } from '@/lib/format';
import type { HudAnchor, HudVehicle } from '@/lib/types';
import { Bar, BrandMark, Icon, PlateTag, VehicleImage, autoTone, cx } from '@/components/ui';
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

/* ───────────────────────── seated: docked stats panel ───────────────────────── */

function SeatedPanel({ v, leaving }: { v: HudVehicle; leaving: boolean }) {
  const { make, name } = splitLabel(v.label, v.make);
  return (
    <div className="nz-ihud" aria-hidden="true">
      <div key={`${v.plate}|${v.model}`} className={cx('nz-ihud__panel', leaving && 'is-leaving')}>
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

        {/* Drivable: the prompt bar shows "Accelerate to leave the garage". */}
        {!v.canDrive && (
          <div className="nz-ihud__hint nz-ihud__hint--locked">
            <Icon name="lock" size={13} strokeWidth={1.8} />
            <span>{t('Display only, you cannot drive this vehicle')}</span>
          </div>
        )}
      </div>
    </div>
  );
}

/* ───────────────────────── on foot: floating vehicle card ───────────────────────── */

function TagRow({ label, icon, value }: { label: string; icon: IconName; value: number }) {
  const v = percent(value);
  const tone = autoTone(v);
  return (
    <div className={cx('nz-itag__row', `nz-itag__row--${tone}`)}>
      <Icon name={icon} size={11} strokeWidth={1.9} />
      <span className="nz-itag__row-label">{label}</span>
      <Bar value={v} tone={tone} height={3} className="nz-itag__row-bar" />
      <b className="nz-itag__row-value">{v}%</b>
    </div>
  );
}

const sameVehicle = (a: HudVehicle, b: HudVehicle) =>
  a.plate === b.plate &&
  a.model === b.model &&
  a.label === b.label &&
  a.make === b.make &&
  a.fuel === b.fuel &&
  a.engine === b.engine &&
  a.body === b.body &&
  a.mileage === b.mileage &&
  a.ownerName === b.ownerName &&
  a.canDrive === b.canDrive;

/** Card body: re-renders only when the vehicle data changes, not on every position update. */
const TagCard = memo(
  function TagCard({ v }: { v: HudVehicle }) {
    const { make, name } = splitLabel(v.label, v.make);
    return (
      <div className="nz-itag__card">
        <div className="nz-itag__head">
          <BrandMark size="sm" className="nz-itag__mark" />
          <div className="nz-itag__id">
            {make && <span className="nz-itag__make">{make}</span>}
            <b className="nz-itag__name" title={v.label}>
              {name}
            </b>
          </div>
          <PlateTag plate={v.plate} size="sm" className="nz-itag__plate" />
        </div>
        <div className="nz-itag__rows">
          <TagRow label={t('Fuel')} icon="fuel" value={v.fuel} />
          <TagRow label={t('Engine')} icon="engine" value={v.engine} />
          <TagRow label={t('Body')} icon="shield" value={v.body} />
        </div>
        <div className="nz-itag__foot">
          {v.canDrive ? (
            <span className="nz-itag__chip nz-itag__chip--go">
              <Icon name="key" size={11} strokeWidth={1.9} />
              {t('Get in to drive')}
            </span>
          ) : (
            <span className="nz-itag__chip">
              <Icon name="lock" size={11} strokeWidth={1.9} />
              {t('Display only')}
            </span>
          )}
          <span className="nz-itag__miles">
            <Icon name="gauge" size={11} strokeWidth={1.9} />
            {distance(v.mileage)}
          </span>
        </div>
        {v.ownerName && (
          <div className="nz-itag__owner">
            <span>{t('Owner')}</span>
            <b>{v.ownerName}</b>
          </div>
        )}
      </div>
    );
  },
  (a, b) => sameVehicle(a.v, b.v),
);

const EDGE = 12;
const STEM = 30;

function FloatingTag({ v, at, leaving }: { v: HudVehicle; at: HudAnchor; leaving: boolean }) {
  const cardRef = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ w: 280, h: 176 });

  useLayoutEffect(() => {
    const el = cardRef.current;
    if (!el) return;
    const w = el.offsetWidth;
    const h = el.offsetHeight;
    if (w && h && (w !== size.w || h !== size.h)) setSize({ w, h });
  });

  const vw = window.innerWidth;
  const vh = window.innerHeight;
  const scale = Math.min(1, Math.max(0.8, at.scale || 1));
  const x = at.x * vw;
  const y = at.y * vh;
  // The stem always points at the car; the card slides to stay on screen.
  const half = (size.w * scale) / 2;
  const shift = Math.min(Math.max(x, half + EDGE), vw - half - EDGE) - x;
  const lift = Math.max(0, EDGE - (y - (size.h + STEM) * scale));

  return (
    <div className="nz-itag" aria-hidden="true" style={{ transform: `translate3d(${x}px, ${y + lift}px, 0)` }}>
      <div className={cx('nz-itag__inner', leaving && 'is-leaving')} style={{ transform: `scale(${scale})` }}>
        <div key={v.plate} ref={cardRef} className="nz-itag__float" style={{ transform: `translateX(calc(-50% + ${shift / scale}px))` }}>
          <TagCard v={v} />
        </div>
        <div className="nz-itag__stem">
          <i />
        </div>
      </div>
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
  if (shown.anchor) return <FloatingTag v={shown} at={shown.anchor} leaving={leaving} />;
  return <SeatedPanel v={shown} leaving={leaving} />;
}
