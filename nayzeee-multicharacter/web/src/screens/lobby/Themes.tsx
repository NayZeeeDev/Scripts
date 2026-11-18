import { useState, type CSSProperties } from 'react';
import { Check } from 'lucide-react';
import { useStore, useChar } from '../../lib/store';
import { post } from '../../lib/nui';
import { cue } from '../../lib/audio';
import { Icon } from '../../lib/icons';
import { t } from '../../i18n';
import { cx, Micro, SectionHead } from '../../components/ui';
import type { ThemeDef } from '../../lib/types';

export function themeArt(p?: string[]): CSSProperties {
  const [a = '#3fe0ff', b = '#2a3340', c = '#0b0d10'] = p || [];
  return {
    background: [
      'repeating-linear-gradient(120deg, rgba(255,255,255,.045) 0 1px, transparent 1px 14px)',
      `linear-gradient(180deg, transparent 52%, ${c}ee 100%)`,
      `radial-gradient(80% 70% at 82% 18%, ${a}d0 0%, ${a}00 62%)`,
      `radial-gradient(70% 60% at 10% 100%, ${b}cc 0%, ${b}00 70%)`,
      `linear-gradient(155deg, ${b} 0%, ${c} 78%)`,
    ].join(','),
  };
}

export async function savePref(slot: number, key: string, value: unknown) {
  const r = await post<{ ok: boolean; msg?: string }>('setPref', { slot, key, value });
  if (r && r.ok === false) {
    cue('error');
    if (r.msg) useStore.getState().toast('error', r.msg);
    return false;
  }
  return true;
}

function ThemeCard({ th, active, onHover, onPick }: { th: ThemeDef; active: boolean; onHover: () => void; onPick: () => void }) {
  return (
    <button
      onMouseEnter={() => { cue('hover'); onHover(); }}
      onClick={onPick}
      className={cx('group relative h-[98px] overflow-hidden cut cut-sm text-left lift', active ? 'accent-glow' : 'ring-1 ring-white/[.07] hover:ring-white/25')}
      style={themeArt(th.palette as string[])}
    >
      {/* horizon + geometry */}
      <span className="absolute left-0 right-0 top-[58%] h-px bg-white/15" />
      <span className="absolute -right-3 -top-2 text-white/[.16] group-hover:text-white/25 transition-colors">
        <Icon name={th.icon} size={68} strokeWidth={1.1} />
      </span>
      <span className="absolute left-[9px] top-[8px] micro text-[7px] px-[5px] py-[2px] bg-black/45 text-white/80">{th.category && t(`cat_${th.category}`)}</span>
      {active && (
        <span className="absolute right-[7px] top-[7px] w-[18px] h-[18px] rounded-full bg-accent grid place-items-center shadow-[0_0_10px_rgb(var(--accent))]">
          <Check size={12} className="text-black" strokeWidth={3} />
        </span>
      )}
      <span className="absolute left-[9px] right-2 bottom-[8px] display text-[15px] leading-[1] text-white drop-shadow-[0_1px_2px_rgba(0,0,0,.8)]">
        {th.label}
      </span>
    </button>
  );
}

export function MoodChips({ size = 34, showLabel = true, align = 'end' }: { size?: number; showLabel?: boolean; align?: 'start' | 'end' }) {
  const cfg = useStore((s) => s.cfg)!;
  const mood = useStore((s) => s.lobby?.mood);
  const theme = useStore((s) => s.lobby?.theme);
  const selected = useStore((s) => s.selected);
  const char = useChar();
  const th = cfg.themes.find((x) => x.id === theme);
  const moods = th?.moods?.length ? cfg.moods.filter((m) => th.moods!.includes(m.id)) : cfg.moods;
  const [hover, setHover] = useState<string | null>(null);
  const shown = cfg.moods.find((m) => m.id === (hover || mood));

  const pick = async (id: string) => {
    if (!char || id === mood) return;
    cue('click');
    const st = useStore.getState();
    if (st.lobby) useStore.setState({ lobby: { ...st.lobby, mood: id } });
    await savePref(selected, 'mood', id);
  };

  return (
    <div>
      {showLabel && (
        <div className="flex items-baseline gap-3 mb-[10px] justify-end">
          <Micro className="text-[9px]">{t('mood')}</Micro>
          <span className="display text-[20px] text-fg">{shown?.label || '—'}</span>
        </div>
      )}
      <div className={cx('flex gap-[12px]', align === 'end' ? 'justify-end' : 'justify-start pl-1')}>
        {moods.map((m) => {
          const [a = '#fff', b = '#888'] = m.swatch || [];
          const on = m.id === mood;
          return (
            <button key={m.id} title={m.label}
              onMouseEnter={() => { cue('hover'); setHover(m.id); }} onMouseLeave={() => setHover(null)}
              onClick={() => pick(m.id)}
              className={cx('relative rounded-full transition-all duration-200', on ? 'scale-110' : 'opacity-75 hover:opacity-100 hover:scale-105')}
              style={{ width: size, height: size }}
            >
              <span className="absolute inset-0 rounded-full" style={{ background: `linear-gradient(135deg, ${a} 0%, ${b} 100%)`, boxShadow: 'inset 0 1px 1px rgba(255,255,255,.4), inset 0 -2px 4px rgba(0,0,0,.35)' }} />
              <span className={cx('absolute -inset-[4px] rounded-full border transition-colors', on ? 'border-accent shadow-[0_0_12px_rgb(var(--accent)/.7)]' : 'border-white/0')} />
              <span className="absolute inset-0 grid place-items-center text-black/55"><Icon name={m.icon} size={size * 0.42} strokeWidth={2} /></span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

export default function Themes() {
  const cfg = useStore((s) => s.cfg)!;
  const active = useStore((s) => s.lobby?.theme);
  const selected = useStore((s) => s.selected);
  const char = useChar();
  const [hover, setHover] = useState<string | null>(null);
  const themes = cfg.themes;
  const info = themes.find((x) => x.id === (hover || active)) || themes[0];
  const locked = cfg.playerPick === false;

  const pick = async (id: string) => {
    if (!char || locked) { cue('error'); return; }
    if (id === active) return;
    cue('confirm');
    post('sound', { name: 'select' });
    const st = useStore.getState();
    if (st.lobby) useStore.setState({ lobby: { ...st.lobby, theme: id } });
    await savePref(selected, 'theme', id);
  };

  return (
    <div className="flex flex-col h-full min-h-0 a-left">
      <div>
        <Micro className="text-[9px] text-accent-hi/70">SCENE_SELECT_C02</Micro>
        <div className="display text-[44px] text-fg mt-1">{t('lobby_title')}</div>
      </div>
      <SectionHead className="mt-4" title={t('lobby_scene')} right={t('scenes_count', themes.length)} />
      <div className="grid grid-cols-3 gap-[7px] mt-3" onMouseLeave={() => setHover(null)}>
        {themes.map((th) => (
          <ThemeCard key={th.id} th={th} active={th.id === active} onHover={() => setHover(th.id)} onPick={() => pick(th.id)} />
        ))}
      </div>
      {info && (
        <div key={info.id} className="glass-dark mt-[10px] px-4 py-3 flex gap-4 items-center a-fade">
          <span className="w-[42px] h-[42px] shrink-0 grid place-items-center cut cut-sm" style={themeArt(info.palette as string[])}>
            <Icon name={info.icon} size={20} className="text-white" />
          </span>
          <div className="min-w-0">
            <div className="flex items-center gap-2">
              <span className="display text-[20px] text-fg truncate">{info.label}</span>
              {info.id === active && <span className="micro text-[8px] px-[5px] py-[2px] bg-accent/20 text-accent-hi">{t('theme_active')}</span>}
            </div>
            <div className="text-[13px] text-fg-2 leading-snug mt-[2px] line-clamp-2">{info.description}</div>
          </div>
        </div>
      )}
      <SectionHead className="mt-6" title={t('mood')} />
      <div className="mt-4">
        <MoodChips size={38} showLabel={false} align="start" />
      </div>
    </div>
  );
}
