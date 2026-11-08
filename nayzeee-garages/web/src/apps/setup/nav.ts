/**
 * Arrow-key navigation over the tile grid: from the focused tile, move to the nearest
 * enabled tile in the pressed direction (by screen position, so it works across sections
 * of different widths and rows that wrap).
 */
export type Dir = 'left' | 'right' | 'up' | 'down';

export const ARROWS: Record<string, Dir> = {
  ArrowLeft: 'left',
  ArrowRight: 'right',
  ArrowUp: 'up',
  ArrowDown: 'down',
};

const center = (r: DOMRect) => ({ x: r.left + r.width / 2, y: r.top + r.height / 2 });

/** Best tile from `from` toward `dir`, or null at the edge. */
export function nextTile(tiles: HTMLElement[], from: HTMLElement, dir: Dir): HTMLElement | null {
  const a = center(from.getBoundingClientRect());
  let best: HTMLElement | null = null;
  let bestScore = Infinity;
  for (const el of tiles) {
    if (el === from) continue;
    const b = center(el.getBoundingClientRect());
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const main = dir === 'left' ? -dx : dir === 'right' ? dx : dir === 'up' ? -dy : dy;
    const cross = dir === 'left' || dir === 'right' ? Math.abs(dy) : Math.abs(dx);
    if (main <= 4) continue; // not in that direction
    // Prefer the same row / column: sideways distance weighs three times as much.
    const score = main + cross * 3;
    if (score < bestScore) {
      bestScore = score;
      best = el;
    }
  }
  return best;
}
