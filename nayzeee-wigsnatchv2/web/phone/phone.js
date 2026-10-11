/* ═══════════════════════════════════════════════════════════
   HAIR PLUG · phone app
   Runs inside lb-phone / YSeries / qs-smartphone.
   Talks to nayzeee-wigsnatchv2 through its NUI callbacks.
   ═══════════════════════════════════════════════════════════ */
'use strict';

const RES = (() => {
  const h = location.hostname || '';
  if (h.startsWith('cfx-nui-')) return h.slice(8);
  return typeof GetParentResourceName === 'function' ? GetParentResourceName() : null;
})();

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
function hexRgb(hex) { const n = parseInt(String(hex || '#08afa2').replace('#', ''), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; }
function mix(hex, to, k) { const a = hexRgb(hex), b = hexRgb(to); return '#' + a.map((v, i) => Math.round(v + (b[i] - v) * k).toString(16).padStart(2, '0')).join(''); }
function tint(hex) { const [r, g, b] = hexRgb(hex); return `--c:${hex};--cw:rgba(${r},${g},${b},.11);--ce:rgba(${r},${g},${b},.34);--cg:rgba(${r},${g},${b},.17);--cc:${hex}`; }

const A = { d: null, tab: 'sell', sel: new Set(), mkt: 'browse', timer: 0, skew: 0 };
const now = () => Math.floor(Date.now() / 1000 + A.skew);
function leftOf(ts) { const s = Math.max(0, ts - now()); const m = Math.floor(s / 60); return m >= 60 ? `${Math.floor(m / 60)}h ${m % 60}m` : `${m}m ${s % 60}s`; }
function ago(ts) { const d = Math.max(0, now() - ts); return d < 3600 ? Math.floor(d / 60) + 'm ago' : d < 86400 ? Math.floor(d / 3600) + 'h ago' : Math.floor(d / 86400) + 'd ago'; }

/* ─────────────── prefs (player colours) ─────────────── */
function applyPrefs(p) {
  if (!p) return;
  const st = document.documentElement.style;
  const set = (name, hex) => {
    if (!/^#[0-9a-f]{6}$/i.test(hex || '')) return;
    const [r, g, b] = hexRgb(hex);
    st.setProperty(`--${name}`, hex); st.setProperty(`--${name}-rgb`, `${r},${g},${b}`);
    st.setProperty(`--${name}-hi`, mix(hex, '#ffffff', 0.2)); st.setProperty(`--${name}-lo`, mix(hex, '#000000', 0.3));
    st.setProperty(`--${name}-wash`, `rgba(${r},${g},${b},.11)`); st.setProperty(`--${name}-edge`, `rgba(${r},${g},${b},.34)`);
  };
  set('teal', p.accent); set('red', p.alert);
  const [r, g, b] = hexRgb(p.accent).map((v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; });
  st.setProperty('--on-accent', (0.2126 * r + 0.7152 * g + 0.0722 * b) > 0.38 ? '#061413' : '#ffffff');
}

/* ─────────────── data ─────────────── */
function tierOf(id) { return arr(A.d && A.d.tiers).find((t) => t.id === id) || { id, label: id || 'Wig', color: '#a7aeb3' }; }
function gradeOf(id) { return arr(A.d && A.d.grades).find((g) => g.id === id) || { id, label: id || 'Hair' }; }
function colorOf(w) { return w.kind === 'bundle' ? '#c9a27a' : (w.tint || tierOf(w.tier).color); }
function tagOf(w) { return w.kind === 'bundle' ? gradeOf(w.grade).label : (w.tierLabel || tierOf(w.tier).label); }
function titleOf(w) { return w.generic ? (w.kind === 'bundle' ? 'Hair bundle' : 'Wig') : `${w.length}" ${w.style}`; }
function subOf(w) {
  if (w.kind === 'bundle') return `Bundle · from ${w.from || 'unknown'}`;
  return [w.lace, w.dyed ? 'dyed' : '', w.burnt ? 'burnt' : '', `${w.cond ?? 100}%`].filter(Boolean).join(' · ');
}
function swatch(w) { const p = A.d && A.d.palette; return p && w.color !== undefined && p[w.color] ? `<span class="sw" style="background:${p[w.color]}"></span>` : ''; }
function thumb(w, cls = 'g-img') {
  return `<div class="${cls}">${w.image ? `<img src="${esc(w.image)}" alt="" onerror="this.replaceWith(Object.assign(document.createElement('i'),{className:'fa-solid ${w.kind === 'bundle' ? 'fa-wind' : 'fa-crown'}'}))">` : `<i class="fa-solid ${w.kind === 'bundle' ? 'fa-wind' : 'fa-crown'}"></i>`}</div>`;
}

async function load() {
  const d = await post('phoneData');
  if (!d) { if (!A.d) $('#phMain').innerHTML = `<div class="ph-empty"><i class="fa-solid fa-signal"></i>No signal</div>`; return; }
  A.d = d;
  A.skew = (d.now || Date.now() / 1000) - Date.now() / 1000;
  const keys = new Set(arr(d.goods).map((g) => g.key));
  [...A.sel].forEach((k) => { if (!keys.has(k)) A.sel.delete(k); });
  $('#phSub').textContent = `${d.me.title} · ${money(d.me.money)} cash${d.me.perk ? ` · +${d.me.perk}% title bonus` : ''}`;
  render();
}

/* ─────────────── render ─────────────── */
function render() {
  const d = A.d; if (!d) return;
  $$('#phTabs button').forEach((b) => b.classList.toggle('on', b.dataset.tab === A.tab));
  $$('#phTabs button').forEach((b) => {
    const t = b.dataset.tab;
    if (t === 'market' && !d.listings) b.hidden = true;
    if (t === 'orders' && !d.orders) b.hidden = true;
  });
  renderDeal();
  const main = $('#phMain');
  main.innerHTML = (VIEW[A.tab] || VIEW.sell)();
  bar();
}

function renderDeal() {
  const deal = A.d.meetup && A.d.meetup.deal;
  const el = $('#phDeal');
  if (!deal) { el.hidden = true; return; }
  el.hidden = false;
  el.innerHTML = `<div class="ic"><i class="fa-solid ${deal.arrived ? 'fa-handshake' : 'fa-person-running'}"></i></div>
    <div><b>${deal.arrived ? 'Your buyer is here' : 'Buyer on the way'}</b><span>${deal.count} item${deal.count === 1 ? '' : 's'} · ${money(deal.total)} · ${deal.arrived ? 'go hand it over' : 'stay where you are'}</span></div><span class="pulse"></span>`;
}

const VIEW = {
  sell() {
    const goods = arr(A.d.goods);
    if (!goods.length) return `<div class="ph-empty"><i class="fa-solid fa-box-open"></i>Nothing to sell. Go snatch something, or snip some bundles.</div>`;
    const total = goods.reduce((a, g) => a + (g.value || 0), 0);
    return `<div class="h"><h3>${goods.length} item${goods.length === 1 ? '' : 's'}</h3><span>Worth ${money(total)} at full price</span></div>
      <div class="goods">${goods.map((g) => `<button class="good ${A.sel.has(g.key) ? 'sel' : ''}" style="${tint(colorOf(g))}" data-sel="${esc(g.key)}">
        <span class="check"><i class="fa-solid fa-check"></i></span>${thumb(g)}
        <div class="g-tx"><div class="g-tag">${esc(tagOf(g))}</div><div class="g-name">${esc(titleOf(g))}</div><div class="g-sub">${swatch(g)}${esc(subOf(g))}</div>
          <div class="g-val">${money(g.value)}<small data-info="${esc(g.key)}"><i class="fa-solid fa-circle-info"></i></small></div></div></button>`).join('')}</div>`;
  },

  market() {
    const L = A.d.listings;
    const seg = `<div class="seg"><button class="${A.mkt === 'browse' ? 'on' : ''}" data-mkt="browse">Browse</button><button class="${A.mkt === 'mine' ? 'on' : ''}" data-mkt="mine">My listings (${arr(L.mine).filter((x) => x.status === 'open').length}/${L.max})</button></div>`;
    if (A.mkt === 'mine') {
      const mine = arr(L.mine);
      return seg + (mine.length ? `<div class="list">${mine.map((x) => listingRow(x, true)).join('')}</div>` : `<div class="ph-empty"><i class="fa-solid fa-tag"></i>Nothing listed. Pick something on the Sell tab and list it.</div>`)
        + `<div class="card"><h4>How listings work</h4><p>The server holds your item until someone buys it. You get the price minus a ${Math.round(L.fee * 100)}% fee, even if you're offline. Unsold items come back after ${L.hours}h.</p></div>`;
    }
    const others = arr(L.market).filter((x) => !x.mine);
    return seg + (others.length ? `<div class="list">${others.map((x) => listingRow(x, false)).join('')}</div>` : `<div class="ph-empty"><i class="fa-solid fa-store"></i>The market is empty right now</div>`);
  },

  orders() {
    const os = arr(A.d.orders);
    if (!os.length) return `<div class="ph-empty"><i class="fa-solid fa-clipboard-list"></i>No orders right now</div>`;
    return `<div class="h"><h3>Buyers looking</h3><span>First come, first served</span></div><div class="list">${os.map((o) => {
      const c = o.kind === 'bundle' ? '#c9a27a' : tierOf(o.tier).color;
      const want = o.kind === 'bundle'
        ? `a <b>${esc(gradeOf(o.grade).label)}+</b> bundle, <b>${o.length}"</b> or longer`
        : `a <b>${esc(tierOf(o.tier).label)}+</b> wig${o.style ? ` in <b>${esc(o.style)}</b>` : ''}${o.fits ? ` for a <b>${o.fits === 'm' ? 'man' : 'woman'}</b>` : ''}`;
      return `<div class="order" style="${tint(c)}">
        <div class="order-top"><div class="order-who"><div class="av">${esc(o.from.slice(0, 2).toUpperCase())}</div><div><b>${esc(o.from)}</b><span>Order #${o.id}</span></div></div><span class="mult">${o.mult.toFixed(2)}×</span></div>
        <p>Looking for ${want}. Pays ${o.mult.toFixed(2)}× what it's worth.</p>
        <div class="order-foot"><span><i class="fa-regular fa-clock"></i> ${leftOf(o.expires)}</span><button class="btn sm teal" data-order="${o.id}"><i class="fa-solid fa-paper-plane"></i>Fill order</button></div>
      </div>`;
    }).join('')}</div>`;
  },

  prices() {
    const d = A.d;
    const rows = arr(d.demand).map((m) => {
      const isB = m.id === 'bundle';
      const c = isB ? '#c9a27a' : tierOf(m.id).color;
      const col = m.demand >= 80 ? 'var(--teal)' : m.demand >= 60 ? '#e5a50a' : 'var(--red)';
      return `<div class="dem-row" style="${tint(c)};--cc:${col}"><span>${esc(isB ? 'Bundles' : tierOf(m.id).label)}</span><div class="b"><i style="width:${m.demand}%"></i></div><b>${m.demand}%</b></div>`;
    }).join('');
    const rate = (label, r) => r ? `<div class="rate"><span>${label}</span><b>${Math.round(r * 100)}%</b></div>` : '';
    return `<div class="h"><h3>Market demand</h3><span>Drops as the city sells, then recovers</span></div><div class="dem">${rows}</div>
      <div class="card"><h4>Payout by option</h4><div class="rates">
        ${d.quick ? rate('Quick sell', d.quick.rate) : ''}${d.meetup ? rate('Meet-up', d.meetup.rate) : ''}
        ${d.listings ? `<div class="rate"><span>Listing fee</span><b>${Math.round(d.listings.fee * 100)}%</b></div>` : ''}
        ${d.orders ? `<div class="rate"><span>Orders</span><b>Bonus</b></div>` : ''}</div></div>
      <div class="card"><h4>Hair pricing</h4><p>Every wig starts at its tier's base price, then condition, how many hands it went through, dye, burns and today's demand move it. Tap <i class="fa-solid fa-circle-info"></i> on any item to see the full breakdown.</p></div>`;
  },
};

function listingRow(x, mine) {
  const st = x.status === 'open' ? `<span class="tag live">Live</span>` : x.status === 'sold' ? `<span class="tag hot">Sold${x.buyer ? ' · ' + esc(x.buyer) : ''}</span>` : `<span class="tag off">${esc(x.status)}</span>`;
  return `<div class="item" style="${tint(colorOf(x))}">${thumb(x, 'thumb')}
    <div class="tx"><b>${esc(titleOf(x))}</b><span>${esc(tagOf(x))} · ${mine ? st : 'by ' + esc(x.seller)} · ${ago(x.created)}</span></div>
    <div class="amt"><b>${money(x.price)}</b>${mine
      ? (x.status === 'open' ? `<button class="btn sm red" data-cancel="${x.listing}">Take down</button>` : '')
      : `<button class="btn sm teal" data-buy="${x.listing}">Buy</button>`}</div></div>`;
}

/* bottom bar when something is selected on the Sell tab */
function bar() {
  const old = $('.bar'); if (old) old.remove();
  if (A.tab !== 'sell' || !A.sel.size) return;
  const picked = arr(A.d.goods).filter((g) => A.sel.has(g.key));
  const total = picked.reduce((a, g) => a + g.value, 0);
  const el = document.createElement('div');
  el.className = 'bar';
  el.innerHTML = `<div class="t"><span>${picked.length} selected</span><b>${money(total)}</b></div><button class="btn ghost sm" data-clear>Clear</button><button class="btn teal" data-sellopts><i class="fa-solid fa-sack-dollar"></i>Sell</button>`;
  $('#ph').appendChild(el);
}

/* ─────────────── sheets ─────────────── */
function sheet(html) {
  const s = $('#phSheet');
  s.innerHTML = `<div class="sheet"><div class="grab"></div>${html}</div>`;
  s.hidden = false;
}
function closeSheet() { $('#phSheet').hidden = true; $('#phSheet').innerHTML = ''; }
$('#phSheet').addEventListener('click', (e) => { if (e.target.id === 'phSheet') closeSheet(); });

function sellSheet() {
  const d = A.d;
  const picked = arr(d.goods).filter((g) => A.sel.has(g.key));
  const full = picked.reduce((a, g) => a + g.value, 0);
  const one = picked.length === 1 ? picked[0] : null;
  const cd = d.meetup && d.meetup.cooldown;
  const opt = (id, icon, color, title, sub, amt, note, off) => `<button class="opt" style="${tint(color)}" data-opt="${id}" ${off ? 'disabled' : ''}>
    <div class="ic"><i class="fa-solid ${icon}"></i></div><div class="tx"><b>${title}</b><span>${sub}</span></div><div class="amt"><b>${amt}</b><small>${note}</small></div></button>`;
  sheet(`<h4>Sell ${picked.length} item${picked.length === 1 ? '' : 's'}</h4><p>Pick how you want to get paid.</p>
    <div class="opts">
      ${d.quick ? opt('quick', 'fa-bolt', '#e5a50a', 'Quick sell', 'Paid right now, from anywhere', money(full * d.quick.rate), Math.round(d.quick.rate * 100) + '%') : ''}
      ${d.meetup ? opt('meetup', 'fa-person-running', '#08afa2', 'Meet-up', cd ? `Buyer is busy for ${Math.ceil(cd / 60)}m` : (d.meetup.dirty ? 'Pays dirty · ' : '') + 'He runs to you, hand it over', money(full * d.meetup.rate), Math.round(d.meetup.rate * 100) + '%', cd > 0 || (d.meetup.deal)) : ''}
      ${d.listings ? opt('list', 'fa-tag', '#3d9bff', 'List on the market', one ? 'Set your own price, sell to players' : 'Pick one item to list it', 'Your price', `-${Math.round(d.listings.fee * 100)}% fee`, !one || !d.hasMeta) : ''}
    </div>
    <div class="row2"><button class="btn ghost" data-close>Cancel</button></div>`);
}

function listSheet(g) {
  const L = A.d.listings;
  sheet(`<div class="hero">${thumb(g)}<div><h4>${esc(titleOf(g))}</h4><p>${esc(tagOf(g))} · worth ${money(g.value)}</p></div></div>
    <label class="field"><i class="fa-solid fa-dollar-sign"></i><input id="lp" inputmode="numeric" placeholder="${L.min} - ${L.maxPrice}" value="${Math.round(g.value * 1.2)}"></label>
    <p>You get <b id="lpNet" style="color:var(--white)">${money(g.value * 1.2 * (1 - L.fee))}</b> after the ${Math.round(L.fee * 100)}% fee. It comes back after ${L.hours}h if nobody buys it.</p>
    <div class="row2"><button class="btn ghost" data-close>Cancel</button><button class="btn teal" data-dolist="${esc(g.key)}"><i class="fa-solid fa-tag"></i>List it</button></div>`);
  const input = $('#lp');
  input.addEventListener('input', () => { input.value = input.value.replace(/[^\d]/g, '').slice(0, 7); $('#lpNet').textContent = money((Number(input.value) || 0) * (1 - L.fee)); });
}

function infoSheet(g) {
  const p = g.pricing || {};
  const mult = (label, v) => v === undefined || v === 1 ? '' : `<div><span>${label}</span><b class="${v > 1 ? 'up' : 'down'}">×${Number(v).toFixed(2)}</b></div>`;
  const rows = g.kind === 'bundle'
    ? `<div><span>${g.length}" of hair</span><b>${money(p.base)}</b></div>${mult('Grade (' + esc(gradeOf(g.grade).label) + ')', p.grade)}${mult('Demand', p.demand)}${mult('Your title', 1 + (p.perk || 0))}`
    : `<div><span>${esc(tagOf(g))} base</span><b>${money(p.base)}</b></div>${mult('Condition ' + (g.cond ?? 100) + '%', p.condition)}${mult('Changed hands ' + (g.hops || 0) + 'x', p.infamy)}${mult('Dyed', p.dye)}${mult('Burnt', p.burnt)}${mult('Demand', p.demand)}${mult('Your title', 1 + (p.perk || 0))}`;
  sheet(`<div class="hero">${thumb(g)}<div><h4>${esc(titleOf(g))}</h4><p>${esc(tagOf(g))}${g.kind === 'bundle' ? '' : ' · ' + esc(g.lace || '')}${g.from ? ' · from ' + esc(g.from) : ''}</p></div></div>
    <div class="price">${rows}<div><span>Hair price</span><b>${money(p.total ?? g.value)}</b></div></div>
    <div class="row2"><button class="btn ghost" data-close>Close</button></div>`);
}

async function orderSheet(id) {
  const o = arr(A.d.orders).find((x) => x.id === id);
  if (!o) return;
  const fits = new Set(arr(await post('phoneOrderFits', { order: id })));
  const goods = arr(A.d.goods).filter((g) => fits.has(g.key));
  sheet(`<h4>${esc(o.from)}'s order</h4><p>Pick what to send. Pays ${o.mult.toFixed(2)}× its value.</p>
    ${goods.length ? `<div class="list" style="margin-top:12px">${goods.map((g) => `<button class="item" style="${tint(colorOf(g))}" data-fill="${esc(g.key)}" data-oid="${id}">${thumb(g, 'thumb')}
      <div class="tx"><b>${esc(titleOf(g))}</b><span>${esc(tagOf(g))} · ${esc(subOf(g))}</span></div><div class="amt"><b>${money(g.value * o.mult)}</b><small>${money(g.value)} × ${o.mult.toFixed(2)}</small></div></button>`).join('')}</div>`
      : `<div class="ph-empty"><i class="fa-solid fa-magnifying-glass"></i>Nothing you have matches</div>`}
    <div class="row2"><button class="btn ghost" data-close>Close</button></div>`);
}

/* ─────────────── actions ─────────────── */
function cash() { post('phoneCash'); }

async function act(name, data, keepSel) {
  const r = await post(name, data);
  closeSheet();
  if (r && r.ok) { if (!keepSel) A.sel.clear(); cash(); }
  await load();
}

document.addEventListener('click', async (e) => {
  const t = e.target;
  const info = t.closest('[data-info]');
  if (info) { e.stopPropagation(); const g = arr(A.d.goods).find((x) => x.key === info.dataset.info); return g && infoSheet(g); }
  const tab = t.closest('[data-tab]');
  if (tab) { A.tab = tab.dataset.tab; closeSheet(); return render(); }
  const sel = t.closest('[data-sel]');
  if (sel) { const k = sel.dataset.sel; A.sel.has(k) ? A.sel.delete(k) : A.sel.add(k); return render(); }
  if (t.closest('[data-clear]')) { A.sel.clear(); return render(); }
  if (t.closest('[data-sellopts]')) return sellSheet();
  if (t.closest('[data-close]')) return closeSheet();
  const opt = t.closest('[data-opt]');
  if (opt) {
    const keys = [...A.sel];
    if (opt.dataset.opt === 'quick') return act('phoneQuickSell', { keys });
    if (opt.dataset.opt === 'meetup') return act('phoneMeetup', { keys });
    if (opt.dataset.opt === 'list') { const g = arr(A.d.goods).find((x) => x.key === keys[0]); return g && listSheet(g); }
  }
  const dl = t.closest('[data-dolist]');
  if (dl) return act('phoneList', { key: dl.dataset.dolist, price: Number(($('#lp') || {}).value || 0) });
  const mk = t.closest('[data-mkt]');
  if (mk) { A.mkt = mk.dataset.mkt; return render(); }
  const buy = t.closest('[data-buy]');
  if (buy) {
    const x = arr(A.d.listings.market).find((l) => String(l.listing) === buy.dataset.buy);
    return x && sheet(`<div class="hero">${thumb(x)}<div><h4>${esc(titleOf(x))}</h4><p>${esc(tagOf(x))} · from ${esc(x.seller)}</p></div></div>
      <div class="price"><div><span>Price</span><b>${money(x.price)}</b></div><div><span>Paid from</span><b>Bank</b></div></div>
      <div class="row2"><button class="btn ghost" data-close>Cancel</button><button class="btn teal" data-dobuy="${x.listing}"><i class="fa-solid fa-cart-shopping"></i>Buy</button></div>`);
  }
  const db = t.closest('[data-dobuy]');
  if (db) return act('phoneBuy', { id: Number(db.dataset.dobuy) }, true);
  const cc = t.closest('[data-cancel]');
  if (cc) return act('phoneCancel', { id: Number(cc.dataset.cancel) }, true);
  const od = t.closest('[data-order]');
  if (od) return orderSheet(Number(od.dataset.order));
  const fill = t.closest('[data-fill]');
  if (fill) return act('phoneOrder', { order: Number(fill.dataset.oid), key: fill.dataset.fill });
});

/* messages pushed from the game (lb-phone SendCustomAppMessage) */
addEventListener('message', (e) => {
  const m = e.data || {};
  if (m.type === 'refresh') load();
  if (m.type === 'prefs') applyPrefs(m.prefs);
});

(async function boot() {
  applyPrefs(await post('prefs'));
  await load();
  // phones without push messages: poll while the app is on screen
  A.timer = setInterval(() => { if (document.visibilityState !== 'hidden') load(); }, 8000);
})();
