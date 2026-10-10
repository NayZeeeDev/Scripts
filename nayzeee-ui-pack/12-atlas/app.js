/* 12 · ATLAS
   SendNUIMessage({ action = 'open', data = {
     title = 'Choose a spawn point',            -- optional
     subtitle = 'Los Santos · San Andreas',     -- optional
     closable = false,                          -- true lets ESC close without spawning (posts 'close')
     locations = {
       { id = 'last', label = 'Last location', district = 'Little Seoul', type = 'public', last = true,
         x = 36, y = 50,                        -- position on the chart in percent (0-100, from top-left)
         desc = 'Pick up where you left off.', tags = { 'Exact position' } },
       { id = 'alta', label = 'Alta Street Apartments', district = 'Downtown', type = 'apartment',
         x = 50, y = 37, desc = '...', tags = { 'Safe zone', 'Garage nearby' },
         meta = '2 min' },                      -- optional: replaces the estimated travel text
     } } })
   type = 'apartment' | 'public' | 'job'  (housing / house / motel also group under Apartments)
   icon = any core icon name, optional
   SendNUIMessage({ action = 'close' })

   Callbacks:
     preview {id}   selection changed (list, arrow keys or hovering a pin). Move the camera here.
     spawn   {id}   the UI closes itself afterwards (NZ.close → also posts 'close').
     close          posted whenever the UI closes.
*/
NZ.addIcons({
  history: '<path d="M3.5 12a8.5 8.5 0 1 0 2.5-6"/><path d="M3.5 4v4h4M12 7.5V12l3 2"/>',
  building: '<path d="M5 21V4.5A1.5 1.5 0 0 1 6.5 3h7A1.5 1.5 0 0 1 15 4.5V21M15 9h3.5A1.5 1.5 0 0 1 20 10.5V21M3 21h18"/><path d="M8.5 7h3M8.5 11h3M8.5 15h3"/>',
  route: '<circle cx="6" cy="18" r="2.5"/><circle cx="18" cy="6" r="2.5"/><path d="M8.5 18H16a3.5 3.5 0 0 0 0-7H8a3.5 3.5 0 0 1 0-7h7.5"/>',
});

const app = NZ.$('#app');
const COLS = 'ABCDEFGHIJKL', ROWS = 8;
const GROUPS = [
  { key: 'last', label: 'Last location', icon: 'history', cls: 'last' },
  { key: 'apartment', label: 'Apartments', icon: 'building', cls: 'apt' },
  { key: 'public', label: 'Public', icon: 'pin', cls: 'pub' },
  { key: 'job', label: 'Job', icon: 'briefcase', cls: 'job' },
];
const DISTRICTS = [
  ['Del Perro', 24, 53], ['Vespucci', 21, 66], ['Rockford Hills', 39, 21], ['Vinewood Hills', 66, 9],
  ['Downtown', 45, 31], ['Little Seoul', 38, 58], ['Strawberry', 47, 70], ['Mirror Park', 85, 24],
  ['East Los Santos', 71, 47], ['La Mesa', 82, 73], ['Port of Los Santos', 72, 95], ['Airport', 42, 91],
];

let cfg = {}, locs = [], order = [], sel = -1, lastSent = null;

const groupOf = l => l.last ? 'last'
  : /apart|hous|home|motel|hotel|flat/i.test(l.type || '') ? 'apartment'
  : /job|work|duty/i.test(l.type || '') ? 'job' : 'public';
const groupMeta = l => GROUPS.find(g => g.key === groupOf(l));
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const gridRef = l => COLS[clamp(Math.floor(l.x / 100 * COLS.length), 0, COLS.length - 1)] + (clamp(Math.floor(l.y / 100 * ROWS), 0, ROWS - 1) + 1);

// rough travel estimate from the last location (or the map centre): the chart spans ~10 km × 7 km
function travel(l) {
  if (l.meta) return { a: l.meta, b: '' };
  if (l.last) return { a: 'Resume', b: 'Where you left' };
  const ref = locs.find(x => x.last) || { x: 50, y: 50 };
  const km = Math.hypot((l.x - ref.x) * 0.1, (l.y - ref.y) * 0.07);
  const min = Math.max(1, Math.round(km * 1.4 + 0.4));
  return { a: `${km.toFixed(1)} km`, b: `≈ ${min} min drive` };
}

function tone(t) {
  if (/safe|garage|medical|hospital|stash|wardrobe|locker/i.test(t)) return 'nz-tag live';
  if (/gang|danger|hostile|pvp|red zone|wanted/i.test(t)) return 'nz-tag hot';
  if (/restrict|curfew|warning|after dark|limited/i.test(t)) return 'nz-tag warn';
  return 'nz-chip white';
}

/* ── static chart furniture ── */
function drawTicks() {
  const cols = [...COLS].map(c => `<span>${c}</span>`).join('');
  const rows = Array.from({ length: ROWS }, (_, i) => `<span>${String(i + 1).padStart(2, '0')}</span>`).join('');
  NZ.$('#t-top').innerHTML = cols; NZ.$('#t-bottom').innerHTML = cols;
  NZ.$('#t-left').innerHTML = rows; NZ.$('#t-right').innerHTML = rows;
  NZ.$('#dlabels').innerHTML = DISTRICTS.map(([n, x, y]) => `<span style="left:${x}%;top:${y}%">${NZ.esc(n)}</span>`).join('')
    + '<span class="sea" style="left:7%;top:86%">Pacific</span>';
}

/* ── render ── */
function renderPins() {
  NZ.$('#pins').innerHTML = order.map((l, i) => {
    const g = groupMeta(l);
    const x = clamp(+l.x || 0, 0, 100), y = clamp(+l.y || 0, 0, 100);
    return `<button class="pin ${g.cls} ${x > 70 ? 'flip' : ''}" data-i="${i}" style="left:${x}%;top:${y}%" aria-label="${NZ.esc(l.label)}">
      <span class="pb">${NZ.icon(l.icon || g.icon)}</span>
      <span class="pl"><b>${NZ.esc(l.label)}</b><span>${NZ.esc(l.district || '')}</span></span>
    </button>`;
  }).join('');
  NZ.$$('#pins .pin').forEach(p => {
    p.onmouseenter = () => select(+p.dataset.i, true);
    p.onclick = () => select(+p.dataset.i, true);
    p.ondblclick = () => spawn();
  });
}

function renderList() {
  let html = '', n = 0;
  GROUPS.forEach(g => {
    const items = order.map((l, i) => [l, i]).filter(([l]) => groupOf(l) === g.key);
    if (!items.length) return;
    if (g.key !== 'last') html += `<div class="grp-h">${NZ.esc(g.label)} <em>${items.length}</em></div>`;
    items.forEach(([l, i]) => {
      const t = travel(l);
      n++;
      html += `<button class="loc ${g.cls}" data-i="${i}">
        <span class="ix">${NZ.icon(l.icon || g.icon)}</span>
        <span class="lb"><b>${NZ.esc(l.label)}</b><span>${NZ.esc(l.district || '')} · ${gridRef(l)}</span></span>
        <span class="mt"><b>${NZ.esc(t.a)}</b>${t.b ? `<span>${NZ.esc(t.b)}</span>` : ''}</span>
      </button>`;
    });
  });
  NZ.$('#list').innerHTML = html || `<div class="nz-empty">${NZ.icon('map')}<b>No locations</b><span>There is nowhere to spawn right now.</span></div>`;
  NZ.$('#count').textContent = `${n} place${n === 1 ? '' : 's'}`;
  NZ.$$('#list .loc').forEach(b => {
    b.onclick = () => select(+b.dataset.i);
    b.ondblclick = () => spawn();
  });
}

function renderDetail() {
  const l = order[sel];
  const d = NZ.$('#detail');
  if (!l) { d.innerHTML = ''; return; }
  const g = groupMeta(l);
  const tags = Array.isArray(l.tags) ? l.tags : [];
  d.innerHTML = `<div class="in">
    <div class="dt-eye"><b>${NZ.esc(g.label)}</b>· Grid ${gridRef(l)}</div>
    <h3>${NZ.esc(l.label)}</h3>
    <div class="dt-dist">${NZ.icon('pin')}${NZ.esc(l.district || 'Los Santos')}${l.last ? '' : `<span style="opacity:.5">·</span>${NZ.icon('route')}${NZ.esc(travel(l).a)}`}</div>
    ${l.desc ? `<p>${NZ.esc(l.desc)}</p>` : ''}
    <div class="dt-tags">${tags.map(t => `<span class="${tone(String(t))}">${NZ.esc(t)}</span>`).join('')}</div>
  </div>`;
}

function select(i, fromMap) {
  if (!order.length) return;
  i = (i + order.length) % order.length;
  const changed = i !== sel;
  sel = i;
  const l = order[sel];
  NZ.$$('#pins .pin').forEach(p => p.classList.toggle('on', +p.dataset.i === sel));
  NZ.$$('#list .loc').forEach(b => b.classList.toggle('on', +b.dataset.i === sel));
  const on = NZ.$('#list .loc.on');
  if (on && (fromMap || changed)) on.scrollIntoView({ block: 'nearest' });

  const x = clamp(+l.x || 0, 0, 100), y = clamp(+l.y || 0, 0, 100);
  const v = NZ.$('#xh-v'), h = NZ.$('#xh-h');
  v.hidden = h.hidden = false;
  v.style.left = `${x}%`; h.style.top = `${y}%`;
  NZ.$('#r-grid').textContent = gridRef(l);
  NZ.$('#r-x').textContent = x.toFixed(1);
  NZ.$('#r-y').textContent = y.toFixed(1);
  const col = clamp(Math.floor(x / 100 * COLS.length), 0, COLS.length - 1), row = clamp(Math.floor(y / 100 * ROWS), 0, ROWS - 1);
  ['#t-top', '#t-bottom'].forEach(s => NZ.$$(`${s} span`).forEach((t, k) => t.classList.toggle('on', k === col)));
  ['#t-left', '#t-right'].forEach(s => NZ.$$(`${s} span`).forEach((t, k) => t.classList.toggle('on', k === row)));

  if (changed) renderDetail();
  NZ.$('#go-sub').textContent = l.label;
  NZ.$('#spawn').disabled = false;
  if (lastSent !== l.id) { lastSent = l.id; NZ.post('preview', { id: l.id }); }
}

function spawn() {
  const l = order[sel];
  if (!l) return;
  NZ.post('spawn', { id: l.id });
  NZ.close(app);
}
NZ.$('#spawn').onclick = spawn;

window.addEventListener('keydown', e => {
  if (!app.classList.contains('nz-open')) return;
  const k = e.key;
  if (k === 'ArrowDown') select(sel + 1);
  else if (k === 'ArrowUp') select(sel - 1);
  else if (k === 'Enter') spawn();
  else if (k === 'Escape') { if (cfg.closable) NZ.close(app); }
  else return;
  e.preventDefault();
});

function openUI(d) {
  cfg = d || {};
  locs = Array.isArray(cfg.locations) ? cfg.locations.slice() : [];
  // list + pin order follows the groups, so ↑/↓ walks the rail top to bottom
  order = GROUPS.flatMap(g => locs.filter(l => groupOf(l) === g.key));
  NZ.$('#title').textContent = cfg.title || 'Choose a spawn point';
  NZ.$('#subtitle').textContent = cfg.subtitle || `Los Santos · ${order.length} location${order.length === 1 ? '' : 's'}`;
  sel = -1; lastSent = null;
  NZ.$('#xh-v').hidden = NZ.$('#xh-h').hidden = true;
  NZ.$('#detail').innerHTML = '';
  NZ.$('#spawn').disabled = true;
  NZ.$('#go-sub').textContent = 'Select a location';
  ['#r-grid', '#r-x', '#r-y'].forEach(s => NZ.$(s).textContent = '—');
  renderPins();
  renderList();
  NZ.open(app);
  if (order.length) select(0);
}
drawTicks();
NZ.on('open', openUI);
NZ.on('close', () => NZ.close(app, { notify: false }));

NZ.preview(() => openUI({
  title: 'Choose a spawn point',
  subtitle: 'Los Santos · San Andreas',
  closable: true,
  locations: [
    { id: 'last', label: 'Last location', district: 'Little Seoul', type: 'public', last: true, x: 36, y: 50,
      desc: 'Wake up exactly where you logged out, outside the gallery on San Andreas Avenue.', tags: ['Exact position', 'Vehicle nearby'] },
    { id: 'alta', label: 'Alta Street Apartments', district: 'Downtown', type: 'apartment', x: 50, y: 37,
      desc: 'Your 3rd floor unit. Private garage on the lower level and a stash in the wardrobe.', tags: ['Safe zone', 'Garage nearby', 'Stash'] },
    { id: 'integrity', label: '4 Integrity Way', district: 'Downtown', type: 'apartment', x: 58, y: 32,
      desc: 'High rise with a concierge. The elevator drops you straight into the parking deck.', tags: ['Garage nearby', 'Elevator'] },
    { id: 'eclipse', label: 'Eclipse Towers', district: 'Rockford Hills', type: 'apartment', x: 33, y: 27,
      desc: 'Penthouse suite on Eclipse Boulevard with a view across the whole city.', tags: ['Safe zone', 'Wardrobe'] },
    { id: 'delperro', label: 'Del Perro Heights', district: 'Del Perro', type: 'apartment', x: 21, y: 44,
      desc: 'Beachside apartment, two minutes from the pier.', tags: ['Garage nearby'] },
    { id: 'legion', label: 'Legion Square', district: 'Mission Row', type: 'public', x: 53, y: 58,
      desc: 'The heart of the city. Busy, central and always someone around.', tags: ['Safe zone', 'Bank nearby', 'Taxi rank'] },
    { id: 'vespucci', label: 'Vespucci Beach', district: 'Vespucci', type: 'public', x: 17, y: 61,
      desc: 'On the boardwalk by the muscle beach gym.', tags: ['Bike rental'] },
    { id: 'vinewood', label: 'Vinewood Boulevard', district: 'Vinewood', type: 'public', x: 50, y: 17,
      desc: 'Outside the Oriental Theater on the walk of fame.', tags: ['Taxi rank'] },
    { id: 'mirror', label: 'Mirror Park', district: 'East Vinewood', type: 'public', x: 82, y: 34,
      desc: 'Quiet lakeside park in the east of the city.', tags: ['Quiet area'] },
    { id: 'lsia', label: 'Los Santos International', district: 'LSIA', type: 'public', x: 30, y: 85,
      desc: 'Arrivals hall. Rental desk and taxis just outside.', tags: ['Car rental', 'Taxi rank'] },
    { id: 'mrpd', label: 'Mission Row PD', district: 'Mission Row', type: 'job', x: 60, y: 62,
      desc: 'Station locker room. Clock on duty at the front desk.', tags: ['Duty locker', 'Armoury', 'Garage nearby'] },
    { id: 'pillbox', label: 'Pillbox Medical', district: 'Pillbox Hill', type: 'job', x: 53, y: 46,
      desc: 'Staff entrance on the upper floor, next to the helipad.', tags: ['Medical', 'Helipad'] },
    { id: 'docks', label: 'Port of Los Santos', district: 'Elysian Island', type: 'job', x: 80, y: 86,
      desc: 'Dock worker gate at the container yard.', tags: ['Restricted after dark', 'Forklift'] },
  ],
}));
