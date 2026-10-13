/* nayzeee-squads · NUI */
(() => {
'use strict';

const IS_GAME = typeof GetParentResourceName === 'function';
const RES = IS_GAME ? GetParentResourceName() : 'nayzeee-squads';
const $ = (s, r = document) => r.querySelector(s);

const state = {
  cfg: null, me: 0, settings: {}, squad: null, chat: [],
  list: null, invites: [], open: false,
  view: 'browse', preview: null, search: '',
  unread: 0, talking: {}, downAt: {}, hudHidden: false, editingHud: false, hudPrevPos: null,
  nameCheck: { value: '', ok: null, msg: '' }, form: null, ranksDraft: null,
  stats: null, board: null, boardTab: 'squads', admin: null, adminOpen: null, isAdmin: false,
  ready: null,
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
const clock = (t) => { const d = new Date(t * 1000); return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`; };
const since = (t) => {
  const s = Math.max(0, Math.floor(Date.now() / 1000 - t));
  if (s < 60) return 'just now';
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m`;
  return `${Math.floor(s / 86400)}d`;
};
const debounce = (fn, ms) => { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; };
const ratio = (k, d) => (d > 0 ? (k / d).toFixed(2) : k.toFixed(2));
const vit = (id) => (state.squad && state.squad.vitals && state.squad.vitals[String(id)]) || null;
const isDown = (m) => m.downed || (vit(m.id) && vit(m.id).h === 0);
const can = (perm) => !!(state.squad && state.squad.you && state.squad.you.perms && state.squad.you.perms[perm]);
const isOwner = () => !!(state.squad && state.squad.members.some((m) => m.id === state.me && m.owner));
const online = () => (state.squad ? state.squad.members.filter((m) => m.online) : []);
const tierOf = (t) => t || { name: 'Bronze', color: '#b4713d' };

const kdaHtml = (m, withRevives) => `<span class="kda"><b class="k">${m.kills || 0}</b><s>/</s><b class="d">${m.deaths || 0}</b><s>/</s><b class="a">${m.assists || 0}</b>${
  withRevives && m.revives ? `<s>·</s><b class="r">${m.revives}<i class="fa-solid fa-kit-medical" style="font-size:8px;margin-left:2px"></i></b>` : ''}</span>`;

const tierBadge = (tier, extra = '') => {
  const t = tierOf(tier);
  return `<span class="tier" style="--tier:${esc(t.color)}"><i class="fa-solid fa-shield-halved"></i>${esc(t.name)}${extra}</span>`;
};

async function nui(name, data = {}) {
  if (!IS_GAME) return Dev.handle(name, data);
  try {
    const r = await fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data) });
    return await r.json();
  } catch { return null; }
}

// ─── toasts ────────────────────────────────────────────────
// Toasts raised in the menu go to whichever notification system the server picked.
// `opts.local` means Lua already routed it here, so draw it without bouncing it back.
const externalNotify = () => state.cfg && state.cfg.notify && state.cfg.notify !== 'builtin';

function toast(title, text, kind = 'info', opts = {}) {
  if (!opts.local && externalNotify()) {
    nui('notify', { title, text, kind, duration: opts.duration });
    return;
  }
  const wrap = $('#toasts');
  const el = document.createElement('div');
  const dur = opts.duration || 4500;
  el.className = `toast ${kind === 'error' ? 'error' : kind === 'warning' ? 'warning' : ''}`;
  el.style.setProperty('--dur', `${dur}ms`);
  if (opts.color) { el.style.borderLeftColor = opts.color; el.style.setProperty('--accent', opts.color); }
  const icon = opts.icon || (kind === 'error' ? 'fa-circle-exclamation' : 'fa-check');
  el.innerHTML = `<div class="ti" ${opts.color ? `style="color:${opts.color};border-color:${opts.color}55;background:${opts.color}1c"` : ''}><i class="fa-solid ${icon}"></i></div>
    <div><b>${esc(title)}</b><p>${esc(text)}</p></div>`;
  wrap.appendChild(el);
  while (wrap.children.length > 4) wrap.firstChild.remove();
  setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 200); }, dur);
}

function result(r, okTitle, okText) {
  if (r && r.ok) { if (okTitle) toast(okTitle, r.msg || okText || '', 'success'); return true; }
  toast('Something went wrong', (r && r.msg) || 'Try that again in a moment.', 'error');
  return false;
}

// ─── modal ─────────────────────────────────────────────────
function confirmModal({ title, text, confirm, danger = true, icon, input }) {
  return new Promise((resolve) => {
    const m = $('#modal');
    m.innerHTML = `<div class="modal">
      <div class="modal-b"><div class="m-icon ${danger ? '' : 'teal'}"><i class="fa-solid ${icon || (danger ? 'fa-triangle-exclamation' : 'fa-circle-question')}"></i></div>
      <div style="flex:1"><h4>${esc(title)}</h4><p>${esc(text)}</p>
      ${input ? `<div class="field"><input id="modalInput" placeholder="${esc(input.placeholder || '')}" value="${esc(input.value || '')}"${input.max ? ` maxlength="${input.max}"` : ''}></div>` : ''}</div></div>
      <div class="modal-f"><button class="btn-line sm" data-m="0">Cancel</button><button class="${danger ? 'btn-red' : 'btn-teal'} sm" data-m="1">${esc(confirm)}</button></div></div>`;
    m.classList.remove('hidden');
    const done = (v) => {
      const val = input && $('#modalInput') ? $('#modalInput').value : null;
      m.classList.add('hidden'); m.innerHTML = ''; m.onclick = null; state.modalClose = null;
      resolve(v && input ? val : v);
    };
    state.modalClose = () => done(false);
    m.onclick = (e) => {
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

// ─── chrome ────────────────────────────────────────────────
function tabsFor() {
  const f = state.cfg.features;
  const allies = f.Affiliations && state.cfg.allyMax > 0;
  const temp = state.squad && state.squad.temporary;
  const t = state.squad
    ? [['squad', 'fa-users', 'Squad'], ['chat', 'fa-message', 'Chat'],
       ...(allies && !temp ? [['allies', 'fa-handshake', 'Allies']] : []),
       ...(temp ? [] : [['stats', 'fa-chart-simple', 'Stats']]),
      ]
    : [['browse', 'fa-magnifying-glass', 'Browse'], ...(f.Leaderboard ? [['board', 'fa-ranking-star', 'Ranks']] : []), ['create', 'fa-plus', 'Create']];
  if (state.isAdmin) t.push(['admin', 'fa-user-shield', 'Staff']);
  return t;
}

const parentView = (v) => ({ preview: 'browse', edit: 'squad', ranks: 'squad' }[v] || v);

function renderChrome() {
  const active = parentView(state.view);
  $('#tabs').innerHTML = tabsFor().map(([id, ico, label]) => {
    const pending = state.squad && state.squad.allyRequests ? state.squad.allyRequests.length : 0;
    const tally = id === 'chat' && state.unread > 0 ? `<span class="tally hot">${state.unread > 99 ? '99+' : state.unread}</span>`
      : id === 'browse' && state.invites.length ? `<span class="tally hot">${state.invites.length}</span>`
      : id === 'allies' && pending ? `<span class="tally hot">${pending}</span>` : '';
    return `<button class="tab ${active === id ? 'on' : ''}" data-tab="${id}"><i class="fa-solid ${ico}"></i>${label}${tally}</button>`;
  }).join('');

  const dot = $('#barDot');
  const tierEl = $('#barTier');
  if (state.squad) {
    const up = online().filter((m) => !isDown(m)).length;
    dot.className = 'dot';
    $('#barText').innerHTML = `<b>${esc(state.squad.name)}</b>${state.squad.tag ? ` <span class="muted">[${esc(state.squad.tag)}]</span>` : ''} · ${up}/${online().length} up`;
    tierEl.innerHTML = state.squad.temporary
      ? '<span class="tag warn"><i class="fa-solid fa-hourglass-half"></i>Temporary</span>'
      : tierBadge(state.squad.tier, ` ${state.squad.elo}`);
  } else {
    const n = state.list ? state.list.length : 0;
    dot.className = n ? 'dot' : 'dot off';
    $('#barText').innerHTML = state.list ? `<b>${n}</b> squad${n === 1 ? '' : 's'}` : 'Loading squads';
    tierEl.innerHTML = '';
  }

  const keys = state.view === 'chat' ? [['ESC', 'Close'], ['↵', 'Send']] : [['ESC', 'Close'], ['TAB', 'Switch tab']];
  $('#keys').innerHTML = keys.map(([k, l]) => `<span><span class="key">${k}</span>${l}</span>`).join('');
}

function go(view) {
  state.view = view;
  if (view === 'chat') state.unread = 0;
  render();
}

const after = {};

function render() {
  if (!state.cfg) return;
  if (state.squad && ['browse', 'create', 'preview', 'board'].includes(state.view)) state.view = 'squad';
  if (!state.squad && ['squad', 'chat', 'edit', 'ranks', 'stats', 'allies'].includes(state.view)) state.view = 'browse';
  // a temporary squad has no rating, so those tabs don't apply
  if (state.squad && state.squad.temporary && ['stats', 'allies'].includes(state.view)) state.view = 'squad';
  renderChrome();
  const views = {
    browse: viewBrowse, preview: viewPreview, board: viewBoard,
    create: () => viewForm(false), edit: () => viewForm(true),
    squad: viewSquad, ranks: viewRanks, chat: viewChat, stats: viewStats, allies: viewAllies,
    settings: viewSettings, admin: viewAdmin,
  };
  $('#view').innerHTML = (views[state.view] || viewBrowse)();
  after[state.view]?.();
}

// ─── browse ────────────────────────────────────────────────
function squadRow(s) {
  const full = s.count >= s.limit;
  const status = s.inviteOnly ? '<span class="tag off"><i class="fa-solid fa-envelope"></i>Invite</span>'
    : s.locked ? '<span class="tag off"><i class="fa-solid fa-lock"></i>Locked</span>'
    : full ? '<span class="tag hot">Full</span>' : '<span class="tag live">Open</span>';
  const badge = s.temporary
    ? '<span class="tag warn"><i class="fa-solid fa-hourglass-half"></i>Temp</span>'
    : tierBadge(s.tier, ` ${s.elo}`);
  return `<div class="row click" data-preview="${s.id}">
    ${avatar(s.name, s.image)}
    <div class="row-txt"><b>${esc(s.name)}${s.tag ? ` <span class="chip squad">${esc(s.tag)}</span>` : ''}</b>
      <span><span class="bp-mini" style="background:${blipHex(s.blipColor)}"></span><i class="fa-solid fa-crown"></i>${esc(s.owner)} · ${s.online} online</span>
      <div class="bar-mini"><i style="width:${Math.round((s.count / s.limit) * 100)}%"></i></div></div>
    <div class="row-end">${badge}<span class="tally">${s.count}/${s.limit}</span>${status}</div>
  </div>`;
}

function viewBrowse() {
  const q = state.search.toLowerCase();
  let body;
  if (!state.list) {
    body = Array.from({ length: 4 }, () => `<div class="skel"><div class="sk circ"></div><div style="flex:1"><div class="sk" style="height:9px;width:52%"></div><div class="sk" style="height:7px;width:32%;margin-top:7px"></div></div></div>`).join('');
  } else {
    const rows = state.list.filter((s) => !q || s.name.toLowerCase().includes(q) || s.owner.toLowerCase().includes(q) || (s.tag || '').toLowerCase().includes(q));
    body = rows.length ? rows.map(squadRow).join('')
      : `<div class="empty"><i class="fa-solid fa-users-slash"></i><b>${q ? 'No squads match that search' : 'No squads are running'}</b>
         <span>${q ? 'Check the spelling or clear the search to see every squad.' : 'Start one and invite your people in.'}</span>
         ${q ? '' : '<button class="btn-teal sm" data-tab="create"><i class="fa-solid fa-plus"></i>Create a squad</button>'}</div>`;
  }

  const invites = state.invites.length ? `<section class="panel">
    <div class="p-head"><div><h2>Invites</h2><p>Squads waiting on your answer</p></div><span class="tally hot">${state.invites.length}</span></div>
    <div class="p-body">${state.invites.map((i) => `<div class="row">${avatar(i.from || i.name, i.fromAvatar || i.image, 'sm')}
      <div class="row-txt"><b>${esc(i.name)}</b><span>${esc(i.from || i.owner)} · ${i.count}/${i.limit}</span></div>
      <div class="row-end">${tierBadge(i.tier)}<button class="btn-line sm" data-decline="${i.id}">Decline</button><button class="btn-teal sm" data-accept="${i.id}">Join</button></div></div>`).join('')}</div>
  </section>` : '';

  return `<div class="page">
    <div class="head"><div><h1>Find a squad</h1><p>Join an open crew or start your own.</p></div></div>
    <div class="cols wide-left">
      <div class="col">
        <div class="inline-form">
          <div class="input"><i class="fa-solid fa-magnifying-glass"></i><input id="search" placeholder="Search name, tag or owner" value="${esc(state.search)}" maxlength="24"></div>
          <button class="btn-ghost" data-act="refresh" style="height:34px"><i class="fa-solid fa-rotate-right"></i>Refresh</button>
        </div>
        <div class="p-body" style="padding:0" id="squadList">${body}</div>
      </div>
      <div class="col">
        ${invites || `<div class="empty"><i class="fa-solid fa-envelope-open"></i><b>No invites waiting</b>
          <span>When someone invites you to their squad it shows up here.</span></div>`}
        <section class="panel"><div class="p-head"><div><h2>How squads work</h2><p>The short version</p></div></div>
          <div class="p-body pad" style="gap:9px">
            <div class="sw-line"><div><b>Ranks are yours</b><span>Rename them and set what each one can do</span></div><i class="fa-solid fa-list-ol" style="color:var(--teal)"></i></div>
            <div class="divider"></div>
            <div class="sw-line"><div><b>Fights are rated</b><span>Beating another squad moves both ratings</span></div><i class="fa-solid fa-ranking-star" style="color:var(--teal)"></i></div>
            <div class="divider"></div>
            <div class="sw-line"><div><b>Pick each other up</b><span>Revive squadmates with your medical items</span></div><i class="fa-solid fa-kit-medical" style="color:var(--teal)"></i></div>
          </div></section>
      </div>
    </div>
  </div>
  <div class="foot"><button class="btn-teal" data-tab="create"><i class="fa-solid fa-plus"></i>Create squad</button></div>`;
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
  const full = s.count >= s.limit;
  const blocked = full || (s.inviteOnly && !invited);
  const needPass = s.locked && !invited;
  const games = (s.wins || 0) + (s.losses || 0);
  return `<div class="page">
    <div><button class="btn-ghost" data-tab="browse"><i class="fa-solid fa-arrow-left"></i>Back to squads</button></div>
    <div class="hero" style="--tier:${esc(tierOf(s.tier).color)}">${avatar(s.name, s.image, 'lg')}
      <div class="hero-txt"><h2>${esc(s.name)}${s.tag ? `<span class="chip squad">${esc(s.tag)}</span>` : ''}</h2><p>Led by ${esc(s.owner)}</p>
        <div class="tags">${tierBadge(s.tier, ` ${s.elo}`)}<span class="tag live"><i class="fa-solid fa-users"></i>${s.count}/${s.limit}</span>
        ${s.locked ? '<span class="tag off"><i class="fa-solid fa-lock"></i>Password</span>' : ''}
        ${s.inviteOnly ? '<span class="tag off"><i class="fa-solid fa-envelope"></i>Invite only</span>' : ''}
        ${full ? '<span class="tag hot">Full</span>' : ''}</div></div></div>
    <div class="stats"><div class="stat"><span><i class="fa-solid fa-trophy"></i>Wins</span><b>${s.wins || 0}</b></div>
      <div class="stat red"><span><i class="fa-solid fa-flag"></i>Losses</span><b>${s.losses || 0}</b></div>
      <div class="stat blue"><span><i class="fa-solid fa-percent"></i>Win rate</span><b>${games ? Math.round((s.wins / games) * 100) : 0}<small>%</small></b></div></div>
    <div class="cols">
      <div class="col">
        ${needPass && !blocked ? `<section class="panel"><div class="p-head"><div><h2>Password</h2><p>This squad is locked</p></div></div>
          <div class="p-body pad"><div class="field"><div class="input"><i class="fa-solid fa-key"></i>
          <input id="joinPass" type="password" maxlength="32" placeholder="Enter the password"></div></div></div></section>` : ''}
        <section class="panel"><div class="p-head"><div><h2>Record</h2><p>How they've done so far</p></div></div>
          <div class="p-body pad" style="gap:9px">
            <div class="sw-line"><div><b>Rating</b></div><span>${s.elo} ELO</span></div><div class="divider"></div>
            <div class="sw-line"><div><b>Fights</b></div><span>${games}</span></div><div class="divider"></div>
            <div class="sw-line"><div><b>Spots left</b></div><span>${Math.max(0, s.limit - s.count)}</span></div>
          </div></section>
      </div>
      <div class="col"><section class="panel">
        <div class="p-head"><div><h2>Members</h2><p>Who you'd be rolling with</p></div><span class="tally">${s.count}</span></div>
        <div class="p-body scroll">${s.members.map((n) => `<div class="row ${n.online ? '' : 'dim'}">${avatar(n.name, n.avatar, `sm ${n.online ? '' : 'off'}`)}
          <div class="row-txt"><b>${esc(n.name)}</b><span>${n.name === s.owner ? '<i class="fa-solid fa-crown"></i>Owner' : (n.online ? 'Online' : 'Offline')}</span></div></div>`).join('')}</div>
      </section></div>
    </div>
  </div>
  <div class="foot"><button class="btn-teal" data-join="${s.id}" ${blocked ? 'disabled' : ''}>
    <i class="fa-solid fa-right-to-bracket"></i>${full ? 'Squad is full' : s.inviteOnly && !invited ? 'Invite only' : 'Join squad'}</button></div>`;
}
after.preview = () => { const p = $('#joinPass'); if (p) { p.focus(); p.onkeydown = (e) => { if (e.key === 'Enter') $('[data-join]')?.click(); }; } };

// ─── leaderboard ───────────────────────────────────────────
function viewBoard() {
  const b = state.board;
  if (!b) {
    return `<div class="page"><div class="head"><div><h1>Leaderboard</h1><p>Ranked by ELO across the server.</p></div></div>
      <div class="cols">${['', ''].map(() => `<div class="col">${Array.from({ length: 5 }, () => `<div class="skel"><div class="sk circ"></div><div style="flex:1"><div class="sk" style="height:9px;width:46%"></div><div class="sk" style="height:7px;width:28%;margin-top:7px"></div></div></div>`).join('')}</div>`).join('')}</div></div>`;
  }
  if (!b.persistent) {
    return `<div class="page"><div class="head"><div><h1>Leaderboard</h1></div></div>
      <div class="empty"><i class="fa-solid fa-database"></i><b>Stats are turned off</b>
      <span>Rankings need persistence switched on in the config, with the SQL file imported.</span></div></div>`;
  }

  const squadRows = (b.squads.length ? b.squads.map((s, i) => {
        const games = s.wins + s.losses;
        return `<div class="lb-row ${state.squad && state.squad.id === s.id ? 'me' : ''}">
          <span class="pos ${i < 3 ? `g${i + 1}` : ''}">${i + 1}</span>${avatar(s.name, s.image, 'sm')}
          <div class="row-txt"><b>${esc(s.name)}${s.tag ? ` <span class="chip squad">${esc(s.tag)}</span>` : ''}</b>
            <span>${s.wins}W ${s.losses}L · ${games ? Math.round((s.wins / games) * 100) : 0}% · ${s.members} members</span></div>
          <div class="lb-end"><b>${s.elo}</b>${tierBadge(s.tierInfo)}</div></div>`;
      }).join('') : `<div class="empty"><i class="fa-solid fa-ranking-star"></i><b>No ranked squads yet</b><span>Squads appear here once they fight another squad.</span></div>`);

  const playerRows = (b.players.length ? b.players.map((p, i) => `<div class="lb-row">
      <span class="pos ${i < 3 ? `g${i + 1}` : ''}">${i + 1}</span>${avatar(p.name, p.image, 'sm')}
      <div class="row-txt"><b>${esc(p.name)}</b><span>${esc(p.squad)}${p.tag ? ` [${esc(p.tag)}]` : ''}${kdaHtml(p, true)}</span></div>
      <div class="lb-end"><b>${p.kills}</b><span>${ratio(p.kills, p.deaths)} K/D</span></div></div>`).join('')
    : `<div class="empty"><i class="fa-solid fa-user-slash"></i><b>No player stats yet</b><span>Kills and assists show up here after the first squad fight.</span></div>`);

  return `<div class="page">
    <div class="head"><div><h1>Leaderboard</h1><p>Top squads by rating, and the players with the most kills.</p></div></div>
    <div class="cols">
      <div class="col"><section class="panel">
        <div class="p-head"><div><h2>Squads</h2><p>By ELO rating</p></div><span class="tally">${b.squads.length}</span></div>
        <div class="p-body scroll">${squadRows}</div></section></div>
      <div class="col"><section class="panel">
        <div class="p-head"><div><h2>Players</h2><p>By kills across every squad</p></div><span class="tally">${b.players.length}</span></div>
        <div class="p-body scroll">${playerRows}</div></section></div>
    </div>
  </div>
  <div class="foot"><button class="btn-line" data-act="refreshBoard"><i class="fa-solid fa-rotate-right"></i>Refresh</button></div>`;
}

// ─── create / edit ─────────────────────────────────────────
function viewForm(edit) {
  const c = state.cfg;
  if (!state.form || state.form.edit !== edit) {
    const s = edit ? state.squad : null;
    const types = c.squadTypes || { temporary: true, permanent: true, default: 'permanent' };
    state.form = {
      edit, name: s ? s.name : '', tag: (s && s.tag) || '', image: (s && s.image) || '',
      limit: s ? s.limit : Math.min(4, c.maxMembers), locked: s ? s.locked : false, password: '',
      inviteOnly: s ? s.inviteOnly : false,
      temporary: s ? !!s.temporary
        : (types.permanent && !(state.status && state.status.permanent === false) ? types.default === 'temporary' : true),
      blipColor: s && s.blipColor !== undefined ? s.blipColor : 2,
      blipSprite: s && s.blipSprite !== undefined ? s.blipSprite : 1,
    };
    state.nameCheck = { value: state.form.name, ok: edit ? true : null, msg: '' };
  }
  const f = state.form, nc = state.nameCheck;
  return `<div class="page">
    ${edit ? '<div><button class="btn-ghost" data-tab="squad"><i class="fa-solid fa-arrow-left"></i>Back to squad</button></div>' : ''}
    <div class="head"><div><h1>${edit ? 'Edit squad' : 'Create a squad'}</h1><p>${edit ? 'Changes apply for everyone right away.' : 'Pick a name and tag, set who can join, and you own it.'}</p></div></div>

    ${edit ? '' : typePicker(f)}

    <div class="cols"><div class="col">
    <section class="panel"><div class="p-head"><div><h2>Details</h2><p>Name, tag and size</p></div></div><div class="p-body pad">
      <div class="grid2">
        <div class="field"><label for="fName">Squad name</label>
          <input id="fName" maxlength="${c.nameMax}" placeholder="Name your squad" value="${esc(f.name)}" class="${nc.ok === true ? 'ok' : nc.ok === false ? 'bad' : ''}">
          <span class="hint ${nc.ok === true ? 'ok' : nc.ok === false ? 'bad' : ''}" id="fNameHint">${nc.ok === false ? esc(nc.msg) : nc.ok === true && !edit ? 'Name is available' : `${c.nameMin}–${c.nameMax} characters`}</span></div>
        <div class="field"><label for="fTag">Tag</label>
          <input id="fTag" maxlength="${c.tagMax}" placeholder="ABC" value="${esc(f.tag)}" style="text-transform:uppercase">
          <span class="hint">Shown over names</span></div>
      </div>
      <div class="field"><label for="fImage">Squad image</label>
        <div class="inline-form"><div id="fImgPrev">${avatar(f.name || '?', safeImg(f.image))}</div>
        <div class="input" style="flex:1"><i class="fa-solid fa-link"></i><input id="fImage" maxlength="300" placeholder="https:// image link (optional)" value="${esc(f.image)}"></div></div></div>
      <div class="field"><label>Member limit</label>
        <div class="stepper"><button data-step="-1" aria-label="Fewer"><i class="fa-solid fa-minus"></i></button><b id="fLimit">${f.limit}</b><button data-step="1" aria-label="More"><i class="fa-solid fa-plus"></i></button></div></div>
    </div></section>
    </div><div class="col">

    <section class="panel"><div class="p-head"><div><h2>Access</h2><p>Control who can get in</p></div></div><div class="p-body pad">
      <div class="sw-line" data-ftoggle="locked"><div><b>Password protected</b><span>Players need the password to join</span></div><span class="sw ${f.locked ? 'on' : ''}"><i></i></span></div>
      ${f.locked ? `<div class="field"><div class="input"><i class="fa-solid fa-key"></i><input id="fPass" type="password" maxlength="32" placeholder="${edit && state.squad.locked ? 'Leave blank to keep the current password' : 'Set a password'}" value="${esc(f.password)}"></div></div>` : ''}
      <div class="divider"></div>
      <div class="sw-line" data-ftoggle="inviteOnly"><div><b>Invite only</b><span>Hidden from joining unless you invite them</span></div><span class="sw ${f.inviteOnly ? 'on' : ''}"><i></i></span></div>
    </div></section>

    ${blipPicker(f)}
    </div></div>
  </div>
  <div class="foot"><button class="btn-teal" data-act="${edit ? 'saveEdit' : 'create'}" id="fSubmit"><i class="fa-solid ${edit ? 'fa-floppy-disk' : 'fa-plus'}"></i>${edit ? 'Save changes' : 'Create squad'}</button></div>`;
}

// Temporary vs permanent, picked once when the squad is created.
function typePicker(f) {
  const t = { ...(state.cfg.squadTypes || {}) };
  const st = state.status || { permanent: t.permanent };
  // the server is the source of truth: the database may be down even when the config allows it
  if (t.permanent && st.permanent === false) {
    if (!f.temporary) f.temporary = true;
    return `<div class="notice"><i class="fa-solid fa-triangle-exclamation"></i><div><b>Only temporary squads right now</b>
      <span>${esc(st.reason || 'Squads cannot be saved at the moment.')} This squad won't be rated or saved.</span></div></div>`;
  }
  if (!t.temporary || !t.permanent) {
    return t.temporary && !t.permanent
      ? `<div class="notice"><i class="fa-solid fa-hourglass-half"></i><div><b>Temporary squads only</b>
         <span>This server doesn't save squads, so there's no rating or stat tracking.</span></div></div>`
      : '';
  }
  const opt = (temp, icon, title, lines) => `<button class="pick ${f.temporary === temp ? 'on' : ''}" data-ftype="${temp ? 1 : 0}">
    <span class="pick-i"><i class="fa-solid ${icon}"></i></span>
    <span class="pick-t"><b>${title}</b>${lines.map((l) => `<span>${l}</span>`).join('')}</span>
    <i class="fa-solid fa-circle-check pick-c"></i></button>`;

  return `<section class="panel"><div class="p-head"><div><h2>Squad type</h2><p>You pick this once — it can't be changed later</p></div></div>
    <div class="p-body pad"><div class="picks">
      ${opt(false, 'fa-shield-halved', 'Permanent crew', [
        'Saved between restarts, keeps its roster',
        'Earns ELO and tracks K/D/A',
        'Ranks, alliances and leaderboard place'])}
      ${opt(true, 'fa-hourglass-half', 'Temporary squad', [
        'For one session, nothing is saved',
        'No rating and no stat tracking',
        t.tempHours > 0 ? `Closes after ${t.tempHours}h or when everyone leaves` : 'Closes when the last member leaves'])}
    </div></div></section>`;
}

// The squad's own map colour and marker, shown on every member's blip.
function blipPicker(f) {
  if (!state.cfg.features.SquadBlips) return '';
  const sprites = state.cfg.blipSprites || [];
  return `<section class="panel"><div class="p-head"><div><h2>Map blip</h2><p>How your squad shows on everyone's map</p></div></div>
    <div class="p-body pad">
      <div class="field"><label>Blip colour</label>
        <div class="swatches">${BLIP_PALETTE.map(([id, hex]) =>
          `<button class="swatch ${f.blipColor === id ? 'on' : ''}" style="background:${hex}" data-fblip="${id}" aria-label="Colour ${id}"></button>`).join('')}</div></div>
      <div class="field"><label>Marker</label>
        <div class="icon-pick">${sprites.map((sp) =>
          `<button class="${f.blipSprite === sp.id ? 'on' : ''}" data-fsprite="${sp.id}" title="${esc(sp.label)}"><i class="fa-solid ${esc(sp.icon)}"></i></button>`).join('')}</div></div>
      <div class="blip-preview">
        <span class="bp-dot" style="background:${blipHex(f.blipColor)};box-shadow:0 0 12px ${blipHex(f.blipColor)}">
          <i class="fa-solid ${esc((sprites.find((x) => x.id === f.blipSprite) || { icon: 'fa-circle' }).icon)}"></i></span>
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
  $('#fImage').oninput = debounce((e) => { f.image = e.target.value.trim(); $('#fImgPrev').innerHTML = avatar(f.name || '?', safeImg(f.image)); }, 250);
  const p = $('#fPass'); if (p) p.oninput = (e) => { f.password = e.target.value; };
}
after.create = formAfter;
after.edit = formAfter;

async function submitForm() {
  const f = state.form, c = state.cfg;
  if (state.nameCheck.ok === false) return toast('Check the name', state.nameCheck.msg, 'error');
  if (f.tag && (f.tag.length < c.tagMin || f.tag.length > c.tagMax)) {
    return toast('Check the tag', `Tags are ${c.tagMin} to ${c.tagMax} characters, or leave it blank.`, 'error');
  }
  if (f.locked && !f.password && !(f.edit && state.squad.locked)) return toast('Add a password', 'Set a password or turn password protection off.', 'error');

  const btn = $('#fSubmit'); btn.disabled = true;
  const payload = { name: f.name, tag: f.tag, image: f.image, limit: f.limit, inviteOnly: f.inviteOnly,
    password: f.locked ? f.password : '', blipColor: f.blipColor, blipSprite: f.blipSprite };
  if (!f.edit) payload.temporary = f.temporary;
  if (f.edit) payload.clearPassword = !f.locked;
  const r = await nui(f.edit ? 'edit' : 'create', payload);
  btn.disabled = false;
  if (result(r, f.edit ? 'Squad updated' : 'Squad created', f.edit ? 'Your changes are live.' : 'Invite your people from the squad tab.')) {
    state.form = null;
    if (f.edit) go('squad');
  }
}

// ─── squad ─────────────────────────────────────────────────
function memberRow(m) {
  const v = vit(m.id), down = isDown(m), me = m.id === state.me;
  const hp = m.online && v ? v.h : 0;
  const acts = [];
  const nk = state.cfg.nicknames || {};
  const nickOk = nk.enabled && (!state.squad.temporary || nk.temp);
  if (me && nickOk) {
    acts.push(`<button class="icon-btn" title="${m.nick ? 'Change your nickname' : 'Set a nickname'}" data-nick="self"><i class="fa-solid fa-signature"></i></button>`);
  }
  if (!me && m.nick && can('kick')) {
    acts.push(`<button class="icon-btn" title="Reset their nickname" data-nickreset="${esc(m.identifier)}"><i class="fa-solid fa-eraser"></i></button>`);
  }
  if (!me && !m.owner) {
    if (can('promote')) acts.push(`<button class="icon-btn" title="Change rank" data-rankmenu="${esc(m.identifier)}"><i class="fa-solid fa-arrow-up-right-dots"></i></button>`);
    if (isOwner()) acts.push(`<button class="icon-btn" title="Transfer ownership" data-transfer="${esc(m.identifier)}"><i class="fa-solid fa-crown"></i></button>`);
    if (can('kick')) acts.push(`<button class="icon-btn danger" title="Remove from squad" data-kick="${esc(m.identifier)}"><i class="fa-solid fa-user-minus"></i></button>`);
  }
  return `<div class="row ${m.online ? '' : 'dim'}" data-member="${m.id || ''}">
    ${avatar(m.name, m.avatar, `${m.owner ? 'leader' : ''} ${m.online ? '' : 'off'}`)}
    <div class="row-txt"><b>${esc(m.name)}${m.nick && m.realName ? ` <span class="real-name" title="Character name">${esc(m.realName)}</span>` : ''}${me ? ' <span class="muted" style="font-size:11px">(you)</span>' : ''}</b>
      <span><span class="rank ${m.owner ? 'owner' : ''}"><i class="fa-solid ${esc(m.rankIcon || 'fa-user')}"></i>${esc(m.rankName)}</span>${kdaHtml(m, true)}</span>
      ${m.online ? `<div class="bar-mini"><i class="${hp <= 25 ? 'low' : ''}" style="width:${hp}%"></i></div>` : ''}</div>
    <div class="row-end">${down ? '<span class="tag hot">Down</span>' : m.online ? '' : '<span class="tag off">Offline</span>'}${acts.join('')}</div>
  </div>`;
}

function viewSquad() {
  const s = state.squad;
  const f = state.cfg.features;
  const down = online().filter(isDown).length;
  const games = s.wins + s.losses;
  const nextTier = s.nextTier;
  const canInvite = can('invite');
  const myRank = (s.members.find((m) => m.id === state.me) || {}).rankName || 'Member';

  // temporary squads have no rating, so the hero shows the type instead of an ELO bar
  const heroBody = s.temporary
    ? `<div class="tags" style="margin-top:9px"><span class="tag warn"><i class="fa-solid fa-hourglass-half"></i>Temporary squad</span>
       <span class="tag off"><i class="fa-solid fa-ban"></i>No rating or stats</span></div>`
    : `<div class="elo-wrap">
         <div class="elo-top"><span>${tierBadge(s.tier)}</span><b>${s.elo} ELO</b></div>
         <div class="elo-bar"><i style="width:${Math.round((s.tierProgress || 0) * 100)}%"></i></div>
         <div class="elo-top" style="margin:5px 0 0"><span>${s.wins}W · ${s.losses}L · ${s.draws}D</span>
           <span>${nextTier ? `${nextTier.min - s.elo} to ${esc(nextTier.name)}` : 'Top tier'}</span></div>
       </div>`;

  const heroTier = s.temporary ? '#9aa4ab' : tierOf(s.tier).color;

  return `<div class="page">
    <div class="hero wide" style="--tier:${esc(heroTier)}">${avatar(s.name, s.image, 'lg')}
      <div class="hero-txt"><h2>${esc(s.name)}${s.tag ? `<span class="chip squad">${esc(s.tag)}</span>` : ''}
        <span class="bp-mini" title="Squad blip colour" style="background:${blipHex(s.blipColor)}"></span></h2>
        <p>${isOwner() ? 'You own this squad' : `Your rank: ${esc(myRank)}`}</p>
        ${heroBody}</div>
      ${can('edit') ? '<button class="icon-btn" title="Edit squad" data-tab="edit"><i class="fa-solid fa-pen"></i></button>' : ''}
    </div>

    <div class="cols wide-right"><div class="col">
    <div class="stats four">
      <div class="stat"><span><i class="fa-solid fa-users"></i>Roster</span><b>${s.members.length}<small>/${s.limit}</small></b></div>
      <div class="stat ${down ? 'red' : ''}"><span><i class="fa-solid fa-heart-pulse"></i>Down</span><b>${down}</b></div>
      ${s.temporary
        ? `<div class="stat blue"><span><i class="fa-solid fa-clock"></i>Running</span><b style="font-size:15px;line-height:1.5" data-since="${s.created}">${since(s.created)}</b></div>
           <div class="stat amber"><span><i class="fa-solid fa-hourglass-half"></i>Type</span><b style="font-size:13px;line-height:1.7">Temporary</b></div>`
        : `<div class="stat blue"><span><i class="fa-solid fa-crosshairs"></i>K/D</span><b>${ratio(s.kills, s.deaths)}</b></div>
           <div class="stat amber"><span><i class="fa-solid fa-percent"></i>Win</span><b>${games ? Math.round((s.wins / games) * 100) : 0}<small>%</small></b></div>`}
    </div>

    <div class="actions">
      ${f.ReadyCheck && can('ready') ? '<button class="btn-ghost" data-act="readyCheck"><i class="fa-solid fa-circle-check"></i>Ready check</button>' : ''}
      ${f.Rally && can('rally') ? (s.rally
        ? '<button class="btn-ghost" data-act="rallyClear"><i class="fa-solid fa-flag"></i>Clear rally</button>'
        : '<button class="btn-ghost" data-act="rally"><i class="fa-solid fa-flag"></i>Set rally here</button>') : ''}
      ${f.Waypoint ? '<button class="btn-ghost" data-act="waypoint"><i class="fa-solid fa-route"></i>Share waypoint</button>' : ''}
      ${can('ranks') ? '<button class="btn-ghost" data-tab="ranks"><i class="fa-solid fa-list-ol"></i>Manage ranks</button>' : ''}
    </div>

    ${canInvite ? `<section class="panel">
      <div class="p-head"><div><h2>Invite a player</h2><p>By server ID, or look at them with your target key</p></div></div>
      <div class="p-body pad"><div class="inline-form">
        <div class="input"><i class="fa-solid fa-hashtag"></i><input id="inviteId" inputmode="numeric" maxlength="5" placeholder="Server ID"></div>
        <button class="btn-teal" data-act="invite" ${s.members.length >= s.limit ? 'disabled' : ''}><i class="fa-solid fa-paper-plane"></i>Invite</button>
      </div></div>
    </section>` : ''}

    </div><div class="col">
    <section class="panel">
      <div class="p-head"><div><h2>Members</h2><p>Live health, rank and K/D/A</p></div><span class="tally">${online().length} online</span></div>
      <div class="p-body scroll" id="memberList">${s.members.map(memberRow).join('')}</div>
    </section>
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

// ─── ranks editor ──────────────────────────────────────────
function viewRanks() {
  const c = state.cfg;
  if (!state.ranksDraft) state.ranksDraft = JSON.parse(JSON.stringify(state.squad.ranks));
  const d = state.ranksDraft;

  return `<div class="page">
    <div><button class="btn-ghost" data-tab="squad"><i class="fa-solid fa-arrow-left"></i>Back to squad</button></div>
    <div class="head"><div><h1>Squad ranks</h1><p>Rename ranks and choose what each one can do. The top rank is the owner and always has everything.</p></div></div>

    <div class="cols">${d.map((r, i) => {
      const top = i === d.length - 1;
      return `<div class="col"><section class="panel" data-rank="${i}">
        <div class="p-head"><div style="flex:1">
          <div class="inline-form"><div class="input" style="flex:1"><i class="fa-solid ${esc(r.icon)}"></i>
            <input data-rname="${i}" maxlength="18" value="${esc(r.name)}" placeholder="Rank name"></div>
            <button class="icon-btn" data-rup="${i}" ${i === d.length - 1 ? 'disabled' : ''} title="Move up"><i class="fa-solid fa-chevron-up"></i></button>
            <button class="icon-btn" data-rdown="${i}" ${i === 0 ? 'disabled' : ''} title="Move down"><i class="fa-solid fa-chevron-down"></i></button>
            <button class="icon-btn danger" data-rdel="${i}" ${d.length <= 2 ? 'disabled' : ''} title="Delete rank"><i class="fa-solid fa-trash"></i></button>
          </div>
          <p style="margin-top:7px">${top ? 'Owner rank · every permission' : `Level ${i + 1}`}</p>
        </div></div>
        <div class="p-body pad">
          <div class="icon-pick">${c.rankIcons.map((ic) => `<button class="${ic === r.icon ? 'on' : ''}" data-ricon="${i}" data-icon="${esc(ic)}"><i class="fa-solid ${esc(ic)}"></i></button>`).join('')}</div>
          ${top ? '' : `<div class="divider"></div>${c.perms.map((p) => `<div class="sw-line compact" data-rperm="${i}" data-perm="${esc(p.key)}">
            <div><b>${esc(p.label)}</b></div><span class="sw mini ${r.perms && r.perms[p.key] ? 'on' : ''}"><i></i></span></div>`).join('')}`}
        </div></section></div>`;
    }).join('')}</div>

    ${d.length < c.maxRanks ? '<button class="btn-line full" data-act="addRank" style="max-width:260px"><i class="fa-solid fa-plus"></i>Add a rank</button>' : ''}
  </div>
  <div class="foot">
    <button class="btn-line" data-act="resetRanks"><i class="fa-solid fa-rotate-left"></i>Discard</button>
    <button class="btn-teal" data-act="saveRanks"><i class="fa-solid fa-floppy-disk"></i>Save ranks</button>
  </div>`;
}
after.ranks = () => {
  document.querySelectorAll('[data-rname]').forEach((el) => {
    el.oninput = () => { state.ranksDraft[Number(el.dataset.rname)].name = el.value; };
  });
};

// ─── chat ──────────────────────────────────────────────────
function msgHtml(m) {
  if (m.system) return `<div class="sys"><i class="fa-solid fa-circle-info"></i>${esc(m.text)}</div>`;
  const me = m.from === state.me;
  return `<div class="msg ${me ? 'me' : ''}">${avatar(m.name, m.avatar, 'sm')}<div class="bubble">
    <div class="who"><b>${me ? 'You' : esc(m.name)}</b><span>${m.rank ? `${esc(m.rank)} · ` : ''}${clock(m.t)}</span></div><p>${esc(m.text)}</p></div></div>`;
}

function viewChat() {
  const max = state.cfg.chatMax;
  const log = state.chat.length ? state.chat.map(msgHtml).join('')
    : `<div class="empty" style="margin:auto 0"><i class="fa-solid fa-comments"></i><b>No messages yet</b><span>Messages here only reach your squad.</span></div>`;
  return `<div class="page fill" style="padding:0;gap:0">
    <div class="chat-log" id="chatLog">${log}</div>
    <div class="composer"><div class="composer-inner">
      <div class="input"><i class="fa-solid fa-message"></i><input id="chatInput" maxlength="${max}" placeholder="Message your squad"></div>
      <span class="count" id="chatCount">0/${max}</span>
      <button class="btn-teal" data-act="send" aria-label="Send"><i class="fa-solid fa-paper-plane"></i></button>
    </div></div></div>`;
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
  const text = input.value.trim();
  if (!text) return;
  input.value = ''; $('#chatCount').textContent = `0/${state.cfg.chatMax}`;
  const r = await nui('chat', { text });
  if (r && !r.ok && r.msg) { toast('Message not sent', r.msg, 'error'); input.value = text; }
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
  if (!st) {
    return `<div class="page"><div class="head"><div><h1>Squad stats</h1><p>Loading the latest numbers.</p></div></div>
      ${Array.from({ length: 4 }, () => `<div class="skel"><div class="sk circ"></div><div style="flex:1"><div class="sk" style="height:9px;width:44%"></div><div class="sk" style="height:7px;width:26%;margin-top:7px"></div></div></div>`).join('')}</div>`;
  }

  const ranked = [...st.members].sort((a, b) => (b.kills - a.kills) || (b.assists - a.assists));
  const live = st.active.length ? `<section class="panel">
    <div class="p-head"><div><h2>Live fights</h2><p>Scored once the shooting stops</p></div><span class="tally hot">${st.active.length}</span></div>
    <div class="p-body">${st.active.map((a) => `<div class="row">
      <div class="row-txt"><b>${esc(a.squad)}${a.tag ? ` <span class="chip squad">${esc(a.tag)}</span>` : ''}</b><span>${a.elo} ELO · started ${since(a.since)} ago</span></div>
      <div class="row-end"><span class="tag ${a.mine > a.theirs ? 'live' : a.mine < a.theirs ? 'hot' : 'off'}">${a.mine} – ${a.theirs}</span></div></div>`).join('')}</div>
  </section>` : '';

  const history = st.history.length ? `<section class="panel">
    <div class="p-head"><div><h2>Recent fights</h2><p>Last 10 scored results</p></div></div>
    <div class="p-body">${st.history.map((h) => {
      const mine = h.squad_a === s.id;
      const myKills = mine ? h.kills_a : h.kills_b;
      const theirKills = mine ? h.kills_b : h.kills_a;
      const delta = mine ? h.delta_a : h.delta_b;
      const other = mine ? h.name_b : h.name_a;
      return `<div class="row"><div class="row-txt"><b>${esc(other)}</b><span>${since(h.ended)} ago</span></div>
        <div class="row-end"><span class="tag ${delta > 0 ? 'live' : delta < 0 ? 'hot' : 'off'}">${myKills} – ${theirKills}</span>
        <b style="font-size:12px;color:${delta > 0 ? 'var(--teal)' : delta < 0 ? 'var(--red)' : 'var(--ink-3)'}">${delta > 0 ? '+' : ''}${delta}</b></div></div>`;
    }).join('')}</div>
  </section>` : '';

  return `<div class="page">
    <div class="head"><div><h1>Squad stats</h1><p>Kills, deaths and assists against other squads.</p></div></div>

    <div class="stats four">
      <div class="stat"><span><i class="fa-solid fa-crosshairs"></i>Kills</span><b>${s.kills}</b></div>
      <div class="stat red"><span><i class="fa-solid fa-skull"></i>Deaths</span><b>${s.deaths}</b></div>
      <div class="stat blue"><span><i class="fa-solid fa-handshake-angle"></i>Assists</span><b>${s.assists}</b></div>
      <div class="stat amber"><span><i class="fa-solid fa-chart-line"></i>K/D</span><b>${ratio(s.kills, s.deaths)}</b></div>
    </div>

    <div class="cols"><div class="col">
    ${live}
    ${history}
    </div><div class="col">
    <section class="panel">
      <div class="p-head"><div><h2>Member leaderboard</h2><p>Ranked by kills inside this squad</p></div><span class="tally">${ranked.length}</span></div>
      <div class="p-body scroll">${ranked.map((m, i) => `<div class="lb-row ${m.id === state.me ? 'me' : ''}">
        <span class="pos ${i < 3 ? `g${i + 1}` : ''}">${i + 1}</span>${avatar(m.name, m.avatar, `sm ${m.online ? '' : 'off'}`)}
        <div class="row-txt"><b>${esc(m.name)}</b><span><span class="rank ${m.owner ? 'owner' : ''}"><i class="fa-solid ${esc(m.rankIcon || 'fa-user')}"></i>${esc(m.rankName)}</span>${kdaHtml(m, true)}</span></div>
        <div class="lb-end"><b>${ratio(m.kills, m.deaths)}</b><span>K/D</span></div></div>`).join('')}</div>
    </section>
    </div></div>
  </div>
  <div class="foot"><button class="btn-line" data-act="refreshStats"><i class="fa-solid fa-rotate-right"></i>Refresh</button></div>`;
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
    <div class="row-txt"><b>${esc(a.name)}${a.tag ? ` <span class="chip squad">${esc(a.tag)}</span>` : ''}</b>
      <span><span class="bp-mini" style="background:${blipHex(a.blipColor)}"></span>${a.online} online · allied ${since(a.since)}</span></div>
    <div class="row-end">${tierBadge(a.tier, ` ${a.elo}`)}
      ${mayManage ? `<button class="icon-btn danger" title="End this alliance" data-allyend="${a.id}"><i class="fa-solid fa-link-slash"></i></button>` : ''}</div></div>`;

  const pendingBlock = pending.length ? `<section class="panel">
    <div class="p-head"><div><h2>Requests</h2><p>Squads asking to ally with you</p></div><span class="tally hot">${pending.length}</span></div>
    <div class="p-body">${pending.map((r) => `<div class="row">${avatar(r.name, r.image, 'sm')}
      <div class="row-txt"><b>${esc(r.name)}${r.tag ? ` <span class="chip squad">${esc(r.tag)}</span>` : ''}</b>
        <span>Sent by ${esc(r.by)} · expires in ${r.expires}s</span></div>
      <div class="row-end">${tierBadge(r.tier)}
        ${mayManage ? `<button class="btn-line sm" data-allyno="${r.id}">Decline</button>
        <button class="btn-teal sm" data-allyyes="${r.id}" ${full ? 'disabled' : ''}>Accept</button>` : '<span class="tag off">Leader only</span>'}</div></div>`).join('')}</div>
  </section>` : '';

  // squads you could ally with: not you, not already allied
  const allied = new Set(list.map((a) => a.id));
  const options = (state.list || []).filter((x) => x.id !== s.id && !allied.has(x.id) && !x.temporary);

  return `<div class="page">
    <div class="head"><div><h1>Allies</h1><p>Allied squads see each other on the map, can't trade friendly fire, and never take ELO off one another.</p></div>
      <span class="tally">${list.length}/${max}</span></div>

    <div class="cols">
      <div class="col">
        ${pendingBlock}
        <section class="panel">
          <div class="p-head"><div><h2>Your alliances</h2><p>${full ? 'You have the most allies allowed' : `Room for ${max - list.length} more`}</p></div></div>
          <div class="p-body">${list.length ? list.map(allyRow).join('')
            : `<div class="empty"><i class="fa-solid fa-handshake-slash"></i><b>No alliances yet</b>
               <span>Pick a squad on the right to send them a request.</span></div>`}</div>
        </section>
      </div>
      <div class="col"><section class="panel">
        <div class="p-head"><div><h2>Send a request</h2><p>${mayManage ? 'Both squads have to agree' : 'Your rank cannot manage alliances'}</p></div>
          <button class="btn-ghost" data-act="refresh"><i class="fa-solid fa-rotate-right"></i></button></div>
        <div class="p-body scroll">${options.length ? options.map((x) => `<div class="row">${avatar(x.name, x.image, 'sm')}
          <div class="row-txt"><b>${esc(x.name)}${x.tag ? ` <span class="chip squad">${esc(x.tag)}</span>` : ''}</b>
            <span>${esc(x.owner)} · ${x.online} online</span></div>
          <div class="row-end">${tierBadge(x.tier, ` ${x.elo}`)}
            <button class="btn-line sm" data-allyask="${x.id}" ${!mayManage || full ? 'disabled' : ''}>Ask</button></div></div>`).join('')
          : `<div class="empty"><i class="fa-solid fa-users-slash"></i><b>No squads to ally with</b>
             <span>Permanent squads show up here once they exist.</span></div>`}</div>
      </section></div>
    </div>
  </div>`;
}

// ─── settings ──────────────────────────────────────────────
const HUD_COLORS = ['#ffffff', '#08afa2', '#58a6ff', '#e5484d', '#e5a50a', '#a078ff', '#8bd35a', '#ff7ad9'];
// GTA blip colour ids with the hex they render as, for the squad blip picker
const BLIP_PALETTE = [
  [2, '#4cd964'], [3, '#2f95dc'], [1, '#e5484d'], [5, '#e5a50a'], [27, '#a078ff'],
  [38, '#4fd1ff'], [0, '#ffffff'], [8, '#ff7ad9'], [17, '#ff9a3c'], [25, '#8bd35a'],
  [48, '#08afa2'], [40, '#9aa4ab'],
];
const blipHex = (id) => (BLIP_PALETTE.find(([i]) => i === id) || [0, '#ffffff'])[1];
const swLine = (key, title, sub) => `<div class="sw-line" data-set="${key}"><div><b>${title}</b>${sub ? `<span>${sub}</span>` : ''}</div><span class="sw ${state.settings[key] ? 'on' : ''}"><i></i></span></div>`;
const swatchRow = (key, list, custom) => `<div class="swatches">${list.map(([hex, id]) =>
  `<button class="swatch ${state.settings[key] === (id ?? hex) ? 'on' : ''}" style="background:${hex}" data-color="${key}" data-val="${id ?? hex}" aria-label="${hex}"></button>`).join('')}
  ${custom ? `<label class="swatch custom" title="Custom colour"><i class="fa-solid fa-eye-dropper"></i><input type="color" data-custom="${key}" value="${esc(state.settings[key])}"></label>` : ''}</div>`;

function viewSettings() {
  const c = state.cfg, st = state.settings, f = c.features;
  const maxOpts = [0, ...Array.from({ length: Math.max(0, c.maxMembers - 2) }, (_, i) => i + 2)];
  const nt = c.nametag || {};

  const seg = (key, options) => `<div class="seg">${options.map(([val, label]) =>
    `<button class="${st[key] === val ? 'on' : ''}" data-pick="${key}" data-val="${val}">${label}</button>`).join('')}</div>`;

  const slider = (key, label, min, max, step, suffix) => `<div class="field">
    <label>${label} <b class="slider-val" id="val-${key}">${st[key]}${suffix}</b></label>
    <input type="range" class="range" id="rng-${key}" data-range="${key}" min="${min}" max="${max}" step="${step}" value="${st[key]}"
      style="--fill:${((st[key] - min) / (max - min)) * 100}%"></div>`;

  return `<div class="page">
    <div class="head"><div><h1>Your settings</h1><p>These are yours alone — saved on your client and kept between sessions.</p></div>
      <button class="btn-ghost" data-act="resetSettings"><i class="fa-solid fa-rotate-left"></i>Reset all</button></div>
    <div class="cols"><div class="col">

    ${f.Hud ? `<section class="panel"><div class="p-head"><div><h2>Team HUD</h2><p>Squad health on your screen</p></div>
      <button class="btn-ghost" data-act="hudMove"><i class="fa-solid fa-up-down-left-right"></i>Move</button></div>
      <div class="p-body pad">
        ${swLine('hud', 'Show team HUD')}
        ${st.hud ? `
        <div class="divider"></div>
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
      <div class="p-body pad">${swLine('radio', 'Join squad radio automatically', 'You go on your squad\u2019s channel as soon as you join, and back to your old one when you leave')}</div>
    </section>` : ''}

    ${c.compass !== false ? `<section class="panel"><div class="p-head"><div><h2>Compass</h2><p>Heading strip at the top of your screen</p></div></div>
      <div class="p-body pad">
        ${swLine('compass', 'Show compass')}
        ${st.compass ? `${swLine('compassStreet', 'Street and area name')}${swLine('compassMarkers', 'Squad, rally and ping markers', 'With their distance')}` : ''}
      </div></section>` : ''}

    </div><div class="col">

    ${f.Tags ? `<section class="panel"><div class="p-head"><div><h2>Nametags</h2><p>What shows over your squadmates</p></div></div>
      <div class="p-body pad">
        ${swLine('tags', 'Show nametags')}
        ${st.tags ? `
        <div class="divider"></div>
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
        ${st.blips ? `
        <div class="divider"></div>
        ${f.SquadBlips ? swLine('blipUseSquad', 'Use squad colours', 'Each squad shows in the colour it picked') : ''}
        ${f.Affiliations ? swLine('blipAllies', 'Allied squads', 'Show allied players on your map') : ''}
        ${!f.SquadBlips || !st.blipUseSquad ? `<div class="field"><label>Blip colour</label>${swatchRow('blipColor', c.blipColors)}</div>` : ''}` : ''}
      </div></section>` : ''}

    <section class="panel"><div class="p-head"><div><h2>Alerts</h2><p>What gets your attention</p></div></div>
      <div class="p-body pad">
        ${swLine('chatNotify', 'Chat pop-ups', 'Show a toast for new squad messages')}
        ${swLine('chatSound', 'Chat sound')}
        ${f.Pings ? `<div class="divider"></div>${swLine('pingNotify', 'Ping pop-ups')}${swLine('pingSound', 'Ping sound')}` : ''}
        ${f.Revive ? swLine('reviveAlerts', 'Downed alerts', 'Alert and map ping when a squadmate goes down') : ''}
        ${f.Combat ? `<div class="divider"></div>${swLine('killfeed', 'Killfeed', 'Show kills against other squads')}${swLine('matchBanner', 'Fight results', 'Banner when a fight is scored')}` : ''}
      </div></section>

    </div></div>
  </div>`;
}

after.settings = () => {
  const sel = $('#hudMax');
  if (sel) sel.onchange = () => setSetting('hudMax', Number(sel.value));
  document.querySelectorAll('[data-custom]').forEach((el) => { el.oninput = debounce(() => setSetting(el.dataset.custom, el.value, true), 120); });

  // sliders update the HUD live, and only persist once the drag settles
  document.querySelectorAll('[data-range]').forEach((el) => {
    const key = el.dataset.range;
    const out = $(`#val-${key}`);
    const suffix = out ? out.textContent.replace(/[\d.-]/g, '') : '';
    el.oninput = () => {
      state.settings[key] = Number(el.value);
      el.style.setProperty('--fill', `${((el.value - el.min) / (el.max - el.min)) * 100}%`);
      if (out) out.textContent = el.value + suffix;
      applyHudStyle();
      renderHud();
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
  if (!a) {
    return `<div class="page"><div class="head"><div><h1>Staff tools</h1><p>Every squad on the server.</p></div></div>
      ${Array.from({ length: 4 }, () => `<div class="skel"><div class="sk circ"></div><div style="flex:1"><div class="sk" style="height:9px;width:44%"></div><div class="sk" style="height:7px;width:28%;margin-top:7px"></div></div></div>`).join('')}</div>`;
  }

  const rows = a.length ? a.map((s) => `<div class="row click ${state.adminOpen === s.id ? 'on' : ''}" data-adminsquad="${s.id}">${avatar(s.name, s.image, 'sm')}
    <div class="row-txt"><b>${esc(s.name)}${s.tag ? ` <span class="chip squad">${esc(s.tag)}</span>` : ''}</b>
      <span>ID ${s.id} · ${s.count} members · ${s.online} online</span></div>
    <div class="row-end">${tierBadge(s.tier, ` ${s.elo}`)}</div></div>`).join('')
    : '<div class="empty"><i class="fa-solid fa-users-slash"></i><b>No squads exist right now</b><span>Created squads will show up here.</span></div>';

  const sel = a.find((x) => x.id === state.adminOpen);
  const detail = sel ? `
    <div class="hero" style="--tier:${esc(tierOf(sel.tier).color)}">${avatar(sel.name, sel.image, 'lg')}
      <div class="hero-txt"><h2>${esc(sel.name)}${sel.tag ? `<span class="chip squad">${esc(sel.tag)}</span>` : ''}</h2>
        <p>ID ${sel.id} · created ${since(sel.created)} ago${sel.persistent ? ' · saved' : ' · session only'}</p>
        <div class="tags">${tierBadge(sel.tier, ` ${sel.elo}`)}<span class="tag off">${sel.wins}W ${sel.losses}L</span>
        <span class="tag off">${sel.kills}K ${sel.deaths}D</span></div></div></div>

    <div class="actions">
      <button class="btn-ghost" data-admin="setElo" data-sq="${sel.id}"><i class="fa-solid fa-sliders"></i>Set ELO</button>
      <button class="btn-ghost" data-admin="resetStats" data-sq="${sel.id}"><i class="fa-solid fa-rotate-left"></i>Reset stats</button>
      <button class="btn-ghost" data-admin="disband" data-sq="${sel.id}"><i class="fa-solid fa-ban"></i>Force disband</button>
    </div>

    <section class="panel"><div class="p-head"><div><h2>Members</h2><p>Server IDs shown for online players</p></div><span class="tally">${sel.count}</span></div>
      <div class="p-body scroll">${sel.members.map((m) => `<div class="row ${m.online ? '' : 'dim'}">${avatar(m.name, null, 'sm')}
        <div class="row-txt"><b>${esc(m.name)}</b><span><span class="rank ${m.owner ? 'owner' : ''}">${esc(m.rankName)}</span>${kdaHtml(m)}</span></div>
        <div class="row-end">${m.online ? `<span class="tally">${m.id}</span>` : '<span class="tag off">Offline</span>'}
        <button class="icon-btn danger" title="Remove from squad" data-admin="kick" data-sq="${sel.id}" data-target="${esc(m.identifier)}"><i class="fa-solid fa-user-minus"></i></button></div></div>`).join('')}</div>
    </section>`
    : `<div class="empty"><i class="fa-solid fa-hand-pointer"></i><b>Pick a squad</b>
       <span>Choose one on the left to see its roster, rating and staff actions.</span></div>`;

  return `<div class="page">
    <div class="head"><div><h1>Staff tools</h1><p>Inspect squads, remove members, adjust ratings or force a disband.</p></div>
      <button class="btn-ghost" data-act="refreshAdmin"><i class="fa-solid fa-rotate-right"></i>Refresh</button></div>
    <div class="cols">
      <div class="col"><section class="panel">
        <div class="p-head"><div><h2>All squads</h2><p>Most active first</p></div><span class="tally">${a.length}</span></div>
        <div class="p-body scroll">${rows}</div></section></div>
      <div class="col">${detail}</div>
    </div>
  </div>`;
}

// ─── team HUD ──────────────────────────────────────────────
// Cards come from team-hud.js (shared with the /hud settings previews). This file feeds them live data.
function hudAccentColor(m, h) {
  const mode = state.settings.hudAccent;
  if (mode === 'none') return null;
  if (mode === 'teal') return '#08afa2';
  if (mode === 'health') {
    if (h === undefined) h = ((m.id === state.me ? state.selfVitals : vit(m.id)) || { h: 100 }).h;
    return h <= 25 ? '#e5484d' : h <= 60 ? '#e5a50a' : '#08afa2';
  }
  return state.squad && state.squad.blipColor !== undefined ? blipHex(state.squad.blipColor) : '#08afa2';
}

const hudOpts = () => ({ ...state.settings, imgTpl: state.cfg && state.cfg.weaponImages });

function applyHudStyle() {
  const st = state.settings, hud = $('#hud');
  const hidden = hud.classList.contains('hidden'), editing = hud.classList.contains('editing');
  hud.className = TeamHud.hudClass(st) + (hidden ? ' hidden' : '') + (editing ? ' editing' : '');
  TeamHud.applyVars(hud, st);
  if (st.hudPos && typeof st.hudPos.x === 'number') {
    Object.assign(hud.style, { left: `${st.hudPos.x}%`, top: `${st.hudPos.y}%`, right: 'auto', bottom: 'auto', transformOrigin: 'top left' });
  } else {
    Object.assign(hud.style, { left: '', top: '', right: '', bottom: '', transformOrigin: '' });
  }
}

function hudCard(m, self) {
  const v = (self ? state.selfVitals : vit(m.id)) || { h: 100, a: 0 };
  const data = { ...v, talk: state.talking[m.id] || false };
  const mm = { id: m.id, name: m.name, avatar: safeImg(pickImg(m.avatar)), owner: m.owner, rank: m.rankName,
    kills: m.kills, deaths: m.deaths, down: isDown(m), downAt: state.downAt[m.id] };
  return TeamHud.card(mm, data, { ...hudOpts(), self, accent: hudAccentColor(m, v.h) });
}

const cardOf = (id) => document.querySelector(`#hud [data-hm="${Number(id) === state.me ? 'self' : id}"]`);

function renderHud() {
  const hud = $('#hud');
  const st = state.settings;
  const others = online().filter((m) => m.id !== state.me);
  const me = state.squad ? state.squad.members.find((m) => m.id === state.me) : null;
  const showSelf = st.hudShowSelf !== false && me;

  // the /hud Squads tab is open and you're not in a squad: show sample cards so changes are visible
  if (state.previewHud && !state.squad) {
    hud.classList.remove('hidden');
    hud.innerHTML = TeamHud.preview(st.hudStyle, hudOpts()).innerHTML;
    return;
  }

  // shown whenever you're in a squad; your own card keeps it visible even when you're alone
  const show = state.cfg && state.cfg.features.Hud && st.hud && state.squad
    && (others.length || showSelf || state.editingHud)
    && (!state.hudHidden || state.editingHud);
  hud.classList.toggle('hidden', !show);
  if (!show) return;

  const max = st.hudMax > 0 ? st.hudMax : others.length;
  const list = others.slice(0, max);
  const extra = others.length - list.length;
  hud.innerHTML = (showSelf ? hudCard(me, true) : '') + list.map((m) => hudCard(m, false)).join('')
    + (extra > 0 ? `<div class="hud-more">+${extra} more</div>` : '');
  TeamHud.restoreRevives(hud);
  TeamHud.tickTimers();
}

function patchVitals(changed) {
  const o = hudOpts();
  for (const id of Object.keys(changed)) {
    const m = state.squad.members.find((x) => String(x.id) === id);
    const v = changed[id];
    // your own card runs on the fresher local feed (selfVitals); the sync's copy of you is up to 750 ms old
    const card = Number(id) === state.me ? null : cardOf(id);
    if (card && m) {
      const down = isDown(m);
      if (card.classList.contains('down') !== down) { renderHud(); return; }
      TeamHud.patch(card, v, o);
      const c = state.settings.hudAccent === 'health' ? hudAccentColor(m, v.h) : null;
      if (c) card.style.setProperty('--accent', c);
    }
    const row = document.querySelector(`[data-member="${id}"] .bar-mini i`);
    if (row) { row.style.width = `${v.h}%`; row.classList.toggle('low', v.h <= 25); }
  }
}

// HUD drag
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
  else if (save) {
    if (state.pendingHudPos !== undefined) setSetting('hudPos', state.pendingHudPos, true);
  } else {
    state.settings.hudPos = state.hudPrevPos;
  }
  applyHudStyle();
  renderHud();
  if (!on && window.parent !== window) window.parent.postMessage({ nhud: 'hudMoveDone', hudPos: state.settings.hudPos || false }, '*');
}

// ─── ready check ───────────────────────────────────────────
function renderReady() {
  const box = $('#readyBox');
  const r = state.ready;
  if (!r) { box.innerHTML = ''; return; }

  if (r.done) {
    const members = state.squad ? online() : [];
    box.innerHTML = `<div class="ready"><h4><i class="fa-solid fa-list-check"></i>Ready check results</h4>
      <p>${Object.values(r.answers).filter(Boolean).length} of ${members.length} ready</p>
      <div class="ready-list">${members.map((m) => {
        const a = r.answers[String(m.id)];
        return `<span class="ready-pill ${a === true ? 'yes' : a === false ? 'no' : ''}">
          <i class="fa-solid ${a === true ? 'fa-check' : a === false ? 'fa-xmark' : 'fa-clock'}"></i>${esc(m.name)}</span>`;
      }).join('')}</div></div>`;
    return;
  }

  box.innerHTML = `<div class="ready"><h4><i class="fa-solid fa-circle-check"></i>Ready check</h4>
    <p>${esc(r.by)} is asking if the squad is good to go</p>
    ${r.answered ? '<div class="ready-list"><span class="ready-pill yes"><i class="fa-solid fa-check"></i>Answer sent</span></div>'
      : `<div class="ready-acts"><button class="btn-line sm" data-ready="0"><i class="fa-solid fa-xmark"></i>Not yet</button>
         <button class="btn-teal sm" data-ready="1"><i class="fa-solid fa-check"></i>Ready</button></div>`}
    <div class="ready-bar"><i style="--dur:${r.duration}s"></i></div></div>`;
}

// ─── killfeed & match result ───────────────────────────────
function killfeed(d) {
  const feed = $('#feed');
  const el = document.createElement('div');
  el.className = `feed-row ${d.good ? '' : 'bad'}`;
  el.innerHTML = `<b>${esc(d.killer)}</b><i class="fa-solid fa-skull"></i><b>${esc(d.victim)}</b>
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
    <p>${d.tier} · ${d.elo} ELO</p>
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
// The strip holds three identical laps; we always sit in the middle one, so crossing north
// never visibly jumps. Lua sends a heading only when you turn, and requestAnimationFrame
// eases the needle toward it so it stays smooth between updates.
const CP = { W: 520, PX: 3.2, target: 0, shown: 0, markers: [], built: false, running: false, visible: false };
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

function shortest(from, to) { return ((to - from + 540) % 360) - 180; }

function compassFrame() {
  if (!CP.visible) { CP.running = false; return; }
  // ease toward the target heading along the shorter way round
  const delta = shortest(CP.shown, CP.target);
  CP.shown = Math.abs(delta) < 0.05 ? CP.target : (CP.shown + delta * 0.35 + 360) % 360;

  $('#cpStrip').style.transform = `translateX(${CP.W / 2 - (360 + CP.shown) * CP.PX}px)`;
  const h = Math.round(CP.shown) % 360;
  $('#cpDir').textContent = dirOf(h);
  $('#cpDeg').textContent = `${h}°`;

  // markers: inside the visible arc they ride the strip, outside it they pin to an edge
  const half = CP.W / 2 / CP.PX - 4;
  const box = $('#cpMarks');
  CP.markers.forEach((m, i) => {
    const el = box.children[i];
    if (!el) return;
    const rel = shortest(CP.shown, m.b);
    const edge = Math.abs(rel) > half;
    const x = edge ? (rel < 0 ? 6 : CP.W - 6) : CP.W / 2 + rel * CP.PX;
    el.style.left = `${x}px`;
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
    // first reading snaps instead of sweeping round from north
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
  if (r) { state.list = r.list; state.invites = r.invites; if (r.status) state.status = r.status; }
  if (['browse', 'preview'].includes(state.view)) render(); else renderChrome();
}

async function loadStats() {
  state.stats = await nui('stats');
  if (state.view === 'stats') render();
}

async function loadBoard() {
  state.board = await nui('leaderboard');
  if (state.view === 'board') render();
}

async function loadAdmin() {
  state.admin = await nui('adminList');
  if (parentView(state.view) === 'admin') render();
}

async function joinSquad(id, password) {
  const r = await nui('join', { id, password });
  if (result(r, 'Joined squad', 'Say hi in the squad chat.')) {
    state.invites = state.invites.filter((i) => i.id !== id);
    state.view = 'squad';
  }
}

async function rankMenu(identifier) {
  const s = state.squad;
  const m = s.members.find((x) => x.identifier === identifier);
  if (!m) return;
  const mine = s.you.rank;
  const options = s.ranks.map((r, i) => ({ level: i + 1, name: r.name }))
    .filter((r) => r.level < s.ranks.length && (mine >= s.ranks.length || r.level < mine) && r.level !== m.rank);
  if (!options.length) return toast('No ranks available', 'There is no rank you can move them to.', 'error');

  const picked = await confirmModal({
    title: `Change rank for ${m.name}`,
    text: `Currently ${m.rankName}. Enter a new rank: ${options.map((o) => `${o.level} = ${o.name}`).join(', ')}.`,
    confirm: 'Set rank', danger: false, icon: 'fa-arrow-up-right-dots',
    input: { placeholder: 'Rank number', value: String(options[options.length - 1].level) },
  });
  if (picked === false || picked === null) return;
  const level = Number(picked);
  if (!options.some((o) => o.level === level)) return toast('Unknown rank', 'Pick one of the listed rank numbers.', 'error');
  result(await nui('setRank', { identifier, rank: level }), 'Rank updated', `${m.name} is now ${s.ranks[level - 1].name}.`);
}

document.addEventListener('click', async (e) => {
  const t = e.target.closest('button, [data-preview], [data-set], [data-ftoggle], [data-rperm], [data-adminsquad], .swatch');
  if (e.target.closest('.range')) return;
  if (!t || t.closest('#modal')) return;
  const d = t.dataset;

  if (d.ready !== undefined) {
    nui('readyAnswer', { answer: d.ready === '1' });
    if (state.ready) { state.ready.answered = true; renderReady(); }
    return;
  }
  if (d.revive !== undefined) {
    const idx = Number(d.revive);
    const opts = state.revive ? state.revive.options : null;
    $('#revivePicker').innerHTML = '';
    nui('revivePick', { index: idx < 0 ? null : idx, options: opts });
    state.revive = null;
    return;
  }

  if (d.tab) {
    if (d.tab === 'create' || d.tab === 'edit') state.form = null;
    if (d.tab === 'ranks') state.ranksDraft = null;
    if (d.tab === 'stats') loadStats();
    if (d.tab === 'allies' && !state.list) refreshList();
    if (d.tab === 'board' && !state.board) loadBoard();
    if (d.tab === 'admin' && !state.admin) loadAdmin();
    return go(d.tab);
  }
  if (d.board) { state.boardTab = d.board; return render(); }
  if (d.preview) { state.preview = Number(d.preview); return go('preview'); }
  if (d.adminsquad) { state.adminOpen = Number(d.adminsquad); return render(); }
  if (d.join) return joinSquad(Number(d.join), $('#joinPass')?.value || undefined);
  if (d.accept) return joinSquad(Number(d.accept));
  if (d.decline) {
    const id = Number(d.decline);
    state.invites = state.invites.filter((i) => i.id !== id);
    nui('declineInvite', { id }); return render();
  }
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

  // ranks editor
  if (d.rperm) {
    const r = state.ranksDraft[Number(d.rperm)];
    r.perms = r.perms || {};
    r.perms[d.perm] = !r.perms[d.perm];
    return render();
  }
  if (d.ricon) { state.ranksDraft[Number(d.ricon)].icon = d.icon; return render(); }
  if (d.rup) { const i = Number(d.rup); const a = state.ranksDraft; [a[i], a[i + 1]] = [a[i + 1], a[i]]; return render(); }
  if (d.rdown) { const i = Number(d.rdown); const a = state.ranksDraft; [a[i], a[i - 1]] = [a[i - 1], a[i]]; return render(); }
  if (d.rdel) { state.ranksDraft.splice(Number(d.rdel), 1); return render(); }

  // member actions
  if (d.kick) {
    const m = state.squad.members.find((x) => x.identifier === d.kick);
    if (m && await confirmModal({ title: `Remove ${m.name}?`, text: 'They leave the squad right away and lose their place on the roster.', confirm: 'Remove member' })) {
      result(await nui('kick', { identifier: m.identifier }), 'Member removed', `${m.name} is no longer in the squad.`);
    }
    return;
  }
  if (d.allyask) {
    const sq = (state.list || []).find((x) => x.id === Number(d.allyask));
    if (sq && await confirmModal({ title: `Ally with ${sq.name}?`, text: 'They have to accept before the alliance starts. Allied squads see each other, cannot hurt each other, and never take ELO off one another.', confirm: 'Send request', danger: false, icon: 'fa-handshake' })) {
      result(await nui('allyRequest', { id: sq.id }), 'Request sent');
    }
    return;
  }
  if (d.allyyes) return result(await nui('allyRespond', { id: Number(d.allyyes), accept: true }), 'Alliance formed');
  if (d.allyno) return result(await nui('allyRespond', { id: Number(d.allyno), accept: false }), 'Request declined');
  if (d.allyend) {
    const a = (state.squad.allies || []).find((x) => x.id === Number(d.allyend));
    if (a && await confirmModal({ title: `End the alliance with ${a.name}?`, text: 'Both squads stop seeing each other, and friendly fire comes back on.', confirm: 'End alliance' })) {
      result(await nui('allyRemove', { id: a.id }), 'Alliance ended');
    }
    return;
  }
  if (d.nick) {
    const meRec = state.squad.members.find((x) => x.id === state.me) || {};
    const nk = state.cfg.nicknames || {};
    const value = await confirmModal({
      title: 'Your squad nickname',
      text: `What your squad sees instead of your character name, on the HUD, nametags, map and chat. ${nk.min || 2}–${nk.max || 20} characters. Leave it blank to go back to ${meRec.realName || 'your name'}.`,
      confirm: 'Save nickname', danger: false, icon: 'fa-signature',
      input: { placeholder: meRec.realName || 'Nickname', value: meRec.nick || '', max: nk.max || 20 },
    });
    if (value === false || value === null) return;
    return result(await nui('setNick', { nick: value }), 'Nickname updated');
  }
  if (d.nickreset) {
    const m = state.squad.members.find((x) => x.identifier === d.nickreset);
    if (m && await confirmModal({ title: `Reset ${m.name}'s nickname?`, text: `They go back to showing as ${m.realName}.`, confirm: 'Reset nickname' })) {
      result(await nui('setNick', { nick: '', identifier: m.identifier }), 'Nickname reset');
    }
    return;
  }
  if (d.rankmenu) return rankMenu(d.rankmenu);
  if (d.transfer) {
    const m = state.squad.members.find((x) => x.identifier === d.transfer);
    if (m && await confirmModal({ title: `Hand the squad to ${m.name}?`, text: 'They become the owner and you drop to the rank below. This cannot be undone by you.', confirm: 'Transfer ownership', danger: false, icon: 'fa-crown' })) {
      result(await nui('transfer', { identifier: m.identifier }), 'Ownership transferred', `${m.name} now owns the squad.`);
    }
    return;
  }

  // admin actions
  if (d.admin) {
    const squadId = Number(d.sq);
    if (d.admin === 'disband') {
      if (!await confirmModal({ title: 'Force disband this squad?', text: 'Everyone is removed and the squad is deleted from the database.', confirm: 'Disband squad' })) return;
    }
    if (d.admin === 'resetStats') {
      if (!await confirmModal({ title: 'Reset this squad\'s stats?', text: 'ELO, wins, losses and every member\'s K/D/A go back to zero.', confirm: 'Reset stats' })) return;
    }
    let value;
    if (d.admin === 'setElo') {
      value = await confirmModal({ title: 'Set squad ELO', text: 'Enter the new rating for this squad.', confirm: 'Set rating', danger: false, icon: 'fa-sliders', input: { placeholder: '1000', value: '1000' } });
      if (value === false || value === null) return;
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
    case 'rally': return result(await nui('rally', {}), 'Rally point set', 'Your squad has a route to it.');
    case 'rallyClear': return result(await nui('rally', { clear: true }), 'Rally cleared');
    case 'addRank':
      state.ranksDraft.splice(state.ranksDraft.length - 1, 0, { name: 'New rank', icon: 'fa-user', perms: {} });
      return render();
    case 'resetRanks': state.ranksDraft = null; return render();
    case 'saveRanks':
      if (result(await nui('setRanks', { ranks: state.ranksDraft }), 'Ranks saved', 'Everyone sees the new ranks now.')) {
        state.ranksDraft = null;
        go('squad');
      }
      return;
    case 'invite': {
      const id = Number($('#inviteId')?.value);
      if (!id) return toast('Add a server ID', 'Enter the ID of the player you want to invite.', 'error');
      if (result(await nui('invite', { id }), 'Invite sent')) $('#inviteId').value = '';
      return;
    }
    case 'leave': {
      const s = state.squad;
      if (!s) return;
      if (s.persistent) {
        const stay = await confirmModal({
          title: 'Leave this squad?',
          text: 'You stay on the roster and keep your rank and stats, so you can rejoin later. To give up your place for good, use Disband or ask the owner to remove you.',
          confirm: 'Leave for now', danger: false, icon: 'fa-right-from-bracket',
        });
        if (stay) await nui('leave', { forget: false });
      } else if (await confirmModal({ title: 'Leave this squad?', text: 'You can rejoin later if the squad is still open.', confirm: 'Leave squad' })) {
        await nui('leave', { forget: true });
      }
      return;
    }
    case 'disband':
      if (await confirmModal({ title: 'Disband the squad?', text: 'Every member is removed and the squad, its ranks and its rating are deleted. This cannot be undone.', confirm: 'Disband squad' })) {
        result(await nui('disband'), 'Squad disbanded', 'Everyone was removed.');
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
    if (state.revive) { $('#revivePicker').innerHTML = ''; nui('revivePick', { index: null }); state.revive = null; return; }
    if (state.editingHud) return hudEdit(false, false);
    if (state.modalClose) return state.modalClose();
    if (state.open) return nui('close');
  }
  if (e.key === 'Tab' && state.open && !state.editingHud) {
    e.preventDefault();
    const tabs = tabsFor().map((x) => x[0]);
    const cur = parentView(state.view);
    const next = tabs[(tabs.indexOf(cur) + (e.shiftKey ? tabs.length - 1 : 1)) % tabs.length];
    if (next === 'stats') loadStats();
    if (next === 'board' && !state.board) loadBoard();
    if (next === 'admin' && !state.admin) loadAdmin();
    go(next);
  }
});

setInterval(() => { const el = document.querySelector('[data-since]'); if (el) el.textContent = since(Number(el.dataset.since)); }, 30000);

// ─── messages from Lua ─────────────────────────────────────
const handlers = {
  open({ squad, view }) {
    state.open = true;
    state.squad = squad || null;
    state.view = view || (state.squad ? (state.view === 'chat' ? 'chat' : 'squad') : 'browse');
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
  list({ list, invites, status }) {
    state.list = list; state.invites = invites;
    if (status) state.status = status;
    if (state.open) { if (['browse', 'preview'].includes(state.view)) render(); else renderChrome(); }
  },
  listUpdate(list) {
    state.list = list;
    if (!state.open) return;
    if (state.view === 'browse') {
      const focused = document.activeElement && document.activeElement.id === 'search';
      if (!focused) render(); else renderChrome();
    } else if (state.view === 'preview') render(); else renderChrome();
  },
  squad(sq) {
    const prevId = state.squad && state.squad.id;
    state.squad = sq || null;
    // bleed-out timers: the server says how long each downed member has been down
    if (sq) {
      for (const m of sq.members) {
        if (m.downed && m.downedFor != null) state.downAt[m.id] = state.downAt[m.id] || Date.now() - m.downedFor * 1000;
        else if (!m.downed) delete state.downAt[m.id];
      }
    } else state.downAt = {};
    if (!sq) { state.chat = []; state.unread = 0; state.talking = {}; state.stats = null; state.ready = null; renderReady(); }
    if (sq && prevId !== sq.id) { state.unread = 0; state.stats = null; }
    renderHud();
    if (!state.open) return;
    if (!sq && ['squad', 'chat', 'edit', 'ranks', 'stats'].includes(state.view)) { state.view = 'browse'; refreshList(); }
    // keep unsaved edits on screen, but a brand new squad takes you straight to it
    if (state.view === 'ranks' || state.view === 'edit') { renderChrome(); if (!sq) render(); return; }
    if (state.view === 'chat') renderChrome(); else render();
  },
  chatHistory(list) { state.chat = list || []; if (state.open && state.view === 'chat') render(); },
  chat({ msg, notify }) {
    state.chat.push(msg);
    if (state.chat.length > 80) state.chat.shift();
    if (state.open && state.view === 'chat') appendChat(msg);
    else if (!msg.system && msg.from !== state.me) {
      state.unread++;
      if (state.open) renderChrome();
      if (notify && state.settings.chatNotify) toast(msg.name, msg.text, 'info', { icon: 'fa-message' });
    }
  },
  vitals(changed) {
    if (!state.squad) return;
    state.squad.vitals = state.squad.vitals || {};
    Object.assign(state.squad.vitals, changed);
    patchVitals(changed);
  },
  downed({ id, state: down, since }) {
    if (!state.squad) return;
    const m = state.squad.members.find((x) => x.id === id);
    if (m) m.downed = down;
    if (down) state.downAt[id] = Date.now() - (Number(since) || 0) * 1000; else delete state.downAt[id];
    renderHud();
    if (state.open && state.view === 'squad') render(); else if (state.open) renderChrome();
  },
  talking(diff) {
    for (const id of Object.keys(diff)) {
      const t = diff[id] === true ? 'mic' : diff[id] || false;
      state.talking[id] = t;
      TeamHud.talk(cardOf(id), t, state.settings);
    }
  },
  // a squadmate took damage: { id, d (damage) }
  hit(d) {
    if (!d || state.settings.hudHits === false) return;
    TeamHud.hit(cardOf(d.id), d.d);
  },
  // someone started (ms) or stopped (false) reviving a downed squadmate: { id, by, ms }
  reviving(d) {
    if (!d) return;
    TeamHud.reviving(cardOf(d.id), d.ms ? { by: d.by, ms: d.ms } : false);
  },
  // shots a squadmate fired: { id, b (burst), o (ms offsets inside the burst) }
  shots(d) {
    if (!d || state.settings.hudShots === false) return;
    TeamHud.shots(cardOf(d.id), String(d.id), d.b, d.o);
  },
  hudHidden(v) { state.hudHidden = v; renderHud(); },
  selfVitals(v) {
    state.selfVitals = { ...(state.selfVitals || {}), ...v };
    const card = cardOf(state.me);
    if (!card) return renderHud();
    TeamHud.patch(card, state.selfVitals, hudOpts());
    if (state.settings.hudAccent === 'health') card.style.setProperty('--accent', hudAccentColor({ id: state.me }, state.selfVitals.h));
  },
  invite(inv) {
    state.invites = [inv, ...state.invites.filter((i) => i.id !== inv.id)];
    if (state.open) { if (state.view === 'browse') render(); else renderChrome(); }
  },
  toast({ title, text, kind, duration }) { toast(title, text, kind, { local: true, duration }); },
  pingToast({ type, name, auto }) {
    const p = state.cfg.pings[type]; if (!p) return;
    toast(p.label, auto ? `${name} is down` : `${name} placed a ping`, auto ? 'warning' : 'info',
      { icon: p.icon, color: p.color, duration: auto ? 6000 : 3500 });
  },
  wheel(on) { openWheel(on); },
  compass(d) { compassUpdate(d); },
  wheelRelease() { wheelFinish(true); },
  killfeed(d) { if (state.settings.killfeed !== false) killfeed(d); },
  matchResult(d) {
    if (state.settings.matchBanner !== false) matchResult(d);
    if (state.open && state.view === 'stats') loadStats();
  },
  revived({ by, item }) { toast('Revived', `${by} brought a squadmate back with a ${String(item).toLowerCase()}.`, 'info', { icon: 'fa-kit-medical' }); },
  readyCheck({ by, duration }) { state.ready = { by, duration, answers: {}, answered: false }; renderReady(); },
  readyResult(answers) {
    if (!state.ready) state.ready = {};
    state.ready = { ...state.ready, done: true, answers: answers || {} };
    renderReady();
    setTimeout(() => { if (state.ready && state.ready.done) { state.ready = null; renderReady(); } }, 6000);
  },
  revivePrompt(d) {
    const box = $('#revivePrompt');
    if (!d) { box.innerHTML = ''; return; }
    box.innerHTML = `<div class="revive-prompt"><i class="fa-solid fa-kit-medical" style="color:var(--red)"></i>
      <span>${d.hold === false ? 'Press' : 'Hold'} <span class="key">${esc(d.key)}</span> to revive <b>${esc(d.name)}</b></span></div>`;
  },
  revivePicker({ name, options }) {
    state.revive = { options };
    $('#revivePicker').innerHTML = `<div class="revive-picker"><div class="picker-card">
      <h4>Revive ${esc(name)}</h4><p>Pick what you want to use</p>
      ${options.map((o, i) => `<button class="picker-opt" data-revive="${i}">
        <span class="pi"><i class="fa-solid ${esc(o.icon)}"></i></span>
        <span style="flex:1"><b>${esc(o.label)}</b><span>${Math.round(o.time / 1000)}s · restores ${o.health}% health</span></span>
        <i class="fa-solid fa-chevron-right" style="color:var(--ink-3);font-size:11px"></i></button>`).join('')}
      <button class="btn-line full" data-revive="-1" style="margin-top:4px">Cancel</button></div></div>`;
  },
};

// nayzeee-hud: the HUD settings edit these settings, preview the cards and start the move tool
handlers.settings = (d) => { if (d && typeof d === 'object') { state.settings = { ...state.settings, ...d }; applyHudStyle(); renderHud(); } };
handlers.hudPreview = (on) => { state.previewHud = !!on; applyHudStyle(); renderHud(); };
handlers.hudMove = () => { state.previewHud = true; hudEdit(true); };
// the inventory started after the HUD: rebuild the cards so the guns use its pictures
handlers.weaponImages = (tpl) => {
  if (!state.cfg) return;
  state.cfg.weaponImages = tpl;
  document.querySelectorAll('#hud [data-w]').forEach((el) => { el.dataset.w = '\u0000'; });
  renderHud();
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
  TeamHud.setBleed(state.cfg.bleedOut);
  $('#ver').textContent = `v${state.cfg.version}`;
  applyHudStyle();
  renderHud();
}

// ─── browser preview (only outside FiveM) ──────────────────
const Dev = {
  av: (k) => (window.__DEV_AVATARS && window.__DEV_AVATARS[k]) || null,
  squad: null,
  handle(name, data) {
    switch (name) {
      case 'ready': return {
        me: 1, squad: null, chat: [],
        settings: { hud: true, hudMinimized: false, hudTalking: true, hudKda: true, hudMax: 0,
          hudHealth: '#ffffff', hudArmor: '#58a6ff', hudPos: false, hudAvatars: true, hudRank: false,
          hudArmorBar: true, hudAccent: 'squad', hudStyle: 'cards', hudScale: 100, hudOpacity: 86, hudShowSelf: true,
          hudWeapon: true, hudShots: true, hudAmmo: true, hudHits: true, hudVehicle: true, animatedAvatars: true,
          tags: true, tagColor: 18, tagName: true, tagSquadTag: true, tagRole: true, tagHealth: true, tagAllies: true,
          blips: true, blipUseSquad: true, blipColor: 2, blipAllies: true,
          chatNotify: true, chatSound: true, pingNotify: true, pingSound: true, reviveAlerts: true,
          killfeed: true, matchBanner: true, radio: true, hudShowSelf: true,
          compass: true, compassStreet: true, compassMarkers: true },
        config: {
          version: '2.2.0', maxMembers: 8, minMembers: 2, nameMin: 3, nameMax: 24, tagMin: 2, tagMax: 4,
          chatMax: 180, maxRanks: 6, voice: true, eloStart: 1000,
          features: { Hud: true, Tags: true, Blips: true, Pings: true, Waypoint: true, Relations: true,
            Combat: true, Revive: true, ReadyCheck: true, Rally: true, DownedAlert: true, Leaderboard: true,
            Affiliations: true, SquadBlips: true, AutoRadio: true },
          squadTypes: { temporary: true, permanent: true, default: 'permanent', tempHours: 6 },
          blipSprites: [{ id: 1, label: 'Dot', icon: 'fa-circle' }, { id: 480, label: 'Skull', icon: 'fa-skull' },
            { id: 303, label: 'Target', icon: 'fa-crosshairs' }, { id: 487, label: 'Shield', icon: 'fa-shield-halved' },
            { id: 491, label: 'Star', icon: 'fa-star' }, { id: 310, label: 'Crown', icon: 'fa-crown' },
            { id: 437, label: 'Flame', icon: 'fa-fire' }, { id: 442, label: 'Diamond', icon: 'fa-gem' }],
          allyMax: 2, allyShareChat: false, autoRadio: true, notify: 'ox_lib', compass: true, bleedOut: 300,
          nicknames: { enabled: true, max: 20, min: 2, temp: true },
          nametag: { Name: true, Tag: true, Role: true, Health: true, Allies: true },
          blipColors: [['#08afa2', 2], ['#e5484d', 1], ['#58a6ff', 3], ['#e5a50a', 5], ['#a078ff', 27], ['#ffffff', 0]],
          tagColors: [['#72cc72', 18], ['#e5484d', 6], ['#58a6ff', 9], ['#e5a50a', 12], ['#a078ff', 21], ['#ffffff', 0]],
          rankIcons: ['fa-user', 'fa-user-check', 'fa-user-shield', 'fa-user-tie', 'fa-crown', 'fa-star', 'fa-shield-halved', 'fa-gun', 'fa-kit-medical', 'fa-car-side'],
          perms: [{ key: 'invite', label: 'Invite players' }, { key: 'kick', label: 'Remove members' }, { key: 'promote', label: 'Change member ranks' },
                  { key: 'edit', label: 'Edit squad details' }, { key: 'ranks', label: 'Manage ranks' }, { key: 'rally', label: 'Set rally points' },
                  { key: 'ready', label: 'Start ready checks' }, { key: 'disband', label: 'Disband the squad' }],
          tiers: Dev.tiers,
          pings: { go: { label: 'Go here', icon: 'fa-location-arrow', color: '#08afa2' }, enemy: { label: 'Enemy', icon: 'fa-crosshairs', color: '#e5484d' },
                   danger: { label: 'Danger', icon: 'fa-triangle-exclamation', color: '#e5a50a' }, loot: { label: 'Loot', icon: 'fa-box-open', color: '#ffffff' },
                   defend: { label: 'Defend', icon: 'fa-shield-halved', color: '#58a6ff' }, vehicle: { label: 'Vehicle', icon: 'fa-car-side', color: '#a078ff' },
                   downed: { label: 'Member down', icon: 'fa-heart-crack', color: '#e5484d' }, rally: { label: 'Rally', icon: 'fa-flag', color: '#08afa2' } },
          wheel: ['go', 'enemy', 'danger', 'loot', 'defend', 'vehicle'], defaults: {},
        },
      };
      case 'setNick': {
        if (!Dev.squad) return { ok: false };
        const m = Dev.squad.members.find((x) => (data.identifier ? x.identifier === data.identifier : x.id === 1));
        if (!m) return { ok: false };
        m.realName = m.realName || m.name;
        const nick = String(data.nick || '').trim();
        m.nick = nick || null;
        m.name = nick || m.realName;
        if (!nick) delete m.realName;
        setTimeout(() => handlers.squad(Dev.squad), 30);
        return { ok: true, msg: nick ? `You now go by ${nick}` : 'Nickname cleared' };
      }
      case 'refresh': return { status: { permanent: true }, list: Dev.list, invites: [{ id: 9, name: 'Grove Runners', tag: 'GRV', fromAvatar: Dev.av('tay'), from: 'Dre Walker', owner: 'Dre Walker', count: 3, limit: 6, elo: 1040, tier: { name: 'Gold', color: '#e5a50a' } }] };
      case 'checkName': return { ok: String(data.name).toLowerCase() !== 'ballas', msg: 'That name is taken' };
      case 'create': case 'join': {
        const s = Dev.makeSquad(data && data.name, data && data.temporary);
        Dev.squad = s;
        setTimeout(() => {
          handlers.squad(s);
          handlers.chatHistory([{ system: true, text: 'NayZeee created the squad', t: Date.now() / 1000 - 1500 },
            { from: 14, name: 'Tay Brooks', avatar: Dev.av('tay'), rank: 'Officer', text: 'pull up to legion, got the car', t: Date.now() / 1000 - 60 }]);
        }, 50);
        return { ok: true };
      }
      case 'stats': return { members: Dev.squad ? Dev.squad.members : [], active: Dev.active, history: Dev.history };
      case 'leaderboard': return { persistent: true, squads: Dev.board, players: Dev.players };
      case 'adminList': return Dev.adminList();
      case 'chat': setTimeout(() => handlers.chat({ msg: { from: 1, name: 'NayZeee', avatar: Dev.av('nay'), rank: 'Leader', text: data.text, t: Date.now() / 1000 } }), 30); return { ok: true };
      case 'leave': case 'disband': setTimeout(() => handlers.squad(null), 30); Dev.squad = null; return { ok: true };
      case 'setRanks': if (Dev.squad) { Dev.squad.ranks = data.ranks; setTimeout(() => handlers.squad(Dev.squad), 30); } return { ok: true };
      case 'readyCheck': setTimeout(() => handlers.readyCheck({ by: 'NayZeee', duration: 20 }), 40); return { ok: true };
      case 'allyRequest': return { ok: true, msg: 'Request sent' };
      case 'allyRespond':
        if (Dev.squad && data.accept) {
          const req = (Dev.squad.allyRequests || []).find((r) => r.id === data.id);
          if (req) {
            Dev.squad.allies.push({ id: req.id, name: req.name, tag: req.tag, image: '', elo: req.elo, tier: req.tier, online: 3, blipColor: 1, since: Date.now() / 1000 });
            Dev.squad.allyRequests = Dev.squad.allyRequests.filter((r) => r.id !== data.id);
          }
        } else if (Dev.squad) {
          Dev.squad.allyRequests = (Dev.squad.allyRequests || []).filter((r) => r.id !== data.id);
        }
        setTimeout(() => handlers.squad(Dev.squad), 30);
        return { ok: true };
      case 'allyRemove':
        if (Dev.squad) Dev.squad.allies = Dev.squad.allies.filter((a) => a.id !== data.id);
        setTimeout(() => handlers.squad(Dev.squad), 30);
        return { ok: true };
      case 'wheelSelect': setTimeout(() => handlers.pingToast({ type: data.type, name: 'Tay Brooks' }), 60); return 1;
      case 'close': return 1;
      default: return { ok: true };
    }
  },
  tiers: [{ name: 'Bronze', min: 0, color: '#b4713d' }, { name: 'Silver', min: 900, color: '#9aa4ab' }, { name: 'Gold', min: 1100, color: '#e5a50a' },
          { name: 'Platinum', min: 1300, color: '#4fd1ff' }, { name: 'Diamond', min: 1500, color: '#a078ff' }, { name: 'Elite', min: 1750, color: '#08afa2' }],
  ranks: [{ name: 'Recruit', icon: 'fa-user', perms: {} },
          { name: 'Member', icon: 'fa-user-check', perms: { invite: true, ready: true } },
          { name: 'Officer', icon: 'fa-user-shield', perms: { invite: true, kick: true, ready: true, rally: true } },
          { name: 'Leader', icon: 'fa-crown', perms: { invite: true, kick: true, promote: true, edit: true, ranks: true, ready: true, rally: true, disband: true } }],
  makeSquad(name, temp) {
    const R = Dev.ranks;
    return {
      id: 1, name: name || 'Southside Crew', tag: 'SSC', image: '', locked: false, inviteOnly: false, limit: 6,
      owner: 'char:nay', persistent: true, temporary: temp === true, blipColor: 2, blipSprite: 480,
      allyMax: 2, ranks: R, created: Date.now() / 1000 - 5400,
      allies: temp ? [] : [{ id: 3, name: 'Vinewood Night Shift', tag: 'VNS', image: '', elo: 980,
        tier: { name: 'Silver', color: '#9aa4ab' }, online: 2, blipColor: 3, since: Date.now() / 1000 - 86400 }],
      allyRequests: temp ? [] : [{ id: 2, name: 'Ballas', tag: 'BLS', image: '', elo: 1420,
        tier: { name: 'Platinum', color: '#4fd1ff' }, by: 'Big Smoke', expires: 94 }],
      allyMembers: {},
      elo: 1285, tier: { name: 'Gold', min: 1100, color: '#e5a50a' }, tierProgress: 0.92, nextTier: { name: 'Platinum', min: 1300 },
      wins: 11, losses: 5, draws: 1, kills: 94, deaths: 61, assists: 38,
      you: { rank: 4, perms: { invite: true, kick: true, promote: true, edit: true, ranks: true, rally: true, ready: true, disband: true } },
      members: [
        { id: 1, identifier: 'char:nay', name: 'NayZeee', avatar: Dev.av('nay'), rank: 4, rankName: 'Leader', rankIcon: 'fa-crown', owner: true, online: true, kills: 31, deaths: 14, assists: 9, revives: 6 },
        { id: 14, identifier: 'char:tay', name: 'Tay', realName: 'Taylor Brooks', nick: 'Tay', avatar: Dev.av('tay'), rank: 3, rankName: 'Officer', rankIcon: 'fa-user-shield', owner: false, online: true, kills: 27, deaths: 18, assists: 12, revives: 3 },
        { id: 22, identifier: 'char:mar', name: 'Marcus Hill', avatar: Dev.av('marcus'), rank: 2, rankName: 'Member', rankIcon: 'fa-user-check', owner: false, online: true, downed: true, downedFor: 42, kills: 19, deaths: 16, assists: 11, revives: 1 },
        { id: 31, identifier: 'char:kei', name: 'Keisha Moore', avatar: Dev.av('keisha'), rank: 2, rankName: 'Member', rankIcon: 'fa-user-check', owner: false, online: true, kills: 14, deaths: 9, assists: 6, revives: 4 },
        { id: null, identifier: 'char:dee', name: 'Dee Carter', avatar: null, rank: 1, rankName: 'Recruit', rankIcon: 'fa-user', owner: false, online: false, kills: 3, deaths: 4, assists: 0, revives: 0 },
      ],
      vitals: { 14: { h: 82, a: 60, w: 'WEAPON_PISTOL50', wl: 'Pistol .50', c: 2, m: 9, t: 27 }, 22: { h: 0, a: 0 }, 31: { h: 21, a: 100, vk: 'heli', vn: 'Maverick', vs: 'p' } },
    };
  },
  list: [
    { id: 2, name: 'Ballas', tag: 'BLS', image: '', locked: true, inviteOnly: false, limit: 8, count: 5, online: 3, elo: 1420, blipColor: 1, tier: { name: 'Platinum', color: '#4fd1ff' }, wins: 19, losses: 9, owner: 'Big Smoke', members: [{ name: 'Big Smoke', online: true }, { name: 'Kane', online: true }, { name: 'Rico', online: false }, { name: 'Jay', online: true }, { name: 'Deshawn', online: false }] },
    { id: 3, name: 'Vinewood Night Shift', tag: 'VNS', image: '', locked: false, inviteOnly: false, limit: 4, count: 2, online: 2, elo: 980, blipColor: 3, tier: { name: 'Silver', color: '#9aa4ab' }, wins: 4, losses: 7, owner: 'Ari Cole', members: [{ name: 'Ari Cole', online: true }, { name: 'Jules', online: true }] },
    { id: 7, name: 'Pier Run', tag: 'PIER', image: '', locked: false, inviteOnly: false, limit: 4, count: 3, online: 3, elo: 1000, blipColor: 17, temporary: true, tier: { name: 'Gold', color: '#e5a50a' }, wins: 0, losses: 0, owner: 'Mika', members: [{ name: 'Mika', online: true }, { name: 'Ren', online: true }, { name: 'Odell', online: true }] },
    { id: 4, name: 'Paleto Hunters', tag: 'PLT', image: '', locked: false, inviteOnly: true, limit: 6, count: 6, online: 1, elo: 1760, blipColor: 27, tier: { name: 'Elite', color: '#08afa2' }, wins: 31, losses: 8, owner: 'Wade', members: [{ name: 'Wade', online: true }, { name: 'Buck', online: false }, { name: 'Ty', online: false }, { name: 'Lou', online: false }, { name: 'Hank', online: false }, { name: 'Mo', online: false }] },
  ],
  active: [{ squad: 'Ballas', tag: 'BLS', elo: 1420, mine: 3, theirs: 1, since: Date.now() / 1000 - 180 }],
  history: [
    { squad_a: 1, squad_b: 4, name_a: 'Southside Crew', name_b: 'Paleto Hunters', kills_a: 5, kills_b: 2, delta_a: 21, delta_b: -21, ended: Date.now() / 1000 - 3600 },
    { squad_a: 3, squad_b: 1, name_a: 'Vinewood Night Shift', name_b: 'Southside Crew', kills_a: 4, kills_b: 3, delta_a: 18, delta_b: -14, ended: Date.now() / 1000 - 9000 },
    { squad_a: 1, squad_b: 2, name_a: 'Southside Crew', name_b: 'Ballas', kills_a: 3, kills_b: 3, delta_a: 4, delta_b: -4, ended: Date.now() / 1000 - 26000 },
  ],
  get board() {
    return [
      { id: 4, name: 'Paleto Hunters', tag: 'PLT', elo: 1760, wins: 31, losses: 8, members: 6, tierInfo: { name: 'Elite', color: '#08afa2' } },
      { id: 2, name: 'Ballas', tag: 'BLS', elo: 1420, wins: 19, losses: 9, members: 5, tierInfo: { name: 'Platinum', color: '#4fd1ff' } },
      { id: 1, name: 'Southside Crew', tag: 'SSC', elo: 1285, wins: 11, losses: 5, members: 5, tierInfo: { name: 'Gold', color: '#e5a50a' } },
      { id: 3, name: 'Vinewood Night Shift', tag: 'VNS', elo: 980, wins: 4, losses: 7, members: 2, tierInfo: { name: 'Silver', color: '#9aa4ab' } },
    ];
  },
  players: [
    { name: 'Wade', kills: 88, deaths: 31, assists: 24, revives: 9, squad: 'Paleto Hunters', tag: 'PLT' },
    { name: 'Big Smoke', kills: 61, deaths: 40, assists: 19, revives: 4, squad: 'Ballas', tag: 'BLS' },
    { name: 'NayZeee', kills: 31, deaths: 14, assists: 9, revives: 6, squad: 'Southside Crew', tag: 'SSC' },
    { name: 'Tay Brooks', kills: 27, deaths: 18, assists: 12, revives: 3, squad: 'Southside Crew', tag: 'SSC' },
  ],
  adminList() {
    const s = Dev.squad || Dev.makeSquad();
    return [{
      id: s.id, name: s.name, tag: s.tag, image: s.image, elo: s.elo, tier: s.tier, wins: s.wins, losses: s.losses,
      kills: s.kills, deaths: s.deaths, persistent: true, created: s.created, count: s.members.length,
      online: s.members.filter((m) => m.online).length,
      members: s.members.map((m) => ({ identifier: m.identifier, id: m.id, name: m.name, online: m.online, rank: m.rank, rankName: m.rankName, owner: m.owner, kills: m.kills, deaths: m.deaths, assists: m.assists })),
    }, {
      id: 2, name: 'Ballas', tag: 'BLS', image: '', elo: 1420, tier: { name: 'Platinum', color: '#4fd1ff' }, wins: 19, losses: 9,
      kills: 140, deaths: 96, persistent: true, created: Date.now() / 1000 - 400000, count: 5, online: 3,
      members: [{ identifier: 'char:smoke', id: 44, name: 'Big Smoke', online: true, rank: 4, rankName: 'Leader', owner: true, kills: 61, deaths: 40, assists: 19 }],
    }];
  },
};

boot();
if (!IS_GAME) {
  document.body.style.background = 'radial-gradient(1100px 640px at 60% 20%,#1a2226 0%,#050607 70%)';
  setTimeout(() => { handlers.open({ squad: null }); refreshList(); }, 100);
  window.__dev = { handlers, state, openWheel, renderReady, Dev, applyHudStyle, renderHud };
}
})();
