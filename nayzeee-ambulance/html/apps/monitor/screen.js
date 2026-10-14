/* NAYZEEE AMBULANCE · monitor prop screen (DUI) — see screen.html */
(() => {
  const cv = document.getElementById('scr');
  const c = cv.getContext('2d');
  const W = 512, H = 256;
  const ARREST = ['vf', 'vt', 'asystole', 'pea'];
  let v = {}, nibp = null, ovr = null, t = 0, last = performance.now();
  const traces = [
    { type: 'ecg', y: 30, h: 70, color: '#3ddc84', x: 0, prev: null, label: 'II' },
    { type: 'pleth', y: 112, h: 58, color: '#3fd0ff', x: 0, prev: null, label: 'PLETH' },
    { type: 'co2', y: 182, h: 50, color: '#f2d64b', x: 0, prev: null, label: 'CO2' },
  ];
  const TW = 318;
  c.fillStyle = '#020303'; c.fillRect(0, 0, W, H);

  window.addEventListener('message', e => {
    let d = e.data;
    if (typeof d === 'string') { try { d = JSON.parse(d); } catch (err) { return; } }
    if (!d || typeof d !== 'object') return;
    if (d.vitals) v = Object.assign(v, d.vitals);
    if (d.nibp) nibp = d.nibp;
    if (d.override !== undefined) ovr = d.override || null;
  });

  function numbers() {
    c.fillStyle = '#020303'; c.fillRect(TW + 2, 0, W - TW - 2, H); c.fillRect(0, 0, TW, 22);
    c.fillStyle = 'rgba(255,255,255,.08)'; c.fillRect(TW + 1, 0, 1, H); c.fillRect(0, 22, TW, 1);
    c.font = '700 11px Lexend'; c.fillStyle = 'rgba(255,255,255,.55)'; c.textAlign = 'left';
    c.fillText('NAYZEEE  ·  ADULT', 8, 15);
    const d = new Date(); c.textAlign = 'right';
    c.fillText(`${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`, TW - 6, 15);
    const arrest = ARREST.includes(v.rhythm) || v.state === 'arrest';
    const blink = Math.floor(t * 2) % 2 === 0;
    const box = (y, k, val, col, alarm, sub) => {
      c.textAlign = 'left'; c.font = '700 11px Lexend'; c.fillStyle = col; c.globalAlpha = 0.85; c.fillText(k, TW + 10, y + 14); c.globalAlpha = 1;
      c.textAlign = 'right'; c.font = '700 46px "JetBrains Mono"'; c.fillStyle = alarm && blink ? '#ff4a4f' : col; c.fillText(val, W - 10, y + 54);
      if (sub) { c.font = '700 14px "JetBrains Mono"'; c.fillStyle = '#fff'; c.textAlign = 'left'; c.fillText(sub, TW + 10, y + 54); }
    };
    const rate = v.ecgRate ?? v.hr;
    box(4, 'HR', rate === undefined ? '--' : (arrest && (v.rhythm === 'vf' || v.rhythm === 'asystole') ? '---' : Math.round(rate)), '#3ddc84', arrest || rate > 130 || (rate > 0 && rate < 45));
    box(86, 'SpO2', arrest || !v.spo2 ? '--' : Math.round(v.spo2), '#3fd0ff', v.spo2 < 90);
    const n = nibp;
    box(168, 'NIBP', n ? Math.round(n.map) : '--', '#0fd4c4', n && n.map < 60, n ? `${Math.round(n.sys)}/${Math.round(n.dia)}` : '--/--');
    c.fillStyle = 'rgba(255,255,255,.06)'; c.fillRect(TW + 2, 84, W - TW, 1); c.fillRect(TW + 2, 166, W - TW, 1);
    if (arrest) { c.fillStyle = blink ? '#c92a2f' : '#7a1a1d'; c.fillRect(110, 3, 120, 17); c.fillStyle = '#fff'; c.font = '700 11px Lexend'; c.textAlign = 'center'; c.fillText(`ARREST · ${String(v.rhythm || '').toUpperCase()}`, 170, 15); }
  }

  function frame(now) {
    const dt = Math.min(0.05, (now - last) / 1000); last = now; t += dt;
    const px = Math.max(1, Math.round(TW * 0.25 * dt));
    traces.forEach(tr => {
      for (let i = 0; i < px; i++) {
        const tt = t - dt + (i / px) * dt;
        c.fillStyle = '#020303'; c.fillRect(tr.x, tr.y, 10, tr.h);
        const val = NZA.vitals.wave(tr.type, tt, { rhythm: v.rhythm || 'sinus', rate: (v.ecgRate ?? v.hr) || 0, rr: v.rr ?? 14, spo2: v.spo2 ?? 98, etco2: v.etco2 ?? 38, amp: 1 });
        const y = tr.y + tr.h / 2 - val * tr.h * 0.42;
        if (tr.prev !== null && tr.x > 0) { c.strokeStyle = tr.color; c.lineWidth = 2; c.beginPath(); c.moveTo(tr.x - 1, tr.prev); c.lineTo(tr.x, y); c.stroke(); }
        tr.prev = y; tr.x += 1;
        if (tr.x >= TW) { tr.x = 0; tr.prev = null; }
      }
      c.font = '700 9px Lexend'; c.fillStyle = 'rgba(255,255,255,.4)'; c.textAlign = 'left'; c.fillText(tr.label, 6, tr.y + 10);
    });
    numbers();
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);

  if (/demo=1/.test(location.search)) {
    v = { hr: 138, ecgRate: 138, spo2: 96, rr: 22, etco2: 33, rhythm: 'stach', state: 'wounded' };
    nibp = { sys: 89, dia: 53, map: 65 };
  }
})();
