/**
 * A key up close (docs/V2_CHANGES.md G.5): the fob art, vehicle name, plate and what the key
 * is. Ground keys (held for the inspector by the server for 20 s): E Keep (keys:groundKeep),
 * G / Esc Return to ground (keys:groundReturn). Carried keys (nz:carlock:inspect): whether it
 * fits the current locks and how it was obtained; Esc closes. `InspectCard` is the card on
 * its own (bottom centre, the game stays visible), `InspectModal` the same over the key ring.
 */
import { useEffect, useState } from 'react';
import { Button, Icon, Kbd, Modal, PlateTag, cx } from '@/components/ui';
import { FobArt } from '@/components/fob/FobArt';
import { useEscape } from '@/lib/escape';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import type { KeyEntry, KeyInspectInfo } from '@/lib/types';
import { ago, displayName, reasonLabel } from './model';

/** Body of the card: art + texts. */
function InspectBody({ info, entry }: { info: KeyInspectInfo; entry?: KeyEntry | null }) {
  const fob = info.keyKind === 'fob';
  const name = displayName({ nickname: entry?.nickname ?? null, label: info.label });
  const validity =
    info.valid === true
      ? { tone: 'teal', icon: 'checkCircle' as const, text: t('Fits the current locks') }
      : info.valid === false
        ? {
            tone: 'red',
            icon: 'ban' as const,
            text:
              info.reason === 'version'
                ? t('Old key: the locks were changed')
                : info.reason === 'plate'
                  ? t('Does not fit this plate any more')
                  : t('This key does not work'),
          }
        : null;
  return (
    <div className="nz-keys-inspect__body">
      <span className="nz-keys-inspect__art">
        <FobArt design={fob ? info.design || 'classic' : 'key'} kind={fob ? 'fob' : 'key'} brand={info.make || null} size={118} />
      </span>
      <span className="nz-keys-inspect__text">
        {info.make && <small className="nz-keys-inspect__make">{info.make}</small>}
        <b className="nz-keys-inspect__name" title={name}>
          {name}
        </b>
        <span className="nz-keys-inspect__row">
          <PlateTag plate={info.plate} />
          <span className={cx('nz-keys-chip', fob && 'is-teal')}>{info.kind === 'temp' ? t("Driver's key") : fob ? t('Fob') : t('Key')}</span>
        </span>
        <small className="nz-keys-inspect__label">{info.keyLabel}</small>
        {validity && (
          <span className={cx('nz-keys-inspect__line', `is-${validity.tone}`)}>
            <Icon name={validity.icon} size={13} strokeWidth={1.9} />
            {validity.text}
          </span>
        )}
        {info.origin && (
          <span className="nz-keys-inspect__line is-amber">
            <Icon name="info" size={13} strokeWidth={1.9} />
            {reasonLabel(info.origin)}
          </span>
        )}
        {info.droppedAgo != null && (
          <span className="nz-keys-inspect__line">
            <Icon name="clock" size={13} strokeWidth={1.9} />
            {t('Dropped {ago}', { ago: ago(info.droppedAgo) })}
          </span>
        )}
      </span>
    </div>
  );
}

export interface InspectCardProps {
  source: 'ground' | 'carried';
  id?: string;
  info: KeyInspectInfo;
  onClose: () => void;
}

/** The card on its own (no window): ground keys Keep / Return, carried keys Close. */
export function InspectCard({ source, id, info, onClose }: InspectCardProps) {
  const [busy, setBusy] = useState<'keep' | 'return' | null>(null);
  const ground = source === 'ground' && !!id;

  const keep = async () => {
    if (!ground || busy || !id) return;
    setBusy('keep');
    const res = await request('keys:groundKeep', { id }, { toastError: false });
    setBusy(null);
    // Lua closes the card itself (then the pick-up animation plays); a refusal is shown by Lua too
    if (!res.ok) onClose();
  };
  const giveBack = async () => {
    if (busy) return;
    if (!ground || !id) {
      onClose();
      return;
    }
    setBusy('return');
    await request('keys:groundReturn', { id }, { toastError: false });
    setBusy(null);
    onClose();
  };

  useEscape(() => void giveBack(), true);
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.repeat) return;
      const k = e.key.toLowerCase();
      if (ground && k === 'e') {
        e.preventDefault();
        void keep();
      } else if (k === 'g' || (!ground && k === 'enter')) {
        e.preventDefault();
        void giveBack();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  return (
    <div className="nz-keys-inspect is-alone" role="dialog" aria-label={t('Key')}>
      <div className="nz-keys-inspect__card">
        <InspectBody info={info} />
        <div className="nz-keys-inspect__keys">
          {ground ? (
            <>
              <button type="button" className="nz-keys-inspect__key is-keep" onClick={() => void keep()} disabled={!!busy}>
                <Kbd>E</Kbd>
                <span>{busy === 'keep' ? t('Picking up…') : t('Keep the key')}</span>
              </button>
              <button type="button" className="nz-keys-inspect__key" onClick={() => void giveBack()} disabled={!!busy}>
                <Kbd>G</Kbd>
                <Kbd>Esc</Kbd>
                <span>{t('Return to ground')}</span>
              </button>
            </>
          ) : (
            <button type="button" className="nz-keys-inspect__key" onClick={onClose}>
              <Kbd>Esc</Kbd>
              <span>{t('Put it away')}</span>
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

/** The same card over the key ring (a key item of the ring, or a virtual key's facts). */
export function InspectModal({ info, entry, onClose }: { info: KeyInspectInfo | null; entry?: KeyEntry | null; onClose: () => void }) {
  return (
    <Modal
      open={!!info}
      onClose={onClose}
      width={460}
      icon="eye"
      title={t('Inspect key')}
      className="nz-keys-modal"
      footer={
        <Button variant="white" onClick={onClose}>
          {t('Done')}
        </Button>
      }
    >
      {info && (
        <div className="nz-keys-inspect">
          <InspectBody info={info} entry={entry} />
        </div>
      )}
    </Modal>
  );
}
