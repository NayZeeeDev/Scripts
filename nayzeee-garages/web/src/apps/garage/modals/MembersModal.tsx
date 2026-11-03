/**
 * Private garage members: add a player with a role, change roles, remove members.
 * Read-only for members without manage rights. The last owner cannot demote themself.
 */
import { useEffect, useMemo, useState } from 'react';
import { Avatar, Badge, Button, EmptyState, Icon, IconButton, Modal, Select, SkeletonRows, Spinner, cx } from '@/components/ui';
import type { SelectOption } from '@/components/ui';
import { t } from '@/lib/i18n';
import { request } from '@/lib/nui';
import { toast } from '@/lib/store';
import type { MemberData, Role } from '@/lib/types';

export function MembersModal({
  open,
  garageName,
  onClose,
  onChanged,
}: {
  open: boolean;
  garageName: string;
  onClose: () => void;
  onChanged: () => void;
}) {
  const [data, setData] = useState<MemberData | null>(null);
  const [failed, setFailed] = useState(false);
  const [player, setPlayer] = useState<number | null>(null);
  const [role, setRole] = useState<Role>('member');
  const [adding, setAdding] = useState(false);
  const [rowBusy, setRowBusy] = useState<string | null>(null);
  const [dirty, setDirty] = useState(false);

  useEffect(() => {
    if (!open) return;
    let alive = true;
    setData(null);
    setFailed(false);
    setPlayer(null);
    setRole('member');
    setDirty(false);
    void request('garage:members', {}).then((res) => {
      if (!alive) return;
      if (res.ok) setData(res.data);
      else setFailed(true);
    });
    return () => {
      alive = false;
    };
  }, [open]);

  const roleOptions: SelectOption<Role>[] = useMemo(
    () => [
      { value: 'member', label: t('Member'), icon: 'user' },
      { value: 'owner', label: t('Owner'), icon: 'crown' },
    ],
    [],
  );

  const members = useMemo(() => {
    const list = [...(data?.members ?? [])];
    const rank = (m: MemberData['members'][number]) => (m.you ? 0 : m.role === 'owner' ? 1 : 2);
    return list.sort((a, b) => rank(a) - rank(b) || a.name.localeCompare(b.name));
  }, [data]);

  const canManage = !!data?.canManage;
  const owners = members.filter((m) => m.role === 'owner').length;
  const youSoleOwner = members.some((m) => m.you && m.role === 'owner') && owners <= 1;

  const apply = (res: { ok: true; data: MemberData } | { ok: false; error: string }) => {
    if (!res.ok) return false;
    setData(res.data);
    setDirty(true);
    return true;
  };

  const add = async () => {
    if (player === null || adding) return;
    const name = data?.players.find((p) => p.serverId === player)?.name ?? '';
    setAdding(true);
    const res = await request('garage:memberAdd', { serverId: player, role });
    setAdding(false);
    if (apply(res)) {
      setPlayer(null);
      toast({ type: 'success', message: t('{name} was added to {garage}.', { name, garage: garageName }) });
    }
  };

  const changeRole = async (identifier: string, next: Role) => {
    setRowBusy(identifier);
    const res = await request('garage:memberRole', { identifier, role: next });
    setRowBusy(null);
    apply(res);
  };

  const remove = async (identifier: string, name: string) => {
    setRowBusy(identifier);
    const res = await request('garage:memberRemove', { identifier });
    setRowBusy(null);
    if (apply(res)) toast({ type: 'info', message: t('{name} was removed from {garage}.', { name, garage: garageName }) });
  };

  const done = () => {
    onClose();
    if (dirty) onChanged();
  };

  return (
    <Modal
      open={open}
      title={t('Manage members')}
      subtitle={garageName}
      icon="users"
      onClose={done}
      width={500}
      footer={
        <Button variant="white" onClick={done}>
          {t('Done')}
        </Button>
      }
    >
      {failed ? (
        <EmptyState compact icon="warning" title={t('Could not load members')} description={t('Close this window and try again.')} />
      ) : !data ? (
        <SkeletonRows count={3} />
      ) : (
        <>
          {canManage ? (
            <div className="nz-garage__addrow nz-garage__addrow--3">
              <Select<number>
                value={player}
                onChange={setPlayer}
                options={data.players.map((p) => ({ value: p.serverId, label: p.name, icon: 'user', hint: t('ID {id}', { id: p.serverId }) }))}
                placeholder={data.players.length ? t('Choose a player') : t('No players online')}
                icon="userPlus"
                disabled={data.players.length === 0}
                searchable
              />
              <Select<Role> value={role} onChange={setRole} options={roleOptions} className="nz-garage__role" />
              <Button variant="teal" icon="plus" disabled={player === null} loading={adding} onClick={() => void add()}>
                {t('Add')}
              </Button>
            </div>
          ) : (
            <div className="nz-garage__reason is-neutral">
              <Icon name="lock" size={14} strokeWidth={1.8} />
              <span>{t('Only owners can add members or change roles.')}</span>
            </div>
          )}

          <div className="nz-garage__people">
            {members.length === 0 ? (
              <EmptyState compact icon="users" title={t('No members yet')} />
            ) : (
              members.map((m) => {
                const lockedSelf = m.you && m.role === 'owner' && owners <= 1;
                const busy = rowBusy === m.identifier;
                return (
                  <div key={m.identifier} className={cx('nz-garage__person', m.you && 'is-you')}>
                    <span className="nz-garage__avatar">
                      <Avatar name={m.name} size={30} />
                      <i className={cx('nz-garage__presence', m.online && 'is-online')} title={m.online ? t('Online') : t('Offline')} />
                    </span>
                    <div className="nz-garage__person-text">
                      <b>
                        {m.name}
                        {m.you && (
                          <Badge tone="white" size="sm">
                            {t('You')}
                          </Badge>
                        )}
                      </b>
                      <span>{m.online ? t('Online') : t('Offline')}</span>
                    </div>
                    {canManage ? (
                      <>
                        <Select<Role>
                          value={m.role}
                          onChange={(r) => void changeRole(m.identifier, r)}
                          options={roleOptions}
                          size="sm"
                          disabled={lockedSelf || !!rowBusy}
                          className="nz-garage__role"
                        />
                        {busy ? (
                          <span className="nz-garage__spin">
                            <Spinner size={14} />
                          </span>
                        ) : m.you ? (
                          <span className="nz-garage__spin" />
                        ) : (
                          <IconButton
                            icon="close"
                            label={t('Remove {name}', { name: m.name })}
                            size="sm"
                            disabled={!!rowBusy}
                            onClick={() => void remove(m.identifier, m.name)}
                          />
                        )}
                      </>
                    ) : (
                      <Badge tone={m.role === 'owner' ? 'teal' : 'neutral'} icon={m.role === 'owner' ? 'crown' : 'user'}>
                        {m.role === 'owner' ? t('Owner') : t('Member')}
                      </Badge>
                    )}
                  </div>
                );
              })
            )}
          </div>
          {canManage && youSoleOwner && (
            <p className="nz-garage__helper">
              <Icon name="info" size={12} strokeWidth={1.8} />
              {t('Add another owner before changing your own role.')}
            </p>
          )}
        </>
      )}
    </Modal>
  );
}
