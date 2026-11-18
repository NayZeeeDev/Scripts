import { ChevronsRight, LogOut, Palette, Settings2, Shirt, Users } from 'lucide-react';
import type { ReactNode } from 'react';
import { useStore } from '../../lib/store';
import { cue } from '../../lib/audio';
import { t } from '../../i18n';
import { cx } from '../../components/ui';
import type { Section } from '../../lib/types';

export const RAIL_W = 84;

function Item({ icon, label, active, onClick, badge, kbd }: { icon: ReactNode; label: string; active?: boolean; onClick: () => void; badge?: number; kbd?: string }) {
  return (
    <button
      onMouseEnter={() => cue('hover')}
      onClick={() => { cue('click'); onClick(); }}
      className="group relative w-full h-[54px] grid place-items-center"
    >
      <span className={cx(
        'absolute left-0 top-1/2 -translate-y-1/2 w-[3px] rounded-r-[2px] bg-accent transition-all duration-300 ease-out',
        active ? 'h-[30px] opacity-100 shadow-[0_0_14px_rgb(var(--accent))]' : 'h-0 opacity-0',
      )} />
      <span className={cx(
        'grid place-items-center w-[44px] h-[44px] rounded-[10px] transition-all duration-200',
        active ? 'text-accent-hi bg-gradient-to-br from-accent/25 to-accent/5 shadow-[inset_0_1px_0_rgba(255,255,255,.08)]' : 'text-fg-3 group-hover:text-fg group-hover:bg-white/[.05]',
      )}>
        {icon}
      </span>
      {!!badge && (
        <span className="absolute top-[7px] right-[17px] min-w-[16px] h-[16px] px-1 rounded-full bg-accent text-black text-[9px] font-mono font-bold grid place-items-center shadow-[0_0_10px_rgb(var(--accent)/.8)]">{badge}</span>
      )}
      {/* tooltip */}
      <span className="pointer-events-none absolute left-[78px] top-1/2 -translate-y-1/2 -translate-x-1 opacity-0 group-hover:opacity-100 group-hover:translate-x-0 transition-all duration-200 z-50">
        <span className="glass-dark flex items-center gap-2 rounded-[4px] px-3 h-[30px] whitespace-nowrap label text-[12px] text-fg">
          {label}{kbd && <span className="kbd !h-[16px] !min-w-[16px] !text-[9px]">{kbd}</span>}
        </span>
      </span>
    </button>
  );
}

export default function Rail() {
  const section = useStore((s) => s.section);
  const setSection = useStore((s) => s.setSection);
  const setModal = useStore((s) => s.setModal);
  const slots = useStore((s) => s.lobby?.slots);
  const incoming = useStore((s) => s.squad.incoming.length + s.squad.links.filter((l) => l.pendingType && !l.pendingByMe).length);
  const squadOn = useStore((s) => s.cfg?.squad?.enabled !== false);
  const used = slots?.used ?? 0;
  const total = slots?.total ?? 0;
  const pct = total ? Math.min(1, used / total) : 0;

  const go = (s: Section) => setSection(section === s && s !== 'characters' ? 'characters' : s);
  const R = 21;
  const C = 2 * Math.PI * R;

  return (
    <div className="absolute left-0 top-0 bottom-0 a-left z-20" style={{ width: RAIL_W }}>
      <div className="absolute inset-0" style={{
        background: 'linear-gradient(90deg, rgba(8,9,10,.86) 0%, rgba(10,11,12,.72) 100%)',
        boxShadow: 'inset -1px 0 0 rgba(255,255,255,.06), 1px 0 0 rgba(0,0,0,.3)',
      }} />
      <div className="relative h-full flex flex-col items-center pt-7 pb-6">
        {/* slots ring (MW4 LVL badge) */}
        <div className="relative w-[52px] h-[52px] grid place-items-center">
          <svg width="52" height="52" className="absolute inset-0 -rotate-90">
            <circle cx="26" cy="26" r={R} fill="rgba(0,0,0,.35)" stroke="rgba(255,255,255,.1)" strokeWidth="2" />
            <circle cx="26" cy="26" r={R} fill="none" strokeWidth="2" strokeLinecap="round"
              style={{ stroke: 'rgb(var(--accent))', strokeDasharray: C, strokeDashoffset: C * (1 - pct), transition: 'stroke-dashoffset .6s ease-out' }} />
          </svg>
          <span className="display text-[19px] text-fg leading-none">{used}<span className="text-fg-3 text-[13px]">/{total}</span></span>
          <span className="absolute -bottom-[1px] right-[3px] w-[8px] h-[8px] rounded-full bg-ok border-2 border-ink" />
        </div>
        <div className="micro text-[8px] text-fg-3 mt-2">{t('rail_slots')}</div>

        <div className="w-8 h-px bg-white/10 my-6" />

        <div className="w-full flex flex-col gap-1">
          <Item icon={<ChevronsRight size={22} strokeWidth={2} />} label={t('rail_characters')} active={section === 'characters'} onClick={() => go('characters')} />
          <Item icon={<Palette size={20} strokeWidth={1.8} />} label={t('rail_lobby')} kbd="L" active={section === 'lobby'} onClick={() => go('lobby')} />
          <Item icon={<Shirt size={20} strokeWidth={1.8} />} label={t('rail_customize')} kbd="C" active={section === 'customize'} onClick={() => go('customize')} />
          {squadOn && <Item icon={<Users size={20} strokeWidth={1.8} />} label={t('rail_squad')} active={section === 'squad'} badge={incoming} onClick={() => go('squad')} />}
        </div>

        <div className="flex-1" />
        <Item icon={<Settings2 size={20} strokeWidth={1.8} />} label={t('rail_settings')} onClick={() => setModal({ kind: 'settings' })} />
        <Item icon={<LogOut size={19} strokeWidth={1.8} />} label={t('rail_quit')} onClick={() => setModal({ kind: 'quit' })} />
      </div>
    </div>
  );
}
