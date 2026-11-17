/* ═══════════════════════════════════════════════════════════
   NAYZEEE BANKING — BANKING MANAGER (/bankingmanager)
   Uses app.js's helpers: esc, initials, notify, openModal,
   closeModal, applyTheme. Everything the server does is behind
   a staff check of its own; this page only draws it.

   Every page is built to fit the window: the page never
   scrolls, a long list scrolls inside its own panel.
   ═══════════════════════════════════════════════════════════ */
const MG = {
  boot: null, page: 'overview', range: 7, overview: null,
  playerQ: '', players: [], player: null, ptab: 'accounts',
  accQ: '', accKind: 'all', branches: null, branch: null, me: null,
  settings: null, setGroup: 'general', setQ: '',
  auditPage: 1, map: { z: 1, x: 0, y: 0 }
};

/* the dark map (web/images/map.png) and where the world sits on it */
const MAP = { w: 695, h: 1045, sx: 0.09266, ox: 305.9, sy: 0.08779, oy: 698.9 };
const toMap = (x, y) => ({ px: MAP.ox + MAP.sx * x, py: MAP.oy - MAP.sy * y });
const toWorld = (px, py) => ({ x: (px - MAP.ox) / MAP.sx, y: (MAP.oy - py) / MAP.sy });

const svg = (d) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
const MI = {
  bank:    svg('<path d="M3 10 12 4l9 6M5 10v9h14v-9M9 19v-5h6v5"/>'),
  users:   svg('<circle cx="9" cy="8" r="3.2"/><path d="M2.8 19.5a6.2 6.2 0 0 1 12.4 0M16.5 5.4a3.2 3.2 0 0 1 0 5.9M18 19.5a6.4 6.4 0 0 0-2-4.4"/>'),
  coin:    svg('<circle cx="12" cy="12" r="8.5"/><path d="M14.5 9.2a3 3 0 0 0-5.2 2c0 2.4 5 2 5 4.2a3 3 0 0 1-5.2 1.5M12 6.5v11"/>'),
  card:    svg('<rect x="2.5" y="5" width="19" height="14" rx="2.5"/><path d="M2.5 10h19M6 15h3"/>'),
  bill:    svg('<path d="M6 3h12v18l-3-2-3 2-3-2-3 2V3z"/><path d="M9.5 8h5M9.5 12h5"/>'),
  pin:     svg('<path d="M12 21s-6.5-5.6-6.5-11a6.5 6.5 0 0 1 13 0C18.5 15.4 12 21 12 21z"/><circle cx="12" cy="10" r="2.4"/>'),
  search:  svg('<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/>'),
  go:      svg('<path d="M5 12h14M13 6l6 6-6 6"/>'),
  move:    svg('<path d="M12 3v18M3 12h18M12 3l-3 3M12 3l3 3M12 21l-3-3M12 21l3-3M3 12l3-3M3 12l3 3M21 12l-3-3M21 12l-3 3"/>'),
  me:      svg('<circle cx="12" cy="7.5" r="3.5"/><path d="M5 20.5a7 7 0 0 1 14 0"/>'),
  machine: svg('<rect x="4" y="8" width="16" height="11" rx="2"/><path d="M8 8V5h8v3M8 13h8M10 16h4"/>'),
  undo:    svg('<path d="M4 9h11a5 5 0 0 1 0 10H8"/><path d="M8 5 4 9l4 4"/>'),
  trash:   svg('<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>'),
  plus:    svg('<path d="M12 5v14M5 12h14"/>'),
  minus:   svg('<path d="M5 12h14"/>'),
  fit:     svg('<path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/>'),
  lock:    svg('<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>'),
  history: svg('<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>'),
  export:  svg('<path d="M12 4v11M7.5 10.5 12 15l4.5-4.5M5 19h14"/>'),
  chart:   svg('<path d="M3 17.5 9 11l4 4 8-8.5"/><path d="M15 6.5h6v6"/>'),
  pulse:   svg('<path d="M3 12h4l2.5-6 5 12 2.5-6h4"/>'),
  refresh: svg('<path d="M20 11a8 8 0 0 0-14.5-4.5M4 4v4h4M4 13a8 8 0 0 0 14.5 4.5M20 20v-4h-4"/>'),
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
const mint = (n) => Math.round(Number(n) || 0).toLocaleString('en-US');
const mAgo = (t) => {
  if (!t) return '—';
  const s = Math.max(0, Math.floor(Date.now() / 1000 - t));
  if (s < 60) return 'just now';
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return `${Math.floor(s / 86400)}d ago`;
};
const TYPE_COLOUR = { personal: 'var(--teal)', savings: '#0fd4c4', shared: '#9ea5aa', society: '#e5a50a' };
const TYPES = ['personal', 'savings', 'shared', 'society'];
const mCap = (s) => String(s || '').charAt(0).toUpperCase() + String(s || '').slice(1);
const mView = () => document.getElementById('mgrView');

/* ── building blocks ──────────────────────────────────────── */
const mHead = (title, sub, acts) => `
  <div class="mhead"><div><h1>${esc(title)}</h1><p>${esc(sub)}</p></div>${acts ? `<div class="acts">${acts}</div>` : ''}</div>`;
const mPanel = (title, sub, body, opts = {}) => `
  <div class="panel ${opts.cls || ''}">
    <div class="p-head"><div><h2>${esc(title)}</h2>${sub ? `<p>${esc(sub)}</p>` : ''}</div>${opts.acts ? `<div class="acts">${opts.acts}</div>` : ''}</div>
    <div class="pb ${opts.flat ? 'flat' : ''}">${body}</div>
    ${opts.foot ? `<div class="pfoot">${opts.foot}</div>` : ''}
  </div>`;
const emptyBox = (title, text, icon) => `<div class="empty">${icon || MI.search}<b>${esc(title)}</b><span>${esc(text)}</span></div>`;
const kpi = (icon, label, value, note, opts = {}) => `
  <div class="kpi ${opts.red ? 'red' : ''}"><div class="tile ${opts.red ? 'red' : ''}">${icon}</div>
    <div style="min-width:0"><span>${esc(label)}</span>
      <b ${opts.count != null ? `data-count="${opts.count}" data-fmt="${opts.fmt || 'int'}"` : ''}>${value}</b>
      ${note ? `<i>${note}</i>` : ''}</div></div>`;
const skeleton = (n) => Array.from({ length: n || 6 }, () => '<div class="skel-row"></div>').join('');
const loadingPage = (title, sub) => {
  mView().innerHTML = `<div class="page">${mHead(title, sub)}<div class="kpis">${'<div class="skel-row" style="height:62px"></div>'.repeat(4)}</div>
    <div class="panel fill"><div class="pb">${skeleton(7)}</div></div></div>`;
};

/** Figures count up from zero when a page opens. */
function countUp(root) {
  (root || mView()).querySelectorAll('[data-count]').forEach(el => {
    const to = Number(el.dataset.count) || 0, fmt = el.dataset.fmt;
    const t0 = performance.now(), dur = 750;
    const draw = (v) => { el.textContent = fmt === 'money' ? mshort(v) : fmt === 'full' ? mm(v) : mint(v); };
    const step = (t) => {
      const k = Math.min(1, (t - t0) / dur);
      draw(to * (1 - Math.pow(1 - k, 3)));
      if (k < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  });
}

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
  (MPAGES[page] || MPAGES.overview)();
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

window.addEventListener('resize', () => { if (MG.page === 'branches') fitMap(); });

/* ═══════════════════════════════════════════════════════════
   OVERVIEW
   ═══════════════════════════════════════════════════════════ */
async function pageOverview() {
  if (!MG.overview) loadingPage('Overview', 'The whole bank at a glance.');
  const res = await mPost('overview', MG.range);
  if (MG.page !== 'overview') return;
  if (!res.ok) return (mView().innerHTML = `<div class="page">${emptyBox('No answer', res.msg || 'The server did not answer.')}</div>`);
  const d = MG.overview = res.data;
  document.getElementById('mgrTallyOnline').textContent = d.online;
  document.getElementById('mgrTallyBranches').textContent = d.branches;

  const sum = (t) => (d.byType[t] && d.byType[t].sum) || 0;
  const num = (t) => (d.byType[t] && d.byType[t].n) || 0;
  const count = TYPES.reduce((a, t) => a + num(t), 0);
  const positive = TYPES.reduce((a, t) => a + Math.max(0, sum(t)), 0) || 1;
  const topMax = Math.max(1, ...d.top.map(a => a.balance));

  mView().innerHTML = `<div class="page">
    ${mHead('Overview', 'What the bank holds, what it is owed, how money is moving and what staff have done.',
      `<button class="btn-ghost" data-mact="refresh">${MI.refresh}Refresh</button>`)}
    <div class="kpis">
      ${kpi(MI.bank, 'Held by the bank', mshort(d.total), `${mint(count)} accounts · <em>+${d.health.fresh}</em> this week`, { count: d.total, fmt: 'money' })}
      ${kpi(MI.users, 'Players in the city', d.online, `${d.branches} branches · ${mint(d.today.accounts)} accounts used today`, { count: d.online })}
      ${kpi(MI.coin, 'Owed on loans', mshort(d.loans.owed), `${d.loans.n} open · <em>${d.loans.bad}</em> defaulted`, { count: d.loans.owed, fmt: 'money', red: d.loans.bad > 0 })}
      ${kpi(MI.bill, 'Unpaid bills', mshort(d.bills.sum), `${d.bills.n} open · <em>${d.bills.late}</em> overdue`, { count: d.bills.sum, fmt: 'money', red: d.bills.late > 0 })}
    </div>
    <div class="grid fill" style="grid-template-columns:1.55fr 1fr;grid-template-rows:minmax(0,1.25fr) minmax(0,1fr)">
      ${mPanel('Cash flow', 'Money in and out by day, without transfers between players. Hover a day.',
        `<div id="mgrFlow" style="display:flex;flex-direction:column;flex:1;min-height:0">${flowHtml(d.days)}</div>`,
        { flat: true, acts: `<div class="seg" id="mgrRange">${[7, 14, 30].map(r => `<button class="${MG.range === r ? 'on' : ''}" data-range="${r}">${r}D</button>`).join('')}</div>` })}
      ${mPanel('Bank health', `${mint(count)} accounts across four kinds`, `
        <div class="mix">${TYPES.map((t, i) => `<i style="width:${Math.max(0, sum(t)) / positive * 100}%;background:${TYPE_COLOUR[t]};animation-delay:${i * 90}ms"></i>`).join('')}</div>
        <div class="mix-key">${TYPES.map(t => `<div><i style="background:${TYPE_COLOUR[t]}"></i>${mCap(t)}<small>${num(t)}</small><b>${mshort(sum(t))}</b></div>`).join('')}</div>
        <div class="sec-label" style="margin-top:6px">Right now</div>
        <div class="kvs">
          <div><span>Frozen accounts</span><b class="${d.health.frozen ? 'red' : ''}">${d.health.frozen}</b></div>
          <div><span>Overdrawn</span><b class="${d.health.overdrawn ? 'amber' : ''}">${d.health.overdrawn} · ${mshort(d.health.below)}</b></div>
          <div><span>Moves today</span><b class="teal">${mint(d.today.n)}</b></div>
          <div><span>Cards in use</span><b>${mint(d.cards.live)}</b></div>
          <div><span>Blocked or stolen</span><b class="${d.cards.stopped ? 'red' : ''}">${mint(d.cards.stopped)}</b></div>
          <div><span>Owed on credit cards</span><b>${mshort(d.cards.owed)}</b></div>
          <div><span>New this week</span><b class="teal">+${mint(d.health.fresh)}</b></div>
          <div><span>Loans running</span><b>${mint(d.loans.n - d.loans.bad)}</b></div>
          <div><span>Bills overdue</span><b class="${d.bills.late ? 'red' : ''}">${mint(d.bills.late)}</b></div>
        </div>`, { flat: true })}
      ${mPanel('Largest accounts', 'Click one to open its owner', `<div class="mlist">${d.top.map((a, i) => `
        <div class="row pick" data-owner="${esc(a.type === 'society' ? '' : a.owner)}">
          <span class="rank">${i + 1}</span>
          <div class="ic">${a.type === 'society' ? MI.bank : MI.card}</div>
          <div class="row-txt"><b>${esc(a.label)}</b><span class="mono">${esc(a.account_number)} · ${esc(a.type)}</span></div>
          ${a.frozen ? '<span class="tag hot">Frozen</span>' : ''}
          <div class="bar-mini"><i style="width:${Math.max(4, a.balance / topMax * 100)}%;animation-delay:${i * 60}ms"></i></div>
          <span class="amount ${a.balance < 0 ? 'out' : ''}">${mshort(a.balance)}</span>
        </div>`).join('') || emptyBox('No accounts yet', 'They appear once players have banked.')}</div>`)}
      ${mPanel('Staff activity', 'The latest changes made in this panel', `<div class="mlist">${d.audits.map(auditRow).join('') ||
        emptyBox('Nothing yet', 'Every change made here is written down, with who made it.', MI.history)}</div>`,
        { acts: `<button class="btn-ghost" data-mpage="audit">All</button>` })}
    </div></div>`;
  countUp();
  wireFlow();
}

const auditRow = (a) => `
  <div class="row"><div class="ic">${MI.history}</div>
    <div class="row-txt"><b>${esc(a.action)}${a.target ? ` · <span class="mono" style="display:inline;font-weight:300;font-size:10.5px">${esc(a.target)}</span>` : ''}</b>
      <span>${esc(a.admin_name)}${a.detail ? ` · ${esc(a.detail)}` : ''}</span></div>
    <span class="mini" style="flex:none">${mAgo(a.at)}</span></div>`;

/* ── the cash-flow chart ── */
function niceMax(v) {
  if (v <= 0) return 1000;
  const p = Math.pow(10, Math.floor(Math.log10(v)));
  const f = v / p;
  return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 2.5 ? 2.5 : f <= 5 ? 5 : 10) * p;
}

function flowHtml(days) {
  const top = niceMax(Math.max(1, ...days.map(x => Math.max(x.inn, x.out))));
  const n = days.length;
  const gap = n <= 7 ? 12 : n <= 14 ? 6 : 3;
  const label = (s, i) => {
    const dt = new Date(s + 'T12:00:00');
    if (n <= 7) return dt.toLocaleDateString('en-GB', { weekday: 'short' });
    if (n <= 14) return (n - 1 - i) % 2 === 0 ? String(dt.getDate()) : '';
    return (n - 1 - i) % 5 === 0 ? dt.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }) : '';
  };
  const totIn = days.reduce((a, x) => a + x.inn, 0), totOut = days.reduce((a, x) => a + x.out, 0);
  const moves = days.reduce((a, x) => a + x.n, 0);
  const net = totIn - totOut;
  return `
    <div class="cf" style="--gap:${gap}px">
      <div class="cf-y">${[0, 1, 2, 3, 4].map(k => `<span style="bottom:${k * 25}%">${k ? mshort(top * k / 4) : '0'}</span>`).join('')}</div>
      <div class="cf-plot">
        ${[1, 2, 3, 4].map(k => `<div class="cf-grid" style="bottom:${k * 25}%;animation-delay:${k * 60}ms"></div>`).join('')}
        <div class="cf-cols">${days.map((x, i) => `
          <div class="cf-col" data-day="${i}">
            <i class="cf-bar in" style="height:${x.inn / top * 100}%;--i:${i}"></i>
            <i class="cf-bar out" style="height:${x.out / top * 100}%;--i:${i}"></i>
          </div>`).join('')}</div>
        <div class="cf-tip" id="mgrTip"></div>
      </div>
      <div class="cf-x">${days.map((x, i) => `<span>${label(x.d, i)}</span>`).join('')}</div>
    </div>
    <div class="cf-sum">
      <div><span><i style="background:var(--teal)"></i>Money in</span><b data-count="${totIn}" data-fmt="money">${mshort(totIn)}</b></div>
      <div><span><i style="background:var(--red)"></i>Money out</span><b data-count="${totOut}" data-fmt="money">${mshort(totOut)}</b></div>
      <div><span><i style="background:${net >= 0 ? 'var(--teal)' : 'var(--red)'}"></i>Net</span><b class="${net >= 0 ? 'm-pos' : 'm-neg'}">${net >= 0 ? '+' : ''}${mshort(net)}</b></div>
      <div><span><i style="background:var(--ink-3)"></i>Moves</span><b data-count="${moves}">${mint(moves)}</b></div>
    </div>`;
}

function wireFlow() {
  const box = document.getElementById('mgrFlow');
  if (!box) return;
  const tip = document.getElementById('mgrTip');
  const plot = box.querySelector('.cf-plot');
  box.querySelectorAll('.cf-col').forEach(col => {
    col.addEventListener('mouseenter', () => {
      const x = MG.overview.days[Number(col.dataset.day)];
      const dt = new Date(x.d + 'T12:00:00').toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' });
      const net = x.inn - x.out;
      tip.innerHTML = `<b>${esc(dt)}</b>
        <div>In<em class="m-pos">${mm(x.inn)}</em></div><div>Out<em class="m-neg">${mm(x.out)}</em></div>
        <div>Net<em class="${net >= 0 ? 'm-pos' : 'm-neg'}">${net >= 0 ? '+' : ''}${mm(net)}</em></div><div>Moves<em>${mint(x.n)}</em></div>`;
      const pr = plot.getBoundingClientRect(), cr = col.getBoundingClientRect();
      const tallest = Math.max(...[...col.querySelectorAll('.cf-bar')].map(b => b.getBoundingClientRect().height));
      const left = Math.max(80, Math.min(pr.width - 80, cr.left - pr.left + cr.width / 2));
      tip.style.left = `${left}px`;
      tip.style.top = `${Math.max(96, pr.height - tallest)}px`;
      tip.classList.add('up');
    });
    col.addEventListener('mouseleave', () => tip.classList.remove('up'));
  });
  countUp(box);
}

async function setRange(r) {
  MG.range = r;
  document.querySelectorAll('#mgrRange button').forEach(b => b.classList.toggle('on', Number(b.dataset.range) === r));
  const res = await mPost('overview', r);
  if (!res.ok || MG.page !== 'overview') return;
  MG.overview = res.data;
  const box = document.getElementById('mgrFlow');
  if (box) { box.innerHTML = flowHtml(res.data.days); wireFlow(); }
}

/* ═══════════════════════════════════════════════════════════
   PLAYERS
   ═══════════════════════════════════════════════════════════ */
async function pagePlayers() {
  mView().innerHTML = `<div class="page">
    ${mHead('Players', 'Everyone in the city, or anyone who has banked here: search by name, server ID, identifier or account number.')}
    <div class="grid fill" style="grid-template-columns:310px 1fr">
      <div class="panel">
        <div style="padding:11px 12px 4px;flex:none"><div class="searchbox">${MI.search}<input id="mgrPlayerQ" placeholder="Name, ID, identifier, account…" value="${esc(MG.playerQ)}"></div></div>
        <div class="pb" id="mgrPlayerList">${skeleton(8)}</div>
        <div class="pfoot" id="mgrPlayerFoot">Loading…</div>
      </div>
      <div style="display:flex;flex-direction:column;gap:10px;min-height:0" id="mgrPlayerView">
        <div class="panel fill"><div class="pb" style="justify-content:center">${emptyBox('Pick a player', 'Their accounts, cash, cards, loans, bills and activity open here.', MI.users)}</div></div>
      </div>
    </div></div>`;
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
  const online = MG.players.filter(p => p.src).length;
  box.innerHTML = MG.players.length ? `<div class="mlist">${MG.players.map(p => `
    <div class="row pick ${MG.player && MG.player.identifier === p.identifier ? 'on' : ''}" data-player="${esc(p.identifier)}">
      <div class="av">${esc(initials(p.name) || '?')}</div>
      <div class="row-txt"><b>${esc(p.name)}</b><span>${p.src ? `ID ${p.src} · ${esc(p.job || '')}` : 'Offline'}</span></div>
      <div class="r-meta"><b class="amount">${p.bank != null ? mshort(p.bank) : '—'}</b><small>${p.src ? `cash ${mshort(p.cash)}` : 'bank'}</small></div>
    </div>`).join('')}</div>` : emptyBox(MG.playerQ ? 'Nobody found' : 'Nobody in the city',
      MG.playerQ ? 'Try another spelling, an account number or their identifier.' : 'Search finds offline players too.', MI.users);
  const foot = document.getElementById('mgrPlayerFoot');
  if (foot) foot.innerHTML = MG.playerQ ? `<b>${MG.players.length}</b> found · ${online} online` : `<b>${online}</b> in the city`;
}

async function openPlayer(identifier) {
  document.querySelectorAll('#mgrPlayerList .row').forEach(r => r.classList.toggle('on', r.dataset.player === identifier));
  const box = document.getElementById('mgrPlayerView');
  if (!box) return;
  const res = await mPost('player', identifier);
  if (!res.ok) { box.innerHTML = `<div class="panel fill"><div class="pb">${emptyBox('Not found', res.msg || '')}</div></div>`; return; }
  const p = MG.player = res.player;
  const own = p.accounts.filter(a => !a.member);
  const held = own.reduce((a, x) => a + x.balance, 0);
  const activeLoans = p.loans.filter(l => l.status !== 'paid');

  box.innerHTML = `
    <div class="who-card">
      <div class="av">${esc(initials(p.name) || '?')}</div>
      <div style="min-width:0"><h2>${esc(p.name)} ${p.src ? `<span class="tag live">Online · ID ${p.src}</span>` : '<span class="tag off">Offline</span>'}</h2>
        <p class="mono">${esc(p.identifier)}${p.job ? ` · ${esc(p.job)}` : ''}</p></div>
      <div class="figs">
        ${p.src ? `<div><span>Carrying</span><b>${mm(p.cash)}</b></div>` : ''}
        <div><span>In the bank</span><b>${mm(held)}</b></div>
        <div><span>Owes on loans</span><b>${mm(activeLoans.reduce((a, l) => a + l.remaining, 0))}</b></div>
        <div><span>Credit</span><b class="teal">${p.credit.score}<small>${esc(p.credit.band)}</small></b></div>
      </div>
    </div>
    <div class="toolbar">
      ${p.src ? `<button class="btn-ghost" data-mact="wallet" data-mode="add">${MI.plus}Give cash</button>
        <button class="btn-ghost" data-mact="wallet" data-mode="remove">${MI.minus}Take cash</button>
        <button class="btn-ghost" data-mact="gotoPlayer">${MI.go}Go to them</button>` : ''}
      <button class="btn-ghost" data-mact="setCredit">${MI.chart}Set credit score</button>
      ${own[0] ? `<button class="btn-ghost" data-mact="adjust" data-id="${own[0].id}" data-label="${esc(own[0].account_number)}" data-bal="${own[0].balance}">${MI.coin}Money on ${esc(own[0].type)}</button>` : ''}
    </div>
    <div class="panel fill">
      <div class="tabs">${[
        ['accounts', 'Accounts', p.accounts.length], ['cards', 'Cards', p.cards.length], ['loans', 'Loans', activeLoans.length],
        ['bills', 'Bills', p.bills.length], ['activity', 'Activity', p.tx.length]
      ].map(([k, l, n]) => `<button class="${MG.ptab === k ? 'on' : ''}" data-ptab="${k}">${l}<span class="tally">${n}</span></button>`).join('')}</div>
      <div class="pb" id="mgrPTab">${playerTab(p)}</div>
    </div>`;
}

function playerTab(p) {
  if (MG.ptab === 'cards') return p.cards.length ? `<div class="mlist">${p.cards.map(c => `
    <div class="row"><div class="ic ${c.status !== 'active' ? 'out' : ''}">${MI.card}</div>
      <div class="row-txt"><b>${esc(mCap(c.card_type))} <span class="mono" style="display:inline;font-weight:300">${esc(c.card_number)}</span></b>
        <span>${esc(c.holder || '')} · ${esc(c.account_number)}${c.kind !== 'debit' ? ` · owes ${mm(c.balance)} of ${mm(c.credit_limit)}` : ''}</span></div>
      ${c.kind !== 'debit' ? `<div class="bar-mini" title="Used of the line"><i style="width:${Math.min(100, c.credit_limit ? c.balance / c.credit_limit * 100 : 0)}%"></i></div>` : ''}
      <span class="tag ${c.status === 'active' ? 'live' : 'hot'}">${esc(c.status)}</span>
      <button class="btn-ghost" data-mact="card" data-id="${c.id}" data-to="${c.status === 'active' ? 'blocked' : 'active'}">${c.status === 'active' ? 'Block' : 'Unblock'}</button>
    </div>`).join('')}</div>` : emptyBox('No cards', 'Nothing issued.', MI.card);

  if (MG.ptab === 'loans') return p.loans.length ? `<div class="mlist">${p.loans.map(l => `
    <div class="row"><div class="ic ${l.status === 'defaulted' ? 'out' : ''}">${MI.coin}</div>
      <div class="row-txt"><b>${esc(mCap(l.tier))} · ${mm(l.principal)}</b>
        <span>${l.status === 'paid' ? 'Paid off' : `${mm(l.remaining)} left · ${mm(l.payment)} an instalment · ${l.missed} missed`}</span></div>
      ${l.status !== 'paid' ? `<div class="bar-mini" title="Paid off so far"><i style="width:${Math.max(3, 100 - l.remaining / Math.max(1, l.principal) * 100)}%"></i></div>` : ''}
      <span class="tag ${l.status === 'active' ? 'live' : l.status === 'paid' ? 'off' : 'hot'}">${esc(l.status)}</span>
      ${l.status !== 'paid' ? `<div class="acts">${l.missed > 0 ? `<button class="btn-ghost" data-mact="loan" data-id="${l.id}" data-do="missed">Clear missed</button>` : ''}
        <button class="btn-ghost" data-mact="loan" data-id="${l.id}" data-do="forgive">Write off</button></div>` : ''}
    </div>`).join('')}</div>` : emptyBox('No loans', 'Never borrowed.', MI.coin);

  if (MG.ptab === 'bills') return p.bills.length ? `<div class="mlist">${p.bills.map(b => `
    <div class="row"><div class="ic out">${MI.bill}</div>
      <div class="row-txt"><b>${esc(b.issuer_label)} · ${mm(b.amount)}</b><span>${esc(b.reason)}</span></div>
      <span class="tag ${b.status === 'overdue' ? 'hot' : 'off'}">${esc(b.status)}</span>
      <button class="btn-ghost" data-mact="bill" data-id="${b.id}">Cancel</button></div>`).join('')}</div>`
    : emptyBox('No open bills', 'Nothing owed to anyone.', MI.bill);

  if (MG.ptab === 'activity') return txTable(p.tx, true);

  return p.accounts.length ? `<div class="mlist">${p.accounts.map(a => `
    <div class="row">
      <div class="ic ${a.balance < 0 ? 'out' : ''}">${a.type === 'society' ? MI.bank : MI.card}</div>
      <div class="row-txt"><b>${esc(a.label)} ${a.member ? '<em class="chip dim" style="margin-left:4px">MEMBER</em>' : ''}</b>
        <span class="mono">${esc(a.account_number)} · ${esc(a.type)}</span></div>
      ${a.frozen ? '<span class="tag hot">Frozen</span>' : ''}
      <span class="amount ${a.balance < 0 ? 'out' : ''}">${mm(a.balance)}</span>
      <div class="acts">
        <button class="btn-ghost" data-mact="adjust" data-id="${a.id}" data-label="${esc(a.account_number)}" data-bal="${a.balance}">${MI.coin}Money</button>
        <button class="btn-ghost" data-mact="history" data-id="${a.id}" data-label="${esc(a.account_number)}" title="History">${MI.history}</button>
        <button class="btn-ghost" data-mact="rename" data-id="${a.id}" data-label="${esc(a.label)}" title="Rename">Aa</button>
        <button class="btn-ghost ${a.frozen ? 'on' : ''}" data-mact="freeze" data-id="${a.id}" data-frozen="${a.frozen ? 1 : 0}" title="${a.frozen ? 'Unfreeze' : 'Freeze'}">${MI.lock}</button>
      </div>
    </div>`).join('')}</div>` : emptyBox('No accounts', 'They get one the first time they open the bank.');
}

function txTable(rows, withAccount) {
  if (!rows || !rows.length) return emptyBox('Nothing yet', 'No money has moved.', MI.history);
  return `<table class="m-table"><tr><th>When</th>${withAccount ? '<th>Account</th>' : ''}<th>What</th><th>By</th><th class="r">Amount</th><th class="r">After</th></tr>
    ${rows.map(t => `<tr><td class="mini" style="white-space:nowrap">${mAgo(t.at)}</td>${withAccount ? `<td class="mono mini">${esc(t.account_number)}</td>` : ''}
      <td><b>${esc(t.label)}</b> <span class="mini">${esc(t.category)}</span></td><td class="mini">${esc(t.actor_name || '')}</td>
      <td class="r ${t.direction === 'in' ? 'm-pos' : 'm-neg'}" style="white-space:nowrap">${t.direction === 'in' ? '+' : '−'}${mm(t.amount)}</td>
      <td class="r" style="white-space:nowrap">${mm(t.balance_after)}</td></tr>`).join('')}</table>`;
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
    body: `<div class="pb" style="max-height:380px;padding:0">${txTable(res.rows || [], false)}</div>`, confirm: 'Done', cancel: false,
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
const accountLine = (a, i, max) => `
  <div class="row">
    ${i != null ? `<span class="rank">${i + 1}</span>` : ''}
    <div class="ic ${a.balance < 0 ? 'out' : ''}">${a.type === 'society' ? MI.bank : MI.card}</div>
    <div class="row-txt"><b>${esc(a.label)}</b><span class="mono">${esc(a.account_number)} · ${esc(a.type)}${a.owner ? ` · ${esc(a.owner)}` : ''}${a.members != null ? ` · ${a.members} on it` : ''}</span></div>
    ${a.frozen ? '<span class="tag hot">Frozen</span>' : ''}
    ${max ? `<div class="bar-mini"><i style="width:${Math.max(3, Math.max(0, a.balance) / max * 100)}%;animation-delay:${Math.min(i || 0, 12) * 40}ms"></i></div>` : ''}
    <span class="amount ${a.balance < 0 ? 'out' : ''}" style="min-width:86px;text-align:right">${mm(a.balance)}</span>
    <div class="acts">
      ${a.type !== 'society' && a.owner ? `<button class="btn-ghost" data-owner="${esc(a.owner)}" title="Open the owner">${MI.me}</button>` : ''}
      <button class="btn-ghost" data-mact="adjust" data-id="${a.id}" data-label="${esc(a.account_number)}" data-bal="${a.balance}">${MI.coin}Money</button>
      <button class="btn-ghost" data-mact="history" data-id="${a.id}" data-label="${esc(a.account_number)}" title="History">${MI.history}</button>
      <button class="btn-ghost" data-mact="rename" data-id="${a.id}" data-label="${esc(a.label)}" title="Rename">Aa</button>
      <button class="btn-ghost ${a.frozen ? 'on' : ''}" data-mact="freeze" data-id="${a.id}" data-frozen="${a.frozen ? 1 : 0}" title="${a.frozen ? 'Unfreeze' : 'Freeze'}">${MI.lock}</button>
    </div>
  </div>`;

async function pageSocieties() {
  loadingPage('Societies', 'Every job’s account.');
  const res = await mPost('societies');
  if (MG.page !== 'societies') return;
  const rows = (res.rows || []).slice().sort((a, b) => b.balance - a.balance);
  const total = rows.reduce((a, r) => a + r.balance, 0);
  const max = Math.max(1, ...rows.map(r => r.balance));
  const frozen = rows.filter(r => r.frozen).length;
  mView().innerHTML = `<div class="page">
    ${mHead('Societies', 'Every job’s account, largest first. Top them up, take from them, freeze, rename or read their history.')}
    <div class="kpis">
      ${kpi(MI.bank, 'Held by societies', mshort(total), `across ${rows.length} jobs`, { count: total, fmt: 'money' })}
      ${kpi(MI.chart, 'Largest', rows[0] ? esc(rows[0].label) : '—', rows[0] ? `${mm(rows[0].balance)} · ${Math.round(rows[0].balance / Math.max(1, total) * 100)}% of it` : '')}
      ${kpi(MI.users, 'People on them', mint(rows.reduce((a, r) => a + (r.members || 0), 0)), 'members with access', {})}
      ${kpi(MI.lock, 'Frozen', frozen, frozen ? 'cannot pay or be paid' : 'none frozen', { red: frozen > 0 })}
    </div>
    ${mPanel('Society accounts', `${rows.length} accounts`, rows.length ? `<div class="mlist">${rows.map((r, i) => accountLine(r, i, max)).join('')}</div>`
      : emptyBox('No society accounts', 'Jobs in Config.Accounts.societyAccess and Config.Bills.issuers get one on start.', MI.bank), { cls: 'fill' })}
  </div>`;
  countUp();
}

async function pageAccounts() {
  mView().innerHTML = `<div class="page">
    ${mHead('All accounts', 'Every account in the bank, largest first. Search by number, name, owner or job.')}
    <div style="display:flex;gap:10px;align-items:center;flex:none">
      <div class="searchbox">${MI.search}<input id="mgrAccQ" placeholder="NZB-…, a label, an identifier or a job" value="${esc(MG.accQ)}"></div>
      <div class="filters" id="mgrAccKinds"></div>
    </div>
    <div class="panel fill"><div class="pb" id="mgrAccList">${skeleton(9)}</div><div class="pfoot" id="mgrAccFoot">Loading…</div></div>
  </div>`;
  const input = document.getElementById('mgrAccQ');
  let t = null;
  input.addEventListener('input', () => { clearTimeout(t); t = setTimeout(() => { MG.accQ = input.value.trim(); listAccounts(); }, 300); });
  listAccounts();
}

async function listAccounts() {
  const res = await mPost('accounts', MG.accQ, MG.accKind);
  const box = document.getElementById('mgrAccList');
  if (!box) return;
  const rows = res.rows || [];
  const counts = res.counts || {};
  const all = TYPES.reduce((a, t) => a + (counts[t] || 0), 0);
  document.getElementById('mgrAccKinds').innerHTML = [['all', 'All', all], ...TYPES.map(t => [t, mCap(t), counts[t] || 0])]
    .map(([k, l, n]) => `<button class="${MG.accKind === k ? 'on' : ''}" data-kind="${k}">${l}<small>${mint(n)}</small></button>`).join('');
  const max = Math.max(1, ...rows.map(r => r.balance));
  box.innerHTML = rows.length ? `<div class="mlist">${rows.map((r, i) => accountLine(r, i, max)).join('')}</div>` : emptyBox('Nothing found', 'Try part of the number or a job name.');
  document.getElementById('mgrAccFoot').innerHTML = `Showing <b>${rows.length}</b> of ${mint(MG.accKind === 'all' ? all : counts[MG.accKind] || 0)}
    <span class="right">In view: <b>${mm(rows.reduce((a, r) => a + r.balance, 0))}</b></span>`;
}

/* ═══════════════════════════════════════════════════════════
   BRANCHES · MAP · TELLERS · MONEY COUNTER
   ═══════════════════════════════════════════════════════════ */
async function pageBranches() {
  if (!MG.branches) loadingPage('Branches & tellers', 'Every branch on the map.');
  const [res, me] = await Promise.all([mPost('branches'), mWorld('here')]);
  if (MG.page !== 'branches') return;
  if (!res.ok) return (mView().innerHTML = `<div class="page">${emptyBox('No answer', res.msg || '')}</div>`);
  MG.branches = res.data;
  MG.me = me && me.ok ? me.pos : null;
  if (MG.branch != null && !MG.branches.rows[MG.branch - 1]) MG.branch = null;
  document.getElementById('mgrTallyBranches').textContent = MG.branches.rows.length;
  drawBranches();
}

const distTo = (r) => MG.me ? Math.hypot(r.x - MG.me.x, r.y - MG.me.y) : null;
const fmtDist = (m) => m == null ? '—' : m >= 1000 ? `${(m / 1000).toFixed(1)} km` : `${Math.round(m)} m`;

function drawBranches() {
  const b = MG.branches;
  const sel = MG.branch != null ? b.rows[MG.branch - 1] : null;
  const custom = b.rows.filter(r => r.counter).length;
  mView().innerHTML = `<div class="page">
    ${mHead('Branches & tellers', 'Pick a branch to move its teller, place its money counter or go there. Click anywhere else on the map to teleport.',
      `<button class="btn-teal" data-mact="addBranch">+ Branch where I stand</button>
       ${b.edited ? `<button class="btn-line" data-mact="resetBranches">Back to config.lua</button>` : ''}`)}
    <div class="grid fill" style="grid-template-columns:auto 1fr">
      <div class="panel map-panel"><div class="pb flat">
        <div class="map-wrap" id="mgrMap">
          <div class="map-in" id="mgrMapIn"><img src="images/map.png" alt="">${b.rows.map((r, i) => pinHtml(r, i)).join('')}
            ${MG.me ? (() => { const p = toMap(MG.me.x, MG.me.y); return `<div class="pin me" style="left:${p.px / MAP.w * 100}%;top:${p.py / MAP.h * 100}%"><button><i></i></button></div>`; })() : ''}
          </div>
          <div class="map-count"><em>${b.rows.length}</em> branches</div>
          <div class="map-tools"><button data-map="in" title="Zoom in">${MI.plus}</button><button data-map="out" title="Zoom out">${MI.minus}</button>
            ${MG.me ? `<button data-map="me" title="Where I am">${MI.me}</button>` : ''}<button data-map="fit" title="Whole map">${MI.fit}</button></div>
          <div class="map-hint">Scroll to zoom · drag to move · <span style="color:var(--red)">●</span> you</div>
        </div>
      </div></div>
      <div style="display:flex;flex-direction:column;gap:12px;min-height:0">${sel ? branchDetail(sel) : branchList(custom)}</div>
    </div></div>`;
  fitMap();
  mapWire();
  countUp();
}

const pinHtml = (r, i) => {
  const p = toMap(r.x, r.y);
  return `<div class="pin ${MG.branch === r.i ? 'on' : ''}" style="left:${p.px / MAP.w * 100}%;top:${p.py / MAP.h * 100}%;--i:${i || 0}">
    <button data-branch="${r.i}"><i><b>${r.i}</b></i><span>${esc(r.label)}</span></button></div>`;
};

function branchList(custom) {
  const rows = MG.branches.rows;
  const near = MG.me ? rows.slice().sort((a, b) => distTo(a) - distTo(b))[0] : null;
  return `
    <div class="kvs" style="flex:none">
      <div><span>Branches · ${MG.branches.edited ? 'edited in this panel' : 'from config.lua'}</span><b class="teal">${rows.length}</b></div>
      <div><span>Own counter layout</span><b>${custom} <small class="mini">of ${rows.length}</small></b></div>
      <div><span>Nearest to you</span><b>${near ? `#${near.i} ${esc(near.label)} · ${fmtDist(distTo(near))}` : '—'}</b></div>
    </div>
    ${mPanel('All branches', 'Each one has a teller, a blip and a money counter', `<div class="mlist">${rows.map(r => `
      <div class="row pick" data-branch="${r.i}">
        <div class="ic">${MI.pin}</div>
        <div class="row-txt"><b>${r.i} · ${esc(r.label)}</b><span class="mono">${r.x.toFixed(1)}, ${r.y.toFixed(1)}, ${r.z.toFixed(1)} · ${esc(r.ped)}</span></div>
        ${r.counter ? '<em class="chip">OWN COUNTER</em>' : ''}
        <span class="mini" style="min-width:56px;text-align:right">${fmtDist(distTo(r))}</span>
        <button class="btn-ghost" data-mact="gotoBranch" data-i="${r.i}">${MI.go}Go</button>
      </div>`).join('') || emptyBox('No branches', 'Stand where a teller should be and add one.', MI.pin)}</div>`, { cls: 'fill' })}`;
}

function branchDetail(r) {
  const c = r.counter || MG.branches.default || {};
  const v = (o) => o ? `${Number(o.x).toFixed(2)}, ${Number(o.y).toFixed(2)}` : '—';
  return `
    ${mPanel(`${r.i} · ${r.label}`, r.counter ? 'This branch has its own counter layout' : 'Uses the default counter layout from Config.Teller', `
       <div class="field row2">
         <div class="field"><label>Name</label><input id="mgrBLabel" value="${esc(r.label)}" maxlength="40"></div>
         <div class="field"><label>Teller model</label><input id="mgrBPed" value="${esc(r.ped)}" maxlength="40"></div>
       </div>
       <div class="kvs" style="margin-top:4px">
         <div><span>Teller stands at</span><b class="mono">${r.x.toFixed(1)}, ${r.y.toFixed(1)}, ${r.z.toFixed(1)}</b></div>
         <div><span>Facing</span><b>${Math.round(r.w)}°</b></div>
         <div><span>From you</span><b class="teal">${fmtDist(distTo(r))}</b></div>
         <div><span>Money counter (from teller)</span><b class="mono">${v(c.machine)}</b></div>
         <div><span>Machine turned</span><b>${Math.round(c.machineHeading || 0)}°</b></div>
         <div><span>Cash spot (from teller)</span><b class="mono">${v(c.counter)}</b></div>
       </div>`,
      { flat: true, acts: `<button class="btn-ghost" data-mact="branchBack">All branches</button><button class="btn-teal" data-mact="branchSaveInfo" style="height:25px">Save</button>` })}
    ${mPanel('In the world', 'The tools close this panel while you work and bring it back when you finish', `
      <div class="tool-grid">
        <button class="tool" data-mact="gotoBranch" data-i="${r.i}">${MI.go}<div><b>Go there</b><span>In front of the teller</span></div></button>
        <button class="tool" data-mact="placeTeller" data-i="${r.i}">${MI.move}<div><b>Move teller</b><span>Arrows, Q/E to turn, ENTER</span></div></button>
        <button class="tool" data-mact="tellerHere" data-i="${r.i}">${MI.me}<div><b>Teller to my spot</b><span>Where you stand, facing your way</span></div></button>
        <button class="tool" data-mact="placeCounter" data-i="${r.i}">${MI.machine}<div><b>Place money counter</b><span>Aim with the mouse, scroll to turn, E</span></div></button>
        ${r.counter ? `<button class="tool" data-mact="resetCounter" data-i="${r.i}">${MI.undo}<div><b>Default counter</b><span>Drop this branch's layout</span></div></button>` : ''}
        <button class="tool red" data-mact="deleteBranch" data-i="${r.i}">${MI.trash}<div><b>Remove branch</b><span>Teller, blip and all</span></div></button>
      </div>`, { flat: true })}`;
}

/** The map as large as its panel allows, kept to the image's shape. */
function fitMap() {
  const wrap = document.getElementById('mgrMap');
  if (!wrap) return;
  const body = wrap.parentElement;
  const h = Math.max(200, body.clientHeight - 20);
  const maxW = Math.max(260, mView().clientWidth * 0.46);
  const w = Math.min(maxW, h * MAP.w / MAP.h);
  wrap.style.width = `${Math.floor(w)}px`;
  wrap.style.height = `${Math.floor(w * MAP.h / MAP.w)}px`;
  mapClamp(wrap);
  mapApply(true);
}

/* ── the map: zoom, drag, click ── */
function mapApply(now) {
  const inner = document.getElementById('mgrMapIn');
  if (!inner) return;
  const { z, x, y } = MG.map;
  inner.classList.toggle('now', !!now);
  inner.style.transform = `translate(${x}px, ${y}px) scale(${z})`;
  inner.style.setProperty('--pin', (1 / z).toFixed(3));
}

function mapClamp(wrap) {
  const w = wrap.clientWidth, h = wrap.clientHeight, m = MG.map;
  m.x = Math.min(0, Math.max(w - w * m.z, m.x));
  m.y = Math.min(0, Math.max(h - h * m.z, m.y));
}

function mapZoom(wrap, factor, cx, cy, now) {
  const m = MG.map;
  const z = Math.min(8, Math.max(1, m.z * factor));
  if (cx == null) { cx = wrap.clientWidth / 2; cy = wrap.clientHeight / 2; }
  m.x = cx - (cx - m.x) * (z / m.z);
  m.y = cy - (cy - m.y) * (z / m.z);
  m.z = z;
  mapClamp(wrap);
  mapApply(now);
}

/** Centre the map on a point, zoomed in, so the city's cluster can be told apart. */
function mapFocus(x, y, zoom) {
  const wrap = document.getElementById('mgrMap');
  if (!wrap) return;
  const p = toMap(x, y);
  const m = MG.map;
  m.z = Math.max(m.z, zoom || 3);
  m.x = wrap.clientWidth / 2 - (p.px / MAP.w) * wrap.clientWidth * m.z;
  m.y = wrap.clientHeight / 2 - (p.py / MAP.h) * wrap.clientHeight * m.z;
  mapClamp(wrap);
  mapApply();
}

function closeMapPop() { document.querySelectorAll('.map-pop, .pin.drop').forEach(n => n.remove()); }

function mapWire() {
  const wrap = document.getElementById('mgrMap');
  if (!wrap) return;
  let down = null;

  wrap.addEventListener('wheel', (e) => {
    e.preventDefault();
    const r = wrap.getBoundingClientRect();
    closeMapPop();
    mapZoom(wrap, e.deltaY < 0 ? 1.25 : 0.8, e.clientX - r.left, e.clientY - r.top, true);
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
    mapClamp(wrap); mapApply(true);
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
    document.getElementById('mgrMapIn').insertAdjacentHTML('beforeend',
      `<div class="pin drop" style="left:${px / MAP.w * 100}%;top:${py / MAP.h * 100}%"><button><i></i></button></div>`);
    wrap.insertAdjacentHTML('beforeend', `<div class="map-pop" style="left:${Math.max(80, Math.min(wrap.clientWidth - 80, cx))}px;top:${Math.max(80, cy)}px">
      <small class="mono">${w.x.toFixed(0)}, ${w.y.toFixed(0)}</small>
      <button class="btn-teal" style="height:27px" data-mact="teleport" data-x="${w.x.toFixed(1)}" data-y="${w.y.toFixed(1)}">Teleport here</button></div>`);
  };

  wrap.querySelector('.map-tools').addEventListener('click', (e) => {
    const b = e.target.closest('[data-map]');
    if (!b) return;
    closeMapPop();
    if (b.dataset.map === 'in') mapZoom(wrap, 1.5);
    else if (b.dataset.map === 'out') mapZoom(wrap, 1 / 1.5);
    else if (b.dataset.map === 'me' && MG.me) mapFocus(MG.me.x, MG.me.y, 3.5);
    else { MG.map = { z: 1, x: 0, y: 0 }; mapApply(); }
  });
}

/* ═══════════════════════════════════════════════════════════
   MARKET
   ═══════════════════════════════════════════════════════════ */
let sparkId = 0;
function mSpark(hist, up) {
  const pts = (hist && hist.length > 1) ? hist.map(Number) : [0, 0];
  const W = 120, H = 30;
  const lo = Math.min(...pts), hi = Math.max(...pts), span = hi - lo || 1;
  const xy = pts.map((v, i) => [i / (pts.length - 1) * W, H - 2 - (v - lo) / span * (H - 4)]);
  const line = xy.map((p, i) => `${i ? 'L' : 'M'}${p[0].toFixed(1)} ${p[1].toFixed(1)}`).join(' ');
  const hex = up ? '#08afa2' : '#e5484d';
  const id = `mspark${++sparkId}`;
  return `<svg class="spark" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
    <defs><linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${hex}" stop-opacity=".28"/><stop offset="1" stop-color="${hex}" stop-opacity="0"/></linearGradient></defs>
    <path class="area" d="${line} L${W} ${H} L0 ${H} Z" fill="url(#${id})"/>
    <path class="line" d="${line}" stroke="${hex}"/></svg>`;
}

async function pageMarket() {
  loadingPage('Market', 'The prices in the Investments tab.');
  const res = await mPost('market');
  if (MG.page !== 'market') return;
  const rows = res.rows || [];
  const invested = rows.reduce((a, r) => a + (r.invested || 0), 0);
  const holders = rows.reduce((a, r) => a + (r.holders || 0), 0);
  const chg = (a) => a.open ? (a.price - a.open) / a.open * 100 : 0;
  const mover = rows.slice().sort((a, b) => Math.abs(chg(b)) - Math.abs(chg(a)))[0];
  const risk = (v) => { const n = v < 0.025 ? 1 : v < 0.04 ? 2 : 3; return `<span class="risk" title="Risk">${[1, 2, 3].map(k => `<i class="${k <= n ? 'on' : ''}"></i>`).join('')}</span>`; };
  mView().innerHTML = `<div class="page">
    ${mHead('Market', 'The prices in the Investments tab. Set one by hand for an event or a crash; it stays between its floor and ceiling and carries on moving from there.')}
    <div class="kpis">
      ${kpi(MI.chart, 'Assets listed', rows.length, 'from Config.Market.assets', { count: rows.length })}
      ${kpi(MI.coin, 'Invested by players', mshort(invested), 'at today’s prices', { count: invested, fmt: 'money' })}
      ${kpi(MI.users, 'Positions held', mint(holders), 'player and asset pairs', { count: holders })}
      ${kpi(MI.pulse, 'Biggest move', mover ? esc(mover.id) : '—', mover ? `<em>${chg(mover) >= 0 ? '+' : ''}${chg(mover).toFixed(2)}%</em> since the hour opened` : '', { red: !!mover && chg(mover) < 0 })}
    </div>
    ${mPanel('Assets', 'The line is the day so far; the bars are how hard it swings', rows.length ? `<table class="m-table">
      <tr><th>Asset</th><th>Today</th><th class="r">Price</th><th class="r">Change</th><th class="r">Floor · ceiling</th><th class="r">Holders</th><th class="r">Invested</th><th class="r">Set price</th></tr>
      ${rows.map(a => {
        const c = chg(a);
        return `<tr><td><b>${esc(a.id)}</b>${risk(a.volatility || 0.03)}<div class="mini">${esc(a.label)} · ${esc(a.kind)}</div></td>
          <td>${mSpark(a.history, c >= 0)}</td>
          <td class="r"><b>${mm(a.price)}</b></td><td class="r ${c >= 0 ? 'm-pos' : 'm-neg'}">${c >= 0 ? '+' : ''}${c.toFixed(2)}%</td>
          <td class="r mini">${mshort(a.floor)} · ${mshort(a.ceiling)}</td><td class="r">${a.holders}</td><td class="r">${mshort(a.invested || 0)}</td>
          <td class="r" style="white-space:nowrap"><input type="number" step="0.01" id="mkt_${esc(a.id)}" placeholder="${Number(a.price).toFixed(2)}">
            <button class="btn-ghost" style="display:inline-flex;margin-left:6px" data-mact="setPrice" data-id="${esc(a.id)}">Set</button></td></tr>`;
      }).join('')}</table>` : emptyBox('No assets', 'Add them to Config.Market.assets.', MI.chart), { cls: 'fill' })}
  </div>`;
  countUp();
}

/* ═══════════════════════════════════════════════════════════
   SETTINGS
   ═══════════════════════════════════════════════════════════ */
async function mPageSettings() {
  if (!MG.settings) loadingPage('Settings', 'Everything in config.lua.');
  const res = await mPost('settings');
  if (MG.page !== 'settings') return;
  if (!res.ok) return (mView().innerHTML = `<div class="page">${emptyBox('No answer', res.msg || '')}</div>`);
  MG.settings = res.data;
  drawSettings();
}

const allItems = () => MG.settings.groups.flatMap(g => g.items);
function changedCount(group) {
  const s = MG.settings;
  return (group ? group.items : allItems()).filter(it => s.overridden[it.p]).length;
}

function drawSettings(keepFocus) {
  const s = MG.settings;
  document.getElementById('mgrTallyChanged').textContent = changedCount();
  const q = MG.setQ.toLowerCase();
  const found = q ? allItems().filter(it => (it.l + ' ' + (it.h || '') + ' ' + it.p).toLowerCase().includes(q)) : null;
  const current = s.groups.find(g => g.id === MG.setGroup) || s.groups[0];
  const items = found || current.items;
  const restart = items.filter(it => it.r).length;

  mView().innerHTML = `<div class="page">
    ${mHead('Settings', 'Everything in config.lua, changed here and live for every player. Reset brings config.lua’s value back.',
      `<div class="searchbox" style="width:240px">${MI.search}<input id="mgrSetQ" placeholder="Find a setting…" value="${esc(MG.setQ)}"></div>
       <button class="btn-ghost" data-mact="export">${MI.export}Copy to config.lua</button>
       <button class="btn-line" data-mact="resetAll" style="height:25px;font-size:11px">Reset all</button>`)}
    <div class="set-wrap">
      <div class="set-groups">${s.groups.map(g => `
        <button data-sgroup="${g.id}" class="${!q && current.id === g.id ? 'on' : ''}">${esc(g.label)}
          <small>${g.items.length}</small>${changedCount(g) ? `<span class="tally">${changedCount(g)}</span>` : ''}</button>`).join('')}</div>
      <div class="panel">
        <div class="p-head"><div><h2>${q ? `Results for “${esc(MG.setQ)}”` : esc(current.label)}</h2>
          <p>${items.length} settings · ${items.filter(it => s.overridden[it.p]).length} changed here${restart ? ` · ${restart} need a restart` : ''}</p></div></div>
        <div class="pb" style="padding:0;gap:0">${items.map(settingRow).join('') || `<div style="padding:12px">${emptyBox('No setting matches', 'Try another word.', MI.search)}</div>`}</div>
        <div class="pfoot">Saves when you leave a field or press ENTER<span class="right"><b>${changedCount()}</b> changed in total</span></div>
      </div>
    </div></div>`;

  const input = document.getElementById('mgrSetQ');
  if (keepFocus) { input.focus(); input.setSelectionRange(input.value.length, input.value.length); }
  let t = null;
  input.addEventListener('input', () => {
    clearTimeout(t);
    t = setTimeout(() => { MG.setQ = input.value.trim(); drawSettings(true); }, 250);
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
    ctl = `<input type="text" data-set="${esc(it.p)}" data-kind="text" value="${esc(v)}"
      ${it.s ? 'placeholder="Paste a new one to change it"' : ''} ${it.max ? `maxlength="${it.max}"` : ''}>`;
  }
  return `
    <div class="set-row ${changed ? 'changed' : ''}" data-row="${esc(it.p)}">
      <div class="lbl"><b>${esc(it.l)} ${it.r ? '<em class="chip amber">RESTART</em>' : ''}</b>
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
  const it = allItems().find(x => x.p === path);
  if (row && it) {
    row.outerHTML = settingRow(it);
    const fresh = document.querySelector(`.set-row[data-row="${CSS.escape(path)}"]`);
    if (fresh) fresh.classList.add('saved');
    document.getElementById('mgrTallyChanged').textContent = changedCount();
    document.querySelectorAll('.set-groups [data-sgroup]').forEach(b => {
      const g = MG.settings.groups.find(x => x.id === b.dataset.sgroup);
      const n = changedCount(g);
      b.innerHTML = `${esc(g.label)} <small>${g.items.length}</small>${n ? `<span class="tally">${n}</span>` : ''}`;
    });
  }
}

/* settings controls: switches save on click, the rest when they change */
document.getElementById('mgrView').addEventListener('change', (e) => {
  const el = e.target.closest('[data-set]');
  if (!el || !MG.settings) return;
  const it = allItems().find(x => x.p === el.dataset.set);
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
  loadingPage('Staff activity', 'Every change made in the Banking Manager.');
  const res = await mPost('audit', MG.auditPage);
  if (MG.page !== 'audit') return;
  const rows = res.rows || [];
  const pages = res.pages || 1, page = res.page || 1;
  const nums = [];
  for (let i = Math.max(1, page - 3); i <= Math.min(pages, page + 3); i++) nums.push(i);
  mView().innerHTML = `<div class="page">
    ${mHead('Staff activity', 'Every change made in the Banking Manager, newest first. Also sent to the Discord log when Config.Logs is on.')}
    ${mPanel('Log', `${mint(res.total || rows.length)} changes on record`, rows.length ? `<table class="m-table">
      <tr><th>When</th><th>Staff</th><th>Did</th><th>To</th><th>Detail</th></tr>
      ${rows.map(a => `<tr><td class="mini" style="white-space:nowrap">${mAgo(a.at)}</td><td><b>${esc(a.admin_name)}</b></td><td>${esc(a.action)}</td>
        <td class="mono mini">${esc(a.target || '')}</td><td class="mini">${esc(a.detail || '')}</td></tr>`).join('')}</table>`
      : emptyBox('Nothing yet', 'Changes made here show up in this list.', MI.history),
      { cls: 'fill', foot: `Page <b>${page}</b> of ${pages}<span class="right pager" style="padding:0">
        <button data-apage="${Math.max(1, page - 1)}" ${page <= 1 ? 'disabled' : ''}>‹</button>
        ${nums.map(i => `<button class="${i === page ? 'on' : ''}" data-apage="${i}">${i}</button>`).join('')}
        <button data-apage="${Math.min(pages, page + 1)}" ${page >= pages ? 'disabled' : ''}>›</button></span>` })}
  </div>`;
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
  const rg = e.target.closest('[data-range]');
  if (rg) return setRange(Number(rg.dataset.range));
  const tab = e.target.closest('[data-ptab]');
  if (tab) {
    MG.ptab = tab.dataset.ptab;
    document.querySelectorAll('[data-ptab]').forEach(b => b.classList.toggle('on', b === tab));
    const box = document.getElementById('mgrPTab');
    if (box && MG.player) { box.innerHTML = playerTab(MG.player); box.scrollTop = 0; }
    return;
  }
  const kind = e.target.closest('[data-kind]');
  if (kind && kind.closest('#mgrAccKinds')) { MG.accKind = kind.dataset.kind; return listAccounts(); }
  const pg = e.target.closest('[data-mpage]');
  if (pg) return mgrGo(pg.dataset.mpage);

  const pl = e.target.closest('[data-player]');
  if (pl) return openPlayer(pl.dataset.player);
  const owner = e.target.closest('[data-owner]');
  if (owner && owner.dataset.owner && !e.target.closest('[data-mact]')) {
    MG.playerQ = ''; MG.player = { identifier: owner.dataset.owner }; MG.ptab = 'accounts';
    return mgrGo('players');
  }

  const br = e.target.closest('[data-branch]');
  if (br && !e.target.closest('[data-mact]')) {
    MG.branch = Number(br.dataset.branch);
    closeMapPop();
    drawBranches();
    const r = MG.branches.rows[MG.branch - 1];
    if (r) mapFocus(r.x, r.y, 3);
    return;
  }

  const a = e.target.closest('[data-mact]');
  if (!a) return;
  const d = a.dataset;
  const p = MG.player;

  switch (d.mact) {
    case 'refresh': MG.overview = null; return mgrGo(MG.page);
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
