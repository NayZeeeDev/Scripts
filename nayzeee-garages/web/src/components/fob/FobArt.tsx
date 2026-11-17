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
  classic: 92, generic: 96, sport: 96, luxury: 78, leather: 100, compact: 88, slim: 58, card: 126, retro: 96, key: 66,
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
  c: Ctx; name: FobButton; x: number; y: number; shape: Shape; tone?: 'rubber' | 'glass' | 'metal' | 'touch' | 'piano'; iconScale?: number;
}) {
  if (tone === 'piano') return <PianoBtn c={c} name={name} x={x} y={y} shape={shape} iconScale={iconScale} />;
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


/** Physical piano-black button (crimson for panic): contact shadow, gap, bevelled face with a lit
 *  top edge and a dark lower lip, glass sheen, micro-engraved icon. */
function PianoBtn({ c, name, x, y, shape, iconScale = 1 }: { c: Ctx; name: FobButton; x: number; y: number; shape: Shape; iconScale?: number }) {
  const on = c.active === name;
  const panic = name === 'panic';
  const outline = (inset = 0, props: Record<string, unknown> = {}) => {
    if (shape.kind === 'circle') return <circle r={shape.r - inset} {...props} />;
    const w = shape.w - inset * 2;
    const h = shape.h - inset * 2;
    const r = shape.kind === 'pill' ? h / 2 : Math.max(shape.r - inset, 0);
    return <rect x={-w / 2} y={-h / 2} width={w} height={h} rx={r} {...props} />;
  };
  return (
    <g transform={`translate(${x} ${y})`} className={`nz-fobart__btn nz-fobart__btn--piano nz-fobart__btn--${name}${panic ? ' is-panic' : ''}${on ? ' is-active' : ''}`}>
      {outline(-3.5, { className: 'nz-fobart__btn-glow', filter: c.url('glow') })}
      {/* the gap the button sits in, then its contact shadow */}
      {outline(-1.1, { fill: '#000', opacity: 0.85 })}
      {outline(0, { fill: '#000', opacity: 0.6, transform: 'translate(0 1.2)', filter: c.url('soft') })}
      <g className="nz-fobart__btn-face">
        {outline(0, { fill: c.url(panic ? 'crimson' : 'pianoBtn') })}
        {outline(0, { fill: c.url('btnDome') })}
        {outline(0.35, { fill: 'none', stroke: c.url(panic ? 'crimsonEdge' : 'btnEdge'), strokeWidth: 0.8 })}
        {outline(1.6, { fill: 'none', stroke: 'rgba(0,0,0,.45)', strokeWidth: 0.6 })}
      </g>
      {outline(0, { className: 'nz-fobart__btn-ring', fill: 'none' })}
      <g transform="translate(0 .55)" className="nz-fobart__engrave-shadow"><Icon name={name} scale={iconScale} /></g>
      <Icon name={name} scale={iconScale} />
    </g>
  );
}

/** Recessed button column: machined chrome rail around a piano-black well with an inner shadow. */
function Column({ c, x, y, w, h, r }: { c: Ctx; x: number; y: number; w: number; h: number; r: number }) {
  return (
    <g className="nz-fobart__column">
      <rect x={x - 1.6} y={y - 1.6} width={w + 3.2} height={h + 3.2} rx={r + 1.6} fill={c.url('bezel')} />
      <rect x={x - 1.6} y={y - 1.6} width={w + 3.2} height={h + 3.2} rx={r + 1.6} fill="none" stroke={c.url('spec')} strokeWidth={0.6} />
      <rect x={x} y={y} width={w} height={h} rx={r} fill={c.url('wellDeep')} filter={c.url('inset')} />
    </g>
  );
}

/** Recessed metallic brand badge: chrome bezel, dark well, the brand render, a glint. */
function CrownBadge({ c, x, y, r }: { c: Ctx; x: number; y: number; r: number }) {
  return (
    <g className="nz-fobart__crown">
      <circle cx={x} cy={y + 0.9} r={r + 3.2} fill="#000" opacity={0.55} filter={c.url('soft')} />
      <circle cx={x} cy={y} r={r + 3} fill={c.url('bezel')} />
      <circle cx={x} cy={y} r={r + 3} fill="none" stroke={c.url('spec')} strokeWidth={0.6} />
      <circle cx={x} cy={y} r={r + 1.1} fill={c.url('gunmetal')} filter={c.url('inset')} />
      <Badge c={c} x={x} y={y} r={r} bezel={false} />
      <path d={`M${x - r * 0.75} ${y - r * 0.55} A${r} ${r} 0 0 1 ${x + r * 0.2} ${y - r * 0.98}`} fill="none" stroke="rgba(255,255,255,.35)" strokeWidth={0.7} strokeLinecap="round" />
    </g>
  );
}

/** Mirror a right-hand outline (start on the centre line, cubic segments down to the centre line). */
function symPath(w: number, start: [number, number], segs: number[][]): string {
  const m = (x: number) => +(w - x).toFixed(2);
  const pts: [number, number][] = [start];
  let d = `M${start[0]} ${start[1]} `;
  for (const s of segs) {
    d += `C${s[0]} ${s[1]} ${s[2]} ${s[3]} ${s[4]} ${s[5]} `;
    pts.push([s[4], s[5]]);
  }
  for (let i = segs.length - 1; i >= 0; i--) {
    const s = segs[i];
    d += `C${m(s[2])} ${s[3]} ${m(s[0])} ${s[1]} ${m(pts[i][0])} ${pts[i][1]} `;
  }
  return `${d}Z`;
}

/** Transform that shrinks a full-height outline of width `w` evenly by `inset` (rims, stitch lines). */
function inner(w: number, inset: number, y0 = 0, h = 200): string {
  const cy = y0 + h / 2;
  return `translate(${w / 2} ${cy}) scale(${((w - inset * 2) / w).toFixed(4)} ${((h - inset * 2) / h).toFixed(4)}) translate(${-w / 2} ${-cy})`;
}

/** Shell stack shared by the premium fobs: shadows, machined chrome rim with a specular edge,
 *  a gap line, then the piano-black (or carbon) body with its diagonal glass sheen.
 *  `y0` / `h` give the outline's vertical span when it does not fill the drawing. */
function Shell({ c, d, w, inset = 4.2, body = 'piano', y0 = 0, h = 200 }: {
  c: Ctx; d: string; w: number; inset?: number; body?: 'piano' | 'carbon'; y0?: number; h?: number;
}) {
  return (
    <g className="nz-fobart__shell">
      <path d={d} fill="#000" opacity={0.55} transform="translate(0 5)" filter={c.url('shadowWide')} />
      <path d={d} fill="#000" opacity={0.7} transform="translate(0 1.4)" filter={c.url('soft')} />
      <path d={d} fill={c.url('bezel')} />
      <path d={d} fill={c.url('bezelShade')} />
      <path d={d} fill="none" stroke={c.url('spec')} strokeWidth={0.9} />
      <path d={d} transform={inner(w, inset, y0, h)} fill="#000" />
      <g transform={inner(w, inset + 0.5, y0, h)}>
        <path d={d} fill={c.url(body === 'carbon' ? 'carbonWeave' : 'piano')} />
        {body === 'carbon' && <path d={d} fill={c.url('carbonShade')} />}
        <path d={d} fill={c.url('pianoSheen')} />
        <path d={d} fill="none" stroke="rgba(255,255,255,.10)" strokeWidth={0.6} />
      </g>
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
      {/* ── premium materials (classic / generic / sport) ── */}
      <linearGradient id={c.id('piano')} x1="0" y1="0" x2=".35" y2="1">
        <stop offset="0" style={s('#1a1a1f')} />
        <stop offset=".42" style={s('#0f0f13')} />
        <stop offset="1" style={s('#08080a')} />
      </linearGradient>
      <linearGradient id={c.id('pianoSheen')} x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" style={s('#ffffff', 0.13)} />
        <stop offset=".18" style={s('#ffffff', 0.03)} />
        <stop offset=".31" style={s('#ffffff', 0)} />
        <stop offset=".335" style={s('#ffffff', 0.12)} />
        <stop offset=".44" style={s('#ffffff', 0.025)} />
        <stop offset=".45" style={s('#ffffff', 0)} />
        <stop offset=".86" style={s('#ffffff', 0)} />
        <stop offset="1" style={s('#ffffff', 0.05)} />
      </linearGradient>
      <linearGradient id={c.id('bezel')} x1="0" y1="0" x2="1" y2=".22">
        <stop offset="0" style={s('#3d4247')} />
        <stop offset=".07" style={s('#f7f8f9')} />
        <stop offset=".16" style={s('#9aa1a7')} />
        <stop offset=".3" style={s('#2c3035')} />
        <stop offset=".46" style={s('#d9dde0')} />
        <stop offset=".54" style={s('#ffffff')} />
        <stop offset=".63" style={s('#8b9298')} />
        <stop offset=".78" style={s('#24282c')} />
        <stop offset=".9" style={s('#c3c8cc')} />
        <stop offset="1" style={s('#4b5157')} />
      </linearGradient>
      <linearGradient id={c.id('bezelShade')} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" style={s('#ffffff', 0.18)} />
        <stop offset=".3" style={s('#ffffff', 0)} />
        <stop offset=".72" style={s('#000000', 0)} />
        <stop offset="1" style={s('#000000', 0.38)} />
      </linearGradient>
      <linearGradient id={c.id('spec')} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" style={s('#ffffff', 0.95)} />
        <stop offset=".35" style={s('#ffffff', 0.35)} />
        <stop offset=".7" style={s('#000000', 0.25)} />
        <stop offset="1" style={s('#000000', 0.65)} />
      </linearGradient>
      <linearGradient id={c.id('gunmetal')} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" style={s('#3a3f45')} />
        <stop offset=".55" style={s('#22262a')} />
        <stop offset="1" style={s('#131518')} />
      </linearGradient>
      <linearGradient id={c.id('wellDeep')} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" style={s('#050506')} />
        <stop offset="1" style={s('#0d0d10')} />
      </linearGradient>
      <linearGradient id={c.id('pianoBtn')} x1="0" y1="0" x2=".2" y2="1">
        <stop offset="0" style={s('#24242a')} />
        <stop offset=".5" style={s('#141418')} />
        <stop offset="1" style={s('#0a0a0c')} />
      </linearGradient>
      <radialGradient id={c.id('btnDome')} cx=".38" cy=".12" r=".9">
        <stop offset="0" style={s('#ffffff', 0.16)} />
        <stop offset=".45" style={s('#ffffff', 0.03)} />
        <stop offset="1" style={s('#000000', 0.25)} />
      </radialGradient>
      <linearGradient id={c.id('btnEdge')} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" style={s('#ffffff', 0.42)} />
        <stop offset=".4" style={s('#ffffff', 0.06)} />
        <stop offset="1" style={s('#000000', 0.7)} />
      </linearGradient>
      <linearGradient id={c.id('crimson')} x1="0" y1="0" x2=".2" y2="1">
        <stop offset="0" style={s('#e0353a')} />
        <stop offset=".45" style={s('#b91c1c')} />
        <stop offset="1" style={s('#6e1010')} />
      </linearGradient>
      <linearGradient id={c.id('crimsonEdge')} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" style={s('#ffb3b3', 0.7)} />
        <stop offset=".45" style={s('#ffffff', 0.05)} />
        <stop offset="1" style={s('#2a0505', 0.85)} />
      </linearGradient>
      <pattern id={c.id('carbonWeave')} width="5" height="5" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
        <rect width="5" height="5" fill="#0a0b0d" />
        <rect width="2.5" height="2.5" fill="#202328" />
        <rect x="2.5" y="2.5" width="2.5" height="2.5" fill="#202328" />
        <rect width="2.5" height=".7" fill="rgba(255,255,255,.09)" />
        <rect x="2.5" y="2.5" width="2.5" height=".7" fill="rgba(255,255,255,.09)" />
        <rect x="2.5" width=".6" height="2.5" fill="rgba(255,255,255,.05)" />
        <rect y="2.5" width=".6" height="2.5" fill="rgba(255,255,255,.05)" />
      </pattern>
      <radialGradient id={c.id('carbonShade')} cx=".35" cy=".25" r=".9">
        <stop offset="0" style={s('#000000', 0)} />
        <stop offset="1" style={s('#000000', 0.55)} />
      </radialGradient>
      <linearGradient id={c.id('leatherRich')} x1="0" y1="0" x2=".4" y2="1">
        <stop offset="0" style={s('#6b4630')} />
        <stop offset=".5" style={s('#3a2416')} />
        <stop offset="1" style={s('#1e120a')} />
      </linearGradient>
      <pattern id={c.id('leatherGrain')} width="5" height="5" patternUnits="userSpaceOnUse">
        <circle cx=".8" cy="1.1" r=".55" fill="rgba(0,0,0,.28)" />
        <circle cx="3.4" cy=".7" r=".4" fill="rgba(0,0,0,.22)" />
        <circle cx="2.2" cy="2.9" r=".6" fill="rgba(0,0,0,.25)" />
        <circle cx="4.3" cy="3.6" r=".45" fill="rgba(0,0,0,.2)" />
        <circle cx="1.2" cy="4.4" r=".35" fill="rgba(255,220,190,.06)" />
        <circle cx="3.9" cy="2.1" r=".3" fill="rgba(255,220,190,.07)" />
        <path d="M0 2 Q1.5 1.6 2.6 2.3 M2.8 4.6 Q4 4.1 5 4.5" fill="none" stroke="rgba(0,0,0,.18)" strokeWidth=".3" />
      </pattern>
      <radialGradient id={c.id('leatherShade')} cx=".35" cy=".22" r=".95">
        <stop offset="0" style={s('#ffd9b0', 0.1)} />
        <stop offset=".45" style={s('#000000', 0)} />
        <stop offset="1" style={s('#000000', 0.5)} />
      </radialGradient>
      <filter id={c.id('soft')} x="-30%" y="-30%" width="160%" height="160%">
        <feGaussianBlur stdDeviation="1.1" />
      </filter>
      <filter id={c.id('shadowWide')} x="-40%" y="-30%" width="180%" height="170%">
        <feGaussianBlur stdDeviation="5" />
      </filter>
      <filter id={c.id('inset')} x="-20%" y="-20%" width="140%" height="140%">
        <feFlood floodColor="#000" floodOpacity=".95" result="ink" />
        <feComposite in="ink" in2="SourceGraphic" operator="out" result="ring" />
        <feGaussianBlur in="ring" stdDeviation="1.6" result="blur" />
        <feOffset in="blur" dy="1.4" result="shift" />
        <feComposite in="shift" in2="SourceGraphic" operator="in" result="inner" />
        <feMerge>
          <feMergeNode in="SourceGraphic" />
          <feMergeNode in="inner" />
        </feMerge>
      </filter>
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

const CLASSIC_D = symPath(92, [46, 9], [
  [52, 9, 58, 7, 64, 7],
  [75, 7, 83, 11, 86, 22],
  [88, 36, 87, 58, 84, 76],
  [81, 92, 80, 104, 80, 116],
  [80, 134, 86, 154, 86, 172],
  [86, 188, 72, 196, 46, 196],
]);

/** Classic: tall piano-black fob with a notched chrome crown, tapered waist, full machined rim and a
 *  recessed chrome-railed column of stacked buttons, crimson panic at the bottom. */
function Classic({ c }: { c: Ctx }) {
  return (
    <>
      <Shell c={c} d={CLASSIC_D} w={92} />
      <CrownBadge c={c} x={46} y={35} r={13} />
      <Column c={c} x={31} y={62} w={30} h={110} r={13} />
      <Btn c={c} name="lock" x={46} y={77} shape={BTN(24, 21, 9)} tone="piano" />
      <Btn c={c} name="unlock" x={46} y={101} shape={BTN(24, 21, 9)} tone="piano" />
      <Btn c={c} name="trunk" x={46} y={125} shape={BTN(24, 21, 9)} tone="piano" />
      <Btn c={c} name="panic" x={46} y={154} shape={BTN(24, 22, 9)} tone="piano" />
      <Led c={c} x={46} y={140} w={8} h={1.6} />
      {/* emergency blade slot */}
      <rect x={36} y={182} width={20} height={4.4} rx={2.2} fill="#000" />
      <rect x={37} y={182.6} width={18} height={3.2} rx={1.6} fill={c.url('bezel')} opacity={0.9} />
    </>
  );
}

const GENERIC_D = symPath(96, [48, 10], [
  [66, 10, 82, 16, 86, 32],
  [90, 48, 88, 70, 85, 90],
  [83, 104, 83, 118, 85, 132],
  [88, 150, 90, 172, 82, 186],
  [76, 195, 62, 197, 48, 197],
]);

/** Generic: grand-tourer fob: broad sculpted shell with a pinched waist, recessed chrome badge,
 *  a chrome-framed 2x2 button cluster (crimson panic) and a machined blade release. */
function Generic({ c }: { c: Ctx }) {
  return (
    <>
      <Shell c={c} d={GENERIC_D} w={96} />
      {/* sculpted side rails */}
      <path d="M14 58 C11 90 11 120 15 150" fill="none" stroke="rgba(255,255,255,.10)" strokeWidth={1} strokeLinecap="round" />
      <path d="M82 58 C85 90 85 120 81 150" fill="none" stroke="rgba(0,0,0,.6)" strokeWidth={1} strokeLinecap="round" />
      <CrownBadge c={c} x={48} y={38} r={13} />
      <Column c={c} x={21} y={68} w={54} h={92} r={14} />
      <Btn c={c} name="lock" x={35} y={92} shape={BTN(22, 36, 9)} tone="piano" />
      <Btn c={c} name="unlock" x={61} y={92} shape={BTN(22, 36, 9)} tone="piano" />
      <Btn c={c} name="trunk" x={35} y={137} shape={BTN(22, 36, 9)} tone="piano" />
      <Btn c={c} name="panic" x={61} y={137} shape={BTN(22, 36, 9)} tone="piano" />
      <Led c={c} x={48} y={170} w={10} h={1.8} />
      {/* blade release slider */}
      <rect x={36} y={178} width={24} height={7} rx={3.5} fill="#000" />
      <rect x={37} y={178.8} width={22} height={5.4} rx={2.7} fill={c.url('bezel')} />
      <path d="M41 180 V183 M45 180 V183 M49 180 V183 M53 180 V183" stroke="rgba(0,0,0,.45)" strokeWidth={0.6} />
    </>
  );
}

const SPORT_D = symPath(96, [48, 8], [
  [58, 8, 66, 12, 70, 22],
  [73, 30, 74, 40, 80, 50],
  [86, 58, 86, 74, 82, 86],
  [79, 96, 79, 110, 82, 122],
  [87, 134, 89, 156, 86, 172],
  [83, 188, 66, 196, 48, 196],
]);

/** Sport: car-shaped fob seen from above (nose, flared fenders, pinched doors, wide haunches) with a
 *  machined chrome rim, carbon-fibre body, a piano-black spine of stacked buttons, panic up front. */
function Sport({ c }: { c: Ctx }) {
  return (
    <>
      <Shell c={c} d={SPORT_D} w={96} body="carbon" />
      {/* bonnet and haunch creases */}
      <path d="M36 44 C40 52 56 52 60 44" fill="none" stroke="rgba(255,255,255,.12)" strokeWidth={0.8} />
      <path d="M22 140 C26 160 30 170 36 178 M74 140 C70 160 66 170 60 178" fill="none" stroke="rgba(255,255,255,.08)" strokeWidth={0.8} />
      <CrownBadge c={c} x={48} y={27} r={10} />
      <Column c={c} x={35} y={50} w={26} h={126} r={13} />
      <Btn c={c} name="panic" x={48} y={63} shape={PILL(20, 12)} tone="piano" iconScale={0.7} />
      <Btn c={c} name="trunk" x={48} y={89} shape={BTN(20, 22, 9)} tone="piano" iconScale={0.9} />
      <Btn c={c} name="unlock" x={48} y={116} shape={BTN(20, 22, 9)} tone="piano" iconScale={0.9} />
      <Btn c={c} name="lock" x={48} y={143} shape={BTN(20, 22, 9)} tone="piano" iconScale={0.9} />
      <Led c={c} x={48} y={164} w={8} h={1.6} />
      {/* chrome key-ring eyelet in the tail */}
      <circle cx={48} cy={185} r={5.2} fill={c.url('bezel')} />
      <circle cx={48} cy={185} r={3.2} fill="#000" />
      <circle cx={48} cy={185} r={5.2} fill="none" stroke={c.url('spec')} strokeWidth={0.6} />
    </>
  );
}

const LUXURY_D = symPath(78, [39, 8], [
  [50, 8, 64, 12, 68, 26],
  [72, 40, 70, 62, 67, 82],
  [65, 96, 65, 110, 66, 122],
  [68, 144, 70, 170, 62, 186],
  [56, 195, 48, 197, 39, 197],
]);

/** Luxury: slender tapered capsule, polished chrome frame, piano-black body, round domed buttons in
 *  a chrome-railed column, crimson panic set apart, a chrome signature bar at the tail. */
function Luxury({ c }: { c: Ctx }) {
  return (
    <>
      <Shell c={c} d={LUXURY_D} w={78} inset={3.6} />
      <CrownBadge c={c} x={39} y={34} r={12} />
      <Column c={c} x={26} y={56} w={26} h={120} r={13} />
      <Btn c={c} name="lock" x={39} y={72} shape={CIRCLE(10.5)} tone="piano" iconScale={0.9} />
      <Btn c={c} name="unlock" x={39} y={98} shape={CIRCLE(10.5)} tone="piano" iconScale={0.9} />
      <Btn c={c} name="trunk" x={39} y={124} shape={CIRCLE(10.5)} tone="piano" iconScale={0.85} />
      <Led c={c} x={39} y={139} w={7} h={1.5} />
      <Btn c={c} name="panic" x={39} y={157} shape={CIRCLE(10.5)} tone="piano" iconScale={0.85} />
      {/* chrome signature bar */}
      <rect x={29} y={182.4} width={20} height={3.2} rx={1.6} fill="#000" />
      <rect x={29.6} y={182.8} width={18.8} height={2.2} rx={1.1} fill={c.url('bezel')} />
    </>
  );
}

const LEATHER_D = symPath(100, [50, 12], [
  [56, 12, 62, 8, 70, 8],
  [82, 8, 92, 14, 94, 28],
  [96, 50, 92, 72, 88, 92],
  [85, 108, 86, 124, 89, 140],
  [93, 162, 90, 184, 76, 192],
  [66, 198, 58, 198, 50, 198],
]);

/** Leather: the fob sewn into a stitched full-grain case (edge-painted rim, cream saddle stitch,
 *  riveted shoulders); the piano-black button column shows through a chrome-railed window. */
function Leather({ c }: { c: Ctx }) {
  return (
    <>
      <path d={LEATHER_D} fill="#000" opacity={0.55} transform="translate(0 5)" filter={c.url('shadowWide')} />
      <path d={LEATHER_D} fill="#000" opacity={0.7} transform="translate(0 1.4)" filter={c.url('soft')} />
      <path d={LEATHER_D} fill={c.url('leatherRich')} />
      <path d={LEATHER_D} fill={c.url('leatherGrain')} />
      <path d={LEATHER_D} fill={c.url('leatherShade')} />
      {/* painted edge with a soft lit roll on top */}
      <path d={LEATHER_D} fill="none" stroke="#140b06" strokeWidth={2.2} />
      <path d={LEATHER_D} fill="none" stroke="rgba(255,226,196,.16)" strokeWidth={0.7} transform={inner(100, 1.6)} />
      {/* saddle stitch: needle holes, then the thread */}
      <path d={LEATHER_D} fill="none" stroke="rgba(0,0,0,.55)" strokeWidth={1.1} strokeDasharray="2.2 1.6" transform={`translate(0 .4) ${inner(100, 5.2)}`} />
      <path d={LEATHER_D} fill="none" className="nz-fobart__thread" transform={inner(100, 5.2)} />
      {/* shoulder rivets */}
      {[24, 76].map((x) => (
        <g key={x}>
          <circle cx={x} cy={22.5} r={2.9} fill="#000" opacity={0.6} filter={c.url('soft')} />
          <circle cx={x} cy={22} r={2.6} fill={c.url('bezel')} />
          <circle cx={x} cy={22} r={2.6} fill="none" stroke={c.url('spec')} strokeWidth={0.5} />
        </g>
      ))}
      <CrownBadge c={c} x={50} y={32} r={12} />
      <Column c={c} x={32} y={54} w={36} h={124} r={16} />
      <Btn c={c} name="lock" x={50} y={71} shape={BTN(26, 21, 9)} tone="piano" />
      <Btn c={c} name="unlock" x={50} y={96} shape={BTN(26, 21, 9)} tone="piano" />
      <Btn c={c} name="trunk" x={50} y={121} shape={BTN(26, 21, 9)} tone="piano" />
      <Led c={c} x={50} y={137} w={8} h={1.6} />
      <Btn c={c} name="panic" x={50} y={155} shape={BTN(26, 21, 9)} tone="piano" />
    </>
  );
}

const COMPACT_D = symPath(88, [44, 40], [
  [58, 40, 76, 44, 80, 60],
  [84, 76, 82, 98, 78, 116],
  [75, 132, 80, 150, 78, 166],
  [76, 184, 62, 194, 44, 194],
]);

/** Compact: a small pebble fob on a woven teal strap held by a machined chrome clasp; 2x2 piano
 *  buttons in a chrome-railed well, crimson panic. */
function Compact({ c }: { c: Ctx }) {
  const loop = 'M34 42 V20 Q34 5 44 5 Q54 5 54 20 V42';
  return (
    <>
      {/* woven strap */}
      <path d={loop} fill="none" stroke="#000" strokeOpacity={0.5} strokeWidth={10} transform="translate(0 1.2)" filter={c.url('soft')} />
      <path d={loop} fill="none" stroke={c.url('strap')} strokeWidth={9} />
      <path d={loop} fill="none" stroke="rgba(0,0,0,.32)" strokeWidth={9} strokeDasharray=".8 1.4" />
      <path d={loop} fill="none" stroke="rgba(255,255,255,.18)" strokeWidth={0.6} transform="translate(-3.6 0)" />
      <path d={loop} fill="none" stroke="rgba(0,0,0,.45)" strokeWidth={0.6} transform="translate(3.6 0)" />
      <Shell c={c} d={COMPACT_D} w={88} inset={3.8} y0={40} h={154} />
      {/* chrome clasp */}
      <rect x={27} y={30.6} width={34} height={14} rx={4} fill="#000" opacity={0.6} filter={c.url('soft')} />
      <rect x={27} y={29} width={34} height={13} rx={4} fill={c.url('bezel')} />
      <rect x={27} y={29} width={34} height={13} rx={4} fill={c.url('bezelShade')} />
      <rect x={27} y={29} width={34} height={13} rx={4} fill="none" stroke={c.url('spec')} strokeWidth={0.6} />
      <rect x={32} y={33.2} width={24} height={3.4} rx={1.7} fill="#050506" />
      <CrownBadge c={c} x={44} y={64} r={10} />
      <Column c={c} x={20} y={86} w={48} h={84} r={14} />
      <Btn c={c} name="lock" x={32} y={107} shape={BTN(18, 32, 8)} tone="piano" iconScale={0.85} />
      <Btn c={c} name="unlock" x={56} y={107} shape={BTN(18, 32, 8)} tone="piano" iconScale={0.85} />
      <Btn c={c} name="trunk" x={32} y={149} shape={BTN(18, 32, 8)} tone="piano" iconScale={0.75} />
      <Btn c={c} name="panic" x={56} y={149} shape={BTN(18, 32, 8)} tone="piano" iconScale={0.75} />
      <Led c={c} x={44} y={180} w={8} h={1.6} />
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
