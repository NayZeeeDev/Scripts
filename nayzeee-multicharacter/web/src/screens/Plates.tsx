import { Heart, PawPrint, Users } from 'lucide-react';
import { useStore } from '../lib/store';
import { useStage } from '../App';
import { cx } from '../components/ui';
import type { Plate } from '../lib/types';

function Tag({ p }: { p: Plate }) {
  if (p.badge === 'pet') {
    return (
      <div className="flex items-center gap-[6px] px-2 h-[22px] rounded-full bg-black/55 border border-white/10">
        <PawPrint size={11} className="text-fg-2" />
        <span className="font-display font-semibold text-[13px] uppercase tracking-[.06em] text-fg">{p.name}</span>
      </div>
    );
  }
  const self = p.badge === 'self';
  const partner = p.badge === 'partner';
  return (
    <div className="flex flex-col items-center">
      <div className={cx('flex items-center gap-[7px] pl-[9px] pr-[11px] h-[28px] border',
        self ? 'bg-gradient-to-r from-accent/70 to-accent/35 border-accent/80 shadow-[0_0_18px_-4px_rgb(var(--accent))]'
          : 'bg-black/60 border-white/[.12]')}
        style={{ clipPath: 'polygon(0 0, 100% 0, 100% calc(100% - 7px), calc(100% - 7px) 100%, 0 100%)' }}>
        {p.online != null && !self && (
          <span className={cx('w-[6px] h-[6px] rounded-full', p.online ? 'bg-ok shadow-[0_0_6px_rgba(61,220,132,.9)]' : 'bg-fg-4')} />
        )}
        {partner && <Heart size={11} className="text-love fill-love" />}
        {p.badge === 'squad' && <Users size={11} className="text-fg-2" />}
        <span className="font-display font-bold text-[16px] uppercase tracking-[.04em] text-white whitespace-nowrap">{p.name}</span>
      </div>
      {p.sub && (
        <div className={cx('micro text-[8px] mt-[3px] px-[6px] py-[2px] whitespace-nowrap', partner ? 'text-love' : 'text-fg-2', 'bg-black/45')}>{p.sub}</div>
      )}
      <span className={cx('w-px h-[10px] mt-[2px]', self ? 'bg-accent' : 'bg-white/30')} />
    </div>
  );
}

export default function Plates() {
  const plates = useStore((s) => s.plates);
  const show = useStore((s) => s.settings.plates && s.cfg?.ui?.nameplates !== false);
  const modal = useStore((s) => s.modal);
  const { W, H } = useStage();
  if (!show || modal) return null;
  return (
    <div className="absolute inset-0 pointer-events-none z-[5]">
      {plates.filter((p) => p.visible).map((p) => (
        <div key={p.key} className="absolute left-0 top-0"
          style={{ transform: `translate3d(${p.x * W}px, ${p.y * H}px, 0) translate(-50%, -100%)`, transition: 'transform 60ms linear' }}>
          <Tag p={p} />
        </div>
      ))}
    </div>
  );
}
