/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · Suture (app 'suture')                module: suture
   Close a laceration / stab wound (or an extraction wound once the bleeding is
   controlled) in a full-screen 3D close-up built on core/nza3d.js.

   Steps on the shared procedure panel (NZA.ui.ProcPanel):
     1 Irrigate       tool 1 Saline      hold LMB, sweep the jet along the cut until the grime
                                         and clot are rinsed out (contamination → 0 %)
     2 Anaesthetise   tool 2 Lidocaine   hold LMB on each marked point along both edges; a
                                         wheal rises, the pain meter drops. Skipping it (press 4)
                                         means pain → flinches (camera shake, bites move)
     (any time)       tool 3 Gauze       hold LMB to blot blood when it pools over the field
     3 Suture         tool 4 Needle      press on the near edge at the marker, pull across to the
                                         far edge, release to tie; bite, angle and spacing judged
     4 Dressing       tool 5 Dressing    pick the dressing up by its edge, lay it over the cut,
                                         release, then rub it down until it sticks
   Then the result card (grade, breakdown, feedback) — Enter closes.

   Lua → JS   open { locale, patient{name,sex}, injury{id,type,region,regionLabel,label,severity,
                     length,depth,bleed,contamination,pain}, tone, hair, seed, items{lidocaine,gauze},
                     cfg{…Config.Suture.Game} }
              result (server outcome)        abort (server ended the session)
   JS → Lua   suture:finish { result }  → { ok, outcome? | pending }
              suture:abort  {}          suture:flinch { pain }      suture:close (core)
   ═══════════════════════════════════════════════════════════ */
(() => {
  const esc = NZA.esc, icon = NZA.icon, clamp = NZA.clamp;
  const MM = 0.001;
  const lerp = (a, b, t) => a + (b - a) * t;
  let LOC = {};
  const T = (k, fb, ...a) => { let s = LOC[k] !== undefined ? String(LOC[k]) : fb; a.forEach(v => { s = s.replace(/%[sd]/, v); }); return s; };
  const pct = v => Math.round(clamp(v, 0, 1) * 100);
  const hash = s => { let h = 2166136261; s = String(s); for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); } return h >>> 0; };
  const rng = seed => { let a = seed >>> 0 || 1; return () => { a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; };

  // gameplay tuning; Config.Suture.Game overrides (sent as data.cfg)
  const DEFAULTS = {
    quality: 'high',
    salineMl: 250, syringeMl: 30, salineFlow: 12, refillTime: 0.75, jetRadius: 4.5, cleanDone: 2,
    lidoSyringe: 5, lidoDose: 0.5, lidoRate: 0.7, lidoMaxPoint: 0.9, lidoSpacing: 14, lidoOffset: 3.5, lidoPick: 4,
    mmPerStitch: 8, minStitches: 3, maxStitches: 12, extraStitches: 3, bite: 4, biteMin: 1.2, biteMax: 9.5, minDrag: 0.3,
    gauzeRadius: 16, gauzeCapacity: 160, gauzeMax: 6,
    flinchPain: 42, flinchChance: 0.55,
    stuckDone: 0.92, coverMin: 0.85,
    weights: { irrigate: 20, anaesthetic: 15, suture: 45, dressing: 20 },
  };
  const TOOLS = [
    { key: '1', id: 'saline', icon: 'drop', label: ['tool_saline', 'Saline syringe'], sub: ['tool_saline_sub', '30 mL · NaCl 0.9%'] },
    { key: '2', id: 'lido', icon: 'syringe', label: ['tool_lido', 'Lidocaine 1%'], sub: ['tool_lido_sub', '5 mL · 25G'] },
    { key: '3', id: 'gauze', icon: 'gauze', label: ['tool_gauze', 'Gauze swab'], sub: ['tool_gauze_sub', '10 × 10 cm'] },
    { key: '4', id: 'driver', icon: 'needle', label: ['tool_driver', 'Needle holder'], sub: ['tool_driver_sub', '4-0 nylon'] },
    { key: '5', id: 'dressing', icon: 'bandage', label: ['tool_dressing', 'Island dressing'], sub: ['tool_dressing_sub', 'Adhesive pad'] },
  ];
  const STEP_TOOL = { 1: 'saline', 2: 'lido', 3: 'driver', 4: 'dressing' };
  const TOOL_STEP = { saline: 1, lido: 2, driver: 3, dressing: 4 };
  const ENGINE_TOOL = { saline: 'irrigator', lido: 'syringe', gauze: 'gauze', driver: 'needleDriver', dressing: null };
  const SAY = [['say_1', 'Ow! Careful!'], ['say_2', 'That stings!'], ['say_3', 'Argh — easy, please!'], ['say_4', 'I can feel that…'], ['say_5', 'Ah! Okay… okay.'], ['say_6', 'Is it nearly done?']];

  const DEMO = {
    patient: { name: 'Michael Garcia', sex: 'm' },
    injury: { id: 'i7', type: 'laceration', region: 'chest', regionLabel: 'Chest', label: 'Deep laceration', severity: 3, length: 56, depth: 8, bleed: 6.1, contamination: 62, pain: 55 },
    tone: 0.3, seed: 4512, items: { lidocaine: 2, gauze: 4 },
  };

  NZA.app('suture', {
    escClose: false, full: true, noscale: true, camInput: false,

    init(el) {
      this.el = el;
      el.innerHTML = `
        <div class="sz-stage"></div>
        <div class="sz-ui">
          <div class="sz-pt nza-hud solid"></div>
          <div class="sz-plan nza-hud solid"></div>
          <div class="sz-result-wrap"></div>
        </div>
        <div class="sz-cur"><svg viewBox="0 0 46 46"><circle class="bg" cx="23" cy="23" r="19"/><circle class="fg" cx="23" cy="23" r="19" stroke-dasharray="0 120"/></svg><span class="tx"></span></div>
        <div class="sz-load"><div class="in"><span class="ring"></span><span class="lt"></span></div></div>`;
      this.stage = el.querySelector('.sz-stage');
      this.ui = el.querySelector('.sz-ui');
      this.ptEl = el.querySelector('.sz-pt');
      this.planEl = el.querySelector('.sz-plan');
      this.resWrap = el.querySelector('.sz-result-wrap');
      this.cur = el.querySelector('.sz-cur');
      this.curFg = el.querySelector('.sz-cur .fg');
      this.curTx = el.querySelector('.sz-cur .tx');
      this.loadEl = el.querySelector('.sz-load');
      this.onMouse = e => { this.mx = e.clientX; this.my = e.clientY; };
      window.addEventListener('mousemove', this.onMouse);
      const heard = e => { if (e.isTrusted) this.heard = true; };
      window.addEventListener('pointerdown', heard, true);
      window.addEventListener('keydown', heard, true);
      this.keys = {};
      ['1', '2', '3', '4', '5'].forEach(k => { this.keys[k] = () => this.pickTool(k); });
      this.keys.Enter = () => { if (this.resultShown && this.canClose) { this.closeNow(); return true; } return false; };
    },

    /* ═════════════ lifecycle ═════════════ */
    open(d) {
      this.teardown();
      LOC = d.locale || {};
      this.d = d;
      this.cfg = Object.assign({}, DEFAULTS, d.cfg || {});
      this.cfg.weights = Object.assign({}, DEFAULTS.weights, (d.cfg && d.cfg.weights) || {});
      this.alive = true;
      this.resultShown = false; this.canClose = false; this.finished = false;
      this.loadEl.classList.remove('out');
      this.loadEl.querySelector('.lt').textContent = T('loading', 'Preparing the field…');
      this.resWrap.innerHTML = '';
      this.ptEl.style.display = ''; this.planEl.style.display = '';
      this.mx = window.innerWidth / 2; this.my = window.innerHeight / 2;
      const token = this.openToken = (this.openToken || 0) + 1;
      // let the loading veil paint before the (heavy) scene build
      requestAnimationFrame(() => requestAnimationFrame(() => { if (this.alive && token === this.openToken) this.boot(); }));
    },
    close() { this.teardown(); },

    teardown() {
      this.alive = false;
      if (this.S) { try { this.S.dispose(); } catch (e) { console.error('[suture] dispose', e); } this.S = null; }
      if (this.pp) { this.pp.destroy(); this.pp = null; }
      if (this.fallbackTimer) { clearInterval(this.fallbackTimer); this.fallbackTimer = null; }
      clearTimeout(this.sayTimer);
      if (this.cur) this.cur.classList.remove('on');
      if (this.stage) { this.stage.innerHTML = ''; this.stage.className = 'sz-stage'; }
      this.g = null;
    },

    msg: {
      result(o) { NZA.apps.suture.showOutcome(o || {}); },
      abort() { NZA.apps.suture.teardown(); NZA.closeLocal('suture'); },
    },

    preview() {
      NZA.mock('suture:finish', r => new Promise(res => setTimeout(() => {
        const s = (r && r.score) || 0;
        res({ ok: true, outcome: { score: s, grade: s >= 90 ? 'S' : s >= 80 ? 'A' : s >= 65 ? 'B' : s >= 50 ? 'C' : s >= 35 ? 'D' : 'F', msg: T('demo_msg', 'Wound closed and dressed.') } });
      }, 700)));
      NZA.mock('suture:abort', { ok: true });
      NZA.mock('suture:flinch', { ok: true });
      NZA.demo('suture', Object.assign({}, DEMO, { locale: {} }));
    },

    /* ═════════════ boot ═════════════ */
    boot() {
      const d = this.d, cfg = this.cfg;
      const inj = Object.assign({}, DEMO.injury, d.injury || {});
      this.inj = inj;
      if (!window.NZA3D || !NZA3D.supported()) return this.fallback();
      const L = clamp(+inj.length || 40, 10, 140);
      const type = inj.type || 'laceration';
      const seed = (+d.seed || hash(`${inj.id}:${(d.patient && d.patient.name) || ''}`)) >>> 0;
      const R = rng(seed);
      const sev = clamp(+inj.severity || 2, 1, 4);
      const limb = /arm|leg/.test(inj.region || '');
      const angle = (R() - 0.5) * (limb ? 0.3 : 0.45);
      let def;
      if (type === 'stab') def = { type: 'stab', length: clamp(L, 12, 48) * MM, gape: clamp(L * 0.1, 2.2, 3.8) * MM, depth: clamp(10 + sev * 2, 10, 18) * MM, jagged: 0.15 };
      else if (type === 'laceration') def = { type: 'laceration', length: L * MM, gape: clamp(L * 0.062, 2.4, 4.8) * MM, depth: clamp(4 + sev * 1.5, 5, 10) * MM, jagged: clamp(0.4 + sev * 0.07, 0.3, 0.75) };
      else def = { type: 'incision', length: clamp(L, 14, 60) * MM, gape: 2.6 * MM, depth: 6 * MM, rim: 0.4, jagged: 0.15 };
      const Lm = def.length;
      this.Lmm = Lm / MM;
      this.depthMm = def.depth / MM;
      def.uv = [0.5, 0.5]; def.angle = angle; def.seed = seed % 100000;
      const viewW = clamp(Lm * 2.05, 0.07, 0.2);
      let S;
      try {
        S = NZA3D.createScene(this.stage, {
          tone: d.tone !== undefined ? +d.tone : 0.3, region: inj.region || 'chest', sex: (d.patient && d.patient.sex) || 'm',
          seed, hair: d.hair !== undefined && d.hair !== null ? +d.hair : null, quality: cfg.quality,
          focus: { uv: [0.5, 0.5], size: [Lm + 0.024, 0.03], view: viewW },
        });
      } catch (e) {
        console.error('[suture] 3D scene', e);
        return this.fallback();
      }
      this.S = S;
      const w = S.wounds.add(def);
      this.w = w;
      this.viewW = viewW;
      // the near edge = the side that projects lower on screen (toward the medic)
      const pa = S.project(w.edge(0.5, 1, 0.004)), pb = S.project(w.edge(0.5, -1, 0.004));
      this.near = pa.y > pb.y ? 1 : -1;
      this.pts = w.points();

      const g = this.g = {
        t: 0, step: 1, tool: null, lmb: false, skipped: {}, done: {}, events: 0, flinches: 0, lastSay: -9,
        stepT: { 1: 0 }, uiT: 0,
        cont0: clamp((+inj.contamination || 0) / 100, 0, 1),
        bleed0: Math.max(0, +inj.bleed || 0),
        pain0: clamp(+inj.pain || 40, 5, 100), painSpike: 0, pain: 0,
        irr: { ml: Math.max(0, cfg.salineMl - cfg.syringeMl), syr: Math.min(cfg.syringeMl, cfg.salineMl), refill: 0, used: 0, cont: 0, sum0: 1, mask: null, done: false, onWound: 0 },
        lido: { have: (d.items && +d.items.lidocaine) || 0, ml: 0, points: [], inj: null, done: false, said: false },
        gz: { have: Math.min((d.items && +d.items.gauze) || 0, cfg.gauzeMax), used: 0, swab: null, stainT: 0, absorbed: 0 },
        sut: { N: 0, list: [], misses: 0, drag: null, done: false, last: null },
        dr: { D: null, rub: false, done: false, cover: 0, settledT: 0, warnT: 0 },
      };
      g.pain = g.pain0;

      this.paintInitial(R, sev);
      // contamination mask over the cut (grime + clot that the jet has to rinse out)
      g.irr.mask = S.layers.mask(this.pts, def.gape * 0.5 + 0.0035);
      g.irr.sum0 = Math.max(1e-6, g.irr.mask.sum('grime') + 0.5 * g.irr.mask.sum('clot'));
      g.irr.cont = g.cont0;
      if (g.cont0 < 0.02) { g.irr.done = true; }
      S.layers.decay('wet', 0.06);
      this.setBleed();

      // stitches: one per ~8 mm
      g.sut.N = +d.sections > 0 ? clamp(Math.round(+d.sections), 2, 20) : clamp(Math.round(this.Lmm / cfg.mmPerStitch), cfg.minStitches, cfg.maxStitches);
      // lidocaine points along both edges
      const nPer = clamp(Math.round(this.Lmm / cfg.lidoSpacing), 2, 6);
      for (const side of [this.near, -this.near]) {
        for (let k = 0; k < nPer; k++) {
          const tN = (k + 0.5) / nPer;
          g.lido.points.push({ id: `L${side > 0 ? 'a' : 'b'}${k}`, tN, side, uv: w.edge(tN, side, cfg.lidoOffset * MM), ml: 0, done: false, bump: null, err: 0 });
        }
      }

      // compile the tool and dressing shaders now, behind the loading veil
      S.prewarm(['irrigator', 'syringe', 'gauze', 'needleDriver'], true);
      S.on('frame', dt => this.frame(dt));
      S.on('down', (e, f) => this.down(e, f));
      S.on('up', (e, f) => this.up(e, f));
      S.start();

      this.buildHud();
      this.buildPanel();
      g.step = g.irr.done ? 2 : 1;
      if (g.irr.done) g.done[1] = true;
      this.enterStep(g.step, true);
      setTimeout(() => this.loadEl.classList.add('out'), 120);
    },

    // grime in and around the cut, clots, pooled blood, a bruise, dried trickles and flecks
    paintInitial(R, sev) {
      const S = this.S, w = this.w, c = this.g.cont0, pts = this.pts;
      const jit = (uv, mm) => [uv[0] + (R() - 0.5) * mm * MM / S.patch.W, uv[1] + (R() - 0.5) * mm * MM / S.patch.H];
      const side = () => (R() < 0.5 ? 1 : -1);
      if (c > 0.02) {
        // dirt packed into the cut: this is what the jet has to rinse out
        for (let i = 0; i < pts.length; i += 2) S.layers.splat('grime', jit(pts[i], 1.2), (1.1 + R() * 1.1) * MM, clamp(0.35 + c * 0.6, 0, 1), { seed: 11 + i, count: 5 });
        // road dirt smeared over the edges: soft granular smudges dragged along the injury
        const n = Math.round(5 + c * 12);
        for (let k = 0; k < n; k++) {
          const tN = 0.04 + R() * 0.92, sd = side(), at = w.at(tN);
          const a = w.edge(tN, sd, (0.8 + R() * R() * 6.5) * MM);
          const ang = Math.atan2(at.dir[1], at.dir[0]) + (R() - 0.5) * 0.7;
          S.layers.paint('grime', a, [(1.4 + R() * 3.4) * MM, (0.4 + R() * 0.8) * MM], (0.16 + R() * 0.2) * (0.4 + c),
            { hardness: 0.05, grain: 0.75, grainScale: 1100 + R() * 900, angle: ang });
        }
        // grit: fine specks within a few millimetres of the edges
        const nd = Math.round(18 + c * 46);
        for (let k = 0; k < nd; k++) {
          S.layers.paint('grime', w.edge(R(), side(), (0.2 + R() * R() * 5.5) * MM), (0.12 + R() * 0.3) * MM, 0.55 + R() * 0.45, { hardness: 0.55 });
        }
      }
      // clots in the groove
      for (let k = 0; k < 2 + sev; k++) S.layers.splat('clot', w.at(0.12 + R() * 0.76).uv, (1.2 + R() * 1.2) * MM, 0.45 + R() * 0.25, { seed: 140 + k, count: 5 });
      // pooled blood along the whole cut
      for (let i = 0; i < pts.length; i++) {
        const tN = i / Math.max(1, pts.length - 1), r = w.halfGape(tN) + 0.0004;
        S.layers.paint('blood', pts[i], [r, r], 0.16 + R() * 0.14, { hardness: 0.3 });
      }
      // dried blood flecks around the cut (red-brown spatter)
      const nf = 26 + sev * 10;
      for (let k = 0; k < nf; k++) {
        const r = (0.1 + R() * R() * 0.45) * MM;
        S.layers.paint('clot', w.edge(R(), side(), (0.4 + R() * R() * 9) * MM), [r * (0.8 + R() * 0.6), r], 0.16 + R() * 0.3, { hardness: 0.45, angle: R() * Math.PI });
      }
      // old dried trickles below the near edge
      for (let k = 0; k < 2; k++) {
        const tN = 0.25 + R() * 0.5, a = w.edge(tN, this.near, 0.0008), r = w.at(tN);
        const len = (5 + R() * 8) * MM, dx = r.nrm[0] * this.near * len, dy = r.nrm[1] * this.near * len;
        const b = [a[0] + dx / S.patch.W, a[1] - dy / S.patch.H];
        S.layers.stroke('clot', a, b, 0.0006, 0.035, { hardness: 0.45, grain: 0.4, grainScale: 120 });
      }
      S.layers.splat('bruise', w.at(0.5).uv, (10 + this.Lmm * 0.12) * MM, 0.09 + sev * 0.025, { seed: 3, count: 7 });
    },

    /* ═════════════ HUD (cards) ═════════════ */
    buildHud() {
      const d = this.d, inj = this.inj;
      const name = (d.patient && d.patient.name) || T('patient', 'Patient');
      const injLabel = inj.label || T(`type_${inj.type}`, inj.type);
      this.ptEl.innerHTML = `
        <div class="hd"><span class="av">${icon('user')}</span><div style="min-width:0"><div class="nm">${esc(name)}</div><div class="inj">${esc(injLabel)} · ${esc(inj.regionLabel || inj.region || '')}</div></div></div>
        <div class="row"><span class="nza-label">${esc(T('pain', 'Pain'))}</span><span class="v pv"></span></div>
        <div class="pm"></div>
        <div class="chips"></div>`;
      this.planEl.innerHTML = `
        <div class="hd"><span class="nza-label">${esc(T('plan', 'Closure plan'))}</span><span class="tm">00:00</span></div>
        <ol></ol>
        <div class="ft"></div>`;
      this.renderHud(true);
    },
    renderHud(full) {
      const g = this.g;
      if (!g) return;
      const p = Math.round(g.pain);
      const pv = this.ptEl.querySelector('.pv');
      pv.textContent = `${p}%`;
      pv.className = `v pv ${p >= 60 ? 'red' : p >= 30 ? 'amber' : 'teal'}`;
      this.ptEl.querySelector('.pm').innerHTML = NZA.ui.meterHTML({ value: p / 100, tone: p >= 60 ? 'red' : p >= 30 ? 'amber' : '' });
      const numb = this.numbFrac();
      const chips = [];
      if (g.done[2]) chips.push(`<span class="sz-chip teal">${icon('check')}${esc(T('chip_numb', 'Anaesthetised'))}</span>`);
      else if (g.skipped[2]) chips.push(`<span class="sz-chip amber">${icon('alert')}${esc(T('chip_no_lido', 'No anaesthetic'))}</span>`);
      else if (numb > 0) chips.push(`<span class="sz-chip">${esc(T('chip_numbing', 'Numbing %s%', pct(numb)))}</span>`);
      if (g.flinches) chips.push(`<span class="sz-chip red">${esc(T('chip_flinch', 'Flinched ×%s', g.flinches))}</span>`);
      const ch = this.ptEl.querySelector('.chips');
      const html = chips.join('');
      if (ch.innerHTML !== html) ch.innerHTML = html;
      // plan
      const steps = [
        [1, T('plan_1', 'Rinse'), g.done[1] ? '0%' : g.skipped[1] ? T('skipped', 'Skipped') : `${pct(g.irr.cont)}%`],
        [2, T('plan_2', 'Numb'), g.skipped[2] ? T('skipped', 'Skipped') : `${g.lido.points.filter(x => x.done).length}/${g.lido.points.length}`],
        [3, T('plan_3', 'Stitch'), `${this.stitchCount()}/${g.sut.N}`],
        [4, T('plan_4', 'Seal'), g.dr.D ? `${pct(g.dr.D.stuck)}%` : ''],
      ];
      const ol = steps.map(([n, label, x]) => {
        const cls = g.done[n] ? 'done' : g.skipped[n] ? 'skip' : g.step === n ? 'cur' : '';
        const b = g.done[n] ? icon('check') : g.skipped[n] ? icon('minus') : n;
        return `<li class="${cls}"><span class="b">${b}</span>${esc(label)}<span class="x">${esc(x)}</span></li>`;
      }).join('');
      const olEl = this.planEl.querySelector('ol');
      if (full || olEl.innerHTML !== ol) olEl.innerHTML = ol;
      this.planEl.querySelector('.tm').textContent = NZA.fmt.time(g.t);
      const ft = [];
      ft.push(`<span class="sz-chip">${icon('gauze')}${esc(T('chip_swabs', 'Swabs %s/%s', g.gz.used, g.gz.have))}</span>`);
      ft.push(`<span class="sz-chip">${icon('bottle')}${esc(T('chip_saline', '%s mL', Math.round(g.irr.ml + g.irr.syr)))}</span>`);
      if (g.sut.misses) ft.push(`<span class="sz-chip amber">${esc(T('chip_misses', 'Missed ×%s', g.sut.misses))}</span>`);
      const fh = ft.join('');
      const ftEl = this.planEl.querySelector('.ft');
      if (ftEl.innerHTML !== fh) ftEl.innerHTML = fh;
    },

    /* ═════════════ panel ═════════════ */
    buildPanel() {
      this.pp = NZA.ui.ProcPanel(this.ui, {
        step: 1, total: 4, tag: T('tag', 'Suture'),
        title: '', text: '', stats: this.stats(), tools: this.toolList(), steps: this.stepNames(),
        hints: [
          { keys: [T('key_rmb', 'RMB')], label: T('cam_look', 'Look around') },
          { keys: [T('key_wheel', 'Wheel')], label: T('cam_zoom', 'Zoom') },
          { keys: ['R'], label: T('cam_recenter', 'Recentre') },
        ],
        abort: { label: T('hold_stop', 'Hold to stop'), key: 'ESC', seconds: 1.2 },
        onAbort: () => this.abort(),
        onTool: key => this.pickTool(key),
      });
      // section dots + contextual tip live in the instruction card, under the step text
      const body = this.pp.el.querySelector('.pp-body') || this.pp.el;
      const after = body.querySelector('.pp-text');
      this.dots = document.createElement('div'); this.dots.className = 'sz-dots';
      this.tip = document.createElement('div'); this.tip.className = 'sz-tip';
      if (after && after.nextSibling) { body.insertBefore(this.tip, after.nextSibling); body.insertBefore(this.dots, this.tip); }
      else { body.appendChild(this.dots); body.appendChild(this.tip); }
    },
    stepNames() {
      // zero-based: the panel shows steps[current] as "Next"
      return [T('plan_1', 'Rinse'), T('plan_2', 'Numb'), T('plan_3', 'Stitch'), T('plan_4', 'Seal')];
    },
    stats() {
      const inj = this.inj;
      const b = this.bleedNow();
      return [
        { id: 'site', label: T('st_site', 'Region'), value: inj.regionLabel || inj.region || '', small: true },
        { id: 'len', label: T('st_length', 'Cut length'), value: String(Math.round(this.Lmm || inj.length || 0)), unit: 'mm' },
        { id: 'depth', label: T('st_depth', 'Depth'), value: String(Math.round(this.depthMm || 0)), unit: 'mm' },
        { id: 'bleed', label: T('st_bleed', 'Bleeding'), value: b.toFixed(1), unit: T('u_mlmin', 'mL/min'), tone: b >= 10 ? 'red' : b >= 3 ? 'amber' : '' },
      ];
    },
    toolList() {
      const g = this.g;
      return TOOLS.map(t => {
        const o = { key: t.key, label: T(t.label[0], t.label[1]), sub: T(t.sub[0], t.sub[1]), icon: t.icon };
        let state = '';
        if (g) {
          const st = TOOL_STEP[t.id];
          if (st && (g.done[st] || g.skipped[st]) && st < g.step) state = 'done';
          if (t.id === 'lido') { o.count = String(g.lido.have); if (!g.lido.have && !g.done[2]) state = 'locked'; }
          if (t.id === 'gauze') { o.count = String(Math.max(0, g.gz.have - g.gz.used + (g.gz.swab ? 1 : 0))); if (!g.gz.have || g.step === 4) state = 'locked'; }
          if (t.id === 'dressing' && g.step < 4) state = state || '';
          if (g.tool === t.id) state = 'active';
        }
        o.state = state;
        return o;
      });
    },
    refreshTools() { if (this.pp) this.pp.set({ tools: this.toolList() }); },
    setTip(text, tone = '') {
      if (!this.tip) return;
      this.tip.className = `sz-tip ${tone}`;
      this.tip.innerHTML = text ? `<span>${NZA.rich(text)}</span>` : '';
    },
    flash(type, text, ms) { if (this.pp) this.pp.flash(type, text, ms); },

    /* ═════════════ steps ═════════════ */
    enterStep(n, first) {
      const g = this.g, S = this.S, cfg = this.cfg;
      g.step = n;
      g.stepT[n] = g.t;
      const texts = {
        1: [T('s1_title', 'Rinse out the cut'), T('s1_text', 'Hold {LMB} to squeeze the syringe. Keep the stream down inside the cut and walk it slowly from one end to the other until no dirt or clot is left.')],
        2: [T('s2_title', 'Numb the edges'), g.lido.have ? T('s2_text', 'Hold {LMB} on each ring beside the cut until the skin puffs up. Both sides need a dose.') : T('s2_text_none', 'You carry no lidocaine. Press {4} to stitch without it — the patient will feel every pass.')],
        3: [T('s3_title', 'Close with stitches'), T('s3_text', 'Press {LMB} at the ring on your side, drag the needle straight through to the dashed ring opposite and let go — the knot ties itself.')],
        4: [T('s4_title', 'Seal the wound'), T('s4_text', 'Lift the dressing by its border, lay the pad over the stitch line and let go. Then hold {LMB} and smooth it flat from the middle out.')],
      };
      this.pp.set({ step: n, title: texts[n][0], titleTone: '', text: texts[n][1] });
      this.useTool(STEP_TOOL[n]);
      this.clearMarkers();
      if (n === 2) this.lidoMarkers();
      if (n === 3) { this.sutureMarkers(); this.renderDots(); }
      if (n === 4) this.startDressing();
      this.dots.style.display = n === 3 ? '' : 'none';
      this.stepTip();
      this.updatePanel(true);
      this.renderHud(true);
      if (!first) this.snd('success');
    },
    completeStep(n, msg) {
      const g = this.g;
      if (g.done[n]) return;
      g.done[n] = true;
      this.flash('ok', msg, 2400);
      if (n === 4) { this.finish(); return; }
      const next = n + 1;
      clearTimeout(this.stepTimer);
      this.stepTimer = setTimeout(() => { if (this.g === g && this.alive && g.step === n) this.enterStep(next); }, 700);
    },
    skipTo(n) {
      const g = this.g;
      for (let k = g.step; k < n; k++) if (!g.done[k]) g.skipped[k] = true;
      if (g.lido.inj) this.stopInject();
      this.enterStep(n);
    },
    // number keys: pick a tool. Picking a later step's tool skips the current one (press twice).
    pickTool(key) {
      const g = this.g;
      if (!g || this.finished) return;
      const t = TOOLS.find(x => x.key === key);
      if (!t) return;
      if (t.id === 'gauze') {
        if (g.step === 4) return this.flash('warn', T('gauze_late', 'The cut is closed — no more blotting.'));
        if (!g.gz.have) return this.flash('bad', T('gauze_none', 'You carry no gauze.'));
        this.useTool(g.tool === 'gauze' ? STEP_TOOL[g.step] : 'gauze');
        return;
      }
      const st = TOOL_STEP[t.id];
      if (st === g.step) { this.useTool(t.id); return; }
      if (st < g.step) return this.flash('warn', T('tool_past', 'That step is behind you.'));
      // a later step
      if (st === 4 && !g.done[3]) return this.flash('bad', T('need_suture', 'Close the cut before you dress it.'));
      if (st === 2 && g.step === 1 && !g.done[1] || st === 3) {
        const now = performance.now();
        if (this.skipArm && this.skipArm.key === key && now - this.skipArm.t < 2600) { this.skipArm = null; this.skipTo(st); return; }
        this.skipArm = { key, t: now };
        const what = g.step === 1 ? T('skip_irrigate', 'the wound is not clean yet') : T('skip_lido', 'the edges are not numb');
        return this.flash('warn', T('skip_confirm', 'Skip ahead? %s — press {%s} again.', what, key), 2600);
      }
      this.skipTo(st);
    },
    useTool(id) {
      const g = this.g, S = this.S;
      if (!g || !S) return;
      if (g.lido.inj) this.stopInject();
      if (g.sut.drag) this.cancelDrag();
      S.fluids.jet(false);
      S.tools.press(false);
      g.tool = id;
      const et = ENGINE_TOOL[id];
      const tool = S.tools.use(et || null);
      if (tool && id === 'lido') tool.set({ plunger: clamp(g.lido.ml / this.cfg.lidoSyringe, 0, 1) });
      if (tool && id === 'saline') tool.set({ plunger: clamp(1 - g.irr.syr / this.cfg.syringeMl, 0, 1) });
      this.stage.classList.toggle('busy', false);
      this.refreshTools();
      this.stepTip();
    },
    stepTip() {
      const g = this.g;
      if (!g) return;
      if (g.tool === 'gauze') return this.setTip(T('tip_gauze', 'Hold {LMB} to press the gauze on the field and soak up the blood. Press {3} again to put it down.'));
      switch (g.step) {
        case 1: return this.setTip(g.lido.have ? T('tip_1', 'Point the stream **into** the cut, not just around it. Blood keeps oozing back — that is fine, the grime is what counts.') : T('tip_1b', 'Point the stream **into** the cut. You have no lidocaine — this will sting.'), '');
        case 2: return this.setTip(g.lido.have ? T('tip_2', 'Each point takes about half a millilitre. Skip with {4} if you must — expect the patient to flinch.') : '', 'amber');
        case 3: return this.setTip(this.anaesthetised() ? T('tip_3', 'Bite about **%s mm** from the edge on both sides and pull straight across the cut. Keep the stitches evenly spaced.', this.cfg.bite) : T('tip_3b', 'No anaesthetic — the patient may flinch while the needle is in. Steady pulls, straight across.', this.cfg.bite), this.anaesthetised() ? '' : 'amber');
        case 4: return this.setTip(T('tip_4', 'Grab the dressing by an **edge** (the cursor changes), lay the pad over the whole cut, then rub from the centre out.'));
      }
      return this.setTip('');
    },

    /* ═════════════ input ═════════════ */
    down(e) {
      const g = this.g;
      if (!g || this.finished) return;
      if (e.button !== 0) return;
      g.lmb = true;
      const S = this.S;
      switch (g.tool) {
        case 'saline': break;
        case 'lido': this.startInject(); break;
        case 'gauze': break;
        case 'driver': this.startStitch(); break;
        case 'dressing': this.dressDown(); break;
      }
      if (g.tool === 'saline' || g.tool === 'gauze') S.tools.press(true);
    },
    up(e) {
      const g = this.g;
      if (!g) return;
      if (e.button !== 0) return;
      g.lmb = false;
      const S = this.S;
      if (g.tool === 'lido') this.stopInject();
      if (g.tool === 'driver' && g.sut.drag) this.endStitch();
      if (g.tool === 'dressing') this.dressUp();
      if (S) { S.tools.press(false); S.fluids.jet(false); }
    },

    /* ═════════════ frame ═════════════ */
    frame(dt) {
      const g = this.g;
      if (!g || !this.alive) return;
      g.t += dt;
      const S = this.S;
      this.updatePain(dt);
      switch (g.tool) {
        case 'saline': this.tickSaline(dt); break;
        case 'lido': this.tickInject(dt); break;
        case 'gauze': this.tickGauze(dt); break;
        case 'driver': this.tickStitch(dt); break;
        case 'dressing': this.tickDressing(dt); break;
      }
      if (g.step === 1 && !g.done[1]) this.measureIrrigation();
      if (g.step === 3 && !g.done[3]) this.hiddenField();
      this.updateCursor();
      g.uiT -= dt;
      if (g.uiT <= 0) { g.uiT = 0.12; this.updatePanel(); this.renderHud(); }
      void S;
    },

    /* ── pain & flinches ── */
    numbFrac() {
      const g = this.g;
      if (!g || !g.lido.points.length) return 0;
      let s = 0;
      for (const p of g.lido.points) s += clamp(p.ml / this.cfg.lidoDose, 0, 1);
      return s / g.lido.points.length;
    },
    anaesthetised() { return this.numbFrac() >= 0.75; },
    updatePain(dt) {
      const g = this.g;
      g.painSpike *= Math.exp(-dt * 1.1);
      const target = g.pain0 * (1 - 0.85 * this.numbFrac());
      g.pain = clamp(target + g.painSpike, 0, 100);
    },
    hurt(amount, flinchChance) {
      const g = this.g;
      const numb = this.numbFrac();
      g.painSpike = Math.min(60, g.painSpike + amount * (1 - 0.88 * numb));
      g.pain = clamp(g.pain0 * (1 - 0.85 * numb) + g.painSpike, 0, 100);
      if (flinchChance && g.pain >= this.cfg.flinchPain && Math.random() < flinchChance * (1 - numb)) { this.flinch(); return true; }
      return false;
    },
    flinch() {
      const g = this.g;
      g.flinches++;
      this.S.controls.shake(0.75, 460);
      this.ptEl.classList.remove('flinch'); void this.ptEl.offsetWidth; this.ptEl.classList.add('flinch');
      if (g.t - g.lastSay > 3.2) {
        g.lastSay = g.t;
        const line = SAY[Math.floor(Math.random() * SAY.length)];
        NZA.speech({ name: (this.d.patient && this.d.patient.name) || T('patient', 'Patient'), text: T(line[0], line[1]), ms: 2400 });
      }
      NZA.post('suture:flinch', { pain: Math.round(g.pain) });
      this.snd('tone', 180, 120, { vol: 0.05, type: 'triangle' });
    },

    /* ── bleeding ── */
    stitchCount() { return this.g ? this.g.sut.list.length : 0; },
    closedFrac() {
      const g = this.g;
      if (!g || !g.sut.N) return 0;
      return this.coveredSlots().filter(Boolean).length / g.sut.N;
    },
    bleedNow() {
      const g = this.g;
      if (!g) return +(this.inj && this.inj.bleed) || 0;
      return g.bleed0 * (1 - 0.95 * this.closedFrac());
    },
    setBleed() {
      const b = this.bleedNow();
      this.S.fluids.bleed(this.w, b > 0.05 ? clamp(b * 0.55, 0.6, 9) : 0);
    },

    /* ═════════════ 1 · IRRIGATE ═════════════ */
    tickSaline(dt) {
      const g = this.g, S = this.S, cfg = this.cfg, tool = S.tools.active, irr = g.irr;
      // the 30 mL syringe empties, then refills from the bottle (a short pause in the stream)
      if (irr.refill > 0) {
        irr.refill -= dt;
        S.fluids.jet(false);
        if (tool) tool.set({ plunger: clamp(irr.refill / cfg.refillTime, 0, 1) });
        this.cursorProgress(1 - clamp(irr.refill / cfg.refillTime, 0, 1), T('cur_refill', 'Refilling…'));
        if (irr.refill <= 0) { const n = Math.min(cfg.syringeMl, irr.ml); irr.ml -= n; irr.syr = n; }
        return;
      }
      const firing = g.lmb && irr.syr > 0 && S.tools.hit && tool && tool.group.visible;
      if (!firing) {
        S.fluids.jet(false);
        if (g.lmb && irr.syr + irr.ml <= 0) this.cursorHint(T('saline_empty', 'Saline used up'), 'red');
        return;
      }
      const hit = S.tools.hit;
      S.fluids.jet({ on: true, from: tool.tipWorld(), to: hit, wash: { grime: 1.7, blood: 1.3, clot: 0.55 }, wet: 1, rate: 1, radius: cfg.jetRadius * MM });
      const use = Math.min(cfg.salineFlow * dt, irr.syr);
      irr.syr -= use; irr.used += use;
      tool.set({ plunger: clamp(1 - irr.syr / cfg.syringeMl, 0, 1) });
      // the jet on a raw, un-numbed wound stings
      const loc = this.w.locate(hit.uv);
      if (loc.d < 0.006) { irr.onWound += dt; this.hurt(9 * dt, 0); if (g.pain > 70 && Math.random() < dt * 0.25) this.flinch(); }
      if (irr.syr <= 0.001) {
        S.fluids.jet(false);
        if (irr.ml > 0) { irr.refill = cfg.refillTime; return; }
        if (!g.done[1]) {
          this.flash('warn', T('saline_out', 'Out of saline — %s% of the contamination is left.', pct(irr.cont)), 3200);
          g.done[1] = true; irr.partial = true;
          clearTimeout(this.stepTimer);
          this.stepTimer = setTimeout(() => { if (this.alive && g.step === 1) this.enterStep(2); }, 1100);
        }
      }
    },
    measureIrrigation() {
      const g = this.g;
      const left = (g.irr.mask.sum('grime') + 0.5 * g.irr.mask.sum('clot')) / g.irr.sum0;
      g.irr.cont = g.cont0 * clamp(left, 0, 1);
      if (g.irr.cont * 100 <= this.cfg.cleanDone) {
        g.irr.cont = 0;
        this.S.fluids.jet(false);
        this.completeStep(1, T('s1_done', 'Clean — the cut is rinsed out.'));
      }
    },

    /* ═════════════ 2 · ANAESTHETISE ═════════════ */
    lidoMarkers() {
      const g = this.g;
      for (const p of g.lido.points) this.S.markers.set(p.id, { uv: p.uv, kind: p.done ? 'check' : 'ring', size: p.done ? 0.0036 : 0.0032, color: 0x0fd4c4, pulse: !p.done, opacity: p.done ? 0.85 : 1 });
    },
    startInject() {
      const g = this.g, S = this.S, cfg = this.cfg;
      if (g.step !== 2) return this.flash('warn', T('lido_wrong_step', 'Not now — finish the current step first.'));
      if (!g.lido.have) return this.flash('bad', T('lido_none', 'You carry no lidocaine.'));
      if (g.lido.ml >= cfg.lidoSyringe - 0.01) return this.flash('bad', T('lido_empty', 'The syringe is empty.'));
      const hit = S.tools.hit;
      if (!hit) return;
      let best = null, bd = Infinity;
      for (const p of g.lido.points) {
        const dd = S.distanceUv(hit.uv, p.uv) / MM;
        if (dd < bd) { bd = dd; best = p; }
      }
      if (!best || bd > cfg.lidoPick) return this.flash('warn', T('lido_off', 'Inject at the marked points along the edges.'));
      if (best.ml >= cfg.lidoMaxPoint) return this.flash('warn', T('lido_enough', 'Enough here — move to the next point.'));
      best.err = Math.max(best.err, bd);
      g.lido.inj = { p: best, t: 0 };
      S.tools.press(true);
      this.hurt(14, 0.35);
    },
    stopInject() {
      const g = this.g;
      if (!g.lido.inj) return;
      g.lido.inj = null;
      this.S.tools.press(false);
    },
    tickInject(dt) {
      const g = this.g, S = this.S, cfg = this.cfg, inj = g.lido.inj;
      const tool = S.tools.active;
      if (!inj) {
        // hover hint over a point
        return;
      }
      const hit = S.tools.hit;
      if (!hit || S.distanceUv(hit.uv, inj.p.uv) / MM > cfg.lidoPick + 1.5) { this.stopInject(); return this.flash('warn', T('lido_slipped', 'The needle slipped out — hold still while you inject.')); }
      inj.t += dt;
      if (inj.t < 0.18) return;   // needle going in
      const p = inj.p;
      const add = Math.min(cfg.lidoRate * dt, cfg.lidoSyringe - g.lido.ml, cfg.lidoMaxPoint - p.ml);
      if (add <= 0) {
        this.stopInject();
        return this.flash('warn', g.lido.ml >= cfg.lidoSyringe - 0.01 ? T('lido_empty', 'The syringe is empty.') : T('lido_enough', 'Enough here — move to the next point.'));
      }
      p.ml += add; g.lido.ml += add;
      if (tool) tool.set({ plunger: clamp(g.lido.ml / cfg.lidoSyringe, 0, 1) });
      const f = clamp(p.ml / cfg.lidoDose, 0, 1.6);
      if (!p.bump) p.bump = S.bumps.add({ uv: p.uv, radius: 0.0012, height: 0.0001 });
      p.bump.set({ radius: (1.2 + 1.9 * Math.min(f, 1.3)) * MM, height: (0.12 + 0.42 * Math.min(f, 1.3)) * MM });
      this.cursorProgress(Math.min(1, p.ml / cfg.lidoDose), '');
      if (!p.done && p.ml >= cfg.lidoDose * 0.75) {
        p.done = true;
        this.snd('click', 900);
        S.markers.set(p.id, { uv: p.uv, kind: 'check', size: 0.0036, pulse: false, opacity: 0.85 });
        const n = g.lido.points.filter(x => x.done).length;
        if (!g.lido.said && n >= g.lido.points.length / 2) {
          g.lido.said = true;
          NZA.speech({ name: (this.d.patient && this.d.patient.name) || T('patient', 'Patient'), text: T('say_numb', 'It is going numb…'), ms: 2200 });
        }
        if (n >= g.lido.points.length) { this.stopInject(); this.completeStep(2, T('s2_done', 'Both edges are numb.')); }
      }
    },

    /* ═════════════ GAUZE (any time before the dressing) ═════════════ */
    tickGauze(dt) {
      const g = this.g, S = this.S, cfg = this.cfg, gz = g.gz;
      const tool = S.tools.active;
      if (!g.lmb || !S.tools.hit) { if (tool) tool.set({ squash: 0 }); return; }
      if (!gz.swab) {
        if (gz.used >= gz.have) { this.cursorHint(T('gauze_out', 'No gauze left'), 'red'); return; }
        gz.used++;
        gz.swab = { load: 0, stains: 0 };
        if (tool) tool.set({ fresh: true });
        this.refreshTools();
      }
      if (tool) tool.set({ squash: 1 });
      const uv = S.tools.hit.uv, r = cfg.gauzeRadius * MM;
      const before = S.layers.total('blood', uv, r) + 0.6 * S.layers.total('clot', uv, r);
      S.layers.erase('blood', uv, r, 3.2 * dt, { hardness: 0.25 });
      S.layers.erase('clot', uv, r * 0.9, 0.45 * dt, { hardness: 0.25 });
      S.layers.erase('wet', uv, r, 1.5 * dt, { hardness: 0.2 });
      const after = S.layers.total('blood', uv, r) + 0.6 * S.layers.total('clot', uv, r);
      const got = Math.max(0, before - after);
      gz.swab.load += got; gz.absorbed += got;
      gz.stainT -= dt;
      if (got > 0.2 && gz.stainT <= 0 && gz.swab.stains < 14 && tool) {
        gz.stainT = 0.22; gz.swab.stains++;
        const k = clamp(gz.swab.load / cfg.gauzeCapacity, 0, 1);
        tool.set({ stain: { x: 0.5 + (Math.random() - 0.5) * (0.25 + k * 0.4), y: 0.5 + (Math.random() - 0.5) * (0.25 + k * 0.4), r: 0.08 + k * 0.22, a: 0.55 + k * 0.4 } });
      }
      this.cursorProgress(clamp(gz.swab.load / cfg.gauzeCapacity, 0, 1), '', true);
      if (gz.swab.load >= cfg.gauzeCapacity) {
        gz.swab = null;
        this.flash('warn', gz.used < gz.have ? T('gauze_soaked', 'That swab is soaked — the next press opens a fresh one.') : T('gauze_last', 'That was your last swab.'));
        this.refreshTools();
      }
    },
    // blood pooled over the cut hides the edges (suturing step)
    hiddenField() {
      const g = this.g;
      const cov = g.irr.mask.coverage('blood', 0.45);
      g.hidden = cov;
      if (cov > 0.6 && g.tool !== 'gauze' && !g.sut.drag) {
        g.warnBlood = (g.warnBlood || 0) - 0.016;
        if (g.warnBlood <= 0) { g.warnBlood = 6; this.flash('warn', g.gz.have - g.gz.used + (g.gz.swab ? 1 : 0) > 0 ? T('blood_hides', 'Blood is hiding the edges — blot it with gauze {3}.') : T('blood_hides_none', 'Blood is hiding the edges — work carefully.'), 3000); }
      }
      // markers fade under pooled blood
      const op = cov > 0.55 ? 0.35 : 1;
      if (this.mkOpacity !== op) { this.mkOpacity = op; this.sutureMarkers(); }
    },

    /* ═════════════ 3 · SUTURE ═════════════ */
    // which ideal slots ((i + .5) / N) already have a stitch nearby
    coveredSlots() {
      const g = this.g, N = g.sut.N;
      const out = new Array(N).fill(false);
      for (const s of g.sut.list) {
        const i = clamp(Math.floor(s.tN * N), 0, N - 1);
        if (Math.abs(s.tN - (i + 0.5) / N) * this.Lmm <= (this.Lmm / N) * 0.62) out[i] = true;
      }
      return out;
    },
    nextSlot() {
      const cov = this.coveredSlots();
      const i = cov.indexOf(false);
      return i;
    },
    sutureMarkers() {
      const g = this.g, S = this.S, cfg = this.cfg;
      if (!S || g.step !== 3) return;
      const i = this.nextSlot();
      if (i < 0) { S.markers.remove('in'); S.markers.remove('inR'); S.markers.remove('out'); return; }
      const tN = (i + 0.5) / g.sut.N;
      const op = this.mkOpacity !== undefined ? this.mkOpacity : 1;
      const a = this.w.edge(tN, this.near, cfg.bite * MM), b = this.w.edge(tN, -this.near, cfg.bite * MM);
      S.markers.set('inR', { uv: a, kind: 'ring', size: 0.0034, color: 0x0fd4c4, pulse: true, opacity: op });
      S.markers.set('in', { uv: a, kind: 'pin', size: 0.0052, color: 0x0fd4c4, lift: 0.008, opacity: op });
      S.markers.set('out', { uv: b, kind: 'dashed', size: 0.0036, color: 0xffffff, pulse: false, opacity: 0.7 * op });
      g.sut.slot = i;
    },
    edgeDist(uv) {
      const w = this.w, loc = w.locate(uv);
      return { loc, mm: (loc.d - w.halfGape(loc.tN)) / MM };
    },
    startStitch() {
      const g = this.g, S = this.S, cfg = this.cfg;
      if (g.step !== 3) return this.flash('warn', T('sut_wrong_step', 'Not yet — finish the current step first.'));
      const hit = S.tools.hit;
      if (!hit) return;
      const { loc, mm } = this.edgeDist(hit.uv);
      if (loc.tN < 0.03 || loc.tN > 0.97) return this.flash('bad', T('sut_ends', 'Stay along the cut, not past its ends.'));
      if (loc.side !== this.near) return this.flash('bad', T('sut_near', 'Start on the **near** edge — the side closest to you.'));
      if (mm < cfg.biteMin) return this.flash('bad', T('sut_close', 'Too close to the edge — that bite would tear out.'));
      if (mm > cfg.biteMax) return this.flash('bad', T('sut_far', 'Too far from the cut — start at the marker.'));
      for (const s of g.sut.list) if (Math.abs(s.tN - loc.tN) * this.Lmm < 2.6) return this.flash('warn', T('sut_taken', 'There is already a stitch here.'));
      if (g.sut.list.length >= g.sut.N + cfg.extraStitches) return this.flash('warn', T('sut_max', 'That is enough thread for this cut.'));
      g.sut.drag = { a: hit.uv.slice(), aTN: loc.tN, aMm: mm, t0: g.t, jit: [0, 0], flinch: false };
      S.tools.press(true);
      const tool = S.tools.active; if (tool) tool.set({ open: 0 });
      this.snd('tone', 520, 30, { vol: 0.03, type: 'triangle' });
      if (this.hurt(22, cfg.flinchChance)) this.jolt();
    },
    jolt() {
      const d = this.g.sut.drag;
      if (!d) return;
      const a = Math.random() * Math.PI * 2, r = (1.2 + Math.random() * 1.6) * MM;
      d.jit[0] += Math.cos(a) * r; d.jit[1] += Math.sin(a) * r;
      d.flinch = true;
    },
    tickStitch(dt) {
      const g = this.g, S = this.S, d = g.sut.drag;
      if (!d) return;
      const hit = S.tools.hit;
      S.stitches.preview(d.a, hit ? hit.point : null);
      if (hit) {
        const { loc, mm } = this.edgeDist(hit.uv);
        const across = loc.side !== this.near;
        this.cursorHint(across ? (mm >= this.cfg.biteMin ? T('cur_release', 'Release to tie') : T('cur_further', 'A little further')) : T('cur_pull', 'Pull across the cut'), across && mm >= this.cfg.biteMin ? 'teal' : '');
      }
      // un-numbed patients may flinch while the needle is in
      if (!this.anaesthetised() && Math.random() < dt * 0.35 && this.hurt(6, this.cfg.flinchChance)) this.jolt();
    },
    cancelDrag() {
      const g = this.g;
      g.sut.drag = null;
      this.S.stitches.preview(null);
      this.S.tools.press(false);
    },
    endStitch() {
      const g = this.g, S = this.S, cfg = this.cfg, d = g.sut.drag;
      g.sut.drag = null;
      S.stitches.preview(null);
      S.tools.press(false);
      const hit = S.tools.hit;
      if (!hit) return;
      const st = S.uvToST(hit.uv);
      const bUv = S.stToUv(st[0] + d.jit[0], st[1] + d.jit[1]);
      const { loc, mm } = this.edgeDist(bUv);
      const dur = g.t - d.t0;
      const miss = msg => { g.sut.misses++; this.hurt(8, 0); this.flash('bad', msg, 2800); this.snd('fail'); this.renderDots(); };
      if (loc.side === this.near || mm < cfg.biteMin * 0.6) return miss(d.flinch ? T('sut_miss_flinch', 'The patient flinched and the needle came out on the same side.') : T('sut_miss_side', 'The needle came out on the same side — pull across to the far edge.'));
      if (mm > cfg.biteMax + 2) return miss(T('sut_miss_far', 'Too far on the far side — that would pucker the skin.'));
      if (loc.tN < 0.01 || loc.tN > 0.99) return miss(T('sut_ends', 'Stay along the cut, not past its ends.'));
      // judge
      const tMid = (d.aTN + loc.tN) / 2;
      const at = this.w.at(tMid);
      const sa = S.uvToST(d.a), sb = S.uvToST(bUv);
      const vx = sb[0] - sa[0], vy = sb[1] - sa[1], vl = Math.hypot(vx, vy) || 1;
      const perp = Math.acos(clamp(Math.abs((vx * at.nrm[0] + vy * at.nrm[1]) / vl), 0, 1)) * 180 / Math.PI;
      const ideal = cfg.bite;
      const biteQ = clamp(100 - 11 * Math.abs(d.aMm - ideal) - 11 * Math.abs(mm - ideal) - 8 * Math.abs(d.aMm - mm), 0, 100);
      const perpQ = clamp(100 - Math.max(0, perp - 6) * 2.6, 0, 100);
      const slot = clamp(Math.floor(tMid * g.sut.N), 0, g.sut.N - 1);
      const spaceMm = Math.abs(tMid - (slot + 0.5) / g.sut.N) * this.Lmm;
      const spaceQ = clamp(100 - Math.max(0, spaceMm - 0.8) * 14, 0, 100);
      const fast = dur < cfg.minDrag;
      const q = clamp(0.4 * biteQ + 0.3 * perpQ + 0.3 * spaceQ - (fast ? 15 : 0) - (d.flinch ? 8 : 0), 0, 100);
      S.stitches.add({ a: d.a, b: bUv, knot: 'b', seed: g.sut.list.length * 31 + 7 });
      this.w.close(tMid, 1, 0.5 / g.sut.N);
      g.sut.list.push({ tN: tMid, q, bite: [d.aMm, mm], perp, space: spaceMm, fast, flinch: d.flinch });
      this.hurt(8, 0);
      this.setBleed();
      // a little blood squeezes out along the cut as the edges come together
      S.layers.paint('blood', at.uv, [(this.Lmm / g.sut.N) * 0.45 * MM, (this.w.halfGape(tMid) + 0.0009)], 0.3, { hardness: 0.35, grain: 0.3, grainScale: 160, angle: Math.atan2(at.dir[1], at.dir[0]) });
      // feedback
      let fb;
      if (fast) fb = ['warn', T('fb_fast', 'Too fast — follow the curve of the needle.')];
      else if (biteQ < 60) fb = ['warn', T('fb_bite', 'Uneven bite — %s mm and %s mm. Aim for %s on both sides.', d.aMm.toFixed(1), mm.toFixed(1), ideal)];
      else if (perpQ < 60) fb = ['warn', T('fb_angle', 'Crooked stitch (%s°) — pull straight across the cut.', Math.round(perp))];
      else if (spaceQ < 60) fb = ['warn', T('fb_space', 'Off the marker by %s mm — keep the spacing even.', spaceMm.toFixed(1))];
      else fb = ['ok', T('fb_good', 'Good stitch — %s mm bites, %s° off square.', ((d.aMm + mm) / 2).toFixed(1), Math.round(perp))];
      this.flash(fb[0], fb[1], 2200);
      g.sut.last = fb;
      this.snd('click', q >= 70 ? 760 : 420);
      this.renderDots();
      const allCovered = this.coveredSlots().every(Boolean);
      if (allCovered) {
        S.markers.remove('in'); S.markers.remove('inR'); S.markers.remove('out');
        this.completeStep(3, T('s3_done', 'The cut is closed.'));
      } else if (g.sut.list.length >= g.sut.N + cfg.extraStitches) {
        this.completeStep(3, T('s3_done_gaps', 'Closed — with gaps between the stitches.'));
      } else {
        if (g.sut.list.length >= g.sut.N) this.flash('warn', T('sut_gap', 'There is still a gap — add a stitch at the marker.'), 2600);
        this.sutureMarkers();
      }
    },
    renderDots() {
      const g = this.g;
      if (!g || !this.dots) return;
      const N = g.sut.N, cov = this.coveredSlots(), next = this.nextSlot();
      const qBySlot = new Array(N).fill(null);
      for (const s of g.sut.list) { const i = clamp(Math.floor(s.tN * N), 0, N - 1); qBySlot[i] = qBySlot[i] === null ? s.q : Math.max(qBySlot[i], s.q); }
      this.dots.innerHTML = qBySlot.map((q, i) => `<i class="${cov[i] ? (q >= 75 ? 'ok' : q >= 50 ? 'mid' : 'bad') : i === next && g.step === 3 ? 'cur' : ''}"></i>`).join('');
    },

    /* ═════════════ 4 · DRESSING ═════════════ */
    startDressing() {
      const g = this.g, S = this.S, w = this.w;
      if (g.dr.D) return;
      const gape = w.p.gape / MM;
      const pw = this.Lmm + 12, ph = clamp(gape * 2.6 + 12, 18, 28);
      const dw = pw + 16, dh = ph + 16;
      // zoom out a little so the dressing fits beside the cut
      const viewW = clamp(Math.max(this.viewW * 1.4, (dw + 40) * MM), 0.08, 0.26);
      S.controls.frame([0.5, 0.5], viewW, { instant: false, pitch: 1.24 });
      // rest it on the far side of the cut, a little crooked
      const c = w.at(0.5), off = (dh / 2 + 15) * MM, far = -this.near;
      let uv = S.stToUv(c.s + c.nrm[0] * off * far, c.t + c.nrm[1] * off * far);
      const ang = Math.atan2(-c.dir[1], c.dir[0]) + 0.1;
      g.dr.D = S.dressing.create({ size: [dw * MM, dh * MM], pad: [pw * MM, ph * MM], uv, angle: ang });
      g.dr.restUv = uv;
    },
    dressDown() {
      const g = this.g, S = this.S, D = g.dr.D;
      if (!D) return;
      const hit = S.raycast();
      const pick = D.pick(hit);
      if (pick === 'edge' && D.stuck < 0.25 && D.state !== 'carried') {
        if (D.grab(hit)) { this.stage.classList.add('grabbing'); this.snd('tone', 300, 40, { vol: 0.03, type: 'triangle' }); return; }
      }
      if (D.state === 'placed' || D.state === 'falling') { g.dr.rub = true; return; }
      if (pick === 'body') this.flash('warn', T('dress_edge', 'Pick it up by its **edge**.'));
      else if (D.stuck >= 0.25 && pick === 'edge') this.flash('warn', T('dress_stuck', 'It is already sticking — rub it down.'));
    },
    dressUp() {
      const g = this.g, D = g.dr.D;
      g.dr.rub = false;
      if (!D) return;
      if (D.state === 'carried') { D.release(); g.dr.settledT = 0; this.stage.classList.remove('grabbing'); }
    },
    tickDressing(dt) {
      const g = this.g, S = this.S, cfg = this.cfg, D = g.dr.D;
      if (!D) return;
      const hit = S.raycast();
      if (D.state === 'carried') { if (hit) D.move(hit); return; }
      if (!g.lmb) {
        const pick = hit ? D.pick(hit) : null;
        this.stage.classList.toggle('grab', pick === 'edge' && D.stuck < 0.25);
        if (pick === 'edge' && D.stuck < 0.25 && D.state === 'rest') this.cursorHint(T('cur_grab', 'Grab the edge'), 'teal');
      }
      if (D.state === 'placed' || D.state === 'falling') {
        g.dr.settledT += dt;
        if (g.dr.settledT > 0.4) {
          g.dr.cover = D.covers(this.pts);
          D.seep(clamp(0.12 + this.bleedNow() / 8, 0, 0.7) * clamp(g.dr.cover, 0.3, 1), this.w.at(0.5).uv);
        }
      }
      if (g.dr.rub && g.lmb && hit && (D.state === 'placed' || D.state === 'falling')) {
        D.rub(hit, dt);
        this.cursorProgress(D.stuck, '');
      }
      // misplaced pad: allow a retry while it is barely stuck
      if (D.state === 'placed' && g.dr.settledT > 0.6 && g.dr.cover < cfg.coverMin && D.stuck < 0.25) {
        g.dr.warnT -= dt;
        if (g.dr.warnT <= 0) { g.dr.warnT = 5; this.flash('warn', T('dress_cover', 'The pad covers only %s% of the cut — lift it by an edge and try again.', pct(g.dr.cover)), 3600); }
      }
      if (!g.done[4] && D.stuck >= cfg.stuckDone && g.dr.settledT > 0.4) {
        g.dr.cover = D.covers(this.pts);
        this.completeStep(4, T('s4_done', 'Dressing on — %s% of the cut covered.', pct(g.dr.cover)));
      }
    },

    /* ═════════════ sound (only after real input: no autoplay warnings in previews) ═════════════ */
    snd(name, ...args) {
      if (!this.heard || !NZA.audio || typeof NZA.audio[name] !== 'function') return;
      try { NZA.audio[name](...args); } catch (e) { /* audio unavailable */ }
    },

    /* ═════════════ cursor helpers ═════════════ */
    cursorProgress(p, text, red) {
      this.curP = { p, text, red, t: performance.now() };
    },
    cursorHint(text, tone) {
      this.curH = { text, tone, t: performance.now() };
    },
    updateCursor() {
      const now = performance.now();
      const cp = this.curP && now - this.curP.t < 160 ? this.curP : null;
      const ch = this.curH && now - this.curH.t < 160 ? this.curH : null;
      const on = !!(cp || ch);
      this.cur.classList.toggle('on', on);
      if (!on) return;
      this.cur.style.transform = `translate(${this.mx}px,${this.my}px)`;
      const p = cp ? clamp(cp.p, 0, 1) : 0;
      this.curFg.setAttribute('stroke-dasharray', `${(p * 119.4).toFixed(1)} 120`);
      this.cur.classList.toggle('red', !!(cp && cp.red && p > 0.85));
      this.cur.querySelector('svg').style.display = cp ? '' : 'none';
      const tx = (ch && ch.text) || (cp && cp.text) || '';
      if (this.curTx.textContent !== tx) this.curTx.textContent = tx;
      this.curTx.className = `tx ${(ch && ch.tone) || ''}`;
    },

    /* ═════════════ panel refresh ═════════════ */
    updatePanel(force) {
      const g = this.g, pp = this.pp;
      if (!g || !pp) return;
      const b = this.bleedNow();
      pp.set({ stats: this.stats() });
      let wide;
      switch (g.step) {
        case 1: {
          const c = pct(g.irr.cont);
          wide = { label: T('w_cont', 'Debris'), value: String(c), unit: '%', tone: c > 40 ? 'red' : c > 10 ? 'amber' : 'teal',
            meter: { value: g.irr.cont, tone: c > 40 ? 'red' : c > 10 ? 'amber' : '' },
            caption: g.irr.ml + g.irr.syr > 0 ? T('w_cont_cap', 'Rinse to 0 % · %s mL left', Math.round(g.irr.ml + g.irr.syr)) : T('saline_empty', 'Saline used up'), captionTone: g.irr.ml + g.irr.syr < 60 ? 'amber' : '' };
          break;
        }
        case 2: {
          const p = Math.round(g.pain), n = g.lido.points.filter(x => x.done).length;
          wide = { label: T('w_pain', 'Pain'), value: String(p), unit: '%', tone: p >= 60 ? 'red' : p >= 30 ? 'amber' : 'teal',
            meter: { value: p / 100, tone: p >= 60 ? 'red' : p >= 30 ? 'amber' : '' },
            caption: T('w_pain_cap', 'Rings %s/%s · %s mL given', n, g.lido.points.length, g.lido.ml.toFixed(1)) };
          break;
        }
        case 3: {
          const n = this.coveredSlots().filter(Boolean).length;
          wide = { label: T('w_section', 'Stitch'), value: String(Math.min(n + (g.done[3] ? 0 : 1), g.sut.N)), unit: `/${g.sut.N}`, tone: 'teal',
            meter: { value: n / g.sut.N, segs: true },
            caption: g.sut.last ? g.sut.last[1] : T('w_section_cap', '%s mm bites · square to the cut', this.cfg.bite), captionTone: g.sut.last ? (g.sut.last[0] === 'ok' ? 'teal' : 'amber') : '' };
          break;
        }
        case 4: {
          const D = g.dr.D, s = D ? D.stuck : 0;
          wide = { label: T('w_stuck', 'Seal'), value: String(pct(s)), unit: '%', tone: s >= 0.9 ? 'teal' : '',
            meter: { value: s, zone: [this.cfg.stuckDone, 1] },
            caption: D && D.state !== 'rest' && D.state !== 'carried' ? T('w_cover', 'Pad over %s% of the stitches', pct(g.dr.cover)) : T('w_stuck_cap', 'Lift by the border · lay · smooth'), captionTone: D && D.state === 'placed' && g.dr.cover < this.cfg.coverMin ? 'amber' : '' };
          break;
        }
      }
      if (wide) pp.set({ wide });
      void b; void force;
    },

    /* ═════════════ markers ═════════════ */
    clearMarkers() { if (this.S) this.S.markers.clear(); this.mkOpacity = undefined; },

    /* ═════════════ finish ═════════════ */
    computeResult() {
      const g = this.g, cfg = this.cfg, W = cfg.weights;
      // 1 irrigation
      const clean = g.cont0 > 0 ? 1 - g.irr.cont / g.cont0 : 1;
      const irrQ = g.skipped[1] ? 0 : clamp(clean * 100 - (g.irr.partial ? 10 : 0), 0, 100);
      // 2 anaesthetic
      const pts = g.lido.points, done = pts.filter(p => p.done);
      const accQ = done.length ? done.reduce((s, p) => s + clamp(100 - Math.max(0, p.err - 1.2) * 18 - Math.max(0, p.ml - cfg.lidoDose * 1.4) * 40, 0, 100), 0) / done.length : 0;
      const lidoQ = g.skipped[2] || !done.length ? 0 : clamp(accQ * (done.length / pts.length), 0, 100);
      // 3 stitches
      const list = g.sut.list.slice().sort((a, b) => a.tN - b.tN);
      const N = g.sut.N;
      const avgQ = list.length ? list.reduce((s, x) => s + x.q, 0) / list.length : 0;
      let evenQ = 0;
      if (list.length) {
        const ideal = this.Lmm / N, gaps = [];
        for (let i = 1; i < list.length; i++) gaps.push((list[i].tN - list[i - 1].tN) * this.Lmm);
        const ends = [list[0].tN * this.Lmm, (1 - list[list.length - 1].tN) * this.Lmm];
        const dev = gaps.reduce((s, v) => s + Math.abs(v - ideal), 0) / Math.max(1, gaps.length);
        evenQ = clamp(100 - dev * 10 - Math.max(0, ends[0] - ideal * 0.85) * 6 - Math.max(0, ends[1] - ideal * 0.85) * 6, 0, 100);
      }
      const closed = this.closedFrac();
      const sutQ = clamp((avgQ * 0.65 + evenQ * 0.35) * closed - g.sut.misses * 4 - g.flinches * 2, 0, 100);
      // 4 dressing
      const D = g.dr.D;
      const stuck = D ? D.stuck : 0, cover = g.dr.cover || 0;
      const dresQ = clamp(cover * 70 + stuck * 30, 0, 100);
      const total = (irrQ * W.irrigate + lidoQ * W.anaesthetic + sutQ * W.suture + dresQ * W.dressing) / Math.max(1, W.irrigate + W.anaesthetic + W.suture + W.dressing);
      return {
        score: Math.round(clamp(total, 0, 100)),
        parts: { irrigate: Math.round(irrQ), anaesthetic: Math.round(lidoQ), suture: Math.round(sutQ), dressing: Math.round(dresQ) },
        irrigated: !g.skipped[1] && g.irr.cont * 100 <= 10, contamination: Math.round(g.irr.cont * 100), salineMl: Math.round(g.irr.used),
        lido: !g.skipped[2] && done.length >= Math.ceil(pts.length * 0.75), lidoPoints: done.length, lidoTotal: pts.length, lidoMl: +g.lido.ml.toFixed(2),
        gauze: g.gz.used,
        stitches: list.length, sections: N, closed: +closed.toFixed(3), misses: g.sut.misses, stitchQ: Math.round(avgQ), evenQ: Math.round(evenQ),
        dressed: !!(D && stuck >= cfg.stuckDone * 0.95), stuck: +stuck.toFixed(3), cover: +cover.toFixed(3),
        flinches: g.flinches, seconds: Math.round(g.t),
        skipped: Object.keys(g.skipped).map(Number),
      };
    },
    finish() {
      const g = this.g;
      if (this.finished) return;
      this.finished = true;
      this.S.tools.use(null);
      this.S.fluids.jet(false);
      this.stage.classList.remove('grab', 'grabbing');
      const res = this.computeResult();
      this.result = res;
      // show the scene a moment longer, then the card
      setTimeout(() => {
        if (!this.alive || this.g !== g) return;
        this.showResult(res, null);
        NZA.post('suture:finish', res).then(r => {
          if (!this.alive) return;
          if (r && r.outcome) this.showOutcome(r.outcome);
          else if (r && r.ok === false) this.showOutcome({ error: r.msg || T('err_save', 'The result could not be saved.') });
        });
      }, 650);
    },
    feedback(res) {
      const out = [];
      if (res.skipped.includes(1)) out.push(['bad', T('fbk_no_irrigate', 'The wound was closed without irrigation — high infection risk.')]);
      else if (res.contamination > 10) out.push(['warn', T('fbk_dirty', '%s% contamination was left in the wound.', res.contamination)]);
      else out.push(['ok', T('fbk_clean', 'Rinsed clean with %s mL of saline.', res.salineMl)]);
      if (res.skipped.includes(2) || !res.lido) out.push(['warn', T('fbk_no_lido', 'No local anaesthetic — the patient flinched %s times.', res.flinches)]);
      else out.push(['ok', T('fbk_lido', 'Both edges numbed (%s/%s points, %s mL).', res.lidoPoints, res.lidoTotal, res.lidoMl)]);
      if (res.stitchQ >= 75 && res.evenQ >= 70) out.push(['ok', T('fbk_stitch_good', 'Neat, even stitches.')]);
      else if (res.evenQ < 70) out.push(['warn', T('fbk_stitch_even', 'Uneven spacing between the stitches.')]);
      else out.push(['warn', T('fbk_stitch_q', 'Bites and angles could be cleaner.')]);
      if (res.misses) out.push(['warn', T('fbk_misses', '%s pass(es) missed the far edge.', res.misses)]);
      if (res.cover < 0.95) out.push(['warn', T('fbk_cover', 'The pad covers %s% of the cut.', Math.round(res.cover * 100))]);
      return out;
    },
    showResult(res, outcome) {
      this.resultShown = true;
      if (this.pp) { this.pp.destroy(); this.pp = null; }
      this.ptEl.style.display = 'none'; this.planEl.style.display = 'none';
      const score = outcome && outcome.score !== undefined ? outcome.score : res.score;
      const grade = (outcome && outcome.grade) || (score >= 90 ? 'S' : score >= 80 ? 'A' : score >= 65 ? 'B' : score >= 50 ? 'C' : score >= 35 ? 'D' : 'F');
      const inj = this.inj;
      const rows = [
        [T('r_irrigate', 'Irrigation'), res.skipped.includes(1) ? T('skipped', 'Skipped') : `${res.contamination}%`, T('r_irrigate_sub', 'left'), res.parts.irrigate],
        [T('r_lido', 'Anaesthetic'), res.lido ? `${res.lidoPoints}/${res.lidoTotal}` : T('none', 'None'), res.lido ? T('r_lido_sub', 'points') : '', res.parts.anaesthetic],
        [T('r_stitches', 'Stitches'), `${res.stitches}`, T('r_stitches_sub', '%s misses · %s% even', res.misses, res.evenQ), res.parts.suture],
        [T('r_dressing', 'Dressing'), `${Math.round(res.cover * 100)}%`, T('r_dressing_sub', 'covered · %s% stuck', Math.round(res.stuck * 100)), res.parts.dressing],
      ];
      const tone = v => (v >= 75 ? '' : v >= 45 ? 'amber' : 'red');
      const fb = this.feedback(res);
      const waiting = !outcome;
      const err = outcome && outcome.error;
      this.canClose = !waiting;
      this.resWrap.innerHTML = `
        <div class="sz-result nza-hud solid nza-pop ${score < 50 ? 'low' : ''}">
          <div class="rh"><span class="grade g-${esc(grade)}">${esc(grade)}</span>
            <div><h3>${esc(score >= 50 ? T('r_title', 'Wound closed') : T('r_title_low', 'Wound closed — poorly'))}</h3><p>${esc(inj.label || '')} · ${esc(inj.regionLabel || '')} · ${esc(T('r_meta', '%s stitches · %s', res.stitches, NZA.fmt.time(res.seconds)))}</p></div>
            <div class="sc"><b>${esc(score)}</b><span>${esc(T('r_score', 'Score'))}</span></div></div>
          <table>${rows.map(r => `<tr><td class="k">${esc(r[0])}</td><td class="d">${esc(r[1])}<i>${esc(r[2])}</i></td><td class="m">${NZA.ui.meterHTML({ value: r[3] / 100, tone: tone(r[3]) })}</td><td class="n">${esc(r[3])}</td></tr>`).join('')}</table>
          <ul class="fb">${fb.map(f => `<li class="${f[0]}">${esc(f[1])}</li>`).join('')}</ul>
          ${outcome && outcome.msg ? `<div class="msg">${esc(outcome.msg)}</div>` : ''}
          ${err ? `<div class="msg err">${esc(err)}</div>` : ''}
          <div class="act">${waiting ? `<span class="wait"><span class="ring"></span>${esc(T('r_saving', 'Saving the treatment…'))}</span>` : ''}
            <button class="pp-done" ${waiting ? 'disabled style="opacity:.45;pointer-events:none"' : ''}><kbd>Enter</kbd>${esc(T('done', 'Done'))}</button></div>
        </div>`;
      const btn = this.resWrap.querySelector('.pp-done');
      if (btn) btn.onclick = () => { if (this.canClose) this.closeNow(); };
    },
    showOutcome(o) {
      if (!this.result) return;
      this.showResult(this.result, o || {});
      if (!o.error) this.snd('success');
    },
    abort() {
      if (this.finished) { if (this.canClose) this.closeNow(); return; }
      NZA.post('suture:abort', {});
      NZA.close('suture');
    },
    closeNow() { NZA.close('suture'); },

    /* ═════════════ no WebGL: short manual fallback ═════════════ */
    fallback() {
      this.loadEl.classList.add('out');
      const inj = this.inj || DEMO.injury;
      this.Lmm = +inj.length || 40;
      this.g = null;
      this.ptEl.style.display = 'none'; this.planEl.style.display = 'none';
      this.pp = NZA.ui.ProcPanel(this.ui, {
        step: 1, total: 1, tag: T('tag', 'Suture'), title: T('fb_title', 'Closing the wound'),
        text: T('fb_text', '3D view unavailable on this client — the wound is closed with a standard technique.'),
        stats: [{ label: T('st_site', 'Site'), value: inj.regionLabel || inj.region || '', small: true }, { label: T('st_length', 'Length'), value: String(Math.round(this.Lmm)), unit: 'mm' }],
        wide: { label: T('w_progress', 'Progress'), value: '0', unit: '%', meter: { value: 0 } },
        tools: [], abort: { label: T('hold_stop', 'Hold to stop'), key: 'ESC', seconds: 1.2 }, onAbort: () => this.abort(),
      });
      const dur = Math.max(8, +(this.cfg && this.cfg.fallbackTime) || 14);
      let t = 0;
      this.fallbackTimer = setInterval(() => {
        t += 0.25;
        if (this.pp) this.pp.wide({ value: String(Math.round(Math.min(1, t / dur) * 100)), meter: { value: Math.min(1, t / dur) } });
        if (t >= dur) {
          clearInterval(this.fallbackTimer); this.fallbackTimer = null;
          const res = { score: 60, parts: { irrigate: 60, anaesthetic: 60, suture: 60, dressing: 60 }, irrigated: true, contamination: 0, salineMl: 120, lido: false, lidoPoints: 0, lidoTotal: 0, lidoMl: 0, gauze: 0, stitches: 0, sections: 0, closed: 1, misses: 0, stitchQ: 60, evenQ: 60, dressed: true, stuck: 1, cover: 1, flinches: 0, seconds: Math.round(t), skipped: [], fallback: true };
          this.result = res; this.finished = true; this.inj = inj;
          this.showResult(res, null);
          NZA.post('suture:finish', res).then(r => { if (r && r.outcome) this.showOutcome(r.outcome); });
        }
      }, 250);
    },

    /* ═════════════ demo automation (browser preview / screenshots) ═════════════
       NZA.apps.suture.demoTo('irrigating'|'irrigated'|'lido'|'suturing'|'dressing'|'placed'|'done') */
    demoTo(stage) {
      const S = this.S, g = this.g;
      if (!S || !g) return false;
      S.stop();
      const sim = (sec, fn) => { const n = Math.ceil(sec * 30); for (let i = 0; i < n; i++) { if (fn) fn(i / n, i); S.step(1 / 30, false); } };
      const aim = uv => { const p = S.project(uv); S.pointer.x = p.x; S.pointer.y = p.y; this.mx = p.x * window.innerWidth; this.my = p.y * window.innerHeight; };
      const press = () => this.down({ button: 0 }), release = () => this.up({ button: 0 });
      const w = this.w;
      const irrigate = (amount) => {
        this.useTool('saline'); aim(w.at(0.05).uv); sim(0.1); press();
        sim(amount, f => aim(w.at(0.04 + 0.92 * (0.5 - 0.5 * Math.cos(f * Math.PI * 3))).uv));
      };
      if (stage === 'irrigating') { irrigate(1.6); aim(w.at(0.62).uv); sim(0.2); S.start(); return true; }
      irrigate(7); release(); sim(1.0);
      if (!g.done[1]) { g.irr.cont = 0; this.completeStep(1, ''); }
      clearTimeout(this.stepTimer); if (g.step === 1) this.enterStep(2);
      if (stage === 'irrigated') { S.start(); return true; }
      const pts = g.lido.points;
      const nLido = stage === 'lido' ? Math.ceil(pts.length * 0.6) : pts.length;
      for (let i = 0; i < nLido; i++) { aim(pts[i].uv); sim(0.05); press(); sim(i === nLido - 1 && stage === 'lido' ? 0.45 : 1.0); if (!(i === nLido - 1 && stage === 'lido')) release(); sim(0.05); }
      if (stage === 'lido') { S.start(); return true; }
      clearTimeout(this.stepTimer); if (g.step === 2) this.enterStep(3);
      const N = g.sut.N, nSt = stage === 'suturing' ? N - 2 : N;
      for (let i = 0; i < nSt; i++) {
        const tN = (i + 0.5) / N + (Math.random() - 0.5) * 0.02;
        aim(w.edge(tN, this.near, (this.cfg.bite + (Math.random() - 0.5)) * MM)); sim(0.05); press();
        const b = w.edge(tN + (Math.random() - 0.5) * 0.01, -this.near, (this.cfg.bite + (Math.random() - 0.5)) * MM);
        sim(0.4, f => { const a = w.edge(tN, this.near, this.cfg.bite * MM); aim([lerp(a[0], b[0], f), lerp(a[1], b[1], f)]); });
        aim(b); sim(0.03); release(); sim(0.1);
      }
      if (stage === 'suturing') {
        const i = nSt, tN = (i + 0.5) / N;
        aim(w.edge(tN, this.near, this.cfg.bite * MM)); sim(0.05); press();
        aim(w.at(tN + 0.004).uv); sim(0.2);
        S.start(); return true;
      }
      clearTimeout(this.stepTimer); if (g.step === 3) this.enterStep(4);
      sim(0.6);
      const D = g.dr.D;
      if (stage === 'dressing') { aim(g.dr.restUv); S.start(); return true; }
      // grab the near edge of the resting dressing and lay it over the cut
      const c = w.at(0.5), dh = D.size[1];
      const edgeSt = [S.uvToST(g.dr.restUv)[0] + c.nrm[0] * this.near * (dh / 2 - 0.0015), S.uvToST(g.dr.restUv)[1] + c.nrm[1] * this.near * (dh / 2 - 0.0015)];
      aim(S.stToUv(edgeSt[0], edgeSt[1])); sim(0.05); press();
      const target = S.stToUv(c.s + c.nrm[0] * this.near * (dh / 2 - 0.0015), c.t + c.nrm[1] * this.near * (dh / 2 - 0.0015));
      const st0 = S.uvToST(S.stToUv(edgeSt[0], edgeSt[1])), st1 = S.uvToST(target);
      sim(0.8, f => aim(S.stToUv(lerp(st0[0], st1[0], f), lerp(st0[1], st1[1], f))));
      if (stage === 'carry') { S.start(); return true; }
      release(); sim(1.4);
      if (stage === 'placed') { S.start(); return true; }
      aim(w.at(0.5).uv); sim(0.05);
      press();
      // rub in a zig-zag over the whole dressing
      const cst = S.uvToST(w.at(0.5).uv), half = [D.size[0] / 2 - 0.004, D.size[1] / 2 - 0.004], dir = c.dir, nrm = c.nrm;
      sim(6, f => {
        const x = Math.sin(f * Math.PI * 9) * half[0], y = (f * 2 - 1) * half[1] * (f < 0.5 ? 1 : -1);
        aim(S.stToUv(cst[0] + dir[0] * x + nrm[0] * y, cst[1] + dir[1] * x + nrm[1] * y));
      });
      // keep rubbing until it sticks (the preview always reaches the result card)
      for (let k = 0; k < 6 && !g.done[4]; k++) {
        sim(2, f => {
          const x = Math.sin(f * Math.PI * 6 + k) * half[0], y = Math.sin(f * Math.PI * 2 + k * 1.3) * half[1];
          aim(S.stToUv(cst[0] + dir[0] * x + nrm[0] * y, cst[1] + dir[1] * x + nrm[1] * y));
        });
      }
      release(); sim(0.3);
      S.start();
      return true;
    },
  });
})();
