/* 13 · FORGE
   SendNUIMessage({ action = 'open', data = {
     bench = { label = 'Weapon bench', sub = 'Sandy Shores garage' },
     level = 3,                                   -- player's crafting skill
     slots = 5,                                   -- optional, max queue length (default 5)
     categories = { {id = 'weapons', label = 'Weapons', icon = 'pistol'} },
     recipes = { {
       id = 'pistol', label = 'Pistol', desc = '...', icon = 'pistol', category = 'weapons',
       time = 45,            -- seconds per craft
       amount = 1,           -- output per craft
       chance = 90,          -- success % (0-100, or 0-1)
       level = 2,            -- required skill level
       max = 10,             -- optional cap per craft order
       materials = { {name = 'steel', label = 'Steel', need = 4, icon = 'ingot'} },
     } },
     inventory = { steel = 12, spring = 3 },
     queue = { ... },                             -- optional, same shape as the 'queue' message
   } })
   SendNUIMessage({ action = 'inventory', data = { steel = 8 } })   -- merges counts
   SendNUIMessage({ action = 'queue', data = {
     { id = 'q1', recipe = 'pistol', qty = 2, ends = os.time() * 1000 + 90000,
       starts = nil } } })                       -- replaces the queue; starts (ms) optional, defaults to ends - time*qty
   SendNUIMessage({ action = 'close' })

   Callbacks:
     craft   { id, qty }   → return { ok = true } or { ok = false, error = '...' }; then send 'queue' + 'inventory'
     cancel  { queueId }
     collect { queueId }
     close
*/
NZ.addIcons({
  hammer: '<path d="M14.5 4.5 19.5 9.5 17 12l-5-5 2.5-2.5z"/><path d="m12 7-1.5-1.5L13 3l1.5 1.5M14.5 9.5 4 20l-1-1 10.5-10.5"/>',
  flask: '<path d="M9.5 3h5M10 3v6l-5 9a2 2 0 0 0 1.8 3h10.4a2 2 0 0 0 1.8-3l-5-9V3"/><path d="M7.5 15h9"/>',
  ingot: '<path d="M3 17 6 9h12l3 8H3z"/><path d="M6 9l1.5-3h9L18 9"/>',
  cog: '<circle cx="12" cy="12" r="3"/><path d="M12 3v2.5M12 18.5V21M3 12h2.5M18.5 12H21M5.6 5.6l1.8 1.8M16.6 16.6l1.8 1.8M5.6 18.4l1.8-1.8M16.6 7.4l1.8-1.8"/>',
  pan: '<circle cx="10" cy="13" r="6.5"/><path d="M16.5 13H22M10 9.5a3.5 3.5 0 0 0-3.5 3.5"/>',
  leaf: '<path d="M5 19C5 10 10 5 20 4c-1 10-6 15-15 15z"/><path d="M5 19 13 11"/>',
  spring: '<path d="M7 4h10M7 20h10M7 6.5l10 2-10 2 10 2-10 2 10 2-10 2"/>',
  chip: '<rect x="6" y="6" width="12" height="12" rx="1.5"/><rect x="9.5" y="9.5" width="5" height="5"/><path d="M9 3v3M15 3v3M9 18v3M15 18v3M3 9h3M3 15h3M18 9h3M18 15h3"/>',
  scale: '<path d="M12 4v16M7 20h10M5 7h14M5 7l-2.5 6a2.5 2.5 0 0 0 5 0L5 7zM19 7l-2.5 6a2.5 2.5 0 0 0 5 0L19 7z"/>',
  barrel: '<path d="M7 3h10c1.5 3 1.5 15 0 18H7c-1.5-3-1.5-15 0-18z"/><path d="M5.6 8h12.8M5.6 16h12.8"/>',
  ammo: '<path d="M7 9a2 2 0 0 1 4 0v11H7V9zM13 9a2 2 0 0 1 4 0v11h-4V9z"/><path d="M7 16h4M13 16h4M9 4v3M15 4v3"/>',
  powder: '<path d="M4 18c2-5 5-8 8-8s6 3 8 8H4z"/><path d="M8 7.5v.01M12 5v.01M16 7.5v.01"/>',
});

const app = NZ.$('#app');
let st = null;              // open payload
let inv = {};
let queue = [];
let cat = 'all', query = '', sel = null, qty = 1, busy = false, msg = null;
let ticker = null;

const recipe = id => (st.recipes || []).find(r => r.id === id);
const have = name => inv[name] || 0;
const pct = c => c == null ? 100 : Math.round(c <= 1 ? c * 100 : c);
const slots = () => st.slots || 5;

function fmtTime(s) {
  s = Math.max(0, Math.round(s));
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60), r = s % 60;
  if (m < 60) return r ? `${m}m ${r}s` : `${m}m`;
  return `${Math.floor(m / 60)}h ${m % 60}m`;
}
const clock = ms => { const s = Math.max(0, Math.ceil(ms / 1000)); return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`; };

function maxFor(r) {
  const mats = r.materials || [];
  let m = mats.length ? Math.min(...mats.map(x => Math.floor(have(x.name) / Math.max(1, x.need)))) : 99;
  return Math.max(0, Math.min(m, r.max || 99));
}
function state(r) {
  if ((r.level || 0) > (st.level || 0)) return 'locked';
  return maxFor(r) >= 1 ? 'ok' : 'short';
}

function visible() {
  const q = query.toLowerCase();
  return (st.recipes || []).filter(r => (cat === 'all' || r.category === cat) &&
    (!q || r.label.toLowerCase().includes(q) || (r.materials || []).some(m => (m.label || m.name).toLowerCase().includes(q))));
}

/* ── 01 ── */
function renderTabs() {
  const all = [{ id: 'all', label: 'All', icon: 'grid' }, ...(st.categories || [])];
  NZ.$('#tabs').innerHTML = all.map(c => `<button class="drawer ${c.id === cat ? 'on' : ''}" data-c="${NZ.esc(c.id)}" title="${NZ.esc(c.label)}">${NZ.icon(c.icon || 'box')}<span>${NZ.esc(c.label)}</span></button>`).join('');
  NZ.$$('.drawer').forEach(b => b.onclick = () => { cat = b.dataset.c; renderTabs(); renderList(); });
}

function renderList() {
  const list = visible();
  const recs = st.recipes || [];
  NZ.$('#known').textContent = recs.length;
  NZ.$('#ready').textContent = recs.filter(r => state(r) === 'ok').length;
  NZ.$('#list-meta').innerHTML = `<em>${list.length}</em> shown`;
  NZ.$('#list').innerHTML = list.length ? list.map((r, k) => {
    const s = state(r), m = maxFor(r);
    const end = s === 'locked' ? `${NZ.icon('lock')}Level ${NZ.esc(r.level)}`
      : s === 'ok' ? `<span class="nz-dot"></span>${m}×`
      : `<span class="nz-dot red"></span>Missing`;
    return `<button class="rc ${s} ${r.id === sel ? 'on' : ''}" data-id="${NZ.esc(r.id)}" style="animation-delay:${Math.min(k, 12) * 18}ms">
      <span class="nz-tile ${s === 'ok' ? '' : 'mute'}">${NZ.icon(r.icon)}</span>
      <span class="t"><b>${NZ.esc(r.label)}</b><span>${NZ.icon('timer')}${fmtTime(r.time || 0)}<i>/</i>makes ${NZ.esc(r.amount || 1)}</span></span>
      <span class="st">${end}</span></button>`;
  }).join('') : `<div class="nz-empty">${NZ.icon('search')}<b>No recipe matches</b><span>Try another word or open a different drawer.</span></div>`;
  NZ.$$('.rc').forEach(b => b.onclick = () => pick(b.dataset.id));
}

function pick(id) {
  if (sel !== id) { sel = id; qty = 1; msg = null; }
  NZ.$$('.rc').forEach(b => b.classList.toggle('on', b.dataset.id === id));
  renderDetail();
  const on = NZ.$('.rc.on'); if (on) on.scrollIntoView({ block: 'nearest' });
}

/* ── 02 / 03 ── */
function renderDetail() {
  const r = sel && recipe(sel);
  const bp = NZ.$('#bp');
  if (!r) {
    NZ.$('#main-meta').textContent = '';
    bp.innerHTML = `<div class="nz-empty">${NZ.icon('hammer')}<b>Pick a recipe</b><span>Choose something from the list to see what it needs.</span></div>`;
    return;
  }
  const c = (st.categories || []).find(x => x.id === r.category);
  const m = maxFor(r);
  qty = Math.max(1, Math.min(qty, Math.max(1, m)));
  const lvOk = (r.level || 0) <= (st.level || 0);
  const ch = pct(r.chance);
  NZ.$('#main-meta').innerHTML = `${NZ.esc(st.bench?.label || 'Bench')}`;

  bp.innerHTML = `
    <div class="bp-top">
      <div class="stage">
        <span class="tk x"></span><span class="tk y"></span>
        <span class="cr a"></span><span class="cr b"></span><span class="cr c"></span>
        <span class="dim">${NZ.esc(String(r.id).toUpperCase().slice(0, 14))}</span>
        ${NZ.icon(r.icon)}
        <span class="out">× ${NZ.esc(r.amount || 1)}</span>
      </div>
      <div class="bp-info">
        <div class="bp-cat">${NZ.icon(c?.icon || 'box')}${NZ.esc(c?.label || 'Recipe')}</div>
        <h1>${NZ.esc(r.label)}</h1>
        <p>${NZ.esc(r.desc || '')}</p>
        <div class="chips">
          <span class="nz-chip ${lvOk ? '' : 'red'}">${NZ.icon(lvOk ? 'check' : 'lock')}Skill level ${NZ.esc(r.level || 0)}</span>
          <span class="nz-chip white">${NZ.icon('hammer')}${NZ.esc(st.bench?.label || 'Bench')}</span>
          <span class="nz-chip white">${NZ.icon('box')}Makes ${NZ.esc(r.amount || 1)} per craft</span>
        </div>
        <div class="specs">
          <div><span>Time per craft</span><b>${fmtTime(r.time || 0)}</b></div>
          <div><span>Success chance</span><b class="${ch < 60 ? 'warn' : ''}">${ch}%</b></div>
          <div><span>You can make</span><b>${m}×</b></div>
        </div>
      </div>
    </div>
    <div class="bp-sec"><span class="step">03</span><b>Materials</b><span class="z-meta" id="mat-meta"></span></div>
    <div class="mats nz-scroll" id="mats"></div>
    <div class="act">
      <div class="qty"><span>Quantity</span>
        <div class="qty-row">
          <div class="stepper"><button id="q-dn">${NZ.icon('minus')}</button><input id="q-in" type="number" min="1"><button id="q-up">${NZ.icon('plus')}</button></div>
          <button class="nz-btn line" id="q-max">Max ${m}</button>
        </div>
      </div>
      <div class="sum">
        <div><span>Output</span><b id="s-out"></b></div>
        <div><span>Success</span><b>${ch}%</b></div>
        <div><span>Total time</span><b id="s-time"></b></div>
      </div>
      <div class="craft"><button class="nz-btn teal" id="craft">${NZ.icon('hammer')}Craft</button><div class="reason" id="reason"></div></div>
    </div>`;

  NZ.$('#q-dn').onclick = () => setQty(qty - 1);
  NZ.$('#q-up').onclick = () => setQty(qty + 1);
  NZ.$('#q-max').onclick = () => setQty(maxFor(r));
  NZ.$('#q-in').onchange = e => setQty(parseInt(e.target.value, 10) || 1);
  NZ.$('#craft').onclick = craft;
  renderQty();
}

function renderQty() {
  const r = sel && recipe(sel);
  if (!r || !NZ.$('#mats')) return;
  const m = maxFor(r), s = state(r);
  NZ.$('#q-in').value = qty;
  NZ.$('#q-dn').disabled = qty <= 1;
  NZ.$('#q-up').disabled = qty >= Math.max(1, m);
  NZ.$('#q-max').disabled = m < 2;
  NZ.$('#s-out').textContent = `${qty * (r.amount || 1)}×`;
  NZ.$('#s-time').textContent = fmtTime((r.time || 0) * qty);

  const mats = r.materials || [];
  let short = 0;
  NZ.$('#mats').innerHTML = mats.map((x, k) => {
    const need = x.need * qty, h = have(x.name), lack = h < need;
    if (lack) short++;
    return `<div class="mat ${lack ? 'short' : ''}" style="animation-delay:${k * 25}ms">
      <span class="nz-tile ${lack ? 'red' : 'mute'}">${NZ.icon(x.icon || 'box')}</span>
      <b>${NZ.esc(x.label || x.name)}</b>
      <span class="cnt">${h}<i> / ${need}</i></span>
      <div class="nz-meter ${lack ? 'red' : ''}"><i style="--v:${Math.min(100, need ? h / need * 100 : 100)}%"></i></div></div>`;
  }).join('') || `<div class="nz-empty" style="grid-column:1/-1">${NZ.icon('check')}<b>No materials needed</b></div>`;
  NZ.$('#mat-meta').innerHTML = short ? `<span style="color:var(--red)">${short} short</span>` : `<em>${mats.length}</em> parts · all in stock`;

  // craft button + reason
  let reason = '', cls = 'err';
  const missing = mats.find(x => have(x.name) < x.need * qty);
  if (s === 'locked') reason = `Requires skill level ${r.level} — you are level ${st.level || 0}`;
  else if (missing) reason = `Missing ${missing.need * qty - have(missing.name)}× ${missing.label || missing.name}`;
  else if (queue.length >= slots()) reason = `Queue is full (${slots()} slots)`;
  else if (msg) { reason = msg.text; cls = msg.ok ? 'ok' : 'err'; }
  else { reason = `Uses ${mats.reduce((a, x) => a + x.need * qty, 0)} materials`; cls = ''; }
  const btn = NZ.$('#craft');
  const blocked = s === 'locked' || !!missing || queue.length >= slots() || busy;
  btn.disabled = blocked;
  btn.innerHTML = `${NZ.icon('hammer')}Craft ${qty > 1 ? qty + '×' : ''}`;
  NZ.$('#reason').className = `reason ${cls}`;
  NZ.$('#reason').innerHTML = (cls === 'err' ? NZ.icon('alert') : cls === 'ok' ? NZ.icon('check') : '') + NZ.esc(reason);
}

function setQty(n) {
  const r = recipe(sel); if (!r) return;
  qty = Math.max(1, Math.min(n, Math.max(1, maxFor(r))));
  msg = null;
  renderQty();
}

async function craft() {
  const r = recipe(sel);
  if (!r || busy || NZ.$('#craft').disabled) return;
  busy = true;
  const n = qty;
  let res;
  if (NZ.inGame) res = await NZ.post('craft', { id: r.id, qty: n });
  else {
    // preview: take materials and queue it on the UI timer
    (r.materials || []).forEach(x => { inv[x.name] = have(x.name) - x.need * n; });
    const last = queue.reduce((a, j) => Math.max(a, j.ends), Date.now());
    queue.push({ id: 'q' + Date.now(), recipe: r.id, qty: n, starts: last, ends: last + (r.time || 0) * n * 1000 });
    res = { ok: true };
  }
  busy = false;
  msg = res && res.ok === false ? { ok: false, text: res.error || 'Could not start crafting' } : { ok: true, text: `Queued ${n}× ${r.label}` };
  qty = 1;
  renderList(); renderDetail(); renderQueue();
}

/* ── 04 queue ── */
function jobTimes(j) {
  const r = recipe(j.recipe) || {};
  const dur = (r.time || 0) * (j.qty || 1) * 1000;
  const starts = j.starts != null ? j.starts : j.ends - dur;
  return { r, starts, dur: Math.max(1, j.ends - starts) };
}

function renderQueue() {
  const now = Date.now();
  NZ.$('#q-meta').innerHTML = `<em>${queue.length}</em> / ${slots()} slots`;
  NZ.$('#queue').innerHTML = queue.length ? queue.map(j => {
    const { r } = jobTimes(j);
    const done = now >= j.ends;
    return `<div class="job ${done ? 'done' : ''}" data-q="${NZ.esc(j.id)}">
      <span class="nz-tile">${NZ.icon(r.icon || 'box')}</span>
      <span class="t"><b>${NZ.esc(r.label || j.recipe)} <em>× ${NZ.esc((j.qty || 1) * (r.amount || 1))}</em></b><span class="lbl"></span></span>
      ${done ? `<button class="nz-btn teal sm collect" data-collect="${NZ.esc(j.id)}">Collect</button>`
             : `<button class="x" data-cancel="${NZ.esc(j.id)}" title="Cancel">${NZ.icon('x')}</button>`}
      <div class="bar"><i></i></div></div>`;
  }).join('') : `<div class="nz-empty">${NZ.icon('timer')}<b>Nothing on the bench</b><span>Crafts you start show up here with a live timer.</span></div>`;
  NZ.$$('[data-cancel]').forEach(b => b.onclick = () => cancelJob(b.dataset.cancel));
  NZ.$$('[data-collect]').forEach(b => b.onclick = () => collect(b.dataset.collect));

  const ready = queue.filter(j => now >= j.ends);
  const left = queue.reduce((a, j) => Math.max(a, j.ends), now) - now;
  NZ.$('#q-foot').innerHTML = queue.length
    ? (ready.length > 1 ? `<button class="nz-btn teal block" id="collect-all">Collect all · ${ready.length}</button>` : '') +
      `<p>${left > 0 ? `Bench clear in <b style="color:var(--white)">${fmtTime(left / 1000)}</b>. ` : ''}Cancelling returns the materials of anything not finished.</p>`
    : '';
  const all = NZ.$('#collect-all');
  if (all) all.onclick = () => ready.forEach(j => collect(j.id));
  tick();
}

function tick() {
  const now = Date.now();
  let flip = false;
  queue.forEach(j => {
    const el = NZ.$(`.job[data-q="${CSS.escape(j.id)}"]`);
    if (!el) return;
    const { starts, dur } = jobTimes(j);
    const done = now >= j.ends;
    if (done !== el.classList.contains('done')) flip = true;
    const waiting = now < starts;
    el.classList.toggle('wait', waiting);
    el.querySelector('.bar > i').style.width = `${done ? 100 : waiting ? 0 : Math.min(100, (now - starts) / dur * 100)}%`;
    el.querySelector('.lbl').innerHTML = done ? 'Ready to collect'
      : waiting ? `Queued · starts in ${clock(starts - now)}`
      : `Crafting · <strong>${clock(j.ends - now)}</strong> left`;
  });
  if (flip) renderQueue();
}

function cancelJob(id) {
  const j = queue.find(x => x.id === id); if (!j) return;
  NZ.post('cancel', { queueId: id });
  if (!NZ.inGame) {
    const r = recipe(j.recipe);
    (r?.materials || []).forEach(x => { inv[x.name] = have(x.name) + x.need * j.qty; });
    // shift later jobs forward
    const { dur } = jobTimes(j), now = Date.now();
    queue.forEach(o => { if (o.starts != null && o.starts >= j.ends - dur && o !== j) { const shift = Math.min(dur, Math.max(0, o.starts - now)); o.starts -= shift; o.ends -= shift; } });
  }
  queue = queue.filter(x => x.id !== id);
  msg = null;
  renderAll();
}

function collect(id) {
  const j = queue.find(x => x.id === id); if (!j) return;
  NZ.post('collect', { queueId: id });
  if (!NZ.inGame) { const r = recipe(j.recipe); inv[j.recipe] = have(j.recipe) + j.qty * (r?.amount || 1); }
  queue = queue.filter(x => x.id !== id);
  renderAll();
}

function renderAll() { renderList(); renderDetail(); renderQueue(); }

/* ── input ── */
NZ.$('#q').oninput = e => { query = e.target.value.trim(); renderList(); };
NZ.$$('[data-close]').forEach(b => b.onclick = () => NZ.close(app));
window.addEventListener('keydown', e => {
  if (!app.classList.contains('nz-open')) return;
  const typing = document.activeElement && document.activeElement.tagName === 'INPUT';
  if (e.key === 'Escape') { if (typing) document.activeElement.blur(); else NZ.close(app); return; }
  if (typing && document.activeElement.id === 'q' && e.key !== 'ArrowDown' && e.key !== 'ArrowUp' && e.key !== 'Enter') return;
  if (typing && document.activeElement.id === 'q-in') return;
  if (e.key === '/') { e.preventDefault(); NZ.$('#q').focus(); return; }
  const list = visible();
  const i = list.findIndex(r => r.id === sel);
  if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
    e.preventDefault();
    if (!list.length) return;
    const n = i < 0 ? 0 : (i + (e.key === 'ArrowDown' ? 1 : -1) + list.length) % list.length;
    pick(list[n].id);
  } else if (e.key === 'ArrowRight') { e.preventDefault(); setQty(qty + 1); }
  else if (e.key === 'ArrowLeft') { e.preventDefault(); setQty(qty - 1); }
  else if (e.key === 'Enter') { e.preventDefault(); if (typing) document.activeElement.blur(); craft(); }
});

/* ── messages ── */
function openForge(d) {
  st = d || {};
  inv = Object.assign({}, st.inventory || {});
  queue = Array.isArray(st.queue) ? st.queue.slice() : [];
  cat = 'all'; query = ''; NZ.$('#q').value = ''; msg = null; qty = 1;
  const first = (st.recipes || []).find(r => state(r) === 'ok') || (st.recipes || [])[0];
  sel = first ? first.id : null;
  NZ.$('#bench').textContent = st.bench?.label || 'Workbench';
  NZ.$('#bench-sub').textContent = st.bench?.sub || '';
  NZ.$('#lvl').textContent = st.level || 0;
  renderTabs(); renderAll();
  clearInterval(ticker); ticker = setInterval(tick, 250);
  NZ.open(app);
}
NZ.on('open', openForge);
NZ.on('inventory', d => { if (!st) return; Object.assign(inv, d || {}); renderList(); renderDetail(); });
NZ.on('queue', d => { if (!st) return; queue = (Array.isArray(d) ? d : (d && d.queue) || []).slice(); renderQueue(); renderQty(); });
NZ.on('close', () => { clearInterval(ticker); NZ.close(app, { notify: false }); });

NZ.preview(() => {
  const now = Date.now();
  openForge({
    bench: { label: 'Weapon bench', sub: 'Sandy Shores · Lot 14 garage' },
    level: 3, slots: 5,
    categories: [
      { id: 'weapons', label: 'Weapons', icon: 'pistol' },
      { id: 'ammo', label: 'Ammo', icon: 'ammo' },
      { id: 'parts', label: 'Parts', icon: 'cog' },
      { id: 'lab', label: 'Lab', icon: 'flask' },
      { id: 'kitchen', label: 'Kitchen', icon: 'pan' },
    ],
    recipes: [
      { id: 'pistol', label: 'Pistol', icon: 'pistol', category: 'weapons', time: 45, amount: 1, chance: 92, level: 2,
        desc: 'Standard 9mm sidearm. Serial filed off, slide hand-fitted on this bench.',
        materials: [{ name: 'steel', label: 'Steel ingot', need: 4, icon: 'ingot' }, { name: 'spring', label: 'Recoil spring', need: 1, icon: 'spring' },
          { name: 'polymer', label: 'Polymer grip', need: 1, icon: 'box' }, { name: 'screws', label: 'Screws', need: 6, icon: 'cog' }] },
      { id: 'smg', label: 'Micro SMG', icon: 'pistol', category: 'weapons', time: 120, amount: 1, chance: 74, level: 4,
        desc: 'Compact, loud and hard to control. Needs a steady hand and a higher skill level.',
        materials: [{ name: 'steel', label: 'Steel ingot', need: 8, icon: 'ingot' }, { name: 'spring', label: 'Recoil spring', need: 2, icon: 'spring' }, { name: 'chipset', label: 'Trigger group', need: 1, icon: 'chip' }] },
      { id: 'ammo9', label: '9mm rounds', icon: 'ammo', category: 'ammo', time: 20, amount: 24, chance: 100, level: 1,
        desc: 'A box of 24 pistol rounds. Fits every 9mm frame in the city.',
        materials: [{ name: 'brass', label: 'Brass casing', need: 24, icon: 'ammo' }, { name: 'gunpowder', label: 'Gunpowder', need: 2, icon: 'powder' }] },
      { id: 'steel', label: 'Steel ingot', icon: 'ingot', category: 'parts', time: 15, amount: 1, chance: 100, level: 1,
        desc: 'Smelt scrap metal from the Rogers yard into a clean bar of steel.',
        materials: [{ name: 'scrap', label: 'Scrap metal', need: 5, icon: 'wrench' }] },
      { id: 'spring', label: 'Recoil spring', icon: 'spring', category: 'parts', time: 12, amount: 2, chance: 95, level: 1,
        desc: 'Wound from a strip of steel wire. Comes out in pairs.',
        materials: [{ name: 'steel', label: 'Steel ingot', need: 1, icon: 'ingot' }] },
      { id: 'lockpick', label: 'Advanced lockpick', icon: 'key', category: 'parts', time: 30, amount: 1, chance: 85, level: 2,
        desc: 'Tension wrench and rake set that survives more than one attempt.',
        materials: [{ name: 'steel', label: 'Steel ingot', need: 1, icon: 'ingot' }, { name: 'screws', label: 'Screws', need: 2, icon: 'cog' }] },
      { id: 'meth', label: 'Crystal batch', icon: 'flask', category: 'lab', time: 180, amount: 10, chance: 68, level: 5,
        desc: 'Grand Senora recipe. Bad air, worse neighbours, high purity if you get it right.',
        materials: [{ name: 'acid', label: 'Hydrochloric acid', need: 2, icon: 'drop' }, { name: 'pseudo', label: 'Pseudoephedrine', need: 5, icon: 'pill' }, { name: 'scale', label: 'Lab scale', need: 1, icon: 'scale' }] },
      { id: 'burger', label: 'Bleeder burger', icon: 'food', category: 'kitchen', time: 8, amount: 1, chance: 100, level: 0,
        desc: 'Grill it, stack it, wrap it. Restores 40 hunger.',
        materials: [{ name: 'bun', label: 'Bun', need: 1, icon: 'food' }, { name: 'patty', label: 'Beef patty', need: 1, icon: 'food' }, { name: 'lettuce', label: 'Lettuce', need: 1, icon: 'leaf' }] },
    ],
    inventory: { steel: 9, spring: 2, polymer: 3, screws: 14, scrap: 22, brass: 30, gunpowder: 1, bun: 4, patty: 2, lettuce: 6, acid: 1, pseudo: 8 },
    queue: [
      { id: 'q1', recipe: 'steel', qty: 2, starts: now - 24000, ends: now + 6000 },
      { id: 'q2', recipe: 'ammo9', qty: 1, starts: now + 6000, ends: now + 26000 },
    ],
  });
});
