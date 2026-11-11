/**
 * Ghost immobiliser keypad (docs/V2_CHANGES.md G.8). Four PIN cells and a 3×4 keypad (mouse,
 * digits / numpad, Backspace, Esc); a full PIN is sent at once.
 * - enter: the driver's PIN; keys:pinEnter asks the server, the pad shows its answer (wrong PIN,
 *   attempts left, the cooldown counting down, the alarm) and stays open until it is right.
 * - set: the owner chooses a PIN (the current one first when a PIN is set), types it twice,
 *   keys:pinSet stores it.
 * - collect: the digits go back to Lua as they are (CarLock.pinPrompt).
 * Closing always reports keys:pinDone { id } so a waiting Lua prompt ends (Lua keeps the
 * server's verdict itself: the pad's word is never trusted).
 */
import { useEffect, useRef, useState } from 'react';
import { Icon, Kbd, Modal, cx } from '@/components/ui';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import type { KeyPinPad } from '@/lib/types';
import { KeypadGlyph } from './glyphs';

type Step = 'enter' | 'old' | 'new' | 'repeat';

export interface PinPadProps {
  pad: KeyPinPad | null;
  /** the pad finished or was cancelled (success: the server accepted it) */
  onClose: (success: boolean) => void;
}

export function PinPad({ pad, onClose }: PinPadProps) {
  const open = !!pad;
  const length = Math.min(Math.max(pad?.length ?? 4, 4), 8);
  const [step, setStep] = useState<Step>('enter');
  const [digits, setDigits] = useState('');
  const [oldPin, setOldPin] = useState<string | null>(null);
  const [newPin, setNewPin] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ tone: 'red' | 'amber' | 'teal'; text: string } | null>(null);
  const [attempts, setAttempts] = useState<number | null>(null);
  const [coolUntil, setCoolUntil] = useState<number>(0);
  const [now, setNow] = useState(() => Date.now());
  const [shake, setShake] = useState(0);
  const [done, setDone] = useState(false);
  const closed = useRef(false);

  useEffect(() => {
    if (!pad) return;
    closed.current = false;
    setStep(pad.mode === 'set' ? (pad.pinSet ? 'old' : 'new') : 'enter');
    setDigits('');
    setOldPin(null);
    setNewPin(null);
    setBusy(false);
    setDone(false);
    setMsg(null);
    setAttempts(pad.attemptsLeft ?? null);
    setCoolUntil(pad.cooldown && pad.cooldown > 0 ? Date.now() + pad.cooldown * 1000 : 0);
  }, [pad?.id]);

  const cooling = coolUntil > now;
  useEffect(() => {
    if (!cooling) return;
    const id = window.setInterval(() => setNow(Date.now()), 250);
    return () => window.clearInterval(id);
  }, [cooling]);

  const finish = (success: boolean) => {
    if (closed.current) return;
    closed.current = true;
    onClose(success);
  };

  const wrong = (text: string, tone: 'red' | 'amber' = 'red') => {
    setMsg({ tone, text });
    setDigits('');
    setShake((n) => n + 1);
  };

  const submit = async (value: string) => {
    if (!pad || busy || done) return;
    if (pad.mode === 'collect') {
      setDone(true);
      await request('keys:pinDone', { id: pad.id, pin: value }, { toastError: false });
      finish(true);
      return;
    }
    if (pad.mode === 'enter') {
      setBusy(true);
      const res = await request('keys:pinEnter', { id: pad.id, pin: value }, { toastError: false });
      setBusy(false);
      if (!res.ok) {
        wrong(res.error);
        return;
      }
      const r = res.data;
      if (r?.success) {
        setDone(true);
        setMsg({ tone: 'teal', text: t('PIN accepted') });
        window.setTimeout(() => {
          void request('keys:pinDone', { id: pad.id, success: true }, { toastError: false });
          finish(true);
        }, 650);
        return;
      }
      if (typeof r?.attemptsLeft === 'number') setAttempts(r.attemptsLeft);
      if (r?.cooldown && r.cooldown > 0) {
        setCoolUntil(Date.now() + r.cooldown * 1000);
        setNow(Date.now());
      }
      wrong(r?.alarm ? t('Wrong PIN: the alarm went off') : r?.error || t('Wrong PIN'));
      return;
    }
    // set
    if (step === 'old') {
      setOldPin(value);
      setStep('new');
      setDigits('');
      setMsg(null);
      return;
    }
    if (step === 'new') {
      setNewPin(value);
      setStep('repeat');
      setDigits('');
      setMsg(null);
      return;
    }
    if (value !== newPin) {
      setStep('new');
      setNewPin(null);
      wrong(t('The two PINs are not the same. Choose it again.'), 'amber');
      return;
    }
    setBusy(true);
    const res = await request('keys:pinSet', { plate: pad.plate, pin: value, oldPin }, { toastError: false });
    setBusy(false);
    if (!res.ok) {
      // a wrong current PIN: ask it again
      if (pad.pinSet) {
        setStep('old');
        setOldPin(null);
      } else setStep('new');
      setNewPin(null);
      wrong(res.error);
      return;
    }
    setDone(true);
    setMsg({ tone: 'teal', text: t('PIN saved') });
    window.setTimeout(() => {
      void request('keys:pinDone', { id: pad.id, success: true }, { toastError: false });
      finish(true);
    }, 650);
  };

  const press = (d: string) => {
    if (busy || done || cooling) return;
    setMsg((m) => (m && m.tone !== 'teal' ? null : m));
    setDigits((cur) => (cur.length >= length ? cur : cur + d));
  };

  // a full PIN goes right away (a short beat so the last dot shows)
  useEffect(() => {
    if (!open || digits.length !== length || busy || done) return;
    const id = window.setTimeout(() => void submit(digits), 120);
    return () => window.clearTimeout(id);
  }, [digits, open, length, busy, done]);
  const back = () => {
    if (busy || done) return;
    setDigits((cur) => cur.slice(0, -1));
  };
  const cancel = () => {
    if (!pad) return;
    void request('keys:pinDone', { id: pad.id }, { toastError: false });
    finish(false);
  };

  // keyboard: digits, Backspace / Delete, Enter (submit a full PIN)
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (/^[0-9]$/.test(e.key)) {
        e.preventDefault();
        press(e.key);
      } else if (e.key === 'Backspace' || e.key === 'Delete') {
        e.preventDefault();
        back();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  const coolLeft = cooling ? Math.ceil((coolUntil - now) / 1000) : 0;
  const prompt =
    pad?.mode === 'set'
      ? step === 'old'
        ? t('Enter the current PIN')
        : step === 'new'
          ? t('Choose a four-digit PIN')
          : t('Type the new PIN again')
      : t('Enter the four-digit PIN');

  return (
    <Modal
      open={open}
      onClose={cancel}
      locked={busy}
      width={360}
      icon="lock"
      title={t('Ghost immobiliser')}
      subtitle={pad ? (pad.vehicle ? `${pad.vehicle} · ${pad.plate}` : pad.plate) : undefined}
      className="nz-keys-modal nz-keys-pin"
      footer={
        <span className="nz-keys-pin__foot">
          <Kbd>Esc</Kbd>
          {t('Cancel')}
        </span>
      }
    >
      <div className="nz-keys-pin__body">
        <span className="nz-keys-pin__icon" aria-hidden="true">
          <KeypadGlyph size={22} strokeWidth={1.6} />
        </span>
        <p className="nz-keys-pin__prompt">{prompt}</p>
        {pad?.mode === 'set' && (
          <div className="nz-keys-pin__steps" aria-hidden="true">
            {(pad.pinSet ? (['old', 'new', 'repeat'] as Step[]) : (['new', 'repeat'] as Step[])).map((s) => (
              <i key={s} className={cx(s === step && 'is-on')} />
            ))}
          </div>
        )}
        <div key={shake} className={cx('nz-keys-pin__cells', shake > 0 && 'is-shake', done && 'is-done')} aria-live="polite">
          {Array.from({ length }, (_, i) => (
            <span key={i} className={cx('nz-keys-pin__cell', i < digits.length && 'is-filled', i === digits.length && !done && !cooling && 'is-caret')}>
              {i < digits.length ? <i /> : null}
            </span>
          ))}
        </div>
        <div
          className={cx(
            'nz-keys-pin__msg',
            cooling ? 'is-red' : msg ? `is-${msg.tone}` : attempts !== null && pad?.mode === 'enter' ? 'is-amber' : '',
          )}
          role="status"
        >
          {cooling ? (
            <>
              <Icon name="clock" size={13} strokeWidth={1.9} />
              {t('Too many wrong PINs: wait {seconds} s', { seconds: coolLeft })}
            </>
          ) : msg ? (
            <>
              <Icon name={msg.tone === 'teal' ? 'checkCircle' : 'warning'} size={13} strokeWidth={1.9} />
              {msg.text}
              {msg.tone !== 'teal' && attempts !== null && pad?.mode === 'enter' && ` · ${t('{n} attempt(s) left', { n: attempts })}`}
            </>
          ) : attempts !== null && pad?.mode === 'enter' ? (
            t('{n} attempt(s) left', { n: attempts })
          ) : (
            <span className="nz-keys-pin__hint">{pad?.mode === 'enter' ? t('The engine starts once the PIN is right.') : t('Only you should know it.')}</span>
          )}
        </div>
        <div className={cx('nz-keys-pin__pad', (cooling || busy || done) && 'is-off')}>
          {['1', '2', '3', '4', '5', '6', '7', '8', '9'].map((d) => (
            <button key={d} type="button" onClick={() => press(d)} disabled={cooling || busy || done}>
              {d}
            </button>
          ))}
          <button type="button" className="is-fn" onClick={() => setDigits('')} disabled={busy || done || digits.length === 0} aria-label={t('Clear')}>
            {t('Clear')}
          </button>
          <button type="button" onClick={() => press('0')} disabled={cooling || busy || done}>
            0
          </button>
          <button type="button" className="is-fn" onClick={back} disabled={busy || done || digits.length === 0} aria-label={t('Delete')}>
            <Icon name="arrowLeft" size={15} strokeWidth={1.9} />
          </button>
        </div>
      </div>
    </Modal>
  );
}
