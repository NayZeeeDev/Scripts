/* 20 · ARRIVAL — loading screen
   fxmanifest.lua:
     loadscreen 'html/20-arrival/index.html'
     loadscreen_manual_shutdown 'yes'   -- optional: keep it up until your client calls ShutdownLoadingScreenNui()
     loadscreen_cursor 'yes'            -- optional: lets players click the music / social buttons
     files { 'html/core/nz-core.css', 'html/core/nz-core.js', 'html/20-arrival/*' }

   Loadscreens do not get SendNUIMessage. The game posts its own window messages,
   handled directly below (e.data.eventName):
     loadProgress           { loadFraction = 0..1 }
     startInitFunctionOrder { type, order, count }   -- INIT_CORE / INIT_BEFORE_MAP_LOADED / INIT_AFTER_MAP_LOADED / INIT_SESSION
     initFunctionInvoking   { type, name, idx }
     startDataFileEntries   { count }
     onDataFileEntry        { name, isNew }
     performMapLoadFunction { idx }
     onLogLine              { message }

   Server config (optional) via the connect handover, read from window.nuiHandoverData:
     AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
       deferrals.defer()
       deferrals.handover({
         name = 'Vespucci Roleplay', tagline = 'A living Los Santos.',
         facts   = { { label = 'Slots', value = '128' } },
         tips    = { 'Press <b>F1</b> to open your phone.' },        -- <b> is the only tag kept
         updates = { { version = 'v2.4', title = 'Summer update', date = 'Oct 08', items = { 'New dealership', 'fix:Garage spawn' } } },
         staff   = { { name = 'Nayzeee', role = 'Owner', online = true, lead = true } },
         socials = { discord = 'discord.gg/vespucci', website = 'vespucci-rp.com', store = 'store.vespucci-rp.com' },
         music   = 'Lobby theme',                                      -- track label shown on the button
       })
       deferrals.done()
     end)

   From a client script while loadscreen_manual_shutdown keeps it open:
     SendLoadingScreenMessage(json.encode({ action = 'step', data = { label = 'Loading your character', progress = 0.96 } }))
     SendLoadingScreenMessage(json.encode({ action = 'config', data = { tagline = '...' } }))
     ShutdownLoadingScreenNui()

   Callbacks: none (a loadscreen has no NUI callbacks).
   Music: drop music.mp3 next to index.html and uncomment the <source> in <audio id="music">.
*/
NZ.addIcons({
  'arrow-ur': '<path d="M7 17 17 7M8 7h9v9"/>',
});

const app = NZ.$('#app');
const audio = NZ.$('#music');
const SEGMENTS = 60;
const TIP_MS = 6000;

const DEFAULTS = {
  name: 'NAYZEEE Roleplay',
  tagline: 'Serious roleplay on a living Los Santos.',
  facts: [],
  tips: ['Take your time — the city will be waiting when you arrive.'],
  updates: [],
  staff: [],
  socials: {},
  music: 'Lobby theme',
};
let cfg = { ...DEFAULTS };

/* ═════════ render ═════════ */
// tips may contain <b>; everything else is escaped
const richTip = s => NZ.esc(s).replace(/&lt;(\/?)b&gt;/g, '<$1b>');

function nameHTML(n) {
  // last word in teal when the name has more than one word
  const parts = NZ.esc(n).split(' ');
  if (parts.length < 2) return parts.join(' ');
  const last = parts.pop();
  return `${parts.join(' ')} <em>${last}</em>`;
}

function renderConfig() {
  NZ.$('#name').innerHTML = nameHTML(cfg.name);
  NZ.$('#top-name').textContent = cfg.name;
  NZ.$('#tagline').textContent = cfg.tagline || '';
  document.title = `${cfg.name} · Loading`;

  NZ.$('#facts').innerHTML = (cfg.facts || []).slice(0, 4).map(f =>
    `<div class="fact"><b>${NZ.esc(f.value)}</b><span>${NZ.esc(f.label)}</span></div>`).join('');

  const s = cfg.socials || {};
  const links = [['discord', 'Discord'], ['website', 'Website'], ['store', 'Store']].filter(([k]) => s[k]);
  NZ.$('#socials').innerHTML = links.map(([k, label]) =>
    `<button class="soc" data-url="${NZ.esc(s[k])}"><b>${label}${NZ.icon('arrow-ur')}</b><small>${NZ.esc(String(s[k]).replace(/^https?:\/\//, ''))}</small></button>`).join('') +
    (links.length ? '<i class="sep"></i>' : '');
  NZ.$$('.soc').forEach(b => b.onclick = () => openLink(b.dataset.url));

  const ups = cfg.updates || [];
  NZ.$('#up-ver').textContent = ups[0] ? ups[0].version : 'Live';
  NZ.$('.up-card').style.display = ups.length ? '' : 'none';
  NZ.$('#updates').innerHTML = ups.map(u => `<div class="up">
      <div class="up-h"><span class="nz-chip ${u === ups[0] ? '' : 'white'}">${NZ.esc(u.version)}</span><b>${NZ.esc(u.title)}</b><small>${NZ.esc(u.date || '')}</small></div>
      <ul>${(u.items || []).map(it => {
        const m = String(it).match(/^(fix|rem):\s*/);
        return `<li class="${m ? m[1] : ''}">${NZ.esc(m ? String(it).slice(m[0].length) : it)}</li>`;
      }).join('')}</ul></div>`).join('');

  const staff = cfg.staff || [];
  NZ.$('.staff-card').style.display = staff.length ? '' : 'none';
  NZ.$('#staff-count').textContent = staff.length ? `${staff.filter(m => m.online).length} online` : '';
  NZ.$('#staff').innerHTML = staff.slice(0, 8).map(m => `<div class="member">
      <div class="nz-av ${m.lead ? 'lead' : ''}">${NZ.esc(NZ.initials(m.name))}</div>
      <div><b>${NZ.esc(m.name)}</b><span>${m.online ? '<i class="nz-dot"></i>' : '<i class="nz-dot off"></i>'}${NZ.esc(m.role || '')}</span></div>
    </div>`).join('');

  NZ.$('#music-track').textContent = cfg.music || 'Lobby theme';
  tipIndex = 0; renderTip(false);
  requestAnimationFrame(clipUpdates);
}

function clipUpdates() {
  const u = NZ.$('#updates');
  u.classList.toggle('clip', u.scrollHeight > u.clientHeight + 2);
}
addEventListener('resize', clipUpdates);

function openLink(url) {
  if (!url) return;
  const full = /^https?:\/\//.test(url) ? url : 'https://' + url;
  if (typeof window.invokeNative === 'function') window.invokeNative('openUrl', full);
  else window.open(full, '_blank');
}

/* ── tips ── */
let tipIndex = 0, tipTimer = null;
function renderTip(animate = true) {
  const tips = cfg.tips && cfg.tips.length ? cfg.tips : DEFAULTS.tips;
  tipIndex = (tipIndex + tips.length) % tips.length;
  const el = NZ.$('#tip');
  const put = () => {
    el.innerHTML = richTip(tips[tipIndex]);
    el.classList.remove('swap');
    NZ.$('#tip-count').textContent = `${String(tipIndex + 1).padStart(2, '0')} / ${String(tips.length).padStart(2, '0')}`;
    NZ.$('#tip-dots').innerHTML = tips.map((_, i) => `<i class="${i === tipIndex ? 'on' : ''}"></i>`).join('');
    const t = NZ.$('#tip-timer');
    t.style.setProperty('--tip-ms', TIP_MS + 'ms');
    t.classList.remove('run'); void t.offsetWidth; t.classList.add('run');
  };
  if (animate) { el.classList.add('swap'); setTimeout(put, 420); } else put();
  clearTimeout(tipTimer);
  tipTimer = setTimeout(() => { tipIndex++; renderTip(); }, TIP_MS);
}

/* ── music (UI works without a file) ── */
let musicOn = false;
function setMusic(on) {
  musicOn = on;
  NZ.$('#music-btn').classList.toggle('on', on);
  NZ.$('#music-state').textContent = on ? 'Music on' : 'Music off';
  const hasSrc = audio.querySelector('source') || audio.getAttribute('src');
  if (!hasSrc) return;
  if (on) { audio.volume = 0.35; audio.play().catch(() => {}); } else audio.pause();
}
NZ.$('#music-btn').onclick = () => setMusic(!musicOn);

window.addEventListener('keydown', e => {
  if (e.key === 'm' || e.key === 'M') setMusic(!musicOn);
  else if (e.key === ' ') { tipIndex++; renderTip(); e.preventDefault(); }
});

/* ═════════ progress ═════════ */
const PHASES = {
  INIT_CORE:              { n: 1, label: 'Starting the game engine',  from: 0,    to: 0.06 },
  INIT_BEFORE_MAP_LOADED: { n: 2, label: 'Initialising game systems', from: 0.06, to: 0.22 },
  DATA_FILES:             { n: 3, label: 'Loading data files',        from: 0.22, to: 0.48 },
  MAP:                    { n: 4, label: 'Loading map data',          from: 0.48, to: 0.74 },
  INIT_AFTER_MAP_LOADED:  { n: 5, label: 'Initialising scripts',      from: 0.74, to: 0.93 },
  INIT_SESSION:           { n: 6, label: 'Joining the session',       from: 0.93, to: 1 },
};
let target = 0, shown = 0, phase = null, counts = {}, dataIdx = 0, startedAt = Date.now(), ready = false;

function buildBar() {
  const bar = NZ.$('#bar');
  bar.style.setProperty('--n', SEGMENTS);
  bar.innerHTML = Array.from({ length: SEGMENTS }, (_, i) => `<span class="seg" style="--i:${i}"><i></i></span>`).join('');
}

function setPhase(key, label) {
  const p = PHASES[key];
  if (!p) return;
  if (phase && PHASES[phase].n > p.n) return; // never step backwards
  phase = key;
  NZ.$('#phase').textContent = `Phase ${p.n} of 6`;
  setStep(label || p.label);
  bump(p.from);
}
function setStep(label) {
  const el = NZ.$('#step');
  if (el.textContent === label) return;
  el.classList.add('swap');
  setTimeout(() => { el.textContent = label; el.classList.remove('swap'); }, 200);
}
function setLog(msg) { if (msg) NZ.$('#log').textContent = String(msg).trim().slice(0, 160); }
function bump(v) { target = Math.max(target, Math.min(1, v)); }
function within(key, frac) { const p = PHASES[key]; if (p) bump(p.from + (p.to - p.from) * Math.min(1, frac)); }

const EVENTS = {
  startInitFunctionOrder(d) { counts[d.type] = d.count || 1; setPhase(d.type); },
  initFunctionInvoking(d) {
    setPhase(d.type);
    within(d.type, (d.idx + 1) / (counts[d.type] || 1));
    if (d.name) setLog(`Running ${d.name}`);
  },
  startDataFileEntries(d) { counts.DATA_FILES = d.count || 1; dataIdx = 0; setPhase('DATA_FILES'); },
  onDataFileEntry(d) { dataIdx++; within('DATA_FILES', dataIdx / (counts.DATA_FILES || 1)); if (d.name) setLog(`Loading ${d.name}`); },
  performMapLoadFunction() { setPhase('MAP'); },
  loadProgress(d) {
    const f = Number(d.loadFraction) || 0;
    bump(f);
    if (phase === 'MAP') within('MAP', f);
  },
  onLogLine(d) { setLog(d.message); },
};
window.addEventListener('message', e => {
  const d = e.data;
  if (d && typeof d === 'object' && d.eventName && EVENTS[d.eventName]) EVENTS[d.eventName](d);
});

// SendLoadingScreenMessage(json.encode({ action = ..., data = ... })) arrives through the core bridge
NZ.on('config', d => { cfg = { ...cfg, ...(d || {}) }; renderConfig(); });
NZ.on('step', d => { if (d.label) setStep(d.label); if (typeof d.progress === 'number') bump(d.progress); if (d.log) setLog(d.log); });

function frame() {
  shown += (target - shown) * 0.08;
  if (target - shown < 0.0005) shown = target;
  const pct = Math.floor(shown * 100);
  NZ.$('#pct').textContent = pct;
  const filled = shown * SEGMENTS;
  NZ.$$('#bar .seg').forEach((s, i) => {
    const f = Math.max(0, Math.min(1, filled - i));
    s.classList.toggle('full', f >= 1);
    s.classList.toggle('lead', f > 0 && f < 1);
    s.firstChild.style.setProperty('--f', f.toFixed(3));
  });
  if (shown >= 0.999 && !ready) {
    ready = true;
    NZ.$('#bar').classList.add('done');
    NZ.$('#phase').textContent = 'Ready';
    setStep('Spawning you in');
    NZ.$('#kicker').textContent = 'Welcome to';
    NZ.$('#top-sub').textContent = 'Connected';
  }
  requestAnimationFrame(frame);
}

setInterval(() => {
  const s = Math.floor((Date.now() - startedAt) / 1000);
  NZ.$('#elapsed').textContent = `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
}, 1000);

function resetProgress() {
  target = 0; shown = 0; phase = null; counts = {}; dataIdx = 0; ready = false; startedAt = Date.now();
  NZ.$('#bar').classList.remove('done');
  NZ.$('#phase').textContent = 'Phase 1 of 6';
  NZ.$('#step').textContent = 'Preparing';
  NZ.$('#log').textContent = 'Waiting for the game';
  NZ.$('#kicker').textContent = 'You are joining';
  NZ.$('#top-sub').textContent = 'Connecting';
}

/* ═════════ boot: visible immediately, never gated on an open message ═════════ */
cfg = { ...DEFAULTS, ...(window.nuiHandoverData || {}) };
buildBar();
renderConfig();
NZ.open(app);
requestAnimationFrame(frame);

/* ═════════ preview: replay a full join sequence through the same handler ═════════ */
NZ.preview(() => {
  cfg = {
    ...cfg,
    name: 'Vespucci Roleplay',
    tagline: 'A living, breathing Los Santos. Hand-built jobs, a real economy and a community that shows up every night.',
    facts: [{ label: 'Player slots', value: '128' }, { label: 'Whitelisted jobs', value: '42' }, { label: 'Server region', value: 'EU West' }, { label: 'Since', value: '2021' }],
    tips: [
      'Press <b>F1</b> to open your phone. Bank transfers, garage and messages all live there.',
      'Fleeca ATMs are on almost every block. Your first <b>$5,000</b> in the bank is insured.',
      'Hold <b>Left Alt</b> to look at people, doors and vehicles you can interact with.',
      'Lost your car? Any public garage can bring it back for a small towing fee.',
      'Read the rules on our Discord before you take your first job. Staff are happy to help.',
      'Mechanics at <b>Benny’s</b> pay the best rate for repairs on Strawberry Ave.',
    ],
    updates: [
      { version: 'v2.4', title: 'Vinewood nights update', date: 'Oct 08', items: ['Nightclub ownership with staff and stock', 'New Fleeca ATM and bank counter UI', 'fix:Garage vehicles spawning inside walls'] },
      { version: 'v2.3', title: 'Emergency services', date: 'Sep 21', items: ['Pillbox triage and patient charts', 'fix:Radio channels resetting on relog', 'rem:Old MDT replaced with the new console'] },
      { version: 'v2.2', title: 'Economy pass', date: 'Sep 02', items: ['Dynamic fuel and grocery prices', 'Business accounts with shared cards'] },
    ],
    staff: [
      { name: 'Nayzeee', role: 'Owner', online: true, lead: true },
      { name: 'Marisol Vega', role: 'Head admin', online: true },
      { name: 'Dex Holloway', role: 'Developer', online: true },
      { name: 'Priya Okafor', role: 'Moderator', online: false },
      { name: 'Tommy Ruiz', role: 'Moderator', online: true },
      { name: 'Lena Brandt', role: 'Support', online: false },
    ],
    socials: { discord: 'discord.gg/vespucci', website: 'vespucci-rp.com', store: 'store.vespucci-rp.com' },
    music: 'Midnight on Del Perro',
  };
  renderConfig();

  const files = ['gta5.meta', 'vehicles.meta', 'carcols.meta', 'handling.meta', 'peds.ymt', 'weapons.meta', 'popgroups.ymt', 'mapzones.meta', 'vinewood_props.ytyp', 'legion_square.ymap'];
  const scripts = ['nz-core', 'nz-garage', 'nz-banking', 'nz-phone', 'nz-hud', 'nz-inventory', 'nz-jobs', 'nz-dealership', 'nz-mdt', 'nz-ems', 'nz-housing', 'nz-clothing'];
  const post = d => window.postMessage(d, '*');
  const seq = [];
  const init = (type, names) => {
    seq.push({ eventName: 'startInitFunctionOrder', type, order: 1, count: names.length });
    names.forEach((n, idx) => seq.push({ eventName: 'initFunctionInvoking', type, name: n, idx }));
  };
  init('INIT_CORE', ['rage::fwConfigManager', 'CStreaming', 'CGameWorld', 'CScaleformMgr']);
  init('INIT_BEFORE_MAP_LOADED', ['CPopCycle', 'CVehicleModelInfo', 'CWeaponManager', 'CTaskClassInfo', 'CPedPopulation', 'CAudio']);
  seq.push({ eventName: 'startDataFileEntries', count: files.length });
  files.forEach(f => seq.push({ eventName: 'onDataFileEntry', name: f, isNew: true }));
  seq.push({ eventName: 'performMapLoadFunction', idx: 1 });
  for (let i = 1; i <= 14; i++) seq.push({ eventName: 'loadProgress', loadFraction: 0.48 + i * 0.018 });
  seq.push({ eventName: 'onLogLine', message: 'Map streaming complete' });
  init('INIT_AFTER_MAP_LOADED', scripts);
  init('INIT_SESSION', ['CNetwork', 'CPlayerSync', 'CSessionJoin']);
  seq.push({ eventName: 'loadProgress', loadFraction: 1 });

  let i = 0;
  const play = () => {
    if (i < seq.length) { post(seq[i++]); setTimeout(play, 260 + Math.random() * 260); }
    else setTimeout(() => { i = 0; resetProgress(); play(); }, 4200);
  };
  setTimeout(play, 600);
});
