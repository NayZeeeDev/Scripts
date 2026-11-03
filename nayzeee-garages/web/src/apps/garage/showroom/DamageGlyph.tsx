/**
 * Damage glyph: a top-down outline of the vehicle (front at the top) whose parts light up
 * from the stored DamageSummary — damaged doors / bonnet / boot and smashed windows glow
 * red, burst tyres amber (on the rim: red). One family of original drawings (viewBox
 * 120×200): car (4 or 6 wheels), bike, boat, plane and helicopter. Boats and aircraft
 * have no doors / tyres to show: their outline takes the body tone and the cockpit glass
 * lights up when the windscreen is smashed.
 *
 * Indexes (types.ts): doors 0 FL, 1 FR, 2 RL, 3 RR, 4 bonnet, 5 boot · windows 0 FL, 1 FR,
 * 2 RL, 3 RR, 4/5 middle, 6 windscreen, 7 rear · tyres 0 FL, 1 FR, 2|45 ML, 3|47 MR, 4 RL, 5 RR
 * (bikes: 0 front, 4 rear).
 */
import { cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { DamageSummary, VehicleType } from '@/lib/types';

export type GlyphShape = 'car' | 'bike' | 'boat' | 'plane' | 'heli';

const HELI_HINT = /heli|buzzard|maverick|frogger|swift|supervolito|valkyrie|savage|annihilator|cargobob|polmav|havok|sparrow|akula|hunter|skylift|volatus|conada/;

/** Which outline fits a vehicle: class first (bikes, boats, helicopters, planes), then its type. */
export function glyphShape(vehicleType: VehicleType, classId?: number, model?: string | null): GlyphShape {
  if (classId === 8 || classId === 13) return 'bike';
  if (classId === 14) return 'boat';
  if (classId === 15) return 'heli';
  if (classId === 16) return 'plane';
  if (vehicleType === 'sea') return 'boat';
  if (vehicleType === 'air') return HELI_HINT.test((model ?? '').toLowerCase()) ? 'heli' : 'plane';
  return 'car';
}

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

const CAR_BODY =
  'M40 10Q60 5 80 10Q95 14 97 32L98 168Q97 186 80 190Q60 195 40 190Q23 186 22 168L23 32Q25 14 40 10Z';

export interface DamageGlyphProps {
  damage: DamageSummary | null;
  shape?: GlyphShape;
  /** Body health 0–100: tints the outline when low. */
  body?: number;
  className?: string;
}

function tyreTitle(label: string, state?: 1 | 2) {
  return state ? `${label} · ${state === 2 ? t('On the rim') : t('Burst')}` : label;
}

export function DamageGlyph({ damage, shape = 'car', body = 100, className }: DamageGlyphProps) {
  const doors = new Set(damage?.doors ?? []);
  const windows = new Set((damage?.windows ?? []).map((w) => WINDOW_ALIAS[w] ?? w));
  const tyreState = new Map<number, 1 | 2>();
  for (const ty of damage?.tyres ?? []) tyreState.set(ty.index, Math.max(tyreState.get(ty.index) ?? 0, ty.state) as 1 | 2);
  const bodyTone = !damage ? 'none' : damage.deformed || body < 35 ? 'red' : body < 65 ? 'amber' : 'ok';
  const bodyCls = cx('nz-garage__glyph-body', `is-${bodyTone}`);
  const glass = (hit: boolean) => cx('nz-garage__glyph-glass', hit && 'is-hit');
  const tyreCls = (st?: 1 | 2) => cx('nz-garage__glyph-tyre', st === 1 && 'is-burst', st === 2 && 'is-rim');

  let art: JSX.Element;
  if (shape === 'bike') {
    const front = Math.max(tyreState.get(0) ?? 0, tyreState.get(1) ?? 0) as 0 | 1 | 2;
    const rear = Math.max(tyreState.get(4) ?? 0, tyreState.get(5) ?? 0) as 0 | 1 | 2;
    art = (
      <>
        <rect x={53} y={12} width={14} height={44} rx={6} className={tyreCls(front || undefined)}>
          <title>{tyreTitle(t('Front tyre'), front || undefined)}</title>
        </rect>
        <rect x={53} y={146} width={14} height={44} rx={6} className={tyreCls(rear || undefined)}>
          <title>{tyreTitle(t('Rear tyre'), rear || undefined)}</title>
        </rect>
        <path d="M60 46Q76 52 74 78L72 150Q60 160 48 150L46 78Q44 52 60 46Z" className={bodyCls} />
        <path d="M30 62Q60 52 90 62" className="nz-garage__glyph-bar" />
        <rect x={52} y={92} width={16} height={44} rx={7} className="nz-garage__glyph-roof" />
        <path d="M54 56Q60 52 66 56" className="nz-garage__glyph-lamp" />
      </>
    );
  } else if (shape === 'boat') {
    art = (
      <>
        <path d="M60 6Q90 44 92 96L92 178Q60 194 28 178L28 96Q30 44 60 6Z" className={bodyCls} />
        <path d="M60 22L60 70" className="nz-garage__glyph-line" />
        <path d="M38 84Q60 74 82 84L80 98Q60 91 40 98Z" className={glass(windows.has(6))}>
          <title>{windows.has(6) ? `${t('Windscreen')} · ${t('Smashed')}` : t('Windscreen')}</title>
        </path>
        <rect x={40} y={102} width={40} height={40} rx={5} className="nz-garage__glyph-roof" />
        <path d="M34 160H86M34 170H86" className="nz-garage__glyph-line" />
      </>
    );
  } else if (shape === 'plane') {
    art = (
      <>
        <path d="M60 6Q68 8 68 30L69 84L114 112V122L69 114L67 166L86 180V188L60 184L34 188V180L53 166L51 114L6 122V112L51 84L52 30Q52 8 60 6Z" className={bodyCls} />
        <path d="M54 22Q60 14 66 22L66 32Q60 29 54 32Z" className={glass(windows.has(6))}>
          <title>{windows.has(6) ? `${t('Cockpit glass')} · ${t('Smashed')}` : t('Cockpit glass')}</title>
        </path>
        <path d="M60 40V160" className="nz-garage__glyph-line" />
      </>
    );
  } else if (shape === 'heli') {
    art = (
      <>
        <circle cx={60} cy={72} r={50} className="nz-garage__glyph-rotor" />
        <path d="M60 22L60 122M14 72L106 72" className="nz-garage__glyph-line" />
        <path d="M34 48V102M86 48V102" className="nz-garage__glyph-bar" />
        <path d="M60 36Q82 38 82 72Q82 104 64 110L63 176L72 182V188H48V182L57 176L56 110Q38 104 38 72Q38 38 60 36Z" className={bodyCls} />
        <path d="M46 52Q60 40 74 52L72 64Q60 58 48 64Z" className={glass(windows.has(6))}>
          <title>{windows.has(6) ? `${t('Cockpit glass')} · ${t('Smashed')}` : t('Cockpit glass')}</title>
        </path>
      </>
    );
  } else {
    const slots = new Map<string, 1 | 2>();
    tyreState.forEach((st, index) => {
      const slot = TYRE_SLOT[index];
      if (slot) slots.set(slot, Math.max(slots.get(slot) ?? 0, st) as 1 | 2);
    });
    const sixWheels = slots.has('ml') || slots.has('mr');
    const tyreSlots = (sixWheels ? ['fl', 'fr', 'ml', 'mr', 'rl', 'rr'] : ['fl', 'fr', 'rl', 'rr']) as (keyof typeof TYRES)[];
    art = (
      <>
        {tyreSlots.map((slot) => {
          const st = slots.get(slot);
          const tt = TYRES[slot];
          return (
            <rect key={slot} x={tt.x} y={tt.y} width={8} height={22} rx={2.5} className={tyreCls(st)}>
              <title>{tyreTitle(tt.label(), st)}</title>
            </rect>
          );
        })}
        <path d={CAR_BODY} className={bodyCls} />
        <path d="M22 66l-5 3v4l5-1M98 66l5 3v4l-5-1" className="nz-garage__glyph-line" />
        <rect x={39} y={82} width={42} height={47} rx={4} className="nz-garage__glyph-roof" />
        {Object.entries(DOORS).map(([i, p]) => (
          <path key={p.id} d={p.d} className={cx('nz-garage__glyph-part', doors.has(Number(i)) && 'is-hit')}>
            <title>{doors.has(Number(i)) ? `${p.label()} · ${t('Damaged')}` : p.label()}</title>
          </path>
        ))}
        {Object.entries(WINDOWS).map(([i, p]) => (
          <path key={p.id} d={p.d} className={glass(windows.has(Number(i)))}>
            <title>{windows.has(Number(i)) ? `${p.label()} · ${t('Smashed')}` : p.label()}</title>
          </path>
        ))}
        <path d="M36 13.5l8-1.6M84 13.5l-8-1.6" className="nz-garage__glyph-lamp" />
        <path d="M37 186.5l8 1.4M83 186.5l-8 1.4" className="nz-garage__glyph-tail" />
      </>
    );
  }

  return (
    <svg
      viewBox="0 0 120 200"
      className={cx('nz-garage__glyph', `is-${shape}`, !damage && 'is-nodata', className)}
      role="img"
      aria-label={t('Damage overview')}
    >
      {art}
    </svg>
  );
}
