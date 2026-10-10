/* 07 · SHOWROOM
   SendNUIMessage({ action = 'open', data = {
     dealer = { name, sub }, financeWeeks = 50,
     categories = { {id, label} },
     colors = { {id, label, hex} },
     vehicles = { {model, make, name, category, price, seats, trunk, top = 'mph', accel = '0-60 s',
                   stats = { speed, acceleration, braking, handling } } } } })   -- stats 0-10
   Callbacks: preview {model}, color {model, color}, rotate {delta}, testdrive {model}, purchase {model, color}, close
*/
const app = NZ.$('#app');
let data = null, cat = null, cur = null, color = null;

const STATS = [['speed', 'Top speed'], ['acceleration', 'Acceleration'], ['braking', 'Braking'], ['handling', 'Handling']];
const inCat = () => data.vehicles.filter(v => !cat || v.category === cat);

function chips() {
  NZ.$('#chips').innerHTML = data.categories.map(c =>
    `<button class="chip ${c.id === cat ? 'on' : ''}" data-c="${NZ.esc(c.id)}">${NZ.esc(c.label)}</button>`).join('');
  NZ.$$('.chip').forEach(b => b.onclick = () => { cat = b.dataset.c; chips(); list(); select(inCat()[0]); });
}

function list() {
  NZ.$('#list').innerHTML = inCat().map(v => `
    <button class="veh ${v === cur ? 'on' : ''}" data-m="${NZ.esc(v.model)}">
      <div><b>${NZ.esc(v.name)}</b><span>${NZ.esc(v.make)} · ${v.seats} seats</span></div>
      <em>${NZ.money(v.price)}</em>
    </button>`).join('');
  NZ.$$('.veh').forEach(b => b.onclick = () => select(data.vehicles.find(v => v.model === b.dataset.m)));
}

function select(v) {
  if (!v) return;
  const prev = cur;
  cur = v;
  NZ.$$('.veh').forEach(b => b.classList.toggle('on', b.dataset.m === v.model));
  NZ.$('#make').textContent = v.make;
  NZ.$('#name').textContent = v.name;
  const label = data.categories.find(c => c.id === v.category)?.label || v.category;
  NZ.$('#tags').innerHTML = `<span class="nz-chip">${NZ.esc(label)}</span>${v.tag ? `<span class="nz-chip white">${NZ.esc(v.tag)}</span>` : ''}`;
  NZ.$('#bars').innerHTML = STATS.map(([k, l]) => {
    const n = Math.round(v.stats[k]), was = prev ? Math.round(prev.stats[k]) : n;
    let segs = '';
    for (let i = 0; i < 10; i++) segs += `<i class="${i < n ? 'on' : i < was ? 'cmp' : ''}"></i>`;
    return `<div class="bar-ln"><div class="top"><span>${l}</span><b>${(v.stats[k]).toFixed(1)}</b></div><div class="segs">${segs}</div></div>`;
  }).join('');
  NZ.$('#facts').innerHTML = [['Top speed', `${v.top} mph`], ['0 – 60', `${v.accel} s`], ['Seats', v.seats], ['Trunk', `${v.trunk} kg`]]
    .map(([k, val]) => `<div><span>${k}</span><b>${NZ.esc(val)}</b></div>`).join('');
  NZ.$('#price').textContent = NZ.money(v.price);
  const weeks = data.financeWeeks || 0;
  NZ.$('#finance').textContent = weeks ? `or ${NZ.money(v.price / weeks)} / week · ${weeks} weeks` : '';
  NZ.post('preview', { model: v.model });
}

function swatches() {
  NZ.$('#swatches').innerHTML = data.colors.map(c =>
    `<button class="sw ${c.id === color ? 'on' : ''}" style="--c:${NZ.esc(c.hex)}" title="${NZ.esc(c.label)}" data-id="${NZ.esc(c.id)}"></button>`).join('');
  NZ.$('#paint-name').textContent = data.colors.find(c => c.id === color)?.label || '';
  NZ.$$('.sw').forEach(b => b.onclick = () => { color = b.dataset.id; swatches(); NZ.post('color', { model: cur.model, color }); });
}

NZ.$('#test').onclick = () => cur && NZ.post('testdrive', { model: cur.model });
NZ.$('#buy').onclick = () => cur && NZ.post('purchase', { model: cur.model, color });

/* rotation: drag the empty middle, or hold A / D */
let dragX = null;
NZ.$('#drag').addEventListener('pointerdown', e => { dragX = e.clientX; e.target.setPointerCapture(e.pointerId); });
NZ.$('#drag').addEventListener('pointermove', e => {
  if (dragX === null) return;
  NZ.post('rotate', { delta: e.clientX - dragX });
  dragX = e.clientX;
});
NZ.$('#drag').addEventListener('pointerup', () => { dragX = null; });
window.addEventListener('keydown', e => {
  if (!app.classList.contains('nz-open')) return;
  const k = e.key.toLowerCase();
  if (k === 'escape') NZ.close(app);
  else if (k === 'a' || k === 'arrowleft') NZ.post('rotate', { delta: -12 });
  else if (k === 'd' || k === 'arrowright') NZ.post('rotate', { delta: 12 });
  else if (k === 'arrowdown' || k === 'arrowup') {
    const l = inCat(), i = l.indexOf(cur);
    select(l[(i + (k === 'arrowdown' ? 1 : -1) + l.length) % l.length]);
    NZ.$('.veh.on')?.scrollIntoView({ block: 'nearest' });
  }
});

function open(d) {
  data = d;
  cat = d.categories[0]?.id || null;
  color = d.colors[0]?.id || null;
  cur = null;
  NZ.$('#dealer').textContent = d.dealer?.name || 'Dealership';
  NZ.$('#dealer-sub').textContent = d.dealer?.sub || '';
  chips(); list(); swatches(); select(inCat()[0]);
  NZ.open(app);
}
NZ.on('open', open);
NZ.on('close', () => NZ.close(app, { notify: false }));

NZ.preview(() => open({
  dealer: { name: 'Premium Deluxe Motorsport', sub: 'Downtown · Est. 1994' },
  financeWeeks: 50,
  categories: [{ id: 'super', label: 'Super' }, { id: 'sports', label: 'Sports' }, { id: 'muscle', label: 'Muscle' }, { id: 'suv', label: 'SUVs' }, { id: 'bikes', label: 'Bikes' }],
  colors: [
    { id: 'white', label: 'Ice White', hex: '#e9ecee' }, { id: 'black', label: 'Jet Black', hex: '#0d0f10' },
    { id: 'teal', label: 'NZ Teal', hex: '#08afa2' }, { id: 'red', label: 'Race Red', hex: '#e5484d' },
    { id: 'graphite', label: 'Graphite', hex: '#3a3f43' }, { id: 'amber', label: 'Amber', hex: '#e5a50a' },
    { id: 'blue', label: 'Midnight Blue', hex: '#1f3a68' },
  ],
  vehicles: [
    { model: 'zentorno', make: 'Pegassi', name: 'Zentorno', category: 'super', price: 725000, seats: 2, trunk: 20, top: 196, accel: 2.9, tag: 'Best seller', stats: { speed: 9.2, acceleration: 9.0, braking: 7.4, handling: 8.1 } },
    { model: 't20', make: 'Progen', name: 'T20', category: 'super', price: 2200000, seats: 2, trunk: 15, top: 205, accel: 2.6, stats: { speed: 9.6, acceleration: 9.5, braking: 8.0, handling: 8.6 } },
    { model: 'adder', make: 'Truffade', name: 'Adder', category: 'super', price: 1000000, seats: 2, trunk: 20, top: 210, accel: 3.1, stats: { speed: 9.8, acceleration: 8.2, braking: 6.9, handling: 7.0 } },
    { model: 'osiris', make: 'Pegassi', name: 'Osiris', category: 'super', price: 1950000, seats: 2, trunk: 15, top: 199, accel: 2.8, stats: { speed: 9.3, acceleration: 9.2, braking: 7.8, handling: 8.4 } },
    { model: 'sultanrs', make: 'Karin', name: 'Sultan RS', category: 'sports', price: 795000, seats: 4, trunk: 40, top: 168, accel: 3.6, stats: { speed: 7.8, acceleration: 8.2, braking: 7.0, handling: 8.8 } },
    { model: 'elegy', make: 'Annis', name: 'Elegy Retro', category: 'sports', price: 904000, seats: 2, trunk: 30, top: 172, accel: 3.5, stats: { speed: 8.0, acceleration: 8.0, braking: 7.2, handling: 8.6 } },
    { model: 'dominator', make: 'Vapid', name: 'Dominator', category: 'muscle', price: 35000, seats: 2, trunk: 35, top: 152, accel: 4.4, stats: { speed: 7.2, acceleration: 7.0, braking: 5.6, handling: 5.9 } },
    { model: 'baller', make: 'Gallivanter', name: 'Baller LE', category: 'suv', price: 149000, seats: 4, trunk: 80, top: 138, accel: 5.8, stats: { speed: 6.2, acceleration: 5.8, braking: 5.5, handling: 5.4 } },
    { model: 'bati', make: 'Pegassi', name: 'Bati 801', category: 'bikes', price: 15000, seats: 2, trunk: 0, top: 160, accel: 3.0, stats: { speed: 8.0, acceleration: 8.8, braking: 6.5, handling: 7.5 } },
  ],
}));
