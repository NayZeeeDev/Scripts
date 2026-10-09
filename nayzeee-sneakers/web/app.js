const $ = id => document.getElementById(id);
const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'nayzeee-sneakers';
const post = (name, data = {}) =>
  fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) })
    .catch(() => {});

const img = name => name ? `../install/images/${name}.png` : '';   // the inventory icons ship once, in install/images
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

/* ---------------- icons (inline SVG, 24px grid, stroked) ---------------- */
const PATHS = {
  check: '<path d="M4 12.5 9 17.5 20 6.5"/>',
  x: '<path d="M6 6l12 12M18 6 6 18"/>',
  alert: '<path d="M12 9v5M12 17.5v.01"/><path d="M10.3 3.9 2.5 17.5A2 2 0 0 0 4.2 20.5h15.6a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/>',
  info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8v.01"/>',
  search: '<circle cx="11" cy="11" r="6.5"/><path d="M20 20l-4.2-4.2"/>',
  shoe: '<path d="M3 17.5V12c0-.6.4-1 1-1h3.5l2-4 3.6 3.2 3.1 1.4c2.4.9 4.8 2.2 4.8 4.4v1.5z"/><path d="M3 15h18M12 9.8l-1.4 1.6M14.6 11.2l-1.3 1.6"/>',
  box: '<path d="M3.5 7.5 12 3.5l8.5 4v9L12 20.5l-8.5-4z"/><path d="M3.5 7.5 12 11.5l8.5-4M12 11.5v9"/>',
  chevron: '<path d="M9 6l6 6-6 6"/>',
  lock: '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
  level: '<path d="M4 20h4v-5h4v-5h4V5h4"/>',
  spark: '<path d="M12 3.5l2.4 5.2 5.6.7-4.1 3.9 1 5.6-4.9-2.7-4.9 2.7 1-5.6L4 9.4l5.6-.7z"/>',
  mask: '<path d="M4.5 5h15v6.5a7.5 7.5 0 0 1-15 0z"/><path d="M9 10h.01M15 10h.01M9.5 14.5c1.5 1 3.5 1 5 0"/>',
  badge: '<circle cx="12" cy="9" r="6"/><path d="M9 14.4 7.5 21l4.5-2.4 4.5 2.4-1.5-6.6"/><path d="M9.6 9l1.7 1.7 3.1-3.2"/>',
  back: '<path d="M19 12H5M11 6l-6 6 6 6"/>',
  scissors: '<circle cx="6" cy="7" r="2.8"/><circle cx="6" cy="17" r="2.8"/><path d="M8.3 8.6 20 19M8.3 15.4 20 5"/>',
  cart: '<path d="M3 4h2l2.4 11.2a1.5 1.5 0 0 0 1.5 1.2h8.6a1.5 1.5 0 0 0 1.5-1.1L21 8H6.2"/><circle cx="9.5" cy="20" r="1.2"/><circle cx="17" cy="20" r="1.2"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  minus: '<path d="M5 12h14"/>',
  target: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3.5"/>',
  hand: '<path d="M8 13V5.5a1.5 1.5 0 0 1 3 0V11M11 10.5V4.5a1.5 1.5 0 0 1 3 0V11M14 10.5V6a1.5 1.5 0 0 1 3 0v8a7 7 0 0 1-7 7h-.5a6 6 0 0 1-4.6-2.2L2.8 16a1.6 1.6 0 0 1 2.4-2.1L8 16.5"/>',
};
// Older menu callers pass Font Awesome class names
const ALIAS = { 'magnifying-glass': 'search', 'shoe-prints': 'shoe', 'box-open': 'box', 'hand-holding': 'hand', 'chevron-right': 'chevron' };
function icon(name) {
  let n = String(name || 'chevron').replace(/^fa-\w+\s+fa-/, '');
  n = ALIAS[n] || n;
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">${PATHS[n] || PATHS.chevron}</svg>`;
}
const fillIcons = root => root.querySelectorAll('[data-icon]').forEach(el => { el.innerHTML = icon(el.dataset.icon); });
fillIcons(document);

/* key names in hint text become key caps */
const KEYS = /\b(LMB|RMB|Scroll|Backspace|ESC|Enter|Q \/ E|Q|E|X|G)\b/g;
function keyHint(text) {
  return String(text || '').split(' · ').map(part =>
    `<span>${esc(part).replace(KEYS, k => k.split(' / ').map(x => `<span class="key">${x}</span>`).join(''))}</span>`).join('');
}

/* ---------------- menu ---------------- */
let options = [], sel = 0, open = false;

function renderSel() {
  [...$('menuList').children].forEach((el, i) => el.classList.toggle('sel', i === sel));
  $('menuList').children[sel]?.scrollIntoView({ block: 'nearest' });
}

function showMenu(menu) {
  options = menu.options || [];
  sel = Math.max(0, options.findIndex(o => !o.disabled));
  $('menuTitle').textContent = menu.title || '';
  $('menuSub').textContent = menu.subtitle || '';
  $('menuSub').hidden = !menu.subtitle;
  $('menuKicker').textContent = menu.image ? 'Your pair' : 'Pick one';
  const av = $('menuImg');
  av.innerHTML = menu.image ? `<img src="${img(menu.image)}" alt="">` : icon('shoe');

  $('menuList').innerHTML = '';
  options.forEach((o, i) => {
    const b = document.createElement('button');
    b.className = 'row';
    b.disabled = !!o.disabled;
    const ic = o.image ? `<span class="av img"><img src="${img(o.image)}" alt=""></span>` : `<span class="av">${icon(o.icon)}</span>`;
    b.innerHTML = `${ic}<span class="row-txt"><b>${esc(o.label)}</b>${o.description ? `<span>${esc(o.description)}</span>` : ''}</span>`;
    b.addEventListener('mouseenter', () => { if (!o.disabled) { sel = i; renderSel(); } });
    b.addEventListener('click', () => choose(i));
    $('menuList').appendChild(b);
  });
  $('menu').hidden = false;
  open = true;
  renderSel();
}

function hideMenu() { $('menu').hidden = true; open = false; }
function choose(i) {
  const o = options[i];
  if (!o || o.disabled) return;
  hideMenu();
  post('menuSelect', { id: o.id });
}
function closeMenu() { if (!open) return; hideMenu(); post('menuClose'); }

$('menuClose').addEventListener('click', closeMenu);
addEventListener('keydown', e => {
  if (!open) return;
  if (e.key === 'Escape' || e.key === 'Backspace') { e.preventDefault(); closeMenu(); }
  else if (e.key === 'ArrowDown') { e.preventDefault(); step(1); }
  else if (e.key === 'ArrowUp') { e.preventDefault(); step(-1); }
  else if (e.key === 'Enter') { e.preventDefault(); choose(sel); }
});
function step(d) {
  if (!options.length) return;
  for (let k = 0; k < options.length; k++) {
    sel = (sel + d + options.length) % options.length;
    if (!options[sel].disabled) break;
  }
  renderSel();
}

/* ---------------- inspect ---------------- */
function showInspect(show, d, hint) {
  $('inspect').hidden = !show;
  $('inspectHint').hidden = !show;
  if (!show || !d) return;
  $('insImg').src = img(d.image);
  $('insName').textContent = d.name;
  $('insColour').textContent = String(d.colourway || '').toUpperCase();
  $('insCond').textContent = d.condition;
  $('insSize').textContent = 'US ' + d.size;
  $('insSerial').textContent = d.serial || '—';
  const dirt = Math.max(0, Math.min(100, d.dirt || 0));
  $('insDirtTxt').textContent = dirt < 5 ? 'Clean' : dirt + '%';
  const bar = $('insDirt');
  bar.style.width = Math.max(dirt, 2) + '%';
  bar.className = dirt >= 60 ? 'high' : dirt >= 25 ? 'mid' : '';
  $('inspectHint').innerHTML = keyHint(hint);
}

/* ---------------- side window: workbench + shop ---------------- */
let side = null;   // 'bench' | 'shop' | null
const money = n => '$' + Math.round(n).toLocaleString('en-US');
const fmtTime = ms => (ms / 1000).toFixed(1).replace(/\.0$/, '') + 's';

function openSide(kind, title, sub) {
  side = kind;
  $('sideTitle').textContent = title.toUpperCase();
  $('sideSub').textContent = sub;
  $('bench').hidden = kind !== 'bench';
  $('shop').hidden = kind !== 'shop';
  $('side').hidden = false;
  document.body.classList.add('side-open');
}
function closeSide() {
  if (!side) return;
  const kind = side;
  side = null;
  showGuide(false);
  $('side').hidden = true;
  document.body.classList.remove('side-open');
  post(kind === 'bench' ? 'benchClose' : 'shopClose');
}
$('sideClose').addEventListener('click', closeSide);

function setNote(el, kind, html) {
  el.className = 'note' + (html ? ' show ' + kind : '');
  el.innerHTML = html || '';
}

/* guide drawer */
const GUIDES = {
  bench: { title: 'SHOE TABLE', steps: [
    ['Get materials', ['Buy them from the <b>supplier</b> (Shoe supplies on your map).', 'Materials are only used up when a pair is finished.']],
    ['Pick a pair', ['Choose <b>Fake</b> or <b>Real</b> at the top. Real pairs need an <b>Authentic tag</b> and a higher level.', 'Pick a shoe, a colourway and a size.']],
    ['Make it', ['You work at the table in first person. The pair builds up in front of you, one stage at a time.', 'Some stages have a <b>skill check</b>. Clean work makes a fake more convincing; sloppy work shows.', 'Press <b>X</b> to stop. You keep your materials.']],
    ['Level up', ['Every pair gives XP. Higher levels unlock more shoes, real pairs, faster work and better fakes.']],
  ]},
  shop: { title: 'SUPPLIES', steps: [
    ['Fill your cart', ['Use <b>+</b> and <b>−</b> on each material. Shift-click adds or removes five.', 'Some materials unlock at higher levels.']],
    ['Pay', ['<b>Buy</b> takes the total and puts everything in your pockets.']],
  ]},
};
function showGuide(on) {
  $('guide').classList.toggle('on', on);
  $('scrim').classList.toggle('on', on);
  if (!on || !side) return;
  const g = GUIDES[side];
  $('guideTitle').textContent = g.title;
  $('guideBody').innerHTML = g.steps.map(([h, items], i) =>
    `<div class="gstep"><h3><span class="n">${i + 1}</span>${esc(h)}</h3><ul>${items.map(t => `<li>${t}</li>`).join('')}</ul></div>`).join('');
}
$('guideBtn').addEventListener('click', () => showGuide(true));
$('guideClose').addEventListener('click', () => showGuide(false));
$('scrim').addEventListener('click', () => showGuide(false));

/* workbench */
const B = { data: null, cat: null, stages: {}, speed: 0, mode: 'fake', model: null, colour: 0, size: null };

function setXP(d) {
  if (!d) return;
  $('xpLevel').textContent = d.level;
  const max = d.to == null;
  $('xpLabel').textContent = max ? 'Max level' : 'Next level';
  $('xpText').textContent = max ? `${d.xp} XP` : `${d.xp - d.from} / ${d.to - d.from}`;
  $('xpBar').style.width = (max ? 100 : Math.min(100, (d.xp - d.from) / (d.to - d.from) * 100)) + '%';
  if (side === 'bench') $('sideSub').textContent = `Level ${d.level} · ${d.xp} XP`;
}

function openBench(data, cat) {
  B.data = data; B.cat = cat; B.model = null;
  openSide('bench', 'Shoe table', '');
  setXP(data);
  setMode(data.level >= cat.realLevel ? B.mode : 'fake');
  $('search').value = '';
  const colours = cat.models.reduce((n, m) => n + m.colours.length, 0);
  $('pickSub').textContent = `${cat.models.length} models · ${colours} colourways`;
  showList();
}

function setMode(m) {
  B.mode = m;
  [...$('mode').children].forEach(b => b.classList.toggle('on', b.dataset.v === m));
  if (B.model) renderDetail();
}
$('mode').addEventListener('click', e => {
  const b = e.target.closest('button');
  if (b) setMode(b.dataset.v);
});

function showList() {
  B.model = null;
  $('pickView').hidden = false;
  $('detailView').hidden = true;
  renderList();
}
$('back').addEventListener('click', showList);
$('search').addEventListener('input', renderList);

function renderList() {
  const q = $('search').value.trim().toLowerCase();
  const lvl = B.data.level;
  $('models').innerHTML = '';
  B.cat.models.filter(m => !q || m.label.toLowerCase().includes(q)).forEach(m => {
    const b = document.createElement('button');
    b.className = 'row';
    const locked = lvl < m.level;
    b.innerHTML = `<span class="av img"><img src="${img(m.colours[0].image)}" alt=""></span>` +
      `<span class="row-txt"><b>${esc(m.label)}</b><span>${esc(m.boxLabel)} · ${m.colours.length} colourways</span></span>` +
      (locked ? `<span class="tag warn">${icon('lock')}Lv ${m.level}</span>` : `<span class="tag off">Lv ${m.level}</span>`);
    b.addEventListener('click', () => pickModel(m));
    $('models').appendChild(b);
  });
  if (!$('models').children.length) $('models').innerHTML = `<div class="note show">Nothing matches <b>${esc(q)}</b>.</div>`;
}

function pickModel(m) {
  B.model = m; B.colour = 0;
  B.size = m.sizes[Math.floor((m.sizes.length - 1) / 2)];
  $('pickView').hidden = true;
  $('detailView').hidden = false;
  $('bench').scrollTop = 0;
  renderDetail();
}

function renderDetail() {
  const m = B.model, c = m.colours[B.colour], lvl = B.data.level;
  $('pvImg').src = img(c.image);
  $('pvName').textContent = m.label;
  $('pvColour').textContent = c.name;
  $('pvLevel').textContent = 'Lv ' + m.level;

  $('swatches').innerHTML = '';
  m.colours.forEach((col, i) => {
    const d = document.createElement('button');
    d.className = 'sw' + (i === B.colour ? ' on' : '');
    d.title = col.name;
    d.innerHTML = `<img src="${img(col.image)}" alt="">`;
    d.addEventListener('click', () => { B.colour = i; renderDetail(); });
    $('swatches').appendChild(d);
  });

  $('sizes').innerHTML = '';
  m.sizes.forEach(sz => {
    const b = document.createElement('button');
    b.className = sz === B.size ? 'on' : '';
    b.textContent = sz;
    b.addEventListener('click', () => { B.size = sz; renderDetail(); });
    $('sizes').appendChild(b);
  });

  const recipe = B.mode === 'real' ? m.real : m.fake;
  let missing = null;
  $('mats').innerHTML = recipe.map(r => {
    const have = B.data.have[r.name] || 0, ok = have >= r.count;
    if (!ok && !missing) missing = r.label;
    return `<div class="row"><span class="av img"><img src="${img(r.name)}" alt=""></span>` +
      `<span class="row-txt"><b>${esc(r.label)}</b><span>Needs ${r.count}</span></span>` +
      `<span class="need${ok ? ' ok' : ''}">${have} / ${r.count}</span></div>`;
  }).join('');

  const speed = 1 - Math.min(0.4, (lvl - 1) * B.speed);
  const stages = B.stages[m.box] || [];
  $('stages').innerHTML = stages.map(st =>
    `<div><span>${esc(st.label)}</span>${st.check ? `<span class="chip amber">CHECK</span>` : ''}</div>`).join('');
  $('stageTime').textContent = `${stages.length} stages · about ${fmtTime(m.time * speed)}`;

  let kind = 'ok', text = `<b>Ready.</b> ${B.mode === 'real' ? 'A real pair' : 'A fake pair'}, US ${esc(B.size)}.`;
  if (lvl < m.level) { kind = 'warn'; text = `<b>${esc(m.label)}</b> unlocks at level ${m.level}.`; }
  else if (B.mode === 'real' && lvl < B.cat.realLevel) { kind = 'warn'; text = `Real pairs unlock at <b>level ${B.cat.realLevel}</b>.`; }
  else if (missing) { kind = 'err'; text = `You're missing <b>${esc(missing)}</b>. The supplier sells it.`; }
  setNote($('benchStatus'), kind, text);
  $('craftBtn').disabled = kind !== 'ok';
}

$('craftBtn').addEventListener('click', () => {
  if (!B.model || $('craftBtn').disabled) return;
  const m = B.model;
  side = null;
  showGuide(false);
  $('side').hidden = true;
  document.body.classList.remove('side-open');
  post('craft', { model: m.id, letter: m.colours[B.colour].letter, size: B.size, real: B.mode === 'real' });
});

/* shop */
const SH = { shop: null, cart: {} };

function openShop(shop) {
  SH.shop = shop; SH.cart = {};
  openSide('shop', shop.title, '');
  renderShop();
}

function renderShop() {
  const sh = SH.shop;
  $('sideSub').textContent = `${sh.account === 'bank' ? 'Bank' : 'Cash'} ${money(sh.money)} · Level ${sh.level}`;
  $('shopList').innerHTML = '';
  let total = 0;
  sh.items.forEach(it => {
    const qty = SH.cart[it.name] || 0;
    total += qty * it.price;
    const locked = sh.level < it.level;
    const row = document.createElement('div');
    row.className = 'row' + (qty ? ' sel' : '');
    row.innerHTML = `<span class="av img"><img src="${img(it.name)}" alt=""></span>` +
      `<span class="row-txt"><b>${esc(it.label)}</b><span><span class="price">${money(it.price)}</span> each</span></span>` +
      (locked ? `<span class="tag warn">${icon('lock')}Lv ${it.level}</span>` :
        `<span class="stepper"><button data-d="-1">${icon('minus')}</button><span>${qty}</span><button data-d="1">${icon('plus')}</button></span>`);
    row.querySelectorAll('.stepper button').forEach(b => b.addEventListener('click', e => {
      const n = Math.max(0, Math.min(sh.max, qty + Number(b.dataset.d) * (e.shiftKey ? 5 : 1)));
      if (n) SH.cart[it.name] = n; else delete SH.cart[it.name];
      renderShop();
    }));
    $('shopList').appendChild(row);
  });
  $('shopTotal').textContent = money(total);
  const broke = total > sh.money;
  setNote($('shopStatus'), 'err', broke ? `That's more than you have (<b>${money(sh.money)}</b>).` : '');
  $('buyBtn').disabled = total === 0 || broke;
}

$('buyBtn').addEventListener('click', async () => {
  if ($('buyBtn').disabled) return;
  $('buyBtn').disabled = true;
  let res = null;
  try {
    const r = await fetch(`https://${RES}/buy`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ cart: SH.cart }) });
    res = await r.json();
  } catch (e) { /* closed, or a browser preview */ }
  if (res && res.ok) {
    SH.cart = {};
    if (typeof res.money === 'number') SH.shop.money = res.money;
  }
  if (side === 'shop') renderShop();
});

addEventListener('keydown', e => {
  if (!side || e.target.tagName === 'INPUT') {
    if (side && e.key === 'Escape') e.target.blur();
    return;
  }
  if (e.key === 'Escape') {
    e.preventDefault();
    if ($('guide').classList.contains('on')) showGuide(false); else closeSide();
  } else if (e.key === 'g' || e.key === 'G') {
    showGuide(!$('guide').classList.contains('on'));
  }
});

/* ---------------- crafting stage ---------------- */
let pgTimer = null;
function showProgress(d) {
  cancelAnimationFrame(pgTimer);
  $('progress').hidden = !d;
  if (!d) return;
  $('pgLabel').textContent = d.label;
  $('pgStep').textContent = `STAGE ${d.step} / ${d.steps}`;
  $('pgHint').innerHTML = keyHint(d.hint);
  const start = performance.now(), bar = $('pgBar');
  const tick = now => {
    bar.style.width = Math.min(100, (now - start) / d.time * 100) + '%';
    if (now - start < d.time) pgTimer = requestAnimationFrame(tick);
  };
  bar.style.width = '0%';
  pgTimer = requestAnimationFrame(tick);
}

/* ---------------- finished pair ---------------- */
let rsTimer = null;
function showResult(d) {
  clearTimeout(rsTimer);
  const el = $('result');
  el.classList.remove('out');
  el.hidden = false;
  $('rsImg').src = img(d.image);
  $('rsName').textContent = d.name;
  const b = $('rsBadge');
  b.className = 'chip' + (d.real ? '' : ' amber');
  b.textContent = d.real ? 'REAL' : 'FAKE';
  $('rsChecks').textContent = d.checks ? `${d.passed} / ${d.checks} CLEAN` : '';
  $('rsQ').textContent = d.quality + '%';
  const bar = $('rsBar');
  bar.style.width = d.quality + '%';
  bar.className = d.quality >= 75 ? '' : d.quality >= 50 ? 'mid' : 'high';
  rsTimer = setTimeout(() => { el.classList.add('out'); setTimeout(() => { el.hidden = true; }, 300); }, 4500);
}

/* ---------------- toasts ---------------- */
const TOAST_ICON = { success: 'check', error: 'x', warning: 'alert', inform: 'info' };
function toast(text, kind = 'inform') {
  const el = document.createElement('div');
  el.className = 'toast ' + kind;
  el.innerHTML = `<div class="ti">${icon(TOAST_ICON[kind] || 'info')}</div><div><b>${esc(text)}</b></div>`;
  $('toasts').appendChild(el);
  setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 260); }, 3800);
}

/* ---------------- messages ---------------- */
addEventListener('message', ({ data }) => {
  if (!data || !data.action) return;
  switch (data.action) {
    case 'menu': showMenu(data.menu || {}); break;
    case 'inspect': showInspect(data.show, data.data, data.hint); break;
    case 'toast': toast(data.text, data.kind); break;
    case 'bench':
      B.stages = (data.catalogue && data.catalogue.stages) || {};
      B.speed = data.speedPerLevel || 0;
      openBench(data.data, data.catalogue);
      break;
    case 'xp':
      if (B.data) { Object.assign(B.data, data.data); if (side === 'bench') setXP(B.data); }
      break;
    case 'shop': openShop(data.shop); break;
    case 'progress': showProgress(data.data); break;
    case 'result': showResult(data.data); break;
    case 'hint':
      $('hint').hidden = !data.text;
      $('hint').innerHTML = keyHint(data.text);
      break;
  }
});
