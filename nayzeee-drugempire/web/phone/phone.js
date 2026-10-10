/* ═══════════════════════════════════════════════════════════
   EMPIRE · phone app
   Messages · Journal · Products · Contacts · Map · Dealers · Deliveries
   Runs inside lb-phone / YSeries / qs-smartphone, or on screen through /empire.
   Talks to nayzeee-drugempire through its NUI callbacks.
   ═══════════════════════════════════════════════════════════ */
'use strict';

const RES = (() => {
  const h = location.hostname || '';
  if (h.startsWith('cfx-nui-')) return h.slice(8);
  return typeof GetParentResourceName === 'function' ? GetParentResourceName() : null;
})();
const STANDALONE = new URLSearchParams(location.search).get('host') === 'nui';

async function post(name, data = {}) {
  if (!RES) return window.Mock ? window.Mock.handle(name, data) : null;
  try {
    const r = await fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data) });
    const t = await r.text();
    return t ? JSON.parse(t) : null;
  } catch (e) { return null; }
}

const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const money = (n) => '$' + Math.round(Number(n) || 0).toLocaleString('en-US');
const arr = (v) => (Array.isArray(v) ? v : v && typeof v === 'object' ? Object.values(v) : []);
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const I = (n) => window.Icons.svg(n);

const A = { d: null, view: 'home', stack: [], thread: null, shop: null, cart: {}, drop: null, account: null, skew: 0 };
const now = () => Date.now() / 1000 + A.skew;
function leftOf(ts) { const s = Math.max(0, Math.floor(ts - now())); const m = Math.floor(s / 60); return m >= 60 ? `${Math.floor(m / 60)}h ${m % 60}m` : `${m}m ${String(s % 60).padStart(2, '0')}s`; }
function ago(ts) { const d = Math.max(0, now() - ts); return d < 60 ? 'now' : d < 3600 ? Math.floor(d / 60) + 'm' : d < 86400 ? Math.floor(d / 3600) + 'h' : Math.floor(d / 86400) + 'd'; }

const VIEWS = {
  messages: { title: 'Messages', icon: 'msg', c: '#3fb950' },
  journal: { title: 'Journal', icon: 'book', c: '#e5a50a' },
  products: { title: 'Products', icon: 'leaf', c: '#0fd4c4' },
  contacts: { title: 'Contacts', icon: 'users', c: '#58a6ff' },
  map: { title: 'Map', icon: 'map', c: '#a371f7' },
  dealers: { title: 'Dealers', icon: 'crew', c: '#f78166' },
  deliveries: { title: 'Deliveries', icon: 'truck', c: '#e3b341' },
};
const KIND_ICON = { weed: 'leaf', meth: 'crystal', shroom: 'shroom', coke: 'powder' };

function eff(e) { const x = A.d && A.d.effects && A.d.effects[e]; return { label: x ? x.label : e, color: x ? x.color : '#9ea5aa' }; }
function chips(list) { return `<div class="chips">${arr(list).map((e) => { const x = eff(e); return `<span class="chip" style="--c:${x.color}">${esc(x.label)}</span>`; }).join('') || '<span class="chip off">No effects</span>'}</div>`; }
function regionLabel(id) { const r = arr(A.d && A.d.regions).find((x) => x.id === id); return r ? r.label : id; }
function spotLabel(id) { const s = A.d && A.d.spots && A.d.spots[id]; return s ? s.label : id; }
function relLabel(r) { return r >= 4 ? 'Loyal' : r >= 3 ? 'Friendly' : r >= 2 ? 'Neutral' : r >= 1 ? 'Unfriendly' : 'Hostile'; }
function stdLabel(id) { const s = arr(A.d && A.d.standards).find((x) => x.id === id); return s ? s.label : '?'; }

function toast(msg, bad) {
  const t = $('#phToast');
  t.textContent = msg; t.className = 'ph-toast' + (bad ? ' bad' : ''); t.hidden = false;
  clearTimeout(toast._t); toast._t = setTimeout(() => t.hidden = true, 2400);
}
async function act(name, data, okMsg) {
  const r = await post(name, data);
  if (!r) { toast('No signal', true); return null; }
  if (r.ok === false) { toast(typeof r.res === 'string' ? r.res : 'That didn\'t work', true); return null; }
  if (okMsg) toast(okMsg);
  await load();
  return r.res === undefined ? true : r.res;
}
function gps(x, y, label) { post('waypoint', { x, y }); toast('GPS set' + (label ? ': ' + label : '')); }

/* ─────────────── sheet ─────────────── */
function sheet(html, bind) {
  const s = $('#phSheet');
  s.innerHTML = `<div class="sheet"><div class="grab"></div>${html}</div>`;
  s.hidden = false;
  s.onclick = (e) => { if (e.target === s) closeSheet(); };
  if (bind) bind($('.sheet', s));
}
function closeSheet() { $('#phSheet').hidden = true; $('#phSheet').innerHTML = ''; }

/* ─────────────── navigation ─────────────── */
function go(view, extra) {
  if (view !== A.view) A.stack.push(A.view);
  A.view = view;
  Object.assign(A, extra || {});
  if (view === 'contacts') post('phoneTab', { tab: 'contacts' });
  render();
}
function back() {
  if (A.view === 'thread') { A.view = 'messages'; A.thread = null; } else { A.view = A.stack.pop() || 'home'; }
  render();
}

async function load() {
  const d = await post('phoneData');
  if (!d) { if (!A.d) $('#phMain').innerHTML = `<div class="ph-empty">${I('phone')}No signal</div>`; return; }
  A.d = d;
  A.skew = (d.now || Date.now() / 1000) - Date.now() / 1000;
  render();
}

/* ─────────────── views ─────────────── */
function vHome(d) {
  const me = d.me;
  const pct = me.need ? clamp(me.xp / me.need * 100, 0, 100) : 100;
  const unread = arr(d.threads).reduce((a, t) => a + (t.unread || 0), 0);
  const offers = arr(d.deals).filter((x) => x.state === 'offer').length;
  const badges = { messages: unread, dealers: arr(d.dealers).filter((x) => x.hired && x.cash > 0).length, deliveries: arr(d.deliveries.orders).filter((o) => !o.done && o.ready <= now()).length };
  const accepted = arr(d.deals).filter((x) => x.state === 'accepted');
  return `<div class="rank"><small>Rank</small><b>${esc(me.rank)}</b><div class="track"><i style="width:${pct}%"></i></div>
      <div class="meta"><span>${me.need ? `${me.xp} / ${me.need} XP` : 'Max rank'}</span><span>${me.nextRank ? 'Next: ' + esc(me.nextRank) : ''}</span></div></div>
    <div class="stats"><div><span>Earned</span><b>${money(me.stats.earned)}</b></div><div><span>Units sold</span><b>${me.stats.sold}</b></div><div><span>Deals</span><b>${me.stats.deals}</b></div></div>
    <div class="h"><h3>Apps</h3><span>${offers ? offers + ' deal request' + (offers > 1 ? 's' : '') : ''}</span></div>
    <div class="apps">${Object.entries(VIEWS).map(([k, v]) => `<button class="app" data-go="${k}" style="--c:${v.c}"><div class="ic">${I(v.icon)}</div>${v.title}${badges[k] ? `<span class="badge">${badges[k]}</span>` : ''}</button>`).join('')}
      <button class="app" data-go="rv" style="--c:#c9d1d9"><div class="ic">${I('rv')}</div>RV</button></div>
    ${accepted.length ? `<div class="h"><h3>Accepted deals</h3></div><div class="list">${accepted.map(dealRow).join('')}</div>` : ''}
    <div class="h"><h3>Watering can</h3><span>${me.water} / ${me.cap} L</span></div>`;
}

function dealRow(x) {
  return `<button class="row" data-deal="${esc(x.id)}"><div class="av" style="--c:var(--green)">${I('handshake')}</div><div class="tx"><b>${esc(x.name)} · ${x.qty}x ${esc(x.product)}</b><span>${esc(x.spotLabel)} · ${x.exp > now() ? leftOf(x.exp) + ' left' : 'late'}</span></div><div class="end"><b>${money(x.price)}</b></div></button>`;
}

function vMessages(d) {
  const list = arr(d.threads);
  if (!list.length) return `<div class="ph-empty">${I('msg')}<b>No messages</b>Customers will text you here.</div>`;
  return `<div class="list">${list.map((t) => `<button class="row" data-thread="${esc(t.id)}"><div class="av ${t.icon === 'wheel' ? 'teal' : ''}">${t.icon === 'user' ? esc((t.name || '?')[0]) : I(t.icon === 'crew' ? 'crew' : t.icon === 'unknown' ? 'unknown' : 'wheel')}</div>
    <div class="tx"><b>${esc(t.name)}</b><span>${esc(t.last)}</span></div><div class="end"><small>${ago(t.t)}</small>${t.unread ? '<div class="dotu" style="margin:6px 0 0 auto"></div>' : ''}</div></button>`).join('')}</div>`;
}

function vThread(d) {
  const t = arr(d.threads).find((x) => x.id === A.thread);
  if (!t) return `<div class="ph-empty">Gone</div>`;
  const deals = Object.fromEntries(arr(d.deals).map((x) => [x.id, x]));
  const out = [];
  for (const m of arr(t.msgs)) {
    out.push(`<div class="bub ${m.f === 'me' ? 'me' : ''}">${esc(m.m)}<small>${ago(m.t)}</small></div>`);
    if (m.deal) {
      const x = deals[m.deal];
      if (x) {
        out.push(`<div class="deal"><div class="top"><b>${x.qty}x ${esc(x.product)}</b><span class="price">${money(x.price)}</span></div>
          <p>${esc(x.spotLabel)} · ${x.exp > now() ? leftOf(x.exp) + ' left' : 'expired'}</p>
          ${x.state === 'offer' ? `<div class="btns"><button class="btn green sm" data-ans="accept" data-id="${esc(x.id)}">Accept</button>${x.countered ? '' : `<button class="btn sm" data-ans="counter" data-id="${esc(x.id)}">Counter</button>`}<button class="btn red sm" data-ans="decline" data-id="${esc(x.id)}">Decline</button></div>`
            : `<div class="state">Accepted</div><div class="btns"><button class="btn sm" data-gps-spot="${esc(x.spot)}">Set GPS</button></div>`}</div>`);
      }
    }
  }
  return `<div class="chat">${out.join('')}</div>`;
}

function vJournal(d) {
  const q = arr(d.journal);
  if (!q.length) return `<div class="ph-empty">${I('book')}<b>All done</b>You've finished Benson's journal.</div>`;
  return q.slice().reverse().map((x) => {
    const cur = x.steps.findIndex((s) => !s.done);
    return `<div class="quest ${x.done ? 'done' : ''}"><h4><span class="star">${I('star')}</span>${esc(x.title)}</h4>${x.steps.map((s, i) => `<div class="step ${s.done ? 'done' : i === cur ? 'cur' : ''}"><i>${s.done ? I('check') : ''}</i>${esc(s.text)}${s.need && i === cur ? ` (${s.n || 0}/${s.need})` : ''}</div>`).join('')}</div>`;
  }).join('');
}

function vProducts(d) {
  const list = arr(d.products);
  if (!list.length) return `<div class="ph-empty">${I('leaf')}<b>No products yet</b>Grow or cook something and it shows up here.</div>`;
  const groups = {};
  for (const p of list) (groups[p.kind] = groups[p.kind] || []).push(p);
  return arr(d.kinds).filter((k) => groups[k.id]).map((k) => `<div class="h"><h3>${esc(k.label)}</h3><span>${groups[k.id].length}</span></div><div class="list">${groups[k.id].map((p) => `
    <button class="row" data-product="${esc(p.id)}"><div class="av" style="--c:${(A.d.drugs || {})[p.base] ? A.d.drugs[p.base].color : 'var(--teal)'}">${I(KIND_ICON[p.kind])}</div>
    <div class="tx"><b>${esc(p.name)}</b>${chips(p.effects)}</div><div class="end"><b>${money(p.price)}</b><small>worth ${money(p.value)}</small></div></button>`).join('')}</div>`).join('');
}

function vContacts(d) {
  const list = arr(d.contacts);
  if (!list.length) return `<div class="ph-empty">${I('users')}<b>No contacts</b></div>`;
  const mine = list.filter((c) => c.unlocked), avail = list.filter((c) => !c.unlocked);
  const row = (c) => `<button class="row ${c.target ? 'on' : ''}" data-contact="${esc(c.id)}"><div class="av" style="--c:${c.unlocked ? 'var(--white)' : 'var(--ink-3)'}">${esc(c.name[0])}</div>
    <div class="tx"><b>${esc(c.name)}${c.dealer ? ' <span class="chip">Dealer</span>' : ''}</b><span>${esc(regionLabel(c.region))} · ${c.unlocked ? relLabel(c.rel) : c.target ? 'Sample pending' : 'Not a customer yet'}</span></div>
    <div class="end"><small>★ ${esc(stdLabel(c.standards))}</small></div></button>`;
  return `<div class="h"><h3>Customers</h3><span>${mine.length}</span></div><div class="list">${mine.map(row).join('') || '<div class="ph-empty">None yet</div>'}</div>
    ${avail.length ? `<div class="h"><h3>Give them a sample</h3><span>${avail.length}</span></div><div class="list">${avail.map(row).join('')}</div>` : ''}`;
}

/* rough San Andreas silhouette for the map (world units) */
const COAST = [[-1800, -3700], [900, -3500], [1500, -2600], [2600, -1500], [3000, -200], [3600, 1500], [3900, 3600], [3700, 5200], [2800, 6400], [1700, 6900], [300, 7600], [-500, 6900], [-1600, 6100], [-2600, 4700], [-3200, 3200], [-3300, 1500], [-2900, 300], [-2500, -600], [-2700, -1700], [-2200, -3000]];
const BOUNDS = { x0: -3800, x1: 4400, y0: -4000, y1: 8000 };
function mx(x) { return (x - BOUNDS.x0) / (BOUNDS.x1 - BOUNDS.x0) * 300; }
function my(y) { return (BOUNDS.y1 - y) / (BOUNDS.y1 - BOUNDS.y0) * 420; }
const PIN = { rv: '#c9d1d9', benson: '#0fd4c4', deal: '#3fb950', customer: '#58a6ff', sample: '#e5a50a', dealer: '#f78166', drop: '#e3b341' };

function vMap(d) {
  const m = d.map;
  const coast = COAST.map(([x, y]) => `${mx(x).toFixed(1)},${my(y).toFixed(1)}`).join(' ');
  const grid = [];
  for (let gx = -3000; gx <= 4000; gx += 1000) grid.push(`<line x1="${mx(gx)}" y1="0" x2="${mx(gx)}" y2="420" />`);
  for (let gy = -3000; gy <= 7000; gy += 1000) grid.push(`<line x1="0" y1="${my(gy)}" x2="300" y2="${my(gy)}" />`);
  const regions = arr(m.regions).map((r) => `<text x="${mx(r.x)}" y="${my(r.y)}" fill="${r.locked ? '#3a4044' : '#7d868b'}" font-size="7" text-anchor="middle" font-weight="600" letter-spacing=".5">${esc(r.label.toUpperCase())}</text>`).join('');
  const pins = arr(m.pins).map((p, i) => `<g data-pin="${i}" style="cursor:pointer"><circle cx="${mx(p.x)}" cy="${my(p.y)}" r="9" fill="transparent"/><circle cx="${mx(p.x)}" cy="${my(p.y)}" r="${p.kind === 'rv' || p.kind === 'deal' ? 4.2 : 3.2}" fill="${PIN[p.kind] || '#fff'}" stroke="#000" stroke-width="1"/></g>`).join('');
  return `<div class="map"><svg viewBox="0 0 300 420"><rect width="300" height="420" fill="#0b1418"/>
    <polygon points="${coast}" fill="#161c1f" stroke="#2a3337" stroke-width="1"/>
    <ellipse cx="${mx(1000)}" cy="${my(4000)}" rx="${mx(1800) - mx(1000)}" ry="${my(3700) - my(4000)}" fill="#0b1418" stroke="#2a3337" stroke-width=".8"/>
    <g stroke="rgba(255,255,255,.035)" stroke-width=".6">${grid.join('')}</g>${regions}${pins}</svg></div>
    <div class="legend">${Object.entries({ rv: 'RV', deal: 'Deal', customer: 'Customer', sample: 'Sample', dealer: 'Dealer', drop: 'Drop', benson: 'Benson' }).map(([k, v]) => `<span><i style="background:${PIN[k]}"></i>${v}</span>`).join('')}</div>
    <div class="h"><h3>Places</h3></div><div class="list">${arr(m.pins).map((p, i) => `<button class="row" data-pin="${i}"><div class="av" style="--c:${PIN[p.kind]}">${I('pin')}</div><div class="tx"><b>${esc(p.label)}</b><span>${esc(p.sub || '')}${p.kind === 'drop' ? (p.ready ? ' · Ready' : ' · On the way') : ''}</span></div></button>`).join('')}</div>`;
}

function vDealers(d) {
  return `<div class="list">${arr(d.dealers).map((x) => {
    const locked = d.me.level < x.unlock;
    return `<button class="row ${locked ? 'dim' : ''} ${x.hired ? 'on' : ''}" data-dealer="${esc(x.id)}"><div class="av" style="--c:${x.hired ? 'var(--teal-hi)' : 'var(--ink-3)'}">${I('crew')}</div>
      <div class="tx"><b>${esc(x.name)}</b><span>${esc(regionLabel(x.region))} · ${x.hired ? `${x.customers.length}/${x.max} customers · ${x.units} units` : locked ? 'Locked' : `Hire for ${money(x.fee)}`}</span></div>
      <div class="end">${x.hired ? `<b>${money(x.cash)}</b><small>to collect</small>` : `<small>${Math.round(x.cut * 100)}% cut</small>`}</div></button>`;
  }).join('')}</div>`;
}

function vDeliveries(d) {
  const dv = d.deliveries;
  A.shop = A.shop || (dv.shops[0] && dv.shops[0].id);
  const shop = dv.shops.find((s) => s.id === A.shop);
  A.account = A.account || dv.accounts[0];
  const drops = dv.drops.filter((x) => !x.locked);
  A.drop = A.drop || (drops[0] && drops[0].id) || 'rv';
  let total = 0;
  for (const it of shop.items) total += (A.cart[it.item] || 0) * it.price;
  if (total > 0 && A.drop === 'rv') total += dv.rvFee;
  const open = dv.orders.filter((o) => !o.done);
  return `<div class="tabs">${dv.shops.map((s) => `<button data-shop="${esc(s.id)}" class="${s.id === A.shop ? 'on' : ''}">${esc(s.label)}</button>`).join('')}</div>
    <p style="font-size:11px;color:var(--ink-3);margin:9px 2px 10px;font-weight:300">${esc(shop.desc)}</p>
    <div class="list">${shop.items.map((it) => `<div class="row ${it.locked ? 'dim' : ''}"><div class="tx"><b>${esc(it.label)}</b><span>${it.locked ? 'Unlocks at ' + esc(it.rank) : money(it.price) + ' each'}</span></div>
      ${it.locked ? '' : `<div class="qty"><button data-dec="${esc(it.item)}">−</button><b>${A.cart[it.item] || 0}</b><button data-inc="${esc(it.item)}">+</button></div>`}</div>`).join('')}</div>
    ${open.length ? `<div class="h"><h3>Orders</h3></div><div class="list">${open.map((o) => `<div class="row"><div class="av" style="--c:${o.ready <= now() ? 'var(--green)' : 'var(--amber)'}">${I('box')}</div><div class="tx"><b>${esc(o.shop)} · ${money(o.total)}</b><span>${esc(o.dropLabel)} · ${o.ready <= now() ? 'Ready to collect' : leftOf(o.ready)}</span></div></div>`).join('')}</div>` : ''}
    <div class="cart"><div class="t"><span>Total${A.drop === 'rv' && total ? ` (incl. ${money(dv.rvFee)} RV fee)` : ''}</span><b>${money(total)}</b></div>
      <select id="dropSel">${drops.map((x) => `<option value="${esc(x.id)}" ${x.id === A.drop ? 'selected' : ''}>Dead drop: ${esc(x.label)}</option>`).join('')}<option value="rv" ${A.drop === 'rv' ? 'selected' : ''}>Your RV (+${money(dv.rvFee)})</option></select>
      <select id="accSel">${dv.accounts.map((a) => `<option value="${esc(a)}" ${a === A.account ? 'selected' : ''}>Pay with ${esc(a)}</option>`).join('')}</select>
      <button class="btn teal wide" id="orderBtn" style="margin-top:9px" ${total ? '' : 'disabled'}>${I('truck')}Place order</button></div>`;
}

function vRv(d) {
  const rvPin = arr(d.map.pins).find((p) => p.kind === 'rv');
  return `<div class="rank"><small>Your RV</small><b>${d.rv.owned ? (d.rv.exists ? 'Parked' : 'Missing') : 'None'}</b><div class="meta"><span>${d.rv.owned ? 'Go in through the back to reach the lab' : 'Benson will sort you out'}</span></div></div>
    ${d.rv.owned ? `<div class="btns"><button class="btn" id="rvLocate" ${rvPin ? '' : 'disabled'}>${I('pin')}Locate</button><button class="btn red" id="rvTow">${I('truck')}Tow (${money(d.rv.towFee)})</button></div>` : ''}`;
}

/* ─────────────── render ─────────────── */
function render() {
  const d = A.d; if (!d) return;
  const main = $('#phMain');
  if (d.locked) { main.innerHTML = `<div class="ph-empty">${I('lock')}<b>Not installed</b>Somebody has to put you on first.</div>`; return; }
  const v = A.view;
  const titles = Object.assign({ home: 'Empire', thread: (arr(d.threads).find((t) => t.id === A.thread) || {}).name || 'Messages', rv: 'RV' }, Object.fromEntries(Object.entries(VIEWS).map(([k, x]) => [k, x.title])));
  $('#phTitle').textContent = titles[v] || 'Empire';
  $('#phSub').textContent = v === 'home' ? `${d.me.name || ''} · ${d.me.rank}` : d.me.rank;
  $('#phBack').hidden = v === 'home';
  const fn = { home: vHome, messages: vMessages, thread: vThread, journal: vJournal, products: vProducts, contacts: vContacts, map: vMap, dealers: vDealers, deliveries: vDeliveries, rv: vRv }[v] || vHome;
  const keepScroll = main.dataset.view === v ? main.scrollTop : 0;
  main.innerHTML = fn(d);
  main.dataset.view = v;
  main.scrollTop = v === 'thread' ? main.scrollHeight : keepScroll;
  bind(main);
}

function bind(main) {
  const d = A.d;
  $$('[data-go]', main).forEach((b) => b.onclick = () => go(b.dataset.go));
  $$('[data-thread]', main).forEach((b) => b.onclick = () => { post('phoneRead', { thread: b.dataset.thread }); const t = arr(d.threads).find((x) => x.id === b.dataset.thread); if (t) t.unread = 0; go('thread', { thread: b.dataset.thread }); });
  $$('[data-deal]', main).forEach((b) => b.onclick = () => { const x = arr(d.deals).find((y) => y.id === b.dataset.deal); if (x) go('thread', { thread: x.cid }); });
  $$('[data-gps-spot]', main).forEach((b) => b.onclick = () => { const p = arr(d.map.pins).find((x) => x.kind === 'deal' && x.sub === spotLabel(b.dataset.gpsSpot)); if (p) gps(p.x, p.y, p.sub); });
  $$('[data-ans]', main).forEach((b) => b.onclick = () => {
    const id = b.dataset.id, ans = b.dataset.ans;
    if (ans !== 'counter') return act('dealRespond', { id, answer: ans }, ans === 'accept' ? 'Deal accepted' : 'Declined');
    const x = arr(d.deals).find((y) => y.id === id);
    sheet(`<h4>Counter offer</h4><p>They offered ${money(x.price)} for ${x.qty}x ${esc(x.product)}. Ask too much and they walk.</p>
      <div class="field">$<input id="ctr" type="number" min="1" value="${Math.round(x.price * 1.15)}"></div><div class="btns"><button class="btn" id="cx">Cancel</button><button class="btn teal" id="cs">Send</button></div>`, (s) => {
      $('#cx', s).onclick = closeSheet;
      $('#cs', s).onclick = async () => { const p = +$('#ctr', s).value; closeSheet(); await act('dealRespond', { id, answer: 'counter', price: p }); };
    });
  });
  $$('[data-product]', main).forEach((b) => b.onclick = () => {
    const p = arr(d.products).find((x) => x.id === b.dataset.product);
    sheet(`<h4>${esc(p.name)}</h4><p>Worth ${money(p.value)} per unit · addictiveness ${Math.round(p.addictive * 100)}%</p>${chips(p.effects)}
      <div class="field">Asking $<input id="pp" type="number" min="1" value="${p.price}"></div><p>Customers see this price in deal requests. Up to 3x the value.</p>
      <div class="btns"><button class="btn" id="px">Close</button><button class="btn teal" id="ps">Save price</button></div>`, (s) => {
      $('#px', s).onclick = closeSheet;
      $('#ps', s).onclick = async () => { const v = +$('#pp', s).value; closeSheet(); await act('productPrice', { pid: p.id, price: v }, 'Price saved'); };
    });
  });
  $$('[data-contact]', main).forEach((b) => b.onclick = () => {
    const c = arr(d.contacts).find((x) => x.id === b.dataset.contact);
    const links = arr(c.links).map((l) => (arr(d.contacts).find((x) => x.id === l) || { name: l }).name).join(', ');
    sheet(`<h4>${esc(c.name)}</h4><p>${esc(regionLabel(c.region))} · hangs out ${esc(spotLabel(c.home)).toLowerCase()}</p>
      ${c.unlocked ? `<div class="kv"><span>Relationship</span><b>${relLabel(c.rel)}</b></div><div class="bar2"><i style="left:calc(${clamp(c.rel / 5 * 100, 0, 100)}% - 1px)"></i></div>
      <div class="kv"><span>Addiction</span><b>${Math.round(c.add * 100)}%</b></div><div class="bar3"><i style="width:${c.add * 100}%"></i></div>` : ''}
      <div class="kv"><span>Standards</span><b>★ ${esc(stdLabel(c.standards))}</b></div>
      <div class="kv"><span>Buys</span><b>${arr(c.buys).map((k) => (arr(d.kinds).find((x) => x.id === k) || { label: k }).label).join(', ')}</b></div>
      <div class="kv"><span>Favourite effects</span></div>${chips(c.favorites)}
      ${links ? `<div class="kv"><span>Knows</span><b>${esc(links)}</b></div>` : ''}
      <div class="btns">${c.unlocked ? `<button class="btn" id="cg">${I('pin')}Set GPS</button>` : c.target ? `<button class="btn red" id="cs0">Cancel sample</button>` : `<button class="btn teal" id="cs1">${I('leaf')}Offer a sample</button>`}</div>`, (s) => {
      const home = arr(d.map.pins).find((p) => p.kind === 'customer' && p.label === c.name);
      if ($('#cg', s)) $('#cg', s).onclick = () => { if (home) gps(home.x, home.y, c.name); closeSheet(); };
      if ($('#cs1', s)) $('#cs1', s).onclick = async () => { closeSheet(); await act('sampleTarget', { cid: c.id }, `Meet ${c.name} with a bagged sample`); };
      if ($('#cs0', s)) $('#cs0', s).onclick = async () => { closeSheet(); await act('sampleTarget', { cid: false }, 'Sample cancelled'); };
    });
  });
  $$('[data-pin]', main).forEach((b) => b.onclick = () => { const p = arr(d.map.pins)[+b.dataset.pin]; if (p) gps(p.x, p.y, p.label); });
  $$('[data-dealer]', main).forEach((b) => b.onclick = () => {
    const x = arr(d.dealers).find((y) => y.id === b.dataset.dealer);
    const locked = d.me.level < x.unlock;
    const mine = arr(d.contacts).filter((c) => c.unlocked);
    sheet(`<h4>${esc(x.name)}</h4><p>${esc(regionLabel(x.region))} · keeps ${Math.round(x.cut * 100)}% of every sale</p>
      ${x.hired ? `<div class="kv"><span>Cash to collect</span><b>${money(x.cash)}</b></div><div class="kv"><span>Stock</span><b>${x.units} units</b></div>
        ${x.stock.map((st) => `<div class="kv"><span>${esc(st.name)}</span><b>${st.n}</b></div>`).join('')}
        <div class="kv"><span>Customers (${x.customers.length}/${x.max})</span></div>
        <div class="list" style="margin-top:7px">${mine.map((c) => { const on = x.customers.includes(c.id); const other = c.dealer && c.dealer !== x.id; return `<button class="row ${on ? 'on' : ''} ${other ? 'dim' : ''}" data-assign="${esc(c.id)}" data-on="${on ? 0 : 1}" ${other ? 'disabled' : ''}><div class="tx"><b>${esc(c.name)}</b><span>${esc(regionLabel(c.region))}${other ? ' · another dealer' : ''}</span></div><div class="end"><small>${on ? 'Assigned' : 'Assign'}</small></div></button>`; }).join('')}</div>
        <p>Give them bagged product and collect cash in person.</p>
        <div class="btns"><button class="btn" id="dg">${I('pin')}Set GPS</button><button class="btn red" id="df">Fire</button></div>`
      : locked ? `<p>Unlocks later in your career.</p>` : `<div class="kv"><span>Signing fee</span><b>${money(x.fee)}</b></div><select id="dacc">${d.deliveries.accounts.map((a) => `<option value="${esc(a)}">Pay with ${esc(a)}</option>`).join('')}</select><div class="btns"><button class="btn teal" id="dh">${I('crew')}Hire ${esc(x.name)}</button></div>`}`, (s) => {
      if ($('#dh', s)) $('#dh', s).onclick = async () => { const account = $('#dacc', s).value; closeSheet(); await act('dealerHire', { id: x.id, account }, `${x.name} is working for you`); };
      if ($('#df', s)) $('#df', s).onclick = async () => { closeSheet(); await act('dealerFire', { id: x.id }, 'Dealer fired'); };
      if ($('#dg', s)) $('#dg', s).onclick = () => { gps(x.coords.x, x.coords.y, x.name); closeSheet(); };
      $$('[data-assign]', s).forEach((r) => r.onclick = async () => { closeSheet(); await act('dealerAssign', { id: x.id, cid: r.dataset.assign, on: r.dataset.on === '1' }); });
    });
  });
  $$('[data-shop]', main).forEach((b) => b.onclick = () => { A.shop = b.dataset.shop; A.cart = {}; render(); });
  $$('[data-inc]', main).forEach((b) => b.onclick = () => { A.cart[b.dataset.inc] = clamp((A.cart[b.dataset.inc] || 0) + 1, 0, 100); render(); });
  $$('[data-dec]', main).forEach((b) => b.onclick = () => { A.cart[b.dataset.dec] = clamp((A.cart[b.dataset.dec] || 0) - 1, 0, 100); render(); });
  const ds = $('#dropSel', main); if (ds) ds.onchange = () => { A.drop = ds.value; render(); };
  const as = $('#accSel', main); if (as) as.onchange = () => { A.account = as.value; };
  const ob = $('#orderBtn', main);
  if (ob) ob.onclick = async () => {
    const res = await act('orderPlace', { shop: A.shop, cart: A.cart, drop: A.drop, account: A.account });
    if (res) { A.cart = {}; toast(`Order placed. Ready in ~${res.minutes} min`); render(); }
  };
  const rl = $('#rvLocate', main); if (rl) rl.onclick = () => { const p = arr(d.map.pins).find((x) => x.kind === 'rv'); if (p) gps(p.x, p.y, 'RV'); };
  const rt = $('#rvTow', main); if (rt) rt.onclick = () => sheet(`<h4>Tow the RV</h4><p>Moves your RV to the nearest lot for ${money(d.rv.towFee)}.</p><select id="tacc">${d.deliveries.accounts.map((a) => `<option value="${esc(a)}">Pay with ${esc(a)}</option>`).join('')}</select><div class="btns"><button class="btn" id="tx">Cancel</button><button class="btn red" id="ty">Tow it</button></div>`, (s) => {
    $('#tx', s).onclick = closeSheet;
    $('#ty', s).onclick = async () => { const account = $('#tacc', s).value; closeSheet(); await act('rvTow', { account }, 'RV towed. Check your map.'); };
  });
}

/* ─────────────── boot ─────────────── */
$('#phBack').innerHTML = I('back');
$('#phBack').onclick = back;
if (STANDALONE) {
  $('#phClose').hidden = false;
  $('#phClose').innerHTML = I('x');
  $('#phClose').onclick = () => post('close', { what: 'phone' });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') post('close', { what: 'phone' }); });
}
window.addEventListener('message', (e) => {
  const m = e.data || {};
  if (m.type === 'refresh') load();
});
setInterval(() => { if (!document.hidden && A.d && (A.view === 'home' || A.view === 'thread' || A.view === 'deliveries')) render(); }, 15000);
load();
if (!RES) { const s = document.createElement('script'); s.src = 'preview.js'; document.body.appendChild(s); }
