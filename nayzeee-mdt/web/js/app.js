/* ═══════════════════════════════════════════════════════════════════════════
   NAYZEEE MDT — TABLET UI
   Tablet OS (lock screen, home, windows, taskbar) wrapped around the MDT apps.
   ═══════════════════════════════════════════════════════════════════════════ */

const IN_GAME = typeof GetParentResourceName === 'function';
const RES = IN_GAME ? GetParentResourceName() : 'nayzeee-mdt';

const $ = (sel, root) => (root || document).querySelector(sel);
const $$ = (sel, root) => Array.from((root || document).querySelectorAll(sel));

const DEFAULT_SETTINGS = {
  wallpaper: null,        // id from config.tablet.wallpapers
  scale: 1,               // tablet zoom
  lockAnimation: true,    // type the password on the lock screen
  bootConsole: true,      // show the command prompt after unlocking
  sounds: true,           // dispatch tones in game (read by the client)
  widgetAuto: true,       // pop the HUD card on a new call (read by the client)
  notifications: true     // tablet notifications for live events
};

const S = {
  boot: null,
  me: null,
  perms: {},
  cfg: {},
  page: null,             // app on screen
  open: [],               // apps pinned to the taskbar
  windowUp: false,
  visible: false,
  unlocked: false,
  booted: false,
  dash: null,
  board: { calls: [], officers: [], selected: null, includeClosed: false },
  panics: {},
  list: {},
  draft: null,
  calc: [],
  loc: null,
  settings: Object.assign({}, DEFAULT_SETTINGS),
  notes: [],
  noteSel: null,
  map: { scale: 1, x: 0, y: 0, min: 1, max: 6, style: null, fresh: true },
  card: { calls: [], panics: [], index: 0, keys: null, me: null, pos: null },
  photoReady: false,
  photoReason: null,
  timers: {},
  modalSeq: 0
};

/* ── bridge ──────────────────────────────────────────────────────────────── */
async function post(name, ...args) {
  if (!IN_GAME) return window.MDT_PREVIEW ? window.MDT_PREVIEW.request(name, args) : { ok: false, msg: 'Preview mode.' };
  try {
    const res = await fetch(`https://${RES}/request`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      // `n` keeps nil arguments in place when Lua unpacks the list
      body: JSON.stringify({ name, args, n: args.length })
    });
    return await res.json();
  } catch (e) {
    return { ok: false, msg: 'The tablet lost its connection.' };
  }
}

async function raw(endpoint, body) {
  if (!IN_GAME) return window.MDT_PREVIEW ? window.MDT_PREVIEW.raw(endpoint, body) : null;
  try {
    const res = await fetch(`https://${RES}/${endpoint}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(body || {})
    });
    return await res.json();
  } catch (e) { return null; }
}

/* ── helpers ─────────────────────────────────────────────────────────────── */
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const cur = () => (S.cfg.currency || '$');
const money = (n) => cur() + Math.round(Number(n) || 0).toLocaleString('en-US');
const initials = (name) => String(name || '').trim().split(/\s+/).slice(0, 2).map(w => w[0] || '').join('').toUpperCase() || '—';
const can = (p) => S.perms[p] === true;
const plural = (n, word, many) => `${n} ${n === 1 ? word : (many || word + 's')}`;
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const cap = (s) => String(s || '').charAt(0).toUpperCase() + String(s || '').slice(1);

function ago(seconds) {
  seconds = Math.max(0, Math.floor(seconds || 0));
  if (seconds < 60) return `${seconds}s ago`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
  return `${Math.floor(seconds / 86400)}d ago`;
}

function distance(x, y) {
  if (!S.loc || x == null || y == null) return null;
  const d = Math.hypot((S.loc.x || 0) - x, (S.loc.y || 0) - y);
  return d >= 1000 ? `${(d / 1000).toFixed(1)} km` : `${Math.round(d)} m`;
}

const callType = (id) => (S.cfg.callTypes || []).find(t => t.id === id) || null;
const charge = (id) => (S.cfg.charges || []).find(c => c.id === id) || null;
const priorityClass = (p) => p === 1 ? 'p1' : p === 2 ? 'p2' : 'p3';
const priorityTone = (p) => p === 1 ? 'red' : p === 2 ? 'amber' : 'teal';
const toneChip = (t) => t === 'red' ? 'red' : t === 'amber' ? 'amber' : t === 'off' ? 'off' : '';
const statusInfo = (id) => (S.cfg.unitStatus || []).find(s => s.id === id) || { id, label: cap(id || 'available'), tone: 'teal' };

const fa = (name, extra) => `<i class="fa-solid fa-${name}${extra ? ' ' + extra : ''}"></i>`;

// config icon names → Font Awesome
const ICON_NAMES = {
  shield: 'shield-halved', cash: 'sack-dollar', car: 'car', warn: 'triangle-exclamation', speaker: 'bullhorn',
  house: 'house', user: 'user', cross: 'kit-medical', alert: 'tower-broadcast', flag: 'flag', pin: 'location-dot',
  file: 'file-lines', box: 'box-archive', flask: 'flask', screen: 'display', phone: 'phone', cal: 'calendar',
  plus: 'plus', minus: 'minus', x: 'xmark', check: 'check', chev: 'chevron-right', refresh: 'rotate-right',
  route: 'route', pen: 'pen', trash: 'trash', lock: 'lock', none: 'inbox', bell: 'bell', badge: 'id-badge',
  cam: 'video', clock: 'clock', ext: 'arrow-up-right-from-square', gun: 'gun', fire: 'fire', link: 'link',
  fingerprint: 'fingerprint', dna: 'dna', hand: 'hand', radio: 'walkie-talkie', gavel: 'gavel', map: 'map-location-dot',
  users: 'users', copy: 'copy', note: 'note-sticky', star: 'star', unlock: 'unlock', eye: 'eye', search: 'magnifying-glass'
};
const ICON = {};
Object.keys(ICON_NAMES).forEach(k => { ICON[k] = fa(ICON_NAMES[k]); });
const icon = (name) => ICON[name] || fa(name || 'circle');
const chev = () => fa('chevron-right', 'chev');

const EV_ICON = { weapon: 'shield', narcotics: 'flask', digital: 'screen', physical: 'box',
                  biological: 'dna', vehicle: 'car', currency: 'cash', document: 'file' };

/* ═══════════════════════════════════════════════════════════════════════════
   NOTIFICATIONS
   ═══════════════════════════════════════════════════════════════════════════ */
function notify(title, body, kind, life) {
  const wrap = $('#notifications');
  if (!wrap || !S.visible) return;
  const bad = kind === true || kind === 'err';
  const warn = kind === 'warn';
  life = life || (bad ? 5000 : 4000);

  const el = document.createElement('div');
  el.className = 'notification' + (bad ? ' err' : warn ? ' warn' : '');
  el.style.setProperty('--life', life + 'ms');
  el.innerHTML = `
    <div class="n-icon">${bad ? fa('triangle-exclamation') : warn ? fa('bell') : fa('check')}</div>
    <div>
      <div class="notification-title">${esc(title)}</div>
      ${body ? `<div class="notification-message">${esc(body)}</div>` : ''}
    </div>`;
  el.addEventListener('click', () => el.remove());
  wrap.appendChild(el);
  while (wrap.children.length > 5) wrap.firstElementChild.remove();

  setTimeout(() => {
    el.classList.add('out');
    setTimeout(() => el.remove(), 300);
  }, life);
}

function reply(res, fallback) {
  if (!res) { notify('Not completed', fallback || 'The tablet did not respond.', true); return false; }
  if (res.ok) { if (res.msg) notify('Done', res.msg); return true; }
  notify('Not completed', res.msg || fallback || 'That did not go through.', true);
  return false;
}

/* ═══════════════════════════════════════════════════════════════════════════
   MODALS — small windows stacked on top of the app
   ═══════════════════════════════════════════════════════════════════════════ */
let modalConfirm = null;
const modalStack = [];
const veilUp = () => $('#veil').classList.contains('up');

function openModal(o) {
  const veil = $('#veil');

  if (o.replace) {
    // keep the stack, swap the content in place (skeleton → loaded record)
  } else if (o.child && veilUp()) {
    modalStack.push({ html: veil.innerHTML, confirm: modalConfirm });
  } else {
    modalStack.length = 0;
  }

  S.modalSeq += 1;
  veil.innerHTML = `
    <div class="modal ${o.wide || ''}" data-hasconfirm="${o.confirm ? 1 : 0}">
      <div class="modal-h">
        ${fa(o.icon || 'window-maximize')}
        <h4>${esc(o.title)}</h4>
        <div class="window-controls">
          <button class="window-btn close" data-modal="cancel" title="Close">${fa('times')}</button>
        </div>
      </div>
      <div class="modal-b">
        ${o.lede ? `<p class="lede">${esc(o.lede)}</p>` : ''}
        ${o.body || ''}
      </div>
      ${o.noFooter ? '' : `<div class="modal-f">
        ${o.extra || ''}
        <button class="btn-line" data-modal="cancel">${esc(o.cancel || (o.confirm ? 'Cancel' : 'Close'))}</button>
        ${o.confirm ? `<button class="${o.danger ? 'btn-red' : 'btn-teal solid'}" data-modal="confirm">${esc(o.confirm)}</button>` : ''}
      </div>`}
    </div>`;
  veil.classList.add('up');
  modalConfirm = o.onConfirm || null;

  if (!o.noFocus) {
    const first = veil.querySelector('.modal-b input:not([type=checkbox]):not([readonly]), .modal-b textarea');
    if (first) setTimeout(() => first.focus(), 40);
  }
  return S.modalSeq;
}

/** Close every modal. */
function closeModal() {
  const veil = $('#veil');
  modalStack.length = 0;
  veil.classList.remove('up');
  veil.innerHTML = '';
  modalConfirm = null;
  S.modalSeq += 1;
}

/** Step back to the modal underneath, or close if there is none. */
function backModal() {
  if (modalStack.length) {
    const prev = modalStack.pop();
    $('#veil').innerHTML = prev.html;
    modalConfirm = prev.confirm;
    S.modalSeq += 1;
    return;
  }
  closeModal();
}

function modalValues() {
  const out = {};
  const modal = $('#veil .modal');
  if (!modal) return out;
  $$('[data-name]', modal).forEach(i => {
    if (i.type === 'checkbox') out[i.dataset.name] = i.checked;
    else if (i.multiple) out[i.dataset.name] = Array.from(i.selectedOptions).map(o => o.value);
    else out[i.dataset.name] = i.value;
  });
  return out;
}

function confirmModal(title, lede, confirmLabel, fn) {
  openModal({
    title, lede, icon: 'triangle-exclamation', confirm: confirmLabel, danger: true, cancel: 'Keep it', child: true,
    onConfirm: async () => { await fn(); }
  });
}

/* ═══════════════════════════════════════════════════════════════════════════
   APPS
   ═══════════════════════════════════════════════════════════════════════════ */
const APPS = {
  dashboard:     { label: 'Dashboard',  icon: 'gauge-high',           tone: 'teal',  exe: 'dashboard.exe',        group: 'ops' },
  dispatch:      { label: 'Dispatch',   icon: 'tower-broadcast',      tone: 'red',   exe: 'dispatch.exe',         group: 'ops',      perm: 'view.dispatch',     key: 'd' },
  bolos:         { label: 'BOLOs',      icon: 'bell',                 tone: 'amber', exe: 'bolo-board.exe',       group: 'ops',      perm: 'view.bolo',         key: 'b' },
  warrants:      { label: 'Warrants',   icon: 'triangle-exclamation', tone: 'red',   exe: 'warrants.exe',         group: 'ops',      perm: 'view.warrant',      key: 'w' },
  incidents:     { label: 'Incidents',  icon: 'file-lines',           tone: 'blue',  exe: 'incident-reports.exe', group: 'records',  perm: 'view.incident',     key: 'i' },
  charges:       { label: 'Penal Code', icon: 'scale-balanced',       tone: 'grey',  exe: 'penal-code.exe',       group: 'records',  perm: 'view.charge',       key: 'p' },
  evidence:      { label: 'Evidence',   icon: 'box-archive',          tone: 'amber', exe: 'evidence-locker.exe',  group: 'records',  perm: 'view.evidence',     key: 'e' },
  citizens:      { label: 'Citizens',   icon: 'user',                 tone: 'teal',  exe: 'citizen-db.exe',       group: 'registry', perm: 'view.citizen',      key: 'c' },
  vehicles:      { label: 'Vehicles',   icon: 'car',                  tone: 'blue',  exe: 'vehicle-db.exe',       group: 'registry', perm: 'view.vehicle',      key: 'v' },
  weapons:       { label: 'Weapons',    icon: 'gun',                  tone: 'red',   exe: 'firearm-db.exe',       group: 'registry', perm: 'view.weapon' },
  properties:    { label: 'Properties', icon: 'house',                tone: 'green', exe: 'property-db.exe',      group: 'registry', perm: 'view.property' },
  officers:      { label: 'Roster',     icon: 'id-badge',             tone: 'teal',  exe: 'roster.exe',           group: 'dept',     perm: 'view.officer',      key: 'r' },
  cameras:       { label: 'Cameras',    icon: 'video',                tone: 'grey',  exe: 'cctv.exe',             group: 'dept',     perm: 'view.camera' },
  announcements: { label: 'Bulletins',  icon: 'bullhorn',             tone: 'amber', exe: 'bulletins.exe',        group: 'dept',     perm: 'view.announcement' },
  audit:         { label: 'Audit Log',  icon: 'clock-rotate-left',    tone: 'grey',  exe: 'audit-log.exe',        group: 'dept',     perm: 'view.audit' },
  codes:         { label: '10-Codes',   icon: 'list-ol',              tone: 'blue',  exe: 'ten-codes.exe',        group: 'tools' },
  notepad:       { label: 'Notepad',    icon: 'note-sticky',          tone: 'amber', exe: 'notepad.exe',          group: 'tools',                               key: 'n' },
  settings:      { label: 'Settings',   icon: 'gear',                 tone: 'grey',  exe: 'settings.exe',         group: 'tools' }
};

const GROUPS = [
  ['ops', 'active_operations'],
  ['records', 'records_and_reports'],
  ['registry', 'registries'],
  ['dept', 'department'],
  ['tools', 'tools']
];

const appAllowed = (id) => {
  const a = APPS[id];
  return !!a && (!a.perm || can(a.perm));
};

/* ═══════════════════════════════════════════════════════════════════════════
   TABLET OS
   ═══════════════════════════════════════════════════════════════════════════ */
function wallpaperList() {
  const list = (S.cfg.tablet && S.cfg.tablet.wallpapers) || [];
  return list.length ? list : [{ id: 'nayzeee', label: 'NAYZEEE', file: 'img/wallpaper.svg' }];
}

function applySettings() {
  const st = S.settings;
  const frame = $('#frame');
  if (frame) frame.style.setProperty('--ui-scale', String(Math.max(0.8, Math.min(1.2, Number(st.scale) || 1))));

  const walls = wallpaperList();
  const want = walls.find(w => w.id === st.wallpaper) ||
               walls.find(w => w.id === (S.cfg.tablet && S.cfg.tablet.wallpaper)) || walls[0];
  const img = $('#wallpaper');
  if (img && want && img.getAttribute('src') !== want.file) img.setAttribute('src', want.file);
}

function saveSettings() {
  raw('settings:set', S.settings);
  if (!IN_GAME) { try { localStorage.setItem('nz_mdt_settings', JSON.stringify(S.settings)); } catch (e) {} }
}

function timeStrings() {
  const now = new Date();
  return {
    time: now.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }),
    date: now.toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' }),
    short: now.toLocaleDateString('en-GB', { day: '2-digit', month: '2-digit', year: 'numeric' })
  };
}

function tick() {
  const t = timeStrings();
  const set = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = v; };
  set('lockTime', t.time);
  set('lockDate', t.date);
  set('homeTime', t.time);
  set('homeDate', t.date);
  set('taskTime', t.time);
  set('taskDate', t.short);
}

async function refreshLocation() {
  const loc = await raw('myLocation');
  if (loc && loc.ok) {
    S.loc = loc;
    const el = $('#taskLocation');
    if (el) el.textContent = loc.street || 'Los Santos';
  }
}

function startTimers() {
  stopTimers();
  tick();
  refreshLocation();
  S.timers.clock = setInterval(tick, 15000);
  S.timers.loc = setInterval(refreshLocation, 15000);
}

function stopTimers() {
  Object.keys(S.timers).forEach(k => { clearInterval(S.timers[k]); clearTimeout(S.timers[k]); });
  S.timers = {};
}

/* ── lock screen + boot console ─────────────────────────────────────────── */
let skipIntro = false;

function lockDetails() {
  const me = S.me;
  $('#lockName').textContent = `${me.rank ? me.rank + ' ' : ''}${me.name}`;
  $('#lockDept').textContent = `${me.deptShort || ''}${me.callsign ? ' · ' + me.callsign : ''} · ${me.deptSub || 'Mobile Data Terminal'}`;
  const pw = $('#lockPassword');
  pw.value = '';
  pw.classList.remove('ok');
}

async function runLock() {
  const lock = $('#lockScreen');
  const desktop = $('#desktop');
  const wall = $('#wallpaper');

  skipIntro = false;
  lockDetails();
  lock.classList.remove('hidden', 'fade');
  desktop.classList.add('hidden');
  wall.classList.add('blur');

  if (S.settings.lockAnimation !== false) {
    const pw = $('#lockPassword');
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ0123456789';
    await sleep(250);
    for (let i = 0; i < 10 && !skipIntro; i++) {
      pw.value += chars[Math.floor(Math.random() * chars.length)];
      await sleep(65);
    }
    pw.classList.add('ok');
    if (!skipIntro) await sleep(420);
  }

  lock.classList.add('fade');
  wall.classList.remove('blur');
  desktop.classList.remove('hidden');
  setTimeout(() => lock.classList.add('hidden'), 360);
  S.unlocked = true;

  if (S.settings.bootConsole !== false && !S.booted && !skipIntro) await bootConsole();
  S.booted = true;
}

async function bootConsole() {
  const box = $('#console');
  const out = $('#consoleOutput');
  if (!box || !out) return;

  out.innerHTML = '';
  box.classList.remove('hidden');
  const line = (text, kind) => {
    const el = document.createElement('div');
    el.className = 'console-line ' + (kind || '');
    el.textContent = text;
    out.appendChild(el);
    out.scrollTop = out.scrollHeight;
  };

  const me = S.me;
  const steps = [
    ['/ NAYZEEE Services /', 'accent', 150],
    [`Connecting to ${me.deptShort || 'MDT'} CAD @ US Server #${Math.floor(Math.random() * 9000) + 1000}`, '', 260],
    ['Authenticating badge credentials...', '', 340],
    [`Badge ${me.badge || '—'} verified.`, '', 200],
    ['Access Granted.', 'success', 260],
    [`Welcome back, ${me.rank ? me.rank + ' ' : ''}${(me.name || '').split(' ').slice(-1)[0]}.`, 'accent', 220],
    ['Starting Application.', '', 320]
  ];

  for (const [text, kind, wait] of steps) {
    if (skipIntro) break;
    line(text, kind);
    await sleep(wait);
  }
  box.classList.add('hidden');
}

/* ── home screen ─────────────────────────────────────────────────────────── */
function renderHome() {
  const home = $('#home');
  if (!home || !S.me) return;

  const me = S.me;
  const d = S.dash;
  const c = d ? d.counts : null;
  const t = timeStrings();
  const hour = new Date().getHours();
  const greet = hour < 5 ? 'Late shift' : hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';
  const st = statusInfo(me.status);

  const badges = {
    dispatch: c && c.openCalls ? [c.openCalls, ''] : null,
    warrants: c && c.activeWarrants ? [c.activeWarrants, ''] : null,
    bolos: c && c.activeBolos ? [c.activeBolos, 'amber'] : null,
    evidence: c && c.evidenceOut ? [c.evidenceOut, 'amber'] : null
  };

  const groups = GROUPS.map(([g, title]) => {
    const apps = Object.keys(APPS).filter(id => APPS[id].group === g && appAllowed(id));
    if (!apps.length) return '';
    return `<div class="app-group-title">~/${title}</div>
      <div class="app-grid">${apps.map(id => {
        const a = APPS[id];
        const b = badges[id];
        return `<button class="tablet-app" data-act="app" data-app="${id}" title="${esc(a.exe)}">
          <div class="app-icon tone-${a.tone}">${fa(a.icon)}</div>
          <span>${esc(a.label)}</span>
          ${b ? `<b class="badge-dot ${b[1]}">${b[0] > 99 ? '99+' : b[0]}</b>` : ''}
        </button>`;
      }).join('')}</div>`;
  }).join('');

  const bulletin = d && (d.announcements || [])[0];

  home.innerHTML = `
    <aside class="home-side">
      <div class="widget-card home-clock">
        <b id="homeTime">${esc(t.time)}</b>
        <span id="homeDate">${esc(t.date)}</span>
        <p>${greet}, <b>${esc((me.name || '').split(' ')[0])}</b>.</p>
      </div>

      <div class="widget-card">
        <div class="widget-title">${fa('id-badge')} officer.profile</div>
        <div class="me-card">
          <div class="av teal">${initials(me.name)}</div>
          <div class="who">
            <b>${esc(me.name)}</b>
            <span>${esc(me.rank || '')}${me.deptShort ? ' · ' + esc(me.deptShort) : ''}</span>
          </div>
        </div>
        <div class="me-meta">
          <div><span>callsign</span><b>${esc(me.callsign || 'unset')}</b></div>
          <div><span>badge</span><b>${esc(me.badge || '—')}</b></div>
          <div><span>duty</span><b class="${me.onDuty ? 'on' : 'off'}">${me.onDuty ? 'On duty' : 'Off duty'}</b></div>
          <div><span>status</span><b>${me.onDuty ? esc(st.label) : '—'}</b></div>
        </div>
        <div class="me-actions">
          <button class="btn-line" data-act="callsign">${fa('pen')} Callsign</button>
          <button class="${me.onDuty ? 'btn-red' : 'btn-teal'}" data-act="duty">${fa('power-off')} ${me.onDuty ? 'Clock out' : 'Clock in'}</button>
        </div>
      </div>

      <div class="widget-card">
        <div class="widget-title">${fa('bolt')} quick.actions</div>
        <div class="quick-grid">
          ${S.cfg.panicEnabled !== false ? `<button class="quick red" data-act="panic">${fa('land-mine-on')} Panic</button>` : ''}
          ${can('dispatch.create') || S.cfg.backupForAll ? `<button class="quick amber" data-act="backup">${fa('people-group')} Backup</button>` : ''}
          ${can('view.vehicle') ? `<button class="quick" data-act="plate-nearby">${fa('car-side')} Run plate</button>` : ''}
          ${can('dispatch.create') ? `<button class="quick" data-act="call-create">${fa('plus')} New call</button>` : ''}
          ${can('incident.create') ? `<button class="quick" data-act="incident-new">${fa('file-pen')} Report</button>` : ''}
          <button class="quick" data-act="app" data-app="notepad">${fa('note-sticky')} Notes</button>
        </div>
      </div>

    </aside>

    <section class="home-main">
      <div class="home-search" data-act="spotlight">
        ${fa('magnifying-glass')}
        <span>Search citizens, plates, serials, reports…</span>
        <span class="kbd">/</span>
      </div>

      ${bulletin ? `<div class="bulletin-strip" data-act="app" data-app="announcements">
        ${fa('bullhorn')}
        <div><b>${esc(bulletin.title)}</b><p>${esc(bulletin.body || '')}</p></div>
        ${chev()}
      </div>` : ''}

      ${groups}
    </section>

    <aside class="home-feed">${homeFeed()}</aside>`;
}

function homeFeed() {
  const d = S.dash;
  const calls = (S.board.calls.length ? S.board.calls : (d && d.calls) || []).filter(c => c.status !== 'closed').slice(0, 5);
  const officers = (d && d.officers) || [];

  const feed = can('view.dispatch') ? `<div class="widget-card">
    <div class="widget-title">${fa('tower-broadcast')} dispatch.feed <span class="more" data-act="app" data-app="dispatch">open ${fa('chevron-right')}</span></div>
    <div class="feed-list">
      ${calls.map(c => `<button class="feed-item ${priorityClass(c.priority)}" data-act="call-select" data-id="${c.id}">
        <div class="top"><b>${esc(c.ref)}</b><span>${esc(c.code || '')}</span><span>${ago(c.ageSeconds)}</span></div>
        <h5>${esc(c.title)}</h5>
        <p>${esc(c.street || 'Location unknown')}${distance(c.x, c.y) ? ' · ' + distance(c.x, c.y) : ''} · ${plural((c.units || []).length, 'unit')}</p>
      </button>`).join('') || `<div class="wempty">The board is clear.</div>`}
    </div>
  </div>` : '';

  const units = `<div class="widget-card">
    <div class="widget-title">${fa('users')} units.on_duty <span class="more">${officers.length}</span></div>
    ${officers.slice(0, 8).map(o => {
      const st = statusInfo(o.status);
      return `<div class="feed-unit">
        <span class="dot ${st.tone === 'teal' ? '' : st.tone}"></span>
        <b>${esc(o.callsign || initials(o.name))}</b>
        <span class="nm">${esc(o.name)}</span>
        <em>${esc(st.label)}</em>
      </div>`;
    }).join('') || `<div class="wempty">Nobody is on duty.</div>`}
    ${officers.length > 8 ? `<div class="wempty" style="padding:0.6vh 0 0">+${officers.length - 8} more</div>` : ''}
  </div>`;

  const reports = d && (d.incidents || []).length && can('view.incident') ? `<div class="widget-card">
    <div class="widget-title">${fa('file-lines')} recent.reports <span class="more" data-act="app" data-app="incidents">all ${fa('chevron-right')}</span></div>
    <div class="feed-list">
      ${d.incidents.slice(0, 3).map(i => `<button class="feed-item" data-act="incident-open" data-id="${i.id}">
        <div class="top"><b>${esc(i.ref)}</b><span>${esc(i.status)}</span><span>${esc(i.stamp)}</span></div>
        <h5>${esc(i.title)}</h5>
      </button>`).join('')}
    </div>
  </div>` : '';

  return feed + units + reports;
}

/* ── windows ─────────────────────────────────────────────────────────────── */
function winTitle() {
  const me = S.me || {};
  const a = APPS[S.page] || { exe: 'app.exe' };
  const user = String(me.callsign || (me.name || 'user').split(' ')[0]).replace(/\s+/g, '');
  return `<span class="dim">root://</span>${esc(user)}<span class="dim">/</span>${esc(a.exe)}`;
}

function windowChrome() {
  const a = APPS[S.page];
  if (!a) return;
  const win = $('#appWindow');
  win.className = 'window t-' + a.tone;
  $('#winIcon').className = 'fa-solid fa-' + a.icon + ' window-header-icon';
  $('#winTitle').innerHTML = winTitle();
  $('#winFooter').textContent = `${(S.me && S.me.deptShort) || 'NAYZEEE'} Services | ${a.label} | v${S.cfg.version || '2.0.0'}`;
}

function setFooterRight(text) {
  const el = $('#winFooterRight');
  if (el) el.textContent = text || '';
}

function openApp(id) {
  if (!appAllowed(id)) return;
  closePopover();
  if (!S.open.includes(id)) S.open.push(id);

  const changed = S.page !== id || !S.windowUp;
  S.page = id;
  S.windowUp = true;
  $('#windowWrap').classList.remove('hidden');

  windowChrome();
  renderDock();
  if (changed) {
    render(true);
    loadPage(id);
  }
}

function minimizeApp() {
  S.windowUp = false;
  $('#windowWrap').classList.add('hidden');
  renderDock();
  renderHome();
}

function closeApp(id) {
  id = id || S.page;
  S.open = S.open.filter(x => x !== id);
  if (S.page === id) {
    S.windowUp = false;
    $('#windowWrap').classList.add('hidden');
    S.page = null;
  }
  renderDock();
  renderHome();
}

function goHome() {
  if (S.windowUp) minimizeApp();
}

function renderDock() {
  const dock = $('#dock');
  if (!dock) return;
  dock.innerHTML = S.open.filter(appAllowed).map(id => {
    const a = APPS[id];
    return `<button class="taskbar-app ${S.page === id && S.windowUp ? 'active' : ''}" data-dock="${id}" title="${esc(a.label)}">${fa(a.icon)}</button>`;
  }).join('');
}

function renderTaskbar() {
  const me = S.me;
  if (!me) return;
  const duty = $('#taskDuty');
  duty.textContent = me.onDuty ? 'DUTY: ON' : 'DUTY: OFF';
  duty.classList.toggle('active', !!me.onDuty);

  const st = statusInfo(me.status);
  const pill = $('#taskStatus');
  pill.className = 'taskbar-status ' + (me.onDuty ? (st.tone === 'teal' ? '' : st.tone) : 'off');
  pill.querySelector('span').textContent = me.onDuty ? st.label : 'Off duty';
  pill.disabled = !me.onDuty;
}

/* ── status popover ─────────────────────────────────────────────────────── */
function closePopover() {
  const p = $('#popover');
  if (p) p.innerHTML = '';
}

function statusPopover() {
  const p = $('#popover');
  if (p.innerHTML) return closePopover();
  const pill = $('#taskStatus');
  const desk = $('#desktop').getBoundingClientRect();
  const r = pill.getBoundingClientRect();
  const scale = desk.width / $('#desktop').offsetWidth || 1;

  p.innerHTML = `<div class="popover" style="right:${Math.max(0, (desk.right - r.right) / scale)}px">
    <div class="popover-title">set.unit_status</div>
    ${(S.cfg.unitStatus || []).map(s => `
      <button class="${S.me.status === s.id ? 'on' : ''}" data-act="set-status" data-status="${esc(s.id)}">
        <span class="dot ${s.tone === 'teal' ? '' : s.tone === 'off' ? 'off' : s.tone}"></span>${esc(s.label)}
      </button>`).join('')}
  </div>`;
}

async function setStatus(id) {
  closePopover();
  const res = await post('nz_mdt:duty:status', id);
  if (reply(res)) {
    S.me.status = id;
    renderTaskbar();
    renderHome();
  }
}

async function toggleDuty() {
  const res = await post('nz_mdt:duty:toggle');
  if (reply(res)) {
    S.me.onDuty = res.onDuty;
    S.me.status = res.onDuty ? 'available' : 'break';
    renderTaskbar();
    renderHome();
    windowChrome();
    scheduleDash(200);
    if (S.windowUp) loadPage(S.page);
  }
}

/* ── open / close ────────────────────────────────────────────────────────── */
function showTablet() {
  S.visible = true;
  $('#widget').classList.remove('up');
  $('#app').classList.remove('hidden', 'shooting');
  const frame = $('#frame');
  frame.classList.remove('closing');
  // restart the slide-in animation
  void frame.offsetWidth;
  startTimers();
}

function hideTablet() {
  S.visible = false;
  stopTimers();
  closePopover();
  closeSpotlight();
  closeModal();
  $('#lightbox').classList.remove('up');
  $('#app').classList.add('hidden');
}

function closeUI() {
  const frame = $('#frame');
  frame.classList.add('closing');
  setTimeout(() => {
    hideTablet();
    raw('close');
  }, 200);
}

/* ═══════════════════════════════════════════════════════════════════════════
   SHARED BUILDERS
   ═══════════════════════════════════════════════════════════════════════════ */
function statTile(ic, label, value, sub, tone, act) {
  return `<div class="stat ${act ? 'clickable' : ''}" ${act ? `data-act="app" data-app="${act}"` : ''}>
    <div class="tile ${tone || ''}">${icon(ic)}</div>
    <div class="stat-txt"><span>${esc(label)}</span><b>${value}</b><i>${esc(sub || '')}</i></div>
  </div>`;
}

function emptyState(ic, title, text) {
  return `<div class="empty">${icon(ic)}<b>${esc(title)}</b><span>${esc(text)}</span></div>`;
}

function skeleton(n) {
  return Array.from({ length: n || 3 }).map(() => `
    <div class="skel"><div class="sk circ"></div>
      <div style="flex:1"><div class="sk" style="height:0.9vh;width:52%"></div>
      <div class="sk" style="height:0.7vh;width:32%;margin-top:0.7vh"></div></div></div>`).join('');
}

function pager(r, act) {
  if (!r || !r.pages) return '';
  const btns = [];
  if (r.pages > 1) {
    const from = Math.max(1, Math.min(r.page - 2, r.pages - 4)), to = Math.min(r.pages, from + 4);
    for (let i = from; i <= to; i++) {
      btns.push(`<button class="${i === r.page ? 'on' : ''}" data-act="${act}" data-page="${i}">${i}</button>`);
    }
  }
  return `<div class="pager">
    <span class="count">${plural(r.total || 0, 'record')}</span>
    ${r.pages > 1 ? `<button data-act="${act}" data-page="${Math.max(1, r.page - 1)}" ${r.page <= 1 ? 'disabled' : ''}>${fa('chevron-left')}</button>
    ${btns.join('')}
    <button data-act="${act}" data-page="${Math.min(r.pages, r.page + 1)}" ${r.page >= r.pages ? 'disabled' : ''}>${fa('chevron-right')}</button>` : ''}
  </div>`;
}

function noteRows(notes) {
  return (notes || []).map(n => `
    <div class="note">
      <div class="note-top">
        <b>${esc(n.author)}</b><span>${esc(n.stamp)}</span>
        <span class="chip ${n.visibility === 'private' ? 'off' : n.visibility === 'command' ? 'amber' : ''}">${esc(n.visibility)}</span>
        ${n.mine || can('officer.manage') ? `<button class="icobtn danger" data-inner="note-del" data-id="${n.id}" title="Remove">${ICON.trash}</button>` : ''}
      </div>
      <p>${esc(n.body)}</p>
    </div>`).join('') || emptyState('file', 'No notes yet', 'Anything you add here is visible to your department.');
}

function noteBlock(subject, subjectId, notes) {
  return `<div class="field">
      <label>add_note</label>
      <textarea data-name="noteBody" placeholder="What should the next officer know?"></textarea>
    </div>
    <div class="inline">
      <div class="field">
        <label>visibility</label>
        <select data-name="noteVis">
          <option value="department">Department</option>
          <option value="command">Command only</option>
          <option value="private">Only me</option>
        </select>
      </div>
      <button class="btn-teal" data-inner="note-add" data-subject="${esc(subject)}" data-sid="${esc(subjectId)}">${ICON.plus} Add note</button>
    </div>
    <div class="scroll short" id="noteList">${noteRows(notes)}</div>`;
}

function filterSelect(act, value, options) {
  return `<div class="field narrow"><select data-act="${act}">
    ${options.map(([v, l]) => `<option value="${esc(v)}" ${value === v ? 'selected' : ''}>${esc(l)}</option>`).join('')}
  </select></div>`;
}

function searchField(act, value, placeholder) {
  return `<div class="field"><input data-act="${act}" placeholder="${esc(placeholder)}" value="${esc(value || '')}" spellcheck="false"></div>`;
}

const statusTag = (s) => s === 'closed' ? 'off' : s === 'pending' ? 'warn' : 'live';

/* ═══════════════════════════════════════════════════════════════════════════
   DASHBOARD
   ═══════════════════════════════════════════════════════════════════════════ */
function pageDashboard() {
  const d = S.dash;
  if (!d) return `<div class="head"><div><h1>Dashboard</h1><p>Loading the department picture…</p></div></div>${skeleton(5)}`;

  const hour = new Date().getHours();
  const greet = hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';
  const first = (S.me.name || '').split(' ')[0];
  const officers = d.officers || [];

  const incidents = (d.incidents || []).map(i => `
    <button class="row" data-act="incident-open" data-id="${i.id}">
      <div class="ic blue">${ICON.file}</div>
      <div class="row-txt"><b>${esc(i.title)}</b><span>${esc(i.ref)} · ${esc(i.location || 'no location')}</span></div>
      <span class="tag ${statusTag(i.status)}">${esc(i.status)}</span>
      <span class="row-meta">${esc(i.stamp)}</span>
    </button>`).join('') || emptyState('file', 'No reports filed', 'Reports appear here as your department files them.');

  const warrants = (d.warrants || []).map(w => `
    <button class="row hot" data-act="citizen-open" data-id="${esc(w.citizen_id)}">
      <div class="ic red">${ICON.warn}</div>
      <div class="row-txt"><b>${esc(w.citizen_name)}</b><span>${esc(w.title)} · ${esc(w.issued_by)}</span></div>
      <span class="row-meta">${esc(w.stamp)}</span>
    </button>`).join('') || emptyState('check', 'No active warrants', 'Nothing outstanding on the board right now.');

  const units = officers.map(o => {
    const st = statusInfo(o.status);
    return `<div class="row">
      <div class="av sm teal">${initials(o.name)}</div>
      <div class="row-txt"><b>${esc(o.callsign || o.name)}</b><span>${esc(o.name)} · ${esc(o.rank || '')}</span></div>
      <span class="tag ${st.tone === 'red' ? 'hot' : st.tone === 'amber' ? 'warn' : st.tone === 'off' ? 'off' : 'live'}">${esc(st.label)}</span>
    </div>`;
  }).join('') || emptyState('badge', 'Nobody on duty', 'Clock on to show up on the roster.');

  return `
    <div class="head">
      <div>
        <h1>${greet}, ${esc(first)}</h1>
        <p>${plural(d.counts.openCalls, 'open call')}, ${plural(d.counts.activeWarrants, 'active warrant')} and ${plural(officers.length, 'unit')} on the street.</p>
      </div>
      <div class="head-act">
        <button class="btn-line" data-act="callsign">${ICON.badge} Callsign</button>
        <button class="${S.me.onDuty ? 'btn-red' : 'btn-teal solid'}" data-act="duty">${fa('power-off')} ${S.me.onDuty ? 'Clock out' : 'Clock in'}</button>
      </div>
    </div>

    <div class="stats five">
      ${statTile('alert', 'Open calls', d.counts.openCalls, 'on the board', d.counts.openCalls > 0 ? 'red' : '', 'dispatch')}
      ${statTile('warn', 'Active warrants', d.counts.activeWarrants, 'outstanding', d.counts.activeWarrants > 0 ? 'red' : '', 'warrants')}
      ${statTile('bell', 'Live BOLOs', d.counts.activeBolos, 'being watched for', d.counts.activeBolos > 0 ? 'amber' : '', 'bolos')}
      ${statTile('file', 'Open reports', d.counts.openIncidents, 'not yet closed', 'blue', 'incidents')}
      ${statTile('clock', 'Your shift', S.me.onDuty ? `${d.me.shiftMinutes}m` : 'Off', `${d.me.totalHours}h logged`)}
    </div>

    ${d.stats ? `<section class="panel">
      <div class="p-head">
        <div><h2>Department performance</h2><p>last ${d.stats.days} days · every unit</p></div>
        <span class="chip">${d.stats.myReports} filed by you</span>
      </div>
      <div class="p-body tight">
        <div class="stats five">
          ${statTile('lock', 'Arrests', d.stats.arrests, 'reports with jail time', 'red')}
          ${statTile('file', 'Citations', d.stats.citations, 'fine only')}
          ${statTile('check', 'Cases closed', d.stats.closed, `${d.stats.filed} filed`)}
          ${statTile('shield', 'Clearance', d.stats.clearance + '%', 'closed vs filed', d.stats.clearance >= 60 ? '' : 'amber')}
          ${statTile('cash', 'Fines levied', money(d.stats.revenue), 'on closed reports', 'amber')}
        </div>
      </div>
    </section>` : ''}

    <div class="cols wide-left">
      <section class="panel">
        <div class="p-head">
          <div><h2>Recent incidents</h2><p>latest department-wide</p></div>
          ${can('view.incident') ? `<button class="btn-ghost" data-act="app" data-app="incidents">See all ${chev()}</button>` : ''}
        </div>
        <div class="p-body">${incidents}</div>
      </section>

      <div class="stack">
        <section class="panel">
          <div class="p-head"><div><h2>Active warrants</h2><p>wanted right now</p></div></div>
          <div class="p-body">${warrants}</div>
        </section>
        <section class="panel">
          <div class="p-head">
            <div><h2>On duty</h2><p>units signed on</p></div>
            <span class="tally">${officers.length}</span>
          </div>
          <div class="p-body">${units}</div>
        </section>
      </div>
    </div>`;
}

/* ═══════════════════════════════════════════════════════════════════════════
   DISPATCH
   ═══════════════════════════════════════════════════════════════════════════ */
function mapPin(x, y) {
  const b = S.cfg.mapBounds || { minX: -6235, maxX: 6435, minY: -4510, maxY: 8810 };
  const px = ((x - b.minX) / (b.maxX - b.minX)) * 100;
  const py = 100 - ((y - b.minY) / (b.maxY - b.minY)) * 100;
  return { left: Math.max(0.5, Math.min(99.5, px)), top: Math.max(0.5, Math.min(99.5, py)) };
}

function callPins() {
  const b = S.board;
  const out = [];
  b.calls.forEach(c => {
    if (c.x == null || c.status === 'closed') return;
    const t = callType(c.type);
    const p = mapPin(c.x, c.y);
    out.push(`<div class="pin ${priorityClass(c.priority)} ${b.selected === c.id ? 'on' : ''}" data-act="call-select" data-id="${c.id}"
        style="left:${p.left}%;top:${p.top}%" title="${esc(c.ref)} · ${esc(c.title)}">
      <div class="pin-head">${icon(t && t.icon)}</div>
      ${b.selected === c.id ? `<span class="plabel">${esc(c.ref)}</span>` : ''}
    </div>`);
  });
  Object.values(S.panics).forEach(p => {
    if (p.x == null) return;
    const pos = mapPin(p.x, p.y);
    out.push(`<div class="pin panic" style="left:${pos.left}%;top:${pos.top}%" title="Panic — ${esc(p.callsign || p.name)}">
      <div class="pin-head">${fa('land-mine-on')}</div><span class="plabel">PANIC ${esc(p.callsign || '')}</span></div>`);
  });
  return out.join('');
}

function unitPins() {
  return (S.board.officers || []).map(o => {
    if (o.x == null) return '';
    const p = mapPin(o.x, o.y);
    const me = S.me && o.identifier === S.me.identifier;
    return `<div class="pin unit ${me ? 'me' : ''}" style="left:${p.left}%;top:${p.top}%" title="${esc(o.name)}">
      <div class="pin-head">${fa('shield-halved')}</div>
      <span class="plabel">${esc(o.callsign || initials(o.name))}</span>
    </div>`;
  }).join('');
}

function unitStrip() {
  return (S.board.officers || []).map(o => {
    const st = statusInfo(o.status);
    return `<div class="unitcard">
      <b>${esc(o.callsign || initials(o.name))}</b>
      <span>${esc(o.name)}</span>
      <div class="st"><span class="dot ${st.tone === 'teal' ? '' : st.tone}"></span>${esc(st.label)}${o.street ? ' · ' + esc(o.street) : ''}</div>
    </div>`;
  }).join('') || `<div class="wempty">No units on duty.</div>`;
}

function stateLabel(s) {
  return s === 'pending' ? 'Pending' : s === 'assigned' ? 'Assigned' : s === 'onscene' ? 'On scene' : 'Closed';
}

function callCards() {
  const b = S.board;
  return b.calls.map(c => {
    const units = (c.units || []).slice(0, 5).map(u => {
      const me = S.me && u.identifier === S.me.identifier;
      return `<span class="unitpip ${me ? 'me' : ''}" title="${esc(u.name)}">${esc((u.callsign || initials(u.name)).slice(0, 4))}</span>`;
    }).join('');
    return `<button class="call ${priorityClass(c.priority)} ${b.selected === c.id ? 'on' : ''} ${c.status === 'closed' ? 'closed' : ''}"
        data-act="call-select" data-id="${c.id}">
      <div class="call-top">
        <span class="dot ${priorityTone(c.priority) === 'teal' ? '' : priorityTone(c.priority)}"></span>
        <span class="ref">${esc(c.ref)}</span>
        <span class="code">${esc(c.code || '')}</span>
        <span class="state ${esc(c.status)}">${stateLabel(c.status)}</span>
      </div>
      <h3>${esc(c.title)}</h3>
      <div class="where">${ICON.pin}${esc(c.street || 'Location unknown')}${distance(c.x, c.y) ? ` · ${distance(c.x, c.y)}` : ''}</div>
      ${c.detail ? `<div class="detail">${esc(c.detail)}</div>` : ''}
      <div class="call-foot">
        <span class="age">${ago(c.ageSeconds)}</span>
        <span class="units">${units}${(c.units || []).length > 5 ? `<span class="unitpip">+${c.units.length - 5}</span>` : ''}</span>
      </div>
    </button>`;
  }).join('') || emptyState('check', 'The board is clear', 'New calls land here the moment they come in.');
}

function pageDispatch() {
  const b = S.board;
  const open = b.calls.filter(c => c.status !== 'closed').length;
  const sel = b.calls.find(c => c.id === b.selected);
  const style = mapStyle();
  const styles = S.cfg.mapStyles || [];

  return `
    <div class="head">
      <div>
        <h1>Dispatch</h1>
        <p>Live calls, attached units and where everyone is right now.</p>
      </div>
      <div class="head-act">
        <button class="btn-ghost ${b.includeClosed ? 'on' : ''}" data-act="board-closed">${fa('box-archive')} Show closed</button>
        ${can('dispatch.create') ? `<button class="btn-line" data-act="backup">${fa('people-group')} Request backup</button>` : ''}
        ${can('dispatch.create') ? `<button class="btn-teal solid" data-act="call-create">${ICON.plus} Create call</button>` : ''}
      </div>
    </div>

    <div class="cols board">
      <section class="panel">
        <div class="p-head">
          <div><h2>Active dispatches</h2><p>priority first · newest first</p></div>
          <span class="tally ${open ? 'hot' : ''}">${open}</span>
        </div>
        <div class="p-body cap" id="callList" style="max-height:62vh">${callCards()}</div>
      </section>

      <div class="stack">
        ${S.cfg.mapEnabled ? `<div class="mapwrap">
          <div class="mapviewport" id="mapViewport">
            <div class="mapplane ${style.file ? 'art' : ''}" id="mapPlane">
              ${style.file ? `<img src="${esc(style.file)}" alt="" draggable="false">` : ''}
              <div id="pinCalls">${callPins()}</div>
              <div id="pinUnits">${unitPins()}</div>
            </div>
          </div>
          ${styles.length > 1 ? `<div class="mapstyles">
            ${styles.map(x => `<button class="${x.id === style.id ? 'on' : ''}" data-act="map-style" data-style="${esc(x.id)}">${esc(x.label)}</button>`).join('')}
          </div>` : ''}
          <div class="mapzoom">
            <button data-act="map-zoom" data-dir="in" title="Zoom in">${ICON.plus}</button>
            <button data-act="map-zoom" data-dir="out" title="Zoom out">${ICON.minus}</button>
            <button data-act="map-zoom" data-dir="me" title="Centre on me">${fa('location-crosshairs')}</button>
            <button data-act="map-zoom" data-dir="reset" title="Reset">${ICON.refresh}</button>
          </div>
          <div class="mapscale" id="mapScale">100%</div>
          <div class="maplegend">
            <span><i class="r"></i>Critical</span><span><i class="a"></i>Priority</span><span><i class="t"></i>Routine &amp; units</span>
          </div>
        </div>` : ''}

        <div id="callDetail">${sel ? callDetail(sel) : ''}</div>

        <section class="panel">
          <div class="p-head"><div><h2>Units on duty</h2><p>status · last known street</p></div><span class="tally">${(b.officers || []).length}</span></div>
          <div class="p-body tight"><div class="units-strip" id="unitStrip">${unitStrip()}</div></div>
        </section>
      </div>
    </div>`;
}

function callDetail(c) {
  const mine = (c.units || []).find(u => S.me && u.identifier === S.me.identifier);
  const units = (c.units || []).map(u => `
    <div class="row">
      <div class="av sm teal">${esc((u.callsign || initials(u.name)).slice(0, 4))}</div>
      <div class="row-txt"><b>${esc(u.name)}</b><span>${esc(u.department || '')}</span></div>
      <span class="tag ${u.status === 'onscene' ? 'warn' : u.status === 'busy' ? 'hot' : 'live'}">${esc(statusInfo(u.status).label)}</span>
    </div>`).join('') || emptyState('badge', 'No units attached', 'Attach yourself to take this call.');

  const statusOpts = (S.cfg.unitStatus || []).map(s =>
    `<option value="${esc(s.id)}" ${mine && mine.status === s.id ? 'selected' : ''}>${esc(s.label)}</option>`).join('');
  const dist = distance(c.x, c.y);

  return `<section class="panel">
    <div class="p-head">
      <div><h2>${esc(c.ref)} · ${esc(c.title)}</h2><p>${esc(c.street || 'Location unknown')} · ${ago(c.ageSeconds)}${dist ? ' · ' + dist + ' away' : ''}</p></div>
      <span class="chip ${toneChip(priorityTone(c.priority))}">${esc(c.code || '10-00')}</span>
    </div>
    <div class="p-body tight">
      ${c.detail ? `<p class="prose" style="margin-bottom:1.2vh">${esc(c.detail)}</p>` : ''}
      <div class="kgrid four" style="margin-bottom:1.4vh">
        <div class="kfield"><span>caller</span><b>${esc(c.caller || 'Anonymous')}</b></div>
        <div class="kfield"><span>status</span><b class="${c.status === 'pending' ? 'red' : 'teal'}">${esc(stateLabel(c.status))}</b></div>
        <div class="kfield"><span>plate</span><b>${c.plate && can('view.vehicle') ? `<a data-act="vehicle-open" data-id="${esc(c.plate)}" style="cursor:pointer;color:var(--accent)">${esc(c.plate)}</a>` : esc(c.plate || '—')}</b></div>
        <div class="kfield"><span>units</span><b>${(c.units || []).length} / ${S.cfg.maxUnits || 8}</b></div>
      </div>
      ${c.closedBy ? `<div class="banner teal" style="margin-bottom:1.2vh">${fa('box-archive')}<div><b>Closed by ${esc(c.closedBy)}</b><p>${esc(c.closedNote || 'No disposition recorded.')}</p></div></div>` : ''}

      <div class="btnrow" style="margin-bottom:1.2vh">
        ${c.x != null ? `<button class="btn-line" data-act="call-route" data-id="${c.id}">${ICON.route} Set route</button>` : ''}
        ${c.status !== 'closed' && can('dispatch.assign')
          ? (mine
            ? `<button class="btn-line" data-act="call-detach" data-id="${c.id}">${fa('right-from-bracket')} Clear</button>
               <select class="mini" data-change="call-status" data-id="${c.id}">${statusOpts}</select>`
            : `<button class="btn-teal solid" data-act="call-attach" data-id="${c.id}">${fa('car-on')} Attach as unit</button>`)
          : ''}
        ${can('incident.create') ? `<button class="btn-ghost" data-act="call-to-incident" data-id="${c.id}">${fa('file-pen')} File report</button>` : ''}
        ${c.status !== 'closed' && can('dispatch.close')
          ? `<button class="btn-red push" data-act="call-close" data-id="${c.id}">${fa('circle-xmark')} Close call</button>` : ''}
      </div>

      <div class="scroll short">${units}</div>
    </div>
  </section>`;
}

/** Repaint the moving parts of the board without rebuilding the map. */
function refreshBoardParts(full) {
  if (S.page !== 'dispatch' || !S.windowUp) return;
  if (full) { render(); return; }
  const units = $('#pinUnits');
  if (units) units.innerHTML = unitPins();
  const calls = $('#pinCalls');
  if (calls) calls.innerHTML = callPins();
  const strip = $('#unitStrip');
  if (strip) strip.innerHTML = unitStrip();
  mapApply();
}

/* ═══════════════════════════════════════════════════════════════════════════
   BOLOs
   ═══════════════════════════════════════════════════════════════════════════ */
function pageBolos() {
  const st = S.list.bolos || { search: '', filter: 'active', rows: null };
  const rows = st.rows;

  const cards = !rows ? skeleton(4) : (rows.length === 0
    ? emptyState('bell', 'Nothing on the board', 'Issue a BOLO and every unit on duty sees it right away.')
    : rows.map(b => `
      <section class="panel">
        <div class="p-head">
          <div>
            <h2>${esc(b.title)}</h2>
            <p>${esc(b.plate ? b.plate + (b.model ? ' · ' + b.model : '') : b.kind)} · P${b.priority}</p>
          </div>
          <div class="acts">
            ${can('bolo.edit') && b.status === 'active' ? `<button class="icobtn" data-act="bolo-edit" data-id="${b.id}" title="Edit">${ICON.pen}</button>` : ''}
            <span class="tag ${b.status === 'active' ? 'hot' : b.status === 'resolved' ? 'ok' : 'off'}">${esc(b.status)}</span>
          </div>
        </div>
        <div class="p-body tight">
          <p class="prose">${esc(b.detail || 'No further detail.')}</p>
          <div class="kv" style="margin-top:1vh"><span>Issued by</span><b>${esc(b.issuedBy)}</b></div>
          <div class="kv"><span>Raised</span><b>${esc(b.stamp)}</b></div>
          ${b.expiresIn != null && b.status === 'active' ? `<div class="kv"><span>Expires in</span><b class="amber">${b.expiresIn}h</b></div>` : ''}
          ${b.resolvedBy ? `<div class="kv"><span>Resolved by</span><b class="teal">${esc(b.resolvedBy)}</b></div>` : ''}
          <div class="btnrow" style="margin-top:1.3vh">
            ${b.status === 'active' && can('bolo.resolve')
              ? `<button class="btn-teal solid" data-act="bolo-resolve" data-id="${b.id}">${ICON.check} Resolve</button>` : ''}
            ${b.plate && can('view.vehicle') ? `<button class="btn-line" data-act="vehicle-open" data-id="${esc(b.plate)}">${ICON.car} Run plate</button>` : ''}
            ${b.citizenId && can('view.citizen') ? `<button class="btn-line" data-act="citizen-open" data-id="${esc(b.citizenId)}">${ICON.user} Person</button>` : ''}
            ${can('bolo.delete') ? `<button class="icobtn danger push" data-act="bolo-delete" data-id="${b.id}" title="Delete">${ICON.trash}</button>` : ''}
          </div>
        </div>
      </section>`).join(''));

  return `
    <div class="head">
      <div><h1>BOLOs</h1><p>Be on the look out — vehicles, people and property your department is watching for. Live plates are matched by the ALPR.</p></div>
      <div class="head-act">
        ${can('bolo.create') ? `<button class="btn-teal solid" data-act="bolo-create">${ICON.plus} Issue a BOLO</button>` : ''}
      </div>
    </div>
    <div class="filters">
      ${searchField('bolo-search', st.search, 'Search titles, plates and detail')}
      ${filterSelect('bolo-filter', st.filter, [['active', 'Active'], ['all', 'All'], ['resolved', 'Resolved'], ['expired', 'Expired']])}
    </div>
    <div class="cols">${cards}</div>`;
}

/* ═══════════════════════════════════════════════════════════════════════════
   WARRANTS
   ═══════════════════════════════════════════════════════════════════════════ */
function pageWarrants() {
  const st = S.list.warrants || { search: '', filter: 'active', rows: null };
  const rows = st.rows;

  const cards = !rows ? skeleton(4) : (rows.length === 0
    ? emptyState('check', 'No warrants on file', 'Nothing matches that filter right now.')
    : rows.map(w => {
      const charges = (w.charges || []).map(c => `<span class="chip off">${esc(c.label || c.id)}</span>`).join(' ');
      const type = (S.cfg.warrantTypes || []).find(t => t.id === w.type);
      return `<section class="panel">
        <div class="p-head">
          <div><h2>${esc(w.citizen)}</h2><p>${esc(w.title)}</p></div>
          <span class="tag ${w.status === 'active' ? 'hot' : w.status === 'executed' ? 'ok' : 'off'}">${esc(w.status)}</span>
        </div>
        <div class="p-body tight">
          <p class="prose">${esc(w.detail || 'No further detail.')}</p>
          ${charges ? `<div class="btnrow" style="margin-top:1vh">${charges}</div>` : ''}
          <div class="kv" style="margin-top:1vh"><span>Type</span><b>${esc(type ? type.label : w.type)}</b></div>
          <div class="kv"><span>Issued by</span><b>${esc(w.issuedBy)}</b></div>
          <div class="kv"><span>Raised</span><b>${esc(w.stamp)}</b></div>
          ${w.expiresIn != null && w.status === 'active' ? `<div class="kv"><span>Expires in</span><b class="amber">${plural(w.expiresIn, 'day')}</b></div>` : ''}
          ${w.executedBy ? `<div class="kv"><span>Executed by</span><b class="teal">${esc(w.executedBy)}</b></div>` : ''}
          <div class="btnrow" style="margin-top:1.3vh">
            ${can('view.citizen') ? `<button class="btn-line" data-act="citizen-open" data-id="${esc(w.citizenId)}">${ICON.user} Record</button>` : ''}
            ${w.status === 'active' && can('warrant.execute')
              ? `<button class="btn-teal solid" data-act="warrant-execute" data-id="${w.id}">${fa('handcuffs')} Executed</button>` : ''}
            ${w.status === 'active' && can('warrant.edit')
              ? `<button class="btn-ghost danger" data-act="warrant-void" data-id="${w.id}">Void</button>` : ''}
            ${can('warrant.delete') ? `<button class="icobtn danger push" data-act="warrant-delete" data-id="${w.id}" title="Delete">${ICON.trash}</button>` : ''}
          </div>
        </div>
      </section>`;
    }).join(''));

  return `
    <div class="head">
      <div><h1>Warrants</h1><p>Arrest, search, bench and seizure warrants across every department.</p></div>
      <div class="head-act">
        ${can('warrant.create') ? `<button class="btn-teal solid" data-act="warrant-create">${ICON.plus} Issue a warrant</button>` : ''}
      </div>
    </div>
    <div class="filters">
      ${searchField('warrant-search', st.search, 'Search by name, title or citizen ID')}
      ${filterSelect('warrant-filter', st.filter, [['active', 'Active'], ['all', 'All'], ['executed', 'Executed'], ['expired', 'Expired'], ['void', 'Void']])}
    </div>
    <div class="cols">${cards}</div>`;
}

/* ═══════════════════════════════════════════════════════════════════════════
   INCIDENTS
   ═══════════════════════════════════════════════════════════════════════════ */
function pageIncidents() {
  const st = S.list.incidents || { search: '', status: 'all', page: 1, res: null };
  const r = st.res;

  const rows = !r ? skeleton(5) : (!r.rows || r.rows.length === 0
    ? emptyState('file', 'No reports match', 'Change the filter, or file the first report.')
    : r.rows.map(i => `
      <button class="row" data-act="incident-open" data-id="${i.id}">
        <div class="ic ${i.status === 'closed' ? 'grey' : i.status === 'pending' ? 'amber' : 'blue'}">${ICON.file}</div>
        <div class="row-txt">
          <b>${esc(i.title)}<small>${esc(i.ref)}</small></b>
          <span>${esc(i.location || 'no location')} · ${esc(i.primary_name || 'no primary citizen')} · ${plural(i.charge_count || 0, 'charge')} · ${esc(i.created_by || '')}</span>
        </div>
        <div class="row-num"><b>${money(i.total_fine)}</b><span>${i.total_jail} months</span></div>
        <span class="tag ${statusTag(i.status)}">${esc(i.status)}</span>
        <span class="row-meta" style="width:13vh;text-align:right">${esc(i.stamp)}</span>
        ${chev()}
      </button>`).join(''));

  return `
    <div class="head">
      <div><h1>Incidents</h1><p>Every report your department has filed, with charges, fines and sentences.</p></div>
      <div class="head-act">
        <button class="btn-ghost ${st.mine ? 'on' : ''}" data-act="incident-mine">${ICON.user} Mine only</button>
        ${can('incident.create') ? `<button class="btn-teal solid" data-act="incident-new">${ICON.plus} File a report</button>` : ''}
      </div>
    </div>
    <div class="filters">
      ${searchField('incident-search', st.search, 'Search by reference, title, citizen or location')}
      ${filterSelect('incident-status', st.status, [['all', 'All reports'], ['open', 'Open'], ['pending', 'Pending'], ['closed', 'Closed']])}
    </div>
    <section class="panel"><div class="p-body">${rows}${pager(r, 'incident-page')}</div></section>`;
}

/* ═══════════════════════════════════════════════════════════════════════════
   PENAL CODE + SENTENCE CALCULATOR
   ═══════════════════════════════════════════════════════════════════════════ */
function calcTotals(list) {
  let fine = 0, jail = 0, points = 0;
  (list || []).forEach(c => {
    const base = charge(c.id);
    if (!base) return;
    const mult = c.reduced ? 0.5 : 1;
    fine += Math.floor(base.fine * c.counts * mult);
    jail += Math.floor(base.jail * c.counts * mult);
    points += (base.points || 0) * c.counts;
  });
  return { fine, jail, points };
}

function chargeRows(list, prefix) {
  return list.map((c, i) => {
    const base = charge(c.id) || { label: c.id, fine: 0, jail: 0, class: 'misdemeanor' };
    const cl = (S.cfg.chargeClasses || {})[base.class] || { tone: 'teal', label: base.class };
    const mult = c.reduced ? 0.5 : 1;
    return `<div class="chargerow">
      <span class="chip ${toneChip(cl.tone)}">${esc((cl.label || '').slice(0, 3).toUpperCase())}</span>
      <b title="${esc(base.label)}">${esc(base.label)}</b>
      <span class="cost">${money(Math.floor(base.fine * c.counts * mult))} · ${Math.floor(base.jail * c.counts * mult)}m</span>
      <button class="btn-ghost ${c.reduced ? 'on' : ''}" data-inner="${prefix}-reduce" data-act="${prefix}-reduce" data-i="${i}" title="Half fine and time">½</button>
      <div class="counter">
        <button data-inner="${prefix}-minus" data-act="${prefix}-minus" data-i="${i}">${ICON.minus}</button>
        <span>${c.counts}</span>
        <button data-inner="${prefix}-plus" data-act="${prefix}-plus" data-i="${i}">${ICON.plus}</button>
      </div>
      <button class="icobtn danger" data-inner="${prefix}-del" data-act="${prefix}-del" data-i="${i}">${ICON.x}</button>
    </div>`;
  }).join('');
}

function pageCharges() {
  const st = S.list.charges || (S.list.charges = { search: '', category: 'all' });
  const s = (st.search || '').toLowerCase();
  const list = (S.cfg.charges || []).filter(c =>
    (!s || c.label.toLowerCase().includes(s) || c.id.toLowerCase().includes(s)) &&
    (st.category === 'all' || c.category === st.category));

  const cats = [...new Set((S.cfg.charges || []).map(c => c.category))];
  const classes = S.cfg.chargeClasses || {};
  const grouped = {};
  list.forEach(c => { (grouped[c.category] = grouped[c.category] || []).push(c); });

  const sections = Object.keys(grouped).map(cat => `
    <section class="panel">
      <div class="p-head"><div><h2>${esc(cat)}</h2><p>${plural(grouped[cat].length, 'charge')}</p></div></div>
      <div class="p-body">
        ${grouped[cat].map(c => {
          const cl = classes[c.class] || { label: c.class, tone: 'teal' };
          const inCalc = S.calc.find(x => x.id === c.id);
          return `<button class="row" data-act="calc-add" data-id="${esc(c.id)}" title="Add to the calculator">
            <span class="chip ${toneChip(cl.tone)}">${esc(cl.label)}</span>
            <div class="row-txt"><b>${esc(c.label)}</b><span>${esc(c.id)}${c.points ? ` · ${plural(c.points, 'licence point')}` : ''}</span></div>
            <div class="row-num"><b>${money(c.fine)}</b><span>${c.jail} months</span></div>
            ${inCalc ? `<span class="tag live">×${inCalc.counts}</span>` : `<span class="icobtn">${ICON.plus}</span>`}
          </button>`;
        }).join('')}
      </div>
    </section>`).join('') || emptyState('file', 'Nothing matches', 'Try a different search or category.');

  const t = calcTotals(S.calc);

  return `
    <div class="head">
      <div><h1>Penal Code</h1><p>Fines and sentences apply per count. Tap a charge to add it to the sentence calculator.</p></div>
    </div>
    <div class="filters">
      ${searchField('charge-search', st.search, 'Search the penal code')}
      ${filterSelect('charge-cat', st.category, [['all', 'All categories']].concat(cats.map(c => [c, c])))}
    </div>
    <div class="cols wide-left">
      <div class="stack">${sections}</div>
      <section class="panel" style="position:sticky;top:0">
        <div class="p-head">
          <div><h2>Sentence calculator</h2><p>${plural(S.calc.length, 'charge')} selected</p></div>
          ${S.calc.length ? `<button class="btn-ghost danger" data-act="calc-clear">${ICON.trash} Clear</button>` : ''}
        </div>
        <div class="p-body tight">
          <div class="chargelist">${chargeRows(S.calc, 'calc') || `<div class="wempty">Pick charges from the list.</div>`}</div>
          <div class="totals three" style="margin-top:1.2vh">
            <div class="total"><span>fine</span><b class="teal">${money(t.fine)}</b></div>
            <div class="total"><span>jail</span><b class="amber">${t.jail}m</b></div>
            <div class="total"><span>points</span><b class="${t.points ? 'red' : ''}">${t.points}</b></div>
          </div>
          ${can('incident.create') && S.calc.length ? `<button class="btn-teal solid wide" style="margin-top:1.2vh" data-act="calc-report">${fa('file-pen')} Start a report with these</button>` : ''}
        </div>
      </section>
    </div>`;
}

/* ═══════════════════════════════════════════════════════════════════════════
   EVIDENCE
   ═══════════════════════════════════════════════════════════════════════════ */
function pageEvidence() {
  const st = S.list.evidence || { search: '', status: 'all', page: 1, res: null };
  const r = st.res;

  const cards = !r ? skeleton(6) : (!r.rows || r.rows.length === 0
    ? emptyState('box', 'Nothing in the lockers', 'Log an item and its chain of custody starts here.')
    : r.rows.map(e => `
      <button class="rcard" data-act="evidence-open" data-id="${e.id}">
        <div class="rcard-top">
          <div class="ic ${e.status === 'out' ? 'amber' : e.status === 'destroyed' ? 'red' : ''}">${icon(EV_ICON[e.type] || 'box')}</div>
          <b>${esc(e.description)}</b>
        </div>
        <div class="rcard-meta">
          <div>${ICON.flag}<span>${esc(e.type)}</span></div>
          <div>${ICON.pin}<span>${esc(e.location || 'no location')}</span></div>
          <div>${ICON.lock}<span>${esc(e.locker || 'unassigned locker')}</span></div>
          <div>${ICON.user}<span>${esc(e.collectedBy)}${e.holder ? ' · held by ' + esc(e.holder) : ''}</span></div>
        </div>
        <div class="rcard-foot">
          <span class="tag ${e.status === 'in' ? 'live' : e.status === 'out' ? 'warn' : 'off'}">${e.status === 'in' ? 'Checked in' : e.status === 'out' ? 'Checked out' : esc(e.status)}</span>
          <span class="id">${esc(e.ref)}${e.incidentRef ? ' · ' + esc(e.incidentRef) : ''}</span>
          ${chev()}
        </div>
      </button>`).join(''));

  return `
    <div class="head">
      <div><h1>Evidence</h1><p>Case evidence with locker assignment and a full chain of custody.</p></div>
      <div class="head-act">
        ${can('evidence.create') ? `<button class="btn-teal solid" data-act="evidence-new">${ICON.plus} Log evidence</button>` : ''}
      </div>
    </div>
    <div class="filters">
      ${searchField('evidence-search', st.search, 'Search by reference, description, location or locker')}
      ${filterSelect('evidence-status', st.status, [['all', 'All items'], ['in', 'Checked in'], ['out', 'Checked out'], ['released', 'Released'], ['destroyed', 'Destroyed']])}
    </div>
    <section class="panel"><div class="p-body grid4">${cards}</div></section>
    ${pager(r, 'evidence-page')}`;
}

/* ═══════════════════════════════════════════════════════════════════════════
   CITIZENS · VEHICLES · WEAPONS · PROPERTIES
   ═══════════════════════════════════════════════════════════════════════════ */
function pageCitizens() {
  const st = S.list.citizens || { search: '', page: 1, res: null };
  const r = st.res;

  const cards = !r ? skeleton(6) : (!r.rows || r.rows.length === 0
    ? emptyState('user', 'No citizen matches', 'Try a name, phone number, citizen ID, DOB, print or DNA.')
    : r.rows.map(c => `
      <button class="rcard ${(c.flags || []).some(f => f.tone === 'red') ? 'hot' : ''}" data-act="citizen-open" data-id="${esc(c.id)}">
        <div class="rcard-top">
          <div class="av teal">${c.mugshot ? `<img src="${esc(c.mugshot)}" alt="">` : initials(c.name)}</div>
          <b>${esc(c.name)}</b>
        </div>
        <div class="rcard-meta">
          <div>${ICON.cal}<span>${esc(c.dob || 'DOB unknown')}</span></div>
          <div>${ICON.phone}<span>${esc(c.phone || 'no number')}</span></div>
          <div>${ICON.user}<span>${esc(c.gender || 'unspecified')}${c.job ? ' · ' + esc(c.job) : ''}</span></div>
        </div>
        <div class="rcard-foot">
          ${(c.flags || []).slice(0, 1).map(f => `<span class="chip ${toneChip(f.tone)}">${esc(f.label)}</span>`).join('')}
          <span class="id">${esc(c.id)}</span>
          ${chev()}
        </div>
      </button>`).join(''));

  return `
    <div class="head">
      <div><h1>Citizens</h1><p>Profiles, criminal history, licences and everything registered to a person.</p></div>
      <div class="head-act">
        ${can('citizen.create') ? `<button class="btn-teal solid" data-act="citizen-new">${ICON.plus} Register a citizen</button>` : ''}
      </div>
    </div>
    <div class="filters">
      ${searchField('citizen-search', st.search, 'Search by name, ID, phone, DOB, fingerprint or DNA')}
    </div>
    <section class="panel"><div class="p-body grid4">${cards}</div></section>
    ${pager(r, 'citizen-page')}`;
}

function pageVehicles() {
  const st = S.list.vehicles || { search: '', page: 1, filter: 'all', res: null };
  const r = st.res;

  const cards = !r ? skeleton(6) : (!r.rows || r.rows.length === 0
    ? emptyState('car', 'No vehicle matches', 'Run a plate, a model or an owner name.')
    : r.rows.map(v => `
      <button class="rcard ${v.stolen ? 'hot' : ''}" data-act="vehicle-open" data-id="${esc(v.plate)}">
        <div class="rcard-top">
          <div class="ic ${v.stolen ? 'red' : 'blue'}">${v.photo ? `<img src="${esc(v.photo)}" style="width:100%;height:100%;object-fit:cover;border-radius:inherit" alt="">` : ICON.car}</div>
          <b style="font-family:var(--font-mono)">${esc(v.plate)}</b>
        </div>
        <div class="rcard-meta">
          <div>${ICON.car}<span>${esc(v.model || 'unknown model')}${v.colour ? ' · ' + esc(v.colour) : ''}</span></div>
          <div>${ICON.user}<span>${esc(v.ownerName || 'unregistered')}</span></div>
          <div>${ICON.file}<span>${esc(v.type || 'no class')}</span></div>
        </div>
        <div class="rcard-foot">
          ${v.stolen ? '<span class="chip red">STOLEN</span>' : ''}
          ${v.impounded ? '<span class="chip amber">IMPOUND</span>' : ''}
          ${v.registration && v.registration !== 'valid' ? `<span class="chip amber">REG ${esc(String(v.registration).toUpperCase())}</span>` : ''}
          <span class="id">${esc(v.vin || '')}</span>
          ${chev()}
        </div>
      </button>`).join(''));

  return `
    <div class="head">
      <div><h1>Vehicles</h1><p>Registration, ownership and stolen-vehicle flags.</p></div>
      <div class="head-act">
        <button class="btn-line" data-act="plate-nearby">${fa('car-side')} Read nearby plate</button>
        ${can('vehicle.create') ? `<button class="btn-teal solid" data-act="vehicle-new">${ICON.plus} Register a vehicle</button>` : ''}
      </div>
    </div>
    <div class="filters">
      ${searchField('vehicle-search', st.search, 'Search by plate, model, VIN or owner')}
      ${filterSelect('vehicle-filter', st.filter, [['all', 'All vehicles'], ['stolen', 'Reported stolen'], ['impounded', 'Impounded']])}
    </div>
    <section class="panel"><div class="p-body grid4">${cards}</div></section>
    ${pager(r, 'vehicle-page')}`;
}

function pageWeapons() {
  const st = S.list.weapons || { search: '', page: 1, res: null };
  const r = st.res;

  const cards = !r ? skeleton(6) : (!r.rows || r.rows.length === 0
    ? emptyState('shield', 'No firearm matches', 'Search by serial, model or registered owner.')
    : r.rows.map(w => `
      <button class="rcard ${w.status === 'stolen' ? 'hot' : ''}" data-act="weapon-open" data-id="${esc(w.serial)}">
        <div class="rcard-top"><div class="ic ${w.status === 'stolen' ? 'red' : 'grey'}">${ICON.gun}</div><b>${esc(w.label)}</b></div>
        <div class="rcard-meta">
          <div>${fa('barcode')}<span>${esc(w.serial)}</span></div>
          <div>${ICON.user}<span>${esc(w.ownerName || 'no registered owner')}</span></div>
        </div>
        <div class="rcard-foot">
          <span class="tag ${w.status === 'registered' ? 'live' : w.status === 'stolen' ? 'hot' : 'off'}">${esc(w.status)}</span>
          <span class="id">${esc(w.weapon || '')}</span>
          ${chev()}
        </div>
      </button>`).join(''));

  return `
    <div class="head">
      <div><h1>Weapons</h1><p>Serial tracking, registration and ownership across the city.</p></div>
      <div class="head-act">
        ${can('weapon.create') ? `<button class="btn-teal solid" data-act="weapon-new">${ICON.plus} Register a firearm</button>` : ''}
      </div>
    </div>
    <div class="filters">
      ${searchField('weapon-search', st.search, 'Search by serial, model or owner')}
    </div>
    <section class="panel"><div class="p-body grid4">${cards}</div></section>
    ${pager(r, 'weapon-page')}`;
}

function pageProperties() {
  const st = S.list.properties || { search: '', page: 1, res: null };
  const r = st.res;

  const cards = !r ? skeleton(6) : (!r.rows || r.rows.length === 0
    ? emptyState('house', 'No property matches', 'Search by name, address or registered owner.')
    : r.rows.map(p => `
      <div class="rcard">
        <div class="rcard-top"><div class="ic green" style="color:var(--success)">${ICON.house}</div><b>${esc(p.label)}</b></div>
        <div class="rcard-meta">
          <div>${ICON.pin}<span>${esc(p.address)}</span></div>
          <div>${ICON.user}<span>${esc(p.owner_name || 'no registered owner')}</span></div>
          <div>${ICON.file}<span>${esc(p.type)}</span></div>
        </div>
        <div class="rcard-foot">
          ${p.owner_id && can('view.citizen') ? `<button class="btn-ghost" data-act="citizen-open" data-id="${esc(p.owner_id)}">${ICON.user} Owner</button>` : ''}
          ${can('property.delete') ? `<button class="icobtn danger push" data-act="property-delete" data-id="${p.id}" title="Remove">${ICON.trash}</button>` : ''}
        </div>
      </div>`).join(''));

  return `
    <div class="head">
      <div><h1>Properties</h1><p>Registered addresses and who holds them.</p></div>
      <div class="head-act">
        ${can('property.create') ? `<button class="btn-teal solid" data-act="property-new">${ICON.plus} Register a property</button>` : ''}
      </div>
    </div>
    <div class="filters">
      ${searchField('property-search', st.search, 'Search by name, address or owner')}
    </div>
    <section class="panel"><div class="p-body grid3">${cards}</div></section>
    ${pager(r, 'property-page')}`;
}

/* ═══════════════════════════════════════════════════════════════════════════
   ROSTER
   ═══════════════════════════════════════════════════════════════════════════ */
function pageOfficers() {
  const st = S.list.officers || { search: '', onDuty: false, rows: null };
  const rows = st.rows;
  const depts = S.cfg.departments || {};

  const cards = !rows ? skeleton(6) : (rows.length === 0
    ? emptyState('badge', 'No officer matches', 'Search by name, callsign or badge number.')
    : rows.map(o => {
      const st2 = statusInfo(o.status);
      return `<div class="rcard">
        <div class="rcard-top">
          <div class="av ${o.onDuty ? 'teal' : ''}">${initials(o.name)}</div>
          <b>${esc(o.name)}</b>
        </div>
        <div class="rcard-meta">
          <div>${ICON.badge}<span>${esc(o.rank || 'no rank')} · ${esc((depts[o.department] || {}).short || o.department)}</span></div>
          <div>${fa('hashtag')}<span>${esc(o.callsign || 'no callsign')}${o.badge ? ' · ' + esc(o.badge) : ''}</span></div>
          <div>${ICON.clock}<span>${o.totalHours}h logged${o.onDuty ? ` · ${o.shiftMinutes}m this shift` : ''}</span></div>
          ${o.street ? `<div>${ICON.pin}<span>${esc(o.street)}</span></div>` : ''}
        </div>
        <div class="rcard-foot">
          <span class="tag ${o.onDuty ? 'ok' : 'off'}">${o.onDuty ? 'On duty' : 'Off duty'}</span>
          ${o.onDuty ? `<span class="chip ${toneChip(st2.tone)}">${esc(st2.label)}</span>` : ''}
          ${can('officer.manage') ? `<button class="icobtn push" data-act="officer-edit" data-id="${esc(o.identifier)}" title="Edit">${ICON.pen}</button>` : ''}
        </div>
      </div>`;
    }).join(''));

  const onCount = (rows || []).filter(o => o.onDuty).length;

  return `
    <div class="head">
      <div><h1>Roster</h1><p>Callsigns, duty status and time logged. ${rows ? `${onCount} of ${rows.length} shown are on duty.` : ''}</p></div>
      <div class="head-act">
        <button class="btn-line" data-act="callsign">${ICON.badge} Set my callsign</button>
        <button class="${S.me.onDuty ? 'btn-red' : 'btn-teal solid'}" data-act="duty">${fa('power-off')} ${S.me.onDuty ? 'Clock out' : 'Clock in'}</button>
      </div>
    </div>
    <div class="filters">
      ${searchField('officer-search', st.search, 'Search by name, callsign or badge')}
      <button class="btn-ghost ${st.onDuty ? 'on' : ''}" data-act="officer-onduty">${fa('circle-dot')} On duty only</button>
    </div>
    <section class="panel"><div class="p-body grid3">${cards}</div></section>`;
}

/* ═══════════════════════════════════════════════════════════════════════════
   CAMERAS
   ═══════════════════════════════════════════════════════════════════════════ */
function pageCameras() {
  const st = S.list.cameras || { search: '', status: 'all', res: null };
  const r = st.res;
  const rows = (r && r.rows) || [];
  const clock = new Date().toLocaleTimeString('en-GB', { hour12: false });

  const cards = !r ? skeleton(6) : (rows.length === 0
    ? emptyState('cam', 'No cameras on the network', 'Place one in the world and it shows up here.')
    : rows.map(c => {
      const dead = c.status === 'destroyed';
      return `<div class="camcard ${dead ? 'dead' : ''}">
        <button class="camfeed" ${dead ? 'disabled' : ''} data-act="camera-view" data-id="${esc(c.id)}" title="Watch the feed">
          ${dead ? fa('video-slash') : ICON.cam}
          ${dead ? '' : `<span class="rec"><b></b>LIVE</span><span class="ts">${esc(clock)}</span>`}
        </button>
        <div class="cambody">
          <b>${esc(c.label)}</b>
          <span>${esc(c.id)} · ${(c.departments || []).length ? (c.departments || []).join(', ') : 'all departments'}</span>
        </div>
        <div class="camfoot">
          <span class="tag ${dead ? 'hot' : 'live'}">${dead ? 'Offline' : 'Online'}</span>
          ${c.fixed ? '<span class="chip off">FIXED</span>' : ''}
          <div class="push">
            ${dead && can('camera.manage') ? `<button class="btn-ghost" data-act="camera-repair" data-id="${esc(c.id)}">${fa('screwdriver-wrench')} Repair</button>` : ''}
            ${!dead && can('camera.manage') ? `<button class="icobtn" title="Edit" data-act="camera-edit" data-id="${esc(c.id)}">${ICON.pen}</button>` : ''}
            ${can('camera.manage') && !c.fixed ? `
              <button class="icobtn" title="Reposition" data-act="camera-move" data-id="${esc(c.id)}" data-model="${esc(c.model)}">${fa('up-down-left-right')}</button>
              <button class="icobtn danger" title="Remove" data-act="camera-delete" data-id="${esc(c.id)}">${ICON.trash}</button>` : ''}
          </div>
        </div>
      </div>`;
    }).join(''));

  const online = rows.filter(c => c.status !== 'destroyed').length;
  const offline = rows.length - online;

  return `
    <div class="head">
      <div><h1>Cameras</h1><p>Live CCTV across the city. Open a feed — arrow keys pan and tilt, scroll zooms, ESC comes back.</p></div>
      <div class="head-act">
        ${can('camera.place') && r && r.placeable ? `<button class="btn-teal solid" data-act="camera-new">${ICON.plus} Place a camera</button>` : ''}
      </div>
    </div>
    <div class="stats three">
      ${statTile('cam', 'Online', online, 'transmitting now')}
      ${statTile('warn', 'Offline', offline, 'shot out or faulty', offline > 0 ? 'red' : '')}
      ${statTile('shield', 'Network', rows.length, 'total cameras', 'blue')}
    </div>
    <div class="filters">
      ${searchField('camera-search', st.search, 'Search by name or camera ID')}
      ${filterSelect('camera-status', st.status, [['all', 'All cameras'], ['online', 'Online'], ['destroyed', 'Offline']])}
    </div>
    <section class="panel"><div class="p-body grid3">${cards}</div></section>`;
}

/* ═══════════════════════════════════════════════════════════════════════════
   BULLETINS · AUDIT
   ═══════════════════════════════════════════════════════════════════════════ */
function pageAnnouncements() {
  const rows = (S.list.announcements || {}).rows;

  const cards = !rows ? skeleton(3) : (rows.length === 0
    ? emptyState('speaker', 'No bulletins posted', 'Command posts department-wide notices here.')
    : rows.map(a => `
      <section class="panel">
        <div class="p-head">
          <div><h2>${a.pinned ? fa('thumbtack') + ' ' : ''}${esc(a.title)}</h2><p>${esc(a.author)} · ${esc(a.stamp)}${a.department ? '' : ' · all departments'}</p></div>
          <div class="acts">
            ${a.pinned ? '<span class="chip">PINNED</span>' : ''}
            ${can('announcement.create') ? `<button class="icobtn danger" data-act="announce-delete" data-id="${a.id}" title="Remove">${ICON.trash}</button>` : ''}
          </div>
        </div>
        <div class="p-body tight"><p class="prose">${esc(a.body)}</p></div>
      </section>`).join(''));

  return `
    <div class="head">
      <div><h1>Bulletins</h1><p>Notices from command to everyone on the roster.</p></div>
      <div class="head-act">
        ${can('announcement.create') ? `<button class="btn-teal solid" data-act="announce-new">${ICON.plus} Post a bulletin</button>` : ''}
      </div>
    </div>
    <div class="stack">${cards}</div>`;
}

function pageAudit() {
  const st = S.list.audit || { search: '', page: 1, res: null };
  const r = st.res;

  const body = !r ? skeleton(6) : (!r.rows || r.rows.length === 0
    ? emptyState('clock', 'Nothing logged', 'Every write to the MDT is recorded here.')
    : `<table>
        <thead><tr><th>officer</th><th>action</th><th>subject</th><th>detail</th><th class="right">when</th></tr></thead>
        <tbody>${r.rows.map(a => `<tr>
          <td><b>${esc(a.actor)}</b><small>${esc(a.department || '')}</small></td>
          <td><span class="chip off">${esc(a.action)}</span></td>
          <td>${esc(a.subject || '')}${a.subject_id ? ` <b>${esc(a.subject_id)}</b>` : ''}</td>
          <td>${esc(a.detail || '')}</td>
          <td class="right" style="white-space:nowrap">${esc(a.stamp)}</td>
        </tr>`).join('')}</tbody>
      </table>${pager(r, 'audit-page')}`);

  return `
    <div class="head">
      <div><h1>Audit Log</h1><p>Who touched what, and when. Kept for the retention window set in the config.</p></div>
    </div>
    <div class="filters">
      ${searchField('audit-search', st.search, 'Search by officer, action, subject or detail')}
    </div>
    <section class="panel"><div class="p-body tight">${body}</div></section>`;
}

/* ═══════════════════════════════════════════════════════════════════════════
   10-CODES
   ═══════════════════════════════════════════════════════════════════════════ */
function pageCodes() {
  const st = S.list.codes || (S.list.codes = { search: '' });
  const s = (st.search || '').toLowerCase();
  const match = (a, b) => !s || String(a || '').toLowerCase().includes(s) || String(b || '').toLowerCase().includes(s);

  const codes = (S.cfg.tenCodes || []).filter(c => match(c.code, c.label));
  const calls = (S.cfg.callTypes || []).filter(c => match(c.code, c.label));

  return `
    <div class="head">
      <div><h1>10-Codes</h1><p>Radio codes and the call types dispatch uses, in one place.</p></div>
    </div>
    <div class="filters">${searchField('codes-search', st.search, 'Search a code or a meaning')}</div>
    <div class="cols">
      <section class="panel">
        <div class="p-head"><div><h2>Radio codes</h2><p>${plural(codes.length, 'code')}</p></div></div>
        <div class="p-body">
          ${codes.map(c => `<div class="row code-row"><span class="code">${esc(c.code)}</span><div class="row-txt"><b>${esc(c.label)}</b></div></div>`).join('')
            || emptyState('list', 'Nothing matches', 'Try another search.')}
        </div>
      </section>
      <section class="panel">
        <div class="p-head"><div><h2>Call types</h2><p>${plural(calls.length, 'type')}</p></div></div>
        <div class="p-body">
          ${calls.map(c => `<div class="row code-row">
            <span class="code">${esc(c.code)}</span>
            <div class="row-txt"><b>${esc(c.label)}</b><span>${esc(c.group)}</span></div>
            <span class="chip ${toneChip(priorityTone(c.priority))}">P${c.priority}</span>
          </div>`).join('') || emptyState('list', 'Nothing matches', 'Try another search.')}
        </div>
      </section>
    </div>`;
}

/* ═══════════════════════════════════════════════════════════════════════════
   NOTEPAD — personal notes, saved on the officer's own client
   ═══════════════════════════════════════════════════════════════════════════ */
function pageNotepad() {
  const notes = S.notes || [];
  const sel = notes.find(n => n.id === S.noteSel) || notes[0] || null;
  if (sel) S.noteSel = sel.id;

  return `
    <div class="head">
      <div><h1>Notepad</h1><p>Personal scratch notes. They live on your tablet only — nobody else can read them.</p></div>
      <div class="head-act">
        <button class="btn-teal solid" data-act="note-new">${ICON.plus} New note</button>
      </div>
    </div>
    <div class="notepad">
      <div class="list">
        ${notes.map(n => `<button class="item ${sel && n.id === sel.id ? 'on' : ''}" data-act="note-pick" data-id="${esc(n.id)}">
          <b>${esc(n.title || 'Untitled')}</b><span>${esc(new Date(n.updated || Date.now()).toLocaleString('en-GB', { hour12: false }))}</span>
        </button>`).join('') || `<div class="wempty">No notes yet.</div>`}
      </div>
      ${sel ? `<div class="editor">
        <input id="noteTitle" maxlength="80" value="${esc(sel.title || '')}" placeholder="Title">
        <textarea id="noteText" maxlength="6000" placeholder="Plates, names, timelines…">${esc(sel.body || '')}</textarea>
        <div class="btnrow">
          <span class="saved" id="noteSaved">saved</span>
          <button class="btn-ghost danger push" data-act="note-delete" data-id="${esc(sel.id)}">${ICON.trash} Delete note</button>
        </div>
      </div>` : `<div class="editor">${emptyState('note', 'Nothing here yet', 'Start a note — it saves as you type.')}</div>`}
    </div>`;
}

let noteTimer = null;
function saveNotesSoon() {
  const flag = $('#noteSaved');
  if (flag) flag.textContent = 'saving…';
  clearTimeout(noteTimer);
  noteTimer = setTimeout(async () => {
    await raw('notepad:set', { notes: S.notes });
    if (!IN_GAME) { try { localStorage.setItem('nz_mdt_notes', JSON.stringify(S.notes)); } catch (e) {} }
    const f = $('#noteSaved');
    if (f) f.textContent = 'saved';
  }, 600);
}

/* ═══════════════════════════════════════════════════════════════════════════
   SETTINGS
   ═══════════════════════════════════════════════════════════════════════════ */
function pageSettings() {
  const st = S.settings;
  const walls = wallpaperList();
  const curWall = (walls.find(w => w.id === st.wallpaper) || walls.find(w => w.id === (S.cfg.tablet || {}).wallpaper) || walls[0] || {}).id;
  const scales = [0.85, 0.9, 0.95, 1, 1.05, 1.1];
  const toggle = (key, title, text) => `<div class="check">
      <div><b>${esc(title)}</b><span>${esc(text)}</span></div>
      <label class="switch"><input type="checkbox" data-setting="${key}" ${st[key] !== false ? 'checked' : ''}><i></i></label>
    </div>`;

  const shortcuts = [['/', 'Search everything'], ['ESC', 'Back · home · put away']]
    .concat(Object.keys(APPS).filter(id => APPS[id].key && appAllowed(id)).map(id => [APPS[id].key.toUpperCase(), APPS[id].label]));

  return `
    <div class="head">
      <div><h1>Settings</h1><p>These stay with you on this tablet.</p></div>
    </div>
    <div class="cols">
      <div class="stack">
        <section class="panel">
          <div class="p-head"><div><h2>Wallpaper</h2><p>home &amp; lock screen</p></div></div>
          <div class="p-body tight">
            <div class="wallpicks">
              ${walls.map(w => `<button class="wallpick ${w.id === curWall ? 'on' : ''}" data-act="set-wall" data-id="${esc(w.id)}">
                <img src="${esc(w.file)}" alt="" loading="lazy"><span>${esc(w.label)}</span></button>`).join('')}
            </div>
          </div>
        </section>
        <section class="panel">
          <div class="p-head"><div><h2>Display</h2><p>tablet size on screen</p></div></div>
          <div class="p-body tight">
            <div class="seg">
              ${scales.map(s => `<button class="${Math.abs((Number(st.scale) || 1) - s) < 0.001 ? 'on' : ''}" data-act="set-scale" data-scale="${s}">${Math.round(s * 100)}%</button>`).join('')}
            </div>
          </div>
        </section>
        <section class="panel">
          <div class="p-head"><div><h2>Shortcuts</h2><p>while the tablet is open</p></div></div>
          <div class="p-body tight">
            ${shortcuts.map(([k, l]) => `<div class="kv"><span>${esc(l)}</span><span class="kbd">${esc(k)}</span></div>`).join('')}
          </div>
        </section>
      </div>
      <div class="stack">
        <section class="panel">
          <div class="p-head"><div><h2>Behaviour</h2><p>startup &amp; alerts</p></div></div>
          <div class="p-body tight">
            ${toggle('lockAnimation', 'Lock screen animation', 'Type the passcode on the lock screen when the tablet comes out.')}
            ${toggle('bootConsole', 'Boot console', 'Show the command prompt the first time you unlock each session.')}
            ${toggle('notifications', 'Tablet notifications', 'Pop a notification on the tablet for new calls, BOLOs and warrants.')}
            ${toggle('sounds', 'Dispatch tones', 'Play the alert tone in game when a call or a panic comes in.')}
            ${toggle('widgetAuto', 'Dispatch card on new calls', 'Show the on-screen card automatically while the tablet is put away.')}
          </div>
        </section>
        <section class="panel">
          <div class="p-head"><div><h2>About</h2><p>this terminal</p></div></div>
          <div class="p-body tight">
            <div class="kv"><span>Version</span><b>v${esc(S.cfg.version || '2.0.0')}</b></div>
            <div class="kv"><span>Department</span><b>${esc(S.me.deptLabel || S.me.department)}</b></div>
            <div class="kv"><span>Officer</span><b>${esc(S.me.name)}</b></div>
            <div class="kv"><span>Rank</span><b>${esc(S.me.rank || '—')}</b></div>
            <div class="kv"><span>Permissions</span><b>${Object.keys(S.perms).length}</b></div>
            <div class="btnrow" style="margin-top:1.2vh">
              <button class="btn-line" data-act="settings-reset">${ICON.refresh} Reset to defaults</button>
            </div>
          </div>
        </section>
      </div>
    </div>`;
}

/* ═══════════════════════════════════════════════════════════════════════════
   ROUTER
   ═══════════════════════════════════════════════════════════════════════════ */
const PAGES = {
  dashboard: pageDashboard, dispatch: pageDispatch, bolos: pageBolos, warrants: pageWarrants,
  incidents: pageIncidents, charges: pageCharges, evidence: pageEvidence, citizens: pageCitizens,
  vehicles: pageVehicles, weapons: pageWeapons, properties: pageProperties, officers: pageOfficers,
  cameras: pageCameras, announcements: pageAnnouncements, audit: pageAudit,
  codes: pageCodes, notepad: pageNotepad, settings: pageSettings
};

function render(resetScroll) {
  if (!S.me || !S.page || !S.windowUp) return;
  const view = $('#view');
  const fn = PAGES[S.page] || pageDashboard;

  // hold on to whatever the officer is typing in a search box
  const active = document.activeElement;
  const typing = active && view.contains(active) && active.dataset && active.dataset.act && active.dataset.act.endsWith('-search')
    ? { act: active.dataset.act, value: active.value, pos: active.selectionStart } : null;
  const scroll = view.scrollTop;

  view.innerHTML = fn();
  view.scrollTop = resetScroll ? 0 : scroll;

  if (typing) {
    const input = view.querySelector(`[data-act="${typing.act}"]`);
    if (input) {
      input.value = typing.value;
      input.focus();
      try { input.setSelectionRange(typing.pos, typing.pos); } catch (e) {}
    }
  }

  if (S.page === 'dispatch') mapApply();
}

function stamp() {
  setFooterRight('synced ' + new Date().toLocaleTimeString('en-GB', { hour12: false }));
}

async function loadPage(page) {
  switch (page) {
    case 'dashboard': await loadDash(); break;
    case 'dispatch': {
      const r = await post('nz_mdt:dispatch:board', S.board.includeClosed);
      if (r && r.ok) {
        S.board.calls = r.calls || [];
        S.board.officers = r.officers || [];
        if (S.board.selected && !S.board.calls.some(c => c.id === S.board.selected)) S.board.selected = null;
      }
      break;
    }
    case 'bolos': {
      const st = S.list.bolos = S.list.bolos || { search: '', filter: 'active', rows: null };
      const r = await post('nz_mdt:bolo:list', st.search, st.filter);
      st.rows = (r && r.rows) || [];
      break;
    }
    case 'warrants': {
      const st = S.list.warrants = S.list.warrants || { search: '', filter: 'active', rows: null };
      const r = await post('nz_mdt:warrant:list', st.search, st.filter);
      st.rows = (r && r.rows) || [];
      break;
    }
    case 'incidents': {
      const st = S.list.incidents = S.list.incidents || { search: '', status: 'all', page: 1, res: null, mine: false };
      st.res = await post('nz_mdt:incident:list', st.search, st.page, st.status, st.mine === true);
      break;
    }
    case 'evidence': {
      const st = S.list.evidence = S.list.evidence || { search: '', status: 'all', page: 1, res: null };
      st.res = await post('nz_mdt:evidence:list', st.search, st.page, st.status);
      break;
    }
    case 'citizens': {
      const st = S.list.citizens = S.list.citizens || { search: '', page: 1, res: null };
      st.res = await post('nz_mdt:citizen:list', st.search, st.page);
      break;
    }
    case 'vehicles': {
      const st = S.list.vehicles = S.list.vehicles || { search: '', page: 1, filter: 'all', res: null };
      st.res = await post('nz_mdt:vehicle:list', st.search, st.page, st.filter);
      break;
    }
    case 'weapons': {
      const st = S.list.weapons = S.list.weapons || { search: '', page: 1, res: null };
      st.res = await post('nz_mdt:weapon:list', st.search, st.page);
      break;
    }
    case 'properties': {
      const st = S.list.properties = S.list.properties || { search: '', page: 1, res: null };
      st.res = await post('nz_mdt:property:list', st.search, st.page);
      break;
    }
    case 'officers': {
      const st = S.list.officers = S.list.officers || { search: '', onDuty: false, rows: null };
      const r = await post('nz_mdt:officer:roster', st.search, st.onDuty);
      st.rows = (r && r.rows) || [];
      break;
    }
    case 'announcements': {
      const st = S.list.announcements = S.list.announcements || {};
      const r = await post('nz_mdt:announce:list');
      st.rows = (r && r.rows) || [];
      break;
    }
    case 'audit': {
      const st = S.list.audit = S.list.audit || { search: '', page: 1, res: null };
      st.res = await post('nz_mdt:audit:list', st.page, st.search);
      break;
    }
    case 'cameras': {
      const st = S.list.cameras = S.list.cameras || { search: '', status: 'all', res: null };
      st.res = await post('nz_mdt:camera:list', st.search, st.status);
      break;
    }
    case 'notepad': {
      const r = await raw('notepad:get');
      if (r && Array.isArray(r.notes)) S.notes = r.notes;
      else if (!IN_GAME) { try { S.notes = JSON.parse(localStorage.getItem('nz_mdt_notes') || '[]'); } catch (e) {} }
      break;
    }
    default: break;
  }
  if (S.page === page && S.windowUp) { render(); stamp(); }
}

async function loadDash() {
  const d = await post('nz_mdt:dashboard');
  if (d && d.ok) {
    S.dash = d;
    S.me.onDuty = d.me.onDuty;
    S.me.callsign = d.me.callsign;
    S.me.status = d.me.status || S.me.status;
    if (d.me.badge) S.me.badge = d.me.badge;
    if (!S.windowUp || S.page !== 'dispatch') {
      S.board.officers = d.officers || S.board.officers;
    }
    renderTaskbar();
    renderHome();
    windowChrome();
  }
}

let dashTimer = null;
function scheduleDash(wait) {
  clearTimeout(dashTimer);
  dashTimer = setTimeout(() => {
    if (!S.visible) return;
    loadDash().then(() => { if (S.page === 'dashboard' && S.windowUp) render(); });
  }, wait == null ? 1500 : wait);
}

/* ═══════════════════════════════════════════════════════════════════════════
   CITIZEN PICKER — type a name, pick a record, the ID fills itself in
   ═══════════════════════════════════════════════════════════════════════════ */
function citizenPicker(name, label, value, display) {
  return `<div class="field picker" data-picker="${esc(name)}">
    <label>${esc(label)}</label>
    <input class="input" data-pick-search placeholder="Search a name or citizen ID" value="${esc(display || value || '')}" autocomplete="off" spellcheck="false">
    <input type="hidden" data-name="${esc(name)}" value="${esc(value || '')}">
    <div class="chargelist" data-pick-results style="margin-top:0.6vh"></div>
  </div>`;
}

let pickTimer = null;
function pickerSearch(input) {
  const box = input.closest('[data-picker]');
  if (!box) return;
  const hidden = box.querySelector('input[type=hidden]');
  const results = box.querySelector('[data-pick-results]');
  // typing a raw citizen ID is still allowed
  hidden.value = /^CZ[A-Z0-9]{4,}$/i.test(input.value.trim()) ? input.value.trim().toUpperCase() : '';

  clearTimeout(pickTimer);
  const term = input.value.trim();
  if (term.length < 2) { results.innerHTML = ''; return; }
  pickTimer = setTimeout(async () => {
    const r = await post('nz_mdt:citizen:list', term, 1);
    const rows = (r && r.rows) || [];
    results.innerHTML = rows.slice(0, 5).map(c => `
      <div class="chargerow pick" data-inner="pick" data-cid="${esc(c.id)}" data-cname="${esc(c.name)}">
        <div class="av sm teal">${initials(c.name)}</div><b>${esc(c.name)}</b>
        <span class="cost">${esc(c.id)} · ${esc(c.dob || 'DOB ?')}</span>
      </div>`).join('') || `<div class="wempty">No citizen matched that.</div>`;
  }, 250);
}

/* ═══════════════════════════════════════════════════════════════════════════
   DISPATCH MODALS
   ═══════════════════════════════════════════════════════════════════════════ */
async function callCreateModal() {
  const loc = await raw('myLocation');
  const types = (S.cfg.callTypes || []).map(t =>
    `<option value="${esc(t.id)}">${esc(t.code)} · ${esc(t.label)}</option>`).join('');

  openModal({
    title: 'dispatch.exe — create call', icon: 'tower-broadcast', child: true,
    lede: 'Everyone on duty in the routed departments gets the alert, a blip and the call on their board.',
    confirm: 'Send it out',
    body: `
      <div class="row2">
        <div class="field"><label>call_type</label><select data-name="type">${types}</select></div>
        <div class="field"><label>priority</label><select data-name="priority">
          <option value="">Use the type default</option>
          <option value="1">1 — Critical</option>
          <option value="2">2 — Priority</option>
          <option value="3">3 — Routine</option>
        </select></div>
      </div>
      <div class="field"><label>headline</label>
        <input data-name="title" maxlength="90" placeholder="Leave blank to use the call type"></div>
      <div class="row2">
        <div class="field"><label>location</label>
          <input data-name="street" maxlength="90" value="${esc((loc && loc.street) || '')}"></div>
        <div class="field"><label>plate_involved</label>
          <input data-name="plate" maxlength="12" placeholder="Optional"></div>
      </div>
      <div class="field"><label>what_was_reported</label>
        <textarea data-name="detail" maxlength="500" placeholder="Caller states two suspects fled north on Route 68."></textarea></div>
      <div class="row2">
        <div class="field"><label>caller</label>
          <input data-name="caller" maxlength="90" value="${esc(S.me.name)}"></div>
        <div class="check" style="border:0;padding:0;align-self:end">
          <div><b>Pin at my position</b><span>Uses where you are standing for the blip.</span></div>
          <label class="switch"><input type="checkbox" data-name="here" checked><i></i></label>
        </div>
      </div>`,
    onConfirm: async (v) => {
      const res = await post('nz_mdt:dispatch:create', {
        type: v.type, title: v.title, detail: v.detail, street: v.street,
        plate: v.plate, caller: v.caller,
        priority: v.priority ? parseInt(v.priority, 10) : null,
        x: v.here && loc ? loc.x : null, y: v.here && loc ? loc.y : null, z: v.here && loc ? loc.z : null
      });
      if (reply(res)) {
        closeModal();
        if (res.call) S.board.selected = res.call.id;
        if (S.page === 'dispatch') loadPage('dispatch'); else openApp('dispatch');
      }
    }
  });
}

function backupModal() {
  openModal({
    title: 'dispatch.exe — request backup', icon: 'people-group', child: true,
    lede: 'Puts a priority call on the board at your position for every unit in your department.',
    confirm: 'Request backup',
    body: `
      <div class="field"><label>urgency</label><select data-name="urgency">
        <option value="3">Code 3 — lights &amp; sirens</option>
        <option value="2">Code 2 — urgent, no lights</option>
        <option value="1">Code 1 — routine assist</option>
      </select></div>
      <div class="field"><label>situation</label>
        <textarea data-name="note" maxlength="300" placeholder="Felony stop, two occupants, one non-compliant."></textarea></div>`,
    onConfirm: async (v) => {
      const res = await raw('backup', { urgency: parseInt(v.urgency, 10) || 3, note: v.note });
      if (reply(res, 'Backup request did not go through.')) closeModal();
    }
  });
}

function panicModal() {
  openModal({
    title: 'panic.exe', icon: 'land-mine-on', child: true, danger: true,
    lede: 'Every unit on duty is alerted with your callsign and position, and a priority call goes on the board.',
    confirm: 'Send panic',
    onConfirm: async () => {
      closeModal();
      const res = await raw('panic');
      if (res && res.ok) notify('Panic sent', 'Every unit on duty has your position.', true);
      else reply(res, 'The panic did not go out.');
    }
  });
}

function callCloseModal(id) {
  openModal({
    title: 'dispatch.exe — close call', icon: 'circle-xmark', child: true,
    lede: 'Every unit attached is released and the call drops off the active board.',
    confirm: 'Close the call', danger: true,
    body: `<div class="field"><label>disposition</label>
      <textarea data-name="note" maxlength="250" placeholder="Two in custody, scene cleared."></textarea></div>`,
    onConfirm: async (v) => {
      const res = await post('nz_mdt:dispatch:close', id, v.note);
      if (reply(res)) { closeModal(); S.board.selected = null; loadPage('dispatch'); }
    }
  });
}

/* ═══════════════════════════════════════════════════════════════════════════
   BOLO / WARRANT
   ═══════════════════════════════════════════════════════════════════════════ */
async function boloModal(existing) {
  const nearby = existing ? null : await raw('nearbyPlate');
  const b = existing || {};

  openModal({
    title: existing && existing.id ? 'bolo-board.exe — edit' : 'bolo-board.exe — issue', icon: 'bell', child: true,
    lede: 'Live BOLOs are matched against every plate the reader picks up.',
    confirm: existing && existing.id ? 'Save changes' : 'Issue it',
    body: `
      <div class="row2">
        <div class="field"><label>kind</label><select data-name="kind">
          <option value="vehicle" ${b.kind === 'vehicle' ? 'selected' : ''}>Vehicle</option>
          <option value="person" ${b.kind === 'person' ? 'selected' : ''}>Person</option>
          <option value="property" ${b.kind === 'property' ? 'selected' : ''}>Property</option>
        </select></div>
        <div class="field"><label>priority</label><select data-name="priority">
          <option value="1" ${b.priority === 1 ? 'selected' : ''}>1 — Critical</option>
          <option value="2" ${!b.priority || b.priority === 2 ? 'selected' : ''}>2 — Priority</option>
          <option value="3" ${b.priority === 3 ? 'selected' : ''}>3 — Routine</option>
        </select></div>
      </div>
      <div class="field"><label>title</label>
        <input data-name="title" maxlength="90" value="${esc(b.title || '')}" placeholder="Armed robbery suspects"></div>
      <div class="row2">
        <div class="field"><label>plate</label>
          <input data-name="plate" maxlength="12" value="${esc(b.plate || (nearby && nearby.plate) || '')}"></div>
        <div class="field"><label>model</label>
          <input data-name="model" maxlength="40" value="${esc(b.model || (nearby && nearby.model) || '')}"></div>
      </div>
      ${citizenPicker('citizenId', 'person (optional)', b.citizenId || '', b.citizenId || '')}
      <div class="field"><label>detail</label>
        <textarea data-name="detail" maxlength="900" placeholder="Two suspects in a black SUV, armed, last seen heading north.">${esc(b.detail || '')}</textarea></div>`,
    onConfirm: async (v) => {
      const payload = {
        title: v.title, kind: v.kind, plate: v.plate, model: v.model, citizenId: v.citizenId,
        detail: v.detail, priority: parseInt(v.priority, 10)
      };
      const res = existing && existing.id
        ? await post('nz_mdt:bolo:update', existing.id, payload)
        : await post('nz_mdt:bolo:create', payload);
      if (reply(res)) { closeModal(); if (S.page === 'bolos') loadPage('bolos'); scheduleDash(); }
    }
  });
}

function warrantModal(prefill) {
  const p = prefill || {};
  const types = (S.cfg.warrantTypes || []).map(t =>
    `<option value="${esc(t.id)}">${esc(t.label)}</option>`).join('');
  const charges = (S.cfg.charges || []).map(c =>
    `<option value="${esc(c.id)}">${esc(c.category)} — ${esc(c.label)}</option>`).join('');

  openModal({
    title: 'warrants.exe — issue', icon: 'gavel', wide: 'wide', child: true,
    lede: 'Every unit on duty is notified, and the citizen record is flagged on the next lookup.',
    confirm: 'Issue it',
    body: `
      <div class="row2">
        ${citizenPicker('citizenId', 'citizen', p.citizenId || '', p.citizenName ? `${p.citizenName} (${p.citizenId})` : (p.citizenId || ''))}
        <div class="field"><label>type</label><select data-name="type">${types}</select></div>
      </div>
      <div class="field"><label>title</label>
        <input data-name="title" maxlength="90" placeholder="Arrest warrant — aggravated assault"></div>
      <div class="field"><label>grounds</label>
        <textarea data-name="detail" maxlength="900" placeholder="Probable cause, what is being sought, and any conditions."></textarea></div>
      <div class="field"><label>charges (ctrl-click for several)</label>
        <select data-name="charges" multiple size="7">${charges}</select></div>`,
    onConfirm: async (v) => {
      if (!v.citizenId) return notify('Not completed', 'Pick the citizen this warrant is for.', true);
      const res = await post('nz_mdt:warrant:create', {
        citizenId: v.citizenId, type: v.type, title: v.title, detail: v.detail, charges: v.charges || []
      });
      if (reply(res)) { closeModal(); if (S.page === 'warrants') loadPage('warrants'); scheduleDash(); }
    }
  });
}

/* ═══════════════════════════════════════════════════════════════════════════
   INCIDENT BUILDER
   ═══════════════════════════════════════════════════════════════════════════ */
function incidentDraft(existing) {
  S.draft = existing || { id: null, title: '', detail: '', location: '', people: [], charges: [], dispatchRef: '' };
}

function incidentBody() {
  const d = S.draft;
  const t = calcTotals(d.charges);

  const people = d.people.map((p, i) => `
    <div class="chargerow">
      <div class="av sm ${i === 0 ? 'teal' : ''}" title="${i === 0 ? 'Primary citizen' : ''}">${initials(p.name)}</div>
      <b>${esc(p.name)}${i === 0 ? ' <span class="chip">PRIMARY</span>' : ''}</b>
      <span class="cost">${esc(p.citizenId)}</span>
      <select class="mini" data-change="person-role" data-i="${i}">
        ${['suspect', 'victim', 'witness', 'officer'].map(r => `<option value="${r}" ${p.role === r ? 'selected' : ''}>${cap(r)}</option>`).join('')}
      </select>
      ${i > 0 ? `<button class="icobtn" data-inner="person-up" data-i="${i}" title="Make primary">${fa('arrow-up')}</button>` : ''}
      <button class="icobtn danger" data-inner="person-del" data-i="${i}">${ICON.x}</button>
    </div>`).join('') || `<div class="wempty">Nobody attached yet.</div>`;

  const chargeOpts = (S.cfg.charges || []).map(c =>
    `<option value="${esc(c.id)}">${esc(c.category)} — ${esc(c.label)} (${money(c.fine)} / ${c.jail}m)</option>`).join('');

  return `
    <div class="row2">
      <div class="field"><label>report_title</label>
        <input data-name="title" maxlength="90" value="${esc(d.title)}" placeholder="Bar fight escalation"></div>
      <div class="field"><label>location</label>
        <input data-name="location" maxlength="120" value="${esc(d.location)}" placeholder="Yellow Jack Inn — Sandy Shores"></div>
    </div>
    <div class="field"><label>linked_dispatch</label>
      <input data-name="dispatchRef" maxlength="20" value="${esc(d.dispatchRef)}" placeholder="DISP-0004"></div>
    <div class="field"><label>narrative</label>
      <textarea data-name="detail" maxlength="2000" style="min-height:12vh" placeholder="What happened, in order, in plain language.">${esc(d.detail)}</textarea></div>

    <div class="cols">
      <div class="field">
        <label>people_involved — the first person is the primary citizen</label>
        <div class="inline">
          <div class="field"><input class="input" id="personSearch" placeholder="Search citizens by name or ID" autocomplete="off"></div>
          <button class="btn-line" data-inner="person-find">${ICON.search} Find</button>
        </div>
        <div id="personResults"></div>
        <div class="chargelist" style="margin-top:0.8vh">${people}</div>
      </div>

      <div class="field">
        <label>charges</label>
        <div class="inline">
          <div class="field"><select id="chargePick">${chargeOpts}</select></div>
          <button class="btn-line" data-inner="draft-add">${ICON.plus} Add</button>
        </div>
        <div class="chargelist" style="margin-top:0.8vh">${chargeRows(d.charges, 'draft') || `<div class="wempty">No charges attached.</div>`}</div>
      </div>
    </div>

    <div class="totals three">
      <div class="total"><span>total_fine</span><b class="teal">${money(t.fine)}</b></div>
      <div class="total"><span>total_jail</span><b class="amber">${t.jail} months</b></div>
      <div class="total"><span>licence_points</span><b class="${t.points ? 'red' : ''}">${t.points}</b></div>
    </div>`;
}

function incidentModal(existing) {
  incidentDraft(existing);
  openModal({
    title: existing && existing.id ? `incident-reports.exe — edit ${existing.ref}` : 'incident-reports.exe — new report',
    icon: 'file-pen', confirm: existing && existing.id ? 'Save the report' : 'File it', wide: 'xwide', child: true,
    body: incidentBody(),
    onConfirm: async (v) => {
      captureDraft(v);
      const payload = {
        id: S.draft.id, title: S.draft.title, detail: S.draft.detail,
        location: S.draft.location, dispatchRef: S.draft.dispatchRef,
        people: S.draft.people, charges: S.draft.charges
      };
      const res = S.draft.id
        ? await post('nz_mdt:incident:update', payload)
        : await post('nz_mdt:incident:create', payload);
      if (reply(res)) {
        closeModal();
        S.calc = [];
        if (S.page === 'incidents') loadPage('incidents');
        else if (S.page === 'charges') render();
        scheduleDash();
      }
    }
  });
}

function captureDraft(v) {
  const values = v || modalValues();
  ['title', 'detail', 'location', 'dispatchRef'].forEach(k => {
    if (values[k] !== undefined) S.draft[k] = values[k] || '';
  });
}

function redrawDraft() {
  captureDraft();
  const box = $('#veil .modal-b');
  if (box) {
    const scroll = box.scrollTop;
    box.innerHTML = incidentBody();
    box.scrollTop = scroll;
  }
}

/* ═══════════════════════════════════════════════════════════════════════════
   INNER MODAL ACTIONS
   ═══════════════════════════════════════════════════════════════════════════ */
function draftCharge(prefix) {
  return prefix === 'calc' ? S.calc : (S.draft ? S.draft.charges : []);
}

function chargeOp(action, i) {
  const [prefix, op] = action.split('-');
  const list = draftCharge(prefix);
  const c = list[i];
  if (op !== 'add' && !c) return false;
  if (op === 'plus') c.counts = Math.min(20, c.counts + 1);
  else if (op === 'minus') c.counts = Math.max(1, c.counts - 1);
  else if (op === 'reduce') c.reduced = !c.reduced;
  else if (op === 'del') list.splice(i, 1);
  else return false;
  return true;
}

async function handleInner(action, el) {
  const i = parseInt(el.dataset.i, 10);

  if (/^draft-(plus|minus|reduce|del)$/.test(action)) {
    if (chargeOp(action, i)) redrawDraft();
    return;
  }

  switch (action) {
    case 'draft-add': {
      const pick = $('#chargePick');
      if (!pick) return;
      if (S.draft.charges.length >= (S.cfg.maxCharges || 25)) return notify('Not completed', 'That report already holds the maximum charges.', true);
      const existing = S.draft.charges.find(c => c.id === pick.value);
      if (existing) existing.counts = Math.min(20, existing.counts + 1);
      else S.draft.charges.push({ id: pick.value, counts: 1, reduced: false, citizenId: (S.draft.people[0] || {}).citizenId });
      redrawDraft();
      break;
    }

    case 'person-find': {
      const input = $('#personSearch');
      const box = $('#personResults');
      if (!input || !box) return;
      if (input.value.trim().length < 2) return notify('Search', 'Type at least two characters.', 'warn');
      box.innerHTML = skeleton(2);
      const r = await post('nz_mdt:citizen:list', input.value, 1);
      box.innerHTML = (r && r.rows && r.rows.length)
        ? `<div class="chargelist" style="margin-top:0.8vh">${r.rows.slice(0, 6).map(c =>
            `<div class="chargerow"><div class="av sm teal">${initials(c.name)}</div><b>${esc(c.name)}</b>
             <span class="cost">${esc(c.id)} · ${esc(c.dob || '')}</span>
             <button class="btn-ghost" data-inner="person-add" data-cid="${esc(c.id)}" data-cname="${esc(c.name)}">${ICON.plus} Add</button></div>`).join('')}</div>`
        : `<div class="wempty">No citizen matched that.</div>`;
      break;
    }
    case 'person-add': {
      const cid = el.dataset.cid, name = el.dataset.cname;
      if (S.draft.people.some(p => p.citizenId === cid)) return notify('Already added', `${name} is on this report.`, 'warn');
      if (S.draft.people.length >= (S.cfg.maxCitizens || 10)) return notify('Not completed', 'That report already holds the maximum people.', true);
      S.draft.people.push({ citizenId: cid, name, role: 'suspect' });
      // charges added before anyone was attached belong to the first person
      S.draft.charges.forEach(c => { if (!c.citizenId) c.citizenId = S.draft.people[0].citizenId; });
      redrawDraft();
      break;
    }
    case 'person-del': S.draft.people.splice(i, 1); redrawDraft(); break;
    case 'person-up': {
      const [p] = S.draft.people.splice(i, 1);
      S.draft.people.unshift(p);
      redrawDraft();
      break;
    }

    case 'pick': {
      const box = el.closest('[data-picker]');
      if (!box) return;
      box.querySelector('input[type=hidden]').value = el.dataset.cid;
      box.querySelector('[data-pick-search]').value = `${el.dataset.cname} (${el.dataset.cid})`;
      box.querySelector('[data-pick-results]').innerHTML = '';
      break;
    }

    case 'note-add': {
      const body = $('#veil [data-name="noteBody"]');
      const vis = $('#veil [data-name="noteVis"]');
      if (!body || body.value.trim().length < 2) return notify('Not completed', 'Write something first.', true);
      const res = await post('nz_mdt:notes:add', el.dataset.subject, el.dataset.sid, body.value, vis ? vis.value : 'department');
      if (reply(res)) {
        body.value = '';
        const list = $('#noteList');
        if (list) list.innerHTML = noteRows(res.rows);
      }
      break;
    }
    case 'note-del': {
      const res = await post('nz_mdt:notes:delete', parseInt(el.dataset.id, 10));
      if (reply(res)) {
        const list = $('#noteList');
        if (list) list.innerHTML = noteRows(res.rows);
      }
      break;
    }

    case 'flag-add': {
      const input = $('#veil [data-name="flagLabel"]');
      const tone = $('#veil [data-name="flagTone"]');
      if (!input || input.value.trim().length < 2) return notify('Not completed', 'Give the flag a label.', true);
      const res = await post('nz_mdt:citizen:flag', el.dataset.cid, input.value, tone ? tone.value : 'teal', false);
      if (reply(res)) citizenModal(el.dataset.cid, true);
      break;
    }
    case 'flag-del': {
      const res = await post('nz_mdt:citizen:flag', el.dataset.cid, el.dataset.label, 'teal', true);
      if (reply(res)) citizenModal(el.dataset.cid, true);
      break;
    }
    case 'evidence-chain': {
      const note = $('#veil [data-name="chainNote"]');
      const id = parseInt(el.dataset.id, 10);
      const res = await post('nz_mdt:evidence:checkout', id, el.dataset.state, note ? note.value : '');
      if (reply(res)) { evidenceModal(id, true); if (S.page === 'evidence') loadPage('evidence'); }
      break;
    }
    case 'vehicle-flag': {
      const patch = {};
      patch[el.dataset.field] = el.dataset.state === '1';
      const res = await post('nz_mdt:vehicle:update', el.dataset.plate, patch);
      if (reply(res)) { vehicleModal(el.dataset.plate, true); if (S.page === 'vehicles') loadPage('vehicles'); }
      break;
    }
    case 'weapon-status': {
      const res = await post('nz_mdt:weapon:update', el.dataset.serial, { status: el.dataset.state });
      if (reply(res)) { weaponModal(el.dataset.serial, true); if (S.page === 'weapons') loadPage('weapons'); }
      break;
    }
    case 'incident-status': {
      const res = await post('nz_mdt:incident:status', parseInt(el.dataset.id, 10), el.dataset.state);
      if (reply(res)) { incidentModalView(parseInt(el.dataset.id, 10), true); if (S.page === 'incidents') loadPage('incidents'); scheduleDash(); }
      break;
    }
    case 'tab': {
      $$('#veil .tab').forEach(t => t.classList.toggle('on', t === el));
      $$('#veil [data-tabpane]').forEach(p => p.classList.toggle('hidden', p.dataset.tabpane !== el.dataset.tab));
      break;
    }
    case 'copy': {
      try { await navigator.clipboard.writeText(el.dataset.text); notify('Copied', el.dataset.text); }
      catch (e) {
        const ta = document.createElement('textarea');
        ta.value = el.dataset.text; document.body.appendChild(ta); ta.select();
        try { document.execCommand('copy'); notify('Copied', el.dataset.text); } catch (e2) {}
        ta.remove();
      }
      break;
    }

    /* ── photos ── */
    case 'photo-open': lightbox(el.dataset.url, el.dataset.cap); break;
    case 'photo-take': {
      const subject = el.dataset.subject, sid = el.dataset.sid;
      openModal({
        title: 'camera.exe — take photo', icon: 'camera', confirm: 'Capture', child: true,
        lede: 'The tablet hides itself, captures what is on screen, and attaches it to this record.',
        body: `<div class="field"><label>caption</label>
          <input data-name="caption" maxlength="200" placeholder="Front of the vehicle, plate visible"></div>`,
        onConfirm: async (v) => {
          backModal();
          notify('Capturing', 'Hold still for a second.', 'warn', 2500);
          const res = await post('nz_mdt:photo:take', subject, sid, v.caption);
          if (reply(res)) refreshPhotos(res.rows);
        }
      });
      break;
    }
    case 'photo-paste': {
      const subject = el.dataset.subject, sid = el.dataset.sid;
      openModal({
        title: 'camera.exe — attach link', icon: 'link', confirm: 'Attach', child: true,
        lede: 'Paste a direct link to an image already hosted somewhere.',
        body: `<div class="field"><label>image_link</label><input data-name="url" placeholder="https://..."></div>
          <div class="field"><label>caption</label><input data-name="caption" maxlength="200" placeholder="Optional"></div>`,
        onConfirm: async (v) => {
          const res = await post('nz_mdt:photo:link', subject, sid, v.url, v.caption);
          if (reply(res)) { backModal(); refreshPhotos(res.rows); }
        }
      });
      break;
    }
    case 'photo-avatar': {
      const res = await post('nz_mdt:photo:avatar', parseInt(el.dataset.id, 10));
      if (reply(res)) refreshPhotos(res.rows);
      break;
    }
    case 'photo-del': {
      const res = await post('nz_mdt:photo:delete', parseInt(el.dataset.id, 10));
      if (reply(res)) refreshPhotos(res.rows);
      break;
    }

    /* ── links ── */
    case 'link-find': {
      const kind = $('#linkKind'), input = $('#linkSearch'), box = $('#linkResults');
      if (!kind || !input || !box) return;
      box.innerHTML = skeleton(2);
      const res = await post('nz_mdt:link:search', kind.value, input.value);
      const rows = (res && res.rows) || [];
      box.innerHTML = rows.length
        ? `<div class="chargelist" style="margin-bottom:0.8vh">${rows.map(r => `
            <div class="chargerow">
              <div class="ic sm">${icon(linkIcon(kind.value))}</div>
              <b>${esc(r.title)}</b>
              <span class="cost">${esc(r.sub || '')}</span>
              <button class="btn-ghost" data-inner="link-add" data-subject="${esc(el.dataset.subject)}" data-sid="${esc(el.dataset.sid)}"
                data-kind="${esc(kind.value)}" data-target="${esc(r.id)}">${ICON.link} Link</button>
            </div>`).join('')}</div>`
        : `<div class="wempty">Nothing matched that.</div>`;
      break;
    }
    case 'link-add': {
      const res = await post('nz_mdt:link:create', el.dataset.subject, el.dataset.sid, el.dataset.kind, el.dataset.target);
      if (reply(res)) {
        refreshLinks(res.rows, el.dataset.subject, el.dataset.sid);
        const box = $('#linkResults'); if (box) box.innerHTML = '';
        const input = $('#linkSearch'); if (input) input.value = '';
      }
      break;
    }
    case 'link-del': {
      const res = await post('nz_mdt:link:remove', parseInt(el.dataset.id, 10), el.dataset.subject, el.dataset.sid);
      if (reply(res)) refreshLinks(res.rows, el.dataset.subject, el.dataset.sid);
      break;
    }
    case 'link-open': openRecord(el.dataset.kind, el.dataset.id); break;
    default: break;
  }
}

/* ═══════════════════════════════════════════════════════════════════════════
   RECORD MODALS
   ═══════════════════════════════════════════════════════════════════════════ */
/** Open a skeleton, fetch, then swap the record in — unless the officer moved on. */
async function recordModal(opts, fetcher, builder) {
  const child = opts.refresh ? false : veilUp();
  const seq = opts.refresh
    ? S.modalSeq
    : openModal({ title: opts.title, icon: opts.icon, wide: opts.wide, body: skeleton(4), child, noFocus: true });
  const r = await fetcher();
  if (seq !== S.modalSeq) return;
  if (!r || !r.ok) {
    backModal();
    return notify('Not found', (r && r.msg) || 'That record could not be loaded.', true);
  }
  const built = builder(r);
  openModal(Object.assign({ icon: opts.icon, wide: opts.wide, replace: true, noFocus: true }, built));
  if (opts.after) opts.after(r, S.modalSeq);
}

function copyBtn(text) {
  return `<button class="icobtn" data-inner="copy" data-text="${esc(text)}" title="Copy">${ICON.copy}</button>`;
}

function citizenModal(id, refresh) {
  return recordModal({ title: 'citizen-db.exe', icon: 'user', wide: 'xwide', refresh },
    () => post('nz_mdt:citizen:profile', id),
    (r) => {
      const c = r.citizen;
      const lic = S.cfg.licences || [];

      const licences = lic.map(l => {
        const state = (c.licences || {})[l.id] || 'none';
        const tone = state === 'valid' ? '' : state === 'suspended' ? 'amber' : state === 'revoked' ? 'red' : 'off';
        return `<div class="kv">
          <span>${esc(l.label)}</span>
          <span class="end">
            <span class="chip ${tone}">${esc(state.toUpperCase())}</span>
            ${can('citizen.licence') ? `<select class="mini" data-change="licence" data-cid="${esc(c.id)}" data-lic="${esc(l.id)}">
              ${['valid', 'suspended', 'revoked', 'none'].map(s => `<option value="${s}" ${s === state ? 'selected' : ''}>${s}</option>`).join('')}
            </select>` : ''}
          </span>
        </div>`;
      }).join('');

      const flags = (c.flags || []).map(f => `
        <span class="chip ${toneChip(f.tone)}" title="${esc(f.by || '')} · ${esc(f.at || '')}">
          ${esc(f.label)}
          ${can('citizen.note') ? `<button data-inner="flag-del" data-cid="${esc(c.id)}" data-label="${esc(f.label)}">×</button>` : ''}
        </span>`).join('') || '<span class="wempty" style="padding:0">No flags on this record.</span>';

      const vehicles = (r.vehicles || []).map(v => `
        <button class="row ${v.stolen ? 'hot' : ''}" data-act="vehicle-open" data-id="${esc(v.plate)}">
          <div class="ic ${v.stolen ? 'red' : 'blue'}">${ICON.car}</div>
          <div class="row-txt"><b style="font-family:var(--font-mono)">${esc(v.plate)}</b><span>${esc(v.model || 'unknown model')} · reg ${esc(v.registration)}</span></div>
          ${v.stolen ? '<span class="tag hot">Stolen</span>' : ''}
        </button>`).join('') || `<div class="wempty">No vehicles registered.</div>`;

      const weapons = (r.weapons || []).map(w => `
        <button class="row" data-act="weapon-open" data-id="${esc(w.serial)}">
          <div class="ic ${w.status === 'stolen' ? 'red' : 'grey'}">${ICON.gun}</div>
          <div class="row-txt"><b>${esc(w.label)}</b><span>${esc(w.serial)}</span></div>
          <span class="tag ${w.status === 'registered' ? 'live' : 'hot'}">${esc(w.status)}</span>
        </button>`).join('') || `<div class="wempty">No firearms registered.</div>`;

      const props = (r.properties || []).map(p => `
        <div class="row"><div class="ic">${ICON.house}</div>
          <div class="row-txt"><b>${esc(p.label)}</b><span>${esc(p.address)}</span></div></div>`).join('')
        || `<div class="wempty">No property registered.</div>`;

      const warrants = (r.warrants || []).map(w => `
        <div class="row ${w.status === 'active' ? 'hot' : ''}">
          <div class="ic ${w.status === 'active' ? 'red' : 'grey'}">${ICON.warn}</div>
          <div class="row-txt"><b>${esc(w.title)}</b><span>${esc(w.type)} · ${esc(w.issued_by)} · ${esc(w.stamp)}</span></div>
          <span class="tag ${w.status === 'active' ? 'hot' : 'off'}">${esc(w.status)}</span>
        </div>`).join('') || `<div class="wempty">No warrants on file.</div>`;

      const incidents = (r.incidents || []).map(i => `
        <button class="row" data-act="incident-open" data-id="${i.id}">
          <div class="ic blue">${ICON.file}</div>
          <div class="row-txt"><b>${esc(i.title)}</b><span>${esc(i.ref)} · ${esc(i.stamp)}</span></div>
          <div class="row-num"><b>${money(i.total_fine)}</b><span>${i.total_jail}m</span></div>
          <span class="tag ${statusTag(i.status)}">${esc(i.status)}</span>
        </button>`).join('') || `<div class="wempty">No reports on file.</div>`;

      const history = (r.charges || []).map(ch => `
        <tr><td><b>${esc(ch.label)}</b></td><td>${esc(ch.class)}</td><td class="right">${ch.counts}</td>
        <td class="right">${money(ch.fine)}</td><td class="right">${ch.jail}m</td></tr>`).join('');

      return {
        title: `citizen-db.exe — ${c.name}`,
        extra: can('citizen.delete') ? `<button class="btn-red left" data-act="citizen-delete" data-id="${esc(c.id)}">${ICON.trash} Delete record</button>` : '',
        body: `
          ${r.record.wanted ? `<div class="banner">${ICON.warn}<div><b>WANTED</b><p>This citizen has an active warrant. Approach with the appropriate caution.</p></div></div>` : ''}

          <div class="record-head">
            ${c.mugshot
              ? `<div class="recpic" data-inner="photo-open" data-url="${esc(c.mugshot)}" data-cap="${esc(c.name)}"><img src="${esc(c.mugshot)}" alt=""></div>`
              : `<div class="av teal lg">${initials(c.name)}</div>`}
            <div class="who">
              <b>${esc(c.name)}</b>
              <span>${esc(c.id)} · ${esc(c.dob || 'DOB unknown')} · ${esc(c.gender || 'unspecified')}</span>
            </div>
            <div class="acts">
              ${copyBtn(c.id)}
              ${can('incident.create') ? `<button class="btn-line" data-act="incident-for" data-id="${esc(c.id)}" data-name="${esc(c.name)}">${fa('file-pen')} Report</button>` : ''}
              ${can('bolo.create') ? `<button class="btn-line" data-act="bolo-for-person" data-id="${esc(c.id)}" data-name="${esc(c.name)}">${ICON.bell} BOLO</button>` : ''}
              ${can('warrant.create') ? `<button class="btn-red" data-act="warrant-for" data-id="${esc(c.id)}" data-name="${esc(c.name)}">${ICON.gavel} Warrant</button>` : ''}
              ${can('citizen.edit') ? `<button class="btn-line" data-act="citizen-edit" data-id="${esc(c.id)}">${ICON.pen} Edit</button>` : ''}
            </div>
          </div>

          <div class="tabs">
            <button class="tab on" data-inner="tab" data-tab="overview">Overview</button>
            <button class="tab" data-inner="tab" data-tab="records">Registered<span class="tally">${(r.vehicles || []).length + (r.weapons || []).length + (r.properties || []).length}</span></button>
            <button class="tab" data-inner="tab" data-tab="criminal">Criminal history<span class="tally ${r.record.wanted ? 'hot' : ''}">${(r.incidents || []).length}</span></button>
            <button class="tab" data-inner="tab" data-tab="media">Photos &amp; links</button>
            <button class="tab" data-inner="tab" data-tab="notes">Notes<span class="tally">${(r.notes || []).length}</span></button>
          </div>

          <div data-tabpane="overview">
            <div class="kgrid three">
              <div class="kfield"><span>phone</span><b>${esc(c.phone || '—')}</b></div>
              <div class="kfield"><span>occupation</span><b>${esc(c.job || '—')}</b></div>
              <div class="kfield"><span>address</span><b>${esc(c.address || '—')}</b></div>
              <div class="kfield"><span>height</span><b>${esc(c.height || '—')}</b></div>
              <div class="kfield"><span>hair</span><b>${esc(c.hair || '—')}</b></div>
              <div class="kfield"><span>eyes</span><b>${esc(c.eyes || '—')}</b></div>
              <div class="kfield"><span>fingerprint</span><b class="mono">${esc(c.fingerprint || '—')}</b></div>
              <div class="kfield"><span>dna</span><b class="mono">${esc(c.dna || '—')}</b></div>
              <div class="kfield"><span>total_charges</span><b class="${r.record.charges ? 'red' : ''}">${r.record.charges}</b></div>
            </div>

            <div class="cols" style="margin-top:1.6vh">
              <div>
                <div class="section-label">flags</div>
                <div class="btnrow">${flags}</div>
                ${can('citizen.note') ? `<div class="inline" style="margin-top:1vh">
                  <div class="field"><input data-name="flagLabel" maxlength="40" placeholder="e.g. known to carry"></div>
                  <div class="field narrow"><select data-name="flagTone">
                    <option value="teal">Note</option><option value="amber">Caution</option><option value="red">Danger</option>
                  </select></div>
                  <button class="btn-line" data-inner="flag-add" data-cid="${esc(c.id)}">${ICON.plus} Add</button>
                </div>` : ''}
              </div>
              <div>
                <div class="section-label">licences</div>
                ${licences}
              </div>
            </div>
          </div>

          <div data-tabpane="records" class="hidden">
            <div class="cols three">
              <div><div class="section-label">${ICON.car} vehicles</div><div class="scroll short">${vehicles}</div></div>
              <div><div class="section-label">${ICON.gun} firearms</div><div class="scroll short">${weapons}</div></div>
              <div><div class="section-label">${ICON.house} property</div><div class="scroll short">${props}</div></div>
            </div>
          </div>

          <div data-tabpane="criminal" class="hidden">
            <div class="totals three" style="margin-bottom:1.4vh">
              <div class="total"><span>lifetime_fines</span><b class="teal">${money(r.record.fine)}</b></div>
              <div class="total"><span>lifetime_sentence</span><b class="amber">${r.record.jail} months</b></div>
              <div class="total"><span>charges</span><b class="${r.record.charges ? 'red' : ''}">${r.record.charges}</b></div>
            </div>
            <div class="cols">
              <div><div class="section-label">warrants</div><div class="scroll short">${warrants}</div></div>
              <div><div class="section-label">reports</div><div class="scroll short">${incidents}</div></div>
            </div>
            ${history ? `<div class="section-label" style="margin-top:1.4vh">charge_history</div>
              <table><thead><tr><th>charge</th><th>class</th><th class="right">counts</th>
              <th class="right">fines</th><th class="right">time</th></tr></thead><tbody>${history}</tbody></table>` : ''}
          </div>

          <div data-tabpane="media" class="hidden">
            ${photoBlock('citizen', c.id, r.photos)}
            <div class="spacer"></div>
            ${linkBlock('citizen', c.id, r.links)}
          </div>

          <div data-tabpane="notes" class="hidden">${noteBlock('citizen', c.id, r.notes)}</div>`
      };
    });
}

/** Imported ESX vehicles carry a model hash — ask the game for the name once. */
async function fixModelName(r, seq) {
  const v = r.vehicle;
  if (!/^-?\d+$/.test(String(v.model || ''))) return;
  const res = await raw('modelName', { model: v.model });
  if (!res || !res.ok || !res.name) return;
  post('nz_mdt:vehicle:model', v.plate, res.name);
  if (seq !== S.modalSeq) return;
  const sub = $('#veil .record-head .who > span');
  if (sub) sub.textContent = sub.textContent.replace(String(v.model), res.name);
}

function vehicleModal(plate, refresh) {
  return recordModal({ title: 'vehicle-db.exe', icon: 'car', wide: 'wide', refresh, after: fixModelName },
    () => post('nz_mdt:vehicle:profile', plate),
    (r) => {
      const v = r.vehicle;
      const bolos = (r.bolos || []).map(b => `
        <div class="row ${b.status === 'active' ? 'hot' : ''}">
          <div class="ic ${b.status === 'active' ? 'red' : 'grey'}">${ICON.bell}</div>
          <div class="row-txt"><b>${esc(b.title)}</b><span>${esc(b.issued_by)} · ${esc(b.stamp)}</span></div>
          <span class="tag ${b.status === 'active' ? 'hot' : 'off'}">${esc(b.status)}</span>
        </div>`).join('') || `<div class="wempty">No BOLOs on this plate.</div>`;

      return {
        title: `vehicle-db.exe — ${v.plate}`,
        extra: can('vehicle.delete') ? `<button class="btn-red left" data-act="vehicle-delete" data-id="${esc(v.plate)}">${ICON.trash} Delete</button>` : '',
        body: `
          ${v.stolen ? `<div class="banner">${ICON.warn}<div><b>REPORTED STOLEN</b><p>Treat the occupants as suspects and call it in before approaching.</p></div></div>` : ''}
          ${r.bolos && r.bolos.some(b => b.status === 'active') ? `<div class="banner amber">${ICON.bell}<div><b>Active BOLO</b><p>${esc(r.bolos.find(b => b.status === 'active').title)}</p></div></div>` : ''}

          <div class="record-head">
            <div class="ic lg ${v.stolen ? 'red' : 'blue'}">${ICON.car}</div>
            <div class="who">
              <b style="font-family:var(--font-mono)">${esc(v.plate)}</b>
              <span>${esc(v.model || 'unknown model')} · ${esc(v.type || 'no class')}${v.colour ? ' · ' + esc(v.colour) : ''}</span>
            </div>
            <div class="acts">
              ${copyBtn(v.plate)}
              ${can('vehicle.flag') ? `<button class="${v.stolen ? 'btn-line' : 'btn-red'}" data-inner="vehicle-flag" data-field="stolen" data-plate="${esc(v.plate)}" data-state="${v.stolen ? '0' : '1'}">
                ${v.stolen ? fa('flag-checkered') + ' Clear stolen' : ICON.flag + ' Flag stolen'}</button>
                <button class="btn-line" data-inner="vehicle-flag" data-field="impounded" data-plate="${esc(v.plate)}" data-state="${v.impounded ? '0' : '1'}">
                ${fa('warehouse')} ${v.impounded ? 'Release' : 'Impound'}</button>` : ''}
              ${can('bolo.create') ? `<button class="btn-line" data-act="bolo-for-plate" data-id="${esc(v.plate)}" data-model="${esc(v.model || '')}">${ICON.bell} BOLO</button>` : ''}
              ${can('vehicle.edit') ? `<button class="btn-line" data-act="vehicle-edit" data-id="${esc(v.plate)}">${ICON.pen} Edit</button>` : ''}
            </div>
          </div>

          <div class="kgrid three">
            <div class="kfield"><span>vin</span><b class="mono">${esc(v.vin || '—')}</b></div>
            <div class="kfield"><span>colour</span><b>${esc(v.colour || '—')}</b></div>
            <div class="kfield"><span>registration</span><b class="${v.registration === 'valid' ? 'teal' : 'red'}">${esc(v.registration)}</b></div>
            <div class="kfield"><span>insurance</span><b class="${v.insurance === 'valid' ? 'teal' : v.insurance === 'expired' || v.insurance === 'none' ? 'red' : ''}">${esc(v.insurance)}</b></div>
            <div class="kfield"><span>impounded</span><b class="${v.impounded ? 'amber' : ''}">${v.impounded ? 'Yes' : 'No'}</b></div>
            <div class="kfield"><span>stolen</span><b class="${v.stolen ? 'red' : 'teal'}">${v.stolen ? 'Yes' : 'No'}</b></div>
          </div>

          <div class="cols">
            <div>
              <div class="section-label">registered_owner</div>
              ${r.owner ? `<button class="row" data-act="citizen-open" data-id="${esc(r.owner.id)}">
                  <div class="av sm teal">${initials(r.owner.name)}</div>
                  <div class="row-txt"><b>${esc(r.owner.name)}</b><span>${esc(r.owner.id)} · ${esc(r.owner.phone || 'no number')}</span></div>
                  ${fa('arrow-up-right-from-square', 'chev')}
                </button>` : `<div class="wempty">No registered owner on file.</div>`}
            </div>
            <div><div class="section-label">bolos</div>${bolos}</div>
          </div>

          ${photoBlock('vehicle', v.plate, r.photos)}
          ${linkBlock('vehicle', v.plate, r.links)}
          <div class="section-label">notes</div>
          ${noteBlock('vehicle', v.plate, r.notes)}`
      };
    });
}

function weaponModal(serial, refresh) {
  return recordModal({ title: 'firearm-db.exe', icon: 'gun', wide: 'wide', refresh },
    () => post('nz_mdt:weapon:profile', serial),
    (r) => {
      const w = r.weapon;
      const states = ['registered', 'stolen', 'seized', 'destroyed'];
      return {
        title: `firearm-db.exe — ${w.serial}`,
        extra: can('weapon.delete') ? `<button class="btn-red left" data-act="weapon-delete" data-id="${esc(w.serial)}">${ICON.trash} Delete</button>` : '',
        body: `
          ${w.status === 'stolen' ? `<div class="banner">${ICON.warn}<div><b>REPORTED STOLEN</b><p>Seize the firearm and log it as evidence.</p></div></div>` : ''}
          <div class="record-head">
            <div class="ic lg ${w.status === 'stolen' ? 'red' : 'grey'}">${ICON.gun}</div>
            <div class="who"><b>${esc(w.label)}</b><span>${esc(w.serial)}</span></div>
            <div class="acts">${copyBtn(w.serial)}<span class="tag ${w.status === 'registered' ? 'live' : 'hot'}">${esc(w.status)}</span></div>
          </div>

          <div class="kgrid">
            <div class="kfield"><span>weapon_type</span><b>${esc(w.weapon || '—')}</b></div>
            <div class="kfield"><span>registered</span><b>${esc(String(w.registered || '').slice(0, 10))}</b></div>
          </div>

          ${can('weapon.edit') ? `<div>
            <div class="section-label">change_status</div>
            <div class="seg">
              ${states.map(s => `<button class="${w.status === s ? 'on' : ''}" data-inner="weapon-status" data-serial="${esc(w.serial)}" data-state="${s}">${cap(s)}</button>`).join('')}
            </div>
          </div>` : ''}

          <div>
            <div class="section-label">owner</div>
            ${r.owner ? `<button class="row" data-act="citizen-open" data-id="${esc(r.owner.id)}">
                <div class="av sm teal">${initials(r.owner.name)}</div>
                <div class="row-txt"><b>${esc(r.owner.name)}</b><span>${esc(r.owner.id)}</span></div>
                ${fa('arrow-up-right-from-square', 'chev')}
              </button>` : `<div class="wempty">No registered owner on file.</div>`}
          </div>

          ${photoBlock('weapon', w.serial, r.photos)}
          ${linkBlock('weapon', w.serial, r.links)}
          <div class="section-label">notes</div>
          ${noteBlock('weapon', w.serial, r.notes)}`
      };
    });
}

function incidentModalView(id, refresh) {
  return recordModal({ title: 'incident-reports.exe', icon: 'file-lines', wide: 'xwide', refresh },
    () => post('nz_mdt:incident:get', id),
    (r) => {
      const i = r.incident;
      const people = (r.people || []).map(p => `
        <button class="row" data-act="citizen-open" data-id="${esc(p.citizen_id)}">
          <div class="av sm teal">${initials(p.name)}</div>
          <div class="row-txt"><b>${esc(p.name)}</b><span>${esc(p.notes || p.citizen_id)}</span></div>
          <span class="chip ${p.role === 'suspect' ? 'red' : p.role === 'victim' ? 'amber' : 'off'}">${esc(p.role.toUpperCase())}</span>
        </button>`).join('') || `<div class="wempty">Nobody attached to this report.</div>`;

      const charges = (r.charges || []).map(c => `
        <tr><td><b>${esc(c.label)}</b>${c.reduced ? ' <span class="chip off">½</span>' : ''}<small>${esc(c.citizen_id || '')}</small></td>
        <td>${esc(c.class)}</td><td class="right">${c.counts}</td>
        <td class="right">${money(c.fine)}</td><td class="right">${c.jail}m</td></tr>`).join('');

      const evidence = (r.evidence || []).map(e => `
        <button class="row" data-act="evidence-open" data-id="${e.id}">
          <div class="ic">${icon(EV_ICON[e.type] || 'box')}</div>
          <div class="row-txt"><b>${esc(e.description)}</b><span>${esc(e.ref)} · ${esc(e.locker || 'unassigned')}</span></div>
          <span class="tag ${e.status === 'in' ? 'live' : 'warn'}">${esc(e.status)}</span>
        </button>`).join('') || `<div class="wempty">No evidence linked to this report.</div>`;

      const actions = [];
      if (i.status !== 'closed' && can('incident.close')) {
        actions.push(`<button class="btn-teal solid" data-inner="incident-status" data-id="${i.id}" data-state="closed">${ICON.check} Close report</button>`);
      }
      if (i.status === 'open' && can('incident.edit')) {
        actions.push(`<button class="btn-line" data-inner="incident-status" data-id="${i.id}" data-state="pending">${ICON.clock} Pending</button>`);
      }
      if (i.status === 'closed' && can('incident.reopen')) {
        actions.push(`<button class="btn-line" data-inner="incident-status" data-id="${i.id}" data-state="open">${ICON.unlock} Reopen</button>`);
      }
      if (i.status !== 'closed' && can('incident.edit')) {
        actions.push(`<button class="btn-line" data-act="incident-edit" data-id="${i.id}">${ICON.pen} Edit</button>`);
      }
      if (can('evidence.create')) {
        actions.push(`<button class="btn-line" data-act="evidence-for" data-id="${esc(i.ref)}">${ICON.box} Evidence</button>`);
      }

      return {
        title: `incident-reports.exe — ${i.ref}`,
        extra: can('incident.delete') ? `<button class="btn-red left" data-act="incident-delete" data-id="${i.id}">${ICON.trash} Delete</button>` : '',
        body: `
          <div class="record-head">
            <div class="ic lg blue">${ICON.file}</div>
            <div class="who">
              <b>${esc(i.title)}</b>
              <span>${esc(i.ref)}${i.dispatch_ref ? ' · from ' + esc(i.dispatch_ref) : ''} · <span class="tag ${statusTag(i.status)}">${esc(i.status)}</span></span>
            </div>
            <div class="acts">${copyBtn(i.ref)}${actions.join('')}</div>
          </div>

          <div class="tabs">
            <button class="tab on" data-inner="tab" data-tab="details">Details</button>
            <button class="tab" data-inner="tab" data-tab="related">Related<span class="tally">${(r.people || []).length + (r.evidence || []).length}</span></button>
            <button class="tab" data-inner="tab" data-tab="media">Photos &amp; links</button>
            <button class="tab" data-inner="tab" data-tab="notes">Notes<span class="tally">${(r.notes || []).length}</span></button>
          </div>

          <div data-tabpane="details">
            <div class="kgrid three">
              <div class="kfield"><span>location</span><b>${esc(i.location || '—')}</b></div>
              <div class="kfield"><span>filed_by</span><b>${esc(i.created_by)}</b></div>
              <div class="kfield"><span>filed</span><b>${esc(i.created_stamp || '')}</b></div>
              <div class="kfield"><span>primary_citizen</span><b>${esc(i.primary_name || '—')}</b></div>
              <div class="kfield"><span>closed_by</span><b>${esc(i.closed_by || '—')}</b></div>
              <div class="kfield"><span>closed</span><b>${esc(i.closed_stamp || '—')}</b></div>
            </div>
            <div class="section-label" style="margin-top:1.4vh">narrative</div>
            <p class="prose boxed">${esc(i.detail || 'No narrative recorded.')}</p>
            ${charges ? `<div class="section-label" style="margin-top:1.4vh">charges</div>
              <table><thead><tr><th>charge</th><th>class</th><th class="right">counts</th>
              <th class="right">fine</th><th class="right">time</th></tr></thead><tbody>${charges}</tbody></table>` : ''}
            <div class="totals" style="margin-top:1.4vh">
              <div class="total"><span>total_fine</span><b class="teal">${money(i.total_fine)}</b></div>
              <div class="total"><span>total_jail</span><b class="amber">${i.total_jail} months</b></div>
            </div>
          </div>

          <div data-tabpane="related" class="hidden">
            <div class="cols">
              <div><div class="section-label">people</div><div class="scroll">${people}</div></div>
              <div><div class="section-label">evidence</div><div class="scroll">${evidence}</div></div>
            </div>
          </div>

          <div data-tabpane="media" class="hidden">
            ${photoBlock('incident', i.ref, r.photos)}
            <div class="spacer"></div>
            ${linkBlock('incident', i.ref, r.links)}
          </div>

          <div data-tabpane="notes" class="hidden">${noteBlock('incident', i.ref, r.notes)}</div>`
      };
    });
}

function evidenceModal(id, refresh) {
  return recordModal({ title: 'evidence-locker.exe', icon: 'box-archive', wide: 'wide', refresh },
    () => post('nz_mdt:evidence:get', id),
    (r) => {
      const e = r.evidence;
      const chain = (r.chain || []).map(c => `
        <div class="row">
          <div class="ic sm">${ICON.clock}</div>
          <div class="row-txt"><b>${esc(cap(c.action))}</b><span>${esc(c.actor)}${c.note ? ' · ' + esc(c.note) : ''}</span></div>
          <span class="row-meta">${esc(c.stamp)}</span>
        </div>`).join('') || `<div class="wempty">Nothing recorded yet.</div>`;

      return {
        title: `evidence-locker.exe — ${e.ref}`,
        extra: can('evidence.delete') ? `<button class="btn-red left" data-act="evidence-delete" data-id="${e.id}">${ICON.trash} Delete</button>` : '',
        body: `
          <div class="record-head">
            <div class="ic lg ${e.status === 'out' ? 'amber' : ''}">${icon(EV_ICON[e.type] || 'box')}</div>
            <div class="who"><b>${esc(e.description)}</b><span>${esc(e.type)} · ${esc(e.ref)}</span></div>
            <div class="acts">${copyBtn(e.ref)}<span class="tag ${e.status === 'in' ? 'live' : e.status === 'out' ? 'warn' : 'off'}">${esc(e.status)}</span></div>
          </div>

          <div class="kgrid three">
            <div class="kfield"><span>collected_by</span><b>${esc(e.collectedBy)}</b></div>
            <div class="kfield"><span>collected_at</span><b>${esc(e.location || '—')}</b></div>
            <div class="kfield"><span>locker</span><b>${esc(e.locker || 'unassigned')}</b></div>
            <div class="kfield"><span>linked_report</span><b>${e.incidentRef && can('view.incident') ? `<a data-act="incident-open" data-id="${esc(e.incidentRef)}" style="cursor:pointer;color:var(--accent)">${esc(e.incidentRef)}</a>` : esc(e.incidentRef || '—')}</b></div>
            <div class="kfield"><span>held_by</span><b>${esc(e.holder || '—')}</b></div>
            <div class="kfield"><span>logged</span><b>${esc(e.stamp || '')}</b></div>
          </div>

          ${can('evidence.checkout') ? `<div>
            <div class="section-label">chain_of_custody</div>
            <div class="field"><input data-name="chainNote" maxlength="200" placeholder="Reason — e.g. taken to the lab for analysis"></div>
            <div class="btnrow" style="margin-top:0.8vh">
              ${e.status !== 'out' ? `<button class="btn-ghost" data-inner="evidence-chain" data-id="${e.id}" data-state="out">${fa('right-from-bracket')} Check out</button>` : ''}
              ${e.status !== 'in' ? `<button class="btn-ghost" data-inner="evidence-chain" data-id="${e.id}" data-state="in">${fa('right-to-bracket')} Check in</button>` : ''}
              ${e.status !== 'released' ? `<button class="btn-ghost" data-inner="evidence-chain" data-id="${e.id}" data-state="released">${fa('hand-holding')} Release</button>` : ''}
              ${can('evidence.delete') && e.status !== 'destroyed' ? `<button class="btn-ghost danger" data-inner="evidence-chain" data-id="${e.id}" data-state="destroyed">${ICON.fire} Destroy</button>` : ''}
            </div>
          </div>` : ''}

          ${photoBlock('evidence', e.ref, r.photos)}
          ${linkBlock('evidence', e.ref, r.links)}

          <div>
            <div class="section-label">history</div>
            <div class="scroll short">${chain}</div>
          </div>

          <div class="section-label">notes</div>
          ${noteBlock('evidence', e.ref, r.notes)}`
      };
    });
}

/* ═══════════════════════════════════════════════════════════════════════════
   CREATE / EDIT MODALS
   ═══════════════════════════════════════════════════════════════════════════ */
function citizenCreateModal(existing) {
  const c = existing || {};
  openModal({
    title: existing ? `citizen-db.exe — edit ${c.name || ''}` : 'citizen-db.exe — register', icon: 'user-plus',
    confirm: existing ? 'Save changes' : 'Register', wide: 'wide', child: true,
    body: `
      <div class="row3">
        <div class="field"><label>first_name</label><input data-name="first" maxlength="40" value="${esc(c.first || '')}"></div>
        <div class="field"><label>last_name</label><input data-name="last" maxlength="40" value="${esc(c.last || '')}"></div>
        <div class="field"><label>date_of_birth</label><input data-name="dob" maxlength="16" placeholder="1992-08-22" value="${esc(c.dob || '')}"></div>
      </div>
      <div class="row3">
        <div class="field"><label>gender</label><select data-name="gender">
          <option value="">Unspecified</option>
          <option value="Male" ${c.gender === 'Male' ? 'selected' : ''}>Male</option>
          <option value="Female" ${c.gender === 'Female' ? 'selected' : ''}>Female</option>
          <option value="Other" ${c.gender === 'Other' ? 'selected' : ''}>Other</option>
        </select></div>
        <div class="field"><label>phone</label><input data-name="phone" maxlength="24" value="${esc(c.phone || '')}"></div>
        <div class="field"><label>occupation</label><input data-name="job" maxlength="48" value="${esc(c.job || '')}"></div>
      </div>
      <div class="field"><label>address</label><input data-name="address" maxlength="90" value="${esc(c.address || '')}"></div>
      <div class="row3">
        <div class="field"><label>height</label><input data-name="height" maxlength="16" value="${esc(c.height || '')}"></div>
        <div class="field"><label>hair</label><input data-name="hair" maxlength="24" value="${esc(c.hair || '')}"></div>
        <div class="field"><label>eyes</label><input data-name="eyes" maxlength="24" value="${esc(c.eyes || '')}"></div>
      </div>`,
    onConfirm: async (v) => {
      if ((v.first || '').trim().length < 2 || (v.last || '').trim().length < 2) {
        return notify('Not completed', 'A first and last name are required.', true);
      }
      const res = existing
        ? await post('nz_mdt:citizen:update', existing.id, v)
        : await post('nz_mdt:citizen:create', v);
      if (reply(res)) {
        closeModal();
        if (S.page === 'citizens') loadPage('citizens');
        if (existing) citizenModal(existing.id);
        else if (res.id) citizenModal(res.id);
      }
    }
  });
}

async function vehicleCreateModal(existing) {
  const nearby = existing ? null : await raw('nearbyPlate');
  const v = existing || {};
  const classes = ['Car', 'Sedan', 'Coupe', 'SUV', 'Sports', 'Supercar', 'Muscle', 'Motorcycle', 'Van', 'Truck', 'Off-Road', 'Boat', 'Aircraft'];
  openModal({
    title: existing ? `vehicle-db.exe — edit ${v.plate}` : 'vehicle-db.exe — register', icon: 'car', child: true,
    confirm: existing ? 'Save changes' : 'Register', wide: 'wide',
    body: `
      <div class="row3">
        <div class="field"><label>plate</label><input data-name="plate" maxlength="12" value="${esc(v.plate || (nearby && nearby.plate) || '')}" ${existing ? 'readonly' : ''}></div>
        <div class="field"><label>model</label><input data-name="model" maxlength="40" value="${esc(v.model || (nearby && nearby.model) || '')}"></div>
        <div class="field"><label>colour</label><input data-name="colour" maxlength="24" value="${esc(v.colour || '')}"></div>
      </div>
      <div class="row3">
        <div class="field"><label>class</label><select data-name="type">
          ${classes.map(c => `<option value="${c}" ${v.type === c ? 'selected' : ''}>${c}</option>`).join('')}
        </select></div>
        <div class="field"><label>insurance</label><select data-name="insurance">
          ${['unknown', 'valid', 'expired', 'none'].map(s => `<option value="${s}" ${v.insurance === s ? 'selected' : ''}>${cap(s)}</option>`).join('')}
        </select></div>
        <div class="field"><label>registration</label><select data-name="registration">
          ${['valid', 'expired', 'revoked'].map(s => `<option value="${s}" ${(v.registration || 'valid') === s ? 'selected' : ''}>${cap(s)}</option>`).join('')}
        </select></div>
      </div>
      ${existing ? '' : citizenPicker('ownerId', 'registered_owner (optional)', '', '')}`,
    onConfirm: async (val) => {
      const res = existing
        ? await post('nz_mdt:vehicle:update', existing.plate, { model: val.model, colour: val.colour, type: val.type, insurance: val.insurance, registration: val.registration })
        : await post('nz_mdt:vehicle:create', val);
      if (reply(res)) {
        closeModal();
        if (S.page === 'vehicles') loadPage('vehicles');
        vehicleModal(existing ? existing.plate : res.plate);
      }
    }
  });
}

function weaponCreateModal() {
  openModal({
    title: 'firearm-db.exe — register', icon: 'gun', child: true,
    lede: 'Leave the serial blank and one is generated for you.',
    confirm: 'Register',
    body: `
      <div class="field"><label>weapon_name</label><input data-name="label" maxlength="60" placeholder="AP Pistol"></div>
      <div class="row2">
        <div class="field"><label>serial</label><input data-name="serial" maxlength="32" placeholder="Optional"></div>
        <div class="field"><label>weapon_type</label>
          <select data-name="weapon">
            <option value="">Not specified</option>
            ${(S.cfg.weaponList || []).map(w => `<option value="${esc(w.name)}">${esc(w.label)}</option>`).join('')}
          </select>
        </div>
      </div>
      ${citizenPicker('ownerId', 'registered_owner (optional)', '', '')}`,
    onConfirm: async (v) => {
      if (!v.label && v.weapon) {
        const w = (S.cfg.weaponList || []).find(x => x.name === v.weapon);
        if (w) v.label = w.label;
      }
      const res = await post('nz_mdt:weapon:create', v);
      if (reply(res)) { closeModal(); if (S.page === 'weapons') loadPage('weapons'); }
    }
  });
}

function propertyCreateModal() {
  openModal({
    title: 'property-db.exe — register', icon: 'house', confirm: 'Register', child: true,
    body: `
      <div class="field"><label>name</label><input data-name="label" maxlength="90" placeholder="4562 Grove Street"></div>
      <div class="field"><label>address</label><input data-name="address" maxlength="120"></div>
      <div class="field"><label>type</label><select data-name="type">
        <option value="residential">Residential</option><option value="commercial">Commercial</option>
        <option value="industrial">Industrial</option><option value="warehouse">Warehouse</option>
      </select></div>
      ${citizenPicker('ownerId', 'owner (optional)', '', '')}`,
    onConfirm: async (v) => {
      const res = await post('nz_mdt:property:create', v);
      if (reply(res)) { closeModal(); if (S.page === 'properties') loadPage('properties'); }
    }
  });
}

async function evidenceCreateModal(incidentRef) {
  const loc = await raw('myLocation');
  const types = (S.cfg.evidenceTypes || []).map(t => `<option value="${esc(t.id)}">${esc(t.label)}</option>`).join('');
  const lockers = (S.cfg.lockers || []).map(l => `<option value="${esc(l)}">${esc(l)}</option>`).join('');

  openModal({
    title: 'evidence-locker.exe — log item', icon: 'box-archive', child: true,
    lede: 'A chain of custody entry is opened the moment the item is logged.',
    confirm: 'Log it',
    body: `
      <div class="field"><label>description</label>
        <input data-name="description" maxlength="150" placeholder="Pistol, black, serial filed"></div>
      <div class="row2">
        <div class="field"><label>type</label><select data-name="type">${types}</select></div>
        <div class="field"><label>locker</label><select data-name="locker">${lockers}</select></div>
      </div>
      <div class="row2">
        <div class="field"><label>collected_at</label>
          <input data-name="location" maxlength="120" value="${esc((loc && loc.street) || '')}"></div>
        <div class="field"><label>linked_report</label>
          <input data-name="incidentRef" maxlength="20" placeholder="INC-000007" value="${esc(incidentRef || '')}"></div>
      </div>`,
    onConfirm: async (v) => {
      const res = await post('nz_mdt:evidence:create', v);
      if (reply(res)) { closeModal(); if (S.page === 'evidence') loadPage('evidence'); }
    }
  });
}

function callsignModal() {
  const prefix = ((S.cfg.departments || {})[S.me.department] || {}).callsignPrefix || '';
  openModal({
    title: 'roster.exe — callsign', icon: 'id-badge', child: true,
    lede: 'Callsigns are unique across the whole roster and show on every call you attach to.',
    confirm: 'Save',
    body: `<div class="field"><label>callsign</label>
      <input data-name="callsign" maxlength="12" value="${esc(S.me.callsign || '')}" placeholder="${esc(prefix)}-12" style="text-transform:uppercase"></div>`,
    onConfirm: async (v) => {
      const res = await post('nz_mdt:officer:callsign', v.callsign);
      if (reply(res)) {
        closeModal();
        S.me.callsign = res.callsign;
        windowChrome();
        renderHome();
        if (S.windowUp) loadPage(S.page);
      }
    }
  });
}

function announceModal() {
  openModal({
    title: 'bulletins.exe — post', icon: 'bullhorn', confirm: 'Post it', child: true, wide: 'wide',
    body: `
      <div class="field"><label>title</label><input data-name="title" maxlength="90"></div>
      <div class="field"><label>body</label><textarea data-name="body" maxlength="1200" style="min-height:14vh"></textarea></div>
      <div class="row2">
        <div class="field"><label>expires_after (days, 0 = never)</label>
          <input data-name="expireDays" type="number" min="0" max="90" value="${esc(S.cfg.bulletinDays != null ? S.cfg.bulletinDays : 7)}"></div>
        <div></div>
      </div>
      <div class="check">
        <div><b>Pin to the top</b><span>Pinned bulletins sit above everything else and show on the home screen.</span></div>
        <label class="switch"><input type="checkbox" data-name="pinned"><i></i></label>
      </div>
      <div class="check">
        <div><b>Send to every department</b><span>Leave this off to keep it inside your own department.</span></div>
        <label class="switch"><input type="checkbox" data-name="allDepartments"><i></i></label>
      </div>`,
    onConfirm: async (v) => {
      const res = await post('nz_mdt:announce:create', v);
      if (reply(res)) { closeModal(); if (S.page === 'announcements') loadPage('announcements'); scheduleDash(); }
    }
  });
}

function officerEditModal(o) {
  const statuses = (S.cfg.unitStatus || []).map(s => `<option value="${esc(s.id)}" ${o.status === s.id ? 'selected' : ''}>${esc(s.label)}</option>`).join('');
  openModal({
    title: `roster.exe — ${o.name}`, icon: 'user-pen', confirm: 'Save', child: true,
    body: `
      <div class="row2">
        <div class="field"><label>badge</label><input data-name="badge" maxlength="20" value="${esc(o.badge || '')}"></div>
        <div class="field"><label>callsign</label><input data-name="callsign" maxlength="12" value="${esc(o.callsign || '')}" style="text-transform:uppercase"></div>
      </div>
      <div class="field"><label>status</label><select data-name="status">${statuses}</select></div>
      ${o.onDuty ? `<div class="check">
        <div><b>Force off duty</b><span>Clocks the officer out and banks their shift.</span></div>
        <label class="switch"><input type="checkbox" data-name="clockOut"><i></i></label>
      </div>` : ''}`,
    onConfirm: async (v) => {
      const patch = {};
      if (v.badge.trim() && v.badge.trim() !== (o.badge || '')) patch.badge = v.badge.trim();
      if (v.callsign.trim() && v.callsign.trim().toUpperCase() !== (o.callsign || '')) patch.callsign = v.callsign.trim();
      if (v.status && v.status !== o.status) patch.status = v.status;
      if (v.clockOut) patch.onDuty = false;
      if (!Object.keys(patch).length) return backModal();
      const r = await post('nz_mdt:officer:update', o.identifier, patch);
      if (reply(r)) { closeModal(); loadPage('officers'); }
    }
  });
}

function cameraModal(existing) {
  const models = ((S.list.cameras && S.list.cameras.res && S.list.cameras.res.models) || S.cfg.cameraModels || []).map(m =>
    `<option value="${esc(m.model)}" ${existing && existing.model === m.model ? 'selected' : ''}>${esc(m.label)}</option>`).join('');

  const depts = Object.keys(S.cfg.departments || {}).map(d => {
    const on = existing ? (existing.departments || []).includes(d) : d === S.me.department;
    return `<option value="${esc(d)}" ${on ? 'selected' : ''}>${esc((S.cfg.departments[d] || {}).short || d)}</option>`;
  }).join('');

  openModal({
    title: existing ? 'cctv.exe — edit camera' : 'cctv.exe — place camera', icon: 'video', child: true,
    lede: existing
      ? 'Rename it, swap the model, or change which departments can watch it.'
      : 'The tablet goes away so you can aim it. Left click places it, right click backs out.',
    confirm: existing ? 'Save changes' : 'Start placing',
    body: `
      <div class="field"><label>camera_name</label>
        <input data-name="label" maxlength="90" value="${esc(existing ? existing.label : '')}" placeholder="Mission Row — rear lot"></div>
      <div class="field"><label>model</label><select data-name="model">${models}</select></div>
      <div class="field"><label>departments (ctrl-click for several)</label>
        <select data-name="departments" multiple size="5">${depts}</select></div>`,
    onConfirm: async (v) => {
      if (existing) {
        const res = await post('nz_mdt:camera:update', existing.id, { label: v.label, model: v.model, departments: v.departments || [] });
        if (reply(res)) { closeModal(); loadPage('cameras'); }
        return;
      }
      if ((v.label || '').trim().length < 2) return notify('Not completed', 'Give the camera a name.', true);
      closeModal();
      const res = await raw('cameraPlace', { label: v.label, model: v.model, departments: v.departments || [] });
      if (res && res.ok && S.page === 'cameras') loadPage('cameras');
    }
  });
}

/* ═══════════════════════════════════════════════════════════════════════════
   ACTIONS — one router for the home screen, the app window and the modals
   ═══════════════════════════════════════════════════════════════════════════ */
function openRecord(kind, id) {
  if (kind === 'citizen' || kind === 'warrant-citizen') return citizenModal(id);
  if (kind === 'vehicle') return vehicleModal(id);
  if (kind === 'weapon') return weaponModal(id);
  if (kind === 'incident') return incidentModalView(id);
  if (kind === 'evidence') return evidenceModal(id);
  if (kind === 'warrant') { closeModal(); openApp('warrants'); return; }
  if (kind === 'bolo') { closeModal(); openApp('bolos'); return; }
  if (kind === 'property') { closeModal(); openApp('properties'); return; }
}

const LIST_PAGE = {
  'incident-page': 'incidents', 'evidence-page': 'evidence', 'citizen-page': 'citizens',
  'vehicle-page': 'vehicles', 'weapon-page': 'weapons', 'property-page': 'properties', 'audit-page': 'audit'
};

async function doAction(act, el) {
  const id = el.dataset.id;
  const num = parseInt(id, 10);

  if (LIST_PAGE[act]) {
    const page = LIST_PAGE[act];
    S.list[page].page = parseInt(el.dataset.page, 10) || 1;
    loadPage(page);
    $('#view').scrollTop = 0;
    return;
  }

  if (/^calc-(plus|minus|reduce|del)$/.test(act)) {
    if (chargeOp(act, parseInt(el.dataset.i, 10))) render();
    return;
  }

  switch (act) {
    /* os */
    case 'app': closeModal(); openApp(el.dataset.app); break;
    case 'spotlight': openSpotlight(); break;
    case 'duty': toggleDuty(); break;
    case 'callsign': callsignModal(); break;
    case 'set-status': setStatus(el.dataset.status); break;
    case 'panic': panicModal(); break;
    case 'backup': backupModal(); break;

    /* dispatch */
    case 'call-select': {
      S.board.selected = S.board.selected === num ? null : num;
      if (S.page !== 'dispatch' || !S.windowUp) { openApp('dispatch'); break; }
      render();
      break;
    }
    case 'call-create': callCreateModal(); break;
    case 'board-closed': S.board.includeClosed = !S.board.includeClosed; loadPage('dispatch'); break;
    case 'call-attach': {
      const r = await post('nz_mdt:dispatch:attach', num);
      if (reply(r)) { if (r.call) mergeCall(r.call); render(); }
      break;
    }
    case 'call-detach': {
      const r = await post('nz_mdt:dispatch:detach', num);
      if (reply(r)) { if (r.call) mergeCall(r.call); render(); }
      break;
    }
    case 'call-close': callCloseModal(num); break;
    case 'call-route': { const r = await post('nz_mdt:dispatch:waypoint', num); reply(r); break; }
    case 'call-to-incident': {
      const call = S.board.calls.find(c => c.id === num);
      incidentModal(call ? {
        id: null, title: call.title, location: call.street || '', dispatchRef: call.ref,
        detail: call.detail || '', people: [], charges: []
      } : null);
      break;
    }

    /* bolo */
    case 'bolo-create': boloModal(null); break;
    case 'bolo-for-plate': boloModal({ kind: 'vehicle', plate: id, model: el.dataset.model || '', priority: 2 }); break;
    case 'bolo-for-person': boloModal({ kind: 'person', citizenId: id, title: `Locate ${el.dataset.name || ''}`.trim(), priority: 2 }); break;
    case 'bolo-edit': {
      const b = ((S.list.bolos || {}).rows || []).find(x => x.id === num);
      if (b) boloModal(b);
      break;
    }
    case 'bolo-resolve': { const r = await post('nz_mdt:bolo:resolve', num); if (reply(r)) { loadPage('bolos'); scheduleDash(); } break; }
    case 'bolo-delete':
      confirmModal('Delete this BOLO?', 'It disappears from the board for everyone. This cannot be undone.',
        'Delete it', async () => { const r = await post('nz_mdt:bolo:delete', num); if (reply(r)) { closeModal(); loadPage('bolos'); scheduleDash(); } });
      break;

    /* warrant */
    case 'warrant-create': warrantModal(); break;
    case 'warrant-for': warrantModal({ citizenId: id, citizenName: el.dataset.name }); break;
    case 'warrant-execute': { const r = await post('nz_mdt:warrant:execute', num); if (reply(r)) { loadPage('warrants'); scheduleDash(); } break; }
    case 'warrant-void':
      confirmModal('Void this warrant?', 'It stops being enforceable and stays on file as void.',
        'Void it', async () => { const r = await post('nz_mdt:warrant:void', num); if (reply(r)) { closeModal(); loadPage('warrants'); scheduleDash(); } });
      break;
    case 'warrant-delete':
      confirmModal('Delete this warrant?', 'It is removed entirely. This cannot be undone.',
        'Delete it', async () => { const r = await post('nz_mdt:warrant:delete', num); if (reply(r)) { closeModal(); loadPage('warrants'); scheduleDash(); } });
      break;

    /* incidents */
    case 'incident-new': incidentModal(null); break;
    case 'incident-for':
      incidentModal({ id: null, title: '', detail: '', location: (S.loc && S.loc.street) || '', dispatchRef: '',
        people: [{ citizenId: id, name: el.dataset.name || id, role: 'suspect' }], charges: [] });
      break;
    case 'incident-open': incidentModalView(isNaN(num) || String(num) !== String(id) ? id : num); break;
    case 'incident-mine': {
      const st = S.list.incidents = S.list.incidents || { search: '', status: 'all', page: 1, res: null };
      st.mine = !st.mine; st.page = 1; loadPage('incidents');
      break;
    }
    case 'incident-edit': {
      const r = await post('nz_mdt:incident:get', num);
      if (r && r.ok) {
        incidentModal({
          id: r.incident.id, ref: r.incident.ref, title: r.incident.title,
          detail: r.incident.detail || '', location: r.incident.location || '',
          dispatchRef: r.incident.dispatch_ref || '',
          people: (r.people || []).map(p => ({ citizenId: p.citizen_id, name: p.name, role: p.role })),
          charges: (r.charges || []).map(c => ({ id: c.charge_id, counts: c.counts, reduced: c.reduced === 1 || c.reduced === true, citizenId: c.citizen_id }))
        });
      } else reply(r);
      break;
    }
    case 'incident-delete':
      confirmModal('Delete this report?', 'Charges, linked people and the narrative all go with it.',
        'Delete it', async () => { const r = await post('nz_mdt:incident:delete', num); if (reply(r)) { closeModal(); if (S.page === 'incidents') loadPage('incidents'); scheduleDash(); } });
      break;

    /* calculator */
    case 'calc-add': {
      const hit = S.calc.find(c => c.id === id);
      if (hit) hit.counts = Math.min(20, hit.counts + 1);
      else S.calc.push({ id, counts: 1, reduced: false });
      render();
      break;
    }
    case 'calc-clear': S.calc = []; render(); break;
    case 'calc-report':
      incidentModal({ id: null, title: '', detail: '', location: (S.loc && S.loc.street) || '', dispatchRef: '',
        people: [], charges: S.calc.map(c => Object.assign({}, c)) });
      break;

    /* evidence */
    case 'evidence-new': evidenceCreateModal(); break;
    case 'evidence-for': evidenceCreateModal(id); break;
    case 'evidence-open': evidenceModal(isNaN(num) || String(num) !== String(id) ? id : num); break;
    case 'evidence-delete':
      confirmModal('Delete this item?', 'The chain of custody goes with it. This cannot be undone.',
        'Delete it', async () => { const r = await post('nz_mdt:evidence:delete', num); if (reply(r)) { closeModal(); if (S.page === 'evidence') loadPage('evidence'); } });
      break;

    /* citizens */
    case 'citizen-new': citizenCreateModal(null); break;
    case 'citizen-open': citizenModal(id); break;
    case 'citizen-edit': {
      const r = await post('nz_mdt:citizen:profile', id);
      if (r && r.ok) citizenCreateModal(r.citizen); else reply(r);
      break;
    }
    case 'citizen-delete':
      confirmModal('Delete this record?', 'Everything tied to the citizen ID is lost. This cannot be undone.',
        'Delete it', async () => { const r = await post('nz_mdt:citizen:delete', id); if (reply(r)) { closeModal(); if (S.page === 'citizens') loadPage('citizens'); } });
      break;

    /* vehicles */
    case 'vehicle-new': vehicleCreateModal(null); break;
    case 'vehicle-open': vehicleModal(id); break;
    case 'vehicle-edit': {
      const r = await post('nz_mdt:vehicle:profile', id);
      if (r && r.ok) vehicleCreateModal(r.vehicle); else reply(r);
      break;
    }
    case 'vehicle-delete':
      confirmModal('Remove this vehicle?', 'It comes off the registry entirely.',
        'Remove it', async () => { const r = await post('nz_mdt:vehicle:delete', id); if (reply(r)) { closeModal(); if (S.page === 'vehicles') loadPage('vehicles'); } });
      break;
    case 'plate-nearby': {
      const n = await raw('nearbyPlate');
      if (!n || !n.ok) { notify('No vehicle', 'Stand next to a vehicle or sit in one.', true); break; }
      vehicleModal(n.plate);
      break;
    }

    /* weapons */
    case 'weapon-new': weaponCreateModal(); break;
    case 'weapon-open': weaponModal(id); break;
    case 'weapon-delete':
      confirmModal('Remove this firearm?', 'It comes off the registry entirely.',
        'Remove it', async () => { const r = await post('nz_mdt:weapon:delete', id); if (reply(r)) { closeModal(); if (S.page === 'weapons') loadPage('weapons'); } });
      break;

    /* properties */
    case 'property-new': propertyCreateModal(); break;
    case 'property-delete':
      confirmModal('Remove this property?', 'The registry entry is deleted.',
        'Remove it', async () => { const r = await post('nz_mdt:property:delete', num); if (reply(r)) { closeModal(); loadPage('properties'); } });
      break;

    /* officers */
    case 'officer-onduty': S.list.officers.onDuty = !S.list.officers.onDuty; loadPage('officers'); break;
    case 'officer-edit': {
      const o = ((S.list.officers || {}).rows || []).find(x => x.identifier === id);
      if (o) officerEditModal(o);
      break;
    }

    /* bulletins */
    case 'announce-new': announceModal(); break;
    case 'announce-delete':
      confirmModal('Remove this bulletin?', 'It comes off every terminal.',
        'Remove it', async () => { const r = await post('nz_mdt:announce:delete', num); if (reply(r)) { closeModal(); loadPage('announcements'); scheduleDash(); } });
      break;

    /* cameras */
    case 'camera-new': cameraModal(null); break;
    case 'camera-view': raw('cameraOpen', { id }); break;
    case 'camera-repair': { const res = await post('nz_mdt:camera:repair', id); if (reply(res)) loadPage('cameras'); break; }
    case 'camera-edit': {
      const cam = (((S.list.cameras || {}).res || {}).rows || []).find(c => c.id === id);
      if (cam) cameraModal(cam);
      break;
    }
    case 'camera-move': raw('cameraMove', { id, model: el.dataset.model }); break;
    case 'camera-delete':
      confirmModal('Remove this camera?', 'It comes off the network and out of the world.',
        'Remove it', async () => { const r = await post('nz_mdt:camera:delete', id); if (reply(r)) { closeModal(); loadPage('cameras'); } });
      break;

    /* map */
    case 'map-style':
      S.map.style = el.dataset.style;
      try { localStorage.setItem('nz_mdt_map', S.map.style); } catch (e) {}
      render();
      break;
    case 'map-zoom': {
      const dir = el.dataset.dir;
      if (dir === 'in') mapZoom(1.4);
      else if (dir === 'out') mapZoom(1 / 1.4);
      else if (dir === 'me') mapFocusMe();
      else mapReset();
      break;
    }

    /* notepad */
    case 'note-new': {
      const n = { id: 'n' + Date.now().toString(36), title: '', body: '', updated: Date.now() };
      S.notes.unshift(n);
      if (S.notes.length > 40) S.notes.length = 40;
      S.noteSel = n.id;
      render();
      saveNotesSoon();
      const t = $('#noteTitle'); if (t) t.focus();
      break;
    }
    case 'note-pick': S.noteSel = id; render(); break;
    case 'note-delete':
      confirmModal('Delete this note?', 'It is removed from your tablet.', 'Delete it', async () => {
        S.notes = S.notes.filter(n => n.id !== id);
        S.noteSel = S.notes[0] ? S.notes[0].id : null;
        closeModal();
        render();
        saveNotesSoon();
      });
      break;

    /* settings */
    case 'set-wall': S.settings.wallpaper = id; applySettings(); saveSettings(); render(); break;
    case 'set-scale': S.settings.scale = parseFloat(el.dataset.scale) || 1; applySettings(); saveSettings(); render(); break;
    case 'settings-reset':
      S.settings = Object.assign({}, DEFAULT_SETTINGS);
      applySettings(); saveSettings(); render();
      notify('Settings reset', 'Back to the defaults.');
      break;
    default: break;
  }
}

function mergeCall(call) {
  const i = S.board.calls.findIndex(c => c.id === call.id);
  if (i >= 0) S.board.calls[i] = call; else S.board.calls.unshift(call);
}

/* ═══════════════════════════════════════════════════════════════════════════
   LIVE EVENTS
   ═══════════════════════════════════════════════════════════════════════════ */
function liveNotify(title, body, kind) {
  if (S.settings.notifications === false) return;
  notify(title, body, kind);
}

function onLive(event, data) {
  switch (event) {
    case 'dispatch:new':
      if (!data) break;
      S.board.calls = [data, ...S.board.calls.filter(c => c.id !== data.id)];
      refreshBoardParts(true);
      liveNotify(`${data.code || ''} ${data.title}`.trim(), data.street || 'Location unknown', data.priority === 1 ? true : 'warn');
      scheduleDash();
      break;

    case 'dispatch:update':
      if (!data) break;
      mergeCall(data);
      refreshBoardParts(true);
      break;

    case 'dispatch:closed':
      if (data && data.id) {
        if (S.board.includeClosed) {
          const c = S.board.calls.find(x => x.id === data.id);
          if (c) c.status = 'closed';
        } else {
          S.board.calls = S.board.calls.filter(c => c.id !== data.id);
          if (S.board.selected === data.id) S.board.selected = null;
        }
      } else if (data && data.all) {
        S.board.calls = S.board.includeClosed ? S.board.calls : [];
        S.board.selected = null;
      }
      refreshBoardParts(true);
      scheduleDash();
      break;

    case 'map:officers':
      // frequent — repaint pins only, never re-query the dashboard
      S.board.officers = Array.isArray(data) ? data : [];
      refreshBoardParts(false);
      break;

    case 'roster:update':
      S.board.officers = Array.isArray(data) ? data : [];
      refreshBoardParts(false);
      if (S.page === 'officers' && S.windowUp) loadPage('officers');
      scheduleDash();
      break;

    case 'panic':
      if (data) {
        S.panics[data.identifier] = data;
        setTimeout(() => { delete S.panics[data.identifier]; refreshBoardParts(false); }, (data.duration || 120) * 1000);
        refreshBoardParts(false);
        notify('PANIC BUTTON', `${data.callsign || data.name} — ${data.street || 'unknown location'}`, true, 9000);
      }
      break;

    case 'panic:move':
      if (data && S.panics[data.identifier]) {
        S.panics[data.identifier].x = data.x;
        S.panics[data.identifier].y = data.y;
        refreshBoardParts(false);
      }
      break;

    case 'alpr':
      if (data && data.hits && data.hits[0]) {
        notify(`Plate reader — ${data.plate}`, `${data.hits[0].label}${data.hits[0].detail ? ' · ' + data.hits[0].detail : ''}`,
          data.hits[0].tone === 'red' ? true : 'warn', 7000);
      }
      break;

    case 'bolo:new':
      if (data) liveNotify('BOLO issued', data.title, 'warn');
      if (S.page === 'bolos' && S.windowUp) loadPage('bolos');
      scheduleDash();
      break;
    case 'bolo:update':
      if (S.page === 'bolos' && S.windowUp) loadPage('bolos');
      scheduleDash();
      break;

    case 'warrant:new':
      if (data) liveNotify('Warrant issued', data.citizen, true);
      if (S.page === 'warrants' && S.windowUp) loadPage('warrants');
      scheduleDash();
      break;
    case 'warrant:update':
      if (S.page === 'warrants' && S.windowUp) loadPage('warrants');
      scheduleDash();
      break;

    case 'incident:update':
      if (S.page === 'incidents' && S.windowUp) loadPage('incidents');
      scheduleDash(3000);
      break;

    case 'announce:new':
      if (data) liveNotify('Department bulletin', data.title);
      if (S.page === 'announcements' && S.windowUp) loadPage('announcements');
      scheduleDash();
      break;

    case 'camera:update':
      if (S.page === 'cameras' && S.windowUp) loadPage('cameras');
      break;

    case 'duty':
      if (data) {
        S.me.onDuty = data.onDuty;
        if (!data.onDuty) S.me.status = 'break';
        renderTaskbar();
        renderHome();
      }
      break;
    default: break;
  }
}

/* ═══════════════════════════════════════════════════════════════════════════
   ON-SCREEN DISPATCH CARD
   One call at a time, paged from the game with the keyboard. It never takes
   focus, so the officer keeps driving while reading it.
   ═══════════════════════════════════════════════════════════════════════════ */
function renderWidget(payload) {
  if (payload) {
    S.card.calls = (payload.calls || []).map(c => Object.assign({ kind: 'call' }, c));
    S.card.panics = Object.values(payload.panics || {}).map(p => Object.assign({ kind: 'panic' }, p));
    if (payload.keys) S.card.keys = payload.keys;
    if (typeof payload.index === 'number') S.card.index = payload.index;
    if (payload.me) S.card.me = payload.me;
    if (payload.pos) S.card.pos = payload.pos;
  }

  const rows = S.card.panics.concat(S.card.calls);
  const total = rows.length;
  if (S.card.index >= total) S.card.index = Math.max(0, total - 1);
  const entry = rows[S.card.index];

  const page = $('#wPage'), body = $('#wBody'), foot = $('#wFoot');
  if (!body) return;

  page.textContent = total ? `${S.card.index + 1} / ${total}` : '0 / 0';
  page.classList.toggle('hot', S.card.panics.length > 0);

  if (!entry) {
    body.innerHTML = `<div class="wempty-card">${fa('circle-check')}<b>The board is clear</b><span>New calls land here the moment they come in.</span></div>`;
    foot.innerHTML = '';
    return;
  }

  const dist = (x, y) => {
    const p = S.card.pos;
    if (!p || x == null || y == null) return '';
    const d = Math.hypot(p.x - x, p.y - y);
    return d >= 1000 ? `${(d / 1000).toFixed(1)} km` : `${Math.round(d)} m`;
  };

  if (entry.kind === 'panic') {
    body.innerHTML = `
      <div class="wcard p1 panic">
        <div class="wcard-top">
          <span class="dot red"></span>
          <span class="ref">PANIC BUTTON</span>
          <span class="state pending">ACTIVE</span>
        </div>
        <h4>Officer needs assistance</h4>
        <div class="wline">${ICON.badge}<span>${esc(entry.callsign || entry.name || 'Unknown unit')}</span></div>
        <div class="wline">${ICON.pin}<span>${esc(entry.street || 'Location unknown')}</span><span class="dist">${dist(entry.x, entry.y)}</span></div>
        <p class="wdetail">Every available unit is asked to respond immediately.</p>
      </div>`;
  } else {
    body.innerHTML = `
      <div class="wcard ${priorityClass(entry.priority)}">
        <div class="wcard-top">
          <span class="dot ${priorityTone(entry.priority) === 'teal' ? '' : priorityTone(entry.priority)}"></span>
          <span class="ref">${esc(entry.ref)}</span>
          <span class="code">${esc(entry.code || '')}</span>
          <span class="state ${esc(entry.status)}">${esc(stateLabel(entry.status))}</span>
        </div>
        <h4>${esc(entry.title)}</h4>
        <div class="wline">${ICON.pin}<span>${esc(entry.street || 'Location unknown')}</span><span class="dist">${dist(entry.x, entry.y)}</span></div>
        <div class="wline">${ICON.clock}<span>${esc(ago(entry.ageSeconds))}${entry.units && entry.units.length ? ' · ' + plural(entry.units.length, 'unit') + ' attached' : ''}</span></div>
        ${entry.plate ? `<div class="wline">${ICON.car}<span>${esc(entry.plate)}</span></div>` : ''}
        ${entry.detail ? `<p class="wdetail">${esc(entry.detail)}</p>` : ''}
      </div>`;
  }

  const k = S.card.keys || { prev: 'LEFT', next: 'RIGHT', accept: 'U' };
  const meId = S.card.me || (S.me && S.me.identifier);
  const mine = entry.kind === 'call' && (entry.units || []).some(u => u.identifier === meId);

  foot.innerHTML = `
    <span class="wkey ${total > 1 ? '' : 'off'}"><span class="kbd">${esc(k.prev)}</span>Prev</span>
    <span class="wkey accept ${mine ? 'on' : ''}"><span class="kbd">${esc(k.accept)}</span>${mine ? 'Attached' : entry.kind === 'panic' ? 'Route' : 'Respond'}</span>
    <span class="wkey ${total > 1 ? '' : 'off'}"><span class="kbd">${esc(k.next)}</span>Next</span>`;
}

/* ═══════════════════════════════════════════════════════════════════════════
   LIVE CAMERA OVERLAY
   ═══════════════════════════════════════════════════════════════════════════ */
function cameraOverlay(cam) {
  let el = $('#camOverlay');
  if (!el) {
    el = document.createElement('div');
    el.id = 'camOverlay';
    document.body.appendChild(el);
  }

  if (!cam) {
    el.classList.remove('up');
    el.innerHTML = '';
    $('#app').classList.remove('shooting');
    return;
  }

  const now = new Date().toLocaleString('en-GB', { hour12: false });
  el.innerHTML = `
    <div class="scan"></div>
    <div class="vig"></div>
    <div class="corner tl"></div><div class="corner tr"></div><div class="corner bl"></div><div class="corner br"></div>
    <div class="hud">
      <div class="tagline">
        <b>${esc(cam.label)}</b>
        <span><b></b>LIVE · ${esc(cam.id)} · ${esc(now)}</span>
      </div>
      <div class="keys">
        <div><span class="kbd">← → ↑ ↓</span> pan and tilt</div>
        <div><span class="kbd">SCROLL</span> zoom</div>
        <div><span class="kbd">ESC</span> back to the tablet</div>
      </div>
    </div>`;
  el.classList.add('up');
  $('#app').classList.add('shooting');
}

/* ═══════════════════════════════════════════════════════════════════════════
   ZOOMABLE MAP — the transform survives re-renders
   ═══════════════════════════════════════════════════════════════════════════ */
function mapStyle() {
  const styles = S.cfg.mapStyles || [];
  const want = S.map.style || S.cfg.mapStyle;
  return styles.find(x => x.id === want) || styles[0] || { id: 'grid', label: 'Grid', file: false };
}

function mapGeometry() {
  const vp = $('#mapViewport');
  if (!vp) return null;
  const w = vp.clientWidth, h = vp.clientHeight;
  return { vp, w, h, size: Math.max(w, h) };
}

function mapClamp(g) {
  const span = g.size * S.map.scale;
  const minX = g.w - span, minY = g.h - span;
  S.map.x = minX > 0 ? minX / 2 : Math.max(minX, Math.min(0, S.map.x));
  S.map.y = minY > 0 ? minY / 2 : Math.max(minY, Math.min(0, S.map.y));
}

function mapApply() {
  const plane = $('#mapPlane');
  const g = mapGeometry();
  if (!plane || !g || !g.w) return;

  plane.style.width = g.size + 'px';
  plane.style.height = g.size + 'px';

  if (S.map.fresh) {
    // first paint: sit the island in the middle of the viewport
    S.map.x = (g.w - g.size) / 2;
    S.map.y = (g.h - g.size) / 2;
    S.map.fresh = false;
  }
  mapClamp(g);

  plane.style.transform = `translate(${S.map.x}px, ${S.map.y}px) scale(${S.map.scale})`;
  plane.querySelectorAll('.pin').forEach(p => {
    p.style.transform = `translate(-50%, -50%) scale(${1 / S.map.scale})`;
  });

  const scale = $('#mapScale');
  if (scale) scale.textContent = Math.round(S.map.scale * 100) + '%';
}

function mapZoom(factor, clientX, clientY) {
  const g = mapGeometry();
  if (!g) return;
  const next = Math.max(S.map.min, Math.min(S.map.max, S.map.scale * factor));
  if (next === S.map.scale) return;

  const rect = g.vp.getBoundingClientRect();
  const k = rect.width / g.w || 1;   // the tablet itself may be scaled
  const px = clientX == null ? g.w / 2 : (clientX - rect.left) / k;
  const py = clientY == null ? g.h / 2 : (clientY - rect.top) / k;

  const ratio = next / S.map.scale;
  S.map.x = px - (px - S.map.x) * ratio;
  S.map.y = py - (py - S.map.y) * ratio;
  S.map.scale = next;
  mapApply();
}

function mapReset() {
  S.map.scale = 1;
  S.map.fresh = true;
  mapApply();
}

function mapFocusMe() {
  const g = mapGeometry();
  if (!g || !S.loc) return notify('Map', 'Your position is not known yet.', 'warn');
  if (S.map.scale < 3) S.map.scale = 3;
  const p = mapPin(S.loc.x, S.loc.y);
  const span = g.size * S.map.scale;
  S.map.x = g.w / 2 - (p.left / 100) * span;
  S.map.y = g.h / 2 - (p.top / 100) * span;
  mapApply();
}

(function bindMap() {
  let dragging = false, startX = 0, startY = 0, originX = 0, originY = 0, k = 1;

  document.addEventListener('mousedown', (e) => {
    const vp = e.target.closest('#mapViewport');
    if (!vp || e.button !== 0 || e.target.closest('.pin:not(.unit)')) return;
    dragging = true;
    startX = e.clientX; startY = e.clientY;
    originX = S.map.x; originY = S.map.y;
    k = vp.getBoundingClientRect().width / vp.clientWidth || 1;
    vp.classList.add('dragging');
  });

  document.addEventListener('mousemove', (e) => {
    if (!dragging) return;
    S.map.x = originX + (e.clientX - startX) / k;
    S.map.y = originY + (e.clientY - startY) / k;
    mapApply();
  });

  document.addEventListener('mouseup', () => {
    if (!dragging) return;
    dragging = false;
    const vp = $('#mapViewport');
    if (vp) vp.classList.remove('dragging');
  });

  document.addEventListener('wheel', (e) => {
    const vp = e.target.closest('#mapViewport');
    if (!vp) return;
    e.preventDefault();
    mapZoom(e.deltaY < 0 ? 1.22 : 1 / 1.22, e.clientX, e.clientY);
  }, { passive: false });

  window.addEventListener('resize', () => { if (S.page === 'dispatch') mapApply(); });
})();

/* ═══════════════════════════════════════════════════════════════════════════
   PHOTOS
   ═══════════════════════════════════════════════════════════════════════════ */
function photoTiles(photos) {
  return (photos || []).map(p => `
    <div class="photo ${p.avatar ? 'avatar' : ''}" data-inner="photo-open" data-url="${esc(p.url)}" data-cap="${esc(p.description || '')}">
      <img src="${esc(p.url)}" alt="" loading="lazy">
      ${p.avatar ? '<span class="pin-badge">RECORD</span>' : ''}
      <div class="tools">
        ${can('photo.avatar') ? `<button data-inner="photo-avatar" data-id="${p.id}" title="${p.avatar ? 'Clear record picture' : 'Set as record picture'}">${ICON.star}</button>` : ''}
        ${can('photo.delete') ? `<button class="danger" data-inner="photo-del" data-id="${p.id}" title="Delete">${ICON.trash}</button>` : ''}
      </div>
      ${p.description ? `<div class="cap">${esc(p.description)}</div>` : ''}
    </div>`).join('') || emptyState('cam', 'No photos', 'Anything you capture here stays on the record.');
}

function photoBlock(subject, subjectId, photos) {
  const ready = S.photoReady;
  return `
    <div>
      <div class="section-label">
        photos <span class="tally">${(photos || []).length}</span>
        ${can('photo.take') ? `<span class="push">
          <button class="btn-ghost" ${ready ? '' : `disabled title="${esc(S.photoReason || 'Photo capture is off')}"`}
            data-inner="photo-take" data-subject="${esc(subject)}" data-sid="${esc(subjectId)}">${fa('camera')} Take photo</button>
          <button class="btn-ghost" data-inner="photo-paste" data-subject="${esc(subject)}" data-sid="${esc(subjectId)}">${ICON.link} Add link</button>
        </span>` : ''}
      </div>
      <div class="photogrid" id="photoGrid">${photoTiles(photos)}</div>
    </div>`;
}

function refreshPhotos(rows) {
  const grid = $('#photoGrid');
  if (grid) grid.innerHTML = photoTiles(rows);
}

function lightbox(url, caption) {
  const el = $('#lightbox');
  el.innerHTML = `<button class="x">${fa('times')}</button><img src="${esc(url)}" alt="">
    ${caption ? `<div class="cap">${esc(caption)}</div>` : ''}`;
  el.classList.add('up');
}
$('#lightbox').addEventListener('click', () => $('#lightbox').classList.remove('up'));

/* ═══════════════════════════════════════════════════════════════════════════
   LINKS
   ═══════════════════════════════════════════════════════════════════════════ */
function linkIcon(kind) {
  const t = (S.cfg.linkTypes || []).find(x => x.id === kind);
  return t ? t.icon : 'file';
}

function linkRows(links, subject, subjectId) {
  return (links || []).map(l => `
    <div class="linkrow ${l.hot ? 'hot' : ''}">
      <div class="ic sm ${l.hot ? 'red' : ''}">${icon(linkIcon(l.kind))}</div>
      <div class="row-txt" data-inner="link-open" data-kind="${esc(l.kind)}" data-id="${esc(l.id)}">
        <b>${esc(l.title)}</b><span>${esc(l.sub || '')}${l.note ? ' · ' + esc(l.note) : ''}</span>
      </div>
      <span class="kindtag">${esc(l.kind)}</span>
      ${can('link.remove') ? `<button class="icobtn danger" data-inner="link-del" data-id="${l.linkId}"
        data-subject="${esc(subject)}" data-sid="${esc(subjectId)}" title="Unlink">${ICON.x}</button>` : ''}
    </div>`).join('') || emptyState('link', 'Nothing linked', 'Tie this record to a person, a plate, a case or a piece of evidence.');
}

function linkBlock(subject, subjectId, links) {
  if (!(S.cfg.linkTypes || []).length) return '';
  const types = (S.cfg.linkTypes || []).map(t => `<option value="${esc(t.id)}">${esc(t.label)}</option>`).join('');
  return `
    <div>
      <div class="section-label">linked_records <span class="tally">${(links || []).length}</span></div>
      ${can('link.create') ? `
        <div class="inline" style="margin-bottom:0.8vh">
          <div class="field narrow"><select id="linkKind">${types}</select></div>
          <div class="field"><input class="input" id="linkSearch" placeholder="Search for a record to link" autocomplete="off"></div>
          <button class="btn-line" data-inner="link-find" data-subject="${esc(subject)}" data-sid="${esc(subjectId)}">${ICON.search} Find</button>
        </div>
        <div id="linkResults"></div>` : ''}
      <div class="scroll short" id="linkList">${linkRows(links, subject, subjectId)}</div>
    </div>`;
}

function refreshLinks(rows, subject, subjectId) {
  const list = $('#linkList');
  if (list) list.innerHTML = linkRows(rows, subject, subjectId);
}

/* ═══════════════════════════════════════════════════════════════════════════
   SPOTLIGHT SEARCH
   ═══════════════════════════════════════════════════════════════════════════ */
let omniTimer = null;
let omniSel = 0;

function openSpotlight() {
  closePopover();
  const sp = $('#spotlight');
  sp.classList.add('up');
  const input = $('#omni');
  input.value = '';
  $('#omniDrop').innerHTML = `<div class="wempty">Type at least two characters.</div>`;
  setTimeout(() => input.focus(), 30);
}

function closeSpotlight() {
  $('#spotlight').classList.remove('up');
}

function omniPaint() {
  $$('#omniDrop button').forEach((b, i) => b.classList.toggle('sel', i === omniSel));
}

$('#omni').addEventListener('input', (e) => {
  const term = e.target.value.trim();
  const drop = $('#omniDrop');
  clearTimeout(omniTimer);
  if (term.length < 2) { drop.innerHTML = `<div class="wempty">Type at least two characters.</div>`; return; }

  omniTimer = setTimeout(async () => {
    const r = await post('nz_mdt:search', term);
    const rows = (r && r.rows) || [];
    omniSel = 0;
    drop.innerHTML = rows.length ? rows.map(x => `
      <button data-kind="${esc(x.kind)}" data-id="${esc(x.id)}">
        <div class="ic sm ${x.hot ? 'red' : ''}">${
          x.kind === 'citizen' ? ICON.user : x.kind === 'vehicle' ? ICON.car :
          x.kind === 'weapon' ? ICON.gun : x.kind === 'warrant' ? ICON.warn :
          x.kind === 'evidence' ? ICON.box : ICON.file}</div>
        <div style="flex:1;min-width:0"><b>${esc(x.title)}</b><span>${esc(x.sub || '')}</span></div>
        <span class="kindtag">${esc(x.kind)}</span>
      </button>`).join('') : `<div class="wempty">Nothing matched “${esc(term)}”.</div>`;
    omniPaint();
  }, 220);
});

$('#omni').addEventListener('keydown', (e) => {
  const items = $$('#omniDrop button');
  if (e.key === 'ArrowDown') { e.preventDefault(); omniSel = Math.min(items.length - 1, omniSel + 1); omniPaint(); }
  else if (e.key === 'ArrowUp') { e.preventDefault(); omniSel = Math.max(0, omniSel - 1); omniPaint(); }
  else if (e.key === 'Enter' && items[omniSel]) { e.preventDefault(); items[omniSel].click(); }
});

$('#omniDrop').addEventListener('click', (e) => {
  const btn = e.target.closest('button[data-kind]');
  if (!btn) return;
  closeSpotlight();
  // warrants open the wanted person's record
  openRecord(btn.dataset.kind === 'warrant' ? 'citizen' : btn.dataset.kind, btn.dataset.id);
});

$('#spotlight').addEventListener('click', (e) => { if (e.target.id === 'spotlight') closeSpotlight(); });

/* ═══════════════════════════════════════════════════════════════════════════
   EVENT WIRING
   ═══════════════════════════════════════════════════════════════════════════ */
$('#lockScreen').addEventListener('click', () => { skipIntro = true; });
$('#console').addEventListener('click', () => { skipIntro = true; });

$('#btnPower').addEventListener('click', closeUI);
$('#btnHome').addEventListener('click', goHome);
$('#btnSearch').addEventListener('click', openSpotlight);
$('#taskDuty').addEventListener('click', toggleDuty);
$('#taskStatus').addEventListener('click', (e) => { e.stopPropagation(); if (S.me && S.me.onDuty) statusPopover(); });

$('#winMin').addEventListener('click', minimizeApp);
$('#winClose').addEventListener('click', () => closeApp());
$('#winRefresh').addEventListener('click', () => { if (S.page) { setFooterRight('syncing…'); loadPage(S.page); } });

$('#dock').addEventListener('click', (e) => {
  const b = e.target.closest('[data-dock]');
  if (!b) return;
  const id = b.dataset.dock;
  if (S.page === id && S.windowUp) minimizeApp(); else openApp(id);
});

$('#dock').addEventListener('contextmenu', (e) => {
  const b = e.target.closest('[data-dock]');
  if (!b) return;
  e.preventDefault();
  closeApp(b.dataset.dock);
});

// clicks on the home screen, the app window and the status popover share one router
['#home', '#view', '#popover'].forEach(sel => {
  $(sel).addEventListener('click', (e) => {
    const el = e.target.closest('[data-act]');
    if (!el || el.tagName === 'SELECT' || el.tagName === 'INPUT') return;
    doAction(el.dataset.act, el);
  });
});

document.addEventListener('click', (e) => {
  if (!e.target.closest('#popover') && !e.target.closest('#taskStatus')) closePopover();
});

$('#veil').addEventListener('click', async (e) => {
  if (e.target.id === 'veil') {
    // never throw away a half-filled form by clicking outside it
    const modal = $('#veil .modal');
    if (modal && modal.dataset.hasconfirm === '0') backModal();
    return;
  }
  const m = e.target.closest('[data-modal]');
  if (m) {
    if (m.dataset.modal === 'cancel') return backModal();
    if (modalConfirm && !m.disabled) {
      m.disabled = true;
      try { await modalConfirm(modalValues()); } finally { m.disabled = false; }
    }
    return;
  }
  const inner = e.target.closest('[data-inner]');
  if (inner) return handleInner(inner.dataset.inner, inner);
  const act = e.target.closest('[data-act]');
  if (act && act.tagName !== 'SELECT' && act.tagName !== 'INPUT') return doAction(act.dataset.act, act);
});

// dropdowns that act on change, inside modals and pages alike
async function onChange(e) {
  const el = e.target;

  if (el.dataset.setting) {
    S.settings[el.dataset.setting] = el.checked;
    applySettings();
    saveSettings();
    return;
  }

  const kind = el.dataset.change;
  if (kind === 'licence') {
    const res = await post('nz_mdt:citizen:licence', el.dataset.cid, el.dataset.lic, el.value);
    if (reply(res)) citizenModal(el.dataset.cid, true);
    return;
  }
  if (kind === 'person-role') {
    const i = parseInt(el.dataset.i, 10);
    if (S.draft && S.draft.people[i]) S.draft.people[i].role = el.value;
    return;
  }
  if (kind === 'call-status') {
    const r = await post('nz_mdt:dispatch:unitStatus', parseInt(el.dataset.id, 10), el.value);
    if (reply(r)) {
      if (r.call) mergeCall(r.call);
      S.me.status = el.value;
      renderTaskbar();
      render();
    }
    return;
  }

  const act = el.dataset.act;
  if (!act) return;
  const v = el.value;
  const list = (k, d) => (S.list[k] = S.list[k] || d);
  switch (act) {
    case 'bolo-filter': list('bolos', { search: '' }).filter = v; loadPage('bolos'); break;
    case 'warrant-filter': list('warrants', { search: '' }).filter = v; loadPage('warrants'); break;
    case 'incident-status': { const st = list('incidents', { search: '', page: 1 }); st.status = v; st.page = 1; loadPage('incidents'); break; }
    case 'evidence-status': { const st = list('evidence', { search: '', page: 1 }); st.status = v; st.page = 1; loadPage('evidence'); break; }
    case 'vehicle-filter': { const st = list('vehicles', { search: '', page: 1 }); st.filter = v; st.page = 1; loadPage('vehicles'); break; }
    case 'camera-status': list('cameras', { search: '' }).status = v; loadPage('cameras'); break;
    case 'charge-cat': list('charges', { search: '', category: 'all' }).category = v; render(); break;
    default: break;
  }
}
$('#view').addEventListener('change', onChange);
$('#veil').addEventListener('change', onChange);

// search boxes
let searchTimer = null;
const SEARCHES = {
  'bolo-search': ['bolos', false], 'warrant-search': ['warrants', false], 'incident-search': ['incidents', true],
  'evidence-search': ['evidence', true], 'citizen-search': ['citizens', true], 'vehicle-search': ['vehicles', true],
  'weapon-search': ['weapons', true], 'property-search': ['properties', true], 'officer-search': ['officers', false],
  'audit-search': ['audit', true], 'camera-search': ['cameras', false]
};

$('#view').addEventListener('input', (e) => {
  const el = e.target;

  if (el.id === 'noteTitle' || el.id === 'noteText') {
    const n = S.notes.find(x => x.id === S.noteSel);
    if (!n) return;
    if (el.id === 'noteTitle') n.title = el.value; else n.body = el.value;
    n.updated = Date.now();
    const item = $(`#view .notepad .item.on b`);
    if (item && el.id === 'noteTitle') item.textContent = el.value || 'Untitled';
    saveNotesSoon();
    return;
  }

  const act = el.dataset.act;
  if (!act) return;
  const v = el.value;

  // client-side filters repaint straight away
  if (act === 'charge-search' || act === 'codes-search') {
    const key = act === 'charge-search' ? 'charges' : 'codes';
    S.list[key] = S.list[key] || { search: '', category: 'all' };
    S.list[key].search = v;
    render();
    return;
  }

  const hit = SEARCHES[act];
  if (!hit) return;
  const [page, paged] = hit;
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => {
    const st = S.list[page] = S.list[page] || { search: '' };
    st.search = v;
    if (paged) st.page = 1;
    loadPage(page);
  }, 300);
});

$('#veil').addEventListener('input', (e) => {
  if (e.target.matches('[data-pick-search]')) pickerSearch(e.target);
});

$('#veil').addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && e.target.id === 'personSearch') {
    e.preventDefault();
    const btn = $('#veil [data-inner="person-find"]');
    if (btn) btn.click();
  } else if (e.key === 'Enter' && e.target.id === 'linkSearch') {
    e.preventDefault();
    const btn = $('#veil [data-inner="link-find"]');
    if (btn) btn.click();
  }
});

/* keyboard */
document.addEventListener('keydown', (e) => {
  if (!S.visible) return;

  if (e.key === 'Escape') {
    e.preventDefault();
    if ($('#lightbox').classList.contains('up')) return $('#lightbox').classList.remove('up');
    if ($('#spotlight').classList.contains('up')) return closeSpotlight();
    if ($('#popover').innerHTML) return closePopover();
    if (veilUp()) return backModal();
    if (!S.unlocked) return closeUI();
    if (S.windowUp) return minimizeApp();
    return closeUI();
  }

  if (!S.unlocked || veilUp() || $('#spotlight').classList.contains('up')) return;

  const typing = ['INPUT', 'SELECT', 'TEXTAREA'].includes(e.target.tagName);
  if (typing || e.ctrlKey || e.altKey || e.metaKey) return;

  if (e.key === '/') { e.preventDefault(); openSpotlight(); return; }
  if (e.key.toLowerCase() === 'h') { goHome(); return; }

  const k = e.key.toLowerCase();
  const app = Object.keys(APPS).find(id => APPS[id].key === k && appAllowed(id));
  if (app) openApp(app);
});

/* ═══════════════════════════════════════════════════════════════════════════
   MESSAGE PUMP
   ═══════════════════════════════════════════════════════════════════════════ */
async function onOpen(m) {
  const data = m.data || {};
  const fresh = !S.me || !data.me || S.me.identifier !== data.me.identifier || m.relock === true;

  S.boot = data;
  S.cfg = data.config || {};
  S.perms = {};
  (data.perms || []).forEach(p => { S.perms[p] = true; });

  if (m.settings && typeof m.settings === 'object') S.settings = Object.assign({}, DEFAULT_SETTINGS, m.settings);
  else if (!IN_GAME) { try { S.settings = Object.assign({}, DEFAULT_SETTINGS, JSON.parse(localStorage.getItem('nz_mdt_settings') || '{}')); } catch (e) {} }

  if (fresh) {
    S.me = data.me;
    S.page = null;
    S.open = [];
    S.windowUp = false;
    S.list = {};
    S.calc = [];
    S.dash = null;
    S.booted = false;
    S.board = { calls: [], officers: [], selected: null, includeClosed: false };
    S.map = { scale: 1, x: 0, y: 0, min: 1, max: 6, style: null, fresh: true };
    try { S.map.style = localStorage.getItem('nz_mdt_map') || null; } catch (e) {}
    $('#windowWrap').classList.add('hidden');
  } else {
    // same officer — keep their apps and lists, refresh who they are
    Object.assign(S.me, data.me);
    // permissions may have changed with a promotion
    S.open = S.open.filter(appAllowed);
    if (S.page && !appAllowed(S.page)) { S.page = null; S.windowUp = false; $('#windowWrap').classList.add('hidden'); }
  }

  applySettings();
  showTablet();
  renderTaskbar();
  renderDock();
  renderHome();

  const lockMode = (S.cfg.tablet && S.cfg.tablet.lockScreen) || 'first';
  const needLock = fresh ? lockMode !== 'never' : lockMode === 'always';
  S.unlocked = !needLock;

  if (needLock) {
    runLock();
  } else {
    $('#lockScreen').classList.add('hidden');
    $('#desktop').classList.remove('hidden');
    $('#wallpaper').classList.remove('blur');
  }

  loadDash();
  if (S.windowUp && S.page) { windowChrome(); render(); loadPage(S.page); }

  S.photoReady = false;
  post('nz_mdt:photo:status').then(res => {
    if (res) { S.photoReady = res.ready === true; S.photoReason = res.reason; }
  });
}

window.addEventListener('message', (e) => {
  const m = e.data || {};

  switch (m.action) {
    case 'open': onOpen(m); break;
    case 'close': hideTablet(); break;
    case 'live': if (S.me) onLive(m.event, m.data); break;
    case 'widget': {
      const w = $('#widget');
      if (m.data && m.data.position) w.className = 'pos-' + m.data.position;
      w.classList.toggle('up', !!m.open && !S.visible);
      if (m.open) renderWidget(m.data);
      break;
    }
    case 'shutter': $('#app').classList.toggle('shooting', !!m.on); break;
    case 'cameraView': cameraOverlay(m.on ? m.data : null); break;
    case 'openApp': if (S.visible && m.app) openApp(m.app); break;
    default: break;
  }
});

/* browser preview — open web/index.html straight in a browser to see the tablet */
if (!IN_GAME) {
  const s = document.createElement('script');
  s.src = 'js/preview.js';
  document.body.appendChild(s);
}
