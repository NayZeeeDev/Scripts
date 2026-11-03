/**
 * Overview tab: attention callouts, then one sheet with three columns — facts, condition
 * at a glance (gauges + damage glyph) and the five latest activity entries.
 */
import { Button, EmptyState, Icon, Skeleton, Tooltip, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import { date, dateTime, distance, hoursLabel, money, percent } from '@/lib/format';
import type { AdminOpenData, AdminVehicleDetail } from '@/lib/types';
import { PERF_MODS, installedModCount, ownerTypeLabel, perfModValue, stateLabel } from '../util';
import type { Props as VProps } from '../props/catalog';
import { ActivityRow } from './ActivityTab';
import { DamageDiagram } from './DamageDiagram';
import { ago, damageCaption, groupLabel, hasVisibleDamage, inTime, nowS, swatchOf } from './data';
import type { DamageSummary } from '@/lib/types';
import { Callout, ColourChip, Fact, Heading, SegGauge } from './parts';
import type { ActivityState } from './useActivity';
import type { DossierTab } from './tabs';

interface Props {
  detail: AdminVehicleDetail;
  data: AdminOpenData;
  damage: DamageSummary | null;
  props: VProps;
  activity: ActivityState;
  needsService: boolean;
  onTab: (tab: DossierTab) => void;
  onEditCondition: () => void;
  onRelease: () => void;
  onUnblock: () => void;
  busy: string | null;
}

export function OverviewTab({ detail, data, damage, props, activity, needsService, onTab, onEditCondition, onRelease, onUnblock, busy }: Props) {
  const v = detail.vehicle;
  const f = detail.finance;
  const imp = detail.impound;
  const threshold = data.settings.vehicles.needsServiceBelow;

  const callouts = [];
  if (imp) {
    const wait = imp.releaseAt - nowS();
    callouts.push(
      <Callout
        key="imp"
        tone="red"
        icon="impound"
        title={t('Impounded at {impound}', { impound: imp.locationName })}
        action={
          <Button size="sm" variant="line" icon="unlock" onClick={onRelease} loading={busy === 'release'}>
            {t('Release')}
          </Button>
        }
      >
        {[
          !imp.retrievable ? t('Staff release only') : wait > 0 ? t('Retrievable {when}', { when: inTime(imp.releaseAt) }) : t('Retrievable now'),
          t('fee {fee}', { fee: money(imp.fee) }),
          imp.reason || null,
        ]
          .filter(Boolean)
          .join(' · ')}
      </Callout>,
    );
  }
  if (v.blocked) {
    callouts.push(
      <Callout
        key="blk"
        tone="red"
        icon="ban"
        title={t('Blocked')}
        action={
          <Button size="sm" variant="line" icon="unlock" onClick={onUnblock} loading={busy === 'block'}>
            {t('Unblock')}
          </Button>
        }
      >
        {t('The owner cannot take it out of any garage.')}
      </Callout>,
    );
  }
  if (f?.overdue) {
    callouts.push(
      <Callout
        key="fin"
        tone="red"
        icon="money"
        title={t('Finance payment overdue')}
        action={
          <Button size="sm" variant="ghost" iconRight="arrowRight" onClick={() => onTab('finance')}>
            {t('Finance')}
          </Button>
        }
      >
        {t('{payment} per payment · {balance} left', { payment: money(f.payment), balance: money(f.balance) })}
      </Callout>,
    );
  } else if (f) {
    callouts.push(
      <Callout
        key="fin"
        tone="blue"
        icon="calendar"
        title={f.nextPaymentHours != null ? t('Next payment in {time}', { time: hoursLabel(f.nextPaymentHours) }) : t('Financed')}
        action={
          <Button size="sm" variant="ghost" iconRight="arrowRight" onClick={() => onTab('finance')}>
            {t('Finance')}
          </Button>
        }
      >
        {t('{payment} · {balance} left', { payment: money(f.payment), balance: money(f.balance) })}
      </Callout>,
    );
  }
  if (needsService) {
    callouts.push(
      <Callout
        key="svc"
        tone="amber"
        icon="wrench"
        title={t('Needs service')}
        action={
          <Button size="sm" variant="ghost" icon="edit" onClick={onEditCondition}>
            {t('Edit')}
          </Button>
        }
      >
        {t('Engine at {n}%, below the {limit}% service threshold.', { n: percent(v.engine), limit: threshold })}
      </Callout>,
    );
  }
  if (hasVisibleDamage(damage) && !needsService) {
    callouts.push(
      <Callout
        key="dmg"
        tone="amber"
        icon="warning"
        title={t('Visible damage')}
        action={
          <Button size="sm" variant="ghost" iconRight="arrowRight" onClick={() => onTab('condition')}>
            {t('Condition')}
          </Button>
        }
      >
        {damageCaption(damage)}
      </Callout>,
    );
  }

  const group = groupLabel(detail, data);
  const since = detail.ownership[0]?.at ?? null;
  const latest = activity.latest?.rows.slice(0, 5) ?? null;
  const typeLabel = v.vehicleType === 'sea' ? t('Boat') : v.vehicleType === 'air' ? t('Aircraft') : t('Land vehicle');

  return (
    <div className="nz-dos-pane nz-dos-ov">
      {callouts.length > 0 ? (
        <div className={cx('nz-dos-ov__callouts', callouts.length > 2 && 'is-many')}>{callouts}</div>
      ) : (
        <div className="nz-dos-ov__clear">
          <i aria-hidden="true" />
          {t('All clear: nothing needs attention on this vehicle.')}
        </div>
      )}

      <div className="nz-dos-sheet nz-dos-ov__sheet">
        <section className="nz-dos-col">
          <Heading>{t('Facts')}</Heading>
          <div className="nz-dos-facts">
            <Fact label={t('Garage')} icon="garage" tone={!v.garageName && !imp ? 'muted' : undefined}>
              {imp ? imp.locationName : v.garageName ?? t('None')}
            </Fact>
            <Fact label={t('State')} icon="parking" tone={v.state === 'impounded' ? 'red' : v.state === 'garaged' ? 'teal' : undefined}>
              <span className={cx('nz-dos-dot', `is-${v.state}`)} />
              {stateLabel(v.state)}
            </Fact>
            <Fact label={t('Last driven')} icon="clock" tone={!detail.lastUsed ? 'muted' : undefined}>
              {detail.lastUsed ? (
                <Tooltip content={dateTime(detail.lastUsed)}>
                  <span>{ago(detail.lastUsed)}</span>
                </Tooltip>
              ) : (
                t('Never')
              )}
            </Fact>
            <Fact label={t('Mileage')} icon="route">
              {distance(v.mileage)}
            </Fact>
            <Fact label={t('Vehicle type')} icon="car">
              {v.classLabel ? `${typeLabel} · ${v.classLabel}` : typeLabel}
            </Fact>
            <Fact label={t('Owner type')} icon="user">
              {ownerTypeLabel(v.ownerType)}
            </Fact>
            <Fact label={t('Job / gang')} icon="briefcase" tone={group ? undefined : 'muted'}>
              {group ?? t('None')}
            </Fact>
            <Fact label={t('Nickname')} icon="tag" tone={v.nickname ? undefined : 'muted'}>
              {v.nickname ?? t('None')}
            </Fact>
            <Fact label={t('Owned since')} icon="calendar" tone={since ? undefined : 'muted'}>
              {since ? date(since) : t('Unknown')}
            </Fact>
          </div>
        </section>

        <section className="nz-dos-col">
          <Heading
            actions={
              <Button size="sm" variant="ghost" iconRight="arrowRight" onClick={() => onTab('condition')}>
                {t('Details')}
              </Button>
            }
          >
            {t('Condition')}
          </Heading>
          <div className="nz-dos-ov__gauges">
            <SegGauge icon="engine" label={t('Engine')} value={v.engine} />
            <SegGauge icon="shield" label={t('Body')} value={v.body} />
            <SegGauge icon="fuel" label={t('Fuel')} value={v.fuel} />
          </div>
          <button type="button" className="nz-dos-ov__glyph" onClick={() => onTab('condition')} aria-label={t('Open the condition tab')}>
            <DamageDiagram damage={damage} />
            <span className={cx('nz-aveh-ellipsis', hasVisibleDamage(damage) && 'is-bad', !damage && 'is-muted')} title={damageCaption(damage)}>
              {damageCaption(damage)}
            </span>
          </button>
        </section>

        <section className="nz-dos-col nz-dos-ov__activity">
          <Heading
            count={activity.latest ? activity.latest.total : undefined}
            actions={
              <Button size="sm" variant="ghost" iconRight="arrowRight" onClick={() => onTab('activity')} disabled={!activity.latest?.total}>
                {t('View all')}
              </Button>
            }
          >
            {t('Recent activity')}
          </Heading>
          {latest === null ? (
            activity.error ? (
              <EmptyState compact icon="warning" title={t('Could not load the activity')} description={activity.error} />
            ) : (
              <ul className="nz-dos-actlist">
                {Array.from({ length: 4 }, (_, i) => (
                  <li key={i} className="nz-dos-act is-compact is-skel">
                    <div className="nz-dos-act__head">
                      <Skeleton width={26} height={26} radius={7} />
                      <span className="nz-dos-act__text">
                        <Skeleton width={`${54 + i * 9}%`} height={10} />
                        <Skeleton width="38%" height={8} style={{ marginTop: 6 }} />
                      </span>
                    </div>
                  </li>
                ))}
              </ul>
            )
          ) : latest.length === 0 ? (
            <EmptyState compact icon="history" title={t('No activity yet')} description={t('Garage visits and edits will show up here.')} />
          ) : (
            <ul className="nz-dos-actlist">
              {latest.map((r) => (
                <ActivityRow key={r.id} row={r} detail={detail} data={data} compact />
              ))}
            </ul>
          )}
        </section>

        <Snapshot detail={detail} props={props} onTab={onTab} />
      </div>
    </div>
  );
}

/** Bottom strip linking to the other tabs (taller screens only). */
function Snapshot({ detail, props, onTab }: { detail: AdminVehicleDetail; props: VProps; onTab: (tab: DossierTab) => void }) {
  const hasProps = Object.keys(props).length > 0;
  const perf = PERF_MODS.filter((m) => perfModValue(m, props).on).length;
  const primary = swatchOf(props.color1);
  const secondary = swatchOf(props.color2);
  const owners = detail.ownership;
  const lastPrice = owners.find((o) => o.price)?.price ?? null;
  const svc = [...detail.service].sort((a, b) => b.at - a.at)[0] ?? null;

  return (
    <div className="nz-dos-ov__snap">
      <button type="button" onClick={() => onTab('upgrades')}>
        <span className="nz-dos-ov__snap-label">
          <Icon name="gauge" size={12} strokeWidth={1.8} />
          {t('Upgrades')}
        </span>
        <b>{hasProps ? t('{n} of {total} performance', { n: perf, total: PERF_MODS.length }) : t('Not saved yet')}</b>
        <span>{hasProps ? t('{n} modifications installed', { n: installedModCount(props) }) : t('Stored on the next garage visit')}</span>
      </button>
      <button type="button" onClick={() => onTab('upgrades')}>
        <span className="nz-dos-ov__snap-label">
          <Icon name="palette" size={12} strokeWidth={1.8} />
          {t('Paint')}
        </span>
        {hasProps ? (
          <>
            <b className="nz-dos-ov__snap-paint">
              <ColourChip hex={primary.hex} size={14} />
              <ColourChip hex={secondary.hex} size={14} />
              <span className="nz-aveh-ellipsis">{primary.name}</span>
            </b>
            <span className="nz-aveh-ellipsis">{t('{name} secondary', { name: secondary.name })}</span>
          </>
        ) : (
          <>
            <b>{t('Unknown')}</b>
            <span>{t('No saved colours')}</span>
          </>
        )}
      </button>
      <button type="button" onClick={() => onTab('history')}>
        <span className="nz-dos-ov__snap-label">
          <Icon name="users" size={12} strokeWidth={1.8} />
          {t('Ownership')}
        </span>
        <b>{owners.length === 1 ? t('1 owner') : t('{n} owners', { n: owners.length })}</b>
        <span>{lastPrice ? t('Last price {price}', { price: money(lastPrice) }) : owners[0] ? t('Since {date}', { date: date(owners[0].at) }) : t('No records')}</span>
      </button>
      <button type="button" onClick={() => onTab('history')}>
        <span className="nz-dos-ov__snap-label">
          <Icon name="wrench" size={12} strokeWidth={1.8} />
          {t('Last service')}
        </span>
        <b className="nz-aveh-ellipsis">{svc ? svc.item : t('Never serviced')}</b>
        <span className="nz-aveh-ellipsis">{svc ? `${ago(svc.at)} · ${svc.shop || t('Unknown shop')}` : t('No service records')}</span>
      </button>
    </div>
  );
}
