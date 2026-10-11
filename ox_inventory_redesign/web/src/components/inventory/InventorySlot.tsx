import React, { useCallback, useRef } from 'react';
import { DragSource, Inventory, InventoryType, Slot, SlotWithItem } from '../../typings';
import { useDrag, useDragDropManager, useDrop } from 'react-dnd';
import { useAppDispatch, useAppSelector } from '../../store';
import { onDrop } from '../../dnd/onDrop';
import { onBuy } from '../../dnd/onBuy';
import { Items } from '../../store/items';
import { canCraftItem, canPurchaseItem, getItemUrl, isSlotWithItem } from '../../helpers';
import { onUse } from '../../dnd/onUse';
import { Locale } from '../../store/locale';
import { onCraft } from '../../dnd/onCraft';
import useNuiEvent from '../../hooks/useNuiEvent';
import { ItemsPayload } from '../../reducers/refreshSlots';
import { closeTooltip, openTooltip } from '../../store/tooltip';
import { openContextMenu } from '../../store/contextMenu';
import { useMergeRefs } from '@floating-ui/react';
import { getRarity } from '../../store/rarity';
import { formatWeight } from '../nz/format';

interface SlotProps {
  inventoryId: Inventory['id'];
  inventoryType: Inventory['type'];
  inventoryGroups: Inventory['groups'];
  item: Slot;
}

export const getItemLabel = (item: SlotWithItem) =>
  item.metadata?.label ? item.metadata.label : Items[item.name]?.label || item.name;

const durabilityColor = (value: number) => (value > 60 ? '#7ee03a' : value > 25 ? '#ffb31a' : '#ff4a4a');

const InventorySlot: React.ForwardRefRenderFunction<HTMLDivElement, SlotProps> = (
  { item, inventoryId, inventoryType, inventoryGroups },
  ref
) => {
  const manager = useDragDropManager();
  const dispatch = useAppDispatch();
  const timerRef = useRef<number | null>(null);
  const hasItem = isSlotWithItem(item);
  const isPlayer = inventoryType === 'player';

  // search highlighting only applies to the player's own inventory
  const search = useAppSelector((state) => (isPlayer ? state.ui.search.trim().toLowerCase() : ''));
  const matches =
    !search || (hasItem && (getItemLabel(item).toLowerCase().includes(search) || item.name.includes(search)));

  const canDrag = useCallback(() => {
    return canPurchaseItem(item, { type: inventoryType, groups: inventoryGroups }) && canCraftItem(item, inventoryType);
  }, [item, inventoryType, inventoryGroups]);

  const [{ isDragging }, drag] = useDrag<DragSource, void, { isDragging: boolean }>(
    () => ({
      type: 'SLOT',
      collect: (monitor) => ({
        isDragging: monitor.isDragging(),
      }),
      item: () =>
        isSlotWithItem(item, inventoryType !== InventoryType.SHOP)
          ? {
              inventory: inventoryType,
              item: {
                name: item.name,
                slot: item.slot,
              },
              image: item?.name && `url(${getItemUrl(item) || 'none'}`,
            }
          : null,
      canDrag,
    }),
    [inventoryType, item]
  );

  const [{ isOver }, drop] = useDrop<DragSource, void, { isOver: boolean }>(
    () => ({
      accept: 'SLOT',
      collect: (monitor) => ({
        isOver: monitor.isOver() && monitor.canDrop(),
      }),
      drop: (source) => {
        dispatch(closeTooltip());
        switch (source.inventory) {
          case InventoryType.SHOP:
            onBuy(source, { inventory: inventoryType, item: { slot: item.slot } });
            break;
          case InventoryType.CRAFTING:
            onCraft(source, { inventory: inventoryType, item: { slot: item.slot } });
            break;
          default:
            onDrop(source, { inventory: inventoryType, item: { slot: item.slot } });
            break;
        }
      },
      canDrop: (source) =>
        (source.item.slot !== item.slot || source.inventory !== inventoryType) &&
        inventoryType !== InventoryType.SHOP &&
        inventoryType !== InventoryType.CRAFTING,
    }),
    [inventoryType, item]
  );

  useNuiEvent('refreshSlots', (data: { items?: ItemsPayload | ItemsPayload[] }) => {
    if (!isDragging && !data.items) return;
    if (!Array.isArray(data.items)) return;

    const itemSlot = data.items.find(
      (dataItem) => dataItem.item.slot === item.slot && dataItem.inventory === inventoryId
    );

    if (!itemSlot) return;

    manager.dispatch({ type: 'dnd-core/END_DRAG' });
  });

  const connectRef = (element: HTMLDivElement | null) => {
    if (!element) return;
    drag(drop(element));
  };

  const handleContext = (event: React.MouseEvent<HTMLDivElement>) => {
    event.preventDefault();
    if (inventoryType !== 'player' || !isSlotWithItem(item)) return;

    dispatch(openContextMenu({ item, coords: { x: event.clientX, y: event.clientY } }));
  };

  const handleClick = (event: React.MouseEvent<HTMLDivElement>) => {
    dispatch(closeTooltip());
    if (timerRef.current) clearTimeout(timerRef.current);
    if (event.ctrlKey && isSlotWithItem(item) && inventoryType !== 'shop' && inventoryType !== 'crafting') {
      onDrop({ item: item, inventory: inventoryType });
    } else if (event.altKey && isSlotWithItem(item) && inventoryType === 'player') {
      onUse(item);
    }
  };

  const refs = useMergeRefs([connectRef, ref]);
  const locked =
    !canPurchaseItem(item, { type: inventoryType, groups: inventoryGroups }) || !canCraftItem(item, inventoryType);
  const hotslot = isPlayer && item.slot <= 5;
  const rarity = hasItem ? getRarity(item) : undefined;

  let className = 'nz-slot-wrap';
  if (isOver) className += ' is-over';
  if (isDragging) className += ' is-dragging';
  if (locked) className += ' is-locked';
  if (search) className += matches ? ' is-match' : ' is-dim';

  return (
    <div ref={refs} onContextMenu={handleContext} onClick={handleClick} className={className}>
      <div className="nz-slot" data-rarity={rarity}>
        {hasItem && (
          <div
            className="nz-slot-content"
            onMouseEnter={() => {
              timerRef.current = window.setTimeout(() => {
                dispatch(openTooltip({ item, inventoryType }));
              }, 450) as unknown as number;
            }}
            onMouseLeave={() => {
              dispatch(closeTooltip());
              if (timerRef.current) {
                clearTimeout(timerRef.current);
                timerRef.current = null;
              }
            }}
          >
            <div className="nz-slot-image" style={{ backgroundImage: `url(${getItemUrl(item) || 'none'})` }} />
            {inventoryType === 'shop' && item.price !== undefined && item.price > 0 ? (
              item.currency && item.currency !== 'money' && item.currency !== 'black_money' ? (
                <div className="nz-slot-price">
                  <img src={getItemUrl(item.currency)} alt="" />
                  {item.price.toLocaleString('en-us')}
                </div>
              ) : (
                <div className={`nz-slot-price${item.currency === 'black_money' ? ' is-dirty' : ''}`}>
                  {Locale.$ || '$'}
                  {item.price.toLocaleString('en-us')}
                </div>
              )
            ) : null}
            {item.count > 1 && <div className="nz-slot-count">x{item.count.toLocaleString('en-us')}</div>}
            {inventoryType !== 'shop' && item.durability !== undefined && (
              <div className="nz-slot-durability">
                <div
                  style={{
                    height: `${Math.max(0, Math.min(100, item.durability))}%`,
                    background: durabilityColor(item.durability),
                  }}
                />
              </div>
            )}
            <div className="nz-slot-footer">
              <span className="nz-slot-label">{getItemLabel(item)}</span>
              {item.weight > 0 || isPlayer ? <span className="nz-slot-weight">{formatWeight(item.weight)}</span> : null}
            </div>
          </div>
        )}
      </div>
      {hotslot && <span className="nz-badge">{item.slot}</span>}
    </div>
  );
};

export default React.memo(React.forwardRef(InventorySlot));
