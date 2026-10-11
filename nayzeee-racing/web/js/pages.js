/* ════════════════════════════════════════════════════════════════════════
   NAYZEEE v5 · racing NUI — pages
   ════════════════════════════════════════════════════════════════════════ */
'use strict';

const NAV = [
  ['home', 'fas fa-house', 'NAV_HOME'],
  ['lobbies', 'fas fa-flag-checkered', 'NAV_LOBBIES'],
  ['tracks', 'fas fa-route', 'NAV_TRACKS'],
  ['crew', 'fas fa-people-group', 'NAV_CREW'],
  ['racers', 'fas fa-ranking-star', 'NAV_RACERS'],
  ['settings', 'fas fa-sliders', 'NAV_SETTINGS'],
];

// ── navigation / data loading ───────────────────────────────────────────
async function loadLobbies() { const r = await req('lobby:list'); S.lobbies = r.data || []; render(); }
async function loadTracks() { const r = await req('track:list'); S.tracks = r.data || []; render(); }
async function loadBoard() { const r = await req('leaderboard'); S.board = r.data || { elo: [], wins: [], winRate: [] }; render(); }
async function loadMe() { const r = await req('profile:get', {}); if (r.data) { S.me = r.data; render(); } }
async function loadCrew(id) {
  const r = await req('crew:get', id ? { id } : {});
  if (id) { S.crewView = r.data || null; } else { S.crew = r.data || null; }
  render();
}
async function loadLobby(id) {
  const r = await req('lobby:get', { id });
  if (r.error) { toast(t(r.error), true); S.lobbyId = null; S.page = 'lobbies'; } else S.lobby = r.data;
  render();
}

function enterPage(page, fresh) {
  S.page = page;
  const keep = [];
  if (page === 'home' || page === 'lobbies') keep.push('lobbies');
  if (page === 'lobby' && S.lobbyId) keep.push('lobby:' + S.lobbyId);
  leaveRooms(keep);
  if (!S.profile) return;
  if (page === 'home') { joinRoom('lobbies'); loadLobbies(); loadMe(); if (!S.board) loadBoard(); }
  if (page === 'lobbies') { joinRoom('lobbies'); loadLobbies(); }
  if (page === 'lobby') { joinRoom('lobby:' + S.lobbyId); loadLobby(S.lobbyId); }
  if (page === 'tracks') loadTracks();
  if (page === 'crew') { if (S.profile.crewId) loadCrew(); else S.crew = null; }
  if (page === 'racers') { loadBoard(); if (!S.me || fresh) loadMe(); }
}
window.enterPage = enterPage;

function go(page, extra = {}) {
  Object.assign(S, extra);
  S.f = {};
  enterPage(page);
  render();
}
ACT.nav = d => go(d.v);
ACT.openLobby = d => go('lobby', { lobbyId: d.v, lobby: null });
ACT.openProfile = d => go('profile', { viewId: Number(d.v), viewProfile: null, profileTab: 'overview' });

// ── pushes ──────────────────────────────────────────────────────────────
PUSH.profile = p => {
  const hadCrew = S.profile && S.profile.crewId;
  S.profile = p;
  if (S.page === 'crew' && (p.crewId || null) !== (hadCrew || null)) enterPage('crew');
  render();
};
PUSH.inbox = () => { req('inbox:count').then(r => { S.inbox = r.data || 0; render(); if (MODAL && MODAL.inbox) loadInbox(); }); };
PUSH.active = v => { S.activeLobby = v || null; render(); };
PUSH.lobbies = d => {
  if (!S.lobbies) return;
  if (d.event === 'remove') S.lobbies = S.lobbies.filter(l => l.id !== d.id);
  else {
    const i = S.lobbies.findIndex(l => l.id === d.lobby.id);
    if (i >= 0) S.lobbies[i] = d.lobby; else S.lobbies.unshift(d.lobby);
  }
  if (S.page === 'home' || S.page === 'lobbies') render();
};
PUSH.lobby = d => {
  if (d.event === 'removed') {
    if (S.page === 'lobby') { toast(t('LOBBY_REMOVED'), true); go('lobbies'); }
    return;
  }
  const l = d.lobby;
  if (S.lobby && S.lobby.id === l.id) S.lobby = l;
  const mine = S.profile && l.participants.some(p => p.id === S.profile.id);
  if (mine && ['pending', 'mobilizing', 'countdown', 'racing'].includes(l.status)) S.activeLobby = l.id;
  else if (S.activeLobby === l.id && (!mine || l.status === 'finished' || l.status === 'cancelled')) S.activeLobby = null;
  render();
};

// ── shell ───────────────────────────────────────────────────────────────
function shell(content, opts = {}) {
  const p = S.profile;
  const r = p ? rankOf(p.elo) : null;
  const mid = p ? `<span class="dot"></span><p>${t('UI_BAR_ELO', `<b>${esc(num(p.elo))}</b>`, esc(r.rank.name))}</p>` : '';
  const act = S.activeLobby ? `<button class="btn btn-ghost sm" data-a="openLobby" data-v="${esc(S.activeLobby)}"><i class="fas fa-flag"></i>${esc(t('UI_MY_LOBBY'))}</button>` : '';
  return `<div class="stage dim"><div class="frame win"><div class="shell">
    <div class="bar">
      <div class="bar-brand"><div class="mark"></div><div class="bar-title"><b>${esc(t('APP_TITLE'))}</b><span>${esc(t('APP_SUB'))}</span></div></div>
      <div class="bar-mid">${mid}</div>
      ${act}
      ${p ? `<button class="bell" data-a="inbox" title="${esc(t('INBOX_TITLE'))}"><i class="fas fa-envelope"></i>${S.inbox ? `<b>${S.inbox > 99 ? '99+' : S.inbox}</b>` : ''}</button>` : ''}
      <span class="ver">v${esc(S.cfg ? S.cfg.version : '1.0.0')}</span>
      <button class="pill-close" data-a="close">${esc(t('UI_CLOSE'))}</button>
    </div>
    ${opts.bare ? `<div class="main">${content}</div>` : `<div class="body">${sidebar()}<div class="main">${content}</div></div>`}
    <div class="statusbar"><span><span class="key">ESC</span>${esc(t('UI_CLOSE'))}</span>${opts.status || ''}<span class="sp">${S.lobbies ? `<b>${S.lobbies.filter(l => l.status === 'pending').length}</b> ${esc(t('UI_OPEN_LOBBIES'))}` : ''}</span></div>
  </div></div></div>`;
}

function sidebar() {
  const p = S.profile;
  const { rank, next } = rankOf(p.elo);
  const pending = (S.lobbies || []).filter(l => l.status === 'pending').length;
  const navs = NAV.map(([k, icon, label]) => {
    const on = S.page === k || (k === 'lobbies' && (S.page === 'lobby' || S.page === 'create')) || (k === 'racers' && S.page === 'profile');
    const tally = k === 'lobbies' && pending ? `<span class="tally hot">${pending}</span>` : '';
    return `<button class="nav ${on ? 'on' : ''}" data-a="nav" data-v="${k}"><i class="${icon}"></i>${esc(t(label))}${tally}</button>`;
  }).join('');
  return `<div class="side">
    <div class="who" data-a="openProfile" data-v="${p.id}">${avatar(p)}<div class="who-txt"><b>${esc(p.alias)}</b><span>${p.crew ? crewTag(p.crew) + ' ' : ''}${esc(rank.name)}</span></div></div>
    <div class="rankbar"><div class="top"><span>${esc(rank.name)}</span><b>${next ? `${num(p.elo)} / ${num(next.min)}` : t('ELO_MAX')}</b></div>
      <div class="track"><div class="bar-fill" style="width:${rankProgress(p.elo)}%"></div></div></div>
    <div class="grp">${esc(t('UI_MENU'))}</div>
    ${navs}
    <div class="side-foot">
      ${btn(t('LOBBIES_CREATE'), 'createLobby', 'btn-teal', { full: true, icon: 'fas fa-plus', disabled: !!S.activeLobby })}
    </div>
  </div>`;
}

window.renderApp = () => {
  if (!S.booted) return shell(`<div class="scroll">${skeleton(6)}</div>`, { bare: true });
  if (!S.profile) return shell(pageSignup(), { bare: true });
  const pages = { home: pageHome, lobbies: pageLobbies, lobby: pageLobby, create: pageCreate, tracks: pageTracks, crew: pageCrew, racers: pageRacers, profile: pageProfile, settings: pageSettings };
  return shell((pages[S.page] || pageHome)());
};

// ════════════════════════════════════════════════════════════════════════
//  SIGN UP / EDIT PROFILE
// ════════════════════════════════════════════════════════════════════════
function avatarEditor(prefix, cfgKey, color) {
  const cfg = S.cfg[cfgKey];
  const f = S.f;
  const styles = (cfg.AllowAvatars ? cfg.AvatarTypes : []).filter(s => AVATAR_PARTS[s]);
  const modes = [];
  if (styles.length) modes.push(['avatar', t('SIGNUP_AVATAR')]);
  if (cfg.AllowCustomImages) modes.push(['image', t('SIGNUP_IMAGE')]);
  modes.push(['none', t('SIGNUP_INITIALS')]);
  if (!modes.some(m => m[0] === f.avMode)) f.avMode = modes[0][0];
  if (f.avMode === 'avatar' && !styles.includes(f.av.style)) f.av.style = styles[0];
  const url = currentAvatar(color);
  let body = '';
  if (f.avMode === 'avatar') {
    const parts = AVATAR_PARTS[f.av.style];
    const part = parts[f.avPart] ? f.avPart : Object.keys(parts)[0];
    f.avPart = part;
    body = `<div class="seg">${styles.map(s => `<button class="${f.av.style === s ? 'on' : ''}" data-a="avStyle" data-v="${s}">${esc(t('AVATAR_STYLE_' + s))}</button>`).join('')}</div>
      <div class="seg">${Object.keys(parts).map(k => `<button class="${part === k ? 'on' : ''}" data-a="avPart" data-v="${k}">${esc(t('AVATAR_PART_' + k))}</button>`).join('')}</div>
      <div class="avb-opts" data-scroll="avopts">${parts[part].map(v => {
        const u = avatarUrl({ ...f.av, color, parts: { ...f.av.parts, [part]: v } });
        return `<button class="${(f.av.parts[part] || '') === v ? 'on' : ''}" data-a="avPick" data-v="${v}" title="${esc(v)}"><img src="${esc(u)}" loading="lazy"></button>`;
      }).join('')}</div>`;
  } else if (f.avMode === 'image') {
    body = `<div class="field"><label>${esc(t('SIGNUP_IMAGE_URL'))}</label><input id="${prefix}-img" data-m="f.image" data-r value="${esc(f.image || '')}" placeholder="https://"></div>
      <div class="hint">${esc(cfg.AllowAllDomains ? t('SIGNUP_IMAGE_ANY') : t('SIGNUP_IMAGE_DOMAINS', cfg.AllowedDomains.join(', ')))}</div>`;
  } else body = `<div class="hint">${esc(t('SIGNUP_INITIALS_HINT'))}</div>`;
  return `<div class="avb">
    <div class="avb-prev">${avatar({ avatar: url, alias: f.alias || f.name || '?', color }, 'xl')}
      ${f.avMode === 'avatar' ? btn(t('AVATAR_RANDOM'), 'avRandom', 'btn-ghost', { size: 'sm', icon: 'fas fa-shuffle', free: true }) : ''}</div>
    <div style="display:flex;flex-direction:column;gap:9px;min-width:0">
      ${modes.length > 1 ? `<div class="seg">${modes.map(([k, l]) => `<button class="${f.avMode === k ? 'on' : ''}" data-a="avMode" data-v="${k}">${esc(l)}</button>`).join('')}</div>` : ''}
      ${body}
    </div></div>`;
}
function currentAvatar(color) {
  const f = S.f;
  if (f.avMode === 'avatar') return avatarUrl({ ...f.av, color });
  if (f.avMode === 'image') return (f.image || '').trim();
  return '';
}
function initAvatarForm(existing, color) {
  const parsed = parseAvatar(existing);
  S.f.av = parsed || { style: null, seed: randSeed(), parts: {} };
  S.f.avMode = parsed ? 'avatar' : existing ? 'image' : 'avatar';
  if (!parsed && existing) S.f.image = existing;
  S.f.color = color;
}
const rr = () => (MODAL ? renderModal() : render());
ACT.avStyle = d => { S.f.av.style = d.v; S.f.av.parts = {}; S.f.avPart = null; rr(); };
ACT.avPart = d => { S.f.avPart = d.v; rr(); };
ACT.avPick = d => { S.f.av.parts[S.f.avPart] = d.v; rr(); };
ACT.avMode = d => { S.f.avMode = d.v; rr(); };
ACT.avRandom = () => {
  S.f.av.seed = randSeed();
  const parts = AVATAR_PARTS[S.f.av.style] || {};
  S.f.av.parts = {};
  for (const [k, list] of Object.entries(parts)) S.f.av.parts[k] = list[Math.floor(Math.random() * list.length)];
  rr();
};
ACT.color = d => { S.f.color = d.v; rr(); };
function swatches(sel) {
  return `<div class="swatches">${S.cfg.Profiles.Colors.map(c => `<button class="swatch ${sel === c ? 'on' : ''}" style="background:${esc(c)}" data-a="color" data-v="${esc(c)}"></button>`).join('')}</div>`;
}
function aliasState() {
  const f = S.f, min = S.cfg.Profiles.AliasMin;
  if (!f.alias) return '';
  if (f.alias.trim().length < min) return `<em class="bad">${esc(t('SIGNUP_ALIAS_MIN', min))}</em>`;
  if (f.aliasOk === 'wait') return `<em>${esc(t('SIGNUP_CHECKING'))}</em>`;
  if (f.aliasOk === true) return `<em class="ok">${esc(t('SIGNUP_AVAILABLE'))}</em>`;
  if (f.aliasOk === false) return `<em class="bad">${esc(t('SIGNUP_TAKEN'))}</em>`;
  return '';
}
ACT.aliasCheck = () => {
  const f = S.f;
  f.aliasOk = 'wait';
  debounce('alias', 350, async () => {
    const r = await req('profile:aliasAvailable', { alias: f.alias });
    if (S.f === f) { f.aliasOk = r.data === true; rr(); }
  });
};

function pageSignup() {
  const f = S.f;
  if (!f.av) { initAvatarForm('', S.cfg.Profiles.Colors[0]); f.alias = ''; }
  const start = rankOf(S.cfg.Profiles.StartingElo || 0).rank;
  const ok = f.alias && f.alias.trim().length >= S.cfg.Profiles.AliasMin && f.aliasOk === true;
  return `<div class="scroll" style="align-items:center;justify-content:center">
    <div class="panel" style="width:640px;flex:none">
      <div class="p-head"><div><h2><i class="fas fa-id-card"></i>${esc(t('SIGNUP_TITLE'))}</h2><p>${esc(t('SIGNUP_SUB'))}</p></div>
        <span class="chip">${esc(t('SIGNUP_START_RANK', start.name, num(S.cfg.Profiles.StartingElo)))}</span></div>
      <div class="p-pad">
        <div class="field"><label>${esc(t('SIGNUP_ALIAS'))}${aliasState()}</label>
          <input id="su-alias" maxlength="${S.cfg.Profiles.AliasMax}" data-m="f.alias" data-on="aliasCheck" data-r value="${esc(f.alias)}" placeholder="${esc(t('SIGNUP_ALIAS_PH'))}"></div>
        <div class="field"><label>${esc(t('SIGNUP_COLOR'))}</label>${swatches(f.color)}</div>
        ${avatarEditor('su', 'Profiles', f.color)}
        ${btn(t('SIGNUP_BUTTON'), 'signup', 'btn-teal', { size: 'lg', full: true, icon: 'fas fa-flag-checkered', busyKey: 'profile:create', disabled: !ok })}
      </div>
    </div></div>`;
}
ACT.signup = async () => {
  const f = S.f;
  const p = await call('profile:create', { alias: f.alias.trim(), color: f.color, avatar: currentAvatar(f.color) });
  if (!p) return;
  S.profile = p;
  S.f = {};
  toast(t('SIGNUP_DONE', p.alias));
  go('home');
};

function editProfileModal() {
  const p = S.profile;
  S.f = { alias: p.alias, aliasOk: true };
  initAvatarForm(p.avatar, p.color);
  openModal({
    render: () => {
      const f = S.f;
      const ok = f.alias && f.alias.trim().length >= S.cfg.Profiles.AliasMin && (f.aliasOk === true || f.alias === p.alias);
      return `<div class="modal wide"><div class="modal-h"><div class="grow"><h4>${esc(t('PROFILE_EDIT'))}</h4><p>${esc(t('PROFILE_EDIT_SUB'))}</p></div></div>
        <div class="modal-body">
          <div class="field"><label>${esc(t('SIGNUP_ALIAS'))}${f.alias !== p.alias ? aliasState() : ''}</label>
            <input id="ep-alias" maxlength="${S.cfg.Profiles.AliasMax}" data-m="f.alias" data-on="aliasCheck" data-r value="${esc(f.alias)}"></div>
          <div class="field"><label>${esc(t('SIGNUP_COLOR'))}</label>${swatches(f.color)}</div>
          ${avatarEditor('ep', 'Profiles', f.color)}
        </div>
        <div class="modal-f">${btn(t('UI_CANCEL'), 'modalNo', 'btn-line', { free: true })}${btn(t('UI_SAVE'), 'saveProfile', 'btn-teal', { icon: 'fas fa-check', busyKey: 'profile:update', disabled: !ok })}</div></div>`;
    },
    on: {
      modalNo: () => closeModal(),
      saveProfile: async () => {
        const f = S.f;
        const r = await call('profile:update', { alias: f.alias.trim(), color: f.color, avatar: currentAvatar(f.color) }, { success: t('PROFILE_SAVED') });
        if (r) { S.profile = r; closeModal(); S.viewProfile = null; enterPage(S.page); render(); }
      },
    },
  });
}
ACT.editProfile = editProfileModal;

// ════════════════════════════════════════════════════════════════════════
//  HOME
// ════════════════════════════════════════════════════════════════════════
function lobbyRow(l) {
  const me = S.profile && l.participants.some(p => p.id === S.profile.id);
  const count = l.participants.length;
  return `<div class="row click ${l.featured ? 'feat' : ''} ${me ? 'on' : ''}" data-a="openLobby" data-v="${esc(l.id)}">
    <div class="tile ${l.type === 'ranked' ? 'amber' : l.type === 'crew' ? '' : 'mute'}"><i class="${typeIcon(l.type)}"></i></div>
    <div class="row-txt"><b>${l.featured ? '<i class="fas fa-star" style="color:var(--amber);font-size:10px"></i>' : ''}${l.star ? '<i class="fas fa-crown" style="color:var(--gold);font-size:10px"></i>' : ''}${esc(l.name)}${l.hasPassword ? ' <i class="fas fa-lock" style="font-size:9px;color:var(--ink-3)"></i>' : ''}</b>
      <span>${esc(l.track.name)} · ${esc(t('MODE_' + l.mode))} · ${l.laps > 0 ? esc(t('UI_N_LAPS', l.laps)) : esc(t('TRACK_sprint'))} · ${esc(l.class === 'Open' ? t('CLASS_OPEN') : t('UI_CLASS', l.class))}</span></div>
    <div class="row-r">${l.wager ? `<span class="chip amber"><i class="fas fa-coins"></i>${esc(money(l.wager, l.currency))}</span>` : ''}
      <span class="chip mute"><i class="fas fa-user"></i>${count}/${l.max}</span>${statusTag(l.status)}</div>
  </div>`;
}

function pageHome() {
  const p = S.profile;
  const st = S.me && S.me.stats;
  const { rank, next } = rankOf(p.elo);
  const lobbies = (S.lobbies || []).filter(l => l.status !== 'cancelled').slice(0, 7);
  const board = S.board ? S.board.elo.slice(0, 6) : null;
  return `<div class="head"><div><h1>${esc(t('HOME_WELCOME', p.alias))}</h1><p>${esc(t('HOME_SUB'))}</p></div>
      <div class="head-r">${btn(t('UI_EDIT_PROFILE'), 'editProfile', 'btn-ghost', { icon: 'fas fa-pen', size: 'sm' })}</div></div>
    <div class="hero" style="--c:${esc(p.color)}">
      ${avatar(p, 'lg')}
      <div class="grow"><h3>${esc(rank.name)} ${p.crew ? crewTag(p.crew) : ''}</h3>
        <p>${next ? esc(t('HOME_NEXT_RANK', num(next.min - p.elo), next.name)) : esc(t('HOME_MAX_RANK'))}${next && next.rewards ? ` · <span class="chip"><i class="fas fa-gift"></i>${esc(t('ELO_REWARDS'))}</span>` : ''}</p>
        <div class="track" style="margin-top:10px;max-width:420px"><div class="bar-fill" style="width:${rankProgress(p.elo)}%"></div></div></div>
      <div class="hero-r"><b>${num(p.elo)}</b><span>${esc(t('UI_ELO'))}</span></div>
    </div>
    <div class="stats">
      ${stat(t('STAT_RACES'), st ? num(st.races) : '—', 'fas fa-flag-checkered')}
      ${stat(t('STAT_WINS'), st ? num(st.wins) : '—', 'fas fa-trophy', 'amber')}
      ${stat(t('STAT_WIN_RATE'), st ? num(st.winRate, 1) : '—', 'fas fa-percent', '', st ? '%' : '')}
      ${stat(t('STAT_STREAK'), st ? (st.streak > 0 ? '+' + st.streak : st.streak) : '—', 'fas fa-fire', st && st.streak < 0 ? 'red' : '')}
    </div>
    <div class="cols c21 fill-y">
      <div class="panel"><div class="p-head"><div><h2><i class="fas fa-flag-checkered"></i>${esc(t('HOME_LOBBIES'))}</h2><p>${esc(t('HOME_LOBBIES_SUB'))}</p></div>
        ${btn(t('HOME_VIEW_ALL'), 'nav', 'btn-ghost', { size: 'sm', data: { v: 'lobbies' }, free: true })}</div>
        <div class="p-body" data-scroll="hl">${!S.lobbies ? skeleton(4) : lobbies.length ? lobbies.map(lobbyRow).join('') :
          empty('fas fa-flag', t('HOME_NO_LOBBIES'), t('HOME_NO_LOBBIES_SUB'), `<div style="margin-top:6px">${btn(t('LOBBIES_CREATE'), 'createLobby', 'btn-teal', { size: 'sm', icon: 'fas fa-plus', disabled: !!S.activeLobby })}</div>`)}</div></div>
      <div class="panel"><div class="p-head"><div><h2><i class="fas fa-ranking-star"></i>${esc(t('BOARD_ELO'))}</h2><p>${esc(t('BOARD_ELO_SUB'))}</p></div></div>
        <div class="p-body" data-scroll="hb">${!board ? skeleton(5) : board.length ? board.map((r, i) => boardRow(r, i + 1, 'elo')).join('') : empty('fas fa-ranking-star', t('BOARD_EMPTY'))}</div></div>
    </div>`;
}

function boardRow(r, pos, kind) {
  const val = kind === 'wins' ? `${num(r.wins)} <small style="color:var(--ink-3);font-weight:300">${esc(t('STAT_WINS'))}</small>`
    : kind === 'winRate' ? `${num(r.winRate, 1)}%` : num(r.elo);
  const me = S.profile && r.id === S.profile.id;
  return `<div class="row click ${me ? 'on' : ''}" data-a="openProfile" data-v="${r.id}">${posBadge(pos)}${avatar(r, 'sm')}
    <div class="row-txt"><b>${esc(r.alias)} ${crewTag(r.crew)}</b><span>${esc(rankOf(r.elo).rank.name)} · ${esc(t('UI_N_RACES', num(r.races)))}</span></div>
    <div class="row-r"><b style="font-size:12.5px;color:var(--white);font-weight:600">${val}</b></div></div>`;
}

// ════════════════════════════════════════════════════════════════════════
//  LOBBIES
// ════════════════════════════════════════════════════════════════════════
function lobbyFilters() {
  S.lf = S.lf || { q: '', status: 'all', mode: 'all', track: 'all', size: 'all' };
  return S.lf;
}
function pageLobbies() {
  const f = lobbyFilters();
  const all = (S.lobbies || []).filter(l => l.status !== 'cancelled');
  const q = f.q.trim().toLowerCase();
  const sizes = { s1: [1, 2], s2: [3, 4], s3: [5, 8], s4: [9, 12], s5: [13, 999] };
  const list = all.filter(l => {
    if (f.status !== 'all' && (f.status === 'active' ? !['mobilizing', 'countdown', 'racing'].includes(l.status) : l.status !== f.status)) return false;
    if (f.mode !== 'all' && (f.mode === 'crew' ? l.type !== 'crew' : l.mode !== f.mode)) return false;
    if (f.track !== 'all' && (l.laps > 0 ? 'circuit' : 'sprint') !== f.track) return false;
    if (f.size !== 'all') { const [a, b] = sizes[f.size]; if (l.max < a || l.max > b) return false; }
    if (!q) return true;
    return [l.name, l.owner.alias, l.track.name].some(s => String(s).toLowerCase().includes(q));
  });
  const seg = (key, opts) => `<div class="seg">${opts.map(([v, l]) => `<button class="${f[key] === v ? 'on' : ''}" data-a="lf" data-k="${key}" data-v="${v}">${esc(l)}</button>`).join('')}</div>`;
  return `<div class="head"><div><h1>${esc(t('LOBBIES_TITLE'))}</h1><p>${esc(t('LOBBIES_SUB'))}</p></div>
      <div class="head-r"><div class="search" style="width:260px"><i class="fas fa-magnifying-glass"></i><input class="input" id="lb-q" data-m="lf.q" data-r value="${esc(f.q)}" placeholder="${esc(t('LOBBIES_SEARCH'))}"></div>
      ${btn(t('LOBBIES_CREATE'), 'createLobby', 'btn-teal', { icon: 'fas fa-plus', disabled: !!S.activeLobby })}</div></div>
    <div style="display:flex;gap:8px;flex-wrap:wrap;flex:none">
      ${seg('status', [['all', t('F_ALL')], ['pending', t('LOBBY_STATUS_pending')], ['active', t('F_ACTIVE')], ['finished', t('LOBBY_STATUS_finished')]])}
      ${seg('mode', [['all', t('F_ALL')], ['standard', t('MODE_standard')], ['drift', t('MODE_drift')], ['time_trial', t('MODE_time_trial')], ['crew', t('TYPE_crew')]])}
      ${seg('track', [['all', t('F_ALL')], ['circuit', t('TRACK_circuit')], ['sprint', t('TRACK_sprint')]])}
      <div class="field" style="width:150px"><select data-m="lf.size" data-r><option value="all">${esc(t('F_ANY_SIZE'))}</option>
        ${Object.keys(sizes).map(k => `<option value="${k}" ${f.size === k ? 'selected' : ''}>${esc(t('F_SIZE_' + k))}</option>`).join('')}</select></div>
      ${f.q || f.status !== 'all' || f.mode !== 'all' || f.track !== 'all' || f.size !== 'all' ? btn(t('F_CLEAR'), 'lfClear', 'btn-line', { size: 'sm', icon: 'fas fa-xmark', free: true }) : ''}
    </div>
    <div class="panel fill-y"><div class="p-head"><div><h2>${esc(t('LOBBIES_SHOWING', list.length, all.length))}</h2></div></div>
      <div class="p-body" data-scroll="ll">${!S.lobbies ? skeleton(6) : list.length ? list.map(lobbyRow).join('') :
        empty('fas fa-flag', t('LOBBIES_NONE'), all.length ? t('LOBBIES_ADJUST') : t('LOBBIES_FIRST'))}</div></div>`;
}
ACT.lf = d => { lobbyFilters()[d.k] = d.v; render(); };
ACT.lfClear = () => { S.lf = null; render(); };

// ── vehicle picker ──────────────────────────────────────────────────────
function pickVehicle(cls) {
  return new Promise(async resolve => {
    const st = { list: null, sel: null, q: '' };
    const m = {
      resolve,
      render: () => {
        const q = st.q.trim().toLowerCase();
        const list = (st.list || []).filter(v => !q || [v.label, v.name, v.plate, v.brand].some(s => s && String(s).toLowerCase().includes(q)));
        const cards = !st.list ? skeleton(3) : list.length ? `<div class="vgrid">${list.map(v => {
          const fits = !cls || cls === 'Open' || v.class === 'All' || v.class === cls;
          return `<button class="vcard ${st.sel === v.plate ? 'on' : ''}" data-a="vPick" data-v="${esc(v.plate)}" ${fits ? '' : 'disabled'}>
            <div class="vimg">${vImage(v)}</div>
            <div class="corner">${v.seated ? `<span class="chip"><i class="fas fa-location-dot"></i>${esc(t('PICK_SEATED'))}</span>` : !fits ? `<span class="chip red">${esc(t('PICK_WRONG_CLASS'))}</span>` : ''}</div>
            <div class="vcard-b"><b>${esc(v.label)}</b><span><span class="plate">${esc(v.plate)}</span>${v.class !== 'All' ? esc(t('UI_CLASS', v.class)) : ''}</span></div></button>`;
        }).join('')}</div>` : empty('fas fa-car-side', t('PICK_NONE'), t('PICK_NONE_SUB'));
        return `<div class="modal xwide"><div class="modal-h"><div class="grow"><h4>${esc(t('PICK_TITLE'))}</h4><p>${esc(t('PICK_SUB'))}</p></div>
          <div class="search" style="max-width:220px"><i class="fas fa-magnifying-glass"></i><input class="input" id="vp-q" placeholder="${esc(t('UI_SEARCH'))}" value="${esc(st.q)}" oninput="window.__vpq(this.value)"></div></div>
          <div class="modal-body" data-scroll="vp" style="max-height:470px">${cards}</div>
          <div class="modal-f">${btn(t('UI_CANCEL'), 'modalNo', 'btn-line', { free: true })}${btn(t('PICK_CONFIRM'), 'vOk', 'btn-teal', { icon: 'fas fa-check', disabled: !st.sel, free: true })}</div></div>`;
      },
      on: {
        modalNo: () => closeModal(null),
        vPick: d => { st.sel = d.v; renderModal(); },
        vOk: () => closeModal(st.list.find(v => v.plate === st.sel)),
      },
    };
    window.__vpq = v => { st.q = v; renderModal(); };
    openModal(m);
    st.list = (await post('vehicles')) || [];
    const seated = st.list.find(v => v.seated);
    if (seated) st.sel = seated.plate;
    if (MODAL === m) renderModal();
  });
}

// ── create lobby ────────────────────────────────────────────────────────
ACT.createLobby = d => {
  if (S.activeLobby) return toast(t('LOBBY_ALREADY_IN'), true);
  go('create');
  S.f = { name: '', trackId: d && d.track ? Number(d.track) : null, type: 'unranked', mode: 'standard', class: 'Open', laps: 1, max: 8,
    wager: '', currency: (S.cfg.Races.WagerCurrencies || [])[0], ghost: true, password: '', featured: false, vehicle: null, tq: '', balance: null };
  if (!S.tracks) loadTracks();
  render();
  refreshBalance();
};
async function refreshBalance() {
  if (!S.cfg.Races.WagerCurrencies.length) return;
  const r = await req('balance', { currency: S.f.currency });
  if (S.page === 'create') { S.f.balance = r.data || 0; render(); }
}

function pageCreate() {
  const f = S.f, R = S.cfg.Races;
  const tracks = S.tracks || [];
  const track = tracks.find(x => x.id === f.trackId);
  const circuit = track && track.type === 'circuit';
  const q = (f.tq || '').trim().toLowerCase();
  const tlist = tracks.filter(x => !q || x.name.toLowerCase().includes(q) || (x.owner.alias || '').toLowerCase().includes(q)).slice(0, 30);
  const p = S.profile;
  const canCrew = p.crew && (p.crew.owner === p.id || (p.crewPerms || []).includes(3));
  const minR = f.type === 'ranked' ? R.RequiredParticipantsForRankedLobby : f.type === 'crew' ? R.MinCrewSize * 2 : 1;
  if (f.max < minR) f.max = minR;
  const need = f.type === 'ranked' ? (S.cfg.ELO.ClassRestrictions[f.class] || 0) : 0;
  const eloOk = p.elo >= need;
  const wager = Number(f.wager) || 0;
  const broke = wager > 0 && f.balance != null && wager > f.balance;
  const classFits = !f.vehicle || f.class === 'Open' || f.vehicle.class === 'All' || f.vehicle.class === f.class;
  const ready = track && f.vehicle && eloOk && !broke && classFits && (f.type !== 'crew' || canCrew);

  const typeCard = (k, icon, desc, dis) => `<button class="ccard ${f.type === k ? 'on' : ''}" data-a="cf" data-k="type" data-v="${k}" ${dis ? 'disabled' : ''}><i class="${icon}"></i><b>${esc(t('TYPE_' + k))}</b><span>${esc(desc)}</span></button>`;
  const modeOpt = k => `<button class="opt ${f.mode === k ? 'on' : ''}" data-a="cf" data-k="mode" data-v="${k}"><i class="${modeIcon(k)}"></i>${esc(t('MODE_' + k))}</button>`;
  const classes = ['Open', ...S.cfg.Classes];
  return `<div class="head"><div><button class="back" data-a="nav" data-v="lobbies"><i class="fas fa-arrow-left"></i>${esc(t('UI_BACK'))}</button><h1>${esc(t('CREATE_TITLE'))}</h1><p>${esc(t('CREATE_SUB'))}</p></div></div>
    <div class="cols c12 fill-y">
      <div class="panel"><div class="p-head"><div><h2><i class="fas fa-route"></i>${esc(t('CREATE_TRACK'))}</h2><p>${esc(t('CREATE_TRACK_SUB'))}</p></div></div>
        <div style="padding:10px 10px 0"><div class="search"><i class="fas fa-magnifying-glass"></i><input class="input" id="cr-tq" data-m="f.tq" data-r value="${esc(f.tq)}" placeholder="${esc(t('CREATE_TRACK_PH'))}"></div></div>
        <div class="p-body" data-scroll="ct">${!S.tracks ? skeleton(5) : tlist.length ? tlist.map(x => `<div class="row click ${x.id === f.trackId ? 'on' : ''}" data-a="cfTrack" data-v="${x.id}">
            <div class="tile ${x.type === 'circuit' ? '' : 'mute'}"><i class="fas ${x.type === 'circuit' ? 'fa-rotate' : 'fa-arrow-right-long'}"></i></div>
            <div class="row-txt"><b>${esc(x.name)}${x.private ? ' <i class="fas fa-lock" style="font-size:9px;color:var(--ink-3)"></i>' : ''}</b><span>${esc(t('TRACK_' + x.type))} · ${esc(dist(x.length))} · ${esc(t('UI_N_CPS', x.checkpoints))}</span></div></div>`).join('')
          : empty('fas fa-route', t('CREATE_NO_TRACKS', f.tq || ''))}</div></div>
      <div class="panel"><div class="p-head"><div><h2><i class="fas fa-sliders"></i>${esc(t('CREATE_SETTINGS'))}</h2><p>${track ? esc(track.name) : esc(t('CREATE_PICK_TRACK'))}</p></div></div>
        <div class="p-body" data-scroll="cs" style="gap:13px;padding:14px">
          <div class="grid2">
            <div class="field"><label>${esc(t('CREATE_NAME'))}</label><input id="cr-name" maxlength="40" data-m="f.name" value="${esc(f.name)}" placeholder="${esc(track ? track.name : t('CREATE_NAME_PH'))}"></div>
            <div class="field"><label>${esc(t('CREATE_PASSWORD'))}<em>${esc(t('UI_OPTIONAL'))}</em></label><input id="cr-pw" maxlength="20" data-m="f.password" value="${esc(f.password)}" placeholder="${esc(t('CREATE_PASSWORD_PH'))}"></div>
          </div>
          <div class="field"><label>${esc(t('CREATE_TYPE'))}</label><div class="cards">
            ${typeCard('unranked', 'fas fa-road', t('CREATE_UNRANKED_DESC'))}
            ${typeCard('ranked', 'fas fa-trophy', t('CREATE_RANKED_DESC', R.RequiredParticipantsForRankedLobby))}
            ${typeCard('crew', 'fas fa-people-group', canCrew ? t('CREATE_CREW_DESC') : t('CREATE_CREW_LOCKED'), !canCrew)}</div></div>
          <div class="field"><label>${esc(t('CREATE_MODE'))}</label><div class="opts">${modeOpt('standard')}${modeOpt('drift')}${modeOpt('time_trial')}</div></div>
          <div class="grid2">
            <div class="field"><label>${esc(t('CREATE_CLASS'))}${need ? `<em class="${eloOk ? 'ok' : 'bad'}">${esc(t('CREATE_CLASS_ELO', num(need)))}</em>` : ''}</label>
              <select data-m="f.class" data-r>${classes.map(c => `<option value="${esc(c)}" ${f.class === c ? 'selected' : ''}>${esc(c === 'Open' ? t('CLASS_OPEN') : c)}</option>`).join('')}</select></div>
            <div class="field"><label>${esc(t('CREATE_RACERS'))}<em>${esc(t('CREATE_RACERS_HINT', minR, R.MaxParticipants))}</em></label>
              <div class="range"><input type="range" min="${minR}" max="${R.MaxParticipants}" value="${f.max}" data-m="f.max" data-t="num" data-r><b>${f.max}</b></div></div>
          </div>
          ${circuit ? `<div class="field"><label>${esc(t('CREATE_LAPS'))}<em>${f.laps == 0 ? esc(t('CREATE_LAPS_SPRINT')) : ''}</em></label>
            <div class="range"><input type="range" min="0" max="${R.MaxLaps}" value="${f.laps}" data-m="f.laps" data-t="num" data-r><b>${f.laps}</b></div></div>` : ''}
          ${R.WagerCurrencies.length ? `<div class="grid2">
            <div class="field"><label>${esc(t('CREATE_WAGER'))}${f.balance != null ? `<em class="${broke ? 'bad' : ''}">${esc(t('CREATE_BALANCE', money(f.balance, f.currency)))}</em>` : ''}</label>
              <input id="cr-wager" type="number" min="0" max="${R.MaxWager}" data-m="f.wager" data-t="num" data-r value="${esc(f.wager)}" placeholder="0"></div>
            ${R.WagerCurrencies.length > 1 ? `<div class="field"><label>${esc(t('CREATE_CURRENCY'))}</label><select data-m="f.currency" data-on="currency" data-r>${R.WagerCurrencies.map(c => `<option value="${c}" ${f.currency === c ? 'selected' : ''}>${esc((S.cfg.Rewards.Currencies[c] || {}).label || c)}</option>`).join('')}</select></div>`
              : `<div class="hint" style="align-self:end;padding-bottom:8px">${esc(t('CREATE_WAGER_DESC'))}</div>`}</div>` : ''}
          <button class="sw-line" data-a="cfToggle" data-k="ghost"><div><b>${esc(t('CREATE_GHOST'))}</b><span>${esc(t('CREATE_GHOST_DESC'))}</span></div><span class="sw ${f.ghost ? 'on' : ''}"><i></i></span></button>
          ${S.canEvents ? `<button class="sw-line" data-a="cfToggle" data-k="featured"><div><b>${esc(t('CREATE_FEATURED'))}</b><span>${esc(t('CREATE_FEATURED_DESC'))}</span></div><span class="sw ${f.featured ? 'on' : ''}"><i></i></span></button>` : ''}
          <div class="field"><label>${esc(t('CREATE_VEHICLE'))}${f.vehicle && !classFits ? `<em class="bad">${esc(t('PICK_WRONG_CLASS'))}</em>` : ''}</label>
            <button class="pick-v ${f.vehicle ? 'set' : ''}" data-a="cfVehicle"><div class="vimg">${f.vehicle ? vImage(f.vehicle) : '<i class="fas fa-plus"></i>'}</div>
              <div class="row-txt"><b>${esc(f.vehicle ? f.vehicle.label : t('CREATE_PICK_VEHICLE'))}</b><span>${f.vehicle ? `<span class="plate">${esc(f.vehicle.plate)}</span>` : esc(t('CREATE_PICK_VEHICLE_SUB'))}</span></div></button></div>
        </div>
        <div class="modal-f">${btn(t('UI_CANCEL'), 'nav', 'btn-line', { data: { v: 'lobbies' } })}${btn(t('CREATE_BUTTON'), 'cfCreate', 'btn-teal', { icon: 'fas fa-flag-checkered', busyKey: 'lobby:create', disabled: !ready })}</div>
      </div></div>`;
}
ACT.cf = d => { S.f[d.k] = d.v; render(); };
ACT.cfToggle = d => { S.f[d.k] = !S.f[d.k]; render(); };
ACT.cfTrack = d => { S.f.trackId = Number(d.v); render(); };
ACT.currency = () => refreshBalance();
ACT.cfVehicle = async () => { const v = await pickVehicle(S.f.class); if (v) { S.f.vehicle = v; render(); } };
ACT.cfCreate = async () => {
  const f = S.f;
  const l = await call('lobby:create', {
    trackId: f.trackId, name: f.name, type: f.type, mode: f.mode, class: f.class, laps: f.laps, max: f.max,
    wager: Number(f.wager) || 0, currency: f.currency, ghost: f.ghost, password: f.password, featured: f.featured, vehicle: f.vehicle,
  });
  if (!l) return;
  S.activeLobby = l.id;
  toast(t('CREATE_DONE'));
  go('lobby', { lobbyId: l.id, lobby: l });
};

// ── lobby detail ────────────────────────────────────────────────────────
function partRow(l, part, owner) {
  const me = part.id === S.profile.id;
  const statusMap = { queuing: ['warn', 'P_QUEUING'], accepted: ['live', 'P_ACCEPTED'], mobilizing: ['warn', 'P_RACING'], countdown: ['warn', 'P_RACING'], racing: ['hot', 'P_RACING'], finished: ['off', 'P_FINISHED'], disqualified: ['hot', 'P_DNF'] };
  const [tone, key] = statusMap[part.status] || ['off', part.status];
  let actions = '';
  if (owner && l.status === 'pending' && !part.owner) {
    actions = part.status === 'queuing'
      ? `<button class="icon-btn" data-a="lm" data-k="accept" data-v="${part.id}" title="${esc(t('LOBBY_ACCEPT'))}"><i class="fas fa-check"></i></button><button class="icon-btn danger" data-a="lm" data-k="decline" data-v="${part.id}" title="${esc(t('LOBBY_DECLINE'))}"><i class="fas fa-xmark"></i></button>`
      : `<button class="icon-btn danger" data-a="lm" data-k="kick" data-v="${part.id}" title="${esc(t('LOBBY_KICK'))}"><i class="fas fa-user-xmark"></i></button>`;
  }
  return `<div class="row ${me ? 'on' : ''}">${avatar(part, '', { online: true })}
    <div class="row-txt"><b>${esc(part.alias)} ${crewTag(part.crew)} ${part.owner ? `<i class="fas fa-crown" style="color:var(--amber);font-size:10px" title="${esc(t('LOBBY_HOST'))}"></i>` : ''}</b>
      <span>${part.vehicle ? esc(part.vehicle.label) + ' · ' : ''}${num(part.elo)} ${esc(t('UI_ELO'))}</span></div>
    <div class="row-r"><span class="tag ${tone}">${esc(t(key))}</span>${actions}</div></div>`;
}

function resultsTable(res, me) {
  if (!res) return '';
  const drift = res.mode === 'drift';
  const crews = res.crews ? `<div class="res-crews" style="padding:4px 0 10px">
      <div class="${res.crews.winner === (res.crews[0].crew || {}).id ? 'w' : ''}"><b>${res.crews[0].score}</b>${crewTag(res.crews[0].crew)}</div><span style="color:var(--ink-3)">vs</span>
      <div class="${res.crews.winner === (res.crews[1].crew || {}).id ? 'w' : ''}"><b>${res.crews[1].score}</b>${crewTag(res.crews[1].crew)}</div></div>` : '';
  return `${crews}<table><thead><tr><th>#</th><th>${esc(t('UI_RACER'))}</th><th>${esc(t('UI_VEHICLE'))}</th><th class="r">${esc(drift ? t('RES_SCORE') : res.mode === 'time_trial' ? t('RES_BEST_LAP') : t('RES_TIME'))}</th><th class="r">${esc(t('UI_ELO'))}</th></tr></thead><tbody>
    ${res.list.map(r => `<tr class="${r.id === me ? 'me' : ''}"><td>${posBadge(r.position, r.status)}</td><td><b>${esc(r.alias)}</b> ${crewTag(r.crew)}</td><td>${esc(r.vehicle || '—')}</td>
      <td class="r"><b>${r.status !== 'finished' ? esc(t('P_DNF')) : drift ? num(r.score) : esc(clock(res.mode === 'time_trial' ? r.score : r.time))}</b>${r.payout ? ` <span class="chip amber">${esc(money(r.payout))}</span>` : ''}</td>
      <td class="r">${eloDelta(r.eloDelta) || '—'}</td></tr>`).join('')}</tbody></table>`;
}

function pageLobby() {
  const l = S.lobby;
  if (!l) return `<div class="scroll">${skeleton(6)}</div>`;
  const p = S.profile;
  const mine = l.participants.find(x => x.id === p.id);
  const owner = l.owner.id === p.id;
  const accepted = l.participants.filter(x => x.status === 'accepted').length;
  const tr = l.track;
  const wr = tr.worldRecord;
  let actions = '';
  if (l.status === 'pending') {
    if (owner) actions = `${btn(t('LOBBY_DISBAND'), 'lDisband', 'btn-red', { icon: 'fas fa-trash' })}${btn(t('LOBBY_START'), 'lStart', 'btn-teal', { icon: 'fas fa-play', busyKey: 'lobby:start' })}`;
    else if (mine) actions = btn(t('LOBBY_LEAVE'), 'lLeave', 'btn-red', { icon: 'fas fa-right-from-bracket' });
    else if (l.participants.length >= l.max) actions = btn(t('LOBBY_FULL'), 'noop', 'btn-line', { disabled: true });
    else if (S.activeLobby) actions = btn(t('LOBBY_IN_OTHER'), 'noop', 'btn-line', { disabled: true });
    else actions = btn(t('LOBBY_JOIN'), 'lJoin', 'btn-teal', { icon: 'fas fa-right-to-bracket', busyKey: 'lobby:join' });
  } else if (mine && ['mobilizing', 'countdown', 'racing'].includes(l.status) && ['mobilizing', 'countdown', 'racing'].includes(mine.status)) {
    actions = btn(t('LOBBY_DNF'), 'lLeave', 'btn-red', { icon: 'fas fa-flag' });
  }
  let parts;
  if (l.type === 'crew') {
    const groups = {};
    l.participants.forEach(x => { const k = x.crewId || 0; (groups[k] = groups[k] || []).push(x); });
    const crews = l.crews.length ? l.crews : [];
    parts = crews.map(c => `<div class="grp" style="margin:4px 2px">${crewTag(c)} ${esc(c.name)}</div>${(groups[c.id] || []).map(x => partRow(l, x, owner)).join('')}`).join('')
      + (crews.length < 2 ? `<div class="empty" style="padding:16px"><i class="fas fa-people-group"></i><span>${esc(t('LOBBY_WAITING_CREW'))}</span></div>` : '');
  } else parts = l.participants.map(x => partRow(l, x, owner)).join('');
  return `<div class="head"><div><button class="back" data-a="nav" data-v="lobbies"><i class="fas fa-arrow-left"></i>${esc(t('UI_BACK'))}</button>
      <h1>${l.featured ? '<i class="fas fa-star" style="color:var(--amber);font-size:16px"></i>' : ''}${esc(l.name)} ${statusTag(l.status)}${l.star ? `<span class="chip amber"><i class="fas fa-crown"></i>${esc(t('LOBBY_STARRED'))}</span>` : ''}</h1>
      <p>${esc(t('LOBBY_HOSTED', l.owner.alias))} · ${esc(t('TYPE_' + l.type))} · ${esc(t('MODE_' + l.mode))} · #${esc(l.id)}</p></div>
      <div class="head-r">${btn(t('LOBBY_WAYPOINT'), 'lWaypoint', 'btn-ghost', { icon: 'fas fa-location-dot', size: 'sm', free: true })}</div></div>
    <div class="cols c12 fill-y">
      <div class="panel"><div class="p-body" data-scroll="li" style="padding:12px;gap:12px">
        ${trackSvg(tr.preview, l.laps > 0, 170)}
        <div><b style="font-size:14px;color:var(--white)">${esc(tr.name)}</b><div class="hint" style="margin-top:3px">${esc(tr.description || t('TRACK_NO_DESC'))}</div></div>
        <div class="kv">
          <span>${esc(t('LOBBY_TRACK_TYPE'))}</span><b>${l.laps > 0 ? esc(t('TRACK_circuit')) + ' · ' + esc(t('UI_N_LAPS', l.laps)) : esc(t('TRACK_sprint'))}</b>
          <span>${esc(t('LOBBY_DISTANCE'))}</span><b>${esc(dist(tr.length * Math.max(1, l.laps)))}</b>
          <span>${esc(t('LOBBY_CPS'))}</span><b>${num(tr.checkpoints)}</b>
          <span>${esc(t('CREATE_CLASS'))}</span><b>${esc(l.class === 'Open' ? t('CLASS_OPEN') : l.class)}</b>
          <span>${esc(t('CREATE_GHOST'))}</span><b>${esc(l.ghost ? t('UI_ON') : t('UI_OFF'))}</b>
          ${l.wager ? `<span>${esc(t('LOBBY_WAGER'))}</span><b>${esc(money(l.wager, l.currency))}</b><span>${esc(t('LOBBY_POT'))}</span><b style="color:var(--amber)">${esc(money(l.pot, l.currency))}</b>` : ''}
          ${l.type === 'ranked' ? `<span>${esc(t('LOBBY_AVG_ELO'))}</span><b>${num(l.avgElo)}</b>` : ''}
          <span>${esc(t('TRACK_WR'))}</span><b>${wr ? `${esc(clock(wr.time))} · ${esc(wr.holder.alias)}` : '—'}</b>
        </div>
      </div></div>
      <div class="panel"><div class="p-head"><div><h2><i class="fas fa-users"></i>${esc(t('LOBBY_RACERS', l.participants.length, l.max))}</h2>
        <p>${l.status === 'pending' ? esc(t('LOBBY_ACCEPTED_N', accepted)) : l.status === 'finished' ? esc(t('LOBBY_RESULTS')) : esc(t('LOBBY_STATUS_' + l.status))}</p></div>
        ${mine && mine.status === 'queuing' ? `<span class="tag warn"><span class="spinner" style="width:9px;height:9px;border-width:1.5px"></span>${esc(t('LOBBY_WAIT_HOST'))}</span>` : ''}</div>
        <div class="p-body" data-scroll="lp">${l.status === 'finished' && l.results ? resultsTable(l.results, p.id) : parts || empty('fas fa-users', t('LOBBY_EMPTY'))}</div>
        ${actions ? `<div class="modal-f">${l.status === 'pending' && l.type === 'ranked' ? `<span class="hint sp">${esc(t('LOBBY_RANKED_NEED', S.cfg.Races.RequiredParticipantsForRankedLobby))}</span>` : ''}${actions}</div>` : ''}
      </div></div>`;
}
ACT.noop = () => {};
ACT.lWaypoint = () => {
  const pt = S.lobby && S.lobby.track.preview && S.lobby.track.preview[0];
  if (pt) { post('waypoint', { x: pt[0], y: pt[1] }); toast(t('LOBBY_WAYPOINT_SET')); }
};
ACT.lJoin = async () => {
  const l = S.lobby;
  const v = await pickVehicle(l.class);
  if (!v) return;
  let password = '';
  if (l.hasPassword) {
    password = await promptBox({ title: t('LOBBY_PASSWORD'), text: t('LOBBY_PASSWORD_SUB'), max: 20, ok: t('LOBBY_JOIN'), type: 'password' });
    if (password == null) return;
  }
  const r = await call('lobby:join', { id: l.id, vehicle: v, password });
  if (r) { S.lobby = r; S.activeLobby = r.id; toast(t('LOBBY_JOINED')); render(); }
};
ACT.lLeave = async () => {
  const l = S.lobby;
  const racing = l.status !== 'pending';
  if (!(await confirmBox({ title: racing ? t('LOBBY_DNF') : t('LOBBY_LEAVE'), text: racing ? t('LOBBY_DNF_CONFIRM') : t('LOBBY_LEAVE_CONFIRM') }))) return;
  const r = await call('lobby:leave', { id: l.id });
  if (r) { S.activeLobby = null; go('lobbies'); }
};
ACT.lDisband = async () => {
  if (!(await confirmBox({ title: t('LOBBY_DISBAND'), text: t('LOBBY_DISBAND_CONFIRM') }))) return;
  const r = await call('lobby:disband', { id: S.lobby.id });
  if (r) { S.activeLobby = null; go('lobbies'); }
};
ACT.lStart = async () => {
  const r = await call('lobby:start', { id: S.lobby.id });
  if (r) closeApp();
};
ACT.lm = async d => {
  if (d.k === 'kick' && !(await confirmBox({ title: t('LOBBY_KICK'), text: t('LOBBY_KICK_CONFIRM') }))) return;
  await call('lobby:manage', { id: S.lobby.id, action: d.k, profileId: Number(d.v) });
};

// ════════════════════════════════════════════════════════════════════════
//  TRACKS
// ════════════════════════════════════════════════════════════════════════
function pageTracks() {
  S.tf = S.tf || { q: '', type: 'all', owner: '' };
  const f = S.tf;
  const all = S.tracks || [];
  const q = f.q.trim().toLowerCase(), o = f.owner.trim().toLowerCase();
  const list = all.filter(x => (f.type === 'all' || x.type === f.type)
    && (!q || [x.name, x.description, x.owner.alias].some(s => s && s.toLowerCase().includes(q)))
    && (!o || (x.owner.alias || '').toLowerCase().includes(o)));
  const cards = list.map(x => `<div class="tcard" data-a="trackOpen" data-v="${x.id}">
    ${trackSvg(x.preview, x.type === 'circuit', 120)}
    <div class="tcard-b"><b>${esc(x.name)}${x.private ? ' <i class="fas fa-lock" style="font-size:10px;color:var(--ink-3)"></i>' : ''}</b>
      <span>${esc(t('TRACK_BY', x.owner.alias || '—'))} · ${esc(dist(x.length))} · ${esc(t('UI_N_CPS', x.checkpoints))}</span>
      <div class="tcard-f"><span class="chip ${x.type === 'circuit' ? '' : 'mute'}">${esc(t('TRACK_' + x.type))}</span>
        ${x.worldRecord ? `<span class="chip amber"><i class="fas fa-trophy"></i>${esc(clock(x.worldRecord.time, true))}</span>` : ''}
        ${x.personalBest && (x.personalBest.lap || x.personalBest.time) ? `<span class="chip mute"><i class="fas fa-user"></i>${esc(clock(x.type === 'circuit' ? (x.personalBest.lap || x.personalBest.time) : x.personalBest.time, true))}</span>` : ''}
        <span class="hint" style="margin-left:auto"><i class="fas fa-play" style="font-size:8px"></i> ${num(x.plays)}</span></div></div></div>`).join('');
  return `<div class="head"><div><h1>${esc(t('TRACKS_TITLE'))}</h1><p>${esc(t('TRACKS_SUB'))}</p></div>
      <div class="head-r">${S.canTracks ? btn(t('TRACKS_CREATE'), 'trackBuild', 'btn-teal', { icon: 'fas fa-plus' }) : ''}</div></div>
    <div style="display:flex;gap:8px;flex:none">
      <div class="search"><i class="fas fa-magnifying-glass"></i><input class="input" id="tr-q" data-m="tf.q" data-r value="${esc(f.q)}" placeholder="${esc(t('TRACKS_SEARCH'))}"></div>
      <div class="search" style="max-width:190px"><i class="fas fa-user"></i><input class="input" id="tr-o" data-m="tf.owner" data-r value="${esc(f.owner)}" placeholder="${esc(t('TRACKS_OWNER_PH'))}"></div>
      <div class="seg">${[['all', t('F_ALL')], ['circuit', t('TRACK_circuit')], ['sprint', t('TRACK_sprint')]].map(([v, l]) => `<button class="${f.type === v ? 'on' : ''}" data-a="tfType" data-v="${v}">${esc(l)}</button>`).join('')}</div>
    </div>
    <div class="hint" style="flex:none">${esc(t('TRACKS_SHOWING', list.length, all.length))}</div>
    <div class="scroll" data-scroll="tg">${!S.tracks ? skeleton(4) : list.length ? `<div class="tgrid">${cards}</div>` : empty('fas fa-route', t('TRACKS_NONE'), all.length ? t('TRACKS_ADJUST') : t('TRACKS_FIRST'))}</div>`;
}
ACT.tfType = d => { S.tf.type = d.v; render(); };
ACT.trackBuild = async () => {
  if (!(await confirmBox({ title: t('TRACKS_CREATE'), text: t('TRACKS_BUILDER_INFO'), ok: t('TRACKS_START_BUILDER'), danger: false, icon: 'fas fa-route' }))) return;
  const r = await post('builder');
  if (r && r.error) toast(t(r.error), true);
};
ACT.trackOpen = async d => {
  const id = Number(d.v);
  const base = (S.tracks || []).find(x => x.id === id);
  const st = { tr: base, full: null, edit: false };
  openModal({
    render: () => {
      const x = st.full || st.tr;
      const top = st.full ? st.full.top : null;
      const circuit = x.type === 'circuit';
      if (st.edit) {
        return `<div class="modal wide"><div class="modal-h"><div class="grow"><h4>${esc(t('TRACKS_EDIT'))}</h4><p>${esc(x.name)}</p></div></div>
          <div class="modal-body">
            <div class="field"><label>${esc(t('TRACKS_NAME'))}</label><input id="te-name" maxlength="60" data-m="f.tname" value="${esc(S.f.tname)}"></div>
            <div class="field"><label>${esc(t('TRACKS_DESC'))}</label><textarea id="te-desc" maxlength="500" data-m="f.tdesc">${esc(S.f.tdesc)}</textarea></div>
            <button class="sw-line" data-a="tePriv"><div><b>${esc(t('TRACKS_PRIVATE'))}</b><span>${esc(t('TRACKS_PRIVATE_DESC'))}</span></div><span class="sw ${S.f.tpriv ? 'on' : ''}"><i></i></span></button>
          </div>
          <div class="modal-f">${btn(t('TRACKS_DELETE'), 'teDel', 'btn-red sp', { icon: 'fas fa-trash' })}<span style="flex:1"></span>${btn(t('UI_CANCEL'), 'teCancel', 'btn-line', { free: true })}${btn(t('UI_SAVE'), 'teSave', 'btn-teal', { icon: 'fas fa-check', busyKey: 'track:update' })}</div></div>`;
      }
      return `<div class="modal xwide"><div class="modal-h"><div class="grow"><h4>${esc(x.name)}</h4><p>${esc(t('TRACK_BY', x.owner.alias || '—'))} · ${esc(t('TRACK_' + x.type))}</p></div>
          ${x.canEdit ? btn(t('TRACKS_EDIT'), 'teOpen', 'btn-ghost', { size: 'sm', icon: 'fas fa-pen', free: true }) : ''}</div>
        <div class="modal-body"><div class="cols">
          <div style="display:flex;flex-direction:column;gap:12px">${trackSvg(x.preview, circuit, 210)}
            <div class="hint">${esc(x.description || t('TRACK_NO_DESC'))}</div>
            <div class="kv"><span>${esc(t('LOBBY_DISTANCE'))}</span><b>${esc(dist(x.length))}</b><span>${esc(t('LOBBY_CPS'))}</span><b>${num(x.checkpoints)}</b>
              <span>${esc(t('TRACKS_PLAYS'))}</span><b>${num(x.plays)}</b>
              <span>${esc(t('TRACK_WR'))}</span><b>${x.worldRecord ? `${esc(clock(x.worldRecord.time))} · ${esc(x.worldRecord.holder.alias)}` : esc(t('TRACK_NO_WR'))}</b>
              <span>${esc(t('TRACK_PB'))}</span><b>${x.personalBest ? esc(clock(circuit ? (x.personalBest.lap || x.personalBest.time) : x.personalBest.time)) : '—'}</b></div></div>
          <div class="panel"><div class="p-head"><div><h2><i class="fas fa-trophy"></i>${esc(t('TRACK_TOP'))}</h2><p>${esc(circuit ? t('RES_BEST_LAP') : t('RES_TIME'))}</p></div></div>
            <div class="p-body" style="max-height:300px">${!top ? skeleton(4) : top.length ? top.map((r, i) => `<div class="row ${r.id === S.profile.id ? 'on' : ''}">${posBadge(i + 1)}
              <div class="row-txt"><b>${esc(r.alias)}</b></div><b style="font-size:12px;color:var(--white)">${esc(clock(circuit ? (r.lap || r.time) : r.time))}</b></div>`).join('') : empty('fas fa-stopwatch', t('TRACK_NO_TIMES'))}</div></div>
        </div></div>
        <div class="modal-f">${btn(t('UI_CLOSE'), 'modalNo', 'btn-line', { free: true })}${btn(t('TRACK_RACE_THIS'), 'teRace', 'btn-teal', { icon: 'fas fa-flag-checkered', disabled: !!S.activeLobby, free: true })}</div></div>`;
    },
    on: {
      modalNo: () => closeModal(),
      teOpen: () => { const x = st.full || st.tr; S.f.tname = x.name; S.f.tdesc = x.description || ''; S.f.tpriv = !!x.private; st.edit = true; renderModal(); },
      teCancel: () => { st.edit = false; renderModal(); },
      tePriv: () => { S.f.tpriv = !S.f.tpriv; renderModal(); },
      teSave: async () => {
        const r = await call('track:update', { id, name: S.f.tname, description: S.f.tdesc, private: S.f.tpriv }, { success: t('TRACKS_SAVED') });
        if (r) { closeModal(); loadTracks(); }
      },
      teDel: async () => {
        const x = st.full || st.tr;
        closeModal();
        if (!(await confirmBox({ title: t('TRACKS_DELETE'), text: t('TRACKS_DELETE_CONFIRM', x.name) }))) return;
        if (await call('track:delete', { id }, { success: t('TRACKS_DELETED') })) loadTracks();
      },
      teRace: () => { closeModal(); ACT.createLobby({ track: id }); },
    },
  });
  const r = await req('track:get', { id });
  if (r.data && MODAL) { st.full = Object.assign({}, base, r.data); renderModal(); }
};

// ════════════════════════════════════════════════════════════════════════
//  CREW
// ════════════════════════════════════════════════════════════════════════
const PERMS = [[1, 'PERM_MEMBERS'], [2, 'PERM_MANAGE'], [3, 'PERM_RACES']];
function canCrew(perm) {
  const p = S.profile, c = S.crew;
  if (!c || !p.crewId) return false;
  return c.owner === p.id || (p.crewPerms || []).includes(perm);
}
function crewAvatar(c, cls = 'lg') { return avatar({ avatar: c.avatar, alias: c.tag, color: c.color }, cls); }

function pageCrew() {
  const p = S.profile;
  if (!p.crewId) return pageCrewSearch();
  const c = S.crew;
  if (!c) return `<div class="scroll">${skeleton(6)}</div>`;
  S.crewTab = S.crewTab || 'overview';
  const tabs = [['overview', 'fas fa-gauge', 'CREW_OVERVIEW'], ['members', 'fas fa-users', 'CREW_MEMBERS'], ['activity', 'fas fa-clock-rotate-left', 'CREW_ACTIVITY']]
    .map(([k, i, l]) => `<button class="${S.crewTab === k ? 'on' : ''}" data-a="crewTab" data-v="${k}"><i class="${i}"></i>${esc(t(l))}${k === 'members' ? ` <span class="tally">${c.members.length}</span>` : ''}</button>`).join('');
  let body = '';
  if (S.crewTab === 'members') body = crewMembers(c);
  else if (S.crewTab === 'activity') body = `<div class="panel fill-y"><div class="p-body" data-scroll="ca">${crewActivity(c.activity)}</div></div>`;
  else body = crewOverview(c);
  return `<div class="hero" style="--c:${esc(c.color)}">${crewAvatar(c)}
      <div class="grow"><h3>${esc(c.name)} ${crewTag(c)}</h3><p>${esc(c.description || t('CREW_NO_DESC'))}</p></div>
      <div class="head-r">${canCrew(1) ? btn(t('CREW_INVITE'), 'crewInvite', 'btn-teal', { size: 'sm', icon: 'fas fa-user-plus' }) : ''}
        ${canCrew(2) ? btn(t('CREW_EDIT'), 'crewEdit', 'btn-ghost', { size: 'sm', icon: 'fas fa-pen' }) : ''}
        ${btn(t('CREW_LEAVE'), 'crewLeave', 'btn-red', { size: 'sm', icon: 'fas fa-right-from-bracket' })}</div></div>
    <div class="tabs">${tabs}</div>${body}`;
}
function crewOverview(c) {
  const s = c.stats;
  const top = c.members.slice(0, 6);
  return `<div class="stats c6">
      ${stat(t('STAT_RACES'), num(s.races), 'fas fa-flag-checkered')}${stat(t('STAT_WINS'), num(s.wins), 'fas fa-trophy', 'amber')}
      ${stat(t('STAT_WIN_RATE'), num(s.winRate), 'fas fa-percent', '', '%')}${stat(t('CREW_AVG_ELO'), num(s.avgElo), 'fas fa-chart-line')}
      ${stat(t('CREW_WARS_WON'), num(s.crewWins), 'fas fa-shield-halved')}${stat(t('CREW_WARS_LOST'), num(s.crewLosses), 'fas fa-skull', 'red')}</div>
    <div class="cols fill-y">
      <div class="panel"><div class="p-head"><div><h2><i class="fas fa-ranking-star"></i>${esc(t('CREW_TOP'))}</h2></div></div>
        <div class="p-body" data-scroll="ct">${top.map((m, i) => `<div class="row click" data-a="openProfile" data-v="${m.id}">${posBadge(i + 1)}${avatar(m, 'sm', { online: m.online })}
          <div class="row-txt"><b>${esc(m.alias)}${m.owner ? ' <i class="fas fa-crown" style="color:var(--amber);font-size:10px"></i>' : ''}</b><span>${esc(t('UI_N_RACES', num(m.races)))} · ${esc(t('UI_N_WINS', num(m.wins)))}</span></div>
          <b style="font-size:12.5px;color:var(--white)">${num(m.elo)}</b></div>`).join('')}</div></div>
      <div class="panel"><div class="p-head"><div><h2><i class="fas fa-clock-rotate-left"></i>${esc(t('CREW_ACTIVITY'))}</h2></div></div>
        <div class="p-body" data-scroll="cr">${crewActivity(c.activity.slice(0, 10))}</div></div></div>`;
}
const ACT_ICON = { WON_RACE: ['fas fa-trophy', ''], LOST_RACE: ['fas fa-skull', 'red'], DRAW_RACE: ['fas fa-equals', 'mute'], CREW_CREATED: ['fas fa-flag', ''],
  CREW_JOINED: ['fas fa-user-plus', ''], CREW_LEFT: ['fas fa-user-minus', 'mute'], CREW_KICKED: ['fas fa-user-xmark', 'red'], PERMISSIONS_UPDATED: ['fas fa-key', 'amber'],
  CREW_UPDATED: ['fas fa-pen', 'mute'], CREW_OWNER: ['fas fa-crown', 'amber'] };
function crewActivity(list) {
  if (!list || !list.length) return empty('fas fa-clock-rotate-left', t('CREW_NO_ACTIVITY'));
  return list.map(a => { const [icon, tone] = ACT_ICON[a.type] || ['fas fa-circle', 'mute'];
    return `<div class="row"><div class="tile ${tone}" style="width:28px;height:28px;font-size:11px"><i class="${icon}"></i></div>
      <div class="row-txt"><b style="font-weight:400;white-space:normal">${esc(a.message)}</b></div><span class="hint">${esc(ago(a.created))}</span></div>`; }).join('');
}
function crewMembers(c) {
  const manage = canCrew(1);
  const rows = c.members.map(m => `<div class="row">${avatar(m, '', { online: m.online })}
    <div class="row-txt"><b>${esc(m.alias)}${m.owner ? ` <span class="chip amber"><i class="fas fa-crown"></i>${esc(t('CREW_OWNER'))}</span>` : ''}</b>
      <span>${num(m.elo)} ${esc(t('UI_ELO'))} · ${esc(t('CREW_JOINED', ago(m.joined)))}</span></div>
    <div class="row-r">${(m.owner ? [1, 2, 3] : m.perms).map(x => `<span class="chip mute" title="${esc(t(PERMS[x - 1][1]))}">${esc(t(PERMS[x - 1][1] + '_SHORT'))}</span>`).join('')}
      ${manage && !m.owner && m.id !== S.profile.id ? `<button class="icon-btn" data-a="crewPerms" data-v="${m.id}" title="${esc(t('CREW_EDIT_PERMS'))}"><i class="fas fa-key"></i></button>
        <button class="icon-btn danger" data-a="crewKick" data-v="${m.id}" title="${esc(t('CREW_KICK'))}"><i class="fas fa-user-xmark"></i></button>` : ''}
      <button class="icon-btn" data-a="openProfile" data-v="${m.id}"><i class="fas fa-eye"></i></button></div></div>`).join('');
  const inv = (c.invites || []).map(i => `<div class="row">${avatar(i, 'sm')}<div class="row-txt"><b>${esc(i.alias)}</b><span>${esc(t('CREW_INVITED', ago(i.created)))}</span></div>
    ${manage ? btn(t('CREW_REVOKE'), 'crewRevoke', 'btn-red', { size: 'sm', data: { v: i.profileId } }) : ''}</div>`).join('');
  return `<div class="cols c21 fill-y"><div class="panel"><div class="p-head"><div><h2><i class="fas fa-users"></i>${esc(t('CREW_MEMBERS'))}</h2></div></div><div class="p-body" data-scroll="cm">${rows}</div></div>
    <div class="panel"><div class="p-head"><div><h2><i class="fas fa-envelope"></i>${esc(t('CREW_PENDING'))}</h2></div></div><div class="p-body" data-scroll="cp">${inv || empty('fas fa-envelope-open', t('CREW_NO_INVITES'))}</div></div></div>`;
}
ACT.crewTab = d => { S.crewTab = d.v; render(); };

function pageCrewSearch() {
  S.cs = S.cs || { q: '', list: null };
  if (!S.cs.list && !S.cs.loading) { S.cs.loading = true; req('crew:search', { q: '' }).then(r => { S.cs.list = r.data || []; S.cs.loading = false; render(); }); }
  return `<div class="head"><div><h1>${esc(t('CREW_TITLE'))}</h1><p>${esc(t('CREW_SUB'))}</p></div>
      <div class="head-r">${btn(t('CREW_CREATE'), 'crewCreate', 'btn-teal', { icon: 'fas fa-plus' })}</div></div>
    <div class="note" style="flex:none"><i class="fas fa-circle-info"></i><span>${esc(t('CREW_NONE_NOTE'))}</span></div>
    <div class="search" style="flex:none"><i class="fas fa-magnifying-glass"></i><input class="input" id="cs-q" data-m="cs.q" data-on="crewSearch" value="${esc(S.cs.q)}" placeholder="${esc(t('CREW_SEARCH'))}"></div>
    <div class="panel fill-y"><div class="p-body" data-scroll="cs">${!S.cs.list ? skeleton(5) : S.cs.list.length ? S.cs.list.map(c => `<div class="row click" data-a="crewView" data-v="${c.id}">
      ${crewAvatar(c, '')}<div class="row-txt"><b>${esc(c.name)} ${crewTag(c)}</b><span>${esc(t('CREW_N_MEMBERS', c.members))}</span></div>
      <div class="row-r"><span class="chip mute">${esc(t('CREW_AVG_ELO'))} ${num(c.avgElo)}</span></div></div>`).join('') : empty('fas fa-people-group', t('CREW_NO_RESULTS', S.cs.q))}</div></div>`;
}
ACT.crewSearch = () => debounce('crews', 300, async () => { const r = await req('crew:search', { q: S.cs.q }); S.cs.list = r.data || []; render(); });
ACT.crewView = async d => {
  const r = await req('crew:get', { id: Number(d.v) });
  if (!r.data) return toast(t(r.error || 'ERR_GENERIC'), true);
  const c = r.data;
  openModal({
    render: () => `<div class="modal wide"><div class="modal-h">${crewAvatar(c, '')}<div class="grow"><h4>${esc(c.name)} ${crewTag(c)}</h4><p>${esc(c.description || t('CREW_NO_DESC'))}</p></div></div>
      <div class="modal-body"><div class="stats">${stat(t('STAT_RACES'), num(c.stats.races), 'fas fa-flag-checkered')}${stat(t('STAT_WINS'), num(c.stats.wins), 'fas fa-trophy', 'amber')}
        ${stat(t('CREW_AVG_ELO'), num(c.stats.avgElo), 'fas fa-chart-line')}${stat(t('CREW_MEMBERS'), num(c.members.length), 'fas fa-users', 'mute')}</div>
        <div class="p-body" style="padding:0;max-height:260px">${c.members.map(m => `<div class="row">${avatar(m, 'sm', { online: m.online })}<div class="row-txt"><b>${esc(m.alias)}${m.owner ? ' <i class="fas fa-crown" style="color:var(--amber);font-size:10px"></i>' : ''}</b></div><b style="font-size:12px">${num(m.elo)}</b></div>`).join('')}</div>
        <div class="note"><i class="fas fa-circle-info"></i><span>${esc(t('CREW_JOIN_NOTE'))}</span></div></div>
      <div class="modal-f">${btn(t('UI_CLOSE'), 'modalNo', 'btn-line', { free: true })}</div></div>`,
    on: { modalNo: () => closeModal() },
  });
};

function crewForm(existing) {
  const c = existing || {};
  S.f = { name: c.name || '', tag: c.tag || '', description: c.description || '', nameOk: existing ? true : null, tagOk: existing ? true : null };
  initAvatarForm(c.avatar || '', c.color || S.cfg.Profiles.Colors[0]);
  if (!existing) S.f.av.seed = randSeed();
  const check = (field) => {
    S.f[field + 'Ok'] = 'wait';
    debounce('crew' + field, 350, async () => {
      const r = await req('crew:available', { field, value: S.f[field], except: existing && existing.id });
      S.f[field + 'Ok'] = r.data === true;
      renderModal();
    });
  };
  ACT.crewName = () => check('name');
  ACT.crewTagChk = () => check('tag');
  const state = (k, min) => {
    const v = S.f[k];
    if (!v) return '';
    if (v.length < min) return `<em class="bad">${esc(t('CREW_MIN', min))}</em>`;
    const ok = S.f[k + 'Ok'];
    return ok === 'wait' ? `<em>${esc(t('SIGNUP_CHECKING'))}</em>` : ok === true ? `<em class="ok">${esc(t('SIGNUP_AVAILABLE'))}</em>` : ok === false ? `<em class="bad">${esc(t('SIGNUP_TAKEN'))}</em>` : '';
  };
  openModal({
    render: () => {
      const f = S.f, C = S.cfg.Crews;
      const ok = f.name.trim().length >= 3 && f.tag.length >= C.TagMin && f.nameOk === true && f.tagOk === true;
      return `<div class="modal wide"><div class="modal-h"><div class="grow"><h4>${esc(existing ? t('CREW_EDIT') : t('CREW_CREATE'))}</h4><p>${esc(existing ? t('CREW_EDIT_SUB') : t('CREW_CREATE_SUB'))}</p></div></div>
        <div class="modal-body">
          <div class="grid3"><div class="field span2"><label>${esc(t('CREW_NAME'))}${state('name', 3)}</label><input id="cf-name" maxlength="30" data-m="f.name" data-on="crewName" data-r value="${esc(f.name)}" placeholder="${esc(t('CREW_NAME_PH'))}"></div>
            <div class="field"><label>${esc(t('CREW_TAG'))}${state('tag', C.TagMin)}</label><input id="cf-tag" maxlength="${C.TagMax}" data-m="f.tag" data-t="upper" data-on="crewTagChk" data-r value="${esc(f.tag)}" placeholder="TAG"></div></div>
          <div class="field"><label>${esc(t('CREW_DESC'))}<em>${f.description.length}/250</em></label><textarea id="cf-desc" maxlength="250" data-m="f.description" data-r>${esc(f.description)}</textarea></div>
          <div class="field"><label>${esc(t('SIGNUP_COLOR'))}</label>${swatches(f.color)}</div>
          ${avatarEditor('cf', 'Crews', f.color)}
        </div>
        <div class="modal-f">${existing && existing.owner === S.profile.id ? btn(t('CREW_DISBAND'), 'crewDisband', 'btn-red', { icon: 'fas fa-trash' }) : ''}<span style="flex:1"></span>
          ${btn(t('UI_CANCEL'), 'modalNo', 'btn-line', { free: true })}${btn(existing ? t('UI_SAVE') : t('CREW_CREATE'), 'crewSave', 'btn-teal', { icon: 'fas fa-check', disabled: !ok, busyKey: existing ? 'crew:update' : 'crew:create' })}</div></div>`;
    },
    on: {
      modalNo: () => closeModal(),
      crewSave: async () => {
        const f = S.f;
        const data = { name: f.name.trim(), tag: f.tag, description: f.description, color: f.color, avatar: currentAvatar(f.color) };
        const r = await call(existing ? 'crew:update' : 'crew:create', data, { success: existing ? t('CREW_SAVED') : t('CREW_CREATED') });
        if (r) { closeModal(); S.crew = r; S.cs = null; render(); }
      },
      crewDisband: async () => {
        closeModal();
        if (!(await confirmBox({ title: t('CREW_DISBAND'), text: t('CREW_DISBAND_CONFIRM', existing.name) }))) return;
        if (await call('crew:disband', {}, { success: t('CREW_DISBANDED') })) { S.crew = null; render(); }
      },
    },
  });
}
ACT.crewCreate = () => crewForm(null);
ACT.crewEdit = () => crewForm(S.crew);
ACT.crewLeave = async () => {
  if (!(await confirmBox({ title: t('CREW_LEAVE'), text: t('CREW_LEAVE_CONFIRM', S.crew.name) }))) return;
  if (await call('crew:leave', {}, { success: t('CREW_LEFT') })) { S.crew = null; S.cs = null; render(); }
};
ACT.crewKick = async d => {
  const m = S.crew.members.find(x => x.id === Number(d.v));
  if (!(await confirmBox({ title: t('CREW_KICK'), text: t('CREW_KICK_CONFIRM', m.alias) }))) return;
  if (await call('crew:kick', { profileId: m.id })) loadCrew();
};
ACT.crewRevoke = async d => { if (await call('crew:revoke', { profileId: Number(d.v) })) loadCrew(); };
function permPicker(sel) {
  return `<div style="display:flex;flex-direction:column;gap:6px">${PERMS.map(([id, key]) => `<button class="sw-line" data-a="permT" data-v="${id}"><div><b>${esc(t(key))}</b><span>${esc(t(key + '_DESC'))}</span></div><span class="sw ${sel.includes(id) ? 'on' : ''}"><i></i></span></button>`).join('')}</div>`;
}
ACT.crewPerms = d => {
  const m = S.crew.members.find(x => x.id === Number(d.v));
  const sel = [...(m.perms || [])];
  openModal({
    render: () => `<div class="modal"><div class="modal-h">${avatar(m, 'sm')}<div class="grow"><h4>${esc(t('CREW_EDIT_PERMS'))}</h4><p>${esc(m.alias)}</p></div></div>
      <div class="modal-body">${permPicker(sel)}</div>
      <div class="modal-f">${btn(t('UI_CANCEL'), 'modalNo', 'btn-line', { free: true })}${btn(t('UI_SAVE'), 'permSave', 'btn-teal', { icon: 'fas fa-check', busyKey: 'crew:perms' })}</div></div>`,
    on: {
      modalNo: () => closeModal(),
      permT: e => { const v = Number(e.v); const i = sel.indexOf(v); if (i >= 0) sel.splice(i, 1); else sel.push(v); renderModal(); },
      permSave: async () => { if (await call('crew:perms', { profileId: m.id, perms: sel }, { success: t('CREW_PERMS_SAVED') })) { closeModal(); loadCrew(); } },
    },
  });
};
ACT.crewInvite = () => {
  const st = { q: '', list: null, sel: [], picked: null };
  const search = () => debounce('inv', 300, async () => { const r = await req('profile:search', { q: st.q }); st.list = (r.data || []).filter(x => x.id !== S.profile.id); renderModal(); });
  window.__invq = v => { st.q = v; search(); };
  openModal({
    render: () => `<div class="modal wide"><div class="modal-h"><div class="grow"><h4>${esc(t('CREW_INVITE'))}</h4><p>${esc(t('CREW_INVITE_SUB'))}</p></div></div>
      <div class="modal-body">
        <div class="search"><i class="fas fa-magnifying-glass"></i><input class="input" id="inv-q" value="${esc(st.q)}" oninput="window.__invq(this.value)" placeholder="${esc(t('RACERS_SEARCH_PH'))}"></div>
        <div class="p-body" style="padding:0;max-height:220px" data-scroll="inv">${!st.list ? empty('fas fa-magnifying-glass', t('CREW_INVITE_PROMPT')) : st.list.length ? st.list.map(x => `<div class="row ${x.crewId ? '' : 'click'} ${st.picked === x.id ? 'on' : ''}" ${x.crewId ? '' : `data-a="invPick" data-v="${x.id}"`}>
          ${avatar(x, 'sm', { online: x.online })}<div class="row-txt"><b>${esc(x.alias)} ${crewTag(x.crew)}</b><span>${num(x.elo)} ${esc(t('UI_ELO'))}</span></div>
          ${x.crewId ? `<span class="tag off">${esc(t('CREW_IN_CREW'))}</span>` : ''}</div>`).join('') : empty('fas fa-user', t('RACERS_NO_RESULTS', st.q))}</div>
        <div class="field"><label>${esc(t('CREW_INVITE_PERMS'))}</label>${permPicker(st.sel)}</div></div>
      <div class="modal-f">${btn(t('UI_CANCEL'), 'modalNo', 'btn-line', { free: true })}${btn(t('CREW_SEND_INVITE'), 'invSend', 'btn-teal', { icon: 'fas fa-paper-plane', disabled: !st.picked, busyKey: 'crew:invite' })}</div></div>`,
    on: {
      modalNo: () => closeModal(),
      invPick: e => { st.picked = Number(e.v); renderModal(); },
      permT: e => { const v = Number(e.v); const i = st.sel.indexOf(v); if (i >= 0) st.sel.splice(i, 1); else st.sel.push(v); renderModal(); },
      invSend: async () => { if (await call('crew:invite', { profileId: st.picked, perms: st.sel }, { success: t('CREW_INVITE_SENT') })) { closeModal(); loadCrew(); } },
    },
  });
  document.getElementById('inv-q').focus();
};

// ════════════════════════════════════════════════════════════════════════
//  RACERS / LEADERBOARDS
// ════════════════════════════════════════════════════════════════════════
function pageRacers() {
  S.rb = S.rb || { board: 'elo', q: '', list: null };
  const b = S.rb;
  const st = S.me && S.me.stats;
  const boards = [['elo', 'BOARD_ELO', 'fas fa-chart-line'], ['wins', 'BOARD_WINS', 'fas fa-trophy'], ['winRate', 'BOARD_WINRATE', 'fas fa-percent']];
  const rows = S.board ? S.board[b.board] : null;
  return `<div class="head"><div><h1>${esc(t('RACERS_TITLE'))}</h1><p>${esc(t('RACERS_SUB'))}</p></div>
      <div class="head-r">${btn(t('RACERS_MY_PROFILE'), 'openProfile', 'btn-ghost', { icon: 'fas fa-id-card', data: { v: S.profile.id }, free: true })}</div></div>
    <div class="stats c5">
      ${stat(t('STAT_ELO'), num(S.profile.elo), 'fas fa-chart-line')}
      ${stat(t('STAT_WIN_RATE'), st ? num(st.winRate, 1) : '—', 'fas fa-percent', '', st ? '%' : '')}
      ${stat(t('STAT_PODIUM_RATE'), st ? num(st.podiumRate, 1) : '—', 'fas fa-medal', 'amber', st ? '%' : '')}
      ${stat(t('STAT_DISTANCE'), st ? esc(dist(st.distance)) : '—', 'fas fa-road', 'mute')}
      ${stat(t('STAT_TIME'), st ? esc(hours(st.time)) : '—', 'fas fa-stopwatch', 'mute')}
    </div>
    <div class="cols c21 fill-y">
      <div class="panel"><div class="p-head"><div><h2><i class="${boards.find(x => x[0] === b.board)[2]}"></i>${esc(t(boards.find(x => x[0] === b.board)[1]))}</h2><p>${esc(t(boards.find(x => x[0] === b.board)[1] + '_SUB'))}</p></div>
        <div class="seg">${boards.map(([k, l]) => `<button class="${b.board === k ? 'on' : ''}" data-a="rbBoard" data-v="${k}">${esc(t(l + '_SHORT'))}</button>`).join('')}</div></div>
        <div class="p-body" data-scroll="rb">${!rows ? skeleton(6) : rows.length ? rows.map((r, i) => boardRow(r, i + 1, b.board)).join('') : empty('fas fa-ranking-star', t('BOARD_EMPTY'), b.board === 'winRate' ? t('BOARD_WINRATE_MIN') : '')}</div></div>
      <div class="panel"><div class="p-head"><div><h2><i class="fas fa-magnifying-glass"></i>${esc(t('RACERS_SEARCH'))}</h2><p>${esc(t('RACERS_SEARCH_SUB'))}</p></div></div>
        <div style="padding:10px 10px 0"><div class="search"><i class="fas fa-magnifying-glass"></i><input class="input" id="rs-q" data-m="rb.q" data-on="racerSearch" value="${esc(b.q)}" placeholder="${esc(t('RACERS_SEARCH_PH'))}"></div></div>
        <div class="p-body" data-scroll="rs">${!b.list ? empty('fas fa-user-magnifying-glass fa-user', t('RACERS_SEARCH_PROMPT')) : b.list.length ? b.list.map(r => `<div class="row click" data-a="openProfile" data-v="${r.id}">
          ${avatar(r, 'sm', { online: r.online })}<div class="row-txt"><b>${esc(r.alias)} ${crewTag(r.crew)}</b><span>${esc(rankOf(r.elo).rank.name)}</span></div><b style="font-size:12px">${num(r.elo)}</b></div>`).join('')
          : empty('fas fa-user', t('RACERS_NO_RESULTS', b.q))}</div></div>
    </div>`;
}
ACT.rbBoard = d => { S.rb.board = d.v; render(); };
ACT.racerSearch = () => debounce('racers', 300, async () => {
  if (!S.rb.q.trim()) { S.rb.list = null; render(); return; }
  const r = await req('profile:search', { q: S.rb.q });
  S.rb.list = r.data || [];
  render();
});

// ── profile page ────────────────────────────────────────────────────────
function eloChart(hist) {
  if (!hist || hist.length < 2) return empty('fas fa-chart-line', t('CHART_NO_DATA'));
  const W = 520, H = 150, pl = 34, pr = 8, pt = 10, pb = 18;
  const vals = hist.map(h => h.elo);
  let min = Math.min(...vals), max = Math.max(...vals);
  if (max - min < 20) { min -= 10; max += 10; }
  const x = i => pl + i * (W - pl - pr) / (hist.length - 1);
  const y = v => pt + (1 - (v - min) / (max - min)) * (H - pt - pb);
  const line = vals.map((v, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)} ${y(v).toFixed(1)}`).join(' ');
  const area = `${line} L${x(vals.length - 1).toFixed(1)} ${H - pb} L${pl} ${H - pb} Z`;
  const ticks = [min, (min + max) / 2, max].map(v => `<line class="ax" x1="${pl}" x2="${W - pr}" y1="${y(v).toFixed(1)}" y2="${y(v).toFixed(1)}"/><text x="${pl - 5}" y="${(y(v) + 3).toFixed(1)}" text-anchor="end">${Math.round(v)}</text>`).join('');
  const last = vals.length - 1;
  return `<svg class="chart" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none"><defs><linearGradient id="gt" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="var(--teal)" stop-opacity=".35"/><stop offset="1" stop-color="var(--teal)" stop-opacity="0"/></linearGradient></defs>
    ${ticks}<path class="ar" d="${area}"/><path class="ln" d="${line}"/><circle cx="${x(last).toFixed(1)}" cy="${y(vals[last]).toFixed(1)}" r="3.5" fill="var(--teal)"/></svg>`;
}
function monthChart(months) {
  if (!months || !months.length) return empty('fas fa-chart-column', t('CHART_NO_DATA'));
  const W = 520, H = 150, pb = 18, pt = 8;
  const max = Math.max(...months.map(m => m.races), 1);
  const bw = (W - 20) / months.length;
  return `<svg class="chart" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none">${months.map((m, i) => {
    const h = (m.races / max) * (H - pb - pt), hw = (m.wins / max) * (H - pb - pt);
    const x = 10 + i * bw + bw * 0.18, w = bw * 0.64;
    return `<rect class="br" x="${x.toFixed(1)}" y="${(H - pb - h).toFixed(1)}" width="${w.toFixed(1)}" height="${h.toFixed(1)}" rx="2"/>
      <rect class="bw" x="${x.toFixed(1)}" y="${(H - pb - hw).toFixed(1)}" width="${w.toFixed(1)}" height="${hw.toFixed(1)}" rx="2"/>
      <text x="${(x + w / 2).toFixed(1)}" y="${H - 5}" text-anchor="middle">${esc(String(m.month).slice(5))}</text>`;
  }).join('')}</svg>`;
}
function pageProfile() {
  const id = S.viewId || S.profile.id;
  const v = S.viewProfile;
  if (!v || v.id !== id) {
    if (!S.loadingProfile) {
      S.loadingProfile = true;
      req('profile:get', { id }).then(r => { S.loadingProfile = false; if (r.data) S.viewProfile = r.data; else { toast(t(r.error || 'ERR_GENERIC'), true); S.page = 'racers'; } render(); });
    }
    return `<div class="scroll">${skeleton(6)}</div>`;
  }
  const s = v.stats, me = v.id === S.profile.id;
  const { rank, next } = rankOf(v.elo);
  S.profileTab = S.profileTab || 'overview';
  const tabs = [['overview', 'PROFILE_PERFORMANCE'], ['log', 'PROFILE_LOG'], ['achievements', 'PROFILE_ACHIEVEMENTS']]
    .map(([k, l]) => `<button class="${S.profileTab === k ? 'on' : ''}" data-a="pTab" data-v="${k}">${esc(t(l))}</button>`).join('');
  let body;
  if (S.profileTab === 'log') {
    body = `<div class="panel fill-y"><div class="p-body" data-scroll="plog">${s.recent.length ? `<table><thead><tr><th>#</th><th>${esc(t('UI_TRACK'))}</th><th>${esc(t('UI_MODE'))}</th><th>${esc(t('UI_VEHICLE'))}</th><th class="r">${esc(t('RES_TIME'))}</th><th class="r">${esc(t('RES_BEST_LAP'))}</th><th class="r">${esc(t('UI_ELO'))}</th><th class="r">${esc(t('UI_DATE'))}</th></tr></thead><tbody>
      ${s.recent.map(r => `<tr><td>${posBadge(r.position, r.status)}</td><td><b>${esc(r.track || '—')}</b></td><td>${esc(t('MODE_' + r.mode))}${r.type === 'ranked' ? ' <i class="fas fa-trophy" style="color:var(--amber);font-size:9px"></i>' : ''}</td><td>${esc(r.vehicle || '—')}</td>
        <td class="r">${r.status === 'finished' ? esc(clock(r.time)) : '—'}</td><td class="r">${r.bestLap ? esc(clock(r.bestLap)) : '—'}</td><td class="r">${eloDelta(r.eloDelta) || '—'}</td><td class="r">${esc(ago(r.date))}</td></tr>`).join('')}</tbody></table>`
      : empty('fas fa-flag-checkered', t('PROFILE_NO_RACES'))}</div></div>`;
  } else if (S.profileTab === 'achievements') {
    const defs = S.cfg.Achievements;
    body = `<div class="scroll" data-scroll="pach"><div class="ach">${s.achievements.map(a => {
      const d = defs.find(x => x.id === a.id) || {};
      return `<div class="ach-i ${a.unlocked ? 'on' : ''}"><div class="tile"><i class="fas fa-${esc(d.icon || 'trophy')}"></i></div>
        <div><b>${esc(d.label || a.id)}</b><span>${esc(d.desc || '')}</span><div class="track"><div class="bar-fill" style="width:${Math.round(a.progress / a.goal * 100)}%"></div></div></div>
        <span class="hint">${a.unlocked ? '<i class="fas fa-check" style="color:var(--teal)"></i>' : esc(d.stat === 'distance' ? `${dist(a.progress)} / ${dist(a.goal)}` : d.stat === 'time' ? `${hours(a.progress)} / ${hours(a.goal)}` : `${num(a.progress)} / ${num(a.goal)}`)}</span></div>`;
    }).join('')}</div></div>`;
  } else {
    const dd = s.distribution, fin = dd.first + dd.podium + dd.mid + dd.rest || 1;
    const drow = (l, n) => `<div class="dist-row"><span>${esc(l)}</span><div class="track"><div class="bar-fill" style="width:${n / fin * 100}%"></div></div><b>${n}</b></div>`;
    body = `<div class="scroll" data-scroll="pov"><div class="cols">
      <div class="panel"><div class="p-head"><div><h2><i class="fas fa-chart-line"></i>${esc(t('CHART_ELO'))}</h2><p>${esc(t('CHART_ELO_SUB'))}</p></div></div><div class="p-pad">${eloChart(s.eloHistory)}</div></div>
      <div class="panel"><div class="p-head"><div><h2><i class="fas fa-chart-column"></i>${esc(t('CHART_MONTHLY'))}</h2><p>${esc(t('CHART_MONTHLY_SUB'))}</p></div></div><div class="p-pad">${monthChart(s.monthly)}</div></div>
      <div class="panel"><div class="p-head"><div><h2><i class="fas fa-medal"></i>${esc(t('CHART_POSITIONS'))}</h2><p>${esc(t('CHART_POSITIONS_SUB'))}</p></div></div>
        <div class="p-pad"><div class="dist">${drow(t('DIST_FIRST'), dd.first)}${drow(t('DIST_PODIUM'), dd.podium)}${drow(t('DIST_MID'), dd.mid)}${drow(t('DIST_REST'), dd.rest)}</div></div></div>
      <div class="panel"><div class="p-head"><div><h2><i class="fas fa-list"></i>${esc(t('PROFILE_DETAILS'))}</h2></div></div>
        <div class="p-pad"><div class="kv"><span>${esc(t('STAT_AVG_POS'))}</span><b>${num(s.avgPosition, 1)}</b><span>${esc(t('STAT_BEST_LAP'))}</span><b>${s.bestLap ? esc(clock(s.bestLap)) : '—'}</b>
          <span>${esc(t('STAT_BEST_STREAK'))}</span><b>${num(s.bestStreak)}</b><span>${esc(t('STAT_DNFS'))}</span><b>${num(s.dnfs)}</b>
          <span>${esc(t('STAT_THIS_MONTH'))}</span><b>${num(s.thisMonth)}</b><span>${esc(t('STAT_RANKED'))}</span><b>${num(s.ranked)}</b></div></div></div>
    </div></div>`;
  }
  return `<div class="hero" style="--c:${esc(v.color)}">${avatar(v, 'xl', { online: v.online })}
      <div class="grow"><button class="back" data-a="nav" data-v="racers"><i class="fas fa-arrow-left"></i>${esc(t('UI_BACK'))}</button>
        <h3>${esc(v.alias)} ${crewTag(v.crew)}</h3><p>${esc(rank.name)}${next ? ` · ${esc(t('HOME_NEXT_RANK', num(next.min - v.elo), next.name))}` : ''} · ${esc(v.online ? t('UI_ONLINE') : t('UI_OFFLINE'))}</p></div>
      <div class="hero-r"><b>${num(v.elo)}</b><span>${esc(t('UI_ELO'))}</span>${me ? `<div style="margin-top:8px">${btn(t('UI_EDIT_PROFILE'), 'editProfile', 'btn-ghost', { size: 'sm', icon: 'fas fa-pen' })}</div>` : ''}</div></div>
    <div class="stats c6">
      ${stat(t('STAT_RACES'), num(s.races), 'fas fa-flag-checkered')}${stat(t('STAT_WINS'), num(s.wins), 'fas fa-trophy', 'amber')}
      ${stat(t('STAT_PODIUMS'), num(s.podiums), 'fas fa-medal')}${stat(t('STAT_WIN_RATE'), num(s.winRate, 1), 'fas fa-percent', '', '%')}
      ${stat(t('STAT_STREAK'), s.streak > 0 ? '+' + s.streak : s.streak, 'fas fa-fire', s.streak < 0 ? 'red' : '')}${stat(t('STAT_DISTANCE'), esc(dist(s.distance)), 'fas fa-road', 'mute')}</div>
    <div class="tabs">${tabs}</div>${body}`;
}
ACT.pTab = d => { S.profileTab = d.v; render(); };

// ════════════════════════════════════════════════════════════════════════
//  SETTINGS
// ════════════════════════════════════════════════════════════════════════
function pageSettings() {
  const s = S.settings;
  S.setTab = S.setTab || 'general';
  const nav = [['general', 'fas fa-gear', 'SET_GENERAL'], ['racing', 'fas fa-flag-checkered', 'SET_RACING'], ['notifications', 'fas fa-bell', 'SET_NOTIFY']];
  const toggle = (key, label, desc) => `<button class="sw-line" data-a="setToggle" data-k="${key}"><div><b>${esc(t(label))}</b><span>${esc(t(desc))}</span></div><span class="sw ${s[key] ? 'on' : ''}"><i></i></span></button>`;
  let body;
  if (S.setTab === 'racing') {
    body = `${toggle('checkpointDui', 'SET_DUI', 'SET_DUI_DESC')}${toggle('checkpointDuiShowNext', 'SET_DUI_NEXT', 'SET_DUI_NEXT_DESC')}
      <div class="sw-line" style="cursor:default"><div><b>${esc(t('SET_DUI_SCALE'))}</b><span>${esc(t('SET_DUI_SCALE_DESC'))}</span></div>
        <div class="range" style="width:220px"><input type="range" min="25" max="120" value="${s.checkpointDuiScale}" data-a="noop" oninput="window.__set('checkpointDuiScale',+this.value)"><b>${s.checkpointDuiScale}%</b></div></div>
      <div class="sw-line" style="cursor:default"><div><b>${esc(t('SET_DUI_COUNT'))}</b><span>${esc(t('SET_DUI_COUNT_DESC'))}</span></div>
        <div class="seg">${[1, 2, 3, 4, 5].map(n => `<button class="${s.checkpointDuiCount === n ? 'on' : ''}" data-a="setVal" data-k="checkpointDuiCount" data-v="${n}" data-n="1">${n}</button>`).join('')}</div></div>
      ${toggle('showBoard', 'SET_BOARD', 'SET_BOARD_DESC')}${toggle('showSpeed', 'SET_SPEED', 'SET_SPEED_DESC')}`;
  } else if (S.setTab === 'notifications') {
    body = [['all', 'fas fa-bell', 'SET_N_ALL'], ['muted', 'fas fa-bell-slash', 'SET_N_MUTED'], ['none', 'fas fa-ban', 'SET_N_NONE']].map(([k, i, l]) =>
      `<button class="ccard ${s.notifications === k ? 'on' : ''}" data-a="setVal" data-k="notifications" data-v="${k}" style="flex-direction:row;align-items:center;gap:12px"><i class="${i}"></i><div><b>${esc(t(l))}</b><span style="display:block">${esc(t(l + '_DESC'))}</span></div></button>`).join('');
  } else {
    const locs = Object.entries(S.locales);
    body = `${locs.length > 1 ? `<div class="sw-line" style="cursor:default"><div><b>${esc(t('SET_LANGUAGE'))}</b><span>${esc(t('SET_LANGUAGE_DESC'))}</span></div>
        <div class="seg">${locs.map(([k, l]) => `<button class="${s.language === k ? 'on' : ''}" data-a="setVal" data-k="language" data-v="${k}">${esc(l)}</button>`).join('')}</div></div>` : ''}
      <div class="sw-line" style="cursor:default"><div><b>${esc(t('SET_UNITS'))}</b><span>${esc(t('SET_UNITS_DESC'))}</span></div>
        <div class="seg"><button class="${s.units === 'kmh' ? 'on' : ''}" data-a="setVal" data-k="units" data-v="kmh">${esc(t('SET_KMH'))}</button><button class="${s.units === 'mph' ? 'on' : ''}" data-a="setVal" data-k="units" data-v="mph">${esc(t('SET_MPH'))}</button></div></div>
      ${toggle('soundEnabled', 'SET_SOUNDS', 'SET_SOUNDS_DESC')}
      ${S.maps && S.maps.List && Object.keys(S.maps.List).length ? `<div class="sw-line" style="cursor:default;align-items:flex-start"><div><b>${esc(t('SET_MAP'))}</b><span>${esc(t('SET_MAP_DESC'))}</span></div>
        <div class="mapopts">${Object.entries(S.maps.List).map(([k, m]) => {
          const on = (s.mapStyle && S.maps.List[s.mapStyle] ? s.mapStyle : S.maps.Default) === k;
          return `<button class="mapopt ${on ? 'on' : ''}" data-a="setVal" data-k="mapStyle" data-v="${esc(k)}">${mapThumb(m)}${esc(m.label || k)}</button>`;
        }).join('')}</div></div>` : ''}`;
  }
  return `<div class="head"><div><h1>${esc(t('SET_TITLE'))}</h1><p>${esc(t('SET_SUB'))}</p></div></div>
    <div class="cols fill-y" style="grid-template-columns:200px 1fr">
      <div style="display:flex;flex-direction:column;gap:3px">${nav.map(([k, i, l]) => `<button class="nav ${S.setTab === k ? 'on' : ''}" data-a="setTab" data-v="${k}"><i class="${i}"></i>${esc(t(l))}</button>`).join('')}</div>
      <div class="panel"><div class="p-head"><div><h2>${esc(t(nav.find(n => n[0] === S.setTab)[2]))}</h2><p>${esc(t(nav.find(n => n[0] === S.setTab)[2] + '_DESC'))}</p></div></div>
        <div class="p-body" style="gap:8px;padding:12px">${body}</div></div></div>`;
}
async function setSetting(key, value) {
  S.settings[key] = value;
  const r = await post('setting', { key, value });
  if (key === 'language' && r && r.locale) T = r.locale;
  render();
}
window.__set = (k, v) => { S.settings[k] = v; debounce('set' + k, 250, () => setSetting(k, v)); const b = document.querySelector('.range b'); if (b) b.textContent = v + '%'; };
ACT.setTab = d => { S.setTab = d.v; render(); };
ACT.setToggle = d => setSetting(d.k, !S.settings[d.k]);
ACT.setVal = d => setSetting(d.k, d.n ? Number(d.v) : d.v);

// ════════════════════════════════════════════════════════════════════════
//  INBOX
// ════════════════════════════════════════════════════════════════════════
let INBOX = null;
async function loadInbox() {
  const r = await req('inbox:list');
  INBOX = r.data || [];
  if (MODAL && MODAL.inbox) renderModal();
}
function rewardText(m) {
  const md = m.metadata || {};
  if (md.rewardType === 'item') return (md.items || []).map(i => `${i.amount || 1}x ${i.item}`).join(', ');
  if (md.rewardType) return money(md.amount, md.rewardType);
  return '';
}
ACT.inbox = () => {
  INBOX = null;
  openModal({
    inbox: true,
    render: () => {
      const list = INBOX;
      const body = !list ? skeleton(4) : list.length ? list.map(m => {
        const md = m.metadata || {};
        const icon = m.type === 'reward' ? ['fas fa-gift', 'amber'] : m.type === 'crew_invite' ? ['fas fa-people-group', ''] : ['fas fa-envelope', 'mute'];
        let actions = '';
        if (m.type === 'reward') actions = btn(t('INBOX_CLAIM', rewardText(m)), 'ibClaim', 'btn-teal', { size: 'sm', icon: 'fas fa-hand-holding-dollar', data: { v: m.id }, busyKey: 'inbox:claim' });
        else if (m.type === 'crew_invite') actions = `${btn(t('INBOX_JOIN'), 'ibJoin', 'btn-teal', { size: 'sm', icon: 'fas fa-check', data: { v: m.id } })}${btn(t('INBOX_DECLINE'), 'ibDecline', 'btn-line', { size: 'sm', data: { v: m.id } })}`;
        else actions = btn(t('INBOX_DELETE'), 'ibDelete', 'btn-line', { size: 'sm', icon: 'fas fa-trash', data: { v: m.id } });
        return `<div class="msg ${m.read ? '' : 'unread'}"><div class="tile ${icon[1]}"><i class="${icon[0]}"></i></div>
          <div class="row-txt"><b>${esc(t('INBOX_TYPE_' + m.type))} ${md.crewTag ? crewTag({ tag: md.crewTag, color: md.crewColor || '#08afa2' }) : ''}</b>
            <span>${esc(m.message || (md.message ? t(md.message) : ''))}</span><div class="msg-a">${actions}</div></div>
          <span class="hint">${esc(ago(m.created))}</span></div>`;
      }).join('') : empty('fas fa-envelope-open', t('INBOX_EMPTY'), t('INBOX_EMPTY_SUB'));
      return `<div class="modal wide"><div class="modal-h"><div class="grow"><h4>${esc(t('INBOX_TITLE'))}</h4><p>${esc(t('INBOX_SUB'))}</p></div></div>
        <div class="modal-body" data-scroll="ib" style="max-height:460px">${body}</div>
        <div class="modal-f">${btn(t('UI_CLOSE'), 'modalNo', 'btn-line', { free: true })}</div></div>`;
    },
    on: {
      modalNo: () => closeModal(),
      ibClaim: async d => { if (await call('inbox:claim', { id: Number(d.v) }, { success: t('INBOX_CLAIMED') })) loadInbox(); },
      ibJoin: async d => { if (await call('crew:respond', { messageId: Number(d.v), accept: true }, { success: t('INBOX_JOINED') })) { loadInbox(); } },
      ibDecline: async d => { if (await call('crew:respond', { messageId: Number(d.v), accept: false })) loadInbox(); },
      ibDelete: async d => { if (await call('inbox:delete', { id: Number(d.v) })) loadInbox(); },
    },
  });
  loadInbox().then(() => { req('inbox:read', { id: 0 }); S.inbox = 0; render(); });
};
