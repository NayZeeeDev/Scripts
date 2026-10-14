/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · waiting area board (DUI)
   Left rail: hospital, rolling clock, status rings (beds open / staff / queue), units en
   route. Right: bed bay map (called beds pulse) and one lane per triage level with the
   queue numbers in call order. A called number takes over the screen with a ring sweep.
   Messages from client/modules/checkin_tv.lua (SendDuiMessage, JSON string):
     { type: 'init', locale, clock, w, h }
     { type: 'board', board, mine, title, clock }   board = NZA.Checkin.Board(hospital)
     { type: 'mine', mine }   { type: 'clock', clock }   { type: 'chime', volume }   { type: 'standby' }
   ═══════════════════════════════════════════════════════════ */
(() => {
  const $ = s => document.querySelector(s);
  const tv = $('#tv');
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const pad = n => String(Math.max(0, Math.floor(n))).padStart(2, '0');
  const mmss = s => { s = Math.max(0, Math.floor(s || 0)); return s >= 3600 ? `${Math.floor(s / 3600)}:${pad((s % 3600) / 60)}:${pad(s % 60)}` : `${pad(s / 60)}:${pad(s % 60)}`; };
  let L = {};
  const tr = (k, f) => (L[k] !== undefined && L[k] !== '' ? L[k] : f);
  const fmtS = (s, ...a) => { let i = 0; return String(s).replace(/%[sd]/g, () => (a[i] !== undefined ? a[i++] : '')); };

  const SV = 'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"';
  const ICON = {
    ambulance: `<svg ${SV}><path d="M3 17V8a1 1 0 0 1 1-1h10v10M14 10h4l3 3.5V17h-2"/><path d="M6 17h8"/><circle cx="7.5" cy="17.5" r="1.7"/><circle cx="17" cy="17.5" r="1.7"/><path d="M8.5 9.5v4M6.5 11.5h4"/></svg>`,
    bed: `<svg ${SV}><path d="M3 18V7M21 18v-5a3 3 0 0 0-3-3h-8v5"/><path d="M3 14h18"/><circle cx="6.5" cy="10.5" r="1.6"/></svg>`,
    heart: `<svg ${SV}><path d="M12 20s-7-4.4-9-9.2C1.7 7.4 4 4.5 7.1 4.5c2 0 3.6 1.2 4.9 3 1.3-1.8 2.9-3 4.9-3 3.1 0 5.4 2.9 4.1 6.3C19 15.6 12 20 12 20z"/></svg>`,
    user: `<svg ${SV}><circle cx="12" cy="8" r="3.6"/><path d="M5 20c.8-3.6 3.6-5.6 7-5.6s6.2 2 7 5.6"/></svg>`,
    arrow: `<svg ${SV}><path d="M5 12h14M13 6l6 6-6 6"/></svg>`,
    bolt: `<svg ${SV}><path d="M13 3 5 13.5h6L10 21l8-10.5h-6z"/></svg>`,
    ticket: `<svg ${SV}><path d="M4 6h16v4a2 2 0 0 0 0 4v4H4v-4a2 2 0 0 0 0-4z"/><path d="M13 6v12" stroke-dasharray="2 2"/></svg>`,
  };

  const S = { board: null, now: Date.now() / 1000, recv: performance.now(), clock: { mode: 'real' }, clockRecv: performance.now(), mine: null, title: null, flashTimer: 0, lastCalled: null, audio: null, clockText: '' };
  const serverNow = () => S.now + (performance.now() - S.recv) / 1000;
  const triOf = n => Math.min(3, Math.max(1, n || 3));
  const triName = n => tr(`tri_${n}`, ['', 'Critical', 'Urgent', 'Standard'][n] || 'Standard');

  /* ── clock (rolling digits) ── */
  function clockText() {
    const c = S.clock || {};
    if (c.mode === 'real' || c.h === undefined) { const d = new Date(); return `${pad(d.getHours())}:${pad(d.getMinutes())}`; }
    const mins = c.h * 60 + c.m + (performance.now() - S.clockRecv) / (c.msPerMin || 2000);
    const m = Math.floor(mins) % 1440;
    return `${pad(m / 60)}:${pad(m % 60)}`;
  }
  function dateText() {
    const d = new Date();
    const days = tr('tv_days', 'Sun,Mon,Tue,Wed,Thu,Fri,Sat').split(',');
    const months = tr('tv_months', 'Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec').split(',');
    return `${days[d.getDay()] || ''} ${d.getDate()} ${months[d.getMonth()] || ''}`;
  }
  const strip = '<span class="st">' + '0123456789'.split('').map(d => `<i>${d}</i>`).join('') + '</span>';
  function setClock(txt) {
    const host = $('.tv-time');
    if (host.childElementCount !== txt.length) host.innerHTML = [...txt].map(ch => (/[0-9]/.test(ch) ? `<span class="d">${strip}</span>` : `<span class="c">${esc(ch)}</span>`)).join('');
    [...txt].forEach((ch, i) => { const d = host.children[i]; if (d && d.classList.contains('d')) d.firstChild.style.transform = `translateY(${-Number(ch)}em)`; });
  }

  /* ── chime (two-tone, like a clinic call) ── */
  function chime(volume) {
    try {
      const C = window.AudioContext || window.webkitAudioContext;
      if (!C) return;
      S.audio = S.audio || new C();
      const ctx = S.audio, v = Math.max(0.05, Math.min(1, volume || 0.6)) * 0.22;
      [[659.25, 0], [987.77, 0.34], [783.99, 0.68]].forEach(([f, at]) => {
        const o = ctx.createOscillator(), o2 = ctx.createOscillator(), g = ctx.createGain(), t0 = ctx.currentTime + at;
        o.type = 'sine'; o.frequency.value = f; o2.type = 'sine'; o2.frequency.value = f * 2;
        const g2 = ctx.createGain(); g2.gain.value = 0.16;
        g.gain.setValueAtTime(0, t0); g.gain.linearRampToValueAtTime(v, t0 + 0.02); g.gain.exponentialRampToValueAtTime(0.0001, t0 + 1.4);
        o.connect(g); o2.connect(g2); g2.connect(g); g.connect(ctx.destination);
        o.start(t0); o2.start(t0); o.stop(t0 + 1.5); o2.stop(t0 + 1.5);
      });
    } catch (e) { /* audio is optional */ }
  }

  /* ── ring (SVG, 100 box) ── */
  function ring(p, tone, inner) {
    const r = 41, C = 2 * Math.PI * r, off = C * (1 - Math.max(0, Math.min(1, p)));
    let tk = '';
    for (let i = 0; i < 40; i++) { const a = (i / 40) * Math.PI * 2, b = i % 10 === 0; const r1 = 49, r2 = b ? 45.5 : 47.2; tk += `<line x1="${(50 + r1 * Math.sin(a)).toFixed(1)}" y1="${(50 - r1 * Math.cos(a)).toFixed(1)}" x2="${(50 + r2 * Math.sin(a)).toFixed(1)}" y2="${(50 - r2 * Math.cos(a)).toFixed(1)}" class="${b ? 'b' : ''}"/>`; }
    return `<span class="tv-ring ${tone || ''}"><svg viewBox="0 0 100 100"><g class="tk">${tk}</g><circle class="tr" cx="50" cy="50" r="${r}"/><circle class="ar" cx="50" cy="50" r="${r}" stroke-dasharray="${C.toFixed(1)}" stroke-dashoffset="${off.toFixed(1)}"/></svg><span class="in">${inner}</span></span>`;
  }

  /* ── static text ── */
  function renderStatic() {
    tv.querySelectorAll('[data-l]').forEach(e => { const k = e.dataset.l; e.textContent = tr(k, e.textContent); });
    $('.tv-ric').innerHTML = ICON.ambulance;
    const lines = [
      tr('tv_t1', 'P1 critical patients always go first'),
      tr('tv_t2', 'Keep your queue pass on you'),
      tr('tv_t3', 'Your number lights up here together with your bed'),
      tr('tv_t4', 'Feeling worse while you wait? Tell the front desk right away'),
    ];
    $('.tv-tick').innerHTML = lines.concat(lines).map(l => `<span><i></i>${esc(l)}</span>`).join('');
  }

  /* ── bed bay map ── */
  function bays(b) {
    const c = b.counts || {};
    const serving = (b.serving || []).slice().sort((x, y) => (x.status === 'called' ? 0 : 1) - (y.status === 'called' ? 0 : 1) || (y.at || 0) - (x.at || 0));
    const total = Math.max(c.bedsTotal || 0, serving.length);
    const free = Math.max(0, Math.min(c.bedsFree || 0, total - serving.length));
    const other = Math.max(0, total - serving.length - free);
    const tiles = serving.map(s => ({ k: s.status === 'called' ? 'called' : 'treat', s }))
      .concat(Array.from({ length: other }, () => ({ k: 'use' })))
      .concat(Array.from({ length: free }, () => ({ k: 'open' })));
    const MAX = 8;
    const shown = tiles.slice(0, MAX);
    const cols = Math.max(3, Math.min(4, shown.length || 3));
    const grid = $('.tv-bgrid');
    grid.style.gridTemplateColumns = `repeat(${cols},1fr)`;
    grid.classList.toggle('two', shown.length > cols);
    if (!shown.length) {
      grid.innerHTML = `<div class="tv-bnone">${ICON.bed}<p>${esc(tr('tv_seat', 'Take a seat — your number shows up here with your bed.'))}</p></div>`;
      return;
    }
    grid.innerHTML = shown.map((t, i) => {
      if (t.k === 'open') return `<div class="tv-bay open" style="--i:${i}"><div class="hd"><span>${esc(tr('tv_bay', 'Bed'))}</span><i></i></div><div class="bd">${ICON.bed}<b>${esc(tr('tv_open', 'Open'))}</b></div></div>`;
      if (t.k === 'use') return `<div class="tv-bay use" style="--i:${i}"><div class="hd"><span>${esc(tr('tv_bay', 'Bed'))}</span><i></i></div><div class="bd">${ICON.user}<b>${esc(tr('tv_use', 'In use'))}</b></div></div>`;
      const s = t.s, tri = triOf(s.triage), mine = S.mine && s.code === S.mine;
      const called = t.k === 'called';
      return `<div class="tv-bay ${called ? 'called' : 'treat'} t${tri} ${mine ? 'mine' : ''}" style="--i:${i}">
        <div class="hd"><span>${esc(s.bed || tr('bed', 'Bed'))}</span><i></i></div>
        <div class="code">${esc(s.code)}</div>
        <div class="st">${called ? `${ICON.arrow}<b>${esc(tr('tv_go', 'Go to your bed'))}</b>` : `${ICON.heart}<b>${esc(tr('tv_in', 'In treatment'))}</b>`}</div>
        ${mine ? `<span class="you">${esc(tr('tv_yours', 'That is you'))}</span>` : ''}
      </div>`;
    }).join('') + (tiles.length > MAX ? `<div class="tv-bmore">+${tiles.length - MAX}</div>` : '');
    $('.tv-legend').textContent = total ? fmtS(tr('tv_bays_n', '%d of %d open'), free, total) : '';
  }

  /* ── triage lanes ── */
  function lanes(b) {
    const wl = b.waiting || [];
    const now = serverNow();
    const PER = 5;
    $('.tv-lanes').innerHTML = [1, 2, 3].map(n => {
      const list = wl.filter(w => triOf(w.triage) === n);
      const tok = list.slice(0, PER).map((w, i) => {
        const secs = now - (w.issued || now);
        const mine = S.mine && w.code === S.mine;
        return `<div class="tv-tok ${mine ? 'mine' : ''} ${i === 0 ? 'first' : ''}" style="--i:${i}"><b>${esc(w.code)}</b><span class="tv-wt ${secs > 900 ? 'long' : ''}" data-since="${w.issued || ''}">${mmss(secs)}</span>${mine ? `<em>${esc(tr('tv_you', 'You'))}</em>` : ''}</div>`;
      }).join('');
      const more = list.length > PER ? `<div class="tv-tok more">+${list.length - PER}</div>` : '';
      return `<div class="tv-lane p${n} ${list.length ? '' : 'empty'}">
        <div class="tv-lh"><i></i><b>P${n}</b><span>${esc(triName(n))}</span><em>${list.length}</em></div>
        <div class="tv-lt">${tok || `<span class="tv-lnone">${esc(tr('tv_lane_empty', 'Nobody in this lane'))}</span>`}${more}</div>
      </div>`;
    }).join('');
    $('.tv-qmore').textContent = b.waitingMore ? fmtS(tr('tv_more', '+ %d more in the queue'), b.waitingMore) : '';
  }

  /* ── rail: status rings + units en route ── */
  function rail(b) {
    const c = b.counts || {};
    const bedsP = c.bedsTotal ? (c.bedsFree || 0) / c.bedsTotal : 0;
    const staffTxt = c.staff ? `<b>${c.staff}</b>` : `<i class="ic">${b.ai ? ICON.bolt : ICON.user}</i>`;
    $('.tv-rings').innerHTML = `
      <div class="tv-rrow">${ring(bedsP, c.bedsTotal && !c.bedsFree ? 'red' : 'teal', `<b>${c.bedsFree || 0}</b><small>/${c.bedsTotal || 0}</small>`)}<div><span>${esc(tr('tv_c_beds', 'Beds open'))}</span><p>${esc(c.bedsTotal && !c.bedsFree ? tr('tv_beds_full', 'All beds in use') : tr('tv_beds_ok', 'Ready for the next patient'))}</p></div></div>
      <div class="tv-rrow">${ring(c.staff ? Math.min(1, c.staff / 4) : (b.ai ? 1 : 0), c.staff ? 'white' : (b.ai ? 'teal' : 'red'), staffTxt)}<div><span>${esc(c.staff ? tr('tv_staff', 'Staff on shift') : (b.ai ? tr('tv_ai', 'AI doctor on call') : tr('tv_nostaff', 'No staff on shift')))}</span><p>${esc(c.staff ? tr('tv_staff_p', 'Doctors and medics in the building') : (b.ai ? tr('tv_ai_p', 'Patients are still seen') : tr('tv_nostaff_p', 'Please wait — help is on the way')))}</p></div></div>
      <div class="tv-rrow">${ring(Math.min(1, (c.waiting || 0) / 10), (c.waiting || 0) > 6 ? 'amber' : 'teal', `<b>${c.waiting || 0}</b>`)}<div><span>${esc(tr('tv_c_waiting', 'In the queue'))}</span><p>${esc(fmtS(tr('tv_c_treat_n', '%d in treatment'), c.treatment || 0))}</p></div></div>`;
    const inc = b.incoming || [];
    $('.tv-route').classList.toggle('none', !inc.length);
    $('.tv-rlist').innerHTML = inc.length
      ? inc.slice(0, 3).map(a => {
        const p = triOf(a.priority);
        return `<div class="tv-unit p${p} ${a.arriving ? 'arr' : ''}"><i></i><div><b>${esc(a.unit)}</b><span>P${p} · ${esc(triName(p))}</span></div><em>${a.arriving ? esc(tr('tv_arriving', 'At the door')) : esc(fmtS(tr('tv_min', '%d min'), Math.max(1, Math.round((a.eta || 0) / 60))))}</em></div>`;
      }).join('')
      : `<span class="tv-rnone">${esc(tr('tv_noinc', 'No ambulances on their way'))}</span>`;
  }

  function render() {
    const b = S.board;
    if (!b) return;
    tv.classList.remove('standby');
    $('.tv-dept').textContent = S.title || b.label || tr('hospital', 'Hospital');
    $('.tv-room').textContent = tr('tv_room', 'Emergency · waiting area');
    bays(b); lanes(b); rail(b);
  }

  function flash(s) {
    const f = $('.tv-flash');
    const mine = S.mine && s.code === S.mine;
    const tri = triOf(s.triage);
    f.className = `tv-flash t${tri}`;
    f.innerHTML = `<div class="fx"><svg viewBox="0 0 100 100"><circle class="r1" cx="50" cy="50" r="46"/><circle class="r2" cx="50" cy="50" r="40"/></svg>
      <small>${esc(tr('tv_calling', 'Number called'))}</small><div class="c">${esc(s.code)}</div>
      <div class="b">${ICON.arrow}<span>${esc(s.bed || '')}</span></div>
      ${mine ? `<div class="y">${esc(tr('tv_yours', 'That is you'))}</div>` : `<div class="g">${esc(tr('tv_go', 'Go to your bed'))}</div>`}</div>`;
    void f.offsetWidth; f.classList.add('on');
    clearTimeout(S.flashTimer);
    S.flashTimer = setTimeout(() => f.classList.remove('on'), 7000);
  }

  function onBoard(m) {
    const b = m.board || {};
    if (b.now) { S.now = b.now; S.recv = performance.now(); }
    if (m.clock) { S.clock = m.clock; S.clockRecv = performance.now(); }
    if ('mine' in m) S.mine = m.mine || null;
    if (m.title !== undefined) S.title = m.title;
    const prevHosp = S.board && S.board.hospital;
    S.board = b;
    // newest called ticket → flash (not on the first board after switching screens)
    const called = (b.serving || []).filter(s => s.status === 'called').sort((x, y) => (y.at || 0) - (x.at || 0))[0];
    const key = called ? `${called.code}:${called.at}` : null;
    if (key && S.lastCalled !== null && key !== S.lastCalled && prevHosp === b.hospital) flash(called);
    S.lastCalled = key || '';
    render();
  }

  function handle(m) {
    if (typeof m === 'string') { try { m = JSON.parse(m); } catch (e) { return; } }
    if (!m || typeof m !== 'object') return;
    switch (m.type) {
      case 'init': L = Object.assign(L, m.locale || {}); if (m.clock) { S.clock = m.clock; S.clockRecv = performance.now(); } renderStatic(); render(); break;
      case 'board': onBoard(m); break;
      case 'mine': S.mine = m.mine || null; render(); break;
      case 'clock': if (m.clock) { S.clock = m.clock; S.clockRecv = performance.now(); } break;
      case 'chime': chime(m.volume); break;
      case 'standby': tv.classList.add('standby'); S.board = null; S.lastCalled = null; break;
    }
  }
  window.addEventListener('message', e => handle(e.data));

  /* ── per-second tick: clock + waiting times ── */
  function tick() {
    setClock(clockText());
    $('.tv-date').textContent = (S.clock && S.clock.mode === 'game') ? tr('tv_local', 'Local time') : dateText();
    const now = serverNow();
    document.querySelectorAll('.tv-wt[data-since]').forEach(e => {
      const v = Number(e.dataset.since);
      if (v) { const s = now - v; e.textContent = mmss(s); e.classList.toggle('long', s > 900); }
    });
  }
  setInterval(tick, 1000);
  renderStatic();
  tick();

  /* ── browser demo (file:// only) ── */
  if (location.protocol === 'file:') {
    const q = new URLSearchParams(location.search);
    const state = q.get('state') || 'full';
    const now = Math.floor(Date.now() / 1000);
    const board = {
      hospital: 'pillbox', label: 'Pillbox Medical', now,
      serving: [{ code: 'A-011', triage: 2, bed: 'Bed 2', status: 'called', at: now - 40 }, { code: 'A-009', triage: 1, bed: 'Bed 1', status: 'treatment', at: now - 600 }, { code: 'A-008', triage: 3, bed: 'Bed 4', status: 'treatment', at: now - 900 }],
      waiting: [{ code: 'A-013', triage: 1, issued: now - 142 }, { code: 'A-014', triage: 2, issued: now - 418 }, { code: 'A-016', triage: 2, issued: now - 95 }, { code: 'A-015', triage: 3, issued: now - 1195 }, { code: 'A-017', triage: 3, issued: now - 61 }],
      waitingMore: 0,
      incoming: [{ unit: 'MEDIC 12', priority: 1, eta: 40, arriving: true }, { unit: 'RESCUE 7', priority: 2, eta: 190, arriving: false }],
      counts: { waiting: 5, treatment: 2, bedsFree: 1, bedsTotal: 5, staff: 1 }, ai: false,
    };
    if (state === 'busy') {
      board.waiting = board.waiting.concat([{ code: 'A-018', triage: 3, issued: now - 40 }, { code: 'A-019', triage: 2, issued: now - 30 }, { code: 'A-020', triage: 3, issued: now - 20 }, { code: 'A-021', triage: 3, issued: now - 12 }, { code: 'A-022', triage: 3, issued: now - 5 }, { code: 'A-023', triage: 3, issued: now - 2 }]);
      board.waitingMore = 4; board.counts = { waiting: 15, treatment: 6, bedsFree: 0, bedsTotal: 8, staff: 3 };
      board.serving = board.serving.concat([{ code: 'A-005', triage: 2, bed: 'Bed 5', status: 'treatment', at: now - 1200 }, { code: 'A-006', triage: 3, bed: 'Bed 6', status: 'treatment', at: now - 1300 }, { code: 'A-007', triage: 3, bed: 'Bed 7', status: 'treatment', at: now - 1400 }]);
    }
    if (state === 'empty') { board.serving = []; board.waiting = []; board.incoming = []; board.counts = { waiting: 0, treatment: 0, bedsFree: 3, bedsTotal: 3, staff: 0 }; board.ai = true; }
    if (state !== 'standby') {
      handle({ type: 'init', locale: {}, clock: { mode: 'game', h: 12, m: 0, msPerMin: 2000 } });
      handle({ type: 'board', board, mine: state === 'mine' ? 'A-014' : null });
      if (state === 'flash') { S.lastCalled = 'x'; handle({ type: 'board', board: Object.assign({}, board, { serving: [{ code: 'A-014', triage: 2, bed: 'Bed 3', status: 'called', at: now }].concat(board.serving) }), mine: 'A-014' }); }
    }
  }
})();
