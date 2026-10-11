(() => {
  const NH = window.NH;
  const ic = NH.ic;

  // ---- SVG helpers (angles in degrees, 0 = top, clockwise) ----
  const rad = d => (d - 90) * Math.PI / 180;
  const pt = (cx, cy, r, d) => [cx + r * Math.cos(rad(d)), cy + r * Math.sin(rad(d))];
  const f = n => n.toFixed(2);
  const arcD = (cx, cy, r, a0, a1) => {
    const [x0, y0] = pt(cx, cy, r, a0), [x1, y1] = pt(cx, cy, r, a1);
    return `M${f(x0)} ${f(y0)}A${r} ${r} 0 ${a1 - a0 > 180 ? 1 : 0} 1 ${f(x1)} ${f(y1)}`;
  };
  const ticks = (cx, cy, r0, r1, a0, a1, n, cls = 'tk', major = 0, rMajor = r0) => {
    let s = '';
    for (let i = 0; i <= n; i++) {
      const a = a0 + (a1 - a0) * i / n;
      const m = major && i % major === 0;
      const [x0, y0] = pt(cx, cy, m ? rMajor : r0, a), [x1, y1] = pt(cx, cy, r1, a);
      s += `<line class="${cls}${m ? ' mj' : ''}" x1="${f(x0)}" y1="${f(y0)}" x2="${f(x1)}" y2="${f(y1)}"/>`;
    }
    return s;
  };
  const labels = (cx, cy, r, a0, a1, vals, cls = 'lb') => vals.map((v, i) => {
    const [x, y] = pt(cx, cy, r, a0 + (a1 - a0) * i / (vals.length - 1));
    return `<text class="${cls}" x="${f(x)}" y="${f(y)}">${v}</text>`;
  }).join('');
  const prog = (d, k, cls = 'pa') => `<path class="${cls}" d="${d}" pathLength="100" style="--k:var(${k})"/>`;
  const needle = (k, a0, sweep, cx, cy, path) =>
    `<g class="needle" style="--k:var(${k});--a0:${a0}deg;--sw:${sweep}deg;transform-origin:${cx}px ${cy}px"><path d="${path}"/></g>`;
  const steps = (max, n) => Array.from({ length: n + 1 }, (_, i) => Math.round(max * i / n));

  // ---- Styles ----
  const STY = {};

  STY.modern = {
    label: 'Modern Pro',
    html: o => `
      <svg viewBox="0 0 260 214">
        <path class="trk mp" d="${arcD(130, 120, 96, -128, 128)}"/>
        ${prog(arcD(130, 120, 96, -128, 128), '--rpm', 'pa mp grad')}
        ${ticks(130, 120, 108, 114, -128, 128, 4, 'tk mj')}
        ${ticks(130, 120, 110, 113, -128, 128, 16, 'tk')}
        <text class="lb" x="${f(pt(130, 120, 76, -118)[0])}" y="${f(pt(130, 120, 76, -118)[1])}">CHG</text>
        <text class="lb" x="${f(pt(130, 120, 76, -64)[0])}" y="${f(pt(130, 120, 76, -64)[1])}">ECO</text>
        <text class="lb" x="${f(pt(130, 120, 76, 64)[0])}" y="${f(pt(130, 120, 76, 64)[1])}">PWR</text>
      </svg>
      <div class="mp-top"><span class="mp-i">${ic('bolt')}</span></div>
      <div class="ctr mpc"><b class="big" data-r="sp">0</b><span class="gtxt" data-r="gear">N</span><small data-r="unit">MPH</small></div>
      <div class="mp-bot"><span data-r="fuelp">100%</span><span class="odo" data-r="odo">000000 MI</span><span data-r="engp">100%</span></div>`,
  };

  STY.radial = {
    label: 'Radial',
    html: o => `
      <svg viewBox="0 0 200 200">
        <circle class="disc" cx="100" cy="100" r="96"/>
        <path class="trk" d="${arcD(100, 100, 86, -135, 135)}"/>
        ${prog(arcD(100, 100, 86, -135, 135), '--sr', 'pa acc')}
        ${ticks(100, 100, 72, 78, -135, 135, 40, 'tk', 5, 67)}
        <path class="trk" d="${arcD(100, 100, 86, 152, 208)}"/>
        ${prog(arcD(100, 100, 86, 152, 208), '--fu', 'pa fuel')}
        ${needle('--sr', -135, 270, 100, 100, 'M100 16L102.6 46H97.4Z')}
      </svg>
      <div class="ctr"><b class="big" data-r="sp">0</b><small data-r="unit">MPH</small><span class="gbox" data-r="gear">N</span></div>`,
  };

  STY.arcDigital = {
    label: 'Arc Digital',
    html: o => `
      <svg viewBox="0 0 240 172">
        ${ticks(120, 114, 98, 104, -115, 115, 44, 'tk', 4, 92)}
        ${prog(arcD(120, 114, 104, -115, 115), '--sr', 'pa acc thin')}
        <path class="trk fat" d="${arcD(120, 114, 80, -115, 115)}"/>
        ${prog(arcD(120, 114, 80, -115, 115), '--sr', 'pa white fat')}
        ${labels(120, 114, 116, -115, 115, [0, Math.round(o.max / 2), o.max])}
      </svg>
      <div class="ctr ad"><b class="big" data-r="sp">0</b><small data-r="unit">MPH</small></div>
      <div class="ad-bot">${ic('fuel')}<div class="fb"><span></span></div><span class="gbox" data-r="gear">N</span></div>`,
  };

  STY.ladder = {
    label: 'Tach Ladder',
    html: o => `
      <div class="lad"><span></span></div>
      <div class="ld-r"><b class="big" data-r="sp">0</b><small data-r="unit">MPH</small>
        <div class="row"><span class="gbox" data-r="gear">N</span>${ic('fuel')}<div class="fb"><span></span></div></div>
      </div>`,
  };

  STY.cluster = {
    label: 'Cluster Bar',
    html: o => `
      <div class="cl-l"><b class="big" data-r="sp">0</b><small data-r="unit">MPH</small>
        <div class="row">${ic('fuel')}<div class="fb"><span></span></div></div></div>
      <div class="cl-m"><div class="hbar"></div><small>RPM</small></div>
      <span class="gbox" data-r="gear">N</span>`,
  };

  STY.pods = {
    label: 'Pod Cluster',
    html: o => `
      <div class="pod sm"><svg viewBox="0 0 60 60"><circle class="disc" cx="30" cy="30" r="28"/>
        <path class="trk" d="${arcD(30, 30, 23, -140, 140)}"/>${prog(arcD(30, 30, 23, -140, 140), '--fu', 'pa fuel')}</svg>${ic('fuel')}</div>
      <div class="pod lg"><svg viewBox="0 0 160 160"><circle class="disc" cx="80" cy="80" r="78"/>
        ${ticks(80, 80, 61, 67, -135, 135, 36, 'tk', 4, 57)}
        <path class="trk" d="${arcD(80, 80, 72, -135, 135)}"/>${prog(arcD(80, 80, 72, -135, 135), '--sr', 'pa acc')}</svg>
        <div class="ctr"><b class="big" data-r="sp">0</b><small data-r="unit">MPH</small></div></div>
      <div class="pod sm"><svg viewBox="0 0 60 60"><circle class="disc" cx="30" cy="30" r="28"/>
        <path class="trk" d="${arcD(30, 30, 23, -140, 140)}"/>${prog(arcD(30, 30, 23, -140, 140), '--rpm', 'pa white')}</svg><b class="gtxt" data-r="gear">N</b></div>`,
  };

  STY.classic = {
    label: 'Classic Dual',
    html: o => `
      <div class="dial"><svg viewBox="0 0 120 120"><circle class="disc2" cx="60" cy="60" r="58"/>
        ${ticks(60, 60, 47, 52, -130, 130, 32, 'tk', 4, 43)}
        <path class="red" d="${arcD(60, 60, 53, 97.5, 130)}"/>
        ${labels(60, 60, 36, -130, 130, [0, 1, 2, 3, 4, 5, 6, 7, 8], 'lb sm')}
        ${needle('--rpm', -130, 260, 60, 60, 'M59 64L60 14L61 64Z')}
        <circle class="hub" cx="60" cy="60" r="4.5"/></svg>
        <span class="gsm" data-r="gear">N</span><small class="dl-lab">RPM x1000</small></div>
      <div class="dial mini"><svg viewBox="0 0 60 60"><circle class="disc2" cx="30" cy="30" r="28"/>
        ${ticks(30, 30, 20, 24, -60, 60, 4, 'tk', 2, 18)}
        <text class="lb sm" x="${f(pt(30, 30, 14, -60)[0])}" y="${f(pt(30, 30, 14, -60)[1])}">E</text>
        <text class="lb sm" x="${f(pt(30, 30, 14, 60)[0])}" y="${f(pt(30, 30, 14, 60)[1])}">F</text>
        ${needle('--fu', -60, 120, 30, 30, 'M29.4 32L30 9L30.6 32Z')}
        <circle class="hub" cx="30" cy="30" r="3"/></svg></div>
      <div class="dial"><svg viewBox="0 0 120 120"><circle class="disc2" cx="60" cy="60" r="58"/>
        ${ticks(60, 60, 47, 52, -130, 130, 30, 'tk', 5, 43)}
        ${labels(60, 60, 36, -130, 130, steps(o.max, 6), 'lb sm')}
        ${needle('--sr', -130, 260, 60, 60, 'M59 64L60 14L61 64Z')}
        <circle class="hub" cx="60" cy="60" r="4.5"/></svg>
        <small class="dl-lab" data-r="unit">MPH</small><span class="odo sm" data-r="odo">000000</span></div>`,
  };

  STY.digital = {
    label: 'Digital Linear',
    html: o => `
      <div class="dg-top"><span class="gbox" data-r="gear">N</span><b class="dig" data-r="sp3">000</b>
        <div class="dg-side"><div class="mini">${ic('fuel')}<span data-r="fuelp">100%</span></div><div class="mini">${ic('engine')}<span data-r="engp">100%</span></div></div></div>
      <div class="dg-bars"></div>
      <div class="odo" data-r="odo">000000 MI</div>
      <div class="dg-ind">${['arrowL', 'gauge', 'warn', 'belt', 'light', 'lock', 'arrowR'].map(i => `<span class="li li-${i}">${ic(i)}</span>`).join('')}</div>`,
  };

  STY.sport = {
    label: 'Sport Arc',
    html: o => `
      <svg viewBox="0 0 200 200">
        <path class="trk sa" d="${arcD(100, 100, 78, -140, 70)}"/>
        ${prog(arcD(100, 100, 78, -140, 70), '--sr', 'pa sa acc glow')}
        ${ticks(100, 100, 90, 95, -140, 70, 10, 'tk')}
        ${labels(100, 100, 104, -140, 70, [1, 2, 3, 4, 5], 'lb sm')}
      </svg>
      <div class="ctr sp-c"><span class="cog">${ic('cog')}<b data-r="gear">N</b></span><b class="big" data-r="sp">0</b><small data-r="unit">MPH</small></div>
      <div class="sa-bot"><div>${ic('engine')}<div class="fb en"><span></span></div></div><div>${ic('fuel')}<div class="fb"><span></span></div></div></div>`,
  };

  STY.tesla = {
    label: 'Tesla Style',
    html: o => `
      <div class="prnd"><span data-g="P">P</span><span data-g="R">R</span><span data-g="N">N</span><span data-g="D">D</span></div>
      <b class="big" data-r="sp">0</b><small data-r="unit">MPH</small>
      <div class="tl"><span></span></div>
      <div class="row tsub">${ic('fuel')}<span data-r="fuelp">100%</span><i class="sep"></i><span data-r="odo">000000 MI</span></div>`,
  };

  STY.minimal = {
    label: 'Minimal',
    html: o => `
      <div class="mn"><b class="big" data-r="sp">0</b><div class="mn-r"><span class="gtxt" data-r="gear">N</span><small data-r="unit">MPH</small></div></div>
      <div class="tl"><span></span></div>`,
  };

  STY.lcd = {
    label: 'Retro LCD',
    html: o => `
      <div class="lcd-row"><div class="lcd-num"><i>888</i><b data-r="sp3">000</b></div>
        <div class="lcd-side"><small data-r="unit">MPH</small><span class="lcd-g" data-r="gear">N</span></div></div>
      <div class="lcd-rpm"></div>
      <div class="lcd-fuel"><small>E</small><div class="lcd-fb"></div><small>F</small></div>`,
  };

  STY.dual = {
    label: 'Twin Bars',
    html: o => `
      <div class="tb-row"><small>SPD</small><div class="tb"><span style="--k:var(--sr)"></span></div><b data-r="sp">0</b><small class="u" data-r="unit">MPH</small></div>
      <div class="tb-row"><small>RPM</small><div class="tb rpm"><span style="--k:var(--rpm)"></span></div><b data-r="gear">N</b><small class="u">GEAR</small></div>
      <div class="tb-row"><small>FUEL</small><div class="tb fuel"><span style="--k:var(--fu)"></span></div><b data-r="fuelv">100</b><small class="u">%</small></div>`,
  };

  STY.watch = {
    label: 'Fitness Watch',
    html: o => `
      <i class="strap"></i>
      <div class="wf"><small class="wt" data-r="time">00:00</small><b class="big" data-r="sp">0</b><small data-r="unit">MPH</small>
        <hr/><div class="wh">${NH.fic('heart')}<b data-r="bpm">80</b></div>
        <div class="wr"><small>RPM</small><b data-r="cad">0</b><small data-r="dunit">MI</small><b data-r="dist">0.00</b></div></div>
      <i class="strap"></i>`,
  };

  NH.SPEEDO_STYLES = STY;

  // ---- Instances ----
  const MAX = { MPH: 180, KMH: 300, KTS: 160 };

  function collect(el) {
    const refs = {};
    el.querySelectorAll('[data-r]').forEach(n => (refs[n.dataset.r] = refs[n.dataset.r] || []).push(n));
    return refs;
  }

  NH.createSpeedo = (style, unit = 'MPH') => {
    const def = STY[style] || STY.modern;
    const el = document.createElement('div');
    el.innerHTML = def.html({ max: MAX[unit] || 180, unit }) + '<span class="deco"></span>';
    const inst = { el, style, unit, refs: collect(el), last: {}, vars: {}, cls: '' };
    inst.base = `sp sp-${style in STY ? style : 'modern'}`;
    el.className = inst.base;
    return inst;
  };

  const setVar = (inst, name, v) => {
    if (inst.vars[name] === v) return;
    inst.vars[name] = v;
    inst.el.style.setProperty(name, v);
  };
  const setTxt = (inst, name, v) => {
    const list = inst.refs[name];
    if (!list || inst.last[name] === v) return;
    inst.last[name] = v;
    for (const n of list) n.textContent = v;
  };

  NH.updateSpeedo = (inst, s) => {
    setVar(inst, '--sr', +s.sr.toFixed(3));
    setVar(inst, '--rpm', +s.rpm.toFixed(3));
    setVar(inst, '--fu', +(s.fuel / 100).toFixed(3));
    setVar(inst, '--en', +(s.eng / 100).toFixed(3));
    setTxt(inst, 'sp', String(s.sp));
    setTxt(inst, 'sp3', String(Math.min(999, s.sp)).padStart(3, '0'));
    setTxt(inst, 'gear', s.gear);
    setTxt(inst, 'unit', s.unit);
    setTxt(inst, 'fuelp', s.fuel + '%');
    setTxt(inst, 'fuelv', String(s.fuel));
    setTxt(inst, 'engp', s.eng + '%');
    setTxt(inst, 'odo', s.odo);
    if (inst.style === 'watch') {
      setTxt(inst, 'time', s.time);
      setTxt(inst, 'bpm', String(s.bpm));
      setTxt(inst, 'cad', String(s.cad));
      setTxt(inst, 'dist', s.dist);
      setTxt(inst, 'dunit', s.dunit);
    }
    let cls = inst.base;
    if (s.hb && !s.belt) cls += ' belt-off';
    if (s.li) cls += s.li === 2 ? ' li-on li-hi' : ' li-on';
    if (s.lk) cls += ' lk';
    if (s.ind & 1) cls += ' ind-l';
    if (s.ind & 2) cls += ' ind-r';
    if (s.cr) cls += ' cr';
    if (s.eng < 35) cls += ' eng-warn';
    if (s.fuelWarn && s.fuel < 15) cls += ' fuel-low';
    if (s.rpm > 0.92) cls += ' redline';
    if (cls !== inst.cls) { inst.cls = cls; inst.el.className = cls; }
    if (inst.style === 'tesla') {
      const g = s.gear === 'P' || s.gear === 'R' || s.gear === 'N' ? s.gear : 'D';
      if (inst.el.dataset.prnd !== g) inst.el.dataset.prnd = g;
    }
  };

  NH.DEMO_SPEEDO = { sp: 60, sr: 0.42, rpm: 0.62, gear: '4', fuel: 68, eng: 92, odo: '012480 MI', unit: 'MPH', belt: true, hb: true, li: 1, lk: false, ind: 0, cr: false, time: '14:32', bpm: 131, cad: 78, dist: '3.99', dunit: 'MI' };

  // ---- Aircraft ----
  const AIR = {};
  AIR.pfd = {
    label: 'Flight PFD',
    html: () => `
      <div class="pfd-spd tape"><span class="tp"></span><b class="box" data-r="ias">0</b></div>
      <div class="pfd-att"><div class="hz"><i class="sky"></i><i class="gnd"></i>${[-20, -10, 10, 20].map(p => `<i class="pl" style="--p:${p}"><em>${Math.abs(p)}</em></i>`).join('')}</div>
        <div class="wing"><i></i><b></b><i></i></div><div class="roll"></div></div>
      <div class="pfd-alt tape"><span class="tp"></span><b class="box" data-r="alt">0</b></div>
      <div class="pfd-vs"><span></span></div>
      <div class="pfd-bot"><small>AGL <b data-r="agl">0</b></small><b class="box" data-r="hdg">000</b><small data-r="lg">GEAR DN</small></div>`,
  };
  AIR.cards = {
    label: 'Info Cards',
    html: () => `
      <div class="ac att"><div class="ac-h"><i class="ac-g"></i><span class="ac-r"><i></i><b></b><i></i></span></div>
        <div class="ac-pr"><small>P: <b data-r="pt">0</b>°</small><small>R: <b data-r="rl">0</b>°</small></div></div>
      <div class="ac-row"><div class="ac alt">${ic('upload')}<div><b data-r="altf">0 ft</b><small data-r="vsf">0 ft/m</small></div></div>
        <div class="ac hdg">${ic('compass')}<b data-r="hdgd">0°</b></div></div>`,
  };
  NH.AIR_STYLES = AIR;

  NH.createAir = (style) => {
    const def = AIR[style] || AIR.pfd;
    const el = document.createElement('div');
    el.className = `air air-${style in AIR ? style : 'pfd'}`;
    el.innerHTML = def.html();
    return { el, style, refs: collect(el), last: {}, vars: {}, cls: '' };
  };

  NH.updateAir = (inst, a) => {
    setVar(inst, '--pitch', a.pt);
    setVar(inst, '--roll', a.rl);
    setVar(inst, '--ias', a.ias);
    setVar(inst, '--alt', a.alt);
    setVar(inst, '--vs', Math.max(-1, Math.min(1, a.vs / 3000)).toFixed(2));
    setTxt(inst, 'ias', String(a.ias));
    setTxt(inst, 'alt', a.alt.toLocaleString('en-US'));
    setTxt(inst, 'agl', a.agl.toLocaleString('en-US'));
    setTxt(inst, 'hdg', String(a.hdg).padStart(3, '0'));
    setTxt(inst, 'hdgd', a.hdg + '°');
    setTxt(inst, 'lg', a.gearDown ? 'GEAR DN' : 'GEAR UP');
    setTxt(inst, 'pt', String(a.pt));
    setTxt(inst, 'rl', String(a.rl));
    setTxt(inst, 'altf', a.alt.toLocaleString('en-US') + ' ft');
    setTxt(inst, 'vsf', (a.vs > 0 ? '+' : '') + a.vs + ' ft/m');
  };

  NH.DEMO_AIR = { pt: 6, rl: -14, ias: 128, alt: 3250, agl: 1180, vs: 640, hdg: 82, gearDown: true };
})();
