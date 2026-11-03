/**
 * Garage-for-sale mocks (browser dev only). Buying closes the card and opens the new
 * private garage (like the Lua side does); the tour closes the card with a toast.
 * Scenario ids: forsale, forsale-sold-out, forsale-broke, forsale-unlimited.
 */
import { registerMock } from '../registry';
import { emitNuiMessage, mockNui } from '../../lib/nui';
import type { ForSaleData, NuiMessage } from '../../lib/types';
import { boughtGarage } from './garage';

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

const LA_MESA: ForSaleData = {
  locationId: 22,
  name: 'La Mesa Motor Club',
  price: 50000,
  available: 2,
  total: 3,
  storage: 'shared',
  spaces: 8,
  interiorName: 'Executive Collection',
  canTour: true,
  canAfford: true,
};

const open = (data: ForSaleData): NuiMessage => ({ action: 'open', data: { app: 'forSale', data } });
const notify = (type: 'success' | 'info' | 'error', message: string, title?: string) =>
  emitNuiMessage({ action: 'notify', data: { type, message, title } });

mockNui('forSale:tour', async () => {
  await wait(600);
  emitNuiMessage({ action: 'close', data: { app: 'forSale' } });
  notify('info', 'Have a look around — walk to the exit marker to leave.', 'Interior tour');
  return null;
});

mockNui('forSale:buy', async ({ locationId }) => {
  await wait(900);
  if (locationId === 41) return { ok: false, error: 'Someone bought the last copy a moment ago' };
  emitNuiMessage({ action: 'close', data: { app: 'forSale' } });
  notify('success', 'La Mesa Motor Club is yours. Add members from the Manage button.', 'Garage purchased');
  setTimeout(() => emitNuiMessage({ action: 'open', data: { app: 'garage', data: boughtGarage() } }), 400);
  return null;
});

registerMock({ id: 'forsale', group: 'For sale', label: 'Garage for sale', messages: [open(LA_MESA)] });
registerMock({
  id: 'forsale-sold-out',
  group: 'For sale',
  label: 'Sold out',
  messages: [open({ ...LA_MESA, available: 0, total: 1, canTour: true })],
});
registerMock({
  id: 'forsale-broke',
  group: 'For sale',
  label: 'Cannot afford (personal storage)',
  messages: [
    open({
      ...LA_MESA,
      locationId: 23,
      name: 'Vinewood Hills Vault',
      price: 1250000,
      available: 1,
      total: 1,
      storage: 'personal',
      spaces: 20,
      interiorName: 'Vinewood Car Club',
      canAfford: false,
    }),
  ],
});
registerMock({
  id: 'forsale-unlimited',
  group: 'For sale',
  label: 'Unlimited copies, no interior',
  messages: [
    open({
      ...LA_MESA,
      locationId: 41,
      name: 'Elysian Island Lockups',
      price: 18500,
      available: 999999,
      total: 0,
      storage: 'personal',
      spaces: 4,
      interiorName: null,
      canTour: false,
    }),
  ],
});
