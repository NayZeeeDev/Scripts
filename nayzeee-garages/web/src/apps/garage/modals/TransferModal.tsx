/**
 * Transfer modal: move a vehicle to another garage (spaces left, per-garage fee) or give it
 * to an online player (ownership changes → extra ConfirmDialog).
 */
import { useEffect, useMemo, useState } from 'react';
import { Button, ConfirmDialog, EmptyState, Field, Icon, Modal, Segmented, Select, Skeleton } from '@/components/ui';
import type { SelectOption } from '@/components/ui';
import { t } from '@/lib/i18n';
import { money } from '@/lib/format';
import { request } from '@/lib/nui';
import { toast } from '@/lib/store';
import type { GarageOptions, GarageVehicle, TransferOptions } from '@/lib/types';
import { displayName } from '../model';
import { ModalVehicle } from './ModalVehicle';

type Mode = 'garage' | 'player';

export function TransferModal({
  vehicle,
  options,
  onClose,
  onDone,
}: {
  vehicle: GarageVehicle | null;
  options: GarageOptions;
  onClose: () => void;
  onDone: () => void;
}) {
  const modes = useMemo(() => {
    const list: { value: Mode; label: string; icon: 'garage' | 'user' }[] = [];
    if (options.garageTransfer) list.push({ value: 'garage', label: t('Garage'), icon: 'garage' });
    if (options.playerTransfer) list.push({ value: 'player', label: t('Player'), icon: 'user' });
    return list;
  }, [options.garageTransfer, options.playerTransfer]);

  const [mode, setMode] = useState<Mode>('garage');
  const [data, setData] = useState<TransferOptions | null>(null);
  const [failed, setFailed] = useState(false);
  const [garageKey, setGarageKey] = useState<string | null>(null);
  const [player, setPlayer] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [confirm, setConfirm] = useState(false);

  const plate = vehicle?.plate ?? null;
  useEffect(() => {
    if (!plate) return;
    let alive = true;
    setMode(modes[0]?.value ?? 'garage');
    setData(null);
    setFailed(false);
    setGarageKey(null);
    setPlayer(null);
    setConfirm(false);
    void request('garage:transferOptions', { plate }).then((res) => {
      if (!alive) return;
      if (res.ok) setData(res.data);
      else setFailed(true);
    });
    return () => {
      alive = false;
    };
    // Reload only when a different vehicle opens the modal (modes are read at that moment).
  }, [plate]);

  const garageOptions: SelectOption<string>[] = (data?.garages ?? []).map((g) => ({
    value: g.key,
    label: g.name,
    icon: 'garage',
    hint: `${
      g.spacesLeft == null
        ? t('Unlimited')
        : g.spacesLeft === 0
          ? t('Full')
          : g.spacesLeft === 1
            ? t('1 space left')
            : t('{n} spaces left', { n: g.spacesLeft })
    } · ${g.fee > 0 ? money(g.fee) : t('Free')}`,
    disabled: g.spacesLeft === 0,
  }));
  const playerOptions: SelectOption<number>[] = (data?.players ?? []).map((p) => ({
    value: p.serverId,
    label: p.name,
    icon: 'user',
    hint: t('ID {id}', { id: p.serverId }),
  }));

  const selectedGarage = data?.garages.find((g) => g.key === garageKey) ?? null;
  const selectedPlayer = data?.players.find((p) => p.serverId === player) ?? null;
  const fee =
    mode === 'garage' ? selectedGarage?.fee ?? data?.garageFee ?? options.garageFee : data?.playerFee ?? options.playerFee;
  const ready = mode === 'garage' ? !!selectedGarage : !!selectedPlayer;

  const send = async () => {
    if (!vehicle || !ready || busy) return;
    setBusy(true);
    const target = mode === 'garage' ? garageKey! : player!;
    const res = await request('garage:transfer', { plate: vehicle.plate, type: mode, target });
    setBusy(false);
    setConfirm(false);
    if (!res.ok) return;
    toast({
      type: 'success',
      title: t('Transfer complete'),
      message:
        mode === 'garage'
          ? t('{vehicle} was moved to {garage}.', { vehicle: displayName(vehicle), garage: selectedGarage?.name ?? '' })
          : t('{vehicle} now belongs to {player}.', { vehicle: displayName(vehicle), player: selectedPlayer?.name ?? '' }),
    });
    onClose();
    onDone();
  };

  const submit = () => {
    if (!ready) return;
    if (mode === 'player') setConfirm(true);
    else void send();
  };

  const loading = !data && !failed;

  return (
    <>
      <Modal
        open={!!vehicle}
        title={t('Transfer vehicle')}
        icon="transfer"
        onClose={onClose}
        locked={busy}
        width={460}
        footer={
          <>
            <Button variant="line" onClick={onClose} disabled={busy}>
              {t('Cancel')}
            </Button>
            <Button
              variant="teal"
              icon="transfer"
              disabled={!ready || loading}
              loading={busy && !confirm}
              badge={ready ? (fee > 0 ? money(fee) : t('Free')) : undefined}
              onClick={submit}
            >
              {t('Transfer')}
            </Button>
          </>
        }
      >
        {vehicle && (
          <>
            <ModalVehicle v={vehicle} />
            {modes.length > 1 && (
              <Segmented<Mode> value={mode} onChange={setMode} options={modes} full />
            )}
            {loading ? (
              <div className="nz-garage__mstack">
                <Skeleton height={11} width={110} />
                <Skeleton height={34} radius={6} />
              </div>
            ) : failed ? (
              <EmptyState compact icon="warning" title={t('Could not load transfer options')} description={t('Close this window and try again.')} />
            ) : mode === 'garage' ? (
              garageOptions.length === 0 ? (
                <EmptyState compact icon="garage" title={t('No other garages')} description={t('There is no other garage this vehicle can be moved to.')} />
              ) : (
                <Field label={t('Destination garage')} hint={t('The vehicle is moved right away and waits for you there.')}>
                  <Select<string>
                    value={garageKey}
                    onChange={setGarageKey}
                    options={garageOptions}
                    placeholder={t('Choose a garage')}
                    icon="garage"
                  />
                </Field>
              )
            ) : playerOptions.length === 0 ? (
              <EmptyState compact icon="users" title={t('Nobody to transfer to')} description={t('No other players are online right now.')} />
            ) : (
              <>
                <Field label={t('New owner')} hint={t('Ownership changes for good — they become the owner.')}>
                  <Select<number>
                    value={player}
                    onChange={setPlayer}
                    options={playerOptions}
                    placeholder={t('Choose a player')}
                    icon="user"
                    searchable
                  />
                </Field>
              </>
            )}
            {!loading && !failed && ready && (
              <div className="nz-garage__summary">
                <span>
                  <Icon name="money" size={13} strokeWidth={1.8} />
                  {t('Transfer fee')}
                </span>
                <b>{fee > 0 ? money(fee) : t('Free')}</b>
              </div>
            )}
          </>
        )}
      </Modal>
      <ConfirmDialog
        open={confirm}
        tone="red"
        icon="transfer"
        title={t('Give this vehicle away?')}
        message={
          <>
            <b>{vehicle ? displayName(vehicle) : ''}</b> ({vehicle?.plate}){' '}
            {t('will belong to')} <b>{selectedPlayer?.name}</b>. {t('You lose ownership and cannot undo this.')}
          </>
        }
        confirmLabel={fee > 0 ? t('Transfer for {fee}', { fee: money(fee) }) : t('Transfer')}
        busy={busy}
        onConfirm={() => void send()}
        onCancel={() => setConfirm(false)}
      />
    </>
  );
}
