/**
 * OwnersSection — "Owners & copies" of a saved private location (admin:groups / admin:group:*).
 *
 * API
 *   <OwnersSection locationId maxCopies purchasable />
 * Lists every copy (group) with its owner, members and parked vehicles; assigns a new copy to a
 * player identifier; renames / deletes copies; changes member roles, removes or adds members.
 * Every action is sent to the server immediately (not on the location's Save).
 */
import { useCallback, useEffect, useState } from 'react';
import {
  Avatar,
  Badge,
  Button,
  ConfirmDialog,
  EmptyState,
  Field,
  Icon,
  IconButton,
  Input,
  Select,
  SkeletonRows,
  Tooltip,
  cx,
} from '@/components/ui';
import { request } from '@/lib/nui';
import { toast } from '@/lib/store';
import { t } from '@/lib/i18n';
import { date } from '@/lib/format';
import type { GroupInfo, Role } from '@/lib/types';
import { useAdminShell } from '../shared/shell';

export interface OwnersSectionProps {
  locationId: number;
  maxCopies: number;
  purchasable: boolean;
}

export function OwnersSection({ locationId, maxCopies, purchasable }: OwnersSectionProps) {
  const shell = useAdminShell();
  const [groups, setGroups] = useState<GroupInfo[] | null>(null);
  const [failed, setFailed] = useState(false);
  const [owner, setOwner] = useState('');
  const [label, setLabel] = useState('');
  const [creating, setCreating] = useState(false);
  const [expanded, setExpanded] = useState<number | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [confirm, setConfirm] = useState<GroupInfo | null>(null);
  const [deleting, setDeleting] = useState(false);
  const [memberText, setMemberText] = useState('');

  const load = useCallback(async () => {
    setFailed(false);
    setGroups(null);
    const res = await request('admin:groups', { locationId });
    if (res.ok) setGroups(res.data ?? []);
    else setFailed(true);
  }, [locationId]);

  useEffect(() => {
    void load();
  }, [load]);

  const used = groups?.length ?? 0;
  const full = maxCopies > 0 && used >= maxCopies;

  const replace = (g: GroupInfo) => setGroups((list) => (list ? list.map((x) => (x.id === g.id ? g : x)) : list));

  const create = async () => {
    const id = owner.trim();
    if (!id || creating || full) return;
    setCreating(true);
    const res = await request('admin:group:save', { group: { locationId, label: label.trim(), owner: id } });
    setCreating(false);
    if (!res.ok) return;
    setGroups((list) => [...(list ?? []), res.data]);
    setOwner('');
    setLabel('');
    setExpanded(res.data.id);
    toast({ type: 'success', message: t('{name} now owns a copy of this garage', { name: res.data.ownerName || res.data.owner }) });
  };

  const setRole = async (g: GroupInfo, identifier: string, role: Role | null) => {
    setBusy(`${g.id}:${identifier}`);
    const res = await request('admin:group:member', { groupId: g.id, identifier, role });
    setBusy(null);
    if (res.ok) replace(res.data);
    return res.ok;
  };

  const addMember = async (g: GroupInfo) => {
    const id = memberText.trim();
    if (!id) return;
    if (await setRole(g, id, 'member')) setMemberText('');
  };

  const doDelete = async () => {
    if (!confirm) return;
    setDeleting(true);
    const res = await request('admin:group:delete', { id: confirm.id });
    setDeleting(false);
    if (!res.ok) return;
    setGroups((list) => (list ? list.filter((x) => x.id !== confirm.id) : list));
    toast({ type: 'success', message: t('{label} was removed', { label: confirm.label }) });
    setConfirm(null);
  };

  return (
    <div className="nz-admin-owners">
      <div className="nz-admin-owners__summary">
        <span className="nz-admin-owners__copies">
          <Icon name="layers" size={14} strokeWidth={1.7} />
          {groups === null
            ? t('Loading copies…')
            : maxCopies > 0
              ? t('{used} of {max} copies in use', { used, max: maxCopies })
              : t('{used} copies in use · unlimited', { used })}
        </span>
        <span className="nz-admin-owners__live">
          <Icon name="info" size={12} strokeWidth={1.8} />
          {t('Changes here apply immediately')}
        </span>
      </div>

      <div className="nz-admin-owners__create">
        <Field label={t('Owner identifier')} hint={purchasable ? t('Assign a copy for free, without a purchase') : undefined}>
          <Input value={owner} onChange={setOwner} mono placeholder={t('e.g. citizen id')} maxLength={64} onEnter={() => void create()} disabled={full} />
        </Field>
        <Field label={t('Label')} hint={t('Optional')}>
          <Input value={label} onChange={setLabel} maxLength={60} placeholder={t('Garage name for the owner')} onEnter={() => void create()} disabled={full} />
        </Field>
        <Tooltip content={full ? t('Every copy is taken. Raise "Max copies" first.') : null} className="nz-admin-owners__assign">
          <Button variant="teal" icon="userPlus" loading={creating} disabled={!owner.trim() || full} onClick={() => void create()}>
            {t('Assign')}
          </Button>
        </Tooltip>
      </div>

      {groups === null && !failed && <SkeletonRows count={2} />}
      {failed && (
        <EmptyState
          compact
          icon="warning"
          title={t('Could not load the owners')}
          action={
            <Button size="sm" icon="refresh" onClick={() => void load()}>
              {t('Try again')}
            </Button>
          }
        />
      )}
      {groups && groups.length === 0 && (
        <EmptyState
          compact
          icon="users"
          title={t('Nobody owns this garage yet')}
          description={purchasable ? t('Players can buy it in game, or assign it above.') : t('Assign it to a player above.')}
        />
      )}

      {groups && groups.length > 0 && (
        <ul className="nz-admin-owners__list">
          {groups.map((g) => {
            const open = expanded === g.id;
            return (
              <li key={g.id} className={cx('nz-admin-owners__group', open && 'is-open')}>
                <div className="nz-admin-owners__row">
                  <button
                    type="button"
                    className="nz-admin-owners__toggle"
                    aria-expanded={open}
                    onClick={() => {
                      setExpanded(open ? null : g.id);
                      setMemberText('');
                    }}
                  >
                    <Avatar name={g.ownerName || g.owner} size={30} />
                    <span className="nz-admin-owners__text">
                      <b>{g.label}</b>
                      <small>
                        {g.ownerName || t('Unknown')} · <span className="nz-admin-owners__id">{g.owner}</span>
                      </small>
                    </span>
                    <span className="nz-admin-owners__stats">
                      <Badge tone="neutral" size="sm" icon="users">
                        {g.members.length}
                      </Badge>
                      <Badge tone={g.vehicles > 0 ? 'teal' : 'neutral'} size="sm" icon="car">
                        {g.vehicles}
                      </Badge>
                    </span>
                    <span className="nz-admin-owners__date">{date(g.createdAt)}</span>
                    <Icon name={open ? 'chevronUp' : 'chevronDown'} size={14} strokeWidth={1.8} className="nz-admin-owners__chev" />
                  </button>
                  <IconButton
                    icon="trash"
                    size="sm"
                    label={g.vehicles > 0 ? t('Move the parked vehicles out first') : t('Remove this copy')}
                    className="nz-admin-locs__del"
                    onClick={() => setConfirm(g)}
                  />
                </div>
                {open && (
                  <div className="nz-admin-owners__members">
                    {g.members.map((m) => {
                      const isOwner = m.identifier === g.owner;
                      const isBusy = busy === `${g.id}:${m.identifier}`;
                      return (
                        <div key={m.identifier} className="nz-admin-owners__member">
                          <Avatar name={m.name} size={24} />
                          <span className="nz-admin-owners__text">
                            <b>{m.name}</b>
                            <small className="nz-admin-owners__id">{m.identifier}</small>
                          </span>
                          <Select<Role>
                            size="sm"
                            value={m.role}
                            disabled={isBusy || isOwner}
                            className="nz-admin-owners__role"
                            onChange={(role) => void setRole(g, m.identifier, role)}
                            options={[
                              { value: 'owner', label: t('Owner'), icon: 'crown' },
                              { value: 'member', label: t('Member'), icon: 'user' },
                            ]}
                          />
                          <IconButton
                            icon="close"
                            size="sm"
                            label={isOwner ? t('Choose a new owner first') : t('Remove member')}
                            disabled={isOwner || isBusy}
                            onClick={() => void setRole(g, m.identifier, null)}
                          />
                        </div>
                      );
                    })}
                    <div className="nz-admin-owners__add">
                      <Input
                        className="nz-admin-owners__add-input"
                        size="sm"
                        mono
                        value={memberText}
                        onChange={setMemberText}
                        placeholder={t('Identifier of a new member')}
                        maxLength={64}
                        onEnter={() => void addMember(g)}
                      />
                      <Button size="sm" icon="plus" disabled={!memberText.trim() || busy !== null} onClick={() => void addMember(g)}>
                        {t('Add member')}
                      </Button>
                    </div>
                  </div>
                )}
              </li>
            );
          })}
        </ul>
      )}

      <ConfirmDialog
        open={!!confirm && !shell.hidden}
        tone="red"
        icon="trash"
        title={t('Remove {label}?', { label: confirm?.label ?? '' })}
        message={
          confirm && confirm.vehicles > 0
            ? t('{count} vehicles are still parked in this copy. The server will refuse until they are moved.', { count: confirm.vehicles })
            : t('The owner and members lose access to this copy. This cannot be undone.')
        }
        confirmLabel={t('Remove copy')}
        busy={deleting}
        onConfirm={() => void doDelete()}
        onCancel={() => setConfirm(null)}
      />
    </div>
  );
}
