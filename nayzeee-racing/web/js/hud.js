/* ════════════════════════════════════════════════════════════════════════
   NAYZEEE v5 · racing NUI — race HUD, results card, track builder overlay
   ════════════════════════════════════════════════════════════════════════ */
'use strict';

const $hud = document.getElementById('hud');
const $res = document.getElementById('results');
const $bld = document.getElementById('builder');

const H = { on: false };
let clockRaf = null, bannerTimer = null, resTimer = null, toastTimer = null;

function hudSpeedUnit() { return (H.settings || S.settings).units === 'mph' ? 'MPH' : 'KM/H'; }
function raceMs() { return H.start ? Date.now() - H.start + (H.penalty || 0) : 0; }

function renderHud() {
  if (!H.on) { $hud.className = ''; $hud.innerHTML = ''; return; }
  $hud.className = 'on';
  const set = H.settings || S.settings;
  const total = H.racers ? H.racers.length : 1;
  const myPos = H.pos || '—';
  let html = '';

  if (['mobilize', 'countdown', 'racing'].includes(H.phase)) {
    html += `<div class="h-pos">
      <div class="hbox h-big"><small>${esc(t('HUD_POSITION'))}</small><b>${myPos}${typeof myPos === 'number' ? `<sup>${esc(t('ORD_' + (myPos % 100 >= 11 && myPos % 100 <= 13 ? 'th' : ['th', 'st', 'nd', 'rd'][myPos % 10] || 'th')))}</sup>` : ''}<em>/ ${total}</em></b></div>
      <div class="h-mini">
        ${H.circuit ? `<div class="hbox"><small>${esc(t('HUD_LAP'))}</small><b>${H.lap || 1}<em> / ${H.laps}</em></b></div>` : ''}
        <div class="hbox" ${H.circuit ? '' : 'style="grid-column:span 2"'}><small>${esc(t('HUD_CHECKPOINT'))}</small><b>${H.k || 0}<em> / ${H.total}</em></b></div>
      </div></div>`;
    html += `<div class="hbox h-clock"><div class="t" id="h-time">${esc(clock(raceMs(), true))}</div>
      <div class="rows">
        ${H.circuit ? `<div><span>${esc(t('HUD_LAST_LAP'))}</span><b>${esc(H.lastLap ? clock(H.lastLap) : '—')}</b></div>
        <div><span>${esc(t('HUD_BEST_LAP'))}</span><b class="best">${esc(H.bestLap ? clock(H.bestLap) : '—')}</b></div>` : ''}
        ${H.pb ? `<div><span>${esc(t('HUD_PB'))}</span><b>${esc(clock(H.circuit ? (H.pb.lap || H.pb.time) : H.pb.time))}</b></div>` : ''}
        ${H.track && H.track.worldRecord ? `<div><span>${esc(t('HUD_WR'))}</span><b>${esc(clock(H.track.worldRecord.time))}</b></div>` : ''}
        ${H.penalty ? `<div><span>${esc(t('HUD_PENALTY'))}</span><b style="color:var(--red)">+${(H.penalty / 1000).toFixed(1)}s</b></div>` : ''}
      </div>
      ${H.mode === 'drift' ? `<div class="drift"><small>${esc(t('HUD_DRIFT'))}</small><b id="h-drift">${num(H.drift || 0)}</b></div>` : ''}</div>`;
    if (set.showBoard && H.board && H.board.length > 1) {
      const sorted = [...H.board].sort((a, b) => a.pos - b.pos);
      let rows = sorted.slice(0, 8);
      if (!rows.some(r => r.id === H.me)) { const mine = sorted.find(r => r.id === H.me); if (mine) rows = [...rows.slice(0, 7), mine]; }
      html += `<div class="h-board">${rows.map(r => `<div class="h-row ${r.id === H.me ? 'me' : ''} ${r.status === 'disqualified' ? 'out' : ''}" style="--c:${esc(r.color)}">
        ${posBadge(r.pos, r.status === 'disqualified' ? 'dnf' : null)}<i class="c"></i><b>${esc(r.alias)}</b>
        <span>${r.status === 'finished' ? '<i class="fas fa-flag-checkered"></i>' : r.status === 'disqualified' ? 'DNF' : H.mode === 'drift' && r.drift != null ? num(r.drift) : ''}</span></div>`).join('')}</div>`;
    }
    if (set.showSpeed) html += `<div class="h-speed"><b id="h-speed">${H.speed || 0}</b><span>${hudSpeedUnit()}</span></div>`;
  }

  if (H.phase === 'mobilize') {
    const left = Math.max(0, Math.ceil((H.mobEnd - Date.now()) / 1000));
    html += `<div class="hbox h-banner"><div class="tile"><i class="${modeIcon(H.mode)}"></i></div>
      <div><b>${esc(H.name)}</b><span>${esc(t('HUD_GET_READY', H.track ? H.track.name : ''))}</span></div><div class="cd" id="h-mob">${left}</div></div>`;
  }
  if (H.phase === 'countdown') {
    html += `<div class="hbox h-lights">${Array.from({ length: H.lights }, (_, i) => `<i class="${i < H.lit ? 'r' : ''}"></i>`).join('')}</div>`;
  }
  if (H.go) html += `<div class="h-go">${esc(t('HUD_GO'))}</div>`;
  if (H.deadlineEnd && H.phase === 'racing') {
    html += `<div class="hbox h-banner" style="top:170px"><div class="tile red"><i class="fas fa-hourglass-half"></i></div><div><b>${esc(t('HUD_DEADLINE'))}</b><span>${esc(t('HUD_DEADLINE_SUB'))}</span></div>
      <div class="cd" id="h-dl" style="color:var(--red)">${Math.max(0, Math.ceil((H.deadlineEnd - Date.now()) / 1000))}</div></div>`;
  }
  if (H.hold > 0) html += `<div class="hbox h-hold"><i class="fas fa-rotate-left" style="color:var(--teal)"></i>${esc(t('HUD_RESPAWN'))}<div class="track"><div class="bar-fill" style="width:${H.hold * 100}%;transition:none"></div></div></div>`;
  if (H.toast) html += `<div class="hbox h-toast ${H.toast.red ? 'red' : ''}">${esc(H.toast.text)}</div>`;
  if (H.phase === 'finished') {
    const r = H.result || {};
    html += `<div class="hbox h-center"><small>${esc(t('HUD_FINISHED'))}</small><h2 class="teal">${typeof H.pos === 'number' ? esc(ordinal(H.pos)) : esc(t('HUD_FINISH'))}</h2>
      <p>${H.mode === 'drift' ? esc(t('HUD_DRIFT')) + ' ' + num(r.drift) : esc(clock(r.time))}${r.bestLap ? ` · ${esc(t('HUD_BEST_LAP'))} ${esc(clock(r.bestLap))}` : ''}</p><p class="hint">${esc(t('HUD_WAIT_RESULTS'))}</p></div>`;
  }
  if (H.phase === 'dnf') {
    html += `<div class="hbox h-center"><small>${esc(t('HUD_DNF_SMALL'))}</small><h2 class="red">${esc(t('HUD_DNF'))}</h2><p>${esc(t('DNF_' + (H.reason || 'left')))}</p></div>`;
  }
  $hud.innerHTML = html;
}

function startClock() {
  cancelAnimationFrame(clockRaf);
  let lastSec = -1;
  const loop = () => {
    const el = document.getElementById('h-time');
    if (el && H.phase === 'racing') el.textContent = clock(raceMs(), true);
    const sec = Math.floor(Date.now() / 1000);
    if (sec !== lastSec) {
      lastSec = sec;
      const dl = document.getElementById('h-dl');
      if (dl && H.deadlineEnd) dl.textContent = Math.max(0, Math.ceil((H.deadlineEnd - Date.now()) / 1000));
      const mob = document.getElementById('h-mob');
      if (mob) mob.textContent = Math.max(0, Math.ceil((H.mobEnd - Date.now()) / 1000));
    }
    if (H.on && ['mobilize', 'countdown', 'racing'].includes(H.phase)) clockRaf = requestAnimationFrame(loop);
  };
  clockRaf = requestAnimationFrame(loop);
}
function hudToast(text, red, ms = 2200) {
  H.toast = { text, red };
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { H.toast = null; renderHud(); }, ms);
  renderHud();
}

const RACE = {
  mobilize(d) {
    Object.assign(H, { on: true, phase: 'mobilize', name: d.name, track: d.track, mode: d.mode, laps: d.laps, circuit: d.circuit, total: d.total,
      racers: d.racers, me: d.me, pb: d.pb, settings: d.settings, k: 0, lap: 1, pos: null, board: null, lastLap: null, bestLap: null,
      start: null, penalty: 0, drift: 0, speed: 0, deadlineEnd: null, hold: 0, toast: null, go: false, result: null, reason: null, mobEnd: Date.now() + d.ms });
    renderHud();
    startClock();
  },
  countdown(d) {
    H.phase = 'countdown';
    H.lights = Math.max(1, Math.round(d.ms / 1000));
    H.lit = 1;
    renderHud();
    let n = 1;
    const iv = setInterval(() => {
      n++;
      if (n > H.lights || H.phase !== 'countdown') { clearInterval(iv); return; }
      H.lit = n;
      renderHud();
    }, 1000);
  },
  start() {
    H.phase = 'racing';
    H.start = Date.now();
    H.go = true;
    renderHud();
    startClock();
    setTimeout(() => { H.go = false; renderHud(); }, 900);
  },
  progress(d) { H.k = d.k; H.total = d.total; if (d.lap) H.lap = d.lap; renderHud(); },
  lap(d) {
    H.lastLap = d.time; H.bestLap = d.best;
    const pb = H.pb && (H.pb.lap || H.pb.time);
    hudToast(d.time <= d.best && pb && d.time < pb ? t('HUD_NEW_PB_LAP', clock(d.time)) : t('HUD_LAP_DONE', d.lap, clock(d.time)));
  },
  positions(d) {
    H.board = d.board;
    const mine = d.board.find(r => r.id === H.me);
    if (mine) H.pos = mine.pos;
    renderHud();
  },
  deadline(d) { H.deadlineEnd = Date.now() + d.ms; renderHud(); hudToast(t('HUD_DEADLINE_STARTED'), true, 3000); },
  tick(d) {
    H.speed = d.speed;
    if (d.drift != null) H.drift = d.drift;
    const sp = document.getElementById('h-speed');
    if (sp) sp.textContent = d.speed;
    const dr = document.getElementById('h-drift');
    if (dr && d.drift != null) dr.textContent = num(d.drift);
  },
  hold(d) { H.hold = d.pct; renderHud(); },
  cooldown() { hudToast(t('HUD_RESPAWN_COOLDOWN'), true); },
  respawned(d) { H.penalty = (H.penalty || 0) + (d.penalty || 0); hudToast(d.penalty ? t('HUD_RESPAWNED_PENALTY', (d.penalty / 1000).toFixed(1)) : t('HUD_RESPAWNED'), !!d.penalty); },
  finished(d) { H.phase = 'finished'; H.result = d.result; H.deadlineEnd = null; renderHud(); },
  dnf(d) { H.phase = 'dnf'; H.reason = d.reason; renderHud(); },
  hide() { H.on = false; cancelAnimationFrame(clockRaf); renderHud(); },
};

function renderResults(d) {
  const res = d.results, list = res.list, drift = res.mode === 'drift';
  const mine = list.find(r => r.id === d.me);
  const crews = res.crews ? `<div class="res-crews">
      <div class="${res.crews.winner === (res.crews[0].crew || {}).id ? 'w' : ''}"><b>${res.crews[0].score}</b>${crewTag(res.crews[0].crew)}</div><span style="color:var(--ink-3)">vs</span>
      <div class="${res.crews.winner === (res.crews[1].crew || {}).id ? 'w' : ''}"><b>${res.crews[1].score}</b>${crewTag(res.crews[1].crew)}</div></div>` : '';
  $res.style.setProperty('--dur', d.ms + 'ms');
  $res.innerHTML = `<div class="hbox">
    <div class="res-h"><div class="tile ${mine && mine.position === 1 && mine.status === 'finished' ? 'amber' : ''}"><i class="fas fa-flag-checkered"></i></div>
      <div style="flex:1;min-width:0"><b>${esc(t('RES_TITLE'))}</b><span>${esc(d.lobby)} · ${esc(d.track)} · ${esc(t('MODE_' + res.mode))}</span></div>
      ${mine && mine.eloDelta ? `<div style="text-align:right"><div class="hint">${esc(t('UI_ELO'))}</div>${eloDelta(mine.eloDelta)}</div>` : ''}</div>
    ${crews}
    <div class="res-list">${list.slice(0, 10).map(r => `<div class="res-row ${r.id === d.me ? 'me' : ''}">${posBadge(r.position, r.status)}${avatar(r, 'sm')}<b>${esc(r.alias)}</b>
      ${r.payout ? `<span class="chip amber">${esc(money(r.payout))}</span>` : ''}${eloDelta(r.eloDelta)}
      <span class="tm">${r.status !== 'finished' ? esc(t('P_DNF')) : drift ? num(r.score) : esc(clock(res.mode === 'time_trial' ? r.score : r.time))}</span></div>`).join('')}</div>
    <div class="res-bar"></div></div>`;
  $res.className = 'on';
  clearTimeout(resTimer);
  resTimer = setTimeout(() => { $res.className = ''; $res.innerHTML = ''; }, d.ms);
}

// ── builder overlay ─────────────────────────────────────────────────────
const B = { on: false, help: true };
const BUILDER_KEYS = [
  [['←', '→'], 'TB_KEY_WIDTH'], [['↑', '↓'], 'TB_KEY_ROTATE'], [['Shift', '↑↓←→'], 'TB_KEY_LEFT'], [['Ctrl', '↑↓←→'], 'TB_KEY_RIGHT'],
  [['Enter'], 'TB_KEY_ADD'], [['Delete'], 'TB_KEY_DELETE'], [['Z'], 'TB_KEY_TYPE'], [['Shift', 'Enter'], 'TB_KEY_SAVE'], [['F10'], 'TB_KEY_HELP'], [['Esc'], 'TB_KEY_CANCEL'],
];
function renderBuilder() {
  if (!B.on) { $bld.className = ''; $bld.innerHTML = ''; return; }
  $bld.className = 'on';
  $bld.innerHTML = `<div class="hbox b-panel">
      <div style="display:flex;align-items:center;gap:10px"><div class="mark"></div><div style="flex:1"><b style="font-size:13px;color:#fff">${esc(t('TB_TITLE'))}</b><div class="hint">${esc(t('TRACK_' + B.type))}</div></div>
        <span class="chip ${B.type === 'circuit' ? '' : 'mute'}">${esc(t('TRACK_' + B.type))}</span></div>
      ${trackSvg(B.preview, B.type === 'circuit', 170)}
      <div class="kv"><span>${esc(t('LOBBY_CPS'))}</span><b>${B.count} <span style="color:var(--ink-3);font-weight:300">/ ${B.max}</span></b>
        <span>${esc(t('LOBBY_DISTANCE'))}</span><b>${esc(dist(B.length))}</b></div>
      ${B.count < B.min ? `<div class="note amber"><i class="fas fa-circle-info"></i><span>${esc(t('TB_NEED_MORE', B.min - B.count))}</span></div>` : ''}
    </div>
    ${B.help ? `<div class="hbox b-help">${BUILDER_KEYS.map(([keys, l]) => `<div><span>${esc(t(l))}</span><span class="keys">${keys.map(k => `<span class="key">${esc(k)}</span>`).join('')}</span></div>`).join('')}</div>` : ''}`;
}
const BUILD = {
  start(d) { Object.assign(B, { on: true, type: d.type, min: d.min, max: d.max, count: 0, length: 0, preview: [], help: true }); renderBuilder(); },
  update(d) { Object.assign(B, { count: d.count, length: d.length, type: d.type, preview: d.preview }); renderBuilder(); },
  help() { B.help = !B.help; renderBuilder(); },
  stop() { B.on = false; renderBuilder(); if (MODAL && MODAL.builder) closeModal(); },
  save(d) {
    const f = { name: '', description: '', private: false, type: d.type };
    openModal({
      builder: true, sticky: true,
      render: () => `<div class="modal wide"><div class="modal-h"><div class="grow"><h4>${esc(t('TB_SAVE_TITLE'))}</h4><p>${esc(t('TB_SAVE_SUB', d.count, dist(d.length)))}</p></div></div>
        <div class="modal-body">
          <div class="field"><label>${esc(t('TRACKS_NAME'))}</label><input id="tb-name" maxlength="60" value="${esc(f.name)}" oninput="window.__tb.name=this.value" placeholder="${esc(t('TB_NAME_PH'))}"></div>
          <div class="field"><label>${esc(t('TRACKS_DESC'))}</label><textarea id="tb-desc" maxlength="500" oninput="window.__tb.description=this.value">${esc(f.description)}</textarea></div>
          <div class="field"><label>${esc(t('CREATE_TYPE'))}</label><div class="seg"><button class="${f.type === 'sprint' ? 'on' : ''}" data-a="tbType" data-v="sprint">${esc(t('TRACK_sprint'))}</button><button class="${f.type === 'circuit' ? 'on' : ''}" data-a="tbType" data-v="circuit">${esc(t('TRACK_circuit'))}</button></div></div>
          <button class="sw-line" data-a="tbPriv"><div><b>${esc(t('TRACKS_PRIVATE'))}</b><span>${esc(t('TRACKS_PRIVATE_DESC'))}</span></div><span class="sw ${f.private ? 'on' : ''}"><i></i></span></button>
        </div>
        <div class="modal-f">${btn(t('TB_KEEP_BUILDING'), 'tbBack', 'btn-line', { free: true })}${btn(t('TB_SAVE'), 'tbSave', 'btn-teal', { icon: 'fas fa-check', busyKey: 'tbsave' })}</div></div>`,
      on: {
        tbType: e => { f.type = e.v; post('builder:type', { type: e.v }); renderModal(); },
        tbPriv: () => { f.private = !f.private; renderModal(); },
        tbBack: () => { closeModal(); post('builder:cancelSave'); },
        tbSave: async () => {
          if (!f.name.trim()) return toast(t('TRACK_NAME_REQUIRED'), true);
          S.busy = 'tbsave'; renderModal();
          const r = await post('builder:save', { name: f.name, description: f.description, private: f.private });
          S.busy = null;
          if (!r || r.error) { toast(t((r && r.error) || 'ERR_GENERIC'), true); renderModal(); return; }
          closeModal();
        },
      },
    });
    window.__tb = f;
    document.getElementById('tb-name').focus();
  },
};

window.HUD = {
  race(d) { const fn = RACE[d.phase]; if (fn) fn(d); },
  results(d) { renderResults(d); },
  builder(d) { const fn = BUILD[d.phase]; if (fn) fn(d); },
};
