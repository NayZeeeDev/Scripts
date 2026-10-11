'use strict';
/* ═══ DASHBOARD ═════════════════════════════════════════════════════════ */
page('dashboard', {
  label: 'Dashboard', icon: 'fas fa-chart-simple',
  async enter() { const r = await rpc('dashboard'); if (r.ok) { pd('dashboard').data = r.data; if (S.page === 'dashboard') rerender(); } },
  render() {
    const d = pd('dashboard').data;
    const head = ph('Dashboard', 'Last 24 hours across every inventory', btn('Refresh', 'dashRefresh', 'btn-ghost sm', { icon: 'fas fa-rotate' }));
    if (!d) return head + `<div class="content">${loading()}</div>`;
    const stat = (lbl, icon, val, sub, c) => `<div class="stat" style="--c:${c || 'var(--teal)'}"><div class="lbl"><i class="${icon}"></i>${esc(lbl)}</div><div class="val">${val}</div><div class="sub">${sub || ''}</div></div>`;
    const nowH = Math.floor(Date.now() / 3600000);
    const map = {};
    (d.hourly || []).forEach(h => map[h.h] = h.c);
    const hours = [];
    for (let i = 23; i >= 0; i--) hours.push({ h: nowH - i, c: map[nowH - i] || 0 });
    const maxH = Math.max(1, ...hours.map(h => h.c));
    const hist = `<div class="hist-wrap"><div class="hist">${hours.map((h, i) => `<div title="${esc(new Date(h.h * 3600000).toLocaleTimeString('en-US', { hour: 'numeric' }))}: ${num(h.c)} events"><i style="height:${Math.max(1.5, h.c / maxH * 100)}%"></i>${i % 4 === 3 ? `<span>${esc(new Date(h.h * 3600000).toLocaleTimeString('en-US', { hour: 'numeric' }))}</span>` : ''}</div>`).join('')}</div></div>`;
    const maxT = Math.max(1, ...(d.types || []).map(t => t.c));
    const maxR = Math.max(1, ...(d.resources || []).map(t => t.c));
    const logRow = l => `<div class="li click" data-a="logOpenRow" data-v="${esc(JSON.stringify(l))}"><div class="tx"><b>${esc(l.source_name || 'Unknown')} <span class="muted" style="display:inline;font-weight:300">· ${esc(l.item_label || l.item_name)} x${num(l.item_count)}</span></b><span>${esc(l.details || '')}</span></div><div class="rt">${badge(l.type)}<br><span style="display:inline-block;margin-top:4px">${ago(l.time)}</span></div></div>`;
    return head + `<div class="content"><div class="stack">
      <div class="g4">
        ${stat('Events', 'fas fa-arrow-right-arrow-left', num(d.day), `${num(d.total)} stored in total`)}
        ${stat('Active characters', 'fas fa-users', num(d.players), `${num(d.online)} online right now`, 'var(--blue)')}
        ${stat('Flagged', 'fas fa-flag', num(d.suspicious), 'items from untrusted sources or spikes', d.suspicious ? 'var(--red)' : 'var(--teal)')}
        ${stat('Staff actions', 'fas fa-user-shield', num(d.admin), 'gives, removals, edits, rollbacks', 'var(--amber)')}
      </div>
      <div class="g-dash">
        <div class="card"><div class="card-h"><h3><i class="fas fa-chart-column"></i>Activity by hour</h3></div><div class="card-b">${hist}</div></div>
        <div class="card"><div class="card-h"><h3><i class="fas fa-layer-group"></i>By type</h3></div><div class="card-b">${(d.types || []).length ? `<div class="bars">${d.types.map(t => `<div class="bar-row"><span class="t ell">${esc(typeLabel(t.type))}</span><div class="track"><i style="width:${t.c / maxT * 100}%;background:${esc((S.boot.colors || {})[t.type] || 'var(--teal)')}"></i></div><span class="n">${num(t.c)}</span></div>`).join('')}</div>` : empty('fas fa-chart-bar', 'Nothing logged yet')}</div></div>
      </div>
      <div class="g3">
        <div class="card"><div class="card-h"><h3><i class="fas fa-boxes-stacked"></i>Most moved items</h3></div><div class="card-b np">${(d.items || []).map(i => `<div class="li click" data-a="dashItem" data-v="${esc(i.item_name)}">${thumb(i.item_name)}<div class="tx"><b>${esc(i.label || i.item_name)}</b><span>${num(i.c)} transfers</span></div><div class="rt"><b class="tteal">${num(i.moved)}</b></div></div>`).join('') || empty('fas fa-box', 'No movement')}</div></div>
        <div class="card"><div class="card-h"><h3><i class="fas fa-user-clock"></i>Most active</h3></div><div class="card-b np">${(d.actors || []).map(a => `<div class="li click" data-a="dashActor" data-v="${esc(a.identifier || '')}">${av(a.name, 'sm')}<div class="tx"><b>${esc(a.name || 'Unknown')}</b><span class="mono">${esc(a.identifier || '')}</span></div><div class="rt">${num(a.c)}</div></div>`).join('') || empty('fas fa-users', 'Nobody yet')}</div></div>
        <div class="card"><div class="card-h"><h3><i class="fas fa-code-branch"></i>Where items come from</h3></div><div class="card-b">${(d.resources || []).length ? `<div class="bars">${d.resources.map(r => `<div class="bar-row" style="grid-template-columns:120px 1fr 56px"><span class="t ell mono">${esc(r.resource)}</span><div class="track"><i style="width:${r.c / maxR * 100}%"></i></div><span class="n">${num(r.c)}</span></div>`).join('')}</div>` : empty('fas fa-code-branch', 'No item creation logged', 'Turn on Config.CreationLogs to see which scripts create items.')}</div></div>
      </div>
      <div class="g2">
        <div class="card"><div class="card-h"><h3><i class="fas fa-flag"></i>Latest flags</h3><div class="r">${btn('All', 'dashFlags', 'btn-ghost xs')}</div></div><div class="card-b np">${(d.flagged || []).map(logRow).join('') || empty('fas fa-shield', 'Nothing flagged')}</div></div>
        <div class="card"><div class="card-h"><h3><i class="fas fa-wallet"></i>Money in the last 24 hours</h3></div><div class="card-b">
          <div class="g2" style="gap:10px">${stat('Received', 'fas fa-arrow-down', '$' + num(d.money && d.money.inflow), '', 'var(--teal)')}${stat('Spent or removed', 'fas fa-arrow-up', '$' + num(d.money && d.money.outflow), '', 'var(--red)')}</div>
          <div class="sep"></div>${(d.spikes || []).length ? d.spikes.slice(-4).reverse().map(s => `<div class="li" style="padding:6px 0"><div class="tx"><b>${esc(s.name)}</b><span>gained $${num(s.total)} quickly</span></div><div class="rt">${ago(s.time)}</div></div>`).join('') : '<span class="muted">No money spikes this session.</span>'}
        </div></div>
      </div>
      <div class="card"><div class="card-h"><h3><i class="fas fa-clock-rotate-left"></i>Latest activity</h3><div class="r">${btn('Open logs', 'nav', 'btn-ghost xs', { v: 'logs' })}</div></div><div class="card-b np">${(d.recent || []).map(logRow).join('') || empty('fas fa-list', 'Nothing yet')}</div></div>
    </div></div>`;
  },
});
A.dashRefresh = () => PAGES.dashboard.enter();
A.dashItem = v => { pd('logs').f = { type: 'all', item: v, range: '24h' }; go('logs'); };
A.dashActor = v => { pd('logs').f = { type: 'all', player: v, range: '24h' }; go('logs'); };
A.dashFlags = () => { pd('logs').f = { type: 'suspicious', range: 'all' }; go('logs'); };
A.logOpenRow = v => openLog(JSON.parse(v));

/* ═══ LOGS ══════════════════════════════════════════════════════════════ */
const RANGES = { '1h': 3600, '24h': 86400, '7d': 604800, '30d': 2592000, all: 0 };
function logFilters() {
  const f = pd('logs').f || {};
  const out = { type: f.type || 'all', player: f.player || '', item: f.item || '', inventory: f.inventory || '', resource: f.resource || '' };
  const secs = RANGES[f.range || 'all'];
  if (secs) out.from = now() - secs;
  return out;
}
async function loadLogs(page) {
  const st = pd('logs');
  st.loading = true;
  const r = await rpc('logs:list', { filters: logFilters(), page: page || st.page || 1 });
  st.loading = false;
  if (!r.ok) return toast(r.err, 'error');
  st.data = r.data; st.page = r.data.page;
  st.maxId = Math.max(st.maxId || 0, ...(r.data.logs || []).map(l => l.id));
  if (S.page === 'logs') { const t = $('#logs-table'); if (t) t.outerHTML = logsTable(); else rerender(); }
}
function logRowHtml(l, isNew) {
  return `<tr class="click ${isNew ? 'new' : ''}" data-a="logOpen" data-v="${l.id}">
    <td><span class="ink2">${esc(clock(l.time))}</span><div class="muted" style="font-size:10px">${esc(date(l.time, false))}</div></td>
    <td>${badge(l.type)}</td>
    <td><div class="cell"><div class="tx"><b>${esc(l.source_name || '-')}</b><span class="mono">${esc(l.source_id ? '#' + l.source_id + ' · ' : '')}${esc((l.source_identifier || '').slice(0, 26))}</span></div></div></td>
    <td><div class="cell">${thumb(l.item_name)}<div class="tx"><b>${esc(l.item_label || l.item_name)}</b><span class="mono">${esc(l.item_name)}</span></div></div></td>
    <td class="num"><b>${num(l.item_count)}</b></td>
    <td class="wrap">${esc(l.details || '')}${l.resource ? ` <span class="chip" style="height:18px">${esc(l.resource)}</span>` : ''}</td></tr>`;
}
function logsTable() {
  const st = pd('logs');
  const d = st.data;
  if (!d) return `<div id="logs-table">${loading()}</div>`;
  if (!d.logs.length) return `<div id="logs-table">${empty('fas fa-magnifying-glass', 'No logs match', 'Loosen a filter or widen the time range.')}</div>`;
  return `<div id="logs-table"><div class="tbl-wrap"><table class="tbl"><thead><tr><th>Time</th><th>Type</th><th>Player</th><th>Item</th><th class="num">Amount</th><th>What happened</th></tr></thead>
    <tbody id="logs-body">${d.logs.map(l => logRowHtml(l)).join('')}</tbody></table></div>${pager(d, 'logsPage')}</div>`;
}
page('logs', {
  label: 'Logs', icon: 'fas fa-list-ul',
  async enter() { const st = pd('logs'); st.f = st.f || { type: 'all', range: '24h' }; st.data = null; st.page = 1; rerender(); await loadLogs(1); },
  leave() { const st = pd('logs'); clearInterval(st.timer); st.timer = null; st.live = false; },
  render() {
    const st = pd('logs'); const f = st.f || {};
    const types = (S.boot.types || []).map(t => `<option value="${esc(t.id)}" ${f.type === t.id ? 'selected' : ''}>${esc(t.label)}</option>`).join('');
    return ph('Logs', 'Every item and money movement, newest first', `
        <button class="btn sm ${st.live ? 'active' : ''}" data-a="logsLive"><i class="fas fa-${st.live ? 'circle-dot' : 'play'}"></i>${st.live ? 'Live' : 'Go live'}</button>
        ${btn('Copy as CSV', 'logsCsv', 'btn-ghost sm', { icon: 'fas fa-file-csv' })}
        ${can('wipe') ? btn('Delete logs', 'logsWipe', 'btn-red sm', { icon: 'fas fa-trash' }) : ''}`) + `<div class="content">
      <div class="toolbar">
        <div class="search" style="max-width:230px"><i class="fas fa-user"></i><input class="inp" data-in="logF" data-k="player" value="${esc(f.player || '')}" placeholder="Player, id or identifier"></div>
        <div class="search" style="max-width:200px"><i class="fas fa-box"></i><input class="inp" data-in="logF" data-k="item" value="${esc(f.item || '')}" placeholder="Item" list="dl-items"></div>
        <select class="sel" style="width:190px" data-ch="logType">${types}</select>
        ${seg([['1h', '1h'], ['24h', '24h'], ['7d', '7d'], ['30d', '30d'], ['all', 'All']], f.range || 'all', 'logRange')}
        <button class="btn sm btn-ghost ${f.inventory || f.resource ? 'active' : ''}" data-a="logMore"><i class="fas fa-sliders"></i>More${f.inventory || f.resource ? ' · on' : ''}</button>
      </div>
      ${logsTable()}</div>`;
  },
});
const logFilterChanged = debounce(() => loadLogs(1), 300);
IN.logF = (v, el) => { pd('logs').f[el.dataset.k] = v; logFilterChanged(); };
CH.logType = v => { pd('logs').f.type = v; loadLogs(1); };
A.logRange = v => { pd('logs').f.range = v; rerender(); loadLogs(1); };
A.logsPage = v => loadLogs(+v);
A.logMore = async () => {
  const f = pd('logs').f;
  const v = await form({ title: 'More filters', icon: 'fas fa-sliders', cols: 1, fields: [
    { name: 'inventory', label: 'Inventory id', value: f.inventory || '', placeholder: 'trunkABC123, police_locker, bag_1234', help: 'Exact id of a stash, trunk, glovebox, backpack or player id.' },
    { name: 'resource', label: 'Created by resource', value: f.resource || '', placeholder: 'e.g. my_jobs', help: 'Only matches "Item created" and "Flagged" rows.' }], ok: 'Apply' });
  if (!v) return;
  f.inventory = v.inventory.trim(); f.resource = v.resource.trim();
  rerender(); loadLogs(1);
};
A.logsLive = () => {
  const st = pd('logs');
  st.live = !st.live;
  clearInterval(st.timer);
  if (st.live) {
    st.timer = setInterval(async () => {
      if (S.page !== 'logs' || !S.open || (st.data && st.data.page !== 1)) return;
      const r = await rpc('logs:since', { after: st.maxId || 0, filters: logFilters() });
      if (!r.ok || !r.data.length) return;
      st.maxId = Math.max(st.maxId || 0, ...r.data.map(l => l.id));
      st.data.logs = r.data.concat(st.data.logs).slice(0, S.boot.perPage || 50);
      st.data.total += r.data.length;
      const body = $('#logs-body');
      if (body) { body.insertAdjacentHTML('afterbegin', r.data.map(l => logRowHtml(l, true)).join('')); while (body.children.length > (S.boot.perPage || 50)) body.lastElementChild.remove(); }
      else rerender();
    }, Math.max(2, S.boot.liveSeconds || 5) * 1000);
    toast('Live mode on. New rows appear at the top.', 'info');
  }
  rerender();
};
A.logsCsv = async () => {
  const rows = await call('logs:export', { filters: logFilters() });
  if (!rows) return;
  const cols = ['id', 'time', 'type', 'source_name', 'source_identifier', 'source_id', 'target_name', 'target_identifier', 'item_name', 'item_label', 'item_count', 'inventory_from', 'inventory_to', 'coords', 'resource', 'details'];
  const cell = v => { const s = v === null || v === undefined ? '' : String(v); return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
  const csv = [cols.join(',')].concat(rows.map(r => cols.map(c => cell(c === 'time' ? new Date(r.time * 1000).toISOString() : r[c])).join(','))).join('\n');
  post('copy', { text: csv });
  toast(`${num(rows.length)} rows copied as CSV. Paste into a spreadsheet.`, 'success');
};
A.logsWipe = async () => {
  const v = await confirmBox('Delete logs', 'Deleted logs cannot be recovered.', { ok: 'Delete', fields: [{ name: 'days', label: 'Only delete logs older than (days)', type: 'number', value: 30, help: 'Set 0 to delete every log.', min: 0 }] });
  if (!v) return;
  const n = await call('logs:wipe', { olderThanDays: +v.days || 0 });
  if (n !== null) { toast(`${num(n)} logs deleted`, 'success'); loadLogs(1); }
};
A.logOpen = v => { const l = (pd('logs').data.logs || []).find(x => String(x.id) === String(v)); if (l) openLog(l); };

function openLog(l) {
  let meta = l.metadata;
  if (typeof meta === 'string') { try { meta = JSON.parse(meta); } catch (e) { /* raw */ } }
  const coords = (l.coords || '').split(',').map(Number);
  const invBtn = id => id && id !== 'ground' && S.boot.remoteView && !/^\d+$/.test(id) ? btn('Open', 'logInv', 'xs', { v: id, icon: 'fas fa-box-open' }) : '';
  const kv = (k, v, extra = '') => `<div><label>${esc(k)}</label><span>${v}${extra}</span></div>`;
  form({ title: `${typeLabel(l.type)} · #${l.id}`, sub: date(l.time), icon: 'fas fa-receipt', size: 'lg', ok: false, cancel: 'Close', focus: false,
    body: `<div style="display:flex;gap:12px;align-items:center">${thumb(l.item_name, null, 'lg')}<div><b style="font-size:14px;color:var(--white)">${esc(l.item_label || l.item_name)} x${num(l.item_count)}</b><div class="muted mono" style="margin-top:4px">${esc(l.item_name)}</div><div style="margin-top:8px">${badge(l.type)}</div></div></div>
      <div class="note">${esc(l.details || '')}</div>
      <div class="kv">
        ${kv('Player', esc(l.source_name || '-'), l.source_id ? ` <span class="muted">#${l.source_id}</span>` : '')}${kv('Identifier', `<span class="mono">${esc(l.source_identifier || '-')}</span>`)}
        ${l.target_name ? kv('Other player', esc(l.target_name), l.target_id ? ` <span class="muted">#${l.target_id}</span>` : '') + kv('Their identifier', `<span class="mono">${esc(l.target_identifier || '-')}</span>`) : ''}
        ${kv('From', esc(l.inventory_from || '-'), ' ' + invBtn(l.inventory_from))}${kv('To', esc(l.inventory_to || '-'), ' ' + invBtn(l.inventory_to))}
        ${kv('Coords', `<span class="mono">${esc(l.coords || '-')}</span>`)}${kv('Created by', esc(l.resource || '-'))}
      </div>
      <div class="field"><label>Metadata</label>${metaHtml(meta)}</div>
      <div class="row-btns">
        ${l.source_identifier ? btn('Only this player', 'logFilterPlayer', 'sm', { v: l.source_identifier, icon: 'fas fa-filter' }) : ''}
        ${btn('Only this item', 'logFilterItem', 'sm', { v: l.item_name, icon: 'fas fa-filter' })}
        ${btn('Find this item everywhere', 'findItem', 'sm', { v: l.item_name, icon: 'fas fa-magnifying-glass-location' })}
        ${coords.length === 3 && !coords.some(isNaN) ? btn('Set waypoint', 'logWaypoint', 'sm', { v: l.coords, icon: 'fas fa-location-dot' }) : ''}
        ${meta && typeof meta === 'object' && Object.keys(meta).length ? btn('Copy metadata', 'copyText', 'sm btn-ghost', { v: JSON.stringify(meta), icon: 'fas fa-copy' }) : ''}
      </div>` });
}
A.copyText = v => copy(v);
A.logFilterPlayer = v => { closeModal(null); const st = pd('logs'); st.f = Object.assign(st.f || {}, { player: v }); if (S.page === 'logs') { rerender(); loadLogs(1); } else go('logs'); };
A.logFilterItem = v => { closeModal(null); const st = pd('logs'); st.f = Object.assign(st.f || {}, { item: v }); if (S.page === 'logs') { rerender(); loadLogs(1); } else go('logs'); };
A.logWaypoint = v => { const [x, y] = v.split(',').map(Number); post('waypoint', { x, y }); toast('Waypoint set', 'success'); };
A.logInv = v => { closeModal(null); viewInventory(v); };
A.findItem = v => { closeModal(null); pd('finder').item = v; go('finder'); setTimeout(() => A.finderScan(), 50); };

async function viewInventory(id) {
  const d = await call('inventory:view', { inv: id });
  if (!d) return;
  const st = pd('invview'); st.d = d;
  form({ title: d.label || id, sub: `${id}${d.live ? '' : ' · saved copy, not loaded right now'}`, icon: 'fas fa-box-open', size: 'xl', ok: false, cancel: 'Close', focus: false,
    body: `${d.live ? '' : note('This inventory is not loaded right now, so this is its saved copy. Removing an item edits the saved copy.', 'amber')}
      <div class="row-btns">${btn('Logs for this inventory', 'invLogs', 'sm btn-ghost', { v: id, icon: 'fas fa-list-ul' })}</div>
      ${inventoryGrid(d.items, can('manage') ? 'invViewSlot' : '')}` });
}
A.invLogs = v => { closeModal(null); pd('logs').f = { type: 'all', inventory: v, range: 'all' }; if (S.page === 'logs') { rerender(); loadLogs(1); } else go('logs'); };
A.invViewSlot = async v => {
  const d = pd('invview').d; const it = d.items.find(i => String(i.slot) === String(v)); if (!it) return;
  const r = await confirmBox(`Remove ${it.label}`, `${d.label} has ${num(it.count)} in slot ${it.slot}.`, { ok: 'Remove', fields: [{ name: 'count', label: 'Amount', type: 'number', value: it.count, presets: [[1, '1'], [it.count, 'All']] }] });
  if (!r) return;
  if (await call('inventory:removeFrom', { inv: d.id, item: it.name, count: +r.count, slot: it.slot }, 'Removed')) viewInventory(d.id);
};

/* ═══ STORAGE (every saved stash, trunk and glovebox) ════════════════════ */
page('storage', {
  label: 'Stashes & trunks', icon: 'fas fa-boxes-stacked',
  when: () => S.boot.remoteView && S.boot.inventory && S.boot.inventory.storage,
  async enter() { const st = pd('storage'); st.kind = st.kind || 'all'; await storageLoad(); },
  render() {
    const st = pd('storage'); const d = st.data;
    const KIND = { stash: ['Stash', 'fas fa-warehouse', 'amber'], trunk: ['Trunk', 'fas fa-car', ''], glovebox: ['Glovebox', 'fas fa-car-side', ''] };
    let body = loading();
    if (d) body = d.rows.length ? `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Inventory</th><th>Type</th><th>Owner</th><th class="num">Stacks</th><th class="num">Items</th><th></th></tr></thead><tbody>${d.rows.map(r => {
      const k = KIND[r.kind] || [r.kind, 'fas fa-box', ''];
      return `<tr class="click" data-a="logInv" data-v="${esc(r.id)}"><td><b class="mono">${esc(r.label)}</b>${r.label !== r.id ? ` <span class="muted mono" style="font-size:10.5px">${esc(r.id)}</span>` : ''}</td><td>${chip(k[0], k[2], k[1])}</td><td class="mono">${esc(r.owner || '-')}</td><td class="num">${num(r.stacks)}</td><td class="num"><b>${num(r.count)}</b></td><td class="act">${btn('Open', 'logInv', 'xs', { v: r.id })}</td></tr>`;
    }).join('')}</tbody></table></div>${d.total > d.rows.length ? `<div class="muted" style="margin-top:10px;font-size:11px">Showing ${num(d.rows.length)} of ${num(d.total)}. Search to narrow it down.</div>` : ''}` : empty('fas fa-boxes-stacked', st.q ? 'Nothing matches' : 'Nothing saved yet', 'Stashes, trunks and gloveboxes show up here once something has been stored in them.');
    const inv = (S.boot.inventory && S.boot.inventory.label) || 'the inventory';
    return ph('Stashes & trunks', `Every saved stash, trunk and glovebox in ${inv}`, btn('', 'storageLoad', 'btn-ghost sm', { icon: 'fas fa-rotate', title: 'Reload' })) + `<div class="content">
      <div class="toolbar"><div class="search" style="max-width:320px"><i class="fas fa-magnifying-glass"></i><input class="inp" data-in="storageQ" value="${esc(st.q || '')}" placeholder="Stash id, plate or owner"></div>
        ${seg([['all', 'Everything'], ['stash', 'Stashes'], ['trunk', 'Trunks'], ['glovebox', 'Gloveboxes']], st.kind, 'storageKind')}</div>${body}</div>`;
  },
});
async function storageLoad(typing) {
  const st = pd('storage');
  if (!typing) { st.data = null; rerender(); }
  const r = await rpc('storage:list', { kind: st.kind, q: st.q || '' });
  st.data = r.ok ? r.data : { rows: [], total: 0 };
  if (!r.ok) toast(r.err, 'error');
  if (S.page !== 'storage') return;
  rerender();
  if (typing) { const i = $('[data-in="storageQ"]'); if (i) { i.focus(); i.setSelectionRange(i.value.length, i.value.length); } }
}
A.storageLoad = () => storageLoad();
A.storageKind = v => { pd('storage').kind = v; storageLoad(); };
IN.storageQ = debounce(v => { pd('storage').q = v; storageLoad(true); }, 300);

/* ═══ AUDIT ═════════════════════════════════════════════════════════════ */
page('audit', {
  label: 'Staff audit', icon: 'fas fa-user-shield',
  async enter() { await loadAudit(1); },
  render() {
    const st = pd('audit'); const d = st.data;
    let body = loading();
    if (d) body = d.rows.length ? `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>When</th><th>Staff</th><th>Action</th><th>Target</th><th>Details</th></tr></thead><tbody>${d.rows.map(r => {
      let det = r.details; try { det = JSON.stringify(JSON.parse(r.details)); } catch (e) { /* keep */ }
      return `<tr><td>${esc(date(r.time))}</td><td><b>${esc(r.admin_name)}</b></td><td>${chip(r.action.replace(/_/g, ' '), /wipe|remove|delete|rollback|restart/.test(r.action) ? 'red' : /editor/.test(r.action) ? 'teal' : '')}</td><td class="mono">${esc(r.target || '')}</td><td class="wrap mono" style="font-size:10.5px">${esc(det === '{}' ? '' : det)}</td></tr>`;
    }).join('')}</tbody></table></div>${pager(d, 'auditPage')}` : empty('fas fa-user-shield', 'No staff actions yet');
    return ph('Staff audit', 'Every give, removal, wipe, edit and rollback, with who did it') + `<div class="content">
      <div class="toolbar"><div class="search" style="max-width:320px"><i class="fas fa-magnifying-glass"></i><input class="inp" data-in="auditQ" value="${esc(st.q || '')}" placeholder="Staff name, action or target"></div></div>${body}</div>`;
  },
});
async function loadAudit(p) { const st = pd('audit'); const r = await rpc('audit:list', { page: p, q: st.q || '' }); if (r.ok) { st.data = r.data; if (S.page === 'audit') rerender(); } }
IN.auditQ = debounce(v => { pd('audit').q = v; loadAudit(1); }, 300);
A.auditPage = v => loadAudit(+v);

/* ═══ PLAYERS ═══════════════════════════════════════════════════════════ */
page('players', {
  label: 'Players', icon: 'fas fa-users',
  badge() { const l = pd('players').online; return l ? `<span class="tally">${l.length}</span>` : ''; },
  async enter() { const st = pd('players'); st.mode = st.mode || 'online'; await loadOnline(); if (st.mode === 'search' && !st.results) plSearchRun(); if (st.sel) loadPlayerInv(); },
  render() {
    const st = pd('players');
    const q = (st.q || '').toLowerCase();
    let list;
    if (st.mode === 'online') {
      const rows = (st.online || []).filter(p => !q || [p.id, p.name, p.player, p.charId, p.job].join(' ').toLowerCase().includes(q));
      list = !st.online ? loading() : rows.length ? rows.map(p => `<div class="li click ${st.sel && st.sel.id === p.id ? 'on' : ''}" data-a="plPick" data-v="${esc(JSON.stringify({ id: p.id, name: p.name, charId: p.charId }))}">${av(p.name, 'sm', true, p.avatar)}<div class="tx"><b>${esc(p.name)}</b><span>#${p.id} · ${esc(p.player)}${p.job ? ' · ' + esc(p.job) : ''}</span></div></div>`).join('') : empty('fas fa-user-slash', 'Nobody matches');
    } else {
      const rows = st.results;
      list = !rows ? loading() : rows.length ? rows.map(p => `<div class="li click ${st.sel && st.sel.charId === p.charId ? 'on' : ''}" data-a="plPick" data-v="${esc(JSON.stringify({ id: p.online, charId: p.charId, name: p.name }))}">${av(p.name, 'sm', !!p.online)}<div class="tx"><b>${esc(p.name || p.charId)}</b><span><span class="mono">${esc(p.charId)}</span>${p.job ? ' · ' + esc(p.job) : ''}</span></div><div class="rt">${p.online ? chip('Online #' + p.online, 'teal') : chip('Offline')}${p.seen && !p.online ? `<br><span style="display:inline-block;margin-top:4px">${esc(ago(p.seen))}</span>` : ''}</div></div>`).join('') : empty('fas fa-user-slash', st.q ? 'No characters match' : 'No characters found', st.q ? 'Try part of the first or last name, the character id or the license.' : 'The character table is empty.');
    }
    const left = `<div class="pane-l"><div class="pane-h">${seg([['online', `Online (${(st.online || []).length})`], ['search', 'All characters']], st.mode, 'plMode')}
      <div class="search"><i class="fas fa-magnifying-glass"></i><input class="inp" id="pl-q" data-in="plQ" ${st.mode === 'search' ? 'data-enter="plSearch"' : ''} value="${esc(st.q || '')}" placeholder="${st.mode === 'online' ? 'Filter by name, id, job' : 'Name, character id or license'}"></div></div>
      <div class="pane-b">${list}</div></div>`;
    return `<div class="content flush"><div class="split">${left}<div class="pane-r">${playerPane()}</div></div></div>`;
  },
});
async function loadOnline() { const st = pd('players'); const r = await rpc('players:online'); if (r.ok) { st.online = r.data; refreshNav(); if (S.page === 'players') rerender(); } }
function plRerenderKeepFocus() {
  const i = $('#pl-q'); const had = i && document.activeElement === i; const pos = i ? i.selectionStart : 0;
  rerender();
  const n = $('#pl-q'); if (n && had) { n.focus(); n.setSelectionRange(pos, pos); }
}
/** All characters: empty search lists the most recently seen, typing searches as you go */
async function plSearchRun() {
  const st = pd('players');
  const q = (st.q || '').trim();
  const r = await rpc('players:search', { q });
  if ((pd('players').q || '').trim() !== q || st.mode !== 'search') return;
  if (!r.ok) toast(r.err, 'error');
  st.results = r.ok ? r.data : [];
  if (S.page === 'players') plRerenderKeepFocus();
}
const plSearchSoon = debounce(plSearchRun, 280);
A.plMode = v => { const st = pd('players'); st.mode = v; st.q = ''; if (v === 'search') st.results = null; rerender(); const i = $('#pl-q'); if (i) i.focus(); if (v === 'search') plSearchRun(); };
IN.plQ = (v) => { const st = pd('players'); st.q = v; if (st.mode === 'online') plFilterSoon(); else plSearchSoon(); };
const plFilterSoon = debounce(() => plRerenderKeepFocus(), 120);
A.plSearch = v => { const st = pd('players'); if (typeof v === 'string') st.q = v; plSearchRun(); };
A.plPick = v => { const st = pd('players'); st.sel = JSON.parse(v); st.inv = null; st.ptab = st.ptab || 'inv'; st.slot = null; rerender(); loadPlayerInv(); };
async function loadPlayerInv() {
  const st = pd('players');
  if (!st.sel) return;
  const target = st.sel.id ? { id: st.sel.id } : { charId: st.sel.charId, name: st.sel.name };
  const r = await rpc('inventory:get', { target });
  if (!r.ok) { toast(r.err, 'error'); st.inv = { error: r.err }; }
  else st.inv = r.data;
  if (st.ptab === 'act' && st.inv.target) {
    const t = await rpc('player:timeline', { identifier: st.inv.target.charId });
    st.timeline = t.ok ? t.data : [];
  }
  if (S.page === 'players') rerender();
}
function targetOf() { const st = pd('players'); const t = st.inv && st.inv.target; return t ? (t.online ? { id: t.id } : { charId: t.charId, name: t.name }) : null; }
function playerPane() {
  const st = pd('players');
  if (!st.sel) return empty('fas fa-user', 'Pick a player', 'Their inventory, activity and quick actions open here.');
  const d = st.inv;
  if (!d) return loading();
  if (d.error) return empty('fas fa-triangle-exclamation', 'Could not load them', d.error);
  const t = d.target;
  const pct = d.maxWeight ? Math.min(100, d.weight / d.maxWeight * 100) : 0;
  const onl = (pd('players').online || []).find(p => (t.id && p.id === t.id) || (t.charId && p.charId === t.charId));
  const head = `<div class="prof-h">${av(t.name, 'lg', t.online, onl && onl.avatar)}<div class="tx"><h2>${esc(t.name)} ${t.online ? chip('Online #' + t.id, 'teal') : chip('Offline')}</h2>
      <p><span class="mono">${esc(t.charId || '')}</span>${t.player ? `<span>${esc(t.player)}</span>` : ''}<span>${d.items.length} stacks</span></p></div>
    <div class="r">${can('manage') ? btn('Give item', 'plGive', 'btn-teal sm', { icon: 'fas fa-plus' }) : ''}
      ${btn('', 'plRefresh', 'sm btn-ghost', { icon: 'fas fa-rotate', title: 'Reload' })}
      ${can('manage') ? btn('Wipe', 'plWipe', 'sm btn-red', { icon: 'fas fa-eraser' }) : ''}</div></div>`;
  let body;
  if ((st.ptab || 'inv') === 'inv') {
    body = `${!t.online ? note('They are offline. Changes are written straight to their saved inventory and apply when they next join.', 'amber') + '<div style="height:12px"></div>' : ''}
      <div class="wbar" style="margin-bottom:12px"><span>Weight</span><div class="track"><i style="width:${pct}%"></i></div><span>${num(Math.round(d.weight / 100) / 10)} / ${num(Math.round(d.maxWeight / 100) / 10)} kg</span></div>
      ${inventoryGrid(d.items, 'plSlot', st.slot)}`;
  } else {
    const tl = st.timeline;
    body = !tl ? loading() : tl.length ? `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>When</th><th>Type</th><th>Item</th><th class="num">Amount</th><th>What happened</th></tr></thead><tbody>${tl.map(l => `<tr class="click" data-a="tlOpen" data-v="${l.id}"><td>${esc(date(l.time))}</td><td>${badge(l.type)}</td><td><b>${esc(l.item_label || l.item_name)}</b></td><td class="num">${num(l.item_count)}</td><td class="wrap">${esc(l.details || '')}</td></tr>`).join('')}</tbody></table></div>` : empty('fas fa-timeline', 'No logged activity');
  }
  return head + tabs([['inv', 'Inventory', 'fas fa-box-open'], ['act', 'Activity', 'fas fa-timeline']], st.ptab || 'inv', 'plTab') + `<div class="content" style="padding-top:14px">${body}</div>`;
}
A.tlOpen = v => { const l = (pd('players').timeline || []).find(x => String(x.id) === String(v)); if (l) openLog(l); };
A.plTab = async v => { const st = pd('players'); st.ptab = v; rerender(); if (v === 'act') { st.timeline = null; const r = await rpc('player:timeline', { identifier: st.inv.target.charId }); st.timeline = r.ok ? r.data : []; rerender(); } };
A.plRefresh = () => loadPlayerInv();
A.plGive = async () => {
  await loadItems();
  const v = await form({ title: `Give to ${pd('players').inv.target.name}`, icon: 'fas fa-gift', fields: [
    itemField('item', 'Item', '', { span: true }),
    { name: 'count', label: 'Amount', type: 'number', value: 1, presets: [1, 5, 10, 50, 100], min: 1 },
    { name: 'force', label: 'Ignore their weight limit', type: 'check' },
    { name: 'metadata', label: 'Metadata (optional JSON)', type: 'textarea', mono: true, span: true, placeholder: '{"label":"Signed contract","serial":"A1"}' }],
    validate: x => !S.itemMap[x.item] ? 'Pick an item from the list.' : null });
  if (!v) return;
  if (await call('inventory:give', { target: targetOf(), item: v.item, count: +v.count, force: v.force, metadata: v.metadata.trim() }, `Gave ${itemLabel(v.item)} x${v.count}`)) loadPlayerInv();
};
A.plWipe = async () => {
  const t = pd('players').inv.target;
  if (!await confirmBox(`Wipe ${t.name}'s inventory?`, 'Every item is removed. Use a rollback snapshot if you need it back.', { ok: 'Wipe inventory' })) return;
  if (await call('inventory:wipe', { target: targetOf() }, 'Inventory wiped')) loadPlayerInv();
};
A.plSlot = async v => {
  const st = pd('players');
  const it = st.inv.items.find(i => String(i.slot) === String(v)); if (!it) return;
  st.slot = it.slot;
  $$('.slot').forEach(s => s.classList.toggle('on', s.dataset.v === String(v)));
  const mayEdit = can('manage');
  const r = await form({ title: `${it.label} x${num(it.count)}`, sub: `Slot ${it.slot} · ${it.name}`, icon: 'fas fa-box', size: 'lg', ok: mayEdit ? 'Set amount' : false, cancel: 'Close',
    body: `<div style="display:flex;gap:12px;align-items:center">${thumb(it.name, it.metadata && it.metadata.image ? it.metadata.image + '.png' : null, 'lg')}<div class="grow"><div class="field"><label>Metadata</label>${metaHtml(it.metadata)}</div></div></div>
      <div class="row-btns">${mayEdit ? btn('Remove all', 'slotRemoveAll', 'sm btn-red', { v: it.slot, icon: 'fas fa-trash' }) : ''}${btn('Find everywhere', 'findItem', 'sm', { v: it.name, icon: 'fas fa-magnifying-glass-location' })}${btn('Item logs', 'logFilterItem', 'sm btn-ghost', { v: it.name, icon: 'fas fa-list-ul' })}${it.metadata && Object.keys(it.metadata).length ? btn('Copy metadata', 'copyText', 'sm btn-ghost', { v: JSON.stringify(it.metadata), icon: 'fas fa-copy' }) : ''}</div>`,
    fields: mayEdit ? [{ name: 'count', label: 'Amount in this slot', type: 'number', value: it.count, min: 0, help: 'Set 0 to remove the stack.' }] : [] });
  if (!r) return;
  if (await call('inventory:set', { target: targetOf(), item: it.name, slot: it.slot, count: +r.count }, 'Amount updated')) loadPlayerInv();
};
A.slotRemoveAll = async v => {
  const st = pd('players'); const it = st.inv.items.find(i => String(i.slot) === String(v));
  closeModal(null);
  if (await call('inventory:remove', { target: targetOf(), item: it.name, count: it.count, slot: it.slot }, `Removed ${it.label}`)) loadPlayerInv();
};

/* ═══ FIND ITEM ═════════════════════════════════════════════════════════ */
page('finder', {
  label: 'Find item', icon: 'fas fa-magnifying-glass-location',
  async enter() { await loadItems(); const st = pd('finder'); st.scope = st.scope || { online: true, offline: true, stashes: true, vehicles: true }; },
  render() {
    const st = pd('finder'); const sc = st.scope || {};
    const r = st.res;
    const check = (k, l) => `<label class="chk"><input type="checkbox" data-ch="finderScope" data-k="${k}" ${sc[k] ? 'checked' : ''}><span class="box"></span>${l}</label>`;
    let body = empty('fas fa-magnifying-glass-location', 'Find where an item is', 'Counts every copy in online players, offline characters, stashes and vehicles. Handy for tracking down dupes.');
    if (st.busy) body = `<div class="loading" style="gap:12px"><div class="spin"></div><span class="muted">Saving inventories and searching the database</span></div>`;
    else if (r) {
      const sec = (title, icon, rows, total, head, cell) => rows.length ? `<div class="card"><div class="card-h"><h3><i class="${icon}"></i>${title}</h3><div class="r">${chip(num(total) + ' total', 'teal')}</div></div><div class="card-b np"><div class="tbl-wrap" style="border:0;border-radius:0;max-height:260px"><table class="tbl"><thead><tr>${head}</tr></thead><tbody>${rows.map(cell).join('')}</tbody></table></div></div></div>` : '';
      body = `<div class="g4" style="margin-bottom:14px">
        <div class="stat"><div class="lbl"><i class="fas fa-user"></i>Online players</div><div class="val">${num(r.totals.online)}</div><div class="sub">${r.online.length} inventories</div></div>
        <div class="stat" style="--c:var(--blue)"><div class="lbl"><i class="fas fa-user-clock"></i>Offline characters</div><div class="val">${num(r.totals.offline)}</div><div class="sub">${r.offline.length} inventories</div></div>
        <div class="stat" style="--c:var(--amber)"><div class="lbl"><i class="fas fa-warehouse"></i>Stashes</div><div class="val">${num(r.totals.stashes)}</div><div class="sub">${r.stashes.length} inventories</div></div>
        <div class="stat" style="--c:#8e4ec6"><div class="lbl"><i class="fas fa-car"></i>Vehicles</div><div class="val">${num(r.totals.vehicles)}</div><div class="sub">${r.vehicles.length} trunks and gloveboxes</div></div></div>
        ${r.total === 0 ? empty('fas fa-check', `No ${itemLabel(r.item)} anywhere`, 'Nothing found in the places you searched.') : `<div class="stack">
        ${sec('Online players', 'fas fa-user', r.online, r.totals.online, '<th>Player</th><th>Character</th><th class="num">Count</th><th></th>', x => `<tr><td><b>${esc(x.name)}</b> <span class="muted">#${x.id}</span></td><td class="mono">${esc(x.charId || '')}</td><td class="num"><b>${num(x.count)}</b></td><td class="act">${btn('Open', 'finderPlayer', 'xs', { v: JSON.stringify({ id: x.id, name: x.name, charId: x.charId }) })}</td></tr>`)}
        ${sec('Offline characters', 'fas fa-user-clock', r.offline, r.totals.offline, '<th>Character</th><th>Id</th><th class="num">Count</th><th></th>', x => `<tr><td><b>${esc(x.name || '-')}</b></td><td class="mono">${esc(x.charId)}</td><td class="num"><b>${num(x.count)}</b></td><td class="act">${btn('Open', 'finderPlayer', 'xs', { v: JSON.stringify({ charId: x.charId, name: x.name || x.charId }) })}</td></tr>`)}
        ${sec('Stashes', 'fas fa-warehouse', r.stashes, r.totals.stashes, '<th>Stash</th><th>Owner</th><th class="num">Count</th><th></th>', x => `<tr><td><b class="mono">${esc(x.name)}</b></td><td class="mono">${esc(x.owner || '-')}</td><td class="num"><b>${num(x.count)}</b></td><td class="act">${S.boot.remoteView ? btn('Open', 'logInv', 'xs', { v: x.id || (x.owner ? `${x.name}:${x.owner}` : x.name) }) : ''}</td></tr>`)}
        ${sec('Vehicles', 'fas fa-car', r.vehicles, r.totals.vehicles, '<th>Vehicle</th><th>Where</th><th class="num">Count</th><th></th>', x => `<tr><td><b class="mono">${esc(x.key)}</b></td><td>${esc(x.where)}</td><td class="num"><b>${num(x.count)}</b></td><td class="act">${S.boot.remoteView ? btn('Open', 'logInv', 'xs', { v: x.id || ((x.where === 'trunk' ? 'trunk' : 'glove') + x.key) }) : ''}</td></tr>`)}
        </div>`}`;
    }
    return ph('Find item', 'See every copy of an item on the server, then remove them if you need to', r && r.total && can('global') ? btn(`Remove all ${num(r.total)}`, 'finderRemove', 'btn-red sm', { icon: 'fas fa-trash' }) : '') + `<div class="content">
      <div class="toolbar"><div class="search" style="max-width:300px"><i class="fas fa-box"></i><input class="inp" id="finder-item" list="dl-items" value="${esc(st.item || '')}" placeholder="Item name" data-enter="finderScan"></div>
        ${check('online', 'Online')}${check('offline', 'Offline characters')}${check('stashes', 'Stashes')}${check('vehicles', 'Vehicles')}
        ${btn('Search', 'finderScan', 'btn-teal', { icon: 'fas fa-magnifying-glass' })}</div>${body}</div>`;
  },
});
CH.finderScope = (v, el) => { pd('finder').scope[el.dataset.k] = v; };
A.finderScan = async () => {
  const st = pd('finder');
  const i = $('#finder-item'); if (i) st.item = i.value.trim();
  if (!st.item) return toast('Type an item name first.', 'error');
  st.busy = true; st.res = null; rerender();
  const r = await rpc('global:scan', { item: st.item, scope: st.scope });
  st.busy = false;
  if (!r.ok) { toast(r.err, 'error'); rerender(); return; }
  st.res = r.data; rerender();
};
A.finderPlayer = v => { const st = pd('players'); st.sel = JSON.parse(v); st.inv = null; st.ptab = 'inv'; st.mode = st.sel.id ? 'online' : 'search'; go('players'); };
A.finderRemove = async () => {
  const st = pd('finder'); const r = st.res;
  const v = await confirmBox(`Remove ${itemLabel(r.item)} everywhere?`, `${num(r.total)} copies were found in the places you searched. This is logged and can't be undone except through a rollback.`, { ok: 'Remove', fields: [
    { name: 'amount', label: 'How many to take from each inventory', value: '', placeholder: 'Leave empty to remove every copy', type: 'number', min: 1 },
    { name: 'confirm', label: `Type ${r.item} to confirm`, value: '' }] });
  if (!v) return;
  if (v.confirm.trim() !== r.item) return toast('The confirmation text did not match, nothing was removed.', 'error');
  st.busy = true; rerender();
  const res = await rpc('global:remove', { item: r.item, scope: st.scope, amount: v.amount ? +v.amount : null });
  st.busy = false;
  if (!res.ok) { toast(res.err, 'error'); rerender(); return; }
  toast(`Removed ${num(res.data.total)} from ${num(res.data.inventories)} inventories`, 'success');
  A.finderScan();
};

/* ═══ SERVER-WIDE ═══════════════════════════════════════════════════════ */
page('global', {
  label: 'Server-wide', icon: 'fas fa-globe', tier: 'global',
  async enter() { await loadItems(); const r = await rpc('players:online'); if (r.ok) { pd('global').online = r.data; if (S.page === 'global') rerender(); } },
  render() {
    const st = pd('global'); const g = st.g || (st.g = { item: '', count: 1, jobs: '', exclude: '', message: '', metadata: '', force: false });
    const online = st.online || [];
    const jobs = g.jobs.split(',').map(s => s.trim().toLowerCase()).filter(Boolean);
    const excl = g.exclude.split(',').map(s => +s.trim()).filter(Boolean);
    const recipients = online.filter(p => (!jobs.length || jobs.includes(String(p.jobName || '').toLowerCase())) && !excl.includes(p.id));
    const res = st.res;
    return ph('Server-wide', 'Hand an item to everyone online, or clear an item out of the whole server') + `<div class="content"><div class="g2">
      <div class="card"><div class="card-h"><h3><i class="fas fa-gift"></i>Give to everyone online</h3></div><div class="card-b"><div class="stack" style="gap:12px">
        <div class="fgrid"><div class="field span"><label>Item</label><input class="inp" list="dl-items" data-in="glF" data-k="item" value="${esc(g.item)}" placeholder="Start typing an item name"></div>
          <div class="field"><label>Amount each <small>max ${num(S.boot.globalMax)}</small></label><input class="inp" type="number" min="1" data-in="glF" data-k="count" value="${esc(g.count)}"></div>
          <div class="field"><label>Only these jobs <small>comma separated</small></label><input class="inp" data-in="glF" data-k="jobs" value="${esc(g.jobs)}" placeholder="police, ambulance"></div>
          <div class="field"><label>Skip these ids</label><input class="inp" data-in="glF" data-k="exclude" value="${esc(g.exclude)}" placeholder="12, 40"></div>
          <div class="field"><label>Message to players <small>optional</small></label><input class="inp" data-in="glF" data-k="message" value="${esc(g.message)}" placeholder="Happy holidays from staff"></div>
          <div class="field span"><label>Metadata <small>optional JSON</small></label><textarea class="txt mono" rows="2" data-in="glF" data-k="metadata" placeholder='{"label":"Event ticket"}'>${esc(g.metadata)}</textarea></div>
          <label class="chk span"><input type="checkbox" data-ch="glForce" ${g.force ? 'checked' : ''}><span class="box"></span>Ignore weight limits</label></div>
        <div class="note" id="gl-recip"><i class="fas fa-users"></i><div><b>${recipients.length}</b> of ${online.length} online players will get it${g.item && S.itemMap[g.item] ? `: <b>${esc(itemLabel(g.item))} x${num(g.count)}</b> each` : ''}.</div></div>
        <div class="row-btns">${btn('Give to everyone', 'glGive', 'btn-teal', { icon: 'fas fa-paper-plane' })}</div>
        ${res ? `<div class="note ${res.full.length ? 'amber' : ''}"><i class="fas fa-circle-check"></i><div>Gave <b>${num(res.given)}</b> to <b>${res.players}</b> players.${res.full.length ? ` ${res.full.length} could not carry it: ${esc(res.full.map(p => p.name).slice(0, 8).join(', '))}${res.full.length > 8 ? '…' : ''}` : ''}</div></div>` : ''}
      </div></div></div>
      <div class="stack">
        <div class="card"><div class="card-h"><h3><i class="fas fa-broom"></i>Remove from the whole server</h3></div><div class="card-b"><div class="stack" style="gap:12px">
          <p class="ink2" style="font-size:11.5px;line-height:1.55">Search first so you can see exactly how many copies exist and where, then remove them from online players, offline characters, stashes and vehicles in one go.</p>
          <div class="row-btns">${btn('Open Find item', 'nav', 'btn-red', { v: 'finder', icon: 'fas fa-magnifying-glass-location' })}</div></div></div></div>
        <div class="card"><div class="card-h"><h3><i class="fas fa-terminal"></i>Chat commands</h3></div><div class="card-b ink2" style="font-size:11.5px;line-height:1.8">
          <div><span class="mono tteal">/igiveall item amount</span> gives to every player online</div>
          <div><span class="mono tteal">/iremoveall item</span> removes it from every player online</div>
          <div><span class="mono tteal">/igive id item amount</span> and <span class="mono tteal">/iremove id item amount</span> for one player</div>
          <div class="muted" style="margin-top:6px">Every command is logged the same way as the panel.</div></div></div>
      </div></div></div>`;
  },
});
IN.glF = (v, el) => {
  const st = pd('global'); st.g[el.dataset.k] = v;
  if (['jobs', 'exclude', 'item', 'count'].includes(el.dataset.k)) {
    const tmp = document.createElement('div'); tmp.innerHTML = PAGES.global.render();
    const n = tmp.querySelector('#gl-recip'); const o = $('#gl-recip'); if (n && o) o.replaceWith(n);
  }
};
CH.glForce = v => { pd('global').g.force = v; };
A.glGive = async () => {
  const st = pd('global'); const g = st.g;
  if (!S.itemMap[g.item]) return toast('Pick an item from the list.', 'error');
  const count = Math.floor(+g.count || 0);
  if (count < 1) return toast('Amount has to be at least 1.', 'error');
  const jobs = g.jobs.split(',').map(s => s.trim()).filter(Boolean);
  const exclude = g.exclude.split(',').map(s => +s.trim()).filter(Boolean);
  if (!await confirmBox(`Give ${itemLabel(g.item)} x${num(count)} to everyone?`, jobs.length ? `Only players with these jobs: ${jobs.join(', ')}` : 'Every player online gets it.', { tone: '', icon: 'fas fa-gift', ok: 'Give', okClass: 'btn-teal' })) return;
  const r = await call('global:give', { item: g.item, count, jobs, exclude, message: g.message, metadata: g.metadata.trim(), force: g.force });
  if (r) { st.res = r; toast(`Gave ${itemLabel(g.item)} to ${r.players} players`, 'success'); rerender(); }
};

/* ═══ ROLLBACK ══════════════════════════════════════════════════════════ */
page('rollback', {
  label: 'Rollback', icon: 'fas fa-clock-rotate-left', tier: 'rollback',
  when: () => S.boot.rollback,
  async enter() { const st = pd('rb'); st.kind = st.kind || 'inventory'; await loadSnaps(); },
  render() {
    const st = pd('rb');
    const list = st.list;
    const left = `<div class="pane-l"><div class="pane-h">${seg([['inventory', 'Inventories'], ['money', 'Money']], st.kind, 'rbKind')}${btn('Take a snapshot now', 'rbTake', 'sm btn-ghost full', { icon: 'fas fa-camera' })}</div>
      <div class="pane-b">${!list ? loading() : list.length ? list.map(s => `<div class="li click ${st.snap && st.snap.id === s.id ? 'on' : ''}" data-a="rbOpen" data-v="${s.id}"><div class="av sm"><i class="fas fa-camera"></i></div><div class="tx"><b>${esc(date(s.time))}</b><span>${s.players} characters · ${ago(s.time)}</span></div></div>`).join('') : empty('fas fa-camera', 'No snapshots yet', 'They are taken automatically every few minutes while players are online.')}</div></div>`;
    let right = empty('fas fa-clock-rotate-left', 'Pick a snapshot', 'Compare a character with how they were, then roll back one character or everyone.');
    const s = st.snap;
    if (s) {
      const q = (st.q || '').toLowerCase();
      const rows = s.players.filter(p => !q || [p.name, p.player, p.charId].join(' ').toLowerCase().includes(q));
      right = `<div class="prof-h"><div class="av lg"><i class="fas fa-camera"></i></div><div class="tx"><h2>${s.kind === 'money' ? 'Money' : 'Inventories'} at ${esc(date(s.time))}</h2><p><span>${s.players.length} characters</span><span>${ago(s.time)}</span></p></div>
        <div class="r">${btn('Roll back everyone', 'rbAll', 'btn-red sm', { icon: 'fas fa-rotate-left' })}</div></div>
        <div class="content" style="padding-top:14px"><div class="toolbar"><div class="search" style="max-width:300px"><i class="fas fa-magnifying-glass"></i><input class="inp" data-in="rbQ" value="${esc(st.q || '')}" placeholder="Filter characters"></div></div>
        <div class="tbl-wrap"><table class="tbl"><thead><tr><th>Character</th><th>Id</th><th class="num">${s.kind === 'money' ? 'Total money' : 'Stacks'}</th><th></th><th></th></tr></thead><tbody>${rows.map(p => `<tr><td><b>${esc(p.name)}</b> <span class="muted">${esc(p.player || '')}</span></td><td class="mono">${esc(p.charId)}</td><td class="num"><b>${s.kind === 'money' ? '$' + num(p.summary) : num(p.summary)}</b></td><td>${p.online ? chip('Online', 'teal') : chip('Offline')}</td>
          <td class="act"><div class="row-btns" style="flex-wrap:nowrap">${btn('Compare', 'rbCompare', 'xs', { v: p.charId, icon: 'fas fa-code-compare' })}${btn('Roll back', 'rbOne', 'xs btn-red', { v: p.charId, disabled: s.kind === 'money' && !p.online })}</div></td></tr>`).join('')}</tbody></table></div></div>`;
    }
    return `<div class="content flush"><div class="split">${left}<div class="pane-r">${right}</div></div></div>`;
  },
});
async function loadSnaps() { const st = pd('rb'); st.list = null; rerender(); const r = await rpc('snapshots:list', { kind: st.kind }); st.list = r.ok ? r.data : []; if (S.page === 'rollback') rerender(); }
A.rbKind = v => { const st = pd('rb'); st.kind = v; st.snap = null; loadSnaps(); };
A.rbTake = async () => { if (await call('snapshots:take', {}, 'Snapshot saved')) loadSnaps(); };
A.rbOpen = async v => { const r = await call('snapshots:get', { id: +v }); if (r) { pd('rb').snap = r; rerender(); } };
IN.rbQ = debounce(v => { pd('rb').q = v; rerender(); const i = $('[data-in="rbQ"]'); if (i) { i.focus(); i.setSelectionRange(v.length, v.length); } }, 150);
A.rbCompare = async v => {
  const s = pd('rb').snap;
  const d = await call('snapshots:compare', { id: s.id, charId: v });
  if (!d) return;
  let body;
  if (d.kind === 'money') {
    const keys = [...new Set(Object.keys(d.before || {}).concat(Object.keys(d.now || {})))];
    body = `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Account</th><th class="num">Then</th><th class="num">Now</th><th class="num">Change</th></tr></thead><tbody>${keys.map(k => { const a = +(d.before || {})[k] || 0, b = d.now ? +(d.now[k] || 0) : null; const df = b === null ? null : b - a; return `<tr><td><b>${esc(k)}</b></td><td class="num">$${num(a)}</td><td class="num">${b === null ? '-' : '$' + num(b)}</td><td class="num ${df > 0 ? 'tteal' : df < 0 ? 'tred' : ''}">${df === null ? 'offline' : (df > 0 ? '+' : '') + num(df)}</td></tr>`; }).join('')}</tbody></table></div>`;
  } else {
    const sum = list => { const m = {}; (list || []).forEach(i => { if (i && i.name) m[i.name] = (m[i.name] || 0) + (i.count || 0); }); return m; };
    const a = sum(d.before), b = sum(d.now);
    const keys = [...new Set(Object.keys(a).concat(Object.keys(b)))].sort((x, y) => Math.abs((b[y] || 0) - (a[y] || 0)) - Math.abs((b[x] || 0) - (a[x] || 0)));
    body = `<div class="tbl-wrap" style="max-height:420px"><table class="tbl"><thead><tr><th>Item</th><th class="num">Then</th><th class="num">Now</th><th class="num">Change</th></tr></thead><tbody>${keys.map(k => { const df = (b[k] || 0) - (a[k] || 0); return `<tr><td><div class="cell">${thumb(k)}<b>${esc(itemLabel(k))}</b></div></td><td class="num">${num(a[k] || 0)}</td><td class="num">${num(b[k] || 0)}</td><td class="num ${df > 0 ? 'tteal' : df < 0 ? 'tred' : 'muted'}">${df === 0 ? 'same' : (df > 0 ? '+' : '') + num(df)}</td></tr>`; }).join('')}</tbody></table></div>`;
  }
  infoBox(`${d.name} · then vs now`, body, { size: 'lg', icon: 'fas fa-code-compare', sub: `Snapshot from ${date(d.time)}${d.online ? '' : ' · character is offline'}` });
};
A.rbOne = async v => {
  const s = pd('rb').snap; const p = s.players.find(x => x.charId === v);
  if (!await confirmBox(`Roll back ${p.name}?`, s.kind === 'money' ? `Their accounts are set back to how they were at ${date(s.time)}.` : `Their current inventory is replaced with the one from ${date(s.time)}.`, { ok: 'Roll back' })) return;
  const r = await call('snapshots:rollback', { id: s.id, charId: v });
  if (r) toast(`Rolled back ${p.name}`, 'success');
};
A.rbAll = async () => {
  const s = pd('rb').snap;
  const v = await confirmBox('Roll back everyone in this snapshot?', `${s.players.length} characters go back to ${date(s.time)}. ${s.kind === 'money' ? 'Offline characters are skipped.' : 'Offline characters are written directly to the database.'}`, { ok: 'Roll back everyone', fields: [{ name: 'confirm', label: 'Type ROLLBACK to confirm' }] });
  if (!v) return;
  if (v.confirm.trim().toUpperCase() !== 'ROLLBACK') return toast('Confirmation did not match, nothing changed.', 'error');
  const r = await call('snapshots:rollback', { id: s.id });
  if (r) toast(`Rolled back ${r.restored} characters${r.skipped ? `, ${r.skipped} skipped` : ''}`, 'success');
};
