import { useEffect, useRef, useState } from 'react';
import { useStore } from '../lib/store';
import { post } from '../lib/nui';
import { cue } from '../lib/audio';
import { SocialIcon } from '../lib/icons';
import { t } from '../i18n';
import { cx, Kbd, isTyping } from '../components/ui';
import { useStage } from '../App';

export default function StartScreen() {
  const cfg = useStore((s) => s.cfg)!;
  const d = useStore((s) => s.start) || {};
  const { W, H } = useStage();
  const [leaving, setLeaving] = useState(false);
  const sent = useRef(false);

  const name = d.serverName || cfg.ui.serverName || 'NAYZEEE';
  const tagline = d.tagline || cfg.ui.tagline || '';
  const logo = d.logo || cfg.ui.logo;
  const socials = d.socials || cfg.ui.socials || [];
  const prompt = d.prompt || cfg.start?.prompt;
  const subtitle = d.subtitle || cfg.start?.subtitle;
  const version = d.version || cfg.version;

  const go = () => {
    if (sent.current) return;
    sent.current = true;
    cue('confirm');
    setLeaving(true);
    post('startContinue');
  };

  useEffect(() => {
    const k = (e: KeyboardEvent) => {
      if ((e.key === 'Enter' || e.key === ' ') && !e.repeat && !isTyping()) { e.preventDefault(); go(); }
    };
    window.addEventListener('keydown', k);
    return () => window.removeEventListener('keydown', k);
  }, []);

  // Prompt text: highlight the key word (ENTER) from the config prompt if present
  const renderPrompt = () => {
    if (prompt) {
      const m = /(enter)/i.exec(prompt);
      if (m) {
        const i = m.index;
        return (<>{prompt.slice(0, i)}<Kbd className="mx-[10px] !h-[24px] !text-[11px] !px-2 align-middle">{prompt.slice(i, i + m[0].length).toUpperCase()}</Kbd>{prompt.slice(i + m[0].length)}</>);
      }
      return prompt;
    }
    const [a, b] = t('start_prompt').split('%s');
    return (<>{a}<Kbd className="mx-[10px] !h-[24px] !text-[11px] !px-2 align-middle">{t('start_enter').toUpperCase()}</Kbd>{b}</>);
  };

  // Plate geometry (stage coordinates), centred
  const pw = Math.min(1500, W - 300);
  const ph = Math.min(840, H - 200);
  const px = (W - pw) / 2;
  const py = (H - ph) / 2 + 10;
  const pts = (inset: number) => [
    [px + pw * 0.07 + inset, py + ph * 0.1 + inset],
    [px + pw * 0.71, py + inset],
    [px + pw - inset, py + ph * 0.5],
    [px + pw * 0.86 - inset, py + ph - inset],
    [px + pw * 0.15, py + ph * 0.93 - inset],
    [px + inset, py + ph * 0.44],
  ].map((p) => p.join(',')).join(' ');

  return (
    <div className={cx('absolute inset-0 transition-opacity duration-500', leaving ? 'opacity-0' : 'a-fade')} onClick={go}>
      {/* vignette — transparent centre, dark edges only */}
      <div className="absolute inset-0" style={{ background: 'radial-gradient(ellipse 75% 70% at 50% 50%, rgba(0,0,0,0) 0%, rgba(0,0,0,.25) 55%, rgba(3,4,5,.88) 100%)' }} />

      {/* skewed glass plate */}
      <svg className="absolute inset-0 pointer-events-none" width={W} height={H} viewBox={`0 0 ${W} ${H}`}>
        <defs>
          <linearGradient id="plate" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor="#ffffff" stopOpacity=".13" />
            <stop offset=".45" stopColor="#ffffff" stopOpacity=".05" />
            <stop offset="1" stopColor="#ffffff" stopOpacity=".02" />
          </linearGradient>
          <linearGradient id="plateEdge" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor="#ffffff" stopOpacity=".38" />
            <stop offset=".5" stopColor="#ffffff" stopOpacity=".08" />
            <stop offset="1" style={{ stopColor: 'rgb(var(--accent))', stopOpacity: 0.35 }} />
          </linearGradient>
          <radialGradient id="plateGlow" cx=".5" cy=".5" r=".55">
            <stop offset="0" style={{ stopColor: 'rgb(var(--accent))', stopOpacity: 0.10 }} />
            <stop offset="1" style={{ stopColor: 'rgb(var(--accent))', stopOpacity: 0 }} />
          </radialGradient>
        </defs>
        <polygon points={pts(-26)} fill="#000" fillOpacity=".22" />
        <polygon points={pts(0)} fill="url(#plate)" stroke="url(#plateEdge)" strokeWidth="1.2" />
        <polygon points={pts(0)} fill="url(#plateGlow)" />
        <polygon points={pts(22)} fill="none" stroke="#fff" strokeOpacity=".06" strokeWidth="1" />
      </svg>

      {/* connected as */}
      <div className="absolute micro text-[11px] text-fg-2 a-down" style={{ left: px + pw * 0.12, top: py + ph * 0.13 }}>
        <div className="flex items-center gap-2">
          <span className="w-[6px] h-[6px] rounded-full bg-ok shadow-[0_0_8px_rgba(61,220,132,.9)]" />
          {subtitle && d.playerName
            ? subtitle.replace('%s', '\u0000').split('\u0000').map((part, i) => (i === 0 ? part : <span key={i}><b className="text-fg font-medium">{d.playerName}</b>{part}</span>))
            : <>{t('start_connected', '')}<b className="text-fg font-medium">{d.playerName || '—'}</b></>}
        </div>
        <div className="text-[8px] text-fg-4 mt-[6px] tracking-[.2em]">{t('start_status')}_C{String(new Date().getDate()).padStart(2, '0')}</div>
      </div>

      {/* wordmark */}
      <div className="absolute left-1/2 -translate-x-1/2 text-center a-zoom" style={{ top: H / 2 - 150 }}>
        {logo ? (
          <img src={logo} alt="" className="mx-auto max-h-[180px] max-w-[520px] object-contain drop-shadow-[0_10px_40px_rgba(0,0,0,.6)]" />
        ) : (
          <div className="display text-[150px] leading-[.85] tracking-[.04em] text-white text-shadow" style={{ fontStyle: 'italic' }}>
            {name}
          </div>
        )}
        {tagline && (
          <div className="flex items-center justify-center gap-4 mt-5">
            <span className="h-px w-16 bg-gradient-to-r from-transparent to-white/40" />
            <span className="micro text-[13px] tracking-[.5em] text-fg-2">{tagline}</span>
            <span className="h-px w-16 bg-gradient-to-l from-transparent to-white/40" />
          </div>
        )}
      </div>

      {/* prompt */}
      <div className="absolute left-0 right-0 text-center" style={{ top: H / 2 + 120 }}>
        <div className="a-pulse inline-flex items-center label text-[17px] tracking-[.32em] text-fg text-shadow cursor-pointer">
          {renderPrompt()}
        </div>
      </div>

      {/* socials */}
      {socials.length > 0 && (
        <div className="absolute top-9 right-10 flex gap-2 a-down" onClick={(e) => e.stopPropagation()}>
          {socials.map((s) => (
            <div
              key={s.label}
              title={s.url || s.label}
              onMouseEnter={() => cue('hover')}
              onClick={() => { cue('click'); if (s.url) navigator.clipboard?.writeText(s.url).catch(() => {}); }}
              className="glass-dark w-[42px] h-[42px] rounded-[6px] grid place-items-center text-fg-2 hover:text-fg hover:border-white/20 lift cursor-pointer"
            >
              <SocialIcon name={s.icon} size={17} />
            </div>
          ))}
        </div>
      )}

      {/* footer */}
      <div className="absolute bottom-7 left-10 micro text-[9px] text-fg-4 flex items-center gap-3">
        {version && <span className="text-fg-3">v{version}</span>}
        <span className="w-px h-3 bg-white/15" />
        <span>NZM_LOBBY // {Math.round(W)}x{Math.round(H)}</span>
      </div>
    </div>
  );
}
