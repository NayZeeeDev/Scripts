/**
 * Share picker: players next to you (server distance, keys:players) to give a virtual key to
 * (owner, virtual mode) or to hand the key item over to (physical mode). The server re-checks
 * the hand-over range, the owner and the item.
 */
import { useEffect, useState } from 'react';
import { Avatar, Button, Icon, Modal, PlateTag, Skeleton, cx } from '@/components/ui';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import type { KeyEntry, KeyRingPlayer } from '@/lib/types';
import { KindGlyph } from './glyphs';
import { displayName, kindInfo, meters } from './model';

export interface ShareModalProps {
  k: KeyEntry | null;
  mode: 'physical' | 'virtual';
  giveRange: number;
  unit: 'mi' | 'km';
  onClose: () => void;
  onDone: (player: KeyRingPlayer) => void;
}

export function ShareModal({ k, mode, giveRange, unit, onClose, onDone }: ShareModalProps) {
  const [players, setPlayers] = useState<KeyRingPlayer[] | null>(null);
  const [picked, setPicked] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const open = !!k;

  const load = async () => {
    setPlayers(null);
    setError(null);
    const res = await request('keys:players', {}, { toastError: false });
    if (!res.ok) {
      setError(res.error);
      setPlayers([]);
      return;
    }
    const list = Array.isArray(res.data) ? res.data : [];
    setPlayers(list);
    setPicked((p) => (p !== null && list.some((x) => x.serverId === p) ? p : (list[0]?.serverId ?? null)));
  };

  useEffect(() => {
    if (!open) return;
    setPicked(null);
    void load();
  }, [open, k?.plate]);

  const give = async () => {
    if (!k || picked === null || busy) return;
    const player = players?.find((p) => p.serverId === picked);
    if (!player) return;
    setBusy(true);
    setError(null);
    const res = await request('keys:share', { plate: k.plate, target: picked }, { toastError: false });
    setBusy(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    onDone(player);
  };

  const virtual = mode === 'virtual';
  const kind = k ? kindInfo(k) : null;
  return (
    <Modal
      open={open}
      title={virtual ? t('Give a key') : t('Hand the key over')}
      subtitle={k ? displayName(k) : undefined}
      icon="userPlus"
      iconTone="teal"
      width={460}
      locked={busy}
      onClose={onClose}
      className="nz-keys-modal"
      footer={
        <>
          <Button variant="ghost" onClick={onClose} disabled={busy}>
            {t('Cancel')}
          </Button>
          <Button variant="teal" icon={virtual ? 'key' : 'transfer'} loading={busy} disabled={picked === null} onClick={() => void give()}>
            {virtual ? t('Give key') : t('Hand over')}
          </Button>
        </>
      }
    >
      {k && kind && (
        <div className="nz-keys-share">
          <div className="nz-keys-share__key">
            <span className={cx('nz-keys-share__pip', `is-${kind.tone}`)}>
              <KindGlyph glyph={kind.glyph} size={15} strokeWidth={1.8} />
            </span>
            <span className="nz-keys-share__keytext">
              <b>{virtual ? t('A virtual key of this vehicle') : k.kind === 'fob' ? t('Your fob item') : t('Your key item')}</b>
              <small>
                {virtual
                  ? t('They can lock, unlock and drive it until you revoke the key.')
                  : t('The item leaves your pockets: you need another key to use the vehicle.')}
              </small>
            </span>
            <PlateTag plate={k.plate} size="sm" />
          </div>

          <div className="nz-keys-share__head">
            <span>{t('Players within {range}', { range: meters(giveRange, unit) })}</span>
            <button type="button" className="nz-keys__mini" onClick={() => void load()} title={t('Refresh')} aria-label={t('Refresh')}>
              <Icon name="refresh" size={12} strokeWidth={1.9} />
            </button>
          </div>

          {players === null ? (
            <div className="nz-keys-share__list">
              {[0, 1].map((i) => (
                <div key={i} className="nz-keys-share__player is-skel">
                  <Skeleton width={32} height={32} radius={8} />
                  <span className="nz-keys-share__ptext">
                    <Skeleton width={130} height={11} />
                    <Skeleton width={70} height={9} />
                  </span>
                </div>
              ))}
            </div>
          ) : players.length === 0 ? (
            <div className="nz-keys-share__empty">
              <Icon name="users" size={18} strokeWidth={1.5} />
              <b>{t('Nobody close enough')}</b>
              <span>{t('Stand next to the player (within {range}) and refresh.', { range: meters(giveRange, unit) })}</span>
            </div>
          ) : (
            <div className="nz-keys-share__list" role="radiogroup" aria-label={t('Players')}>
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
                    void give();
                  }}
                >
                  <Avatar name={pl.name} size={32} />
                  <span className="nz-keys-share__ptext">
                    <b>{pl.name}</b>
                    <small>
                      {t('ID {id}', { id: pl.serverId })}
                      {pl.distance !== undefined && ` · ${meters(pl.distance, unit)}`}
                    </small>
                  </span>
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
