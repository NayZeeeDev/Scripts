/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · EMS Manager (app 'manager')        module: hospital
   v5 window: explorer (search, All / Linked / Standalone, department folders with
   Overview, Roster, Grades, Outfits, Positions, Garage, area folders, Hospital section)
   + editor (identity, integrations, easy mode, HQ, map blip, roster, grades with
   permission chips, outfits, positions with in-world placement, garage, funds).

   Lua → JS   open { mode = 'admin'|'boss', data, types, me, locale, resume, placed }
              open { compact = true, mode = 'locker'|'stash'|'storage'|'garage'|'elevator', ... }
   JS → Lua   manager:create|save|delete|hire|grade|fire|pointData|pointDelete|funds|place|goto|
              capture|tryOn|restore|refresh            (replies { ok, msg, data })
              manager:wear|civvies|take|spawn|floor|stashMove   (compact menus)
   Keys: ESC close (asks first when there are unsaved changes) · Ctrl+S save
   ═══════════════════════════════════════════════════════════ */
(() => {
  const esc = NZA.esc, icon = NZA.icon;
  const APP = 'manager';
  let LOC = {};
  const T = (k, fb, ...a) => { let s = LOC[k] !== undefined ? String(LOC[k]) : (fb !== undefined ? fb : k); a.forEach(v => { s = s.replace(/%[sd]/, v); }); return s; };
  const clone = o => JSON.parse(JSON.stringify(o === undefined ? null : o));
  const num = (v, d = 0) => { const n = Number(v); return Number.isFinite(n) ? n : d; };
  const initials = n => String(n || '?').split(/\s+/).filter(Boolean).slice(0, 2).map(s => s[0]).join('').toUpperCase() || '?';
  const human = k => String(k).replace(/_/g, ' ').replace(/([a-z])([A-Z])/g, '$1 $2').replace(/^./, c => c.toUpperCase());

  const PERM_ICON = {
    assess: 'stetho', basic: 'bandage', cpr: 'heart', defib: 'defib', iv: 'iv', blood: 'bloodbag', binder: 'bone',
    splint: 'splint', suture: 'needle', burn: 'flame', graft: 'scalpel', airway: 'lungs', ultrasound: 'probe',
    chestdrain: 'tube', pericardio: 'syringe', xray: 'xray', surgery: 'scalpel', angio: 'monitor', meds: 'pill',
    transport: 'ambulance', bodybag: 'skull', checkin: 'ticket', pharmacy: 'store', manage: 'crown',
  };
  // explorer folders: every position type lands in one (unknown types → "Other")
  const FOLDERS = [
    { id: 'station', label: 'Station', icon: 'badge', types: ['duty', 'locker', 'stash', 'boss', 'storage'], unit: 'loc' },
    { id: 'pharmacy', label: 'Pharmacy', icon: 'pill', types: ['pharmacy'], unit: 'loc' },
    { id: 'checkin', label: 'Check-in', icon: 'ticket', types: ['checkin', 'tv'], unit: 'desk' },
    { id: 'blood', label: 'Transfusion', icon: 'bloodbag', types: ['bloodbank', 'donation'], unit: 'loc' },
    { id: 'surgery', label: 'Surgery', icon: 'scalpel', types: ['surgery'], unit: 'loc' },
    { id: 'angio', label: 'Angiography suite', icon: 'monitor', types: ['angio'], unit: 'loc' },
    { id: 'xray', label: 'X-ray', icon: 'xray', types: ['xray', 'lightbox'], unit: 'loc' },
    { id: 'ultrasound', label: 'Ultrasound', icon: 'probe', types: ['ultrasound'], unit: 'loc' },
    { id: 'beds', label: 'Beds', icon: 'bed', types: ['bed', 'respawn'], unit: 'bed' },
    { id: 'elevators', label: 'Elevators', icon: 'building', types: ['elevator'], unit: 'floor' },
    { id: 'morgue', label: 'Morgue', icon: 'skull', types: ['morgue'], unit: 'loc' },
  ];
  const GARAGE_TYPES = ['garage', 'heli'];
  const COMP = { 1: 'Mask', 3: 'Arms', 4: 'Legs', 5: 'Bag', 6: 'Shoes', 7: 'Neck', 8: 'Shirt', 9: 'Vest', 10: 'Decals', 11: 'Top' };
  const PROP = { 0: 'Hat', 1: 'Glasses', 2: 'Ears', 6: 'Watch', 7: 'Bracelet' };
  const SPRITE_ICON = { 61: 'cross', 153: 'medkit', 43: 'heli', 50: 'garage' };

  const S = {
    mode: 'admin', data: null, types: [], me: null,
    sel: { dept: null, view: 'overview' }, drafts: {}, base: {},
    expanded: new Set(), search: '', filter: 'all', posFilter: 'all',
    editing: null, showEasyPerms: false, busy: false,
  };
  let root = null, win = null, modal = null, C = null;   // C = compact state

  /* ═════════════════════════ helpers ═════════════════════════ */
  const isAdmin = () => S.mode === 'admin';
  const depts = () => (S.data && S.data.depts) || [];
  const server = id => depts().find(d => d.id === id) || null;
  const typeDef = name => S.types.find(t => t.name === name) || { name, label: human(name), icon: 'pin', kind: 'marker', data: {} };
  const staffOf = id => (S.data && S.data.staff && S.data.staff[id]) || [];
  const pointsOf = id => ((S.data && S.data.points) || []).filter(p => p.hospital === id);
  const blipHex = c => { const list = (S.data && S.data.blips && S.data.blips.colours) || []; const f = list.find(x => Number(x.id) === Number(c)); return f ? f.hex : '#e03232'; };

  function draft(id) {
    if (!S.drafts[id]) {
      const d = server(id);
      if (!d) return null;
      const c = clone(d);
      (c.grades || []).forEach(g => { g.from = g.level; });
      c.easyPerms = c.easyPerms || {};
      c.blip = c.blip || { enabled: true, sprite: 61, colour: 1, scale: 0.85, shortRange: true };
      S.drafts[id] = c;
      S.base[id] = JSON.stringify(c);
    }
    return S.drafts[id];
  }
  const dirty = id => !!S.drafts[id] && JSON.stringify(S.drafts[id]) !== S.base[id];
  const anyDirty = () => Object.keys(S.drafts).some(dirty);
  const view = () => S.sel.view;
  const myLevel = () => (S.data && S.data.me && S.data.me.grade) || 0;
  const bossLocked = level => S.mode === 'boss' && S.data && S.data.bossOutranks && level >= myLevel();

  function dist(c) {
    if (!c || !S.me) return null;
    const dx = c.x - S.me.x, dy = c.y - S.me.y, dz = c.z - S.me.z;
    return Math.sqrt(dx * dx + dy * dy + dz * dz);
  }
  const fmtDist = d => (d === null ? '' : d < 1000 ? `${Math.round(d)} m` : `${(d / 1000).toFixed(1)} km`);
  const fmtC = v => Number(v).toFixed(2);
  const money = n => `$${Math.round(num(n)).toLocaleString('en-US')}`;

  function toast(message, type = 'success', title) { NZA.toast({ title: title || T('mgr_title', 'EMS Manager'), message, type }); }

  async function act(event, payload, { quiet = false } = {}) {
    if (S.busy) return null;
    S.busy = true;
    let res = null;
    try { res = await NZA.post(`${APP}:${event}`, payload || {}); } catch (e) { res = null; }
    S.busy = false;
    if (!res || res.ok === false) {
      toast((res && res.msg) || T('err_failed', 'Something went wrong. Try again.'), 'error');
      return null;
    }
    if (res.me) S.me = res.me;
    if (res.types) S.types = res.types;
    if (res.data) applyData(res.data);
    if (res.msg && !quiet) toast(res.msg, 'success');
    return res;
  }

  function applyData(data) {
    S.data = data;
    S.mode = data.mode || S.mode;
    Object.keys(S.drafts).forEach(id => { if (!server(id)) { delete S.drafts[id]; delete S.base[id]; } });
    if (S.sel.dept && !server(S.sel.dept) && !String(S.sel.view).startsWith('h:')) S.sel.dept = null;
    if (!S.sel.dept && depts().length && !String(S.sel.view).startsWith('h:')) {
      S.sel.dept = depts()[0].id;
      S.sel.view = isAdmin() ? 'overview' : 'roster';
      S.expanded.add(S.sel.dept);
    }
  }

  /* ═════════════════════════ modals ═════════════════════════ */
  function closeModal() { if (modal) { modal.close(); modal = null; } }
  function confirmBox({ title, text, label, tone = 'red', ic = 'trash', onYes }) {
    closeModal();
    modal = NZA.ui.Modal({
      title, text, icon: ic, tone, host: root,
      actions: [
        { label: T('cancel', 'Cancel'), kind: 'line', onClick: () => { modal = null; } },
        { label, kind: tone === 'red' ? 'red' : 'teal', onClick: () => { modal = null; onYes && onYes(); } },
      ],
    });
  }

  function newDeptModal() {
    closeModal();
    const wrap = NZA.el('div', 'nza-modal-wrap');
    wrap.innerHTML = `<div class="nza-modal nza-pop">
      <div class="mx-mh"><div><h4>${esc(T('new_dept', 'New department'))}</h4><p>${esc(T('new_dept_sub', 'Create a hospital or EMS organisation'))}</p></div></div>
      <div class="mx-mform">
        <div class="mx-note">${esc(T('new_dept_note', 'The display name is shown in the explorer and on the map. The internal name identifies the department in code: letters, digits and underscore only.'))}</div>
        <div class="mx-f"><label>${esc(T('display_name', 'Display name'))}</label><input class="nz-input" data-n="label" maxlength="48" placeholder="Los Santos Medical"></div>
        <div class="mx-f"><label>${esc(T('internal_name', 'Internal name'))}</label><input class="nz-input mono" data-n="id" maxlength="32" placeholder="lsmd"></div>
        <div class="mx-err"></div>
      </div>
      <div class="mf"><button class="btn-line" data-a="cancel">${esc(T('cancel', 'Cancel'))}</button><button class="btn-teal" data-a="ok">${icon('plus')}${esc(T('create_dept', 'Create department'))}</button></div>
    </div>`;
    root.appendChild(wrap);
    const lab = wrap.querySelector('[data-n=label]'), idI = wrap.querySelector('[data-n=id]'), err = wrap.querySelector('.mx-err');
    let touched = false;
    const slug = s => s.toLowerCase().normalize('NFKD').replace(/[^\w\s]/g, '').trim().replace(/\s+/g, '_').replace(/[^a-z0-9_]/g, '').slice(0, 32);
    lab.addEventListener('input', () => { if (!touched) idI.value = slug(lab.value); err.textContent = ''; });
    idI.addEventListener('input', () => { touched = true; idI.value = idI.value.toLowerCase().replace(/[^a-z0-9_]/g, ''); err.textContent = ''; });
    const submit = async () => {
      const label = lab.value.trim(), id = idI.value.trim();
      if (!label) { err.textContent = T('err_need_label', 'Give the department a display name.'); lab.focus(); return; }
      if (!/^[a-z0-9_]{2,32}$/.test(id)) { err.textContent = T('err_bad_id_hint', 'Internal name: 2-32 letters, digits or underscore.'); idI.focus(); return; }
      if (server(id)) { err.textContent = T('err_exists_hint', 'A department with that internal name already exists.'); idI.focus(); return; }
      const res = await act('create', { id, label });
      if (!res) return;
      closeModal();
      select(res.dept || id, 'overview');
    };
    wrap.querySelector('[data-a=cancel]').onclick = closeModal;
    wrap.querySelector('[data-a=ok]').onclick = submit;
    [lab, idI].forEach(i => i.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); submit(); } }));
    modal = { close: () => wrap.remove(), el: wrap };
    setTimeout(() => lab.focus(), 30);
  }

  /* ═════════════════════════ shell ═════════════════════════ */
  function buildShell() {
    root.innerHTML = '<div class="nza-dim"></div>';
    win = NZA.ui.Win(root, {
      title: T('mgr_title', 'EMS Manager'),
      sub: isAdmin() ? T('sub_admin', 'Department editor') : T('sub_boss', 'Boss menu'),
      nav: [],
      status: [{ key: 'ESC', label: T('close', 'Close') }, { key: 'Ctrl S', label: T('save', 'Save') }],
      onClose: tryClose,
    });
    win.el.classList.add('mx-win');
    win.side.innerHTML = `
      <div class="mx-sh"><div class="nz-tile mute">${icon('hospital')}</div><div><b>${esc(T('departments', 'Departments'))}</b><span class="mx-count"></span></div></div>
      <label class="mx-search">${icon('search')}<input type="text" placeholder="${esc(T('search', 'Search departments'))}"></label>
      <div class="mx-filter"></div>
      <div class="mx-tree nza-scroll" data-wheel></div>`;
    const inp = win.side.querySelector('.mx-search input');
    inp.value = S.search;
    inp.addEventListener('input', () => { S.search = inp.value; renderTree(); });
    if (isAdmin()) {
      NZA.ui.Segmented(win.side.querySelector('.mx-filter'), {
        options: [{ value: 'all', label: T('f_all', 'All') }, { value: 'linked', label: T('f_linked', 'Linked') }, { value: 'standalone', label: T('f_standalone', 'Standalone') }],
        value: S.filter, onChange: v => { S.filter = v; renderTree(); },
      });
    } else {
      win.side.querySelector('.mx-filter').style.display = 'none';
      win.side.querySelector('.mx-search').style.display = 'none';
    }
    win.side.querySelector('.mx-tree').addEventListener('click', onTreeClick);
    if (!isAdmin() && S.data && S.data.me) {
      const me = S.data.me, d = server(me.dept), g = d && d.grades && d.grades[me.grade];
      const st = staffOf(me.dept).find(r => r.identifier === me.identifier);
      win.side.insertAdjacentHTML('beforeend', `<div class="mx-mecard"><div class="nz-av">${esc(initials(me.name))}</div><div><b>${esc(me.name || '')}</b><span>${esc(g ? g.label : '')}</span></div>${st && st.onDuty ? `<span class="nz-tag live">${esc(T('on_duty', 'On duty'))}</span>` : `<span class="nz-tag off">${esc(T('off_duty', 'Off duty'))}</span>`}</div>`);
    }
    win.main.innerHTML = '<div class="mx-main"></div>';
    renderTop();
  }

  function renderTop() {
    if (!win) return;
    const t = (S.data && S.data.totals) || {};
    win.setMid(`<span class="nz-dot"></span><p><b>${depts().length}</b> ${esc(depts().length === 1 ? T('mid_dept', 'department') : T('mid_depts', 'departments'))} · <b>${t.staff || 0}</b> ${esc(T('mid_staff', 'staff'))} · <b>${t.onDuty || 0}</b> ${esc(T('mid_duty', 'on duty'))}</p><span class="nz-ver">${esc(isAdmin() ? T('admin', 'Admin') : T('boss', 'Boss'))}</span>`);
    win.act.innerHTML = `<button class="btn-line btn-sm" data-a="refresh" title="${esc(T('refresh_help', 'Reload staff, duty and positions'))}">${icon('refresh')}${esc(T('refresh', 'Refresh'))}</button>${isAdmin() ? `<button class="btn-teal btn-sm" data-a="new">${icon('plus')}${esc(T('new_dept', 'New department'))}</button>` : ''}`;
    const nb = win.act.querySelector('[data-a=new]');
    if (nb) nb.onclick = newDeptModal;
    win.act.querySelector('[data-a=refresh]').onclick = async () => { if (await act('refresh', {}, { quiet: true })) { renderTop(); renderTree(); renderMain(); } };
    const cnt = win.side.querySelector('.mx-count');
    if (cnt) cnt.textContent = `${depts().length} ${T('dept_short', 'dept')} · ${t.staff || 0} ${T('employees', 'employees')}`;
  }

  function tryClose() {
    if (anyDirty()) {
      confirmBox({
        title: T('discard_title', 'Discard unsaved changes?'),
        text: T('discard_text', 'You changed departments without saving. Close anyway and lose those changes?'),
        label: T('discard', 'Discard & close'), ic: 'alert',
        onYes: () => { S.drafts = {}; S.base = {}; NZA.close(APP); },
      });
      return;
    }
    NZA.close(APP);
  }

  /* ═════════════════════════ explorer ═════════════════════════ */
  function folderTypes() {
    const known = new Set();
    FOLDERS.forEach(f => f.types.forEach(t => known.add(t)));
    GARAGE_TYPES.forEach(t => known.add(t));
    known.add('hq');
    const other = S.types.filter(t => t.manager !== false && !known.has(t.name)).map(t => t.name);
    return { other };
  }

  function foldersFor(id) {
    const pts = pointsOf(id);
    const reg = new Set(S.types.map(t => t.name));
    const out = FOLDERS.filter(f => f.types.some(t => reg.has(t) || pts.some(p => p.type === t)))
      .map(f => ({ ...f, count: pts.filter(p => f.types.includes(p.type)).length }));
    const { other } = folderTypes();
    const extra = pts.filter(p => !FOLDERS.some(f => f.types.includes(p.type)) && !GARAGE_TYPES.includes(p.type)).map(p => p.type);
    const otherTypes = [...new Set([...other, ...extra])];
    if (otherTypes.length) out.push({ id: 'other', label: T('folder_other', 'Other'), icon: 'grid', types: otherTypes, unit: 'loc', count: pts.filter(p => otherTypes.includes(p.type)).length });
    return out;
  }
  const folderById = (deptId, fid) => foldersFor(deptId).find(f => f.id === fid);

  function kidsFor(d) {
    const dr = S.drafts[d.id] || d;
    const pts = pointsOf(d.id);
    const st = staffOf(d.id);
    const items = [];
    if (isAdmin()) items.push({ v: 'overview', label: T('v_overview', 'Overview'), ic: 'cog' });
    items.push({ v: 'roster', label: T('v_roster', 'Roster'), ic: 'users', ct: st.length });
    items.push({ v: 'grades', label: T('v_grades', 'Grades'), ic: 'star', ct: (dr.grades || []).length });
    items.push({ v: 'outfits', label: T('v_outfits', 'Outfits'), ic: 'shirt', ct: (dr.outfits || []).length });
    if (isAdmin()) items.push({ v: 'positions', label: T('v_positions', 'Positions'), ic: 'pin', ct: pts.length });
    items.push({ v: 'garage', label: T('v_garage', 'Garage'), ic: 'car', ct: `${(dr.vehicles || []).length} ${T('u_veh', 'veh')}` });
    if (!isAdmin()) items.push({ v: 'funds', label: T('v_funds', 'Funds'), ic: 'bank', ct: money((S.data.society || {})[d.id] || 0) });
    let html = items.map(it => kidBtn(d.id, it)).join('');
    if (isAdmin()) {
      const fs = foldersFor(d.id);
      if (fs.length) {
        html += `<div class="mx-kgrp">${esc(T('areas', 'Areas'))}</div>`;
        html += fs.map(f => kidBtn(d.id, { v: `f:${f.id}`, label: T(`folder_${f.id}`, f.label), ic: f.icon, ct: `${f.count} ${T('u_' + f.unit, f.unit)}`, zero: f.count === 0 })).join('');
      }
    }
    return html;
  }
  function kidBtn(id, it) {
    const on = S.sel.dept === id && S.sel.view === it.v;
    return `<button class="mx-kid ${on ? 'on' : ''}" data-d="${esc(id)}" data-v="${esc(it.v)}">${icon(it.ic)}<span>${esc(it.label)}</span>${it.ct !== undefined ? `<span class="ct ${it.zero || it.ct === 0 ? 'z' : ''}">${esc(it.ct)}</span>` : ''}</button>`;
  }

  function renderTree() {
    if (!win) return;
    const tree = win.side.querySelector('.mx-tree');
    const q = S.search.trim().toLowerCase();
    const list = depts().filter(d => {
      if (S.filter === 'linked' && !d.job) return false;
      if (S.filter === 'standalone' && d.job) return false;
      if (!q) return true;
      return [d.label, d.id, d.job, d.description].some(x => String(x || '').toLowerCase().includes(q));
    });
    let html = list.map(d => {
      const dr = S.drafts[d.id] || d;
      const open = S.expanded.has(d.id) || (q && list.length <= 3);
      const sel = S.sel.dept === d.id && !String(S.sel.view).startsWith('h:');
      const sub = d.job ? T('linked_to', 'Job · %s', d.job) : T('standalone', 'Standalone');
      return `<div class="mx-folder ${open ? 'open' : ''} ${sel ? 'sel' : ''}">
        <button class="mx-fh" data-f="${esc(d.id)}">${icon('chev-r', 'chev')}<span class="bdot" style="background:${esc(blipHex(dr.blip && dr.blip.colour))}"></span>
          <span class="nm"><b>${esc(dr.label || d.id)}</b><span>${esc(sub)} · ${staffOf(d.id).length} ${esc(T('members_short', 'staff'))}</span></span>${dirty(d.id) ? '<span class="dirty"></span>' : ''}</button>
        <div class="mx-kids">${kidsFor(d)}</div></div>`;
    }).join('');
    if (!list.length) html = `<div class="mx-empty-tree">${esc(depts().length ? T('no_match', 'No department matches.') : T('no_depts', 'No departments yet.'))}</div>`;
    if (isAdmin()) {
      html += `<div class="mx-sec">${esc(T('hospital', 'Hospital'))}</div>`;
      html += [
        { v: 'h:overview', label: T('h_overview', 'All departments'), ic: 'grid', ct: depts().length },
        { v: 'h:positions', label: T('h_positions', 'Every position'), ic: 'map', ct: ((S.data && S.data.points) || []).length },
        { v: 'h:duty', label: T('h_duty', 'On duty now'), ic: 'pulse', ct: (S.data && S.data.totals && S.data.totals.onDuty) || 0 },
      ].map(it => `<button class="mx-kid ${S.sel.view === it.v ? 'on' : ''}" style="padding-left:10px" data-v="${it.v}">${icon(it.ic)}<span>${esc(it.label)}</span><span class="ct">${esc(it.ct)}</span></button>`).join('');
    }
    tree.innerHTML = html;
  }

  function onTreeClick(e) {
    const fh = e.target.closest('.mx-fh');
    if (fh) {
      const id = fh.dataset.f;
      if (S.expanded.has(id) && S.sel.dept === id) S.expanded.delete(id); else S.expanded.add(id);
      if (S.sel.dept !== id || String(S.sel.view).startsWith('h:')) select(id, isAdmin() ? 'overview' : 'roster');
      else renderTree();
      return;
    }
    const k = e.target.closest('.mx-kid');
    if (k) select(k.dataset.d || null, k.dataset.v);
  }

  function select(id, v) {
    if (id) { S.sel.dept = id; S.expanded.add(id); }
    S.sel.view = v || S.sel.view;
    S.editing = null;
    renderTree();
    renderMain();
  }

  /* ═════════════════════════ main area ═════════════════════════ */
  const VIEW_LABEL = () => ({
    overview: [T('v_overview', 'Overview'), T('v_overview_sub', 'Identity, integrations, easy mode, HQ and map blip')],
    roster: [T('v_roster', 'Roster'), T('v_roster_sub', 'Hire, promote and fire. Refresh to update who is online and on duty.')],
    grades: [T('v_grades', 'Grades'), T('v_grades_sub', 'Ranks from lowest to highest. Each grade has a salary and its own permissions.')],
    outfits: [T('v_outfits', 'Outfits'), T('v_outfits_sub', 'Uniforms for the lockers. Dress your character, then save it for male or female.')],
    positions: [T('v_positions', 'Positions'), T('v_positions_sub', 'Every placed spot of this department. Click a type to drop a new one where you look.')],
    garage: [T('v_garage', 'Garage'), T('v_garage_sub', 'Vehicles per grade and the spots they spawn at.')],
    funds: [T('v_funds', 'Funds'), T('v_funds_sub', 'The department society account.')],
    'h:overview': [T('h_overview', 'All departments'), T('h_overview_sub', 'Every department on the server at a glance.')],
    'h:positions': [T('h_positions', 'Every position'), T('h_positions_sub', 'All placed positions of all departments.')],
    'h:duty': [T('h_duty', 'On duty now'), T('h_duty_sub', 'Medics on duty right now, by department.')],
  });

  function head({ title, sub, crumb, actions = '' }) {
    return `<div class="mx-head"><div>${crumb ? `<div class="mx-crumb">${crumb}</div>` : ''}<h1>${title}</h1>${sub ? `<p>${esc(sub)}</p>` : ''}</div><div class="mx-hact">${actions}</div></div>`;
  }

  function deptActions(id, withDelete) {
    const dt = dirty(id);
    return `${dt ? `<span class="mx-unsaved"><i></i>${esc(T('unsaved', 'Unsaved changes'))}</span>` : ''}
      ${dt ? `<button class="btn-line btn-sm" data-a="revert">${icon('rot-l')}${esc(T('revert', 'Revert'))}</button>` : ''}
      <button class="btn-teal" data-a="save" ${dt ? '' : 'disabled'}>${icon('save')}${esc(T('save', 'Save'))}</button>
      ${withDelete && isAdmin() ? `<button class="btn-red" data-a="delete">${icon('trash')}${esc(T('delete', 'Delete'))}</button>` : ''}`;
  }

  function refreshDirtyUi() {
    if (!win) return;
    const id = S.sel.dept;
    const hact = win.main.querySelector('.mx-hact');
    if (hact && id && hact.querySelector('[data-a=save]')) {
      hact.innerHTML = deptActions(id, S.sel.view === 'overview');
      bindHeadActions();
    }
    renderTree();
  }

  function bindHeadActions() {
    const m = win.main;
    const q = s => m.querySelector(`.mx-hact ${s}`);
    if (q('[data-a=save]')) q('[data-a=save]').onclick = save;
    if (q('[data-a=revert]')) q('[data-a=revert]').onclick = () => { const id = S.sel.dept; delete S.drafts[id]; delete S.base[id]; renderMain(); renderTree(); };
    if (q('[data-a=delete]')) q('[data-a=delete]').onclick = askDelete;
  }

  async function save() {
    const id = S.sel.dept;
    if (!id || !dirty(id)) return;
    const d = S.drafts[id];
    const res = await act('save', { dept: d });
    if (!res) return;
    delete S.drafts[id]; delete S.base[id];
    renderTop(); renderTree(); renderMain();
  }

  function askDelete() {
    const id = S.sel.dept, d = server(id);
    if (!d) return;
    confirmBox({
      title: T('delete_title', 'Delete %s?', d.label),
      text: T('delete_text', 'This removes the department, its %s positions and %s staff records. It cannot be undone.', pointsOf(id).length, staffOf(id).length),
      label: T('delete_dept', 'Delete department'),
      onYes: async () => {
        const res = await act('delete', { id });
        if (!res) return;
        delete S.drafts[id]; delete S.base[id];
        S.sel.dept = depts()[0] ? depts()[0].id : null;
        S.sel.view = 'overview';
        renderTop(); renderTree(); renderMain();
      },
    });
  }

  function renderMain() {
    if (!win) return;
    const host = win.main.querySelector('.mx-main');
    const v = S.sel.view;
    const labels = VIEW_LABEL();
    if (v.startsWith('h:')) {
      const [tt, sub] = labels[v];
      host.innerHTML = head({ title: esc(tt), sub, crumb: `${icon('hospital')}<b>${esc(T('hospital', 'Hospital'))}</b>` }) + '<div class="mx-body nza-scroll" data-wheel></div>';
      const body = host.querySelector('.mx-body');
      if (v === 'h:overview') hospitalOverview(body);
      else if (v === 'h:positions') positionsView(body, null, null, true);
      else dutyView(body);
      return;
    }
    const id = S.sel.dept;
    const d = server(id);
    if (!d) {
      host.innerHTML = `<div class="mx-welcome"><div><div class="nz-mark xl"></div><h2>${esc(T('welcome_title', 'No department selected'))}</h2>
        <p>${esc(isAdmin() ? T('welcome_text', 'Create a department to start: give it grades and permissions, dress its lockers and place its duty, stash, garage, beds and treatment rooms in the world.') : T('welcome_boss', 'Your department could not be loaded.'))}</p>
        ${isAdmin() ? `<button class="btn-teal btn-lg" data-a="new">${icon('plus')}${esc(T('new_dept', 'New department'))}</button>` : ''}</div></div>`;
      const nb = host.querySelector('[data-a=new]');
      if (nb) nb.onclick = newDeptModal;
      return;
    }
    const dr = draft(id);
    let tt, sub;
    if (v.startsWith('f:')) {
      const f = folderById(id, v.slice(2));
      tt = f ? T(`folder_${f.id}`, f.label) : T('v_positions', 'Positions');
      sub = T('folder_sub', 'Positions in this area. Click a type to place one where you look.');
    } else {
      [tt, sub] = labels[v] || labels.overview;
    }
    const editable = ['overview', 'grades', 'outfits', 'garage'].includes(v);
    const titleHtml = `${esc(v === 'overview' ? (dr.label || d.id) : tt)}${v === 'overview' ? ` <span class="nz-tag ${d.job ? 'live' : 'off'}">${esc(d.job ? T('linked_to', 'Job · %s', d.job) : T('standalone', 'Standalone'))}</span>` : ''}`;
    host.innerHTML = head({
      title: titleHtml, sub: v === 'overview' ? (d.job ? T('linked_sub', 'Members with the framework job "%s" join automatically.', d.job) : T('standalone_sub', 'No framework job linked. Members are hired here.')) : sub,
      crumb: `${icon('building')}<b>${esc(dr.label || d.id)}</b>${v !== 'overview' ? ` ${icon('chev-r')} ${esc(tt)}` : ''}`,
      actions: editable ? deptActions(id, v === 'overview') : '',
    }) + '<div class="mx-body nza-scroll" data-wheel></div>';
    bindHeadActions();
    const body = host.querySelector('.mx-body');
    if (v === 'overview') overviewView(body, dr, d);
    else if (v === 'roster') rosterView(body, d);
    else if (v === 'grades') gradesView(body, dr);
    else if (v === 'outfits') outfitsView(body, dr);
    else if (v === 'positions') positionsView(body, d, null, false);
    else if (v === 'garage') garageView(body, dr, d);
    else if (v === 'funds') fundsView(body, d);
    else if (v.startsWith('f:')) { const f = folderById(id, v.slice(2)); positionsView(body, d, f ? f.types : [], false); }
  }

  const stat = (ic, label, value, tone = '') => `<div class="w-stat"><div class="nz-tile ${tone}">${icon(ic)}</div><div><span>${esc(label)}</span><b>${esc(value)}</b></div></div>`;
  const card = (ic, title, sub, body, extra = '', tone = '') => `<div class="mx-card"><div class="mx-ch"><div class="nz-tile ${tone}">${icon(ic)}</div><div class="sp"><h3>${esc(title)}</h3>${sub ? `<p>${esc(sub)}</p>` : ''}</div>${extra}</div><div class="mx-cb">${body}</div></div>`;

  function bindInputs(scope, target) {
    scope.querySelectorAll('[data-k]').forEach(inp => {
      inp.addEventListener('input', () => {
        const k = inp.dataset.k;
        let v = inp.value;
        if (inp.type === 'number') v = inp.value === '' ? null : Number(inp.value);
        const path = k.split('.');
        let o = target;
        for (let i = 0; i < path.length - 1; i++) { o[path[i]] = o[path[i]] || {}; o = o[path[i]]; }
        o[path[path.length - 1]] = v;   // '' clears a field on the server (job, discord, society)
        if (inp.dataset.live) renderLive(inp.dataset.live);
        refreshDirtyUi();
      });
    });
  }
  let liveFns = {};
  const renderLive = k => { if (liveFns[k]) liveFns[k](); };

  /* ── overview ── */
  function overviewView(body, dr, d) {
    liveFns = {};
    const st = staffOf(d.id);
    const onDuty = st.filter(s => s.onDuty).length;
    const pts = pointsOf(d.id);
    const hq = dr.hq;
    const hqDist = hq ? dist(hq) : null;
    const perms = (S.data.perms || []);
    const b = dr.blip;
    const colours = (S.data.blips && S.data.blips.colours) || [];
    const sprites = (S.data.blips && S.data.blips.sprites) || [];
    body.innerHTML = `
      <div class="mx-stats">${stat('users', T('st_staff', 'Staff'), st.length)}${stat('pulse', T('st_duty', 'On duty'), onDuty)}${stat('pin', T('st_positions', 'Positions'), pts.length, 'mute')}${stat('car', T('st_vehicles', 'Vehicles'), (dr.vehicles || []).length, 'mute')}</div>
      <div class="mx-grid">
        <div class="mx-col">
          ${card('id', T('c_identity', 'Identity'), T('c_identity_sub', 'How the department is named in menus, on the map and in code'), `
            <div class="mx-row2">
              <div class="mx-f"><label>${esc(T('display_name', 'Display name'))}</label><input class="nz-input" data-k="label" data-live="blip" maxlength="48" value="${esc(dr.label || '')}"></div>
              <div class="mx-f"><label>${icon('lock')}${esc(T('internal_name', 'Internal name'))}</label><input class="nz-input mono" value="${esc(dr.id)}" disabled></div>
            </div>
            <div class="mx-f"><label>${esc(T('description', 'Description'))}</label><textarea class="nz-input" data-k="description" maxlength="400" placeholder="${esc(T('description_ph', 'Optional. Shown to staff in the boss menu.'))}">${esc(dr.description || '')}</textarea></div>`)}
          ${card('link', T('c_integrations', 'Integrations'), T('c_integrations_sub', 'Framework job, Discord role and the society account that pays'), `
            <div class="mx-row2">
              <div class="mx-f"><label>${esc(T('framework_job', 'Framework job'))}</label><input class="nz-input mono" data-k="job" maxlength="40" placeholder="ambulance" value="${esc(dr.job || '')}"><small>${esc(T('framework_job_help', 'Players with this job are members. Leave empty for a standalone department.'))}</small></div>
              <div class="mx-f"><label>${esc(T('discord_role', 'Discord role'))}</label><input class="nz-input mono" data-k="discord" maxlength="24" placeholder="123456789012345678" value="${esc(dr.discord || '')}"><small>${esc(T('discord_help', 'Role id, for your Discord bot or logs.'))}</small></div>
            </div>
            <div class="mx-f"><label>${esc(T('society', 'Society account'))}</label><input class="nz-input mono" data-k="society" maxlength="40" placeholder="${esc(dr.job || dr.id)}" value="${esc(dr.society || '')}"><small>${esc(T('society_help', 'Bills, the boss menu and paychecks use this account. Empty = the job name.'))}</small></div>`)}
          ${card('bolt', T('c_easy', 'Easy mode'), T('c_easy_sub', 'For servers that want treatment without minigames'), `
            <div class="mx-opt"><div class="t"><b>${esc(T('easy_label', 'Replace minigames with progress bars'))}</b><small>${esc(T('easy_text', "On-duty medics of this department get a progress bar instead of the minigame. Treatment then only needs the injury's supplies, wherever the patient lies: no X-ray, operating table, blood or special room."))}</small></div><span data-h="easy"></span></div>
            <span class="mx-more ${S.showEasyPerms ? 'open' : ''}" data-a="easyperms">${icon('chev-r')}${esc(T('easy_per_perm', 'Per permission'))} <span class="t-dim" data-h="easycount"></span></span>
            <div data-h="easychips" style="display:${S.showEasyPerms ? '' : 'none'}"></div>`, '', 'amber')}
        </div>
        <div class="mx-col">
          ${card('flag', T('c_hq', 'HQ location'), T('c_hq_sub', 'Centre of the department: the map blip sits here'), hq ? `
            <div class="mx-coords"><span class="mx-cc"><i>X</i>${fmtC(hq.x)}</span><span class="mx-cc"><i>Y</i>${fmtC(hq.y)}</span><span class="mx-cc"><i>Z</i>${fmtC(hq.z)}</span><span class="mx-cc"><i>H</i>${num(hq.w).toFixed(1)}</span></div>
            <div class="mx-btns"><button class="btn-line" data-a="hqgo">${icon('pin')}${esc(T('go_to', 'Go to'))}</button><button class="btn-line" data-a="hqplace">${icon('target')}${esc(T('replace', 'Re-place in-world'))}</button>${hqDist !== null ? `<span class="t-dim" style="font-size:11px;align-self:center">${esc(T('away', '%s away', fmtDist(hqDist)))}</span>` : ''}</div>` : `
            <div class="mx-none" style="padding:18px">${icon('flag')}<b>${esc(T('no_hq', 'No HQ yet'))}</b><span>${esc(T('no_hq_text', 'Stand at the front of the hospital and place the HQ. The map blip appears there.'))}</span><button class="btn-teal" data-a="hqplace">${icon('target')}${esc(T('place_hq', 'Place HQ'))}</button></div>`)}
          ${card('map', T('c_blip', 'Map blip'), T('c_blip_sub', 'How the department shows on the pause map and minimap'), `
            <div class="mx-opt"><div class="t"><b>${esc(T('blip_show', 'Show on the map'))}</b><small>${esc(T('blip_show_help', 'Needs an HQ location.'))}</small></div><span data-h="blipon"></span></div>
            <div class="mx-map" data-h="preview"></div>
            <div class="mx-f"><label>${esc(T('colour', 'Colour'))}</label><div class="mx-swatches">${colours.map(c => `<span class="mx-sw ${Number(b.colour) === Number(c.id) ? 'on' : ''}" data-col="${esc(c.id)}" style="background:${esc(c.hex)};color:${esc(c.hex)}" title="${esc(c.id)}"></span>`).join('')}</div></div>
            <div class="mx-f"><label>${esc(T('sprite', 'Sprite'))}</label><div class="mx-sprites">${sprites.map(s => `<button class="chipx sm ${Number(b.sprite) === Number(s.id) ? 'on' : ''}" data-spr="${esc(s.id)}">${esc(s.label)}</button>`).join('')}<input class="nz-input mono" type="number" min="1" max="900" data-k="blip.sprite" data-live="blip" value="${esc(b.sprite)}" title="${esc(T('sprite_id', 'Any GTA blip id'))}"></div></div>
            <div class="mx-row2">
              <div class="mx-f"><label>${esc(T('scale', 'Scale'))}</label><span data-h="scale"></span></div>
              <div class="mx-f"><label>${esc(T('blip_label', 'Label'))}</label><input class="nz-input" data-k="blip.label" data-live="blip" maxlength="48" placeholder="${esc(dr.label)}" value="${esc(b.label && b.label !== dr.label ? b.label : '')}"></div>
            </div>
            <div class="mx-opt"><div class="t"><b>${esc(T('short_range', 'Short range'))}</b><small>${esc(T('short_range_help', 'Only on the minimap when you are close. Always on the pause map.'))}</small></div><span data-h="short"></span></div>`)}
        </div>
      </div>`;
    bindInputs(body, dr);
    // easy mode
    const easyChipsHost = body.querySelector('[data-h=easychips]');
    const effective = () => perms.filter(p => (dr.easyPerms[p.key] !== undefined ? dr.easyPerms[p.key] : dr.easy)).map(p => p.key);
    const countEl = body.querySelector('[data-h=easycount]');
    const setCount = () => { countEl.textContent = `· ${effective().length}/${perms.length}`; };
    let chips = null;
    const buildChips = () => {
      easyChipsHost.innerHTML = '';
      chips = NZA.ui.Chips(easyChipsHost, {
        options: perms.map(p => ({ value: p.key, label: p.label, icon: PERM_ICON[p.key] || 'check' })), values: effective(),
        onChange: vals => { const set = new Set(vals); dr.easyPerms = {}; perms.forEach(p => { const on = set.has(p.key); if (on !== dr.easy) dr.easyPerms[p.key] = on; }); setCount(); refreshDirtyUi(); },
      });
      chips.el.classList.add('mx-chips');
    };
    buildChips(); setCount();
    NZA.ui.Toggle(body.querySelector('[data-h=easy]'), { on: !!dr.easy, onChange: v => { dr.easy = v; dr.easyPerms = {}; buildChips(); setCount(); refreshDirtyUi(); } });
    body.querySelector('[data-a=easyperms]').onclick = e => { S.showEasyPerms = !S.showEasyPerms; e.currentTarget.classList.toggle('open', S.showEasyPerms); easyChipsHost.style.display = S.showEasyPerms ? '' : 'none'; };
    // HQ
    const hg = body.querySelector('[data-a=hqgo]');
    if (hg) hg.onclick = () => NZA.post(`${APP}:goto`, { coords: dr.hq });
    body.querySelectorAll('[data-a=hqplace]').forEach(bt => { bt.onclick = () => place({ dept: dr.id, hq: true }); });
    // blip
    const prev = body.querySelector('[data-h=preview]');
    liveFns.blip = () => {
      const h1 = win && win.main.querySelector('.mx-head h1');
      if (h1 && h1.firstChild && h1.firstChild.nodeType === 3) h1.firstChild.textContent = `${dr.label || dr.id} `;
      const size = Math.round(20 * num(b.scale, 0.85));
      prev.innerHTML = `<span class="me"></span><div class="mx-pin" style="opacity:${b.enabled === false ? 0.25 : 1}"><span class="bp" style="width:${size}px;height:${size}px;background:${esc(blipHex(b.colour))}">${icon(SPRITE_ICON[Number(b.sprite)] || 'pin')}</span><span class="tl">${esc((b.label && b.label.trim()) || dr.label || dr.id)}</span></div>`;
      body.querySelectorAll('[data-spr]').forEach(x => x.classList.toggle('on', Number(x.dataset.spr) === Number(b.sprite)));
    };
    liveFns.blip();
    NZA.ui.Toggle(body.querySelector('[data-h=blipon]'), { on: b.enabled !== false, onChange: v => { b.enabled = v; liveFns.blip(); refreshDirtyUi(); } });
    NZA.ui.Toggle(body.querySelector('[data-h=short]'), { on: b.shortRange !== false, onChange: v => { b.shortRange = v; refreshDirtyUi(); } });
    NZA.ui.Slider(body.querySelector('[data-h=scale]'), { min: 0.4, max: 2, step: 0.05, value: num(b.scale, 0.85), format: v => `${v.toFixed(2)}×`, onChange: v => { b.scale = Math.round(v * 100) / 100; liveFns.blip(); refreshDirtyUi(); } });
    body.querySelectorAll('[data-col]').forEach(sw => {
      sw.onclick = () => { b.colour = Number(sw.dataset.col); body.querySelectorAll('[data-col]').forEach(x => x.classList.toggle('on', x === sw)); liveFns.blip(); refreshDirtyUi(); };
    });
    body.querySelectorAll('[data-spr]').forEach(bt => {
      bt.onclick = () => { b.sprite = Number(bt.dataset.spr); body.querySelector('[data-k="blip.sprite"]').value = b.sprite; liveFns.blip(); refreshDirtyUi(); };
    });
  }

  /* ── roster ── */
  function gradeOptions(d, sel, { lockAbove = false } = {}) {
    return (d.grades || []).map(g => `<option value="${g.level}" ${Number(sel) === g.level ? 'selected' : ''} ${lockAbove && bossLocked(g.level) ? 'disabled' : ''}>${esc(`${g.level} · ${g.label}`)}</option>`).join('');
  }

  function rosterView(body, d) {
    const rows = staffOf(d.id);
    const online = rows.filter(r => r.online).length, duty = rows.filter(r => r.onDuty).length;
    const members = new Set(rows.map(r => r.identifier));
    const pickable = ((S.data && S.data.online) || []).filter(p => !p.identifier || !members.has(p.identifier));
    const firstFree = (d.grades || []).find(g => !bossLocked(g.level));
    body.innerHTML = `
      <div class="mx-stats c3">${stat('users', T('st_members', 'Members'), rows.length)}${stat('signal', T('st_online', 'Online'), online, 'mute')}${stat('pulse', T('st_duty', 'On duty'), duty)}</div>
      ${card('user-plus', T('hire', 'Hire'), T('hire_sub', 'Pick an online player or type a server id / citizen id'), `
        <div class="mx-hire">
          <div class="mx-f"><label>${esc(T('online_player', 'Online player'))}</label><select class="nz-input" data-r="pick"><option value="">${esc(T('pick_player', 'Choose…'))}</option>${pickable.map(p => `<option value="${esc(p.src)}">${esc(`[${p.src}] ${p.name}`)}</option>`).join('')}</select></div>
          <div class="mx-f"><label>${esc(T('or_id', 'Or server id / citizen id'))}</label><input class="nz-input mono" data-r="target" maxlength="80" placeholder="12  ·  ABC12345"></div>
          <div class="mx-f"><label>${esc(T('grade', 'Grade'))}</label><select class="nz-input" data-r="grade">${gradeOptions(d, firstFree ? firstFree.level : 0, { lockAbove: true })}</select></div>
          <button class="btn-teal" data-a="hire">${icon('user-plus')}${esc(T('hire', 'Hire'))}</button>
        </div>`)}
      <div class="mx-card"><div class="mx-ch"><div class="nz-tile mute">${icon('users')}</div><div class="sp"><h3>${esc(T('staff', 'Staff'))}</h3><p>${esc(d.job ? T('staff_linked', 'Hired members, plus online players with the "%s" job', d.job) : T('staff_sub', 'Everyone hired into this department'))}</p></div></div>
        <div class="mx-cb" style="padding:6px 8px 8px">${rows.length ? `<table class="mx-table"><thead><tr><th>${esc(T('member', 'Member'))}</th><th>${esc(T('grade', 'Grade'))}</th><th>${esc(T('status', 'Status'))}</th><th>${esc(T('since', 'Since'))}</th><th></th></tr></thead><tbody>
          ${rows.map(r => {
            const locked = bossLocked(r.grade) || (S.mode === 'boss' && S.data.me && r.identifier === S.data.me.identifier);
            const tag = r.onDuty ? `<span class="nz-tag live">${esc(T('on_duty', 'On duty'))}</span>` : r.online ? `<span class="nz-tag off">${esc(T('off_duty', 'Off duty'))}</span>` : `<span class="nz-tag off" style="opacity:.6">${esc(T('offline', 'Offline'))}</span>`;
            return `<tr data-id="${esc(r.identifier)}">
              <td><div class="mx-who"><div class="nz-av">${esc(initials(r.name))}<i class="od ${r.onDuty ? 'on' : ''}" style="${r.online ? '' : 'display:none'}"></i></div><div><b>${esc(r.name)}${r.src ? ` <span class="t-dim" style="display:inline;font-family:var(--font)">#${esc(r.src)}</span>` : ''}</b><span>${esc(r.identifier)}</span></div></div></td>
              <td><select class="nz-input" data-r="grade" ${locked ? 'disabled' : ''}>${gradeOptions(d, r.grade, { lockAbove: true })}</select></td>
              <td>${tag}${r.linked ? ` <span class="nz-chip white" title="${esc(T('via_job_help', 'Member through the framework job'))}">${esc(T('via_job', 'via job'))}</span>` : ''}</td>
              <td class="mx-mono" style="font-size:11px">${esc(r.created ? String(r.created).slice(0, 10) : '—')}</td>
              <td><div class="mx-act"><button class="mx-ib red" data-a="fire" title="${esc(T('fire', 'Fire'))}" ${locked ? 'disabled' : ''}>${icon('user-x')}</button></div></td></tr>`;
          }).join('')}</tbody></table>` : `<div class="mx-none">${icon('users')}<b>${esc(T('no_staff', 'Nobody hired yet'))}</b><span>${esc(T('no_staff_text', 'Hire someone above. They get the grade\'s permissions as soon as they go on duty.'))}</span></div>`}</div></div>`;
    const pick = body.querySelector('[data-r=pick]'), tgt = body.querySelector('[data-r=target]');
    pick.onchange = () => { if (pick.value) tgt.value = pick.value; };
    body.querySelector('[data-a=hire]').onclick = async () => {
      const target = (tgt.value || pick.value || '').trim();
      if (!target) { toast(T('err_need_target', 'Pick a player or type an id.'), 'error'); tgt.focus(); return; }
      const res = await act('hire', { dept: d.id, target, grade: Number(body.querySelector('[data-r=grade]').value) });
      if (res) { renderTop(); renderTree(); renderMain(); }
    };
    body.querySelectorAll('tr[data-id]').forEach(tr => {
      const id = tr.dataset.id;
      const r = rows.find(x => x.identifier === id);
      const sel = tr.querySelector('select');
      sel.onchange = async () => {
        const res = await act('grade', { dept: d.id, identifier: id, grade: Number(sel.value) });
        if (!res) sel.value = r.grade;
        renderMain();
      };
      tr.querySelector('[data-a=fire]').onclick = () => confirmBox({
        title: T('fire_title', 'Fire %s?', r.name), text: T('fire_text', 'They lose every permission of %s right away.', d.label),
        label: T('fire', 'Fire'), ic: 'user-x',
        onYes: async () => { const res = await act('fire', { dept: d.id, identifier: id }); if (res) { renderTop(); renderTree(); renderMain(); } },
      });
    });
  }

  /* ── grades ── */
  function gradesView(body, dr) {
    const perms = S.data.perms || [];
    const grades = dr.grades;
    const lockText = l => (S.mode === 'boss' && l === myLevel() ? T('your_grade', 'YOUR GRADE') : T('above_you', 'ABOVE YOUR GRADE'));
    body.innerHTML = `<div class="mx-note">${esc(T('grades_note', 'Grade 0 is the lowest. Staff keep their place when you reorder or remove grades: removed grades move their people one step down.'))}</div>
      <div class="mx-gl">${grades.map((g, i) => {
        const locked = bossLocked(i);
        return `<div class="mx-card mx-gc ${locked ? 'locked' : ''}" data-i="${i}" data-lock="${esc(locked ? lockText(i) : '')}">
          <div class="mx-gh">
            <div class="mx-lv">${i}</div>
            <div class="mx-f"><label>${esc(T('grade_label', 'Label'))}</label><input class="nz-input" data-g="label" maxlength="32" value="${esc(g.label)}" ${locked ? 'disabled' : ''}></div>
            <div class="mx-f"><label>${esc(T('grade_name', 'Internal name'))}</label><input class="nz-input mono" data-g="name" maxlength="24" value="${esc(g.name)}" ${locked ? 'disabled' : ''}></div>
            <div class="mx-f"><label>${esc(T('salary', 'Salary'))}</label><div class="mx-pre"><span>$</span><input class="nz-input mono" type="number" min="0" data-g="salary" value="${esc(g.salary)}" ${locked ? 'disabled' : ''}></div></div>
            <div class="mx-act" style="align-self:end">
              <button class="mx-ib" data-a="up" title="${esc(T('move_down', 'Lower'))}" ${locked || i === 0 || bossLocked(i - 1) ? 'disabled' : ''}>${icon('arrow-up')}</button>
              <button class="mx-ib" data-a="down" title="${esc(T('move_up', 'Higher'))}" ${locked || i === grades.length - 1 || bossLocked(i + 1) ? 'disabled' : ''}>${icon('arrow-down')}</button>
              <button class="mx-ib red" data-a="del" title="${esc(T('remove', 'Remove'))}" ${locked || grades.length <= 1 ? 'disabled' : ''}>${icon('trash')}</button>
            </div>
          </div>
          <div class="mx-gb"><div class="top"><span>${esc(T('permissions', 'Permissions'))}</span><em><b>${g.perms.length}</b> / ${perms.length}${locked ? '' : ` · <a class="mx-link" data-a="all">${esc(T('all', 'All'))}</a> · <a class="mx-link" data-a="none">${esc(T('none', 'None'))}</a>${i > 0 ? ` · <a class="mx-link" data-a="copy">${esc(T('copy_below', 'Copy from grade %s', i - 1))}</a>` : ''}`}</em></div><div data-h="chips"></div></div>
        </div>`;
      }).join('')}</div>
      ${S.mode === 'boss' && grades.length >= myLevel() + 1 && S.data.bossOutranks ? '' : ''}
      <button class="mx-add" data-a="add">${icon('plus')}${esc(T('add_grade', 'Add a grade'))}</button>`;
    body.querySelectorAll('.mx-gc').forEach(cardEl => {
      const i = Number(cardEl.dataset.i), g = grades[i];
      const locked = bossLocked(i);
      const ch = NZA.ui.Chips(cardEl.querySelector('[data-h=chips]'), {
        options: perms.map(p => ({ value: p.key, label: p.label, icon: PERM_ICON[p.key] || 'check' })), values: g.perms,
        onChange: vals => { g.perms = perms.map(p => p.key).filter(k => vals.includes(k)); cardEl.querySelector('.top em b').textContent = g.perms.length; refreshDirtyUi(); },
      });
      ch.el.classList.add('mx-chips');
      if (locked) ch.el.style.pointerEvents = 'none';
      cardEl.querySelectorAll('[data-g]').forEach(inp => inp.addEventListener('input', () => {
        const k = inp.dataset.g;
        g[k] = k === 'salary' ? Math.max(0, Math.round(num(inp.value))) : (k === 'name' ? inp.value.replace(/[^\w-]/g, '') : inp.value);
        refreshDirtyUi();
      }));
      const a = s => cardEl.querySelector(`[data-a=${s}]`);
      if (a('up')) a('up').onclick = () => { [grades[i - 1], grades[i]] = [grades[i], grades[i - 1]]; renderMain(); refreshDirtyUi(); };
      if (a('down')) a('down').onclick = () => { [grades[i + 1], grades[i]] = [grades[i], grades[i + 1]]; renderMain(); refreshDirtyUi(); };
      if (a('del')) a('del').onclick = () => confirmBox({
        title: T('remove_grade', 'Remove "%s"?', g.label), text: T('remove_grade_text', 'Staff with this grade move one grade down when you save.'),
        label: T('remove', 'Remove'), onYes: () => { grades.splice(i, 1); renderMain(); refreshDirtyUi(); },
      });
      if (a('all')) a('all').onclick = () => { g.perms = perms.map(p => p.key); renderMain(); refreshDirtyUi(); };
      if (a('none')) a('none').onclick = () => { g.perms = []; renderMain(); refreshDirtyUi(); };
      if (a('copy')) a('copy').onclick = () => { g.perms = [...grades[i - 1].perms]; renderMain(); refreshDirtyUi(); };
    });
    body.querySelector('[data-a=add]').onclick = () => {
      if (grades.length >= num(S.data.limits && S.data.limits.grades, 20)) { toast(T('err_limit_hint', 'Limit reached.'), 'error'); return; }
      const g = { label: T('new_grade', 'New grade'), name: `grade${grades.length}`, salary: 0, perms: grades.length ? [...grades[grades.length - 1].perms] : [] };
      if (S.mode === 'boss') {
        // bosses add below their own grade
        const at = Math.min(myLevel(), grades.length);
        grades.splice(at, 0, g);
      } else grades.push(g);
      renderMain(); refreshDirtyUi();
    };
  }

  /* ── outfits ── */
  function outfitBits(data) {
    if (!data) return '';
    const bits = [];
    (data.components || []).forEach(c => { if (c[1] > 0 || c[0] === 11) bits.push(`${COMP[c[0]] || c[0]} ${c[1]}${c[2] ? `:${c[2]}` : ''}`); });
    (data.props || []).forEach(p => { if (p[1] >= 0) bits.push(`${PROP[p[0]] || p[0]} ${p[1]}`); });
    return bits.slice(0, 8).map(b => `<span>${esc(b)}</span>`).join('');
  }

  async function capture(gender) {
    const res = await NZA.post(`${APP}:capture`, {});
    if (!res || res.ok === false) { toast((res && res.msg) || T('err_failed', 'Something went wrong. Try again.'), 'error'); return null; }
    if (gender && res.gender !== gender) { toast(T('err_wrong_gender', 'You are wearing a %s character. Save it to that side.', res.gender === 'male' ? T('male', 'Male') : T('female', 'Female')), 'error'); return null; }
    return res;
  }

  function outfitsView(body, dr) {
    const list = dr.outfits = dr.outfits || [];
    const gradeOpts = (dr.grades || []).map(g => ({ value: String(g.level), label: g.label }));
    body.innerHTML = `
      <div class="mx-btns"><button class="btn-teal" data-a="new">${icon('plus')}${esc(T('outfit_new', 'New outfit from my clothes'))}</button><button class="btn-line" data-a="restore">${icon('rot-l')}${esc(T('restore_clothes', 'Put my own clothes back'))}</button></div>
      ${list.length ? `<div class="mx-og">${list.map((o, i) => `
        <div class="mx-card mx-oc" data-i="${i}">
          <div class="mx-ch"><div class="nz-tile">${icon('shirt')}</div><input class="nz-input" data-o="name" maxlength="32" value="${esc(o.name)}" style="flex:1"><button class="mx-ib red" data-a="del" title="${esc(T('remove', 'Remove'))}">${icon('trash')}</button></div>
          <div class="mx-cb">
            <div class="mx-f"><label>${esc(T('outfit_grades', 'Grades'))}</label><div data-h="grades"></div><small>${esc(o.grades && o.grades.length ? T('outfit_some', 'Only these grades see it in the locker.') : T('outfit_all', 'No grade picked: every grade sees it.'))}</small></div>
            <div class="mx-gs">${['male', 'female'].map(gd => `
              <div class="mx-g"><div class="gh"><b>${icon('person')}${esc(gd === 'male' ? T('male', 'Male') : T('female', 'Female'))}</b><span class="st ${o[gd] ? 'ok' : ''}">${esc(o[gd] ? T('saved_pieces', 'Saved') : T('empty', 'Empty'))}</span></div>
                <div class="bits">${o[gd] ? outfitBits(o[gd]) : `<span style="opacity:.6">${esc(T('outfit_empty', 'Dress up, then save'))}</span>`}</div>
                <div class="acts"><button class="btn-line btn-sm" data-a="cap" data-g="${gd}">${icon('download')}${esc(T('save_current', 'Save current'))}</button><button class="btn-line btn-sm" data-a="try" data-g="${gd}" ${o[gd] ? '' : 'disabled'}>${icon('eye')}${esc(T('try_on', 'Try on'))}</button></div></div>`).join('')}
            </div>
          </div>
        </div>`).join('')}</div>` : `<div class="mx-none">${icon('shirt')}<b>${esc(T('no_outfits', 'No outfits yet'))}</b><span>${esc(T('no_outfits_text', 'Put on the uniform with your clothing menu, then click "New outfit from my clothes". Do it once for a male and once for a female character.'))}</span></div>`}`;
    body.querySelector('[data-a=new]').onclick = async () => {
      if (list.length >= num(S.data.limits && S.data.limits.outfits, 40)) { toast(T('err_limit_hint', 'Limit reached.'), 'error'); return; }
      const res = await capture(null);
      if (!res) return;
      const o = { id: `o${Date.now().toString(36)}`, name: T('outfit_n', 'Outfit %s', list.length + 1), grades: [], male: null, female: null };
      o[res.gender] = res.data;
      list.push(o);
      renderMain(); refreshDirtyUi();
    };
    body.querySelector('[data-a=restore]').onclick = async () => { const r = await NZA.post(`${APP}:restore`, {}); if (r && r.msg) toast(r.msg, r.ok ? 'success' : 'error'); };
    body.querySelectorAll('.mx-oc').forEach(cardEl => {
      const o = list[Number(cardEl.dataset.i)];
      const ch = NZA.ui.Chips(cardEl.querySelector('[data-h=grades]'), {
        options: gradeOpts, values: (o.grades || []).map(String),
        onChange: vals => { o.grades = vals.map(Number).sort((a, b) => a - b); refreshDirtyUi(); },
      });
      ch.el.classList.add('mx-chips');
      cardEl.querySelector('[data-o=name]').addEventListener('input', e => { o.name = e.target.value; refreshDirtyUi(); });
      cardEl.querySelector('[data-a=del]').onclick = () => confirmBox({
        title: T('remove_outfit', 'Remove "%s"?', o.name), text: T('remove_outfit_text', 'It disappears from the lockers when you save.'),
        label: T('remove', 'Remove'), onYes: () => { list.splice(list.indexOf(o), 1); renderMain(); refreshDirtyUi(); },
      });
      cardEl.querySelectorAll('[data-a=cap]').forEach(bt => { bt.onclick = async () => { const res = await capture(bt.dataset.g); if (!res) return; o[bt.dataset.g] = res.data; renderMain(); refreshDirtyUi(); }; });
      cardEl.querySelectorAll('[data-a=try]').forEach(bt => { bt.onclick = () => { const data = o[bt.dataset.g]; if (data) NZA.post(`${APP}:tryOn`, { data }); }; });
    });
  }

  /* ── positions ── */
  function place(payload) {
    if (!isAdmin()) return;
    NZA.post(`${APP}:place`, payload);
  }

  function pointSummary(p, t) {
    const data = Object.assign({}, t.data || {}, p.data || {});
    return Object.keys(data).filter(k => typeof data[k] !== 'object').slice(0, 3).map(k => {
      const v = data[k];
      return `<span class="nz-chip white">${esc(T(`field_${k}`, human(k)))}: ${esc(typeof v === 'boolean' ? (v ? T('yes', 'yes') : T('no', 'no')) : v)}</span>`;
    }).join('');
  }

  function pointEditor(p, t) {
    const data = Object.assign({}, clone(t.data || {}), clone(p.data || {}));
    const fields = Object.keys(data).filter(k => typeof data[k] !== 'object').map(k => {
      const v = data[k];
      const lab = `<label>${esc(T(`field_${k}`, human(k)))}</label>`;
      if (typeof v === 'boolean') return `<div class="mx-f">${lab}<span data-bool="${esc(k)}"></span></div>`;
      if (typeof v === 'number') return `<div class="mx-f">${lab}<input class="nz-input mono" type="number" data-pf="${esc(k)}" value="${esc(v)}"></div>`;
      return `<div class="mx-f">${lab}<input class="nz-input" data-pf="${esc(k)}" maxlength="120" value="${esc(v)}"></div>`;
    }).join('');
    return { html: `<div class="mx-pe">
      <div class="mx-fields"><div class="mx-f"><label>${esc(T('point_label', 'Label'))}</label><input class="nz-input" data-pf="__label" maxlength="64" placeholder="${esc(t.label)}" value="${esc(p.label || '')}"></div>${fields}</div>
      ${t.desc ? `<div class="mx-note">${esc(t.desc)}</div>` : ''}
      <div class="foot"><button class="btn-line btn-sm" data-a="cancel">${esc(T('cancel', 'Cancel'))}</button><button class="btn-teal btn-sm" data-a="savep">${icon('save')}${esc(T('save', 'Save'))}</button></div></div>`, data };
  }

  function positionsView(body, d, typesFilter, all) {
    const pts = all ? ((S.data && S.data.points) || []) : pointsOf(d.id);
    const regTypes = S.types.filter(t => t.manager !== false && (!typesFilter || typesFilter.includes(t.name)));
    const shownTypes = typesFilter ? [...new Set([...regTypes.map(t => t.name), ...typesFilter])] : null;
    let list = pts.filter(p => !shownTypes || shownTypes.includes(p.type));
    const counts = {};
    list.forEach(p => { counts[p.type] = (counts[p.type] || 0) + 1; });
    const filterTypes = Object.keys(counts).sort();
    if (!typesFilter && S.posFilter !== 'all' && !counts[S.posFilter]) S.posFilter = 'all';
    if (!typesFilter && S.posFilter !== 'all') list = list.filter(p => p.type === S.posFilter);
    list = list.slice().sort((a, b) => (a.hospital === b.hospital ? (a.type === b.type ? a.id - b.id : String(a.type).localeCompare(b.type)) : String(a.hospital).localeCompare(b.hospital)));
    const kindLabel = k => ({ prop: T('k_prop', 'Prop'), marker: T('k_marker', 'Marker'), car: T('k_car', 'Vehicle'), heli: T('k_heli', 'Helicopter') }[k] || k);

    const addHtml = !all && regTypes.length ? `<div class="mx-card"><div class="mx-ch"><div class="nz-tile">${icon('plus')}</div><div class="sp"><h3>${esc(T('add_position', 'Add a position'))}</h3><p>${esc(T('add_position_sub', 'Opens placement mode: aim where it goes, E to confirm.'))}</p></div></div>
      <div class="mx-cb"><div class="mx-types">${regTypes.map(t => `<button class="mx-type" data-t="${esc(t.name)}" title="${esc(t.desc || '')}"><span class="nz-tile">${icon(t.icon || 'pin')}</span><span class="tx"><b>${esc(t.label)}</b><span>${esc(kindLabel(t.kind))}</span></span><span class="n ${counts[t.name] ? 'has' : ''}">${counts[t.name] || 0}</span></button>`).join('')}</div></div></div>` : '';
    const filt = !typesFilter && filterTypes.length > 1 ? `<div class="mx-tf">${[['all', T('all', 'All'), list.length]].concat(filterTypes.map(k => [k, typeDef(k).label, counts[k]])).map(([k, l, n]) => `<button class="chipx ${S.posFilter === k ? 'on' : ''}" data-pf-type="${esc(k)}">${esc(l)}<em>${k === 'all' ? Object.values(counts).reduce((a, b) => a + b, 0) : n}</em></button>`).join('')}</div>` : '';

    let lastDept = null;
    const rows = list.map(p => {
      const t = typeDef(p.type);
      const dd = dist(p.coords);
      const editing = S.editing === p.id;
      const ed = editing ? pointEditor(p, t) : null;
      let grp = '';
      if (all && p.hospital !== lastDept) {
        lastDept = p.hospital;
        const dep = server(p.hospital);
        grp = `<div class="mx-group"><span class="bdot" style="background:${esc(blipHex(dep && dep.blip && dep.blip.colour))}"></span>${esc(dep ? dep.label : p.hospital)}</div>`;
      }
      return `${grp}<div class="mx-pr ${editing ? 'edit' : ''}" data-id="${p.id}">
        <div class="mx-prh"><span class="nz-tile ${t.manager === false ? 'mute' : ''}">${icon(t.icon || 'pin')}</span>
          <div class="tx"><b>${esc(p.label || t.label)} <em>#${p.id}</em></b><span>${fmtC(p.coords.x)}, ${fmtC(p.coords.y)}, ${fmtC(p.coords.z)} · ${num(p.coords.w).toFixed(1)}°</span></div>
          <div class="tags">${pointSummary(p, t)}</div>
          <div class="dist ${dd !== null && dd < 25 ? 'near' : ''}">${esc(fmtDist(dd))}</div>
          <div class="mx-act"><button class="mx-ib" data-a="go" title="${esc(T('go_to', 'Go to'))}">${icon('pin')}</button><button class="mx-ib" data-a="move" title="${esc(T('replace', 'Re-place in-world'))}">${icon('target')}</button><button class="mx-ib ${editing ? 'teal' : ''}" data-a="edit" title="${esc(T('edit', 'Edit'))}">${icon('edit')}</button><button class="mx-ib red" data-a="del" title="${esc(T('delete', 'Delete'))}">${icon('trash')}</button></div>
        </div>${ed ? ed.html : ''}</div>`;
    }).join('');

    body.innerHTML = `${addHtml}
      <div class="mx-card"><div class="mx-ch"><div class="nz-tile mute">${icon('pin')}</div><div class="sp"><h3>${esc(T('configured', 'Configured positions'))}</h3><p>${esc(T('configured_sub', '%s placed · distances from where you stand', list.length))}</p></div></div>
        <div class="mx-cb">${filt}${list.length ? `<div class="mx-pl">${rows}</div>` : `<div class="mx-none">${icon('pin')}<b>${esc(T('no_positions', 'No positions yet'))}</b><span>${esc(all ? T('no_positions_all', 'Open a department and add its positions.') : T('no_positions_text', 'Click a type above to drop one in-world.'))}</span></div>`}</div></div>`;

    body.querySelectorAll('[data-t]').forEach(bt => { bt.onclick = () => place({ dept: d.id, type: bt.dataset.t }); });
    body.querySelectorAll('[data-pf-type]').forEach(bt => { bt.onclick = () => { S.posFilter = bt.dataset.pfType; renderMain(); }; });
    body.querySelectorAll('.mx-pr').forEach(row => {
      const id = Number(row.dataset.id);
      const p = pts.find(x => x.id === id);
      const t = typeDef(p.type);
      const a = s => row.querySelector(`[data-a=${s}]`);
      a('go').onclick = () => NZA.post(`${APP}:goto`, { coords: p.coords });
      a('move').onclick = () => place({ dept: p.hospital, type: p.type, point: p.id });
      a('edit').onclick = () => { S.editing = S.editing === id ? null : id; renderMain(); };
      a('del').onclick = () => confirmBox({
        title: T('delete_point', 'Delete %s #%s?', p.label || t.label, p.id), text: T('delete_point_text', 'It disappears for everyone right away.'),
        label: T('delete', 'Delete'), onYes: async () => { const res = await act('pointDelete', { id }); if (res) { S.editing = null; renderTree(); renderMain(); } },
      });
      if (S.editing === id) {
        const data = Object.assign({}, clone(t.data || {}), clone(p.data || {}));
        row.querySelectorAll('[data-bool]').forEach(h => { const k = h.dataset.bool; NZA.ui.Toggle(h, { on: !!data[k], onChange: v => { data[k] = v; } }); });
        let label = p.label || '';
        row.querySelectorAll('[data-pf]').forEach(inp => inp.addEventListener('input', () => {
          const k = inp.dataset.pf;
          if (k === '__label') { label = inp.value; return; }
          data[k] = inp.type === 'number' ? num(inp.value) : inp.value;
        }));
        a('cancel').onclick = () => { S.editing = null; renderMain(); };
        a('savep').onclick = async () => { const res = await act('pointData', { id, data, label }); if (res) { S.editing = null; renderMain(); } };
      }
    });
  }

  /* ── garage ── */
  function garageView(body, dr, d) {
    const veh = dr.vehicles = dr.vehicles || [];
    const pts = ((S.data && S.data.points) || []).filter(p => p.hospital === d.id && GARAGE_TYPES.includes(p.type));
    body.innerHTML = `
      <div class="mx-card"><div class="mx-ch"><div class="nz-tile">${icon('car')}</div><div class="sp"><h3>${esc(T('vehicles', 'Vehicles'))}</h3><p>${esc(T('vehicles_sub', 'Model = spawn name. Cars spawn at Vehicle Garage points, helicopters at Helipads.'))}</p></div></div>
        <div class="mx-cb" style="padding:8px 10px 12px">${veh.length ? `<table class="mx-table mx-vt"><thead><tr><th>${esc(T('model', 'Model'))}</th><th>${esc(T('label', 'Label'))}</th><th>${esc(T('type', 'Type'))}</th><th>${esc(T('min_grade', 'Min grade'))}</th><th>${esc(T('livery', 'Livery'))}</th><th>${esc(T('extras', 'Extras'))}</th><th></th></tr></thead><tbody>
          ${veh.map((v, i) => `<tr data-i="${i}">
            <td><input class="nz-input mono" data-v="model" maxlength="32" value="${esc(v.model)}" style="width:130px"></td>
            <td><input class="nz-input" data-v="label" maxlength="32" value="${esc(v.label)}"></td>
            <td><span data-h="type"></span></td>
            <td><select class="nz-input" data-v="minGrade" style="min-width:140px">${gradeOptions(dr, v.minGrade)}</select></td>
            <td><input class="nz-input mono w-n" type="number" min="-1" max="60" data-v="livery" value="${esc(v.livery === undefined ? -1 : v.livery)}" title="${esc(T('livery_help', '-1 = keep the default'))}"></td>
            <td><input class="nz-input mono" data-v="extras" style="width:110px" placeholder="1, 2, 5" value="${esc((v.extras || []).join(', '))}"></td>
            <td><div class="mx-act"><button class="mx-ib red" data-a="del">${icon('trash')}</button></div></td></tr>`).join('')}</tbody></table>` : `<div class="mx-none">${icon('car')}<b>${esc(T('no_vehicles', 'No vehicles yet'))}</b><span>${esc(T('no_vehicles_text', 'Add the vehicles this department may take out.'))}</span></div>`}
          <button class="mx-add" data-a="add" style="margin-top:10px">${icon('plus')}${esc(T('add_vehicle', 'Add a vehicle'))}</button></div></div>
      <div class="mx-card"><div class="mx-ch"><div class="nz-tile mute">${icon('garage')}</div><div class="sp"><h3>${esc(T('spawns', 'Spawn points'))}</h3><p>${esc(T('spawns_sub', 'Where vehicles appear. Medics also store them back here.'))}</p></div>
        ${isAdmin() ? `<div class="mx-btns"><button class="btn-line btn-sm" data-t="garage">${icon('car')}${esc(typeDef('garage').label)}</button><button class="btn-line btn-sm" data-t="heli">${icon('heli')}${esc(typeDef('heli').label)}</button></div>` : ''}</div>
        <div class="mx-cb">${pts.length ? `<div class="mx-pl">${pts.map(p => { const t = typeDef(p.type); const dd = dist(p.coords); return `<div class="mx-pr" data-id="${p.id}"><div class="mx-prh"><span class="nz-tile">${icon(t.icon)}</span><div class="tx"><b>${esc(p.label || t.label)} <em>#${p.id}</em></b><span>${fmtC(p.coords.x)}, ${fmtC(p.coords.y)}, ${fmtC(p.coords.z)} · ${num(p.coords.w).toFixed(1)}°</span></div><div class="dist">${esc(fmtDist(dd))}</div>${isAdmin() ? `<div class="mx-act"><button class="mx-ib" data-a="go">${icon('pin')}</button><button class="mx-ib" data-a="move">${icon('target')}</button><button class="mx-ib red" data-a="del">${icon('trash')}</button></div>` : ''}</div></div>`; }).join('')}</div>` : `<div class="mx-none">${icon('garage')}<b>${esc(T('no_spawns', 'No spawn points'))}</b><span>${esc(T('no_spawns_text', 'Place a Vehicle Garage and a Helipad where the vehicles should appear.'))}</span></div>`}</div></div>`;
    body.querySelectorAll('tr[data-i]').forEach(tr => {
      const v = veh[Number(tr.dataset.i)];
      NZA.ui.Segmented(tr.querySelector('[data-h=type]'), { options: [{ value: 'car', label: T('seg_car', 'Car') }, { value: 'heli', label: T('seg_heli', 'Heli') }], value: v.type || 'car', onChange: x => { v.type = x; refreshDirtyUi(); } });
      tr.querySelectorAll('[data-v]').forEach(inp => {
        const ev = inp.tagName === 'SELECT' ? 'change' : 'input';
        inp.addEventListener(ev, () => {
          const k = inp.dataset.v;
          if (k === 'minGrade' || k === 'livery') v[k] = Math.round(num(inp.value, k === 'livery' ? -1 : 0));
          else if (k === 'extras') v.extras = inp.value.split(/[^\d]+/).filter(Boolean).map(Number).filter(n => n >= 0 && n <= 20);
          else if (k === 'model') v.model = inp.value.replace(/[^\w-]/g, '').toLowerCase();
          else v[k] = inp.value;
          refreshDirtyUi();
        });
      });
      tr.querySelector('[data-a=del]').onclick = () => { veh.splice(veh.indexOf(v), 1); renderMain(); refreshDirtyUi(); };
    });
    body.querySelector('[data-a=add]').onclick = () => {
      if (veh.length >= num(S.data.limits && S.data.limits.vehicles, 40)) { toast(T('err_limit_hint', 'Limit reached.'), 'error'); return; }
      veh.push({ id: `v${Date.now().toString(36)}`, model: 'ambulance', label: T('new_vehicle', 'Ambulance'), type: 'car', minGrade: 0, livery: -1, extras: [] });
      renderMain(); refreshDirtyUi();
    };
    body.querySelectorAll('[data-t]').forEach(bt => { bt.onclick = () => place({ dept: d.id, type: bt.dataset.t }); });
    body.querySelectorAll('.mx-pr').forEach(row => {
      const p = pts.find(x => x.id === Number(row.dataset.id));
      const a = s => row.querySelector(`[data-a=${s}]`);
      if (!a('go')) return;
      a('go').onclick = () => NZA.post(`${APP}:goto`, { coords: p.coords });
      a('move').onclick = () => place({ dept: p.hospital, type: p.type, point: p.id });
      a('del').onclick = () => confirmBox({ title: T('delete_point', 'Delete %s #%s?', p.label || typeDef(p.type).label, p.id), text: T('delete_point_text', 'It disappears for everyone right away.'), label: T('delete', 'Delete'), onYes: async () => { if (await act('pointDelete', { id: p.id })) { renderTree(); renderMain(); } } });
    });
  }

  /* ── funds (boss) ── */
  function fundsView(body, d) {
    const bal = (S.data.society || {})[d.id] || 0;
    let account = 'cash';
    body.innerHTML = `
      <div class="mx-grid"><div class="mx-col">
        ${card('bank', T('balance', 'Balance'), T('balance_sub', 'Society account "%s"', d.society || d.job || d.id), `<div class="mx-bal"><b>${esc(money(bal))}</b><span>${esc(T('available', 'available'))}</span></div>`)}
        ${card('swap', T('transfer', 'Transfer'), T('transfer_sub', 'Move money between you and the department'), `
          <div class="mx-row2"><div class="mx-f"><label>${esc(T('amount', 'Amount'))}</label><div class="mx-pre"><span>$</span><input class="nz-input mono" type="number" min="1" data-r="amount" placeholder="0"></div></div>
            <div class="mx-f"><label>${esc(T('account', 'Your account'))}</label><span data-h="acc"></span></div></div>
          <div class="mx-quick">${[100, 500, 1000, 5000, 10000].map(v => `<button class="chipx sm" data-q="${v}">+${esc(money(v))}</button>`).join('')}</div>
          <div class="mx-btns"><button class="btn-teal" data-a="dep">${icon('download')}${esc(T('deposit', 'Deposit'))}</button><button class="btn-line" data-a="wd">${icon('upload')}${esc(T('withdraw', 'Withdraw'))}</button></div>`)}
      </div><div class="mx-col">
        ${card('users', T('payroll', 'Payroll'), T('payroll_sub', 'Salary per grade, paid while on duty'), `<table class="mx-table"><tbody>${(d.grades || []).map(g => `<tr><td><b>${esc(g.label)}</b></td><td class="mx-mono" style="text-align:right">${esc(money(g.salary))}</td><td style="text-align:right">${staffOf(d.id).filter(s => s.grade === g.level).length} ${esc(T('members_short', 'staff'))}</td></tr>`).join('')}</tbody></table>`, '', 'mute')}
      </div></div>`;
    const amt = body.querySelector('[data-r=amount]');
    NZA.ui.Segmented(body.querySelector('[data-h=acc]'), { options: [{ value: 'cash', label: T('cash', 'Cash') }, { value: 'bank', label: T('bank', 'Bank') }], value: account, onChange: v => { account = v; } });
    body.querySelectorAll('[data-q]').forEach(b => { b.onclick = () => { amt.value = num(amt.value) + Number(b.dataset.q); }; });
    const go = async action => {
      const amount = Math.round(num(amt.value));
      if (amount <= 0) { toast(T('err_bad_amount', 'Type an amount.'), 'error'); amt.focus(); return; }
      if (await act('funds', { dept: d.id, action, amount, account })) renderMain();
    };
    body.querySelector('[data-a=dep]').onclick = () => go('deposit');
    body.querySelector('[data-a=wd]').onclick = () => go('withdraw');
  }

  /* ── hospital section ── */
  function hospitalOverview(body) {
    const t = (S.data && S.data.totals) || {};
    body.innerHTML = `<div class="mx-stats">${stat('building', T('st_departments', 'Departments'), depts().length)}${stat('users', T('st_staff', 'Staff'), t.staff || 0)}${stat('pulse', T('st_duty', 'On duty'), t.onDuty || 0)}${stat('pin', T('st_positions', 'Positions'), ((S.data && S.data.points) || []).length, 'mute')}</div>
      <div class="mx-card"><div class="mx-cb" style="padding:8px 10px 10px">${depts().length ? `<table class="mx-table"><thead><tr><th>${esc(T('department', 'Department'))}</th><th>${esc(T('link', 'Link'))}</th><th>${esc(T('st_staff', 'Staff'))}</th><th>${esc(T('st_duty', 'On duty'))}</th><th>${esc(T('st_positions', 'Positions'))}</th><th>${esc(T('st_vehicles', 'Vehicles'))}</th><th>${esc(T('c_easy', 'Easy mode'))}</th></tr></thead><tbody>
        ${depts().map(d => { const st = staffOf(d.id); return `<tr class="click" data-d="${esc(d.id)}"><td><div class="mx-who"><span class="bdot" style="width:9px;height:9px;border-radius:50%;background:${esc(blipHex(d.blip && d.blip.colour))}"></span><div><b>${esc(d.label)}</b><span>${esc(d.id)}</span></div></div></td>
          <td>${d.job ? `<span class="nz-tag live">${esc(d.job)}</span>` : `<span class="nz-tag off">${esc(T('standalone', 'Standalone'))}</span>`}</td><td>${st.length}</td><td>${st.filter(s => s.onDuty).length}</td><td>${pointsOf(d.id).length}</td><td>${(d.vehicles || []).length}</td>
          <td>${d.easy ? `<span class="nz-tag warn">${esc(T('on', 'On'))}</span>` : `<span class="nz-tag off">${esc(T('off', 'Off'))}</span>`}</td></tr>`; }).join('')}</tbody></table>` : `<div class="mx-none">${icon('building')}<b>${esc(T('no_depts', 'No departments yet.'))}</b></div>`}</div></div>`;
    body.querySelectorAll('tr[data-d]').forEach(tr => { tr.onclick = () => select(tr.dataset.d, 'overview'); });
  }

  function dutyView(body) {
    const rows = [];
    depts().forEach(d => staffOf(d.id).filter(s => s.onDuty).forEach(s => rows.push({ d, s })));
    body.innerHTML = `<div class="mx-card"><div class="mx-cb" style="padding:8px 10px 10px">${rows.length ? `<table class="mx-table"><thead><tr><th>${esc(T('member', 'Member'))}</th><th>${esc(T('department', 'Department'))}</th><th>${esc(T('grade', 'Grade'))}</th><th>${esc(T('server_id', 'Server id'))}</th></tr></thead><tbody>
      ${rows.map(({ d, s }) => `<tr><td><div class="mx-who"><div class="nz-av">${esc(initials(s.name))}<i class="od on"></i></div><div><b>${esc(s.name)}</b><span>${esc(s.identifier)}</span></div></div></td><td>${esc(d.label)}</td><td>${esc((d.grades[s.grade] || {}).label || s.grade)}</td><td class="mx-mono">${esc(s.src || '—')}</td></tr>`).join('')}</tbody></table>` : `<div class="mx-none">${icon('pulse')}<b>${esc(T('nobody_duty', 'Nobody is on duty'))}</b></div>`}</div></div>`;
  }

  /* ═════════════════════════ compact menus ═════════════════════════ */
  function compactWin(title, sub, wide) {
    root.innerHTML = '<div class="nza-dim"></div>';
    const w = NZA.ui.Win(root, { title, sub, status: [{ key: 'ESC', label: T('close', 'Close') }], onClose: () => NZA.close(APP) });
    w.el.classList.add('mx-cw');
    if (wide) w.el.classList.add('wide');
    w.main.innerHTML = '<div class="mx-cbody nza-scroll" data-wheel></div>';
    return w.main.querySelector('.mx-cbody');
  }
  const itemImg = it => `<div class="img">${it.image ? `<img src="${esc(it.image)}" alt="" onerror="this.remove()">` : icon('box')}</div>`;

  function renderCompact() {
    const d = C.data;
    if (C.mode === 'locker') {
      const body = compactWin(T('locker', 'Locker'), `${d.dept || ''}${d.grade ? ` · ${d.grade}` : ''}`);
      body.innerHTML = `${!d.gender ? `<div class="mx-note amber">${esc(T('locker_freemode', 'Outfits only fit the multiplayer male and female characters.'))}</div>` : ''}
        ${(d.outfits || []).length ? d.outfits.map(o => `<div class="mx-li ${o.fits ? '' : 'off'}"><div class="nz-tile">${icon('shirt')}</div><div class="tx"><b>${esc(o.name)}</b><span>${esc(o.fits ? T('fits', 'Fits your character') : T('no_fit', 'No version for your character'))}${o.grades && o.grades.length ? ` · ${esc((o.grades || []).map(g => (d.grades || [])[g] || g).join(', '))}` : ''}</span></div><button class="btn-teal btn-sm" data-wear="${esc(o.id)}" ${o.fits ? '' : 'disabled'}>${esc(T('wear', 'Wear'))}</button></div>`).join('')
          : `<div class="mx-none">${icon('shirt')}<b>${esc(T('locker_empty', 'This locker is empty'))}</b><span>${esc(T('locker_empty_text', 'Your boss adds outfits in the EMS Manager.'))}</span></div>`}
        <div class="mx-cfoot"><span class="t-dim" style="font-size:11px">${esc(T('locker_hint', 'Your own clothes are kept until you change back.'))}</span><button class="btn-line" data-a="civ" ${d.civvies ? '' : 'disabled'}>${icon('rot-l')}${esc(T('civvies', 'Civilian clothes'))}</button></div>`;
      body.querySelectorAll('[data-wear]').forEach(b => { b.onclick = async () => { const r = await NZA.post(`${APP}:wear`, { id: b.dataset.wear }); if (r && r.ok === false && r.msg) toast(r.msg, 'error'); }; });
      body.querySelector('[data-a=civ]').onclick = () => NZA.post(`${APP}:civvies`, {});
    } else if (C.mode === 'storage') {
      const body = compactWin(T('storage', 'Supply cabinet'), d.dept || '');
      C.qty = C.qty || {};
      body.innerHTML = `<div class="mx-note">${esc(T('storage_note', 'Free supplies while you are on duty. Each item has a limit per shift.'))}</div>` + ((d.items || []).length ? (d.items || []).map(it => {
        const left = Math.max(0, (it.limit || 0) - (it.taken || 0));
        const q = Math.min(C.qty[it.key] || 1, Math.max(1, left));
        return `<div class="mx-li ${left ? '' : 'off'}">${itemImg(it)}<div class="tx"><b>${esc(it.label)}</b><span>${esc(T('left_shift', '%s left this shift', left))}</span></div>
          <div class="lim"><span>${it.taken || 0} / ${it.limit}</span>${NZA.ui.meterHTML({ value: (it.taken || 0) / Math.max(1, it.limit), tone: left ? '' : 'red' })}</div>
          <div class="mx-step"><button data-dec="${esc(it.key)}">${icon('minus')}</button><span>${q}</span><button data-inc="${esc(it.key)}">${icon('plus')}</button></div>
          <button class="btn-teal btn-sm" data-take="${esc(it.key)}" ${left ? '' : 'disabled'}>${esc(T('take', 'Take'))}</button></div>`;
      }).join('') : `<div class="mx-none">${icon('medkit')}<b>${esc(T('storage_empty', 'Nothing for your grade'))}</b></div>`);
      const item = k => d.items.find(x => x.key === k);
      body.querySelectorAll('[data-dec]').forEach(b => { b.onclick = () => { C.qty[b.dataset.dec] = Math.max(1, (C.qty[b.dataset.dec] || 1) - 1); renderCompact(); }; });
      body.querySelectorAll('[data-inc]').forEach(b => { b.onclick = () => { const it = item(b.dataset.inc); C.qty[b.dataset.inc] = Math.min(Math.max(1, it.limit - it.taken), (C.qty[b.dataset.inc] || 1) + 1); renderCompact(); }; });
      body.querySelectorAll('[data-take]').forEach(b => {
        b.onclick = async () => {
          const r = await NZA.post(`${APP}:take`, { key: b.dataset.take, count: C.qty[b.dataset.take] || 1 });
          if (!r || r.ok === false) { toast((r && r.msg) || T('err_failed', 'Something went wrong. Try again.'), 'error'); return; }
          if (r.items) d.items = r.items;
          C.qty[b.dataset.take] = 1;
          if (r.msg) toast(r.msg, 'success');
          renderCompact();
        };
      });
    } else if (C.mode === 'garage') {
      const heli = d.kind === 'heli';
      const body = compactWin(heli ? T('helipad', 'Helipad') : T('garage', 'Vehicle garage'), `${d.dept || ''}${d.max ? ` · ${T('out_of', '%s / %s out', d.out || 0, d.max)}` : ''}`);
      body.innerHTML = (d.vehicles || []).length ? d.vehicles.map(v => `<div class="mx-li ${v.locked ? 'off' : ''}"><div class="nz-tile ${v.locked ? 'mute' : ''}">${icon(v.type === 'heli' ? 'heli' : 'car')}</div><div class="tx"><b>${esc(v.label)}</b><span><em class="mx-mono">${esc(v.model)}</em>${v.locked ? ` · ${esc(T('needs_grade', 'Needs %s', v.gradeLabel || v.minGrade))}` : ''}</span></div><button class="btn-teal btn-sm" data-spawn="${esc(v.id)}" ${v.locked || (d.max && d.out >= d.max) ? 'disabled' : ''}>${icon('key')}${esc(T('take_out', 'Take out'))}</button></div>`).join('')
        : `<div class="mx-none">${icon(heli ? 'heli' : 'car')}<b>${esc(T('garage_empty', 'No vehicles here'))}</b><span>${esc(T('garage_empty_text', 'The department has no vehicles of this kind yet.'))}</span></div>`;
      if (d.max && d.out >= d.max) body.insertAdjacentHTML('afterbegin', `<div class="mx-note amber">${esc(T('too_many_out', 'You already have %s vehicles out. Store one first.', d.out))}</div>`);
      body.querySelectorAll('[data-spawn]').forEach(b => { b.onclick = async () => { b.disabled = true; const r = await NZA.post(`${APP}:spawn`, { id: b.dataset.spawn }); if (!r || r.ok === false) { toast((r && r.msg) || T('err_failed', 'Something went wrong. Try again.'), 'error'); b.disabled = false; } }; });
    } else if (C.mode === 'elevator') {
      const body = compactWin(T('elevator', 'Elevator'), `${d.dept || ''}`);
      body.innerHTML = `<div class="mx-floors">${(d.floors || []).map(f => `<button class="mx-floor ${f.current ? 'cur' : ''}" data-floor="${esc(f.id)}"><span class="lv">${esc(f.order)}</span><span class="tx"><b>${esc(f.label)}</b><span>${esc(f.current ? T('you_are_here', 'You are here') : T('go_floor', 'Take the elevator'))}</span></span><span class="go">${icon(f.current ? 'pin' : 'chev-r')}</span></button>`).join('')}</div>`;
      body.querySelectorAll('[data-floor]').forEach(b => { b.onclick = () => NZA.post(`${APP}:floor`, { id: Number(b.dataset.floor) }); });
    } else if (C.mode === 'stash') {
      const body = compactWin(d.title || T('stash', 'Stash'), T('stash_sub', 'Shared department storage'), true);
      C.amount = C.amount || '1';
      const col = (title, list, dir) => `<div class="mx-ccol"><h4>${esc(title)}<span>${list.length}</span></h4><div class="lst nza-scroll" data-wheel>${list.length ? list.map((it, i) => `<div class="mx-li">${itemImg(it)}<div class="tx"><b>${esc(it.label)}</b><span>${esc(it.meta ? T('has_meta', 'Labelled unit') : it.name)}</span></div><span class="cnt">×${esc(it.count)}</span><button class="mx-ib teal" data-mv="${dir}" data-i="${i}" title="${esc(dir === 'out' ? T('take', 'Take') : T('put', 'Store'))}">${icon(dir === 'out' ? 'arrow-r' : 'arrow-l')}</button></div>`).join('') : `<div class="mx-none" style="padding:20px">${icon('box')}<b>${esc(T('empty', 'Empty'))}</b></div>`}</div></div>`;
      body.innerHTML = `<div class="mx-opt"><div class="t"><b>${esc(T('move_amount', 'Amount per click'))}</b></div><span data-h="amt"></span></div>
        <div class="mx-cgrid">${col(T('stash', 'Stash'), d.items || [], 'out')}${col(T('pockets', 'Your pockets'), d.inv || [], 'in')}</div>`;
      NZA.ui.Segmented(body.querySelector('[data-h=amt]'), { options: ['1', '5', '10', 'all'].map(v => ({ value: v, label: v === 'all' ? T('all', 'All') : v })), value: C.amount, onChange: v => { C.amount = v; } });
      body.querySelectorAll('[data-mv]').forEach(b => {
        b.onclick = async () => {
          const dir = b.dataset.mv, i = Number(b.dataset.i);
          const it = dir === 'out' ? d.items[i] : d.inv[i];
          const count = C.amount === 'all' ? it.count : Math.min(it.count, Number(C.amount));
          const r = await NZA.post(`${APP}:stashMove`, dir === 'out' ? { dir, index: it.index, name: it.name, count } : { dir, slot: it.slot, name: it.name, count });
          if (!r || r.ok === false) { toast((r && r.msg) || T('err_failed', 'Something went wrong. Try again.'), 'error'); return; }
          d.items = r.items || d.items; d.inv = r.inv || d.inv;
          renderCompact();
        };
      });
    }
  }

  /* ═════════════════════════ app ═════════════════════════ */
  function openManager(data) {
    C = null;
    const resume = !!data.resume && !!S.data && S.mode === data.mode;
    if (!resume) {
      S.sel = { dept: null, view: 'overview' }; S.drafts = {}; S.base = {}; S.expanded = new Set(); S.search = ''; S.filter = 'all'; S.posFilter = 'all';
    }
    S.mode = data.mode || 'admin';
    S.types = data.types || S.types || [];
    S.me = data.me || S.me;
    S.editing = null;
    if (data.data) applyData(data.data);
    const pl = data.placed;
    if (pl) {
      if (pl.ok && pl.hq && S.sel.dept && S.drafts[S.sel.dept]) {
        S.drafts[S.sel.dept].hq = pl.hq;
        const b = JSON.parse(S.base[S.sel.dept]); b.hq = pl.hq; S.base[S.sel.dept] = JSON.stringify(b);
      }
      if (pl.msg) toast(pl.msg, pl.ok ? 'success' : 'error');
    }
    closeModal();
    buildShell();
    renderTree();
    renderMain();
  }

  NZA.app(APP, {
    init(el) { root = el; },
    open(data) {
      if (data.locale) LOC = Object.assign({}, LOC, data.locale);
      if (data.compact) {
        C = { mode: data.mode, data, qty: {}, amount: '1' };
        win = null;
        renderCompact();
        return;
      }
      openManager(data);
    },
    close() { closeModal(); if (root) root.innerHTML = ''; win = null; C = null; },
    keys: {
      Escape() {
        if (modal) { closeModal(); return true; }
        if (C) { NZA.close(APP); return true; }
        tryClose();
        return true;
      },
      s(e) { if ((e.ctrlKey || e.metaKey) && !C) { save(); return true; } return false; },
    },
    // preview helper: NZA.apps.manager.go('roster', 'lsmd')
    go(v, id) { select(id || S.sel.dept, v); },
    preview() { preview(); },
  });

  /* ═════════════════════════ preview (browser only) ═════════════════════════ */
  function preview() {
    const P = {
      lo: ['assess', 'basic', 'cpr', 'transport', 'checkin'],
      emt: ['assess', 'basic', 'cpr', 'transport', 'checkin', 'defib', 'iv', 'splint', 'binder', 'suture', 'burn', 'meds', 'airway', 'bodybag', 'blood'],
    };
    P.para = P.emt.concat(['ultrasound', 'chestdrain', 'pericardio', 'xray', 'pharmacy']);
    P.doc = P.para.concat(['surgery', 'angio', 'graft']);
    P.chief = P.doc.concat(['manage']);
    const permList = [['assess', 'Assess patients'], ['basic', 'Basic first aid'], ['cpr', 'CPR'], ['defib', 'Defibrillator'], ['iv', 'IV / IO access'], ['blood', 'Blood products'], ['binder', 'Pelvic binder'], ['splint', 'Splints & collars'], ['suture', 'Wound closure'], ['burn', 'Burn care'], ['graft', 'Skin grafts'], ['airway', 'Airway'], ['ultrasound', 'Ultrasound'], ['chestdrain', 'Chest drain'], ['pericardio', 'Pericardiocentesis'], ['xray', 'Radiology'], ['surgery', 'Surgery'], ['angio', 'Angiography'], ['meds', 'Medication'], ['transport', 'Transport'], ['bodybag', 'Body bags & morgue'], ['checkin', 'Front desk'], ['pharmacy', 'Pharmacy staff'], ['manage', 'Department manager']].map(([key, label]) => ({ key, label }));
    const grades = () => [
      { level: 0, name: 'trainee', label: 'Trainee', salary: 50, perms: P.lo.slice() },
      { level: 1, name: 'emt', label: 'EMT', salary: 75, perms: P.emt.slice() },
      { level: 2, name: 'paramedic', label: 'Paramedic', salary: 100, perms: P.para.slice() },
      { level: 3, name: 'doctor', label: 'Doctor', salary: 150, perms: P.doc.slice() },
      { level: 4, name: 'chief', label: 'Chief of Medicine', salary: 200, perms: P.chief.slice() },
    ];
    const outfit = (top, legs) => ({ components: [[1, 0, 0], [3, 85, 0], [4, legs, 0], [5, 0, 0], [6, 25, 0], [7, 126, 0], [8, 15, 0], [9, 0, 0], [10, 58, 0], [11, top, 1]], props: [[0, -1, 0], [1, 5, 0], [2, -1, 0], [6, 3, 0], [7, -1, 0]] });
    const depts = [
      { id: 'lsmd', label: 'Los Santos Medical', description: 'Pillbox Hill hospital and the city ambulance service.', job: 'ambulance', discord: '1123456789012345678', society: null, easy: false, easyPerms: {},
        hq: { x: 298.62, y: -584.47, z: 43.26, w: 71.5 }, blip: { enabled: true, sprite: 61, colour: 1, scale: 0.9, label: 'Pillbox Medical', shortRange: true },
        grades: grades(), outfits: [{ id: 'o1', name: 'EMS Duty uniform', grades: [], male: outfit(250, 96), female: outfit(258, 99) }, { id: 'o2', name: 'Surgeon scrubs', grades: [3, 4], male: outfit(146, 9), female: null }],
        vehicles: [{ id: 'v1', model: 'ambulance', label: 'Ambulance', type: 'car', minGrade: 0, livery: 0, extras: [1, 2] }, { id: 'v2', model: 'lguard', label: 'Rapid response', type: 'car', minGrade: 2, livery: -1, extras: [] }, { id: 'v3', model: 'polmav', label: 'Air Ambulance', type: 'heli', minGrade: 3, livery: 1, extras: [] }] },
      { id: 'sandy', label: 'Sandy Shores Medical', description: '', job: null, discord: null, society: 'sandymed', easy: true, easyPerms: { surgery: false },
        hq: { x: 1839.6, y: 3672.9, z: 34.28, w: 210 }, blip: { enabled: true, sprite: 61, colour: 3, scale: 0.8, label: 'Sandy Medical', shortRange: true },
        grades: grades().slice(0, 4), outfits: [], vehicles: [{ id: 'v4', model: 'ambulance', label: 'Ambulance', type: 'car', minGrade: 0, livery: 1, extras: [] }] },
      { id: 'lsfd', label: 'LSFD Rescue', description: 'Fire department paramedics.', job: 'fire', discord: null, society: null, easy: false, easyPerms: {}, hq: null,
        blip: { enabled: true, sprite: 61, colour: 17, scale: 0.85, shortRange: true }, grades: grades().slice(0, 3), outfits: [], vehicles: [] },
    ];
    const names = [['Maya Reyes', 4, 1, 1], ['John Doe', 3, 1, 1], ['Theo Kane', 2, 1, 0], ['Sam Brooks', 0, 1, 1], ['Lena Park', 2, 0, 0], ['Ravi Shah', 1, 0, 0], ['Ella Novak', 1, 1, 1], ['Owen Price', 0, 0, 0]];
    const staff = {
      lsmd: names.map(([n, g, on, duty], i) => ({ identifier: `char1:${(0x5f3a2c + i * 7919).toString(16)}e9a${i}`, name: n, grade: g, online: !!on, src: on ? 3 + i * 4 : null, onDuty: !!duty, created: `2026-0${(i % 8) + 1}-1${i} 18:22:01`, linked: i === 6 })),
      sandy: [{ identifier: 'char1:77aa21', name: 'Hank Miller', grade: 2, online: true, src: 41, onDuty: true, created: '2026-09-02 12:00:00' }],
      lsfd: [],
    };
    let pid = 100;
    const pt = (hospital, type, x, y, z, w, data = {}, label) => ({ id: pid++, hospital, type, coords: { x, y, z, w }, data, label });
    const points = [
      pt('lsmd', 'duty', 311.2, -594.1, 43.28, 340), pt('lsmd', 'locker', 299.8, -598.3, 43.28, 70), pt('lsmd', 'locker', 301.4, -599.0, 43.28, 70, {}, 'Women\'s locker'),
      pt('lsmd', 'stash', 306.9, -601.4, 43.28, 160, { slots: 80, weight: 250000, personal: false, minGrade: 0 }), pt('lsmd', 'boss', 335.1, -594.6, 43.28, 70),
      pt('lsmd', 'storage', 309.8, -567.1, 43.28, 250), pt('lsmd', 'garage', 294.6, -607.4, 43.31, 70), pt('lsmd', 'garage', 290.1, -614.2, 43.36, 70),
      pt('lsmd', 'heli', 351.9, -588.2, 74.16, 250), pt('lsmd', 'bed', 324.3, -583.0, 43.71, 340), pt('lsmd', 'bed', 319.4, -581.1, 43.71, 340), pt('lsmd', 'bed', 314.5, -584.2, 43.71, 340),
      pt('lsmd', 'respawn', 307.6, -595.4, 43.28, 340), pt('lsmd', 'xray', 339.6, -578.9, 43.28, 160), pt('lsmd', 'lightbox', 341.8, -577.0, 43.28, 160),
      pt('lsmd', 'surgery', 314.9, -568.2, 43.28, 70), pt('lsmd', 'checkin', 307.0, -595.0, 43.28, 70), pt('lsmd', 'tv', 309.5, -590.5, 45.1, 160), pt('lsmd', 'pharmacy', 318.4, -571.7, 43.28, 160),
      pt('lsmd', 'elevator', 332.4, -595.7, 43.28, 70, { group: 'main', floor: 'Ground floor · ER', order: 0, staffOnly: false }), pt('lsmd', 'elevator', 338.9, -583.8, 74.16, 250, { group: 'main', floor: 'Roof · Helipad', order: 3, staffOnly: true }),
      pt('lsmd', 'elevator', 330.1, -601.2, 28.79, 340, { group: 'main', floor: 'Garage level', order: -1, staffOnly: false }),
      pt('lsmd', 'donation', 343.2, -586.3, 43.28, 340), pt('lsmd', 'angio', 347.9, -580.6, 43.28, 70),
      pt('sandy', 'duty', 1834.2, 3676.4, 34.27, 210), pt('sandy', 'garage', 1830.1, 3690.2, 33.97, 300), pt('sandy', 'bed', 1828.6, 3673.0, 34.62, 120),
    ];
    const t = (name, label, ic, kind, data, desc, manager) => ({ name, label, icon: ic, kind, data: data || {}, desc, manager: manager !== false });
    const types = [
      t('duty', 'Duty', 'clock', 'marker', {}, 'Go on and off duty here.'), t('locker', 'Locker', 'shirt', 'marker', {}, 'Change into the department outfits.'),
      t('stash', 'Stash', 'box', 'marker', { slots: 80, weight: 250000, personal: false, minGrade: 0 }, 'Shared department storage.'),
      t('boss', 'Boss Menu', 'crown', 'marker', {}, 'Roster, grades, outfits, garage and funds.'), t('storage', 'Supply Cabinet', 'medkit', 'marker', {}, 'Free supplies per shift.'),
      t('garage', 'Vehicle Garage', 'car', 'car', {}, 'Vehicles spawn here.'), t('heli', 'Helipad', 'heli', 'heli', {}, 'Helicopters spawn here.'),
      t('elevator', 'Elevator', 'building', 'marker', { group: 'main', floor: 'Ground floor', order: 0, staffOnly: false }, 'Positions with the same group are linked floors.'),
      t('bed', 'Hospital Bed', 'bed', 'marker', {}, 'Lie down to heal four times faster.'), t('respawn', 'Respawn Point', 'heart', 'marker', {}, 'Where the dead wake up.'),
      t('hq', 'Department HQ', 'flag', 'marker', {}, '', false),
      t('checkin', 'Check-in Desk', 'ticket', 'marker'), t('tv', 'Waiting Room TV', 'monitor', 'prop'), t('pharmacy', 'Pharmacy', 'pill', 'marker'),
      t('bloodbank', 'Blood Bank', 'bloodbag', 'marker'), t('donation', 'Blood Donation Station', 'drop', 'prop'), t('xray', 'X-ray Table', 'xray', 'prop'),
      t('lightbox', 'Lightbox', 'lightbox', 'prop'), t('surgery', 'Operating Table', 'scalpel', 'prop'), t('ultrasound', 'Ultrasound Cart', 'probe', 'prop'),
      t('angio', 'Angiography Suite', 'monitor', 'prop'), t('morgue', 'Morgue', 'skull', 'marker'),
    ];
    const data = {
      mode: 'admin', admin: true, me: { dept: 'lsmd', grade: 4, src: 7, identifier: 'char1:5f3a2ce9a0', name: 'Maya Reyes' },
      depts, staff, points, perms: permList,
      online: [{ src: 3, name: 'Maya Reyes', identifier: staff.lsmd[0].identifier }, { src: 12, name: 'Carlos Vega', identifier: 'char1:00c1' }, { src: 17, name: 'Nina Ortiz', identifier: 'char1:00c2' }, { src: 22, name: 'Felix Grant', identifier: 'char1:00c3' }],
      society: { lsmd: 148250 }, totals: { departments: 3, staff: 9, onDuty: 5, points: points.length },
      limits: { departments: 20, grades: 20, outfits: 40, vehicles: 40, points: 400, staff: 500 },
      blips: { colours: [{ id: 1, hex: '#e03232' }, { id: 6, hex: '#b82020' }, { id: 17, hex: '#f0a050' }, { id: 5, hex: '#eec64e' }, { id: 2, hex: '#71cb71' }, { id: 25, hex: '#3c8c3c' }, { id: 3, hex: '#5db6e5' }, { id: 38, hex: '#2f5ed4' }, { id: 7, hex: '#9a72cc' }, { id: 8, hex: '#f17fbd' }, { id: 0, hex: '#f0f0f0' }, { id: 40, hex: '#4c4c4c' }],
        sprites: [{ id: 61, label: 'Hospital' }, { id: 153, label: 'Medical' }, { id: 43, label: 'Helipad' }, { id: 50, label: 'Garage' }] },
      bossOutranks: true,
    };
    NZA.mock(`${APP}:capture`, { ok: true, gender: 'male', data: outfit(250, 96) });
    NZA.mock(`${APP}:create`, p => { const nd = clone(depts[2]); nd.id = p.id; nd.label = p.label; nd.job = null; nd.hq = null; data.depts.push(nd); data.staff[p.id] = []; return { ok: true, dept: p.id, data: clone(data), msg: `${p.label} created` }; });
    NZA.mock(`${APP}:save`, p => { const i = data.depts.findIndex(x => x.id === p.dept.id); const c = clone(p.dept); (c.grades || []).forEach((g, k) => { g.level = k; delete g.from; }); data.depts[i] = c; return { ok: true, data: clone(data), msg: `${c.label} saved` }; });
    const params = new URLSearchParams(location.search);
    const mode = params.get('mode');
    const locale = {};
    if (mode === 'locker') {
      NZA.open(APP, { compact: true, mode, dept: 'Los Santos Medical', grade: 'Paramedic', gender: 'male', civvies: true, grades: ['Trainee', 'EMT', 'Paramedic', 'Doctor', 'Chief'], locale,
        outfits: [{ id: 'o1', name: 'EMS Duty uniform', grades: [], male: true, female: true, fits: true }, { id: 'o3', name: 'Winter jacket', grades: [1, 2, 3], male: true, female: true, fits: true }, { id: 'o2', name: 'Surgeon scrubs', grades: [3, 4], male: false, female: true, fits: false }] });
    } else if (mode === 'storage') {
      const it = (key, label, limit, taken) => ({ key, name: key, label, limit, taken, image: `img/items/${key}.png` });
      NZA.open(APP, { compact: true, mode, dept: 'Los Santos Medical', locale, items: [it('bandage', 'Bandage', 20, 6), it('gauze', 'Gauze', 20, 0), it('tourniquet', 'Tourniquet', 4, 4), it('suture_kit', 'Suture Kit', 6, 1), it('iv_kit', 'IV Kit', 6, 2), it('saline_bag', 'Saline 500 ml', 6, 0), it('morphine', 'Morphine', 4, 3)] });
    } else if (mode === 'garage') {
      NZA.open(APP, { compact: true, mode, dept: 'Los Santos Medical', kind: 'car', out: 1, max: 2, locale,
        vehicles: [{ id: 'v1', model: 'ambulance', label: 'Ambulance', type: 'car', minGrade: 0 }, { id: 'v2', model: 'lguard', label: 'Rapid response', type: 'car', minGrade: 2 }, { id: 'v5', model: 'emsbus', label: 'Mass casualty bus', type: 'car', minGrade: 3, locked: true, gradeLabel: 'Doctor' }] });
    } else if (mode === 'elevator') {
      NZA.open(APP, { compact: true, mode, dept: 'Los Santos Medical', locale, floors: [{ id: 2, label: 'Roof · Helipad', order: 3 }, { id: 1, label: 'Ground floor · ER', order: 0, current: true }, { id: 3, label: 'Garage level', order: -1 }] });
    } else if (mode === 'stash') {
      const it = (name, label, count, extra = {}) => Object.assign({ name, label, count, image: `img/items/${name}.png` }, extra);
      NZA.open(APP, { compact: true, mode, dept: 'Los Santos Medical', title: 'Los Santos Medical · Stash', locale,
        items: [it('bandage', 'Bandage', 48, { index: 1 }), it('saline_bag', 'Saline 500 ml', 12, { index: 2 }), it('blood_bag', 'Blood Bag', 1, { index: 3, meta: { type: 'O-' } }), it('splint', 'Splint', 6, { index: 4 }), it('defibrillator', 'Defibrillator', 1, { index: 5 })],
        inv: [it('gauze', 'Gauze', 4, { slot: 1 }), it('morphine', 'Morphine', 2, { slot: 2 }), it('tourniquet', 'Tourniquet', 1, { slot: 3 })] });
    } else {
      if (mode === 'boss') { data.mode = 'boss'; data.admin = false; data.depts = [depts[0]]; data.points = points.filter(p => GARAGE_TYPES.includes(p.type) && p.hospital === 'lsmd'); data.me.grade = 3; }
      NZA.open(APP, { mode: data.mode, data, types, me: { x: 306.4, y: -590.2, z: 43.28, w: 70 }, locale });
      const v = params.get('view');
      if (v) select(params.get('dept') || S.sel.dept, v);
    }
  }
})();
