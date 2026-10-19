/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · monitor — "PM-4" handheld field monitor (HUD overlay)
   Our own device: carry handle on top, alarm light bar, a row of status rings
   (HR / SpO₂ / NIBP / RESP) with rolling values over full-width traces, an
   instrument foot line and rubber keys + a rotary knob along the bottom bezel.
   No brand on the face — model code only. Traces come from NZA.vitals.Trace.

   Lua → JS   open { target?, name?, compact?, position = 'tl'|'tr'|'bl'|'br', nibpAuto = 60 (s, 0 = manual),
                     nibpTime = 4, alarms = true, beep = true, silence = 120, label?, locale? }
              vitals { hr, ecgRate, spo2, sys, dia, map, rr, temp, etco2, rhythm, state, name }
              override { map, sys, dia } | null      (the field resuscitation step's pressure model)
              nibp {}                                 start a cuff cycle now
              compact { on }   position { pos }   locale { ... }   standby { on }   silence {}
   JS → Lua   monitor:bind { target }   (when opened with a target: Lua starts NZA.Patient.Watch)
              monitor:unbind {}         (on close)
              monitor:nibp { sys, dia, map }   (a cuff cycle finished)
   ═══════════════════════════════════════════════════════════ */
(() => {
  let loc = {};
  const L = (k, f) => (loc[`mon_${k}`] !== undefined ? loc[`mon_${k}`] : NZA.t(`field.mon_${k}`, f));
  const esc = NZA.esc;
  const ARREST = ['vf', 'vt', 'asystole', 'pea'];
  const RHYTHM = { sinus: 'SINUS', stach: 'S.TACH', sbrady: 'S.BRADY', afib: 'AFIB', vf: 'VF', vt: 'VT', pea: 'PEA', asystole: 'ASYSTOLE' };
  const COL = { ecg: '#3ddc84', pleth: '#3fd0ff', co2: '#f2d64b' };
  const pad = n => String(n).padStart(2, '0');
  const clamp = NZA.clamp;

  const M = {
    root: null, o: {}, live: {}, nibp: null, override: null, cuff: null, traces: {}, odo: {},
    power: true, silenceUntil: 0, alarmAt: 0, alarmIdx: 0, timers: [], nextNibp: 0, nibpAt: 0,
  };

  /* ── status ring: 270° sweep, gap at the bottom ── */
  const SWEEP = 75;   // % of the circle (pathLength 100)
  function ringSVG() {
    let ticks = '';
    for (let i = 0; i <= 10; i++) {
      const a = (135 + (270 * i) / 10) * Math.PI / 180;
      const r1 = i % 5 ? 40.5 : 39.5, r2 = 43;
      ticks += `<line x1="${(46 + Math.cos(a) * r1).toFixed(2)}" y1="${(46 + Math.sin(a) * r1).toFixed(2)}" x2="${(46 + Math.cos(a) * r2).toFixed(2)}" y2="${(46 + Math.sin(a) * r2).toFixed(2)}"/>`;
    }
    return `<svg viewBox="0 0 92 92" class="rg">
      <g class="tk">${ticks}</g>
      <circle class="rt" cx="46" cy="46" r="34" pathLength="100" stroke-dasharray="${SWEEP} 100" transform="rotate(135 46 46)"/>
      <circle class="rz" cx="46" cy="46" r="34" pathLength="100" stroke-dasharray="0 100" transform="rotate(135 46 46)"/>
      <circle class="rf" cx="46" cy="46" r="34" pathLength="100" stroke-dasharray="0 100" transform="rotate(135 46 46)"/>
      <circle class="rn" cx="46" cy="12" r="2.6"/>
    </svg>`;
  }
  function ringSet(tile, f, zone) {
    if (!tile) return;
    const fill = clamp(f, 0, 1) * SWEEP;
    tile.querySelector('.rf').setAttribute('stroke-dasharray', `${fill.toFixed(2)} 100`);
    const z = tile.querySelector('.rz');
    if (zone) {
      const a = clamp(zone[0], 0, 1) * SWEEP, b = clamp(zone[1], 0, 1) * SWEEP;
      z.setAttribute('stroke-dasharray', `0 ${a.toFixed(2)} ${(b - a).toFixed(2)} 100`);
    } else z.setAttribute('stroke-dasharray', '0 100');
    // the bright nib rides the end of the fill
    const ang = (135 + 270 * clamp(f, 0, 1)) * Math.PI / 180;
    const n = tile.querySelector('.rn');
    n.setAttribute('cx', (46 + Math.cos(ang) * 34).toFixed(2));
    n.setAttribute('cy', (46 + Math.sin(ang) * 34).toFixed(2));
    n.style.opacity = f > 0.005 ? 1 : 0;
  }

  function tileHTML(k, label, unit) {
    return `<div class="pm-ring ${k}" data-k="${k}">
      <span class="pk"><b>${label}</b><i>${unit}</i></span>
      <div class="pr">${ringSVG()}<span class="pv"></span></div>
      <span class="ps"></span>
    </div>`;
  }

  function build(host, o) {
    host.innerHTML = '';
    teardownTraces();
    const compact = !!o.compact;
    const wrap = NZA.el('div', `mon nza-int pos-${o.position || 'tl'} ${compact ? 'compact' : ''}`);
    wrap.innerHTML = `
      <div class="pm-handle"><i></i></div>
      <div class="pm-body">
        <i class="pm-bump tl"></i><i class="pm-bump tr"></i><i class="pm-bump bl"></i><i class="pm-bump br"></i>
        <div class="pm-lamp"><i></i></div>
        <div class="pm-plate">
          <span class="pm-model"><b>PM-4</b><span>${esc(L('type', 'Field monitor'))}</span></span>
          <span class="pm-screws"><i></i><i></i></span>
          <span class="pm-leds"><span class="pm-led pwr" title=""></span><span class="pm-led al"></span></span>
        </div>
        <div class="pm-screen">
          <div class="pm-head">
            <span class="pm-al"></span>
            <span class="pm-pt"><em>${esc(L('adult', 'Adult'))}</em><span class="pname"></span></span>
            <span class="pm-rhy"></span>
            <span class="pm-bat"><i></i></span>
            <span class="pm-clock">--:--</span>
          </div>
          <div class="pm-rings">
            ${tileHTML('hr', 'HR', 'bpm')}
            ${tileHTML('sp', 'SpO₂', '%')}
            ${tileHTML('bp', esc(L('nibp', 'NIBP')), 'mmHg')}
            ${compact ? '' : tileHTML('rr', 'RESP', '/min')}
          </div>
          <div class="pm-trs">
            <div class="pm-tr ecg"><span class="tl">II</span><span class="sc">×1</span><canvas data-t="ecg"></canvas></div>
            <div class="pm-tr pleth"><span class="tl">PLETH</span><canvas data-t="pleth"></canvas></div>
            ${compact ? '' : '<div class="pm-tr co2"><span class="tl">CO₂</span><canvas data-t="co2"></canvas></div>'}
          </div>
          <div class="pm-foot">
            <span class="fi tp"><em>${esc(L('temp', 'Temp'))}</em><b>--</b><i>°C</i></span>
            <span class="fi et"><em>EtCO₂</em><b>--</b><i>mmHg</i></span>
            <span class="fi nb"><em>${esc(L('nibp', 'NIBP'))}</em><b class="when">--</b></span>
            <span class="fi au"><b class="auto"></b></span>
          </div>
          <div class="pm-off"><b>PM-4</b><span class="st">${esc(L('standby', 'Standby'))}</span><span class="bar"><i></i></span></div>
          <i class="pm-glass"></i>
        </div>
        <div class="pm-keys">
          <button class="pm-key pwr" data-b="power">${NZA.icon('power')}<span class="tip">${esc(L('btn_power', 'Power'))}</span></button>
          <button class="pm-key" data-b="silence">${NZA.icon('mute')}<span class="tip">${esc(L('btn_silence', 'Silence alarms'))}</span></button>
          <button class="pm-key" data-b="nibp">${NZA.icon('cuff')}<span class="tip">${esc(L('btn_nibp', 'Measure BP now'))}</span></button>
          <span class="pm-grille"></span>
          <span class="pm-sticker"><b>!</b>${esc(L('sticker', 'Defib-proof leads only'))}</span>
          <button class="pm-knob" data-b="size"><i></i><span class="tip">${esc(L('btn_size', 'Display size'))}</span></button>
        </div>
      </div>`;
    host.appendChild(wrap);
    M.root = wrap;
    wrap.querySelectorAll('[data-b]').forEach(b => b.addEventListener('click', () => button(b.dataset.b)));
    // rolling values
    M.odo = {};
    wrap.querySelectorAll('.pm-ring').forEach(t => { M.odo[t.dataset.k] = NZA.ui.FlipClock(t.querySelector('.pv'), { value: '--' }); });
    // traces
    wrap.querySelectorAll('.pm-tr canvas').forEach(cv => {
      const tp = cv.dataset.t;
      M.traces[tp] = NZA.vitals.Trace(cv, { type: tp, color: COL[tp], gain: tp === 'ecg' ? 0.36 : 0.32 });
    });
    const tr = M.traces.ecg;
    if (tr) {
      const hr = wrap.querySelector('.pm-ring.hr');
      tr.set({ onBeat: () => {
        if (!M.power) return;
        hr.classList.remove('beat'); void hr.offsetWidth; hr.classList.add('beat');
        if (M.o.beep !== false && NZA.cfg.sounds !== false) NZA.audio.heartbeat(M.live.spo2 ?? 98);
      } });
    }
    if (!M.power) { wrap.classList.add('off'); Object.values(M.traces).forEach(t => t.stop()); }
    head(); render(); nibpRow(); alarms(true);
  }

  function teardownTraces() {
    Object.values(M.traces).forEach(t => t.stop());
    M.traces = {};
  }

  function head() {
    if (!M.root) return;
    M.root.querySelector('.pname').textContent = M.o.label || M.o.name || M.live.name || '';
    const d = new Date();
    M.root.querySelector('.pm-clock').textContent = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }

  /* ── numbers, rings & traces ── */
  function arrested() {
    const r = M.live.rhythm || 'sinus';
    return M.live.state === 'arrest' || M.live.state === 'dead' || ARREST.includes(r);
  }
  const num = v => (v === undefined || v === null || Number.isNaN(Number(v)) ? null : Math.round(Number(v)));
  function tile(k) { return M.root ? M.root.querySelector(`.pm-ring.${k}`) : null; }
  function setVal(k, txt, tone) {
    const t = tile(k);
    if (!t) return;
    if (M.odo[k]) M.odo[k].set(String(txt));
    t.classList.toggle('alarm', tone === 'alarm');
  }

  function render() {
    if (!M.root) return;
    const v = M.live, r = v.rhythm || 'sinus', arrest = arrested();
    const rate = num(v.ecgRate ?? v.hr);
    // HR
    const hrTxt = rate === null ? '--' : (r === 'asystole' || r === 'vf') ? '---' : rate;
    setVal('hr', hrTxt, rate !== null && (arrest || rate > 130 || (rate > 0 && rate < 45)) ? 'alarm' : '');
    ringSet(tile('hr'), rate ? rate / 200 : 0, [50 / 200, 120 / 200]);
    tile('hr').querySelector('.ps').innerHTML = `${esc(L('limits', 'Lim'))} <b>45–130</b>`;
    // SpO2
    const sp = num(v.spo2);
    setVal('sp', arrest || !sp ? '--' : sp, sp && sp < 90 ? 'alarm' : '');
    ringSet(tile('sp'), arrest || !sp ? 0 : (sp - 60) / 40, [(94 - 60) / 40, 1]);
    tile('sp').querySelector('.ps').innerHTML = arrest || !sp ? esc(L('no_pulse_wave', 'No pleth')) : `${esc(L('limits', 'Lim'))} <b>90</b>`;
    // NIBP (intermittent) — while the cuff runs the ring shows the cuff pressure
    const bp = tile('bp');
    if (M.cuff) {
      bp.classList.add('cuff'); bp.classList.remove('alarm', 'stale');
      M.odo.bp.set(String(Math.round(M.cuff.p)));
      ringSet(bp, M.cuff.p / 260, null);
      bp.querySelector('.ps').textContent = M.cuff.phase === 'inflate' ? L('inflating', 'Cuff filling') : L('deflating', 'Reading');
    } else {
      bp.classList.remove('cuff');
      const n = M.nibp;
      setVal('bp', n ? n.map : '--', n && n.map < 60 ? 'alarm' : '');
      ringSet(bp, n ? (n.map - 20) / 120 : 0, [(65 - 20) / 120, (100 - 20) / 120]);
      bp.querySelector('.ps').innerHTML = n ? `<b>${n.sys}/${n.dia}</b> ${esc(L('map_short', 'MAP'))}` : esc(L('no_reading', 'No reading'));
      bp.classList.toggle('stale', !!n && (Date.now() - M.nibpAt) > Math.max(90, (M.o.nibpAuto || 60) * 1.5) * 1000);
    }
    // RESP + EtCO2
    const rr = num(v.rr), et = num(v.etco2);
    if (tile('rr')) {
      setVal('rr', rr === null ? '--' : rr, rr !== null && (rr <= 0 || rr > 30 || rr < 8) ? 'alarm' : '');
      ringSet(tile('rr'), rr ? rr / 40 : 0, [10 / 40, 24 / 40]);
      tile('rr').querySelector('.ps').innerHTML = et === null ? '' : `EtCO₂ <b>${et}</b>`;
    }
    const q = s => M.root.querySelector(s);
    const tp = q('.fi.tp b'); if (tp) { tp.textContent = v.temp ? Number(v.temp).toFixed(1) : '--'; q('.fi.tp').classList.toggle('bad', !!v.temp && v.temp < 35); }
    const ee = q('.fi.et b'); if (ee) { ee.textContent = et === null ? '--' : et; q('.fi.et').classList.toggle('bad', !arrest && et !== null && et > 0 && (et < 20 || et > 55)); }
    const rh = q('.pm-rhy'); rh.textContent = RHYTHM[r] || r.toUpperCase(); rh.classList.toggle('bad', ARREST.includes(r));
    // traces
    Object.entries(M.traces).forEach(([tpn, tr]) => tr.set({ rhythm: r, rate: rate || 0, rr: v.rr ?? 14, spo2: v.spo2 ?? 98, etco2: v.etco2 ?? 38,
      amp: tpn === 'pleth' ? Math.max(0.25, Math.min(1, ((M.override || {}).map ?? v.map ?? 80) / 85)) : 1 }));
  }

  /* ── NIBP cuff ── */
  function nibpRow() {
    if (!M.root) return;
    const when = M.root.querySelector('.when');
    if (M.cuff) when.textContent = L('measuring', 'measuring');
    else if (M.nibpAt) {
      const s = Math.round((Date.now() - M.nibpAt) / 1000);
      when.textContent = s < 60 ? L('ago_s', '{n} s ago').replace('{n}', s) : L('ago_m', '{n} min ago').replace('{n}', Math.floor(s / 60));
    } else when.textContent = L('no_reading', 'No reading');
    const auto = M.root.querySelector('.auto');
    const au = M.root.querySelector('.fi.au');
    if (M.o.nibpAuto > 0 && M.nextNibp && !M.cuff) { auto.textContent = `${L('auto', 'Auto')} ${NZA.fmt.time(Math.max(0, (M.nextNibp - Date.now()) / 1000))}`; au.style.display = ''; }
    else { auto.textContent = ''; au.style.display = 'none'; }
    M.root.querySelector('.fi.nb').classList.toggle('ovr', !!M.override);
    const btn = M.root.querySelector('[data-b="nibp"]');
    if (btn) btn.classList.toggle('busy', !!M.cuff);
  }

  function startNibp() {
    if (!M.power || M.cuff) return false;
    const dur = Math.max(1.5, M.o.nibpTime || 4) * 1000;
    M.cuff = { phase: 'inflate', p: 0, t0: performance.now(), dur };
    NZA.audio.tone(320, 120, { vol: 0.03, type: 'triangle' });
    const tick = () => {
      const c = M.cuff;
      if (!c) return;
      const t = (performance.now() - c.t0) / c.dur;
      const src = M.override || M.live;
      const top = Math.max(140, (src.sys || 110) + 35);
      if (t < 0.35) { c.phase = 'inflate'; c.p = top * (t / 0.35); }
      else if (t < 1) { c.phase = 'deflate'; c.p = top - (top - Math.max(20, (src.dia || 60) - 10)) * ((t - 0.35) / 0.65); c.p = Math.round(c.p / 6) * 6; }
      else { finishNibp(); return; }
      render();
      c.raf = requestAnimationFrame(tick);
    };
    M.cuff.raf = requestAnimationFrame(tick);
    nibpRow(); render();
    return true;
  }
  function finishNibp() {
    const src = M.override || M.live;
    M.cuff = null;
    if (arrested() || !src.sys) {
      M.nibp = null;
      NZA.audio.tone(240, 200, { vol: 0.05, type: 'square' });
    } else {
      M.nibp = { sys: Math.round(src.sys), dia: Math.round(src.dia), map: Math.round(src.map || (src.dia + (src.sys - src.dia) / 3)) };
      NZA.audio.tone(980, 70, { vol: 0.04 }); NZA.audio.tone(980, 70, { vol: 0.04, at: 0.12 });
      NZA.post('monitor:nibp', M.nibp);
    }
    M.nibpAt = Date.now();
    if (M.o.nibpAuto > 0) M.nextNibp = Date.now() + M.o.nibpAuto * 1000;
    render(); nibpRow(); alarms(true);
  }

  /* ── alarms ── */
  function evalAlarms() {
    const v = M.live, out = [];
    if (!M.power || v.hr === undefined) return out;
    const r = v.rhythm || 'sinus';
    if (arrested()) {
      out.push({ lv: 3, key: 'arrest', text: `${L('al_arrest', 'Arrest')} · ${RHYTHM[r] || r.toUpperCase()}` });
      return out;
    }
    const rate = v.ecgRate ?? v.hr;
    if (v.spo2 !== undefined && v.spo2 < 90) out.push({ lv: v.spo2 < 85 ? 2 : 1, key: 'desat', text: L('al_desat', 'SpO₂ low') });
    if (M.nibp && M.nibp.map < 60) out.push({ lv: M.nibp.map < 50 ? 2 : 1, key: 'hypo', text: L('al_hypo', 'Pressure low') });
    if (v.rr !== undefined && v.rr <= 0) out.push({ lv: 2, key: 'apnoea', text: L('al_apnoea', 'No breathing') });
    if (rate > 130) out.push({ lv: rate > 150 ? 2 : 1, key: 'tachy', text: L('al_tachy', 'Heart rate high') });
    if (rate > 0 && rate < 50) out.push({ lv: rate < 40 ? 2 : 1, key: 'brady', text: L('al_brady', 'Heart rate low') });
    if (v.rr > 30) out.push({ lv: 1, key: 'tachypnoea', text: L('al_tachypnoea', 'Breathing fast') });
    if (v.etco2 !== undefined && v.etco2 > 0 && v.etco2 < 20) out.push({ lv: 1, key: 'etco2', text: L('al_etco2', 'EtCO₂ low') });
    if (v.temp && v.temp < 35) out.push({ lv: 1, key: 'cold', text: L('al_cold', 'Body temp low') });
    out.sort((a, b) => b.lv - a.lv);
    return out;
  }
  function alarms(noSound) {
    if (!M.root) return;
    const list = evalAlarms();
    const chip = M.root.querySelector('.pm-al');
    const lamp = M.root.querySelector('.pm-lamp');
    const led = M.root.querySelector('.pm-led.al');
    const muted = Date.now() < M.silenceUntil;
    M.root.querySelector('[data-b="silence"]').classList.toggle('on', muted);
    M.root.querySelector('.pm-led.pwr').classList.toggle('off', !M.power);
    if (!list.length) {
      chip.className = 'pm-al'; chip.innerHTML = '';
      lamp.className = 'pm-lamp'; led.className = 'pm-led al';
      return;
    }
    M.alarmIdx = (M.alarmIdx + 1) % list.length;
    const a = list[Math.min(M.alarmIdx, list.length - 1)];
    const top = list[0];
    chip.className = `pm-al on l${a.lv} ${muted ? 'muted' : ''}`;
    const left = muted ? Math.ceil((M.silenceUntil - Date.now()) / 1000) : 0;
    chip.innerHTML = `${muted ? NZA.icon('mute') : NZA.icon('bell')}<span>${esc(a.text)}</span>${list.length > 1 ? `<i>+${list.length - 1}</i>` : ''}${muted ? `<i>${NZA.fmt.time(left)}</i>` : ''}`;
    lamp.className = `pm-lamp on l${top.lv >= 2 ? 2 : 1} ${muted ? 'muted' : ''}`;
    led.className = `pm-led al ${top.lv >= 2 ? 'red' : 'amber'}`;
    if (noSound || muted || M.o.alarms === false || NZA.cfg.sounds === false) return;
    const now = Date.now();
    const every = top.lv >= 2 ? 3000 : 6500;
    if (now - M.alarmAt >= every) { M.alarmAt = now; NZA.audio.alarm(top.lv >= 2 ? 2 : 1); }
  }

  /* ── keys ── */
  function setPower(on) {
    M.power = !!on;
    if (!M.root) return;
    M.root.classList.toggle('off', !M.power);
    Object.values(M.traces).forEach(t => (M.power ? t.start() : t.stop()));
    if (M.power) {
      M.root.classList.remove('boot'); void M.root.offsetWidth; M.root.classList.add('boot');
      setTimeout(() => M.root && M.root.classList.remove('boot'), 1300);
      NZA.audio.tone(660, 90, { vol: 0.05 }); NZA.audio.tone(990, 120, { vol: 0.05, at: 0.12 });
      if (M.o.nibpAuto > 0) M.nextNibp = Date.now() + 2500;
    } else {
      if (M.cuff) { cancelAnimationFrame(M.cuff.raf); M.cuff = null; }
      NZA.audio.tone(440, 160, { vol: 0.05, slide: 220 });
    }
    alarms(true); nibpRow(); render();
  }
  function button(b) {
    NZA.audio.click(520);
    const k = M.root && M.root.querySelector(`[data-b="${b}"]`);
    if (k) { k.classList.remove('press'); void k.offsetWidth; k.classList.add('press'); }
    if (b === 'power') return setPower(!M.power);
    if (!M.power) return;
    if (b === 'silence') {
      M.silenceUntil = Date.now() < M.silenceUntil ? 0 : Date.now() + (M.o.silence || 120) * 1000;
      return alarms(true);
    }
    if (b === 'nibp') return startNibp();
    if (b === 'size') { M.o.compact = !M.o.compact; build(M.root.parentElement, M.o); }
  }

  function loop() {
    head(); nibpRow(); alarms(false);
    if (M.power && M.o.nibpAuto > 0 && M.nextNibp && Date.now() >= M.nextNibp && !M.cuff && M.live.hr !== undefined) startNibp();
  }

  function teardown() {
    M.timers.forEach(clearInterval); M.timers = [];
    if (M.cuff) { cancelAnimationFrame(M.cuff.raf); M.cuff = null; }
    teardownTraces();
    if (M.root) { M.root.remove(); M.root = null; }
  }

  NZA.app('monitor', {
    escClose: false,
    init(el) { this.host = el; },
    open(d) {
      teardown();
      M.o = Object.assign({ position: 'tl', nibpAuto: 60, nibpTime: 4, alarms: true, beep: true, silence: 120 }, d || {});
      if (d && d.locale) loc = Object.assign({}, loc, d.locale);
      M.live = {}; M.nibp = null; M.nibpAt = 0; M.override = null; M.power = true; M.silenceUntil = 0;
      M.nextNibp = M.o.nibpAuto > 0 ? Date.now() + 2500 : 0;
      build(this.host, M.o);
      M.timers.push(setInterval(loop, 1000));
      if (d && d.vitals) this.msg.vitals(d.vitals);
      if (d && d.target && NZA.inGame) NZA.post('monitor:bind', { target: d.target });
    },
    close() {
      teardown();
      if (NZA.inGame) NZA.post('monitor:unbind', {});
    },
    msg: {
      vitals(v) {
        if (!v) return;
        const first = M.live.hr === undefined;
        M.live = Object.assign(M.live, v);
        if (v.name && !M.o.name) { M.o.name = v.name; head(); }
        render();
        if (first) { alarms(true); if (M.o.nibpAuto > 0) M.nextNibp = Math.min(M.nextNibp || Infinity, Date.now() + 1200); }
      },
      override(o) { M.override = o && o.map ? o : null; nibpRow(); render(); },
      nibp() { startNibp(); },
      compact(d) { M.o.compact = !!(d && d.on); if (M.root) build(M.root.parentElement, M.o); },
      position(d) { M.o.position = (d && d.pos) || 'tl'; if (M.root) M.root.className = M.root.className.replace(/pos-\w+/, `pos-${M.o.position}`); },
      standby(d) { setPower(!(d && d.on)); },
      silence() { button('silence'); },
      locale(d) { loc = Object.assign({}, loc, d || {}); if (M.root) build(M.root.parentElement, M.o); },
    },
    preview() {
      const big = !/compact/.test(location.hash);
      NZA.open('monitor', { name: 'Pavel Lindqvist', position: 'tl', nibpAuto: 20, nibpTime: 2.5, compact: !big });
      let t = 0;
      const base = { hr: 131, ecgRate: 131, spo2: 88, sys: 94, dia: 57, map: 69, rr: 24, temp: 35.4, etco2: 31, rhythm: 'stach', state: 'wounded' };
      const push = () => {
        t += 1;
        const w = Math.sin(t / 7);
        NZA.apps.monitor.msg.vitals(Object.assign({}, base, { hr: 131 + Math.round(w * 3), ecgRate: 131 + Math.round(w * 3), spo2: 88 + Math.round(w), sys: 94 + Math.round(w * 2) }));
      };
      push(); setInterval(push, 1000);
      setTimeout(() => startNibp(), 300);
    },
  });

  // other modules / previews may want the alarm list
  NZA.monitorAlarms = () => evalAlarms();
})();
