/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · dispatch board (UI v5 window)
   Overview · Calls (detail, timeline, patients, assign) · Units · Unit map (canvas,
   world → map projection) · Call log (nza_calls) · Hospital queue (check-in module +
   incoming ambulances).

   Lua → JS: open (board data + tab + locale + logLimit) · data (board data, every ~2 s)
     board data = { now, clock, self {x,y}, calls[], units[], hospitals[], queue[] | nil,
                    queueAvailable, incoming[], recent[], stats {…}, me {…} }
   JS → Lua: dispatch:respond {id} · dispatch:assign {id, src} · dispatch:unassign {id, src}
             dispatch:clear {id} · dispatch:closeCall {id} · dispatch:priority {id, priority}
             dispatch:gps {id} | {x, y} · dispatch:status {code} · dispatch:npc {on}
             dispatch:log {priority, search} → { rows, db } · dispatch:refresh → data
   Keys: ↑/↓ select call · R respond · G GPS · M map · ESC close
   ═══════════════════════════════════════════════════════════ */
(() => {
  const K = window.NZD;
  const esc = NZA.esc, icon = NZA.icon;
  let tr = K.tr({});
  let D = null, recvAt = 0, tab = 'overview', selId = null, win = null, logState = { prio: 0, search: '', rows: null, db: true, loading: false };
  let mapView = null, mapRaf = 0, mapHover = null, popover = null;
  let el;

  /* ─────────── helpers ─────────── */
  const ageOf = c => (c.age || 0) + (performance.now() - recvAt) / 1000;
  const prioChip = p => `<span class="prio p${K.prio(p)}">P${K.prio(p)}</span>`;
  const cap = s => (s ? String(s).charAt(0).toUpperCase() + String(s).slice(1) : '');
  const typeLabel = t => tr('type_' + t, cap(t));
  const HIST = { dsp: 'Dispatched', enr: 'En route', scn: 'On scene', care: 'Treating', trn: 'Transporting', hsp: 'At hospital', join: 'Unit joined', clr: 'Unit cleared', p1: 'Raised to P1', dup: 'Called again' };
  const histLabel = s => tr('hist_' + String(s).toLowerCase(), HIST[String(s).toLowerCase()] || s);
  const unitTone = s => K.unitStatusTone(s);
  const UNIT_LBL = { 108: 'Available', 107: 'Out of service', ENR: 'En route', SCN: 'On scene', CARE: 'Treating', TRN: 'Transporting', HSP: 'At hospital', DSP: 'Dispatched' };
  const unitLabel = s => { const k = String(s).replace('-', ''); return tr('unit_' + k, UNIT_LBL[k] || ''); };
  const unitChip = (s, full) => `<span class="ust ${unitTone(s)}">${esc(s)}${full ? `<span>${esc(unitLabel(s))}</span>` : ''}</span>`;
  const initials = n => String(n || '?').split(/\s+/).map(x => x[0] || '').join('').slice(0, 2).toUpperCase();
  const hhmm = t => { if (!t) return '--:--'; const d = new Date(t * 1000); return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`; };
  const dur = s => (s == null || isNaN(s) ? '—' : K.eta(s));
  const me = () => (D && D.me) || {};
  const calls = () => (D && D.calls) || [];
  const units = () => (D && D.units) || [];
  const callById = id => calls().find(c => c.id === id);
  const distTo = (x, y) => { const s = D && D.self; if (!s || x == null) return null; return Math.hypot(x - s.x, y - s.y); };
  const canAssign = () => !!me().canAssign;
  const where = c => K.where(c) || tr('unknown_location', 'Unknown location');
  const empty = (ic, title, text) => `<div class="db-empty"><span class="ei">${icon(ic)}</span><b>${esc(title)}</b><p>${esc(text)}</p></div>`;

  function keepScroll(fn) {
    const saved = {};
    el.querySelectorAll('[data-scroll]').forEach(s => { saved[s.dataset.scroll] = s.scrollTop; });
    fn();
    el.querySelectorAll('[data-scroll]').forEach(s => { if (saved[s.dataset.scroll] != null) s.scrollTop = saved[s.dataset.scroll]; });
  }

  async function act(name, data) {
    closePopover();
    const r = await NZA.post(`dispatch:${name}`, data || {});
    return r;
  }

  /* ─────────── window chrome ─────────── */
  function navItems() {
    const st = (D && D.stats) || {};
    return [
      { group: tr('db_g_ops', 'Operations') },
      { id: 'overview', label: tr('db_overview', 'Overview'), icon: 'grid' },
      { id: 'calls', label: tr('db_calls', 'Active calls'), icon: 'siren', tally: calls().length },
      { id: 'units', label: tr('db_units', 'Units'), icon: 'users', tally: units().length },
      { id: 'map', label: tr('db_map', 'Unit map'), icon: 'map' },
      { group: tr('db_g_rec', 'Records') },
      { id: 'log', label: tr('db_log', 'Call log'), icon: 'list' },
      { id: 'queue', label: tr('db_queue', 'Hospital queue'), icon: 'hospital', tally: st.waiting != null ? st.waiting : undefined },
    ];
  }

  function navTop() {
    const m = me();
    const st = m.call ? (m.status || 'ENR') : (m.oos ? '10-7' : '10-8');
    return `
      <div class="db-who"><div class="av">${esc(initials(m.name))}</div><div class="who-txt"><b>${esc(m.name || '')}</b><span>${esc([m.callsign, m.grade].filter(Boolean).join(' · '))}</span></div></div>
      <div class="db-shift">
        <div class="row"><span>${esc(tr('db_status', 'Status'))}</span>${unitChip(st, true)}</div>
        <div class="segc db-stseg" ${m.call ? 'data-locked="1"' : ''}><button data-st="10-8" class="${!m.oos && !m.call ? 'on' : ''}">10-8</button><button data-st="10-7" class="${m.oos ? 'on' : ''}">10-7</button></div>
        <div class="row tgl"><span>${esc(tr('db_npc', 'NPC calls'))}</span><button class="tg ${m.npc ? 'on' : ''}" data-npc><i></i></button></div>
      </div>`;
  }

  function chrome() {
    const st = (D && D.stats) || {};
    win.setMid(`<span class="nz-dot ${st.p1 ? 'red' : ''}"></span><p>${esc(tr('db_connected', 'Connected to dispatch'))} · <b>${st.onDuty || 0}</b> ${esc(tr('db_on_duty', 'on duty'))} · <b>${st.active || 0}</b> ${esc(tr('db_open', 'open calls'))}</p><span class="nz-ver">${esc(me().callsign || 'EMS')}</span>`);
    win.setNav(navItems());
    win.setStatus([
      { key: 'ESC', label: tr('db_k_close', 'Close') }, { key: '↑↓', label: tr('db_k_select', 'Select call') },
      { key: 'R', label: tr('db_k_respond', 'Respond') }, { key: 'G', label: tr('db_k_gps', 'Set GPS') }, { key: 'M', label: tr('db_k_map', 'Map') },
    ], `<span class="db-clock">${icon('clock')}<b>${esc((D && D.clock) || '--:--')}</b></span>`);
  }

  function bindSide() {
    const side = win.side;
    if (!side) return;
    side.onclick = e => {
      const s = e.target.closest('[data-st]');
      if (s && !s.parentElement.dataset.locked) { act('status', { code: s.dataset.st }); me().oos = s.dataset.st === '10-7'; refreshChrome(); return; }
      const n = e.target.closest('[data-npc]');
      if (n) { me().npc = !me().npc; act('npc', { on: me().npc }); refreshChrome(); }
    };
  }
  function refreshChrome() {
    chrome();
    win.side.querySelectorAll('.db-who,.db-shift').forEach(x => x.remove());
    win.side.insertAdjacentHTML('afterbegin', navTop());
  }

  /* ─────────── pages ─────────── */
  function callCard(c, opts = {}) {
    const p = K.prio(c.priority);
    const us = c.units || [];
    const mine = me().call === c.id;
    return `<article class="db-inc p${p} ${selId === c.id ? 'sel' : ''} ${mine ? 'mine' : ''}" data-call="${esc(c.id)}">
      <div class="inc-top">${prioChip(p)}<span class="db-code">${esc(c.code || '')}</span><span class="db-type">${icon(K.typeIcon(c.type))}${esc(typeLabel(c.type))}</span>
        <span class="ref">${esc(c.id)}</span><span class="db-age" data-age="${esc(c.id)}">${K.age(ageOf(c))}</span></div>
      <h3>${esc(c.title || '')}${mine ? `<span class="db-mine">${esc(tr('db_yours', 'Your call'))}</span>` : ''}</h3>
      <p>${icon('pin')}${esc(where(c))}${c.caller ? ` <span class="dim">· ${esc(c.caller)}</span>` : ''}</p>
      ${opts.compact ? '' : K.chain(c.status, tr, 'db-chain')}
      <div class="meta">${us.length ? us.map(u => `<span class="db-u ${unitTone(u.stage)}">${esc(u.callsign)}<i>${esc(u.stage)}</i></span>`).join('') : `<span class="db-unassigned">${icon('alert')}${esc(tr('db_unassigned', 'Unassigned'))}</span>`}
        <span class="sp"></span>${(c.patients || []).length ? `<span class="dim">${icon('person')}${(c.patients || []).length}</span>` : ''}${c.declined ? `<span class="dim">${icon('x')}${c.declined}</span>` : ''}</div>
    </article>`;
  }

  function pageOverview() {
    const st = (D && D.stats) || {};
    const list = calls();
    const ulist = units();
    return `
      <div class="w-head"><div><h1>${esc(tr('db_overview_t', 'Dispatch'))}</h1><p>${esc(tr('db_overview_p', 'Live calls, units on duty and the hospital queue.'))}</p></div>
        <div class="db-clockbig"><b>${esc((D && D.clock) || '--:--')}</b><span>${esc(tr('db_game_time', 'City time'))}</span></div></div>
      <div class="w-stats">
        <div class="w-stat"><div class="nz-tile ${st.p1 ? 'red' : ''}">${icon('siren')}</div><div><span>${esc(tr('db_s_open', 'Open calls'))}</span><b>${st.active || 0}</b></div>${st.p1 ? `<em class="delta dn">${st.p1} P1</em>` : ''}</div>
        <div class="w-stat"><div class="nz-tile">${icon('ambulance')}</div><div><span>${esc(tr('db_s_avail', 'Units free'))}</span><b>${st.available || 0}<small>/${st.onDuty || 0}</small></b></div>${st.onCall ? `<em class="delta">${st.onCall} ${esc(tr('db_s_busy', 'busy'))}</em>` : ''}</div>
        <div class="w-stat"><div class="nz-tile">${icon('timer')}</div><div><span>${esc(tr('db_s_resp', 'Avg. response'))}</span><b>${st.avgResponse != null ? K.eta(st.avgResponse) : '—'}</b></div>${st.served ? `<em class="delta">${st.served} ${esc(tr('db_s_served', 'today'))}</em>` : ''}</div>
        <div class="w-stat"><div class="nz-tile">${icon('hospital')}</div><div><span>${esc(tr('db_s_wait', 'Hospital queue'))}</span><b>${st.waiting != null ? st.waiting : '—'}</b></div>${(D.incoming || []).length ? `<em class="delta">${(D.incoming || []).length} ${esc(tr('db_s_incoming', 'incoming'))}</em>` : ''}</div>
      </div>
      <div class="db-cols">
        <section class="w-panel"><div class="w-phead"><div><h2>${esc(tr('db_calls', 'Active calls'))}</h2><p>${esc(tr('db_calls_p', 'Newest and most urgent first'))}</p></div>
          <button class="btn-ghost" data-go="calls">${icon('arrow-r')}${esc(tr('db_open_calls', 'Open'))}</button></div>
          <div class="w-pbody" data-scroll="ov-calls">${list.length ? list.map(c => callCard(c)).join('') : empty('siren', tr('db_no_calls', 'No open calls'), tr('db_no_calls_p', 'New calls show up here, on the call card and on your pager.'))}</div></section>
        <section class="w-panel"><div class="w-phead"><div><h2>${esc(tr('db_units', 'Units'))}</h2><p>${esc(K.fmt(tr('db_units_p', '%d medics signed in'), ulist.length))}</p></div>
          <button class="btn-ghost" data-go="map">${icon('map')}${esc(tr('db_map', 'Unit map'))}</button></div>
          <div class="w-pbody" data-scroll="ov-units">${ulist.length ? ulist.map(unitRow).join('') : empty('users', tr('db_no_units', 'No units on duty'), tr('db_no_units_p', 'Medics appear here when they go on duty.'))}</div></section>
      </div>`;
  }

  function unitRow(u) {
    const c = u.call && callById(u.call);
    const d = distTo(u.x, u.y);
    return `<div class="w-row db-unit" data-unit="${u.src}"><div class="av">${esc(initials(u.name))}</div>
      <div class="txt"><b>${esc(u.callsign)} <em class="nm">· ${esc(u.short || u.name)}</em></b><span>${esc(c ? `${c.id} · ${c.title}` : (u.grade || tr('db_medic', 'Medic')))}${d != null ? ` · ${K.dist(d).v}${K.dist(d).u}` : ''}${u.veh ? ` · ${esc(tr('db_in_vehicle', 'in vehicle'))}` : ''}</span></div>
      ${unitChip(u.status)}</div>`;
  }

  function pageCalls() {
    const list = calls();
    if (!selId || !callById(selId)) selId = list[0] ? list[0].id : null;
    const c = selId && callById(selId);
    return `
      <div class="db-split">
        <section class="w-panel db-list"><div class="w-phead"><div><h2>${esc(tr('db_calls', 'Active calls'))}</h2><p>${esc(K.fmt(tr('db_calls_n', '%d open'), list.length))}</p></div></div>
          <div class="w-pbody" data-scroll="calls-list">${list.length ? list.map(x => callCard(x, { compact: true })).join('') : empty('siren', tr('db_no_calls', 'No open calls'), tr('db_no_calls_p', 'New calls show up here, on the call card and on your pager.'))}</div></section>
        <section class="w-panel db-detail">${c ? detail(c) : empty('clipboard', tr('db_pick', 'Pick a call'), tr('db_pick_p', 'Select a call on the left to see the details.'))}</section>
      </div>`;
  }

  function detail(c) {
    const p = K.prio(c.priority);
    const mine = me().call === c.id;
    const onIt = (c.units || []).some(u => u.src === me().src);
    const d = distTo(c.x, c.y);
    const hist = (c.history || []).slice().reverse();
    const pts = c.patients || [];
    return `
      <div class="dt-head p${p}">
        <div class="dt-top">${prioChip(p)}<span class="db-code">${esc(c.code || '')}</span><span class="ref">${esc(c.id)}</span><span class="sp"></span>
          ${canAssign() ? `<span class="dt-plabel">${esc(tr('db_priority', 'Priority'))}</span><div class="segc db-pseg">${[1, 2, 3].map(n => `<button data-prio="${n}" class="${p === n ? 'on' : ''}">P${n}</button>`).join('')}</div>` : ''}
          <span class="db-age big" data-age="${esc(c.id)}">${K.age(ageOf(c))}</span></div>
        <div class="dt-title"><div class="nz-tile ${p === 1 ? 'red' : ''}">${icon(K.typeIcon(c.type))}</div><div><h2>${esc(c.title || '')}</h2><p>${icon('pin')}${esc(where(c))}${d != null ? ` · <b>${K.dist(d).v} ${K.dist(d).u}</b>` : ''}</p></div></div>
        ${K.chain(c.status, tr, 'db-chain big')}
        <div class="dt-acts">
          ${mine || onIt ? `<button class="btn-line" data-a="clear">${icon('x')}${esc(tr('db_a_clear', 'Clear'))}</button>` : `<button class="btn-teal" data-a="respond">${icon('siren')}${esc(tr('db_a_respond', 'Respond'))}<kbd>R</kbd></button>`}
          <button class="btn-line" data-a="gps">${icon('nav')}${esc(tr('db_a_gps', 'Set GPS'))}<kbd>G</kbd></button>
          ${canAssign() ? `<button class="btn-line" data-a="assign">${icon('user-plus')}${esc(tr('db_a_assign', 'Assign unit'))}</button>` : ''}
          <span class="sp"></span>
          ${canAssign() || onIt ? `<button class="btn-red" data-a="close">${icon('check')}${esc(tr('db_a_close', 'Close call'))}</button>` : ''}
        </div>
      </div>
      <div class="w-pbody dt-body" data-scroll="detail">
        ${c.caller || c.message ? `<div class="dt-box"><div class="lb">${icon('phone')}${esc(tr('cc_caller', 'Caller'))} <b>${esc(c.caller || tr('cc_unknown_caller', 'Unknown'))}</b>${c.phone ? `<span class="mono">${esc(c.phone)}</span>` : ''}<span class="sp"></span><span class="dim">${esc(tr('src_' + (c.source || 'system'), cap(c.source)))}</span></div>${c.message ? `<q>${esc(c.message)}</q>` : ''}</div>` : ''}
        <div class="dt-grid">
          <div class="dt-sec"><h4>${esc(tr('db_patients', 'Patients'))}<span>${pts.length}</span></h4>
            ${pts.length ? pts.map(pt => `<div class="dt-pt"><span class="tri t${pt.tri}">${esc(tr('tri_' + pt.tri, ['', 'Critical', 'Urgent', 'Standard'][pt.tri] || ''))}</span><div><b>${esc(pt.name || '?')}</b><span>${esc(tr('pst_' + pt.st, cap(pt.st)))}${(pt.tags || []).length ? ' · ' + pt.tags.map(typeLabel).map(esc).join(', ') : ''}</span></div></div>`).join('') : `<p class="dim sm">${esc(tr('db_no_patients', 'No patient linked yet'))}</p>`}
          </div>
          <div class="dt-sec"><h4>${esc(tr('db_on_call', 'Units on the call'))}<span>${(c.units || []).length}</span></h4>
            ${(c.units || []).length ? c.units.map(u => `<div class="dt-unit"><b>${esc(u.callsign)}</b><span class="dim">${esc(u.short || '')}</span><span class="sp"></span>${unitChip(u.stage)}${canAssign() || u.src === me().src ? `<button class="db-xs" data-unassign="${u.src}" title="${esc(tr('db_a_unassign', 'Take off the call'))}">${icon('x')}</button>` : ''}</div>`).join('') : `<p class="dim sm">${esc(tr('db_unassigned', 'Unassigned'))}${c.declined ? ` · ${esc(K.fmt(tr('db_declined', '%d declined'), c.declined))}` : ''}</p>`}
          </div>
        </div>
        <div class="dt-sec"><h4>${esc(tr('db_timeline', 'Timeline'))}</h4>
          <div class="dt-tl">${hist.map(h => `<div class="tl-i ${esc(String(h.s).toLowerCase())}"><i></i><span class="t">${hhmm(h.t)}</span><b>${esc(histLabel(h.s))}</b>${h.u ? `<span class="dim">${esc(h.u)}</span>` : ''}</div>`).join('')}
            <div class="tl-i created"><i></i><span class="t">${hhmm(c.created)}</span><b>${esc(tr('hist_created', 'Call created'))}</b><span class="dim">${esc(tr('src_' + (c.source || 'system'), cap(c.source)))}</span></div></div>
        </div>
      </div>`;
  }

  function pageUnits() {
    const ulist = units();
    const sel = (selId && callById(selId)) || calls().find(c => !(c.units || []).length) || null;
    return `
      <div class="w-head"><div><h1>${esc(tr('db_units', 'Units'))}</h1><p>${esc(tr('db_units_h', 'Everyone on duty, their status and where they are.'))}</p></div>
        <div class="db-legend">${['10-8', 'ENR', 'SCN', 'TRN', '10-7'].map(x => unitChip(x, true)).join('')}</div></div>
      <section class="w-panel grow"><div class="w-pbody" data-scroll="units">
        ${ulist.length ? `<table class="w-table db-table"><thead><tr><th>${esc(tr('db_t_unit', 'Unit'))}</th><th>${esc(tr('db_t_name', 'Name'))}</th><th>${esc(tr('db_t_grade', 'Grade'))}</th><th>${esc(tr('db_t_status', 'Status'))}</th><th>${esc(tr('db_t_call', 'Call'))}</th><th>${esc(tr('db_t_dist', 'Distance'))}</th><th></th></tr></thead><tbody>
          ${ulist.map(u => { const c = u.call && callById(u.call); const d = distTo(u.x, u.y); return `<tr>
            <td><b>${esc(u.callsign)}</b></td><td>${esc(u.name)}${u.offDuty ? ` <span class="dim sm">· ${esc(tr('db_off_duty', 'off duty'))}</span>` : ''}</td><td>${esc(u.grade || '—')}</td><td>${unitChip(u.status, true)}</td>
            <td>${c ? `<a class="db-link" data-call="${esc(c.id)}">${esc(c.id)} · ${esc(c.title)}</a>` : '<span class="dim">—</span>'}</td>
            <td>${d != null ? `${K.dist(d).v} ${K.dist(d).u}${u.veh ? ` ${icon('car')}` : ''}` : '—'}</td>
            <td class="r">${u.x != null ? `<button class="db-xs" data-gpsxy="${u.x},${u.y}" title="${esc(tr('db_a_gps', 'Set GPS'))}">${icon('nav')}</button>` : ''}
              ${canAssign() && sel && !u.call ? `<button class="btn-line btn-sm" data-assignto="${u.src}" data-for="${esc(sel.id)}">${icon('user-plus')}${esc(K.fmt(tr('db_a_send', 'Send to %s'), sel.id))}</button>` : ''}</td></tr>`; }).join('')}
          </tbody></table>` : empty('users', tr('db_no_units', 'No units on duty'), tr('db_no_units_p', 'Medics appear here when they go on duty.'))}
      </div></section>`;
  }

  function pageMap() {
    const sel = selId && callById(selId);
    return `
      <div class="db-mapwrap">
        <section class="w-panel db-map"><canvas class="db-cv"></canvas>
          <div class="db-mapbar"><button class="db-xs" data-map="in">${icon('plus')}</button><button class="db-xs" data-map="out">${icon('minus')}</button><button class="db-xs" data-map="fit">${icon('target')}</button></div>
          <div class="db-maplegend"><span><i class="lg p1"></i>P1</span><span><i class="lg p2"></i>P2</span><span><i class="lg p3"></i>P3</span><span><i class="lg unit"></i>${esc(tr('db_units', 'Units'))}</span><span><i class="lg hosp"></i>${esc(tr('hospital', 'Hospital'))}</span><span><i class="lg you"></i>${esc(tr('db_you', 'You'))}</span></div>
          <div class="db-tip"></div></section>
        <section class="w-panel db-mapside"><div class="w-phead"><div><h2>${esc(sel ? sel.id : tr('db_calls', 'Active calls'))}</h2><p>${esc(sel ? where(sel) : tr('db_map_p', 'Click a call on the map'))}</p></div></div>
          <div class="w-pbody" data-scroll="map-side">${sel ? callCard(sel) + `<div class="dt-acts col">${me().call === sel.id ? '' : `<button class="btn-teal btn-block" data-a="respond">${icon('siren')}${esc(tr('db_a_respond', 'Respond'))}</button>`}<button class="btn-line btn-block" data-a="gps">${icon('nav')}${esc(tr('db_a_gps', 'Set GPS'))}</button></div>` : ''}
            ${calls().filter(c => !sel || c.id !== sel.id).map(c => callCard(c, { compact: true })).join('')}
            ${!calls().length ? empty('map', tr('db_no_calls', 'No open calls'), tr('db_map_empty', 'Units and hospitals are still shown on the map.')) : ''}</div></section>
      </div>`;
  }

  function pageLog() {
    const rows = logState.rows;
    return `
      <div class="w-head"><div><h1>${esc(tr('db_log', 'Call log'))}</h1><p>${esc(logState.db ? tr('db_log_p', 'Every call handled by EMS, newest first.') : tr('db_log_mem', 'This session only (no database).'))}</p></div>
        <div class="db-filters"><div class="segc db-logseg">${[0, 1, 2, 3].map(n => `<button data-lp="${n}" class="${logState.prio === n ? 'on' : ''}">${n ? 'P' + n : esc(tr('db_all', 'All'))}</button>`).join('')}</div>
          <label class="db-search">${icon('search')}<input class="input" placeholder="${esc(tr('db_search', 'Search id, street, unit…'))}" value="${esc(logState.search)}"></label></div></div>
      <section class="w-panel grow"><div class="w-pbody" data-scroll="log">
        ${logState.loading && !rows ? `<div class="db-empty"><span class="ei spin">${icon('refresh')}</span><b>${esc(tr('db_loading', 'Loading…'))}</b></div>` : ''}
        ${rows && rows.length ? `<table class="w-table db-table"><thead><tr><th>${esc(tr('db_t_time', 'Time'))}</th><th>${esc(tr('db_t_call', 'Call'))}</th><th></th><th>${esc(tr('db_t_loc', 'Location'))}</th><th>${esc(tr('db_units', 'Units'))}</th><th>${esc(tr('db_t_resp', 'Response'))}</th><th>${esc(tr('db_t_dur', 'Duration'))}</th><th>${esc(tr('db_t_status', 'Status'))}</th></tr></thead><tbody>
          ${rows.map(r => `<tr><td class="mono">${hhmm(r.created)}<span class="dim sm">${r.created ? ' ' + new Date(r.created * 1000).toLocaleDateString() : ''}</span></td>
            <td><b>${esc(r.title || '')}</b><span class="dim sm"> ${esc(r.id)} · ${esc(r.code || '')}</span></td><td>${prioChip(r.priority)}</td>
            <td>${esc([r.zone, r.street].filter(Boolean).join(' · ') || '—')}</td>
            <td>${(r.units || []).length ? (Array.isArray(r.units) ? r.units.map(u => typeof u === 'string' ? u : (u.callsign || '')).map(esc).join(', ') : '') : '<span class="dim">—</span>'}</td>
            <td class="mono">${r.arrived && r.created ? dur(r.arrived - r.created) : (r.arrivedAt && r.created ? dur(r.arrivedAt - r.created) : '—')}</td>
            <td class="mono">${r.closed && r.created && r.closed !== true ? dur(r.closed - r.created) : '—'}</td>
            <td>${K.chain(r.status, null, 'db-chain xs')}<span class="dim sm">${esc(tr('reason_' + (r.reason || ''), cap(r.reason)))}</span></td></tr>`).join('')}
          </tbody></table>` : (!logState.loading ? empty('list', tr('db_log_empty', 'Nothing logged yet'), tr('db_log_empty_p', 'Closed calls are saved here.')) : '')}
      </div></section>`;
  }

  function pageQueue() {
    const q = D.queue;
    const inc = D.incoming || [];
    return `
      <div class="w-head"><div><h1>${esc(tr('db_queue', 'Hospital queue'))}</h1><p>${esc(tr('db_queue_p', 'Patients waiting at check-in and ambulances on their way in.'))}</p></div></div>
      <div class="db-cols">
        <section class="w-panel"><div class="w-phead"><div><h2>${esc(tr('db_q_waiting', 'Waiting at check-in'))}</h2><p>${esc(D.queueAvailable ? K.fmt(tr('db_q_n', '%d tickets'), (q || []).length) : tr('db_q_none', 'Check-in desks are not set up'))}</p></div></div>
          <div class="w-pbody" data-scroll="queue">${q && q.length ? `<table class="w-table db-table"><thead><tr><th>${esc(tr('db_t_ticket', 'Ticket'))}</th><th>${esc(tr('db_t_name', 'Name'))}</th><th></th><th>${esc(tr('db_t_wait', 'Waiting'))}</th><th>${esc(tr('db_t_status', 'Status'))}</th></tr></thead><tbody>
            ${q.map(e => `<tr><td class="mono"><b>${esc(e.ticket)}</b></td><td>${esc(e.name)}${e.hospital ? `<span class="dim sm"> · ${esc(e.hospital)}</span>` : ''}</td><td>${prioChip(e.priority)}</td><td class="mono">${K.eta(e.wait)}</td><td><span class="ust ${e.status === 'waiting' ? 'amber' : 'teal'}">${esc(tr('qst_' + e.status, cap(e.status)))}</span></td></tr>`).join('')}</tbody></table>`
            : empty('ticket', D.queueAvailable ? tr('db_q_empty', 'Nobody is waiting') : tr('db_q_off', 'No check-in queue'), D.queueAvailable ? tr('db_q_empty_p', 'Tickets from the check-in desk show up here.') : tr('db_q_off_p', 'Build a check-in desk in /nzadmin to use the queue.'))}</div></section>
        <section class="w-panel"><div class="w-phead"><div><h2>${esc(tr('db_q_incoming', 'Incoming ambulances'))}</h2><p>${esc(K.fmt(tr('db_q_inc_n', '%d transporting'), inc.length))}</p></div></div>
          <div class="w-pbody" data-scroll="incoming">${inc.length ? inc.map(i => `<div class="w-row"><div class="nz-tile ${i.priority === 1 ? 'red' : ''}">${icon('ambulance')}</div><div class="txt"><b>${esc(i.callsign)} <em class="nm">· ${esc(i.name || '')}</em></b><span>${esc(i.call || '')} · ${esc(i.title || '')} → ${esc(i.hospital || '')}</span></div>${prioChip(i.priority)}<div class="db-eta"><span>${esc(tr('cc_eta', 'ETA'))}</span><b>${K.eta(i.eta)}</b></div></div>`).join('')
            : empty('ambulance', tr('db_q_noinc', 'No ambulances inbound'), tr('db_q_noinc_p', 'Units transporting a patient show up here with their ETA.'))}</div></section>
      </div>`;
  }

  /* ─────────── render / events ─────────── */
  function render() {
    if (!win || !D) return;
    stopMap();
    keepScroll(() => {
      const fn = { overview: pageOverview, calls: pageCalls, units: pageUnits, map: pageMap, log: pageLog, queue: pageQueue }[tab] || pageOverview;
      win.main.innerHTML = fn();
      win.main.dataset.tab = tab;
    });
    if (tab === 'map') startMap();
    if (tab === 'log') bindLog();
  }

  function setTab(t) {
    tab = t;
    win.nav(t);
    refreshChrome();
    if (t === 'log' && !logState.rows) loadLog();
    render();
  }

  async function loadLog() {
    logState.loading = true;
    if (tab === 'log') render();
    const r = await NZA.post('dispatch:log', { priority: logState.prio || null, search: logState.search || null });
    logState.loading = false;
    logState.rows = (r && r.rows) || [];
    logState.db = !r || r.db !== false;
    if (tab === 'log') render();
  }

  let searchT = 0;
  function bindLog() {
    const inp = win.main.querySelector('.db-search input');
    if (!inp) return;
    inp.addEventListener('input', () => { logState.search = inp.value; clearTimeout(searchT); searchT = setTimeout(() => { loadLog().then(() => { const i = win.main.querySelector('.db-search input'); if (i) { i.focus(); i.setSelectionRange(i.value.length, i.value.length); } }); }, 350); });
  }

  function onClick(e) {
    const t = e.target;
    if (popover && !t.closest('.db-pop')) closePopover();
    const go = t.closest('[data-go]'); if (go) return setTab(go.dataset.go);
    const cc = t.closest('[data-call]');
    if (cc && !t.closest('button')) { selId = cc.dataset.call; if (tab === 'overview' || tab === 'units') return setTab('calls'); return render(); }
    const a = t.closest('[data-a]');
    if (a) return action(a.dataset.a, a);
    const pr = t.closest('[data-prio]'); if (pr && selId) { act('priority', { id: selId, priority: Number(pr.dataset.prio) }); pr.parentElement.querySelectorAll('button').forEach(b => b.classList.toggle('on', b === pr)); return; }
    const un = t.closest('[data-unassign]'); if (un && selId) { act('unassign', { id: selId, src: Number(un.dataset.unassign) }); return; }
    const as = t.closest('[data-assignto]'); if (as) { act('assign', { id: as.dataset.for || selId, src: Number(as.dataset.assignto) }); return; }
    const gx = t.closest('[data-gpsxy]'); if (gx) { const [x, y] = gx.dataset.gpsxy.split(',').map(Number); act('gps', { x, y }); return; }
    const pick = t.closest('[data-pick]'); if (pick && selId) { act('assign', { id: selId, src: Number(pick.dataset.pick) }); closePopover(); return; }
    const lp = t.closest('[data-lp]'); if (lp) { logState.prio = Number(lp.dataset.lp); loadLog(); return; }
    const mp = t.closest('[data-map]'); if (mp && mapView) { if (mp.dataset.map === 'fit') fitMap(); else zoomMap(mp.dataset.map === 'in' ? 1.5 : 1 / 1.5); }
  }

  function action(name, btn) {
    const c = selId && callById(selId);
    if (!c) return;
    if (name === 'respond') { act('respond', { id: c.id }); btn.disabled = true; }
    else if (name === 'gps') act('gps', { id: c.id });
    else if (name === 'clear') act('clear', { id: c.id });
    else if (name === 'assign') openAssign(btn, c);
    else if (name === 'close') {
      NZA.ui.Modal({
        title: K.fmt(tr('db_close_t', 'Close %s?'), c.id), text: tr('db_close_p', 'Units on it are released and the call moves to the log.'), icon: 'check', tone: 'teal',
        actions: [{ label: tr('db_cancel', 'Cancel'), kind: 'line' }, { label: tr('db_a_close', 'Close call'), kind: 'red', onClick: () => act('closeCall', { id: c.id }) }],
        host: el,
      });
    }
  }

  function openAssign(btn, c) {
    closePopover();
    const free = units().filter(u => !(c.units || []).some(x => x.src === u.src));
    popover = NZA.el('div', 'db-pop nza-pop');
    popover.innerHTML = `<div class="hd">${esc(tr('db_a_assign', 'Assign unit'))}</div>` + (free.length ? free.map(u => `<button data-pick="${u.src}"><b>${esc(u.callsign)}</b><span>${esc(u.short || u.name)}</span><span class="sp"></span>${unitChip(u.status)}</button>`).join('') : `<p>${esc(tr('db_no_free', 'No other units on duty'))}</p>`);
    const r = btn.getBoundingClientRect(), host = el.getBoundingClientRect();
    const z = r.width / (btn.offsetWidth || r.width) || 1;
    popover.style.left = `${(r.left - host.left) / z}px`;
    popover.style.top = `${(r.bottom - host.top) / z + 6}px`;
    el.appendChild(popover);
  }
  function closePopover() { if (popover) { popover.remove(); popover = null; } }

  /* ─────────── unit map (canvas) ─────────── */
  // stylised San Andreas outline (world metres; x east, y north)
  const LAND = [[-2100, -3200], [-1800, -3600], [-1000, -3700], [-200, -3500], [600, -3500], [1300, -3300], [1700, -2700], [2100, -2000], [2700, -1400], [2950, -700],
    [3050, 300], [2850, 1200], [3000, 2000], [3650, 2600], [3850, 3600], [3650, 4400], [3500, 5100], [3100, 5600], [2400, 6300], [1600, 6500], [700, 7400],
    [-100, 7600], [-700, 6900], [-1200, 6200], [-1700, 5600], [-2300, 4800], [-2800, 4100], [-3000, 3400], [-2700, 2900], [-3150, 2400], [-3300, 1600],
    [-3150, 800], [-2800, 300], [-2400, -300], [-2000, -700], [-1900, -1200], [-1700, -1700], [-2000, -2300], [-2200, -2800]];
  const LAKE = [[650, 4050], [1100, 3850], [1700, 3800], [2300, 3950], [2550, 4300], [2100, 4500], [1400, 4550], [900, 4450]];
  const PLACES = [['Los Santos', 150, -900, 1], ['Vespucci', -1250, -1350, 2], ['LSIA', -1250, -2950, 2], ['Port of LS', 900, -2950, 2], ['Vinewood Hills', 0, 900, 2],
    ['Chumash', -3000, 1050, 2], ['Fort Zancudo', -2250, 3100, 2], ['Sandy Shores', 1800, 3650, 2], ['Alamo Sea', 1550, 4200, 3], ['Grapeseed', 2000, 4900, 2],
    ['Paleto Bay', -250, 6350, 2], ['Mount Chiliad', 500, 5550, 3], ['Harmony', 600, 2700, 3], ['Tataviam', 2550, 300, 3], ['Del Perro', -1550, -650, 3], ['Mirror Park', 1150, -500, 3]];

  function mapCanvas() { return win && win.main.querySelector('.db-cv'); }

  function fitMap() {
    const pts = [];
    calls().forEach(c => pts.push([c.x, c.y]));
    units().forEach(u => { if (u.x != null) pts.push([u.x, u.y]); });
    if (D.self) pts.push([D.self.x, D.self.y]);
    let minX = -2200, maxX = 1600, minY = -3600, maxY = 1200;
    if (pts.length) {
      minX = Math.min(...pts.map(p => p[0])); maxX = Math.max(...pts.map(p => p[0]));
      minY = Math.min(...pts.map(p => p[1])); maxY = Math.max(...pts.map(p => p[1]));
      const span = Math.max(maxX - minX, maxY - minY, 1800);
      const cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
      minX = cx - span / 2; maxX = cx + span / 2; minY = cy - span / 2; maxY = cy + span / 2;
    }
    const pad = 1.25;
    mapView = { cx: (minX + maxX) / 2, cy: (minY + maxY) / 2, span: Math.max(maxX - minX, maxY - minY) * pad };
  }
  function zoomMap(f, at) {
    if (!mapView) return;
    const ns = Math.max(250, Math.min(16000, mapView.span / f));
    if (at) { const k = 1 - ns / mapView.span; mapView.cx += (at[0] - mapView.cx) * k; mapView.cy += (at[1] - mapView.cy) * k; }
    mapView.span = ns;
  }

  function startMap() {
    const cv = mapCanvas();
    if (!cv) return;
    if (!mapView) fitMap();
    let drag = null;
    const toWorld = (e) => {
      const r = cv.getBoundingClientRect();
      const fx = (e.clientX - r.left) / r.width, fy = (e.clientY - r.top) / r.height;
      const sc = mapScale(r.width, r.height);
      return [mapView.cx + (fx - 0.5) * r.width / sc, mapView.cy - (fy - 0.5) * r.height / sc];
    };
    cv.addEventListener('wheel', e => { e.preventDefault(); zoomMap(e.deltaY < 0 ? 1.25 : 0.8, toWorld(e)); }, { passive: false });
    cv.addEventListener('mousedown', e => { if (e.button === 0) drag = { x: e.clientX, y: e.clientY, cx: mapView.cx, cy: mapView.cy, moved: false }; });
    cv.addEventListener('mousemove', e => {
      const r = cv.getBoundingClientRect(), sc = mapScale(r.width, r.height);
      if (drag) {
        const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
        if (Math.abs(dx) + Math.abs(dy) > 3) drag.moved = true;
        mapView.cx = drag.cx - dx / sc; mapView.cy = drag.cy + dy / sc;
      }
      mapHover = hitTest(toWorld(e), sc);
      const tip = win.main.querySelector('.db-tip');
      if (tip) {
        if (mapHover) {
          tip.innerHTML = mapHover.html; tip.classList.add('on');
          tip.style.left = `${(e.clientX - r.left) / (r.width / cv.offsetWidth) + 14}px`; tip.style.top = `${(e.clientY - r.top) / (r.height / cv.offsetHeight) + 14}px`;
        } else tip.classList.remove('on');
      }
      cv.style.cursor = drag ? 'grabbing' : mapHover && mapHover.call ? 'pointer' : 'grab';
    });
    window.addEventListener('mouseup', mapUp);
    function mapUp() {
      if (drag && !drag.moved && mapHover && mapHover.call) { selId = mapHover.call; render(); }
      drag = null;
    }
    cv._up = mapUp;
    const loop = () => { drawMap(cv); mapRaf = requestAnimationFrame(loop); };
    loop();
  }
  function stopMap() {
    cancelAnimationFrame(mapRaf); mapRaf = 0;
    const cv = mapCanvas();
    if (cv && cv._up) window.removeEventListener('mouseup', cv._up);
  }
  const mapScale = (w, h) => Math.min(w, h) / mapView.span;

  function hitTest(w, sc) {
    const r = 12 / sc;
    for (const c of calls()) if (Math.hypot(c.x - w[0], c.y - w[1]) < r) return { call: c.id, html: `<b>${esc(c.id)} · ${esc(c.title)}</b><span>${esc(where(c))}</span><span>${(c.units || []).map(u => esc(u.callsign)).join(', ') || esc(tr('db_unassigned', 'Unassigned'))} · ${K.age(ageOf(c))}</span>` };
    for (const u of units()) if (u.x != null && Math.hypot(u.x - w[0], u.y - w[1]) < r) return { html: `<b>${esc(u.callsign)} · ${esc(u.short || u.name)}</b><span>${esc(u.status)} · ${esc(unitLabel(u.status))}</span>` };
    for (const h of (D.hospitals || [])) if (Math.hypot(h.x - w[0], h.y - w[1]) < r) return { html: `<b>${esc(h.label)}</b><span>${esc(tr('hospital', 'Hospital'))}</span>` };
    return null;
  }

  function drawMap(cv) {
    const { w, h } = NZA.fitCanvas(cv);
    const ctx = cv.getContext('2d');
    const dpr = w / Math.max(1, cv.clientWidth);
    const sc = mapScale(w, h);
    const X = x => w / 2 + (x - mapView.cx) * sc, Y = y => h / 2 - (y - mapView.cy) * sc;
    const t = performance.now() / 1000;
    ctx.clearRect(0, 0, w, h);
    ctx.fillStyle = '#060708'; ctx.fillRect(0, 0, w, h);
    // grid (1 km)
    const gStep = mapView.span > 9000 ? 2000 : mapView.span > 3500 ? 1000 : 500;
    ctx.strokeStyle = 'rgba(255,255,255,.035)'; ctx.lineWidth = 1;
    ctx.beginPath();
    for (let gx = Math.floor((mapView.cx - mapView.span) / gStep) * gStep; gx < mapView.cx + mapView.span; gx += gStep) { ctx.moveTo(X(gx), 0); ctx.lineTo(X(gx), h); }
    for (let gy = Math.floor((mapView.cy - mapView.span) / gStep) * gStep; gy < mapView.cy + mapView.span; gy += gStep) { ctx.moveTo(0, Y(gy)); ctx.lineTo(w, Y(gy)); }
    ctx.stroke();
    // land
    const poly = (pts) => { ctx.beginPath(); pts.forEach(([x, y], i) => (i ? ctx.lineTo(X(x), Y(y)) : ctx.moveTo(X(x), Y(y)))); ctx.closePath(); };
    poly(LAND);
    const g = ctx.createLinearGradient(0, 0, 0, h); g.addColorStop(0, '#111517'); g.addColorStop(1, '#0c0f10');
    ctx.fillStyle = g; ctx.fill();
    ctx.strokeStyle = 'rgba(8,175,162,.32)'; ctx.lineWidth = 1.4 * dpr; ctx.stroke();
    poly(LAKE); ctx.fillStyle = '#070909'; ctx.fill(); ctx.strokeStyle = 'rgba(8,175,162,.2)'; ctx.stroke();
    // grid over land (subtle)
    ctx.save(); poly(LAND); ctx.clip();
    ctx.strokeStyle = 'rgba(255,255,255,.03)'; ctx.beginPath();
    for (let gx = Math.floor((mapView.cx - mapView.span) / (gStep / 2)) * (gStep / 2); gx < mapView.cx + mapView.span; gx += gStep / 2) { ctx.moveTo(X(gx), 0); ctx.lineTo(X(gx), h); }
    for (let gy = Math.floor((mapView.cy - mapView.span) / (gStep / 2)) * (gStep / 2); gy < mapView.cy + mapView.span; gy += gStep / 2) { ctx.moveTo(0, Y(gy)); ctx.lineTo(w, Y(gy)); }
    ctx.stroke(); ctx.restore();
    // places
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    PLACES.forEach(([name, x, y, rank]) => {
      if (rank === 3 && mapView.span > 7000) return;
      if (rank === 2 && mapView.span > 12000) return;
      ctx.font = `${rank === 1 ? 600 : 500} ${(rank === 1 ? 12 : 10.5) * dpr}px Lexend, sans-serif`;
      ctx.fillStyle = rank === 1 ? 'rgba(255,255,255,.34)' : 'rgba(255,255,255,.2)';
      ctx.fillText(name.toUpperCase(), X(x), Y(y));
    });
    // hospitals
    (D.hospitals || []).forEach(hp => {
      const x = X(hp.x), y = Y(hp.y), s = 8 * dpr;
      ctx.fillStyle = 'rgba(8,175,162,.16)'; ctx.strokeStyle = 'rgba(15,212,196,.85)'; ctx.lineWidth = 1.4 * dpr;
      roundRect(ctx, x - s, y - s, s * 2, s * 2, 3 * dpr); ctx.fill(); ctx.stroke();
      ctx.fillStyle = '#0fd4c4'; ctx.font = `700 ${10 * dpr}px Lexend, sans-serif`; ctx.fillText('H', x, y + 0.5 * dpr);
    });
    // unit → call lines
    ctx.setLineDash([4 * dpr, 4 * dpr]); ctx.lineWidth = 1.2 * dpr;
    units().forEach(u => { const c = u.call && callById(u.call); if (!c || u.x == null) return; ctx.strokeStyle = 'rgba(255,255,255,.28)'; ctx.beginPath(); ctx.moveTo(X(u.x), Y(u.y)); ctx.lineTo(X(c.x), Y(c.y)); ctx.stroke(); });
    ctx.setLineDash([]);
    // calls
    const PC = { 1: [229, 72, 77], 2: [229, 165, 10], 3: [8, 175, 162] };
    calls().forEach(c => {
      const [r, gg, b] = PC[K.prio(c.priority)];
      const x = X(c.x), y = Y(c.y);
      const ph = (t * 0.8 + (c.x % 7) / 7) % 1;
      ctx.strokeStyle = `rgba(${r},${gg},${b},${0.55 * (1 - ph)})`; ctx.lineWidth = 2 * dpr;
      ctx.beginPath(); ctx.arc(x, y, (8 + ph * 20) * dpr, 0, Math.PI * 2); ctx.stroke();
      ctx.fillStyle = `rgb(${r},${gg},${b})`; ctx.beginPath(); ctx.arc(x, y, 6.5 * dpr, 0, Math.PI * 2); ctx.fill();
      ctx.strokeStyle = selId === c.id ? '#fff' : 'rgba(0,0,0,.6)'; ctx.lineWidth = (selId === c.id ? 2.4 : 1.5) * dpr; ctx.stroke();
      if (selId === c.id || mapView.span < 6000) {
        const label = `${c.code || ''} ${c.id}`;
        ctx.font = `600 ${10.5 * dpr}px Lexend, sans-serif`;
        const tw = ctx.measureText(label).width + 12 * dpr;
        ctx.fillStyle = 'rgba(12,13,16,.92)'; roundRect(ctx, x + 10 * dpr, y - 9 * dpr, tw, 18 * dpr, 5 * dpr); ctx.fill();
        ctx.strokeStyle = `rgba(${r},${gg},${b},.6)`; ctx.lineWidth = 1 * dpr; ctx.stroke();
        ctx.fillStyle = '#fff'; ctx.textAlign = 'left'; ctx.fillText(label, x + 16 * dpr, y + 0.5 * dpr); ctx.textAlign = 'center';
      }
    });
    // units
    const UC = { teal: '#0fd4c4', amber: '#f2b423', red: '#ff6b6f', white: '#ffffff', off: '#7a8186' };
    units().forEach(u => {
      if (u.x == null) return;
      const x = X(u.x), y = Y(u.y);
      ctx.save(); ctx.translate(x, y); ctx.rotate(-(u.h || 0) * Math.PI / 180);
      ctx.fillStyle = UC[unitTone(u.status)] || '#0fd4c4'; ctx.strokeStyle = 'rgba(0,0,0,.7)'; ctx.lineWidth = 1.4 * dpr;
      ctx.beginPath(); ctx.moveTo(0, -9 * dpr); ctx.lineTo(6.5 * dpr, 7 * dpr); ctx.lineTo(0, 3.5 * dpr); ctx.lineTo(-6.5 * dpr, 7 * dpr); ctx.closePath(); ctx.fill(); ctx.stroke();
      ctx.restore();
      if (mapView.span < 9000) {
        ctx.font = `600 ${9.5 * dpr}px Lexend, sans-serif`; ctx.fillStyle = 'rgba(255,255,255,.85)'; ctx.textAlign = 'center';
        ctx.fillText(u.callsign || '', x, y + 17 * dpr);
      }
    });
    // you
    if (D.self) {
      const x = X(D.self.x), y = Y(D.self.y);
      ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(x, y, 4.5 * dpr, 0, Math.PI * 2); ctx.fill();
      ctx.strokeStyle = 'rgba(255,255,255,.35)'; ctx.lineWidth = 6 * dpr; ctx.beginPath(); ctx.arc(x, y, 8 * dpr, 0, Math.PI * 2); ctx.stroke();
    }
    // scale bar
    const m = gStep, px = m * sc;
    ctx.strokeStyle = 'rgba(255,255,255,.5)'; ctx.lineWidth = 1.5 * dpr; ctx.beginPath();
    ctx.moveTo(16 * dpr, h - 18 * dpr); ctx.lineTo(16 * dpr + px, h - 18 * dpr); ctx.moveTo(16 * dpr, h - 22 * dpr); ctx.lineTo(16 * dpr, h - 14 * dpr); ctx.moveTo(16 * dpr + px, h - 22 * dpr); ctx.lineTo(16 * dpr + px, h - 14 * dpr); ctx.stroke();
    ctx.font = `500 ${9.5 * dpr}px Lexend, sans-serif`; ctx.fillStyle = 'rgba(255,255,255,.55)'; ctx.textAlign = 'left';
    ctx.fillText(m >= 1000 ? `${m / 1000} km` : `${m} m`, 22 * dpr + px, h - 18 * dpr);
    // compass
    ctx.textAlign = 'center'; ctx.font = `700 ${10 * dpr}px Lexend, sans-serif`; ctx.fillStyle = 'rgba(255,255,255,.5)'; ctx.fillText('N', w - 22 * dpr, 20 * dpr);
    ctx.beginPath(); ctx.moveTo(w - 22 * dpr, 28 * dpr); ctx.lineTo(w - 26 * dpr, 38 * dpr); ctx.lineTo(w - 18 * dpr, 38 * dpr); ctx.closePath(); ctx.fill();
  }
  function roundRect(ctx, x, y, w, h, r) { ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r); ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath(); }

  /* ─────────── ages tick ─────────── */
  let ageT = 0;
  function tickAges() {
    if (!win) return;
    win.main.querySelectorAll('[data-age]').forEach(x => { const c = callById(x.dataset.age); if (c) x.textContent = K.age(ageOf(c)); });
  }

  function apply(data, first) {
    D = data || D || {};
    recvAt = performance.now();
    if (data && data.locale) tr = K.tr(data.locale);
    if (!win) return;
    refreshChrome();
    if (first) { render(); return; }
    // live refresh: keep inputs alive on the log page, re-render the rest
    if (tab === 'log') return;
    if (tab === 'map') {
      const side = win.main.querySelector('.db-mapside');
      if (side) {
        const tmp = NZA.el('div', '', pageMap());
        const ns = tmp.querySelector('.db-mapside');
        keepScroll(() => side.replaceWith(ns));
      }
      return;
    }
    if (el.querySelector('.nza-modal-wrap') || popover) return;
    render();
  }

  NZA.app('dispatch', {
    full: true,
    init(root) { el = root; },
    open(d) {
      el.innerHTML = '<div class="nza-dim"></div>';
      tab = (d && d.tab) || 'overview';
      if (tab === 'log') logState.rows = null;
      if (d && d.locale) tr = K.tr(d.locale);
      D = d;
      win = NZA.ui.Win(el, {
        title: tr('db_title', 'Dispatch'), sub: tr('db_sub', 'Emergency Medical Services'), width: '1280px', height: '780px',
        nav: navItems(), navValue: tab,
        onNav: v => setTab(v), onClose: () => NZA.close('dispatch'),
      });
      win.el.classList.add('db-win');
      win.el.addEventListener('click', onClick);
      bindSide();
      apply(d, true);
      if (tab === 'log') loadLog();
      clearInterval(ageT); ageT = setInterval(tickAges, 1000);
    },
    close() { stopMap(); clearInterval(ageT); closePopover(); if (win) win.destroy(); win = null; el.innerHTML = ''; mapView = null; },
    msg: { data(d) { apply(d, false); } },
    keys: {
      ArrowDown(e) { if (e.target.closest && e.target.closest('input')) return false; moveSel(1); },
      ArrowUp(e) { if (e.target.closest && e.target.closest('input')) return false; moveSel(-1); },
      r(e) { if (e.target.closest && e.target.closest('input')) return false; const c = selId && callById(selId); if (c && me().call !== c.id) act('respond', { id: c.id }); },
      g(e) { if (e.target.closest && e.target.closest('input')) return false; if (selId) act('gps', { id: selId }); },
      m(e) { if (e.target.closest && e.target.closest('input')) return false; setTab('map'); },
      Escape() { if (popover) { closePopover(); return; } const m = el.querySelector('.nza-modal-wrap'); if (m) { m.remove(); return; } NZA.close('dispatch'); },
    },
    preview() {
      const now = Math.floor(Date.now() / 1000);
      const demo = {
        clock: '16:42', now, self: { x: 310, y: -600 },
        me: { src: 1, name: 'John Doe', callsign: 'Unit 04', grade: 'Paramedic', status: 'ENR', call: 'C-0416', npc: true, oos: false, canAssign: true },
        calls: [
          { id: 'C-0418', code: '10-52', priority: 1, title: 'Gunshot Wound', type: 'gunshot', x: -1120, y: -1250, zone: 'Vespucci Canals', street: 'Imagination Ct / Prosperity St', caller: 'Michael Garcia', phone: '555-0142',
            message: "My friend's been shot in the chest, he's bleeding a lot!", age: 42, status: 'DSP', units: [], declined: 1, source: 'player',
            patients: [{ pid: 'p:1', name: 'Tony Russo', tri: 1, st: 'wounded', tags: ['gunshot'] }], history: [{ s: 'DSP', t: now - 42 }], created: now - 42 },
          { id: 'C-0416', code: '10-50', priority: 2, title: 'Vehicle Collision', type: 'mva', x: 120, y: -1010, zone: 'Pillbox Hill', street: 'Palomino Ave', caller: 'Witness', age: 260, status: 'ENR', source: 'npc', npc: true,
            units: [{ src: 1, callsign: 'Unit 04', short: 'J. Doe', stage: 'ENR' }, { src: 3, callsign: 'Unit 09', short: 'T. Kane', stage: 'SCN' }],
            patients: [{ pid: 'n:1', name: 'Ana Silva', tri: 2, st: 'wounded', tags: ['fracture', 'laceration'] }, { pid: 'n:2', name: 'Dean Price', tri: 3, st: 'alive', tags: ['contusion'] }],
            history: [{ s: 'DSP', t: now - 260 }, { s: 'JOIN', t: now - 200, u: 'Unit 09' }, { s: 'ENR', t: now - 200, u: 'Unit 09' }, { s: 'SCN', t: now - 80, u: 'Unit 09' }, { s: 'JOIN', t: now - 30, u: 'Unit 04' }], created: now - 260 },
          { id: 'C-0415', code: '10-56', priority: 3, title: 'Overdose', type: 'overdose', x: 1700, y: 3650, zone: 'Sandy Shores', street: 'Alhambra Dr', age: 610, status: 'TRN', source: 'npc', npc: true,
            units: [{ src: 5, callsign: 'Unit 12', short: 'M. Reyes', stage: 'TRN' }], patients: [{ pid: 'n:3', name: 'Kyle Ward', tri: 2, st: 'wounded', tags: [] }], history: [{ s: 'DSP', t: now - 610 }], created: now - 610 },
        ],
        units: [
          { src: 1, name: 'John Doe', short: 'J. Doe', callsign: 'Unit 04', grade: 'Paramedic', status: 'ENR', call: 'C-0416', x: 300, y: -620, h: 20, veh: true },
          { src: 3, name: 'Theo Kane', short: 'T. Kane', callsign: 'Unit 09', grade: 'EMT', status: 'SCN', call: 'C-0416', x: 130, y: -1000, h: 200 },
          { src: 5, name: 'Maya Reyes', short: 'M. Reyes', callsign: 'Unit 12', grade: 'Paramedic', status: 'TRN', call: 'C-0415', x: 1500, y: 3000, h: 160, veh: true },
          { src: 7, name: 'Sam Brooks', short: 'S. Brooks', callsign: 'Unit 15', grade: 'Trainee', status: '10-8', x: -400, y: -300, h: 90 },
          { src: 8, name: 'Lena Ortiz', short: 'L. Ortiz', callsign: 'Unit 21', grade: 'Doctor', status: '10-7', x: 320, y: -560, h: 0 },
        ],
        hospitals: [{ id: 'h1', label: 'Pillbox Medical', x: 298, y: -584 }, { id: 'h2', label: 'Sandy Shores Medical', x: 1839, y: 3672 }, { id: 'h3', label: 'Paleto Bay Clinic', x: -247, y: 6331 }],
        queue: [{ ticket: 'A-014', name: 'Rosa Diaz', priority: 2, wait: 380, status: 'waiting', hospital: 'Pillbox' }, { ticket: 'A-015', name: 'Ben Carter', priority: 3, wait: 140, status: 'waiting' }, { ticket: 'A-012', name: 'Lily Chen', priority: 1, wait: 620, status: 'treatment' }],
        queueAvailable: true,
        incoming: [{ callsign: 'Unit 12', name: 'M. Reyes', call: 'C-0415', title: 'Overdose', priority: 3, hospital: 'Sandy Shores Medical', eta: 64 }],
        stats: { active: 3, p1: 1, available: 1, onDuty: 5, onCall: 3, avgResponse: 236, served: 14, waiting: 3 },
        locale: {}, tab: 'overview',
      };
      NZA.mock('dispatch:log', () => ({ db: true, rows: [
        { id: 'C-0414', code: '10-52', priority: 1, title: 'Stab Wound', type: 'stab', zone: 'Davis', street: 'Grove St', units: ['Unit 04', 'Unit 09'], status: 'HSP', reason: 'hospital', created: now - 3600, arrived: now - 3330, closed: now - 2700 },
        { id: 'C-0413', code: '10-50', priority: 2, title: 'Vehicle Collision', type: 'mva', zone: 'Rockford Hills', street: 'Portola Dr', units: ['Unit 12'], status: 'SCN', reason: 'cleared', created: now - 5400, arrived: now - 5100, closed: now - 4600 },
        { id: 'C-0411', code: '10-52', priority: 3, title: 'Fall', type: 'fall', zone: 'Vinewood', street: 'Hawick Ave', units: [], status: 'DSP', reason: 'expired', created: now - 9000, closed: now - 8100 },
      ] }));
      NZA.demo('dispatch', demo);
    },
  });

  function moveSel(dir) {
    const list = calls();
    if (!list.length) return;
    const i = list.findIndex(c => c.id === selId);
    selId = list[(i + dir + list.length) % list.length].id;
    if (tab === 'overview' || tab === 'units') setTab('calls'); else render();
  }
})();
