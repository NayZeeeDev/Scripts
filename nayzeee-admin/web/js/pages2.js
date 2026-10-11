'use strict';
/* ═══ VEHICLES ══════════════════════════════════════════════════════════ */
const VCLASS = ['Compacts', 'Sedans', 'SUVs', 'Coupes', 'Muscle', 'Sports Classics', 'Sports', 'Super', 'Motorcycles', 'Off-road', 'Industrial', 'Utility', 'Vans', 'Cycles', 'Boats', 'Helicopters', 'Planes', 'Service', 'Emergency', 'Military', 'Commercial', 'Trains', 'Open Wheel'];
page('vehicles', {
  label: 'Vehicles', icon: 'fas fa-car', perms: ['vehicles.spawn', 'vehicles.view', 'vehicles_database.view', 'vehicles.force_wipe'],
  async enter() { await loadVehTab(); },
  render() {
    const st = pd('vehicles');
    const T = [];
    if (can('vehicles.spawn')) T.push(['spawn', 'Spawner', 'fas fa-car-side']);
    if (can('vehicles.view')) T.push(['world', 'World vehicles', 'fas fa-earth-americas']);
    if (can('vehicles_database.view')) T.push(['owned', 'Owned vehicles', 'fas fa-key']);
    if (can('vehicles.force_wipe')) T.push(['wipe', 'Vehicle wipe', 'fas fa-broom']);
    const t = vehTab(T);
    let body = '';
    if (t === 'spawn') {
      const all = st.models;
      const q = (st.q || '').toLowerCase(); const cls = st.cls ?? '';
      const list = (all || []).filter(m => (cls === '' || String(m.class) === String(cls)) && (!q || `${m.model} ${m.label} ${m.make}`.toLowerCase().includes(q)));
      const sel = st.sel;
      body = `<div class="toolbar"><div class="search"><i class="fas fa-magnifying-glass"></i><input class="inp" data-in="vehQ" value="${esc(st.q || '')}" placeholder="Search model, name or make"></div>
        <select class="sel" style="width:170px" data-ch="vehCls"><option value="">All classes</option>${VCLASS.map((c, i) => `<option value="${i}" ${String(cls) === String(i) ? 'selected' : ''}>${c}</option>`).join('')}</select>
        <span class="muted">${all ? `${list.length} models` : ''}</span></div>
        <div class="bulkbar" style="${sel ? '' : 'opacity:.5'}"><b>${sel ? esc(sel) : 'Pick a vehicle'}</b>
          ${btn('Spawn', 'vehSpawn', 'sm btn-teal', { icon: 'fas fa-plus', disabled: !sel })}${btn('Spawn maxed', 'vehSpawn', 'sm', { v: 'max', icon: 'fas fa-bolt', disabled: !sel })}
          ${btn('Spawn for player', 'vehFor', 'sm', { icon: 'fas fa-user', disabled: !sel })}${can('vehicles.give') ? btn('Give owned', 'vehGive', 'sm', { icon: 'fas fa-key', disabled: !sel }) : ''}
          <span style="flex:1"></span><input class="inp sm" id="veh-model" placeholder="Or type a model" style="width:160px" data-enter="vehTyped">${btn('Spawn', 'vehTyped', 'sm btn-ghost')}</div>
        <div id="veh-grid">${!all ? loading() : list.length ? `<div class="vgrid">${list.slice(0, 160).map(m => `<div class="vcard ${sel === m.model ? 'on' : ''}" data-a="vehPick" data-v="${esc(m.model)}"><div class="img">${imgTag(vehImg(m.model), 'fas fa-car')}</div><div class="tx"><b>${esc(m.label)}</b><span>${esc(m.make ? m.make + ' · ' : '')}${esc(m.model)} · ${VCLASS[m.class] || ''}</span></div></div>`).join('')}</div>${list.length > 160 ? `<p class="muted" style="text-align:center;margin-top:12px">Showing 160 of ${list.length}, search to narrow down</p>` : ''}` : empty('fas fa-car', 'No vehicles match')}</div>`;
    } else if (t === 'world') {
      const rows = st.world;
      body = `<div class="toolbar"><div class="search"><i class="fas fa-magnifying-glass"></i><input class="inp" data-in="vehWQ" value="${esc(st.wq || '')}" placeholder="Search plate, model or driver"></div><span class="muted">${rows ? rows.length + ' vehicles' : ''}</span>${btn('Refresh', 'vehWorldLoad', 'btn-ghost sm', { icon: 'fas fa-rotate' })}</div>
        <div class="tbl-wrap">${!rows ? loading() : rows.length ? `<table class="tbl"><thead><tr><th>Vehicle</th><th>Plate</th><th>Occupants</th><th class="num">Engine</th><th class="num">Body</th><th class="num">Distance</th><th></th></tr></thead><tbody>${rows.filter(v => { const q = (st.wq || '').toLowerCase(); return !q || `${v.plate} ${v.model} ${v.label} ${(v.occupants || []).map(o => o.name).join(' ')}`.toLowerCase().includes(q); }).slice(0, 200).map(v => `<tr>
          <td><div class="cell"><div class="av sm"><i class="fas fa-car"></i></div><div class="tx"><b>${esc(v.label && v.label !== 'NULL' ? v.label : v.model || v.hash)}</b><span>${esc(v.model || '')}${v.locked ? ' · locked' : ''}</span></div></div></td>
          <td class="mono">${esc(v.plate)}</td><td>${(v.occupants || []).length ? v.occupants.map(o => chip(`${o.name} (${o.id})`, o.seat === -1 ? 'teal' : '')).join(' ') : '<span class="muted">Empty</span>'}</td>
          <td class="num ${v.engine < 400 ? 'tred' : ''}">${v.engine}</td><td class="num">${v.body}</td><td class="num">${num(v.dist)}m</td>
          <td class="tact"><div class="row-btns" style="flex-wrap:nowrap">${can('self.teleport') ? btn('', 'vehW', 'xs', { v: 'goto:' + v.net, icon: 'fas fa-location-arrow', title: 'Go to' }) : ''}${can('vehicles.repair') ? btn('', 'vehW', 'xs', { v: 'repair:' + v.net, icon: 'fas fa-wrench', title: 'Repair' }) : ''}${can('vehicles.unlock_doors') ? btn('', 'vehW', 'xs', { v: 'unlock:' + v.net, icon: 'fas fa-lock-open', title: 'Unlock' }) : ''}${can('vehicles.give_key') ? btn('', 'vehW', 'xs', { v: 'keys:' + v.net, icon: 'fas fa-key', title: 'Keys' }) : ''}${can('vehicles.set_plate') ? btn('', 'vehW', 'xs', { v: 'plate:' + v.net, icon: 'fas fa-rectangle-list', title: 'Plate' }) : ''}${can('vehicles.despawn') ? btn('', 'vehW', 'xs btn-red', { v: 'despawn:' + v.net, icon: 'fas fa-trash', title: 'Despawn' }) : ''}</div></td></tr>`).join('')}</tbody></table>` : empty('fas fa-car', 'No vehicles spawned')}</div>`;
    } else if (t === 'owned') {
      const rows = st.owned;
      body = `<div class="toolbar"><div class="search"><i class="fas fa-magnifying-glass"></i><input class="inp" id="own-q" data-enter="vehOwnLoad" value="${esc(st.oq || '')}" placeholder="Search plate, owner or model, press Enter"></div>${btn('Search', 'vehOwnLoad', 'btn-teal', { icon: 'fas fa-magnifying-glass' })}</div>
        <div class="tbl-wrap">${!rows ? empty('fas fa-key', 'Search owned vehicles', 'Look up any vehicle in the garage table.') : rows.length ? `<table class="tbl"><thead><tr><th>Plate</th><th>Model</th><th>Owner</th><th>Garage</th><th>Stored</th><th></th></tr></thead><tbody>${rows.map((v, i) => `<tr><td class="mono"><b>${esc(v.plate)}</b></td><td>${esc(v.model || v.hash || '-')}</td><td><div class="tx"><b>${esc(v.owner_name || '-')}</b><div class="mono muted">${esc(v.owner)}</div></div></td><td>${esc(v.garage || '-')}</td><td>${v.stored == 1 || v.stored === true ? chip('Stored', 'teal') : chip('Out', 'amber')}</td>
          <td class="tact"><div class="row-btns" style="flex-wrap:nowrap">${can('vehicles.set_owner') ? btn('', 'vehO', 'xs', { v: 'owner:' + i, icon: 'fas fa-user-pen', title: 'Transfer owner' }) : ''}${can('vehicles.set_plate') ? btn('', 'vehO', 'xs', { v: 'plate:' + i, icon: 'fas fa-rectangle-list', title: 'Change plate' }) : ''}${can('vehicles.send_to_garage') ? btn('', 'vehO', 'xs', { v: 'garage:' + i, icon: 'fas fa-warehouse', title: 'Send to garage' }) : ''}${can('vehicles.remove') ? btn('', 'vehO', 'xs btn-red', { v: 'delete:' + i, icon: 'fas fa-trash', title: 'Delete' }) : ''}</div></td></tr>`).join('')}</tbody></table>` : empty('fas fa-key', 'Nothing found')}</div>`;
    } else if (t === 'wipe') {
      body = `<div class="card" style="max-width:560px"><div class="card-h"><h3><i class="fas fa-broom"></i>Vehicle wipe</h3></div><div class="card-b" style="display:grid;gap:12px">
        <p class="ink2" style="line-height:1.6">Removes spawned vehicles from the world. Players get a countdown announcement first. Occupied vehicles and vehicles that are in the owned vehicles table are skipped when those options are on in the config.</p>
        <div class="kv"><div><label>Warnings at</label><span>${esc((S.boot.wipe || [60, 30, 10]).join('s, '))}s</span></div><div><label>World vehicles now</label><span>${st.world ? st.world.length : '-'}</span></div></div>
        ${btn('Start vehicle wipe', 'vehWipe', 'btn-solid-red', { icon: 'fas fa-broom' })}</div></div>`;
    }
    return ph('Vehicles', 'Spawn, manage and clean up vehicles') + tabs(T, t, 'vehTabGo') + `<div class="content" style="padding-top:14px">${body}</div>`;
  },
});
function vehTab(T) { T = T || [['spawn'], ['world'], ['owned'], ['wipe']].filter(x => can({ spawn: 'vehicles.spawn', world: 'vehicles.view', owned: 'vehicles_database.view', wipe: 'vehicles.force_wipe' }[x[0]])); return S.tab.vehicles && T.some(x => x[0] === S.tab.vehicles) ? S.tab.vehicles : (T[0] || ['spawn'])[0]; }
async function loadVehTab() {
  const st = pd('vehicles'); const t = vehTab();
  if (t === 'spawn' && !st.models) { st.models = await loc('vehicleModels') || []; }
  if ((t === 'world' || t === 'wipe') && can('vehicles.view')) { const r = await rpc('vehicles:world'); if (r.ok) st.world = r.data; }
  if (S.page === 'vehicles') rerender();
}
A.vehTabGo = v => { S.tab.vehicles = v; rerender(); loadVehTab(); };
IN.vehQ = debounce(v => { pd('vehicles').q = v; const tmp = document.createElement('div'); tmp.innerHTML = PAGES.vehicles.render(); $('#veh-grid').replaceWith(tmp.querySelector('#veh-grid')); }, 150);
IN.vehWQ = debounce(v => { pd('vehicles').wq = v; rerender(); const i = $('[data-in="vehWQ"]'); if (i) { i.focus(); i.setSelectionRange(v.length, v.length); } }, 250);
A.vehCls = v => { pd('vehicles').cls = v; rerender(); };
A.vehPick = v => { pd('vehicles').sel = v; rerender(); };
A.vehSpawn = async v => { const m = pd('vehicles').sel; if (await call('vehicles:spawn', { model: m, maxed: v === 'max' })) { toast(`Spawned ${m}`, 'success'); A.close(); } };
A.vehTyped = async () => { const m = ($('#veh-model').value || '').trim(); if (!m) return; if (await call('vehicles:spawn', { model: m })) { toast(`Spawned ${m}`, 'success'); A.close(); } };
A.vehFor = async () => { const m = pd('vehicles').sel; const f = await form({ title: `Spawn ${m} for a player`, icon: 'fas fa-car', fields: [{ name: 'id', label: 'Player ID', type: 'number' }, { name: 'maxed', label: 'Max upgrades', type: 'check' }] }); if (f) call('vehicles:spawn', { id: +f.id, model: m, maxed: f.maxed }, 'Vehicle spawned'); };
A.vehGive = async () => { const m = pd('vehicles').sel; const f = await form({ title: `Give ${m} as owned`, sub: 'Saved to the player\u2019s garage.', icon: 'fas fa-key', fields: [{ name: 'id', label: 'Player ID', type: 'number', placeholder: 'Blank = you' }, { name: 'plate', label: 'Plate', placeholder: 'Random', max: 8 }, { name: 'maxed', label: 'Max upgrades', type: 'check' }, { name: 'spawn', label: 'Spawn it now', type: 'check', value: true }] }); if (!f) return; const r = await call('vehicles:give', { id: f.id ? +f.id : undefined, model: m, plate: f.plate, maxed: f.maxed, spawn: f.spawn }); if (r) toast(`Given with plate ${r}`, 'success'); };
A.vehWorldLoad = async () => { const st = pd('vehicles'); st.world = null; rerender(); loadVehTab(); };
A.vehW = async v => {
  const [action, net] = v.split(':'); const d = { net: +net, action };
  if (action === 'despawn' && !await confirmBox('Despawn this vehicle?', 'Anyone inside is ejected first.')) return;
  if (action === 'plate') { const f = await form({ title: 'Set plate', icon: 'fas fa-rectangle-list', cols: 1, fields: [{ name: 'plate', label: 'Plate', max: 8 }] }); if (!f) return; d.plate = f.plate.toUpperCase(); }
  if (action === 'keys') { const f = await form({ title: 'Give keys', icon: 'fas fa-key', cols: 1, fields: [{ name: 'to', label: 'Player ID', type: 'number', placeholder: 'Blank = you' }] }); if (!f) return; if (f.to) d.to = +f.to; }
  if (await call('vehicles:world:action', d, 'Done')) { if (action === 'goto') return A.close(); A.vehWorldLoad(); }
};
A.vehOwnLoad = async () => { const st = pd('vehicles'); const i = $('#own-q'); st.oq = i ? i.value : st.oq; const r = await call('vehicles:db', { search: st.oq || '' }); if (r) { st.owned = r; rerender(); } };
A.vehO = async v => {
  const [action, i] = v.split(':'); const row = pd('vehicles').owned[+i]; const d = { plate: row.plate, action };
  if (action === 'owner') { const f = await form({ title: 'Transfer owner', sub: `Plate ${row.plate}`, icon: 'fas fa-user-pen', cols: 1, fields: [{ name: 'owner', label: 'Online player ID or character identifier' }] }); if (!f) return; d.owner = f.owner; }
  else if (action === 'plate') { const f = await form({ title: 'Change plate', icon: 'fas fa-rectangle-list', cols: 1, fields: [{ name: 'newPlate', label: 'New plate', max: 8, value: row.plate }] }); if (!f) return; d.newPlate = f.newPlate; }
  else if (action === 'delete' && !await confirmBox(`Delete ${row.plate}?`, 'The vehicle is removed from the owner for good.')) return;
  if (await call('vehicles:db:action', d, 'Saved')) A.vehOwnLoad();
};
A.vehWipe = async () => { if (!await confirmBox('Start a vehicle wipe?', 'Players will be warned with a countdown.', { ok: 'Start wipe' })) return; call('vehicles:wipe', {}, 'Wipe started'); };

/* ═══ ITEMS ═════════════════════════════════════════════════════════════ */
page('items', {
  label: 'Items', icon: 'fas fa-box', perms: ['items_database.view', 'inventory.give'],
  async enter() { const st = pd('items'); if (!st.list) { const r = await rpc('items:list'); if (r.ok) { st.list = r.data.items; rerender(); } } },
  render() {
    const st = pd('items'); const q = (st.q || '').toLowerCase();
    const list = (st.list || []).filter(i => !q || `${i.name} ${i.label}`.toLowerCase().includes(q));
    const sel = st.sel && (st.list || []).find(i => i.name === st.sel);
    const left = `<div class="pane-r" style="padding:14px 18px;overflow:hidden"><div class="toolbar"><div class="search"><i class="fas fa-magnifying-glass"></i><input class="inp" data-in="itemQ" value="${esc(st.q || '')}" placeholder="Search items"></div><span class="muted">${st.list ? list.length + ' items' : ''}</span></div>
      <div id="item-grid" class="scroll-y" style="flex:1;min-height:0">${!st.list ? loading() : list.length ? `<div class="inv">${list.slice(0, 300).map(i => `<div class="slot ${st.sel === i.name ? 'act on' : ''}" style="${st.sel === i.name ? 'border-color:var(--teal)' : ''}" data-a="itemPick" data-v="${esc(i.name)}" title="${esc(i.name)}">${itemImg(i.name) ? `<img src="${esc(itemImg(i.name))}" loading="lazy" onerror="this.outerHTML='<div class=\\'ph-i\\'><i class=\\'fas fa-box\\'></i></div>'">` : '<div class="ph-i"><i class="fas fa-box"></i></div>'}<b>${esc(i.label)}</b></div>`).join('')}</div>` : empty('fas fa-box', 'No items match')}</div></div>`;
    const right = `<div class="pane-l" style="border-right:0;border-left:1px solid var(--line-soft);width:320px">${sel ? `<div class="pane-h" style="justify-items:center;text-align:center;padding:20px">
        <div class="slot" style="width:110px;cursor:default">${imgTag(itemImg(sel.name), 'fas fa-box')}</div><b style="font-size:14px;color:var(--white)">${esc(sel.label)}</b><span class="mono muted">${esc(sel.name)}${sel.weight ? ` · ${sel.weight}g` : ''}</span></div>
      <div class="pane-b" style="padding:14px;display:grid;gap:12px;align-content:start">
        ${can('inventory.give') ? `<div class="fgrid"><div class="field"><label>Player ID</label><input class="inp" id="it-id" type="number" placeholder="Blank = you"></div><div class="field"><label>Amount</label><input class="inp" id="it-n" type="number" value="1"></div></div>${btn('Give item', 'itemGive', 'btn-teal full', { icon: 'fas fa-plus' })}` : ''}
        ${can('items_database.view') ? `<div class="sep" style="margin:4px 0"></div><div style="display:flex;align-items:center"><b style="font-size:11.5px;font-weight:500">Who has it online</b><span style="flex:1"></span>${btn('Check', 'itemHolders', 'sm', { icon: 'fas fa-magnifying-glass' })}</div>
          <div>${!st.holders ? '<p class="muted" style="font-size:11px">Counts every online player\u2019s stack.</p>' : st.holders.length ? st.holders.map(h => `<div class="li click" style="padding:8px 4px" data-a="openProfileGo" data-v="${h.id}">${av(h.name, 'sm')}<div class="tx"><b>${esc(h.name)}</b><span>ID ${h.id}${h.char ? ' · ' + esc(h.char) : ''}</span></div><div class="rt"><b class="tteal">x${num(h.count)}</b></div></div>`).join('') : '<p class="muted" style="font-size:11px">Nobody online has this.</p>'}</div>` : ''}
      </div>` : empty('fas fa-hand-pointer', 'Pick an item', 'Give it to anyone or see who is carrying it.')}</div>`;
    return `<div class="content flush"><div class="split">${left}${right}</div></div>`;
  },
});
IN.itemQ = debounce(v => { pd('items').q = v; const tmp = document.createElement('div'); tmp.innerHTML = PAGES.items.render(); $('#item-grid').replaceWith(tmp.querySelector('#item-grid')); }, 150);
A.itemPick = v => { const st = pd('items'); st.sel = v; st.holders = null; rerender(); };
A.itemGive = async () => { const st = pd('items'); const id = $('#it-id').value; const n = Math.max(1, +$('#it-n').value || 1); if (await call('player:item:give', { id: id ? +id : undefined, item: st.sel, count: n })) toast(`Gave ${n}x ${st.sel}`, 'success'); };
A.itemHolders = async () => { const st = pd('items'); const r = await call('items:holders', { item: st.sel }); if (r) { st.holders = r; rerender(); } };

/* ═══ LIVE MAP ══════════════════════════════════════════════════════════ */
const MAP = { img: null, imgOk: false, scale: 1, ox: 0, oy: 0, data: null, heat: false, vehicles: false, sel: null, hover: null, timer: null };
page('map', {
  label: 'Live map', icon: 'fas fa-map-location-dot', perms: ['map.view'],
  enter() { loadMap(); },
  leave() { clearInterval(MAP.timer); MAP.timer = null; },
  render() {
    const sel = MAP.sel && MAP.data && MAP.data.players.find(p => p.id === MAP.sel);
    return `<div class="content flush"><div class="map" id="map"><canvas id="mapc"></canvas>
      <div class="map-ov">${seg([['off', 'Players'], ['on', 'Death heatmap']], MAP.heat ? 'on' : 'off', 'mapHeat')}${can('vehicles.view') ? btn('Vehicles', 'mapVeh', 'sm ' + (MAP.vehicles ? 'active' : ''), { icon: 'fas fa-car' }) : ''}</div>
      <div class="map-ov r">${btn('', 'mapZoom', 'sm', { v: 1, icon: 'fas fa-plus' })}${btn('', 'mapZoom', 'sm', { v: -1, icon: 'fas fa-minus' })}${btn('', 'mapFit', 'sm', { icon: 'fas fa-expand', title: 'Fit' })}</div>
      <div class="map-tip hide" id="map-tip"></div>
      ${sel ? `<div class="card map-card"><div class="card-h">${av(sel.name, 'sm')}<h3 style="margin-left:4px">${esc(sel.name)} <span class="muted" style="font-weight:400">#${sel.id}</span></h3><div class="r">${btn('', 'mapSel', 'xs btn-ghost', { v: '', icon: 'fas fa-xmark' })}</div></div>
        <div class="card-b" style="display:grid;gap:8px"><div class="muted mono">${Math.round(sel.x)}, ${Math.round(sel.y)}, ${Math.round(sel.z)}${sel.bucket ? ` · bucket ${sel.bucket}` : ''}${sel.veh ? ' · in vehicle' : ''}</div>
        <div class="row-btns">${can('player.teleport') ? btn('Go to', 'mapDo', 'sm', { v: 'goto', icon: 'fas fa-location-arrow' }) + btn('Bring', 'mapDo', 'sm', { v: 'bring', icon: 'fas fa-person-arrow-down-to-line' }) : ''}${can('player.spectate') ? btn('Spectate', 'mapDo', 'sm', { v: 'spectate', icon: 'fas fa-eye' }) : ''}${btn('Profile', 'mapDo', 'sm', { v: 'profile', icon: 'fas fa-user' })}</div></div></div>` : ''}
    </div></div>`;
  },
  mounted() { setupMap(); },
});
function mapBounds() { return (S.boot && S.boot.map && S.boot.map.Bounds) || { minX: -4000, maxX: 6000, minY: -4000, maxY: 8000 }; }
function mapSize() { if (MAP.imgOk) return { w: MAP.img.naturalWidth, h: MAP.img.naturalHeight }; const b = mapBounds(); return { w: (b.maxX - b.minX) / 4, h: (b.maxY - b.minY) / 4 }; }
function w2m(x, y) { const b = mapBounds(), s = mapSize(); return { x: (x - b.minX) / (b.maxX - b.minX) * s.w, y: (b.maxY - y) / (b.maxY - b.minY) * s.h }; }
function m2w(u, v) { const b = mapBounds(), s = mapSize(); return { x: b.minX + u / s.w * (b.maxX - b.minX), y: b.maxY - v / s.h * (b.maxY - b.minY) }; }
function s2m(px, py) { return { u: (px - MAP.ox) / MAP.scale, v: (py - MAP.oy) / MAP.scale }; }
async function loadMap() {
  const img = S.boot && S.boot.map && S.boot.map.Image;
  if (img && !MAP.img) { MAP.img = new Image(); MAP.img.onload = () => { MAP.imgOk = true; A.mapFit(); }; MAP.img.src = img; }
  await fetchMap();
  clearInterval(MAP.timer);
  MAP.timer = setInterval(() => { if (S.open && S.page === 'map') fetchMap(); }, Math.max(1000, (S.boot && S.boot.mapRefresh) || 2000));
}
async function fetchMap() {
  const r = await rpc('map:data', { heatmap: MAP.heat, vehicles: MAP.vehicles, days: 7 });
  if (r.ok) { MAP.data = r.data; drawMap(); }
}
function setupMap() {
  const el = $('#map'), c = $('#mapc'); if (!el || !c) return;
  const fit = () => { c.width = el.clientWidth * devicePixelRatio; c.height = el.clientHeight * devicePixelRatio; c.style.width = el.clientWidth + 'px'; c.style.height = el.clientHeight + 'px'; drawMap(); };
  if (!MAP.fitted) { MAP.fitted = true; requestAnimationFrame(() => { A.mapFit(); fit(); }); } else fit();
  let drag = null, moved = false;
  el.onmousedown = e => { if (e.target !== c) return; drag = { x: e.clientX, y: e.clientY, ox: MAP.ox, oy: MAP.oy }; moved = false; el.classList.add('drag'); };
  window.onmouseup = e => { if (!drag) return; el.classList.remove('drag'); if (!moved && e.button === 0) { const hit = mapHit(e); MAP.sel = hit ? hit.id : null; rerender(); } drag = null; };
  el.onmousemove = e => {
    if (drag) { const dx = e.clientX - drag.x, dy = e.clientY - drag.y; if (Math.abs(dx) + Math.abs(dy) > 3) moved = true; MAP.ox = drag.ox + dx; MAP.oy = drag.oy + dy; drawMap(); return; }
    const hit = mapHit(e); const tip = $('#map-tip');
    if (hit && tip) { const r = el.getBoundingClientRect(); tip.classList.remove('hide'); tip.style.left = (e.clientX - r.left) + 'px'; tip.style.top = (e.clientY - r.top) + 'px'; tip.innerHTML = `<b>${esc(hit.name)}</b> <span class="muted">#${hit.id}</span>`; }
    else if (tip) tip.classList.add('hide');
  };
  el.onwheel = e => { e.preventDefault(); const r = el.getBoundingClientRect(); zoomAt(e.clientX - r.left, e.clientY - r.top, e.deltaY < 0 ? 1.2 : 1 / 1.2); };
  el.oncontextmenu = async e => {
    e.preventDefault(); const r = el.getBoundingClientRect(); const m = s2m(e.clientX - r.left, e.clientY - r.top); const w = m2w(m.u, m.v);
    const f = await form({ title: 'Map point', sub: `${Math.round(w.x)}, ${Math.round(w.y)}`, icon: 'fas fa-location-dot', ok: 'Teleport here', fields: [{ name: 'wp', label: 'Only set a waypoint', type: 'check' }] });
    if (!f) return;
    if (f.wp) { await loc('waypoint', { x: w.x, y: w.y }); toast('Waypoint set', 'success'); } else { await loc('tpCoords', { x: w.x, y: w.y }); A.close(); }
  };
  window.onresize = () => { if ($('#mapc')) fit(); };
}
function zoomAt(px, py, f) { const ns = Math.min(8, Math.max(0.05, MAP.scale * f)); MAP.ox = px - (px - MAP.ox) * (ns / MAP.scale); MAP.oy = py - (py - MAP.oy) * (ns / MAP.scale); MAP.scale = ns; drawMap(); }
function mapHit(e) {
  if (!MAP.data) return null; const el = $('#map'); const r = el.getBoundingClientRect(); const px = e.clientX - r.left, py = e.clientY - r.top;
  let best = null, bd = 12;
  MAP.data.players.forEach(p => { const m = w2m(p.x, p.y); const sx = m.x * MAP.scale + MAP.ox, sy = m.y * MAP.scale + MAP.oy; const d = Math.hypot(sx - px, sy - py); if (d < bd) { bd = d; best = p; } });
  return best;
}
function drawMap() {
  const c = $('#mapc'); if (!c) return; const g = c.getContext('2d'); const dpr = devicePixelRatio;
  g.setTransform(1, 0, 0, 1, 0, 0); g.clearRect(0, 0, c.width, c.height); g.scale(dpr, dpr);
  g.save(); g.translate(MAP.ox, MAP.oy); g.scale(MAP.scale, MAP.scale);
  const s = mapSize();
  if (MAP.imgOk) g.drawImage(MAP.img, 0, 0);
  else {
    g.fillStyle = '#0d181c'; g.fillRect(0, 0, s.w, s.h);
    g.strokeStyle = 'rgba(8,175,162,.08)'; g.lineWidth = 1 / MAP.scale;
    const b = mapBounds();
    for (let x = Math.ceil(b.minX / 500) * 500; x <= b.maxX; x += 500) { const m = w2m(x, 0); g.beginPath(); g.moveTo(m.x, 0); g.lineTo(m.x, s.h); g.stroke(); }
    for (let y = Math.ceil(b.minY / 500) * 500; y <= b.maxY; y += 500) { const m = w2m(0, y); g.beginPath(); g.moveTo(0, m.y); g.lineTo(s.w, m.y); g.stroke(); }
    g.fillStyle = 'rgba(158,165,170,.35)'; g.font = `${12 / MAP.scale}px Lexend`; g.fillText('Add a map image in Config.Map.Image', 20 / MAP.scale, 30 / MAP.scale);
  }
  const d = MAP.data;
  if (d && MAP.heat && d.deaths) {
    d.deaths.forEach(p => { const m = w2m(p.x, p.y); const rad = 26 / Math.sqrt(MAP.scale); const gr = g.createRadialGradient(m.x, m.y, 0, m.x, m.y, rad); gr.addColorStop(0, 'rgba(229,72,77,.35)'); gr.addColorStop(1, 'rgba(229,72,77,0)'); g.fillStyle = gr; g.beginPath(); g.arc(m.x, m.y, rad, 0, 7); g.fill(); });
  }
  if (d && d.vehicles && MAP.vehicles) {
    g.fillStyle = 'rgba(158,165,170,.7)';
    d.vehicles.forEach(v => { const m = w2m(v.x, v.y); const r = 2.2 / MAP.scale; g.fillRect(m.x - r, m.y - r, r * 2, r * 2); });
  }
  if (d) d.players.forEach(p => {
    const m = w2m(p.x, p.y); const r = (p.id === MAP.sel ? 7 : 5) / MAP.scale;
    g.fillStyle = p.dead ? '#e5484d' : (p.staff || '#08afa2');
    g.strokeStyle = '#000'; g.lineWidth = 2 / MAP.scale;
    g.beginPath(); g.arc(m.x, m.y, r, 0, 7); g.fill(); g.stroke();
    if (MAP.scale > 0.35 || p.id === MAP.sel) { g.fillStyle = '#fff'; g.font = `500 ${10.5 / MAP.scale}px Lexend`; g.fillText(`${p.name} #${p.id}`, m.x + r + 3 / MAP.scale, m.y + 3.5 / MAP.scale); }
  });
  g.restore();
}
A.mapFit = () => { const el = $('#map'); if (!el) return; const s = mapSize(); MAP.scale = Math.min(el.clientWidth / s.w, el.clientHeight / s.h) * 0.95; MAP.ox = (el.clientWidth - s.w * MAP.scale) / 2; MAP.oy = (el.clientHeight - s.h * MAP.scale) / 2; drawMap(); };
A.mapZoom = v => { const el = $('#map'); zoomAt(el.clientWidth / 2, el.clientHeight / 2, +v > 0 ? 1.4 : 1 / 1.4); };
A.mapHeat = v => { MAP.heat = v === 'on'; rerender(); fetchMap(); };
A.mapVeh = () => { MAP.vehicles = !MAP.vehicles; rerender(); fetchMap(); };
A.mapSel = () => { MAP.sel = null; rerender(); };
A.mapDo = async v => { const id = MAP.sel; if (v === 'goto') { if (await call('player:goto', { id })) A.close(); } else if (v === 'bring') call('player:bring', { id }, 'Player brought'); else if (v === 'spectate') { if (await call('player:spectate', { id })) hideUI(); } else if (v === 'profile') { go('players'); openProfile(id); } };

/* ═══ WORLD ═════════════════════════════════════════════════════════════ */
const WEATHER_ICON = { EXTRASUNNY: 'fas fa-sun', CLEAR: 'fas fa-cloud-sun', NEUTRAL: 'fas fa-cloud-sun', SMOG: 'fas fa-smog', FOGGY: 'fas fa-smog', OVERCAST: 'fas fa-cloud', CLOUDS: 'fas fa-cloud', CLEARING: 'fas fa-cloud-sun-rain', RAIN: 'fas fa-cloud-rain', THUNDER: 'fas fa-cloud-bolt', SNOW: 'fas fa-snowflake', BLIZZARD: 'fas fa-wind', SNOWLIGHT: 'fas fa-snowflake', XMAS: 'fas fa-snowman', HALLOWEEN: 'fas fa-ghost' };
page('world', {
  label: 'World', icon: 'fas fa-earth-americas', perms: ['weather.change', 'announcements.create', 'blips.create', 'props.view', 'zones.view', 'events.view', 'self.manage_time'],
  async enter(extra) {
    if (extra && extra.tab) S.tab.world = extra.tab;
    if (extra && extra.zonePoints && extra.zoneDraft) { const d = Object.assign({}, extra.zoneDraft, { points: extra.zonePoints }); const r = await call('zones:save', d, 'Zone saved'); if (r) pd('world').zones = r; }
    await loadWorld();
  },
  render() {
    const st = pd('world');
    const T = [];
    if (canAny('weather.change', 'self.manage_time')) T.push(['weather', 'Weather and time', 'fas fa-cloud-sun']);
    if (can('announcements.create')) T.push(['announce', 'Announcements', 'fas fa-bullhorn']);
    if (can('blips.create')) T.push(['blips', 'Blips', 'fas fa-location-dot']);
    if (can('props.view')) T.push(['props', 'Props', 'fas fa-cubes']);
    if (can('zones.view')) T.push(['zones', 'Zones', 'fas fa-draw-polygon']);
    if (can('events.view')) T.push(['events', 'Events', 'fas fa-calendar']);
    const t = worldTab(T);
    let body = '';
    if (t === 'weather') {
      const w = st.weather; const s = st.draft || (w && w.state) || { weather: 'CLEAR', hour: 12, minute: 0 };
      const types = (w && w.types) || S.boot.weatherTypes || [];
      body = `<div class="g-dash"><div class="card"><div class="card-h"><h3><i class="fas fa-cloud-sun"></i>Server weather</h3><div class="r">${w ? chip(w.mode === 'builtin' ? 'Built-in sync' : w.mode, 'teal') : ''}</div></div><div class="card-b" style="display:grid;gap:14px">
          <div class="acts" style="grid-template-columns:repeat(5,1fr)">${types.map(x => `<button class="act ${s.weather === x ? 'on' : ''}" data-a="wxPick" data-v="${x}"><i class="${WEATHER_ICON[x] || 'fas fa-cloud'}"></i>${esc(x.charAt(0) + x.slice(1).toLowerCase())}</button>`).join('')}</div>
          <div class="field"><label>Time <small id="wx-time">${String(s.hour).padStart(2, '0')}:${String(s.minute).padStart(2, '0')}</small></label><input type="range" min="0" max="1439" step="5" value="${s.hour * 60 + s.minute}" data-in="wxTime"></div>
          <div class="row-btns">${[['Dawn', 6], ['Noon', 12], ['Dusk', 19], ['Midnight', 0]].map(([l, h]) => `<span class="chip btnish" data-a="wxHour" data-v="${h}">${l}</span>`).join('')}</div>
          <div style="display:flex;gap:18px;align-items:center"><label class="chk" data-a="wxFlag" data-v="freeze">${swv(s.freeze)}Freeze time</label><label class="chk" data-a="wxFlag" data-v="blackout">${swv(s.blackout)}Blackout</label><span style="flex:1"></span>
          ${can('weather.change') ? btn('Apply to server', 'wxApply', 'btn-teal', { icon: 'fas fa-check' }) : ''}</div></div></div>
        <div class="card"><div class="card-h"><h3><i class="fas fa-user-clock"></i>Just for me</h3></div><div class="card-b" style="display:grid;gap:12px">
          <p class="ink2" style="font-size:11.5px;line-height:1.6">Override weather and time on your own screen only. Handy for screenshots and checking lighting.</p>
          ${can('self.manage_time') ? `${btn('Use these settings locally', 'wxLocal', 'full', { icon: 'fas fa-eye' })}${btn('Back to server weather', 'wxLocalOff', 'btn-ghost full', { icon: 'fas fa-rotate-left' })}` : ''}
          ${can('self.blackout') ? `<label class="chk" data-a="toggleSelfA" data-v="blackout">${swv(S.toggles.blackout)}Local blackout</label>` : ''}</div></div></div>`;
    } else if (t === 'announce') {
      const a = st.ann || { title: 'Announcement', message: '', kind: 'info', seconds: 10, delay: 0 };
      body = `<div class="g2"><div class="card"><div class="card-h"><h3><i class="fas fa-bullhorn"></i>New announcement</h3></div><div class="card-b"><div class="fgrid">
          <div class="field span"><label>Title</label><input class="inp" id="an-title" value="${esc(a.title)}" maxlength="60" data-in="annPrev"></div>
          <div class="field span"><label>Message</label><textarea class="txt" id="an-msg" maxlength="500" data-in="annPrev" placeholder="What everyone should know">${esc(a.message)}</textarea></div>
          <div class="field"><label>Style</label><select class="sel" id="an-kind" data-ch="annPrevC">${[['info', 'Info'], ['success', 'Good news'], ['warning', 'Warning'], ['error', 'Urgent']].map(([k, l]) => `<option value="${k}" ${a.kind === k ? 'selected' : ''}>${l}</option>`).join('')}</select></div>
          <div class="field"><label>Show for <small>seconds</small></label><input class="inp" id="an-sec" type="number" value="${a.seconds}" min="3" max="60"></div>
          <div class="field"><label>Delay <small>minutes, 0 = now</small></label><input class="inp" id="an-delay" type="number" value="${a.delay}" min="0"></div>
          <div class="field"><label>&nbsp;</label><label class="chk" style="height:32px"><input type="checkbox" id="an-anon"><span class="box"></span>Hide my name</label></div>
          <div class="span">${btn('Send announcement', 'annSend', 'btn-teal full', { icon: 'fas fa-paper-plane' })}</div></div></div></div>
        <div class="card"><div class="card-h"><h3><i class="fas fa-eye"></i>Preview</h3></div><div class="card-b" id="ann-prev" style="min-height:160px;display:grid;place-items:center">${annPreview()}</div></div></div>`;
    } else if (t === 'blips') {
      const list = st.blips;
      body = `<div class="toolbar">${btn('New blip', 'blipEdit', 'btn-teal sm', { icon: 'fas fa-plus' })}<span class="sp"></span><span class="muted">${list ? list.length + ' blips' : ''}</span></div>
        <div class="tbl-wrap">${!list ? loading() : list.length ? `<table class="tbl"><thead><tr><th>Label</th><th>Category</th><th class="num">Sprite</th><th class="num">Colour</th><th>Coords</th><th></th></tr></thead><tbody>${list.map((b, i) => `<tr><td><b>${esc(b.label)}</b></td><td>${esc(b.category || '-')}</td><td class="num">${b.sprite}</td><td class="num">${b.color}</td><td class="mono">${Math.round(b.x)}, ${Math.round(b.y)}, ${Math.round(b.z)}</td>
          <td class="tact"><div class="row-btns" style="flex-wrap:nowrap">${btn('', 'gotoXYZ', 'xs', { v: `${b.x},${b.y},${b.z}`, icon: 'fas fa-location-arrow', title: 'Go to' })}${btn('', 'blipEdit', 'xs', { v: i, icon: 'fas fa-pen' })}${can('blips.delete') ? btn('', 'blipDel', 'xs btn-red', { v: b.id, icon: 'fas fa-trash' }) : ''}</div></td></tr>`).join('')}</tbody></table>` : empty('fas fa-location-dot', 'No blips yet', 'Blips you add here show on everyone\u2019s map.')}</div>`;
    } else if (t === 'props') {
      const list = st.props;
      body = `<div class="toolbar">${can('props.create') ? btn('Place prop', 'propNew', 'btn-teal sm', { icon: 'fas fa-plus' }) : ''}<span class="sp"></span><span class="muted">${list ? list.length + ' placed · ' : ''}streamed within ${Math.round(S.boot.propDistance || 150)}m</span></div>
        <div class="tbl-wrap">${!list ? loading() : list.length ? `<table class="tbl"><thead><tr><th>Name</th><th>Type</th><th>Model</th><th>Coords</th><th>Flags</th><th></th></tr></thead><tbody>${list.map(p => `<tr><td><b>${esc(p.name)}</b></td><td>${chip(p.type, p.type === 'ped' ? 'blue' : p.type === 'vehicle' ? 'amber' : '')}</td><td class="mono">${esc(p.model)}</td><td class="mono">${Math.round(p.x)}, ${Math.round(p.y)}, ${Math.round(p.z)}</td><td>${p.frozen ? chip('Frozen') : ''} ${p.collision ? '' : chip('No collision')}</td>
          <td class="tact"><div class="row-btns" style="flex-wrap:nowrap">${btn('', 'gotoXYZ', 'xs', { v: `${p.x},${p.y},${p.z}`, icon: 'fas fa-location-arrow', title: 'Go to' })}${can('props.delete') ? btn('', 'propDel', 'xs btn-red', { v: p.id, icon: 'fas fa-trash' }) : ''}</div></td></tr>`).join('')}</tbody></table>` : empty('fas fa-cubes', 'No props placed', 'Place objects, peds and vehicles that stay after restarts.')}</div>`;
    } else if (t === 'zones') {
      const z = st.zones;
      body = `<div class="toolbar">${can('zones.create') ? btn('New zone', 'zoneNew', 'btn-teal sm', { icon: 'fas fa-plus' }) : ''}<span class="sp"></span><span class="muted">Behaviours live in config/zones.lua</span></div>
        <div class="tbl-wrap">${!z ? loading() : z.zones.length ? `<table class="tbl"><thead><tr><th>Name</th><th>Behaviour</th><th class="num">Points</th><th class="num">Height</th><th>Debug</th><th></th></tr></thead><tbody>${z.zones.map((x, i) => `<tr><td><div class="cell"><i class="dotc" style="background:${esc(x.color)}"></i><b>${esc(x.name)}</b></div></td><td>${esc((z.handlers.find(h => h.id === x.handler) || {}).label || x.handler || 'None')}</td><td class="num">${(x.points || []).length}</td><td class="num">${x.thickness}m</td><td>${x.debug ? chip('On', 'teal') : '<span class="muted">Off</span>'}</td>
          <td class="tact"><div class="row-btns" style="flex-wrap:nowrap">${x.points && x.points[0] ? btn('', 'gotoXYZ', 'xs', { v: `${x.points[0].x},${x.points[0].y},${x.points[0].z}`, icon: 'fas fa-location-arrow', title: 'Go to' }) : ''}${can('zones.create') ? btn('', 'zoneEdit', 'xs', { v: i, icon: 'fas fa-pen' }) : ''}${can('zones.delete') ? btn('', 'zoneDel', 'xs btn-red', { v: x.id, icon: 'fas fa-trash' }) : ''}</div></td></tr>`).join('')}</tbody></table>` : empty('fas fa-draw-polygon', 'No zones yet', 'Draw polygon zones in the world and attach a behaviour.')}</div>`;
    } else if (t === 'events') body = calendarHtml();
    return ph('World', 'Weather, announcements and things placed in the world') + tabs(T, t, 'worldTabGo') + `<div class="content" style="padding-top:14px">${body}</div>`;
  },
});
function worldTab(T) { const keys = T ? T.map(x => x[0]) : ['weather', 'announce', 'blips', 'props', 'zones', 'events']; return keys.includes(S.tab.world) ? S.tab.world : keys[0]; }
function worldTabs() {
  return [['weather', canAny('weather.change', 'self.manage_time')], ['announce', can('announcements.create')], ['blips', can('blips.create')],
    ['props', can('props.view')], ['zones', can('zones.view')], ['events', can('events.view')]].filter(x => x[1]).map(x => [x[0]]);
}
async function loadWorld() {
  const st = pd('world'); const t = worldTab(worldTabs());
  const map = { weather: ['weather:get', 'weather'], blips: ['blips:list', 'blips'], props: ['props:list', 'props'], zones: ['zones:list', 'zones'] };
  if (map[t]) { const r = await rpc(map[t][0]); if (r.ok) { st[map[t][1]] = r.data; if (t === 'weather') st.draft = null; } }
  if (t === 'events') await loadEvents();
  if (S.page === 'world') rerender();
}
A.worldTabGo = v => { S.tab.world = v; rerender(); loadWorld(); };
A.noop = () => {};
function wxDraft() { const st = pd('world'); st.draft = st.draft || Object.assign({ weather: 'CLEAR', hour: 12, minute: 0 }, st.weather && st.weather.state); return st.draft; }
A.wxPick = v => { wxDraft().weather = v; rerender(); };
IN.wxTime = v => { const d = wxDraft(); d.hour = Math.floor(v / 60); d.minute = v % 60; $('#wx-time').textContent = `${String(d.hour).padStart(2, '0')}:${String(d.minute).padStart(2, '0')}`; d.timeChanged = true; };
A.wxHour = v => { const d = wxDraft(); d.hour = +v; d.minute = 0; d.timeChanged = true; rerender(); };
A.wxFlag = v => { const d = wxDraft(); d[v] = !d[v]; d[v + 'Changed'] = true; rerender(); };
A.wxApply = async () => {
  const d = wxDraft(); const body = { weather: d.weather };
  if (d.timeChanged) { body.hour = d.hour; body.minute = d.minute; }
  if (d.freezeChanged) body.freeze = !!d.freeze;
  if (d.blackoutChanged) body.blackout = !!d.blackout;
  const r = await call('weather:set', body, 'Weather updated');
  if (r) { const st = pd('world'); st.weather.state = r; st.draft = null; rerender(); }
};
A.wxLocal = async () => { const d = wxDraft(); if (await loc('localTime', { hour: d.hour, minute: d.minute, weather: d.weather })) toast('Local override on', 'success'); };
A.wxLocalOff = async () => { await loc('toggle', { key: 'localtime', state: false }); toast('Back to server weather', 'success'); };
function annPreview() {
  const t = ($('#an-title') || {}).value ?? (pd('world').ann || {}).title ?? 'Announcement';
  const m = ($('#an-msg') || {}).value ?? '';
  const k = ($('#an-kind') || {}).value || 'info';
  const icon = { info: 'fas fa-bullhorn', success: 'fas fa-circle-check', warning: 'fas fa-triangle-exclamation', error: 'fas fa-circle-exclamation' }[k];
  return `<div class="frame ann ${k}" style="position:static;transform:none;width:100%;animation:none"><div class="shell"><div class="ann-b"><div class="ic"><i class="${icon}"></i></div><div><h4>${esc(t || 'Announcement')}</h4><p>${esc(m || 'Your message shows here.')}</p><small>${esc(S.me.name || 'Staff')}</small></div></div></div></div>`;
}
IN.annPrev = () => { const p = $('#ann-prev'); if (p) p.innerHTML = annPreview(); };
A.annPrevC = IN.annPrev;
A.annSend = async () => {
  const d = { title: $('#an-title').value, message: $('#an-msg').value, kind: $('#an-kind').value, seconds: +$('#an-sec').value, delay: +$('#an-delay').value, anonymous: $('#an-anon').checked };
  if (!d.message.trim()) return toast('Write a message first', 'error');
  if (!await confirmBox('Send to everyone?', d.delay > 0 ? `It goes out in ${d.delay} minute${d.delay === 1 ? '' : 's'}.` : 'Every player sees it right away.', { tone: '', icon: 'fas fa-bullhorn', okClass: 'btn-teal', ok: 'Send' })) return;
  const r = await call('announce', d);
  if (r) { toast(r === 'scheduled' ? 'Announcement scheduled' : 'Announcement sent', 'success'); $('#an-msg').value = ''; IN.annPrev(); }
};
A.gotoXYZ = async v => { const [x, y, z] = v.split(',').map(Number); if (await loc('gotoCoords', { x, y, z })) A.close(); };
A.toggleSelfA = v => toggleSelf(v).then(rerender);
A.blipEdit = async v => {
  const b = v !== undefined ? pd('world').blips[+v] : null;
  const f = await form({ title: b ? 'Edit blip' : 'New blip', sub: b ? '' : 'It is placed where you stand unless you enter coords.', icon: 'fas fa-location-dot', fields: [
    { name: 'label', label: 'Label', value: b ? b.label : '', span: true, max: 60 },
    { name: 'sprite', label: 'Sprite', type: 'number', value: b ? b.sprite : 1, hint: 'docs.fivem.net/docs/game-references/blips' }, { name: 'color', label: 'Colour', type: 'number', value: b ? b.color : 0 },
    { name: 'scale', label: 'Scale', type: 'number', step: '0.1', value: b ? b.scale : 0.8 }, { name: 'display', label: 'Display', type: 'select', value: b ? b.display : 4, options: [[4, 'Map and minimap'], [3, 'Map only'], [5, 'Minimap only'], [2, 'Everywhere']] },
    { name: 'category', label: 'Group name', value: b ? b.category : '', placeholder: 'Blank = its own entry' }, { name: 'coords', label: 'Coords', value: b ? `${b.x}, ${b.y}, ${b.z}` : '', placeholder: 'Blank = my position' },
    { name: 'short_range', label: 'Only show when close', type: 'check', value: b ? !!b.short_range : true, span: true }] });
  if (!f) return;
  const d = Object.assign({}, f, { id: b ? b.id : undefined });
  if (f.coords) { const [x, y, z] = f.coords.replace(/vec(tor)?[34]?\(|\)/g, '').split(/[\s,]+/).filter(Boolean).map(Number); if (isNaN(x) || isNaN(y)) return toast('Coords must be x, y, z', 'error'); d.coords = { x, y, z: isNaN(z) ? 0 : z }; } else delete d.coords;
  const r = await call('blips:save', d, 'Blip saved'); if (r) { pd('world').blips = r; rerender(); }
};
A.blipDel = async v => { if (!await confirmBox('Delete blip?', 'It disappears for everyone.')) return; const r = await call('blips:delete', { id: +v }); if (r) { pd('world').blips = r; rerender(); } };
A.propNew = async () => {
  const f = await form({ title: 'Place a prop', sub: 'You place it in the world with your mouse after this.', icon: 'fas fa-cubes', fields: [
    { name: 'type', label: 'Type', type: 'select', options: [['object', 'Object'], ['ped', 'Ped'], ['vehicle', 'Vehicle']] }, { name: 'model', label: 'Model', placeholder: 'prop_bench_01a' },
    { name: 'name', label: 'Name', placeholder: 'Optional', span: true }, { name: 'anim', label: 'Ped animation', placeholder: 'WORLD_HUMAN_SMOKING or dict@@anim', span: true },
    { name: 'frozen', label: 'Frozen', type: 'check', value: true }, { name: 'collision', label: 'Collision', type: 'check', value: true }] });
  if (!f || !f.model) return;
  if (await loc('placeProp', f)) hideUI();
};
A.propDel = async v => { if (!await confirmBox('Delete prop?', 'It is removed for everyone.')) return; const r = await call('props:delete', { id: +v }, 'Deleted'); if (r) { pd('world').props = r; rerender(); } };
async function zoneForm(z) {
  const handlers = (pd('world').zones || {}).handlers || [];
  return form({ title: z ? 'Edit zone' : 'New zone', sub: z ? '' : 'Next you walk around and drop the corners with E.', icon: 'fas fa-draw-polygon', fields: [
    { name: 'name', label: 'Name', value: z ? z.name : '', max: 60 }, { name: 'handler', label: 'Behaviour', type: 'select', value: z ? z.handler || '' : '', options: [['', 'None'], ...handlers.map(h => [h.id, h.label])] },
    { name: 'thickness', label: 'Height (m)', type: 'number', value: z ? z.thickness : 10 }, { name: 'color', label: 'Colour', type: 'color', value: z ? z.color : '#08afa2' },
    { name: 'options', label: 'Options (JSON)', type: 'textarea', value: z ? JSON.stringify(z.options || {}) : '{}', span: true, placeholder: '{"kmh": 50}' },
    { name: 'debug', label: 'Show outline in game', type: 'check', value: z ? !!z.debug : false, span: true }] });
}
function parseOpts(s) { try { return JSON.parse(s || '{}'); } catch (e) { toast('Options must be valid JSON', 'error'); return null; } }
A.zoneNew = async () => { const f = await zoneForm(); if (!f) return; const opts = parseOpts(f.options); if (!opts) return; f.options = opts; if (await loc('zoneTool', { draft: f, thickness: +f.thickness })) hideUI(); };
A.zoneEdit = async v => {
  const z = pd('world').zones.zones[+v]; const f = await zoneForm(z); if (!f) return; const opts = parseOpts(f.options); if (!opts) return;
  const d = Object.assign({}, f, { id: z.id, options: opts, points: z.points });
  const redraw = await form({ title: 'Redraw the corners?', icon: 'fas fa-draw-polygon', ok: 'Keep corners', cancel: 'Redraw in game' });
  if (redraw === null) { if (await loc('zoneTool', { draft: d, thickness: +f.thickness })) hideUI(); return; }
  const r = await call('zones:save', d, 'Zone saved'); if (r) { pd('world').zones = r; rerender(); }
};
A.zoneDel = async v => { if (!await confirmBox('Delete zone?', 'Its behaviour stops right away.')) return; const r = await call('zones:delete', { id: +v }); if (r) { pd('world').zones = r; rerender(); } };

/* ─── events calendar ─────────────────────────────────────────────────── */
async function loadEvents() {
  const st = pd('world'); const m = st.month || (st.month = (() => { const d = new Date(); return { y: d.getFullYear(), m: d.getMonth() }; })());
  const from = new Date(m.y, m.m, 1).getTime() / 1000 - 7 * 86400, to = new Date(m.y, m.m + 1, 1).getTime() / 1000 + 7 * 86400;
  const r = await rpc('events:list', { from, to }); if (r.ok) st.events = r.data;
}
function calendarHtml() {
  const st = pd('world'); const m = st.month || { y: new Date().getFullYear(), m: new Date().getMonth() };
  const first = new Date(m.y, m.m, 1); const start = new Date(first); start.setDate(1 - ((first.getDay() + 6) % 7));
  const today = new Date().toDateString();
  let cells = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map(d => `<div class="dh">${d}</div>`).join('');
  for (let i = 0; i < 42; i++) {
    const d = new Date(start); d.setDate(start.getDate() + i);
    const evs = (st.events || []).filter(e => new Date(e.date * 1000).toDateString() === d.toDateString());
    cells += `<div class="d ${d.getMonth() !== m.m ? 'out' : ''} ${d.toDateString() === today ? 'today' : ''}" data-a="${can('events.create') ? 'evNew' : 'noop'}" data-v="${d.getTime()}"><span class="n">${d.getDate()}</span>${evs.map(e => `<div class="ev" data-a="evOpen" data-v="${e.id}">${clock(e.date)} ${esc(e.title)}</div>`).join('')}</div>`;
  }
  return `<div class="toolbar">${btn('', 'calMove', 'sm', { v: -1, icon: 'fas fa-chevron-left' })}<b style="font-size:13px;font-weight:500;min-width:150px;text-align:center">${first.toLocaleDateString('en-US', { month: 'long', year: 'numeric' })}</b>${btn('', 'calMove', 'sm', { v: 1, icon: 'fas fa-chevron-right' })}${btn('Today', 'calMove', 'btn-ghost sm', { v: 0 })}<span class="sp"></span>${can('events.create') ? btn('New event', 'evNew', 'btn-teal sm', { icon: 'fas fa-plus' }) : ''}</div><div class="cal">${cells}</div>`;
}
A.calMove = v => { const st = pd('world'); const m = st.month; if (+v === 0) { const d = new Date(); st.month = { y: d.getFullYear(), m: d.getMonth() }; } else { const d = new Date(m.y, m.m + +v, 1); st.month = { y: d.getFullYear(), m: d.getMonth() }; } loadEvents().then(rerender); };
function toLocalInput(t) { const d = new Date(t * 1000); d.setMinutes(d.getMinutes() - d.getTimezoneOffset()); return d.toISOString().slice(0, 16); }
async function eventForm(e, dayMs) {
  const base = e ? e.date : Math.floor((dayMs ? dayMs + 20 * 3600000 : Date.now() + 86400000) / 1000);
  const f = await form({ title: e ? 'Edit event' : 'New event', icon: 'fas fa-calendar-plus', cols: 1, fields: [{ name: 'title', label: 'Title', value: e ? e.title : '', max: 90 }, { name: 'date', label: 'When', type: 'datetime-local', value: toLocalInput(base) }, { name: 'description', label: 'Details', type: 'textarea', value: e ? e.description || '' : '' }] });
  if (!f) return;
  const r = await call('events:save', { id: e ? e.id : undefined, title: f.title, description: f.description, date: Math.floor(new Date(f.date).getTime() / 1000) }, 'Event saved');
  if (r) { await loadEvents(); rerender(); }
}
A.evNew = v => eventForm(null, v ? +v : null);
A.evOpen = async (v, el, e) => {
  e.stopPropagation();
  const ev = pd('world').events.find(x => x.id === +v);
  const r = await form({ title: ev.title, sub: date(ev.date, true) + ' · ' + (ev.author || ''), icon: 'fas fa-calendar-day', body: `<p class="ink2" style="line-height:1.6;white-space:pre-wrap">${esc(ev.description || 'No details.')}</p>`, ok: can('events.create') ? 'Edit' : 'Close', cancel: can('events.delete') ? 'Delete' : 'Close' });
  if (r && can('events.create')) return eventForm(ev);
  if (r === null && can('events.delete') && await confirmBox('Delete event?', ev.title)) { await call('events:delete', { id: ev.id }, 'Deleted'); await loadEvents(); rerender(); }
};

/* ═══ STAFF ═════════════════════════════════════════════════════════════ */
page('staff', {
  label: 'Staff', icon: 'fas fa-user-shield', perms: [],
  async enter() { await loadStaff(); },
  render() {
    const st = pd('staff');
    const T = [['online', 'Online staff', 'fas fa-signal']];
    if (can('staff.view')) T.unshift(['overview', 'Overview', 'fas fa-chart-simple']);
    if (can('staff.manage')) T.push(['groups', 'Groups', 'fas fa-layer-group'], ['members', 'Members', 'fas fa-id-badge']);
    const t = staffTab(T);
    let body = '';
    const o = st.overview;
    if (t === 'overview') {
      if (!o) body = loading();
      else {
        const onl = o.members.filter(m => m.online).length, duty = o.members.filter(m => m.duty).length;
        const week = o.members.reduce((a, m) => a + (m.week || 0), 0);
        const daily = o.daily || [];
        body = `<div class="stack"><div class="g4">
          <div class="stat"><div class="lbl"><i class="fas fa-id-badge"></i>Members</div><div class="val">${o.members.length}</div><div class="sub">${o.groups.length} groups</div></div>
          <div class="stat" style="--c:#4c9aff"><div class="lbl"><i class="fas fa-signal"></i>Online now</div><div class="val">${onl}</div><div class="sub">${duty} on duty</div><div class="meter"><i style="width:${onl ? duty / onl * 100 : 0}%"></i></div></div>
          <div class="stat"><div class="lbl"><i class="fas fa-clock"></i>Duty this week</div><div class="val">${Math.round(week / 3600)}<small>hours</small></div><div class="sub">all staff combined</div></div>
          <div class="stat" style="--c:var(--amber)"><div class="lbl"><i class="fas fa-bolt"></i>Actions this week</div><div class="val">${num(o.members.reduce((a, m) => a + (m.actions || 0), 0))}</div><div class="sub">logged staff actions</div></div></div>
          <div class="card"><div class="card-h"><h3><i class="fas fa-chart-column"></i>Duty hours, last 14 days</h3></div><div class="card-b">${daily.length ? barChart(daily.map(d => Math.round(d.secs / 360) / 10), daily.map(d => d.day), { id: 'duty', h: 150, fmt: v => (Math.round(v * 10) / 10) + 'h' }) : empty('fas fa-chart-column', 'No duty sessions yet')}</div></div>
          <div class="tbl-wrap"><table class="tbl"><thead><tr><th>Member</th><th>Group</th><th>Status</th><th class="num">Today</th><th class="num">Week</th><th class="num">Total</th><th class="num">Actions</th><th>Last seen</th></tr></thead><tbody>${o.members.map(m => { const g = o.groups.find(x => x.name === m.group_name) || {}; return `<tr class="click" data-a="staffSessions" data-v="${esc(m.license)}"><td><div class="cell">${av(m.nickname || m.name, 'sm', !!m.online)}<div class="tx"><b>${esc(m.nickname || m.name)}</b><span>${m.nickname ? esc(m.name) : ''}</span></div></div></td>
            <td><span class="chip" style="color:${esc(g.color)};border-color:${esc(g.color)}55">${esc(g.label || m.group_name)}</span></td><td>${m.duty ? chip('On duty', 'teal') : m.online ? chip('Online') : '<span class="muted">Offline</span>'}</td>
            <td class="num">${dur(m.today)}</td><td class="num"><b>${dur(m.week)}</b></td><td class="num">${dur(m.total_duty)}</td><td class="num">${num(m.actions)}</td><td>${m.online ? 'now' : ago(m.last_seen)}</td></tr>`; }).join('')}</tbody></table></div></div>`;
      }
    } else if (t === 'online') {
      const l = st.online;
      body = !l ? loading() : l.length ? `<div class="g3">${l.map(s => `<div class="card"><div class="card-b" style="display:flex;gap:12px;align-items:center">${av(s.name, '', true)}<div class="tx" style="flex:1;min-width:0"><b style="color:var(--white);font-weight:500">${esc(s.name)} <span class="muted">#${s.id}</span></b><div style="margin-top:5px;display:flex;gap:5px;flex-wrap:wrap"><span class="chip" style="color:${esc(s.color)};border-color:${esc(s.color)}55">${esc(s.group)}</span>${s.duty ? chip('On duty ' + dur(s.dutyFor), 'teal') : chip('Off duty')}${s.spectating ? chip('Spectating', 'blue', 'fas fa-eye') : ''}</div></div>
        ${can('player.teleport') && s.id !== S.me.id ? btn('', 'pquickS', 'sm', { v: 'goto:' + s.id, icon: 'fas fa-location-arrow', title: 'Go to' }) : ''}</div></div>`).join('')}</div>` : empty('fas fa-user-shield', 'No staff online');
    } else if (t === 'groups') body = groupsHtml();
    else if (t === 'members') {
      if (!o) body = loading();
      else body = `<div class="toolbar">${btn('Add member', 'memberAdd', 'btn-teal sm', { icon: 'fas fa-user-plus' })}<span class="sp"></span><span class="muted">${o.members.length} members</span></div>
        <div class="tbl-wrap"><table class="tbl"><thead><tr><th>Member</th><th>License</th><th>Discord</th><th>Group</th><th></th></tr></thead><tbody>${o.members.map((m, i) => { const g = o.groups.find(x => x.name === m.group_name) || {}; return `<tr><td><div class="cell">${av(m.nickname || m.name, 'sm', !!m.online)}<div class="tx"><b>${esc(m.nickname || m.name)}</b><span>${m.nickname ? esc(m.name) : ''}</span></div></div></td><td class="mono ell" style="max-width:220px">${esc(m.license)}</td><td class="mono">${esc(m.discord || '-')}</td>
          <td><span class="chip" style="color:${esc(g.color)};border-color:${esc(g.color)}55">${esc(g.label || m.group_name)}</span></td>
          <td class="tact"><div class="row-btns" style="flex-wrap:nowrap">${btn('', 'memberEdit', 'xs', { v: i, icon: 'fas fa-pen' })}${btn('', 'memberDel', 'xs btn-red', { v: i, icon: 'fas fa-user-minus' })}</div></td></tr>`; }).join('')}</tbody></table></div>`;
    }
    return ph('Staff', 'Team, duty time, groups and permissions') + tabs(T, t, 'staffTabGo') + `<div class="content" style="padding-top:14px">${body}</div>`;
  },
});
function staffTab(T) { const keys = T.map(x => x[0]); return keys.includes(S.tab.staff) ? S.tab.staff : keys[0]; }
async function loadStaff() {
  const st = pd('staff');
  const jobs = [rpc('staff:online').then(r => { if (r.ok) st.online = r.data; })];
  if (canAny('staff.view', 'staff.manage') && can('staff.view')) jobs.push(rpc('staff:overview').then(r => { if (r.ok) st.overview = r.data; }));
  if (can('staff.manage')) jobs.push(rpc('groups:list').then(r => { if (r.ok) { st.groups = r.data.groups; st.catalog = r.data.catalog; } }));
  await Promise.all(jobs);
  if (S.page === 'staff') rerender();
}
A.staffTabGo = v => { S.tab.staff = v; rerender(); };
A.pquickS = (v, el, e) => A.pquick(v, el, e);
A.staffSessions = async v => {
  const r = await call('staff:sessions', { license: v }); if (!r) return;
  const m = pd('staff').overview.members.find(x => x.license === v);
  infoBox(`Duty sessions · ${m.nickname || m.name}`, r.length ? `<div class="tbl-wrap" style="max-height:380px;overflow:auto"><table class="tbl"><thead><tr><th>Started</th><th>Ended</th><th class="num">Length</th></tr></thead><tbody>${r.map(s => `<tr><td>${date(s.started, true)}</td><td>${date(s.ended, true)}</td><td class="num"><b>${dur(s.seconds)}</b></td></tr>`).join('')}</tbody></table></div>` : empty('fas fa-clock', 'No sessions recorded'), { icon: 'fas fa-clock', size: 'lg' });
};
function groupsHtml() {
  const st = pd('staff'); const gs = st.groups; if (!gs) return loading();
  const cur = st.gedit;
  const left = `<div class="card" style="width:280px;flex:none;align-self:start"><div class="card-h"><h3><i class="fas fa-layer-group"></i>Groups</h3><div class="r">${btn('New', 'groupNew', 'btn-teal xs', { icon: 'fas fa-plus' })}</div></div><div class="card-b np">${gs.map(g => `<div class="li click ${cur && cur.name === g.name && !cur.isNew ? 'on' : ''}" data-a="groupPick" data-v="${esc(g.name)}"><i class="dotc" style="background:${esc(g.color)}"></i><div class="tx"><b>${esc(g.label)}</b><span>${esc(g.name)} · level ${g.hierarchy} · ${(g.permissions || []).includes('*') ? 'all permissions' : (g.permissions || []).length + ' permissions'}</span></div></div>`).join('')}</div></div>`;
  let right = `<div class="card" style="flex:1">${empty('fas fa-layer-group', 'Pick a group', 'Set its level, colour, Discord role, duty outfit and permissions.')}</div>`;
  if (cur) {
    const all = cur.permissions.includes('*');
    right = `<div class="card" style="flex:1;min-width:0"><div class="card-h"><h3><i class="fas fa-pen"></i>${cur.isNew ? 'New group' : esc(cur.label)}</h3><div class="r">${!cur.isNew ? btn('Save my outfit', 'groupOutfit', 'xs', { icon: 'fas fa-shirt', title: 'Uses what you are wearing now as the duty outfit' }) + (cur.hasOutfit ? btn('Clear outfit', 'groupOutfit', 'xs btn-ghost', { v: 'clear' }) : '') + btn('Delete', 'groupDel', 'xs btn-red', { icon: 'fas fa-trash' }) : ''}${btn('Save', 'groupSave', 'xs btn-teal', { icon: 'fas fa-check' })}</div></div>
      <div class="card-b"><div class="fgrid c4" style="margin-bottom:16px">
        <div class="field"><label>Name</label><input class="inp" id="g-name" value="${esc(cur.name)}" ${cur.isNew ? '' : 'disabled'}></div><div class="field"><label>Label</label><input class="inp" id="g-label" value="${esc(cur.label)}"></div>
        <div class="field"><label>Level <small>higher = more senior</small></label><input class="inp" id="g-hier" type="number" value="${cur.hierarchy}"></div><div class="field"><label>Colour</label><div style="display:flex;gap:6px"><input class="inp" type="color" id="g-color" value="${esc(cur.color)}"><input class="inp" id="g-sprite" type="number" value="${cur.sprite || 280}" title="Map sprite for duty blips"></div></div>
        <div class="field span"><label>Discord role ID <small>optional, members with this role join the group</small></label><input class="inp" id="g-role" value="${esc(cur.discord_role || '')}"></div></div>
        <div style="display:flex;align-items:center;gap:10px;margin-bottom:12px"><b style="font-size:12px;font-weight:500">Permissions</b><span class="muted">${all ? 'Everything' : cur.permissions.length + ' selected'}</span><span style="flex:1"></span><label class="chk" data-a="permAll">${swv(all)}Full access</label></div>
        ${(st.catalog || []).filter(c => c.list.length).map(c => `<div class="perm-cat"><h4>${esc(c.cat)}<span class="muted" style="font-weight:300">${c.list.filter(p => cur.permissions.includes(p[0])).length}/${c.list.length}</span>${all ? '' : btn('Toggle all', 'permCat', 'xs btn-ghost', { v: c.cat })}</h4><div class="perm-grid">${c.list.map(([id, label]) => { const on = all || cur.permissions.includes(id); return `<div class="perm ${on ? 'on' : ''} ${all ? 'lock' : ''}" data-a="permToggle" data-v="${esc(id)}" title="${esc(id)}"><label class="chk"><input type="checkbox" ${on ? 'checked' : ''}><span class="box"></span></label>${esc(label)}</div>`; }).join('')}</div></div>`).join('')}</div></div>`;
  }
  return `<div style="display:flex;gap:14px;align-items:flex-start">${left}${right}</div>`;
}
function groupFormRead() { const g = pd('staff').gedit; ['name', 'label', 'role', 'sprite'].forEach(() => {}); if ($('#g-label')) { g.name = $('#g-name').value; g.label = $('#g-label').value; g.hierarchy = +$('#g-hier').value; g.color = $('#g-color').value; g.sprite = +$('#g-sprite').value; g.discord_role = $('#g-role').value; } }
A.groupPick = v => { const st = pd('staff'); const g = st.groups.find(x => x.name === v); st.gedit = JSON.parse(JSON.stringify(Object.assign({}, g, { permissions: g.permissions || [] }))); rerender(); };
A.groupNew = () => { pd('staff').gedit = { isNew: true, name: '', label: '', hierarchy: 10, color: '#08afa2', sprite: 280, permissions: ['self.panel', 'self.quickmenu'] }; rerender(); };
A.permToggle = v => { groupFormRead(); const g = pd('staff').gedit; const i = g.permissions.indexOf(v); i >= 0 ? g.permissions.splice(i, 1) : g.permissions.push(v); rerender(); };
A.permAll = () => { groupFormRead(); const g = pd('staff').gedit; g.permissions = g.permissions.includes('*') ? [] : ['*']; rerender(); };
A.permCat = v => { groupFormRead(); const st = pd('staff'); const g = st.gedit; const c = st.catalog.find(x => x.cat === v); const ids = c.list.map(p => p[0]); const allOn = ids.every(id => g.permissions.includes(id)); g.permissions = allOn ? g.permissions.filter(p => !ids.includes(p)) : [...new Set([...g.permissions, ...ids])]; rerender(); };
A.groupSave = async () => { groupFormRead(); const st = pd('staff'); const g = st.gedit; const r = await call('groups:save', Object.assign({}, g, { id: g.isNew ? undefined : g.id }), 'Group saved'); if (r) { st.groups = r; S.boot.groups = r; st.gedit = null; A.groupPick(g.name.toLowerCase().replace(/[^\w]/g, '')); } };
A.groupDel = async () => { const st = pd('staff'); const g = st.gedit; if (!await confirmBox(`Delete ${g.label}?`, 'Every member of this group loses staff access.', { ok: 'Delete group' })) return; const r = await call('groups:delete', { name: g.name }, 'Group deleted'); if (r) { st.groups = r; st.gedit = null; rerender(); } };
A.groupOutfit = async v => { const g = pd('staff').gedit; if (await call('groups:outfit', { name: g.name, clear: v === 'clear' }, v === 'clear' ? 'Outfit cleared' : 'Outfit saved from what you are wearing')) { g.hasOutfit = v !== 'clear'; rerender(); } };
async function memberForm(m) {
  const groups = (pd('staff').overview || {}).groups || S.boot.groups || [];
  return form({ title: m ? 'Edit member' : 'Add member', icon: 'fas fa-user-plus', fields: [
    ...(m ? [] : [{ name: 'id', label: 'Online player ID', type: 'number', placeholder: 'or use a license below' }]),
    { name: 'license', label: 'License', value: m ? m.license : '', placeholder: 'license:xxxxxxxx', span: !m ? false : true },
    { name: 'group', label: 'Group', type: 'select', value: m ? m.group_name : '', options: groups.map(g => [g.name, g.label]) }, { name: 'nickname', label: 'Nickname', value: m ? m.nickname || '' : '', placeholder: 'Optional' },
    ...(m ? [] : [{ name: 'name', label: 'Name', placeholder: 'For offline adds' }])] });
}
A.memberAdd = async () => { const f = await memberForm(); if (!f) return; if (await call('members:save', f, 'Member saved')) { await loadStaff(); } };
A.memberEdit = async v => { const m = pd('staff').overview.members[+v]; const f = await memberForm(m); if (!f) return; if (await call('members:save', Object.assign(f, { name: m.name }), 'Member saved')) loadStaff(); };
A.memberDel = async v => { const m = pd('staff').overview.members[+v]; if (!await confirmBox(`Remove ${m.nickname || m.name}?`, 'They lose all staff access right away.', { ok: 'Remove' })) return; if (await call('members:delete', { license: m.license }, 'Removed')) loadStaff(); };

/* ═══ LOGS ══════════════════════════════════════════════════════════════ */
const LOGCATS = [['all', 'All', 'fas fa-list'], ['staff', 'Staff', 'fas fa-user-shield'], ['moderation', 'Moderation', 'fas fa-gavel'], ['reports', 'Reports', 'fas fa-flag'], ['joins', 'Joins', 'fas fa-right-to-bracket'], ['deaths', 'Deaths', 'fas fa-skull'], ['money', 'Money', 'fas fa-sack-dollar'], ['developer', 'Developer', 'fas fa-code'], ['chat', 'Chat', 'fas fa-message']];
const LOGCOL = { staff: 'teal', moderation: 'red', reports: 'blue', joins: '', deaths: 'red', money: 'amber', developer: 'blue', chat: '' };
page('logs', {
  label: 'Logs', icon: 'fas fa-scroll', perms: ['logs.view'],
  async enter() { await loadLogs(); },
  render() {
    const st = pd('logs'); const cat = st.cat || 'all';
    const counts = {}; (st.counts || []).forEach(c => counts[c.category] = c.n);
    const rows = st.rows;
    return ph('Logs', 'Everything staff and players did, newest first', `<span class="muted" style="font-size:11px">Last 24h: <b class="ink2">${num(Object.values(counts).reduce((a, b) => a + b, 0))}</b></span>`) + `<div class="content">
      <div class="toolbar">${seg(LOGCATS.filter(([k]) => k === 'all' || counts[k] || k === cat).map(([k, l]) => [k, l, counts[k] ? `<span class="tally">${counts[k]}</span>` : '']), cat, 'logCat')}
        <div class="search" style="min-width:220px"><i class="fas fa-magnifying-glass"></i><input class="inp" id="log-q" data-enter="logSearch" value="${esc(st.q || '')}" placeholder="Search message, staff, player or license"></div></div>
      <div class="tbl-wrap">${!rows ? loading() : rows.length ? `<table class="tbl"><thead><tr><th>Time</th><th>Type</th><th>Action</th><th>Staff</th><th>Player</th><th>Details</th><th></th></tr></thead><tbody id="log-body">${rows.map(logRow).join('')}</tbody></table>` : empty('fas fa-scroll', 'No logs found')}</div>
      ${rows && rows.length >= 80 ? `<div style="text-align:center;margin-top:12px">${btn('Load older', 'logMore', 'btn-ghost sm', { icon: 'fas fa-chevron-down' })}</div>` : ''}</div>`;
  },
});
function logRow(r) {
  return `<tr><td title="${date(r.time, true)}">${ago(r.time)}</td><td>${chip(r.category, LOGCOL[r.category] || '')}</td><td><b>${esc((r.action || '').replace(/_/g, ' '))}</b></td><td>${esc(r.staff_name || r.staff || '-')}</td><td>${esc(r.target_name || r.target || '-')}</td>
    <td style="white-space:normal;max-width:360px;color:var(--ink-2)">${esc(r.message || '')}</td><td class="tact">${r.x ? btn('', 'gotoXYZ', 'xs', { v: `${r.x},${r.y},${r.z}`, icon: 'fas fa-location-arrow', title: 'Go to location' }) : ''}</td></tr>`;
}
async function loadLogs(more) {
  const st = pd('logs');
  const d = { category: st.cat || 'all', search: st.q || '' };
  if (more && st.rows && st.rows.length) d.before = st.rows[st.rows.length - 1].id;
  const r = await rpc('logs:list', d);
  if (r.ok) { st.rows = more ? st.rows.concat(r.data.rows) : r.data.rows; st.counts = r.data.counts; if (S.page === 'logs') rerender(); }
}
A.logCat = v => { const st = pd('logs'); st.cat = v; st.rows = null; rerender(); loadLogs(); };
A.logSearch = () => { const st = pd('logs'); st.q = $('#log-q').value; st.rows = null; rerender(); loadLogs(); };
A.logMore = () => loadLogs(true);

/* ═══ SERVER ════════════════════════════════════════════════════════════ */
page('server', {
  label: 'Server', icon: 'fas fa-server', perms: ['resources.read', 'console.read', 'developer.execute'],
  async enter() { await serverTabEnter(); },
  leave() { if (pd('server').subbed) { rpc('console:subscribe', { on: false }); pd('server').subbed = false; } },
  render() {
    const st = pd('server');
    const T = [];
    if (can('resources.read')) T.push(['resources', 'Resources', 'fas fa-cubes-stacked']);
    if (can('console.read')) T.push(['console', 'Console', 'fas fa-terminal']);
    if (can('developer.execute')) T.push(['dev', 'Developer', 'fas fa-code']);
    const t = serverTab(T);
    let body = '';
    if (t === 'resources') {
      const q = (st.rq || '').toLowerCase(); const list = (st.res || []).filter(r => !q || `${r.name} ${r.author || ''} ${r.description || ''}`.toLowerCase().includes(q));
      const started = (st.res || []).filter(r => r.state === 'started').length;
      body = `<div class="toolbar"><div class="search"><i class="fas fa-magnifying-glass"></i><input class="inp" data-in="resQ" value="${esc(st.rq || '')}" placeholder="Search resources"></div><span class="muted">${started} started · ${(st.res || []).length} total</span>${btn('Refresh', 'resLoad', 'btn-ghost sm', { icon: 'fas fa-rotate' })}</div>
        <div class="tbl-wrap" id="res-table">${!st.res ? loading() : `<table class="tbl"><thead><tr><th>Resource</th><th>Version</th><th>Author</th><th>State</th><th></th></tr></thead><tbody>${list.map(r => `<tr><td><div class="tx"><b>${esc(r.name)}</b>${r.description ? `<div class="muted ell" style="max-width:380px;font-size:10.5px">${esc(r.description)}</div>` : ''}</div></td><td>${esc(r.version || '-')}</td><td>${esc(r.author || '-')}</td>
          <td>${r.state === 'started' ? chip('Started', 'teal') : r.state === 'stopped' ? chip('Stopped') : chip(r.state, 'amber')}</td>
          <td class="tact">${can('resources.manage') ? `<div class="row-btns" style="flex-wrap:nowrap">${r.state === 'started' ? btn('', 'resDo', 'xs', { v: 'restart:' + r.name, icon: 'fas fa-rotate-right', title: 'Restart' }) + btn('', 'resDo', 'xs btn-red', { v: 'stop:' + r.name, icon: 'fas fa-stop', title: 'Stop' }) : btn('', 'resDo', 'xs btn-teal', { v: 'start:' + r.name, icon: 'fas fa-play', title: 'Start' })}</div>` : ''}</td></tr>`).join('')}</tbody></table>`}</div>`;
    } else if (t === 'console') {
      body = `<div style="display:flex;flex-direction:column;height:100%;gap:10px"><div class="console" id="console">${(st.lines || []).map(consoleLine).join('')}</div>
        ${can('console.execute') ? `<div style="display:flex;gap:8px"><input class="inp mono" id="con-in" data-enter="conExec" placeholder="Server command, like: ensure my-resource"><button class="btn btn-teal" data-a="conExec"><i class="fas fa-paper-plane"></i>Run</button></div>` : ''}</div>`;
    } else if (t === 'dev') {
      const d = st.dev || { side: 'server', code: 'print(GetNumPlayerIndices())\nreturn #GetPlayers()', target: '' };
      body = `<div class="g2" style="align-items:start"><div class="card"><div class="card-h"><h3><i class="fas fa-code"></i>Run Lua</h3><div class="r">${seg([['server', 'Server'], ['client', 'Client']], d.side, 'devSide')}</div></div><div class="card-b" style="display:grid;gap:10px">
          <textarea class="code" id="dev-code" spellcheck="false" data-in="devCode">${esc(d.code)}</textarea>
          <div style="display:flex;gap:8px">${d.side === 'client' ? `<input class="inp" id="dev-target" type="number" placeholder="Player ID, blank = you" value="${esc(d.target)}" style="width:190px">` : ''}<span style="flex:1"></span><span class="muted" style="align-self:center;font-size:10.5px">Every run is logged</span>${btn('Run', 'devRun', 'btn-teal', { icon: 'fas fa-play' })}</div></div></div>
        <div class="card"><div class="card-h"><h3><i class="fas fa-terminal"></i>Output</h3><div class="r">${btn('', 'devClear', 'xs btn-ghost', { icon: 'fas fa-eraser', title: 'Clear' })}</div></div><div class="card-b"><div class="out" id="dev-out" style="max-height:420px;min-height:200px">${(st.out || []).map(o => `<div class="${o.err ? 'tred' : ''}">${esc(o.t)}</div>`).join('') || '<span class="muted">Results show here. Server code can use print() and return values.</span>'}</div></div></div></div>`;
    }
    return ph('Server', 'Resources, live console and developer tools') + tabs(T, t, 'serverTabGo') + `<div class="content" style="padding-top:14px;${t === 'console' ? 'display:flex;flex-direction:column' : ''}">${body}</div>`;
  },
  mounted() { const c = $('#console'); if (c) c.scrollTop = c.scrollHeight; },
});
function serverTab(T) { const keys = T ? T.map(x => x[0]) : ['resources', 'console', 'dev'].filter(k => can({ resources: 'resources.read', console: 'console.read', dev: 'developer.execute' }[k])); return keys.includes(S.tab.server) ? S.tab.server : keys[0]; }
async function serverTabEnter() {
  const st = pd('server'); const t = serverTab();
  if (t === 'resources') { const r = await rpc('resources:list'); if (r.ok) st.res = r.data; }
  if (t === 'console' && !st.subbed) { const r = await rpc('console:subscribe', { on: true }); if (r.ok) { st.subbed = true; st.lines = Array.isArray(r.data) ? r.data : []; } }
  if (t !== 'console' && st.subbed) { rpc('console:subscribe', { on: false }); st.subbed = false; }
  if (S.page === 'server') rerender();
}
A.serverTabGo = v => { S.tab.server = v; rerender(); serverTabEnter(); };
IN.resQ = debounce(v => { pd('server').rq = v; const tmp = document.createElement('div'); tmp.innerHTML = PAGES.server.render(); $('#res-table').replaceWith(tmp.querySelector('#res-table')); }, 150);
A.resLoad = () => { pd('server').res = null; rerender(); serverTabEnter(); };
A.resDo = async v => { const [a, name] = v.split(':'); if (a !== 'start' && !await confirmBox(`${a === 'stop' ? 'Stop' : 'Restart'} ${name}?`, 'Players using it may be affected.', { ok: a === 'stop' ? 'Stop' : 'Restart' })) return; const r = await call('resources:action', { name, action: a }, `${name}: ${a}`); if (r) { const st = pd('server'); const x = st.res.find(y => y.name === name); if (x) x.state = r; rerender(); } };
const stripColors = s => String(s).replace(/\^[0-9]/g, '').replace(/\x1b\[[0-9;]*m/g, '');
function consoleLine(l) { const m = stripColors(l.m); const cls = /error|fail|exception/i.test(m) ? 'err' : /warn/i.test(m) ? 'wrn' : ''; return `<div class="ln ${cls}">${l.c ? `<span class="ch">[${esc(l.c)}]</span>` : ''}${esc(m)}</div>`; }
function consolePush(batch) {
  const st = pd('server'); st.lines = (st.lines || []).concat(batch).slice(-600);
  const c = $('#console'); if (!c) return;
  const stick = c.scrollTop + c.clientHeight >= c.scrollHeight - 30;
  c.insertAdjacentHTML('beforeend', batch.map(consoleLine).join(''));
  while (c.childElementCount > 600) c.firstElementChild.remove();
  if (stick) c.scrollTop = c.scrollHeight;
}
A.conExec = async () => { const i = $('#con-in'); const cmd = i.value.trim(); if (!cmd) return; i.value = ''; consolePush([{ c: '>', m: cmd }]); await call('console:exec', { command: cmd }); };
function devState() { const st = pd('server'); st.dev = st.dev || { side: 'server', code: 'print(GetNumPlayerIndices())\nreturn #GetPlayers()', target: '' }; return st.dev; }
IN.devCode = v => { devState().code = v; };
A.devSide = v => { const d = devState(); const c = $('#dev-code'); if (c) d.code = c.value; d.side = v; rerender(); };
A.devClear = () => { pd('server').out = []; rerender(); };
function devOut(t, err) { const st = pd('server'); st.out = (st.out || []).concat({ t, err }).slice(-100); const o = $('#dev-out'); if (o) { if (!o.querySelector('div')) o.innerHTML = ''; o.insertAdjacentHTML('beforeend', `<div class="${err ? 'tred' : ''}">${esc(t)}</div>`); o.scrollTop = o.scrollHeight; } }
A.devRun = async () => {
  const d = devState(); d.code = $('#dev-code').value; const tg = $('#dev-target'); d.target = tg ? tg.value : '';
  devOut(`> ${d.side}${d.side === 'client' ? ' ' + (d.target || 'me') : ''}`);
  const r = await rpc('dev:exec', { code: d.code, side: d.side, target: d.target ? +d.target : undefined });
  if (!r.ok) return devOut(r.err, true);
  (r.data.output || []).forEach(l => devOut(l));
  if (r.data.error) devOut(r.data.error, true);
  if (r.data.result) devOut('= ' + r.data.result);
};

/* ═══ SETTINGS ══════════════════════════════════════════════════════════ */
const POSITIONS = [['top-center', 'Top centre'], ['top-left', 'Top left'], ['top-right', 'Top right'], ['bottom-center', 'Bottom centre'], ['bottom-left', 'Bottom left'], ['left-center', 'Left middle']];
page('settings', {
  label: 'Settings', icon: 'fas fa-sliders', perms: [],
  render() {
    const s = S.settings;
    const cmds = S.boot && S.boot.commands ? Object.entries(S.boot.commands).filter(([, c]) => c.enabled) : [];
    const row = (t, d, ctrl) => `<div class="li" style="padding:12px 14px"><div class="tx"><b>${esc(t)}</b><span style="white-space:normal">${esc(d)}</span></div>${ctrl}</div>`;
    return ph('Settings', 'Saved on your PC only') + `<div class="content"><div class="g2" style="align-items:start">
      <div class="card"><div class="card-h"><h3><i class="fas fa-display"></i>Interface</h3></div><div class="card-b np">
        ${row('Panel size', 'Scale the whole panel up or down.', `<div style="display:flex;align-items:center;gap:10px;width:200px"><input type="range" min="0.75" max="1.25" step="0.05" value="${s.scale}" data-ch="setScale"><b style="width:40px;text-align:right">${Math.round(s.scale * 100)}%</b></div>`)}
        ${row('Sounds', 'Soft tones for reports, messages and errors.', sw(s.sounds, 'setBool', 'sounds'))}
        ${row('Go on duty when joining', 'Otherwise you join off duty.', sw(s.autoDuty !== false, 'setBool', 'autoDuty'))}
        ${row('Coords position', 'Where the coords box sits.', `<select class="sel sm" style="width:160px" data-ch="setPos" data-k="coordsPos">${POSITIONS.map(([k, l]) => `<option value="${k}" ${s.coordsPos === k ? 'selected' : ''}>${l}</option>`).join('')}</select>`)}
        ${row('Noclip hint position', 'Where the noclip speed box sits.', `<select class="sel sm" style="width:160px" data-ch="setPos" data-k="noclipPos">${POSITIONS.map(([k, l]) => `<option value="${k}" ${s.noclipPos === k ? 'selected' : ''}>${l}</option>`).join('')}</select>`)}
        ${row('Start page', 'The page the panel opens on.', `<select class="sel sm" style="width:160px" data-ch="setPos" data-k="startPage">${Object.values(PAGES).filter(pageAllowed).map(p => `<option value="${p.key}" ${s.startPage === p.key ? 'selected' : ''}>${esc(p.label)}</option>`).join('')}</select>`)}
      </div></div>
      <div class="stack">
      <div class="card"><div class="card-h"><h3><i class="fas fa-bolt"></i>Quick menu keys</h3><div class="r">${sw(s.hotkeys !== false, 'setBool', 'hotkeys')}${btn('Reset', 'qkReset', 'btn-ghost xs', { icon: 'fas fa-rotate-left' })}</div></div>
        <div class="card-b np scroll-y" style="max-height:330px">${s.hotkeys === false ? empty('fas fa-keyboard', 'Menu keys are off', 'Turn them on to use the keys below in the quick menu and panel.') : `<p class="muted" style="padding:10px 14px 4px;font-size:10.5px;line-height:1.5">Press these while the quick menu is open. Click a key to change it, Backspace clears it, Esc cancels.</p>
          <div class="kgrid">${quickKeyList().map(x => `<div class="krow"><span class="ell">${esc(x.label)}</span><button class="btn xs ${S.rebind === x.id ? 'active' : ''}" data-a="qkRebind" data-v="${x.id}">${x.key ? `<span class="key">${esc(keyLabel(x.key))}</span>` : '<span class="muted">None</span>'}</button></div>`).join('')}</div>`}</div></div>
      <div class="card"><div class="card-h"><h3><i class="fas fa-keyboard"></i>Game keys</h3><div class="r"><span class="muted" style="font-size:10.5px">Rebind in GTA settings, Key Bindings, FiveM</span></div></div><div class="card-b np scroll-y" style="max-height:330px">
        ${cmds.map(([k, c]) => { const key = S.keys[k] || c.key; return `<div class="li" style="padding:9px 14px"><div class="tx"><b class="mono">/${esc(c.name)}</b></div>${key ? `<span class="key">${esc(keyLabel(key))}</span>` : c.key === undefined ? '<span class="muted" style="font-size:10.5px">Command only</span>' : '<span class="muted" style="font-size:10.5px">Not bound</span>'}</div>`; }).join('') || empty('fas fa-keyboard', 'No commands')}
        ${(S.binds || []).length ? `<div class="act-grp" style="padding:10px 14px 4px">Bindable actions</div>${S.binds.map(b => `<div class="li" style="padding:9px 14px"><div class="tx"><b>${esc(b.label)}</b></div>${b.key ? `<span class="key">${esc(keyLabel(b.key))}</span>` : '<span class="muted" style="font-size:10.5px">Not bound</span>'}</div>`).join('')}` : ''}
      </div></div>
      <div class="card"><div class="card-h"><h3><i class="fas fa-circle-info"></i>Panel shortcuts</h3><div class="r">${btn('All keys', 'keyHelp', 'btn-ghost xs', { icon: 'fas fa-keyboard' })}</div></div><div class="card-b" style="display:flex;flex-wrap:wrap;gap:14px;font-size:11px;color:var(--ink-2)">
        <span><span class="key">Ctrl</span> <span class="key">K</span> Search</span><span><span class="key">Alt</span> <span class="key">1-9</span> Pages</span><span><span class="key">Alt</span> <span class="key">Q</span> Quick menu</span><span><span class="key">Alt</span> <span class="key">D</span> Duty</span><span><span class="key">?</span> All keys</span></div></div>
      </div></div></div>`;
  },
});
function saveSettings() { post('saveSettings', S.settings); }
A.setScale = v => { S.settings.scale = +v; applyScale(); saveSettings(); rerender(); };
A.setBool = v => { const cur = v === 'autoDuty' || v === 'hotkeys' ? S.settings[v] !== false : !!S.settings[v]; S.settings[v] = !cur; saveSettings(); rerender(); };
A.setPos = (v, el) => { S.settings[el.dataset.k] = v; saveSettings(); };
