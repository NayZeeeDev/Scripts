/**
 * Original key fob artwork (SVG), shared by the key ring, the fob HUD, the inspect cards and the
 * admin key manager. Placeholder API: the fob HUD track draws the designs.
 */
export type FobDesign = 'generic' | 'sport' | 'luxury' | 'classic' | 'leather' | 'compact' | 'key';

export interface FobArtProps {
  design?: FobDesign | string;
  /** 'key' = plain key (standard profile), 'fob' = electronic fob */
  kind?: 'key' | 'fob';
  /** pixel height; width follows the design's aspect */
  size?: number;
  /** highlight a button: 'lock' | 'unlock' | 'trunk' | 'panic' */
  active?: string | null;
  className?: string;
}

export function FobArt({ size = 120, className }: FobArtProps) {
  return <div className={className} style={{ width: size * 0.42, height: size }} />;
}
