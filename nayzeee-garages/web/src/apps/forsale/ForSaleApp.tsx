/**
 * Garage for sale (app 'forSale'): a compact card for a purchasable private garage —
 * copies left, storage type, parking, interior, interior tour and buy — with a confirm
 * step inside the same window (Back / Escape returns to the details).
 */
import { useState } from 'react';
import { Badge, Button, Icon, InfoDot, Window } from '@/components/ui';
import { useApp } from '@/lib/store';
import { useEscape } from '@/lib/escape';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import { money } from '@/lib/format';
import type { ForSaleData } from '@/lib/types';
import './forsale.css';

export function ForSaleApp() {
  const { open, data, close } = useApp('forSale');
  useEscape(close, open);
  if (!open || !data) return null;
  return <ForSaleWindow key={data.locationId} data={data} close={close} />;
}

function storageLabel(storage: ForSaleData['storage']) {
  return storage === 'shared' ? t('Shared vehicles') : t('Personal vehicles');
}

function spacesLabel(spaces: number | null) {
  if (spaces === null || spaces <= 0) return t('Unlimited spaces');
  return spaces === 1 ? t('1 space in total') : t('{n} spaces in total', { n: spaces });
}

function ForSaleWindow({ data, close }: { data: ForSaleData; close: () => void }) {
  const [step, setStep] = useState<'details' | 'confirm'>('details');
  const [busy, setBusy] = useState<'tour' | 'buy' | null>(null);
  useEscape(() => {
    if (!busy) setStep('details');
  }, step === 'confirm');

  const soldOut = data.available <= 0;
  const blocked = soldOut ? t('Sold out — every copy of this garage already has an owner.') : !data.canAfford ? t('You cannot afford this garage right now.') : null;

  const tour = async () => {
    setBusy('tour');
    const res = await request('forSale:tour', { locationId: data.locationId });
    if (!res.ok) setBusy(null);
  };

  const buy = async () => {
    setBusy('buy');
    const res = await request('forSale:buy', { locationId: data.locationId });
    if (!res.ok) setBusy(null);
  };

  const availability =
    data.total > 0 ? (
      <Badge tone={soldOut ? 'red' : 'teal'} icon={soldOut ? 'ban' : 'checkCircle'} size="sm">
        {soldOut ? t('Sold out') : t('{available} of {total} available', { available: data.available, total: data.total })}
      </Badge>
    ) : (
      <Badge tone="teal" icon="checkCircle" size="sm">
        {t('Available')}
      </Badge>
    );

  return (
    <Window
      className="nz-forsale"
      bodyClassName="nz-forsale__body"
      width={500}
      title={step === 'confirm' ? t('Confirm purchase') : t('Garage for sale')}
      icon={step === 'confirm' ? 'cart' : 'tag'}
      onClose={close}
    >
      {step === 'details' ? (
        <div className="nz-forsale__view" key="details">
          <div className="nz-forsale__hero">
            <span className="nz-forsale__tile">
              <Icon name="garage" size={22} strokeWidth={1.5} />
            </span>
            <div className="nz-forsale__title">
              <b title={data.name}>{data.name}</b>
              <span className="nz-forsale__badges">
                {availability}
                <Badge tone="neutral" icon={data.storage === 'shared' ? 'users' : 'user'} size="sm">
                  {storageLabel(data.storage)}
                </Badge>
              </span>
            </div>
            <div className="nz-forsale__price">
              <span>{t('Price')}</span>
              <b>{money(data.price)}</b>
            </div>
          </div>

          <div className="nz-forsale__grid">
            <div className="nz-forsale__info">
              <span className="nz-forsale__label">{t('Storage')}</span>
              <span className="nz-forsale__value">
                <span className="nz-forsale__text">{storageLabel(data.storage)}</span>
                <span className="nz-forsale__dot">
                  <InfoDot
                    text={
                      data.storage === 'shared'
                        ? t('Every member sees and can drive every vehicle stored here. Ownership never changes.')
                        : t('Members share the garage, but each one only sees their own vehicles.')
                    }
                  />
                </span>
              </span>
            </div>
            <div className="nz-forsale__info">
              <span className="nz-forsale__label">{t('Parking')}</span>
              <span className="nz-forsale__value">
                <span className="nz-forsale__text">{spacesLabel(data.spaces)}</span>
              </span>
            </div>
            <div className="nz-forsale__info">
              <span className="nz-forsale__label">{t('Interior')}</span>
              <span className="nz-forsale__value" title={data.interiorName ?? undefined}>
                <span className="nz-forsale__text">{data.interiorName ?? t('Outdoor parking only')}</span>
              </span>
            </div>
          </div>

          {blocked && (
            <div className="nz-forsale__blocked">
              <Icon name={soldOut ? 'ban' : 'money'} size={14} strokeWidth={1.8} />
              <span>{blocked}</span>
            </div>
          )}

          <div className="nz-forsale__actions">
            {data.canTour && (
              <Button icon="walk" loading={busy === 'tour'} disabled={!!busy} onClick={() => void tour()}>
                {t('Interior tour')}
              </Button>
            )}
            <span className="nz-forsale__spacer" />
            <Button
              variant="white"
              icon="cart"
              badge={money(data.price)}
              disabled={!!blocked || !!busy}
              title={blocked ?? undefined}
              onClick={() => setStep('confirm')}
            >
              {t('Buy garage')}
            </Button>
          </div>
        </div>
      ) : (
        <div className="nz-forsale__view nz-forsale__confirm" key="confirm">
          <span className="nz-forsale__cart">
            <Icon name="cart" size={22} strokeWidth={1.5} />
          </span>
          <h3>{t('Buy {name} for {price}?', { name: data.name, price: money(data.price) })}</h3>
          <p>{t('You become the owner of your own copy of this garage, with its own members and vehicles.')}</p>
          <ul className="nz-forsale__checks">
            <li>
              <Icon name="check" size={13} strokeWidth={2.2} />
              {t('Add members and invite guests from inside the garage.')}
            </li>
            <li>
              <Icon name="check" size={13} strokeWidth={2.2} />
              {t('{storage} storage, {spaces}.', {
                storage: storageLabel(data.storage),
                spaces: spacesLabel(data.spaces).toLowerCase(),
              })}
            </li>
            <li>
              <Icon name="check" size={13} strokeWidth={2.2} />
              {t('Sell it any time once it is empty.')}
            </li>
          </ul>
          <div className="nz-forsale__actions">
            <Button icon="arrowLeft" disabled={busy === 'buy'} onClick={() => setStep('details')}>
              {t('Back')}
            </Button>
            <span className="nz-forsale__spacer" />
            <Button variant="teal" icon="check" badge={money(data.price)} loading={busy === 'buy'} autoFocus onClick={() => void buy()}>
              {t('Confirm purchase')}
            </Button>
          </div>
        </div>
      )}
    </Window>
  );
}
