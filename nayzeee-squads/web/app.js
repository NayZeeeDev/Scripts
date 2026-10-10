/* nayzeee-squads · NUI · NAYZEEE UI v5 */
(() => {
'use strict';

const IS_GAME = typeof GetParentResourceName === 'function';
const RES = IS_GAME ? GetParentResourceName() : 'nayzeee-squads';
const $ = (s, r = document) => r.querySelector(s);

const state = {
  cfg: null, me: 0, settings: {}, squad: null, chat: [], profile: null,
  list: null, invites: [], myRequests: [], status: null, open: false,
  view: 'browse', preview: null, search: '', browseFilter: 'all', memberFilter: 'all',
  unread: 0, talking: {}, hudHidden: false, editingHud: false, hudPrevPos: null, selfVitals: null,
  nameCheck: { value: '', ok: null, msg: '' }, form: null, ranksDraft: null,
  stats: null, statsSort: 'kills', board: null, boardTab: 'squads', boardSort: 'elo',
  admin: null, adminOpen: null, isAdmin: false,
  prompt: null, readyAnswers: null, modalClose: null,
};

// ─── utils ─────────────────────────────────────────────────
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const initials = (n) => String(n || '?').trim().split(/\s+/).slice(0, 2).map((p) => p[0]).join('').toUpperCase();
const safeImg = (u) => (typeof u === 'string' && (/^https:\/\/[^\s"'<>]+$/.test(u) || /^data:image\/(png|gif|webp|jpeg);base64,[A-Za-z0-9+/=]+$/.test(u)) ? u : null);
const pickImg = (img) => (img && typeof img === 'object' ? (state.settings.animatedAvatars && img.anim) || img.static : img);
const avatar = (name, img, cls = '') => {
  const src = safeImg(pickImg(img));
  const ini = esc(initials(name));
  return src
    ? `<div class="av ${cls}" data-i="${ini}"><img src="${esc(src)}" alt="" loading="lazy" draggable="false" onerror="this.parentNode.textContent=this.parentNode.dataset.i"></div>`
    : `<div class="av ${cls}">${ini}</div>`;
};
const pad = (n) => String(n).padStart(2, '0');
const clock = (t) => { const d = new Date(t * 1000); return `${pad(d.getHours())}:${pad(d.getMinutes())}`; };
const since = (t) => {
  const s = Math.max(0, Math.floor(Date.now() / 1000 - t));
  if (s < 60) return 'just now';
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m`;
  return `${Math.floor(s / 86400)}d`;
};
const ago = (t) => { const s = since(t); return s === 'just now' ? s : `${s} ago`; };
const dur = (sec) => {
  sec = Math.max(0, Math.floor(sec || 0));
  if (sec < 60) return `${sec}s`;
  if (sec < 3600) return `${Math.floor(sec / 60)}m`;
  const h = Math.floor(sec / 3600);
  return h >= 100 ? `${h}h` : `${h}h ${Math.floor((sec % 3600) / 60)}m`;
};
const debounce = (fn, ms) => { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; };
const ratio = (k, d) => (d > 0 ? (k / d).toFixed(2) : Number(k || 0).toFixed(2));
const pct = (w, l) => { const g = (w || 0) + (l || 0); return g ? Math.round((w / g) * 100) : 0; };
const vit = (id) => (state.squad && state.squad.vitals && state.squad.vitals[String(id)]) || null;
const isDown = (m) => m.downed || (vit(m.id) && vit(m.id).h === 0);
const can = (perm) => !!(state.squad && state.squad.you && state.squad.you.perms && state.squad.you.perms[perm]);
const isOwner = () => !!(state.squad && state.squad.members.some((m) => m.id === state.me && m.owner));
const online = () => (state.squad ? state.squad.members.filter((m) => m.online) : []);
const myMember = () => (state.squad ? state.squad.members.find((m) => m.id === state.me) : null);
const tierOf = (t) => t || { name: 'Bronze', color: '#b4713d' };
const blipHex = (id) => (state.cfg && state.cfg.blipHex && state.cfg.blipHex[String(id)]) || '#ffffff';
const feature = (k) => !!(state.cfg && state.cfg.features && state.cfg.features[k]);

const kdaHtml = (m, withRevives) => `<span class="kda"><b class="k">${m.kills || 0}</b><s>/</s><b class="d">${m.deaths || 0}</b><s>/</s><b class="a">${m.assists || 0}</b>${
  withRevives && m.revives ? `<s>·</s><b class="r">${m.revives}<i class="fa-solid fa-kit-medical" style="font-size:8px;margin-left:2px"></i></b>` : ''}</span>`;

const tierBadge = (tier, extra = '') => {
  const t = tierOf(tier);
  return `<span class="tier" style="--tier:${esc(t.color)}"><i class="fa-solid fa-shield-halved"></i>${esc(t.name)}${extra}</span>`;
};
const tagChip = (tag) => (tag ? ` <span class="chip squad">${esc(tag)}</span>` : '');
const skeleton = (n, w = 52) => Array.from({ length: n }, () => `<div class="skel"><div class="sk circ"></div><div style="flex:1"><div class="sk" style="height:9px;width:${w}%"></div><div class="sk" style="height:7px;width:${Math.round(w * 0.6)}%;margin-top:7px"></div></div></div>`).join('');
const emptyBox = (icon, title, text, extra = '') => `<div class="empty"><i class="fa-solid ${icon}"></i><b>${title}</b><span>${text}</span>${extra}</div>`;
const nowClock = () => {
  const d = new Date();
  const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  return `<div class="clock"><b>${pad(d.getHours())}:${pad(d.getMinutes())}</b><span>${days[d.getDay()]}, ${d.getDate()} ${months[d.getMonth()]}</span></div>`;
};

async function nui(name, data = {}) {
  if (!IS_GAME) return Dev.handle(name, data);
  try {
    const r = await fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data) });
    return await r.json();
  } catch { return null; }
}

// Every message the menu raises goes to ox_lib's notify through Lua. Nothing is drawn here.
function notify(text, kind = 'inform', icon) {
  if (!text) return;
  nui('notify', { text, kind, icon });
}

function result(r, okText) {
  if (r && r.ok) { if (r.msg || okText) notify(r.msg || okText, 'success'); return true; }
  notify((r && r.msg) || 'Try that again in a moment', 'error');
  return false;
}

// ─── modal ─────────────────────────────────────────────────
// Confirm, text input, or a pick list (options: [{ value, label, icon }]). Resolves false on cancel.
function confirmModal({ title, text, confirm, danger = true, icon, input, options }) {
  return new Promise((resolve) => {
    const m = $('#modal');
    let picked = options && options.length ? options[0].value : null;
    m.innerHTML = `<div class="modal">
      <div class="modal-b"><div class="m-icon ${danger ? '' : 'teal'}"><i class="fa-solid ${icon || (danger ? 'fa-triangle-exclamation' : 'fa-circle-question')}"></i></div>
      <div style="flex:1;min-width:0"><h4>${esc(title)}</h4><p>${esc(text)}</p>
      ${input ? `<div class="field"><input id="modalInput" placeholder="${esc(input.placeholder || '')}" value="${esc(input.value || '')}"${input.max ? ` maxlength="${input.max}"` : ''}${input.numeric ? ' inputmode="numeric"' : ''}></div>` : ''}
      ${options ? `<div class="opts">${options.map((o) => `<button class="opt ${o.value === picked ? 'on' : ''}" data-opt="${esc(o.value)}"><i class="fa-solid ${esc(o.icon || 'fa-chevron-right')}"></i>${esc(o.label)}</button>`).join('')}</div>` : ''}
      </div></div>
      <div class="modal-f"><button class="btn-line sm" data-m="0">Cancel</button><button class="${danger ? 'btn-red' : 'btn-teal'} sm" data-m="1">${esc(confirm)}</button></div></div>`;
    m.classList.remove('hidden');
    const done = (v) => {
      const val = input && $('#modalInput') ? $('#modalInput').value : null;
      m.classList.add('hidden'); m.innerHTML = ''; m.onclick = null; state.modalClose = null;
      if (!v) return resolve(false);
      if (options) return resolve(picked);
      resolve(input ? val : true);
    };
    state.modalClose = () => done(false);
    m.onclick = (e) => {
      const o = e.target.closest('[data-opt]');
      if (o) {
        picked = options.find((x) => String(x.value) === o.dataset.opt)?.value ?? picked;
        m.querySelectorAll('[data-opt]').forEach((b) => b.classList.toggle('on', b.dataset.opt === o.dataset.opt));
        return;
      }
      const b = e.target.closest('[data-m]');
      if (b) done(b.dataset.m === '1');
      else if (e.target === m) done(false);
    };
    setTimeout(() => {
      const field = input ? $('#modalInput') : $('[data-m="1"]', m);
      field?.focus();
      if (input && field) field.onkeydown = (e) => { if (e.key === 'Enter') done(true); };
    }, 20);
  });
}

// ─── chrome: sidebar, title bar, status bar ────────────────
function navFor() {
  const s = state.squad;
  const groups = [];
  if (s) {
    const temp = !!s.temporary;
    const allies = feature('Affiliations') && state.cfg.allyMax > 0 && !temp;
    const pending = (s.allyRequests || []).length + (s.requests || []).length;
    groups.push({ label: 'Squad', items: [
      ['squad', 'fa-table-cells-large', 'Overview', pending ? { n: pending, hot: true } : null],
      ['members', 'fa-users', 'Members', { n: `${online().length}/${s.members.length}` }],
      ['chat', 'fa-message', 'Chat', state.unread ? { n: state.unread > 99 ? '99+' : state.unread, hot: true } : null],
      ...(allies ? [['allies', 'fa-handshake', 'Allies', (s.allyRequests || []).length ? { n: s.allyRequests.length, hot: true } : null]] : []),
      ...(temp ? [] : [['stats', 'fa-chart-simple', 'Stats', null]]),
      ...(feature('ActivityLog') ? [['activity', 'fa-clock-rotate-left', 'Activity', null]] : []),
    ] });
    groups.push({ label: 'Server', items: [
      ['browse', 'fa-magnifying-glass', 'Browse squads', null],
      ...(feature('Leaderboard') ? [['board', 'fa-ranking-star', 'Leaderboard', null]] : []),
    ] });
  } else {
    groups.push({ label: 'Server', items: [
      ['browse', 'fa-magnifying-glass', 'Browse squads', state.invites.length ? { n: state.invites.length, hot: true } : null],
      ...(feature('Leaderboard') ? [['board', 'fa-ranking-star', 'Leaderboard', null]] : []),
      ['create', 'fa-plus', 'Create a squad', null],
    ] });
  }
  groups.push({ label: 'You', items: [['settings', 'fa-sliders', 'Settings', null]] });
  if (state.isAdmin) groups.push({ label: 'Staff', items: [['admin', 'fa-user-shield', 'Staff tools', state.admin ? { n: state.admin.length } : null]] });
  return groups;
}

const parentView = (v) => ({ preview: 'browse', edit: 'squad', ranks: 'squad' }[v] || v);
const allViews = () => navFor().flatMap((g) => g.items.map((i) => i[0]));

function renderSide() {
  const s = state.squad, p = state.profile || {};
  const me = myMember();
  const name = (me && me.name) || p.name || 'You';
  const who = `<div class="who">${avatar(name, (me && me.avatar) || p.avatar)}
    <div class="who-txt"><b>${esc(name)}</b><span>${s ? `${esc(me ? me.rankName : 'Member')} · ${esc(s.name)}` : 'Not in a squad'}</span></div></div>`;
  const shift = s
    ? `<div class="shift"><span>${s.tag ? `[${esc(s.tag)}] ` : ''}${esc(s.name)}</span>${s.temporary
        ? '<b class="off"><span class="dot amber"></span>Temporary</b>'
        : `<b><span class="dot"></span>${s.elo} ELO</b>`}</div>`
    : '<div class="shift"><span>No squad</span><b class="off"><span class="dot off"></span>Free agent</b></div>';
  const active = parentView(state.view);
  const nav = navFor().map((g) => `<div class="grp">${g.label}</div>${g.items.map(([id, ico, label, tally]) =>
    `<button class="nav ${active === id ? 'on' : ''}" data-tab="${id}"><i class="fa-solid ${ico}"></i>${label}${tally ? `<span class="tally ${tally.hot ? 'hot' : ''}">${tally.n}</span>` : ''}</button>`).join('')}`).join('');
  $('#side').innerHTML = who + shift + nav;
}

function renderBar() {
  const s = state.squad;
  const dot = $('#barDot');
  if (s) {
    const up = online().filter((m) => !isDown(m)).length;
    dot.className = up < online().length ? 'dot red' : 'dot';
    $('#barText').innerHTML = `<b>${esc(s.name)}</b> · ${up}/${online().length} up${s.rally ? ' · rally set' : ''}${s.ready ? ' · ready check running' : ''}`;
    $('#barSub').textContent = s.temporary ? 'Temporary squad' : `${tierOf(s.tier).name} · ${s.elo} ELO`;
  } else {
    const n = state.list ? state.list.length : 0;
    dot.className = n ? 'dot' : 'dot off';
    $('#barText').innerHTML = state.list ? `<b>${n}</b> squad${n === 1 ? '' : 's'} on the server` : 'Loading squads';
    $('#barSub').textContent = 'NayZeee';
  }
  const keys = state.view === 'chat' ? [['ESC', 'Close'], ['↵', 'Send'], ['TAB', 'Switch page']] : [['ESC', 'Close'], ['TAB', 'Switch page']];
  const c = state.cfg;
  $('#keys').innerHTML = keys.map(([k, l]) => `<span><span class="key">${k}</span>${l}</span>`).join('')
    + (c ? `<span class="fw">${c.commands && c.commands.Chat ? `<b>/${esc(c.commands.Chat)}</b> squad chat · ` : ''}<b>/${esc(c.command)}</b> opens this menu</span>` : '');
}

function renderChrome() { renderSide(); renderBar(); }

function go(view) {
  state.view = view;
  if (view === 'chat') state.unread = 0;
  render();
}

const after = {};

function render() {
  if (!state.cfg || !state.open) return;
  if (state.squad && ['create', 'preview'].includes(state.view)) state.view = 'squad';
  if (!state.squad && ['squad', 'members', 'chat', 'edit', 'ranks', 'stats', 'allies', 'activity'].includes(state.view)) state.view = 'browse';
  if (state.squad && state.squad.temporary && ['stats', 'allies'].includes(state.view)) state.view = 'squad';
  renderChrome();
  const views = {
    browse: viewBrowse, preview: viewPreview, board: viewBoard,
    create: () => viewForm(false), edit: () => viewForm(true),
    squad: viewOverview, members: viewMembers, ranks: viewRanks, chat: viewChat,
    stats: viewStats, allies: viewAllies, activity: viewActivity,
    settings: viewSettings, admin: viewAdmin,
  };
  $('#view').innerHTML = (views[state.view] || viewBrowse)();
  after[state.view]?.();
}

// ─── browse ────────────────────────────────────────────────
function squadRow(s) {
  const full = s.count >= s.limit;
  const requested = state.myRequests.includes(s.id);
  const status = requested ? '<span class="tag warn"><i class="fa-solid fa-hourglass-half"></i>Requested</span>'
    : s.inviteOnly ? '<span class="tag off"><i class="fa-solid fa-envelope"></i>Invite</span>'
    : s.locked ? '<span class="tag off"><i class="fa-solid fa-lock"></i>Locked</span>'
    : full ? '<span class="tag hot">Full</span>' : '<span class="tag live">Open</span>';
  const badge = s.temporary ? '<span class="tag warn"><i class="fa-solid fa-hourglass-half"></i>Temp</span>' : tierBadge(s.tier, ` ${s.elo}`);
  return `<div class="row click" data-preview="${s.id}">
    ${avatar(s.name, s.image)}
    <div class="row-txt"><b>${esc(s.name)}${tagChip(s.tag)}</b>
      <span><span class="bp-mini" style="background:${blipHex(s.blipColor)}"></span><i class="fa-solid fa-crown"></i>${esc(s.owner)} · ${s.online} online${s.description ? ` · ${esc(s.description)}` : ''}</span>
      <div class="bar-mini"><i style="width:${Math.round((s.count / s.limit) * 100)}%"></i></div></div>
    <div class="row-end">${badge}<span class="tally">${s.count}/${s.limit}</span>${status}</div>
  </div>`;
}

function viewBrowse() {
  const q = state.search.toLowerCase();
  const f = state.browseFilter;
  let body;
  if (!state.list) {
    body = skeleton(5);
  } else {
    const rows = state.list.filter((s) => {
      if (q && !(s.name.toLowerCase().includes(q) || s.owner.toLowerCase().includes(q) || (s.tag || '').toLowerCase().includes(q))) return false;
      if (f === 'open') return !s.inviteOnly && !s.locked && s.count < s.limit;
      if (f === 'perm') return !s.temporary;
      if (f === 'temp') return !!s.temporary;
      return true;
    });
    body = rows.length ? rows.map(squadRow).join('')
      : emptyBox('fa-users-slash', q || f !== 'all' ? 'No squads match' : 'No squads are running',
        q || f !== 'all' ? 'Clear the search or filter to see every squad.' : 'Start one and invite your people in.',
        q || f !== 'all' || state.squad ? '' : '<button class="btn-teal sm" data-tab="create"><i class="fa-solid fa-plus"></i>Create a squad</button>');
  }

  const invites = state.invites.length ? `<section class="panel">
    <div class="p-head"><div><h2>Invites</h2><p>Squads waiting on your answer</p></div><span class="tally hot">${state.invites.length}</span></div>
    <div class="p-body">${state.invites.map((i) => `<div class="row">${avatar(i.name, i.image, 'sm')}
      <div class="row-txt"><b>${esc(i.name)}${tagChip(i.tag)}</b><span>${esc(i.from || i.owner)} · ${i.count}/${i.limit}${i.temporary ? ' · temporary' : ''}</span></div>
      <div class="row-end">${i.temporary ? '' : tierBadge(i.tier)}<button class="btn-line sm" data-decline="${i.id}">Decline</button><button class="btn-teal sm" data-accept="${i.id}">Join</button></div></div>`).join('')}</div>
  </section>` : '';

  const mine = state.myRequests.map((id) => (state.list || []).find((s) => s.id === id)).filter(Boolean);
  const requests = mine.length ? `<section class="panel">
    <div class="p-head"><div><h2>Your requests</h2><p>Waiting on an officer to answer</p></div><span class="tally">${mine.length}</span></div>
    <div class="p-body">${mine.map((s) => `<div class="row">${avatar(s.name, s.image, 'sm')}
      <div class="row-txt"><b>${esc(s.name)}${tagChip(s.tag)}</b><span>${s.online} online · ${s.count}/${s.limit}</span></div>
      <div class="row-end"><button class="btn-line sm" data-cancelreq="${s.id}">Withdraw</button></div></div>`).join('')}</div>
  </section>` : '';

  const filters = [['all', 'All'], ['open', 'Open'], ['perm', 'Permanent'], ['temp', 'Temporary']];
  return `<div class="page">
    <div class="head"><div><h1>${state.squad ? 'Squads on the server' : 'Find a squad'}</h1><p>${state.squad ? 'See who else is running, and who you could ally with.' : 'Join an open crew, ask to join a locked one, or start your own.'}</p></div>${nowClock()}</div>
    <div class="cols wide-left">
      <div class="col">
        <div class="inline-form">
          <div class="input"><i class="fa-solid fa-magnifying-glass"></i><input id="search" placeholder="Search name, tag or owner" value="${esc(state.search)}" maxlength="24"></div>
          <button class="btn-ghost" data-act="refresh" style="height:34px"><i class="fa-solid fa-rotate-right"></i>Refresh</button>
        </div>
        <div class="seg">${filters.map(([k, l]) => `<button class="${f === k ? 'on' : ''}" data-bfilter="${k}">${l}</button>`).join('')}</div>
        <div class="p-body" style="padding:0" id="squadList">${body}</div>
      </div>
      <div class="col">
        ${invites || (state.squad ? '' : emptyBox('fa-envelope-open', 'No invites waiting', 'When someone invites you to their squad it shows up here.'))}
        ${requests}
        <section class="panel"><div class="p-head"><div><h2>How squads work</h2><p>The short version</p></div></div>
          <div class="p-body pad" style="gap:9px">
            <div class="sw-line static"><div><b>Ranks are yours</b><span>Rename them and set what each one can do</span></div><i class="fa-solid fa-list-ol" style="color:var(--teal)"></i></div>
            <div class="divider"></div>
            <div class="sw-line static"><div><b>Fights are rated</b><span>Beating another squad moves both ratings</span></div><i class="fa-solid fa-ranking-star" style="color:var(--teal)"></i></div>
            <div class="divider"></div>
            <div class="sw-line static"><div><b>Locked squad?</b><span>Ask to join and an officer gets your request</span></div><i class="fa-solid fa-user-plus" style="color:var(--teal)"></i></div>
            <div class="divider"></div>
            <div class="sw-line static"><div><b>Pick each other up</b><span>Revive squadmates with your medical items</span></div><i class="fa-solid fa-kit-medical" style="color:var(--teal)"></i></div>
          </div></section>
      </div>
    </div>
  </div>
  ${state.squad ? '' : '<div class="foot"><button class="btn-teal" data-tab="create"><i class="fa-solid fa-plus"></i>Create squad</button></div>'}`;
}
after.browse = () => {
  const s = $('#search');
  if (s) s.oninput = debounce(() => { state.search = s.value; const pos = s.selectionStart; render(); const n = $('#search'); n.focus(); n.setSelectionRange(pos, pos); }, 180);
};

// ─── preview ───────────────────────────────────────────────
function viewPreview() {
  const s = state.list && state.list.find((x) => x.id === state.preview);
  if (!s) { state.view = 'browse'; return viewBrowse(); }
  const invited = state.invites.some((i) => i.id === s.id);
  const requested = state.myRequests.includes(s.id);
  const full = s.count >= s.limit;
  const blocked = full || (s.inviteOnly && !invited);
  const needPass = s.locked && !invited;
  const canAsk = s.canRequest && !invited && !full && state.cfg.requests.enabled;
  return `<div class="page">
    <div><button class="btn-ghost" data-tab="browse"><i class="fa-solid fa-arrow-left"></i>Back to squads</button></div>
    <div class="hero" style="--tier:${esc(s.temporary ? '#9aa4ab' : tierOf(s.tier).color)}">${avatar(s.name, s.image, 'lg')}
      <div class="hero-txt"><h2>${esc(s.name)}${tagChip(s.tag)}</h2><p>Led by ${esc(s.owner)}${s.description ? ` · ${esc(s.description)}` : ''}</p>
        <div class="tags">${s.temporary ? '<span class="tag warn"><i class="fa-solid fa-hourglass-half"></i>Temporary</span>' : tierBadge(s.tier, ` ${s.elo}`)}<span class="tag live"><i class="fa-solid fa-users"></i>${s.count}/${s.limit}</span>
        ${s.locked ? '<span class="tag off"><i class="fa-solid fa-lock"></i>Password</span>' : ''}
        ${s.inviteOnly ? '<span class="tag off"><i class="fa-solid fa-envelope"></i>Invite only</span>' : ''}
        ${full ? '<span class="tag hot">Full</span>' : ''}${invited ? '<span class="tag live"><i class="fa-solid fa-envelope-open"></i>You are invited</span>' : ''}</div></div></div>
    <div class="stats">
      <div class="stat"><div class="tile"><i class="fa-solid fa-trophy"></i></div><div class="stat-txt"><span>Wins</span><b>${s.wins || 0}</b></div></div>
      <div class="stat"><div class="tile red"><i class="fa-solid fa-flag"></i></div><div class="stat-txt"><span>Losses</span><b>${s.losses || 0}</b></div></div>
      <div class="stat"><div class="tile blue"><i class="fa-solid fa-percent"></i></div><div class="stat-txt"><span>Win rate</span><b>${pct(s.wins, s.losses)}<small>%</small></b></div></div>
    </div>
    <div class="cols">
      <div class="col">
        ${needPass && !blocked ? `<section class="panel"><div class="p-head"><div><h2>Password</h2><p>This squad is locked</p></div></div>
          <div class="p-body pad"><div class="field"><div class="input"><i class="fa-solid fa-key"></i><input id="joinPass" type="password" maxlength="32" placeholder="Enter the password"></div></div></div></section>` : ''}
        <section class="panel"><div class="p-head"><div><h2>Record</h2><p>How they've done so far</p></div></div>
          <div class="p-body pad" style="gap:9px">
            <div class="sw-line static"><div><b>Rating</b></div><span class="muted">${s.temporary ? 'Not rated' : `${s.elo} ELO`}</span></div><div class="divider"></div>
            <div class="sw-line static"><div><b>Fights</b></div><span class="muted">${(s.wins || 0) + (s.losses || 0)}</span></div><div class="divider"></div>
            <div class="sw-line static"><div><b>Allies</b></div><span class="muted">${s.allies || 0}</span></div><div class="divider"></div>
            <div class="sw-line static"><div><b>Spots left</b></div><span class="muted">${Math.max(0, s.limit - s.count)}</span></div><div class="divider"></div>
            <div class="sw-line static"><div><b>Running since</b></div><span class="muted">${ago(s.created)}</span></div>
          </div></section>
      </div>
      <div class="col"><section class="panel">
        <div class="p-head"><div><h2>Members</h2><p>Who you'd be rolling with</p></div><span class="tally">${s.count}</span></div>
        <div class="p-body scroll">${s.members.map((n) => `<div class="row ${n.online ? '' : 'dim'}">${avatar(n.name, n.avatar, `sm ${n.online ? '' : 'off'}`)}
          <div class="row-txt"><b>${esc(n.name)}</b><span>${n.name === s.owner ? '<i class="fa-solid fa-crown"></i>Owner' : (n.online ? 'Online' : 'Offline')}</span></div></div>`).join('')}</div>
      </section></div>
    </div>
  </div>
  <div class="foot">
    ${canAsk && !requested ? `<button class="btn-line" data-askjoin="${s.id}"><i class="fa-solid fa-user-plus"></i>Ask to join</button>` : ''}
    ${requested ? `<button class="btn-line" data-cancelreq="${s.id}"><i class="fa-solid fa-xmark"></i>Withdraw request</button>` : ''}
    <button class="btn-teal" data-join="${s.id}" ${blocked ? 'disabled' : ''}>
    <i class="fa-solid fa-right-to-bracket"></i>${full ? 'Squad is full' : s.inviteOnly && !invited ? 'Invite only' : 'Join squad'}</button></div>`;
}
after.preview = () => { const p = $('#joinPass'); if (p) { p.focus(); p.onkeydown = (e) => { if (e.key === 'Enter') $('[data-join]')?.click(); }; } };

// ─── leaderboard ───────────────────────────────────────────
function viewBoard() {
  const b = state.board;
  const head = `<div class="head"><div><h1>Leaderboard</h1><p>Top squads by rating, and the players doing the most damage.</p></div>${nowClock()}</div>`;
  if (!b) return `<div class="page">${head}<div class="cols"><div class="col">${skeleton(5, 46)}</div><div class="col">${skeleton(5, 46)}</div></div></div>`;
  if (!b.persistent) return `<div class="page">${head}${emptyBox('fa-database', 'Stats are turned off', 'Rankings need persistence switched on in the config.')}</div>`;

  const sq = [...b.squads];
  const sqSort = { elo: (x, y) => y.elo - x.elo, wins: (x, y) => y.wins - x.wins || y.elo - x.elo, kd: (x, y) => ratio(y.kills, y.deaths) - ratio(x.kills, x.deaths) };
  const plSort = { kills: (x, y) => y.kills - x.kills || y.assists - x.assists, kd: (x, y) => ratio(y.kills, y.deaths) - ratio(x.kills, x.deaths), revives: (x, y) => (y.revives || 0) - (x.revives || 0), playtime: (x, y) => (y.playtime || 0) - (x.playtime || 0) };
  const isSq = state.boardTab === 'squads';
  const sort = isSq ? (sqSort[state.boardSort] || sqSort.elo) : (plSort[state.boardSort] || plSort.kills);
  const sqRows = sq.sort(sort).map((s, i) => `<div class="lb-row ${state.squad && state.squad.id === s.id ? 'me' : ''}">
      <span class="pos ${i < 3 ? `g${i + 1}` : ''}">${i + 1}</span>${avatar(s.name, s.image, 'sm')}
      <div class="row-txt"><b>${esc(s.name)}${tagChip(s.tag)}</b>
        <span>${s.wins}W ${s.losses}L${s.draws ? ` ${s.draws}D` : ''} · ${pct(s.wins, s.losses)}% · ${s.members} members${s.online ? ` · ${s.online} online` : ''}</span></div>
      <div class="lb-end"><b>${state.boardSort === 'kd' ? ratio(s.kills, s.deaths) : state.boardSort === 'wins' ? `${s.wins}W` : s.elo}</b>${tierBadge(s.tierInfo)}</div></div>`).join('');
  const plRows = [...b.players].sort(sort).map((p, i) => `<div class="lb-row">
      <span class="pos ${i < 3 ? `g${i + 1}` : ''}">${i + 1}</span>${avatar(p.name, p.image, 'sm')}
      <div class="row-txt"><b>${esc(p.name)}</b><span>${esc(p.squad)}${p.tag ? ` [${esc(p.tag)}]` : ''} ${kdaHtml(p, true)}</span></div>
      <div class="lb-end"><b>${state.boardSort === 'kd' ? ratio(p.kills, p.deaths) : state.boardSort === 'revives' ? p.revives || 0 : state.boardSort === 'playtime' ? dur(p.playtime) : p.kills}</b>
        <span>${state.boardSort === 'kd' ? 'K/D' : state.boardSort === 'revives' ? 'revives' : state.boardSort === 'playtime' ? 'played' : `${ratio(p.kills, p.deaths)} K/D`}</span></div></div>`).join('');

  const sorts = isSq ? [['elo', 'Rating'], ['wins', 'Wins'], ['kd', 'K/D']] : [['kills', 'Kills'], ['kd', 'K/D'], ['revives', 'Revives'], ['playtime', 'Playtime']];
  return `<div class="page">${head}
    <div class="cols wide-left" style="grid-template-columns:1fr 1fr">
      <div class="seg"><button class="${isSq ? 'on' : ''}" data-board="squads"><i class="fa-solid fa-users"></i> Squads</button><button class="${!isSq ? 'on' : ''}" data-board="players"><i class="fa-solid fa-user"></i> Players</button></div>
      <div class="seg">${sorts.map(([k, l]) => `<button class="${state.boardSort === k ? 'on' : ''}" data-bsort="${k}">${l}</button>`).join('')}</div>
    </div>
    <section class="panel">
      <div class="p-head"><div><h2>${isSq ? 'Squads' : 'Players'}</h2><p>${isSq ? 'Permanent squads with a rating' : 'Across every squad on the server'}</p></div><span class="tally">${isSq ? sq.length : b.players.length}</span></div>
      <div class="p-body scroll" style="max-height:none">${isSq
        ? (sqRows || emptyBox('fa-ranking-star', 'No ranked squads yet', 'Squads appear here once they fight another squad.'))
        : (plRows || emptyBox('fa-user-slash', 'No player stats yet', 'Kills, assists and revives show up here after the first squad fight.'))}</div>
    </section>
  </div>
  <div class="foot right"><button class="btn-line" data-act="refreshBoard"><i class="fa-solid fa-rotate-right"></i>Refresh</button></div>`;
}

// ─── create / edit ─────────────────────────────────────────
function viewForm(edit) {
  const c = state.cfg;
  if (!state.form || state.form.edit !== edit) {
    const s = edit ? state.squad : null;
    const types = c.squadTypes || { temporary: true, permanent: true, default: 'permanent' };
    state.form = {
      edit, name: s ? s.name : '', tag: (s && s.tag) || '', image: (s && s.image) || '', description: (s && s.description) || '',
      limit: s ? s.limit : Math.min(4, c.maxMembers), locked: s ? s.locked : false, password: '',
      inviteOnly: s ? s.inviteOnly : false,
      temporary: s ? !!s.temporary : (types.permanent && !(state.status && state.status.permanent === false) ? types.default === 'temporary' : true),
      blipColor: s && s.blipColor !== undefined ? s.blipColor : (c.squadBlipColors[0] ?? 2),
      blipSprite: s && s.blipSprite !== undefined ? s.blipSprite : 1,
    };
    state.nameCheck = { value: state.form.name, ok: edit ? true : null, msg: '' };
  }
  const f = state.form, nc = state.nameCheck;
  return `<div class="page">
    ${edit ? '<div><button class="btn-ghost" data-tab="squad"><i class="fa-solid fa-arrow-left"></i>Back to overview</button></div>' : ''}
    <div class="head"><div><h1>${edit ? 'Edit squad' : 'Create a squad'}</h1><p>${edit ? 'Changes apply for everyone right away.' : 'Pick a name and tag, set who can join, and you own it.'}</p></div>${nowClock()}</div>
    ${edit ? '' : typePicker(f)}
    <div class="cols"><div class="col">
    <section class="panel"><div class="p-head"><div><h2>Details</h2><p>Name, tag, blurb and size</p></div></div><div class="p-body pad">
      <div class="grid2">
        <div class="field"><label for="fName">Squad name</label>
          <input id="fName" maxlength="${c.nameMax}" placeholder="Name your squad" value="${esc(f.name)}" class="${nc.ok === true ? 'ok' : nc.ok === false ? 'bad' : ''}">
          <span class="hint ${nc.ok === true ? 'ok' : nc.ok === false ? 'bad' : ''}" id="fNameHint">${nc.ok === false ? esc(nc.msg) : nc.ok === true && !edit ? 'Name is available' : `${c.nameMin}–${c.nameMax} characters`}</span></div>
        <div class="field"><label for="fTag">Tag</label>
          <input id="fTag" maxlength="${c.tagMax}" placeholder="ABC" value="${esc(f.tag)}" style="text-transform:uppercase">
          <span class="hint">Shown over names</span></div>
      </div>
      <div class="field"><label for="fDesc">Short blurb <b class="slider-val" id="fDescCount">${f.description.length}/${c.descriptionMax}</b></label>
        <input id="fDesc" maxlength="${c.descriptionMax}" placeholder="What the squad is about (shown in the browser)" value="${esc(f.description)}"></div>
      <div class="field"><label for="fImage">Squad image</label>
        <div class="inline-form"><div id="fImgPrev">${avatar(f.name || '?', safeImg(f.image))}</div>
        <div class="input" style="flex:1"><i class="fa-solid fa-link"></i><input id="fImage" maxlength="300" placeholder="https:// image link (optional)" value="${esc(f.image)}"></div></div></div>
      <div class="field"><label>Member limit</label>
        <div class="stepper"><button data-step="-1" aria-label="Fewer"><i class="fa-solid fa-minus"></i></button><b id="fLimit">${f.limit}</b><button data-step="1" aria-label="More"><i class="fa-solid fa-plus"></i></button></div></div>
    </div></section>
    </div><div class="col">
    <section class="panel"><div class="p-head"><div><h2>Access</h2><p>Control who can get in</p></div></div><div class="p-body pad">
      <div class="sw-line" data-ftoggle="locked"><div><b>Password protected</b><span>Players need the password to join. They can still ask to join.</span></div><span class="sw ${f.locked ? 'on' : ''}"><i></i></span></div>
      ${f.locked ? `<div class="field"><div class="input"><i class="fa-solid fa-key"></i><input id="fPass" type="password" maxlength="32" placeholder="${edit && state.squad.locked ? 'Leave blank to keep the current password' : 'Set a password'}" value="${esc(f.password)}"></div></div>` : ''}
      <div class="divider"></div>
      <div class="sw-line" data-ftoggle="inviteOnly"><div><b>Invite only</b><span>Nobody joins without an invite or an accepted request</span></div><span class="sw ${f.inviteOnly ? 'on' : ''}"><i></i></span></div>
    </div></section>
    ${blipPicker(f)}
    </div></div>
  </div>
  <div class="foot"><button class="btn-teal" data-act="${edit ? 'saveEdit' : 'create'}" id="fSubmit"><i class="fa-solid ${edit ? 'fa-floppy-disk' : 'fa-plus'}"></i>${edit ? 'Save changes' : 'Create squad'}</button></div>`;
}

function typePicker(f) {
  const t = { ...(state.cfg.squadTypes || {}) };
  const st = state.status || { permanent: t.permanent };
  if (t.permanent && st.permanent === false) {
    if (!f.temporary) f.temporary = true;
    return `<div class="notice"><i class="fa-solid fa-triangle-exclamation"></i><div><b>Only temporary squads right now</b>
      <span>${esc(st.reason || 'Squads cannot be saved at the moment.')} This squad won't be rated or saved.</span></div></div>`;
  }
  if (!t.temporary || !t.permanent) {
    return t.temporary && !t.permanent
      ? `<div class="notice"><i class="fa-solid fa-hourglass-half"></i><div><b>Temporary squads only</b><span>This server doesn't save squads, so there's no rating or stat tracking.</span></div></div>`
      : '';
  }
  const opt = (temp, icon, title, lines) => `<button class="pick ${f.temporary === temp ? 'on' : ''}" data-ftype="${temp ? 1 : 0}">
    <span class="pick-i"><i class="fa-solid ${icon}"></i></span>
    <span class="pick-t"><b>${title}</b>${lines.map((l) => `<span>${l}</span>`).join('')}</span>
    <i class="fa-solid fa-circle-check pick-c"></i></button>`;
  return `<section class="panel"><div class="p-head"><div><h2>Squad type</h2><p>You pick this once — it can't be changed later</p></div></div>
    <div class="p-body pad"><div class="picks">
      ${opt(false, 'fa-shield-halved', 'Permanent crew', ['Saved between restarts, keeps its roster', 'Earns ELO and tracks K/D/A', 'Ranks, alliances, activity log and leaderboard place'])}
      ${opt(true, 'fa-hourglass-half', 'Temporary squad', ['For one session, nothing is saved', 'No rating and no stat tracking', t.tempHours > 0 ? `Closes after ${t.tempHours}h or when everyone leaves` : 'Closes when the last member leaves'])}
    </div></div></section>`;
}

function blipPicker(f) {
  if (!feature('SquadBlips')) return '';
  const sprites = state.cfg.blipSprites || [];
  return `<section class="panel"><div class="p-head"><div><h2>Map blip</h2><p>How your squad shows on everyone's map</p></div></div>
    <div class="p-body pad">
      <div class="field"><label>Blip colour</label>
        <div class="swatches">${state.cfg.squadBlipColors.map((id) => `<button class="swatch ${f.blipColor === id ? 'on' : ''}" style="background:${blipHex(id)}" data-fblip="${id}" aria-label="Colour ${id}"></button>`).join('')}</div></div>
      <div class="field"><label>Marker</label>
        <div class="icon-pick">${sprites.map((sp) => `<button class="${f.blipSprite === sp.id ? 'on' : ''}" data-fsprite="${sp.id}" title="${esc(sp.label)}"><i class="fa-solid ${esc(sp.icon)}"></i></button>`).join('')}</div></div>
      <div class="blip-preview">
        <span class="bp-dot" style="background:${blipHex(f.blipColor)};box-shadow:0 0 12px ${blipHex(f.blipColor)}"><i class="fa-solid ${esc((sprites.find((x) => x.id === f.blipSprite) || { icon: 'fa-circle' }).icon)}"></i></span>
        <div><b>${esc(f.name || 'Your squad')}</b><span>How squadmates see each other on the map</span></div>
      </div>
    </div></section>`;
}

const checkName = debounce(async (value) => {
  const r = await nui('checkName', { name: value });
  if (!state.form || state.form.name !== value) return;
  state.nameCheck = { value, ok: !!(r && r.ok), msg: (r && r.msg) || '' };
  paintNameHint();
}, 320);

function paintNameHint() {
  const input = $('#fName'), hint = $('#fNameHint');
  if (!input || !hint) return;
  const nc = state.nameCheck, c = state.cfg;
  input.className = nc.ok === true ? 'ok' : nc.ok === false ? 'bad' : '';
  hint.className = `hint ${input.className}`;
  hint.textContent = nc.ok === false ? nc.msg
    : nc.ok === true && !(state.form.edit && nc.value === state.squad.name) ? 'Name is available'
    : `${c.nameMin}–${c.nameMax} characters`;
}

function formAfter() {
  const f = state.form;
  $('#fName').oninput = (e) => {
    f.name = e.target.value;
    state.nameCheck = { value: f.name, ok: null, msg: '' };
    paintNameHint();
    if (f.name.trim().length >= state.cfg.nameMin) checkName(f.name);
    else if (f.name.length) { state.nameCheck = { value: f.name, ok: false, msg: `Use at least ${state.cfg.nameMin} characters` }; paintNameHint(); }
  };
  $('#fTag').oninput = (e) => { e.target.value = e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, ''); f.tag = e.target.value; };
  $('#fDesc').oninput = (e) => { f.description = e.target.value; $('#fDescCount').textContent = `${f.description.length}/${state.cfg.descriptionMax}`; };
  $('#fImage').oninput = debounce((e) => { f.image = e.target.value.trim(); $('#fImgPrev').innerHTML = avatar(f.name || '?', safeImg(f.image)); }, 250);
  const p = $('#fPass'); if (p) p.oninput = (e) => { f.password = e.target.value; };
}
after.create = formAfter;
after.edit = formAfter;

async function submitForm() {
  const f = state.form, c = state.cfg;
  if (state.nameCheck.ok === false) return notify(state.nameCheck.msg || 'Check the squad name', 'error');
  if (f.name.trim().length < c.nameMin) return notify(`Use at least ${c.nameMin} characters for the name`, 'error');
  if (f.tag && (f.tag.length < c.tagMin || f.tag.length > c.tagMax)) return notify(`Tags are ${c.tagMin} to ${c.tagMax} characters, or leave it blank`, 'error');
  if (f.locked && !f.password && !(f.edit && state.squad.locked)) return notify('Set a password or turn password protection off', 'error');

  const btn = $('#fSubmit'); btn.disabled = true;
  const payload = { name: f.name, tag: f.tag, image: f.image, description: f.description, limit: f.limit, inviteOnly: f.inviteOnly,
    password: f.locked ? f.password : '', blipColor: f.blipColor, blipSprite: f.blipSprite };
  if (!f.edit) payload.temporary = f.temporary;
  if (f.edit) payload.clearPassword = !f.locked;
  const r = await nui(f.edit ? 'edit' : 'create', payload);
  btn.disabled = false;
  if (result(r, f.edit ? 'Squad updated' : 'Squad created')) {
    state.form = null;
    if (f.edit) go('squad');
  }
}

// ─── overview ──────────────────────────────────────────────
const LOG_ICON = {
  create: ['fa-flag', ''], join: ['fa-user-plus', ''], leave: ['fa-user-minus', 'grey'], kick: ['fa-user-xmark', 'red'],
  rank: ['fa-arrow-up-right-dots', 'blue'], owner: ['fa-crown', 'amber'], ally: ['fa-handshake', ''], match: ['fa-crosshairs', 'amber'],
  motd: ['fa-message', ''], edit: ['fa-pen', 'grey'], request: ['fa-envelope', ''],
};
const logRow = (l) => {
  const [icon, cls] = LOG_ICON[l.kind] || ['fa-circle-info', 'grey'];
  return `<div class="log-row"><span class="log-i ${cls}"><i class="fa-solid ${icon}"></i></span>
    <div class="log-txt"><p>${esc(l.text)}</p><span>${ago(l.at)} · ${clock(l.at)}</span></div></div>`;
};

function memberRow(m, compact) {
  const v = vit(m.id), down = isDown(m), me = m.id === state.me;
  const hp = m.online && v ? v.h : 0;
  const acts = [];
  const nk = state.cfg.nicknames || {};
  const nickOk = nk.enabled && (!state.squad.temporary || nk.temp);
  if (!compact) {
    if (me && nickOk) acts.push(`<button class="icon-btn" title="${m.nick ? 'Change your nickname' : 'Set a nickname'}" data-nick="self"><i class="fa-solid fa-signature"></i></button>`);
    if (!me && m.nick && can('kick')) acts.push(`<button class="icon-btn" title="Reset their nickname" data-nickreset="${esc(m.identifier)}"><i class="fa-solid fa-eraser"></i></button>`);
    if (!me && !m.owner) {
      if (can('promote')) acts.push(`<button class="icon-btn" title="Change rank" data-rankmenu="${esc(m.identifier)}"><i class="fa-solid fa-arrow-up-right-dots"></i></button>`);
      if (isOwner()) acts.push(`<button class="icon-btn" title="Transfer ownership" data-transfer="${esc(m.identifier)}"><i class="fa-solid fa-crown"></i></button>`);
      if (can('kick')) acts.push(`<button class="icon-btn danger" title="Remove from squad" data-kick="${esc(m.identifier)}"><i class="fa-solid fa-user-minus"></i></button>`);
    }
  }
  const sub = m.online
    ? `<span class="rank ${m.owner ? 'owner' : ''}"><i class="fa-solid ${esc(m.rankIcon || 'fa-user')}"></i>${esc(m.rankName)}</span>${state.squad.temporary ? '' : kdaHtml(m, true)}${m.streak >= 3 ? `<span class="chip" style="color:var(--amber);border-color:var(--amber-edge);background:var(--amber-wash)">${m.streak} streak</span>` : ''}`
    : `<span class="rank ${m.owner ? 'owner' : ''}"><i class="fa-solid ${esc(m.rankIcon || 'fa-user')}"></i>${esc(m.rankName)}</span>${m.lastSeen ? `seen ${ago(m.lastSeen)}` : 'offline'}${!state.squad.temporary && m.playtime ? ` · ${dur(m.playtime)} played` : ''}`;
  return `<div class="row ${m.online ? '' : 'dim'}" data-member="${m.id || ''}">
    ${avatar(m.name, m.avatar, `${m.owner ? 'leader' : ''} ${m.online ? '' : 'off'}`)}
    <div class="row-txt"><b>${esc(m.name)}${m.nick && m.realName ? ` <span class="real-name" title="Character name">${esc(m.realName)}</span>` : ''}${me ? ' <span class="muted" style="font-size:11px">(you)</span>' : ''}</b>
      <span>${sub}</span>
      ${m.online && !compact ? `<div class="bar-mini"><i class="${hp <= 25 ? 'low' : ''}" style="width:${hp}%"></i></div>` : ''}</div>
    <div class="row-end">${down ? '<span class="tag hot">Down</span>' : m.online ? (compact ? '<span class="tag live">Online</span>' : '') : '<span class="tag off">Offline</span>'}${acts.join('')}</div>
  </div>`;
}

function requestsPanel(s) {
  const reqs = s.requests || [];
  if (!reqs.length || !can('invite')) return '';
  const full = s.members.length >= s.limit;
  return `<section class="panel">
    <div class="p-head"><div><h2>Join requests</h2><p>Players asking to get in</p></div><span class="tally hot">${reqs.length}</span></div>
    <div class="p-body">${reqs.map((r) => `<div class="row">${avatar(r.name, r.avatar, 'sm')}
      <div class="row-txt"><b>${esc(r.name)}<span class="muted" style="font-size:10.5px">#${r.id}</span></b><span>asked ${ago(r.at)} · expires in ${Math.max(0, Math.round(r.expires / 60))}m</span>${r.message ? `<p>“${esc(r.message)}”</p>` : ''}</div>
      <div class="row-end"><button class="btn-line sm" data-reqno="${esc(r.identifier)}">Decline</button><button class="btn-teal sm" data-reqyes="${esc(r.identifier)}" ${full ? 'disabled' : ''}>Accept</button></div></div>`).join('')}</div>
  </section>`;
}

function readyPanel(s) {
  const r = s.ready;
  if (!r) return '';
  const members = online();
  const mine = r.answers[String(state.me)];
  return `<section class="panel"><div class="p-head"><div><h2>Ready check</h2><p>${esc(r.by || 'Someone')} wants to know if the squad is good to go</p></div>
      ${mine === undefined ? `<div class="p-end"><button class="btn-line sm" data-ready="0"><i class="fa-solid fa-xmark"></i>Not yet</button><button class="btn-teal sm" data-ready="1"><i class="fa-solid fa-check"></i>Ready</button></div>` : `<span class="tag ${mine ? 'live' : 'hot'}">You said ${mine ? 'ready' : 'not yet'}</span>`}</div>
    <div class="p-body pad"><div class="ready-list" style="margin:0">${members.map((m) => {
      const a = r.answers[String(m.id)];
      return `<span class="ready-pill ${a === true ? 'yes' : a === false ? 'no' : ''}"><i class="fa-solid ${a === true ? 'fa-check' : a === false ? 'fa-xmark' : 'fa-clock'}"></i>${esc(m.name)}</span>`;
    }).join('')}</div></div></section>`;
}

function viewOverview() {
  const s = state.squad;
  const down = online().filter(isDown).length;
  const me = myMember() || {};
  const heroTier = s.temporary ? '#9aa4ab' : tierOf(s.tier).color;
  const heroBody = s.temporary
    ? `<div class="tags" style="margin-top:9px"><span class="tag warn"><i class="fa-solid fa-hourglass-half"></i>Temporary squad</span><span class="tag off"><i class="fa-solid fa-ban"></i>No rating or stats</span><span class="tag off"><i class="fa-solid fa-clock"></i>Running ${since(s.created)}</span></div>`
    : `<div class="elo-wrap">
         <div class="elo-top"><span>${tierBadge(s.tier)}</span><b>${s.elo} ELO</b></div>
         <div class="elo-bar"><i style="width:${Math.round((s.tierProgress || 0) * 100)}%"></i></div>
         <div class="elo-top" style="margin:5px 0 0"><span>${s.wins}W · ${s.losses}L · ${s.draws}D</span><span>${s.nextTier ? `${s.nextTier.min - s.elo} to ${esc(s.nextTier.name)}` : 'Top tier'}</span></div>
       </div>`;
  const log = (s.log || []).slice(-5).reverse();
  const roster = [...s.members].sort((a, b) => (b.online - a.online) || (b.rank - a.rank)).slice(0, 6);

  return `<div class="page">
    <div class="head"><div><h1>Overview</h1><p>${isOwner() ? `You own ${esc(s.name)}` : `${esc(me.rankName || 'Member')} of ${esc(s.name)}`}${s.description ? ` · ${esc(s.description)}` : ''}</p></div>${nowClock()}</div>

    <div class="hero wide" style="--tier:${esc(heroTier)}">${avatar(s.name, s.image, 'lg')}
      <div class="hero-txt"><h2>${esc(s.name)}${tagChip(s.tag)}<span class="bp-mini" title="Squad blip colour" style="background:${blipHex(s.blipColor)}"></span></h2>
        <p>${s.members.length} on the roster · ${online().length} online${s.allies && s.allies.length ? ` · ${s.allies.length} ${s.allies.length === 1 ? 'ally' : 'allies'}` : ''} · running since ${ago(s.created)}</p>
        ${heroBody}</div>
      <div class="hero-end">${can('edit') ? '<button class="icon-btn" title="Edit squad" data-tab="edit"><i class="fa-solid fa-pen"></i></button>' : ''}
        ${can('ranks') ? '<button class="icon-btn" title="Manage ranks" data-tab="ranks"><i class="fa-solid fa-list-ol"></i></button>' : ''}</div>
    </div>

    <div class="stats four">
      <div class="stat"><div class="tile"><i class="fa-solid fa-users"></i></div><div class="stat-txt"><span>Online</span><b>${online().length}<small>/${s.members.length}</small></b></div></div>
      <div class="stat"><div class="tile ${down ? 'red' : 'grey'}"><i class="fa-solid fa-heart-pulse"></i></div><div class="stat-txt"><span>Down</span><b>${down}</b></div></div>
      ${s.temporary
        ? `<div class="stat"><div class="tile blue"><i class="fa-solid fa-clock"></i></div><div class="stat-txt"><span>Running</span><b class="txt" data-since="${s.created}">${since(s.created)}</b></div></div>
           <div class="stat"><div class="tile amber"><i class="fa-solid fa-hourglass-half"></i></div><div class="stat-txt"><span>Type</span><b class="txt">Temporary</b></div></div>`
        : `<div class="stat"><div class="tile blue"><i class="fa-solid fa-crosshairs"></i></div><div class="stat-txt"><span>Squad K/D</span><b>${ratio(s.kills, s.deaths)}</b></div></div>
           <div class="stat"><div class="tile amber"><i class="fa-solid fa-percent"></i></div><div class="stat-txt"><span>Win rate</span><b>${pct(s.wins, s.losses)}<small>%</small></b></div>
             ${s.wins + s.losses ? `<span class="delta ${s.wins >= s.losses ? '' : 'dn'}"><i class="fa-solid fa-arrow-${s.wins >= s.losses ? 'up' : 'down'}"></i>${s.wins + s.losses} fights</span>` : ''}</div>`}
    </div>

    <div class="cols wide-left"><div class="col">
      ${readyPanel(s)}
      ${requestsPanel(s)}
      <div class="motd"><i class="fa-solid fa-message"></i><div><b>Message of the day</b><p class="${s.motd ? '' : 'empty-txt'}">${s.motd ? esc(s.motd) : (can('motd') ? 'Nothing set. Leave your squad a note, it shows here and when they join.' : 'Nothing set yet.')}</p></div>
        ${can('motd') ? '<button class="icon-btn" title="Edit message" data-act="motd"><i class="fa-solid fa-pen"></i></button>' : ''}</div>

      <section class="panel"><div class="p-head"><div><h2>Quick actions</h2><p>Things you can do from here</p></div></div>
        <div class="p-body pad" style="gap:8px">
          <div class="actions">
            ${feature('ReadyCheck') && can('ready') ? `<button class="btn-ghost" data-act="readyCheck" ${s.ready ? 'disabled' : ''}><i class="fa-solid fa-circle-check"></i>Ready check</button>` : ''}
            ${feature('Rally') && can('rally') ? (s.rally ? '<button class="btn-ghost" data-act="rallyClear"><i class="fa-solid fa-flag"></i>Clear rally</button>' : '<button class="btn-ghost" data-act="rally"><i class="fa-solid fa-flag"></i>Set rally here</button>') : ''}
            ${feature('Waypoint') ? '<button class="btn-ghost" data-act="waypoint"><i class="fa-solid fa-route"></i>Share waypoint</button>' : ''}
            <button class="btn-ghost" data-tab="chat"><i class="fa-solid fa-message"></i>Open chat</button>
            ${can('ranks') ? '<button class="btn-ghost" data-tab="ranks"><i class="fa-solid fa-list-ol"></i>Manage ranks</button>' : ''}
          </div>
          ${s.rally ? `<div class="divider"></div><div class="sw-line static"><div><b>Rally point active</b><span>Set by ${esc(s.rally.by)} ${ago(s.rally.at)}. Everyone has a route to it.</span></div><i class="fa-solid fa-flag" style="color:var(--teal)"></i></div>` : ''}
          ${can('invite') ? `<div class="divider"></div><div class="inline-form">
            <div class="input"><i class="fa-solid fa-hashtag"></i><input id="inviteId" inputmode="numeric" maxlength="5" placeholder="Invite by server ID"></div>
            <button class="btn-teal" data-act="invite" ${s.members.length >= s.limit ? 'disabled' : ''}><i class="fa-solid fa-paper-plane"></i>Invite</button></div>` : ''}
        </div></section>
    </div><div class="col">
      <section class="panel">
        <div class="p-head"><div><h2>Members</h2><p>Online first</p></div><button class="btn-ghost" data-tab="members">All ${s.members.length}<i class="fa-solid fa-chevron-right"></i></button></div>
        <div class="p-body">${roster.map((m) => memberRow(m, true)).join('')}</div>
      </section>
      ${feature('ActivityLog') ? `<section class="panel">
        <div class="p-head"><div><h2>Recent activity</h2><p>What happened lately</p></div><button class="btn-ghost" data-tab="activity">Full log<i class="fa-solid fa-chevron-right"></i></button></div>
        <div class="p-body tight" style="padding:4px 10px">${log.length ? `<div class="log">${log.map(logRow).join('')}</div>` : '<div class="empty" style="padding:18px"><i class="fa-solid fa-clock-rotate-left"></i><b>Nothing logged yet</b><span>Joins, promotions and fights show up here.</span></div>'}</div>
      </section>` : ''}
    </div></div>
  </div>
  <div class="foot">
    <button class="btn-red" data-act="leave"><i class="fa-solid fa-right-from-bracket"></i>Leave</button>
    ${can('disband') ? '<button class="btn-red" data-act="disband"><i class="fa-solid fa-ban"></i>Disband</button>' : ''}
  </div>`;
}
after.squad = () => {
  const i = $('#inviteId');
  if (i) {
    i.onkeydown = (e) => { if (e.key === 'Enter') $('[data-act="invite"]')?.click(); };
    i.oninput = () => { i.value = i.value.replace(/\D/g, ''); };
  }
};

// ─── members ───────────────────────────────────────────────
function viewMembers() {
  const s = state.squad;
  const f = state.memberFilter;
  const list = s.members.filter((m) => f === 'all' || (f === 'online' ? m.online : !m.online));
  return `<div class="page">
    <div class="head"><div><h1>Members</h1><p>${online().length} online · ${s.members.length} of ${s.limit} spots filled · ranks, live health and K/D/A.</p></div>
      <div class="head-end"><div class="seg">${[['all', 'All'], ['online', 'Online'], ['offline', 'Offline']].map(([k, l]) => `<button class="${f === k ? 'on' : ''}" data-mfilter="${k}">${l}</button>`).join('')}</div></div></div>
    ${requestsPanel(s)}
    <section class="panel">
      <div class="p-head"><div><h2>Roster</h2><p>Highest rank first</p></div><span class="tally">${list.length}</span></div>
      <div class="p-body" id="memberList">${list.length ? list.map((m) => memberRow(m, false)).join('') : emptyBox('fa-user-slash', 'Nobody here', 'No members match that filter.')}</div>
    </section>
  </div>
  <div class="foot">${can('invite') ? `<div class="inline-form" style="flex:1;max-width:420px">
      <div class="input"><i class="fa-solid fa-hashtag"></i><input id="inviteId" inputmode="numeric" maxlength="5" placeholder="Invite by server ID"></div>
      <button class="btn-teal" data-act="invite" ${s.members.length >= s.limit ? 'disabled' : ''}><i class="fa-solid fa-paper-plane"></i>Invite</button></div>` : '<span class="muted" style="font-size:11px;align-self:center">Your rank cannot invite players</span>'}</div>`;
}
after.members = after.squad;

// ─── chat ──────────────────────────────────────────────────
function msgHtml(m) {
  if (m.system) return `<div class="sys"><i class="fa-solid fa-circle-info"></i>${esc(m.text)}</div>`;
  const me = m.from === state.me;
  return `<div class="msg ${me ? 'me' : ''}">${avatar(m.name, m.avatar, 'sm')}<div class="bubble">
    <div class="who"><b>${me ? 'You' : esc(m.name)}</b><span>${m.rank ? `${esc(m.rank)} · ` : ''}${clock(m.t)}</span></div><p>${esc(m.text)}</p></div></div>`;
}

function viewChat() {
  const max = state.cfg.chatMax;
  const s = state.squad;
  const log = state.chat.length ? state.chat.map(msgHtml).join('')
    : `<div class="empty" style="margin:auto 0"><i class="fa-solid fa-comments"></i><b>No messages yet</b><span>Messages here only reach your squad.${state.cfg.commands && state.cfg.commands.Chat ? ` You can also type /${esc(state.cfg.commands.Chat)} in game chat.` : ''}</span></div>`;
  return `<div class="page fill">
    <div class="chat-head"><div><h1>Squad chat</h1><p>${online().length} online · only your squad sees this</p></div><span class="tag live"><i class="fa-solid fa-users"></i>${esc(s.name)}</span></div>
    <div class="chat-log" id="chatLog">${log}</div>
    <div class="composer">
      <div class="input"><i class="fa-solid fa-message"></i><input id="chatInput" maxlength="${max}" placeholder="Message your squad"></div>
      <span class="count" id="chatCount">0/${max}</span>
      <button class="btn-teal" data-act="send" aria-label="Send"><i class="fa-solid fa-paper-plane"></i></button>
    </div></div>`;
}
after.chat = () => {
  const log = $('#chatLog'); log.scrollTop = log.scrollHeight;
  const input = $('#chatInput');
  input.focus();
  input.oninput = () => { $('#chatCount').textContent = `${input.value.length}/${state.cfg.chatMax}`; };
  input.onkeydown = (e) => { if (e.key === 'Enter') sendChat(); };
};

async function sendChat() {
  const input = $('#chatInput');
  if (!input) return;
  const text = input.value.trim();
  if (!text) return;
  input.value = ''; $('#chatCount').textContent = `0/${state.cfg.chatMax}`;
  const r = await nui('chat', { text });
  if (r && !r.ok && r.msg) { notify(r.msg, 'error'); input.value = text; }
}

function appendChat(msg) {
  const log = $('#chatLog');
  if (!log) return;
  const stick = log.scrollHeight - log.scrollTop - log.clientHeight < 60;
  if (log.querySelector('.empty')) log.innerHTML = '';
  log.insertAdjacentHTML('beforeend', msgHtml(msg));
  while (log.children.length > 80) log.firstChild.remove();
  if (stick || msg.from === state.me) log.scrollTop = log.scrollHeight;
}

// ─── stats ─────────────────────────────────────────────────
function viewStats() {
  const s = state.squad, st = state.stats;
  const head = `<div class="head"><div><h1>Squad stats</h1><p>Kills, deaths and assists against other squads, plus every fight that was scored.</p></div>${nowClock()}</div>`;
  if (!st) return `<div class="page">${head}${skeleton(4, 44)}</div>`;

  const sorters = {
    kills: (a, b) => (b.kills - a.kills) || (b.assists - a.assists),
    kd: (a, b) => ratio(b.kills, b.deaths) - ratio(a.kills, a.deaths),
    revives: (a, b) => (b.revives || 0) - (a.revives || 0),
    playtime: (a, b) => (b.playtime || 0) - (a.playtime || 0),
  };
  const ranked = [...st.members].sort(sorters[state.statsSort] || sorters.kills);
  const live = st.active.length ? `<section class="panel">
    <div class="p-head"><div><h2>Live fights</h2><p>Scored once the shooting stops</p></div><span class="tally hot">${st.active.length}</span></div>
    <div class="p-body">${st.active.map((a) => `<div class="row">
      <div class="row-txt"><b>${esc(a.squad)}${tagChip(a.tag)}</b><span>${a.elo} ELO · started ${ago(a.since)} · last kill ${ago(a.last || a.since)}</span></div>
      <div class="row-end"><span class="tag ${a.mine > a.theirs ? 'live' : a.mine < a.theirs ? 'hot' : 'off'}">${a.mine} – ${a.theirs}</span></div></div>`).join('')}</div>
  </section>` : '';
  const history = `<section class="panel">
    <div class="p-head"><div><h2>Recent fights</h2><p>Last 10 scored results</p></div></div>
    <div class="p-body">${st.history.length ? st.history.map((h) => {
      const mine = h.squad_a === s.id;
      const myKills = mine ? h.kills_a : h.kills_b, theirKills = mine ? h.kills_b : h.kills_a;
      const delta = mine ? h.delta_a : h.delta_b, other = mine ? h.name_b : h.name_a;
      return `<div class="row"><div class="row-txt"><b>${esc(other)}</b><span>${ago(h.ended)}</span></div>
        <div class="row-end"><span class="tag ${delta > 0 ? 'live' : delta < 0 ? 'hot' : 'off'}">${myKills} – ${theirKills}</span>
        <b style="font-size:12px;color:${delta > 0 ? 'var(--teal)' : delta < 0 ? 'var(--red)' : 'var(--ink-3)'}">${delta > 0 ? '+' : ''}${delta}</b></div></div>`;
    }).join('') : emptyBox('fa-crosshairs', 'No fights scored yet', 'Trade kills with another squad and the result lands here.')}</div>
  </section>`;
  const sorts = [['kills', 'Kills'], ['kd', 'K/D'], ['revives', 'Revives'], ['playtime', 'Playtime']];
  const val = (m) => state.statsSort === 'kd' ? [ratio(m.kills, m.deaths), 'K/D'] : state.statsSort === 'revives' ? [m.revives || 0, 'revives'] : state.statsSort === 'playtime' ? [dur(m.playtime), 'played'] : [m.kills, 'kills'];

  return `<div class="page">${head}
    <div class="stats four">
      <div class="stat"><div class="tile"><i class="fa-solid fa-crosshairs"></i></div><div class="stat-txt"><span>Kills</span><b>${s.kills}</b></div></div>
      <div class="stat"><div class="tile red"><i class="fa-solid fa-skull"></i></div><div class="stat-txt"><span>Deaths</span><b>${s.deaths}</b></div></div>
      <div class="stat"><div class="tile blue"><i class="fa-solid fa-handshake-angle"></i></div><div class="stat-txt"><span>Assists</span><b>${s.assists}</b></div></div>
      <div class="stat"><div class="tile amber"><i class="fa-solid fa-chart-line"></i></div><div class="stat-txt"><span>K/D</span><b>${ratio(s.kills, s.deaths)}</b></div></div>
    </div>
    <div class="cols"><div class="col">${live}${history}</div><div class="col">
    <section class="panel">
      <div class="p-head"><div><h2>Member leaderboard</h2><p>Inside this squad</p></div><div class="seg" style="padding:2px">${sorts.map(([k, l]) => `<button class="${state.statsSort === k ? 'on' : ''}" data-ssort="${k}" style="height:23px;font-size:10.5px">${l}</button>`).join('')}</div></div>
      <div class="p-body scroll">${ranked.map((m, i) => { const [v, l] = val(m); return `<div class="lb-row ${m.id === state.me ? 'me' : ''}">
        <span class="pos ${i < 3 ? `g${i + 1}` : ''}">${i + 1}</span>${avatar(m.name, m.avatar, `sm ${m.online ? '' : 'off'}`)}
        <div class="row-txt"><b>${esc(m.name)}</b><span><span class="rank ${m.owner ? 'owner' : ''}"><i class="fa-solid ${esc(m.rankIcon || 'fa-user')}"></i>${esc(m.rankName)}</span>${kdaHtml(m, true)}</span></div>
        <div class="lb-end"><b>${v}</b><span>${l}</span></div></div>`; }).join('')}</div>
    </section></div></div>
  </div>
  <div class="foot right"><button class="btn-line" data-act="refreshStats"><i class="fa-solid fa-rotate-right"></i>Refresh</button></div>`;
}

// ─── activity ──────────────────────────────────────────────
function viewActivity() {
  const log = [...(state.squad.log || [])].reverse();
  return `<div class="page">
    <div class="head"><div><h1>Activity</h1><p>Joins, promotions, alliances, fights and edits — the last ${log.length || 0} things that happened in the squad.</p></div>${nowClock()}</div>
    <section class="panel"><div class="p-head"><div><h2>Log</h2><p>Newest first</p></div><span class="tally">${log.length}</span></div>
      <div class="p-body" style="padding:4px 12px">${log.length ? `<div class="log">${log.map(logRow).join('')}</div>` : emptyBox('fa-clock-rotate-left', 'Nothing logged yet', 'Activity builds up as the squad plays.')}</div></section>
  </div>`;
}

// ─── allies ────────────────────────────────────────────────
function viewAllies() {
  const s = state.squad;
  const max = state.cfg.allyMax || 0;
  const list = s.allies || [];
  const pending = s.allyRequests || [];
  const mayManage = can('edit');
  const full = list.length >= max;

  const allyRow = (a) => `<div class="row">${avatar(a.name, a.image, 'sm')}
    <div class="row-txt"><b>${esc(a.name)}${tagChip(a.tag)}</b><span><span class="bp-mini" style="background:${blipHex(a.blipColor)}"></span>${a.online} online · allied ${ago(a.since)}</span></div>
    <div class="row-end">${tierBadge(a.tier, ` ${a.elo}`)}${mayManage ? `<button class="icon-btn danger" title="End this alliance" data-allyend="${a.id}"><i class="fa-solid fa-link-slash"></i></button>` : ''}</div></div>`;

  const pendingBlock = pending.length ? `<section class="panel">
    <div class="p-head"><div><h2>Requests</h2><p>Squads asking to ally with you</p></div><span class="tally hot">${pending.length}</span></div>
    <div class="p-body">${pending.map((r) => `<div class="row">${avatar(r.name, r.image, 'sm')}
      <div class="row-txt"><b>${esc(r.name)}${tagChip(r.tag)}</b><span>Sent by ${esc(r.by)} · expires in ${r.expires}s</span></div>
      <div class="row-end">${tierBadge(r.tier)}${mayManage ? `<button class="btn-line sm" data-allyno="${r.id}">Decline</button><button class="btn-teal sm" data-allyyes="${r.id}" ${full ? 'disabled' : ''}>Accept</button>` : '<span class="tag off">Leader only</span>'}</div></div>`).join('')}</div>
  </section>` : '';

  const allied = new Set(list.map((a) => a.id));
  const options = (state.list || []).filter((x) => x.id !== s.id && !allied.has(x.id) && !x.temporary);

  return `<div class="page">
    <div class="head"><div><h1>Allies</h1><p>Allied squads see each other on the map, can't trade friendly fire, and never take ELO off one another.</p></div><span class="tally" style="margin:0 0 4px">${list.length}/${max}</span></div>
    <div class="cols">
      <div class="col">
        ${pendingBlock}
        <section class="panel"><div class="p-head"><div><h2>Your alliances</h2><p>${full ? 'You have the most allies allowed' : `Room for ${max - list.length} more`}</p></div></div>
          <div class="p-body">${list.length ? list.map(allyRow).join('') : emptyBox('fa-handshake-slash', 'No alliances yet', 'Pick a squad on the right to send them a request.')}</div></section>
      </div>
      <div class="col"><section class="panel">
        <div class="p-head"><div><h2>Send a request</h2><p>${mayManage ? 'Both squads have to agree' : 'Your rank cannot manage alliances'}</p></div><button class="btn-ghost" data-act="refresh"><i class="fa-solid fa-rotate-right"></i></button></div>
        <div class="p-body scroll">${!state.list ? skeleton(3) : options.length ? options.map((x) => `<div class="row">${avatar(x.name, x.image, 'sm')}
          <div class="row-txt"><b>${esc(x.name)}${tagChip(x.tag)}</b><span>${esc(x.owner)} · ${x.online} online</span></div>
          <div class="row-end">${tierBadge(x.tier, ` ${x.elo}`)}<button class="btn-line sm" data-allyask="${x.id}" ${!mayManage || full ? 'disabled' : ''}>Ask</button></div></div>`).join('')
          : emptyBox('fa-users-slash', 'No squads to ally with', 'Other permanent squads show up here once they exist.')}</div>
      </section></div>
    </div>
  </div>`;
}

// ─── ranks editor ──────────────────────────────────────────
function viewRanks() {
  const c = state.cfg;
  if (!state.ranksDraft) state.ranksDraft = JSON.parse(JSON.stringify(state.squad.ranks));
  const d = state.ranksDraft;
  return `<div class="page">
    <div><button class="btn-ghost" data-tab="squad"><i class="fa-solid fa-arrow-left"></i>Back to overview</button></div>
    <div class="head"><div><h1>Squad ranks</h1><p>Rename ranks and choose what each one can do. The top rank is the owner and always has everything.</p></div>
      ${d.length < c.maxRanks ? '<button class="btn-ghost" data-act="addRank"><i class="fa-solid fa-plus"></i>Add a rank</button>' : ''}</div>
    <div class="cols">${d.map((r, i) => {
      const top = i === d.length - 1;
      return `<div class="col"><section class="panel" data-rank="${i}">
        <div class="p-head"><div style="flex:1">
          <div class="inline-form"><div class="input" style="flex:1"><i class="fa-solid ${esc(r.icon)}"></i><input data-rname="${i}" maxlength="18" value="${esc(r.name)}" placeholder="Rank name"></div>
            <button class="icon-btn" data-rup="${i}" ${i === d.length - 1 ? 'disabled' : ''} title="Move up"><i class="fa-solid fa-chevron-up"></i></button>
            <button class="icon-btn" data-rdown="${i}" ${i === 0 ? 'disabled' : ''} title="Move down"><i class="fa-solid fa-chevron-down"></i></button>
            <button class="icon-btn danger" data-rdel="${i}" ${d.length <= 2 ? 'disabled' : ''} title="Delete rank"><i class="fa-solid fa-trash"></i></button>
          </div>
          <p style="margin-top:7px">${top ? 'Owner rank · every permission' : `Level ${i + 1}`}</p>
        </div></div>
        <div class="p-body pad">
          <div class="icon-pick">${c.rankIcons.map((ic) => `<button class="${ic === r.icon ? 'on' : ''}" data-ricon="${i}" data-icon="${esc(ic)}"><i class="fa-solid ${esc(ic)}"></i></button>`).join('')}</div>
          ${top ? '' : `<div class="divider"></div>${c.perms.map((p) => `<div class="sw-line compact" data-rperm="${i}" data-perm="${esc(p.key)}"><div><b>${esc(p.label)}</b></div><span class="sw mini ${r.perms && r.perms[p.key] ? 'on' : ''}"><i></i></span></div>`).join('')}`}
        </div></section></div>`;
    }).join('')}</div>
  </div>
  <div class="foot">
    <button class="btn-line" data-act="resetRanks"><i class="fa-solid fa-rotate-left"></i>Discard</button>
    <button class="btn-teal" data-act="saveRanks"><i class="fa-solid fa-floppy-disk"></i>Save ranks</button>
  </div>`;
}
after.ranks = () => {
  document.querySelectorAll('[data-rname]').forEach((el) => { el.oninput = () => { state.ranksDraft[Number(el.dataset.rname)].name = el.value; }; });
};

// ─── settings ──────────────────────────────────────────────
const HUD_COLORS = ['#ffffff', '#08afa2', '#58a6ff', '#e5484d', '#e5a50a', '#a078ff', '#8bd35a', '#ff7ad9'];
const swLine = (key, title, sub) => `<div class="sw-line" data-set="${key}"><div><b>${title}</b>${sub ? `<span>${sub}</span>` : ''}</div><span class="sw ${state.settings[key] ? 'on' : ''}"><i></i></span></div>`;
const swatchRow = (key, list, custom) => `<div class="swatches">${list.map(([hex, id]) =>
  `<button class="swatch ${state.settings[key] === (id ?? hex) ? 'on' : ''}" style="background:${hex}" data-color="${key}" data-val="${id ?? hex}" aria-label="${hex}"></button>`).join('')}
  ${custom ? `<label class="swatch custom" title="Custom colour"><i class="fa-solid fa-eye-dropper"></i><input type="color" data-custom="${key}" value="${esc(state.settings[key])}"></label>` : ''}</div>`;

function viewSettings() {
  const c = state.cfg, st = state.settings, f = c.features;
  const maxOpts = [0, ...Array.from({ length: Math.max(0, c.maxMembers - 2) }, (_, i) => i + 2)];
  const nt = c.nametag || {};
  const seg = (key, options) => `<div class="seg">${options.map(([val, label]) => `<button class="${st[key] === val ? 'on' : ''}" data-pick="${key}" data-val="${val}">${label}</button>`).join('')}</div>`;
  const slider = (key, label, min, max, step, suffix) => `<div class="field">
    <label>${label} <b class="slider-val" id="val-${key}">${st[key]}${suffix}</b></label>
    <input type="range" class="range" id="rng-${key}" data-range="${key}" min="${min}" max="${max}" step="${step}" value="${st[key]}" style="--fill:${((st[key] - min) / (max - min)) * 100}%"></div>`;
  const blipColors = c.squadBlipColors.map((id) => [blipHex(id), id]);

  return `<div class="page">
    <div class="head"><div><h1>Your settings</h1><p>These are yours alone — saved on your client and kept between sessions.</p></div>
      <button class="btn-ghost" data-act="resetSettings"><i class="fa-solid fa-rotate-left"></i>Reset all</button></div>
    <div class="cols"><div class="col">

    ${f.Hud ? `<section class="panel"><div class="p-head"><div><h2>Team HUD</h2><p>Squad health on your screen</p></div>
      <button class="btn-ghost" data-act="hudMove"><i class="fa-solid fa-up-down-left-right"></i>Move</button></div>
      <div class="p-body pad">
        ${swLine('hud', 'Show team HUD')}
        ${st.hud ? `<div class="divider"></div>
        <div class="field"><label>Card style</label>${seg('hudStyle', [['cards', 'Cards'], ['bars', 'Flat bars']])}</div>
        <div class="field"><label>Left edge colour</label>${seg('hudAccent', [['squad', 'Squad'], ['teal', 'Teal'], ['health', 'Health'], ['none', 'None']])}</div>
        ${slider('hudScale', 'Size', 70, 130, 5, '%')}
        ${slider('hudOpacity', 'Background', 0, 100, 5, '%')}
        <div class="divider"></div>
        ${swLine('hudShowSelf', 'Show your own card', 'Your health and armour at the top of the list')}
        ${swLine('hudAvatars', 'Profile pictures')}
        ${swLine('animatedAvatars', 'Animated pictures', 'Play animated Discord avatars')}
        ${swLine('hudArmorBar', 'Armour bar')}
        ${swLine('hudRank', 'Rank name on cards')}
        ${swLine('hudKda', 'Kills and deaths on cards')}
        ${swLine('hudTalking', 'Voice indicator', 'Glow when a squadmate is talking')}
        ${swLine('hudMinimized', 'Compact cards', 'Smaller cards with less detail')}
        <div class="divider"></div>
        <div class="field"><label for="hudMax">Cards shown</label>
          <select id="hudMax" class="select">${maxOpts.map((n) => `<option value="${n}" ${st.hudMax === n ? 'selected' : ''}>${n === 0 ? 'Every member' : `Up to ${n}`}</option>`).join('')}</select></div>
        <div class="field"><label>Health bar colour</label>${swatchRow('hudHealth', HUD_COLORS.map((h) => [h]), true)}</div>
        ${st.hudArmorBar ? `<div class="field"><label>Armour bar colour</label>${swatchRow('hudArmor', HUD_COLORS.map((h) => [h]), true)}</div>` : ''}` : ''}
      </div></section>` : ''}

    ${c.voice && c.autoRadio ? `<section class="panel"><div class="p-head"><div><h2>Voice</h2><p>Squad radio</p></div></div>
      <div class="p-body pad">${swLine('radio', 'Join squad radio automatically', 'You go on your squad’s channel as soon as you join, and back to your old one when you leave')}</div></section>` : ''}

    ${f.Compass ? `<section class="panel"><div class="p-head"><div><h2>Compass</h2><p>Heading strip at the top of your screen</p></div></div>
      <div class="p-body pad">
        ${swLine('compass', 'Show compass')}
        ${st.compass ? `${swLine('compassStreet', 'Street and area name')}${swLine('compassMarkers', 'Squad, rally and ping markers', 'With their distance')}` : ''}
      </div></section>` : ''}

    </div><div class="col">

    <section class="panel"><div class="p-head"><div><h2>Alerts</h2><p>Everything arrives as an ox_lib notification</p></div></div>
      <div class="p-body pad">
        ${swLine('quiet', 'Quiet mode', 'Mute every squad notification and sound except invites and downed alerts')}
        <div class="divider"></div>
        ${swLine('chatNotify', 'Chat messages', 'Pop up new squad messages while the menu is closed')}
        ${swLine('chatSound', 'Chat sound')}
        ${f.Pings ? `<div class="divider"></div>${swLine('pingNotify', 'Ping alerts')}${swLine('pingSound', 'Ping sound')}` : ''}
        ${f.Revive ? swLine('reviveAlerts', 'Downed alerts', 'Alert and map ping when a squadmate goes down') : ''}
        ${c.requests && c.requests.enabled ? swLine('requestNotify', 'Join requests', 'Tell you when someone asks to join (officers only)') : ''}
        ${f.Combat ? `<div class="divider"></div>${f.Killfeed ? swLine('killfeed', 'Killfeed', 'On-screen feed for kills against other squads') : ''}${f.MatchBanner ? swLine('matchBanner', 'Fight results', 'Banner when a fight is scored') : ''}` : ''}
      </div></section>

    ${f.Tags ? `<section class="panel"><div class="p-head"><div><h2>Nametags</h2><p>What shows over your squadmates</p></div></div>
      <div class="p-body pad">
        ${swLine('tags', 'Show nametags')}
        ${st.tags ? `<div class="divider"></div>
        ${nt.Name !== false ? swLine('tagName', 'Player name') : ''}
        ${nt.Tag !== false ? swLine('tagSquadTag', 'Squad tag') : ''}
        ${nt.Role !== false ? swLine('tagRole', 'Rank name') : ''}
        ${nt.Health !== false ? swLine('tagHealth', 'Health and armour bar') : ''}
        ${f.Affiliations && nt.Allies !== false ? swLine('tagAllies', 'Allied squads', 'Show tags over allied players too') : ''}
        <div class="field"><label>Tag colour</label>${swatchRow('tagColor', c.tagColors)}</div>` : ''}
      </div></section>` : ''}

    ${f.Blips ? `<section class="panel"><div class="p-head"><div><h2>Map blips</h2><p>Squadmates on your map and radar</p></div></div>
      <div class="p-body pad">
        ${swLine('blips', 'Show blips')}
        ${st.blips ? `<div class="divider"></div>
        ${f.SquadBlips ? swLine('blipUseSquad', 'Use squad colours', 'Each squad shows in the colour it picked') : ''}
        ${f.Affiliations ? swLine('blipAllies', 'Allied squads', 'Show allied players on your map') : ''}
        ${!f.SquadBlips || !st.blipUseSquad ? `<div class="field"><label>Blip colour</label>${swatchRow('blipColor', blipColors)}</div>` : ''}` : ''}
      </div></section>` : ''}

    <section class="panel"><div class="p-head"><div><h2>Keys</h2><p>Defaults — rebind them in the FiveM key settings</p></div></div>
      <div class="p-body pad" style="gap:8px">
        <div class="sw-line static"><div><b>Accept prompt</b><span>Invites and ready checks</span></div><span class="key">${esc(c.prompts.accept)}</span></div>
        <div class="sw-line static"><div><b>Decline prompt</b></div><span class="key">${esc(c.prompts.decline)}</span></div>
        ${f.Revive ? `<div class="sw-line static"><div><b>Revive squadmate</b></div><span class="key">${esc(c.reviveKey)}</span></div>` : ''}
        ${f.Pings ? '<div class="sw-line static"><div><b>Ping</b><span>Tap to ping where you look, hold for the wheel</span></div><span class="key">MMB</span></div>' : ''}
      </div></section>

    </div></div>
  </div>`;
}

after.settings = () => {
  const sel = $('#hudMax');
  if (sel) sel.onchange = () => setSetting('hudMax', Number(sel.value));
  document.querySelectorAll('[data-custom]').forEach((el) => { el.oninput = debounce(() => setSetting(el.dataset.custom, el.value, true), 120); });
  document.querySelectorAll('[data-range]').forEach((el) => {
    const key = el.dataset.range;
    const out = $(`#val-${key}`);
    const suffix = out ? out.textContent.replace(/[\d.-]/g, '') : '';
    el.oninput = () => {
      state.settings[key] = Number(el.value);
      el.style.setProperty('--fill', `${((el.value - el.min) / (el.max - el.min)) * 100}%`);
      if (out) out.textContent = el.value + suffix;
      applyHudStyle(); renderHud();
    };
    el.onchange = () => setSetting(key, Number(el.value), true);
  });
};

function setSetting(key, value, keepView) {
  state.settings = { ...state.settings, [key]: value };
  if (key === 'compass' && !value) setCompassVisible(false);
  nui('saveSettings', state.settings);
  applyHudStyle();
  renderHud();
  if (!keepView) render();
}

// ─── admin ─────────────────────────────────────────────────
function viewAdmin() {
  const a = state.admin;
  const head = `<div class="head"><div><h1>Staff tools</h1><p>Inspect squads, remove members, rename, adjust ratings or force a disband.</p></div>
    <div class="head-end"><button class="btn-ghost" data-admin="seasonReset"><i class="fa-solid fa-calendar-xmark"></i>Season reset</button><button class="btn-ghost" data-act="refreshAdmin"><i class="fa-solid fa-rotate-right"></i>Refresh</button></div></div>`;
  if (!a) return `<div class="page">${head}${skeleton(4, 44)}</div>`;

  const rows = a.length ? a.map((s) => `<div class="row click ${state.adminOpen === s.id ? 'on' : ''}" data-adminsquad="${s.id}">${avatar(s.name, s.image, 'sm')}
    <div class="row-txt"><b>${esc(s.name)}${tagChip(s.tag)}</b><span>ID ${s.id} · ${s.count} members · ${s.online} online${s.temporary ? ' · temporary' : ''}</span></div>
    <div class="row-end">${s.temporary ? '<span class="tag warn">Temp</span>' : tierBadge(s.tier, ` ${s.elo}`)}</div></div>`).join('')
    : emptyBox('fa-users-slash', 'No squads exist right now', 'Created squads will show up here.');

  const sel = a.find((x) => x.id === state.adminOpen);
  const detail = sel ? `
    <div class="hero" style="--tier:${esc(tierOf(sel.tier).color)}">${avatar(sel.name, sel.image, 'lg')}
      <div class="hero-txt"><h2>${esc(sel.name)}${tagChip(sel.tag)}</h2>
        <p>ID ${sel.id} · created ${ago(sel.created)}${sel.persistent ? ' · saved' : ' · session only'} · ${sel.allies || 0} allies</p>
        <div class="tags">${tierBadge(sel.tier, ` ${sel.elo}`)}<span class="tag off">${sel.wins}W ${sel.losses}L ${sel.draws || 0}D</span><span class="tag off">${sel.kills}K ${sel.deaths}D</span></div>
        ${sel.motd ? `<p style="margin-top:8px;color:var(--ink-2)">MOTD: ${esc(sel.motd)}</p>` : ''}</div></div>
    <div class="actions">
      <button class="btn-ghost" data-admin="rename" data-sq="${sel.id}"><i class="fa-solid fa-pen"></i>Rename</button>
      <button class="btn-ghost" data-admin="setElo" data-sq="${sel.id}"><i class="fa-solid fa-sliders"></i>Set ELO</button>
      <button class="btn-ghost" data-admin="resetStats" data-sq="${sel.id}"><i class="fa-solid fa-rotate-left"></i>Reset stats</button>
      ${sel.motd ? `<button class="btn-ghost" data-admin="clearMotd" data-sq="${sel.id}"><i class="fa-solid fa-eraser"></i>Clear MOTD</button>` : ''}
      <button class="btn-ghost" data-admin="disband" data-sq="${sel.id}" style="color:var(--red);border-color:var(--red-edge)"><i class="fa-solid fa-ban"></i>Force disband</button>
    </div>
    <section class="panel"><div class="p-head"><div><h2>Members</h2><p>Server IDs shown for online players</p></div><span class="tally">${sel.count}</span></div>
      <div class="p-body scroll">${sel.members.map((m) => `<div class="row ${m.online ? '' : 'dim'}">${avatar(m.name, null, 'sm')}
        <div class="row-txt"><b>${esc(m.name)}${m.realName && m.realName !== m.name ? ` <span class="real-name">${esc(m.realName)}</span>` : ''}</b><span><span class="rank ${m.owner ? 'owner' : ''}">${esc(m.rankName)}</span>${kdaHtml(m)}${!m.online && m.lastSeen ? ` · seen ${ago(m.lastSeen)}` : ''}</span></div>
        <div class="row-end">${m.online ? `<span class="tally">${m.id}</span>` : '<span class="tag off">Offline</span>'}
        <button class="icon-btn danger" title="Remove from squad" data-admin="kick" data-sq="${sel.id}" data-target="${esc(m.identifier)}"><i class="fa-solid fa-user-minus"></i></button></div></div>`).join('')}</div>
    </section>
    ${sel.log && sel.log.length ? `<section class="panel"><div class="p-head"><div><h2>Activity</h2><p>Newest first</p></div></div>
      <div class="p-body scroll" style="padding:4px 12px"><div class="log">${[...sel.log].reverse().slice(0, 20).map(logRow).join('')}</div></div></section>` : ''}`
    : emptyBox('fa-hand-pointer', 'Pick a squad', 'Choose one on the left to see its roster, rating and staff actions.');

  return `<div class="page">${head}
    <div class="cols">
      <div class="col"><section class="panel">
        <div class="p-head"><div><h2>All squads</h2><p>Most active first</p></div><span class="tally">${a.length}</span></div>
        <div class="p-body scroll" style="max-height:none">${rows}</div></section></div>
      <div class="col">${detail}</div>
    </div>
  </div>`;
}

// ─── team HUD ──────────────────────────────────────────────
function hudAccentColor(m) {
  const mode = state.settings.hudAccent;
  if (mode === 'none') return null;
  if (mode === 'teal') return '#08afa2';
  if (mode === 'health') {
    const h = ((m.id === state.me ? state.selfVitals : vit(m.id)) || { h: 100 }).h;
    return h <= 25 ? '#e5484d' : h <= 60 ? '#e5a50a' : '#08afa2';
  }
  return state.squad && state.squad.blipColor !== undefined ? blipHex(state.squad.blipColor) : '#08afa2';
}

function applyHudStyle() {
  const st = state.settings, hud = $('#hud'), root = document.documentElement;
  root.style.setProperty('--hud-health', st.hudHealth);
  root.style.setProperty('--hud-armor', st.hudArmor);
  root.style.setProperty('--hud-scale', (st.hudScale || 100) / 100);
  root.style.setProperty('--hud-bg', `rgba(8,9,10,${(st.hudOpacity ?? 86) / 100})`);
  hud.classList.toggle('min', !!st.hudMinimized);
  hud.classList.toggle('bars', st.hudStyle === 'bars');
  hud.classList.toggle('no-accent', st.hudAccent === 'none');
  if (st.hudPos && typeof st.hudPos.x === 'number') {
    Object.assign(hud.style, { left: `${st.hudPos.x}%`, top: `${st.hudPos.y}%`, right: 'auto', bottom: 'auto' });
  } else {
    Object.assign(hud.style, { left: '', top: '', right: '', bottom: '' });
  }
}

const armorBars = (a) => [0, 1, 2, 3].map((i) => `<span><i style="width:${Math.max(0, Math.min(25, a - i * 25)) * 4}%"></i></span>`).join('');

function hudCard(m, self) {
  const st = state.settings;
  const v = (self ? state.selfVitals : vit(m.id)) || { h: 100, a: 0 };
  const down = isDown(m);
  const accent = hudAccentColor(m);
  const meta = [];
  if (st.hudRank && m.rankName) meta.push(`<span class="hm-rank">${esc(m.rankName)}</span>`);
  if (st.hudKda) meta.push(`<span class="kda"><b class="k">${m.kills || 0}</b><s>/</s><b class="d">${m.deaths || 0}</b></span>`);
  return `<div class="hm ${down ? 'down' : ''} ${self ? 'self' : ''}" data-hm="${self ? 'self' : m.id}"${accent ? ` style="--accent:${accent}"` : ''}>
    ${st.hudAvatars ? avatar(m.name, m.avatar, state.talking[m.id] ? 'talk' : '') : ''}
    <div class="hm-txt">
      <div class="hm-top">${m.owner ? '<i class="fa-solid fa-crown"></i>' : ''}<b>${esc(m.name)}</b>${self ? '<span class="hm-you">You</span>' : ''}${meta.join('')}
        <span class="down-tag">Down</span><i class="fa-solid fa-microphone mic ${state.talking[m.id] && st.hudTalking ? 'on' : ''}"></i></div>
      <div class="hm-bars"><div class="hb"><i style="width:${v.h}%"></i></div>${st.hudArmorBar ? `<div class="ha">${armorBars(v.a)}</div>` : ''}</div>
    </div></div>`;
}

function renderHud() {
  const hud = $('#hud');
  const st = state.settings;
  if (!state.cfg) return;
  const others = online().filter((m) => m.id !== state.me);
  const me = myMember();
  const showSelf = st.hudShowSelf !== false && me;
  const show = feature('Hud') && st.hud && state.squad && (others.length || showSelf || state.editingHud) && (!state.hudHidden || state.editingHud);
  hud.classList.toggle('hidden', !show);
  if (!show) return;
  const max = st.hudMax > 0 ? st.hudMax : others.length;
  const list = others.slice(0, max);
  const extra = others.length - list.length;
  hud.innerHTML = (showSelf ? hudCard(me, true) : '') + list.map((m) => hudCard(m, false)).join('')
    + (extra > 0 ? `<div class="hud-more">+${extra} more</div>` : '');
}

function patchCard(card, v, m) {
  const hb = card.querySelector('.hb i'); if (hb) hb.style.width = `${v.h}%`;
  card.querySelectorAll('.ha span i').forEach((el, i) => { el.style.width = `${Math.max(0, Math.min(25, v.a - i * 25)) * 4}%`; });
  if (m) card.classList.toggle('down', isDown(m));
  if (state.settings.hudAccent === 'health') {
    const c = v.h <= 25 ? '#e5484d' : v.h <= 60 ? '#e5a50a' : '#08afa2';
    card.style.setProperty('--accent', c);
  }
}

function patchVitals(changed) {
  for (const id of Object.keys(changed)) {
    const m = state.squad.members.find((x) => String(x.id) === id);
    const card = document.querySelector(`[data-hm="${id}"]`);
    if (card && m) patchCard(card, changed[id], m);
    const row = document.querySelector(`[data-member="${id}"] .bar-mini i`);
    if (row) { row.style.width = `${changed[id].h}%`; row.classList.toggle('low', changed[id].h <= 25); }
  }
}

(() => {
  let drag = null;
  document.addEventListener('mousedown', (e) => {
    if (!state.editingHud) return;
    const hud = e.target.closest('#hud');
    if (!hud) return;
    const r = hud.getBoundingClientRect();
    drag = { dx: e.clientX - r.left, dy: e.clientY - r.top, w: r.width, h: r.height };
    e.preventDefault();
  });
  document.addEventListener('mousemove', (e) => {
    if (!drag) return;
    const x = Math.max(0, Math.min(window.innerWidth - drag.w, e.clientX - drag.dx));
    const y = Math.max(0, Math.min(window.innerHeight - drag.h, e.clientY - drag.dy));
    Object.assign($('#hud').style, { left: `${x}px`, top: `${y}px`, right: 'auto', bottom: 'auto' });
  });
  document.addEventListener('mouseup', () => {
    if (!drag) return;
    drag = null;
    const r = $('#hud').getBoundingClientRect();
    state.pendingHudPos = { x: +(r.left / window.innerWidth * 100).toFixed(2), y: +(r.top / window.innerHeight * 100).toFixed(2) };
  });
})();

function hudEdit(on, save) {
  state.editingHud = on;
  $('#panel').classList.toggle('hidden', on || !state.open);
  $('#hudEdit').classList.toggle('hidden', !on);
  $('#hud').classList.toggle('editing', on);
  if (on) { state.hudPrevPos = state.settings.hudPos; state.pendingHudPos = undefined; }
  else if (save) { if (state.pendingHudPos !== undefined) setSetting('hudPos', state.pendingHudPos, true); }
  else state.settings.hudPos = state.hudPrevPos;
  applyHudStyle();
  renderHud();
}

// ─── prompt card (invites, ready checks) ───────────────────
function renderPrompt() {
  const box = $('#promptBox');
  const p = state.prompt;
  if (!p) { box.innerHTML = ''; return; }
  const keys = `<div class="prompt-keys"><span class="yes"><span class="key">${esc(p.accept)}</span>Accept</span><span class="no"><span class="key">${esc(p.decline)}</span>Decline</span></div>`;
  if (p.kind === 'invite') {
    const d = p.data;
    box.innerHTML = `<div class="prompt"><div class="prompt-top">${avatar(d.from || d.name, d.fromAvatar || d.image)}
      <div><h4><i class="fa-solid fa-envelope"></i>Squad invite</h4><p>${esc(d.from)} invited you to <b style="color:var(--white);font-weight:500">${esc(d.name)}</b>${d.tag ? ` [${esc(d.tag)}]` : ''} · ${d.count}/${d.limit}${d.temporary ? ' · temporary' : ` · ${esc(tierOf(d.tier).name)}`}</p></div></div>
      ${keys}<div class="prompt-bar"><i style="--dur:${p.duration}s"></i></div></div>`;
    return;
  }
  if (p.kind === 'ready') {
    const d = p.data;
    const answers = state.readyAnswers || {};
    const members = online();
    const pills = members.length ? `<div class="ready-list">${members.map((m) => {
      const a = answers[String(m.id)];
      return `<span class="ready-pill ${a === true ? 'yes' : a === false ? 'no' : ''}"><i class="fa-solid ${a === true ? 'fa-check' : a === false ? 'fa-xmark' : 'fa-clock'}"></i>${esc(m.name)}</span>`;
    }).join('')}</div>` : '';
    const yes = Object.values(answers).filter(Boolean).length;
    if (p.done) {
      box.innerHTML = `<div class="prompt"><div class="prompt-top"><div class="av"><i class="fa-solid fa-list-check" style="color:var(--teal)"></i></div>
        <div><h4><i class="fa-solid fa-circle-check"></i>Ready check results</h4><p>${yes} of ${members.length} ready</p></div></div>${pills}</div>`;
      return;
    }
    box.innerHTML = `<div class="prompt"><div class="prompt-top"><div class="av"><i class="fa-solid fa-circle-check" style="color:var(--teal)"></i></div>
      <div><h4><i class="fa-solid fa-circle-check"></i>Ready check</h4><p>${esc(d.by)} is asking if the squad is good to go · ${yes} ready</p></div></div>
      ${p.answered === undefined ? keys : `<div class="ready-list" style="margin-top:10px"><span class="ready-pill ${p.answered ? 'yes' : 'no'}"><i class="fa-solid ${p.answered ? 'fa-check' : 'fa-xmark'}"></i>You said ${p.answered ? 'ready' : 'not yet'}</span></div>`}
      ${pills}<div class="prompt-bar"><i style="--dur:${p.duration}s"></i></div></div>`;
  }
}

// ─── killfeed & match result ───────────────────────────────
function killfeed(d) {
  const feed = $('#feed');
  const el = document.createElement('div');
  el.className = `feed-row ${d.good ? '' : 'bad'}`;
  el.innerHTML = `<b>${esc(d.killer)}</b><i class="fa-solid fa-skull"></i><b>${esc(d.victim)}</b>
    ${d.streak ? `<span class="streak"><i class="fa-solid fa-fire" style="font-size:8px"></i> ${d.streak}</span>` : ''}
    <span class="score">${d.score[0]} – ${d.score[1]}</span>`;
  feed.appendChild(el);
  while (feed.children.length > 5) feed.firstChild.remove();
  setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 180); }, 6000);
}

function matchResult(d) {
  const box = $('#matchBox');
  const color = d.result === 'win' ? '#08afa2' : d.result === 'loss' ? '#e5484d' : '#9ea5aa';
  box.innerHTML = `<div class="match" style="--tier:${color}">
    <h3>${d.result === 'win' ? 'Fight won' : d.result === 'loss' ? 'Fight lost' : 'Fight drawn'}</h3>
    <h2>vs ${esc(d.squad)}${d.tag ? ` [${esc(d.tag)}]` : ''}</h2>
    <p>${esc(d.tier)} · ${d.elo} ELO</p>
    <div class="match-score">
      <div><b>${d.kills}</b><span>Your kills</span></div>
      <div class="match-delta ${d.delta > 0 ? 'up' : d.delta < 0 ? 'down' : ''}">${d.delta > 0 ? '+' : ''}${d.delta}</div>
      <div><b>${d.enemyKills}</b><span>Their kills</span></div>
    </div></div>`;
  setTimeout(() => {
    const el = box.firstElementChild;
    if (el) { el.classList.add('out'); setTimeout(() => { box.innerHTML = ''; }, 220); }
  }, 7000);
}

// ─── compass ───────────────────────────────────────────────
const CP = { W: 520, PX: 3.2, target: 0, shown: 0, markers: [], built: false, running: false, visible: false, seen: false };
const CARDINALS = { 0: 'N', 45: 'NE', 90: 'E', 135: 'SE', 180: 'S', 225: 'SW', 270: 'W', 315: 'NW' };
const dirOf = (h) => ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'][Math.round(h / 45) % 8];

function buildCompass() {
  if (CP.built) return;
  CP.built = true;
  const out = [];
  for (let lap = 0; lap < 3; lap++) {
    for (let d = 0; d < 360; d += 5) {
      const x = (lap * 360 + d) * CP.PX;
      const card = CARDINALS[d];
      out.push(`<div class="cp-t ${card ? 'big' : d % 15 === 0 ? 'mid' : 'min'}" style="left:${x}px"></div>`);
      if (card) out.push(`<div class="cp-l ${card.length === 1 ? 'card' : 'inter'} ${card === 'N' ? 'n' : ''}" style="left:${x}px">${card}</div>`);
      else if (d % 15 === 0) out.push(`<div class="cp-l" style="left:${x}px">${d}</div>`);
    }
  }
  $('#cpStrip').innerHTML = out.join('');
}

const shortest = (from, to) => ((to - from + 540) % 360) - 180;

function compassFrame() {
  if (!CP.visible) { CP.running = false; return; }
  const delta = shortest(CP.shown, CP.target);
  CP.shown = Math.abs(delta) < 0.05 ? CP.target : (CP.shown + delta * 0.35 + 360) % 360;
  $('#cpStrip').style.transform = `translateX(${CP.W / 2 - (360 + CP.shown) * CP.PX}px)`;
  const h = Math.round(CP.shown) % 360;
  $('#cpDir').textContent = dirOf(h);
  $('#cpDeg').textContent = `${h}°`;
  const half = CP.W / 2 / CP.PX - 4;
  const box = $('#cpMarks');
  CP.markers.forEach((m, i) => {
    const el = box.children[i];
    if (!el) return;
    const rel = shortest(CP.shown, m.b);
    const edge = Math.abs(rel) > half;
    el.style.left = `${edge ? (rel < 0 ? 6 : CP.W - 6) : CP.W / 2 + rel * CP.PX}px`;
    el.classList.toggle('edge', edge);
    el.classList.toggle('left', edge && rel < 0);
    el.classList.toggle('right', edge && rel > 0);
  });
  requestAnimationFrame(compassFrame);
}

function setCompassVisible(on) {
  CP.visible = on && state.settings.compass !== false;
  $('#compass').classList.toggle('hidden', !CP.visible);
  if (CP.visible) {
    buildCompass();
    if (!CP.running) { CP.running = true; requestAnimationFrame(compassFrame); }
  }
}

function renderCompassMarkers() {
  $('#cpMarks').innerHTML = CP.markers.map((m) => {
    const dist = m.d >= 1000 ? `${(m.d / 1000).toFixed(1)}km` : `${m.d}m`;
    return `<div class="cp-m ${esc(m.k)}" style="--mc:${esc(m.c)}"><i></i><span>${dist}</span></div>`;
  }).join('');
}

function compassUpdate(d) {
  if (d.show !== undefined) setCompassVisible(d.show);
  if (typeof d.h === 'number') {
    if (!CP.seen) { CP.shown = d.h; CP.seen = true; }
    CP.target = d.h;
  }
  if (d.markers) { CP.markers = d.markers; renderCompassMarkers(); }
  if (d.street !== undefined) {
    const el = $('#cpStreet');
    if (!d.street) { el.innerHTML = ''; return; }
    el.innerHTML = `${esc(d.street)}${d.cross ? `<em>/</em>${esc(d.cross)}` : ''}${d.zone ? `<em>·</em>${esc(d.zone)}` : ''}`;
  }
}

// ─── ping wheel ────────────────────────────────────────────
const wheel = { open: false, hover: null };
const wash = (hex, a) => { const n = parseInt(hex.slice(1), 16); return `rgba(${n >> 16},${(n >> 8) & 255},${n & 255},${a})`; };

function arcPath(cx, cy, r1, r2, a0, a1) {
  const p = (r, a) => [cx + r * Math.cos(a), cy + r * Math.sin(a)];
  const [x0, y0] = p(r2, a0), [x1, y1] = p(r2, a1), [x2, y2] = p(r1, a1), [x3, y3] = p(r1, a0);
  const large = a1 - a0 > Math.PI ? 1 : 0;
  return `M${x0} ${y0}A${r2} ${r2} 0 ${large} 1 ${x1} ${y1}L${x2} ${y2}A${r1} ${r1} 0 ${large} 0 ${x3} ${y3}Z`;
}

function openWheel(on) {
  const el = $('#wheel');
  wheel.open = on; wheel.hover = null;
  el.classList.toggle('hidden', !on);
  if (!on) { el.innerHTML = ''; return; }
  const types = state.cfg.wheel, n = types.length, step = (Math.PI * 2) / n, gap = 0.035;
  const segs = types.map((t, i) => {
    const a0 = -Math.PI / 2 - step / 2 + i * step + gap, a1 = a0 + step - gap * 2, mid = (a0 + a1) / 2;
    const col = state.cfg.pings[t].color;
    return { t, col, path: arcPath(150, 150, 62, 146, a0, a1), ix: 150 + 104 * Math.cos(mid), iy: 150 + 104 * Math.sin(mid) };
  });
  el.innerHTML = `<div class="wheel-ring">
    <svg viewBox="0 0 300 300">${segs.map((s) => `<path class="seg-arc" data-seg="${s.t}" style="--seg:${s.col};--segfill:${wash(s.col, 0.2)}" d="${s.path}"/>`).join('')}</svg>
    ${segs.map((s) => `<div class="seg-ico" data-ico="${s.t}" style="left:${s.ix}px;top:${s.iy}px;--seg:${s.col}"><i class="fa-solid ${state.cfg.pings[s.t].icon}"></i></div>`).join('')}
    <div class="wheel-core"><b id="wheelLabel">Ping</b><span>Release to place</span></div></div>`;
}

function wheelHover(e) {
  const ring = $('.wheel-ring'); if (!ring) return;
  const r = ring.getBoundingClientRect();
  const dx = e.clientX - (r.left + r.width / 2), dy = e.clientY - (r.top + r.height / 2);
  const types = state.cfg.wheel;
  let hover = null;
  if (Math.hypot(dx, dy) > 40) {
    let a = Math.atan2(dy, dx) + Math.PI / 2 + Math.PI / types.length;
    a = (a + Math.PI * 2) % (Math.PI * 2);
    hover = types[Math.floor(a / ((Math.PI * 2) / types.length)) % types.length];
  }
  if (hover === wheel.hover) return;
  wheel.hover = hover;
  document.querySelectorAll('[data-seg]').forEach((s) => s.classList.toggle('on', s.dataset.seg === hover));
  document.querySelectorAll('[data-ico]').forEach((s) => s.classList.toggle('on', s.dataset.ico === hover));
  $('#wheelLabel').textContent = hover ? state.cfg.pings[hover].label : 'Ping';
}

function wheelFinish(select) {
  if (!wheel.open) return;
  const type = select ? wheel.hover : null;
  openWheel(false);
  nui(type ? 'wheelSelect' : 'wheelCancel', { type });
}
document.addEventListener('mousemove', (e) => { if (wheel.open) wheelHover(e); });
document.addEventListener('mouseup', (e) => { if (wheel.open) wheelFinish(e.button !== 2); });
document.addEventListener('contextmenu', (e) => e.preventDefault());

// ─── actions ───────────────────────────────────────────────
async function refreshList() {
  const r = await nui('refresh');
  if (r) { state.list = r.list; state.invites = r.invites; state.myRequests = r.myRequests || []; if (r.status) state.status = r.status; }
  if (['browse', 'preview', 'allies'].includes(state.view)) render(); else renderChrome();
}
async function loadStats() { state.stats = await nui('stats'); if (state.view === 'stats') render(); }
async function loadBoard() { state.board = await nui('leaderboard'); if (state.view === 'board') render(); }
async function loadAdmin() { state.admin = await nui('adminList'); if (parentView(state.view) === 'admin') render(); }

async function joinSquad(id, password) {
  const r = await nui('join', { id, password });
  if (result(r, 'You joined the squad')) {
    state.invites = state.invites.filter((i) => i.id !== id);
    state.view = 'squad';
  }
}

async function rankMenu(identifier) {
  const s = state.squad;
  const m = s.members.find((x) => x.identifier === identifier);
  if (!m) return;
  const mine = s.you.rank;
  const options = s.ranks.map((r, i) => ({ value: i + 1, label: r.name, icon: r.icon }))
    .filter((r) => r.value < s.ranks.length && (mine >= s.ranks.length || r.value < mine) && r.value !== m.rank).reverse();
  if (!options.length) return notify('There is no rank you can move them to', 'error');
  const picked = await confirmModal({ title: `Change rank for ${m.name}`, text: `Currently ${m.rankName}. Pick the new rank.`, confirm: 'Set rank', danger: false, icon: 'fa-arrow-up-right-dots', options });
  if (picked === false) return;
  result(await nui('setRank', { identifier, rank: Number(picked) }), `${m.name} is now ${s.ranks[Number(picked) - 1].name}`);
}

function enterTabs(tab) {
  if (tab === 'create' || tab === 'edit') state.form = null;
  if (tab === 'ranks') state.ranksDraft = null;
  if (tab === 'stats') loadStats();
  if ((tab === 'allies' || tab === 'browse') && !state.list) refreshList();
  if (tab === 'board' && !state.board) loadBoard();
  if (tab === 'admin' && !state.admin) loadAdmin();
  go(tab);
}

document.addEventListener('click', async (e) => {
  const t = e.target.closest('button, [data-preview], [data-set], [data-ftoggle], [data-rperm], [data-adminsquad], .swatch');
  if (e.target.closest('.range')) return;
  if (!t || t.closest('#modal')) return;
  const d = t.dataset;

  if (d.ready !== undefined) { nui('readyAnswer', { answer: d.ready === '1' }); return; }
  if (d.tab) return enterTabs(d.tab);
  if (d.board) { state.boardTab = d.board; state.boardSort = d.board === 'squads' ? 'elo' : 'kills'; return render(); }
  if (d.bsort) { state.boardSort = d.bsort; return render(); }
  if (d.ssort) { state.statsSort = d.ssort; return render(); }
  if (d.bfilter) { state.browseFilter = d.bfilter; return render(); }
  if (d.mfilter) { state.memberFilter = d.mfilter; return render(); }
  if (d.preview) { state.preview = Number(d.preview); return go('preview'); }
  if (d.adminsquad) { state.adminOpen = Number(d.adminsquad); return render(); }
  if (d.join) return joinSquad(Number(d.join), $('#joinPass')?.value || undefined);
  if (d.accept) return joinSquad(Number(d.accept));
  if (d.decline) {
    const id = Number(d.decline);
    state.invites = state.invites.filter((i) => i.id !== id);
    nui('declineInvite', { id }); return render();
  }
  if (d.askjoin) {
    const sq = (state.list || []).find((x) => x.id === Number(d.askjoin));
    if (!sq) return;
    const msg = await confirmModal({ title: `Ask to join ${sq.name}?`, text: 'An officer sees your request in their menu and can let you in. Add a short note if you like.', confirm: 'Send request', danger: false, icon: 'fa-user-plus', input: { placeholder: 'Optional note', max: state.cfg.requests.messageMax } });
    if (msg === false) return;
    if (result(await nui('requestJoin', { id: sq.id, message: msg }))) { state.myRequests = [...state.myRequests, sq.id]; render(); }
    return;
  }
  if (d.cancelreq) {
    if (result(await nui('cancelRequest', { id: Number(d.cancelreq) }))) { state.myRequests = state.myRequests.filter((x) => x !== Number(d.cancelreq)); render(); }
    return;
  }
  if (d.reqyes) return result(await nui('respondRequest', { identifier: d.reqyes, accept: true }));
  if (d.reqno) return result(await nui('respondRequest', { identifier: d.reqno, accept: false }));
  if (d.step && state.form) {
    state.form.limit = Math.max(state.cfg.minMembers, Math.min(state.cfg.maxMembers, state.form.limit + Number(d.step)));
    $('#fLimit').textContent = state.form.limit; return;
  }
  if (d.ftoggle && state.form) { state.form[d.ftoggle] = !state.form[d.ftoggle]; return render(); }
  if (d.ftype !== undefined && state.form) { state.form.temporary = d.ftype === '1'; return render(); }
  if (d.fblip !== undefined && state.form) { state.form.blipColor = Number(d.fblip); return render(); }
  if (d.fsprite !== undefined && state.form) { state.form.blipSprite = Number(d.fsprite); return render(); }
  if (d.set) return setSetting(d.set, !state.settings[d.set]);
  if (d.pick) return setSetting(d.pick, d.val);
  if (d.color) { const raw = d.val; return setSetting(d.color, /^\d+$/.test(raw) ? Number(raw) : raw); }

  if (d.rperm) { const r = state.ranksDraft[Number(d.rperm)]; r.perms = r.perms || {}; r.perms[d.perm] = !r.perms[d.perm]; return render(); }
  if (d.ricon) { state.ranksDraft[Number(d.ricon)].icon = d.icon; return render(); }
  if (d.rup) { const i = Number(d.rup); const a = state.ranksDraft; [a[i], a[i + 1]] = [a[i + 1], a[i]]; return render(); }
  if (d.rdown) { const i = Number(d.rdown); const a = state.ranksDraft; [a[i], a[i - 1]] = [a[i - 1], a[i]]; return render(); }
  if (d.rdel) { state.ranksDraft.splice(Number(d.rdel), 1); return render(); }

  if (d.kick) {
    const m = state.squad.members.find((x) => x.identifier === d.kick);
    if (m && await confirmModal({ title: `Remove ${m.name}?`, text: 'They leave the squad right away and lose their place on the roster.', confirm: 'Remove member' })) {
      result(await nui('kick', { identifier: m.identifier }), `${m.name} was removed`);
    }
    return;
  }
  if (d.allyask) {
    const sq = (state.list || []).find((x) => x.id === Number(d.allyask));
    if (sq && await confirmModal({ title: `Ally with ${sq.name}?`, text: 'They have to accept before the alliance starts. Allied squads see each other, cannot hurt each other, and never take ELO off one another.', confirm: 'Send request', danger: false, icon: 'fa-handshake' })) {
      result(await nui('allyRequest', { id: sq.id }));
    }
    return;
  }
  if (d.allyyes) return result(await nui('allyRespond', { id: Number(d.allyyes), accept: true }));
  if (d.allyno) return result(await nui('allyRespond', { id: Number(d.allyno), accept: false }));
  if (d.allyend) {
    const a = (state.squad.allies || []).find((x) => x.id === Number(d.allyend));
    if (a && await confirmModal({ title: `End the alliance with ${a.name}?`, text: 'Both squads stop seeing each other, and friendly fire comes back on.', confirm: 'End alliance' })) {
      result(await nui('allyRemove', { id: a.id }));
    }
    return;
  }
  if (d.nick) {
    const meRec = myMember() || {};
    const nk = state.cfg.nicknames || {};
    const value = await confirmModal({ title: 'Your squad nickname', text: `What your squad sees instead of your character name on the HUD, nametags, map and chat. ${nk.min || 2}–${nk.max || 20} characters. Leave it blank to go back to ${meRec.realName || 'your name'}.`,
      confirm: 'Save nickname', danger: false, icon: 'fa-signature', input: { placeholder: meRec.realName || 'Nickname', value: meRec.nick || '', max: nk.max || 20 } });
    if (value === false) return;
    return result(await nui('setNick', { nick: value }));
  }
  if (d.nickreset) {
    const m = state.squad.members.find((x) => x.identifier === d.nickreset);
    if (m && await confirmModal({ title: `Reset ${m.name}'s nickname?`, text: `They go back to showing as ${m.realName}.`, confirm: 'Reset nickname' })) {
      result(await nui('setNick', { nick: '', identifier: m.identifier }));
    }
    return;
  }
  if (d.rankmenu) return rankMenu(d.rankmenu);
  if (d.transfer) {
    const m = state.squad.members.find((x) => x.identifier === d.transfer);
    if (m && await confirmModal({ title: `Hand the squad to ${m.name}?`, text: 'They become the owner and you drop to the rank below. Only they can hand it back.', confirm: 'Transfer ownership', danger: false, icon: 'fa-crown' })) {
      result(await nui('transfer', { identifier: m.identifier }), `${m.name} now owns the squad`);
    }
    return;
  }

  if (d.admin) {
    const squadId = Number(d.sq);
    let value;
    if (d.admin === 'disband' && !await confirmModal({ title: 'Force disband this squad?', text: 'Everyone is removed and the squad is deleted from the database.', confirm: 'Disband squad' })) return;
    if (d.admin === 'resetStats' && !await confirmModal({ title: 'Reset this squad\'s stats?', text: 'ELO, wins, losses and every member\'s K/D/A go back to zero.', confirm: 'Reset stats' })) return;
    if (d.admin === 'seasonReset' && !await confirmModal({ title: 'Start a new season?', text: 'Every saved squad goes back to the starting rating with zero wins, losses, kills, deaths and assists. Match history stays.', confirm: 'Reset every squad' })) return;
    if (d.admin === 'setElo') {
      value = await confirmModal({ title: 'Set squad ELO', text: 'Enter the new rating for this squad.', confirm: 'Set rating', danger: false, icon: 'fa-sliders', input: { placeholder: '1000', value: '1000', numeric: true } });
      if (value === false) return;
    }
    if (d.admin === 'rename') {
      value = await confirmModal({ title: 'Rename squad', text: 'Enter the new squad name. Members are told about the change.', confirm: 'Rename', danger: false, icon: 'fa-pen', input: { placeholder: 'New name', max: state.cfg.nameMax } });
      if (value === false) return;
    }
    const r = await nui('adminAction', { action: d.admin, squadId, target: d.target, value });
    if (result(r, 'Done')) { if (d.admin === 'disband') state.adminOpen = null; await loadAdmin(); }
    return;
  }

  switch (d.act) {
    case 'close': return nui('close');
    case 'refresh': state.list = null; render(); return refreshList();
    case 'refreshStats': state.stats = null; render(); return loadStats();
    case 'refreshBoard': state.board = null; render(); return loadBoard();
    case 'refreshAdmin': state.admin = null; render(); return loadAdmin();
    case 'create': case 'saveEdit': return submitForm();
    case 'send': return sendChat();
    case 'waypoint': return nui('shareWaypoint');
    case 'readyCheck': return result(await nui('readyCheck'), 'Ready check sent');
    case 'rally': return result(await nui('rally', {}), 'Rally point set');
    case 'rallyClear': return result(await nui('rally', { clear: true }), 'Rally point cleared');
    case 'motd': {
      const value = await confirmModal({ title: 'Message of the day', text: `Shown on the overview and to members when they join. Up to ${state.cfg.motdMax} characters, blank clears it.`, confirm: 'Save message', danger: false, icon: 'fa-message', input: { placeholder: 'Rolling at 9 — bring armour', value: state.squad.motd || '', max: state.cfg.motdMax } });
      if (value === false) return;
      return result(await nui('setMotd', { motd: value }));
    }
    case 'addRank': state.ranksDraft.splice(state.ranksDraft.length - 1, 0, { name: 'New rank', icon: 'fa-user', perms: {} }); return render();
    case 'resetRanks': state.ranksDraft = null; return render();
    case 'saveRanks':
      if (result(await nui('setRanks', { ranks: state.ranksDraft }), 'Ranks saved')) { state.ranksDraft = null; go('squad'); }
      return;
    case 'invite': {
      const id = Number($('#inviteId')?.value);
      if (!id) return notify('Enter the server ID of the player you want to invite', 'error');
      if (result(await nui('invite', { id }))) $('#inviteId').value = '';
      return;
    }
    case 'leave': {
      const s = state.squad;
      if (!s) return;
      if (s.persistent) {
        const stay = await confirmModal({ title: 'Leave this squad?', text: 'You stay on the roster and keep your rank and stats, so you can rejoin later. To give up your place for good, pick "Leave for good".', confirm: 'Leave for now', danger: false, icon: 'fa-right-from-bracket', options: [{ value: 'soft', label: 'Leave for now, keep my place', icon: 'fa-door-open' }, { value: 'hard', label: 'Leave for good, drop off the roster', icon: 'fa-user-minus' }] });
        if (stay === false) return;
        result(await nui('leave', { forget: stay === 'hard' }));
      } else if (await confirmModal({ title: 'Leave this squad?', text: 'You can rejoin later if the squad is still open.', confirm: 'Leave squad' })) {
        result(await nui('leave', { forget: true }));
      }
      return;
    }
    case 'disband':
      if (await confirmModal({ title: 'Disband the squad?', text: 'Every member is removed and the squad, its ranks, its log and its rating are deleted. This cannot be undone.', confirm: 'Disband squad' })) {
        result(await nui('disband'), 'Squad disbanded');
      }
      return;
    case 'resetSettings':
      if (await confirmModal({ title: 'Reset your settings?', text: 'HUD, nametag, blip and alert settings go back to the server defaults.', confirm: 'Reset settings' })) {
        state.settings = { ...state.cfg.defaults }; nui('saveSettings', state.settings); applyHudStyle(); renderHud(); render();
      }
      return;
    case 'hudMove': return hudEdit(true);
    case 'hudSave': return hudEdit(false, true);
    case 'hudCancel': return hudEdit(false, false);
    case 'hudReset': state.pendingHudPos = false; state.settings.hudPos = false; applyHudStyle(); return;
  }
});

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    if (wheel.open) return wheelFinish(false);
    if (state.editingHud) return hudEdit(false, false);
    if (state.modalClose) return state.modalClose();
    if (state.open) return nui('close');
  }
  if (e.key === 'Tab' && state.open && !state.editingHud) {
    e.preventDefault();
    const tabs = allViews();
    const cur = parentView(state.view);
    enterTabs(tabs[(tabs.indexOf(cur) + (e.shiftKey ? tabs.length - 1 : 1)) % tabs.length]);
  }
});

setInterval(() => {
  if (!state.open) return;
  const el = document.querySelector('[data-since]'); if (el) el.textContent = since(Number(el.dataset.since));
  const c = document.querySelector('.head .clock'); if (c) c.outerHTML = nowClock();
}, 30000);

// ─── messages from Lua ─────────────────────────────────────
const handlers = {
  open({ squad, view }) {
    state.open = true;
    state.squad = squad || null;
    state.view = view || (state.squad ? (['chat', 'members'].includes(state.view) ? state.view : 'squad') : 'browse');
    state.list = null;
    if (state.view === 'stats') loadStats();
    if (state.view === 'admin') loadAdmin();
    $('#panel').classList.remove('hidden');
    render();
    renderHud();
  },
  close() {
    state.open = false;
    if (state.editingHud) hudEdit(false, false);
    $('#panel').classList.add('hidden');
    $('#modal').classList.add('hidden');
    state.modalClose = null;
    renderHud();
  },
  adminUnlock() { state.isAdmin = true; if (state.open) renderChrome(); },
  profile(p) { state.profile = p; if (p && p.staff) state.isAdmin = true; if (state.open) renderChrome(); },
  list({ list, invites, status, myRequests }) {
    state.list = list; state.invites = invites; state.myRequests = myRequests || [];
    if (status) state.status = status;
    if (state.open) { if (['browse', 'preview', 'allies'].includes(state.view)) render(); else renderChrome(); }
  },
  listUpdate(list) {
    state.list = list;
    if (!state.open) return;
    if (state.view === 'browse') {
      const focused = document.activeElement && document.activeElement.id === 'search';
      if (!focused) render(); else renderChrome();
    } else if (['preview', 'allies'].includes(state.view)) render(); else renderChrome();
  },
  squad(sq) {
    const prevId = state.squad && state.squad.id;
    state.squad = sq || null;
    if (!sq) { state.chat = []; state.unread = 0; state.talking = {}; state.stats = null; state.readyAnswers = null; }
    if (sq && prevId !== sq.id) { state.unread = 0; state.stats = null; }
    if (sq && sq.ready) state.readyAnswers = sq.ready.answers;
    renderHud();
    if (state.prompt && state.prompt.kind === 'ready') renderPrompt();
    if (!state.open) return;
    if (!sq && ['squad', 'members', 'chat', 'edit', 'ranks', 'stats', 'allies', 'activity'].includes(state.view)) { state.view = 'browse'; refreshList(); }
    if (state.view === 'ranks' || state.view === 'edit') { renderChrome(); if (!sq) render(); return; }
    if (state.view === 'chat') renderChrome(); else render();
  },
  chatHistory(list) { state.chat = list || []; if (state.open && state.view === 'chat') render(); },
  chat(msg) {
    state.chat.push(msg);
    if (state.chat.length > 80) state.chat.shift();
    if (state.open && state.view === 'chat') appendChat(msg);
    else if (!msg.system && msg.from !== state.me) { state.unread++; if (state.open) renderChrome(); }
  },
  vitals(changed) {
    if (!state.squad) return;
    state.squad.vitals = state.squad.vitals || {};
    Object.assign(state.squad.vitals, changed);
    patchVitals(changed);
  },
  downed({ id, state: down }) {
    if (!state.squad) return;
    const m = state.squad.members.find((x) => x.id === id);
    if (m) m.downed = down;
    renderHud();
    if (state.open && ['squad', 'members'].includes(state.view)) render(); else if (state.open) renderChrome();
  },
  talking(diff) {
    for (const id of Object.keys(diff)) {
      state.talking[id] = diff[id];
      const card = document.querySelector(`[data-hm="${Number(id) === state.me ? 'self' : id}"]`);
      if (card) {
        card.querySelector('.av')?.classList.toggle('talk', diff[id]);
        card.querySelector('.mic')?.classList.toggle('on', diff[id]);
      }
    }
  },
  hudHidden(v) { state.hudHidden = v; renderHud(); },
  selfVitals(v) {
    state.selfVitals = v;
    const card = document.querySelector('[data-hm="self"]');
    if (!card) return renderHud();
    patchCard(card, v, null);
  },
  invite(inv) {
    state.invites = [inv, ...state.invites.filter((i) => i.id !== inv.id)];
    if (state.open) { if (state.view === 'browse') render(); else renderChrome(); }
  },
  prompt(d) {
    if (!d) { state.prompt = null; renderPrompt(); return; }
    if (d.kind === 'ready' && d.answered !== undefined && state.prompt && state.prompt.kind === 'ready') {
      state.prompt.answered = d.answered;
    } else {
      state.prompt = { kind: d.kind, data: d.data, duration: d.duration, accept: d.accept || (state.cfg && state.cfg.prompts.accept), decline: d.decline || (state.cfg && state.cfg.prompts.decline), answered: d.answered };
      if (d.kind === 'ready') state.readyAnswers = {};
    }
    renderPrompt();
  },
  readyCheck() { state.readyAnswers = {}; },
  readyProgress(answers) {
    state.readyAnswers = answers || {};
    if (state.squad && state.squad.ready) state.squad.ready.answers = state.readyAnswers;
    renderPrompt();
    if (state.open && state.view === 'squad') render();
  },
  readyResult(answers) {
    state.readyAnswers = answers || {};
    state.prompt = { kind: 'ready', data: {}, done: true };
    renderPrompt();
    setTimeout(() => { if (state.prompt && state.prompt.done) { state.prompt = null; renderPrompt(); } }, 6000);
  },
  wheel(on) { openWheel(on); },
  wheelRelease() { wheelFinish(true); },
  compass(d) { compassUpdate(d); },
  killfeed(d) { if (state.settings.killfeed !== false) killfeed(d); },
  matchResult(d) {
    if (state.settings.matchBanner !== false) matchResult(d);
    if (state.open && state.view === 'stats') loadStats();
  },
};

window.addEventListener('message', (e) => {
  const { action, data } = e.data || {};
  if (handlers[action]) handlers[action](data);
});

// ─── boot ──────────────────────────────────────────────────
async function boot() {
  const r = await nui('ready');
  if (!r) return setTimeout(boot, 500);
  state.cfg = r.config; state.me = r.me; state.settings = r.settings; state.squad = r.squad || null; state.chat = r.chat || [];
  $('#ver').textContent = `v${state.cfg.version}`;
  applyHudStyle();
  renderHud();
}

// ─── browser preview (only outside FiveM) ──────────────────
const Dev = {
  squad: null,
  tiers: [{ name: 'Bronze', min: 0, color: '#b4713d' }, { name: 'Silver', min: 900, color: '#9aa4ab' }, { name: 'Gold', min: 1100, color: '#e5a50a' },
          { name: 'Platinum', min: 1300, color: '#4fd1ff' }, { name: 'Diamond', min: 1500, color: '#a078ff' }, { name: 'Elite', min: 1750, color: '#08afa2' }],
  ranks: [{ name: 'Recruit', icon: 'fa-user', perms: {} }, { name: 'Member', icon: 'fa-user-check', perms: { invite: true, ready: true } },
          { name: 'Officer', icon: 'fa-user-shield', perms: { invite: true, kick: true, ready: true, rally: true, motd: true } },
          { name: 'Leader', icon: 'fa-crown', perms: { invite: true, kick: true, promote: true, edit: true, ranks: true, ready: true, rally: true, motd: true, disband: true } }],
  handle(name, data) {
    const t = Date.now() / 1000;
    switch (name) {
      case 'ready': return {
        me: 1, squad: null, chat: [],
        settings: { hud: true, hudMinimized: false, hudTalking: true, hudKda: true, hudMax: 0, hudHealth: '#ffffff', hudArmor: '#58a6ff', hudPos: false, hudAvatars: true, hudRank: false,
          hudArmorBar: true, hudAccent: 'squad', hudStyle: 'cards', hudScale: 100, hudOpacity: 86, hudShowSelf: true, animatedAvatars: true,
          tags: true, tagColor: 18, tagName: true, tagSquadTag: true, tagRole: true, tagHealth: true, tagAllies: true,
          blips: true, blipUseSquad: true, blipColor: 2, blipAllies: true, quiet: false, chatNotify: true, chatSound: true, pingNotify: true, pingSound: true,
          reviveAlerts: true, killfeed: true, matchBanner: true, requestNotify: true, radio: true, compass: true, compassStreet: true, compassMarkers: true },
        config: {
          version: '3.0.0', maxMembers: 8, minMembers: 2, nameMin: 3, nameMax: 24, tagMin: 2, tagMax: 4, descriptionMax: 120, motdMax: 200,
          chatMax: 180, maxRanks: 6, voice: true, eloStart: 1000, autoRadio: true, compass: true, command: 'squads',
          commands: { Chat: 'sq', Invite: 'sqinvite', Leave: 'sqleave' }, prompts: { accept: 'Y', decline: 'U' }, reviveKey: 'G',
          features: { Hud: true, Tags: true, Blips: true, Pings: true, Waypoint: true, Relations: true, Combat: true, Revive: true, ReadyCheck: true, Rally: true,
            DownedAlert: true, Leaderboard: true, Affiliations: true, SquadBlips: true, AutoRadio: true, ActivityLog: true, Killfeed: true, MatchBanner: true, Compass: true },
          squadTypes: { temporary: true, permanent: true, default: 'permanent', tempHours: 6 },
          blipSprites: [{ id: 1, label: 'Dot', icon: 'fa-circle' }, { id: 480, label: 'Skull', icon: 'fa-skull' }, { id: 303, label: 'Target', icon: 'fa-crosshairs' },
            { id: 487, label: 'Shield', icon: 'fa-shield-halved' }, { id: 491, label: 'Star', icon: 'fa-star' }, { id: 310, label: 'Crown', icon: 'fa-crown' }],
          blipHex: { 0: '#ffffff', 1: '#e5484d', 2: '#4cd964', 3: '#2f95dc', 5: '#e5a50a', 8: '#ff7ad9', 17: '#ff9a3c', 25: '#8bd35a', 27: '#a078ff', 38: '#4fd1ff', 40: '#9aa4ab', 48: '#08afa2' },
          squadBlipColors: [2, 3, 1, 5, 27, 38, 0, 8, 17, 25, 48, 40],
          allyMax: 2, nicknames: { enabled: true, max: 20, min: 2, temp: true }, requests: { enabled: true, messageMax: 80 },
          nametag: { Name: true, Tag: true, Role: true, Health: true, Allies: true },
          tagColors: [['#72cc72', 18], ['#e5484d', 6], ['#58a6ff', 9], ['#e5a50a', 12], ['#a078ff', 21], ['#ffffff', 0]],
          rankIcons: ['fa-user', 'fa-user-check', 'fa-user-shield', 'fa-user-tie', 'fa-crown', 'fa-star', 'fa-shield-halved', 'fa-gun', 'fa-kit-medical', 'fa-car-side'],
          perms: [{ key: 'invite', label: 'Invite players and answer join requests' }, { key: 'kick', label: 'Remove members' }, { key: 'promote', label: 'Change member ranks' },
                  { key: 'edit', label: 'Edit squad details' }, { key: 'motd', label: 'Set the message of the day' }, { key: 'ranks', label: 'Manage ranks' },
                  { key: 'rally', label: 'Set rally points' }, { key: 'ready', label: 'Start ready checks' }, { key: 'disband', label: 'Disband the squad' }],
          tiers: Dev.tiers,
          pings: { go: { label: 'Go here', icon: 'fa-location-arrow', color: '#08afa2' }, enemy: { label: 'Enemy', icon: 'fa-crosshairs', color: '#e5484d' },
                   danger: { label: 'Danger', icon: 'fa-triangle-exclamation', color: '#e5a50a' }, loot: { label: 'Loot', icon: 'fa-box-open', color: '#ffffff' },
                   defend: { label: 'Defend', icon: 'fa-shield-halved', color: '#58a6ff' }, vehicle: { label: 'Vehicle', icon: 'fa-car-side', color: '#a078ff' } },
          wheel: ['go', 'enemy', 'danger', 'loot', 'defend', 'vehicle'], defaults: {},
        },
      };
      case 'profile': return { name: 'NayZeee', avatar: null, staff: true };
      case 'notify': console.log('[notify]', data.kind, data.text); return 1;
      case 'refresh': return { status: { permanent: true }, list: Dev.list, myRequests: Dev.squad ? [] : [4],
        invites: Dev.squad ? [] : [{ id: 9, name: 'Grove Runners', tag: 'GRV', from: 'Dre Walker', owner: 'Dre Walker', count: 3, limit: 6, elo: 1040, tier: { name: 'Gold', color: '#e5a50a' } }] };
      case 'checkName': return { ok: String(data.name).toLowerCase() !== 'ballas', msg: 'That name is taken' };
      case 'create': case 'join': {
        Dev.squad = Dev.makeSquad(data && data.name, data && data.temporary);
        setTimeout(() => {
          handlers.squad(Dev.squad);
          handlers.chatHistory([{ system: true, text: 'NayZeee created the squad', t: t - 1500 }, { from: 14, name: 'Tay', rank: 'Officer', text: 'pull up to legion, got the car', t: t - 60 }]);
        }, 50);
        return { ok: true };
      }
      case 'stats': return { members: Dev.squad ? Dev.squad.members : [], active: [{ squad: 'Ballas', tag: 'BLS', elo: 1420, mine: 3, theirs: 1, since: t - 180, last: t - 40 }],
        history: [{ squad_a: 1, squad_b: 4, name_a: 'Southside Crew', name_b: 'Paleto Hunters', kills_a: 5, kills_b: 2, delta_a: 21, delta_b: -21, ended: t - 3600 },
          { squad_a: 3, squad_b: 1, name_a: 'Vinewood Night Shift', name_b: 'Southside Crew', kills_a: 4, kills_b: 3, delta_a: 18, delta_b: -14, ended: t - 9000 }] };
      case 'leaderboard': return { persistent: true, squads: Dev.board, players: Dev.players };
      case 'adminList': return Dev.adminList();
      case 'chat': setTimeout(() => handlers.chat({ from: 1, name: 'NayZeee', rank: 'Leader', text: data.text, t }), 30); return { ok: true };
      case 'leave': case 'disband': setTimeout(() => handlers.squad(null), 30); Dev.squad = null; return { ok: true };
      case 'setRanks': if (Dev.squad) { Dev.squad.ranks = data.ranks; setTimeout(() => handlers.squad(Dev.squad), 30); } return { ok: true };
      case 'setMotd': if (Dev.squad) { Dev.squad.motd = data.motd || null; setTimeout(() => handlers.squad(Dev.squad), 30); } return { ok: true, msg: 'Message updated' };
      case 'readyCheck':
        setTimeout(() => { handlers.prompt({ kind: 'ready', data: { by: 'NayZeee', duration: 20 }, duration: 20, accept: 'Y', decline: 'U', answered: true }); handlers.readyProgress({ 1: true, 14: true }); }, 40);
        return { ok: true };
      case 'respondRequest': if (Dev.squad) { Dev.squad.requests = Dev.squad.requests.filter((r) => r.identifier !== data.identifier); setTimeout(() => handlers.squad(Dev.squad), 30); } return { ok: true, msg: data.accept ? 'Dee Carter joined the squad' : 'Request declined' };
      case 'requestJoin': return { ok: true, msg: 'Request sent' };
      case 'cancelRequest': return { ok: true, msg: 'Request withdrawn' };
      case 'allyRespond':
        if (Dev.squad && data.accept) {
          const req = (Dev.squad.allyRequests || []).find((r) => r.id === data.id);
          if (req) Dev.squad.allies.push({ id: req.id, name: req.name, tag: req.tag, elo: req.elo, tier: req.tier, online: 3, blipColor: 1, since: t });
        }
        if (Dev.squad) Dev.squad.allyRequests = (Dev.squad.allyRequests || []).filter((r) => r.id !== data.id);
        setTimeout(() => handlers.squad(Dev.squad), 30);
        return { ok: true };
      case 'allyRemove': if (Dev.squad) Dev.squad.allies = Dev.squad.allies.filter((a) => a.id !== data.id); setTimeout(() => handlers.squad(Dev.squad), 30); return { ok: true };
      case 'wheelSelect': return 1;
      case 'close': return 1;
      default: return { ok: true };
    }
  },
  makeSquad(name, temp) {
    const t = Date.now() / 1000;
    return {
      id: 1, name: name || 'Southside Crew', tag: 'SSC', image: '', description: 'South LS crew, rolling most nights', motd: 'Rolling at 9 — bring armour and a getaway car.',
      locked: false, inviteOnly: false, limit: 6, owner: 'char:nay', persistent: true, temporary: temp === true, blipColor: 2, blipSprite: 480,
      allyMax: 2, ranks: Dev.ranks, created: t - 5400,
      allies: temp ? [] : [{ id: 3, name: 'Vinewood Night Shift', tag: 'VNS', elo: 980, tier: { name: 'Silver', color: '#9aa4ab' }, online: 2, blipColor: 3, since: t - 86400 }],
      allyRequests: temp ? [] : [{ id: 2, name: 'Ballas', tag: 'BLS', elo: 1420, tier: { name: 'Platinum', color: '#4fd1ff' }, by: 'Big Smoke', expires: 94 }],
      allyMembers: {},
      requests: [{ identifier: 'char:dee', id: 51, name: 'Dee Carter', message: 'got a crew of my own but yall look fun', at: t - 120, expires: 180 }],
      elo: 1285, tier: { name: 'Gold', min: 1100, color: '#e5a50a' }, tierProgress: 0.92, nextTier: { name: 'Platinum', min: 1300 },
      wins: 11, losses: 5, draws: 1, kills: 94, deaths: 61, assists: 38, rally: { x: 0, y: 0, z: 0, by: 'Tay', at: t - 300 },
      you: { rank: 4, identifier: 'char:nay', perms: { invite: true, kick: true, promote: true, edit: true, ranks: true, rally: true, ready: true, disband: true, motd: true } },
      members: [
        { id: 1, identifier: 'char:nay', name: 'NayZeee', rank: 4, rankName: 'Leader', rankIcon: 'fa-crown', owner: true, online: true, kills: 31, deaths: 14, assists: 9, revives: 6, playtime: 52000, streak: 4 },
        { id: 14, identifier: 'char:tay', name: 'Tay', realName: 'Taylor Brooks', nick: 'Tay', rank: 3, rankName: 'Officer', rankIcon: 'fa-user-shield', owner: false, online: true, kills: 27, deaths: 18, assists: 12, revives: 3, playtime: 41000 },
        { id: 22, identifier: 'char:mar', name: 'Marcus Hill', rank: 2, rankName: 'Member', rankIcon: 'fa-user-check', owner: false, online: true, downed: true, kills: 19, deaths: 16, assists: 11, revives: 1, playtime: 12000 },
        { id: 31, identifier: 'char:kei', name: 'Keisha Moore', rank: 2, rankName: 'Member', rankIcon: 'fa-user-check', owner: false, online: true, kills: 14, deaths: 9, assists: 6, revives: 4, playtime: 9000 },
        { id: null, identifier: 'char:rob', name: 'Rob Diaz', rank: 1, rankName: 'Recruit', rankIcon: 'fa-user', owner: false, online: false, kills: 3, deaths: 4, assists: 0, revives: 0, playtime: 3000, lastSeen: t - 7200 },
      ],
      vitals: { 14: { h: 82, a: 60 }, 22: { h: 0, a: 0 }, 31: { h: 45, a: 100 } },
      log: [{ kind: 'create', text: 'NayZeee created the squad', at: t - 5400 }, { kind: 'join', text: 'Tay joined', at: t - 5000 }, { kind: 'rank', text: 'Tay was promoted to Officer', at: t - 4800 },
        { kind: 'ally', text: 'Allied with Vinewood Night Shift', at: t - 4000 }, { kind: 'match', text: 'Won vs Paleto Hunters 5-2 (+21 ELO)', at: t - 3600 }, { kind: 'motd', text: 'NayZeee set the message: Rolling at 9', at: t - 900 }],
    };
  },
  list: [
    { id: 2, name: 'Ballas', tag: 'BLS', locked: true, inviteOnly: false, limit: 8, count: 5, online: 3, elo: 1420, blipColor: 1, tier: { name: 'Platinum', color: '#4fd1ff' }, wins: 19, losses: 9, owner: 'Big Smoke', created: Date.now() / 1000 - 400000, allies: 1, canRequest: true, description: 'Purple till we die', members: [{ name: 'Big Smoke', online: true }, { name: 'Kane', online: true }, { name: 'Rico', online: false }] },
    { id: 3, name: 'Vinewood Night Shift', tag: 'VNS', locked: false, inviteOnly: false, limit: 4, count: 2, online: 2, elo: 980, blipColor: 3, tier: { name: 'Silver', color: '#9aa4ab' }, wins: 4, losses: 7, owner: 'Ari Cole', created: Date.now() / 1000 - 90000, members: [{ name: 'Ari Cole', online: true }, { name: 'Jules', online: true }] },
    { id: 7, name: 'Pier Run', tag: 'PIER', locked: false, inviteOnly: false, limit: 4, count: 3, online: 3, elo: 1000, blipColor: 17, temporary: true, tier: { name: 'Gold', color: '#e5a50a' }, wins: 0, losses: 0, owner: 'Mika', created: Date.now() / 1000 - 1200, members: [{ name: 'Mika', online: true }, { name: 'Ren', online: true }, { name: 'Odell', online: true }] },
    { id: 4, name: 'Paleto Hunters', tag: 'PLT', locked: false, inviteOnly: true, limit: 6, count: 5, online: 1, elo: 1760, blipColor: 27, tier: { name: 'Elite', color: '#08afa2' }, wins: 31, losses: 8, owner: 'Wade', created: Date.now() / 1000 - 900000, canRequest: true, members: [{ name: 'Wade', online: true }, { name: 'Buck', online: false }] },
  ],
  get board() {
    return [
      { id: 4, name: 'Paleto Hunters', tag: 'PLT', elo: 1760, wins: 31, losses: 8, draws: 2, kills: 300, deaths: 120, members: 6, online: 1, tierInfo: { name: 'Elite', color: '#08afa2' } },
      { id: 2, name: 'Ballas', tag: 'BLS', elo: 1420, wins: 19, losses: 9, kills: 140, deaths: 96, members: 5, online: 3, tierInfo: { name: 'Platinum', color: '#4fd1ff' } },
      { id: 1, name: 'Southside Crew', tag: 'SSC', elo: 1285, wins: 11, losses: 5, kills: 94, deaths: 61, members: 5, online: 4, tierInfo: { name: 'Gold', color: '#e5a50a' } },
      { id: 3, name: 'Vinewood Night Shift', tag: 'VNS', elo: 980, wins: 4, losses: 7, kills: 30, deaths: 45, members: 2, online: 2, tierInfo: { name: 'Silver', color: '#9aa4ab' } },
    ];
  },
  players: [
    { name: 'Wade', kills: 88, deaths: 31, assists: 24, revives: 9, playtime: 300000, squad: 'Paleto Hunters', tag: 'PLT' },
    { name: 'Big Smoke', kills: 61, deaths: 40, assists: 19, revives: 4, playtime: 120000, squad: 'Ballas', tag: 'BLS' },
    { name: 'NayZeee', kills: 31, deaths: 14, assists: 9, revives: 6, playtime: 52000, squad: 'Southside Crew', tag: 'SSC' },
    { name: 'Tay', kills: 27, deaths: 18, assists: 12, revives: 3, playtime: 41000, squad: 'Southside Crew', tag: 'SSC' },
  ],
  adminList() {
    const s = Dev.squad || Dev.makeSquad();
    return [{ id: s.id, name: s.name, tag: s.tag, elo: s.elo, tier: s.tier, wins: s.wins, losses: s.losses, draws: s.draws, kills: s.kills, deaths: s.deaths, persistent: true, created: s.created, count: s.members.length, motd: s.motd, allies: 1, log: s.log,
      online: s.members.filter((m) => m.online).length, members: s.members.map((m) => ({ identifier: m.identifier, id: m.id, name: m.name, realName: m.realName, online: m.online, rank: m.rank, rankName: m.rankName, owner: m.owner, kills: m.kills, deaths: m.deaths, assists: m.assists, lastSeen: m.lastSeen })) },
      { id: 2, name: 'Ballas', tag: 'BLS', elo: 1420, tier: { name: 'Platinum', color: '#4fd1ff' }, wins: 19, losses: 9, draws: 0, kills: 140, deaths: 96, persistent: true, created: Date.now() / 1000 - 400000, count: 5, online: 3, allies: 0, log: [],
        members: [{ identifier: 'char:smoke', id: 44, name: 'Big Smoke', online: true, rank: 4, rankName: 'Leader', owner: true, kills: 61, deaths: 40, assists: 19 }] }];
  },
};

boot();
if (!IS_GAME) {
  document.body.style.background = 'radial-gradient(1100px 640px at 60% 20%,#1a2226 0%,#050607 70%)';
  setTimeout(() => { handlers.profile({ name: 'NayZeee', staff: true }); handlers.open({ squad: null }); refreshList(); }, 100);
  window.__dev = { handlers, state, openWheel, renderPrompt, Dev, applyHudStyle, renderHud, go, enterTabs };
}
})();
