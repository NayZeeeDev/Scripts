/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · vitals waveforms
     NZA.vitals.wave(type, phase, opts) → -1..1   pure waveform maths
     NZA.vitals.Trace(canvas, { type, rhythm, rate, color, speed, amp, onBeat })
         sweeping trace like a real monitor (erase bar). .set({...}) .stop()
     NZA.vitals.Monitor(host, { compact, traces: ['ecg','pleth','resp'] })
         bedside monitor: traces + HR/SpO2/NIBP/MAP/RR/Temp numbers. .update(vitals) .destroy()
   vitals = { hr, spo2, sys, dia, map, rr, temp, etco2, rhythm, alarm }
   rhythm ∈ sinus stach sbrady afib vf vt pea asystole
   ═══════════════════════════════════════════════════════════ */
(() => {
  const TAU = Math.PI * 2;
  const g = (x, mu, sig) => Math.exp(-((x - mu) * (x - mu)) / (2 * sig * sig));

  // one PQRST complex over phase 0..1
  function pqrst(p, wide = false) {
    const w = wide ? 2.4 : 1;
    return 0.12 * g(p, 0.16, 0.025)                 // P
      - 0.10 * g(p, 0.285, 0.008 * w)               // Q
      + 1.00 * g(p, 0.30, 0.011 * w)                // R
      - 0.22 * g(p, 0.318, 0.010 * w)               // S
      + 0.26 * g(p, 0.52, 0.045);                   // T
  }

  // deterministic noise so traces look alive but stable
  const nz = x => Math.sin(x * 12.9898) * 43758.5453 % 1;
  const smooth = x => { const i = Math.floor(x), f = x - i, a = nz(i), b = nz(i + 1); return a + (b - a) * (f * f * (3 - 2 * f)); };

  function wave(type, t, o = {}) {
    // t = seconds since start, rate = per minute
    const rate = Math.max(1, o.rate || 75);
    const period = 60 / rate;
    const rhythm = o.rhythm || 'sinus';
    if (type === 'ecg') {
      switch (rhythm) {
        case 'asystole': return 0.015 * Math.sin(t * 3.1) + 0.01 * (smooth(t * 9) - 0.5);
        case 'vf': return 0.42 * Math.sin(t * TAU * 4.2 + Math.sin(t * 1.7) * 2.2) * (0.6 + 0.4 * Math.sin(t * 0.9)) + 0.18 * Math.sin(t * TAU * 6.8);
        case 'vt': { const p = (t % (60 / 180)) / (60 / 180); return 0.85 * Math.sin(p * TAU) * (p < 0.85 ? 1 : 0.3); }
        case 'afib': {
          const base = 0.04 * Math.sin(t * TAU * 6.3) + 0.03 * Math.sin(t * TAU * 8.7);
          const jitter = 0.55 + 0.9 * smooth(Math.floor(t / period) * 1.37);
          const per = period * jitter;
          const p = (t % per) / per;
          return base + pqrst(p) - 0.12 * g(p, 0.16, 0.025);
        }
        case 'pea':
        default: {
          const p = (t % period) / period;
          return pqrst(p, rhythm === 'pea' && rate < 50);
        }
      }
    }
    if (type === 'pleth') {
      if (rhythm === 'asystole' || rhythm === 'vf' || rhythm === 'vt' || rhythm === 'pea' || (o.spo2 !== undefined && o.spo2 <= 0)) return 0.02 * Math.sin(t * 2);
      const p = (t % period) / period;
      const amp = o.amp ?? 1;
      return amp * (0.95 * g(p, 0.32, 0.075) + 0.32 * g(p, 0.56, 0.06) - 0.35);
    }
    if (type === 'resp') {
      const rr = Math.max(0, o.rr ?? 14);
      if (rr <= 0) return 0;
      return 0.7 * Math.sin(t * TAU * rr / 60);
    }
    if (type === 'co2') {
      const rr = Math.max(0, o.rr ?? 14);
      if (rr <= 0) return -0.8;
      const per = 60 / rr; const p = (t % per) / per;
      const h = Math.min(1, (o.etco2 ?? 38) / 45);
      if (p < 0.08) return -0.8 + (p / 0.08) * (1.6 * h);
      if (p < 0.55) return -0.8 + 1.6 * h + 0.06 * (p - 0.08);
      if (p < 0.62) return -0.8 + 1.6 * h * (1 - (p - 0.55) / 0.07);
      return -0.8;
    }
    return 0;
  }

  /* ── sweeping trace ── */
  function Trace(canvas, opts = {}) {
    const ctx = canvas.getContext('2d');
    let o = Object.assign({ type: 'ecg', rhythm: 'sinus', rate: 75, rr: 14, spo2: 98, etco2: 38, color: '#3ddc84', speed: 0.25, amp: 1, line: 1.8, gain: 0.38, glow: true, artifact: 0, cprRate: 110 }, opts);
    let raf = 0, last = performance.now(), t = 0, x = 0, prevY = null, lastBeat = -1, running = true;
    let W = 0, H = 0, S = 1;
    const resize = () => {
      const z = (window.NZA && canvas.closest('.nza-app:not(.noscale)')) ? (NZA.zoom || 1) : 1;
      const dpr = window.devicePixelRatio || 1;
      S = z * dpr;
      const w = Math.max(10, Math.round(canvas.clientWidth * S)), h = Math.max(10, Math.round(canvas.clientHeight * S));
      if (w !== W || h !== H) { W = canvas.width = w; H = canvas.height = h; ctx.fillStyle = '#020303'; ctx.fillRect(0, 0, W, H); x = 0; prevY = null; }
    };
    function frame(now) {
      if (!running) return;
      resize();
      const dt = Math.min(0.05, (now - last) / 1000); last = now;
      const pxPerSec = W * o.speed;
      const steps = Math.max(1, Math.round(pxPerSec * dt));
      ctx.lineWidth = o.line * S; ctx.lineCap = 'round'; ctx.strokeStyle = o.color;
      if (o.glow) { ctx.shadowColor = o.color; ctx.shadowBlur = 6 * S; }
      for (let i = 0; i < steps; i++) {
        t += dt / steps;
        // erase bar ahead of the pen
        ctx.shadowBlur = 0; ctx.fillStyle = '#020303'; ctx.fillRect(x, 0, Math.ceil(14 * S), H);
        if (o.glow) ctx.shadowBlur = 6 * S;
        let v = wave(o.type, t, o) * o.amp;
        // chest-compression artefact (CPR running): big rounded deflections at the compression rate
        if (o.artifact > 0 && o.type === 'ecg') { const ph = (t * o.cprRate / 60) % 1; v += o.artifact * 0.55 * Math.sin(Math.PI * Math.min(1, ph / 0.55)) * (ph < 0.55 ? 1 : 0) - o.artifact * 0.12; }
        const y = H * 0.5 - v * H * o.gain;
        if (prevY !== null && x > 0) { ctx.beginPath(); ctx.moveTo(x - 1, prevY); ctx.lineTo(x, y); ctx.stroke(); }
        prevY = y; x += 1;
        if (x >= W) { x = 0; prevY = null; }
        // beat detection for sounds
        if (o.type === 'ecg' && o.onBeat && !['vf', 'asystole'].includes(o.rhythm)) {
          const per = o.rhythm === 'vt' ? 60 / 180 : 60 / Math.max(1, o.rate);
          const beat = Math.floor((t - per * 0.3) / per);
          if (beat !== lastBeat) { lastBeat = beat; if (t > per * 0.3) o.onBeat(); }
        }
      }
      ctx.shadowBlur = 0;
      raf = requestAnimationFrame(frame);
    }
    raf = requestAnimationFrame(frame);
    return {
      set(n) { o = Object.assign(o, n); },
      stop() { running = false; cancelAnimationFrame(raf); },
      start() { if (!running) { running = true; last = performance.now(); raf = requestAnimationFrame(frame); } },
      clear() { ctx.fillStyle = '#020303'; ctx.fillRect(0, 0, W, H); x = 0; prevY = null; },
    };
  }

  /* ── bedside monitor ── */
  function Monitor(host, opts = {}) {
    const o = Object.assign({ traces: ['ecg', 'pleth'], height: 180, beep: true, title: 'ADULT' }, opts);
    const root = document.createElement('div');
    root.className = 'vmon';
    const traceH = Math.round(o.height / o.traces.length);
    const COLORS = { ecg: '#3ddc84', pleth: '#3fd0ff', resp: '#f2d64b', co2: '#f2d64b' };
    const LABEL = { ecg: 'II', pleth: 'PLETH', resp: 'RESP', co2: 'CO₂' };
    root.innerHTML = `
      <div class="trs">${o.traces.map(tp => `<div class="tr" style="height:${traceH}px"><span class="tl">${LABEL[tp]}</span><canvas data-t="${tp}"></canvas></div>`).join('')}</div>
      <div class="nums">
        <div class="nb hr"><span class="k">HR</span><span class="v" data-v="hr">--</span></div>
        <div class="nb sp"><span class="k">SpO₂</span><span class="v" data-v="spo2">--</span></div>
        <div class="nb mp"><span class="k">MAP</span><span class="v" data-v="map">--</span><span class="s" data-v="nibp">--/--</span></div>
        ${o.compact ? '' : '<div class="nb rr"><span class="k">RR</span><span class="v" data-v="rr">--</span></div><div class="nb tp"><span class="k">TEMP</span><span class="v" data-v="temp" style="font-size:20px">--</span></div>'}
      </div>
      <div class="foot"><span>${o.title}</span><span data-v="rhythm"></span><span style="margin-left:auto" data-v="clock"></span></div>`;
    host.appendChild(root);
    const traces = {};
    let vit = {};
    root.querySelectorAll('canvas').forEach(cv => {
      const tp = cv.dataset.t;
      traces[tp] = Trace(cv, { type: tp, color: COLORS[tp], onBeat: tp === 'ecg' && o.beep ? () => { if (window.NZA && NZA.cfg.sounds !== false && root.isConnected && root.offsetParent) NZA.audio.heartbeat(vit.spo2 ?? 98); } : null });
    });
    const q = k => root.querySelector(`[data-v="${k}"]`);
    const clockT = setInterval(() => { const d = new Date(); const c = q('clock'); if (c) c.textContent = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`; }, 1000);
    function update(v = {}) {
      vit = Object.assign(vit, v);
      const r = vit.rhythm || 'sinus';
      const arrest = ['vf', 'vt', 'asystole', 'pea'].includes(r);
      const set = (k, val, alarm) => { const e = q(k); if (!e) return; e.textContent = val; e.parentElement.classList.toggle('alarm', !!alarm); };
      set('hr', r === 'asystole' || r === 'vf' ? '---' : Math.round(vit.hr ?? 0), (vit.hr ?? 75) > 130 || (vit.hr ?? 75) < 45 || arrest);
      set('spo2', arrest || !vit.spo2 ? '--' : Math.round(vit.spo2), (vit.spo2 ?? 98) < 90);
      set('map', arrest ? '--' : Math.round(vit.map ?? 0), (vit.map ?? 80) < 60);
      const nb = q('nibp'); if (nb) nb.textContent = arrest ? '--/--' : `${Math.round(vit.sys ?? 0)}/${Math.round(vit.dia ?? 0)}`;
      set('rr', Math.round(vit.rr ?? 0), (vit.rr ?? 14) < 8 || (vit.rr ?? 14) > 28);
      set('temp', vit.temp ? Number(vit.temp).toFixed(1) : '--', (vit.temp ?? 37) < 35);
      const rh = q('rhythm'); if (rh) rh.textContent = (r === 'sinus' ? '' : r.toUpperCase());
      Object.entries(traces).forEach(([tp, tr]) => tr.set({ rhythm: r, rate: vit.hr || 0, rr: vit.rr ?? 14, spo2: vit.spo2 ?? 98, etco2: vit.etco2 ?? 38, amp: tp === 'pleth' ? Math.max(0.25, Math.min(1, (vit.map ?? 80) / 85)) : 1 }));
    }
    return { el: root, update, traces, destroy() { clearInterval(clockT); Object.values(traces).forEach(t => t.stop()); root.remove(); } };
  }

  window.NZA = window.NZA || {};
  NZA.vitals = { wave, Trace, Monitor, pqrst };
})();
