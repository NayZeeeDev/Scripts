/**
 * Damage glyph: a top-down vehicle outline (front at the top) whose parts light up from the
 * stored DamageSummary — damaged doors / bonnet / boot and smashed windows glow red, burst
 * tyres amber (tyres on the rim red). Original drawing, viewBox 120×200.
 *
 * Indexes (types.ts): doors 0 FL, 1 FR, 2 RL, 3 RR, 4 bonnet, 5 boot · windows 0 FL, 1 FR,
 * 2 RL, 3 RR, 4/5 middle, 6 windscreen, 7 rear · tyres 0 FL, 1 FR, 2|45 ML, 3|47 MR, 4 RL, 5 RR.
 */
import { cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { DamageSummary, VehicleType } from '@/lib/types';

interface Part {
  id: string;
  d: string;
  label: () => string;
}

const DOORS: Record<number, Part> = {
  0: { id: 'd0', d: 'M24 66h7v38h-7a2 2 0 0 1-2-2V68a2 2 0 0 1 2-2z', label: () => t('Front left door') },
  1: { id: 'd1', d: 'M96 66h-7v38h7a2 2 0 0 0 2-2V68a2 2 0 0 0-2-2z', label: () => t('Front right door') },
  2: { id: 'd2', d: 'M24 106h7v36h-7a2 2 0 0 1-2-2v-32a2 2 0 0 1 2-2z', label: () => t('Rear left door') },
  3: { id: 'd3', d: 'M96 106h-7v36h7a2 2 0 0 0 2-2v-32a2 2 0 0 0-2-2z', label: () => t('Rear right door') },
  4: { id: 'd4', d: 'M33 20Q60 13 87 20L88 56Q60 51 32 56Z', label: () => t('Bonnet') },
  5: { id: 'd5', d: 'M32 152Q60 157 88 152L87 178Q60 185 33 178Z', label: () => t('Boot') },
};

const WINDOWS: Record<number, Part> = {
  0: { id: 'w0', d: 'M32.5 84h4.5v20h-4.5z', label: () => t('Front left window') },
  1: { id: 'w1', d: 'M87.5 84h-4.5v20h4.5z', label: () => t('Front right window') },
  2: { id: 'w2', d: 'M32.5 106h4.5v22h-4.5z', label: () => t('Rear left window') },
  3: { id: 'w3', d: 'M87.5 106h-4.5v22h4.5z', label: () => t('Rear right window') },
  6: { id: 'w6', d: 'M34 61Q60 55 86 61L81 80Q60 76 39 80Z', label: () => t('Windscreen') },
  7: { id: 'w7', d: 'M39 131Q60 135 81 131L85 147Q60 152 35 147Z', label: () => t('Rear window') },
};
// Middle windows (vans, buses) share the rear side slots.
const WINDOW_ALIAS: Record<number, number> = { 4: 2, 5: 3 };

const TYRES: Record<string, { x: number; y: number; label: () => string }> = {
  fl: { x: 13, y: 34, label: () => t('Front left tyre') },
  fr: { x: 99, y: 34, label: () => t('Front right tyre') },
  ml: { x: 13, y: 112, label: () => t('Middle left tyre') },
  mr: { x: 99, y: 112, label: () => t('Middle right tyre') },
  rl: { x: 13, y: 148, label: () => t('Rear left tyre') },
  rr: { x: 99, y: 148, label: () => t('Rear right tyre') },
};
const TYRE_SLOT: Record<number, keyof typeof TYRES> = { 0: 'fl', 1: 'fr', 2: 'ml', 45: 'ml', 3: 'mr', 47: 'mr', 4: 'rl', 5: 'rr' };

const BODY =
  'M40 10Q60 5 80 10Q95 14 97 32L98 168Q97 186 80 190Q60 195 40 190Q23 186 22 168L23 32Q25 14 40 10Z';

export interface DamageGlyphProps {
  damage: DamageSummary | null;
  vehicleType?: VehicleType;
  /** Body health 0–100: tints the outline when low. */
  body?: number;
  className?: string;
}

export function DamageGlyph({ damage, vehicleType = 'car', body = 100, className }: DamageGlyphProps) {
  const doors = new Set(damage?.doors ?? []);
  const windows = new Set((damage?.windows ?? []).map((w) => WINDOW_ALIAS[w] ?? w));
  const tyres = new Map<string, 1 | 2>();
  for (const ty of damage?.tyres ?? []) {
    const slot = TYRE_SLOT[ty.index];
    if (slot) tyres.set(slot, Math.max(tyres.get(slot) ?? 0, ty.state) as 1 | 2);
  }
  const sixWheels = tyres.has('ml') || tyres.has('mr');
  const tyreSlots = (sixWheels ? ['fl', 'fr', 'ml', 'mr', 'rl', 'rr'] : ['fl', 'fr', 'rl', 'rr']) as (keyof typeof TYRES)[];
  const bodyTone = !damage ? 'none' : damage.deformed || body < 35 ? 'red' : body < 65 ? 'amber' : 'ok';
  const isCar = vehicleType === 'car';

  return (
    <svg
      viewBox="0 0 120 200"
      className={cx('nz-garage__glyph', !damage && 'is-nodata', className)}
      role="img"
      aria-label={t('Damage overview')}
    >
      {isCar &&
        tyreSlots.map((slot) => {
          const st = tyres.get(slot);
          const tt = TYRES[slot];
          return (
            <rect
              key={slot}
              x={tt.x}
              y={tt.y}
              width={8}
              height={22}
              rx={2.5}
              className={cx('nz-garage__glyph-tyre', st === 1 && 'is-burst', st === 2 && 'is-rim')}
            >
              <title>{st ? `${tt.label()} · ${st === 2 ? t('On the rim') : t('Burst')}` : tt.label()}</title>
            </rect>
          );
        })}
      <path d={BODY} className={cx('nz-garage__glyph-body', `is-${bodyTone}`)} />
      {/* mirrors */}
      <path d="M22 66l-5 3v4l5-1M98 66l5 3v4l-5-1" className="nz-garage__glyph-line" />
      {/* roof */}
      <rect x={39} y={82} width={42} height={47} rx={4} className="nz-garage__glyph-roof" />
      {Object.entries(DOORS).map(([i, p]) => (
        <path key={p.id} d={p.d} className={cx('nz-garage__glyph-part', doors.has(Number(i)) && 'is-hit')}>
          <title>{doors.has(Number(i)) ? `${p.label()} · ${t('Damaged')}` : p.label()}</title>
        </path>
      ))}
      {Object.entries(WINDOWS).map(([i, p]) => (
        <path key={p.id} d={p.d} className={cx('nz-garage__glyph-glass', windows.has(Number(i)) && 'is-hit')}>
          <title>{windows.has(Number(i)) ? `${p.label()} · ${t('Smashed')}` : p.label()}</title>
        </path>
      ))}
      {/* head / tail lights */}
      <path d="M36 13.5l8-1.6M84 13.5l-8-1.6" className="nz-garage__glyph-lamp" />
      <path d="M37 186.5l8 1.4M83 186.5l-8 1.4" className="nz-garage__glyph-tail" />
    </svg>
  );
}
