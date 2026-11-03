/**
 * The six panels of the vehicle detail dashboard: Details, Impound, Installed mods, Finance,
 * Ownership history and Service history.
 */
import type { ReactNode } from 'react';
import { Badge, Bar, Button, EmptyState, Icon, IconButton, Panel, Pips, Ring, Tooltip, autoTone, cx } from '@/components/ui';
import type { IconName } from '@/components/ui';
import { t } from '@/lib/i18n';
import { date, dateTime, distance, hoursLabel, money, percent } from '@/lib/format';
import type { AdminVehicleDetail } from '@/lib/types';
import { KeyValue, PanelFoot, Timeline } from './common';
import { PERF_MODS, inGarageLabel, installedModCount, ownerTypeLabel, perfModValue, viaLabel } from './util';

const PREVIEW = 3;

function Gauge({ icon, label, value }: { icon: IconName; label: string; value: number }) {
  const v = percent(value);
  return (
    <div className={cx('nz-aveh-gauge', `is-${autoTone(v)}`)}>
      <Ring value={v} size={40} stroke={3} tone="auto">
        <Icon name={icon} size={14} strokeWidth={1.7} />
      </Ring>
      <div>
        <span>{label}</span>
        <b>{v}%</b>
      </div>
    </div>
  );
}

function Shell({ title, icon, actions, children, className }: { title: string; icon: IconName; actions?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <Panel title={title} icon={icon} actions={actions} className={cx('nz-aveh-dpanel', className)} bodyClassName="nz-aveh-dpanel__body">
      {children}
    </Panel>
  );
}

/* ── Details ──────────────────────────────────────────────────────────── */

export function DetailsPanel({ detail, onEdit, jobLabel }: { detail: AdminVehicleDetail; onEdit: () => void; jobLabel: string | null }) {
  const v = detail.vehicle;
  return (
    <Shell title={t('Details')} icon="car" actions={<IconButton icon="edit" size="sm" label={t('Edit details')} onClick={onEdit} />}>
      <div className="nz-aveh-gauges">
        <Gauge icon="fuel" label={t('Fuel')} value={v.fuel} />
        <Gauge icon="engine" label={t('Engine')} value={v.engine} />
        <Gauge icon="shield" label={t('Body')} value={v.body} />
      </div>
      <div className="nz-aveh-kvgrid is-3">
        <KeyValue label={t('Garage')}>{v.garageName ?? <span className="nz-aveh-muted">{t('None')}</span>}</KeyValue>
        <KeyValue label={t('In garage')}>
          <span className={cx(v.state === 'impounded' && 'nz-aveh-red', v.state === 'garaged' && 'nz-aveh-teal')}>{inGarageLabel(v.state)}</span>
        </KeyValue>
        <KeyValue label={t('Mileage')}>{distance(v.mileage)}</KeyValue>
        <KeyValue label={t('Nickname')}>{v.nickname ?? <span className="nz-aveh-muted">{t('None')}</span>}</KeyValue>
        <KeyValue label={t('Owner type')}>{ownerTypeLabel(v.ownerType)}</KeyValue>
        <KeyValue label={t('Job / gang')}>{jobLabel ?? <span className="nz-aveh-muted">{t('None')}</span>}</KeyValue>
      </div>
    </Shell>
  );
}

/* ── Impound ──────────────────────────────────────────────────────────── */

export function ImpoundPanel({ detail, onEdit }: { detail: AdminVehicleDetail; onEdit: () => void }) {
  const imp = detail.impound;
  const now = Math.floor(Date.now() / 1000);
  const waitH = imp ? Math.max(0, (imp.releaseAt - now) / 3600) : 0;
  return (
    <Shell
      title={t('Impound')}
      icon="impound"
      className={cx(imp && 'is-alert')}
      actions={<IconButton icon="edit" size="sm" label={imp ? t('Edit impound') : t('Impound vehicle')} onClick={onEdit} />}
    >
      {!imp ? (
        <EmptyState
          compact
          icon="parking"
          title={t('Not impounded')}
          description={t('The vehicle is free to use.')}
          action={
            <Button size="sm" variant="line" icon="impound" onClick={onEdit} disabled={!detail.impounds.length}>
              {t('Impound')}
            </Button>
          }
          className="nz-aveh-dpanel__empty"
        />
      ) : (
        <>
          <div className="nz-aveh-imphead">
            <span className="nz-aveh-imphead__icon">
              <Icon name="impound" size={16} strokeWidth={1.7} />
            </span>
            <div>
              <b className="nz-aveh-ellipsis">{imp.locationName}</b>
              <span>{t('since {when}', { when: dateTime(imp.at) })}</span>
            </div>
            {imp.retrievable ? (
              <Badge tone={waitH > 0 ? 'amber' : 'teal'} size="sm" icon="clock">
                {waitH > 0 ? t('in {time}', { time: hoursLabel(waitH) }) : t('Retrievable')}
              </Badge>
            ) : (
              <Badge tone="red" size="sm" icon="lock">
                {t('Staff only')}
              </Badge>
            )}
          </div>
          <div className="nz-aveh-kvgrid">
            <KeyValue label={t('Reason')}>
              <Tooltip content={imp.reason}>
                <span className="nz-aveh-ellipsis">{imp.reason || <span className="nz-aveh-muted">{t('No reason given')}</span>}</span>
              </Tooltip>
            </KeyValue>
            <KeyValue label={t('Fee')}>{money(imp.fee)}</KeyValue>
            <KeyValue label={t('Impounded by')}>{imp.byName || <span className="nz-aveh-muted">{t('Unknown')}</span>}</KeyValue>
            <KeyValue label={t('Release')}>{imp.releaseAt > now ? dateTime(imp.releaseAt) : t('Now')}</KeyValue>
          </div>
        </>
      )}
    </Shell>
  );
}

/* ── Installed mods ───────────────────────────────────────────────────── */

export function ModsPanel({ detail, onEdit, onViewAll }: { detail: AdminVehicleDetail; onEdit: () => void; onViewAll: () => void }) {
  const props = detail.vehicle.props ?? {};
  const n = installedModCount(props);
  return (
    <Shell title={t('Installed mods')} icon="wrench" actions={<IconButton icon="edit" size="sm" label={t('Edit vehicle props')} onClick={onEdit} />}>
      <div className="nz-aveh-mods">
        {PERF_MODS.map((m) => {
          const val = perfModValue(m, props);
          return (
            <div key={m.key} className={cx('nz-aveh-mods__item', val.on && 'is-on')}>
              <span>{m.label()}</span>
              <b>{val.text}</b>
              {m.max > 0 ? <Pips total={m.max} done={val.level} tone={val.on ? 'teal' : 'neutral'} /> : <Pips total={1} done={val.on ? 1 : 0} tone={val.on ? 'teal' : 'neutral'} />}
            </div>
          );
        })}
      </div>
      <PanelFoot summary={t('{n} installed', { n })} onViewAll={onViewAll} />
    </Shell>
  );
}

/* ── Finance ──────────────────────────────────────────────────────────── */

export function FinancePanel({ detail, onEdit, onDelete }: { detail: AdminVehicleDetail; onEdit: () => void; onDelete: () => void }) {
  const f = detail.finance;
  const total = f && f.paymentsTotal ? f.paymentsTotal * f.payment : null;
  const made = f && f.paymentsTotal ? Math.max(0, f.paymentsTotal - f.paymentsLeft) : null;
  return (
    <Shell
      title={t('Finance')}
      icon="money"
      className={cx(f?.overdue && 'is-alert')}
      actions={
        <>
          {f?.overdue && (
            <Badge tone="red" size="sm" icon="warning">
              {t('Overdue')}
            </Badge>
          )}
          <IconButton icon={f ? 'edit' : 'plus'} size="sm" label={f ? t('Edit finance') : t('Add finance')} onClick={onEdit} />
          {f && <IconButton icon="trash" size="sm" variant="red" label={t('Delete finance')} onClick={onDelete} />}
        </>
      }
    >
      {!f ? (
        <EmptyState
          compact
          icon="money"
          title={t('No finance')}
          description={t('The vehicle is fully paid off.')}
          action={
            <Button size="sm" variant="line" icon="plus" onClick={onEdit}>
              {t('Add finance')}
            </Button>
          }
          className="nz-aveh-dpanel__empty"
        />
      ) : (
        <>
          <div className="nz-aveh-fin__top">
            <b>{money(f.balance)}</b>
            <span>{total ? t('remaining of {total}', { total: money(total) }) : t('remaining')}</span>
          </div>
          <Bar value={total ? total - f.balance : 0} max={total ?? 1} height={6} tone="white" className="nz-aveh-fin__bar" />
          <div className="nz-aveh-kvgrid is-3">
            <KeyValue label={t('Next payment')}>
              <span className={cx(f.overdue && 'nz-aveh-red')}>
                {f.overdue ? t('Overdue') : f.nextPaymentHours != null ? t('in {time}', { time: hoursLabel(f.nextPaymentHours) }) : '—'}
              </span>
            </KeyValue>
            <KeyValue label={f.intervalHours ? t('Every {time}', { time: hoursLabel(f.intervalHours) }) : t('Payment')}>{money(f.payment)}</KeyValue>
            <KeyValue label={t('Payments made')}>
              {made !== null ? t('{made} of {total}', { made, total: f.paymentsTotal ?? 0 }) : t('{n} left', { n: f.paymentsLeft })}
            </KeyValue>
          </div>
        </>
      )}
    </Shell>
  );
}

/* ── Ownership ────────────────────────────────────────────────────────── */

export function OwnershipPanel({ detail, onViewAll }: { detail: AdminVehicleDetail; onViewAll: () => void }) {
  const list = detail.ownership;
  return (
    <Shell title={t('Ownership history')} icon="history">
      {list.length === 0 ? (
        <EmptyState compact icon="history" title={t('No ownership records')} className="nz-aveh-dpanel__empty" />
      ) : (
        <Timeline
          items={list.slice(0, PREVIEW).map((o, i) => ({
            key: `${o.identifier ?? 'x'}-${o.at}-${i}`,
            current: i === 0,
            title: o.name || t('Unknown'),
            meta: `${viaLabel(o.via)} · ${date(o.at)}`,
            aside: o.price ? money(o.price) : undefined,
          }))}
        />
      )}
      <PanelFoot summary={list.length === 1 ? t('1 owner') : t('{n} owners', { n: list.length })} onViewAll={onViewAll} viewAllDisabled={!list.length} />
    </Shell>
  );
}

/* ── Service ──────────────────────────────────────────────────────────── */

export function ServicePanel({ detail, onEdit, onViewAll }: { detail: AdminVehicleDetail; onEdit: () => void; onViewAll: () => void }) {
  const list = [...detail.service].sort((a, b) => b.at - a.at);
  return (
    <Shell title={t('Service history')} icon="wrench" actions={<IconButton icon="edit" size="sm" label={t('Edit service history')} onClick={onEdit} />}>
      {list.length === 0 ? (
        <EmptyState
          compact
          icon="wrench"
          title={t('No service records')}
          action={
            <Button size="sm" variant="line" icon="plus" onClick={onEdit}>
              {t('Add entry')}
            </Button>
          }
          className="nz-aveh-dpanel__empty"
        />
      ) : (
        <Timeline
          items={list.slice(0, PREVIEW).map((s, i) => ({
            key: s.id ?? `${s.at}-${i}`,
            current: i === 0,
            title: s.item,
            meta: `${s.shop || t('Unknown shop')} · ${date(s.at)}`,
            aside: <span className="nz-aveh-mono">{distance(s.mileage)}</span>,
          }))}
        />
      )}
      <PanelFoot summary={list.length === 1 ? t('1 record') : t('{n} records', { n: list.length })} onViewAll={onViewAll} viewAllDisabled={!list.length} />
    </Shell>
  );
}
