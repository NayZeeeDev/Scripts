/**
 * Right-hand summary of the selected interior: readiness checks (slots, exit, camera path),
 * IPL profile and its options, entry point and the garages that use it.
 */
import { Badge, Button, EmptyState, Icon, Tooltip, cx } from '@/components/ui';
import type { IconName } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { AdminOpenData, Interior, Location } from '@/lib/types';
import { KIND_PAGE, accessModeLabel, kindNoun } from '../shared/labels';
import type { LocationPageKind } from '../shared/labels';
import { useAdminShell } from '../shared/shell';

interface Props {
  data: AdminOpenData;
  interior: Interior | null;
  /** Whether any interior exists (no selection + none → onboarding guide). */
  hasAny: boolean;
  editing: boolean;
  onEdit: (interior: Interior) => void;
}

const fx = (n: number) => (Math.round(n * 10) / 10).toFixed(1);

/** Locations whose access uses this interior. */
export function usersOf(locations: Location[], id: number | null): Location[] {
  if (id === null) return [];
  return locations.filter((l) => 'access' in l && l.access.mode !== 'quick' && l.access.interiorId === id);
}

/** Problems that stop the interior from working well. */
export function interiorIssues(i: Interior): string[] {
  const out: string[] = [];
  if (!i.slots.length) out.push(t('No vehicle slots — vehicles cannot be shown inside.'));
  return out;
}

function Check({ ok, icon, label, value, tip }: { ok: boolean; icon: IconName; label: string; value: string; tip: string }) {
  return (
    <Tooltip content={tip}>
      <div className={cx('nz-aint-check', ok ? 'is-ok' : 'is-missing')}>
        <span className="nz-aint-check__icon">
          <Icon name={icon} size={15} strokeWidth={1.6} />
        </span>
        <span className="nz-aint-check__text">
          <span>{label}</span>
          <b>{value}</b>
        </span>
      </div>
    </Tooltip>
  );
}

export function InteriorDetail({ data, interior, hasAny, editing, onEdit }: Props) {
  const shell = useAdminShell();

  if (!interior) {
    return (
      <aside className="nz-aint-side">
        {hasAny ? (
          <EmptyState
            className="nz-aint-side__empty"
            icon="building"
            title={t('No interior selected')}
            description={t('Select an interior to see its slots, camera path and the garages that use it.')}
          />
        ) : (
          <div className="nz-aint-guide">
            <h4>{t('How interiors work')}</h4>
            <ol>
              <li>
                <span>1</span>
                <div>
                  <b>{t('Create')}</b>
                  <p>{t('Pick an IPL profile or stand where your MLO is and use your current position.')}</p>
                </div>
              </li>
              <li>
                <span>2</span>
                <div>
                  <b>{t('Build it in the world')}</b>
                  <p>{t('The creator opens in game: set the entry, an optional camera path, the vehicle slots and the exit.')}</p>
                </div>
              </li>
              <li>
                <span>3</span>
                <div>
                  <b>{t('Use it in a garage')}</b>
                  <p>{t('Edit a garage and set its access mode to Interior (or both) to let players walk in.')}</p>
                </div>
              </li>
            </ol>
          </div>
        )}
      </aside>
    );
  }

  const profile = interior.profile ? data.profiles.find((p) => p.key === interior.profile) ?? null : null;
  const users = usersOf(data.locations, interior.id);
  const points = interior.cutscene.points.length;
  const options = profile
    ? profile.options.map((o) => ({
        key: o.key,
        label: o.label,
        value: o.choices.find((c) => c.value === (interior.options[o.key] ?? o.default))?.label ?? interior.options[o.key] ?? o.default,
      }))
    : [];

  return (
    <aside className="nz-aint-side" aria-label={t('Interior details')}>
      <header className="nz-aint-side__head">
        <div className="nz-aint-side__titles">
          <span className="nz-aint-side__id">#{interior.id}</span>
          <h3 title={interior.name}>{interior.name}</h3>
        </div>
        {interior.enabled ? (
          <Badge tone="teal" size="sm" dot>
            {t('Enabled')}
          </Badge>
        ) : (
          <Badge tone="neutral" size="sm" dot>
            {t('Disabled')}
          </Badge>
        )}
      </header>

      <div className="nz-aint-side__body">
        <div className="nz-aint-checks">
          <Check
            ok={interior.slots.length > 0}
            icon="parking"
            label={t('Vehicle slots')}
            value={String(interior.slots.length)}
            tip={interior.slots.length ? t('Vehicles parked inside are shown on these slots.') : t('Place at least one slot in the creator.')}
          />
          <Check
            ok={!!interior.exit}
            icon="door"
            label={t('Exit')}
            value={interior.exit ? t('Placed') : t('Entry')}
            tip={interior.exit ? t('Players leave through the exit point.') : t('No exit point — players leave where they came in.')}
          />
          <Check
            ok={interior.cutscene.enabled && points > 0}
            icon="camera"
            label={t('Camera')}
            value={interior.cutscene.enabled && points > 0 ? t('{n} points', { n: points }) : t('Off')}
            tip={t('Camera path played when a player enters.')}
          />
        </div>

        <section className="nz-aint-sec">
          <h4>{t('IPL profile')}</h4>
          {profile ? (
            <div className="nz-aint-kv">
              <div>
                <span>{t('Profile')}</span>
                <b title={profile.label}>{profile.label}</b>
              </div>
              {options.map((o) => (
                <div key={o.key}>
                  <span>{o.label}</span>
                  <b>{o.value}</b>
                </div>
              ))}
            </div>
          ) : (
            <p className="nz-aint-note">{interior.profile ? t('Unknown profile ({key})', { key: interior.profile }) : t('None — a custom MLO or map location.')}</p>
          )}
        </section>

        <section className="nz-aint-sec">
          <h4>{t('Entry point')}</h4>
          <div className="nz-aint-coord">
            <Icon name="pin" size={13} strokeWidth={1.7} />
            <span>
              {fx(interior.entry.x)}, {fx(interior.entry.y)}, {fx(interior.entry.z)}
            </span>
            <em>{Math.round(interior.entry.w)}°</em>
          </div>
        </section>

        <section className="nz-aint-sec">
          <h4>
            {t('Used by')}
            <span className="nz-aint-sec__count">{users.length}</span>
          </h4>
          {users.length ? (
            <ul className="nz-aint-users">
              {users.map((l) => (
                <li key={String(l.id)}>
                  <button
                    type="button"
                    onClick={() => shell.go(KIND_PAGE[l.kind as LocationPageKind])}
                    title={t('Open {page}', { page: kindNoun(l.kind) })}
                  >
                    <Icon name={l.kind === 'private' ? 'users' : l.kind === 'job' ? 'briefcase' : 'garage'} size={13} strokeWidth={1.6} />
                    <span className="nz-aint-users__name">{l.name}</span>
                    <span className="nz-aint-users__mode">{'access' in l ? accessModeLabel(l.access.mode) : ''}</span>
                    <Icon name="chevronRight" size={12} strokeWidth={1.8} className="nz-aint-users__chev" />
                  </button>
                </li>
              ))}
            </ul>
          ) : (
            <p className="nz-aint-note">{t('No garage uses it yet. Pick it as the interior of a garage (access mode Interior).')}</p>
          )}
        </section>
      </div>

      <footer className="nz-aint-side__foot">
        <Button variant="white" icon="edit" full loading={editing} onClick={() => onEdit(interior)}>
          {t('Edit in creator')}
        </Button>
      </footer>
    </aside>
  );
}
