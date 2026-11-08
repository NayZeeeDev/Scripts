/**
 * ZoneSection — the "Garage zone" block of the location editor.
 *
 * API
 *   <ZoneSection zone openPoints spawnPoints busy disabled flash? error? notes? onDraw onClear />
 *   - zone: the draft's LocationZone, or null (point-based location).
 *   - onDraw(): starts the in-world zone tool (LocationEditor → requestPoints({ kind: 'zone' })).
 *     It is offered as "Draw zone" without a zone and "Redraw" with one (the old outline is
 *     shown grey in the world while drawing).
 *   - onClear(): removes the zone from the draft (saved with the location).
 *   - notes: extra explanations under the card (store interactions unused, target mode, …).
 *
 * Card: a top-down preview (north up, the zone with its corners, open interactions as teal
 * rings, spawn points as white ticks pointing the spawn heading, fitted to the shape), then
 * corners / area / size / height and the actions. Without an open interaction the tool cannot
 * run (the server measures the zone from it): the button is disabled with the reason.
 */
import { useMemo } from 'react';
import { Button, Icon, InfoDot, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { InteractionPoint, LocationZone, Vec4 } from '@/lib/types';
import { zoneArea, zoneSize } from './zone';
import './zone.css';

export interface ZoneSectionProps {
  zone: LocationZone | null;
  openPoints: InteractionPoint[];
  spawnPoints: Vec4[];
  busy: boolean;
  disabled: boolean;
  /** Just changed by the in-world tool. */
  flash?: boolean;
  error?: string;
  notes?: string[];
  onDraw: () => void;
  onClear: () => void;
}

const VIEW_W = 220;
const VIEW_H = 148;
const PAD = 16;
/** Reference points farther than this from the zone are left out of the preview framing. */
const NEAR = 90;

const nf = (n: number, digits = 0) => n.toLocaleString(undefined, { minimumFractionDigits: digits, maximumFractionDigits: digits });

function Preview({ zone, openPoints, spawnPoints }: { zone: LocationZone; openPoints: InteractionPoint[]; spawnPoints: Vec4[] }) {
  const shape = useMemo(() => {
    const pts = zone.points;
    const cx0 = pts.reduce((s, p) => s + p.x, 0) / pts.length;
    const cy0 = pts.reduce((s, p) => s + p.y, 0) / pts.length;
    const near = (x: number, y: number) => Math.hypot(x - cx0, y - cy0) <= NEAR;
    const opens = openPoints.map((p) => p.coords).filter((c) => near(c.x, c.y));
    const spawns = spawnPoints.filter((s) => near(s.x, s.y));
    const xs = [...pts.map((p) => p.x), ...opens.map((c) => c.x), ...spawns.map((s) => s.x)];
    const ys = [...pts.map((p) => p.y), ...opens.map((c) => c.y), ...spawns.map((s) => s.y)];
    const minX = Math.min(...xs);
    const maxX = Math.max(...xs);
    const minY = Math.min(...ys);
    const maxY = Math.max(...ys);
    const k = Math.min((VIEW_W - PAD * 2) / Math.max(maxX - minX, 1), (VIEW_H - PAD * 2) / Math.max(maxY - minY, 1));
    const ox = (VIEW_W - (maxX - minX) * k) / 2;
    const oy = (VIEW_H - (maxY - minY) * k) / 2;
    // north up: world y grows upwards, SVG y downwards
    const at = (x: number, y: number) => ({ x: ox + (x - minX) * k, y: oy + (maxY - y) * k });
    return {
      poly: pts.map((p) => at(p.x, p.y)),
      opens: opens.map((c) => at(c.x, c.y)),
      spawns: spawns.map((s) => ({ ...at(s.x, s.y), w: s.w })),
      grid: Math.max(6, 10 * k),
    };
  }, [zone, openPoints, spawnPoints]);

  const d = shape.poly.map((p, i) => `${i ? 'L' : 'M'}${p.x.toFixed(1)} ${p.y.toFixed(1)}`).join(' ') + ' Z';
  return (
    <svg
      className="nz-admin-zone__svg"
      viewBox={`0 0 ${VIEW_W} ${VIEW_H}`}
      preserveAspectRatio="xMidYMid slice"
      role="img" aria-label={t('Top-down preview of the garage zone')}>
      <defs>
        <pattern id="nz-zone-grid" width={shape.grid} height={shape.grid} patternUnits="userSpaceOnUse">
          <path d={`M ${shape.grid} 0 L 0 0 0 ${shape.grid}`} className="nz-admin-zone__grid" />
        </pattern>
      </defs>
      <rect width={VIEW_W} height={VIEW_H} fill="url(#nz-zone-grid)" />
      <path d={d} className="nz-admin-zone__shape" />
      {shape.poly.map((p, i) => (
        <circle key={i} cx={p.x} cy={p.y} r={2.4} className="nz-admin-zone__corner" />
      ))}
      {shape.spawns.map((s, i) => (
        // heading: GTA 0° = north, counter-clockwise; SVG rotates clockwise
        <g key={`s${i}`} transform={`translate(${s.x.toFixed(1)} ${s.y.toFixed(1)}) rotate(${(-s.w).toFixed(1)})`} className="nz-admin-zone__spawn">
          <path d="M0 -4 L2.7 2.9 L0 1.4 L-2.7 2.9 Z" />
        </g>
      ))}
      {shape.opens.map((o, i) => (
        <g key={`o${i}`} className="nz-admin-zone__open">
          <circle cx={o.x} cy={o.y} r={5.5} />
          <circle cx={o.x} cy={o.y} r={1.8} className="is-dot" />
        </g>
      ))}
      <path d={`M${VIEW_W - 16} 13 L${VIEW_W - 12} 6 L${VIEW_W - 8} 13`} className="nz-admin-zone__north-arrow" />
      <text x={VIEW_W - 12} y={23} className="nz-admin-zone__north" textAnchor="middle">
        {t('N')}
      </text>
    </svg>
  );
}

export function ZoneSection({ zone, openPoints, spawnPoints, busy, disabled, flash, error, notes, onDraw, onClear }: ZoneSectionProps) {
  const noOpen = openPoints.length === 0;
  const stats = useMemo(() => {
    if (!zone) return null;
    const size = zoneSize(zone.points);
    return {
      corners: zone.points.length,
      area: zoneArea(zone.points),
      width: size.width,
      depth: size.depth,
      height: zone.maxZ - zone.minZ,
    };
  }, [zone]);

  return (
    <div className="nz-admin-zone" data-invalid={!!error}>
      <div className={cx('nz-admin-zone__card', !zone && 'is-empty', error && 'is-invalid', flash && 'is-updated')}>
        <div className="nz-admin-zone__preview">
          {zone ? (
            <Preview zone={zone} openPoints={openPoints} spawnPoints={spawnPoints} />
          ) : (
            <div className="nz-admin-zone__placeholder">
              <svg viewBox="0 0 60 44" aria-hidden="true" className="nz-admin-zone__placeholder-art">
                <path d="M8 30 L18 8 L44 6 L54 26 L34 38 Z" />
              </svg>
              <span>{t('No zone')}</span>
            </div>
          )}
        </div>

        <div className="nz-admin-zone__body">
          <div className="nz-admin-zone__head">
            <span className="nz-admin-zone__title">
              <b>{zone ? t('Zone drawn') : t('Point-based')}</b>
              <InfoDot
                text={t(
                  'Inside the zone players open the menu and park the vehicle they drive anywhere, no store circle needed. Without a zone the open and store interactions are used.',
                )}
              />
            </span>
            {zone && <span className="nz-admin-zone__tag">{t('Active')}</span>}
          </div>

          {stats ? (
            <dl className="nz-admin-zone__stats">
              <div>
                <dt>{t('Corners')}</dt>
                <dd>{stats.corners}</dd>
              </div>
              <div>
                <dt>{t('Area')}</dt>
                <dd>
                  {nf(stats.area)} <small>{t('m²')}</small>
                </dd>
              </div>
              <div>
                <dt>{t('Size')}</dt>
                <dd>
                  {nf(stats.width)} × {nf(stats.depth)} <small>{t('m')}</small>
                </dd>
              </div>
              <div>
                <dt>{t('Height')}</dt>
                <dd title={`${nf(zone!.minZ, 1)} – ${nf(zone!.maxZ, 1)}`}>
                  {nf(stats.height, 1)} <small>{t('m')}</small>
                </dd>
              </div>
            </dl>
          ) : (
            <p className="nz-admin-zone__empty">
              {noOpen
                ? t('Place an open interaction first: the zone is drawn around the garage.')
                : t('Draw the parking area in the world: walk or fly, place the corners, then set the height.')}
            </p>
          )}

          <div className="nz-admin-zone__actions">
            <Button
              size="sm"
              variant={zone ? 'line' : 'white'}
              icon={zone ? 'refresh' : 'route'}
              loading={busy}
              disabled={(disabled && !busy) || noOpen}
              title={noOpen ? t('Place an open interaction first') : undefined}
              onClick={onDraw}
            >
              {zone ? t('Redraw') : t('Draw zone')}
            </Button>
            {zone && (
              <Button size="sm" variant="ghost" icon="trash" disabled={disabled} onClick={onClear}>
                {t('Clear')}
              </Button>
            )}
          </div>
        </div>
      </div>

      {error && (
        <span className="nz-admin-form__error" role="alert">
          <Icon name="warning" size={12} strokeWidth={1.8} />
          {error}
        </span>
      )}
      {notes?.map((n) => (
        <p key={n} className="nz-admin-form__hint is-block nz-admin-zone__note">
          <Icon name="info" size={12} strokeWidth={1.8} />
          {n}
        </p>
      ))}
    </div>
  );
}
