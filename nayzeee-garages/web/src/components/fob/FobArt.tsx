/**
 * Original key fob artwork (inline SVG), shared by the key ring, the fob HUD, the inspect cards
 * and the admin key manager. Nine fob designs plus a plain metal key, drawn for this resource in
 * the NayZeee look (dark shells, chrome trim, teal light pipes). Every fob has four buttons —
 * lock, unlock, trunk, panic — that light up with `active`, and shows the vehicle's brand badge
 * (web/public/brands/png/<slug>.png, see ./brands.ts) or a neutral badge for unknown makes.
 *
 * Designs: classic · generic (flip key) · sport · luxury · leather · compact · slim · card ·
 * retro · key. Unknown names draw 'classic'. Colours: the --teal family for light, local
 * material variables (fob.css) for plastics and metals.
 */
import { useId, useState, type ReactNode } from 'react';
import { brandBadgeUrl, brandName, brandSlug } from './brands';
import './fob.css';

export type FobDesign =
  | 'generic' | 'sport' | 'luxury' | 'classic' | 'leather' | 'compact' | 'slim' | 'card' | 'retro' | 'key';

/** Every design FobArt draws (admin settings / the key ring can offer these). */
export const FOB_DESIGNS: FobDesign[] = ['classic', 'generic', 'sport', 'luxury', 'leather', 'compact', 'slim', 'card', 'retro', 'key'];

export type FobButton = 'lock' | 'unlock' | 'trunk' | 'panic';

export interface FobArtProps {
  design?: FobDesign | string;
  /** 'key' = plain key (standard profile), 'fob' = electronic fob */
  kind?: 'key' | 'fob';
  /** pixel height; width follows the design's aspect */
  size?: number;
  /** vehicle make (GetMakeNameFromVehicleModel / VehicleLabel.make, any case): shows that brand's badge
   *  from web/public/brands (see brandSlug in ./brands.ts); unknown makes show a neutral badge */
  brand?: string | null;
  /** highlight a button: 'lock' | 'unlock' | 'trunk' | 'panic' */
  active?: string | null;
  className?: string;
}

/** viewBox width of each design (the height is always 200). */
const WIDTH: Record<FobDesign, number> = {
  classic: 92, generic: 104, sport: 96, luxury: 78, leather: 100, compact: 88, slim: 58, card: 126, retro: 96, key: 66,
};

function resolveDesign(design: string | undefined | null, kind: string | undefined): FobDesign {
  if (kind === 'key' || design === 'key') return 'key';
  return design && design in WIDTH ? (design as FobDesign) : 'classic';
}

/** Width / height of a design (layout helpers: grids, the HUD frame). */
export function fobAspect(design?: string | null, kind?: string): number {
  return WIDTH[resolveDesign(design, kind)] / 200;
}

/* ───────────────────────────── shared pieces ───────────────────────────── */

interface Ctx {
  id: (name: string) => string;
  url: (name: string) => string;
  active: string | null;
  badge: string | null;
  badgeAlt: string;
  badgeFailed: () => void;
}

function Icon({ name, scale = 1 }: { name: FobButton; scale?: number }) {
  const common = { fill: 'none', stroke: 'currentColor', strokeWidth: 1.5 / scale, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const };
  return (
    <g transform={`scale(${scale})`} className="nz-fobart__icon">
      {name === 'lock' && (
        <>
          <rect x={-4.6} y={-0.6} width={9.2} height={7} rx={1.6} {...common} />
          <path d="M-2.8 -0.6 V-3.2 A2.8 2.8 0 0 1 2.8 -3.2 V-0.6" {...common} />
          <circle cx={0} cy={2.8} r={0.7} fill="currentColor" stroke="none" />
        </>
      )}
      {name === 'unlock' && (
        <>
          <rect x={-4.6} y={-0.6} width={9.2} height={7} rx={1.6} {...common} />
          <path d="M-2.8 -0.6 V-3.6 A2.8 2.8 0 0 1 2.6 -4.8" {...common} />
          <circle cx={0} cy={2.8} r={0.7} fill="currentColor" stroke="none" />
        </>
      )}
      {name === 'trunk' && (
        <>
          <path d="M-6.5 3.2 H6.5 V0.6 L4.2 -0.4 L1.4 -3.2 H-3.6 L-5.6 -0.4 L-6.5 0.6 Z" {...common} />
          <path d="M4.2 -0.4 L7.4 -5.4" {...common} />
          <circle cx={-3.4} cy={3.6} r={1.1} {...common} />
          <circle cx={3.2} cy={3.6} r={1.1} {...common} />
        </>
      )}
      {name === 'panic' && (
        <>
          <path d="M-6 -1.8 H-3.4 L0.6 -4.8 V4.8 L-3.4 1.8 H-6 Z" {...common} />
          <path d="M2.8 -2.4 A3.4 3.4 0 0 1 2.8 2.4 M4.6 -4.2 A6 6 0 0 1 4.6 4.2" {...common} />
        </>
      )}
    </g>
  );
}

type Shape = { kind: 'rect'; w: number; h: number; r: number } | { kind: 'circle'; r: number } | { kind: 'pill'; w: number; h: number };

/** One button: face, light ring (shown when active) and the icon. */
function Btn({ c, name, x, y, shape, tone = 'rubber', iconScale = 1 }: {
  c: Ctx; name: FobButton; x: number; y: number; shape: Shape; tone?: 'rubber' | 'glass' | 'metal' | 'touch'; iconScale?: number;
}) {
  const on = c.active === name;
  const panic = name === 'panic';
  const outline = (inset = 0, props: Record<string, unknown> = {}) => {
    if (shape.kind === 'circle') return <circle r={shape.r - inset} {...props} />;
    const w = shape.w - inset * 2;
    const h = shape.h - inset * 2;
    const r = shape.kind === 'pill' ? h / 2 : Math.max(shape.r - inset, 0);
    return <rect x={-w / 2} y={-h / 2} width={w} height={h} rx={r} {...props} />;
  };
  const face = tone === 'glass' ? c.url('glassBtn') : tone === 'metal' ? c.url('metalBtn') : tone === 'touch' ? 'transparent' : c.url('rubber');
  return (
    <g transform={`translate(${x} ${y})`} className={`nz-fobart__btn nz-fobart__btn--${name} nz-fobart__btn--${tone}${panic ? ' is-panic' : ''}${on ? ' is-active' : ''}`}>
      {outline(-3.5, { className: 'nz-fobart__btn-glow', filter: c.url('glow') })}
      {tone !== 'touch' && outline(-0.8, { className: 'nz-fobart__btn-well' })}
      {outline(0, { fill: face, className: 'nz-fobart__btn-face' })}
      {tone !== 'touch' && outline(0.8, { fill: 'none', className: 'nz-fobart__btn-sheen', stroke: c.url('sheen') })}
      {outline(0, { className: 'nz-fobart__btn-ring', fill: 'none' })}
      <Icon name={name} scale={iconScale} />
    </g>
  );
}

/** Brand badge (chrome logo render) in a round bezel; neutral emblem when the make is unknown. */
function Badge({ c, x, y, r, bezel = true }: { c: Ctx; x: number; y: number; r: number; bezel?: boolean }) {
  const clip = c.id(`badge${Math.round(x)}${Math.round(y)}`);
  return (
    <g transform={`translate(${x} ${y})`} className="nz-fobart__badge">
      {bezel && <circle r={r + 2.2} fill={c.url('chrome')} />}
      {bezel && <circle r={r + 0.6} fill={c.url('badgeWell')} />}
      {c.badge ? (
        <>
          <clipPath id={clip}>
            <circle r={r} />
          </clipPath>
          <image
            href={c.badge}
            x={-r * 0.94}
            y={-r * 0.94}
            width={r * 1.88}
            height={r * 1.88}
            className="nz-fobart__badge-img"
            clipPath={`url(#${clip})`}
            preserveAspectRatio="xMidYMid meet"
            onError={c.badgeFailed}
          >
            <title>{c.badgeAlt}</title>
          </image>
        </>
      ) : (
        <g className="nz-fobart__badge-neutral">
          <circle r={r * 0.62} fill="none" strokeWidth={r * 0.12} />
          <path d={`M${-r * 0.22} ${-r * 0.22} h${r * 0.44} v${r * 0.44} l${-r * 0.16} ${r * 0.16} h${-r * 0.28} z`} />
        </g>
      )}
      {bezel && <circle r={r + 0.6} fill="none" className="nz-fobart__badge-glint" stroke={c.url('sheen')} strokeWidth={0.8} />}
    </g>
  );
}

/** The status LED: teal while a button is pressed, red for the panic button. */
function Led({ c, x, y, w = 10, h = 2.4 }: { c: Ctx; x: number; y: number; w?: number; h?: number }) {
  const on = !!c.active;
  return (
    <g className={`nz-fobart__led${on ? ' is-on' : ''}${c.active === 'panic' ? ' is-panic' : ''}`}>
      <rect x={x - w / 2 - 2} y={y - h / 2 - 2} width={w + 4} height={h + 4} rx={(h + 4) / 2} className="nz-fobart__led-glow" filter={c.url('glow')} />
      <rect x={x - w / 2} y={y - h / 2} width={w} height={h} rx={h / 2} className="nz-fobart__led-lens" />
    </g>
  );
}

/** Split key ring (metal) at the top of a design. */
function Ring({ c, x, y, r = 9 }: { c: Ctx; x: number; y: number; r?: number }) {
  return (
    <g className="nz-fobart__ring">
      <circle cx={x} cy={y} r={r} fill="none" stroke={c.url('chrome')} strokeWidth={2.6} />
      <circle cx={x} cy={y} r={r - 1.6} fill="none" stroke="rgba(0,0,0,.45)" strokeWidth={0.6} />
      <path d={`M${x + r * 0.5} ${y - r * 0.86} a${r} ${r} 0 0 1 ${r * 0.48} ${r * 0.62}`} fill="none" stroke="rgba(255,255,255,.65)" strokeWidth={0.9} strokeLinecap="round" />
    </g>
  );
}

/** Gradients, patterns and filters of one drawing (ids unique per instance). */
function Defs({ c }: { c: Ctx }) {
  const s = (v: string, o?: number) => ({ stopColor: v, stopOpacity: o ?? 1 });
  return (
    <defs>
      <linearGradient id={c.id('shell')} x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" style={s('var(--fob-shell-hi)')} />
        <stop offset=".55" style={s('var(--fob-shell)')} />
        <stop offset="1" style={s('var(--fob-shell-lo)')} />
      </linearGradient>
      <linearGradient id={c.id('face')} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" style={s('var(--fob-face-hi)')} />
        <stop offset="1" style={s('var(--fob-face-lo)')} />
      </linearGradient>
      <linearGradient id={c.id('gloss')} x1="0" y1="0" x2=".7" y2="1">
        <stop offset="0" style={s('#ffffff', 0.2)} />
        <stop offset=".35" style={s('#ffffff', 0.04)} />
        <stop offset=".36" style={s('#ffffff', 0)} />
      </linearGradient>
      <linearGradient id={c.id('chrome')} x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" style={s('var(--fob-chrome-hi)')} />
        <stop offset=".3" style={s('var(--fob-chrome-mid)')} />
        <stop offset=".5" style={s('var(--fob-chrome-lo)')} />
        <stop offset=".72" style={s('var(--fob-chrome-hi)')} />
        <stop offset="1" style={s('var(--fob-chrome-mid)')} />
      </linearGradient>
      <linearGradient id={c.id('brushed')} x1="0" y1="0" x2="1" y2="0">
        <stop offset="0" style={s('var(--fob-chrome-lo)')} />
        <stop offset=".22" style={s('var(--fob-chrome-hi)')} />
        <stop offset=".5" style={s('var(--fob-chrome-mid)')} />
        <stop offset=".8" style={s('var(--fob-chrome-hi)')} />
        <stop offset="1" style={s('var(--fob-chrome-lo)')} />
      </linearGradient>
      <radialGradient id={c.id('badgeWell')} cx=".5" cy=".4" r=".7">
        <stop offset="0" style={s('var(--fob-well-hi)')} />
        <stop offset="1" style={s('var(--fob-well-lo)')} />
      </radialGradient>
      <linearGradient id={c.id('rubber')} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" style={s('var(--fob-btn-hi)')} />
        <stop offset="1" style={s('var(--fob-btn-lo)')} />
      </linearGradient>
      <linearGradient id={c.id('glassBtn')} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" style={s('var(--fob-glass-hi)')} />
        <stop offset="1" style={s('var(--fob-glass-lo)')} />
      </linearGradient>
      <linearGradient id={c.id('metalBtn')} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" style={s('var(--fob-chrome-hi)')} />
        <stop offset=".55" style={s('var(--fob-chrome-mid)')} />
        <stop offset="1" style={s('var(--fob-chrome-lo)')} />
      </linearGradient>
      <linearGradient id={c.id('sheen')} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" style={s('#ffffff', 0.32)} />
        <stop offset=".5" style={s('#ffffff', 0.02)} />
        <stop offset="1" style={s('#000000', 0.3)} />
      </linearGradient>
      <linearGradient id={c.id('leather')} x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" style={s('var(--fob-leather-hi)')} />
        <stop offset="1" style={s('var(--fob-leather-lo)')} />
      </linearGradient>
      <linearGradient id={c.id('strap')} x1="0" y1="0" x2="1" y2="0">
        <stop offset="0" style={s('var(--teal-lo)')} />
        <stop offset=".5" style={s('var(--teal)')} />
        <stop offset="1" style={s('var(--teal-lo)')} />
      </linearGradient>
      <linearGradient id={c.id('pipe')} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" style={s('var(--teal-hi)', 0.9)} />
        <stop offset="1" style={s('var(--teal-lo)', 0.5)} />
      </linearGradient>
      <pattern id={c.id('carbon')} width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
        <rect width="6" height="6" style={{ fill: 'var(--fob-shell-lo)' }} />
        <rect width="3" height="3" style={{ fill: 'var(--fob-carbon)' }} />
        <rect x="3" y="3" width="3" height="3" style={{ fill: 'var(--fob-carbon)' }} />
        <rect width="3" height="1" fill="rgba(255,255,255,.05)" />
        <rect x="3" y="3" width="3" height="1" fill="rgba(255,255,255,.05)" />
      </pattern>
      <pattern id={c.id('grain')} width="4" height="4" patternUnits="userSpaceOnUse">
        <circle cx="1" cy="1" r=".45" fill="rgba(255,255,255,.05)" />
        <circle cx="3" cy="2.6" r=".5" fill="rgba(0,0,0,.25)" />
        <circle cx="2.2" cy="3.6" r=".35" fill="rgba(255,255,255,.035)" />
      </pattern>
      <filter id={c.id('glow')} x="-60%" y="-60%" width="220%" height="220%">
        <feGaussianBlur stdDeviation="2.6" />
      </filter>
      <filter id={c.id('drop')} x="-30%" y="-20%" width="160%" height="150%">
        <feGaussianBlur in="SourceAlpha" stdDeviation="3" />
        <feOffset dy="3" />
        <feComponentTransfer>
          <feFuncA type="linear" slope=".55" />
        </feComponentTransfer>
        <feMerge>
          <feMergeNode />
          <feMergeNode in="SourceGraphic" />
        </feMerge>
      </filter>
    </defs>
  );
}

/* ───────────────────────────── designs ───────────────────────────── */

const BTN = (w: number, h: number, r: number): Shape => ({ kind: 'rect', w, h, r });
const CIRCLE = (r: number): Shape => ({ kind: 'circle', r });
const PILL = (w: number, h: number): Shape => ({ kind: 'pill', w, h });

/** Classic: pebble shell with the NayZeee chamfer at the bottom right, 2x2 buttons, panic bar. */
function Classic({ c }: { c: Ctx }) {
  const body = 'M36 18 H56 Q86 18 86 50 V170 L70 192 H34 Q6 192 6 164 V50 Q6 18 36 18 Z';
  return (
    <>
      <Ring c={c} x={46} y={11} r={8} />
      <path d="M38 16 Q46 8 54 16 V22 H38 Z" fill={c.url('shell')} />
      <path d={body} fill={c.url('shell')} filter={c.url('drop')} />
      <path d={body} fill="none" className="nz-fobart__edge" />
      <path d="M36 26 H56 Q78 26 78 52 V166 L66 184 H35 Q14 184 14 162 V52 Q14 26 36 26 Z" fill={c.url('face')} />
      <path d="M36 26 H56 Q78 26 78 52 V166 L66 184 H35 Q14 184 14 162 V52 Q14 26 36 26 Z" fill={c.url('grain')} opacity={0.8} />
      <path d={body} fill={c.url('gloss')} />
      <Badge c={c} x={46} y={50} r={15} />
      <Led c={c} x={46} y={75} w={14} />
      <Btn c={c} name="lock" x={31} y={100} shape={BTN(24, 24, 7)} />
      <Btn c={c} name="unlock" x={61} y={100} shape={BTN(24, 24, 7)} />
      <Btn c={c} name="trunk" x={31} y={132} shape={BTN(24, 24, 7)} />
      <Btn c={c} name="panic" x={61} y={132} shape={BTN(24, 24, 7)} />
      <path d="M22 160 H56" className="nz-fobart__pipe" stroke={c.url('pipe')} />
      <text x={46} y={175} className="nz-fobart__engrave" textAnchor="middle">NZ</text>
    </>
  );
}

/** Generic: flip key — rounded shell with the folded blade along its right side + release button. */
function Generic({ c }: { c: Ctx }) {
  const body = 'M20 24 H64 Q78 24 78 40 V176 Q78 190 64 190 H20 Q6 190 6 176 V40 Q6 24 20 24 Z';
  return (
    <>
      <Ring c={c} x={24} y={13} r={8} />
      <path d="M16 20 Q24 12 32 20 V28 H16 Z" fill={c.url('shell')} />
      {/* folded blade */}
      <path d="M80 30 H90 Q96 30 96 38 V150 L92 158 L88 150 V44 H80 Z" fill={c.url('brushed')} filter={c.url('drop')} />
      <path d="M88 52 L92 56 L88 60 L92 66 L88 72 L92 78 L88 86 L92 94 L88 100 L92 108 L88 116 L92 124 L88 132" fill="none" stroke="rgba(0,0,0,.35)" strokeWidth={0.7} />
      <path d="M70 26 H84 Q90 26 90 32 V48 H70 Z" fill={c.url('chrome')} />
      <path d={body} fill={c.url('shell')} filter={c.url('drop')} />
      <path d={body} fill="none" className="nz-fobart__edge" />
      <rect x={13} y={34} width={58} height={148} rx={10} fill={c.url('face')} />
      <path d={body} fill={c.url('gloss')} />
      <Badge c={c} x={42} y={55} r={14} />
      <Btn c={c} name="lock" x={42} y={93} shape={BTN(40, 22, 8)} />
      <Btn c={c} name="unlock" x={42} y={120} shape={BTN(40, 22, 8)} />
      <Btn c={c} name="trunk" x={30} y={150} shape={CIRCLE(10)} iconScale={0.85} />
      <Btn c={c} name="panic" x={54} y={150} shape={CIRCLE(10)} iconScale={0.85} />
      <Led c={c} x={42} y={174} w={12} />
      {/* blade release */}
      <rect x={73} y={60} width={6} height={18} rx={3} fill={c.url('metalBtn')} />
    </>
  );
}

/** Sport: angular carbon-fibre shell, teal side light bars, round buttons in a column. */
function Sport({ c }: { c: Ctx }) {
  const body = 'M22 16 H74 L90 38 V168 L70 194 H26 L6 168 V38 Z';
  return (
    <>
      <path d={body} fill={c.url('carbon')} filter={c.url('drop')} />
      <path d={body} fill={c.url('gloss')} />
      <path d={body} fill="none" className="nz-fobart__edge" />
      <path d="M26 22 H70 L83 40 V164 L66 186 H30 L13 164 V40 Z" fill="none" stroke="rgba(255,255,255,.07)" strokeWidth={1} />
      <path d="M9 52 V150" className="nz-fobart__pipe nz-fobart__pipe--side" stroke={c.url('pipe')} />
      <path d="M87 52 V150" className="nz-fobart__pipe nz-fobart__pipe--side" stroke={c.url('pipe')} />
      {/* hex badge plate */}
      <path d="M48 26 L64 35 V53 L48 62 L32 53 V35 Z" fill={c.url('chrome')} />
      <path d="M48 29 L61.5 37 V51.5 L48 59 L34.5 51.5 V37 Z" fill={c.url('badgeWell')} />
      <Badge c={c} x={48} y={44} r={11} bezel={false} />
      <Led c={c} x={48} y={72} w={18} h={2} />
      <Btn c={c} name="lock" x={48} y={94} shape={CIRCLE(12.5)} tone="metal" />
      <Btn c={c} name="unlock" x={48} y={124} shape={CIRCLE(12.5)} tone="metal" />
      <Btn c={c} name="trunk" x={48} y={154} shape={CIRCLE(10.5)} tone="metal" iconScale={0.9} />
      <Btn c={c} name="panic" x={48} y={180} shape={PILL(26, 11)} iconScale={0.7} />
    </>
  );
}

/** Luxury: slim glass capsule in a polished frame; touch buttons under the glass. */
function Luxury({ c }: { c: Ctx }) {
  return (
    <>
      <rect x={4} y={6} width={70} height={188} rx={35} fill={c.url('chrome')} filter={c.url('drop')} />
      <rect x={7.5} y={9.5} width={63} height={181} rx={31.5} fill="var(--fob-glass-lo)" />
      <rect x={7.5} y={9.5} width={63} height={181} rx={31.5} fill={c.url('glassBtn')} opacity={0.65} />
      <Badge c={c} x={39} y={42} r={18} />
      <path d="M22 70 H56" stroke="rgba(255,255,255,.08)" strokeWidth={0.8} />
      <Btn c={c} name="lock" x={39} y={88} shape={CIRCLE(13)} tone="touch" />
      <Btn c={c} name="unlock" x={39} y={118} shape={CIRCLE(13)} tone="touch" />
      <Btn c={c} name="trunk" x={39} y={148} shape={CIRCLE(13)} tone="touch" />
      <Btn c={c} name="panic" x={39} y={174} shape={PILL(22, 10)} tone="touch" iconScale={0.7} />
      <path d="M12 40 Q14 16 39 12" fill="none" stroke="rgba(255,255,255,.35)" strokeWidth={1.4} strokeLinecap="round" />
      <rect x={7.5} y={9.5} width={63} height={181} rx={31.5} fill={c.url('gloss')} />
      <Led c={c} x={39} y={186} w={8} h={1.6} />
    </>
  );
}

/** Leather: the fob in a stitched leather case with a strap loop and D-ring. */
function Leather({ c }: { c: Ctx }) {
  const caseP = 'M18 40 H82 Q94 40 94 54 V178 Q94 194 78 194 H22 Q6 194 6 178 V54 Q6 40 18 40 Z';
  return (
    <>
      <path d="M40 10 H60 Q66 10 66 16 V44 H34 V16 Q34 10 40 10 Z" fill={c.url('leather')} />
      <path d="M40 14 H60 Q62 14 62 16 V40 M38 40 V16 Q38 14 40 14" fill="none" className="nz-fobart__stitch" />
      <path d="M36 6 Q50 -4 64 6" fill="none" stroke={c.url('chrome')} strokeWidth={3} strokeLinecap="round" />
      <rect x={34} y={4} width={32} height={4} rx={2} fill={c.url('chrome')} />
      <path d={caseP} fill={c.url('leather')} filter={c.url('drop')} />
      <path d={caseP} fill={c.url('grain')} />
      <path d="M20 47 H80 Q87 47 87 55 V176 Q87 187 77 187 H23 Q13 187 13 176 V55 Q13 47 20 47 Z" fill="none" className="nz-fobart__stitch" />
      {/* window over the fob's face */}
      <rect x={20} y={56} width={60} height={124} rx={12} fill={c.url('shell')} />
      <rect x={20} y={56} width={60} height={124} rx={12} fill="none" stroke="rgba(0,0,0,.55)" strokeWidth={2} />
      <Badge c={c} x={50} y={78} r={13} />
      <Btn c={c} name="lock" x={36} y={112} shape={BTN(22, 22, 11)} />
      <Btn c={c} name="unlock" x={64} y={112} shape={BTN(22, 22, 11)} />
      <Btn c={c} name="trunk" x={36} y={142} shape={BTN(22, 22, 11)} />
      <Btn c={c} name="panic" x={64} y={142} shape={BTN(22, 22, 11)} />
      <Led c={c} x={50} y={166} w={14} />
      <path d={caseP} fill={c.url('gloss')} opacity={0.5} />
    </>
  );
}

/** Compact: a small rounded fob on a teal fabric lanyard. */
function Compact({ c }: { c: Ctx }) {
  const body = 'M22 74 H66 Q82 74 82 92 V170 Q82 192 60 192 H28 Q6 192 6 170 V92 Q6 74 22 74 Z';
  return (
    <>
      <path d="M30 76 V22 Q30 6 44 6 Q58 6 58 22 V76" fill="none" stroke={c.url('strap')} strokeWidth={9} />
      <path d="M30 76 V22 Q30 6 44 6 Q58 6 58 22 V76" fill="none" stroke="rgba(0,0,0,.25)" strokeWidth={9} strokeDasharray="1 2" />
      <rect x={24} y={60} width={40} height={14} rx={4} fill={c.url('chrome')} />
      <path d={body} fill={c.url('shell')} filter={c.url('drop')} />
      <path d={body} fill="none" className="nz-fobart__edge" />
      <path d="M24 82 H64 Q74 82 74 94 V168 Q74 184 58 184 H30 Q14 184 14 168 V94 Q14 82 24 82 Z" fill={c.url('face')} />
      <path d={body} fill={c.url('gloss')} />
      <Badge c={c} x={44} y={100} r={11} />
      <Btn c={c} name="lock" x={30} y={132} shape={CIRCLE(11)} />
      <Btn c={c} name="unlock" x={58} y={132} shape={CIRCLE(11)} />
      <Btn c={c} name="trunk" x={30} y={162} shape={CIRCLE(9)} iconScale={0.8} />
      <Btn c={c} name="panic" x={58} y={162} shape={CIRCLE(9)} iconScale={0.8} />
      <Led c={c} x={44} y={180} w={8} h={1.8} />
    </>
  );
}

/** Slim: a narrow stick with a brushed spine and four stacked buttons. */
function Slim({ c }: { c: Ctx }) {
  return (
    <>
      <Ring c={c} x={29} y={11} r={8} />
      <rect x={23} y={14} width={12} height={10} rx={3} fill={c.url('chrome')} />
      <rect x={6} y={20} width={46} height={174} rx={20} fill={c.url('shell')} filter={c.url('drop')} />
      <rect x={6} y={20} width={46} height={174} rx={20} fill="none" className="nz-fobart__edge" />
      <rect x={10} y={24} width={4} height={166} rx={2} fill={c.url('brushed')} opacity={0.75} />
      <rect x={44} y={24} width={4} height={166} rx={2} fill={c.url('brushed')} opacity={0.75} />
      <Badge c={c} x={29} y={46} r={12} />
      <Btn c={c} name="lock" x={29} y={80} shape={BTN(26, 22, 8)} />
      <Btn c={c} name="unlock" x={29} y={108} shape={BTN(26, 22, 8)} />
      <Btn c={c} name="trunk" x={29} y={136} shape={BTN(26, 22, 8)} />
      <Btn c={c} name="panic" x={29} y={164} shape={BTN(26, 18, 8)} iconScale={0.85} />
      <Led c={c} x={29} y={184} w={10} h={1.8} />
      <rect x={6} y={20} width={46} height={174} rx={20} fill={c.url('gloss')} />
    </>
  );
}

/** Card: a thin key card with contacts, a teal stripe and touch icons. */
function Card({ c }: { c: Ctx }) {
  return (
    <>
      <rect x={4} y={4} width={118} height={192} rx={12} fill={c.url('shell')} filter={c.url('drop')} />
      <rect x={4} y={4} width={118} height={192} rx={12} fill={c.url('grain')} />
      <rect x={4} y={4} width={118} height={192} rx={12} fill="none" className="nz-fobart__edge" />
      <path d="M4 150 L122 120 V136 L4 166 Z" fill={c.url('strap')} opacity={0.85} />
      <path d="M4 150 L122 120" stroke="rgba(255,255,255,.25)" strokeWidth={0.6} />
      <Badge c={c} x={30} y={32} r={15} />
      {/* contacts */}
      <g transform="translate(78 22)">
        <rect width={30} height={24} rx={4} fill={c.url('brushed')} />
        <path d="M0 8 H10 M0 16 H10 M20 8 H30 M20 16 H30 M10 0 V24 M20 0 V24" stroke="rgba(0,0,0,.35)" strokeWidth={0.8} />
      </g>
      <path d="M78 58 a8 8 0 0 1 0 12 M82 54 a13 13 0 0 1 0 20 M86 50 a18 18 0 0 1 0 28" fill="none" className="nz-fobart__nfc" />
      <Btn c={c} name="lock" x={30} y={94} shape={CIRCLE(13)} tone="touch" />
      <Btn c={c} name="unlock" x={63} y={94} shape={CIRCLE(13)} tone="touch" />
      <Btn c={c} name="trunk" x={96} y={94} shape={CIRCLE(13)} tone="touch" />
      <Btn c={c} name="panic" x={96} y={174} shape={PILL(30, 14)} tone="touch" iconScale={0.8} />
      <Led c={c} x={26} y={176} w={20} h={2} />
      <rect x={4} y={4} width={118} height={192} rx={12} fill={c.url('gloss')} />
    </>
  );
}

/** Retro: a tear-drop remote with two big rubber buttons, a chrome band and a small panic key. */
function Retro({ c }: { c: Ctx }) {
  const body = 'M48 18 C78 18 90 44 90 74 V150 C90 178 72 194 48 194 C24 194 6 178 6 150 V74 C6 44 18 18 48 18 Z';
  return (
    <>
      <Ring c={c} x={48} y={12} r={9} />
      <path d={body} fill={c.url('shell')} filter={c.url('drop')} />
      <path d={body} fill="none" className="nz-fobart__edge" />
      <path d="M6 112 H90" stroke={c.url('brushed')} strokeWidth={5} />
      <path d="M6 110 H90" stroke="rgba(255,255,255,.18)" strokeWidth={0.6} />
      <Badge c={c} x={48} y={50} r={14} />
      <Btn c={c} name="lock" x={30} y={86} shape={CIRCLE(14)} />
      <Btn c={c} name="unlock" x={66} y={86} shape={CIRCLE(14)} />
      <Btn c={c} name="trunk" x={33} y={142} shape={BTN(28, 20, 6)} iconScale={0.9} />
      <Btn c={c} name="panic" x={63} y={142} shape={BTN(28, 20, 6)} iconScale={0.9} />
      <Led c={c} x={48} y={172} w={6} h={6} />
      <path d={body} fill={c.url('gloss')} />
    </>
  );
}

/** Plain metal key: rubber head with the badge, ring hole, shoulder and a cut blade. */
function Key({ c }: { c: Ctx }) {
  const head = 'M10 30 Q10 6 33 6 Q56 6 56 30 V64 Q56 76 44 78 H22 Q10 76 10 64 Z';
  return (
    <>
      <path d={head} fill={c.url('shell')} filter={c.url('drop')} />
      <path d={head} fill="none" className="nz-fobart__edge" />
      <circle cx={33} cy={18} r={5.5} fill="var(--fob-hole)" />
      <circle cx={33} cy={18} r={5.5} fill="none" stroke={c.url('chrome')} strokeWidth={1.4} />
      <Badge c={c} x={33} y={48} r={13} />
      <path d="M22 78 H44 V86 H22 Z" fill={c.url('chrome')} />
      {/* blade with cuts */}
      <path
        d="M24 86 H42 V170 L36 192 H30 L28 184 L24 180 V172 L28 168 L24 162 V154 L28 150 L24 144 V136 L29 132 L24 126 V118 L28 114 L24 108 Z"
        fill={c.url('brushed')}
        filter={c.url('drop')}
      />
      <path d="M33 90 V182" stroke="rgba(0,0,0,.3)" strokeWidth={1.2} />
      <path d="M36 90 V176" stroke="rgba(255,255,255,.35)" strokeWidth={0.6} />
      <path d={head} fill={c.url('gloss')} />
    </>
  );
}

const DRAW: Record<FobDesign, (p: { c: Ctx }) => ReactNode> = {
  classic: Classic, generic: Generic, sport: Sport, luxury: Luxury, leather: Leather,
  compact: Compact, slim: Slim, card: Card, retro: Retro, key: Key,
};

export function FobArt({ design, kind = 'fob', size = 120, brand = null, active = null, className }: FobArtProps) {
  const which = resolveDesign(design, kind);
  const uid = useId().replace(/[^a-zA-Z0-9_-]/g, '');
  const slug = brandSlug(brand);
  const [failed, setFailed] = useState<string | null>(null);
  const badge = slug && failed !== slug ? brandBadgeUrl(slug) : null;
  const width = WIDTH[which];
  const c: Ctx = {
    id: (n) => `nzf${uid}${n}`,
    url: (n) => `url(#nzf${uid}${n})`,
    active: which === 'key' ? null : (active as string | null) || null,
    badge,
    badgeAlt: slug ? brandName(slug) : '',
    badgeFailed: () => setFailed(slug),
  };
  const Draw = DRAW[which];
  return (
    <span
      className={`nz-fobart nz-fobart--${which}${c.active ? ' is-pressed' : ''}${className ? ` ${className}` : ''}`}
      style={{ width: Math.round((size * width) / 200), height: size }}
      role="img"
      aria-label={slug ? brandName(slug) : undefined}
    >
      <svg viewBox={`0 0 ${width} 200`} width="100%" height="100%" aria-hidden="true">
        <Defs c={c} />
        <Draw c={c} />
      </svg>
    </span>
  );
}
