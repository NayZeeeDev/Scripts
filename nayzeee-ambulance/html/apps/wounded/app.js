/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · app 'wounded' — the downed HUD (HUD design)
   Opened from Lua without focus (client/modules/wounded.lua):
     open    { L, state, injuries, maxChips, pulseLine, overlay, heartbeat, volume }
     state   { state, avpu, unconscious, bleed, stab, clock, running, rate (clock speed 0..1), critical,
               carried, stretcher, bag, vehicle,
               crawl { enabled, can, why, on, stamina, toggle },
               giveUp { enabled, allowed, left, hold },
               call { allowed, left, called, pending, medics, ai },
               status { cpr, cprBy, treating, onScene }, help { eta, unit, ai, status } | null,
               keys { crawl, stop, left, right, call, giveUp } }
     injuries { list: [{ regionLabel, label, icon, severity, bleeding, tourniquet, splinted, treated }], max }
     fx      { mode, tunnel, bleed, unconscious, cpr, stab }   screen overlay + heartbeat
     hold    { kind: 'giveUp', p: 0..1 }                        hold ring
     flash   { kind: 'ok'|'warn'|'bad', text, ms }
   The clock, ETA and lock timers count down locally between Lua updates.
   ═══════════════════════════════════════════════════════════ */
(() => {
  const esc = NZA.esc;
  const icon = n => NZA.icon(n);
  let L = {};
  const T = (k, fb, ...a) => {
    let s = String(L[k] !== undefined ? L[k] : fb);
    a.forEach(v => { s = s.replace(/%[sd]/, v); });
    return s;
  };
  const mmss = s => { s = Math.max(0, Math.floor(s || 0)); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; };
  const RING = 2 * Math.PI * 15;

  const A = {
    st: null, recvAt: 0,
    clockBase: 0, clockAt: 0,
    inj: [], maxChips: 5,
    fx: { mode: 'wounded', tunnel: 0, bleed: 0, unconscious: false, cpr: false, stab: false },
    opts: { pulseLine: true, overlay: true, heartbeat: true, volume: 0.6 },
    hold: 0,
    phase: 0, lastBeat: 0, agonalAt: 0, blipAt: -9,
  };
  let ui = {};
  let flip = null;
  let ticker = 0;
  let raf = 0;
  let flashTimer = 0;
  let previewHold = null;
  const last = {};

  const setHTML = (key, el, html) => { if (last[key] !== html) { last[key] = html; el.innerHTML = html; } };
  const since = () => (performance.now() - A.recvAt) / 1000;
  const left = v => Math.max(0, Math.ceil((v || 0) - since()));

  /* ─────────────── build ─────────────── */
  function build(el) {
    el.innerHTML = `
      <div class="wd-fx">
        <div class="wd-vig"></div>
        <div class="wd-edge"></div>
        <div class="wd-lid"></div>
      </div>
      <div class="wd-dock">
        <div class="wd-help"></div>
        <div class="wd-flash"></div>
        <div class="wd-panel nza-hud">
          <div class="wd-top">
            <div class="wd-clockcol">
              <div class="wd-cap"><span class="wd-dot"></span><span class="t"></span></div>
              <div class="wd-flip"></div>
            </div>
            <div class="wd-info">
              <div class="wd-titlerow">
                <canvas class="wd-beat" width="96" height="30"></canvas>
                <h1 class="wd-title"></h1>
              </div>
              <div class="wd-status"></div>
            </div>
          </div>
          <div class="wd-inj"></div>
          <div class="wd-keys">
            <div class="wd-move"></div>
            <i class="wd-sep"></i>
            <div class="wd-call"></div>
            <div class="wd-give"></div>
          </div>
        </div>
      </div>`;
    const q = s => el.querySelector(s);
    ui = {
      root: el, fx: q('.wd-fx'), edge: q('.wd-edge'), help: q('.wd-help'), flash: q('.wd-flash'), panel: q('.wd-panel'),
      cap: q('.wd-cap .t'), capDot: q('.wd-dot'), title: q('.wd-title'), status: q('.wd-status'), inj: q('.wd-inj'),
      move: q('.wd-move'), sep: q('.wd-sep'), call: q('.wd-call'), give: q('.wd-give'), beat: q('.wd-beat'),
    };
    flip = NZA.ui.FlipClock(q('.wd-flip'), { value: '00:00' });
  }

  /* ─────────────── clock ─────────────── */
  function clockValue() {
    const s = A.st;
    if (!s) return 0;
    if (!s.running) return A.clockBase;
    const rate = s.rate === undefined || s.rate === null ? 1 : Math.max(0, Math.min(1, s.rate));
    return Math.max(0, A.clockBase - Math.floor(((performance.now() - A.clockAt) / 1000) * rate));
  }

  function renderClock() {
    const s = A.st;
    if (!s) return;
    const v = clockValue();
    flip.set(NZA.fmt.time(v));
    const arrest = s.state === 'arrest';
    const cpr = s.status && s.status.cpr;
    let tone = '';
    if (arrest) tone = cpr ? 'teal' : 'red';
    else if (!s.running) tone = 'teal';
    else if (v <= (s.critical || 30)) tone = 'red';
    flip.tone(tone);
    flip.paused(!s.running);
    let cap;
    if (arrest) cap = cpr ? T('clock_cpr', 'Held by CPR') : T('clock_arrest', 'Until death');
    else cap = s.running ? T('clock_bleed', 'Bleed-out') : T('clock_paused', 'Clock paused');
    if (ui.cap.textContent !== cap) ui.cap.textContent = cap;
    ui.capDot.className = `wd-dot ${tone || 'white'} ${s.running ? 'live' : ''}`;
    ui.panel.classList.toggle('crit', tone === 'red');
  }

  /* ─────────────── title + status ─────────────── */
  function titleText(s) {
    if (s.state === 'arrest') return T('title_arrest', 'CARDIAC ARREST');
    if (s.unconscious) return T('title_unconscious', 'UNCONSCIOUS');
    return T('title_wounded', 'WOUNDED');
  }

  function statusSegments(s) {
    const out = [];
    const st = s.status || {};
    if (s.state === 'arrest') {
      out.push(st.cpr ? { t: T('st_cpr', 'CPR IN PROGRESS'), c: 'teal pulse' } : { t: T('st_nocpr', 'NO PULSE — CPR NEEDED'), c: 'red' });
    } else if (s.stab) {
      out.push({ t: T('st_stable', 'STABILIZED — CLOCK PAUSED'), c: 'teal' });
    } else if (s.bleed > 0) {
      out.push({ t: T(`st_bleed_${s.bleed}`, ['', 'BLEEDING SLOWLY', 'BLEEDING', 'BLEEDING HEAVILY'][s.bleed] || 'BLEEDING'), c: s.bleed >= 2 ? 'red' : 'amber' });
    }
    if (s.bag) out.push({ t: T('st_bag', 'IN A BODY BAG'), c: '' });
    else if (s.stretcher) out.push({ t: T('st_stretcher', 'ON A STRETCHER'), c: '' });
    else if (s.carried) out.push({ t: T('st_carried', 'BEING CARRIED'), c: '' });
    else if (s.vehicle) out.push({ t: T('st_vehicle', 'IN TRANSPORT'), c: '' });

    const h = s.help;
    const call = s.call || {};
    if (s.state === 'arrest' && st.cpr) return out;
    if (st.treating) out.push({ t: T('st_treating', 'A MEDIC IS TREATING YOU'), c: 'teal' });
    else if (st.onScene) out.push({ t: T('st_onscene', 'MEDIC ON SCENE'), c: 'teal' });
    else if (h && h.status !== 'onscene') {
      out.push({ t: h.ai ? T('st_ai', 'AI PARAMEDIC RESPONDING') : T('st_enroute', 'MEDIC ON THE WAY'), c: 'white' });
      if (h.eta !== null && h.eta !== undefined) out.push({ t: T('st_eta', 'ETA %s', mmss(left(h.eta))), c: 'white mono' });
    } else if (h && h.status === 'onscene') out.push({ t: T('st_onscene', 'MEDIC ON SCENE'), c: 'teal' });
    else if (call.called && call.medics === 0 && !call.ai) out.push({ t: T('st_nomedic', 'NO MEDICS ON DUTY'), c: 'amber' });
    else if (call.called) out.push({ t: T('st_notified', 'EMS NOTIFIED'), c: '' });
    return out;
  }

  function renderStatus() {
    const s = A.st;
    if (!s) return;
    const t = titleText(s);
    if (ui.title.textContent !== t) ui.title.textContent = t;
    ui.title.className = `wd-title ${s.state === 'arrest' ? 'red' : s.unconscious ? 'dim' : ''}`;
    const segs = statusSegments(s);
    setHTML('status', ui.status, segs.map((g, i) => `${i ? '<i class="dot">·</i>' : ''}<span class="${g.c}">${esc(g.t)}</span>`).join(''));
  }

  /* ─────────────── injuries ─────────────── */
  function chipsHTML(list, count) {
    const shown = list.slice(0, count);
    return shown.map(j => {
      let tone = '';
      let tag = '';
      if (j.tourniquet) { tone = 'teal'; tag = `<em>${esc(T('tag_tq', 'TQ'))}</em>`; }
      else if (j.splinted) { tone = 'teal'; tag = icon('splint'); }
      else if (j.bleeding) { tone = 'red'; tag = '<i class="bd"></i>'; }
      else if (j.treated) { tone = 'teal'; tag = icon('check'); }
      return `<span class="wd-chip ${tone} s${j.severity || 1}">${icon(j.icon || 'drop')}<b>${esc(j.regionLabel)}</b><span>${esc(j.label)}</span>${tag ? `<span class="wt">${tag}</span>` : ''}</span>`;
    }).join('') + (list.length > count ? `<span class="wd-chip more">+${list.length - count}</span>` : '');
  }

  // as many chips as fit on one line (worst first), the rest collapse into "+N"
  function renderInj() {
    const list = A.inj || [];
    if (!list.length) { setHTML('inj', ui.inj, ''); ui.inj.style.display = 'none'; return; }
    ui.inj.style.display = '';
    let count = Math.min(list.length, Math.max(1, A.maxChips || 5));
    setHTML('inj', ui.inj, chipsHTML(list, count));
    const wrapped = () => {
      const first = ui.inj.firstElementChild, lastEl = ui.inj.lastElementChild;
      return !!(first && lastEl && lastEl.offsetTop > first.offsetTop + 4);
    };
    while (count > 1 && wrapped()) {
      count -= 1;
      setHTML('inj', ui.inj, chipsHTML(list, count));
    }
  }

  /* ─────────────── key hints ─────────────── */
  const kbd = (k, cls = '') => `<kbd class="${cls}">${esc(k)}</kbd>`;

  function renderKeys() {
    const s = A.st;
    if (!s) return;
    const k = s.keys || {};
    const c = s.crawl || {};
    let move = '';
    if (c.enabled && s.state === 'wounded') {
      if (c.can) {
        const st = c.stamina ?? 1;
        const meter = (c.on || st < 0.985)
          ? `<span class="wd-stam ${st < 0.25 ? 'low' : ''}" title=""><i style="width:${Math.round(st * 100)}%"></i></span>` : '';
        move = `<span class="wd-k ${c.on ? 'on' : ''}">${kbd(k.crawl || 'W', c.on ? 'teal' : '')}${esc(T('k_crawl', 'Crawl'))}${meter}</span>`
          + (c.toggle !== false ? `<span class="wd-k">${kbd(k.stop || 'S')}${esc(T('k_stop', 'Stop'))}</span>` : '')
          + `<span class="wd-k">${kbd(k.left || 'A')}${kbd(k.right || 'D')}${esc(T('k_turn', 'Turn'))}</span>`;
      } else {
        move = `<span class="wd-k off">${icon(c.why === 'held' ? 'hand' : 'lock')}${esc(c.why === 'held' ? T('k_held', 'Someone is moving you') : T('k_nomove', "You can't move"))}</span>`;
      }
    } else if (s.state === 'arrest' || (c.enabled && !c.can)) {
      move = `<span class="wd-k off">${icon('lock')}${esc(T('k_nomove', "You can't move"))}</span>`;
    }
    setHTML('move', ui.move, move);
    ui.move.style.display = move ? '' : 'none';

    const call = s.call || {};
    let ch = '';
    const cl = left(call.left);
    if (!call.allowed) ch = `<span class="wd-k off">${kbd(k.call || 'G')}${esc(T('k_call', 'Call EMS'))}</span>`;
    else if (call.pending) ch = `<span class="wd-k busy">${kbd(k.call || 'G', 'teal')}${esc(T('k_call', 'Call EMS'))}<i class="spin"></i></span>`;
    else if (cl > 0) ch = `<span class="wd-k done">${kbd(k.call || 'G')}${icon('check')}${esc(T('k_called', 'EMS called'))}<span class="cd">${mmss(cl)}</span></span>`;
    else ch = `<span class="wd-k ${call.called ? '' : 'hot'}">${kbd(k.call || 'G', call.called ? '' : 'teal')}${esc(T('k_call', 'Call EMS'))}</span>`;
    setHTML('call', ui.call, ch);

    const g = s.giveUp || {};
    let gh = '';
    if (g.enabled && g.allowed) {
      const gl = left(g.left);
      const locked = gl > 0;
      const dash = (A.hold * RING).toFixed(1);
      gh = `<span class="wd-k give ${locked ? 'off' : ''} ${A.hold > 0 ? 'holding' : ''}">
          <span class="wd-ring"><svg viewBox="0 0 34 34"><circle cx="17" cy="17" r="15" class="bg"/><circle cx="17" cy="17" r="15" class="fg" stroke-dasharray="${dash} ${RING.toFixed(1)}"/></svg>${kbd(k.giveUp || 'E')}</span>
          <span class="lb">${esc(T('k_giveup', 'Give up'))}${locked ? `<small>${icon('lock')}${esc(T('k_locked', 'in %s', mmss(gl)))}</small>` : `<small>${esc(T('k_hold', 'Hold'))} ${g.hold || 3}s</small>`}</span>
        </span>`;
    }
    setHTML('give', ui.give, gh);
    ui.give.style.display = gh ? '' : 'none';
    ui.sep.style.display = move ? '' : 'none';
  }

  /* ─────────────── help card ─────────────── */
  function renderHelp() {
    const s = A.st;
    if (!s) return;
    const st = s.status || {};
    const h = s.help;
    const call = s.call || {};
    let card = null;
    if (s.state === 'arrest' && st.cpr) {
      card = { tone: 'teal', ic: 'heart', t: T('help_cpr', 'CPR in progress'), m: st.cprBy || T('help_cpr_m', 'Stay with us — compressions keep the clock from running out.'), live: true };
    } else if (st.treating) {
      card = { tone: 'teal', ic: 'stetho', t: T('help_treating', 'A medic is examining you'), m: st.onScene || '' };
    } else if (st.onScene || (h && h.status === 'onscene')) {
      card = { tone: 'teal', ic: 'ambulance', t: T('help_onscene', 'Medic on scene'), m: st.onScene || (h && h.unit) || '' };
    } else if (h) {
      const eta = (h.eta !== null && h.eta !== undefined) ? left(h.eta) : null;
      card = { tone: 'white', ic: 'ambulance', t: h.ai ? T('help_ai', 'AI paramedic responding') : T('help_enroute', 'Medic on the way'), m: h.unit || '', eta, etaMax: h.eta };
    } else if (call.called && call.medics === 0 && !call.ai && s.state !== 'dead') {
      card = { tone: 'amber', ic: 'alert', t: T('help_none', 'No medics on duty'), m: T('help_none_m', 'Your call is logged. Anyone passing by can still help.') };
    } else if (call.called) {
      const n = call.medics;
      const m = n === 1 ? T('help_medic1', '1 medic on duty') : (n > 1 ? T('help_medics', '%d medics on duty', n) : '');
      card = { tone: 'white', ic: 'broadcast', t: T('help_notified', 'EMS notified'), m };
    }
    if (!card) { setHTML('help', ui.help, ''); ui.help.classList.remove('on'); return; }
    let right = '';
    let bar = '';
    if (card.eta !== null && card.eta !== undefined) {
      right = `<div class="eta"><small>${esc(T('help_eta', 'ETA'))}</small><b>${mmss(card.eta)}</b></div>`;
      const startEta = Math.max(card.etaMax || 1, 1);
      bar = `<i class="bar" style="width:${Math.max(4, 100 - (card.eta / startEta) * 100).toFixed(1)}%"></i>`;
    } else if (card.live) {
      right = '<div class="eta live"><span class="cprdot"></span></div>';
    }
    const html = `<div class="wd-note ${card.tone}"><span class="ni">${icon(card.ic)}</span><div class="tx"><b>${esc(card.t)}</b>${card.m ? `<p>${esc(card.m)}</p>` : ''}</div>${right}${bar}</div>`;
    setHTML('help', ui.help, html);
    ui.help.classList.add('on');
  }

  /* ─────────────── overlay fx ─────────────── */
  function renderFx() {
    const f = A.fx;
    const s = A.st || {};
    const arrest = s.state === 'arrest' || f.mode === 'arrest';
    const unc = !!(s.unconscious || f.unconscious);
    let vig = 0.2 + (f.tunnel || 0) * 0.55 + (unc ? 0.18 : 0);
    if (arrest) vig = 0.82;
    if (s.stab && !arrest) vig *= 0.8;
    ui.fx.style.setProperty('--vig', Math.min(0.95, vig).toFixed(2));
    A.edgeBase = arrest ? 0.5 : Math.min(0.8, 0.1 + (f.bleed || 0) * 0.11 + (f.tunnel || 0) * 0.22);
    ui.edge.style.opacity = A.edgeBase.toFixed(2);
    ui.fx.classList.toggle('off', A.opts.overlay === false);
    ui.fx.classList.toggle('unc', unc && !arrest);
    ui.fx.classList.toggle('arrest', arrest);
    ui.root.classList.toggle('is-arrest', arrest);
    ui.root.classList.toggle('is-unc', unc);
  }

  /* ─────────────── heartbeat (line + sound + edge pulse) ─────────────── */
  function heartRate() {
    const s = A.st || {};
    const f = A.fx;
    if (s.state === 'arrest') return (s.status && s.status.cpr) ? 110 : 0;
    let r = 94 + (f.tunnel || 0) * 56 + (s.bleed || 0) * 5;
    if (s.stab) r -= 12;
    if (s.unconscious) r -= 8;
    return Math.max(56, Math.min(158, r));
  }

  function beatSound(weak) {
    if (!A.opts.heartbeat || !NZA.audio) return;
    const v = Math.max(0, Math.min(1, A.opts.volume ?? 0.6));
    const s = A.st || {};
    const soft = (s.unconscious ? 0.6 : 1) * (weak ? 0.45 : 1);
    const vol = 0.2 * v * soft;
    if (vol <= 0.002) return;
    NZA.audio.tone(64, 120, { vol, type: 'sine', slide: 40 });
    NZA.audio.tone(128, 60, { vol: vol * 0.35, type: 'sine', slide: 80 });
    if (!weak) NZA.audio.tone(56, 130, { vol: vol * 0.7, type: 'sine', at: 0.17, slide: 36 });
  }

  function beatPulse(strength) {
    if (!ui.edge || !ui.edge.animate || A.opts.overlay === false) return;
    const base = A.edgeBase || 0.3;
    const peak = Math.min(1, base + strength * 0.45);
    ui.edge.animate([{ opacity: base }, { opacity: peak, offset: 0.18 }, { opacity: base }], { duration: 520, easing: 'ease-out' });
  }

  function drawLine(dt) {
    const cv = ui.beat;
    if (!cv) return;
    const s = A.st || {};
    const rate = heartRate();
    const arrest = s.state === 'arrest';
    const now = performance.now() / 1000;

    // beat timing (phase integrates the rate so rate changes never jump)
    let beat = false;
    if (rate > 0) {
      const before = Math.floor(A.phase);
      A.phase += dt * rate / 60;
      if (Math.floor(A.phase) !== before) beat = true;
    } else if (arrest) {
      if (!A.agonalAt) A.agonalAt = now + 3 + Math.random() * 4;
      if (now >= A.agonalAt) { A.blipAt = now; A.agonalAt = now + 4 + Math.random() * 5; beatSound(true); beatPulse(0.7); }
    }
    if (beat) { beatSound(false); beatPulse(Math.min(1, 0.35 + (s.bleed || 0) * 0.2)); }

    if (A.opts.pulseLine === false) return;
    const ctx = cv.getContext('2d');
    const z = NZA.zoom || 1;
    const dpr = window.devicePixelRatio || 1;
    const W = Math.round(cv.clientWidth * z * dpr), H = Math.round(cv.clientHeight * z * dpr);
    if (!W || !H) return;
    if (cv.width !== W || cv.height !== H) { cv.width = W; cv.height = H; A.buf = null; }
    if (!A.buf || A.buf.length !== W) A.buf = new Float32Array(W);
    const per = rate > 0 ? 60 / rate : 1;
    const speed = W / 1.6;                     // px per second
    const steps = Math.max(1, Math.round(speed * dt));
    for (let i = 0; i < steps; i++) {
      A.lineT = (A.lineT || 0) + dt / steps;
      let v;
      if (rate > 0) {
        const tp = (A.phase - (steps - i - 1) * (dt / steps) * rate / 60) * per;
        v = NZA.vitals.wave('ecg', tp, { rhythm: arrest ? 'sinus' : (rate > 100 ? 'stach' : 'sinus'), rate });
        if (arrest) v *= 0.7;
      } else {
        v = NZA.vitals.wave('ecg', A.lineT, { rhythm: 'asystole', rate: 60 });
        const b = now - A.blipAt;
        if (b >= 0 && b < 0.6) v += 0.55 * NZA.vitals.wave('ecg', b, { rhythm: 'pea', rate: 40 });
      }
      A.buf.copyWithin(0, 1);
      A.buf[W - 1] = v;
    }
    ctx.clearRect(0, 0, W, H);
    const col = arrest ? (rate > 0 ? '15,212,196' : '255,116,120') : (s.stab ? '15,212,196' : (s.bleed >= 2 ? '255,116,120' : '255,255,255'));
    const g = ctx.createLinearGradient(0, 0, W, 0);
    g.addColorStop(0, `rgba(${col},0)`);
    g.addColorStop(0.55, `rgba(${col},.55)`);
    g.addColorStop(1, `rgba(${col},1)`);
    ctx.strokeStyle = g;
    ctx.lineWidth = 1.6 * z * dpr;
    ctx.lineJoin = 'round';
    ctx.shadowColor = `rgba(${col},.8)`;
    ctx.shadowBlur = 5 * z * dpr;
    ctx.beginPath();
    for (let x = 0; x < W; x++) {
      const y = H * 0.56 - A.buf[x] * H * 0.42;
      if (x === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    }
    ctx.stroke();
    // the pen
    const yEnd = H * 0.56 - A.buf[W - 1] * H * 0.42;
    ctx.shadowBlur = 8 * z * dpr;
    ctx.fillStyle = `rgba(${col},1)`;
    ctx.beginPath(); ctx.arc(W - 2 * z * dpr, yEnd, 2 * z * dpr, 0, Math.PI * 2); ctx.fill();
  }

  function frame(tsPrev) {
    let prev = tsPrev;
    const loop = ts => {
      const dt = Math.min(0.05, prev ? (ts - prev) / 1000 : 0.016);
      prev = ts;
      try { drawLine(dt); } catch (e) { console.error('[wounded] line', e); }
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
  }

  /* ─────────────── tick ─────────────── */
  function tick() {
    renderClock();
    renderStatus();
    renderKeys();
    renderHelp();
  }

  function applyState(d) {
    const prev = A.st;
    const now = performance.now();
    const shown = clockValue();
    A.st = d;
    A.recvAt = now;
    const rebase = !prev || prev.state !== d.state || prev.running !== d.running || prev.rate !== d.rate || !d.running || Math.abs(shown - d.clock) >= 2;
    if (rebase) { A.clockBase = d.clock; A.clockAt = now; }
    ui.root.classList.toggle('st-arrest', d.state === 'arrest');
    const w = ui.panel.offsetWidth;
    tick();
    renderFx();
    if (ui.panel.offsetWidth !== w) renderInj();   // panel width changed: re-fit the chip strip
  }

  function flash({ kind = 'ok', text = '', ms = 3200 } = {}) {
    if (!text) return;
    const ic = kind === 'ok' ? 'check' : kind === 'bad' ? 'x' : 'alert';
    ui.flash.className = `wd-flash on ${kind}`;
    ui.flash.innerHTML = `${icon(ic)}<span>${esc(text)}</span>`;
    clearTimeout(flashTimer);
    flashTimer = setTimeout(() => { ui.flash.className = 'wd-flash'; }, ms);
  }

  /* ─────────────── app ─────────────── */
  NZA.app('wounded', {
    escClose: false,
    init(el) { build(el); },
    open(d) {
      L = Object.assign({}, d.L || {});
      A.opts = {
        pulseLine: d.pulseLine !== false, overlay: d.overlay !== false,
        heartbeat: d.heartbeat !== false, volume: d.volume ?? 0.6,
      };
      A.maxChips = d.maxChips || 5;
      A.inj = d.injuries || [];
      A.hold = 0;
      A.phase = 0;
      A.st = null;
      Object.keys(last).forEach(k => { delete last[k]; });
      ui.beat.style.display = A.opts.pulseLine ? '' : 'none';
      ui.root.classList.remove('leaving');
      if (d.state) applyState(d.state);
      renderInj();
      clearInterval(ticker);
      ticker = setInterval(tick, 250);
      cancelAnimationFrame(raf);
      frame(0);
    },
    close() {
      clearInterval(ticker);
      cancelAnimationFrame(raf);
      clearTimeout(flashTimer);
      ui.flash.className = 'wd-flash';
      if (previewHold) { previewHold.destroy(); previewHold = null; }
    },
    msg: {
      state(d) { applyState(d); },
      injuries(d) { A.inj = d.list || []; if (d.max) A.maxChips = d.max; renderInj(); },
      fx(d) { A.fx = Object.assign(A.fx, d || {}); renderFx(); },
      hold(d) { A.hold = Math.max(0, Math.min(1, d.p || 0)); renderKeys(); },
      flash(d) { flash(d); },
    },

    /* browser demo: index.html?app=wounded&demo=bleeding|stable|unconscious|arrest|cpr|crawl|help|nomedic */
    preview() {
      const demo = new URLSearchParams(location.search).get('demo') || 'bleeding';
      const keys = { crawl: 'W', stop: 'S', left: 'A', right: 'D', call: 'G', giveUp: 'E' };
      const base = {
        state: 'wounded', avpu: 'A', unconscious: false, bleed: 2, stab: false, clock: 167, running: true, critical: 30,
        carried: false, stretcher: false, bag: false, vehicle: false,
        crawl: { enabled: true, can: true, why: null, on: false, stamina: 1, toggle: true },
        giveUp: { enabled: true, allowed: true, left: 38, hold: 3 },
        call: { allowed: true, left: 0, called: false, pending: false, medics: 3, ai: false },
        status: { cpr: false, treating: false, onScene: null },
        help: null, keys,
      };
      const variants = {
        bleeding: {},
        stable: { bleed: 0, stab: true, clock: 120, running: false, giveUp: { enabled: true, allowed: true, left: 0, hold: 3 },
          call: { allowed: true, left: 41, called: true, pending: false, medics: 3, ai: false } },
        unconscious: { avpu: 'U', unconscious: true, bleed: 3, clock: 24, crawl: { enabled: true, can: false, why: 'nomove', on: false, stamina: 1 } },
        arrest: { state: 'arrest', avpu: 'U', unconscious: true, bleed: 3, clock: 241, crawl: { enabled: true, can: false, why: 'nomove' },
          giveUp: { enabled: true, allowed: true, left: 0, hold: 3 } },
        cpr: { state: 'arrest', avpu: 'U', unconscious: true, bleed: 1, clock: 188, running: false, crawl: { enabled: true, can: false, why: 'nomove' },
          status: { cpr: true, cprBy: 'Maya Reyes · Paramedic', treating: true, onScene: 'Maya Reyes' }, giveUp: { enabled: true, allowed: true, left: 0, hold: 3 } },
        crawl: { crawl: { enabled: true, can: true, on: true, stamina: 0.46, toggle: true }, bleed: 1, clock: 212 },
        help: { bleed: 1, clock: 198, call: { allowed: true, left: 47, called: true, pending: false, medics: 2, ai: false },
          help: { eta: 84, unit: 'Unit 04 · Maya Reyes', ai: false, status: 'enroute' } },
        nomedic: { call: { allowed: true, left: 52, called: true, pending: false, medics: 0, ai: false } },
        carried: { carried: true, bleed: 1, clock: 205, crawl: { enabled: true, can: false, why: 'held' },
          status: { cpr: false, treating: false, onScene: 'Theo Kane' } },
      };
      const v = variants[demo] || {};
      const st = Object.assign({}, base, v);
      const injuries = demo === 'arrest' || demo === 'cpr'
        ? [
          { regionLabel: 'Chest', label: 'GSW', icon: 'crosshair', severity: 4, bleeding: demo !== 'cpr', treated: demo === 'cpr' },
          { regionLabel: 'Abdomen', label: 'Internal', icon: 'drop', severity: 3, bleeding: true },
          { regionLabel: 'Left thigh', label: 'GSW', icon: 'crosshair', severity: 2, bleeding: false, tourniquet: true },
        ]
        : [
          { regionLabel: 'Chest', label: 'GSW', icon: 'crosshair', severity: 3, bleeding: !st.stab, treated: st.stab },
          { regionLabel: 'Right thigh', label: 'Fracture', icon: 'bone', severity: 3, bleeding: false, splinted: demo === 'stable' },
          { regionLabel: 'Left forearm', label: 'Laceration', icon: 'cut', severity: 2, bleeding: !st.stab, tourniquet: demo === 'stable' },
          { regionLabel: 'Face', label: 'Contusion', icon: 'bruise', severity: 1 },
          { regionLabel: 'Back', label: 'Abrasion', icon: 'scrape', severity: 1 },
          { regionLabel: 'Left knee', label: 'Contusion', icon: 'bruise', severity: 1 },
        ];
      NZA.demo('wounded', {
        L: {}, state: st, injuries, maxChips: 5, pulseLine: true, overlay: true, heartbeat: false, volume: 0.6,
      });
      NZA.apps.wounded.msg.fx({
        mode: st.state, tunnel: st.state === 'arrest' ? 0.9 : (st.stab ? 0.25 : 0.55), bleed: st.bleed,
        unconscious: st.unconscious, cpr: st.status.cpr, stab: st.stab,
      });
      // interactive preview: G calls EMS, hold E to give up
      NZA.mock('wounded:close', { ok: true });
      window.addEventListener('keydown', e => {
        if (e.key.toLowerCase() !== 'g' || e.repeat) return;
        const s = Object.assign({}, A.st, { call: Object.assign({}, A.st.call, { pending: true }) });
        applyState(s);
        setTimeout(() => {
          applyState(Object.assign({}, A.st, { call: { allowed: true, left: 60, called: true, pending: false, medics: 3, ai: false } }));
          flash({ kind: 'ok', text: 'Your call went through to EMS.' });
        }, 700);
      });
      previewHold = NZA.ui.Hold({
        key: 'e', seconds: 3,
        onProgress: p => { if ((A.st.giveUp || {}).left <= since()) NZA.apps.wounded.msg.hold({ p }); },
        onDone: () => flash({ kind: 'bad', text: 'You gave up.' }),
      });
    },
  });
})();
