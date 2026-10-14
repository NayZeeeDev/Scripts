/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · monitor — rugged NAYZEEE patient monitor
   NZA.vitals.Monitor (ECG / PLETH / CO₂ traces + numbers) in a device frame with
   an alarm banner, an intermittent NIBP cuff and side hardware buttons
   (power, alarm silence, cycle NIBP, size).

   Lua → JS   open { target?, name?, compact?, position = 'tl'|'tr'|'bl'|'br', nibpAuto = 60 (s, 0 = manual),
                     nibpTime = 4, alarms = true, beep = true, silence = 120, label?, locale? }
              vitals { hr, ecgRate, spo2, sys, dia, map, rr, temp, etco2, rhythm, state, name }
              override { map, sys, dia } | null      (the field resuscitation step's pressure model)
              nibp {}                                 start a cuff cycle now
              compact { on }   position { pos }   locale { ... }   standby { on }
   JS → Lua   monitor:bind { target }   (when opened with a target: Lua starts NZA.Patient.Watch)
              monitor:unbind {}         (on close)
              monitor:nibp { sys, dia, map }   (a cuff cycle finished)
   ═══════════════════════════════════════════════════════════ */
(() => {
  let loc = {};
  const L = (k, f) => (loc[`mon_${k}`] !== undefined ? loc[`mon_${k}`] : NZA.t(`field.mon_${k}`, f));
  const ARREST = ['vf', 'vt', 'asystole', 'pea'];
  const RHYTHM = { sinus: 'SINUS', stach: 'S.TACH', sbrady: 'S.BRADY', afib: 'AFIB', vf: 'VF', vt: 'VT', pea: 'PEA', asystole: 'ASYSTOLE' };
  const pad = n => String(n).padStart(2, '0');

  const M = {
    root: null, o: {}, mon: null, live: {}, nibp: null, override: null, cuff: null,
    power: true, silenceUntil: 0, alarmAt: 0, alarmIdx: 0, timers: [], nextNibp: 0, nibpAt: 0,
  };

  function el(tag, cls, html) { return NZA.el(tag, cls, html); }

  function build(host, o) {
    host.innerHTML = '';
    const wrap = el('div', `mon nza-int pos-${o.position || 'tl'} ${o.compact ? 'compact' : ''}`);
    wrap.innerHTML = `
      <div class="mon-dev dev">
        <div class="mon-top"><div class="dev-brand"><span class="nz-mark"></span>NAYZEEE · ${NZA.esc(L('brand', 'Vitals'))}</div><span class="mon-model">VX-7</span><span class="dev-led"></span></div>
        <div class="mon-body">
          <div class="mon-screen dev-screen">
            <div class="mon-head"><span>${NZA.esc(L('adult', 'Adult'))}</span><span class="pname"></span><span class="rhy"></span><span class="bat"><i></i></span><span class="clock">--:--</span></div>
            <div class="mon-alarm"></div>
            <div class="mon-vm"></div>
            <div class="mon-nibp"><span class="cuff">${NZA.icon('cuff')}<b class="ct">${NZA.esc(L('nibp', 'NIBP'))}</b></span><span class="bar"><i></i></span><span class="ovr">${NZA.esc(L('live', 'Field'))}</span><span class="when">--</span><span class="auto"></span></div>
            <div class="mon-off"><span class="nz-mark"></span><span class="st">${NZA.esc(L('standby', 'Standby'))}</span></div>
          </div>
          <div class="mon-btns">
            <button class="dev-btn pwr" data-b="power">${NZA.icon('power')}<span class="tip">${NZA.esc(L('btn_power', 'Power'))}</span></button>
            <button class="dev-btn" data-b="silence">${NZA.icon('mute')}<span class="tip">${NZA.esc(L('btn_silence', 'Silence alarms'))}</span></button>
            <button class="dev-btn" data-b="nibp">${NZA.icon('cuff')}<span class="tip">${NZA.esc(L('btn_nibp', 'Cycle NIBP'))}</span></button>
            <button class="dev-btn" data-b="size">${NZA.icon('grid')}<span class="tip">${NZA.esc(L('btn_size', 'Display size'))}</span></button>
            <span class="dev-led led"></span>
          </div>
        </div>
      </div>`;
    host.appendChild(wrap);
    M.root = wrap;
    wrap.querySelectorAll('.mon-btns .dev-btn').forEach(b => b.addEventListener('click', () => button(b.dataset.b)));
    mountMonitor();
    head();
  }

  function mountMonitor() {
    const host = M.root.querySelector('.mon-vm');
    if (M.mon) { M.mon.destroy(); M.mon = null; }
    host.innerHTML = '';
    const compact = !!M.o.compact;
    M.mon = NZA.vitals.Monitor(host, {
      traces: compact ? ['ecg', 'pleth'] : ['ecg', 'pleth', 'co2'],
      height: compact ? 132 : 198, beep: false, compact: false, title: '',
    });
    const nums = M.mon.el.querySelector('.nums');
    const co = el('div', 'nb co', `<span class="k">EtCO₂<span class="lim">mmHg</span></span><span class="v" data-v="etco2">--</span>`);
    nums.appendChild(co);
    const set = (sel, txt) => { const k = M.mon.el.querySelector(sel); if (k) k.innerHTML = txt; };
    set('.nb.hr .k', `HR<span class="lim">bpm</span>`);
    set('.nb.sp .k', `SpO₂<span class="lim">%</span>`);
    set('.nb.mp .k', `<span>NIBP</span><span class="lim">MAP</span>`);
    set('.nb.rr .k', `RR<span class="lim">/min</span>`);
    set('.nb.tp .k', `TEMP<span class="lim">°C</span>`);
    // heartbeat dot on the HR box
    const tr = M.mon.traces.ecg;
    if (tr) {
      const hr = M.mon.el.querySelector('.nb.hr');
      tr.set({ onBeat: () => {
        hr.classList.add('beat'); setTimeout(() => hr.classList.remove('beat'), 140);
        if (M.power && M.o.beep !== false && NZA.cfg.sounds !== false) NZA.audio.heartbeat(M.live.spo2 ?? 98);
      } });
    }
    render();
  }

  function head() {
    if (!M.root) return;
    M.root.querySelector('.pname').textContent = M.o.label || M.o.name || M.live.name || '';
    const d = new Date();
    M.root.querySelector('.clock').textContent = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }

  /* ── numbers & traces ── */
  function arrested() {
    const r = M.live.rhythm || 'sinus';
    return M.live.state === 'arrest' || M.live.state === 'dead' || ARREST.includes(r);
  }
  function render() {
    if (!M.mon || !M.root) return;
    const v = M.live;
    const rate = v.ecgRate ?? v.hr;
    const n = M.nibp;
    M.mon.update({
      hr: rate ?? 0, spo2: v.spo2, rr: v.rr, temp: v.temp, etco2: v.etco2, rhythm: v.rhythm || 'sinus',
      sys: n ? n.sys : 0, dia: n ? n.dia : 0, map: n ? n.map : (v.map ?? 80),
    });
    const q = s => M.mon.el.querySelector(s);
    const et = q('[data-v="etco2"]');
    if (et) {
      et.textContent = v.etco2 === undefined ? '--' : Math.round(v.etco2);
      et.parentElement.classList.toggle('alarm', !arrested() && v.etco2 !== undefined && (v.etco2 < 20 || v.etco2 > 55));
    }
    if (!n) {
      const mp = q('[data-v="map"]'); if (mp) { mp.textContent = '--'; mp.parentElement.classList.remove('alarm'); }
      const nb = q('[data-v="nibp"]'); if (nb) nb.textContent = '--/--';
    }
    const mpBox = q('.nb.mp');
    if (mpBox) mpBox.classList.toggle('stale', !!n && (Date.now() - M.nibpAt) > Math.max(90, (M.o.nibpAuto || 60) * 1.5) * 1000);
    const rhy = M.root.querySelector('.rhy');
    const r = v.rhythm || 'sinus';
    rhy.textContent = RHYTHM[r] || r.toUpperCase();
    rhy.style.color = ARREST.includes(r) ? '#ff6b70' : 'rgba(255,255,255,.55)';
  }

  /* ── NIBP cuff ── */
  function nibpRow() {
    if (!M.root) return;
    const row = M.root.querySelector('.mon-nibp');
    const c = M.cuff;
    row.classList.toggle('busy', !!c);
    row.classList.toggle('ovr', !!M.override);
    const bar = row.querySelector('.bar i');
    const ct = row.querySelector('.ct');
    if (c) {
      ct.textContent = `${c.phase === 'inflate' ? L('inflating', 'Cuff inflating') : L('deflating', 'Measuring')} ${Math.round(c.p)}`;
      bar.style.width = `${Math.min(100, (c.p / 220) * 100)}%`;
    } else {
      ct.textContent = L('nibp', 'NIBP');
      bar.style.width = '0%';
    }
    const when = row.querySelector('.when');
    if (M.nibpAt) {
      const s = Math.round((Date.now() - M.nibpAt) / 1000);
      when.textContent = s < 60 ? L('ago_s', '{n} s ago').replace('{n}', s) : L('ago_m', '{n} min ago').replace('{n}', Math.floor(s / 60));
    } else when.textContent = L('no_reading', 'no reading');
    const auto = row.querySelector('.auto');
    if (M.o.nibpAuto > 0 && M.nextNibp && !c) auto.textContent = `${L('auto', 'auto')} ${NZA.fmt.time(Math.max(0, (M.nextNibp - Date.now()) / 1000))}`;
    else auto.textContent = '';
    const btn = M.root.querySelector('.dev-btn[data-b="nibp"]');
    if (btn) btn.classList.toggle('busy', !!c);
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
      nibpRow();
      c.raf = requestAnimationFrame(tick);
    };
    M.cuff.raf = requestAnimationFrame(tick);
    nibpRow();
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
    if (v.spo2 !== undefined && v.spo2 < 90) out.push({ lv: v.spo2 < 85 ? 2 : 1, key: 'desat', text: L('al_desat', 'Desaturating') });
    if (M.nibp && M.nibp.map < 60) out.push({ lv: M.nibp.map < 50 ? 2 : 1, key: 'hypo', text: L('al_hypo', 'Hypotension') });
    if (v.rr !== undefined && v.rr <= 0) out.push({ lv: 2, key: 'apnoea', text: L('al_apnoea', 'Apnoea') });
    if (rate > 130) out.push({ lv: rate > 150 ? 2 : 1, key: 'tachy', text: L('al_tachy', 'Tachycardia') });
    if (rate > 0 && rate < 50) out.push({ lv: rate < 40 ? 2 : 1, key: 'brady', text: L('al_brady', 'Bradycardia') });
    if (v.rr > 30) out.push({ lv: 1, key: 'tachypnoea', text: L('al_tachypnoea', 'Tachypnoea') });
    if (v.etco2 !== undefined && v.etco2 > 0 && v.etco2 < 20) out.push({ lv: 1, key: 'etco2', text: L('al_etco2', 'Low EtCO₂') });
    if (v.temp && v.temp < 35) out.push({ lv: 1, key: 'cold', text: L('al_cold', 'Hypothermia') });
    out.sort((a, b) => b.lv - a.lv);
    return out;
  }
  function alarms(noSound) {
    if (!M.root) return;
    const list = evalAlarms();
    const ban = M.root.querySelector('.mon-alarm');
    const led = M.root.querySelector('.mon-top .dev-led');
    const muted = Date.now() < M.silenceUntil;
    const sil = M.root.querySelector('.dev-btn[data-b="silence"]');
    sil.classList.toggle('on', muted);
    if (!list.length) {
      ban.className = 'mon-alarm';
      led.className = `dev-led ${M.power ? '' : 'off'}`;
      return;
    }
    M.alarmIdx = (M.alarmIdx + 1) % list.length;
    const a = list[Math.min(M.alarmIdx, list.length - 1)];
    const top = list[0];
    ban.className = `mon-alarm on l${a.lv} ${muted ? 'muted' : ''}`;
    const left = muted ? Math.ceil((M.silenceUntil - Date.now()) / 1000) : 0;
    ban.innerHTML = `${muted ? NZA.icon('mute') : NZA.icon('alert')}<span>${NZA.esc(a.text)}</span>${list.length > 1 ? `<span class="cnt">+${list.length - 1}</span>` : ''}${muted ? `<span class="cnt">${NZA.fmt.time(left)}</span>` : ''}`;
    led.className = `dev-led ${top.lv >= 2 ? 'red' : ''}`;
    if (noSound || muted || M.o.alarms === false || NZA.cfg.sounds === false) return;
    const now = Date.now();
    const every = top.lv >= 2 ? 3000 : 6500;
    if (now - M.alarmAt >= every) { M.alarmAt = now; NZA.audio.alarm(top.lv >= 2 ? 2 : 1); }
  }

  /* ── buttons ── */
  function setPower(on) {
    M.power = !!on;
    if (!M.root) return;
    M.root.classList.toggle('off', !M.power);
    Object.values(M.mon ? M.mon.traces : {}).forEach(t => (M.power ? t.start() : t.stop()));
    if (M.power) {
      M.root.classList.add('boot'); setTimeout(() => M.root && M.root.classList.remove('boot'), 1100);
      NZA.audio.tone(660, 90, { vol: 0.05 }); NZA.audio.tone(990, 120, { vol: 0.05, at: 0.12 });
      if (M.o.nibpAuto > 0) M.nextNibp = Date.now() + 2500;
    } else {
      if (M.cuff) { cancelAnimationFrame(M.cuff.raf); M.cuff = null; }
      NZA.audio.tone(440, 160, { vol: 0.05, slide: 220 });
    }
    alarms(true); nibpRow();
  }
  function button(b) {
    NZA.audio.click(520);
    if (b === 'power') return setPower(!M.power);
    if (!M.power) return;
    if (b === 'silence') {
      M.silenceUntil = Date.now() < M.silenceUntil ? 0 : Date.now() + (M.o.silence || 120) * 1000;
      return alarms(true);
    }
    if (b === 'nibp') return startNibp();
    if (b === 'size') { M.o.compact = !M.o.compact; M.root.classList.toggle('compact', M.o.compact); mountMonitor(); }
  }

  function loop() {
    head(); nibpRow(); alarms(false);
    if (M.power && M.o.nibpAuto > 0 && M.nextNibp && Date.now() >= M.nextNibp && !M.cuff && M.live.hr !== undefined) startNibp();
  }

  function teardown() {
    M.timers.forEach(clearInterval); M.timers = [];
    if (M.cuff) { cancelAnimationFrame(M.cuff.raf); M.cuff = null; }
    if (M.mon) { M.mon.destroy(); M.mon = null; }
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
        if (v.name && !M.o.name) M.o.name = v.name;
        render();
        if (first) { alarms(true); if (M.o.nibpAuto > 0) M.nextNibp = Math.min(M.nextNibp || Infinity, Date.now() + 1200); }
      },
      override(o) { M.override = o && o.map ? o : null; nibpRow(); },
      nibp() { startNibp(); },
      compact(d) { M.o.compact = !!(d && d.on); if (M.root) { M.root.classList.toggle('compact', M.o.compact); mountMonitor(); } },
      position(d) { M.o.position = d && d.pos || 'tl'; if (M.root) M.root.className = M.root.className.replace(/pos-\w+/, `pos-${M.o.position}`); },
      standby(d) { setPower(!(d && d.on)); },
      silence() { button('silence'); },
      locale(d) { loc = Object.assign({}, loc, d || {}); if (M.root) { const h = M.root.parentElement; build(h, M.o); } },
    },
    preview() {
      NZA.open('monitor', { name: 'Michael Garcia', position: 'tl', nibpAuto: 20, nibpTime: 2.5 });
      let t = 0;
      const base = { hr: 138, ecgRate: 138, spo2: 88, sys: 89, dia: 53, map: 65, rr: 24, temp: 35.4, etco2: 31, rhythm: 'stach', state: 'wounded' };
      const push = () => {
        t += 1;
        const w = Math.sin(t / 7);
        NZA.apps.monitor.msg.vitals(Object.assign({}, base, { hr: 138 + Math.round(w * 3), ecgRate: 138 + Math.round(w * 3), spo2: 88 + Math.round(w), sys: 89 + Math.round(w * 2) }));
      };
      push(); setInterval(push, 1000);
      setTimeout(() => startNibp(), 300);
    },
  });

  // other modules / previews may want the alarm list
  NZA.monitorAlarms = () => evalAlarms();
})();
