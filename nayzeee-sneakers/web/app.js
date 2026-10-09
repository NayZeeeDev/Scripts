const $ = id => document.getElementById(id);
const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'nayzeee-sneakers';
const post = (name, data = {}) =>
  fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) })
    .catch(() => {});

const img = name => name ? `../install/images/${name}.png` : '';   // the inventory icons ship once, in install/images
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

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
  const mi = $('menuImg');
  mi.hidden = !menu.image;
  if (menu.image) mi.querySelector('img').src = img(menu.image);

  $('menuList').innerHTML = '';
  options.forEach((o, i) => {
    const b = document.createElement('button');
    b.className = 'opt';
    b.disabled = !!o.disabled;
    const icon = o.image ? `<img src="${img(o.image)}" alt="">` : `<i class="${esc(o.icon || 'fa-solid fa-chevron-right')}"></i>`;
    b.innerHTML = `<span class="ic">${icon}</span><span class="tx"><span class="lb">${esc(o.label)}</span>` +
      (o.description ? `<span class="ds">${esc(o.description)}</span>` : '') + `</span>`;
    b.addEventListener('mouseenter', () => { sel = i; renderSel(); });
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
  $('insColour').textContent = d.colourway;
  $('insSize').textContent = 'US ' + d.size;
  $('insCond').textContent = d.condition;
  $('insSerial').textContent = d.serial || '—';
  const dirt = Math.max(0, Math.min(100, d.dirt || 0));
  $('insDirtTxt').textContent = dirt < 5 ? 'Clean' : dirt + '%';
  const bar = $('insDirt');
  bar.style.width = dirt + '%';
  bar.className = dirt >= 60 ? 'high' : dirt >= 25 ? 'mid' : '';
  $('inspectHint').textContent = hint || '';
}

/* ---------------- side panel: workbench + shop ---------------- */
let side = null;   // 'bench' | 'shop' | null
const money = n => '$' + Math.round(n).toLocaleString('en-US');
const fmtTime = ms => (ms / 1000).toFixed(1).replace(/\.0$/, '') + 's';

function openSide(kind, title, sub, icon) {
  side = kind;
  $('sideTitle').textContent = title;
  $('sideSub').textContent = sub;
  $('sideIcon').className = icon;
  $('bench').hidden = kind !== 'bench';
  $('shop').hidden = kind !== 'shop';
  $('side').hidden = false;
}
function closeSide() {
  if (!side) return;
  const kind = side;
  side = null;
  showGuide(false);
  $('side').hidden = true;
  post(kind === 'bench' ? 'benchClose' : 'shopClose');
}
$('sideClose').addEventListener('click', closeSide);

function setStatus(el, kind, text) {
  el.className = 'status' + (text ? ' show ' + kind : '');
  el.textContent = text || '';
}

/* guide drawer */
const GUIDES = {
  bench: { title: 'Shoe table', steps: [
    ['Get materials', ['Buy them from the <b>supplier</b> (the clipboard guy on your map).', 'Every pair uses up its materials when it\'s finished, not before.']],
    ['Pick a pair', ['Choose <b>Fake</b> or <b>Real</b> at the top. Real pairs need an <b>Authentic tag</b> and a higher level.', 'Pick a shoe, a colourway and a size.']],
    ['Make it', ['You work at the table in first person. The pair builds up in front of you, one stage at a time.', 'Some stages have a <b>skill check</b>. Clean work makes a fake more convincing; sloppy work shows.', 'Press <b>X</b> to stop. You keep your materials.']],
    ['Level up', ['Every pair gives XP. Higher levels unlock more shoes, real pairs, faster work and better fakes.']],
  ]},
  shop: { title: 'Supplies', steps: [
    ['Fill your cart', ['Use <b>+</b> and <b>−</b> on each material.', 'Some materials unlock at higher levels.']],
    ['Pay', ['<b>Buy</b> takes the total from your cash and puts everything in your pockets.']],
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
const B = { data: null, cat: null, mode: 'fake', model: null, colour: 0, size: null };

function setXP(d) {
  if (!d) return;
  $('xpLevel').textContent = d.level;
  const max = d.to == null;
  $('xpText').textContent = max ? `${d.xp} XP · max level` : `${d.xp - d.from} / ${d.to - d.from} XP`;
  $('xpBar').style.width = (max ? 100 : Math.min(100, (d.xp - d.from) / (d.to - d.from) * 100)) + '%';
  $('sideSub').textContent = side === 'bench' ? `Level ${d.level}` : $('sideSub').textContent;
}

function openBench(data, cat) {
  B.data = data; B.cat = cat; B.model = null;
  openSide('bench', 'Shoe table', '', 'fa-solid fa-scissors');
  setXP(data);
  setMode(data.level >= cat.realLevel ? B.mode : 'fake');
  $('search').value = '';
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
    b.className = 'opt model';
    const locked = lvl < m.level;
    b.innerHTML = `<span class="ic"><img src="${img(m.colours[0].image)}" alt=""></span>` +
      `<span class="tx"><span class="lb">${esc(m.label)}</span><span class="ds">${esc(m.boxLabel)} · ${m.colours.length} colourways</span></span>` +
      `<span class="lock${locked ? ' no' : ''}">${locked ? '<i class="fa-solid fa-lock"></i> ' : ''}Lv ${m.level}</span>`;
    b.addEventListener('click', () => pickModel(m));
    $('models').appendChild(b);
  });
}

function pickModel(m) {
  B.model = m; B.colour = 0;
  B.size = m.sizes[Math.floor((m.sizes.length - 1) / 2)];
  $('pickView').hidden = true;
  $('detailView').hidden = false;
  $('side').querySelector('#bench').scrollTop = 0;
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
    const d = document.createElement('div');
    d.className = 'sw' + (i === B.colour ? ' on' : '');
    d.title = col.name;
    d.innerHTML = `<img src="${img(col.image)}" alt="">`;
    d.addEventListener('click', () => { B.colour = i; renderDetail(); });
    $('swatches').appendChild(d);
  });

  $('sizes').innerHTML = '';
  m.sizes.forEach(sz => {
    const b = document.createElement('button');
    b.className = 'chip' + (sz === B.size ? ' on' : '');
    b.textContent = sz;
    b.addEventListener('click', () => { B.size = sz; renderDetail(); });
    $('sizes').appendChild(b);
  });

  const recipe = B.mode === 'real' ? m.real : m.fake;
  let missing = null;
  $('mats').innerHTML = recipe.map(r => {
    const have = B.data.have[r.name] || 0, ok = have >= r.count;
    if (!ok && !missing) missing = r.label;
    return `<div class="frow${ok ? ' ok' : ''}"><span class="mi"><img src="${img(r.name)}" alt=""></span>` +
      `<span class="nm">${esc(r.label)}</span><span class="ct">${have} / ${r.count}</span></div>`;
  }).join('');

  const speed = 1 - Math.min(0.4, (lvl - 1) * (B.speed || 0));
  const stages = B.stages[m.box] || [];
  $('stages').innerHTML = stages.map(st =>
    `<div><span>${esc(st.label)}</span>${st.check ? '<span class="ck"><i class="fa-solid fa-bullseye"></i> check</span>' : ''}</div>`).join('');
  $('stageTime').textContent = '~' + fmtTime(m.time * speed);

  let kind = 'ok', text = `Ready · ${stages.length} stages, about ${fmtTime(m.time * speed)}`;
  if (lvl < m.level) { kind = 'warn'; text = `${m.label} unlocks at level ${m.level}.`; }
  else if (B.mode === 'real' && lvl < B.cat.realLevel) { kind = 'warn'; text = `Real pairs unlock at level ${B.cat.realLevel}.`; }
  else if (missing) { kind = 'err'; text = `You're missing ${missing}. The supplier sells it.`; }
  setStatus($('benchStatus'), kind, text);
  $('craftBtn').disabled = kind !== 'ok';
}

$('craftBtn').addEventListener('click', () => {
  if (!B.model || $('craftBtn').disabled) return;
  const m = B.model;
  side = null;
  showGuide(false);
  $('side').hidden = true;
  post('craft', { model: m.id, letter: m.colours[B.colour].letter, size: B.size, real: B.mode === 'real' });
});

/* shop */
const SH = { shop: null, cart: {} };

function openShop(shop) {
  SH.shop = shop; SH.cart = {};
  openSide('shop', shop.title, '', 'fa-solid fa-box-open');
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
    row.className = 'frow' + (qty ? ' ok' : '');
    row.innerHTML = `<span class="mi"><img src="${img(it.name)}" alt=""></span>` +
      `<span class="nm">${esc(it.label)}<span class="pr">${money(it.price)} each</span></span>` +
      (locked ? `<span class="lock no"><i class="fa-solid fa-lock"></i> Lv ${it.level}</span>` :
        `<span class="stepper"><button data-d="-1"><i class="fa-solid fa-minus"></i></button><span>${qty}</span><button data-d="1"><i class="fa-solid fa-plus"></i></button></span>`);
    row.querySelectorAll('.stepper button').forEach(b => b.addEventListener('click', () => {
      const n = Math.max(0, Math.min(sh.max, qty + Number(b.dataset.d) * (window.event && window.event.shiftKey ? 5 : 1)));
      if (n) SH.cart[it.name] = n; else delete SH.cart[it.name];
      renderShop();
    }));
    $('shopList').appendChild(row);
  });
  $('shopTotal').textContent = money(total);
  const broke = total > sh.money;
  setStatus($('shopStatus'), broke ? 'err' : 'ok', total === 0 ? '' : broke ? `You have ${money(sh.money)}.` : '');
  $('buyBtn').disabled = total === 0 || broke;
}

$('buyBtn').addEventListener('click', async () => {
  if ($('buyBtn').disabled) return;
  $('buyBtn').disabled = true;
  let res = null;
  try {
    const r = await fetch(`https://${RES}/buy`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ cart: SH.cart }) });
    res = await r.json();
  } catch (e) { /* closed or browser preview */ }
  if (res && res.ok) {
    SH.cart = {};
    if (typeof res.money === 'number') SH.shop.money = res.money;
  }
  if (side === 'shop') renderShop();
});

/* ---------------- crafting stage bar ---------------- */
let pgTimer = null;
function showProgress(d) {
  cancelAnimationFrame(pgTimer);
  $('progress').hidden = !d;
  if (!d) return;
  $('pgLabel').textContent = d.label;
  $('pgStep').textContent = `${d.step} / ${d.steps}`;
  $('pgHint').textContent = d.hint || '';
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
  b.className = 'badge ' + (d.real ? 'real' : 'fake');
  b.textContent = d.real ? 'REAL' : 'FAKE';
  $('rsChecks').textContent = d.checks ? `${d.passed} / ${d.checks} clean` : '';
  $('rsQ').textContent = d.quality + '%';
  const bar = $('rsBar');
  bar.style.width = d.quality + '%';
  bar.className = d.quality >= 75 ? '' : d.quality >= 50 ? 'mid' : 'high';
  rsTimer = setTimeout(() => { el.classList.add('out'); setTimeout(() => { el.hidden = true; }, 300); }, 4500);
}

addEventListener('keydown', e => {
  if (!side) return;
  if (e.key === 'Escape') {
    e.preventDefault();
    if ($('guide').classList.contains('on')) showGuide(false); else closeSide();
  }
});

/* ---------------- toasts ---------------- */
const ICONS = { success: 'fa-solid fa-check', error: 'fa-solid fa-xmark', warning: 'fa-solid fa-triangle-exclamation', inform: 'fa-solid fa-circle-info' };
function toast(text, kind = 'inform') {
  const el = document.createElement('div');
  el.className = 'toast ' + kind;
  el.innerHTML = `<i class="${ICONS[kind] || ICONS.inform}"></i><span>${esc(text)}</span>`;
  $('toasts').appendChild(el);
  setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 260); }, 3800);
}

/* ---------------- messages ---------------- */
addEventListener('message', ({ data }) => {
  if (!data || !data.action) return;
  if (data.action === 'menu') showMenu(data.menu || {});
  else if (data.action === 'inspect') showInspect(data.show, data.data, data.hint);
  else if (data.action === 'toast') toast(data.text, data.kind);
  else if (data.action === 'bench') { B.stages = (data.catalogue && data.catalogue.stages) || {}; B.speed = data.speedPerLevel || 0; openBench(data.data, data.catalogue); }
  else if (data.action === 'xp') { if (B.data) Object.assign(B.data, data.data); if (side === 'bench') setXP(B.data); }
  else if (data.action === 'shop') openShop(data.shop);
  else if (data.action === 'progress') showProgress(data.data);
  else if (data.action === 'result') showResult(data.data);
  else if (data.action === 'hint') { $('hint').hidden = !data.text; $('hint').textContent = data.text || ''; }
});
