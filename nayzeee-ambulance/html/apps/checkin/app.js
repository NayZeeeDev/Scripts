/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · app 'checkin'
   Check-in desk: thermal-paper receipt, ticket chip while you wait, receptionist
   subtitles and the staff reception window. Several layers can show at once; the
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

  /* ── deterministic barcode (Code-128 look) ── */
  function barcode(text, w = 236, h = 46) {
    let seed = 7;
    for (const ch of String(text)) seed = (seed * 31 + ch.charCodeAt(0)) >>> 0;
    const rnd = () => { seed = (seed * 1103515245 + 12345) >>> 0; return (seed >>> 16) / 65536; };
    const mods = [2, 1, 1, 2, 1, 1];          // start guard
    for (let i = 0; i < 26; i++) { for (let k = 0; k < 6; k++) mods.push(1 + Math.floor(rnd() * 3.2)); }
    mods.push(2, 3, 3, 1, 1, 1, 2);            // stop guard
    const total = mods.reduce((a, b) => a + b, 0);
    const unit = w / total;
    let x = 0, out = '';
    mods.forEach((m, i) => { if (i % 2 === 0) out += `<rect x="${x.toFixed(2)}" y="0" width="${(m * unit).toFixed(2)}" height="${h}"/>`; x += m * unit; });
    return `<svg viewBox="0 0 ${w} ${h}" width="${w}" height="${h}" preserveAspectRatio="none">${out}</svg>`;
  }

  /* ── thermal printer sound ── */
  function printSound(ms) {
    const a = NZA.audio;
    a.noise(ms, { vol: 0.045, lp: 5600, hp: 1900, attack: 0.04, release: 0.1 });
    const n = Math.floor(ms / 70);
    for (let i = 0; i < n; i++) a.tone(2400 + (i % 3) * 140, 14, { vol: 0.012, type: 'square', at: i * 0.07 });
    a.noise(140, { vol: 0.09, lp: 3800, hp: 700, at: ms / 1000 + 0.15, attack: 0.05, release: 0.5 });   // tear
  }

  const S = { el: null, cfg: { receiptTime: 14, ticketHud: true, printSound: true }, mine: null, receipt: null, receiptTimer: 0, sayTimer: 0, desk: null, deskOn: false, win: null, tab: 'queue', sel: null, busy: false, timer: 0, hidden: true };

  /* ═══════════════════════ RECEIPT ═══════════════════════ */
  function stampFor(t) {
    if (!t) return '';
    if (t.status === 'expired') return `<div class="ci-stamp red">${esc(tr('stamp_expired', 'Not valid'))}</div>`;
    if (t.status === 'called') return `<div class="ci-stamp teal">${esc(tr('stamp_called', 'Called'))}<small>${esc(t.bed || '')}</small></div>`;
    if (t.status === 'treatment') return `<div class="ci-stamp teal">${esc(tr('stamp_treatment', 'In treatment'))}</div>`;
    if (t.status === 'done') return `<div class="ci-stamp teal">${esc(tr('stamp_done', 'Treated'))}</div>`;
    if (t.status === 'left' || t.status === 'noshow' || t.status === 'cancelled') return `<div class="ci-stamp red">${esc(tr('stamp_closed', 'Closed'))}</div>`;
    return '';
  }
  function receiptRows(t) {
    const waited = t.issued ? serverNow() - t.issued : 0;
    const est = t.status === 'waiting' ? Math.max(0, (t.estimate || 0) - waited) : 0;
    const rows = [];
    if (t.name) rows.push([tr('r_patient', 'Patient'), t.name]);
    if (t.status === 'waiting' || t.ahead !== undefined) rows.push([tr('r_ahead', 'Patients ahead'), t.status === 'waiting' ? String(t.ahead || 0) : '0']);
    if (t.issued) rows.push([tr('r_waiting', 'Waiting'), mmss(waited), 'wait']);
    if (t.status === 'waiting') rows.push([tr('r_estimate', 'Est. wait'), est > 0 ? `~${Math.max(1, Math.round(est / 60))} ${tr('min', 'min')}` : tr('r_soon', 'Soon'), 'est']);
    if (t.bed && t.status !== 'waiting') rows.push([tr('r_bed', 'Go to'), t.bed]);
    if (t.issued) rows.push([tr('r_issued', 'Issued'), hhmm(t.issued)]);
    return rows.map(r => `<div class="ci-row" ${r[2] ? `data-k="${r[2]}"` : ''}><span>${esc(r[0])}</span><i></i><b>${esc(r[1])}</b></div>`).join('');
  }
  function receiptHTML(t) {
    const tri = Math.min(3, Math.max(1, t.triage || 3));
    const id = String(t.id || t.code || '').replace(/^T/, '');
    const rows = receiptRows(t);
    return `
      <div class="ci-paper">
        <div class="ci-hd"><div class="nz-mark sm"></div><div class="ci-hn"><b>${esc((t.hospitalLabel || tr('hospital', 'Hospital')).toUpperCase())}</b><span>${esc(t.desk || tr('desk', 'Check-in Desk'))}</span></div>${t.number ? `<span class="ci-no">#${esc(String(t.number).padStart(4, '0'))}</span>` : ''}</div>
        <div class="ci-cut"></div>
        <div class="ci-lbl">${esc(tr('your_number', 'Your number'))}</div>
        <div class="ci-num">${esc(t.code || '?')}</div>
        <div class="ci-tri p${tri}"><span class="dot">P${tri}</span><div><small>${esc(tr('triage', 'Triage'))}</small><b>${esc(triLabel(tri, t.triageLabel).toUpperCase())}</b></div></div>
        <div class="ci-cut"></div>
        ${rows ? `<div class="ci-rows">${rows}</div><div class="ci-cut"></div>` : ''}
        <div class="ci-bars">${barcode(t.id || t.code)}</div>
        <div class="ci-bc">${esc(id.toUpperCase())}</div>
        <p class="ci-foot">${esc(tr('receipt_foot', 'Please keep this ticket. Watch the screen for your number.'))}</p>
        <div class="ci-stamps">${stampFor(t)}</div>
      </div>`;
  }
  function showReceipt(t, print) {
    S.receipt = t;
    const host = S.el.querySelector('.ci-receipt');
    clearTimeout(S.receiptTimer);
    host.classList.remove('out');
    host.innerHTML = `
      <div class="ci-printer"><span class="ci-led"></span><span class="ci-slot"></span><span class="ci-pbrand"><span class="nz-mark xs"></span>NAYZEEE</span></div>
      <div class="ci-shadow ${print ? 'late' : ''}"></div>
      <div class="ci-feed">${receiptHTML(t)}</div>
      <div class="ci-hint">${icon('ticket')}<span>${esc(tr('receipt_hint', 'Ticket added to your inventory'))}</span></div>`;
    host.classList.add('on');
    const paper = host.querySelector('.ci-paper');
    if (print) {
      paper.classList.add('printing');
      if (S.cfg.printSound !== false) printSound(1500);
    }
    const secs = Number(S.cfg.receiptTime);
    if (secs > 0) S.receiptTimer = setTimeout(hideReceipt, (secs + (print ? 1.6 : 0)) * 1000);
    sync();
  }
  function hideReceipt() {
    const host = S.el.querySelector('.ci-receipt');
    if (!host.classList.contains('on')) return;
    clearTimeout(S.receiptTimer);
    host.classList.add('out');
    setTimeout(() => { host.classList.remove('on', 'out'); host.innerHTML = ''; S.receipt = null; sync(); }, 320);
  }
  function updateReceipt() {
    if (!S.receipt) return;
    const rows = S.el.querySelector('.ci-receipt .ci-rows');
    if (rows && S.receipt.issued) rows.innerHTML = receiptRows(S.receipt);
    const st = S.el.querySelector('.ci-receipt .ci-stamps');
    if (st) st.innerHTML = stampFor(S.receipt);
  }

  /* ═══════════════════════ TICKET CHIP ═══════════════════════ */
  function renderChip() {
    const host = S.el.querySelector('.ci-chipwrap');
    const t = S.mine;
    if (!t || S.cfg.ticketHud === false) { host.innerHTML = ''; host.classList.remove('on'); return; }
    host.classList.add('on');
    const tri = Math.min(3, Math.max(1, t.triage || 3));
    let body;
    if (t.status === 'called') {
      body = `<div class="ci-chip nza-hud solid called"><span class="ci-cic">${icon('bed')}</span>
        <div class="ci-cc"><small>${esc(tr('chip_called', 'Your number is called'))}</small><b>${esc(t.code)}<em>→</em>${esc(t.bed || tr('bed', 'Bed'))}</b></div>
        <div class="ci-csep"></div><div class="ci-ckv"><small>${esc(tr('chip_go', 'Go now'))}</small><b data-k="calledFor">${mmss(t.called ? serverNow() - t.called : 0)}</b></div>
        <span class="ci-pulse"></span></div>`;
    } else if (t.status === 'treatment') {
      body = `<div class="ci-chip nza-hud solid treat"><span class="ci-cic">${icon('heart')}</span>
        <div class="ci-cc"><small>${esc(t.ai ? tr('chip_ai', 'AI doctor') : tr('chip_treat', 'In treatment'))}</small><b>${esc(t.code)}<em>·</em>${esc(t.bed || '')}</b></div></div>`;
    } else {
      const waited = t.issued ? serverNow() - t.issued : 0;
      const est = Math.max(0, (t.estimate || 0) - waited);
      body = `<div class="ci-chip nza-hud solid"><span class="ci-cic">${icon('ticket')}</span>
        <div class="ci-cc"><small>${esc(tr('chip_ticket', 'Your ticket'))}</small><b>${esc(t.code)}</b></div>
        <span class="prio p${tri}">P${tri}</span>
        <div class="ci-csep"></div>
        <div class="ci-ckv"><small>${esc(tr('chip_ahead', 'Ahead'))}</small><b>${t.ahead || 0}</b></div>
        <div class="ci-ckv"><small>${esc(tr('chip_waiting', 'Waiting'))}</small><b data-k="waited">${mmss(waited)}</b></div>
        <div class="ci-ckv"><small>${esc(tr('chip_est', 'Est.'))}</small><b data-k="est">${est > 0 ? `~${Math.max(1, Math.round(est / 60))}${esc(tr('min_short', 'm'))}` : esc(tr('r_soon', 'Soon'))}</b></div></div>`;
    }
    host.innerHTML = body;
    sync();
  }

  /* ═══════════════════════ SAY (receptionist) ═══════════════════════ */
  function showSay(s) {
    if (!s || !s.text) return;
    const host = S.el.querySelector('.ci-say');
    clearTimeout(S.sayTimer);
    host.innerHTML = `<div class="ci-speech nza-hud solid"><span class="who"><span class="nz-mark xs"></span>${esc(s.role || tr('reception', 'Reception'))} · <b>${esc(s.name || '')}</b></span><span class="txt">${esc(s.text)}</span></div>`;
    host.classList.add('on');
    S.sayTimer = setTimeout(() => {
      const sp = host.querySelector('.ci-speech');
      if (sp) sp.classList.add('out');
      setTimeout(() => { host.classList.remove('on'); host.innerHTML = ''; sync(); }, 220);
    }, Math.max(3200, s.text.length * 70));
    sync();
  }

  /* ═══════════════════════ RECEPTION WINDOW (staff) ═══════════════════════ */
  const STATUS = {
    waiting: ['st_waiting', 'Waiting', ''], called: ['st_called', 'Called', 'teal'], treatment: ['st_treatment', 'In treatment', 'white'],
    done: ['st_done', 'Treated', 'teal'], noshow: ['st_noshow', 'No-show', 'red'], left: ['st_left', 'Left', ''], cancelled: ['st_cancelled', 'Cancelled', 'red'],
  };
  const stLabel = s => tr((STATUS[s] || STATUS.waiting)[0], (STATUS[s] || STATUS.waiting)[1]);

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
    return `<span class="nz-dot"></span><p><b>${staff}</b> ${esc(tr('staff_on_duty', 'medical staff on duty'))} · <b>${counts().waiting}</b> ${esc(tr('waiting_lc', 'waiting'))}</p>${aiTxt}${hs}`;
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
  function statTiles() {
    const c = counts(), d = S.desk || {}, st = d.stats || {};
    return `<div class="w-stats ci-stats">
      <div class="w-stat"><div class="nz-tile">${icon('ticket')}</div><div><span>${esc(tr('s_waiting', 'Waiting'))}</span><b>${c.waiting}</b></div>${c.p1 ? `<em class="ci-delta red">${c.p1} P1</em>` : ''}</div>
      <div class="w-stat"><div class="nz-tile">${icon('heart')}</div><div><span>${esc(tr('s_treatment', 'In treatment'))}</span><b>${c.treatment + c.called}</b></div>${c.called ? `<em class="ci-delta">${c.called} ${esc(tr('s_called', 'called'))}</em>` : ''}</div>
      <div class="w-stat"><div class="nz-tile">${icon('bed')}</div><div><span>${esc(tr('s_beds', 'Beds free'))}</span><b>${c.free}<small>/${c.beds}</small></b></div></div>
      <div class="w-stat"><div class="nz-tile">${icon('timer')}</div><div><span>${esc(tr('s_avg', 'Average wait'))}</span><b>${st.avgWait != null ? mmss(st.avgWait) : '--:--'}</b></div>${st.served ? `<em class="ci-delta">${st.served} ${esc(tr('s_served', 'served'))}</em>` : ''}</div>
    </div>`;
  }
  function stateLine(t) {
    const now = serverNow();
    if (t.status === 'waiting') return `<span class="ci-st">${esc(stLabel('waiting'))} <b data-since="${t.issued}">${mmss(now - t.issued)}</b></span>`;
    if (t.status === 'called') return `<span class="ci-st teal">${esc(stLabel('called'))} → <b class="bd">${esc(t.bed || '')}</b> · <b data-since="${t.called}">${mmss(now - (t.called || now))}</b></span>`;
    return `<span class="ci-st white">${esc(stLabel('treatment'))} · <b>${esc(t.bed || '')}</b>${t.ai ? ` · ${esc(tr('chip_ai', 'AI doctor'))}` : (t.by ? ` · ${esc(t.by)}` : '')}</span>`;
  }
  function pageQueue() {
    const list = (S.desk || {}).tickets || [];
    if (S.sel && !list.find(t => t.id === S.sel)) S.sel = null;
    if (!S.sel && list.length) S.sel = list[0].id;
    const rows = list.map(t => {
      const tri = Math.min(3, Math.max(1, t.triage || 3));
      const inj = (t.injuries || []).slice(0, 4).map(i => `<span class="ci-inj" title="${esc(i.label)} · ${esc(i.region)}">${icon(TYPE_ICON[i.type] || 'medkit')}${esc(i.short || i.label)}</span>`).join('');
      const more = (t.injuryCount || 0) > 4 ? `<span class="ci-inj more">+${t.injuryCount - 4}</span>` : '';
      return `<button class="ci-q tri${tri} ${t.status} ${t.id === S.sel ? 'on' : ''}" data-id="${esc(t.id)}">
        <span class="ci-qbar"></span>
        <span class="ci-qcode">${esc(t.code)}</span>
        <span class="prio p${tri}">P${tri}</span>
        <span class="ci-qmain"><b>${esc(t.name || '?')}${t.online === false ? `<em class="ci-off">${esc(tr('offline', 'offline'))}</em>` : ''}</b><span class="ci-injs">${inj}${more}${!inj ? `<span class="ci-inj none">${esc(tr('no_injuries', 'Nothing listed'))}</span>` : ''}</span></span>
        ${stateLine(t)}
      </button>`;
    }).join('');
    const empty = `<div class="ci-empty">${icon('ticket')}<b>${esc(tr('q_empty', 'Nobody is waiting'))}</b><span>${esc(tr('q_empty_p', 'New tickets from the check-in desk show up here.'))}</span></div>`;
    return `
      <div class="w-head"><div><h1>${esc(tr('q_title', 'Patient queue'))}</h1><p>${esc(tr('q_sub', 'Critical patients first, then by arrival. Call a patient to a free bed — they get a waypoint and the board shows their number.'))}</p></div></div>
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
    const tri = Math.min(3, Math.max(1, t.triage || 3));
    const sev = s => `<span class="ci-sev">${[1, 2, 3, 4].map(i => `<i class="${i <= s ? 'on' : ''} s${s}"></i>`).join('')}</span>`;
    const inj = (t.injuries || []).map(i => `<div class="ci-drow"><span class="ci-dic">${icon(TYPE_ICON[i.type] || 'medkit')}</span><div><b>${esc(i.label)}</b><span>${esc(i.region)}</span></div>${sev(i.severity || 1)}</div>`).join('');
    const beds = freeBeds();
    const bedSel = beds.length ? `<select class="input ci-bed">${beds.map(b => `<option value="${esc(b.id)}">${esc(b.label)}</option>`).join('')}</select>` : `<span class="ci-nobed">${esc(tr('no_free_bed', 'No free bed'))}</span>`;
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
    return `
      <div class="ci-dhead tri${tri}">
        <div class="ci-dcode">${esc(t.code)}</div>
        <div class="ci-dmeta"><span class="prio p${tri}">P${tri} ${esc(triLabel(tri, t.triageLabel).toUpperCase())}</span><span class="ci-dname">${esc(t.name || '?')}</span></div>
      </div>
      <div class="ci-dkv">
        <div><span>${esc(tr('d_status', 'Status'))}</span><b>${esc(t.bed && t.status !== 'waiting' ? t.bed : stLabel(t.status))}</b></div>
        <div><span>${esc(tr('d_waiting', 'Waiting'))}</span><b data-since="${t.issued}">${mmss(serverNow() - t.issued)}</b></div>
        <div><span>${esc(tr('d_issued', 'Issued'))}</span><b>${hhmm(t.issued)}</b></div>
        <div><span>${esc(tr('d_blood', 'Blood'))}</span><b class="${t.blood != null && t.blood < 80 ? 't-red' : ''}">${t.blood != null ? `${t.blood}%` : '--'}</b></div>
      </div>
      <div class="ci-dsec">${esc(tr('d_injuries', 'Reported injuries'))}<em>${t.injuryCount || 0}</em></div>
      <div class="ci-dlist nza-scroll">${inj || `<div class="ci-drow none">${esc(tr('no_injuries', 'Nothing listed'))}</div>`}</div>
      ${actions}`;
  }
  function pageBeds() {
    const beds = (S.desk || {}).beds || [];
    const cards = beds.map(b => `<div class="ci-bedc ${b.state}">
        <div class="ci-bedt">${icon('bed')}<b>${esc(b.label)}</b><span class="chipx sm ${b.state === 'free' ? 'teal' : b.state === 'reserved' ? 'amber' : ''}">${esc(tr('bed_' + b.state, b.state === 'free' ? 'Free' : b.state === 'reserved' ? 'Reserved' : 'Occupied'))}</span></div>
        <div class="ci-bedp">${b.ticket ? `<span class="ci-qcode sm">${esc(b.ticket)}</span>` : ''}<span>${esc(b.name || (b.state === 'free' ? tr('bed_ready', 'Ready for the next patient') : ''))}</span></div>
      </div>`).join('');
    return `<div class="w-head"><div><h1>${esc(tr('b_title', 'Beds'))}</h1><p>${esc(tr('b_sub', 'Every bed of this department. Reserved beds wait for a called patient.'))}</p></div></div>
      ${statTiles()}
      <div class="ci-beds nza-scroll">${cards || `<div class="ci-empty">${icon('bed')}<b>${esc(tr('b_none', 'No beds placed'))}</b><span>${esc(tr('b_none_p', 'Place beds in /nzadmin → Positions to call patients.'))}</span></div>`}</div>`;
  }
  function pageToday() {
    const h = (S.desk || {}).history || [];
    const rows = h.map(t => {
      const tri = Math.min(3, Math.max(1, t.triage || 3));
      const st = STATUS[t.status] || STATUS.left;
      return `<tr><td><b class="ci-mono">${esc(t.code)}</b></td><td><span class="prio p${tri}">P${tri}</span></td><td>${esc(t.name || '?')}</td>
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
    return q('.ci-receipt') || q('.ci-chipwrap') || q('.ci-say') || S.deskOn;
  }
  function sync() {
    const vis = anyVisible();
    if (!vis && !S.hidden) { S.hidden = true; NZA.post('checkin:hidden', {}); }
    if (vis) S.hidden = false;
  }
  function tick() {
    const t = S.mine;
    if (t) {
      const now = serverNow();
      const w = S.el.querySelector('.ci-chipwrap [data-k="waited"]');
      if (w && t.issued) w.textContent = mmss(now - t.issued);
      const e = S.el.querySelector('.ci-chipwrap [data-k="est"]');
      if (e && t.issued) { const est = Math.max(0, (t.estimate || 0) - (now - t.issued)); e.textContent = est > 0 ? `~${Math.max(1, Math.round(est / 60))}${tr('min_short', 'm')}` : tr('r_soon', 'Soon'); }
      const c = S.el.querySelector('.ci-chipwrap [data-k="calledFor"]');
      if (c && t.called) c.textContent = mmss(now - t.called);
    }
    if (S.receipt) {
      const rw = S.el.querySelector('.ci-receipt [data-k="wait"] b');
      if (rw && S.receipt.issued && (S.receipt.status === 'waiting' || S.receipt.status === 'called')) rw.textContent = mmss(serverNow() - S.receipt.issued);
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
      showReceipt(d.ticket, d.print);
    }
    if (d.mode === 'desk' && d.desk) openDesk(d.desk);
    if (d.say) showSay(d.say);
    renderChip();
    sync();
  }

  NZA.app('checkin', {
    escClose: false,
    init(el) {
      S.el = el;
      el.innerHTML = '<div class="ci-chipwrap"></div><div class="ci-receipt"></div><div class="ci-say"></div><div class="ci-deskwrap"></div>';
    },
    open(d) {
      S.hidden = false;
      clearInterval(S.timer);
      S.timer = setInterval(tick, 1000);
      apply(d || {});
    },
    close() {
      clearInterval(S.timer);
      clearTimeout(S.receiptTimer); clearTimeout(S.sayTimer);
      S.deskOn = false; S.win = null; S.receipt = null; S.hidden = true;
      S.el.querySelectorAll('.ci-chipwrap,.ci-receipt,.ci-say,.ci-deskwrap').forEach(e => { e.classList.remove('on', 'out'); e.innerHTML = ''; });
    },
    msg: {
      mine(d) {
        const prev = S.mine;
        S.mine = d.ticket || null;
        if (S.mine && S.mine.now) setNow(S.mine.now);
        if (S.receipt) {
          if (S.mine && S.mine.id === S.receipt.id) S.receipt = S.mine;
          else if (!S.mine && d.closed && d.closed.id === S.receipt.id) S.receipt = Object.assign({}, S.receipt, { status: d.closed.status });
          updateReceipt();
        }
        if (S.mine && S.mine.status === 'called' && (!prev || prev.status !== 'called')) NZA.audio.ready();
        renderChip();
      },
      say(d) { showSay(d); },
      desk(d) { if (S.deskOn) { S.desk = d; setNow(d.now); renderDesk(); } },
      deskClosed() { closeDesk(false); },
      hideReceipt() { hideReceipt(); },
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

    /* ═══════════════════════ browser preview ═══════════════════════ */
    preview() {
      const now = Math.floor(Date.now() / 1000);
      const p = new URLSearchParams(location.search);
      const view = p.get('view') || 'ticket';
      const inj = (type, label, short, region, severity) => ({ type, label, short, region, severity, status: 'open' });
      const tickets = [
        { id: 'T8F3A21', code: 'A-013', number: 13, triage: 1, triageLabel: 'Critical', name: 'Rosa Diaz', status: 'waiting', issued: now - 142, ahead: 0, estimate: 0, online: true, blood: 71, injuryCount: 3, injuries: [inj('gunshot', 'Gunshot wound', 'GSW', 'Abdomen', 3), inj('fracture', 'Fracture', 'Fracture', 'Left lower leg', 2), inj('abrasion', 'Abrasion', 'Abrasion', 'Right upper arm', 1)] },
        { id: 'T8F3A22', code: 'A-014', number: 14, triage: 2, triageLabel: 'Urgent', name: 'Ben Carter', status: 'waiting', issued: now - 418, ahead: 1, estimate: 240, online: true, blood: 92, injuryCount: 2, injuries: [inj('laceration', 'Deep laceration', 'Laceration', 'Left lower arm', 2), inj('contusion', 'Contusion', 'Contusion', 'Chest', 1)] },
        { id: 'T8F3A23', code: 'A-015', number: 15, triage: 3, triageLabel: 'Standard', name: 'Lily Chen', status: 'waiting', issued: now - 195, ahead: 2, estimate: 720, online: false, blood: 99, injuryCount: 1, injuries: [inj('burn', 'Burn', 'Burn', 'Right lower arm', 1)] },
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
      const mine = { id: 'T8F3A22', code: 'A-014', number: 14, prefix: 'A', hospital: 'pillbox', hospitalLabel: 'Pillbox Medical', desk: 'Check-in Desk', status: 'waiting', triage: 2, triageLabel: 'Urgent', issued: now - 61, ahead: 2, estimate: 960, now, name: 'Ben Carter' };
      const base = { cfg: { receiptTime: 0, ticketHud: true, printSound: false }, clock: { mode: 'game', h: 12, m: 1, msPerMin: 2000 } };
      NZA.mock('checkin:action', d => {
        const t = desk.tickets.find(x => x.id === d.id);
        if (d.action === 'callNext' || (d.action === 'call' && t)) {
          const tk = t || desk.tickets.filter(x => x.status === 'waiting').sort((a, b) => a.triage - b.triage || a.issued - b.issued)[0];
          const bed = desk.beds.find(b => String(b.id) === String(d.bed)) || desk.beds.find(b => b.state === 'free');
          if (!tk) return { ok: false, msg: 'Nobody is waiting.' };
          if (!bed) return { ok: false, msg: 'No free bed.' };
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
      const ticket = view === 'p1' ? Object.assign({}, mine, { code: 'A-001', number: 1, triage: 1, triageLabel: 'Critical', ahead: 0, estimate: 0, issued: now - 1 }) : mine;
      if (view === 'expired') {
        NZA.demo('checkin', Object.assign({}, base, { mode: 'ticket', ticket: { code: 'A-006', hospitalLabel: 'Pillbox Medical', status: 'expired', triage: 3, now }, mine: null }));
        return;
      }
      NZA.demo('checkin', Object.assign({}, base, {
        mode: 'ticket', ticket, mine: ticket, print: p.get('print') === '1',
        say: { name: 'Maria', role: 'Reception', text: ticket.triage === 1 ? 'Oh — you need a doctor right now. Number A-001, they will call you first.' : 'Here is your ticket, A-014. Two patients are ahead of you — please take a seat and watch the screen.' },
      }));
    },
  });
})();
