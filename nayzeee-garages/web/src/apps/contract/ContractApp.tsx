/**
 * Sale contract app (docs/CARLOCK.md §12): `draft` for the seller (blank contract used next to
 * one of their vehicles), `review` for the buyer (read, sign, pay; countdown), `view` for a
 * signed copy. The document is the same in every mode (ContractDocument); the server checks
 * and decides everything, this window only collects the seller's choices and signatures.
 * Outcomes of a sent contract arrive as 'update' { status }.
 */
import { useEffect, useMemo, useRef, useState } from 'react';
import type { ReactNode, RefObject } from 'react';
import clsx from 'clsx';
import {
  Avatar,
  Badge,
  Button,
  Chip,
  ConfirmDialog,
  EmptyState,
  Icon,
  IconButton,
  NumberInput,
  PlateTag,
  Ring,
  Section,
  VehicleImage,
  Window,
} from '@/components/ui';
import type { IconName } from '@/components/ui';
import { useApp, useSettings } from '@/lib/store';
import { useEscape } from '@/lib/escape';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import { dateTime, money } from '@/lib/format';
import type {
  ContractDraftData,
  ContractKeyKind,
  ContractReviewData,
  ContractStatus,
  ContractVehicle,
  ContractViewData,
  PlayerOption,
} from '@/lib/types';
import { ContractDocument } from './ContractDocument';
import type { StampTone } from './ContractDocument';
import { SignaturePad, SignatureView, pathToStrokes, signatureReady, strokesToPath } from './signature';
import type { Stroke } from './signature';
import './contract.css';

const MAX_TERMS = 600;
const MAX_TERMS_LINES = 12;
/** ms between two balance checks while the buyer reads a contract */
const BALANCE_POLL = 5000;

export function ContractApp() {
  const { open, data, close, update } = useApp('contract');
  if (!open || !data) return null;
  if (data.mode === 'draft') return <DraftView key="draft" data={data} close={close} update={update} />;
  if (data.mode === 'review') return <ReviewView key={data.contractId} data={data} close={close} />;
  return <ReadView key={data.contractId} data={data} close={close} />;
}

/* ───────────────────────── shared bits ───────────────────────── */

/** Seconds left of `seconds` counted from when it was received (no clock skew with Lua). */
function useCountdown(seconds: number | null, key: unknown): number | null {
  const [deadline, setDeadline] = useState<number | null>(() => (seconds == null ? null : Date.now() + seconds * 1000));
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    setDeadline(seconds == null ? null : Date.now() + seconds * 1000);
    setNow(Date.now());
  }, [seconds, key]);
  useEffect(() => {
    if (deadline == null) return;
    const id = window.setInterval(() => setNow(Date.now()), 250);
    return () => window.clearInterval(id);
  }, [deadline]);
  if (deadline == null) return null;
  return Math.max(0, Math.ceil((deadline - now) / 1000));
}

function clock(seconds: number) {
  const s = Math.max(0, seconds);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

/** Is the element (inside its scroll containers) on screen? */
function useInView(ref: RefObject<HTMLElement>, active: boolean): boolean {
  const [visible, setVisible] = useState(true);
  useEffect(() => {
    const el = ref.current;
    if (!active || !el || typeof IntersectionObserver === 'undefined') return;
    const io = new IntersectionObserver(([entry]) => setVisible(entry.intersectionRatio >= 0.6), { threshold: [0, 0.6, 1] });
    io.observe(el);
    return () => io.disconnect();
  }, [ref, active]);
  return visible;
}

function reveal(ref: RefObject<HTMLElement>) {
  ref.current?.scrollIntoView({ behavior: 'smooth', block: 'center' });
}

function Timer({ left, total, label }: { left: number; total: number; label: string }) {
  const tone = left <= 10 ? 'red' : left <= 30 ? 'amber' : 'teal';
  return (
    <span className={clsx('nz-contract__timer', `is-${tone}`)} role="timer" aria-label={label}>
      <Ring value={left} max={Math.max(total, 1)} size={20} stroke={2.5} tone={tone} />
      <b>{clock(left)}</b>
      <small>{label}</small>
    </span>
  );
}

interface StatusInfo {
  icon: IconName;
  tone: 'teal' | 'red' | 'amber' | 'neutral';
  text: string;
  stamp: { text: string; tone: StampTone } | null;
}

function statusInfo(status: ContractStatus, role: 'seller' | 'buyer', other: string): StatusInfo {
  switch (status) {
    case 'signed':
      return {
        icon: 'checkCircle',
        tone: 'teal',
        text: role === 'seller' ? t('{name} signed and paid. The vehicle is theirs now.', { name: other }) : t('Signed and paid. The vehicle is yours.'),
        stamp: { text: t('Sold'), tone: 'teal' },
      };
    case 'declined':
      return {
        icon: 'ban',
        tone: 'red',
        text: role === 'seller' ? t('{name} declined the contract.', { name: other }) : t('You declined this contract.'),
        stamp: { text: t('Declined'), tone: 'red' },
      };
    case 'expired':
      return {
        icon: 'clock',
        tone: 'amber',
        text: role === 'seller' ? t('The contract expired before {name} signed it.', { name: other }) : t('This contract expired before you signed it.'),
        stamp: { text: t('Expired'), tone: 'amber' },
      };
    case 'withdrawn':
      return {
        icon: 'arrowLeft',
        tone: 'neutral',
        text: role === 'seller' ? t('You withdrew the contract.') : t('{name} withdrew this contract.', { name: other }),
        stamp: { text: t('Withdrawn'), tone: 'neutral' },
      };
    case 'cancelled':
      return {
        icon: 'logout',
        tone: 'red',
        text: t('{name} left: the contract is void.', { name: other }),
        stamp: { text: t('Void'), tone: 'red' },
      };
    case 'failed':
      return {
        icon: 'warning',
        tone: 'red',
        text: t('The sale could not be completed. Nothing changed hands.'),
        stamp: { text: t('Void'), tone: 'red' },
      };
    default:
      return { icon: 'clock', tone: 'teal', text: '', stamp: null };
  }
}

function Banner({ icon, tone, children, progress }: { icon: IconName; tone: string; children: ReactNode; progress?: number | null }) {
  return (
    <div className={clsx('nz-contract__banner', `is-${tone}`)} role="status">
      <Icon name={icon} size={15} strokeWidth={1.8} />
      <span>{children}</span>
      {progress != null && (
        <span className="nz-contract__banner-bar" aria-hidden="true">
          <i style={{ width: `${Math.max(0, Math.min(1, progress)) * 100}%` }} />
        </span>
      )}
    </div>
  );
}

function accountLabel(account: 'bank' | 'cash') {
  return account === 'cash' ? t('cash') : t('bank account');
}

/** What the buyer holds after signing: the key (by key system) and their signed copy. */
function boughtNote(key: ContractKeyKind | null | undefined, copy: boolean): string {
  if (key === 'item') return copy ? t('The key and your signed copy are in your inventory.') : t('The key is in your inventory.');
  const keyText = key === 'temp' ? t('You have a temporary key to it.') : key === 'external' ? t('You have the keys.') : null;
  const copyText = copy ? t('Your signed copy is in your inventory.') : null;
  if (keyText && copyText) return `${keyText} ${copyText}`;
  return keyText ?? copyText ?? t('The sale is recorded in the vehicle\'s ownership history.');
}

/* ───────────────────────── draft (seller) ───────────────────────── */

const CLAUSES = [
  'Sold as seen, without warranty.',
  'All keys are handed over on signing.',
  'The buyer pays any fines from the date of sale.',
  'The seller confirms the vehicle is free of finance.',
];

interface Sent {
  id: string;
  expiresIn: number;
  buyer: PlayerOption;
}

/** After a "no" (declined / expired) this buyer waits `seconds` (from `at`) for a new contract. */
interface Cooldown {
  buyer: PlayerOption;
  seconds: number;
  at: number;
}

function DraftView({
  data,
  close,
  update,
}: {
  data: ContractDraftData;
  close: () => void;
  update: (partial: Partial<ContractDraftData>) => void;
}) {
  const settings = useSettings();
  // `data.sent`: the seller's contract is still waiting (blank contract used again): its sent state
  const reopened = data.sent ?? null;
  const [vehicles, setVehicles] = useState<ContractVehicle[]>(data.vehicles);
  const [buyers, setBuyers] = useState<PlayerOption[]>(data.buyers);
  const [plate, setPlate] = useState<string | null>(() => reopened?.plate ?? data.vehicles.find((v) => !v.blocked)?.plate ?? null);
  const [buyerId, setBuyerId] = useState<number | null>(() =>
    reopened ? reopened.buyer.serverId : data.buyers.length === 1 ? data.buyers[0].serverId : null,
  );
  const [price, setPrice] = useState(() => reopened?.price ?? Number.NaN);
  const [terms, setTerms] = useState(() => reopened?.terms ?? '');
  const [strokes, setStrokes] = useState<Stroke[]>(() => (reopened ? pathToStrokes(reopened.signature) : []));
  const [sent, setSent] = useState<Sent | null>(() =>
    reopened ? { id: reopened.id, expiresIn: reopened.expiresIn, buyer: reopened.buyer } : null,
  );
  const [busy, setBusy] = useState<'send' | 'withdraw' | 'refresh' | null>(null);
  const [cooldown, setCooldown] = useState<Cooldown | null>(null);
  useEscape(close, true);
  const vehicleRef = useRef<HTMLSpanElement>(null);
  const buyerRef = useRef<HTMLSpanElement>(null);
  const priceRef = useRef<HTMLSpanElement>(null);
  const signRef = useRef<HTMLDivElement>(null);
  const paperRef = useRef<HTMLDivElement>(null);

  const vehicle = vehicles.find((v) => v.plate === plate) ?? null;
  const buyer = buyers.find((b) => b.serverId === buyerId) ?? (sent ? sent.buyer : null);
  const status: ContractStatus | null = sent ? data.status ?? 'pending' : null;
  const left = useCountdown(sent && status === 'pending' ? sent.expiresIn : null, sent?.id);
  const effective: ContractStatus | null = status === 'pending' && left === 0 ? 'expired' : status;
  const locked = sent !== null;
  const termLines = terms.split('\n').length;
  const termsOk = terms.length <= MAX_TERMS && termLines <= MAX_TERMS_LINES;
  // the server's answer to a "no" carries how long that buyer waits for a new contract
  useEffect(() => {
    if (!sent || (data.status !== 'declined' && data.status !== 'expired')) return;
    const seconds = data.resendIn ?? 0;
    if (seconds > 0) setCooldown({ buyer: sent.buyer, seconds, at: Date.now() });
  }, [sent, data.status, data.resendIn]);
  const coolLeft = useCountdown(cooldown ? cooldown.seconds : null, cooldown?.at) ?? 0;
  const cooling = cooldown && coolLeft > 0 ? cooldown : null;
  const buyerWaits = !!cooling && !!buyer && buyer.serverId === cooling.buyer.serverId;

  const checks = [
    { ok: !!vehicle && !vehicle.blocked, label: t('Vehicle'), ref: vehicleRef },
    { ok: !!buyer && !buyerWaits, label: t('Buyer'), ref: buyerRef },
    { ok: price >= 1 && price <= data.maxPrice, label: t('Price'), ref: priceRef },
    { ok: signatureReady(strokes), label: t('Signature'), ref: signRef },
  ];
  const ready = checks.every((c) => c.ok) && termsOk;

  const refresh = async () => {
    setBusy('refresh');
    const res = await request('contract:refresh', {});
    setBusy(null);
    if (!res.ok) return;
    setVehicles(res.data.vehicles);
    setBuyers(res.data.buyers);
    if (plate && !res.data.vehicles.some((v) => v.plate === plate && !v.blocked)) {
      setPlate(res.data.vehicles.find((v) => !v.blocked)?.plate ?? null);
    }
    if (buyerId !== null && !res.data.buyers.some((b) => b.serverId === buyerId)) {
      setBuyerId(res.data.buyers.length === 1 ? res.data.buyers[0].serverId : null);
    } else if (buyerId === null && res.data.buyers.length === 1) {
      setBuyerId(res.data.buyers[0].serverId);
    }
  };

  const send = async () => {
    if (!ready || !vehicle || !buyer) return;
    setBusy('send');
    const res = await request('contract:send', {
      plate: vehicle.plate,
      buyer: buyer.serverId,
      price,
      terms: terms.trim(),
      signature: strokesToPath(strokes),
    });
    setBusy(null);
    if (!res.ok) return;
    update({ status: 'pending' });
    setSent({ id: res.data.contractId, expiresIn: res.data.expiresIn, buyer });
  };

  const withdraw = async () => {
    if (!sent) return;
    setBusy('withdraw');
    const res = await request('contract:decline', { contractId: sent.id });
    setBusy(null);
    if (!res.ok) return;
    update({ status: undefined });
    setSent(null);
  };

  const editAgain = () => {
    update({ status: undefined });
    setSent(null);
  };

  const addClause = (clause: string) => {
    const text = t(clause);
    if (terms.includes(text)) return;
    const next = terms.trim() ? `${terms.trimEnd()}\n${text}` : text;
    if (next.length <= MAX_TERMS && next.split('\n').length <= MAX_TERMS_LINES) setTerms(next);
  };

  const info = effective && effective !== 'pending' ? statusInfo(effective, 'seller', sent?.buyer.name ?? '') : null;
  // an outcome arrived: bring the banner under the letterhead into view
  useEffect(() => {
    if (effective && effective !== 'pending') paperRef.current?.scrollTo({ top: 0, behavior: 'smooth' });
  }, [effective]);
  const banner = !sent ? null : effective === 'pending' ? (
    <Banner icon="clock" tone="teal" progress={left !== null ? left / Math.max(data.expireSeconds, sent.expiresIn, 1) : null}>
      {t('Waiting for {name} to sign. You can close this window: you will be told when they answer.', { name: sent.buyer.name })}
    </Banner>
  ) : info ? (
    <Banner icon={info.icon} tone={info.tone}>
      {info.text}
    </Banner>
  ) : null;

  return (
    <Window
      className="nz-contract nz-contract--draft"
      bodyClassName="nz-contract__body"
      width={1140}
      title={t('Sale contract')}
      icon="receipt"
      subtitle={sent ? t('Sent to {name}', { name: sent.buyer.name }) : t('Draft · fill it in, sign and send it to the buyer')}
      headerExtra={
        sent && effective === 'pending' && left !== null ? (
          <Timer left={left} total={Math.max(data.expireSeconds, sent.expiresIn)} label={t('to sign')} />
        ) : undefined
      }
      onClose={close}
    >
      <div className="nz-contract__split">
        <aside className={clsx('nz-contract__form', locked && 'is-locked')}>
          <Section
            title={t('Vehicle')}
            actions={
              <IconButton
                icon="refresh"
                label={t('Look around again')}
                size="sm"
                disabled={locked || busy !== null}
                onClick={() => void refresh()}
              />
            }
          >
            <span ref={vehicleRef} className="nz-contract__anchor" aria-hidden="true" />
            {vehicles.length === 0 ? (
              <EmptyState compact icon="car" title={t('No vehicle of yours nearby')} description={t('Stand next to the vehicle you want to sell, then look around again.')} />
            ) : (
              <div className="nz-contract__opts" role="radiogroup" aria-label={t('Vehicle')}>
                {vehicles.map((v) => {
                  const selected = v.plate === plate;
                  return (
                    <button
                      key={v.plate}
                      type="button"
                      role="radio"
                      aria-checked={selected}
                      className={clsx('nz-contract__opt', selected && 'is-selected', v.blocked && 'is-blocked')}
                      disabled={locked || !!v.blocked}
                      title={v.blocked ?? undefined}
                      onClick={() => setPlate(v.plate)}
                    >
                      <VehicleImage className="nz-contract__opt-img" image={v.image} vehicleType={v.vehicleType} alt={v.label} />
                      <span className="nz-contract__opt-text">
                        <b>{v.label}</b>
                        <span className="nz-contract__opt-meta">
                          <PlateTag plate={v.plate} size="sm" />
                          <span className="nz-contract__opt-dist">
                            {v.distance != null ? (v.distance < 1 ? t('You are in it') : t('{n} m away', { n: Math.round(v.distance) })) : ''}
                          </span>
                        </span>
                        {v.blocked && (
                          <span className="nz-contract__opt-why">
                            <Icon name="warning" size={11} strokeWidth={2} />
                            <span>{v.blocked}</span>
                          </span>
                        )}
                      </span>
                      <span className="nz-contract__opt-check" aria-hidden="true">
                        {selected && <Icon name="check" size={12} strokeWidth={2.4} />}
                      </span>
                    </button>
                  );
                })}
              </div>
            )}
          </Section>

          <Section title={t('Buyer')}>
            <span ref={buyerRef} className="nz-contract__anchor" aria-hidden="true" />
            {buyers.length === 0 ? (
              <p className="nz-contract__note">
                <Icon name="users" size={13} />
                {t('Nobody is standing next to you. The buyer has to be close, then look around again.')}
              </p>
            ) : (
              <div className="nz-contract__opts nz-contract__opts--people" role="radiogroup" aria-label={t('Buyer')}>
                {buyers.map((b) => {
                  const selected = b.serverId === buyerId;
                  const waits = !!cooling && cooling.buyer.serverId === b.serverId;
                  return (
                    <button
                      key={b.serverId}
                      type="button"
                      role="radio"
                      aria-checked={selected}
                      className={clsx('nz-contract__opt nz-contract__opt--person', selected && 'is-selected', waits && 'is-waiting')}
                      disabled={locked}
                      onClick={() => setBuyerId(b.serverId)}
                    >
                      <Avatar name={b.name} size={28} />
                      <span className="nz-contract__opt-text">
                        <b title={b.name}>{b.name}</b>
                        <span className="nz-contract__opt-dist">
                          {waits ? t('Wait {n} s', { n: coolLeft }) : t('ID {id}', { id: b.serverId })}
                        </span>
                      </span>
                    </button>
                  );
                })}
              </div>
            )}
            {!locked && buyerWaits && cooling && (
              <p className="nz-contract__hint is-amber">
                {t('{name} can get a new contract from you in {n} s. You can choose another buyer now.', {
                  name: cooling.buyer.name,
                  n: coolLeft,
                })}
              </p>
            )}
          </Section>

          <Section title={t('Price')}>
            <span ref={priceRef} className="nz-contract__anchor" aria-hidden="true" />
            <NumberInput
              value={price}
              onChange={(n) => setPrice(Math.floor(n))}
              min={1}
              max={data.maxPrice}
              step={500}
              prefix={settings.currency}
              disabled={locked}
            />
            <p className="nz-contract__hint">
              {t('Paid from the buyer\'s {account} into yours. Up to {max}.', { account: accountLabel(data.account), max: money(data.maxPrice) })}
            </p>
          </Section>

          <Section title={t('Terms')} actions={<span className={clsx('nz-contract__count', !termsOk && 'is-over')}>{terms.length} / {MAX_TERMS}</span>}>
            <textarea
              className="nz-contract__textarea"
              value={terms}
              maxLength={MAX_TERMS}
              rows={4}
              disabled={locked}
              placeholder={t('Anything you both agree on (optional)')}
              onChange={(e) => setTerms(e.target.value.replace(/[<>]/g, ''))}
            />
            <div className="nz-contract__clauses">
              {CLAUSES.map((clause) => (
                <Chip key={clause} icon="plus" disabled={locked || terms.includes(t(clause))} onClick={() => addClause(clause)}>
                  {t(clause)}
                </Chip>
              ))}
            </div>
          </Section>
        </aside>

        <div className="nz-contract__paper" ref={paperRef}>
          <ContractDocument
            number={sent?.id ?? null}
            dated={null}
            seller={data.seller}
            buyer={buyer ?? null}
            vehicle={vehicle && !vehicle.blocked ? vehicle : null}
            price={price >= 1 ? price : null}
            account={data.account}
            terms={terms}
            active={locked ? null : 'seller'}
            signRef={signRef}
            banner={banner}
            stamp={info?.stamp ?? null}
            sellerSignature={
              locked ? <SignatureView path={strokesToPath(strokes)} /> : <SignaturePad strokes={strokes} onChange={setStrokes} placeholder={t('Sign here as the seller')} />
            }
            buyerSignature={
              <span className="nz-contract__sign-wait">
                {!sent
                  ? t('The buyer signs after you')
                  : effective === 'pending'
                    ? t('Waiting for {name}', { name: sent.buyer.name })
                    : effective === 'signed'
                      ? t('Signed')
                      : t('Not signed')}
              </span>
            }
          />
        </div>
      </div>

      <footer className="nz-contract__actions">
        {!sent ? (
          <>
            <ul className="nz-contract__checks" aria-label={t('Ready to send')}>
              {checks.map((c) => (
                <li key={c.label} className={clsx(c.ok && 'is-ok')}>
                  <button type="button" onClick={() => reveal(c.ref)}>
                    <Icon name={c.ok ? 'checkCircle' : 'info'} size={13} strokeWidth={1.9} />
                    {c.label}
                  </button>
                </li>
              ))}
            </ul>
            <span className="nz-contract__spacer" />
            <Button variant="ghost" onClick={close}>
              {t('Cancel')}
            </Button>
            <Button
              variant="teal"
              icon="arrowRight"
              badge={price >= 1 ? money(price) : undefined}
              disabled={!ready || busy !== null}
              loading={busy === 'send'}
              onClick={() => void send()}
            >
              {t('Send to buyer')}
            </Button>
          </>
        ) : effective === 'pending' ? (
          <>
            <span className="nz-contract__foot-note">
              <Icon name="info" size={13} />
              {t('Stay close: the vehicle and {name} must be within reach when they sign.', { name: sent.buyer.name })}
            </span>
            <span className="nz-contract__spacer" />
            <Button variant="red" icon="close" loading={busy === 'withdraw'} disabled={busy !== null} onClick={() => void withdraw()}>
              {t('Withdraw')}
            </Button>
            <Button variant="line" onClick={close}>
              {t('Close')}
            </Button>
          </>
        ) : effective === 'signed' ? (
          <>
            <span className="nz-contract__foot-note is-teal">
              <Icon name="receipt" size={13} />
              {data.copy ? t('Your signed copy is in your inventory.') : t('The sale is recorded in the vehicle\'s ownership history.')}
            </span>
            <span className="nz-contract__spacer" />
            <Button variant="teal" icon="check" onClick={close}>
              {t('Done')}
            </Button>
          </>
        ) : (
          <>
            <span className="nz-contract__foot-note">
              <Icon name={cooling ? 'clock' : 'info'} size={13} />
              {cooling
                ? t('{name} can get a new contract from you in {n} s. You can choose another buyer now.', {
                    name: cooling.buyer.name,
                    n: coolLeft,
                  })
                : t('Your blank contract was not used. Change what you need and send it again.')}
            </span>
            <span className="nz-contract__spacer" />
            <Button variant="ghost" onClick={close}>
              {t('Close')}
            </Button>
            <Button variant="teal" icon="edit" onClick={editAgain}>
              {t('Edit and send again')}
            </Button>
          </>
        )}
      </footer>
    </Window>
  );
}

/* ───────────────────────── review (buyer) ───────────────────────── */

function ReviewView({ data, close }: { data: ContractReviewData; close: () => void }) {
  const [strokes, setStrokes] = useState<Stroke[]>([]);
  const [busy, setBusy] = useState(false);
  const [signedAt, setSignedAt] = useState<number | null>(null);
  const [bought, setBought] = useState<{ key: ContractKeyKind | null; copy: boolean }>({ key: null, copy: false });
  const [canAfford, setCanAfford] = useState(data.canAfford);
  const [confirm, setConfirm] = useState(false);
  const signRef = useRef<HTMLDivElement>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const left = useCountdown(data.expiresIn, data.contractId) ?? 0;
  const status: ContractStatus = signedAt ? 'signed' : data.status && data.status !== 'pending' ? data.status : left <= 0 ? 'expired' : 'pending';
  const pending = status === 'pending';
  const info = pending ? null : statusInfo(status, 'buyer', data.seller.name);
  const signed = signatureReady(strokes);
  const canSign = pending && canAfford && signed && !busy;
  const padVisible = useInView(signRef, pending);
  // money can arrive (or go) while the buyer reads: ask the server again every few seconds
  useEffect(() => {
    if (!pending) return;
    let alive = true;
    const id = window.setInterval(() => {
      void request('contract:balance', { contractId: data.contractId }, { toastError: false }).then((res) => {
        if (alive && res.ok && res.data) setCanAfford(res.data.canAfford);
      });
    }, BALANCE_POLL);
    return () => {
      alive = false;
      window.clearInterval(id);
    };
  }, [pending, data.contractId]);
  useEffect(() => {
    if (!pending && status !== 'signed') scrollRef.current?.scrollTo({ top: 0, behavior: 'smooth' });
  }, [pending, status]);

  // closing a pending contract declines it: ask first
  const requestClose = () => {
    if (pending && !busy) setConfirm(true);
    else close();
  };
  useEscape(requestClose, !confirm);

  const sign = async () => {
    if (!canSign) return;
    setBusy(true);
    const res = await request('contract:sign', { contractId: data.contractId, signature: strokesToPath(strokes) });
    setBusy(false);
    if (!res.ok) return;
    setBought({ key: res.data?.key ?? null, copy: res.data?.copy === true });
    setSignedAt(res.data?.signedAt ?? Math.floor(Date.now() / 1000));
  };

  const banner = pending ? (
    <Banner icon="clock" tone={left <= 30 ? 'amber' : 'teal'} progress={left / Math.max(data.expiresIn, 1)}>
      {t('{name} signed this contract. Read it, then sign below to buy the vehicle.', { name: data.seller.name })}
    </Banner>
  ) : info ? (
    <Banner icon={info.icon} tone={info.tone}>
      {info.text}
    </Banner>
  ) : null;

  return (
    <>
      <Window
        className="nz-contract nz-contract--review"
        bodyClassName="nz-contract__body"
        width={780}
        title={t('Sale contract')}
        icon="receipt"
        subtitle={t('From {name}', { name: data.seller.name })}
        headerExtra={pending ? <Timer left={left} total={data.expiresIn} label={t('to sign')} /> : undefined}
        onClose={requestClose}
        closeLabel={pending ? t('Decline') : undefined}
      >
        <div className="nz-contract__scroll" ref={scrollRef}>
          <ContractDocument
            number={data.contractId}
            dated={data.createdAt}
            seller={data.seller}
            buyer={data.buyer}
            vehicle={data.vehicle}
            price={data.price}
            account={data.account}
            terms={data.terms}
            active={pending ? 'buyer' : null}
            signRef={signRef}
            banner={banner}
            stamp={info?.stamp ?? null}
            sellerSignature={<SignatureView path={data.sellerSignature} />}
            sellerCaption={t('Signed {when}', { when: dateTime(data.createdAt) })}
            buyerSignature={
              pending ? (
                <SignaturePad strokes={strokes} onChange={setStrokes} disabled={busy} placeholder={t('Sign here as the buyer')} />
              ) : (
                <SignatureView path={status === 'signed' ? strokesToPath(strokes) : ''} />
              )
            }
            buyerCaption={signedAt ? t('Signed {when}', { when: dateTime(signedAt) }) : undefined}
          />
        </div>

        <footer className="nz-contract__actions">
          {pending ? (
            <>
              <span className={clsx('nz-contract__pay', !canAfford && 'is-short')}>
                <Icon name={canAfford ? 'money' : 'warning'} size={15} strokeWidth={1.8} />
                <span>
                  <b>{canAfford ? t('You pay {amount}', { amount: money(data.price) }) : t('Not enough money')}</b>
                  <small>
                    {canAfford
                      ? t('From your {account}, the moment you sign', { account: accountLabel(data.account) })
                      : t('You need {amount} in your {account} to sign', { amount: money(data.price), account: accountLabel(data.account) })}
                  </small>
                </span>
              </span>
              <span className="nz-contract__spacer" />
              {!signed && !padVisible && (
                <Button variant="ghost" icon="edit" onClick={() => reveal(signRef)}>
                  {t('Sign below')}
                </Button>
              )}
              <Button variant="line" icon="ban" disabled={busy} onClick={() => setConfirm(true)}>
                {t('Decline')}
              </Button>
              <Button
                variant="teal"
                icon="check"
                badge={money(data.price)}
                disabled={!canSign}
                loading={busy}
                title={!canAfford ? t('Not enough money') : !signed ? t('Sign the contract first') : undefined}
                onClick={() => void sign()}
              >
                {t('Sign & pay')}
              </Button>
            </>
          ) : (
            <>
              <span className={clsx('nz-contract__foot-note', status === 'signed' && 'is-teal')}>
                <Icon name={status === 'signed' ? 'key' : 'info'} size={13} />
                {status === 'signed' ? boughtNote(bought.key, bought.copy) : t('Nothing was paid and nothing changed hands.')}
              </span>
              <span className="nz-contract__spacer" />
              <Button variant={status === 'signed' ? 'teal' : 'line'} icon={status === 'signed' ? 'check' : undefined} onClick={close}>
                {status === 'signed' ? t('Done') : t('Close')}
              </Button>
            </>
          )}
        </footer>
      </Window>

      <ConfirmDialog
        open={confirm}
        title={t('Decline this contract?')}
        message={t('{name} will be told right away. You can only sign a new contract they send you.', { name: data.seller.name })}
        confirmLabel={t('Decline')}
        cancelLabel={t('Keep reading')}
        tone="red"
        icon="ban"
        onConfirm={() => {
          setConfirm(false);
          close();
        }}
        onCancel={() => setConfirm(false)}
      />
    </>
  );
}

/* ───────────────────────── view (signed copy) ───────────────────────── */

function ReadView({ data, close }: { data: ContractViewData; close: () => void }) {
  useEscape(close, true);
  const copy = data.copy === 'seller' ? t('Seller\'s copy') : data.copy === 'buyer' ? t('Buyer\'s copy') : t('Copy');
  const banner = data.verified ? (
    <Banner icon="shield" tone="teal">
      {t('On record: this sale is in the vehicle\'s ownership history.')}
    </Banner>
  ) : (
    <Banner icon="warning" tone="amber">
      {t('Not on record: this copy does not match the vehicle\'s ownership history.')}
    </Banner>
  );
  const subtitle = useMemo(() => `${copy} · ${data.vehicle.plate}`, [copy, data.vehicle.plate]);

  return (
    <Window
      className="nz-contract nz-contract--view"
      bodyClassName="nz-contract__body"
      width={780}
      title={t('Sale contract')}
      icon="receipt"
      subtitle={subtitle}
      badge={
        data.verified ? (
          <Badge tone="teal" icon="checkCircle" size="sm">
            {t('Verified')}
          </Badge>
        ) : (
          <Badge tone="amber" icon="warning" size="sm">
            {t('Unverified')}
          </Badge>
        )
      }
      onClose={close}
    >
      <div className="nz-contract__scroll">
        <ContractDocument
          number={data.contractId}
          dated={data.signedAt}
          seller={data.seller}
          buyer={data.buyer}
          vehicle={data.vehicle}
          price={data.price}
          account={data.account ?? 'bank'}
          terms={data.terms}
          banner={banner}
          stamp={{ text: t('Sold'), tone: data.verified ? 'teal' : 'neutral' }}
          sellerSignature={<SignatureView path={data.sellerSignature} />}
          buyerSignature={<SignatureView path={data.buyerSignature} />}
          sellerCaption={data.createdAt ? t('Signed {when}', { when: dateTime(data.createdAt) }) : undefined}
          buyerCaption={t('Signed {when}', { when: dateTime(data.signedAt) })}
        />
      </div>
      <footer className="nz-contract__actions">
        <span className="nz-contract__foot-note">
          <Icon name="receipt" size={13} />
          {t('{copy} of the sale of {plate} on {when}', { copy, plate: data.vehicle.plate, when: dateTime(data.signedAt) })}
        </span>
        <span className="nz-contract__spacer" />
        <Button variant="line" onClick={close}>
          {t('Close')}
        </Button>
      </footer>
    </Window>
  );
}
