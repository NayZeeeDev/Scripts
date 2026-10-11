/* ═══════════════════════════════════════════════════════════
   Tuning UI · tablet (per-player accent + wallpaper, apps by job / rank)
   ═══════════════════════════════════════════════════════════ */
'use strict';

const WALLPAPERS = [
  ['carbon', 'Carbon'], ['midnight', 'Midnight'], ['aurora', 'Aurora'], ['sunset', 'Sunset'],
  ['track', 'Checkered'], ['blueprint', 'Blueprint'], ['redline', 'Redline'], ['mono', 'Graphite'],
];

const Tab = { open: false, s: null, app: null, arg: null, clock: null, unread: 0, cache: {} };

/* Discord avatar (animated gifs play as-is) with initials underneath as the fallback */
const initials = (n) => String(n || '?').trim().split(/\s+/).map((x) => x[0]).join('').slice(0, 2).toUpperCase();
const av = (url, name, cls = '') => `<span class="av ${cls}">${esc(initials(name))}${url ? `<img src="${esc(url)}" alt="" loading="lazy" onerror="this.remove()">` : ''}</span>`;

/* app registry: id, label, icon, group, visible(s) */
const APPS = [
  ['dashboard', 'Overview', 'fa-gauge-high', 'Workshop', (s) => !!s.biz],
  ['orders', 'Job Board', 'fa-table-columns', 'Workshop', (s) => !!s.biz],
  ['queue', 'My Bay', 'fa-warehouse', 'Workshop', (s) => !!s.biz],
  ['callouts', 'Roadside', 'fa-truck-pickup', 'Workshop', (s) => !!s.biz && s.missions],
  ['supplier', 'Parts Store', 'fa-boxes-stacked', 'Workshop', (s) => !!s.supplier],
  ['storage', 'Supply Storage', 'fa-boxes-packing', 'Workshop', (s) => !!s.storage],
  ['employees', 'Crew', 'fa-users', 'Management', (s) => !!s.biz && s.rank.manager],
  ['discounts', 'Promo Codes', 'fa-ticket', 'Management', (s) => !!s.biz && s.rank.manager && s.discounts],
  ['finance', 'Vault', 'fa-vault', 'Management', (s) => !!s.biz && s.rank.boss],
  ['upgrades', 'Equipment', 'fa-toolbox', 'Management', (s) => !!s.biz && s.upgrades],
  ['diag', 'Health Check', 'fa-heart-pulse', 'Tools', (s) => !!s.diagnostics],
  ['ecu', 'ECU Studio', 'fa-microchip', 'Tools', (s) => !!s.ecu],
  ['messages', 'Messages', 'fa-comment-dots', 'Tools', () => true],
  ['work', 'My Work', 'fa-wrench', 'Me', (s) => !!s.shop],
  ['cars', 'My Cars', 'fa-car', 'Me', () => true],
  ['myorders', 'My Orders', 'fa-receipt', 'Me', () => true],
  ['settings', 'Settings', 'fa-sliders', 'Me', () => true],
];
const SUBS = {
  dashboard: 'How the workshop is doing', orders: 'Every job from new to finished', queue: 'Jobs assigned to you', callouts: 'Stranded drivers waiting for help',
  supplier: 'Restock parts with the workshop account', storage: 'Parts on the shelf and on the way', employees: 'Hire, promote and reward', discounts: 'Codes for regulars and events', finance: 'Account, rates and payouts',
  upgrades: 'Unlock more services', diag: 'Plug in and read every module', ecu: 'Ignition timing and calibration', messages: 'Chats on every order',
  work: 'Everything you signed off', cars: 'Your registered vehicles', myorders: 'Parts waiting to be fitted', settings: 'Make this tablet yours',
};
Tab.apps = () => APPS.filter((a) => a[4](Tab.s));

/* ---------- open / close ---------- */
Tab.show = function ({ data, app }) {
  Tab.s = data;
  Tab.open = true;
  Tab.unread = 0;
  Tab.cache = {};
  Tab.theme(data.settings.accent, data.settings.wallpaper);
  $('#tCarrier').textContent = data.shop ? data.shop.label.toUpperCase() : (data.osName || 'NZ-OS');
  $('#tBatt').textContent = 60 + Math.floor(Math.random() * 39) + '%';
  $('#tablet').hidden = false;
  Tab.tick();
  clearInterval(Tab.clock);
  Tab.clock = setInterval(Tab.tick, 10000);
  const allowed = Tab.apps().map((a) => a[0]);
  if (app && allowed.includes(app)) Tab.go(app); else Tab.home();
};
Tab.hide = function () {
  Tab.open = false;
  $('#tablet').hidden = true;
  clearInterval(Tab.clock);
  Tab.app = null;
};
Tab.close = () => post('tab:close');
Tab.key = function (e) {
  if (['INPUT', 'TEXTAREA', 'SELECT'].includes(document.activeElement && document.activeElement.tagName)) {
    if (e.key === 'Escape') document.activeElement.blur();
    return;
  }
  if (e.key !== 'Escape') return;
  if (Tab.app && Tab.arg != null && Tab.app !== 'messages') return Tab.go(Tab.app);
  if (Tab.app) return Tab.home();
  Tab.close();
};
Tab.tick = () => {
  const d = new Date();
  $('#tClock').textContent = d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
  const c = $('#hClock');
  if (c) { c.textContent = $('#tClock').textContent; $('#hDate').textContent = d.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' }); }
};
Tab.theme = function (accent, wall) {
  const sc = $('#screen');
  const rgb = hex2rgb(accent);
  sc.style.setProperty('--acc', accent);
  sc.style.setProperty('--acc-lo', rgb2hex({ r: rgb.r * 0.55, g: rgb.g * 0.55, b: rgb.b * 0.55 }));
  sc.style.setProperty('--acc-wash', `rgba(${rgb.r},${rgb.g},${rgb.b},.13)`);
  sc.style.setProperty('--acc-edge', `rgba(${rgb.r},${rgb.g},${rgb.b},.4)`);
  const w = $('#wall');
  w.className = 'wall';
  w.style.backgroundImage = '';
  if (/^https?:\/\//.test(wall)) w.style.backgroundImage = `url("${wall.replace(/"/g, '')}")`;
  else w.classList.add('wp-' + (WALLPAPERS.some((x) => x[0] === wall) ? wall : 'carbon'));
};
Tab.toast = function (text, err, avatar) {
  const sc = $('#screen');
  const t = el(`<div class="ttoast ${err ? 'e' : ''}">${avatar ? av(avatar, '', 'sm') : `<i class="fa-solid ${err ? 'fa-circle-exclamation' : 'fa-circle-check'}"></i>`}<span>${esc(text)}</span></div>`);
  $$('.ttoast', sc).forEach((x) => x.remove());
  sc.appendChild(t);
  setTimeout(() => t.remove(), 3000);
};
Tab.reloadBiz = async function () {
  const d = await post('biz:refresh');
  if (d) Tab.s.biz = d;
};
Tab.avatar = function (d) {
  if (!Tab.s) return;
  Tab.s.avatar = d.url;
  if (!Tab.app) Tab.home();
  else { const m = $('.topx .mex .av'); if (m) m.outerHTML = av(d.url, Tab.s.name, 'sm'); }
};

/* ---------- launcher ---------- */
Tab.home = function () {
  Tab.app = null;
  Tab.arg = null;
  const s = Tab.s;
  const apps = Tab.apps();
  const dockIds = ['orders', 'diag', 'messages', 'settings'].filter((id) => apps.some((a) => a[0] === id));
  const tile = (a, acc) => `<button class="app ${acc ? 'acc' : ''}" data-a="${a[0]}"><span class="ico"><i class="fa-solid ${a[2]}"></i></span><span>${esc(a[1])}</span>${a[0] === 'messages' && Tab.unread ? `<b class="bdg">${Tab.unread}</b>` : ''}</button>`;
  $('#os').innerHTML = `<div class="home">
    <div class="who">${av(s.avatar, s.name, 'md')}<div><b>${esc(s.name)}</b><span>${esc(s.job)}${s.grade ? ' · ' + esc(s.grade) : ''}${s.shop ? ' · ' + esc(s.shop.label) : ''}</span></div></div>
    <div class="clock" id="hClock"></div><div class="date" id="hDate"></div>
    <div class="apps">${apps.filter((a) => !dockIds.includes(a[0])).map((a) => tile(a, a[3] === 'Workshop' || a[3] === 'Management')).join('')}</div>
    <div class="dock">${dockIds.map((id) => tile(apps.find((a) => a[0] === id), true)).join('')}</div>
  </div>`;
  $$('#os [data-a]').forEach((b) => (b.onclick = () => Tab.go(b.dataset.a)));
  Tab.tick();
};

/* ---------- app shell ---------- */
Tab.go = function (app, arg = null) {
  Tab.app = app;
  Tab.arg = arg;
  const s = Tab.s;
  const apps = Tab.apps();
  const groups = ['Workshop', 'Management', 'Tools', 'Me'].map((g) => [g, apps.filter((a) => a[3] === g)]).filter((g) => g[1].length);
  $('#os').innerHTML = `<div class="shellx">
    <nav class="tside scroll">
      <div class="logo"><span class="lm"><i class="fa-solid fa-screwdriver-wrench"></i></span><div><b>${esc(s.shop ? s.brand || 'PITWALL' : s.osName || 'NZ-OS')}</b><span>${esc(s.shop ? s.shop.label : 'Personal')}</span></div></div>
      ${groups.map(([g, list]) => `<div class="navg">${g}</div>${list.map((a) => `<button class="nav ${a[0] === app ? 'on' : ''}" data-a="${a[0]}"><i class="fa-solid ${a[2]}"></i>${esc(a[1])}${a[0] === 'messages' && Tab.unread ? `<span class="n">${Tab.unread}</span>` : ''}</button>`).join('')}`).join('')}
    </nav>
    <div class="mainx"><div class="topx" id="tTop"></div><div class="pg scroll" id="tPg"></div></div>
  </div>`;
  $$('#os .nav').forEach((b) => (b.onclick = () => Tab.go(b.dataset.a)));
  Tab.render();
};

/* signed-in user chip in the header */
Tab.me = function () {
  const s = Tab.s;
  if (!s) return '';
  const role = s.rank && s.rank.boss ? 'Owner' : s.rank && s.rank.manager ? 'Manager' : s.shop ? 'Mechanic' : s.job;
  return `<span class="mex">${av(s.avatar, s.name, 'sm')}<b>${esc(s.name)}</b><span>${esc(role || '')}</span></span>`;
};

/* header: optional back button, title + subtitle, right-side slot */
Tab.top = function (title, sub, { back, right = '' } = {}) {
  const t = $('#tTop');
  if (!t) return;
  t.innerHTML = `${back ? '<button class="bk" id="tBack"><i class="fa-solid fa-arrow-left"></i></button>' : ''}<h1>${esc(title)}<small>${esc(sub || '')}</small></h1>
    <span class="sp"></span>${right}${Tab.me()}<button class="bell" id="tBell" title="Messages"><i class="fa-regular fa-bell"></i>${Tab.unread ? '<i class="n"></i>' : ''}</button>`;
  if (back) $('#tBack').onclick = () => Tab.go(back);
  $('#tBell').onclick = () => Tab.go('messages');
};

Tab.render = function () {
  const pg = $('#tPg');
  if (!pg) return;
  const a = APPS.find((x) => x[0] === Tab.app);
  Tab.top(a ? a[1] : '', SUBS[Tab.app]);
  pg.scrollTop = 0;
  // workshop pages bring their own heading; the tablet header already shows it, so drop theirs
  const tidy = (p) => { const ph = p.firstElementChild; if (ph && ph.classList.contains('ph')) { const h = $('h2', ph); if (h) h.remove(); if (!ph.children.length) ph.remove(); } };
  const fn = TabApps[Tab.app] || (BizPages[Tab.app] && (async (p) => { if (!Biz.d) { p.innerHTML = '<div class="empty"><b>Workshop data unavailable</b></div>'; return; } await BizPages[Tab.app](p, Biz.d); tidy(p); }));
  if (fn) fn(pg, Tab.arg);
};

Tab.refresh = function (d) {
  if (!Tab.open || !Tab.app) return;
  if (d && d.app === 'storage') {
    if (Tab.app === 'storage') TabApps.storage($('#tPg'), null, true);
    else if (Tab.app === 'supplier') TabApps.supplierIncoming();
    return;
  }
  if (d && d.app === 'orders' && ['orders', 'queue', 'dashboard'].includes(Tab.app)) {
    Tab.cache.orders = null;
    if (Tab.app === 'dashboard') Tab.reloadBiz().then(Tab.render); else Tab.render();
  }
};

Tab.message = function (m) {
  if (Tab.app === 'messages' && Tab.arg === m.order) return TabApps.messages($('#tPg'), m.order, true);
  Tab.unread += 1;
  Tab.toast(`${m.from}: ${m.body}`, false, m.avatar || null);
  if (!Tab.app) Tab.home(); else { const n = $(`#os .nav[data-a="messages"]`); if (n && !$('.n', n)) n.insertAdjacentHTML('beforeend', `<span class="n">${Tab.unread}</span>`); }
};

$('#homeBar').onclick = () => (Tab.app ? Tab.home() : Tab.close());

/* ═══════════════ APPS ═══════════════ */
const TabApps = {};
const ago = (ms) => {
  const m = Math.max(0, Math.round((Date.now() - ms) / 60000));
  if (m < 1) return 'just now';
  if (m < 60) return `${m} min`;
  const h = Math.round(m / 60);
  return h < 48 ? `${h} h` : `${Math.round(h / 24)} days`;
};
const toMs = (v) => (typeof v === 'number' ? (v < 1e12 ? v * 1000 : v) : Date.parse(v) || Date.now());
const STATUS = { open: ['New', 'fa-bolt'], accepted: ['Claimed', 'fa-hand'], working: ['In the bay', 'fa-wrench'], done: ['Finished', 'fa-flag-checkered'], cancelled: ['Refunded', 'fa-rotate-left'] };
const STCOL = { open: '#f59e0b', accepted: '#60a5fa', working: '#c084fc', done: '#4ade80', cancelled: '#e5484d' };
const pill = (st) => `<span class="stp ${st}"><i class="fa-solid ${(STATUS[st] || [])[1] || 'fa-circle'}"></i>${(STATUS[st] || [st])[0]}</span>`;
const loadOrders = async (force) => {
  if (!force && Tab.cache.orders) return Tab.cache.orders;
  Tab.cache.orders = (await post('biz:orders')) || [];
  return Tab.cache.orders;
};

/* ---------- job board ---------- */
TabApps.orders = async function (pg, id) {
  if (id != null) return TabApps.job(pg, id, 'orders');
  pg.innerHTML = '<div class="empty"><i class="fa-solid fa-spinner fa-spin"></i></div>';
  const list = await loadOrders(true);
  if (Tab.app !== 'orders' || Tab.arg != null) return;
  const cols = [['open', 'New'], ['accepted', 'Claimed'], ['working', 'In the bay'], ['done', 'Finished']];
  pg.innerHTML = `<div class="jb">${cols.map(([st, label]) => {
    const items = list.filter((o) => (st === 'done' ? o.status === 'done' || o.status === 'cancelled' : o.status === st));
    return `<div class="jcol"><h5><i class="fa-solid ${STATUS[st][1]}" style="color:${STCOL[st]}"></i>${label}<em>${items.length}</em></h5><div class="jl scroll">${items.length ? items.map((o) => {
      return `<button class="jcard ${o.mine ? 'mine' : ''}" data-o="${o.id}" style="--c:${STCOL[o.status] || STCOL.open}">
        <div class="r1"><span class="lp">${esc(o.plate)}</span><time>${ago(toMs(o.created))}</time></div>
        <div class="nm">${esc(o.label || o.model)}</div>
        <div class="cu">${av(o.customerAvatar, o.customer, 'sm')}${esc(o.customer || 'Customer')}${o.mechanic ? ` <span class="muted">· ${esc(o.mechanic)}</span>` : ''}</div>
        <div class="r3">${o.items.slice(0, 6).map((i) => `<span class="pi ${i.done ? 'd' : ''}" title="${esc(i.label)}"><i class="fa-solid ${i.icon || 'fa-wrench'}"></i></span>`).join('')}${o.items.length > 6 ? `<span class="pi">+${o.items.length - 6}</span>` : ''}<b>${money(o.total)}</b></div></button>`;
    }).join('') : '<div class="none">Nothing here</div>'}</div></div>`;
  }).join('')}</div>`;
  $$('[data-o]', pg).forEach((b) => (b.onclick = () => Tab.go('orders', +b.dataset.o)));
};

/* ---------- job card ---------- */
TabApps.job = async function (pg, id, back) {
  let list = await loadOrders();
  if (!list.some((o) => o.id === id)) list = await loadOrders(true);
  const o = list.find((x) => x.id === id);
  if (!o) { pg.innerHTML = '<div class="empty"><i class="fa-solid fa-clipboard-question"></i><b>Job not found</b><span>It may have been closed.</span></div>'; return; }
  const s = Tab.s;
  Tab.top(`Job ${o.id}`, `${o.label || o.model} · ${o.plate}`, { back, right: pill(o.status) });
  const done = o.items.filter((i) => i.done).length;
  const active = ['open', 'accepted', 'working'].includes(o.status);
  const canStart = o.status === 'open' || (o.mine && (o.status === 'accepted' || o.status === 'working'));
  const svc = o.items.every((i) => ['repair', 'service', 'clean'].includes(i.kind)) ? 'Service' : 'Tuning';
  const order = ['open', 'accepted', 'working', 'done'];
  const at = o.status === 'cancelled' ? -1 : order.indexOf(o.status);
  const steps = order.map((st, i) => `${i ? `<span class="ln ${i <= at ? 'd' : ''}"></span>` : ''}<span class="s ${i < at || (i === at && st === 'done') ? 'd' : i === at ? 'c' : ''}"><i class="fa-solid ${i < at || st === 'done' && at === 3 ? 'fa-check' : STATUS[st][1]}"></i>${STATUS[st][0]}</span>`).join('');
  pg.innerHTML = `<div class="jx">
    <div>
      <div class="jhero"><span class="vi"><i class="fa-solid fa-car-side"></i></span>
        <div><h3>${esc(o.label || o.model)}</h3><div class="meta"><span class="lp">${esc(o.plate)}</span><span><i class="fa-solid fa-wrench"></i> ${svc}</span><span><i class="fa-regular fa-clock"></i> queued ${ago(toMs(o.created))}</span></div></div>
        <div class="fee"><small>Job value</small><b>${money(o.total)}</b></div></div>
      <div class="steps">${o.status === 'cancelled' ? '<span class="s c"><i class="fa-solid fa-rotate-left"></i>Refunded to the customer</span>' : steps}</div>
      <div class="sect" style="margin-top:16px">Parts · ${done} of ${o.items.length} fitted</div>
      ${o.items.map((i) => `<div class="jpart ${i.done ? 'd' : ''}"><span class="ck"><i class="fa-solid fa-check"></i></span>
        <div class="tx"><b><i class="fa-solid ${i.icon || 'fa-wrench'}" style="color:var(--ink-3);margin-right:6px"></i>${esc(i.label)}</b>${i.needs && i.needs.length ? `<span>${i.needs.map((n) => `<em>${esc(n.label)}</em>`).join('')}</span>` : ''}</div>
        <span class="pr">${i.price != null ? money(i.price) : ''}</span></div>`).join('')}
    </div>
    <div class="jside">
      <div class="jbox"><h6>Customer</h6>
        <div class="jcust">${av(o.customerAvatar, o.customer, 'md')}<div><b>${esc(o.customer || 'Customer')}</b><span>${o.mechanic ? 'Mechanic: ' + esc(o.mechanic) : 'Waiting for a mechanic'}</span></div></div>
        <button class="jact" id="oMsg" style="margin-top:12px"><i class="fa-regular fa-comment-dots"></i>Chat with customer</button></div>
      <div class="jbox"><h6>Next step</h6>
        ${canStart ? `<button class="jact p" id="oStart"><i class="fa-solid fa-screwdriver-wrench"></i>${o.status === 'working' ? 'Resume work' : 'Begin work'}</button>` : ''}
        ${o.status === 'open' ? '<button class="jact" id="oAccept"><i class="fa-solid fa-hand"></i>Claim job</button>' : ''}
        ${o.mine && (o.status === 'accepted' || o.status === 'working') ? '<button class="jact" id="oRelease"><i class="fa-solid fa-arrow-right-from-bracket"></i>Hand back</button>' : ''}
        ${active && s.rank.manager ? '<button class="jact r" id="oRefund"><i class="fa-solid fa-rotate-left"></i>Refund job</button>' : ''}
        ${!canStart && !active ? '<div class="muted" style="font-size:11.5px">Nothing left to do on this job.</div>' : ''}
        ${!canStart && active && !o.mine ? `<div class="muted" style="font-size:11.5px;margin-top:8px">${esc(o.mechanic || 'Another mechanic')} is on this job.</div>` : ''}</div>
      <div class="jbox rcpt"><h6>Receipt</h6>
        ${o.items.map((i) => `<div class="rr"><span>${esc(i.label)}</span><b>${i.price != null ? money(i.price) : '-'}</b></div>`).join('')}
        <div class="rr t"><span>Total</span><b>${money(o.total)}</b></div></div>
    </div></div>`;
  const on = (sel, fn) => { const b = $(sel, pg); if (b) b.onclick = fn; };
  on('#oStart', () => post('biz:startOrder', { id }));
  on('#oAccept', async () => { if (await bizCall('biz:orderAccept', { id }, 'Job claimed.')) { Tab.cache.orders = null; Tab.go(back, id); } });
  on('#oRelease', async () => { if (await bizCall('biz:orderRelease', { id }, 'Job handed back.')) { Tab.cache.orders = null; Tab.go(back); } });
  on('#oRefund', async (e) => {
    const b = e.currentTarget;
    if (b.dataset.c !== '1') { b.dataset.c = '1'; b.innerHTML = '<i class="fa-solid fa-triangle-exclamation"></i>Tap again to refund'; return; }
    if (await bizCall('biz:orderCancel', { id }, 'Job refunded.')) { Tab.cache.orders = null; Tab.go(back); }
  });
  on('#oMsg', () => Tab.go('messages', id));
};

/* ---------- my bay ---------- */
TabApps.queue = async function (pg, id) {
  if (id != null) return TabApps.job(pg, id, 'queue');
  pg.innerHTML = '<div class="empty"><i class="fa-solid fa-spinner fa-spin"></i></div>';
  const list = await loadOrders(true);
  if (Tab.app !== 'queue') return;
  const mine = list.filter((o) => o.mine && (o.status === 'accepted' || o.status === 'working'));
  const open = list.filter((o) => o.status === 'open');
  let bays = null;
  if (Tab.s.bays) { const b = await post('tab:bays'); if (Tab.app !== 'queue') return; if (b && b.ok && b.data.enabled) bays = b.data; }
  const myBays = bays ? bays.bays.filter((b) => b.mine).length : 0;
  pg.innerHTML = `
    ${bays ? `<div class="sect">Workshop bays<span class="sx">${myBays}/${bays.max} yours</span></div>
    <div class="bays">${bays.bays.map((b) => `<div class="bayx ${b.mine ? 'mine' : b.name ? 'taken' : ''}">
      <div class="r1"><span class="bn">${b.bay}</span><div class="grow"><b>Bay ${b.bay}</b><span>${b.mine ? 'Yours' : b.name ? 'In use' : 'Free'}</span></div>${b.name ? av(b.avatar, b.name, 'sm') : '<i class="fa-solid fa-square-parking free"></i>'}</div>
      <div class="who">${b.name ? esc(b.name) : 'Nobody has claimed this bay'}</div>
      <div class="hrow">${!b.name && bays.canClaim ? `<button class="btn sm pri grow" data-claim="${b.bay}" ${myBays >= bays.max ? 'disabled title="You already hold the most bays you can"' : ''}><i class="fa-solid fa-hand"></i>Claim</button>` : ''}
        ${b.mine || (b.name && bays.manager) ? `<button class="btn sm grow" data-free="${b.bay}"><i class="fa-solid fa-arrow-right-from-bracket"></i>${b.mine ? 'Release' : 'Free it'}</button>` : ''}
        <button class="btn sm" data-route="${b.bay}" title="Route there"><i class="fa-solid fa-route"></i></button></div></div>`).join('')}</div>` : ''}
    <div class="sect">On your lift</div>
    ${mine.length ? `<div class="bay">${mine.map((o) => {
      const done = o.items.filter((i) => i.done).length, pct = o.items.length ? Math.round((done / o.items.length) * 100) : 0;
      return `<div class="baycard"><div class="r1"><span class="ring" style="--p:${pct}"><span>${pct}%</span></span><div class="grow"><b>${esc(o.label || o.model)}</b><div class="hrow" style="margin-top:6px"><span class="lp">${esc(o.plate)}</span>${pill(o.status)}</div></div></div>
        <div class="hrow" style="margin-top:12px">${av(o.customerAvatar, o.customer, 'sm')}<span class="grow dim" style="font-size:11px">${esc(o.customer || '')}</span><b>${money(o.total)}</b></div>
        <div class="hrow" style="margin-top:12px"><button class="btn sm grow" data-v="${o.id}">Job card</button><button class="btn sm pri grow" data-s="${o.id}"><i class="fa-solid fa-screwdriver-wrench"></i>${o.status === 'working' ? 'Resume' : 'Begin'}</button></div></div>`;
    }).join('')}</div>` : '<div class="empty"><i class="fa-solid fa-mug-hot"></i><b>Your bay is empty</b><span>Claim a job from the waiting list below.</span></div>'}
    <div class="sect">Waiting · ${open.length}</div>
    ${open.length ? open.map((o) => `<div class="wait">${av(o.customerAvatar, o.customer)}<div class="grow"><b style="font-size:12.5px;color:#fff">${esc(o.label || o.model)}</b><div class="muted" style="font-size:10.5px;margin-top:3px">${esc(o.plate)} · ${o.items.length} part${o.items.length === 1 ? '' : 's'} · queued ${ago(toMs(o.created))}</div></div><b>${money(o.total)}</b><button class="btn sm" data-v="${o.id}">Open</button><button class="btn sm pri" data-s="${o.id}">Begin</button></div>`).join('')
      : '<div class="muted" style="font-size:11.5px">Nothing waiting.</div>'}`;
  $$('[data-v]', pg).forEach((b) => (b.onclick = () => Tab.go('queue', +b.dataset.v)));
  $$('[data-s]', pg).forEach((b) => (b.onclick = () => post('biz:startOrder', { id: +b.dataset.s })));
  const bayAct = async (nui, bay, msg) => { const r = await post(nui, { bay }); if (!r || !r.ok) return Tab.toast((r && r.error) || 'That did not work.', true); Tab.toast(msg); TabApps.queue(pg); };
  $$('[data-claim]', pg).forEach((b) => (b.onclick = () => bayAct('tab:bayClaim', +b.dataset.claim, `Bay ${b.dataset.claim} is yours.`)));
  $$('[data-free]', pg).forEach((b) => (b.onclick = () => bayAct('tab:bayRelease', +b.dataset.free, `Bay ${b.dataset.free} is free again.`)));
  $$('[data-route]', pg).forEach((b) => (b.onclick = async () => { if (await post('tab:bayRoute', { bay: +b.dataset.route })) Tab.toast(`Route set to bay ${b.dataset.route}.`); }));
};

/* ---------- ETA countdowns ([data-eta] = unix seconds, server clock) ---------- */
const Eta = { off: 0, t: null };
Eta.sync = (serverNow) => { if (serverNow) Eta.off = serverNow * 1000 - Date.now(); };
Eta.fmt = (sec) => (sec <= 0 ? 'Arriving' : sec >= 60 ? `${Math.floor(sec / 60)}m ${String(sec % 60).padStart(2, '0')}s` : `${sec}s`);
Eta.tick = () => {
  const now = (Date.now() + Eta.off) / 1000;
  const list = $$('#tPg [data-eta]');
  if (!list.length) { clearInterval(Eta.t); Eta.t = null; return; }
  list.forEach((e) => {
    const left = Math.max(0, Math.round(+e.dataset.eta - now));
    e.textContent = Eta.fmt(left);
    const bar = e.closest('.inc') && $('.ib i', e.closest('.inc'));
    if (bar && e.dataset.from) bar.style.width = clamp(100 - (left / Math.max(1, +e.dataset.eta - +e.dataset.from)) * 100, 3, 100) + '%';
  });
};
Eta.start = () => { if (!Eta.t) Eta.t = setInterval(Eta.tick, 1000); Eta.tick(); };

const incomingCards = (list) => list.map((r) => {
  const run = r.kind === 'run';
  const what = r.items.map((i) => `${i.qty}× ${esc(i.label)}`).join(' · ');
  return `<div class="inc ${run ? 'run' : ''}"><span class="ic"><i class="fa-solid ${run ? 'fa-truck-ramp-box' : 'fa-truck-fast'}"></i></span>
    <div class="grow"><b>${run ? `Supply run · ${esc(r.name || '')}` : `Delivery #${r.id}`}</b><span>${what}</span>${run ? '' : '<div class="ib"><i></i></div>'}</div>
    ${run ? '<span class="stp working"><i class="fa-solid fa-road"></i>On the road</span>' : `<span class="eta" data-eta="${r.eta}" data-from="${r.t}">-</span>`}</div>`;
}).join('');

/* ---------- supply storage ---------- */
const SRC_TXT = {
  supply: ['fa-warehouse', 'Parts come straight from storage', 'Mechanics fit parts from this storage at the racks. Nothing needed in your pockets.'],
  inventory: ['fa-hand-holding', 'Take parts out before fitting', 'Mechanics take the parts they need from here into their inventory, then fit them.'],
  both: ['fa-layer-group', 'Pockets first, then storage', 'Parts in your pockets are used first, anything missing comes from storage.'],
};
TabApps.storage = async function (pg, _, quiet) {
  if (!quiet) pg.innerHTML = '<div class="empty"><i class="fa-solid fa-spinner fa-spin"></i></div>';
  const r = await post('tab:storage');
  if (Tab.app !== 'storage') return;
  if (!r || !r.ok) { pg.innerHTML = `<div class="empty"><i class="fa-solid fa-lock"></i><b>No access</b><span>${esc((r && r.error) || '')}</span></div>`; return; }
  const d = r.data;
  Eta.sync(d.now);
  const src = SRC_TXT[d.source] || SRC_TXT.supply;
  const f = TabApps.storage.filter || 'all';
  const total = d.items.reduce((t, i) => t + i.qty, 0);
  Tab.top('Supply Storage', SUBS.storage, { right: `<span class="stp"><i class="fa-solid ${src[0]}"></i>${src[1]}</span>` });
  const cats = [...new Set(d.items.map((i) => i.cat))];
  const shown = (i) => f === 'all' || (f === 'stock' ? i.qty > 0 : i.carry > 0);
  const scroll = pg.scrollTop;
  pg.innerHTML = `
    <div class="sthead">
      <div class="stk-sum"><small>On the shelf</small><b>${total}</b><span>${d.items.filter((i) => i.qty > 0).length} part types</span></div>
      <div class="stk-sum"><small>On the way</small><b>${d.incoming.length}</b><span>${d.incoming.length ? 'deliveries and runs' : 'nothing ordered'}</span></div>
      <div class="note ${d.near ? '' : 'w'} grow"><i class="fa-solid ${d.near ? 'fa-circle-check' : 'fa-location-dot'}"></i><span>${d.near ? (d.canTake ? 'You are at the storage. Take parts out or put spares back.' : 'You can look but your rank cannot take parts out.') : `${src[2]} ${d.hasPoint ? 'Stand at the supply storage to take or put back parts.' : ''}`}</span>${!d.near && d.hasPoint ? '<button class="btn sm" id="stRoute"><i class="fa-solid fa-route"></i>Route</button>' : ''}</div>
    </div>
    ${d.incoming.length ? `<div class="sect">On the way</div><div class="incl">${incomingCards(d.incoming)}</div>` : ''}
    <div class="sect">Shelf<span class="chips">${[['all', 'All'], ['stock', 'In stock'], ['carry', 'In my pockets']].map(([k, l]) => `<button class="chip ${f === k ? 'on' : ''}" data-f="${k}">${l}</button>`).join('')}</span></div>
    ${cats.map((c) => { const list = d.items.filter((i) => i.cat === c && shown(i)); return list.length ? `<div class="sub">${esc(c)}</div><div class="stkgrid">${list.map((i) => `<div class="stk ${i.qty ? '' : 'z'}">
      <div class="r1"><b>${esc(i.label)}</b><em>${i.qty}</em></div>
      <span>${i.carry ? `you carry ${i.carry}` : 'none on you'}</span>
      ${d.near ? `<div class="hrow">${d.canTake ? `<button class="btn sm grow" data-take="${esc(i.item)}" ${i.qty ? '' : 'disabled'}><i class="fa-solid fa-arrow-up-from-bracket"></i>Take</button>` : ''}${d.canPut ? `<button class="btn sm grow" data-put="${esc(i.item)}" ${i.carry ? '' : 'disabled'}><i class="fa-solid fa-box-archive"></i>Put</button>` : ''}</div>` : ''}
    </div>`).join('')}</div>` : ''; }).join('') || '<div class="empty"><i class="fa-solid fa-box-open"></i><b>Nothing here</b><span>Order parts in the Parts Store or fetch them with a supply run.</span></div>'}`;
  pg.scrollTop = scroll;
  Eta.start();
  $$('[data-f]', pg).forEach((b) => (b.onclick = () => { TabApps.storage.filter = b.dataset.f; TabApps.storage(pg, null, true); }));
  const route = $('#stRoute', pg);
  if (route) route.onclick = async () => { if (await post('tab:storageRoute')) Tab.toast('Route set to the supply storage.'); };
  const move = async (kind, item, btn) => {
    btn.disabled = true;
    const res = await post(kind === 'take' ? 'tab:storageTake' : 'tab:storagePut', { item, qty: 1 });
    if (!res || !res.ok) { btn.disabled = false; return Tab.toast((res && res.error) || 'That did not work.', true); }
    TabApps.storage(pg, null, true);
  };
  $$('[data-take]', pg).forEach((b) => (b.onclick = () => move('take', b.dataset.take, b)));
  $$('[data-put]', pg).forEach((b) => (b.onclick = () => move('put', b.dataset.put, b)));
};

/* ---------- parts store ---------- */
TabApps.supplier = async function (pg) {
  pg.innerHTML = '<div class="empty"><i class="fa-solid fa-spinner fa-spin"></i></div>';
  const r = await post('tab:supplier');
  if (Tab.app !== 'supplier') return;
  if (!r || !r.ok) { pg.innerHTML = `<div class="empty"><i class="fa-solid fa-lock"></i><b>No access</b><span>${esc((r && r.error) || '')}</span></div>`; return; }
  const d = r.data;
  const cart = {};
  const cats = [...new Set(d.items.map((i) => i.cat))];
  const total = () => d.items.reduce((t, i) => t + (cart[i.item] || 0) * i.price, 0);
  Tab.top('Parts Store', SUBS.supplier, { right: `<span class="stp"><i class="fa-solid fa-wallet"></i>${money(d.balance)}</span>` });
  Eta.sync(d.now);
  pg.innerHTML = `<div id="supInc">${d.incoming && d.incoming.length ? `<div class="sect">On the way</div><div class="incl">${incomingCards(d.incoming)}</div>` : ''}</div>
    ${cats.map((c) => `<div class="sect">${esc(c)}</div><div class="supgrid">${d.items.filter((i) => i.cat === c).map((i) => `<div class="sup"><b>${esc(i.label)}</b><span>${money(i.price)} each · ${d.storage ? `${i.stock || 0} in storage` : `you carry ${i.have}`}</span>
      <div class="hrow"><button class="ibtn" data-m="${i.item}"><i class="fa-solid fa-minus"></i></button><span class="q" data-q="${i.item}">0</span><button class="ibtn" data-p="${i.item}"><i class="fa-solid fa-plus"></i></button></div></div>`).join('')}</div>`).join('')}
    <div class="hrow" style="position:sticky;bottom:-26px;margin:16px -26px -26px;padding:14px 26px;background:rgba(7,8,9,.97);border-top:1px solid rgba(255,255,255,.06)">
      <span class="grow" id="supT">Nothing selected</span><button class="btn" id="supX">Clear</button>${Tab.s.supplyRuns ? `<button class="btn" id="supRun" disabled title="Drive a box truck to the warehouse and bring the crates back"><i class="fa-solid fa-truck-ramp-box"></i>Fetch it yourself <span class="tag t">-${Tab.s.supplyRuns.discount}%</span></button>` : ''}<button class="btn pri" id="supBuy" disabled title="${d.minutes ? `Arrives in supply storage in ${d.minutes} minutes` : 'Arrives right away'}"><i class="fa-solid fa-truck-fast"></i>${d.minutes ? `Deliver · ${d.minutes} min` : 'Deliver now'}</button></div>`;
  Eta.start();
  const upd = () => {
    $$('[data-q]', pg).forEach((q) => (q.textContent = cart[q.dataset.q] || 0));
    const t = total();
    const sr = Tab.s.supplyRuns;
    const qty = Object.values(cart).reduce((a, b) => a + b, 0);
    $('#supT').innerHTML = t ? `Delivered <b class="teal">${money(t)}</b>${sr ? ` <span class="muted">· fetch it yourself ${money(Math.floor(t * (100 - sr.discount) / 100))}</span>` : ''}` : 'Nothing selected';
    $('#supBuy').disabled = !t;
    const run = $('#supRun');
    if (run) { run.disabled = !t || qty > sr.max; run.title = qty > sr.max ? `A truck carries ${sr.max} parts at most` : `Drive to the warehouse and back within ${sr.minutes} minutes`; }
  };
  $$('[data-p]', pg).forEach((b) => (b.onclick = () => { cart[b.dataset.p] = Math.min(d.max, (cart[b.dataset.p] || 0) + 1); upd(); }));
  $$('[data-m]', pg).forEach((b) => (b.onclick = () => { cart[b.dataset.m] = Math.max(0, (cart[b.dataset.m] || 0) - 1); if (!cart[b.dataset.m]) delete cart[b.dataset.m]; upd(); }));
  $('#supX').onclick = () => { Object.keys(cart).forEach((k) => delete cart[k]); upd(); };
  const run = $('#supRun');
  if (run) run.onclick = async () => {
    const res = await post('tab:supplyRun', { cart });
    if (!res || !res.ok) Tab.toast((res && res.error) || 'Could not start the run.', true);
  };
  $('#supBuy').onclick = async () => {
    const res = await post('tab:buy', { cart });
    if (!res || !res.ok) return Tab.toast((res && res.error) || 'Order failed.', true);
    if (res.data.eta) Tab.toast(`Ordered: ${money(res.data.total)}. It lands in supply storage in ${Eta.fmt(Math.max(0, res.data.eta - res.data.now))}.`);
    else Tab.toast(res.data.refunded ? `Delivered. ${money(res.data.refunded)} refunded (pockets full).` : `Parts delivered: ${money(res.data.total)}`);
    TabApps.supplier(pg);
  };
};

TabApps.supplierIncoming = async function () {
  const box = $('#supInc');
  if (!box) return;
  const r = await post('tab:supplier');
  if (Tab.app !== 'supplier' || !r || !r.ok) return;
  Eta.sync(r.data.now);
  const inc = r.data.incoming || [];
  box.innerHTML = inc.length ? `<div class="sect">On the way</div><div class="incl">${incomingCards(inc)}</div>` : '';
  r.data.items.forEach((i) => { const sup = $(`[data-q="${i.item}"]`); const sp = sup && sup.closest('.sup') && $('span', sup.closest('.sup')); if (sp && r.data.storage) sp.textContent = `${money(i.price)} each · ${i.stock || 0} in storage`; });
  Eta.start();
};

/* ---------- health check ---------- */
TabApps.diag = async function (pg) {
  const car = await post('tab:car');
  if (Tab.app !== 'diag') return;
  pg.innerHTML = car ? `<div class="scan"><span class="pulse"><i class="fa-solid fa-car-side"></i></span><b>${esc(car.label)}</b><span>${esc(car.plate)} · plug in to read the engine, chassis and body modules.</span><button class="btn pri" id="dgGo"><i class="fa-solid fa-stethoscope"></i>Run health check</button></div>`
    : '<div class="scan"><span class="pulse"><i class="fa-solid fa-plug-circle-xmark"></i></span><b>No vehicle in range</b><span>Stand next to the car (or sit in it) and try again.</span><button class="btn" id="dgRe"><i class="fa-solid fa-rotate"></i>Look again</button></div>';
  const re = $('#dgRe');
  if (re) re.onclick = () => TabApps.diag(pg);
  const go = $('#dgGo');
  if (go) go.onclick = async () => {
    pg.innerHTML = '<div class="scan"><span class="pulse"><i class="fa-solid fa-wave-square"></i></span><b id="dgSt">Connecting</b><div class="pbar"><i id="dgP"></i></div></div>';
    const steps = ['Connecting', 'Engine module', 'Chassis and brakes', 'Body control', 'Fault memory'];
    let p = 0;
    const tm = setInterval(() => { p = Math.min(96, p + 4); const b = $('#dgP'); if (b) { b.style.width = p + '%'; $('#dgSt').textContent = steps[Math.min(steps.length - 1, Math.floor(p / 20))]; } }, 90);
    const [r] = await Promise.all([post('tab:scan'), new Promise((ok) => setTimeout(ok, 2400))]);
    clearInterval(tm);
    if (Tab.app !== 'diag') return;
    if (!r || !r.ok) { pg.innerHTML = `<div class="scan"><span class="pulse"><i class="fa-solid fa-triangle-exclamation"></i></span><b>${esc((r && r.error) || 'Scan failed')}</b><button class="btn" id="dgRe2">Back</button></div>`; $('#dgRe2').onclick = () => TabApps.diag(pg); return; }
    TabApps.diagResult(pg, r.data);
  };
};

TabApps.diagResult = function (pg, d) {
  const live = d.live || {};
  const codes = d.codes || [];
  const perf = live.perf || {};
  const lvl = (v) => (v == null || v < 0 ? 'Stock' : 'L' + (v + 1));
  const wear = d.wear || {};
  const vals = [live.engine, live.body, ...Object.values(wear)].filter((v) => v != null);
  const score = vals.length ? Math.round(vals.reduce((a, v) => a + v, 0) / vals.length) - codes.filter((c) => c.sev === 'high').length * 6 : 100;
  const sc = clamp(score, 0, 100);
  const col = sc < 45 ? '#e5484d' : sc < 70 ? '#e5a50a' : 'var(--acc)';
  const tile = (name, icon, v, inv) => { const bad = inv ? v > 60 : v < 40, warn = inv ? v > 30 : v < 70; return `<div class="sysc ${bad ? 'b' : warn ? 'w' : ''}"><div class="h"><i class="fa-solid ${icon}"></i>${name}<b>${Math.round(v)}%</b></div><div class="tr"><i style="width:${clamp(v, 0, 100)}%"></i></div></div>`; };
  const icons = { engine: 'fa-gears', transmission: 'fa-code-branch', brakes: 'fa-circle-stop', suspension: 'fa-arrows-up-down', tyres: 'fa-life-ring', turbo: 'fa-fan' };
  Tab.top('Health Check', `${d.vehicle} · ${d.plate}`, { right: '<button class="btn sm" id="dgAgain"><i class="fa-solid fa-rotate"></i>Scan again</button>' });
  pg.innerHTML = `<div class="hc">
    <div class="hscore"><span class="gauge" style="--p:${sc};--g:${col}"><span><b>${sc}</b><small>health</small></span></span>
      <div><b style="font-size:14px;color:#fff">${sc >= 80 ? 'Road ready' : sc >= 60 ? 'Needs attention soon' : 'Service required'}</b><div class="muted" style="font-size:11px;margin-top:4px">${codes.length} fault${codes.length === 1 ? '' : 's'} stored · ${Math.round(d.km || 0).toLocaleString('en-US')} km</div></div>
      <div class="chips" style="justify-content:center">${d.registered ? '<span class="tag t">Registered</span>' : '<span class="tag a">Unregistered</span>'}${live.turbo ? '<span class="tag">Turbo</span>' : ''}${d.ecu ? '<span class="tag t">Programmable ECU</span>' : ''}${d.swap ? `<span class="tag t">${esc(d.swap)}</span>` : ''}${d.nitrous ? `<span class="tag t">NOS ${Math.round(d.nitrous.amount || 0)}</span>` : ''}</div>
      ${Tab.s.ecu && d.ecu ? '<button class="btn pri wide" id="dgEcu"><i class="fa-solid fa-microchip"></i>Open in ECU Studio</button>' : ''}
    </div>
    <div>
      <div class="sect">Live readings</div>
      <div class="sys">${tile('Engine', 'fa-gears', live.engine)}${tile('Body', 'fa-car-burst', live.body)}${tile('Fuel tank', 'fa-gas-pump', live.tank)}${tile('Fuel', 'fa-droplet', live.fuel)}${tile('Dirt', 'fa-soap', live.dirt, true)}
        <div class="sysc"><div class="h"><i class="fa-solid fa-temperature-half"></i>Coolant<b>${live.temp}°C</b></div><div class="muted" style="font-size:10.5px;margin-top:9px">Oil level ${live.oil}</div></div></div>
      ${Object.keys(wear).length ? `<div class="sect">Part condition</div><div class="sys">${Object.entries(wear).map(([k, v]) => tile(cap(k), icons[k] || 'fa-wrench', v)).join('')}</div>` : ''}
      <div class="sect">Fault codes</div>
      ${codes.length ? codes.map((c) => `<div class="dtc2 ${c.sev}"><code>${esc(c.code)}</code><span>${esc(c.text)}</span><em>${c.sev === 'high' ? 'urgent' : c.sev === 'med' ? 'soon' : 'info'}</em></div>`).join('') : '<div class="note"><i class="fa-solid fa-circle-check teal"></i><span>No faults stored.</span></div>'}
      <div class="sect">Build</div>
      <div class="chips"><span class="tag">Engine ${lvl(perf['11'])}</span><span class="tag">Brakes ${lvl(perf['12'])}</span><span class="tag">Gearbox ${lvl(perf['13'])}</span><span class="tag">Suspension ${lvl(perf['15'])}</span><span class="tag">Armor ${lvl(perf['16'])}</span></div>
      ${d.lastShop ? `<div class="muted" style="margin-top:12px;font-size:11px">Last serviced at ${esc(d.lastShop)} · ${new Date(d.lastTime * 1000).toLocaleDateString()}</div>` : ''}
    </div></div>`;
  $('#dgAgain').onclick = () => { Tab.top('Health Check', SUBS.diag); TabApps.diag(pg); };
  const e = $('#dgEcu');
  if (e) e.onclick = () => Tab.go('ecu');
};

/* ---------- ECU studio: ignition timing bands + calibration ---------- */
TabApps.ecu = async function (pg) {
  const M = Tab.s.ecuMap;
  pg.innerHTML = '<div class="empty"><i class="fa-solid fa-spinner fa-spin"></i><b>Reading ECU</b></div>';
  const r = await post('tab:ecuRead');
  if (Tab.app !== 'ecu') return;
  if (!r || !r.ok) {
    pg.innerHTML = `<div class="scan"><span class="pulse"><i class="fa-solid fa-microchip"></i></span><b>${esc((r && r.error) || 'No ECU')}</b><span>Stand next to a car with a programmable ECU. Customers buy it at a tuning shop (Performance › ECU Tune).</span><button class="btn" id="ecRe"><i class="fa-solid fa-rotate"></i>Try again</button></div>`;
    $('#ecRe').onclick = () => TabApps.ecu(pg);
    return;
  }
  const d = r.data;
  const params = (CFG.ecu && CFG.ecu.params) || [];
  const presets = (CFG.ecu && CFG.ecu.presets) || [];
  const base = Array.from({ length: M.Cells }, () => M.Base);
  let cells = (d.cells && d.cells.length === M.Cells ? d.cells : base).slice();
  let cal = Object.assign({}, d.params || {});
  const flashed = { cells: cells.slice(), cal: Object.assign({}, cal), fuel: d.fuel || 0 };
  let fuel = d.fuel || 0, sel = 0, tab = Tab.cache.ecuTab || 'timing';
  const log = [['ok', `Connected to ${d.label}`], ['', d.cells ? 'Custom timing found on the ECU' : 'Factory timing on the ECU']];
  const thr = (i) => (M.Thresholds[i] || 70) + fuel * M.FuelRaise;
  const calc = () => {
    let over = 0; const knock = [];
    for (let i = 0; i < M.Cells; i++) { over += cells[i] - M.Base; if (cells[i] > thr(i)) knock.push(i); }
    return { gain: Math.round(((over / (M.Cells * (100 - M.Base))) * M.MaxGain - (fuel / 100) * M.FuelCost) * 100) / 100, knock };
  };
  const powerPct = () => cal.power || 0;
  Tab.top('ECU Studio', `${d.label} · ${d.plate}`, { right: d.canFlash ? '<span class="stp"><i class="fa-solid fa-lock-open"></i>Write access</span>' : '<span class="stp cancelled"><i class="fa-solid fa-lock"></i>Read only</span>' });
  pg.innerHTML = `<div class="es">
    <div class="eshead"><span class="vi"><i class="fa-solid fa-microchip"></i></span><div><b>${esc(d.label)}</b><span>${esc(d.plate)} · ${d.cells ? 'custom calibration' : 'factory calibration'}</span></div><span class="sp"></span>
      <div class="etabs"><button data-tab="timing">Ignition timing</button><button data-tab="cal">Calibration</button></div></div>
    <div id="ecBody" style="flex:1;min-height:0;display:flex;flex-direction:column"></div>
    <div class="efoot"><button class="btn pri" id="ecFlash" ${d.canFlash ? '' : 'disabled'}><i class="fa-solid fa-download"></i>Write to ECU</button><button class="btn" id="ecReset"><i class="fa-solid fa-clock-rotate-left"></i>Undo changes</button><button class="btn" id="ecRev"><i class="fa-solid fa-gauge-high"></i>Rev test</button><span class="sp"></span><button class="btn warn" id="ecStock" ${d.canFlash ? '' : 'disabled'}><i class="fa-solid fa-industry"></i>Factory reset</button></div>
  </div>`;
  const say = (cls, text) => { log.unshift([cls, text, new Date().toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' })]); const b = $('#ecLog'); if (b) paintLog(); };
  const paintLog = () => { const b = $('#ecLog'); if (b) b.innerHTML = log.slice(0, 30).map(([c, x, t]) => `<div class="${c}"><i class="fa-solid ${c === 'er' ? 'fa-xmark' : c === 'wa' ? 'fa-exclamation' : 'fa-check'}"></i>${esc(x)}${t ? `<time>${t}</time>` : ''}</div>`).join(''); };

  // dyno: stock vs tuned power across the rev range
  const dyno = () => {
    const W = 460, H = 150, n = M.Cells, x = (i) => 10 + (i * (W - 20)) / (n - 1);
    const shape = (i) => Math.sin(((i + 1) / (n + 1)) * Math.PI * 0.92) * 0.85 + 0.15;
    const p = 1 + powerPct() / 100;
    const stock = Array.from({ length: n }, (_, i) => shape(i));
    const tuned = stock.map((v, i) => v * p * (1 + ((cells[i] - M.Base) / (100 - M.Base)) * (M.MaxGain / 100)) * (1 - (fuel / 100) * (M.FuelCost / 100)));
    const max = Math.max(...stock, ...tuned) * 1.08;
    const y = (v) => H - 14 - (v / max) * (H - 24);
    const line = (arr) => arr.map((v, i) => `${x(i)},${y(v)}`).join(' ');
    const { knock } = calc();
    return `<svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none">
      ${[0.25, 0.5, 0.75].map((f) => `<line x1="0" x2="${W}" y1="${H * f}" y2="${H * f}" stroke="rgba(255,255,255,.05)"/>`).join('')}
      ${knock.map((i) => `<circle cx="${x(i)}" cy="${y(tuned[i])}" r="9" fill="rgba(239,68,68,.25)"/>`).join('')}
      <polyline points="${line(stock)}" fill="none" stroke="rgba(255,255,255,.35)" stroke-width="1.6" stroke-dasharray="4 4"/>
      <polygon points="${x(0)},${H - 14} ${line(tuned)} ${x(n - 1)},${H - 14}" fill="var(--acc-wash)"/>
      <polyline points="${line(tuned)}" fill="none" stroke="var(--acc)" stroke-width="2.6" stroke-linejoin="round"/>
      ${Array.from({ length: n }, (_, i) => `<text x="${x(i)}" y="${H}" fill="#63696d" font-size="9" text-anchor="middle">${i + 1}k</text>`).join('')}</svg>`;
  };
  const side = () => `<div class="ebox"><h6><i class="fa-solid fa-chart-line"></i>Predicted output<span>dashed = factory</span></h6>
      <div class="gainrow"><span class="gauge" id="ecG"><span><b id="ecGain">0%</b><small>power</small></span></span>
        <div class="estat"><div><small>Est. power</small><b id="ecHp">-</b></div><div><small>Knock risk</small><b id="ecKn">0</b></div><div><small>Mixture</small><b id="ecMx">0%</b></div><div><small>Stage</small><b id="ecSt">Stock</b></div></div></div>
      <div class="dyno" id="ecDyno"></div></div>
    <div class="ebox" style="flex:1"><h6><i class="fa-solid fa-list-check"></i>Activity</h6><div class="elog" id="ecLog"></div></div>`;

  const body = () => {
    $$('.etabs button', pg).forEach((b) => b.classList.toggle('on', b.dataset.tab === tab));
    const box = $('#ecBody');
    if (tab === 'timing') {
      box.innerHTML = `<div class="egrid"><div style="display:flex;flex-direction:column;gap:14px;min-height:0">
        <div class="ebox" style="flex:1"><h6><i class="fa-solid fa-bolt"></i>Timing advance per rev band<span>drag a column up or down · red line = knock limit</span></h6>
          <div class="bands" id="ecBands">${cells.map((_, i) => `<div class="band" data-i="${i}"><span class="v"></span><div class="col"><i class="fill"></i><i class="lim"></i></div><label>${i + 1}k</label></div>`).join('')}</div></div>
        <div class="ebox"><h6><i class="fa-solid fa-droplet"></i>Mixture richness<span>richer = safer timing, less power</span></h6><div class="mix" id="ecMix"></div></div>
      </div><div style="display:flex;flex-direction:column;gap:14px;min-height:0">${side()}</div></div>`;
      $('#ecMix').appendChild(range({ label: 'Enrichment', min: 0, max: 100, step: 1, value: fuel, fmt: (x) => x + '%', hint: `Raises every knock limit by ${M.FuelRaise} per %`, onInput: (x) => { fuel = x; paint(); } }));
      $$('#ecBands .band').forEach((b) => {
        const col = $('.col', b);
        col.addEventListener('mousedown', (e) => {
          sel = +b.dataset.i;
          const set = (ev) => { const rc = col.getBoundingClientRect(); cells[sel] = clamp(Math.round((1 - (ev.clientY - rc.top) / rc.height) * 100), 0, 100); paint(); };
          set(e);
          const up = () => { window.removeEventListener('mousemove', set); window.removeEventListener('mouseup', up); if (calc().knock.includes(sel)) say('wa', `Knock predicted at ${sel + 1}k rpm`); };
          window.addEventListener('mousemove', set); window.addEventListener('mouseup', up);
        });
      });
    } else {
      box.innerHTML = `<div class="egrid"><div class="ebox" style="min-height:0"><h6><i class="fa-solid fa-sliders"></i>Calibration<span>handling and power tables</span></h6>
          <div class="chips" style="margin-bottom:14px" id="ecPre">${presets.map((p, i) => `<button class="chip" data-p="${i}">${esc(p.label)}</button>`).join('')}</div>
          <div class="stack scroll" id="ecCal" style="flex:1;min-height:0;padding-right:6px"></div></div>
        <div style="display:flex;flex-direction:column;gap:14px;min-height:0">${side()}</div></div>`;
      const holder = $('#ecCal');
      const ranges = params.map((p) => {
        const rg = range({ label: p.label, min: p.min, max: p.max, step: p.step, value: cal[p.key] || 0, hint: p.hint, fmt: (x) => (x > 0 ? '+' : '') + x + p.unit, onInput: (x) => { cal[p.key] = x; paint(); } });
        holder.appendChild(rg);
        return [p.key, rg];
      });
      $$('#ecPre .chip').forEach((c) => (c.onclick = () => {
        const p = presets[+c.dataset.p];
        ranges.forEach(([k, rg]) => { cal[k] = p.values[k] || 0; rg.set(cal[k]); });
        $$('#ecPre .chip').forEach((x) => x.classList.toggle('on', x === c));
        say('', `${p.label} preset loaded`);
        paint();
      }));
    }
    paintLog();
    paint();
  };

  const paint = () => {
    const { gain, knock } = calc();
    $$('#ecBands .band').forEach((b) => {
      const i = +b.dataset.i;
      $('.v', b).textContent = Math.round(cells[i]);
      $('.fill', b).style.height = cells[i] + '%';
      $('.lim', b).style.bottom = `calc(${clamp(thr(i), 0, 100)}% - 1px)`;
      b.classList.toggle('hot', knock.includes(i));
      b.classList.toggle('sel', i === sel);
    });
    const total = gain + powerPct();
    const g = $('#ecG');
    if (g) {
      g.style.setProperty('--p', clamp(Math.abs(total) * 4, 0, 100));
      g.style.setProperty('--g', total < 0 ? '#e5484d' : 'var(--acc)');
      $('#ecGain').textContent = (total > 0 ? '+' : '') + total.toFixed(1) + '%';
      $('#ecHp').textContent = Math.round(d.hp * (1 + total / 100)) + ' hp';
      $('#ecKn').textContent = `${knock.length} / ${M.Cells}`;
      $('#ecKn').className = knock.length ? 'r' : 'g';
      $('#ecMx').textContent = fuel + '%';
      $('#ecSt').textContent = total >= 18 ? 'Stage 3' : total >= 10 ? 'Stage 2' : total > 1 ? 'Stage 1' : total < -1 ? 'Economy' : 'Stock';
      $('#ecDyno').innerHTML = dyno();
    }
  };

  $$('.etabs button', pg).forEach((b) => (b.onclick = () => { tab = Tab.cache.ecuTab = b.dataset.tab; body(); }));
  $('#ecReset').onclick = () => { cells = flashed.cells.slice(); cal = Object.assign({}, flashed.cal); fuel = flashed.fuel; body(); say('', 'Changes undone'); };
  $('#ecRev').onclick = () => post('tab:rev');
  const write = async (stock) => {
    say('', stock ? 'Restoring factory calibration...' : 'Writing calibration...');
    $('#ecFlash').disabled = $('#ecStock').disabled = true;
    const clean = {};
    params.forEach((p) => { clean[p.key] = cal[p.key] || 0; });
    const res = await post('tab:ecuFlash', { cells: cells.map((v) => Math.round(v)), fuel, params: clean, stock: !!stock });
    $('#ecFlash').disabled = $('#ecStock').disabled = !d.canFlash;
    if (!res || !res.ok) return say('er', 'Write failed: ' + ((res && res.error) || 'unknown'));
    if (stock) { cells = base.slice(); fuel = 0; cal = {}; }
    flashed.cells = cells.slice(); flashed.cal = Object.assign({}, cal); flashed.fuel = fuel;
    say('ok', `Written · timing ${res.data.gain > 0 ? '+' : ''}${res.data.gain}% · ${res.data.knock} knocking band${res.data.knock === 1 ? '' : 's'}`);
    if (res.data.knock) say('wa', 'Knocking bands wear the engine and can damage it under load');
    body();
  };
  $('#ecFlash').onclick = () => write(false);
  $('#ecStock').onclick = (e) => {
    const b = e.currentTarget;
    if (b.dataset.c !== '1') { b.dataset.c = '1'; b.innerHTML = '<i class="fa-solid fa-triangle-exclamation"></i>Tap again'; setTimeout(() => { b.dataset.c = ''; b.innerHTML = '<i class="fa-solid fa-industry"></i>Factory reset'; }, 2500); return; }
    write(true);
  };
  if (!d.canFlash) log.unshift(['wa', 'Read only: your job cannot write ECUs']);
  body();
};

/* ---------- messages ---------- */
TabApps.messages = async function (pg, id, keep) {
  if (!keep) pg.innerHTML = '<div class="empty"><i class="fa-solid fa-spinner fa-spin"></i></div>';
  const threads = (await post('tab:threads')) || [];
  if (Tab.app !== 'messages') return;
  Tab.unread = 0;
  const cur = id != null ? id : threads[0] && threads[0].id;
  Tab.arg = cur;
  pg.innerHTML = `<div class="chat">
    <div class="threads scroll">${threads.length ? threads.map((t) => `<button class="thr ${t.id === cur ? 'on' : ''}" data-t="${t.id}">${av(t.avatar, t.mine ? t.mechanic_name || t.shopLabel : t.customer_name)}<div class="tx"><b>${esc(t.label || t.model || t.plate)} · ${t.id}</b><span>${esc(t.mine ? t.shopLabel : t.customer_name || '')} · ${esc(t.last || (STATUS[t.status] || [t.status])[0])}</span></div></button>`).join('')
      : '<div class="empty"><i class="fa-regular fa-comment-dots"></i><b>No conversations</b><span>Every order has its own chat between the customer and the workshop.</span></div>'}</div>
    <div class="conv" id="conv">${cur == null ? '<div class="empty" style="margin:auto;border:0"><b>Pick a conversation</b></div>' : '<div class="empty" style="margin:auto;border:0"><i class="fa-solid fa-spinner fa-spin"></i></div>'}</div>
  </div>`;
  $$('[data-t]', pg).forEach((b) => (b.onclick = () => TabApps.messages(pg, +b.dataset.t, true)));
  if (cur == null) return;
  const r = await post('tab:messages', { id: cur });
  const conv = $('#conv');
  if (!conv || !r || !r.ok) { if (conv) conv.innerHTML = '<div class="empty" style="margin:auto;border:0"><b>Conversation unavailable</b></div>'; return; }
  const o = r.data.order;
  const meName = Tab.s.name;
  conv.innerHTML = `<div class="hd"><span class="lp">${esc(o.plate)}</span>${esc(o.label || '')}<span class="sp" style="flex:1"></span>${pill(o.status)}</div>
    <div class="msgs scroll" id="msgs">${r.data.rows.length ? r.data.rows.map((m) => {
      const me = m.me != null ? m.me : m.sender_name === meName;
      return `<div class="mrow ${me ? 'me' : ''}">${av(me ? Tab.s.avatar || m.avatar : m.avatar, m.sender_name, 'sm')}<div class="bub"><small>${esc(m.sender_name)} · ${new Date(m.t * 1000).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' })}</small>${esc(m.body)}</div></div>`;
    }).join('') : '<div class="muted" style="margin:auto;font-size:11.5px">No messages yet. Say hi.</div>'}</div>
    <div class="in"><input class="field grow" id="msgIn" maxlength="500" placeholder="Write a message" spellcheck="false"><button class="btn pri" id="msgGo"><i class="fa-solid fa-paper-plane"></i></button></div>`;
  const box = $('#msgs');
  box.scrollTop = box.scrollHeight;
  const send = async () => {
    const inp = $('#msgIn');
    const body = inp.value.trim();
    if (!body) return;
    inp.value = '';
    const res = await post('tab:send', { id: cur, body });
    if (!res || !res.ok) return Tab.toast((res && res.error) || 'Not sent.', true);
    TabApps.messages(pg, cur, true);
  };
  $('#msgGo').onclick = send;
  $('#msgIn').onkeydown = (e) => { if (e.key === 'Enter') send(); };
  $('#msgIn').focus();
};

/* ---------- my work ---------- */
TabApps.work = async function (pg) {
  pg.innerHTML = '<div class="empty"><i class="fa-solid fa-spinner fa-spin"></i></div>';
  const d = await post('tab:myWork');
  if (Tab.app !== 'work' || !d) return;
  pg.innerHTML = `<div class="kgrid" style="grid-template-columns:repeat(3,1fr)"><div class="k"><small><i class="fa-solid fa-screwdriver-wrench"></i>Parts fitted</small><b>${d.installs}</b></div><div class="k"><small><i class="fa-solid fa-sack-dollar"></i>Commission</small><b>${money(d.earned)}</b></div><div class="k"><small><i class="fa-solid fa-calendar-week"></i>Jobs this week</small><b>${d.week}</b></div></div>
    ${d.rows.length ? `<table class="tbl"><thead><tr><th>Job</th><th>Car</th><th>Customer</th><th>Parts</th><th style="text-align:right">Total</th></tr></thead><tbody>${d.rows.map((r) => `<tr><td><b>${r.id}</b><div class="muted" style="font-size:10px;margin-top:2px">${new Date(r.t * 1000).toLocaleDateString()}</div></td><td><span class="lp">${esc(r.plate)}</span><div class="muted" style="font-size:10px;margin-top:4px">${esc(r.shopLabel)}</div></td><td>${esc(r.customer_name || '-')}</td><td><div class="chips">${(r.items || []).slice(0, 4).map((i) => `<span class="tag">${esc(i.label)}</span>`).join('')}${(r.items || []).length > 4 ? `<span class="tag">+${r.items.length - 4}</span>` : ''}</div></td><td style="text-align:right"><b>${money(r.total)}</b></td></tr>`).join('')}</tbody></table>`
      : '<div class="empty"><i class="fa-solid fa-wrench"></i><b>No jobs yet</b><span>Finished jobs show up here.</span></div>'}`;
};

/* ---------- my cars ---------- */
TabApps.cars = async function (pg) {
  pg.innerHTML = '<div class="empty"><i class="fa-solid fa-spinner fa-spin"></i></div>';
  const [list, car] = await Promise.all([post('tab:myCars'), post('tab:car')]);
  if (Tab.app !== 'cars') return;
  const cars = list || [];
  pg.innerHTML = `${car && car.driver && Tab.s.assists ? `<div class="panel" style="margin-bottom:12px"><h4><i class="fa-solid fa-car-burst"></i>Driver assists<span>${esc(car.label)} · ${esc(car.plate)}</span></h4><div class="hrow"><button class="btn" data-as="tcs"><i class="fa-solid fa-road-circle-check"></i>Toggle TCS</button><button class="btn" data-as="esc"><i class="fa-solid fa-arrows-spin"></i>Toggle ESC</button><span class="muted" style="font-size:10.5px">Also /tcs and /esc</span></div></div>` : ''}
    ${cars.length ? cars.map((c) => `<div class="carcard"><div class="hrow"><span style="width:42px;height:42px;border-radius:11px;display:grid;place-items:center;background:var(--acc-wash);color:var(--acc)"><i class="fa-solid fa-car"></i></span>
      <div class="grow"><b style="font-size:13.5px;color:#fff">${esc(c.label)}</b><div class="hrow" style="margin-top:5px"><span class="lp">${esc(c.plate)}</span><span class="muted" style="font-size:10.5px">${Math.round(c.km).toLocaleString('en-US')} km${c.lastShop ? ' · last at ' + esc(c.lastShop) : ''}</span></div></div>
      ${c.locator ? `<button class="btn sm" data-loc="${esc(c.plate)}"><i class="fa-solid fa-location-crosshairs"></i>Locate</button>` : ''}</div>
      <div class="chips" style="margin-top:10px">${c.ecu ? '<span class="tag t">ECU</span>' : ''}${c.swap ? `<span class="tag t">${esc(c.swap)}</span>` : ''}${c.manual ? '<span class="tag">Manual</span>' : ''}${c.drive && c.drive !== 'stock' ? `<span class="tag">${esc(c.drive.toUpperCase())}</span>` : ''}${c.tyres && c.tyres !== 'stock' ? `<span class="tag">${esc(cap(c.tyres))} tyres</span>` : ''}${c.nitrous ? `<span class="tag t">NOS ${Math.round(c.nitrous.amount || 0)}</span>` : ''}${c.tcs ? '<span class="tag">TCS</span>' : ''}${c.esc ? '<span class="tag">ESC</span>' : ''}</div>
      ${c.wear ? `<div style="margin-top:10px">${meter(Object.entries(c.wear).map(([k, v]) => [cap(k), v]))}</div>` : ''}</div>`).join('')
      : '<div class="empty"><i class="fa-solid fa-car"></i><b>No cars found</b></div>'}`;
  $$('[data-loc]', pg).forEach((b) => (b.onclick = async () => { const r = await post('tab:locate', { plate: b.dataset.loc, route: true }); Tab.toast(r && r.ok ? `Signal near ${r.street}. Route set.` : (r && r.error) || 'No signal.', !(r && r.ok)); }));
  $$('[data-as]', pg).forEach((b) => (b.onclick = async () => { const r = await post('tab:assist', { which: b.dataset.as }); if (!r || !r.ok) Tab.toast((r && r.error) || 'Get in the driver seat.', true); }));
};

/* ---------- my orders ---------- */
TabApps.myorders = async function (pg) {
  pg.innerHTML = '<div class="empty"><i class="fa-solid fa-spinner fa-spin"></i></div>';
  const list = (await post('tab:myOrders')) || [];
  if (Tab.app !== 'myorders') return;
  pg.innerHTML = list.length ? list.map((o) => `<div class="ocard"><div class="top"><span class="lp">${esc(o.plate)}</span><div class="tx"><b>${esc(o.label || o.model || o.plate)}</b><span>${esc(o.shopLabel)}${o.mechanic_name ? ' · ' + esc(o.mechanic_name) : ''} · job ${o.id}</span></div>
      ${pill(o.status)}<b>${money(o.total)}</b><button class="btn sm" data-m="${o.id}"><i class="fa-regular fa-comment-dots"></i></button>${o.status === 'open' ? `<button class="btn sm warn" data-c="${o.id}">Cancel</button>` : ''}</div>
      <div class="prog"><i style="width:${o.count ? (o.done / o.count) * 100 : 0}%"></i></div></div>`).join('')
    : '<div class="empty"><i class="fa-solid fa-receipt"></i><b>No orders</b><span>Choose "Order" at a staffed tuning shop and a mechanic fits the parts for you.</span></div>';
  $$('[data-m]', pg).forEach((b) => (b.onclick = () => Tab.go('messages', +b.dataset.m)));
  $$('[data-c]', pg).forEach((b) => (b.onclick = async () => {
    const r = await post('tab:cancelOrder', { id: +b.dataset.c });
    Tab.toast(r && r.ok ? 'Order cancelled and refunded.' : (r && r.error) || 'Could not cancel.', !(r && r.ok));
    TabApps.myorders(pg);
  }));
};

/* ---------- settings ---------- */
TabApps.settings = function (pg) {
  const s = Tab.s;
  let acc = s.settings.accent, wall = s.settings.wallpaper;
  pg.innerHTML = `<div class="panel"><h4><i class="fa-solid fa-user"></i>Profile</h4><div class="hrow" style="gap:14px">${av(s.avatar, s.name, 'lg')}<div><b style="font-size:15px;color:#fff">${esc(s.name)}</b><div class="muted" style="font-size:11px;margin-top:4px">${esc(s.job)}${s.grade ? ' · ' + esc(s.grade) : ''}${s.shop ? ' · ' + esc(s.shop.label) : ''}</div><div class="muted" style="font-size:10.5px;margin-top:6px">${s.avatar ? 'Picture synced from Discord' : 'Link Discord to FiveM to show your Discord picture'}</div></div></div></div>
    <div class="panel" style="margin-top:10px"><h4><i class="fa-solid fa-palette"></i>Accent colour</h4><div class="accs">${s.accents.map((c) => `<button data-c="${c}" style="background:${c}" class="${c === acc ? 'on' : ''}"></button>`).join('')}</div></div>
    <div class="panel" style="margin-top:10px"><h4><i class="fa-solid fa-image"></i>Wallpaper</h4><div class="wps">${WALLPAPERS.map(([id, n]) => `<button data-w="${id}" class="wp-${id} ${id === wall ? 'on' : ''}"><span>${n}</span></button>`).join('')}</div>
      ${s.customWallpaper ? `<div class="hrow" style="margin-top:10px"><input class="field grow" id="wpUrl" placeholder="Image link (allowed hosts only)" value="${/^https?:/.test(wall) ? esc(wall) : ''}" spellcheck="false"><button class="btn" id="wpUse">Use</button></div>` : ''}</div>`;
  const save = async () => {
    Tab.theme(acc, wall);
    const r = await post('tab:settings', { accent: acc, wallpaper: wall });
    if (!r || !r.ok) return Tab.toast((r && r.error) || 'Not saved.', true);
    s.settings.accent = acc; s.settings.wallpaper = wall;
  };
  $$('[data-c]', pg).forEach((b) => (b.onclick = () => { acc = b.dataset.c; $$('[data-c]', pg).forEach((x) => x.classList.toggle('on', x === b)); save(); }));
  $$('[data-w]', pg).forEach((b) => (b.onclick = () => { wall = b.dataset.w; $$('[data-w]', pg).forEach((x) => x.classList.toggle('on', x === b)); save(); }));
  const u = $('#wpUse');
  if (u) u.onclick = () => { const v = $('#wpUrl').value.trim(); if (/^https?:\/\//.test(v)) { wall = v; save(); } };
};
