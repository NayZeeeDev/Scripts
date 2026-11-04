/**
 * Condition tab: large labelled damage diagram with a parts checklist (hover links both),
 * health gauges (engine / body / tank as /1000 and %), fuel, deformation and service state.
 */
import { useState } from 'react';
import type { ReactNode } from 'react';
import { Icon, cx } from '@/components/ui';
import type { IconName } from '@/components/ui';
import { t } from '@/lib/i18n';
import { dateTime, distance, percent } from '@/lib/format';
import type { AdminOpenData, AdminVehicleDetail, DamageSummary } from '@/lib/types';
import { actorOf } from './activity';
import { DamageDiagram } from './DamageDiagram';
import { ago, damageCaption, damageCounts, garageName, partStates, partsFor, shapeOf } from './data';
import type { PartGroup, PartState } from './data';
import { Fact, Heading, SegGauge } from './parts';
import type { ActivityState } from './useActivity';
import type { DossierTab } from './tabs';

interface Props {
  detail: AdminVehicleDetail;
  data: AdminOpenData;
  damage: DamageSummary | null;
  needsService: boolean;
  serviceBelow: number;
  activity: ActivityState;
  onTab: (tab: DossierTab) => void;
}

const stateText = (s: PartState, group?: PartGroup) =>
  s === 'bad' ? (group === 'windows' ? t('Smashed') : t('Damaged')) : s === 'burst' ? t('Burst') : s === 'rim' ? t('On the rim') : t('Intact');

const GROUPS: { id: PartGroup; label: () => string }[] = [
  { id: 'doors', label: () => t('Doors and panels') },
  { id: 'windows', label: () => t('Windows') },
  { id: 'tyres', label: () => t('Tyres') },
];

export function ConditionTab({ detail, data, damage, needsService, serviceBelow, activity, onTab }: Props) {
  const v = detail.vehicle;
  const [hot, setHot] = useState<string | null>(null);
  const shape = shapeOf(v);
  const parts = partsFor(shape);
  const states = partStates(damage, shape);
  const counts = damageCounts(damage, shape);
  const hotPart = hot ? parts.find((p) => p.id === hot) : null;
  const of1000 = (n: number) => t('{n}/1000', { n: Math.round(n) });
  // Engine / body come from the vehicle row (it wins on spawn and admin edits update it);
  // the stored damage only adds the tank, the parts and the deformation.
  const groups = GROUPS.filter((g) => parts.some((p) => p.group === g.id));
  // The stored damage is written on every garage store: the newest store entry dates it.
  const stored = activity.latest?.rows.find((r) => r.event === 'vehicle.store') ?? null;
  const storedAt = stored ? (typeof stored.data?.garageName === 'string' && stored.data.garageName) || garageName(stored.data?.garage, detail, data) : null;
  const storedKm = stored && typeof stored.data?.mileage === 'number' ? stored.data.mileage : null;
  const svc = [...detail.service].sort((a, b) => b.at - a.at)[0] ?? null;

  return (
    <div className="nz-dos-pane">
      <div className={cx('nz-dos-sheet nz-dos-cond', `is-${shape}`)}>
        <section className="nz-dos-col nz-dos-cond__diagram">
          <Heading
            actions={
              <span className="nz-dos-legend" aria-hidden="true">
                <span className="is-ok">{t('Intact')}</span>
                {groups.some((g) => g.id !== 'tyres') && <span className="is-bad">{t('Damaged')}</span>}
                {groups.some((g) => g.id === 'tyres') && (
                  <>
                    <span className="is-burst">{t('Burst')}</span>
                    <span className="is-rim">{t('On the rim')}</span>
                  </>
                )}
              </span>
            }
          >
            {t('Damage map')}
          </Heading>
          <div className={cx('nz-dos-cond__canvas', !damage && 'is-nodata')}>
            <DamageDiagram damage={damage} shape={shape} engine={v.engine} labels hot={hot} onHot={setHot} />
            {!damage && (
              <div className="nz-dos-cond__nodata">
                <Icon name="info" size={14} strokeWidth={1.7} />
                <span>{t('No damage data: the vehicle was stored before damage saving was turned on, or it was never stored.')}</span>
              </div>
            )}
          </div>
          <p className={cx('nz-dos-cond__caption', hotPart && 'is-hot', hotPart && `is-${states[hotPart.id]}`)} aria-live="polite">
            {hotPart ? (
              <>
                <b>{hotPart.label()}</b>
                <span>{damage ? stateText(states[hotPart.id], hotPart.group) : t('Unknown')}</span>
              </>
            ) : (
              <span>{damageCaption(damage, shape)}</span>
            )}
          </p>
        </section>

        <section className="nz-dos-col nz-dos-cond__side">
          <Heading>{t('Health')}</Heading>
          <div className="nz-dos-cond__gauges">
            <SegGauge icon="engine" label={t('Engine')} value={v.engine} detail={of1000(v.engine * 10)} />
            <SegGauge icon="shield" label={t('Body')} value={v.body} detail={of1000(v.body * 10)} />
            {damage && <SegGauge icon="fuel" label={t('Fuel tank')} value={damage.tank / 10} detail={of1000(damage.tank)} />}
            <SegGauge icon="fuel" label={t('Fuel level')} value={v.fuel} />
          </div>

          <Heading count={damage ? counts.doors + counts.windows + counts.burst + counts.rim : undefined}>{t('Parts')}</Heading>
          <div className="nz-dos-parts">
            {groups.map((g) => {
              const list = parts.filter((p) => p.group === g.id && (!p.optional || states[p.id] !== 'ok'));
              return (
                <div key={g.id} className="nz-dos-parts__group">
                  <span className="nz-dos-parts__label">{g.id === 'windows' && shape !== 'car' ? t('Glass') : g.label()}</span>
                  <div className="nz-dos-parts__chips">
                    {list.map((p) => {
                      const s = damage ? states[p.id] : null;
                      return (
                        <span
                          key={p.id}
                          className={cx('nz-dos-part', s ? `is-${s}` : 'is-unknown', hot === p.id && 'is-hot')}
                          onMouseEnter={() => setHot(p.id)}
                          onMouseLeave={() => setHot(null)}
                          title={`${p.label()}: ${s ? stateText(s, p.group) : t('Unknown')}`}
                        >
                          <i />
                          {p.short()}
                        </span>
                      );
                    })}
                  </div>
                </div>
              );
            })}
          </div>

          <div className="nz-dos-facts nz-dos-cond__facts">
            <Fact label={t('Body deformation')} icon="car" tone={damage?.deformed ? 'red' : 'muted'}>
              {!damage ? t('Unknown') : damage.deformed ? t('Saved with the vehicle') : t('None')}
            </Fact>
            <Fact label={t('Service')} icon="wrench" tone={needsService ? 'amber' : 'teal'}>
              {needsService
                ? t('Needed (engine {n}% < {limit}%)', { n: percent(v.engine), limit: serviceBelow })
                : t('Not needed')}
            </Fact>
          </div>

          <div className="nz-dos-cond__records">
            <div className="nz-dos-recs">
              <Record
                icon="parking"
                title={
                  stored
                    ? storedAt
                      ? t('Damage saved at {garage}', { garage: storedAt })
                      : t('Damage saved on the last garage visit')
                    : damage
                      ? t('Damage saved on a garage visit')
                      : t('No damage saved yet')
                }
                sub={
                  stored
                    ? [ago(stored.at), actorOf(stored), storedKm !== null ? distance(storedKm) : null].filter(Boolean).join(' · ')
                    : !activity.latest
                      ? t('Loading the activity…')
                      : damage
                        ? t('Not in the recent activity')
                        : t('Saved the next time it is stored')
                }
                hint={stored ? dateTime(stored.at) : undefined}
                action={t('Activity')}
                onClick={() => onTab('activity')}
              />
              <Record
                icon="wrench"
                title={svc ? t('Last service: {item}', { item: svc.item }) : t('Never serviced')}
                sub={svc ? `${svc.shop || t('Unknown shop')} · ${ago(svc.at)}` : t('No service records')}
                hint={svc ? dateTime(svc.at) : undefined}
                action={t('History')}
                onClick={() => onTab('history')}
              />
            </div>
          </div>
        </section>
      </div>
    </div>
  );
}

/** A compact link card: icon, one-line title and detail, the tab it opens. */
function Record({ icon, title, sub, hint, action, onClick }: { icon: IconName; title: ReactNode; sub: ReactNode; hint?: string; action: string; onClick: () => void }) {
  return (
    <button type="button" className="nz-dos-rec" onClick={onClick} title={hint ? `${hint} · ${action}` : action}>
      <span className="nz-dos-rec__icon">
        <Icon name={icon} size={14} strokeWidth={1.7} />
      </span>
      <span className="nz-dos-rec__text">
        <b className="nz-aveh-ellipsis">{title}</b>
        <span className="nz-aveh-ellipsis">{sub}</span>
      </span>
      <span className="nz-dos-rec__go" aria-label={action}>
        <Icon name="arrowRight" size={13} strokeWidth={1.8} />
      </span>
    </button>
  );
}
