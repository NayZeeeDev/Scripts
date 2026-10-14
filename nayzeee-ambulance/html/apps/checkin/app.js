/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · app 'checkin'
   Front desk: the queue pass (dark glass card, top-left, issued with a scan sweep:
   queue ring, rolling number, instrument list, journey spine), the queue dock while
   you wait (same corner, compact), receptionist lines through NZA.speech (top-centre
   voice card) and the staff reception window. Several layers can show at once; the
   app posts checkin:hidden when nothing is left on screen.

   Lua → JS   open { mode: 'ticket'|'chip'|'say'|'desk', ticket, print, say, desk, mine,
                     cfg { receiptTime, ticketHud, printSound, estimate }, clock, locale }
              mine { ticket|null, event, closed }   say { name, role, text }
              desk (desk payload)   deskClosed   hideReceipt
   JS → Lua   checkin:action { action, id, bed, hospital } → { ok, msg }
              checkin:deskClose · checkin:refresh { hospital } → { ok, desk }
              checkin:hospital { id } → { ok, desk } · checkin:leave · checkin:hidden
   ═══════════════════════════════════════════════════════════ */
(() => {
  const esc = NZA.esc, icon = NZA.icon;
  let L = {};
  const tr = (k, f) => (L[k] !== undefined && L[k] !== '' ? L[k] : f);
  const fmtS = (s, ...a) => { let i = 0; return String(s).replace(/%[sd]/g, () => (a[i] !== undefined ? a[i++] : '')); };
  const pad = n => String(Math.max(0, Math.floor(n))).padStart(2, '0');
  const mmss = s => { s = Math.max(0, Math.floor(s || 0)); return s >= 3600 ? `${Math.floor(s / 3600)}:${pad((s % 3600) / 60)}:${pad(s % 60)}` : `${pad(s / 60)}:${pad(s % 60)}`; };
  const TYPE_ICON = { gunshot: 'crosshair', shrapnel: 'burst', stab: 'knife', laceration: 'cut', abrasion: 'scrape', contusion: 'bruise', fracture: 'bone', burn: 'flame', internal: 'drop' };
  const TRI = { 1: ['tri_1', 'Critical'], 2: ['tri_2', 'Urgent'], 3: ['tri_3', 'Standard'] };
  const triLabel = (n, label) => label || tr(TRI[n] ? TRI[n][0] : 'tri_3', TRI[n] ? TRI[n][1] : 'Standard');
  const triOf = t => Math.min(3, Math.max(1, (t && t.triage) || 3));
  const VOID = { expired: 1, left: 1, noshow: 1, cancelled: 1 };

  /* ── server time + clock reference ── */
  const ref = { now: Date.now() / 1000, recv: performance.now(), clock: { mode: 'real' }, clockRecv: performance.now() };
  const serverNow = () => ref.now + (performance.now() - ref.recv) / 1000;
  function setNow(n) { if (n) { ref.now = n; ref.recv = performance.now(); } }
  function setClock(c) { if (c) { ref.clock = c; ref.clockRecv = performance.now(); } }
  // wall time ('HH:MM') of a server epoch, in game time or real time
  function hhmm(epoch) {
    const c = ref.clock || {};
    if (c.mode === 'real' || c.h === undefined) { const d = new Date(epoch * 1000); return `${pad(d.getHours())}:${pad(d.getMinutes())}`; }
    const per = c.msPerMin || 2000;
    const nowMin = c.h * 60 + c.m + (performance.now() - ref.clockRecv) / per;
    const ago = (serverNow() - epoch) * 1000 / per;
    const m = ((Math.floor(nowMin - ago) % 1440) + 1440) % 1440;
    return `${pad(m / 60)}:${pad(m % 60)}`;
  }
  const estText = t => {
    const est = Math.max(0, (t.estimate || 0) - (t.issued ? serverNow() - t.issued : 0));
    return est > 0 ? `~${Math.max(1, Math.round(est / 60))} ${tr('min', 'min')}` : tr('r_soon', 'Any moment');
  };

  /* ── progress ring (SVG, 100×100 box): track, arc, optional bezel ticks ── */
  function ringSVG(p, { r = 40, w = 7, ticks = 0, cls = '' } = {}) {
    const C = 2 * Math.PI * r;
    const off = C * (1 - Math.max(0, Math.min(1, p)));
    let tk = '';
    if (ticks) {
      for (let i = 0; i < ticks; i++) {
        const a = (i / ticks) * Math.PI * 2, big = i % (ticks / 12) === 0;
        const r1 = 48.5, r2 = big ? 44.5 : 46.4;
        tk += `<line x1="${(50 + r1 * Math.sin(a)).toFixed(2)}" y1="${(50 - r1 * Math.cos(a)).toFixed(2)}" x2="${(50 + r2 * Math.sin(a)).toFixed(2)}" y2="${(50 - r2 * Math.cos(a)).toFixed(2)}" class="${big ? 'b' : ''}"/>`;
      }
    }
    return `<svg class="ci-rsvg ${cls}" viewBox="0 0 100 100">${tk ? `<g class="tk">${tk}</g>` : ''}<circle class="tr" cx="50" cy="50" r="${r}" stroke-width="${w}"/><circle class="ar" cx="50" cy="50" r="${r}" stroke-width="${w}" stroke-dasharray="${C.toFixed(2)}" stroke-dashoffset="${off.toFixed(2)}" data-c="${C.toFixed(2)}"/></svg>`;
  }
  const setRing = (svg, p) => { const a = svg && svg.querySelector('.ar'); if (a) a.style.strokeDashoffset = String(Number(a.dataset.c) * (1 - Math.max(0, Math.min(1, p)))); };

  /* ── issue sound: a soft data chirp, then a two-tone confirm ── */
  function issueSound(ms) {
    const a = NZA.audio;
    const n = Math.max(6, Math.floor(ms / 90));
    for (let i = 0; i < n; i++) a.tone(1700 + ((i * 7) % 5) * 170, 22, { vol: 0.018, type: 'sine', at: i * 0.075 });
    a.noise(ms * 0.8, { vol: 0.018, lp: 7000, hp: 2600, attack: 0.1, release: 0.3 });
    a.tone(880, 120, { vol: 0.06, at: ms / 1000 + 0.05 });
    a.tone(1320, 200, { vol: 0.06, at: ms / 1000 + 0.18 });
  }

  const S = { el: null, cfg: { receiptTime: 14, ticketHud: true, printSound: true }, mine: null, pass: null, passTimer: 0, sayUntil: 0, sayTimer: 0, desk: null, deskOn: false, win: null, tab: 'queue', sel: null, busy: false, timer: 0, hidden: true, maxAhead: {}, odo: null };

  /* queue position as a ring fraction: grows as people ahead of you are called */
  function queueP(t) {
    if (!t) return 0;
    if (t.status === 'called' || t.status === 'treatment' || t.status === 'done') return 1;
    if (VOID[t.status]) return 0;
    const key = t.id || t.code;
    const ahead = Math.max(0, t.ahead || 0);
    S.maxAhead[key] = Math.max(S.maxAhead[key] || 0, ahead);
    const max = S.maxAhead[key];
    return (max - ahead + 0.5) / (max + 1);
  }
  function stageOf(t) {
    if (!t) return 0;
    if (t.status === 'called') return 2;
    if (t.status === 'treatment') return 3;
    if (t.status === 'done') return 4;
    if (VOID[t.status]) return -1;
    return 1;
  }
  function statusChip(t) {
    if (!t) return '';
    if (t.status === 'expired') return `<span class="ci-pst red">${icon('x')}${esc(tr('stamp_expired', 'Not valid'))}</span>`;
    if (VOID[t.status]) return `<span class="ci-pst red">${icon('x')}${esc(tr('stamp_closed', 'Closed'))}</span>`;
    if (t.status === 'called') return `<span class="ci-pst teal on"><i></i>${esc(tr('stamp_called', 'Called'))}</span>`;
    if (t.status === 'treatment') return `<span class="ci-pst white">${icon('heart')}${esc(tr('stamp_treatment', 'In treatment'))}</span>`;
    if (t.status === 'done') return `<span class="ci-pst teal">${icon('check')}${esc(tr('stamp_done', 'Treated'))}</span>`;
    return `<span class="ci-pst live"><i></i>${esc(tr('stamp_live', 'In queue'))}</span>`;
  }
  // what sits inside the queue ring
  function ringCore(t, big) {
    if (!t) return '';
    if (VOID[t.status]) return `<span class="ci-rc ic red">${icon('x')}</span>`;
    if (t.status === 'called') return `<span class="ci-rc ic teal">${icon('bed')}${big ? `<small>${esc(tr('ring_go', 'Go'))}</small>` : ''}</span>`;
    if (t.status === 'treatment') return `<span class="ci-rc ic white">${icon('heart')}</span>`;
    if (t.status === 'done') return `<span class="ci-rc ic teal">${icon('check')}</span>`;
    const a = Math.max(0, t.ahead || 0);
    if (a === 0) return `<span class="ci-rc"><b class="nx">${esc(tr('ring_next', 'NEXT'))}</b>${big ? `<small>${esc(tr('ring_up', 'up'))}</small>` : ''}</span>`;
    return `<span class="ci-rc"><b>${a}</b><small>${esc(tr('ring_ahead', 'ahead'))}</small></span>`;
  }

  /* ═══════════════════════ QUEUE PASS ═══════════════════════ */
  function passRows(t) {
    const rows = [];
    const waited = t.issued ? serverNow() - t.issued : 0;
    if (t.name) rows.push(['', tr('r_patient', 'Name'), esc(t.name), '']);
    if (t.status === 'called') {
      rows.push(['teal', tr('r_bed', 'Head to'), esc(t.bed || tr('bed', 'Bed')), '']);
      rows.push(['teal', tr('r_called', 'Called'), mmss(t.called ? serverNow() - t.called : 0), 'called']);
    } else if (t.status === 'waiting') {
      rows.push(['', tr('r_waiting', 'Time in queue'), mmss(waited), 'wait']);
      rows.push([t.ahead ? '' : 'teal', tr('r_estimate', 'Expected call'), esc(estText(t)), 'est']);
    } else if (t.bed) {
      rows.push(['white', tr('r_bed_now', 'Bed'), esc(t.bed), '']);
    }
    return rows.map(r => `<div class="ci-irow ${r[0]}" ${r[3] ? `data-k="${r[3]}"` : ''}><span>${esc(r[1])}</span><b>${r[2]}</b></div>`).join('');
  }
  function journeyHTML(t) {
    const st = stageOf(t);
    const voidAt = st === -1 ? (t.called ? 2 : 1) : -1;
    const ahead = Math.max(0, t.ahead || 0);
    const nodes = [
      [tr('j_issued', 'Registered'), t.issued ? hhmm(t.issued) : ''],
      [tr('j_queue', 'In the queue'), t.status === 'waiting' ? (ahead ? fmtS(tr('j_ahead', '%d ahead'), ahead) : tr('j_next', 'You are next')) : ''],
      [tr('j_called', 'Called to a bed'), t.bed && st >= 2 ? t.bed : ''],
      [tr('j_treat', 'Treatment'), st === 3 ? (t.ai ? tr('chip_ai', 'AI doctor') : (t.by || '')) : st === 4 ? tr('stamp_done', 'Treated') : ''],
    ];
    const fill = st === -1 ? voidAt / 3 : Math.min(1, Math.max(0, st) / 3);
    return `<div class="ci-jr ${st === -1 ? 'void' : ''}"><span class="trk"><i style="height:${(fill * 100).toFixed(1)}%"></i></span>${nodes.map((n, i) => {
      let cls = '';
      if (st === -1) cls = i < voidAt ? 'done' : i === voidAt ? 'bad' : '';
      else cls = i === 0 || i < st ? 'done' : i === st ? 'cur' : '';
      if (st === 4) cls = 'done';
      return `<div class="ci-jn ${cls}"><i></i><span>${esc(n[0])}</span><b>${esc(n[1])}</b></div>`;
    }).join('')}</div>`;
  }
  function passHTML(t) {
    const tri = triOf(t);
    const id = String(t.id || t.code || '').replace(/^T/, '');
    const st = stageOf(t);
    return `
      <div class="ci-pass nza-hud solid tri${tri} ${st === -1 ? 'void' : ''} s${t.status || 'waiting'}">
        <i class="ci-scan"></i>
        <header class="ci-ph">
          <div class="ci-pk"><small>${esc(tr('pass_kicker', 'Queue pass'))}</small><b>${esc(t.hospitalLabel || tr('hospital', 'Hospital'))}</b><span>${esc(t.desk || tr('desk', 'Front desk'))}${t.number ? ` · <em>#${esc(String(t.number).padStart(4, '0'))}</em>` : ''}</span></div>
          <div class="ci-pstw">${statusChip(t)}</div>
        </header>
        <div class="ci-pmain">
          <div class="ci-ring big">${ringSVG(0, { r: 39, w: 7, ticks: 48 })}<div class="ci-rcw">${ringCore(t, true)}</div></div>
          <div class="ci-pid">
            <small>${esc(tr('your_number', 'Queue number'))}</small>
            <div class="ci-code"></div>
            <span class="ci-tri p${tri}"><i></i><b>P${tri}</b>${esc(triLabel(tri, t.triageLabel))}</span>
          </div>
        </div>
        <div class="ci-ilist">${passRows(t)}</div>
        ${journeyHTML(t)}
        <footer class="ci-pf">${icon('ticket')}<span>${esc(tr('receipt_hint', 'Pass saved to your pockets'))}</span>${id ? `<b>${esc(id.toUpperCase())}</b>` : ''}</footer>
      </div>`;
  }
  function showPass(t, issue) {
    S.pass = t;
    const host = S.el.querySelector('.ci-passwrap');
    clearTimeout(S.passTimer);
    host.classList.remove('out');
    host.innerHTML = passHTML(t);
    host.classList.add('on');
    const card = host.querySelector('.ci-pass');
    // rolling number: starts at zero digits and rolls up to the real code
    const code = String(t.code || '?');
    S.odo = NZA.ui.FlipClock(card.querySelector('.ci-code'), { value: issue ? code.replace(/[0-9]/g, '0') : code });
    if (issue) {
      card.classList.add('issuing');
      setTimeout(() => S.odo && S.odo.set(code), 260);
      if (S.cfg.printSound !== false) issueSound(1100);
    }
    const svg = card.querySelector('.ci-ring svg');
    requestAnimationFrame(() => requestAnimationFrame(() => setRing(svg, queueP(t))));
    renderDock();
    const secs = Number(S.cfg.receiptTime);
    if (secs > 0) S.passTimer = setTimeout(hidePass, (secs + (issue ? 1.2 : 0)) * 1000);
    sync();
  }
  function hidePass() {
    const host = S.el.querySelector('.ci-passwrap');
    if (!host.classList.contains('on')) return;
    clearTimeout(S.passTimer);
    host.classList.add('out');
    setTimeout(() => { host.classList.remove('on', 'out'); host.innerHTML = ''; S.pass = null; S.odo = null; renderDock(); sync(); }, 300);
  }
  function updatePass() {
    const t = S.pass;
    const card = S.el.querySelector('.ci-passwrap .ci-pass');
    if (!t || !card) return;
    const tri = triOf(t), st = stageOf(t);
    card.className = `ci-pass nza-hud solid tri${tri} ${st === -1 ? 'void' : ''} s${t.status || 'waiting'}`;
    card.querySelector('.ci-pstw').innerHTML = statusChip(t);
    card.querySelector('.ci-rcw').innerHTML = ringCore(t, true);
    card.querySelector('.ci-ilist').innerHTML = passRows(t);
    const jr = card.querySelector('.ci-jr');
    if (jr) jr.outerHTML = journeyHTML(t);
    setRing(card.querySelector('.ci-ring svg'), queueP(t));
  }

  /* ═══════════════════════ QUEUE DOCK (while you wait) ═══════════════════════ */
  function renderDock() {
    const host = S.el.querySelector('.ci-dockwrap');
    const t = S.mine;
    const passOpen = S.el.querySelector('.ci-passwrap').classList.contains('on');
    if (!t || S.cfg.ticketHud === false || passOpen) {
      if (host.classList.contains('on')) { host.classList.remove('on'); host.innerHTML = ''; }
      sync();
      return;
    }
    const tri = triOf(t);
    const wasOn = host.classList.contains('on');
    host.classList.add('on');
    let line1, line2, cls = '';
    if (t.status === 'called') {
      cls = 'called';
      line1 = `<small>${esc(tr('chip_called', 'Called to a bed'))}</small><b class="cd">${esc(t.code)}<em>${icon('arrow-r')}</em>${esc(t.bed || tr('bed', 'Bed'))}</b>`;
      line2 = `<span class="go"><i></i>${esc(tr('chip_go', 'Go now'))}</span><span class="sep"></span><span><b data-k="calledFor">${mmss(t.called ? serverNow() - t.called : 0)}</b></span>`;
    } else if (t.status === 'treatment') {
      cls = 'treat';
      line1 = `<small>${esc(t.ai ? tr('chip_ai', 'AI doctor') : tr('chip_treat', 'In treatment'))}</small><b class="cd">${esc(t.code)}<em>·</em>${esc(t.bed || '')}</b>`;
      line2 = `<span>${esc(tr('chip_treat_sub', 'Stay on the bed'))}</span>`;
    } else {
      const waited = t.issued ? serverNow() - t.issued : 0;
      line1 = `<small>${esc(tr('chip_ticket', 'Your queue number'))}</small><b class="cd">${esc(t.code)}</b><span class="ci-tri sm p${tri}"><i></i><b>P${tri}</b></span>`;
      line2 = `<span><b data-k="waited">${mmss(waited)}</b> ${esc(tr('chip_waiting', 'in queue'))}</span><span class="sep"></span><span>${esc(tr('chip_est', 'call'))} <b data-k="est">${esc(estText(t))}</b></span>`;
    }
    host.innerHTML = `<div class="ci-dock nza-hud solid tri${tri} ${cls} ${wasOn ? 'still' : ''}">
        <span class="ci-dspine"></span>
        <div class="ci-ring sm">${ringSVG(queueP(t), { r: 40, w: 9 })}<div class="ci-rcw">${ringCore(t, false)}</div></div>
        <div class="ci-dtx"><div class="ci-dl1">${line1}</div><div class="ci-dl2">${line2}</div></div>
      </div>`;
    sync();
  }

  /* ═══════════════════════ VOICE (receptionist → NZA.speech) ═══════════════════════ */
  function showSay(s) {
    if (!s || !s.text) return;
    const ms = Math.max(3200, s.text.length * 70);
    NZA.speech({ name: s.name || tr('reception', 'Reception'), role: s.role || tr('reception', 'Reception'), text: s.text, ms });
    S.sayUntil = performance.now() + ms;
    clearTimeout(S.sayTimer);
    S.sayTimer = setTimeout(sync, ms + 250);
    sync();
  }

  /* ═══════════════════════ RECEPTION WINDOW (staff) ═══════════════════════ */
  const STATUS = {
    waiting: ['st_waiting', 'Waiting', ''], called: ['st_called', 'Called', 'teal'], treatment: ['st_treatment', 'In treatment', 'white'],
    done: ['st_done', 'Treated', 'teal'], noshow: ['st_noshow', 'No-show', 'red'], left: ['st_left', 'Left', ''], cancelled: ['st_cancelled', 'Cancelled', 'red'],
  };
  const stLabel = s => tr((STATUS[s] || STATUS.waiting)[0], (STATUS[s] || STATUS.waiting)[1]);
  const WAIT_CAP = 1800;   // a queue row's wait ring is full after 30 min
  const waitTone = s => (s > 1500 ? 'red' : s > 900 ? 'amber' : '');

  function openDesk(desk) {
    S.desk = desk || S.desk || {};
    setNow(S.desk.now);
    if (!S.win) {
      const host = S.el.querySelector('.ci-deskwrap');
      host.innerHTML = '<div class="nza-dim"></div>';
      S.win = NZA.ui.Win(host, {
        title: tr('desk_title', 'Reception'), sub: S.desk.label || '', width: 'min(1260px,94vw)', height: 'min(820px,95vh)',
        nav: navItems(), navValue: S.tab, onNav: id => { S.tab = id; renderDesk(); }, onClose: () => closeDesk(true),
        status: [{ key: 'ESC', label: tr('k_close', 'Close') }, { key: 'N', label: tr('k_next', 'Call next') }, { key: '↑↓', label: tr('k_select', 'Select') }, { key: '↵', label: tr('k_call', 'Call to a bed') }],
      });
      S.win.el.classList.add('ci-win');
    }
    S.deskOn = true;
    S.el.querySelector('.ci-deskwrap').classList.add('on');
    renderDesk();
    sync();
  }
  function closeDesk(post) {
    if (!S.deskOn) return;
    S.deskOn = false;
    const host = S.el.querySelector('.ci-deskwrap');
    host.classList.remove('on');
    host.innerHTML = '';
    S.win = null;
    if (post) NZA.post('checkin:deskClose', {});
    sync();
  }
  function counts() {
    const d = S.desk || {}, list = d.tickets || [], beds = d.beds || [];
    const c = { waiting: 0, called: 0, treatment: 0, p1: 0, free: 0, beds: beds.length };
    list.forEach(t => { c[t.status] = (c[t.status] || 0) + 1; if (t.status === 'waiting' && t.triage === 1) c.p1++; });
    beds.forEach(b => { if (b.state === 'free') c.free++; });
    return c;
  }
  function navItems() {
    const c = counts();
    return [
      { group: tr('nav_group', 'Reception') },
      { id: 'queue', label: tr('nav_queue', 'Queue'), icon: 'ticket', tally: c.waiting + c.called + c.treatment },
      { id: 'beds', label: tr('nav_beds', 'Beds'), icon: 'bed', tally: `${c.free}/${c.beds}` },
      { id: 'today', label: tr('nav_today', 'Today'), icon: 'history', tally: ((S.desk || {}).history || []).length },
    ];
  }
  function deskMid() {
    const d = S.desk || {}, ai = d.ai || {};
    const staff = d.staff || 0;
    let aiTxt = '';
    if (ai.enabled) aiTxt = ai.standby ? `<span class="chipx sm teal">${icon('bolt')}${esc(tr('ai_standby', 'AI doctor on call'))}</span>` : (ai.treating ? `<span class="chipx sm teal">${icon('bolt')}${esc(fmtS(tr('ai_treating', 'AI doctor treating %d'), ai.treating))}</span>` : '');
    let hs = '';
    if (Array.isArray(d.hospitals) && d.hospitals.length > 1) {
      hs = `<select class="input ci-hsel">${d.hospitals.map(h => `<option value="${esc(h.id)}" ${h.id === d.hospital ? 'selected' : ''}>${esc(h.label)}</option>`).join('')}</select>`;
    }
    return `<span class="nz-dot"></span><p><b>${staff}</b> ${esc(tr('staff_on_duty', 'medical staff on shift'))} · <b>${counts().waiting}</b> ${esc(tr('waiting_lc', 'in the queue'))}</p>${aiTxt}${hs}`;
  }
  function renderDesk() {
    if (!S.win) return;
    const d = S.desk || {};
    S.win.el.querySelector('.w-brand .s').textContent = d.label || '';
    S.win.setNav(navItems());
    S.win.setMid(deskMid());
    const sel = S.win.el.querySelector('.ci-hsel');
    if (sel) sel.onchange = async () => { const r = await NZA.post('checkin:hospital', { id: sel.value }); if (r && r.ok && r.desk) { S.desk = r.desk; S.sel = null; renderDesk(); } else if (r && r.msg) NZA.toast({ title: tr('title', 'Check-in'), message: r.msg, type: 'error' }); };
    S.win.act.innerHTML = `<button class="btn-line btn-ic" data-a="refresh" title="${esc(tr('refresh', 'Refresh'))}">${icon('refresh')}</button><button class="btn-teal" data-a="callNext">${icon('bell')}${esc(tr('call_next', 'Call next patient'))}<kbd class="ci-kk">N</kbd></button>`;
    S.win.act.querySelector('[data-a="refresh"]').onclick = refresh;
    S.win.act.querySelector('[data-a="callNext"]').onclick = () => act('callNext', {});
    const m = S.win.main;
    if (S.tab === 'beds') m.innerHTML = pageBeds();
    else if (S.tab === 'today') m.innerHTML = pageToday();
    else m.innerHTML = pageQueue();
    bindDesk();
    tickDesk();
  }
  // instrument strip: four readouts with a status ring each
  function statTiles() {
    const c = counts(), d = S.desk || {}, st = d.stats || {};
    const occ = c.beds ? (c.beds - c.free) / c.beds : 0;
    const tile = (p, tone, ic, label, val, extra) => `<div class="ci-st ${tone}"><div class="ci-ring xs">${ringSVG(p, { r: 40, w: 9 })}<span class="ci-rc ic">${icon(ic)}</span></div><div class="ci-stt"><span>${esc(label)}</span><b>${val}</b></div>${extra || ''}</div>`;
    return `<div class="ci-stats">
      ${tile(Math.min(1, c.waiting / 8), c.p1 ? 'red' : '', 'ticket', tr('s_waiting', 'In the queue'), c.waiting, c.p1 ? `<em class="ci-delta red">${c.p1} P1</em>` : '')}
      ${tile(c.beds ? (c.treatment + c.called) / c.beds : 0, 'white', 'heart', tr('s_treatment', 'In treatment'), c.treatment + c.called, c.called ? `<em class="ci-delta">${c.called} ${esc(tr('s_called', 'called'))}</em>` : '')}
      ${tile(1 - occ, c.beds && !c.free ? 'red' : 'teal', 'bed', tr('s_beds', 'Beds open'), `${c.free}<small>/${c.beds}</small>`)}
      ${tile(st.avgWait != null ? Math.min(1, st.avgWait / WAIT_CAP) : 0, waitTone(st.avgWait || 0), 'timer', tr('s_avg', 'Average wait'), st.avgWait != null ? mmss(st.avgWait) : '--:--', st.served ? `<em class="ci-delta">${st.served} ${esc(tr('s_served', 'served'))}</em>` : '')}
    </div>`;
  }
  function stateLine(t) {
    const now = serverNow();
    if (t.status === 'waiting') return `<span class="ci-st2">${esc(stLabel('waiting'))}</span>`;
    if (t.status === 'called') return `<span class="ci-st2 teal">${esc(stLabel('called'))} ${icon('arrow-r')} <b class="bd">${esc(t.bed || '')}</b> · <b data-since="${t.called}">${mmss(now - (t.called || now))}</b></span>`;
    return `<span class="ci-st2 white">${esc(stLabel('treatment'))} · <b>${esc(t.bed || '')}</b>${t.ai ? ` · ${esc(tr('chip_ai', 'AI doctor'))}` : (t.by ? ` · ${esc(t.by)}` : '')}</span>`;
  }
  function pageQueue() {
    const list = (S.desk || {}).tickets || [];
    if (S.sel && !list.find(t => t.id === S.sel)) S.sel = null;
    if (!S.sel && list.length) S.sel = list[0].id;
    const now = serverNow();
    const rows = list.map((t, k) => {
      const tri = triOf(t);
      const waited = now - (t.issued || now);
      const inj = (t.injuries || []).slice(0, 4).map(i => `<span class="ci-inj" title="${esc(i.label)} · ${esc(i.region)}">${icon(TYPE_ICON[i.type] || 'medkit')}${esc(i.short || i.label)}</span>`).join('');
      const more = (t.injuryCount || 0) > 4 ? `<span class="ci-inj more">+${t.injuryCount - 4}</span>` : '';
      return `<button class="ci-q tri${tri} ${t.status} ${t.id === S.sel ? 'on' : ''}" data-id="${esc(t.id)}" style="animation-delay:${Math.min(k, 10) * 30}ms">
        <span class="ci-qbar"></span>
        <span class="ci-qring ${t.status === 'waiting' ? waitTone(waited) : t.status}" data-ring="${t.status === 'waiting' ? t.issued : ''}">${ringSVG(t.status === 'waiting' ? waited / WAIT_CAP : 1, { r: 40, w: 10 })}<b data-since="${t.status === 'waiting' ? t.issued : ''}">${t.status === 'waiting' ? mmss(waited) : ''}</b>${t.status === 'waiting' ? '' : `<span class="ci-rc ic">${icon(t.status === 'called' ? 'bell' : 'heart')}</span>`}</span>
        <span class="ci-qid"><span class="ci-qcode">${esc(t.code)}</span><span class="ci-tri sm p${tri}"><i></i><b>P${tri}</b>${esc(triLabel(tri, t.triageLabel))}</span></span>
        <span class="ci-qmain"><b>${esc(t.name || '?')}${t.online === false ? `<em class="ci-off">${esc(tr('offline', 'offline'))}</em>` : ''}</b><span class="ci-injs">${inj}${more}${!inj ? `<span class="ci-inj none">${esc(tr('no_injuries', 'Nothing listed'))}</span>` : ''}</span></span>
        ${stateLine(t)}
      </button>`;
    }).join('');
    const empty = `<div class="ci-empty">${icon('ticket')}<b>${esc(tr('q_empty', 'Nobody is waiting'))}</b><span>${esc(tr('q_empty_p', 'New tickets from the front desk show up here.'))}</span></div>`;
    return `
      <div class="w-head"><div><h1>${esc(tr('q_title', 'Patient queue'))}</h1><p>${esc(tr('q_sub', 'Critical patients first, then by arrival. Call a patient to an open bed — they get a waypoint and the board shows their number.'))}</p></div></div>
      ${statTiles()}
      <div class="ci-qgrid">
        <section class="w-panel"><div class="w-phead"><div><h2>${esc(tr('q_list', 'Tickets'))}</h2><p>${esc(fmtS(tr('q_n', '%d open tickets'), list.length))}</p></div></div>
          <div class="w-pbody ci-qlist">${rows || empty}</div></section>
        <section class="w-panel ci-detail">${detailHTML(list.find(t => t.id === S.sel))}</section>
      </div>`;
  }
  function freeBeds() { return ((S.desk || {}).beds || []).filter(b => b.state === 'free'); }
  function detailHTML(t) {
    if (!t) return `<div class="ci-empty">${icon('user')}<b>${esc(tr('d_none', 'No ticket selected'))}</b><span>${esc(tr('d_none_p', 'Pick a ticket on the left.'))}</span></div>`;
    const tri = triOf(t);
    const sev = s => `<span class="ci-sev">${[1, 2, 3, 4].map(i => `<i class="${i <= s ? 'on' : ''} s${s}"></i>`).join('')}</span>`;
    const inj = (t.injuries || []).map(i => `<div class="ci-drow"><span class="ci-dic">${icon(TYPE_ICON[i.type] || 'medkit')}</span><div><b>${esc(i.label)}</b><span>${esc(i.region)}</span></div>${sev(i.severity || 1)}</div>`).join('');
    const beds = freeBeds();
    const bedSel = beds.length ? `<select class="input ci-bed">${beds.map(b => `<option value="${esc(b.id)}">${esc(b.label)}</option>`).join('')}</select>` : `<span class="ci-nobed">${esc(tr('no_free_bed', 'No open bed'))}</span>`;
    let actions = '';
    if (t.status === 'waiting') {
      actions = `<div class="ci-dact"><div class="ci-callrow">${bedSel}<button class="btn-teal" data-a="call" ${beds.length ? '' : 'disabled'}>${icon('bell')}${esc(tr('a_call', 'Call'))}</button></div>
        ${(S.desk.ai || {}).enabled ? `<button class="btn-line btn-block" data-a="ai" ${beds.length ? '' : 'disabled'}>${icon('bolt')}${esc(tr('a_ai', 'Hand to the AI doctor'))}</button>` : ''}
        <button class="btn-red btn-block" data-a="cancel">${icon('x')}${esc(tr('a_cancel', 'Cancel ticket'))}</button></div>`;
    } else if (t.status === 'called') {
      actions = `<div class="ci-dact"><div class="ci-grid2"><button class="btn-line" data-a="recall">${icon('bell-ring')}${esc(tr('a_recall', 'Call again'))}</button><button class="btn-teal" data-a="treatment">${icon('heart')}${esc(tr('a_treatment', 'Arrived'))}</button></div>
        <div class="ci-grid2"><button class="btn-line" data-a="requeue">${icon('rot-l')}${esc(tr('a_requeue', 'Back to queue'))}</button><button class="btn-red" data-a="noshow">${icon('user-x')}${esc(tr('a_noshow', 'No-show'))}</button></div></div>`;
    } else {
      actions = `<div class="ci-dact"><button class="btn-teal btn-block" data-a="treated">${icon('check')}${esc(tr('a_treated', 'Mark as treated'))}</button>
        <button class="btn-line btn-block" data-a="requeue">${icon('rot-l')}${esc(tr('a_requeue', 'Back to queue'))}</button></div>`;
    }
    const blood = t.blood != null ? t.blood : null;
    return `
      <div class="ci-dhead tri${tri}">
        <div class="ci-ring md">${ringSVG(blood != null ? blood / 100 : 0, { r: 40, w: 8, ticks: 36, cls: blood != null && blood < 80 ? 'red' : '' })}<span class="ci-rc"><b>${blood != null ? blood : '--'}</b><small>${esc(tr('d_blood', 'Blood'))} %</small></span></div>
        <div class="ci-dmeta"><div class="ci-dcode">${esc(t.code)}</div><span class="ci-tri p${tri}"><i></i><b>P${tri}</b>${esc(triLabel(tri, t.triageLabel))}</span><span class="ci-dname">${esc(t.name || '?')}</span></div>
      </div>
      <div class="ci-dkv">
        <div><span>${esc(tr('d_status', 'Status'))}</span><b>${esc(t.bed && t.status !== 'waiting' ? t.bed : stLabel(t.status))}</b></div>
        <div><span>${esc(tr('d_waiting', 'In queue'))}</span><b data-since="${t.issued}">${mmss(serverNow() - t.issued)}</b></div>
        <div><span>${esc(tr('d_issued', 'Registered'))}</span><b>${hhmm(t.issued)}</b></div>
      </div>
      <div class="ci-dsec">${esc(tr('d_injuries', 'Reported injuries'))}<em>${t.injuryCount || 0}</em></div>
      <div class="ci-dlist nza-scroll">${inj || `<div class="ci-drow none">${esc(tr('no_injuries', 'Nothing listed'))}</div>`}</div>
      ${actions}`;
  }
  function pageBeds() {
    const beds = (S.desk || {}).beds || [];
    const cards = beds.map((b, k) => {
      const tone = b.state === 'free' ? 'teal' : b.state === 'reserved' ? 'amber' : 'white';
      return `<div class="ci-bedc ${b.state}" style="animation-delay:${Math.min(k, 12) * 35}ms">
        <div class="ci-ring sm ${tone}">${ringSVG(b.state === 'free' ? 0 : b.state === 'reserved' ? 0.5 : 1, { r: 40, w: 9 })}<span class="ci-rc ic">${icon(b.state === 'free' ? 'bed' : b.state === 'reserved' ? 'bell' : 'heart')}</span></div>
        <div class="ci-bedt"><b>${esc(b.label)}</b><span class="ci-bst ${tone}">${esc(tr('bed_' + b.state, b.state === 'free' ? 'Open' : b.state === 'reserved' ? 'Held' : 'In use'))}</span></div>
        <div class="ci-bedp">${b.ticket ? `<span class="ci-qcode sm">${esc(b.ticket)}</span>` : ''}<span>${esc(b.name || (b.state === 'free' ? tr('bed_ready', 'Ready for the next patient') : ''))}</span></div>
      </div>`;
    }).join('');
    return `<div class="w-head"><div><h1>${esc(tr('b_title', 'Beds'))}</h1><p>${esc(tr('b_sub', 'Every bed of this department. A held bed waits for the patient you called.'))}</p></div></div>
      ${statTiles()}
      <div class="ci-beds nza-scroll">${cards || `<div class="ci-empty">${icon('bed')}<b>${esc(tr('b_none', 'No beds placed'))}</b><span>${esc(tr('b_none_p', 'Place beds in /nzadmin → Positions to call patients.'))}</span></div>`}</div>`;
  }
  function pageToday() {
    const h = (S.desk || {}).history || [];
    const rows = h.map(t => {
      const tri = triOf(t);
      const st = STATUS[t.status] || STATUS.left;
      return `<tr><td><b class="ci-mono">${esc(t.code)}</b></td><td><span class="ci-tri sm p${tri}"><i></i><b>P${tri}</b></span></td><td>${esc(t.name || '?')}</td>
        <td><span class="chipx sm ${st[2] === 'red' ? 'red' : st[2] === 'teal' ? 'teal' : ''}">${esc(stLabel(t.status))}</span></td>
        <td class="ci-mono">${t.waited != null ? mmss(t.waited) : '--'}</td><td>${esc(t.by || '—')}</td><td class="ci-mono">${t.closed ? hhmm(t.closed) : '--'}</td></tr>`;
    }).join('');
    return `<div class="w-head"><div><h1>${esc(tr('h_title', 'Today'))}</h1><p>${esc(tr('h_sub', 'Closed tickets of this department.'))}</p></div></div>
      ${statTiles()}
      <section class="w-panel ci-hist"><div class="w-pbody">${rows ? `<table class="w-table"><thead><tr><th>${esc(tr('h_ticket', 'Ticket'))}</th><th>${esc(tr('h_tri', 'Triage'))}</th><th>${esc(tr('h_name', 'Name'))}</th><th>${esc(tr('h_status', 'Outcome'))}</th><th>${esc(tr('h_waited', 'Waited'))}</th><th>${esc(tr('h_by', 'Handled by'))}</th><th>${esc(tr('h_closed', 'Closed'))}</th></tr></thead><tbody>${rows}</tbody></table>`
        : `<div class="ci-empty">${icon('history')}<b>${esc(tr('h_none', 'Nothing yet today'))}</b><span>${esc(tr('h_none_p', 'Treated, no-show and cancelled tickets are listed here.'))}</span></div>`}</div></section>`;
  }
  function bindDesk() {
    const m = S.win.main;
    m.querySelectorAll('.ci-q').forEach(b => b.addEventListener('click', () => { S.sel = b.dataset.id; renderDesk(); }));
    m.querySelectorAll('.ci-detail [data-a]').forEach(b => b.addEventListener('click', () => {
      const bed = m.querySelector('.ci-detail .ci-bed');
      act(b.dataset.a, { id: S.sel, bed: bed ? bed.value : undefined });
    }));
    const sel = m.querySelector('.ci-q.on');
    if (sel && sel.scrollIntoView) sel.scrollIntoView({ block: 'nearest' });
  }
  async function act(action, data) {
    if (S.busy) return;
    S.busy = true;
    const res = await NZA.post('checkin:action', Object.assign({ action, hospital: (S.desk || {}).hospital }, data));
    S.busy = false;
    if (res && res.msg) NZA.toast({ title: tr('title', 'Check-in'), message: res.msg, type: res.ok ? 'success' : 'error', icon: 'ticket' });
    if (res && res.ok && action === 'callNext') NZA.audio.success();
  }
  async function refresh() {
    const res = await NZA.post('checkin:refresh', { hospital: (S.desk || {}).hospital });
    if (res && res.ok && res.desk) { S.desk = res.desk; setNow(res.desk.now); renderDesk(); }
  }
  function tickDesk() {
    if (!S.win) return;
    const now = serverNow();
    S.win.el.querySelectorAll('[data-since]').forEach(e => { const v = Number(e.dataset.since); if (v) e.textContent = mmss(now - v); });
    S.win.el.querySelectorAll('.ci-qring[data-ring]').forEach(e => {
      const v = Number(e.dataset.ring);
      if (!v) return;
      const s = now - v;
      setRing(e.querySelector('svg'), s / WAIT_CAP);
      e.classList.toggle('amber', waitTone(s) === 'amber');
      e.classList.toggle('red', waitTone(s) === 'red');
    });
  }
  function moveSel(dir) {
    const list = (S.desk || {}).tickets || [];
    if (!list.length) return;
    let i = list.findIndex(t => t.id === S.sel);
    i = Math.max(0, Math.min(list.length - 1, i + dir));
    S.sel = list[i].id;
    renderDesk();
  }

  /* ═══════════════════════ visibility / ticking ═══════════════════════ */
  function anyVisible() {
    const q = s => S.el.querySelector(s).classList.contains('on');
    return q('.ci-passwrap') || q('.ci-dockwrap') || performance.now() < S.sayUntil || S.deskOn;
  }
  function sync() {
    const vis = anyVisible();
    if (!vis && !S.hidden) { S.hidden = true; NZA.post('checkin:hidden', {}); }
    if (vis) S.hidden = false;
  }
  function tick() {
    const t = S.mine;
    const now = serverNow();
    if (t) {
      const w = S.el.querySelector('.ci-dockwrap [data-k="waited"]');
      if (w && t.issued) w.textContent = mmss(now - t.issued);
      const e = S.el.querySelector('.ci-dockwrap [data-k="est"]');
      if (e && t.issued) e.textContent = estText(t);
      const c = S.el.querySelector('.ci-dockwrap [data-k="calledFor"]');
      if (c && t.called) c.textContent = mmss(now - t.called);
    }
    if (S.pass) {
      const p = S.pass;
      const rw = S.el.querySelector('.ci-passwrap [data-k="wait"] b');
      if (rw && p.issued && p.status === 'waiting') rw.textContent = mmss(now - p.issued);
      const re = S.el.querySelector('.ci-passwrap [data-k="est"] b');
      if (re && p.status === 'waiting') re.textContent = estText(p);
      const rc = S.el.querySelector('.ci-passwrap [data-k="called"] b');
      if (rc && p.called) rc.textContent = mmss(now - p.called);
    }
    tickDesk();
  }

  function apply(d) {
    if (d.locale) L = Object.assign(L, d.locale);
    if (d.cfg) S.cfg = Object.assign(S.cfg, d.cfg);
    if (d.clock) setClock(d.clock);
    const t = d.ticket || d.mine;
    if (t && t.now) setNow(t.now);
    if ('mine' in d) S.mine = d.mine || null;
    if (d.mode === 'ticket' && d.ticket) {
      if (d.ticket.status !== 'expired' && (!S.mine || S.mine.id === d.ticket.id)) S.mine = d.ticket;
      showPass(d.ticket, d.print);
    }
    if (d.mode === 'desk' && d.desk) openDesk(d.desk);
    if (d.say) showSay(d.say);
    renderDock();
    sync();
  }

  NZA.app('checkin', {
    escClose: false,
    init(el) {
      S.el = el;
      el.innerHTML = '<div class="ci-dockwrap"></div><div class="ci-passwrap"></div><div class="ci-deskwrap"></div>';
    },
    open(d) {
      S.hidden = false;
      clearInterval(S.timer);
      S.timer = setInterval(tick, 1000);
      apply(d || {});
    },
    close() {
      clearInterval(S.timer);
      clearTimeout(S.passTimer); clearTimeout(S.sayTimer);
      S.deskOn = false; S.win = null; S.pass = null; S.odo = null; S.hidden = true; S.sayUntil = 0;
      S.el.querySelectorAll('.ci-dockwrap,.ci-passwrap,.ci-deskwrap').forEach(e => { e.classList.remove('on', 'out'); e.innerHTML = ''; });
    },
    msg: {
      mine(d) {
        const prev = S.mine;
        S.mine = d.ticket || null;
        if (S.mine && S.mine.now) setNow(S.mine.now);
        if (S.pass) {
          if (S.mine && S.mine.id === S.pass.id) S.pass = S.mine;
          else if (!S.mine && d.closed && d.closed.id === S.pass.id) S.pass = Object.assign({}, S.pass, { status: d.closed.status });
          updatePass();
        }
        if (S.mine && S.mine.status === 'called' && (!prev || prev.status !== 'called')) NZA.audio.ready();
        renderDock();
      },
      say(d) { showSay(d); },
      desk(d) { if (S.deskOn) { S.desk = d; setNow(d.now); renderDesk(); } },
      deskClosed() { closeDesk(false); },
      hideReceipt() { hidePass(); },
    },
    keys: {
      Escape() { if (S.deskOn) { closeDesk(true); return true; } return false; },
      ArrowDown() { if (!S.deskOn || S.tab !== 'queue') return false; moveSel(1); return true; },
      ArrowUp() { if (!S.deskOn || S.tab !== 'queue') return false; moveSel(-1); return true; },
      Enter() {
        if (!S.deskOn || S.tab !== 'queue' || (document.activeElement && document.activeElement.tagName === 'SELECT')) return false;
        const t = ((S.desk || {}).tickets || []).find(x => x.id === S.sel);
        if (!t || t.status !== 'waiting') return false;
        const bed = S.win && S.win.main.querySelector('.ci-detail .ci-bed');
        act('call', { id: t.id, bed: bed ? bed.value : undefined });
        return true;
      },
      KeyN() { if (!S.deskOn) return false; act('callNext', {}); return true; },
    },

    /* ═══════════════════════ browser preview ═══════════════════════
       ?app=checkin&view=ticket|p1|expired|chip|called|treat|desk|beds|today  (&print=1 replays the issue) */
    preview() {
      const now = Math.floor(Date.now() / 1000);
      const p = new URLSearchParams(location.search);
      const view = p.get('view') || 'ticket';
      const inj = (type, label, short, region, severity) => ({ type, label, short, region, severity, status: 'open' });
      const tickets = [
        { id: 'T8F3A21', code: 'A-013', number: 13, triage: 1, triageLabel: 'Critical', name: 'Rosa Diaz', status: 'waiting', issued: now - 142, ahead: 0, estimate: 0, online: true, blood: 71, injuryCount: 3, injuries: [inj('gunshot', 'Gunshot wound', 'GSW', 'Abdomen', 3), inj('fracture', 'Fracture', 'Fracture', 'Left lower leg', 2), inj('abrasion', 'Abrasion', 'Abrasion', 'Right upper arm', 1)] },
        { id: 'T8F3A22', code: 'A-014', number: 14, triage: 2, triageLabel: 'Urgent', name: 'Ben Carter', status: 'waiting', issued: now - 1018, ahead: 1, estimate: 240, online: true, blood: 92, injuryCount: 2, injuries: [inj('laceration', 'Deep laceration', 'Laceration', 'Left lower arm', 2), inj('contusion', 'Contusion', 'Contusion', 'Chest', 1)] },
        { id: 'T8F3A23', code: 'A-015', number: 15, triage: 3, triageLabel: 'Standard', name: 'Lily Chen', status: 'waiting', issued: now - 1595, ahead: 2, estimate: 720, online: false, blood: 99, injuryCount: 1, injuries: [inj('burn', 'Burn', 'Burn', 'Right lower arm', 1)] },
        { id: 'T8F3A19', code: 'A-011', number: 11, triage: 2, triageLabel: 'Urgent', name: 'Marcus Webb', status: 'called', issued: now - 905, called: now - 64, bed: 'Bed 2', bedId: 12, online: true, blood: 84, injuryCount: 1, injuries: [inj('stab', 'Stab wound', 'Stab', 'Chest', 2)] },
        { id: 'T8F3A17', code: 'A-009', number: 9, triage: 1, triageLabel: 'Critical', name: 'Ana Lopez', status: 'treatment', issued: now - 1520, called: now - 610, treatmentAt: now - 560, bed: 'Bed 1', bedId: 11, ai: false, by: 'Dr. K. Brooks', online: true, blood: 77, injuryCount: 2, injuries: [inj('internal', 'Internal bleeding', 'Internal', 'Abdomen', 3), inj('shrapnel', 'Shrapnel wound', 'Shrapnel', 'Right upper leg', 2)] },
      ];
      const beds = [{ id: 11, label: 'Bed 1', state: 'occupied', ticket: 'A-009', name: 'Ana Lopez' }, { id: 12, label: 'Bed 2', state: 'reserved', ticket: 'A-011', name: 'Marcus Webb' }, { id: 13, label: 'Bed 3', state: 'free' }, { id: 14, label: 'Bed 4', state: 'free' }, { id: 15, label: 'Bed 5', state: 'occupied', name: 'Unknown NPC' }, { id: 16, label: 'Bed 6', state: 'free' }];
      const history = [
        { code: 'A-008', triage: 3, name: 'Tom Hughes', status: 'done', waited: 312, by: 'Dr. K. Brooks', closed: now - 900 },
        { code: 'A-007', triage: 2, name: 'Sara Kim', status: 'done', waited: 188, by: 'Dr. Hale (AI)', closed: now - 1600 },
        { code: 'A-006', triage: 3, name: 'Dev Patel', status: 'noshow', waited: 640, by: 'Dr. K. Brooks', closed: now - 2300 },
        { code: 'A-005', triage: 1, name: 'Jon Ruiz', status: 'done', waited: 35, by: 'Dr. K. Brooks', closed: now - 3100 },
        { code: 'A-004', triage: 3, name: 'Mia Ford', status: 'left', waited: null, by: null, closed: now - 3900 },
      ];
      const desk = { hospital: 'pillbox', label: 'Pillbox Medical', now, tickets, beds, history, staff: 2, ai: { enabled: true, standby: false, treating: 0, timeout: 600 }, stats: { served: 3, noshow: 1, avgWait: 278 }, hospitals: [{ id: 'pillbox', label: 'Pillbox Medical' }, { id: 'sandy', label: 'Sandy Shores Medical' }] };
      const mine = { id: 'T8F3A22', code: 'A-014', number: 14, prefix: 'A', hospital: 'pillbox', hospitalLabel: 'Pillbox Medical', desk: 'Front desk', status: 'waiting', triage: 2, triageLabel: 'Urgent', issued: now - 64, ahead: 2, estimate: 960, now, name: 'Ben Carter' };
      const base = { cfg: { receiptTime: 0, ticketHud: true, printSound: false }, clock: { mode: 'game', h: 12, m: 1, msPerMin: 2000 } };
      NZA.mock('checkin:action', d => {
        const t = desk.tickets.find(x => x.id === d.id);
        if (d.action === 'callNext' || (d.action === 'call' && t)) {
          const tk = t || desk.tickets.filter(x => x.status === 'waiting').sort((a, b) => a.triage - b.triage || a.issued - b.issued)[0];
          const bed = desk.beds.find(b => String(b.id) === String(d.bed)) || desk.beds.find(b => b.state === 'free');
          if (!tk) return { ok: false, msg: 'Nobody is waiting.' };
          if (!bed) return { ok: false, msg: 'No open bed.' };
          tk.status = 'called'; tk.called = Math.floor(Date.now() / 1000); tk.bed = bed.label; bed.state = 'reserved'; bed.ticket = tk.code; bed.name = tk.name;
          setTimeout(() => NZA.apps.checkin.msg.desk(desk), 120);
          return { ok: true, msg: `Called ${tk.code} to ${bed.label}.` };
        }
        if (t && (d.action === 'treated' || d.action === 'noshow' || d.action === 'cancel')) {
          desk.tickets = desk.tickets.filter(x => x !== t);
          desk.history.unshift({ code: t.code, triage: t.triage, name: t.name, status: d.action === 'treated' ? 'done' : d.action === 'cancel' ? 'cancelled' : 'noshow', waited: 200, by: 'John Doe', closed: Math.floor(Date.now() / 1000) });
          setTimeout(() => NZA.apps.checkin.msg.desk(desk), 120);
          return { ok: true, msg: `${t.code} updated.` };
        }
        if (t && d.action === 'treatment') { t.status = 'treatment'; t.by = 'John Doe'; setTimeout(() => NZA.apps.checkin.msg.desk(desk), 120); return { ok: true }; }
        if (t && d.action === 'requeue') { t.status = 'waiting'; t.bed = null; setTimeout(() => NZA.apps.checkin.msg.desk(desk), 120); return { ok: true, msg: `${t.code} is back in the queue.` }; }
        return { ok: true, msg: 'Done.' };
      });
      NZA.mock('checkin:refresh', () => ({ ok: true, desk }));
      NZA.mock('checkin:hospital', () => ({ ok: true, desk }));
      if (view === 'desk' || view === 'beds' || view === 'today') {
        S.tab = view === 'desk' ? 'queue' : view;
        NZA.demo('checkin', Object.assign({}, base, { mode: 'desk', desk, mine: null }));
        return;
      }
      if (view === 'chip') {
        S.maxAhead[mine.id] = 4;
        NZA.demo('checkin', Object.assign({}, base, { mode: 'chip', mine }));
        return;
      }
      if (view === 'called') {
        NZA.demo('checkin', Object.assign({}, base, { mode: 'chip', mine: Object.assign({}, mine, { status: 'called', called: now - 12, bed: 'Bed 3', ahead: 0 }) }));
        return;
      }
      if (view === 'treat') {
        NZA.demo('checkin', Object.assign({}, base, { mode: 'chip', mine: Object.assign({}, mine, { status: 'treatment', bed: 'Bed 3', ai: true }) }));
        return;
      }
      if (view === 'expired') {
        NZA.demo('checkin', Object.assign({}, base, { mode: 'ticket', ticket: { code: 'A-006', hospitalLabel: 'Pillbox Medical', status: 'expired', triage: 3, issued: now - 4000, now }, mine: null }));
        return;
      }
      const ticket = view === 'p1' ? Object.assign({}, mine, { code: 'A-001', number: 1, triage: 1, triageLabel: 'Critical', ahead: 0, estimate: 0, issued: now - 1 }) : mine;
      if (view !== 'p1') S.maxAhead[ticket.id] = 4;
      NZA.demo('checkin', Object.assign({}, base, {
        mode: 'ticket', ticket, mine: ticket, print: p.get('print') === '1',
        say: { name: 'Maria', role: 'Reception', text: ticket.triage === 1 ? 'You need a doctor right away. Number A-001 — you go first.' : 'Number A-014 is yours. Two people are ahead of you — grab a seat, the board will call you.' },
      }));
    },
  });
})();
