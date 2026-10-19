/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · Department Console (app 'manager')   module: hospital
   v5 window, NAYZEEE composition (no folder tree):
     · department RAIL (window sidebar): rolling count, search with inline link filters,
       one unit card per department (status ring = staff on shift, blip colour, code),
       whole-server rows at the bottom (admins) or your own card (command desk)
     · section DOCK: a vertical icon dock beside the content (Profile, Staff, Ranks,
       Uniforms, Sites, Fleet / Account); it switches to the server sections when one is open
     · content: bracket header + section body (profile hero with instrument list, settings
       rows, base-point radar, staff list + hire panel, rank ladder on a spine, uniform
       cards, zone board + site list + set-a-site palette, fleet, account with a rolling balance)

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
  const codeOf = n => String(n || '?').split(/[\s_-]+/).filter(Boolean).slice(0, 3).map(s => s[0]).join('').toUpperCase() || '?';
  const human = k => String(k).replace(/_/g, ' ').replace(/([a-z])([A-Z])/g, '$1 $2').replace(/^./, c => c.toUpperCase());
  const pad2 = n => String(Math.max(0, Math.round(n))).padStart(2, '0');

  const PERM_ICON = {
    assess: 'stetho', basic: 'bandage', cpr: 'heart', defib: 'defib', iv: 'iv', blood: 'bloodbag', binder: 'bone',
    splint: 'splint', suture: 'needle', burn: 'flame', graft: 'scalpel', airway: 'lungs', ultrasound: 'probe',
    chestdrain: 'tube', pericardio: 'syringe', xray: 'xray', surgery: 'scalpel', angio: 'monitor', meds: 'pill',
    transport: 'ambulance', bodybag: 'skull', checkin: 'ticket', pharmacy: 'store', manage: 'crown',
  };
  // zone board: every site type lands in one zone (unknown types → "Other")
  const ZONES = [
    { id: 'station', label: 'Staff base', icon: 'badge', types: ['duty', 'locker', 'stash', 'boss', 'storage'] },
    { id: 'pharmacy', label: 'Dispensary', icon: 'pill', types: ['pharmacy'] },
    { id: 'checkin', label: 'Front desk', icon: 'ticket', types: ['checkin', 'tv'] },
    { id: 'blood', label: 'Blood service', icon: 'bloodbag', types: ['bloodbank', 'donation'] },
    { id: 'surgery', label: 'Theatre', icon: 'scalpel', types: ['surgery'] },
    { id: 'angio', label: 'Cath lab', icon: 'monitor', types: ['angio'] },
    { id: 'xray', label: 'Imaging', icon: 'xray', types: ['xray', 'lightbox'] },
    { id: 'ultrasound', label: 'Sonography', icon: 'probe', types: ['ultrasound'] },
    { id: 'beds', label: 'Wards', icon: 'bed', types: ['bed', 'respawn'] },
    { id: 'elevators', label: 'Lifts', icon: 'building', types: ['elevator'] },
    { id: 'morgue', label: 'Mortuary', icon: 'skull', types: ['morgue'] },
  ];
  const GARAGE_TYPES = ['garage', 'heli'];
  const COMP = { 1: 'Mask', 3: 'Arms', 4: 'Legs', 5: 'Bag', 6: 'Shoes', 7: 'Neck', 8: 'Shirt', 9: 'Vest', 10: 'Decals', 11: 'Top' };
  const PROP = { 0: 'Hat', 1: 'Glasses', 2: 'Ears', 6: 'Watch', 7: 'Bracelet' };
  const SPRITE_ICON = { 61: 'cross', 153: 'medkit', 43: 'heli', 50: 'garage' };

  const S = {
    mode: 'admin', data: null, types: [], me: null,
    sel: { dept: null, view: 'overview' }, drafts: {}, base: {},
    search: '', filter: 'all', posFilter: 'all', zone: 'all',
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

  // status ring (HUD design): track + fill, optional colour
  const RC = 2 * Math.PI * 17;
  const ring = (frac, col, cls = '') => `<svg class="mx-rg ${cls}" viewBox="0 0 40 40"><circle class="tr" cx="20" cy="20" r="17"/><circle class="fl" cx="20" cy="20" r="17" style="${col ? `stroke:${col};` : ''}stroke-dasharray:${(Math.max(0, Math.min(1, num(frac))) * RC).toFixed(1)} ${RC.toFixed(1)}"/></svg>`;
  // instrument list row: label left, mono value right, tone notch
  const irow = (label, value, tone = '', extra = '') => `<div class="mx-ir ${tone}"><span>${esc(label)}</span><b>${value}</b>${extra}</div>`;

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

  function toast(message, type = 'success', title) { NZA.toast({ title: title || T('mgr_title', 'Department Console'), message, type }); }

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
    }
  }

  /* ═════════════════════════ modals ═════════════════════════ */
  function closeModal() { if (modal) { modal.close(); modal = null; } }
  function confirmBox({ title, text, label, tone = 'red', ic = 'trash', onYes }) {
    closeModal();
    modal = NZA.ui.Modal({
      title, text, icon: ic, tone, host: root,
      actions: [
        { label: T('cancel', 'Keep it'), kind: 'line', onClick: () => { modal = null; } },
        { label, kind: tone === 'red' ? 'red' : 'teal', onClick: () => { modal = null; onYes && onYes(); } },
      ],
    });
  }

  // register a department: live unit-card preview on the left, two field rows on the right
  function newDeptModal() {
    closeModal();
    const wrap = NZA.el('div', 'nza-modal-wrap');
    wrap.innerHTML = `<div class="nza-modal mx-reg nza-pop">
      <div class="mx-reg-pv">
        <span class="k">${esc(T('reg_preview', 'Card preview'))}</span>
        <div class="mx-badge xl" style="--bc:#e03232">${ring(0.0001, '#e03232')}<b data-p="code">?</b></div>
        <b class="nm" data-p="name">${esc(T('reg_name_ph', 'Los Santos Medical'))}</b>
        <span class="cd mono" data-p="id">lsmd</span>
        <div class="mx-il sm">${irow(T('st_staff', 'Staff'), '00')}${irow(T('st_positions', 'Sites'), '00')}${irow(T('st_ranks', 'Ranks'), '05')}</div>
      </div>
      <div class="mx-reg-f">
        <div class="mx-reg-h"><span class="kick">${esc(T('new_dept_sub', 'New department'))}</span><h4>${esc(T('new_dept', 'Register a department'))}</h4><p>${esc(T('new_dept_note', 'It starts with a default rank ladder. Add staff, uniforms and sites once it exists.'))}</p></div>
        <div class="mx-opt col"><div class="t"><b>${esc(T('display_name', 'Name'))}</b><small>${esc(T('display_name_help', 'Shown in menus, on staff cards and on the map.'))}</small></div><input class="nz-input" data-n="label" maxlength="48" placeholder="${esc(T('reg_name_ph', 'Los Santos Medical'))}"></div>
        <div class="mx-opt col"><div class="t"><b>${esc(T('internal_name', 'Code'))}</b><small>${esc(T('internal_name_help', 'a–z, 0–9 and _ only. Fixed once registered.'))}</small></div><input class="nz-input mono" data-n="id" maxlength="32" placeholder="lsmd"></div>
        <div class="mx-err"></div>
        <div class="mf"><button class="btn-line" data-a="cancel">${esc(T('back', 'Back'))}</button><button class="btn-teal" data-a="ok">${icon('check')}${esc(T('create_dept', 'Register'))}</button></div>
      </div>
    </div>`;
    root.appendChild(wrap);
    const lab = wrap.querySelector('[data-n=label]'), idI = wrap.querySelector('[data-n=id]'), err = wrap.querySelector('.mx-err');
    const pv = k => wrap.querySelector(`[data-p=${k}]`);
    let touched = false;
    const slug = s => s.toLowerCase().normalize('NFKD').replace(/[^\w\s]/g, '').trim().replace(/\s+/g, '_').replace(/[^a-z0-9_]/g, '').slice(0, 32);
    const sync = () => {
      pv('name').textContent = lab.value.trim() || T('reg_name_ph', 'Los Santos Medical');
      pv('code').textContent = codeOf(lab.value.trim() || T('reg_name_ph', 'Los Santos Medical'));
      pv('id').textContent = idI.value || 'lsmd';
    };
    lab.addEventListener('input', () => { if (!touched) idI.value = slug(lab.value); err.textContent = ''; sync(); });
    idI.addEventListener('input', () => { touched = true; idI.value = idI.value.toLowerCase().replace(/[^a-z0-9_]/g, ''); err.textContent = ''; sync(); });
    const submit = async () => {
      const label = lab.value.trim(), id = idI.value.trim();
      if (!label) { err.textContent = T('err_need_label', 'Give the department a name.'); lab.focus(); return; }
      if (!/^[a-z0-9_]{2,32}$/.test(id)) { err.textContent = T('err_bad_id_hint', 'Code: 2–32 characters, a–z, 0–9 or _.'); idI.focus(); return; }
      if (server(id)) { err.textContent = T('err_exists_hint', 'That code is already taken.'); idI.focus(); return; }
      const res = await act('create', { id, label });
      if (!res) return;
      closeModal();
      select(res.dept || id, 'overview');
    };
    wrap.querySelector('[data-a=cancel]').onclick = closeModal;
    wrap.querySelector('[data-a=ok]').onclick = submit;
    [lab, idI].forEach(i => i.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); submit(); } }));
    modal = { close: () => wrap.remove(), el: wrap };
    sync();
    setTimeout(() => lab.focus(), 30);
  }

  /* ═════════════════════════ shell ═════════════════════════ */
  function buildShell() {
    root.innerHTML = '<div class="nza-dim"></div>';
    win = NZA.ui.Win(root, {
      title: T('mgr_title', 'Department Console'),
      sub: isAdmin() ? T('sub_admin', 'Server admin') : T('sub_boss', 'Command desk'),
      nav: [],
      status: [{ key: 'ESC', label: T('close', 'Close') }, { key: 'Ctrl S', label: T('save', 'Save') }],
      onClose: tryClose,
    });
    win.el.classList.add('mx-win');
    win.side.innerHTML = `
      <div class="mx-rh"><div><span class="k">${esc(T('rail_kicker', 'On file'))}</span><b>${esc(T('departments', 'Departments'))}</b></div><div class="mx-rcount" data-h="rcount"></div></div>
      <label class="mx-search">${icon('search')}<input type="text" placeholder="${esc(T('search', 'Find a department'))}">
        <button class="mx-ft" data-ft="linked" title="${esc(T('f_linked', 'Only job-linked departments'))}">${icon('link')}</button>
        <button class="mx-ft" data-ft="standalone" title="${esc(T('f_standalone', 'Only departments with their own roster'))}">${icon('id')}</button></label>
      <div class="mx-units nza-scroll" data-wheel></div>
      <div class="mx-foot"></div>`;
    const inp = win.side.querySelector('.mx-search input');
    inp.value = S.search;
    inp.addEventListener('input', () => { S.search = inp.value; renderRail(); });
    win.side.querySelectorAll('[data-ft]').forEach(b => {
      b.onclick = e => { e.preventDefault(); S.filter = S.filter === b.dataset.ft ? 'all' : b.dataset.ft; renderRail(); };
    });
    if (!isAdmin()) win.side.querySelector('.mx-search').style.display = 'none';
    win.side.querySelector('.mx-units').addEventListener('click', onRailClick);
    win.side.querySelector('.mx-foot').addEventListener('click', onRailClick);
    win.main.innerHTML = '<div class="mx-stage"><nav class="mx-dock"></nav><div class="mx-main"></div></div>';
    win.main.querySelector('.mx-dock').addEventListener('click', e => { const b = e.target.closest('.mx-slot'); if (b) select(b.dataset.d || S.sel.dept, b.dataset.v); });
    renderTop();
  }

  function renderTop() {
    if (!win) return;
    const t = (S.data && S.data.totals) || {};
    const staff = t.staff || 0, duty = t.onDuty || 0;
    const v = S.sel.view, tag = isAdmin() ? 'button' : 'span';
    const rd = (view, label, value, extra = '', cls = '') => `<${tag} class="mx-mr ${cls} ${isAdmin() && v === view ? 'on' : ''}" ${isAdmin() ? `data-v="${view}" title="${esc(T('mid_open', 'Open the server view'))}"` : ''}>${extra}<em>${esc(label)}</em><b>${value}</b></${tag}>`;
    win.setMid(`<div class="mx-mid">
      ${rd('h:overview', T('mid_depts', 'Departments'), pad2(depts().length))}
      ${rd('h:positions', T('mid_sites', 'Sites'), pad2(((S.data && S.data.points) || []).length))}
      ${rd('h:duty', T('mid_duty', 'On shift'), `${pad2(duty)}<small>/${pad2(staff)}</small>`, ring(staff ? duty / staff : 0, '', 'xs'), 'live')}
      <span class="nz-ver">${esc(isAdmin() ? T('admin', 'Admin') : T('boss', 'Command'))}</span></div>`);
    win.el.querySelectorAll('.mx-mid [data-v]').forEach(b => { b.onclick = () => select(null, b.dataset.v); });
    win.act.innerHTML = `<button class="mx-ib" data-a="refresh" title="${esc(T('refresh_help', 'Reload staff, shifts and sites'))}">${icon('refresh')}</button>${isAdmin() ? `<button class="btn-teal btn-sm" data-a="new">${icon('plus')}${esc(T('new_dept_btn', 'Register department'))}</button>` : ''}`;
    const nb = win.act.querySelector('[data-a=new]');
    if (nb) nb.onclick = newDeptModal;
    win.act.querySelector('[data-a=refresh]').onclick = async e => {
      const b = e.currentTarget; b.classList.add('spin');
      if (await act('refresh', {}, { quiet: true })) { renderTop(); renderRail(); renderMain(); }
      b.classList.remove('spin');
    };
    const host = win.side.querySelector('[data-h=rcount]');
    if (host) { host.innerHTML = ''; NZA.ui.FlipClock(host, { value: pad2(depts().length), small: true, tone: 'teal' }); }
  }

  function tryClose() {
    if (anyDirty()) {
      confirmBox({
        title: T('discard_title', 'Leave without saving?'),
        text: T('discard_text', 'Some departments have changes that are not saved yet. Close and drop them?'),
        label: T('discard', 'Drop changes'), ic: 'alert',
        onYes: () => { S.drafts = {}; S.base = {}; NZA.close(APP); },
      });
      return;
    }
    NZA.close(APP);
  }

  /* ═════════════════════════ rail ═════════════════════════ */
  function zonesFor(id) {
    const pts = id ? pointsOf(id) : [];
    const reg = new Set(S.types.filter(t => t.manager !== false).map(t => t.name));
    const out = ZONES.filter(z => z.types.some(t => reg.has(t) || pts.some(p => p.type === t)))
      .map(z => ({ ...z, label: T(`folder_${z.id}`, z.label), count: pts.filter(p => z.types.includes(p.type)).length }));
    const known = new Set(['hq', ...GARAGE_TYPES]);
    ZONES.forEach(z => z.types.forEach(t => known.add(t)));
    const other = [...new Set([...S.types.filter(t => t.manager !== false && !known.has(t.name)).map(t => t.name), ...pts.filter(p => !known.has(p.type)).map(p => p.type)])];
    if (other.length) out.push({ id: 'other', label: T('folder_other', 'Other'), icon: 'grid', types: other, count: pts.filter(p => other.includes(p.type)).length });
    return out;
  }

  function unitCard(d) {
    const dr = S.drafts[d.id] || d;
    const st = staffOf(d.id), duty = st.filter(s => s.onDuty).length;
    const col = blipHex(dr.blip && dr.blip.colour);
    const sel = S.sel.dept === d.id && !String(S.sel.view).startsWith('h:');
    return `<button class="mx-unit ${sel ? 'sel' : ''}" data-d="${esc(d.id)}">
      <span class="mx-badge" style="--bc:${esc(col)}">${ring(st.length ? duty / st.length : 0, col)}<b>${esc(codeOf(dr.label || d.id))}</b></span>
      <span class="tx"><b>${esc(dr.label || d.id)}</b><span>${d.job ? `${icon('link')}${esc(d.job)}` : `${icon('id')}${esc(T('standalone', 'Own roster'))}`}</span></span>
      <span class="dt"><span class="v"><b>${duty}</b><i>/${st.length}</i></span><em>${esc(T('on_shift_short', 'on shift'))}</em></span>
      ${dirty(d.id) ? `<span class="dirty" title="${esc(T('unsaved', 'Not saved yet'))}"></span>` : ''}</button>`;
  }

  function renderRail() {
    if (!win) return;
    const units = win.side.querySelector('.mx-units');
    const q = S.search.trim().toLowerCase();
    win.side.querySelectorAll('[data-ft]').forEach(b => b.classList.toggle('on', S.filter === b.dataset.ft));
    const list = depts().filter(d => {
      if (S.filter === 'linked' && !d.job) return false;
      if (S.filter === 'standalone' && d.job) return false;
      if (!q) return true;
      return [d.label, d.id, d.job, d.description].some(x => String(x || '').toLowerCase().includes(q));
    });
    units.innerHTML = list.length ? list.map(unitCard).join('')
      : `<div class="mx-empty-rail">${icon('search')}<span>${esc(depts().length ? T('no_match', 'Nothing matches that search.') : T('no_depts', 'No departments yet.'))}</span></div>`;
    if (isAdmin() && !q) units.insertAdjacentHTML('beforeend', `<button class="mx-unit add" data-a="new"><span class="mx-badge">${icon('plus')}</span><span class="tx"><b>${esc(T('new_dept_btn', 'Register department'))}</b><span>${esc(T('new_dept_hint', 'Hospital, clinic or rescue service'))}</span></span></button>`);
    win.el.querySelectorAll('.mx-mid [data-v]').forEach(b => b.classList.toggle('on', S.sel.view === b.dataset.v));
    const foot = win.side.querySelector('.mx-foot');
    if (isAdmin()) {
      const live = [];
      depts().forEach(d => staffOf(d.id).filter(x => x.onDuty).forEach(x => live.push({ x, col: blipHex(d.blip && d.blip.colour) })));
      foot.innerHTML = `<button class="mx-live ${S.sel.view === 'h:duty' ? 'on' : ''}" data-v="h:duty">
        <span class="hd"><i class="${live.length ? 'pulse' : ''}"></i>${esc(T('live_kicker', 'Live now'))}<b>${pad2(live.length)}</b></span>
        <span class="faces">${live.slice(0, 7).map((l, i) => `<span class="mx-av sm on" style="z-index:${10 - i}">${ring(1, l.col)}<b>${esc(initials(l.x.name))}</b></span>`).join('')}${live.length > 7 ? `<span class="more">+${live.length - 7}</span>` : ''}${live.length ? '' : `<span class="none">${esc(T('nobody_duty', 'Nobody is on shift'))}</span>`}</span>
        <span class="ft">${esc(T('live_sub', '%s on shift across %s departments', live.length, depts().length))}</span></button>`;
    } else if (S.data && S.data.me) {
      const me = S.data.me, d = server(me.dept), g = d && d.grades && d.grades[me.grade];
      const st = staffOf(me.dept).find(r => r.identifier === me.identifier);
      const on = st && st.onDuty;
      foot.innerHTML = `<div class="mx-mecard"><span class="mx-av ${on ? 'on' : ''}">${ring(on ? 1 : 0.0001)}<b>${esc(initials(me.name))}</b></span><div><b>${esc(me.name || '')}</b><span>${esc(g ? g.label : '')}</span></div><span class="nz-tag ${on ? 'live' : 'off'}">${esc(on ? T('on_duty', 'On shift') : T('off_duty', 'Off shift'))}</span></div>`;
    } else foot.innerHTML = '';
  }

  function onRailClick(e) {
    if (e.target.closest('[data-a=new]')) { newDeptModal(); return; }
    const u = e.target.closest('.mx-unit');
    if (u) { const id = u.dataset.d; select(id, S.sel.dept === id && !String(S.sel.view).startsWith('h:') ? S.sel.view : (isAdmin() ? 'overview' : 'roster')); return; }
    const lv = e.target.closest('.mx-live');
    if (lv) select(null, lv.dataset.v);
  }

  /* ═════════════════════════ dock ═════════════════════════ */
  function dockItems() {
    if (String(S.sel.view).startsWith('h:')) {
      return [
        { v: 'h:overview', label: T('dock_server', 'Overview'), ic: 'grid' },
        { v: 'h:positions', label: T('dock_sites', 'Sites'), ic: 'map', ct: ((S.data && S.data.points) || []).length },
        { v: 'h:duty', label: T('dock_shift', 'On shift'), ic: 'pulse', ct: (S.data && S.data.totals && S.data.totals.onDuty) || 0 },
      ];
    }
    const id = S.sel.dept, d = server(id);
    if (!d) return [];
    const dr = S.drafts[id] || d;
    const items = [];
    if (isAdmin()) items.push({ v: 'overview', label: T('v_overview', 'Profile'), ic: 'id' });
    items.push({ v: 'roster', label: T('v_roster', 'Staff'), ic: 'users', ct: staffOf(id).length });
    items.push({ v: 'grades', label: T('v_grades', 'Ranks'), ic: 'star', ct: (dr.grades || []).length });
    items.push({ v: 'outfits', label: T('v_outfits', 'Uniforms'), ic: 'hanger', ct: (dr.outfits || []).length });
    if (isAdmin()) items.push({ v: 'positions', label: T('v_positions', 'Sites'), ic: 'pin', ct: pointsOf(id).length });
    items.push({ v: 'garage', label: T('v_garage', 'Fleet'), ic: 'ambulance', ct: (dr.vehicles || []).length });
    if (!isAdmin()) items.push({ v: 'funds', label: T('v_funds', 'Account'), ic: 'bank' });
    return items;
  }

  function renderDock() {
    if (!win) return;
    const dock = win.main.querySelector('.mx-dock');
    const items = dockItems();
    dock.innerHTML = items.map((it, i) => `<button class="mx-slot ${S.sel.view === it.v ? 'on' : ''}" data-v="${esc(it.v)}" style="animation-delay:${i * 30}ms">
      <span class="ic">${icon(it.ic)}${it.ct !== undefined ? `<i class="ct ${it.ct ? '' : 'z'}">${esc(it.ct)}</i>` : ''}</span><span class="lb">${esc(it.label)}</span></button>`).join('');
    dock.style.display = items.length ? '' : 'none';
  }

  function select(id, v) {
    if (id) S.sel.dept = id;
    v = v || S.sel.view;
    if (String(v).startsWith('f:')) { S.zone = v.slice(2); v = 'positions'; }
    if (v !== S.sel.view) S.posFilter = 'all';
    S.sel.view = v;
    S.editing = null;
    renderRail();
    renderMain();
  }

  /* ═════════════════════════ main area ═════════════════════════ */
  const VIEW_LABEL = () => ({
    overview: [T('v_overview', 'Profile'), T('v_overview_sub', 'Name, links, simple care, base point and map pin.')],
    roster: [T('v_roster', 'Staff'), T('v_roster_sub', 'Hire, move people between ranks and let them go. Refresh to see who just came online.')],
    grades: [T('v_grades', 'Ranks'), T('v_grades_sub', 'The ladder, top to bottom. Every rank has its own pay and its own permissions.')],
    outfits: [T('v_outfits', 'Uniforms'), T('v_outfits_sub', 'What the lockers hand out. Dress your character, then save it to the male or female side.')],
    positions: [T('v_positions', 'Sites'), T('v_positions_sub', 'Everything this department has in the world. Pick a zone, then set new sites from the list on the right.')],
    garage: [T('v_garage', 'Fleet'), T('v_garage_sub', 'Vehicles by rank and the bays they come out of.')],
    funds: [T('v_funds', 'Account'), T('v_funds_sub', 'The department money: balance, transfers and pay.')],
    'h:overview': [T('h_overview', 'Server overview'), T('h_overview_sub', 'Every department on this server. Click a card to open it.')],
    'h:positions': [T('h_positions', 'All sites'), T('h_positions_sub', 'Every site of every department, nearest first inside each one.')],
    'h:duty': [T('h_duty', 'On shift now'), T('h_duty_sub', 'Who is working right now, by department.')],
  });

  function head({ title, sub, crumb, actions = '' }) {
    return `<div class="mx-head"><div class="hl">${crumb ? `<div class="mx-crumb">${crumb}</div>` : ''}<h1>${title}</h1>${sub ? `<p>${esc(sub)}</p>` : ''}</div><div class="mx-hact">${actions}</div></div>`;
  }

  function deptActions(id, withDelete) {
    const dt = dirty(id);
    return `${dt ? `<span class="mx-unsaved"><i></i>${esc(T('unsaved', 'Not saved yet'))}</span>` : ''}
      ${dt ? `<button class="mx-ib" data-a="revert" title="${esc(T('revert', 'Undo my changes'))}">${icon('rot-l')}</button>` : ''}
      ${withDelete && isAdmin() ? `<button class="mx-ib red" data-a="delete" title="${esc(T('delete_dept', 'Remove department'))}">${icon('trash')}</button>` : ''}
      <button class="btn-teal" data-a="save" ${dt ? '' : 'disabled'}>${icon('save')}${esc(T('save', 'Save'))}</button>`;
  }

  function refreshDirtyUi() {
    if (!win) return;
    const id = S.sel.dept;
    const hact = win.main.querySelector('.mx-hact');
    if (hact && id && hact.querySelector('[data-a=save]')) {
      hact.innerHTML = deptActions(id, S.sel.view === 'overview');
      bindHeadActions();
    }
    renderRail();
  }

  function bindHeadActions() {
    const m = win.main;
    const q = s => m.querySelector(`.mx-hact ${s}`);
    if (q('[data-a=save]')) q('[data-a=save]').onclick = save;
    if (q('[data-a=revert]')) q('[data-a=revert]').onclick = () => { const id = S.sel.dept; delete S.drafts[id]; delete S.base[id]; renderMain(); renderRail(); };
    if (q('[data-a=delete]')) q('[data-a=delete]').onclick = askDelete;
  }

  async function save() {
    const id = S.sel.dept;
    if (!id || !dirty(id)) return;
    const d = S.drafts[id];
    const res = await act('save', { dept: d });
    if (!res) return;
    delete S.drafts[id]; delete S.base[id];
    renderTop(); renderRail(); renderMain();
  }

  function askDelete() {
    const id = S.sel.dept, d = server(id);
    if (!d) return;
    confirmBox({
      title: T('delete_title', 'Remove %s?', d.label),
      text: T('delete_text', 'Its %s sites and %s staff records go with it. There is no undo.', pointsOf(id).length, staffOf(id).length),
      label: T('delete_dept', 'Remove department'),
      onYes: async () => {
        const res = await act('delete', { id });
        if (!res) return;
        delete S.drafts[id]; delete S.base[id];
        S.sel.dept = depts()[0] ? depts()[0].id : null;
        S.sel.view = 'overview';
        renderTop(); renderRail(); renderMain();
      },
    });
  }

  function renderMain() {
    if (!win) return;
    renderDock();
    const host = win.main.querySelector('.mx-main');
    const v = S.sel.view;
    const labels = VIEW_LABEL();
    host.classList.remove('swap'); void host.offsetWidth; host.classList.add('swap');
    if (v.startsWith('h:')) {
      const [tt, sub] = labels[v];
      host.innerHTML = head({ title: esc(tt), sub, crumb: `<b>${esc(T('hospital', 'Whole server'))}</b>` }) + '<div class="mx-body nza-scroll" data-wheel></div>';
      const body = host.querySelector('.mx-body');
      if (v === 'h:overview') hospitalOverview(body);
      else if (v === 'h:positions') positionsView(body, null, true);
      else dutyView(body);
      return;
    }
    const id = S.sel.dept;
    const d = server(id);
    if (!d) {
      host.innerHTML = `<div class="mx-welcome"><div><div class="mx-badge xl" style="--bc:var(--teal)">${ring(0.0001)}<b>${icon('hospital')}</b></div><h2>${esc(T('welcome_title', 'Nothing open yet'))}</h2>
        <p>${esc(isAdmin() ? T('welcome_text', 'Register a department to begin. Then build its rank ladder, dress its lockers and set its duty point, store, fleet bays, beds and treatment rooms in the world.') : T('welcome_boss', 'Your department could not be loaded.'))}</p>
        ${isAdmin() ? `<button class="btn-teal btn-lg" data-a="new">${icon('plus')}${esc(T('new_dept_btn', 'Register department'))}</button>` : ''}</div></div>`;
      const nb = host.querySelector('[data-a=new]');
      if (nb) nb.onclick = newDeptModal;
      return;
    }
    const dr = draft(id);
    const [tt, sub] = labels[v] || labels.overview;
    const editable = ['overview', 'grades', 'outfits', 'garage'].includes(v);
    host.innerHTML = head({
      title: esc(tt), sub,
      crumb: `<i class="dot" style="background:${esc(blipHex(dr.blip && dr.blip.colour))}"></i><b>${esc(dr.label || d.id)}</b><span class="mono">${esc(d.id)}</span>`,
      actions: editable ? deptActions(id, v === 'overview') : '',
    }) + '<div class="mx-body nza-scroll" data-wheel></div>';
    bindHeadActions();
    const body = host.querySelector('.mx-body');
    if (v === 'overview') overviewView(body, dr, d);
    else if (v === 'roster') rosterView(body, d);
    else if (v === 'grades') gradesView(body, dr);
    else if (v === 'outfits') outfitsView(body, dr);
    else if (v === 'positions') positionsView(body, d, false);
    else if (v === 'garage') garageView(body, dr, d);
    else if (v === 'funds') fundsView(body, d);
  }

  const card = (ic, title, sub, body, extra = '', cls = '') => `<div class="mx-card ${cls}"><div class="mx-ch"><span class="mx-ci">${icon(ic)}</span><div class="sp"><h3>${esc(title)}</h3>${sub ? `<p>${esc(sub)}</p>` : ''}</div>${extra}</div><div class="mx-cb">${body}</div></div>`;
  const opt = (label, help, control, cls = '') => `<div class="mx-opt ${cls}"><div class="t"><b>${esc(label)}</b>${help ? `<small>${esc(help)}</small>` : ''}</div><div class="c">${control}</div></div>`;

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

  /* ── profile ── */
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
      <div class="mx-hero">
        <div class="mx-badge xl" data-h="hbadge"></div>
        <div class="mx-hid">
          <div class="chips"><span class="mx-code">${icon('lock')}${esc(dr.id)}</span>${d.job ? `<span class="nz-tag live">${icon('link')}${esc(T('linked_to', 'Job · %s', d.job))}</span>` : `<span class="nz-tag off">${esc(T('standalone', 'Own roster'))}</span>`}${dr.easy ? `<span class="nz-tag warn">${esc(T('c_easy', 'Simple care'))}</span>` : ''}</div>
          <h2 data-h="hname">${esc(dr.label || d.id)}</h2>
          <p>${esc(d.job ? T('linked_sub', 'Anyone with the "%s" job belongs here automatically.', d.job) : T('standalone_sub', 'No job link. People join when you hire them here.'))}</p>
        </div>
        <div class="mx-il">
          ${irow(T('st_staff', 'Staff'), pad2(st.length))}
          ${irow(T('st_duty', 'On shift'), `${pad2(onDuty)}<small>/${pad2(st.length)}</small>`, onDuty ? 'teal' : '')}
          ${irow(T('st_positions', 'Sites'), pad2(pts.length))}
          ${irow(T('st_vehicles', 'Fleet'), pad2((dr.vehicles || []).length))}
        </div>
      </div>
      <div class="mx-grid">
        <div class="mx-col">
          <div class="mx-panel">
            <section class="mx-sec"><h4>${esc(T('c_identity', 'Name & code'))}</h4>
              ${opt(T('display_name', 'Name'), T('display_name_help', 'Shown in menus, on staff cards and on the map.'), `<input class="nz-input" data-k="label" data-live="blip" maxlength="48" value="${esc(dr.label || '')}">`)}
              ${opt(T('internal_name', 'Code'), T('internal_name_fixed', 'Fixed. Scripts and logs use it.'), `<input class="nz-input mono" value="${esc(dr.id)}" disabled>`)}
              ${opt(T('description', 'About'), T('description_ph', 'Optional. Staff read it at the command desk.'), `<textarea class="nz-input" data-k="description" maxlength="400" placeholder="${esc(T('description_hint', 'Who you are and where you work.'))}">${esc(dr.description || '')}</textarea>`, 'col')}
            </section>
            <section class="mx-sec"><h4>${esc(T('c_integrations', 'Links'))}</h4>
              ${opt(T('framework_job', 'Job link'), T('framework_job_help', 'Everyone with this framework job is a member. Empty: you hire people here.'), `<input class="nz-input mono" data-k="job" maxlength="40" placeholder="ambulance" value="${esc(dr.job || '')}">`)}
              ${opt(T('discord_role', 'Discord role ID'), T('discord_help', 'For your Discord bot or logs.'), `<input class="nz-input mono" data-k="discord" maxlength="24" placeholder="123456789012345678" value="${esc(dr.discord || '')}">`)}
              ${opt(T('society', 'Paying account'), T('society_help', 'Bills, pay and the command desk use it. Empty: the job name.'), `<input class="nz-input mono" data-k="society" maxlength="40" placeholder="${esc(dr.job || dr.id)}" value="${esc(dr.society || '')}">`)}
            </section>
            <section class="mx-sec"><h4>${esc(T('c_easy', 'Simple care'))}</h4>
              ${opt(T('easy_label', 'Timed actions instead of minigames'), T('easy_text', "Medics of this department on shift treat with a short timed action. They still need the injury's supplies, but no X-ray, operating table, blood or special room."), '<span data-h="easy"></span>')}
              <button class="mx-more ${S.showEasyPerms ? 'open' : ''}" data-a="easyperms">${icon('chev-r')}${esc(T('easy_per_perm', 'Choose per permission'))} <span class="t-dim" data-h="easycount"></span></button>
              <div data-h="easychips" style="display:${S.showEasyPerms ? '' : 'none'}"></div>
            </section>
          </div>
        </div>
        <div class="mx-col">
          ${card('flag', T('c_hq', 'Base point'), T('c_hq_sub', 'The heart of the department. Its map pin sits here.'), `
            <div class="mx-radar" data-h="preview"></div>
            ${hq ? `<div class="mx-il">${irow('X', fmtC(hq.x))}${irow('Y', fmtC(hq.y))}${irow('Z', fmtC(hq.z))}${irow(T('facing', 'Facing'), `${num(hq.w).toFixed(1)}°`)}${hqDist !== null ? irow(T('from_you', 'From you'), esc(fmtDist(hqDist)), hqDist < 50 ? 'teal' : '') : ''}</div>
            <div class="mx-btns"><button class="btn-line" data-a="hqgo">${icon('teleport')}${esc(T('go_to', 'Travel there'))}</button><button class="btn-line" data-a="hqplace">${icon('crosshair')}${esc(T('replace', 'Move it'))}</button></div>`
            : `<div class="mx-none">${icon('flag')}<b>${esc(T('no_hq', 'No base point yet'))}</b><span>${esc(T('no_hq_text', 'Stand by the main entrance and set it. The map pin appears there.'))}</span><button class="btn-teal" data-a="hqplace">${icon('crosshair')}${esc(T('place_hq', 'Set base point'))}</button></div>`}`, '', 'base')}
          ${card('map', T('c_blip', 'Map pin'), T('c_blip_sub', 'How the department looks on the map and the minimap.'), `
            ${opt(T('blip_show', 'Show on the map'), T('blip_show_help', 'Needs a base point.'), '<span data-h="blipon"></span>')}
            <div class="mx-f"><label>${esc(T('colour', 'Pin colour'))}</label><div class="mx-swatches">${colours.map(c => `<span class="mx-sw ${Number(b.colour) === Number(c.id) ? 'on' : ''}" data-col="${esc(c.id)}" style="background:${esc(c.hex)};color:${esc(c.hex)}" title="${esc(c.id)}"></span>`).join('')}</div></div>
            <div class="mx-f"><label>${esc(T('sprite', 'Pin icon'))}</label><div class="mx-sprites">${sprites.map(s => `<button class="chipx sm ${Number(b.sprite) === Number(s.id) ? 'on' : ''}" data-spr="${esc(s.id)}">${icon(SPRITE_ICON[Number(s.id)] || 'pin')}${esc(s.label)}</button>`).join('')}<input class="nz-input mono" type="number" min="1" max="900" data-k="blip.sprite" data-live="blip" value="${esc(b.sprite)}" title="${esc(T('sprite_id', 'Any GTA blip id'))}"></div></div>
            <div class="mx-row2">
              <div class="mx-f"><label>${esc(T('scale', 'Size'))}</label><span data-h="scale"></span></div>
              <div class="mx-f"><label>${esc(T('blip_label', 'Pin text'))}</label><input class="nz-input" data-k="blip.label" data-live="blip" maxlength="48" placeholder="${esc(dr.label)}" value="${esc(b.label && b.label !== dr.label ? b.label : '')}"></div>
            </div>
            ${opt(T('short_range', 'Only when close'), T('short_range_help', 'Minimap shows it near the base only. The pause map always shows it.'), '<span data-h="short"></span>')}`)}
        </div>
      </div>`;
    bindInputs(body, dr);
    // simple care
    const easyChipsHost = body.querySelector('[data-h=easychips]');
    const effective = () => perms.filter(p => (dr.easyPerms[p.key] !== undefined ? dr.easyPerms[p.key] : dr.easy)).map(p => p.key);
    const countEl = body.querySelector('[data-h=easycount]');
    const setCount = () => { countEl.textContent = `· ${effective().length}/${perms.length}`; };
    const buildChips = () => {
      easyChipsHost.innerHTML = '';
      const chips = NZA.ui.Chips(easyChipsHost, {
        options: perms.map(p => ({ value: p.key, label: p.label, icon: PERM_ICON[p.key] || 'check' })), values: effective(),
        onChange: vals => { const set = new Set(vals); dr.easyPerms = {}; perms.forEach(p => { const on = set.has(p.key); if (on !== dr.easy) dr.easyPerms[p.key] = on; }); setCount(); refreshDirtyUi(); },
      });
      chips.el.classList.add('mx-chips');
    };
    buildChips(); setCount();
    NZA.ui.Toggle(body.querySelector('[data-h=easy]'), { on: !!dr.easy, onChange: v => { dr.easy = v; dr.easyPerms = {}; buildChips(); setCount(); refreshDirtyUi(); } });
    body.querySelector('[data-a=easyperms]').onclick = e => { S.showEasyPerms = !S.showEasyPerms; e.currentTarget.classList.toggle('open', S.showEasyPerms); easyChipsHost.style.display = S.showEasyPerms ? '' : 'none'; };
    // base point
    const hg = body.querySelector('[data-a=hqgo]');
    if (hg) hg.onclick = () => NZA.post(`${APP}:goto`, { coords: dr.hq });
    body.querySelectorAll('[data-a=hqplace]').forEach(bt => { bt.onclick = () => place({ dept: dr.id, hq: true }); });
    // map pin: radar preview + hero badge follow every change
    const prev = body.querySelector('[data-h=preview]');
    const hb = body.querySelector('[data-h=hbadge]');
    liveFns.blip = () => {
      const col = blipHex(b.colour);
      const hn = body.querySelector('[data-h=hname]');
      if (hn) hn.textContent = dr.label || dr.id;
      hb.style.setProperty('--bc', col);
      hb.innerHTML = `${ring(st.length ? onDuty / st.length : 0.0001, col)}<b>${esc(codeOf(dr.label || dr.id))}</b><i class="sp" style="background:${esc(col)}">${icon(SPRITE_ICON[Number(b.sprite)] || 'pin')}</i>`;
      const size = Math.round(22 * num(b.scale, 0.85));
      const far = hqDist !== null ? Math.min(1, hqDist / 600) : 0.5;
      prev.innerHTML = `<span class="sweep"></span><span class="rings"></span>
        <span class="me" style="left:${(50 + far * 32).toFixed(1)}%;top:${(50 + far * 26).toFixed(1)}%"></span>
        <div class="mx-pin" style="opacity:${b.enabled === false || !hq ? 0.28 : 1}"><span class="bp" style="width:${size}px;height:${size}px;background:${esc(col)}">${icon(SPRITE_ICON[Number(b.sprite)] || 'pin')}</span><span class="tl">${esc((b.label && b.label.trim()) || dr.label || dr.id)}</span></div>
        ${hqDist !== null ? `<span class="rd">${esc(fmtDist(hqDist))}</span>` : ''}`;
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

  /* ── staff ── */
  function gradeOptions(d, sel, { lockAbove = false } = {}) {
    return (d.grades || []).map(g => `<option value="${g.level}" ${Number(sel) === g.level ? 'selected' : ''} ${lockAbove && bossLocked(g.level) ? 'disabled' : ''}>${esc(`${g.level} · ${g.label}`)}</option>`).join('');
  }

  function rosterView(body, d) {
    const rows = staffOf(d.id).slice().sort((a, b) => (b.onDuty - a.onDuty) || (b.online - a.online) || (b.grade - a.grade));
    const online = rows.filter(r => r.online).length, duty = rows.filter(r => r.onDuty).length;
    const members = new Set(rows.map(r => r.identifier));
    const pickable = ((S.data && S.data.online) || []).filter(p => !p.identifier || !members.has(p.identifier));
    const firstFree = (d.grades || []).find(g => !bossLocked(g.level));
    body.innerHTML = `<div class="mx-split">
      <div class="mx-card list">
        <div class="mx-ch"><span class="mx-ci">${icon('users')}</span><div class="sp"><h3>${esc(T('staff', 'People'))}</h3><p>${esc(d.job ? T('staff_linked', 'Hired here, plus anyone online with the "%s" job.', d.job) : T('staff_sub', 'Everyone hired into this department.'))}</p></div></div>
        <div class="mx-cb flush">${rows.length ? rows.map((r, i) => {
          const locked = bossLocked(r.grade) || (S.mode === 'boss' && S.data.me && r.identifier === S.data.me.identifier);
          const stt = r.onDuty ? ['live', T('on_duty', 'On shift')] : r.online ? ['off', T('off_duty', 'Off shift')] : ['away', T('offline', 'Away')];
          return `<div class="mx-person ${r.onDuty ? 'duty' : r.online ? '' : 'away'}" data-id="${esc(r.identifier)}" style="animation-delay:${Math.min(i, 12) * 22}ms">
            <span class="mx-av ${r.onDuty ? 'on' : ''}">${ring(r.onDuty ? 1 : r.online ? 0.5 : 0.0001)}<b>${esc(initials(r.name))}</b></span>
            <div class="tx"><b>${esc(r.name)}${r.src ? ` <em>#${esc(r.src)}</em>` : ''}${r.linked ? `<i class="lk" title="${esc(T('via_job_help', 'Member through the framework job'))}">${icon('link')}${esc(T('via_job', 'job'))}</i>` : ''}</b><span><i class="s ${stt[0]}">${esc(stt[1])}</i>${esc(r.identifier)}</span></div>
            <select class="nz-input" data-r="grade" ${locked ? 'disabled' : ''}>${gradeOptions(d, r.grade, { lockAbove: true })}</select>
            <span class="since">${esc(r.created ? String(r.created).slice(0, 10) : '—')}</span>
            <button class="mx-ib red" data-a="fire" title="${esc(T('fire', 'Let go'))}" ${locked ? 'disabled' : ''}>${icon('user-x')}</button>
          </div>`;
        }).join('') : `<div class="mx-none">${icon('users')}<b>${esc(T('no_staff', 'Nobody here yet'))}</b><span>${esc(T('no_staff_text', 'Hire someone from the panel on the right. Their rank permissions start the moment they clock in.'))}</span></div>`}</div>
      </div>
      <aside class="mx-aside">
        <div class="mx-card gauge">
          <div class="mx-gauge"><div class="mx-badge lg" style="--bc:var(--teal-hi)">${ring(rows.length ? duty / rows.length : 0.0001)}<b>${pad2(duty)}</b></div><div><span class="k">${esc(T('st_duty', 'On shift'))}</span><b>${duty} / ${rows.length}</b></div></div>
          <div class="mx-il">${irow(T('st_members', 'Members'), pad2(rows.length))}${irow(T('st_online', 'Online'), pad2(online), online ? 'teal' : '')}${irow(T('st_duty', 'On shift'), pad2(duty), duty ? 'teal' : '')}</div>
        </div>
        ${card('user-plus', T('hire', 'Hire'), T('hire_sub', 'Pick someone online or type a server id or citizen id.'), `
          <div class="mx-f"><label>${esc(T('online_player', 'Online now'))}</label><select class="nz-input" data-r="pick"><option value="">${esc(T('pick_player', 'Choose a player…'))}</option>${pickable.map(p => `<option value="${esc(p.src)}">${esc(`[${p.src}] ${p.name}`)}</option>`).join('')}</select></div>
          <div class="mx-f"><label>${esc(T('or_id', 'Or an id'))}</label><input class="nz-input mono" data-r="target" maxlength="80" placeholder="12  ·  ABC12345"></div>
          <div class="mx-f"><label>${esc(T('grade', 'Rank'))}</label><select class="nz-input" data-r="grade">${gradeOptions(d, firstFree ? firstFree.level : 0, { lockAbove: true })}</select></div>
          <button class="btn-teal" data-a="hire">${icon('user-plus')}${esc(T('hire_btn', 'Hire'))}</button>`)}
      </aside></div>`;
    const pick = body.querySelector('[data-r=pick]'), tgt = body.querySelector('[data-r=target]');
    pick.onchange = () => { if (pick.value) tgt.value = pick.value; };
    body.querySelector('[data-a=hire]').onclick = async () => {
      const target = (tgt.value || pick.value || '').trim();
      if (!target) { toast(T('err_need_target', 'Pick a player or type an id.'), 'error'); tgt.focus(); return; }
      const res = await act('hire', { dept: d.id, target, grade: Number(body.querySelector('aside [data-r=grade]').value) });
      if (res) { renderTop(); renderRail(); renderMain(); }
    };
    body.querySelectorAll('.mx-person[data-id]').forEach(row => {
      const id = row.dataset.id;
      const r = rows.find(x => x.identifier === id);
      const sel = row.querySelector('select');
      sel.onchange = async () => {
        const res = await act('grade', { dept: d.id, identifier: id, grade: Number(sel.value) });
        if (!res) sel.value = r.grade;
        renderMain();
      };
      row.querySelector('[data-a=fire]').onclick = () => confirmBox({
        title: T('fire_title', 'Let %s go?', r.name), text: T('fire_text', 'Every permission of %s stops right away.', d.label),
        label: T('fire', 'Let go'), ic: 'user-x',
        onYes: async () => { const res = await act('fire', { dept: d.id, identifier: id }); if (res) { renderTop(); renderRail(); renderMain(); } },
      });
    });
  }

  /* ── ranks: a ladder on a spine, top rank first ── */
  function gradesView(body, dr) {
    const perms = S.data.perms || [];
    const grades = dr.grades;
    const lockText = l => (S.mode === 'boss' && l === myLevel() ? T('your_grade', 'Your rank') : T('above_you', 'Above you'));
    const order = grades.map((g, i) => i).reverse();
    body.innerHTML = `<div class="mx-note">${esc(T('grades_note', 'Rank 0 is the bottom rung. Moving or removing a rank never strands anyone: people on a removed rank drop one rung when you save.'))}</div>
      <div class="mx-ladder">${order.map(i => {
        const g = grades[i];
        const locked = bossLocked(i);
        return `<div class="mx-rung ${locked ? 'locked' : ''} ${i === grades.length - 1 ? 'top' : ''}" data-i="${i}">
          <div class="node"><b>${i}</b></div>
          <div class="mx-card">
            <div class="mx-rh2">
              <div class="mx-f grow"><label>${esc(T('grade_label', 'Rank title'))}</label><input class="nz-input" data-g="label" maxlength="32" value="${esc(g.label)}" ${locked ? 'disabled' : ''}></div>
              <div class="mx-f"><label>${esc(T('grade_name', 'Code'))}</label><input class="nz-input mono" data-g="name" maxlength="24" value="${esc(g.name)}" ${locked ? 'disabled' : ''}></div>
              <div class="mx-f pay"><label>${esc(T('salary', 'Pay'))}</label><div class="mx-pre"><span>$</span><input class="nz-input mono" type="number" min="0" data-g="salary" value="${esc(g.salary)}" ${locked ? 'disabled' : ''}></div></div>
              <div class="mx-act">
                ${locked ? `<span class="mx-lockt">${icon('lock')}${esc(lockText(i))}</span>` : ''}
                <button class="mx-ib" data-a="up" title="${esc(T('move_up', 'Move up'))}" ${locked || i === grades.length - 1 || bossLocked(i + 1) ? 'disabled' : ''}>${icon('arrow-up')}</button>
                <button class="mx-ib" data-a="down" title="${esc(T('move_down', 'Move down'))}" ${locked || i === 0 || bossLocked(i - 1) ? 'disabled' : ''}>${icon('arrow-down')}</button>
                <button class="mx-ib red" data-a="del" title="${esc(T('remove', 'Remove'))}" ${locked || grades.length <= 1 ? 'disabled' : ''}>${icon('trash')}</button>
              </div>
            </div>
            <div class="mx-gb"><div class="top"><span>${esc(T('permissions', 'Permissions'))} <b data-h="pc">${g.perms.length}</b><i>/ ${perms.length}</i></span><em>${locked ? '' : `<a class="mx-link" data-a="all">${esc(T('all', 'All'))}</a><a class="mx-link" data-a="none">${esc(T('none', 'None'))}</a>${i > 0 ? `<a class="mx-link" data-a="copy">${esc(T('copy_below', 'Same as rank %s', i - 1))}</a>` : ''}`}</em></div><div data-h="chips"></div></div>
          </div>
        </div>`;
      }).join('')}</div>
      <button class="mx-add" data-a="add">${icon('plus')}${esc(T('add_grade', 'Add a rank'))}</button>`;
    body.querySelectorAll('.mx-rung').forEach(cardEl => {
      const i = Number(cardEl.dataset.i), g = grades[i];
      const locked = bossLocked(i);
      const ch = NZA.ui.Chips(cardEl.querySelector('[data-h=chips]'), {
        options: perms.map(p => ({ value: p.key, label: p.label, icon: PERM_ICON[p.key] || 'check' })), values: g.perms,
        onChange: vals => { g.perms = perms.map(p => p.key).filter(k => vals.includes(k)); cardEl.querySelector('[data-h=pc]').textContent = g.perms.length; refreshDirtyUi(); },
      });
      ch.el.classList.add('mx-chips');
      if (locked) ch.el.style.pointerEvents = 'none';
      cardEl.querySelectorAll('[data-g]').forEach(inp => inp.addEventListener('input', () => {
        const k = inp.dataset.g;
        g[k] = k === 'salary' ? Math.max(0, Math.round(num(inp.value))) : (k === 'name' ? inp.value.replace(/[^\w-]/g, '') : inp.value);
        refreshDirtyUi();
      }));
      const a = s => cardEl.querySelector(`[data-a=${s}]`);
      if (a('up')) a('up').onclick = () => { [grades[i + 1], grades[i]] = [grades[i], grades[i + 1]]; renderMain(); refreshDirtyUi(); };
      if (a('down')) a('down').onclick = () => { [grades[i - 1], grades[i]] = [grades[i], grades[i - 1]]; renderMain(); refreshDirtyUi(); };
      if (a('del')) a('del').onclick = () => confirmBox({
        title: T('remove_grade', 'Remove "%s"?', g.label), text: T('remove_grade_text', 'People on this rank drop one rung when you save.'),
        label: T('remove', 'Remove'), onYes: () => { grades.splice(i, 1); renderMain(); refreshDirtyUi(); },
      });
      if (a('all')) a('all').onclick = () => { g.perms = perms.map(p => p.key); renderMain(); refreshDirtyUi(); };
      if (a('none')) a('none').onclick = () => { g.perms = []; renderMain(); refreshDirtyUi(); };
      if (a('copy')) a('copy').onclick = () => { g.perms = [...grades[i - 1].perms]; renderMain(); refreshDirtyUi(); };
    });
    body.querySelector('[data-a=add]').onclick = () => {
      if (grades.length >= num(S.data.limits && S.data.limits.grades, 20)) { toast(T('err_limit_hint', 'Limit reached.'), 'error'); return; }
      const g = { label: T('new_grade', 'New rank'), name: `grade${grades.length}`, salary: 0, perms: grades.length ? [...grades[grades.length - 1].perms] : [] };
      if (S.mode === 'boss') {
        // command desk: new ranks go in below your own
        const at = Math.min(myLevel(), grades.length);
        grades.splice(at, 0, g);
      } else grades.push(g);
      renderMain(); refreshDirtyUi();
    };
  }

  /* ── uniforms ── */
  function outfitBits(data) {
    if (!data) return '';
    const bits = [];
    (data.components || []).forEach(c => { if (c[1] > 0 || c[0] === 11) bits.push([COMP[c[0]] || c[0], `${c[1]}${c[2] ? `:${c[2]}` : ''}`]); });
    (data.props || []).forEach(p => { if (p[1] >= 0) bits.push([PROP[p[0]] || p[0], p[1]]); });
    return bits.slice(0, 6).map(([k, v]) => `<span><i>${esc(k)}</i>${esc(v)}</span>`).join('');
  }

  async function capture(gender) {
    const res = await NZA.post(`${APP}:capture`, {});
    if (!res || res.ok === false) { toast((res && res.msg) || T('err_failed', 'Something went wrong. Try again.'), 'error'); return null; }
    if (gender && res.gender !== gender) { toast(T('err_wrong_gender', 'You are playing a %s character. Save it to that side.', res.gender === 'male' ? T('male', 'Male') : T('female', 'Female')), 'error'); return null; }
    return res;
  }

  function outfitsView(body, dr) {
    const list = dr.outfits = dr.outfits || [];
    const gradeOpts = (dr.grades || []).map(g => ({ value: String(g.level), label: g.label }));
    body.innerHTML = `
      <div class="mx-bar"><button class="btn-teal" data-a="new">${icon('hanger')}${esc(T('outfit_new', 'Save what I wear as a uniform'))}</button><button class="btn-line" data-a="restore">${icon('rot-l')}${esc(T('restore_clothes', 'Back to my own clothes'))}</button></div>
      ${list.length ? `<div class="mx-og">${list.map((o, i) => `
        <div class="mx-card mx-oc" data-i="${i}" style="animation-delay:${i * 40}ms">
          <div class="mx-ch"><span class="mx-ci">${icon('hanger')}</span><input class="nz-input" data-o="name" maxlength="32" value="${esc(o.name)}"><button class="mx-ib red" data-a="del" title="${esc(T('remove', 'Remove'))}">${icon('trash')}</button></div>
          <div class="mx-cb">
            <div class="mx-gs">${['male', 'female'].map(gd => `
              <div class="mx-g ${o[gd] ? 'ok' : ''}"><div class="gh"><span class="mx-av sm ${o[gd] ? 'on' : ''}">${ring(o[gd] ? 1 : 0.0001)}<b>${icon('person')}</b></span><div><b>${esc(gd === 'male' ? T('male', 'Male') : T('female', 'Female'))}</b><span>${esc(o[gd] ? T('saved_pieces', 'Saved') : T('empty', 'Empty'))}</span></div></div>
                <div class="bits">${o[gd] ? outfitBits(o[gd]) : `<span class="ph">${esc(T('outfit_empty', 'Dress up, then save it here'))}</span>`}</div>
                <div class="acts"><button class="btn-line btn-sm" data-a="cap" data-g="${gd}">${icon('download')}${esc(T('save_current', 'Save'))}</button><button class="btn-line btn-sm" data-a="try" data-g="${gd}" ${o[gd] ? '' : 'disabled'}>${icon('eye')}${esc(T('try_on', 'Try on'))}</button></div></div>`).join('')}
            </div>
            <div class="mx-f"><label>${esc(T('outfit_grades', 'Ranks'))}</label><div data-h="grades"></div><small>${esc(o.grades && o.grades.length ? T('outfit_some', 'Only these ranks find it in the locker.') : T('outfit_all', 'No rank picked: every rank finds it.'))}</small></div>
          </div>
        </div>`).join('')}</div>` : `<div class="mx-none">${icon('hanger')}<b>${esc(T('no_outfits', 'No uniforms yet'))}</b><span>${esc(T('no_outfits_text', 'Put the uniform on with your clothing menu, then press "Save what I wear as a uniform". Do it once on a male and once on a female character.'))}</span></div>`}`;
    body.querySelector('[data-a=new]').onclick = async () => {
      if (list.length >= num(S.data.limits && S.data.limits.outfits, 40)) { toast(T('err_limit_hint', 'Limit reached.'), 'error'); return; }
      const res = await capture(null);
      if (!res) return;
      const o = { id: `o${Date.now().toString(36)}`, name: T('outfit_n', 'Uniform %s', list.length + 1), grades: [], male: null, female: null };
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
        title: T('remove_outfit', 'Remove "%s"?', o.name), text: T('remove_outfit_text', 'Lockers stop handing it out when you save.'),
        label: T('remove', 'Remove'), onYes: () => { list.splice(list.indexOf(o), 1); renderMain(); refreshDirtyUi(); },
      });
      cardEl.querySelectorAll('[data-a=cap]').forEach(bt => { bt.onclick = async () => { const res = await capture(bt.dataset.g); if (!res) return; o[bt.dataset.g] = res.data; renderMain(); refreshDirtyUi(); }; });
      cardEl.querySelectorAll('[data-a=try]').forEach(bt => { bt.onclick = () => { const data = o[bt.dataset.g]; if (data) NZA.post(`${APP}:tryOn`, { data }); }; });
    });
  }

  /* ── sites ── */
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
    return `<div class="mx-pe">
      <div class="mx-fields"><div class="mx-f"><label>${esc(T('point_label', 'Name on site'))}</label><input class="nz-input" data-pf="__label" maxlength="64" placeholder="${esc(t.label)}" value="${esc(p.label || '')}"></div>${fields}</div>
      ${t.desc ? `<div class="mx-note">${esc(t.desc)}</div>` : ''}
      <div class="foot"><button class="btn-line btn-sm" data-a="cancel">${esc(T('cancel', 'Keep it'))}</button><button class="btn-teal btn-sm" data-a="savep">${icon('save')}${esc(T('save', 'Save'))}</button></div></div>`;
  }

  const kindLabel = k => ({ prop: T('k_prop', 'Prop'), marker: T('k_marker', 'Marker'), car: T('k_car', 'Vehicle bay'), heli: T('k_heli', 'Helipad') }[k] || k);

  function siteRow(p, editing) {
    const t = typeDef(p.type);
    const dd = dist(p.coords);
    const near = dd !== null && dd < 25;
    return `<div class="mx-site ${editing ? 'edit' : ''}" data-id="${p.id}">
      <div class="row"><span class="mx-ci ${t.manager === false ? 'mute' : ''}">${icon(t.icon || 'pin')}</span>
        <div class="tx"><b>${esc(p.label || t.label)} <em>#${p.id}</em></b><span>${fmtC(p.coords.x)}, ${fmtC(p.coords.y)}, ${fmtC(p.coords.z)} · ${num(p.coords.w).toFixed(1)}°</span></div>
        <div class="tags">${pointSummary(p, t)}</div>
        <div class="rng ${near ? 'near' : ''}">${ring(dd === null ? 0 : Math.max(0.04, 1 - Math.min(1, dd / 400)), '', 'xs')}<b>${esc(fmtDist(dd) || '—')}</b></div>
        ${isAdmin() ? `<div class="mx-act"><button class="mx-ib" data-a="go" title="${esc(T('go_to', 'Travel there'))}">${icon('teleport')}</button><button class="mx-ib" data-a="move" title="${esc(T('replace', 'Move it'))}">${icon('crosshair')}</button>${editing !== null ? `<button class="mx-ib ${editing ? 'teal' : ''}" data-a="edit" title="${esc(T('edit', 'Settings'))}">${icon('sliders')}</button>` : ''}<button class="mx-ib red" data-a="del" title="${esc(T('delete', 'Remove'))}">${icon('trash')}</button></div>` : ''}
      </div>${editing ? pointEditor(p, t) : ''}</div>`;
  }

  function bindSiteRows(scope, pts) {
    scope.querySelectorAll('.mx-site').forEach(row => {
      const id = Number(row.dataset.id);
      const p = pts.find(x => x.id === id);
      if (!p) return;
      const t = typeDef(p.type);
      const a = s => row.querySelector(`[data-a=${s}]`);
      if (!a('go')) return;
      a('go').onclick = () => NZA.post(`${APP}:goto`, { coords: p.coords });
      a('move').onclick = () => place({ dept: p.hospital, type: p.type, point: p.id });
      if (a('edit')) a('edit').onclick = () => { S.editing = S.editing === id ? null : id; renderMain(); };
      a('del').onclick = () => confirmBox({
        title: T('delete_point', 'Remove %s #%s?', p.label || t.label, p.id), text: T('delete_point_text', 'It vanishes for everyone straight away.'),
        label: T('delete', 'Remove'), onYes: async () => { const res = await act('pointDelete', { id }); if (res) { S.editing = null; renderRail(); renderMain(); } },
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

  function positionsView(body, d, all) {
    const pts = all ? ((S.data && S.data.points) || []) : pointsOf(d.id);
    const zones = all ? [] : zonesFor(d.id);
    if (!all && S.zone !== 'all' && !zones.some(z => z.id === S.zone)) S.zone = 'all';
    const zone = !all && S.zone !== 'all' ? zones.find(z => z.id === S.zone) : null;
    const regTypes = S.types.filter(t => t.manager !== false && !GARAGE_TYPES.includes(t.name) && (!zone || zone.types.includes(t.name)));
    let list = pts.filter(p => !zone || zone.types.includes(p.type));
    const counts = {};
    list.forEach(p => { counts[p.type] = (counts[p.type] || 0) + 1; });
    const filterTypes = Object.keys(counts).sort((a, b) => String(typeDef(a).label).localeCompare(typeDef(b).label));
    if (S.posFilter !== 'all' && !counts[S.posFilter]) S.posFilter = 'all';
    if (S.posFilter !== 'all') list = list.filter(p => p.type === S.posFilter);
    const byDist = (a, b) => { const da = dist(a.coords), db = dist(b.coords); return (da === null ? 1e9 : da) - (db === null ? 1e9 : db); };
    list = list.slice().sort((a, b) => (a.hospital === b.hospital ? byDist(a, b) || a.id - b.id : String(a.hospital).localeCompare(b.hospital)));

    // zone board
    const allPts = pts.length;
    const board = all ? '' : `<div class="mx-zones">${[{ id: 'all', label: T('zone_all', 'Every zone'), icon: 'grid', types: [], count: allPts }].concat(zones).map((z, i) => {
      const typesIn = z.id === 'all' ? S.types.filter(t => t.manager !== false && !GARAGE_TYPES.includes(t.name)).map(t => t.name) : z.types;
      const covered = typesIn.filter(tn => pts.some(p => p.type === tn)).length;
      const frac = typesIn.length ? covered / typesIn.length : 0;
      return `<button class="mx-zone ${S.zone === z.id ? 'on' : ''} ${z.count ? '' : 'z'}" data-zone="${esc(z.id)}" style="animation-delay:${i * 18}ms">
        <span class="mx-zr">${ring(Math.max(0.0001, frac))}${icon(z.icon)}</span><span class="tx"><b>${esc(z.label)}</b><span>${esc(T('n_sites', '%s sites', z.count))} · ${covered}/${typesIn.length}</span></span></button>`;
    }).join('')}</div>`;

    let lastDept = null;
    const rows = list.map(p => {
      let grp = '';
      if (all && p.hospital !== lastDept) {
        lastDept = p.hospital;
        const dep = server(p.hospital);
        grp = `<div class="mx-group"><span class="bdot" style="background:${esc(blipHex(dep && dep.blip && dep.blip.colour))}"></span>${esc(dep ? dep.label : p.hospital)}</div>`;
      }
      return grp + siteRow(p, S.editing === p.id);
    }).join('');
    const filt = filterTypes.length > 1 && (zone || all) ? `<div class="mx-tf">${[['all', T('all', 'All'), list.length]].concat(filterTypes.map(k => [k, typeDef(k).label, counts[k]])).map(([k, l, n]) => `<button class="chipx ${S.posFilter === k ? 'on' : ''}" data-pf-type="${esc(k)}">${esc(l)}<em>${k === 'all' ? Object.values(counts).reduce((x, y) => x + y, 0) : n}</em></button>`).join('')}</div>` : '';
    const listCard = `<div class="mx-card list"><div class="mx-ch"><span class="mx-ci">${icon('map')}</span><div class="sp"><h3>${esc(zone ? zone.label : all ? T('h_positions', 'All sites') : T('configured', 'Sites in the world'))}</h3><p>${esc(T('configured_sub', '%s set · nearest first, measured from you', list.length))}</p></div></div>
      <div class="mx-cb">${filt}${list.length ? `<div class="mx-pl">${rows}</div>` : `<div class="mx-none">${icon('pin')}<b>${esc(T('no_positions', 'Nothing set here yet'))}</b><span>${esc(all ? T('no_positions_all', 'Open a department and set its sites.') : T('no_positions_text', 'Pick a type on the right. Aim where it goes and press E.'))}</span></div>`}</div></div>`;
    const palette = all ? '' : `<aside class="mx-card drop"><div class="mx-ch"><span class="mx-ci teal">${icon('crosshair')}</span><div class="sp"><h3>${esc(T('add_position', 'Set a new site'))}</h3><p>${esc(T('add_position_sub', 'Aim with the camera, E sets it, Q backs out.'))}</p></div></div>
      <div class="mx-cb flush">${regTypes.length ? regTypes.map(t => `<button class="mx-type" data-t="${esc(t.name)}" title="${esc(t.desc || '')}"><span class="mx-ci">${icon(t.icon || 'pin')}</span><span class="tx"><b>${esc(t.label)}</b><span>${esc(kindLabel(t.kind))}${counts[t.name] || pts.some(p => p.type === t.name) ? ` · ${pts.filter(p => p.type === t.name).length}` : ''}</span></span><span class="go">${icon('plus')}</span></button>`).join('') : `<div class="mx-none sm">${icon('grid')}<span>${esc(T('no_types', 'No site types in this zone.'))}</span></div>`}</div></aside>`;

    body.innerHTML = `${board}${all ? listCard : `<div class="mx-split sites">${listCard}${palette}</div>`}`;
    body.querySelectorAll('[data-zone]').forEach(bt => { bt.onclick = () => { S.zone = bt.dataset.zone; S.posFilter = 'all'; S.editing = null; renderMain(); }; });
    body.querySelectorAll('[data-t]').forEach(bt => { bt.onclick = () => place({ dept: d.id, type: bt.dataset.t }); });
    body.querySelectorAll('[data-pf-type]').forEach(bt => { bt.onclick = () => { S.posFilter = bt.dataset.pfType; renderMain(); }; });
    bindSiteRows(body, pts);
  }

  /* ── fleet ── */
  function garageView(body, dr, d) {
    const veh = dr.vehicles = dr.vehicles || [];
    const pts = ((S.data && S.data.points) || []).filter(p => p.hospital === d.id && GARAGE_TYPES.includes(p.type));
    body.innerHTML = `
      <div class="mx-card"><div class="mx-ch"><span class="mx-ci">${icon('ambulance')}</span><div class="sp"><h3>${esc(T('vehicles', 'Vehicles'))}</h3><p>${esc(T('vehicles_sub', 'Model is the spawn name. Cars come out of vehicle bays, helicopters off helipads.'))}</p></div></div>
        <div class="mx-cb">${veh.length ? `<div class="mx-vl">${veh.map((v, i) => `<div class="mx-veh" data-i="${i}">
            <span class="mx-ci ${v.type === 'heli' ? 'amber' : ''}">${icon(v.type === 'heli' ? 'heli' : 'ambulance')}</span>
            <div class="mx-f"><label>${esc(T('label', 'Name'))}</label><input class="nz-input" data-v="label" maxlength="32" value="${esc(v.label)}"></div>
            <div class="mx-f"><label>${esc(T('model', 'Model'))}</label><input class="nz-input mono" data-v="model" maxlength="32" value="${esc(v.model)}"></div>
            <div class="mx-f"><label>${esc(T('type', 'Kind'))}</label><span data-h="type"></span></div>
            <div class="mx-f"><label>${esc(T('min_grade', 'From rank'))}</label><select class="nz-input" data-v="minGrade">${gradeOptions(dr, v.minGrade)}</select></div>
            <div class="mx-f sm"><label>${esc(T('livery', 'Livery'))}</label><input class="nz-input mono" type="number" min="-1" max="60" data-v="livery" value="${esc(v.livery === undefined ? -1 : v.livery)}" title="${esc(T('livery_help', '-1 keeps the default'))}"></div>
            <div class="mx-f sm"><label>${esc(T('extras', 'Extras'))}</label><input class="nz-input mono" data-v="extras" placeholder="1, 2, 5" value="${esc((v.extras || []).join(', '))}"></div>
            <button class="mx-ib red" data-a="del" title="${esc(T('remove', 'Remove'))}">${icon('trash')}</button></div>`).join('')}</div>` : `<div class="mx-none">${icon('ambulance')}<b>${esc(T('no_vehicles', 'No vehicles yet'))}</b><span>${esc(T('no_vehicles_text', 'Add what this department may take out.'))}</span></div>`}
          <button class="mx-add" data-a="add">${icon('plus')}${esc(T('add_vehicle', 'Add a vehicle'))}</button></div></div>
      <div class="mx-card"><div class="mx-ch"><span class="mx-ci">${icon('garage')}</span><div class="sp"><h3>${esc(T('spawns', 'Bays'))}</h3><p>${esc(T('spawns_sub', 'Where vehicles appear and where medics park them again.'))}</p></div>
        ${isAdmin() ? `<div class="mx-btns"><button class="btn-line btn-sm" data-t="garage">${icon('car')}${esc(typeDef('garage').label)}</button><button class="btn-line btn-sm" data-t="heli">${icon('heli')}${esc(typeDef('heli').label)}</button></div>` : ''}</div>
        <div class="mx-cb">${pts.length ? `<div class="mx-pl">${pts.map(p => siteRow(p, null)).join('')}</div>` : `<div class="mx-none">${icon('garage')}<b>${esc(T('no_spawns', 'No bays yet'))}</b><span>${esc(T('no_spawns_text', 'Set a vehicle bay and a helipad where the vehicles should appear.'))}</span></div>`}</div></div>`;
    body.querySelectorAll('.mx-veh[data-i]').forEach(rowEl => {
      const v = veh[Number(rowEl.dataset.i)];
      NZA.ui.Segmented(rowEl.querySelector('[data-h=type]'), { options: [{ value: 'car', label: T('seg_car', 'Road') }, { value: 'heli', label: T('seg_heli', 'Air') }], value: v.type || 'car', onChange: x => { v.type = x; rowEl.querySelector('.mx-ci').innerHTML = icon(x === 'heli' ? 'heli' : 'ambulance'); rowEl.querySelector('.mx-ci').classList.toggle('amber', x === 'heli'); refreshDirtyUi(); } });
      rowEl.querySelectorAll('[data-v]').forEach(inp => {
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
      rowEl.querySelector('[data-a=del]').onclick = () => { veh.splice(veh.indexOf(v), 1); renderMain(); refreshDirtyUi(); };
    });
    body.querySelector('[data-a=add]').onclick = () => {
      if (veh.length >= num(S.data.limits && S.data.limits.vehicles, 40)) { toast(T('err_limit_hint', 'Limit reached.'), 'error'); return; }
      veh.push({ id: `v${Date.now().toString(36)}`, model: 'ambulance', label: T('new_vehicle', 'Ambulance'), type: 'car', minGrade: 0, livery: -1, extras: [] });
      renderMain(); refreshDirtyUi();
    };
    body.querySelectorAll('[data-t]').forEach(bt => { bt.onclick = () => place({ dept: d.id, type: bt.dataset.t }); });
    bindSiteRows(body, pts);
  }

  /* ── account (command desk) ── */
  function fundsView(body, d) {
    const bal = (S.data.society || {})[d.id] || 0;
    let account = 'cash';
    const staff = staffOf(d.id);
    const perShift = (d.grades || []).reduce((s, g) => s + num(g.salary) * staff.filter(x => x.grade === g.level).length, 0);
    body.innerHTML = `
      <div class="mx-grid">
        <div class="mx-col">
          <div class="mx-card bal"><div class="mx-ch"><span class="mx-ci">${icon('bank')}</span><div class="sp"><h3>${esc(T('balance', 'Balance'))}</h3><p>${esc(T('balance_sub', 'Account "%s"', d.society || d.job || d.id))}</p></div></div>
            <div class="mx-cb"><div class="mx-bal"><span class="cur">$</span><div data-h="odo"></div></div>
              <div class="mx-il">${irow(T('payroll_round', 'One pay round'), esc(money(perShift)))}${irow(T('rounds_left', 'Rounds covered'), perShift ? String(Math.floor(bal / perShift)) : '—', perShift && bal < perShift * 3 ? 'amber' : 'teal')}</div></div></div>
          ${card('swap', T('transfer', 'Move money'), T('transfer_sub', 'Between your own money and the department.'), `
            <div class="mx-row2"><div class="mx-f"><label>${esc(T('amount', 'Amount'))}</label><div class="mx-pre"><span>$</span><input class="nz-input mono" type="number" min="1" data-r="amount" placeholder="0"></div></div>
              <div class="mx-f"><label>${esc(T('account', 'From / to'))}</label><span data-h="acc"></span></div></div>
            <div class="mx-quick">${[100, 500, 1000, 5000, 10000].map(v => `<button class="chipx sm" data-q="${v}">+${esc(money(v))}</button>`).join('')}</div>
            <div class="mx-btns"><button class="btn-teal" data-a="dep">${icon('download')}${esc(T('deposit', 'Pay in'))}</button><button class="btn-line" data-a="wd">${icon('upload')}${esc(T('withdraw', 'Take out'))}</button></div>`)}
        </div>
        <div class="mx-col">
          ${card('users', T('payroll', 'Pay by rank'), T('payroll_sub', 'Paid out while people are on shift.'), `<div class="mx-il">${(d.grades || []).slice().reverse().map(g => irow(`${g.level} · ${g.label}`, `${esc(money(g.salary))}<small> × ${staff.filter(s => s.grade === g.level).length}</small>`)).join('')}</div>`)}
        </div>
      </div>`;
    NZA.ui.FlipClock(body.querySelector('[data-h=odo]'), { value: Math.round(bal).toLocaleString('en-US'), tone: 'teal' });
    const amt = body.querySelector('[data-r=amount]');
    NZA.ui.Segmented(body.querySelector('[data-h=acc]'), { options: [{ value: 'cash', label: T('cash', 'Cash') }, { value: 'bank', label: T('bank', 'Bank') }], value: account, onChange: v => { account = v; } });
    body.querySelectorAll('[data-q]').forEach(b => { b.onclick = () => { amt.value = num(amt.value) + Number(b.dataset.q); }; });
    const go = async action => {
      const amount = Math.round(num(amt.value));
      if (amount <= 0) { toast(T('err_bad_amount', 'Type a valid amount.'), 'error'); amt.focus(); return; }
      if (await act('funds', { dept: d.id, action, amount, account })) renderMain();
    };
    body.querySelector('[data-a=dep]').onclick = () => go('deposit');
    body.querySelector('[data-a=wd]').onclick = () => go('withdraw');
  }

  /* ── whole server ── */
  function hospitalOverview(body) {
    const t = (S.data && S.data.totals) || {};
    body.innerHTML = `<div class="mx-il row4">${irow(T('st_departments', 'Departments'), pad2(depts().length))}${irow(T('st_staff', 'Staff'), pad2(t.staff || 0))}${irow(T('st_duty', 'On shift'), pad2(t.onDuty || 0), t.onDuty ? 'teal' : '')}${irow(T('st_positions', 'Sites'), pad2(((S.data && S.data.points) || []).length))}</div>
      ${depts().length ? `<div class="mx-ug">${depts().map((d, i) => {
        const st = staffOf(d.id), duty = st.filter(s => s.onDuty).length, col = blipHex(d.blip && d.blip.colour);
        return `<button class="mx-card mx-uc" data-d="${esc(d.id)}" style="animation-delay:${i * 40}ms">
          <div class="top"><span class="mx-badge lg" style="--bc:${esc(col)}">${ring(st.length ? duty / st.length : 0.0001, col)}<b>${esc(codeOf(d.label))}</b></span>
            <div class="tx"><b>${esc(d.label)}</b><span class="mono">${esc(d.id)}</span><div class="chips">${d.job ? `<span class="nz-tag live">${icon('link')}${esc(d.job)}</span>` : `<span class="nz-tag off">${esc(T('standalone', 'Own roster'))}</span>`}${d.easy ? `<span class="nz-tag warn">${esc(T('c_easy', 'Simple care'))}</span>` : ''}</div></div></div>
          <div class="mx-il">${irow(T('st_staff', 'Staff'), pad2(st.length))}${irow(T('st_duty', 'On shift'), pad2(duty), duty ? 'teal' : '')}${irow(T('st_positions', 'Sites'), pad2(pointsOf(d.id).length))}${irow(T('st_vehicles', 'Fleet'), pad2((d.vehicles || []).length))}</div>
        </button>`;
      }).join('')}</div>` : `<div class="mx-none">${icon('building')}<b>${esc(T('no_depts', 'No departments yet.'))}</b></div>`}`;
    body.querySelectorAll('.mx-uc[data-d]').forEach(c => { c.onclick = () => select(c.dataset.d, 'overview'); });
  }

  function dutyView(body) {
    const groups = depts().map(d => ({ d, rows: staffOf(d.id).filter(s => s.onDuty) })).filter(g => g.rows.length);
    body.innerHTML = groups.length ? groups.map(({ d, rows }) => `<div class="mx-card mx-dutyonly">
        <div class="mx-ch"><span class="mx-badge sm" style="--bc:${esc(blipHex(d.blip && d.blip.colour))}">${ring(1, blipHex(d.blip && d.blip.colour))}<b>${esc(codeOf(d.label))}</b></span><div class="sp"><h3>${esc(d.label)}</h3><p>${esc(T('n_on_shift', '%s on shift', rows.length))}</p></div></div>
        <div class="mx-cb flush">${rows.map(s => `<div class="mx-person duty"><span class="mx-av on">${ring(1)}<b>${esc(initials(s.name))}</b></span><div class="tx"><b>${esc(s.name)}</b><span><i class="s live">${esc((d.grades[s.grade] || {}).label || s.grade)}</i>${esc(s.identifier)}</span></div><span class="since">${esc(s.src ? `#${s.src}` : '—')}</span></div>`).join('')}</div></div>`).join('')
      : `<div class="mx-none">${icon('pulse')}<b>${esc(T('nobody_duty', 'Nobody is on shift'))}</b></div>`;
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
      const body = compactWin(T('locker', 'Uniform locker'), `${d.dept || ''}${d.grade ? ` · ${d.grade}` : ''}`);
      body.innerHTML = `${!d.gender ? `<div class="mx-note amber">${esc(T('locker_freemode', 'Uniforms only fit the multiplayer male and female characters.'))}</div>` : ''}
        ${(d.outfits || []).length ? d.outfits.map(o => `<div class="mx-li ${o.fits ? '' : 'off'}"><span class="mx-ci">${icon('hanger')}</span><div class="tx"><b>${esc(o.name)}</b><span>${esc(o.fits ? T('fits', 'Fits your character') : T('no_fit', 'No version for your character'))}${o.grades && o.grades.length ? ` · ${esc((o.grades || []).map(g => (d.grades || [])[g] || g).join(', '))}` : ''}</span></div><button class="btn-teal btn-sm" data-wear="${esc(o.id)}" ${o.fits ? '' : 'disabled'}>${esc(T('wear', 'Put on'))}</button></div>`).join('')
          : `<div class="mx-none">${icon('hanger')}<b>${esc(T('locker_empty', 'This locker is empty'))}</b><span>${esc(T('locker_empty_text', 'Your command adds uniforms in the Department Console.'))}</span></div>`}
        <div class="mx-cfoot"><span class="t-dim">${esc(T('locker_hint', 'Your own clothes wait here until you change back.'))}</span><button class="btn-line" data-a="civ" ${d.civvies ? '' : 'disabled'}>${icon('rot-l')}${esc(T('civvies', 'My own clothes'))}</button></div>`;
      body.querySelectorAll('[data-wear]').forEach(b => { b.onclick = async () => { const r = await NZA.post(`${APP}:wear`, { id: b.dataset.wear }); if (r && r.ok === false && r.msg) toast(r.msg, 'error'); }; });
      body.querySelector('[data-a=civ]').onclick = () => NZA.post(`${APP}:civvies`, {});
    } else if (C.mode === 'storage') {
      const body = compactWin(T('storage', 'Supply cabinet'), d.dept || '');
      C.qty = C.qty || {};
      body.innerHTML = `<div class="mx-note">${esc(T('storage_note', 'Free while you are on shift. Every item has a limit per shift.'))}</div>` + ((d.items || []).length ? (d.items || []).map(it => {
        const left = Math.max(0, (it.limit || 0) - (it.taken || 0));
        const q = Math.min(C.qty[it.key] || 1, Math.max(1, left));
        return `<div class="mx-li ${left ? '' : 'off'}">${itemImg(it)}<div class="tx"><b>${esc(it.label)}</b><span>${esc(T('left_shift', '%s left this shift', left))}</span></div>
          <span class="mx-av sm ${left ? 'on' : ''}">${ring(left / Math.max(1, it.limit), left ? '' : 'var(--red)')}<b class="mono">${left}</b></span>
          <div class="mx-step"><button data-dec="${esc(it.key)}">${icon('minus')}</button><span>${q}</span><button data-inc="${esc(it.key)}">${icon('plus')}</button></div>
          <button class="btn-teal btn-sm" data-take="${esc(it.key)}" ${left ? '' : 'disabled'}>${esc(T('take', 'Take'))}</button></div>`;
      }).join('') : `<div class="mx-none">${icon('medkit')}<b>${esc(T('storage_empty', 'Nothing here for your rank'))}</b></div>`);
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
      const body = compactWin(heli ? T('helipad', 'Helipad') : T('garage', 'Vehicle bay'), `${d.dept || ''}${d.max ? ` · ${T('out_of', '%s of %s out', d.out || 0, d.max)}` : ''}`);
      body.innerHTML = (d.vehicles || []).length ? d.vehicles.map(v => `<div class="mx-li ${v.locked ? 'off' : ''}"><span class="mx-ci ${v.locked ? 'mute' : heli ? 'amber' : ''}">${icon(v.type === 'heli' ? 'heli' : 'ambulance')}</span><div class="tx"><b>${esc(v.label)}</b><span><em class="mx-mono">${esc(v.model)}</em>${v.locked ? ` · ${esc(T('needs_grade', 'From %s', v.gradeLabel || v.minGrade))}` : ''}</span></div><button class="btn-teal btn-sm" data-spawn="${esc(v.id)}" ${v.locked || (d.max && d.out >= d.max) ? 'disabled' : ''}>${icon('key')}${esc(T('take_out', 'Sign out'))}</button></div>`).join('')
        : `<div class="mx-none">${icon(heli ? 'heli' : 'ambulance')}<b>${esc(T('garage_empty', 'Nothing parked here'))}</b><span>${esc(T('garage_empty_text', 'The department has no vehicles of this kind yet.'))}</span></div>`;
      if (d.max && d.out >= d.max) body.insertAdjacentHTML('afterbegin', `<div class="mx-note amber">${esc(T('too_many_out', 'You already have %s vehicles out. Park one first.', d.out))}</div>`);
      body.querySelectorAll('[data-spawn]').forEach(b => { b.onclick = async () => { b.disabled = true; const r = await NZA.post(`${APP}:spawn`, { id: b.dataset.spawn }); if (!r || r.ok === false) { toast((r && r.msg) || T('err_failed', 'Something went wrong. Try again.'), 'error'); b.disabled = false; } }; });
    } else if (C.mode === 'elevator') {
      const body = compactWin(T('elevator', 'Lift'), `${d.dept || ''}`);
      const floors = (d.floors || []).slice().sort((a, b) => num(b.order) - num(a.order));
      body.innerHTML = `<div class="mx-floors">${floors.map(f => `<button class="mx-floor ${f.current ? 'cur' : ''}" data-floor="${esc(f.id)}"><span class="lv">${esc(f.order)}</span><span class="tx"><b>${esc(f.label)}</b><span>${esc(f.current ? T('you_are_here', 'You are here') : T('go_floor', 'Ride here'))}</span></span><span class="go">${icon(f.current ? 'pin' : 'chev-r')}</span></button>`).join('')}</div>`;
      body.querySelectorAll('[data-floor]').forEach(b => { b.onclick = () => NZA.post(`${APP}:floor`, { id: Number(b.dataset.floor) }); });
    } else if (C.mode === 'stash') {
      const body = compactWin(d.title || T('stash', 'Staff store'), T('stash_sub', 'Shared by the whole department'), true);
      C.amount = Math.max(1, num(C.amount, 1));
      C.whole = !!C.whole;
      const col = (title, list, dir) => `<div class="mx-ccol"><h4><span>${icon(dir === 'out' ? 'box' : 'backpack')}${esc(title)}</span><b>${list.length}</b></h4><div class="lst nza-scroll" data-wheel>${list.length ? list.map((it, i) => `<div class="mx-li">${itemImg(it)}<div class="tx"><b>${esc(it.label)}</b><span>${esc(it.meta ? T('has_meta', 'Labelled unit') : it.name)}</span></div><span class="cnt">${esc(it.count)}</span><button class="mx-ib teal" data-mv="${dir}" data-i="${i}" title="${esc(dir === 'out' ? T('take', 'Take') : T('put', 'Store'))}">${icon(dir === 'out' ? 'arrow-r' : 'arrow-l')}</button></div>`).join('') : `<div class="mx-none sm">${icon('box')}<b>${esc(T('empty', 'Empty'))}</b></div>`}</div></div>`;
      body.innerHTML = `<div class="mx-mv">
          <div class="t"><b>${esc(T('move_amount', 'Move per click'))}</b><small>${esc(T('move_amount_help', 'Arrows move this many; whole stack moves everything in that row.'))}</small></div>
          <div class="mx-step big ${C.whole ? 'dim' : ''}"><button data-amt="-1">${icon('minus')}</button><span data-h="amt">${C.amount}</span><button data-amt="1">${icon('plus')}</button></div>
          <label class="mx-whole"><span data-h="whole"></span>${esc(T('whole_stack', 'Whole stack'))}</label></div>
        <div class="mx-cgrid">${col(T('stash', 'Staff store'), d.items || [], 'out')}${col(T('pockets', 'On you'), d.inv || [], 'in')}</div>`;
      body.querySelectorAll('[data-amt]').forEach(b => { b.onclick = () => { C.amount = Math.max(1, Math.min(999, C.amount + Number(b.dataset.amt))); body.querySelector('[data-h=amt]').textContent = C.amount; }; });
      NZA.ui.Toggle(body.querySelector('[data-h=whole]'), { on: C.whole, onChange: v => { C.whole = v; body.querySelector('.mx-step.big').classList.toggle('dim', v); } });
      body.querySelectorAll('[data-mv]').forEach(b => {
        b.onclick = async () => {
          const dir = b.dataset.mv, i = Number(b.dataset.i);
          const it = dir === 'out' ? d.items[i] : d.inv[i];
          const count = C.whole ? it.count : Math.min(it.count, C.amount);
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
      S.sel = { dept: null, view: 'overview' }; S.drafts = {}; S.base = {}; S.search = ''; S.filter = 'all'; S.posFilter = 'all'; S.zone = 'all';
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
    renderRail();
    renderMain();
  }

  NZA.app(APP, {
    init(el) { root = el; },
    open(data) {
      if (data.locale) LOC = Object.assign({}, LOC, data.locale);
      if (data.compact) {
        C = { mode: data.mode, data, qty: {}, amount: 1, whole: false };
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
    // preview helper: NZA.apps.manager.go('roster', 'lsmd') · go('f:xray') opens Sites on that zone
    go(v, id) { select(id || S.sel.dept, v); },
    newDept() { newDeptModal(); },
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
    const permList = [['assess', 'Assess patients'], ['basic', 'Basic first aid'], ['cpr', 'CPR'], ['defib', 'Defibrillator'], ['iv', 'IV / IO access'], ['blood', 'Blood products'], ['binder', 'Pelvic binder'], ['splint', 'Splints & collars'], ['suture', 'Wound closure'], ['burn', 'Burn care'], ['graft', 'Skin grafts'], ['airway', 'Airway'], ['ultrasound', 'Ultrasound'], ['chestdrain', 'Chest drain'], ['pericardio', 'Pericardiocentesis'], ['xray', 'Radiology'], ['surgery', 'Surgery'], ['angio', 'Angiography'], ['meds', 'Medication'], ['transport', 'Transport'], ['bodybag', 'Body bags & mortuary'], ['checkin', 'Front desk'], ['pharmacy', 'Dispensary staff'], ['manage', 'Department command']].map(([key, label]) => ({ key, label }));
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
        grades: grades(), outfits: [{ id: 'o1', name: 'EMS duty uniform', grades: [], male: outfit(250, 96), female: outfit(258, 99) }, { id: 'o2', name: 'Surgeon scrubs', grades: [3, 4], male: outfit(146, 9), female: null }],
        vehicles: [{ id: 'v1', model: 'ambulance', label: 'Ambulance', type: 'car', minGrade: 0, livery: 0, extras: [1, 2] }, { id: 'v2', model: 'lguard', label: 'Rapid response', type: 'car', minGrade: 2, livery: -1, extras: [] }, { id: 'v3', model: 'polmav', label: 'Air ambulance', type: 'heli', minGrade: 3, livery: 1, extras: [] }] },
      { id: 'sandy', label: 'Sandy Shores Medical', description: '', job: null, discord: null, society: 'sandymed', easy: true, easyPerms: { surgery: false },
        hq: { x: 1839.6, y: 3672.9, z: 34.28, w: 210 }, blip: { enabled: true, sprite: 61, colour: 3, scale: 0.8, label: 'Sandy Medical', shortRange: true },
        grades: grades().slice(0, 4), outfits: [], vehicles: [{ id: 'v4', model: 'ambulance', label: 'Ambulance', type: 'car', minGrade: 0, livery: 1, extras: [] }] },
      { id: 'lsfd', label: 'LSFD Rescue', description: 'Fire department paramedics.', job: 'fire', discord: null, society: null, easy: false, easyPerms: {}, hq: null,
        blip: { enabled: true, sprite: 61, colour: 17, scale: 0.85, shortRange: true }, grades: grades().slice(0, 3), outfits: [], vehicles: [] },
    ];
    const names = [['Maya Reyes', 4, 1, 1], ['Priya Nair', 3, 1, 1], ['Theo Kane', 2, 1, 0], ['Sam Brooks', 0, 1, 1], ['Lena Park', 2, 0, 0], ['Ravi Shah', 1, 0, 0], ['Ella Novak', 1, 1, 1], ['Owen Price', 0, 0, 0]];
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
      t('duty', 'Shift Clock', 'clock', 'marker', {}, 'Clock on and off here.'), t('locker', 'Uniform Locker', 'hanger', 'marker', {}, 'Change into the department uniforms.'),
      t('stash', 'Staff Store', 'box', 'marker', { slots: 80, weight: 250000, personal: false, minGrade: 0 }, 'Shared department storage.'),
      t('boss', 'Command Desk', 'crown', 'marker', {}, 'Staff, ranks, uniforms, fleet and account.'), t('storage', 'Supply Cabinet', 'medkit', 'marker', {}, 'Free supplies per shift.'),
      t('garage', 'Vehicle Bay', 'car', 'car', {}, 'Vehicles come out here.'), t('heli', 'Helipad', 'heli', 'heli', {}, 'Helicopters come out here.'),
      t('elevator', 'Lift Stop', 'building', 'marker', { group: 'main', floor: 'Ground floor', order: 0, staffOnly: false }, 'Stops with the same group are linked floors.'),
      t('bed', 'Ward Bed', 'bed', 'marker', {}, 'Lie down to heal four times faster.'), t('respawn', 'Recovery Point', 'heart', 'marker', {}, 'Where the dead wake up.'),
      t('hq', 'Base Point', 'flag', 'marker', {}, '', false),
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
    NZA.mock(`${APP}:create`, p => { const nd = clone(depts[2]); nd.id = p.id; nd.label = p.label; nd.job = null; nd.hq = null; data.depts.push(nd); data.staff[p.id] = []; return { ok: true, dept: p.id, data: clone(data), msg: `${p.label} registered.` }; });
    NZA.mock(`${APP}:save`, p => { const i = data.depts.findIndex(x => x.id === p.dept.id); const c = clone(p.dept); (c.grades || []).forEach((g, k) => { g.level = k; delete g.from; }); data.depts[i] = c; return { ok: true, data: clone(data), msg: `${c.label} saved.` }; });
    const params = new URLSearchParams(location.search);
    const mode = params.get('mode');
    const locale = {};
    if (mode === 'locker') {
      NZA.open(APP, { compact: true, mode, dept: 'Los Santos Medical', grade: 'Paramedic', gender: 'male', civvies: true, grades: ['Trainee', 'EMT', 'Paramedic', 'Doctor', 'Chief'], locale,
        outfits: [{ id: 'o1', name: 'EMS duty uniform', grades: [], male: true, female: true, fits: true }, { id: 'o3', name: 'Winter jacket', grades: [1, 2, 3], male: true, female: true, fits: true }, { id: 'o2', name: 'Surgeon scrubs', grades: [3, 4], male: false, female: true, fits: false }] });
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
      NZA.open(APP, { compact: true, mode, dept: 'Los Santos Medical', title: 'Los Santos Medical · Staff store', locale,
        items: [it('bandage', 'Bandage', 48, { index: 1 }), it('saline_bag', 'Saline 500 ml', 12, { index: 2 }), it('blood_bag', 'Blood Bag', 1, { index: 3, meta: { type: 'O-' } }), it('splint', 'Splint', 6, { index: 4 }), it('defibrillator', 'Defibrillator', 1, { index: 5 })],
        inv: [it('gauze', 'Gauze', 4, { slot: 1 }), it('morphine', 'Morphine', 2, { slot: 2 }), it('tourniquet', 'Tourniquet', 1, { slot: 3 })] });
    } else {
      if (mode === 'boss') { data.mode = 'boss'; data.admin = false; data.depts = [depts[0]]; data.points = points.filter(p => GARAGE_TYPES.includes(p.type) && p.hospital === 'lsmd'); data.me.grade = 3; }
      NZA.open(APP, { mode: data.mode, data, types, me: { x: 306.4, y: -590.2, z: 43.28, w: 70 }, locale });
      const v = params.get('view');
      if (v) select(params.get('dept') || S.sel.dept, v);
      if (params.get('zone')) select(null, `f:${params.get('zone')}`);
      if (params.get('modal') === 'new') newDeptModal();
    }
  }
})();
