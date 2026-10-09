/* ═══════════════════════════════════════════════════════════
   WIG SNATCH V3 · making wigs from materials + the supplier
   ═══════════════════════════════════════════════════════════ */
'use strict';

Object.assign(S, { wsMode: 'make', mk: null, shop: null });

/* ─────────────── make a wig ─────────────── */
async function loadMake(m) {
  const prev = S.mk || {};
  const info = await post('craftInfo', { m: m || prev.m });
  if (!info || !info.laces) { S.mk = { off: true }; S.wsMode = 'bundles'; return; }
  const laces = arr(info.laces);
  const styles = arr(info.styles);
  const keep = prev.m === info.m;
  S.mk = Object.assign({ q: '', length: 18, c: 2, h: 2, t: 0 }, keep ? prev : { m: info.m }, {
    info, m: info.m, styles, shots: new Set(arr(info.shots)),
  });
  if (!keep || !styles.some((s) => s.d === S.mk.d)) S.mk.d = styles.length ? styles[0].d : null;
  if (!S.mk.lace || !laces.some((l) => l.id === S.mk.lace && !l.locked)) S.mk.lace = (laces.find((l) => !l.locked) || laces[0] || {}).id;
  const [lo, hi] = arr(info.lengths);
  S.mk.length = clamp(S.mk.length, lo || 10, hi || 30);
  if (info.palette) S.palette = arr(info.palette);
}

function mkRecipe() {
  const mk = S.mk, i = mk.info, out = {};
  const add = (k, n) => (out[k] = (out[k] || 0) + n);
  Object.entries(i.base || {}).forEach(([k, n]) => add(k, n));
  add(i.weft, Math.ceil(mk.length / (i.weftInches || 6)));
  const lace = arr(i.laces).find((l) => l.id === mk.lace);
  if (lace) Object.entries(lace.items || {}).forEach(([k, n]) => add(k, n));
  if (!arr(i.natural).includes(mk.c)) add(i.dye, 1);
  return { items: out, lace };
}

const mkShot = (m, d) => `../shots/wig_${m}_${d}_0.png`;
const mkThumb = (m, d, has) => has
  ? `<img src="${mkShot(m, d)}" alt="" loading="lazy" onerror="this.replaceWith(Object.assign(document.createElement('i'),{className:'fa-solid fa-scissors'}))">`
  : '<i class="fa-solid fa-scissors"></i>';

function makeView(bench, away) {
  const mk = S.mk;
  if (!mk) return `<div class="wig-list">${bench}<div class="empty"><i class="fa-solid fa-circle-notch fa-spin"></i>Laying out the materials</div></div>`;
  if (mk.off) return `<div class="wig-list">${bench}<div class="empty"><i class="fa-solid fa-lock"></i>Making wigs from materials is off on this server</div></div>`;
  const i = mk.info, q = mk.q.trim().toLowerCase();
  const list = mk.styles.filter((s) => !q || String(s.d) === q || String(s.name || '').toLowerCase().includes(q));
  const cur = mk.styles.find((s) => s.d === mk.d);
  const { items, lace } = mkRecipe();
  const rows = Object.entries(items);
  const missing = rows.filter(([k, n]) => (i.have[k] || 0) < n);
  const ready = cur && lace && !lace.locked && !missing.length && !away;
  const pal = S.palette || [];
  const sw = (field) => `<div class="palette">${pal.map((hex, n) => `<button class="pal ${mk[field] === n ? 'on' : ''}" style="background:${hex}" data-act="mkCol" data-v="${field}:${n}" title="${n}"></button>`).join('')}</div>`;
  const [lo, hi] = arr(i.lengths);
  const t = lace ? tier(lace.tier) : null;

  return `<div class="wig-list">${bench}
      <div class="sec-h"><h3>Pick a hairstyle</h3><span>${mk.styles.length} ${mk.m === 'm' ? 'male' : 'female'} hairstyles · any in the city</span></div>
      <div class="mk-bar">
        <div class="seg">${[['f', 'Female'], ['m', 'Male']].map(([k, l]) => `<button class="${mk.m === k ? 'on' : ''}" data-act="mkModel" data-v="${k}">${l}</button>`).join('')}</div>
        <label class="field"><i class="fa-solid fa-magnifying-glass"></i><input id="mkSearch" placeholder="Search by name or number" value="${esc(mk.q)}"></label>
      </div>
      <div class="mk-grid">${list.map((s) => `<button class="mk-style ${s.d === mk.d ? 'on' : ''}" data-act="mkPick" data-v="${s.d}">
          <span class="mk-th">${mkThumb(mk.m, s.d, mk.shots.has(`${mk.m}/${s.d}_0`))}</span>
          <b>${esc(s.name || 'Hairstyle ' + s.d)}</b><small>#${s.d}${s.n > 1 ? ` · ${s.n} textures` : ''}</small></button>`).join('')
        || '<div class="empty" style="grid-column:1/-1"><i class="fa-solid fa-magnifying-glass"></i>Nothing matches</div>'}</div>
    </div>
    <div class="detail">
      <div class="card mk-card">
        <div class="mk-prev"><span class="mk-th lg">${cur ? mkThumb(mk.m, cur.d, mk.shots.has(`${mk.m}/${cur.d}_0`)) : ''}</span>
          <div><b>${cur ? esc(cur.name || 'Hairstyle ' + cur.d) : 'Pick a hairstyle'}</b>
          <small>${cur ? `${mk.m === 'm' ? 'Male' : 'Female'} · #${cur.d}` : ''}</small>
          ${t ? `<span class="chip" style="${tintVars(t.color)};color:var(--c);border-color:var(--ce);background:var(--cw)">${esc(t.label)} · ${money(lace.price[0])}–${money(lace.price[1])}</span>` : ''}</div></div>
        ${cur && cur.n > 1 ? `<div class="sub-h">Texture</div><div class="mk-tex">${Array.from({ length: Math.min(cur.n, 16) }, (_, n) => `<button class="${mk.t === n ? 'on' : ''}" data-act="mkTex" data-v="${n}">${n + 1}</button>`).join('')}</div>` : ''}
        <div class="sub-h">Length <b class="mk-len" id="mkLenV">${mk.length}"</b></div>
        <input type="range" id="mkLen" min="${lo || 10}" max="${hi || 30}" step="2" value="${mk.length}">
        <div class="sub-h">Lace</div>
        <div class="pick mk-lace">${arr(i.laces).map((l) => { const lt = tier(l.tier); return `<button class="${mk.lace === l.id ? 'on' : ''}" data-act="mkLace" data-v="${l.id}" ${l.locked ? 'disabled' : ''} style="${tintVars(lt.color)}">
            <span class="dot" style="background:var(--c)"></span>${esc(l.label)}<small>${l.locked ? `<i class="fa-solid fa-lock"></i> Level ${l.level}` : esc(lt.label)}</small></button>`; }).join('')}</div>
      </div>
      <div class="card mk-card">
        <div class="sec-h" style="margin:0"><h3>Materials</h3><span>${missing.length ? `${missing.length} missing` : 'All here'}</span></div>
        <div class="mk-mats">${rows.map(([k, n]) => { const have = i.have[k] || 0, ok = have >= n; return `<div class="${ok ? 'ok' : 'no'}">
          <i class="fa-solid ${ok ? 'fa-check' : 'fa-xmark'}"></i><span>${esc((i.labels || {})[k] || k)}</span><b>${have} / ${n}</b></div>`; }).join('')}</div>
        ${missing.length && i.supplier ? `<div class="note">Buy materials from <b>${esc(i.supplier)}</b> (on your map).</div>` : ''}
        <button class="btn teal wide" data-act="mkGo" ${ready ? '' : 'disabled'} style="margin-top:12px"><i class="fa-solid fa-screwdriver-wrench"></i>${away ? 'Make wigs at a wig table' : S.bench ? 'Make it at the table' : 'Make wig'}</button>
      </div>
      <div class="card mk-card">
        <div class="sub-h" style="margin-top:0">Colour${arr(i.natural).includes(mk.c) ? '' : ' <em>needs a hair dye</em>'}</div>${sw('c')}
        <div class="sub-h">Highlight</div>${sw('h')}
      </div>
    </div>`;
}

function rerenderMake() {
  const s = $('#mkSearch'), had = s && document.activeElement === s;
  const scroll = $('.mk-grid') ? $('.mk-grid').closest('.wig-list').scrollTop : 0;
  $('#vview').innerHTML = workshopView(); paintSwatches(body);
  const wl = $('.mk-grid') && $('.mk-grid').closest('.wig-list'); if (wl) wl.scrollTop = scroll;
  if (had) { const n = $('#mkSearch'); n.focus(); n.setSelectionRange(n.value.length, n.value.length); }
}

Object.assign(ACT, {
  wsMode: async (v) => { S.wsMode = v; rerenderMake(); if (v === 'make' && !S.mk) { await loadMake(); rerenderMake(); } },
  mkModel: async (v) => { S.mk.m = v; await loadMake(v); rerenderMake(); },
  mkPick: (v) => { S.mk.d = Number(v); S.mk.t = 0; rerenderMake(); },
  mkTex: (v) => { S.mk.t = Number(v); rerenderMake(); },
  mkLace: (v) => { S.mk.lace = v; rerenderMake(); },
  mkCol: (v) => { const [f, n] = v.split(':'); S.mk[f] = Number(n); rerenderMake(); },
  mkGo: () => {
    const mk = S.mk;
    post('make', { m: mk.m, d: mk.d, t: mk.t, length: mk.length, lace: mk.lace, c: mk.c, h: mk.h, view: S.camView });
    closeApp(true);
  },
});

app.addEventListener('input', (e) => {
  if (e.target.id === 'mkSearch') { S.mk.q = e.target.value; rerenderMake(); }
  if (e.target.id === 'mkLen') { S.mk.length = Number(e.target.value); $('#mkLenV').textContent = S.mk.length + '"'; }
});
app.addEventListener('change', (e) => { if (e.target.id === 'mkLen') rerenderMake(); });

/* ─────────────── supplier shop ─────────────── */
const itemImg = (name) => `https://cfx-nui-ox_inventory/web/images/${name}.png`;

function renderShop() {
  const sh = S.shop, cart = sh.cart;
  const lines = arr(sh.items).filter((it) => cart[it.name] > 0);
  const total = lines.reduce((a, it) => a + it.price * cart[it.name], 0);
  setHead(sh.title, `Level ${sh.level} · ${money(sh.money)} ${sh.account === 'bank' ? 'in the bank' : 'cash'}`,
    `<span><span class="kc">ESC</span>Close</span><span>Up to ${sh.max} of each per order</span>`);
  body.innerHTML = `<div class="view split">
    <div class="wig-list"><div class="sec-h"><h3>Wig making supplies</h3><span>${arr(sh.items).length} items</span></div>
      <div class="shop-grid">${arr(sh.items).map((it) => `<div class="shop-item ${it.locked ? 'locked' : ''} ${cart[it.name] ? 'on' : ''}">
        <div class="shop-img"><img src="${itemImg(it.name)}" alt="" onerror="this.replaceWith(Object.assign(document.createElement('i'),{className:'fa-solid fa-box'}))"></div>
        <b>${esc(it.label)}</b><small>${it.locked ? `<i class="fa-solid fa-lock"></i> Level ${it.level}` : `You have ${it.have}`}</small>
        <div class="shop-row"><span class="shop-price">${money(it.price)}</span>
          ${it.locked ? '' : `<div class="qty"><button data-act="shopQty" data-v="${it.name}:-1">−</button><span>${cart[it.name] || 0}</span><button data-act="shopQty" data-v="${it.name}:1">+</button></div>`}</div>
      </div>`).join('')}</div></div>
    <div class="detail"><div class="card">
      <div class="sec-h" style="margin:0 0 10px"><h3>Order</h3><span>${lines.length} line${lines.length === 1 ? '' : 's'}</span></div>
      ${lines.length ? `<div class="mk-mats">${lines.map((it) => `<div class="ok"><span>${cart[it.name]} × ${esc(it.label)}</span><b>${money(it.price * cart[it.name])}</b></div>`).join('')}</div>`
        : '<div class="empty" style="padding:18px"><i class="fa-solid fa-basket-shopping"></i>Nothing picked yet</div>'}
      <div class="shop-total"><span>Total</span><b>${money(total)}</b></div>
      <button class="btn teal wide" data-act="shopBuy" ${lines.length && total <= sh.money ? '' : 'disabled'}><i class="fa-solid fa-bag-shopping"></i>${total > sh.money ? "Can't afford it" : 'Buy'}</button>
      ${lines.length ? '<button class="btn ghost wide" data-act="shopClear" style="margin-top:6px">Clear</button>' : ''}
    </div></div></div>`;
}

Object.assign(ACT, {
  shopQty: (v) => {
    const [name, d] = v.split(':');
    S.shop.cart[name] = clamp((S.shop.cart[name] || 0) + Number(d), 0, S.shop.max);
    renderShop();
  },
  shopClear: () => { S.shop.cart = {}; renderShop(); },
  shopBuy: async () => {
    const r = await post('shopBuy', { cart: S.shop.cart });
    if (r && r.ok) {
      arr(S.shop.items).forEach((it) => { it.have += S.shop.cart[it.name] || 0; });
      S.shop.cart = {};
      if (r.money !== undefined && r.money !== null) S.shop.money = r.money;
    }
    renderShop();
  },
});
