/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · Breathing check (app 'breathing')   module: assess
   Layout (NAYZEEE HUD language):
     · procedure column bottom-left (core ProcPanel): dial + instrument list, step spine,
       and in its slot our widgets: "On sight" observation list, the count window strip
       (step 1) and the sound picker (step 3, grouped: whole chest / one side matrix)
     · AX-4 auscultation unit top-right (generic device, no brand): live spectrogram,
       6-pad chest map, instrument list with dwell / sides / R·L air-entry balance
     · tool belt right edge (core), debrief card slides in under the unit at the end
   3 steps:
     1 Watch and count   the chest marker rises with every breath; Space opens a 15 s count
                         window, tap Space on every rise. N = no chest rise.
     2 Sweep the zones   chest piece on the 6 zones (world anchors 'ru' 'rm' 'rl' 'lu' 'lm' 'll'
                         or the pads on the unit), hold the mouse button to listen. Breath
                         sounds are synthesised per zone: vesicular, reduced, absent, crackles,
                         wheeze, stridor, gurgling, silence.
     3 Name the sound    normal / reduced L·R / absent L·R / crackles / wheeze / noisy airway /
                         not breathing (keys 1-9) → debrief + the true pad map on the unit.

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
  const ZONE_TAG = { ru: 'R·UP', rm: 'R·MID', rl: 'R·LOW', lu: 'L·UP', lm: 'L·MID', ll: 'L·LOW' };
  const SPEC_SPAN = 6000;     // ms of history on the spectrogram
  const F0 = 50, F1 = 1600;   // spectrogram band (Hz, log scale)
  const codeLabel = c => ({ Space: 'Space', Enter: 'Enter', Escape: 'ESC' })[c] || String(c || '').replace(/^Key|^Digit/, '');

  NZ.addIcons({
    'br-ban': '<circle cx="12" cy="12" r="8.5"/><path d="M6 6l12 12"/>',
    'br-rise': '<path d="M4 17c2.5 0 3.5-9 8-9s5.5 9 8 9"/><path d="M12 3v3M10 4.5 12 3l2 1.5"/>',
  });

  // glyphs for the sound picker (stroke drawings, 28×14 box)
  const SOUND_GLYPH = {
    normal: '<path d="M1 8c3 0 3.5-5 6.5-5S11 11 14 11s3.5-8 6.5-8S24 8 27 8"/>',
    crackles: '<path d="M3 9v.01M6.5 5v.01M9.5 10v.01M12.5 6v.01M15.5 9.5v.01M18.5 4.5v.01M21.5 8.5v.01M25 6v.01" stroke-width="2.4"/>',
    wheeze: '<path d="M1 7q1.5-5 3 0t3 0 3 0 3 0 3 0 3 0 3 0 3 0 3 0"/>',
    airway: '<path d="M1 7l2-4 2 8 2-6 2 5 2-7 2 8 2-5 2 4 2-6 2 7 2-4 1 2"/>',
    none: '<path d="M1 7h26" stroke-dasharray="2 2.5"/>',
  };
  // a pair of lungs (patient's right drawn on the viewer's left), affected side shaded
  const lungs = (side, kind) => `<svg class="lg2 ${kind}" viewBox="0 0 32 22"><path class="${side === 'r' ? 'af' : ''}" d="M14.5 3.5c-4.5.2-9.5 5.6-9.5 12.6 0 2.1 1.1 3.4 3.1 3.4h6.4z"/><path class="${side === 'l' ? 'af' : ''}" d="M17.5 3.5c4.5.2 9.5 5.6 9.5 12.6 0 2.1-1.1 3.4-3.1 3.4h-6.4z"/><path class="tr" d="M16 1v6M16 7l-2.6 2.4M16 7l2.6 2.4"/></svg>`;

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

  // spectrogram colour ramp: near-black → deep teal → teal → ice → white
  const RAMP = (() => {
    const stops = [[0, [3, 7, 8]], [0.22, [6, 46, 44]], [0.45, [8, 120, 111]], [0.68, [27, 205, 190]], [0.86, [170, 245, 238]], [1, [255, 255, 255]]];
    const out = [];
    for (let i = 0; i < 64; i++) {
      const v = i / 63; let k = 0; while (k < stops.length - 2 && v > stops[k + 1][0]) k++;
      const [a, ca] = stops[k], [b, cb] = stops[k + 1], f = (v - a) / (b - a);
      out.push(`rgb(${ca.map((c, j) => Math.round(c + (cb[j] - c) * f)).join(',')})`);
    }
    return out;
  })();
  const yOfF = (f, h) => h - (Math.log(f / F0) / Math.log(F1 / F0)) * h;
  const gauss = (x, m, s) => Math.exp(-(((x - m) / s) ** 2));

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
        <div class="br-vig"></div>
        <div class="br-right">
          <section class="ax nza-int">
            <header class="ax-top">
              <i class="scr"></i>
              <span class="plate"><b>AX-4</b><em class="unit"></em></span>
              <span class="grille"></span>
              <span class="led"></span>
              <i class="scr"></i>
            </header>
            <div class="ax-glass">
              <div class="ax-bar"><span class="zt">--</span><span class="md"></span><span class="rec"><i></i><b>STBY</b></span></div>
              <div class="ax-spec"><canvas></canvas><div class="fax"><i style="top:${(yOfF(1000, 100)).toFixed(1)}%">1k</i><i style="top:${(yOfF(400, 100)).toFixed(1)}%">400</i><i style="top:${(yOfF(150, 100)).toFixed(1)}%">150</i><i style="top:${(yOfF(60, 100)).toFixed(1)}%">60</i></div><span class="hz">Hz</span><span class="now"></span></div>
              <div class="ax-low">
                <div class="ax-pads"><canvas></canvas><span class="sR">R</span><span class="sL">L</span></div>
                <ul class="ax-list">
                  <li><span class="k-zone"></span><b class="v-zone">--</b></li>
                  <li><span class="k-dwell"></span><b class="v-dwell">0.0<small>s</small></b><i class="dw"><i></i></i></li>
                  <li><span class="k-sides"></span><b class="v-sides">0<small>/2</small></b></li>
                  <li class="bal"><span class="k-bal"></span><span class="balm"><i class="r"></i><i class="l"></i></span></li>
                </ul>
              </div>
              <div class="ax-leg"></div>
            </div>
            <footer class="ax-foot"><span class="keys"><i></i><i></i><i></i></span><span class="stk"></span><span class="sn">SN 04-1187</span></footer>
          </section>
          <div class="br-deb-wrap"></div>
        </div>`;
      this.$ = s => el.querySelector(s);
      this.cvSpec = this.$('.ax-spec canvas');
      this.cvPads = this.$('.ax-pads canvas');
      this.buf = document.createElement('canvas');
      // the stethoscope cursor lives in the unzoomed anchor layer (positions are viewport px)
      this.steth = document.createElement('div');
      this.steth.className = 'br-steth';
      this.steth.innerHTML = '<span class="ring"></span><span class="head"></span><span class="tag"></span>';
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
      this.cvPads.addEventListener('mousemove', e => { this.mapHover = this.mapZoneAt(e); });
      this.cvPads.addEventListener('mouseleave', () => { this.mapHover = null; });
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
      this.count = null; this.counting = false; this.taps = []; this.tapMarks = [];
      this.noRise = false;
      this.listened = {}; this.level = {}; ZONES.forEach(z => { this.listened[z] = 0; this.level[z] = 0; });
      this.zone = null; this.held = false; this.call = null;
      this.done = false; this.finished = false; this.warnedSides = false;
      this.entryPeak = 0;
      this.truthShown = false;
      this.specX = 0; this.specLast = now();
      this.$('.br-deb-wrap').innerHTML = '';
      this.el.classList.remove('br-res', 'br-listen');
      this.labelDevice();
      if (this.pp) this.pp.destroy();
      this.buildPanel();
      this.bindKeys();
      this.chestMarker = NZA.ui.Marker('breathing', 'chest', { anchor: 'chest', dot: 'white', label: T('br_watch', 'Watch the rise') });
      this.chestMarker.el.classList.add('br-chest');
      this.chestMarker.el.classList.remove('hide2');
      this.zoneMarkers = {};
      this.steth.style.display = 'none';
      const b = this.buf.getContext('2d'); b.clearRect(0, 0, this.buf.width, this.buf.height);
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

    /* ── device labels (printed on the unit) ── */
    labelDevice() {
      this.$('.ax-top .unit').textContent = T('ax_unit', 'Auscultation unit');
      this.$('.ax-bar .md').textContent = T('ax_mode', 'Diaphragm · 50–1600 Hz');
      this.$('.k-zone').textContent = T('st_zone', 'Zone');
      this.$('.k-dwell').textContent = T('ax_dwell', 'Dwell');
      this.$('.k-sides').textContent = T('st_sides', 'Sides');
      this.$('.k-bal').textContent = T('ax_balance', 'R · L entry');
      this.$('.ax-foot .stk').innerHTML = `${icon('alert')}${esc(T('ax_sticker', 'Wipe the chest piece between patients'))}`;
      this.$('.ax-leg').innerHTML = [['v', T('lg_normal', 'Normal')], ['r', T('lg_reduced', 'Reduced')], ['a', T('lg_absent', 'Absent')], ['x', T('lg_added', 'Added sound')]]
        .map(([c, l]) => `<span><i class="${c}"></i>${esc(l)}</span>`).join('');
    },

    /* ── procedure HUD ── */
    buildPanel() {
      this.pp = NZA.ui.ProcPanel(this.el, {
        step: 1, total: 3, tag: T('br_tag', 'Breathing check'),
        steps: [T('br_step1', 'Watch and count'), T('br_step2', 'Sweep the zones'), T('br_step3', 'Name the sound')],
        title: T('br_s1_title', 'Watch and count'),
        text: T('br_s1_text', 'Keep your eyes on the chest. {Space} opens a 15 s window, then tap {Space} on every rise.'),
        wide: this.dial(), stats: this.stats(), tools: this.tools(), hints: this.hints(),
        abort: { label: T('hold_stop', 'Hold to leave'), key: 'ESC', seconds: 1.0 },
        onAbort: () => this.abort(),
        onTool: key => this.tool(key),
      });
      const box = document.createElement('div');
      box.className = 'br-slot s1';
      box.innerHTML = `
        <section class="br-sight"><header><span class="kick">${icon('eye')}<span class="st"></span></span><span class="n"></span></header><ul></ul></section>
        <section class="br-strip">
          <header><span class="kick">${icon('br-rise')}<span class="wl"></span></span><span class="cnt"><span class="odoh"></span><small class="rl"></small></span></header>
          <div class="tl"><div class="trk"><i class="fill"></i><span class="marks"></span><span class="head"></span></div><div class="sc"></div></div>
        </section>
        <section class="br-call"></section>`;
      this.pp.slot.prepend(box);
      this.slot = box;
      this.odo = NZA.ui.FlipClock(box.querySelector('.odoh'), { value: '00', small: true, tone: 'teal' });
      box.querySelector('.br-strip .wl').textContent = T('count_window', 'Count window');
      box.querySelector('.br-strip .rl').textContent = T('rises', 'rises');
      const secs = this.d.countSeconds || 15;
      box.querySelector('.br-strip .sc').innerHTML = [0, 1 / 3, 2 / 3, 1].map(f => `<i style="left:${f * 100}%">${Math.round(secs * f)}</i>`).join('') + '<em>s</em>';
      box.querySelector('.br-call').addEventListener('click', e => { const b = e.target.closest('button[data-n]'); if (b) this.pick(Number(b.dataset.n)); });
      this.renderSight();
      this.renderStrip();
    },
    renderSight() {
      const list = this.d.look || [];
      const box = this.slot.querySelector('.br-sight');
      box.querySelector('.st').textContent = T('see_title', 'On sight');
      box.querySelector('.n').textContent = list.length ? String(list.length) : '';
      const tone = t => (t === 'bad' ? 't-red' : t === 'warn' ? 't-amber' : t === 'ok' ? 't-teal' : '');
      box.querySelector('ul').innerHTML = list.map((l, i) => `<li class="${tone(l.tone)}" style="animation-delay:${120 + i * 70}ms"><i class="no"></i><span>${esc(l.text)}</span></li>`).join('')
        || `<li class="t-teal"><i class="no"></i><span>${esc(T('see_nothing', 'Nothing unusual'))}</span></li>`;
    },
    renderStrip() {
      if (!this.slot) return;
      const total = (this.d.countSeconds || 15) * 1000;
      const el = this.slot.querySelector('.br-strip');
      const f = this.count ? clamp(((this.count.ended || now()) - this.count.started) / total, 0, 1) : 0;
      el.querySelector('.fill').style.width = `${f * 100}%`;
      el.querySelector('.head').style.left = `${f * 100}%`;
      el.classList.toggle('run', !!this.counting);
      el.classList.toggle('ended', !!(this.count && !this.counting));
      const marks = this.count ? this.tapMarks.map(tm => `<i class="${tm.good ? 'ok' : 'no'}" style="left:${clamp((tm.ms - this.count.startMs) / total, 0, 1) * 100}%"></i>`).join('') : '';
      const mk = el.querySelector('.marks');
      if (mk.dataset.n !== String(this.tapMarks.length)) { mk.dataset.n = String(this.tapMarks.length); mk.innerHTML = marks; }
    },
    renderCall() {
      const btn = (n, inner, cls = '') => `<button data-n="${n}" class="${cls} ${this.call === CALLS[n - 1] ? 'on' : ''}"><kbd>${n}</kbd>${inner}</button>`;
      const whole = [1, 6, 7, 8, 9].map(n => { const c = CALLS[n - 1]; return btn(n, `<svg class="sg" viewBox="0 0 28 14">${SOUND_GLYPH[c]}</svg><span>${esc(T(`call_${c}`, CALL_FB[c]))}</span>`, 'w'); }).join('');
      this.slot.querySelector('.br-call').innerHTML = `
        <header><span class="kick">${icon('stetho')}${esc(T('call_title', 'What did you hear?'))}</span></header>
        <div class="grp"><span class="gl">${esc(T('grp_both', 'Both sides'))}</span><div class="whole">${whole}</div></div>
        <div class="grp"><span class="gl">${esc(T('grp_one', 'One side only'))}</span>
          <div class="mx">
            <span></span><span class="ch">${esc(T('side_right', 'Right'))}</span><span class="ch">${esc(T('side_left', 'Left'))}</span>
            <span class="rh">${esc(T('lg_reduced', 'Reduced'))}</span>${btn(3, lungs('r', 'red'), 'c')}${btn(2, lungs('l', 'red'), 'c')}
            <span class="rh">${esc(T('lg_absent', 'Absent'))}</span>${btn(5, lungs('r', 'abs'), 'c')}${btn(4, lungs('l', 'abs'), 'c')}
          </div></div>`;
    },
    setSlotStep() {
      if (!this.slot) return;
      this.slot.className = `br-slot s${this.step}${this.finished ? ' fin' : ''}`;
      if (this.step === 3) this.renderCall();
    },
    dial() {
      const total = this.d.countSeconds || 15;
      if (this.step === 1) {
        if (!this.count) return { label: T('st_watching', 'Watching'), value: this.watch.toFixed(1), unit: 's', meter: { value: clamp(this.watch / total, 0, 1), tone: 'white' }, caption: T('cap_ready', '{Space} opens the window') };
        const el = ((this.count.ended || now()) - this.count.started) / 1000;
        return { label: T('st_breaths', 'Rises'), value: String(this.taps.length), meter: { value: clamp(el / total, 0, 1), tone: this.counting ? '' : 'white' },
          caption: this.counting ? T('cap_left', '%s s left', Math.max(0, Math.ceil(total - el))) : T('br_cap_rate', '%s a minute', this.rate()), captionTone: this.counting ? '' : 'teal' };
      }
      if (this.step === 2) {
        const h = this.heardCount();
        return { label: T('ax_zones', 'Zones'), value: String(h), unit: '/6', meter: { value: h / 6, tone: h >= 6 ? '' : 'white' },
          caption: this.zone ? T(`zone_${this.zone}`, ZONE_FB[this.zone]) : T('cap_place', 'Move over a zone'), captionTone: this.zone ? 'teal' : '' };
      }
      const r = this.noRise ? 0 : (this.count ? this.rate() : null);
      return { label: T('st_rate', 'Your rate'), value: r === null ? '--' : String(r), unit: T('per_min', '/min'), meter: { value: clamp((r || 0) / 40, 0, 1), tone: '' },
        caption: this.call ? T(`call_${this.call}`, CALL_FB[this.call]) : T('cap_pick', 'Pick what you heard'), captionTone: this.call ? 'teal' : '' };
    },
    stats() {
      if (this.step === 1) {
        const off = this.tapMarks.filter(t => !t.good).length;
        return [
          this.count ? { id: 'watch', label: T('st_watching', 'Watching'), value: this.watch.toFixed(1), unit: 's' } : { id: 'count', label: T('st_breaths', 'Rises'), value: '--' },
          { id: 'rate', label: T('st_rate', 'Your rate'), value: this.count && !this.counting ? this.rate() : '--', unit: T('per_min', '/min'), tone: this.count && !this.counting ? 'teal' : '' },
          { id: 'off', label: T('st_off', 'Off the rise'), value: off, tone: off ? 'amber' : '' },
        ];
      }
      if (this.step === 2) {
        const sides = this.sidesDone();
        return [
          { id: 'zone', label: T('st_zone', 'Zone'), value: this.zone ? T(`zone_${this.zone}`, ZONE_FB[this.zone]) : '--', small: true, tone: this.zone ? 'teal' : '' },
          { id: 'sides', label: T('st_sides', 'Sides'), value: sides, unit: '/2', tone: sides >= 2 ? 'teal' : '' },
          { id: 'entry', label: T('br_air', 'Air entry'), value: Math.round(this.entryPeak * 100), unit: '%' },
        ];
      }
      return [
        { id: 'rate', label: T('st_rate', 'Your rate'), value: this.noRise ? 0 : (this.count ? this.rate() : '--'), unit: T('per_min', '/min') },
        { id: 'heard', label: T('st_heard', 'Heard'), value: this.heardCount(), unit: '/6' },
        { id: 'call', label: T('st_call', 'Your call'), value: this.call ? T(`call_${this.call}`, CALL_FB[this.call]) : '--', small: true, tone: this.call ? 'teal' : '' },
      ];
    },
    hints() {
      if (this.step === 1) return [{ keys: [codeLabel(this.keysCfg.count)], label: T('h_rise', 'on every rise') }];
      if (this.step === 2) return [{ keys: [T('mouse', 'Mouse')], label: T('h_move', 'move the chest piece') }, { keys: [T('lmb', 'LMB')], label: T('h_listen', 'hold to listen') }];
      return [{ keys: ['1-9'], label: T('h_pick', 'pick a sound') }, { keys: [codeLabel(this.keysCfg.submit)], label: T('h_submit', 'submit') }];
    },
    tools() {
      const k = this.keysCfg;
      if (this.step === 1) {
        const counting = !!this.count && this.counting;
        return [
          { key: codeLabel(k.count), label: counting ? T('tool_tap_rise', 'Rise') : T('br_tool_count', 'Open window'), icon: counting ? 'br-rise' : 'timer', state: counting ? 'active' : (this.count ? 'done' : '') },
          { key: codeLabel(k.none), label: T('tool_no_rise', 'No rise at all'), icon: 'br-ban', state: this.count ? 'locked' : '' },
          { key: codeLabel(k.submit), label: T('tool_next', 'Go listen'), icon: 'stetho', state: (this.count && !this.counting) || this.noRise ? 'active' : 'locked' },
        ];
      }
      if (this.step === 2) {
        return [
          { key: T('lmb', 'LMB'), label: T('tool_hold_listen', 'Listen'), icon: 'stetho', state: this.held && this.zone ? 'active' : '' },
          { key: codeLabel(k.submit), label: T('tool_done_listen', 'Name the sound'), icon: 'arrow-r', state: this.heardCount() ? 'active' : '' },
        ];
      }
      return [{ key: codeLabel(k.submit), label: T('submit', 'Submit'), icon: 'check', state: this.call ? 'active' : 'locked' }];
    },
    refresh(full) {
      if (!this.pp) return;
      this.pp.set(full ? { wide: this.dial(), stats: this.stats(), tools: this.tools(), hints: this.hints() } : { wide: this.dial(), stats: this.stats() });
    },
    tool(key) {
      const k = this.keysCfg;
      if (key === codeLabel(k.count)) return this.space();
      if (key === codeLabel(k.none)) return this.noRiseCall();
      if (key === codeLabel(k.submit)) return this.enter();
      if (/^[1-9]$/.test(key)) return this.pick(Number(key));
      return null;
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
    // loudness profile of a zone right now → audio + spectrogram
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
        this.odo.set('00');
        this.pp.set({ title: T('br_s1b_title', 'Count the rises'), text: T('br_s1b_text', 'Tap {Space} each time the chest **lifts**. Keep going until the window closes.') });
        this.refresh(true);
        this.renderStrip();
        NZA.audio.beep(1040, 70, 0.06);
        return;
      }
      if (!this.counting) return;
      const ph = this.phase(ms - 400);
      const good = !this.apnoea && (ph.inInsp || this.phase(ms).inInsp || this.phase(ms - 700).inInsp);
      this.taps.push(Math.round(ms));
      this.tapMarks.push({ ms, good });
      if (good) NZA.audio.tone(1150, 45, { vol: 0.06, type: 'triangle' }); else NZA.audio.tone(240, 70, { vol: 0.07, type: 'triangle' });
      this.odo.set(String(this.taps.length).padStart(2, '0'));
      this.renderStrip();
      this.refresh(false);
    },
    noRiseCall() {
      if (this.done || this.step !== 1 || this.count) return;
      const need = this.d.noBreathAfter || 6;
      if (this.watch < need) return this.pp.flash('warn', T('keep_watching', 'Watch for another %s s before you rule it out.', (need - this.watch).toFixed(1)));
      this.noRise = true;
      this.pp.flash('bad', T('no_rise_noted', 'Logged: **no chest rise**. Listen to confirm, or name it.'), 3500);
      this.toListen();
    },
    enter() {
      if (this.done) { if (this.finished) NZA.close('breathing'); return; }
      if (this.step === 1) {
        if ((this.count && !this.counting) || this.noRise) this.toListen();
        else this.pp.flash('warn', T('count_first', 'Count the rises first, or log no rise with {N}.'));
        return;
      }
      if (this.step === 2) {
        if (this.sidesDone() < 2 && this.d.stetho !== false && !this.warnedSides) {
          this.warnedSides = true;
          return this.pp.flash('warn', T('both_sides', 'Compare **both sides** first. {Enter} again to skip it.'));
        }
        return this.toCall();
      }
      if (this.step === 3) {
        if (!this.call) return this.pp.flash('warn', T('pick_call', 'Pick a sound first.'));
        this.submit();
      }
    },
    pick(n) {
      if (this.done || this.step !== 3) return;
      const c = CALLS[n - 1]; if (!c) return;
      this.call = c;
      NZA.audio.click(820);
      this.refresh(true);
      this.renderCall();
    },
    toListen() {
      this.counting = false;
      this.step = 2;
      this.chestMarker.set({ label: '' });
      this.chestMarker.el.classList.add('hide2');
      this.setSlotStep();
      NZA.post('breathing:step', { step: 2 });
      if (this.d.stetho === false) {
        this.pp.set({ step: 2, title: T('br_s2_title', 'Sweep the zones'), text: T('br_no_stetho', 'No stethoscope on you. Name it from what you saw.') });
        this.pp.flash('warn', T('no_stetho', 'You are not carrying a stethoscope.'), 0);
        setTimeout(() => this.toCall(), 1800);
        return;
      }
      this.el.classList.add('br-listen');
      document.body.classList.add('br-nocursor');
      this.steth.style.display = '';
      this.pp.set({ step: 2, title: T('br_s2_title', 'Sweep the zones'), text: T('br_s2_text', 'Set the chest piece on a zone and **hold the mouse button**. Work top to bottom and compare each level left against right.') });
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
      this.pp.set({ step: 3, title: T('br_s3_title', 'Name the sound'), text: T('br_s3_text', 'Pick what you heard with {1}–{9}, then {Enter}.') });
      this.setSlotStep();
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
        this.pp.flash('warn', T('too_fast', 'Stay with the patient a little longer.'), 0);
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
      this.pp.set({ title: T('checking', 'Scoring your findings…'), text: '', tools: [] });
      NZA.post('breathing:finish', result).then(r => { if (r && r.outcome) this.showResult(r.outcome); });
    },
    abort() {
      if (this.finished) return NZA.close('breathing');
      this.done = true;
      NZA.post('breathing:abort', {});
      NZA.close('breathing');
    },

    /* ── chest piece placement ── */
    zonePoints() {
      const W = window.innerWidth, H = window.innerHeight, out = {};
      ZONES.forEach(z => { const a = this.anc.get(z); if (a && a.visible !== false) out[z] = { x: a.x * W, y: a.y * H }; });
      return out;
    },
    mapZoneAt(e) {
      const r = this.cvPads.getBoundingClientRect();
      const x = (e.clientX - r.left) / r.width, y = (e.clientY - r.top) / r.height;
      let best = null, bd = 0.11;
      Object.entries(this.mapPos()).forEach(([z, p]) => { const d = Math.hypot(p.x - x, (p.y - y) * r.height / r.width); if (d < bd) { bd = d; best = z; } });
      return best;
    },
    mapPos() {   // pad centres on the unit's chest map (fractions of the canvas; patient's right on the left)
      return { ru: { x: 0.36, y: 0.3 }, rm: { x: 0.31, y: 0.52 }, rl: { x: 0.33, y: 0.74 }, lu: { x: 0.64, y: 0.3 }, lm: { x: 0.69, y: 0.52 }, ll: { x: 0.67, y: 0.74 } };
    },
    updateSteth() {
      if (this.step !== 2 || !this.mousePx) { this.zone = this.mapHover && this.step === 2 ? this.mapHover : null; return; }
      const pts = this.zonePoints();
      let best = null, bd = 70 * (NZA.zoom || 1);
      Object.entries(pts).forEach(([z, p]) => { const d = Math.hypot(p.x - this.mousePx.x, p.y - this.mousePx.y); if (d < bd) { bd = d; best = z; } });
      if (this.mapHover) best = this.mapHover;
      this.zone = best;
      const at = best && pts[best] && !this.mapHover ? pts[best] : this.mousePx;
      this.steth.style.transform = `translate(${at.x}px, ${at.y}px)`;
      this.steth.classList.toggle('on', !!best);
      this.steth.classList.toggle('held', !!(best && this.held));
      this.steth.classList.toggle('pad', !!this.mapHover);
      const tag = best ? ZONE_TAG[best] : '';
      const tg = this.steth.querySelector('.tag');
      if (tg.textContent !== tag) tg.textContent = tag;
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
          this.pp.set({ title: T('br_s1c_title', 'Window closed'), text: T('br_s1c_text', 'You counted **%s rises a minute**. {Enter} to pick up the stethoscope.', this.rate()) });
          this.refresh(true);
          this.renderStrip();
          NZA.audio.beep(880, 70, 0.06);
        }
        if (this.counting) this.renderStrip();
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
          this.level[this.zone] = Math.max(this.level[this.zone] * 0.999, snd.level);
        }
      }
      const ev = { crackle: false, bubble: false };
      if (snd) {
        if (snd.crackle > 0.05 && Math.random() < snd.crackle * 0.55) { this.synth.crackle(0.12 * snd.crackle); ev.crackle = true; }
        if (snd.bubble > 0.05 && Math.random() < snd.bubble * 0.08) { this.synth.bubble(0.18); ev.bubble = true; }
        this.synth.set({ on: true, breath: snd.breath, harsh: snd.harsh, tone: snd.tone, toneF: snd.toneF, lp: snd.lp, bpf: snd.bpf, hiss: 0.012 });
        this.entryPeak = Math.max(this.entryPeak * 0.985, snd.level);
      } else {
        this.synth.set({ on: this.step === 2 && this.held, breath: 0, harsh: 0, tone: 0, hiss: this.held ? 0.03 : 0 });
        this.entryPeak *= 0.96;
      }
      this.drawSpec(snd, ev);
      this.drawPads(ms, ph);
      this.updateDevice();
      this.statT = (this.statT || 0) + dt;
      if (this.statT > 0.15 && !this.done) {
        this.statT = 0;
        if (this.step === 2) {
          const before = this.toolSig;
          this.toolSig = `${this.held && this.zone}|${this.heardCount()}`;
          this.refresh(before !== this.toolSig);
        } else this.refresh(false);
      }
      this.raf = requestAnimationFrame(x => this.frame(x));
    },

    /* ── AX-4 unit ── */
    updateDevice() {
      const z = this.zone, need = this.d.listenSeconds || 1.8;
      const zt = this.$('.ax-bar .zt');
      const label = this.step === 2 ? (z ? ZONE_TAG[z] : T('ax_seek', 'SEEK')) : (this.step === 1 ? T('ax_standby', 'STANDBY') : T('ax_review', 'REVIEW'));
      if (zt.textContent !== label) zt.textContent = label;
      zt.className = `zt ${z && this.step === 2 ? 'on' : ''}`;
      const live = !!(this.held && z && this.step === 2);
      const rec = this.$('.ax-bar .rec');
      rec.className = `rec ${live ? 'live' : ''}`;
      const rb = rec.querySelector('b'), rt = live ? T('ax_live', 'LIVE') : T('ax_stby', 'STBY');
      if (rb.textContent !== rt) rb.textContent = rt;
      this.$('.ax-top .led').className = `led ${live ? 'on' : ''}`;
      const vz = this.$('.v-zone'), zn = z ? T(`zone_${z}`, ZONE_FB[z]) : '--';
      if (vz.textContent !== zn) vz.textContent = zn;
      const dw = z ? this.listened[z] : 0;
      this.$('.v-dwell').innerHTML = `${Math.min(dw, 99).toFixed(1)}<small>s</small>`;
      this.$('.ax-list .dw i').style.width = `${clamp(dw / need, 0, 1) * 100}%`;
      this.$('.ax-list .dw').classList.toggle('ok', dw >= need);
      this.$('.v-sides').innerHTML = `${this.sidesDone()}<small>/2</small>`;
      const avg = s => { const zs = ZONES.filter(x => x[0] === s && this.listened[x] > 0.3); return zs.length ? zs.reduce((a, x) => a + this.level[x], 0) / zs.length : 0; };
      this.$('.balm .r').style.width = `${clamp(avg('r'), 0, 1) * 50}%`;
      this.$('.balm .l').style.width = `${clamp(avg('l'), 0, 1) * 50}%`;
    },
    // scrolling spectrogram (log frequency, newest on the right)
    drawSpec(snd, ev) {
      const cv = this.cvSpec;
      const { w, h, scale } = NZA.fitCanvas(cv);
      const buf = this.buf;
      if (buf.width !== w || buf.height !== h) { buf.width = w; buf.height = h; const b0 = buf.getContext('2d'); b0.fillStyle = RAMP[0]; b0.fillRect(0, 0, w, h); }
      const b = buf.getContext('2d');
      const t = now(), dt = Math.min(200, t - this.specLast); this.specLast = t;
      this.specX += (dt / SPEC_SPAN) * w;
      const dx = Math.floor(this.specX);
      if (dx >= 1) {
        this.specX -= dx;
        b.drawImage(buf, -dx, 0);
        const NB = 44, bh = h / NB;
        for (let i = 0; i < NB; i++) {
          const yc = h - (i + 0.5) * bh;
          const lf = Math.log(F0) + ((i + 0.5) / NB) * Math.log(F1 / F0), f = Math.exp(lf);
          let e = 0.05 + Math.random() * 0.05;
          if (this.step === 2 && this.held) e += 0.04 * gauss(lf, Math.log(90), 0.6);       // handling rumble
          if (snd) {
            const lpk = f < snd.lp ? 1 : Math.exp(-(f - snd.lp) / 160);
            e += snd.breath * 1.5 * gauss(lf, Math.log(snd.bpf * 0.7), 0.85) * lpk * (0.75 + Math.random() * 0.5);
            e += snd.harsh * 1.1 * gauss(lf, Math.log(1250), 0.32) * (0.7 + Math.random() * 0.6);
            if (snd.tone > 0.01) e += snd.tone * 5 * (gauss(lf, Math.log(snd.toneF), 0.05) + 0.45 * gauss(lf, Math.log(snd.toneF * 2), 0.05));
            if (snd.bubble > 0.05) e += snd.bubble * 0.25 * gauss(lf, Math.log(220), 0.4) * Math.random();
            if (ev.crackle && f > 120 && Math.random() < 0.75) e += 0.25 + Math.random() * 0.35;
            if (ev.bubble) e += 0.6 * gauss(lf, Math.log(200), 0.45);
          }
          b.fillStyle = RAMP[clamp(Math.round(clamp(e, 0, 1) * 63), 0, 63)];
          b.fillRect(w - dx, yc - bh / 2 - 0.5, dx, bh + 1);
        }
      }
      const c = cv.getContext('2d');
      c.drawImage(buf, 0, 0);
      // frequency grid + scan line
      c.strokeStyle = 'rgba(255,255,255,.07)'; c.lineWidth = 1;
      [60, 150, 400, 1000].forEach(f => { const y = Math.round(yOfF(f, h)) + 0.5; c.beginPath(); c.moveTo(0, y); c.lineTo(w, y); c.stroke(); });
      c.strokeStyle = 'rgba(255,255,255,.05)';
      for (let x = w - ((t / SPEC_SPAN * w) % (w / 6)); x > 0; x -= w / 6) { c.beginPath(); c.moveTo(Math.round(x) + 0.5, 0); c.lineTo(Math.round(x) + 0.5, h); c.stroke(); }
      const g = c.createLinearGradient(w - 18 * scale, 0, w, 0);
      g.addColorStop(0, 'rgba(15,212,196,0)'); g.addColorStop(1, snd ? 'rgba(15,212,196,.35)' : 'rgba(255,255,255,.08)');
      c.fillStyle = g; c.fillRect(w - 18 * scale, 0, 18 * scale, h);
    },
    // 6-pad chest map on the unit
    drawPads(ms, ph) {
      const cv = this.cvPads;
      const { w, h, scale } = NZA.fitCanvas(cv);
      const c = cv.getContext('2d');
      c.clearRect(0, 0, w, h);
      const X = f => f * w, Y = f => f * h;
      const breathe = 1 + ph.rise * 0.025;
      c.save(); c.translate(w / 2, h * 0.55); c.scale(breathe, breathe); c.translate(-w / 2, -h * 0.55);
      // torso silhouette
      const torso = new Path2D();
      torso.moveTo(X(0.42), Y(0.04)); torso.lineTo(X(0.58), Y(0.04));
      torso.bezierCurveTo(X(0.6), Y(0.1), X(0.7), Y(0.11), X(0.86), Y(0.15));
      torso.bezierCurveTo(X(0.92), Y(0.18), X(0.9), Y(0.4), X(0.86), Y(0.62));
      torso.bezierCurveTo(X(0.84), Y(0.8), X(0.8), Y(0.94), X(0.76), Y(0.98));
      torso.lineTo(X(0.24), Y(0.98));
      torso.bezierCurveTo(X(0.2), Y(0.94), X(0.16), Y(0.8), X(0.14), Y(0.62));
      torso.bezierCurveTo(X(0.1), Y(0.4), X(0.08), Y(0.18), X(0.14), Y(0.15));
      torso.bezierCurveTo(X(0.3), Y(0.11), X(0.4), Y(0.1), X(0.42), Y(0.04));
      const tg = c.createLinearGradient(0, 0, 0, h);
      tg.addColorStop(0, 'rgba(15,212,196,.10)'); tg.addColorStop(1, 'rgba(15,212,196,.02)');
      c.fillStyle = tg; c.fill(torso);
      c.strokeStyle = 'rgba(15,212,196,.45)'; c.lineWidth = 1.2 * scale; c.stroke(torso);
      // ribs + sternum
      c.save(); c.clip(torso);
      c.strokeStyle = 'rgba(255,255,255,.07)'; c.lineWidth = 1 * scale;
      for (let i = 0; i < 6; i++) {
        const y = 0.2 + i * 0.12;
        c.beginPath(); c.moveTo(X(0.47), Y(y)); c.quadraticCurveTo(X(0.22), Y(y - 0.05), X(0.12), Y(y + 0.12)); c.stroke();
        c.beginPath(); c.moveTo(X(0.53), Y(y)); c.quadraticCurveTo(X(0.78), Y(y - 0.05), X(0.88), Y(y + 0.12)); c.stroke();
      }
      c.restore();
      c.strokeStyle = 'rgba(255,255,255,.14)'; c.lineWidth = 2 * scale;
      c.beginPath(); c.moveTo(X(0.5), Y(0.14)); c.lineTo(X(0.5), Y(0.66)); c.stroke();
      c.restore();
      // pads
      const need = this.d.listenSeconds || 1.8;
      const TONE = { vesicular: '#0fd4c4', reduced: '#f3c35a', absent: '#ff5a5f', silent: '#ff5a5f', crackles: '#ffffff', wheeze: '#ffffff', stridor: '#ffffff', gurgle: '#ffffff' };
      const LET = { crackles: 'C', wheeze: 'W', stridor: 'S', gurgle: 'G' };
      const hex = (x, y, r) => { c.beginPath(); for (let i = 0; i < 6; i++) { const a = Math.PI / 6 + i * Math.PI / 3; c[i ? 'lineTo' : 'moveTo'](x + Math.cos(a) * r, y + Math.sin(a) * r); } c.closePath(); };
      Object.entries(this.mapPos()).forEach(([z, p]) => {
        const x = X(p.x), y = Y(p.y), heard = this.listened[z] >= need, cur = z === this.zone, r = 10 * scale;
        if (this.truthShown) {
          const snd = this.zones[z].sound, col = TONE[snd] || '#fff';
          c.shadowColor = col; c.shadowBlur = 10 * scale;
          hex(x, y, r); c.fillStyle = col; c.globalAlpha = 0.9; c.fill(); c.globalAlpha = 1; c.shadowBlur = 0;
          if (!heard) { c.setLineDash([2 * scale, 2 * scale]); c.strokeStyle = 'rgba(255,255,255,.7)'; c.lineWidth = 1.2 * scale; hex(x, y, r + 3.5 * scale); c.stroke(); c.setLineDash([]); }
          if (LET[snd]) { c.fillStyle = '#05100f'; c.font = `700 ${10 * scale}px ${getComputedStyle(document.body).fontFamily}`; c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillText(LET[snd], x, y + 0.5 * scale); }
          return;
        }
        if (cur) {
          const pr = r + (5 + (this.held ? Math.sin(ms / 110) * 1.5 : 0)) * scale;
          c.strokeStyle = 'rgba(255,255,255,.85)'; c.lineWidth = 1.5 * scale; hex(x, y, pr); c.stroke();
        }
        hex(x, y, r);
        c.fillStyle = heard ? 'rgba(15,212,196,.85)' : 'rgba(6,10,11,.85)'; c.fill();
        c.strokeStyle = heard ? '#7af0e6' : 'rgba(255,255,255,.4)'; c.lineWidth = 1.3 * scale; c.stroke();
        const prog = clamp(this.listened[z] / need, 0, 1);
        if (prog > 0 && prog < 1) { c.strokeStyle = '#0fd4c4'; c.lineWidth = 2.2 * scale; c.lineCap = 'round'; c.beginPath(); c.arc(x, y, r + 3 * scale, -Math.PI / 2, -Math.PI / 2 + prog * Math.PI * 2); c.stroke(); c.lineCap = 'butt'; }
        if (heard) { c.strokeStyle = '#03201d'; c.lineWidth = 1.8 * scale; c.beginPath(); c.moveTo(x - 4 * scale, y); c.lineTo(x - 1 * scale, y + 3 * scale); c.lineTo(x + 4.5 * scale, y - 3 * scale); c.stroke(); }
      });
    },

    /* ── debrief ── */
    showResult(o) {
      if (this.finished) return;
      this.finished = true;
      this.truthShown = !!o.zones;
      if (o.zones) ZONES.forEach(z => { if (o.zones[z]) this.zones[z].sound = o.zones[z]; });
      this.el.classList.add('br-res');
      const r = o.rows || {};
      const score = clamp(Math.round(o.score ?? 0), 0, 100);
      const tone = score >= 75 ? 'teal' : score >= 50 ? 'amber' : 'red';
      const verdict = score >= 90 ? T('vd_5', 'Spot on') : score >= 75 ? T('vd_4', 'Solid read') : score >= 55 ? T('vd_3', 'Close call') : score >= 35 ? T('vd_2', 'Off the mark') : T('vd_1', 'Missed it');
      const rate = r.rate || {}, call = r.call || {}, zones = r.zones || {}, pat = r.pattern || {};
      const calls = [rate.ok, call.partial ? null : call.ok].filter(x => x !== undefined && x !== null);
      const right = calls.filter(Boolean).length;
      const mark = (ok, partial) => (partial ? '<span class="mk pt">~</span>' : ok === true ? `<span class="mk ok">${icon('check')}</span>` : ok === false ? `<span class="mk no">${icon('x')}</span>` : '<span class="mk"></span>');
      const you = parseFloat(rate.you), pv = parseFloat(rate.patient);
      const max = Math.max(40, Math.ceil(Math.max(isNaN(you) ? 0 : you, isNaN(pv) ? 0 : pv) / 10) * 10 + 10);
      const X = v => `${clamp(v / max, 0, 1) * 100}%`;
      const ticks = Array.from({ length: max / 10 + 1 }, (_, i) => `<i style="left:${X(i * 10)}"><em>${i * 10}</em></i>`).join('');
      const rateBar = `<div class="rs-bar">${ticks}${!isNaN(pv) ? `<span class="band" style="left:${X(Math.max(0, pv - 4))};width:calc(${X(Math.min(max, pv + 4))} - ${X(Math.max(0, pv - 4))})"></span><span class="tru" style="left:${X(pv)}"></span>` : ''}${!isNaN(you) ? `<span class="you ${rate.ok ? 'ok' : 'no'}" style="left:${X(you)}"></span>` : ''}</div>`;
      const callTone = call.ok ? 'ok' : call.partial ? 'pt' : 'no';
      const truthPads = ZONES.map(z => { const s = this.zones[z].sound; const k = s === 'vesicular' ? 'v' : s === 'reduced' ? 'r' : (s === 'absent' || s === 'silent') ? 'a' : 'x'; return `<i class="${k} ${this.listened[z] >= (this.d.listenSeconds || 1.8) ? 'hd' : ''}" title="${esc(T(`zone_${z}`, ZONE_FB[z]))}"></i>`; });
      const fb = (o.feedback || []).map(f => `<li class="t-${esc(f.tone || 'info')}"><i></i><span>${esc(f.text)}</span></li>`).join('');
      const rec = (o.recorded || []).map(x => `<span class="lg">${icon('clipboard')}${esc(x)}</span>`).join('');
      this.$('.br-deb-wrap').innerHTML = `
        <section class="br-deb t-${tone}">
          <header class="dh">
            <div class="sr"><svg class="rs" viewBox="0 0 88 88"><circle class="bg" cx="44" cy="44" r="38"/><circle class="fg" cx="44" cy="44" r="38" stroke-dasharray="${(2 * Math.PI * 38).toFixed(2)}" stroke-dashoffset="${(2 * Math.PI * 38).toFixed(2)}"/></svg><div class="in"><span class="odoh"></span><small>${esc(T('score', 'Score'))}</small></div></div>
            <div class="dt"><span class="kick">${esc(o.title || T('breath_result_title', 'Breathing debrief'))}</span><h3>${esc(verdict)}</h3>
              <p>${esc(T('result_sub', '%s s with the patient', o.seconds ?? 0))}${calls.length ? ` · ${esc(T('calls_right', '%s of %s calls right', right, calls.length))}` : ''}</p></div>
          </header>
          ${o.error ? `<p class="err">${icon('alert')}${esc(o.msg || '')}</p>` : `
          <div class="rows">
            <div class="rw"><div class="rl"><span>${esc(T('row_rate', 'Rate'))}</span>${mark(rate.ok)}</div>
              <div class="rv"><div class="nums"><b>${esc(rate.you ?? '--')}</b><i>${esc(T('vs', 'vs'))}</i><b class="t">${esc(rate.patient ?? '--')}</b><em>${esc(rate.unit || T('per_min', '/min'))}</em>${pat.patient ? `<span class="pat">${esc(pat.patient)}</span>` : ''}</div>${rateBar}</div></div>
            <div class="rw"><div class="rl"><span>${esc(T('row_call', 'Sounds'))}</span>${mark(call.ok, call.partial)}</div>
              <div class="rv"><div class="cmp"><span class="you ${callTone}"><em>${esc(T('you_short', 'you'))}</em>${esc(call.you || '--')}</span>${icon('arrow-r')}<span class="tru">${icon('check')}${esc(call.patient || '--')}</span></div></div></div>
            <div class="rw"><div class="rl"><span>${esc(T('row_zones', 'Zones'))}</span></div>
              <div class="rv"><div class="zp"><span class="side">R</span>${truthPads.slice(0, 3).join('')}<span class="gap"></span>${truthPads.slice(3).join('')}<span class="side">L</span>
                <span class="hc">${zones.stetho === false ? esc(T('no_stetho_short', 'No stethoscope')) : esc(T('heard_n', '%s of 6 heard', zones.you ?? this.heardCount()))}</span></div></div></div>
          </div>`}
          ${fb ? `<ul class="fb">${fb}</ul>` : ''}
          ${rec ? `<div class="rec"><span class="kick">${esc(T('recorded', 'Logged to chart'))}</span>${rec}</div>` : ''}
        </section>`;
      const odo = NZA.ui.FlipClock(this.$('.br-deb .odoh'), { value: '00', tone, small: true });
      requestAnimationFrame(() => requestAnimationFrame(() => {
        const fg = this.$('.br-deb .sr .fg');
        if (fg) fg.style.strokeDashoffset = (2 * Math.PI * 38 * (1 - score / 100)).toFixed(2);
        odo.set(String(score).padStart(2, '0'));
      }));
      if (score >= 75) NZA.audio.success(); else NZA.audio.fail();
      this.setSlotStep();
      this.pp.complete({ title: T('complete', 'Check finished'), text: T('br_complete_text', 'The unit now shows what each zone really sounded like. {Enter} when you are ready.'), label: T('done', 'Done'), onDone: () => NZA.close('breathing') });
      const mine = this.noRise ? T('finding_apnoea', 'Not breathing') : [this.count ? `${this.rate()}${T('per_min', '/min')}` : '', this.call ? T(`call_${this.call}`, CALL_FB[this.call]) : ''].filter(Boolean).join(' · ');
      this.pp.flash(tone === 'teal' ? 'ok' : tone === 'amber' ? 'warn' : 'bad', T('your_call', 'Your call: %s', mine || '--'), 0);
      // the debrief owns the right edge now: drop the cancel ring (Esc still closes)
      this.pp.set({ abort: false, hints: [{ keys: ['Enter'], label: T('h_done', 'done') }, { keys: ['ESC'], label: T('h_close', 'close') }] });
    },

    /* ── browser preview ── */
    preview() {
      const body = NZAAssess.body({ focus: 'chest', shirtless: true });
      // demo patient: pulled from the water, RR 28 laboured, right haemothorax
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
          score: 81, grade: 'B', seconds: Math.round((now() - this.opened) / 1000), title: 'Breathing debrief',
          rows: { rate: { you: String(this.rate()), patient: '28', unit: '/min', ok: Math.abs(this.rate() - 28) <= 4 }, pattern: { patient: 'Laboured' },
            call: { you: CALL_FB[res.call] || '--', patient: 'Absent right', ok: res.call === 'absent_r', partial: res.call === 'reduced_r' }, zones: { you: String(this.heardCount()), stetho: true } },
          zones: { ru: 'reduced', rm: 'absent', rl: 'absent', lu: 'vesicular', lm: 'crackles', ll: 'crackles' },
          feedback: [{ tone: 'ok', text: 'Good call: no air moving on the right.' }, { tone: 'warn', text: 'Crackles at the left base as well: water in that lung.' }],
          recorded: ['Haemothorax suspected (right)'],
        }), 300);
        return { ok: true };
      });
    },
  });
})();
