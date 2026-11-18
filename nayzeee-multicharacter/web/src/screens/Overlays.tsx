import { useEffect, useState, type ReactNode } from 'react';
import { AlertTriangle, CheckCircle2, Info, LogOut, Trash2, XCircle, Gift } from 'lucide-react';
import { useStore } from '../lib/store';
import { post } from '../lib/nui';
import { cue } from '../lib/audio';
import { t } from '../i18n';
import { Btn, cx, Modal, Slider, Toggle } from '../components/ui';
import type { Settings } from '../lib/types';

function Toasts() {
  const toasts = useStore((s) => s.toasts);
  const dismiss = useStore((s) => s.dismissToast);
  const icon = { success: <CheckCircle2 size={16} className="text-ok" />, error: <XCircle size={16} className="text-bad" />, warning: <AlertTriangle size={16} className="text-warn" />, info: <Info size={16} className="text-accent-hi" /> };
  const bar = { success: 'bg-ok', error: 'bg-bad', warning: 'bg-warn', info: 'bg-accent' };
  return (
    <div className="absolute left-1/2 -translate-x-1/2 top-[26px] z-[80] flex flex-col items-center gap-2 pointer-events-none">
      {toasts.map((x) => (
        <div key={x.id} onClick={() => dismiss(x.id)}
          className="pointer-events-auto glass cut cut-sm a-down relative flex items-center gap-3 pl-4 pr-5 h-[44px] min-w-[260px] max-w-[560px] cursor-pointer">
          <span className={cx('absolute left-0 top-0 bottom-0 w-[3px]', bar[x.type])} />
          {icon[x.type]}
          <span className="text-[14px] font-medium text-fg truncate">{x.text}</span>
        </div>
      ))}
    </div>
  );
}

function Busy() {
  const busy = useStore((s) => s.busy);
  if (!busy.on) return null;
  return (
    <div className="absolute left-1/2 -translate-x-1/2 top-[86px] z-[70] a-down">
      <div className="glass-dark rounded-full h-[38px] pl-3 pr-5 flex items-center gap-3">
        <span className="w-[16px] h-[16px] rounded-full border-2 border-white/15 border-t-accent a-spin" />
        <span className="label text-[12px] text-fg">{busy.text || t('loading')}</span>
      </div>
    </div>
  );
}

function Row({ title, desc, children }: { title: string; desc?: string; children: ReactNode }) {
  return (
    <div className="flex items-center gap-6 py-[11px] border-b border-white/[.05] last:border-0">
      <div className="flex-1 min-w-0">
        <div className="text-[14px] font-medium text-fg">{title}</div>
        {desc && <div className="text-[12px] text-fg-3 mt-[1px]">{desc}</div>}
      </div>
      <div className="shrink-0 flex items-center">{children}</div>
    </div>
  );
}

function Group({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div>
      <div className="flex items-center gap-2 mb-1">
        <span className="w-[3px] h-[11px] bg-accent" />
        <span className="micro text-[9px] text-fg-2">{title}</span>
      </div>
      {children}
    </div>
  );
}

function SettingsModal({ onClose }: { onClose: () => void }) {
  const s = useStore((st) => st.settings);
  const set = useStore((st) => st.setSettings);
  const toast = useStore((st) => st.toast);
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const b = (k: keyof Settings) => <Toggle on={!!s[k]} onChange={(v) => set({ [k]: v } as Partial<Settings>)} />;
  const pct = (v: number) => `${Math.round(v * 100)}%`;

  const redeem = async () => {
    if (!code.trim() || busy) return;
    setBusy(true);
    const r = await post<{ ok: boolean; msg?: string }>('redeem', { code: code.trim() });
    setBusy(false);
    if (r?.ok) { cue('confirm'); setCode(''); toast('success', r.msg || t('saved')); } else toast('error', r?.msg || t('v_fix'));
  };

  return (
    <Modal onClose={onClose} width={760} title={t('settings')} code="SYS_CONFIG_C05">
      <div className="grid grid-cols-2 gap-x-10 gap-y-6 px-7 pb-7">
        <div className="flex flex-col gap-6">
          <Group title={t('set_interface')}>
            <div className="py-[11px] border-b border-white/[.05]">
              <div className="text-[14px] font-medium text-fg mb-2">{t('set_scale')}</div>
              <Slider value={s.scale} min={0.75} max={1.25} step={0.05} format={pct} onChange={(v) => set({ scale: Math.round(v * 100) / 100 })} />
            </div>
            <Row title={t('set_plates')} desc={t('set_plates_desc')}>{b('plates')}</Row>
            <Row title={t('set_perf')} desc={t('set_perf_desc')}>{b('perf')}</Row>
          </Group>
          <Group title={t('set_camera')}>
            <Row title={t('set_sway')} desc={t('set_sway_desc')}>{b('sway')}</Row>
            <Row title={t('set_dof')} desc={t('set_dof_desc')}>{b('dof')}</Row>
            <Row title={t('set_bars')} desc={t('set_bars_desc')}>{b('bars')}</Row>
          </Group>
        </div>
        <div className="flex flex-col gap-6">
          <Group title={t('set_audio')}>
            <Row title={t('set_muted')}>{b('muted')}</Row>
            <div className={cx('py-[11px] border-b border-white/[.05] transition-opacity', s.muted && 'opacity-40')}>
              <div className="text-[14px] font-medium text-fg mb-2">{t('set_ui_volume')}</div>
              <Slider value={s.uiVolume} min={0} max={1} step={0.05} format={pct} onChange={(v) => set({ uiVolume: v })} />
            </div>
            <div className={cx('py-[11px] transition-opacity', s.muted && 'opacity-40')}>
              <div className="text-[14px] font-medium text-fg mb-2">{t('set_amb_volume')}</div>
              <Slider value={s.ambientVolume} min={0} max={1} step={0.05} format={pct} onChange={(v) => set({ ambientVolume: v })} />
            </div>
          </Group>
          <Group title={t('set_account')}>
            <div className="glass-soft p-4 mt-2">
              <div className="flex items-center gap-2 text-[13px] text-fg-2 mb-3"><Gift size={15} className="text-accent-hi" />{t('redeem_desc')}</div>
              <div className="flex gap-2">
                <input className="field !h-[40px] font-mono !text-[13px] tracking-[.08em] uppercase" placeholder={t('redeem_ph')} value={code}
                  onChange={(e) => setCode(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') redeem(); }} />
                <Btn variant="accent" disabled={!code.trim() || busy} onClick={redeem}>{t('redeem')}</Btn>
              </div>
            </div>
          </Group>
        </div>
      </div>
    </Modal>
  );
}

function QuitModal({ onClose }: { onClose: () => void }) {
  return (
    <Modal onClose={onClose} width={460} title={t('quit_title')} code="SESSION_END">
      <div className="px-7 pb-7">
        <div className="text-[14px] text-fg-2">{t('quit_desc')}</div>
        <div className="flex gap-2 justify-end mt-6">
          <Btn onClick={onClose}>{t('cancel')}</Btn>
          <Btn variant="danger" onClick={() => { onClose(); post('quit'); }}><LogOut size={15} />{t('quit_confirm')}</Btn>
        </div>
      </div>
    </Modal>
  );
}

function DeleteModal({ slot, onClose }: { slot: number; onClose: () => void }) {
  const cfg = useStore((s) => s.cfg)!;
  const c = useStore((s) => s.lobby?.characters.find((x) => x.slot === slot));
  const toast = useStore((s) => s.toast);
  const [v, setV] = useState('');
  const [busy, setBusy] = useState(false);
  if (!c) return null;
  const needType = cfg.typeToConfirm !== false;
  const ok = !needType || v.trim().toLowerCase() === c.name.trim().toLowerCase();
  const go = async () => {
    if (!ok || busy) return;
    setBusy(true);
    const r = await post<{ ok: boolean; msg?: string }>('delete', { slot, confirm: v.trim() });
    setBusy(false);
    if (r?.ok) { onClose(); toast('success', r.msg || t('saved')); } else toast('error', r?.msg || t('v_fix'));
  };
  return (
    <Modal onClose={onClose} width={500} title={t('delete_title', c.name)} code={`RECORD_PURGE // SLOT_${String(slot).padStart(2, '0')}`}>
      <div className="px-7 pb-7">
        <div className="flex gap-3 p-4 bg-bad/[.08] border border-bad/25 text-[13px] text-fg-2 leading-snug">
          <Trash2 size={18} className="text-bad shrink-0 mt-[1px]" />{t('delete_desc')}
        </div>
        {needType && (
          <>
            <div className="micro text-[9px] text-fg-3 mt-5 mb-2">{t('delete_type', '')}<span className="text-fg normal-case tracking-normal font-body text-[12px]">{c.name}</span></div>
            <input autoFocus className={cx('field', v && !ok && 'err')} value={v} onChange={(e) => setV(e.target.value)} placeholder={c.name}
              onKeyDown={(e) => { if (e.key === 'Enter') go(); }} />
          </>
        )}
        <div className="flex gap-2 justify-end mt-6">
          <Btn onClick={onClose}>{t('cancel')}</Btn>
          <Btn variant="danger" disabled={!ok || busy} onClick={go}><Trash2 size={15} />{t('delete_confirm')}</Btn>
        </div>
      </div>
    </Modal>
  );
}

function RemoveLinkModal({ id, name, onClose }: { id: number; name: string; onClose: () => void }) {
  const toast = useStore((s) => s.toast);
  return (
    <Modal onClose={onClose} width={460} title={t('remove_link')} code="SQUAD_UNLINK">
      <div className="px-7 pb-7">
        <div className="text-[14px] text-fg-2">{t('remove_link_desc', name)}</div>
        <div className="flex gap-2 justify-end mt-6">
          <Btn onClick={onClose}>{t('cancel')}</Btn>
          <Btn variant="danger" onClick={async () => {
            onClose();
            const r = await post<{ ok: boolean; msg?: string }>('squadRemove', { id });
            if (r && r.ok === false) toast('error', r.msg || t('v_fix'));
          }}>{t('remove')}</Btn>
        </div>
      </div>
    </Modal>
  );
}

export default function Overlays() {
  const modal = useStore((s) => s.modal);
  const setModal = useStore((s) => s.setModal);
  const view = useStore((s) => s.view);
  const close = () => { cue('back'); setModal(null); };

  useEffect(() => {
    if (!modal) return;
    cue('whoosh');
    const k = (e: KeyboardEvent) => { if (e.key === 'Escape') { e.stopImmediatePropagation(); close(); } };
    window.addEventListener('keydown', k, true);
    return () => window.removeEventListener('keydown', k, true);
  }, [modal]);

  const showModals = view === 'lobby';
  return (
    <>
      {showModals && modal?.kind === 'settings' && <SettingsModal onClose={close} />}
      {showModals && modal?.kind === 'quit' && <QuitModal onClose={close} />}
      {showModals && modal?.kind === 'delete' && <DeleteModal slot={modal.slot} onClose={close} />}
      {showModals && modal?.kind === 'removeLink' && <RemoveLinkModal id={modal.id} name={modal.name} onClose={close} />}
      {view !== 'cutscene' && <Busy />}
      <Toasts />
    </>
  );
}
