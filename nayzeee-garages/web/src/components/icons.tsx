/**
 * nayzeee-garages icon set — original 24×24 stroke icons (currentColor, 1.6 stroke,
 * round caps/joins) plus the vehicle silhouettes used by <VehicleImage> as a fallback.
 */
import type { ReactNode, SVGProps } from 'react';
import type { VehicleType } from '@/lib/types';

export type IconName =
  | 'car' | 'boat' | 'plane' | 'heli' | 'bike' | 'truck' | 'trailer' | 'garage' | 'search' | 'list' | 'grid' | 'walk'
  | 'close' | 'check' | 'checkCircle' | 'star' | 'starFilled' | 'wrench' | 'pin' | 'clock' | 'fuel' | 'engine'
  | 'shield' | 'transfer' | 'tag' | 'users' | 'user' | 'userPlus' | 'more' | 'chevronDown' | 'chevronUp'
  | 'chevronLeft' | 'chevronRight' | 'arrowRight' | 'arrowLeft' | 'plus' | 'minus' | 'edit' | 'trash' | 'ban'
  | 'lock' | 'unlock' | 'cog' | 'key' | 'camera' | 'door' | 'building' | 'impound' | 'briefcase' | 'import' | 'sort'
  | 'info' | 'warning' | 'money' | 'cart' | 'palette' | 'gauge' | 'spray' | 'wheel' | 'sparkle' | 'bulb' | 'sliders'
  | 'history' | 'crown' | 'eye' | 'eyeOff' | 'refresh' | 'map' | 'layers' | 'route' | 'link' | 'copy' | 'code'
  | 'calendar' | 'save' | 'logout' | 'sidebar' | 'filter' | 'hash' | 'percent' | 'receipt' | 'parking';

/* ── generated shapes ─────────────────────────────────────────────────── */

const r2 = (n: number) => Math.round(n * 100) / 100;
const polar = (r: number, deg: number): [number, number] => {
  const a = ((deg - 90) * Math.PI) / 180;
  return [r2(12 + r * Math.cos(a)), r2(12 + r * Math.sin(a))];
};

/** 8-tooth gear outline. */
const GEAR = (() => {
  const teeth = 8;
  const rOut = 9.3;
  const rIn = 7;
  let d = '';
  for (let i = 0; i < teeth; i++) {
    const a = (360 / teeth) * i;
    const p1 = polar(rIn, a - 14);
    const p2 = polar(rOut, a - 7.5);
    const p3 = polar(rOut, a + 7.5);
    const p4 = polar(rIn, a + 14);
    const n1 = polar(rIn, a + 360 / teeth - 14);
    d += `${i === 0 ? 'M' : 'L'}${p1[0]} ${p1[1]}L${p2[0]} ${p2[1]}L${p3[0]} ${p3[1]}L${p4[0]} ${p4[1]}`;
    d += `A${rIn} ${rIn} 0 0 1 ${n1[0]} ${n1[1]}`;
  }
  return `${d}Z`;
})();

/** 5 spokes between hub and rim. */
const SPOKES = Array.from({ length: 5 }, (_, i) => {
  const a = i * 72;
  const [x1, y1] = polar(2.1, a);
  const [x2, y2] = polar(5.6, a);
  return `M${x1} ${y1}L${x2} ${y2}`;
}).join('');

const dot = (cx: number, cy: number, r = 1.05) => <circle cx={cx} cy={cy} r={r} fill="currentColor" stroke="none" />;

const STAR = 'M12 3.6l2.55 5.2 5.7.82-4.13 4.03.98 5.68L12 16.65l-5.1 2.68.98-5.68-4.13-4.03 5.7-.82z';

/* ── icon bodies ──────────────────────────────────────────────────────── */

const ICONS: Record<IconName, ReactNode> = {
  car: (
    <>
      <path d="M5.2 11.2l1.5-3.9A2 2 0 0 1 8.57 6h6.86a2 2 0 0 1 1.87 1.3l1.5 3.9" />
      <path d="M3.5 13.2a2 2 0 0 1 2-2h13a2 2 0 0 1 2 2v3.3h-17z" />
      <path d="M5.5 16.5v2.2M18.5 16.5v2.2M7 13.9h1.6M15.4 13.9H17" />
    </>
  ),
  boat: (
    <>
      <path d="M2.8 14h18.4l-2.1 4.3a2 2 0 0 1-1.8 1.2H6.7a2 2 0 0 1-1.8-1.2z" />
      <path d="M6 14v-3.2a1 1 0 0 1 1-1h6.6L17 14" />
      <path d="M10.2 9.8V5.5M10.2 5.5l3.3 1.6" />
    </>
  ),
  plane: (
    <path d="M12 2.8c.75 0 1.35.62 1.35 1.4v5.15l7.15 4.15v1.95l-7.15-2.05v4.1l2.1 1.55v1.6L12 19.85l-3.45.85v-1.6l2.1-1.55v-4.1L3.5 15.6v-1.95l7.15-4.15V4.2c0-.78.6-1.4 1.35-1.4z" />
  ),
  heli: (
    <>
      <path d="M3.4 5.2h17.2M13.4 5.2v2.6" />
      <path d="M9.2 12.3a4.5 4.5 0 0 1 4.5-4.5h1.2a5.9 5.9 0 0 1 5.8 4.9l.1.5a1.5 1.5 0 0 1-1.5 1.8h-7.6a2.5 2.5 0 0 1-2.5-2.5z" />
      <path d="M9.3 11.1L4 10.3M4 8.4v3.9M10.4 19h9.6M12.7 15l-.5 4M17.7 15l.5 4" />
    </>
  ),
  bike: (
    <>
      <circle cx="5.6" cy="15.6" r="3.1" />
      <circle cx="18.4" cy="15.6" r="3.1" />
      <path d="M5.6 15.6l3.3-4.7h4.6l2.4 4.7" />
      <path d="M18.4 15.6L15.6 8h-2.1M7.6 10.9h3.2M15.6 8l1.9-.9" />
    </>
  ),
  truck: (
    <>
      <path d="M4.7 17H3.5a1 1 0 0 1-1-1V7.5a1 1 0 0 1 1-1h9a1 1 0 0 1 1 1V17M8.3 17h6.4" />
      <path d="M13.5 9.5h3.75a1 1 0 0 1 .78.37l2.72 3.38V16a1 1 0 0 1-1 1h-1.45M13.5 13h7" />
      <circle cx="6.5" cy="17" r="1.8" />
      <circle cx="16.5" cy="17" r="1.8" />
    </>
  ),
  trailer: (
    <>
      <path d="M8 15.6H3.6a1.1 1.1 0 0 1-1.1-1.1V7.6c0-.6.5-1.1 1.1-1.1h11.8c.6 0 1.1.5 1.1 1.1v6.9c0 .6-.5 1.1-1.1 1.1H12" />
      <circle cx="10" cy="16.4" r="2" />
      <path d="M16.5 13.4h3.4M19.9 13.4a1.25 1.25 0 1 0 1.3 0" />
    </>
  ),
  garage: (
    <>
      <path d="M3.2 20V9.6L12 4l8.8 5.6V20" />
      <path d="M7 20v-7.2a.8.8 0 0 1 .8-.8h8.4a.8.8 0 0 1 .8.8V20M7 15.2h10M7 17.8h10" />
    </>
  ),
  search: (
    <>
      <circle cx="10.8" cy="10.8" r="6.3" />
      <path d="M15.4 15.4l4.6 4.6" />
    </>
  ),
  list: (
    <>
      <path d="M9 6.5h11M9 12h11M9 17.5h11" />
      {dot(4.6, 6.5)}
      {dot(4.6, 12)}
      {dot(4.6, 17.5)}
    </>
  ),
  grid: (
    <>
      <rect x="3.6" y="3.6" width="7" height="7" rx="1.6" />
      <rect x="13.4" y="3.6" width="7" height="7" rx="1.6" />
      <rect x="3.6" y="13.4" width="7" height="7" rx="1.6" />
      <rect x="13.4" y="13.4" width="7" height="7" rx="1.6" />
    </>
  ),
  walk: (
    <>
      <circle cx="13.6" cy="4.6" r="1.7" />
      <path d="M12.7 8l-1.6 5.4 3 2.6.9 4.6M11.1 13.4l-2.2 2.9-1.6 4.3M12.4 9.2l-3 1.6-.8 2.5M12.6 9.2l2.2 2.6 2.6.9" />
    </>
  ),
  close: <path d="M6.5 6.5l11 11M17.5 6.5l-11 11" />,
  check: <path d="M4.8 12.6l4.4 4.4 10-10" />,
  checkCircle: (
    <>
      <circle cx="12" cy="12" r="8.8" />
      <path d="M8.2 12.3l2.6 2.6 5-5.1" />
    </>
  ),
  star: <path d={STAR} />,
  starFilled: <path d={STAR} fill="currentColor" />,
  wrench: (
    <path d="M14.9 4a4.6 4.6 0 0 0-4.5 6l-6.1 6.1a2.15 2.15 0 0 0 3 3.05l6.1-6.1a4.6 4.6 0 0 0 6-4.5l-2.75 2.75-2.6-.5-.5-2.6z" />
  ),
  pin: (
    <>
      <path d="M12 21s-6.6-5.6-6.6-11.1a6.6 6.6 0 0 1 13.2 0C18.6 15.4 12 21 12 21z" />
      <circle cx="12" cy="9.9" r="2.3" />
    </>
  ),
  clock: (
    <>
      <circle cx="12" cy="12" r="8.8" />
      <path d="M12 7.4V12l3 1.9" />
    </>
  ),
  fuel: (
    <>
      <path d="M4.8 20V5.4c0-.83.67-1.5 1.5-1.5h5.9c.83 0 1.5.67 1.5 1.5V20M3.4 20h11.7M4.8 10.2h8.9" />
      <path d="M13.7 8.4h1.9c.83 0 1.5.67 1.5 1.5v6.2a1.3 1.3 0 0 0 2.6 0V9.1l-2.4-2.5" />
    </>
  ),
  engine: (
    <>
      <path d="M6.2 9h2.4V7.1h5.8V9h2.2l1.8 2.2h1.9v4.6h-1.9L16.6 18H9.4l-2.1-2.3H6.2z" />
      <path d="M3.3 10.6v5.2M3.3 13.2h2.9M9.8 7.1V5.5h3.4v1.6" />
    </>
  ),
  shield: (
    <>
      <path d="M12 3.2l7.6 2.9v5.5c0 4.6-3.2 8.3-7.6 9.6-4.4-1.3-7.6-5-7.6-9.6V6.1z" />
      <path d="M8.9 12.2l2.2 2.2 4-4.1" />
    </>
  ),
  transfer: <path d="M4.2 8.3h14.6l-3.6-3.6M19.8 15.7H5.2l3.6 3.6" />,
  tag: (
    <>
      <path d="M3.6 11.9V4.6a1 1 0 0 1 1-1h7.3a1 1 0 0 1 .7.3l7.7 7.7a1.5 1.5 0 0 1 0 2.1l-6.9 6.9a1.5 1.5 0 0 1-2.1 0L3.9 12.6a1 1 0 0 1-.3-.7z" />
      <circle cx="8.1" cy="8.1" r="1.5" />
    </>
  ),
  users: (
    <>
      <circle cx="9" cy="8.3" r="3.3" />
      <path d="M2.9 19.6a6.1 6.1 0 0 1 12.2 0M15.6 5.1a3.3 3.3 0 0 1 0 6.4M17.6 14.1a6.1 6.1 0 0 1 3.5 5.5" />
    </>
  ),
  user: (
    <>
      <circle cx="12" cy="8.2" r="3.7" />
      <path d="M4.6 20a7.4 7.4 0 0 1 14.8 0" />
    </>
  ),
  userPlus: (
    <>
      <circle cx="10" cy="8.2" r="3.5" />
      <path d="M3.2 20a6.9 6.9 0 0 1 11.6-5M18.6 13.4v6M15.6 16.4h6" />
    </>
  ),
  more: (
    <>
      {dot(5.8, 12, 1.25)}
      {dot(12, 12, 1.25)}
      {dot(18.2, 12, 1.25)}
    </>
  ),
  chevronDown: <path d="M6.5 9.5l5.5 5.5 5.5-5.5" />,
  chevronUp: <path d="M6.5 14.5L12 9l5.5 5.5" />,
  chevronLeft: <path d="M14.5 6.5L9 12l5.5 5.5" />,
  chevronRight: <path d="M9.5 6.5L15 12l-5.5 5.5" />,
  arrowRight: <path d="M4.5 12h15M13.6 6.1l5.9 5.9-5.9 5.9" />,
  arrowLeft: <path d="M19.5 12h-15M10.4 6.1L4.5 12l5.9 5.9" />,
  plus: <path d="M12 5v14M5 12h14" />,
  minus: <path d="M5 12h14" />,
  edit: (
    <>
      <path d="M4 20h4.4L19.2 9.2a2.1 2.1 0 0 0 0-3l-1.4-1.4a2.1 2.1 0 0 0-3 0L4 15.6z" />
      <path d="M13.4 6.2l4.4 4.4M13 20h7" />
    </>
  ),
  trash: (
    <>
      <path d="M4.5 6.6h15M9.6 6.6V4.9c0-.55.45-1 1-1h2.8c.55 0 1 .45 1 1v1.7" />
      <path d="M6.4 6.6l.9 12.1a1.5 1.5 0 0 0 1.5 1.4h6.4a1.5 1.5 0 0 0 1.5-1.4l.9-12.1M10 10.6v5.6M14 10.6v5.6" />
    </>
  ),
  ban: (
    <>
      <circle cx="12" cy="12" r="8.8" />
      <path d="M5.8 5.8l12.4 12.4" />
    </>
  ),
  lock: (
    <>
      <rect x="4.8" y="10.4" width="14.4" height="10" rx="2.2" />
      <path d="M8.1 10.4V7.9a3.9 3.9 0 0 1 7.8 0v2.5M12 14.4v2.1" />
    </>
  ),
  unlock: (
    <>
      <rect x="4.8" y="10.4" width="14.4" height="10" rx="2.2" />
      <path d="M8.1 10.4V7.9a3.9 3.9 0 0 1 7.5-1.5M12 14.4v2.1" />
    </>
  ),
  cog: (
    <>
      <path d={GEAR} />
      <circle cx="12" cy="12" r="2.9" />
    </>
  ),
  key: (
    <>
      <circle cx="8" cy="15.8" r="3.9" />
      <path d="M10.8 13l8.6-8.6M16.6 7.2l2.4 2.4M14.3 9.5l1.9 1.9" />
    </>
  ),
  camera: (
    <>
      <path d="M4 8.6c0-.83.67-1.5 1.5-1.5h2.3l1.5-2.3h5.4l1.5 2.3h2.3c.83 0 1.5.67 1.5 1.5v9c0 .83-.67 1.5-1.5 1.5h-13c-.83 0-1.5-.67-1.5-1.5z" />
      <circle cx="12" cy="12.9" r="3.3" />
    </>
  ),
  door: (
    <>
      <path d="M5.5 20.2V4.8c0-.55.45-1 1-1h11c.55 0 1 .45 1 1v15.4M3.5 20.2h17" />
      <path d="M5.5 3.9l7.6 2.2c.53.15.9.64.9 1.2v12.9" />
      {dot(11.6, 13, 1)}
    </>
  ),
  building: (
    <>
      <path d="M4.5 20.3V4.9c0-.55.45-1 1-1h8.4c.55 0 1 .45 1 1v15.4M14.9 9.2h3.6c.55 0 1 .45 1 1v10.1M2.8 20.3h18.4" />
      <path d="M8 7.8h1M11.4 7.8h1M8 11.4h1M11.4 11.4h1M8 15h1M11.4 15h1M17.2 13h.01M17.2 16.4h.01" />
    </>
  ),
  impound: (
    <>
      <path d="M2.8 5.2h18.4v3.3H2.8z" />
      <path d="M6.8 5.2l-2 3.3M11.4 5.2l-2 3.3M16 5.2l-2 3.3M20.6 5.2l-2 3.3" />
      <path d="M6.8 14.4l1-2.5h8.4l1 2.5M5.3 14.4h13.4v3.4H5.3zM6.6 17.8v1.6M17.4 17.8v1.6" />
    </>
  ),
  briefcase: (
    <>
      <rect x="3.4" y="7.4" width="17.2" height="12.4" rx="2" />
      <path d="M9 7.4V5.6c0-.55.45-1 1-1h4c.55 0 1 .45 1 1v1.8M3.4 12.6h17.2M10.6 12.6v1.6h2.8v-1.6" />
    </>
  ),
  import: (
    <path d="M12 3.8v11M7.6 10.4l4.4 4.4 4.4-4.4M4 15.2v3.3c0 .83.67 1.5 1.5 1.5h13c.83 0 1.5-.67 1.5-1.5v-3.3" />
  ),
  sort: <path d="M7.2 4.6v14.8M3.8 16l3.4 3.4 3.4-3.4M16.8 19.4V4.6M13.4 8l3.4-3.4L20.2 8" />,
  info: (
    <>
      <circle cx="12" cy="12" r="8.8" />
      <path d="M12 10.9v5.6" />
      {dot(12, 7.9, 1.1)}
    </>
  ),
  warning: (
    <>
      <path d="M10.3 4.3L2.9 17.4a2 2 0 0 0 1.7 3h14.8a2 2 0 0 0 1.7-3L13.7 4.3a2 2 0 0 0-3.4 0z" />
      <path d="M12 9.6v4.4" />
      {dot(12, 17, 1.05)}
    </>
  ),
  money: (
    <>
      <rect x="2.6" y="6.2" width="18.8" height="11.6" rx="2" />
      <circle cx="12" cy="12" r="2.7" />
      <path d="M6.2 9.6v.01M17.8 14.4v.01" />
    </>
  ),
  cart: (
    <>
      <path d="M3 4.2h2.2l2.3 10.6h10.6l2-7.6H6.2" />
      <circle cx="9.2" cy="18.9" r="1.45" />
      <circle cx="16.6" cy="18.9" r="1.45" />
    </>
  ),
  palette: (
    <>
      <path d="M12 3.4a8.6 8.6 0 1 0 0 17.2c1.15 0 1.85-.8 1.85-1.8 0-.5-.2-.92-.52-1.27a1.7 1.7 0 0 1-.48-1.2c0-.98.8-1.73 1.8-1.73h2.05a3.9 3.9 0 0 0 3.9-3.9c0-4.03-3.85-7.3-8.6-7.3z" />
      {dot(7.6, 11.2)}
      {dot(9.4, 7.6)}
      {dot(13.8, 6.9)}
      {dot(16.9, 9.7)}
    </>
  ),
  gauge: (
    <>
      <path d="M4.3 17.6a8.7 8.7 0 1 1 15.4 0" />
      <path d="M12 13.6l3.7-4.1M7.4 12.8h.01M12 8.2h.01M16.6 12.8h.01" />
      <circle cx="12" cy="13.6" r="1.5" />
    </>
  ),
  spray: (
    <>
      <path d="M7.6 9.6h6.8c.55 0 1 .45 1 1v9.2c0 .55-.45 1-1 1H7.6c-.55 0-1-.45-1-1v-9.2c0-.55.45-1 1-1zM8.6 9.6V7.2h4.8v2.4M10 7.2V4.6h2.9M6.6 13.6h8.8" />
      {dot(17.4, 4.6, .9)}
      {dot(19.6, 3.4, .9)}
      {dot(19.6, 6.4, .9)}
      {dot(17.4, 7.8, .9)}
    </>
  ),
  wheel: (
    <>
      <circle cx="12" cy="12" r="8.9" />
      <circle cx="12" cy="12" r="5.6" />
      <circle cx="12" cy="12" r="2.1" />
      <path d={SPOKES} />
    </>
  ),
  sparkle: (
    <>
      <path d="M11 3.6c.55 4 2.5 6 6.5 6.5-4 .55-5.95 2.5-6.5 6.5-.55-4-2.5-5.95-6.5-6.5 4-.55 5.95-2.5 6.5-6.5z" />
      <path d="M18.2 15.6v4.6M15.9 17.9h4.6" />
    </>
  ),
  bulb: (
    <>
      <path d="M8.7 14.6a6 6 0 1 1 6.6 0c-.6.45-.9 1.1-.9 1.85v.65H9.6v-.65c0-.75-.3-1.4-.9-1.85z" />
      <path d="M9.6 19.6h4.8M12 9v3.2" />
    </>
  ),
  sliders: (
    <>
      <path d="M4 7.5h7.5M16.5 7.5H20M4 16.5h3.5M12.5 16.5H20" />
      <circle cx="14" cy="7.5" r="2.5" />
      <circle cx="10" cy="16.5" r="2.5" />
    </>
  ),
  history: (
    <>
      <path d="M3.8 12.2a8.4 8.4 0 1 0 2.4-6.1L3.8 8.5" />
      <path d="M3.8 4.3v4.2H8M12 7.9v4.3l2.9 1.8" />
    </>
  ),
  crown: (
    <>
      <path d="M4.1 17.2L3 7.6l5 3.9L12 5.4l4 6.1 5-3.9-1.1 9.6z" />
      <path d="M4.6 20.4h14.8" />
    </>
  ),
  eye: (
    <>
      <path d="M2.6 12S6 5.6 12 5.6 21.4 12 21.4 12 18 18.4 12 18.4 2.6 12 2.6 12z" />
      <circle cx="12" cy="12" r="2.9" />
    </>
  ),
  eyeOff: (
    <>
      <path d="M10.5 5.75A9.5 9.5 0 0 1 12 5.6c6 0 9.4 6.4 9.4 6.4a17 17 0 0 1-2.5 3.3M6.6 7.3C4.1 9 2.6 12 2.6 12s3.4 6.4 9.4 6.4c1.6 0 3-.45 4.2-1.1" />
      <path d="M9.95 9.95a2.9 2.9 0 0 0 4.1 4.1M3.6 3.6l16.8 16.8" />
    </>
  ),
  refresh: (
    <>
      <path d="M19.6 12.4a7.6 7.6 0 1 1-2.25-5.8l2.25 2.2" />
      <path d="M19.6 4.2v4.6H15" />
    </>
  ),
  map: (
    <>
      <path d="M9 4.6L3.6 6.6v12.8L9 17.4l6 2 5.4-2V4.6L15 6.6z" />
      <path d="M9 4.6v12.8M15 6.6v12.8" />
    </>
  ),
  layers: (
    <>
      <path d="M12 3.6l8.8 4.5L12 12.6 3.2 8.1z" />
      <path d="M3.2 12.1l8.8 4.5 8.8-4.5M3.2 16l8.8 4.5 8.8-4.5" />
    </>
  ),
  route: (
    <>
      <circle cx="6.2" cy="18.3" r="2.1" />
      <circle cx="17.8" cy="5.7" r="2.1" />
      <path d="M8.3 18.3h8.1a3.15 3.15 0 0 0 0-6.3H7.6a3.15 3.15 0 0 1 0-6.3h8.1" />
    </>
  ),
  link: (
    <path d="M10.2 13.8a4 4 0 0 0 5.65 0l2.9-2.9a4 4 0 0 0-5.65-5.65l-1 1M13.8 10.2a4 4 0 0 0-5.65 0l-2.9 2.9a4 4 0 0 0 5.65 5.65l1-1" />
  ),
  copy: (
    <>
      <rect x="8.6" y="8.6" width="11.8" height="11.8" rx="2" />
      <path d="M15.4 8.6V5.1c0-.83-.67-1.5-1.5-1.5H5.1c-.83 0-1.5.67-1.5 1.5v8.8c0 .83.67 1.5 1.5 1.5h3.5" />
    </>
  ),
  code: <path d="M8.4 7.2L3.6 12l4.8 4.8M15.6 7.2l4.8 4.8-4.8 4.8M13.5 4.6l-3 14.8" />,
  calendar: (
    <>
      <rect x="3.6" y="5" width="16.8" height="15.4" rx="2.4" />
      <path d="M3.6 10h16.8M8 3.2v3.6M16 3.2v3.6M7.8 13.6h.01M12 13.6h.01M16.2 13.6h.01M7.8 16.8h.01M12 16.8h.01" />
    </>
  ),
  save: (
    <>
      <path d="M5.1 3.6h11.3l4 4v11.3c0 .83-.67 1.5-1.5 1.5H5.1c-.83 0-1.5-.67-1.5-1.5V5.1c0-.83.67-1.5 1.5-1.5z" />
      <path d="M7.6 3.6v4.2h7.2V3.6M7.2 20.4v-5.6c0-.55.45-1 1-1h7.6c.55 0 1 .45 1 1v5.6" />
    </>
  ),
  logout: (
    <path d="M9.6 20H6c-.83 0-1.5-.67-1.5-1.5v-13C4.5 4.67 5.17 4 6 4h3.6M15.6 16.4L20 12l-4.4-4.4M20 12H9.6" />
  ),
  sidebar: (
    <>
      <rect x="3.4" y="4.4" width="17.2" height="15.2" rx="2.2" />
      <path d="M9.4 4.4v15.2M5.8 8h1.4M5.8 11h1.4" />
    </>
  ),
  filter: <path d="M3.8 5h16.4l-6.3 7.4v5.9l-3.8 1.9v-7.8z" />,
  hash: <path d="M9.6 3.8l-1.9 16.4M16.3 3.8l-1.9 16.4M4.6 9h15.6M3.8 15h15.6" />,
  percent: (
    <>
      <path d="M18.6 5.4L5.4 18.6" />
      <circle cx="7.2" cy="7.2" r="2.3" />
      <circle cx="16.8" cy="16.8" r="2.3" />
    </>
  ),
  receipt: (
    <>
      <path d="M5.6 3.6h12.8v17.2l-2.15-1.45-2.1 1.45-2.15-1.45-2.15 1.45-2.1-1.45-2.15 1.45z" />
      <path d="M9 8.2h6M9 11.6h6M9 15h3.6" />
    </>
  ),
  parking: (
    <>
      <rect x="3.6" y="3.6" width="16.8" height="16.8" rx="3.6" />
      <path d="M9.8 16.8V7.4h3.3a2.8 2.8 0 0 1 0 5.6H9.8" />
    </>
  ),
};

/** Every icon name, in declaration order (used by the kit gallery). */
export const ICON_NAMES = Object.keys(ICONS) as IconName[];

export interface IconProps extends Omit<SVGProps<SVGSVGElement>, 'name'> {
  name: IconName;
  size?: number;
  strokeWidth?: number;
  className?: string;
}

export function Icon({ name, size = 16, strokeWidth = 1.6, className, ...rest }: IconProps) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill="none"
      stroke="currentColor"
      strokeWidth={strokeWidth}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className ? `nz-icon ${className}` : 'nz-icon'}
      aria-hidden="true"
      focusable="false"
      {...rest}
    >
      {ICONS[name] ?? ICONS.info}
    </svg>
  );
}

/* ═══════════════════════ vehicle silhouettes ═══════════════════════ */

export type SilhouetteKind = 'car' | 'boat' | 'plane' | 'heli';

const HELI_MODELS = [
  'heli', 'buzzard', 'maverick', 'frogger', 'swift', 'supervolito', 'valkyrie', 'savage', 'annihilator',
  'cargobob', 'polmav', 'havok', 'seasparrow', 'akula', 'hunter', 'skylift', 'volatus', 'conada', 'sparrow',
];

/** Picks the silhouette for a vehicle type (air → helicopter when the model name says so). */
export function silhouetteFor(vehicleType: VehicleType, model?: string | null): SilhouetteKind {
  if (vehicleType === 'sea') return 'boat';
  if (vehicleType === 'air') {
    const m = (model ?? '').toLowerCase();
    return HELI_MODELS.some((h) => m.includes(h)) ? 'heli' : 'plane';
  }
  return 'car';
}

/** Soft, original side-profile silhouettes (viewBox 240×110). Colours come from CSS. */
export function VehicleSilhouette({ kind, className }: { kind: SilhouetteKind; className?: string }) {
  return (
    <svg viewBox="0 0 240 110" className={className ? `nz-sil ${className}` : 'nz-sil'} aria-hidden="true" focusable="false">
      <ellipse className="nz-sil__shadow" cx="120" cy="96" rx="96" ry="5" />
      {kind === 'car' && (
        <g>
          <path
            className="nz-sil__body"
            d="M24 80L20 67Q19 58 30 56L58 51Q76 35 99 32L139 31Q154 31 168 41L183 52Q211 55 219 61Q225 66 223 76L221 80H199A19 19 0 0 0 161 80H79A19 19 0 0 0 41 80Z"
          />
          <path className="nz-sil__glass" d="M68 52Q82 39 99 37L121 36.5V52Z" />
          <path className="nz-sil__glass" d="M127 36.5H138Q150 36.5 160 44L167 52H127Z" />
          <path className="nz-sil__line" d="M30 64H214M124 52V77" />
          <path className="nz-sil__lamp" d="M210 61.5L220 64.5" />
          <circle className="nz-sil__wheel" cx="60" cy="80" r="14.5" />
          <circle className="nz-sil__wheel" cx="180" cy="80" r="14.5" />
          <circle className="nz-sil__hub" cx="60" cy="80" r="5.5" />
          <circle className="nz-sil__hub" cx="180" cy="80" r="5.5" />
        </g>
      )}
      {kind === 'boat' && (
        <g>
          <path className="nz-sil__body" d="M16 60H192L230 52L210 82Q206 88 197 88H38Q27 88 24 80Z" />
          <path className="nz-sil__body" d="M72 60L82 41Q85 36 92 36H146L170 60Z" />
          <path className="nz-sil__glass" d="M138 41H146L161 57H138Z" />
          <path className="nz-sil__glass" d="M88 44Q90 41 94 41H130V57H82Z" />
          <path className="nz-sil__line" d="M28 70H204M112 36V28H122" />
          <path className="nz-sil__wave" d="M8 98Q20 93 32 98T56 98T80 98T104 98T128 98T152 98T176 98T200 98T224 98" />
        </g>
      )}
      {kind === 'plane' && (
        <g>
          <path className="nz-sil__body" d="M30 49L14 18H31L62 46Z" />
          <path className="nz-sil__body" d="M20 54Q22 46 34 46H190Q218 46 230 56Q222 66 196 66H42Q27 66 20 58Z" />
          <path className="nz-sil__body" d="M96 60H140L114 88H100Z" />
          <rect className="nz-sil__body" x="104" y="66" width="28" height="10" rx="5" />
          <path className="nz-sil__glass" d="M202 50H215L223 56H206Z" />
          <path className="nz-sil__line" d="M24 59L8 63H22L44 60" />
          {[66, 78, 90, 102, 150, 162, 174, 186].map((x) => (
            <circle key={x} className="nz-sil__window" cx={x} cy="53.5" r="2.2" />
          ))}
        </g>
      )}
      {kind === 'heli' && (
        <g>
          <path className="nz-sil__line" d="M30 22H230M138 22V31" />
          <path className="nz-sil__body" d="M104 44Q104 31 118 31H150Q180 31 191 53Q195 67 179 69H122Q104 69 104 56Z" />
          <path className="nz-sil__body" d="M106 46L34 52V57L106 61Z" />
          <path className="nz-sil__body" d="M30 55L22 36H32L40 54Z" />
          <circle className="nz-sil__line" cx="27" cy="51" r="11" />
          <path className="nz-sil__glass" d="M156 36Q177 38 185 54H156Z" />
          <path className="nz-sil__line" d="M110 86H190Q198 86 200 80M126 69L122 86M172 69L176 86" />
        </g>
      )}
    </svg>
  );
}
