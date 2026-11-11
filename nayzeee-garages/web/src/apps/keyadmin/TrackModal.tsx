/**
 * Track a vehicle (nz:carlock:admin:track): where the server sees it, on the calibrated world
 * map of the admin pages (MapView), with distance, routing bucket and coordinates. Set
 * waypoint asks the server again (keyadmin:waypoint): the client never sends a position.
 */
import { useEffect, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import { Badge, Button, EmptyState, Icon, Modal, Spinner } from '@/components/ui';
import { t } from '@/lib/i18n';
import { request } from '@/lib/nui';
import { toast, useSettings } from '@/lib/store';
import type { KeyAdminTrack } from '@/lib/types';
import { MapView } from '../admin/shared/MapView';
import '../admin/shared/map.css';
import { meters } from './model';

export function TrackModal({ plate, label, onClose }: { plate: string; label?: string | null; onClose: () => void }) {
  const { distanceUnit } = useSettings();
  const [info, setInfo] = useState<KeyAdminTrack | null>(null);
  const [loading, setLoading] = useState(true);
  const [focus, setFocus] = useState(0);
  const [busy, setBusy] = useState(false);
  const [at, setAt] = useState<number | null>(null);
  const seq = useRef(0);

  const load = async () => {
    const id = ++seq.current;
    setLoading(true);
    const res = await request('keyadmin:track', { plate });
    if (id !== seq.current) return;
    setLoading(false);
    if (res.ok && res.data) {
      setInfo(res.data);
      setAt(Date.now());
      setFocus((n) => n + 1);
    }
  };

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [plate]);

  const waypoint = async () => {
    setBusy(true);
    const res = await request('keyadmin:waypoint', { plate });
    setBusy(false);
    if (!res.ok || !res.data) return;
    setInfo(res.data);
    setAt(Date.now());
    toast({ type: 'success', message: t('Waypoint set on {plate}', { plate }) });
  };

  const c = info?.coords;
  const out = !!info?.spawned && !!c;

  return (
    <Modal
      open
      title={label ? t('Track {name}', { name: label }) : t('Track vehicle')}
      subtitle={<span className="nz-kadm-mono">{plate}</span>}
      icon="route"
      width={760}
      onClose={onClose}
      bodyClassName="nz-kadm-track"
      footer={
        <>
          <span className="nz-kadm-track__when">
            {at ? t('Server position at {time}', { time: new Date(at).toLocaleTimeString('en-GB') }) : ''}
          </span>
          <Button variant="ghost" icon="refresh" onClick={() => void load()} loading={loading && !!info}>
            {t('Refresh')}
          </Button>
          <Button variant="teal" icon="pin" onClick={() => void waypoint()} loading={busy} disabled={!out}>
            {t('Set waypoint')}
          </Button>
        </>
      }
    >
      <div className="nz-kadm-track__map">
        {out && c ? (
          <MapView
            pins={[{ id: plate, x: c.x, y: c.y, label: label || plate, type: 'car', meta: plate }]}
            selectedId={plate}
            focusTick={focus}
            distanceUnit={distanceUnit}
            className="nz-kadm-track__mapview"
          />
        ) : loading && !info ? (
          <div className="nz-kadm-track__wait">
            <Spinner size={22} />
          </div>
        ) : (
          <EmptyState
            icon="route"
            title={t('The vehicle is not out')}
            description={t('Stored, impounded or never spawned: only vehicles out in the world can be tracked.')}
          />
        )}
      </div>
      <div className="nz-kadm-track__facts">
        <Fact icon="gauge" label={t('Distance')} value={out ? meters(info?.distance ?? null, distanceUnit) : '—'} />
        <Fact
          icon="layers"
          label={t('Routing bucket')}
          value={
            out ? (
              info?.bucket ? (
                <Badge tone="amber" size="sm">
                  {t('Bucket {n}', { n: info.bucket })}
                </Badge>
              ) : (
                t('Main world')
              )
            ) : (
              '—'
            )
          }
        />
        <Fact
          icon="pin"
          label={t('Coordinates')}
          value={out && c ? <span className="nz-kadm-mono">{`${c.x.toFixed(1)}, ${c.y.toFixed(1)}, ${c.z.toFixed(1)}`}</span> : '—'}
        />
      </div>
    </Modal>
  );
}

function Fact({ icon, label, value }: { icon: 'gauge' | 'layers' | 'pin'; label: string; value: ReactNode }) {
  return (
    <div className="nz-kadm-fact">
      <span className="nz-kadm-fact__label">
        <Icon name={icon} size={13} strokeWidth={1.7} />
        {label}
      </span>
      <span className="nz-kadm-fact__value">{value}</span>
    </div>
  );
}
