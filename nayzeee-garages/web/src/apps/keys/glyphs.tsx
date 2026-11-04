/**
 * Key ring glyphs the kit has no icon for (key fob, siren, tracker signal), drawn in the kit's
 * icon style: 24px grid, round 1.6 strokes, currentColor. Plus KindGlyph, which picks the glyph of
 * a key kind (kit icons for key / clock / link).
 */
import type { ReactNode } from 'react';
import { Icon } from '@/components/ui';
import type { Glyph } from './model';

interface GlyphProps {
  size?: number;
  strokeWidth?: number;
  className?: string;
}

function Svg({ size = 16, strokeWidth = 1.6, className, children }: GlyphProps & { children: ReactNode }) {
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
    >
      {children}
    </svg>
  );
}

/** Remote key fob: rounded body, two buttons, key ring, radio waves. */
export function FobGlyph(props: GlyphProps) {
  return (
    <Svg {...props}>
      <rect x="6.5" y="8" width="9" height="13" rx="3.2" />
      <circle cx="11" cy="12.4" r="1.25" />
      <circle cx="11" cy="16.6" r="1.25" />
      <path d="M11 8V5.6a1.6 1.6 0 1 1 1.6 1.6" />
      <path d="M18.2 6.2a4.2 4.2 0 0 1 0 5.6" />
      <path d="M20.4 4.2a7.2 7.2 0 0 1 0 9.6" />
    </Svg>
  );
}

/** Alarm: a siren dome on its base with light rays. */
export function SirenGlyph(props: GlyphProps) {
  return (
    <Svg {...props}>
      <path d="M7 17v-4.5a5 5 0 0 1 10 0V17" />
      <path d="M5 17h14v3H5z" />
      <path d="M12 3v2" />
      <path d="M4.2 6.2l1.4 1.4" />
      <path d="M19.8 6.2l-1.4 1.4" />
      <path d="M10 12.5a2 2 0 0 1 2-2" />
    </Svg>
  );
}

/** Tracker: a crosshair over a pulse ring. */
export function SignalGlyph(props: GlyphProps) {
  return (
    <Svg {...props}>
      <circle cx="12" cy="12" r="3" />
      <circle cx="12" cy="12" r="7.5" opacity=".55" />
      <path d="M12 2.5v3" />
      <path d="M12 18.5v3" />
      <path d="M2.5 12h3" />
      <path d="M18.5 12h3" />
    </Svg>
  );
}

/** Glyph of a key kind. */
export function KindGlyph({ glyph, size = 13, strokeWidth = 1.8, className }: GlyphProps & { glyph: Glyph }) {
  if (glyph === 'fob') return <FobGlyph size={size} strokeWidth={strokeWidth} className={className} />;
  const name = glyph === 'clock' ? 'clock' : glyph === 'link' ? 'link' : 'key';
  return <Icon name={name} size={size} strokeWidth={strokeWidth} className={className} />;
}
