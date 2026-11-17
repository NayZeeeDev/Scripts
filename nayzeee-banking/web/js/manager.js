/* ═══════════════════════════════════════════════════════════
   NAYZEEE BANKING — BANKING MANAGER (/bankingmanager)
   Uses app.js's helpers: esc, initials, notify, openModal,
   closeModal. Everything the server does is behind a staff
   check of its own; this page only draws it.
   ═══════════════════════════════════════════════════════════ */
const MG = {
  boot: null, page: 'overview',
  playerQ: '', players: [], player: null,
  accQ: '', branches: null, branch: null, me: null,
  settings: null, setGroup: 'general', setQ: '',
  auditPage: 1, map: { z: 1, x: 0, y: 0 }
};

/* the dark map (web/images/map.png) and where the world sits on it */
const MAP = { w: 695, h: 1045, sx: 0.09266, ox: 305.9, sy: 0.08779, oy: 698.9 };
const toMap = (x, y) => ({ px: MAP.ox + MAP.sx * x, py: MAP.oy - MAP.sy * y });
const toWorld = (px, py) => ({ x: (px - MAP.ox) / MAP.sx, y: (MAP.oy - py) / MAP.sy });

const MI = {
  bank:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M3 10 12 4l9 6M5 10v9h14v-9M9 19v-5h6v5"/></svg>',
  users:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><circle cx="9" cy="8" r="3.2"/><path d="M2.8 19.5a6.2 6.2 0 0 1 12.4 0M16.5 5.4a3.2 3.2 0 0 1 0 5.9M18 19.5a6.4 6.4 0 0 0-2-4.4"/></svg>',
  coin:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><circle cx="12" cy="12" r="8.5"/><path d="M14.5 9.2a3 3 0 0 0-5.2 2c0 2.4 5 2 5 4.2a3 3 0 0 1-5.2 1.5M12 6.5v11"/></svg>',
  card:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><rect x="2.5" y="5" width="19" height="14" rx="2.5"/><path d="M2.5 10h19M6 15h3"/></svg>',
  bill:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M6 3h12v18l-3-2-3 2-3-2-3 2V3z"/><path d="M9.5 8h5M9.5 12h5"/></svg>',
  pin:    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M12 21s-6.5-5.6-6.5-11a6.5 6.5 0 0 1 13 0C18.5 15.4 12 21 12 21z"/><circle cx="12" cy="10" r="2.4"/></svg>',
  search: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/></svg>',
  go:     '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14M13 6l6 6-6 6"/></svg>',
  move:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v18M3 12h18M12 3l-3 3M12 3l3 3M12 21l-3-3M12 21l3-3M3 12l3-3M3 12l3 3M21 12l-3-3M21 12l-3 3"/></svg>',
  me:     '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><circle cx="12" cy="7.5" r="3.5"/><path d="M5 20.5a7 7 0 0 1 14 0"/></svg>',
  machine:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="8" width="16" height="11" rx="2"/><path d="M8 8V5h8v3M8 13h8M10 16h4"/></svg>',
  undo:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4 9h11a5 5 0 0 1 0 10H8"/><path d="M8 5 4 9l4 4"/></svg>',
  trash:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/></svg>',
  plus:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>',
  minus:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M5 12h14"/></svg>',
  fit:    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/></svg>',
  lock:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>',
  history:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/></svg>',
  export: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4v11M7.5 10.5 12 15l4.5-4.5M5 19h14"/></svg>',
  chart:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M3 17.5 9 11l4 4 8-8.5"/><path d="M15 6.5h6v6"/></svg>',
  warn:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4 2.5 20h19L12 4z"/><path d="M12 10v4.5M12 17.5v.01"/></svg>',
};

/* ── bridge ───────────────────────────────────────────────── */
async function mPost(name, ...args) {
  const control = new AbortController();
  const timer = setTimeout(() => control.abort(), 15000);
  try {
    const res = await fetch(`https://${RES}/mgr`, {
      method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify({ name, args, n: args.length }), signal: control.signal
    });
    return await res.json();
  } catch (e) {
    return { ok: false, msg: 'The server did not answer.' };
  } finally { clearTimeout(timer); }
}

async function mWorld(what, extra) {
  try {
    const res = await fetch(`https://${RES}/mgrWorld`, {
      method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(Object.assign({ what }, extra || {}))
    });
    return await res.json();
  } catch (e) { return { ok: false }; }
}

function mSay(res, fallback) {
  if (!res) { notify('Banking Manager', fallback || 'That did not go through.', 'error'); return false; }
  if (res.msg || !res.ok) notify('Banking Manager', res.msg || fallback || 'That did not go through.', res.ok ? 'success' : 'error');
  return res.ok;
}

/* ── formatting ───────────────────────────────────────────── */
const mcur = () => (MG.boot && MG.boot.currency) || '$';
const mm = (n) => {
  const r = Math.round(Number(n) || 0);
  const v = Math.abs(r).toLocaleString('en-US').replace(/,/g, ' ');
  return (r < 0 ? '−' : '') + mcur() + v;
};
const mshort = (n) => {
  n = Number(n) || 0; const a = Math.abs(n); const s = n < 0 ? '−' : '';
  if (a >= 1e9) return `${s}${mcur()}${(a / 1e9).toFixed(1)}B`;
  if (a >= 1e6) return `${s}${mcur()}${(a / 1e6).toFixed(1)}M`;
  if (a >= 1e4) return `${s}${mcur()}${(a / 1e3).toFixed(1)}K`;
  return mm(n);
};
const mAgo = (t) => {
  if (!t) return '—';
  const s = Math.max(0, Math.floor(Date.now() / 1000 - t));
  if (s < 60) return 'just now';
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return `${Math.floor(s / 86400)}d ago`;
};
const TYPE_COLOUR = { personal: 'var(--teal)', savings: '#0fd4c4', shared: '#9ea5aa', society: '#e5a50a' };
const view = () => document.getElementById('mgrView');
const head = (title, sub, acts) => `
  <div class="head"><div><h1>${esc(title)}</h1><p>${esc(sub)}</p></div>${acts ? `<div class="head-act">${acts}</div>` : ''}</div>`;
const panel = (title, sub, body, acts) => `
  <div class="panel"><div class="p-head"><div><h2>${esc(title)}</h2>${sub ? `<p>${esc(sub)}</p>` : ''}</div>
  ${acts ? `<div class="acts">${acts}</div>` : ''}</div><div class="p-body tight">${body}</div></div>`;
const emptyBox = (title, text, icon) => `<div class="empty">${icon || MI.search}<b>${esc(title)}</b><span>${esc(text)}</span></div>`;
const loading = () => { view().innerHTML = `<div class="empty" style="margin-top:40px">${MI.history}<b>Loading</b><span>Asking the server…</span></div>`; };

/* ═══════════════════════════════════════════════════════════
   OPEN · CLOSE · NAV
   ═══════════════════════════════════════════════════════════ */
function mgrOpen(boot, page) {
  MG.boot = boot;
  if (typeof applyTheme === 'function' && boot.ui) applyTheme(boot.ui);
  document.getElementById('mgrStatus').innerHTML = `Signed in as <b>${esc(boot.me)}</b>`;
  document.getElementById('mgrName').textContent = boot.me || '—';
  document.getElementById('mgrAv').textContent = initials(boot.me) || 'ST';
  document.getElementById('mgrStack').textContent = `${boot.framework || '?'} · ${boot.inventory || '?'}`;
  document.getElementById('mgrVer').textContent = `v${boot.version || '1.0.0'}`;
  document.body.classList.remove('hud-up');
  document.body.classList.add('mgr-up');
  mgrGo(page || MG.page || 'overview');
}

function mgrClose(tell) {
  closeModal();
  document.body.classList.remove('mgr-up');
  if (tell !== false) fetch(`https://${RES}/mgrClose`, { method: 'POST', body: '{}' }).catch(() => {});
}

function mgrGo(page) {
  MG.page = page;
  document.querySelectorAll('#mgrNav .nav').forEach(b => b.classList.toggle('on', b.dataset.mpage === page));
  const fn = MPAGES[page] || MPAGES.overview;
  fn();
}

document.getElementById('mgrNav').addEventListener('click', (e) => {
  const b = e.target.closest('[data-mpage]');
  if (b) mgrGo(b.dataset.mpage);
});
document.getElementById('mgrClose').addEventListener('click', () => mgrClose());

window.addEventListener('message', (e) => {
  const m = e.data || {};
  if (m.action === 'manager') mgrOpen(m.data, m.page);
  else if (m.action === 'managerClose') mgrClose(false);
  else if (m.action === 'managerHide') { closeModal(); document.body.classList.remove('mgr-up'); }
  else if (m.action === 'managerShow') { document.body.classList.add('mgr-up'); mgrGo(m.page || MG.page); }
  else if (m.action === 'mgrHud') drawHud(m.data);
});

document.addEventListener('keydown', (e) => {
  if (!document.body.classList.contains('mgr-up')) return;
  if (e.key !== 'Escape') return;
  if (document.getElementById('veil').classList.contains('up')) return closeModal();
  if (document.querySelector('.map-pop')) return closeMapPop();
  mgrClose();
});

/* ═══════════════════════════════════════════════════════════
   OVERVIEW
   ═══════════════════════════════════════════════════════════ */
async function pageOverview() {
  loading();
  const res = await mPost('overview');
  if (MG.page !== 'overview') return;
  if (!res.ok) return (view().innerHTML = emptyBox('No answer', res.msg || 'The server did not answer.'));
  const d = res.data;
  document.getElementById('mgrTallyOnline').textContent = d.online;
  document.getElementById('mgrTallyBranches').textContent = d.branches;

  const types = ['personal', 'savings', 'shared', 'society'];
  const sum = (t) => (d.byType[t] && d.byType[t].sum) || 0;
  const count = types.reduce((a, t) => a + ((d.byType[t] && d.byType[t].n) || 0), 0);
  const positive = types.reduce((a, t) => a + Math.max(0, sum(t)), 0) || 1;
  const peak = Math.max(1, ...d.days.map(x => Math.max(x.inn, x.out)));
  const dayName = (s) => new Date(s + 'T12:00:00').toLocaleDateString('en-GB', { weekday: 'short' });

  const stat = (icon, label, value, note, red) => `
    <div class="stat"><div class="tile ${red ? 'red' : ''}">${icon}</div>
    <div class="stat-txt"><span>${esc(label)}</span><b>${value}</b>${note ? `<i>${esc(note)}</i>` : ''}</div></div>`;

  view().innerHTML = `
    ${head('Overview', 'The whole bank at a glance: what it holds, who owes it and what staff have done.',
      `<button class="btn-ghost" data-mact="refresh">${MI.history}Refresh</button>`)}
    <div class="m-stats">
      ${stat(MI.bank, 'Held by the bank', mshort(d.total), `${count} accounts`)}
      ${stat(MI.users, 'Players in the city', d.online, `${d.branches} branches open`)}
      ${stat(MI.coin, 'Owed on loans', mshort(d.loans.owed), `${d.loans.n} loans · ${d.loans.bad} defaulted`, d.loans.bad > 0)}
      ${stat(MI.bill, 'Unpaid bills', mshort(d.bills.sum), `${d.bills.n} open · ${d.bills.late} overdue`, d.bills.late > 0)}
    </div>
    <div class="m-cols">
      ${panel('Money moving', 'Deposits, wages, fees and payments over the last week (transfers between players left out)', `
        <div class="flow">${d.days.map(x => `
          <div class="day" title="${esc(x.d)} · in ${mm(x.inn)} · out ${mm(x.out)} · ${x.n} moves">
            <div class="bars"><i class="in" style="height:${(x.inn / peak) * 100}%"></i><i class="out" style="height:${(x.out / peak) * 100}%"></i></div>
            <span>${dayName(x.d)}</span></div>`).join('')}</div>
        <div class="legend-row" style="margin-top:12px"><span><i style="background:var(--teal)"></i>In</span><span><i style="background:var(--red)"></i>Out</span>
          <span style="margin-left:auto">Week: in ${mshort(d.days.reduce((a, x) => a + x.inn, 0))} · out ${mshort(d.days.reduce((a, x) => a + x.out, 0))}</span></div>`)}
      ${panel('Where the money sits', `${count} accounts across four kinds`, `
        <div class="mix">${types.map(t => `<i style="width:${Math.max(0, sum(t)) / positive * 100}%;background:${TYPE_COLOUR[t]}"></i>`).join('')}</div>
        <div class="mix-key">${types.map(t => `<div><i style="background:${TYPE_COLOUR[t]}"></i>${t[0].toUpperCase() + t.slice(1)}<b>${mshort(sum(t))}</b></div>`).join('')}</div>
        <div class="kvs" style="margin-top:14px">
          <div><span>Cards in use</span><b>${d.cards.live}</b></div>
          <div><span>Blocked or stolen</span><b>${d.cards.stopped}</b></div>
          <div><span>Owed on credit cards</span><b>${mm(d.cards.owed)}</b></div>
          <div><span>Accounts</span><b>${count}</b></div>
        </div>`)}
    </div>
    <div class="m-cols half">
      ${panel('Largest accounts', 'Click one to open its owner', `<div class="m-list">${d.top.map(a => `
        <div class="row pick" data-owner="${esc(a.type === 'society' ? '' : a.owner)}" data-acc="${a.id}">
          <div class="ic">${a.type === 'society' ? MI.bank : MI.card}</div>
          <div class="row-txt"><b>${esc(a.label)}</b><span class="mono">${esc(a.account_number)} · ${esc(a.type)}</span></div>
          ${a.frozen ? '<span class="tag hot">Frozen</span>' : ''}<span class="amount ${a.balance < 0 ? 'out' : ''}">${mm(a.balance)}</span>
        </div>`).join('') || emptyBox('No accounts yet', 'They appear once players have banked.')}</div>`)}
      ${panel('Staff activity', 'The latest changes made in this panel', `<div class="m-list">${d.audits.map(auditRow).join('') ||
        emptyBox('Nothing yet', 'Every change made here is written down, with who made it.', MI.history)}</div>`,
        `<button class="btn-ghost" data-mpage="audit">All</button>`)}
    </div>`;
}

const auditRow = (a) => `
  <div class="row"><div class="ic">${MI.history}</div>
    <div class="row-txt"><b>${esc(a.action)}${a.target ? ` · <span class="mono" style="display:inline;font-weight:300">${esc(a.target)}</span>` : ''}</b>
      <span>${esc(a.admin_name)}${a.detail ? ` · ${esc(a.detail)}` : ''}</span></div>
    <span class="mini">${mAgo(a.at)}</span></div>`;

/* ═══════════════════════════════════════════════════════════
   PLAYERS
   ═══════════════════════════════════════════════════════════ */
async function pagePlayers() {
  view().innerHTML = `
    ${head('Players', 'Everyone in the city, or search anyone who has banked here by name, ID, identifier or account number.')}
    <div class="m-cols wide-r">
      <div class="panel"><div class="p-body tight" style="gap:10px">
        <div class="searchbox">${MI.search}<input id="mgrPlayerQ" placeholder="Name, server ID, identifier, account…" value="${esc(MG.playerQ)}"></div>
        <div class="m-list m-scroll" id="mgrPlayerList"><div class="mini">Loading…</div></div>
      </div></div>
      <div class="stack" id="mgrPlayerView">${emptyBox('Pick a player', 'Their accounts, cash, cards, loans and bills open here.', MI.users)}</div>
    </div>`;
  const input = document.getElementById('mgrPlayerQ');
  let t = null;
  input.addEventListener('input', () => { clearTimeout(t); t = setTimeout(() => { MG.playerQ = input.value.trim(); listPlayers(); }, 300); });
  await listPlayers();
  if (MG.player) openPlayer(MG.player.identifier);
}

async function listPlayers() {
  const res = await mPost('players', MG.playerQ);
  const box = document.getElementById('mgrPlayerList');
  if (!box) return;
  MG.players = res.ok ? res.rows : [];
  box.innerHTML = MG.players.map(p => `
    <div class="row pick ${MG.player && MG.player.identifier === p.identifier ? 'on' : ''}" data-player="${esc(p.identifier)}">
      <div class="av">${esc(initials(p.name) || '?')}</div>
      <div class="row-txt"><b>${esc(p.name)}</b><span>${p.src ? `ID ${p.src} · ${esc(p.job || '')}` : 'Offline'}</span></div>
      <div class="r-meta"><b class="amount">${p.bank != null ? mm(p.bank) : '—'}</b>${p.src ? `<small>cash ${mm(p.cash)}</small>` : '<small>bank</small>'}</div>
    </div>`).join('') || emptyBox(MG.playerQ ? 'Nobody found' : 'Nobody in the city', MG.playerQ ? 'Try a different spelling, an account number or their identifier.' : 'Search finds offline players too.', MI.users);
}

async function openPlayer(identifier) {
  document.querySelectorAll('#mgrPlayerList .row').forEach(r => r.classList.toggle('on', r.dataset.player === identifier));
  const box = document.getElementById('mgrPlayerView');
  if (!box) return;
  const res = await mPost('player', identifier);
  if (!res.ok) { box.innerHTML = emptyBox('Not found', res.msg || ''); return; }
  const p = MG.player = res.player;

  const accRow = (a) => `
    <div class="row">
      <div class="ic ${a.balance < 0 ? 'out' : ''}">${a.type === 'society' ? MI.bank : MI.card}</div>
      <div class="row-txt"><b>${esc(a.label)} ${a.member ? '<em class="chip dim" style="margin-left:4px;font-style:normal">MEMBER</em>' : ''}</b>
        <span class="mono">${esc(a.account_number)} · ${esc(a.type)}</span></div>
      ${a.frozen ? '<span class="tag hot">Frozen</span>' : ''}
      <span class="amount ${a.balance < 0 ? 'out' : ''}">${mm(a.balance)}</span>
      <div class="acts">
        <button class="btn-ghost" data-mact="adjust" data-id="${a.id}" data-label="${esc(a.account_number)}" data-bal="${a.balance}">${MI.coin}Money</button>
        <button class="btn-ghost" data-mact="history" data-id="${a.id}" data-label="${esc(a.account_number)}">${MI.history}</button>
        <button class="btn-ghost ${a.frozen ? 'on' : ''}" data-mact="freeze" data-id="${a.id}" data-frozen="${a.frozen ? 1 : 0}" title="${a.frozen ? 'Unfreeze' : 'Freeze'}">${MI.lock}</button>
      </div>
    </div>`;

  box.innerHTML = `
    <div class="who-card">
      <div class="av">${esc(initials(p.name) || '?')}</div>
      <div><h2>${esc(p.name)} ${p.src ? `<span class="tag live">Online · ID ${p.src}</span>` : '<span class="tag off">Offline</span>'}</h2>
        <p class="mono">${esc(p.identifier)}${p.job ? ` · ${esc(p.job)}` : ''}</p></div>
      <div class="figs">
        ${p.src ? `<div><span>Carrying</span><b>${mm(p.cash)}</b></div>` : ''}
        <div><span>Credit score</span><b class="teal">${p.credit.score}</b></div>
      </div>
    </div>
    <div class="toolbar">
      ${p.src ? `<button class="btn-ghost" data-mact="wallet" data-mode="add">${MI.plus}Give cash</button>
        <button class="btn-ghost" data-mact="wallet" data-mode="remove">${MI.minus}Take cash</button>
        <button class="btn-ghost" data-mact="gotoPlayer">${MI.go}Go to them</button>` : ''}
      <button class="btn-ghost" data-mact="setCredit">${MI.chart}Set credit score</button>
    </div>
    ${panel('Accounts', `${p.accounts.length} account${p.accounts.length === 1 ? '' : 's'} · credit ${p.credit.band}`,
      `<div class="m-list">${p.accounts.map(accRow).join('') || emptyBox('No accounts', 'They get one the first time they open the bank.')}</div>`)}
    <div class="stack">
      ${panel('Cards', '', `<div class="m-list">${p.cards.map(c => `
        <div class="row"><div class="ic ${c.status !== 'active' ? 'out' : ''}">${MI.card}</div>
          <div class="row-txt"><b>${esc(c.card_type)} <span class="mono" style="display:inline;font-weight:300">${esc(c.card_number)}</span></b>
            <span>${esc(c.account_number)}${c.kind !== 'debit' ? ` · owes ${mm(c.balance)} of ${mm(c.credit_limit)}` : ''}</span></div>
          <span class="tag ${c.status === 'active' ? 'live' : 'hot'}">${esc(c.status)}</span>
          <button class="btn-ghost" data-mact="card" data-id="${c.id}" data-to="${c.status === 'active' ? 'blocked' : 'active'}">${c.status === 'active' ? 'Block' : 'Unblock'}</button>
        </div>`).join('') || emptyBox('No cards', 'Nothing issued.', MI.card)}</div>`)}
      ${panel('Loans', '', `<div class="m-list">${p.loans.map(l => `
        <div class="row"><div class="ic ${l.status === 'defaulted' ? 'out' : ''}">${MI.coin}</div>
          <div class="row-txt"><b>${esc(l.tier)} · ${mm(l.principal)}</b>
            <span>${l.status === 'paid' ? 'Paid off' : `${mm(l.remaining)} left · ${l.missed} missed`}</span></div>
          <span class="tag ${l.status === 'active' ? 'live' : l.status === 'paid' ? 'off' : 'hot'}">${esc(l.status)}</span>
          ${l.status !== 'paid' ? `<div class="acts">${l.missed > 0 ? `<button class="btn-ghost" data-mact="loan" data-id="${l.id}" data-do="missed">Clear missed</button>` : ''}
            <button class="btn-ghost" data-mact="loan" data-id="${l.id}" data-do="forgive">Write off</button></div>` : ''}
        </div>`).join('') || emptyBox('No loans', 'Never borrowed.', MI.coin)}</div>`)}
    </div>
    ${p.bills.length ? panel('Open bills', '', `<div class="m-list">${p.bills.map(b => `
      <div class="row"><div class="ic out">${MI.bill}</div>
        <div class="row-txt"><b>${esc(b.issuer_label)} · ${mm(b.amount)}</b><span>${esc(b.reason)}</span></div>
        <span class="tag ${b.status === 'overdue' ? 'hot' : 'off'}">${esc(b.status)}</span>
        <button class="btn-ghost" data-mact="bill" data-id="${b.id}">Cancel</button></div>`).join('')}</div>`) : ''}
    ${panel('Recent activity', 'Their last 40 moves across every account', txTable(p.tx, true))}`;
}

function txTable(rows, withAccount) {
  if (!rows || !rows.length) return emptyBox('Nothing yet', 'No money has moved.', MI.history);
  return `<table class="m-table"><tr><th>When</th>${withAccount ? '<th>Account</th>' : ''}<th>What</th><th>By</th><th class="r">Amount</th><th class="r">After</th></tr>
    ${rows.map(t => `<tr><td class="mini">${mAgo(t.at)}</td>${withAccount ? `<td class="mono mini">${esc(t.account_number)}</td>` : ''}
      <td><b>${esc(t.label)}</b> <span class="mini">${esc(t.category)}</span></td><td class="mini">${esc(t.actor_name || '')}</td>
      <td class="r ${t.direction === 'in' ? 'm-pos' : 'm-neg'}">${t.direction === 'in' ? '+' : '−'}${mm(t.amount)}</td><td class="r">${mm(t.balance_after)}</td></tr>`).join('')}</table>`;
}

/* ── money modals ── */
function adjustModal(id, label, balance) {
  openModal({
    title: `Money · ${label}`,
    text: `Balance now ${mm(balance)}. Every change is logged with your name on the account and in Staff activity.`,
    body: `
      <div class="seg" data-mseg="mode"><button class="on" data-v="add">Add</button><button data-v="remove">Remove</button><button data-v="set">Set to</button></div>
      <input type="hidden" data-name="mode" value="add">
      <div class="field"><label>Amount</label><input type="number" min="0" data-name="amount" placeholder="0"></div>
      <div class="field"><label>Reason (shown on the account)</label><input data-name="reason" maxlength="60" placeholder="Refund, compensation, correction…"></div>`,
    confirm: 'Apply',
    onConfirm: async (v) => {
      const res = await mPost('adjust', id, v.mode, Number(v.amount), v.reason);
      if (mSay(res)) { closeModal(); refreshPage(); }
    }
  });
}

document.getElementById('veil').addEventListener('click', (e) => {
  const b = e.target.closest('[data-mseg] button');
  if (!b) return;
  const seg = b.parentElement;
  seg.querySelectorAll('button').forEach(x => x.classList.toggle('on', x === b));
  const hidden = document.querySelector(`#veil [data-name="${seg.dataset.mseg}"]`);
  if (hidden) hidden.value = b.dataset.v;
});

async function historyModal(id, label) {
  const res = await mPost('transactions', id);
  openModal({ title: `History · ${label}`, text: 'The last 60 moves on this account.',
    body: `<div class="m-scroll" style="max-height:380px">${txTable(res.rows || [], false)}</div>`, confirm: 'Done', cancel: false,
    onConfirm: () => closeModal() });
  const m = document.querySelector('#veil .modal');
  if (m) m.style.width = '640px';
}

function refreshPage() {
  if (MG.page === 'players' && MG.player) { listPlayers(); openPlayer(MG.player.identifier); }
  else mgrGo(MG.page);
}

/* ═══════════════════════════════════════════════════════════
   SOCIETIES · ALL ACCOUNTS
   ═══════════════════════════════════════════════════════════ */
const accountLine = (a) => `
  <div class="row">
    <div class="ic ${a.balance < 0 ? 'out' : ''}">${a.type === 'society' ? MI.bank : MI.card}</div>
    <div class="row-txt"><b>${esc(a.label)}</b><span class="mono">${esc(a.account_number)} · ${esc(a.type)}${a.owner ? ` · ${esc(a.owner)}` : ''}${a.members != null ? ` · ${a.members} on it` : ''}</span></div>
    ${a.frozen ? '<span class="tag hot">Frozen</span>' : ''}
    <span class="amount ${a.balance < 0 ? 'out' : ''}">${mm(a.balance)}</span>
    <div class="acts">
      ${a.type !== 'society' ? `<button class="btn-ghost" data-owner="${esc(a.owner)}">${MI.me}</button>` : ''}
      <button class="btn-ghost" data-mact="adjust" data-id="${a.id}" data-label="${esc(a.account_number)}" data-bal="${a.balance}">${MI.coin}Money</button>
      <button class="btn-ghost" data-mact="history" data-id="${a.id}" data-label="${esc(a.account_number)}">${MI.history}</button>
      <button class="btn-ghost" data-mact="rename" data-id="${a.id}" data-label="${esc(a.label)}" title="Rename">Aa</button>
      <button class="btn-ghost ${a.frozen ? 'on' : ''}" data-mact="freeze" data-id="${a.id}" data-frozen="${a.frozen ? 1 : 0}">${MI.lock}</button>
    </div>
  </div>`;

async function pageSocieties() {
  loading();
  const res = await mPost('societies');
  if (MG.page !== 'societies') return;
  const rows = res.rows || [];
  const total = rows.reduce((a, r) => a + r.balance, 0);
  view().innerHTML = `
    ${head('Societies', `Every job's account: ${rows.length} accounts holding ${mm(total)}.`)}
    ${panel('Society accounts', 'Top them up, take from them, freeze them or read their history', `<div class="m-list">${rows.map(accountLine).join('') ||
      emptyBox('No society accounts', 'Jobs in Config.Accounts.societyAccess and Config.Bills.issuers get one on start.', MI.bank)}</div>`)}`;
}

async function pageAccounts() {
  view().innerHTML = `
    ${head('All accounts', 'Search every account in the bank by number, name or owner. Largest first.')}
    <div class="searchbox" style="flex:none">${MI.search}<input id="mgrAccQ" placeholder="NZB-…, a label, an identifier or a job" value="${esc(MG.accQ)}"></div>
    <div class="m-list" id="mgrAccList"><div class="mini">Loading…</div></div>`;
  const input = document.getElementById('mgrAccQ');
  let t = null;
  const run = async () => {
    const res = await mPost('accounts', MG.accQ);
    const box = document.getElementById('mgrAccList');
    if (box) box.innerHTML = (res.rows || []).map(accountLine).join('') || emptyBox('Nothing found', 'Try part of the number or a job name.');
  };
  input.addEventListener('input', () => { clearTimeout(t); t = setTimeout(() => { MG.accQ = input.value.trim(); run(); }, 300); });
  run();
}

/* ═══════════════════════════════════════════════════════════
   BRANCHES · MAP · TELLERS · MONEY COUNTER
   ═══════════════════════════════════════════════════════════ */
async function pageBranches() {
  loading();
  const [res, me] = await Promise.all([mPost('branches'), mWorld('here')]);
  if (MG.page !== 'branches') return;
  if (!res.ok) return (view().innerHTML = emptyBox('No answer', res.msg || ''));
  MG.branches = res.data;
  MG.me = me && me.ok ? me.pos : null;
  if (MG.branch != null && !MG.branches.rows[MG.branch - 1]) MG.branch = null;
  document.getElementById('mgrTallyBranches').textContent = MG.branches.rows.length;
  drawBranches();
}

function drawBranches() {
  const b = MG.branches;
  const sel = MG.branch != null ? b.rows[MG.branch - 1] : null;
  view().innerHTML = `
    ${head('Branches & tellers', 'Every branch on the map. Pick one to move its teller, place its money counter or go there; click anywhere else on the map to teleport.',
      `<button class="btn-teal" data-mact="addBranch">+ Branch where I stand</button>
       ${b.edited ? `<button class="btn-line" data-mact="resetBranches">Back to config.lua</button>` : ''}`)}
    <div class="m-cols map">
      <div class="panel"><div class="p-body tight">
        <div class="map-wrap" id="mgrMap">
          <div class="map-in" id="mgrMapIn"><img src="images/map.png" alt="">${b.rows.map(r => pinHtml(r)).join('')}
            ${MG.me ? (() => { const p = toMap(MG.me.x, MG.me.y); return `<div class="pin me" style="left:${p.px / MAP.w * 100}%;top:${p.py / MAP.h * 100}%"><button><i></i></button></div>`; })() : ''}
          </div>
          <div class="map-tools"><button data-map="in">${MI.plus}</button><button data-map="out">${MI.minus}</button><button data-map="fit">${MI.fit}</button></div>
          <div class="map-hint">Scroll to zoom · drag to move · <span style="color:var(--red)">●</span> you</div>
        </div>
      </div></div>
      <div class="stack">${sel ? branchDetail(sel) : branchList()}</div>
    </div>`;
  mapWire();
}

const pinHtml = (r) => {
  const p = toMap(r.x, r.y);
  return `<div class="pin ${MG.branch === r.i ? 'on' : ''}" style="left:${p.px / MAP.w * 100}%;top:${p.py / MAP.h * 100}%">
    <button data-branch="${r.i}"><i><b>${r.i}</b></i><span>${esc(r.label)}</span></button></div>`;
};

function branchList() {
  const rows = MG.branches.rows;
  return panel(`${rows.length} branches`, 'Each one has a teller, a blip and a money counter', `<div class="m-list m-scroll" style="max-height:560px">${rows.map(r => `
    <div class="row pick" data-branch="${r.i}">
      <div class="ic">${MI.pin}</div>
      <div class="row-txt"><b>${r.i} · ${esc(r.label)}</b><span class="mono">${r.x.toFixed(1)}, ${r.y.toFixed(1)}, ${r.z.toFixed(1)} · ${esc(r.ped)}</span></div>
      ${r.counter ? '<span class="chip">COUNTER SET</span>' : ''}
      <button class="btn-ghost" data-mact="gotoBranch" data-i="${r.i}">${MI.go}Go</button>
    </div>`).join('') || emptyBox('No branches', 'Stand where a teller should be and add one.', MI.pin)}</div>`);
}

function branchDetail(r) {
  const c = r.counter || MG.branches.default || {};
  const v = (o) => o ? `${Number(o.x).toFixed(2)}, ${Number(o.y).toFixed(2)}` : '—';
  return `
    ${panel(`${r.i} · ${r.label}`, r.counter ? 'This branch has its own counter layout' : 'Uses the default counter layout',
      `<div class="field row2" style="margin-bottom:10px">
         <div class="field"><label>Name</label><input id="mgrBLabel" value="${esc(r.label)}" maxlength="40"></div>
         <div class="field"><label>Teller model</label><input id="mgrBPed" value="${esc(r.ped)}" maxlength="40"></div>
       </div>
       <div class="kvs">
         <div><span>Teller stands at</span><b class="mono">${r.x.toFixed(2)}, ${r.y.toFixed(2)}, ${r.z.toFixed(2)}</b></div>
         <div><span>Facing</span><b>${Math.round(r.w)}°</b></div>
         <div><span>Money counter (from the teller)</span><b class="mono">${v(c.machine)} · ${Math.round(c.machineHeading || 0)}°</b></div>
         <div><span>Cash spot (from the teller)</span><b class="mono">${v(c.counter)}</b></div>
       </div>`,
      `<button class="btn-ghost" data-mact="branchBack">All branches</button><button class="btn-teal" data-mact="branchSaveInfo" style="height:27px">Save</button>`)}
    ${panel('In the world', 'The tools close this panel while you work and bring it back when you finish', `
      <div class="tool-grid">
        <button class="tool" data-mact="gotoBranch" data-i="${r.i}">${MI.go}<div><b>Go there</b><span>In front of the teller</span></div></button>
        <button class="tool" data-mact="placeTeller" data-i="${r.i}">${MI.move}<div><b>Move teller</b><span>Arrows, Q/E to turn, ENTER</span></div></button>
        <button class="tool" data-mact="tellerHere" data-i="${r.i}">${MI.me}<div><b>Teller to my spot</b><span>Where you stand, facing your way</span></div></button>
        <button class="tool" data-mact="placeCounter" data-i="${r.i}">${MI.machine}<div><b>Place money counter</b><span>Aim with the mouse, scroll to turn, E</span></div></button>
        ${r.counter ? `<button class="tool" data-mact="resetCounter" data-i="${r.i}">${MI.undo}<div><b>Default counter</b><span>Drop this branch's layout</span></div></button>` : ''}
        <button class="tool red" data-mact="deleteBranch" data-i="${r.i}">${MI.trash}<div><b>Remove branch</b><span>Teller, blip and all</span></div></button>
      </div>`)}`;
}

/* ── the map: zoom, drag, click ── */
function mapApply() {
  const inner = document.getElementById('mgrMapIn');
  if (!inner) return;
  const { z, x, y } = MG.map;
  inner.style.transform = `translate(${x}px, ${y}px) scale(${z})`;
  inner.style.setProperty('--pin', (1 / z).toFixed(3));
}

function mapClamp(wrap) {
  const w = wrap.clientWidth, h = wrap.clientHeight, m = MG.map;
  m.x = Math.min(0, Math.max(w - w * m.z, m.x));
  m.y = Math.min(0, Math.max(h - h * m.z, m.y));
}

function mapZoom(wrap, factor, cx, cy) {
  const m = MG.map;
  const z = Math.min(8, Math.max(1, m.z * factor));
  if (cx == null) { cx = wrap.clientWidth / 2; cy = wrap.clientHeight / 2; }
  m.x = cx - (cx - m.x) * (z / m.z);
  m.y = cy - (cy - m.y) * (z / m.z);
  m.z = z;
  mapClamp(wrap);
  mapApply();
}

/** Centre the map on a branch, zoomed in, so the city's cluster can be told apart. */
function mapFocus(r) {
  const wrap = document.getElementById('mgrMap');
  if (!wrap || !r) return;
  const p = toMap(r.x, r.y);
  const m = MG.map;
  m.z = Math.max(m.z, 3);
  m.x = wrap.clientWidth / 2 - (p.px / MAP.w) * wrap.clientWidth * m.z;
  m.y = wrap.clientHeight / 2 - (p.py / MAP.h) * wrap.clientHeight * m.z;
  mapClamp(wrap);
  mapApply();
}

function closeMapPop() { document.querySelectorAll('.map-pop, .pin.drop').forEach(n => n.remove()); }

function mapWire() {
  const wrap = document.getElementById('mgrMap');
  if (!wrap) return;
  mapApply();
  let down = null;

  wrap.addEventListener('wheel', (e) => {
    e.preventDefault();
    const r = wrap.getBoundingClientRect();
    closeMapPop();
    mapZoom(wrap, e.deltaY < 0 ? 1.25 : 0.8, e.clientX - r.left, e.clientY - r.top);
  }, { passive: false });

  wrap.addEventListener('mousedown', (e) => {
    if (e.button !== 0 || e.target.closest('.map-tools, .map-pop, .pin button')) return;
    down = { x: e.clientX, y: e.clientY, mx: MG.map.x, my: MG.map.y, moved: false };
  });
  window.onmousemove = (e) => {
    if (!down) return;
    const dx = e.clientX - down.x, dy = e.clientY - down.y;
    if (Math.abs(dx) + Math.abs(dy) > 4) { down.moved = true; wrap.classList.add('drag'); closeMapPop(); }
    if (!down.moved) return;
    MG.map.x = down.mx + dx; MG.map.y = down.my + dy;
    mapClamp(wrap); mapApply();
  };
  window.onmouseup = (e) => {
    if (!down) return;
    const was = down; down = null;
    wrap.classList.remove('drag');
    if (was.moved || !document.getElementById('mgrMap')) return;
    // a click on the map itself: offer a teleport to that spot
    const r = wrap.getBoundingClientRect();
    const cx = e.clientX - r.left, cy = e.clientY - r.top;
    const px = ((cx - MG.map.x) / MG.map.z) / wrap.clientWidth * MAP.w;
    const py = ((cy - MG.map.y) / MG.map.z) / wrap.clientHeight * MAP.h;
    const w = toWorld(px, py);
    closeMapPop();
    const inner = document.getElementById('mgrMapIn');
    inner.insertAdjacentHTML('beforeend', `<div class="pin drop" style="left:${px / MAP.w * 100}%;top:${py / MAP.h * 100}%"><button><i></i></button></div>`);
    wrap.insertAdjacentHTML('beforeend', `<div class="map-pop" style="left:${cx}px;top:${cy}px">
      <small class="mono">${w.x.toFixed(0)}, ${w.y.toFixed(0)}</small>
      <button class="btn-teal" style="height:28px" data-mact="teleport" data-x="${w.x.toFixed(1)}" data-y="${w.y.toFixed(1)}">Teleport here</button></div>`);
  };

  wrap.querySelector('.map-tools').addEventListener('click', (e) => {
    const b = e.target.closest('[data-map]');
    if (!b) return;
    if (b.dataset.map === 'in') mapZoom(wrap, 1.5);
    else if (b.dataset.map === 'out') mapZoom(wrap, 1 / 1.5);
    else { MG.map = { z: 1, x: 0, y: 0 }; mapApply(); }
  });
}

/* ═══════════════════════════════════════════════════════════
   MARKET
   ═══════════════════════════════════════════════════════════ */
async function pageMarket() {
  loading();
  const res = await mPost('market');
  if (MG.page !== 'market') return;
  const rows = res.rows || [];
  view().innerHTML = `
    ${head('Market', 'The prices in the Investments tab. Set one by hand for an event or a crash; it stays between its floor and ceiling and carries on moving from there.')}
    ${panel('Assets', `${rows.length} listed`, rows.length ? `<table class="m-table">
      <tr><th>Asset</th><th class="r">Price</th><th class="r">Today</th><th class="r">Floor · ceiling</th><th class="r">Holders</th><th class="r">Set price</th></tr>
      ${rows.map(a => {
        const chg = a.open ? (a.price - a.open) / a.open * 100 : 0;
        return `<tr><td><b>${esc(a.id)}</b> <span class="mini">${esc(a.label)} · ${esc(a.kind)}</span></td>
          <td class="r"><b>${mm(a.price)}</b></td><td class="r ${chg >= 0 ? 'm-pos' : 'm-neg'}">${chg >= 0 ? '+' : ''}${chg.toFixed(2)}%</td>
          <td class="r mini">${mm(a.floor)} · ${mm(a.ceiling)}</td><td class="r">${a.holders}</td>
          <td class="r"><input type="number" step="0.01" id="mkt_${esc(a.id)}" placeholder="${Number(a.price).toFixed(2)}">
            <button class="btn-ghost" style="display:inline-flex;margin-left:6px" data-mact="setPrice" data-id="${esc(a.id)}">Set</button></td></tr>`;
      }).join('')}</table>` : emptyBox('No assets', 'Add them to Config.Market.assets.', MI.chart))}`;
}

/* ═══════════════════════════════════════════════════════════
   SETTINGS
   ═══════════════════════════════════════════════════════════ */
async function mPageSettings() {
  loading();
  const res = await mPost('settings');
  if (MG.page !== 'settings') return;
  if (!res.ok) return (view().innerHTML = emptyBox('No answer', res.msg || ''));
  MG.settings = res.data;
  drawSettings();
}

function changedCount(group) {
  const s = MG.settings;
  return (group ? group.items : s.groups.flatMap(g => g.items)).filter(it => s.overridden[it.p]).length;
}

function drawSettings() {
  const s = MG.settings;
  document.getElementById('mgrTallyChanged').textContent = changedCount();
  const q = MG.setQ.toLowerCase();
  const groups = q ? s.groups.map(g => ({ ...g, items: g.items.filter(it =>
    (it.l + ' ' + (it.h || '') + ' ' + it.p).toLowerCase().includes(q)) })).filter(g => g.items.length) : s.groups;
  const current = q ? null : (s.groups.find(g => g.id === MG.setGroup) || s.groups[0]);

  view().innerHTML = `
    ${head('Settings', 'Everything in config.lua, changed here and live for every player. config.lua stays the starting point: Reset brings its value back.',
      `<button class="btn-ghost" data-mact="export">${MI.export}Copy to config.lua</button>
       <button class="btn-line" data-mact="resetAll" style="height:27px">Reset all</button>`)}
    <div class="searchbox" style="flex:none">${MI.search}<input id="mgrSetQ" placeholder="Find a setting: fee, ATM, teller, interest…" value="${esc(MG.setQ)}"></div>
    <div class="set-wrap">
      <div class="set-groups">${s.groups.map(g => `
        <button data-sgroup="${g.id}" class="${!q && current && current.id === g.id ? 'on' : ''}">${esc(g.label)}
          ${changedCount(g) ? `<span class="tally">${changedCount(g)}</span>` : ''}</button>`).join('')}</div>
      <div class="stack">${(q ? groups : [current]).map(g => panel(g.label, q ? '' : `${g.items.length} settings`,
        `<div style="margin:-13px -15px -15px">${g.items.map(settingRow).join('')}</div>`)).join('') ||
        emptyBox('No setting matches', 'Try another word.', MI.search)}</div>
    </div>`;

  const input = document.getElementById('mgrSetQ');
  let t = null;
  input.addEventListener('input', () => {
    clearTimeout(t);
    t = setTimeout(() => {
      MG.setQ = input.value.trim();
      drawSettings();
      const again = document.getElementById('mgrSetQ');
      again.focus(); again.setSelectionRange(again.value.length, again.value.length);
    }, 250);
  });
}

function settingRow(it) {
  const s = MG.settings;
  const v = s.values[it.p];
  const changed = s.overridden[it.p];
  let ctl = '';
  if (it.t === 'bool') {
    ctl = `<button class="sw ${v ? 'on' : ''}" data-set="${esc(it.p)}" data-kind="bool"><i></i></button>`;
  } else if (it.t === 'number') {
    const shown = it.pct ? +(Number(v || 0) * 100).toFixed(4) : v;
    ctl = `<input type="number" data-set="${esc(it.p)}" data-kind="number" value="${esc(shown)}"
      ${it.min != null ? `min="${it.min}"` : ''} ${it.max != null ? `max="${it.max}"` : ''} step="${it.step || (it.pct ? 0.1 : 1)}">
      ${it.pct ? '<span class="unit">%</span>' : ''}`;
  } else if (it.t === 'select') {
    ctl = `<select data-set="${esc(it.p)}" data-kind="select">${(it.o || []).map(o => `<option ${o === v ? 'selected' : ''}>${esc(o)}</option>`).join('')}</select>`;
  } else if (it.t === 'color') {
    ctl = `<span class="hex mono">${esc(v)}</span><input type="color" data-set="${esc(it.p)}" data-kind="color" value="${esc(v || '#000000')}">`;
  } else {
    ctl = `<input type="text" data-set="${esc(it.p)}" data-kind="text" value="${esc(it.s ? (v ? '••••••••' : '') : v)}"
      ${it.s ? 'placeholder="Paste a new one to change it"' : ''} ${it.max ? `maxlength="${it.max}"` : ''}>`;
  }
  return `
    <div class="set-row ${changed ? 'changed' : ''}" data-row="${esc(it.p)}">
      <div class="lbl"><b>${esc(it.l)} ${it.r ? '<span class="chip amber">RESTART</span>' : ''}</b>
        ${it.h ? `<span>${esc(it.h)}</span>` : ''}<div class="path mono">Config.${esc(it.p)}</div></div>
      <div class="ctl">${ctl}</div>
      <div class="state">${changed ? `<button class="dotreset" data-reset="${esc(it.p)}" title="Back to config.lua">Reset</button>` : ''}</div>
    </div>`;
}

async function saveSetting(path, value, reset) {
  const row = document.querySelector(`.set-row[data-row="${CSS.escape(path)}"]`);
  if (row) row.classList.add('saving');
  const res = await mPost('setting', path, value, !!reset);
  if (row) row.classList.remove('saving');
  if (!res.ok) { mSay(res); return drawSettings(); }
  MG.settings.values[path] = res.value;
  MG.settings.overridden[path] = res.overridden;
  if (res.restart) notify('Banking Manager', res.msg, 'inform');
  const it = MG.settings.groups.flatMap(g => g.items).find(x => x.p === path);
  if (row && it) {
    row.outerHTML = settingRow(it);
    document.getElementById('mgrTallyChanged').textContent = changedCount();
    document.querySelectorAll('.set-groups [data-sgroup]').forEach(b => {
      const g = MG.settings.groups.find(x => x.id === b.dataset.sgroup);
      const n = changedCount(g);
      b.innerHTML = `${esc(g.label)} ${n ? `<span class="tally">${n}</span>` : ''}`;
    });
  }
}

/* settings controls: switches save on click, the rest when they change */
document.getElementById('mgrView').addEventListener('change', (e) => {
  const el = e.target.closest('[data-set]');
  if (!el) return;
  const it = MG.settings && MG.settings.groups.flatMap(g => g.items).find(x => x.p === el.dataset.set);
  if (!it) return;
  let v = el.value;
  if (it.t === 'number') {
    v = Number(v);
    if (!Number.isFinite(v)) return drawSettings();
    if (it.pct) v = v / 100;
  }
  if (it.s && v === '••••••••') return;
  saveSetting(it.p, v);
});
document.getElementById('mgrView').addEventListener('input', (e) => {
  if (e.target.type === 'color') {
    const hex = e.target.parentElement.querySelector('.hex');
    if (hex) hex.textContent = e.target.value;
  }
});
document.getElementById('mgrView').addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && e.target.matches('[data-set]')) e.target.blur();
  if (e.key === 'Enter' && e.target.matches('.m-table input[id^="mkt_"]')) {
    const b = e.target.parentElement.querySelector('[data-mact="setPrice"]');
    if (b) b.click();
  }
});

/* ═══════════════════════════════════════════════════════════
   STAFF ACTIVITY
   ═══════════════════════════════════════════════════════════ */
async function pageAudit() {
  loading();
  const res = await mPost('audit', MG.auditPage);
  if (MG.page !== 'audit') return;
  const rows = res.rows || [];
  view().innerHTML = `
    ${head('Staff activity', 'Every change made in the Banking Manager, newest first. Also sent to the Discord log when Config.Logs is on.')}
    ${panel('Log', `Page ${res.page || 1} of ${res.pages || 1}`, rows.length ? `<table class="m-table">
      <tr><th>When</th><th>Staff</th><th>Did</th><th>To</th><th>Detail</th></tr>
      ${rows.map(a => `<tr><td class="mini">${mAgo(a.at)}</td><td><b>${esc(a.admin_name)}</b></td><td>${esc(a.action)}</td>
        <td class="mono mini">${esc(a.target || '')}</td><td class="mini">${esc(a.detail || '')}</td></tr>`).join('')}</table>
      <div class="pager">${Array.from({ length: Math.min(res.pages || 1, 12) }, (_, i) =>
        `<button class="${i + 1 === res.page ? 'on' : ''}" data-apage="${i + 1}">${i + 1}</button>`).join('')}</div>`
      : emptyBox('Nothing yet', 'Changes made here show up in this list.', MI.history))}`;
}

/* ═══════════════════════════════════════════════════════════
   ACTIONS
   ═══════════════════════════════════════════════════════════ */
document.getElementById('mgrView').addEventListener('click', async (e) => {
  const sw = e.target.closest('.sw[data-set]');
  if (sw) return saveSetting(sw.dataset.set, !sw.classList.contains('on'));
  const reset = e.target.closest('[data-reset]');
  if (reset) return saveSetting(reset.dataset.reset, null, true);
  const grp = e.target.closest('[data-sgroup]');
  if (grp) { MG.setGroup = grp.dataset.sgroup; MG.setQ = ''; return drawSettings(); }
  const ap = e.target.closest('[data-apage]');
  if (ap) { MG.auditPage = Number(ap.dataset.apage); return pageAudit(); }
  const pg = e.target.closest('[data-mpage]');
  if (pg) return mgrGo(pg.dataset.mpage);

  const pl = e.target.closest('[data-player]');
  if (pl) return openPlayer(pl.dataset.player);
  const owner = e.target.closest('[data-owner]');
  if (owner && owner.dataset.owner && !e.target.closest('[data-mact]')) {
    MG.playerQ = ''; MG.player = { identifier: owner.dataset.owner };
    return mgrGo('players');
  }

  const br = e.target.closest('[data-branch]');
  if (br && !e.target.closest('[data-mact]')) {
    MG.branch = Number(br.dataset.branch);
    closeMapPop();
    drawBranches();
    mapFocus(MG.branches.rows[MG.branch - 1]);
    return;
  }

  const a = e.target.closest('[data-mact]');
  if (!a) return;
  const d = a.dataset;
  const p = MG.player;

  switch (d.mact) {
    case 'refresh': return mgrGo(MG.page);
    case 'adjust': return adjustModal(Number(d.id), d.label, Number(d.bal));
    case 'history': return historyModal(Number(d.id), d.label);
    case 'freeze': {
      const res = await mPost('freeze', Number(d.id), d.frozen !== '1');
      if (mSay(res)) refreshPage();
      return;
    }
    case 'rename':
      return openModal({ title: 'Rename account', body: `<div class="field"><label>Name</label><input data-name="label" maxlength="40" value="${esc(d.label)}"></div>`,
        confirm: 'Rename', onConfirm: async (v) => { if (mSay(await mPost('rename', Number(d.id), v.label))) { closeModal(); refreshPage(); } } });
    case 'wallet':
      return openModal({ title: d.mode === 'add' ? `Give cash · ${p.name}` : `Take cash · ${p.name}`,
        text: `Carrying ${mm(p.cash)}. ${d.mode === 'add' ? 'It goes into their pockets' : 'It comes out of their pockets'} (banknotes when physical cash is on).`,
        body: `<div class="field"><label>Amount</label><input type="number" min="1" data-name="amount"></div>`,
        confirm: d.mode === 'add' ? 'Give' : 'Take', danger: d.mode !== 'add',
        onConfirm: async (v) => { if (mSay(await mPost('wallet', p.src, d.mode, Number(v.amount)))) { closeModal(); refreshPage(); } } });
    case 'setCredit':
      return openModal({ title: `Credit score · ${p.name}`, text: `Now ${p.credit.score} (${p.credit.band}). Runs from ${p.credit.min} to ${p.credit.max}; the change shows in their credit history.`,
        body: `<div class="field"><label>New score</label><input type="number" data-name="score" min="${p.credit.min}" max="${p.credit.max}" value="${p.credit.score}"></div>`,
        confirm: 'Set', onConfirm: async (v) => { if (mSay(await mPost('credit', p.identifier, Number(v.score)))) { closeModal(); refreshPage(); } } });
    case 'card': { if (mSay(await mPost('card', Number(d.id), d.to))) refreshPage(); return; }
    case 'loan':
      return openModal({ title: d.do === 'forgive' ? 'Write this loan off?' : 'Clear missed payments?',
        text: d.do === 'forgive' ? 'What is left is forgiven and the loan closes as paid. No money moves.' : 'The missed count goes back to zero, so it no longer heads for a default.',
        danger: d.do === 'forgive', confirm: d.do === 'forgive' ? 'Write off' : 'Clear',
        onConfirm: async () => { if (mSay(await mPost('loan', Number(d.id), d.do))) { closeModal(); refreshPage(); } } });
    case 'bill':
      return openModal({ title: 'Cancel this bill?', text: 'It is marked void. Nobody is paid and the player no longer owes it.', danger: true, confirm: 'Cancel bill', cancel: 'Keep it',
        onConfirm: async () => { if (mSay(await mPost('bill', Number(d.id)))) { closeModal(); refreshPage(); } } });
    case 'gotoPlayer': {
      const res = await mWorld('player', { src: p.src });
      if (!res.ok) mSay(res);
      return;
    }
    case 'setPrice': {
      const input = document.getElementById(`mkt_${d.id}`);
      const v = Number(input && input.value);
      if (!input || !input.value || !Number.isFinite(v) || v <= 0) return notify('Banking Manager', 'Enter a price above zero.', 'error');
      if (mSay(await mPost('marketSet', d.id, v))) pageMarket();
      return;
    }

    /* branches */
    case 'branchBack': MG.branch = null; return drawBranches();
    case 'teleport': return mWorld('teleport', { x: Number(d.x), y: Number(d.y) });
    case 'gotoBranch': return mWorld('branch', { index: Number(d.i) });
    case 'placeTeller': return mWorld('placeTeller', { index: Number(d.i) });
    case 'placeCounter': return mWorld('placeCounter', { index: Number(d.i) });
    case 'branchSaveInfo': {
      const r = MG.branches.rows[MG.branch - 1];
      const label = document.getElementById('mgrBLabel').value, ped = document.getElementById('mgrBPed').value;
      const res = await mPost('branchSave', r.i, { label, ped, x: r.x, y: r.y, z: r.z, w: r.w });
      if (mSay(res, 'Not saved.') && res.data) { MG.branches = res.data; notify('Banking Manager', 'Branch saved for everyone.', 'success'); drawBranches(); }
      return;
    }
    case 'tellerHere': {
      const r = MG.branches.rows[Number(d.i) - 1];
      const me = await mWorld('here');
      if (!me.ok) return;
      return openModal({ title: `Teller to your spot · ${r.label}`,
        text: 'The teller stands exactly where you are and faces the way you face, so stand behind the counter looking at the customers.',
        confirm: 'Move teller', onConfirm: async () => {
          const res = await mPost('branchSave', r.i, { label: r.label, ped: r.ped, x: me.pos.x, y: me.pos.y, z: me.pos.z, w: me.pos.w });
          if (mSay(res, 'Not saved.') && res.data) { closeModal(); MG.branches = res.data; notify('Banking Manager', 'Teller moved for everyone.', 'success'); drawBranches(); }
        } });
    }
    case 'addBranch':
      return openModal({ title: 'New branch here',
        text: 'Stand where the teller should be, facing the customers. You can fine-tune it with the move tool straight after.',
        body: `<div class="field"><label>Name</label><input data-name="label" maxlength="40" value="Fleeca Bank"></div>
               <div class="field"><label>Teller model</label><input data-name="ped" maxlength="40" value="ig_bankman"></div>`,
        confirm: 'Add branch', onConfirm: async (v) => {
          const me = await mWorld('here');
          if (!me.ok) return;
          const res = await mPost('branchSave', 0, { label: v.label, ped: v.ped, x: me.pos.x, y: me.pos.y, z: me.pos.z, w: me.pos.w });
          if (mSay(res, 'Not saved.') && res.data) {
            closeModal(); MG.branches = res.data; MG.branch = res.data.rows.length;
            notify('Banking Manager', 'Branch added. Its teller appears for everyone now.', 'success'); drawBranches();
          }
        } });
    case 'resetCounter':
      return openModal({ title: 'Use the default counter?', text: 'This branch goes back to the money counter layout in Config.Teller.', confirm: 'Reset',
        onConfirm: async () => { const res = await mPost('counterSave', Number(d.i), { reset: true }); if (mSay(res) && res.data) { closeModal(); MG.branches = res.data; drawBranches(); } } });
    case 'deleteBranch': {
      const r = MG.branches.rows[Number(d.i) - 1];
      return openModal({ title: `Remove ${r.label}?`, text: 'Its teller, blip and counter go for every player. Back to config.lua brings the original list back.',
        danger: true, confirm: 'Remove', onConfirm: async () => {
          const res = await mPost('branchDelete', r.i);
          if (mSay(res) && res.data) { closeModal(); MG.branches = res.data; MG.branch = null; drawBranches(); }
        } });
    }
    case 'resetBranches':
      return openModal({ title: 'Back to config.lua?', text: 'Every branch, teller position and counter layout made here is dropped and Config.Banks comes back.',
        danger: true, confirm: 'Reset branches', onConfirm: async () => {
          const res = await mPost('branchesReset');
          if (mSay(res) && res.data) { closeModal(); MG.branches = res.data; MG.branch = null; drawBranches(); }
        } });

    /* settings */
    case 'export': {
      const res = await mPost('export');
      openModal({ title: 'Copy to config.lua', text: 'Everything changed here, as config.lua lines. Paste them in to make the changes permanent for a fresh install.',
        body: `<textarea class="export" readonly id="mgrExport">${esc(res.text || '')}</textarea>`, confirm: 'Copy', cancel: 'Close',
        onConfirm: () => {
          const ta = document.getElementById('mgrExport');
          ta.select(); let ok = false;
          try { ok = document.execCommand('copy'); } catch (err) { ok = false; }
          notify('Banking Manager', ok ? 'Copied. Paste it at the bottom of config.lua.' : 'Select the text and copy it by hand.', ok ? 'success' : 'inform');
        } });
      const m = document.querySelector('#veil .modal');
      if (m) m.style.width = '620px';
      return;
    }
    case 'resetAll':
      return openModal({ title: 'Reset every setting?', text: 'Every setting changed here goes back to config.lua. Branches and counters are kept; they have their own reset.',
        danger: true, confirm: 'Reset all', onConfirm: async () => {
          const res = await mPost('resetSettings');
          if (mSay(res) && res.data) { closeModal(); MG.settings = res.data; drawSettings(); }
        } });
  }
});

/* ═══════════════════════════════════════════════════════════
   PLACEMENT HUD
   ═══════════════════════════════════════════════════════════ */
function drawHud(d) {
  const hud = document.getElementById('mgrHud');
  if (!d) { document.body.classList.remove('hud-up'); hud.innerHTML = ''; return; }
  document.body.classList.add('hud-up');
  const rows = d.rows || [];
  hud.innerHTML = `
    <div class="h-top"><div class="mark"></div><div><b>${esc(d.title)}</b><small>BANKING MANAGER · PLACING</small></div></div>
    ${rows.length ? `<div class="h-vals">${rows.map(r => `<div>${esc(r[0])}<b class="mono">${esc(r[1])}</b></div>`).join('')}</div>` : ''}
    <div class="h-keys">${(d.keys || []).map(k => `<span class="key">${esc(k[0])}</span><span>${esc(k[1])}</span>`).join('')}</div>`;
}

const MPAGES = {
  overview: pageOverview, players: pagePlayers, societies: pageSocieties, accounts: pageAccounts,
  branches: pageBranches, market: pageMarket, settings: mPageSettings, audit: pageAudit,
};
