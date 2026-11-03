/**
 * Top-down damage diagram (nose to the right). Damaged doors / panels and smashed windows
 * glow red, burst tyres amber, tyres on the rim red; a deformed body gets a dashed red
 * outline and the engine bay is tinted by engine health. `labels` adds the side captions
 * (large Condition view); without them it is the small glyph of the Overview.
 */
import { useId } from 'react';
import { cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { DamageSummary } from '@/lib/types';
import { partStates } from './data';
import type { PartState } from './data';

interface Props {
  damage: DamageSummary | null;
  labels?: boolean;
  /** Highlighted part id (hover from the parts list). */
  hot?: string | null;
  onHot?: (id: string | null) => void;
  className?: string;
}

/* Shapes in a 440 × 230 box, body from x 50 to 390, centre line y 115. */
const BODY = 'M90 53 L320 51 C366 53 388 80 390 115 C388 150 366 177 320 179 L90 177 C64 175 50 152 50 115 C50 78 64 55 90 53 Z';

const PANELS: { id: string; d: string }[] = [
  { id: 'door4', d: 'M304 60 L320 59 C360 61 380 86 382 115 C380 144 360 169 320 171 L304 170 C299 142 299 88 304 60 Z' },
  { id: 'door5', d: 'M140 62 L94 61 C72 63 61 86 59 115 C61 144 72 167 94 169 L140 168 C136 142 136 88 140 62 Z' },
  { id: 'door0', d: 'M224 57 H292 Q296 57 296 61 V70 Q296 74 292 74 H224 Q220 74 220 70 V61 Q220 57 224 57 Z' },
  { id: 'door2', d: 'M150 58 H212 Q216 58 216 62 V70 Q216 74 212 74 H150 Q146 74 146 70 V62 Q146 58 150 58 Z' },
  { id: 'door1', d: 'M224 156 H292 Q296 156 296 160 V169 Q296 173 292 173 H224 Q220 173 220 169 V160 Q220 156 224 156 Z' },
  { id: 'door3', d: 'M150 156 H212 Q216 156 216 160 V168 Q216 172 212 172 H150 Q146 172 146 168 V160 Q146 156 150 156 Z' },
];

const GLASS: { id: string; d: string }[] = [
  { id: 'win6', d: 'M268 84 L298 74 C293 100 293 130 298 156 L268 146 C265 128 265 102 268 84 Z' },
  { id: 'win7', d: 'M146 76 L172 86 C170 104 170 126 172 144 L146 154 C143 130 143 100 146 76 Z' },
  { id: 'win0', d: 'M226 77 H262 Q265 77 265 80 V80.5 Q265 83 262 83 H226 Q223 83 223 80.5 V80 Q223 77 226 77 Z' },
  { id: 'win2', d: 'M180 77 H213 Q216 77 216 80 V80.5 Q216 83 213 83 H180 Q177 83 177 80.5 V80 Q177 77 180 77 Z' },
  { id: 'win1', d: 'M226 147 H262 Q265 147 265 150 V150.5 Q265 153 262 153 H226 Q223 153 223 150.5 V150 Q223 147 226 147 Z' },
  { id: 'win3', d: 'M180 147 H213 Q216 147 216 150 V150.5 Q216 153 213 153 H180 Q177 153 177 150.5 V150 Q177 147 180 147 Z' },
];

const TYRES: { id: string; x: number; y: number; optional?: boolean }[] = [
  { id: 'tyre0', x: 304, y: 37 },
  { id: 'tyre1', x: 304, y: 179 },
  { id: 'tyre4', x: 84, y: 37 },
  { id: 'tyre5', x: 84, y: 179 },
  { id: 'tyre2', x: 192, y: 37, optional: true },
  { id: 'tyre3', x: 192, y: 179, optional: true },
];

export function DamageDiagram({ damage, labels = false, hot = null, onHot, className }: Props) {
  const uid = useId().replace(/:/g, '');
  const states = partStates(damage);
  const engine = damage ? damage.engine / 10 : 100;
  const engineTone = engine < 25 ? 'red' : engine < 50 ? 'amber' : null;
  const none = !damage;

  const part = (id: string, base: string) => {
    const s: PartState = states[id] ?? 'ok';
    return {
      className: cx(base, `is-${s}`, hot === id && 'is-hot'),
      onMouseEnter: onHot ? () => onHot(id) : undefined,
      onMouseLeave: onHot ? () => onHot(null) : undefined,
      'data-part': id,
    };
  };

  return (
    <svg
      viewBox={labels ? '0 0 440 230' : '40 30 360 170'}
      className={cx('nz-dmg', labels && 'nz-dmg--labels', none && 'is-nodata', className)}
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

      {/* tyres sit outside the body so their state is always readable */}
      {TYRES.filter((ty) => !ty.optional || states[ty.id] !== 'ok').map((ty) => (
        <rect key={ty.id} x={ty.x} y={ty.y} width={46} height={14} rx={4.5} {...part(ty.id, 'nz-dmg__tyre')} />
      ))}

      <path d={BODY} className={cx('nz-dmg__body', damage?.deformed && 'is-deformed')} />
      <ellipse cx={284} cy={48} rx={7} ry={3.2} className="nz-dmg__trim" />
      <ellipse cx={284} cy={182} rx={7} ry={3.2} className="nz-dmg__trim" />
      <ellipse cx={375} cy={70} rx={9} ry={3.6} transform="rotate(32 375 70)" className="nz-dmg__head" />
      <ellipse cx={375} cy={160} rx={9} ry={3.6} transform="rotate(-32 375 160)" className="nz-dmg__head" />
      <ellipse cx={62} cy={74} rx={7} ry={3} transform="rotate(-58 62 74)" className="nz-dmg__tail" />
      <ellipse cx={62} cy={156} rx={7} ry={3} transform="rotate(58 62 156)" className="nz-dmg__tail" />

      {PANELS.map((p) => (
        <path key={p.id} d={p.d} {...part(p.id, 'nz-dmg__panel')} />
      ))}
      {engineTone && <ellipse cx={342} cy={115} rx={34} ry={44} fill={`url(#bay-${uid})`} className="nz-dmg__bay" />}

      <rect x={176} y={86} width={88} height={58} rx={8} className="nz-dmg__roof" />
      <line x1={186} y1={100} x2={254} y2={100} className="nz-dmg__roofline" />
      <line x1={186} y1={130} x2={254} y2={130} className="nz-dmg__roofline" />

      {GLASS.map((g) => {
        const smashed = states[g.id] === 'bad';
        return <path key={g.id} d={g.d} {...part(g.id, 'nz-dmg__glass')} fill={smashed ? `url(#crack-${uid})` : undefined} />;
      })}

      {labels && (
        <g className="nz-dmg__labels" aria-hidden="true">
          <text x={107} y={22}>{t('REAR LEFT')}</text>
          <text x={327} y={22}>{t('FRONT LEFT')}</text>
          <text x={107} y={208}>{t('REAR RIGHT')}</text>
          <text x={327} y={208}>{t('FRONT RIGHT')}</text>
          <text x={24} y={115} transform="rotate(-90 24 115)">{t('BOOT')}</text>
          <text x={416} y={115} transform="rotate(90 416 115)">{t('BONNET')}</text>
        </g>
      )}
    </svg>
  );
}
