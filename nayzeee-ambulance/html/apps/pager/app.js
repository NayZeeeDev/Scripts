/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · pager
   An "RX-10" two-way receiver (bottom right, generic device — no brand on the face):
   graphite shell with rubber corner bumpers, LED light pipes on the top edge (PWR / MSG /
   LNK), a teal OLED glass on the left and a round jog pad + ✕ key on the right. Pops up
   without focus when a call comes in; taken in hand (focus + cursor, game input kept)
   with the pager key / item.

   Screens: CALL (range dial on the left: range in the centre, a blip on the rim at the
            call's bearing, the arc = answer window / route / call progress; the call type
            in full words beside it over a short instrument list (drive time, answer
            window or time on the call); a foot row with the priority, the call phase as a
            pixel quarter ring + word, the street as a ticker and the list index; key
            legend), SETUP (call list, link phone, silent, street calls, availability,
            page log, stand down), PAGE LOG, STANDBY (clock, status)
   Keys (focused): ◀ / ArrowLeft setup-back · ▲▼ scroll · Enter / ArrowRight take-open ·
                   Backspace pass-back · ESC or the pager key: put it away

   Lua → JS: open (payload) · state (payload) · page { id, priority, beep, line? } · live { time, calls } · focus { on }
             line = { title, text, hospital, priority, time } (NZA.Dispatch.Page): shown on the glass
             for a few seconds over the call / standby screen, then kept in the page log
   JS → Lua: pager:ack {id} · pager:decl {id} · pager:clear · pager:gps {id} · pager:pair {on}
             pager:mute {on} · pager:npc {on} · pager:status {code} · pager:hide
   ═══════════════════════════════════════════════════════════ */
(() => {
  const K = window.NZD;
  const esc = NZA.esc;
  let tr = K.tr({});
  let d = { calls: [], history: [], me: {}, muted: false, phone: true, beep: true, focused: false, time: '--:--', key: 'F7' };
  let live = { calls: {} };
  let screen = 'call', sel = 0, menuSel = 0, histSel = 0, blink = false, blinkT = 0, flashT = 0, line = null, lineT = 0;
  let dev, scr, body, statusEl, legEl, ledMsg, ledLnk, hintsEl;

  const up = s => String(s ?? '').toUpperCase();
  const calls = () => d.calls || [];
  const cur = () => calls()[Math.min(sel, Math.max(0, calls().length - 1))];
  const isMine = c => c && d.me && d.me.call === c.id;
  // fallback short names for the glass (in game the locale's type_*_s strings win)
  const SHORT = { gunshot: 'GSW', shrapnel: 'BLAST', stab: 'STAB', burn: 'BURNS', arrest: 'NO PULSE', overdose: 'OD', mva: 'CRASH', crash: 'CRASH',
    fall: 'FALL', drowning: 'DROWNING', deceased: 'DOA', unconscious: 'UNRESP', call: '911', fracture: 'FRACTURE', internal: 'BLEED', unknown: 'UNKNOWN' };
  const availWord = m => (m.oos ? tr('pg_unavail', 'UNAVAIL') : tr('pg_avail', 'AVAIL'));

  /* ── setup menu model ── */
  function menu() {
    const m = d.me || {};
    const on = v => (v ? tr('pg_on', 'ON') : tr('pg_off', 'OFF'));
    const items = [
      { id: 'calls', label: tr('pg_calls', 'Call list'), val: String(calls().length) },
      d.phone ? { id: 'pair', label: tr('pg_pair', 'Link phone'), val: on(m.paired) } : null,
      { id: 'mute', label: tr('pg_mute', 'Silent'), val: on(d.muted) },
      { id: 'npc', label: tr('pg_npc', 'Street calls'), val: on(m.npc) },
      { id: 'status', label: tr('pg_status', 'Availability'), val: m.call ? K.stageShort(m.status || 'ENR', tr) : availWord(m) },
      { id: 'history', label: tr('pg_history', 'Page log'), val: String((d.history || []).length) },
      m.call ? { id: 'clear', label: tr('pg_clear', 'Stand down'), val: m.call } : null,
    ];
    return items.filter(Boolean);
  }

  /* ── pixel widgets ── */
  // dial: dotted track, arc, 24 rim dots; optional blip on the rim at a bearing (degrees,
  // relative to the camera)
  function ringSVG(frac, big, small, rel) {
    const f = Math.max(0, Math.min(1, frac || 0));
    let ticks = '';
    for (let i = 0; i < 24; i++) { const a = (i * 15 - 90) * Math.PI / 180; ticks += `<rect x="${(31 * Math.cos(a) - 1).toFixed(1)}" y="${(31 * Math.sin(a) - 1).toFixed(1)}" width="2" height="2" class="${i / 24 < f ? 'on' : ''}"/>`; }
    const blip = rel != null ? `<path class="blip" transform="rotate(${Number(rel).toFixed(1)})" d="M0 -37.5L3.6 -31.5H-3.6Z"/>` : '';
    return `<div class="px-ring"><svg viewBox="-36 -36 72 72"><circle class="trk" r="26"/><circle class="arc" r="26" pathLength="100" stroke-dasharray="${(f * 100).toFixed(1)} 100"/>${ticks}${blip}</svg>
      <div class="rv"><b>${esc(big)}</b><span>${esc(small)}</span></div></div>`;
  }
  // instrument rows: label left, dotted leader, value right
  const inst = rows => rows.map(r => `<div class="ln iv ${r.hot ? 'hot' : ''}"><span class="dm">${esc(up(r.k))}</span><span class="lead"></span><span class="vl">${esc(up(r.v))}</span></div>`).join('');
  // foot row: priority, the call phase (pixel quarter ring + word), the street as a ticker,
  // the list index. The ticker keeps its position across re-renders (negative delay from
  // the clock); a new phase word rolls in once.
  const QUAD = [0, 1, 2, 3].map(i => {
    const a0 = (i * 90 - 90 + 7) * Math.PI / 180, a1 = ((i + 1) * 90 - 90 - 7) * Math.PI / 180;
    return `M${(6 * Math.cos(a0)).toFixed(2)} ${(6 * Math.sin(a0)).toFixed(2)}A6 6 0 0 1 ${(6 * Math.cos(a1)).toFixed(2)} ${(6 * Math.sin(a1)).toFixed(2)}`;
  });
  let phaseSeen = {};
  function footRow(c, p, street, idx) {
    const ph = K.phase(c.status), done = K.done(c.status), now = performance.now();
    const seen = phaseSeen[c.id];
    if (!seen || seen.ph !== ph) phaseSeen[c.id] = { ph, t: seen ? now : -1e9 };
    const since = now - phaseSeen[c.id].t;
    const roll = since < 600 ? ` class="roll" style="animation-delay:-${since.toFixed(0)}ms"` : '';
    const quad = `<svg class="pq" viewBox="-8 -8 16 16">${QUAD.map((dd, i) => `<path class="${i < ph || done ? 'dn' : i === ph ? 'cur' : ''}" d="${dd}"/>`).join('')}</svg>`;
    let tick = '<span class="sp"></span>';
    if (street) {
      const dur = Math.max(6, street.length * 0.42);
      const at = ((now / 1000) % dur).toFixed(2);
      tick = `<span class="tk"><em style="animation-duration:${dur.toFixed(2)}s;animation-delay:-${at}s">${esc(street)}</em></span>`;
    }
    return `<div class="ln ft ${p === 1 ? 'p1' : ''}"><span class="inv pr">P${p}</span>${quad}<span class="pw"><em${roll}>${esc(up(K.stageShort(c.status, tr)))}</em></span>${tick}<span class="sn">${esc(idx)}</span></div>`;
  }
  function legend(rows) {
    const html = rows.filter(Boolean).map(r => `<div class="lg ${r.cls || ''}"><span class="g">${r.g}</span><span>${esc(up(r.t))}</span></div>`).join('');
    if (legEl.innerHTML !== html) legEl.innerHTML = html;
  }
  const G = { ok: '<i class="dot"></i>', x: '✕', l: '◀', ud: '▲▼' };

  /* ── render ── */
  const pairIcon = () => '<svg viewBox="0 0 16 10"><rect x="1.5" y=".8" width="5.5" height="8.4" rx="1"/><path d="M3.5 7.4h1.5"/><path d="M9.5 3.2a2.6 2.6 0 0 1 0 3.6M11.8 1.4a5.2 5.2 0 0 1 0 7.2"/></svg>';
  const muteIcon = () => '<svg viewBox="0 0 16 10"><path d="M1 3.5h3l3-2.5v8l-3-2.5H1z"/><path d="M10 2.5l5 5M15 2.5l-5 5"/></svg>';
  function renderStatus() {
    const m = d.me || {};
    statusEl.innerHTML = `
      <span class="unit">${esc(up(m.callsign || ''))}</span>
      ${m.paired ? `<span class="ic">${pairIcon()}</span>` : ''}
      ${d.muted ? `<span class="ic">${muteIcon()}</span>` : ''}
      <span class="sp"></span>
      <span class="sig"><i></i><i></i><i></i><i></i></span>
      <span class="clk">${esc(live.time || d.time || '--:--')}</span>
      <span class="bat"><i></i></span>`;
  }

  function renderCall() {
    const c = cur();
    if (!c) { screen = 'idle'; return renderIdle(); }
    const L = live.calls[c.id] || {};
    const dist = L.dist != null ? K.dist(L.dist) : { v: '--', u: 'm' };
    const p = K.prio(c.priority);
    // the type in full words (the short glass codes are kept for the page log)
    const type = up(tr('type_' + c.type, c.title || SHORT[c.type] || c.type));
    const where = up([c.street, c.zone].filter(Boolean).join(' · ') || tr('unknown_location', 'UNKNOWN LOCATION'));
    const ageNow = c.age != null ? c.age + (performance.now() - (c._at || performance.now())) / 1000 : 0;
    const range = up([dist.u, L.dir].filter(Boolean).join(' '));
    const drv = { k: tr('pg_eta', 'DRV'), v: K.eta(L.eta) };
    const onIt = { k: tr('pg_time', 'TIME'), v: K.eta(ageNow) };
    let ring, rows;
    if (isMine(c) && K.phase(c.status) >= 2) {
      // with the patient / to hospital: time on the call in the dial, the scene range below
      ring = ringSVG(K.fill(c.status), K.eta(ageNow), tr('pg_time', 'TIME'));
      rows = [{ k: tr('pg_scene', 'Scene'), v: dist.v + dist.u }];
    } else if (isMine(c)) {
      ring = ringSVG(L.prog != null ? L.prog : 0, dist.v, range, L.rel);
      rows = [drv, onIt];
    } else {
      const win = Number(d.ackWindow) || 30;
      const left = Math.max(0, win - ageNow);
      ring = ringSVG(left / win, dist.v, range, L.rel);
      rows = [drv, left > 0 ? { k: tr('pg_take_in', 'Take in'), v: `${Math.ceil(left)} ${tr('pg_sec', 'SEC')}`, hot: left <= 8 } : { k: tr('pg_held', 'HELD'), v: K.eta(ageNow) }];
    }
    body.innerHTML = `
      <div class="pg-call">
        ${ring}
        <div class="ci">
          <div class="ln tw"><span>${esc(type)}</span></div>
          ${inst(rows)}
        </div>
      </div>
      ${footRow(c, p, where, `${sel + 1}/${calls().length}`)}`;
    if (isMine(c)) legend([{ g: G.ok, t: tr('pg_gps', 'Nav'), cls: 'hot' }, { g: G.x, t: tr('pg_clr', 'End') }, { g: G.l, t: tr('pg_menu', 'Setup') }]);
    else legend([{ g: G.ok, t: tr('pg_ack', 'Take'), cls: 'hot' }, { g: G.x, t: tr('pg_decl', 'Pass') }, { g: G.l, t: tr('pg_menu', 'Setup') }]);
  }

  function renderMenu() {
    const items = menu();
    menuSel = Math.max(0, Math.min(menuSel, items.length - 1));
    const start = Math.max(0, Math.min(menuSel - 2, items.length - 4));
    body.innerHTML = `<div class="ln hd"><span class="inv">${esc(up(tr('pg_menu', 'Setup')))}</span><span class="sp"></span><span class="dots">${items.map((_, i) => `<i class="${i === menuSel ? 'on' : ''}"></i>`).join('')}</span></div>` +
      items.slice(start, start + 4).map((it, i) => {
        const on = start + i === menuSel;
        return `<div class="ln mi ${on ? 'on' : ''}"><span class="cur">${on ? '&gt;' : ''}</span><span class="lb">${esc(up(it.label))}</span><span class="lead"></span><span class="vl">${esc(up(it.val))}</span></div>`;
      }).join('');
    legend([{ g: G.ok, t: tr('pg_sel', 'Open'), cls: 'hot' }, { g: G.x, t: tr('pg_back', 'Back') }, { g: G.ud, t: tr('pg_move', 'Move') }]);
  }

  function renderHistory() {
    const h = d.history || [];
    if (!h.length) {
      body.innerHTML = `<div class="ln hd"><span class="inv">${esc(up(tr('pg_history', 'Page log')))}</span></div><div class="ln dim ct">${esc(up(tr('pg_no_history', 'Nothing paged yet')))}</div>`;
    } else {
      histSel = Math.max(0, Math.min(histSel, h.length - 1));
      const start = Math.max(0, Math.min(histSel - 2, h.length - 4));
      body.innerHTML = `<div class="ln hd"><span class="inv">${esc(up(tr('pg_history', 'Page log')))}</span><span class="sp"></span><span class="ix">${histSel + 1}/${h.length}</span></div>` +
        h.slice(start, start + 4).map((e, i) => {
          const on = start + i === histSel;
          return `<div class="ln mi ${on ? 'on' : ''} ${e.closed ? 'dim' : ''}"><span class="cur">${on ? '&gt;' : ''}</span><span>${esc(e.time || '')}</span><span>P${K.prio(e.priority)}</span><span class="lb">${esc(up(tr('type_' + (e.type || '') + '_s', SHORT[e.type] || e.title || '')))}</span><span class="lead"></span><span class="vl">${esc(up(e.page ? tr('pg_page', 'Page') : e.closed ? tr('pg_closed', 'Done') : tr('pg_open', 'Open')))}</span></div>`;
        }).join('');
    }
    legend([{ g: G.x, t: tr('pg_back', 'Back') }, { g: G.ud, t: tr('pg_move', 'Move') }]);
  }

  // a paged line (no call behind it): title, text, where
  function renderLine() {
    const m = line;
    body.innerHTML = `
      <div class="ln hd"><span class="inv">P${K.prio(m.priority)}</span><span class="tt">${esc(up(m.title || tr('pg_page', 'Page')))}</span><span class="sp"></span><span class="ix">${esc(m.time || '')}</span></div>
      ${m.text ? `<div class="ln wr"><span>${esc(up(m.text))}</span></div>` : ''}
      ${m.hospital ? `<div class="ln dim">${esc(up(m.hospital))}</div>` : ''}`;
    legend([{ g: G.ok, t: tr('pg_ok', 'OK'), cls: 'hot' }, { g: G.x, t: tr('pg_back', 'Back') }, { g: G.l, t: tr('pg_menu', 'Setup') }]);
  }
  const lineUp = () => !!line && (screen === 'call' || screen === 'idle');
  function dropLine() { line = null; clearTimeout(lineT); }

  function renderIdle() {
    const m = d.me || {};
    const st = m.call ? K.stageShort(m.status || 'ENR', tr) : m.oos ? tr('pg_unavail', 'UNAVAIL') : tr('pg_avail', 'AVAIL');
    body.innerHTML = `
      <div class="pg-idle">
        ${ringSVG(m.oos ? 0.25 : 1, '', '')}
        <div class="ii">
          <div class="ln idle-clk">${esc(live.time || d.time || '--:--')}</div>
          <div class="ln"><span class="inv">${esc(up(tr('pg_standby', 'Standby')))}</span><span>${esc(up(st))}</span></div>
          <div class="ln dim">${esc(up(tr('pg_no_calls', 'No open calls')))}</div>
        </div>
      </div>`;
    legend([{ g: G.ok, t: tr('pg_menu', 'Setup'), cls: 'hot' }, { g: G.x, t: tr('pg_hide', 'Hide') }]);
  }

  function renderHints() {
    const k = esc(d.key || 'F7');
    const html = `<span><kbd>◀</kbd>${esc(tr('pg_h_menu', 'Setup'))}</span><span><kbd>▲</kbd><kbd>▼</kbd>${esc(tr('pg_h_scroll', 'Scroll'))}</span>` +
      `<span><kbd>Enter</kbd>${esc(tr('pg_h_ack', 'Take'))}</span><span><kbd>⌫</kbd>${esc(tr('pg_h_back', 'Pass / back'))}</span><span><kbd>${k}</kbd>${esc(tr('pg_h_hide', 'Put away'))}</span>`;
    if (hintsEl.innerHTML !== html) hintsEl.innerHTML = html;
  }

  function render() {
    if (!body) return;
    renderStatus();
    if (screen === 'call' && !calls().length) screen = 'idle';
    if (screen === 'idle' && calls().length) screen = 'call';
    if (lineUp()) renderLine();
    else ({ call: renderCall, menu: renderMenu, history: renderHistory, idle: renderIdle })[screen]();
    scr.dataset.screen = screen;
    const m = d.me || {};
    ledMsg.className = `led-i ${blink ? 'red blink' : m.call ? 'teal' : calls().length ? 'amber' : ''}`;
    ledLnk.className = `led-i ${m.paired ? 'teal' : ''}`;
    dev.classList.toggle('focused', !!d.focused);
    hintsEl.classList.toggle('on', !!d.focused);
    if (d.focused) renderHints();
  }

  /* ── input ── */
  function click() { NZA.audio.tone(2200, 25, { vol: 0.04, type: 'square' }); }
  function press(btn) {
    if (!d.focused) return;
    blink = false;
    click();
    dev.querySelectorAll(`[data-b="${btn}"]`).forEach(b => { b.classList.add('press'); setTimeout(() => b.classList.remove('press'), 120); });
    if (lineUp() && (btn === 'ack' || btn === 'back')) { dropLine(); render(); return; }
    if (lineUp()) dropLine();
    if (btn === 'left') {
      if (screen === 'menu') screen = calls().length ? 'call' : 'idle';
      else if (screen === 'history') screen = 'menu';
      else screen = 'menu';
    } else if (btn === 'up' || btn === 'down') {
      const dir = btn === 'up' ? -1 : 1;
      if (screen === 'call') { const n = calls().length; if (n) sel = (sel + dir + n) % n; }
      else if (screen === 'menu') { const n = menu().length; menuSel = (menuSel + dir + n) % n; }
      else if (screen === 'history') { const n = (d.history || []).length; if (n) histSel = (histSel + dir + n) % n; }
    } else if (btn === 'ack') {
      ack();
    } else if (btn === 'back') {
      back();
    }
    render();
  }

  function ack() {
    if (screen === 'call') {
      const c = cur(); if (!c) return;
      if (isMine(c)) NZA.post('pager:gps', { id: c.id });
      else { NZA.post('pager:ack', { id: c.id }); flash(); }
    } else if (screen === 'idle') {
      screen = 'menu';
    } else if (screen === 'menu') {
      const it = menu()[menuSel]; if (!it) return;
      const m = d.me || (d.me = {});
      if (it.id === 'calls') screen = calls().length ? 'call' : 'idle';
      else if (it.id === 'history') { screen = 'history'; histSel = 0; }
      else if (it.id === 'pair') { NZA.post('pager:pair', { on: !m.paired }); }
      else if (it.id === 'mute') { d.muted = !d.muted; NZA.post('pager:mute', { on: d.muted }); }
      else if (it.id === 'npc') { m.npc = !m.npc; NZA.post('pager:npc', { on: m.npc }); }
      else if (it.id === 'status' && !m.call) { m.oos = !m.oos; NZA.post('pager:status', { code: m.oos ? '10-7' : '10-8' }); }
      else if (it.id === 'clear') { NZA.post('pager:clear', {}); screen = 'call'; }
    }
  }

  function back() {
    if (screen === 'call') {
      const c = cur(); if (!c) return;
      if (isMine(c)) NZA.post('pager:clear', {});
      else { NZA.post('pager:decl', { id: c.id }); d.calls = calls().filter(x => x.id !== c.id); sel = Math.max(0, sel - 1); }
    } else if (screen === 'menu') screen = calls().length ? 'call' : 'idle';
    else if (screen === 'history') screen = 'menu';
    else if (screen === 'idle') NZA.post('pager:hide', {});
  }

  function flash() {
    clearTimeout(flashT);
    scr.classList.remove('flash'); void scr.offsetWidth; scr.classList.add('flash');
    flashT = setTimeout(() => scr.classList.remove('flash'), 560);
  }

  function apply(p) {
    const keepId = cur() && cur().id;
    d = Object.assign(d, p || {});
    if (p && p.locale) tr = K.tr(p.locale);
    const now = performance.now();
    (d.calls || []).forEach(c => { c._at = now; });
    const seen = {};
    (d.calls || []).forEach(c => { if (phaseSeen[c.id]) seen[c.id] = phaseSeen[c.id]; });
    phaseSeen = seen;
    if (keepId) { const i = calls().findIndex(c => c.id === keepId); if (i >= 0) sel = i; }
    if (sel >= calls().length) sel = 0;
    render();
  }

  const screw = cls => `<span class="pg-screw ${cls}"><i></i></span>`;

  NZA.app('pager', {
    escClose: false,
    init(el) {
      el.innerHTML = `
        <div class="pg-wrap">
          <div class="pg-hints nza-hud solid"></div>
          <div class="pg-dev">
            <div class="pg-clip"></div>
            <div class="pg-shell"><div class="pg-plate">
              ${screw('s1')}${screw('s2')}${screw('s3')}${screw('s4')}
              <div class="pg-top">
                <span class="pg-model">RX-10</span><span class="pg-kind">2-WAY ALPHA RECEIVER</span>
                <span class="sp"></span>
                <span class="pg-leds">
                  <span class="led"><i class="led-i teal"></i>PWR</span>
                  <span class="led"><i class="led-i" data-led="msg"></i>MSG</span>
                  <span class="led"><i class="led-i" data-led="lnk"></i>LNK</span>
                </span>
              </div>
              <div class="pg-face">
                <div class="pg-bezel"><div class="pg-scr">
                  <div class="pg-status"></div>
                  <div class="pg-main"><div class="pg-body"></div><div class="pg-leg"></div></div>
                </div></div>
                <div class="pg-ctl">
                  <div class="pg-pad">
                    <span class="pg-rose"></span>
                    <button class="pk pk-u" data-b="up"><svg viewBox="0 0 24 24"><path d="M6 15l6-7 6 7z"/></svg></button>
                    <button class="pk pk-d" data-b="down"><svg viewBox="0 0 24 24"><path d="M6 9l6 7 6-7z"/></svg></button>
                    <button class="pk pk-l" data-b="left"><svg viewBox="0 0 24 24"><path d="M15 6l-7 6 7 6z"/></svg></button>
                    <button class="pk pk-r" data-b="ack"><svg viewBox="0 0 24 24"><path d="M9 6l7 6-7 6z"/></svg></button>
                    <button class="pg-sel" data-b="ack"><i></i></button>
                  </div>
                  <button class="pg-x" data-b="back"><svg viewBox="0 0 24 24"><path d="M7 7l10 10M17 7L7 17"/></svg></button>
                </div>
              </div>
              <div class="pg-bot">
                <span class="pg-grill">${'<i></i>'.repeat(9)}</span>
                <span class="pg-sticker"><b>!</b><span>IP54 · KEEP DRY</span></span>
                <span class="sp"></span>
                <span class="pg-sn">SN 4471-0932 · 433 MHz</span>
              </div>
            </div></div>
          </div>
        </div>`;
      dev = el.querySelector('.pg-dev');
      scr = el.querySelector('.pg-scr');
      body = el.querySelector('.pg-body');
      legEl = el.querySelector('.pg-leg');
      statusEl = el.querySelector('.pg-status');
      ledMsg = el.querySelector('[data-led="msg"]');
      ledLnk = el.querySelector('[data-led="lnk"]');
      hintsEl = el.querySelector('.pg-hints');
      el.querySelectorAll('[data-b]').forEach(b => b.addEventListener('mousedown', e => { e.preventDefault(); press(b.dataset.b); }));
      // the pager key itself puts the pager away while it has focus
      window.addEventListener('keydown', e => {
        if (!NZA.isOpen('pager') || !d.focused || e.repeat) return;
        const k = String(d.key || '').toUpperCase();
        if (k && (String(e.key).toUpperCase() === k || String(e.code).toUpperCase() === k || String(e.code).toUpperCase() === 'KEY' + k)) { e.preventDefault(); NZA.post('pager:hide', {}); }
      });
    },
    open(p) {
      screen = 'call';
      apply(p);
      dev.classList.remove('in'); void dev.offsetWidth; dev.classList.add('in');
    },
    close() { clearTimeout(blinkT); blink = false; dropLine(); },
    msg: {
      state: apply,
      focus(p) { d.focused = !!(p && p.on); render(); },
      page(p) {
        const i = calls().findIndex(c => c.id === p.id);
        if (i >= 0 && (screen !== 'menu' || !d.focused)) { sel = i; screen = 'call'; }
        if (p.line) {
          line = p.line;
          clearTimeout(lineT);
          lineT = setTimeout(() => { line = null; render(); }, (Number(p.line.hold) || 10) * 1000);
        }
        blink = true;
        clearTimeout(blinkT);
        blinkT = setTimeout(() => { blink = false; render(); }, 15000);
        flash();
        dev.classList.remove('buzz'); void dev.offsetWidth; dev.classList.add('buzz');
        if (p.beep !== false) NZA.audio.pager();
        render();
      },
      live(l) {
        live = l || live; live.calls = live.calls || {};
        if (screen === 'call' || screen === 'idle') render(); else renderStatus();
      },
    },
    keys: {
      ArrowLeft() { if (!d.focused) return false; press('left'); },
      ArrowRight() { if (!d.focused) return false; press('ack'); },
      ArrowUp() { if (!d.focused) return false; press('up'); },
      ArrowDown() { if (!d.focused) return false; press('down'); },
      Enter() { if (!d.focused) return false; press('ack'); },
      Backspace() { if (!d.focused) return false; press('back'); },
      Escape() { if (!d.focused) return false; NZA.post('pager:hide', {}); },
    },
    preview() {
      NZA.demo('pager', {
        focused: true, time: '16:42', muted: false, phone: true, key: 'F7', ackWindow: 30,
        me: { callsign: 'Unit 04', status: '10-8', paired: true, npc: true, call: null },
        calls: [
          { id: 'C-0417', code: '10-57', priority: 1, title: 'Collapsed, not breathing', type: 'arrest', street: 'Sinner St', zone: 'Mission Row', status: 'DSP', age: 6 },
          { id: 'C-0416', code: '10-50', priority: 1, title: 'Two-car collision', type: 'mva', street: 'Strawberry Ave', zone: 'Strawberry', status: 'ENR', age: 140 },
          { id: 'C-0412', code: '10-52', priority: 3, title: 'Fall', type: 'fall', street: 'Vespucci Blvd', zone: 'Vespucci', status: 'DSP', age: 310 },
        ],
        history: [
          { id: 'C-0417', priority: 1, title: 'Collapsed, not breathing', type: 'arrest', time: '16:41' },
          { id: 'C-0410', priority: 1, title: 'Gunshot', type: 'gunshot', time: '16:12', closed: true },
          { id: 'C-0407', priority: 3, title: 'Fall', type: 'fall', time: '15:48', closed: true },
        ],
        locale: {},
      });
      live = { time: '16:42', calls: { 'C-0417': { dist: 820, dir: 'W', rel: 262, eta: 46, prog: 0.2 }, 'C-0416': { dist: 1240, dir: 'SW', rel: 205, eta: 71 } } };
      NZA.apps.pager.msg.page({ id: 'C-0417', priority: 1, beep: false });
    },
  });
})();
