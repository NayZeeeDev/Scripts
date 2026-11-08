/**
 * Garage zone geometry for the location editor (mirrors server/locations.lua, which decides).
 *
 * API
 * - ZONE_LIMITS                      the server's limits (corners, area, span, height, open gap).
 * - normalizeZone(raw)               a LocationZone from whatever Lua sent, or null (absent / invalid).
 * - zoneArea(points)                 m².
 * - zoneSize(points)                 { width, depth } of the bounding box in metres.
 * - zoneSpan(points)                 largest distance between two corners.
 * - zoneSelfIntersects(points)       two edges without a shared corner touch or cross.
 * - zoneDistance(points, x, y)       0 inside, else the distance to the nearest edge.
 * - zoneProblem(zone, openPoints)    the first reason the server would refuse it (translated) or null.
 * No React here.
 */
import { t } from '@/lib/i18n';
import type { InteractionPoint, LocationZone, ZonePoint } from '@/lib/types';

export const ZONE_LIMITS = {
  minPoints: 3,
  maxPoints: 40,
  minArea: 10,
  maxArea: 40000,
  maxSpan: 250,
  minHeight: 2,
  maxHeight: 100,
  openGap: 30,
  openZGap: 10,
} as const;

const EPS = 1e-9;
const num = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v);

export function normalizeZone(raw: unknown): LocationZone | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const src = raw as { points?: unknown; minZ?: unknown; maxZ?: unknown };
  if (!Array.isArray(src.points) || !num(src.minZ) || !num(src.maxZ) || src.maxZ <= src.minZ) return null;
  const points: ZonePoint[] = [];
  for (const p of src.points) {
    const q = p as { x?: unknown; y?: unknown } | null;
    if (q && num(q.x) && num(q.y)) points.push({ x: q.x, y: q.y });
  }
  if (points.length < ZONE_LIMITS.minPoints) return null;
  return { points, minZ: src.minZ, maxZ: src.maxZ };
}

export function zoneArea(points: ZonePoint[]): number {
  const n = points.length;
  if (n < 3) return 0;
  const o = points[0];
  let sum = 0;
  for (let i = 0; i < n; i++) {
    const a = points[i];
    const b = points[(i + 1) % n];
    sum += (a.x - o.x) * (b.y - o.y) - (b.x - o.x) * (a.y - o.y);
  }
  return Math.abs(sum) / 2;
}

export function zoneSize(points: ZonePoint[]): { width: number; depth: number } {
  if (!points.length) return { width: 0, depth: 0 };
  const xs = points.map((p) => p.x);
  const ys = points.map((p) => p.y);
  return { width: Math.max(...xs) - Math.min(...xs), depth: Math.max(...ys) - Math.min(...ys) };
}

export function zoneSpan(points: ZonePoint[]): number {
  let best = 0;
  for (let i = 0; i < points.length; i++) {
    for (let j = i + 1; j < points.length; j++) {
      best = Math.max(best, Math.hypot(points[i].x - points[j].x, points[i].y - points[j].y));
    }
  }
  return best;
}

const cross = (a: ZonePoint, b: ZonePoint, c: ZonePoint) => (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
const sign = (v: number) => (v > EPS ? 1 : v < -EPS ? -1 : 0);
const onSegment = (a: ZonePoint, b: ZonePoint, c: ZonePoint) =>
  c.x >= Math.min(a.x, b.x) - EPS && c.x <= Math.max(a.x, b.x) + EPS && c.y >= Math.min(a.y, b.y) - EPS && c.y <= Math.max(a.y, b.y) + EPS;

function segmentsIntersect(a: ZonePoint, b: ZonePoint, c: ZonePoint, d: ZonePoint): boolean {
  const d1 = sign(cross(c, d, a));
  const d2 = sign(cross(c, d, b));
  const d3 = sign(cross(a, b, c));
  const d4 = sign(cross(a, b, d));
  if (d1 * d2 < 0 && d3 * d4 < 0) return true;
  return (
    (d1 === 0 && onSegment(c, d, a)) || (d2 === 0 && onSegment(c, d, b)) || (d3 === 0 && onSegment(a, b, c)) || (d4 === 0 && onSegment(a, b, d))
  );
}

export function zoneSelfIntersects(points: ZonePoint[]): boolean {
  const n = points.length;
  if (n < 4) return false;
  for (let i = 0; i < n; i++) {
    for (let j = i + 2; j < n; j++) {
      if (i === 0 && j === n - 1) continue;
      if (segmentsIntersect(points[i], points[(i + 1) % n], points[j], points[(j + 1) % n])) return true;
    }
  }
  return false;
}

function inside(points: ZonePoint[], x: number, y: number): boolean {
  let hit = false;
  for (let i = 0, j = points.length - 1; i < points.length; j = i++) {
    const a = points[i];
    const b = points[j];
    if (a.y > y !== b.y > y && x < ((b.x - a.x) * (y - a.y)) / (b.y - a.y) + a.x) hit = !hit;
  }
  return hit;
}

function segmentDistance(x: number, y: number, a: ZonePoint, b: ZonePoint): number {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const len2 = dx * dx + dy * dy;
  const k = len2 > 0 ? Math.max(0, Math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / len2)) : 0;
  return Math.hypot(a.x + dx * k - x, a.y + dy * k - y);
}

export function zoneDistance(points: ZonePoint[], x: number, y: number): number {
  if (points.length < 3) return Infinity;
  if (inside(points, x, y)) return 0;
  let best = Infinity;
  for (let i = 0; i < points.length; i++) best = Math.min(best, segmentDistance(x, y, points[i], points[(i + 1) % points.length]));
  return best;
}

/** Same checks and wording as the server (server/locations.lua zoneConfig). */
export function zoneProblem(zone: LocationZone, openPoints: InteractionPoint[]): string | null {
  const L = ZONE_LIMITS;
  const pts = zone.points;
  if (pts.length < L.minPoints) return t('A garage zone needs at least 3 points');
  if (pts.length > L.maxPoints) return t('A garage zone can have at most {count} points', { count: L.maxPoints });
  if (zoneSpan(pts) > L.maxSpan) return t('The garage zone is too large (at most {size} m across)', { size: L.maxSpan });
  if (zoneSelfIntersects(pts)) return t('The edges of the garage zone cross each other');
  const area = zoneArea(pts);
  if (area < L.minArea) return t('The garage zone is too small');
  if (area > L.maxArea) return t('The garage zone is too large (at most {size} m², it is {area} m²)', { size: L.maxArea, area: Math.floor(area) });
  if (!openPoints.length) return t('Place an open interaction before drawing the garage zone');
  const height = zone.maxZ - zone.minZ;
  if (height < L.minHeight) return t('The garage zone must be at least {height} m high', { height: L.minHeight });
  if (height > L.maxHeight) return t('The garage zone can be at most {height} m high', { height: L.maxHeight });
  const near = openPoints.some(
    (p) => zoneDistance(pts, p.coords.x, p.coords.y) <= L.openGap && p.coords.z >= zone.minZ - L.openZGap && p.coords.z <= zone.maxZ + L.openZGap,
  );
  if (!near) return t('The garage zone must be at most {distance} m from an open interaction', { distance: L.openGap });
  return null;
}
