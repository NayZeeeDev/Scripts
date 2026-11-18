import { useEffect, useRef, useState } from 'react';
import { ChevronLeft, ChevronRight, History, House, MapPin, Plane } from 'lucide-react';
import { useStore } from '../lib/store';
import { post } from '../lib/nui';
import { cue } from '../lib/audio';
import { iconFor } from '../lib/icons';
import { t } from '../i18n';
import { cx, HoldButton, isTyping, Micro } from '../components/ui';
import { useStage } from '../App';
import { Steps } from './Create';
import type { SpawnOption } from '../lib/types';

const CARD_W = 236;
const GAP = 14;

function spawnIcon(o: SpawnOption) {
  if (o.icon) return iconFor(o.icon, MapPin);
  if (o.kind === 'last') return History;
  if (o.kind === 'house') return House;
  if (o.kind === 'first') return Plane;
  return MapPin;
}

export default function Spawn() {
  const spawn = useStore((s) => s.spawn)!;
  const { W } = useStage();
  const options = spawn.options;
  const [idx, setIdx] = useState(() => Math.max(0, options.findIndex((o) => o.id === spawn.selected)));
  const [busy, setBusy] = useState(false);
  const hoverT = useRef<number>();
  const cur = options[idx];

  const focus = (i: number, sound = true) => {
    const n = (i + options.length) % options.length;
    if (n === idx) return;
    setIdx(n);
    if (sound) cue('tick');
    window.clearTimeout(hoverT.current);
    hoverT.current = window.setTimeout(() => post('spawnHover', { id: options[n].id }), 140);
  };

  useEffect(() => {
    const k = (e: KeyboardEvent) => {
      if (isTyping()) return;
      const key = e.key.toLowerCase();
      if (key === 'arrowleft' || key === 'q' || key === 'a') { e.preventDefault(); focus(idx - 1); post('sound', { name: 'nav' }); }
      if (key === 'arrowright' || key === 'e' || key === 'd') { e.preventDefault(); focus(idx + 1); post('sound', { name: 'nav' }); }
    };
    window.addEventListener('keydown', k);
    return () => window.removeEventListener('keydown', k);
  }, [idx, options]);

  const confirm = async () => {
    if (!cur || busy) return;
    setBusy(true);
    post('sound', { name: 'deploy' });
    const r = await post<{ ok: boolean }>('spawnConfirm', { id: cur.id });
    if (r && r.ok === false) { setBusy(false); cue('error'); }
  };

  const offset = W / 2 - CARD_W / 2 - idx * (CARD_W + GAP);

  return (
    <div className="absolute inset-0">
      <div className="absolute inset-0 pointer-events-none" style={{
        background: 'linear-gradient(0deg, rgba(4,5,6,.78) 0%, rgba(4,5,6,.35) 24%, rgba(4,5,6,0) 42%), linear-gradient(180deg, rgba(4,5,6,.55) 0%, rgba(4,5,6,0) 18%)',
      }} />

      {/* title */}
      <div className="absolute left-12 top-10 flex items-center gap-4 a-down">
        <div className="w-[52px] h-[52px] grid place-items-center cut accent-block" style={{ ['--cut' as string]: '12px' }}>
          <MapPin size={24} className="text-white" />
        </div>
        <div>
          <div className="display text-[42px] text-white text-shadow leading-none">{t('spawn_title')}</div>
          <div className="micro text-[10px] text-fg-2 mt-[6px]">{t('spawn_sub')}</div>
        </div>
      </div>
      <div className="absolute right-12 top-12 w-[420px] a-down">
        <Steps active={2} />
      </div>

      {/* carousel */}
      <div className="absolute left-0 right-0 bottom-[150px] h-[176px] overflow-visible">
        <div className="absolute top-0 flex items-end gap-[14px]" style={{ transform: `translateX(${offset}px)`, transition: 'transform .38s cubic-bezier(.22,.8,.26,1)' }}>
          {options.map((o, i) => {
            const Ic = spawnIcon(o);
            const on = i === idx;
            const dist = Math.abs(i - idx);
            return (
              <button key={o.id}
                onMouseEnter={() => focus(i)}
                onClick={() => focus(i)}
                className={cx('relative shrink-0 text-left cut overflow-hidden transition-all duration-300 ease-out',
                  on ? 'h-[176px] accent-glow' : 'h-[150px] ring-1 ring-white/[.08] hover:ring-white/25')}
                style={{
                  width: CARD_W, ['--cut' as string]: '16px', opacity: on ? 1 : Math.max(0.35, 0.85 - dist * 0.15),
                  background: on
                    ? 'radial-gradient(100% 80% at 85% 0%, rgb(var(--accent) / .45), transparent 65%), linear-gradient(165deg, rgba(24,28,30,.94), rgba(9,10,11,.94))'
                    : 'radial-gradient(100% 80% at 85% 0%, rgba(255,255,255,.08), transparent 65%), linear-gradient(165deg, rgba(20,23,25,.88), rgba(9,10,11,.88))',
                }}>
                <span className="absolute inset-0" style={{ background: 'repeating-linear-gradient(120deg, rgba(255,255,255,.03) 0 1px, transparent 1px 12px)' }} />
                <span className={cx('absolute right-[-10px] top-[-8px] transition-colors', on ? 'text-white/25' : 'text-white/[.07]')}><Ic size={110} strokeWidth={1} /></span>
                <span className={cx('absolute left-4 top-4 w-[36px] h-[36px] rounded-full grid place-items-center', on ? 'bg-accent text-black' : 'bg-white/[.07] text-fg-2')}>
                  <Ic size={17} />
                </span>
                {o.kind && o.kind !== 'city' && (
                  <span className="absolute right-3 top-3 micro text-[8px] px-[6px] py-[2px] bg-black/50 text-fg-2">{o.kind}</span>
                )}
                <span className="absolute left-4 right-4 bottom-4">
                  <span className={cx('display block truncate', on ? 'text-[26px] text-white' : 'text-[21px] text-fg')}>{o.label}</span>
                  {o.desc && <span className="micro text-[9px] text-fg-3 block mt-[4px] truncate">{o.desc}</span>}
                </span>
              </button>
            );
          })}
        </div>
      </div>

      {/* controls */}
      <div className="absolute left-1/2 -translate-x-1/2 bottom-[44px] flex items-center gap-4 a-up">
        <button onMouseEnter={() => cue('hover')} onClick={() => focus(idx - 1)}
          className="w-[54px] h-[54px] grid place-items-center glass-dark rounded-full text-fg-2 hover:text-white hover:border-white/25 transition-colors">
          <ChevronLeft size={22} />
        </button>
        <div className="w-[440px]">
          <HoldButton label={t('spawn_now')} sub={cur ? `${cur.label} // ${t('spawn_of', String(idx + 1).padStart(2, '0'), String(options.length).padStart(2, '0'))}` : ''} busy={busy} onComplete={confirm} size="md" />
        </div>
        <button onMouseEnter={() => cue('hover')} onClick={() => focus(idx + 1)}
          className="w-[54px] h-[54px] grid place-items-center glass-dark rounded-full text-fg-2 hover:text-white hover:border-white/25 transition-colors">
          <ChevronRight size={22} />
        </button>
      </div>
      <Micro className="absolute left-12 bottom-[34px] text-[9px]">← → {t('key_browse')} · {t('hold')} Enter {t('key_confirm')}</Micro>
    </div>
  );
}
