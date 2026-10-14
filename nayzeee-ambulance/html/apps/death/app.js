/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · app 'death' — full-screen death screen (HUD design)
   Opened from Lua without focus (client/modules/wounded_death.lua):
     open   { L, name, tod, cause: [{ icon, text, tone, lead }], hold, timer (Config.Death.respawnTimer),
              respawn { hospital, fee, cover, plan, pay, loseItems, loseCash, heal },
              recovery, ...state }
     info   same as open without L (server details arrived)
     state  { respawnIn, ready, loading, respawning, bagged, carried, deadFor,
              call { allowed, left, called, pending }, keys { respawn, call } }
     hold   { p: 0..1 }            hold-to-respawn progress
     flash  { kind, text, ms }
   Timers count down locally between updates.
   ═══════════════════════════════════════════════════════════ */
(() => {
  const esc = NZA.esc;
  const icon = n => NZA.icon(n);
  let L = {};
  const T = (k, fb, ...a) => {
    let s = String(L[k] !== undefined ? L[k] : fb);
    a.forEach(v => { s = s.replace(/%[sd]/, v); });
    return s;
  };
  const money = n => `$${Math.max(0, Math.round(n || 0)).toLocaleString('en-US')}`;
  const mmss = s => { s = Math.max(0, Math.floor(s || 0)); return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`; };

  const D = { info: {}, st: {}, recvAt: 0, deadAt: 0, hold: 0, total: 300 };
  let ui = {};
  let flip = null;
  let ticker = 0;
  let flashTimer = 0;
  let previewHold = null;
  const last = {};
  const setHTML = (k, el, html) => { if (last[k] !== html) { last[k] = html; el.innerHTML = html; } };
  const since = () => (performance.now() - D.recvAt) / 1000;
  const respawnLeft = () => Math.max(0, Math.ceil((D.st.respawnIn || 0) - since()));

  /* flatline: a few weak complexes on the left that fade into a flat line */
  function flatlinePath() {
    const W = 1920, mid = 100;
    let d = `M0 ${mid}`;
    const beat = (x0, amp) => {
      const pts = [[x0, mid], [x0 + 14, mid - 6 * amp], [x0 + 26, mid], [x0 + 34, mid + 10 * amp], [x0 + 42, mid - 70 * amp], [x0 + 52, mid + 34 * amp], [x0 + 62, mid], [x0 + 92, mid - 14 * amp], [x0 + 118, mid]];
      return pts.map(p => `L${p[0]} ${p[1].toFixed(1)}`).join(' ');
    };
    d += ` L110 ${mid} ${beat(110, 0.95)} L310 ${mid} ${beat(310, 0.6)} L480 ${mid} ${beat(480, 0.28)} L${W} ${mid}`;
    return d;
  }

  function build(el) {
    el.innerHTML = `
      <div class="dz-fx"><div class="dz-vig"></div><div class="dz-scan"></div></div>
      <svg class="dz-line" viewBox="0 0 1920 200" preserveAspectRatio="none">
        <defs><linearGradient id="dz-lg" x1="0" x2="1" y1="0" y2="0">
          <stop offset="0" stop-color="#e5484d" stop-opacity="0"/><stop offset=".12" stop-color="#e5484d" stop-opacity=".55"/>
          <stop offset=".5" stop-color="#e5484d" stop-opacity=".9"/><stop offset="1" stop-color="#e5484d" stop-opacity=".15"/></linearGradient></defs>
        <path class="trace" d="${flatlinePath()}"/>
      </svg>
      <header class="dz-head">
        <div class="dz-over"><span class="nz-dot red"></span><span class="t"></span></div>
        <h1 class="dz-title"></h1>
        <div class="dz-meta"></div>
      </header>
      <div class="dz-dock">
        <div class="dz-flash"></div>
        <div class="dz-cards">
          <section class="dz-card nza-hud dz-cause">
            <div class="dz-h"><span class="nza-label"></span></div>
            <ul class="dz-list"></ul>
          </section>
          <section class="dz-card nza-hud dz-resp">
            <div class="dz-h"><span class="nza-label"></span><span class="dz-where"></span></div>
            <div class="dz-act"></div>
            <div class="dz-bill"></div>
            <div class="dz-loss"></div>
          </section>
        </div>
        <div class="dz-note"></div>
      </div>`;
    const q = s => el.querySelector(s);
    ui = {
      root: el, over: q('.dz-over .t'), title: q('.dz-title'), meta: q('.dz-meta'), flash: q('.dz-flash'),
      causeH: q('.dz-cause .nza-label'), list: q('.dz-list'), respH: q('.dz-resp .nza-label'), where: q('.dz-where'),
      act: q('.dz-act'), bill: q('.dz-bill'), loss: q('.dz-loss'), note: q('.dz-note'), resp: q('.dz-resp'),
    };
  }

  /* ─────────────── render ─────────────── */
  function renderStatic() {
    const i = D.info;
    ui.over.textContent = T('death_over', 'Patient status');
    ui.title.textContent = T('death_title', 'DECEASED');
    ui.causeH.textContent = T('death_cause', 'Cause of death');
    ui.respH.textContent = T('death_respawn', 'Respawn');
    const cause = Array.isArray(i.cause) && i.cause.length ? i.cause.slice(0, 6) : null;
    if (cause) {
      setHTML('cause', ui.list, cause.map(c => `<li class="${esc(c.tone || '')} ${c.lead ? 'lead' : ''}"><span class="ic">${icon(c.icon || 'alert')}</span><span class="tx">${esc(c.text)}</span></li>`).join(''));
    } else {
      setHTML('cause', ui.list, '<li class="sk"><span class="ic"></span><span class="tx"></span></li><li class="sk"><span class="ic"></span><span class="tx"></span></li><li class="sk"><span class="ic"></span><span class="tx"></span></li>');
    }
    const r = i.respawn || {};
    setHTML('where', ui.where, r.hospital ? `${icon('hospital')}<span>${esc(r.hospital)}</span>` : '');
    // bill
    let bill = '';
    if (r.fee !== undefined && r.fee !== null) {
      if (r.fee <= 0) {
        bill = `<div class="row tot"><span>${esc(T('death_fee', 'Hospital bill'))}</span><b class="teal">${esc(T('death_free', 'No charge'))}</b></div>`;
      } else {
        bill = `<div class="row"><span>${esc(T('death_fee', 'Hospital bill'))}</span><b>${money(r.fee)}</b></div>`;
        if (r.cover > 0) {
          bill += `<div class="row ins"><span>${icon('shield-check')}${esc(T('death_cover', 'Insurance'))}${r.plan ? ` · ${esc(r.plan)}` : ''} <em>${Math.round(r.cover * 100)}%</em></span><b>−${money(r.fee - r.pay)}</b></div>`;
        }
        bill += `<div class="row tot"><span>${esc(T('death_pay', 'You pay'))}</span><b>${money(r.pay)}</b></div>`;
      }
    }
    setHTML('bill', ui.bill, bill);
    const chips = [];
    if (r.heal !== undefined) chips.push(r.heal ? ['teal', 'heart', T('death_heal', 'You wake up fully treated')] : ['amber', 'bandage', T('death_noheal', 'Your injuries stay with you')]);
    if (r.loseItems !== undefined) chips.push(r.loseItems ? ['red', 'backpack', T('death_items_lost', 'Your items will be taken')] : ['', 'backpack', T('death_items_kept', 'You keep your items')]);
    if (r.loseCash !== undefined) chips.push(r.loseCash ? ['red', 'cash', T('death_cash_lost', 'Your cash will be lost')] : ['', 'cash', T('death_cash_kept', 'You keep your cash')]);
    setHTML('loss', ui.loss, chips.map(c => `<span class="chipx sm ${c[0]}">${icon(c[1])}${esc(c[2])}</span>`).join(''));
  }

  function renderMeta() {
    const i = D.info;
    const deadFor = Math.floor((D.st.deadFor || 0) + since());
    const parts = [];
    if (i.tod) parts.push(`<span>${esc(T('death_tod', 'Time of death'))} <b>${esc(i.tod)}</b></span>`);
    parts.push(`<span>${esc(T('death_for', 'Dead for'))} <b class="mono">${mmss(deadFor)}</b></span>`);
    if (i.name) parts.push(`<span><b>${esc(i.name)}</b></span>`);
    setHTML('meta', ui.meta, parts.join('<i></i>'));
  }

  function renderAct() {
    const s = D.st;
    const k = s.keys || {};
    const r = D.info.respawn || {};
    const leftS = respawnLeft();
    const ready = !s.loading && leftS <= 0;
    ui.resp.classList.toggle('ready', ready && !s.respawning);
    let html;
    if (s.respawning) {
      html = `<div class="dz-busy"><i class="spin"></i><span>${esc(T('death_respawning', 'Respawning…'))}</span></div>`;
      if (flip) { flip = null; }
    } else if (!ready) {
      if (!flip || !ui.act.querySelector('.flip')) {
        ui.act.innerHTML = `<div class="dz-wait"><div class="dz-flip"></div><div class="dz-wt"><small>${esc(T('death_wait', 'You can respawn in'))}</small><div class="dz-prog"><i></i></div></div></div>`;
        last.act = null;
        flip = NZA.ui.FlipClock(ui.act.querySelector('.dz-flip'), { value: mmss(leftS), small: true });
      }
      flip.set(mmss(leftS));
      const total = Math.max(1, D.total || 300);
      const p = ui.act.querySelector('.dz-prog i');
      if (p) p.style.width = `${Math.min(100, (1 - leftS / total) * 100).toFixed(1)}%`;
      return;
    } else {
      const RING = 2 * Math.PI * 19;
      const where = r.hospital ? T('death_at', 'at %s', r.hospital) : '';
      html = `<div class="dz-go ${D.hold > 0 ? 'holding' : ''}">
          <span class="fill" style="width:${(D.hold * 100).toFixed(1)}%"></span>
          <span class="dz-ring"><svg viewBox="0 0 42 42"><circle cx="21" cy="21" r="19" class="bg"/><circle cx="21" cy="21" r="19" class="fg" stroke-dasharray="${(D.hold * RING).toFixed(1)} ${RING.toFixed(1)}"/></svg><kbd>${esc(k.respawn || 'E')}</kbd></span>
          <span class="tx"><b>${esc(T('death_ready', 'Hold %s to respawn', k.respawn || 'E'))}</b>${where ? `<small>${esc(where)}</small>` : ''}</span>
          ${icon('arrow-r')}
        </div>`;
      flip = null;
    }
    setHTML('act', ui.act, html);
  }

  function renderNote() {
    const s = D.st;
    const k = s.keys || {};
    const call = s.call || {};
    const bag = s.bagged;
    const title = bag ? T('death_bagged_t', 'You are in a body bag') : T('death_note_t', 'EMS can still recover your body');
    const msg = bag ? T('death_bagged_m', 'The morgue will process you. You can still respawn when the timer ends.') : T('death_note_m', 'A medic can bag you and take you to the morgue. You can still respawn when the timer ends.');
    let key = '';
    if (D.info.recovery !== false && !bag && call.allowed) {
      const cl = Math.max(0, Math.ceil((call.left || 0) - since()));
      if (call.pending) key = `<span class="k busy"><kbd class="teal">${esc(k.call || 'G')}</kbd><i class="spin"></i></span>`;
      else if (call.called || cl > 0) key = `<span class="k done">${icon('check')}<span>${esc(T('help_recovery', 'Body recovery requested'))}</span>${cl > 0 ? `<em>${mmss(cl)}</em>` : ''}</span>`;
      else key = `<span class="k"><kbd>${esc(k.call || 'G')}</kbd><span>${esc(T('k_recovery', 'Request body recovery'))}</span></span>`;
    }
    setHTML('note', ui.note, `<span class="ni">${icon(bag ? 'box' : 'ambulance')}</span><div class="tx"><b>${esc(title)}</b><p>${esc(msg)}</p></div>${key}`);
  }

  function tick() {
    renderMeta();
    renderAct();
    renderNote();
  }

  function applyInfo(d) {
    ['name', 'tod', 'cause', 'hold', 'respawn', 'recovery'].forEach(k => { if (d[k] !== undefined) D.info[k] = d[k]; });
    renderStatic();
  }

  function applyState(d) {
    if (d.timer) D.total = Math.max(1, d.timer);
    D.st = Object.assign({}, D.st, d);
    D.recvAt = performance.now();
    tick();
  }

  function flash({ kind = 'ok', text = '', ms = 3200 } = {}) {
    if (!text) return;
    ui.flash.className = `dz-flash on ${kind}`;
    ui.flash.innerHTML = `${icon(kind === 'ok' ? 'check' : kind === 'bad' ? 'x' : 'alert')}<span>${esc(text)}</span>`;
    clearTimeout(flashTimer);
    flashTimer = setTimeout(() => { ui.flash.className = 'dz-flash'; }, ms);
  }

  NZA.app('death', {
    escClose: false,
    init(el) { build(el); },
    open(d) {
      L = Object.assign({}, d.L || {});
      D.info = {};
      D.st = {};
      D.hold = 0;
      D.total = Math.max(1, d.timer || d.respawnIn || 300);
      Object.keys(last).forEach(k => { delete last[k]; });
      flip = null;
      ui.act.innerHTML = '';
      ui.root.classList.remove('in');
      void ui.root.offsetWidth;
      ui.root.classList.add('in');
      applyInfo(d);
      applyState(d);
      clearInterval(ticker);
      ticker = setInterval(tick, 250);
    },
    close() {
      clearInterval(ticker);
      clearTimeout(flashTimer);
      ui.flash.className = 'dz-flash';
      if (previewHold) { previewHold.destroy(); previewHold = null; }
    },
    msg: {
      info(d) { applyInfo(d); applyState(d); },
      state(d) { applyState(d); },
      hold(d) { D.hold = Math.max(0, Math.min(1, d.p || 0)); last.act = null; renderAct(); },
      flash(d) { flash(d); },
    },

    /* browser demo: index.html?app=death&demo=wait|ready|bagged|gaveup */
    preview() {
      const demo = new URLSearchParams(location.search).get('demo') || 'wait';
      const ready = demo === 'ready' || demo === 'gaveup';
      const cause = demo === 'gaveup'
        ? [
          { icon: 'flag', text: 'Gave up', tone: 'red', lead: true },
          { icon: 'knife', text: 'Serious stab wound · Abdomen', tone: 'red' },
          { icon: 'cut', text: 'Moderate deep laceration · Left forearm', tone: 'amber' },
          { icon: 'drop', text: 'Lost 31% of their blood (1.6 L)', tone: 'amber' },
        ]
        : [
          { icon: 'skull', text: 'Bled out before help arrived', tone: 'red', lead: true },
          { icon: 'crosshair', text: 'Critical gunshot wound · Chest', tone: 'red' },
          { icon: 'drop', text: 'Moderate internal bleeding · Abdomen', tone: 'amber' },
          { icon: 'lungs', text: 'Blood around a lung', tone: 'amber' },
          { icon: 'drop', text: 'Lost 52% of their blood (2.6 L)', tone: 'red' },
          { icon: 'ecg', text: 'No pulse for 05:00', tone: 'dim' },
        ];
      NZA.demo('death', {
        L: {},
        name: 'Michael Garcia', tod: '21:47', hold: 3, timer: 300, cause, recovery: true,
        respawn: { hospital: 'Pillbox Hill Medical Center', fee: 500, cover: 0.8, plan: 'Gold', pay: 100, loseItems: false, loseCash: true, heal: true },
        respawnIn: ready ? 0 : 252, ready, loading: false, respawning: false, bagged: demo === 'bagged', carried: false, deadFor: ready ? 318 : 48,
        call: { allowed: true, left: demo === 'bagged' ? 0 : (ready ? 0 : 37), called: !ready, pending: false },
        keys: { respawn: 'E', call: 'G' },
      });
      previewHold = NZA.ui.Hold({
        key: 'e', seconds: 3,
        onProgress: p => { if (respawnLeft() <= 0) NZA.apps.death.msg.hold({ p }); },
        onDone: () => applyState({ respawning: true }),
      });
    },
  });
})();
