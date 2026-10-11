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
    pos: c => c.radar ? [c.map.l + c.map.w + 0.7, c.map.b] : [1.4, 98.2],
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
    visible: () => NH.cur.map.frame && (NH.S.radar || NH.editing),
    build(el) { el.innerHTML = '<div class="mf"></div>'; },
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
      if (NH.S.vm === 'cycle' && NH.cur.cycle.style === 'watch') return 'watch';
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
      el.innerHTML = `<div class="dash panel">${['belt', 'light', 'gauge', 'lock', 'warn', 'arrowL', 'arrowR'].map(i => `<span class="dl dl-${i}">${ic(i)}</span>`).join('')}</div><span class="deco"></span>`;
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
  def('clock', {
    label: 'Weather & Time', anchor: [1, 0],
    pos: () => [98.6, 1.6],
    visible: () => NH.cur.clock.enabled,
    build(el) {
      el.innerHTML = `<div class="clk"><div class="clk-t"><b>00:00</b><small>Monday</small></div><svg class="wx" viewBox="0 0 24 24"></svg></div><span class="deco"></span>`;
      this.box = el.firstChild; this.t = $(el, 'b'); this.d = $(el, 'small'); this.wx = $(el, '.wx');
      this.timer = null;
    },
    apply() {
      const c = NH.cur.clock;
      this.box.className = 'clk ' + (c.style === 'text' ? 'text' : 'pill panel');
      this.d.style.display = c.day ? '' : 'none';
      this.wx.style.display = c.weather ? '' : 'none';
      clearInterval(this.timer);
      if (c.source === 'real') this.timer = setInterval(() => this.render({ clk: 1 }), 10000);
      this.render({ clk: 1 });
    },
    render(g) {
      if (!g.clk && !g.edit) return;
      const c = NH.cur.clock, S = NH.S;
      let h, m, dow;
      if (c.source === 'real') { const d = new Date(); h = d.getHours(); m = d.getMinutes(); dow = d.getDay(); }
      else { h = S.hr ?? 12; m = S.mn ?? 0; dow = S.dow ?? 5; }
      const mm = String(m).padStart(2, '0');
      const txt = c.h24 ? `${String(h).padStart(2, '0')}:${mm}` : `${(h % 12) || 12}:${mm} ${h < 12 ? 'AM' : 'PM'}`;
      if (this.t.textContent !== txt) this.t.textContent = txt;
      const day = DAYS[dow] || '';
      if (this.d.textContent !== day) this.d.textContent = day;
      const night = h < 6 || h >= 20;
      const key = (S.wx || 'CLEAR') + night;
      if (key !== this.wxKey) { this.wxKey = key; this.wx.innerHTML = NH.weatherIcon(S.wx || 'CLEAR', night); }
    },
  });

  // ---------------- Player info ----------------
  def('info', {
    label: 'Player Info', anchor: [1, 0],
    pos: () => [98.6, 7.2],
    visible: () => NH.cur.info.enabled,
    build(el) { this.style = null; },
    apply() {
      const c = NH.cur.info;
      if (c.style !== this.style) {
        this.style = c.style;
        const row = (k, icon, label) => c.style === 'stack'
          ? `<div class="ir i-${k}"><div><small>${label}</small><b data-i="${k}"></b></div><span class="cic">${ic(icon)}</span></div>`
          : `<span class="pill i-${k}">${ic(icon)}<b data-i="${k}"></b></span>`;
        let html;
        if (c.style === 'stack') {
          html = `<div class="inf stack">${row('job', 'briefcase', 'Job')}${row('cash', 'cash', 'Cash')}${row('bank', 'bank', 'Bank')}${row('id', 'idcard', 'Server ID')}</div>`;
        } else if (c.style === 'compact') {
          html = `<div class="inf compact panel"><div class="ic-hd i-headshot"><img data-i="hs" alt=""/><div><b data-i="job"></b><small data-i="id"></small></div></div>
            <div class="ic-row i-cash">${ic('cash')}<b data-i="cash"></b></div><div class="ic-row i-bank">${ic('bank')}<b data-i="bank"></b></div></div>`;
        } else {
          html = `<div class="inf pills"><div class="r">${row('job', 'briefcase')}</div><div class="r">${row('bank', 'bank')}${row('cash', 'cash')}</div>
            <div class="r"><span class="pill hs i-headshot">${NH.fic('mic', 'mic')}<img data-i="hs" alt=""/></span>${row('id', 'idcard')}</div></div>`;
        }
        this.el.innerHTML = html + '<span class="deco"></span>';
        this.refs = {};
        this.el.querySelectorAll('[data-i]').forEach(n => (this.refs[n.dataset.i] = this.refs[n.dataset.i] || []).push(n));
        this.box = this.el.firstChild;
        this.last = {};
      }
      for (const k of ['job', 'cash', 'bank', 'id', 'headshot']) this.box.classList.toggle('no-' + k, !c[k]);
      this.render({ info: 1, st: 1 });
    },
    set(k, v) {
      if (this.last[k] === v || !this.refs[k]) return;
      this.last[k] = v;
      for (const n of this.refs[k]) {
        if (n.tagName === 'IMG') { if (v) n.src = v; n.parentNode.classList.toggle('noimg', !v); }
        else n.textContent = v;
      }
    },
    render(g) {
      if (!g.info && !g.st && !g.edit) return;
      const S = NH.S;
      this.set('job', S.grd ? `${S.job || 'Civilian'} (${S.grd})` : (S.job || 'Civilian'));
      this.set('cash', NH.money(S.cash));
      this.set('bank', NH.money(S.bank));
      this.set('id', this.style === 'compact' ? `ID #${S.id ?? 0}` : `#${S.id ?? 0}`);
      this.set('hs', S.hs ? `https://nui-img/${S.hs}/${S.hs}?t=${S.hs}` : '');
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
  def('watermark', {
    label: 'Watermark', anchor: [0, 0],
    pos: () => [1.4, 1.6],
    visible: () => NH.cur.watermark.enabled && NH.cfg.watermark.enabled !== false,
    build(el) { this.key = null; },
    apply() {
      const c = NH.cur.watermark, w = NH.cfg.watermark;
      const key = c.style + c.effect + w.title + w.subtitle + w.logo;
      if (key === this.key) return;
      this.key = key;
      const logo = w.logo ? `<img src="${w.logo}" alt=""/>` : '';
      this.el.innerHTML = `<div class="wm wm-${c.style} fx-${c.effect}">${logo}<div class="wm-t"><b data-text="${w.title}">${w.title}</b>${w.subtitle ? `<small>${w.subtitle}</small>` : ''}</div></div><span class="deco"></span>`;
    },
  });

  // ---------------- Layout ----------------
  NH.layoutCtx = () => ({
    radar: !!NH.S.radar || (NH.editing && NH.cur.map.mode !== 'never'),
    map: NH.map,
    statusH: W.status.el ? pxH(W.status.el) * (NH.cur.layout.status?.s || 1) * NH.cur.scale : 4.6,
    speedoH: W.speedo.el && W.speedo.el.offsetHeight ? pxH(W.speedo.el) * (NH.cur.layout.speedo?.s || 1) * NH.cur.scale : 22,
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
