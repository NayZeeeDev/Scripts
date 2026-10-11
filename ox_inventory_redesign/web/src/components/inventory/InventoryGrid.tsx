import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Inventory } from '../../typings';
import InventorySlot from './InventorySlot';
import { getTotalWeight } from '../../helpers';
import { useAppSelector } from '../../store';
import { useIntersection } from '../../hooks/useIntersection';
import { T } from '../../store/strings';
import { formatKg } from '../nz/format';
import { IconBackpack, IconBag, IconBox, IconCar, IconDrop, IconHammer, IconStore, IconUser } from '../nz/Icons';

const PAGE_SIZE = 30;

const getMeta = (inventory: Inventory) => {
  switch (inventory.type) {
    case 'player':
      return { title: T.pocket, sub: T.pocket_sub, Icon: IconBackpack };
    case 'newdrop':
      return { title: T.ground, sub: T.ground_sub, Icon: IconDrop };
    case 'drop':
      return { title: inventory.label || T.ground, sub: T.ground_sub, Icon: IconDrop };
    case 'shop':
      return { title: inventory.label || 'Shop', sub: T.shop_sub, Icon: IconStore };
    case 'crafting':
      return { title: inventory.label || 'Crafting', sub: T.crafting_sub, Icon: IconHammer };
    case 'trunk':
      return { title: inventory.label || 'Trunk', sub: T.trunk_sub, Icon: IconCar };
    case 'glovebox':
      return { title: inventory.label || 'Glovebox', sub: T.glovebox_sub, Icon: IconCar };
    case 'container':
      return { title: inventory.label || 'Container', sub: T.container_sub, Icon: IconBox };
    case 'otherplayer':
    case 'inspect':
      return { title: inventory.label || T.player, sub: T.player_sub, Icon: IconUser };
    default:
      return { title: inventory.label || inventory.id, sub: T.storage_sub, Icon: IconBox };
  }
};

export const WeightSegments: React.FC<{ percent: number; segments?: number }> = ({ percent, segments = 10 }) => {
  const filled = Math.min(segments, Math.ceil((Math.max(0, percent) / 100) * segments));
  const danger = percent >= 90;
  return (
    <div className={`nz-segments${danger ? ' is-danger' : ''}`}>
      {Array.from({ length: segments }, (_, i) => (
        <span key={i} className={i < filled ? 'on' : undefined} />
      ))}
    </div>
  );
};

const InventoryGrid: React.FC<{ inventory: Inventory; side: 'left' | 'right' }> = ({ inventory, side }) => {
  const weight = useMemo(
    () => (inventory.maxWeight !== undefined ? Math.floor(getTotalWeight(inventory.items) * 1000) / 1000 : 0),
    [inventory.maxWeight, inventory.items]
  );
  const [page, setPage] = useState(0);
  const { ref, entry } = useIntersection({ threshold: 0.5 });
  const isBusy = useAppSelector((state) => state.inventory.isBusy);
  const scrollRef = useRef<HTMLDivElement>(null);
  const meta = getMeta(inventory);
  const isPlayer = side === 'left' && inventory.type === 'player';

  useEffect(() => {
    if (entry && entry.isIntersecting) {
      setPage((prev) => ++prev);
    }
  }, [entry]);

  // new inventory -> back to the top
  useEffect(() => {
    setPage(0);
    if (scrollRef.current) scrollRef.current.scrollTop = 0;
  }, [inventory.id, inventory.type]);

  const Icon = meta.Icon;

  return (
    <div className={`nz-panel nz-panel-${side}`} style={{ pointerEvents: isBusy ? 'none' : 'auto' }}>
      <div className="nz-panel-header">
        <div className="nz-diamond">
          <Icon />
        </div>
        <div className="nz-panel-title">
          <p>{meta.title}</p>
          <span>{meta.sub}</span>
        </div>
        {inventory.maxWeight ? (
          <div className="nz-panel-weight">
            <IconBag className="nz-weight-icon" />
            <b>{formatKg(weight)}</b>
            <span>/ {formatKg(inventory.maxWeight)} KG</span>
            <WeightSegments percent={(weight / inventory.maxWeight) * 100} />
          </div>
        ) : null}
      </div>
      <div className="nz-grid-scroll" ref={scrollRef}>
        <div className={`nz-grid-row${isPlayer ? ' has-gutter' : ''}`}>
          {isPlayer && (
            <div className="nz-gutter">
              <span className="nz-gutter-hotbar">{T.hotbar}</span>
              <span className="nz-gutter-inventory">{T.inventory}</span>
            </div>
          )}
          <div className="nz-grid">
            {inventory.items.slice(0, (page + 1) * PAGE_SIZE).map((item, index) => (
              <InventorySlot
                key={`${inventory.type}-${inventory.id}-${item.slot}`}
                item={item}
                ref={index === (page + 1) * PAGE_SIZE - 1 ? ref : null}
                inventoryType={inventory.type}
                inventoryGroups={inventory.groups}
                inventoryId={inventory.id}
              />
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};

export default InventoryGrid;
