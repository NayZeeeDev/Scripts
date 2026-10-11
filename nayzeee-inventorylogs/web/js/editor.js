'use strict';
/* ═══ path + diff helpers ═══════════════════════════════════════════════ */
const SPECIAL = ['__vec3', '__vec4', '__vec2', '__fn', '__raw', '__hash'];
const isSpecial = o => o && typeof o === 'object' && SPECIAL.some(k => k in o);
const isPlain = o => o && typeof o === 'object' && !Array.isArray(o) && !isSpecial(o);
const splitPath = p => String(p).split('.').filter(Boolean).map(s => /^\d+$/.test(s) ? +s : s);
function getPath(o, p) { for (const k of splitPath(p)) { if (o == null) return undefined; o = o[k]; } return o; }
function setPath(o, p, v) {
  const ks = splitPath(p);
  let cur = o;
  ks.forEach((k, i) => {
    if (i === ks.length - 1) { if (v === undefined) { if (Array.isArray(cur)) cur[k] = undefined; else delete cur[k]; } else cur[k] = v; return; }
    if (cur[k] == null || typeof cur[k] !== 'object') cur[k] = typeof ks[i + 1] === 'number' ? [] : {};
    cur = cur[k];
  });
  // drop parents that became empty objects
  for (let i = ks.length - 1; i > 0 && v === undefined; i--) {
    const parent = getPath(o, ks.slice(0, i).join('.'));
    if (isPlain(parent) && !Object.keys(parent).filter(k => k !== '__empty').length) setPath(o, ks.slice(0, i).join('.'), undefined); else break;
  }
}
function clean(v) {
  if (Array.isArray(v)) return v.filter(x => x !== undefined && x !== null).map(clean);
  if (v && typeof v === 'object') { const o = {}; Object.keys(v).forEach(k => { if (k === '__empty' || v[k] === undefined) return; o[k] = clean(v[k]); }); return o; }
  return v;
}
const same = (a, b) => JSON.stringify(clean(a)) === JSON.stringify(clean(b));
function diffOps(a, b, path = [], ops = []) {
  a = a || {}; b = b || {};
  const keys = new Set([...Object.keys(a), ...Object.keys(b)].filter(k => k !== '__empty'));
  keys.forEach(k => {
    const x = a[k], y = b[k], p = path.concat(k);
    if (y === undefined) { if (x !== undefined) ops.push({ path: p, unset: true }); return; }
    if (x === undefined) { ops.push({ path: p, value: clean(y) }); return; }
    if (isPlain(x) && isPlain(y)) return diffOps(x, y, p, ops);
    if (!same(x, y)) ops.push({ path: p, value: clean(y) });
  });
  return ops;
}

/* ═══ editor state ══════════════════════════════════════════════════════ */
const ED = {};   // file -> state
const ed = f => (ED[f] = ED[f] || { mode: 'form' });
let curFile = null;

async function edLoadList(file, collection) {
  const st = ed(file);
  const r = await rpc('ed:list', { file, collection: collection ?? st.collection });
  if (!r.ok) { toast(r.err, 'error'); st.error = r.err; st.list = null; return rerender(); }
  st.list = r.data; st.error = r.data.error; st.collection = r.data.collection;
  rerender();
}
async function edOpen(file, key) {
  const st = ed(file);
  const r = await rpc('ed:get', { file, collection: st.collection, key });
  if (!r.ok) { toast(r.err, 'error'); return; }
  st.sel = r.data.key; st.entry = r.data; st.draft = clone(r.data.value) || {}; st.code = r.data.source; st.keyDraft = String(r.data.key);
  st.creating = false; st.dirty = false; st.result = null;
  if (r.data.fn && st.mode === 'form' && !FORMS[r.data.kind]) st.mode = 'code';
  rerender();
}
function markDirty() { const st = ed(curFile); if (!st.dirty) { st.dirty = true; const d = $('#ed-dirty'); if (d) d.classList.remove('hide'); } }

const TEMPLATES = {
  item: () => ({ label: '', weight: 100 }),
  weapon: c => c === 'Weapons' ? { label: '', weight: 1000, durability: 0.1, ammoname: '' } : { label: '', weight: 100 },
  shop: () => ({ name: 'New shop', inventory: [], locations: [] }),
  stash: () => ({ name: '', label: '', slots: 50, weight: 100000, coords: { __vec3: [0, 0, 0] } }),
  crafting: () => ({ name: '', items: [], points: [] }),
  qbitem: () => ({ label: '', weight: 100, type: 'item', unique: false, useable: false, shouldClose: true }),
  qbweapon: () => ({ label: '', weapontype: 'Pistol', ammotype: 'AMMO_PISTOL' }),
  qbshop: () => ({ label: 'New shop', coords: { __vec4: [0, 0, 0, 0] }, ped: 'mp_m_shopkeep_01', scenario: 'WORLD_HUMAN_STAND_MOBILE', radius: 1.5, targetIcon: 'fas fa-shopping-basket', targetLabel: 'Open Shop', showblip: true, blipsprite: 52, blipscale: 0.6, blipcolor: 0 }),
  qbproducts: () => [],
};
const ITEMISH = { item: 1, weapon: 1, qbitem: 1 };
const imageOf = (kind, d) => kind === 'qbitem' ? (d && typeof d.image === 'string' ? d.image : null) : getPath(d || {}, 'client.image');

/* ═══ form widgets ══════════════════════════════════════════════════════ */
const val = p => getPath(ed(curFile).draft, p);
function fText(p, label, o = {}) {
  const v = val(p);
  if (v !== undefined && typeof v === 'object') return `<div class="field ${o.span ? 'span' : ''}"><label>${esc(label)}</label><div class="note"><i class="fas fa-code"></i><div>This uses a custom value. Edit it in the Lua code tab.</div></div></div>`;
  return `<div class="field ${o.span ? 'span' : ''}"><label>${esc(label)}${o.hint ? `<small>${esc(o.hint)}</small>` : ''}</label>${o.area ? `<textarea class="txt" rows="${o.rows || 2}" data-in="edF" data-p="${p}" data-t="str" placeholder="${esc(o.ph || '')}">${esc(v ?? '')}</textarea>` : `<input class="inp" data-in="edF" data-p="${p}" data-t="str" value="${esc(v ?? '')}" placeholder="${esc(o.ph || '')}" ${o.list ? `list="${o.list}"` : ''}>`}${o.help ? `<div class="hint">${esc(o.help)}</div>` : ''}</div>`;
}
function fNum(p, label, o = {}) {
  const v = val(p);
  return `<div class="field ${o.span ? 'span' : ''}"><label>${esc(label)}${o.hint ? `<small>${esc(o.hint)}</small>` : ''}</label><input class="inp" type="number" step="${o.step || 'any'}" data-in="edF" data-p="${p}" data-t="num" value="${esc(v ?? '')}" placeholder="${esc(o.ph ?? '')}">${o.help ? `<div class="hint">${esc(o.help)}</div>` : ''}</div>`;
}
function fBool(p, label, def, o = {}) {
  const v = val(p);
  const on = v === undefined ? def : !!v;
  return `<label class="chk ${o.span ? 'span' : ''}" style="${o.span ? 'grid-column:1/-1' : ''}"><input type="checkbox" data-ch="edB" data-p="${p}" data-def="${def ? 1 : 0}" ${on ? 'checked' : ''}><span class="box"></span>${esc(label)}</label>`;
}
function fVec(p, label, o = {}) {
  const v = val(p);
  const arr = v && v.__vec3 ? v.__vec3 : v && v.__vec4 ? v.__vec4 : null;
  const kind = (v && v.__vec4) || (!arr && o.vec4) ? '__vec4' : '__vec3';
  const n = kind === '__vec4' ? 4 : 3;
  const a = arr || new Array(n).fill('');
  return `<div class="field ${o.span === false ? '' : 'span'}"><label>${esc(label)}</label><div class="vec ${n === 4 ? 'v4' : ''}">${a.map((x, i) => `<input class="inp num" type="number" step="any" data-in="edV" data-p="${p}" data-k="${kind}" data-i="${i}" data-n="${n}" value="${esc(x)}" placeholder="${'xyzw'[i]}">`).join('')}${btn('Capture', 'edHere', 'sm', { v: `${p}|${kind}`, icon: 'fas fa-crosshairs', title: 'Hide the panel and pick a point in the world' })}</div></div>`;
}
function normGroups(g) {
  if (g == null) return [];
  if (typeof g === 'string') return [{ name: g, grade: 0 }];
  if (Array.isArray(g)) return g.map(x => ({ name: x, grade: 0 }));
  return Object.keys(g).filter(k => k !== '__empty').map(k => ({ name: k, grade: g[k] }));
}
function fGroups(p, label) {
  const rows = normGroups(val(p));
  return `<div class="field span"><label>${esc(label)}<small>leave empty for everyone</small></label><div class="rows" data-groups="${p}">
    ${rows.map((r, i) => `<div class="rowline" style="grid-template-columns:1fr 110px auto"><input class="inp sm" data-in="edGrp" data-p="${p}" value="${esc(r.name)}" placeholder="job or gang name"><input class="inp sm num" type="number" data-in="edGrp" data-p="${p}" value="${esc(r.grade)}" placeholder="min grade">${btn('', 'edGrpDel', 'xs btn-ghost', { v: `${p}|${i}`, icon: 'fas fa-xmark' })}</div>`).join('')}
    </div><div>${btn('Add group', 'edGrpAdd', 'xs btn-ghost', { v: p, icon: 'fas fa-plus' })}</div></div>`;
}
function readGroups(p) {
  const box = $(`[data-groups="${p}"]`); if (!box) return;
  const map = {};
  $$('.rowline', box).forEach(r => { const [n, g] = $$('input', r); if (n.value.trim()) map[n.value.trim()] = +g.value || 0; });
  setPath(ed(curFile).draft, p, Object.keys(map).length ? map : undefined);
  markDirty();
}
function customNote(text) { return `<div class="note span" style="grid-column:1/-1"><i class="fas fa-code"></i><div>${text}</div></div>`; }
function fSel(p, label, options, o = {}) {
  const v = val(p);
  const cur = v === undefined ? (o.def ?? '') : v;
  return `<div class="field ${o.span ? 'span' : ''}"><label>${esc(label)}${o.hint ? `<small>${esc(o.hint)}</small>` : ''}</label><select class="inp sel" data-ch="edSel" data-p="${p}">${options.map(([k, l]) => `<option value="${esc(k)}" ${String(k) === String(cur) ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select>${o.help ? `<div class="hint">${esc(o.help)}</div>` : ''}</div>`;
}
CH.edSel = (v, el) => { setPath(ed(curFile).draft, el.dataset.p, v === '' ? undefined : v); markDirty(); };
/** comma separated names <-> Lua array of strings */
function fList(p, label, o = {}) {
  const v = val(p);
  if (v && typeof v === 'object' && !Array.isArray(v)) return `<div class="field ${o.span ? 'span' : ''}"><label>${esc(label)}</label><div class="note"><i class="fas fa-code"></i><div>Uses a custom table. Edit it in the Lua code tab.</div></div></div>`;
  const text = Array.isArray(v) ? v.filter(Boolean).join(', ') : (v ?? '');
  return `<div class="field ${o.span ? 'span' : ''}"><label>${esc(label)}${o.hint ? `<small>${esc(o.hint)}</small>` : ''}</label><input class="inp" data-in="edList" data-p="${p}" value="${esc(text)}" placeholder="${esc(o.ph || '')}"></div>`;
}
IN.edList = (v, el) => { const list = v.split(',').map(x => x.trim()).filter(Boolean); setPath(ed(curFile).draft, el.dataset.p, list.length ? list : undefined); markDirty(); };
function imageBlock(key, img, field, help) {
  const st = ed(curFile);
  return `<div class="drop-img" data-drop="img">${thumb(key, st.pendingImg || img, 'lg')}<div class="stack" style="gap:8px;flex:1">
    ${imgPicker()}
    ${fText(field, 'Image file', { ph: `${bareKey(key) || 'item'}.png`, help })}</div></div>`;
}
const bareKey = k => String(k ?? '').replace(/`/g, '');
const QB_WEAPON_TYPES = ['Melee', 'Pistol', 'Submachine Gun', 'Shotgun', 'Assault Rifle', 'Light Machine Gun', 'Sniper Rifle', 'Heavy Weapon', 'Throwable', 'Miscellaneous'];
const QB_AMMO = ['AMMO_PISTOL', 'AMMO_SMG', 'AMMO_RIFLE', 'AMMO_SHOTGUN', 'AMMO_MG', 'AMMO_SNIPER', 'AMMO_SNIPER_REMOTE', 'AMMO_RPG', 'AMMO_GRENADELAUNCHER', 'AMMO_STUNGUN', 'AMMO_FIREEXTINGUISHER', 'AMMO_PETROLCAN', 'AMMO_BALL', 'AMMO_FLARE'];
function ammoList() {
  let dl = $('#dl-ammo');
  if (!dl) { dl = document.createElement('datalist'); dl.id = 'dl-ammo'; document.body.appendChild(dl); }
  dl.innerHTML = QB_AMMO.map(a => `<option value="${a}">`).join('');
}

const sect = (title, icon, inner, right = '') => `<div class="sect"><h4><i class="${icon}"></i>${esc(title)}<span class="r">${right}</span></h4>${inner}</div>`;

/* ═══ forms per kind ════════════════════════════════════════════════════ */
const FORMS = {
  item() {
    const st = ed(curFile); const d = st.draft;
    const c = d.client || {};
    const img = typeof c.image === 'string' ? c.image : null;
    const anim = c.anim, prop = c.prop;
    return sect('Basics', 'fas fa-box', `<div class="fgrid">
        ${fText('label', 'Label', { ph: 'Shown to players' })}${fNum('weight', 'Weight', { hint: 'grams', step: 1 })}
        ${fText('description', 'Description', { area: true, span: true, ph: 'Optional text under the item name' })}
        <div class="fgrid c3 span">${fBool('stack', 'Stacks in one slot', true)}${fBool('close', 'Closes inventory on use', true)}${fBool('decay', 'Removed when durability hits 0', false)}</div>
        ${fNum('consume', 'Used up per use', { hint: '1 = one item', help: '0 keeps the item, 0.2 wears it down by 20% each use.' })}${fNum('degrade', 'Degrades over', { hint: 'minutes', step: 1, help: 'Leave empty if it never goes off.' })}
      </div>`) +
      sect('Image', 'fas fa-image', `<div class="drop-img" data-drop="img">${thumb(st.creating ? (st.keyDraft || 'new') : st.sel, st.pendingImg || img, 'lg')}<div class="stack" style="gap:8px;flex:1">
        ${imgPicker()}
        ${fText('client.image', 'Image file or URL', { ph: `${st.keyDraft || 'item'}.png (default)`, help: 'Leave empty to use ox_inventory/web/images/<name>.png. Full https:// links work too.' })}</div></div>`) +
      sect('When used', 'fas fa-hand-pointer', `<div class="fgrid">
        ${fNum('client.status.hunger', 'Hunger', { hint: '1000000 = full', step: 1000 })}${fNum('client.status.thirst', 'Thirst', { step: 1000 })}
        ${fNum('client.status.stress', 'Stress', { step: 1000 })}${fNum('client.usetime', 'Use time', { hint: 'ms', step: 100 })}
        ${typeof anim === 'object' && anim ? customNote('Uses a custom animation table. Edit it in the Lua code tab.') : fText('client.anim', 'Animation', { ph: 'eating, drinking, or a name from animations.lua' })}
        ${typeof prop === 'object' && prop ? customNote('Uses a custom prop table. Edit it in the Lua code tab.') : fText('client.prop', 'Prop', { ph: 'burger, bottle, or a name from animations.lua' })}
        ${fText('client.notification', 'Message after use', { span: true, ph: 'You feel better' })}
        <div class="fgrid c4 span">${fBool('client.cancel', 'Can be cancelled', false)}${fBool('client.disable.move', 'Stop moving', false)}${fBool('client.disable.car', 'Block in cars', false)}${fBool('client.disable.combat', 'Block combat', false)}</div>
      </div>`) +
      sect('With a weapon out', 'fas fa-gun', armedField()) +
      sect('Scripts', 'fas fa-code-branch', `<div class="fgrid">
        ${fText('client.export', 'Client export', { ph: 'resource.function', help: 'Runs on the player when used.' })}${fText('server.export', 'Server export', { ph: 'resource.function', help: 'Runs on the server when used.' })}
        ${st.entry && st.entry.fn ? customNote('This item has Lua functions (buttons or add/remove handlers). They are kept exactly as they are. Edit them in the Lua code tab.') : ''}</div>`);
  },
  weapon() {
    const st = ed(curFile); const c = (st.draft.client || {});
    const isW = st.collection === 'Weapons';
    return sect('Basics', 'fas fa-gun', `<div class="fgrid">${fText('label', 'Label')}${fNum('weight', 'Weight', { hint: 'grams', step: 1 })}
        ${isW ? fNum('durability', 'Wear per shot', { hint: '0.01 to 1', help: 'How much durability each shot uses.' }) + fText('ammoname', 'Ammo item', { list: 'dl-items', ph: 'ammo-9' }) : ''}
        ${isW ? fBool('throwable', 'Throwable (stacks)', false) : ''}
        ${st.collection === 'Components' ? fText('type', 'Component type', { ph: 'suppressor, flashlight, magazine...' }) : ''}</div>`) +
      sect('Image', 'fas fa-image', `<div class="drop-img" data-drop="img">${thumb(st.creating ? (st.keyDraft || 'new') : st.sel, st.pendingImg || (typeof c.image === 'string' ? c.image : null), 'lg')}<div class="stack" style="gap:8px;flex:1">
        ${imgPicker()}
        ${fText('client.image', 'Image file or URL', { ph: 'default: <name>.png' })}</div></div>`) +
      (st.collection === 'Components' ? customNote('The component hash list lives in the Lua code tab.') : '');
  },
  shop() {
    const st = ed(curFile); const d = st.draft;
    const inv = Array.isArray(d.inventory) ? d.inventory : [];
    const locs = Array.isArray(d.locations) ? d.locations : [];
    const rows = inv.map((it, i) => it ? `<div class="rowline" style="grid-template-columns:34px 1.6fr .8fr .7fr .9fr .9fr .6fr auto">${thumb(it.name || '')}
        <input class="inp sm" list="dl-items" data-in="edF" data-p="inventory.${i}.name" data-t="str" value="${esc(it.name || '')}" placeholder="item">
        <input class="inp sm num" type="number" data-in="edF" data-p="inventory.${i}.price" data-t="num" value="${esc(it.price ?? '')}" placeholder="price">
        <input class="inp sm num" type="number" data-in="edF" data-p="inventory.${i}.count" data-t="num" value="${esc(it.count ?? '')}" placeholder="stock">
        <input class="inp sm" data-in="edF" data-p="inventory.${i}.currency" data-t="str" value="${esc(it.currency ?? '')}" placeholder="money">
        <input class="inp sm" data-in="edF" data-p="inventory.${i}.license" data-t="str" value="${esc(it.license ?? '')}" placeholder="license">
        <input class="inp sm num" type="number" data-in="edF" data-p="inventory.${i}.grade" data-t="num" value="${typeof it.grade === 'number' ? esc(it.grade) : ''}" placeholder="grade">
        ${btn('', 'edRowDel', 'xs btn-ghost', { v: `inventory|${i}`, icon: 'fas fa-xmark' })}</div>` : '').join('');
    return sect('Basics', 'fas fa-store', `<div class="fgrid">${fText('name', 'Shop name')}${fText('label', 'Prompt text', { ph: 'Open shop (optional)' })}
        <div class="fgrid c3 span">${fNum('blip.id', 'Blip sprite', { step: 1, ph: 'none' })}${fNum('blip.colour', 'Blip colour', { step: 1 })}${fNum('blip.scale', 'Blip scale', { step: 0.1 })}</div>
        ${fGroups('groups', 'Only these jobs')}</div>`) +
      sect(`Stock (${inv.filter(Boolean).length})`, 'fas fa-tags', `<div class="rows">${inv.length ? `<div class="rowline muted" style="grid-template-columns:34px 1.6fr .8fr .7fr .9fr .9fr .6fr 22px;font-size:10px"><span></span><span>Item</span><span>Price</span><span>Stock</span><span>Currency</span><span>License</span><span>Grade</span><span></span></div>` : ''}${rows || '<span class="muted">No items for sale yet.</span>'}</div>`, btn('Add item', 'edRowAdd', 'xs', { v: 'inventory', icon: 'fas fa-plus' })) +
      sect(`Locations (${locs.length})`, 'fas fa-location-dot', `<div class="stack" style="gap:8px">${locs.map((l, i) => `<div class="rowline" style="grid-template-columns:1fr auto">${fVec(`locations.${i}`, `Location ${i + 1}`, { span: false })}${btn('', 'edRowDel', 'xs btn-ghost', { v: `locations|${i}`, icon: 'fas fa-xmark' })}</div>`).join('') || '<span class="muted">No marker locations.</span>'}
        ${d.targets ? customNote('This shop also has ox_target zones (targets). Edit those in the Lua code tab.') : ''}${d.model ? customNote('This shop uses ped models for targeting. Edit them in the Lua code tab.') : ''}</div>`, btn('Capture location', 'edRowAdd', 'xs', { v: 'locations', icon: 'fas fa-crosshairs' }));
  },
  stash() {
    const d = ed(curFile).draft;
    return sect('Stash', 'fas fa-warehouse', `<div class="fgrid">${fText('name', 'Id', { help: 'Unique id other scripts use to open it.' })}${fText('label', 'Label')}
        ${fNum('slots', 'Slots', { step: 1 })}${fNum('weight', 'Max weight', { hint: 'grams', step: 1000 })}
        ${fBool('owner', 'Personal (each player gets their own)', false, { span: true })}
        ${fVec('coords', 'Marker position')}${fGroups('groups', 'Only these jobs')}
        ${d.target ? customNote('Has an ox_target zone. Edit the zone in the Lua code tab.') : ''}</div>`);
  },
  crafting() {
    const st = ed(curFile); const d = st.draft;
    const recipes = Array.isArray(d.items) ? d.items : [];
    const points = Array.isArray(d.points) ? d.points : [];
    const recipe = (r, i) => {
      if (!r) return '';
      const ing = r.ingredients && typeof r.ingredients === 'object' ? Object.keys(r.ingredients).filter(k => k !== '__empty') : [];
      return `<div class="card" style="margin-bottom:8px"><div class="card-b"><div class="rowline" style="grid-template-columns:34px 1.6fr .7fr .8fr auto;margin-bottom:8px">${thumb(r.name || '')}
          <input class="inp sm" list="dl-items" data-in="edF" data-p="items.${i}.name" data-t="str" value="${esc(r.name || '')}" placeholder="crafted item">
          <input class="inp sm num" type="number" data-in="edF" data-p="items.${i}.count" data-t="num" value="${esc(r.count ?? '')}" placeholder="makes">
          <input class="inp sm num" type="number" data-in="edF" data-p="items.${i}.duration" data-t="num" value="${esc(r.duration ?? '')}" placeholder="time ms">
          ${btn('', 'edRowDel', 'xs btn-ghost', { v: `items|${i}`, icon: 'fas fa-trash' })}</div>
        <div class="rows" style="padding-left:42px">${ing.map(k => `<div class="rowline" style="grid-template-columns:1fr 110px auto"><input class="inp sm" list="dl-items" value="${esc(k)}" data-ch="edIngName" data-p="items.${i}.ingredients" data-old="${esc(k)}"><input class="inp sm num" type="number" step="any" data-in="edF" data-p="items.${i}.ingredients.${k}" data-t="num" value="${esc(r.ingredients[k])}">${btn('', 'edIngDel', 'xs btn-ghost', { v: `items.${i}.ingredients|${k}`, icon: 'fas fa-xmark' })}</div>`).join('')}
          <div>${btn('Add ingredient', 'edIngAdd', 'xs btn-ghost', { v: `items.${i}.ingredients`, icon: 'fas fa-plus' })} <span class="muted" style="font-size:10px">Amounts under 1 use durability instead of the whole item.</span></div></div></div></div>`;
    };
    return sect('Bench', 'fas fa-screwdriver-wrench', `<div class="fgrid">${fText('name', 'Id')}${fText('label', 'Label')}
        ${fNum('blip.id', 'Blip sprite', { step: 1, ph: 'none' })}${fNum('blip.colour', 'Blip colour', { step: 1 })}${fGroups('groups', 'Only these jobs')}</div>`) +
      sect(`Recipes (${recipes.filter(Boolean).length})`, 'fas fa-flask', recipes.map(recipe).join('') || '<span class="muted">No recipes yet.</span>', btn('Add recipe', 'edRowAdd', 'xs', { v: 'items', icon: 'fas fa-plus' })) +
      sect(`Locations (${points.length})`, 'fas fa-location-dot', `<div class="stack" style="gap:8px">${points.map((l, i) => `<div class="rowline" style="grid-template-columns:1fr auto">${fVec(`points.${i}`, `Bench ${i + 1}`, { span: false })}${btn('', 'edRowDel', 'xs btn-ghost', { v: `points|${i}`, icon: 'fas fa-xmark' })}</div>`).join('') || '<span class="muted">No marker locations.</span>'}
        ${d.zones ? customNote('Has ox_target zones. Edit those in the Lua code tab.') : ''}</div>`, btn('Capture location', 'edRowAdd', 'xs', { v: 'points', icon: 'fas fa-crosshairs' }));
  },
  qbitem() {
    const st = ed(curFile); const d = st.draft;
    ammoList();
    const key = st.creating ? (st.keyDraft || 'new') : String(st.sel);
    return sect('Basics', 'fas fa-box', `<div class="fgrid">
        ${fText('label', 'Label', { ph: 'Shown to players' })}${fNum('weight', 'Weight', { hint: 'grams', step: 1 })}
        ${fSel('type', 'Type', [['item', 'Item'], ['weapon', 'Weapon']], { def: 'item' })}${d.type === 'weapon' ? fText('ammotype', 'Ammo type', { list: 'dl-ammo', ph: 'AMMO_PISTOL' }) : '<div></div>'}
        ${fText('description', 'Description', { area: true, span: true, ph: 'Shown under the item name' })}
        <div class="fgrid c3 span">${fBool('unique', 'Unique (one per slot)', false)}${fBool('useable', 'Can be used', false)}${fBool('shouldClose', 'Closes inventory on use', false)}</div>
      </div>`) +
      sect('Image', 'fas fa-image', imageBlock(key, typeof d.image === 'string' ? d.image : null, 'image', `File in ${S.boot.inventory.resource}/html/images. Upload a PNG to replace it.`)) +
      sect('Decay', 'fas fa-hourglass-half', `<div class="fgrid">${fNum('decay', 'Decays over', { hint: 'days', step: 0.5, ph: 'never', help: 'Leave empty if it never goes off.' })}${fBool('delete', 'Removed when fully decayed', false)}</div>`) +
      (d.combinable ? customNote('This item can be combined with others. Edit the combinable table in the Lua code tab.') : '');
  },
  qbweapon() {
    ammoList();
    return sect('Weapon', 'fas fa-gun', `<div class="fgrid">
        ${fText('label', 'Label')}${fSel('weapontype', 'Weapon type', QB_WEAPON_TYPES.map(t => [t, t]), { def: 'Pistol' })}
        ${fText('ammotype', 'Ammo type', { list: 'dl-ammo', ph: 'AMMO_PISTOL' })}<div></div>
        ${fText('damagereason', 'Death message', { span: true, ph: 'Pistoled / Blasted / Plugged', help: 'Shown in kill feeds and death logs.' })}</div>`) +
      customNote('The item players carry (label, weight, image) is in Items. This file only describes how the gun behaves.');
  },
  qbshop() {
    const st = ed(curFile); const d = st.draft;
    const ref = st.entry && st.entry.refs && st.entry.refs.products;
    const rawP = (d.products && d.products.__raw) || (st.entry && st.entry.raw && st.entry.raw.products) || '';
    const curList = (String(rawP).match(/\[['"](.+?)['"]\]/) || String(rawP).match(/\.([\w]+)$/) || [])[1] || '';
    const products = ref ? `<div class="field"><label>Sells<small>a product list</small></label><select class="inp sel" data-ch="qbShopList">${!curList ? '<option value="">Custom (Lua code tab)</option>' : ''}${ref.options.map(o => `<option value="${esc(o)}" ${o === curList ? 'selected' : ''}>${esc(o)}</option>`).join('')}</select><div class="hint">${curList ? `${btn('Edit this list', 'qbShopEditList', 'xs btn-ghost', { v: curList, icon: 'fas fa-pen' })}` : ''}</div></div>` : customNote('Products are set in the Lua code tab.');
    const sample = Array.isArray(d.products) ? d.products.filter(Boolean) : [];
    return sect('Shop', 'fas fa-store', `<div class="fgrid">${fText('label', 'Name')}${products}
        ${sample.length ? `<div class="span row-btns" style="gap:6px">${sample.slice(0, 14).map(x => `<span class="chip">${esc(itemLabel(x.name))} <span class="muted">$${num(x.price)}</span></span>`).join('')}${sample.length > 14 ? `<span class="muted">+${sample.length - 14} more</span>` : ''}</div>` : ''}</div>`) +
      sect('Shopkeeper', 'fas fa-person', `<div class="fgrid">${fVec('coords', 'Position and heading', { vec4: true })}
        ${fText('ped', 'Ped model', { ph: 'mp_m_shopkeep_01' })}${fText('scenario', 'Idle animation', { ph: 'WORLD_HUMAN_STAND_MOBILE' })}
        ${fNum('radius', 'Interact radius', { step: 0.1 })}${fText('targetLabel', 'Target text', { ph: 'Open Shop' })}
        ${fText('targetIcon', 'Target icon', { ph: 'fas fa-shopping-basket' })}<div></div></div>`) +
      sect('Map blip', 'fas fa-location-dot', `<div class="fgrid c4">${fBool('showblip', 'Show on map', false)}${fNum('blipsprite', 'Sprite', { step: 1 })}${fNum('blipscale', 'Scale', { step: 0.1 })}${fNum('blipcolor', 'Colour', { step: 1 })}</div>`) +
      sect('Access and delivery', 'fas fa-lock', `<div class="fgrid">${fList('requiredJob', 'Only these jobs', { ph: 'police, mechanic', hint: 'comma separated' })}${fList('requiredGang', 'Only these gangs', { ph: 'ballas', hint: 'comma separated' })}
        ${d.delivery ? fVec('delivery', 'Restock delivery point', { vec4: true }) : `<div class="field span"><label>Restock delivery point</label><div>${btn('Capture delivery point', 'qbShopDelivery', 'xs', { icon: 'fas fa-crosshairs' })}</div></div>`}</div>`);
  },
  qbproducts() {
    const st = ed(curFile);
    const list = Array.isArray(st.draft) ? st.draft : [];
    const rows = list.map((it, i) => it ? `<div class="rowline" style="grid-template-columns:34px 1.6fr .8fr .8fr 1.3fr auto">${thumb(it.name || '')}
        <input class="inp sm" list="dl-items" data-in="edF" data-p="${i}.name" data-t="str" value="${esc(it.name || '')}" placeholder="item">
        <input class="inp sm num" type="number" data-in="edF" data-p="${i}.price" data-t="num" value="${esc(it.price ?? '')}" placeholder="price">
        <input class="inp sm num" type="number" data-in="edF" data-p="${i}.amount" data-t="num" value="${esc(it.amount ?? '')}" placeholder="stock">
        <input class="inp sm" data-in="qbpJobs" data-i="${i}" value="${esc(Array.isArray(it.requiredJob) ? it.requiredJob.join(', ') : '')}" placeholder="jobs only (optional)">
        ${btn('', 'qbpDel', 'xs btn-ghost', { v: i, icon: 'fas fa-xmark' })}</div>` : '').join('');
    return sect(`Products (${list.filter(Boolean).length})`, 'fas fa-tags', `<div class="rows">${list.length ? `<div class="rowline muted" style="grid-template-columns:34px 1.6fr .8fr .8fr 1.3fr 22px;font-size:10px"><span></span><span>Item</span><span>Price</span><span>Stock</span><span>Jobs</span><span></span></div>` : ''}${rows || '<span class="muted">Nothing for sale yet.</span>'}</div>`, btn('Add item', 'qbpAdd', 'xs', { icon: 'fas fa-plus' })) +
      customNote('Every shop that sells this list updates when you save. qb-shops restarts to load the change.');
  },
};

/* ═══ weapon-out use ═════════════════════════════════════════════════════ */
function weaponOptions() {
  let dl = $('#dl-weapons');
  if (!dl) { dl = document.createElement('datalist'); dl.id = 'dl-weapons'; document.body.appendChild(dl); }
  const list = (S.items || []).filter(i => i.weapon);
  dl.innerHTML = list.map(i => `<option value="${esc(i.name)}">${esc(i.label)}</option>`).join('');
}
function armedField() {
  weaponOptions();
  const on = !!val('allowArmed');
  const list = Array.isArray(val('allowArmedWith')) ? val('allowArmedWith').filter(Boolean) : [];
  const bridge = S.boot.bridge;
  return `<div class="stack" style="gap:10px">
    <label class="chk"><input type="checkbox" data-ch="edArmed" ${on ? 'checked' : ''}><span class="box"></span>Players can use this while holding a weapon</label>
    ${on ? `<div class="field"><label>Only while holding<small>leave empty for any weapon</small></label>
      <div class="row-btns">${list.map((w, i) => `<span class="chip">${esc(itemLabel(w))} <span class="mono muted">${esc(w)}</span><button class="btn xs ico btn-ghost" data-a="edArmedDel" data-v="${i}" title="Remove"><i class="fas fa-xmark"></i></button></span>`).join('')}
        <input class="inp sm" style="width:220px" list="dl-weapons" placeholder="Add a weapon, e.g. WEAPON_PISTOL" data-enter="edArmedAdd" data-ch="edArmedAdd"></div>
      <div class="hint">${list.length ? `Only works with ${list.length === 1 ? 'that weapon' : 'those weapons'} out. Other weapons still block it.` : 'Works with any weapon out, like eating or popping a pill mid-fight.'}${list.length && !bridge ? ' Weapon limits need the ox_inventory bridge. Without it, any weapon is allowed.' : ''}</div></div>` : '<div class="hint">Off: ox_inventory blocks this item while a weapon is out, which is the default for every item.</div>'}
  </div>`;
}
CH.edArmed = v => {
  const st = ed(curFile);
  setPath(st.draft, 'allowArmed', v ? true : undefined);
  if (!v) setPath(st.draft, 'allowArmedWith', undefined);
  markDirty(); rerender();
};
function armedAdd(v, el) {
  const w = String(v || '').trim().toUpperCase();
  if (!w) return;
  const st = ed(curFile);
  if (!S.itemMap[w] && !S.itemMap[w.toLowerCase()]) { toast(`${w} is not an item in weapons.lua`, 'warning'); }
  const list = Array.isArray(getPath(st.draft, 'allowArmedWith')) ? getPath(st.draft, 'allowArmedWith').filter(Boolean) : [];
  if (!list.includes(w)) list.push(w);
  setPath(st.draft, 'allowArmedWith', list);
  if (el) el.value = '';
  markDirty(); rerender();
}
A.edArmedAdd = (v, el) => armedAdd(v, el);
CH.edArmedAdd = (v, el) => armedAdd(v, el);
A.edArmedDel = v => {
  const st = ed(curFile);
  const list = (getPath(st.draft, 'allowArmedWith') || []).filter(Boolean);
  list.splice(+v, 1);
  setPath(st.draft, 'allowArmedWith', list.length ? list : undefined);
  markDirty(); rerender();
};

/* ═══ page factory ══════════════════════════════════════════════════════ */
function codeBox(value, id = 'ed-code', scrollKey = '') {
  const lines = String(value || '').split('\n').length;
  return `<div class="code" id="${id}-wrap"><div class="gut" id="${id}-gut">${Array.from({ length: lines }, (_, i) => i + 1).join('\n')}</div><textarea id="${id}" spellcheck="false" data-in="codeIn"${scrollKey ? ` data-scroll="${esc(scrollKey)}"` : ''}>${esc(value || '')}</textarea></div>`;
}
IN.codeIn = (v, el) => {
  const g = $('#' + el.id + '-gut'); if (g) { const n = v.split('\n').length; if (g.childNodes.length !== n) g.textContent = Array.from({ length: n }, (_, i) => i + 1).join('\n'); }
  if (el.id === 'ed-code') { ed(curFile).code = v; markDirty(); }
  if (el.id === 'raw-code') { pd('files').src = v; pd('files').dirty = true; const d = $('#raw-dirty'); if (d) d.classList.remove('hide'); }
};
document.addEventListener('scroll', e => { const t = e.target; if (t && t.tagName === 'TEXTAREA' && t.id && $('#' + t.id + '-gut')) $('#' + t.id + '-gut').scrollTop = t.scrollTop; }, true);
document.addEventListener('keydown', e => {
  const t = e.target;
  if (e.key === 'Tab' && t.tagName === 'TEXTAREA' && (t.id === 'ed-code' || t.id === 'raw-code')) {
    e.preventDefault();
    const s = t.selectionStart, en = t.selectionEnd;
    t.value = t.value.slice(0, s) + '\t' + t.value.slice(en);
    t.selectionStart = t.selectionEnd = s + 1;
    IN.codeIn(t.value, t);
  }
});

function listRow(file, e, st) {
  const kind = st.list.kind;
  let sub = '';
  if (kind === 'item') sub = `${num(e.weight)}g${e.stack ? '' : ' · single'}${e.usable ? ' · usable' : ''}${e.armed ? ' · usable armed' : ''}${e.degrade ? ' · degrades' : ''}`;
  else if (kind === 'weapon') sub = `${num(e.weight)}g${e.ammo ? ' · ' + e.ammo : ''}`;
  else if (kind === 'shop') sub = `${e.items} items · ${e.locations} locations${e.groups ? ' · job only' : ''}`;
  else if (kind === 'stash') sub = `${e.name || ''} · ${e.slots || '?'} slots${e.owner ? ' · personal' : ''}`;
  else if (kind === 'crafting') sub = `${e.recipes} recipes · ${e.locations} locations`;
  else if (kind === 'license') sub = e.price ? '$' + num(e.price) : '';
  else if (kind === 'qbitem') sub = `${num(e.weight)}g${e.itype === 'weapon' ? ' · weapon' : ''}${e.stack ? '' : ' · unique'}${e.usable ? ' · usable' : ''}`;
  else if (kind === 'qbweapon') sub = `${e.wtype || ''}${e.ammo ? ' · ' + e.ammo : ''}`;
  else if (kind === 'qbshop') sub = `${e.items} products${e.blip ? ' · blip' : ''}${e.job ? ' · job only' : ''}`;
  else if (kind === 'qbproducts') sub = `${e.items} items`;
  const icon = { shop: 'fa-store', qbshop: 'fa-store', qbproducts: 'fa-tags', stash: 'fa-warehouse', crafting: 'fa-screwdriver-wrench', license: 'fa-id-card', evidence: 'fa-box-archive', anim: 'fa-person-running' }[kind];
  const showThumb = ITEMISH[kind] || kind === 'qbweapon';
  return `<div class="li click ${String(st.sel) === String(e.key) && !st.creating ? 'on' : ''}" data-a="edPick" data-v="${esc(e.key)}">
    ${showThumb ? thumb(bareKey(e.key), e.image) : `<div class="thumb"><i class="fas ${icon || 'fa-cube'}"></i></div>`}
    <div class="tx"><b>${esc(e.label)}</b><span>${showThumb ? `<span class="mono">${esc(bareKey(e.key))}</span> · ` : ''}${esc(sub)}</span></div>${e.fn ? '<i class="fas fa-code muted" title="Has Lua functions"></i>' : ''}</div>`;
}

function editorPane(file) {
  const st = ed(file);
  if (!st.creating && st.sel === undefined) return empty('fas fa-pen-to-square', 'Pick something to edit', 'Or create a new one. Saving writes the file, keeps a backup, and pushes it to the server and every player.');
  const kind = st.list.kind;
  const hasForm = !!FORMS[kind];
  const mode = hasForm ? st.mode : 'code';
  const res = st.result && st.result.apply;
  const isArr = Array.isArray(st.draft);
  const title = st.creating ? 'New entry' : (!isArr && (getPath(st.draft, 'label') || getPath(st.draft, 'name')) || bareKey(st.sel));
  const keyed = st.list.keyed;
  const head = `<div class="ed-head">${ITEMISH[kind] || kind === 'qbweapon' ? thumb(bareKey(st.creating ? st.keyDraft || 'new' : st.sel), isArr ? null : imageOf(kind, st.draft)) : ''}
    <div style="min-width:0"><h2 class="ell">${esc(title)} <span id="ed-dirty" class="dirty-dot ${st.dirty ? '' : 'hide'}" style="display:inline-block;vertical-align:middle;margin-left:6px" title="Unsaved changes"></span></h2>
    <p>${st.creating ? 'Not saved yet' : `${esc(st.list.name || file + '.lua')}${st.collection ? ' · ' + esc(st.collection) : ''}`}</p></div>
    <div class="r">${btn(st.creating ? 'Create' : 'Save', 'edSave', 'btn-teal sm', { icon: 'fas fa-floppy-disk' })}
      ${!st.creating ? btn('', 'edDup', 'sm', { icon: 'fas fa-clone', title: 'Duplicate' }) + btn('', 'edDel', 'sm btn-red', { icon: 'fas fa-trash', title: 'Delete' }) : btn('Cancel', 'edCancel', 'sm btn-ghost')}</div></div>`;
  const KEYLABEL = { item: 'Item name', qbitem: 'Item name', qbweapon: 'Weapon name', qbshop: 'Shop id', qbproducts: 'List name' };
  const KEYPH = { item: 'goldbar', qbitem: 'goldbar', weapon: 'WEAPON_NAME', qbweapon: 'weapon_name', qbshop: 'gold_dealer', qbproducts: 'jeweler' };
  const keyField = keyed ? `<div class="fgrid" style="margin-bottom:16px"><div class="field"><label>${KEYLABEL[kind] || 'Name'}<small>${st.creating ? 'lowercase, used by scripts' : 'renaming breaks scripts that use the old name'}</small></label><input class="inp mono" data-in="edKey" value="${esc(bareKey(st.keyDraft || ''))}" placeholder="${KEYPH[kind] || 'Name'}"></div></div>` : '';
  const resNote = res ? (res.ok === false ? note(`Saved to the file, but applying it live failed: ${esc(res.err)}`, 'red', 'fas fa-triangle-exclamation') : res.live ? note(`Saved and live for every player${res.changed !== undefined ? ` (${res.changed} changed)` : ''}.${res.note ? ' ' + esc(res.note) : ''}`, '', 'fas fa-circle-check') : note(esc(res.note || 'Saved.'), 'amber', 'fas fa-clock')) : '';
  // each entry remembers its own scroll position, so adding a row or picking a picture doesn't jump to the top
  const where = `${file}:${st.collection || ''}:${st.creating ? '+new' : bareKey(st.sel)}`;
  let body;
  if (mode === 'form') body = `<div class="ed-body" data-scroll="edbody:${esc(where)}">${resNote ? resNote + '<div style="height:14px"></div>' : ''}${keyField}<div id="ed-form">${FORMS[kind]()}</div></div>`;
  else body = `<div class="ed-body codemode">${resNote ? resNote + '<div style="height:10px"></div>' : ''}${keyed && st.creating ? keyField : ''}
    ${codeBox(st.code ?? '{\n}', 'ed-code', 'edcode:' + where)}
    <div class="codebar">${btn('Check', 'edCheck', 'sm', { icon: 'fas fa-spell-check' })}<span class="msg" id="ed-check">This is the entry's Lua table exactly as it sits in ${esc(st.list.name || file + '.lua')}.</span></div></div>`;
  const modeTabs = hasForm ? tabs([['form', 'Form', 'fas fa-sliders'], ['code', 'Lua code', 'fas fa-code']], mode, 'edMode') : '';
  return head + modeTabs + body;
}

function edPage(key, label, icon) {
  const files = () => ((invPage(key) || {}).files || []);
  const F = () => pd(key).file || (files()[0] || {}).id;
  const extraHead = () => files().length > 1 ? seg(files().map(f => [f.id, f.label]), F(), 'edTab') : '';
  page(key, {
    label, icon, tier: 'editor', when: () => S.boot.editor && !!invPage(key),
    async enter() {
      const file = F();
      curFile = file;
      A.hotSave = () => A.edSave();
      await loadItems();
      const st = ed(file);
      if (!st.list) await edLoadList(file); else { rerender(); edLoadList(file); }
    },
    leave() { A.hotSave = null; },
    async canLeave() {
      const st = ed(F());
      if (!st.dirty) return true;
      const ok = await confirmBox('Leave without saving?', 'Your unsaved changes will be lost.', { ok: 'Discard changes', tone: 'amber', icon: 'fas fa-triangle-exclamation' });
      if (ok) st.dirty = false;
      return !!ok;
    },
    render() {
      const file = F();
      curFile = file;
      const st = ed(file);
      const P = PAGES[key];
      const bridge = S.boot.bridge;
      const inv = S.boot.inventory || {};
      const bridgeWarn = bridge ? '' : `<span class="livechip warn"><span class="dot"></span>Saves need a ${esc(inv.resource || 'inventory')} restart until the bridge is installed</span>`;
      const head = ph(P.label, st.list && st.list.path ? st.list.path : '', `${bridgeWarn}${btn('', 'edReload', 'btn-ghost sm', { icon: 'fas fa-rotate', title: 'Reload from disk' })}`);
      if (!st.list) return head + `<div class="content">${st.error ? empty('fas fa-triangle-exclamation', 'Could not read the file', st.error) : loading()}</div>`;
      if (st.error) return head + `<div class="content">${note(`<b>${esc(st.list.name || file)} has an error, so the form view is off.</b> ${esc(st.error)}. Fix it in Code &amp; backups, or restore a backup.`, 'red', 'fas fa-triangle-exclamation')}<div style="height:12px"></div>${btn('Open Code & backups', 'edGoFiles', 'btn-teal', { v: file, icon: 'fas fa-file-code' })}</div>`;
      const q = (st.q || '').toLowerCase();
      const rows = (st.list.entries || []).filter(e => !q || [e.key, e.label, e.name, e.description].join(' ').toLowerCase().includes(q));
      const cats = st.list.collections ? seg(st.list.collections.map(c => [c.id, `${c.id} (${c.count})`]), st.collection, 'edCat') : '';
      const warn = bridge ? '' : `<div class="note amber" style="padding:8px 10px"><i class="fas fa-clock"></i><div>Bridge not installed, saves apply after ${esc(inv.resource || 'the inventory')} restarts.</div></div>`;
      const left = `<div class="pane-l wide ed-list"><div class="pane-h">${extraHead()}${cats}${warn}<div style="display:flex;gap:6px"><div class="search"><i class="fas fa-magnifying-glass"></i><input class="inp" data-in="edQ" value="${esc(st.q || '')}" placeholder="Search ${rows.length} of ${(st.list.entries || []).length}"></div>${btn('', 'edReload', 'btn-ghost ico', { icon: 'fas fa-rotate', title: 'Reload from disk' })}${btn('New', 'edNew', 'btn-teal', { icon: 'fas fa-plus' })}</div>
        ${IMPORT_KINDS[st.list.kind] ? btn('Import a new script\'s items & pictures', 'edImport', 'sm btn-ghost full', { icon: 'fas fa-file-import', title: 'Installing a new script? Drop its pictures and item list here, no restart needed' }) : ''}</div>
        <div class="pane-b" id="ed-list" data-scroll="edlist:${esc(file)}:${esc(st.collection || '')}">${rows.map(e => listRow(file, e, st)).join('') || empty('fas fa-magnifying-glass', 'Nothing matches')}</div></div>`;
      return `<div class="content flush"><div class="split">${left}<div class="pane-r">${editorPane(file)}</div></div></div>`;
    },
  });
}
edPage('ed_items', 'Items', 'fas fa-box');
edPage('ed_weapons', 'Weapons', 'fas fa-gun');
edPage('ed_shops', 'Shops', 'fas fa-store');
edPage('ed_stashes', 'Stashes', 'fas fa-warehouse');
edPage('ed_crafting', 'Crafting', 'fas fa-screwdriver-wrench');
edPage('ed_other', 'Other data', 'fas fa-folder-tree');
A.edTab = async v => {
  const key = S.page;
  const cur = pd(key).file || ((invPage(key) || {}).files || [])[0]?.id;
  if (v === cur) return;
  if (!(await PAGES[key].canLeave())) return;
  pd(key).file = v; curFile = v; rerender();
  if (!ed(v).list) edLoadList(v);
};

/* ═══ editor actions ════════════════════════════════════════════════════ */
IN.edQ = debounce(v => { const st = ed(curFile); st.q = v; const q = v.toLowerCase(); const box = $('#ed-list'); if (!box) return; const rows = (st.list.entries || []).filter(e => !q || [e.key, e.label, e.name, e.description].join(' ').toLowerCase().includes(q)); box.innerHTML = rows.map(e => listRow(curFile, e, st)).join('') || empty('fas fa-magnifying-glass', 'Nothing matches'); }, 120);
A.edCat = async v => { const st = ed(curFile); if (st.dirty && !(await confirmBox('Discard unsaved changes?', '', { ok: 'Discard', tone: 'amber' }))) return; st.sel = undefined; st.creating = false; st.dirty = false; st.collection = v; edLoadList(curFile, v); };
A.edReload = () => { const st = ed(curFile); st.dirty = false; edLoadList(curFile).then(() => { if (st.sel !== undefined && !st.creating) edOpen(curFile, st.sel); }); };
A.edGoFiles = v => { pd('files').file = v; go('ed_files'); };
A.edPick = async v => {
  const st = ed(curFile);
  if (st.dirty && !(await confirmBox('Discard unsaved changes?', 'You have edits that are not saved yet.', { ok: 'Discard', tone: 'amber', icon: 'fas fa-triangle-exclamation' }))) return;
  edOpen(curFile, v);
};
A.edMode = async v => {
  const st = ed(curFile);
  if (v === st.mode) return;
  if (st.dirty && !st.creating) {
    if (!(await confirmBox('Switch view and lose unsaved changes?', 'Save first if you want to keep them.', { ok: 'Switch', tone: 'amber' }))) return;
    st.dirty = false;
    st.draft = clone(st.entry.value) || {}; st.code = st.entry.source;
  }
  if (st.creating && v === 'code') {
    const r = await rpc('ed:preview', { file: curFile, collection: st.collection, value: clean(st.draft) });
    if (r.ok) st.code = r.data.source;
  }
  st.mode = v; rerender();
};
A.edNew = async () => {
  const st = ed(curFile);
  if (st.dirty && !(await confirmBox('Discard unsaved changes?', '', { ok: 'Discard', tone: 'amber' }))) return;
  const kind = st.list.kind;
  st.creating = true; st.sel = undefined; st.entry = null; st.result = null; st.dirty = false; st.keyDraft = ''; st.pendingImg = null;
  st.draft = TEMPLATES[kind] ? TEMPLATES[kind](st.collection) : {};
  st.code = '{\n\t\n}';
  if (!FORMS[kind]) st.mode = 'code';
  rerender();
  const k = $('[data-in="edKey"]'); if (k) k.focus();
};
A.edCancel = () => { const st = ed(curFile); st.pendingImg = null; st.creating = false; st.dirty = false; st.sel = undefined; rerender(); };
A.edDup = async () => {
  const st = ed(curFile);
  const src = st.entry.source; const val2 = clone(st.entry.value);
  st.creating = true; st.result = null; st.dirty = true;
  st.keyDraft = st.list.keyed ? bareKey(st.sel) + '_copy' : '';
  st.draft = val2 || {}; st.code = src;
  if (st.list.kind === 'stash' && st.draft.name) st.draft.name += '_copy';
  st.sel = undefined; rerender();
};
IN.edKey = v => { ed(curFile).keyDraft = v.trim(); markDirty(); };
IN.edF = (v, el) => {
  const t = el.dataset.t;
  let out = v;
  if (t === 'num') out = v === '' ? undefined : Number(v);
  else if (v === '') out = undefined;
  setPath(ed(curFile).draft, el.dataset.p, out);
  markDirty();
};
CH.edB = (v, el) => {
  const st = ed(curFile);
  const def = el.dataset.def === '1';
  const orig = st.entry ? getPath(st.entry.value, el.dataset.p) : undefined;
  setPath(st.draft, el.dataset.p, v === def && orig === undefined ? undefined : v);
  markDirty();
};
IN.edV = (v, el) => {
  const st = ed(curFile);
  const cur = getPath(st.draft, el.dataset.p);
  const kind = el.dataset.k; const n = +el.dataset.n;
  const arr = cur && cur[kind] ? cur[kind].slice() : new Array(n).fill(0);
  arr[+el.dataset.i] = v === '' ? 0 : Number(v);
  setPath(st.draft, el.dataset.p, { [kind]: arr });
  markDirty();
};
/** Hides the panel so staff can aim at a spot in the world. Resolves with {x,y,z,w} or null if cancelled. */
async function capturePoint(heading) {
  if (!IS_FIVEM) { const r = await rpc('me:coords'); return r.ok ? r.data : null; }
  const hide = ['#app', '#modal'].map(q => $(q));
  hide.forEach(el => { if (el) el.style.visibility = 'hidden'; });
  const r = await post('capture', { heading: !!heading });
  hide.forEach(el => { if (el) el.style.visibility = ''; });
  if (!r || !r.ok) { toast('Capture cancelled', 'info', 1800); return null; }
  toast('Point captured', 'success', 1800);
  return r;
}
A.edHere = async v => {
  const [p, kind] = v.split('|');
  const c = await capturePoint(kind === '__vec4');
  if (!c) return;
  setPath(ed(curFile).draft, p, kind === '__vec4' ? { __vec4: [c.x, c.y, c.z, c.w] } : { __vec3: [c.x, c.y, c.z] });
  markDirty(); rerender();
};
IN.edGrp = (v, el) => readGroups(el.dataset.p);
A.edGrpAdd = p => { const st = ed(curFile); const rows = normGroups(getPath(st.draft, p)); const map = {}; rows.forEach(r => map[r.name] = r.grade); map[''] = 0; setPath(st.draft, p, map); rerender(); };
A.edGrpDel = v => { const [p, i] = v.split('|'); const st = ed(curFile); const rows = normGroups(getPath(st.draft, p)); rows.splice(+i, 1); const map = {}; rows.forEach(r => { if (r.name) map[r.name] = r.grade; }); setPath(st.draft, p, Object.keys(map).length ? map : undefined); markDirty(); rerender(); };
A.edRowAdd = async p => {
  const st = ed(curFile);
  const list = (getPath(st.draft, p) || []).filter(x => x != null);
  if (p === 'inventory') list.push({ name: '', price: 0 });
  else if (p === 'items') list.push({ name: '', ingredients: {}, duration: 5000, count: 1 });
  else {
    const c = await capturePoint(false);
    if (!c) return;
    list.push({ __vec3: [c.x, c.y, c.z] });
  }
  setPath(st.draft, p, list); markDirty(); rerender();
};
A.edRowDel = v => { const [p, i] = v.split('|'); const st = ed(curFile); const list = (getPath(st.draft, p) || []).slice(); list.splice(+i, 1); setPath(st.draft, p, list.filter(x => x != null)); markDirty(); rerender(); };
A.edIngAdd = p => { const st = ed(curFile); const m = Object.assign({}, getPath(st.draft, p) || {}); delete m.__empty; let k = 'item'; let n = 1; while (m[k] !== undefined) k = 'item' + (++n); m[k] = 1; setPath(st.draft, p, m); markDirty(); rerender(); };
A.edIngDel = v => { const [p, k] = v.split('|'); const st = ed(curFile); const m = Object.assign({}, getPath(st.draft, p) || {}); delete m[k]; setPath(st.draft, p, m); markDirty(); rerender(); };
CH.edIngName = (v, el) => { const st = ed(curFile); const m = Object.assign({}, getPath(st.draft, el.dataset.p) || {}); const old = el.dataset.old; const amt = m[old]; delete m[old]; if (v.trim()) m[v.trim()] = amt ?? 1; setPath(st.draft, el.dataset.p, m); markDirty(); rerender(); };
/* ═══ item pictures ═════════════════════════════════════════════════════
   Any picture works (PNG, JPG, WEBP, GIF, BMP, any size). Pick a file, drag one onto the item's
   picture, or copy one and press Ctrl+V. The picture editor sizes and frames it, can remove a plain
   background, and hands the server a PNG. */
const IMG_OK = /^image\/(png|jpe?g|webp|gif|bmp|avif)$/i;
function imgPicker() {
  return `${btn('Choose picture', 'edImgPick', 'sm', { icon: 'fas fa-upload' })}<span class="muted" style="font-size:10.5px">or drag one here, or paste with Ctrl+V</span>`;
}
function loadImage(src) {
  return new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = () => rej(new Error('bad image')); i.src = src; });
}
const imgMaxBytes = () => ((S.boot && S.boot.imageMaxKB) || (S.d.files && S.d.files.status && S.d.files.status.imageMaxKB) || 256) * 1024;
const dataBytes = d => Math.round((d.length - 22) * 0.75);

/* ─── picture editor: size, framing, zoom, drag, white background removal → PNG ─── */
const IE = {};
const IE_SIZES = [64, 100, 128, 256];
function ieRender(size) {
  const { img } = IE;
  const c = document.createElement('canvas'); c.width = c.height = size;
  const g = c.getContext('2d'); g.imageSmoothingQuality = 'high';
  const w = img.naturalWidth, h = img.naturalHeight;
  const base = IE.mode === 'fill' ? Math.max(size / w, size / h) : Math.min(size / w, size / h);
  const k = base * IE.zoom;
  const dw = w * k, dh = h * k;
  g.drawImage(img, (size - dw) / 2 + IE.ox * size, (size - dh) / 2 + IE.oy * size, dw, dh);
  if (IE.clear) ieClearBackground(g, size);
  return c;
}
/** Flood-fill from the edges: pixels close to the corner colour become transparent, so a white box
 *  around the product goes away but white parts inside it stay. */
function ieBackground() {
  if (IE.bg) return IE.bg;
  const { img } = IE;
  const n = 48;
  const c = document.createElement('canvas'); c.width = c.height = n;
  const g = c.getContext('2d'); g.drawImage(img, 0, 0, n, n);
  const p = g.getImageData(0, 0, n, n).data;
  const pts = [[0, 0], [n - 1, 0], [0, n - 1], [n - 1, n - 1], [n >> 1, 0], [0, n >> 1]].map(([x, y]) => (y * n + x) * 4).filter(i => p[i + 3] > 200);
  IE.bg = pts.length ? pts.reduce((a, i) => [a[0] + p[i], a[1] + p[i + 1], a[2] + p[i + 2]], [0, 0, 0]).map(v => v / pts.length) : null;
  return IE.bg;
}
function ieClearBackground(g, n) {
  const ref = ieBackground();
  if (!ref) return;
  const d = g.getImageData(0, 0, n, n); const p = d.data;
  const tol = IE.tol * 3;
  // transparent pixels (empty space around the photo) let the fill pass through
  const open = i => p[i + 3] === 0 || Math.abs(p[i] - ref[0]) + Math.abs(p[i + 1] - ref[1]) + Math.abs(p[i + 2] - ref[2]) <= tol;
  const seen = new Uint8Array(n * n); const stack = [];
  for (let i = 0; i < n; i++) stack.push(i, 0, i, n - 1, 0, i, n - 1, i);
  while (stack.length) {
    const y = stack.pop(), x = stack.pop();
    if (x < 0 || y < 0 || x >= n || y >= n) continue;
    const j = y * n + x; if (seen[j]) continue; seen[j] = 1;
    const i = j * 4; if (!open(i)) continue;
    p[i + 3] = 0;
    stack.push(x + 1, y, x - 1, y, x, y + 1, x, y - 1);
  }
  g.putImageData(d, 0, 0);
}
function ieDraw() {
  const v = $('#ie-view'); if (!v || !IE.img) return;
  const out = ieRender(IE.size);
  const g = v.getContext('2d'); g.clearRect(0, 0, v.width, v.height);
  g.imageSmoothingEnabled = IE.size < 128 ? false : true;
  g.drawImage(out, 0, 0, v.width, v.height);
  const data = out.toDataURL('image/png');
  IE.out = data;
  const kb = dataBytes(data) / 1024;
  const info = $('#ie-info');
  if (info) info.innerHTML = `Saves as <b>${IE.size}×${IE.size} PNG</b> · ${kb < 10 ? kb.toFixed(1) : Math.round(kb)} KB${dataBytes(data) > imgMaxBytes() ? ' <span class="tred">· too big, pick a smaller size</span>' : ''}`;
}
function ieSeg(id, list, cur, a) { return `<div class="seg" id="${id}">${list.map(([k, l]) => `<button type="button" class="${String(k) === String(cur) ? 'on' : ''}" data-a="${a}" data-v="${k}">${esc(l)}</button>`).join('')}</div>`; }
function ieSetSeg(id, v) { $$(`#${id} button`).forEach(b => b.classList.toggle('on', b.dataset.v === String(v))); }
A.ieSize = v => { IE.size = +v; ieSetSeg('ie-size', v); ieDraw(); };
A.ieMode = v => { IE.mode = v; IE.ox = IE.oy = 0; ieSetSeg('ie-mode', v); ieDraw(); };
A.ieCenter = () => { IE.ox = IE.oy = 0; IE.zoom = 1; const z = $('#ie-zoom'); if (z) z.value = 100; ieDraw(); };
IN.ieZoom = v => { IE.zoom = (+v || 100) / 100; ieDraw(); };
IN.ieTol = v => { IE.tol = +v || 30; ieDraw(); };
CH.ieClear = v => { IE.clear = !!v; const t = $('#ie-tol-row'); if (t) t.style.display = v ? '' : 'none'; ieDraw(); };
function ieMount() {
  const v = $('#ie-view'); if (!v) return;
  let drag = null;
  v.addEventListener('pointerdown', e => { drag = { x: e.clientX, y: e.clientY, ox: IE.ox, oy: IE.oy }; v.setPointerCapture(e.pointerId); });
  v.addEventListener('pointermove', e => {
    if (!drag) return;
    const r = v.getBoundingClientRect();
    IE.ox = drag.ox + (e.clientX - drag.x) / r.width; IE.oy = drag.oy + (e.clientY - drag.y) / r.height;
    ieDraw();
  });
  const end = () => { drag = null; };
  v.addEventListener('pointerup', end); v.addEventListener('pointercancel', end);
  v.addEventListener('wheel', e => { e.preventDefault(); IE.zoom = Math.min(4, Math.max(0.3, IE.zoom * (e.deltaY < 0 ? 1.08 : 1 / 1.08))); const z = $('#ie-zoom'); if (z) z.value = Math.round(IE.zoom * 100); ieDraw(); }, { passive: false });
  ieDraw();
}
/** Opens the picture editor. Resolves with a PNG data URL, or null if cancelled. */
async function openImageEditor(file) {
  const url = URL.createObjectURL(file);
  let img;
  try { img = await loadImage(url); } catch (e) { URL.revokeObjectURL(url); toast('That picture couldn\'t be read. Try saving it as a PNG or JPG first.', 'error'); return null; }
  Object.assign(IE, { img, size: 128, mode: 'fit', zoom: 1, ox: 0, oy: 0, clear: false, tol: 30, out: null, bg: null });
  const kind = (file.type || 'image').replace('image/', '').toUpperCase();
  const body = `<div class="imged">
      <div class="ie-stage"><canvas id="ie-view" width="256" height="256" title="Drag to move, scroll to zoom"></canvas></div>
      <div class="stack" style="gap:14px;min-width:0">
        <div class="field"><label>Size<small>inventory icons are usually 100 or 128</small></label>${ieSeg('ie-size', IE_SIZES.map(n => [n, `${n}px`]), IE.size, 'ieSize')}</div>
        <div class="field"><label>Framing</label>${ieSeg('ie-mode', [['fit', 'Show whole picture'], ['fill', 'Fill the square']], IE.mode, 'ieMode')}</div>
        <div class="field"><label>Zoom<small>or scroll on the picture</small></label><div style="display:flex;gap:8px;align-items:center"><input type="range" id="ie-zoom" min="30" max="400" value="100" data-in="ieZoom" style="flex:1">${btn('Reset', 'ieCenter', 'xs btn-ghost', { icon: 'fas fa-arrows-to-dot' })}</div></div>
        <label class="chk"><input type="checkbox" data-ch="ieClear"><span class="box"></span>Remove the background colour (for product photos on white)</label>
        <div class="field" id="ie-tol-row" style="display:none"><label>How close a colour counts as background</label><input type="range" min="5" max="90" value="30" data-in="ieTol"></div>
        <div class="hint">Drag the picture to move it.</div>
        <div id="ie-info" class="muted" style="font-size:11px"></div>
      </div></div>`;
  const p = form({ title: 'Item picture', sub: `${file.name || 'Pasted picture'} · ${img.naturalWidth}×${img.naturalHeight} ${kind}`, icon: 'fas fa-crop-simple', size: 'lg', ok: 'Use this picture', body, focus: false, mounted: () => setTimeout(ieMount, 0) });
  const v = await p;
  URL.revokeObjectURL(url);
  if (v === null) return null;
  let out = IE.out || ieRender(IE.size).toDataURL('image/png');
  // still over the server limit: step the size down until it fits
  for (let i = IE_SIZES.indexOf(IE.size) - 1; dataBytes(out) > imgMaxBytes() && i >= 0; i--) out = ieRender(IE_SIZES[i]).toDataURL('image/png');
  if (dataBytes(out) > imgMaxBytes()) { toast('That picture is still too big after resizing.', 'error'); return null; }
  IE.img = null;
  return out;
}
async function sendImage(item, data) {
  toast('Uploading picture…', 'info', 1500);
  const r = await post('upload', { item, data });
  if (!r || !r.ok) { toast((r && (r.msg || r.err)) || 'Upload failed. Check the server console.', 'error', 9000); return false; }
  S.img[item] = data;
  toast(r.msg, r.data && r.data.live ? 'success' : 'warning', 7000);
  return r;
}
async function useImageFile(file) {
  if (!file) return;
  if (!IMG_OK.test(file.type || '')) return toast('That file isn\'t a picture. Use a PNG, JPG, WEBP or GIF.', 'error');
  const data = await openImageEditor(file);
  if (!data) return;
  const st = ed(curFile);
  if (st.creating) {
    st.pendingImg = data;
    toast('Picture added. It uploads when you press Create.', 'info');
    return rerender();
  }
  const item = bareKey(st.sel);
  const r = await sendImage(item, data);
  if (!r) return;
  if (r.data && r.data.changed) { await edLoadList(curFile); await edOpen(curFile, st.sel); }
  rerender();
}
// FiveM's browser only opens the file window once per file input, so every click gets a brand-new one
A.edImgPick = () => {
  document.querySelectorAll('input.ed-img-pick').forEach(x => x.remove());
  const f = document.createElement('input');
  f.type = 'file';
  f.className = 'ed-img-pick';
  f.id = 'ed-img';
  f.accept = 'image/png,image/jpeg,image/webp,image/gif,image/bmp';
  f.style.cssText = 'position:fixed;left:-9999px;top:0;width:1px;height:1px;opacity:0';
  f.addEventListener('change', () => {
    const file = f.files && f.files[0];
    f.remove();
    useImageFile(file);
  });
  document.body.appendChild(f);
  f.click();
};
const importOpen = () => !!$('#modal [data-drop="import"]');
document.addEventListener('dragover', e => {
  if (importOpen()) { e.preventDefault(); const z = $('#modal [data-drop="import"]'); if (z) z.classList.add('drag'); return; }
  const z = e.target.closest && e.target.closest('[data-drop="img"]'); if (z) { e.preventDefault(); z.classList.add('drag'); }
});
document.addEventListener('dragleave', e => { const z = e.target.closest && e.target.closest('[data-drop]'); if (z) z.classList.remove('drag'); });
document.addEventListener('drop', e => {
  // the Import window takes anything dropped anywhere on it: pictures, item lists, whole folders
  if (importOpen()) { e.preventDefault(); const z = $('#modal [data-drop="import"]'); if (z) z.classList.remove('drag'); importDrop(e.dataTransfer); return; }
  const z = e.target.closest && e.target.closest('[data-drop="img"]');
  if (!z) return;
  e.preventDefault(); z.classList.remove('drag');
  const f = [...(e.dataTransfer && e.dataTransfer.files || [])].find(x => IMG_OK.test(x.type));
  if (f) useImageFile(f); else toast('Drop a picture file (PNG, JPG, WEBP or GIF).', 'error');
});
document.addEventListener('paste', e => {
  if (importOpen()) {
    const files = [...(e.clipboardData && e.clipboardData.items || [])].filter(x => x.kind === 'file').map(x => x.getAsFile()).filter(Boolean);
    if (files.length) { e.preventDefault(); importFiles(files); }
    return;
  }
  if (!$('[data-drop="img"]')) return;
  const it = [...(e.clipboardData && e.clipboardData.items || [])].find(x => x.kind === 'file' && IMG_OK.test(x.type));
  if (!it) return;
  e.preventDefault();
  useImageFile(it.getAsFile());
});
A.edCheck = async () => {
  const st = ed(curFile);
  const r = await rpc('ed:check', { source: st.code, snippet: true });
  const m = $('#ed-check'); const w = $('#ed-code-wrap');
  const ok = r.ok && r.data.ok;
  if (m) { m.className = 'msg ' + (ok ? 'ok' : 'bad'); m.innerHTML = ok ? '<i class="fas fa-circle-check"></i>Looks good.' : `<i class="fas fa-circle-exclamation"></i>${esc((r.data && r.data.err) || r.err)}`; }
  if (w) w.classList.toggle('err', !ok);
};

function applyToast(res) {
  const a = res && res.apply;
  if (!a) return toast('Saved', 'success');
  if (a.ok === false) return toast(`Saved to the file, but applying it live failed: ${a.err}`, 'error', 8000);
  if (a.live) return toast(`Saved and live for every player${a.note ? '. ' + a.note : ''}`, 'success', a.note ? 7000 : 3600);
  toast(a.note || 'Saved', 'warning', 7000);
}

A.edSave = async () => {
  const st = ed(curFile);
  if (!st.list) return;
  const code = st.mode === 'code' || !FORMS[st.list.kind];
  let r;
  if (st.creating) {
    if (st.list.keyed && !st.keyDraft) return toast('Give it a name first.', 'error');
    const payload = { file: curFile, collection: st.collection, key: st.keyDraft, hash: st.list.hash };
    if (code) payload.source = st.code; else payload.value = clean(st.draft);
    if (!code && Array.isArray(st.draft) && !st.draft.length) payload.value = [];
    r = await rpc('ed:create', payload);
  } else {
    const payload = { file: curFile, collection: st.collection, key: st.sel, hash: st.entry.hash };
    if (st.list.keyed && st.keyDraft && st.keyDraft !== String(st.sel)) payload.rename = st.keyDraft;
    if (code) payload.source = st.code;
    else if (Array.isArray(st.draft)) {
      if (same(st.entry.value, st.draft) && !payload.rename) { toast('Nothing changed.', 'info'); return; }
      payload.replace = clean(st.draft);
      if (!payload.replace.length) payload.replace = [];
    } else {
      payload.ops = diffOps(st.entry.value, st.draft);
      if (!payload.ops.length && !payload.rename) { toast('Nothing changed.', 'info'); return; }
    }
    r = await rpc('ed:save', payload);
  }
  if (!r.ok) return toast(r.err, 'error', 8000);
  applyToast(r.data);
  st.dirty = false;
  st.result = r.data;
  const key = r.data.key;
  if (st.pendingImg && key !== undefined && key !== null) { const img = st.pendingImg; st.pendingImg = null; await sendImage(bareKey(key), img); }
  st.pendingImg = null;
  await edLoadList(curFile);
  if (key !== undefined && key !== null) { await edOpen(curFile, key); st.result = r.data; rerender(); }
  if (ITEMISH[st.list.kind]) loadItems(true);
};

A.edDel = async () => {
  const st = ed(curFile);
  const isItem = !!ITEMISH[st.list.kind];
  const fields = isItem && can('global') ? [{ name: 'purge', label: 'Also remove every copy players, stashes and vehicles still hold', type: 'check', value: false }] : undefined;
  const label = (!Array.isArray(st.draft) && (getPath(st.draft, 'label') || getPath(st.draft, 'name'))) || bareKey(st.sel);
  const v = await confirmBox(`Delete ${label}?`, isItem ? 'Scripts and shops that use this name stop working. Copies players already hold stay in their slots unless you remove them too.' : 'It is removed from the file. A backup is kept.', { ok: 'Delete', fields });
  if (!v) return;
  const r = await rpc('ed:delete', { file: curFile, collection: st.collection, key: st.sel, hash: st.entry.hash, purge: v.purge });
  if (!r.ok) return toast(r.err, 'error', 8000);
  applyToast(r.data);
  if (r.data.purged) toast(`Removed ${num(r.data.purged.total)} copies from ${num(r.data.purged.inventories)} inventories`, 'success');
  st.sel = undefined; st.entry = null; st.dirty = false;
  edLoadList(curFile);
  if (isItem) loadItems(true);
};

/* ═══ CODE & BACKUPS ════════════════════════════════════════════════════ */
page('ed_files', {
  label: 'Code & backups', icon: 'fas fa-file-code', tier: 'editor', when: () => S.boot.editor,
  async enter() {
    A.hotSave = () => A.rawSave();
    const st = pd('files');
    const r = await rpc('ed:status');
    if (!r.ok) { toast(r.err, 'error'); return; }
    st.status = r.data;
    if (!st.file || !r.data.files.some(f => f.id === st.file)) st.file = (r.data.files[0] || {}).id;
    if (st.file) await rawLoad(st.file);
  },
  leave() { A.hotSave = null; },
  async canLeave() { const st = pd('files'); if (!st.dirty) return true; const ok = await confirmBox('Leave without saving?', 'Your unsaved code changes will be lost.', { ok: 'Discard changes', tone: 'amber' }); if (ok) st.dirty = false; return !!ok; },
  render() {
    const st = pd('files'); const s = st.status;
    const invName = (S.boot.inventory && S.boot.inventory.label) || 'inventory';
    if (!s) return ph('Code & backups', `Edit any ${invName} data file directly`) + `<div class="content">${loading()}</div>`;
    const cur = s.files.find(f => f.id === st.file) || {};
    const b = s.bridge;
    const left = `<div class="pane-l"><div class="pane-h"><div class="card"><div class="card-b" style="padding:12px">
        ${b ? `<div class="status-live"><span class="livechip on"><span class="dot"></span>Live editing on</span></div><div class="muted" style="font-size:10.5px;margin-top:8px;line-height:1.5">${b.version ? `Bridge v${esc(b.version)}${b.crafting !== undefined ? ` · crafting ${b.crafting ? 'live' : 'needs the export from INSTALL.md'}` : ''}` : `Applied through ${esc(b.via || s.resource)}`}</div>`
          : `<div class="status-live"><span class="livechip warn"><span class="dot"></span>Bridge not installed</span></div><div class="muted" style="font-size:10.5px;margin-top:8px;line-height:1.5">Edits save to disk and apply after ${esc(s.resource)} restarts. Follow INSTALL.md to make them live.</div>`}
        <div class="muted" style="font-size:10.5px;margin-top:6px">${esc(s.inventory || s.resource)} ${esc(s.oxVersion || '')}</div></div></div></div>
      <div class="pane-b" data-scroll="rawfiles">${s.files.map(f => `<div class="li click ${st.file === f.id ? 'on' : ''}" data-a="rawPick" data-v="${f.id}"><div class="thumb"><i class="fas fa-file-code"></i></div><div class="tx"><b>${esc(f.label || f.name)}</b><span><span class="mono">${esc(f.name)}</span> · ${f.exists ? num(Math.round(f.size / 102.4) / 10) + ' KB' : 'missing'}</span></div></div>`).join('')}</div>
      <div class="pane-f">${(s.restartable || []).map(r => btn(`Restart ${r}`, 'rawRestart', 'btn-red sm full', { v: r, icon: 'fas fa-power-off' })).join('')}</div></div>`;
    const right = st.src === undefined ? loading() : `<div class="ed-head"><div><h2>${esc(cur.name || st.file)} <span id="raw-dirty" class="dirty-dot ${st.dirty ? '' : 'hide'}" style="display:inline-block;vertical-align:middle;margin-left:6px"></span></h2><p>${esc(cur.path || '')}</p></div>
        <div class="r">${btn('Save', 'rawSave', 'btn-teal sm', { icon: 'fas fa-floppy-disk' })}${btn('Backups', 'rawBackups', 'sm', { icon: 'fas fa-clock-rotate-left' })}${btn('', 'rawApply', 'sm', { icon: 'fas fa-bolt', title: 'Apply the file on disk again' })}${btn('', 'rawReload', 'sm btn-ghost', { icon: 'fas fa-rotate', title: 'Reload from disk' })}</div></div>
      <div class="ed-body codemode">${codeBox(st.src, 'raw-code', 'rawcode:' + st.file)}<div class="codebar">${btn('Check', 'rawCheck', 'sm', { icon: 'fas fa-spell-check' })}<span class="msg" id="raw-check">Saving checks the whole file first. A file with an error is never written.</span></div></div>`;
    return `<div class="content flush"><div class="split">${left}<div class="pane-r">${right}</div></div></div>`;
  },
});
async function rawLoad(file) {
  const st = pd('files');
  st.src = undefined; rerender();
  const r = await rpc('ed:raw:get', { file });
  if (!r.ok) { toast(r.err, 'error'); return; }
  st.src = r.data.source; st.hash = r.data.hash; st.dirty = false;
  if (S.page === 'ed_files') rerender();
}
A.rawPick = async v => { if (!(await PAGES.ed_files.canLeave())) return; pd('files').file = v; rawLoad(v); };
A.rawReload = async () => { if (!(await PAGES.ed_files.canLeave())) return; rawLoad(pd('files').file); };
A.rawCheck = async () => {
  const st = pd('files');
  const r = await rpc('ed:check', { source: st.src, file: st.file });
  const m = $('#raw-check'); const w = $('#raw-code-wrap');
  const ok = r.ok && r.data.ok;
  if (m) { m.className = 'msg ' + (ok ? 'ok' : 'bad'); m.innerHTML = ok ? '<i class="fas fa-circle-check"></i>No errors.' : `<i class="fas fa-circle-exclamation"></i>${esc((r.data && r.data.err) || r.err)}`; }
  if (w) w.classList.toggle('err', !ok);
};
A.rawSave = async () => {
  const st = pd('files');
  if (!st.dirty) return toast('Nothing changed.', 'info');
  const r = await rpc('ed:raw:save', { file: st.file, source: st.src, hash: st.hash });
  if (!r.ok) return toast(r.err, 'error', 9000);
  applyToast(r.data);
  st.hash = r.data.hash; st.dirty = false;
  const d = $('#raw-dirty'); if (d) d.classList.add('hide');
  Object.keys(ED).forEach(k => { ED[k].list = null; ED[k].sel = undefined; });
  loadItems(true);
};
A.rawApply = async () => { const r = await call('ed:apply', { file: pd('files').file }); if (r) applyToast({ apply: r }); };
A.rawRestart = async res => {
  if (!await confirmBox(`Restart ${res}?`, res === 'ox_inventory' ? 'Inventories are saved first. Players can\'t open their inventory for a few seconds, and scripts that depend on ox_inventory may restart with it.' : `Scripts that depend on ${res} may restart with it.`, { ok: 'Restart' })) return;
  if (await call('ed:restart', { resource: res }, `Restarting ${res}`)) setTimeout(() => { const st = pd('files'); st.status = null; PAGES.ed_files.enter(); }, 6000);
};
A.rawBackups = async () => {
  const st = pd('files');
  const list = await call('ed:backups', { file: st.file });
  if (!list) return;
  const f = ((st.status && st.status.files) || []).find(x => x.id === st.file) || {};
  infoBox(`Backups of ${f.name || st.file}`, list.length ? `<div class="tbl-wrap" style="max-height:420px"><table class="tbl"><thead><tr><th>Saved</th><th>By</th><th>Change</th><th class="num">Size</th><th></th></tr></thead><tbody>${list.map(b => `<tr><td>${esc(date(b.time))}</td><td><b>${esc(b.admin)}</b></td><td>${chip(b.action)}</td><td class="num">${num(Math.round(b.size / 102.4) / 10)} KB</td><td class="act"><div class="row-btns" style="flex-wrap:nowrap">${btn('View', 'bkView', 'xs', { v: b.id })}${btn('Restore', 'bkRestore', 'xs btn-amber', { v: b.id })}</div></td></tr>`).join('')}</tbody></table></div>`
    : empty('fas fa-clock-rotate-left', 'No backups yet', 'A backup is made every time this file is saved from the panel.'), { size: 'lg', icon: 'fas fa-clock-rotate-left', sub: 'Each backup is the file as it was just before that save.' });
};
A.bkView = async v => {
  const st = pd('files');
  const r = await call('ed:backup:get', { file: st.file, id: +v });
  if (!r) return;
  infoBox(`Backup #${v}`, `<div class="code" style="height:420px">${'<textarea readonly spellcheck="false" style="white-space:pre">' + esc(r.source) + '</textarea>'}</div>`, { size: 'xl', icon: 'fas fa-file-code' });
};
A.bkRestore = async v => {
  const st = pd('files');
  closeModal(null);
  if (!await confirmBox(`Restore backup #${v}?`, `The file is replaced with this backup and applied. The current version is backed up first, so you can undo this.`, { ok: 'Restore', tone: 'amber', okClass: 'btn-amber', icon: 'fas fa-clock-rotate-left' })) return;
  const r = await call('ed:backup:restore', { file: st.file, id: +v });
  if (r) { applyToast(r); rawLoad(st.file); Object.keys(ED).forEach(k => { ED[k].list = null; }); }
};

/* ═══ qb-shops helpers ══════════════════════════════════════════════════ */
CH.qbShopList = v => {
  const st = ed(curFile);
  const ref = st.entry && st.entry.refs && st.entry.refs.products;
  if (!ref || !v) return;
  setPath(st.draft, 'products', { __raw: ref.format.replace('%s', v) });
  markDirty(); rerender();
};
A.qbShopEditList = async v => {
  const pageKey = S.page;
  if (!(await PAGES[pageKey].canLeave())) return;
  pd(pageKey).file = 'products'; curFile = 'products';
  const st = ed('products');
  await edLoadList('products');
  await edOpen('products', v);
  rerender();
};
A.qbShopDelivery = async () => {
  const c = await capturePoint(true);
  if (!c) return;
  setPath(ed(curFile).draft, 'delivery', { __vec4: [c.x, c.y, c.z, c.w] });
  markDirty(); rerender();
};
A.qbpAdd = () => { const st = ed(curFile); const list = (Array.isArray(st.draft) ? st.draft : []).filter(Boolean); list.push({ name: '', price: 1, amount: 50 }); st.draft = list; markDirty(); rerender(); };
A.qbpDel = v => { const st = ed(curFile); const list = (Array.isArray(st.draft) ? st.draft : []).slice(); list.splice(+v, 1); st.draft = list.filter(Boolean); markDirty(); rerender(); };
IN.qbpJobs = (v, el) => { const st = ed(curFile); const i = +el.dataset.i; const list = v.split(',').map(x => x.trim()).filter(Boolean); if (st.draft[i]) { if (list.length) st.draft[i].requiredJob = list; else delete st.draft[i].requiredJob; } markDirty(); };

/* ═══ IMPORT: a new script's items and pictures in one go ═══════════════
   Server owners installing a script (drugs, jobs, heists...) get a folder of pictures and a list of
   items to paste into items.lua. Drop all of it here: the items are added to the file, the pictures
   are uploaded, and with the bridge installed everything is live without a restart. */
const IMPORT_KINDS = { item: 1, qbitem: 1 };
const IMP = { pics: [], plan: null };
const IMP_TEXT = /\.(lua|txt|json|md)$/i;
const picName = f => String(f.name || '').replace(/\.[^.]+$/, '').trim().toLowerCase().replace(/[^a-z0-9_-]+/g, '_').replace(/^_+|_+$/g, '');

/** Any picture -> PNG data URL under the upload limit (largest side 256px, smaller if needed) */
async function toPng(file) {
  const url = URL.createObjectURL(file);
  try {
    const img = await loadImage(url);
    for (const max of [256, 128, 100, 64]) {
      const k = Math.min(1, max / Math.max(img.naturalWidth, img.naturalHeight));
      const c = document.createElement('canvas');
      c.width = Math.max(1, Math.round(img.naturalWidth * k)); c.height = Math.max(1, Math.round(img.naturalHeight * k));
      const g = c.getContext('2d'); g.imageSmoothingQuality = 'high'; g.drawImage(img, 0, 0, c.width, c.height);
      const d = c.toDataURL('image/png');
      if (dataBytes(d) <= imgMaxBytes()) return d;
    }
  } catch (e) { /* unreadable */ } finally { URL.revokeObjectURL(url); }
  return null;
}
const readText = f => new Promise(res => { const r = new FileReader(); r.onload = () => res(String(r.result || '')); r.onerror = () => res(''); r.readAsText(f); });

/** Files from a drop, including everything inside dropped folders */
async function importDrop(dt) {
  if (!dt) return;
  // entries must be read during the drop event, before any await
  const entries = [...(dt.items || [])].map(i => i.webkitGetAsEntry && i.webkitGetAsEntry()).filter(Boolean);
  if (!entries.length) return importFiles([...(dt.files || [])]);
  const out = [];
  const walk = async (en, depth) => {
    if (en.isFile) { const f = await new Promise(r => en.file(r, () => r(null))); if (f) out.push(f); return; }
    if (en.isDirectory && depth < 6) {
      const rd = en.createReader();
      let batch;
      do { batch = await new Promise(r => rd.readEntries(r, () => r([]))); for (const c of batch) await walk(c, depth + 1); } while (batch.length);
    }
  };
  for (const en of entries) await walk(en, 0);
  importFiles(out);
}

async function importFiles(files) {
  const pics = files.filter(f => IMG_OK.test(f.type || '') || /\.(png|jpe?g|webp|gif|bmp)$/i.test(f.name || ''));
  const texts = files.filter(f => IMP_TEXT.test(f.name || '') && f.size < 2 * 1024 * 1024);
  if (!pics.length && !texts.length) return toast('Nothing to import in that. Drop pictures, a .lua or .txt item list, or the script\'s folder.', 'error');
  const area = $('#modal [name="source"]');
  for (const f of texts) {
    const t = (await readText(f)).trim();
    // README-style files: only take them when they actually contain item tables
    if (!t || (/\.md$/i.test(f.name) && !/=\s*\{/.test(t))) continue;
    if (area) { area.value = area.value.trim() ? area.value.trimEnd() + '\n' + t : t; }
  }
  if (pics.length) impStatus(`Reading ${pics.length} picture${pics.length === 1 ? '' : 's'}…`);
  let skipped = 0;
  for (const f of pics.slice(0, 400)) {
    const name = picName(f);
    const data = name && await toPng(f);
    if (!data) { skipped++; continue; }
    IMP.pics = IMP.pics.filter(p => p.name !== name).concat({ name, data });
  }
  if (skipped) toast(`${skipped} picture${skipped === 1 ? '' : 's'} couldn't be read or stayed too big.`, 'warning');
  impPics();
  impCheck();
}

function impStatus(html, cls = '') { const el = $('#imp-plan'); if (el) el.outerHTML = `<div id="imp-plan">${html ? note(html, cls, cls === 'red' ? 'fas fa-triangle-exclamation' : 'fas fa-circle-info') : ''}</div>`; }
function impKnown() {
  const st = ed(curFile);
  const names = new Set(((st.list && st.list.entries) || []).map(e => bareKey(e.key)));
  const pl = IMP.plan;
  if (pl) [...pl.added, ...pl.replaced, ...pl.skipped].forEach(n => names.add(n));
  return names;
}
function impPics() {
  const box = $('#imp-pics'); if (!box) return;
  if (!IMP.pics.length) { box.innerHTML = ''; return; }
  const known = impKnown();
  const miss = IMP.pics.filter(p => !known.has(p.name)).length;
  box.innerHTML = `<div class="field"><label>Pictures (${IMP.pics.length})<small>${miss ? `${miss} have no item with that name yet` : 'each one matches an item'}</small></label>
    <div class="imp-pics">${IMP.pics.map((p, i) => `<div class="imp-pic ${known.has(p.name) ? '' : 'miss'}" title="${known.has(p.name) ? esc(p.name) + '.png' : 'No item called ' + esc(p.name) + '. It is still uploaded, rename the file to match the item if this is wrong.'}">
      <img src="${p.data}"><span class="mono ell">${esc(p.name)}</span><button class="btn xs ico btn-ghost" data-a="impPicDel" data-v="${i}" title="Leave this one out"><i class="fas fa-xmark"></i></button></div>`).join('')}</div></div>`;
}
const impCheck = debounce(async () => {
  const area = $('#modal [name="source"]'); if (!area) return;
  const source = area.value.trim();
  if (!source) { IMP.plan = null; impPics(); return impStatus(IMP.pics.length ? `Only pictures this time: <b>${IMP.pics.length}</b> will be uploaded.` : ''); }
  const rep = $('#modal [name="replace"]');
  const r = await rpc('ed:import:check', { file: curFile, source, replace: !!(rep && rep.checked) });
  if (!$('#modal [name="source"]')) return;
  if (!r.ok) { IMP.plan = null; impPics(); return impStatus(esc(r.err), 'red'); }
  IMP.plan = r.data;
  const p = r.data;
  const list = (a, n = 6) => a.slice(0, n).map(x => `<span class="mono">${esc(x)}</span>`).join(', ') + (a.length > n ? ` +${a.length - n} more` : '');
  const parts = [];
  if (p.added.length) parts.push(`Adds <b>${p.added.length}</b> new item${p.added.length === 1 ? '' : 's'}: ${list(p.added)}`);
  if (p.replaced.length) parts.push(`Replaces <b>${p.replaced.length}</b>: ${list(p.replaced)}`);
  if (p.skipped.length) parts.push(`Skips <b>${p.skipped.length}</b> that already exist${rep && rep.checked ? '' : ' (tick Replace to overwrite them)'}: ${list(p.skipped)}`);
  if (p.invalid.length) parts.push(`<span class="tred">Leaves out ${p.invalid.length} with names that aren't allowed: ${list(p.invalid)}</span>`);
  if (IMP.pics.length) parts.push(`Uploads <b>${IMP.pics.length}</b> picture${IMP.pics.length === 1 ? '' : 's'}`);
  impStatus(parts.join('<br>') || 'Nothing new in that list.', p.added.length || p.replaced.length ? '' : 'amber');
  impPics();
}, 350);
IN.impSrc = () => impCheck();
CH.impReplace = () => impCheck();
A.impPicDel = v => { IMP.pics.splice(+v, 1); impPics(); impCheck(); };
A.impPick = () => {
  document.querySelectorAll('input.imp-pick').forEach(x => x.remove());
  const f = document.createElement('input');
  f.type = 'file'; f.multiple = true; f.className = 'imp-pick';
  f.accept = 'image/png,image/jpeg,image/webp,image/gif,image/bmp,.lua,.txt,.json';
  f.style.cssText = 'position:fixed;left:-9999px;top:0;width:1px;height:1px;opacity:0';
  f.addEventListener('change', () => { const files = [...(f.files || [])]; f.remove(); importFiles(files); });
  document.body.appendChild(f);
  f.click();
};

async function runImport(vals) {
  const st = ed(curFile);
  const source = (vals.source || '').trim();
  if (!source && !IMP.pics.length) { toast('Drop or paste something to import first.', 'error'); return false; }
  let res = null;
  if (source) {
    impStatus('Adding the items…');
    const r = await rpc('ed:import', { file: curFile, source, replace: !!vals.replace });
    if (!r.ok) { impStatus(esc(r.err), 'red'); toast(r.err, 'error', 9000); return false; }
    res = r.data;
  }
  let up = 0; const bad = [];
  for (let i = 0; i < IMP.pics.length; i++) {
    const p = IMP.pics[i];
    impStatus(`Uploading pictures… <b>${i + 1}</b> of ${IMP.pics.length}`);
    const r = await post('upload', { item: p.name, data: p.data });
    if (r && r.ok) { up++; S.img[p.name] = p.data; } else bad.push(`${p.name}: ${(r && (r.msg || r.err)) || 'failed'}`);
  }
  const parts = [];
  if (res) parts.push(`${num(res.added.length)} item${res.added.length === 1 ? '' : 's'} added${res.replaced.length ? `, ${num(res.replaced.length)} replaced` : ''}`);
  if (IMP.pics.length) parts.push(`${num(up)} picture${up === 1 ? '' : 's'} uploaded`);
  const a = res && res.apply;
  const how = !a ? '' : a.ok === false ? `. Applying it live failed: ${a.err}` : a.live ? '. Live for every player now.' : `. ${a.note || ''}`;
  toast(parts.join(' and ') + how, a && (a.ok === false || !a.live) ? 'warning' : 'success', 8000);
  if (bad.length) toast(`Some pictures didn't upload: ${bad.slice(0, 3).join(' · ')}${bad.length > 3 ? ` +${bad.length - 3} more` : ''}`, 'error', 10000);
  IMP.pics = []; IMP.plan = null;
  st.sel = undefined; st.creating = false;
  edLoadList(curFile);
  loadItems(true);
  return true;
}

A.edImport = async () => {
  const st = ed(curFile);
  if (st.dirty && !(await confirmBox('Discard unsaved changes?', 'Importing reloads the list.', { ok: 'Discard', tone: 'amber' }))) return;
  st.dirty = false;
  IMP.pics = []; IMP.plan = null;
  const kind = st.list.kind;
  const example = kind === 'qbitem'
    ? `weed_bag = { name = 'weed_bag', label = 'Weed bag', weight = 100, type = 'item', image = 'weed_bag.png', unique = false, useable = true, shouldClose = true, description = 'A bag of weed' },`
    : `['weed_bag'] = {\n    label = 'Weed bag',\n    weight = 100,\n},`;
  const body = `<div class="imp-drop" data-drop="import">
      <i class="fas fa-cloud-arrow-up"></i>
      <div><b>Drop the new script's files here</b><span>Its pictures (PNG, JPG, WEBP), its item list (.lua or .txt), or the whole folder at once</span></div>
      ${btn('Choose files', 'impPick', 'sm', { icon: 'fas fa-folder-open' })}
    </div>
    <div class="field"><label>Item list<small>paste it from the script's install guide</small></label>
      <textarea class="txt mono" name="source" rows="8" spellcheck="false" data-in="impSrc" placeholder="${esc(example)}"></textarea></div>
    <label class="chk"><input type="checkbox" name="replace" data-ch="impReplace"><span class="box"></span>Replace items that already exist</label>
    <div id="imp-plan"></div>
    <div id="imp-pics"></div>
    ${S.boot.bridge ? '' : note(`The bridge isn't installed, so new items save to the file and show up after ${esc((S.boot.inventory && S.boot.inventory.resource) || 'the inventory')} restarts.`, 'amber', 'fas fa-clock')}`;
  await form({ title: 'Import items & pictures', sub: `Adds a new script's items to ${st.list.name || 'the item list'} and uploads its pictures. A backup is made first.`, icon: 'fas fa-file-import', size: 'lg', ok: 'Import', body, focus: false, onOk: runImport });
  IMP.pics = []; IMP.plan = null;
};

/* ═══ edits made outside the game ═══════════════════════════════════════
   The server watches the data files and the picture folder. When someone saves items.lua over FTP
   (or drops new pictures in), the panel reloads what it shows instead of working on a stale copy. */
window.addEventListener('message', e => {
  const m = e.data || {};
  if (m.action !== 'dataChanged' || !S.open || !S.boot) return;
  const d = m.data || {};
  Object.entries(d.images || {}).forEach(([k, v]) => { S.img[k] = v; });
  if (d.msg) toast(d.msg, d.ok === false ? 'error' : d.live ? 'success' : 'warning', 8000);
  if (d.ok === false) return;
  const files = d.files || [];
  let stale = false;
  files.forEach(f => { const st = ED[f]; if (!st) return; if (st.dirty) stale = true; else st.list = null; });
  if (stale) toast('A file you have unsaved changes in was just changed outside the game. Copy your changes, then reload before saving.', 'warning', 10000);
  if (files.length) loadItems(true);
  const typing = document.activeElement && /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName);
  const P = PAGES[S.page];
  if (P && P.tier === 'editor' && S.page !== 'ed_files' && curFile && files.includes(curFile) && !ED[curFile].dirty) {
    const st = ED[curFile];
    edLoadList(curFile).then(() => { if (st.sel !== undefined && !st.creating) edOpen(curFile, st.sel); });
  } else if (S.page === 'ed_files' && files.includes(pd('files').file) && !pd('files').dirty) {
    rawLoad(pd('files').file);
  } else if (d.images && !typing && !$('#modal').innerHTML) {
    rerender();
  }
});
