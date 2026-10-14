/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · pager
   A NAYZEEE EMS pager (bottom right): backlit dot-matrix LCD (VT323), LED, soft keys
   and three hardware buttons. Pops up without focus when a call comes in; taken in hand
   (focus + cursor, game input kept) with the pager key / item.

   Screens: CALL (priority + type, street, distance + ETA, progress, status chain)
            MENU (calls, pair phone, mute, NPC calls, status 10-8/10-7, history, clear call)
            HISTORY, IDLE (clock, unit, status)
   Keys (focused): ◀ / ArrowLeft menu-back · ▲▼ scroll · Y / Enter ACK-select ·
                   Backspace BACK-decline · ESC or the pager key: put it away

   Lua → JS: open (payload) · state (payload) · page { id, priority, beep } · live { time, calls } · focus { on }
   JS → Lua: pager:ack {id} · pager:decl {id} · pager:clear · pager:gps {id} · pager:pair {on}
             pager:mute {on} · pager:npc {on} · pager:status {code} · pager:hide
   ═══════════════════════════════════════════════════════════ */
(() => {
  const K = window.NZD;
  const esc = NZA.esc;
  let tr = K.tr({});
  let d = { calls: [], history: [], me: {}, muted: false, phone: true, beep: true, focused: false, time: '--:--', key: 'F7' };
  let live = { calls: {} };
  let screen = 'call', sel = 0, menuSel = 0, histSel = 0, blink = false, blinkT = 0, flashT = 0;
  let dev, lcd, body, softL, softR, statusEl, ledEl, hintsEl;

  const up = s => String(s ?? '').toUpperCase();
  const pad = (s, n) => { s = String(s); return s.length >= n ? s.slice(0, n) : s + ' '.repeat(n - s.length); };
  const calls = () => d.calls || [];
  const cur = () => calls()[Math.min(sel, Math.max(0, calls().length - 1))];
  const isMine = c => c && d.me && d.me.call === c.id;

  /* ── menu model ── */
  function menu() {
    const m = d.me || {};
    const on = v => (v ? tr('pg_on', 'ON') : tr('pg_off', 'OFF'));
    const items = [
      { id: 'calls', label: tr('pg_calls', 'CALLS'), val: String(calls().length) },
      d.phone ? { id: 'pair', label: tr('pg_pair', 'PAIR PHONE'), val: on(m.paired) } : null,
      { id: 'mute', label: tr('pg_mute', 'MUTE'), val: on(d.muted) },
      { id: 'npc', label: tr('pg_npc', 'NPC CALLS'), val: on(m.npc) },
      { id: 'status', label: tr('pg_status', 'STATUS'), val: m.call ? (m.status || 'ENR') : (m.oos ? '10-7' : '10-8') },
      { id: 'history', label: tr('pg_history', 'HISTORY'), val: String((d.history || []).length) },
      m.call ? { id: 'clear', label: tr('pg_clear', 'CLEAR CALL'), val: m.call } : null,
    ];
    return items.filter(Boolean);
  }

  /* ── render ── */
  function chainHTML(stage) {
    const ci = K.stageIdx(stage);
    return K.STAGES.map((s, i) => `<span class="${i < ci ? 'dn' : i === ci ? 'inv' : 'fut'}">${s}</span>`).join('<span class="gt">&gt;</span>');
  }

  function renderStatus() {
    const m = d.me || {};
    statusEl.innerHTML = `
      <span class="sig"><i></i><i></i><i></i><i></i></span>
      ${m.paired ? `<span class="lk">${pairIcon()}</span>` : ''}
      ${d.muted ? `<span class="mt">${muteIcon()}</span>` : ''}
      <span class="unit">${esc(up(m.callsign || ''))}</span>
      <span class="sp"></span>
      <span class="clk">${esc(live.time || d.time || '--:--')}</span>
      <span class="bat"><i></i></span>`;
  }
  const pairIcon = () => '<svg viewBox="0 0 16 10"><rect x="1.5" y=".8" width="5.5" height="8.4" rx="1"/><path d="M3.5 7.4h1.5"/><path d="M9.5 3.2a2.6 2.6 0 0 1 0 3.6M11.8 1.4a5.2 5.2 0 0 1 0 7.2"/></svg>';
  const muteIcon = () => '<svg viewBox="0 0 16 10"><path d="M1 3.5h3l3-2.5v8l-3-2.5H1z"/><path d="M10 2.5l5 5M15 2.5l-5 5"/></svg>';

  function renderCall() {
    const c = cur();
    if (!c) { screen = 'idle'; return renderIdle(); }
    const L = live.calls[c.id] || {};
    const dist = L.dist != null ? K.dist(L.dist) : { v: '--', u: 'm' };
    const p = K.prio(c.priority);
    const type = up(tr('type_' + c.type + '_s', tr('type_' + c.type, c.title || c.type)));
    const ageNow = c.age != null ? c.age + (performance.now() - (c._at || performance.now())) / 1000 : 0;
    let prog, num;
    if (isMine(c)) {
      prog = L.prog != null ? L.prog : (K.stageIdx(c.status) > 1 ? 1 : 0);
      num = K.stageIdx(c.status) > 1 ? K.eta(ageNow) : K.eta(L.eta);
    } else {
      const win = Number(d.ackWindow) || 30;
      const left = Math.max(0, win - ageNow);
      prog = left / win;
      num = left > 0 ? String(Math.ceil(left)) : K.eta(ageNow);
    }
    body.innerHTML = `
      <div class="ln l1"><span class="inv pr">P${p}</span> <span class="tt">${esc(type)}</span><span class="sp"></span><span class="ix">${sel + 1}/${calls().length}</span></div>
      <div class="ln">${esc(up(c.street || c.zone || tr('unknown_location', 'UNKNOWN LOCATION')))}</div>
      <div class="ln"><span>${esc(up(dist.v + dist.u))} ${esc(L.dir || '')}</span><span class="sp"></span><span>${esc(tr('pg_eta', 'ETA'))} ${esc(K.eta(L.eta))}</span></div>
      <div class="ln pb"><span class="bar"><i style="width:${Math.round(prog * 100)}%"></i></span><span class="ag">${esc(num)}</span></div>
      <div class="ln ch">${chainHTML(c.status)}</div>`;
    if (isMine(c)) { soft(tr('pg_clr', 'CLR'), tr('pg_gps', 'GPS')); } else { soft(tr('pg_decl', 'DECL'), tr('pg_ack', 'ACK')); }
  }

  function renderMenu() {
    const items = menu();
    menuSel = Math.max(0, Math.min(menuSel, items.length - 1));
    const start = Math.max(0, Math.min(menuSel - 2, items.length - 5));
    body.innerHTML = `<div class="ln hd"><span class="inv">${esc(tr('pg_menu', 'MENU'))}</span><span class="sp"></span><span class="ix">${menuSel + 1}/${items.length}</span></div>` +
      items.slice(start, start + 4).map((it, i) => {
        const on = start + i === menuSel;
        return `<div class="ln mi ${on ? 'on' : ''}"><span class="cur">${on ? '&gt;' : '&nbsp;'}</span><span>${esc(up(it.label))}</span><span class="sp"></span><span class="${on ? 'inv' : ''}">${esc(up(it.val))}</span></div>`;
      }).join('');
    soft(tr('pg_back', 'BACK'), tr('pg_sel', 'SEL'));
  }

  function renderHistory() {
    const h = d.history || [];
    if (!h.length) {
      body.innerHTML = `<div class="ln hd"><span class="inv">${esc(tr('pg_history', 'HISTORY'))}</span></div><div class="ln dim">${esc(tr('pg_no_history', 'NO PAGES YET'))}</div>`;
    } else {
      histSel = Math.max(0, Math.min(histSel, h.length - 1));
      const start = Math.max(0, Math.min(histSel - 2, h.length - 4));
      body.innerHTML = `<div class="ln hd"><span class="inv">${esc(tr('pg_history', 'HISTORY'))}</span><span class="sp"></span><span class="ix">${histSel + 1}/${h.length}</span></div>` +
        h.slice(start, start + 4).map((e, i) => {
          const on = start + i === histSel;
          return `<div class="ln mi ${on ? 'on' : ''} ${e.closed ? 'dim' : ''}"><span class="cur">${on ? '&gt;' : '&nbsp;'}</span><span>${esc(e.time || '')}</span> <span>P${K.prio(e.priority)}</span> <span class="tt">${esc(up(tr('type_' + (e.type || '') + '_s', e.title || '')))}</span><span class="sp"></span><span>${esc(e.closed ? tr('pg_closed', 'CLSD') : tr('pg_open', 'OPEN'))}</span></div>`;
        }).join('');
    }
    soft(tr('pg_back', 'BACK'), '');
  }

  function renderIdle() {
    const m = d.me || {};
    const st = m.call ? (m.status || 'ENR') : (m.oos ? '10-7' : '10-8');
    body.innerHTML = `
      <div class="ln idle-clk">${esc(live.time || d.time || '--:--')}</div>
      <div class="ln dim ct">${esc(tr('pg_no_calls', 'NO ACTIVE CALLS'))}</div>
      <div class="ln ct"><span class="inv">${esc(st)}</span> <span>${esc(up(tr('unit_' + st.replace('-', ''), '')))}</span></div>`;
    soft(tr('pg_hide', 'HIDE'), tr('pg_menu', 'MENU'));
  }

  function renderHints() {
    const k = esc(d.key || 'F7');
    const html = `<span><kbd>◀</kbd>${esc(tr('pg_h_menu', 'Menu'))}</span><span><kbd>▲</kbd><kbd>▼</kbd>${esc(tr('pg_h_scroll', 'Scroll'))}</span>` +
      `<span><kbd>Y</kbd>${esc(tr('pg_h_ack', 'Ack'))}</span><span><kbd>⌫</kbd>${esc(tr('pg_h_back', 'Back'))}</span><span><kbd>${k}</kbd>${esc(tr('pg_h_hide', 'Put away'))}</span>`;
    if (hintsEl.innerHTML !== html) hintsEl.innerHTML = html;
  }

  function soft(l, r) {
    softL.innerHTML = l ? `<span class="inv">BACK</span> ${esc(up(l))}` : '';
    softR.innerHTML = r ? `<span class="inv">Y</span> ${esc(up(r))}` : '';
  }

  function render() {
    if (!body) return;
    renderStatus();
    if (screen === 'call' && !calls().length) screen = 'idle';
    if (screen === 'idle' && calls().length) screen = 'call';
    ({ call: renderCall, menu: renderMenu, history: renderHistory, idle: renderIdle })[screen]();
    const m = d.me || {};
    ledEl.className = `pg-led ${blink ? 'red blink' : m.call ? 'green' : calls().length ? 'amber' : 'off'}`;
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
    const b = dev.querySelector(`[data-b="${btn}"]`);
    if (b) { b.classList.add('dn'); setTimeout(() => b.classList.remove('dn'), 120); }
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
    lcd.classList.add('flash');
    flashT = setTimeout(() => lcd.classList.remove('flash'), 520);
  }

  function apply(p) {
    const keepId = cur() && cur().id;
    d = Object.assign(d, p || {});
    if (p && p.locale) tr = K.tr(p.locale);
    const now = performance.now();
    (d.calls || []).forEach(c => { c._at = now; });
    if (keepId) { const i = calls().findIndex(c => c.id === keepId); if (i >= 0) sel = i; }
    if (sel >= calls().length) sel = 0;
    render();
  }

  NZA.app('pager', {
    escClose: false,
    init(el) {
      el.innerHTML = `
        <div class="pg-wrap">
          <div class="pg-hints nza-hud solid"></div>
          <div class="pg-dev">
            <div class="pg-shell">
              <div class="pg-top"><span class="pg-led off"></span><div class="pg-brand"><span class="nz-mark"></span>NAYZEEE<em>EMS</em></div><span class="pg-model">NZ-P2</span></div>
              <div class="pg-bezel"><div class="pg-lcd">
                <div class="pg-status"></div>
                <div class="pg-body"></div>
                <div class="pg-soft"><span class="sl" data-b="back"></span><span class="sr" data-b="ack"></span></div>
              </div></div>
              <div class="pg-keys">
                <button class="pg-btn" data-b="left"><svg viewBox="0 0 24 24"><path d="M15 6l-7 6 7 6z"/></svg></button>
                <button class="pg-btn" data-b="up"><svg viewBox="0 0 24 24"><path d="M6 15l6-7 6 7z"/></svg></button>
                <button class="pg-btn" data-b="down"><svg viewBox="0 0 24 24"><path d="M6 9l6 7 6-7z"/></svg></button>
              </div>
              <div class="pg-grille">${'<i></i>'.repeat(14)}</div>
            </div>
          </div>
        </div>`;
      dev = el.querySelector('.pg-dev');
      lcd = el.querySelector('.pg-lcd');
      body = el.querySelector('.pg-body');
      softL = el.querySelector('.sl');
      softR = el.querySelector('.sr');
      statusEl = el.querySelector('.pg-status');
      ledEl = el.querySelector('.pg-led');
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
    close() { clearTimeout(blinkT); blink = false; },
    msg: {
      state: apply,
      focus(p) { d.focused = !!(p && p.on); render(); },
      page(p) {
        const i = calls().findIndex(c => c.id === p.id);
        if (i >= 0 && (screen !== 'menu' || !d.focused)) { sel = i; screen = 'call'; }
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
      ArrowUp() { if (!d.focused) return false; press('up'); },
      ArrowDown() { if (!d.focused) return false; press('down'); },
      y() { if (!d.focused) return false; press('ack'); },
      Y() { if (!d.focused) return false; press('ack'); },
      Enter() { if (!d.focused) return false; press('ack'); },
      Backspace() { if (!d.focused) return false; press('back'); },
      Escape() { if (!d.focused) return false; NZA.post('pager:hide', {}); },
    },
    preview() {
      NZA.demo('pager', {
        focused: true, time: '16:42', muted: false, phone: true, key: 'F7',
        me: { callsign: 'Unit 04', status: '10-8', paired: true, npc: true, call: null },
        calls: [
          { id: 'C-0417', code: '10-56', priority: 2, title: 'Overdose', type: 'overdose', street: 'Palomino Ave', zone: 'Pillbox Hill', status: 'DSP', age: 27 },
          { id: 'C-0416', code: '10-50', priority: 1, title: 'Vehicle Collision', type: 'mva', street: 'Strawberry Ave', zone: 'Strawberry', status: 'ENR', age: 140 },
          { id: 'C-0412', code: '10-52', priority: 3, title: 'Fall', type: 'fall', street: 'Vespucci Blvd', zone: 'Vespucci', status: 'DSP', age: 310 },
        ],
        history: [
          { id: 'C-0417', priority: 2, title: 'Overdose', type: 'overdose', time: '16:41' },
          { id: 'C-0410', priority: 1, title: 'Gunshot', type: 'gunshot', time: '16:12', closed: true },
        ],
        locale: {},
      });
      live = { time: '16:42', calls: { 'C-0417': { dist: 310, dir: 'SW', eta: 19, prog: 0.86 }, 'C-0416': { dist: 1240, dir: 'NE', eta: 71 } } };
      NZA.apps.pager.msg.page({ id: 'C-0417', priority: 2, beep: false });
    },
  });
})();
