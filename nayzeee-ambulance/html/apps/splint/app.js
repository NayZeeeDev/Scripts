/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · Splint (app 'splint')             module: splint
   In-world splinting on the shared procedure panel (NZA.ui.ProcPanel), over a
   top-down (or side-on) game camera on the broken limb:
     1 Place the splint   drag the measured splint onto the limb; Q / E rotate,
                          arrows nudge, X reset, Shift fine, right-drag turns the
                          limb (camera), wheel zooms. Both ends must sit on their
                          joint (world anchors 'prox' / 'dist'); it sets itself
                          after a short steady hold (or Space).
     2 Pad & mould        click / hold each point along the splint until it sits
                          flush; bony points get padding first; over-moulding
                          leaves a pressure point.
     3 Strap & check CMS  wrap 3 straps (click), lock each tension in the band
                          (click again); then click the toes / fingers ('cms'
                          anchor) for circulation, motor and sensation. A strap
                          that is too tight cuts the pulse off: loosen it and
                          check again.
   The splint pose lives in the limb's frame, so it stays on the limb when the
   camera turns or zooms. Also hosts the mobility HUD (wheelchair / crutches).

   Lua → JS   open { mode = 'proc', locale, region, regionLabel, limb, device, deviceLabel,
                     fracture, open, segLen, pulse, pulseWhy, tune, keys }
              open { mode = 'hud', locale, hud }      hud (hud)      hudOff     procEnd
              result (outcome)    anchors { prox, dist, cms, core }
   JS → Lua   splint:finish (result)  splint:abort  splint:done  splint:close
   ═══════════════════════════════════════════════════════════ */
(() => {
  const APP = 'splint';
  const esc = NZA.esc, icon = NZA.icon, clamp = NZA.clamp;
  let LOC = {};
  const T = (k, fb, ...a) => { let s = LOC[k] !== undefined ? String(LOC[k]) : fb; a.forEach(x => { s = s.replace(/%[sd]/, x); }); return s; };

  /* ─────────────── 2D vectors (screen px) ─────────────── */
  const v = (x, y) => ({ x, y });
  const add = (a, b) => v(a.x + b.x, a.y + b.y);
  const sub = (a, b) => v(a.x - b.x, a.y - b.y);
  const mul = (a, k) => v(a.x * k, a.y * k);
  const dot = (a, b) => a.x * b.x + a.y * b.y;
  const len = a => Math.hypot(a.x, a.y);
  const perp = a => v(-a.y, a.x);
  const rotv = (a, r) => { const c = Math.cos(r), s = Math.sin(r); return v(a.x * c - a.y * s, a.x * s + a.y * c); };
  const lerp = (a, b, t) => a + (b - a) * t;
  const easeOut = t => 1 - Math.pow(1 - clamp(t, 0, 1), 3);
  const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
  const keyLabel = c => ({ Space: 'Space', Enter: 'Enter', Escape: 'ESC', ShiftLeft: 'Shift' })[c] || String(c || '').replace(/^Key|^Digit/, '');

  const DEF_TUNE = {
    tolerance: 0.075, lockHold: 0.7, rotateSpeed: 55, nudgeSpeed: 0.30, fine: 0.22,
    mouldPoints: 6, mouldSeconds: 1.15, mouldClick: 0.18, mouldZone: [0.72, 1.0],
    strapZone: [0.55, 0.82], strapTight: 0.88, strapPeriod: 1.7,
    extProx: 0.07, extDist: 0.06,
  };
  const DEF_KEYS = { rotateLeft: 'KeyQ', rotateRight: 'KeyE', reset: 'KeyX', set: 'Space' };
  const COL = { teal: '#08afa2', tealHi: '#2fe0d0', red: '#e5484d', redHi: '#ff7478', amber: '#e5a50a', amberHi: '#f3c35a', white: '#ffffff' };

  /* ═══════════════════════════ APP ═══════════════════════════ */
  const A = {
    escClose: false,
    camInput: true,

    init(el) {
      this.el = el;
      el.innerHTML = `
        <canvas class="sp-cv"></canvas>
        <div class="sp-tags"></div>
        <div class="sp-cms nza-hud solid" hidden></div>
        <div class="sp-res nza-hud solid rail" hidden></div>
        <div class="sp-hint" hidden></div>
        <div class="sp-hud nza-hud" hidden></div>`;
      this.cv = el.querySelector('.sp-cv');
      this.ctx = this.cv.getContext('2d');
      this.tagsEl = el.querySelector('.sp-tags');
      this.cmsEl = el.querySelector('.sp-cms');
      this.resEl = el.querySelector('.sp-res');
      this.hintEl = el.querySelector('.sp-hint');
      this.hudEl = el.querySelector('.sp-hud');
      this.anc = {};
      this.tags = {};
      this.shift = false;
      this.held = new Set();
      NZA.ui.Anchors(APP).on(map => { this.anc = map || {}; });

      window.addEventListener('keydown', e => { if (e.key === 'Shift') this.shift = true; });
      window.addEventListener('keyup', e => { if (e.key === 'Shift') this.shift = false; });
      window.addEventListener('blur', () => { this.held.clear(); this.shift = false; this.pointerUp(); });
      window.addEventListener('mousedown', e => this.pointerDown(e));
      window.addEventListener('mousemove', e => this.pointerMove(e));
      window.addEventListener('mouseup', e => { if (e.button === 0) this.pointerUp(e); });
      this.loop = this.loop.bind(this);
    },

    open(d) {
      LOC = Object.assign(LOC, d.locale || {});
      if (d.mode === 'hud') { this.hudShow(d.hud || {}); return; }
      this.procStart(d);
    },

    close() {
      this.procStop();
      this.hudHide();
    },

    msg: {
      result(o) { A.showResult(o || {}); },
      hud(d) { A.hudShow(d || {}); },
      hudOff() { A.hudHide(); },
      procEnd() { A.procStop(); },
      error(d) { if (A.pp) A.pp.flash('bad', (d && d.msg) || T('err', 'Something went wrong')); },
    },

    keys: {},
    keysUp: {},

    /* ═════════════════════ PROCEDURE ═════════════════════ */
    procStart(d) {
      this.procStop();
      this.d = d;
      this.tune = Object.assign({}, DEF_TUNE, d.tune || {});
      this.K = Object.assign({}, DEF_KEYS, d.keys || {});
      const kind = d.device === 'arm' || d.limb === 'arm' ? 'arm' : 'leg';
      this.kind = kind;
      const nPts = clamp(Math.round(Number(this.tune.mouldPoints) || (kind === 'leg' ? 6 : 5)), 3, 9);
      const S = {
        step: 1, active: true, t0: performance.now(),
        pose: { cu: 0, cv: 0, phi: 0 }, pose0: null,
        drag: null, alignHold: 0, locked: false, lockAnim: null, resets: 0, moved: false,
        aligned: { p: false, d: false }, err: { p: 1, d: 1, a: 90 },
        points: Array.from({ length: nPts }, (_, i) => ({
          t: 0.07 + i * (0.86 / (nPts - 1)), f: 0, pad: i === 0 || i === nPts - 1, padded: false,
          done: false, tight: false, pop: 0,
        })),
        press: -1,
        straps: [0.2, 0.5, 0.79].map((t, i) => ({ i, t, state: 'open', tension: 0, ph: 0, anim: 0, quality: 0, locks: 0 })),
        sweeping: -1,
        cms: { state: 'hidden', checks: 0, t: 0, rows: null, fixed: false },
        tightEver: 0, s1: 0, s2: 0, s3: 0, finished: false, result: null,
      };
      this.S = S;
      this.held.clear();
      this.wireKeys();
      this.cv.classList.add('on');
      this.cmsEl.hidden = true; this.resEl.hidden = true; this.hintEl.hidden = true;
      this.tagsEl.innerHTML = ''; this.tags = {};

      this.pp = NZA.ui.ProcPanel(this.el, {
        step: 1, total: 3, tag: `${T('tag', 'Splinting')} · ${d.regionLabel || ''}`,
        title: '', text: '', stats: [], tools: this.toolsFor(1),
        hints: [],
        abort: { label: T('hold_abort', 'Hold to abort'), key: 'ESC', seconds: 1.2 },
        onAbort: () => this.abort(),
        onTool: () => {},
      });
      this.pp.el.classList.add('sp-pp');
      this.enterStep(1);
      if (d.open) setTimeout(() => this.pp && this.S === S && this.pp.flash('warn', d.dressed ? T('open_dressed', 'Open fracture, dressed. Keep the dressing clean under the splint.') : T('open_warn', 'Open fracture: the bone broke the skin. Cover it before you strap over it.'), 5200), 500);
      else if (d.fracture && d.fracture.displaced) setTimeout(() => this.pp && this.S === S && this.pp.flash('warn', T('displaced', 'Displaced fracture (%s°). Splint it where it lies; it is reduced in hospital.', Math.round(d.fracture.angle || 0)), 4600), 500);
      if (!this.raf) this.raf = requestAnimationFrame(this.loop);
    },

    procStop() {
      if (this.S) this.S.active = false;
      this.S = null;
      this.held.clear();
      if (this.pp) { this.pp.destroy(); this.pp = null; }
      if (this.raf) { cancelAnimationFrame(this.raf); this.raf = 0; }
      this.cv.classList.remove('on');
      const c = this.ctx; c.setTransform(1, 0, 0, 1, 0, 0); c.clearRect(0, 0, this.cv.width, this.cv.height);
      this.tagsEl.innerHTML = ''; this.tags = {};
      this.cmsEl.hidden = true; this.resEl.hidden = true; this.hintEl.hidden = true;
      this.keys = {}; this.keysUp = {};
    },

    wireKeys() {
      const K = this.K;
      const down = name => e => { if (!this.S || this.S.finished) return false; this.held.add(name); if (name !== 'up' && name !== 'down' && name !== 'left' && name !== 'right') this.S.moved = true; return true; };
      const up = name => () => { this.held.delete(name); return true; };
      this.keys = {
        [K.rotateLeft]: down('rotL'), [K.rotateRight]: down('rotR'),
        ArrowUp: down('up'), ArrowDown: down('down'), ArrowLeft: down('left'), ArrowRight: down('right'),
        [K.reset]: e => { if (!e.repeat) this.resetSplint(); },
        [K.set]: e => { if (!e.repeat) this.trySet(); },
        Enter: e => !!(this.pp && this.pp.key(e)),
      };
      this.keysUp = {
        [K.rotateLeft]: up('rotL'), [K.rotateRight]: up('rotR'),
        ArrowUp: up('up'), ArrowDown: up('down'), ArrowLeft: up('left'), ArrowRight: up('right'),
      };
    },

    toolsFor(step) {
      const st = i => (i < step ? 'done' : i === step ? 'active' : 'locked');
      return [
        { key: '1', label: T('tool_place', 'Place'), icon: 'splint', state: st(1) },
        { key: '2', label: T('tool_mould', 'Pad & mould'), icon: 'hand', state: st(2) },
        { key: '3', label: T('tool_strap', 'Straps & CMS'), icon: 'pulse', state: st(3) },
      ];
    },

    enterStep(n) {
      const S = this.S, d = this.d;
      if (!S) return;
      S.step = n;
      const K = this.K;
      const where = `**${(d.regionLabel || '').toLowerCase()}**`;
      if (n === 1) {
        this.pp.set({
          step: 1, title: T('s1_title', 'Place the splint'),
          text: T('s1_text', 'Drag the splint onto the %s. {%s} {%s} rotate it and the arrows nudge it until both ends line up with the joints.', where, keyLabel(K.rotateLeft), keyLabel(K.rotateRight)),
          stats: this.stats1(), tools: this.toolsFor(1),
          hints: [
            { keys: [`${keyLabel(K.rotateLeft)} / ${keyLabel(K.rotateRight)}`], label: T('h_rotate', 'Rotate') },
            { keys: ['← → ↑ ↓'], label: T('h_nudge', 'Nudge') },
            { keys: [keyLabel(K.reset)], label: T('h_reset', 'Reset') },
            { keys: ['Shift'], label: T('h_fine', 'Fine') },
            { keys: [T('k_rdrag', 'Right-drag')], label: T('h_turn', 'Turn the limb') },
          ],
        });
      } else if (n === 2) {
        this.pp.set({
          step: 2, title: T('s2_title', 'Pad & mould'),
          text: T('s2_text', 'Click or hold each point along the splint until it sits **flush** with the limb. Bony points get padding first. Stop in the band, or you leave a pressure point.'),
          stats: this.stats2(), tools: this.toolsFor(2),
          hints: [{ keys: [T('k_click', 'Click')], label: T('h_mould', 'Mould') }, { keys: ['Shift'], label: T('h_gentle', 'Gentle') }, { keys: [T('k_rdrag', 'Right-drag')], label: T('h_turn', 'Turn the limb') }],
        });
      } else {
        this.pp.set({
          step: 3, title: T('s3_title', 'Strap it & check CMS'),
          text: T('s3_text', 'Click a strap to wrap it, then click again when the tension needle is in the **band**. With all three secured, click the %s to check circulation, motor and sensation.', this.kind === 'leg' ? T('toes', 'toes') : T('fingers', 'fingers')),
          stats: this.stats3(), tools: this.toolsFor(3),
          hints: [{ keys: [T('k_click', 'Click')], label: T('h_strap', 'Wrap / lock strap') }, { keys: [T('k_rdrag', 'Right-drag')], label: T('h_turn', 'Turn the limb') }],
        });
      }
    },

    stats1() {
      const S = this.S, d = this.d;
      const st = ok => ({ value: ok ? T('aligned', 'Aligned') : T('offline', 'Off line'), tone: ok ? 'teal' : '' });
      return [
        Object.assign({ id: 'dist', label: T('distal', 'Distal end'), small: true }, st(S.aligned.d)),
        Object.assign({ id: 'prox', label: T('proximal', 'Proximal end'), small: true }, st(S.aligned.p)),
        { id: 'dev', label: T('device', 'Device'), value: d.deviceLabel || (this.kind === 'leg' ? T('dev_leg', 'Posterior leg splint') : T('dev_arm', 'Arm splint')), small: true },
      ];
    },
    stats2() {
      const S = this.S;
      const done = S.points.filter(p => p.done).length;
      const fit = Math.round(100 * S.points.reduce((a, p) => a + Math.min(1, p.f / this.tune.mouldZone[0]), 0) / S.points.length);
      const press = S.points.filter(p => p.tight).length;
      return [
        { id: 'mould', label: T('moulded', 'Moulded'), value: done, unit: `/${S.points.length}`, tone: done === S.points.length ? 'teal' : '' },
        { id: 'press', label: T('pressure', 'Pressure points'), value: press, tone: press ? 'amber' : '' },
        { id: 'fit', label: T('fit', 'Fit'), value: fit, unit: '%', meter: { value: fit / 100, tone: fit >= 100 ? '' : 'white' } },
      ];
    },
    stats3() {
      const S = this.S;
      const locked = S.straps.filter(s => s.state === 'locked').length;
      const sw = S.sweeping >= 0 ? S.straps[S.sweeping] : null;
      const z = this.tune.strapZone;
      const cmsTxt = { hidden: T('cms_wait', 'Straps first'), ready: T('cms_ready', 'Not checked'), checking: T('cms_checking', 'Checking…'), ok: T('cms_ok', 'Intact'), bad: T('cms_bad', 'Compromised') }[S.cms.state];
      return [
        { id: 'straps', label: T('straps', 'Straps'), value: locked, unit: '/3', tone: locked === 3 ? 'teal' : '' },
        { id: 'tension', label: T('tension', 'Tension'), value: sw ? Math.round(sw.tension * 100) : '--', unit: sw ? '%' : '', meter: { value: sw ? sw.tension : 0, zone: z, mark: sw ? sw.tension : undefined, noFill: true } },
        { id: 'cms', label: T('cms', 'Distal CMS'), value: cmsTxt, small: true, tone: S.cms.state === 'ok' ? 'teal' : S.cms.state === 'bad' ? 'red' : '' },
      ];
    },

    abort() {
      if (!this.S || this.S.finished) return;
      NZA.post(`${APP}:abort`, {});
      if (!NZA.inGame) { NZA.toast({ title: T('title', 'Splint'), message: T('aborted', 'Splinting stopped'), type: 'error' }); NZA.close(APP); }
    },

    /* ─────────────── limb frame & splint geometry ─────────────── */
    frame() {
      const a = this.anc || {}, W = this.cv.width, H = this.cv.height;
      const pr = a.prox, di = a.dist;
      if (!pr || !di || pr.visible === false || di.visible === false) return null;
      const P = v(pr.x * W, pr.y * H), D = v(di.x * W, di.y * H);
      const ax = sub(D, P), L = len(ax);
      if (L < 10) return null;
      const u = mul(ax, 1 / L), n = perp(u);
      const Tp = sub(P, mul(u, L * this.tune.extProx)), Td = add(D, mul(u, L * this.tune.extDist));
      const Ls = len(sub(Td, Tp));
      const wr = this.kind === 'leg' ? 0.165 : 0.2;
      return { P, D, u, n, L, Tp, Td, M: mul(add(Tp, Td), 0.5), Ls, Wd: Ls * wr };
    },
    geom(f, pose) {
      const s = rotv(f.u, pose.phi), m = perp(s);
      const C = add(f.M, add(mul(f.u, pose.cu * f.L), mul(f.n, pose.cv * f.L)));
      const H = f.Ls / 2;
      return { C, s, m, H, W: f.Wd, Sp: sub(C, mul(s, H)), Sd: add(C, mul(s, H)) };
    },
    local(g, p) { const r = sub(p, g.C); return v(dot(r, g.s), dot(r, g.m)); },
    world(g, x, y) { return add(g.C, add(mul(g.s, x), mul(g.m, y))); },
    toPose(f, C, phi) { const r = sub(C, f.M); return { cu: dot(r, f.u) / f.L, cv: dot(r, f.n) / f.L, phi }; },

    initialPose(f) {
      // start beside the limb, away from the body, tilted
      let side = 1;
      const core = this.anc.core;
      if (core && core.visible !== false) {
        const c = v(core.x * this.cv.width, core.y * this.cv.height);
        side = dot(sub(c, f.M), f.n) > 0 ? -1 : 1;
      }
      return { cu: 0.12, cv: side * 0.85, phi: side * 0.42 };
    },

    resetSplint() {
      const S = this.S;
      if (!S || S.step !== 1 || S.locked) return;
      const f = this.frame();
      if (!f) return;
      S.pose = this.initialPose(f); S.pose0 = Object.assign({}, S.pose);
      S.resets += 1; S.alignHold = 0;
      NZA.audio.click(420);
    },

    trySet() {
      const S = this.S;
      if (!S || S.step !== 1 || S.locked) return;
      if (S.aligned.p && S.aligned.d) this.lockSplint();
      else { this.pp.flash('warn', T('not_aligned', 'Line both ends up with the joints first.'), 2000); NZA.audio.click(260); }
    },

    lockSplint() {
      const S = this.S;
      const t = this.tune;
      const e = (S.err.p + S.err.d) / 2;
      S.s1 = Math.round(clamp(100 - (e / t.tolerance) * 22 - Math.max(0, S.err.a - 2) * 1.6 - Math.max(0, S.resets - 1) * 4, 35, 100));
      S.locked = true;
      S.lockAnim = { from: Object.assign({}, S.pose), t0: performance.now() };
      NZA.audio.success();
      this.pp.flash('ok', T('set_ok', 'Splint set: both joints held.'), 2200);
      setTimeout(() => { if (this.S === S) { S.pose = { cu: 0, cv: 0, phi: 0 }; this.enterStep(2); } }, 650);
    },

    /* ─────────────── pointer ─────────────── */
    px(e) { return v(e.clientX / window.innerWidth * this.cv.width, e.clientY / window.innerHeight * this.cv.height); },
    overUi(e) { return !!(e.target && e.target.closest && e.target.closest('.pp,.sp-res,.sp-hud')); },

    pointerDown(e) {
      const S = this.S;
      if (!S || !S.active || S.finished || e.button !== 0 || this.overUi(e)) return;
      const f = this.frame();
      if (!f) return;
      const p = this.px(e);
      const g = this.geom(f, S.pose);
      if (S.step === 1 && !S.locked) {
        const l = this.local(g, p);
        const pad = Math.max(14, g.W * 0.35);
        if (Math.abs(l.x) <= g.H + pad && Math.abs(l.y) <= g.W / 2 + pad) {
          S.drag = { last: p, off: sub(g.C, p) };
          S.moved = true;
          NZA.audio.click(560);
        }
      } else if (S.step === 2) {
        const i = this.pointAt(g, p);
        if (i >= 0) this.mouldStart(i);
      } else if (S.step === 3) {
        if (S.cms.state === 'ready' || S.cms.state === 'bad') {
          const c = this.cmsPos(f, g);
          if (c && len(sub(c, p)) <= Math.max(28 * (this.cv.height / 1080), g.W * 0.6)) { this.cmsCheck(); return; }
        }
        const si = this.strapAt(g, p);
        if (si >= 0) this.strapClick(si);
      }
    },
    pointerMove(e) {
      const S = this.S;
      if (!S || !S.drag) return;
      const f = this.frame();
      if (!f) return;
      const p = this.px(e);
      let C;
      if (this.shift || e.shiftKey) {
        const g = this.geom(f, S.pose);
        C = add(g.C, mul(sub(p, S.drag.last), this.tune.fine));
        S.drag.off = sub(C, p);
      } else {
        C = add(p, S.drag.off);
      }
      S.drag.last = p;
      S.pose = this.toPose(f, C, S.pose.phi);
    },
    pointerUp() {
      const S = this.S;
      if (!S) return;
      if (S.drag) S.drag = null;
      if (S.press >= 0) this.mouldEnd();
    },

    /* ─────────────── step 2: mould ─────────────── */
    pointAt(g, p) {
      const r = Math.max(16, g.W * 0.42);
      let best = -1, bd = r;
      this.S.points.forEach((pt, i) => {
        const c = this.world(g, -g.H + pt.t * 2 * g.H, 0);
        const d = len(sub(c, p));
        if (d < bd) { bd = d; best = i; }
      });
      return best;
    },
    mouldStart(i) {
      const S = this.S, pt = S.points[i];
      if (pt.done && pt.f >= 1) { this.pp.flash('warn', T('mould_full', 'That point is already flush.'), 1600); return; }
      if (pt.pad && !pt.padded) {
        pt.padded = true; pt.pop = 1;
        NZA.audio.tone(380, 90, { vol: 0.06, type: 'triangle' });
        this.pp.flash('ok', T('padded', 'Padded the bony point.'), 1400);
      }
      S.press = i;
      pt.f = Math.min(1.02, pt.f + this.tune.mouldClick);
      NZA.audio.noise(110, { vol: 0.05, lp: 900, hp: 200 });
      this.checkTight(pt);
    },
    mouldEnd() {
      const S = this.S, i = S.press;
      S.press = -1;
      if (i < 0) return;
      const pt = S.points[i];
      if (!pt.done && pt.f >= this.tune.mouldZone[0]) {
        pt.done = true; pt.pop = 1;
        NZA.audio.click(880);
      }
      this.pp.set({ stats: this.stats2() });
      this.checkMouldDone();
    },
    checkTight(pt) {
      if (pt.f > this.tune.mouldZone[1] && !pt.tight) {
        pt.tight = true; pt.f = 1; pt.done = true; this.S.press = -1;
        NZA.audio.click(240);
        this.pp.flash('bad', T('pressure_point', 'Too much pressure there: that leaves a pressure point.'), 2400);
        this.pp.set({ stats: this.stats2() });
        this.checkMouldDone();
      }
    },
    checkMouldDone() {
      const S = this.S;
      if (S.step !== 2 || !S.points.every(p => p.done)) return;
      const [z0] = this.tune.mouldZone;
      const q = S.points.map(p => (p.tight ? 52 : clamp(100 - Math.abs(p.f - (z0 + 1) / 2) * 140, 60, 100)) - (p.pad && !p.padded ? 15 : 0));
      S.s2 = Math.round(q.reduce((a, b) => a + b, 0) / q.length);
      NZA.audio.success();
      this.pp.flash('ok', T('mould_ok', 'Splint moulded to the limb.'), 2000);
      setTimeout(() => { if (this.S === S) this.enterStep(3); }, 700);
    },

    /* ─────────────── step 3: straps & CMS ─────────────── */
    strapAt(g, p) {
      const l = this.local(g, p);
      if (Math.abs(l.y) > g.W * 0.9) return -1;
      let best = -1, bd = Math.max(16, g.H * 0.09);
      this.S.straps.forEach((s, i) => {
        const x = -g.H + s.t * 2 * g.H;
        const d = Math.abs(l.x - x);
        if (d < bd) { bd = d; best = i; }
      });
      return best;
    },
    strapClick(i) {
      const S = this.S, s = S.straps[i];
      if (S.cms.state === 'checking') return;
      if (S.sweeping >= 0 && S.sweeping !== i) { this.pp.flash('warn', T('strap_one', 'Finish the strap you are tensioning first.'), 1600); return; }
      if (s.state === 'open' || s.state === 'locked') {
        if (s.state === 'locked') { NZA.audio.click(500); if (S.cms.state === 'ok') return; }
        s.state = 'wrap'; s.anim = 0; s.ph = 0; S.sweeping = i;
        NZA.audio.noise(260, { vol: 0.06, lp: 2400, hp: 400 });
        if (S.cms.state === 'bad' || S.cms.state === 'ready') { S.cms.state = S.straps.every(x => x.state === 'locked') ? 'ready' : 'hidden'; this.cmsEl.hidden = true; }
      } else if (s.state === 'sweep') {
        s.state = 'locked'; s.locks += 1; S.sweeping = -1;
        const z = this.tune.strapZone;
        const tn = s.tension;
        s.quality = tn > this.tune.strapTight ? 30 : tn < z[0] ? clamp(78 - (z[0] - tn) * 160, 30, 78) : clamp(100 - Math.abs(tn - (z[0] + z[1]) / 2) * 90, 80, 100);
        s.tight = tn > this.tune.strapTight;
        s.loose = tn < z[0];
        if (s.tight) S.tightEver += 1;
        NZA.audio.click(s.tight ? 300 : s.loose ? 520 : 940);
        this.pp.flash(s.tight ? 'bad' : s.loose ? 'warn' : 'ok', s.tight ? T('strap_tight', 'Strap %s is very tight.', i + 1) : s.loose ? T('strap_loose', 'Strap %s is loose; the splint can slip.', i + 1) : T('strap_ok', 'Strap %s secured.', i + 1), 1800);
        if (S.straps.every(x => x.state === 'locked')) {
          S.cms.state = 'ready';
          this.pp.flash('ok', T('cms_prompt', 'All straps on. Click the %s to check CMS.', this.kind === 'leg' ? T('toes', 'toes') : T('fingers', 'fingers')), 3200);
        }
      }
      this.pp.set({ stats: this.stats3() });
    },
    cmsPos(f, g) {
      const a = this.anc.cms;
      if (a && a.visible !== false) return v(a.x * this.cv.width, a.y * this.cv.height);
      return add(g.Sd, mul(g.s, f.L * 0.18));
    },
    cmsCheck() {
      const S = this.S, d = this.d;
      if (S.cms.state !== 'ready' && S.cms.state !== 'bad') return;
      S.cms.state = 'checking'; S.cms.checks += 1; S.cms.t = performance.now();
      const tight = S.straps.some(s => s.tight);
      const pulse = d.pulse || 'present';
      const limb = this.kind;
      const rows = [];
      if (tight) rows.push({ k: 'C', label: T('circ', 'Circulation'), value: T('c_tight', 'Weak distal pulse · refill 3.6 s'), tone: 'red' });
      else if (pulse === 'absent') rows.push({ k: 'C', label: T('circ', 'Circulation'), value: d.pulseWhy || T('c_absent', 'No distal pulse · tourniquet above'), tone: 'amber' });
      else if (pulse === 'weak') rows.push({ k: 'C', label: T('circ', 'Circulation'), value: d.pulseWhy || T('c_weak', 'Weak, thready pulse · in shock'), tone: 'amber' });
      else rows.push({ k: 'C', label: T('circ', 'Circulation'), value: T('c_ok', 'Distal pulse present · refill 1.4 s'), tone: 'teal' });
      rows.push({ k: 'M', label: T('motor', 'Motor'), value: tight ? T('m_tight', 'Weak movement') : (limb === 'leg' ? T('m_leg', 'Wiggles the toes') : T('m_arm', 'Moves the fingers')), tone: tight ? 'amber' : 'teal' });
      rows.push({ k: 'S', label: T('sens', 'Sensation'), value: tight ? T('s_tight', 'Pins and needles') : T('s_ok', 'Feels light touch'), tone: tight ? 'red' : 'teal' });
      S.cms.rows = rows;
      S.cms.tight = tight;
      this.renderCms(0);
      this.pp.set({ stats: this.stats3() });
      NZA.audio.click(700);
    },
    renderCms(shown) {
      const S = this.S, r = S.cms.rows || [];
      const title = this.kind === 'leg' ? T('cms_foot', 'Foot check') : T('cms_hand', 'Hand check');
      this.cmsEl.innerHTML = `<div class="hd">${icon('pulse')}<b>${esc(title)}</b><span>${esc(T('cms_short', 'CMS'))}</span></div>` +
        r.map((row, i) => `<div class="row ${i < shown ? `on ${row.tone}` : ''}"><span class="k">${esc(row.k)}</span><span class="l">${esc(row.label)}</span><span class="vv">${i < shown ? esc(row.value) : '<i class="dots"><i></i><i></i><i></i></i>'}</span></div>`).join('');
      this.cmsEl.hidden = false;
    },
    cmsTick(now) {
      const S = this.S;
      if (S.cms.state !== 'checking') return;
      const el = (now - S.cms.t) / 1000;
      const shown = Math.min(3, Math.floor(el / 0.55));
      if (shown !== S.cms.shown) {
        S.cms.shown = shown; this.renderCms(shown);
        if (shown > 0) NZA.audio.tick();
      }
      if (el >= 3 * 0.55 + 0.35) {
        if (S.cms.tight) {
          S.cms.state = 'bad'; S.cms.fixed = true;
          NZA.audio.fail();
          this.pp.flash('bad', T('cms_fail', 'Circulation cut off below the splint. Loosen the tight strap (click it) and check again.'), 5200);
          this.pp.set({ stats: this.stats3() });
        } else {
          S.cms.state = 'ok';
          this.pp.set({ stats: this.stats3() });
          this.finish();
        }
      }
    },

    finish() {
      const S = this.S;
      if (S.finished) return;
      S.finished = true;
      const q = S.straps.map(s => s.quality);
      const strapAvg = q.reduce((a, b) => a + b, 0) / q.length;
      const checksPenalty = Math.max(0, S.cms.checks - (S.cms.fixed ? 2 : 1)) * 4;
      S.s3 = Math.round(clamp(strapAvg + (S.cms.fixed ? 4 : 0) - checksPenalty, 25, 100));
      const score = Math.round(clamp(S.s1 * 0.4 + S.s2 * 0.3 + S.s3 * 0.3, 0, 100));
      const result = {
        score, align: S.s1, mould: S.s2, straps: S.s3, cms: 'ok', checks: S.cms.checks,
        pressure: S.points.filter(p => p.tight).length, padded: S.points.filter(p => p.pad && p.padded).length,
        tight: S.tightEver, loose: S.straps.filter(s => s.loose).length, resets: S.resets,
        time: Math.round((performance.now() - S.t0) / 100) / 10,
      };
      S.result = result;
      NZA.audio.success();
      this.pp.set({ title: T('securing', 'Securing the splint…'), titleTone: '', text: T('securing_text', 'Distal CMS intact. Recording the splint on the patient.'), tools: this.toolsFor(4) });
      NZA.post(`${APP}:finish`, result).then(r => {
        if (!NZA.inGame && r && r.outcome) this.showResult(r.outcome);
      });
    },

    showResult(o) {
      const S = this.S;
      if (!S || !this.pp) return;
      const r = S.result || {};
      const score = clamp(Math.round(o.score ?? r.score ?? 0), 0, 100);
      const grade = o.grade || (score >= 90 ? 'S' : score >= 80 ? 'A' : score >= 68 ? 'B' : score >= 55 ? 'C' : score >= 40 ? 'D' : 'F');
      const row = (lab, val) => `<div class="r"><span>${esc(lab)}</span><b>${esc(val)}</b><i style="width:${clamp(val, 0, 100)}%"></i></div>`;
      this.resEl.innerHTML = `
        <div class="top"><div class="grade g-${esc(grade)}">${esc(grade)}</div>
          <div><div class="nza-label">${esc(T('res_label', 'Splint applied'))}</div><div class="sc">${score}<span>/100</span></div><div class="dev">${esc(this.d.deviceLabel || '')} · ${esc(this.d.regionLabel || '')}</div></div></div>
        <div class="bars">${row(T('res_align', 'Alignment'), r.align ?? score)}${row(T('res_mould', 'Moulding'), r.mould ?? score)}${row(T('res_straps', 'Straps'), r.straps ?? score)}</div>
        <div class="foot">${icon('check')}<span>${esc(T('res_cms', 'Distal CMS intact'))}</span>${r.pressure ? `<span class="warn">${esc(T('res_press', '%s pressure point(s)', r.pressure))}</span>` : ''}</div>`;
      this.resEl.hidden = false;
      this.cmsEl.hidden = true;
      this.pp.complete({
        title: T('done_title', 'Splint secured'),
        text: o.msg || T('done_text', 'The limb is held above and below the break.'),
        label: T('done', 'Done'), onDone: () => this.done(),
      });
    },

    done() {
      NZA.post(`${APP}:done`, {});
      if (!NZA.inGame) NZA.close(APP);
    },

    /* ─────────────── frame loop ─────────────── */
    loop(now) {
      this.raf = 0;
      const S = this.S;
      if (!S || !S.active) return;
      const dt = Math.min(0.05, (now - (this.last || now)) / 1000);
      this.last = now;
      if (this.previewTick) this.previewTick(now, dt);
      this.update(now, dt);
      this.draw(now);
      this.raf = requestAnimationFrame(this.loop);
    },

    update(now, dt) {
      const S = this.S, t = this.tune;
      const f = this.frame();
      this.hintEl.hidden = !!f;
      if (!f) { this.hintEl.textContent = T('no_view', 'Turn the camera until you can see the limb.'); return; }
      if (!S.pose0) { S.pose = this.initialPose(f); S.pose0 = Object.assign({}, S.pose); }
      const fine = this.shift ? t.fine : 1;

      if (S.step === 1 && !S.locked) {
        const h = this.held;
        let phi = S.pose.phi;
        const rs = t.rotateSpeed * Math.PI / 180 * fine * dt;
        if (h.has('rotL')) phi -= rs;
        if (h.has('rotR')) phi += rs;
        let C = this.geom(f, S.pose).C;
        const ns = t.nudgeSpeed * f.L * fine * dt;
        if (h.has('up')) C = add(C, v(0, -ns));
        if (h.has('down')) C = add(C, v(0, ns));
        if (h.has('left')) C = add(C, v(-ns, 0));
        if (h.has('right')) C = add(C, v(ns, 0));
        if (h.size) { S.pose = this.toPose(f, C, phi); S.moved = true; }
        S.pose.phi = Math.atan2(Math.sin(S.pose.phi), Math.cos(S.pose.phi));
        const g = this.geom(f, S.pose);
        S.err.p = len(sub(g.Sp, f.Tp)) / f.L;
        S.err.d = len(sub(g.Sd, f.Td)) / f.L;
        S.err.a = Math.abs(S.pose.phi) * 180 / Math.PI;
        const ap = S.err.p < t.tolerance, ad = S.err.d < t.tolerance;
        if (ap !== S.aligned.p || ad !== S.aligned.d) {
          if ((ap && !S.aligned.p) || (ad && !S.aligned.d)) NZA.audio.click(990);
          S.aligned.p = ap; S.aligned.d = ad;
          this.pp.set({ stats: this.stats1() });
        }
        const steady = !S.drag && this.held.size === 0;
        if (ap && ad && steady && S.moved) S.alignHold += dt; else S.alignHold = 0;
        if (S.alignHold >= t.lockHold) this.lockSplint();
      } else if (S.step === 1 && S.lockAnim) {
        const k = easeOut((now - S.lockAnim.t0) / 280);
        const a = S.lockAnim.from;
        S.pose = { cu: lerp(a.cu, 0, k), cv: lerp(a.cv, 0, k), phi: lerp(a.phi, 0, k) };
      }

      if (S.step === 2 && S.press >= 0) {
        const pt = S.points[S.press];
        pt.f += dt / t.mouldSeconds * (this.shift ? 0.45 : 1);
        this.checkTight(pt);
        if (!this._s2 || now - this._s2 > 120) { this._s2 = now; this.pp.set({ stats: this.stats2() }); }
      }
      S.points.forEach(p => { if (p.pop > 0) p.pop = Math.max(0, p.pop - dt * 2.5); });

      if (S.step === 3) {
        S.straps.forEach(s => {
          if (s.state === 'wrap') { s.anim += dt / 0.38; if (s.anim >= 1) { s.anim = 1; s.state = 'sweep'; s.ph = 0; } }
          if (s.state === 'sweep') {
            s.ph += dt / t.strapPeriod;
            s.tension = 0.5 - 0.5 * Math.cos(s.ph * Math.PI * 2);
            if (!this._s3 || now - this._s3 > 90) { this._s3 = now; this.pp.set({ stats: this.stats3() }); }
          }
        });
        this.cmsTick(now);
      }
    },

    /* ─────────────── drawing ─────────────── */
    draw(now) {
      const cv = this.cv, c = this.ctx;
      const { w, h } = NZA.fitCanvas(cv);
      c.setTransform(1, 0, 0, 1, 0, 0);
      c.clearRect(0, 0, w, h);
      const S = this.S;
      const f = this.frame();
      const U = h / 1080;
      this.U = U;
      const tags = {};
      if (!f) { this.syncTags(tags); return; }
      const g = this.geom(f, S.pose);
      const tol = this.tune.tolerance * f.L;

      // joint targets (step 1) / limb guide
      if (S.step === 1) {
        c.save();
        c.setLineDash([5 * U, 5 * U]);
        c.lineWidth = 1.2 * U;
        c.strokeStyle = 'rgba(255,255,255,.28)';
        c.beginPath(); c.moveTo(f.Tp.x, f.Tp.y); c.lineTo(f.Td.x, f.Td.y); c.stroke();
        c.restore();
        [['p', f.Tp, S.aligned.p], ['d', f.Td, S.aligned.d]].forEach(([k, pt, ok]) => this.drawTarget(pt, tol, ok, now));
      }

      this.drawSplint(f, g, now);

      if (S.step === 1 && !S.locked) {
        // end connectors
        [[g.Sp, f.Tp, S.aligned.p], [g.Sd, f.Td, S.aligned.d]].forEach(([a, b, ok]) => {
          c.save();
          c.strokeStyle = ok ? 'rgba(47,224,208,.9)' : 'rgba(255,255,255,.55)';
          c.lineWidth = 1.4 * U; c.setLineDash([3 * U, 4 * U]);
          c.beginPath(); c.moveTo(a.x, a.y); c.lineTo(b.x, b.y); c.stroke();
          c.setLineDash([]);
          c.fillStyle = ok ? COL.tealHi : '#fff';
          c.beginPath(); c.arc(a.x, a.y, 3.6 * U, 0, Math.PI * 2); c.fill();
          c.restore();
        });
        // drag handle
        const hd = g.C;
        const r = 13 * U;
        c.save();
        c.shadowColor = 'rgba(0,0,0,.5)'; c.shadowBlur = 8 * U;
        c.fillStyle = S.drag ? 'rgba(8,175,162,.45)' : 'rgba(8,175,162,.22)';
        c.strokeStyle = COL.teal; c.lineWidth = 2.2 * U;
        c.beginPath(); c.arc(hd.x, hd.y, r, 0, Math.PI * 2); c.fill(); c.stroke();
        c.shadowBlur = 0;
        if (S.alignHold > 0) {
          c.strokeStyle = COL.tealHi; c.lineWidth = 3 * U;
          c.beginPath(); c.arc(hd.x, hd.y, r + 6 * U, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * clamp(S.alignHold / this.tune.lockHold, 0, 1)); c.stroke();
        }
        c.restore();
        tags.drag = { at: hd, label: S.aligned.p && S.aligned.d ? T('tag_hold', 'Hold steady') : T('tag_drag', 'Drag splint'), tone: 'teal', off: r + 10 * U };
        const away = mul(f.n, this.limbSide(f));
        tags.prox = { at: f.Tp, label: T('proximal', 'Proximal end'), tone: S.aligned.p ? 'ok' : '', off: tol + 8 * U, dir: away };
        tags.dist = { at: f.Td, label: T('distal', 'Distal end'), tone: S.aligned.d ? 'ok' : '', off: tol + 8 * U, dir: away };
      }

      if (S.step === 2) this.drawMould(f, g, now, tags);
      if (S.step === 3) this.drawStraps(f, g, now, tags);
      this.syncTags(tags);
      if (S.step === 3 && !this.cmsEl.hidden) {
        const cp = this.cmsPos(f, g);
        const side = cp.x > w * 0.62 ? -1 : 1;
        this.cmsEl.style.left = `${(cp.x / w) * 100}%`;
        this.cmsEl.style.top = `${(cp.y / h) * 100}%`;
        this.cmsEl.classList.toggle('flip', side < 0);
      }
    },

    drawTarget(pt, r, ok, now) {
      const c = this.ctx, U = this.U;
      c.save();
      const pulse = 0.5 + 0.5 * Math.sin(now / 320);
      c.fillStyle = ok ? 'rgba(8,175,162,.18)' : 'rgba(255,255,255,.06)';
      c.beginPath(); c.arc(pt.x, pt.y, r, 0, Math.PI * 2); c.fill();
      c.setLineDash(ok ? [] : [4 * U, 4 * U]);
      c.lineDashOffset = -now / 60;
      c.lineWidth = (ok ? 2.4 : 1.8) * U;
      c.strokeStyle = ok ? COL.tealHi : `rgba(255,255,255,${0.65 + pulse * 0.3})`;
      c.shadowColor = 'rgba(0,0,0,.6)'; c.shadowBlur = 6 * U;
      c.beginPath(); c.arc(pt.x, pt.y, r, 0, Math.PI * 2); c.stroke();
      c.setLineDash([]);
      c.fillStyle = ok ? COL.tealHi : '#fff';
      c.beginPath(); c.arc(pt.x, pt.y, 2.6 * U, 0, Math.PI * 2); c.fill();
      c.restore();
    },

    // half width profile of the tray along t (0 proximal .. 1 distal)
    profile(t) {
      const capP = 0.05, capD = this.kind === 'leg' ? 0.045 : 0.04;
      let k = 1;
      if (t < capP) { const q = 1 - t / capP; k = Math.sqrt(Math.max(0, 1 - q * q)); }
      if (t > 1 - capD) { const q = (t - (1 - capD)) / capD; k = Math.min(k, Math.sqrt(Math.max(0, 1 - q * q))); }
      let base = 1;
      if (this.kind === 'leg') base = 1 + 0.22 * smooth(0.74, 0.88, t) - 0.08 * smooth(0.9, 1, t);  // heel cup + foot plate
      else base = 1 - 0.1 * smooth(0.3, 0.6, t);                                                   // forearm taper
      return base * k;
    },
    bulge(g, x) {
      const S = this.S;
      if (S.step < 2) return g.W * 0.07;
      let b = 0;
      const sig = g.H * 2 * 0.075;
      S.points.forEach(pt => {
        const px = -g.H + pt.t * 2 * g.H;
        const gap = Math.max(0, 1 - pt.f / this.tune.mouldZone[0]);
        b += gap * g.W * 0.12 * Math.exp(-(((x - px) / sig) ** 2));
      });
      return b;
    },
    traySide(g, sign, scale, withBulge) {
      const N = 64, out = [];
      for (let i = 0; i <= N; i++) {
        const t = i / N;
        const x = -g.H + t * 2 * g.H;
        const hw = g.W / 2 * this.profile(t) * scale + (withBulge ? this.bulge(g, x) : 0);
        out.push(this.world(g, x, sign * hw));
      }
      return out;
    },
    pathTray(g, scale, withBulge) {
      const c = this.ctx;
      const a = this.traySide(g, -1, scale, withBulge), b = this.traySide(g, 1, scale, withBulge).reverse();
      c.beginPath();
      a.concat(b).forEach((p, i) => (i ? c.lineTo(p.x, p.y) : c.moveTo(p.x, p.y)));
      c.closePath();
    },

    drawSplint(f, g, now) {
      const c = this.ctx, U = this.U, S = this.S;
      const aligned = S.step === 1 ? (S.aligned.p && S.aligned.d) : true;
      const ghost = S.step >= 2;
      c.save();
      // drop shadow
      c.shadowColor = 'rgba(0,0,0,.55)'; c.shadowBlur = 16 * U; c.shadowOffsetY = 4 * U;
      this.pathTray(g, 1, true);
      const gr = c.createLinearGradient(this.world(g, 0, -g.W / 2).x, this.world(g, 0, -g.W / 2).y, this.world(g, 0, g.W / 2).x, this.world(g, 0, g.W / 2).y);
      const a0 = ghost ? 0.16 : 0.24, a1 = ghost ? 0.30 : 0.42;
      gr.addColorStop(0, `rgba(226,238,240,${a0})`);
      gr.addColorStop(0.5, `rgba(245,250,250,${a1})`);
      gr.addColorStop(1, `rgba(214,226,229,${a0})`);
      c.fillStyle = gr; c.fill();
      c.shadowColor = 'transparent';
      // foam channel
      this.pathTray(g, 0.56, false);
      c.fillStyle = ghost ? 'rgba(8,175,162,.10)' : 'rgba(8,175,162,.16)';
      c.fill();
      c.strokeStyle = 'rgba(255,255,255,.28)'; c.lineWidth = 1 * U; c.stroke();
      // outline
      this.pathTray(g, 1, true);
      c.lineWidth = 2.2 * U;
      c.strokeStyle = aligned && S.step === 1 ? COL.tealHi : 'rgba(255,255,255,.92)';
      if (aligned && S.step === 1) { c.shadowColor = 'rgba(47,224,208,.7)'; c.shadowBlur = 12 * U; }
      c.stroke();
      c.shadowBlur = 0;
      // ruler ticks along one edge (every 5 cm when the limb length is known)
      const segLen = Number(this.d.segLen) || 0;
      if (segLen > 0.05) {
        const metres = segLen * (1 + this.tune.extProx + this.tune.extDist);
        const pxPerCm = (2 * g.H) / (metres * 100);
        if (pxPerCm * 5 > 6 * U) {
          c.strokeStyle = 'rgba(255,255,255,.55)'; c.lineWidth = 1 * U;
          for (let cm = 5; cm < metres * 100 - 2; cm += 5) {
            const x = -g.H + cm * pxPerCm;
            const big = cm % 10 === 0;
            const y0 = -g.W / 2 * this.profile((x + g.H) / (2 * g.H)) * 0.93;
            const p0 = this.world(g, x, y0), p1 = this.world(g, x, y0 + (big ? 7 : 4) * U);
            c.beginPath(); c.moveTo(p0.x, p0.y); c.lineTo(p1.x, p1.y); c.stroke();
          }
          // printed length
          const mid = this.world(g, -g.H * 0.55, g.W * 0.27);
          c.save();
          c.translate(mid.x, mid.y);
          let ang = Math.atan2(g.s.y, g.s.x);
          if (ang > Math.PI / 2 || ang < -Math.PI / 2) ang += Math.PI;
          c.rotate(ang);
          c.font = `600 ${Math.max(9, 10.5 * U)}px "JetBrains Mono", monospace`;
          c.fillStyle = 'rgba(255,255,255,.62)'; c.textAlign = 'center'; c.textBaseline = 'middle';
          c.fillText(`${Math.round(metres * 100)} CM · NZ`, 0, 0);
          c.restore();
        }
      }
      // arm splint palm roll / leg foot plate detail
      if (this.kind === 'arm') {
        const pr = this.world(g, g.H - g.W * 0.42, 0);
        c.beginPath(); c.ellipse(pr.x, pr.y, g.W * 0.44, g.W * 0.34, Math.atan2(g.s.y, g.s.x), 0, Math.PI * 2);
        c.fillStyle = 'rgba(8,175,162,.20)'; c.fill();
        c.strokeStyle = 'rgba(255,255,255,.6)'; c.lineWidth = 1.2 * U; c.stroke();
      } else {
        const a = this.world(g, g.H * 0.78, -g.W * 0.48), b = this.world(g, g.H * 0.78, g.W * 0.48);
        c.strokeStyle = 'rgba(255,255,255,.45)'; c.lineWidth = 1.2 * U;
        c.beginPath(); c.moveTo(a.x, a.y); c.lineTo(b.x, b.y); c.stroke();
      }
      c.restore();
    },

    drawMould(f, g, now, tags) {
      const c = this.ctx, U = this.U, S = this.S;
      const r = Math.max(9 * U, Math.min(g.W * 0.26, 17 * U));
      const z = this.tune.mouldZone;
      let next = -1;
      S.points.forEach((pt, i) => { if (next < 0 && !pt.done) next = i; });
      S.points.forEach((pt, i) => {
        const p = this.world(g, -g.H + pt.t * 2 * g.H, 0);
        // gap glow on both edges
        if (!pt.done) {
          const gap = 1 - pt.f / z[0];
          [-1, 1].forEach(sg => {
            const e = this.world(g, -g.H + pt.t * 2 * g.H, sg * (g.W / 2 * this.profile(pt.t) + this.bulge(g, -g.H + pt.t * 2 * g.H)));
            c.fillStyle = `rgba(229,165,10,${0.18 + 0.32 * gap})`;
            c.beginPath(); c.arc(e.x, e.y, (4 + 6 * gap) * U, 0, Math.PI * 2); c.fill();
          });
        }
        // pad
        if (pt.pad && pt.padded) {
          c.save();
          c.translate(p.x, p.y); c.rotate(Math.atan2(g.s.y, g.s.x));
          c.fillStyle = 'rgba(255,255,255,.28)';
          const pw = g.W * 0.62, ph = g.H * 0.11;
          c.beginPath(); c.roundRect ? c.roundRect(-ph / 2, -pw / 2, ph, pw, 4 * U) : c.rect(-ph / 2, -pw / 2, ph, pw); c.fill();
          c.restore();
        }
        const pop = 1 + pt.pop * 0.35;
        c.save();
        c.shadowColor = 'rgba(0,0,0,.6)'; c.shadowBlur = 6 * U;
        c.fillStyle = pt.tight ? 'rgba(229,165,10,.35)' : pt.done ? 'rgba(8,175,162,.4)' : 'rgba(12,13,16,.72)';
        c.beginPath(); c.arc(p.x, p.y, r * pop, 0, Math.PI * 2); c.fill();
        c.shadowBlur = 0;
        // zone arc
        const a0 = -Math.PI / 2;
        c.lineWidth = 3.4 * U;
        c.strokeStyle = 'rgba(255,255,255,.12)';
        c.beginPath(); c.arc(p.x, p.y, r * pop, 0, Math.PI * 2); c.stroke();
        c.strokeStyle = 'rgba(8,175,162,.45)';
        c.beginPath(); c.arc(p.x, p.y, r * pop + 4.5 * U, a0 + z[0] * Math.PI * 2, a0 + z[1] * Math.PI * 2 - 0.02); c.stroke();
        c.strokeStyle = pt.tight ? COL.amberHi : pt.done ? COL.tealHi : '#fff';
        c.beginPath(); c.arc(p.x, p.y, r * pop, a0, a0 + clamp(pt.f, 0, 1) * Math.PI * 2); c.stroke();
        // glyph
        c.fillStyle = pt.done ? (pt.tight ? COL.amberHi : COL.tealHi) : '#fff';
        c.font = `700 ${Math.round(10 * U)}px Lexend, sans-serif`;
        c.textAlign = 'center'; c.textBaseline = 'middle';
        c.fillText(pt.tight ? '!' : pt.done ? '✓' : pt.pad && !pt.padded ? 'P' : String(i + 1), p.x, p.y + 0.5 * U);
        c.restore();
        if (i === next && S.press < 0) {
          const ring = r + 10 * U + Math.sin(now / 220) * 2 * U;
          c.save(); c.strokeStyle = 'rgba(255,255,255,.55)'; c.lineWidth = 1.4 * U; c.setLineDash([3 * U, 3 * U]);
          c.beginPath(); c.arc(p.x, p.y, ring, 0, Math.PI * 2); c.stroke(); c.restore();
          tags.mould = { at: p, label: pt.pad && !pt.padded ? T('tag_pad', 'Pad & mould') : T('tag_mould', 'Mould here'), tone: 'teal', off: ring + 6 * U, dir: mul(g.m, this.tagSide(g)) };
        }
      });
    },

    drawStraps(f, g, now, tags) {
      const c = this.ctx, U = this.U, S = this.S;
      const z = this.tune.strapZone;
      const thick = Math.max(7 * U, g.H * 2 * 0.045);
      let next = -1;
      S.straps.forEach((s, i) => { if (next < 0 && s.state === 'open') next = i; });
      S.straps.forEach((s, i) => {
        const x = -g.H + s.t * 2 * g.H;
        const hw = g.W / 2 * this.profile(s.t) * 1.12;
        const ang = Math.atan2(g.s.y, g.s.x);
        const p = this.world(g, x, 0);
        c.save();
        c.translate(p.x, p.y); c.rotate(ang);
        if (s.state === 'open') {
          c.setLineDash([4 * U, 3 * U]);
          c.strokeStyle = i === next ? 'rgba(255,255,255,.9)' : 'rgba(255,255,255,.45)'; c.lineWidth = 1.4 * U;
          c.strokeRect(-thick / 2, -hw, thick, hw * 2);
        } else {
          const k = s.state === 'wrap' ? easeOut(s.anim) : 1;
          const tone = s.state === 'locked' ? (s.tight ? COL.red : s.loose ? COL.amber : COL.teal) : '#cfd6d8';
          c.shadowColor = 'rgba(0,0,0,.55)'; c.shadowBlur = 6 * U;
          c.fillStyle = 'rgba(18,22,24,.94)';
          c.fillRect(-thick / 2, -hw, thick, hw * 2 * k);
          c.shadowBlur = 0;
          // webbing lines
          c.strokeStyle = 'rgba(255,255,255,.08)'; c.lineWidth = 1 * U;
          for (let yy = -hw + 4 * U; yy < -hw + hw * 2 * k; yy += 4 * U) { c.beginPath(); c.moveTo(-thick / 2, yy); c.lineTo(thick / 2, yy); c.stroke(); }
          c.strokeStyle = tone; c.lineWidth = 1.6 * U;
          c.strokeRect(-thick / 2, -hw, thick, hw * 2 * k);
          if (k >= 1) {
            // buckle
            c.fillStyle = tone;
            c.fillRect(-thick / 2 - 2 * U, hw - thick * 0.9, thick + 4 * U, thick * 0.9);
            c.fillStyle = 'rgba(0,0,0,.45)';
            c.fillRect(-thick / 2 + 1.5 * U, hw - thick * 0.62, thick - 3 * U, thick * 0.3);
          }
          if (s.state === 'locked' && s.tight && S.cms.state === 'bad') {
            c.strokeStyle = `rgba(229,72,77,${0.5 + 0.5 * Math.sin(now / 160)})`; c.lineWidth = 3 * U;
            c.strokeRect(-thick / 2 - 4 * U, -hw - 4 * U, thick + 8 * U, hw * 2 + 8 * U);
          }
        }
        c.restore();
        // tension gauge beside the strap
        if (s.state === 'sweep') {
          const side = this.tagSide(g);
          const base = this.world(g, x, side * (hw + 18 * U));
          const gh = Math.max(64 * U, hw * 1.6), gw = 9 * U;
          c.save();
          c.translate(base.x, base.y);
          c.fillStyle = 'rgba(12,13,16,.85)'; c.strokeStyle = 'rgba(255,255,255,.14)'; c.lineWidth = 1 * U;
          c.beginPath(); c.roundRect ? c.roundRect(-gw / 2 - 4 * U, -gh / 2 - 4 * U, gw + 8 * U, gh + 8 * U, 6 * U) : c.rect(-gw / 2 - 4 * U, -gh / 2 - 4 * U, gw + 8 * U, gh + 8 * U);
          c.fill(); c.stroke();
          c.fillStyle = 'rgba(255,255,255,.1)'; c.fillRect(-gw / 2, -gh / 2, gw, gh);
          const yOf = tv => gh / 2 - tv * gh;
          c.fillStyle = 'rgba(8,175,162,.35)'; c.fillRect(-gw / 2, yOf(z[1]), gw, (z[1] - z[0]) * gh);
          c.fillStyle = 'rgba(229,72,77,.35)'; c.fillRect(-gw / 2, -gh / 2, gw, (1 - this.tune.strapTight) * gh);
          const ny = yOf(s.tension);
          const inZone = s.tension >= z[0] && s.tension <= z[1];
          c.fillStyle = s.tension > this.tune.strapTight ? COL.redHi : inZone ? COL.tealHi : '#fff';
          c.fillRect(-gw / 2 - 4 * U, ny - 1.6 * U, gw + 8 * U, 3.2 * U);
          c.restore();
          tags.tension = { at: base, label: inZone ? T('tag_lock', 'Click to lock') : T('tag_tension', 'Tension'), tone: inZone ? 'teal' : '', off: gw + 12 * U, dir: mul(g.m, side) };
        }
        if (i === next && S.sweeping < 0) {
          tags.strap = { at: this.world(g, x, this.tagSide(g) * hw), label: T('tag_strap', 'Strap %s', i + 1), tone: 'teal', off: 12 * U, dir: mul(g.m, this.tagSide(g)) };
        }
      });
      // CMS target
      if (S.cms.state === 'ready' || S.cms.state === 'bad' || S.cms.state === 'checking' || S.cms.state === 'ok') {
        const cp = this.cmsPos(f, g);
        const r = 15 * U + (S.cms.state === 'ready' ? Math.sin(now / 200) * 2 * U : 0);
        c.save();
        c.shadowColor = 'rgba(0,0,0,.6)'; c.shadowBlur = 8 * U;
        c.fillStyle = S.cms.state === 'bad' ? 'rgba(229,72,77,.25)' : 'rgba(8,175,162,.22)';
        c.strokeStyle = S.cms.state === 'bad' ? COL.red : COL.tealHi; c.lineWidth = 2.2 * U;
        c.beginPath(); c.arc(cp.x, cp.y, r, 0, Math.PI * 2); c.fill(); c.stroke();
        c.restore();
        if (S.cms.state === 'ready' || S.cms.state === 'bad') {
          tags.cms = { at: cp, label: S.cms.state === 'bad' ? T('tag_recheck', 'Check again') : T('tag_cms', 'Check CMS'), tone: S.cms.state === 'bad' ? 'red' : 'teal', off: r + 8 * U };
        }
      }
    },

    // which side of the limb has room for labels (away from the body)
    limbSide(f) {
      const core = this.anc.core;
      if (core && core.visible !== false) {
        const cp = v(core.x * this.cv.width, core.y * this.cv.height);
        return dot(sub(cp, f.M), f.n) > 0 ? -1 : 1;
      }
      return 1;
    },
    // which side of the splint has room for labels (away from the body)
    tagSide(g) {
      const core = this.anc.core;
      if (core && core.visible !== false) {
        const cp = v(core.x * this.cv.width, core.y * this.cv.height);
        return dot(sub(cp, g.C), g.m) > 0 ? -1 : 1;
      }
      return 1;
    },

    /* DOM label pills that follow canvas points */
    syncTags(want) {
      const W = this.cv.width, H = this.cv.height;
      Object.keys(this.tags).forEach(k => { if (!want[k]) { this.tags[k].el.remove(); delete this.tags[k]; } });
      Object.entries(want).forEach(([k, o]) => {
        let t = this.tags[k];
        if (!t) {
          t = { el: NZA.el('div', 'sp-tag') };
          this.tagsEl.appendChild(t.el);
          this.tags[k] = t;
        }
        if (t.label !== o.label || t.tone !== o.tone) {
          t.el.innerHTML = `<span class="lbl ${o.tone || ''}">${o.tone === 'ok' ? icon('check') : ''}${esc(o.label)}</span>`;
          t.label = o.label; t.tone = o.tone;
        }
        let ux = 1, uy = 0;
        if (o.dir) { const l = len(o.dir) || 1; ux = o.dir.x / l; uy = o.dir.y / l; }
        const x = o.at.x + ux * (o.off || 0), y = o.at.y + uy * (o.off || 0);
        t.el.style.left = `${(x / W) * 100}%`;
        t.el.style.top = `${(y / H) * 100}%`;
        t.el.classList.toggle('left', ux < -0.35);
        t.el.classList.toggle('mid', Math.abs(ux) <= 0.35);
        t.el.classList.toggle('up', Math.abs(ux) <= 0.35 && uy < 0);
      });
    },

    /* ═════════════════════ MOBILITY HUD ═════════════════════ */
    hudShow(h) {
      this.hud = Object.assign(this.hud || {}, h);
      const o = this.hud;
      const el = this.hudEl;
      const kind = o.kind || 'chair';
      const ic = kind === 'crutch' ? 'crutch' : 'wheelchair';
      const speed = Math.max(0, Number(o.speed) || 0);
      const max = Math.max(0.1, Number(o.max) || 2);
      const frac = clamp(Math.abs(speed) / max, 0, 1);
      const slope = Number(o.slope) || 0;
      const keys = (o.keys || []).map(k => `<span class="hk">${(k.keys || []).map(x => `<kbd>${esc(x)}</kbd>`).join('')}<em>${esc(k.label)}</em></span>`).join('');
      const showGauge = kind !== 'crutch';
      el.className = `sp-hud nza-hud kind-${kind} ${o.state ? `st-${o.state}` : ''}`;
      el.innerHTML = `
        <div class="ic">${icon(ic)}</div>
        <div class="tx"><b>${esc(o.title || '')}</b><small>${esc(o.sub || '')}</small></div>
        ${showGauge ? `<div class="gauge"><svg viewBox="0 0 44 44"><circle cx="22" cy="22" r="18" class="bg"/><circle cx="22" cy="22" r="18" class="fg" style="stroke-dasharray:${(frac * 0.75 * 113.1).toFixed(1)} 113.1"/></svg><span><b>${(Math.abs(speed) * 3.6).toFixed(1)}</b><i>${esc(T('kmh', 'km/h'))}</i></span></div>
        <div class="slope ${Math.abs(slope) >= 8 ? 'steep' : ''}"><i style="transform:rotate(${clamp(-slope, -30, 30)}deg)"></i><span>${slope > 0.5 ? '▲' : slope < -0.5 ? '▼' : ''}${Math.abs(Math.round(slope))}°</span></div>` : ''}
        ${o.blocked ? `<span class="chipx sm amber">${esc(o.blocked)}</span>` : ''}
        <div class="keys">${keys}</div>`;
      el.hidden = false;
    },
    hudHide() {
      this.hud = null;
      this.hudEl.hidden = true;
    },

    /* ═════════════════════ PREVIEW ═════════════════════ */
    preview(stage = 'place') {
      LOC = {};
      const P = previewScene(this);
      const d = {
        mode: 'proc', region: 'r_lower_leg', regionLabel: 'Right lower leg', limb: 'leg', device: 'leg', deviceLabel: 'Posterior leg splint',
        fracture: { kind: 'closed', bone: 'tibia', displaced: true, angle: 14 }, open: false, segLen: 0.43, pulse: 'present',
        keys: { rotateLeft: 'KeyQ', rotateRight: 'KeyE', reset: 'KeyX', set: 'Space' },
      };
      NZA.mock(`${APP}:finish`, r => ({ ok: true, outcome: { score: r.score, grade: r.score >= 90 ? 'S' : r.score >= 80 ? 'A' : 'B', msg: 'Right lower leg splinted · pain easing' } }));
      if (stage.startsWith('hud')) {
        this.procStop();
        P.stop();
        const hudDemo = {
          'hud-chair': { kind: 'chair', title: 'Wheelchair', sub: 'Driving · flat', speed: 1.42, max: 1.9, slope: -4, keys: [{ keys: ['W', 'S'], label: 'Drive' }, { keys: ['A', 'D'], label: 'Turn' }, { keys: ['F'], label: 'Stand up' }] },
          'hud-push': { kind: 'push', title: 'Pushing wheelchair', sub: 'Michael Garcia', speed: 1.1, max: 1.9, slope: 6, keys: [{ keys: ['G'], label: 'Let go' }] },
          'hud-crutch': { kind: 'crutch', title: 'Crutches', sub: 'Walking · no sprinting', keys: [{ keys: ['K'], label: 'Put away' }] },
        }[stage] || {};
        NZA.demo(APP, { mode: 'hud', hud: hudDemo });
        return;
      }
      NZA.demo(APP, d);
      P.start();
      const S = this.S;
      const at = (fn, ms) => setTimeout(() => { if (this.S === S) fn(); }, ms);
      if (stage === 'aligned' || stage === 'mould' || stage === 'strap' || stage === 'cms' || stage === 'cmsbad' || stage === 'done') {
        at(() => {
          S.moved = true;
          if (stage === 'aligned') { S.pose = { cu: 0.012, cv: 0.02, phi: 0.03 }; S.alignHold = -99; return; }
          S.pose = { cu: 0.01, cv: 0.01, phi: 0.02 };
          this.lockSplint();
        }, 120);
      }
      if (stage === 'mould') {
        at(() => {
          S.points.forEach((p, i) => { if (i < 2) { p.f = i ? 0.9 : 0.86; p.done = true; p.padded = p.pad; } });
          S.points[2].f = 0.46; S.press = -1;
          this.pp.set({ stats: this.stats2() });
        }, 900);
      }
      if (stage === 'strap' || stage === 'cms' || stage === 'cmsbad' || stage === 'done') {
        at(() => {
          S.points.forEach(p => { p.f = 0.88; p.done = true; p.padded = p.pad; });
          this.checkMouldDone();
        }, 900);
      }
      if (stage === 'strap') {
        at(() => {
          const s0 = S.straps[0]; s0.state = 'locked'; s0.tension = 0.68; s0.quality = 96;
          const s1 = S.straps[1]; s1.state = 'sweep'; s1.anim = 1; s1.ph = 0.22; S.sweeping = 1;
          this.pp.set({ stats: this.stats3() });
        }, 1800);
      }
      if (stage === 'cms' || stage === 'cmsbad' || stage === 'done') {
        at(() => {
          S.straps.forEach((s, i) => { s.state = 'locked'; s.tension = stage === 'cmsbad' && i === 1 ? 0.93 : 0.66; s.quality = s.tension > 0.9 ? 30 : 94; s.tight = s.tension > 0.9; if (s.tight) S.tightEver += 1; });
          S.cms.state = 'ready';
          this.pp.set({ stats: this.stats3() });
        }, 1800);
        if (stage !== 'cms') at(() => this.cmsCheck(), 2000);
      }
    },
  };

  /* ─────────────── browser preview scene: a patient lying top-down ─────────────── */
  function previewScene(app) {
    if (app._scene) return app._scene;
    const host = document.createElement('canvas');
    host.className = 'sp-scene';
    document.body.prepend(host);
    const ctx = host.getContext('2d');
    // metres, patient supine, head up (+y); patient right side = screen left
    const J = {
      head: [0, 0.74], neck: [0, 0.6], chest: [0, 0.38], pelvis: [0, 0],
      rSh: [-0.21, 0.5], rEl: [-0.36, 0.25], rWr: [-0.47, 0.04], rHa: [-0.52, -0.05],
      lSh: [0.21, 0.5], lEl: [0.4, 0.3], lWr: [0.56, 0.16], lHa: [0.64, 0.12],
      rHip: [-0.1, -0.04], rKn: [-0.16, -0.47], rAn: [-0.19, -0.9], rToe: [-0.2, -1.03],
      lHip: [0.1, -0.04], lKn: [0.2, -0.46], lAn: [0.27, -0.88], lToe: [0.29, -1.01],
    };
    const cam = { focus: [-0.175, -0.68], scale: 820, rot: 0.04, tRot: 0.04, drag: null };
    const proj = p => {
      const W = host.width, H = host.height, s = cam.scale * (H / 1080);
      const x = p[0] - cam.focus[0], y = p[1] - cam.focus[1];
      const c = Math.cos(cam.rot), sn = Math.sin(cam.rot);
      return { x: W / 2 + (x * c - y * sn) * s, y: H / 2 - (x * sn + y * c) * s };
    };
    const capsule = (a, b, r0, r1, fill, edge) => {
      const A = proj(a), B = proj(b), s = cam.scale * (host.height / 1080);
      const d = { x: B.x - A.x, y: B.y - A.y }, l = Math.hypot(d.x, d.y) || 1, n = { x: -d.y / l, y: d.x / l };
      ctx.beginPath();
      ctx.moveTo(A.x + n.x * r0 * s, A.y + n.y * r0 * s);
      ctx.lineTo(B.x + n.x * r1 * s, B.y + n.y * r1 * s);
      ctx.arc(B.x, B.y, r1 * s, Math.atan2(n.y, n.x), Math.atan2(n.y, n.x) + Math.PI, true);
      ctx.lineTo(A.x - n.x * r0 * s, A.y - n.y * r0 * s);
      ctx.arc(A.x, A.y, r0 * s, Math.atan2(-n.y, -n.x), Math.atan2(-n.y, -n.x) + Math.PI, true);
      ctx.closePath();
      ctx.fillStyle = fill; ctx.fill();
      if (edge) { ctx.strokeStyle = edge; ctx.lineWidth = 1.2; ctx.stroke(); }
    };
    let noise = null;
    function floor() {
      const W = host.width, H = host.height;
      const g = ctx.createRadialGradient(W * 0.45, H * 0.4, 50, W * 0.5, H * 0.5, W * 0.8);
      g.addColorStop(0, '#8d8a83'); g.addColorStop(1, '#5b5954');
      ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
      if (!noise) {
        noise = document.createElement('canvas'); noise.width = noise.height = 256;
        const nc = noise.getContext('2d'), id = nc.createImageData(256, 256);
        for (let i = 0; i < id.data.length; i += 4) { const v0 = 110 + Math.random() * 60; id.data[i] = id.data[i + 1] = id.data[i + 2] = v0; id.data[i + 3] = 26; }
        nc.putImageData(id, 0, 0);
      }
      ctx.fillStyle = ctx.createPattern(noise, 'repeat'); ctx.fillRect(0, 0, W, H);
      // plank + expansion joints
      ctx.save();
      const a = proj([-0.9, -1.6]), b = proj([0.55, 1.2]);
      ctx.strokeStyle = 'rgba(40,38,34,.35)'; ctx.lineWidth = 3;
      for (let i = -6; i <= 6; i++) { const p0 = proj([i * 0.6, -3]), p1 = proj([i * 0.6, 3]); ctx.beginPath(); ctx.moveTo(p0.x, p0.y); ctx.lineTo(p1.x, p1.y); ctx.stroke(); }
      ctx.restore();
      void a; void b;
    }
    function body() {
      ctx.save();
      ctx.shadowColor = 'rgba(0,0,0,.45)'; ctx.shadowBlur = 26; ctx.shadowOffsetY = 8;
      const jeans = '#4d6587', jeansHi = '#5f7aa0', skin = '#c99a7b', shirt = '#9aa18f', vest = '#c8d24a', boot = '#6b4a2b';
      // legs
      capsule(J.lHip, J.lKn, 0.085, 0.066, jeans); capsule(J.lKn, J.lAn, 0.064, 0.05, jeans);
      capsule(J.rHip, J.rKn, 0.085, 0.066, jeans); capsule(J.rKn, J.rAn, 0.064, 0.05, jeansHi);
      capsule(J.lAn, J.lToe, 0.055, 0.045, boot); capsule(J.rAn, J.rToe, 0.055, 0.045, boot);
      // arms
      capsule(J.rSh, J.rEl, 0.06, 0.05, shirt); capsule(J.rEl, J.rWr, 0.048, 0.04, skin); capsule(J.rWr, J.rHa, 0.042, 0.04, skin);
      capsule(J.lSh, J.lEl, 0.06, 0.05, shirt); capsule(J.lEl, J.lWr, 0.048, 0.04, skin); capsule(J.lWr, J.lHa, 0.042, 0.04, skin);
      // torso
      capsule([0, 0.05], [0, 0.42], 0.17, 0.2, shirt);
      ctx.shadowBlur = 0; ctx.shadowOffsetY = 0;
      capsule([-0.1, 0.12], [-0.11, 0.44], 0.06, 0.07, vest); capsule([0.1, 0.12], [0.11, 0.44], 0.06, 0.07, vest);
      capsule([0, -0.02], [0, 0.04], 0.16, 0.16, '#5b4a38');
      // head
      capsule(J.neck, J.head, 0.055, 0.105, skin);
      capsule([0, 0.7], [0, 0.8], 0.1, 0.09, '#e0b62b');
      // shin bruise (fracture site)
      const m = proj([-0.18, -0.7]); const s = cam.scale * (host.height / 1080);
      const rg = ctx.createRadialGradient(m.x, m.y, 1, m.x, m.y, 0.06 * s);
      rg.addColorStop(0, 'rgba(110,40,60,.55)'); rg.addColorStop(1, 'rgba(110,40,60,0)');
      ctx.fillStyle = rg; ctx.beginPath(); ctx.arc(m.x, m.y, 0.06 * s, 0, Math.PI * 2); ctx.fill();
      ctx.restore();
    }
    let last = '';
    const sendAnchors = () => {
      const W = host.width, H = host.height;
      const f = p => { const q = proj(p); return { x: q.x / W, y: q.y / H, visible: true }; };
      const map = { prox: f(J.rKn), dist: f(J.rAn), cms: f(J.rToe), core: f(J.chest) };
      const key = JSON.stringify(map);
      if (key !== last) { last = key; app.anc = map; }
    };
    const onDown = e => { if (e.button === 2) cam.drag = { x: e.clientX, rot: cam.tRot }; };
    const onMove = e => { if (cam.drag) cam.tRot = cam.drag.rot + (e.clientX - cam.drag.x) / window.innerWidth * Math.PI; };
    const onUp = e => { if (e.button === 2) cam.drag = null; };
    const onWheel = e => { cam.scale = clamp(cam.scale * (e.deltaY > 0 ? 0.92 : 1.08), 380, 1500); };
    const scene = {
      start() {
        host.hidden = false;
        window.addEventListener('mousedown', onDown); window.addEventListener('mousemove', onMove);
        window.addEventListener('mouseup', onUp); window.addEventListener('wheel', onWheel);
        app.previewTick = () => {
          cam.rot += (cam.tRot - cam.rot) * 0.15;
          const dpr = window.devicePixelRatio || 1;
          const w = Math.round(window.innerWidth * dpr), h = Math.round(window.innerHeight * dpr);
          if (host.width !== w || host.height !== h) { host.width = w; host.height = h; }
          floor(); body(); sendAnchors();
        };
      },
      stop() { host.hidden = true; app.previewTick = null; },
    };
    app._scene = scene;
    return scene;
  }

  NZA.app(APP, A);
})();
