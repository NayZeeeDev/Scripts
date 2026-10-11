'use strict';
/* ═══ DASHBOARD ═════════════════════════════════════════════════════════ */
page('dashboard', {
  label: 'Dashboard', icon: 'fas fa-chart-simple', perms: ['statistics.view'],
  async enter() { await loadDash(); },
  render() {
    const st = pd('dashboard');
    const d = st.data;
    const head = ph('Dashboard', d ? `${d.server.name} · up ${dur(d.uptime)}` : 'Server overview', btn('Refresh', 'dashRefresh', 'btn-ghost sm', { icon: 'fas fa-rotate' }));
    if (!d) return head + `<div class="content">${loading()}</div>`;
    const stat = (lbl, icon, val, sub, c, pct) => `<div class="stat" style="--c:${c || 'var(--teal)'}"><div class="lbl"><i class="${icon}"></i>${esc(lbl)}</div><div class="val">${val}</div><div class="sub">${sub || ''}</div>${pct !== undefined ? `<div class="meter"><i style="width:${Math.min(100, pct)}%"></i></div>` : ''}</div>`;
    const chart = d.chart || [];
    const labels = chart.map(p => clock(p.ts));
    const jobsMax = Math.max(1, ...(d.jobs || []).map(j => j.count));
    return head + `<div class="content"><div class="stack">
      <div class="g4">
        ${stat('Players online', 'fas fa-users', `${num(d.online)}<small>/ ${d.max}</small>`, `${num(d.unique)} unique all time`, 'var(--teal)', d.online / d.max * 100)}
        ${stat('Staff on duty', 'fas fa-user-shield', `${d.staffDuty}<small>/ ${d.staffOnline} online</small>`, `${d.jailed} player${d.jailed === 1 ? '' : 's'} jailed`, '#4c9aff', d.staffOnline ? d.staffDuty / d.staffOnline * 100 : 0)}
        ${stat('Open reports', 'fas fa-flag', num(d.reportsOpen), `${num(d.reportsToday)} created today`, d.reportsOpen ? 'var(--red)' : 'var(--teal)')}
        ${stat('Active bans', 'fas fa-gavel', num(d.bans), `${num(d.warningsWeek)} warnings this week`, 'var(--amber)')}
      </div>
      <div class="g-dash">
        <div class="card"><div class="card-h"><h3><i class="fas fa-chart-line"></i>Last 24 hours</h3><div class="r legend"><span><i class="dotc" style="background:#08afa2"></i>Players</span><span><i class="dotc" style="background:#4c9aff"></i>Staff</span></div></div>
          <div class="card-b">${chart.length > 1 ? lineChart([{ values: chart.map(p => p.players), color: '#08afa2' }, { values: chart.map(p => p.staff), color: '#4c9aff', fill: false, dash: true }], labels, { id: 'dash' }) : empty('fas fa-chart-line', 'Collecting data', 'Player counts are sampled every 5 minutes.')}</div></div>
        <div class="card"><div class="card-h"><h3><i class="fas fa-briefcase"></i>Jobs online</h3></div>
          <div class="card-b">${(d.jobs || []).length ? `<div class="bars">${d.jobs.slice(0, 7).map(j => `<div class="bar-row"><span class="t ell">${esc(j.label)}</span><div class="track"><i style="width:${j.count / jobsMax * 100}%"></i></div><span class="n">${j.count}</span></div>`).join('')}</div>` : empty('fas fa-briefcase', 'Nobody online')}</div></div>
      </div>
      <div class="g4">
        ${stat('New today', 'fas fa-user-plus', num(d.newToday), `${num(d.newWeek)} this week`)}
        ${stat('Returning', 'fas fa-arrow-rotate-left', num(d.returning), 'new players who came back', '#4c9aff')}
        ${stat('Characters', 'fas fa-id-card', num(d.characters), `${esc(d.server.framework)} · ${esc(d.server.inventory)}`, '#9ea5aa')}
        ${stat('Deaths today', 'fas fa-skull', num(d.deathsToday), 'from the death log', 'var(--red)')}
      </div>
      <div class="g3">
        <div class="card"><div class="card-h"><h3><i class="fas fa-calendar-week"></i>This week</h3><div class="r legend"><span>Peak players</span></div></div>
          <div class="card-b">${(d.week || []).length ? barChart(d.week.map(w => w.peak), d.week.map(w => w.day), { id: 'wk', w: 360, h: 160 }) : empty('fas fa-chart-column', 'No data yet')}</div></div>
        <div class="card"><div class="card-h"><h3><i class="fas fa-clock-rotate-left"></i>Recent staff actions</h3><div class="r">${can('logs.view') ? btn('All', 'nav', 'btn-ghost xs', { v: 'logs' }) : ''}</div></div>
          <div class="card-b np scroll-y" style="max-height:198px">${(d.recent || []).length ? d.recent.map(r => `<div class="li"><div class="tx"><b>${esc(r.staff_name || 'System')} <span class="muted" style="display:inline;font-weight:300">${esc(r.action.replace(/_/g, ' '))}</span></b><span>${esc(r.target_name ? r.target_name + ' · ' : '')}${esc(r.message || '')}</span></div><div class="rt">${ago(r.time)}</div></div>`).join('') : empty('fas fa-list', 'No actions yet')}</div></div>
        <div class="card"><div class="card-h"><h3><i class="fas fa-trophy"></i>Top staff this week</h3></div>
          <div class="card-b np">${(d.topStaff || []).length ? d.topStaff.map((s, i) => `<div class="li">${av(s.nickname || s.name, 'sm')}<div class="tx"><b>${esc(s.nickname || s.name)}</b><span>${esc(s.group_name)}</span></div><div class="rt"><b class="tteal">${dur(s.secs)}</b></div></div>`).join('') : empty('fas fa-user-shield', 'No duty time yet')}</div></div>
      </div>
      <div class="g3">
        <div class="card"><div class="card-h"><h3><i class="fas fa-user-clock"></i>Newest players</h3></div>
          <div class="card-b np">${(d.latest || []).map(p => `<div class="li">${av(p.name, 'sm')}<div class="tx"><b>${esc(p.name)}</b><span>${p.sessions} session${p.sessions === 1 ? '' : 's'}</span></div><div class="rt">${ago(p.time)}</div></div>`).join('') || empty('fas fa-users', 'Nobody yet')}</div></div>
        <div class="card"><div class="card-h"><h3><i class="fas fa-sack-dollar"></i>Richest characters</h3></div>
          <div class="card-b np">${(d.rich || []).map((p, i) => `<div class="li"><span class="muted" style="width:14px">${i + 1}</span><div class="tx"><b>${esc(p.name)}</b></div><div class="rt"><b class="tteal">${money(p.total)}</b></div></div>`).join('') || empty('fas fa-sack-dollar', 'No data')}</div></div>
        <div class="card"><div class="card-h"><h3><i class="fas fa-calendar"></i>Upcoming events</h3><div class="r">${can('events.view') ? btn('Calendar', 'worldTab', 'btn-ghost xs', { v: 'events' }) : ''}</div></div>
          <div class="card-b np">${(d.events || []).map(e => `<div class="li"><div class="av sm"><i class="fas fa-calendar-day"></i></div><div class="tx"><b>${esc(e.title)}</b><span>${date(e.date, true)}</span></div></div>`).join('') || empty('fas fa-calendar', 'Nothing planned')}</div></div>
      </div>
      <div class="card"><div class="card-h"><h3><i class="fas fa-server"></i>Server</h3></div><div class="card-b">
        <div class="kv" style="grid-template-columns:repeat(5,1fr)">
          <div><label>Framework</label><span>${esc(d.server.framework)}</span></div><div><label>Inventory</label><span>${esc(d.server.inventory)}</span></div>
          <div><label>Artifact</label><span>${esc(d.server.build)}</span></div><div><label>OneSync</label><span>${esc(d.server.onesync)}</span></div>
          <div><label>Uptime</label><span>${dur(d.uptime)}</span></div></div></div></div>
    </div></div>`;
  },
});
async function loadDash() {
  const r = await rpc('dashboard');
  if (r.ok) { pd('dashboard').data = r.data; const o = $('#sb-online'); if (o) o.textContent = r.data.online; S.badges.reports = r.data.reportsOpen || S.badges.reports; if (S.page === 'dashboard') rerender(); refreshNav(); }
}
A.dashRefresh = loadDash;
A.worldTab = v => { S.tab.world = v; go('world'); };

/* ═══ PLAYERS ═══════════════════════════════════════════════════════════ */
page('players', {
  label: 'Players', icon: 'fas fa-users', perms: [],
  badge() { const l = pd('players').list; return l ? `<span class="tally">${l.length}</span>` : ''; },
  async enter(extra) { const st = pd('players'); st.sel = st.sel || new Set(); if (!extra || !extra.keep) st.profile = st.profile || null; await loadPlayers(); if (st.profile) loadProfile(st.profile, true); },
  leave() { clearInterval(pd('players').timer); },
  render() {
    const st = pd('players');
    if (st.profile) return profileHtml();
    const list = filterPlayers();
    const all = st.list || [];
    const counts = { all: all.length, staff: all.filter(p => p.staff).length, flagged: all.filter(p => p.flags && p.flags.length).length, jailed: all.filter(p => p.jailed).length };
    const bulk = st.sel && st.sel.size ? `<div class="bulkbar"><b>${st.sel.size} selected</b>
      ${can('player.revive') ? btn('Revive', 'bulk', 'sm', { v: 'revive', icon: 'fas fa-heart-pulse' }) : ''}${can('player.heal') ? btn('Heal', 'bulk', 'sm', { v: 'heal', icon: 'fas fa-kit-medical' }) : ''}
      ${can('player.teleport') ? btn('Bring', 'bulk', 'sm', { v: 'bring', icon: 'fas fa-person-arrow-down-to-line' }) : ''}${can('player.freeze') ? btn('Freeze', 'bulk', 'sm', { v: 'freeze', icon: 'fas fa-snowflake' }) : ''}
      ${can('player.notify') ? btn('Message', 'bulk', 'sm', { v: 'notify', icon: 'fas fa-message' }) : ''}${can('player.warn') ? btn('Warn', 'bulk', 'sm btn-amber', { v: 'warn', icon: 'fas fa-triangle-exclamation' }) : ''}
      ${can('player.kick') ? btn('Kick', 'bulk', 'sm btn-red', { v: 'kick', icon: 'fas fa-door-open' }) : ''}<span style="flex:1"></span>${btn('Clear', 'bulkClear', 'btn-ghost sm')}</div>` : '';
    const rows = list.map(p => `<tr class="click ${st.sel.has(p.id) ? 'sel' : ''}" data-a="openProfile" data-v="${p.id}">
      <td style="width:34px" data-a="selRow" data-v="${p.id}"><label class="chk"><input type="checkbox" ${st.sel.has(p.id) ? 'checked' : ''}><span class="box"></span></label></td>
      <td style="width:50px"><b>${p.id}</b></td>
      <td><div class="cell">${av(p.name, 'sm')}<div class="tx"><b>${esc(p.name)}</b><span>${esc(p.char || (p.loaded ? '' : 'Not loaded'))}</span></div></div></td>
      <td>${esc(p.job || '-')}${p.jobGrade ? `<span class="muted"> · ${esc(p.jobGrade)}</span>` : ''}</td>
      <td><div class="row-btns">${p.staff ? `<span class="chip" style="color:${esc(p.staff.color)};border-color:${esc(p.staff.color)}55"><i class="fas fa-shield-halved"></i>${esc(p.staff.label)}${p.staff.duty ? '' : ' · off'}</span>` : ''}${(p.flags || []).map(flagChip).join('')}${p.jailed ? chip('Jailed', 'amber', 'fas fa-lock') : ''}${p.frozen ? chip('Frozen', 'blue', 'fas fa-snowflake') : ''}${p.bucket ? chip('Bucket ' + p.bucket, '', 'fas fa-cube') : ''}</div></td>
      <td>${hpBar(p.health, p.armour)}</td>
      <td class="num">${p.ping}<span class="muted">ms</span></td>
      <td class="num">${dur(now() - (p.joined || now()))}</td>
      <td class="tact"><div class="row-btns" style="flex-wrap:nowrap">
        ${can('player.teleport') ? btn('', 'pquick', 'xs', { v: 'goto:' + p.id, icon: 'fas fa-location-arrow', title: 'Go to' }) + btn('', 'pquick', 'xs', { v: 'bring:' + p.id, icon: 'fas fa-person-arrow-down-to-line', title: 'Bring' }) : ''}
        ${can('player.spectate') ? btn('', 'pquick', 'xs', { v: 'spectate:' + p.id, icon: 'fas fa-eye', title: 'Spectate' }) : ''}
        ${can('player.revive') ? btn('', 'pquick', 'xs', { v: 'revive:' + p.id, icon: 'fas fa-heart-pulse', title: 'Revive' }) : ''}</div></td></tr>`).join('');
    return ph('Players', `${all.length} online · ${counts.staff} staff`, `${can('player.revive') ? btn('Revive radius', 'reviveRadius', 'btn-ghost sm', { icon: 'fas fa-circle-dot' }) : ''}${btn('Refresh', 'playersRefresh', 'btn-ghost sm', { icon: 'fas fa-rotate' })}`) + `<div class="content">
      <div class="toolbar"><div class="search"><i class="fas fa-magnifying-glass"></i><input class="inp" data-in="plSearch" value="${esc(st.q || '')}" placeholder="Search by name, ID, character, job or license"></div>
        ${seg([['all', 'All', `<span class="tally">${counts.all}</span>`], ['staff', 'Staff', `<span class="tally">${counts.staff}</span>`], ['flagged', 'Flagged', `<span class="tally">${counts.flagged}</span>`], ['jailed', 'Jailed', `<span class="tally">${counts.jailed}</span>`]], st.filter || 'all', 'plFilter')}
        ${btn(st.sel.size === list.length && list.length ? 'Unselect all' : 'Select all', 'selAll', 'btn-ghost sm', { icon: 'fas fa-check-double' })}</div>
      <div id="pl-bulk">${bulk}</div>
      <div class="tbl-wrap" id="pl-table">${!st.list ? loading() : list.length ? `<table class="tbl"><thead><tr><th></th><th>ID</th><th>Player</th><th>Job</th><th>Tags</th><th>Health</th><th class="num">Ping</th><th class="num">Session</th><th></th></tr></thead><tbody>${rows}</tbody></table>` : empty('fas fa-user-slash', 'No players match', 'Try a different search or filter.')}</div>
    </div>`;
  },
  mounted() {
    const st = pd('players');
    clearInterval(st.timer);
    st.timer = setInterval(() => { if (S.page === 'players' && S.open && !st.profile && !$('#modal').innerHTML) loadPlayers(true); }, 8000);
  },
});
async function loadPlayers(silent) {
  const r = await rpc('players:list');
  if (!r.ok) return;
  const st = pd('players');
  st.list = r.data;
  const ids = new Set(r.data.map(p => p.id));
  st.sel.forEach(id => { if (!ids.has(id)) st.sel.delete(id); });
  refreshNav();
  if (S.page !== 'players' || st.profile) return;
  if (silent) { const focused = document.activeElement && document.activeElement.dataset.in === 'plSearch'; if (focused) return redrawPlayerTable(); }
  rerender();
}
function redrawPlayerTable() {
  const html = PAGES.players.render();
  const tmp = document.createElement('div'); tmp.innerHTML = html;
  const nt = tmp.querySelector('#pl-table'), nb = tmp.querySelector('#pl-bulk');
  if (nt && $('#pl-table')) $('#pl-table').replaceWith(nt);
  if (nb && $('#pl-bulk')) $('#pl-bulk').replaceWith(nb);
}
function filterPlayers() {
  const st = pd('players'); const q = (st.q || '').toLowerCase(); const f = st.filter || 'all';
  return (st.list || []).filter(p => {
    if (f === 'staff' && !p.staff) return false;
    if (f === 'flagged' && !(p.flags && p.flags.length)) return false;
    if (f === 'jailed' && !p.jailed) return false;
    if (!q) return true;
    return [p.id, p.name, p.char, p.job, p.license].join(' ').toLowerCase().includes(q);
  });
}
IN.plSearch = debounce(v => { pd('players').q = v; redrawPlayerTable(); }, 120);
A.plFilter = v => { pd('players').filter = v; rerender(); };
A.playersRefresh = () => loadPlayers();
A.selRow = (v, el, e) => { e.stopPropagation(); const s = pd('players').sel; const id = +v; s.has(id) ? s.delete(id) : s.add(id); redrawPlayerTable(); };
A.selAll = () => { const st = pd('players'); const l = filterPlayers(); if (st.sel.size === l.length) st.sel.clear(); else l.forEach(p => st.sel.add(p.id)); rerender(); };
A.bulkClear = () => { pd('players').sel.clear(); redrawPlayerTable(); };
A.bulk = async v => {
  const st = pd('players'); const ids = [...st.sel];
  const extra = {};
  if (v === 'kick' || v === 'warn') {
    const f = await form({ title: `${v === 'kick' ? 'Kick' : 'Warn'} ${ids.length} players`, icon: v === 'kick' ? 'fas fa-door-open' : 'fas fa-triangle-exclamation', tone: 'red', ok: v === 'kick' ? 'Kick all' : 'Warn all', okClass: 'btn-solid-red', cols: 1,
      fields: [{ name: 'reason', label: 'Reason', type: 'textarea', presets: v === 'warn' ? (S.boot.warnPresets || []) : undefined }] });
    if (!f) return; extra.reason = f.reason;
  } else if (v === 'notify') {
    const f = await form({ title: `Message ${ids.length} players`, icon: 'fas fa-message', cols: 1, fields: [{ name: 'message', label: 'Message', type: 'textarea', max: 300 }] });
    if (!f) return; extra.message = f.message;
  } else if (!await confirmBox(`${v[0].toUpperCase() + v.slice(1)} ${ids.length} players?`, 'This runs on every selected player.', { tone: '', icon: 'fas fa-users', okClass: 'btn-teal' })) return;
  const r = await call('players:bulk', Object.assign({ ids, action: v }, extra));
  if (r) toast(`${r.done} done${r.failed ? ', ' + r.failed + ' failed' : ''}`, r.failed ? 'warning' : 'success');
  loadPlayers();
};
A.pquick = async (v, el, e) => {
  e.stopPropagation();
  const [act, id] = v.split(':');
  if (act === 'goto') call('player:goto', { id }, 'Teleported');
  else if (act === 'bring') call('player:bring', { id }, 'Player brought');
  else if (act === 'spectate') { const r = await call('player:spectate', { id: +id }); if (r) hideUI(); }
  else if (act === 'revive') call('player:action', { id, action: 'revive' }, 'Revived');
};
A.reviveRadius = async () => {
  const f = await form({ title: 'Revive in radius', sub: 'Revives everyone around you.', icon: 'fas fa-circle-dot', fields: [{ name: 'radius', label: 'Radius (meters)', type: 'number', value: 25, presets: [[10, '10m'], [25, '25m'], [50, '50m'], [100, '100m']] }], cols: 1 });
  if (!f) return;
  const n = await call('player:revive_radius', { radius: +f.radius });
  if (n !== null) toast(`Revived ${n} player${n === 1 ? '' : 's'}`, 'success');
};

/* ─── profile ─────────────────────────────────────────────────────────── */
function openProfile(id) { const st = pd('players'); st.profile = +id; st.ptab = st.ptab || 'overview'; st.pdata = null; rerender(); loadProfile(+id); }
A.openProfile = v => openProfile(v);
A.backToList = () => { const st = pd('players'); st.profile = null; st.pdata = null; rerender(); loadPlayers(true); };
A.ptab = v => { const st = pd('players'); st.ptab = v; rerender(); loadProfileTab(); };
async function loadProfile(id, keepTab) {
  const st = pd('players');
  const r = await rpc('player:get', { id });
  if (st.profile !== id) return;
  if (!r.ok) { toast(r.err, 'error'); st.profile = null; return rerender(); }
  st.pdata = r.data; st.hist = null; st.inv = null;
  rerender(); loadProfileTab();
}
async function loadProfileTab() {
  const st = pd('players'); const p = st.pdata; if (!p) return;
  if ((st.ptab === 'history' || st.ptab === 'notes') && !st.hist) {
    const r = await rpc('player:history', { license: p.license }); if (r.ok) { st.hist = r.data; rerender(); }
  } else if (st.ptab === 'inventory' && !st.inv) {
    const r = await rpc('player:inventory', { id: p.id }); if (r.ok) { st.inv = r.data.items; rerender(); }
  }
}

const PACTS = [
  ['Health', [['revive', 'Revive', 'fas fa-heart-pulse', 'player.revive'], ['heal', 'Heal', 'fas fa-kit-medical', 'player.heal'], ['armour', 'Give armour', 'fas fa-shield-halved', 'player.give_armor'], ['feed', 'Food and water', 'fas fa-burger', 'player.give_food_and_water'], ['kill', 'Kill', 'fas fa-skull', 'player.kill', 'danger']]],
  ['Control', [['freeze', 'Freeze', 'fas fa-snowflake', 'player.freeze', '', 'frozen'], ['cuff', 'Handcuff', 'fas fa-handcuffs', 'player.handcuff', '', 'cuffed'], ['unarm', 'Remove weapons', 'fas fa-gun', 'player.unarm', 'warn'], ['slap', 'Slap', 'fas fa-hand', 'player.slap'], ['ragdoll', 'Ragdoll', 'fas fa-person-falling', 'player.ragdoll'], ['burn', 'Set on fire', 'fas fa-fire', 'player.burn', 'danger'], ['explode', 'Explode', 'fas fa-bomb', 'player.explode', 'danger']]],
  ['Teleport', [['goto', 'Go to', 'fas fa-location-arrow', 'player.teleport'], ['bring', 'Bring', 'fas fa-person-arrow-down-to-line', 'player.teleport'], ['sendto', 'Send to…', 'fas fa-map-location-dot', 'player.teleport'], ['back', 'Send back', 'fas fa-arrow-rotate-left', 'player.teleport'], ['seat', 'Seat in their vehicle', 'fas fa-car-side', 'player.teleport'], ['bucket', 'Routing bucket', 'fas fa-cube', 'player.routing_bucket']]],
  ['Character', [['job', 'Set job', 'fas fa-briefcase', 'player.update_job'], ['gang', 'Set gang', 'fas fa-people-group', 'player.update_job'], ['group', 'Framework group', 'fas fa-user-gear', 'player.set_group'], ['ped', 'Change ped', 'fas fa-person', 'player.change_ped'], ['resetped', 'Reload skin', 'fas fa-rotate', 'player.change_ped'], ['clothing', 'Clothing menu', 'fas fa-shirt', 'player.clothing_menu'], ['weapon', 'Give weapon', 'fas fa-gun', 'player.give_weapon'], ['vehicle', 'Spawn vehicle for', 'fas fa-car', 'vehicles.spawn'], ['ownveh', 'Give owned vehicle', 'fas fa-key', 'vehicles.give'], ['message', 'Send message', 'fas fa-message', 'player.notify']]],
  ['Moderation', [['warn', 'Warn', 'fas fa-triangle-exclamation', 'player.warn', 'warn'], ['kick', 'Kick', 'fas fa-door-open', 'player.kick', 'danger'], ['ban', 'Ban', 'fas fa-gavel', 'player.ban', 'danger'], ['jail', 'Jail', 'fas fa-lock', 'player.jail', 'warn'], ['unjail', 'Release from jail', 'fas fa-lock-open', 'player.jail_remove'], ['delchar', 'Delete character', 'fas fa-user-xmark', 'player.delete_character', 'danger']]],
];

function profileHtml() {
  const st = pd('players'); const p = st.pdata;
  const back = btn('Players', 'backToList', 'btn-ghost sm', { icon: 'fas fa-arrow-left' });
  if (!p) return `<div class="ph">${back}</div><div class="content">${loading()}</div>`;
  const flags = (S.boot.flags || []).map(f => { const on = (p.flags || []).includes(f.id); return `<span class="chip btnish" data-a="${can('player.flags') ? 'toggleFlag' : ''}" data-v="${f.id}" style="${on ? `color:${f.color};border-color:${f.color}66;background:${f.color}1c` : ''}"><i class="fa${on ? 's' : 'r'} fa-flag"></i>${esc(f.label)}</span>`; }).join('');
  const tags = [p.staff ? `<span class="chip" style="color:${esc(p.staff.color)};border-color:${esc(p.staff.color)}55"><i class="fas fa-shield-halved"></i>${esc(p.staff.label)}</span>` : '', p.jail ? chip(`Jailed · ${dur(p.jail.remaining)}`, 'amber', 'fas fa-lock') : '', p.frozen ? chip('Frozen', 'blue', 'fas fa-snowflake') : '', p.cuffed ? chip('Cuffed', 'blue', 'fas fa-handcuffs') : '', p.inCall ? chip('In staff call', 'teal', 'fas fa-phone') : '', p.vehicle ? chip('In vehicle', '', 'fas fa-car') : ''].join('');
  const head = `<div class="prof-h">${av(p.name, 'lg', true)}<div class="tx"><h2>${esc(p.name)} <span class="muted" style="font-weight:400;font-size:12px">#${p.id}</span></h2>
      <p><span><i class="fas fa-id-card muted"></i> ${esc(p.char || 'No character')}</span><span><i class="fas fa-briefcase muted"></i> ${esc(p.job || '-')}${p.jobGrade ? ' · ' + esc(p.jobGrade) : ''}</span><span><i class="fas fa-signal muted"></i> ${p.ping}ms</span><span><i class="fas fa-clock muted"></i> ${dur(p.playtime)} played</span></p>
      <div class="flags">${tags}${flags}</div></div>
    <div class="r">${back}${can('player.spectate') ? btn('Spectate', 'pact', 'sm', { v: 'spectate', icon: 'fas fa-eye' }) : ''}${can('player.screenshot') ? btn('Screenshot', 'pact', 'sm', { v: 'screenshot', icon: 'fas fa-camera' }) : ''}${can('player.staff_call') ? btn(p.inCall ? 'End call' : 'Staff call', 'pact', 'sm ' + (p.inCall ? 'active' : ''), { v: 'call', icon: 'fas fa-phone' }) : ''}${can('inventory.view') ? btn('Inventory', 'pact', 'sm', { v: 'openinv', icon: 'fas fa-box-open' }) : ''}</div></div>`;
  const T = [['overview', 'Overview', 'fas fa-user'], ['actions', 'Actions', 'fas fa-bolt']];
  if (p.accounts) T.push(['accounts', 'Money', 'fas fa-wallet']);
  if (can('inventory.view')) T.push(['inventory', 'Inventory', 'fas fa-box-open']);
  if (can('player.view_notes')) T.push(['notes', `Notes (${p.notesCount})`, 'fas fa-note-sticky']);
  T.push(['history', `History (${p.warnings + p.bans})`, 'fas fa-clock-rotate-left']);
  let body = '';
  const tab = st.ptab || 'overview';
  if (tab === 'overview') {
    const ids = p.identifiers ? Object.entries(p.identifiers).filter(([, v]) => v).map(([k, v]) => `<div><label>${esc(k)}</label><span class="mono ell">${esc(v)}${btn('', 'copyText', 'xs btn-ghost', { v, icon: 'fas fa-copy', title: 'Copy' })}</span></div>`).join('') : '';
    const c = p.coords;
    body = `<div class="stack"><div class="kv" style="grid-template-columns:repeat(4,1fr)">
      <div><label>Server ID</label><span>${p.id}</span></div><div><label>Character ID</label><span class="mono ell">${esc(p.charId || '-')}</span></div>
      <div><label>Job</label><span>${esc(p.job || '-')}${p.jobGrade ? ' · ' + esc(p.jobGrade) : ''}</span></div><div><label>Gang</label><span>${esc(p.gang && p.gang.label || '-')}</span></div>
      <div><label>Framework group</label><span>${esc(p.fwGroup || '-')}</span></div><div><label>Routing bucket</label><span>${p.bucket}</span></div>
      <div><label>Health / armour</label><span>${Math.max(0, p.health - 100)} / ${p.armour}</span></div><div><label>Session</label><span>${dur(now() - (p.joined || now()))}</span></div>
      <div><label>First seen</label><span>${date(p.firstSeen)}</span></div><div><label>Sessions</label><span>${num(p.sessions)}</span></div>
      <div><label>Warnings</label><span class="${p.warnings ? 'tamber' : ''}">${p.warnings}</span></div><div><label>Bans</label><span class="${p.bans ? 'tred' : ''}">${p.bans}</span></div>
      <div style="grid-column:span 4"><label>Coords</label><span class="mono">${c ? `${c.x}, ${c.y}, ${c.z}, ${c.w}` : '-'}${c ? btn('', 'copyText', 'xs btn-ghost', { v: `vec4(${c.x}, ${c.y}, ${c.z}, ${c.w})`, icon: 'fas fa-copy', title: 'Copy vec4' }) : ''}</span></div></div>
      ${ids ? `<div class="card"><div class="card-h"><h3><i class="fas fa-fingerprint"></i>Identifiers</h3><div class="r">${p.tokens !== undefined ? chip(p.tokens + ' hardware tokens', '', 'fas fa-microchip') : ''}</div></div><div class="card-b"><div class="kv">${ids}</div></div></div>` : ''}</div>`;
  } else if (tab === 'actions') {
    body = PACTS.map(([g, list]) => {
      const items = list.filter(a => can(a[3]) && !(a[0] === 'unjail' && !p.jail) && !(a[0] === 'jail' && (p.jail || !S.boot.jail.enabled)));
      if (!items.length) return '';
      return `<div class="act-grp">${esc(g)}</div><div class="acts">${items.map(([k, l, i, , tone, stateKey]) => `<button class="act ${tone || ''} ${stateKey && p[stateKey] ? 'on' : ''}" data-a="pact" data-v="${k}"><i class="${i}"></i>${esc(stateKey && p[stateKey] ? 'Un' + l.toLowerCase() : l)}</button>`).join('')}</div>`;
    }).join('');
  } else if (tab === 'accounts') {
    body = `<div class="g3">${(p.accounts || []).map(a => `<div class="stat"><div class="lbl"><i class="fas fa-wallet"></i>${esc(a.label)}</div><div class="val">${money(a.money)}</div>
      ${can('player.manage_accounts') ? `<div class="row-btns" style="margin-top:12px">${btn('Set', 'acctSet', 'sm', { v: a.name, icon: 'fas fa-pen' })}${btn('Add', 'acctAdd', 'sm', { v: a.name, icon: 'fas fa-plus' })}${btn('Remove', 'acctSub', 'sm', { v: a.name, icon: 'fas fa-minus' })}</div>` : ''}</div>`).join('')}</div>`;
  } else if (tab === 'inventory') {
    const inv = st.inv;
    body = `<div class="toolbar">${can('inventory.give') ? btn('Give item', 'invGive', 'btn-teal sm', { icon: 'fas fa-plus' }) : ''}${btn('Open inventory', 'pact', 'sm', { v: 'openinv', icon: 'fas fa-box-open' })}<span class="sp"></span>${inv ? `<span class="muted">${inv.length} stacks</span>` : ''}${btn('', 'invReload', 'btn-ghost sm', { icon: 'fas fa-rotate', title: 'Reload' })}</div>
      ${!inv ? loading() : inv.length ? `<div class="inv">${inv.map(it => `<div class="slot" data-a="invItem" data-v="${esc(it.name)}" data-slot="${it.slot || ''}" title="${esc(it.name)}">${it.slot ? `<span class="sl">${it.slot}</span>` : ''}<span class="cnt">x${num(it.count)}</span>${itemImg(it.name) ? `<img src="${esc(itemImg(it.name))}" onerror="this.outerHTML='<div class=\\'ph-i\\'><i class=\\'fas fa-box\\'></i></div>'">` : `<div class="ph-i"><i class="fas fa-box"></i></div>`}<b>${esc(it.label || it.name)}</b></div>`).join('')}</div>` : empty('fas fa-box-open', 'Inventory is empty')}`;
  } else if (tab === 'notes') {
    const n = st.hist && st.hist.notes;
    body = `${can('player.create_notes') ? `<div class="card" style="margin-bottom:14px"><div class="card-b" style="display:flex;gap:8px"><input class="inp" id="note-in" placeholder="Write a note about this player" data-enter="noteAdd" maxlength="1000">${btn('Add note', 'noteAdd', 'btn-teal', { icon: 'fas fa-plus' })}</div></div>` : ''}
      ${!st.hist ? loading() : (n || []).length ? `<div class="card"><div class="card-b np">${n.map(x => `<div class="li"><div class="av sm"><i class="fas fa-note-sticky"></i></div><div class="tx"><b style="white-space:normal">${esc(x.text)}</b><span>${esc(x.staff_name)} · ${date(x.time, true)}</span></div>${can('player.delete_notes') ? btn('', 'noteDel', 'xs btn-ghost', { v: x.id, icon: 'fas fa-trash' }) : ''}</div>`).join('')}</div></div>` : empty('fas fa-note-sticky', 'No notes yet')}`;
  } else if (tab === 'history') {
    const h = st.hist;
    if (!h) body = loading();
    else {
      const w = h.warnings || [], b = h.bans || [], t = h.timeline || [];
      body = `<div class="g2"><div class="stack">
        <div class="card"><div class="card-h"><h3><i class="fas fa-triangle-exclamation"></i>Warnings</h3><div class="r">${chip(S.boot.maxWarnings > 0 ? `${w.length} / ${S.boot.maxWarnings}` : `${w.length}`, w.length ? 'amber' : '')}</div></div><div class="card-b np">${w.length ? w.map(x => `<div class="li"><div class="tx"><b style="white-space:normal">${esc(x.reason)}</b><span>${esc(x.staff_name)} · ${date(x.time, true)}</span></div>${can('player.warn_remove') ? btn('', 'warnDel', 'xs btn-ghost', { v: x.id, icon: 'fas fa-trash' }) : ''}</div>`).join('') : empty('fas fa-check', 'Clean record')}</div></div>
        <div class="card"><div class="card-h"><h3><i class="fas fa-gavel"></i>Bans</h3></div><div class="card-b np">${b.length ? b.map(x => `<div class="li"><div class="tx"><b style="white-space:normal">${esc(x.reason)}</b><span>${esc(x.staff_name)} · ${date(x.time)} · ${x.expires ? 'until ' + date(x.expires, true) : 'permanent'}</span></div>${x.active ? chip('Active', 'red') : chip('Lifted')}</div>`).join('') : empty('fas fa-check', 'Never banned')}</div></div></div>
        <div class="card"><div class="card-h"><h3><i class="fas fa-timeline"></i>Timeline</h3></div><div class="card-b scroll-y" style="max-height:440px">${t.length ? `<div class="timeline">${t.map(x => `<div class="tl" style="--c:${({ moderation: 'var(--red)', staff: 'var(--teal)', money: 'var(--amber)', reports: '#4c9aff' })[x.category] || 'var(--ink-3)'}"><b>${esc(x.action.replace(/_/g, ' '))}</b><p>${esc(x.message || '')}</p><span>${esc(x.staff_name || 'System')} · ${date(x.time, true)}</span></div>`).join('')}</div>` : empty('fas fa-timeline', 'Nothing logged')}</div></div></div>`;
    }
  }
  return head + tabs(T, tab, 'ptab') + `<div class="content" style="padding-top:16px">${body}</div>`;
}
A.copyText = (v, el, e) => { e.stopPropagation(); copy(v); toast('Copied', 'success'); };
A.toggleFlag = async v => { const st = pd('players'); const p = st.pdata; const r = await call('player:flag', { license: p.license, flag: v, name: p.name }); if (r) { p.flags = r; rerender(); } };
A.invReload = () => { pd('players').inv = null; rerender(); loadProfileTab(); };
A.noteAdd = async () => { const st = pd('players'); const i = $('#note-in'); if (!i || !i.value.trim()) return; const r = await call('player:note:add', { license: st.pdata.license, name: st.pdata.name, text: i.value }); if (r) { st.pdata.notesCount++; st.hist = null; rerender(); loadProfileTab(); } };
A.noteDel = async v => { if (!await confirmBox('Delete note?', 'This cannot be undone.')) return; const st = pd('players'); if (await call('player:note:delete', { id: +v })) { st.pdata.notesCount--; st.hist = null; rerender(); loadProfileTab(); } };
A.warnDel = async v => { if (!await confirmBox('Remove warning?', 'The warning is deleted from their record.')) return; const st = pd('players'); if (await call('warning:remove', { id: +v })) { st.pdata.warnings--; st.hist = null; rerender(); loadProfileTab(); } };

async function acct(name, mode) {
  const st = pd('players'); const p = st.pdata; const a = p.accounts.find(x => x.name === name);
  const f = await form({ title: `${mode === 'set' ? 'Set' : mode === 'add' ? 'Add to' : 'Remove from'} ${a.label}`, sub: `Current balance ${money(a.money)}`, icon: 'fas fa-wallet', tone: 'amber', cols: 1, fields: [{ name: 'amount', label: 'Amount', type: 'number', value: mode === 'set' ? a.money : '' }] });
  if (!f) return;
  let amount = Math.floor(+f.amount || 0);
  if (mode === 'add') amount = a.money + amount; else if (mode === 'sub') amount = Math.max(0, a.money - amount);
  const r = await call('player:account', { id: p.id, account: name, amount }, 'Balance updated');
  if (r) { p.accounts = r; rerender(); }
}
A.acctSet = v => acct(v, 'set'); A.acctAdd = v => acct(v, 'add'); A.acctSub = v => acct(v, 'sub');

async function itemPicker(title, o = {}) {
  let items = S.d.items && S.d.items.list;
  if (!items) { const r = await rpc('items:list'); if (r.ok) { S.d.items = S.d.items || {}; S.d.items.list = items = r.data.items; } }
  const opts = (items || []).map(i => [i.name, `${i.label} (${i.name})`]);
  return form({ title, icon: 'fas fa-box', size: '', fields: [
    { name: 'item', label: 'Item', type: opts.length ? 'select' : 'text', options: opts, value: o.item, span: true },
    { name: 'count', label: 'Amount', type: 'number', value: o.count || 1, presets: [1, 5, 10, 50, 100] },
    ...(o.withTarget ? [{ name: 'id', label: 'Player ID', type: 'number', value: o.id || '' }] : []),
  ] });
}
A.invGive = async () => {
  const st = pd('players'); const f = await itemPicker('Give item');
  if (!f) return;
  const r = await call('player:item:give', { id: st.pdata.id, item: f.item, count: Math.max(1, +f.count || 1) }, 'Item given');
  if (r) { st.inv = r; rerender(); }
};
A.invItem = async (v, el) => {
  if (!can('inventory.remove')) return;
  const st = pd('players'); const it = st.inv.find(i => i.name === v && String(i.slot || '') === el.dataset.slot) || st.inv.find(i => i.name === v);
  const f = await form({ title: `Remove ${it.label || it.name}`, sub: `They have ${it.count}.`, icon: 'fas fa-box', tone: 'red', ok: 'Remove', okClass: 'btn-solid-red', cols: 1, fields: [{ name: 'count', label: 'Amount', type: 'number', value: it.count, presets: [[1, '1'], [it.count, 'All']] }] });
  if (!f) return;
  const r = await call('player:item:remove', { id: st.pdata.id, item: it.name, count: Math.max(1, +f.count || 1), slot: it.slot }, 'Item removed');
  if (r) { st.inv = r; rerender(); }
};

function durationField(name = 'duration', value = '1d') {
  return { name, label: 'Duration', value, placeholder: '30m, 2h, 7d, perm', hint: 'y w d h m', presets: (S.boot.bans.presets || []).map(p => [p.duration, p.label]) };
}
async function jobPick(gang) {
  let jobs = S.d.jobs;
  if (!jobs) { const r = await rpc('jobs:list'); jobs = S.d.jobs = r.ok ? r.data : []; }
  const list = gang && jobs.gangs ? jobs.gangs : (jobs.jobs || jobs);
  const opts = (Array.isArray(list) ? list : []).flatMap(j => (j.grades || [{ grade: 0, label: '' }]).map(g => [`${j.name}|${g.grade}`, `${j.label} · ${g.label || g.grade}`]));
  const f = await form({ title: gang ? 'Set gang' : 'Set job', icon: 'fas fa-briefcase', cols: 1, fields: opts.length ? [{ name: 'pick', label: gang ? 'Gang and grade' : 'Job and grade', type: 'select', options: opts }] : [{ name: 'name', label: 'Name' }, { name: 'grade', label: 'Grade', type: 'number', value: 0 }] });
  if (!f) return null;
  if (f.pick) { const [name, grade] = f.pick.split('|'); return { name, grade: +grade }; }
  return { name: f.name, grade: +f.grade || 0 };
}

A.pact = async v => {
  const st = pd('players'); const p = st.pdata; const id = p.id;
  const simple = ['revive', 'heal', 'armour', 'feed', 'slap', 'ragdoll', 'unarm', 'resetped', 'clothing', 'freeze', 'cuff'];
  const danger = { kill: 'Kill this player?', burn: 'Set this player on fire?', explode: 'Explode this player?' };
  let r;
  if (simple.includes(v)) { r = await call('player:action', { id, action: v }, 'Done'); }
  else if (danger[v]) { if (await confirmBox(danger[v], p.name)) r = await call('player:action', { id, action: v }, 'Done'); }
  else if (v === 'goto') r = await call('player:goto', { id }, 'Teleported');
  else if (v === 'bring') r = await call('player:bring', { id }, 'Player brought');
  else if (v === 'back') r = await call('player:back', { id }, 'Sent back');
  else if (v === 'seat') r = await call('player:seat', { id }, 'Seated');
  else if (v === 'spectate') { r = await call('player:spectate', { id }); if (r) return hideUI(); }
  else if (v === 'openinv') { r = await call('player:inventory:open', { id }); if (r) return hideUI(); }
  else if (v === 'screenshot') { r = await call('player:screenshot', { id }); if (r) toast('Screenshot requested, it opens when it arrives.', 'info'); }
  else if (v === 'call') { r = await call('player:call', { id }); if (r) { p.inCall = r === 'started'; toast(r === 'started' ? 'Call started' : 'Call ended', 'success'); } }
  else if (v === 'sendto') {
    const tps = (S.boot.teleports && S.boot.teleports.full) || [];
    const f = await form({ title: 'Send player to…', icon: 'fas fa-map-location-dot', cols: 1, fields: [
      { name: 'loc', label: 'Location', type: 'select', options: [['', 'Pick a location'], ...tps.map((t, i) => [i, t.name])] },
      { name: 'player', label: 'Or another player (ID)', type: 'number' }, { name: 'coords', label: 'Or coords', placeholder: 'x, y, z' }] });
    if (!f) return;
    const d = { id };
    if (f.player) d.to = +f.player; else if (f.loc !== '') d.coords = tps[+f.loc].coords; else if (f.coords) { const [x, y, z] = f.coords.replace(/vec(tor)?[34]?\(|\)/g, '').split(/[\s,]+/).filter(Boolean).map(Number); if (isNaN(x) || isNaN(y)) return toast('Enter x, y and optionally z', 'error'); d.coords = { x, y, z: isNaN(z) ? undefined : z }; }
    else return toast('Pick a location, a player or coords', 'error');
    r = await call('player:sendto', d, 'Player sent');
  } else if (v === 'bucket') {
    const f = await form({ title: 'Routing bucket', sub: `Currently ${p.bucket}. 0 is the main world.`, icon: 'fas fa-cube', cols: 1, fields: [{ name: 'bucket', label: 'Bucket', type: 'number', value: p.bucket, presets: [[0, 'Main world']] }] });
    if (f) { r = await call('player:bucket', { id, bucket: +f.bucket }, 'Bucket changed'); if (r) p.bucket = +f.bucket; }
  } else if (v === 'job' || v === 'gang') {
    const j = await jobPick(v === 'gang'); if (j) r = await call('player:job', Object.assign({ id, gang: v === 'gang' }, j), 'Updated');
  } else if (v === 'group') {
    const f = await form({ title: 'Framework group', sub: `Currently ${p.fwGroup || 'user'}. This is the framework permission group, not the staff group.`, icon: 'fas fa-user-gear', cols: 1, fields: [{ name: 'group', label: 'Group', value: p.fwGroup || 'user', presets: ['user', 'mod', 'admin', 'superadmin'] }] });
    if (f) r = await call('player:group', { id, group: f.group }, 'Group set');
  } else if (v === 'ped') {
    const f = await form({ title: 'Change ped', icon: 'fas fa-person', cols: 1, fields: [{ name: 'model', label: 'Ped model', placeholder: 'a_m_y_hipster_01', presets: ['mp_m_freemode_01', 'mp_f_freemode_01', 'a_c_chop', 's_m_y_cop_01', 'u_m_y_rsranger_01'] }] });
    if (f) r = await call('player:ped', { id, model: f.model }, 'Ped changed');
  } else if (v === 'weapon') {
    const f = await form({ title: 'Give weapon', icon: 'fas fa-gun', fields: [{ name: 'weapon', label: 'Weapon', value: 'WEAPON_PISTOL', span: true, presets: ['WEAPON_PISTOL', 'WEAPON_COMBATPISTOL', 'WEAPON_SMG', 'WEAPON_CARBINERIFLE', 'WEAPON_PUMPSHOTGUN', 'WEAPON_STUNGUN', 'WEAPON_NIGHTSTICK'] }, { name: 'ammo', label: 'Ammo', type: 'number', value: 250 }] });
    if (f) r = await call('player:weapon', { id, weapon: f.weapon, ammo: +f.ammo }, 'Weapon given');
  } else if (v === 'vehicle') {
    const f = await form({ title: 'Spawn vehicle for player', icon: 'fas fa-car', fields: [{ name: 'model', label: 'Model', placeholder: 'adder', span: true }, { name: 'maxed', label: 'Max upgrades', type: 'check' }] });
    if (f) r = await call('vehicles:spawn', { id, model: f.model, maxed: f.maxed }, 'Vehicle spawned');
  } else if (v === 'ownveh') {
    const f = await form({ title: 'Give owned vehicle', sub: 'Adds the vehicle to their garage.', icon: 'fas fa-key', fields: [{ name: 'model', label: 'Model', placeholder: 'sultan' }, { name: 'plate', label: 'Plate', placeholder: 'Random', max: 8 }, { name: 'maxed', label: 'Max upgrades', type: 'check' }, { name: 'spawn', label: 'Spawn it for them now', type: 'check', value: true }] });
    if (f) { r = await call('vehicles:give', { id, model: f.model, plate: f.plate, maxed: f.maxed, spawn: f.spawn }); if (r) toast(`Given with plate ${r}`, 'success'); }
  } else if (v === 'message') {
    const f = await form({ title: `Message ${p.name}`, icon: 'fas fa-message', cols: 1, fields: [{ name: 'message', label: 'Message', type: 'textarea', max: 300 }] });
    if (f) r = await call('player:message', { id, message: f.message }, 'Message sent');
  } else if (v === 'warn') {
    const f = await form({ title: `Warn ${p.name}`, sub: `${S.boot.maxWarnings > 0 ? `${p.warnings} of ${S.boot.maxWarnings} warnings` : `${p.warnings} warnings on record`}. They see a full screen warning.`, icon: 'fas fa-triangle-exclamation', tone: 'amber', ok: 'Warn', okClass: 'btn-amber', cols: 1, fields: [{ name: 'reason', label: 'Reason', type: 'textarea', presets: S.boot.warnPresets }], validate: v => v.reason.trim() ? null : 'Give a reason' });
    if (f) { r = await call('player:warn', { id, reason: f.reason }, 'Warning issued'); if (r) p.warnings++; }
  } else if (v === 'kick') {
    const f = await form({ title: `Kick ${p.name}`, icon: 'fas fa-door-open', tone: 'red', ok: 'Kick', okClass: 'btn-solid-red', cols: 1, fields: [{ name: 'reason', label: 'Reason', type: 'textarea' }] });
    if (f) { r = await call('player:kick', { id, reason: f.reason }, 'Player kicked'); if (r) return A.backToList(); }
  } else if (v === 'ban') {
    const f = await form({ title: `Ban ${p.name}`, sub: 'Bans the license, Discord, hardware tokens and other identifiers.', icon: 'fas fa-gavel', tone: 'red', ok: 'Ban', okClass: 'btn-solid-red', cols: 1, fields: [durationField(), { name: 'reason', label: 'Reason', type: 'textarea' }] });
    if (f) { r = await call('player:ban', { id, reason: f.reason, duration: f.duration }); if (r) { toast(`Banned · #${r}`, 'success'); return A.backToList(); } }
  } else if (v === 'jail') {
    const f = await form({ title: `Jail ${p.name}`, icon: 'fas fa-lock', tone: 'amber', ok: 'Jail', okClass: 'btn-amber', cols: 1, fields: [durationField('duration', '30m'), { name: 'reason', label: 'Reason', type: 'textarea' }] });
    if (f) r = await call('player:jail', { id, duration: f.duration, reason: f.reason }, 'Player jailed');
  } else if (v === 'unjail') { r = await call('player:unjail', { id }, 'Released'); }
  else if (v === 'delchar') {
    if (await confirmBox('Delete this character?', `${p.char} will be permanently removed and ${p.name} will be dropped. This cannot be undone.`, { ok: 'Delete character' })) { r = await call('player:delete_character', { id }, 'Character deleted'); if (r) return A.backToList(); }
  }
  if (r) loadProfile(id);
};

/* ═══ OFFLINE ═══════════════════════════════════════════════════════════ */
page('offline', {
  label: 'Offline', icon: 'fas fa-user-clock', perms: ['offline_player.search'],
  render() {
    const st = pd('offline'); const t = S.tab.offline || 'chars';
    let body;
    if (t === 'chars') {
      const rows = st.chars;
      body = `<div class="toolbar"><div class="search"><i class="fas fa-magnifying-glass"></i><input class="inp" data-enter="offSearch" id="off-q" value="${esc(st.q || '')}" placeholder="Search character name, identifier or citizen ID, press Enter"></div>${btn('Search', 'offSearch', 'btn-teal', { icon: 'fas fa-magnifying-glass' })}</div>
        <div class="tbl-wrap">${!rows ? empty('fas fa-magnifying-glass', 'Search characters', 'Find any character in the database, online or not.') : rows.length ? `<table class="tbl"><thead><tr><th>Character</th><th>Job</th><th class="num">Cash</th><th class="num">Bank</th><th>Group</th><th></th></tr></thead><tbody>${rows.map((c, i) => `<tr>
          <td><div class="cell">${av(c.name, 'sm', !!c.online)}<div class="tx"><b>${esc(c.name)}</b><span class="mono">${esc(c.charId)}</span></div></div></td>
          <td>${esc(c.job || '-')}${c.grade !== undefined ? ` <span class="muted">· ${esc(c.grade)}</span>` : ''}</td><td class="num">${money(c.money && c.money.cash)}</td><td class="num">${money(c.money && c.money.bank)}</td><td>${esc(c.group || '-')}</td>
          <td class="tact"><div class="row-btns" style="flex-wrap:nowrap">${c.online ? btn('Online', 'openProfileGo', 'xs active', { v: c.online, icon: 'fas fa-circle' }) : `${can('offline_player.update_name') ? btn('', 'offEdit', 'xs', { v: 'name:' + i, icon: 'fas fa-signature', title: 'Rename' }) : ''}${can('offline_player.change_job') ? btn('', 'offEdit', 'xs', { v: 'job:' + i, icon: 'fas fa-briefcase', title: 'Set job' }) : ''}${can('offline_player.change_money') ? btn('', 'offEdit', 'xs', { v: 'money:' + i, icon: 'fas fa-wallet', title: 'Money' }) : ''}${can('offline_player.ban') ? btn('', 'offEdit', 'xs btn-red', { v: 'ban:' + i, icon: 'fas fa-gavel', title: 'Ban' }) : ''}${can('offline_player.delete') ? btn('', 'offEdit', 'xs btn-red', { v: 'delete:' + i, icon: 'fas fa-trash', title: 'Delete' }) : ''}`}</div></td></tr>`).join('')}</tbody></table>` : empty('fas fa-user-slash', 'No characters found')}</div>`;
    } else {
      const rows = st.seen;
      body = `<div class="toolbar"><div class="search"><i class="fas fa-magnifying-glass"></i><input class="inp" data-enter="seenSearch" id="seen-q" value="${esc(st.sq || '')}" placeholder="Search player name, license or Discord ID, press Enter"></div>${btn('Search', 'seenSearch', 'btn-teal', { icon: 'fas fa-magnifying-glass' })}${can('offline_player.ban') ? btn('Ban identifier', 'banIdentifier', 'btn-red', { icon: 'fas fa-gavel' }) : ''}</div>
        <div class="tbl-wrap">${!rows ? empty('fas fa-address-book', 'Player history', 'Every account that ever joined, with playtime and last seen.') : rows.length ? `<table class="tbl"><thead><tr><th>Player</th><th>License</th><th>Discord</th><th class="num">Playtime</th><th class="num">Sessions</th><th>Last seen</th><th></th></tr></thead><tbody>${rows.map((r, i) => `<tr><td><b>${esc(r.name)}</b></td><td class="mono ell" style="max-width:180px">${esc(r.license)}</td><td class="mono">${esc(r.discord || '-')}</td><td class="num">${dur(r.playtime)}</td><td class="num">${r.sessions}</td><td>${ago(r.last)}</td>
          <td class="tact"><div class="row-btns" style="flex-wrap:nowrap">${btn('', 'copyText', 'xs', { v: r.license, icon: 'fas fa-copy', title: 'Copy license' })}${can('offline_player.ban') ? btn('', 'seenBan', 'xs btn-red', { v: i, icon: 'fas fa-gavel', title: 'Ban' }) : ''}</div></td></tr>`).join('')}</tbody></table>` : empty('fas fa-user-slash', 'Nobody found')}</div>`;
    }
    return ph('Offline players', 'Edit characters and ban people who are not online') + `<div class="content">${seg([['chars', 'Characters'], ['seen', 'Player history']], t, 'offTab')}<div style="height:12px"></div>${body}</div>`;
  },
});
A.offTab = v => { S.tab.offline = v; rerender(); };
A.openProfileGo = v => { go('players'); openProfile(v); };
A.offSearch = async () => { const st = pd('offline'); st.q = $('#off-q').value; const r = await call('offline:search', { search: st.q }); if (r) { st.chars = r; rerender(); } };
A.seenSearch = async () => { const st = pd('offline'); st.sq = $('#seen-q').value; const r = await call('players:seen', { search: st.sq }); if (r) { st.seen = r; rerender(); } };
A.offEdit = async v => {
  const [field, i] = v.split(':'); const c = pd('offline').chars[+i];
  let value;
  if (field === 'name') { const f = await form({ title: 'Rename character', icon: 'fas fa-signature', fields: [{ name: 'first', label: 'First name', value: c.name.split(' ')[0] }, { name: 'last', label: 'Last name', value: c.name.split(' ').slice(1).join(' ') }] }); if (!f) return; value = { first: f.first, last: f.last }; }
  else if (field === 'job') { const j = await jobPick(); if (!j) return; value = j; }
  else if (field === 'money') { const f = await form({ title: 'Set money', sub: `Cash ${money(c.money.cash)} · Bank ${money(c.money.bank)}`, icon: 'fas fa-wallet', tone: 'amber', fields: [{ name: 'account', label: 'Account', type: 'select', options: [['cash', 'Cash'], ['bank', 'Bank'], ['black_money', 'Black money'], ['crypto', 'Crypto']] }, { name: 'amount', label: 'New balance', type: 'number', value: c.money.cash }] }); if (!f) return; value = { account: f.account, amount: +f.amount || 0 }; }
  else if (field === 'ban') { const f = await form({ title: `Ban ${c.name}`, icon: 'fas fa-gavel', tone: 'red', ok: 'Ban', okClass: 'btn-solid-red', cols: 1, fields: [durationField(), { name: 'reason', label: 'Reason', type: 'textarea' }] }); if (!f) return; const r = await call('offline:ban', { license: c.license, name: c.name, duration: f.duration, reason: f.reason }); if (r) toast('Banned · #' + r, 'success'); return; }
  else if (field === 'delete') { if (!await confirmBox('Delete character?', `${c.name} (${c.charId}) and everything tied to it will be removed.`, { ok: 'Delete' })) return; value = true; }
  if (await call('offline:update', { charId: c.charId, field, value, name: c.name, license: c.license }, 'Saved')) A.offSearch();
};
async function offlineBan(license, name) {
  const f = await form({ title: 'Ban identifier', sub: 'Works for players who are not online.', icon: 'fas fa-gavel', tone: 'red', ok: 'Ban', okClass: 'btn-solid-red', cols: 1, fields: [{ name: 'license', label: 'Identifier', value: license || '', placeholder: 'license:xxxxxxxx' }, { name: 'name', label: 'Name', value: name || '' }, durationField(), { name: 'reason', label: 'Reason', type: 'textarea' }] });
  if (!f) return;
  const r = await call('offline:ban', f); if (r) toast('Banned · #' + r, 'success');
}
A.banIdentifier = () => offlineBan();
A.seenBan = v => { const r = pd('offline').seen[+v]; offlineBan(r.license, r.name); };

/* ═══ REPORTS ═══════════════════════════════════════════════════════════ */
page('reports', {
  label: 'Reports', icon: 'fas fa-flag', perms: ['reports.view'],
  badge() { return S.badges.reports ? `<span class="tally hot">${S.badges.reports}</span>` : ''; },
  async enter() { await loadReports(); },
  render() {
    const st = pd('reports'); const list = st.list; const cur = st.cur;
    const left = `<div class="pane-l"><div class="pane-h">${seg([['active', 'Active'], ['closed', 'Closed']], st.status || 'active', 'repStatus')}</div><div class="pane-b">${!list ? loading() : list.length ? list.map(r => `<div class="li click ${cur && cur.chat.id === r.id ? 'on' : ''}" data-a="repOpen" data-v="${r.id}">${av(r.author_name, 'sm', !!r.online)}<div class="tx"><b>#${r.id} · ${esc(r.label)}</b><span>${esc(r.author_name)} · ${esc(r.category)}${r.claimed_name ? ' · ' + esc(r.claimed_name) : ''}</span></div><div class="rt">${ago(r.updated)}<br>${r.status === 'claimed' ? chip('Claimed', 'teal') : r.status === 'closed' ? chip('Closed') : chip('Open', 'red')}</div></div>`).join('') : empty('fas fa-flag', 'No reports', st.status === 'closed' ? 'Closed reports show here.' : 'All clear.')}</div></div>`;
    let right;
    if (!cur) right = empty('fas fa-comments', 'Pick a report', 'Reply, claim, teleport and close from here.');
    else {
      const c = cur.chat; const online = c.online;
      right = `<div class="prof-h" style="padding:12px 16px">${av(c.author_name, '', !!online)}<div class="tx"><h2 style="font-size:14px">#${c.id} · ${esc(c.label)}</h2><p><span>${esc(c.author_name)}${online ? ` · ID ${online}` : ' · offline'}</span><span>${esc(c.category)}</span><span>${date(c.created_at || 0, true)}</span>${c.claimed_name ? `<span class="tteal">Claimed by ${esc(c.claimed_name)}</span>` : ''}</p></div>
        <div class="r">${online ? `${can('player.teleport') ? btn('', 'repDo', 'sm', { v: 'goto', icon: 'fas fa-location-arrow', title: 'Go to' }) + btn('', 'repDo', 'sm', { v: 'bring', icon: 'fas fa-person-arrow-down-to-line', title: 'Bring' }) : ''}${can('player.spectate') ? btn('', 'repDo', 'sm', { v: 'spectate', icon: 'fas fa-eye', title: 'Spectate' }) : ''}${btn('', 'repDo', 'sm', { v: 'profile', icon: 'fas fa-user', title: 'Profile' })}` : ''}
          ${c.status !== 'closed' ? btn(c.claimed_name ? (c.claimed_name === S.me.name ? 'Unclaim' : 'Take over') : 'Claim', 'repDo', 'sm btn-teal', { v: 'claim', icon: 'fas fa-hand' }) : ''}
          ${can('reports.close') ? (c.status === 'closed' ? btn('Reopen', 'repDo', 'sm', { v: 'reopen', icon: 'fas fa-rotate-left' }) : btn('Close', 'repDo', 'sm btn-red', { v: 'close', icon: 'fas fa-check' })) : ''}</div></div>
        <div class="chat" id="chat">${msgsHtml(cur.messages)}</div>
        ${c.status !== 'closed' ? `<div class="composer"><input class="inp" id="rep-in" placeholder="Reply to ${esc(c.author_name)}" data-enter="repSend" maxlength="500">${btn('Send', 'repSend', 'btn-teal', { icon: 'fas fa-paper-plane' })}</div>` : ''}`;
    }
    return `<div class="content flush"><div class="split">${left}<div class="pane-r">${right}</div></div></div>`;
  },
  mounted() { const c = $('#chat'); if (c) c.scrollTop = c.scrollHeight; },
});
function msgsHtml(list) {
  return (list || []).map(m => `<div class="msg ${m.mine ? 'mine' : ''} ${m.staff ? 'staff' : ''}" data-mid="${m.id}"><div class="meta"><b>${esc(m.author)}</b>${m.staff ? chip('Staff', 'teal') : ''}<span>${clock(m.time)}</span></div><div class="bub">${esc(m.message)}</div></div>`).join('') || `<div class="msg sys"><div class="bub">No messages yet</div></div>`;
}
async function loadReports() {
  const st = pd('reports'); const r = await rpc('reports:list', { status: st.status || 'active' });
  if (r.ok) { st.list = r.data; if ((st.status || 'active') === 'active') S.badges.reports = r.data.filter(x => x.status !== 'claimed').length; refreshNav(); if (S.page === 'reports') rerender(); }
}
A.repStatus = v => { const st = pd('reports'); st.status = v; st.list = null; st.cur = null; rerender(); loadReports(); };
A.repOpen = async v => { const st = pd('reports'); const r = await call('reports:get', { id: +v }); if (r) { r.messages.forEach(m => { m.mine = m.staff && m.author === S.me.name; }); st.cur = r; rerender(); } };
A.repSend = async () => {
  const st = pd('reports'); const i = $('#rep-in'); if (!i || !i.value.trim()) return;
  const text = i.value; i.value = '';
  const m = await call('chats:send', { id: st.cur.chat.id, message: text });
  if (m) addMessage(st.cur, m);
};
function addMessage(cur, m) {
  if (cur.messages.some(x => x.id === m.id)) return;
  cur.messages.push(m);
  const c = $('#chat'); if (!c) return;
  const tmp = document.createElement('div'); tmp.innerHTML = msgsHtml([m]);
  if (cur.messages.length === 1) c.innerHTML = '';
  c.appendChild(tmp.firstElementChild); c.scrollTop = c.scrollHeight;
}
A.repDo = async v => {
  const st = pd('reports'); const c = st.cur.chat; const id = c.online;
  if (v === 'goto') call('player:goto', { id }, 'Teleported');
  else if (v === 'bring') call('player:bring', { id }, 'Player brought');
  else if (v === 'spectate') { if (await call('player:spectate', { id })) hideUI(); }
  else if (v === 'profile') { go('players'); openProfile(id); }
  else if (v === 'claim') { if (await call('reports:claim', { id: c.id })) { A.repOpen(c.id); loadReports(); } }
  else if (v === 'close') { if (await call('reports:close', { id: c.id }, 'Report closed')) { st.cur = null; loadReports(); rerender(); } }
  else if (v === 'reopen') { if (await call('reports:reopen', { id: c.id }, 'Reopened')) { st.cur = null; loadReports(); rerender(); } }
};

/* ═══ STAFF CHAT ════════════════════════════════════════════════════════ */
page('chats', {
  label: 'Staff chat', icon: 'fas fa-comments', perms: ['chats.view'],
  badge() { return S.badges.chats ? `<span class="tally teal">${S.badges.chats}</span>` : ''; },
  async enter() { S.badges.chats = 0; refreshNav(); await loadRooms(); },
  render() {
    const st = pd('chats'); const cur = st.cur;
    const left = `<div class="pane-l"><div class="pane-h" style="grid-template-columns:1fr auto;display:grid;align-items:center"><b style="font-size:12px;font-weight:500">Rooms</b>${can('chats.create') ? btn('New', 'roomEdit', 'btn-teal sm', { icon: 'fas fa-plus' }) : ''}</div>
      <div class="pane-b">${!st.rooms ? loading() : st.rooms.length ? st.rooms.map(r => `<div class="li click ${cur && cur.chat.id === r.id ? 'on' : ''}" data-a="roomOpen" data-v="${r.id}"><div class="av sm"><i class="fas fa-hashtag"></i></div><div class="tx"><b>${esc(r.label)}${r.unread ? ` <span class="tally teal" style="display:inline-grid">${r.unread}</span>` : ''}</b><span>${esc(r.last || 'No messages yet')}</span></div><div class="rt">${r.groups && r.groups.length ? `<i class="fas fa-lock" title="${esc(r.groups.join(', '))}"></i>` : ''}</div></div>`).join('') : empty('fas fa-comments', 'No rooms', can('chats.create') ? 'Create one for your team.' : '')}</div></div>`;
    let right;
    if (!cur) right = empty('fas fa-hashtag', 'Pick a room');
    else right = `<div class="prof-h" style="padding:12px 16px"><div class="av"><i class="fas fa-hashtag"></i></div><div class="tx"><h2 style="font-size:14px">${esc(cur.chat.label)}</h2><p><span>${(cur.groups || []).length ? 'Visible to ' + esc(cur.groups.join(', ')) : 'Visible to all staff'}</span></p></div>
        <div class="r">${can('chats.update') ? btn('', 'roomEdit', 'sm', { v: cur.chat.id, icon: 'fas fa-pen', title: 'Edit' }) : ''}${can('chats.delete') ? btn('', 'roomDel', 'sm btn-red', { v: cur.chat.id, icon: 'fas fa-trash', title: 'Delete' }) : ''}</div></div>
      <div class="chat" id="chat">${msgsHtml(cur.messages)}</div>
      <div class="composer"><input class="inp" id="room-in" placeholder="Message #${esc(cur.chat.label)}" data-enter="roomSend" maxlength="1000">${btn('Send', 'roomSend', 'btn-teal', { icon: 'fas fa-paper-plane' })}</div>`;
    return `<div class="content flush"><div class="split">${left}<div class="pane-r">${right}</div></div></div>`;
  },
  mounted() { const c = $('#chat'); if (c) c.scrollTop = c.scrollHeight; },
});
async function loadRooms() { const st = pd('chats'); const r = await rpc('chats:list'); if (r.ok) { const old = {}; (st.rooms || []).forEach(x => old[x.id] = x.unread); st.rooms = r.data.map(x => Object.assign(x, { unread: old[x.id] || 0 })); if (S.page === 'chats') rerender(); } }
A.roomOpen = async v => { const st = pd('chats'); const r = await call('chats:get', { id: +v }); if (r) { r.groups = r.chat.groups ? (typeof r.chat.groups === 'string' ? JSON.parse(r.chat.groups) : r.chat.groups) : []; st.cur = r; const room = (st.rooms || []).find(x => x.id === +v); if (room) room.unread = 0; rerender(); } };
A.roomSend = async () => { const st = pd('chats'); const i = $('#room-in'); if (!i || !i.value.trim()) return; const text = i.value; i.value = ''; const m = await call('chats:send', { id: st.cur.chat.id, message: text }); if (m) addMessage(st.cur, m); };
A.roomEdit = async v => {
  const st = pd('chats'); const room = v ? st.rooms.find(r => r.id === +v) : null;
  const groups = S.boot.groups || [];
  const f = await form({ title: room ? 'Edit room' : 'New room', icon: 'fas fa-hashtag', cols: 1, fields: [{ name: 'label', label: 'Name', value: room ? room.label : '', max: 60 },
    { name: 'gh', type: 'html', span: true, html: `<div class="field"><label>Who can see it <small>none ticked = all staff</small></label><div class="perm-grid" style="grid-template-columns:1fr 1fr">${groups.map(g => `<label class="chk"><input type="checkbox" name="g_${esc(g.name)}" ${room && (room.groups || []).includes(g.name) ? 'checked' : ''}><span class="box"></span>${esc(g.label)}</label>`).join('')}</div></div>` }] });
  if (!f) return;
  const sel = Object.keys(f).filter(k => k.startsWith('g_') && f[k]).map(k => k.slice(2));
  if (await call('chats:save', { id: room ? room.id : undefined, label: f.label, groups: sel }, 'Saved')) loadRooms();
};
A.roomDel = async v => { if (!await confirmBox('Delete this room?', 'All messages in it are deleted.')) return; if (await call('chats:delete', { id: +v }, 'Room deleted')) { pd('chats').cur = null; loadRooms(); rerender(); } };

/* ═══ MODERATION ════════════════════════════════════════════════════════ */
page('moderation', {
  label: 'Moderation', icon: 'fas fa-gavel', perms: ['moderation.view.bans', 'moderation.view.warnings', 'moderation.view.jail'],
  async enter() { await loadMod(); },
  render() {
    const st = pd('moderation');
    const T = [];
    if (can('moderation.view.bans')) T.push(['bans', 'Bans', 'fas fa-gavel']);
    if (can('moderation.view.warnings')) T.push(['warnings', 'Warnings', 'fas fa-triangle-exclamation']);
    if (can('moderation.view.jail')) T.push(['jail', 'Jail', 'fas fa-lock']);
    const t = S.tab.moderation && T.some(x => x[0] === S.tab.moderation) ? S.tab.moderation : T[0][0];
    const rows = st[t];
    let table;
    if (!rows) table = loading();
    else if (!rows.length) table = empty('fas fa-check', 'Nothing here');
    else if (t === 'bans') table = `<table class="tbl"><thead><tr><th>#</th><th>Player</th><th>Reason</th><th>By</th><th>Expires</th><th>Status</th><th></th></tr></thead><tbody>${rows.map((b, i) => { const active = b.active && (!b.expires || b.expires > now()); return `<tr><td><b>${b.id}</b></td><td><div class="tx"><b>${esc(b.name)}</b><div class="mono muted ell" style="max-width:160px">${esc(b.license || '')}</div></div></td><td class="ell" style="max-width:240px;white-space:normal">${esc(b.reason)}</td><td>${esc(b.staff_name)}</td><td>${b.expires ? date(b.expires, true) : 'Permanent'}</td><td>${active ? chip('Active', 'red') : chip(b.active ? 'Expired' : 'Lifted')}</td>
      <td class="tact"><div class="row-btns" style="flex-wrap:nowrap">${can('player.ban') && active ? btn('', 'banEdit', 'xs', { v: i, icon: 'fas fa-pen', title: 'Edit' }) : ''}${can('player.unban') && active ? btn('Unban', 'banLift', 'xs btn-red', { v: b.id }) : ''}</div></td></tr>`; }).join('')}</tbody></table>`;
    else if (t === 'warnings') table = `<table class="tbl"><thead><tr><th>#</th><th>Player</th><th>Reason</th><th>By</th><th>Date</th><th></th></tr></thead><tbody>${rows.map(w => `<tr><td><b>${w.id}</b></td><td><b>${esc(w.name)}</b></td><td style="white-space:normal">${esc(w.reason)}</td><td>${esc(w.staff_name)}</td><td>${date(w.time, true)}</td><td class="tact">${can('player.warn_remove') ? btn('', 'modWarnDel', 'xs btn-red', { v: w.id, icon: 'fas fa-trash' }) : ''}</td></tr>`).join('')}</tbody></table>`;
    else table = `<table class="tbl"><thead><tr><th>Character</th><th>Reason</th><th>Cell</th><th>Mode</th><th class="num">Remaining</th><th>By</th><th></th></tr></thead><tbody>${rows.map((j, i) => `<tr><td><div class="cell">${av(j.name, 'sm', !!j.online)}<div class="tx"><b>${esc(j.name)}</b><span>${j.online ? 'ID ' + j.online : 'offline'}</span></div></div></td><td style="white-space:normal">${esc(j.reason)}</td><td>${esc(j.cell)}</td><td>${j.time_mode === 'playtime' ? chip('Playtime', 'blue') : chip('Real time')}</td><td class="num"><b>${dur(j.remaining)}</b></td><td>${esc(j.staff_name)}</td>
      <td class="tact">${can('player.jail_remove') ? btn('Release', 'jailFree', 'xs btn-teal', { v: i }) : ''}</td></tr>`).join('')}</tbody></table>`;
    return ph('Moderation', 'Bans, warnings and jail', can('offline_player.ban') ? btn('Ban identifier', 'banIdentifier', 'btn-red sm', { icon: 'fas fa-gavel' }) : '') + tabs(T, t, 'modTab') + `<div class="content" style="padding-top:14px">
      ${t !== 'jail' ? `<div class="toolbar"><div class="search"><i class="fas fa-magnifying-glass"></i><input class="inp" id="mod-q" data-enter="modSearch" value="${esc(st.q || '')}" placeholder="Search name, license, reason or ban ID"></div>${btn('Search', 'modSearch', 'btn-ghost', { icon: 'fas fa-magnifying-glass' })}</div>` : ''}
      <div class="tbl-wrap">${table}</div></div>`;
  },
});
async function loadMod() {
  const st = pd('moderation');
  const allowed = [['bans', 'moderation.view.bans'], ['warnings', 'moderation.view.warnings'], ['jail', 'moderation.view.jail']].filter(x => can(x[1])).map(x => x[0]);
  const T = allowed.includes(S.tab.moderation) ? S.tab.moderation : allowed[0];
  if (!T) return;
  const route = { bans: 'moderation:bans', warnings: 'moderation:warnings', jail: 'moderation:jail' }[T];
  const r = await rpc(route, { search: st.q || '' });
  if (r.ok) { st[T] = r.data; if (S.page === 'moderation') rerender(); }
}
A.modTab = v => { S.tab.moderation = v; pd('moderation')[v] = null; rerender(); loadMod(); };
A.modSearch = () => { const st = pd('moderation'); st.q = $('#mod-q').value; loadMod(); };
A.banLift = async v => { if (!await confirmBox(`Lift ban #${v}?`, 'They can join again right away.', { tone: '', okClass: 'btn-teal', ok: 'Unban', icon: 'fas fa-unlock' })) return; if (await call('ban:remove', { id: +v }, 'Ban lifted')) loadMod(); };
A.banEdit = async v => { const b = pd('moderation').bans[+v]; const f = await form({ title: `Edit ban #${b.id}`, sub: `${b.expires ? 'Expires ' + date(b.expires, true) : 'Permanent'} · leave the duration blank to keep it, a new one counts from now.`, icon: 'fas fa-gavel', tone: 'red', cols: 1, fields: [durationField('duration', ''), { name: 'reason', label: 'Reason', type: 'textarea', value: b.reason }] }); if (!f) return; if (await call('ban:edit', { id: b.id, duration: f.duration, reason: f.reason }, 'Ban updated')) loadMod(); };
A.modWarnDel = async v => { if (!await confirmBox('Remove warning?', 'It is deleted from their record.')) return; if (await call('warning:remove', { id: +v }, 'Removed')) loadMod(); };
A.jailFree = async v => { const j = pd('moderation').jail[+v]; if (!await confirmBox(`Release ${j.name}?`, 'They are sent back to where they were jailed from.', { tone: '', okClass: 'btn-teal', ok: 'Release', icon: 'fas fa-lock-open' })) return; if (await call('player:unjail', { id: j.online, charId: j.char_id, name: j.name, license: j.license }, 'Released')) loadMod(); };
