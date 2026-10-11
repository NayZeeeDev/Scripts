import React, { useEffect, useState } from 'react';
import { useAppDispatch, useAppSelector } from '../../store';
import { closeGive } from '../../store/ui';
import { T } from '../../store/strings';
import { fetchNui } from '../../utils/fetchNui';
import { isEnvBrowser } from '../../utils/misc';
import { getItemUrl, isSlotWithItem } from '../../helpers';
import { getRarity } from '../../store/rarity';
import { getItemLabel } from '../inventory/InventorySlot';
import { useEscapeClose } from '../../hooks/useEscapeClose';
import { IconClose, IconMinus, IconPlus, IconSwap, IconUser } from './Icons';

interface NearbyPlayer {
  id: number;
  name?: string;
  distance?: number;
}

const GiveModal: React.FC = () => {
  const dispatch = useAppDispatch();
  const give = useAppSelector((state) => state.ui.give);
  const itemAmount = useAppSelector((state) => state.inventory.itemAmount);
  const item = useAppSelector((state) => (give ? state.inventory.leftInventory.items[give.slot - 1] : undefined));
  const [players, setPlayers] = useState<NearbyPlayer[] | null>(null);
  const [count, setCount] = useState(1);

  useEscapeClose(!!give, () => dispatch(closeGive()));

  useEffect(() => {
    if (!give) return;
    setPlayers(null);
    if (isEnvBrowser()) {
      setTimeout(() => setPlayers([{ id: 3, distance: 1.4 }, { id: 7, distance: 2.6 }]), 300);
      return;
    }
    fetchNui<NearbyPlayer[]>('nz:getNearbyPlayers')
      .then((list) => setPlayers(Array.isArray(list) ? list : []))
      .catch(() => setPlayers([]));
  }, [give]);

  useEffect(() => {
    if (!give || !item || !isSlotWithItem(item)) return;
    const wanted = give.count || itemAmount || 1;
    setCount(Math.max(1, Math.min(item.count, wanted)));
  }, [give, item?.count]);

  // item moved/removed while the popup was open
  useEffect(() => {
    if (give && (!item || !isSlotWithItem(item))) dispatch(closeGive());
  }, [give, item]);

  if (!give || !item || !isSlotWithItem(item)) return null;

  const rarity = getRarity(item);
  const send = (target: number) => {
    fetchNui('nz:giveTo', { target, slot: item.slot, count }).catch(() => {});
    dispatch(closeGive());
  };

  return (
    <div className="nz-modal-backdrop is-light" onMouseDown={() => dispatch(closeGive())}>
      <div className="nz-give" onMouseDown={(e) => e.stopPropagation()}>
        <div className="nz-give-head">
          <div className="nz-square-icon">
            <IconSwap />
          </div>
          <div>
            <p>{T.send_item}</p>
            <span>{T.send_item_sub}</span>
          </div>
          <button className="nz-icon-btn" onClick={() => dispatch(closeGive())}>
            <IconClose />
          </button>
        </div>
        <div className="nz-give-item" data-rarity={rarity}>
          <div className="nz-give-thumb" style={{ backgroundImage: `url(${getItemUrl(item)})` }} />
          <div className="nz-give-info">
            <p>{getItemLabel(item)}</p>
            <span className="nz-chip" data-rarity={rarity}>
              {T[`rarity_${rarity}`]}
            </span>
          </div>
          <div className="nz-stepper">
            <button onClick={() => setCount((c) => Math.max(1, c - 1))}>
              <IconMinus />
            </button>
            <b>x{count.toLocaleString('en-us')}</b>
            <button onClick={() => setCount((c) => Math.min(item.count, c + 1))}>
              <IconPlus />
            </button>
          </div>
        </div>
        <div className="nz-give-list">
          {players === null && <div className="nz-give-empty">{T.searching}</div>}
          {players && players.length === 0 && <div className="nz-give-empty">{T.no_players}</div>}
          {players?.map((p) => (
            <button key={p.id} className="nz-give-player" onClick={() => send(p.id)}>
              <div className="nz-give-avatar">
                <IconUser />
              </div>
              <div>
                <p>{p.name || `${T.player} ${p.id}`}</p>
                <span>
                  ID {p.id} • {p.distance !== undefined ? `${p.distance.toFixed(1)}m` : T.nearby}
                </span>
              </div>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
};

export default GiveModal;
