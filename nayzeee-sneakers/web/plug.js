/* Plug app: an lb-phone custom app (added by client/plug.lua with AddCustomApp). */
const $ = id => document.getElementById(id);
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const money = n => '$' + Math.round(n || 0).toLocaleString('en-US');
// once an icon has been found it's remembered, so redrawing never makes it search (and flicker) again
const ICON_AT = (() => { try { return JSON.parse(localStorage.getItem('nzs:icons') || '{}') || {}; } catch (e) { return {}; } })();
const img = name => name ? (ICON_AT[name] || `../install/images/${name}.png`) : '';
let PROPS_RES = 'nayzeee-sneakers-props';

// where an icon can be: this script, studio photos, the props resource, the inventory's own images, then a plain box
const iconName = src => {
  const m = src.match(/install\/images\/([^/?]+)\.png/) || src.match(/shots\/([^/?]+)\.png/) || src.match(/\/icons\/([^/?]+)\.png/) || src.match(/\/images\/([^/?]+)\.png/);
  return m ? m[1] : null;
};
// which places exist on this server (the game says at start); a missing resource can take seconds to answer
let ICON_SRC = { props: true, ox: true, qb: true };
let iconSave = 0;
const saveIcons = () => {
  clearTimeout(iconSave);
  iconSave = setTimeout(() => { try { localStorage.setItem('nzs:icons', JSON.stringify(ICON_AT)); } catch (e) { /* no storage: fine */ } }, 400);
};
const searching = {};
function iconPlaces(name) {
  const t = [`../install/images/${name}.png`, `../shots/${name}.png`];
  if (ICON_SRC.props) t.push(`https://cfx-nui-${PROPS_RES}/icons/${name}.png`);
  if (ICON_SRC.ox) t.push(`https://cfx-nui-ox_inventory/web/images/${name}.png`);
  if (ICON_SRC.qb) t.push(`https://cfx-nui-qb-inventory/html/images/${name}.png`);
  return t;
}
// asks every place at once and answers with the first one (in that order) that has the icon
function findIcon(name) {
  if (searching[name]) return searching[name];
  const tries = iconPlaces(name);
  return (searching[name] = new Promise(res => {
    const got = tries.map(() => null);
    const settle = () => {
      for (let i = 0; i < tries.length; i++) {
        if (got[i] === null) return;
        if (got[i]) return res(tries[i]);
      }
      res(name === 'nz_shoebox' ? null : '../install/images/nz_shoebox.png');
    };
    tries.forEach((u, i) => {
      const probe = new Image();
      probe.onload = () => { got[i] = true; settle(); };
      probe.onerror = () => { got[i] = false; settle(); };
      probe.src = u;
    });
    // a place that never answers doesn't hold the others up
    setTimeout(() => { got.forEach((g, i) => { if (g === null) got[i] = false; }); settle(); }, 2000);
  }));
}
addEventListener('error', e => {
  const el = e.target;
  if (!(el instanceof HTMLImageElement)) return;
  const failed = el.getAttribute('src') || '';
  const name = el.dataset.want || iconName(failed);
  if (!name) return;
  el.dataset.want = name;
  if (ICON_AT[name] === failed) { delete ICON_AT[name]; delete searching[name]; saveIcons(); }   // a remembered place stopped working
  findIcon(name).then(url => {
    if (!url || url === failed || el.dataset.want !== name) return;
    ICON_AT[name] = url;
    saveIcons();
    el.dataset.next = url;
    el.src = url;
  });
}, true);
// (image load events never reach window, so this listens on the document)
document.addEventListener('load', e => {
  const el = e.target;
  if (!(el instanceof HTMLImageElement)) return;
  const src = el.getAttribute('src') || '';
  if (src.startsWith('data:')) return;
  const name = el.dataset.want || iconName(src);
  if (name && ICON_AT[name] !== src) { ICON_AT[name] = src; saveIcons(); }
}, true);
// a new picture in the same <img> starts a fresh search
new MutationObserver(list => list.forEach(r => {
  const el = r.target;
  if (r.attributeName !== 'src' || !el.dataset || el.getAttribute('src') === el.dataset.next) return;
  delete el.dataset.want; delete el.dataset.next;
})).observe(document.documentElement, { subtree: true, attributes: true, attributeFilter: ['src'] });

// Windows redraw their lists on every click. A brand-new <img> is blank until it loads, which made every
// picture blink; so when a redraw puts back a picture that was just on screen, the old (already drawn)
// <img> is moved into its place instead.
const keepImages = new MutationObserver(list => {
  const gone = new Map(), added = [];
  const each = (n, fn) => { if (n.nodeType !== 1) return; if (n.tagName === 'IMG') fn(n); else n.querySelectorAll('img').forEach(fn); };
  for (const r of list) {
    r.removedNodes.forEach(n => each(n, i => {
      if (i.isConnected || !i.complete || !i.naturalWidth) return;
      const k = i.getAttribute('src');
      if (!gone.has(k)) gone.set(k, []);
      gone.get(k).push(i);
    }));
    r.addedNodes.forEach(n => each(n, i => added.push(i)));
  }
  if (!gone.size) return;
  added.forEach(i => {
    const old = i.isConnected && gone.get(i.getAttribute('src'));
    if (!old || !old.length) return;
    const o = old.pop();
    o.className = i.className;
    if (i.title) o.title = i.title;
    i.replaceWith(o);
  });
  keepImages.takeRecords();   // our own swaps aren't redraws
});
keepImages.observe(document.documentElement, { childList: true, subtree: true });

// lb-phone gives custom apps `resourceName`; fall back to the page's own host (https://cfx-nui-<resource>/...)
const RES = (() => {
  if (typeof window.resourceName === 'string' && window.resourceName) return window.resourceName;
  const h = location.hostname || '';
  if (h.startsWith('cfx-nui-')) return h.slice(8);
  return 'nayzeee-sneakers';
})();

async function call(name, data = {}) {
  try {
    const r = await fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
    return await r.json();
  } catch (e) { return null; }
}

/* ---------------- icons ---------------- */
const PATHS = {
  chat: '<path d="M4 5h16v11H9l-5 4z"/>',
  box: '<path d="M3.5 7.5 12 3.5l8.5 4v9L12 20.5l-8.5-4z"/><path d="M3.5 7.5 12 11.5l8.5-4M12 11.5v9"/>',
  flame: '<path d="M12 21c-4 0-7-2.8-7-6.6 0-3.1 2-5.2 3.6-7 .3 2 1.4 3.2 2.6 3.6C11 7.6 12.4 5 15 3c-.3 3 1 4.6 2.3 6.2 1.1 1.4 1.7 3 1.7 4.9C19 18.2 16 21 12 21z"/>',
  user: '<circle cx="12" cy="8" r="3.5"/><path d="M5 20a7 7 0 0 1 14 0"/>',
  pin: '<path d="M12 21s-6.5-6.2-6.5-11a6.5 6.5 0 0 1 13 0c0 4.8-6.5 11-6.5 11z"/><circle cx="12" cy="10" r="2.3"/>',
  x: '<path d="M6 6l12 12M18 6 6 18"/>',
  check: '<path d="M4 12.5 9 17.5 20 6.5"/>',
  search: '<circle cx="11" cy="11" r="6.5"/><path d="M20 20l-4.2-4.2"/>',
  car: '<path d="M3 13l2-5.5A2 2 0 0 1 6.9 6h10.2a2 2 0 0 1 1.9 1.5L21 13v5h-3M3 18v-5h18M6.5 18h11"/><circle cx="7" cy="18" r="1.6"/><circle cx="17" cy="18" r="1.6"/>',
  walk: '<circle cx="13" cy="4.5" r="1.8"/><path d="M10 21l2-6-2.5-2.5L11 8l3 3 3 1M9.5 12.5 7 15"/><path d="M14 15l2 6"/>',
  inbox: '<rect x="3.5" y="5" width="17" height="15" rx="2.5"/><path d="M3.5 13h5l1.5 2.5h4L15.5 13h5"/>',
  cash: '<rect x="2.5" y="6.5" width="19" height="11" rx="2"/><circle cx="12" cy="12" r="2.6"/><path d="M6 9.5v.01M18 14.5v.01"/>',
  bolt: '<path d="M13 3 5 13.5h6L10 21l8-10.5h-6z"/>',
  alert: '<path d="M12 9v5M12 17.5v.01"/><path d="M10.3 3.9 2.5 17.5A2 2 0 0 0 4.2 20.5h15.6a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/>',
  spark: '<path d="M12 3.5l2.4 5.2 5.6.7-4.1 3.9 1 5.6-4.9-2.7-4.9 2.7 1-5.6L4 9.4l5.6-.7z"/>',
  ticket: '<path d="M3.5 8.5V6.5a1 1 0 0 1 1-1h15a1 1 0 0 1 1 1v2a2.5 2.5 0 0 0 0 5v2a1 1 0 0 1-1 1h-15a1 1 0 0 1-1-1v-2a2.5 2.5 0 0 0 0-5z"/><path d="M14.5 5.5v13" stroke-dasharray="1.6 2"/>',
  clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
};
const icon = n => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">${PATHS[n] || ''}</svg>`;
document.querySelectorAll('[data-icon]').forEach(el => { el.innerHTML = icon(el.dataset.icon); });

/* ---------------- state ---------------- */
let D = null, tab = 'offers', offset = 0, busy = false;
const now = () => Math.floor(Date.now() / 1000) + offset;
const mmss = s => s <= 0 ? '0:00' : `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;
const initials = name => String(name || '?').split(' ').map(w => w[0]).join('').slice(0, 2).toUpperCase();

async function load() {
  const d = await call('plug:data');
  if (!d) return;
  D = d;
  if (d.props) PROPS_RES = d.props;
  if (d.sources) ICON_SRC = d.sources;
  offset = (d.now || 0) - Math.floor(Date.now() / 1000);
  if (d.deal) d.deal.endsAt = now() + d.deal.left;
  render();
}

function empty(ic, title, text) {
  return `<div class="empty">${icon(ic)}<b>${esc(title)}</b><span>${esc(text)}</span></div>`;
}

/* ---------------- header + deal ---------------- */
function renderHead() {
  const p = D.profile || {};
  $('pSub').textContent = `Level ${p.level || 1} · ${money(p.earned)} earned`;
  $('pRep').textContent = `Rep ${p.rep || 0}`;
  const n = (D.offers || []).length;
  $('pBadge').hidden = !n;
  $('pBadge').textContent = n;
  const dr = D.drop;
  $('pDropBadge').hidden = !(dr && (dr.phase === 'raffle' && !dr.entered || dr.won && !dr.claimed));

  const el = $('pDeal');
  const d = D.deal;
  el.hidden = !d;
  if (!d) return;
  const o = d.offer;
  el.innerHTML = `<div class="inc-top"><span class="chip">DEAL ON</span><span class="ref" id="dealLeft">${mmss(d.endsAt - now())}</span></div>
    <div class="who"><div class="av big"><img src="${img(o.image)}" alt=""></div>
      <div class="who-txt"><b>${esc(o.pair)}</b><span>${esc(o.buyer.name)} · ${esc(o.buyer.label)} · ${money(o.price)}</span></div></div>
    <div class="mini" style="margin-top:8px">${icon('pin')}<span><b>${esc(d.meet.label)}</b> · ${o.buyer.drive ? 'pulling up' : 'on foot'}</span></div>
    <div class="acts"><button class="btn-teal" id="dGps">${icon('pin')}Set GPS</button><button class="btn-red" id="dCancel">${icon('x')}Call it off</button></div>`;
  $('dGps').onclick = () => call('plug:gps');
  const cancel = async () => { if (busy) return; busy = true; await call('plug:cancel'); busy = false; load(); };
  $('dCancel').onclick = () => {
    // lb-phone's own confirm popup when it's there
    if (typeof window.setPopUp === 'function') {
      window.setPopUp({ title: 'Call it off?', description: `${o.buyer.name} won't be happy. You lose a little rep.`,
        buttons: [{ title: 'Keep the deal' }, { title: 'Call it off', color: 'red', cb: cancel }] });
    } else cancel();
  };
}

/* ---------------- tabs ---------------- */
function checkDots(c) {
  const n = c >= 0.9 ? 3 : c >= 0.5 ? 2 : 1;
  return `<span class="dots">${[1, 2, 3].map(i => `<i class="${i <= n ? 'on' : ''}"></i>`).join('')}</span>`;
}

function renderOffers() {
  const list = D.offers || [];
  let h = `<div class="ph-h"><h2>Offers</h2><span>${list.length ? list.length + ' waiting' : ''}</span></div>`;
  if (!list.length) return h + empty('inbox', 'No offers yet', 'Go to your Stash and hit "Find buyers" on a pair. Buyers DM you here.');
  for (const o of list) {
    const left = o.expires - now();
    h += `<div class="card" data-id="${o.id}">
      <div class="top"><div class="pav">${esc(initials(o.buyer.name))}</div>
        <div class="nm"><b>${esc(o.buyer.name)}</b><span>${esc(o.buyer.label)} · checks${checkDots(o.buyer.check)}</span></div>
        <span class="tag off">${icon(o.buyer.drive ? 'car' : 'walk')}${o.buyer.drive ? 'Drive-up' : 'Walk-up'}</span></div>
      <div class="bubble">I'll take the <b>${esc(o.pair)}</b> in US ${esc(o.size)}${o.boxed ? ' with the box' : ''}. <b>${money(o.price)}</b> cash.</div>
      <div class="pair"><div class="pim"><img src="${img(o.image)}" alt=""></div>
        <div class="pt"><b>${esc(o.pair)}</b><span>US ${esc(o.size)} · ${o.boxed ? 'Boxed' : 'No box'}</span></div>
        <div class="price">${money(o.price)}</div></div>
      <div class="acts"><button class="btn-teal" data-act="accept">${icon('check')}Accept</button>
        <button class="btn-line" data-act="decline">Pass</button><span class="exp${left < 60 ? ' low' : ''}" data-exp="${o.expires}">${mmss(left)}</span></div>
    </div>`;
  }
  return h;
}

function renderStash() {
  const list = D.stash || [];
  let h = `<div class="ph-h"><h2>Stash</h2><span>${list.length} pair${list.length === 1 ? '' : 's'}</span></div>`;
  if (!list.length) return h + empty('box', 'Nothing to sell', 'Pairs in your pockets show up here, loose or boxed. Make some at a shoe table.');
  for (const p of list) {
    const wait = p.wait > 0;
    h += `<div class="card" data-serial="${esc(p.serial)}">
      <div class="pair"><div class="pim"><img src="${img(p.image)}" alt=""></div>
        <div class="pt"><b>${esc(p.name)} '${esc(p.colourway)}'</b><span>US ${esc(p.size)} · ${esc(p.conditionLabel)}${p.dirt >= 5 ? ` · ${p.dirt}% dirty` : ''}</span></div></div>
      <div class="tags"><span class="tag ${p.boxed ? 'live' : 'off'}">${p.boxed ? 'Boxed' : 'No box'}</span>
        <span class="tag ${p.real ? 'live' : 'warn'}">${p.real ? 'Real' : `Fake · ${p.quality || 0}%`}</span></div>
      <div class="val"><span>Worth about</span><div class="price sm">${money(p.low)}<small class="to">to</small>${money(p.high)}</div></div>
      <button class="btn-teal" data-act="find" ${wait ? 'disabled' : ''} data-wait="${wait ? now() + p.wait : 0}">${icon('search')}${wait ? 'Posted · ' + mmss(p.wait) : 'Find buyers'}</button>
    </div>`;
  }
  return h;
}

function renderHype() {
  const list = D.hype || [];
  let h = `<div class="ph-h"><h2>Hype</h2><span>what's moving today</span></div>`;
  if (!list.length) return h + empty('flame', 'Hype is off', 'Every model sells at its normal price on this server.');
  const max = Math.max(...list.map(x => x.mult));
  list.forEach((x, i) => {
    const pct = Math.round((x.mult - 1) * 100);
    h += `<div class="hrow${i < (D.trending || 3) ? ' hot' : ''}"><div class="pim"><img src="${img(x.image)}" alt=""></div>
      <div class="pt"><b>${esc(x.label)}${i < (D.trending || 3) ? ' <span class="chip" style="margin-left:6px">HOT</span>' : ''}</b>
      <div class="meter"><i style="width:${Math.round(x.mult / max * 100)}%" class="${pct < 0 ? 'high' : ''}"></i></div></div>
      <div class="pct${pct < 0 ? ' down' : ''}">${pct >= 0 ? '+' : ''}${pct}%</div></div>`;
  });
  return h;
}

function renderDrops() {
  const d = D.drop;
  let h = `<div class="ph-h"><h2>Drops</h2><span>${d ? (d.phase === 'raffle' ? 'raffle open' : 'live now') : ''}</span></div>`;
  if (!d) return h + empty('ticket', 'Nothing dropping', 'Limited pairs drop every so often. You get a text the moment one does.');
  let status, acts = '';
  if (d.phase === 'raffle') {
    status = `<div class="mini">${icon('clock')}<span>Raffle closes in <b data-until="${d.closeAt}">${mmss(d.closeAt - now())}</b> · ${d.entries} entered</span></div>`;
    acts = d.entered
      ? `<button class="btn-line" disabled>${icon('check')}You're in. Good luck</button>`
      : `<button class="btn-teal" data-act="drop-enter">${icon('ticket')}Enter the raffle</button>`;
  } else if (d.won && !d.claimed) {
    status = `<div class="mini got">${icon('spark')}<span><b>You won!</b> Collect at ${esc(d.store)} within <b data-until="${d.claimUntil}">${mmss(d.claimUntil - now())}</b></span></div>`;
    acts = `<button class="btn-teal" data-act="drop-gps">${icon('pin')}Set GPS to the store</button>`;
  } else if (d.claimed) {
    status = `<div class="mini">${icon('check')}<span>You got yours. ${d.left} left for everyone else.</span></div>`;
  } else if (d.walkIn > 0) {
    status = `<div class="mini">${icon('bolt')}<span><b>${d.walkIn} pair${d.walkIn === 1 ? '' : 's'}</b> left, first come first served at ${esc(d.store)}</span></div>`;
    acts = `<button class="btn-teal" data-act="drop-gps">${icon('pin')}Set GPS to the store</button>`;
  } else {
    status = `<div class="mini">${icon('x')}<span>${d.entered ? 'No luck this time. ' : ''}Every pair is taken.</span></div>`;
  }
  return h + `<div class="card drop">
    <div class="drop-top"><span class="chip">LIMITED</span><span class="ref">${d.stock} pairs</span></div>
    <div class="drop-img"><img src="${img(d.image + '_box')}" alt=""></div>
    <div class="pt"><b>${esc(d.label)} '${esc(d.colourway)}'</b><span>Real · deadstock · ${esc(d.store)}</span></div>
    <div class="val"><span>Price</span><div class="price">${money(d.price)}</div></div>
    ${status}
    <div class="acts">${acts}</div>
  </div>
  <div class="note-s">Limited pairs sell for more. One per person; pay ${d.account === 'bank' ? 'by card' : 'cash'} when you collect.</div>`;
}

function renderMe() {
  const p = D.profile || {};
  const max = p.to == null;
  const xpPct = max ? 100 : Math.min(100, (p.xp - p.from) / (p.to - p.from) * 100);
  return `<div class="ph-h"><h2>Profile</h2><span>${esc(p.level ? 'Level ' + p.level : '')}</span></div>
    <div class="card lvl-card"><div class="row-l"><span>Level</span><b>${p.level || 1}</b></div>
      <div class="meter"><i style="width:${xpPct}%"></i></div>
      <div class="row-l" style="margin-top:6px;margin-bottom:0"><span>${max ? 'Max level' : `${p.xp - p.from} / ${p.to - p.from} XP`}</span><span>${p.xp || 0} XP</span></div></div>
    <div class="card lvl-card"><div class="row-l"><span>Reputation</span><b>${p.rep || 0} / ${p.repMax || 100}</b></div>
      <div class="meter"><i style="width:${(p.rep || 0) / (p.repMax || 100) * 100}%"></i></div>
      <div class="row-l" style="margin-top:6px;margin-bottom:0"><span>Better rep, better offers</span></div></div>
    <div class="pstats">
      <div class="stat"><div class="tile">${icon('cash')}</div><div class="stat-txt"><span>Earned</span><b>${money(p.earned)}</b></div></div>
      <div class="stat"><div class="tile">${icon('check')}</div><div class="stat-txt"><span>Pairs sold</span><b>${p.sold || 0}</b></div></div>
      <div class="stat"><div class="tile">${icon('bolt')}</div><div class="stat-txt"><span>Pairs made</span><b>${p.made || 0}</b></div></div>
      <div class="stat"><div class="tile red">${icon('alert')}</div><div class="stat-txt"><span>Fakes caught</span><b>${p.caught || 0}</b></div></div>
    </div>`;
}

const VIEWS = { offers: renderOffers, stash: renderStash, drops: renderDrops, hype: renderHype, me: renderMe };

function render() {
  if (!D) return;
  renderHead();
  [...$('pTabs').children].forEach(b => b.classList.toggle('on', b.dataset.tab === tab));
  $('pBody').innerHTML = VIEWS[tab]();
}

/* ---------------- actions ---------------- */
$('pTabs').addEventListener('click', e => {
  const b = e.target.closest('button');
  if (!b) return;
  tab = b.dataset.tab;
  render();
  $('pBody').scrollTop = 0;
});

$('pBody').addEventListener('click', async e => {
  const b = e.target.closest('button[data-act]');
  if (!b || b.disabled || busy) return;
  const card = b.closest('.card');
  busy = true;
  b.disabled = true;
  if (b.dataset.act === 'accept') await call('plug:accept', { id: Number(card.dataset.id) });
  else if (b.dataset.act === 'decline') await call('plug:decline', { id: Number(card.dataset.id) });
  else if (b.dataset.act === 'find') await call('plug:find', { serial: card.dataset.serial });
  else if (b.dataset.act === 'drop-enter') await call('plug:dropEnter');
  else if (b.dataset.act === 'drop-gps') await call('plug:dropGps');
  busy = false;
  load();
});


// timers tick locally between refreshes
setInterval(() => {
  if (!D) return;
  document.querySelectorAll('[data-exp]').forEach(el => {
    const left = Number(el.dataset.exp) - now();
    el.textContent = mmss(left);
    el.classList.toggle('low', left < 60);
    if (left <= 0) el.closest('.card')?.remove();
  });
  document.querySelectorAll('button[data-wait]').forEach(el => {
    const until = Number(el.dataset.wait);
    if (!until) return;
    const left = until - now();
    if (left <= 0) { el.disabled = false; el.dataset.wait = 0; el.innerHTML = icon('search') + 'Find buyers'; }
    else el.innerHTML = icon('search') + 'Posted · ' + mmss(left);
  });
  if (D.deal && $('dealLeft')) $('dealLeft').textContent = mmss(D.deal.endsAt - now());
  document.querySelectorAll('[data-until]').forEach(el => { el.textContent = mmss(Number(el.dataset.until) - now()); });
}, 1000);

addEventListener('message', ({ data }) => {
  if (data === 'componentsLoaded') return load();          // lb-phone finished setting the app up
  if (data && typeof data === 'object' && data.type === 'refresh') load();
});

load();
