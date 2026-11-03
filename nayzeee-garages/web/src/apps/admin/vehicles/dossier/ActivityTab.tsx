/**
 * Activity tab: the vehicle's log (admin:vehicle:activity), newest first, grouped by day.
 * Each entry: family icon, readable sentence, actor, relative time (exact time on hover)
 * and expandable details. ActivityRow is reused (compact) by the Overview.
 */
import { useState } from 'react';
import { Button, EmptyState, Icon, Pagination, Skeleton, Tooltip, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import { date, dateTime } from '@/lib/format';
import type { AdminOpenData, AdminVehicleDetail, VehicleActivity } from '@/lib/types';
import { activityDetails, actorOf, describeActivity } from './activity';
import { ago } from './data';
import type { ActivityState } from './useActivity';

interface RowProps {
  row: VehicleActivity;
  detail: AdminVehicleDetail;
  data: AdminOpenData;
  compact?: boolean;
  open?: boolean;
  onToggle?: () => void;
}

export function ActivityRow({ row, detail, data, compact = false, open = false, onToggle }: RowProps) {
  const view = describeActivity(row, { detail, data });
  const details = compact ? [] : activityDetails(row);
  const expandable = !compact && !!onToggle;
  const head = (
    <>
      <span className={cx('nz-dos-act__icon', `is-${view.tone}`)}>
        <Icon name={view.icon} size={14} strokeWidth={1.7} />
      </span>
      <span className="nz-dos-act__text">
        <b className={cx(!view.known && 'is-raw')}>
          {view.sentence}
          {view.extra && <em> · {view.extra}</em>}
        </b>
        <span>
          {actorOf(row)}
          {compact && (
            <>
              {' · '}
              <Tooltip content={dateTime(row.at)}>
                <span>{ago(row.at)}</span>
              </Tooltip>
            </>
          )}
          {!compact && <span className="nz-dos-act__family"> · {view.family}</span>}
        </span>
      </span>
      {!compact && (
        <Tooltip content={dateTime(row.at)} side="left">
          <span className="nz-dos-act__time">{ago(row.at)}</span>
        </Tooltip>
      )}
      {expandable && <Icon name={open ? 'chevronUp' : 'chevronDown'} size={14} strokeWidth={1.8} className="nz-dos-act__chev" />}
    </>
  );

  return (
    <li className={cx('nz-dos-act', compact && 'is-compact', open && 'is-open')}>
      {expandable ? (
        <button type="button" className="nz-dos-act__head" onClick={onToggle} aria-expanded={open}>
          {head}
        </button>
      ) : (
        <div className="nz-dos-act__head">{head}</div>
      )}
      {open && expandable && (
        <div className="nz-dos-act__more">
          <dl>
            <div>
              <dt>{t('Event')}</dt>
              <dd className="is-mono">{row.event}</dd>
            </div>
            <div>
              <dt>{t('When')}</dt>
              <dd>{dateTime(row.at)}</dd>
            </div>
            {row.actor && (
              <div>
                <dt>{t('Identifier')}</dt>
                <dd className="is-mono">{row.actor}</dd>
              </div>
            )}
            {details.map((d) => (
              <div key={d.key}>
                <dt>{d.label}</dt>
                <dd>{d.value}</dd>
              </div>
            ))}
          </dl>
          {details.length === 0 && <p>{t('No extra details were logged for this event.')}</p>}
        </div>
      )}
    </li>
  );
}

/** Day heading for a unix time: Today / Yesterday / date. */
function dayLabel(unix: number): string {
  const d = new Date(unix * 1000);
  const today = new Date();
  const start = (x: Date) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
  const diff = Math.round((start(today) - start(d)) / 86400000);
  if (diff === 0) return t('Today');
  if (diff === 1) return t('Yesterday');
  return date(unix);
}

interface Props {
  detail: AdminVehicleDetail;
  data: AdminOpenData;
  activity: ActivityState;
}

export function ActivityTab({ detail, data, activity }: Props) {
  const [open, setOpen] = useState<number | null>(null);
  const { current, loading, error } = activity;
  const rows = current?.rows ?? [];
  const pageCount = current ? Math.max(1, Math.ceil(current.total / current.pageSize)) : 1;

  if (error && !current) {
    return (
      <div className="nz-dos-pane nz-dos-pane--center">
        <EmptyState
          icon="warning"
          title={t('Could not load the activity')}
          description={error}
          action={
            <Button size="sm" variant="white" icon="refresh" onClick={activity.reload}>
              {t('Try again')}
            </Button>
          }
        />
      </div>
    );
  }

  if (!current) {
    return (
      <div className="nz-dos-pane nz-dos-actlog">
        <ul className="nz-dos-actlist">
          {Array.from({ length: 6 }, (_, i) => (
            <li key={i} className="nz-dos-act is-skel">
              <div className="nz-dos-act__head">
                <Skeleton width={28} height={28} radius={7} />
                <span className="nz-dos-act__text">
                  <Skeleton width={`${46 + ((i * 17) % 30)}%`} height={11} />
                  <Skeleton width="22%" height={9} style={{ marginTop: 6 }} />
                </span>
              </div>
            </li>
          ))}
        </ul>
      </div>
    );
  }

  if (current.total === 0) {
    return (
      <div className="nz-dos-pane nz-dos-pane--center">
        <EmptyState
          icon="history"
          title={t('No activity yet')}
          description={t('Garage visits, transfers, impounds and admin edits of this vehicle appear here once they happen. Turn on database logs on the server to record them.')}
        />
      </div>
    );
  }

  // Group the page by day (rows arrive newest first).
  const groups: { label: string; rows: VehicleActivity[] }[] = [];
  for (const r of rows) {
    const label = dayLabel(r.at);
    const last = groups[groups.length - 1];
    if (last && last.label === label) last.rows.push(r);
    else groups.push({ label, rows: [r] });
  }

  return (
    <div className={cx('nz-dos-pane nz-dos-actlog', loading && 'is-loading')}>
      <div className="nz-dos-actlog__scroll">
        {groups.map((g, gi) => (
          <section key={`${g.label}-${gi}`} className="nz-dos-actday">
            <h5>
              <span>{g.label}</span>
              <i>{g.rows.length}</i>
            </h5>
            <ul className="nz-dos-actlist">
              {g.rows.map((r) => (
                <ActivityRow key={r.id} row={r} detail={detail} data={data} open={open === r.id} onToggle={() => setOpen((o) => (o === r.id ? null : r.id))} />
              ))}
            </ul>
          </section>
        ))}
      </div>
      <div className="nz-dos-actlog__foot">
        <span className="nz-dos-actlog__note">
          <Icon name="info" size={13} strokeWidth={1.7} />
          {t('Newest first. Click an entry for its details.')}
        </span>
        <Pagination page={current.page} pageCount={pageCount} total={current.total} pageSize={current.pageSize} onChange={activity.setPage} />
      </div>
    </div>
  );
}
