/**
 * Locksmith app (app 'locksmith', docs/CARLOCK.md §9). Two panes like the garage Showroom:
 * left the vehicles the locksmith can work on (parked nearby first, then your keys and
 * vehicles), right the selected vehicle and the services — Duplicate a key, Program a key,
 * Change the locks — with price, materials (have / need) and why a service is not possible,
 * then the order dock (Pay). Legal shops serve owners and key holders; illegal shops work on any
 * vehicle parked nearby (the police may hear about it). Changing the locks is for owners only.
 * Every paid service is confirmed first (Pay / Enter open the confirmation, its button pays).
 * The server re-checks everything (locksmith:service) and answers with fresh data.
 * Keyboard: ↑ ↓ vehicle, ← → service, Enter order (then Enter to pay), Esc close.
 */
import { useEffect, useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import {
  Badge,
  Button,
  ConfirmDialog,
  EmptyState,
  Icon,
  IconButton,
  KeyHint,
  PlateTag,
  VehicleImage,
  Window,
  cx,
} from '@/components/ui';
import type { IconName } from '@/components/ui';
import { useApp, useUi, toast } from '@/lib/store';
import { useEscape } from '@/lib/escape';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import { money } from '@/lib/format';
import type { LocksmithOpenData, LocksmithService, LocksmithServiceId, LocksmithVehicle } from '@/lib/types';
import './locksmith.css';

export function LocksmithApp() {
  const { open, data, close } = useApp('locksmith');
  useEscape(close, open);
  const clean = useMemo(() => (data ? normalize(data) : null), [data]);
  if (!open || !clean) return null;
  return <Locksmith key={clean.id} data={clean} close={close} />;
}

/** Lua drops nil fields and sends empty tables as {} or []: make every list a list. */
function normalize(d: LocksmithOpenData): LocksmithOpenData {
  const list = <T,>(v: T[] | unknown): T[] => (Array.isArray(v) ? (v as T[]) : []);
  return {
    ...d,
    money: Number(d.money) || 0,
    services: list<LocksmithService>(d.services).map((s) => ({ ...s, materials: list(s.materials) })),
    vehicles: list<LocksmithVehicle>(d.vehicles).map((v) => ({
      ...v,
      blocked: v.blocked && !Array.isArray(v.blocked) ? v.blocked : {},
      keyItems: Number(v.keyItems) || 0,
      label: v.label ?? '',
      make: v.make ?? '',
      image: v.image ?? null,
    })),
  };
}

const ORDER: LocksmithServiceId[] = ['duplicate', 'program', 'rekey'];

const nameOf = (v: LocksmithVehicle) => (v.nickname ?? '').trim() || v.label || t('Unknown vehicle');

function serviceTitle(id: LocksmithServiceId): string {
  return id === 'duplicate' ? t('Duplicate a key') : id === 'program' ? t('Program a key') : t('Change the locks');
}

function serviceIcon(id: LocksmithServiceId): IconName {
  return id === 'duplicate' ? 'copy' : id === 'program' ? 'key' : 'lock';
}

function serviceText(id: LocksmithServiceId, d: LocksmithOpenData, v: LocksmithVehicle | null): string {
  const word = v?.keyType === 'fob' ? t('fob') : t('key');
  if (id === 'duplicate') {
    return d.mode === 'virtual'
      ? t('Virtual keys are given from the key ring, not copied.')
      : t('A copy of a {kind} you carry. It works until the locks change.', { kind: word });
  }
  if (id === 'program') {
    if (d.mode === 'virtual') {
      return d.illegal
        ? t('A temporary key ({hours} h) for a vehicle parked here. It opens it, not its tracker.', { hours: Math.round(d.tempHours) })
        : t('Owners give keys from the key ring: a licensed shop programs none.');
    }
    return d.illegal
      ? t('A brand-new {kind} for a vehicle parked here, no key needed. Unregistered: it opens the car, not its tracker.', { kind: word })
      : t('A brand-new {kind} for a vehicle you own or hold a key for, parked here.', { kind: word });
  }
  return d.mode === 'virtual'
    ? t('Owners only. New locks: every key given to others stops working.')
    : t('Owners only. New locks and a new {kind}: every other key stops working.', { kind: word });
}

/** What the customer walks away with. */
function outcome(id: LocksmithServiceId, d: LocksmithOpenData, v: LocksmithVehicle): string {
  const fob = v.keyType === 'fob';
  if (id === 'duplicate') return fob ? t('Spare fob · {plate}', { plate: v.plate }) : t('Spare key · {plate}', { plate: v.plate });
  if (id === 'program') {
    if (d.mode === 'virtual') return t('Temporary key · {hours} h', { hours: Math.round(d.tempHours) });
    return fob ? t('New fob · {plate}', { plate: v.plate }) : t('New key · {plate}', { plate: v.plate });
  }
  if (d.mode === 'virtual') return t('New locks');
  return fob ? t('New locks + fob') : t('New locks + key');
}

/** Title of the confirmation: what is bought, for how much. */
function confirmTitle(id: LocksmithServiceId, d: LocksmithOpenData, v: LocksmithVehicle, price: number): string {
  const kind = v.keyType === 'fob' ? t('fob') : t('key');
  if (price <= 0) return t('{service}?', { service: serviceTitle(id) });
  const p = money(price);
  if (id === 'duplicate') return t('Pay {price} for a spare {kind}?', { price: p, kind });
  if (id === 'program') {
    return d.mode === 'virtual' ? t('Pay {price} for a temporary key?', { price: p }) : t('Pay {price} for a new {kind}?', { price: p, kind });
  }
  return t('Pay {price} to change the locks?', { price: p });
}

interface Done {
  plate: string;
  service: LocksmithServiceId;
  message: string;
  at: number;
}

function Locksmith({ data, close }: { data: LocksmithOpenData; close: () => void }) {
  const services = useMemo(
    () => ORDER.map((id) => data.services.find((s) => s.id === id)).filter((s): s is LocksmithService => !!s && s.enabled),
    [data.services],
  );
  const nearby = useMemo(
    () => data.vehicles.filter((v) => v.nearby).sort((a, b) => (a.distance ?? 0) - (b.distance ?? 0)),
    [data.vehicles],
  );
  const others = useMemo(() => data.vehicles.filter((v) => !v.nearby), [data.vehicles]);
  const flat = useMemo(() => [...nearby, ...others], [nearby, others]);

  const [plate, setPlate] = useState<string | null>(flat[0]?.plate ?? null);
  const v = flat.find((x) => x.plate === plate) ?? flat[0] ?? null;
  const firstOpen = (veh: LocksmithVehicle | null) =>
    services.find((s) => s.offered && !(veh?.blocked ?? {})[s.id])?.id ?? services[0]?.id ?? null;
  const [serviceId, setServiceId] = useState<LocksmithServiceId | null>(() => firstOpen(v));
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<Done | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  // the order waiting for its confirmation (vehicle + service at the moment Pay was pressed)
  const [confirm, setConfirm] = useState<{ plate: string; service: LocksmithServiceId } | null>(null);

  // picking another vehicle picks the first service it can get
  const pick = (p: string) => {
    setPlate(p);
    const veh = flat.find((x) => x.plate === p) ?? null;
    const cur = services.find((s) => s.id === serviceId);
    if (!cur || !cur.offered || (veh?.blocked ?? {})[cur.id]) setServiceId(firstOpen(veh));
  };

  const service = services.find((s) => s.id === serviceId) ?? null;
  const blocked = v && service ? ((v.blocked ?? {})[service.id] ?? null) : null;
  const missing = service ? service.materials.filter((m) => m.have < m.count) : [];
  const short = service ? service.price > data.money : false;
  let reason: string | null = null;
  if (!v) reason = t('Pick a vehicle');
  else if (!service) reason = t('Pick a service');
  else if (!service.offered) reason = service.reason ?? t('Not offered here');
  else if (blocked) reason = blocked;
  else if (missing.length)
    reason = t('Missing materials: {list}', { list: missing.map((m) => `${m.count - m.have}× ${m.label}`).join(', ') });
  else if (short) reason = t('You cannot afford this: you have {money}', { money: money(data.money) });
  const canPay = reason === null && !busy;

  /** Pay / Enter: ask first (money is taken, materials used; new locks lock others out). */
  const order = () => {
    if (!v || !service || !canPay) return;
    setConfirm({ plate: v.plate, service: service.id });
  };

  /** The confirmation's button: the server checks and runs the service. */
  const pay = async () => {
    if (!confirm || busy) return;
    const { plate: p, service: sid } = confirm;
    setBusy(true);
    const res = await request('locksmith:service', { locksmithId: data.id, service: sid, plate: p });
    setBusy(false);
    setConfirm(null);
    if (!res.ok || !res.data) return;
    setDone({ plate: p, service: sid, message: res.data.message, at: Date.now() });
    toast({ type: 'success', message: res.data.message });
    if (res.data.data && useUi.getState().apps.locksmith.open) useUi.getState().openApp('locksmith', res.data.data);
  };

  const refresh = async () => {
    if (refreshing) return;
    setRefreshing(true);
    const res = await request('locksmith:refresh', { locksmithId: data.id });
    setRefreshing(false);
    if (res.ok && res.data && useUi.getState().apps.locksmith.open) useUi.getState().openApp('locksmith', res.data);
  };

  /* ── keyboard ── */
  useEffect(() => {
    // the confirmation has the keyboard (its focused Pay button, Esc cancels)
    if (confirm) return;
    const onKey = (e: KeyboardEvent) => {
      const el = e.target as HTMLElement | null;
      const tag = el?.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA') return;
      if ((e.key === 'ArrowDown' || e.key === 'ArrowUp') && flat.length) {
        e.preventDefault();
        const i = v ? flat.findIndex((x) => x.plate === v.plate) : -1;
        const next = flat[Math.max(0, Math.min(flat.length - 1, i + (e.key === 'ArrowDown' ? 1 : -1)))];
        if (next) pick(next.plate);
      } else if ((e.key === 'ArrowLeft' || e.key === 'ArrowRight') && services.length) {
        e.preventDefault();
        const i = services.findIndex((s) => s.id === serviceId);
        const next = services[Math.max(0, Math.min(services.length - 1, i + (e.key === 'ArrowRight' ? 1 : -1)))];
        if (next) setServiceId(next.id);
      } else if (e.key === 'Enter') {
        // the service card already picked (focused after a mouse pick): Enter orders it, as the
        // footer says; any other focused button (another card, Refresh) does what it says
        const card = el?.closest<HTMLElement>('.nz-smith__card');
        if (card && card.getAttribute('aria-checked') === 'true') {
          e.preventDefault();
          order();
          return;
        }
        if (el && el.closest('button, a, [role="button"]')) return;
        e.preventDefault();
        order();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  const accountLabel = data.account === 'bank' ? t('Bank') : t('Cash');

  return (
    <Window
      className={cx('nz-smith', data.illegal && 'is-illegal')}
      bodyClassName="nz-smith__body"
      width="min(1120px, 94vw)"
      height="min(760px, 92vh)"
      title={data.name}
      icon="key"
      subtitle={data.illegal ? t('No questions asked') : t('Licensed locksmith')}
      badge={
        data.illegal ? (
          <Badge tone="red" icon="warning" size="sm">
            {t('Off the books')}
          </Badge>
        ) : (
          <Badge tone="teal" icon="shield" size="sm">
            {t('Licensed')}
          </Badge>
        )
      }
      headerExtra={
        <>
          <span className={cx('nz-smith__wallet', short && 'is-short')} title={t('Paid from {account}', { account: accountLabel })}>
            <Icon name="money" size={13} strokeWidth={1.8} />
            <span>{accountLabel}</span>
            <b>{money(data.money)}</b>
          </span>
          <IconButton icon="refresh" label={t('Refresh')} variant="ghost" size="sm" onClick={() => void refresh()} disabled={refreshing} />
        </>
      }
      onClose={close}
      footer={
        <>
          <span>
            <b>{nearby.length}</b> {t('parked nearby')}
            {' · '}
            {t('within {m} m', { m: Math.round(data.range) })}
          </span>
          <span className="nz-smith__spacer" />
          {flat.length > 1 && <KeyHint keys={['ArrowUp', 'ArrowDown']} label={t('Vehicle')} />}
          {v && services.length > 1 && <KeyHint keys={['ArrowLeft', 'ArrowRight']} label={t('Service')} />}
          {canPay && <KeyHint keys={['Enter']} label={t('Order')} />}
          <KeyHint keys={['Esc']} label={t('Close')} />
        </>
      }
    >
      <div className="nz-smith__layout">
        <aside className="nz-smith__rail" aria-label={t('Vehicles')}>
          {flat.length === 0 ? (
            <div className="nz-smith__railempty">
              <span className="nz-smith__grouphead">
                <span>{t('Vehicles')}</span>
                <b>0</b>
              </span>
              <p>
                {data.illegal ? t('Park a vehicle next to the shop.') : t('Park one of your vehicles next to the shop, or bring a key.')}
              </p>
            </div>
          ) : (
            <div className="nz-smith__list" role="listbox" aria-label={t('Vehicles')}>
              {nearby.length > 0 && (
                <RailGroup label={t('Parked nearby')} items={nearby} selected={v?.plate ?? null} onPick={pick} illegal={data.illegal} />
              )}
              {others.length > 0 && (
                <RailGroup
                  label={t('Your keys and vehicles')}
                  items={others}
                  selected={v?.plate ?? null}
                  onPick={pick}
                  illegal={data.illegal}
                />
              )}
            </div>
          )}
        </aside>

        <main className="nz-smith__main">
          {v ? (
            <>
              <Hero v={v} data={data} />
              <div className="nz-smith__scroll">
                {done && done.plate === v.plate && (
                  <div key={done.at} className="nz-smith__done" role="status">
                    <Icon name="checkCircle" size={16} strokeWidth={1.8} />
                    <span>
                      <b>{serviceTitle(done.service)}</b>
                      {done.message}
                    </span>
                  </div>
                )}
                <div className="nz-smith__sechead">
                  <span>{t('Services')}</span>
                </div>
                {services.length === 0 ? (
                  <EmptyState
                    icon="key"
                    title={t('Closed for now')}
                    description={t('This locksmith offers no services at the moment.')}
                    compact
                  />
                ) : (
                  <div
                    className="nz-smith__services"
                    role="radiogroup"
                    aria-label={t('Services')}
                    style={{ gridTemplateColumns: `repeat(${Math.max(services.length, 2)}, minmax(0, 1fr))` }}
                  >
                    {services.map((s) => (
                      <ServiceCard key={s.id} s={s} data={data} v={v} picked={s.id === serviceId} onPick={() => setServiceId(s.id)} />
                    ))}
                  </div>
                )}
                <ShopRules data={data} />
              </div>
              <footer className="nz-smith__dock">
                <div className="nz-smith__summary">
                  {service ? (
                    <>
                      <span className="nz-smith__sum-line">
                        <Icon name={serviceIcon(service.id)} size={14} strokeWidth={1.8} />
                        <b>{serviceTitle(service.id)}</b>
                        <PlateTag plate={v.plate} size="sm" />
                      </span>
                      {reason ? (
                        <span className={cx('nz-smith__reason', (missing.length > 0 || short || !!blocked) && 'is-amber')}>
                          <Icon name={missing.length || short || blocked ? 'warning' : 'info'} size={13} strokeWidth={1.8} />
                          <span>{reason}</span>
                        </span>
                      ) : (
                        <span className="nz-smith__reason is-teal">
                          <Icon name="arrowRight" size={13} strokeWidth={1.8} />
                          <span>{t('You get: {what}', { what: outcome(service.id, data, v) })}</span>
                        </span>
                      )}
                    </>
                  ) : (
                    <span className="nz-smith__reason">{t('Pick a service')}</span>
                  )}
                </div>
                <div className="nz-smith__pay">
                  {service && (
                    <span className={cx('nz-smith__total', short && 'is-short')}>
                      <small>{t('Total')}</small>
                      <b>{service.price > 0 ? money(service.price) : t('Free')}</b>
                    </span>
                  )}
                  <Button
                    variant="teal"
                    size="lg"
                    icon="money"
                    disabled={!canPay}
                    loading={busy}
                    onClick={order}
                    className="nz-smith__go"
                  >
                    {service && service.price > 0 ? t('Pay {price}', { price: money(service.price) }) : t('Confirm')}
                  </Button>
                </div>
              </footer>
            </>
          ) : (
            <div className="nz-smith__empty">
              <span className="nz-smith__empty-icon">
                <Icon name="car" size={22} strokeWidth={1.5} />
              </span>
              <b>{t('No vehicle to work on')}</b>
              <span>
                {data.illegal
                  ? t('Bring a vehicle within {m} m of the shop. Any vehicle will do here.', { m: Math.round(data.range) })
                  : t('Park your vehicle within {m} m of the shop, or bring a key of it to copy.', { m: Math.round(data.range) })}
              </span>
              <Button size="sm" icon="refresh" loading={refreshing} onClick={() => void refresh()}>
                {t('Look again')}
              </Button>
              {services.length > 0 && (
                <div className="nz-smith__pricelist">
                  {services.map((s) => (
                    <span key={s.id} className={cx('nz-smith__priceitem', !s.offered && 'is-off')}>
                      <Icon name={serviceIcon(s.id)} size={13} strokeWidth={1.8} />
                      <span>{serviceTitle(s.id)}</span>
                      <b>{s.offered ? (s.price > 0 ? money(s.price) : t('Free')) : t('Not offered')}</b>
                    </span>
                  ))}
                </div>
              )}
            </div>
          )}
        </main>
      </div>
      <OrderConfirm
        data={data}
        order={confirm}
        vehicle={confirm ? (flat.find((x) => x.plate === confirm.plate) ?? null) : null}
        service={confirm ? (services.find((x) => x.id === confirm.service) ?? null) : null}
        busy={busy}
        onConfirm={() => void pay()}
        onCancel={() => setConfirm(null)}
      />
    </Window>
  );
}

/* ── order confirmation ───────────────────────────────────────────────── */

function OrderConfirm({
  data,
  order,
  vehicle,
  service,
  busy,
  onConfirm,
  onCancel,
}: {
  data: LocksmithOpenData;
  order: { plate: string; service: LocksmithServiceId } | null;
  vehicle: LocksmithVehicle | null;
  service: LocksmithService | null;
  busy: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  const open = !!order && !!vehicle && !!service;
  const v = vehicle;
  const s = service;
  const rekey = s?.id === 'rekey';
  const price = s?.price ?? 0;
  const after = data.money - price;
  const accountLabel = data.account === 'bank' ? t('Bank') : t('Cash');
  return (
    <ConfirmDialog
      className="nz-smith-confirm"
      open={open}
      tone={rekey || data.illegal ? 'red' : 'teal'}
      icon={s ? serviceIcon(s.id) : 'key'}
      title={s && v ? confirmTitle(s.id, data, v, price) : ''}
      message={
        s && v ? (
          <>
            {t('You get: {what}', { what: outcome(s.id, data, v) })}
            {'. '}
            {t('The money and materials are taken when the work is done.')}
          </>
        ) : null
      }
      confirmLabel={price > 0 ? t('Pay {price}', { price: money(price) }) : t('Confirm')}
      busy={busy}
      onConfirm={onConfirm}
      onCancel={onCancel}
    >
      {s && v && (
        <>
          <div className="nz-smith-confirm__sum">
            <div className="nz-smith-confirm__row">
              <span>
                <Icon name="car" size={12} strokeWidth={1.9} />
                {t('Vehicle')}
              </span>
              <span className="nz-smith-confirm__veh">
                <b title={nameOf(v)}>{nameOf(v)}</b>
                <PlateTag plate={v.plate} size="sm" />
              </span>
            </div>
            <div className="nz-smith-confirm__row">
              <span>
                <Icon name={serviceIcon(s.id)} size={12} strokeWidth={1.9} />
                {t('Service')}
              </span>
              <b>{serviceTitle(s.id)}</b>
            </div>
            <div className="nz-smith-confirm__row">
              <span>
                <Icon name="wrench" size={12} strokeWidth={1.9} />
                {t('Materials')}
              </span>
              <b>{s.materials.length ? s.materials.map((m) => `${m.count}× ${m.label}`).join(', ') : t('None')}</b>
            </div>
            <div className="nz-smith-confirm__row is-total">
              <span>
                <Icon name="money" size={12} strokeWidth={1.9} />
                {t('From {account}', { account: accountLabel })}
              </span>
              <b>
                {price > 0 ? money(price) : t('Free')}
                <small>{t('{money} left', { money: money(Math.max(0, after)) })}</small>
              </b>
            </div>
          </div>
          {rekey && (
            <div className="nz-smith-confirm__warn">
              <Icon name="warning" size={14} strokeWidth={1.8} />
              <span>{t('Every other key of {plate} stops working, including keys you gave to others.', { plate: v.plate })}</span>
            </div>
          )}
          {data.illegal && (
            <div className="nz-smith-confirm__warn is-amber">
              <Icon name="warning" size={14} strokeWidth={1.8} />
              <span>{t('No questions asked: word gets around, the police may hear about it.')}</span>
            </div>
          )}
        </>
      )}
    </ConfirmDialog>
  );
}

/* ── rail ─────────────────────────────────────────────────────────────── */

function RailGroup({
  label,
  items,
  selected,
  onPick,
  illegal,
}: {
  label: string;
  items: LocksmithVehicle[];
  selected: string | null;
  onPick: (plate: string) => void;
  illegal: boolean;
}) {
  return (
    <div className="nz-smith__group" role="group" aria-label={label}>
      <div className="nz-smith__grouphead">
        <span>{label}</span>
        <b>{items.length}</b>
      </div>
      {items.map((x) => (
        <div
          key={x.plate}
          role="option"
          aria-selected={x.plate === selected}
          tabIndex={-1}
          className={cx('nz-smith__row', x.plate === selected && 'is-selected', !x.nearby && 'is-away')}
          onClick={() => onPick(x.plate)}
        >
          <span className="nz-smith__thumb">
            <VehicleImage image={x.image} vehicleType={x.vehicleType} alt={nameOf(x)} className="nz-smith__thumb-img" />
          </span>
          <span className="nz-smith__rowtext">
            <span className="nz-smith__rowname">
              <b title={nameOf(x)}>{nameOf(x)}</b>
              {x.isOwner && (
                <span className="nz-smith__owner" title={t('You own it')}>
                  <Icon name="crown" size={11} strokeWidth={1.9} />
                </span>
              )}
            </span>
            <span className="nz-smith__rowmeta">
              <PlateTag plate={x.plate} size="sm" />
              <KeyChip v={x} illegal={illegal} />
            </span>
          </span>
          <span className={cx('nz-smith__where', x.nearby ? 'is-teal' : 'is-grey')}>
            {x.towing ? t('Towed') : x.nearby ? t('{m} m', { m: x.distance ?? 0 }) : t('Not here')}
          </span>
        </div>
      ))}
    </div>
  );
}

/** What the player's key is, in words: the owner's access, a garage share / fleet access, a
 *  virtual key the owner gave, a temporary key. */
function keyWord(v: LocksmithVehicle): { text: string; tone: 'teal' | 'blue' | 'amber' } | null {
  if (!v.hasKey) return null;
  if (v.keyKind === 'temp') return { text: t('Temporary key'), tone: 'amber' };
  // 'owner' = ownership itself, or the access of a garage share / job or gang fleet
  if (v.keyKind === 'owner') return v.isOwner ? { text: t('Owner'), tone: 'teal' } : { text: t('Shared access'), tone: 'blue' };
  if (v.keyKind === 'virtual') return { text: t('Virtual key'), tone: 'blue' };
  return null;
}

function KeyChip({ v, illegal }: { v: LocksmithVehicle; illegal: boolean }) {
  if (v.keyItems > 0) {
    return (
      <span
        className={cx('nz-smith__chip', v.unregistered ? 'is-amber' : 'is-white')}
        title={v.unregistered ? t('Unregistered key: it opens the vehicle, a licensed locksmith will not register it') : undefined}
      >
        <Icon name="key" size={10} strokeWidth={2.2} />
        {v.keyType === 'fob' ? t('Fob ×{n}', { n: v.keyItems }) : t('Key ×{n}', { n: v.keyItems })}
      </span>
    );
  }
  const word = keyWord(v);
  if (word) return <span className={cx('nz-smith__chip', `is-${word.tone}`)}>{word.text}</span>;
  if (v.isOwner) return <span className="nz-smith__chip">{t('Papers')}</span>;
  return <span className={cx('nz-smith__chip', illegal ? 'is-red' : undefined)}>{t('No key')}</span>;
}

/* ── hero ─────────────────────────────────────────────────────────────── */

function Hero({ v, data }: { v: LocksmithVehicle; data: LocksmithOpenData }) {
  const facts: { icon: IconName; text: ReactNode; tone?: string }[] = [];
  facts.push(
    v.nearby
      ? { icon: 'pin', text: t('Parked {m} m from the shop', { m: v.distance ?? 0 }), tone: 'teal' }
      : { icon: 'parking', text: t('Not parked here'), tone: 'grey' },
  );
  if (v.isOwner) facts.push({ icon: 'crown', text: t('You own it') });
  else if (v.owned) facts.push({ icon: 'user', text: t('Someone else’s vehicle'), tone: data.illegal ? 'red' : undefined });
  else facts.push({ icon: 'user', text: t('No registered owner') });
  const word = keyWord(v);
  if (v.keyItems > 0) {
    facts.push({
      icon: 'key',
      text: v.keyType === 'fob' ? t('{n} fob(s) in your pockets', { n: v.keyItems }) : t('{n} key(s) in your pockets', { n: v.keyItems }),
    });
    if (v.unregistered) facts.push({ icon: 'warning', text: t('Unregistered key'), tone: 'amber' });
  } else if (word && !(word.tone === 'teal' && v.isOwner)) facts.push({ icon: 'key', text: word.text, tone: word.tone === 'amber' ? 'amber' : undefined });
  else if (!word) facts.push({ icon: 'ban', text: t('No key'), tone: 'grey' });
  return (
    <div className="nz-smith__hero">
      <div className="nz-smith__heroimg">
        <span className="nz-smith__heroimg-floor" aria-hidden="true" />
        <VehicleImage key={v.plate} image={v.image} vehicleType={v.vehicleType} alt={nameOf(v)} className="nz-smith__heroimg-car" />
      </div>
      <div className="nz-smith__herotext">
        {v.make && <span className="nz-smith__make">{v.make}</span>}
        <span className="nz-smith__heroline">
          <b title={nameOf(v)}>{nameOf(v)}</b>
          {v.nickname && v.label && <em>{v.label}</em>}
        </span>
        <div className="nz-smith__facts">
          {facts.map((f, i) => (
            <span key={i} className={cx('nz-smith__fact', f.tone && `is-${f.tone}`)}>
              <Icon name={f.icon} size={12} strokeWidth={1.9} />
              {f.text}
            </span>
          ))}
        </div>
      </div>
      <span className="nz-smith__plate">
        <small>{t('San Andreas')}</small>
        <b>{v.plate}</b>
      </span>
    </div>
  );
}

/* ── shop rules ───────────────────────────────────────────────────────── */

function ShopRules({ data }: { data: LocksmithOpenData }) {
  const range = Math.round(data.range);
  const rules: { icon: IconName; title: string; text: string; tone?: 'red' }[] = data.illegal
    ? [
        { icon: 'ban', title: t('No papers asked'), text: t('Any vehicle parked within {m} m gets a key.', { m: range }) },
        { icon: 'warning', title: t('Risky business'), text: t('Word gets around: the police may hear about it.'), tone: 'red' },
        {
          icon: 'key',
          title: data.mode === 'virtual' ? t('Temporary keys') : t('Unregistered keys'),
          text:
            data.mode === 'virtual'
              ? t('Programmed keys last {h} h and never reach a tracker.', { h: Math.round(data.tempHours) })
              : t('They open the vehicle, never its tracker. Copies need a key you bring.'),
        },
      ]
    : [
        data.mode === 'virtual'
          ? { icon: 'shield', title: t('Your own vehicles'), text: t('Owners only: bring the vehicle.') }
          : { icon: 'shield', title: t('Owners and key holders'), text: t('Bring a key, or the papers of a vehicle you own.') },
        {
          icon: 'clock',
          title: t('Borrowed access does not count'),
          text: t('Temporary keys, back-alley keys, garage shares and job vehicles never make new keys.'),
        },
        { icon: 'pin', title: t('Park it here'), text: t('Programming and new locks need the vehicle within {m} m.', { m: range }) },
      ];
  return (
    <div className="nz-smith__rules">
      <span className="nz-smith__rules-head">{t('Shop rules')}</span>
      <div className="nz-smith__rules-list">
        {rules.map((r) => (
          <div key={r.title} className={cx('nz-smith__rule', r.tone && `is-${r.tone}`)}>
            <Icon name={r.icon} size={14} strokeWidth={1.8} />
            <span>
              <b>{r.title}</b>
              {r.text}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

/* ── service card ─────────────────────────────────────────────────────── */

function ServiceCard({
  s,
  data,
  v,
  picked,
  onPick,
}: {
  s: LocksmithService;
  data: LocksmithOpenData;
  v: LocksmithVehicle;
  picked: boolean;
  onPick: () => void;
}) {
  const blocked = !s.offered ? (s.reason ?? t('Not offered here')) : ((v.blocked ?? {})[s.id] ?? null);
  const short = s.price > data.money;
  const missing = s.materials.some((m) => m.have < m.count);
  const state = blocked ? 'blocked' : missing || short ? 'short' : 'ok';
  return (
    <button
      type="button"
      role="radio"
      aria-checked={picked}
      className={cx('nz-smith__card', picked && 'is-picked', `is-${state}`, !s.offered && 'is-off')}
      onClick={onPick}
    >
      <span className="nz-smith__card-top">
        <span className="nz-smith__card-icon">
          <Icon name={serviceIcon(s.id)} size={17} strokeWidth={1.7} />
        </span>
        <span className="nz-smith__card-radio" aria-hidden="true">
          {picked && <Icon name="check" size={11} strokeWidth={2.6} />}
        </span>
      </span>
      <b className="nz-smith__card-title">{serviceTitle(s.id)}</b>
      <span className="nz-smith__card-text">{serviceText(s.id, data, v)}</span>
      <span className={cx('nz-smith__price', short && 'is-short')}>{s.price > 0 ? money(s.price) : t('Free')}</span>
      <span className="nz-smith__mats">
        {s.materials.length === 0 ? (
          <span className="nz-smith__mat is-none">
            <Icon name="check" size={11} strokeWidth={2.2} />
            {t('No materials needed')}
          </span>
        ) : (
          s.materials.map((m) => (
            <span key={m.item} className={cx('nz-smith__mat', m.have >= m.count ? 'is-ok' : 'is-missing')}>
              <Icon name={m.have >= m.count ? 'check' : 'close'} size={11} strokeWidth={2.2} />
              <span>
                {m.count}× {m.label}
              </span>
              <small>{t('{have}/{need}', { have: m.have, need: m.count })}</small>
            </span>
          ))
        )}
      </span>
      <span className={cx('nz-smith__card-state', `is-${state}`)}>
        <Icon name={state === 'ok' ? 'checkCircle' : state === 'short' ? 'warning' : 'ban'} size={12} strokeWidth={1.9} />
        <span>
          {state === 'ok' ? t('Available') : state === 'short' ? (short ? t('Not enough money') : t('Missing materials')) : blocked}
        </span>
      </span>
    </button>
  );
}
