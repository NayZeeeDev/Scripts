/**
 * Finance tab: balance, payment, payments made (pips + bar), interval, next payment or
 * overdue state and the projected payoff, all derived from the Finance record.
 */
import { Bar, Button, EmptyState, Icon, Pips, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import { date, hoursLabel, money } from '@/lib/format';
import type { AdminVehicleDetail } from '@/lib/types';
import { nowS } from './data';
import { Fact, Heading } from './parts';

interface Props {
  detail: AdminVehicleDetail;
  onEdit: () => void;
}

export function FinanceTab({ detail, onEdit }: Props) {
  const f = detail.finance;
  if (!f) {
    return (
      <div className="nz-dos-pane nz-dos-pane--center">
        <EmptyState
          icon="money"
          title={t('No finance')}
          description={t('{vehicle} is fully paid off. Add a finance agreement to collect recurring payments from the owner.', { vehicle: detail.vehicle.label })}
          action={
            <Button size="sm" variant="teal" icon="plus" onClick={onEdit}>
              {t('Add finance')}
            </Button>
          }
        />
      </div>
    );
  }

  const totalPayments = f.paymentsTotal ?? null;
  const made = totalPayments ? Math.max(0, totalPayments - f.paymentsLeft) : null;
  const total = totalPayments ? totalPayments * f.payment : null;
  const paid = total !== null ? Math.max(0, total - f.balance) : null;
  const pct = total ? Math.round((paid! / total) * 100) : null;
  // Projected payoff: next payment, then one payment per interval.
  const payoffAt =
    f.nextPaymentHours != null && f.intervalHours
      ? nowS() + Math.round((Math.max(0, f.nextPaymentHours) + Math.max(0, f.paymentsLeft - 1) * f.intervalHours) * 3600)
      : null;

  return (
    <div className="nz-dos-pane">
      <div className="nz-dos-sheet nz-dos-fin">
        <section className="nz-dos-col nz-dos-fin__main">
          <Heading>{t('Balance')}</Heading>
          <div className="nz-dos-fin__balance">
            <b>{money(f.balance)}</b>
            <span>{total !== null ? t('left of {total}', { total: money(total) }) : t('left to pay')}</span>
          </div>
          {pct !== null && (
            <div className="nz-dos-fin__progress">
              <Bar value={pct} height={8} tone="teal" />
              <div>
                <span>{t('{pct}% paid', { pct })}</span>
                <span>{t('{amount} paid so far', { amount: money(paid ?? 0) })}</span>
              </div>
            </div>
          )}

          <Heading className="nz-dos-h--gap" count={made !== null && totalPayments ? `${made}/${totalPayments}` : undefined}>
            {t('Payments')}
          </Heading>
          {totalPayments ? (
            <div className="nz-dos-fin__pips">
              <Pips total={totalPayments} done={made ?? 0} tone={f.overdue ? 'red' : 'teal'} />
              <span>{t('{made} made · {left} left', { made: made ?? 0, left: f.paymentsLeft })}</span>
            </div>
          ) : (
            <p className="nz-dos-note">{t('{n} payments left', { n: f.paymentsLeft })}</p>
          )}
        </section>

        <section className="nz-dos-col nz-dos-fin__side">
          <div className={cx('nz-dos-fin__next', f.overdue && 'is-overdue')}>
            <span className="nz-dos-fin__next-icon">
              <Icon name={f.overdue ? 'warning' : 'clock'} size={18} strokeWidth={1.7} />
            </span>
            <div>
              <span>{f.overdue ? t('Payment overdue') : t('Next payment')}</span>
              <b>{f.overdue ? money(f.payment) : f.nextPaymentHours != null ? t('in {time}', { time: hoursLabel(f.nextPaymentHours) }) : '—'}</b>
              <em>{f.overdue ? t('The owner missed a payment.') : t('{amount} will be charged', { amount: money(f.payment) })}</em>
            </div>
          </div>
          <Heading>{t('Agreement')}</Heading>
          <div className="nz-dos-facts">
            <Fact label={t('Payment')} icon="money">
              {money(f.payment)}
            </Fact>
            <Fact label={t('Interval')} icon="clock" tone={f.intervalHours ? undefined : 'muted'}>
              {f.intervalHours ? t('Every {time}', { time: hoursLabel(f.intervalHours) }) : t('Not set')}
            </Fact>
            <Fact label={t('Total price')} icon="receipt" tone={total === null ? 'muted' : undefined}>
              {total !== null ? money(total) : t('Unknown')}
            </Fact>
            <Fact label={t('Projected payoff')} icon="calendar" tone={payoffAt ? undefined : 'muted'}>
              {payoffAt ? date(payoffAt) : t('Unknown')}
            </Fact>
          </div>
        </section>
      </div>
    </div>
  );
}
