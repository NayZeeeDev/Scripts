import { useEffect, useState } from 'react';
import { Camera, ScanFace, Shirt, Users2, Heart } from 'lucide-react';
import { useStore, useChar } from '../lib/store';
import { post } from '../lib/nui';
import { cue } from '../lib/audio';
import { t } from '../i18n';
import { cx, HoldButton, isTyping, Kbd } from '../components/ui';
import Rail, { RAIL_W } from './lobby/Rail';
import { Roster, StatusPill } from './lobby/TopBar';
import Characters, { useRows } from './lobby/Characters';
import Themes, { MoodChips } from './lobby/Themes';
import Customize from './lobby/Customize';
import Squad, { type SquadTab } from './lobby/Squad';

const LEFT = RAIL_W + 36;
const COL_W = 440;

function Wordmark() {
  const ui = useStore((s) => s.cfg!.ui);
  return (
    <div className="absolute a-down" style={{ left: LEFT, top: 30 }}>
      {ui.logo ? (
        <img src={ui.logo} alt="" className="h-[44px] object-contain" />
      ) : (
        <div className="flex items-end gap-3">
          <span className="display text-[40px] italic tracking-[.03em] text-white text-shadow leading-none">{ui.serverName || 'NAYZEEE'}</span>
          {ui.tagline && <span className="micro text-[9px] text-fg-3 mb-[5px] tracking-[.3em]">{ui.tagline}</span>}
        </div>
      )}
    </div>
  );
}

const CAM_ICON: Record<string, JSX.Element> = {
  squad: <Users2 size={14} />, duo: <Heart size={14} />, body: <Shirt size={14} />, face: <ScanFace size={14} />,
};

function CameraSwitch() {
  const cfg = useStore((s) => s.cfg)!;
  const camera = useStore((s) => s.camera);
  const setCamera = useStore((s) => s.setCamera);
  const partner = useStore((s) => s.squad.links.some((l) => l.type === 'couple' && l.visible));
  const modes = cfg.cameraModes?.length ? cfg.cameraModes : ['squad', 'duo', 'body', 'face'];
  return (
    <div className="flex flex-col items-center gap-2 a-up">
      <div className="flex items-center gap-2 micro text-[9px] text-fg-3"><Camera size={11} />{t('camera')}<Kbd className="!h-[16px] !text-[9px] ml-1">Tab</Kbd></div>
      <div className="glass-dark rounded-full p-[4px] flex gap-[2px]" style={{ background: 'linear-gradient(180deg, rgba(16,18,20,.82), rgba(8,9,10,.78))' }}>
        {modes.map((m) => {
          const disabled = m === 'duo' && !partner;
          const on = m === camera;
          return (
            <button key={m} disabled={disabled}
              onMouseEnter={() => !disabled && cue('hover')}
              onClick={() => setCamera(m)}
              className={cx('h-[34px] px-4 rounded-full flex items-center gap-2 label text-[12px] transition-all duration-200',
                on ? 'bg-accent text-black shadow-[0_0_18px_-4px_rgb(var(--accent))]' : 'text-fg-2 hover:text-fg hover:bg-white/[.06]',
                disabled && '!text-fg-4 cursor-not-allowed hover:!bg-transparent')}>
              {CAM_ICON[m]}{t(`cam_${m}`)}
            </button>
          );
        })}
      </div>
    </div>
  );
}

function KeyHints() {
  const keys = useStore((s) => s.cfg!.ui.keys) || {};
  const items: [string, string][] = [
    [keys.deploy || 'Enter', t('key_deploy')],
    [keys.switch || 'Q / E', t('key_switch')],
    [keys.camera || 'Tab', t('key_camera')],
    [keys.customize || 'C', t('key_customize')],
    [keys.back || 'Esc', t('key_back')],
  ];
  return (
    <div className="flex items-center gap-5 a-fade">
      {items.map(([k, l]) => (
        <span key={l} className="flex items-center gap-2 micro text-[9px] text-fg-3">
          <Kbd className="!h-[18px] !text-[9px]">{k}</Kbd>{l}
        </span>
      ))}
    </div>
  );
}

function Deploy() {
  const char = useChar();
  const selected = useStore((s) => s.selected);
  const busy = useStore((s) => s.busy.on);
  const modal = useStore((s) => s.modal);
  const [sent, setSent] = useState(false);
  useEffect(() => { if (!busy) setSent(false); }, [busy]);
  const disabled = !char || !!char.disabled || !!char.locked;
  return (
    <HoldButton
      label={t('deploy')}
      sub={char ? `${t('deploy_sub')} // ${char.name}` : t('create_character')}
      disabled={disabled}
      busy={sent && busy}
      hotkey={!modal}
      onComplete={() => { setSent(true); post('sound', { name: 'deploy' }); post('play', { slot: selected }); }}
    />
  );
}

export default function Lobby() {
  const section = useStore((s) => s.section);
  const setSection = useStore((s) => s.setSection);
  const selectSlot = useStore((s) => s.selectSlot);
  const setCamera = useStore((s) => s.setCamera);
  const cfg = useStore((s) => s.cfg)!;
  const rows = useRows();
  const [squadTab, setSquadTab] = useState<SquadTab>('linked');

  const openSquad = (tab: SquadTab = 'linked') => { setSquadTab(tab); setSection('squad'); };

  useEffect(() => { cue('whoosh'); }, [section]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (isTyping() || useStore.getState().modal) return;
      const st = useStore.getState();
      const k = e.key.toLowerCase();
      if (k === 'q' || k === 'e' || k === 'arrowleft' || k === 'arrowright' || k === 'arrowup' || k === 'arrowdown') {
        const list = rows.filter((r) => r.kind !== 'locked');
        if (!list.length) return;
        const i = Math.max(0, list.findIndex((r) => r.slot === st.selected));
        const dir = k === 'q' || k === 'arrowleft' || k === 'arrowup' ? -1 : 1;
        const next = list[(i + dir + list.length) % list.length];
        if (next) { e.preventDefault(); selectSlot(next.slot); post('sound', { name: 'nav' }); }
      } else if (k === 'tab') {
        e.preventDefault();
        const partner = st.squad.links.some((l) => l.type === 'couple' && l.visible);
        const modes = (cfg.cameraModes?.length ? cfg.cameraModes : ['squad', 'duo', 'body', 'face']).filter((m) => m !== 'duo' || partner);
        const i = modes.indexOf(st.camera);
        setCamera(modes[(i + (e.shiftKey ? -1 : 1) + modes.length) % modes.length]);
      } else if (k === 'c') {
        setSection(st.section === 'customize' ? 'characters' : 'customize');
      } else if (k === 'l') {
        setSection(st.section === 'lobby' ? 'characters' : 'lobby');
      } else if (k === 'escape' && st.section !== 'characters') {
        cue('back'); post('sound', { name: 'back' });
        setSection('characters');
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [rows, cfg]);

  return (
    <div className="absolute inset-0">
      {/* edge-only shading so text reads over any scene; centre stays clear */}
      <div className="absolute inset-0 pointer-events-none" style={{
        background: 'linear-gradient(90deg, rgba(4,5,6,.62) 0%, rgba(4,5,6,.28) 22%, rgba(4,5,6,0) 36%, rgba(4,5,6,0) 70%, rgba(4,5,6,.38) 100%), linear-gradient(0deg, rgba(4,5,6,.5) 0%, rgba(4,5,6,0) 18%)',
      }} />
      <Rail />
      <Wordmark />

      {/* left column */}
      <div className="absolute flex flex-col" style={{ left: LEFT, top: 104, width: COL_W, bottom: 150 }}>
        {section === 'lobby' ? <Themes key="lobby" />
          : section === 'squad' ? <Squad key="squad" tab={squadTab} setTab={setSquadTab} />
            : <Characters key="chars" />}
      </div>
      <div className="absolute a-up" style={{ left: LEFT, width: COL_W, bottom: 64 }}>
        <Deploy />
      </div>
      <div className="absolute" style={{ left: LEFT, bottom: 26 }}>
        <KeyHints />
      </div>

      {/* top right */}
      <div className="absolute right-9 top-[26px]">
        <StatusPill onOpenSquad={openSquad} />
      </div>
      <div className="absolute right-9" style={{ top: 100, bottom: 150 }}>
        {section === 'customize'
          ? <div className="h-full" style={{ width: COL_W }}><Customize onClose={() => setSection('characters')} /></div>
          : <Roster onOpenSquad={openSquad} />}
      </div>

      {/* bottom centre: camera */}
      <div className="absolute left-1/2 -translate-x-1/2 bottom-[34px]">
        <CameraSwitch />
      </div>

      {/* bottom right: mood */}
      {section !== 'lobby' && cfg.scenePick !== false && cfg.moods?.length > 0 && (
        <div className="absolute right-9 bottom-[34px] a-up">
          <MoodChips />
        </div>
      )}
    </div>
  );
}
