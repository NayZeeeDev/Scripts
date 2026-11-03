/**
 * Condition tab: large labelled damage diagram with a parts checklist (hover links both),
 * health gauges (engine / body / tank as /1000 and %), fuel, deformation and service state.
 */
import { useState } from 'react';
import { Icon, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import { percent } from '@/lib/format';
import type { AdminVehicleDetail, DamageSummary } from '@/lib/types';
import { DamageDiagram } from './DamageDiagram';
import { PARTS, damageCaption, damageCounts, partStates } from './data';
import type { PartGroup, PartState } from './data';
import { Fact, Heading, SegGauge } from './parts';

interface Props {
  detail: AdminVehicleDetail;
  damage: DamageSummary | null;
  needsService: boolean;
  serviceBelow: number;
}

const stateText = (s: PartState, group?: PartGroup) =>
  s === 'bad' ? (group === 'windows' ? t('Smashed') : t('Damaged')) : s === 'burst' ? t('Burst') : s === 'rim' ? t('On the rim') : t('Intact');

const GROUPS: { id: PartGroup; label: () => string }[] = [
  { id: 'doors', label: () => t('Doors and panels') },
  { id: 'windows', label: () => t('Windows') },
  { id: 'tyres', label: () => t('Tyres') },
];

export function ConditionTab({ detail, damage, needsService, serviceBelow }: Props) {
  const v = detail.vehicle;
  const [hot, setHot] = useState<string | null>(null);
  const states = partStates(damage);
  const counts = damageCounts(damage);
  const hotPart = hot ? PARTS.find((p) => p.id === hot) : null;
  const of1000 = (n: number) => t('{n}/1000', { n: Math.round(n) });

  return (
    <div className="nz-dos-pane">
      <div className="nz-dos-sheet nz-dos-cond">
        <section className="nz-dos-col nz-dos-cond__diagram">
          <Heading
            actions={
              <span className="nz-dos-legend" aria-hidden="true">
                <span className="is-ok">{t('Intact')}</span>
                <span className="is-bad">{t('Damaged')}</span>
                <span className="is-burst">{t('Burst')}</span>
                <span className="is-rim">{t('On the rim')}</span>
              </span>
            }
          >
            {t('Damage map')}
          </Heading>
          <div className={cx('nz-dos-cond__canvas', !damage && 'is-nodata')}>
            <DamageDiagram damage={damage} labels hot={hot} onHot={setHot} />
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
              <span>{damageCaption(damage)}</span>
            )}
          </p>
        </section>

        <section className="nz-dos-col nz-dos-cond__side">
          <Heading>{t('Health')}</Heading>
          <div className="nz-dos-cond__gauges">
            <SegGauge icon="engine" label={t('Engine')} value={v.engine} detail={damage ? of1000(damage.engine) : undefined} />
            <SegGauge icon="shield" label={t('Body')} value={v.body} detail={damage ? of1000(damage.body) : undefined} />
            {damage && <SegGauge icon="fuel" label={t('Fuel tank')} value={damage.tank / 10} detail={of1000(damage.tank)} />}
            <SegGauge icon="fuel" label={t('Fuel level')} value={v.fuel} />
          </div>

          <Heading count={damage ? counts.doors + counts.windows + counts.burst + counts.rim : undefined}>{t('Parts')}</Heading>
          <div className="nz-dos-parts">
            {GROUPS.map((g) => {
              const parts = PARTS.filter((p) => p.group === g.id && (!p.optional || states[p.id] !== 'ok'));
              return (
                <div key={g.id} className="nz-dos-parts__group">
                  <span className="nz-dos-parts__label">{g.label()}</span>
                  <div className="nz-dos-parts__chips">
                    {parts.map((p) => {
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
        </section>
      </div>
    </div>
  );
}
