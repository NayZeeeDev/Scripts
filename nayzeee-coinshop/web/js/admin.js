/* ════════════════════════════════════════════════════════════════════════
   nayzeee-coinshop — admin panel
   ════════════════════════════════════════════════════════════════════════ */
'use strict';

const ADM_TABS = [
  ['dashboard', 'fa-chart-simple', 'ADM_DASHBOARD'], ['packages', 'fa-boxes-stacked', 'ADM_PACKAGES'], ['categories', 'fa-layer-group', 'ADM_CATEGORIES'],
  ['deals', 'fa-tags', 'ADM_DEALS'], ['players', 'fa-users', 'ADM_PLAYERS'], ['codes', 'fa-ticket', 'ADM_CODES'], ['logs', 'fa-list', 'ADM_LOGS'], ['appearance', 'fa-palette', 'ADM_APPEARANCE'],
];
const ICONS = ['fa-car-side', 'fa-car', 'fa-motorcycle', 'fa-truck-monster', 'fa-helicopter', 'fa-plane', 'fa-ship', 'fa-box-open', 'fa-boxes-stacked', 'fa-gift',
  'fa-crosshairs', 'fa-gun', 'fa-bomb', 'fa-shield-halved', 'fa-screwdriver-wrench', 'fa-toolbox', 'fa-hammer', 'fa-kit-medical', 'fa-burger', 'fa-mug-hot',
  'fa-shirt', 'fa-gem', 'fa-crown', 'fa-star', 'fa-fire', 'fa-bolt', 'fa-house', 'fa-key', 'fa-sack-dollar', 'fa-coins',
  'fa-dog', 'fa-paw', 'fa-mobile-screen', 'fa-laptop', 'fa-headset', 'fa-music', 'fa-palette', 'fa-wand-magic-sparkles', 'fa-ticket', 'fa-tag'];

window.adminEnter = () => { loadAdmin(S.adm.tab); };

async function loadAdmin(tab) {
  const a = S.adm;
  const map = {
    dashboard: ['admin:dashboard', {}, 'dash'], logs: ['admin:logs', { q: a.logQ }, 'logs'], players: ['admin:players', { q: a.playerQ }, 'players'],
    codes: ['admin:codes', { q: a.codeQ }, 'codes'], deals: ['admin:deals', {}, 'deals'],
  }[tab];
  if (tab === 'packages') { const r = await req('catalog'); if (r.data) { setCatalog(r.data); render(); } return; }
  if (!map) return;
  const r = await req(map[0], map[1]);
  if (r.error) { toast(errText(r), true); return; }
  a[map[2]] = r.data;
  render();
}

function admTable(head, rows, empty) {
  if (!rows.length) return `<div class="empty"><i class="fas fa-inbox"></i><b>${esc(empty || t('UI_NOTHING'))}</b></div>`;
  return `<table class="table"><thead><tr>${head.map(h => `<th class="${h[1] || ''}">${esc(h[0])}</th>`).join('')}</tr></thead><tbody>${rows.join('')}</tbody></table>`;
}
const loading = () => `<div class="empty"><i class="fas fa-circle-notch fa-spin"></i></div>`;

// ── page ─────────────────────────────────────────────────────────────────
VIEWS.admin = () => {
  if (!S.admin) return VIEWS.home();
  const a = S.adm;
  const body = (ADMV[a.tab] || ADMV.dashboard)();
  return `<div class="scroll" data-keep="adm-${a.tab}">
    <div class="head"><div class="head-txt"><h1>${esc(t('NAV_ADMIN'))}</h1><p>${esc(t('ADM_SUB'))}</p></div></div>
    <div class="tabs">${ADM_TABS.map(([k, i, l]) => `<button class="${a.tab === k ? 'on' : ''}" data-a="admTab" data-v="${k}"><i class="fas ${i}"></i>${esc(t(l))}</button>`).join('')}</div>
    ${body}
  </div>`;
};
const ADMV = {};

ADMV.dashboard = () => {
  const d = S.adm.dash;
  if (!d) return loading();
  const max = Math.max(1, ...d.days.map(x => Number(x.coins)));
  const days = [];
  for (let i = 13; i >= 0; i--) {
    const dt = new Date(Date.now() - i * 86400000);
    const key = `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}-${String(dt.getDate()).padStart(2, '0')}`;
    const row = d.days.find(x => x.day === key);
    days.push({ label: dt.getDate(), v: row ? Number(row.coins) : 0, n: row ? Number(row.sales) : 0 });
  }
  const topMax = Math.max(1, ...d.top.map(x => Number(x.sales)));
  const st = (tile, icon, label, value, withCoin) => `<div class="stat"><div class="tile ${tile}"><i class="fas ${icon}"></i></div><div class="stat-txt"><span>${esc(label)}</span><b>${withCoin ? coin() : ''}${value}</b></div></div>`;
  return `<div class="stats c6">
      ${st('', 'fa-boxes-stacked', t('D_PACKAGES'), num(d.packages))}
      ${st('', 'fa-sack-dollar', t('D_SALES'), num(d.totalSales), true)}
      ${st('a', 'fa-clock', t('D_DAY'), num(d.daySales), true)}
      ${st('w', 'fa-bag-shopping', t('D_PURCHASES'), num(d.purchases))}
      ${st('w', 'fa-coins', t('D_CIRCULATING'), num(d.circulating), true)}
      ${st('w', 'fa-users', t('D_ONLINE'), `${num(d.online)} <span class="muted" style="font-size:10px;font-weight:400">/ ${num(d.shopping)} ${esc(t('D_SHOPPING'))}</span>`)}
    </div>
    <div class="grid2" style="grid-template-columns:1.5fr 1fr">
      <div class="panel"><div class="panel-h"><h3>${esc(t('D_CHART'))}</h3><span class="chip">${esc(t('D_CODES_PENDING', d.pendingCodes))}</span></div>
        <div class="panel-b"><div class="chart">${days.map(x => `<div class="col"><div class="bar-v ${x.v ? '' : 'zero'}" data-v="${num(x.v)} · ${x.n}" style="height:${Math.max(2, x.v / max * 100)}%"></div><span>${x.label}</span></div>`).join('')}</div></div></div>
      <div class="panel"><div class="panel-h"><h3>${esc(t('D_TOP'))}</h3></div><div class="panel-b" style="padding-top:4px;padding-bottom:4px">
        ${d.top.length ? d.top.map((x, i) => `<div class="rank"><span class="n">${i + 1}</span><div class="thumb" style="width:30px;height:30px">${x.image ? `<img src="${esc(x.image)}">` : '<i class="fas fa-box"></i>'}</div>
          <div class="cell-t"><b>${esc(x.name)}</b><div class="meter"><i style="width:${x.sales / topMax * 100}%"></i></div></div><span class="muted" style="font-size:10.5px">${num(x.sales)}</span></div>`).join('') : `<div class="empty" style="padding:30px"><span>${esc(t('UI_NOTHING'))}</span></div>`}
      </div></div>
    </div>
    <div class="panel" style="margin-top:12px"><div class="panel-h"><h3>${esc(t('D_RECENT'))}</h3><button class="btn btn-text sm" data-a="admTab" data-v="logs">${esc(t('UI_SEE_ALL'))}</button></div>
      ${admTable([[t('TH_PLAYER')], [t('TH_PACKAGE')], [t('TH_PRICE'), 'num'], [t('TH_DATE'), 'num']], d.recent.map(r => `<tr><td><b>${esc(r.player || r.identifier)}</b></td>
        <td>${esc(r.name)} <span class="muted">x${num(r.quantity)}</span> ${r.giftedTo ? `<span class="chip teal"><i class="fas fa-gift"></i>${esc(r.giftedTo)}</span>` : ''} ${r.refunded ? `<span class="chip amber">${esc(t('UI_REFUNDED'))}</span>` : ''}</td>
        <td class="num"><b>${num(r.price)}</b></td><td class="num">${esc(ago(r.date))}</td></tr>`))}</div>`;
};

ADMV.packages = () => {
  const a = S.adm;
  const q = a.pkgQ.trim().toLowerCase();
  const list = S.items.filter(i => (a.pkgCat === 'all' || i.category === a.pkgCat) && (!q || i.name.toLowerCase().includes(q) || i.id.toLowerCase().includes(q)));
  return `<div class="toolbar">
      <div class="lsearch"><i class="fas fa-magnifying-glass"></i><input class="input" id="pkgq" placeholder="${esc(t('ADM_SEARCH_PKG'))}" value="${esc(a.pkgQ)}" data-f="adm.pkgQ" data-r></div>
      <select class="select" data-f="adm.pkgCat" data-r><option value="all">${esc(t('UI_ALL_TYPES'))}</option>${['vehicle', 'item', 'weapon', 'tool'].map(c => `<option value="${c}" ${a.pkgCat === c ? 'selected' : ''}>${esc(t('CAT_' + c.toUpperCase()))}</option>`).join('')}</select>
      <div class="sp"></div><button class="btn btn-teal" data-a="pkgEdit"><i class="fas fa-plus"></i>${esc(t('ADM_NEW_PKG'))}</button></div>
    <div class="panel">${admTable([[t('TH_PACKAGE')], [t('TH_TYPE')], [t('TH_PRICE'), 'num'], [t('TH_STOCK'), 'num'], [t('TH_SOLD'), 'num'], [t('TH_ON')], [t('UI_TRENDING')], ['', 'act']],
      list.map(i => `<tr><td><div class="cell"><div class="thumb">${i.images[0] ? `<img src="${esc(i.images[0])}">` : `<i class="fas ${CAT_ICON[i.category]}"></i>`}</div><div class="cell-t"><b>${esc(i.name)}</b><span>${esc(i.id)}${i.spawnName ? ' · ' + esc(i.spawnName) : i.itemName ? ' · ' + esc(i.itemName) + ' x' + i.itemCount : i.weaponName ? ' · ' + esc(i.weaponName) : ''}</span></div></div></td>
        <td>${esc(t('CAT_' + i.category.toUpperCase()))}</td>
        <td class="num"><b>${num(i.price)}</b>${i.sale ? ` <span class="strike">${num(i.basePrice)}</span>` : ''}</td>
        <td class="num">${i.stock == null ? '∞' : num(i.stock)}</td><td class="num">${num(i.sold)}</td>
        <td><button class="toggle ${i.enabled ? 'on' : ''}" data-a="pkgToggle" data-v="${esc(i.id)}|enabled"></button></td>
        <td><button class="toggle ${i.trending ? 'on' : ''}" data-a="pkgToggle" data-v="${esc(i.id)}|trending"></button></td>
        <td class="act"><button class="icon-btn" data-a="pkgMove" data-v="${esc(i.id)}|-1" title="${esc(t('UI_UP'))}"><i class="fas fa-arrow-up"></i></button><button class="icon-btn" data-a="pkgMove" data-v="${esc(i.id)}|1"><i class="fas fa-arrow-down"></i></button>
          <button class="icon-btn" data-a="pkgEdit" data-v="${esc(i.id)}"><i class="fas fa-pen"></i></button><button class="icon-btn danger" data-a="pkgDelete" data-v="${esc(i.id)}"><i class="fas fa-trash"></i></button></td></tr>`), t('UI_NO_RESULTS'))}</div>
    <div class="panel" style="margin-top:12px;border-color:var(--red-edge)"><div class="panel-h"><h3>${esc(t('ADM_DANGER'))}</h3><button class="btn btn-red sm" data-a="clearAll"><i class="fas fa-trash"></i>${esc(t('ADM_CLEAR'))}</button></div>
      <div class="panel-b hint">${esc(t('ADM_CLEAR_TXT'))}</div></div>`;
};

ADMV.categories = () => `<div class="toolbar"><p class="hint" style="flex:1">${esc(t('ADM_CAT_TXT'))}</p><button class="btn btn-teal" data-a="catEdit"><i class="fas fa-plus"></i>${esc(t('ADM_NEW_CAT'))}</button></div>
  <div class="panel">${admTable([[t('TH_CATEGORY')], [t('TH_SHOWS')], [t('TH_ITEMS'), 'num'], ['', 'act']], S.cats.map(c => `<tr>
    <td><div class="cell"><div class="tile w" style="width:30px;height:30px">${catIcon(c.icon, CAT_ICON[c.type] || 'fa-tag')}</div><div class="cell-t"><b>${esc(c.name)}</b><span>${esc(c.id)}</span></div></div></td>
    <td>${c.type ? `<span class="chip">${esc(t('ADM_ALL_OF', t('CAT_' + c.type.toUpperCase())))}</span>` : `<span class="chip teal">${esc(t('ADM_ASSIGNED'))}</span>`}</td>
    <td class="num">${num(catItems(c.id).length)}</td>
    <td class="act"><button class="icon-btn" data-a="catMove" data-v="${esc(c.id)}|up"><i class="fas fa-arrow-up"></i></button><button class="icon-btn" data-a="catMove" data-v="${esc(c.id)}|down"><i class="fas fa-arrow-down"></i></button>
      <button class="icon-btn" data-a="catEdit" data-v="${esc(c.id)}"><i class="fas fa-pen"></i></button><button class="icon-btn danger" data-a="catDelete" data-v="${esc(c.id)}"><i class="fas fa-trash"></i></button></td></tr>`))}</div>`;

ADMV.deals = () => {
  const list = S.adm.deals;
  if (!list) return loading();
  return `<div class="toolbar"><p class="hint" style="flex:1">${esc(t('ADM_DEAL_TXT'))}</p><button class="btn btn-teal" data-a="dealEdit"><i class="fas fa-plus"></i>${esc(t('ADM_NEW_DEAL'))}</button></div>
    <div class="panel">${admTable([[t('UI_DEAL')], [t('UI_PACKAGES'), 'num'], [t('TH_PRICE'), 'num'], [t('TH_STATUS')], ['', 'act']], list.map(d => `<tr>
      <td><div class="cell"><div class="thumb">${d.image ? `<img src="${esc(d.image)}">` : '<i class="fas fa-gift"></i>'}</div><div class="cell-t"><b>${esc(d.name)}</b><span>${esc(d.id)}</span></div></div></td>
      <td class="num">${d.items.length}</td><td class="num"><b>${num(d.price)}</b> <span class="muted">/ ${num(d.value)}</span></td>
      <td>${d.remaining == null ? `<span class="chip">${esc(t('UI_NO_EXPIRY'))}</span>` : d.remaining > 0 ? `<span class="chip teal">${esc(t('ADM_ENDS', clock(d.remaining)))}</span>` : `<span class="chip red">${esc(t('UI_EXPIRED'))}</span>`}</td>
      <td class="act"><button class="icon-btn" data-a="dealEdit" data-v="${esc(d.id)}"><i class="fas fa-pen"></i></button><button class="icon-btn danger" data-a="dealDelete" data-v="${esc(d.id)}"><i class="fas fa-trash"></i></button></td></tr>`), t('UI_NO_DEALS'))}</div>`;
};

ADMV.players = () => {
  const a = S.adm;
  return `<div class="toolbar"><div class="lsearch" style="max-width:340px"><i class="fas fa-magnifying-glass"></i><input class="input" id="plq" placeholder="${esc(t('ADM_SEARCH_PLAYER'))}" value="${esc(a.playerQ)}" data-f="adm.playerQ" data-live="playerSearch"></div>
      <div class="sp"></div><button class="btn btn-ghost" data-a="admRefresh"><i class="fas fa-rotate"></i>${esc(t('UI_REFRESH'))}</button></div>
    <div class="panel">${!a.players ? loading() : admTable([[t('TH_ID')], [t('TH_PLAYER')], [t('TH_BALANCE'), 'num'], [t('UI_TOTAL_SPENT'), 'num'], [t('TH_STATUS')], ['', 'act']], a.players.filter(p => {
      const q = a.playerQ.trim().toLowerCase();
      return !q || String(p.id || '') === q || p.name.toLowerCase().includes(q) || p.identifier.toLowerCase().includes(q);
    }).map(p => `<tr><td>${p.id ? `<span class="chip">${p.id}</span>` : '—'}</td><td><div class="cell-t"><b>${esc(p.name)}</b><span>${esc(p.identifier)}</span></div></td>
      <td class="num"><b>${num(p.coins)}</b></td><td class="num">${num(p.spent)}</td>
      <td>${p.online ? `<span class="chip teal">${esc(p.shopping ? t('ADM_SHOPPING') : t('ADM_ONLINE'))}</span>` : `<span class="chip">${esc(t('ADM_OFFLINE'))}</span>`}</td>
      <td class="act"><button class="btn btn-ghost sm" data-a="coinsEdit" data-v="${esc(p.identifier)}"><i class="fas fa-coins"></i>${esc(t('ADM_COINS'))}</button>
        <button class="icon-btn" data-a="ledger" data-v="${esc(p.identifier)}" title="${esc(t('HIST_LEDGER'))}"><i class="fas fa-clock-rotate-left"></i></button></td></tr>`), t('UI_NO_RESULTS'))}</div>`;
};

ADMV.codes = () => {
  const c = S.adm.codes;
  if (!c) return loading();
  return `<div class="grid2" style="grid-template-columns:1.4fr 1fr;align-items:start">
    <div class="panel"><div class="panel-h"><h3>${esc(t('ADM_TEBEX_CODES'))}</h3><button class="btn btn-teal sm" data-a="codeCreate"><i class="fas fa-plus"></i>${esc(t('ADM_NEW_CODE'))}</button></div>
      <div style="padding:10px 12px 0"><div class="lsearch" style="position:relative"><i class="fas fa-magnifying-glass" style="position:absolute;left:11px;top:50%;transform:translateY(-50%);font-size:10.5px;color:var(--ink-3)"></i><input class="input" style="padding-left:29px;height:30px" id="codeq" placeholder="${esc(t('ADM_SEARCH_CODE'))}" value="${esc(S.adm.codeQ)}" data-f="adm.codeQ" data-live="codeSearch"></div></div>
      ${admTable([[t('REDEEM_CODE')], [S.cfg.coinName, 'num'], [t('TH_STATUS')], ['', 'act']], c.codes.map(x => `<tr><td><div class="cell-t"><b style="font-family:monospace;font-size:10.5px">${esc(x.code)}</b><span>${esc(x.source === 'manual' ? t('ADM_MANUAL') : 'Tebex')} · ${esc(ago(x.created))}</span></div></td>
        <td class="num"><b>${num(x.coins)}</b></td>
        <td>${x.status === 'pending' ? `<span class="chip amber">${esc(t('ADM_PENDING'))}</span>` : `<span class="chip teal" title="${esc(x.redeemedBy || '')}">${esc(x.redeemedName || t('ADM_REDEEMED'))}</span>`}</td>
        <td class="act">${x.status === 'pending' ? `<button class="icon-btn" data-a="copy" data-v="${esc(x.code)}" title="${esc(t('UI_COPY'))}"><i class="fas fa-copy"></i></button><button class="icon-btn danger" data-a="codeDelete" data-v="${esc(x.code)}"><i class="fas fa-trash"></i></button>` : ''}</td></tr>`), t('ADM_NO_CODES'))}</div>
    <div class="panel"><div class="panel-h"><h3>${esc(t('ADM_PROMOS'))}</h3><button class="btn btn-teal sm" data-a="promoCreate"><i class="fas fa-plus"></i>${esc(t('ADM_NEW_PROMO'))}</button></div>
      ${admTable([[t('REDEEM_CODE')], [t('ADM_USES'), 'num'], ['', 'act']], c.promos.map(p => `<tr><td><div class="cell-t"><b>${esc(p.code)}</b><span>${num(p.coins)} ${esc(S.cfg.coinName)}${p.expires ? ' · ' + (p.expires > Date.now() / 1000 ? t('ADM_ENDS', clock(p.expires - Date.now() / 1000)) : t('UI_EXPIRED')) : ''}</span></div></td>
        <td class="num">${num(p.uses)}${p.maxUses ? ' / ' + num(p.maxUses) : ''}</td>
        <td class="act"><button class="icon-btn danger" data-a="promoDelete" data-v="${esc(p.code)}"><i class="fas fa-trash"></i></button></td></tr>`), t('ADM_NO_PROMOS'))}</div>
  </div>
  <p class="hint" style="margin-top:12px"><i class="fas fa-circle-info"></i> ${esc(t('ADM_TEBEX_HINT'))}</p>`;
};

ADMV.logs = () => {
  const a = S.adm;
  return `<div class="toolbar"><div class="lsearch" style="max-width:340px"><i class="fas fa-magnifying-glass"></i><input class="input" id="logq" placeholder="${esc(t('ADM_SEARCH_LOGS'))}" value="${esc(a.logQ)}" data-f="adm.logQ" data-live="logSearch"></div><div class="sp"></div>
      <button class="btn btn-ghost" data-a="admRefresh"><i class="fas fa-rotate"></i>${esc(t('UI_REFRESH'))}</button></div>
    <div class="panel">${!a.logs ? loading() : admTable([['#'], [t('TH_PLAYER')], [t('TH_PACKAGE')], [t('TH_PRICE'), 'num'], [t('TH_DATE'), 'num'], ['', 'act']], a.logs.map(r => `<tr>
      <td class="muted">${r.id}</td><td><div class="cell-t"><b>${esc(r.player || '—')}</b><span>${esc(r.identifier)}</span></div></td>
      <td>${esc(r.name)} <span class="muted">x${num(r.quantity)}</span> ${r.kind === 'deal' ? `<span class="chip">${esc(t('UI_DEAL'))}</span>` : ''} ${r.giftedTo ? `<span class="chip teal"><i class="fas fa-gift"></i>${esc(r.giftedTo)}</span>` : ''} ${r.plate ? `<span class="chip">${esc(r.plate)}</span>` : ''}</td>
      <td class="num"><b>${num(r.price)}</b></td><td class="num">${esc(ago(r.date))}</td>
      <td class="act">${r.refunded ? `<span class="chip amber">${esc(t('UI_REFUNDED'))}</span>` : `<button class="btn btn-ghost sm" data-a="refund" data-v="${r.id}"><i class="fas fa-rotate-left"></i>${esc(t('ADM_REFUND'))}</button>`}</td></tr>`), t('UI_NOTHING'))}</div>`;
};

ADMV.appearance = () => {
  const v = S.adm.theme || (S.adm.theme = Object.assign({}, S.settings));
  const color = (k, l) => `<div class="field"><label>${esc(t(l))}</label><div class="swatch-row"><input type="color" value="${esc(v[k])}" data-f="adm.theme.${k}" data-live="themeLive" data-r><input class="input" id="th-${k}" value="${esc(v[k])}" data-f="adm.theme.${k}" data-live="themeLive"></div></div>`;
  const range = (k, l, min, max, step, unit) => `<div class="field"><label>${esc(t(l))}</label><div class="range"><input type="range" min="${min}" max="${max}" step="${step}" value="${esc(v[k])}" data-f="adm.theme.${k}" data-live="themeLive" data-r><b>${esc(v[k])}${unit || ''}</b></div></div>`;
  return `<div class="grid2" style="align-items:start">
    <div class="panel"><div class="panel-h"><h3>${esc(t('TH_COLORS'))}</h3></div><div class="panel-b" style="display:flex;flex-direction:column;gap:12px">
      <div class="grid2">${color('accent', 'TH_ACCENT')}${color('danger', 'TH_DANGER')}${color('background', 'TH_BG')}${color('text', 'TH_TEXT')}</div>
      ${range('cardRadius', 'TH_RADIUS', 0, 20, 1, 'px')}</div></div>
    <div class="panel"><div class="panel-h"><h3>${esc(t('TH_MEDIA'))}</h3></div><div class="panel-b" style="display:flex;flex-direction:column;gap:12px">
      <div class="field"><label>${esc(t('TH_BG_IMAGE'))} <small>${esc(t('TH_URL_HINT'))}</small></label><input class="input" id="th-bg" value="${esc(v.bgImage)}" data-f="adm.theme.bgImage" data-live="themeLive" placeholder="https://..."></div>
      <div class="grid2">${range('bgOpacity', 'TH_BG_OPACITY', 0, 1, .01)}${range('bgBlur', 'TH_BG_BLUR', 0, 20, 1, 'px')}</div>
      <div class="field"><label>${esc(t('TH_COIN'))} <small>${esc(t('TH_COIN_HINT'))}</small></label><div class="swatch-row"><div class="tile w" style="font-size:18px">${coin()}</div><input class="input" id="th-coin" value="${esc(v.coinIcon)}" data-f="adm.theme.coinIcon" data-live="themeLive" data-r placeholder="https://..."></div></div>
    </div></div></div>
    <div class="toolbar" style="margin-top:14px"><div class="sp"></div><button class="btn btn-ghost" data-a="themeReset"><i class="fas fa-rotate-left"></i>${esc(t('TH_RESET'))}</button><button class="btn btn-teal" data-a="themeSave"><i class="fas fa-floppy-disk"></i>${esc(t('TH_SAVE'))}</button></div>`;
};

// ── package editor ───────────────────────────────────────────────────────
MODALS.pkg = () => {
  const f = S.modal.f;
  const typeSeg = ['vehicle', 'item', 'weapon', 'tool'].map(c => `<button class="${f.category === c ? 'on' : ''}" data-a="pkgType" data-v="${c}"><i class="fas ${CAT_ICON[c]}"></i>${esc(t('CAT_' + c.toUpperCase()))}</button>`).join('');
  const inp = (k, l, ph, hint, attrs) => `<div class="field"><label>${esc(t(l))}${hint ? ` <small>${esc(t(hint))}</small>` : ''}</label><input class="input" id="pf-${k}" value="${esc(f[k] ?? '')}" data-f="modal.f.${k}" data-r placeholder="${esc(ph || '')}" ${attrs || ''}></div>`;
  const custom = S.cats.filter(c => !c.type);
  const prev = { id: f.id || 'preview', name: f.name || t('PF_NAME'), category: f.category, price: Number(f.salePrice) >= 0 && f.salePrice !== '' && Number(f.salePrice) < Number(f.price) ? Number(f.salePrice) : Number(f.price) || 0,
    basePrice: Number(f.price) || 0, sale: f.salePrice !== '' && Number(f.salePrice) >= 0 && Number(f.salePrice) < Number(f.price), images: String(f.images || '').split('\n').map(x => x.trim()).filter(Boolean),
    itemCount: Number(f.itemCount) || 1, tags: String(f.tags || '').split(',').map(x => x.trim()).filter(Boolean), trending: f.trending, stock: f.stock === '' ? null : Number(f.stock), single: f.category === 'vehicle' || (f.category === 'weapon' && !f.itemName) };
  return modalFrame('w-lg', `<i class="fas fa-box"></i>${esc(f.editing ? t('PF_EDIT') : t('ADM_NEW_PKG'))}`, `<div class="m-body" data-keep="pkg"><div class="editor">
      <div class="editor-form">
        <div class="seg">${typeSeg}</div>
        <div class="grid2">${inp('name', 'PF_NAME', 'Truffade Adder')}${f.editing ? `<div class="field"><label>${esc(t('PF_ID'))}</label><input class="input" value="${esc(f.id)}" disabled></div>` : inp('id', 'PF_ID', 'veh_adder', 'PF_ID_HINT')}</div>
        ${f.category === 'vehicle' ? inp('spawnName', 'PF_SPAWN', 'adder', 'PF_SPAWN_HINT') : ''}
        ${f.category === 'weapon' ? `<div class="grid2">${inp('weaponName', 'PF_WEAPON', 'WEAPON_PISTOL', 'PF_WEAPON_HINT')}${inp('itemName', 'PF_WEAPON_ITEM', 'weapon_pistol', 'PF_OPTIONAL')}</div>` : ''}
        ${f.category === 'item' || f.category === 'tool' || (f.category === 'weapon' && f.itemName) ? `<div class="grid2">${f.category !== 'weapon' ? inp('itemName', 'PF_ITEM', 'repairkit', 'PF_ITEM_HINT') : '<div></div>'}${inp('itemCount', 'PF_COUNT', '1', '', 'inputmode="numeric"')}</div>` : ''}
        <div class="grid3">${inp('price', 'PF_PRICE', '1000', '', 'inputmode="numeric"')}${inp('salePrice', 'PF_SALE', '', 'PF_OPTIONAL', 'inputmode="numeric"')}${inp('saleHours', 'PF_SALE_HOURS', f.editing && f.saleEndsRaw ? t('PF_KEEP') : '', 'PF_SALE_HOURS_HINT', 'inputmode="numeric"')}</div>
        <div class="field"><label>${esc(t('PF_DESC'))}</label><textarea class="textarea" id="pf-desc" data-f="modal.f.description" data-r>${esc(f.description || '')}</textarea></div>
        <div class="field"><label>${esc(t('PF_IMAGES'))} <small>${esc(t('PF_IMAGES_HINT'))}</small></label><textarea class="textarea" id="pf-img" data-f="modal.f.images" data-r style="min-height:54px">${esc(f.images || '')}</textarea></div>
        <div class="grid2">${inp('tags', 'PF_TAGS', 'supercar, fast', 'PF_TAGS_HINT')}
          <div class="field"><label>${esc(t('PF_CATEGORY'))} <small>${esc(t('PF_OPTIONAL'))}</small></label><select class="select" data-f="modal.f.customCategory"><option value="none">${esc(t('PF_NONE'))}</option>${custom.map(c => `<option value="${esc(c.id)}" ${f.customCategory === c.id ? 'selected' : ''}>${esc(c.name)}</option>`).join('')}</select></div></div>
        <div class="grid2">${inp('stock', 'PF_STOCK', '∞', 'PF_STOCK_HINT', 'inputmode="numeric"')}${inp('playerLimit', 'PF_LIMIT', '∞', 'PF_LIMIT_HINT', 'inputmode="numeric"')}</div>
        <div class="grid2"><div class="check-row" data-a="pfFlag" data-v="trending"><div><b>${esc(t('UI_TRENDING'))}</b><span>${esc(t('PF_TRENDING_HINT'))}</span></div><span class="toggle ${f.trending ? 'on' : ''}"></span></div>
          <div class="check-row" data-a="pfFlag" data-v="enabled"><div><b>${esc(t('PF_VISIBLE'))}</b><span>${esc(t('PF_VISIBLE_HINT'))}</span></div><span class="toggle ${f.enabled ? 'on' : ''}"></span></div></div>
      </div>
      <div class="editor-prev"><span class="hint">${esc(t('PF_PREVIEW'))}</span>${card(prev)}</div>
    </div></div>`,
    `${f.editing ? `<button class="btn btn-red" data-a="pkgDelete" data-v="${esc(f.id)}"><i class="fas fa-trash"></i>${esc(t('UI_DELETE'))}</button>` : ''}<div class="sp"></div>
     <button class="btn btn-ghost" data-a="closeModal">${esc(t('UI_CANCEL'))}</button><button class="btn btn-teal" data-a="pkgSave" ${S.busy ? 'disabled' : ''}><i class="fas fa-floppy-disk"></i>${esc(t('UI_SAVE'))}</button>`);
};

// ── category editor ──────────────────────────────────────────────────────
MODALS.cat = () => {
  const f = S.modal.f;
  const url = /^(https?:|data:|nui:)/.test(f.icon || '');
  return modalFrame('w-md', `<i class="fas fa-layer-group"></i>${esc(f.id ? t('CF_EDIT') : t('ADM_NEW_CAT'))}`, `<div class="m-body">
      <div class="field"><label>${esc(t('PF_NAME'))}</label><input class="input" id="cf-name" value="${esc(f.name || '')}" data-f="modal.f.name" data-r placeholder="VIP"></div>
      <div class="field"><label>${esc(t('CF_ICON'))}</label><div class="icon-grid">${ICONS.map(i => `<button class="${f.icon === i ? 'on' : ''}" data-a="cfIcon" data-v="${i}"><i class="fas ${i}"></i></button>`).join('')}</div></div>
      <div class="field"><label>${esc(t('CF_ICON_URL'))} <small>${esc(t('PF_OPTIONAL'))}</small></label><input class="input" id="cf-url" value="${esc(url ? f.icon : '')}" data-f="modal.f.icon" data-r placeholder="https://..."></div>
      <div class="nav on" style="pointer-events:none;width:220px">${catIcon(f.icon)}<span class="lbl">${esc(f.name || t('PF_NAME'))}</span></div>
    </div>`,
    `<div class="sp"></div><button class="btn btn-ghost" data-a="closeModal">${esc(t('UI_CANCEL'))}</button><button class="btn btn-teal" data-a="catSave"><i class="fas fa-floppy-disk"></i>${esc(t('UI_SAVE'))}</button>`);
};

// ── deal editor ──────────────────────────────────────────────────────────
MODALS.dealEdit = () => {
  const f = S.modal.f;
  const sel = new Set(f.items);
  const q = (f.q || '').toLowerCase();
  const value = f.items.reduce((s, id) => s + ((item(id) || {}).basePrice || 0), 0);
  const inp = (k, l, ph, hint) => `<div class="field"><label>${esc(t(l))}${hint ? ` <small>${esc(t(hint))}</small>` : ''}</label><input class="input" id="df-${k}" value="${esc(f[k] ?? '')}" data-f="modal.f.${k}" data-r placeholder="${esc(ph || '')}"></div>`;
  return modalFrame('w-lg', `<i class="fas fa-tags"></i>${esc(f.id ? t('DF_EDIT') : t('ADM_NEW_DEAL'))}`, `<div class="m-body" data-keep="dealed"><div class="editor">
      <div class="editor-form">
        ${inp('name', 'PF_NAME', 'Starter Bundle')}
        <div class="grid2">${inp('price', 'PF_PRICE', '3500')}${inp('hours', 'DF_HOURS', f.id ? t('PF_KEEP') : '168', 'DF_HOURS_HINT')}</div>
        ${inp('image', 'DF_IMAGE', 'https://...', 'PF_OPTIONAL')}
        <div class="field"><label>${esc(t('PF_DESC'))}</label><textarea class="textarea" id="df-desc" data-f="modal.f.description" data-r>${esc(f.description || '')}</textarea></div>
        <div class="confirm-box"><div class="confirm-line"><span>${esc(t('DF_VALUE'))}</span><b>${coin()}${num(value)}</b></div><div class="confirm-line"><span>${esc(t('DF_SAVING'))}</span><b>${value > 0 && Number(f.price) < value ? Math.round((1 - Number(f.price) / value) * 100) + '%' : '—'}</b></div></div>
      </div>
      <div class="editor-form">
        <div class="field"><label>${esc(t('DF_ITEMS', f.items.length, S.cfg.dealMaxItems))}</label><input class="input" id="df-q" value="${esc(f.q || '')}" data-f="modal.f.q" data-r placeholder="${esc(t('ADM_SEARCH_PKG'))}"></div>
        <div class="pick-list" style="max-height:330px">${S.items.filter(i => !q || i.name.toLowerCase().includes(q)).sort((a, b) => sel.has(b.id) - sel.has(a.id)).map(i => `<div class="pick ${sel.has(i.id) ? 'on' : ''}" data-a="dfPick" data-v="${esc(i.id)}"><span class="cb"><i class="fas fa-check"></i></span>
          <div class="thumb">${i.images[0] ? `<img src="${esc(i.images[0])}">` : `<i class="fas ${CAT_ICON[i.category]}"></i>`}</div><div class="cell-t"><b>${esc(i.name)}</b><span>${esc(t('CAT_' + i.category.toUpperCase()))}</span></div><span class="muted">${num(i.basePrice)}</span></div>`).join('')}</div>
      </div>
    </div></div>`,
    `${f.id ? `<button class="btn btn-red" data-a="dealDelete" data-v="${esc(f.id)}"><i class="fas fa-trash"></i>${esc(t('UI_DELETE'))}</button>` : ''}<div class="sp"></div>
     <button class="btn btn-ghost" data-a="closeModal">${esc(t('UI_CANCEL'))}</button><button class="btn btn-teal" data-a="dealSave"><i class="fas fa-floppy-disk"></i>${esc(t('UI_SAVE'))}</button>`);
};

// ── coins + ledger + code modals ─────────────────────────────────────────
MODALS.coins = () => {
  const m = S.modal;
  const p = m.p;
  return modalFrame('w-sm', `<i class="fas fa-coins"></i>${esc(p.name)}`, `<div class="m-body">
      <div class="confirm-box"><div class="confirm-line"><span>${esc(t('UI_BALANCE'))}</span><b>${coin()}${num(p.coins)}</b></div></div>
      <div class="seg">${['give', 'remove', 'set'].map(k => `<button class="${m.mode === k ? 'on' : ''}" data-a="coinsMode" data-v="${k}">${esc(t('ADM_MODE_' + k.toUpperCase()))}</button>`).join('')}</div>
      <div class="field"><label>${esc(t('UI_AMOUNT'))}</label><input class="input" id="camt" value="${esc(m.amount || '')}" data-f="modal.amount" data-r data-enter="coinsGo" inputmode="numeric"></div>
    </div>`,
    `<div class="sp"></div><button class="btn btn-ghost" data-a="closeModal">${esc(t('UI_CANCEL'))}</button><button class="btn btn-teal" data-a="coinsGo" ${m.amount !== '' && m.amount != null ? '' : 'disabled'}>${esc(t('UI_CONFIRM'))}</button>`);
};

MODALS.ledger = () => {
  const m = S.modal;
  return modalFrame('w-md', `<i class="fas fa-clock-rotate-left"></i>${esc(m.name)}`, `<div class="m-body" style="padding:0">${!m.rows ? loading() : admTable([[t('TH_ACTIVITY')], [t('TH_CHANGE'), 'num'], [t('TH_BALANCE'), 'num'], [t('TH_DATE'), 'num']],
    m.rows.map(l => `<tr><td><div class="cell-t"><b>${esc(t('R_' + l.reason.toUpperCase()))}</b><span>${esc(l.note || '')}</span></div></td><td class="num"><span class="delta ${l.delta >= 0 ? 'p' : 'n'}">${l.delta >= 0 ? '+' : ''}${num(l.delta)}</span></td><td class="num">${num(l.balance)}</td><td class="num">${esc(ago(l.date))}</td></tr>`), t('HIST_EMPTY'))}</div>`);
};

MODALS.code = () => {
  const m = S.modal;
  const promo = m.promo;
  if (m.created) {
    return modalFrame('w-sm', '', `<div class="m-body">${resultView(true, t('ADM_CODE_READY'), t('ADM_CODE_READY_TXT'), `<span class="plate" style="letter-spacing:.06em">${esc(m.created)}</span>`)}</div>`,
      `<button class="btn btn-ghost" data-a="copy" data-v="${esc(m.created)}"><i class="fas fa-copy"></i>${esc(t('UI_COPY'))}</button><div class="sp"></div><button class="btn btn-teal" data-a="closeModal">${esc(t('UI_CONTINUE'))}</button>`);
  }
  const inp = (k, l, ph, hint) => `<div class="field"><label>${esc(t(l))}${hint ? ` <small>${esc(t(hint))}</small>` : ''}</label><input class="input" id="cc-${k}" value="${esc(m[k] || '')}" data-f="modal.${k}" data-r placeholder="${esc(ph || '')}"></div>`;
  return modalFrame('w-sm', `<i class="fas fa-ticket"></i>${esc(promo ? t('ADM_NEW_PROMO') : t('ADM_NEW_CODE'))}`, `<div class="m-body">
      ${inp('code', 'REDEEM_CODE', promo ? 'SUMMER25' : t('ADM_AUTO'), promo ? '' : 'PF_OPTIONAL')}
      ${inp('coins', 'UI_AMOUNT', '500')}
      ${promo ? `<div class="grid2">${inp('maxUses', 'ADM_MAX_USES', '∞', 'ADM_ZERO_UNLIMITED')}${inp('hours', 'DF_HOURS', '∞', 'ADM_ZERO_NEVER')}</div>` : ''}
    </div>`,
    `<div class="sp"></div><button class="btn btn-ghost" data-a="closeModal">${esc(t('UI_CANCEL'))}</button><button class="btn btn-teal" data-a="codeGo">${esc(t('UI_CREATE'))}</button>`);
};

// ── actions ──────────────────────────────────────────────────────────────
ACT.admTab = v => { S.adm.tab = v; S.page = 'admin'; render(); loadAdmin(v); };
ACT.admRefresh = () => loadAdmin(S.adm.tab);
let admSearchTimer;
const debounced = tab => () => { clearTimeout(admSearchTimer); admSearchTimer = setTimeout(() => loadAdmin(tab), 300); };
ACT.logSearch = debounced('logs');
ACT.codeSearch = debounced('codes');
ACT.playerSearch = () => { render(); const n = S.adm.playerQ.trim().length; if (n >= 2 || n === 0) debounced('players')(); };
ACT.copy = v => {
  const ta = document.createElement('textarea');
  ta.value = v; document.body.appendChild(ta); ta.select();
  try { document.execCommand('copy'); toast(t('UI_COPIED')); } catch (e) { }
  ta.remove();
};

ACT.pkgEdit = v => {
  const it = v ? item(v) : null;
  const f = it ? {
    editing: true, id: it.id, name: it.name, category: it.category, description: it.description, price: String(it.basePrice), salePrice: it.salePrice != null ? String(it.salePrice) : '',
    saleHours: '', saleEndsRaw: it.saleEndsRaw, images: it.images.join('\n'), spawnName: it.spawnName || '', itemName: it.itemName || '', itemCount: String(it.itemCount || 1),
    weaponName: it.weaponName || '', tags: it.tags.join(', '), customCategory: it.customCategory || 'none', stock: it.stock != null ? String(it.stock) : '',
    playerLimit: it.playerLimit ? String(it.playerLimit) : '', trending: it.trending, enabled: it.enabled,
  } : { category: 'vehicle', price: '', salePrice: '', saleHours: '', images: '', itemCount: '1', tags: '', stock: '', playerLimit: '', trending: false, enabled: true, customCategory: 'none' };
  openModal('pkg', { f });
  render();
};
ACT.pkgType = v => { S.modal.f.category = v; render(); };
ACT.pfFlag = v => { S.modal.f[v] = !S.modal.f[v]; render(); };
ACT.pkgSave = async () => {
  const f = S.modal.f;
  const payload = Object.assign({}, f, {
    tags: String(f.tags || '').split(',').map(x => x.trim()).filter(Boolean),
    images: String(f.images || '').split('\n').map(x => x.trim()).filter(Boolean),
    salePrice: f.salePrice === '' ? null : f.salePrice, stock: f.stock === '' ? null : f.stock, playerLimit: f.playerLimit === '' ? null : f.playerLimit,
    saleHours: f.saleHours === '' ? null : f.saleHours,
  });
  const r = await call('admin:item:save', payload, { success: t('ADM_SAVED') });
  if (!r) return;
  closeModal();
  await reloadCatalog();
};
ACT.pkgDelete = v => {
  const it = item(v);
  confirmBox(t('ADM_DELETE_PKG'), t('ADM_DELETE_TXT', it ? it.name : v), async () => {
    const r = await call('admin:item:delete', { id: v }, { success: t('ADM_DELETED') });
    if (r) await reloadCatalog();
    return !!r;
  }, { danger: true, ok: t('UI_DELETE') });
};
ACT.pkgToggle = async v => {
  const [id, field] = v.split('|');
  const it = item(id);
  if (it) { it[field] = !it[field]; render(); }
  const r = await req('admin:item:toggle', { id, field });
  if (r.error) { toast(errText(r), true); if (it) it[field] = !it[field]; render(); }
};
ACT.pkgMove = async v => {
  const [id, dir] = v.split('|');
  const i = S.items.findIndex(x => x.id === id);
  const j = i + Number(dir);
  if (i < 0 || j < 0 || j >= S.items.length) return;
  [S.items[i], S.items[j]] = [S.items[j], S.items[i]];
  render();
  await req('admin:item:order', { ids: S.items.map(x => x.id) });
};
ACT.clearAll = () => confirmBox(t('ADM_CLEAR'), t('ADM_CLEAR_TXT'), async m => {
  const r = await call('admin:clear', { confirm: m.value }, { success: t('ADM_CLEARED') });
  if (r) await reloadCatalog();
  return !!r;
}, { danger: true, input: 'CLEAR', ok: t('ADM_CLEAR') });

ACT.catEdit = v => {
  const c = v ? S.cats.find(x => x.id === v) : null;
  openModal('cat', { f: c ? { id: c.id, name: c.name, icon: c.icon } : { icon: 'fa-star' } });
  render();
};
ACT.cfIcon = v => { S.modal.f.icon = v; render(); };
ACT.catSave = async () => {
  const r = await call('admin:category:save', S.modal.f, { success: t('ADM_SAVED') });
  if (!r) return;
  closeModal();
  await reloadCatalog();
};
ACT.catDelete = v => {
  const c = S.cats.find(x => x.id === v);
  confirmBox(t('ADM_DELETE_CAT'), t('ADM_DELETE_CAT_TXT', c ? c.name : v), async () => {
    const r = await call('admin:category:delete', { id: v }, { success: t('ADM_DELETED') });
    if (r) await reloadCatalog();
    return !!r;
  }, { danger: true, ok: t('UI_DELETE') });
};
ACT.catMove = async v => {
  const [id, dir] = v.split('|');
  await req('admin:category:move', { id, dir });
  await reloadCatalog();
};

ACT.dealEdit = v => {
  const d = v ? (S.adm.deals || []).find(x => x.id === v) : null;
  openModal('dealEdit', { f: d ? { id: d.id, name: d.name, price: String(d.price), image: d.image, description: d.description, items: d.itemIds.slice(), hours: '' }
    : { items: [], price: '', hours: '168', image: '', description: '' } });
  render();
};
ACT.dfPick = v => {
  const f = S.modal.f;
  const i = f.items.indexOf(v);
  if (i >= 0) f.items.splice(i, 1);
  else if (f.items.length < S.cfg.dealMaxItems) f.items.push(v);
  else toast(t('ERR_DEAL_ITEMS', S.cfg.dealMaxItems), true);
  render();
};
ACT.dealSave = async () => {
  const f = S.modal.f;
  const r = await call('admin:deal:save', Object.assign({}, f, { keepExpiry: !!f.id && f.hours === '' }), { success: t('ADM_SAVED') });
  if (!r) return;
  closeModal();
  await reloadCatalog();
  loadAdmin('deals');
};
ACT.dealDelete = v => confirmBox(t('ADM_DELETE_DEAL'), t('ADM_DELETE_TXT', v), async () => {
  const r = await call('admin:deal:delete', { id: v }, { success: t('ADM_DELETED') });
  if (r) { await reloadCatalog(); loadAdmin('deals'); }
  return !!r;
}, { danger: true, ok: t('UI_DELETE') });

ACT.coinsEdit = v => {
  const p = (S.adm.players || []).find(x => x.identifier === v);
  openModal('coins', { p, mode: 'give', amount: '' });
  render();
};
ACT.coinsMode = v => { S.modal.mode = v; render(); };
ACT.coinsGo = async () => {
  const m = S.modal;
  const r = await call('admin:coins', { identifier: m.p.identifier, mode: m.mode, amount: m.amount }, { success: t('ADM_COINS_DONE') });
  if (!r) return;
  m.p.coins = r.coins;
  if (m.p.id === S.me.serverId) setCoins(r.coins);
  closeModal();
  render();
};
ACT.ledger = async v => {
  const p = (S.adm.players || []).find(x => x.identifier === v);
  const m = { name: p ? p.name : v };
  openModal('ledger', m);
  render();
  const r = await req('admin:ledger', { identifier: v });
  if (S.modal && S.modal.type === 'ledger') { S.modal.rows = r.data || []; render(); }
};
ACT.refund = v => confirmBox(t('ADM_REFUND'), t('ADM_REFUND_TXT'), async () => {
  const r = await call('admin:refund', { id: Number(v) }, { success: t('ADM_REFUNDED') });
  if (r) loadAdmin('logs');
  return !!r;
});

ACT.codeCreate = () => { openModal('code', { promo: false }); render(); };
ACT.promoCreate = () => { openModal('code', { promo: true }); render(); };
ACT.codeGo = async () => {
  const m = S.modal;
  const r = await call(m.promo ? 'admin:promo:create' : 'admin:code:create', { code: m.code, coins: m.coins, maxUses: m.maxUses, hours: m.hours });
  if (!r) return;
  m.created = r.code;
  render();
  loadAdmin('codes');
};
ACT.codeDelete = v => confirmBox(t('ADM_DELETE_CODE'), t('ADM_DELETE_TXT', v), async () => {
  const r = await call('admin:code:delete', { code: v }, { success: t('ADM_DELETED') });
  if (r) loadAdmin('codes');
  return !!r;
}, { danger: true, ok: t('UI_DELETE') });
ACT.promoDelete = v => confirmBox(t('ADM_DELETE_CODE'), t('ADM_DELETE_TXT', v), async () => {
  const r = await call('admin:promo:delete', { code: v }, { success: t('ADM_DELETED') });
  if (r) loadAdmin('codes');
  return !!r;
}, { danger: true, ok: t('UI_DELETE') });

ACT.themeLive = () => { applyTheme(S.adm.theme); S.settings = Object.assign({}, S.settings, { coinIcon: S.adm.theme.coinIcon, bgImage: S.adm.theme.bgImage }); };
ACT.themeSave = async () => {
  const r = await call('admin:settings', { values: S.adm.theme }, { success: t('ADM_SAVED') });
  if (r) { S.settings = r; S.adm.theme = null; applyTheme(r); render(); }
};
ACT.themeReset = () => confirmBox(t('TH_RESET'), t('TH_RESET_TXT'), async () => {
  const r = await call('admin:settings', { reset: true }, { success: t('ADM_SAVED') });
  if (r) { S.settings = r; S.adm.theme = null; applyTheme(r); }
  return !!r;
});
