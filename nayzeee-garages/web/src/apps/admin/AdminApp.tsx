/**
 * Admin panel shell (app 'admin', AdminOpenData).
 *
 * A large Window in the settings layout: the window bar carries the brand ("NAYZEEE GARAGES" /
 * "Admin panel"), framework status and Refresh; below it a sidebar (v5 nav items, collapsible
 * to an icon rail, remembered per browser) and the content column (page title + one-line
 * description, then the page body).
 *
 * Page contract (AdminPageProps): pages render inside `.nz-admin__page`, a flex column that
 * fills the remaining height (min-height 0, horizontal padding 22px, bottom 18px). Pages manage
 * their own scrolling. `refresh()` re-fetches AdminOpenData (admin:refresh) keeping the current
 * page; `setData(fn)` patches the store locally.
 *
 * In-world tools: call admin:points only through requestPoints() (shared/away.ts). While it is
 * pending the whole admin UI (window + modals + popovers) is hidden by CSS but stays mounted,
 * Escape is swallowed, and everything comes back exactly as it was when the request resolves.
 */
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import type { CSSProperties } from 'react';
import type { ComponentType } from 'react';
import { Button, Icon, Tooltip, cx } from '@/components/ui';
import type { IconName } from '@/components/ui';
import { Window } from '@/components/ui';
import { useApp, useUi } from '@/lib/store';
import { useEscape } from '@/lib/escape';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import type { AdminOpenData, AdminPage, AdminPageProps } from '@/lib/types';
import { AdminShellContext } from './shared/shell';
import type { AdminShell } from './shared/shell';
import { runAway, useAdminHidden } from './shared/away';
import { GaragesPage } from './pages/GaragesPage';
import { JobGaragesPage } from './pages/JobGaragesPage';
import { PrivateGaragesPage } from './pages/PrivateGaragesPage';
import { ImpoundsPage } from './pages/ImpoundsPage';
import { InteriorsPage } from './pages/InteriorsPage';
import { PlayerVehiclesPage } from './pages/PlayerVehiclesPage';
import { SettingsPage } from './pages/SettingsPage';
import './admin.css';

interface NavItem {
  page: AdminPage;
  icon: IconName;
  label: () => string;
  title: () => string;
  description: () => string;
  component: ComponentType<AdminPageProps>;
}

const NAV_GROUPS: { label: () => string; items: NavItem[] }[] = [
  {
    label: () => t('Locations'),
    items: [
      {
        page: 'garages',
        icon: 'garage',
        label: () => t('Garages'),
        title: () => t('Garages'),
        description: () => t('Public garages where players park, store and retrieve their own vehicles.'),
        component: GaragesPage,
      },
      {
        page: 'jobs',
        icon: 'briefcase',
        label: () => t('Job & gang'),
        title: () => t('Job & gang garages'),
        description: () => t('Fleets and vehicle spawners for jobs and gangs, with minimum grades.'),
        component: JobGaragesPage,
      },
      {
        page: 'private',
        icon: 'users',
        label: () => t('Private'),
        title: () => t('Private garages'),
        description: () => t('Garages players can buy or be assigned, with their owners and copies.'),
        component: PrivateGaragesPage,
      },
      {
        page: 'impounds',
        icon: 'impound',
        label: () => t('Impounds'),
        title: () => t('Impounds'),
        description: () => t('Impound lots, who may operate them and the default release fee.'),
        component: ImpoundsPage,
      },
    ],
  },
  {
    label: () => t('Manage'),
    items: [
      {
        page: 'interiors',
        icon: 'building',
        label: () => t('Interiors'),
        title: () => t('Interiors'),
        description: () => t('Walk-in garage interiors: entry, camera path, vehicle slots and exit.'),
        component: InteriorsPage,
      },
      {
        page: 'vehicles',
        icon: 'car',
        label: () => t('Player vehicles'),
        title: () => t('Player vehicles'),
        description: () => t('Find a player and manage their vehicles, ownership and history.'),
        component: PlayerVehiclesPage,
      },
      {
        page: 'settings',
        icon: 'cog',
        label: () => t('Settings'),
        title: () => t('Settings'),
        description: () => t('Server-wide rules for vehicles, garages, transfers, impounds and the interface.'),
        component: SettingsPage,
      },
    ],
  },
];

const ALL_ITEMS = NAV_GROUPS.flatMap((g) => g.items);
const findItem = (page: AdminPage) => ALL_ITEMS.find((i) => i.page === page) ?? ALL_ITEMS[0];
/** Unknown / missing page from Lua → the first page. */
const validPage = (page: unknown): AdminPage => findItem(page as AdminPage).page;

const FRAMEWORKS: Record<AdminOpenData['framework'], string> = {
  qb: 'QBCore',
  qbx: 'Qbox',
  esx: 'ESX Legacy',
  standalone: 'Standalone',
};

const RAIL_KEY = 'nz-admin-rail';

function readRail(): boolean {
  try {
    return window.localStorage.getItem(RAIL_KEY) === '1';
  } catch {
    return false;
  }
}

function writeRail(v: boolean) {
  try {
    window.localStorage.setItem(RAIL_KEY, v ? '1' : '0');
  } catch {
    /* storage unavailable */
  }
}

export function AdminApp() {
  const { open, data } = useApp('admin');
  if (!open || !data) return null;
  return <AdminWindow data={data} />;
}

function AdminWindow({ data }: { data: AdminOpenData }) {
  const { close } = useApp('admin');
  const [page, setPage] = useState<AdminPage>(() => validPage(data.page));
  const [rail, setRail] = useState(readRail);
  const [refreshing, setRefreshing] = useState(false);
  const pageRef = useRef(page);
  pageRef.current = page;

  // A new 'open' from Lua with another page switches to it.
  useEffect(() => {
    setPage(validPage(data.page));
  }, [data.page]);

  const hidden = useAdminHidden();

  // Align the sidebar edge with the brand block of the window bar (its width depends on
  // the font and the translated subtitle).
  const [sideWidth, setSideWidth] = useState<number | null>(null);
  const sideRef = useRef<HTMLElement>(null);
  useLayoutEffect(() => {
    const side = sideRef.current;
    const root = side?.closest<HTMLElement>('.nz-admin');
    const extra = root?.querySelector<HTMLElement>('header [class$="__extra"]');
    if (!side || !extra) return;
    const measure = () => {
      const w = extra.getBoundingClientRect().left - side.parentElement!.getBoundingClientRect().left;
      if (w > 0) setSideWidth(Math.max(196, Math.min(280, Math.round(w))));
    };
    measure();
    if (typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver(measure);
    ro.observe(extra);
    return () => ro.disconnect();
  }, []);
  // Always registered (never toggled): re-registering would move it above the modals that are
  // open, and Escape would then close the whole panel instead of the topmost dialog.
  useEscape(close, true);
  // While an in-world tool runs, Escape belongs to the game: swallow it (registered last, so it
  // sits above every open modal) so nothing hidden closes behind the admin's back.
  useEscape(() => undefined, hidden);

  const go = useCallback((next: AdminPage) => {
    setPage(next);
    useUi.getState().updateApp('admin', { page: next });
  }, []);

  const refresh = useCallback(async () => {
    setRefreshing(true);
    const res = await request('admin:refresh', {});
    setRefreshing(false);
    const st = useUi.getState();
    if (res.ok && res.data && st.apps.admin.open) st.openApp('admin', { ...res.data, page: pageRef.current });
  }, []);

  const setData = useCallback((fn: (prev: AdminOpenData) => AdminOpenData) => {
    const st = useUi.getState();
    const cur = st.apps.admin.data;
    if (cur && st.apps.admin.open) st.openApp('admin', { ...fn(cur), page: pageRef.current });
  }, []);

  const shell = useMemo<Omit<AdminShell, 'hidden'>>(() => ({ runInWorld: runAway, page, go }), [page, go]);

  const toggleRail = () => {
    setRail((r) => {
      writeRail(!r);
      return !r;
    });
  };

  const counts = useMemo(() => {
    const c: Partial<Record<AdminPage, number>> = { garages: 0, jobs: 0, private: 0, impounds: 0 };
    for (const l of data.locations) {
      if (l.kind === 'garage') c.garages! += 1;
      else if (l.kind === 'job') c.jobs! += 1;
      else if (l.kind === 'private') c.private! += 1;
      else if (l.kind === 'impound') c.impounds! += 1;
    }
    c.interiors = data.interiors.length;
    return c;
  }, [data.locations, data.interiors]);

  const item = findItem(page);
  const PageComponent = item.component;

  return (
    <AdminShellContext.Provider value={shell}>
      <Window
        title={t('NAYZEEE GARAGES')}
        subtitle={t('Admin panel')}
        onClose={close}
        width="min(1240px, calc(100vw - 48px))"
        height="min(704px, calc(100vh - 24px))"
        className="nz-admin"
        style={{ maxHeight: 'calc(100vh - 24px)', ...(sideWidth ? { '--nz-admin-side': `${sideWidth}px` } : {}) } as CSSProperties}
        bodyClassName="nz-admin__body"
        headerExtra={
          <>
            <span className="nz-admin__status" title={t('Framework')}>
              <span className="nz-admin__status-dot" />
              <span className="nz-admin__status-text">
                {t('Running on')} <b>{FRAMEWORKS[data.framework] ?? data.framework}</b>
              </span>
              <span className="nz-admin__status-sep" />
              <span className="nz-admin__status-text">
                {data.locations.length === 1 ? t('1 location') : t('{count} locations', { count: data.locations.length })}
              </span>
            </span>
            <Button size="sm" variant="ghost" icon="refresh" loading={refreshing} onClick={() => void refresh()}>
              {t('Refresh')}
            </Button>
          </>
        }
      >
        <nav ref={sideRef} className={cx('nz-admin__side', rail && 'is-rail')} aria-label={t('Admin sections')}>
          <div className="nz-admin__nav">
            {NAV_GROUPS.map((group, gi) => (
              <div key={gi} className="nz-admin__group">
                <div className="nz-admin__group-label">
                  <span>{group.label()}</span>
                </div>
                {group.items.map((it) => {
                  const on = it.page === page;
                  const count = counts[it.page];
                  return (
                    <Tooltip key={it.page} content={it.label()} side="right" disabled={!rail} className="nz-admin__nav-tip">
                      <button
                        type="button"
                        className={cx('nz-admin__nav-item', on && 'is-on')}
                        aria-current={on ? 'page' : undefined}
                        aria-label={rail ? it.label() : undefined}
                        onClick={() => go(it.page)}
                      >
                        <Icon name={it.icon} size={16} strokeWidth={1.6} />
                        <span className="nz-admin__nav-label">{it.label()}</span>
                        {count !== undefined && <span className="nz-admin__tally">{count}</span>}
                      </button>
                    </Tooltip>
                  );
                })}
              </div>
            ))}
          </div>
          <div className="nz-admin__side-foot">
            <Tooltip content={t('Expand sidebar')} side="right" disabled={!rail} className="nz-admin__nav-tip">
              <button
                type="button"
                className="nz-admin__rail-btn"
                onClick={toggleRail}
                aria-label={rail ? t('Expand sidebar') : t('Collapse sidebar')}
                aria-expanded={!rail}
              >
                <Icon name="sidebar" size={16} strokeWidth={1.6} />
                <span className="nz-admin__nav-label">{t('Collapse')}</span>
              </button>
            </Tooltip>
          </div>
        </nav>

        <main className="nz-admin__main">
          <header className="nz-admin__head">
            <span className="nz-admin__head-icon">
              <Icon name={item.icon} size={17} strokeWidth={1.6} />
            </span>
            <div className="nz-admin__head-text">
              <h1>{item.title()}</h1>
              <p>{item.description()}</p>
            </div>
          </header>
          <div key={page} className="nz-admin__page">
            <PageComponent data={data} refresh={refresh} setData={setData} />
          </div>
        </main>
      </Window>
    </AdminShellContext.Provider>
  );
}
