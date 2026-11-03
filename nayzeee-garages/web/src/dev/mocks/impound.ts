/**
 * Impound mocks (browser dev only): owner + staff impound lists with live countdowns and
 * the "Impound vehicle" form, plus stateful handlers for impound:* / impoundForm:submit.
 * Vehicles carry class / stats (via veh()), stored damage and upgrades like in game.
 * Scenario ids: impound-owner, impound-staff, impound-waived, impound-empty, impound-form,
 * impound-form-npc.
 */
import { registerMock } from '../registry';
import { emitNuiMessage, mockNui, onNuiMessage } from '../../lib/nui';
import { defaultInterface, toast } from '../../lib/store';
import type { ImpoundFormData, ImpoundInfo, ImpoundOpenData, ImpoundedVehicle, NuiMessage } from '../../lib/types';
import { dmg, impoundInfo, mods, nowS, veh } from './garage';

const H = 3600;
const D = 86400;
const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
const clone = <T,>(v: T): T => JSON.parse(JSON.stringify(v)) as T;

function impounded(
  model: string,
  label: string,
  make: string,
  plate: string,
  info: Partial<ImpoundInfo>,
  extra: Partial<ImpoundedVehicle> = {},
): ImpoundedVehicle {
  const impound = impoundInfo(info);
  return {
    ...veh(model, label, make, plate, {
      state: 'impounded',
      here: false,
      garageKey: null,
      garageName: impound.locationName,
      canDrive: false,
      reason: `Impounded at ${impound.locationName}`,
      ...extra,
    }),
    impound,
  } as ImpoundedVehicle;
}

function ownerView(): ImpoundOpenData {
  const t = nowS();
  return {
    impound: { id: 5, name: 'Davis Impound', vehicleType: 'car' },
    staff: false,
    vehicles: [
      impounded('euros', 'Annis Euros', 'Annis', 'DVS 23', {
        reason: 'Obstructing a private driveway on Grove Street',
        fee: 500,
        at: t - 26 * H,
        releaseAt: t - 2 * H,
      }, { mileage: 15430, fuel: 61, mods: mods(2, 2, 1, 1, 0, true) }),
      impounded('zr350', 'Annis ZR350', 'Annis', 'DVS RX', {
        reason: 'Abandoned on the freeway shoulder',
        fee: 750,
        byName: 'Officer Delgado',
        at: t - 9 * H,
        releaseAt: t - 20 * 60,
      }, {
        mileage: 18320,
        body: 46,
        engine: 71,
        damage: dmg({ engine: 710, body: 460, doors: [0, 4], windows: [0, 6], tyres: [{ index: 1, state: 1 }, { index: 4, state: 2 }], deformed: true }),
      }),
      impounded('jester4', 'Dinka Jester RR', 'Dinka', 'DVS RR', {
        reason: 'Parked across two disabled bays',
        fee: 350,
        at: t - 40 * 60,
        releaseAt: t + 95,
      }, { nickname: 'Night Shift', mileage: 12482, mods: mods(3, 2, 2, 1, 0, true) }),
      impounded('neon', 'Pfister Neon', 'Pfister', 'SILENT', {
        reason: 'Street racing in Vinewood Hills',
        fee: 2500,
        byName: 'Sgt. Morales',
        at: t - 3 * H,
        releaseAt: t + 21 * H + 12 * 60,
      }, { mileage: 4173, damage: dmg({ body: 820, windows: [7] }), mods: mods(4, 3, 3, 2, 0, true) }),
      impounded('coquette4', 'Invetero Coquette D10', 'Invetero', 'D10 GOLD', {
        reason: 'Held as evidence in an ongoing investigation',
        fee: 5000,
        byName: 'Det. Hayes',
        at: t - 2 * D,
        releaseAt: t - D,
        retrievable: false,
      }, { mileage: 2215 }),
    ],
  };
}

function staffView(): ImpoundOpenData {
  const t = nowS();
  const owner = (name: string): Partial<ImpoundedVehicle> => ({ isOwner: false, ownerName: name });
  return {
    impound: { id: 5, name: 'Davis Impound', vehicleType: 'car' },
    staff: true,
    vehicles: [
      impounded('sultan2', 'Karin Sultan Classic', 'Karin', 'MESA RS', { reason: 'Parked in a fire lane', fee: 500, releaseAt: t - H }, { ...owner('Marcus Reid'), mileage: 7860 }),
      impounded('buffalo4', 'Bravado Buffalo STX', 'Bravado', 'BUFF 4', { reason: 'Unpaid parking tickets (6)', fee: 1200, releaseAt: t + 4 * H }, { ...owner('Lena Ortiz'), mileage: 9312, fuel: 23 }),
      impounded('kuruma', 'Karin Kuruma', 'Karin', 'KRM 404', {
        reason: 'Used in an armed robbery — evidence hold',
        fee: 7500,
        retrievable: false,
        byName: 'Det. Hayes',
        at: t - 3 * D,
      }, {
        ...owner('Dmitri Volkov'),
        mileage: 22140,
        body: 31,
        damage: dmg({ body: 310, doors: [0, 1, 2], windows: [0, 1, 2, 3, 6], deformed: true }),
        mods: mods(2, 2, 2, 2, 5),
      }),
      impounded('granger2', 'Declasse Granger 3600LX', 'Declasse', 'FAMILY 3', { reason: 'Blocking an ambulance bay', fee: 800, releaseAt: t + 35 * 60 }, { ...owner('Priya Shah'), mileage: 41230 }),
      impounded('sanchez', 'Maibatsu Sanchez', 'Maibatsu', 'DIRT 77', { reason: 'Riding on the sidewalk', fee: 250, releaseAt: t - 10 * 60 }, { ...owner('Sam Carter'), mileage: 6620, fuel: 12 }),
      impounded('tenf2', 'Obey 10F Widebody', 'Obey', 'WIDE 10', { reason: 'Excessive noise after midnight', fee: 400, releaseAt: t + 2 * D }, { ...owner('Isabella Rossi'), mileage: 3249 }),
      impounded('euros', 'Annis Euros', 'Annis', 'DVS 23', { reason: 'Obstructing a private driveway', fee: 500, releaseAt: t - 2 * H }, { isOwner: true, mileage: 15430 }),
      impounded('rumpo', 'Bravado Rumpo', 'Bravado', 'DELIVER', {
        reason: 'Abandoned vehicle report',
        fee: 0,
        byName: 'Tow driver Kenji',
        releaseAt: t - 5 * H,
      }, { ...owner('Grace Okafor'), mileage: 94210, body: 58 }),
    ],
  };
}

function emptyView(): ImpoundOpenData {
  return { impound: { id: 9, name: 'Paleto Bay Impound', vehicleType: 'car' }, staff: false, vehicles: [] };
}

const FORM: ImpoundFormData = {
  plate: 'SILENT',
  netId: 4182,
  label: 'Pfister Neon',
  owned: true,
  impounds: [
    { id: 5, name: 'Davis Impound' },
    { id: 9, name: 'Paleto Bay Impound' },
    { id: 11, name: 'Sandy Shores Impound' },
  ],
  defaults: { fee: 500, hours: 0, impoundId: 5 },
};

const NPC_FORM: ImpoundFormData = {
  ...FORM,
  plate: '46EEK572',
  netId: 9921,
  label: 'Vapid Stanier',
  owned: false,
};

/* ───────────────────────── stateful backend ───────────────────────── */

/** Mirrors server/impound.lua retrievalCheck: canDrive + reason per viewer. */
function withRetrieval(d: ImpoundOpenData): ImpoundOpenData {
  const now = nowS();
  for (const v of d.vehicles) {
    let ok = true;
    let reason: string | null = null;
    if (v.blocked) [ok, reason] = [false, 'This vehicle is blocked'];
    else if (v.finance?.overdue) [ok, reason] = [false, 'Finance payment overdue'];
    else if (d.staff) [ok, reason] = [true, null];
    else if (!v.impound.retrievable) [ok, reason] = [false, 'Contact the authorities to release this vehicle'];
    else if (v.impound.releaseAt > now) [ok, reason] = [false, 'Not available yet'];
    v.canDrive = ok;
    v.reason = reason;
  }
  return d;
}

const state: { data: ImpoundOpenData | null } = { data: null };
onNuiMessage((msg: NuiMessage) => {
  if (msg.action === 'open' && msg.data.app === 'impound') state.data = clone(msg.data.data as ImpoundOpenData);
});
/** In game Lua shows these through the notify integration; the browser harness logs them. */
const notify = (type: 'success' | 'error' | 'info', message: string, title?: string) => toast({ type, message, title });

mockNui('impound:refresh', async () => {
  await wait(150);
  return state.data ? clone(state.data) : { ok: false, error: 'No impound open' };
});

mockNui('impound:retrieve', async ({ plate }) => {
  await wait(800);
  const v = state.data?.vehicles.find((x) => x.plate === plate);
  if (!v) return { ok: false, error: 'Vehicle not found' };
  if (!v.impound.retrievable) return { ok: false, error: 'This vehicle has to be released by impound staff first' };
  if (v.impound.releaseAt > nowS()) return { ok: false, error: 'This vehicle is not available yet' };
  if (v.impound.fee >= 5000) return { ok: false, error: 'You do not have enough money in your bank account' };
  setTimeout(() => {
    emitNuiMessage({ action: 'close', data: { app: 'impound' } });
    notify('success', `You paid $${v.impound.fee.toLocaleString('en-US')}. Your ${v.nickname ?? v.label} is outside.`, 'Vehicle released');
  }, 900);
  return null;
});

mockNui('impound:release', async ({ plate, mode }) => {
  await wait(500);
  const d = state.data;
  const v = d?.vehicles.find((x) => x.plate === plate);
  if (!d || !v) return { ok: false, error: 'Vehicle not found' };
  if (mode === 'owner') {
    v.impound.retrievable = true;
    v.impound.releaseAt = nowS() - 1;
  } else {
    d.vehicles = d.vehicles.filter((x) => x.plate !== plate);
  }
  return clone(withRetrieval(d));
});

mockNui('impoundForm:submit', async (req) => {
  await wait(700);
  if (!req.plate) return { ok: false, error: 'No vehicle selected' };
  if (req.reason.toLowerCase().includes('fail')) return { ok: false, error: 'The vehicle moved away — get closer and try again' };
  return null;
});

/* ───────────────────────── scenarios ───────────────────────── */

const settings: NuiMessage = { action: 'settings', data: { ...defaultInterface, defaultView: 'list' } };
const open = (app: 'impound' | 'impoundForm', data: ImpoundOpenData | ImpoundFormData): NuiMessage => ({
  action: 'open',
  data: { app, data },
});

registerMock({ id: 'impound-owner', group: 'Impound', label: 'Impound — owner (countdowns)', messages: [settings, open('impound', withRetrieval(ownerView()))] });
registerMock({ id: 'impound-staff', group: 'Impound', label: 'Impound — staff view', messages: [settings, open('impound', withRetrieval(staffView()))] });
registerMock({
  id: 'impound-waived',
  group: 'Impound',
  label: 'Impound — staff, fees waived',
  messages: [{ ...settings, data: { ...defaultInterface, defaultView: 'grid' } }, open('impound', withRetrieval({ ...staffView(), feeWaived: true }))],
});
registerMock({ id: 'impound-empty', group: 'Impound', label: 'Impound — nothing held', messages: [settings, open('impound', withRetrieval(emptyView()))] });
registerMock({ id: 'impound-form', group: 'Impound', label: 'Impound form (owned)', messages: [open('impoundForm', FORM)] });
registerMock({ id: 'impound-form-npc', group: 'Impound', label: 'Impound form (no owner)', messages: [open('impoundForm', NPC_FORM)] });
