/**
 * Plate view (nz:carlock:admin:plate): every key of one vehicle. Owner (→ their key page),
 * key version, copies of the current locks, immobiliser, spawned + distance; the key items
 * with custody and holder, virtual / temporary access holders, keys on the ground.
 * Track opens the track dialog; a key item, access or ground key can be deleted (the
 * holder, else the owner, is the player the server answers for).
 */
import { useEffect, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import { Avatar, Badge, Button, ConfirmDialog, EmptyState, Icon, IconButton, Modal, SkeletonRows, Tooltip, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import { request } from '@/lib/nui';
import { toast, useSettings } from '@/lib/store';
import type { KeyAdminPlateData } from '@/lib/types';
import type { Nav } from './ManageKeys';
import { KeyGlyph } from './PlayerView';
import { custodyOf, duration, list, meters, originLabel, secondsLeft, stamp } from './model';

interface Props {
  plate: string;
  fobDesign: string | null;
  onClose: () => void;
  /** keys changed here: an open player page reloads */
  onChanged: () => void;
  nav: Nav;
}

interface Pending {
  identifier: string;
  id: string;
  title: string;
  message: string;
}

export function PlateModal({ plate, fobDesign, onClose, onChanged, nav }: Props) {
  const { distanceUnit } = useSettings();
  const [data, setData] = useState<KeyAdminPlateData | null>(null);
  const [loading, setLoading] = useState(true);
  const [failed, setFailed] = useState(false);
  const [pending, setPending] = useState<Pending | null>(null);
  const [busy, setBusy] = useState(false);
  const seq = useRef(0);

  const load = async () => {
    const id = ++seq.current;
    setLoading(true);
    const res = await request('keyadmin:plate', { plate });
    if (id !== seq.current) return;
    setLoading(false);
    setFailed(!res.ok);
    if (res.ok && res.data) setData({ ...res.data, custody: list(res.data.custody), holders: list(res.data.holders), ground: list(res.data.ground) });
  };

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [plate]);

  const remove = async () => {
    if (!pending || busy) return;
    setBusy(true);
    const res = await request('keyadmin:delete', { identifier: pending.identifier, id: pending.id });
    setBusy(false);
    if (!res.ok) return;
    toast({ type: 'success', message: t('Key of {plate} deleted', { plate }) });
    setPending(null);
    onChanged();
    void load();
  };

  const owner = data?.owner ?? null;
  const title = data?.label || data?.model || plate;

  return (
    <Modal
      open
      title={title}
      subtitle={t('Every key of this vehicle')}
      icon="tag"
      width={860}
      onClose={onClose}
      bodyClassName="nz-kadm-plateview"
      footer={
        <>
          <Button variant="ghost" icon="refresh" onClick={() => void load()} loading={loading && !!data}>
            {t('Refresh')}
          </Button>
          <Button variant="teal" icon="map" disabled={!data?.spawned} onClick={() => nav.track(plate, data?.label)}>
            {data?.spawned ? t('Track') : t('Not out')}
          </Button>
        </>
      }
    >
      {!data ? (
        failed ? (
          <EmptyState
            icon="warning"
            title={t('{plate} could not be loaded', { plate })}
            action={
              <Button size="sm" icon="refresh" onClick={() => void load()}>
                {t('Try again')}
              </Button>
            }
          />
        ) : (
          <SkeletonRows count={6} />
        )
      ) : (
        <>
          <div className="nz-kadm-pv__head">
            <span className="nz-kadm-pv__plate">{data.plate}</span>
            <div className="nz-kadm-pv__veh">
              <b>{title}</b>
              <span>
                {data.make ? `${data.make} · ` : ''}
                <span className="nz-kadm-mono">{data.model ?? t('model unknown')}</span>
              </span>
            </div>
            {data.owned ? (
              owner ? (
                <button type="button" className="nz-kadm-pv__owner" onClick={() => nav.openPlayer(owner, data.ownerName ?? undefined)} title={t('Open their keys')}>
                  <Avatar name={data.ownerName ?? '?'} size={28} />
                  <span>
                    <em>{t('Owner')}</em>
                    <b>{data.ownerName ?? t('Unknown')}</b>
                  </span>
                  <Icon name="chevronRight" size={14} strokeWidth={1.8} />
                </button>
              ) : (
                <Badge tone="neutral">{t('Registered, no owner')}</Badge>
              )
            ) : (
              <Badge tone="amber" icon="warning">
                {t('Not a registered vehicle')}
              </Badge>
            )}
          </div>

          <div className="nz-kadm-pv__stats">
            <Stat label={t('Lock version')} value={data.version ?? '—'} hint={t('Changing the locks retires every older key')} />
            <Stat label={t('Live copies')} value={data.live ?? '—'} hint={t('Key items cut for the current locks: pockets, stashes and the ground')} />
            <Stat
              label={t('Immobiliser')}
              value={
                data.immobiliser.level === 'none' ? (
                  t('None')
                ) : (
                  <span className="nz-kadm-pv__immo">
                    {data.immobiliser.level === 'ghost' ? t('Ghost') : t('Standard')}
                    {data.immobiliser.level === 'ghost' && (
                      <Badge tone={data.immobiliser.pinSet ? 'teal' : 'amber'} size="sm">
                        {data.immobiliser.pinSet ? t('PIN set') : t('No PIN')}
                      </Badge>
                    )}
                  </span>
                )
              }
            />
            <Stat
              label={t('Vehicle')}
              value={
                data.spawned ? (
                  <span className="nz-kadm-veh is-out">
                    <i className="nz-kadm-dot is-on" />
                    {data.distance !== null ? t('Out · {d} away', { d: meters(data.distance, distanceUnit) }) : t('Out')}
                  </span>
                ) : (
                  <span className="nz-kadm-veh">
                    <i className="nz-kadm-dot" />
                    {t('Not out')}
                  </span>
                )
              }
            />
          </div>

          <Section title={t('Key items')} count={data.custody.length}>
            {data.custody.length === 0 ? (
              <p className="nz-kadm-pv__none">{t('No key items are known for this vehicle.')}</p>
            ) : (
              data.custody.map((k) => {
                const c = custodyOf(k.custody);
                const who = k.holder ?? owner;
                return (
                  <div key={k.id} className={cx('nz-kadm-pv__row', !k.current && 'is-old')}>
                    <KeyGlyph type={k.type} design={fobDesign} brand={data.make} size={30} />
                    <span className="nz-kadm-pv__main">
                      <b>{k.type === 'fob' ? t('Fob') : t('Key')}</b>
                      <span>{originLabel(k.origin)}</span>
                    </span>
                    {k.current ? (
                      <Badge tone="teal" size="sm">
                        {t('Fits')}
                      </Badge>
                    ) : (
                      <Tooltip content={t('Cut for older locks: it no longer opens the vehicle')}>
                        <Badge tone="red" size="sm">
                          {t('Old locks')}
                        </Badge>
                      </Tooltip>
                    )}
                    <span className={cx('nz-kadm-custody', `is-${c.tone}`)}>
                      <Icon name={c.icon} size={14} strokeWidth={1.7} />
                      <span>
                        {c.label}
                        {c.detail && <em> · {c.detail}</em>}
                      </span>
                    </span>
                    <span className="nz-kadm-pv__holder">
                      {k.holder ? (
                        <button type="button" onClick={() => nav.openPlayer(k.holder as string, k.holderName ?? undefined)}>
                          {k.holderName ?? t('Unknown')}
                          <Icon name="chevronRight" size={12} strokeWidth={1.8} />
                        </button>
                      ) : (
                        <span>—</span>
                      )}
                    </span>
                    <IconButton
                      icon="trash"
                      size="sm"
                      className="nz-kadm-del"
                      label={who ? t('Delete this key') : t('Nobody to answer for: delete it from a player page')}
                      disabled={!who}
                      onClick={() =>
                        who &&
                        setPending({
                          identifier: who,
                          id: k.id,
                          title: t('Delete this key item of {plate}?', { plate }),
                          message: t('It is taken out of where it is and stops working. A key nobody can reach is marked lost.'),
                        })
                      }
                    />
                  </div>
                );
              })
            )}
          </Section>

          <Section title={t('Access without an item')} count={data.holders.length}>
            {data.holders.length === 0 ? (
              <p className="nz-kadm-pv__none">{t('Nobody holds a virtual or temporary key.')}</p>
            ) : (
              data.holders.map((h) => {
                const left = h.type === 'temp' ? secondsLeft(h.expires) : null;
                return (
                  <div key={`${h.type}:${h.identifier}`} className="nz-kadm-pv__row">
                    <KeyGlyph type={h.type} design={null} size={30} />
                    <span className="nz-kadm-pv__main">
                      <button type="button" className="nz-kadm-link" onClick={() => nav.openPlayer(h.identifier, h.name)}>
                        {h.name}
                      </button>
                      <span>{h.type === 'temp' ? originLabel(h.origin) : t('Shared key')}</span>
                    </span>
                    <Badge tone={h.type === 'temp' ? 'amber' : 'blue'} size="sm">
                      {h.type === 'temp' ? t('Temporary') : t('Virtual')}
                    </Badge>
                    <span className="nz-kadm-pv__meta">{left !== null ? (left > 0 ? t('{time} left', { time: duration(left) }) : t('ending')) : '—'}</span>
                    <span />
                    <IconButton
                      icon="trash"
                      size="sm"
                      className="nz-kadm-del"
                      label={t('Revoke')}
                      onClick={() =>
                        setPending({
                          identifier: h.identifier,
                          id: `${h.type}:${plate}`,
                          title: t('Revoke the key of {name}?', { name: h.name }),
                          message: h.type === 'temp' ? t('Their temporary key ends now.') : t('Their shared access is revoked.'),
                        })
                      }
                    />
                  </div>
                );
              })
            )}
          </Section>

          <Section title={t('On the ground')} count={data.ground.length}>
            {data.ground.length === 0 ? (
              <p className="nz-kadm-pv__none">{t('No key of this vehicle lies on the ground.')}</p>
            ) : (
              data.ground.map((g) => (
                <div key={g.id} className="nz-kadm-pv__row">
                  <KeyGlyph type={g.keyKind} design={fobDesign} brand={data.make} size={30} />
                  <span className="nz-kadm-pv__main">
                    <b>{g.kind === 'temp' ? t('Robbed driver key') : g.keyKind === 'fob' ? t('Fob') : t('Key')}</b>
                    <span className="nz-kadm-mono">{`${g.coords.x.toFixed(1)}, ${g.coords.y.toFixed(1)}, ${g.coords.z.toFixed(1)}`}</span>
                  </span>
                  {g.bucket ? (
                    <Badge tone="amber" size="sm">
                      {t('Bucket {n}', { n: g.bucket })}
                    </Badge>
                  ) : (
                    <span />
                  )}
                  <span className="nz-kadm-pv__meta">{t('Dropped {time}', { time: stamp(g.createdAt) })}</span>
                  <span className="nz-kadm-pv__meta">{g.expiresAt ? t('Gone {time}', { time: stamp(g.expiresAt) }) : t('Stays')}</span>
                  <IconButton
                    icon="trash"
                    size="sm"
                    className="nz-kadm-del"
                    label={owner || g.droppedBy ? t('Remove from the ground') : t('Nobody to answer for: delete it from a player page')}
                    disabled={!owner && !g.droppedBy}
                    onClick={() =>
                      setPending({
                        identifier: (owner ?? g.droppedBy) as string,
                        id: `ground:${g.id}`,
                        title: t('Remove this key from the ground?'),
                        message: t('The prop disappears and the key stops working.'),
                      })
                    }
                  />
                </div>
              ))
            )}
          </Section>
        </>
      )}
      <ConfirmDialog
        open={!!pending}
        tone="red"
        icon="trash"
        title={pending?.title ?? ''}
        message={pending?.message ?? ''}
        confirmLabel={t('Delete')}
        busy={busy}
        onConfirm={() => void remove()}
        onCancel={() => setPending(null)}
      />
    </Modal>
  );
}

function Section({ title, count, children }: { title: string; count: number; children: ReactNode }) {
  return (
    <section className="nz-kadm-pv__section">
      <h4 className="nz-kadm-heading">
        {title}
        <span>{count}</span>
      </h4>
      <div className="nz-kadm-pv__list">{children}</div>
    </section>
  );
}

function Stat({ label, value, hint }: { label: string; value: ReactNode; hint?: string }) {
  return (
    <div className="nz-kadm-pv__stat">
      <span className="nz-kadm-pv__stat-label">
        {label}
        {hint && (
          <Tooltip content={hint}>
            <Icon name="info" size={12} strokeWidth={1.7} />
          </Tooltip>
        )}
      </span>
      <span className="nz-kadm-pv__stat-value">{value}</span>
    </div>
  );
}
