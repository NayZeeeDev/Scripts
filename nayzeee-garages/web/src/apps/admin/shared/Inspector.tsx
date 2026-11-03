/**
 * Inspector — details + actions of the selected location, sliding over the bottom of the map.
 *
 *   <Inspector loc kindLabel facts factsTitle stats owners? showOwners? onRetryOwners?
 *              capacity? capacityMeter? spawner? busy
 *              onClose onEdit onTeleport onPoints(kind) onToggle onDelete />
 *
 * Header: type tile, name + mono #id, "kind · vehicle type · 1 open · 4 spawn", the anchor
 * coordinates (mono, copy button), state badge, close (×).
 * Sections: the page's kind section (facts), OWNERS (private: owned copies), VEHICLES (parked /
 * out / impounded or held; spawner locations explain that their vehicles are not stored; a
 * capacity meter when the location has a total limit).
 * Action bar: Edit (teal, Enter), Teleport, Points ▾ (in-world manager), Enable/Disable,
 * Delete (red). These replace the old per-row icon buttons.
 */
import { forwardRef, useEffect, useState } from 'react';
import type { CSSProperties } from 'react';
import { Avatar, Badge, Button, Icon, IconButton, Kbd, Menu, Skeleton, cx } from '@/components/ui';
import type { MenuItem } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { CapacityConfig, GroupInfo, Location, LocationStats } from '@/lib/types';
import type { Fact } from './commandTypes';
import { copyText } from './clipboard';
import { formatCoord } from './mapGeo';
import { capacityLabel, locationAnchor, plural, vehicleTypeIcon, vehicleTypeLabel } from './labels';

export type PointKind = 'spawn' | 'open' | 'store';
export type InspectorBusy = 'toggle' | 'teleport' | 'points' | null;

export interface InspectorProps {
  loc: Location;
  kindLabel: string;
  facts: Fact[];
  factsTitle: string;
  stats: LocationStats;
  /** Private locations: owned copies (undefined = loading, 'error' = failed). */
  owners?: GroupInfo[] | 'error' | undefined;
  showOwners?: boolean;
  onRetryOwners?: () => void;
  capacity?: CapacityConfig;
  /** Show "x of y spaces used" when the capacity is a total limit (not for private copies). */
  capacityMeter?: boolean;
  /** Spawner locations: number of vehicle models (their vehicles are never stored here). */
  spawner?: number | null;
  busy: InspectorBusy;
  onClose: () => void;
  onEdit: () => void;
  onTeleport: () => void;
  onPoints: (kind: PointKind) => void;
  onToggle: () => void;
  onDelete: () => void;
}

const fmt = (n: number) => n.toLocaleString('en-US');

export const Inspector = forwardRef<HTMLElement, InspectorProps>(function Inspector(
  {
    loc,
    kindLabel,
    facts,
    factsTitle,
    stats,
    owners,
    showOwners = false,
    onRetryOwners,
    capacity,
    capacityMeter = true,
    spawner = null,
    busy,
    onClose,
    onEdit,
    onTeleport,
    onPoints,
    onToggle,
    onDelete,
  },
  ref,
) {
  const anchor = locationAnchor(loc);
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    if (!copied) return;
    const id = window.setTimeout(() => setCopied(false), 1400);
    return () => window.clearTimeout(id);
  }, [copied]);
  useEffect(() => setCopied(false), [loc.id]);

  const copy = () => {
    if (!anchor) return;
    if (copyText(`${anchor.x.toFixed(2)}, ${anchor.y.toFixed(2)}, ${anchor.z.toFixed(2)}`)) setCopied(true);
  };

  const isImpound = loc.kind === 'impound';
  const storesAtOpen = isImpound || loc.useOpenForStore;
  const pointItems: MenuItem[] = [
    { label: t('Open interactions'), icon: 'pin', hint: String(loc.openPoints.length), onSelect: () => onPoints('open') },
    ...(storesAtOpen
      ? []
      : [{ label: t('Store interactions'), icon: 'parking' as const, hint: String(loc.storePoints.length), onSelect: () => onPoints('store') }]),
    { label: t('Spawn points'), icon: 'car', hint: String(loc.spawnPoints.length), onSelect: () => onPoints('spawn') },
  ];

  const total = capacityMeter && capacity && capacity.mode === 'limited' && capacity.appliesTo === 'total' ? capacity.spaces : null;
  const used = stats.parked;
  const vehicles = stats.parked + stats.out + stats.impounded;

  const points = [
    plural(loc.openPoints.length, '{count} open point', '{count} open points'),
    ...(storesAtOpen ? [] : [plural(loc.storePoints.length, '{count} store point', '{count} store points')]),
    plural(loc.spawnPoints.length, '{count} spawn', '{count} spawns'),
  ].join(' · ');

  return (
    <section ref={ref} className={cx('nz-admin-cmd__insp', !loc.enabled && 'is-off')} aria-label={t('Selected location')}>
      <header className="nz-admin-cmd__insp-head">
        <span className={cx('nz-admin-cmd__type', 'is-lg', `is-${loc.enabled ? loc.vehicleType : 'off'}`)}>
          <Icon name={vehicleTypeIcon(loc.vehicleType)} size={19} strokeWidth={1.6} />
        </span>
        <div className="nz-admin-cmd__insp-title">
          <h2>
            <span title={loc.name}>{loc.name}</span>
            {loc.id !== null && <small>#{loc.id}</small>}
          </h2>
          <p title={points}>
            {kindLabel} <i>·</i> {vehicleTypeLabel(loc.vehicleType)} <i>·</i> {points}
          </p>
        </div>
        {anchor ? (
          <span className="nz-admin-cmd__coords" title={t('Position of the first open interaction')}>
            <Icon name="pin" size={12} strokeWidth={1.8} />
            <code>
              {formatCoord(anchor.x)}, {formatCoord(anchor.y)}, {formatCoord(anchor.z)}
            </code>
            <IconButton
              icon={copied ? 'check' : 'copy'}
              label={copied ? t('Copied') : t('Copy coordinates')}
              size="sm"
              onClick={copy}
              className={cx('nz-admin-cmd__copy', copied && 'is-done')}
            />
          </span>
        ) : (
          <span className="nz-admin-cmd__coords is-missing">
            <Icon name="warning" size={12} strokeWidth={1.9} />
            {t('No point placed yet')}
          </span>
        )}
        <Badge tone={loc.enabled ? 'teal' : 'neutral'} dot size="sm">
          {loc.enabled ? t('Enabled') : t('Disabled')}
        </Badge>
        <IconButton icon="close" label={t('Close details')} size="sm" onClick={onClose} className="nz-admin-cmd__insp-x" />
      </header>

      <div className={cx('nz-admin-cmd__insp-body', showOwners && 'has-owners')}>
        {/* kind facts */}
        <div className="nz-admin-cmd__insp-sec">
          <h3>{factsTitle}</h3>
          <dl className="nz-admin-cmd__facts">
            {facts.map((f) => (
              <div key={f.label} className={cx('nz-admin-cmd__fact', f.tone && `is-${f.tone}`)}>
                <dt>{f.label}</dt>
                <dd title={f.title ?? (typeof f.value === 'string' ? f.value : undefined)}>{f.value}</dd>
              </div>
            ))}
          </dl>
        </div>

        {/* owners (private) */}
        {showOwners && (
          <div className="nz-admin-cmd__insp-sec">
            <h3>
              {t('Owners')}
              {Array.isArray(owners) && owners.length > 0 && <em>{owners.length}</em>}
            </h3>
            {owners === undefined ? (
              <div className="nz-admin-cmd__owners">
                {[0, 1].map((i) => (
                  <span key={i} className="nz-admin-cmd__owner is-skel">
                    <Skeleton width={24} height={24} radius={6} />
                    <Skeleton width={i ? 72 : 104} height={9} />
                  </span>
                ))}
              </div>
            ) : owners === 'error' ? (
              <p className="nz-admin-cmd__muted-text">
                {t('Could not load the owners.')}{' '}
                {onRetryOwners && (
                  <button type="button" className="nz-admin-cmd__link" onClick={onRetryOwners}>
                    {t('Retry')}
                  </button>
                )}
              </p>
            ) : owners.length === 0 ? (
              <p className="nz-admin-cmd__muted-text">{t('Nobody owns a copy yet.')}</p>
            ) : (
              <div className="nz-admin-cmd__owners">
                {owners.slice(0, 3).map((g) => (
                  <span key={g.id} className="nz-admin-cmd__owner" title={`${g.label} · ${g.ownerName}`}>
                    <Avatar name={g.ownerName || g.owner} size={24} />
                    <span className="nz-admin-cmd__owner-text">
                      <b>{g.label}</b>
                      <small>
                        {g.ownerName} · {plural(g.members.length, '{count} member', '{count} members')} · {plural(g.vehicles, '{count} vehicle', '{count} vehicles')}
                      </small>
                    </span>
                  </span>
                ))}
                {owners.length > 3 && <span className="nz-admin-cmd__more">{t('+{count} more in the editor', { count: owners.length - 3 })}</span>}
              </div>
            )}
          </div>
        )}

        {/* vehicles */}
        <div className="nz-admin-cmd__insp-sec">
          <h3>{t('Vehicles')}</h3>
          {isImpound ? (
            <div className="nz-admin-cmd__nums">
              <span className={cx('is-held', !stats.held && 'is-zero')}>
                <b>{fmt(stats.held)}</b>
                <small>{t('held here')}</small>
              </span>
            </div>
          ) : spawner !== null && vehicles === 0 ? (
            <p className="nz-admin-cmd__note">
              <Icon name="key" size={13} strokeWidth={1.8} />
              <span>
                <b>{plural(spawner, '{count} spawner vehicle', '{count} spawner vehicles')}</b>
                <small>{t('Taken out on demand, never stored here.')}</small>
              </span>
            </p>
          ) : (
            <div className="nz-admin-cmd__nums">
              <span className={cx('is-parked', !stats.parked && 'is-zero')}>
                <b>{fmt(stats.parked)}</b>
                <small>{t('parked')}</small>
              </span>
              <span className={cx('is-out', !stats.out && 'is-zero')}>
                <b>{fmt(stats.out)}</b>
                <small>{t('out now')}</small>
              </span>
              <span className={cx('is-impounded', !stats.impounded && 'is-zero')}>
                <b>{fmt(stats.impounded)}</b>
                <small>{t('impounded')}</small>
              </span>
            </div>
          )}
          {!isImpound && capacity && !(spawner !== null && vehicles === 0) && (
            <div className="nz-admin-cmd__cap">
              {total !== null ? (
                <>
                  <span className="nz-admin-cmd__cap-text">
                    {t('{used} of {total} spaces used', { used: fmt(used), total: fmt(total) })}
                  </span>
                  <i
                    className={cx('nz-admin-cmd__cap-bar', used >= total && 'is-full', used / total >= 0.8 && used < total && 'is-high')}
                    style={{ '--ratio': Math.min(1, total ? used / total : 0) } as CSSProperties}
                  />
                </>
              ) : (
                <span className="nz-admin-cmd__cap-text">
                  {t('Capacity')}: <b>{capacityLabel(capacity)}</b>
                </span>
              )}
            </div>
          )}
        </div>
      </div>

      <footer className="nz-admin-cmd__insp-actions">
        <Button variant="teal" size="sm" icon="edit" onClick={onEdit}>
          {t('Edit')}
          <Kbd size="sm" className="nz-admin-cmd__kbd">
            Enter
          </Kbd>
        </Button>
        <Button
          size="sm"
          icon="pin"
          onClick={onTeleport}
          disabled={!anchor}
          loading={busy === 'teleport'}
          title={anchor ? t('Teleport to the first open interaction') : t('No interaction point to teleport to')}
        >
          {t('Teleport')}
        </Button>
        <Menu
          align="left"
          items={pointItems}
          trigger={
            <Button size="sm" icon="route" iconRight="chevronDown" loading={busy === 'points'} title={t('Place points in the world')}>
              {t('Points')}
            </Button>
          }
        />
        <span className="nz-admin-cmd__grow" />
        <Button size="sm" icon={loc.enabled ? 'eyeOff' : 'eye'} onClick={onToggle} loading={busy === 'toggle'}>
          {loc.enabled ? t('Disable') : t('Enable')}
        </Button>
        <Button size="sm" variant="red" icon="trash" onClick={onDelete}>
          {t('Delete')}
        </Button>
      </footer>
    </section>
  );
});
