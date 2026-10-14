/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · Check Breathing (app 'breathing')   module: assess
   3 steps on the shared procedure panel (NZA.ui.ProcPanel):
     1 Look & feel   watch the chest (world marker rises with every breath), Space starts a
                     15 s count, tap Space on every rise. N = no chest rise. 'What you see' card.
     2 Listen        stethoscope on the 6 lung zones (world anchors 'ru' 'rm' 'rl' 'lu' 'lm' 'll'
                     or the acoustic map): hold the mouse button to listen. Breath sounds are
                     synthesised with WebAudio per zone: vesicular, reduced, absent, crackles,
                     wheeze, stridor, gurgling, silence. Scrolling sound trace, air entry meter,
                     sides 0/2.
     3 Call          normal / reduced L / reduced R / absent L / absent R / crackles / wheeze /
                     noisy airway / not breathing  → result card + the true acoustic map.

   Lua → JS   open { locale, k, s, look, stetho, countSeconds, listenSeconds, noBreathAfter,
                     minTime, keys, patient }   result (outcome)   anchors { chest, ru..ll }
   JS → Lua   breathing:step { step }   breathing:finish { result }   breathing:abort   breathing:close
   ═══════════════════════════════════════════════════════════ */
(() => {
  const esc = NZA.esc, icon = NZA.icon, clamp = NZA.clamp;
  let LOC = {};
  const T = (k, fb, ...a) => { let s = LOC[k] !== undefined ? String(LOC[k]) : fb; a.forEach(v => { s = s.replace(/%[sd]/, v); }); return s; };
  const now = () => performance.now();
  const ZONES = ['ru', 'rm', 'rl', 'lu', 'lm', 'll'];
  const SOUNDS = ['vesicular', 'reduced', 'absent', 'crackles', 'wheeze', 'stridor', 'gurgle', 'silent'];
  const CALLS = ['normal', 'reduced_l', 'reduced_r', 'absent_l', 'absent_r', 'crackles', 'wheeze', 'airway', 'none'];
  const CALL_FB = { normal: 'Normal', reduced_l: 'Reduced left', reduced_r: 'Reduced right', absent_l: 'Absent left', absent_r: 'Absent right', crackles: 'Crackles', wheeze: 'Wheeze', airway: 'Noisy airway', none: 'Not breathing' };
  const ZONE_FB = { ru: 'Right upper', rm: 'Right middle', rl: 'Right lower', lu: 'Left upper', lm: 'Left middle', ll: 'Left lower' };
  const codeLabel = c => ({ Space: 'Space', Enter: 'Enter', Escape: 'ESC' })[c] || String(c || '').replace(/^Key|^Digit/, '');

  function decode(seed, str) {
    let x = Math.floor(seed) % 2147483647; if (x <= 0) x = 1;
    const out = [];
    for (let i = 0; i + 3 <= str.length; i += 3) { x = (x * 48271) % 2147483647; out.push(((parseInt(str.substr(i, 3), 16) - (x % 4096)) % 4096 + 4096) % 4096); }
    return out;
  }
  function encode(seed, values) {
    let x = Math.floor(seed) % 2147483647; if (x <= 0) x = 1;
    return values.map(v => { x = (x * 48271) % 2147483647; v = clamp(Math.round(v), 0, 4095); return ((v + x % 4096) % 4096).toString(16).padStart(3, '0'); }).join('');
  }

  /* ─────────────── breath sound synthesiser ─────────────── */
  function Synth() {
    let ctx = null, master = null, nodes = null;
    function build() {
      const C = window.AudioContext || window.webkitAudioContext;
      if (!C) return false;
      ctx = new C();
      master = ctx.createGain(); master.gain.value = 0; master.connect(ctx.destination);
      const len = ctx.sampleRate * 2, buf = ctx.createBuffer(1, len, ctx.sampleRate), d = buf.getChannelData(0);
      let b = 0; for (let i = 0; i < len; i++) { const w = Math.random() * 2 - 1; b = 0.97 * b + 0.03 * w; d[i] = w * 0.55 + b * 2.2; }
      const src = ctx.createBufferSource(); src.buffer = buf; src.loop = true;
      // breath (filtered noise)
      const bp = ctx.createBiquadFilter(); bp.type = 'bandpass'; bp.frequency.value = 420; bp.Q.value = 0.7;
      const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 900;
      const breath = ctx.createGain(); breath.gain.value = 0;
      src.connect(bp); bp.connect(lp); lp.connect(breath); breath.connect(master);
      // harsh upper airway noise
      const hp = ctx.createBiquadFilter(); hp.type = 'bandpass'; hp.frequency.value = 1300; hp.Q.value = 2.2;
      const harsh = ctx.createGain(); harsh.gain.value = 0;
      src.connect(hp); hp.connect(harsh); harsh.connect(master);
      // musical wheeze / stridor tone
      const osc = ctx.createOscillator(); osc.type = 'sawtooth'; osc.frequency.value = 460;
      const lfo = ctx.createOscillator(); lfo.frequency.value = 5.5; const lfoG = ctx.createGain(); lfoG.gain.value = 14;
      lfo.connect(lfoG); lfoG.connect(osc.frequency);
      const obp = ctx.createBiquadFilter(); obp.type = 'bandpass'; obp.frequency.value = 520; obp.Q.value = 6;
      const tone = ctx.createGain(); tone.gain.value = 0;
      osc.connect(obp); obp.connect(tone); tone.connect(master);
      // stethoscope handling hiss
      const hiss = ctx.createGain(); hiss.gain.value = 0;
      const hlp = ctx.createBiquadFilter(); hlp.type = 'lowpass'; hlp.frequency.value = 260;
      src.connect(hlp); hlp.connect(hiss); hiss.connect(master);
      src.start(); osc.start(); lfo.start();
      nodes = { breath, bp, lp, harsh, hp, tone, osc, obp, hiss };
      return true;
    }
    function burst(f, ms, vol, at = 0) {    // a crackle / bubble
      if (!ctx) return;
      const t0 = ctx.currentTime + at;
      const o = ctx.createOscillator(), g = ctx.createGain(), bf = ctx.createBiquadFilter();
      o.type = 'triangle'; o.frequency.setValueAtTime(f, t0); o.frequency.exponentialRampToValueAtTime(Math.max(40, f * 0.55), t0 + ms / 1000);
      bf.type = 'bandpass'; bf.frequency.value = f; bf.Q.value = 3;
      g.gain.setValueAtTime(0, t0); g.gain.linearRampToValueAtTime(vol, t0 + 0.002); g.gain.exponentialRampToValueAtTime(0.0001, t0 + ms / 1000);
      o.connect(bf); bf.connect(g); g.connect(master); o.start(t0); o.stop(t0 + ms / 1000 + 0.02);
    }
    return {
      start() { if (!ctx && !build()) return; if (ctx.state === 'suspended') ctx.resume(); },
      set(p) {
        if (!ctx || !nodes) return;
        const t = ctx.currentTime, k = 0.035;
        const on = p.on && (window.NZA ? NZA.cfg.sounds !== false : true);
        master.gain.setTargetAtTime(on ? 0.9 : 0, t, 0.05);
        nodes.breath.gain.setTargetAtTime(p.breath || 0, t, k);
        nodes.lp.frequency.setTargetAtTime(p.lp || 900, t, 0.08);
        nodes.bp.frequency.setTargetAtTime(p.bpf || 420, t, 0.08);
        nodes.harsh.gain.setTargetAtTime(p.harsh || 0, t, k);
        nodes.tone.gain.setTargetAtTime(p.tone || 0, t, k);
        nodes.osc.frequency.setTargetAtTime(p.toneF || 460, t, 0.1);
        nodes.obp.frequency.setTargetAtTime(p.toneF ? p.toneF * 1.1 : 520, t, 0.1);
        nodes.hiss.gain.setTargetAtTime(p.hiss || 0, t, 0.1);
      },
      crackle(vol) { burst(700 + Math.random() * 900, 6 + Math.random() * 10, vol); },
      bubble(vol) { burst(140 + Math.random() * 160, 40 + Math.random() * 60, vol); },
      stop() { if (ctx) { try { master.gain.setTargetAtTime(0, ctx.currentTime, 0.03); } catch (e) { /* closed */ } } },
      destroy() { if (ctx) { try { ctx.close(); } catch (e) { /* closed */ } } ctx = null; nodes = null; },
    };
  }

  NZA.app('breathing', {
    escClose: false,
    init(el) {
      this.el = el;
      el.innerHTML = `
        <div class="br-left">
          <div class="dev br-dev nza-int">
            <div class="br-top"><div class="dev-brand"><span class="nz-mark"></span><span>NAYZEEE</span><b>AUSCULT</b></div><span class="dev-led off"></span></div>
            <div class="dev-screen br-scr1">
              <div class="br-sh"><span>${'LUNG'}</span><b class="zn">--</b><i class="st"></i></div>
              <canvas class="br-wave"></canvas>
              <div class="br-prog"><div class="mtr"><i></i></div><span class="ps">0s</span></div>
            </div>
            <div class="dev-screen br-scr2">
              <div class="br-sh"><span class="am">ACOUSTIC MAP</span><span class="sides"><b>0</b>/2<em>SIDES</em></span></div>
              <div class="br-map"><div class="br-entry"><div class="bar"><i></i></div><span>AIR ENTRY</span></div><canvas class="br-lungs"></canvas></div>
              <div class="br-foot"><span class="r">R <b>--</b></span><span class="leg"></span><span class="l"><b>--</b> L</span></div>
            </div>
          </div>
          <div class="br-see nza-hud nza-int"><h4></h4><ul></ul></div>
        </div>
        <div class="br-result-wrap"></div>`;
      this.$ = s => el.querySelector(s);
      this.cvWave = this.$('.br-wave');
      this.cvLungs = this.$('.br-lungs');
      // the stethoscope cursor lives in the unzoomed anchor layer (positions are viewport px)
      this.steth = document.createElement('div');
      this.steth.className = 'br-steth';
      this.steth.innerHTML = '<span class="ring"></span><span class="head"></span>';
      this.steth.style.display = 'none';
      (document.getElementById('nza-layer-anchors') || document.body).appendChild(this.steth);
      this.anc = NZA.ui.Anchors('breathing');
      this.synth = Synth();
      this.onMove = e => { if (!NZA.isOpen('breathing')) return; this.mouse = NZA.pointer(e); this.mousePx = { x: e.clientX, y: e.clientY }; };
      this.onDown = e => { if (!NZA.isOpen('breathing') || e.button !== 0) return; this.synth.start(); this.held = true; };
      this.onUp = e => { if (e.button === 0) this.held = false; };
      window.addEventListener('mousemove', this.onMove);
      window.addEventListener('mousedown', this.onDown);
      window.addEventListener('mouseup', this.onUp);
      this.cvLungs.addEventListener('mousemove', e => { this.mapHover = this.mapZoneAt(e); });
      this.cvLungs.addEventListener('mouseleave', () => { this.mapHover = null; });
    },

    open(d) {
      LOC = Object.assign({}, d.locale || {});
      this.d = d;
      this.keysCfg = Object.assign({ count: 'Space', none: 'KeyN', submit: 'Enter' }, d.keys || {});
      const v = decode(d.k, d.s || '');
      const n = v[0] || 0;
      this.breaths = [];
      let acc = 0;
      for (let i = 0; i < n; i++) { const iv = v[1 + i] || 4000; acc += iv; this.breaths.push({ t: acc, iv, d: (v[1 + n + i] || 0) / 1000 }); }
      this.total = acc;
      this.zones = {};
      ZONES.forEach((z, i) => { const o = 1 + 2 * n + i * 2; this.zones[z] = { sound: SOUNDS[v[o]] || 'vesicular', entry: (v[o + 1] || 0) / 1000 }; });
      this.apnoea = n === 0;
      this.step = 1;
      this.t0 = now(); this.opened = now();
      this.watch = 0;
      this.count = null; this.taps = []; this.tapMarks = [];
      this.noRise = false;
      this.listened = {}; ZONES.forEach(z => { this.listened[z] = 0; });
      this.zone = null; this.held = false; this.call = null;
      this.done = false; this.finished = false;
      this.samples = [];
      this.entryPeak = 0;
      this.truthShown = false;
      this.$('.br-result-wrap').innerHTML = '';
      this.$('.br-scr1 .zn').textContent = T('br_place', 'Place the stethoscope');
      this.$('.br-scr1 .br-sh span').textContent = T('br_lung', 'Lung');
      this.$('.br-scr2 .am').textContent = T('br_map', 'Acoustic map');
      this.$('.br-scr2 .sides em').textContent = T('br_sides', 'Sides');
      this.$('.br-entry span').textContent = T('br_air', 'Air entry');
      this.renderSee();
      if (this.pp) this.pp.destroy();
      this.buildPanel();
      this.bindKeys();
      this.chestMarker = NZA.ui.Marker('breathing', 'chest', { anchor: 'chest', dot: 'white', label: T('br_watch', 'Watch the chest') });
      this.chestMarker.el.classList.add('br-chest');
      this.zoneMarkers = {};
      this.steth.style.display = 'none';
      this.el.classList.remove('br-listen');
      cancelAnimationFrame(this.raf);
      this.last = now();
      this.raf = requestAnimationFrame(t => this.frame(t));
    },
    close() {
      cancelAnimationFrame(this.raf);
      clearTimeout(this.minTimer);
      this.synth.stop();
      if (this.pp) { this.pp.destroy(); this.pp = null; }
      this.held = false;
      this.steth.style.display = 'none';
      document.body.classList.remove('br-nocursor');
    },

    msg: {
      result(o) { NZA.apps.breathing.showResult(o || {}); },
    },

    bindKeys() {
      const k = this.keysCfg, self = this, map = {};
      map[k.count] = e => { if (!e.repeat) self.space(); };
      map[k.none] = () => self.noRiseCall();
      map[k.submit] = () => self.enter();
      for (let i = 1; i <= 9; i++) map[`Digit${i}`] = () => self.pick(i);
      this.keys = map;
    },

    /* ── panel ── */
    buildPanel() {
      this.pp = NZA.ui.ProcPanel(this.el, {
        step: 1, total: 3, tag: T('br_tag', 'Breathing'),
        title: T('br_s1_title', 'Look at the chest'),
        text: T('br_s1_text', 'Watch the chest rise and fall. {Space} starts a 15 s count, then tap {Space} on every rise.'),
        stats: this.stats(), tools: this.tools(),
        abort: { label: T('hold_stop', 'Hold to stop'), key: 'ESC', seconds: 1.0 },
        onAbort: () => this.abort(),
        onTool: key => this.tool(key),
      });
    },
    stats() {
      if (this.step === 1) {
        const total = this.d.countSeconds || 15;
        const left = this.count ? Math.max(0, total - (now() - this.count.started) / 1000) : total;
        return [
          { id: 'watch', label: T('st_watching', 'Watching'), value: this.watch.toFixed(1), unit: 's' },
          { id: 'count', label: T('st_breaths', 'Breaths'), value: this.taps.length, meter: { value: this.count ? 1 - left / total : 0, tone: 'teal' } },
          { id: 'rate', label: T('st_rate', 'Your rate'), value: this.count && !this.counting ? this.rate() : '--', unit: T('per_min', '/min') },
        ];
      }
      if (this.step === 2) {
        const z = this.zone;
        const sides = this.sidesDone();
        return [
          { id: 'zone', label: T('st_zone', 'Zone'), value: z ? T(`zone_${z}`, ZONE_FB[z]) : '--', small: true },
          { id: 'heard', label: T('st_heard', 'Heard'), value: this.heardCount(), unit: '/6', meter: { value: this.heardCount() / 6, tone: 'teal' } },
          { id: 'sides', label: T('st_sides', 'Sides'), value: sides, unit: '/2', tone: sides >= 2 ? 'teal' : '' },
        ];
      }
      return [
        { id: 'rate', label: T('st_rate', 'Your rate'), value: this.noRise ? 0 : (this.count ? this.rate() : '--'), unit: T('per_min', '/min') },
        { id: 'heard', label: T('st_heard', 'Heard'), value: this.heardCount(), unit: '/6' },
        { id: 'call', label: T('st_call', 'Your call'), value: this.call ? T(`call_${this.call}`, CALL_FB[this.call]) : '--', small: true, tone: this.call ? 'teal' : '' },
      ];
    },
    tools() {
      const k = this.keysCfg;
      if (this.step === 1) {
        const counting = !!this.count && this.counting;
        return [
          { key: codeLabel(k.count), label: counting ? T('tool_tap_rise', 'Tap each rise') : T('tool_count', 'Start count'), state: counting ? 'active' : (this.count ? 'done' : '') },
          { key: codeLabel(k.none), label: T('tool_no_rise', 'No chest rise'), state: this.count ? 'locked' : '' },
          { key: codeLabel(k.submit), label: T('tool_next', 'Next'), state: (this.count && !this.counting) || this.noRise ? 'active' : 'locked' },
        ];
      }
      if (this.step === 2) {
        return [
          { key: T('lmb', 'LMB'), label: T('tool_hold_listen', 'Hold to listen'), state: this.held && this.zone ? 'active' : '' },
          { key: codeLabel(k.submit), label: T('tool_done_listen', 'Done listening'), state: this.heardCount() ? 'active' : '' },
        ];
      }
      return CALLS.map((c, i) => ({ key: String(i + 1), label: T(`call_${c}`, CALL_FB[c]), state: this.call === c ? 'active' : '' }))
        .concat([{ key: codeLabel(k.submit), label: T('submit', 'Submit'), state: this.call ? 'active' : 'locked' }]);
    },
    refresh(full) { if (!this.pp) return; this.pp.set(full ? { stats: this.stats(), tools: this.tools() } : { stats: this.stats() }); },
    tool(key) {
      const k = this.keysCfg;
      if (key === codeLabel(k.count)) return this.space();
      if (key === codeLabel(k.none)) return this.noRiseCall();
      if (key === codeLabel(k.submit)) return this.enter();
      if (/^[1-9]$/.test(key)) return this.pick(Number(key));
      return null;
    },
    renderSee() {
      const box = this.$('.br-see');
      const list = this.d.look || [];
      box.querySelector('h4').textContent = T('see_title', 'What you see');
      box.querySelector('ul').innerHTML = list.map(l => `<li class="${esc(l.tone || '')}">${esc(l.text)}</li>`).join('') || `<li>${esc(T('see_nothing', 'Nothing unusual'))}</li>`;
    },

    /* ── breath model ── */
    breathAt(ms) {
      if (!this.total || !this.breaths.length) return null;
      const cyc = Math.floor(ms / this.total), off = ms - cyc * this.total;
      let lo = 0, hi = this.breaths.length - 1, idx = -1;
      while (lo <= hi) { const m = (lo + hi) >> 1; if (this.breaths[m].t <= off) { idx = m; lo = m + 1; } else hi = m - 1; }
      if (idx < 0) { const b = this.breaths[this.breaths.length - 1]; return { b: this.breaths[0], t: cyc * this.total - this.total + b.t, iv: this.breaths[0].iv }; }
      const nb = this.breaths[idx + 1] || this.breaths[0];
      return { b: nb, t: cyc * this.total + this.breaths[idx].t, iv: nb.iv };
    },
    // phase: returns { rise 0..1 (chest), insp 0..1, exp 0..1, depth }
    phase(ms) {
      const cur = this.breathAt(ms);
      if (!cur) return { rise: 0, insp: 0, exp: 0, depth: 0, inInsp: false };
      const tau = ms - cur.t, iv = cur.iv, d = cur.b.d;
      const ti = Math.min(1700, iv * 0.38), te = Math.min(2600, iv * 0.55);
      if (tau < ti) { const x = tau / ti; return { rise: d * Math.sin(x * Math.PI / 2), insp: d * Math.sin(x * Math.PI), exp: 0, depth: d, inInsp: true }; }
      if (tau < ti + te) { const x = (tau - ti) / te; return { rise: d * Math.cos(x * Math.PI / 2), insp: 0, exp: d * Math.sin(x * Math.PI) * (1 - x * 0.4), depth: d, inInsp: false }; }
      return { rise: 0, insp: 0, exp: 0, depth: d, inInsp: false };
    },
    // loudness profile of a zone right now → audio + trace
    zoneSound(z, ph) {
      const Z = this.zones[z] || { sound: 'silent', entry: 0 };
      const e = Z.entry;
      const out = { breath: 0, harsh: 0, tone: 0, toneF: 460, lp: 900, bpf: 420, crackle: 0, bubble: 0, level: 0 };
      if (Z.sound === 'silent' || this.apnoea) return out;
      const ins = ph.insp, ex = ph.exp;
      const ves = ins * 1.0 + ex * 0.32;
      switch (Z.sound) {
        case 'vesicular': out.breath = ves * 0.5 * e; break;
        case 'reduced': out.breath = ves * 0.5 * e; out.lp = 520; break;
        case 'absent': out.breath = ves * 0.05; out.lp = 300; break;
        case 'crackles': out.breath = ves * 0.42 * e; out.crackle = ins * e; break;
        case 'wheeze': out.breath = ves * 0.32 * e; out.tone = (ex * 0.6 + ins * 0.12) * 0.22; out.toneF = 380 + 180 * ex; break;
        case 'stridor': out.breath = ves * 0.25; out.harsh = ins * 0.55; out.tone = ins * 0.16; out.toneF = 760; break;
        case 'gurgle': out.breath = ves * 0.3; out.bubble = (ins + ex) * 0.8; out.lp = 600; break;
        default: break;
      }
      out.level = clamp(out.breath * 1.6 + out.harsh + out.tone * 2 + out.crackle * 0.3 + out.bubble * 0.25, 0, 1);
      return out;
    },

    /* ── input ── */
    space() {
      if (this.done || this.step !== 1) return;
      const ms = now() - this.t0;
      if (!this.count) {
        this.count = { started: now(), startMs: ms };
        this.counting = true;
        this.taps = []; this.tapMarks = [];
        this.pp.set({ title: T('br_s1b_title', 'Count the breaths'), text: T('br_s1b_text', 'Tap {Space} every time the chest **rises**.') });
        this.refresh(true);
        NZA.audio.beep(1040, 70, 0.06);
        return;
      }
      if (!this.counting) return;
      const ph = this.phase(ms - 400);
      const good = !this.apnoea && (ph.inInsp || this.phase(ms).inInsp || this.phase(ms - 700).inInsp);
      this.taps.push(Math.round(ms));
      this.tapMarks.push({ ms, good });
      if (good) NZA.audio.tone(1150, 45, { vol: 0.06, type: 'triangle' }); else NZA.audio.tone(240, 70, { vol: 0.07, type: 'triangle' });
      this.refresh(false);
    },
    noRiseCall() {
      if (this.done || this.step !== 1 || this.count) return;
      const need = this.d.noBreathAfter || 6;
      if (this.watch < need) return this.pp.flash('warn', T('keep_watching', 'Keep watching for %s more seconds.', (need - this.watch).toFixed(1)));
      this.noRise = true;
      this.pp.flash('bad', T('no_rise_noted', 'No chest rise. Listen to confirm, or make the call.'), 3500);
      this.toListen();
    },
    enter() {
      if (this.done) { if (this.finished) NZA.close('breathing'); return; }
      if (this.step === 1) {
        if ((this.count && !this.counting) || this.noRise) this.toListen();
        else this.pp.flash('warn', T('count_first', 'Count the breaths first (or call no chest rise).'));
        return;
      }
      if (this.step === 2) {
        if (this.sidesDone() < 2 && this.d.stetho !== false && !this.warnedSides) {
          this.warnedSides = true;
          return this.pp.flash('warn', T('both_sides', 'Listen to **both sides** before you decide. {Enter} again to skip.'));
        }
        return this.toCall();
      }
      if (this.step === 3) {
        if (!this.call) return this.pp.flash('warn', T('pick_call', 'Pick what you heard first.'));
        this.submit();
      }
    },
    pick(n) {
      if (this.done || this.step !== 3) return;
      const c = CALLS[n - 1]; if (!c) return;
      this.call = c;
      NZA.audio.click(820);
      this.refresh(true);
    },
    toListen() {
      this.counting = false;
      this.step = 2;
      this.chestMarker.set({ label: '' });
      this.chestMarker.el.classList.add('hide2');
      NZA.post('breathing:step', { step: 2 });
      if (this.d.stetho === false) {
        this.pp.set({ step: 2, title: T('br_s2_title', 'Listen to the chest'), text: T('br_no_stetho', 'You have no stethoscope. Make the call from what you saw.') });
        this.pp.flash('warn', T('no_stetho', 'No stethoscope in your inventory.'), 0);
        setTimeout(() => this.toCall(), 1800);
        return;
      }
      this.el.classList.add('br-listen');
      document.body.classList.add('br-nocursor');
      this.steth.style.display = '';
      this.pp.set({ step: 2, title: T('br_s2_title', 'Listen to the chest'), text: T('br_s2_text', 'Put the stethoscope on each zone and **hold the mouse button** to listen. Compare left and right at the same height.') });
      this.refresh(true);
      this.synth.start();
    },
    toCall() {
      this.step = 3;
      this.held = false;
      this.el.classList.remove('br-listen');
      document.body.classList.remove('br-nocursor');
      this.steth.style.display = 'none';
      Object.values(this.zoneMarkers).forEach(m => m.remove());
      this.zoneMarkers = {};
      this.synth.set({ on: false });
      NZA.post('breathing:step', { step: 3 });
      this.pp.set({ step: 3, title: T('br_s3_title', 'Make the call'), text: T('br_s3_text', 'What did you hear? Pick it with {1}–{9}, then {Enter}.') });
      this.refresh(true);
    },
    rate() { return Math.round(this.taps.length * 60 / (this.d.countSeconds || 15)); },
    heardCount() { return ZONES.filter(z => this.listened[z] >= (this.d.listenSeconds || 1.8)).length; },
    sidesDone() {
      const need = this.d.listenSeconds || 1.8;
      const side = s => ZONES.filter(z => z[0] === s && this.listened[z] >= need).length >= 2;
      return (side('r') ? 1 : 0) + (side('l') ? 1 : 0);
    },

    submit() {
      const left = (this.d.minTime ?? 10) - (now() - this.opened) / 1000;
      if (left > 0) {
        this.pp.flash('warn', T('too_fast', 'Take a little more time with the patient.'), 0);
        clearTimeout(this.minTimer);
        this.minTimer = setTimeout(() => this.submit(), left * 1000 + 250);
        return;
      }
      this.done = true;
      const listened = {};
      ZONES.forEach(z => { listened[z] = Math.round(this.listened[z] * 10) / 10; });
      const result = {
        nonce: Math.floor(Math.random() * 1e9),
        countStart: this.count ? Math.round(this.count.startMs) : -1,
        countMs: this.count ? Math.round(Math.min((this.d.countSeconds || 15) * 1000, (this.count.ended || now()) - this.count.started)) : 0,
        taps: this.taps.slice(0, 120), noRise: this.noRise, listened, call: this.call, score: 0,
      };
      this.pp.set({ title: T('checking', 'Checking your findings…'), text: '', tools: [] });
      NZA.post('breathing:finish', result).then(r => { if (r && r.outcome) this.showResult(r.outcome); });
    },
    abort() {
      if (this.finished) return NZA.close('breathing');
      this.done = true;
      NZA.post('breathing:abort', {});
      NZA.close('breathing');
    },

    /* ── stethoscope placement ── */
    zonePoints() {
      const W = window.innerWidth, H = window.innerHeight, out = {};
      ZONES.forEach(z => { const a = this.anc.get(z); if (a && a.visible !== false) out[z] = { x: a.x * W, y: a.y * H }; });
      return out;
    },
    mapZoneAt(e) {
      const r = this.cvLungs.getBoundingClientRect();
      const x = (e.clientX - r.left) / r.width, y = (e.clientY - r.top) / r.height;
      let best = null, bd = 0.09;
      Object.entries(this.mapPos()).forEach(([z, p]) => { const d = Math.hypot(p.x - x, (p.y - y) * r.height / r.width); if (d < bd) { bd = d; best = z; } });
      return best;
    },
    mapPos() {   // zone centres on the acoustic map (fractions of the canvas)
      return { ru: { x: 0.33, y: 0.33 }, rm: { x: 0.3, y: 0.53 }, rl: { x: 0.31, y: 0.73 }, lu: { x: 0.67, y: 0.33 }, lm: { x: 0.7, y: 0.53 }, ll: { x: 0.69, y: 0.73 } };
    },
    updateSteth() {
      if (this.step !== 2 || !this.mousePx) { this.zone = this.mapHover && this.step === 2 ? this.mapHover : null; return; }
      const pts = this.zonePoints();
      let best = null, bd = 70 * (NZA.zoom || 1);
      Object.entries(pts).forEach(([z, p]) => { const d = Math.hypot(p.x - this.mousePx.x, p.y - this.mousePx.y); if (d < bd) { bd = d; best = z; } });
      if (this.mapHover) best = this.mapHover;
      this.zone = best;
      const at = best && pts[best] ? pts[best] : this.mousePx;
      this.steth.style.transform = `translate(${at.x}px, ${at.y}px)`;
      this.steth.classList.toggle('on', !!best);
      this.steth.classList.toggle('held', !!(best && this.held));
      if (this.mapHover) this.steth.style.transform = `translate(${this.mousePx.x}px, ${this.mousePx.y}px)`;
      // zone markers in the world
      ZONES.forEach(z => {
        const heard = this.listened[z] >= (this.d.listenSeconds || 1.8);
        const cls = `br-z ${heard ? 'heard' : ''} ${z === best ? 'cur' : ''}`;
        if (!this.zoneMarkers[z]) { this.zoneMarkers[z] = NZA.ui.Marker('breathing', `z_${z}`, { anchor: z, dot: 'ring' }); }
        const m = this.zoneMarkers[z];
        if (m.el.dataset.cls !== cls) { m.el.dataset.cls = cls; m.el.className = `anc ${cls} ${m.el.classList.contains('hide') ? 'hide' : ''}`; }
      });
    },

    /* ── frame ── */
    frame(t) {
      if (!NZA.isOpen('breathing')) return;
      const dt = Math.min(0.1, (t - this.last) / 1000); this.last = t;
      const ms = t - this.t0;
      const ph = this.phase(ms);
      if (!this.done && this.step === 1) {
        this.watch += dt;
        if (this.count && this.counting && now() - this.count.started >= (this.d.countSeconds || 15) * 1000) {
          this.counting = false;
          this.count.ended = now();
          this.pp.set({ title: T('br_s1c_title', 'Count done'), text: T('br_s1c_text', 'You counted **%s breaths a minute**. {Enter} to listen to the chest.', this.rate()) });
          this.refresh(true);
          NZA.audio.beep(880, 70, 0.06);
        }
      }
      // chest marker breathes
      if (this.chestMarker && this.step === 1) {
        const dot = this.chestMarker.el.querySelector('.dot');
        if (dot) { dot.style.transform = `scale(${1 + ph.rise * 0.9})`; dot.style.boxShadow = `0 0 0 ${4 + ph.rise * 10}px rgba(15,212,196,${0.08 + ph.rise * 0.22})`; dot.style.borderColor = ph.rise > 0.25 ? '#0fd4c4' : '#fff'; }
      }
      // listening
      let snd = null;
      if (this.step === 2 && !this.done) {
        this.updateSteth();
        if (this.zone && this.held) {
          this.listened[this.zone] += dt;
          snd = this.zoneSound(this.zone, ph);
        }
      }
      const listening = !!snd;
      if (listening) {
        if (snd.crackle > 0.05 && Math.random() < snd.crackle * 0.55) this.synth.crackle(0.12 * snd.crackle);
        if (snd.bubble > 0.05 && Math.random() < snd.bubble * 0.08) this.synth.bubble(0.18);
        this.synth.set({ on: true, breath: snd.breath, harsh: snd.harsh, tone: snd.tone, toneF: snd.toneF, lp: snd.lp, bpf: snd.bpf, hiss: 0.012 });
        this.entryPeak = Math.max(this.entryPeak * 0.985, snd.level);
      } else {
        this.synth.set({ on: this.step === 2 && this.held, breath: 0, harsh: 0, tone: 0, hiss: this.held ? 0.03 : 0 });
        this.entryPeak *= 0.96;
      }
      // trace sample
      let v = 0;
      if (snd) {
        v = snd.level * (0.55 + Math.random() * 0.45);
        if (snd.crackle > 0.05 && Math.random() < snd.crackle * 0.5) v += 0.4 + Math.random() * 0.4;
        if (snd.tone > 0.02) v = Math.max(v, snd.tone * 3 * (0.8 + 0.2 * Math.sin(ms * 0.09)));
        if (snd.bubble > 0.05 && Math.random() < 0.08) v += 0.5;
      } else v = this.held && this.step === 2 ? 0.03 * Math.random() : 0.01 * Math.random();
      this.samples.push({ ms, v: clamp(v, 0, 1) });
      while (this.samples.length && ms - this.samples[0].ms > 6000) this.samples.shift();
      this.drawWave(ms);
      this.drawLungs(ms, ph);
      this.updateDevice();
      this.statT = (this.statT || 0) + dt;
      if (this.statT > 0.15 && !this.done) {
        this.statT = 0;
        if (this.step === 1) {
          this.pp.stat('watch', { value: this.watch.toFixed(1) });
          if (this.count) { const total = this.d.countSeconds || 15; const left = Math.max(0, total - (now() - this.count.started) / 1000); this.pp.stat('count', { value: this.taps.length, meter: { value: this.counting ? 1 - left / total : 1, tone: 'teal' } }); if (this.counting) this.pp.el.querySelector('.pp-tag').textContent = `${Math.ceil(left)} s`; }
        } else if (this.step === 2) {
          const before = this.toolSig;
          this.toolSig = `${this.held && this.zone}|${this.heardCount()}`;
          if (before !== this.toolSig) this.refresh(true); else this.refresh(false);
        }
      }
      this.raf = requestAnimationFrame(x => this.frame(x));
    },
    updateDevice() {
      const z = this.zone;
      const zn = this.$('.br-scr1 .zn');
      const label = this.step === 2 ? (z ? T(`zone_${z}`, ZONE_FB[z]) : T('br_place', 'Place the stethoscope')) : (this.step === 1 ? T('br_standby', 'Standby') : T('br_review', 'Review'));
      if (zn.textContent !== label) zn.textContent = label;
      this.$('.br-scr1 .st').className = `st ${this.held && z ? 'on' : ''}`;
      const need = this.d.listenSeconds || 1.8;
      const p = z ? clamp(this.listened[z] / need, 0, 1) : 0;
      this.$('.br-prog .mtr i').style.width = `${p * 100}%`;
      this.$('.br-prog .ps').textContent = z ? `${Math.min(this.listened[z], 99).toFixed(1)}s` : '0s';
      this.$('.br-entry .bar i').style.height = `${clamp(this.entryPeak * 100, 0, 100)}%`;
      const sides = this.sidesDone();
      const sb = this.$('.br-scr2 .sides b'); if (sb.textContent !== String(sides)) sb.textContent = sides;
      const side = s => ZONES.filter(x => x[0] === s && this.listened[x] >= need).length;
      this.$('.br-foot .r b').textContent = `${side('r')}/3`;
      this.$('.br-foot .l b').textContent = `${side('l')}/3`;
      this.$('.br-top .dev-led').className = `dev-led ${this.held && z ? '' : 'off'}`;
    },
    drawWave(ms) {
      const cv = this.cvWave;
      const { w, h, scale } = NZA.fitCanvas(cv);
      const c = cv.getContext('2d');
      c.fillStyle = '#010302'; c.fillRect(0, 0, w, h);
      c.strokeStyle = 'rgba(8,175,162,.07)'; c.lineWidth = 1;
      for (let x = w - ((ms / 6000 * w) % (30 * scale)); x > 0; x -= 30 * scale) { c.beginPath(); c.moveTo(x, 0); c.lineTo(x, h); c.stroke(); }
      c.strokeStyle = 'rgba(8,175,162,.25)'; c.beginPath(); c.moveTo(0, h / 2); c.lineTo(w, h / 2); c.stroke();
      const xOf = m => w - ((ms - m) / 6000) * w;
      c.fillStyle = '#0fd4c4';
      c.shadowColor = '#0fd4c4'; c.shadowBlur = 6 * scale;
      const bw = Math.max(1, 1.6 * scale);
      this.samples.forEach(s => { const x = xOf(s.ms); const a = s.v * h * 0.46; if (a > 0.6) c.fillRect(x, h / 2 - a, bw, a * 2); });
      c.shadowBlur = 0;
      if (this.tapMarks && this.step === 1) this.tapMarks.forEach(tm => { const x = xOf(tm.ms); if (x > 0) { c.fillStyle = tm.good ? '#0fd4c4' : '#e5484d'; c.fillRect(x - 1.5 * scale, 2 * scale, 3 * scale, 8 * scale); } });
    },
    drawLungs(ms, ph) {
      const cv = this.cvLungs;
      const { w, h, scale } = NZA.fitCanvas(cv);
      const c = cv.getContext('2d');
      c.fillStyle = '#010302'; c.fillRect(0, 0, w, h);
      // grid
      c.strokeStyle = 'rgba(8,175,162,.05)'; c.lineWidth = 1;
      for (let x = 0; x < w; x += 14 * scale) { c.beginPath(); c.moveTo(x, 0); c.lineTo(x, h); c.stroke(); }
      for (let y = 0; y < h; y += 14 * scale) { c.beginPath(); c.moveTo(0, y); c.lineTo(w, y); c.stroke(); }
      const X = f => f * w, Y = f => f * h;
      const breathe = 1 + ph.rise * 0.035;
      c.save(); c.translate(w / 2, h * 0.55); c.scale(breathe, breathe); c.translate(-w / 2, -h * 0.55);
      // ribs
      c.strokeStyle = 'rgba(8,175,162,.13)'; c.lineWidth = 1 * scale;
      for (let i = 0; i < 7; i++) {
        const y = 0.22 + i * 0.095;
        c.beginPath(); c.moveTo(X(0.5), Y(y)); c.bezierCurveTo(X(0.32), Y(y - 0.03), X(0.14), Y(y + 0.02), X(0.12), Y(y + 0.1)); c.stroke();
        c.beginPath(); c.moveTo(X(0.5), Y(y)); c.bezierCurveTo(X(0.68), Y(y - 0.03), X(0.86), Y(y + 0.02), X(0.88), Y(y + 0.1)); c.stroke();
      }
      // lungs (wireframe)
      const lung = (side) => {
        const s = side === 'r' ? -1 : 1;
        const p = new Path2D();
        p.moveTo(X(0.5 + s * 0.06), Y(0.14));
        p.bezierCurveTo(X(0.5 + s * 0.17), Y(0.1), X(0.5 + s * 0.31), Y(0.3), X(0.5 + s * 0.33), Y(0.62));
        p.bezierCurveTo(X(0.5 + s * 0.35), Y(0.8), X(0.5 + s * 0.3), Y(0.9), X(0.5 + s * 0.22), Y(0.88));
        p.bezierCurveTo(X(0.5 + s * 0.15), Y(0.86), X(0.5 + s * 0.09), Y(0.84), X(0.5 + s * 0.07), Y(0.78));
        p.bezierCurveTo(X(0.5 + s * 0.05), Y(0.6), X(0.5 + s * 0.04), Y(0.3), X(0.5 + s * 0.06), Y(0.14));
        return p;
      };
      ['r', 'l'].forEach(sd => {
        const p = lung(sd);
        c.fillStyle = 'rgba(8,175,162,.07)'; c.fill(p);
        c.save(); c.clip(p);
        c.strokeStyle = 'rgba(15,212,196,.22)'; c.lineWidth = 1 * scale;
        for (let y = 0.1; y < 0.95; y += 0.035) { c.beginPath(); c.moveTo(X(0), Y(y)); for (let x = 0; x <= 1; x += 0.05) c.lineTo(X(x), Y(y + Math.sin(x * 9 + y * 4) * 0.006)); c.stroke(); }
        for (let x = 0.1; x < 0.9; x += 0.03) { c.beginPath(); c.moveTo(X(x), Y(0)); c.lineTo(X(x + 0.01), Y(1)); c.stroke(); }
        c.restore();
        c.strokeStyle = 'rgba(15,212,196,.7)'; c.lineWidth = 1.3 * scale; c.stroke(p);
      });
      // trachea & bronchi
      c.strokeStyle = 'rgba(15,212,196,.55)'; c.lineWidth = 1.4 * scale;
      c.beginPath(); c.moveTo(X(0.485), Y(0.02)); c.lineTo(X(0.485), Y(0.36)); c.lineTo(X(0.38), Y(0.47)); c.moveTo(X(0.515), Y(0.02)); c.lineTo(X(0.515), Y(0.36)); c.lineTo(X(0.62), Y(0.47)); c.stroke();
      // heart shadow
      c.fillStyle = 'rgba(229,72,77,.12)'; c.beginPath(); c.ellipse(X(0.55), Y(0.62), X(0.085), Y(0.11), -0.4, 0, Math.PI * 2); c.fill();
      c.restore();
      // zones
      const need = this.d.listenSeconds || 1.8;
      const TONE = { vesicular: '#0fd4c4', reduced: '#e5a50a', absent: '#e5484d', silent: '#e5484d', crackles: '#ffffff', wheeze: '#ffffff', stridor: '#ffffff', gurgle: '#ffffff' };
      const LET = { crackles: 'C', wheeze: 'W', stridor: 'S', gurgle: 'G' };
      Object.entries(this.mapPos()).forEach(([z, p]) => {
        const x = X(p.x), y = Y(p.y);
        const heard = this.listened[z] >= need;
        const cur = z === this.zone;
        const r = (cur ? 11 : 8) * scale;
        if (this.truthShown) {
          const snd = this.zones[z].sound;
          c.fillStyle = TONE[snd] || '#fff'; c.globalAlpha = 0.85;
          c.beginPath(); c.arc(x, y, 9 * scale, 0, Math.PI * 2); c.fill(); c.globalAlpha = 1;
          if (LET[snd]) { c.fillStyle = '#000'; c.font = `700 ${10 * scale}px ${getComputedStyle(document.body).fontFamily}`; c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillText(LET[snd], x, y + 0.5); }
          return;
        }
        if (cur) { c.strokeStyle = 'rgba(255,255,255,.9)'; c.lineWidth = 1.6 * scale; c.beginPath(); c.arc(x, y, r + 5 * scale + (this.held ? Math.sin(ms / 120) * 2 * scale : 0), 0, Math.PI * 2); c.stroke(); }
        c.strokeStyle = heard ? '#0fd4c4' : 'rgba(255,255,255,.55)'; c.lineWidth = 1.6 * scale;
        c.fillStyle = heard ? 'rgba(15,212,196,.85)' : 'rgba(255,255,255,.06)';
        c.beginPath(); c.arc(x, y, r, 0, Math.PI * 2); c.fill(); c.stroke();
        const prog = clamp(this.listened[z] / need, 0, 1);
        if (prog > 0 && prog < 1) { c.strokeStyle = '#0fd4c4'; c.lineWidth = 2.4 * scale; c.beginPath(); c.arc(x, y, r + 2.5 * scale, -Math.PI / 2, -Math.PI / 2 + prog * Math.PI * 2); c.stroke(); }
      });
    },

    /* ── result ── */
    showResult(o) {
      if (this.finished) return;
      this.finished = true;
      this.truthShown = !!o.zones;
      if (o.zones) ZONES.forEach(z => { if (o.zones[z]) this.zones[z].sound = o.zones[z]; });
      const g = o.grade || 'F', r = o.rows || {};
      const okIc = ok => (ok === true ? `<span class="ok">${icon('check')}</span>` : ok === false ? `<span class="no">${icon('x')}</span>` : '<span></span>');
      const rate = r.rate || {}, call = r.call || {}, zones = r.zones || {}, pat = r.pattern || {};
      const fb = (o.feedback || []).map(f => `<li class="${esc(f.tone || '')}">${esc(f.text)}</li>`).join('');
      const rec = (o.recorded || []).map(x => `<span class="chipx sm amber">${icon('clipboard')}${esc(x)}</span>`).join('');
      this.$('.br-result-wrap').innerHTML = `
        <div class="br-result nza-hud solid nza-pop">
          <div class="rh"><div class="grade g-${esc(g)}">${esc(g)}</div><div><h3>${esc(o.title || T('breath_result_title', 'Breathing assessment'))}</h3><p>${esc(T('result_sub', '%s s at the patient · score %s', o.seconds ?? 0, o.score ?? 0))}</p></div></div>
          ${o.error ? `<p class="err">${esc(o.msg || '')}</p>` : `
          <table><thead><tr><th></th><th>${esc(T('your_finding', 'Your finding'))}</th><th>${esc(T('patient', 'Patient'))}</th><th></th></tr></thead><tbody>
            <tr><th>${esc(T('row_rate', 'Rate'))}</th><td>${esc(rate.you ?? '--')}<i>${esc(rate.unit || '/min')}</i></td><td>${esc(rate.patient ?? '--')}<i>${esc(rate.unit || '/min')}</i></td><td class="m">${okIc(rate.ok)}</td></tr>
            <tr><th>${esc(T('row_pattern', 'Pattern'))}</th><td class="dim">--</td><td>${esc(pat.patient || '--')}</td><td></td></tr>
            <tr><th>${esc(T('row_call', 'Sounds'))}</th><td>${esc(call.you || '--')}</td><td>${esc(call.patient || '--')}</td><td class="m">${okIc(call.partial ? null : call.ok)}${call.partial ? '<span class="pt">~</span>' : ''}</td></tr>
            <tr><th>${esc(T('row_zones', 'Zones heard'))}</th><td>${esc(zones.you ?? '0')}<i>/6</i></td><td>${zones.stetho === false ? `<span class="dim">${esc(T('no_stetho_short', 'No stethoscope'))}</span>` : ''}</td><td></td></tr>
          </tbody></table>
          <div class="legend"><span><i class="v"></i>${esc(T('lg_normal', 'Normal'))}</span><span><i class="r"></i>${esc(T('lg_reduced', 'Reduced'))}</span><span><i class="a"></i>${esc(T('lg_absent', 'Absent'))}</span><span><i class="x">C</i>${esc(T('lg_added', 'Crackles / Wheeze / Stridor / Gurgle'))}</span></div>`}
          ${fb ? `<ul class="fb">${fb}</ul>` : ''}
          ${rec ? `<div class="rec"><span class="nza-label">${esc(T('recorded', 'Recorded'))}</span>${rec}</div>` : ''}
        </div>`;
      if (['S', 'A', 'B'].includes(g)) NZA.audio.success(); else NZA.audio.fail();
      this.pp.complete({ title: T('complete', 'Assessment complete'), text: T('br_complete_text', 'The acoustic map now shows what was really there. {Enter} to close.'), label: T('done', 'Done'), onDone: () => NZA.close('breathing') });
    },

    /* ── browser preview ── */
    preview() {
      const body = NZAAssess.body({ focus: 'chest', shirtless: true });
      // demo patient: drowning, RR 28 laboured, right haemothorax 1200 mL
      const rr = 28, list = [], seed = 5150;
      let tt = 0;
      while (tt < 90000) { const iv = 60000 / rr * (1 + (Math.random() - 0.5) * 0.16); list.push([Math.round(iv), 1.0]); tt += iv; }
      const zones = { ru: [1, 450], rm: [2, 120], rl: [2, 30], lu: [0, 1000], lm: [3, 750], ll: [3, 650] };
      const vals = [list.length, ...list.map(b => b[0]), ...list.map(b => b[1] * 1000)];
      ZONES.forEach(z => vals.push(zones[z][0], zones[z][1]));
      NZA.demo('breathing', {
        k: seed, s: encode(seed, vals), stetho: true, countSeconds: 15, listenSeconds: 1.8, noBreathAfter: 6, minTime: 10,
        look: [{ key: 'dusky', tone: 'bad', text: 'Lips and nail beds dusky blue' }, { key: 'accessory', tone: 'warn', text: 'Neck and shoulder muscles pull with each breath' }, { key: 'asym', tone: 'warn', text: 'The right side of the chest barely moves' }],
        patient: { name: 'Lucas Brandt', sex: 'm' }, locale: {},
      });
      NZAAssess.feed('breathing', [], { map: () => { const o = { chest: body.at('chest') }; ZONES.forEach(z => { o[z] = body.at(z); }); return o; } });
      NZA.mock('breathing:finish', res => {
        setTimeout(() => this.showResult({
          score: 81, grade: 'B', seconds: Math.round((now() - this.opened) / 1000), title: 'Breathing assessment',
          rows: { rate: { you: String(this.rate()), patient: '28', unit: '/min', ok: Math.abs(this.rate() - 28) <= 4 }, pattern: { patient: 'Laboured' },
            call: { you: CALL_FB[res.call] || '--', patient: 'Absent right', ok: res.call === 'absent_r', partial: res.call === 'reduced_r' }, zones: { you: String(this.heardCount()), stetho: true } },
          zones: { ru: 'reduced', rm: 'absent', rl: 'absent', lu: 'vesicular', lm: 'crackles', ll: 'crackles' },
          feedback: [{ tone: 'ok', text: 'Right call: absent breath sounds on the right.' }, { tone: 'warn', text: 'Crackles at the left base too: water in the lungs.' }],
          recorded: ['Haemothorax suspected (right)'],
        }), 300);
        return { ok: true };
      });
    },
  });
})();
