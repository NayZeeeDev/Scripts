import React, { useRef, useState } from 'react';
import { getItemUrl, isSlotWithItem } from '../../helpers';
import useNuiEvent from '../../hooks/useNuiEvent';
import { useAppSelector } from '../../store';
import { selectLeftInventory } from '../../store/inventory';
import SlideUp from '../utils/transitions/SlideUp';
import { getRarity } from '../../store/rarity';
import { getItemLabel } from './InventorySlot';
import { formatWeight } from '../nz/format';

const InventoryHotbar: React.FC = () => {
  const [hotbarVisible, setHotbarVisible] = useState(false);
  const items = useAppSelector(selectLeftInventory).items.slice(0, 5);
  const style = useAppSelector((state) => state.ui.settings.hotbarStyle);
  const handle = useRef<ReturnType<typeof setTimeout>>(undefined);

  useNuiEvent('toggleHotbar', () => {
    if (hotbarVisible) {
      setHotbarVisible(false);
    } else {
      if (handle.current) clearTimeout(handle.current);
      setHotbarVisible(true);
      handle.current = setTimeout(() => setHotbarVisible(false), 3000);
    }
  });

  return (
    <SlideUp in={hotbarVisible}>
      <div className={`nz-hotbar is-${style}`}>
        {items.map((item) => {
          const has = isSlotWithItem(item);
          return (
            <div className="nz-hot-wrap" key={`hotbar-${item.slot}`}>
              <div className="nz-hot" data-rarity={has ? getRarity(item) : undefined}>
                {has && (
                  <>
                    <div className="nz-slot-image" style={{ backgroundImage: `url(${getItemUrl(item)})` }} />
                    {item.count > 1 && <div className="nz-slot-count">x{item.count.toLocaleString('en-us')}</div>}
                    <div className="nz-hot-weight">{formatWeight(item.weight)}</div>
                    {item.durability !== undefined && (
                      <div className="nz-hot-durability">
                        <div style={{ width: `${Math.max(0, Math.min(100, item.durability))}%` }} />
                      </div>
                    )}
                    <div className="nz-hot-label">{getItemLabel(item)}</div>
                  </>
                )}
              </div>
              <span className="nz-badge">{item.slot}</span>
            </div>
          );
        })}
      </div>
    </SlideUp>
  );
};

export default InventoryHotbar;
