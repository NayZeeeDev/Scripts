/**
 * Give keys picker (docs/V2_CHANGES.md G.3 Share, G.5 dialogs): the players next to you with
 * the server's distance (keys:players), Refresh, then keys:share. What it gives follows the key
 * mode: flexible = a copy (you keep yours), limited = your key item, virtual = access. The
 * server re-checks the hand-over range, the owner, the item and the copy limits.
 * Keyboard: ↑ / ↓ pick, Enter give, R refresh.
 */
import { useEffect, useRef, useState } from 'react';
import { Avatar, Button, Icon, Modal, PlateTag, Skeleton, cx } from '@/components/ui';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import type { KeyEntry, KeyMode, KeyRingPlayer, KeysOpenData } from '@/lib/types';
import { KindGlyph } from './glyphs';
import { displayName, kindInfo, meters, shareInfo } from './model';
import type { Unit } from './model';

export interface ShareModalProps {
  k: KeyEntry | null;
  mode: KeysOpenData['mode'];
  keyMode: KeyMode | null | undefined;
  giveRange: number;
  unit: Unit;
  onClose: () => void;
  onDone: (player: KeyRingPlayer) => void;
}

export function ShareModal({ k, mode, keyMode, giveRange, unit, onClose, onDone }: ShareModalProps) {
  const [players, setPlayers] = useState<KeyRingPlayer[] | null>(null);
  const [picked, setPicked] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const open = !!k;
  const session = useRef(0);

  const load = async () => {
    const id = ++session.current;
    setLoading(true);
    setError(null);
    const res = await request('keys:players', {}, { toastError: false });
    if (id !== session.current) return;
    setLoading(false);
    if (!res.ok) {
      setError(res.error);
      setPlayers((p) => p ?? []);
      return;
    }
    const list = (Array.isArray(res.data) ? res.data : []).slice().sort((a, b) => (a.distance ?? 99) - (b.distance ?? 99));
    setPlayers(list);
    setPicked((p) => (p !== null && list.some((x) => x.serverId === p) ? p : (list[0]?.serverId ?? null)));
  };

  useEffect(() => {
    if (!open) return;
    setPicked(null);
    setPlayers(null);
    void load();
    return () => {
      session.current++;
    };
  }, [open, k?.plate]);

  const give = async (target = picked) => {
    if (!k || target === null || busy) return;
    const player = players?.find((p) => p.serverId === target);
    if (!player) return;
    setBusy(true);
    setError(null);
    const res = await request('keys:share', { plate: k.plate, target }, { toastError: false });
    setBusy(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    onDone(player);
  };

  // keyboard inside the picker (the modal holds the focus)
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      const typing = (e.target as HTMLElement | null)?.tagName === 'INPUT';
      if (typing) return;
      if ((e.key === 'ArrowDown' || e.key === 'ArrowUp') && players && players.length) {
        e.preventDefault();
        const i = Math.max(0, players.findIndex((p) => p.serverId === picked));
        const n = Math.max(0, Math.min(players.length - 1, i + (e.key === 'ArrowDown' ? 1 : -1)));
        setPicked(players[n].serverId);
      } else if ((e.key === 'r' || e.key === 'R') && !e.repeat) {
        e.preventDefault();
        void load();
      } else if (e.key === 'Enter' && !(e.target as HTMLElement | null)?.closest('button')) {
        e.preventDefault();
        void give();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  const info = k ? shareInfo(k, mode, keyMode) : null;
  const kind = k ? kindInfo(k) : null;
  return (
    <Modal
      open={open}
      title={info?.title ?? t('Give keys')}
      subtitle={
        k ? (
          <span className="nz-keys-share__sub">
            {displayName(k)} <PlateTag plate={k.plate} size="sm" />
          </span>
        ) : undefined
      }
      icon="userPlus"
      iconTone="teal"
      width={470}
      locked={busy}
      onClose={onClose}
      className="nz-keys-modal"
      footer={
        <>
          <Button variant="ghost" icon="refresh" onClick={() => void load()} disabled={busy || loading}>
            {t('Refresh')}
          </Button>
          <span className="nz-keys__spacer" />
          <Button variant="ghost" onClick={onClose} disabled={busy}>
            {t('Cancel')}
          </Button>
          <Button variant="teal" icon="key" loading={busy} disabled={picked === null || loading} onClick={() => void give()}>
            {info?.action ?? t('Give')}
          </Button>
        </>
      }
    >
      {k && kind && info && (
        <div className="nz-keys-share">
          <div className="nz-keys-share__key">
            <span className={cx('nz-keys-share__pip', `is-${kind.tone}`)}>
              <KindGlyph glyph={kind.glyph} size={15} strokeWidth={1.8} />
            </span>
            <span className="nz-keys-share__keytext">
              <b>{info.what}</b>
              <small>{info.effect}</small>
            </span>
          </div>

          <div className="nz-keys-share__head">
            <span>{t('Choose a player next to you')}</span>
            <small>{t('Within {range}', { range: meters(giveRange, unit) })}</small>
          </div>

          {players === null ? (
            <div className="nz-keys-share__list">
              {[0, 1].map((i) => (
                <div key={i} className="nz-keys-share__player is-skel">
                  <Skeleton width={34} height={34} radius={9} />
                  <span className="nz-keys-share__ptext">
                    <Skeleton width={130} height={11} />
                    <Skeleton width={70} height={9} />
                  </span>
                </div>
              ))}
            </div>
          ) : players.length === 0 ? (
            <div className="nz-keys-share__empty">
              <Icon name="users" size={20} strokeWidth={1.5} />
              <b>{t('Nobody close enough')}</b>
              <span>{t('Stand next to the player (within {range}) and refresh.', { range: meters(giveRange, unit) })}</span>
            </div>
          ) : (
            <div className={cx('nz-keys-share__list', loading && 'is-loading')} role="radiogroup" aria-label={t('Players')}>
              {players.map((pl) => (
                <button
                  key={pl.serverId}
                  type="button"
                  role="radio"
                  aria-checked={picked === pl.serverId}
                  className={cx('nz-keys-share__player', picked === pl.serverId && 'is-picked')}
                  onClick={() => setPicked(pl.serverId)}
                  onDoubleClick={() => {
                    setPicked(pl.serverId);
                    void give(pl.serverId);
                  }}
                >
                  {pl.anonymous ? (
                    // no names of strangers: the server id is what the player sees
                    <span className="nz-keys-share__idpip" aria-hidden="true">
                      <small>{t('ID')}</small>
                      {pl.serverId}
                    </span>
                  ) : (
                    <Avatar name={pl.name} size={34} />
                  )}
                  <span className="nz-keys-share__ptext">
                    <b>{pl.name}</b>
                    <small>{pl.anonymous ? t('Name not shown') : t('ID {id}', { id: pl.serverId })}</small>
                  </span>
                  {pl.distance !== undefined && <span className="nz-keys-share__dist">{meters(pl.distance, unit)}</span>}
                  <span className="nz-keys-share__radio" aria-hidden="true">
                    {picked === pl.serverId && <Icon name="check" size={12} strokeWidth={2.4} />}
                  </span>
                </button>
              ))}
            </div>
          )}

          {error && (
            <div className="nz-keys-share__error" role="alert">
              <Icon name="warning" size={14} strokeWidth={1.8} />
              <span>{error}</span>
            </div>
          )}
        </div>
      )}
    </Modal>
  );
}
