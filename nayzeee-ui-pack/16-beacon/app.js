/* 16 · BEACON — dispatch alerts
   The alert stack is always on and needs no NUI focus: Lua reads the keys and sends messages.

   SendNUIMessage({ action = 'alert', data = {
     id = 'LS-2041', code = '10-71', title = 'Shots fired',
     street = 'Grove Street', district = 'Davis',
     priority = 1,                         -- 1 red · 2 amber · 3 teal
     distance = 1240,                      -- metres (or a ready string like '1.2 km')
     units = { '1-ADAM-12', '1-LINCOLN-30' },
     blip = 1,                             -- GTA blip colour id, or 'red' | 'amber' | 'teal' | 'white' | '#hex'
     time = os.time(),                     -- unix seconds; defaults to now
     caller = 'Anonymous', details = 'Multiple shots heard near the basketball court.',  -- optional, shown in the log
   } })                                    -- an id already in the stack updates in place (distance, units…)
   SendNUIMessage({ action = 'cycle',   data = { dir = 1 } })   -- 1 = older (→), -1 = newer (←)
   SendNUIMessage({ action = 'respond', data = { callsign = '2-ADAM-14' } })
                 -- marks the focused alert as responding and posts back 'respond' { id }; callsign optional
   SendNUIMessage({ action = 'hide' })                          -- slide the stack away until the next alert
   SendNUIMessage({ action = 'hide',    data = { id = 'LS-2041' } })  -- drop one alert from the stack
   SendNUIMessage({ action = 'log', data = { open = true, label = 'Mission Row PD', me = '2-ADAM-14', calls = { ... } } })
                 -- call = alert fields + status = 'received' | 'enroute' | 'onscene' | 'closed', mine = true,
                 --        timeline = { { status = 'enroute', time = 1760090000, by = '1-ADAM-12', note = '...' } }
   SendNUIMessage({ action = 'close' })                         -- closes the log (the stack stays)

   Callbacks:
     respond  { id }   -- [G] on the stack (via the message above) or Respond in the log
     waypoint { id }   -- Set waypoint in the log, or [W]
     close             -- the log was closed with ESC / Close: release focus

   Lua keys example:
     RegisterCommand('+beacon_respond', function() SendNUIMessage({ action = 'respond' }) end)
     RegisterKeyMapping('+beacon_respond', 'Respond to dispatch', 'keyboard', 'G')
*/
NZ.addIcons({
  nav: '<path d="M12 3 19.5 20 12 16.2 4.5 20 12 3z"/>',
  siren: '<path d="M7 18v-6a5 5 0 0 1 10 0v6"/><path d="M4.5 18h15v3h-15zM12 2.5V4M4.2 5.2l1.1 1.1M19.8 5.2l-1.1 1.1M2.5 12H4M20 12h1.5"/>',
  route: '<circle cx="6" cy="18" r="2.2"/><circle cx="18" cy="6" r="2.2"/><path d="M8.2 18H15a3 3 0 0 0 0-6H9a3 3 0 0 1 0-6h6.8"/>',
});

const app = NZ.$('#app'), logEl = NZ.$('#log');
const calls = new Map();            // id → call (stack + log share it)
const els = new Map();              // id → stack card element
let order = [];                     // stack ids, newest first
let focusId = null, freshId = null, stackHidden = false;
let me = '', logF = 'all', logQ = '', selId = null, wpFlash = null;
const MAX_VIS = 4, KEEP = 12;
const STEPS = [['received', 'Received'], ['enroute', 'Unit en route'], ['onscene', 'On scene'], ['closed', 'Closed']];
const STEP_I = { received: 0, enroute: 1, onscene: 2, closed: 3 };

/* ── helpers ── */
const pad = n => String(n).padStart(2, '0');
const arr = v => Array.isArray(v) ? v : (v && typeof v === 'object' ? Object.values(v) : []);
const toMs = t => (typeof t === 'number' && isFinite(t)) ? (t < 1e12 ? t * 1000 : t) : null;
const nowS = () => Math.floor(Date.now() / 1000);
function ago(ms, short) {
  const s = Math.max(0, Math.floor((Date.now() - ms) / 1000)), m = Math.floor(s / 60), h = Math.floor(m / 60);
  if (short) return s < 60 ? `${s}s` : m < 60 ? `${m}m` : `${h}h ${pad(m % 60)}m`;
  if (s < 5) return 'Just now';
  if (s < 60) return `${s}s ago`;
  if (m < 10) return `${m}m ${pad(s % 60)}s ago`;
  if (m < 60) return `${m}m ago`;
  return `${h}h ${pad(m % 60)}m ago`;
}
const clock = ms => { const d = new Date(ms); return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`; };
function dist(v) {
  if (v == null || v === '') return '—';
  if (typeof v !== 'number') return NZ.esc(v);
  return v < 1000 ? `${Math.round(v / 10) * 10} m` : `${(v / 1000).toFixed(1)} km`;
}
const BLIP_ID = { 0: 'var(--white)', 1: 'var(--red)', 2: 'var(--teal)', 3: '#4c8dff', 4: 'var(--white)', 5: 'var(--amber)',
  6: 'var(--red)', 25: 'var(--teal)', 38: '#4c8dff', 46: 'var(--amber)', 47: 'var(--amber)', 49: 'var(--red)', 59: 'var(--red)', 69: 'var(--teal)' };
const BLIP_NAME = { red: 'var(--red)', amber: 'var(--amber)', yellow: 'var(--amber)', orange: 'var(--amber)', teal: 'var(--teal)',
  green: 'var(--teal)', white: 'var(--white)', blue: '#4c8dff' };
function blipColor(c) {
  const b = c.blip;
  if (typeof b === 'number') return BLIP_ID[b] || '';
  if (typeof b === 'string') { if (BLIP_NAME[b.toLowerCase()]) return BLIP_NAME[b.toLowerCase()]; if (/^#[0-9a-f]{3,8}$/i.test(b)) return b; }
  return '';
}
const isActive = c => c.status === 'enroute' || c.status === 'onscene';
const unitChips = (c, none) => c.units.length
  ? c.units.map(u => `<span class="cs ${me && u === me ? 'me' : ''}">${NZ.esc(u)}</span>`).join('')
  : `<span class="none">${none}</span>`;

/* ── data ── */
function upsert(d) {
  const id = String(d.id ?? `call-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`);
  const old = calls.get(id);
  const c = Object.assign(old || { status: 'received', units: [], timeline: [], mine: false }, d, { id });
  c.priority = Math.min(3, Math.max(1, parseInt(c.priority, 10) || 2));
  c.units = arr(c.units).map(String);
  c.timeline = arr(c.timeline);
  if (!STEP_I.hasOwnProperty(c.status)) c.status = 'received';
  c.t = toMs(d.time) ?? old?.t ?? Date.now();
  if (!c.timeline.some(e => e.status === 'received')) c.timeline.unshift({ status: 'received', time: Math.floor(c.t / 1000) });
  calls.set(id, c);
  if (calls.size > 120) { // keep memory flat on long sessions
    const oldest = [...calls.values()].filter(x => !order.includes(x.id)).sort((a, b) => a.t - b.t)[0];
    if (oldest) calls.delete(oldest.id);
  }
  return { c, isNew: !old };
}

function onAlert(d) {
  if (!d || typeof d !== 'object') return;
  const { c, isNew } = upsert(d);
  if (isNew || !order.includes(c.id)) {
    order = [c.id, ...order.filter(x => x !== c.id)].slice(0, KEEP);
    focusId = c.id; freshId = c.id; stackHidden = false;
  }
  renderStack();
  if (logOpen()) renderLog();
}

function setStatus(c, status, by, note) {
  if (STEP_I[status] <= STEP_I[c.status] && c.timeline.some(e => e.status === status)) return;
  c.status = status;
  c.timeline.push({ status, time: nowS(), by, note });
}

async function respondTo(id) {
  const c = calls.get(String(id));
  if (!c || c.status === 'closed') return;
  if (c.mine) { setWaypoint(c.id); return; }   // second press: just route again
  {
    c.mine = true;
    if (me && !c.units.includes(me)) c.units.push(me);
    if (c.status === 'received') setStatus(c, 'enroute', me || 'You');
    else c.timeline.push({ status: c.status, time: nowS(), by: me || 'You', note: 'Joined the call' });
  }
  renderStack(); if (logOpen()) renderLog();
  const res = await NZ.post('respond', { id: c.id });
  if (res && typeof res === 'object' && (res.units || res.status)) { upsert({ ...res, id: c.id }); renderStack(); if (logOpen()) renderLog(); }
  if (!NZ.inGame) demoProgress(c);
}

function setWaypoint(id) {
  const c = calls.get(String(id)); if (!c) return;
  NZ.post('waypoint', { id: c.id });
  wpFlash = c.id;
  if (logOpen()) renderLog();
  clearTimeout(setWaypoint.t);
  setWaypoint.t = setTimeout(() => { wpFlash = null; if (logOpen()) renderLog(); }, 2200);
}

/* ── stack ── */
function cardFull(c, pos, total) {
  const blip = blipColor(c);
  return `<i class="stripe"></i>
    <div class="al-top"><span class="code">${NZ.esc(c.code || '10-00')}</span><span class="pri">Priority ${c.priority}</span>
      <span class="ago" data-ago="${NZ.esc(c.id)}"></span><span class="blip"${blip ? ` style="--bc:${NZ.esc(blip)}"` : ''}><i></i></span></div>
    <h3>${NZ.esc(c.title || 'Dispatch call')}</h3>
    <div class="al-loc">${NZ.icon('pin')}<span class="st">${NZ.esc(c.street || 'Unknown street')}</span>${c.district ? `<span class="ds">· ${NZ.esc(c.district)}</span>` : ''}
      <span class="dist">${NZ.icon('nav')}${dist(c.distance)}</span></div>
    <div class="al-units"><span class="ul">Units</span>${unitChips(c, 'No units assigned yet')}</div>
    ${c.mine ? `<div class="al-resp">${NZ.icon('check')}You are responding · waypoint set</div>` : ''}
    <div class="al-keys nz-hints">
      <span><span class="nz-key">G</span>${c.mine ? 'Waypoint' : 'Respond'}</span>
      <span><span class="nz-key">←</span><span class="nz-key">→</span>Cycle</span>
      <span><span class="nz-key">H</span>Hide</span>
      <span class="pos"><b>${pos}</b> / ${total}</span>
    </div>`;
}
function cardMini(c) {
  return `<i class="stripe"></i><span class="code">${NZ.esc(c.code || '10-00')}</span>
    <span class="mt"><b>${NZ.esc(c.title || 'Dispatch call')}</b><span>${NZ.esc(c.street || '')}${c.district ? ` · ${NZ.esc(c.district)}` : ''}</span></span>
    ${c.mine ? NZ.icon('check', 'ok') : ''}<span class="ago" data-ago="${NZ.esc(c.id)}" data-s="1"></span>`;
}

function renderStack() {
  const ids = order.filter(id => calls.has(id));
  order = ids;
  if (!ids.includes(focusId)) focusId = ids[0] || null;
  NZ.$('#stack').classList.toggle('gone', stackHidden || !ids.length || logOpen());
  document.body.classList.toggle('b-logopen', logOpen());

  const fi = Math.max(0, ids.indexOf(focusId));
  const start = fi >= MAX_VIS ? fi - MAX_VIS + 1 : 0;
  const vis = ids.slice(start, start + MAX_VIS);
  const host = NZ.$('#s-list');
  [...host.children].forEach(el => { if (!vis.includes(el.dataset.id)) el.remove(); });
  vis.forEach((id, k) => {
    const c = calls.get(id), focus = id === focusId;
    let el = els.get(id);
    if (!el) {
      el = document.createElement('article');
      el.dataset.id = id;
      el.innerHTML = '<i class="al-echo"></i><div class="al-box"><div class="al-in"></div></div>';
      el.onclick = () => { focusId = id; renderStack(); };   // preview only (no pointer events in game)
      els.set(id, el);
    }
    const isNew = id === freshId;
    if (isNew) {
      freshId = null; el.dataset.new = '1';
      clearTimeout(el._t); el._t = setTimeout(() => { delete el.dataset.new; el.classList.remove('new'); }, 4600);
    }
    el.className = `al p${c.priority} ${focus ? 'focus' : 'mini'}${c.mine ? ' mine' : ''}${el.dataset.new ? ' new' : ''}`;
    const html = focus ? cardFull(c, ids.indexOf(id) + 1, ids.length) : cardMini(c);
    const inner = el.querySelector('.al-in');
    if (inner._sig !== html) { inner.innerHTML = html; inner._sig = html; }
    if (host.children[k] !== el) host.insertBefore(el, host.children[k] || null);
  });
  [...els.keys()].forEach(id => { if (!ids.includes(id)) els.delete(id); });

  const p1 = ids.filter(id => calls.get(id).priority === 1).length;
  NZ.$('#s-sub').textContent = ids.length ? `${ids.length} active call${ids.length === 1 ? '' : 's'}${p1 ? ` · ${p1} priority 1` : ''}` : 'No active calls';
  const more = ids.length - vis.length;
  NZ.$('#s-more').innerHTML = more > 0 ? `${NZ.icon('chev-d')}<b>+${more}</b> more` : '';
  tick();
}

function tick() {
  NZ.$$('[data-ago]').forEach(el => {
    const c = calls.get(el.dataset.ago);
    if (c) el.textContent = ago(c.t, !!el.dataset.s);
  });
}
setInterval(tick, 1000);

function cycle(dir) {
  if (!order.length) return;
  const i = Math.max(0, order.indexOf(focusId));
  focusId = order[(i + (dir < 0 ? -1 : 1) + order.length) % order.length];
  stackHidden = false;
  renderStack();
}
function hide(d) {
  if (d && d.id != null) { order = order.filter(x => x !== String(d.id)); }
  else stackHidden = true;
  renderStack();
}

/* ── dispatch log ── */
const logOpen = () => logEl.classList.contains('nz-open');
const LOG_F = {
  all: () => true,
  p1: c => c.priority === 1,
  mine: c => c.mine,
  active: c => isActive(c),
};
function logList() {
  const q = logQ.toLowerCase();
  return [...calls.values()]
    .filter(c => !q || [c.code, c.title, c.street, c.district, ...c.units].some(v => String(v || '').toLowerCase().includes(q)))
    .sort((a, b) => b.t - a.t);
}
const statusTag = c => `<span class="stt ${c.status}">${STEPS[STEP_I[c.status]][1]}</span>`;

function renderLog() {
  const base = logList(), list = base.filter(LOG_F[logF]);
  NZ.$$('#g-filters button').forEach(b => {
    b.classList.toggle('on', b.dataset.f === logF);
    b.querySelector('span').textContent = base.filter(LOG_F[b.dataset.f]).length;
  });
  const all = [...calls.values()];
  NZ.$('#g-stats').innerHTML = `
    <div><span>Open calls</span><b>${all.filter(c => c.status !== 'closed').length}</b></div>
    <div><span>Priority 1</span><b class="red">${all.filter(c => c.priority === 1 && c.status !== 'closed').length}</b></div>
    <div><span>Units out</span><b class="teal">${new Set(all.filter(isActive).flatMap(c => c.units)).size}</b></div>`;
  NZ.$('#g-sub').textContent = [me ? `Signed in as ${me}` : '', `${all.length} calls this shift`].filter(Boolean).join(' · ');

  if (!list.some(c => c.id === selId)) selId = list[0]?.id ?? null;
  NZ.$('#g-list').innerHTML = list.length ? list.map(c => `
    <button class="c p${c.priority} ${c.id === selId ? 'on' : ''} ${c.status === 'closed' ? 'done' : ''}" data-id="${NZ.esc(c.id)}"><i></i>
      <div class="c-top"><span class="code">${NZ.esc(c.code || '10-00')}</span><b>${NZ.esc(c.title || 'Dispatch call')}</b><span class="ago" data-ago="${NZ.esc(c.id)}" data-s="1"></span></div>
      <div class="c-sub"><span>${NZ.esc(c.street || '')}${c.district ? ` · ${NZ.esc(c.district)}` : ''}</span>${c.mine ? '<span class="stt mine">Mine</span>' : ''}${statusTag(c)}</div>
    </button>`).join('')
    : `<div class="nz-empty">${NZ.icon('radio')}<b>No calls here</b><span>Nothing matches this filter right now.</span></div>`;
  NZ.$$('#g-list .c').forEach(b => b.onclick = () => { selId = b.dataset.id; renderLog(); });
  NZ.$('#g-list .c.on')?.scrollIntoView({ block: 'nearest' });
  renderDetail();
  tick();
}

function renderDetail() {
  const c = calls.get(selId), box = NZ.$('#g-detail');
  if (!c) { box.innerHTML = `<div class="nz-empty">${NZ.icon('radio')}<b>Select a call</b><span>Pick a call on the left to see its timeline.</span></div>`; return; }
  const cur = STEP_I[c.status];
  const steps = STEPS.map(([key, label], i) => {
    const ev = [...c.timeline].reverse().find(e => e.status === key);
    const state = i < cur || (i === cur && key === 'closed') ? 'done' : i === cur ? 'cur' : 'todo';
    const ms = ev ? toMs(ev.time) : null;
    const sub = ev ? [ev.by, ev.note].filter(Boolean).map(NZ.esc).join(' · ') : (state === 'todo' ? 'Waiting' : '');
    return `<div class="stp ${state}${i === STEPS.length - 1 ? ' last' : ''}">
      <span class="dt">${state === 'done' ? NZ.icon('check') : state === 'cur' ? NZ.icon(key === 'received' ? 'bell' : key === 'enroute' ? 'nav' : 'pin') : ''}</span>
      <span class="tx"><b>${label}</b>${sub ? `<small>${sub}</small>` : ''}</span>
      <span class="tm">${ms ? clock(ms) : ''}</span></div>`;
  }).join('');
  const closed = c.status === 'closed';
  box.innerHTML = `<div class="d-scroll nz-scroll">
      <div class="d-head">
        <div class="d-code p${c.priority}"><span>Code</span><b>${NZ.esc(c.code || '10-00')}</b></div>
        <div class="d-t">
          <div class="d-tags"><span class="pchip p${c.priority}">Priority ${c.priority}</span>${statusTag(c)}${c.mine ? '<span class="stt mine">You are responding</span>' : ''}</div>
          <h2>${NZ.esc(c.title || 'Dispatch call')}</h2>
          <div class="d-loc">${NZ.icon('pin')}${NZ.esc(c.street || 'Unknown street')}${c.district ? `<span>· ${NZ.esc(c.district)}</span>` : ''}</div>
        </div>
      </div>
      <div class="d-facts">
        <div><span>Received</span><b data-ago="${NZ.esc(c.id)}"></b><small>${clock(c.t)}</small></div>
        <div><span>Distance</span><b>${dist(c.distance)}</b><small>From your position</small></div>
        <div><span>Caller</span><b>${NZ.esc(c.caller || 'Anonymous')}</b><small>${NZ.esc(c.phone || '911 line')}</small></div>
        <div><span>Units</span><b>${c.units.length}</b><small>${c.units.length ? (isActive(c) ? 'Responding' : 'Attached') : 'None yet'}</small></div>
      </div>
      ${c.details ? `<p class="d-note">${NZ.esc(c.details)}</p>` : ''}
      <div class="d-sec"><span>Responding units</span><div class="d-units">${unitChips(c, 'No units have picked this up yet.')}</div></div>
      <div class="d-sec"><span>Timeline</span><div class="tl">${steps}</div></div>
    </div>
    <div class="d-act">
      ${wpFlash === c.id ? `<span class="note ok">${NZ.icon('check')}Waypoint set on your map</span>` : `<span class="note">${NZ.icon('route')}${dist(c.distance)} away</span>`}
      <button class="nz-btn ghost lg" id="d-wp">${NZ.icon('nav')}Set waypoint</button>
      ${closed ? `<button class="nz-btn line lg" disabled>Call closed</button>`
        : c.mine ? `<button class="nz-btn teal lg mine">${NZ.icon('check')}Responding</button>`
        : `<button class="nz-btn teal lg" id="d-resp">${NZ.icon('siren')}Respond</button>`}
    </div>`;
  NZ.$('#d-wp', box).onclick = () => setWaypoint(c.id);
  const r = NZ.$('#d-resp', box); if (r) r.onclick = () => respondTo(c.id);
}

function openLog(d = {}) {
  arr(d.calls).forEach(x => upsert(x));
  if (d.me) me = String(d.me);
  if (d.label) NZ.$('#g-title').textContent = d.label;
  if (d.open === false) { closeLog(false); return; }
  if (d.select != null) selId = String(d.select);
  else if (!logOpen()) selId = focusId || selId;
  NZ.open(logEl);
  renderLog(); renderStack();
}
function closeLog(notify = true) {
  if (!logOpen()) return;
  logEl.classList.remove('nz-open');   // not NZ.close: the stack stays up, so no "reopen preview" overlay
  if (notify) NZ.post('close');
  renderStack();
}

NZ.$$('#g-filters button').forEach(b => b.onclick = () => { logF = b.dataset.f; renderLog(); });
NZ.$('#g-q').oninput = e => { logQ = e.target.value.trim(); renderLog(); };
NZ.$$('[data-close]').forEach(b => b.onclick = () => closeLog());

/* ── messages ── */
NZ.on('alert', onAlert);
NZ.on('cycle', d => cycle(+(d && d.dir) || 1));
NZ.on('respond', d => { if (d && d.callsign) me = String(d.callsign); respondTo((d && d.id != null) ? d.id : focusId); });
NZ.on('hide', d => hide(d));
NZ.on('log', d => openLog(d || {}));
NZ.on('close', () => closeLog(false));

/* keys: the log has focus so JS reads them; the stack keys come from Lua (browser preview simulates them) */
window.addEventListener('keydown', e => {
  const typing = document.activeElement === NZ.$('#g-q');
  if (logOpen()) {
    if (e.key === 'Escape') { e.preventDefault(); closeLog(); return; }
    if (typing) return;
    const list = logList().filter(LOG_F[logF]), i = list.findIndex(c => c.id === selId);
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      const n = list[Math.min(list.length - 1, Math.max(0, i + (e.key === 'ArrowDown' ? 1 : -1)))];
      if (n) { selId = n.id; renderLog(); }
    } else if (e.key === 'g' || e.key === 'G') { if (selId) respondTo(selId); }
    else if (e.key === 'w' || e.key === 'W') { if (selId) setWaypoint(selId); }
    else if (e.key === '/') { e.preventDefault(); NZ.$('#g-q').focus(); }
    return;
  }
  if (NZ.inGame) return;
  if (e.key === 'ArrowRight') cycle(1);
  else if (e.key === 'ArrowLeft') cycle(-1);
  else if (e.key === 'g' || e.key === 'G') respondTo(focusId);
  else if (e.key === 'h' || e.key === 'H') hide();
  else if (e.key === 'l' || e.key === 'L') openLog({ open: true });
});

NZ.open(app);   // the stack is a HUD layer: always mounted, shows itself when calls arrive
renderStack();

/* ── browser preview: calls arrive every few seconds ── */
let demoProgress = () => {};
NZ.preview(() => {
  if (NZ.preview.ran) return; NZ.preview.ran = true;
  me = '2-ADAM-14';
  const t = nowS();
  const past = [
    { id: 'LS-2031', code: '10-50', title: 'Vehicle collision', street: 'Great Ocean Hwy', district: 'Banham Canyon', priority: 2, distance: 6400,
      units: ['1-ADAM-03', 'MED-12'], caller: 'Rosa Delgado', phone: '555-0182', status: 'closed', time: t - 3400,
      details: 'Two vehicles, one rolled onto its side. Driver trapped but conscious.',
      timeline: [{ status: 'received', time: t - 3400 }, { status: 'enroute', time: t - 3320, by: '1-ADAM-03' }, { status: 'onscene', time: t - 2980, by: '1-ADAM-03' }, { status: 'closed', time: t - 1900, by: '1-ADAM-03', note: 'Patient transported to Pillbox' }] },
    { id: 'LS-2034', code: '10-31', title: 'Burglary in progress', street: 'Mirror Park Blvd', district: 'Mirror Park', priority: 2, distance: 2900,
      units: ['2-ADAM-14', '1-LINCOLN-07'], mine: true, caller: 'Neighbour', status: 'onscene', time: t - 1500,
      details: 'Caller sees two people climbing through a back window of number 14.',
      timeline: [{ status: 'received', time: t - 1500 }, { status: 'enroute', time: t - 1440, by: '2-ADAM-14' }, { status: 'onscene', time: t - 1080, by: '2-ADAM-14', note: 'Perimeter set' }] },
    { id: 'LS-2036', code: '10-15', title: 'Suspicious vehicle', street: 'Elgin Ave', district: 'Downtown', priority: 3, distance: 1800,
      units: [], caller: 'Anonymous', status: 'received', time: t - 820, details: 'Black Baller idling outside the Fleeca for twenty minutes, windows tinted.' },
    { id: 'LS-2037', code: '10-16', title: 'Domestic disturbance', street: 'Forum Drive', district: 'Strawberry', priority: 2, distance: 3300,
      units: ['1-ADAM-21'], caller: 'Tyrell Banks', phone: '555-0144', status: 'enroute', time: t - 540,
      timeline: [{ status: 'received', time: t - 540 }, { status: 'enroute', time: t - 470, by: '1-ADAM-21' }] },
    { id: 'LS-2038', code: '10-53', title: 'Vehicle breakdown', street: 'Route 68', district: 'Harmony', priority: 3, distance: 11800,
      units: [], caller: 'Cole Whitaker', phone: '555-0109', status: 'received', time: t - 260, details: 'Tow requested. Truck blocking the westbound lane.' },
  ];
  past.forEach(c => upsert(c));
  ['LS-2036', 'LS-2037', 'LS-2038'].forEach(id => { order.unshift(id); });
  focusId = order[0];
  renderStack();

  const pool = [
    { code: '10-71', title: 'Shots fired', street: 'Grove Street', district: 'Davis', priority: 1, distance: 1240, units: ['1-ADAM-12', '1-LINCOLN-30'], blip: 1, caller: 'Anonymous', details: 'Multiple shots heard near the basketball court. Possible victim on the ground.' },
    { code: '10-90', title: 'Store alarm', street: 'Innocence Blvd', district: 'Strawberry', priority: 2, distance: 2100, units: [], blip: 5, caller: 'Alarm company', details: '24/7 Supermarket silent alarm triggered at the register.' },
    { code: '10-99', title: 'Officer needs assistance', street: 'Vespucci Blvd', district: 'Little Seoul', priority: 1, distance: 880, units: ['1-ADAM-07'], blip: 1, caller: 'Panic button · 1-ADAM-07', details: 'Panic button pressed. No radio response from the unit.' },
    { code: '10-52', title: 'Person down', street: 'Strawberry Ave', district: 'Pillbox Hill', priority: 2, distance: 1650, units: ['MED-04'], blip: 'amber', caller: 'Jada Brooks', phone: '555-0177', details: 'Unconscious male on the sidewalk, breathing.' },
    { code: '10-80', title: 'Vehicle pursuit', street: 'Del Perro Fwy', district: 'Del Perro', priority: 1, distance: 4300, units: ['1-ADAM-30', 'AIR-1'], blip: 1, caller: '1-ADAM-30', details: 'Red Sultan RS heading east at high speed, plate 46EEK572.' },
    { code: '10-60', title: 'Bank robbery', street: 'Hawick Ave', district: 'Burton', priority: 1, distance: 3100, units: [], blip: 1, caller: 'Fleeca alarm', details: 'Vault alarm at the Hawick Fleeca. Hostages reported.' },
    { code: '10-14', title: 'Noise complaint', street: 'Bay City Ave', district: 'Vespucci', priority: 3, distance: 5200, units: [], blip: 'teal', caller: 'Priya Shah', phone: '555-0121' },
    { code: '10-53', title: 'Tow request', street: 'Senora Way', district: 'Grand Senora', priority: 3, distance: 15400, units: [], blip: 'white', caller: 'Eli Navarro', phone: '555-0163', details: 'Flat tyre and no spare. Customer waiting by the car.' },
  ];
  let n = 2040, k = 0;
  const next = () => { const a = pool[k++ % pool.length]; onAlert({ ...a, id: `LS-${n++}`, units: [...a.units], time: nowS() }); };
  setTimeout(next, 900);
  setInterval(() => { if (!logOpen()) next(); }, 7000);

  // fake the radio moving a call forward after you respond
  demoProgress = c => setTimeout(() => {
    if (c.status === 'enroute') { setStatus(c, 'onscene', me, 'Arrived'); renderStack(); if (logOpen()) renderLog(); }
  }, 6000);

  const demo = document.createElement('div');
  demo.className = 'b-demo';
  demo.innerHTML = `<b>Preview controls · in game Lua sends these</b><div>
    <button class="nz-btn ghost sm" data-d="new">New alert</button>
    <button class="nz-btn ghost sm" data-d="prev">${NZ.icon('chev-l')}Newer</button>
    <button class="nz-btn ghost sm" data-d="next">Older${NZ.icon('chev-r')}</button>
    <button class="nz-btn ghost sm" data-d="resp">Respond · G</button>
    <button class="nz-btn ghost sm" data-d="hide">Hide · H</button>
    <button class="nz-btn teal sm" data-d="log">${NZ.icon('clipboard')}Open dispatch log</button></div>`;
  document.body.appendChild(demo);
  const A = { new: next, prev: () => cycle(-1), next: () => cycle(1), resp: () => respondTo(focusId), hide: () => hide(), log: () => openLog({ open: true, label: 'Mission Row PD' }) };
  demo.querySelectorAll('[data-d]').forEach(b => b.onclick = () => A[b.dataset.d]());
  NZ.$('#g-title').textContent = 'Mission Row PD';
});
