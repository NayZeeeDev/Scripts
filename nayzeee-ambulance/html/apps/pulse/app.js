/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · Pulse check (app 'pulse')          module: assess
   3 steps on the shared procedure HUD (NZA.ui.ProcPanel):
     1 Locate the artery  pick the site (neck / wrist), scroll = finger pressure (240° dial in
                          the readout). The palpation scope (pp.slot) is a polar trace swept
                          like a radar: beats only show inside the right pressure band (too
                          light = flat, too hard = flattened artery, amber). N = nothing here.
     2 Count              Space starts the timer; tap Space on every beat. The beat count rolls
                          in the centre of the scope, taps are marked on its rim.
     3 Describe it        rhythm (regular / irregular) and strength (weak / normal / bounding)
                          in the verdict picker (pp.slot, keys 1-5), Enter submits.
   Then a debrief card (top-right): score ring with a rolling score, rate scale (your count
   against the real band), rhythm / strength scales, sites, notes, logged findings.

   The beat schedule arrives obfuscated (k + s, decoded here); the heart rate, rhythm and
   strength are never sent: the server re-scores the raw taps and returns the truth.

   Lua → JS   open { locale, k, s, sites, start, countSeconds, absentAfter, minTime, tapWindow,
                     keys, patient }   result (outcome)   anchors { carotid, radial }
   JS → Lua   pulse:site { site }   pulse:finish { result }   pulse:abort   pulse:close
   ═══════════════════════════════════════════════════════════ */
(() => {
  const esc = NZA.esc, icon = NZA.icon, clamp = NZA.clamp;
  let LOC = {};
  const T = (k, fb, ...a) => { let s = LOC[k] !== undefined ? String(LOC[k]) : fb; a.forEach(v => { s = s.replace(/%[sd]/, v); }); return s; };
  const now = () => performance.now();
  const SWEEP = 4000;   // ms per revolution of the palpation scope

  NZ.addIcons({
    'as-neck': '<path d="M9 3.5c2.8-.8 6 .6 6.6 3.6.3 1.6-.2 2.6.6 3.6l1.3 1.6-1.6.6v2.2c0 1-.8 1.6-1.8 1.4l-1.6-.3V20"/><path d="M8 20v-4.5C6.2 14 5.4 11.8 5.6 9.4 5.8 6.6 7 4.2 9 3.5z"/><circle cx="10.5" cy="14.5" r="1.3"/>',
    'as-wrist': '<path d="M5 21v-6l-1.5-4.5c-.3-.9.6-1.6 1.4-1.1L7 11V5.2c0-.9 1.4-.9 1.4 0V10M8.4 9.5V4c0-.9 1.4-.9 1.4 0v6M9.8 9.6V4.6c0-.9 1.4-.9 1.4 0v5.6M11.2 10.2V6.5c0-.9 1.4-.9 1.4 0V15c0 2-1 3.5-2.5 4.4V21"/><circle cx="16.8" cy="16" r="1.3"/><path d="M19.5 13.5a4 4 0 0 1 0 5"/>',
    'as-ban': '<circle cx="12" cy="12" r="8.5"/><path d="M6 6l12 12"/>',
  });

  // Park-Miller stream, same as server NZA.Assess.Encode
  function decode(seed, str) {
    let x = Math.floor(seed) % 2147483647; if (x <= 0) x = 1;
    const out = [];
    for (let i = 0; i + 3 <= str.length; i += 3) {
      x = (x * 48271) % 2147483647;
      out.push(((parseInt(str.substr(i, 3), 16) - (x % 4096)) % 4096 + 4096) % 4096);
    }
    return out;
  }
  function encode(seed, values) {   // preview only
    let x = Math.floor(seed) % 2147483647; if (x <= 0) x = 1;
    return values.map(v => { x = (x * 48271) % 2147483647; v = clamp(Math.round(v), 0, 4095); return ((v + x % 4096) % 4096).toString(16).padStart(3, '0'); }).join('');
  }
  const codeLabel = c => ({ Space: 'Space', Enter: 'Enter', Escape: 'ESC' })[c] || String(c || '').replace(/^Key|^Digit/, '');

  // pulse wave at tau ms after the beat (peak ≈ 120 ms)
  function wave(tau, iv) {
    if (tau < 0) return 0;
    const k = clamp(iv / 800, 0.55, 1.2);
    const t = tau / k;
    if (t < 120) return Math.sin((Math.PI / 2) * (t / 120));
    const d = Math.exp(-(t - 120) / 170);
    return d + 0.22 * Math.exp(-(((t - 330) / 45) ** 2)) * d * 2.2;
  }
  // verdict glyphs: beat spacing (rhythm) and wave height (strength)
  const GLYPH = {
    1: 'M1 10h3l1.5-7 1.5 7h4l1.5-7 1.5 7h4l1.5-7 1.5 7h3',
    2: 'M1 10h2l1.5-7 1.5 7h8l1.5-7 1.5 7h.5l1.5-7 1.5 7h3',
    3: 'M1 10c2.2 0 2.2-2 4.4-2s2.2 2 4.4 2 2.2-2 4.4-2 2.2 2 4.4 2 2.2-2 4.4-2',
    4: 'M1 10c2.2 0 2.2-5 4.4-5s2.2 5 4.4 5 2.2-5 4.4-5 2.2 5 4.4 5 2.2-5 4.4-5',
    5: 'M1 12c2.2 0 2.2-11 4.4-11s2.2 11 4.4 11 2.2-11 4.4-11 2.2 11 4.4 11 2.2-11 4.4-11',
  };
  const ringSvg = (p, r, box, cls = '') => {
    const C = 2 * Math.PI * r;
    return `<svg class="rs ${cls}" viewBox="0 0 ${box} ${box}"><circle class="bg" cx="${box / 2}" cy="${box / 2}" r="${r}"/><circle class="fg" cx="${box / 2}" cy="${box / 2}" r="${r}" stroke-dasharray="${C.toFixed(2)}" stroke-dashoffset="${(C * (1 - clamp(p, 0, 1))).toFixed(2)}"/></svg>`;
  };

  NZA.app('pulse', {
    escClose: false,
    init(el) {
      this.el = el;
      el.innerHTML = '<div class="pz-vig"></div><div class="pz-deb-wrap"></div>';
      this.debWrap = el.querySelector('.pz-deb-wrap');
      this.onWheel = e => { if (!NZA.isOpen('pulse') || this.done) return; this.press(e.deltaY > 0 ? -0.035 : 0.035); e.preventDefault(); };
      window.addEventListener('wheel', this.onWheel, { passive: false });
    },

    open(d) {
      LOC = Object.assign({}, d.locale || {});
      this.d = d;
      this.keysCfg = Object.assign({ count: 'Space', none: 'KeyN', carotid: 'Digit1', radial: 'Digit2', submit: 'Enter' }, d.keys || {});
      const v = decode(d.k, d.s || '');
      const n = v[0] || 0;
      this.beats = [];
      let acc = 0;
      for (let i = 0; i < n; i++) {
        const iv = v[1 + i] || 800;
        acc += iv;
        this.beats.push({ t: acc, iv, c: (v[1 + n + i] || 0) / 1000, r: (v[1 + 2 * n + i] || 0) / 1000 });
      }
      this.total = acc;
      this.sites = d.sites || { carotid: { band: [0.35, 0.65] }, radial: { band: [0.25, 0.5], side: 'right' } };
      this.site = d.start === 'carotid' ? 'carotid' : 'radial';
      this.pressure = 0.12;
      this.palp = { carotid: 0, radial: 0 };
      this.none = { carotid: false, radial: false };
      this.step = 1;
      this.t0 = now();
      this.opened = now();
      this.samples = [];
      this.taps = []; this.tapMarks = [];
      this.count = null;
      this.rhythm = null; this.strength = null;
      this.inBand = 0; this.countFrames = 0;
      this.done = false; this.finished = false;
      this.lastFelt = -1; this.flashAt = -1e9;
      this.debWrap.innerHTML = '';
      this.el.classList.remove('pz-res');
      if (this.pp) this.pp.destroy();
      this.buildPanel();
      this.bindKeys();
      this.marker = NZA.ui.Marker('pulse', 'site', { anchor: this.site, dot: 'white', label: this.siteName() });
      this.marker.el.classList.add('pz-site');
      cancelAnimationFrame(this.raf);
      this.last = now();
      this.raf = requestAnimationFrame(t => this.frame(t));
    },
    close() {
      cancelAnimationFrame(this.raf);
      if (this.pp) { this.pp.destroy(); this.pp = null; }
      clearTimeout(this.minTimer);
      this.debWrap.innerHTML = '';
      this.cv = null; this.odo = null;
    },

    msg: {
      result(o) { NZA.apps.pulse.showResult(o || {}); },
    },

    /* ── keys (configurable codes) ── */
    bindKeys() {
      const k = this.keysCfg, self = this, map = {};
      map[k.count] = e => { if (!e.repeat) self.space(); };
      map[k.none] = () => self.noPulse();
      map[k.carotid] = () => self.digit(1);
      map[k.radial] = () => self.digit(2);
      map.Digit3 = () => self.digit(3); map.Digit4 = () => self.digit(4); map.Digit5 = () => self.digit(5);
      map[k.submit] = () => self.enter();
      map.KeyR = () => { if (self.step === 3 && !self.done) self.recount(); };
      map.ArrowUp = () => self.press(0.03);
      map.ArrowDown = () => self.press(-0.03);
      this.keys = map;
    },

    /* ── panel ── */
    buildPanel() {
      this.pp = NZA.ui.ProcPanel(this.el, {
        step: 1, total: 3, tag: T('pulse_tag', 'Pulse check'),
        steps: [T('step_locate', 'Locate the artery'), T('step_count', 'Count the beats'), T('step_judge', 'Describe it')],
        title: T('pulse_s1_title', 'Locate the artery'), text: this.siteText(),
        wide: this.dial(), stats: this.stats(), tools: this.tools(), hints: this.hints(),
        abort: { label: T('hold_stop', 'Hold to leave'), key: 'ESC', seconds: 1.0 },
        onAbort: () => this.abort(),
        onTool: key => this.tool(key),
      });
      // palpation scope + verdict picker live in the HUD slot (above the key legend)
      const box = document.createElement('div');
      box.className = 'pz-slot';
      box.innerHTML = `
        <div class="pz-scope">
          <div class="sc-dial"><canvas></canvas><div class="sc-c"><span class="hb">${icon('heart')}</span><span class="odoh"></span><small></small></div></div>
          <div class="sc-side">
            <span class="kick">${esc(T('under_fingers', 'Palpation scope'))}</span>
            <b class="cap"></b>
            <ul class="sc-l"></ul>
          </div>
        </div>
        <div class="pz-verdict"></div>`;
      this.pp.slot.prepend(box);
      this.slot = box;
      this.cv = box.querySelector('canvas');
      this.capEl = box.querySelector('.cap');
      this.scList = box.querySelector('.sc-l');
      this.centerLbl = box.querySelector('.sc-c small');
      this.odo = NZA.ui.FlipClock(box.querySelector('.odoh'), { value: '00', small: true, tone: 'teal' });
      box.querySelector('.pz-verdict').addEventListener('click', e => { const b = e.target.closest('button[data-n]'); if (b) this.digit(Number(b.dataset.n)); });
      this.renderSlot();
    },
    renderSlot() {
      if (!this.slot) return;
      this.slot.classList.toggle('judge', this.step === 3);
      this.slot.classList.toggle('counting', this.step === 2);
      this.centerLbl.textContent = this.step === 2 ? T('beats', 'beats') : T('cap_feel', 'feel');
      if (this.step === 3) this.renderVerdict();
      this.renderScopeList();
    },
    renderScopeList() {
      const good = (this.tapMarks || []).filter(t => t.good).length, bad = (this.tapMarks || []).length - good;
      const total = this.d.countSeconds || 15;
      const left = this.count ? Math.max(0, total - (now() - this.count.started) / 1000) : total;
      const row = (cls, l, v) => `<li class="${cls}"><i class="no"></i><span>${esc(l)}</span><b>${esc(v)}</b></li>`;
      this.scList.innerHTML = row('t-teal', T('sc_on', 'On a beat'), String(good)) + row(bad ? 't-red' : '', T('sc_off', 'Between beats'), String(bad)) +
        row(this.step === 2 ? 't-amber' : '', T('sc_window', 'Timer'), `${Math.ceil(left)} s`);
    },
    renderVerdict() {
      const opt = (n, label, on) => `<button data-n="${n}" class="${on ? 'on' : ''}"><kbd>${n}</kbd><svg class="gl" viewBox="0 0 26 14"><path d="${GLYPH[n]}"/></svg><span>${esc(label)}</span></button>`;
      this.slot.querySelector('.pz-verdict').innerHTML = `
        <div class="vr"><span class="vl">${esc(T('row_rhythm', 'Rhythm'))}</span><div class="opts n2">${opt(1, T('rhythm_regular', 'Regular'), this.rhythm === 'regular')}${opt(2, T('rhythm_irregular', 'Irregular'), this.rhythm === 'irregular')}</div></div>
        <div class="vr"><span class="vl">${esc(T('row_strength', 'Strength'))}</span><div class="opts n3">${opt(3, T('strength_weak', 'Weak'), this.strength === 'weak')}${opt(4, T('strength_normal', 'Normal'), this.strength === 'normal')}${opt(5, T('strength_bounding', 'Bounding'), this.strength === 'bounding')}</div></div>`;
    },
    siteName(site) {
      site = site || this.site;
      if (site === 'carotid') return T('site_carotid', 'Neck');
      return (this.sites.radial && this.sites.radial.side === 'left') ? T('site_radial_left', 'Left wrist') : T('site_radial_right', 'Right wrist');
    },
    siteText() {
      return this.site === 'carotid'
        ? T('pulse_s1_carotid', 'Slide two fingers into the groove beside the windpipe. Use **one side only** and press a little firmer.')
        : T('pulse_s1_radial', 'Two fingertips on the wrist, below the thumb. Build up the pressure until each beat taps back.');
    },
    pressWord(p) {
      if (p < 0.25) return T('press_light', 'Feather');
      if (p < 0.5) return T('press_moderate', 'Gentle');
      if (p < 0.75) return T('press_firm', 'Firm');
      return T('press_deep', 'Hard');
    },
    contact() {
      const p = this.pressure, f = this.feel(this.site, p), occ = this.occluded(this.site, p);
      if (p < 0.08) return { cap: T('cap_lift', 'Just touching'), tone: '' };
      if (occ) return { cap: T('cap_occluded', 'Too hard: the artery is flattened'), tone: 'amber' };
      if (f >= 0.85) return { cap: T('cap_best', 'Clear beat'), tone: 'teal' };
      if (f > 0.05) return { cap: T('cap_faint', 'Faint beat'), tone: '' };
      return { cap: T('cap_nothing', 'No beat yet'), tone: '' };
    },
    dial() {
      if (this.step === 3) {
        const r = this.rate();
        return { label: T('st_rate', 'Your rate'), value: String(r), unit: T('bpm', 'bpm'), meter: { value: clamp(r / 200, 0, 1), tone: '' },
          caption: T('cap_rate', '%s beats in %s s', this.taps.length, this.d.countSeconds || 15), captionTone: 'teal' };
      }
      const p = this.pressure, occ = this.occluded(this.site, p), c = this.contact();
      return {
        label: T('st_pressure', 'Pressure'), value: String(Math.round(p * 100)), unit: '%',
        meter: { value: p, tone: occ ? 'amber' : (c.tone === 'teal' ? '' : 'white') },
        caption: `${this.pressWord(p)} · ${c.cap}`, captionTone: c.tone,
      };
    },
    stats() {
      const s = [{ id: 'site', label: T('st_site', 'Site'), value: this.siteName(), small: true, tone: 'teal' }];
      if (this.step === 1) {
        s.push({ id: 'palp', label: T('st_palpating', 'Feeling for'), value: this.palp[this.site].toFixed(1), unit: 's' });
        s.push({ id: 'none', label: T('st_logged', 'Logged'), value: this.none.radial ? T('st_no_wrist', 'No wrist pulse') : '--', small: true, tone: this.none.radial ? 'amber' : '' });
      } else if (this.step === 2) {
        const left = this.count ? Math.max(0, (this.d.countSeconds || 15) - (now() - this.count.started) / 1000) : (this.d.countSeconds || 15);
        s.push({ id: 'count', label: T('st_counted', 'Beats'), value: this.taps.length });
        s.push({ id: 'left', label: T('st_left', 'Time left'), value: Math.ceil(left), unit: 's', tone: 'amber' });
      } else {
        const off = (this.tapMarks || []).filter(t => !t.good).length;
        s.push({ id: 'count', label: T('st_counted', 'Beats'), value: this.taps.length });
        s.push({ id: 'off', label: T('sc_off', 'Between beats'), value: off, tone: off ? 'amber' : '' });
      }
      return s;
    },
    hints() {
      if (this.step === 3) return [{ keys: ['1-2'], label: T('h_rhythm', 'rhythm') }, { keys: ['3-5'], label: T('h_strength', 'strength') }, { keys: ['R'], label: T('h_recount', 'count again') }];
      if (this.step === 2) return [{ keys: ['Space'], label: T('h_beat', 'on every beat') }, { keys: ['Scroll'], label: T('h_hold', 'keep the pressure') }];
      return [{ keys: ['Scroll'], label: T('h_press', 'finger pressure') }, { keys: ['↑', '↓'], label: T('h_fine', 'fine adjust') }];
    },
    tools() {
      const k = this.keysCfg;
      if (this.step === 3) {
        return [
          { key: 'R', label: T('tool_recount', 'Count again'), icon: 'rot-l' },
          { key: codeLabel(k.submit), label: T('submit', 'Submit'), icon: 'check', state: (this.rhythm && this.strength) ? 'active' : 'locked' },
        ];
      }
      const counting = this.step === 2;
      return [
        { key: 'Scroll', label: T('tool_pressure', 'Press'), icon: 'hand' },
        { key: codeLabel(k.count), label: counting ? T('tool_tap', 'Beat') : T('tool_count', 'Start timer'), icon: counting ? 'heart' : 'timer', state: counting ? 'active' : '' },
        { key: codeLabel(k.none), label: this.site === 'radial' ? T('tool_no_radial', 'Nothing at wrist') : T('tool_no_pulse', 'Nothing at neck'), icon: 'as-ban', state: (this.none[this.site] || counting) ? 'locked' : '' },
        { key: codeLabel(k.carotid), label: T('site_carotid', 'Neck'), sub: T('site_carotid_sub', 'carotid'), icon: 'as-neck', state: this.site === 'carotid' ? 'active' : (counting ? 'locked' : '') },
        { key: codeLabel(k.radial), label: T('site_radial', 'Wrist'), sub: T('site_radial_sub', 'radial'), icon: 'as-wrist', state: this.site === 'radial' ? 'active' : (counting || this.none.radial ? 'locked' : '') },
      ];
    },
    refresh(full) {
      if (!this.pp) return;
      if (full) this.pp.set({ wide: this.dial(), stats: this.stats(), tools: this.tools(), hints: this.hints() });
      else this.pp.set({ wide: this.dial(), stats: this.stats() });
      if (full) this.renderSlot();
    },
    tool(key) {
      const k = this.keysCfg;
      if (key === codeLabel(k.count)) return this.space();
      if (key === codeLabel(k.none)) return this.noPulse();
      if (key === codeLabel(k.submit)) return this.enter();
      if (key === 'R') return this.step === 3 ? this.recount() : null;
      if (/^[1-5]$/.test(key)) return this.digit(Number(key));
      return null;
    },

    /* ── physics of feeling ── */
    feel(site, p) {
      const b = (this.sites[site] && this.sites[site].band) || [0.3, 0.6];
      const lo = b[0], hi = b[1], c = (lo + hi) / 2, hw = Math.max(0.02, (hi - lo) / 2);
      if (p < lo - 0.1) return 0;
      if (p < lo) return ((p - (lo - 0.1)) / 0.1) * 0.3;
      if (p <= hi) return 0.35 + 0.65 * Math.pow(clamp(1 - Math.abs(p - c) / hw, 0, 1), 0.6);
      if (p < hi + 0.08) return 0.3 * (1 - (p - hi) / 0.08);
      return 0;
    },
    occluded(site, p) { const b = (this.sites[site] && this.sites[site].band) || [0.3, 0.6]; return p > b[1] + 0.06; },
    beatAt(ms) {
      // returns { idx, t } of the last beat at or before ms in the cycled schedule
      if (!this.total || !this.beats.length) return null;
      const cyc = Math.floor(ms / this.total), off = ms - cyc * this.total;
      let lo = 0, hi = this.beats.length - 1, idx = -1;
      while (lo <= hi) { const m = (lo + hi) >> 1; if (this.beats[m].t <= off) { idx = m; lo = m + 1; } else hi = m - 1; }
      if (idx < 0) return { b: this.beats[this.beats.length - 1], t: cyc * this.total - this.total + this.beats[this.beats.length - 1].t, next: this.beats[0] };
      return { b: this.beats[idx], t: cyc * this.total + this.beats[idx].t, next: this.beats[idx + 1] || this.beats[0], idx };
    },
    signal(ms, site, p) {
      const f = this.feel(site, p);
      const key = site === 'carotid' ? 'c' : 'r';
      let v = 0;
      const cur = this.beatAt(ms);
      if (cur) {
        v += cur.b[key] * f * wave(ms - cur.t, cur.b.iv);
        const prev = this.beatAt(cur.t - 1);
        if (prev && prev.t < cur.t) v += prev.b[key] * f * wave(ms - prev.t, prev.b.iv) * 0.6;
      }
      const n = Math.sin(ms * 0.031) * 0.5 + Math.sin(ms * 0.0173 + 1.3) * 0.35 + Math.sin(ms * 0.077) * 0.15;
      const tremor = p > 0.08 ? 0.035 + (this.occluded(site, p) ? 0.01 : 0) : 0.015;
      return v + n * tremor;
    },
    feltNear(ms, site, tol) {
      const key = site === 'carotid' ? 'c' : 'r';
      const f = this.feel(site, this.pressure);
      const cur = this.beatAt(ms - 120 + tol);
      const cands = [];
      if (cur) { cands.push(cur); const prev = this.beatAt(cur.t - 1); if (prev) cands.push(prev); }
      return cands.some(c => Math.abs((ms - 120) - c.t) <= tol && c.b[key] * f >= 0.12);
    },

    /* ── input ── */
    press(dp) {
      if (this.done || this.step > 3) return;
      this.pressure = clamp(this.pressure + dp, 0, 1);
      if (dp && Math.random() < 0.6) NZA.audio.tick();
    },
    setSite(site) {
      if (this.step === 2 || this.done) return;
      if (site === 'radial' && this.none.radial) return this.pp.flash('warn', T('radial_marked', 'The wrist is already logged as empty.'));
      if (this.site === site) return;
      this.site = site;
      this.pressure = 0.12;
      this.marker.set({ anchor: site, label: this.siteName() });
      if (this.step === 1) this.pp.set({ text: this.siteText() });
      this.refresh(true);
      NZA.audio.click(700);
      NZA.post('pulse:site', { site });
    },
    digit(n) {
      if (this.done) return;
      if (this.step === 3) {
        if (n === 1) this.rhythm = 'regular';
        else if (n === 2) this.rhythm = 'irregular';
        else this.strength = ['weak', 'normal', 'bounding'][n - 3];
        NZA.audio.click(820);
        this.refresh(true);
        return;
      }
      if (n === 1) this.setSite('carotid');
      else if (n === 2) this.setSite('radial');
    },
    space() {
      if (this.done) return;
      const ms = now() - this.t0;
      if (this.step === 1) {
        this.step = 2;
        this.count = { started: now(), startMs: ms };
        this.taps = []; this.tapMarks = []; this.inBand = 0; this.countFrames = 0;
        this.pp.set({ step: 2, title: T('pulse_s2_title', 'Count the beats'), text: T('pulse_s2_text', 'Hit {Space} on each beat. Hold your pressure steady while the timer runs.') });
        this.pp.flash('ok', T('tip_2', '15 seconds × 4 = beats per minute. Do not stop early.'), 3600);
        this.odo.set('00');
        this.refresh(true);
        NZA.audio.beep(1040, 70, 0.06);
        return;
      }
      if (this.step === 2) {
        const good = this.feltNear(ms, this.site, (this.d.tapWindow || 0.25) * 1000);
        this.taps.push(Math.round(ms));
        this.tapMarks.push({ ms, good });
        if (good) NZA.audio.tone(1250, 45, { vol: 0.06, type: 'triangle' }); else NZA.audio.tone(240, 70, { vol: 0.07, type: 'triangle' });
        this.odo.set(String(this.taps.length).padStart(2, '0'));
        this.renderScopeList();
        this.refresh(false);
      }
    },
    noPulse() {
      if (this.done || this.step !== 1) return;
      const need = this.d.absentAfter || 5;
      const felt = this.palp[this.site];
      if (felt < need) return this.pp.flash('warn', T('keep_feeling', 'Feel for another %s s before you rule it out.', (need - felt).toFixed(1)));
      if (this.site === 'radial') {
        this.none.radial = true;
        this.pp.flash('ok', T('no_radial_noted', 'Logged: **nothing at the wrist**. Move to the neck.'), 3200);
        NZA.audio.click(600);
        this.setSite('carotid');
        this.refresh(true);
        return;
      }
      this.none.carotid = true;
      this.pp.flash('bad', T('no_pulse_called', 'Nothing at the neck.'), 0);
      this.submit();
    },
    recount() {
      this.step = 1; this.count = null; this.taps = []; this.tapMarks = [];
      this.rhythm = null; this.strength = null;
      this.odo.set('00');
      this.pp.set({ step: 1, title: T('pulse_s1_title', 'Locate the artery'), text: this.siteText() });
      this.refresh(true);
    },
    enter() {
      if (this.done) { if (this.finished) this.closeNow(); return; }
      if (this.step !== 3) return;
      if (!this.rhythm || !this.strength) return this.pp.flash('warn', T('judge_first', 'Set the rhythm **and** the strength first.'));
      this.submit();
    },
    rate() { return Math.round(this.taps.length * 60 / (this.d.countSeconds || 15)); },

    submit() {
      const left = (this.d.minTime ?? 8) - (now() - this.opened) / 1000;
      if (left > 0) {
        this.pp.flash('warn', T('too_fast', 'Stay with the patient a little longer.'), 0);
        clearTimeout(this.minTimer);
        this.minTimer = setTimeout(() => this.submit(), left * 1000 + 250);
        return;
      }
      this.done = true;
      const result = {
        nonce: Math.floor(Math.random() * 1e9),
        site: this.site,
        countStart: this.count ? Math.round(this.count.startMs) : -1,
        countMs: this.count ? Math.round(Math.min((this.d.countSeconds || 15) * 1000, now() - this.count.started)) : 0,
        taps: this.taps.slice(0, 240),
        rhythm: this.rhythm, strength: this.strength,
        none: this.none,
        pressure: this.countFrames ? this.inBand / this.countFrames : 0,
        palp: { carotid: Math.round(this.palp.carotid * 10) / 10, radial: Math.round(this.palp.radial * 10) / 10 },
        score: 0,
      };
      this.pp.set({ title: T('checking', 'Scoring your findings…'), titleTone: '', text: '', tools: [] });
      NZA.post('pulse:finish', result).then(r => { if (r && r.outcome) this.showResult(r.outcome); });
    },
    abort() {
      if (this.finished) return this.closeNow();
      this.done = true;
      NZA.post('pulse:abort', {});
      NZA.close('pulse');
    },
    closeNow() { NZA.close('pulse'); },

    /* ── frame ── */
    frame(t) {
      if (!NZA.isOpen('pulse')) return;
      const dt = Math.min(0.1, (t - this.last) / 1000); this.last = t;
      const ms = t - this.t0;
      const site = this.site, p = this.pressure;
      const v = this.signal(ms, site, p);
      this.samples.push({ ms, v, occ: this.occluded(site, p) });
      while (this.samples.length && ms - this.samples[0].ms > SWEEP) this.samples.shift();
      if (!this.done) {
        if (p > 0.08 && this.step === 1) this.palp[site] += dt;
        if (this.step === 2 && this.count) {
          this.countFrames += dt;
          if (this.feel(site, p) >= 0.35) this.inBand += dt;
          if (now() - this.count.started >= (this.d.countSeconds || 15) * 1000) this.toJudge();
        }
        // in-world fingertip throb on a felt beat
        const cur = this.beatAt(ms - 120);
        const key = site === 'carotid' ? 'c' : 'r';
        if (cur && cur.t !== this.lastFelt && ms - 120 - cur.t < 80) {
          this.lastFelt = cur.t;
          if (cur.b[key] * this.feel(site, p) >= 0.12) {
            this.flashAt = ms;
            if (this.marker) { this.marker.el.classList.remove('pz-beat'); void this.marker.el.offsetWidth; this.marker.el.classList.add('pz-beat'); }
            if (this.slot) { this.slot.classList.remove('beat'); void this.slot.offsetWidth; this.slot.classList.add('beat'); }
          }
        }
      }
      this.draw(ms);
      this.statT = (this.statT || 0) + dt;
      if (this.statT > 0.12 && !this.finished && !this.done) { this.statT = 0; this.refreshStats(); }
      this.raf = requestAnimationFrame(x => this.frame(x));
    },
    refreshStats() {
      if (!this.pp) return;
      this.pp.set({ wide: this.dial(), stats: this.stats() });
      const c = this.contact();
      if (this.capEl.textContent !== c.cap) { this.capEl.textContent = c.cap; this.capEl.className = `cap t-${c.tone || 'base'}`; }
      if (this.step === 2) this.renderScopeList();
    },
    toJudge() {
      this.step = 3;
      this.pp.set({ step: 3, tag: T('pulse_tag', 'Pulse check'), title: T('pulse_s3_title', 'Describe it'), text: T('pulse_s3_text', 'Steady or uneven? Faint, normal or pounding? Set both, then {Enter}. {R} counts again.') });
      this.pp.flash('ok', T('tip_3', 'Uneven with no pattern: think atrial fibrillation. Faint and racing: think blood loss.'), 5200);
      this.refresh(true);
      NZA.audio.beep(880, 70, 0.06);
    },
    // polar palpation scope: one revolution = SWEEP ms, the beat lifts the trace outwards
    draw(ms) {
      const cv = this.cv; if (!cv || this.step === 3) return;
      const { w, h, scale } = NZA.fitCanvas(cv);
      const c = cv.getContext('2d');
      c.clearRect(0, 0, w, h);
      const cx = w / 2, cy = h / 2, R = Math.min(w, h) / 2 - 3 * scale, r0 = R * 0.56, amp = R * 0.36;
      const ang = m => -Math.PI / 2 + ((((m % SWEEP) + SWEEP) % SWEEP) / SWEEP) * Math.PI * 2;
      // disc
      const bg = c.createRadialGradient(cx, cy, R * 0.1, cx, cy, R);
      bg.addColorStop(0, '#0a1a18'); bg.addColorStop(0.7, '#040a09'); bg.addColorStop(1, '#020404');
      c.fillStyle = bg; c.beginPath(); c.arc(cx, cy, R, 0, Math.PI * 2); c.fill();
      // grid rings + spokes
      c.lineWidth = 1;
      [0.32, 0.56, 0.74, 0.92].forEach((k, i) => { c.strokeStyle = i === 1 ? 'rgba(15,212,196,.22)' : 'rgba(15,212,196,.08)'; c.beginPath(); c.arc(cx, cy, R * k, 0, Math.PI * 2); c.stroke(); });
      c.strokeStyle = 'rgba(15,212,196,.07)';
      for (let i = 0; i < 12; i++) { const a = (i / 12) * Math.PI * 2; c.beginPath(); c.moveTo(cx + Math.cos(a) * R * 0.32, cy + Math.sin(a) * R * 0.32); c.lineTo(cx + Math.cos(a) * R * 0.98, cy + Math.sin(a) * R * 0.98); c.stroke(); }
      // rim ticks
      c.strokeStyle = 'rgba(15,212,196,.35)';
      for (let i = 0; i < 60; i++) { const a = (i / 60) * Math.PI * 2, l = i % 5 ? 3 : 6; c.beginPath(); c.moveTo(cx + Math.cos(a) * R, cy + Math.sin(a) * R); c.lineTo(cx + Math.cos(a) * (R - l * scale), cy + Math.sin(a) * (R - l * scale)); c.stroke(); }
      // sweep fan
      const a0 = ang(ms);
      for (let i = 0; i < 18; i++) {
        const a = a0 - (i / 18) * 0.9;
        c.fillStyle = `rgba(15,212,196,${(0.10 * (1 - i / 18)).toFixed(3)})`;
        c.beginPath(); c.moveTo(cx, cy); c.arc(cx, cy, R * 0.96, a - 0.05, a); c.closePath(); c.fill();
      }
      // count window progress on the rim
      if (this.count) {
        const total = (this.d.countSeconds || 15) * 1000, f = clamp((now() - this.count.started) / total, 0, 1);
        c.strokeStyle = 'rgba(243,195,90,.85)'; c.lineWidth = 3 * scale; c.lineCap = 'round';
        c.beginPath(); c.arc(cx, cy, R + 0.5 * scale, -Math.PI / 2, -Math.PI / 2 + f * Math.PI * 2); c.stroke();
        c.lineCap = 'butt';
      }
      // trace (fades with age)
      const occ = this.samples.length && this.samples[this.samples.length - 1].occ;
      const col = occ ? '243,195,90' : '15,212,196';
      c.lineWidth = 1.9 * scale; c.lineJoin = 'round';
      for (let i = 1; i < this.samples.length; i++) {
        const s0 = this.samples[i - 1], s1 = this.samples[i];
        const age = (ms - s1.ms) / SWEEP;
        const al = Math.max(0, 1 - age);
        const ra = r0 + clamp(s0.v, -0.2, 1.3) * amp, rb = r0 + clamp(s1.v, -0.2, 1.3) * amp;
        const aa = ang(s0.ms), ab = ang(s1.ms);
        if (Math.abs(ab - aa) > 1) continue;
        c.strokeStyle = `rgba(${col},${(al * 0.95).toFixed(3)})`;
        c.beginPath(); c.moveTo(cx + Math.cos(aa) * ra, cy + Math.sin(aa) * ra); c.lineTo(cx + Math.cos(ab) * rb, cy + Math.sin(ab) * rb); c.stroke();
      }
      // pen
      if (this.samples.length) {
        const s = this.samples[this.samples.length - 1], r = r0 + clamp(s.v, -0.2, 1.3) * amp;
        c.shadowColor = `rgb(${col})`; c.shadowBlur = 10 * scale; c.fillStyle = '#fff';
        c.beginPath(); c.arc(cx + Math.cos(a0) * r, cy + Math.sin(a0) * r, 2.8 * scale, 0, Math.PI * 2); c.fill();
        c.shadowBlur = 0;
      }
      // taps on the rim
      (this.tapMarks || []).forEach(tm => {
        const age = (ms - tm.ms) / SWEEP; if (age > 1) return;
        const a = ang(tm.ms), r = R - 9 * scale;
        c.fillStyle = tm.good ? `rgba(15,212,196,${1 - age * 0.7})` : `rgba(255,90,95,${1 - age * 0.7})`;
        c.beginPath(); c.arc(cx + Math.cos(a) * r, cy + Math.sin(a) * r, 3.2 * scale, 0, Math.PI * 2); c.fill();
      });
    },

    /* ── debrief ── */
    showResult(o) {
      if (this.finished) return;
      this.finished = true;
      this.el.classList.add('pz-res');
      const r = o.rows || {};
      const score = clamp(Math.round(o.score ?? 0), 0, 100);
      const tone = score >= 75 ? 'teal' : score >= 50 ? 'amber' : 'red';
      const verdict = score >= 90 ? T('vd_5', 'Spot on') : score >= 75 ? T('vd_4', 'Solid read') : score >= 55 ? T('vd_3', 'Close call') : score >= 35 ? T('vd_2', 'Off the mark') : T('vd_1', 'Missed it');
      const rate = r.rate || {}, rh = r.rhythm || {}, st = r.strength || {}, site = r.site || {};
      const calls = [rate.ok, rh.ok, st.ok].filter(x => x !== undefined && x !== null);
      const right = calls.filter(Boolean).length;
      const mark = ok => (ok === true ? `<span class="mk ok">${icon('check')}</span>` : ok === false ? `<span class="mk no">${icon('x')}</span>` : '<span class="mk"></span>');
      // rate scale 0..max with the real value band and your count
      const you = parseFloat(rate.you), pat = parseFloat(rate.patient);
      const max = Math.max(160, Math.ceil(Math.max(isNaN(you) ? 0 : you, isNaN(pat) ? 0 : pat) / 40) * 40 + 40);
      const X = v => `${clamp(v / max, 0, 1) * 100}%`;
      const ticks = Array.from({ length: max / 40 + 1 }, (_, i) => `<i style="left:${X(i * 40)}"><em>${i * 40}</em></i>`).join('');
      const rateBar = `<div class="rs-bar">${ticks}${!isNaN(pat) ? `<span class="band" style="left:${X(Math.max(0, pat - 10))};width:calc(${X(Math.min(max, pat + 10))} - ${X(Math.max(0, pat - 10))})"></span><span class="tru" style="left:${X(pat)}"></span>` : ''}${!isNaN(you) ? `<span class="you ${rate.ok ? 'ok' : 'no'}" style="left:${X(you)}"></span>` : ''}</div>`;
      const scale = (opts, youV, patV) => {
        const list = opts.slice();
        if (patV && !list.includes(patV)) list.push(patV);
        return `<div class="sc">${list.map(op => `<span class="${op === patV ? 'tru' : ''} ${op === youV ? 'you' : ''}">${op === patV ? icon('check') : ''}${esc(op)}${op === youV ? `<em>${esc(T('you_short', 'you'))}</em>` : ''}</span>`).join('')}</div>`;
      };
      const fb = (o.feedback || []).map(f => `<li class="t-${esc(f.tone || 'info')}"><i></i><span>${esc(f.text)}</span></li>`).join('');
      const rec = (o.recorded || []).map(x => `<span class="lg">${icon('clipboard')}${esc(x)}</span>`).join('');
      const siteDot = (on, label) => `<span class="sd ${on ? 'on' : 'off'}"><i></i>${esc(label)}<em>${esc(on ? T('felt', 'felt') : T('not_felt', 'not felt'))}</em></span>`;
      this.debWrap.innerHTML = `
        <section class="pz-deb t-${tone}">
          <header class="dh">
            <div class="sr">${ringSvg(0, 38, 88)}<div class="in"><span class="odoh"></span><small>${esc(T('score', 'Score'))}</small></div></div>
            <div class="dt"><span class="kick">${esc(o.title || T('pulse_result_title', 'Pulse debrief'))}</span><h3>${esc(verdict)}</h3>
              <p>${esc(T('result_sub', '%s s with the patient', o.seconds ?? 0))}${calls.length ? ` · ${esc(T('calls_right', '%s of %s calls right', right, calls.length))}` : ''}</p></div>
          </header>
          ${o.error ? `<p class="err">${icon('alert')}${esc(o.msg || '')}</p>` : `
          <div class="rows">
            <div class="rw"><div class="rl"><span>${esc(T('row_rate', 'Rate'))}</span>${mark(rate.ok)}</div>
              <div class="rv"><div class="nums"><b>${esc(rate.you ?? '--')}</b><i>${esc(T('vs', 'vs'))}</i><b class="t">${esc(rate.patient ?? '--')}</b><em>${esc(rate.unit || T('bpm', 'bpm'))}</em></div>${rateBar}
              ${rate.apical ? `<div class="ap">${icon('alert')}${esc(T('apical', 'Heart %s bpm: some beats never reach the wrist', rate.apical))}</div>` : ''}</div></div>
            <div class="rw"><div class="rl"><span>${esc(T('row_rhythm', 'Rhythm'))}</span>${mark(rh.ok)}</div><div class="rv">${scale([T('rhythm_regular', 'Regular'), T('rhythm_irregular', 'Irregular')], rh.you, rh.patient)}</div></div>
            <div class="rw"><div class="rl"><span>${esc(T('row_strength', 'Strength'))}</span>${mark(st.ok)}</div><div class="rv">${scale([T('strength_weak', 'Weak'), T('strength_normal', 'Normal'), T('strength_bounding', 'Bounding')], st.you, st.patient)}</div></div>
            <div class="rw"><div class="rl"><span>${esc(T('row_site', 'Sites'))}</span></div><div class="rv sites">${siteDot(site.carotid, T('site_carotid', 'Neck'))}${siteDot(site.radial, T('site_radial', 'Wrist'))}${site.you ? `<span class="cnt">${esc(T('counted_at', 'counted at %s', site.you))}</span>` : ''}</div></div>
          </div>`}
          ${fb ? `<ul class="fb">${fb}</ul>` : ''}
          ${rec ? `<div class="rec"><span class="kick">${esc(T('recorded', 'Logged to chart'))}</span>${rec}</div>` : ''}
        </section>`;
      const host = this.debWrap.querySelector('.odoh');
      const odo = NZA.ui.FlipClock(host, { value: '00', tone, small: true });
      requestAnimationFrame(() => requestAnimationFrame(() => {
        const fg = this.debWrap.querySelector('.sr .fg');
        if (fg) { const C = 2 * Math.PI * 38; fg.style.strokeDashoffset = (C * (1 - score / 100)).toFixed(2); }
        odo.set(String(score).padStart(2, '0'));
      }));
      if (score >= 75) NZA.audio.success(); else NZA.audio.fail();
      this.slot && this.slot.classList.add('gone');
      this.pp.complete({ title: T('complete', 'Check finished'), text: T('complete_text', 'Your debrief is on the right. {Enter} when you are ready.'), label: T('done', 'Done'), onDone: () => this.closeNow() });
      const mine = [`${this.rate()} ${T('bpm', 'bpm')}`, this.rhythm ? T(`rhythm_${this.rhythm}`, this.rhythm) : '', this.strength ? T(`strength_${this.strength}`, this.strength) : ''].filter(Boolean).join(' · ');
      this.pp.flash(tone === 'teal' ? 'ok' : tone === 'amber' ? 'warn' : 'bad', T('your_call', 'Your call: %s', this.none.carotid ? T('finding_pulseless', 'No pulse') : mine), 0);
      // the debrief owns the right edge now: drop the cancel ring (Esc still closes)
      this.pp.set({ abort: false, hints: [{ keys: ['Enter'], label: T('h_done', 'done') }, { keys: ['ESC'], label: T('h_close', 'close') }] });
    },

    /* ── browser preview ── */
    preview() {
      const body = NZAAssess.body({ focus: 'wrist', wounds: ['chest'] });
      // demo patient: 124 bpm sinus tachycardia, weak (SBP 86), radial present
      const hr = 124, beats = [], seed = 918273;
      let tt = 0;
      while (tt < 90000) { const iv = 60000 / hr * (1 + (Math.random() - 0.5) * 0.06); const c = 0.4 * (0.92 + Math.random() * 0.16); beats.push([Math.round(iv), c, c * 0.85]); tt += iv; }
      const vals = [beats.length, ...beats.map(b => b[0]), ...beats.map(b => b[1] * 1000), ...beats.map(b => b[2] * 1000)];
      const data = {
        k: seed, s: encode(seed, vals), start: 'radial', countSeconds: 15, absentAfter: 5, minTime: 8, tapWindow: 0.25,
        sites: { carotid: { band: [0.36, 0.58] }, radial: { band: [0.24, 0.4], side: 'right' } },
        patient: { name: 'Michael Garcia', sex: 'm' }, locale: {},
      };
      NZA.demo('pulse', data);
      NZAAssess.feed('pulse', ['carotid', 'radial'], { map: () => ({ carotid: body.at('carotid'), radial: body.at('wrist') }) });
      this.pressure = 0.31;
      NZA.mock('pulse:finish', res => {
        const counted = Math.round(res.taps.length * 60 / (this.d.countSeconds || 15));
        setTimeout(() => this.showResult({
          score: 64, grade: 'C', seconds: Math.round((now() - this.opened) / 1000), title: 'Pulse debrief',
          rows: { rate: { you: String(counted), patient: '124', unit: 'bpm', ok: Math.abs(counted - 124) <= 10 },
            rhythm: { you: res.rhythm === 'irregular' ? 'Irregular' : 'Regular', patient: 'Regular', ok: res.rhythm !== 'irregular' },
            strength: { you: ({ weak: 'Weak', normal: 'Normal', bounding: 'Bounding' })[res.strength] || '--', patient: 'Weak', ok: res.strength === 'weak' },
            site: { you: 'Right wrist', carotid: true, radial: true } },
          feedback: [{ tone: Math.abs(counted - 124) <= 10 ? 'ok' : 'bad', text: `Your count: ${counted} bpm. Real rate: 124.` }, { tone: 'warn', text: '3 taps landed between beats.' }, { tone: 'warn', text: 'Faint and racing: find the bleeding.' }],
          recorded: ['Weak, fast pulse'],
        }), 300);
        return { ok: true };
      });
    },
  });
})();
