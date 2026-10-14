/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · Check Pulse (app 'pulse')        module: assess
   3 steps on the shared procedure panel (NZA.ui.ProcPanel):
     1 Find the pulse   pick the site (carotid / radial), scroll = finger pressure. The
                        "under your fingers" trace only shows beats inside the right pressure
                        band (too light = nothing, too hard = occluded). N = no pulse here.
     2 Count            Space starts a 15 s count; tap Space on every beat you feel.
     3 Judge            rhythm (regular / irregular) and strength (weak / normal / bounding).
   Then the result card (grade, your finding vs the patient, feedback, findings recorded).

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

  NZA.app('pulse', {
    escClose: false,
    init(el) {
      this.el = el;
      el.innerHTML = '<div class="pz-result-wrap"></div>';
      this.resultWrap = el.querySelector('.pz-result-wrap');
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
      this.taps = [];
      this.count = null;
      this.rhythm = null; this.strength = null;
      this.inBand = 0; this.countFrames = 0;
      this.done = false;
      this.lastFelt = -1;
      this.resultWrap.innerHTML = '';
      if (this.pp) this.pp.destroy();
      this.buildPanel();
      this.bindKeys();
      this.marker = NZA.ui.Marker('pulse', 'site', { anchor: this.site, dot: 'white', label: '' });
      this.marker.el.classList.add('pz-site');
      cancelAnimationFrame(this.raf);
      this.last = now();
      this.raf = requestAnimationFrame(t => this.frame(t));
    },
    close() {
      cancelAnimationFrame(this.raf);
      if (this.pp) { this.pp.destroy(); this.pp = null; }
      clearTimeout(this.minTimer);
      this.resultWrap.innerHTML = '';
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
        step: 1, total: 3, tag: T('pulse_tag', 'Pulse'),
        title: T('pulse_s1_title', 'Find the pulse'), text: this.siteText(),
        stats: this.stats(),
        tools: this.tools(),
        hints: [],
        abort: { label: T('hold_stop', 'Hold to stop'), key: 'ESC', seconds: 1.0 },
        onAbort: () => this.abort(),
        onTool: key => this.tool(key),
      });
      this.tip = document.createElement('div');
      this.tip.className = 'pz-tip';
      this.pp.el.querySelector('.pp-left').appendChild(this.tip);
      this.setTip(1);
      const right = this.pp.el.querySelector('.pp-right');
      const box = document.createElement('div');
      box.className = 'pz-feel';
      box.innerHTML = `<div class="pz-fh"><span class="l">${esc(T('under_fingers', 'Under your fingers'))}</span><span class="cap"></span></div><canvas class="pz-cv"></canvas>`;
      right.appendChild(box);
      this.cv = box.querySelector('canvas');
      this.cap = box.querySelector('.cap');
    },
    setTip(step) {
      const tips = {
        1: T('tip_1', 'No radial pulse usually means the systolic pressure is under about 80.'),
        2: T('tip_2', 'Count the full 15 seconds: the rate is the beats times four.'),
        3: T('tip_3', 'Irregularly irregular = atrial fibrillation. Weak and fast = think shock.'),
      };
      if (this.tip) this.tip.innerHTML = `${icon('info')}<span>${esc(tips[step] || '')}</span>`;
    },
    siteName(site) {
      site = site || this.site;
      if (site === 'carotid') return T('site_carotid', 'Carotid');
      return (this.sites.radial && this.sites.radial.side === 'left') ? T('site_radial_left', 'Left radial') : T('site_radial_right', 'Right radial');
    },
    siteText() {
      return this.site === 'carotid'
        ? T('pulse_s1_carotid', 'Two fingers beside the windpipe, under the jaw. Press firmly but not too hard, and **one side only**.')
        : T('pulse_s1_radial', 'Thumb side of the wrist, just above the crease. Press gently: too hard and it disappears.');
    },
    pressWord(p) {
      if (p < 0.25) return T('press_light', 'Light');
      if (p < 0.5) return T('press_moderate', 'Moderate');
      if (p < 0.75) return T('press_firm', 'Firm');
      return T('press_deep', 'Deep');
    },
    stats() {
      const p = this.pressure;
      const s = [
        { id: 'site', label: T('st_site', 'Site'), value: this.siteName(), small: true },
        { id: 'press', label: T('st_pressure', 'Pressure'), value: this.pressWord(p), small: true, tone: p >= 0.75 ? 'amber' : '', meter: { value: p, tone: p >= 0.75 ? 'amber' : 'white', segs: true } },
      ];
      if (this.step === 1) s.push({ id: 'palp', label: T('st_palpating', 'Palpating'), value: this.palp[this.site].toFixed(1), unit: 's', meter: { value: clamp(this.palp[this.site] / Math.max(1, this.d.absentAfter || 5), 0, 1), tone: 'white' } });
      else if (this.step === 2) {
        const left = this.count ? Math.max(0, (this.d.countSeconds || 15) - (now() - this.count.started) / 1000) : (this.d.countSeconds || 15);
        s.push({ id: 'count', label: T('st_counted', 'Counted'), value: this.taps.length, unit: T('beats', 'beats'), meter: { value: 1 - left / (this.d.countSeconds || 15), tone: 'teal' } });
      } else s.push({ id: 'rate', label: T('st_rate', 'Your rate'), value: this.rate(), unit: T('bpm', 'bpm'), tone: 'teal' });
      return s;
    },
    tools() {
      const k = this.keysCfg;
      if (this.step === 3) {
        const t = (key, label, on) => ({ key, label, state: on ? 'active' : '' });
        return [
          t('1', T('rhythm_regular', 'Regular'), this.rhythm === 'regular'),
          t('2', T('rhythm_irregular', 'Irregular'), this.rhythm === 'irregular'),
          t('3', T('strength_weak', 'Weak'), this.strength === 'weak'),
          t('4', T('strength_normal', 'Normal'), this.strength === 'normal'),
          t('5', T('strength_bounding', 'Bounding'), this.strength === 'bounding'),
          { key: codeLabel(k.submit), label: T('submit', 'Submit'), state: (this.rhythm && this.strength) ? 'active' : 'locked' },
        ];
      }
      const counting = this.step === 2;
      return [
        { key: 'Scroll', label: T('tool_pressure', 'Pressure') },
        { key: codeLabel(k.count), label: counting ? T('tool_tap', 'Tap each beat') : T('tool_count', 'Start count'), state: counting ? 'active' : '' },
        { key: codeLabel(k.none), label: this.site === 'radial' ? T('tool_no_radial', 'No radial pulse') : T('tool_no_pulse', 'No pulse'), state: (this.none[this.site] || counting) ? 'locked' : '' },
        { key: codeLabel(k.carotid), label: T('site_carotid', 'Carotid'), state: this.site === 'carotid' ? 'active' : (counting ? 'locked' : '') },
        { key: codeLabel(k.radial), label: T('site_radial', 'Radial'), state: this.site === 'radial' ? 'active' : (counting || this.none.radial ? 'locked' : '') },
      ];
    },
    refresh(full) {
      if (!this.pp) return;
      if (full) this.pp.set({ stats: this.stats(), tools: this.tools() });
      else this.pp.set({ stats: this.stats() });
    },
    tool(key) {
      const k = this.keysCfg;
      if (key === codeLabel(k.count)) return this.space();
      if (key === codeLabel(k.none)) return this.noPulse();
      if (key === codeLabel(k.submit)) return this.enter();
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
      if (site === 'radial' && this.none.radial) return this.pp.flash('warn', T('radial_marked', 'You already called no radial pulse.'));
      if (this.site === site) return;
      this.site = site;
      this.pressure = 0.12;
      this.marker.set({ anchor: site });
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
        this.setTip(2);
        this.pp.set({ step: 2, title: T('pulse_s2_title', 'Count the beats'), text: T('pulse_s2_text', 'Tap {Space} every time you feel a beat. Keep the pressure where you feel it best.') });
        this.refresh(true);
        NZA.audio.beep(1040, 70, 0.06);
        return;
      }
      if (this.step === 2) {
        const good = this.feltNear(ms, this.site, (this.d.tapWindow || 0.25) * 1000);
        this.taps.push(Math.round(ms));
        this.tapMarks.push({ ms, good });
        if (good) NZA.audio.tone(1250, 45, { vol: 0.06, type: 'triangle' }); else NZA.audio.tone(240, 70, { vol: 0.07, type: 'triangle' });
        this.refresh(false);
      }
    },
    noPulse() {
      if (this.done || this.step !== 1) return;
      const need = this.d.absentAfter || 5;
      const felt = this.palp[this.site];
      if (felt < need) return this.pp.flash('warn', T('keep_feeling', 'Keep feeling for %s more seconds before you call it.', (need - felt).toFixed(1)));
      if (this.site === 'radial') {
        this.none.radial = true;
        this.pp.flash('ok', T('no_radial_noted', 'Noted: **no radial pulse**. Check the carotid.'), 3200);
        NZA.audio.click(600);
        this.setSite('carotid');
        this.refresh(true);
        return;
      }
      this.none.carotid = true;
      this.pp.flash('bad', T('no_pulse_called', 'No carotid pulse.'), 0);
      this.submit();
    },
    recount() {
      this.step = 1; this.count = null; this.taps = []; this.tapMarks = [];
      this.rhythm = null; this.strength = null;
      this.setTip(1);
      this.pp.set({ step: 1, title: T('pulse_s1_title', 'Find the pulse'), text: this.siteText() });
      this.refresh(true);
    },
    enter() {
      if (this.done) { if (this.finished) this.closeNow(); return; }
      if (this.step !== 3) return;
      if (!this.rhythm || !this.strength) return this.pp.flash('warn', T('judge_first', 'Pick a rhythm **and** a strength first.'));
      this.submit();
    },
    rate() { return Math.round(this.taps.length * 60 / (this.d.countSeconds || 15)); },

    submit() {
      const left = (this.d.minTime ?? 8) - (now() - this.opened) / 1000;
      if (left > 0) {
        this.pp.flash('warn', T('too_fast', 'Take a little more time with the patient.'), 0);
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
      this.pp.set({ title: T('checking', 'Checking your findings…'), titleTone: '', text: '', tools: [] });
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
      while (this.samples.length && ms - this.samples[0].ms > 4200) this.samples.shift();
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
          if (cur.b[key] * this.feel(site, p) >= 0.12 && this.marker) {
            this.marker.el.classList.remove('pz-beat'); void this.marker.el.offsetWidth; this.marker.el.classList.add('pz-beat');
          }
        }
      }
      this.draw(ms);
      this.statT = (this.statT || 0) + dt;
      if (this.statT > 0.12 && !this.finished) { this.statT = 0; this.refreshStats(); }
      this.raf = requestAnimationFrame(x => this.frame(x));
    },
    refreshStats() {
      if (!this.pp) return;
      const p = this.pressure;
      this.pp.stat('press', { value: this.pressWord(p), tone: p >= 0.75 ? 'amber' : '', meter: { value: p, tone: p >= 0.75 ? 'amber' : 'white', segs: true } });
      if (this.step === 1) this.pp.stat('palp', { value: this.palp[this.site].toFixed(1), meter: { value: clamp(this.palp[this.site] / Math.max(1, this.d.absentAfter || 5), 0, 1), tone: 'white' } });
      if (this.step === 2 && this.count) {
        const total = this.d.countSeconds || 15;
        const left = Math.max(0, total - (now() - this.count.started) / 1000);
        this.pp.stat('count', { value: this.taps.length, meter: { value: 1 - left / total, tone: 'teal' } });
        this.pp.el.querySelector('.pp-tag').textContent = `${Math.ceil(left)} s`;
      }
      // caption
      const f = this.feel(this.site, p), occ = this.occluded(this.site, p);
      let cap = '', tone = '';
      if (p < 0.08) cap = T('cap_lift', 'Fingers resting on the skin');
      else if (occ) { cap = T('cap_occluded', 'Pressing hard: the artery is squashed flat'); tone = 'amber'; }
      else if (f >= 0.85) { cap = T('cap_best', 'Good contact'); tone = 'teal'; }
      else if (f > 0.05) cap = T('cap_faint', 'Faint contact');
      else cap = T('cap_nothing', 'Nothing under your fingers');
      if (this.cap.textContent !== cap) { this.cap.textContent = cap; this.cap.className = `cap ${tone}`; }
    },
    toJudge() {
      this.step = 3;
      this.setTip(3);
      this.pp.set({ step: 3, tag: T('pulse_tag', 'Pulse'), title: T('pulse_s3_title', 'Judge the pulse'), text: T('pulse_s3_text', 'Was the beat **regular**? Was it **weak**, **normal** or **bounding**? Then press {Enter}. {R} counts again.') });
      this.refresh(true);
      NZA.audio.beep(880, 70, 0.06);
    },
    draw(ms) {
      const cv = this.cv; if (!cv) return;
      const { w, h, scale } = NZA.fitCanvas(cv);
      const c = cv.getContext('2d');
      c.clearRect(0, 0, w, h);
      c.fillStyle = '#020403'; c.fillRect(0, 0, w, h);
      // grid
      c.strokeStyle = 'rgba(8,175,162,.08)'; c.lineWidth = 1;
      const gx = 24 * scale;
      for (let x = w - ((ms / 4000 * w) % gx); x > 0; x -= gx) { c.beginPath(); c.moveTo(x, 0); c.lineTo(x, h); c.stroke(); }
      for (let y = h / 4; y < h; y += h / 4) { c.beginPath(); c.moveTo(0, y); c.lineTo(w, y); c.stroke(); }
      // count window shading
      const xOf = m => w - ((ms - m) / 4000) * w;
      if (this.count) {
        const a = xOf(this.count.startMs), b = xOf(this.count.startMs + (this.d.countSeconds || 15) * 1000);
        c.fillStyle = 'rgba(8,175,162,.06)'; c.fillRect(Math.max(0, a), 0, Math.min(w, b) - Math.max(0, a), h);
      }
      // trace
      const base = h * 0.72, amp = h * 0.56;
      const occ = this.samples.length && this.samples[this.samples.length - 1].occ;
      c.lineWidth = 1.8 * scale; c.lineJoin = 'round';
      c.strokeStyle = occ ? '#e5a50a' : '#0fd4c4';
      c.shadowColor = c.strokeStyle; c.shadowBlur = 6 * scale;
      c.beginPath();
      this.samples.forEach((s, i) => { const x = xOf(s.ms), y = base - s.v * amp; if (i) c.lineTo(x, y); else c.moveTo(x, y); });
      c.stroke();
      c.shadowBlur = 0;
      // pen dot
      if (this.samples.length) { const s = this.samples[this.samples.length - 1]; c.fillStyle = '#fff'; c.beginPath(); c.arc(w - 2 * scale, base - s.v * amp, 2.6 * scale, 0, Math.PI * 2); c.fill(); }
      // taps
      (this.tapMarks || []).forEach(tm => {
        const x = xOf(tm.ms); if (x < 0) return;
        c.fillStyle = tm.good ? '#0fd4c4' : '#e5484d';
        c.fillRect(x - 1.5 * scale, 3 * scale, 3 * scale, 9 * scale);
      });
    },

    /* ── result ── */
    showResult(o) {
      if (this.finished) return;
      this.finished = true;
      const g = o.grade || 'F';
      const r = o.rows || {};
      const okIc = ok => (ok === true ? `<span class="ok">${icon('check')}</span>` : ok === false ? `<span class="no">${icon('x')}</span>` : '<span></span>');
      const row = (label, you, pat, ok, unit = '') => `<tr><th>${esc(label)}</th><td>${esc(you ?? '--')}${unit && you !== '--' ? `<i>${esc(unit)}</i>` : ''}</td><td>${esc(pat ?? '--')}${unit && pat !== '--' ? `<i>${esc(unit)}</i>` : ''}</td><td class="m">${okIc(ok)}</td></tr>`;
      const rate = r.rate || {}, rh = r.rhythm || {}, st = r.strength || {}, site = r.site || {};
      const chip = (on, label) => `<span class="chipx sm ${on ? 'teal' : 'red'}">${icon(on ? 'check' : 'x')}${esc(label)}</span>`;
      const fb = (o.feedback || []).map(f => `<li class="${esc(f.tone || '')}">${esc(f.text)}</li>`).join('');
      const rec = (o.recorded || []).map(x => `<span class="chipx sm amber">${icon('clipboard')}${esc(x)}</span>`).join('');
      this.resultWrap.innerHTML = `
        <div class="pz-result nza-hud solid nza-pop">
          <div class="rh"><div class="grade g-${esc(g)}">${esc(g)}</div><div><h3>${esc(o.title || T('pulse_result_title', 'Pulse assessment'))}</h3><p>${esc(T('result_sub', '%s s at the patient · score %s', o.seconds ?? 0, o.score ?? 0))}</p></div></div>
          ${o.error ? `<p class="err">${esc(o.msg || '')}</p>` : `
          <table><thead><tr><th></th><th>${esc(T('your_finding', 'Your finding'))}</th><th>${esc(T('patient', 'Patient'))}</th><th></th></tr></thead><tbody>
            ${row(T('row_rate', 'Rate'), rate.you, rate.patient, rate.ok, rate.unit || T('bpm', 'bpm'))}
            ${rate.apical ? `<tr class="sub"><th></th><td></td><td colspan="2">${esc(T('apical', 'Heart %s bpm (pulse deficit)', rate.apical))}</td></tr>` : ''}
            ${row(T('row_rhythm', 'Rhythm'), rh.you, rh.patient, rh.ok)}
            ${row(T('row_strength', 'Strength'), st.you, st.patient, st.ok)}
            <tr><th>${esc(T('row_site', 'Site'))}</th><td>${esc(site.you || '--')}</td><td colspan="2"><span class="chips-row">${chip(site.carotid, T('site_carotid', 'Carotid'))}${chip(site.radial, T('site_radial', 'Radial'))}</span></td></tr>
          </tbody></table>`}
          ${fb ? `<ul class="fb">${fb}</ul>` : ''}
          ${rec ? `<div class="rec"><span class="nza-label">${esc(T('recorded', 'Recorded'))}</span>${rec}</div>` : ''}
        </div>`;
      if (['S', 'A', 'B'].includes(g)) NZA.audio.success(); else NZA.audio.fail();
      this.pp.complete({ title: T('complete', 'Assessment complete'), text: T('complete_text', 'Check your call against the patient. {Enter} to close.'), label: T('done', 'Done'), onDone: () => this.closeNow() });
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
          score: 64, grade: 'C', seconds: Math.round((now() - this.opened) / 1000), title: 'Pulse assessment',
          rows: { rate: { you: String(counted), patient: '124', unit: 'bpm', ok: Math.abs(counted - 124) <= 10 },
            rhythm: { you: res.rhythm === 'irregular' ? 'Irregular' : 'Regular', patient: 'Regular', ok: res.rhythm !== 'irregular' },
            strength: { you: ({ weak: 'Weak', normal: 'Normal', bounding: 'Bounding' })[res.strength] || '--', patient: 'Weak', ok: res.strength === 'weak' },
            site: { you: 'Right radial', carotid: true, radial: true } },
          feedback: [{ tone: Math.abs(counted - 124) <= 10 ? 'ok' : 'bad', text: `You counted ${counted} bpm. The pulse at that site was 124.` }, { tone: 'warn', text: 'Weak and fast: think shock. Find the bleeding.' }],
          recorded: [],
        }), 300);
        return { ok: true };
      });
    },
  });
})();
