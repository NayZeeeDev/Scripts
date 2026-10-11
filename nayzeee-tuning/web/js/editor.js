/* ═══════════════════════════════════════════════════════════
   Tuning UI · shop editor (/mechaniceditor)
   ═══════════════════════════════════════════════════════════ */
'use strict';

const Ed = { open: false, d: null, shops: [], draft: null, isNew: false, confirm: null };
const ED_COL = { center: '#ffffff', bay: '#08afa2', boss: '#f59e0b', booth: '#a855f7', pile: '#3b82f6', drop: '#22c55e', truck: '#e5484d', storage: '#22d3ee' };
const PILE_NAMES = { body: 'Body panels', exhaust: 'Exhausts', engine: 'Engine parts', jacks: 'Jacks & stands', wheels: 'Wheels', paint: 'Paint supplies', interior: 'Interior', electronics: 'Electronics', repair: 'Repair kits' };
const fmtC = (c) => (c ? `${c.x.toFixed(1)}, ${c.y.toFixed(1)}, ${c.z.toFixed(1)}${c.w != null ? ' · ' + Math.round(c.w) + '°' : ''}` : 'Not set');
const clone = (o) => JSON.parse(JSON.stringify(o));

Ed.show = function (d) {
  Ed.d = d;
  Ed.shops = d.shops || [];
  Ed.open = true;
  $('#editorx').hidden = false;
  $('#editorx').classList.remove('away');
  Ed.pick(Ed.shops[0] && Ed.shops[0].id);
};
Ed.hide = () => { Ed.open = false; Ed.walk(false); $('#editorx').hidden = true; };
Ed.walk = (on) => { $('#editorx').classList.toggle('walk', on); $('#exWalk').hidden = !on; };
Ed.close = () => post('ed:close');

Ed.pick = function (id) {
  const s = Ed.shops.find((x) => x.id === id);
  Ed.isNew = !s;
  Ed.draft = s ? clone(s) : null;
  if (Ed.draft) { Ed.draft.bays = Ed.draft.bays || []; Ed.draft.booths = Ed.draft.booths || []; Ed.draft.stockpiles = Ed.draft.stockpiles || {}; }
  Ed.render();
  Ed.sync();
};

Ed.newShop = function () {
  Ed.isNew = true;
  Ed.draft = { id: '', label: '', mode: 'mechanic', job: 'mechanic', bayRadius: 2.4, radius: 30, grades: { access: 0, manager: 2, boss: 3 },
    blip: { enabled: true, sprite: 446, color: 5, scale: 0.8 }, center: clone(Ed.d.here), bays: [], booths: [], stockpiles: {}, boss: null, drop: null, truckSpawn: null, storage: null,
    claimBays: 'auto', partSource: 'default' };
  Ed.render();
  Ed.sync();
};

Ed.sync = () => post('ed:preview', Ed.draft || null);

// sets a point to where you stand right now (or your car for bays / the work truck)
Ed.place = async function (kind, apply) {
  const r = await post('ed:here', { kind });
  if (!r || r.x == null) return;
  apply({ x: +r.x.toFixed(2), y: +r.y.toFixed(2), z: +r.z.toFixed(2), w: +(r.w || 0).toFixed(1) });
  Ed.render();
  Ed.sync();
};

const exRow = (color, title, c, actions, extra = '') => `<div class="exp"><span class="dot" style="background:${color}"></span><div class="tx"><b>${title}</b><span class="${c ? '' : 'unset'}">${fmtC(c)}</span></div>${extra}${actions}</div>`;
const exBtn = (act, icon, title, data = '') => `<button class="ibtn sm ${act === 'place' ? 'here' : ''}" data-act="${act}" ${data} title="${title}"><i class="fa-solid ${icon}"></i></button>`;
const HERE = 'fa-location-crosshairs';

Ed.render = function () {
  const d = Ed.draft;
  const body = $('#exBody');
  $('#exSub').textContent = d ? (Ed.isNew ? 'New shop' : `${d.label || d.id}${d.edited ? ' · edited' : ''}`) : 'Place points in the world';
  body.innerHTML = `
    <div class="exhelp">Press <span class="kc">F2</span> (or Walk) to hide the editor and walk to a spot, face the way it should point, press <span class="kc">F2</span> again and hit <i class="fa-solid ${HERE}" style="color:var(--teal)"></i> to set it there. Bays and the work truck use your car when you sit in one. <i class="fa-solid fa-xmark"></i> removes a point. Nothing changes until you press Save.</div>
    <div class="hrow exg"><select class="field grow" id="exShop">${Ed.shops.map((s) => `<option value="${esc(s.id)}" ${d && !Ed.isNew && s.id === d.id ? 'selected' : ''}>${esc(s.label || s.id)}${s.created ? ' (editor)' : ''}${s.edited ? ' *' : ''}</option>`).join('')}${Ed.isNew ? '<option selected>New shop</option>' : ''}</select>
      <button class="btn sm" id="exNew"><i class="fa-solid fa-plus"></i>New shop</button></div>
    ${!d ? '<div class="empty"><b>No shop selected</b></div>' : `
    <div class="sect">Basics</div>
    <div class="exgrid exg">
      ${Ed.isNew ? `<div><span class="lbl">Shop id</span><input class="field" id="exId" maxlength="40" placeholder="my_shop" value="${esc(d.id)}" spellcheck="false"></div>` : ''}
      <div><span class="lbl">Name</span><input class="field" id="exLabel" maxlength="48" value="${esc(d.label || '')}"></div>
      <div><span class="lbl">Job</span><input class="field" id="exJob" maxlength="40" placeholder="none = public shop" value="${esc(d.job || '')}" spellcheck="false"></div>
      <div><span class="lbl">Mode</span><select class="field" id="exMode">${['self', 'mechanic', 'hybrid'].map((m) => `<option ${d.mode === m ? 'selected' : ''}>${m}</option>`).join('')}</select></div>
      <div><span class="lbl">Default bay radius (m)</span><input class="field" id="exBayR" type="number" step="0.1" min="1" max="10" value="${d.bayRadius || 2.4}"></div>
      <div><span class="lbl">Blip sprite / colour</span><div class="hrow"><input class="field" id="exSprite" type="number" value="${(d.blip || {}).sprite || 446}"><input class="field" id="exColor" type="number" value="${(d.blip || {}).color || 5}"></div></div>
      ${d.job ? `<div><span class="lbl">Bay claiming</span><select class="field" id="exClaim">${[['auto', 'Auto (by mode / bay count)'], ['on', 'On'], ['off', 'Off']].map(([v, l]) => `<option value="${v}" ${claimVal(d) === v ? 'selected' : ''}>${l}</option>`).join('')}</select></div>
      <div><span class="lbl">Work order parts from</span><select class="field" id="exSrc">${[['default', 'Default (config)'], ['supply', 'Supply storage'], ['inventory', 'Inventory'], ['both', 'Both']].map(([v, l]) => `<option value="${v}" ${(d.partSource || 'default') === v ? 'selected' : ''}>${l}</option>`).join('')}</select></div>` : ''}
    </div>
    ${d.job ? `<div class="exgrid exg" style="grid-template-columns:repeat(3,1fr)"><div><span class="lbl">Grade: access</span><input class="field" id="exGa" type="number" min="0" value="${(d.grades || {}).access ?? 0}"></div><div><span class="lbl">Manager</span><input class="field" id="exGm" type="number" min="0" value="${(d.grades || {}).manager ?? 2}"></div><div><span class="lbl">Boss</span><input class="field" id="exGb" type="number" min="0" value="${(d.grades || {}).boss ?? 3}"></div></div>` : ''}

    <div class="sect">Location</div>
    ${exRow(ED_COL.center, 'Shop centre & blip', d.center, exBtn('place', HERE, 'Set to where I stand', 'data-k="center"') + exBtn('goto', 'fa-location-arrow', 'Go there', 'data-k="center"'))}

    <div class="sect">Tuning bays · ${d.bays.length}</div>
    ${d.bays.map((b, i) => exRow(ED_COL.bay, `Bay ${i + 1}`, b, exBtn('place', HERE, 'Move here (where I stand)', `data-k="bay" data-i="${i}"`) + exBtn('goto', 'fa-location-arrow', 'Go there', `data-k="bay" data-i="${i}"`) + exBtn('del', 'fa-xmark', 'Remove', `data-k="bay" data-i="${i}"`), `<input class="field" type="number" step="0.1" min="1" max="10" data-bayr="${i}" value="${b.r ?? ''}" placeholder="${d.bayRadius || 2.4}" title="Radius of this bay in metres (empty = default)">`)).join('')}
    <button class="exadd" data-act="add" data-k="bay"><i class="fa-solid fa-plus"></i>Add a bay</button>

    ${d.job ? `<div class="sect">Workshop</div>
    ${exRow(ED_COL.boss, 'Boss desk (tablet without the item)', d.boss, exBtn('place', HERE, 'Set to where I stand', 'data-k="boss"') + exBtn('goto', 'fa-location-arrow', 'Go there', 'data-k="boss"') + (d.boss ? exBtn('clear', 'fa-xmark', 'Clear', 'data-k="boss"') : ''))}
    ${exRow(ED_COL.storage, 'Supply storage (take parts, runs unload here)', d.storage, exBtn('place', HERE, 'Set to where I stand', 'data-k="storage"') + exBtn('goto', 'fa-location-arrow', 'Go there', 'data-k="storage"') + (d.storage ? exBtn('clear', 'fa-xmark', 'Remove', 'data-k="storage"') : ''))}
    ${exRow(ED_COL.drop, 'Drop point (tow jobs, supply runs)', d.drop, exBtn('place', HERE, 'Set to where I stand', 'data-k="drop"') + exBtn('goto', 'fa-location-arrow', 'Go there', 'data-k="drop"') + (d.drop ? exBtn('clear', 'fa-xmark', 'Clear', 'data-k="drop"') : ''))}
    ${exRow(ED_COL.truck, 'Work truck spawn', d.truckSpawn, exBtn('place', HERE, 'Set to where I stand', 'data-k="truckSpawn"') + exBtn('goto', 'fa-location-arrow', 'Go there', 'data-k="truckSpawn"') + (d.truckSpawn ? exBtn('clear', 'fa-xmark', 'Clear', 'data-k="truckSpawn"') : ''))}

    <div class="sect">Paint booths · ${d.booths.length}</div>
    ${d.booths.map((b, i) => exRow(ED_COL.booth, `Booth ${i + 1}`, b.coords, exBtn('place', HERE, 'Move here (where I stand)', `data-k="booth" data-i="${i}"`) + exBtn('del', 'fa-xmark', 'Remove', `data-k="booth" data-i="${i}"`), `<input class="field" type="number" step="0.5" min="1" max="15" data-br="${i}" value="${b.radius}" title="Radius">`)).join('')}
    <button class="exadd" data-act="add" data-k="booth"><i class="fa-solid fa-plus"></i>Add a paint booth</button>

    <div class="sect">Part racks (mechanic installs)</div>
    ${(Ed.d.piles || []).map((p) => exRow(ED_COL.pile, PILE_NAMES[p] || p, d.stockpiles[p], exBtn('place', HERE, 'Set to where I stand', `data-k="pile" data-p="${p}"`) + exBtn('goto', 'fa-location-arrow', 'Go there', `data-k="pile" data-p="${p}"`) + (d.stockpiles[p] ? exBtn('del', 'fa-xmark', 'Remove', `data-k="pile" data-p="${p}"`) : ''))).join('')}
    ` : '<div class="note" style="margin-top:12px"><i class="fa-solid fa-circle-info"></i><span>Set a job to unlock the boss desk, drop point, work truck, paint booths and part racks.</span></div>'}`}`;

  const foot = $('#exFoot');
  foot.innerHTML = d ? `${!Ed.isNew && (d.edited || d.created) ? `<button class="btn warn" id="exReset"><i class="fa-solid fa-rotate-left"></i>${d.created ? 'Delete shop' : 'Back to config'}</button>` : ''}
    ${!Ed.isNew && !d.created ? '<button class="btn" id="exDisable" title="Hide this shop"><i class="fa-solid fa-eye-slash"></i></button>' : ''}
    <span class="grow"></span><button class="btn pri" id="exSave"><i class="fa-solid fa-floppy-disk"></i>Save</button>` : '';

  // inputs
  const bind = (sel, fn) => { const e = $(sel, body); if (e) e.oninput = () => { fn(e.value); }; };
  if (d) {
    bind('#exId', (v) => (d.id = v.toLowerCase().replace(/[^a-z0-9_]/g, '_')));
    bind('#exLabel', (v) => (d.label = v));
    bind('#exJob', (v) => { const had = !!d.job; d.job = v.trim(); if (had !== !!d.job) { Ed.render(); const j = $('#exJob'); if (j) { j.focus(); j.setSelectionRange(j.value.length, j.value.length); } } });
    bind('#exMode', (v) => (d.mode = v));
    const cl = $('#exClaim', body); if (cl) cl.onchange = () => (d.claimBays = cl.value === 'on' ? true : cl.value === 'off' ? false : 'auto');
    const sr = $('#exSrc', body); if (sr) sr.onchange = () => (d.partSource = sr.value);
    bind('#exBayR', (v) => { d.bayRadius = +v; Ed.sync(); });
    bind('#exSprite', (v) => (d.blip = Object.assign({}, d.blip, { sprite: +v })));
    bind('#exColor', (v) => (d.blip = Object.assign({}, d.blip, { color: +v })));
    bind('#exGa', (v) => (d.grades = Object.assign({}, d.grades, { access: +v })));
    bind('#exGm', (v) => (d.grades = Object.assign({}, d.grades, { manager: +v })));
    bind('#exGb', (v) => (d.grades = Object.assign({}, d.grades, { boss: +v })));
    $$('[data-br]', body).forEach((e) => (e.oninput = () => { d.booths[+e.dataset.br].radius = +e.value; Ed.sync(); }));
    $$('[data-bayr]', body).forEach((e) => (e.oninput = () => { const b = d.bays[+e.dataset.bayr]; if (e.value === '') delete b.r; else b.r = clamp(+e.value, 1, 10); Ed.sync(); }));
  }
  $('#exShop').onchange = (e) => Ed.pick(e.target.value);
  $('#exNew').onclick = Ed.newShop;
  $$('[data-act]', body).forEach((b) => (b.onclick = () => Ed.act(b.dataset)));
  const save = $('#exSave');
  if (save) save.onclick = Ed.save;
  const reset = $('#exReset');
  if (reset) reset.onclick = (e) => Ed.twoTap(e.currentTarget, async () => { const r = await post('ed:reset', { id: d.id }); Ed.after(r, d.id, d.created ? 'Shop deleted.' : 'Back to the config file values.'); });
  const dis = $('#exDisable');
  if (dis) dis.onclick = (e) => Ed.twoTap(e.currentTarget, async () => { const r = await post('ed:disable', { id: d.id }); Ed.after(r, null, 'Shop hidden. "Back to config" brings it back.'); });
};

Ed.twoTap = function (btn, fn) {
  if (btn.dataset.c === '1') return fn();
  btn.dataset.c = '1';
  const old = btn.innerHTML;
  btn.innerHTML = '<i class="fa-solid fa-triangle-exclamation"></i>Tap again';
  setTimeout(() => { if (btn.isConnected) { btn.dataset.c = ''; btn.innerHTML = old; } }, 2500);
};

Ed.after = function (r, keep, msg) {
  if (!r || !r.ok) return flash((r && r.error) || 'That did not work.');
  Ed.shops = r.data;
  flash(msg, 's');
  Ed.pick(keep && Ed.shops.some((s) => s.id === keep) ? keep : Ed.shops[0] && Ed.shops[0].id);
};

Ed.act = function (ds) {
  const d = Ed.draft;
  const k = ds.k, i = ds.i != null ? +ds.i : null;
  const coordsOf = () => (k === 'bay' ? d.bays[i] : k === 'booth' ? d.booths[i].coords : k === 'pile' ? d.stockpiles[ds.p] : d[k]);
  if (ds.act === 'goto') { const c = coordsOf(); if (c) post('ed:goto', c); return; }
  if (ds.act === 'clear') { d[k] = null; Ed.render(); return Ed.sync(); }
  if (ds.act === 'del') {
    if (k === 'bay') d.bays.splice(i, 1);
    else if (k === 'booth') d.booths.splice(i, 1);
    else if (k === 'pile') delete d.stockpiles[ds.p];
    Ed.render();
    return Ed.sync();
  }
  const kind = k === 'truckSpawn' ? 'truck' : k;
  if (ds.act === 'add') {
    if (k === 'bay') return Ed.place('bay', (c) => d.bays.push(c));
    if (k === 'booth') return Ed.place('booth', (c) => d.booths.push({ coords: { x: c.x, y: c.y, z: c.z }, radius: 4.5 }));
  }
  if (ds.act === 'place') {
    if (k === 'bay') return Ed.place('bay', (c) => (d.bays[i] = Object.assign(c, d.bays[i].r != null ? { r: d.bays[i].r } : {})));
    if (k === 'booth') return Ed.place('booth', (c) => (d.booths[i].coords = { x: c.x, y: c.y, z: c.z }));
    if (k === 'pile') return Ed.place('pile', (c) => (d.stockpiles[ds.p] = { x: c.x, y: c.y, z: c.z }));
    if (k === 'truckSpawn') return Ed.place(kind, (c) => (d.truckSpawn = c));
    return Ed.place(kind, (c) => (d[k] = { x: c.x, y: c.y, z: c.z }));
  }
};

Ed.save = async function () {
  const d = Ed.draft;
  if (Ed.isNew && !/^[a-z0-9_]{2,40}$/.test(d.id || '')) return flash('Give the shop an id: lowercase letters, numbers and _.');
  if (!d.label || d.label.length < 2) return flash('Give the shop a name.');
  if (!d.center) return flash('Place the shop centre first.');
  const data = {
    label: d.label, mode: d.mode, job: d.job || false, bayRadius: d.bayRadius || 2.4, blip: d.blip, center: d.center,
    bays: d.bays, booths: d.booths, stockpiles: d.stockpiles, boss: d.boss || false, drop: d.drop || false, truckSpawn: d.truckSpawn || false,
    storage: d.storage || false,
  };
  if (d.job) { data.claimBays = d.claimBays == null ? 'auto' : d.claimBays; data.partSource = d.partSource || 'default'; }
  if (d.job) data.grades = d.grades || { access: 0, manager: 2, boss: 3 };
  const r = await post('ed:save', { id: d.id, data });
  Ed.after(r, d.id, 'Saved. Everyone sees it right away.');
};

$('#exClose').onclick = Ed.close;
$('#exWalkBtn').onclick = () => post('ed:walk');
const claimVal = (d) => (d.claimBays === true ? 'on' : d.claimBays === false ? 'off' : 'auto');
