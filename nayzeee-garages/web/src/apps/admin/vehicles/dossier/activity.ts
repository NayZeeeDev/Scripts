/**
 * nz_logs rows of a vehicle (VehicleActivity) → icon, tone and a readable sentence.
 * Unknown events still render: their name is the sentence and their data the details.
 */
import { t } from '@/lib/i18n';
import { distance, hoursLabel, money } from '@/lib/format';
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
  /** identifier → character name, collected from the loaded rows (see nameIndex). */
  names?: Map<string, string>;
}

/** identifier → name from the vehicle record and every name a loaded row carries. */
export function nameIndex(rows: VehicleActivity[], detail: AdminVehicleDetail | null): Map<string, string> {
  const m = new Map<string, string>();
  const add = (id: unknown, name: unknown) => {
    const i = str(id);
    const n = str(name);
    if (i && n && !m.has(i)) m.set(i, n);
  };
  if (detail) {
    add(detail.vehicle.owner, detail.vehicle.ownerName);
    for (const o of detail.ownership) add(o.identifier, o.name);
  }
  for (const r of rows) {
    add(r.actor, r.actorName);
    const d: Data = r.data && typeof r.data === 'object' && !Array.isArray(r.data) ? r.data : {};
    add(d.target, d.targetName);
    add(d.seller, d.sellerName);
    add(d.buyer, d.buyerName);
    add(d.by, d.byName);
    add(d.owner, d.ownerName);
    if (d.type === 'player') {
      add(d.from, d.fromName);
      add(d.to, d.toName);
    }
  }
  return m;
}

/**
 * One drive-out of a garage interior logs both 'vehicle.retrieve' (fromInterior) and
 * 'interior.driveOut' within a second or two: keep only the retrieve row.
 */
export function collapseActivity(rows: VehicleActivity[]): VehicleActivity[] {
  const retrieves = rows.filter((r) => r.event === 'vehicle.retrieve' && yes(r.data?.fromInterior));
  if (!retrieves.length) return rows;
  return rows.filter((r) => r.event !== 'interior.driveOut' || !retrieves.some((x) => Math.abs(x.at - r.at) <= 10));
}

/** A garage key resolved to a real name, or null when only the raw key is known. */
function knownGarage(key: unknown, ctx: Ctx): string | null {
  const k = str(key);
  if (!k) return null;
  const name = garageName(k, ctx.detail, ctx.data);
  return name && name !== k ? name : null;
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
    case 'interior.driveOut': {
      // Real payload: { instance = '<garageKey>:<owner>', plate, spawnIndex }.
      const name = str(d.garageName) ?? knownGarage(d.garage, ctx) ?? knownGarage(str(d.instance)?.split(':')[0], ctx);
      return name
        ? v('route', 'teal', t('Garage'), t('Driven out of the {garage} interior', { garage: name }))
        : v('route', 'neutral', t('Garage'), t('Left the garage interior'));
    }
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
      // 'remove' only carries the target identifier (and byOwner): resolve it from the loaded rows.
      const target = str(d.target);
      const who = str(d.targetName) ?? (target ? ctx.names?.get(target) : undefined) ?? target ?? t('a player');
      if (d.action !== 'remove') return v('users', 'teal', t('Sharing'), t('Shared with {player}', { player: who }));
      if (d.byOwner === false) return v('users', 'neutral', t('Sharing'), t('{player} gave back their access', { player: actorOf(row) }));
      return v('users', 'neutral', t('Sharing'), t('Stopped sharing with {player}', { player: who }));
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
      // mode 'owner' only makes the vehicle collectable: it stays impounded until the owner pays.
      if (d.mode === 'owner') return v('unlock', 'amber', t('Impound'), t('Made collectable at {impound}', { impound: impound() }), feeText ? t('fee {fee}', { fee: feeText }) : null);
      const to = str(d.garageName) ?? knownGarage(d.garage, ctx);
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

/** Keys whose value is a garage key in every event that logs them. */
const GARAGE_KEYS = new Set(['garage', 'garageKey', 'previousGarage']);
/** Keys whose value is a character identifier. */
const PERSON_KEYS = new Set(['owner', 'target', 'seller', 'buyer', 'by']);

/** "Jordan Vale · NZV41207" when the identifier's name is known, else the identifier. */
function person(v: unknown, ctx: Ctx): string {
  const id = str(v);
  if (!id) return humanValue(v);
  const name = ctx.names?.get(id);
  return name && name !== id ? `${name} · ${id}` : id;
}

/** A detail value formatted by its key (money, distance, %, garage / impound names). */
function formatValue(key: string, v: unknown, row: VehicleActivity, d: Data, ctx: Ctx): string {
  const n = numOr(v);
  switch (key) {
    case 'mileage':
      return n !== null ? distance(n) : humanValue(v);
    case 'fee':
    case 'price':
    case 'amount':
    case 'balance':
      return n !== null ? money(n) : humanValue(v);
    case 'fuel':
    case 'engine':
    case 'body':
      return n !== null ? `${Math.round(n)}%` : humanValue(v);
    case 'hours':
      return n !== null ? hoursLabel(n) : humanValue(v);
    case 'impound':
      return impoundName(v, ctx.detail, ctx.data) ?? humanValue(v);
    case 'from':
    case 'to': {
      // Garage keys for garage moves; identifiers for player transfers, nicknames for renames.
      const garageMove = row.event === 'vehicle.garage' || (row.event === 'vehicle.transfer' && d.type !== 'player');
      if (garageMove) return garageName(v, ctx.detail, ctx.data) ?? humanValue(v);
      return row.event === 'vehicle.transfer' ? person(v, ctx) : humanValue(v);
    }
    default:
      if (GARAGE_KEYS.has(key)) return garageName(v, ctx.detail, ctx.data) ?? humanValue(v);
      if (PERSON_KEYS.has(key)) return person(v, ctx);
      return humanValue(v);
  }
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

/** Key/value pairs for the expanded details of an entry, formatted by key. */
export function activityDetails(row: VehicleActivity, ctx: Ctx): { key: string; label: string; value: string }[] {
  const d: Data = row.data && typeof row.data === 'object' && !Array.isArray(row.data) ? row.data : {};
  return Object.entries(d)
    .filter(([k]) => !HIDDEN.has(k))
    .map(([k, val]) => ({ key: k, label: t(humanKey(k)), value: formatValue(k, val, row, d, ctx) }));
}

/** Who did it: the character name, the server, or the identifier. */
export function actorOf(row: VehicleActivity): string {
  const fromData = row.data && typeof row.data === 'object' ? (row.data as Data).actorName : null;
  return row.actorName || (typeof fromData === 'string' && fromData) || row.actor || t('Server');
}
