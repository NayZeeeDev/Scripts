/**
 * Share modal: let other players drive a vehicle without changing ownership.
 * Lists current shares (remove), add an online player, max counter.
 */
import { useEffect, useRef, useState } from 'react';
import { Avatar, Badge, Button, EmptyState, IconButton, Modal, Select, SkeletonRows, Spinner } from '@/components/ui';
import { t } from '@/lib/i18n';
import { request } from '@/lib/nui';
import { toast } from '@/lib/store';
import type { GarageVehicle, ShareData } from '@/lib/types';
import { ModalVehicle } from './ModalVehicle';

export function ShareModal({
  vehicle,
  onClose,
  onChanged,
}: {
  vehicle: GarageVehicle | null;
  onClose: () => void;
  /** Called after a share was added / removed (caller refreshes the garage). */
  onChanged: () => void;
}) {
  const [data, setData] = useState<ShareData | null>(null);
  const [failed, setFailed] = useState(false);
  const [player, setPlayer] = useState<number | null>(null);
  const [adding, setAdding] = useState(false);
  const [removing, setRemoving] = useState<string | null>(null);
  const [dirty, setDirty] = useState(false);

  const plate = vehicle?.plate ?? null;
  /** Plate the modal currently shows: replies for another plate (or after close) are not applied. */
  const curPlate = useRef<string | null>(plate);
  useEffect(() => {
    curPlate.current = plate;
    if (!plate) return;
    let alive = true;
    setData(null);
    setFailed(false);
    setPlayer(null);
    setDirty(false);
    void request('garage:shares', { plate }).then((res) => {
      if (!alive) return;
      if (res.ok) setData(res.data);
      else setFailed(true);
    });
    return () => {
      alive = false;
    };
  }, [plate]);

  const count = data?.sharedWith.length ?? 0;
  const max = data?.max ?? 0;
  const full = count >= max; // server: max 0 = nobody can be added
  const busy = adding || removing !== null;

  const add = async () => {
    if (!vehicle || player === null || busy || full) return;
    const forPlate = vehicle.plate;
    setAdding(true);
    const name = data?.players.find((p) => p.serverId === player)?.name ?? '';
    const res = await request('garage:share', { plate: forPlate, serverId: player });
    setAdding(false);
    if (!res.ok) return;
    if (curPlate.current !== forPlate) {
      // Closed or switched vehicle meanwhile: the share still changed, refresh the garage.
      onChanged();
      return;
    }
    setData(res.data);
    setPlayer(null);
    setDirty(true);
    toast({ type: 'success', message: t('{name} can now drive this vehicle.', { name }) });
  };

  const remove = async (identifier: string, name: string) => {
    if (!vehicle || busy) return;
    const forPlate = vehicle.plate;
    setRemoving(identifier);
    const res = await request('garage:unshare', { plate: forPlate, identifier });
    setRemoving(null);
    if (!res.ok) return;
    if (curPlate.current !== forPlate) {
      onChanged();
      return;
    }
    setData(res.data);
    setDirty(true);
    toast({ type: 'info', message: t('{name} can no longer drive this vehicle.', { name }) });
  };

  const done = () => {
    if (busy) return;
    onClose();
    if (dirty) onChanged();
  };

  return (
    <Modal
      className="nz-garage-modal"
      open={!!vehicle}
      title={t('Share vehicle')}
      subtitle={t('Shared players can drive it. You stay the owner.')}
      icon="users"
      onClose={done}
      locked={busy}
      width={460}
      footer={
        <Button variant="white" onClick={done} disabled={busy}>
          {t('Done')}
        </Button>
      }
    >
      {vehicle && (
        <>
          <ModalVehicle
            v={vehicle}
            aside={
              data && max > 0 ? (
                <Badge tone={full ? 'amber' : 'neutral'} icon="users">
                  {t('{count}/{max} shared', { count, max })}
                </Badge>
              ) : null
            }
          />
          {failed ? (
            <EmptyState compact icon="warning" title={t('Could not load shares')} description={t('Close this window and try again.')} />
          ) : !data ? (
            <SkeletonRows count={2} />
          ) : (
            <>
              <div className="nz-garage__addrow">
                <Select<number>
                  value={player}
                  onChange={setPlayer}
                  options={data.players.map((p) => ({ value: p.serverId, label: p.name, icon: 'user', hint: t('ID {id}', { id: p.serverId }) }))}
                  placeholder={data.players.length ? t('Choose a player') : t('No players online')}
                  icon="userPlus"
                  disabled={full || busy || data.players.length === 0}
                  searchable
                />
                <Button variant="teal" icon="plus" disabled={player === null || full || removing !== null} loading={adding} onClick={() => void add()}>
                  {t('Share')}
                </Button>
              </div>
              {full && <p className="nz-garage__helper is-amber">{t('You reached the share limit. Remove someone to add another player.')}</p>}
              <div className="nz-garage__people">
                {data.sharedWith.length === 0 ? (
                  <EmptyState
                    compact
                    icon="users"
                    title={t('Not shared yet')}
                    description={t('Pick a player above to give them a key. You can take it back at any time.')}
                  />
                ) : (
                  data.sharedWith.map((s) => (
                    <div key={s.identifier} className="nz-garage__person">
                      <Avatar name={s.name} size={30} />
                      <div className="nz-garage__person-text">
                        <b>{s.name}</b>
                        <span>{t('Can drive this vehicle')}</span>
                      </div>
                      {removing === s.identifier ? (
                        <span className="nz-garage__spin">
                          <Spinner size={14} />
                        </span>
                      ) : (
                        <IconButton
                          icon="close"
                          label={t('Stop sharing with {name}', { name: s.name })}
                          size="sm"
                          variant="ghost"
                          disabled={busy}
                          onClick={() => void remove(s.identifier, s.name)}
                        />
                      )}
                    </div>
                  ))
                )}
              </div>
            </>
          )}
        </>
      )}
    </Modal>
  );
}
