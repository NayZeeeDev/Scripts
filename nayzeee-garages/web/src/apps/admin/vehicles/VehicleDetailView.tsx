/**
 * Player vehicles — level 3: one vehicle's dashboard (admin:vehicle:get) with owner, block,
 * delete and six editable panels. Every edit goes through admin:vehicle:update.
 */
import { useCallback, useEffect, useMemo, useState } from 'react';
import { Avatar, Badge, Button, ConfirmDialog, EmptyState, Icon, IconButton, PlateTag, Skeleton, Tooltip, VehicleImage } from '@/components/ui';
import { request } from '@/lib/nui';
import { toast } from '@/lib/store';
import { t } from '@/lib/i18n';
import { money } from '@/lib/format';
import type { AdminOpenData, AdminVehicleDetail, AdminVehiclePatch, AdminVehicleRow } from '@/lib/types';
import { useAdminShell } from '../shared/shell';
import { StatusBadges } from './common';
import { DetailsPanel, FinancePanel, ImpoundPanel, ModsPanel, OwnershipPanel, ServicePanel } from './panels';
import { DetailsModal } from './modals/DetailsModal';
import { ImpoundModal } from './modals/ImpoundModal';
import { FinanceModal } from './modals/FinanceModal';
import { OwnerModal } from './modals/OwnerModal';
import { ServiceModal } from './modals/ServiceModal';
import { ModsModal, OwnershipModal, ServiceListModal } from './modals/ListModals';
import { PropsEditor } from './props/PropsEditor';
import { ownerTypeLabel, rowFromDetail, vehicleTypeIcon } from './util';

type ModalId =
  | 'details'
  | 'impound'
  | 'props'
  | 'mods'
  | 'finance'
  | 'financeDelete'
  | 'ownership'
  | 'service'
  | 'serviceList'
  | 'owner'
  | 'delete'
  | null;

interface Props {
  data: AdminOpenData;
  plate: string;
  /** Identifier of the player whose list we came from. */
  identifier: string;
  initialModal?: 'props' | null;
  onBack: () => void;
  /** The vehicle changed (row) or was deleted / left this player (null). */
  onRowChange: (oldPlate: string, row: AdminVehicleRow | null) => void;
  onPlateChange: (plate: string) => void;
}

export function VehicleDetailView({ data, plate, identifier, initialModal = null, onBack, onRowChange, onPlateChange }: Props) {
  const shell = useAdminShell();
  const [detail, setDetail] = useState<AdminVehicleDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [modal, setModal] = useState<ModalId>(initialModal);
  const [busy, setBusy] = useState<'block' | 'delete' | 'finance' | null>(null);

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

  const isOpen = (id: Exclude<ModalId, null>) => modal === id && !shell.hidden;
  const close = () => setModal(null);

  /** Apply a patch, refresh the dashboard and the player's list. */
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
      toast({ type: 'success', message });
      return true;
    },
    [detail, identifier, onRowChange, onPlateChange],
  );

  const toggleBlock = async () => {
    if (!detail) return;
    setBusy('block');
    const blocked = !detail.vehicle.blocked;
    await patch({ blocked }, blocked ? t('{vehicle} is blocked', { vehicle: detail.vehicle.label }) : t('{vehicle} is unblocked', { vehicle: detail.vehicle.label }));
    setBusy(null);
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

  if (!detail) {
    return (
      <div className="nz-aveh-view">
        <div className="nz-aveh-dhead">
          <IconButton icon="arrowLeft" label={t('Back to vehicles')} variant="line" onClick={onBack} />
          {error ? (
            <div className="nz-aveh-dhead__titles">
              <h2>{plate}</h2>
            </div>
          ) : (
            <>
              <Skeleton width={128} height={64} radius={8} />
              <div className="nz-aveh-dhead__titles">
                <Skeleton width={220} height={16} />
                <Skeleton width={150} height={11} style={{ marginTop: 9 }} />
              </div>
            </>
          )}
        </div>
        {error ? (
          <div className="nz-aveh-card nz-aveh-card--center">
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
        ) : (
          <div className="nz-aveh-dgrid">
            {Array.from({ length: 6 }, (_, i) => (
              <div key={i} className="nz-aveh-dpanel nz-aveh-dpanel--skel">
                <Skeleton width="40%" height={12} />
                <Skeleton width="86%" height={9} />
                <Skeleton width="64%" height={9} />
                <Skeleton width="72%" height={9} />
              </div>
            ))}
          </div>
        )}
      </div>
    );
  }

  const v = detail.vehicle;
  const groupLabel =
    v.ownerType === 'job'
      ? data.jobs.find((j) => j.name === v.job)?.label ?? v.job
      : v.ownerType === 'gang'
        ? data.gangs.find((g) => g.name === v.gang)?.label ?? v.gang
        : v.job ?? v.gang;

  return (
    <div className="nz-aveh-view">
      <div className="nz-aveh-dhead">
        <IconButton icon="arrowLeft" label={t('Back to vehicles')} variant="line" onClick={onBack} />
        <div className="nz-aveh-dhead__img">
          <VehicleImage image={v.image} vehicleType={v.vehicleType} alt={v.label} />
        </div>
        <div className="nz-aveh-dhead__titles">
          <div className="nz-aveh-row">
            <h2 className="nz-aveh-ellipsis">{v.label || v.model}</h2>
            {v.nickname && <span className="nz-aveh-nick">“{v.nickname}”</span>}
          </div>
          <div className="nz-aveh-row nz-aveh-dhead__meta">
            <PlateTag plate={v.plate} />
            <span className="nz-aveh-mono">{v.model}</span>
            <Icon name={vehicleTypeIcon(v.vehicleType)} size={13} strokeWidth={1.7} />
            <StatusBadges row={{ state: v.state, financed: !!detail.finance, blocked: v.blocked }} />
          </div>
        </div>
        <div className="nz-aveh-dhead__actions">
          <Tooltip content={t('Change owner')} side="bottom">
            <button type="button" className="nz-aveh-ownerchip" onClick={() => setModal('owner')}>
              <Avatar name={v.ownerName || '?'} size={22} />
              <span className="nz-aveh-ellipsis">{v.ownerName || t('No owner')}</span>
              {v.ownerType !== 'player' && (
                <Badge size="sm" tone="blue">
                  {ownerTypeLabel(v.ownerType)}
                </Badge>
              )}
              <Icon name="edit" size={13} strokeWidth={1.7} className="nz-aveh-ownerchip__edit" />
            </button>
          </Tooltip>
          <Tooltip
            side="bottom"
            content={v.blocked ? t('Players can take this vehicle out again.') : t('Blocked vehicles cannot be taken out of any garage.')}
          >
            <Button variant="line" icon={v.blocked ? 'unlock' : 'ban'} onClick={toggleBlock} loading={busy === 'block'}>
              {v.blocked ? t('Unblock') : t('Block vehicle')}
            </Button>
          </Tooltip>
          <Button variant="red" icon="trash" onClick={() => setModal('delete')}>
            {t('Delete')}
          </Button>
        </div>
      </div>

      {v.blocked && (
        <div className="nz-aveh-banner">
          <Icon name="ban" size={14} strokeWidth={1.8} />
          <span>{t('This vehicle is blocked — the owner cannot take it out of any garage until it is unblocked.')}</span>
        </div>
      )}

      <div className="nz-aveh-dgrid">
        <DetailsPanel detail={detail} onEdit={() => setModal('details')} jobLabel={groupLabel ?? null} />
        <ImpoundPanel detail={detail} onEdit={() => setModal('impound')} />
        <ModsPanel detail={detail} onEdit={() => setModal('props')} onViewAll={() => setModal('mods')} />
        <FinancePanel detail={detail} onEdit={() => setModal('finance')} onDelete={() => setModal('financeDelete')} />
        <OwnershipPanel detail={detail} onViewAll={() => setModal('ownership')} />
        <ServicePanel detail={detail} onEdit={() => setModal('service')} onViewAll={() => setModal('serviceList')} />
      </div>

      <DetailsModal open={isOpen('details')} detail={detail} onClose={close} onSave={patch} />
      <ImpoundModal open={isOpen('impound')} data={data} detail={detail} onClose={close} onSave={patch} />
      <FinanceModal open={isOpen('finance')} detail={detail} onClose={close} onSave={patch} />
      <OwnerModal open={isOpen('owner')} data={data} detail={detail} onClose={close} onSave={patch} />
      <ServiceModal open={isOpen('service')} detail={detail} onClose={close} onSave={patch} />
      <PropsEditor open={isOpen('props')} props={props} vehicleLabel={`${v.label} · ${v.plate}`} onClose={close} onSave={patch} />
      <OwnershipModal open={isOpen('ownership')} detail={detail} onClose={close} />
      <ServiceListModal open={isOpen('serviceList')} detail={detail} onClose={close} onEdit={() => setModal('service')} />
      <ModsModal open={isOpen('mods')} detail={detail} onClose={close} onEdit={() => setModal('props')} />

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
        message={
          <>
            {t('{vehicle} ({plate}) is removed from {owner} permanently, with its history. This cannot be undone.', {
              vehicle: v.label,
              plate: v.plate,
              owner: v.ownerName || t('its owner'),
            })}
          </>
        }
        confirmLabel={t('Delete vehicle')}
        busy={busy === 'delete'}
        onConfirm={remove}
        onCancel={close}
      />
    </div>
  );
}
