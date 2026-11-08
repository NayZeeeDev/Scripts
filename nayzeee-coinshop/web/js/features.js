/* ════════════════════════════════════════════════════════════════════════
   nayzeee-coinshop — get coins, rewards (ranks, daily streak, memberships),
   scheduled sale banners and the 3D vehicle showroom
   ════════════════════════════════════════════════════════════════════════ */
'use strict';

// ── shared bits ──────────────────────────────────────────────────────────
// Rank colour as CSS variables (solid, wash, edge, glow, dark) without color-mix, for older CEF builds
function rankVars(color) {
  const c = hexToRgb(color) || [8, 175, 162];
  const a = x => `rgba(${c.join(',')},${x})`;
  return `--rc:rgb(${c.join(',')});--rc-w:${a(.14)};--rc-e:${a(.42)};--rc-g:${a(.28)};--rc-d:rgb(${c.map(v => Math.round(v * .55)).join(',')})`;
}
function rankChip(r, big) {
  if (!r) return '';
  return `<span class="rank-chip ${big ? 'big' : ''}" style="${rankVars(r.color)}"><i class="fas ${esc(r.icon || 'fa-medal')}"></i>${esc(r.name)}</span>`;
}
const activeMember = id => (S.me.memberships || []).find(m => m.itemId === id && m.active);
function saleGo(s) { return s.scope === 'all' ? 'browse:sale' : 'browse:' + s.scope.replace(/^cat:/, ''); }

function saleBanners() {
  const live = S.sales.filter(s => s.live), soon = S.sales.filter(s => !s.live);
  return live.map(s => `<div class="sale-banner">
      <div class="sale-pct"><b>${num(s.percent)}%</b><span>${esc(t('SALE_TAG'))}</span></div>
      <div class="sale-txt"><b>${esc(s.name)}</b><span>${esc(t('SALE_LIVE', s.percent, s.scopeName))}</span></div>
      <span class="timer"><i class="fas fa-clock"></i>${esc(t('SALE_ENDS'))} <b data-until="${s.endsAt}">${clock(s.endsAt - Date.now() / 1000)}</b></span>
      <button class="btn btn-teal" data-a="go" data-v="${esc(saleGo(s))}">${esc(t('SALE_SHOP'))}<i class="fas fa-arrow-right"></i></button>
    </div>`).join('')
    + soon.map(s => `<div class="sale-soon"><i class="fas fa-hourglass-half"></i><b>${esc(s.name)}</b><span>${esc(t('SALE_LIVE', s.percent, s.scopeName))}</span>
      <span class="timer">${esc(t('SALE_SOON'))} <b data-until="${s.startsAt}">${clock(s.startsAt - Date.now() / 1000)}</b></span></div>`).join('');
}

function dailyStrip() {
  if (!S.cfg.daily || !S.me.daily) return '';
  return `<div class="daily-strip" data-a="go" data-v="rewards"><div class="tile"><i class="fas fa-calendar-check"></i></div>
    <div><b>${esc(t('DAILY_READY_HOME'))}</b><span>${esc(t('DAILY_READY_SUB', num(S.me.daily), S.cfg.coinName))}</span></div>
    <button class="btn btn-teal sm">${esc(t('DAILY_CLAIM_NOW'))}<i class="fas fa-arrow-right"></i></button></div>`;
}

// ── get coins ────────────────────────────────────────────────────────────
VIEWS.coins = () => {
  const list = S.cfg.coinPackages || [];
  const rank = S.me.rank;
  const per = p => p.coins > 0 && parseFloat(String(p.price).replace(/[^\d.]/g, '')) > 0 ? parseFloat(String(p.price).replace(/[^\d.]/g, '')) / p.coins * 100 : null;
  const sym = p => (String(p.price).match(/^[^\d]*/) || [''])[0];
  const steps = [['fa-hand-pointer', 'COINS_STEP_1'], ['fa-credit-card', 'COINS_STEP_2'], ['fa-ticket', 'COINS_STEP_3']];
  return `<div class="scroll" data-keep="coins">
    <div class="head"><div class="head-txt"><h1>${esc(t('NAV_COINS'))}</h1><p>${esc(t('COINS_SUB'))}</p></div>
      <div class="wallet-big">${coin()}<div><span>${esc(t('UI_BALANCE'))}</span><b>${num(S.me.coins)}</b></div></div></div>
    <div class="steps-row">${steps.map(([i, k], n) => `<div class="srow"><span class="n">${n + 1}</span><i class="fas ${i}"></i>${esc(t(k))}</div>${n < 2 ? '<i class="fas fa-chevron-right sep"></i>' : ''}`).join('')}</div>
    ${list.length ? `<div class="coin-grid">${list.map(p => `<div class="coin-tile ${p.tag ? 'tag-' + esc(p.tag) : ''}" data-a="openLink" data-v="${esc(p.url)}">
        ${p.tag ? `<span class="coin-tag">${esc(t(p.tag === 'best' ? 'COINS_BEST' : 'COINS_POPULAR'))}</span>` : ''}
        <div class="coin-art">${coin()}${p.coins >= 2000 ? coin() : ''}${p.coins >= 5000 ? coin() : ''}</div>
        <b class="coin-amt">${num(p.coins)}</b><span class="coin-name">${esc(p.label || S.cfg.coinName)}</span>
        ${p.bonus ? `<span class="chip green">${esc(t('COINS_BONUS', p.bonus))}</span>` : '<span class="chip ghost">&nbsp;</span>'}
        <div class="coin-price">${esc(p.price)}</div>
        ${per(p) ? `<span class="coin-per">${esc(t('COINS_PER_100', sym(p) + per(p).toFixed(2)))}</span>` : ''}
        <button class="btn btn-teal full">${esc(t('COINS_BUY'))}<i class="fas fa-arrow-up-right-from-square"></i></button>
      </div>`).join('')}</div>`
      : `<div class="empty"><i class="fas fa-coins"></i><b>${esc(t('COINS_NONE'))}</b><span>${esc(t('COINS_NONE_SUB'))}</span><button class="btn btn-teal" data-a="store">${esc(t('UI_BUY_COINS'))}</button></div>`}
    ${rank && rank.bonus ? `<div class="callout rank-callout" style="${rankVars(rank.color)}"><i class="fas ${esc(rank.icon)}"></i><div><b>${esc(t('COINS_RANK_NOTE', rank.name, rank.bonus))}</b></div></div>` : ''}
    <div class="callout"><i class="fas fa-ticket"></i><div><b>${esc(t('COINS_HAVE_ORDER'))}</b><span>${esc(t('COINS_HAVE_ORDER_SUB'))}</span></div><button class="btn btn-teal" data-a="redeem"><i class="fas fa-ticket"></i>${esc(t('UI_REDEEM_CODE'))}</button></div>
    <p class="hint center"><i class="fas fa-lock"></i> ${esc(t('COINS_SECURE'))}</p>
  </div>`;
};
ACT.openLink = v => openUrl(v);

// ── rewards ──────────────────────────────────────────────────────────────
async function loadRewards() {
  const r = await req('rewards');
  if (!r.data) return;
  S.rewards = r.data;
  S.me.rank = r.data.rank;
  S.me.memberships = r.data.memberships;
  S.me.daily = r.data.daily && r.data.daily.ready ? r.data.daily.amount : false;
  const now = Date.now() / 1000;
  if (r.data.daily) r.data.daily.resetAt = now + r.data.daily.resetIn;
  (r.data.memberships || []).forEach(m => { m.endsAt = now + m.remaining; });
  render();
}

function rankCard(rk, ranks) {
  if (!rk) return '';
  const nx = rk.next;
  return `<div class="panel rank-card" style="${rankVars(rk.color)}">
      <div class="rank-top"><div class="rank-emblem"><i class="fas ${esc(rk.icon)}"></i></div>
        <div class="rank-main"><span>${esc(t('RANK_TITLE'))}</span><b>${esc(rk.name)}</b><em>${esc(rk.bonus ? t('RANK_BONUS', rk.bonus) : t('RANK_NO_BONUS'))}</em></div>
        <div class="rank-spent"><span>${esc(t('RANK_SPENT'))}</span><b>${coin()}${num(rk.spent)}</b></div></div>
      <div class="rank-bar"><i style="width:${Math.round(rk.progress * 100)}%"></i></div>
      <div class="rank-foot">${nx ? `<span>${esc(t('RANK_NEXT', num(nx.need), nx.name))}</span>${rankChip(nx)}` : `<span>${esc(t('RANK_MAX'))}</span>`}</div>
      ${ranks && ranks.length > 1 ? `<div class="rank-ladder">${ranks.map((r, i) => `<div class="rung ${i + 1 === rk.index ? 'on' : i + 1 < rk.index ? 'done' : ''}" style="${rankVars(r.color)}">
          <i class="fas ${esc(r.icon)}"></i><b>${esc(r.name)}</b><span>${esc(t('RANK_FROM', num(r.spent)))}</span><em>${esc(r.bonus ? t('RANK_PERK', r.bonus) : '—')}</em>
          ${i + 1 === rk.index ? `<span class="you">${esc(t('RANK_YOU'))}</span>` : ''}</div>`).join('')}</div>` : ''}
    </div>`;
}

function dailyCard(d) {
  if (!d) return '';
  return `<div class="panel daily-card">
      <div class="panel-h"><h3><i class="fas fa-calendar-check teal"></i> ${esc(t('DAILY_TITLE'))}</h3>
        ${d.streak ? `<span class="chip amber"><i class="fas fa-fire"></i>${esc(t('DAILY_STREAK', d.streak))}</span>` : ''}<span class="chip">${esc(t('DAILY_TOTAL', num(d.claims)))}</span></div>
      <div class="panel-b"><p class="hint">${esc(d.lost ? t('DAILY_LOST') : t('DAILY_SUB'))}</p>
        <div class="days">${d.rewards.map((amt, i) => { const n = i + 1; const st = n < d.day || (n === d.day && d.claimed) ? 'done' : n === d.day ? 'today' : '';
          return `<div class="day ${st} ${n === d.rewards.length ? 'big' : ''}"><span>${esc(t('DAILY_DAY', n))}</span>${n === d.rewards.length ? '<i class="fas fa-gift"></i>' : coin()}<b>${num(amt)}</b>${st === 'done' ? '<i class="fas fa-check ok"></i>' : ''}</div>`; }).join('')}</div>
        <div class="daily-foot">${d.claimed
          ? `<span class="muted"><i class="fas fa-circle-check teal"></i> ${esc(t('DAILY_CLAIMED'))} · ${esc(t('DAILY_NEXT_IN'))} <b data-until="${d.resetAt}">${clock(d.resetAt - Date.now() / 1000)}</b></span>`
          : `<button class="btn btn-teal lg" data-a="dailyClaim" ${S.busy ? 'disabled' : ''}>${S.busy === 'daily' ? '<i class="fas fa-circle-notch spin"></i>' : '<i class="fas fa-hand-holding-dollar"></i>'}${esc(t('DAILY_CLAIM', num(d.amount), S.cfg.coinName))}</button>`}</div>
      </div></div>`;
}

function memberCards(list) {
  return `<div class="panel"><div class="panel-h"><h3><i class="fas fa-crown teal"></i> ${esc(t('MEMBER_TITLE'))}</h3></div>
    ${list && list.length ? `<div class="members">${list.map(m => `<div class="member ${m.active ? 'on' : ''}">
        <div class="thumb">${m.image ? `<img src="${esc(m.image)}" alt="">` : '<i class="fas fa-crown"></i>'}</div>
        <div class="member-b"><div class="member-h"><b>${esc(m.name)}</b>${m.active ? `<span class="chip teal"><i class="fas fa-circle-check"></i>${esc(t('MEMBER_ACTIVE'))}</span><span class="timer"><i class="fas fa-clock"></i><b data-until="${m.endsAt}">${clock(m.remaining)}</b></span>` : `<span class="chip">${esc(t('MEMBER_ENDED'))}</span>`}</div>
          ${m.perks && m.perks.length ? `<ul class="perks">${m.perks.map(p => `<li><i class="fas fa-check"></i>${esc(p)}</li>`).join('')}</ul>` : ''}</div>
        ${item(m.itemId) ? `<button class="btn ${m.active ? 'btn-ghost' : 'btn-teal'} sm" data-a="item" data-v="${esc(m.itemId)}">${esc(m.active ? t('MEMBER_RENEW') : t('MEMBER_BUY_AGAIN'))}</button>` : ''}</div>`).join('')}</div>`
      : `<div class="empty" style="padding:30px"><i class="fas fa-crown"></i><b>${esc(t('MEMBER_NONE'))}</b><span>${esc(t('MEMBER_NONE_SUB'))}</span></div>`}</div>`;
}

VIEWS.rewards = () => {
  const r = S.rewards;
  if (!r) return `<div class="empty" style="flex:1"><i class="fas fa-circle-notch fa-spin"></i></div>`;
  return `<div class="scroll" data-keep="rewards">
    <div class="head"><div class="head-txt"><h1>${esc(t('NAV_REWARDS'))}</h1><p>${esc(t('REWARDS_SUB'))}</p></div></div>
    <div class="rewards-grid">
      <div class="col">${rankCard(r.rank, r.ranks)}${memberCards(r.memberships)}</div>
      <div class="col">${dailyCard(r.daily)}
        ${r.playtime ? `<div class="callout" style="margin-top:0"><i class="fas fa-clock"></i><div><b>${esc(t('TUT_PLAYTIME'))}</b><span>${esc(t('TUT_PLAYTIME_TXT', r.playtime.coins, S.cfg.coinName, r.playtime.minutes))}</span></div></div>` : ''}
        ${S.cfg.coinPackages && S.cfg.coinPackages.length ? `<div class="callout" style="margin-top:0"><i class="fas fa-coins"></i><div><b>${esc(t('NAV_COINS'))}</b><span>${esc(t('COINS_SUB'))}</span></div><button class="btn btn-teal" data-a="go" data-v="coins">${esc(t('NAV_COINS'))}<i class="fas fa-arrow-right"></i></button></div>` : ''}
      </div>
    </div></div>`;
};

ACT.dailyClaim = async () => {
  const r = await call('daily:claim', {}, { busy: 'daily' });
  if (!r) { loadRewards(); return; }
  if (S.rewards) { S.rewards.daily = r.daily; r.daily.resetAt = Date.now() / 1000 + r.daily.resetIn; }
  S.me.daily = false;
  toast(t('DAILY_GOT', num(r.amount), S.cfg.coinName));
  setCoins(r.coins);
};

// ── showroom (3D vehicle preview) ────────────────────────────────────────
function previewView() {
  const p = S.preview;
  const it = item(p.id);
  if (!it) return '';
  const st = p.stats;
  const bar = (k, label, val) => `<div class="sr-stat"><div class="sr-stat-h"><span>${esc(t(label))}</span><b>${val || ''}</b></div><div class="sr-bar"><i style="width:${st ? Math.round(st.bars[k] * 100) : 0}%"></i></div></div>`;
  const colors = (S.cfg.showroom && S.cfg.showroom.colors) || [];
  return `<div class="sr">
    <div class="sr-drag" data-drag></div>
    <div class="sr-top"><button class="btn btn-ghost" data-a="srBack"><i class="fas fa-arrow-left"></i>${esc(t('SR_BACK'))}</button>
      <div class="sr-title"><span><i class="fas fa-car-side"></i>${esc(t('SR_PREVIEW'))}</span><b>${esc(it.name)}</b></div><div class="sp"></div>
      <span class="sr-hint"><i class="fas fa-computer-mouse"></i>${esc(t('SR_DRAG'))}</span></div>
    ${p.loading ? `<div class="sr-loading"><i class="fas fa-circle-notch fa-spin"></i>${esc(t('SR_LOADING'))}</div>` : `
    <div class="sr-panel sr-left"><h4>${esc(t('SR_STATS'))}</h4>
      ${bar('speed', 'SR_SPEED', st ? `${num(st.speed)} ${t('SR_KMH')}` : '')}${bar('accel', 'SR_ACCEL')}${bar('brake', 'SR_BRAKE')}${bar('grip', 'SR_GRIP')}
      ${st ? `<div class="sr-seats"><i class="fas fa-user-group"></i>${esc(t('SR_SEATS'))} <b>${num(st.seats)}</b></div>` : ''}
      <div class="sr-tools"><button class="${p.lights ? 'on' : ''}" data-a="srToggle" data-v="lights"><i class="fas fa-lightbulb"></i>${esc(t('SR_LIGHTS'))}</button>
        <button class="${p.doors ? 'on' : ''}" data-a="srToggle" data-v="doors"><i class="fas fa-door-open"></i>${esc(t('SR_DOORS'))}</button>
        <button data-a="srReset"><i class="fas fa-rotate"></i>${esc(t('SR_RESET'))}</button></div>
    </div>
    ${colors.length ? `<div class="sr-panel sr-paint"><span>${esc(t('SR_PAINT'))}</span><div class="swatches">${colors.map((c, i) => `<button class="${p.color === i + 1 ? 'on' : ''}" title="${esc(c[0])}" style="--sw:rgb(${+c[1]},${+c[2]},${+c[3]})" data-a="srColor" data-v="${i + 1}"></button>`).join('')}</div></div>` : ''}
    <div class="sr-panel sr-buy"><div class="total"><span>${esc(t('UI_TOTAL'))}</span><b>${coin()}${num(it.price)}${it.sale ? `<span class="strike">${num(it.basePrice)}</span>` : ''}</b></div>
      ${S.cfg.testDrive ? `<button class="btn btn-ghost lg" data-a="srDrive"><i class="fas fa-gauge-high"></i>${esc(t('UI_TEST_DRIVE'))}</button>` : ''}
      <button class="btn btn-teal lg" data-a="srBuy" ${soldOut(it) ? 'disabled' : ''}><i class="fas fa-bag-shopping"></i>${esc(t('UI_BUY'))}</button></div>`}
    <div class="sr-foot"><span class="key">ESC</span>${esc(t('SR_HINT_ESC'))}</div>
  </div>`;
}

ACT.srOpen = async v => {
  const it = item(v);
  if (!it || !it.spawnName) return;
  S.preview = { id: v, loading: true, color: 0 };
  render();
  const r = await post('showroom:open', { model: it.spawnName });
  if (!S.preview || S.preview.id !== v) return;
  if (!r || r.error) { toast(errText(r || { error: 'ERR_GENERIC' }), true); S.preview = null; render(); return; }
  S.preview.loading = false;
  S.preview.stats = r.data;
  render();
};
async function srClose() { if (!S.preview) return; S.preview = null; render(); await post('showroom:close'); }
ACT.srBack = () => srClose();
ACT.srBuy = async () => { const id = S.preview && S.preview.id; await srClose(); if (S.modal && S.modal.id === id) { S.modal.step = 'confirm'; render(); } };
ACT.srDrive = async () => { await srClose(); ACT.testDrive(); };
ACT.srColor = v => { S.preview.color = Number(v); render(); post('showroom:color', { index: Number(v) }); };
ACT.srToggle = async v => { const r = await post('showroom:toggle', { what: v }); if (S.preview && r && r.data) { S.preview.lights = r.data.lights; S.preview.doors = r.data.doors; render(); } };
ACT.srReset = () => post('showroom:reset');

// drag to rotate / wheel to zoom, sent at most ~30 times a second
let srDrag = null, srAcc = { dx: 0, dy: 0 }, srTimer = null;
function srFlush() {
  srTimer = null;
  if (srAcc.dx) { post('showroom:rotate', { dx: srAcc.dx }); srAcc.dx = 0; }
  if (srAcc.dy) { post('showroom:zoom', { dy: srAcc.dy }); srAcc.dy = 0; }
}
const srQueue = () => { if (!srTimer) srTimer = setTimeout(srFlush, 33); };
document.addEventListener('mousedown', e => { if (S.preview && e.target.closest && e.target.closest('[data-drag]')) { srDrag = e.clientX; document.body.classList.add('dragging'); } });
document.addEventListener('mousemove', e => { if (srDrag === null || !S.preview) return; srAcc.dx += e.clientX - srDrag; srDrag = e.clientX; srQueue(); });
document.addEventListener('mouseup', () => { srDrag = null; document.body.classList.remove('dragging'); });
document.addEventListener('wheel', e => { if (!S.preview || !(e.target.closest && e.target.closest('[data-drag]'))) return; srAcc.dy += e.deltaY; srQueue(); }, { passive: true });
