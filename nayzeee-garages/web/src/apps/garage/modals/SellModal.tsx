/**
 * Sell modal: send a sale offer (player + price) — the buyer has to accept in game.
 * Online players come from garage:transferOptions.
 */
import { useEffect, useState } from 'react';
import { Button, EmptyState, Field, Icon, Modal, NumberInput, Select, Skeleton } from '@/components/ui';
import { t } from '@/lib/i18n';
import { money } from '@/lib/format';
import { request } from '@/lib/nui';
import { toast, useSettings } from '@/lib/store';
import type { GarageVehicle, PlayerOption } from '@/lib/types';
import { displayName } from '../model';
import { ModalVehicle } from './ModalVehicle';

const MAX_PRICE = 100_000_000;

export function SellModal({ vehicle, onClose }: { vehicle: GarageVehicle | null; onClose: () => void }) {
  const currency = useSettings().currency;
  const [players, setPlayers] = useState<PlayerOption[] | null>(null);
  const [failed, setFailed] = useState(false);
  const [player, setPlayer] = useState<number | null>(null);
  const [price, setPrice] = useState(0);
  const [busy, setBusy] = useState(false);

  const plate = vehicle?.plate ?? null;
  useEffect(() => {
    if (!plate) return;
    let alive = true;
    setPlayers(null);
    setFailed(false);
    setPlayer(null);
    setPrice(0);
    void request('garage:transferOptions', { plate }).then((res) => {
      if (!alive) return;
      if (res.ok) setPlayers(res.data.players);
      else setFailed(true);
    });
    return () => {
      alive = false;
    };
  }, [plate]);

  const buyer = players?.find((p) => p.serverId === player) ?? null;
  const valid = !!buyer && price > 0;

  const send = async () => {
    if (!vehicle || !valid || busy) return;
    setBusy(true);
    const res = await request('garage:sell', { plate: vehicle.plate, serverId: buyer!.serverId, price });
    setBusy(false);
    if (!res.ok) return;
    toast({
      type: 'success',
      title: t('Offer sent'),
      message: t('{player} received your offer for {vehicle} ({price}).', {
        player: buyer!.name,
        vehicle: displayName(vehicle),
        price: money(price),
      }),
    });
    onClose();
  };

  return (
    <Modal
      open={!!vehicle}
      title={t('Sell vehicle')}
      subtitle={t('The buyer gets an offer and has to accept it.')}
      icon="tag"
      onClose={onClose}
      locked={busy}
      width={460}
      footer={
        <>
          <Button variant="line" onClick={onClose} disabled={busy}>
            {t('Cancel')}
          </Button>
          <Button variant="teal" icon="tag" disabled={!valid} loading={busy} badge={valid ? money(price) : undefined} onClick={() => void send()}>
            {t('Send offer')}
          </Button>
        </>
      }
    >
      {vehicle && (
        <>
          <ModalVehicle v={vehicle} />
          {failed ? (
            <EmptyState compact icon="warning" title={t('Could not load players')} description={t('Close this window and try again.')} />
          ) : !players ? (
            <div className="nz-garage__mstack">
              <Skeleton height={11} width={90} />
              <Skeleton height={34} radius={6} />
              <Skeleton height={11} width={70} />
              <Skeleton height={34} radius={6} />
            </div>
          ) : players.length === 0 ? (
            <EmptyState compact icon="users" title={t('No buyers around')} description={t('No other players are online right now.')} />
          ) : (
            <>
              <Field label={t('Buyer')}>
                <Select<number>
                  value={player}
                  onChange={setPlayer}
                  options={players.map((p) => ({ value: p.serverId, label: p.name, icon: 'user', hint: t('ID {id}', { id: p.serverId }) }))}
                  placeholder={t('Choose a player')}
                  icon="user"
                  searchable
                />
              </Field>
              <Field label={t('Price')} hint={t('Paid by the buyer when they accept.')}>
                <NumberInput value={price} onChange={setPrice} min={0} max={MAX_PRICE} step={500} prefix={currency} onEnter={() => void send()} />
              </Field>
              <div className="nz-garage__receipt">
                <div>
                  <span>{t('Vehicle')}</span>
                  <b>{displayName(vehicle)}</b>
                </div>
                <div>
                  <span>{t('Buyer')}</span>
                  <b>{buyer ? buyer.name : '—'}</b>
                </div>
                <div className="is-total">
                  <span>{t('You receive')}</span>
                  <b>{money(price)}</b>
                </div>
                <p>
                  <Icon name="info" size={12} strokeWidth={1.8} />
                  {t('Ownership only changes once the buyer accepts and pays.')}
                </p>
              </div>
            </>
          )}
        </>
      )}
    </Modal>
  );
}
