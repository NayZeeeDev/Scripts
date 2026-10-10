/* 03 · ORBIT
   SendNUIMessage({ action = 'open', data = { title, items = { {id, label, desc, icon, danger, items = {...}} } } })
   Up to 10 items per ring. Items with `items` open a sub-ring.
   Callbacks: select {id, path}, close
*/
const app = NZ.$('#app');
const R_IN = 106, R_OUT = 224, GAP = 1.4;
let root = null, stack = [], sel = -1;

const pt = (r, deg) => [r * Math.cos(deg * Math.PI / 180), r * Math.sin(deg * Math.PI / 180)];
function arc(r1, r2, a0, a1) {
  const large = a1 - a0 > 180 ? 1 : 0;
  const [x0, y0] = pt(r2, a0), [x1, y1] = pt(r2, a1), [x2, y2] = pt(r1, a1), [x3, y3] = pt(r1, a0);
  return `M${x0} ${y0}A${r2} ${r2} 0 ${large} 1 ${x1} ${y1}L${x2} ${y2}A${r1} ${r1} 0 ${large} 0 ${x3} ${y3}Z`;
}
function stroke(r, a0, a1) {
  const [x0, y0] = pt(r, a0), [x1, y1] = pt(r, a1);
  return `M${x0} ${y0}A${r} ${r} 0 ${a1 - a0 > 180 ? 1 : 0} 1 ${x1} ${y1}`;
}

const items = () => stack[stack.length - 1].items;
const step = () => 360 / items().length;
const start = i => -90 + i * step() - step() / 2;

function render() {
  const list = items(), n = list.length;
  let svg = `<circle class="dash" r="246"/>`;
  for (let t = 0; t < 72; t++) {
    const [x0, y0] = pt(232, t * 5), [x1, y1] = pt(t % 6 ? 235 : 238, t * 5);
    svg += `<line class="ticks" x1="${x0}" y1="${y0}" x2="${x1}" y2="${y1}"/>`;
  }
  svg += `<g class="segs">` + list.map((it, i) =>
    `<path class="seg ${it.danger ? 'danger' : ''}" data-i="${i}" d="${arc(R_IN, R_OUT, start(i) + GAP, start(i + 1) - GAP)}"/>`
  ).join('') + `<path class="halo" id="halo" d="" opacity="0"/></g>`;
  NZ.$('#svg').innerHTML = svg;

  const half = 270, mid = (R_IN + R_OUT) / 2;
  NZ.$('#labs').innerHTML = list.map((it, i) => {
    const [x, y] = pt(mid, -90 + i * step());
    return `<div class="lab ${it.danger ? 'danger' : ''}" data-i="${i}" style="left:${half + x}px;top:${half + y}px">
      <span class="num">${i + 1}</span>${NZ.icon(it.icon || 'more')}<span>${NZ.esc(it.label)}</span></div>`;
  }).join('');
  // restart the pop animation on ring change
  ['.segs', '#labs'].forEach(s => { const el = NZ.$(s); el.style.animation = 'none'; void el.offsetWidth; el.style.animation = ''; });

  NZ.$('#hub').classList.toggle('sub', stack.length > 1);
  highlight(-1);
}

function highlight(i) {
  sel = i;
  const list = items();
  NZ.$$('.seg').forEach(s => s.classList.toggle('on', +s.dataset.i === i));
  NZ.$$('.lab').forEach(s => s.classList.toggle('on', +s.dataset.i === i));
  const halo = NZ.$('#halo');
  const it = list[i];
  if (it) {
    halo.setAttribute('d', stroke(R_OUT + 8, start(i) + GAP + 2, start(i + 1) - GAP - 2));
    halo.setAttribute('class', 'halo' + (it.danger ? ' danger' : ''));
    halo.setAttribute('opacity', '1');
    NZ.$('#hub-title').textContent = it.label;
    NZ.$('#hub-desc').textContent = it.desc || (it.items ? `${it.items.length} options` : 'Click to confirm');
  } else {
    halo.setAttribute('opacity', '0');
    const ring = stack[stack.length - 1];
    NZ.$('#hub-title').textContent = ring.label || root.title || 'Interact';
    NZ.$('#hub-desc').textContent = stack.length > 1 ? 'Right click to go back' : 'Move your mouse to choose';
  }
}

function pick(i) {
  const it = items()[i];
  if (!it) return;
  if (it.items) { stack.push(it); render(); return; }
  NZ.post('select', { id: it.id, path: stack.slice(1).map(s => s.id) });
  NZ.close(app); // also posts close so Lua can drop focus
}
function back() { if (stack.length > 1) { stack.pop(); render(); } else NZ.close(app); }

window.addEventListener('mousemove', e => {
  if (!app.classList.contains('nz-open')) return;
  const r = NZ.$('#wheel').getBoundingClientRect();
  const dx = e.clientX - (r.left + r.width / 2), dy = e.clientY - (r.top + r.height / 2);
  if (Math.hypot(dx, dy) < R_IN - 14) { if (sel !== -1) highlight(-1); return; }
  let a = Math.atan2(dy, dx) * 180 / Math.PI + 90 + step() / 2;
  a = ((a % 360) + 360) % 360;
  const i = Math.floor(a / step());
  if (i !== sel) highlight(i);
});
window.addEventListener('mousedown', e => {
  if (!app.classList.contains('nz-open')) return;
  if (e.button === 2) back();
  else if (e.button === 0) { if (sel === -1 && e.target.closest('#hub')) back(); else pick(sel); }
});
window.addEventListener('contextmenu', e => e.preventDefault());
window.addEventListener('keydown', e => {
  if (!app.classList.contains('nz-open')) return;
  if (e.key === 'Escape') NZ.close(app);
  else if (e.key === 'Backspace') back();
  else if (/^[1-9]$/.test(e.key)) pick(+e.key - 1);
  else if (e.key === '0') pick(9);
});

function open(d) {
  root = d; stack = [d];
  render();
  NZ.open(app);
}
NZ.on('open', open);
NZ.on('close', () => NZ.close(app, { notify: false }));

NZ.preview(() => open({
  title: 'Interact',
  items: [
    { id: 'vehicle', label: 'Vehicle', icon: 'car', desc: 'Doors, engine and seats', items: [
      { id: 'engine', label: 'Engine', icon: 'power' }, { id: 'doors', label: 'Doors', icon: 'door' },
      { id: 'windows', label: 'Windows', icon: 'window' }, { id: 'hood', label: 'Hood', icon: 'hood' },
      { id: 'trunk', label: 'Trunk', icon: 'trunk' }, { id: 'seat', label: 'Change seat', icon: 'seat' },
    ]},
    { id: 'clothing', label: 'Clothing', icon: 'shirt', desc: 'Toggle worn items', items: [
      { id: 'hat', label: 'Hat', icon: 'hat' }, { id: 'mask', label: 'Mask', icon: 'mask' },
      { id: 'glasses', label: 'Glasses', icon: 'glasses' }, { id: 'shirt', label: 'Shirt', icon: 'shirt' },
      { id: 'shoes', label: 'Shoes', icon: 'shoe' },
    ]},
    { id: 'emotes', label: 'Emotes', icon: 'smile', desc: 'Quick animations', items: [
      { id: 'wave', label: 'Wave', icon: 'wave' }, { id: 'sit', label: 'Sit', icon: 'sit' },
      { id: 'dance', label: 'Dance', icon: 'dance' }, { id: 'cancel', label: 'Cancel emote', icon: 'x', danger: true },
    ]},
    { id: 'walk', label: 'Walkstyle', icon: 'walk', desc: 'Change how you move' },
    { id: 'job', label: 'Job', icon: 'badge', desc: 'Police actions', items: [
      { id: 'cuff', label: 'Cuff', icon: 'cuff' }, { id: 'escort', label: 'Escort', icon: 'hand' },
      { id: 'search', label: 'Search', icon: 'search' }, { id: 'jail', label: 'Send to jail', icon: 'lock', danger: true },
    ]},
    { id: 'bill', label: 'Billing', icon: 'receipt', desc: 'Send an invoice' },
    { id: 'id', label: 'Show ID', icon: 'id', desc: 'Show your ID to nearby players' },
    { id: 'keys', label: 'Give keys', icon: 'key', desc: 'Share the closest vehicle' },
  ],
}));
