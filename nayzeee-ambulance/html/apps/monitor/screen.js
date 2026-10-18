/* NAYZEEE AMBULANCE · monitor prop screen (DUI) — see screen.html
   Same screen grammar as the PM-4 overlay: header strip, a row of status rings
   (HR / SpO₂ / NIBP / RESP) and full-width ECG + PLETH sweeps under them. No brand. */
(() => {
  const cv = document.getElementById('scr');
  const c = cv.getContext('2d');
  const W = 512, H = 256;
  const BG = '#020303';
  const ARREST = ['vf', 'vt', 'asystole', 'pea'];
  const RHY = { sinus: 'SINUS', stach: 'S.TACH', sbrady: 'S.BRADY', afib: 'AFIB', vf: 'VF', vt: 'VT', pea: 'PEA', asystole: 'ASYSTOLE' };
  let v = {}, nibp = null, ovr = null, t = 0, last = performance.now(), loc = {}, beatAt = -1, lastBeat = -1;
  const L = (k, f) => (loc[`field.mon_${k}`] !== undefined ? loc[`field.mon_${k}`] : (loc[`mon_${k}`] !== undefined ? loc[`mon_${k}`] : f));
  const HEAD = 20, RING_Y = HEAD + 2, RING_H = 104, TOP_TR = RING_Y + RING_H + 2;
  const traces = [
    { type: 'ecg', y: TOP_TR, h: 64, color: '#3ddc84', x: 0, prev: null, label: 'II' },
    { type: 'pleth', y: TOP_TR + 66, h: 50, color: '#3fd0ff', x: 0, prev: null, label: 'PLETH' },
  ];
  const TW = W;
  c.fillStyle = BG; c.fillRect(0, 0, W, H);

  window.addEventListener('message', e => {
    let d = e.data;
    if (typeof d === 'string') { try { d = JSON.parse(d); } catch (err) { return; } }
    if (!d || typeof d !== 'object') return;
    if (d.vitals) v = Object.assign(v, d.vitals);
    if (d.name) v.name = d.name;
    if (d.locale && typeof d.locale === 'object') loc = Object.assign(loc, d.locale);
    if (d.nibp) nibp = d.nibp;
    if (d.override !== undefined) ovr = d.override || null;
  });

  // faint grid behind the sweeps (drawn under the trace each column as it is erased)
  function gridCol(x, y, h) {
    c.fillStyle = BG; c.fillRect(x, y, 8, h);
    c.fillStyle = 'rgba(255,255,255,.05)';
    for (let gx = Math.ceil(x / 16) * 16; gx < x + 8; gx += 16) c.fillRect(gx, y, 1, h);
    for (let gy = y; gy < y + h; gy += 16) c.fillRect(x, gy, 8, 1);
  }

  function ring(cx, cy, r, f, color, zone, label, unit, value, sub, alarm, blink) {
    const A0 = 135 * Math.PI / 180, SW = 270 * Math.PI / 180;
    c.lineCap = 'round';
    // ticks
    c.strokeStyle = 'rgba(255,255,255,.16)'; c.lineWidth = 1;
    for (let i = 0; i <= 10; i++) {
      const a = A0 + SW * i / 10, r1 = r + 6, r2 = r + (i % 5 ? 8 : 10);
      c.beginPath(); c.moveTo(cx + Math.cos(a) * r1, cy + Math.sin(a) * r1); c.lineTo(cx + Math.cos(a) * r2, cy + Math.sin(a) * r2); c.stroke();
    }
    c.strokeStyle = 'rgba(255,255,255,.08)'; c.lineWidth = 5; c.beginPath(); c.arc(cx, cy, r, A0, A0 + SW); c.stroke();
    if (zone) { c.globalAlpha = 0.22; c.strokeStyle = color; c.lineWidth = 9; c.lineCap = 'butt'; c.beginPath(); c.arc(cx, cy, r, A0 + SW * zone[0], A0 + SW * zone[1]); c.stroke(); c.globalAlpha = 1; c.lineCap = 'round'; }
    const col = alarm ? '#ff5a5f' : color;
    if (f > 0.005) {
      c.shadowColor = col; c.shadowBlur = 8; c.strokeStyle = col; c.lineWidth = 5;
      c.beginPath(); c.arc(cx, cy, r, A0, A0 + SW * Math.min(1, f)); c.stroke(); c.shadowBlur = 0;
      const a = A0 + SW * Math.min(1, f);
      c.fillStyle = '#fff'; c.beginPath(); c.arc(cx + Math.cos(a) * r, cy + Math.sin(a) * r, 2.6, 0, Math.PI * 2); c.fill();
    }
    c.textAlign = 'left'; c.font = '800 10px Lexend'; c.fillStyle = col; c.fillText(label, cx - 56, RING_Y + 13);
    c.textAlign = 'right'; c.font = '600 8px "JetBrains Mono"'; c.fillStyle = 'rgba(255,255,255,.35)'; c.fillText(unit, cx + 56, RING_Y + 13);
    c.textAlign = 'center'; c.font = '700 26px "JetBrains Mono"'; c.fillStyle = alarm && blink ? '#ff9a9d' : col; c.fillText(value, cx, cy + 9);
    if (sub) { c.font = '700 10px "JetBrains Mono"'; c.fillStyle = 'rgba(255,255,255,.75)'; c.fillText(sub, cx, RING_Y + RING_H - 6); }
  }

  function top() {
    c.fillStyle = BG; c.fillRect(0, 0, W, TOP_TR - 1);
    c.fillStyle = 'rgba(255,255,255,.025)'; c.fillRect(0, 0, W, HEAD);
    c.fillStyle = 'rgba(255,255,255,.07)'; c.fillRect(0, HEAD, W, 1); c.fillRect(0, TOP_TR - 2, W, 1);
    for (let i = 1; i < 4; i++) c.fillRect(i * 128, RING_Y + 4, 1, RING_H - 8);
    const arrest = ARREST.includes(v.rhythm) || v.state === 'arrest' || v.state === 'dead';
    const blink = Math.floor(t * 2) % 2 === 0;
    const r = v.rhythm || 'sinus';
    // header
    c.textAlign = 'left'; c.font = '700 9px Lexend'; c.fillStyle = 'rgba(255,255,255,.12)'; c.fillRect(6, 5, 38, 11);
    c.fillStyle = 'rgba(255,255,255,.62)'; c.fillText(String(L('adult', 'Adult')).toUpperCase(), 10, 14);
    c.font = '700 10px Lexend'; c.fillStyle = 'rgba(255,255,255,.86)'; c.fillText(String(v.name || '').toUpperCase().slice(0, 26), 52, 14);
    const d = new Date(); c.textAlign = 'right'; c.font = '700 10px "JetBrains Mono"'; c.fillStyle = 'rgba(255,255,255,.62)';
    c.fillText(`${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`, W - 8, 14);
    c.fillStyle = ARREST.includes(r) ? '#ff6b70' : '#3ddc84'; c.fillText(RHY[r] || r.toUpperCase(), W - 50, 14);
    if (arrest) {
      c.fillStyle = blink ? '#c92a2f' : '#7a1a1d'; c.fillRect(196, 3, 150, 14);
      c.fillStyle = '#fff'; c.font = '800 9px Lexend'; c.textAlign = 'center'; c.fillText(`${String(L('al_arrest', 'Arrest')).toUpperCase()} · ${RHY[r] || r.toUpperCase()}`, 271, 13);
    }
    // rings
    const cy = RING_Y + 54, R = 30;
    const rate = v.ecgRate ?? v.hr;
    const hrTxt = rate === undefined ? '--' : (r === 'asystole' || r === 'vf') ? '---' : Math.round(rate);
    const beat = t - beatAt < 0.18;
    ring(64, cy, beat ? R + 1 : R, rate ? rate / 200 : 0, '#3ddc84', [0.25, 0.6], 'HR', 'bpm', hrTxt, '', arrest || rate > 130 || (rate > 0 && rate < 45), blink);
    const sp = arrest || !v.spo2 ? null : Math.round(v.spo2);
    ring(192, cy, R, sp ? (sp - 60) / 40 : 0, '#3fd0ff', [0.85, 1], 'SpO2', '%', sp ?? '--', '', sp && sp < 90, blink);
    const n = nibp;
    ring(320, cy, R, n ? (n.map - 20) / 120 : 0, '#0fd4c4', [0.375, 0.667], 'NIBP', 'mmHg', n ? Math.round(n.map) : '--', n ? `${Math.round(n.sys)}/${Math.round(n.dia)}` : '--/--', n && n.map < 60, blink);
    const rr = v.rr === undefined ? null : Math.round(v.rr);
    ring(448, cy, R, rr ? rr / 40 : 0, '#f2d64b', [0.25, 0.6], 'RESP', '/min', rr ?? '--', v.etco2 !== undefined ? `EtCO2 ${Math.round(v.etco2)}` : '', rr !== null && (rr <= 0 || rr > 30), blink);
  }

  function frame(now) {
    const dt = Math.min(0.05, (now - last) / 1000); last = now; t += dt;
    const px = Math.max(1, Math.round(TW * 0.25 * dt));
    const rate = (v.ecgRate ?? v.hr) || 0;
    traces.forEach(tr => {
      for (let i = 0; i < px; i++) {
        const tt = t - dt + (i / px) * dt;
        gridCol(tr.x, tr.y, tr.h);
        const val = NZA.vitals.wave(tr.type, tt, { rhythm: v.rhythm || 'sinus', rate, rr: v.rr ?? 14, spo2: v.spo2 ?? 98, etco2: v.etco2 ?? 38,
          amp: tr.type === 'pleth' ? Math.max(0.25, Math.min(1, ((ovr || {}).map ?? v.map ?? 80) / 85)) : 1 });
        const y = tr.y + tr.h / 2 - val * tr.h * 0.4;
        if (tr.prev !== null && tr.x > 0) { c.strokeStyle = tr.color; c.lineWidth = 2; c.shadowColor = tr.color; c.shadowBlur = 5; c.beginPath(); c.moveTo(tr.x - 1, tr.prev); c.lineTo(tr.x, y); c.stroke(); c.shadowBlur = 0; }
        tr.prev = y; tr.x += 1;
        if (tr.x >= TW) { tr.x = 0; tr.prev = null; }
      }
      c.fillStyle = 'rgba(2,3,3,.85)'; c.fillRect(4, tr.y + 3, tr.label.length * 6 + 8, 12);
      c.font = '800 8px Lexend'; c.fillStyle = tr.color; c.textAlign = 'left'; c.fillText(tr.label, 8, tr.y + 12);
    });
    // beat flash for the HR ring
    if (rate > 0 && !['vf', 'asystole'].includes(v.rhythm)) {
      const per = v.rhythm === 'vt' ? 60 / 180 : 60 / Math.max(1, rate);
      const b = Math.floor((t - per * 0.3) / per);
      if (b !== lastBeat) { lastBeat = b; beatAt = t; }
    }
    top();
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);

  if (/demo=1/.test(location.search)) {
    v = { hr: 138, ecgRate: 138, spo2: 96, rr: 22, etco2: 33, rhythm: 'stach', state: 'wounded', name: 'Michael Garcia' };
    nibp = { sys: 89, dia: 53, map: 65 };
  }
})();
