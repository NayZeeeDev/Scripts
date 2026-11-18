import { Bell, Crown, EyeOff, Heart, Plus, Settings2, Users, Volume2, VolumeX } from 'lucide-react';
import { useStore, useChar } from '../../lib/store';
import { cue } from '../../lib/audio';
import { t } from '../../i18n';
import { Avatar, cx, Dot, IconBtn, SectionHead } from '../../components/ui';

export function StatusPill({ onOpenSquad }: { onOpenSquad: (tab?: 'linked' | 'requests' | 'find') => void }) {
  const cfg = useStore((s) => s.cfg)!;
  const squad = useStore((s) => s.squad);
  const online = useStore((s) => s.lobby?.online ?? 0);
  const muted = useStore((s) => s.settings.muted);
  const setSettings = useStore((s) => s.setSettings);
  const setModal = useStore((s) => s.setModal);
  const links = [...squad.links].sort((a, b) => a.slot - b.slot);
  const reqs = squad.incoming.length + squad.links.filter((l) => l.pendingType && !l.pendingByMe).length;
  const squadOn = cfg.squad?.enabled !== false;

  return (
    <div className="glass-dark rounded-full h-[48px] pl-2 pr-2 flex items-center gap-1 a-down shadow-[0_10px_30px_-12px_rgba(0,0,0,.7)]"
      style={{ background: 'linear-gradient(180deg, rgba(18,20,22,.84), rgba(9,10,11,.8))' }}>
      {squadOn && (
        <>
          <button
            onMouseEnter={() => cue('hover')}
            onClick={() => { cue('click'); onOpenSquad(links.length ? 'linked' : 'find'); }}
            className="flex items-center h-[38px] pl-1 pr-2 rounded-full hover:bg-white/[.05] transition-colors"
          >
            <span className="grid place-items-center w-[26px] h-[26px] text-fg-2"><Plus size={16} /></span>
            <span className="flex -space-x-[9px] ml-1">
              {links.length === 0 && <span className="micro text-[10px] text-fg-3 pl-2 pr-1">{t('invite_player')}</span>}
              {links.map((l) => (
                <span key={l.id} className="relative">
                  <Avatar name={l.other.name} size={30} ring={l.type === 'couple' ? 'love' : null}
                    className={cx('border-2 border-[#0c0d0e]', !l.visible && 'opacity-40')} />
                  {l.type === 'couple' && <Heart size={10} className="absolute -bottom-[2px] -right-[1px] text-love fill-love drop-shadow" />}
                </span>
              ))}
            </span>
          </button>
          <span className="w-px h-5 bg-white/10 mx-1" />
        </>
      )}
      {cfg.ui?.showOnline !== false && (
        <div className="flex items-center gap-[7px] px-3 h-[38px] text-fg-2" title={t('online_players')}>
          <Users size={17} />
          <span className="display text-[19px] text-fg leading-none">{online}</span>
        </div>
      )}
      {squadOn && (
        <IconBtn title={t('notifications')} badge={reqs} onClick={() => onOpenSquad('requests')}>
          <Bell size={17} />
        </IconBtn>
      )}
      <IconBtn title={muted ? t('unmute') : t('mute')} active={muted} onClick={() => setSettings({ muted: !muted })}>
        {muted ? <VolumeX size={17} /> : <Volume2 size={17} />}
      </IconBtn>
      <IconBtn title={t('settings')} onClick={() => setModal({ kind: 'settings' })}>
        <Settings2 size={17} />
      </IconBtn>
    </div>
  );
}

/** MW4 "PARTY" roster under the pill */
export function Roster({ onOpenSquad }: { onOpenSquad: (tab?: 'linked' | 'requests' | 'find') => void }) {
  const cfg = useStore((s) => s.cfg)!;
  const squad = useStore((s) => s.squad);
  const char = useChar();
  if (cfg.squad?.enabled === false || !char) return null;
  const links = [...squad.links].sort((a, b) => a.slot - b.slot);
  const max = cfg.squad?.maxLinks ?? 3;

  return (
    <div className="w-[360px] a-right">
      <SectionHead code="SYSTEM_ONLINE_C21" title={t('party')} right={`${links.length + 1}/${max + 1}`} />
      <div className="mt-[10px] flex flex-col gap-[3px]">
        {/* self */}
        <div className="relative h-[34px] flex items-center gap-3 pl-3 pr-3 overflow-hidden"
          style={{ background: 'linear-gradient(90deg, rgb(var(--accent) / .55), rgb(var(--accent) / .18) 70%, rgb(var(--accent) / .08))', boxShadow: 'inset 0 0 0 1px rgb(var(--accent) / .55)' }}>
          <span className="micro text-[10px] text-white/80 w-[18px]">P1</span>
          <span className="w-[5px] h-[5px] bg-white rounded-full" />
          <span className="flex-1 truncate font-mono text-[13px] text-white tracking-[.02em]">{char.name}</span>
          <Crown size={14} className="text-white/90" />
        </div>
        {links.map((l) => (
          <button key={l.id} onClick={() => { cue('click'); onOpenSquad('linked'); }} onMouseEnter={() => cue('hover')}
            className="h-[32px] flex items-center gap-3 pl-3 pr-3 bg-black/35 hover:bg-white/[.06] border border-white/[.04] transition-colors text-left">
            <span className="micro text-[10px] text-fg-3 w-[18px]">P{l.slot}</span>
            <Dot online={l.other.online} />
            <span className={cx('flex-1 truncate font-mono text-[13px] tracking-[.02em]', l.visible ? 'text-fg' : 'text-fg-3')}>{l.other.name}</span>
            {!l.visible && <EyeOff size={13} className="text-fg-3" />}
            {l.type === 'couple' ? <Heart size={13} className="text-love fill-love" /> : <Users size={13} className="text-fg-3" />}
          </button>
        ))}
        {links.length < max && (
          <button onClick={() => { cue('click'); onOpenSquad('find'); }} onMouseEnter={() => cue('hover')}
            className="h-[32px] flex items-center gap-3 px-3 border border-dashed border-white/10 text-fg-3 hover:text-fg hover:border-white/25 transition-colors">
            <Plus size={14} /><span className="label text-[11px]">{t('invite_player')}</span>
          </button>
        )}
      </div>
    </div>
  );
}
