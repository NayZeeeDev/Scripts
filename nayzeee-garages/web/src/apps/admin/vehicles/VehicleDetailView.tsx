/**
 * Player vehicles — level 3: the vehicle Dossier (admin:vehicle:get).
 * Hero band (stage, identity, plate, owner, record actions), pill tabs (Overview ·
 * Condition · Upgrades & paint · Finance · History · Activity · Data; keys 1-7) and every
 * edit modal. Every edit goes through admin:vehicle:update and refreshes the activity log.
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import { Button, ConfirmDialog, EmptyState, IconButton, Kbd, Skeleton, Tabs, cx } from '@/components/ui';
import { request } from '@/lib/nui';
import { toast } from '@/lib/store';
import { t } from '@/lib/i18n';
import { money } from '@/lib/format';
import type { AdminOpenData, AdminVehicleDetail, AdminVehiclePatch, AdminVehicleRow } from '@/lib/types';
import { useAdminShell } from '../shared/shell';
import { DetailsModal } from './modals/DetailsModal';
import { ImpoundModal } from './modals/ImpoundModal';
import { FinanceModal } from './modals/FinanceModal';
import { OwnerModal } from './modals/OwnerModal';
import { ServiceModal } from './modals/ServiceModal';
import { ModsModal } from './modals/ListModals';
import { PropsEditor } from './props/PropsEditor';
import { rowFromDetail } from './util';
import { Hero } from './dossier/Hero';
import { OverviewTab } from './dossier/OverviewTab';
import { ConditionTab } from './dossier/ConditionTab';
import { UpgradesTab } from './dossier/UpgradesTab';
import { FinanceTab } from './dossier/FinanceTab';
import { HistoryTab } from './dossier/HistoryTab';
import { ActivityTab } from './dossier/ActivityTab';
import { DataTab } from './dossier/DataTab';
import { DOSSIER_TABS } from './dossier/tabs';
import type { DossierTab } from './dossier/tabs';
import { normDamage } from './dossier/data';
import { useActivity } from './dossier/useActivity';

type ModalId = 'details' | 'impound' | 'release' | 'props' | 'mods' | 'finance' | 'financeDelete' | 'service' | 'owner' | 'delete' | null;

interface Props {
  data: AdminOpenData;
  plate: string;
  /** Identifier of the player whose list we came from. */
  identifier: string;
  initialModal?: 'props' | null;
  initialTab?: DossierTab | null;
  onBack: () => void;
  /** The vehicle changed (row) or was deleted / left this player (null). */
  onRowChange: (oldPlate: string, row: AdminVehicleRow | null) => void;
  onPlateChange: (plate: string) => void;
}

const isTyping = (el: EventTarget | null) => {
  const n = el as HTMLElement | null;
  return !!n && (n.tagName === 'INPUT' || n.tagName === 'TEXTAREA' || n.isContentEditable);
};

export function VehicleDetailView({ data, plate, identifier, initialModal = null, initialTab = null, onBack, onRowChange, onPlateChange }: Props) {
  const shell = useAdminShell();
  const [detail, setDetail] = useState<AdminVehicleDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [tab, setTab] = useState<DossierTab>(initialTab ?? 'overview');
  const [modal, setModal] = useState<ModalId>(initialModal);
  const [propsCategory, setPropsCategory] = useState<string | null>(null);
  // Bumped on every open so each modal mounts with fresh state from the current detail.
  const [session, setSession] = useState(0);
  const show = (id: Exclude<ModalId, null>) => {
    setSession((n) => n + 1);
    setModal(id);
  };
  const [busy, setBusy] = useState<'block' | 'delete' | 'finance' | 'release' | null>(null);
  const activity = useActivity(detail ? detail.vehicle.plate : null);
  const bodyRef = useRef<HTMLDivElement>(null);
  const [more, setMore] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    const res = await request('admin:vehicle:get', { plate }, { toastError: false });
    setLoading(false);
    if (res.ok) setDetail(res.data);
    else setError(res.error);
  }, [plate]);

  useEffect(() => {
    if (!detail || detail.vehicle.plate !== plate) void load();
  }, [plate]); // eslint-disable-line react-hooks/exhaustive-deps

  // Lua sends an empty props table as [] — normalise to an object (stable identity for the editor).
  const props = useMemo<Record<string, unknown>>(() => {
    const p = detail?.vehicle.props;
    return p && typeof p === 'object' && !Array.isArray(p) ? p : {};
  }, [detail]);
  const damage = useMemo(() => normDamage(detail?.damage), [detail]);

  const isOpen = (id: Exclude<ModalId, null>) => modal === id && !shell.hidden;
  const close = () => setModal(null);

  // 1-7 switch tabs (not while typing or while a dialog is open).
  useEffect(() => {
    if (!detail) return undefined;
    const onKey = (e: KeyboardEvent) => {
      if (modal || shell.hidden || e.ctrlKey || e.altKey || e.metaKey || isTyping(e.target)) return;
      const i = Number(e.key) - 1;
      if (Number.isInteger(i) && i >= 0 && i < DOSSIER_TABS.length) {
        e.preventDefault();
        setTab(DOSSIER_TABS[i].value);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [detail, modal, shell.hidden]);

  // Scroll cue: fade the bottom edge while the tab's sheet runs past the window (1280×720).
  useEffect(() => {
    const body = bodyRef.current;
    if (!body) return undefined;
    const pane = body.querySelector<HTMLElement>(':scope > .nz-dos-pane');
    if (!pane) {
      setMore(false);
      return undefined;
    }
    const check = () => setMore(pane.scrollHeight - pane.clientHeight - pane.scrollTop > 4);
    check();
    const ro = new ResizeObserver(check);
    ro.observe(pane);
    Array.from(pane.children).forEach((c) => ro.observe(c));
    pane.addEventListener('scroll', check, { passive: true });
    return () => {
      ro.disconnect();
      pane.removeEventListener('scroll', check);
    };
  }, [tab, detail]);

  /** Apply a patch, refresh the dossier, the activity and the player's list. */
  const patch = useCallback(
    async (p: AdminVehiclePatch, message: string): Promise<boolean> => {
      if (!detail) return false;
      const oldPlate = detail.vehicle.plate;
      const res = await request('admin:vehicle:update', { plate: oldPlate, patch: p });
      if (!res.ok) return false;
      const next = res.data;
      setDetail(next);
      const stillHere = next.vehicle.ownerType === 'player' && next.vehicle.owner === identifier;
      onRowChange(oldPlate, stillHere ? rowFromDetail(next) : null);
      if (next.vehicle.plate !== oldPlate) onPlateChange(next.vehicle.plate);
      else activity.reload();
      toast({ type: 'success', message });
      return true;
    },
    [detail, identifier, onRowChange, onPlateChange, activity],
  );

  const toggleBlock = async () => {
    if (!detail) return;
    setBusy('block');
    const blocked = !detail.vehicle.blocked;
    await patch({ blocked }, blocked ? t('{vehicle} is blocked', { vehicle: detail.vehicle.label }) : t('{vehicle} is unblocked', { vehicle: detail.vehicle.label }));
    setBusy(null);
  };

  const release = async () => {
    setBusy('release');
    const ok = await patch({ impound: false }, t('Vehicle released from the impound'));
    setBusy(null);
    if (ok) setModal(null);
  };

  const remove = async () => {
    if (!detail) return;
    setBusy('delete');
    const res = await request('admin:vehicle:delete', { plate: detail.vehicle.plate });
    setBusy(null);
    if (!res.ok) return;
    toast({ type: 'success', message: t('{vehicle} ({plate}) was deleted', { vehicle: detail.vehicle.label, plate: detail.vehicle.plate }) });
    setModal(null);
    onRowChange(detail.vehicle.plate, null);
    onBack();
  };

  const deleteFinance = async () => {
    setBusy('finance');
    const ok = await patch({ finance: false }, t('Finance removed'));
    setBusy(null);
    if (ok) setModal(null);
  };

  const openProps = (category?: string) => {
    setPropsCategory(category ?? null);
    show('props');
  };

  /* ── loading / error ── */
  if (!detail) {
    return (
      <div className="nz-aveh-view nz-dos">
        {error ? (
          <>
            <div className="nz-dos-hero is-skel">
              <IconButton icon="arrowLeft" label={t('Back to vehicles (Esc)')} variant="line" onClick={onBack} className="nz-dos-hero__back" />
              <div className="nz-dos-hero__id">
                <span className="nz-dos-hero__eyebrow">{t('Vehicle')}</span>
                <h2 className="nz-dos-hero__plate-only">{plate}</h2>
              </div>
            </div>
            <div className="nz-dos-body nz-dos-pane--center">
              <EmptyState
                icon="warning"
                title={t('Could not load this vehicle')}
                description={error}
                action={
                  <div className="nz-aveh-row">
                    <Button size="sm" icon="arrowLeft" onClick={onBack}>
                      {t('Back')}
                    </Button>
                    <Button size="sm" variant="white" icon="refresh" onClick={load} loading={loading}>
                      {t('Try again')}
                    </Button>
                  </div>
                }
              />
            </div>
          </>
        ) : (
          <>
            <div className="nz-dos-hero is-skel" aria-busy="true">
              <IconButton icon="arrowLeft" label={t('Back to vehicles (Esc)')} variant="line" onClick={onBack} className="nz-dos-hero__back" />
              <Skeleton width={236} height={132} radius={10} />
              <div className="nz-dos-hero__id">
                <Skeleton width={120} height={9} />
                <Skeleton width={260} height={20} style={{ marginTop: 10 }} />
                <Skeleton width={150} height={16} radius={999} style={{ marginTop: 10 }} />
                <Skeleton width={190} height={28} style={{ marginTop: 12 }} />
              </div>
              <div className="nz-dos-hero__side">
                <Skeleton width="100%" height={78} radius={10} />
                <Skeleton width="100%" height={30} radius={6} style={{ marginTop: 8 }} />
              </div>
            </div>
            <div className="nz-dos-tabrow">
              <Skeleton width={520} height={30} radius={999} />
            </div>
            <div className="nz-dos-body">
              <div className="nz-dos-pane">
                <div className="nz-dos-sheet nz-dos-sheet--skel">
                  {[0, 1, 2].map((c) => (
                    <div key={c} className="nz-dos-col">
                      <Skeleton width="34%" height={9} />
                      {Array.from({ length: 6 }, (_, i) => (
                        <Skeleton key={i} width={`${58 + ((i * 13 + c * 7) % 36)}%`} height={10} style={{ marginTop: 14 }} />
                      ))}
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </>
        )}
      </div>
    );
  }

  const v = detail.vehicle;
  const needsService = v.engine < data.settings.vehicles.needsServiceBelow;
  const historyCount = detail.ownership.length + detail.service.length;

  const tabActions: Partial<Record<DossierTab, ReactNode>> = {
    overview: (
      <span className="nz-dos-tabrow__hint">
        <Kbd size="sm">1</Kbd>
        <i>–</i>
        <Kbd size="sm">7</Kbd>
        {t('switch tabs')}
      </span>
    ),
    condition: (
      <Button size="sm" variant="line" icon="edit" onClick={() => show('details')}>
        {t('Edit details & condition')}
      </Button>
    ),
    upgrades: (
      <Button size="sm" variant="line" icon="sliders" onClick={() => openProps()}>
        {t('Edit modifications')}
      </Button>
    ),
    finance: detail.finance ? (
      <>
        <Button size="sm" variant="red" icon="trash" onClick={() => show('financeDelete')}>
          {t('Remove')}
        </Button>
        <Button size="sm" variant="line" icon="edit" onClick={() => show('finance')}>
          {t('Edit finance')}
        </Button>
      </>
    ) : null /* the empty state carries the Add finance button */,
    history: (
      <>
        <Button size="sm" variant="line" icon="transfer" onClick={() => show('owner')}>
          {t('Change owner')}
        </Button>
        <Button size="sm" variant="line" icon="wrench" onClick={() => show('service')}>
          {t('Edit service history')}
        </Button>
      </>
    ),
    activity: (
      <Button size="sm" variant="ghost" icon="refresh" onClick={activity.reload} loading={activity.loading && !!activity.current}>
        {t('Refresh')}
      </Button>
    ),
  };

  return (
    <div className="nz-aveh-view nz-dos">
      <Hero
        detail={detail}
        data={data}
        busy={busy}
        onBack={onBack}
        onOwner={() => show('owner')}
        onBlock={toggleBlock}
        onImpound={() => show('impound')}
        onRelease={() => show('release')}
        onDelete={() => show('delete')}
      />

      <div className="nz-dos-tabrow">
        <Tabs<DossierTab>
          value={tab}
          onChange={setTab}
          variant="pill"
          className="nz-dos-tabs"
          items={DOSSIER_TABS.map((x) => ({
            value: x.value,
            label: x.label(),
            count: x.value === 'history' ? historyCount : x.value === 'activity' && activity.latest ? activity.latest.total : undefined,
          }))}
        />
        <div className="nz-dos-tabrow__actions">{tabActions[tab]}</div>
      </div>

      <div className={cx('nz-dos-body', `is-${tab}`, more && 'has-more')} key={tab} role="tabpanel" ref={bodyRef}>
        {tab === 'overview' && (
          <OverviewTab
            detail={detail}
            data={data}
            damage={damage}
            props={props}
            activity={activity}
            needsService={needsService}
            onTab={setTab}
            onEditCondition={() => show('details')}
            onEditDetails={() => show('details')}
            onEditImpound={() => show('impound')}
            onRelease={() => show('release')}
            onUnblock={toggleBlock}
            busy={busy}
          />
        )}
        {tab === 'condition' && (
          <ConditionTab
            detail={detail}
            data={data}
            damage={damage}
            needsService={needsService}
            serviceBelow={data.settings.vehicles.needsServiceBelow}
            activity={activity}
            onTab={setTab}
          />
        )}
        {tab === 'upgrades' && <UpgradesTab detail={detail} props={props} onEdit={openProps} onViewAll={() => show('mods')} />}
        {tab === 'finance' && <FinanceTab detail={detail} activity={activity} onEdit={() => show('finance')} onActivity={() => setTab('activity')} />}
        {tab === 'history' && <HistoryTab detail={detail} onOwner={() => show('owner')} onService={() => show('service')} />}
        {tab === 'activity' && <ActivityTab detail={detail} data={data} activity={activity} />}
        {tab === 'data' && <DataTab props={props} onEdit={() => openProps()} />}
      </div>

      <DetailsModal key={`DetailsModal-${session}`} open={isOpen('details')} detail={detail} onClose={close} onSave={patch} />
      <ImpoundModal key={`ImpoundModal-${session}`} open={isOpen('impound')} data={data} detail={detail} onClose={close} onSave={patch} />
      <FinanceModal key={`FinanceModal-${session}`} open={isOpen('finance')} detail={detail} onClose={close} onSave={patch} />
      <OwnerModal key={`OwnerModal-${session}`} open={isOpen('owner')} data={data} detail={detail} onClose={close} onSave={patch} />
      <ServiceModal key={`ServiceModal-${session}`} open={isOpen('service')} detail={detail} onClose={close} onSave={patch} />
      <PropsEditor
        key={`PropsEditor-${session}`}
        open={isOpen('props')}
        props={props}
        vehicleLabel={`${v.label} · ${v.plate}`}
        initialCategory={propsCategory}
        onClose={close}
        onSave={patch}
      />
      <ModsModal key={`ModsModal-${session}`} open={isOpen('mods')} detail={detail} onClose={close} onEdit={() => openProps()} />

      <ConfirmDialog
        open={isOpen('release')}
        tone="red"
        icon="unlock"
        title={t('Release vehicle?')}
        message={t('{vehicle} leaves {impound} without paying the fee and goes back to its garage.', {
          vehicle: v.label,
          impound: detail.impound?.locationName ?? t('the impound'),
        })}
        confirmLabel={t('Release')}
        busy={busy === 'release'}
        onConfirm={release}
        onCancel={close}
      />
      <ConfirmDialog
        open={isOpen('financeDelete')}
        tone="red"
        icon="money"
        title={t('Delete finance?')}
        message={t('The remaining balance of {amount} is written off and {vehicle} becomes fully owned.', {
          amount: money(detail.finance?.balance ?? 0),
          vehicle: v.label,
        })}
        confirmLabel={t('Delete finance')}
        busy={busy === 'finance'}
        onConfirm={deleteFinance}
        onCancel={close}
      />
      <ConfirmDialog
        open={isOpen('delete')}
        tone="red"
        icon="trash"
        title={t('Delete vehicle?')}
        message={t('{vehicle} ({plate}) is removed from {owner} permanently, with its history. This cannot be undone.', {
          vehicle: v.label,
          plate: v.plate,
          owner: v.ownerName || t('its owner'),
        })}
        confirmLabel={t('Delete vehicle')}
        busy={busy === 'delete'}
        onConfirm={remove}
        onCancel={close}
      />
    </div>
  );
}
