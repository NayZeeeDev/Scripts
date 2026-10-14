/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · app 'wounded' — the downed HUD ("vital column")
   A column docked on the left edge (top-left, clear of the minimap):
     1. vital card   large bleed-out status ring (60-tick bezel, arc = time left, critical
                     sector, heart glyph that beats with the pulse, rolling counter inside),
                     awareness tag, plain-words headline, live heartbeat trace, state chips
     2. response     EMS response card (status ring + rolling ETA)          only when relevant
     3. injuries     holographic body figure with region diamonds + instrument list
     4. actions      compact vertical key list (crawl / lie still / turn / call / let go)
   Opened from Lua without focus (client/modules/wounded.lua):
     open    { L, state, injuries, maxChips, pulseLine, overlay, heartbeat, volume }
     state   { state, avpu, unconscious, bleed, stab, clock, clockMax, running, rate (clock speed 0..1),
               critical, carried, stretcher, bag, vehicle,
               crawl { enabled, can, why, on, stamina, toggle },
               giveUp { enabled, allowed, left, hold },
               call { allowed, left, called, pending, medics, ai },
               status { cpr, cprBy, treating, onScene }, help { eta, unit, ai, status } | null,
               keys { crawl, stop, left, right, call, giveUp } }
     injuries { list: [{ region, regionLabel, label, icon, severity, bleeding, tourniquet, splinted, treated }], max }
     fx      { mode, tunnel, bleed, unconscious, cpr, stab }   screen overlay + heartbeat
     hold    { kind: 'giveUp', p: 0..1 }                        hold ring on the "let go" row
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
  const reduced = !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
  const TICKS = 60;
  const DIAL_R = 80;                       // arc radius in the 200×200 dial viewBox
  const HEART = '<svg viewBox="0 0 24 24"><path d="M12 21l-7-7C3.5 12.5 2 10.8 2 8.5A5.5 5.5 0 0 1 7.5 3c1.8 0 3 .5 4.5 2 1.5-1.5 2.7-2 4.5-2A5.5 5.5 0 0 1 22 8.5c0 2.3-1.5 4-3 5.5z"/></svg>';
  const TONE_RANK = { red: 4, amber: 3, white: 2, teal: 1 };

  /* holographic body figure (front view; the patient's left is on the viewer's right) */
  const limb = (r, x1, y1, x2, y2, w, extra = '') => `<g class="sg" data-r="${r}"><line class="o" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke-width="${w + 1.5}"/><line class="i" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke-width="${w}"/>${extra}</g>`;
  const hand = (x, y) => `<circle class="s" cx="${x}" cy="${y}" r="2.8"/>`;
  const SCAN = (id, base, line) => `<pattern id="${id}" width="4" height="2.6" patternUnits="userSpaceOnUse"><rect width="4" height="2.6" fill="${base}"/><rect width="4" height=".9" fill="${line}"/></pattern>`;
  const BODY = `
    <svg class="fig" viewBox="0 0 80 160" aria-hidden="true">
      <defs>
        ${SCAN('wdp-base', '#0b2321', 'rgba(15,212,196,.28)')}
        ${SCAN('wdp-red', '#3a1214', 'rgba(255,107,112,.45)')}
        ${SCAN('wdp-amber', '#33270a', 'rgba(243,195,90,.42)')}
        ${SCAN('wdp-white', '#1d2224', 'rgba(255,255,255,.3)')}
        ${SCAN('wdp-teal', '#0c3430', 'rgba(15,212,196,.55)')}
        <radialGradient id="wdp-pad" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="#0fd4c4" stop-opacity=".45"/><stop offset="1" stop-color="#0fd4c4" stop-opacity="0"/></radialGradient>
      </defs>
      <ellipse class="pad" cx="40" cy="153" rx="26" ry="4.5" fill="url(#wdp-pad)"/>
      <ellipse class="pad-ring" cx="40" cy="153" rx="17" ry="2.4"/>
      <g class="segs">
        ${limb('r_upper_arm', 25.5, 33.5, 20.6, 56.5, 6.4)}
        ${limb('r_lower_arm', 20.4, 58.2, 16.8, 80, 5.4, hand(16.3, 84.6))}
        ${limb('l_upper_arm', 54.5, 33.5, 59.4, 56.5, 6.4)}
        ${limb('l_lower_arm', 59.6, 58.2, 63.2, 80, 5.4, hand(63.7, 84.6))}
        ${limb('r_upper_leg', 34.6, 84, 33.9, 114, 8.4)}
        ${limb('r_lower_leg', 33.9, 116.4, 33.3, 145, 6.4, '<path class="s" d="M30.2 145.5h6.2l.4 3.6h-8.6z"/>')}
        ${limb('l_upper_leg', 45.4, 84, 46.1, 114, 8.4)}
        ${limb('l_lower_leg', 46.1, 116.4, 46.7, 145, 6.4, '<path class="s" d="M43.6 145.5h6.2l1.9 3.6h-8.6z"/>')}
        ${limb('neck', 40, 21.5, 40, 29, 5.6)}
        <g class="sg" data-r="pelvis"><path class="s" d="M29.4 69.6Q40 71.8 50.6 69.6L51.6 81.6Q40 86.2 28.4 81.6Z"/></g>
        <g class="sg" data-r="abdomen"><path class="s" d="M27.6 53.4Q40 56 52.4 53.4L50.6 68Q40 70.2 29.4 68Z"/></g>
        <g class="sg" data-r="chest back"><path class="s" d="M26.4 30.6Q40 27.2 53.6 30.6L52.4 51.8Q40 54.4 27.6 51.8Z"/><path class="ln" d="M40 31.5v19M31 41.5q9 2.4 18 0"/></g>
        <g class="sg" data-r="head face"><ellipse class="s" cx="40" cy="12.6" rx="7.8" ry="9.4"/></g>
      </g>
      <g class="mks"></g>
    </svg>`;
  const PTS = {
    head: [40, 8.6], face: [40, 15.4], neck: [40, 25.4],
    chest: [36.6, 40.6], back: [43.6, 46.2],
    abdomen: [40, 61.4], pelvis: [40, 76.2],
    r_upper_arm: [23, 45], r_lower_arm: [18.6, 69.2],
    l_upper_arm: [57, 45], l_lower_arm: [61.4, 69.2],
    r_upper_leg: [34.3, 99], r_lower_leg: [33.6, 130.5],
    l_upper_leg: [45.7, 99], l_lower_leg: [46.4, 130.5],
  };

  const A = {
    st: null, recvAt: 0,
    clockBase: 0, clockAt: 0, maxSeen: 0,
    inj: [], maxChips: 5,
    fx: { mode: 'wounded', tunnel: 0, bleed: 0, unconscious: false, cpr: false, stab: false },
    opts: { pulseLine: true, overlay: true, heartbeat: true, volume: 0.6 },
    hold: 0,
    phase: 0, agonalAt: 0, blipAt: -9,
    etaKey: '', etaMax: 1,
    tone: '', lit: -1, crit: -1,
  };
  let ui = {};
  let odo = null;
  let etaOdo = null;
  let ticker = 0;
  let raf = 0;
  let flashTimer = 0;
  let previewHold = null;
  let previewKeys = null;
  const last = {};

  const setHTML = (key, el, html) => { if (last[key] !== html) { last[key] = html; el.innerHTML = html; } };
  const setText = (el, t) => { if (el.textContent !== t) el.textContent = t; };
  const since = () => (performance.now() - A.recvAt) / 1000;
  const left = v => Math.max(0, Math.ceil((v || 0) - since()));
  const kbd = (k, cls = '') => `<kbd class="${cls}">${esc(k)}</kbd>`;

  /* ─────────────── build ─────────────── */
  function dialTicks() {
    let out = '';
    for (let i = 0; i < TICKS; i++) {
      const a = (i / TICKS) * Math.PI * 2;
      const lg = i % 5 === 0;
      const r1 = lg ? 88.5 : 91, r2 = 96.5;
      const sx = Math.sin(a), cy = Math.cos(a);
      out += `<line class="${lg ? 'lg' : ''}" x1="${(100 + r1 * sx).toFixed(2)}" y1="${(100 - r1 * cy).toFixed(2)}" x2="${(100 + r2 * sx).toFixed(2)}" y2="${(100 - r2 * cy).toFixed(2)}"/>`;
    }
    return out;
  }

  function build(el) {
    el.innerHTML = `
      <div class="wd-fx">
        <div class="wd-vig"></div>
        <div class="wd-edge"></div>
        <div class="wd-lid"></div>
      </div>
      <div class="wd-col">
        <section class="wd-vital nza-hud solid">
          <div class="wd-dial">
            <div class="wd-sheen"></div>
            <svg viewBox="0 0 200 200">
              <g class="ticks">${dialTicks()}</g>
              <circle class="trk" cx="100" cy="100" r="${DIAL_R}"/>
              <circle class="crit" cx="100" cy="100" r="${DIAL_R}" pathLength="100" transform="rotate(-90 100 100)" stroke-dasharray="0 100"/>
              <circle class="arc" cx="100" cy="100" r="${DIAL_R}" pathLength="100" transform="rotate(-90 100 100)" stroke-dasharray="0 100"/>
              <circle class="head" cx="100" cy="${100 - DIAL_R}" r="4.6"/>
            </svg>
            <div class="wd-sonar"></div>
            <div class="wd-core">
              <span class="wd-heart">${HEART}</span>
              <div class="wd-odo"></div>
              <small class="wd-cap"></small>
              <span class="wd-pips"><i></i><i></i><i></i></span>
            </div>
          </div>
          <div class="wd-info">
            <div class="wd-aware"><i></i><span></span></div>
            <h1 class="wd-title"></h1>
            <canvas class="wd-beat"></canvas>
            <div class="wd-chips"></div>
          </div>
          <div class="wd-flash"></div>
        </section>
        <section class="wd-resp nza-hud solid">
          <span class="ri"><svg viewBox="0 0 44 44"><circle class="bg" cx="22" cy="22" r="19"/><circle class="fg" cx="22" cy="22" r="19" pathLength="100" transform="rotate(-90 22 22)" stroke-dasharray="0 100"/></svg><span class="ic"></span></span>
          <div class="tx"><small></small><b></b><p></p></div>
          <div class="eta"><small></small><div class="eo"></div></div>
          <i class="bar"></i>
        </section>
        <section class="wd-inj nza-hud solid">
          <header class="wd-h"><span class="nza-label"></span><b class="wd-cnt"></b></header>
          <div class="wd-injb">
            <div class="wd-body">${BODY}<i class="sweep"></i></div>
            <ul class="wd-list"></ul>
          </div>
        </section>
        <section class="wd-keys nza-hud solid"><ul class="wd-klist"></ul></section>
      </div>`;
    const q = s => el.querySelector(s);
    ui = {
      root: el, fx: q('.wd-fx'), edge: q('.wd-edge'), col: q('.wd-col'),
      vital: q('.wd-vital'), dial: q('.wd-dial'), ticks: [...el.querySelectorAll('.ticks line')],
      crit: q('.wd-dial .crit'), arc: q('.wd-dial .arc'), head: q('.wd-dial .head'), sonar: q('.wd-sonar'),
      heart: q('.wd-heart'), cap: q('.wd-cap'), pips: [...el.querySelectorAll('.wd-pips i')], pipsBox: q('.wd-pips'),
      aware: q('.wd-aware span'), title: q('.wd-title'), beat: q('.wd-beat'), chips: q('.wd-chips'), flash: q('.wd-flash'),
      resp: q('.wd-resp'), respFg: q('.wd-resp .fg'), respIc: q('.wd-resp .ic'), respK: q('.wd-resp .tx small'),
      respT: q('.wd-resp .tx b'), respP: q('.wd-resp .tx p'), respEta: q('.wd-resp .eta'), respEtaK: q('.wd-resp .eta small'), respBar: q('.wd-resp .bar'),
      inj: q('.wd-inj'), injH: q('.wd-inj .nza-label'), injCnt: q('.wd-cnt'), list: q('.wd-list'), mks: q('.wd-body .mks'),
      segs: [...el.querySelectorAll('.wd-body .sg')],
      keys: q('.wd-keys'), klist: q('.wd-klist'),
    };
    odo = NZA.ui.FlipClock(q('.wd-odo'), { value: '00:00' });
    etaOdo = NZA.ui.FlipClock(q('.wd-resp .eo'), { value: '0:00', small: true });
  }

  /* ─────────────── clock ─────────────── */
  function clockValue() {
    const s = A.st;
    if (!s) return 0;
    if (!s.running) return A.clockBase;
    const rate = s.rate === undefined || s.rate === null ? 1 : Math.max(0, Math.min(1, s.rate));
    return Math.max(0, A.clockBase - Math.floor(((performance.now() - A.clockAt) / 1000) * rate));
  }

  function toneOf(s, v) {
    const st = s.status || {};
    if (s.state === 'arrest') return st.cpr ? 'teal' : 'red';
    if (!s.running) return 'teal';
    if (v <= (s.critical || 30) || (s.bleed || 0) >= 2) return 'red';
    if ((s.bleed || 0) === 1) return 'amber';
    return 'white';
  }

  function renderDial() {
    const s = A.st;
    if (!s) return;
    const v = clockValue();
    const max = Math.max(1, s.clockMax || Math.max(300, A.maxSeen));
    const f = Math.max(0, Math.min(1, v / max));
    const tone = toneOf(s, v);
    const st = s.status || {};
    const arrest = s.state === 'arrest';

    if (A.tone !== tone) {
      ui.vital.classList.remove('t-red', 't-amber', 't-teal', 't-white');
      ui.vital.classList.add(`t-${tone}`);
      ui.resp.dataset.vital = tone;
      A.tone = tone;
    }
    const critical = s.running && !arrest && v <= (s.critical || 30);
    ui.vital.classList.toggle('crit', critical || (arrest && !st.cpr));
    ui.vital.classList.toggle('paused', !s.running);

    odo.set(NZA.fmt.time(v));
    odo.tone(tone === 'white' ? '' : tone);
    odo.paused(!s.running);

    ui.arc.setAttribute('stroke-dasharray', `${(f * 100).toFixed(2)} 100`);
    const a = f * Math.PI * 2;
    ui.head.setAttribute('cx', (100 + DIAL_R * Math.sin(a)).toFixed(2));
    ui.head.setAttribute('cy', (100 - DIAL_R * Math.cos(a)).toFixed(2));
    ui.head.style.opacity = f > 0.004 ? '' : '0';
    ui.arc.style.opacity = f > 0.004 ? '' : '0';     // a round cap would draw a dot at 0

    const crit = arrest ? 0 : Math.min(1, (s.critical || 30) / max);
    if (crit !== A.crit) { A.crit = crit; ui.crit.setAttribute('stroke-dasharray', `${(crit * 100).toFixed(2)} 100`); }
    const lit = Math.ceil(f * TICKS - 0.001);
    if (lit !== A.lit) {
      A.lit = lit;
      ui.ticks.forEach((t, i) => t.classList.toggle('on', i < lit));
    }

    let cap;
    if (arrest) cap = st.cpr ? T('clock_cpr', 'CPR holding') : T('clock_arrest', 'No pulse');
    else cap = s.running ? T('clock_bleed', 'Time left') : T('clock_paused', 'On hold');
    setText(ui.cap, cap);

    // bleed pips: how fast the blood is going (no exact numbers are ever shown)
    const b = arrest ? 0 : Math.max(0, Math.min(3, s.bleed || 0));
    ui.pipsBox.style.visibility = (b > 0 || s.stab) && !arrest ? '' : 'hidden';
    ui.pips.forEach((p, i) => { p.className = s.stab ? 'ok' : (i < b ? 'on' : ''); });
  }

  /* ─────────────── headline + chips ─────────────── */
  function awareText(s) {
    if (s.state === 'arrest') return T('aw_arrest', 'No pulse');
    const map = { A: T('aw_A', 'Awake'), V: T('aw_V', 'Drowsy'), P: T('aw_P', 'Fading'), U: T('aw_U', 'Unresponsive') };
    return map[s.avpu] || (s.unconscious ? map.U : map.A);
  }

  function titleText(s) {
    if (s.state === 'arrest') return T('title_arrest', 'Your heart stopped');
    if (s.unconscious) return T('title_unconscious', "You're out cold");
    return T('title_wounded', "You're down");
  }

  function chipList(s) {
    const out = [];
    const st = s.status || {};
    if (s.state === 'arrest') {
      out.push(st.cpr ? ['teal pulse', 'heart', T('st_cpr', 'CPR running')] : ['red', 'pulse', T('st_nocpr', 'Needs CPR now')]);
    } else if (s.stab) {
      out.push(['teal', 'check', T('st_stable', 'Bleeding stopped')]);
    } else if (s.bleed > 0) {
      out.push([s.bleed >= 2 ? 'red' : 'amber', 'drop', T(`st_bleed_${s.bleed}`, ['', 'Slow bleed', 'Bleeding', 'Heavy bleeding'][s.bleed] || 'Bleeding')]);
    }
    if (st.treating && !(s.state === 'arrest' && st.cpr)) out.push(['teal', 'stetho', T('st_treating', 'In care')]);
    else if (st.onScene && !(s.state === 'arrest' && st.cpr)) out.push(['teal', 'user', T('st_onscene', 'Medic with you')]);
    if (s.bag) out.push(['', 'box', T('st_bag', 'In a body bag')]);
    else if (s.stretcher) out.push(['', 'bed', T('st_stretcher', 'On a stretcher')]);
    else if (s.carried) out.push(['', 'hand', T('st_carried', 'Being carried')]);
    else if (s.vehicle) out.push(['', 'ambulance', T('st_vehicle', 'In transport')]);
    return out;
  }

  function renderInfo() {
    const s = A.st;
    if (!s) return;
    setText(ui.aware, awareText(s));
    setText(ui.title, titleText(s));
    setHTML('chips', ui.chips, chipList(s).map(c => `<span class="wd-chip ${c[0]}">${icon(c[1])}<span>${esc(c[2])}</span></span>`).join(''));
  }

  /* ─────────────── response card ─────────────── */
  function helpCard(s) {
    const st = s.status || {};
    const h = s.help;
    const call = s.call || {};
    if (s.state === 'arrest' && st.cpr) {
      return { tone: 'teal', ic: 'heart', t: T('help_cpr', 'Someone is doing CPR'), m: st.cprBy || T('help_cpr_m', 'Hold on. Chest compressions keep the clock from running out.'), live: true };
    }
    if (st.treating) return { tone: 'teal', ic: 'stetho', t: T('help_treating', 'A medic is checking you'), m: st.onScene || '', full: true };
    if (st.onScene || (h && h.status === 'onscene')) return { tone: 'teal', ic: 'ambulance', t: T('help_onscene', 'A medic is here'), m: st.onScene || (h && h.unit) || '', full: true };
    if (h) {
      const eta = (h.eta !== null && h.eta !== undefined) ? left(h.eta) : null;
      return { tone: 'white', ic: 'ambulance', t: h.ai ? T('help_ai', 'AI paramedic on the way') : T('help_enroute', 'Help is coming'), m: h.unit || '', eta, key: `${h.unit || ''}|${h.ai ? 1 : 0}` };
    }
    if (call.called && call.medics === 0 && !call.ai) {
      return { tone: 'amber', ic: 'alert', t: T('help_none', 'No medics on duty'), m: T('help_none_m', 'Your call is saved. Anyone nearby can still help you.'), part: 0.33 };
    }
    if (call.called) {
      const n = call.medics;
      const m = n === 1 ? T('help_medic1', '1 medic on duty') : (n > 1 ? T('help_medics', '%d medics on duty', n) : '');
      return { tone: 'white', ic: 'broadcast', t: T('help_notified', 'Call received'), m, wait: true };
    }
    return null;
  }

  function renderHelp() {
    const s = A.st;
    if (!s) return;
    const c = helpCard(s);
    if (!c) { ui.resp.classList.remove('on'); A.etaKey = ''; return; }
    ui.resp.classList.add('on');
    ui.resp.classList.remove('teal', 'white', 'amber', 'red');
    ui.resp.classList.add(c.tone);
    ui.resp.classList.toggle('live', !!c.live);
    ui.resp.classList.toggle('wait', !!c.wait);
    setHTML('respIc', ui.respIc, icon(c.ic));
    setText(ui.respK, T('help_kicker', 'Emergency response'));
    setText(ui.respT, c.t);
    setText(ui.respP, c.m || '');
    ui.respP.style.display = c.m ? '' : 'none';
    let p = c.full || c.live ? 1 : (c.part || 0);
    if (c.eta !== null && c.eta !== undefined) {
      if (A.etaKey !== c.key) { A.etaKey = c.key; A.etaMax = Math.max(1, c.eta); }
      A.etaMax = Math.max(A.etaMax, c.eta, 1);
      p = Math.max(0.03, 1 - c.eta / A.etaMax);
      ui.respEta.style.display = '';
      setText(ui.respEtaK, T('help_eta', 'Arrives in'));
      etaOdo.set(mmss(c.eta));
      ui.respBar.style.width = `${(p * 100).toFixed(1)}%`;
      ui.respBar.style.display = '';
    } else {
      A.etaKey = '';
      ui.respEta.style.display = 'none';
      ui.respBar.style.display = 'none';
    }
    ui.respFg.setAttribute('stroke-dasharray', `${(p * 100).toFixed(1)} 100`);
    ui.respFg.style.opacity = p > 0.002 || c.wait ? '' : '0';
  }

  /* ─────────────── injuries: body figure + instrument list ─────────────── */
  function injTone(j) {
    if (j.bleeding && !j.tourniquet) return 'red';
    if (j.tourniquet || j.splinted || j.treated) return 'teal';
    return (j.severity || 1) >= 3 ? 'amber' : 'white';
  }

  function injTag(j) {
    if (j.bleeding && !j.tourniquet) return ['red', T('inj_bleeding', 'Bleeding')];
    if (j.tourniquet) return ['teal', T('inj_tq', 'Tourniquet')];
    if (j.splinted) return ['teal', T('inj_splint', 'Splinted')];
    if (j.treated) return ['teal', T('inj_treated', 'Treated')];
    const sv = Math.max(1, Math.min(4, j.severity || 1));
    return [sv >= 3 ? 'amber' : '', T(`sev_${sv}`, ['', 'Minor', 'Moderate', 'Serious', 'Critical'][sv])];
  }

  function renderInj() {
    const raw = Array.isArray(A.inj) ? A.inj : [];
    if (!raw.length) { ui.inj.classList.remove('on'); setHTML('list', ui.list, ''); setHTML('mks', ui.mks, ''); return; }
    ui.inj.classList.add('on');
    const list = raw.map((j, i) => ({ j, i, t: injTone(j) }))
      .sort((a, b) => (TONE_RANK[b.t] - TONE_RANK[a.t]) || ((b.j.severity || 1) - (a.j.severity || 1)) || (a.i - b.i));
    const max = Math.max(1, A.maxChips || 5);
    const shown = list.slice(0, max);
    setText(ui.injH, T('inj_title', 'Injuries'));
    setText(ui.injCnt, String(list.length));
    let rows = shown.map(({ j, t }) => {
      const [tc, tt] = injTag(j);
      return `<li class="${t}"><i class="nt"></i><span class="ic">${icon(j.icon || 'drop')}</span><span class="rg">${esc(j.regionLabel || j.region || '')}</span><span class="ty">${esc(j.label || '')}</span><em class="tg ${tc}">${esc(tt)}</em></li>`;
    }).join('');
    if (list.length > max) rows += `<li class="more"><span>${esc(T('inj_more', '+%d more', list.length - max))}</span></li>`;
    setHTML('list', ui.list, rows);

    // worst tone per region → tint the body segment + one diamond per region
    const worst = {};
    list.forEach(({ j, t }) => {
      const r = j.region;
      if (!r) return;
      if (!worst[r] || TONE_RANK[t] > TONE_RANK[worst[r]]) worst[r] = t;
    });
    ui.segs.forEach(g => {
      let best = null;
      g.dataset.r.split(' ').forEach(r => { const t = worst[r]; if (t && (!best || TONE_RANK[t] > TONE_RANK[best])) best = t; });
      g.setAttribute('class', `sg${best ? ` hit ${best}` : ''}`);
    });
    const mk = Object.keys(worst).filter(r => PTS[r]).map(r => {
      const [x, y] = PTS[r];
      const t = worst[r];
      return `<g class="mk ${t}${r === 'back' ? ' back' : ''}" transform="translate(${x} ${y})">${t === 'red' ? '<circle class="pl" r="4"/>' : ''}<rect class="d" x="-2.6" y="-2.6" width="5.2" height="5.2" transform="rotate(45)"/></g>`;
    }).join('');
    setHTML('mks', ui.mks, mk);
  }

  /* ─────────────── action list ─────────────── */
  const row = (cls, kc, label, sub = '', ex = '') => `<li class="wd-kr ${cls}"><span class="kc">${kc}</span><span class="lb">${label}${sub ? `<small>${sub}</small>` : ''}</span>${ex ? `<span class="ex">${ex}</span>` : ''}</li>`;

  function renderKeys() {
    const s = A.st;
    if (!s) return;
    const k = s.keys || {};
    const c = s.crawl || {};
    const rows = [];
    if (c.enabled && s.state === 'wounded') {
      if (c.can) {
        const st = c.stamina ?? 1;
        const meter = (c.on || st < 0.985)
          ? `<span class="wd-stam ${st < 0.25 ? 'low' : ''}"><i style="width:${Math.round(st * 100)}%"></i></span>` : '';
        rows.push(row(c.on ? 'on' : '', kbd(k.crawl || 'W', c.on ? 'teal' : ''), esc(T('k_crawl', 'Crawl forward')), meter ? esc(T('k_stamina', 'Strength')) : '', meter));
        if (c.toggle !== false) rows.push(row('', kbd(k.stop || 'S'), esc(T('k_stop', 'Lie still'))));
        rows.push(row('', kbd(k.left || 'A') + kbd(k.right || 'D'), esc(T('k_turn', 'Change direction'))));
      } else {
        const held = c.why === 'held';
        rows.push(row('off lockrow', `<span class="lk">${icon(held ? 'hand' : 'lock')}</span>`, esc(held ? T('k_held', 'Someone is moving you') : T('k_nomove', 'Too weak to move'))));
      }
    } else if (s.state === 'arrest' || (c.enabled && !c.can)) {
      rows.push(row('off lockrow', `<span class="lk">${icon('lock')}</span>`, esc(T('k_nomove', 'Too weak to move'))));
    }
    if (rows.length) rows.push('<li class="wd-sep"></li>');

    const call = s.call || {};
    const cl = left(call.left);
    const ck = k.call || 'G';
    if (!call.allowed) rows.push(row('off', kbd(ck), esc(T('k_call', 'Call a medic')), esc(T('k_call_off', 'Someone else has to call'))));
    else if (call.pending) rows.push(row('busy', kbd(ck, 'teal'), esc(T('k_calling', 'Calling…')), '', '<i class="spin"></i>'));
    else if (cl > 0) rows.push(row('done', kbd(ck), esc(T('k_called', 'Medic called')), esc(T('k_again', 'Call again in %s', mmss(cl))), `${icon('check')}`));
    else rows.push(row(call.called ? '' : 'hot', kbd(ck, call.called ? '' : 'teal'), esc(call.called ? T('k_call_again', 'Call again') : T('k_call', 'Call a medic'))));

    const g = s.giveUp || {};
    if (g.enabled && g.allowed) {
      const gl = left(g.left);
      const locked = gl > 0;
      const p = locked ? 0 : A.hold;
      const ring = `<span class="wd-gr"><svg viewBox="0 0 34 34"><circle class="bg" cx="17" cy="17" r="15"/>${p > 0.002 ? `<circle class="fg" cx="17" cy="17" r="15" pathLength="100" transform="rotate(-90 17 17)" stroke-dasharray="${(p * 100).toFixed(1)} 100"/>` : ''}</svg>${kbd(k.giveUp || 'E')}</span>`;
      const sub = locked ? `${icon('lock')}${esc(T('k_locked', 'Unlocks in %s', mmss(gl)))}` : esc(T('k_hold', 'Hold %d s', g.hold || 3));
      rows.push(`<li class="wd-kr give ${locked ? 'off' : ''} ${p > 0 ? 'holding' : ''}"><i class="fill" style="width:${(p * 100).toFixed(1)}%"></i><span class="kc">${ring}</span><span class="lb">${esc(T('k_giveup', 'Let go'))}<small>${sub}</small></span></li>`);
    }
    setHTML('keys', ui.klist, rows.join(''));
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

  /* ─────────────── heartbeat (trace + glyph + sonar + sound + edge pulse) ─────────────── */
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

  function beatGlyph(weak) {
    if (reduced || !ui.heart.animate) return;
    const k = weak ? 1.1 : 1.24;
    ui.heart.animate([{ transform: 'scale(1)' }, { transform: `scale(${k})`, offset: 0.16 }, { transform: 'scale(.96)', offset: 0.34 }, { transform: 'scale(1)' }], { duration: 460, easing: 'ease-out' });
    ui.sonar.animate([{ transform: 'scale(.92)', opacity: weak ? 0.25 : 0.55 }, { transform: 'scale(1.16)', opacity: 0 }], { duration: weak ? 700 : 900, easing: 'cubic-bezier(.2,.7,.2,1)' });
  }

  function drawLine(dt) {
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
      if (now >= A.agonalAt) { A.blipAt = now; A.agonalAt = now + 4 + Math.random() * 5; beatSound(true); beatPulse(0.7); beatGlyph(true); }
    }
    if (beat) { beatSound(false); beatPulse(Math.min(1, 0.35 + (s.bleed || 0) * 0.2)); beatGlyph(false); }

    const cv = ui.beat;
    if (!cv || A.opts.pulseLine === false) return;
    const ctx = cv.getContext('2d');
    const z = NZA.zoom || 1;
    const dpr = window.devicePixelRatio || 1;
    const W = Math.round(cv.clientWidth * z * dpr), H = Math.round(cv.clientHeight * z * dpr);
    if (!W || !H) return;
    if (cv.width !== W || cv.height !== H) { cv.width = W; cv.height = H; A.buf = null; }
    if (!A.buf || A.buf.length !== W) A.buf = new Float32Array(W);
    const per = rate > 0 ? 60 / rate : 1;
    const speed = W / 1.8;                     // px per second
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
    // faint grid behind the trace
    ctx.strokeStyle = 'rgba(255,255,255,.045)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    const gs = Math.round(8 * z * dpr);
    for (let x = W - 1; x > 0; x -= gs) { ctx.moveTo(x + 0.5, 0); ctx.lineTo(x + 0.5, H); }
    ctx.moveTo(0, Math.round(H * 0.58) + 0.5); ctx.lineTo(W, Math.round(H * 0.58) + 0.5);
    ctx.stroke();
    const col = { red: '255,116,120', amber: '243,195,90', teal: '15,212,196', white: '255,255,255' }[A.tone] || '255,255,255';
    const g = ctx.createLinearGradient(0, 0, W, 0);
    g.addColorStop(0, `rgba(${col},0)`);
    g.addColorStop(0.5, `rgba(${col},.5)`);
    g.addColorStop(1, `rgba(${col},1)`);
    ctx.strokeStyle = g;
    ctx.lineWidth = 1.6 * z * dpr;
    ctx.lineJoin = 'round';
    ctx.shadowColor = `rgba(${col},.8)`;
    ctx.shadowBlur = 5 * z * dpr;
    ctx.beginPath();
    for (let x = 0; x < W; x++) {
      const y = H * 0.58 - A.buf[x] * H * 0.44;
      if (x === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    }
    ctx.stroke();
    const yEnd = H * 0.58 - A.buf[W - 1] * H * 0.44;
    ctx.shadowBlur = 9 * z * dpr;
    ctx.fillStyle = `rgba(${col},1)`;
    ctx.beginPath(); ctx.arc(W - 2.5 * z * dpr, yEnd, 2.2 * z * dpr, 0, Math.PI * 2); ctx.fill();
    ctx.shadowBlur = 0;
  }

  function frame() {
    let prev = 0;
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
    renderDial();
    renderInfo();
    renderKeys();
    renderHelp();
  }

  function applyState(d) {
    const prev = A.st;
    const now = performance.now();
    const shown = clockValue();
    A.st = d;
    A.recvAt = now;
    A.maxSeen = Math.max(A.maxSeen, d.clock || 0);
    const rebase = !prev || prev.state !== d.state || prev.running !== d.running || prev.rate !== d.rate || !d.running || Math.abs(shown - d.clock) >= 2;
    if (rebase) { A.clockBase = d.clock; A.clockAt = now; }
    ui.root.classList.toggle('st-arrest', d.state === 'arrest');
    tick();
    renderFx();
  }

  function flash({ kind = 'ok', text = '', ms = 3200 } = {}) {
    if (!text) return;
    const ic = kind === 'ok' ? 'check' : kind === 'bad' ? 'x' : 'alert';
    ui.flash.className = `wd-flash on ${kind}`;
    ui.flash.innerHTML = `<span class="fi">${icon(ic)}</span><span>${esc(text)}</span>`;
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
      A.maxSeen = 0;
      A.tone = '';
      A.lit = -1;
      A.crit = -1;
      A.etaKey = '';
      Object.keys(last).forEach(k => { delete last[k]; });
      ui.beat.style.display = A.opts.pulseLine ? '' : 'none';
      ui.col.classList.remove('in');
      void ui.col.offsetWidth;
      ui.col.classList.add('in');
      if (d.state) applyState(d.state);
      renderInj();
      clearInterval(ticker);
      ticker = setInterval(tick, 250);
      cancelAnimationFrame(raf);
      frame();
    },
    close() {
      clearInterval(ticker);
      cancelAnimationFrame(raf);
      clearTimeout(flashTimer);
      ui.flash.className = 'wd-flash';
      if (previewHold) { previewHold.destroy(); previewHold = null; }
      if (previewKeys) { window.removeEventListener('keydown', previewKeys); previewKeys = null; }
    },
    msg: {
      state(d) { applyState(d); },
      injuries(d) { A.inj = d.list || []; if (d.max) A.maxChips = d.max; renderInj(); },
      fx(d) { A.fx = Object.assign(A.fx, d || {}); renderFx(); },
      hold(d) { A.hold = Math.max(0, Math.min(1, d.p || 0)); renderKeys(); },
      flash(d) { flash(d); },
    },

    /* browser demo: index.html?app=wounded&demo=bleeding|critical|stable|unconscious|arrest|cpr|crawl|help|treat|nomedic|carried */
    preview() {
      const demo = new URLSearchParams(location.search).get('demo') || 'bleeding';
      const keys = { crawl: 'W', stop: 'S', left: 'A', right: 'D', call: 'G', giveUp: 'E' };
      const base = {
        state: 'wounded', avpu: 'A', unconscious: false, bleed: 2, stab: false, clock: 167, clockMax: 300, running: true, critical: 30,
        carried: false, stretcher: false, bag: false, vehicle: false,
        crawl: { enabled: true, can: true, why: null, on: false, stamina: 1, toggle: true },
        giveUp: { enabled: true, allowed: true, left: 38, hold: 3 },
        call: { allowed: true, left: 0, called: false, pending: false, medics: 3, ai: false },
        status: { cpr: false, treating: false, onScene: null },
        help: null, keys,
      };
      const variants = {
        bleeding: {},
        critical: { bleed: 3, clock: 23, avpu: 'V', giveUp: { enabled: true, allowed: true, left: 0, hold: 3 },
          call: { allowed: true, left: 22, called: true, pending: false, medics: 2, ai: false },
          help: { eta: 51, unit: 'Medic 2 · Dana Whitfield', ai: false, status: 'enroute' } },
        stable: { bleed: 0, stab: true, clock: 120, running: false, giveUp: { enabled: true, allowed: true, left: 0, hold: 3 },
          call: { allowed: true, left: 41, called: true, pending: false, medics: 3, ai: false } },
        unconscious: { avpu: 'U', unconscious: true, bleed: 3, clock: 74, crawl: { enabled: true, can: false, why: 'nomove', on: false, stamina: 1 },
          call: { allowed: false, left: 0, called: false, pending: false, medics: 3, ai: false } },
        arrest: { state: 'arrest', clockMax: 300, avpu: 'U', unconscious: true, bleed: 3, clock: 241, crawl: { enabled: true, can: false, why: 'nomove' },
          giveUp: { enabled: true, allowed: true, left: 0, hold: 3 } },
        cpr: { state: 'arrest', clockMax: 300, avpu: 'U', unconscious: true, bleed: 1, clock: 188, running: false, crawl: { enabled: true, can: false, why: 'nomove' },
          status: { cpr: true, cprBy: 'Maya Reyes · Paramedic', treating: true, onScene: 'Maya Reyes' }, giveUp: { enabled: true, allowed: true, left: 0, hold: 3 } },
        crawl: { crawl: { enabled: true, can: true, on: true, stamina: 0.46, toggle: true }, bleed: 1, clock: 212 },
        help: { bleed: 1, clock: 198, call: { allowed: true, left: 47, called: true, pending: false, medics: 2, ai: false },
          help: { eta: 84, unit: 'Unit 04 · Maya Reyes', ai: false, status: 'enroute' } },
        treat: { bleed: 0, stab: true, clock: 143, running: false, crawl: { enabled: true, can: false, why: 'held' },
          status: { cpr: false, treating: true, onScene: 'Maya Reyes · Paramedic' }, giveUp: { enabled: true, allowed: true, left: 0, hold: 3 },
          call: { allowed: true, left: 0, called: true, pending: false, medics: 3, ai: false } },
        nomedic: { call: { allowed: true, left: 52, called: true, pending: false, medics: 0, ai: false } },
        carried: { carried: true, bleed: 1, clock: 205, crawl: { enabled: true, can: false, why: 'held' },
          status: { cpr: false, treating: false, onScene: 'Theo Kane' } },
      };
      const v = variants[demo] || {};
      const st = Object.assign({}, base, v);
      const injuries = demo === 'arrest' || demo === 'cpr'
        ? [
          { region: 'chest', regionLabel: 'Chest', label: 'GSW', icon: 'crosshair', severity: 4, bleeding: demo !== 'cpr', treated: demo === 'cpr' },
          { region: 'abdomen', regionLabel: 'Abdomen', label: 'Internal', icon: 'drop', severity: 3, bleeding: true },
          { region: 'l_upper_leg', regionLabel: 'Left thigh', label: 'GSW', icon: 'crosshair', severity: 2, bleeding: false, tourniquet: true },
          { region: 'head', regionLabel: 'Head', label: 'Contusion', icon: 'bruise', severity: 2 },
        ]
        : [
          { region: 'chest', regionLabel: 'Chest', label: 'GSW', icon: 'crosshair', severity: 3, bleeding: !st.stab, treated: st.stab },
          { region: 'r_upper_leg', regionLabel: 'Right thigh', label: 'Fracture', icon: 'bone', severity: 3, bleeding: false, splinted: demo === 'stable' || demo === 'treat' },
          { region: 'l_lower_arm', regionLabel: 'Left forearm', label: 'Laceration', icon: 'cut', severity: 2, bleeding: !st.stab, tourniquet: demo === 'stable' || demo === 'treat' },
          { region: 'face', regionLabel: 'Face', label: 'Contusion', icon: 'bruise', severity: 1 },
          { region: 'back', regionLabel: 'Back', label: 'Abrasion', icon: 'scrape', severity: 1 },
          { region: 'l_lower_leg', regionLabel: 'Left lower leg', label: 'Contusion', icon: 'bruise', severity: 1 },
        ];
      NZA.demo('wounded', {
        L: {}, state: st, injuries, maxChips: 5, pulseLine: true, overlay: true, heartbeat: false, volume: 0.6,
      });
      NZA.apps.wounded.msg.fx({
        mode: st.state, tunnel: st.state === 'arrest' ? 0.9 : (st.stab ? 0.25 : 0.55), bleed: st.bleed,
        unconscious: st.unconscious, cpr: st.status.cpr, stab: st.stab,
      });
      // interactive preview: G calls EMS, hold E to let go
      NZA.mock('wounded:close', { ok: true });
      if (previewKeys) window.removeEventListener('keydown', previewKeys);
      previewKeys = e => {
        if (e.key.toLowerCase() !== 'g' || e.repeat || !A.st) return;
        applyState(Object.assign({}, A.st, { call: Object.assign({}, A.st.call, { pending: true }) }));
        setTimeout(() => {
          applyState(Object.assign({}, A.st, { call: { allowed: true, left: 60, called: true, pending: false, medics: 3, ai: false } }));
          flash({ kind: 'ok', text: 'Your call reached EMS.' });
        }, 700);
      };
      window.addEventListener('keydown', previewKeys);
      if (previewHold) previewHold.destroy();
      previewHold = NZA.ui.Hold({
        key: 'e', seconds: 3,
        onProgress: p => { if (A.st && (A.st.giveUp || {}).left <= since()) NZA.apps.wounded.msg.hold({ p }); },
        onDone: () => flash({ kind: 'bad', text: 'You let go.' }),
      });
    },
  });
})();
