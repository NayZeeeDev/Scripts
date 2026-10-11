(() => {
  const NH = window.NH;

  const svg = (inner, vb = '0 0 24 24') => NH.svgUrl(`<svg xmlns='http://www.w3.org/2000/svg' viewBox='${vb}'>${inner}</svg>`);

  // Small shapes used for particles + corner decorations
  const SHAPE = {
    snow: c => `<g stroke='${c}' stroke-width='2' stroke-linecap='round'><path d='M12 2v20M3.3 7l17.4 10M3.3 17L20.7 7'/><path d='M9.5 4L12 6l2.5-2M9.5 20l2.5-2 2.5 2'/></g>`,
    flake: c => `<circle cx='12' cy='12' r='6' fill='${c}'/>`,
    leaf: c => `<path d='M4 20C4 9 10 4 21 3c-1 11-6 17-17 17z' fill='${c}'/><path d='M4 20L14 10' stroke='rgba(0,0,0,.25)' stroke-width='1.5'/>`,
    heart: c => `<path d='M12 21S3 15.5 3 9a4.8 4.8 0 0 1 9-2.4A4.8 4.8 0 0 1 21 9c0 6.5-9 12-9 12z' fill='${c}'/>`,
    petal: c => `<path d='M12 3c4 4 4 10 0 18-4-8-4-14 0-18z' fill='${c}'/>`,
    clover: c => `<g fill='${c}'><circle cx='8.5' cy='8.5' r='4'/><circle cx='15.5' cy='8.5' r='4'/><circle cx='12' cy='14' r='4'/></g><path d='M12 15v7' stroke='${c}' stroke-width='2'/>`,
    confetti: c => `<rect x='8' y='4' width='8' height='16' rx='1.5' fill='${c}'/>`,
    spark: c => `<path d='M12 1l2.6 8.4L23 12l-8.4 2.6L12 23l-2.6-8.4L1 12l8.4-2.6z' fill='${c}'/>`,
    bat: c => `<path d='M12 9c1-2 2-2 2-2l.5 2C16 7 19 6 23 7c-2 1-3 3-3 5-1.5-1-3-1-4 .5-.8-1-1.8-1.5-2.5-1L12 14l-1.5-2.5c-.7-.5-1.7 0-2.5 1-1-1.5-2.5-1.5-4-.5 0-2-1-4-3-5 4-1 7 0 8.5 2L10 7s1 0 2 2z' fill='${c}'/>`,
    bubble: c => `<circle cx='12' cy='12' r='8' fill='none' stroke='${c}' stroke-width='2'/><circle cx='9' cy='9' r='2' fill='${c}'/>`,
    hat: () => `<path d='M3 18c2-9 7-14 15-13 1 3 0 6-2 8' fill='#e11d2a'/><circle cx='17' cy='14' r='2.6' fill='#fff'/><rect x='2' y='16.5' width='16' height='5' rx='2.5' fill='#fff'/>`,
    pumpkin: () => `<ellipse cx='12' cy='14' rx='9' ry='7.5' fill='#f97316'/><path d='M12 7c0-2 1-4 3-4' stroke='#16a34a' stroke-width='2' fill='none'/><path d='M8.5 12l1.5 1.5L8.5 15M15.5 12L14 13.5l1.5 1.5' stroke='#291403' stroke-width='1.4' fill='none'/><path d='M9 17.5q3 1.6 6 0' stroke='#291403' stroke-width='1.4' fill='none'/>`,
    sun: () => `<circle cx='12' cy='12' r='5' fill='#fbbf24'/><g stroke='#fbbf24' stroke-width='2' stroke-linecap='round'><path d='M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M4.9 19.1L7 17M17 7l2.1-2.1'/></g>`,
    flower: () => `<g fill='#f9a8d4'><circle cx='12' cy='6.5' r='4'/><circle cx='17.2' cy='10.4' r='4'/><circle cx='15.2' cy='16.6' r='4'/><circle cx='8.8' cy='16.6' r='4'/><circle cx='6.8' cy='10.4' r='4'/></g><circle cx='12' cy='12' r='3' fill='#fde047'/>`,
  };
  const enc = c => c;

  NH.SEASONS = {
    default:      { label: 'Default',       dates: '',                 accent: null },
    winter:       { label: 'Winter',        dates: 'Dec – Feb',        accent: '#7dd3fc', a2: '#e0f2fe', p: 'snow',     pc: ['#ffffff', '#dbeafe', '#bae6fd'], deco: 'snow',    anim: 'fall' },
    christmas:    { label: 'Christmas',     dates: 'Dec 1 – 27',       accent: '#ef4444', a2: '#22c55e', p: 'flake',    pc: ['#ffffff', '#f1f5f9'],            deco: 'hat',     anim: 'fall' },
    newyear:      { label: 'New Year',      dates: 'Dec 28 – Jan 3',   accent: '#facc15', a2: '#fde68a', p: 'confetti', pc: ['#facc15', '#f472b6', '#60a5fa', '#34d399'], deco: 'spark', anim: 'confetti' },
    valentine:    { label: 'Valentine',     dates: 'Feb 7 – 15',       accent: '#fb7185', a2: '#f9a8d4', p: 'heart',    pc: ['#fb7185', '#f472b6', '#fda4af'], deco: 'heart',   anim: 'rise' },
    stpatrick:    { label: "St. Patrick's", dates: 'Mar 12 – 18',      accent: '#22c55e', a2: '#facc15', p: 'clover',   pc: ['#22c55e', '#4ade80', '#16a34a'], deco: 'clover',  anim: 'fall' },
    spring:       { label: 'Spring',        dates: 'Mar – May',        accent: '#f9a8d4', a2: '#86efac', p: 'petal',    pc: ['#fbcfe8', '#f9a8d4', '#fce7f3'], deco: 'flower',  anim: 'fall' },
    summer:       { label: 'Summer',        dates: 'Jun – Aug',        accent: '#fbbf24', a2: '#22d3ee', p: 'bubble',   pc: ['#a5f3fc', '#fde68a', '#ffffff'], deco: 'sun',     anim: 'rise' },
    independence: { label: 'Independence',  dates: 'Jul 1 – 5',        accent: '#3b82f6', a2: '#ef4444', p: 'spark',    pc: ['#ef4444', '#ffffff', '#3b82f6'], deco: 'spark',   anim: 'twinkle' },
    autumn:       { label: 'Autumn',        dates: 'Sep – Nov',        accent: '#f97316', a2: '#facc15', p: 'leaf',     pc: ['#f97316', '#ea580c', '#facc15', '#b45309'], deco: 'leaf', anim: 'fall' },
    halloween:    { label: 'Halloween',     dates: 'Oct 15 – Nov 1',   accent: '#fb923c', a2: '#a855f7', p: 'bat',      pc: ['#1c1917', '#3b0764', '#292524'], deco: 'pumpkin', anim: 'fly' },
  };

  NH.seasonForDate = (d = new Date()) => {
    const m = d.getMonth() + 1, day = d.getDate(), md = m * 100 + day;
    if (md >= 1228 || md <= 103) return 'newyear';
    if (md >= 1201) return 'christmas';
    if (md >= 207 && md <= 215) return 'valentine';
    if (md >= 312 && md <= 318) return 'stpatrick';
    if (md >= 701 && md <= 705) return 'independence';
    if (md >= 1015 && md <= 1101) return 'halloween';
    if (m === 12 || m <= 2) return 'winter';
    if (m <= 5) return 'spring';
    if (m <= 8) return 'summer';
    return 'autumn';
  };

  NH.resolveSeason = (s) => (s === 'auto' ? NH.seasonForDate() : (NH.SEASONS[s] ? s : 'default'));

  const decoUrl = (name, season) => {
    if (SHAPE[name] && ['hat', 'pumpkin', 'sun', 'flower'].includes(name)) return svg(SHAPE[name]());
    const color = enc(name === 'snow' ? '#ffffff' : season.accent || '#ffffff');
    return svg(SHAPE[name](color));
  };

  NH.seasonSwatch = (key) => {
    const s = NH.SEASONS[key];
    if (!s.accent) return `<span class="sw-dot" style="background:var(--base-accent)"></span>`;
    return `<span class="sw-dot" style="background:${s.accent}"></span><span class="sw-dot" style="background:${s.a2}"></span><span class="sw-ico" style="background-image:${decoUrl(s.deco, s)}"></span>`;
  };

  let current = null;
  const fx = () => document.getElementById('fx');

  function spawnParticles(key, season) {
    const layer = fx();
    layer.innerHTML = '';
    layer.className = '';
    if (!season.p) return;
    layer.className = 'fx-' + season.anim;
    const count = season.anim === 'fly' ? 5 : season.anim === 'twinkle' ? 10 : 14;
    let html = '';
    for (let i = 0; i < count; i++) {
      const c = enc(season.pc[i % season.pc.length]);
      const size = (season.anim === 'fly' ? 22 : 9) + Math.round(Math.random() * (season.anim === 'fly' ? 14 : 9));
      const dur = (season.anim === 'fly' ? 16 : season.anim === 'twinkle' ? 3 : 11) + Math.random() * 9;
      const delay = -Math.random() * dur;
      const x = Math.round(Math.random() * 100);
      const y = Math.round(10 + Math.random() * 70);
      const sway = Math.round(20 + Math.random() * 60) * (Math.random() > 0.5 ? 1 : -1);
      html += `<i style="--x:${x}vw;--y:${y}vh;--s:${size}px;--d:${dur.toFixed(1)}s;--dl:${delay.toFixed(1)}s;--sw:${sway}px;--r:${Math.round(Math.random() * 360)}deg;background-image:${svg(SHAPE[season.p](c))}"></i>`;
    }
    layer.innerHTML = html;
  }

  NH.applySeason = (cfg) => {
    const key = NH.resolveSeason(cfg.season);
    const season = NH.SEASONS[key];
    const root = document.documentElement;
    const accent = (cfg.seasonAccent && season.accent) || cfg.accent;
    root.style.setProperty('--base-accent', cfg.accent);
    root.style.setProperty('--accent', accent);
    root.style.setProperty('--accent-rgb', NH.hexToRgb(accent));
    root.style.setProperty('--accent2', (cfg.seasonAccent && season.a2) || accent);
    document.body.dataset.season = key;
    document.body.classList.toggle('decor', !!(cfg.decor && season.deco));
    root.style.setProperty('--deco', season.deco ? decoUrl(season.deco, season) : 'none');
    const sig = key + (cfg.particles ? '1' : '0');
    if (sig !== current) {
      current = sig;
      if (cfg.particles) spawnParticles(key, season);
      else { fx().innerHTML = ''; fx().className = ''; }
    }
  };
})();
