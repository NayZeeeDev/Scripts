/* 02 · RAIL
   SendNUIMessage({ action = 'open', data = { title, subtitle, items = { ... } } })
   item = { id, label, desc, icon, price, count, danger, locked,
            toggle = true|false,            -- switch
            options = {'A','B'}, index = 1,  -- ‹ value ›  (index is 1-based, Lua style)
            items = { ... },                 -- submenu
            plate, stats = {{label, value}}, info }  -- detail panel
   Callbacks: select {id, path}, toggle {id, value}, change {id, value, index}, close
*/
const app = NZ.$('#app');
let root = null;
let stack = [];   // [{ menu, sel }]

const cur = () => stack[stack.length - 1];

function endFor(it) {
  if (typeof it.toggle === 'boolean') return `<span class="nz-sw ${it.toggle ? 'on' : ''}"><i></i></span>`;
  if (it.options) return `<span class="pick">${NZ.icon('chev-l')}${NZ.esc(it.options[it.index - 1])}${NZ.icon('chev-r')}</span>`;
  let out = '';
  if (it.count != null) out += `<span class="cnt">${NZ.esc(it.count)}</span>`;
  if (it.price != null) out += `<span class="price">${NZ.money(it.price)}</span>`;
  if (it.locked) out += NZ.icon('lock');
  else if (it.items) out += NZ.icon('chev-r');
  return out;
}

function render() {
  const { menu, sel } = cur();
  NZ.$('#title').textContent = root.title || 'Menu';
  NZ.$('#subtitle').textContent = root.subtitle || '';
  NZ.$('#count').innerHTML = `<b>${sel + 1}</b> / ${menu.items.length}`;

  const crumb = NZ.$('#crumb');
  if (stack.length > 1) {
    crumb.innerHTML = `<button data-back>${NZ.icon('chev-l')}Back</button>` +
      stack.map((s, i) => i === stack.length - 1 ? `<b>${NZ.esc(s.menu.label || root.title)}</b>` : NZ.esc(s.menu.label || root.title) + NZ.icon('chev-r')).join('');
    crumb.querySelector('[data-back]').onclick = back;
  } else {
    crumb.innerHTML = `${NZ.icon('filter')}${NZ.esc(root.hint || 'Choose an option')}`;
  }

  NZ.$('#list').innerHTML = menu.items.map((it, i) => `
    <button class="it ${i === sel ? 'on' : ''} ${it.danger ? 'danger' : ''} ${it.locked ? 'locked' : ''}" data-i="${i}">
      <span class="ico">${NZ.icon(it.icon || 'chev-r')}</span>
      <span class="lbl"><b>${NZ.esc(it.label)}</b>${it.desc ? `<span>${NZ.esc(it.desc)}</span>` : ''}</span>
      <span class="end">${endFor(it)}</span>
    </button>`).join('');
  NZ.$$('#list .it').forEach(el => {
    el.onmouseenter = () => { if (cur().sel !== +el.dataset.i) { cur().sel = +el.dataset.i; render(); } };
    el.onclick = () => activate();
  });
  NZ.$('#list .it.on')?.scrollIntoView({ block: 'nearest' });

  const it = menu.items[sel];
  let d = '';
  if (it && (it.plate || it.stats || it.info)) {
    if (it.plate) d += `<span class="plate">Plate <b>${NZ.esc(it.plate)}</b></span>`;
    if (it.info) d += `<p>${NZ.esc(it.info)}</p>`;
    if (it.stats) d += it.stats.map(s => {
      const tone = s.value < 25 ? 'red' : s.value < 50 ? 'amber' : '';
      return `<div class="stat-ln"><span>${NZ.esc(s.label)}</span><div class="nz-meter ${tone}"><i style="--v:${s.value}%"></i></div><b>${Math.round(s.value)}%</b></div>`;
    }).join('');
  }
  NZ.$('#detail').innerHTML = d;
}

const path = () => stack.slice(1).map(s => s.menu.id);

function move(dir) {
  const c = cur();
  c.sel = (c.sel + dir + c.menu.items.length) % c.menu.items.length;
  render();
}

function change(dir) {
  const it = cur().menu.items[cur().sel];
  if (!it || !it.options) return;
  it.index = ((it.index - 1 + dir + it.options.length) % it.options.length) + 1;
  NZ.post('change', { id: it.id, value: it.options[it.index - 1], index: it.index });
  render();
}

function activate() {
  const it = cur().menu.items[cur().sel];
  if (!it || it.locked) return;
  if (it.items) { stack.push({ menu: it, sel: 0 }); render(); return; }
  if (typeof it.toggle === 'boolean') { it.toggle = !it.toggle; NZ.post('toggle', { id: it.id, value: it.toggle }); render(); return; }
  if (it.options) return change(1);
  NZ.post('select', { id: it.id, path: path() });
  if (it.close) NZ.close(app);
}

function back() {
  if (stack.length > 1) { stack.pop(); render(); } else NZ.close(app);
}

window.addEventListener('keydown', e => {
  if (!app.classList.contains('nz-open')) return;
  const k = e.key;
  if (k === 'ArrowDown') move(1);
  else if (k === 'ArrowUp') move(-1);
  else if (k === 'ArrowLeft') change(-1);
  else if (k === 'ArrowRight') change(1);
  else if (k === 'Enter') activate();
  else if (k === 'Backspace') back();
  else if (k === 'Escape') NZ.close(app);
  else return;
  e.preventDefault();
});

function open(d) {
  root = d;
  stack = [{ menu: root, sel: 0 }];
  render();
  NZ.open(app);
}
NZ.on('open', open);
NZ.on('close', () => NZ.close(app, { notify: false }));

NZ.preview(() => open({
  title: 'Garage', subtitle: 'Pillbox Hill · Public', hint: 'Vehicles stored at this location',
  items: [
    { id: 'vehicles', label: 'Stored vehicles', desc: '4 vehicles · 1 impounded', icon: 'car', count: 4, items: [
      { id: 'zentorno', label: 'Pegassi Zentorno', desc: 'Super · Stored', icon: 'car', plate: 'NZ 4021',
        stats: [{ label: 'Fuel', value: 82 }, { label: 'Engine', value: 96 }, { label: 'Body', value: 71 }], close: true },
      { id: 'sultan', label: 'Karin Sultan RS', desc: 'Sports · Stored', icon: 'car', plate: 'LS 9915',
        stats: [{ label: 'Fuel', value: 41 }, { label: 'Engine', value: 64 }, { label: 'Body', value: 88 }], close: true },
      { id: 'sanchez', label: 'Maibatsu Sanchez', desc: 'Motorcycle · Stored', icon: 'bolt', plate: 'DRT 07',
        stats: [{ label: 'Fuel', value: 18 }, { label: 'Engine', value: 52 }, { label: 'Body', value: 34 }], close: true },
      { id: 'baller', label: 'Gallivanter Baller', desc: 'Impounded · Davis lot', icon: 'lock', locked: true, price: 1250 },
    ]},
    { id: 'park', label: 'Park nearby vehicle', desc: 'Store the vehicle you are in', icon: 'garage' },
    { id: 'transfer', label: 'Transfer vehicle', desc: 'Move a vehicle to another garage', icon: 'swap', price: 500 },
    { id: 'settings', label: 'Garage settings', desc: 'Sorting and map display', icon: 'sliders', items: [
      { id: 'blips', label: 'Show garage blips', icon: 'pin', toggle: true },
      { id: 'sort', label: 'Sort vehicles by', icon: 'filter', options: ['Name', 'Fuel', 'Plate', 'Class'], index: 1 },
      { id: 'notify', label: 'Damage warnings', icon: 'bell', toggle: false },
    ]},
    { id: 'keys', label: 'Shared keys', desc: 'Manage who can drive your cars', icon: 'key', count: 2, info: 'Players with a shared key can take your vehicle out of any public garage.' },
    { id: 'exit', label: 'Leave garage', icon: 'logout', danger: true, close: true },
  ],
}));
