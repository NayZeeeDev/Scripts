/**
 * The contract itself, laid out like a real document in the NayZeee dark style: letterhead
 * (brand mark, title, number, date), parties, vehicle (plate, model, mileage, condition),
 * price, terms and the two signature lines. Draft, review and view all render this; the
 * signature lines take a pad or a finished signature.
 */
import type { ReactNode, Ref } from 'react';
import clsx from 'clsx';
import { Avatar, BrandMark, Icon, VehicleImage } from '@/components/ui';
import { t } from '@/lib/i18n';
import { date, distance, money, percent } from '@/lib/format';
import type { ContractParty, ContractVehicle } from '@/lib/types';

export type StampTone = 'teal' | 'red' | 'amber' | 'neutral';

export interface DocumentProps {
  /** contract id (null while drafting) */
  number: string | null;
  /** unix seconds of the document date (null = today) */
  dated: number | null;
  seller: ContractParty;
  buyer: ContractParty | null;
  vehicle: ContractVehicle | null;
  price: number | null;
  account: 'bank' | 'cash';
  terms: string;
  sellerSignature: ReactNode;
  buyerSignature: ReactNode;
  /** caption under a signature line (e.g. "Signed Nov 4 at 14:02") */
  sellerCaption?: ReactNode;
  buyerCaption?: ReactNode;
  /** the line the reader has to sign (highlighted) */
  active?: 'seller' | 'buyer' | null;
  stamp?: { text: string; tone: StampTone } | null;
  /** strip under the letterhead (status, countdown) */
  banner?: ReactNode;
  /** attached to the signature line being signed (scroll it into view) */
  signRef?: Ref<HTMLDivElement>;
  className?: string;
}

export function contractNumber(id: string | null): string {
  return id ? `NZ-${id.slice(0, 4)}-${id.slice(4)}` : t('Draft');
}

function conditionTone(value: number) {
  return value >= 70 ? 'is-good' : value >= 40 ? 'is-fair' : 'is-poor';
}

function Condition({ label, icon, value }: { label: string; icon: 'engine' | 'shield'; value: number }) {
  const v = percent(value);
  return (
    <div className={clsx('nz-contract__cond', conditionTone(v))}>
      <span className="nz-contract__cond-top">
        <Icon name={icon} size={12} strokeWidth={1.8} />
        <span>{label}</span>
        <b>{v}%</b>
      </span>
      <span className="nz-contract__cond-bar">
        <i style={{ width: `${v}%` }} />
      </span>
    </div>
  );
}

function Party({ role, party, placeholder }: { role: string; party: ContractParty | null; placeholder: string }) {
  return (
    <div className={clsx('nz-contract__party', !party && 'is-empty')}>
      <span className="nz-contract__label">{role}</span>
      <div className="nz-contract__party-row">
        {party ? <Avatar name={party.name} size={30} /> : <span className="nz-contract__party-blank"><Icon name="user" size={14} /></span>}
        <div className="nz-contract__party-text">
          <b title={party?.name}>{party ? party.name : placeholder}</b>
          <small>{party?.serverId !== undefined ? t('Citizen · ID {id}', { id: party.serverId }) : party ? t('Citizen') : t('Not chosen yet')}</small>
        </div>
      </div>
    </div>
  );
}

export function ContractDocument({
  number,
  dated,
  seller,
  buyer,
  vehicle,
  price,
  account,
  terms,
  sellerSignature,
  buyerSignature,
  sellerCaption,
  buyerCaption,
  active = null,
  stamp = null,
  banner,
  signRef,
  className,
}: DocumentProps) {
  const when = dated ?? Math.floor(Date.now() / 1000);
  const lines = terms.trim() ? terms.split('\n') : [];
  const accountText = account === 'cash' ? t('in cash') : t('by bank transfer');

  return (
    <article className={clsx('nz-contract__doc', className)} aria-label={t('Vehicle sale contract')}>
      <span className="nz-contract__doc-mark" aria-hidden="true" />
      <header className="nz-contract__head">
        <BrandMark size="md" />
        <div className="nz-contract__head-title">
          <span className="nz-contract__eyebrow">{t('Bill of sale · San Andreas')}</span>
          <h3>{t('Vehicle sale contract')}</h3>
        </div>
        <dl className="nz-contract__head-meta">
          <div>
            <dt>{t('No.')}</dt>
            <dd className="nz-contract__mono">{contractNumber(number)}</dd>
          </div>
          <div>
            <dt>{t('Date')}</dt>
            <dd>{date(when)}</dd>
          </div>
        </dl>
      </header>

      {banner}

      <section className="nz-contract__sec">
        <h4 className="nz-contract__h">{t('Parties')}</h4>
        <div className="nz-contract__parties">
          <Party role={t('Seller')} party={seller} placeholder="" />
          <span className="nz-contract__arrow" aria-hidden="true">
            <Icon name="arrowRight" size={14} />
          </span>
          <Party role={t('Buyer')} party={buyer} placeholder={t('Choose a buyer')} />
        </div>
      </section>

      <section className="nz-contract__sec">
        <h4 className="nz-contract__h">{t('Vehicle')}</h4>
        {vehicle ? (
          <div className="nz-contract__vehicle">
            <VehicleImage className="nz-contract__vimg" image={vehicle.image} vehicleType={vehicle.vehicleType} alt={vehicle.label} />
            <div className="nz-contract__vtext">
              <span className="nz-contract__make">{vehicle.make || t('Vehicle')}</span>
              <b title={vehicle.label}>{vehicle.label}</b>
              <small>
                {[vehicle.classLabel, vehicle.nickname ? `“${vehicle.nickname}”` : null].filter(Boolean).join(' · ') || vehicle.model}
              </small>
            </div>
            <span className="nz-contract__plate">
              <small>{t('San Andreas')}</small>
              <b>{vehicle.plate}</b>
            </span>
          </div>
        ) : (
          <div className="nz-contract__vehicle is-empty">
            <Icon name="car" size={18} />
            <span>{t('Choose one of your vehicles')}</span>
          </div>
        )}
        {vehicle && (
          <div className="nz-contract__specs">
            <div className="nz-contract__spec">
              <span className="nz-contract__label">{t('Mileage')}</span>
              <b>{distance(vehicle.mileage)}</b>
            </div>
            <Condition label={t('Engine')} icon="engine" value={vehicle.engine} />
            <Condition label={t('Body')} icon="shield" value={vehicle.body} />
          </div>
        )}
      </section>

      <section className="nz-contract__sec nz-contract__sec--price">
        <div>
          <h4 className="nz-contract__h">{t('Price')}</h4>
          <p className="nz-contract__small">{t('Paid in full {account} on signing.', { account: accountText })}</p>
        </div>
        <b className={clsx('nz-contract__price', price === null && 'is-empty')}>{price === null ? '—' : money(price)}</b>
      </section>

      <section className="nz-contract__sec">
        <h4 className="nz-contract__h">{t('Terms')}</h4>
        {lines.length ? (
          <div className="nz-contract__terms">
            {lines.map((line, i) => (line.trim() ? <p key={i}>{line}</p> : <br key={i} />))}
          </div>
        ) : (
          <p className="nz-contract__small">{t('No further terms: the vehicle is sold as it stands.')}</p>
        )}
      </section>

      <section className="nz-contract__sec nz-contract__sec--sign">
        <h4 className="nz-contract__h">{t('Signatures')}</h4>
        <div className="nz-contract__signs">
          <div ref={active === 'seller' ? signRef : undefined} className={clsx('nz-contract__sign', active === 'seller' && 'is-active')}>
            <div className="nz-contract__sign-box">{sellerSignature}</div>
            <div className="nz-contract__sign-line">
              <b>{seller.name}</b>
              <span>{t('Seller')}</span>
            </div>
            {sellerCaption && <small className="nz-contract__sign-cap">{sellerCaption}</small>}
          </div>
          <div ref={active === 'buyer' ? signRef : undefined} className={clsx('nz-contract__sign', active === 'buyer' && 'is-active')}>
            <div className="nz-contract__sign-box">{buyerSignature}</div>
            <div className="nz-contract__sign-line">
              <b>{buyer ? buyer.name : '—'}</b>
              <span>{t('Buyer')}</span>
            </div>
            {buyerCaption && <small className="nz-contract__sign-cap">{buyerCaption}</small>}
          </div>
        </div>
      </section>

      {stamp && (
        <span className={clsx('nz-contract__stamp', `is-${stamp.tone}`)} aria-label={stamp.text}>
          {stamp.text}
        </span>
      )}
    </article>
  );
}

