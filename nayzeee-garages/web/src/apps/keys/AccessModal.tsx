/**
 * Who has a key of the owner's vehicle (virtual mode): keys:holders (opaque ids, thieves masked
 * as 'Unknown holder' with how the key was obtained), Revoke with a confirmation
 * (keys:revoke answers with the new list). Physical modes have no list: nobody knows who
 * carries a key item, a locksmith changes the locks instead.
 */
import { useEffect, useState } from 'react';
import { Avatar, Button, ConfirmDialog, EmptyState, Icon, Modal, Skeleton, cx } from '@/components/ui';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import { toast } from '@/lib/store';
import type { KeyEntry, KeyHolder } from '@/lib/types';
import { ago, countdown, displayName, reasonLabel } from './model';

export interface AccessModalProps {
  k: KeyEntry | null;
  onClose: () => void;
  /** number of holders after a load / revoke (the action badge) */
  onCount: (plate: string, n: number) => void;
}

export function AccessModal({ k, onClose, onCount }: AccessModalProps) {
  const [list, setList] = useState<KeyHolder[] | 'loading' | 'error'>('loading');
  const [at, setAt] = useState(() => Date.now());
  const [now, setNow] = useState(() => Date.now());
  const [revoke, setRevoke] = useState<KeyHolder | null>(null);
  const [busy, setBusy] = useState(false);
  const open = !!k;

  const load = async () => {
    if (!k) return;
    setList('loading');
    const res = await request('keys:holders', { plate: k.plate }, { toastError: false });
    const rows = res.ok && Array.isArray(res.data) ? res.data : null;
    setList(rows ?? 'error');
    setAt(Date.now());
    if (rows) onCount(k.plate, rows.length);
  };

  useEffect(() => {
    if (!open) return;
    void load();
    const id = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(id);
  }, [open, k?.plate]);

  const confirm = async () => {
    if (!k || !revoke || busy) return;
    setBusy(true);
    const res = await request('keys:revoke', { plate: k.plate, id: revoke.id });
    setBusy(false);
    const holder = revoke;
    setRevoke(null);
    if (!res.ok) {
      // an old list (ids expire on the server): load it again
      void load();
      return;
    }
    const rows = Array.isArray(res.data) ? res.data : [];
    setList(rows);
    setAt(Date.now());
    onCount(k.plate, rows.length);
    toast({
      type: 'success',
      message: holder.masked ? t('That temporary key no longer works.') : t('{name} no longer has a key.', { name: holder.name }),
    });
  };

  const rows = Array.isArray(list) ? list : [];
  return (
    <>
      <Modal
        open={open && !revoke}
        onClose={onClose}
        width={500}
        icon="users"
        title={t('Key access')}
        subtitle={k ? displayName(k) : undefined}
        className="nz-keys-modal"
        footer={
          <>
            <Button variant="ghost" icon="refresh" onClick={() => void load()} disabled={list === 'loading'}>
              {t('Refresh')}
            </Button>
            <span className="nz-keys__spacer" />
            <Button variant="white" onClick={onClose}>
              {t('Done')}
            </Button>
          </>
        }
      >
        <div className="nz-keys-access">
          {list === 'loading' ? (
            [0, 1, 2].map((i) => (
              <div key={i} className="nz-keys-access__row is-skel">
                <Skeleton width={34} height={34} radius={9} />
                <span className="nz-keys-access__text">
                  <Skeleton width={140} height={11} />
                  <Skeleton width={90} height={9} />
                </span>
              </div>
            ))
          ) : list === 'error' ? (
            <EmptyState icon="warning" title={t('Could not load the key holders')} description={t('Try again in a moment.')} compact />
          ) : rows.length === 0 ? (
            <EmptyState icon="key" title={t('Only you have a key')} description={t('Share access from the key ring to give someone a key.')} compact />
          ) : (
            rows.map((h) => {
              const left = h.expiresIn !== null ? Math.max(0, h.expiresIn - Math.floor((now - at) / 1000)) : null;
              return (
                <div key={h.id} className={cx('nz-keys-access__row', h.masked && 'is-masked')}>
                  {h.masked ? (
                    <span className="nz-keys-access__mask" aria-hidden="true">
                      <Icon name="eyeOff" size={15} strokeWidth={1.7} />
                    </span>
                  ) : (
                    <Avatar name={h.name} size={34} />
                  )}
                  <span className="nz-keys-access__text">
                    <b>{h.name}</b>
                    <small>
                      {h.kind === 'temp' ? `${reasonLabel(h.reason)} · ` : `${t('Virtual key')} · `}
                      {left !== null ? t('{time} left', { time: countdown(left) }) : t('given {ago}', { ago: ago(h.agoSeconds) })}
                    </small>
                  </span>
                  <Button size="sm" variant="red" icon="ban" onClick={() => setRevoke(h)}>
                    {t('Revoke')}
                  </Button>
                </div>
              );
            })
          )}
        </div>
      </Modal>
      <ConfirmDialog
        open={!!revoke}
        tone="red"
        icon="ban"
        title={revoke?.masked ? t('Revoke this temporary key?') : t('Revoke the key of {name}?', { name: revoke?.name ?? '' })}
        message={
          revoke
            ? revoke.masked
              ? t('How it was obtained: {how}. Whoever holds it can no longer lock, unlock or start this vehicle.', { how: reasonLabel(revoke.reason) })
              : t('They can no longer lock, unlock or start this vehicle.')
            : null
        }
        confirmLabel={t('Revoke key')}
        busy={busy}
        onConfirm={() => void confirm()}
        onCancel={() => setRevoke(null)}
      />
    </>
  );
}
