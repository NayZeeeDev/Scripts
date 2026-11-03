/**
 * Garage interior control panel (app 'interior', takes focus). Compact window docked
 * bottom-left: floor pager, parked count, people inside (kick for owners), invite a nearby
 * player, leave the garage. Opened / closed by Lua with the interior panel key (F6).
 */
import { useEffect, useRef, useState } from 'react';
import { useApp, useUi, toast } from '@/lib/store';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import { useEscape } from '@/lib/escape';
import type { InteriorPanelData, PlayerOption } from '@/lib/types';
import {
  Avatar,
  Badge,
  Bar,
  Button,
  ConfirmDialog,
  EmptyState,
  IconButton,
  Icon,
  KeyHint,
  Select,
  Spinner,
  Window,
  cx,
} from '@/components/ui';
import './interior.css';

type Member = InteriorPanelData['members'][number];
type InviteState =
  | { step: 'idle' }
  | { step: 'loading' }
  | { step: 'pick'; players: PlayerOption[]; target: number | null; sending: boolean };

const isTyping = (el: EventTarget | null) => {
  const node = el as HTMLElement | null;
  if (!node || !node.tagName) return false;
  return node.tagName === 'INPUT' || node.tagName === 'TEXTAREA' || node.getAttribute('aria-haspopup') !== null;
};

function RoleBadge({ role }: { role: Member['role'] }) {
  if (role === 'owner')
    return (
      <Badge tone="teal" size="sm" icon="crown">
        {t('Owner')}
      </Badge>
    );
  if (role === 'member')
    return (
      <Badge tone="neutral" size="sm" icon="key">
        {t('Member')}
      </Badge>
    );
  return (
    <Badge tone="blue" size="sm" icon="eye">
      {t('Guest')}
    </Badge>
  );
}

function roleLine(role: InteriorPanelData['role']) {
  if (role === 'owner') return t('Your garage');
  if (role === 'member') return t('Member access');
  return t('Visiting');
}

export function InteriorPanelApp() {
  const { open, data, close, update } = useApp('interior');
  const [paging, setPaging] = useState<'prev' | 'next' | null>(null);
  const [invite, setInvite] = useState<InviteState>({ step: 'idle' });
  const [kickTarget, setKickTarget] = useState<Member | null>(null);
  const [kicking, setKicking] = useState(false);
  const [leaving, setLeaving] = useState(false);
  const openRef = useRef(open);
  openRef.current = open;

  // Fresh state every time the panel opens. Reset when it CLOSES (F6 or Lua, possibly with the
  // kick dialog still open): the panel renders nothing while closed, so the first render after
  // reopening is already clean. Resetting after the reopen would mount the stale dialog for a frame.
  useEffect(() => {
    if (open) return;
    setPaging(null);
    setInvite({ step: 'idle' });
    setKickTarget(null);
    setKicking(false);
    setLeaving(false);
  }, [open]);

  useEscape(() => close(), open);

  const page = data?.page ?? 1;
  const pages = Math.max(1, data?.pages ?? 1);
  const canPage = !!data && data.role !== 'guest' && pages > 1;

  const goPage = async (dir: 'prev' | 'next') => {
    if (!data || paging || !canPage) return;
    const target = dir === 'prev' ? page - 1 : page + 1;
    if (target < 1 || target > pages) return;
    setPaging(dir);
    const res = await request('interior:page', { page: target });
    setPaging(null);
    // Lua follows up with an `update`; reflect the floor right away.
    if (res.ok && openRef.current) update({ page: target });
  };

  // F6 closes (the game key bind does not fire while the panel has focus); ←/→ change floor.
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'F6') {
        e.preventDefault();
        close();
        return;
      }
      if (isTyping(e.target) || kickTarget) return;
      if (e.key === 'ArrowLeft') void goPage('prev');
      else if (e.key === 'ArrowRight') void goPage('next');
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  if (!open || !data) return null;

  const isOwner = data.role === 'owner';
  const members = [...(data.members ?? [])].sort((a, b) => {
    if (a.you !== b.you) return a.you ? -1 : 1;
    const rank = { owner: 0, member: 1, guest: 2 } as const;
    if (rank[a.role] !== rank[b.role]) return rank[a.role] - rank[b.role];
    return a.name.localeCompare(b.name);
  });
  const canKick = (m: Member) => isOwner && !m.you && m.role !== 'owner';

  const startInvite = async () => {
    setInvite({ step: 'loading' });
    const res = await request('interior:players', {});
    if (!openRef.current) return;
    if (!res.ok) {
      setInvite({ step: 'idle' });
      return;
    }
    const players = Array.isArray(res.data) ? res.data : [];
    setInvite({ step: 'pick', players, target: players.length === 1 ? players[0].serverId : null, sending: false });
  };

  const sendInvite = async () => {
    if (invite.step !== 'pick' || invite.target === null || invite.sending) return;
    const player = invite.players.find((p) => p.serverId === invite.target);
    setInvite({ ...invite, sending: true });
    const res = await request('interior:invite', { serverId: invite.target });
    if (!openRef.current) return;
    if (res.ok) {
      toast({ type: 'success', title: t('Invitation sent'), message: t('{name} can now join you inside.', { name: player?.name ?? '' }) });
      setInvite({ step: 'idle' });
    } else {
      setInvite({ ...invite, sending: false });
    }
  };

  const confirmKick = async () => {
    if (!kickTarget) return;
    setKicking(true);
    const target = kickTarget;
    const res = await request('interior:kick', { serverId: target.serverId });
    setKicking(false);
    if (!openRef.current) return;
    if (res.ok) {
      const current = useUi.getState().apps.interior.data;
      if (current) update({ members: current.members.filter((m) => m.serverId !== target.serverId) });
      toast({ type: 'info', message: t('{name} was removed from the garage.', { name: target.name }) });
    }
    setKickTarget(null);
  };

  const leave = async () => {
    if (leaving) return;
    setLeaving(true);
    const res = await request('interior:leave', {});
    if (res.ok) useUi.getState().hideApp('interior');
    else setLeaving(false);
  };

  const footer = (
    <>
      <KeyHint keys={['F6']} label={t('Close panel')} />
      <KeyHint keys={['Esc']} label={t('Close')} />
      {canPage && <KeyHint keys={['ArrowLeft', 'ArrowRight']} label={t('Floor')} />}
    </>
  );

  return (
    <>
      <Window
        title={data.garageName || t('Garage')}
        subtitle={roleLine(data.role)}
        onClose={close}
        width={392}
        footer={footer}
        className="nz-ipanel"
        bodyClassName="nz-ipanel__body"
      >
        {/* floor pager + occupancy */}
        <div className="nz-ipanel__floor">
          <div className="nz-ipanel__floor-row">
            <IconButton
              icon="chevronLeft"
              label={t('Previous floor')}
              variant="line"
              onClick={() => void goPage('prev')}
              disabled={!canPage || page <= 1 || !!paging}
            />
            <div className="nz-ipanel__floor-mid">
              <span className="nz-ipanel__floor-label">
                {paging ? <Spinner size={11} /> : <Icon name="layers" size={11} strokeWidth={1.9} />}
              </span>
              <b className="nz-ipanel__floor-value">{t('Floor {page}/{pages}', { page, pages })}</b>
              {pages > 1 && pages <= 12 && (
                <span className="nz-ipanel__dots" aria-hidden="true">
                  {Array.from({ length: pages }, (_, i) => (
                    <i key={i} className={cx(i + 1 === page && 'is-on')} />
                  ))}
                </span>
              )}
            </div>
            <IconButton
              icon="chevronRight"
              label={t('Next floor')}
              variant="line"
              onClick={() => void goPage('next')}
              disabled={!canPage || page >= pages || !!paging}
            />
          </div>
          <div className="nz-ipanel__occupancy">
            <div className="nz-ipanel__occupancy-top">
              <Icon name="car" size={13} strokeWidth={1.8} />
              <span>{t('Vehicles on this floor')}</span>
              <b>
                {data.vehicles}
                <small>/{data.slots}</small>
              </b>
            </div>
            <Bar value={data.vehicles} max={Math.max(1, data.slots)} tone="teal" height={3} />
          </div>
        </div>
        {data.role === 'guest' && pages > 1 && (
          <p className="nz-ipanel__note">
            <Icon name="info" size={12} strokeWidth={1.8} />
            {t('Only the owner and members can switch floors.')}
          </p>
        )}

        {/* people inside */}
        <div className="nz-ipanel__section">
          <div className="nz-ipanel__head">
            <h4>{t('People here')}</h4>
            <span className="nz-ipanel__count">{members.length}</span>
          </div>
          {members.length === 0 ? (
            <EmptyState compact icon="users" title={t('Nobody else is here')} />
          ) : (
            <ul className="nz-ipanel__members">
              {members.map((m) => (
                <li key={m.serverId} className={cx('nz-ipanel__member', m.you && 'is-you')}>
                  <Avatar name={m.name} size={28} />
                  <div className="nz-ipanel__member-text">
                    <b title={m.name}>{m.name}</b>
                    {m.you && <span className="nz-ipanel__you">{t('You')}</span>}
                  </div>
                  <RoleBadge role={m.role} />
                  {isOwner && (
                    <span className="nz-ipanel__kick-slot">
                      {canKick(m) && (
                        <IconButton
                          icon="close"
                          size="sm"
                          variant="ghost"
                          label={t('Remove {name}', { name: m.name })}
                          className="nz-ipanel__kick"
                          onClick={() => setKickTarget(m)}
                        />
                      )}
                    </span>
                  )}
                </li>
              ))}
            </ul>
          )}
        </div>

        {/* invite */}
        {data.canInvite && (
          <div className="nz-ipanel__section">
            {invite.step !== 'pick' ? (
              <Button
                variant="line"
                icon="userPlus"
                full
                loading={invite.step === 'loading'}
                onClick={() => void startInvite()}
              >
                {t('Invite player')}
              </Button>
            ) : (
              <div className="nz-ipanel__invite">
                <div className="nz-ipanel__head">
                  <h4>{t('Invite player')}</h4>
                  <span className="nz-ipanel__head-actions">
                    <IconButton icon="refresh" size="sm" label={t('Refresh')} onClick={() => void startInvite()} disabled={invite.sending} />
                    <IconButton icon="close" size="sm" label={t('Cancel')} onClick={() => setInvite({ step: 'idle' })} disabled={invite.sending} />
                  </span>
                </div>
                {invite.players.length === 0 ? (
                  <EmptyState
                    compact
                    icon="userPlus"
                    title={t('Nobody nearby')}
                    description={t('Players must be standing near the garage entrance.')}
                  />
                ) : (
                  <>
                    <div className="nz-ipanel__invite-row">
                      <Select<number>
                        value={invite.target}
                        onChange={(v) => setInvite({ ...invite, target: v })}
                        options={invite.players.map((p) => ({ value: p.serverId, label: p.name, hint: `#${p.serverId}`, icon: 'user' as const }))}
                        placeholder={t('Choose a player')}
                        disabled={invite.sending}
                        className="nz-ipanel__invite-select"
                      />
                      <Button
                        variant="teal"
                        icon="arrowRight"
                        onClick={() => void sendInvite()}
                        loading={invite.sending}
                        disabled={invite.target === null}
                      >
                        {t('Send')}
                      </Button>
                    </div>
                    <p className="nz-ipanel__hint">{t('Players must be standing near the garage entrance.')}</p>
                  </>
                )}
              </div>
            )}
          </div>
        )}

        <div className="nz-ipanel__leave">
          <Button variant="red" icon="logout" full loading={leaving} onClick={() => void leave()}>
            {t('Leave garage')}
          </Button>
        </div>
      </Window>

      <ConfirmDialog
        open={!!kickTarget}
        tone="red"
        icon="logout"
        title={t('Remove from garage')}
        message={t('{name} will be sent back outside. They can come back if someone invites them again.', {
          name: kickTarget?.name ?? '',
        })}
        confirmLabel={t('Remove')}
        busy={kicking}
        onConfirm={() => void confirmKick()}
        onCancel={() => setKickTarget(null)}
      />
    </>
  );
}
