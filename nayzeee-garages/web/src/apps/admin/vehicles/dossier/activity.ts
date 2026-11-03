/**
 * nz_logs rows of a vehicle (VehicleActivity) → icon, tone and a readable sentence.
 * Unknown events still render: their name is the sentence and their data the details.
 */
import { t } from '@/lib/i18n';
import { distance, money } from '@/lib/format';
import type { AdminOpenData, AdminVehicleDetail, VehicleActivity } from '@/lib/types';
import type { IconName } from '@/components/ui';
import { garageName, impoundName } from './data';

export type ActivityTone = 'teal' | 'neutral' | 'amber' | 'red' | 'blue';

export interface ActivityView {
  icon: IconName;
  tone: ActivityTone;
  /** Short family label ("Garage", "Impound"…). */
  family: string;
  sentence: string;
  /** Extra short facts shown after the sentence (fee, reason…). */
  extra: string | null;
  /** False for events this UI does not know. */
  known: boolean;
}

type Data = Record<string, unknown>;

const str = (v: unknown): string | null => (typeof v === 'string' && v.trim() !== '' ? v : typeof v === 'number' ? String(v) : null);
const numOr = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : typeof v === 'string' && v.trim() !== '' && Number.isFinite(Number(v)) ? Number(v) : null);
const yes = (v: unknown) => v === true || v === 1 || v === 'true';

interface Ctx {
  detail: AdminVehicleDetail | null;
  data: AdminOpenData;
}

const changedLabels = (): Record<string, string> => ({
  plate: t('plate'),
  details: t('details'),
  owner: t('owner'),
  props: t('modifications'),
  impound: t('impound'),
  finance: t('finance'),
  blocked: t('block state'),
  service: t('service history'),
});

export function describeActivity(row: VehicleActivity, ctx: Ctx): ActivityView {
  const d: Data = row.data && typeof row.data === 'object' && !Array.isArray(row.data) ? row.data : {};
  const garage = (key: unknown, name?: unknown) => str(name) ?? garageName(key, ctx.detail, ctx.data) ?? t('a garage');
  const impound = () => str(d.impoundName) ?? impoundName(d.impound, ctx.detail, ctx.data) ?? t('the impound');
  const fee = numOr(d.fee);
  const feeText = fee && fee > 0 ? money(fee) : null;
  const v = (icon: IconName, tone: ActivityTone, family: string, sentence: string, extra: string | null = null): ActivityView => ({
    icon,
    tone,
    family,
    sentence,
    extra,
    known: true,
  });

  switch (row.event) {
    case 'vehicle.retrieve': {
      if (yes(d.rolledBack)) return v('warning', 'amber', t('Garage'), t('Take-out at {garage} was rolled back', { garage: garage(d.garage) }), str(d.reason));
      if (yes(d.fromImpound)) return v('route', 'teal', t('Garage'), t('Driven out of the impound'), feeText);
      if (yes(d.fromInterior)) return v('route', 'teal', t('Garage'), t('Driven out of the {garage} interior', { garage: garage(d.garage) }), feeText);
      return v('route', 'teal', t('Garage'), t('Taken out at {garage}', { garage: garage(d.garage, d.garageName) }), feeText);
    }
    case 'interior.driveOut':
      return v('route', 'teal', t('Garage'), t('Driven out of the {garage} interior', { garage: garage(d.garage, d.garageName) }));
    case 'vehicle.store': {
      if (yes(d.spawner)) return v('parking', 'neutral', t('Garage'), t('Returned to {garage}', { garage: garage(d.garage, d.garageName) }));
      const km = numOr(d.mileage);
      return v('parking', 'neutral', t('Garage'), t('Stored at {garage}', { garage: garage(d.garage, d.garageName) }), km !== null ? distance(km) : null);
    }
    case 'vehicle.spawnFailed':
      return v('warning', 'amber', t('Garage'), t('Could not be spawned at {garage}', { garage: garage(d.garage) }));
    case 'vehicle.recover':
      return v('refresh', 'amber', t('Garage'), t('Recovered to {garage}', { garage: garage(d.garage, d.garageName) }), feeText);
    case 'vehicle.garage':
      return v('garage', 'neutral', t('Garage'), t('Moved to {garage} by a script', { garage: garage(d.to) }));
    case 'vehicle.transfer': {
      if (d.type === 'player') {
        return v('transfer', 'blue', t('Ownership'), t('Transferred from {from} to {to}', { from: str(d.fromName) ?? t('a player'), to: str(d.toName) ?? t('a player') }), feeText);
      }
      return v('transfer', 'neutral', t('Garage'), t('Moved from {from} to {to}', { from: garage(d.from), to: garage(d.to, d.toName) }), feeText);
    }
    case 'vehicle.share': {
      const who = str(d.targetName) ?? t('a player');
      return d.action === 'remove'
        ? v('users', 'neutral', t('Sharing'), t('Stopped sharing with {player}', { player: who }))
        : v('users', 'teal', t('Sharing'), t('Shared with {player}', { player: who }));
    }
    case 'vehicle.sell': {
      const price = numOr(d.price);
      const priceText = price !== null ? money(price) : null;
      if (d.action === 'sold') {
        return v('tag', 'blue', t('Ownership'), t('Sold by {seller} to {buyer}', { seller: str(d.sellerName) ?? t('a player'), buyer: str(d.buyerName) ?? t('a player') }), priceText);
      }
      if (d.action === 'declined') return v('tag', 'neutral', t('Ownership'), t('Sale offer declined'), priceText);
      return v('tag', 'neutral', t('Ownership'), t('Offered for sale to {buyer}', { buyer: str(d.buyerName) ?? t('a player') }), priceText);
    }
    case 'vehicle.rename': {
      const to = str(d.to);
      return v('edit', 'neutral', t('Details'), to ? t('Renamed to “{name}”', { name: to }) : t('Nickname removed'));
    }
    case 'vehicle.favourite':
      return v('star', 'neutral', t('Details'), yes(d.value) ? t('Marked as a favourite') : t('Removed from favourites'));
    case 'vehicle.finance': {
      const amount = numOr(d.amount);
      if (yes(d.paidOff)) return v('money', 'teal', t('Finance'), t('Finance paid off'), amount !== null ? money(amount) : null);
      const bal = numOr(d.balance);
      return v('money', 'teal', t('Finance'), t('Finance payment of {amount}', { amount: money(amount ?? 0) }), bal !== null ? t('{amount} left', { amount: money(bal) }) : null);
    }
    case 'vehicle.service': {
      const item = str(d.item) ?? t('Service');
      const shop = str(d.shop);
      return v('wrench', 'teal', t('Service'), shop ? t('{item} at {shop}', { item, shop }) : t('Serviced: {item}', { item }));
    }
    case 'vehicle.add':
      return v('userPlus', 'blue', t('Ownership'), t('Registered to {owner}', { owner: str(d.ownerName) ?? str(d.owner) ?? t('a player') }));
    case 'vehicle.ownerRecord':
      return v('history', 'blue', t('Ownership'), t('Ownership record added for {name}', { name: str(d.name) ?? t('a player') }));
    case 'impound.add': {
      const reason = str(d.reason);
      if (yes(d.npc)) return v('impound', 'red', t('Impound'), t('Towed to {impound}', { impound: impound() }), reason);
      return v('impound', 'red', t('Impound'), feeText ? t('Impounded at {impound} · {fee}', { impound: impound(), fee: feeText }) : t('Impounded at {impound}', { impound: impound() }), reason);
    }
    case 'impound.release': {
      const to = str(d.garageName);
      return v('unlock', 'amber', t('Impound'), to ? t('Released from {impound} to {garage}', { impound: impound(), garage: to }) : t('Released from {impound}', { impound: impound() }));
    }
    case 'impound.retrieve':
      return v('checkCircle', 'teal', t('Impound'), yes(d.staff) ? t('Released by staff at {impound}', { impound: impound() }) : t('Collected from {impound}', { impound: impound() }), feeText ? t('paid {fee}', { fee: feeText }) : null);
    case 'admin.vehicle.update': {
      const labels = changedLabels();
      const changed = (Array.isArray(d.changed) ? d.changed : d.changed && typeof d.changed === 'object' ? Object.values(d.changed as object) : [])
        .map((x) => (typeof x === 'string' ? labels[x] ?? x : null))
        .filter((x): x is string => !!x);
      const np = str(d.newPlate);
      if (np) return v('crown', 'blue', t('Admin'), t('Plate changed to {plate}', { plate: np }), changed.length > 1 ? t('also {list}', { list: changed.filter((c) => c !== labels.plate).join(', ') }) : null);
      return v('crown', 'blue', t('Admin'), changed.length ? t('Admin edited the {list}', { list: changed.join(', ') }) : t('Admin edit'));
    }
    case 'admin.vehicle.assign':
      return v('userPlus', 'blue', t('Admin'), t('Assigned by an admin'), garage(d.garage));
    case 'admin.vehicle.delete':
      return v('trash', 'red', t('Admin'), t('Deleted by an admin'));
    default:
      break;
  }
  if (row.event.startsWith('security.')) {
    return v('warning', 'red', t('Security'), t('Security alert: {reason}', { reason: str(d.reason) ?? row.event.slice(9) }));
  }
  return { icon: 'hash', tone: 'neutral', family: t('Other'), sentence: row.event, extra: null, known: false };
}

/** Data keys never shown in the details (already in the row or internal). */
const HIDDEN = new Set(['plate', 'actorName', 'actorSource']);

/** "impoundName" → "Impound name". */
function humanKey(k: string): string {
  const s = k.replace(/[_-]+/g, ' ').replace(/([a-z0-9])([A-Z])/g, '$1 $2').toLowerCase();
  return s.charAt(0).toUpperCase() + s.slice(1);
}

function humanValue(v: unknown): string {
  if (v === true) return t('Yes');
  if (v === false) return t('No');
  if (v === null || v === undefined) return '—';
  if (typeof v === 'number') return Number.isInteger(v) ? v.toLocaleString('en-US') : String(Math.round(v * 100) / 100);
  if (typeof v === 'string') return v;
  try {
    return JSON.stringify(v);
  } catch {
    return String(v);
  }
}

/** Key/value pairs for the expanded details of an entry. */
export function activityDetails(row: VehicleActivity): { key: string; label: string; value: string }[] {
  const d = row.data && typeof row.data === 'object' && !Array.isArray(row.data) ? row.data : {};
  return Object.entries(d)
    .filter(([k]) => !HIDDEN.has(k))
    .map(([k, val]) => ({ key: k, label: t(humanKey(k)), value: humanValue(val) }));
}

/** Who did it: the character name, the server, or the identifier. */
export function actorOf(row: VehicleActivity): string {
  const fromData = row.data && typeof row.data === 'object' ? (row.data as Data).actorName : null;
  return row.actorName || (typeof fromData === 'string' && fromData) || row.actor || t('Server');
}
