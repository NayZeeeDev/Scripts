/**
 * Admin › Private garages (kind 'private') — table + map, create/edit (with owners & copies).
 * Columns: Name, Vehicle, Price or Assigned, Copies, Storage.
 */
import { t } from '@/lib/i18n';
import { money } from '@/lib/format';
import type { AdminPageProps, PrivateLocation } from '@/lib/types';
import { LocationListPage } from '../shared/LocationListPage';
import type { LocationColumn } from '../shared/LocationListPage';

export function PrivateGaragesPage(props: AdminPageProps) {
  const columns: LocationColumn<PrivateLocation>[] = [
    {
      key: 'price',
      header: t('Price'),
      width: '16%',
      render: (l) => (l.purchasable ? <b className="nz-admin-locs__strong">{money(l.price)}</b> : <span>{t('Assigned')}</span>),
    },
    {
      key: 'copies',
      header: t('Copies'),
      width: '13%',
      render: (l) => (l.maxCopies > 0 ? String(l.maxCopies) : <span title={t('Unlimited')}>{t('Unlimited')}</span>),
    },
    {
      key: 'storage',
      header: t('Storage'),
      width: '13%',
      render: (l) => (l.storage === 'shared' ? t('Shared') : t('Personal')),
    },
  ];

  return (
    <LocationListPage<PrivateLocation>
      {...props}
      kind="private"
      columns={columns}
      searchText={(l) => (l.purchasable ? 'purchasable' : 'assigned')}
      emptyIcon="users"
      emptyTitle={t('No private garages yet')}
      emptyDescription={t('Sell garages to players, or assign them to someone from the garage editor.')}
    />
  );
}
