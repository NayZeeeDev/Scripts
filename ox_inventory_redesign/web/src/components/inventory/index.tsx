import React, { useState } from 'react';
import useNuiEvent from '../../hooks/useNuiEvent';
import InventoryControl from './InventoryControl';
import InventoryHotbar from './InventoryHotbar';
import { useAppDispatch, useAppSelector } from '../../store';
import { refreshSlots, setAdditionalMetadata, setupInventory } from '../../store/inventory';
import { useExitListener } from '../../hooks/useExitListener';
import type { Inventory as InventoryProps } from '../../typings';
import RightInventory from './RightInventory';
import LeftInventory from './LeftInventory';
import Tooltip from '../utils/Tooltip';
import { closeTooltip } from '../../store/tooltip';
import InventoryContext from './InventoryContext';
import { closeContextMenu } from '../../store/contextMenu';
import Fade from '../utils/transitions/Fade';
import { selectSettings } from '../../store/ui';
import Toolbar from '../nz/Toolbar';
import PlayerCard from '../nz/PlayerCard';
import GiveModal from '../nz/GiveModal';
import SettingsModal from '../nz/SettingsModal';
import ClothingPanel from '../nz/ClothingPanel';
import { BrandMark } from '../nz/Icons';

const Inventory: React.FC = () => {
  const [inventoryVisible, setInventoryVisible] = useState(false);
  const dispatch = useAppDispatch();
  const settings = useAppSelector(selectSettings);
  const clothingOpen = useAppSelector((state) => state.ui.clothingOpen);
  const config = useAppSelector((state) => state.ui.config);

  useNuiEvent<boolean>('setInventoryVisible', setInventoryVisible);
  useNuiEvent<false>('closeInventory', () => {
    setInventoryVisible(false);
    dispatch(closeContextMenu());
    dispatch(closeTooltip());
  });
  useExitListener(setInventoryVisible);

  useNuiEvent<{
    leftInventory?: InventoryProps;
    rightInventory?: InventoryProps;
  }>('setupInventory', (data) => {
    dispatch(setupInventory(data));
    !inventoryVisible && setInventoryVisible(true);
  });

  useNuiEvent('refreshSlots', (data) => dispatch(refreshSlots(data)));

  useNuiEvent('displayMetadata', (data: Array<{ metadata: string; value: string }>) => {
    dispatch(setAdditionalMetadata(data));
  });

  const compact = settings.view === 'compact';
  const classes = [
    'nz-inventory',
    `view-${settings.view}`,
    `layout-${settings.layout}`,
    `shape-${settings.slotShape}`,
    clothingOpen ? 'is-clothing' : '',
  ].join(' ');

  return (
    <>
      <Fade in={inventoryVisible}>
        <div className={classes}>
          <div className="nz-backdrop" />
          {settings.brand && !compact && (
            <div className="nz-brand">
              {config.brandLogo ? <img src={config.brandLogo} alt="" /> : <BrandMark size="3.4vh" />}
              <span>{config.brandName}</span>
            </div>
          )}

          {clothingOpen ? (
            <div className="nz-stage">
              <div className="nz-col nz-col-left">
                <div className="nz-col-top">{!compact && <Toolbar />}</div>
                <LeftInventory />
                <RightInventory />
              </div>
              {!compact && <InventoryControl />}
              <div className="nz-col nz-col-right">
                <div className="nz-col-top">
                  <PlayerCard />
                </div>
                <ClothingPanel />
              </div>
            </div>
          ) : (
            <div className="nz-stage">
              <div className="nz-col nz-col-left">
                <div className="nz-col-top">{!compact && <Toolbar />}</div>
                <LeftInventory />
              </div>
              {!compact && <InventoryControl />}
              <div className="nz-col nz-col-right">
                <div className="nz-col-top">
                  <PlayerCard />
                </div>
                <RightInventory />
              </div>
            </div>
          )}

          {compact && (
            <div className="nz-dock">
              <InventoryControl>
                <Toolbar compact />
              </InventoryControl>
            </div>
          )}

          <Tooltip />
          <InventoryContext />
          <GiveModal />
          <SettingsModal />
        </div>
      </Fade>
      <InventoryHotbar />
    </>
  );
};

export default Inventory;
