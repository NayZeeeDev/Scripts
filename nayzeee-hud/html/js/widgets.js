(() => {
  const NH = window.NH;
  const ic = NH.ic;
  const $ = (el, sel) => el.querySelector(sel);

  const DIRS = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  NH.dirOf = deg => DIRS[Math.round(((deg % 360) + 360) % 360 / 45) % 8];

  const inVeh = () => !!NH.S.vm;
  const pxH = (el) => el.offsetHeight / window.innerHeight * 100;

  // Every widget: anchor = which point of the element sits on (x,y) %, pos() = default position
  const W = NH.W = {};
  const def = (id, o) => (W[id] = Object.assign({ id, anchor: [0, 0], el: null }, o));

  // ---------------- Status ----------------
  def('status', {
    label: 'Player Status', anchor: [0, 1],
    pos: c => NH.cur.status.place === 'side'
      ? (c.radar ? [c.map.l + c.map.w + 0.7, c.map.b] : [1.4, 98.2])
      : [Math.max(1.2, c.map.l + 0.2), 98.4], // under the minimap (the radar is lifted to make room)
    visible: () => NH.cur.status.enabled,
    build(el) { NH.status.build(el); el.insertAdjacentHTML('beforeend', '<span class="deco"></span>'); },
    apply() { NH.status.apply(); },
    render(g) { if (g.st || g.edit) NH.status.render(); },
  });

  // ---------------- Street bar ----------------
  def('street', {
    label: 'Street Bar', anchor: [0, 1],
    pos: c => c.radar ? [c.map.l, c.map.b - c.map.h - 0.9] : [1.4, 98.2 - (c.statusH || 4.6) - 0.9],
    visible: () => NH.cur.map.street && (inVeh() || NH.cur.map.streetOnFoot),
    build(el) {
      el.innerHTML = `<div class="sb panel"><b class="sb-dir">N</b><div class="sb-t"><b class="sb-s">-</b><small class="sb-z">-</small></div></div><span class="deco"></span>`;
      this.r = { dir: $(el, '.sb-dir'), s: $(el, '.sb-s'), z: $(el, '.sb-z') };
    },
    render(g) {
      if (!g.loc && !g.edit) return;
      const S = NH.S;
      this.r.dir.textContent = NH.dirOf(S.dir || 0);
      this.r.s.textContent = S.str || 'Unknown Road';
      const z = [S.zn || 'San Andreas'];
      if (S.pst) z.push(S.pst);
      else if (S.crs) z.unshift(S.crs);
      this.r.z.textContent = z.join(' · ');
    },
  });

  // ---------------- Minimap frame ----------------
  def('mapframe', {
    label: 'Minimap Frame', fixed: true,
    visible: () => NH.cur.map.frame && NH.cur.map.frameStyle !== 'none' && (c => !c.shape || c.shape === 'default')(NH.map) && (NH.S.radar || NH.editing),
    build(el) { el.innerHTML = '<div class="mf"><i></i><i></i><i></i><i></i></div>'; this.mf = el.firstChild; },
    apply() { this.mf.dataset.style = NH.cur.map.frameStyle || 'glass'; },
    place(c) {
      const s = this.el.style;
      s.left = c.map.l + '%'; s.top = (c.map.b - c.map.h) + '%';
      s.width = c.map.w + '%'; s.height = c.map.h + '%';
    },
  });

  // ---------------- Speed limit sign ----------------
  def('sign', {
    label: 'Speed Limit', anchor: [1, 0],
    pos: c => c.radar ? [c.map.l + c.map.w - 0.4, c.map.b - c.map.h + 0.8] : [16, 80],
    visible: () => NH.cur.map.sign && ((inVeh() && ['car', 'moto'].includes(NH.S.vm)) || NH.editing),
    build(el) { el.innerHTML = '<div class="sgn"><small>SPEED<br>LIMIT</small><b>30</b></div>'; this.b = $(el, 'b'); this.box = el.firstChild; },
    apply() { this.box.className = 'sgn ' + (NH.cur.map.signStyle === 'eu' ? 'eu' : 'us'); this.limit = null; },
    render(g) {
      if (!g.veh && !g.loc && !g.edit) return;
      const lim = NH.S.lim || 35;
      const kmh = NH.cur.units === 'kmh';
      const shown = kmh ? Math.round(lim * 1.609 / 10) * 10 : lim;
      if (shown !== this.limit) { this.limit = shown; this.b.textContent = shown; }
      const speeding = NH.cur.map.blink && NH.veh && NH.veh.spUnit > shown + 3;
      this.box.classList.toggle('blink', !!speeding);
    },
  });

  // ---------------- Speedometer ----------------
  def('speedo', {
    label: 'Speedometer', anchor: [1, 1],
    pos: () => [98.6, 97.8],
    visible: () => (inVeh() && NH.S.vm !== 'train') || NH.editing,
    build(el) { this.inst = null; },
    effectiveStyle() {
      if (NH.S.vm === 'cycle' && NH.cur.cycle.style !== 'car') return NH.cur.cycle.style;
      return NH.cur.speedo.style;
    },
    apply() {
      const style = this.effectiveStyle();
      const unit = NH.vehUnit();
      if (!this.inst || this.inst.style !== style || this.inst.unit !== unit) {
        this.inst = NH.createSpeedo(style, unit);
        this.el.innerHTML = '';
        this.el.appendChild(this.inst.el);
        this.dirtySize = true;
      }
    },
    render(g) {
      if (g.mode || g.edit) this.apply();
      if (!g.veh && !g.edit && !g.mode && !g.clk) return;
      NH.updateSpeedo(this.inst, NH.vehState());
    },
  });

  // ---------------- Dashboard lights ----------------
  def('dash', {
    label: 'Dashboard Lights', anchor: [0.5, 1],
    pos: () => [50, 98.4],
    visible: () => NH.cur.speedo.lights && ((inVeh() && ['car', 'moto'].includes(NH.S.vm)) || NH.editing),
    build(el) {
      el.innerHTML = `<div class="dash panel">${['belt', 'light', 'gauge', 'lock', 'warn', 'bolt', 'arrowL', 'arrowR'].map(i => `<span class="dl dl-${i}">${ic(i)}</span>`).join('')}</div><span class="deco"></span>`;
      this.box = el.firstChild;
    },
    render(g) {
      if (!g.veh && !g.edit) return;
      const s = NH.vehState();
      let cls = 'dash panel';
      if (s.hb && !s.belt) cls += ' belt-off';
      if (s.li) cls += s.li === 2 ? ' li-on li-hi' : ' li-on';
      if (s.cr) cls += ' cr';
      if (s.lk) cls += ' lk';
      if (s.eng < 35) cls += ' eng-warn';
      if (s.ind & 1) cls += ' ind-l';
      if (s.ind & 2) cls += ' ind-r';
      if (NH.S.hn) cls += ' hn';
      if (NH.S.nos > 0) cls += NH.S.nosOn ? ' nos nos-on' : ' nos';
      if (this.box.className !== cls) this.box.className = cls;
    },
  });

  // ---------------- Aircraft ----------------
  def('air', {
    label: 'Flight Display', anchor: [1, 1],
    pos: c => [98.6, 97.8 - (c.speedoH || 22) - 1.2],
    visible: () => NH.cur.air.style !== 'off' && (NH.S.vm === 'air' || NH.editing),
    build() { this.inst = null; },
    apply() {
      const style = NH.cur.air.style === 'off' ? 'pfd' : NH.cur.air.style;
      if (!this.inst || this.inst.style !== style) {
        this.inst = NH.createAir(style);
        this.el.innerHTML = '';
        this.el.appendChild(this.inst.el);
      }
    },
    render(g) {
      if (!g.air && !g.veh && !g.edit) return;
      const S = NH.S;
      const a = NH.S.vm === 'air' ? {
        pt: S.pt || 0, rl: S.rl || 0, ias: Math.round((S.spd || 0) / 10 * 1.943844),
        alt: S.alt || 0, agl: S.agl || 0, vs: S.vs || 0, hdg: S.vh || 0, gearDown: !S.lg,
      } : NH.DEMO_AIR;
      NH.updateAir(this.inst, a);
    },
  });

  // ---------------- Boat ----------------
  def('boat', {
    label: 'Boat Display', anchor: [1, 1],
    pos: c => NH.editing && !NH.S.vm ? [80, 97.8] : [98.6, 97.8 - (c.speedoH || 22) - 1.2],
    visible: () => NH.cur.boat.info !== false && (NH.S.vm === 'boat' || NH.editing),
    build(el) { this.inst = NH.createBoat(); el.appendChild(this.inst.el); },
    render(g) {
      if (!g.air && !g.veh && !g.edit) return;
      const S = NH.S;
      NH.updateBoat(this.inst, S.vm === 'boat' ? { pt: S.pt || 0, hdg: S.vh || 0 } : NH.DEMO_BOAT);
    },
  });

  // ---------------- Compass ----------------
  const PX = 2.4; // px per degree
  def('compass', {
    label: 'Compass', anchor: [0.5, 0],
    pos: () => [50, 1.4],
    visible: () => NH.cur.map.compass && (NH.cur.map.compassWhen === 'always' || inVeh() || NH.editing),
    build(el) {
      let strip = '';
      for (let d = -360; d <= 720; d += 5) {
        const n = ((d % 360) + 360) % 360;
        const x = (d + 360) * PX;
        if (n % 45 === 0) strip += `<b class="cd${n % 90 === 0 ? ' main' : ''}" style="left:${x}px">${DIRS[n / 45]}</b>`;
        else if (n % 15 === 0) strip += `<i class="tk lg" style="left:${x}px"></i><small style="left:${x}px">${n}</small>`;
        else strip += `<i class="tk" style="left:${x}px"></i>`;
      }
      el.innerHTML = `
        <div class="cmp-tape"><div class="cmp-win"><div class="cmp-strip">${strip}</div></div><span class="cmp-mark"></span><b class="cmp-deg">0°</b></div>
        <div class="cmp-rib panel"><b class="cmp-l">N</b><i></i><span class="cmp-d">0°</span></div>`;
      this.strip = $(el, '.cmp-strip');
      this.deg = $(el, '.cmp-deg');
      this.l = $(el, '.cmp-l');
      this.d = $(el, '.cmp-d');
      this.shown = null;
    },
    apply() { this.el.dataset.style = NH.cur.map.compassStyle; },
    render(g) {
      if (!g.cmp && !g.edit) return;
      const h = NH.S.hdg || 0;
      if (this.shown === null) this.shown = h;
      else {
        let delta = h - (((this.shown % 360) + 360) % 360);
        if (delta > 180) delta -= 360;
        if (delta < -180) delta += 360;
        if (this.shown < -300 || this.shown > 660) { // keep inside the strip without visible jumps
          this.strip.style.transition = 'none';
          this.shown = ((this.shown % 360) + 360) % 360;
          this.strip.style.transform = `translateX(${-(this.shown + 360) * PX}px)`;
          void this.strip.offsetWidth;
          this.strip.style.transition = '';
        }
        this.shown += delta;
      }
      this.strip.style.transform = `translateX(${-(this.shown + 360) * PX}px)`;
      this.deg.textContent = h + '°';
      this.l.textContent = NH.dirOf(h);
      this.d.textContent = h + '°';
    },
  });

  // ---------------- Clock & weather ----------------
  const WX_LABEL = { EXTRASUNNY: 'Sunny', CLEAR: 'Clear', NEUTRAL: 'Clear', CLOUDS: 'Cloudy', OVERCAST: 'Overcast', CLEARING: 'Clearing', RAIN: 'Rain', RAIN_HALLOWEEN: 'Rain',
    THUNDER: 'Thunder', SMOG: 'Smog', FOGGY: 'Foggy', HALLOWEEN: 'Foggy', SNOW: 'Snow', SNOWLIGHT: 'Light snow', BLIZZARD: 'Blizzard', XMAS: 'Snow', SNOW_HALLOWEEN: 'Snow' };
  const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  const wxIcon = (cls = '') => `<svg class="wx ${cls}" viewBox="0 0 24 24" data-c="icon"></svg>`;

  NH.CLOCK_STYLES = {
    pill:  { label: 'Pill',          html: () => `<div class="clk pill panel"><div class="clk-t"><b data-c="time"></b><small class="c-day" data-c="day"></small></div>${wxIcon()}</div>` },
    text:  { label: 'Text and icon', html: () => `<div class="clk text"><div class="clk-t"><b data-c="time"></b><small class="c-day" data-c="day"></small></div>${wxIcon()}</div>` },
    card:  { label: 'Weather Card',  html: () => `<div class="clk card panel">${wxIcon('lg')}<div class="clk-t"><b data-c="time"></b><small class="c-day" data-c="full"></small><small class="c-wx" data-c="wxl"></small></div></div>` },
    line:  { label: 'Line',          html: () => `<div class="clk line">${wxIcon('sm')}<span class="c-day" data-c="date"></span><b data-c="time"></b></div>` },
    big:   { label: 'Big Clock',     html: () => `<div class="clk big"><div class="clk-t"><b data-c="time"></b><small class="c-day" data-c="full"></small></div>${wxIcon('lg')}</div>` },
    split: { label: 'Split Pills',   html: () => `<div class="clk split"><span class="panel">${ic('clock')}<b data-c="time"></b></span><span class="panel c-wx">${wxIcon('sm')}<b data-c="wxl"></b></span></div>` },
  };

  NH.clockValues = (S, c) => {
    let h, m, dow, dom, mon;
    if (c.source === 'real') { const d = new Date(); h = d.getHours(); m = d.getMinutes(); dow = d.getDay(); dom = d.getDate(); mon = d.getMonth(); }
    else { h = S.hr ?? 12; m = S.mn ?? 0; dow = S.dow ?? 5; dom = S.dom ?? 1; mon = S.mon ?? 0; }
    const mm = String(m).padStart(2, '0');
    const wx = S.wx || 'CLEAR';
    return {
      time: c.h24 ? `${String(h).padStart(2, '0')}:${mm}` : `${(h % 12) || 12}:${mm} ${h < 12 ? 'AM' : 'PM'}`,
      day: DAYS[dow] || '',
      full: `${DAYS[dow] || ''}, ${dom} ${MONTHS[mon] || ''}`,
      date: `${dom} ${MONTHS[mon] || ''} ${(DAYS[dow] || '').slice(0, 3)}`,
      wxl: WX_LABEL[wx] || 'Clear',
      icon: wx + (h < 6 || h >= 20 ? '|n' : '|d'),
    };
  };

  NH.fillClock = (refs, v, last = {}) => {
    for (const k in refs) {
      if (v[k] === undefined || last[k] === v[k]) continue;
      last[k] = v[k];
      for (const n of refs[k]) {
        if (k === 'icon') { const [wx, n2] = v.icon.split('|'); n.innerHTML = NH.weatherIcon(wx, n2 === 'n'); }
        else n.textContent = v[k];
      }
    }
    return last;
  };

  NH.clockPreview = (style) => {
    const wrap = document.createElement('div');
    wrap.innerHTML = (NH.CLOCK_STYLES[style] || NH.CLOCK_STYLES.pill).html();
    const refs = {};
    wrap.querySelectorAll('[data-c]').forEach(n => (refs[n.dataset.c] = refs[n.dataset.c] || []).push(n));
    NH.fillClock(refs, NH.clockValues({ hr: 23, mn: 27, dow: 5, dom: 6, mon: 7, wx: 'CLEAR' }, Object.assign({}, NH.cur.clock, { source: 'game' })));
    return wrap.firstElementChild;
  };

  def('clock', {
    label: 'Weather & Time', anchor: [1, 0],
    pos: () => [98.6, 1.6],
    visible: () => NH.cur.clock.enabled,
    build() { this.style = null; this.timer = null; },
    apply() {
      const c = NH.cur.clock;
      if (c.style !== this.style) {
        this.style = c.style;
        this.el.innerHTML = (NH.CLOCK_STYLES[c.style] || NH.CLOCK_STYLES.pill).html() + '<span class="deco"></span>';
        this.box = this.el.firstChild;
        this.refs = {};
        this.el.querySelectorAll('[data-c]').forEach(n => (this.refs[n.dataset.c] = this.refs[n.dataset.c] || []).push(n));
        this.last = {};
      }
      this.box.classList.toggle('no-day', !c.day);
      this.box.classList.toggle('no-wx', !c.weather);
      clearInterval(this.timer);
      if (c.source === 'real') this.timer = setInterval(() => this.render({ clk: 1 }), 10000);
      this.render({ clk: 1 });
    },
    render(g) {
      if (!g.clk && !g.edit) return;
      NH.fillClock(this.refs, NH.clockValues(NH.S, NH.cur.clock), this.last);
    },
  });

  // ---------------- Player info ----------------
  def('info', {
    label: 'Player Info', anchor: [1, 0],
    pos: c => [98.6, NH.cur.clock.enabled && !NH.cur.layout.clock ? 1.6 + (c.clockH || 4.6) + 0.9 : 7.2],
    visible: () => NH.cur.info.enabled,
    build(el) { this.style = null; },
    apply() {
      const c = NH.cur.info;
      if (c.style !== this.style) {
        this.style = c.style;
        this.el.innerHTML = (NH.INFO_STYLES[c.style] || NH.INFO_STYLES.pills).html() + '<span class="deco"></span><div class="mpops"></div>';
        this.pops = this.el.querySelector('.mpops');
        this.refs = NH.collectInfo(this.el);
        this.box = this.el.firstChild;
        this.last = {};
        this.hiddenKey = '';
      }
      this.render({ info: 1, st: 1, clk: 1 });
    },
    pop(kind, delta, total) {
      if (!this.pops) return;
      const el = document.createElement('div');
      const neutral = total !== undefined;
      el.className = 'mpop ' + (neutral ? 'acc' : delta < 0 ? 'neg' : 'pos');
      el.innerHTML = `${ic(kind === 'bank' ? 'bank' : 'cash')}${neutral ? `<small>${kind === 'bank' ? 'Bank' : 'Cash'}</small><b>${NH.money(total)}</b>` : `<b>${delta < 0 ? '-' : '+'}${NH.money(Math.abs(delta))}</b>`}`;
      this.pops.appendChild(el);
      while (this.pops.children.length > 4) this.pops.firstChild.remove();
      setTimeout(() => el.remove(), neutral ? 4200 : 2800);
    },
    render(g) {
      if (!g.info && !g.st && !g.clk && !g.edit) return;
      const S = NH.S, c = NH.cur.info;
      NH.fillInfo(this.refs, NH.infoValues(S), this.last);
      const hidden = NH.infoHidden(S, c);
      const key = JSON.stringify(hidden);
      if (key !== this.hiddenKey) {
        this.hiddenKey = key;
        for (const k in hidden) this.box.classList.toggle('no-' + k, hidden[k]);
      }
      // +$/-$ popups: only for real changes, never for the first value or right after login
      this.prevMoney = this.prevMoney || {};
      for (const k of ['cash', 'bank']) {
        if (S[k] === undefined) continue;
        const v = Number(S[k]) || 0, prev = this.prevMoney[k];
        if (prev !== undefined && v !== prev && c.popups && Date.now() > (NH.popsAfter || 0)) this.pop(k, v - prev);
        this.prevMoney[k] = v;
      }
      this.box.classList.toggle('talk', !!S.tk);
    },
  });

  // ---------------- Weapon ----------------
  def('weapon', {
    label: 'Weapon', anchor: [1, 0],
    pos: () => [98.6, 33],
    visible: () => NH.cur.weapon.enabled && (!!NH.S.wp || NH.editing),
    build(el) {
      el.innerHTML = `<div class="wpn"><img alt=""/><b class="wn"></b><div class="am">${ic('bullets')}<b class="clip">0</b><i></i><span class="res">0</span></div></div><span class="deco"></span>`;
      this.box = el.firstChild; this.img = $(el, 'img'); this.n = $(el, '.wn'); this.c = $(el, '.clip'); this.r = $(el, '.res'); this.am = $(el, '.am');
      this.img.onerror = () => this.box.classList.add('noimg');
      this.img.onload = () => this.box.classList.remove('noimg');
    },
    apply() {
      const c = NH.cur.weapon;
      this.box.className = `wpn w-${c.style} ${c.style === 'card' ? 'panel' : ''}`;
      this.box.classList.toggle('hideimg', !c.image || !NH.cfg.weaponImages);
      this.wp = null;
      this.render({ wpn: 1 });
    },
    render(g) {
      if (!g.wpn && !g.edit) return;
      const S = NH.S;
      const wp = S.wp || (NH.editing ? 'WEAPON_HEAVYPISTOL' : null);
      if (!wp) return;
      if (wp !== this.wp) {
        this.wp = wp;
        this.n.textContent = S.wp ? (S.wl || 'Weapon') : 'Heavy Pistol';
        if (NH.cfg.weaponImages && wp !== 'WEAPON_UNKNOWN') this.img.src = NH.cfg.weaponImages.replace('%s', wp.toUpperCase());
        else this.box.classList.add('noimg');
      }
      const melee = S.wp ? S.clip === false : false;
      this.am.style.display = melee ? 'none' : '';
      this.c.textContent = S.wp ? (S.clip || 0) : 30;
      this.r.textContent = S.wp ? (S.ammo || 0) : 36;
    },
  });

  // ---------------- Watermark ----------------
  // ---------------- Voice & radio ----------------
  // Range (whisper / normal / shout or the voice resource's own names), talking, radio channel and transmit.
  const RANGE3 = ['Whisper', 'Normal', 'Shouting'];
  NH.VOICE_STYLES = [['pill', 'Pill'], ['bars', 'Bars'], ['card', 'Card'], ['minimal', 'Minimal']];
  NH.voiceValues = (S) => {
    const count = Math.max(1, Math.min(6, S.vrc || 3));
    const idx = Math.max(1, Math.min(count, S.vr || 2));
    const name = S.vrn || (count === 3 ? RANGE3[idx - 1] : `Range ${idx}`);
    const dist = typeof S.vrd === 'number' && S.vrd > 0 ? `${+S.vrd.toFixed(1)}m` : '';
    const rd = S.rd ? (/^\d+(\.\d+)?$/.test(String(S.rd)) ? `CH ${S.rd}` : String(S.rd)) : '';
    return { count, idx, name, dist, rd, talk: !!S.tk, rt: !!S.rt };
  };
  NH.voiceHtml = (style) => `<div class="vc vs-${style}${style === 'minimal' ? '' : ' panel'}">
      <span class="vc-mic">${ic('mic')}<span class="vc-eq"><i></i><i></i><i></i></span></span>
      <div class="vc-r"><div class="vc-bars"></div><div class="vc-t"><b class="vc-n"></b><small class="vc-d"></small></div></div>
      <span class="vc-radio">${ic('radio')}<b class="vc-ch"></b></span></div>`;
  NH.fillVoice = (box, v) => {
    const bars = box.querySelector('.vc-bars');
    if (bars.childElementCount !== v.count) bars.innerHTML = '<i></i>'.repeat(v.count);
    [...bars.children].forEach((b, i) => b.classList.toggle('on', i < v.idx));
    box.querySelector('.vc-n').textContent = v.name;
    box.querySelector('.vc-d').textContent = v.dist;
    box.querySelector('.vc-ch').textContent = v.rd;
    box.classList.toggle('talk', v.talk);
    box.classList.toggle('has-rd', !!v.rd);
    box.classList.toggle('rt', v.rt);
  };

  def('voice', {
    label: 'Voice & Radio', anchor: [0, 1],
    // right of the player status row, same baseline
    pos: c => NH.cur.status.enabled && W.status.x != null ? [W.status.x + (c.statusW || 20) + 0.7, W.status.y] : [1.4, 98.4],
    visible: () => {
      const c = NH.cur.voice;
      if (!c.enabled) return false;
      if (NH.editing || c.when === 'always') return true;
      if (c.when === 'radio') return !!NH.S.rd;
      return !!(NH.S.tk || NH.S.rt); // 'talking'
    },
    build() {
      this.style = null;
      // the status row grows and shrinks as rings auto-hide; keep sitting right next to it
      if (window.ResizeObserver && W.status.el) {
        let last = 0;
        new ResizeObserver(([e]) => {
          const w = Math.round(e.contentRect.width);
          if (w !== last) { last = w; if (NH.cur && NH.cur.voice && NH.cur.voice.enabled) NH.place(); }
        }).observe(W.status.el);
      }
    },
    apply() {
      const c = NH.cur.voice;
      if (c.style !== this.style) {
        this.style = c.style;
        this.el.innerHTML = NH.voiceHtml(c.style) + '<span class="deco"></span>';
        this.box = this.el.firstElementChild;
      }
      this.box.classList.toggle('no-name', !c.label);
      this.render({ st: 1 });
    },
    render(g) {
      if (!g.st && !g.edit) return;
      const v = NH.voiceValues(NH.editing && !NH.S.vr ? { vr: 2, vrc: 3, rd: 12, tk: true } : NH.S);
      NH.fillVoice(this.box, v);
    },
  });

  // Server logo: a file dropped into html/logo/ (or a link). 'auto' takes the first logo.* that loads.
  const esc = NH.esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const LOGO_AUTO = ['logo/logo.png', 'logo/logo.webp', 'logo/logo.gif', 'logo/logo.svg'];
  NH.logoCandidates = (logo) => {
    if (!logo) return [];
    if (logo === 'auto') return LOGO_AUTO;
    if (/^https?:\/\//i.test(logo) || /^nui:\/\//i.test(logo)) return [logo];
    return /^[\w.-]+$/.test(logo) ? ['logo/' + logo] : [];
  };
  NH.findLogo = (logo, done) => {
    const list = NH.logoCandidates(logo);
    const next = (i) => {
      if (i >= list.length) return done(null);
      const img = new Image();
      img.onload = () => done(list[i]);
      img.onerror = () => next(i + 1);
      img.src = list[i];
    };
    next(0);
  };

  def('watermark', {
    label: 'Watermark', anchor: [0, 0],
    pos: () => [1.4, 1.6],
    visible: () => NH.cur.watermark.enabled && NH.cfg.watermark.enabled !== false,
    build(el) { this.key = null; this.logo = null; this.logoFor = undefined; },
    apply() {
      const c = NH.cur.watermark, w = NH.cfg.watermark;
      // look the logo up again whenever the configured value changes (the server's config arrives after boot)
      if (this.logoFor !== w.logo) {
        const want = this.logoFor = w.logo;
        this.logo = null;
        NH.logoSrc = null;
        NH.findLogo(want, (src) => {
          if (this.logoFor !== want) return;
          this.logo = src; NH.logoSrc = src; this.key = null; this.apply(); NH.place?.();
        });
      }
      const key = [c.style, c.effect, w.title, w.subtitle, this.logo, w.showText].join('|');
      if (key === this.key) return;
      this.key = key;
      const logo = this.logo ? `<img src="${esc(this.logo)}" alt=""/>` : '';
      const text = this.logo && w.showText === false ? ''
        : `<div class="wm-t"><b data-text="${esc(w.title)}">${esc(w.title)}</b>${w.subtitle ? `<small>${esc(w.subtitle)}</small>` : ''}</div>`;
      this.el.innerHTML = `<div class="wm wm-${c.style} fx-${c.effect}">${logo}${text}</div><span class="deco"></span>`;
    },
  });

  // ---------------- Layout ----------------
  NH.layoutCtx = () => ({
    radar: !!NH.S.radar || (NH.editing && NH.cur.map.mode !== 'never'),
    // in the browser preview there is no Lua to lift the radar, so mimic it
    map: NH.IS_GAME ? NH.map : Object.assign({}, NH.map, { b: NH.map.b - (NH.cur.status.enabled && NH.cur.status.place !== 'side' ? 4.5 : 0) }),
    statusH: W.status.el ? pxH(W.status.el) * (NH.cur.layout.status?.s || 1) * NH.cur.scale : 4.6,
    statusW: W.status.el ? W.status.el.offsetWidth / window.innerWidth * 100 * (NH.cur.layout.status?.s || 1) * NH.cur.scale : 20,
    speedoH: W.speedo.el && W.speedo.el.offsetHeight ? pxH(W.speedo.el) * (NH.cur.layout.speedo?.s || 1) * NH.cur.scale : 22,
    clockH: W.clock.el && W.clock.el.offsetHeight ? pxH(W.clock.el) * (NH.cur.layout.clock?.s || 1) * NH.cur.scale : 4.6,
  });

  NH.place = () => {
    const ctx = NH.layoutCtx();
    for (const id in W) {
      const w = W[id];
      if (!w.el) continue;
      if (w.fixed) { w.place(ctx); continue; }
      const saved = NH.cur.layout[id];
      const [x, y] = saved && saved.x != null ? [saved.x, saved.y] : w.pos(ctx);
      const s = (saved?.s || 1) * NH.cur.scale;
      const [ax, ay] = w.anchor;
      const st = w.el.style;
      st.left = x + '%';
      st.top = y + '%';
      st.transformOrigin = `${ax * 100}% ${ay * 100}%`;
      st.transform = `translate(${-ax * 100}%, ${-ay * 100}%) scale(${s})`;
      w.x = x; w.y = y;
    }
  };

  NH.updateVisibility = () => {
    for (const id in W) {
      const w = W[id];
      if (!w.el) continue;
      w.el.classList.toggle('off', !w.visible());
    }
  };

  NH.buildWidgets = () => {
    const hud = document.getElementById('hud');
    for (const id in W) {
      const el = document.createElement('div');
      el.className = `w w-${id}`;
      el.dataset.id = id;
      el.dataset.label = W[id].label;
      hud.appendChild(el);
      W[id].el = el;
      W[id].build(el);
    }
  };

  // ---------------- Edit layout (drag + wheel) ----------------
  let drag = null;
  document.addEventListener('pointerdown', (e) => {
    if (!NH.editing) return;
    const el = e.target.closest('.w');
    if (!el || W[el.dataset.id]?.fixed) return;
    const w = W[el.dataset.id];
    drag = { w, sx: e.clientX, sy: e.clientY, x: w.x, y: w.y };
    el.classList.add('dragging');
    el.setPointerCapture?.(e.pointerId);
    e.preventDefault();
  });
  document.addEventListener('pointermove', (e) => {
    if (!drag) return;
    const x = Math.max(0, Math.min(100, drag.x + (e.clientX - drag.sx) / window.innerWidth * 100));
    const y = Math.max(0, Math.min(100, drag.y + (e.clientY - drag.sy) / window.innerHeight * 100));
    const L = NH.cur.layout[drag.w.id] = NH.cur.layout[drag.w.id] || {};
    L.x = +x.toFixed(2); L.y = +y.toFixed(2);
    NH.place();
  });
  document.addEventListener('pointerup', () => {
    if (!drag) return;
    drag.w.el.classList.remove('dragging');
    drag = null;
    NH.settingsUI?.markDirty();
  });
  document.addEventListener('wheel', (e) => {
    if (!NH.editing) return;
    const el = e.target.closest('.w');
    if (!el || W[el.dataset.id]?.fixed) return;
    const L = NH.cur.layout[el.dataset.id] = NH.cur.layout[el.dataset.id] || {};
    L.s = Math.max(0.4, Math.min(2.5, +((L.s || 1) + (e.deltaY < 0 ? 0.05 : -0.05)).toFixed(2)));
    NH.place();
    NH.settingsUI?.markDirty();
    NH.toast?.(`${W[el.dataset.id].label}: ${Math.round(L.s * 100)}%`);
  }, { passive: true });
  document.addEventListener('contextmenu', (e) => {
    if (!NH.editing) return;
    const el = e.target.closest('.w');
    if (!el) return;
    e.preventDefault();
    delete NH.cur.layout[el.dataset.id];
    NH.place();
    NH.settingsUI?.markDirty();
  });
})();
