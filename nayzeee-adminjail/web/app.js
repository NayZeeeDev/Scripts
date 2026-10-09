/* ═══════════════════════════════════════════════════════════
   NAYZEEE ADMIN JAIL v2 — NUI
   Opens in a normal browser too: demo data loads automatically.
   ═══════════════════════════════════════════════════════════ */
'use strict';

const DEMO = typeof window.GetParentResourceName !== 'function';
const RES = DEMO ? 'nayzeee-adminjail' : window.GetParentResourceName();

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

/* ─────────────── icons (stroke set from NAYZEEE UI) ─────────────── */
const ICONS = {
  grid: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
  gavel: '<path d="m14 13-7.5 7.5a2.1 2.1 0 0 1-3-3L11 10"/><path d="m16 16 6-6M8 8l6-6M9 7l8 8M21 11l-8-8"/>',
  users: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><path d="M16 4.6a3.5 3.5 0 0 1 0 6.8M18 14.2A6.5 6.5 0 0 1 21.5 20"/>',
  file: '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8l-5-5z"/><path d="M14 3v5h5M9 13h6M9 17h4"/>',
  lock: '<rect x="4.5" y="10.5" width="15" height="10" rx="2"/><path d="M8 10.5V7a4 4 0 0 1 8 0v3.5M12 14.5v2.5"/>',
  alert: '<path d="M12 9v5M12 17.5v.01"/><path d="M10.3 3.9 2.5 17.5A2 2 0 0 0 4.2 20.5h15.6a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/>',
  shield: '<path d="M12 3 4.5 6v5.5c0 4.6 3.2 8.1 7.5 9.5 4.3-1.4 7.5-4.9 7.5-9.5V6L12 3z"/><path d="m9 12 2 2 4-4"/>',
  search: '<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/>',
  refresh: '<path d="M20 11a8 8 0 1 0-2.3 5.7M20 5v6h-6"/>',
  check: '<path d="M4 12.5 9 17.5 20 6.5"/>',
  x: '<path d="M6 6l12 12M18 6 6 18"/>',
  info: '<path d="M12 8v.01M12 11v5"/><circle cx="12" cy="12" r="9"/>',
  wrench: '<path d="M14.7 6.3a4 4 0 0 0 5 5L21 13l-8 8-3-3 6.7-6.7a4 4 0 0 1-5-5L9 4.6 4.6 9 3 7.4 7.4 3 9 4.6"/>',
  unlock: '<rect x="4.5" y="10.5" width="15" height="10" rx="2"/><path d="M8 10.5V7a4 4 0 0 1 7.7-1.5M12 14.5v2.5"/>',
  move: '<path d="M5 12h14M13 6l6 6-6 6"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  door: '<path d="M14 4h4a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-4M10 16l4-4-4-4M14 12H4"/>',
};
const icon = (name) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">${ICONS[name] || ''}</svg>`;
const hydrateIcons = (root = document) => $$('i[data-icon]', root).forEach((el) => { if (!el.firstChild) el.innerHTML = icon(el.dataset.icon); });

/* ─────────────── helpers ─────────────── */
const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const initials = (name) => String(name || '?').trim().split(/\s+/).slice(0, 2).map((p) => p[0]).join('').toUpperCase() || '?';
const pad = (n) => String(n).padStart(2, '0');

function clock(sec) {
  sec = Math.max(0, Math.floor(sec));
  const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
  return h ? `${h}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`;
}
function mins(sec) {
  const m = Math.round(Math.max(0, sec) / 60);
  if (m < 60) return `${m}m`;
  return `${Math.floor(m / 60)}h${m % 60 ? ` ${m % 60}m` : ''}`;
}
function ago(ts) {
  const d = Math.max(0, Math.floor(Date.now() / 1000 - ts));
  if (d < 60) return 'just now';
  if (d < 3600) return `${Math.floor(d / 60)}m ago`;
  if (d < 86400) return `${Math.floor(d / 3600)}h ago`;
  return `${Math.floor(d / 86400)}d ago`;
}
function date(ts) {
  const d = new Date(ts * 1000);
  return `${d.toLocaleDateString(undefined, { day: 'numeric', month: 'short' })} · ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
function bind(key, value) { $$(`[data-bind="${key}"]`).forEach((el) => { el.textContent = value; }); }

async function nui(name, data) {
  if (DEMO) return Demo.handle(name, data);
  try {
    const res = await fetch(`https://${RES}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data ?? {}),
    });
    return await res.json();
  } catch (e) {
    return { ok: false, msg: 'Request failed' };
  }
}
const request = (name, data) => nui('request', { name, data });

/* ─────────────── live countdowns (one shared 1s tick) ─────────────── */
// [data-left]: seconds remaining when fetched, [data-at]: when it was fetched, [data-tick]: "1" while counting down
function liveLeft(el) {
  const left = Number(el.dataset.left);
  if (el.dataset.tick !== '1') return left;
  return Math.max(0, left - Math.floor((performance.now() - Number(el.dataset.at)) / 1000));
}
const live = (m) => `data-left="${m.remaining}" data-tick="${m.ticking ? 1 : 0}" data-at="${P.at}"`;
function tick() {
  if (!$('#panel').classList.contains('hidden')) {
    const now = new Date();
    bind('clock', `${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`);
    bind('clockShort', `${pad(now.getHours())}:${pad(now.getMinutes())}`);
    $$('[data-left]').forEach((el) => {
      const left = liveLeft(el);
      el.textContent = el.dataset.fmt === 'mins' ? mins(left) : clock(left);
    });
  }
  if (!$('#hud').classList.contains('hidden')) Hud.render();
}
setInterval(tick, 1000);

/* ─────────────── scale with resolution ─────────────── */
function rescale() {
  const s = Math.min(window.innerWidth / 1920, window.innerHeight / 1080);
  document.documentElement.style.setProperty('--s', Math.max(0.6, s).toFixed(3));
}
window.addEventListener('resize', rescale);
rescale();

/* ═══════════════════════════════════════════════════════════
   ADMIN PANEL
   ═══════════════════════════════════════════════════════════ */
const P = {
  boot: null,
  view: 'overview',
  inmates: [],
  at: 0, // performance.now() when `inmates` was fetched
  players: [],
  recent: [],
  source: 'online',
  pick: null,
  minutes: '',
  reason: '',
  location: null,
  history: { rows: [], page: 0, more: false },
  poll: null,
  modal: null,
};

const Panel = {
  open(data) {
    P.boot = data;
    P.location = data.defaultLocation;
    P.inmates = data.inmates || [];
    P.at = performance.now();

    bind('version', `v${data.version || '2.0.0'}`);
    bind('adminName', data.admin?.name || 'Staff');
    bind('adminInitials', initials(data.admin?.name));
    bind('adminMeta', `Staff · ID ${data.admin?.id ?? '-'}`);
    const d = new Date();
    bind('date', d.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' }));

    Panel.stats(data.stats);
    Panel.renderOverview(data.recent || []);
    Sentence.setup();
    Panel.go('overview');

    $('#panel').classList.remove('hidden');
    tick();
    clearInterval(P.poll);
    P.poll = setInterval(() => {
      if (P.view === 'overview') Panel.refreshOverview();
      else if (P.view === 'inmates') Panel.refreshInmates();
    }, 10000);
  },

  close(notify = true) {
    $('#panel').classList.add('hidden');
    Modal.close();
    clearInterval(P.poll);
    if (notify) nui('close');
  },

  go(view) {
    P.view = view;
    $$('.nav').forEach((n) => n.classList.toggle('on', n.dataset.view === view));
    $$('.view').forEach((v) => v.classList.toggle('on', v.dataset.viewId === view));
    if (view === 'overview') Panel.refreshOverview();
    if (view === 'inmates') Panel.refreshInmates();
    if (view === 'sentence') Sentence.load();
    if (view === 'history') History.load(true);
  },

  stats(s = {}) {
    bind('serving', s.serving ?? 0);
    bind('offline', s.offline ?? 0);
    bind('sentenced', s.sentenced ?? 0);
    bind('escapes', s.escapes ?? 0);
    bind('tally', (s.serving ?? 0) + (s.offline ?? 0));
    bind('offlineDelta', s.offline ? `+${s.offline} offline` : '');
  },

  async refreshOverview() {
    const res = await request('overview');
    if (!res?.ok) return;
    P.inmates = res.inmates || [];
    P.at = performance.now();
    Panel.stats(res.stats);
    Panel.renderOverview(res.recent || []);
  },

  async refreshInmates() {
    const res = await request('inmates');
    if (!res?.ok) return;
    P.inmates = res.inmates || [];
    P.at = performance.now();
    Panel.renderInmates();
  },

  statusTag(m) {
    if (!m.id) return '<span class="tag off">Offline</span>';
    if (m.state === 'placing') return '<span class="tag warn">Placing</span>';
    return '<span class="tag live">Serving</span>';
  },

  renderOverview(recent) {
    const ov = $('#ov-inmates');
    if (!P.inmates.length) {
      ov.innerHTML = empty('check', 'Nobody is serving', 'Sentences you hand out show up here with a live timer.');
    } else {
      ov.innerHTML = P.inmates.slice(0, 12).map((m) => `
        <button class="row click" data-inmate="${esc(m.identifier)}">
          <div class="av">${esc(initials(m.name))}</div>
          <div class="row-txt"><b>${esc(m.name)}</b><span>${esc(m.locationName)} · ${esc(m.reason)}</span></div>
          <div class="row-end">
            <span class="tag ${m.ticking ? 'live' : 'off'}" ${live(m)}>${clock(m.remaining)}</span>
          </div>
        </button>`).join('');
    }

    const rc = $('#ov-recent');
    if (!recent.length) {
      rc.innerHTML = empty('file', 'No closed sentences yet', 'Released and served sentences will be listed here.');
    } else {
      rc.innerHTML = recent.map((r) => `
        <article class="inc ${r.outcome === 'served' ? '' : 'urgent'}">
          <div class="inc-top">${outcomeChip(r.outcome)}<span class="ref">#${esc(r.id)}</span></div>
          <h3>${esc(r.name)}</h3>
          <p>${esc(r.reason)}</p>
          <div class="meta"><span>Served <b>${mins(r.served)} / ${mins(r.total)}</b></span><span>By <b>${esc(r.admin)}</b></span><span>${ago(r.released_at)}</span></div>
        </article>`).join('');
    }
    tick();
  },

  renderInmates() {
    const q = $('#inm-search').value.trim().toLowerCase();
    const list = P.inmates.filter((m) => !q || [m.name, m.account, m.reason, m.locationName, m.admin, m.id].join(' ').toLowerCase().includes(q));
    const el = $('#inm-list');
    if (!list.length) {
      el.innerHTML = empty('users', q ? 'No matches' : 'No open sentences', q ? 'Try a different search.' : 'Everyone is free. For now.');
      return;
    }
    el.innerHTML = list.map((m) => {
      const pct = m.total ? Math.min(100, Math.round(((m.total - m.remaining) / m.total) * 100)) : 0;
      return `
        <div class="row inm inm-grid" data-inmate="${esc(m.identifier)}">
          <div class="who-cell"><div class="av">${esc(initials(m.name))}</div>
            <div class="row-txt"><b>${esc(m.name)}</b><span>${m.id ? `#${m.id} · ` : ''}${esc(m.account || 'Offline')}</span></div></div>
          <div class="cell-sub"><b>${esc(m.locationName)}</b><small>${esc(m.reason)}</small></div>
          <div class="prog-cell"><div class="bar-prog"><i style="width:${pct}%"></i></div><span>${pct}% · ${m.escapes} esc · ${m.cycles} cycles</span></div>
          <div class="time-cell ${m.ticking ? '' : 'paused'}" ${live(m)}>${clock(m.remaining)}</div>
          <div>${Panel.statusTag(m)}</div>
        </div>`;
    }).join('');
    tick();
  },
};

function empty(ic, title, text) {
  return `<div class="empty"><i data-icon="${ic}">${icon(ic)}</i><b>${esc(title)}</b><span>${esc(text)}</span></div>`;
}
function skeleton(n = 4) {
  return Array.from({ length: n }, (_, i) => `<div class="skel"><div class="sk circ"></div><div style="flex:1"><div class="sk" style="height:9px;width:${50 + (i * 13) % 30}%"></div><div class="sk" style="height:7px;width:${30 + (i * 7) % 20}%;margin-top:7px"></div></div></div>`).join('');
}
function outcomeChip(outcome) {
  if (outcome === 'served') return '<span class="chip">Served</span>';
  return `<span class="chip red">${esc(outcome === 'released' ? 'Released' : outcome)}</span>`;
}

/* ─────────────── New sentence ─────────────── */
const Sentence = {
  setup() {
    const b = P.boot;
    $('#f-durations').innerHTML = (b.durations || []).map((m) => `<button class="qchip" data-min="${m}">${mins(m * 60)}</button>`).join('');
    $('#f-presets').innerHTML = (b.presets || []).map((p, i) => `<button class="qchip" data-preset="${i}">${esc(p.label)}<em>${mins(p.minutes * 60)}</em></button>`).join('');
    $('#f-locs').innerHTML = (b.locations || []).map((l) => `
      <button class="loc ${l.id === P.location ? 'on' : ''}" data-loc="${esc(l.id)}">
        ${l.image ? `<img src="${esc(l.image)}" alt="" onerror="this.remove()">` : ''}
        <div class="loc-check"><i data-icon="check">${icon('check')}</i></div>
        <div class="loc-txt"><b>${esc(l.name)}</b><span>${esc(l.description || '')}</span></div>
      </button>`).join('');
    $('#f-minutes').max = b.maxMinutes;
    Sentence.reset();
  },

  reset() {
    P.pick = null;
    P.minutes = '';
    P.reason = '';
    $('#f-minutes').value = '';
    $('#f-reason').value = '';
    Sentence.sync();
  },

  async load() {
    $('#pick-list').innerHTML = skeleton(5);
    const res = await request('players');
    if (!res?.ok) return;
    P.players = res.players || [];
    P.recent = res.recent || [];
    bind('onlineCount', P.players.length);
    bind('recentCount', P.recent.length);
    Sentence.renderList();
  },

  renderList() {
    const q = $('#pick-search').value.trim().toLowerCase();
    const recent = P.source === 'recent';
    $('#pick-sub').textContent = recent ? 'Disconnected in the last 3 hours' : 'Online now';
    $$('.seg button').forEach((b) => b.classList.toggle('on', b.dataset.source === P.source));

    const src = recent ? P.recent : P.players;
    const list = src.filter((p) => !q || [p.name, p.account, p.id].join(' ').toLowerCase().includes(q));
    const el = $('#pick-list');

    if (!list.length) {
      el.innerHTML = recent
        ? empty('door', q ? 'No matches' : 'Nobody left recently', 'Players who disconnect show up here so you can still sentence them.')
        : empty('users', 'No matches', 'Try a name, account name or server ID.');
      return;
    }

    el.innerHTML = list.map((p) => {
      const key = recent ? p.identifier : String(p.id);
      const sel = P.pick && P.pick.key === key;
      const sub = recent ? `${esc(p.account || 'Unknown')} · left ${ago(p.droppedAt)}` : `#${p.id} · ${esc(p.account)}`;
      return `
        <button class="row click ${sel ? 'sel' : ''} ${p.jailed ? 'dim' : ''}" data-pick="${esc(key)}" ${p.jailed ? 'disabled' : ''}>
          <div class="av">${esc(initials(p.name))}</div>
          <div class="row-txt"><b>${esc(p.name)}</b><span>${sub}</span></div>
          <div class="row-end">
            ${p.jailed ? '<span class="tag off">Jailed</span>' : ''}
            ${p.priors ? `<span class="chip ${p.priors >= 3 ? 'red' : 'mute'}">${p.priors} prior${p.priors > 1 ? 's' : ''}</span>` : ''}
          </div>
        </button>`;
    }).join('');
  },

  pick(key) {
    const recent = P.source === 'recent';
    const p = (recent ? P.recent : P.players).find((x) => (recent ? x.identifier : String(x.id)) === key);
    if (!p || p.jailed) return;
    P.pick = { key, recent, ...p };
    Sentence.renderList();
    Sentence.sync();
  },

  sync() {
    const p = P.pick;
    const picked = $('#picked');
    if (!p) {
      picked.className = 'picked none';
      picked.innerHTML = `<div class="av">?</div><div class="row-txt"><b>No player selected</b><span>Choose someone from the list</span></div>`;
    } else {
      picked.className = 'picked';
      picked.innerHTML = `
        <div class="av">${esc(initials(p.name))}</div>
        <div class="row-txt"><b>${esc(p.name)}</b><span>${p.recent ? `Offline · starts when they join` : `#${p.id} · ${esc(p.account)}`}</span></div>
        <div class="picked-flags">
          ${p.recent ? '<span class="tag off">Offline</span>' : '<span class="tag live">Online</span>'}
          ${p.priors ? `<span class="chip ${p.priors >= 3 ? 'red' : 'mute'}">${p.priors} prior${p.priors > 1 ? 's' : ''}</span>` : ''}
        </div>`;
    }

    const m = parseInt(P.minutes, 10);
    $$('#f-durations .qchip').forEach((b) => b.classList.toggle('on', Number(b.dataset.min) === m));
    $$('#f-presets .qchip').forEach((b) => {
      const pr = P.boot.presets[b.dataset.preset];
      b.classList.toggle('on', pr && pr.label === P.reason);
    });
    $$('#f-locs .loc').forEach((b) => b.classList.toggle('on', b.dataset.loc === P.location));

    const valid = p && m >= 1 && m <= P.boot.maxMinutes && P.location;
    $('#f-submit').disabled = !valid;
    const loc = P.boot.locations.find((l) => l.id === P.location);
    $('#f-summary').innerHTML = !p
      ? 'Select a player to continue'
      : !(m >= 1)
        ? 'Set a length'
        : m > P.boot.maxMinutes
          ? `Max is <b>${P.boot.maxMinutes} min</b>`
          : `<b>${esc(p.name)}</b> · <b>${mins(m * 60)}</b> · ${esc(loc?.name || '')}`;
  },

  async submit() {
    if ($('#f-submit').disabled) return;
    const p = P.pick;
    const btn = $('#f-submit');
    btn.disabled = true;
    const res = await request('jail', {
      target: p.recent ? undefined : p.id,
      identifier: p.recent ? p.identifier : undefined,
      name: p.name,
      minutes: parseInt(P.minutes, 10),
      reason: P.reason,
      location: P.location,
    });
    toast(res);
    if (res?.ok) {
      Sentence.reset();
      Sentence.load();
      Panel.refreshOverview();
    } else {
      Sentence.sync();
    }
  },
};

/* ─────────────── History ─────────────── */
let historyTimer = null;
const History = {
  async load(reset) {
    const h = P.history;
    if (reset) { h.page = 0; h.rows = []; $('#his-body').innerHTML = `<tr><td colspan="6">${skeleton(4)}</td></tr>`; }
    const res = await request('history', { field: $('#his-field').value, query: $('#his-search').value.trim(), page: h.page });
    if (!res?.ok) return;
    h.rows = reset ? res.rows : h.rows.concat(res.rows);
    h.more = res.more;
    History.render();
  },
  render() {
    const { rows, more } = P.history;
    $('#his-more').classList.toggle('hidden', !more);
    if (!rows.length) {
      $('#his-body').innerHTML = `<tr><td colspan="6">${empty('file', 'Nothing found', 'Closed sentences matching your search will show here.')}</td></tr>`;
      return;
    }
    $('#his-body').innerHTML = rows.map((r) => `
      <tr>
        <td class="clip"><b>${esc(r.name)}</b><small>${esc(r.account || '')}</small></td>
        <td class="clip">${esc(r.reason)}<small>${esc(r.location || '')}${r.escapes ? ` · ${r.escapes} escapes` : ''}</small></td>
        <td>${mins(r.served)} <small>of ${mins(r.total)}</small></td>
        <td>${outcomeChip(r.outcome)}</td>
        <td class="clip">${esc(r.admin)}<small>${r.released_by && r.released_by !== r.admin ? `→ ${esc(r.released_by)}` : ''}</small></td>
        <td>${date(r.jailed_at)}</td>
      </tr>`).join('');
  },
};

/* ─────────────── Modals ─────────────── */
const Modal = {
  show(html) {
    const ov = $('#overlay');
    ov.innerHTML = html;
    ov.classList.remove('hidden');
    hydrateIcons(ov);
  },
  close() {
    P.modal = null;
    $('#overlay').classList.add('hidden');
    $('#overlay').innerHTML = '';
  },
  open() { return !$('#overlay').classList.contains('hidden'); },

  inmate(identifier) {
    const m = P.inmates.find((x) => x.identifier === identifier);
    if (!m) return;
    P.modal = { type: 'inmate', identifier };
    const pct = m.total ? Math.min(100, Math.round(((m.total - m.remaining) / m.total) * 100)) : 0;
    const locs = P.boot.locations.map((l) => `<option value="${esc(l.id)}" ${l.id === m.location ? 'selected' : ''}>${esc(l.name)}</option>`).join('');
    Modal.show(`
      <div class="modal wide">
        <div class="m-head">
          <div class="av">${esc(initials(m.name))}</div>
          <div class="row-txt"><b>${esc(m.name)}</b><span>${m.id ? `#${m.id} · ` : ''}${esc(m.account || 'Offline')}</span></div>
          ${Panel.statusTag(m)}
          <button class="m-x" data-action="modal-close"><i data-icon="x"></i></button>
        </div>
        <div class="m-body">
          <div class="m-time">
            <div><div class="big ${m.ticking ? '' : 'paused'}" ${live(m)}>${clock(m.remaining)}</div>
            <small>${m.ticking ? 'remaining' : 'paused · not in jail right now'}</small></div>
            <div style="flex:1"><div class="bar-prog"><i style="width:${pct}%"></i></div><small>${pct}% served of ${mins(m.total)}</small></div>
          </div>
          <div class="kv">
            <div><span>Location</span><b>${esc(m.locationName)}</b></div>
            <div><span>Jailed by</span><b>${esc(m.admin)}</b></div>
            <div><span>Jailed</span><b>${ago(m.jailedAt)}</b></div>
            <div><span>Escape attempts</span><b>${m.escapes}</b></div>
            <div><span>Work cycles</span><b>${m.cycles}</b></div>
            <div><span>Worked off</span><b>${mins(m.reduced)}</b></div>
            <div class="span3"><span>Reason</span><b>${esc(m.reason)}</b></div>
          </div>
          <div class="m-sec">
            <label>Adjust time</label>
            <div class="m-row">
              <div class="chips">
                ${[-30, -10, -5].map((v) => `<button class="qchip neg" data-adjust="${v}">${v}m</button>`).join('')}
                ${[5, 10, 30].map((v) => `<button class="qchip" data-adjust="${v}">+${v}m</button>`).join('')}
              </div>
              <input type="number" id="m-adjust" placeholder="±min">
              <button class="btn-line" data-action="adjust-custom"><i data-icon="clock"></i>Apply</button>
            </div>
          </div>
          <div class="m-sec">
            <label>Transfer</label>
            <div class="m-row">
              <select class="select" id="m-loc">${locs}</select>
              <button class="btn-line" data-action="transfer"><i data-icon="move"></i>Move</button>
            </div>
          </div>
        </div>
        <div class="modal-f">
          <button class="btn-line" data-action="modal-close">Done</button>
          <button class="btn-red" data-action="release-ask"><i data-icon="unlock"></i>Release now</button>
        </div>
      </div>`);
  },

  confirmRelease(identifier) {
    const m = P.inmates.find((x) => x.identifier === identifier);
    if (!m) return;
    P.modal = { type: 'release', identifier };
    Modal.show(`
      <div class="modal">
        <div class="modal-b">
          <div class="warn"><i data-icon="alert"></i></div>
          <div><h4>Release ${esc(m.name)}?</h4><p>Their sentence closes now with ${clock(liveLeftOf(m))} left. It goes into history as released by you.</p></div>
        </div>
        <div class="modal-f">
          <button class="btn-line" data-action="back">Keep serving</button>
          <button class="btn-red" data-action="release"><i data-icon="unlock"></i>Release</button>
        </div>
      </div>`);
  },
};
function liveLeftOf(m) {
  return m.ticking ? Math.max(0, m.remaining - Math.floor((performance.now() - P.at) / 1000)) : m.remaining;
}

async function inmateAction(name, data) {
  const res = await request(name, { identifier: P.modal.identifier, ...data });
  toast(res);
  if (!res?.ok) return;
  const id = P.modal.identifier;
  await Panel.refreshInmates();
  Panel.refreshOverview();
  if (name === 'release' || !P.inmates.find((x) => x.identifier === id)) Modal.close();
  else Modal.inmate(id);
}

/* ─────────────── Toasts ─────────────── */
function toast(res, title) {
  if (!res) return;
  const ok = !!res.ok;
  const el = document.createElement('div');
  el.className = `toast ${ok ? '' : 'err'}`;
  el.innerHTML = `<div class="ti">${icon(ok ? 'check' : 'info')}</div><div><b>${esc(title || (ok ? 'Done' : 'Not done'))}</b><p>${esc(res.msg || (ok ? 'Saved.' : 'Something went wrong.'))}</p></div>`;
  $('#toasts').appendChild(el);
  setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 220); }, 4000);
}

/* ─────────────── Events ─────────────── */
document.addEventListener('click', (e) => {
  const t = e.target.closest('button, [data-inmate]');
  if (!t) return;

  if (t.dataset.view) return Panel.go(t.dataset.view);
  if (t.dataset.goto) return Panel.go(t.dataset.goto);
  if (t.hasAttribute('data-refresh')) return Panel.refreshInmates();
  if (t.dataset.inmate) return Modal.inmate(t.dataset.inmate);
  if (t.dataset.source) { P.source = t.dataset.source; return Sentence.renderList(); }
  if (t.dataset.pick) return Sentence.pick(t.dataset.pick);
  if (t.dataset.min) { P.minutes = t.dataset.min; $('#f-minutes').value = P.minutes; return Sentence.sync(); }
  if (t.dataset.preset) {
    const pr = P.boot.presets[t.dataset.preset];
    P.reason = pr.label; $('#f-reason').value = pr.label;
    if (pr.minutes) { P.minutes = String(pr.minutes); $('#f-minutes').value = P.minutes; }
    return Sentence.sync();
  }
  if (t.dataset.loc) { P.location = t.dataset.loc; return Sentence.sync(); }
  if (t.dataset.adjust) return inmateAction('adjust', { minutes: Number(t.dataset.adjust) });
  if (t.id === 'f-submit') return Sentence.submit();
  if (t.id === 'his-more') { P.history.page += 1; return History.load(false); }

  switch (t.dataset.action) {
    case 'close': return Panel.close();
    case 'modal-close': return Modal.close();
    case 'back': return Modal.inmate(P.modal.identifier);
    case 'release-ask': return Modal.confirmRelease(P.modal.identifier);
    case 'release': return inmateAction('release');
    case 'transfer': return inmateAction('transfer', { location: $('#m-loc').value });
    case 'adjust-custom': {
      const v = parseInt($('#m-adjust').value, 10);
      if (v) inmateAction('adjust', { minutes: v });
      return;
    }
  }
});

$('#overlay').addEventListener('mousedown', (e) => { if (e.target.id === 'overlay') Modal.close(); });
$('#f-minutes').addEventListener('input', (e) => { P.minutes = e.target.value; Sentence.sync(); });
$('#f-reason').addEventListener('input', (e) => { P.reason = e.target.value; Sentence.sync(); });
$('#pick-search').addEventListener('input', () => Sentence.renderList());
$('#inm-search').addEventListener('input', () => Panel.renderInmates());
$('#his-search').addEventListener('input', () => { clearTimeout(historyTimer); historyTimer = setTimeout(() => History.load(true), 300); });
$('#his-field').addEventListener('change', () => History.load(true));

document.addEventListener('keydown', (e) => {
  if ($('#panel').classList.contains('hidden')) return;
  const typing = /INPUT|SELECT/.test(document.activeElement?.tagName);

  if (e.key === 'Escape') {
    e.preventDefault();
    if (Modal.open()) return Modal.close();
    if (typing) return document.activeElement.blur();
    return Panel.close();
  }
  if (e.key === '/' && !typing) {
    e.preventDefault();
    const id = { sentence: '#pick-search', inmates: '#inm-search', history: '#his-search' }[P.view];
    if (id) $(id).focus();
    return;
  }
  if (e.key === 'Enter') {
    if (P.modal?.type === 'release') return inmateAction('release');
    if (document.activeElement?.id === 'm-adjust') return $('[data-action="adjust-custom"]').click();
    if (P.view === 'sentence' && !Modal.open()) return Sentence.submit();
  }
});

/* ═══════════════════════════════════════════════════════════
   PLAYER HUD
   ═══════════════════════════════════════════════════════════ */
const RING = 389.56;
const H = { s: null, syncAt: 0, work: null };

const Hud = {
  show({ sentence, rules, work, key }) {
    $('#hud-rules').innerHTML = (rules || []).map((r) => `<li>${r}</li>`).join(''); // trusted config HTML
    $('#hud-work').classList.toggle('hidden', !work);
    if (key) $('#hud-key').textContent = key;
    $('#hud').classList.remove('hidden');
    Hud.sync(sentence);
  },
  hide() {
    $('#hud').classList.add('hidden');
    H.s = null;
    H.work = null;
  },
  toggle() { $('#hud').classList.toggle('min'); },

  sync(s) {
    if (!s) return;
    H.s = s;
    H.syncAt = performance.now();
    $('#hud-loc').textContent = s.locationName || '-';
    $('#hud-reason').textContent = s.reason || '-';
    $('#hud-admin').textContent = s.admin || '-';
    $('#hud-total').textContent = mins(s.total);
    $('#hud-escapes').textContent = s.escapes ?? 0;
    const status = $('#hud-status');
    status.className = `tag ${s.ticking ? 'live' : 'warn'}`;
    status.textContent = s.ticking ? 'Serving' : 'Transferring';
    if (H.work) Hud.work(Object.assign(H.work, { cycles: s.cycles, reduced: s.reduced, hourReduced: s.hourReduced }));
    Hud.render();
  },

  left() {
    if (!H.s) return 0;
    if (!H.s.ticking) return H.s.remaining;
    return Math.max(0, H.s.remaining - Math.floor((performance.now() - H.syncAt) / 1000));
  },

  render() {
    if (!H.s) return;
    const left = Hud.left();
    const txt = clock(left);
    $('#hud-time').textContent = txt;
    $('#hud-mini').textContent = txt;
    $('#hud-sub').textContent = H.s.ticking ? 'remaining' : 'paused';
    const ring = $('#hud-ring');
    const progress = H.s.total > 0 ? left / H.s.total : 0;
    ring.style.strokeDashoffset = (RING * (1 - Math.min(1, progress))).toFixed(2);
    ring.classList.toggle('paused', !H.s.ticking);
    ring.classList.toggle('red', H.s.ticking && left < 60);
    ring.classList.toggle('amber', H.s.ticking && left >= 60 && left < 180);

    if (H.work?.locked) {
      const reset = Math.max(0, H.work.resetIn - Math.floor((performance.now() - H.work.at) / 1000));
      $('#hw-task').textContent = `Limit reached · resets in ${clock(reset)}`;
    }
  },

  work(w) {
    H.work = { ...w, at: performance.now() };
    const tag = $('#hw-tag');
    if (w.locked) {
      tag.className = 'tag warn'; tag.textContent = 'Hour limit';
    } else {
      tag.className = 'tag live'; tag.textContent = 'Active';
      $('#hw-task').textContent = w.point ? `${w.point.label} · task ${Math.min(w.step + 1, w.of)}/${w.of}` : 'Waiting for a task…';
    }
    $('#hw-segs').innerHTML = Array.from({ length: w.of || 5 }, (_, i) => `<i class="${i < w.step ? 'done' : i === w.step && !w.locked ? 'now' : ''}"></i>`).join('');
    $('#hw-reduced').textContent = mins(w.reduced || 0);
    $('#hw-cycles').textContent = w.cycles || 0;
    $('#hw-hour').textContent = `${Math.round((w.hourReduced || 0) / 60)}/${Math.round((w.hourCap || 600) / 60)}m`;
    Hud.render();
  },

  flash({ kind, text }) {
    const el = $('#hud-flash');
    el.className = `flash ${kind}`;
    el.textContent = text;
    void el.offsetWidth;
    el.classList.add('go');
  },
};

/* ─────────────── messages from Lua ─────────────── */
window.addEventListener('message', ({ data: msg }) => {
  if (!msg || !msg.action) return;
  const d = msg.data;
  switch (msg.action) {
    case 'panel:open': return Panel.open(d);
    case 'panel:close': return Panel.close(false);
    case 'hud:show': return Hud.show(d);
    case 'hud:sync': return Hud.sync(d);
    case 'hud:work': return Hud.work(d);
    case 'hud:hide': return Hud.hide();
    case 'hud:toggle': return Hud.toggle();
    case 'hud:flash': return Hud.flash(d);
  }
});

hydrateIcons();

/* ═══════════════════════════════════════════════════════════
   DEMO — only when opened outside FiveM
   ═══════════════════════════════════════════════════════════ */
const Demo = {
  now: () => Math.floor(Date.now() / 1000),
  inmates: [],
  history: [],
  players: [],
  recent: [],
  boot() {
    const n = Demo.now();
    Demo.inmates = [
      { identifier: 'license:a1', id: 14, name: 'Marcus Vale', account: 'vale', reason: 'RDM at Legion Square', admin: 'NayZeee', location: 'bolingbroke', locationName: 'Bolingbroke Penitentiary', remaining: 1312, total: 1800, ticking: true, state: 'active', escapes: 1, cycles: 2, reduced: 240, jailedAt: n - 900 },
      { identifier: 'license:a2', id: 31, name: 'Tasha Reid', account: 'tashxr', reason: 'VDM - ran over EMS twice', admin: 'Kilo', location: 'aircraft_carrier', locationName: 'USS Luxington', remaining: 584, total: 1200, ticking: true, state: 'active', escapes: 0, cycles: 4, reduced: 480, jailedAt: n - 1600 },
      { identifier: 'license:a3', id: null, name: 'Diego Santos', account: 'dsantos', reason: 'Combat logging during a pursuit', admin: 'NayZeee', location: 'police_station', locationName: 'Mission Row Holding', remaining: 3420, total: 3600, ticking: false, state: 'offline', escapes: 0, cycles: 0, reduced: 0, jailedAt: n - 7200 },
    ];
    Demo.history = Array.from({ length: 12 }, (_, i) => ({
      id: 212 - i, identifier: `license:h${i}`, name: ['Jay Pork', 'Rico Salas', 'Ana Brooks', 'Theo Kane', 'Maya Reyes', 'Sam Kim'][i % 6],
      account: ['jpork', 'rsalas', 'anab', 'tkane', 'mreyes', 'samk'][i % 6], reason: ['FailRP - no fear for life', 'Metagaming stream info', 'RDM', 'VDM', 'Staff disrespect', 'Combat logging'][i % 6],
      admin: ['NayZeee', 'Kilo', 'Vex'][i % 3], released_by: i % 4 === 1 ? 'Kilo' : 'Time served', location: 'Bolingbroke Penitentiary',
      total: [1200, 1800, 3600, 600][i % 4], served: [1200, 900, 3600, 600][i % 4], escapes: i % 5 === 0 ? 2 : 0, outcome: i % 4 === 1 ? 'released' : 'served',
      jailed_at: n - 3600 * (i + 1), released_at: n - 1800 * (i + 1),
    }));
    Demo.players = [
      { id: 3, name: 'Jay Pork', account: 'jpork', jailed: false, priors: 4 },
      { id: 7, name: 'Lena Ortiz', account: 'lenao', jailed: false, priors: 0 },
      { id: 14, name: 'Marcus Vale', account: 'vale', jailed: true, priors: 2 },
      { id: 22, name: 'Owen Hart', account: 'ohart', jailed: false, priors: 1 },
      { id: 31, name: 'Tasha Reid', account: 'tashxr', jailed: true, priors: 0 },
      { id: 40, name: 'Priya Shah', account: 'pshah', jailed: false, priors: 0 },
    ];
    Demo.recent = [{ identifier: 'license:r1', name: 'Nico Ward', account: 'nward', droppedAt: n - 420, jailed: false, priors: 3 }];
  },
  stats() {
    return { serving: Demo.inmates.filter((m) => m.id).length, offline: Demo.inmates.filter((m) => !m.id).length, sentenced: 7, escapes: 2 };
  },
  handle(name, body) {
    if (name === 'close') return { ok: true };
    const d = body?.data || {};
    const n = body?.name;
    switch (n) {
      case 'overview': return { ok: true, stats: Demo.stats(), inmates: Demo.inmates, recent: Demo.history.slice(0, 6) };
      case 'inmates': return { ok: true, inmates: Demo.inmates };
      case 'players': return { ok: true, players: Demo.players, recent: Demo.recent };
      case 'history': {
        const q = (d.query || '').toLowerCase();
        const rows = Demo.history.filter((r) => !q || [r.name, r.admin, r.reason].join(' ').toLowerCase().includes(q));
        return { ok: true, rows: rows.slice(d.page * 8, d.page * 8 + 8), more: rows.length > (d.page + 1) * 8 };
      }
      case 'jail': {
        const p = Demo.players.find((x) => x.id === d.target) || Demo.recent.find((x) => x.identifier === d.identifier);
        if (p) p.jailed = true;
        const loc = Demo.bootData.locations.find((l) => l.id === d.location);
        Demo.inmates.unshift({ identifier: `license:${Math.random()}`, id: d.target || null, name: d.name, account: p?.account, reason: d.reason || 'No reason given', admin: 'NayZeee', location: d.location, locationName: loc.name, remaining: d.minutes * 60, total: d.minutes * 60, ticking: !!d.target, state: d.target ? 'active' : 'offline', escapes: 0, cycles: 0, reduced: 0, jailedAt: Demo.now() });
        return { ok: true, msg: d.target ? `Jailed ${d.name} for ${d.minutes} minutes` : `Sentence queued for ${d.name} - it starts when they join` };
      }
      case 'adjust': {
        const m = Demo.inmates.find((x) => x.identifier === d.identifier);
        m.remaining = Math.max(0, m.remaining + d.minutes * 60);
        if (d.minutes > 0) m.total += d.minutes * 60;
        return { ok: true, msg: `Changed ${m.name}'s sentence by ${d.minutes > 0 ? '+' : ''}${d.minutes} minutes` };
      }
      case 'transfer': {
        const m = Demo.inmates.find((x) => x.identifier === d.identifier);
        const loc = Demo.bootData.locations.find((l) => l.id === d.location);
        m.location = loc.id; m.locationName = loc.name;
        return { ok: true, msg: `Moved ${m.name} to ${loc.name}` };
      }
      case 'release': {
        const m = Demo.inmates.find((x) => x.identifier === d.identifier);
        Demo.inmates = Demo.inmates.filter((x) => x !== m);
        const p = Demo.players.find((x) => x.id === m.id); if (p) p.jailed = false;
        return { ok: true, msg: `Released ${m.name}` };
      }
    }
    return { ok: false, msg: 'Unknown request' };
  },
};

if (DEMO) {
  document.body.classList.add('demo');
  Demo.boot();
  Demo.bootData = {
    ok: true, version: '2.0.0', admin: { name: 'NayZeee', id: 1 }, defaultLocation: 'bolingbroke', maxMinutes: 1440,
    durations: [10, 20, 30, 60, 120],
    presets: [{ label: 'RDM', minutes: 30 }, { label: 'VDM', minutes: 20 }, { label: 'FailRP', minutes: 20 }, { label: 'Combat logging', minutes: 60 }, { label: 'Metagaming', minutes: 30 }],
    locations: [
      { id: 'aircraft_carrier', name: 'USS Luxington', description: 'Maximum security floating prison', image: 'https://r2.fivemanage.com/4iPDn6qcQHpV9zEdQQSZO/aircraft.png' },
      { id: 'bolingbroke', name: 'Bolingbroke Penitentiary', description: 'Maximum security prison', image: 'https://r2.fivemanage.com/4iPDn6qcQHpV9zEdQQSZO/prison.png' },
      { id: 'military_base', name: 'Fort Zancudo Detention', description: 'Military detention facility', image: 'https://r2.fivemanage.com/4iPDn6qcQHpV9zEdQQSZO/militery.png' },
      { id: 'police_station', name: 'Mission Row Holding', description: 'Police station detention', image: 'https://r2.fivemanage.com/4iPDn6qcQHpV9zEdQQSZO/police.png' },
    ],
    stats: Demo.stats(), inmates: Demo.inmates, recent: Demo.history.slice(0, 6),
  };
  const params = new URLSearchParams(location.search);
  if (params.get('view') !== 'hud') Panel.open(Demo.bootData);
  if (params.get('view')) Panel.go(params.get('view') === 'hud' ? 'overview' : params.get('view'));
  if (params.get('view') === 'hud' || params.has('hud')) {
    Hud.show({ sentence: { locationName: 'Bolingbroke Penitentiary', remaining: 1312, total: 1800, ticking: true, reason: 'RDM at Legion Square', admin: 'NayZeee', escapes: 1, cycles: 2, reduced: 240, hourReduced: 240, hourCap: 600 }, rules: ['Escape attempts add <span class="red">extra time</span> - and it stacks', 'Finish work cycles to <span class="teal">reduce your sentence</span>', 'Work reduction has an <span class="amber">hourly limit</span>', 'Your timer pauses while you are offline'], work: true, key: 'HOME' });
    Hud.work({ step: 2, of: 5, cycles: 2, reduced: 240, hourReduced: 240, hourCap: 600, point: { label: 'Sweep the floor' } });
  }
}
