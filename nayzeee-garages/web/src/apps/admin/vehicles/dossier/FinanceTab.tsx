/**
 * Finance tab: balance, payment, payments made (pips + bar), interval, next payment or
 * overdue state and the projected payoff, all derived from the Finance record.
 */
import { Bar, Button, EmptyState, Icon, Pips, Tooltip, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import { date, dateTime, hoursLabel, money } from '@/lib/format';
import type { AdminVehicleDetail } from '@/lib/types';
import { actorOf } from './activity';
import { ago, inTime, nowS } from './data';
import { Fact, Heading } from './parts';
import type { ActivityState } from './useActivity';

interface Props {
  detail: AdminVehicleDetail;
  activity: ActivityState;
  onEdit: () => void;
  onActivity: () => void;
}

const SCHEDULE = 5;

export function FinanceTab({ detail, activity, onEdit, onActivity }: Props) {
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

  // Upcoming payments, projected from the agreement (next payment, then one per interval).
  const schedule =
    f.nextPaymentHours != null && f.intervalHours && f.paymentsLeft > 0
      ? Array.from({ length: Math.min(SCHEDULE, f.paymentsLeft) }, (_, i) => {
          const at = nowS() + Math.round((Math.max(0, f.nextPaymentHours ?? 0) + i * (f.intervalHours ?? 0)) * 3600);
          const amount = Math.min(f.payment, Math.max(0, f.balance - i * f.payment));
          return {
            n: (made ?? 0) + i + 1,
            at,
            amount,
            after: Math.max(0, f.balance - (i + 1) * f.payment),
            last: i === f.paymentsLeft - 1,
          };
        })
      : [];
  // Payments the log recorded (newest page only).
  const recorded = (activity.latest?.rows ?? []).filter((r) => r.event === 'vehicle.finance').slice(0, 4);

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

          {schedule.length > 0 && (
            <>
              <Heading className="nz-dos-h--gap" count={f.paymentsLeft > SCHEDULE ? t('next {n}', { n: SCHEDULE }) : undefined}>
                {t('Upcoming')}
              </Heading>
              <ol className="nz-dos-sched">
                {schedule.map((p, i) => (
                  <li key={p.n} className={cx(i === 0 && 'is-next', i === 0 && f.overdue && 'is-overdue')}>
                    <span className="nz-dos-sched__n">#{p.n}</span>
                    <Tooltip content={dateTime(p.at)}>
                      <span className="nz-dos-sched__when">{i === 0 && f.overdue ? t('Overdue') : inTime(p.at)}</span>
                    </Tooltip>
                    <span className="nz-dos-sched__date">{date(p.at)}</span>
                    <b>{money(p.amount)}</b>
                    <span className="nz-dos-sched__after">{p.last ? t('Paid off') : t('{amount} left', { amount: money(p.after) })}</span>
                  </li>
                ))}
              </ol>
            </>
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
            <Fact label={t('Total financed')} icon="receipt" tone={total === null ? 'muted' : undefined}>
              {total !== null ? money(total) : t('Unknown')}
            </Fact>
            <Fact label={t('Projected payoff')} icon="calendar" tone={payoffAt ? undefined : 'muted'}>
              {payoffAt ? date(payoffAt) : t('Unknown')}
            </Fact>
          </div>

          <Heading
            className="nz-dos-h--gap"
            actions={
              <Button size="sm" variant="ghost" iconRight="arrowRight" onClick={onActivity}>
                {t('Log')}
              </Button>
            }
          >
            {t('Recorded payments')}
          </Heading>
          {recorded.length === 0 ? (
            <p className="nz-dos-note">
              <Icon name="info" size={13} strokeWidth={1.7} />
              {activity.latest ? t('No payments in the recent activity.') : t('Loading the activity…')}
            </p>
          ) : (
            <ul className="nz-dos-paid">
              {recorded.map((r) => {
                const d = r.data ?? {};
                const amount = typeof d.amount === 'number' ? d.amount : 0;
                return (
                  <li key={r.id}>
                    <Icon name={d.paidOff ? 'checkCircle' : 'money'} size={13} strokeWidth={1.7} />
                    <b>{money(amount)}</b>
                    <span className="nz-aveh-ellipsis">{actorOf(r)}</span>
                    <Tooltip content={dateTime(r.at)} side="left">
                      <em>{ago(r.at)}</em>
                    </Tooltip>
                  </li>
                );
              })}
            </ul>
          )}
        </section>
      </div>
    </div>
  );
}
