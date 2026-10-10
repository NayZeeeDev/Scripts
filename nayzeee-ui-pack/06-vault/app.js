/* 06 · VAULT
   SendNUIMessage({ action = 'open', data = {
     player = { label, sub, slots = 25, maxWeight = 30, items = { [slot] = item } },
     other  = { label, sub, icon, slots = 25, maxWeight = 20, items = {...} } } })   -- other is optional
   item = { name, label, count, weight (per unit, kg), icon, desc, stack = true, durability = 0-100, meta = {{'Serial','LS-123'}} }
   SendNUIMessage({ action = 'update', data = { player = {...}, other = {...} } })   -- replace one or both
   Callbacks: move {from, fromSlot, to, toSlot, amount}, use {slot, name}, give {slot, name, amount}, close
   Slots are 1-based. Hotbar = player slots 1-5.
*/
const app = NZ.$('#app');
const inv = { player: null, other: null };
let sel = null; // { inv, slot }

const panes = { player: NZ.$('[data-inv="player"]'), other: NZ.$('[data-inv="other"]') };
const weight = i => Object.values(i.items).reduce((s, it) => s + (it.weight || 0) * (it.count || 1), 0);
const amount = () => Math.max(0, Math.floor(+NZ.$('#amount').value || 0));

function renderInv(key) {
  const i = inv[key], pane = panes[key];
  pane.style.display = i ? '' : 'none';
  if (!i) return;
  pane.querySelector('[data-label]').textContent = i.label;
  pane.querySelector('[data-sub]').textContent = i.sub || '';
  if (i.icon) pane.querySelector('.nz-tile').innerHTML = NZ.icon(i.icon);
  const w = weight(i);
  pane.querySelector('[data-w]').textContent = w.toFixed(1);
  pane.querySelector('[data-max]').textContent = (+i.maxWeight).toFixed(1);
  const m = pane.querySelector('[data-meter]');
  m.querySelector('i').style.setProperty('--v', Math.min(100, (w / i.maxWeight) * 100) + '%');
  m.classList.toggle('red', w / i.maxWeight > .9);

  let html = '';
  for (let s = 1; s <= i.slots; s++) {
    const it = i.items[s];
    const hot = key === 'player' && s <= 5;
    const isSel = sel && sel.inv === key && sel.slot === s;
    html += `<div class="slot ${it ? 'has' : ''} ${hot ? 'hot' : ''} ${isSel ? 'sel' : ''}" data-inv="${key}" data-slot="${s}">`;
    if (hot) html += `<span class="key">${s}</span>`;
    if (it) {
      html += `<span class="ico">${NZ.icon(it.icon)}</span>`;
      if (it.count > 1) html += `<span class="cnt">×${it.count}</span>`;
      html += `<span class="wt">${((it.weight || 0) * (it.count || 1)).toFixed(1)}</span>`;
      html += `<span class="nm">${NZ.esc(it.label)}</span>`;
      if (it.durability != null) html += `<span class="dur ${it.durability < 25 ? 'low' : ''}"><i style="--v:${it.durability}%"></i></span>`;
    }
    html += '</div>';
  }
  pane.querySelector('[data-slots]').innerHTML = html;
}

function meta(it) {
  let rows = `<div class="kv"><span>Weight</span><b>${((it.weight || 0) * (it.count || 1)).toFixed(2)} kg</b></div>`;
  if (it.durability != null) rows += `<div class="kv"><span>Durability</span><b>${Math.round(it.durability)}%</b></div>`;
  (it.meta || []).forEach(([k, v]) => { rows += `<div class="kv"><span>${NZ.esc(k)}</span><b>${NZ.esc(v)}</b></div>`; });
  return rows;
}

function renderDetail() {
  const it = sel && inv[sel.inv]?.items[sel.slot];
  NZ.$('#detail').innerHTML = it
    ? `<div class="big">${NZ.icon(it.icon)}</div><b>${NZ.esc(it.label)}${it.count > 1 ? ` <span style="color:var(--ink-3);font-weight:400">×${it.count}</span>` : ''}</b>${it.desc ? `<p>${NZ.esc(it.desc)}</p>` : ''}${meta(it)}`
    : `<div class="none">Select an item to see its details</div>`;
  NZ.$('#use').disabled = !(it && sel.inv === 'player');
  NZ.$('#give').disabled = !(it && sel.inv === 'player');
}

const render = () => { renderInv('player'); renderInv('other'); renderDetail(); };

/* ── moving items ── */
function move(from, fs, to, ts, n) {
  if (from === to && fs === ts) return;
  const A = inv[from], B = inv[to];
  const a = A.items[fs]; if (!a) return;
  const b = B.items[ts];
  const qty = n > 0 && n < a.count ? n : a.count;
  if (from !== to && weight(B) + (a.weight || 0) * qty > B.maxWeight + 1e-9) return flashPane(to);

  if (!b) {
    B.items[ts] = { ...a, count: qty };
    if (qty === a.count) delete A.items[fs]; else a.count -= qty;
  } else if (b.name === a.name && a.stack !== false) {
    b.count += qty;
    if (qty === a.count) delete A.items[fs]; else a.count -= qty;
  } else if (qty === a.count) {
    if (from !== to && weight(A) - (a.weight || 0) * a.count + (b.weight || 0) * b.count > A.maxWeight + 1e-9) return flashPane(from);
    A.items[fs] = b; B.items[ts] = a;
  } else return;

  sel = { inv: to, slot: ts };
  NZ.post('move', { from, fromSlot: fs, to, toSlot: ts, amount: qty });
  render();
}
function firstFree(key, name) {
  const i = inv[key];
  for (let s = 1; s <= i.slots; s++) if (i.items[s] && i.items[s].name === name && i.items[s].stack !== false) return s;
  for (let s = 1; s <= i.slots; s++) if (!i.items[s]) return s;
  return null;
}
function flashPane(key) {
  const m = panes[key].querySelector('[data-meter]');
  m.classList.add('red');
  setTimeout(() => renderInv(key), 500);
}

/* ── pointer drag ── */
let drag = null;
const tip = document.createElement('div');
document.body.appendChild(tip);
tip.style.display = 'none';

app.addEventListener('pointerdown', e => {
  const el = e.target.closest('.slot.has');
  if (!el || e.button !== 0) return;
  drag = { inv: el.dataset.inv, slot: +el.dataset.slot, x: e.clientX, y: e.clientY, el, ghost: null };
});
window.addEventListener('pointermove', e => {
  if (drag) {
    if (!drag.ghost && Math.hypot(e.clientX - drag.x, e.clientY - drag.y) > 5) {
      const it = inv[drag.inv].items[drag.slot];
      const n = amount();
      drag.ghost = document.createElement('div');
      drag.ghost.className = 'ghost';
      drag.ghost.innerHTML = NZ.icon(it.icon) + (it.count > 1 ? `<span>×${n > 0 && n < it.count ? n : it.count}</span>` : '');
      document.body.appendChild(drag.ghost);
      drag.el.classList.add('drag');
      tip.style.display = 'none';
    }
    if (drag.ghost) {
      drag.ghost.style.left = e.clientX + 'px';
      drag.ghost.style.top = e.clientY + 'px';
      NZ.$$('.slot.over').forEach(s => s.classList.remove('over'));
      document.elementFromPoint(e.clientX, e.clientY)?.closest('.slot')?.classList.add('over');
      return;
    }
  }
  const el = e.target.closest?.('.slot.has');
  const it = el && inv[el.dataset.inv]?.items[+el.dataset.slot];
  if (!it) { tip.style.display = 'none'; return; }
  tip.className = 'tip';
  tip.innerHTML = `<b>${NZ.esc(it.label)}</b>${it.desc ? `<p>${NZ.esc(it.desc)}</p>` : ''}${meta(it)}`;
  tip.style.display = '';
  const x = Math.min(e.clientX + 16, innerWidth - 236), y = Math.min(e.clientY + 16, innerHeight - tip.offsetHeight - 10);
  tip.style.left = x + 'px'; tip.style.top = y + 'px';
});
window.addEventListener('pointerup', e => {
  if (!drag) return;
  const d = drag; drag = null;
  NZ.$$('.slot.over').forEach(s => s.classList.remove('over'));
  d.el.classList.remove('drag');
  if (d.ghost) {
    d.ghost.remove();
    const t = document.elementFromPoint(e.clientX, e.clientY)?.closest('.slot');
    if (t) move(d.inv, d.slot, t.dataset.inv, +t.dataset.slot, amount());
  } else {
    sel = { inv: d.inv, slot: d.slot };
    render();
  }
});
app.addEventListener('dblclick', e => {
  const el = e.target.closest('.slot.has');
  if (el && el.dataset.inv === 'player') use(+el.dataset.slot);
});
app.addEventListener('contextmenu', e => {
  e.preventDefault();
  const el = e.target.closest('.slot.has');
  if (!el || !inv.other) return;
  const from = el.dataset.inv, to = from === 'player' ? 'other' : 'player';
  const ts = firstFree(to, inv[from].items[+el.dataset.slot].name);
  if (ts) move(from, +el.dataset.slot, to, ts, amount());
});

function use(slot) {
  const it = inv.player.items[slot]; if (!it) return;
  NZ.post('use', { slot, name: it.name });
}
NZ.$('#use').onclick = () => sel && use(sel.slot);
NZ.$('#give').onclick = () => {
  const it = sel && inv.player.items[sel.slot]; if (!it) return;
  NZ.post('give', { slot: sel.slot, name: it.name, amount: amount() || it.count });
};
NZ.escape(() => { tip.style.display = 'none'; NZ.close(app); });

// hotbar: number keys use slots 1-5 while open
window.addEventListener('keydown', e => {
  if (!app.classList.contains('nz-open') || document.activeElement === NZ.$('#amount')) return;
  if (/^[1-5]$/.test(e.key)) use(+e.key);
});

// Lua can send items as a sparse table, an array, or a list with item.slot — accept all three.
function norm(i) {
  if (!i) return null;
  const out = {}, src = i.items || {};
  if (Array.isArray(src)) src.forEach((it, k) => { if (it) out[it.slot ?? k + 1] = it; });
  else Object.entries(src).forEach(([k, it]) => { if (it) out[it.slot ?? +k] = it; });
  i.items = out;
  return i;
}

function open(d) {
  inv.player = norm(d.player); inv.other = norm(d.other); sel = null;
  render();
  NZ.open(app);
}
NZ.on('open', open);
NZ.on('update', d => { if (d.player) inv.player = norm(d.player); if ('other' in d) inv.other = norm(d.other); render(); });
NZ.on('close', () => NZ.close(app, { notify: false }));

NZ.preview(() => open({
  player: { label: 'Pockets', sub: 'John Doe · ID 12', slots: 25, maxWeight: 30, items: {
    1: { name: 'phone', label: 'Phone', count: 1, weight: .2, icon: 'phone', desc: 'Your personal phone. Number 555-0142.', meta: [['Number', '555-0142']] },
    2: { name: 'pistol', label: 'Combat Pistol', count: 1, weight: 1.2, icon: 'pistol', desc: 'Registered sidearm.', durability: 78, stack: false, meta: [['Serial', 'LS-48213'], ['Ammo', '12 / 12']] },
    3: { name: 'bandage', label: 'Bandage', count: 6, weight: .05, icon: 'bandage', desc: 'Stops light bleeding and restores 15 health.' },
    4: { name: 'water', label: 'Water', count: 3, weight: .5, icon: 'drop', desc: 'Restores 35 thirst.' },
    5: { name: 'radio', label: 'Radio', count: 1, weight: .4, icon: 'radio', desc: 'Encrypted channels 1–500.' },
    7: { name: 'cash', label: 'Cash', count: 4820, weight: 0, icon: 'cash', desc: 'Clean, spendable money.' },
    8: { name: 'id', label: 'ID card', count: 1, weight: 0, icon: 'id', desc: 'State of San Andreas identification.', meta: [['Name', 'John Doe'], ['DOB', '04/12/1994']] },
    9: { name: 'keys', label: 'Car keys', count: 2, weight: .05, icon: 'key', desc: 'Pegassi Zentorno · NZ 4021' },
    12: { name: 'burger', label: 'Burger', count: 2, weight: .3, icon: 'food', desc: 'Restores 40 hunger.' },
    13: { name: 'repair', label: 'Repair kit', count: 1, weight: 2.5, icon: 'wrench', desc: 'Fixes engine damage.', durability: 18 },
    16: { name: 'gem', label: 'Diamond', count: 3, weight: .02, icon: 'gem', desc: 'Worth a lot to the right buyer.' },
  }},
  other: { label: 'Glovebox', sub: 'Pegassi Zentorno · NZ 4021', icon: 'car', slots: 15, maxWeight: 10, items: {
    1: { name: 'pill', label: 'Painkillers', count: 4, weight: .05, icon: 'pill', desc: 'Reduces stress for a few minutes.' },
    2: { name: 'receipt', label: 'Receipt', count: 1, weight: 0, icon: 'receipt', desc: 'Premium Deluxe Motorsport · $725,000' },
    6: { name: 'bottle', label: 'eCola', count: 2, weight: .4, icon: 'bottle', desc: 'Restores 25 thirst.' },
  }},
}));
