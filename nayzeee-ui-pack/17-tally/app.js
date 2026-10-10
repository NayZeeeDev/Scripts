/* 17 · TALLY
   Hold-to-show scoreboard. Lua sends open on TAB down and close on TAB up,
   so no NUI focus is needed. Give focus (SetNuiFocus(true, true)) only if you
   want players to search or scroll the list with the mouse.

   SendNUIMessage({ action = 'open', data = {
     server = 'NAYZEEE Roleplay', tagline = 'Los Santos · EU 1',  -- tagline optional
     max = 128, queue = 4,                                          -- queue optional
     uptime = 15120,          -- seconds since start, counts up locally
     restartIn = 7980,        -- seconds until restart, counts down locally (nil hides it)
     jobs = { {id = 'police', label = 'Police', icon = 'badge', count = 6}, ... },
     players = { {id = 12, name = 'Marcus Reed', job = 'police', ping = 42,
                  staff = 'Admin',   -- optional: string or true
                  me = true}, ... }  -- optional: pinned + highlighted row
   } })
   SendNUIMessage({ action = 'update', data = { ... } })  -- any subset of the open fields;
       -- players / jobs replace the list. Also: upsert = {player, ...} and remove = {id, ...}
   SendNUIMessage({ action = 'close' })
   player.job may be a jobs[].id (shows the job label and a teal duty marker) or any text;
   player.jobLabel (optional) overrides the shown text, e.g. 'Mechanic · Benny\'s'.
   Callbacks: close (only when the player presses ESC while focused)
*/
NZ.addIcons({
  taxi: '<path d="M5 16H3.5v-4l2-4.5A2 2 0 0 1 7.3 6.5h9.4a2 2 0 0 1 1.8 1l2 4.5v4H19"/><path d="M3.5 12h17M9 16h6M10 3.5h4v3h-4z"/><circle cx="7" cy="16.5" r="1.8"/><circle cx="17" cy="16.5" r="1.8"/>',
  sortd: '<path d="M7 4v16M3.5 16.5 7 20l3.5-3.5M13 6h8M13 11h6M13 16h3"/>',
  sortu: '<path d="M7 20V4M3.5 7.5 7 4l3.5 3.5M13 6h3M13 11h6M13 16h8"/>',
});

const app = NZ.$('#app');
const listEl = NZ.$('#list');
let state = { server: '', tagline: '', max: 0, uptime: 0, restartIn: null, jobs: [], players: [] };
let base = 0;              // performance.now() when uptime/restartIn were last set
let sortKey = 'id', sortDir = 1, query = '';
let ticker = null;

try { const s = JSON.parse(localStorage.getItem('nz-tally-sort') || 'null'); if (s) { sortKey = s.k; sortDir = s.d; } } catch {}

const pad = n => String(Math.floor(n)).padStart(2, '0');
const clock = s => { s = Math.max(0, s); return `${pad(s / 3600)}:${pad(s / 60 % 60)}:${pad(s % 60)}`; };
const jobOf = id => (state.jobs || []).find(j => String(j.id) === String(id));

function pid(id) {
  const s = String(id ?? '');
  if (!/^\d+$/.test(s) || s.length >= 3) return NZ.esc(s);
  return `<i>${'0'.repeat(3 - s.length)}</i>${s}`;
}

function bars(ping) {
  const p = +ping || 0;
  const n = p < 60 ? 4 : p < 100 ? 3 : p < 160 ? 2 : 1;
  const tone = n >= 3 ? '' : n === 2 ? 'amber' : 'red';
  return `<span class="bars ${tone}">${[1, 2, 3, 4].map(i => `<i class="${i <= n ? 'on' : ''}"></i>`).join('')}</span>`;
}

function staffChip(s) {
  if (!s) return '';
  const label = s === true ? 'Staff' : String(s);
  const white = /owner|admin|director/i.test(label);
  return `<span class="nz-chip ${white ? 'white' : ''}">${NZ.esc(label)}</span>`;
}

function row(p) {
  const j = jobOf(p.job);
  const civ = !p.job || /^(unemployed|civilian|none)$/i.test(p.job);
  const raw = String(p.jobLabel || p.job || '');
  const label = p.jobLabel ? raw : j ? j.label : civ ? 'Unemployed' : raw.charAt(0).toUpperCase() + raw.slice(1);
  return `<div class="pl">
    <span class="pid">${pid(p.id)}</span>
    <span class="pn"><b>${NZ.esc(p.name)}</b>${p.me ? '<span class="nz-chip">You</span>' : ''}${staffChip(p.staff)}</span>
    <span class="pj ${j ? 'duty' : civ ? 'civ' : ''}"><span>${NZ.esc(label)}</span></span>
    <span class="pp">${bars(p.ping)}<small>${Math.round(+p.ping || 0)}</small></span>
  </div>`;
}

function renderHead() {
  NZ.$('#server').textContent = state.server || 'Server';
  NZ.$('#tagline').textContent = state.tagline || 'Online players';
  const online = state.count ?? (state.players || []).length;
  const max = state.max || online || 1;
  const pct = Math.min(100, Math.round(online / max * 100));
  NZ.$('#online').textContent = online;
  NZ.$('#max').textContent = state.max || '—';
  NZ.$('#pct').textContent = pct + '%';
  NZ.$('#cap-fill').style.setProperty('--v', pct + '%');
  NZ.$('.cap-bar').classList.toggle('full', pct >= 100);
  const staff = (state.players || []).filter(p => p.staff).length;
  NZ.$('#queue').innerHTML = [
    `<b>${max - online > 0 ? max - online : 0}</b> slots free`,
    state.queue ? `<b>${NZ.esc(state.queue)}</b> in queue` : '',
    staff ? `<b>${staff}</b> staff online` : '',
  ].filter(Boolean).join(' · ');

  NZ.$('#jobs').innerHTML = (state.jobs || []).map(j => {
    const c = +j.count || 0;
    return `<div class="job ${c ? '' : 'zero'}">
      <div class="row">${NZ.icon(j.icon || 'briefcase')}<b>${c}</b></div>
      <span class="lb">${NZ.esc(j.label)}</span>
      <span class="st">${c ? 'On duty' : '<i class="nz-dot red"></i>None on duty'}</span>
    </div>`;
  }).join('');
}

function tick() {
  const el = (performance.now() - base) / 1000;
  NZ.$('#uptime').textContent = clock((+state.uptime || 0) + el);
  const wrap = NZ.$('#restart-wrap');
  if (state.restartIn == null) { wrap.style.display = 'none'; return; }
  wrap.style.display = '';
  const left = (+state.restartIn || 0) - el;
  NZ.$('#restart').textContent = clock(left);
  wrap.className = left <= 60 ? 'hot' : left <= 600 ? 'warn' : '';
}

function renderList(animate) {
  const q = query.trim().toLowerCase();
  const all = state.players || [];
  const me = all.find(p => p.me);
  NZ.$('#me').innerHTML = me ? row(me) : '';

  const list = all.filter(p => !p.me && (!q ||
    String(p.name).toLowerCase().includes(q) || String(p.id) === q || String(p.id).startsWith(q) ||
    String((jobOf(p.job) || {}).label || p.job || '').toLowerCase().includes(q)));
  const cmp = {
    id: (a, b) => (+a.id || 0) - (+b.id || 0),
    name: (a, b) => String(a.name).localeCompare(String(b.name)),
    ping: (a, b) => (+a.ping || 0) - (+b.ping || 0),
  }[sortKey];
  list.sort((a, b) => cmp(a, b) * sortDir);

  listEl.classList.toggle('anim', !!animate);
  listEl.innerHTML = list.length
    ? list.map(row).join('')
    : `<div class="nz-empty">${NZ.icon('search')}<b>No players match “${NZ.esc(query)}”</b><span>Search by name, server ID or job.</span></div>`;
  if (animate) NZ.$$('.pl', listEl).forEach((el, i) => { el.style.animationDelay = Math.min(i, 18) * 16 + 'ms'; });

  NZ.$$('#sort button').forEach(b => {
    const on = b.dataset.k === sortKey;
    b.classList.toggle('on', on);
    b.innerHTML = `${NZ.esc(b.dataset.k === 'id' ? 'ID' : b.dataset.k === 'name' ? 'Name' : 'Ping')}${NZ.icon(sortDir > 0 ? 'sortu' : 'sortd')}`;
  });
}

function setTimes(d) {
  if ('uptime' in d || 'restartIn' in d) {
    // rebase both counters so they keep ticking from the new values
    const el = (performance.now() - base) / 1000;
    if (!('uptime' in d)) d.uptime = (+state.uptime || 0) + el;
    if (!('restartIn' in d) && state.restartIn != null) d.restartIn = state.restartIn - el;
    base = performance.now();
  }
}

function openUI(d) {
  d = d || {};
  base = performance.now();
  state = Object.assign({ jobs: [], players: [] }, d);
  query = '';
  NZ.$('#q').value = '';
  renderHead(); renderList(true); tick();
  clearInterval(ticker); ticker = setInterval(tick, 1000);
  NZ.open(app);
  listEl.scrollTop = 0;
}

function updateUI(d) {
  if (!d) return;
  setTimes(d);
  const { upsert, remove, ...rest } = d;
  Object.assign(state, rest);
  if (upsert) (Array.isArray(upsert) ? upsert : [upsert]).forEach(p => {
    const i = state.players.findIndex(x => String(x.id) === String(p.id));
    i >= 0 ? Object.assign(state.players[i], p) : state.players.push(p);
  });
  if (remove) { const ids = (Array.isArray(remove) ? remove : [remove]).map(String); state.players = state.players.filter(p => !ids.includes(String(p.id))); }
  renderHead();
  if (app.classList.contains('nz-open')) { renderList(false); tick(); }
}

function closeUI(notify) {
  clearInterval(ticker); ticker = null;
  NZ.close(app, { notify });
}

NZ.$('#q').addEventListener('input', e => { query = e.target.value; renderList(true); });
NZ.$('#sort').addEventListener('click', e => {
  const b = e.target.closest('button'); if (!b) return;
  if (b.dataset.k === sortKey) sortDir = -sortDir; else { sortKey = b.dataset.k; sortDir = 1; }
  try { localStorage.setItem('nz-tally-sort', JSON.stringify({ k: sortKey, d: sortDir })); } catch {}
  renderList(true);
});
window.addEventListener('keydown', e => {
  if (!app.classList.contains('nz-open')) return;
  if (e.key === 'Escape') { e.preventDefault(); closeUI(true); }
  else if (e.key === '/' && document.activeElement !== NZ.$('#q')) { e.preventDefault(); NZ.$('#q').focus(); }
});

NZ.on('open', openUI);
NZ.on('update', updateUI);
NZ.on('close', () => closeUI(false));

/* ── browser preview ── */
NZ.preview(() => {
  const first = ['Marcus', 'Elena', 'Tyrell', 'Sofia', 'Darnell', 'Mia', 'Jamal', 'Ava', 'Hector', 'Lena', 'Andre', 'Chloe', 'Viktor', 'Nadia', 'Omar', 'Rosa', 'Tommy', 'Kenji', 'Isla', 'Luis', 'Grace', 'Rico', 'Dana', 'Felix'];
  const last = ['Reed', 'Vasquez', 'Brooks', 'Moretti', 'King', 'Chen', 'Hayes', 'Russo', 'Delgado', 'Novak', 'Price', 'Walsh', 'Ortega', 'Bishop', 'Kowalski', 'Santos', 'Grant', 'Ito', 'Mercer', 'Fontaine'];
  const jobs = ['police', 'police', 'ems', 'mechanic', 'taxi', 'unemployed', 'unemployed', 'unemployed', 'Burger Shot', 'Bean Machine', 'Trucker', 'Weazel News', 'unemployed', 'Lawyer'];
  const players = [];
  let seed = 7;
  const rnd = n => { seed = (seed * 9301 + 49297) % 233280; return Math.floor(seed / 233280 * n); };
  const ids = new Set();
  for (let i = 0; i < 47; i++) {
    let id; do { id = 1 + rnd(140); } while (ids.has(id)); ids.add(id);
    const job = jobs[rnd(jobs.length)];
    players.push({ id, name: `${first[rnd(first.length)]} ${last[rnd(last.length)]}`, job: job === 'mechanic' && i > 20 ? 'Trucker' : job, ping: 18 + rnd(i % 9 === 0 ? 220 : 90) });
  }
  players[2].staff = 'Admin'; players[2].job = 'unemployed';
  players[9].staff = 'Moderator';
  players[15].staff = 'Support';
  players.push({ id: 23, name: 'Nayzeee', job: 'mechanic', ping: 31, me: true, staff: 'Owner' });
  openUI({
    server: 'NAYZEEE Roleplay', tagline: 'Los Santos · EU 1 · Whitelist',
    max: 128, queue: 3, uptime: 4 * 3600 + 12 * 60 + 9, restartIn: 2 * 3600 + 14 * 60 + 33,
    jobs: [
      { id: 'police', label: 'Police', icon: 'badge', count: players.filter(p => p.job === 'police').length },
      { id: 'ems', label: 'EMS', icon: 'medkit', count: players.filter(p => p.job === 'ems').length },
      { id: 'mechanic', label: 'Mechanic', icon: 'wrench', count: players.filter(p => p.job === 'mechanic').length },
      { id: 'taxi', label: 'Taxi', icon: 'taxi', count: players.filter(p => p.job === 'taxi').length },
      { id: 'realestate', label: 'Real estate', icon: 'home', count: 0 },
      { id: 'doj', label: 'Judge', icon: 'briefcase', count: 0 },
    ],
    players,
  });
});
