'use strict';
/* ═══ self toggles ══════════════════════════════════════════════════════ */
async function toggleSelf(key, state) {
  const r = await loc('toggle', { key, state });
  if (r && r.toggles) { S.toggles = r.toggles; if (S.mode === 'quick') refreshQuick(); }
  return r;
}

/* ═══ QUICK MENU (right side) ═══════════════════════════════════════════ */
const QTOGGLES = [
  ['noclip', 'Noclip', 'fas fa-feather', 'self.noclip'], ['god', 'God mode', 'fas fa-shield-heart', 'self.godmode'],
  ['invis', 'Invisible', 'fas fa-ghost', 'self.invisibility'], ['superjump', 'Super jump', 'fas fa-person-running', 'self.super_jump'],
  ['fastrun', 'Fast run', 'fas fa-gauge-high', 'self.fast_run'], ['ammo', 'Infinite ammo', 'fas fa-infinity', 'self.infinite_ammo'],
  ['names', 'Names', 'fas fa-signature', 'self.player_names'], ['ids', 'Player IDs', 'fas fa-hashtag', 'self.player_ids'],
  ['coords', 'Coords', 'fas fa-crosshairs', 'self.show_coords'], ['freeze', 'Freeze self', 'fas fa-snowflake', 'self.freeze'],
  ['vehgod', 'Vehicle god', 'fas fa-car-burst', 'self.godmode'], ['night', 'Night vision', 'fas fa-moon', 'self.night_vision'],
  ['thermal', 'Thermal', 'fas fa-temperature-half', 'self.thermal_vision'], ['headlight', 'Head light', 'fas fa-lightbulb', 'self.head_light'],
  ['blackout', 'Local blackout', 'fas fa-power-off', 'self.blackout'],
];
// id, label, icon, click action (data-a), value, permission check
const QACTIONS = [
  ['waypoint', 'To waypoint', 'fas fa-location-crosshairs', 'qWaypoint', '', () => can('self.teleport')],
  ['back', 'Back', 'fas fa-arrow-rotate-left', 'qBack', '', () => can('self.teleport')],
  ['heal', 'Heal', 'fas fa-kit-medical', 'qHeal', '', () => can('self.revive')],
  ['revive', 'Revive', 'fas fa-heart-pulse', 'qRevive', '', () => can('self.revive')],
  ['clothing', 'Clothing', 'fas fa-shirt', 'qClothing', '', () => can('self.clothing_menu')],
  ['weapon', 'Weapon', 'fas fa-gun', 'qWeapon', '', () => can('self.give_weapon')],
  ['copy', 'Copy coords', 'fas fa-copy', 'qCopy', '', () => true],
  ['inspector', 'Inspector', 'fas fa-magnifying-glass-location', 'qInspector', '', () => can('self.entity_inspector')],
  ['kill', 'Kill self', 'fas fa-skull', 'qKill', '', () => can('self.kill'), 'danger'],
  ['repair', 'Repair', 'fas fa-wrench', 'qVeh', 'vehRepair', () => can('vehicles.repair')],
  ['flip', 'Flip', 'fas fa-rotate', 'qVeh', 'vehFlip', () => can('vehicles.repair')],
  ['max', 'Max upgrades', 'fas fa-bolt', 'qVeh', 'vehMax', () => can('vehicles.set_mods')],
  ['clean', 'Clean', 'fas fa-soap', 'qVeh', 'vehClean', () => can('vehicles.repair')],
  ['plate', 'Plate', 'fas fa-rectangle-list', 'qPlate', '', () => can('vehicles.set_plate')],
  ['delveh', 'Delete', 'fas fa-trash', 'qVeh', 'vehDelete', () => can('vehicles.despawn'), 'danger'],
  ['player', 'Player ID box', 'fas fa-id-badge', 'qFocusPlayer', '', () => quickPlayerOk(), '', true],
  ['vehicle', 'Vehicle box', 'fas fa-car', 'qFocusVeh', '', () => can('vehicles.spawn'), '', true],
  ['panel', 'Open panel', 'fas fa-table-columns', 'openPanel', '', () => can('self.panel')],
  ['duty', 'Toggle duty', 'fas fa-user-shield', 'toggleDuty', '', () => true, '', true],
  ['reviveR', 'Revive nearby', 'fas fa-circle-dot', 'qReviveR', '', () => can('player.revive')],
  ['announce', 'Announce', 'fas fa-bullhorn', 'qAnnounce', '', () => can('announcements.create')],
  ['reports', 'Reports', 'fas fa-flag', 'openPanel', 'reports', () => can('reports.view')],
];
const QKEYS_DEFAULT = {
  noclip: '1', god: '2', invis: '3', superjump: '4', fastrun: '5', ammo: '6', names: '7', ids: '8', coords: '9', freeze: '0',
  waypoint: 'T', back: 'B', heal: 'H', revive: 'R', copy: 'C', inspector: 'I', repair: 'F', flip: 'G', max: 'M', delveh: 'X',
  player: 'N', vehicle: 'V', panel: 'P', duty: 'D', announce: 'A', reports: 'O',
};
const qkeys = () => Object.assign({}, QKEYS_DEFAULT, S.settings.qkeys || {});
const quickPlayerOk = () => canAny('player.teleport', 'player.spectate', 'player.revive', 'player.heal', 'player.freeze');
/** everything in the quick menu that can sit on a key, in menu order */
function quickKeyList(all) {
  const k = qkeys();
  const t = QTOGGLES.filter(x => all || can(x[3])).map(([id, label]) => ({ id, label, key: k[id] || '', run: () => toggleSelf(id) }));
  const a = QACTIONS.filter(x => all || x[5]()).map(([id, label, , act, v]) => ({ id, label, key: k[id] || '', run: () => A[act] && A[act](v || undefined) }));
  return t.concat(a);
}
const hk = id => { const k = qkeys()[id]; return k && S.settings.hotkeys !== false ? `<span class="key hk">${esc(keyLabel(k))}</span>` : ''; };
const qact = id => QACTIONS.find(x => x[0] === id);
function qb(id) {
  const x = qact(id); if (!x || !x[5]()) return '';
  const [, label, icon, act, v, , cls] = x;
  const extra = id === 'reports' && S.badges.reports ? ` (${S.badges.reports})` : '';
  return `<button class="qbtn ${cls || ''}" data-a="${act}" ${v ? `data-v="${esc(v)}"` : ''}><i class="${icon}"></i><span class="ell">${esc(label + extra)}</span>${hk(id)}</button>`;
}
function quickHtml() {
  const g = S.me.group || {};
  const tg = QTOGGLES.filter(t => can(t[3])).map(([k, l, i]) => `<button class="tgl ${S.toggles[k] ? 'on' : ''}" data-a="qToggle" data-v="${k}"><i class="${i}"></i><span class="ell">${esc(l)}</span>${hk(k)}${swv(S.toggles[k])}</button>`).join('');
  const tps = (S.teleports || []).map((t, i) => `<button class="qbtn" data-a="qTp" data-v="${i}"><i class="${esc(t.icon || 'fas fa-location-dot')}"></i><span class="ell">${esc(t.name)}</span></button>`).join('');
  const pb = (l, v, i, perm, cls = '') => can(perm) ? `<button class="qbtn ${cls}" data-a="qPlayer" data-v="${v}" title="${esc(l)}"><i class="${i}"></i><span class="ell">${esc(l)}</span></button>` : '';
  const me = ['heal', 'revive', 'clothing', 'weapon', 'copy', 'inspector', 'kill'].map(qb).join('');
  const veh = ['repair', 'flip', 'max', 'clean', 'plate', 'delveh'].map(qb).join('');
  const srv = ['panel', 'reviveR', 'announce', 'reports'].map(qb).join('');
  return `<div class="qwrap"><div class="frame"><div class="shell">
    <div class="bar" style="padding-right:10px"><div class="bar-brand" style="width:auto;border-right:0;padding-right:0"><div class="mark"></div><div class="bar-title"><b>Quick menu</b><span>${esc(g.label || 'Staff')}</span></div></div>
      <span style="flex:1"></span><span class="ver">v${esc(S.cfg.version)}</span><button class="pill-close" data-a="close">Close</button></div>
    <div class="who" style="padding:10px 14px">${av(S.me.name, 'sm', true)}<div class="who-txt" style="flex:1"><b>${esc(S.me.name || '')}</b></div>
      <button class="duty ${S.me.duty ? 'on' : ''}" data-a="toggleDuty"><span class="dot"></span>${S.me.duty ? 'On duty' : 'Off duty'}</button>${hk('duty')}</div>
    <div class="qbody" id="qbody">
      ${tg ? `<div class="qsec">Self</div><div class="tg" id="qtg">${tg}</div>` : ''}
      ${can('self.teleport') ? `<div class="qsec">Teleport</div><div class="tg">${qb('waypoint')}${qb('back')}</div>
        <div style="display:flex;gap:6px;margin-top:6px"><input class="inp sm" id="q-coords" placeholder="x, y, z" data-enter="qCoords">${btn('Go', 'qCoords', 'sm')}</div>
        ${tps ? `<div class="tg" style="margin-top:6px">${tps}</div>` : ''}` : ''}
      ${quickPlayerOk() ? `<div class="qsec">Player ${hk('player')}</div><div style="display:flex;gap:6px"><input class="inp sm" id="q-pid" type="number" min="1" placeholder="Server ID" data-enter="qPlayerProfile" value="${esc(S.qpid || '')}" data-in="qPid">${can('self.panel') ? btn('Profile', 'qPlayerProfile', 'sm', { icon: 'fas fa-user' }) : ''}</div>
        <div class="tg tg3" style="margin-top:6px">${pb('Go to', 'goto', 'fas fa-location-arrow', 'player.teleport')}${pb('Bring', 'bring', 'fas fa-person-arrow-down-to-line', 'player.teleport')}${pb('Spectate', 'spectate', 'fas fa-eye', 'player.spectate')}${pb('Revive', 'revive', 'fas fa-heart-pulse', 'player.revive')}${pb('Heal', 'heal', 'fas fa-kit-medical', 'player.heal')}${pb('Freeze', 'freeze', 'fas fa-snowflake', 'player.freeze')}</div>` : ''}
      ${me ? `<div class="qsec">Me</div><div class="tg">${me}</div>` : ''}
      ${can('vehicles.spawn') || veh ? `<div class="qsec">Vehicle ${can('vehicles.spawn') ? hk('vehicle') : ''}</div>${can('vehicles.spawn') ? `<div style="display:flex;gap:6px"><input class="inp sm" id="q-veh" placeholder="Model, like adder" data-enter="qSpawn">${btn('Spawn', 'qSpawn', 'sm btn-teal')}</div>` : ''}
        ${veh ? `<div class="tg" style="margin-top:6px">${veh}</div>` : ''}` : ''}
      ${srv ? `<div class="qsec">Server</div><div class="tg">${srv}</div>` : ''}
    </div>
    <div class="statusbar"><span><span class="key">ESC</span>${S.keys.quick ? `<span class="key">${esc(keyLabel(S.keys.quick))}</span>` : ''}Close</span><span class="click" data-a="keyHelp"><span class="key">?</span>Keys</span><span class="sp"></span></div>
  </div></div></div>`;
}
function refreshQuick() {
  const box = $('#qtg'); if (!box) return;
  QTOGGLES.forEach(([k]) => { const b = box.querySelector(`[data-v="${k}"]`); if (b) { b.classList.toggle('on', !!S.toggles[k]); const s = b.querySelector('.sw'); if (s) s.classList.toggle('on', !!S.toggles[k]); } });
}
/* quick menu hotkeys */
KEYHANDLERS.push(e => {
  if (S.mode !== 'quick' || e.ctrlKey || e.altKey || e.metaKey) return false;
  const k = keyNorm(evKey(e));
  const it = quickKeyList().find(x => x.key && keyNorm(x.key) === k);
  if (!it) return false;
  it.run();
  return true;
});
A.qToggle = v => toggleSelf(v);
A.qTp = async v => { const t = S.teleports[+v]; if (t && await loc('tpCoords', t.coords)) A.close(); };
A.qWaypoint = async () => { if (await loc('tpWaypoint')) A.close(); };
A.qBack = async () => { if (await loc('back')) A.close(); };
A.qCoords = async () => { const raw = ($('#q-coords').value || '').replace(/vec(tor)?[34]?\(|\)/g, ''); const [x, y, z, w] = raw.split(/[\s,]+/).filter(Boolean).map(Number); if (isNaN(x) || isNaN(y)) return toast('Enter x, y and optionally z', 'error'); if (await loc('tpCoords', { x, y, z: isNaN(z) ? undefined : z, w: isNaN(w) ? undefined : w })) A.close(); };
A.qHeal = async () => { if (await loc('selfHeal')) toast('Healed', 'success'); };
A.qRevive = () => call('self:revive', {}, 'Revived');
A.qKill = async () => { if (await confirmBox('Kill yourself?', 'Your character goes down.')) loc('selfKill'); };
A.qClothing = async () => { await loc('selfClothing'); hideUI(); };
A.qWeapon = async () => { const f = await form({ title: 'Give myself a weapon', icon: 'fas fa-gun', fields: [{ name: 'weapon', label: 'Weapon', value: 'WEAPON_PISTOL', span: true, presets: ['WEAPON_PISTOL', 'WEAPON_CARBINERIFLE', 'WEAPON_SMG', 'WEAPON_STUNGUN', 'WEAPON_FLASHLIGHT'] }, { name: 'ammo', label: 'Ammo', type: 'number', value: 250 }] }); if (f) call('player:weapon', { weapon: f.weapon, ammo: +f.ammo }, 'Weapon given'); };
A.qCopy = async () => { const r = await loc('copyCoords', { format: 'vec4' }); if (r) toast(typeof r === 'string' ? r : 'Copied', 'success', 'Copied'); };
A.qInspector = async () => { if (await loc('inspector')) hideUI(); };
A.qSpawn = async () => { const i = $('#q-veh'); const m = (i && i.value || '').trim(); if (!m) { if (i) i.focus(); return; } if (await call('vehicles:spawn', { model: m })) A.close(); };
const VEHFAIL = { vehDelete: 'No vehicle near you', vehRepair: 'Sit in a vehicle first', vehFlip: 'Sit in a vehicle first', vehMax: 'Sit in a vehicle first', vehClean: 'Sit in a vehicle first' };
A.qVeh = async v => { const r = await loc(v); if (r) toast('Done', 'success'); else toast(VEHFAIL[v] || 'Could not do that', 'error'); };
A.qPlate = async () => { const f = await form({ title: 'Change plate', icon: 'fas fa-rectangle-list', cols: 1, fields: [{ name: 'plate', label: 'Plate', max: 8 }] }); if (f && await loc('vehPlate', f)) toast('Plate changed', 'success'); };
A.qReviveR = () => A.reviveRadius();
A.qAnnounce = () => { S.tab.world = 'announce'; A.openPanel('world'); };
A.qFocusPlayer = () => { const i = $('#q-pid'); if (i) { i.focus(); i.select(); } };
A.qFocusVeh = () => { const i = $('#q-veh'); if (i) { i.focus(); i.select(); } };
IN.qPid = v => { S.qpid = v; };
function qPid() { const i = $('#q-pid'); const id = parseInt(i && i.value, 10); if (!id || id < 1) { toast('Enter a server ID', 'error'); if (i) i.focus(); return null; } S.qpid = id; return id; }
A.qPlayer = async v => {
  const id = qPid(); if (!id) return;
  if (v === 'goto') { if (await call('player:goto', { id })) A.close(); }
  else if (v === 'bring') call('player:bring', { id }, 'Player brought');
  else if (v === 'spectate') { if (await call('player:spectate', { id })) hideUI(); }
  else if (v === 'revive' || v === 'heal' || v === 'freeze') call('player:action', { id, action: v }, v === 'freeze' ? 'Freeze toggled' : v === 'heal' ? 'Healed' : 'Revived');
};
A.qPlayerProfile = () => { const id = qPid(); if (!id || !can('self.panel')) return; A.openPanel('players'); openProfile(id); };

/* ─── rebinding quick menu keys (Settings) ─────────────────────────────── */
const RESERVED = ['ESCAPE', 'ENTER', 'TAB', 'SHIFT', 'CONTROL', 'ALT', 'META', 'CAPSLOCK', '?', '/'];
function rebindKey(e) {
  e.preventDefault(); e.stopPropagation();
  const id = S.rebind; S.rebind = null;
  const k = keyNorm(evKey(e));
  if (k === 'ESCAPE') return rerender();
  const keys = Object.assign({}, S.settings.qkeys || {});
  if (k === 'BACKSPACE' || k === 'DELETE') keys[id] = '';
  else if (RESERVED.includes(k)) { toast('That key is used by the menu', 'error'); return rerender(); }
  else {
    const cur = qkeys();
    Object.keys(cur).forEach(o => { if (o !== id && keyNorm(cur[o]) === k) keys[o] = ''; }); // one action per key
    keys[id] = k;
  }
  S.settings.qkeys = keys; saveSettings(); rerender();
}
A.qkRebind = v => { S.rebind = v; const b = $(`[data-a="qkRebind"][data-v="${v}"]`); if (b) { b.classList.add('active'); b.innerHTML = '<i class="fas fa-keyboard"></i>Press a key'; } };
A.qkReset = async () => { if (!await confirmBox('Reset quick menu keys?', 'Every quick menu key goes back to its default.', { tone: '', okClass: 'btn-teal', ok: 'Reset', icon: 'fas fa-rotate-left' })) return; S.settings.qkeys = null; saveSettings(); rerender(); };

/* ═══ PLAYER REPORT WINDOW ══════════════════════════════════════════════ */
function reportHtml() {
  const R = S.rep || {};
  const list = R.reports || [];
  const cur = list.find(r => r.id === R.cur);
  let body;
  if (!S.rep) body = loading();
  else if (cur) body = `<div class="prof-h" style="padding:12px 16px"><div class="av"><i class="fas fa-flag"></i></div><div class="tx"><h2 style="font-size:13.5px">#${cur.id} · ${esc(cur.label)}</h2><p><span>${esc(cur.category)}</span><span>${cur.claimed_name ? `<b class="tteal">${esc(cur.claimed_name)}</b> is helping you` : 'Waiting for staff'}</span></p></div>
      <div class="r">${btn('Close report', 'repMineClose', 'sm btn-red', { icon: 'fas fa-check' })}</div></div>
    <div class="chat" id="chat">${msgsHtml(cur.messages)}</div>
    <div class="composer"><input class="inp" id="rep-mine-in" placeholder="Add more details" data-enter="repMineSend" maxlength="${R.max || 500}">${btn('Send', 'repMineSend', 'btn-teal', { icon: 'fas fa-paper-plane' })}</div>`;
  else body = `<div class="content" style="padding:18px"><div class="fgrid" style="grid-template-columns:1fr">
      <p class="ink2" style="line-height:1.6;font-size:12px">Tell staff what is going on. You can keep chatting here until it is sorted.</p>
      <div class="field"><label>Category</label><select class="sel" id="rp-cat">${(R.categories || ['General']).map(c => `<option>${esc(c)}</option>`).join('')}</select></div>
      <div class="field"><label>Title <small>optional</small></label><input class="inp" id="rp-title" maxlength="60" placeholder="Short summary"></div>
      <div class="field"><label>What happened <small id="rp-count">0 / ${R.max || 500}</small></label><textarea class="txt" id="rp-msg" style="min-height:150px" maxlength="${R.max || 500}" data-in="rpCount" placeholder="Include player IDs and where it happened if you can"></textarea></div>
      ${btn('Send report', 'repCreate', 'btn-teal full', { icon: 'fas fa-paper-plane' })}</div></div>`;
  const tabsHtml = list.length ? `<div class="tabs">${list.map(r => `<button class="${R.cur === r.id ? 'on' : ''}" data-a="repMineTab" data-v="${r.id}"><i class="fas fa-flag"></i>#${r.id}</button>`).join('')}<button class="${!cur ? 'on' : ''}" data-a="repMineTab" data-v=""><i class="fas fa-plus"></i>New</button></div>` : '';
  return `<div class="stage"><div class="frame rwin"><div class="shell">
    <div class="bar" style="padding-right:10px"><div class="bar-brand" style="width:auto;border-right:0"><div class="mark"></div><div class="bar-title"><b>Help and reports</b><span>Talk to staff</span></div></div><span style="flex:1"></span><span class="ver">v${esc(S.cfg.version)}</span><button class="pill-close" data-a="close">Close</button></div>
    ${tabsHtml}<div style="flex:1;display:flex;flex-direction:column;min-height:0">${body}</div>
    <div class="statusbar"><span><span class="key">ESC</span>Close</span><span class="sp"></span></div></div></div></div>`;
}
async function loadMyReports(keepCur) {
  const r = await rpc('report:mine');
  if (!r.ok) { toast(r.err, 'error'); return; }
  const cur = keepCur && S.rep ? S.rep.cur : null;
  S.rep = r.data;
  S.rep.cur = cur && r.data.reports.some(x => x.id === cur) ? cur : (r.data.reports[0] ? r.data.reports[0].id : null);
  if (S.mode === 'report') { renderApp(); const c = $('#chat'); if (c) c.scrollTop = c.scrollHeight; }
}
IN.rpCount = v => { const c = $('#rp-count'); if (c) c.textContent = `${v.length} / ${S.rep.max || 500}`; };
A.repMineTab = v => { S.rep.cur = v ? +v : null; renderApp(); const c = $('#chat'); if (c) c.scrollTop = c.scrollHeight; };
A.repCreate = async () => { const d = { category: $('#rp-cat').value, title: $('#rp-title').value, message: $('#rp-msg').value }; const id = await call('report:create', d, 'Report sent to staff'); if (id) { S.rep.cur = id; loadMyReports(true); } };
A.repMineSend = async () => { const i = $('#rep-mine-in'); if (!i.value.trim()) return; const text = i.value; i.value = ''; const m = await call('report:send', { id: S.rep.cur, message: text }); if (m) { const cur = S.rep.reports.find(r => r.id === S.rep.cur); if (cur) addMessage(cur, m); } };
A.repMineClose = async () => { if (!await confirmBox('Close this report?', 'Only do this if your issue is sorted.', { tone: '', okClass: 'btn-teal', ok: 'Close report', icon: 'fas fa-check' })) return; if (await call('report:close_mine', { id: S.rep.cur }, 'Report closed')) { S.rep.cur = null; loadMyReports(); } };

/* ═══ OVERLAYS ══════════════════════════════════════════════════════════ */
const OV = { annQ: [], annBusy: false, jail: null, jailTimer: null };
function ov(id, html) { let el = document.getElementById(id); if (!el) { el = document.createElement('div'); el.id = id; $('#hud').appendChild(el); } el.innerHTML = html || ''; return el; }

function showAnnouncement(p) { OV.annQ.push(p); if (!OV.annBusy) nextAnn(); }
function nextAnn() {
  const p = OV.annQ.shift(); if (!p) { OV.annBusy = false; ov('ov-ann', ''); return; }
  OV.annBusy = true;
  const k = p.kind || 'info';
  const icon = { info: 'fas fa-bullhorn', success: 'fas fa-circle-check', warning: 'fas fa-triangle-exclamation', error: 'fas fa-circle-exclamation' }[k] || 'fas fa-bullhorn';
  const secs = Math.max(3, p.seconds || 8);
  ov('ov-ann', `<div class="frame ann ${k}"><div class="shell"><div class="ann-b"><div class="ic"><i class="${icon}"></i></div><div><h4>${esc(p.title || 'Announcement')}</h4><p>${esc(p.message)}</p>${p.sender ? `<small>${esc(p.sender)}</small>` : ''}</div></div><div class="prog" style="animation-duration:${secs}s"></div></div></div>`);
  sound(k === 'error' || k === 'warning' ? 'alert' : 'ping');
  setTimeout(nextAnn, secs * 1000 + 250);
}

function showWarned(p) {
  clearInterval(OV.warnT);
  let left = p.seconds || 10;
  const draw = () => ov('ov-warn', `<div class="warnscr"><div class="frame"><div class="shell"><div class="wb"><div class="ic"><i class="fas fa-triangle-exclamation"></i></div>
    <h2>You have been warned</h2><p>A staff member issued you a formal warning. Read it and keep it in mind.</p>
    <div class="reason">${esc(p.reason)}</div>
    ${p.max > 0 ? `<div class="cnt">${Array.from({ length: p.max }, (_, i) => `<i class="${i < p.count ? 'on' : ''}"></i>`).join('')}</div>` : ''}
    <p style="font-size:11.5px;margin-top:8px">${p.max > 0 ? `Warning ${p.count} of ${p.max}${p.count >= p.max ? ' · this results in a ban' : ''}` : `Warning ${p.count} on record`} · issued by ${esc(p.staff)}</p>
    <div class="timer">This closes in ${left}s</div></div></div></div></div>`);
  draw(); sound('alert');
  OV.warnT = setInterval(() => { left--; if (left <= 0) { clearInterval(OV.warnT); ov('ov-warn', ''); } else draw(); }, 1000);
}

function showStaffMessage(p) {
  ov('ov-smsg', `<div class="frame smsg"><div class="shell"><div class="ann-b"><div class="ic"><i class="fas fa-user-shield"></i></div><div><h4>Message from staff</h4><p>${esc(p.message)}</p><small>${esc(p.from)}</small></div></div><div class="prog" style="animation-duration:9s"></div></div></div>`);
  sound('ping');
  clearTimeout(OV.smsgT); OV.smsgT = setTimeout(() => ov('ov-smsg', ''), 9000);
}

function showJail(info) {
  clearInterval(OV.jailTimer);
  if (!info) { OV.jail = null; ov('ov-jail', ''); return; }
  OV.jail = { remaining: info.remaining, reason: info.reason };
  const draw = () => ov('ov-jail', `<div class="chipbox jailchip"><i class="fas fa-lock"></i><b>Jailed</b><span class="sepv"></span><span>${dur(OV.jail.remaining)} left</span><span class="sepv"></span><span class="muted ell" style="max-width:260px">${esc(OV.jail.reason)}</span></div>`);
  draw();
  OV.jailTimer = setInterval(() => { OV.jail.remaining = Math.max(0, OV.jail.remaining - 1); draw(); }, 1000);
}

function showCoords(c) {
  if (!c) return ov('ov-coords', '');
  ov('ov-coords', `<div class="chipbox pos-${esc(c.pos || S.settings.coordsPos)}"><i class="fas fa-crosshairs"></i><span class="mono"><b>${c.x.toFixed(2)}</b>, <b>${c.y.toFixed(2)}</b>, <b>${c.z.toFixed(2)}</b></span><span class="sepv"></span><span class="mono">H ${c.h.toFixed(1)}</span>${c.street ? `<span class="sepv"></span><span class="muted">${esc(c.street)}</span>` : ''}</div>`);
}

function showNoclip(d) {
  if (!d || !d.on) return ov('ov-noclip', '');
  const dots = Array.from({ length: 6 }, (_, i) => `<i style="width:5px;height:12px;border-radius:2px;display:inline-block;background:${i < d.speed ? 'var(--teal)' : 'var(--raise-2)'}"></i>`).join('');
  ov('ov-noclip', `<div class="chipbox pos-${esc(d.pos || S.settings.noclipPos)}"><i class="fas fa-feather"></i><b>Noclip</b><span class="sepv"></span><span style="display:flex;gap:3px">${dots}</span><span class="sepv"></span>
    <span class="hints"><span><span class="key">W A S D</span>Move</span><span><span class="key">Q</span><span class="key">E</span>Up / down</span><span><span class="key">Scroll</span>Speed</span><span><span class="key">Shift</span>Fast</span></span></div>`);
}

function showSpectate(d) {
  if (!d) return ov('ov-spec', '');
  ov('ov-spec', `<div class="chipbox spec"><i class="fas fa-eye"></i><b>${esc(d.name || '')}</b><span class="muted">#${d.id}</span>
    ${d.health !== undefined ? `<span class="sepv"></span>${hpBar(d.health + 100, d.armour)}` : ''}<span class="sepv"></span>
    <span class="hints"><span><span class="key">&larr;</span><span class="key">&rarr;</span>Switch</span><span><span class="key">Backspace</span>Stop</span></span></div>`);
}

function showInspector(d) {
  if (!d) return ov('ov-insp', '');
  if (d.none) return ov('ov-insp', `<div class="frame insp pos-right"><div class="shell"><div class="ib"><div class="row"><label>Aim at an entity</label><span>${d.coords ? `${d.coords.x}, ${d.coords.y}, ${d.coords.z}` : '-'}</span></div></div></div></div>`);
  const rows = [['Type', d.type], ['Model', d.name || d.model], ['Hash', d.model], ['Handle', d.handle], ['Net ID', d.netId ?? 'local'], ['Owner', d.owner ?? '-'], ['Coords', `${d.coords.x}, ${d.coords.y}, ${d.coords.z}`], ['Heading', d.coords.w], ['Rotation', `${d.rotation.x}, ${d.rotation.y}, ${d.rotation.z}`], ['Health', `${d.health} / ${d.maxHealth}`], ['Distance', d.distance + 'm'], ['Frozen', d.frozen ? 'yes' : 'no'], ['Mission', d.mission ? 'yes' : 'no']];
  if (d.plate) rows.push(['Plate', d.plate], ['Engine', d.engine]);
  if (d.driver) rows.push(['Driver ID', d.driver]);
  if (d.player) rows.push(['Player', `${d.player.name} (${d.player.id})`]);
  if (d.worldProp) rows.push(['Saved prop', '#' + d.worldProp]);
  ov('ov-insp', `<div class="frame insp pos-right"><div class="shell"><div class="card-h"><h3><i class="fas fa-magnifying-glass-location"></i>Entity inspector</h3></div><div class="ib">${rows.map(([l, v]) => `<div class="row"><label>${esc(l)}</label><span>${esc(v)}</span></div>`).join('')}</div></div></div>`);
}

function showToolHint(d) {
  if (!d) return ov('ov-hint', '');
  ov('ov-hint', `<div class="chipbox pos-bottom-center"><i class="fas fa-screwdriver-wrench"></i><b>${esc(d.title)}</b><span class="sepv"></span><span class="hints">${d.keys.map(([k, l]) => `<span><span class="key">${esc(k)}</span>${esc(l)}</span>`).join('')}</span></div>`);
}

/* ═══ server pushes ═════════════════════════════════════════════════════ */
function handlePush(kind, d) {
  if (kind === 'log') {
    const st = S.d.logs;
    if (st && st.rows && (!st.cat || st.cat === 'all' || st.cat === d.category) && !st.q) {
      st.rows.unshift(Object.assign({ id: (st.rows[0] ? st.rows[0].id : 0) + 0.001 }, d));
      if (st.rows.length > 300) st.rows.pop();
      const body = $('#log-body'); if (body && S.page === 'logs') body.insertAdjacentHTML('afterbegin', logRow(d));
    }
  } else if (kind === 'chat:message') {
    const mine = d.staff && d.author === S.me.name;
    d.mine = mine;
    const rep = S.d.reports && S.d.reports.cur, room = S.d.chats && S.d.chats.cur;
    const isRoom = S.d.chats && S.d.chats.rooms && S.d.chats.rooms.some(r => r.id === d.chat);
    if (rep && rep.chat.id === d.chat && S.page === 'reports' && S.open) addMessage(rep, d);
    else if (room && room.chat.id === d.chat && S.page === 'chats' && S.open) addMessage(room, d);
    else if (isRoom && !mine) { const r = S.d.chats.rooms.find(x => x.id === d.chat); r.unread = (r.unread || 0) + 1; r.last = d.message; S.badges.chats++; refreshNav(); if (S.page === 'chats') rerender(); }
    else if (!isRoom && S.page === 'reports' && S.open) loadReports();
    if (!mine) sound('soft');
  } else if (kind === 'report:new') {
    S.badges.reports++; refreshNav(); sound('alert');
    if (S.open) toast(`${d.player}: ${String(d.message).slice(0, 70)}`, 'warning', `Report #${d.id}`);
    if (S.page === 'reports') loadReports();
  } else if (kind === 'report:update') {
    if (S.d.reports) { if (S.page === 'reports' && S.open) { loadReports(); const c = S.d.reports.cur; if (c && c.chat.id === d.id) { c.chat.status = d.status; c.chat.claimed_name = d.claimed || null; rerender(); } } else if (d.status !== 'open') S.badges.reports = Math.max(0, S.badges.reports - 1); refreshNav(); }
  } else if (kind === 'chats:changed') { if (S.page === 'chats' && S.open) loadRooms(); }
  else if (kind === 'console') consolePush(d);
  else if (kind === 'dev:result') devOut(`[client ${d.from}] ${d.result}`);
  else if (kind === 'staffchat') { if (S.open) toast(d.message, 'info', `Staff · ${d.from}`); sound('soft'); }
  else if (kind === 'screenshot') {
    S.lastShot = d;
    if (S.open && S.mode === 'panel') showShot(d);
    else toast('Screenshot ready, open the panel to see it', 'info');
  }
}
function showShot(d) {
  S.lastShot = null;
  infoBox(`Screenshot · ${d.name}`, `<img class="shotimg" src="${d.image}"><div class="row-btns" style="margin-top:8px"><span class="muted">${date(d.time, true)} · ID ${d.id}</span></div>`, { icon: 'fas fa-camera', size: 'xl' });
}

/* ═══ open / NUI messages ═══════════════════════════════════════════════ */
async function openUI(d) {
  if (d.settings) S.settings = Object.assign(S.settings, d.settings);
  if (d.toggles) S.toggles = d.toggles;
  if (d.me) S.me = d.me;
  if (d.teleports) S.teleports = d.teleports;
  if (d.keys) S.keys = d.keys;
  if (d.binds) S.binds = d.binds;
  S.rebind = null;
  S.open = true; S.mode = d.mode; S.openedAt = Date.now();
  if (d.mode === 'report') { S.rep = null; renderApp(); return loadMyReports(); }
  if (!S.boot) { $('#app').innerHTML = `<div class="stage">${loading()}</div>`; const r = await rpc('boot'); if (!r.ok) { toast(r.err || 'Could not load', 'error'); return A.close(); } S.boot = r.data; if (r.data.version) S.cfg.version = r.data.version; }
  if (d.mode === 'quick') { if (PAGES[S.page] && PAGES[S.page].leave) PAGES[S.page].leave(); return renderApp(); }
  const extra = d.extra || {};
  const pageKey = d.page || (S.page && S.opened ? S.page : S.settings.startPage) || 'dashboard';
  S.opened = true;
  S.page = PAGES[pageKey] && pageAllowed(PAGES[pageKey]) ? pageKey : (Object.values(PAGES).find(pageAllowed) || PAGES.settings).key;
  renderApp();
  const p = PAGES[S.page]; if (p.enter) p.enter(extra);
  if (extra.palette) openPalette();
  if (S.lastShot) showShot(S.lastShot);
  if (can('reports.view') && !S.d.reports) rpc('reports:list', { status: 'active' }).then(r => { if (r.ok) { S.badges.reports = r.data.filter(x => x.status !== 'claimed').length; refreshNav(); } });
}

window.addEventListener('message', e => {
  const { type, data } = e.data || {};
  switch (type) {
    case 'config': S.cfg = Object.assign(S.cfg, data || {}); if (data && data.accent) document.documentElement.style.setProperty('--teal', data.accent); break;
    case 'staff': S.me = data || { isStaff: false }; if (S.open && S.mode !== 'report' && !S.me.isStaff) hideUI(); { const du = $('.duty'); if (du) { du.classList.toggle('on', !!S.me.duty); du.innerHTML = `<span class="dot"></span>${S.me.duty ? 'On duty' : 'Off duty'}`; } } break;
    case 'open': openUI(data || {}); break;
    case 'close': if (PAGES[S.page] && PAGES[S.page].leave) PAGES[S.page].leave(); closeModal(null); closePalette(); hideUI(); break;
    case 'toggles': S.toggles = data || {}; if (S.mode === 'quick') refreshQuick(); else if (S.open && S.page === 'world') rerender(); break;
    case 'push': handlePush(data.kind, data.data); break;
    case 'announce': showAnnouncement(data); break;
    case 'warned': showWarned(data); break;
    case 'staffMessage': showStaffMessage(data); break;
    case 'report':
      if (!S.rep) break;
      if (data.kind === 'message') { const cur = S.rep.reports.find(r => r.id === data.data.chat); if (cur) { if (S.mode === 'report') addMessage(cur, data.data); else cur.messages.push(data.data); sound('ping'); } }
      if (data.kind === 'closed') { S.rep.reports = S.rep.reports.filter(r => r.id !== data.data.id); if (S.rep.cur === data.data.id) S.rep.cur = S.rep.reports[0] ? S.rep.reports[0].id : null; if (S.mode === 'report') renderApp(); }
      break;
    case 'noclip': showNoclip(data); break;
    case 'coords': showCoords(data); break;
    case 'jail': showJail(data); break;
    case 'spectate': showSpectate(data); break;
    case 'inspector': showInspector(data); break;
    case 'toolHint': showToolHint(data); break;
  }
});
