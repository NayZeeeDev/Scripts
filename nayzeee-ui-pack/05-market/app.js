/* 05 · MARKET
   SendNUIMessage({ action = 'open', data = {
     store = { name, location }, wallet = { cash, bank }, tax = 0.05,
     categories = { {id, label, icon} },
     items = { {id, name, desc, price, category, icon, stock, limit} } } })
   SendNUIMessage({ action = 'wallet', data = { cash, bank } })
   Callbacks: checkout {items = {{id, qty}}, method, total}  → return { ok = true } or { ok = false, error = '...' }
              close
*/
const app = NZ.$('#app');
let shop = null, cat = 'all', query = '', method = 'cash';
const cart = new Map(); // id -> qty

const item = id => shop.items.find(i => i.id === id);
const maxFor = it => Math.min(it.stock ?? Infinity, it.limit ?? Infinity);

function tabs() {
  const all = [{ id: 'all', label: 'All', icon: 'grid' }, ...(shop.categories || [])];
  NZ.$('#tabs').innerHTML = all.map(c => {
    const n = c.id === 'all' ? shop.items.length : shop.items.filter(i => i.category === c.id).length;
    return `<button class="tab ${c.id === cat ? 'on' : ''}" data-c="${NZ.esc(c.id)}">${NZ.icon(c.icon || 'tag')}${NZ.esc(c.label)}<span>${n}</span></button>`;
  }).join('');
  NZ.$$('.tab').forEach(t => t.onclick = () => { cat = t.dataset.c; tabs(); grid(); });
}

function grid() {
  const q = query.toLowerCase();
  const list = shop.items.filter(i => (cat === 'all' || i.category === cat) && (!q || i.name.toLowerCase().includes(q)));
  NZ.$('#grid').innerHTML = list.length ? list.map((it, k) => {
    const out = it.stock === 0;
    const tag = out ? '<span class="nz-tag hot">Sold out</span>' : it.stock != null && it.stock <= 5 ? `<span class="nz-tag warn">${it.stock} left</span>` : it.tag ? `<span class="nz-tag live">${NZ.esc(it.tag)}</span>` : '';
    return `<article class="card ${out ? 'out' : ''}" style="animation-delay:${k * 25}ms">
      <div class="vis">${tag}${NZ.icon(it.icon)}</div>
      <div class="info"><b>${NZ.esc(it.name)}</b><span>${NZ.esc(it.desc || '')}</span></div>
      <div class="buy"><span class="price">${NZ.money(it.price)}</span><button class="add" data-id="${NZ.esc(it.id)}" title="Add to basket">${NZ.icon('plus')}</button></div>
    </article>`;
  }).join('') : `<div class="nz-empty">${NZ.icon('search')}<b>Nothing matches “${NZ.esc(query)}”</b><span>Try another word or switch category.</span></div>`;
  NZ.$$('.add').forEach(b => b.onclick = () => add(b.dataset.id, 1));
}

function add(id, n) {
  const it = item(id);
  const q = Math.max(0, Math.min(maxFor(it), (cart.get(id) || 0) + n));
  q ? cart.set(id, q) : cart.delete(id);
  NZ.$('#msg').innerHTML = '';
  basket();
}

function totals() {
  const sub = [...cart].reduce((s, [id, q]) => s + item(id).price * q, 0);
  const tax = Math.round(sub * (shop.tax || 0));
  return { sub, tax, total: sub + tax };
}

function basket() {
  const lines = [...cart];
  const count = lines.reduce((s, [, q]) => s + q, 0);
  NZ.$('#c-count').textContent = `${count} item${count === 1 ? '' : 's'}`;
  NZ.$('#lines').innerHTML = lines.length ? lines.map(([id, q]) => {
    const it = item(id);
    return `<div class="line"><div class="nz-tile mute">${NZ.icon(it.icon)}</div>
      <div class="t"><b>${NZ.esc(it.name)}</b><span>${NZ.money(it.price * q)}</span></div>
      <div class="step"><button data-d="-1" data-id="${NZ.esc(id)}">${NZ.icon('minus')}</button><b>${q}</b><button data-d="1" data-id="${NZ.esc(id)}">${NZ.icon('plus')}</button></div></div>`;
  }).join('') : `<div class="nz-empty">${NZ.icon('bag')}<b>Your basket is empty</b><span>Tap the plus on any product to add it here.</span></div>`;
  NZ.$$('.step button').forEach(b => b.onclick = () => add(b.dataset.id, +b.dataset.d));

  const { sub, tax, total } = totals();
  NZ.$('#sub').textContent = NZ.money(sub);
  NZ.$('#tax').textContent = NZ.money(tax);
  NZ.$('#tax-pct').textContent = shop.tax ? `(${Math.round(shop.tax * 100)}%)` : '';
  NZ.$('#total').textContent = NZ.money(total);
  payment(total);
}

function payment(total = totals().total) {
  const w = shop.wallet || {};
  ['cash', 'bank'].forEach(m => {
    const b = NZ.$(`#pay [data-m="${m}"]`);
    b.classList.toggle('on', m === method);
    b.classList.toggle('short', (w[m] || 0) < total);
    NZ.$(`#p-${m}`).textContent = (w[m] || 0) < total ? `Short ${NZ.money(total - (w[m] || 0))}` : `${NZ.money(w[m] || 0)} available`;
  });
  NZ.$('#w-cash').textContent = NZ.money(w.cash || 0);
  NZ.$('#w-bank').textContent = NZ.money(w.bank || 0);
  const btn = NZ.$('#checkout');
  btn.disabled = !cart.size || (w[method] || 0) < total;
  btn.textContent = cart.size ? `Pay ${NZ.money(total)}` : 'Pay now';
}

async function checkout() {
  const { total } = totals();
  const items = [...cart].map(([id, qty]) => ({ id, qty }));
  const btn = NZ.$('#checkout');
  btn.disabled = true;
  const res = NZ.inGame ? await NZ.post('checkout', { items, method, total }) : { ok: true };
  if (res && res.ok) {
    shop.wallet[method] = (shop.wallet[method] || 0) - total;
    items.forEach(({ id, qty }) => { const it = item(id); if (it.stock != null) it.stock -= qty; });
    cart.clear();
    basket(); grid();
    NZ.$('#msg').innerHTML = `<div class="done">${NZ.icon('check')}Paid ${NZ.money(total)} — items added to your inventory</div>`;
  } else {
    payment();
    NZ.$('#msg').innerHTML = `<div class="done err">${NZ.icon('error')}${NZ.esc((res && res.error) || 'Payment failed')}</div>`;
  }
}

NZ.$$('#pay button').forEach(b => b.onclick = () => { method = b.dataset.m; payment(); });
NZ.$('#checkout').onclick = checkout;
NZ.$('#clear').onclick = () => { cart.clear(); basket(); };
NZ.$('#q').oninput = e => { query = e.target.value.trim(); grid(); };
NZ.$$('[data-close]').forEach(b => b.onclick = () => NZ.close(app));
window.addEventListener('keydown', e => {
  if (!app.classList.contains('nz-open')) return;
  if (e.key === 'Escape') NZ.close(app);
  else if (e.key === '/' && document.activeElement !== NZ.$('#q')) { e.preventDefault(); NZ.$('#q').focus(); }
});

function open(d) {
  shop = d; shop.wallet = shop.wallet || {}; cat = 'all'; query = ''; NZ.$('#q').value = ''; cart.clear();
  NZ.$('#store').textContent = d.store?.name || 'Store';
  NZ.$('#where').textContent = d.store?.location || '';
  NZ.$('#msg').innerHTML = '';
  tabs(); grid(); basket();
  NZ.open(app);
}
NZ.on('open', open);
NZ.on('wallet', w => { if (shop) { Object.assign(shop.wallet, w); payment(); } });
NZ.on('close', () => NZ.close(app, { notify: false }));

NZ.preview(() => {
  open({
    store: { name: '24/7 Supermarket', location: 'Innocence Blvd · Open 24h' },
    wallet: { cash: 4820, bank: 128450 }, tax: 0.05,
    categories: [
      { id: 'food', label: 'Food', icon: 'food' }, { id: 'drink', label: 'Drinks', icon: 'bottle' },
      { id: 'med', label: 'Medical', icon: 'medkit' }, { id: 'tools', label: 'Tools', icon: 'wrench' },
      { id: 'tech', label: 'Electronics', icon: 'phone' },
    ],
    items: [
      { id: 'burger', name: 'Bleeder Burger', desc: 'Restores 40 hunger. Grease included.', price: 12, category: 'food', icon: 'food', tag: 'Popular' },
      { id: 'sandwich', name: 'Egg-chan Sandwich', desc: 'Light snack, restores 20 hunger.', price: 6, category: 'food', icon: 'food' },
      { id: 'water', name: 'Raine Water', desc: 'Restores 35 thirst.', price: 3, category: 'drink', icon: 'drop' },
      { id: 'ecola', name: 'eCola', desc: 'Restores 25 thirst and a little stamina.', price: 4, category: 'drink', icon: 'bottle' },
      { id: 'bandage', name: 'Bandage', desc: 'Stops light bleeding, heals 15 HP.', price: 45, category: 'med', icon: 'bandage', stock: 4 },
      { id: 'painkillers', name: 'Painkillers', desc: 'Reduces stress for a few minutes.', price: 80, category: 'med', icon: 'pill' },
      { id: 'repair', name: 'Repair kit', desc: 'Fixes engine damage on the spot.', price: 350, category: 'tools', icon: 'wrench', limit: 2 },
      { id: 'lockpick', name: 'Lockpick', desc: 'For your own car. Obviously.', price: 120, category: 'tools', icon: 'key', stock: 0 },
      { id: 'phone', name: 'Phone', desc: 'Calls, texts and the banking app.', price: 650, category: 'tech', icon: 'phone' },
      { id: 'radio', name: 'Radio', desc: 'Encrypted channels 1–500.', price: 400, category: 'tech', icon: 'radio' },
    ],
  });
  add('burger', 2); add('water', 3); add('repair', 1);
});
