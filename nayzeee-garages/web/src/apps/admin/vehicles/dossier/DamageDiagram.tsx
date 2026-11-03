/**
 * Top-down damage diagram (nose to the right), the same outline family as the showroom
 * glyph: car (4 or 6 wheels), bike, boat, plane and helicopter. Damaged doors / panels and
 * smashed glass glow red, burst tyres amber, tyres on the rim red; a deformed body gets a
 * dashed red outline and the engine bay is tinted by engine health. `labels` adds the side
 * captions (large Condition view); without them it is the small glyph of the Overview.
 */
import { useId } from 'react';
import type { ReactNode } from 'react';
import { cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { DamageSummary } from '@/lib/types';
import { partStates } from './data';
import type { DmgShape, PartState } from './data';

interface Props {
  damage: DamageSummary | null;
  shape?: DmgShape;
  /** Engine health 0-100 (the vehicle row, which wins on spawn): tints the engine bay. */
  engine?: number;
  labels?: boolean;
  /** Highlighted part id (hover from the parts list). */
  hot?: string | null;
  onHot?: (id: string | null) => void;
  className?: string;
}

/* Shapes in a 440 × 230 box, centre line y 115, nose at the right. */

/* ── car ── */
const CAR_BODY = 'M90 53 L320 51 C366 53 388 80 390 115 C388 150 366 177 320 179 L90 177 C64 175 50 152 50 115 C50 78 64 55 90 53 Z';

const CAR_PANELS: { id: string; d: string }[] = [
  { id: 'door4', d: 'M304 60 L320 59 C360 61 380 86 382 115 C380 144 360 169 320 171 L304 170 C299 142 299 88 304 60 Z' },
  { id: 'door5', d: 'M140 62 L94 61 C72 63 61 86 59 115 C61 144 72 167 94 169 L140 168 C136 142 136 88 140 62 Z' },
  { id: 'door0', d: 'M224 57 H292 Q296 57 296 61 V70 Q296 74 292 74 H224 Q220 74 220 70 V61 Q220 57 224 57 Z' },
  { id: 'door2', d: 'M150 58 H212 Q216 58 216 62 V70 Q216 74 212 74 H150 Q146 74 146 70 V62 Q146 58 150 58 Z' },
  { id: 'door1', d: 'M224 156 H292 Q296 156 296 160 V169 Q296 173 292 173 H224 Q220 173 220 169 V160 Q220 156 224 156 Z' },
  { id: 'door3', d: 'M150 156 H212 Q216 156 216 160 V168 Q216 172 212 172 H150 Q146 172 146 168 V160 Q146 156 150 156 Z' },
];

const CAR_GLASS: { id: string; d: string }[] = [
  { id: 'win6', d: 'M268 84 L298 74 C293 100 293 130 298 156 L268 146 C265 128 265 102 268 84 Z' },
  { id: 'win7', d: 'M146 76 L172 86 C170 104 170 126 172 144 L146 154 C143 130 143 100 146 76 Z' },
  { id: 'win0', d: 'M226 77 H262 Q265 77 265 80 V80.5 Q265 83 262 83 H226 Q223 83 223 80.5 V80 Q223 77 226 77 Z' },
  { id: 'win2', d: 'M180 77 H213 Q216 77 216 80 V80.5 Q216 83 213 83 H180 Q177 83 177 80.5 V80 Q177 77 180 77 Z' },
  { id: 'win1', d: 'M226 147 H262 Q265 147 265 150 V150.5 Q265 153 262 153 H226 Q223 153 223 150.5 V150 Q223 147 226 147 Z' },
  { id: 'win3', d: 'M180 147 H213 Q216 147 216 150 V150.5 Q216 153 213 153 H180 Q177 153 177 150.5 V150 Q177 147 180 147 Z' },
];

/** Middle windows (vans, buses) light the rear side-window shapes; they keep their own list chips. */
const GLASS_ALIAS: Record<string, string> = { win4: 'win2', win5: 'win3' };

const CAR_TYRES: { id: string; x: number; y: number; optional?: boolean }[] = [
  { id: 'tyre0', x: 304, y: 37 },
  { id: 'tyre1', x: 304, y: 179 },
  { id: 'tyre4', x: 84, y: 37 },
  { id: 'tyre5', x: 84, y: 179 },
  { id: 'tyre2', x: 192, y: 37, optional: true },
  { id: 'tyre3', x: 192, y: 179, optional: true },
  { id: 'tyre45', x: 140, y: 37, optional: true },
  { id: 'tyre47', x: 140, y: 179, optional: true },
];

/* ── bike ── */
const BIKE_BODY = 'M318 115 C318 101 300 93 270 93 L172 95 C142 96 124 104 120 115 C124 126 142 134 172 135 L270 137 C300 137 318 129 318 115 Z';

/* ── boat ── */
const BOAT_HULL = 'M52 64 L250 61 C330 63 384 92 406 115 C384 138 330 167 250 169 L52 166 C46 166 42 160 42 154 L42 76 C42 70 46 64 52 64 Z';
const BOAT_GLASS = 'M262 80 C277 96 277 134 262 150 L247 146 C258 133 258 97 247 84 Z';

/* ── plane ── */
const PLANE_BODY =
  'M406 115 C406 108 396 103 380 103 L262 103 L214 20 L195 20 L211 103 L92 105 L60 71 L46 71 L55 108 L38 110 L38 120 L55 122 L46 159 L60 159 L92 125 L211 127 L195 210 L214 210 L262 127 L380 127 C396 127 406 122 406 115 Z';
const PLANE_GLASS = 'M390 109 C398 111 398 119 390 121 L374 120 C376 117 376 113 374 110 Z';

/* ── helicopter ── */
const HELI_BODY =
  'M332 115 C332 92 314 80 284 80 L232 82 C208 84 198 98 196 108 L82 111 L66 95 L57 95 L61 112 L50 112 L50 118 L61 118 L57 135 L66 135 L82 119 L196 122 C198 132 208 146 232 148 L284 150 C314 150 332 138 332 115 Z';
const HELI_GLASS = 'M320 99 C331 107 331 123 320 131 L302 128 C308 120 308 110 302 102 Z';

/** End captions per shape: [tail end, nose end]. */
const END_LABELS: Record<DmgShape, () => [string, string]> = {
  car: () => [t('BOOT'), t('BONNET')],
  bike: () => [t('REAR'), t('FRONT')],
  boat: () => [t('STERN'), t('BOW')],
  plane: () => [t('TAIL'), t('NOSE')],
  heli: () => [t('TAIL'), t('NOSE')],
};

/** Engine bay per shape (none for planes: their engines sit in the wings / nose). */
const BAY: Partial<Record<DmgShape, { cx: number; cy: number; rx: number; ry: number }>> = {
  car: { cx: 342, cy: 115, rx: 34, ry: 44 },
  bike: { cx: 238, cy: 115, rx: 34, ry: 22 },
  boat: { cx: 92, cy: 115, rx: 40, ry: 40 },
  heli: { cx: 246, cy: 115, rx: 36, ry: 28 },
};

export function DamageDiagram({ damage, shape = 'car', engine = 100, labels = false, hot = null, onHot, className }: Props) {
  const uid = useId().replace(/:/g, '');
  const states = partStates(damage, shape);
  const engineTone = engine < 25 ? 'red' : engine < 50 ? 'amber' : null;
  const none = !damage;
  const bay = BAY[shape];
  const deformed = cx(damage?.deformed && 'is-deformed');

  /** Hover / state props of a part; `alias` folds another part (win4 → win2) onto this shape. */
  const part = (id: string, base: string, alias?: string) => {
    const own: PartState = states[id] ?? 'ok';
    const s: PartState = own === 'ok' && alias && states[alias] && states[alias] !== 'ok' ? states[alias] : own;
    const isHot = hot === id || (!!alias && hot === alias);
    return {
      className: cx(base, `is-${s}`, isHot && 'is-hot'),
      onMouseEnter: onHot ? () => onHot(id) : undefined,
      onMouseLeave: onHot ? () => onHot(null) : undefined,
      'data-part': id,
      // An inline style beats the class rule, so the crack pattern shows on smashed glass.
      style: base === 'nz-dmg__glass' && s === 'bad' ? { fill: `url(#crack-${uid})` } : undefined,
    };
  };
  const aliasOf = (id: string) => Object.keys(GLASS_ALIAS).find((k) => GLASS_ALIAS[k] === id);

  let art: ReactNode;
  if (shape === 'bike') {
    art = (
      <>
        <rect x={322} y={108} width={74} height={14} rx={6} {...part('tyre0', 'nz-dmg__tyre')} />
        <rect x={44} y={108} width={74} height={14} rx={6} {...part('tyre4', 'nz-dmg__tyre')} />
        <path d={BIKE_BODY} className={cx('nz-dmg__body', deformed)} />
        <rect x={150} y={104} width={74} height={22} rx={10} className="nz-dmg__roof" />
        <ellipse cx={262} cy={115} rx={24} ry={15} className="nz-dmg__panel" />
        <path d="M300 115 H322" className="nz-dmg__bar" />
        <path d="M296 58 C306 80 306 150 296 172" className="nz-dmg__bar" />
        <ellipse cx={294} cy={56} rx={6} ry={3.4} className="nz-dmg__trim" />
        <ellipse cx={294} cy={174} rx={6} ry={3.4} className="nz-dmg__trim" />
        <ellipse cx={320} cy={115} rx={3.6} ry={9} className="nz-dmg__head" />
        <ellipse cx={121} cy={115} rx={2.6} ry={7} className="nz-dmg__tail" />
      </>
    );
  } else if (shape === 'boat') {
    art = (
      <>
        <path d={BOAT_HULL} className={cx('nz-dmg__body', deformed)} />
        <path d="M300 115 H384" className="nz-dmg__roofline" />
        <path d="M60 86 V144 M72 86 V144" className="nz-dmg__roofline" />
        <rect x={146} y={86} width={98} height={58} rx={8} className="nz-dmg__roof" />
        <path d={BOAT_GLASS} {...part('win6', 'nz-dmg__glass')} />
      </>
    );
  } else if (shape === 'plane') {
    art = (
      <>
        <path d={PLANE_BODY} className={cx('nz-dmg__body', deformed)} />
        <path d="M110 115 H360" className="nz-dmg__roofline" />
        <path d={PLANE_GLASS} {...part('win6', 'nz-dmg__glass')} />
      </>
    );
  } else if (shape === 'heli') {
    art = (
      <>
        <circle cx={250} cy={115} r={104} className="nz-dmg__rotor" />
        <path d="M206 72 H316 M206 158 H316" className="nz-dmg__bar" />
        <path d={HELI_BODY} className={cx('nz-dmg__body', deformed)} />
        <circle cx={58} cy={115} r={15} className="nz-dmg__rotor" />
        <path d="M146 115 H354 M250 11 V219" className="nz-dmg__blade" />
        <path d={HELI_GLASS} {...part('win6', 'nz-dmg__glass')} />
      </>
    );
  } else {
    art = (
      <>
        {/* tyres sit outside the body so their state is always readable */}
        {CAR_TYRES.filter((ty) => !ty.optional || states[ty.id] !== 'ok').map((ty) => (
          <rect key={ty.id} x={ty.x} y={ty.y} width={46} height={14} rx={4.5} {...part(ty.id, 'nz-dmg__tyre')} />
        ))}
        <path d={CAR_BODY} className={cx('nz-dmg__body', deformed)} />
        <ellipse cx={284} cy={48} rx={7} ry={3.2} className="nz-dmg__trim" />
        <ellipse cx={284} cy={182} rx={7} ry={3.2} className="nz-dmg__trim" />
        <ellipse cx={375} cy={70} rx={9} ry={3.6} transform="rotate(32 375 70)" className="nz-dmg__head" />
        <ellipse cx={375} cy={160} rx={9} ry={3.6} transform="rotate(-32 375 160)" className="nz-dmg__head" />
        {/* tail lights stay neutral (red means damage here) unless the boot is damaged */}
        <ellipse cx={62} cy={74} rx={7} ry={3} transform="rotate(-58 62 74)" className={cx('nz-dmg__tail', states.door5 === 'bad' && 'is-bad')} />
        <ellipse cx={62} cy={156} rx={7} ry={3} transform="rotate(58 62 156)" className={cx('nz-dmg__tail', states.door5 === 'bad' && 'is-bad')} />
        {CAR_PANELS.map((p) => (
          <path key={p.id} d={p.d} {...part(p.id, 'nz-dmg__panel')} />
        ))}
      </>
    );
  }

  const [tailLabel, noseLabel] = END_LABELS[shape]();
  const endX = shape === 'car' ? [24, 416] : [20, 424];

  return (
    <svg
      viewBox={labels ? '0 0 440 230' : shape === 'car' ? '40 30 360 170' : '30 14 380 202'}
      className={cx('nz-dmg', `is-${shape}`, labels && 'nz-dmg--labels', none && 'is-nodata', className)}
      role="img"
      aria-label={t('Top-down damage diagram')}
    >
      <defs>
        <pattern id={`crack-${uid}`} width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(38)">
          <rect width="6" height="6" className="nz-dmg__crackbg" />
          <line x1="0" y1="0" x2="0" y2="6" className="nz-dmg__crack" />
        </pattern>
        <radialGradient id={`bay-${uid}`} cx="0.5" cy="0.5" r="0.5">
          <stop offset="0" stopOpacity=".5" style={{ stopColor: engineTone === 'red' ? 'var(--red)' : 'var(--amber)' }} />
          <stop offset="1" stopOpacity="0" style={{ stopColor: engineTone === 'red' ? 'var(--red)' : 'var(--amber)' }} />
        </radialGradient>
      </defs>

      {art}

      {engineTone && bay && <ellipse cx={bay.cx} cy={bay.cy} rx={bay.rx} ry={bay.ry} fill={`url(#bay-${uid})`} className="nz-dmg__bay" />}

      {shape === 'car' && (
        <>
          <rect x={176} y={86} width={88} height={58} rx={8} className="nz-dmg__roof" />
          <line x1={186} y1={100} x2={254} y2={100} className="nz-dmg__roofline" />
          <line x1={186} y1={130} x2={254} y2={130} className="nz-dmg__roofline" />
          {CAR_GLASS.map((g) => (
            <path key={g.id} d={g.d} {...part(g.id, 'nz-dmg__glass', aliasOf(g.id))} />
          ))}
        </>
      )}

      {labels && (
        <g className="nz-dmg__labels" aria-hidden="true">
          {shape === 'car' && (
            <>
              <text x={107} y={22}>{t('REAR LEFT')}</text>
              <text x={327} y={22}>{t('FRONT LEFT')}</text>
              <text x={107} y={208}>{t('REAR RIGHT')}</text>
              <text x={327} y={208}>{t('FRONT RIGHT')}</text>
            </>
          )}
          <text x={endX[0]} y={115} transform={`rotate(-90 ${endX[0]} 115)`}>
            {tailLabel}
          </text>
          <text x={endX[1]} y={115} transform={`rotate(90 ${endX[1]} 115)`}>
            {noseLabel}
          </text>
        </g>
      )}
    </svg>
  );
}
