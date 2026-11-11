/**
 * "+ Give key" (nz:carlock:admin:give): plate, type (key item / temporary / virtual), the key
 * item's kind (key / fob, shown as a fob render) and a temporary key's hours. The server checks
 * everything again: a key item needs the player online, a virtual key a registered vehicle.
 */
import { useState } from 'react';
import { Button, Chip, Field, Icon, Input, Modal, NumberInput, Segmented, cx } from '@/components/ui';
import { FobArt } from '@/components/fob/FobArt';
import { t } from '@/lib/i18n';
import { request } from '@/lib/nui';
import { toast } from '@/lib/store';
import type { KeyAdminGive, KeyAdminPlayerData } from '@/lib/types';
import { duration } from './model';

export interface GivePreset {
  plate?: string;
  type?: KeyAdminGive['type'];
  keyKind?: 'key' | 'fob';
}

interface Props {
  preset: GivePreset;
  player: KeyAdminPlayerData['player'];
  ownedPlates: string[];
  fobDesign: string | null;
  tempKeyHours: number;
  onClose: () => void;
  onDone: (data: KeyAdminPlayerData) => void;
}

const HOUR_CHIPS = [1, 6, 24, 72, 168];
const PLATE_RE = /^[A-Z0-9 ]{1,8}$/;

export function GiveKeyModal({ preset, player, ownedPlates, fobDesign, tempKeyHours, onClose, onDone }: Props) {
  const [plate, setPlate] = useState(preset.plate ?? '');
  const [type, setType] = useState<KeyAdminGive['type']>(preset.type === 'item' && !player.online ? 'temp' : preset.type ?? 'item');
  const [keyKind, setKeyKind] = useState<'auto' | 'key' | 'fob'>(preset.keyKind ?? 'auto');
  const [hours, setHours] = useState(() => Math.max(0.05, Math.min(720, tempKeyHours || 24)));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const clean = plate.trim().toUpperCase();
  const plateOk = PLATE_RE.test(clean);
  const itemBlocked = type === 'item' && !player.online;
  const canGive = plateOk && !itemBlocked && !busy;

  const submit = async () => {
    if (!canGive) return;
    setBusy(true);
    setError(null);
    const payload: KeyAdminGive = { identifier: player.identifier, plate: clean, type };
    if (type === 'item' && keyKind !== 'auto') payload.keyKind = keyKind;
    if (type === 'temp') payload.hours = hours;
    const res = await request('keyadmin:give', payload, { toastError: false });
    setBusy(false);
    if (!res.ok || !res.data) {
      setError(res.ok ? t('Something went wrong') : res.error);
      return;
    }
    toast({
      type: 'success',
      message:
        type === 'item'
          ? t('{name} got a key item of {plate}', { name: player.name, plate: clean })
          : type === 'temp'
            ? t('{name} got a temporary key of {plate}', { name: player.name, plate: clean })
            : t('{name} got a virtual key of {plate}', { name: player.name, plate: clean }),
    });
    onDone(res.data);
  };

  const typeHelp =
    type === 'item'
      ? player.online
        ? t('A key item cut for the current locks goes into their pockets.')
        : t('Key items need the player online: their pockets must be reachable.')
      : type === 'temp'
        ? t('Works until it runs out, also while they are offline. Not an item.')
        : t('Lasting access without an item, like a key shared by the owner. Registered vehicles only.');

  return (
    <Modal
      open
      title={t('Give a key')}
      subtitle={t('to {name}', { name: player.name })}
      icon="userPlus"
      width={520}
      onClose={onClose}
      bodyClassName="nz-kadm-give"
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            {t('Cancel')}
          </Button>
          <Button variant="teal" icon="key" onClick={() => void submit()} loading={busy} disabled={!canGive}>
            {t('Give key')}
          </Button>
        </>
      }
    >
      <Field label={t('Plate')} error={clean && !plateOk ? t('Up to 8 letters, digits and spaces') : undefined}>
        <Input value={plate} onChange={(v) => setPlate(v.toUpperCase())} uppercase mono maxLength={8} placeholder="ABC 123" onEnter={() => void submit()} icon="tag" />
      </Field>
      {ownedPlates.length > 0 && (
        <div className="nz-kadm-give__plates">
          <span>{t('Their vehicles')}</span>
          {ownedPlates.slice(0, 8).map((p) => (
            <Chip key={p} active={clean === p} onClick={() => setPlate(p)}>
              {p}
            </Chip>
          ))}
        </div>
      )}

      <Field label={t('Type')}>
        <Segmented<KeyAdminGive['type']>
          full
          value={type}
          onChange={setType}
          options={[
            { value: 'item', label: t('Key item'), icon: 'key', disabled: !player.online },
            { value: 'temp', label: t('Temporary'), icon: 'clock' },
            { value: 'virtual', label: t('Virtual'), icon: 'link' },
          ]}
        />
      </Field>
      <p className={cx('nz-kadm-give__help', itemBlocked && 'is-warn')}>
        <Icon name={itemBlocked ? 'warning' : 'info'} size={13} strokeWidth={1.7} />
        {typeHelp}
      </p>

      {type === 'item' && (
        <div className="nz-kadm-give__kinds" role="radiogroup" aria-label={t('Kind')}>
          {(['auto', 'key', 'fob'] as const).map((k) => (
            <button
              key={k}
              type="button"
              role="radio"
              aria-checked={keyKind === k}
              className={cx('nz-kadm-kind', keyKind === k && 'is-on')}
              onClick={() => setKeyKind(k)}
            >
              <span className="nz-kadm-kind__art">
                {k === 'auto' ? (
                  <Icon name="sparkle" size={20} strokeWidth={1.6} />
                ) : (
                  <FobArt design={k === 'key' ? 'key' : fobDesign ?? undefined} kind={k} size={46} />
                )}
              </span>
              <b>{k === 'auto' ? t('Automatic') : k === 'key' ? t('Key') : t('Fob')}</b>
              <span>{k === 'auto' ? t('From the security profile') : k === 'key' ? t('Plain key, short range') : t('Remote, keyless')}</span>
            </button>
          ))}
        </div>
      )}

      {type === 'temp' && (
        <Field label={t('Lasts')} hint={t('About {time}', { time: duration(hours * 3600) })}>
          <div className="nz-kadm-give__hours">
            <NumberInput value={hours} onChange={setHours} min={0.05} max={720} step={0.5} suffix={t('h')} />
            <div className="nz-kadm-give__hchips">
              {HOUR_CHIPS.map((h) => (
                <Chip key={h} active={hours === h} onClick={() => setHours(h)}>
                  {h < 24 ? t('{n} h', { n: h }) : t('{n} d', { n: h / 24 })}
                </Chip>
              ))}
            </div>
          </div>
        </Field>
      )}

      {error && (
        <p className="nz-kadm-give__error" role="alert">
          <Icon name="warning" size={13} strokeWidth={1.8} />
          {error}
        </p>
      )}
    </Modal>
  );
}
