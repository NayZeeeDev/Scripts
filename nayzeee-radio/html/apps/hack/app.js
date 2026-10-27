/* ═══════════════════════════════════════════════════════════
   NAYZEEE RADIO · hack (focused)                                        apps/hack/app.js
   Jammer hack minigame (client/modules/jammers.lua). Our own design (SPEC §14, Rule A).

   Each stage: the jammer pushes a carrier (red trace) and you build a counter-signal
   (teal trace). Two dials shape it: PHASE (A/D, Q/E, ←/→, wheel or drag) and GAIN
   (W/S, ↑/↓, wheel or drag; SHIFT = fine). When both match, the counter cancels the
   carrier, the residual trace below goes flat and the null ring fills. Keep it there for
   the hold time to clear the stage. The carrier drifts (and jumps, on tougher units);
   drift, jumps and tolerance get harder every stage and with `difficulty`.
   Stages = bands, one shared clock = time. Everything random comes from `seed`, so the
   same attempt always gets the same puzzle (no re-rolling for an easier one).

   Lua → NUI
     open  { id, title, code?, label?, type?, bands 1..5, time (s), seed, difficulty? 1..5 }
           title "JX-90 · Heavy Jammer"; code / label are used when sent, else read from the
           title (or the type: pocket JX-10, case JX-40, heavy JX-90)
     close
   NUI → Lua
     hack:result { id, success, cancelled }
           posted once, after the result card has been up a moment. A success is never posted
           sooner than bands × 2.5 s + 0.4 s after the window opened (the server refuses
           faster ones). Esc posts { success = false, cancelled = true } and closes at once.
           Lua closes the window when it gets the result; if nothing closes it within 2.5 s
           the page closes itself (posts hack:close, which also releases focus).
   Strings: locales/en/windows.lua (ui.hk_*), English fallbacks inline for the preview.
   Sounds (NZR.sfx): key on dial detents, hack_tick while the null builds, toggle on a
   cleared stage, hack_ok / hack_fail on the result.
   ═══════════════════════════════════════════════════════════ */
(() => {
  const NZR = window.NZR;
  const { esc, t, icon, clamp } = NZR;
  const TAU = Math.PI * 2;
  const RAD = Math.PI / 180;
  const CODES = { pocket: 'JX-10', case: 'JX-40', heavy: 'JX-90' };
  const GAIN_MIN = 0.1, GAIN_MAX = 1.6;
  const CLEAR_PAUSE = 0.85;     // s between stages (the clock stops)
  const RESULT_MIN = 1.35;      // s the result card stays before the result is posted
  const num = (v, d) => { const n = Number(v); return Number.isFinite(n) ? n : d; };
  const wrap180 = d => ((d % 360) + 540) % 360 - 180;
  const norm360 = d => ((d % 360) + 360) % 360;
  const smooth = x => (x <= 0 ? 0 : x >= 1 ? 1 : x * x * (3 - 2 * x));
  const sfx = (name, opts) => { try { NZR.sfx.play(name, opts); } catch (_) { /* engine not ready */ } };

  /* ─────────────── seeded random (mulberry32) ─────────────── */
  function hashSeed(v) {
    if (typeof v === 'number' && Number.isFinite(v)) return (Math.floor(Math.abs(v)) >>> 0) || 0x9e3779b9;
    const s = String(v ?? 'nzr');
    let h = 2166136261;
    for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); }
    return (h >>> 0) || 0x9e3779b9;
  }
  function rng(seed) {
    let a = hashSeed(seed);
    return () => {
      a = (a + 0x6D2B79F5) >>> 0;
      let x = a;
      x = Math.imul(x ^ (x >>> 15), x | 1);
      x ^= x + Math.imul(x ^ (x >>> 7), x | 61);
      return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
    };
  }

  // carrier shapes: harmonic weights 1..5 (more texture on later stages)
  const PROFILES = [
    [1, 0, 0.1, 0, 0],
    [1, 0.3, 0, 0, 0],
    [1, 0, 0.32, 0, 0.12],
    [1, 0.24, 0.18, 0, 0.08],
    [1, -0.36, 0.14, -0.09, 0],
  ];

  /* ─────────────── the puzzle, from the seed ─────────────── */
  function makeStages(seed, n, diff) {
    const r = rng(seed);
    const d = diff - 1;
    const out = [];
    for (let s = 0; s < n; s++) {
      const prof = PROFILES[Math.min(PROFILES.length - 1, s + Math.floor(r() * 2) + (diff >= 4 ? 1 : 0))];
      const h = prof.map(w => w);
      const psi = h.map(() => r() * TAU);
      psi[0] = 0;
      const normH = h.reduce((a, w) => a + Math.abs(w), 0) || 1;
      const a0 = 0.55 + r() * 0.6;
      const phi0 = r() * 360;
      const kicks = [];
      if ((diff >= 2 && s >= 1) || diff >= 3) {
        let at = 2.4 + r() * 2.2;
        while (at < 180) {
          kicks.push({ at, mag: (r() < 0.5 ? -1 : 1) * (16 + r() * 14 + 4 * s + 2 * d) });
          at += Math.max(3.2, 5.2 - 0.5 * s - 0.3 * d) + r() * 3;
        }
      }
      const tol = clamp(0.24 - 0.022 * d - 0.03 * s, 0.1, 0.3);
      out.push({
        cycles: 2.2 + r() * 1.5 + s * 0.45,
        speed: 0.45 + r() * 0.35 + s * 0.08,
        h, psi, normH, a0, phi0, kicks,
        pAmp: 10 + 8 * s + 4 * d, pF1: 0.05 + r() * 0.05 + 0.02 * s, pF2: 0.13 + r() * 0.08 + 0.03 * s, p1: r() * TAU, p2: r() * TAU,
        aAmp: 0.06 + 0.035 * s + 0.02 * d, aF: 0.07 + r() * 0.06, p3: r() * TAU,
        tol,
        hold: 1.5 + 0.28 * d + 0.2 * s,
        startPhase: norm360(phi0 + (r() < 0.5 ? -1 : 1) * (75 + r() * 85)),
        startGain: 0,
        gainSide: r() < 0.5 ? -1 : 1, gainOff: 0.3 + r() * 0.3,
      });
      const st = out[s];
      st.drain = st.hold * 1.4;   // s for a full null ring to run dry once the match is lost
      st.startGain = clamp(st.a0 + st.gainSide * st.gainOff, GAIN_MIN + 0.05, GAIN_MAX - 0.05);
      if (Math.abs(st.startGain - st.a0) < 0.25) st.startGain = clamp(st.a0 - st.gainSide * st.gainOff, GAIN_MIN + 0.05, GAIN_MAX - 0.05);
    }
    return out;
  }

  // where the carrier sits at stage time tt
  function target(st, tt) {
    let ph = st.phi0 + st.pAmp * (0.6 * Math.sin(TAU * st.pF1 * tt + st.p1) + 0.4 * Math.sin(TAU * st.pF2 * tt + st.p2));
    let jumping = false;
    for (const k of st.kicks) {
      if (k.at > tt) break;
      const f = (tt - k.at) / 0.35;
      ph += k.mag * smooth(f);
      if (f < 2.4) jumping = true;
    }
    const amp = st.a0 * (1 + st.aAmp * Math.sin(TAU * st.aF * tt + st.p3));
    return { ph: norm360(ph), amp, jumping };
  }

  function shape(st, th) {
    let v = 0;
    for (let k = 0; k < st.h.length; k++) if (st.h[k]) v += st.h[k] * Math.sin((k + 1) * th + st.psi[k]);
    return v / st.normH;
  }

  /* ─────────────── markup ─────────────── */
  const dialSVG = kind => {
    const ticks = [];
    if (kind === 'phase') {
      for (let i = 0; i < 36; i++) {
        const a = i * 10 * RAD, mj = i % 9 === 0, r1 = mj ? 37 : 39.5, r2 = 43;
        ticks.push(`<line class="${mj ? 'mj' : ''}" x1="${(50 + r1 * Math.sin(a)).toFixed(2)}" y1="${(50 - r1 * Math.cos(a)).toFixed(2)}" x2="${(50 + r2 * Math.sin(a)).toFixed(2)}" y2="${(50 - r2 * Math.cos(a)).toFixed(2)}"/>`);
      }
      return `<svg viewBox="0 0 100 100"><g class="tk">${ticks.join('')}</g>
        <circle class="kb" cx="50" cy="50" r="30"/><circle class="kr" cx="50" cy="50" r="30"/>
        <g class="pt"><line x1="50" y1="24" x2="50" y2="36"/><circle cx="50" cy="12.5" r="2.6"/></g></svg>`;
    }
    for (let i = 0; i <= 24; i++) {
      const a = (-120 + i * 10) * RAD, mj = i % 6 === 0, r1 = mj ? 37 : 39.5, r2 = 43;
      ticks.push(`<line class="${mj ? 'mj' : ''}" x1="${(50 + r1 * Math.sin(a)).toFixed(2)}" y1="${(50 - r1 * Math.cos(a)).toFixed(2)}" x2="${(50 + r2 * Math.sin(a)).toFixed(2)}" y2="${(50 - r2 * Math.cos(a)).toFixed(2)}"/>`);
    }
    // 240° arc, r 47: starts lower left (-120°), clockwise
    const p = a => `${(50 + 47 * Math.sin(a * RAD)).toFixed(2)} ${(50 - 47 * Math.cos(a * RAD)).toFixed(2)}`;
    const arc = `M${p(-120)}A47 47 0 1 1 ${p(120)}`;
    return `<svg viewBox="0 0 100 100"><path class="tr" d="${arc}"/><path class="fl" d="${arc}" pathLength="100" stroke-dasharray="100" stroke-dashoffset="100"/><g class="tk">${ticks.join('')}</g>
      <circle class="kb" cx="50" cy="50" r="30"/><circle class="kr" cx="50" cy="50" r="30"/>
      <g class="pt"><line x1="50" y1="24" x2="50" y2="36"/></g></svg>`;
  };

  function hintsHTML() {
    const k = s => `<span class="nz-key">${esc(s)}</span>`;
    return `<span>${k('A')}${k('D')}${esc(t('ui.hk_k_phase', 'Phase'))}</span>
      <span>${k('W')}${k('S')}${esc(t('ui.hk_k_gain', 'Gain'))}</span>
      <span>${k('SHIFT')}${esc(t('ui.hk_k_fine', 'Fine'))}</span>
      <span>${k('ESC')}${esc(t('ui.hk_k_quit', 'Give up'))}</span>
      <span class="nz-sig"><span class="nz-mark xs"></span>NAYZEEE</span>`;
  }

  /* ─────────────── state ─────────────── */
  let app = null, root = null, card = null, cv = null, ctx = null;
  let raf = 0, last = 0;
  let S = null;                       // the running attempt
  const held = new Set();             // key codes held
  let shift = false;
  let assist = false;                 // preview only: tunes the dials by itself
  const q = sel => root.querySelector(sel);
  const RING_C = 2 * Math.PI * 17;

  function build() {
    root.innerHTML = `
      <div class="hk-wrap">
        <div class="hk-shell">
          <div class="hk-card nz-grain" data-shape="bevel">
            <i class="hk-br tl"></i><i class="hk-br tr"></i>
            <header class="hk-head">
              <div class="nz-mark sm"></div>
              <div class="hk-ttl"><b><span class="hk-code"></span><span class="hk-lab"></span></b><span class="hk-sub"></span></div>
              <div class="hk-clock"><svg viewBox="0 0 40 40"><circle class="b" cx="20" cy="20" r="17"/><circle class="f" cx="20" cy="20" r="17" stroke-dasharray="${RING_C.toFixed(2)}" stroke-dashoffset="0"/></svg><b>--</b><em>${esc(t('ui.hk_clock', 'left'))}</em></div>
            </header>
            <div class="hk-body">
              <ol class="hk-spine"></ol>
              <div class="hk-scope">
                <canvas></canvas>
                <span class="hk-lg a"><i class="sw red"></i>${esc(t('ui.hk_carrier', 'Jammer carrier'))}</span>
                <span class="hk-lg b"><i class="sw teal"></i>${esc(t('ui.hk_counter', 'Your counter'))}</span>
                <span class="hk-lg r"><i class="sw white"></i>${esc(t('ui.hk_residual', 'What gets through'))}</span>
                <span class="hk-jump">${icon('bolt')}${esc(t('ui.hk_jump', 'Carrier jumped'))}</span>
                <span class="hk-clear">${icon('check')}${esc(t('ui.hk_cleared', 'Carrier cancelled'))}</span>
              </div>
              <div class="hk-dials">
                <div class="hk-dial" data-k="phase">${dialSVG('phase')}<div class="rd"><em>${esc(t('ui.hk_phase', 'Phase'))}</em><b>0°</b></div></div>
                <div class="hk-dial" data-k="gain">${dialSVG('gain')}<div class="rd"><em>${esc(t('ui.hk_gain', 'Gain'))}</em><b>0%</b></div></div>
              </div>
            </div>
            <div class="hk-null">
              <div class="hk-hold"><svg viewBox="0 0 48 48"><circle class="b" cx="24" cy="24" r="20"/><circle class="f" cx="24" cy="24" r="20" pathLength="100" stroke-dasharray="100" stroke-dashoffset="100"/></svg><b>0</b></div>
              <div class="hk-nt"><b>${esc(t('ui.hk_hold', 'Hold the null'))}</b><span>${esc(t('ui.hk_hold_sub', 'Match phase and gain until the residual runs flat'))}</span></div>
              <div class="hk-res">
                <div class="rl"><em>${esc(t('ui.hk_res', 'Residual'))}</em><b>100%</b></div>
                <div class="hk-mtr"><span class="zone"></span><i></i><span class="mk"></span></div>
              </div>
            </div>
            <footer class="hk-foot nz-hints">${hintsHTML()}</footer>
            <div class="hk-result"></div>
          </div>
        </div>
      </div>`;
    card = q('.hk-card');
    cv = q('canvas');
    ctx = cv.getContext('2d');
    root.querySelectorAll('.hk-dial').forEach(bindDial);
  }

  /* ─────────────── dials: wheel + drag ─────────────── */
  function nudge(kind, steps, fine) {
    if (!S || S.phase !== 'play') return;
    if (kind === 'phase') S.phase360 = norm360(S.phase360 + steps * (fine ? 1 : 4));
    else S.gain = clamp(S.gain + steps * (fine ? 0.01 : 0.04), GAIN_MIN, GAIN_MAX);
  }
  function bindDial(el) {
    const kind = el.dataset.k;
    el.addEventListener('wheel', e => { e.preventDefault(); nudge(kind, e.deltaY < 0 ? 1 : -1, e.shiftKey); }, { passive: false });
    el.addEventListener('pointerdown', e => {
      if (e.button !== 0 || !S || S.phase !== 'play') return;
      e.preventDefault();
      el.classList.add('drag');
      let lx = e.clientX, ly = e.clientY;
      const mv = ev => {
        const z = NZR.zoom || 1;
        const d = ((ev.clientX - lx) - (ev.clientY - ly)) / z;
        lx = ev.clientX; ly = ev.clientY;
        if (!S || S.phase !== 'play') return;
        if (kind === 'phase') S.phase360 = norm360(S.phase360 + d * (ev.shiftKey ? 0.25 : 1.1));
        else S.gain = clamp(S.gain + d * (ev.shiftKey ? 0.0025 : 0.009), GAIN_MIN, GAIN_MAX);
      };
      const up = () => { el.classList.remove('drag'); window.removeEventListener('pointermove', mv); window.removeEventListener('pointerup', up); };
      window.addEventListener('pointermove', mv);
      window.addEventListener('pointerup', up);
    });
  }

  /* ─────────────── open / stages ─────────────── */
  function start(data) {
    const bands = clamp(Math.round(num(data.bands, 1)), 1, 5);
    const diff = clamp(Math.round(num(data.difficulty, bands)), 1, 5);
    const time = Math.max(5, num(data.time, 30));
    const title = String(data.title || '');
    const parts = title.split('·').map(s => s.trim()).filter(Boolean);
    const code = String(data.code || (parts.length > 1 ? parts[0] : '') || CODES[data.type] || 'JX');
    const label = String(data.label || (parts.length > 1 ? parts.slice(1).join(' · ') : title) || t('ui.hk_unit', 'Signal jammer'));
    S = {
      id: data.id, bands, diff, time, left: time, code, label,
      stages: makeStages(data.seed ?? data.id ?? 1, bands, diff),
      stage: 0, tt: 0, hold: 0, lastTick: 0, phase: 'play', pause: 0,
      phase360: 0, gain: 0.5, ease: null, done: false, posted: false,
      openedAt: performance.now(), detP: 0, detG: 0, clickAt: 0, results: [],
      err: 1, tgt: { ph: 0, amp: 1 }, jumpShown: 0,
    };
    const st0 = S.stages[0];
    S.phase360 = st0.startPhase; S.gain = st0.startGain;
    S.detP = Math.round(S.phase360 / 10); S.detG = Math.round(S.gain / 0.05);

    q('.hk-code').textContent = code;
    q('.hk-lab').textContent = label;
    card.className = 'hk-card nz-grain';
    card.classList.toggle('hard', diff >= 3);
    const res = q('.hk-result'); res.className = 'hk-result'; res.innerHTML = '';
    q('.hk-spine').innerHTML = S.stages.map((_, i) => `<li><i>${i + 1}</i></li>`).join('');
    q('.hk-spine').classList.toggle('one', bands === 1);
    stageUI();
    held.clear();
    loop(true);
  }

  function stageUI() {
    const st = S.stages[S.stage];
    q('.hk-sub').innerHTML = esc(t('ui.hk_stage', 'Cancel the carrier · stage {n} of {N}'))
      .replace('{n}', `<em>${S.stage + 1}</em>`).replace('{N}', `<em>${S.bands}</em>`);
    q('.hk-spine').querySelectorAll('li').forEach((li, i) => {
      li.className = i < S.stage ? 'ok' : i === S.stage ? 'cur' : '';
    });
    const z = q('.hk-mtr .zone');
    z.style.width = `${(st.tol / 1) * 100}%`;
  }

  function nextStage() {
    S.results.push(true);
    S.stage++;
    if (S.stage >= S.bands) return finish(true, false);
    const st = S.stages[S.stage];
    S.tt = 0; S.hold = 0; S.lastTick = 0;
    // the dials glide to the new stage's starting point
    S.ease = { t: 0, p0: S.phase360, p1: st.startPhase, g0: S.gain, g1: st.startGain };
    S.phase = 'play';
    card.classList.remove('cleared');
    stageUI();
  }

  /* ─────────────── loop ─────────────── */
  function loop(reset) {
    cancelAnimationFrame(raf);
    last = performance.now();
    if (reset && ctx) ctx.clearRect(0, 0, cv.width, cv.height);
    const frame = now => {
      if (!S) return;
      const dt = Math.min(0.1, Math.max(0, (now - last) / 1000));
      last = now;
      step(dt, now);
      draw(dt);
      paint();
      raf = requestAnimationFrame(frame);
    };
    raf = requestAnimationFrame(frame);
  }

  function input(dt) {
    const fine = shift;
    const hp = (held.has('KeyD') || held.has('KeyE') || held.has('ArrowRight') ? 1 : 0) - (held.has('KeyA') || held.has('KeyQ') || held.has('ArrowLeft') ? 1 : 0);
    const hg = (held.has('KeyW') || held.has('ArrowUp') ? 1 : 0) - (held.has('KeyS') || held.has('ArrowDown') ? 1 : 0);
    S.holdP = hp ? (S.holdP || 0) + dt : 0;
    S.holdG = hg ? (S.holdG || 0) + dt : 0;
    if (hp) {
      const rate = fine ? 9 : 26 + 120 * smooth(S.holdP / 0.9);      // °/s, ramps while held
      S.phase360 = norm360(S.phase360 + hp * rate * dt);
    }
    if (hg) {
      const rate = fine ? 0.07 : 0.22 + 0.55 * smooth(S.holdG / 0.9);  // gain/s
      S.gain = clamp(S.gain + hg * rate * dt, GAIN_MIN, GAIN_MAX);
    }
  }

  function step(dt, now) {
    if (S.phase === 'result') return;
    if (S.phase === 'clear') {
      S.pause -= dt;
      if (S.pause <= 0) nextStage();
      return;
    }
    const st = S.stages[S.stage];
    S.left -= dt;
    S.tt += dt;
    if (S.left <= 0) { S.left = 0; return finish(false, false); }

    if (S.ease) {
      S.ease.t = Math.min(1, S.ease.t + dt / 0.45);
      const e = smooth(S.ease.t);
      S.phase360 = norm360(S.ease.p0 + wrap180(S.ease.p1 - S.ease.p0) * e);
      S.gain = S.ease.g0 + (S.ease.g1 - S.ease.g0) * e;
      if (S.ease.t >= 1) S.ease = null;
    } else {
      input(dt);
      if (assist && !NZR.inGame) {
        const tg = target(st, S.tt);
        S.phase360 = norm360(S.phase360 + clamp(wrap180(tg.ph - S.phase360), -70 * dt, 70 * dt));
        S.gain += clamp(tg.amp - S.gain, -0.5 * dt, 0.5 * dt);
      }
    }

    // detent clicks while the dials turn
    const dp = Math.round(S.phase360 / 10), dg = Math.round(S.gain / 0.05);
    if ((dp !== S.detP || dg !== S.detG) && now - S.clickAt > 55 && !S.ease) { sfx('key', { volume: 0.22 }); S.clickAt = now; }
    S.detP = dp; S.detG = dg;

    const tg = target(st, S.tt);
    S.tgt = tg;
    if (tg.jumping && now - S.jumpShown > 1200) { S.jumpShown = now; card.classList.remove('jump'); void card.offsetWidth; card.classList.add('jump'); }
    const a = tg.amp, g = S.gain;
    const dx = a * Math.cos(tg.ph * RAD) - g * Math.cos(S.phase360 * RAD);
    const dy = a * Math.sin(tg.ph * RAD) - g * Math.sin(S.phase360 * RAD);
    S.err = Math.hypot(dx, dy) / a;
    S.okP = Math.abs(wrap180(tg.ph - S.phase360)) < 2 * Math.asin(Math.min(1, st.tol / (2 * Math.SQRT2))) / RAD;
    S.okG = Math.abs(g - a) / a < st.tol / Math.SQRT2;
    S.lock = S.err < st.tol;

    const prev = S.hold;
    if (S.lock) S.hold = Math.min(1, S.hold + dt / st.hold);
    else S.hold = Math.max(0, S.hold - dt / st.drain);
    const tick = Math.floor(S.hold * 8);
    if (S.lock && tick > S.lastTick) sfx('hack_tick', { volume: 0.55 + 0.06 * tick });
    if (tick !== S.lastTick && (S.lock || tick < S.lastTick)) S.lastTick = tick;
    if (prev < 1 && S.hold >= 1) {
      S.phase = 'clear';
      S.pause = CLEAR_PAUSE;
      card.classList.add('cleared');
      const li = q('.hk-spine').children[S.stage];
      if (li) li.className = 'ok just';
      sfx('toggle', { volume: 0.9 });
    }
  }

  /* ─────────────── scope ─────────────── */
  function draw(dt) {
    if (!ctx || !S) return;
    const { w, h, scale } = NZR.fitCanvas(cv);
    if (w < 4 || h < 4) return;
    const st = S.stages[Math.min(S.stage, S.bands - 1)];
    const tg = S.tgt || target(st, S.tt);
    // phosphor: fade what was drawn before instead of clearing it
    ctx.globalCompositeOperation = 'destination-out';
    ctx.fillStyle = `rgba(0,0,0,${Math.min(1, 0.32 + dt * 6).toFixed(3)})`;
    ctx.fillRect(0, 0, w, h);
    ctx.globalCompositeOperation = 'source-over';

    const laneH = h * 0.63, laneR = h - laneH;
    const cyA = laneH / 2, cyR = laneH + laneR / 2;
    const ampA = laneH * 0.36, ampR = laneR * 0.34;
    const N = Math.max(120, Math.min(360, Math.round(w / 3)));
    const scroll = S.tt * TAU * st.speed;
    const jam = S.phase === 'play' ? 1 : 0.35;
    const lockK = S.lock ? 1 : 0;

    const carrier = new Float32Array(N + 1), counter = new Float32Array(N + 1), resid = new Float32Array(N + 1);
    // the residual is drawn magnified (small mismatches must read) but soft-limited so a
    // wild one never leaves its lane
    const squash = v => Math.tanh(v * 1.5) / Math.tanh(1.5);
    for (let i = 0; i <= N; i++) {
      const x = i / N;
      const th = TAU * st.cycles * x - scroll;
      let noise = (Math.random() - 0.5) * 0.07 * jam;
      if (Math.random() < 0.012 * jam) noise += (Math.random() - 0.5) * 0.5;
      const c = tg.amp * shape(st, th + tg.ph * RAD) + noise;
      const n = -S.gain * shape(st, th + S.phase360 * RAD);
      carrier[i] = c; counter[i] = n; resid[i] = squash((c + n) / 1.25) * 1.25;
    }
    const line = (arr, cy, amp, k, color, glow, width) => {
      ctx.beginPath();
      for (let i = 0; i <= N; i++) {
        const x = (i / N) * w;
        const y = clamp(cy - arr[i] * amp * k, cy - amp * 1.35, cy + amp * 1.35);
        if (i) ctx.lineTo(x, y); else ctx.moveTo(x, y);
      }
      ctx.strokeStyle = color;
      ctx.lineWidth = width * scale;
      ctx.shadowColor = glow;
      ctx.shadowBlur = 8 * scale;
      ctx.stroke();
    };
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    const sc = 1 / 1.25;
    line(carrier, cyA, ampA, sc, 'rgba(255,107,112,.92)', 'rgba(229,72,77,.85)', 1.6);
    line(counter, cyA, ampA, sc, 'rgba(15,212,196,.95)', 'rgba(8,175,162,.9)', 1.6);
    line(resid, cyR, ampR * 1.25, sc, lockK ? 'rgba(170,255,246,.95)' : 'rgba(255,255,255,.9)', lockK ? 'rgba(15,212,196,.9)' : 'rgba(255,255,255,.35)', 1.8);
    ctx.shadowBlur = 0;
  }

  /* ─────────────── DOM readouts ─────────────── */
  const lastPaint = {};
  function setText(sel, v) { if (lastPaint[sel] === v) return; lastPaint[sel] = v; const e = q(sel); if (e) e.textContent = v; }
  function paint() {
    if (!S) return;
    // clock
    const fr = clamp(S.left / S.time, 0, 1);
    const clock = q('.hk-clock');
    q('.hk-clock .f').setAttribute('stroke-dashoffset', (RING_C * (1 - fr)).toFixed(2));
    clock.classList.toggle('low', fr < 0.35 && fr >= 0.15);
    clock.classList.toggle('crit', fr < 0.15);
    setText('.hk-clock b', String(Math.ceil(S.left)));
    // dials
    const pd = q('.hk-dial[data-k="phase"]'), gd = q('.hk-dial[data-k="gain"]');
    pd.querySelector('.pt').setAttribute('transform', `rotate(${S.phase360.toFixed(2)} 50 50)`);
    const gf = (S.gain - GAIN_MIN) / (GAIN_MAX - GAIN_MIN);
    gd.querySelector('.pt').setAttribute('transform', `rotate(${(-120 + 240 * gf).toFixed(2)} 50 50)`);
    gd.querySelector('.fl').setAttribute('stroke-dashoffset', (100 - gf * 100).toFixed(2));
    setText('.hk-dial[data-k="phase"] b', `${String(Math.round(S.phase360) % 360).padStart(3, '0')}°`);
    setText('.hk-dial[data-k="gain"] b', `${Math.round(S.gain * 100)}%`);
    const play = S.phase === 'play';
    pd.classList.toggle('ok', play && !!S.okP);
    gd.classList.toggle('ok', play && !!S.okG);
    // null ring + residual meter
    const hold = (S.phase === 'clear' || (S.phase === 'result' && S.won)) ? 1 : S.hold;
    q('.hk-hold .f').setAttribute('stroke-dashoffset', (100 - hold * 100).toFixed(2));
    setText('.hk-hold b', String(Math.round(hold * 100)));
    const err = S.phase === 'clear' ? 0 : clamp(S.err, 0, 1);
    setText('.hk-res b', `${Math.round(err * 100)}%`);
    const m = q('.hk-mtr');
    m.querySelector('i').style.width = `${(err * 100).toFixed(1)}%`;
    m.querySelector('.mk').style.left = `${(err * 100).toFixed(1)}%`;
    card.classList.toggle('lock', (play && S.lock) || S.phase === 'clear');
  }

  /* ─────────────── result ─────────────── */
  function finish(success, cancelled) {
    if (!S || S.done) return;
    S.done = true;
    S.won = success;
    S.phase = 'result';
    card.classList.remove('lock', 'cleared', 'jump');
    if (!success) {
      const li = q('.hk-spine').children[S.stage];
      if (li) li.className = 'no';
    }
    const used = S.time - S.left;
    const res = q('.hk-result');
    const title = success ? t('ui.hk_win', 'Jammer down') : t('ui.hk_lose', 'Signal lost');
    const line = success
      ? t('ui.hk_win_sub', '{code} is off the air. Radios nearby clear up.').replace('{code}', S.code)
      : cancelled ? t('ui.hk_quit_sub', 'You let go of the carrier. The jammer keeps running.')
        : t('ui.hk_lose_sub', 'The carrier slipped away. Give it a moment before you try again.');
    res.className = `hk-result on ${success ? '' : 'fail'}`;
    res.innerHTML = `<div class="ic">${icon(success ? 'check' : 'x')}</div><h2>${esc(title)}</h2><p>${esc(line)}</p>
      <div class="rr"><span><em>${esc(t('ui.hk_r_stages', 'Stages'))}</em><b>${S.results.length}/${S.bands}</b></span><span><em>${esc(t('ui.hk_r_time', 'Time'))}</em><b>${esc(NZR.fmt.time(used))}</b></span><span><em>${esc(t('ui.hk_r_unit', 'Unit'))}</em><b>${esc(S.code)}</b></span></div>
      <i class="run"></i>`;
    if (!success) { card.classList.remove('shake'); void card.offsetWidth; card.classList.add('shake'); }
    sfx(success ? 'hack_ok' : 'hack_fail');
    if (cancelled) { post(false, true); return; }
    const sinceOpen = (performance.now() - S.openedAt) / 1000;
    const minWait = success ? Math.max(0, S.bands * 2.5 + 0.4 - sinceOpen) : 0;
    const wait = Math.max(RESULT_MIN, minWait);
    res.querySelector('.run').style.animationDuration = `${wait.toFixed(2)}s`;
    const mine = S;
    setTimeout(() => { if (S === mine) post(success, false); }, wait * 1000);
  }

  function post(success, cancelled) {
    if (!S || S.posted) return;
    S.posted = true;
    const mine = S;
    NZR.post('hack:result', { id: S.id, success: !!success, cancelled: !!cancelled });
    if (cancelled) { NZR.close('hack'); return; }
    // Lua closes the window when it has the result; close it ourselves if that never comes
    setTimeout(() => { if (S === mine && NZR.isOpen('hack')) NZR.close('hack'); }, NZR.inGame ? 2500 : 900);
  }

  function cancel() {
    if (!S) return NZR.close('hack');
    if (S.done) { if (!S.posted) post(S.won, false); return; }
    finish(false, true);
  }

  /* ─────────────── keys ─────────────── */
  const MOVE = ['KeyA', 'KeyD', 'KeyQ', 'KeyE', 'KeyW', 'KeyS', 'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'];
  const keys = { Escape: () => cancel() };
  const keysUp = {};
  MOVE.forEach(code => {
    keys[code] = e => {
      shift = e.shiftKey;
      if (!S || S.phase !== 'play') return;
      if (!held.has(code) && !e.repeat) {
        // a tap moves one fine step even if released before the next frame
        const fine = e.shiftKey;
        if (code === 'KeyD' || code === 'KeyE' || code === 'ArrowRight') S.phase360 = norm360(S.phase360 + (fine ? 0.5 : 1.5));
        if (code === 'KeyA' || code === 'KeyQ' || code === 'ArrowLeft') S.phase360 = norm360(S.phase360 - (fine ? 0.5 : 1.5));
        if (code === 'KeyW' || code === 'ArrowUp') S.gain = clamp(S.gain + (fine ? 0.004 : 0.012), GAIN_MIN, GAIN_MAX);
        if (code === 'KeyS' || code === 'ArrowDown') S.gain = clamp(S.gain - (fine ? 0.004 : 0.012), GAIN_MIN, GAIN_MAX);
      }
      held.add(code);
    };
    keysUp[code] = e => { shift = e.shiftKey; held.delete(code); };
  });
  keys.ShiftLeft = keys.ShiftRight = () => { shift = true; };
  keysUp.ShiftLeft = keysUp.ShiftRight = () => { shift = false; };
  window.addEventListener('blur', () => { held.clear(); shift = false; });

  /* ─────────────── preview helpers (browser only) ─────────────── */
  const DEMO = {
    pocket: { code: 'JX-10', label: 'Pocket Jammer', bands: 1, time: 25 },
    case: { code: 'JX-40', label: 'Field Jammer', bands: 2, time: 40 },
    heavy: { code: 'JX-90', label: 'Heavy Jammer', bands: 3, time: 55 },
  };
  let demoType = 'heavy', demoSeed = 7734211;
  function demoData() {
    const d = DEMO[demoType];
    return { id: `jm${demoSeed % 997}`, title: `${d.code} · ${d.label}`, code: d.code, label: d.label, type: demoType, bands: d.bands, time: d.time, seed: demoSeed, difficulty: d.bands };
  }
  function demoBar() {
    if (NZR.inGame || document.querySelector('.hk-demo')) return;
    const bar = document.createElement('div');
    bar.className = 'hk-demo';
    bar.innerHTML = `<span>Preview</span><div class="seg">${Object.keys(DEMO).map(k => `<button data-t="${k}" class="${k === demoType ? 'on' : ''}">${DEMO[k].code}</button>`).join('')}</div>
      <button class="btn-line btn-sm" data-a="seed">${icon('refresh')}New seed</button>
      <button class="btn-line btn-sm" data-a="assist">${icon('target')}Assist</button>`;
    bar.addEventListener('click', e => {
      const b = e.target.closest('button'); if (!b) return;
      if (b.dataset.t) { demoType = b.dataset.t; bar.querySelectorAll('[data-t]').forEach(x => x.classList.toggle('on', x === b)); }
      if (b.dataset.a === 'seed') demoSeed = Math.floor(Math.random() * 2147483646) + 1;
      if (b.dataset.a === 'assist') { assist = !assist; b.classList.toggle('on', assist); return; }
      const r = document.querySelector('.nz-reopen'); if (r) r.remove();
      NZR.demo('hack', demoData());
    });
    document.body.appendChild(bar);
  }

  app = NZR.app('hack', {
    full: true,
    escClose: false,
    modalKeys: true,
    keys,
    keysUp,
    init(el) { root = el; build(); },
    open(data) {
      Object.keys(lastPaint).forEach(k => delete lastPaint[k]);
      start(data || {});
    },
    close() {
      cancelAnimationFrame(raf);
      raf = 0;
      S = null;
      held.clear();
      if (card) card.className = 'hk-card nz-grain';
    },
    preview() {
      NZR.mock('hack:result', d => ({ ok: true, d }));
      demoBar();
      NZR.demo('hack', demoData());
    },
    // preview/test hooks (no effect on a real attempt unless called)
    debug: {
      assist(on) { assist = !!on; },
      finish(ok) { if (S && !S.done) { if (ok) S.results = S.stages.map(() => true); finish(!!ok, false); } },
      state() { return S && { stage: S.stage, err: S.err, hold: S.hold, left: S.left, phase: S.phase, lock: S.lock }; },
      time(sec) { if (S) S.left = sec; },
    },
  });
})();
