/**
 * Root: mounts every app (each renders nothing while closed) and the in-world widgets.
 * File paths and export names here are part of the contract — see docs/UI_KIT.md.
 * Notifications: toast() always sends them to Lua (bridge/client/notify.lua), which draws them
 * back here in <Toasts /> while one of our windows holds NUI focus (FiveM puts the focused page
 * above every other resource's NUI) and otherwise uses the configured notify integration.
 */
import { useEffect } from 'react';
import { useUi } from './lib/store';
import { isBrowser } from './lib/nui';
import { Toasts } from './components/Toasts';
import { Prompt } from './apps/hud/Prompt';
import { Hint } from './apps/hud/Hint';
import { InteriorHud } from './apps/interior/InteriorHud';
import { InteriorPanelApp } from './apps/interior/InteriorPanelApp';
import { GarageApp } from './apps/garage/GarageApp';
import { ImpoundApp } from './apps/impound/ImpoundApp';
import { ImpoundFormApp } from './apps/impound/ImpoundFormApp';
import { ForSaleApp } from './apps/forsale/ForSaleApp';
import { SetupApp } from './apps/setup/SetupApp';
import { CreatorApp } from './apps/creator/CreatorApp';
import { AdminApp } from './apps/admin/AdminApp';
import { KeysApp } from './apps/keys/KeysApp';
import { LocksmithApp } from './apps/locksmith/LocksmithApp';
import { ContractApp } from './apps/contract/ContractApp';
import { FobApp } from './apps/fob/FobApp';
import { MinigameApp } from './apps/minigame/MinigameApp';
import { KeyAdminApp } from './apps/keyadmin/KeyAdminApp';

export function App() {
  const anyOpen = useUi((s) => Object.values(s.apps).some((a) => a.open));

  useEffect(() => {
    document.body.classList.toggle('nz-browser', isBrowser);
  }, []);

  return (
    <div className={`nz-root${anyOpen ? ' nz-root--active' : ''}`}>
      <Prompt />
      <Hint />
      <InteriorHud />
      <InteriorPanelApp />
      <SetupApp />
      <CreatorApp />
      <GarageApp />
      <ImpoundApp />
      <ImpoundFormApp />
      <ForSaleApp />
      <AdminApp />
      <KeysApp />
      <LocksmithApp />
      <ContractApp />
      <FobApp />
      <MinigameApp />
      <KeyAdminApp />
      <Toasts />
    </div>
  );
}
