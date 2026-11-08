/**
 * Small drawings of the setup menu tiles: the livery swatch (number on a striped chip whose
 * stripe angle differs per livery, so neighbouring tiles read apart without pretending to
 * know the livery's colours), the extra's mini switch and the camera preset diagrams (the
 * car seen from above, a dot where the camera goes).
 */
import type { CSSProperties } from 'react';
import type { SetupView } from '@/lib/types';
import { Icon } from '@/components/ui';

const ANGLES = [35, 125, 70, 160, 15, 100, 55, 145];

export function LiverySwatch({ index, position }: { index: number; position: number }) {
  const text = index < 0 ? '–' : String(index + 1).padStart(2, '0');
  const style = { '--nz-setup-angle': `${ANGLES[position % ANGLES.length]}deg` } as CSSProperties;
  return (
    <span className="nz-setup__swatch" style={style} aria-hidden="true">
      <b>{text}</b>
    </span>
  );
}

export function MiniSwitch({ on }: { on: boolean }) {
  return (
    <span className={on ? 'nz-setup__switch is-on' : 'nz-setup__switch'} aria-hidden="true">
      <i />
    </span>
  );
}

/** Where the camera dot sits around the 12x20 car body (centre 14,12). */
const CAMERA_DOT: Record<Exclude<SetupView, 'reset' | 'top'>, [number, number]> = {
  front: [14, 1.6],
  rear: [14, 22.4],
  side: [2.4, 12],
};

export function ViewGlyph({ view }: { view: SetupView }) {
  if (view === 'reset') return <Icon name="refresh" size={18} strokeWidth={1.7} />;
  return (
    <svg className="nz-setup__view-glyph" width="28" height="24" viewBox="0 0 28 24" fill="none" aria-hidden="true">
      {/* car from above: body, windscreen, rear window */}
      <rect x="9" y="3.5" width="10" height="17" rx="3.2" stroke="currentColor" strokeWidth="1.4" />
      <path d="M10.6 8.2h6.8M11 16.4h6" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" opacity=".7" />
      {view === 'top' ? (
        <>
          <circle cx="14" cy="12" r="2.1" className="nz-setup__view-dot" />
          <circle cx="14" cy="12" r="4.6" stroke="currentColor" strokeWidth="1" strokeDasharray="1.6 1.8" className="nz-setup__view-ring" />
        </>
      ) : (
        <circle cx={CAMERA_DOT[view][0]} cy={CAMERA_DOT[view][1]} r="2" className="nz-setup__view-dot" />
      )}
    </svg>
  );
}
