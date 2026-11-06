/* ════════════════════════════════════════════════════════════════════════
   nayzeee-coinshop — player views: shell, shop pages, item / deal / redeem modals
   ════════════════════════════════════════════════════════════════════════ */
'use strict';

// ── shell ────────────────────────────────────────────────────────────────
function shell() {
  const bg = `<div class="shell-bg" style="${S.settings.bgImage ? `background-image:url('${esc(S.settings.bgImage)}')` : ''}"></div>`;
  if (S.loading || !S.me) {
    return `<div class="stage dim"><div class="frame win"><div class="shell">${bg}${bar()}
      <div class="body"><div class="main"><div class="empty" style="flex:1"><i class="fas fa-circle-notch fa-spin"></i><span>${esc(t('UI_LOADING'))}</span></div></div></div>
    </div></div></div>`;
  }
  const view = (VIEWS[S.page] || VIEWS.home)();
  const m = S.modal && MODALS[S.modal.type] ? MODALS[S.modal.type]() : '';
  return `<div class="stage dim"><div class="frame win"><div class="shell">${bg}
    ${bar()}
    <div class="body">${sidebar()}<div class="main">${view}</div></div>
    <div class="statusbar"><span><span class="key">ESC</span>${esc(t('UI_CLOSE'))}</span><span><i class="fas fa-circle-info"></i>${esc(t('UI_STATUS_HINT'))}</span></div>
    ${m}
  </div></div></div>`;
}

function bar() {
  const me = S.me;
  return `<div class="bar">
    <div class="bar-brand"><div class="mark"></div><div class="bar-title"><b>${esc(t('APP_TITLE'))}</b><span>${esc(t('APP_SUB'))}</span></div></div>
    <div class="bar-mid">${me ? `<div class="gsearch"><i class="fas fa-magnifying-glass"></i><input id="gsearch" placeholder="${esc(t('UI_SEARCH_ALL'))}" value="${esc(S.q)}" data-f="q" data-live="globalSearch" autocomplete="off"></div>` : ''}</div>
    ${me ? `<div class="wallet" title="${esc(t('UI_BALANCE'))}">${coin()}<b>${num(me.coins)}</b><button data-a="redeem" title="${esc(t('UI_REDEEM'))}"><i class="fas fa-plus"></i></button></div>` : ''}
    <span class="ver">v${esc(S.cfg ? S.cfg.version : '1.0.0')}</span>
    <button class="pill-close" data-a="close">${esc(t('UI_CLOSE'))}</button>
  </div>`;
}

function catItems(id) {
  if (id === 'all') return SHOP();
  if (id === 'favorites') return SHOP().filter(i => S.favs.has(i.id));
  if (id === 'sale') return SHOP().filter(i => i.sale);
  const c = S.cats.find(x => x.id === id);
  if (!c) return [];
  return c.type ? SHOP().filter(i => i.category === c.type) : SHOP().filter(i => i.customCategory === c.id);
}

function nav(page, cat, icon, label, tally, hot) {
  const on = S.page === page && (cat === undefined || S.cat === cat);
  return `<button class="nav ${on ? 'on' : ''}" data-a="go" data-v="${page}${cat !== undefined ? ':' + esc(cat) : ''}">${icon}<span class="lbl">${esc(label)}</span>${tally ? `<span class="tally ${hot ? 'hot' : ''}">${tally}</span>` : ''}</button>`;
}

function sidebar() {
  const me = S.me;
  const cats = S.cats.map(c => nav('browse', c.id, catIcon(c.icon, CAT_ICON[c.type] || 'fa-tag'), c.name, catItems(c.id).length)).join('');
  const sale = SHOP().filter(i => i.sale).length;
  return `<div class="side"><div class="side-scroll" data-keep="side">
    <div class="who">${avatar(me)}<div class="who-txt"><b>${esc(me.name)}</b><span>${esc(t('UI_WHO_SUB', me.serverId, num(me.spent)))}</span></div></div>
    <div class="grp">${esc(t('UI_SHOP'))}</div>
    ${nav('home', undefined, '<i class="fas fa-house"></i>', t('NAV_HOME'))}
    ${nav('browse', 'all', '<i class="fas fa-grip"></i>', t('NAV_ALL'), SHOP().length)}
    ${nav('deals', undefined, '<i class="fas fa-tags"></i>', t('NAV_DEALS'), S.deals.length || '', true)}
    ${sale ? nav('browse', 'sale', '<i class="fas fa-percent"></i>', t('NAV_SALE'), sale, true) : ''}
    ${nav('browse', 'favorites', '<i class="fas fa-heart"></i>', t('NAV_FAVORITES'), S.favs.size || '')}
    ${S.cats.length ? `<div class="grp">${esc(t('UI_CATEGORIES'))}</div>${cats}` : ''}
    <div class="grp">${esc(t('UI_ACCOUNT'))}</div>
    ${nav('history', undefined, '<i class="fas fa-receipt"></i>', t('NAV_HISTORY'))}
    <button class="nav" data-a="redeem"><i class="fas fa-ticket"></i><span class="lbl">${esc(t('NAV_REDEEM'))}</span></button>
    ${S.cfg.transfer ? `<button class="nav" data-a="transfer"><i class="fas fa-paper-plane"></i><span class="lbl">${esc(t('NAV_TRANSFER'))}</span></button>` : ''}
    ${nav('tutorial', undefined, '<i class="fas fa-circle-question"></i>', t('NAV_TUTORIAL'))}
    ${S.admin ? `<div class="grp">${esc(t('UI_STAFF'))}</div>${nav('admin', undefined, '<i class="fas fa-shield-halved"></i>', t('NAV_ADMIN'))}` : ''}
  </div>
  <div class="side-foot">
    <div class="balance"><span>${esc(t('UI_BALANCE'))}</span><b>${coin()}${num(me.coins)}</b></div>
    <button class="btn btn-teal full" data-a="redeem"><i class="fas fa-ticket"></i>${esc(t('UI_REDEEM_CODE'))}</button>
  </div></div>`;
}

// ── cards ────────────────────────────────────────────────────────────────
function badges(it) {
  const b = [];
  if (soldOut(it)) b.push(`<span class="chip red">${esc(t('UI_SOLD_OUT'))}</span>`);
  if (it.sale) b.push(`<span class="chip white">-${Math.round((1 - it.price / it.basePrice) * 100)}%</span>`);
  if (it.trending) b.push(`<span class="chip teal"><i class="fas fa-fire"></i>${esc(t('UI_TRENDING'))}</span>`);
  if (it.isNew && !it.trending) b.push(`<span class="chip">${esc(t('UI_NEW'))}</span>`);
  if (!soldOut(it) && it.stock != null && it.stock <= 10) b.push(`<span class="chip amber">${esc(t('UI_LEFT', it.stock))}</span>`);
  return b.join('');
}

function meta(it) {
  const parts = [`<i class="fas ${CAT_ICON[it.category] || 'fa-tag'}"></i>${esc(t('CAT_' + it.category.toUpperCase()))}`];
  if (!isSingle(it) && it.itemCount > 1) parts.push(`x${num(it.itemCount)}`);
  if (it.tags && it.tags[0]) parts.push(esc(it.tags[0]));
  return parts.join(' · ');
}

function card(it) {
  return `<div class="card ${soldOut(it) ? 'out' : ''}" data-a="item" data-v="${esc(it.id)}">
    <div class="card-img">${img(it.images[0], CAT_ICON[it.category])}<div class="badges">${badges(it)}</div>
      <button class="fav ${S.favs.has(it.id) ? 'on' : ''}" data-a="fav" data-v="${esc(it.id)}" data-stop title="${esc(t('UI_FAVORITE'))}"><i class="fas fa-heart"></i></button></div>
    <div class="card-b"><b>${esc(it.name)}</b><div class="card-meta">${meta(it)}</div>
      <div class="price">${coin()}<b>${num(it.price)}</b>${it.sale ? `<span class="strike">${num(it.basePrice)}</span>` : ''}<span class="go"><i class="fas fa-arrow-right"></i></span></div></div>
  </div>`;
}

function sortItems(list) {
  const l = list.slice();
  const by = {
    featured: (a, b) => (b.trending - a.trending) || 0,
    popular: (a, b) => b.sold - a.sold,
    'price-asc': (a, b) => a.price - b.price,
    'price-desc': (a, b) => b.price - a.price,
    newest: (a, b) => (b.created || 0) - (a.created || 0),
    name: (a, b) => a.name.localeCompare(b.name),
  }[S.sort];
  return by ? l.sort(by) : l;
}

function filterItems(list) {
  const q = S.q.trim().toLowerCase();
  return list.filter(i => (!q || i.name.toLowerCase().includes(q) || (i.tags || []).some(x => x.toLowerCase().includes(q)) || i.description.toLowerCase().includes(q))
    && (!S.tag || (i.tags || []).includes(S.tag)));
}

// ── home ─────────────────────────────────────────────────────────────────
VIEWS.home = () => {
  const d = S.deals[S.heroIdx];
  const hero = d ? `<div class="hero">
      <div class="hero-txt">
        <div style="display:flex;gap:6px;align-items:center"><span class="chip teal"><i class="fas fa-bolt"></i>${esc(t('UI_SPECIAL_DEAL'))}</span>
          ${d.until ? `<span class="timer"><i class="fas fa-clock"></i><b data-until="${d.until}">${clock(d.until - Date.now() / 1000)}</b></span>` : ''}</div>
        <h2>${esc(d.name)}</h2><p>${esc(d.description)}</p>
        <div class="hero-inc">${d.items.slice(0, 5).map(i => `<span class="chip"><i class="fas ${CAT_ICON[i.category] || 'fa-tag'}"></i>${esc(i.name)}</span>`).join('')}${d.items.length > 5 ? `<span class="chip">+${d.items.length - 5}</span>` : ''}</div>
        <div class="hero-foot"><div class="hero-price"><b>${coin()}${num(d.price)}</b>${d.value > d.price ? `<span class="strike">${num(d.value)}</span><span class="chip white">${esc(t('UI_SAVE_PCT', Math.round((1 - d.price / d.value) * 100)))}</span>` : ''}</div>
          <button class="btn btn-teal" data-a="deal" data-v="${esc(d.id)}">${esc(t('UI_VIEW_DEAL'))}<i class="fas fa-arrow-right"></i></button></div>
      </div>
      <div class="hero-img">${img(d.image || (d.items[0] && d.items[0].image), 'fa-gift')}</div>
      ${S.deals.length > 1 ? `<div class="dots">${S.deals.map((_, i) => `<button class="${i === S.heroIdx ? 'on' : ''}" data-a="hero" data-v="${i}"></button>`).join('')}</div>` : ''}
    </div>` : '';
  const trending = SHOP().filter(i => i.trending && !soldOut(i)).slice(0, 8);
  const sale = SHOP().filter(i => i.sale).slice(0, 4);
  const popular = SHOP().slice().filter(i => i.sold > 0).sort((a, b) => b.sold - a.sold).slice(0, 4);
  const fresh = SHOP().filter(i => i.isNew).slice(0, 4);
  const sec = (title, sub, list, go) => list.length ? `<div class="sec"><h2>${esc(title)}</h2><span>${esc(sub)}</span><div class="rule"></div>${go ? `<button data-a="go" data-v="${go}">${esc(t('UI_SEE_ALL'))}</button>` : ''}</div><div class="cards">${list.map(card).join('')}</div>` : '';
  const body = hero + sec(t('HOME_TRENDING'), t('HOME_TRENDING_SUB'), trending, 'browse:all')
    + sec(t('HOME_SALE'), t('HOME_SALE_SUB'), sale, 'browse:sale')
    + sec(t('HOME_POPULAR'), t('HOME_POPULAR_SUB'), popular)
    + sec(t('HOME_NEW'), t('HOME_NEW_SUB'), fresh);
  return `<div class="scroll" data-keep="home">
    <div class="head"><div class="head-txt"><h1>${esc(t('HOME_TITLE', S.me.name.split(' ')[0]))}</h1><p>${esc(t('HOME_SUB'))}</p></div></div>
    ${body || `<div class="empty"><i class="fas fa-store"></i><b>${esc(t('UI_EMPTY_SHOP'))}</b></div>`}
  </div>`;
};

// ── browse ───────────────────────────────────────────────────────────────
VIEWS.browse = () => {
  const c = S.cats.find(x => x.id === S.cat);
  const title = { all: t('NAV_ALL'), favorites: t('NAV_FAVORITES'), sale: t('NAV_SALE') }[S.cat] || (c ? c.name : t('NAV_ALL'));
  const base = catItems(S.cat);
  const list = sortItems(filterItems(base));
  const tags = {};
  base.forEach(i => (i.tags || []).forEach(x => { tags[x] = (tags[x] || 0) + 1; }));
  const topTags = Object.entries(tags).sort((a, b) => b[1] - a[1]).slice(0, 12).map(x => x[0]);
  const sorts = ['featured', 'popular', 'price-asc', 'price-desc', 'newest', 'name'];
  return `<div class="scroll" data-keep="browse-${esc(S.cat)}">
    <div class="head"><div class="head-txt"><h1>${esc(title)}</h1><p>${esc(t('UI_SHOWING', list.length, base.length))}</p></div></div>
    <div class="toolbar">
      <div class="lsearch"><i class="fas fa-magnifying-glass"></i><input class="input" id="lsearch" placeholder="${esc(t('UI_SEARCH_IN', title))}" value="${esc(S.q)}" data-f="q" data-r autocomplete="off"></div>
      <div class="sp"></div>
      <select class="select" data-f="sort" data-r>${sorts.map(s => `<option value="${s}" ${S.sort === s ? 'selected' : ''}>${esc(t('SORT_' + s.replace('-', '_').toUpperCase()))}</option>`).join('')}</select>
    </div>
    ${topTags.length > 1 ? `<div class="tagbar"><button class="${!S.tag ? 'on' : ''}" data-a="tag" data-v="">${esc(t('UI_ALL_TAGS'))}</button>${topTags.map(x => `<button class="${S.tag === x ? 'on' : ''}" data-a="tag" data-v="${esc(x)}">${esc(x)}</button>`).join('')}</div>` : ''}
    ${list.length ? `<div class="cards">${list.map(card).join('')}</div>` : `<div class="empty"><i class="fas ${S.cat === 'favorites' ? 'fa-heart' : 'fa-box-open'}"></i><b>${esc(t(S.cat === 'favorites' && !base.length ? 'UI_NO_FAVS' : 'UI_NO_RESULTS'))}</b><span>${esc(t(S.cat === 'favorites' && !base.length ? 'UI_NO_FAVS_SUB' : 'UI_NO_RESULTS_SUB'))}</span></div>`}
  </div>`;
};

// ── deals ────────────────────────────────────────────────────────────────
function dealRow(d) {
  return `<div class="deal" data-a="deal" data-v="${esc(d.id)}">
    <div class="deal-img">${img(d.image || (d.items[0] && d.items[0].image), 'fa-gift')}</div>
    <div class="deal-b"><h3>${esc(d.name)}${d.value > d.price ? `<span class="chip white">${esc(t('UI_SAVE_PCT', Math.round((1 - d.price / d.value) * 100)))}</span>` : ''}</h3>
      <p>${esc(d.description)}</p>
      <div class="thumbs">${d.items.map(i => `<div class="thumb" title="${esc(i.name)}">${i.image ? `<img src="${esc(i.image)}" alt="">` : `<i class="fas ${CAT_ICON[i.category]}"></i>`}</div>`).join('')}</div></div>
    <div class="deal-side">${d.until ? `<span class="timer"><i class="fas fa-clock"></i><b data-until="${d.until}">${clock(d.until - Date.now() / 1000)}</b></span>` : `<span class="chip">${esc(t('UI_NO_EXPIRY'))}</span>`}
      <div><div class="hero-price" style="justify-content:flex-end"><b>${coin()}${num(d.price)}</b></div>${d.value > d.price ? `<div class="strike" style="font-size:10.5px;margin-top:3px">${esc(t('UI_WORTH', num(d.value)))}</div>` : ''}</div>
      <button class="btn btn-teal sm">${esc(t('UI_VIEW_DEAL'))}</button></div>
  </div>`;
}

VIEWS.deals = () => `<div class="scroll" data-keep="deals">
  <div class="head"><div class="head-txt"><h1>${esc(t('NAV_DEALS'))}</h1><p>${esc(t('DEALS_SUB'))}</p></div></div>
  ${S.deals.length ? S.deals.map(dealRow).join('') : `<div class="empty"><i class="fas fa-tags"></i><b>${esc(t('UI_NO_DEALS'))}</b><span>${esc(t('UI_NO_DEALS_SUB'))}</span></div>`}
</div>`;

// ── history ──────────────────────────────────────────────────────────────
const REASON_ICON = { purchase: 'fa-bag-shopping', deal: 'fa-tags', redeem: 'fa-ticket', promo: 'fa-gift', refund: 'fa-rotate-left', playtime: 'fa-clock',
  transfer_in: 'fa-arrow-down', transfer_out: 'fa-paper-plane', admin_give: 'fa-shield-halved', admin_set: 'fa-shield-halved', admin_remove: 'fa-shield-halved', export: 'fa-plug' };

VIEWS.history = () => {
  const h = S.history;
  if (!h) return `<div class="empty" style="flex:1"><i class="fas fa-circle-notch fa-spin"></i></div>`;
  const tabs = [['purchases', 'fa-receipt', t('HIST_PURCHASES')], ['ledger', 'fa-coins', t('HIST_LEDGER')], ['gifts', 'fa-gift', t('HIST_GIFTS')]];
  let table = '';
  if (S.histTab === 'purchases') {
    table = h.purchases.length ? `<table class="table"><thead><tr><th>${esc(t('TH_PACKAGE'))}</th><th>${esc(t('TH_DETAILS'))}</th><th class="num">${esc(t('TH_PRICE'))}</th><th class="num">${esc(t('TH_DATE'))}</th></tr></thead><tbody>
      ${h.purchases.map(p => { const it = item(p.itemId); return `<tr><td><div class="cell"><div class="thumb">${it && it.images[0] ? `<img src="${esc(it.images[0])}">` : `<i class="fas ${p.kind === 'deal' ? 'fa-tags' : 'fa-box'}"></i>`}</div><div class="cell-t"><b>${esc(p.name)}</b><span>${p.kind === 'deal' ? esc(t('UI_DEAL')) : 'x' + num(p.quantity)}</span></div></div></td>
        <td>${p.giftedTo ? `<span class="chip teal"><i class="fas fa-gift"></i>${esc(p.giftedTo)}</span> ` : ''}${p.plate ? `<span class="chip">${esc(p.plate)}</span> ` : ''}${p.refunded ? `<span class="chip amber">${esc(t('UI_REFUNDED'))}</span>` : ''}</td>
        <td class="num"><b>${num(p.price)}</b></td><td class="num">${esc(ago(p.date))}</td></tr>`; }).join('')}</tbody></table>`
      : `<div class="empty"><i class="fas fa-receipt"></i><b>${esc(t('HIST_EMPTY'))}</b></div>`;
  } else if (S.histTab === 'ledger') {
    table = h.ledger.length ? `<table class="table"><thead><tr><th>${esc(t('TH_ACTIVITY'))}</th><th class="num">${esc(t('TH_CHANGE'))}</th><th class="num">${esc(t('TH_BALANCE'))}</th><th class="num">${esc(t('TH_DATE'))}</th></tr></thead><tbody>
      ${h.ledger.map(l => `<tr><td><div class="cell"><div class="tile w" style="width:28px;height:28px;font-size:10px"><i class="fas ${REASON_ICON[l.reason] || 'fa-coins'}"></i></div><div class="cell-t"><b>${esc(t('R_' + l.reason.toUpperCase()))}</b><span>${esc(l.note || '')}</span></div></div></td>
        <td class="num"><span class="delta ${l.delta >= 0 ? 'p' : 'n'}">${l.delta >= 0 ? '+' : ''}${num(l.delta)}</span></td><td class="num">${num(l.balance)}</td><td class="num">${esc(ago(l.date))}</td></tr>`).join('')}</tbody></table>`
      : `<div class="empty"><i class="fas fa-coins"></i><b>${esc(t('HIST_EMPTY'))}</b></div>`;
  } else {
    table = h.gifts.length ? `<table class="table"><thead><tr><th>${esc(t('TH_PACKAGE'))}</th><th>${esc(t('TH_FROM'))}</th><th class="num">${esc(t('TH_DATE'))}</th></tr></thead><tbody>
      ${h.gifts.map(g => `<tr><td><b>${esc(g.name)}</b> <span class="muted">x${num(g.quantity)}</span></td><td>${esc(g.sender || '—')}</td><td class="num">${esc(ago(g.date))}</td></tr>`).join('')}</tbody></table>`
      : `<div class="empty"><i class="fas fa-gift"></i><b>${esc(t('HIST_NO_GIFTS'))}</b></div>`;
  }
  return `<div class="scroll" data-keep="history">
    <div class="head"><div class="head-txt"><h1>${esc(t('NAV_HISTORY'))}</h1><p>${esc(t('HIST_SUB'))}</p></div></div>
    <div class="stats">
      <div class="stat"><div class="tile"><i class="fas fa-wallet"></i></div><div class="stat-txt"><span>${esc(t('UI_BALANCE'))}</span><b>${coin()}${num(S.me.coins)}</b></div></div>
      <div class="stat"><div class="tile w"><i class="fas fa-fire"></i></div><div class="stat-txt"><span>${esc(t('UI_TOTAL_SPENT'))}</span><b>${coin()}${num(h.spent)}</b></div></div>
      <div class="stat"><div class="tile w"><i class="fas fa-bag-shopping"></i></div><div class="stat-txt"><span>${esc(t('UI_PURCHASES'))}</span><b>${num(h.purchases.length)}</b></div></div>
    </div>
    <div class="tabs">${tabs.map(([k, i, l]) => `<button class="${S.histTab === k ? 'on' : ''}" data-a="histTab" data-v="${k}"><i class="fas ${i}"></i>${esc(l)}</button>`).join('')}</div>
    <div class="panel">${table}</div>
  </div>`;
};

// ── tutorial ─────────────────────────────────────────────────────────────
VIEWS.tutorial = () => {
  const imgs = S.cfg.tutorial || [];
  const icons = ['fa-cart-shopping', 'fa-ticket', 'fa-gift'];
  return `<div class="scroll" data-keep="tutorial">
    <div class="head"><div class="head-txt"><h1>${esc(t('NAV_TUTORIAL'))}</h1><p>${esc(t('TUT_SUB'))}</p></div></div>
    <div class="steps">${[1, 2, 3].map(n => `<div class="step"><div class="step-img">${imgs[n - 1] ? `<img src="${esc(imgs[n - 1])}" alt="">` : `<i class="fas ${icons[n - 1]}"></i>`}</div>
      <div class="step-b"><div class="n">${n}</div><b>${esc(t('TUT_' + n))}</b><p>${esc(t('TUT_' + n + '_TXT', S.cfg.coinName))}</p></div></div>`).join('')}</div>
    <div class="callout"><i class="fas fa-store"></i><div><b>${esc(t('TUT_STORE'))}</b><span>${esc(S.cfg.storeUrl || '')}</span></div><button class="btn btn-teal" data-a="store">${esc(t('UI_BUY_COINS'))}<i class="fas fa-arrow-up-right-from-square"></i></button></div>
    ${S.cfg.playtime ? `<div class="callout" style="border-color:var(--line-soft);background:var(--panel)"><i class="fas fa-clock"></i><div><b>${esc(t('TUT_PLAYTIME'))}</b><span>${esc(t('TUT_PLAYTIME_TXT', S.cfg.playtime.coins, S.cfg.coinName, S.cfg.playtime.minutes))}</span></div></div>` : ''}
  </div>`;
};

// ── modal frame ──────────────────────────────────────────────────────────
function modalFrame(cls, head, body, foot) {
  return `<div class="modal-wrap" id="modal-${esc(S.modal ? S.modal.type : 'x')}" data-a="modalBg"><div class="modal ${cls}" data-a="noop" data-stop><div class="frame"><div class="shell">
    ${head ? `<div class="m-head"><h3>${head}</h3><button class="icon-btn" data-a="closeModal"><i class="fas fa-xmark"></i></button></div>` : ''}
    ${body}${foot ? `<div class="m-foot">${foot}</div>` : ''}
  </div></div></div></div>`;
}

function giftBlock(m) {
  if (!S.cfg.giftItems) return '';
  const st = m.lookup;
  return `<div class="gift"><div class="gift-top" data-a="giftToggle"><div class="tile w" style="width:28px;height:28px;font-size:10px"><i class="fas fa-gift"></i></div>
      <div><b>${esc(t('UI_GIFT'))}</b><span>${esc(t('UI_GIFT_SUB'))}</span></div><span class="toggle ${m.gift ? 'on' : ''}"></span></div>
    ${m.gift ? `<div class="row" style="align-items:center"><input class="input" id="giftid" style="max-width:130px" placeholder="${esc(t('UI_SERVER_ID'))}" value="${esc(m.giftId || '')}" data-f="modal.giftId" data-live="giftLookup" inputmode="numeric">
      <div class="lookup ${st && st.name ? 'ok' : st && st.error ? 'bad' : ''}">${st && st.name ? `<i class="fas fa-circle-check"></i>${esc(st.name)}` : st && st.error ? `<i class="fas fa-circle-xmark"></i>${esc(t(st.error))}` : st && st.busy ? '<i class="fas fa-circle-notch fa-spin"></i>' : `<span class="muted">${esc(t('UI_GIFT_HINT'))}</span>`}</div></div>` : ''}
  </div>`;
}
const giftReady = m => !m.gift || (m.lookup && m.lookup.name);

function resultView(ok, title, text, extra) {
  return `<div class="result ${ok ? '' : 'bad'}"><div class="big"><i class="fas ${ok ? 'fa-check' : 'fa-xmark'}"></i></div><h3>${esc(title)}</h3><p>${esc(text)}</p>${extra || ''}</div>`;
}

// ── item modal ───────────────────────────────────────────────────────────
MODALS.item = () => {
  const m = S.modal;
  const it = item(m.id);
  if (!it) return '';
  const qty = isSingle(it) ? 1 : m.qty;
  const total = it.price * qty;
  const enough = S.me.coins >= total;
  const imgs = it.images.length ? it.images : [null];
  const gi = Math.min(m.img || 0, imgs.length - 1);
  if (m.step === 'done') {
    const r = m.result;
    return modalFrame('w-sm', '', `<div class="m-body">${resultView(true, t('BUY_DONE'), r.gift ? t('BUY_DONE_GIFT', it.name, r.gift) : t('BUY_DONE_TXT', it.name),
      r.plate ? `<span class="plate">${esc(r.plate)}</span>` : '')}</div>`,
      `<div class="sp"></div><button class="btn btn-ghost" data-a="closeModal">${esc(t('UI_CONTINUE'))}</button>`);
  }
  if (m.step === 'confirm') {
    return modalFrame('w-sm', `<i class="fas fa-bag-shopping"></i>${esc(t('BUY_CONFIRM'))}`, `<div class="m-body">
      <div class="cell"><div class="thumb" style="width:48px;height:48px">${it.images[0] ? `<img src="${esc(it.images[0])}">` : `<i class="fas ${CAT_ICON[it.category]}"></i>`}</div><div class="cell-t"><b style="font-size:13px">${esc(it.name)}</b><span>${meta(it)}</span></div></div>
      <div class="confirm-box">
        <div class="confirm-line"><span>${esc(t('UI_QUANTITY'))}</span><b>${num(qty)}</b></div>
        ${m.gift ? `<div class="confirm-line"><span>${esc(t('UI_RECIPIENT'))}</span><b><i class="fas fa-gift teal"></i>${esc(m.lookup.name)}</b></div>` : ''}
        <div class="confirm-line"><span>${esc(t('UI_BALANCE'))}</span><b>${coin()}${num(S.me.coins)}</b></div>
        <div class="confirm-line"><span>${esc(t('UI_AFTER'))}</span><b>${coin()}${num(S.me.coins - total)}</b></div>
        <div class="confirm-line total-line"><span>${esc(t('UI_TOTAL'))}</span><b>${coin()}${num(total)}</b></div>
      </div><p class="hint">${esc(t('BUY_CONFIRM_TXT'))}</p></div>`,
      `<button class="btn btn-ghost" data-a="step" data-v="view">${esc(t('UI_BACK'))}</button><div class="sp"></div>
       <button class="btn btn-teal" data-a="buyItem" ${S.busy ? 'disabled' : ''}>${S.busy ? '<i class="fas fa-circle-notch spin"></i>' : '<i class="fas fa-check"></i>'}${esc(t('UI_CONFIRM'))}</button>`);
  }
  const specs = [[t('SPEC_CATEGORY'), t('CAT_' + it.category.toUpperCase())]];
  if (it.category === 'vehicle' && it.spawnName) specs.push([t('SPEC_MODEL'), it.spawnName]);
  if (!isSingle(it)) specs.push([t('SPEC_CONTAINS'), `${num(it.itemCount)}x`]);
  if (it.stock != null) specs.push([t('SPEC_STOCK'), soldOut(it) ? t('UI_SOLD_OUT') : t('UI_LEFT', it.stock)]);
  if (it.playerLimit) specs.push([t('SPEC_LIMIT'), t('UI_PER_PLAYER', it.playerLimit)]);
  specs.push([t('SPEC_SOLD'), num(it.sold)]);
  const canBuy = enough && !soldOut(it) && giftReady(m);
  return modalFrame('w-item', '', `<div class="detail">
      <div class="gallery"><div class="gallery-main">${imgs[gi] ? `<img src="${esc(imgs[gi])}" alt="">` : `<i class="fas ${CAT_ICON[it.category]} noimg"></i>`}
        ${imgs.length > 1 ? `<button class="gallery-nav l" data-a="img" data-v="-1"><i class="fas fa-chevron-left"></i></button><button class="gallery-nav r" data-a="img" data-v="1"><i class="fas fa-chevron-right"></i></button>` : ''}
        <div class="badges" style="left:14px;top:14px">${badges(it)}</div></div>
        ${imgs.length > 1 ? `<div class="gallery-thumbs">${imgs.map((s, i) => `<button class="${i === gi ? 'on' : ''}" data-a="imgAt" data-v="${i}"><img src="${esc(s)}"></button>`).join('')}</div>` : ''}
      </div>
      <div class="info">
        <div class="m-head" style="border:0;padding-bottom:0"><h3 style="font-size:11px;color:var(--ink-3);font-weight:500"><i class="fas ${CAT_ICON[it.category]}"></i>${esc(t('CAT_' + it.category.toUpperCase()))}</h3>
          <button class="icon-btn ${S.favs.has(it.id) ? 'on' : ''}" data-a="fav" data-v="${esc(it.id)}" title="${esc(t('UI_FAVORITE'))}" style="${S.favs.has(it.id) ? 'color:var(--red)' : ''}"><i class="fas fa-heart"></i></button>
          <button class="icon-btn" data-a="closeModal"><i class="fas fa-xmark"></i></button></div>
        <div class="info-scroll" data-keep="info">
          <h2>${esc(it.name)}</h2>
          ${it.tags.length ? `<div class="thumbs">${it.tags.map(x => `<span class="chip">${esc(x)}</span>`).join('')}</div>` : ''}
          ${it.description ? `<p class="desc">${esc(it.description)}</p>` : ''}
          <div class="specs">${specs.map(([a, b]) => `<div class="spec"><span>${esc(a)}</span><b>${esc(b)}</b></div>`).join('')}</div>
          ${it.sale && it.saleUntil ? `<div class="timer"><i class="fas fa-percent"></i>${esc(t('UI_SALE_ENDS'))} <b data-until="${it.saleUntil}">${clock(it.saleUntil - Date.now() / 1000)}</b></div>` : ''}
          ${!isSingle(it) ? `<div class="field"><label>${esc(t('UI_QUANTITY'))}</label><div class="qty"><button data-a="qty" data-v="-1"><i class="fas fa-minus"></i></button><input id="qty" value="${qty}" data-f="modal.qty" data-live="qtyInput" inputmode="numeric"><button data-a="qty" data-v="1"><i class="fas fa-plus"></i></button></div></div>` : ''}
          ${giftBlock(m)}
        </div>
        <div class="buybar">
          <div class="total"><span>${esc(t('UI_TOTAL'))}</span><b>${coin()}${num(total)}${it.sale ? `<span class="strike">${num(it.basePrice * qty)}</span>` : ''}</b>
            ${!enough ? `<span class="red" style="margin-top:3px">${esc(t('UI_NEED_MORE', num(total - S.me.coins)))}</span>` : ''}</div>
          ${it.category === 'vehicle' && S.cfg.testDrive ? `<button class="btn btn-ghost lg" data-a="testDrive" ${S.busy ? 'disabled' : ''}><i class="fas fa-gauge-high"></i>${esc(t('UI_TEST_DRIVE'))}</button>` : ''}
          ${enough ? `<button class="btn btn-teal lg" data-a="step" data-v="confirm" ${canBuy ? '' : 'disabled'}><i class="fas fa-bag-shopping"></i>${esc(m.gift ? t('UI_BUY_GIFT') : t('UI_BUY'))}</button>`
            : `<button class="btn btn-teal lg" data-a="redeem"><i class="fas fa-ticket"></i>${esc(t('UI_GET_COINS'))}</button>`}
        </div>
      </div>
    </div>`);
};

// ── deal modal ───────────────────────────────────────────────────────────
MODALS.deal = () => {
  const m = S.modal;
  const d = deal(m.id);
  if (!d) return '';
  const enough = S.me.coins >= d.price;
  if (m.step === 'done') {
    const r = m.result;
    return modalFrame('w-sm', '', `<div class="m-body">${resultView(true, t('BUY_DONE'), r.gift ? t('BUY_DONE_GIFT', d.name, r.gift) : t('BUY_DONE_TXT', d.name))}
      ${r.failed && r.failed.length ? `<p class="err" style="text-align:center">${esc(t('BUY_PARTIAL', r.failed.join(', '), num(r.refund)))}</p>` : ''}</div>`,
      `<div class="sp"></div><button class="btn btn-ghost" data-a="closeModal">${esc(t('UI_CONTINUE'))}</button>`);
  }
  if (m.step === 'confirm') {
    return modalFrame('w-sm', `<i class="fas fa-tags"></i>${esc(t('BUY_CONFIRM_DEAL'))}`, `<div class="m-body">
      <div class="confirm-box">
        <div class="confirm-line"><span>${esc(t('UI_DEAL'))}</span><b>${esc(d.name)}</b></div>
        <div class="confirm-line"><span>${esc(t('UI_PACKAGES'))}</span><b>${d.items.length}</b></div>
        ${m.gift ? `<div class="confirm-line"><span>${esc(t('UI_RECIPIENT'))}</span><b><i class="fas fa-gift teal"></i>${esc(m.lookup.name)}</b></div>` : ''}
        <div class="confirm-line"><span>${esc(t('UI_AFTER'))}</span><b>${coin()}${num(S.me.coins - d.price)}</b></div>
        <div class="confirm-line total-line"><span>${esc(t('UI_TOTAL'))}</span><b>${coin()}${num(d.price)}</b></div>
      </div><p class="hint">${esc(t('BUY_CONFIRM_TXT'))}</p></div>`,
      `<button class="btn btn-ghost" data-a="step" data-v="view">${esc(t('UI_BACK'))}</button><div class="sp"></div>
       <button class="btn btn-teal" data-a="buyDeal" ${S.busy ? 'disabled' : ''}>${S.busy ? '<i class="fas fa-circle-notch spin"></i>' : '<i class="fas fa-check"></i>'}${esc(t('UI_CONFIRM'))}</button>`);
  }
  return modalFrame('w-md', `<i class="fas fa-tags"></i>${esc(d.name)}`, `<div class="m-body" data-keep="deal">
      <div class="hero" style="min-height:150px"><div class="hero-txt" style="padding:16px 18px"><p style="-webkit-line-clamp:4">${esc(d.description)}</p>
        ${d.until ? `<span class="timer" style="margin-top:auto"><i class="fas fa-clock"></i>${esc(t('UI_ENDS_IN'))} <b data-until="${d.until}">${clock(d.until - Date.now() / 1000)}</b></span>` : ''}</div>
        <div class="hero-img" style="width:220px">${img(d.image || (d.items[0] && d.items[0].image), 'fa-gift')}</div></div>
      <div class="field"><label>${esc(t('UI_INCLUDED'))} <small>${esc(t('UI_WORTH', num(d.value)))}</small></label>
        <div class="pick-list" style="max-height:200px">${d.items.map(i => `<div class="pick" style="cursor:default"><div class="thumb">${i.image ? `<img src="${esc(i.image)}">` : `<i class="fas ${CAT_ICON[i.category]}"></i>`}</div><div class="cell-t"><b>${esc(i.name)}</b><span>${esc(t('CAT_' + i.category.toUpperCase()))}</span></div><span class="muted">${coin()} ${num(i.price)}</span></div>`).join('')}</div></div>
      ${giftBlock(m)}
    </div>`,
    `<div class="total"><span>${esc(t('UI_TOTAL'))}</span><b>${coin()}${num(d.price)}${d.value > d.price ? `<span class="strike">${num(d.value)}</span>` : ''}</b></div>
     ${enough ? `<button class="btn btn-teal lg" data-a="step" data-v="confirm" ${giftReady(m) ? '' : 'disabled'}><i class="fas fa-bag-shopping"></i>${esc(m.gift ? t('UI_BUY_GIFT') : t('UI_BUY'))}</button>`
       : `<button class="btn btn-teal lg" data-a="redeem"><i class="fas fa-ticket"></i>${esc(t('UI_GET_COINS'))}</button>`}`);
};

// ── redeem ───────────────────────────────────────────────────────────────
MODALS.redeem = () => {
  const m = S.modal;
  if (m.done) {
    return modalFrame('w-sm', '', `<div class="m-body">${resultView(true, t('REDEEM_DONE'), m.done.gift ? t('REDEEM_DONE_GIFT', num(m.done.amount), S.cfg.coinName, m.done.gift) : t('REDEEM_DONE_TXT', num(m.done.amount), S.cfg.coinName))}</div>`,
      `<button class="btn btn-ghost" data-a="redeemAgain">${esc(t('REDEEM_ANOTHER'))}</button><div class="sp"></div><button class="btn btn-teal" data-a="closeModal">${esc(t('UI_CONTINUE'))}</button>`);
  }
  const tebex = m.tab !== 'promo';
  const ready = (m.code || '').trim() && (!tebex || giftReady(m));
  return modalFrame('w-sm', `<i class="fas fa-ticket"></i>${esc(t('REDEEM_TITLE'))}`, `<div class="m-body">
      <div class="seg"><button class="${tebex ? 'on' : ''}" data-a="redeemTab" data-v="tebex"><i class="fas fa-receipt"></i>${esc(t('REDEEM_TEBEX'))}</button><button class="${!tebex ? 'on' : ''}" data-a="redeemTab" data-v="promo"><i class="fas fa-gift"></i>${esc(t('REDEEM_PROMO'))}</button></div>
      <p class="hint">${esc(tebex ? t('REDEEM_TEBEX_TXT') : t('REDEEM_PROMO_TXT'))}</p>
      <div class="field"><label>${esc(tebex ? t('REDEEM_ORDER') : t('REDEEM_CODE'))}</label>
        <input class="input" id="rcode" placeholder="${esc(tebex ? 'tbx-xxxxxxxxxxxxx-xxxxxx' : 'SUMMER25')}" value="${esc(m.code || '')}" data-f="modal.code" data-r data-enter="redeemGo" autocomplete="off"></div>
      ${tebex ? giftBlock(m) : ''}
      ${tebex && S.cfg.storeUrl ? `<button class="btn btn-text sm" data-a="store" style="align-self:flex-start"><i class="fas fa-store"></i>${esc(t('UI_BUY_COINS'))}</button>` : ''}
    </div>`,
    `<button class="btn btn-ghost" data-a="closeModal">${esc(t('UI_CANCEL'))}</button><div class="sp"></div>
     <button class="btn btn-teal" data-a="redeemGo" ${ready && !S.busy ? '' : 'disabled'}>${S.busy ? '<i class="fas fa-circle-notch spin"></i>' : '<i class="fas fa-check"></i>'}${esc(t('UI_REDEEM'))}</button>`);
};

// ── transfer ─────────────────────────────────────────────────────────────
MODALS.transfer = () => {
  const m = S.modal;
  const amount = Math.floor(Number(m.amount) || 0);
  const fee = Math.floor(amount * (S.cfg.transferFee || 0) / 100);
  const ok = m.lookup && m.lookup.name && amount >= S.cfg.transferMin && amount <= S.me.coins;
  return modalFrame('w-sm', `<i class="fas fa-paper-plane"></i>${esc(t('NAV_TRANSFER'))}`, `<div class="m-body">
      <p class="hint">${esc(t('TRANSFER_TXT', S.cfg.coinName))}</p>
      <div class="field"><label>${esc(t('UI_SERVER_ID'))}</label><div class="row" style="align-items:center"><input class="input" id="giftid" style="max-width:130px" value="${esc(m.giftId || '')}" data-f="modal.giftId" data-live="giftLookup" inputmode="numeric">
        <div class="lookup ${m.lookup && m.lookup.name ? 'ok' : m.lookup && m.lookup.error ? 'bad' : ''}">${m.lookup && m.lookup.name ? `<i class="fas fa-circle-check"></i>${esc(m.lookup.name)}` : m.lookup && m.lookup.error ? `<i class="fas fa-circle-xmark"></i>${esc(t(m.lookup.error))}` : ''}</div></div></div>
      <div class="field"><label>${esc(t('UI_AMOUNT'))} <small>${esc(t('TRANSFER_MIN', num(S.cfg.transferMin)))}</small></label><input class="input" id="tamount" value="${esc(m.amount || '')}" data-f="modal.amount" data-r inputmode="numeric"></div>
      ${fee > 0 ? `<div class="confirm-box"><div class="confirm-line"><span>${esc(t('TRANSFER_FEE', S.cfg.transferFee))}</span><b>${num(fee)}</b></div><div class="confirm-line"><span>${esc(t('TRANSFER_RECEIVES'))}</span><b>${coin()}${num(amount - fee)}</b></div></div>` : ''}
    </div>`,
    `<button class="btn btn-ghost" data-a="closeModal">${esc(t('UI_CANCEL'))}</button><div class="sp"></div>
     <button class="btn btn-teal" data-a="transferGo" ${ok && !S.busy ? '' : 'disabled'}><i class="fas fa-paper-plane"></i>${esc(t('TRANSFER_SEND'))}</button>`);
};

// generic confirm { title, text, danger, run, input }
MODALS.confirm = () => {
  const m = S.modal;
  const ready = !m.input || (m.value || '') === m.input;
  return modalFrame('w-sm', `<i class="fas ${m.danger ? 'fa-triangle-exclamation' : 'fa-circle-question'}" style="${m.danger ? 'color:var(--red)' : ''}"></i>${esc(m.title)}`,
    `<div class="m-body"><p class="desc" style="font-size:11.5px;color:var(--ink-2);line-height:1.6">${esc(m.text)}</p>
      ${m.input ? `<div class="field"><label>${esc(t('UI_TYPE_TO_CONFIRM', m.input))}</label><input class="input" id="cinput" value="${esc(m.value || '')}" data-f="modal.value" data-r></div>` : ''}</div>`,
    `<button class="btn btn-ghost" data-a="closeModal">${esc(t('UI_CANCEL'))}</button><div class="sp"></div>
     <button class="btn ${m.danger ? 'btn-red' : 'btn-teal'}" data-a="confirmGo" ${ready && !S.busy ? '' : 'disabled'}>${esc(m.ok || t('UI_CONFIRM'))}</button>`);
};
function confirmBox(title, text, run, opts = {}) { openModal('confirm', Object.assign({ title, text, run }, opts)); render(); }

// ── actions ──────────────────────────────────────────────────────────────
ACT.noop = () => { };
ACT.close = () => close();
ACT.closeModal = () => { closeModal(); render(); };
ACT.modalBg = (_, el, e) => { if (e.target === el) { closeModal(); render(); } };
ACT.go = v => {
  const [page, cat] = String(v).split(':');
  S.page = page;
  if (cat) { if (S.cat !== cat) { S.tag = null; } S.cat = cat; }
  if (page !== 'browse') S.q = '';
  if (page === 'history') loadHistory();
  if (page === 'admin' && window.adminEnter) adminEnter();
  render();
};
ACT.globalSearch = () => {
  if (S.page !== 'browse') { S.page = 'browse'; S.cat = 'all'; S.tag = null; }
  render();
};
ACT.tag = v => { S.tag = v || null; render(); };
ACT.hero = v => { S.heroIdx = Number(v) || 0; render(); };
ACT.item = v => { openModal('item', { id: v, qty: 1, img: 0, step: 'view' }); render(); };
ACT.deal = v => { openModal('deal', { id: v, step: 'view' }); render(); };
ACT.step = v => { if (S.modal) { S.modal.step = v; render(); } };
ACT.img = v => { const it = item(S.modal.id); const n = Math.max(1, it.images.length); S.modal.img = ((S.modal.img || 0) + Number(v) + n) % n; render(); };
ACT.imgAt = v => { S.modal.img = Number(v); render(); };
ACT.qty = v => { S.modal.qty = Math.max(1, Math.min(S.cfg.maxQty, (Number(S.modal.qty) || 1) + Number(v))); render(); };
ACT.qtyInput = () => { const q = Math.floor(Number(S.modal.qty)); if (q >= 1) { S.modal.qty = Math.min(S.cfg.maxQty, q); render(); } };
ACT.store = () => openUrl(S.cfg.storeUrl);
ACT.histTab = v => { S.histTab = v; render(); };

ACT.fav = async v => {
  const on = !S.favs.has(v);
  if (on) S.favs.add(v); else S.favs.delete(v);
  render();
  const r = await req('favorite', { id: v, on });
  if (r.error) { if (on) S.favs.delete(v); else S.favs.add(v); render(); }
};

ACT.giftToggle = () => { S.modal.gift = !S.modal.gift; if (!S.modal.gift) { S.modal.giftId = ''; S.modal.lookup = null; } render(); };
let lookupTimer;
ACT.giftLookup = () => {
  clearTimeout(lookupTimer);
  const m = S.modal;
  const id = String(m.giftId || '').trim();
  m.lookup = id ? { busy: true } : null;
  render();
  if (!id) return;
  lookupTimer = setTimeout(async () => {
    const r = await req('player:lookup', { id });
    if (S.modal !== m || String(m.giftId).trim() !== id) return;
    m.lookup = r.error ? { error: r.error } : { name: r.data.name, id: r.data.id };
    render();
  }, 350);
};

ACT.buyItem = async () => {
  const m = S.modal;
  const r = await call('buy:item', { id: m.id, qty: m.qty, gift: m.gift ? m.lookup.id : null }, { busy: 'buy' });
  if (!r) { if (S.modal === m) { m.step = 'view'; render(); } return; }
  setCoins(r.coins);
  const it = item(m.id);
  if (it) { it.sold += isSingle(it) ? 1 : m.qty; if (r.stock !== undefined && r.stock !== null) it.stock = r.stock; }
  m.step = 'done'; m.result = r;
  render();
};
ACT.buyDeal = async () => {
  const m = S.modal;
  const r = await call('buy:deal', { id: m.id, gift: m.gift ? m.lookup.id : null }, { busy: 'buy' });
  if (!r) { if (S.modal === m) { m.step = 'view'; render(); } return; }
  setCoins(r.coins);
  m.step = 'done'; m.result = r;
  render();
};
ACT.testDrive = async () => {
  if (S.busy) return;
  S.busy = 'td'; render();
  const r = await post('testdrive', { id: S.modal.id });
  S.busy = null;
  if (!r || r.error) { toast(errText(r || { error: 'ERR_GENERIC' }), true); render(); return; }
  S.modal = null;
};

ACT.redeem = () => { openModal('redeem', { tab: 'tebex', code: '' }); render(); };
ACT.redeemTab = v => { S.modal.tab = v; render(); };
ACT.redeemAgain = () => { S.modal.done = null; S.modal.code = ''; render(); };
ACT.redeemGo = async () => {
  const m = S.modal;
  if (!m || !(m.code || '').trim()) return;
  const tebex = m.tab !== 'promo';
  if (tebex && !giftReady(m)) return;
  const r = await call(tebex ? 'redeem:tebex' : 'redeem:promo', { code: m.code, gift: tebex && m.gift ? m.lookup.id : null }, { busy: 'redeem' });
  if (!r) return;
  setCoins(r.coins);
  m.done = r;
  render();
};

ACT.transfer = () => { openModal('transfer', { amount: '' }); render(); };
ACT.transferGo = async () => {
  const m = S.modal;
  const r = await call('transfer', { to: m.lookup.id, amount: Math.floor(Number(m.amount)) }, { success: t('TRANSFER_DONE') });
  if (!r) return;
  setCoins(r.coins);
  closeModal(); render();
};

ACT.confirmGo = async () => {
  const m = S.modal;
  if (!m || !m.run) return;
  const ok = await m.run(m);
  if (ok !== false && S.modal === m) { closeModal(); render(); }
};

async function loadHistory() {
  S.history = null;
  const r = await req('history');
  if (r.data) { S.history = r.data; S.me.coins = r.data.coins; }
  render();
}
