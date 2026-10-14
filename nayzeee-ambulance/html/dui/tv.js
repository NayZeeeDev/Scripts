/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · waiting room board (DUI)
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

  const ICON = {
    ambulance: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M3 17V8a1 1 0 0 1 1-1h10v10M14 10h4l3 3.5V17h-2"/><path d="M6 17h8"/><circle cx="7.5" cy="17.5" r="1.7"/><circle cx="17" cy="17.5" r="1.7"/><path d="M8.5 9.5v4M6.5 11.5h4"/></svg>',
    chair: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M6 11V5a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v6"/><path d="M4 11h16v4H4z"/><path d="M6 15v5M18 15v5"/></svg>',
  };

  const S = { board: null, now: Date.now() / 1000, recv: performance.now(), clock: { mode: 'real' }, clockRecv: performance.now(), mine: null, title: null, flashTimer: 0, lastCalled: null, audio: null };
  const serverNow = () => S.now + (performance.now() - S.recv) / 1000;

  /* ── clock ── */
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

  /* ── chime (two-tone, like an airport / clinic call) ── */
  function chime(volume) {
    try {
      const C = window.AudioContext || window.webkitAudioContext;
      if (!C) return;
      S.audio = S.audio || new C();
      const ctx = S.audio, v = Math.max(0.05, Math.min(1, volume || 0.6)) * 0.22;
      [[784, 0], [523.25, 0.42]].forEach(([f, at]) => {
        const o = ctx.createOscillator(), o2 = ctx.createOscillator(), g = ctx.createGain(), t0 = ctx.currentTime + at;
        o.type = 'sine'; o.frequency.value = f; o2.type = 'sine'; o2.frequency.value = f * 2;
        const g2 = ctx.createGain(); g2.gain.value = 0.18;
        g.gain.setValueAtTime(0, t0); g.gain.linearRampToValueAtTime(v, t0 + 0.02); g.gain.exponentialRampToValueAtTime(0.0001, t0 + 1.6);
        o.connect(g); o2.connect(g2); g2.connect(g); g.connect(ctx.destination);
        o.start(t0); o2.start(t0); o.stop(t0 + 1.7); o2.stop(t0 + 1.7);
      });
    } catch (e) { /* audio is optional */ }
  }

  /* ── rendering ── */
  const triName = n => tr(`tri_${n}`, ['', 'Critical', 'Urgent', 'Standard'][n] || 'Standard');
  const pri = (n, short) => `<span class="tv-pri p${n}"><b>P${n}</b>${short ? '' : ` ${esc(triName(n))}`}</span>`;

  function renderStatic() {
    tv.querySelectorAll('[data-l]').forEach(e => { const k = e.dataset.l; e.textContent = tr(k, e.textContent); });
    $('.tv-iic').innerHTML = ICON.ambulance;
    const lines = [
      tr('tv_t1', 'Critical patients (P1) are always seen first'),
      tr('tv_t2', 'Please keep your ticket with you'),
      tr('tv_t3', 'Watch this screen — your number appears with your bed'),
      tr('tv_t4', 'Feeling worse while you wait? Tell the reception at once'),
    ];
    $('.tv-tick').innerHTML = lines.concat(lines).map(l => `<span>${esc(l)}</span>`).join('');
  }

  function render() {
    const b = S.board;
    if (!b) return;
    tv.classList.remove('standby');
    $('.tv-dept').textContent = S.title || b.label || tr('hospital', 'Hospital');
    $('.tv-room').textContent = tr('tv_room', 'Waiting room');
    // now serving
    const serving = b.serving || [];
    const sl = $('.tv-slist');
    if (!serving.length) {
      sl.innerHTML = `<div class="tv-empty"><span class="tv-eic">${ICON.chair}</span><p>${esc(tr('tv_seat', 'Please take a seat. Your ticket number will appear here when a bed is ready.'))}</p></div>`;
    } else {
      sl.innerHTML = serving.map((s, i) => {
        const tri = Math.min(3, Math.max(1, s.triage || 3));
        const called = s.status === 'called';
        const mine = S.mine && s.code === S.mine;
        return `<div class="tv-scard t${tri} ${i === 0 ? 'first' : ''} ${called ? '' : 'treat'} ${mine ? 'mine' : ''}">
          ${mine ? `<span class="tv-mine">${esc(tr('tv_yours', 'Your number'))}</span>` : ''}
          <span class="tv-scode">${esc(s.code)}</span><span class="tv-sarrow">→</span>
          <div class="tv-sbed"><b>${esc(s.bed || tr('bed', 'Bed'))}</b><span>${esc(called ? tr('tv_go', 'Please go now') : tr('tv_in', 'In treatment'))}</span></div></div>`;
      }).join('');
    }
    // waiting list
    const wl = b.waiting || [];
    $('.tv-wcount').textContent = (b.counts && b.counts.waiting) != null ? b.counts.waiting : wl.length;
    const now = serverNow();
    $('.tv-wlist').innerHTML = wl.length
      ? wl.map(w => {
        const tri = Math.min(3, Math.max(1, w.triage || 3));
        const secs = now - (w.issued || now);
        return `<div class="tv-wrow ${S.mine && w.code === S.mine ? 'mine' : ''}">${pri(tri)}<span class="tv-wcode">${esc(w.code)}</span><span class="tv-wtime ${secs > 900 ? 'long' : ''}" data-since="${w.issued || ''}">${mmss(secs)}</span></div>`;
      }).join('') + (b.waitingMore ? `<div class="tv-wmore">${esc(fmtS(tr('tv_more', '+ %d more waiting'), b.waitingMore))}</div>` : '')
      : `<div class="tv-wnone">${esc(tr('tv_nobody', 'Nobody waiting'))}</div>`;
    // incoming
    const inc = b.incoming || [];
    $('.tv-ilist').innerHTML = inc.length
      ? inc.map(a => {
        const p = Math.min(3, Math.max(1, a.priority || 3));
        return `<div class="tv-icard ${a.arriving ? 'arr' : ''}"><div class="u"><b>${esc(a.unit)}</b>${pri(p)}</div><div class="e"><small>${esc(tr('tv_eta', 'ETA'))}</small><b>${a.arriving ? esc(tr('tv_arriving', 'Arriving')) : esc(fmtS(tr('tv_min', '%d min'), Math.max(1, Math.round((a.eta || 0) / 60))))}</b></div></div>`;
      }).join('')
      : `<span class="tv-inone">${esc(tr('tv_noinc', 'No ambulances on their way'))}</span>`;
    // footer
    const c = b.counts || {};
    const bedsPct = c.bedsTotal ? (c.bedsFree / c.bedsTotal) * 100 : 0;
    $('.tv-counts').innerHTML = `
      <span class="tv-cnt">${esc(tr('tv_c_waiting', 'Waiting'))} <b>${c.waiting || 0}</b></span>
      <span class="tv-cnt">${esc(tr('tv_c_treat', 'In treatment'))} <b>${c.treatment || 0}</b></span>
      <span class="tv-cnt ${c.bedsTotal && !c.bedsFree ? 'low' : ''}">${esc(tr('tv_c_beds', 'Beds free'))} <b>${c.bedsFree || 0}/${c.bedsTotal || 0}</b><span class="bar"><i style="width:${bedsPct}%"></i></span></span>`;
    const st = $('.tv-staff');
    st.classList.toggle('none', !c.staff);
    st.innerHTML = c.staff ? `<i></i>${esc(tr('tv_staff', 'Medical staff on duty'))} <b>${c.staff}</b>` : `<i></i>${esc(b.ai ? tr('tv_ai', 'AI doctor on call') : tr('tv_nostaff', 'No medical staff on duty'))}`;
  }

  function flash(s) {
    const f = $('.tv-flash');
    const mine = S.mine && s.code === S.mine;
    f.innerHTML = `<small>${esc(tr('tv_calling', 'Now calling'))}</small><div class="c">${esc(s.code)}</div><div class="b"><em>→</em>${esc(s.bed || '')}</div>${mine ? `<div class="y">${esc(tr('tv_yours', 'Your number'))}</div>` : ''}`;
    f.classList.remove('on'); void f.offsetWidth; f.classList.add('on');
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
  setInterval(() => {
    $('.tv-time').textContent = clockText();
    $('.tv-date').textContent = (S.clock && S.clock.mode === 'game') ? tr('tv_local', 'Local time') : dateText();
    const now = serverNow();
    document.querySelectorAll('.tv-wtime[data-since]').forEach(e => {
      const v = Number(e.dataset.since);
      if (v) { const s = now - v; e.textContent = mmss(s); e.classList.toggle('long', s > 900); }
    });
  }, 1000);
  renderStatic();
  $('.tv-time').textContent = clockText();

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
      counts: { waiting: 5, treatment: 2, bedsFree: 1, bedsTotal: 4, staff: 1 }, ai: false,
    };
    if (state === 'empty') { board.serving = []; board.waiting = []; board.incoming = []; board.counts = { waiting: 0, treatment: 0, bedsFree: 3, bedsTotal: 3, staff: 0 }; board.ai = true; }
    if (state !== 'standby') {
      handle({ type: 'init', locale: {}, clock: { mode: 'game', h: 12, m: 0, msPerMin: 2000 } });
      handle({ type: 'board', board, mine: state === 'mine' ? 'A-014' : null });
      if (state === 'flash') { S.lastCalled = 'x'; handle({ type: 'board', board: Object.assign({}, board, { serving: [{ code: 'A-014', triage: 2, bed: 'Bed 3', status: 'called', at: now }].concat(board.serving) }), mine: 'A-014' }); }
    }
  }
})();
