/**
 * Sale contract mocks (browser dev only). Scenario ids:
 *   contract-draft, contract-draft-alone, contract-draft-sent, contract-draft-declined,
 *   contract-draft-expired, contract-review,
 *   contract-review-broke, contract-review-topup, contract-review-late, contract-review-expired,
 *   contract-review-withdrawn, contract-view, contract-view-unverified.
 * Sending a draft: buyer Jade Ortiz (7) declines after 2.5 s, Priya Nair (21) signs after 3 s,
 * Tomás Reyes (12) never answers (the countdown runs out, then the server's 'expired'). After a
 * "no" that buyer waits RESEND_IN s for a new contract. contract-review-topup: the buyer
 * has the money at the first balance check (5 s); contract-review-broke never does.
 */
import { registerMock } from '../registry';
import { emitNuiMessage, mockNui } from '../../lib/nui';
import type { ContractOpenData, ContractVehicle, NuiMessage, PlayerOption } from '../../lib/types';

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
const now = () => Math.floor(Date.now() / 1000);

/** A cursive signature in the 400x140 pad (looping trochoid + underline), as the pad records it. */
function signature(seed: number, loops: number): string {
  const pts: string[] = [];
  const steps = 150;
  for (let i = 0; i <= steps; i++) {
    const t = i / steps;
    const phase = Math.PI * 2 * loops * t + seed;
    const env = 1 - Math.pow(t - 0.45, 2) * 1.6;
    const x = 46 + t * 250 - Math.sin(phase) * 15;
    const y = 74 - Math.cos(phase) * 27 * env * (0.72 + 0.38 * Math.sin(t * 7 + seed)) - Math.sin(t * 5 + seed) * 6;
    pts.push(`${i === 0 ? 'M' : 'L'}${Math.round(x)} ${Math.round(y)}`);
  }
  pts.push('M70 114');
  for (let i = 1; i <= 18; i++) pts.push(`L${70 + i * 15} ${Math.round(113 - Math.sin(i / 6) * 7)}`);
  return pts.join('');
}

const ELEGY: ContractVehicle = {
  plate: 'RETRO 6',
  model: 'elegy',
  hash: -1,
  label: 'Elegy Retro Custom',
  make: 'Annis',
  image: 'elegy',
  classLabel: 'Sports',
  vehicleType: 'car',
  nickname: 'Midnight',
  mileage: 28360,
  engine: 88,
  body: 64,
  distance: 3.2,
};

const SULTAN: ContractVehicle = {
  plate: 'MESA RS',
  model: 'sultan',
  hash: -2,
  label: 'Sultan Classic',
  make: 'Karin',
  image: 'sultan',
  classLabel: 'Sedans',
  vehicleType: 'car',
  nickname: null,
  mileage: 91204,
  engine: 46,
  body: 33,
  distance: 7.8,
};

const KURUMA: ContractVehicle = {
  plate: 'KRM 404',
  model: 'kuruma',
  hash: -3,
  label: 'Kuruma',
  make: 'Karin',
  image: 'kuruma',
  classLabel: 'Sports',
  vehicleType: 'car',
  nickname: null,
  mileage: 12044,
  engine: 97,
  body: 95,
  distance: 5.1,
  blocked: 'Pay off the finance before selling',
};

const BUYERS: PlayerOption[] = [
  { serverId: 7, name: 'Jade Ortiz' },
  { serverId: 12, name: 'Tomás Reyes' },
  { serverId: 21, name: 'Priya Nair' },
];

const SELLER = { name: 'Marcus Hale', serverId: 3 };
const TERMS = 'Sold as seen, without warranty.\nAll keys are handed over on signing.\nNew tyres fitted in October; the spare is in the boot.';

const open = (data: ContractOpenData): NuiMessage => ({ action: 'open', data: { app: 'contract', data } });
/** Config.Contracts.resendCooldown of the mocks */
const RESEND_IN = 60;

const status = (
  value: 'declined' | 'signed' | 'expired' | 'withdrawn' | 'cancelled' | 'failed',
  copy = false,
): NuiMessage => ({
  action: 'update',
  data: {
    app: 'contract',
    data: { status: value, copy, resendIn: value === 'declined' || value === 'expired' ? RESEND_IN : null },
  },
});

/** buyers who said no in this page session (the server refuses a new contract to them) */
const sendRefused = new Set<number>();

/** contract ids of the review scenarios that never get the money */
const BROKE_ID = '9B1D3E77';

const draft = (buyers: PlayerOption[] = BUYERS): ContractOpenData => ({
  mode: 'draft',
  seller: SELLER,
  vehicles: [ELEGY, KURUMA, SULTAN],
  buyers,
  maxPrice: 10000000,
  account: 'bank',
  expireSeconds: 120,
});

/** The seller used a blank contract again while their contract waits for Priya Nair. */
const draftSent = (): ContractOpenData => ({
  mode: 'draft',
  seller: SELLER,
  vehicles: [ELEGY],
  buyers: [BUYERS[2]],
  maxPrice: 10000000,
  account: 'bank',
  expireSeconds: 120,
  sent: {
    id: '7C30E5A2',
    expiresIn: 71,
    buyer: BUYERS[2],
    plate: ELEGY.plate,
    price: 48500,
    terms: TERMS,
    signature: signature(0.4, 6),
  },
});

const review = (patch: Partial<Extract<ContractOpenData, { mode: 'review' }>> = {}): ContractOpenData => ({
  mode: 'review',
  contractId: '4F2A91C0',
  vehicle: { ...ELEGY, distance: null },
  seller: SELLER,
  buyer: { name: 'Jade Ortiz', serverId: 7 },
  price: 48500,
  terms: TERMS,
  sellerSignature: signature(0.4, 6),
  createdAt: now() - 6,
  expiresIn: 114,
  canAfford: true,
  account: 'bank',
  ...patch,
});

const view = (verified: boolean): ContractOpenData => ({
  mode: 'view',
  contractId: '4F2A91C0',
  copy: 'buyer',
  vehicle: { ...ELEGY, distance: null },
  seller: SELLER,
  buyer: { name: 'Jade Ortiz' },
  price: 48500,
  account: 'bank',
  terms: TERMS,
  sellerSignature: signature(0.4, 6),
  buyerSignature: signature(2.2, 5),
  createdAt: now() - 86400 * 3 - 95,
  signedAt: now() - 86400 * 3,
  verified,
});

mockNui('contract:refresh', async () => {
  await wait(400);
  return { vehicles: [ELEGY, KURUMA, SULTAN], buyers: BUYERS };
});

mockNui('contract:send', async ({ buyer, price }) => {
  await wait(700);
  if (price > 10000000) return { ok: false, error: 'Enter a price between $1 and $10,000,000' };
  if (sendRefused.has(buyer)) {
    return { ok: false, error: `${BUYERS.find((b) => b.serverId === buyer)?.name ?? 'The buyer'} turned down your last contract: wait 52 s before sending another` };
  }
  if (buyer === 7) setTimeout(() => (sendRefused.add(7), emitNuiMessage(status('declined'))), 2500);
  if (buyer === 21) setTimeout(() => emitNuiMessage(status('signed', true)), 3000);
  if (buyer === 12) setTimeout(() => (sendRefused.add(12), emitNuiMessage(status('expired'))), 25300);
  return { contractId: '4F2A91C0', expiresIn: buyer === 12 ? 25 : 120 };
});

mockNui('contract:sign', async () => {
  await wait(900);
  return { signedAt: now(), key: 'item', copy: true };
});

mockNui('contract:balance', async ({ contractId }) => {
  await wait(150);
  return { canAfford: contractId !== BROKE_ID };
});

mockNui('contract:decline', async () => {
  await wait(300);
  return null;
});

registerMock({ id: 'contract-draft', group: 'Contract', label: 'Draft (seller)', messages: [open(draft())] });
registerMock({ id: 'contract-draft-alone', group: 'Contract', label: 'Draft, nobody nearby', messages: [open(draft([]))] });
registerMock({ id: 'contract-draft-sent', group: 'Contract', label: 'Draft reopened, waiting', messages: [open(draftSent())] });
registerMock({
  id: 'contract-draft-declined',
  group: 'Contract',
  label: 'Draft, buyer declined',
  messages: [open(draftSent()), status('declined')],
});
registerMock({
  id: 'contract-draft-expired',
  group: 'Contract',
  label: 'Draft, contract expired',
  messages: [open(draftSent()), status('expired')],
});
registerMock({ id: 'contract-review', group: 'Contract', label: 'Review (buyer)', messages: [open(review())] });
registerMock({
  id: 'contract-review-broke',
  group: 'Contract',
  label: 'Review, cannot afford',
  messages: [open(review({ contractId: BROKE_ID, canAfford: false, price: 148500, terms: '' }))],
});
registerMock({
  id: 'contract-review-topup',
  group: 'Contract',
  label: 'Review, money arrives',
  messages: [open(review({ contractId: '5E81A0D4', canAfford: false }))],
});
registerMock({ id: 'contract-review-late', group: 'Contract', label: 'Review, 24 s left', messages: [open(review({ expiresIn: 24 }))] });
registerMock({ id: 'contract-review-expired', group: 'Contract', label: 'Review, expired', messages: [open(review({ expiresIn: 0 }))] });
registerMock({
  id: 'contract-review-withdrawn',
  group: 'Contract',
  label: 'Review, withdrawn by the seller',
  messages: [open(review()), status('withdrawn')],
});
registerMock({ id: 'contract-view', group: 'Contract', label: 'Signed copy', messages: [open(view(true))] });
registerMock({ id: 'contract-view-unverified', group: 'Contract', label: 'Signed copy, not on record', messages: [open(view(false))] });
