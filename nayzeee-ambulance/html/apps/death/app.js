/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · app 'death' — full-screen death screen (cinematic letterbox)
   Top bar      kicker + "You didn't make it" + time of death / time since / name (instrument trio)
   Bottom bar   its top edge is the patient's last trace going flat; body pickup note + key
   Left card    "What happened": the lead cause + contributing lines on a vertical spine
   Right card   "Wake up in hospital": the status ring fills while the respawn timer runs, then
                turns into the hold ring; bill as an instrument list; what you keep / lose
   The centre stays clear for the death camera.
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
  const TICKS = 60;

  const D = { info: {}, st: {}, recvAt: 0, hold: 0, total: 300, view: '', lit: -1 };
  let ui = {};
  let odo = null;
  let sinceOdo = null;
  let ticker = 0;
  let flashTimer = 0;
  let previewHold = null;
  const last = {};
  const setHTML = (k, el, html) => { if (last[k] !== html) { last[k] = html; el.innerHTML = html; } };
  const setText = (el, t) => { if (el.textContent !== t) el.textContent = t; };
  const since = () => (performance.now() - D.recvAt) / 1000;
  const respawnLeft = () => Math.max(0, Math.ceil((D.st.respawnIn || 0) - since()));

  /* the last trace: a few weakening complexes that run out into a flat line */
  function flatlinePath() {
    const W = 1920, mid = 60;
    let d = `M0 ${mid}`;
    const beat = (x0, amp) => {
      const pts = [[x0, mid], [x0 + 14, mid - 6 * amp], [x0 + 26, mid], [x0 + 34, mid + 9 * amp], [x0 + 42, mid - 52 * amp], [x0 + 52, mid + 26 * amp], [x0 + 62, mid], [x0 + 92, mid - 11 * amp], [x0 + 118, mid]];
      return pts.map(p => `L${p[0]} ${p[1].toFixed(1)}`).join(' ');
    };
    d += ` L90 ${mid} ${beat(90, 1)} L300 ${mid} ${beat(300, 0.62)} L520 ${mid} ${beat(520, 0.3)} L760 ${mid} L770 ${mid - 4} L778 ${mid} L${W} ${mid}`;
    return d;
  }

  function dialTicks() {
    let out = '';
    for (let i = 0; i < TICKS; i++) {
      const a = (i / TICKS) * Math.PI * 2;
      const lg = i % 5 === 0;
      const r1 = lg ? 88 : 90.5, r2 = 96.5;
      const sx = Math.sin(a), cy = Math.cos(a);
      out += `<line class="${lg ? 'lg' : ''}" x1="${(100 + r1 * sx).toFixed(2)}" y1="${(100 - r1 * cy).toFixed(2)}" x2="${(100 + r2 * sx).toFixed(2)}" y2="${(100 - r2 * cy).toFixed(2)}"/>`;
    }
    return out;
  }

  function build(el) {
    el.innerHTML = `
      <div class="dz-fx"><div class="dz-vig"></div><div class="dz-grain"></div></div>
      <header class="dz-bar dz-top">
        <div class="dz-ttl">
          <span class="dz-kick"><i></i><span></span></span>
          <h1 class="dz-title"></h1>
        </div>
        <dl class="dz-meta">
          <div class="m tod"><dt></dt><dd></dd></div>
          <div class="m for"><dt></dt><dd><span class="so"></span></dd></div>
          <div class="m who"><dt></dt><dd></dd></div>
        </dl>
      </header>
      <footer class="dz-bar dz-bot">
        <svg class="dz-line" viewBox="0 0 1920 120" preserveAspectRatio="none">
          <defs><linearGradient id="dz-lg" x1="0" x2="1" y1="0" y2="0">
            <stop offset="0" stop-color="#e5484d" stop-opacity=".15"/><stop offset=".08" stop-color="#e5484d" stop-opacity=".95"/>
            <stop offset=".42" stop-color="#e5484d" stop-opacity=".75"/><stop offset="1" stop-color="#e5484d" stop-opacity=".35"/></linearGradient></defs>
          <path class="trace" d="${flatlinePath()}"/>
        </svg>
        <i class="dz-sweep"></i>
        <div class="dz-note"></div>
        <div class="dz-call"></div>
      </footer>
      <aside class="dz-case nza-hud solid">
        <header class="dz-h"><span class="nza-label"></span><b class="dz-cnt"></b></header>
        <ol class="dz-spine"></ol>
      </aside>
      <aside class="dz-ret nza-hud solid">
        <header class="dz-h"><span class="nza-label"></span></header>
        <div class="dz-where"></div>
        <div class="dz-ring s-wait">
          <svg viewBox="0 0 200 200">
            <g class="ticks">${dialTicks()}</g>
            <circle class="trk" cx="100" cy="100" r="80"/>
            <circle class="arc" cx="100" cy="100" r="80" pathLength="100" transform="rotate(-90 100 100)" stroke-dasharray="0 100"/>
            <circle class="htrk" cx="100" cy="100" r="69"/>
            <circle class="hold" cx="100" cy="100" r="69" pathLength="100" transform="rotate(-90 100 100)" stroke-dasharray="0 100"/>
          </svg>
          <div class="dz-core">
            <div class="v v-wait"><span class="vi">${icon('hospital')}</span><div class="dz-odo"></div><small class="cap"></small></div>
            <div class="v v-ready"><kbd class="big"></kbd><small class="cap"></small></div>
            <div class="v v-busy"><i class="spin"></i><small class="cap"></small></div>
          </div>
        </div>
        <p class="dz-status"></p>
        <div class="dz-bill"></div>
        <ul class="dz-loss"></ul>
      </aside>
      <div class="dz-flash"></div>`;
    const q = s => el.querySelector(s);
    ui = {
      root: el, kick: q('.dz-kick span'), title: q('.dz-title'),
      todK: q('.m.tod dt'), todV: q('.m.tod dd'), forK: q('.m.for dt'), whoK: q('.m.who dt'), whoV: q('.m.who dd'), whoBox: q('.m.who'), todBox: q('.m.tod'),
      note: q('.dz-note'), call: q('.dz-call'), flash: q('.dz-flash'),
      caseH: q('.dz-case .nza-label'), cnt: q('.dz-cnt'), spine: q('.dz-spine'),
      retH: q('.dz-ret .nza-label'), where: q('.dz-where'), ring: q('.dz-ring'), arc: q('.dz-ring .arc'), hold: q('.dz-ring .hold'),
      ticks: [...el.querySelectorAll('.dz-ring .ticks line')],
      capWait: q('.v-wait .cap'), capReady: q('.v-ready .cap'), capBusy: q('.v-busy .cap'), key: q('.v-ready kbd'),
      status: q('.dz-status'), bill: q('.dz-bill'), loss: q('.dz-loss'), ret: q('.dz-ret'),
    };
    odo = NZA.ui.FlipClock(q('.dz-odo'), { value: '00:00' });
    sinceOdo = NZA.ui.FlipClock(q('.m.for .so'), { value: '00:00', small: true });
  }

  /* ─────────────── render ─────────────── */
  function renderStatic() {
    const i = D.info;
    setText(ui.title, T('death_title', "You didn't make it"));
    setText(ui.caseH, T('death_cause', 'What happened'));
    setText(ui.retH, T('death_respawn', 'Wake up in hospital'));
    setText(ui.todK, T('death_tod', 'Time of death'));
    setText(ui.forK, T('death_for', 'Since death'));
    setText(ui.whoK, T('death_name', 'Patient'));
    setText(ui.todV, i.tod || '--:--');
    ui.whoBox.style.display = i.name ? '' : 'none';
    setText(ui.whoV, i.name || '');

    const cause = Array.isArray(i.cause) && i.cause.length ? i.cause.slice(0, 6) : null;
    setText(ui.cnt, cause ? String(cause.length) : '');
    ui.cnt.style.display = cause ? '' : 'none';
    if (cause) {
      const lead = cause.find(c => c.lead) || null;
      const rest = cause.filter(c => c !== lead);
      let html = '';
      if (lead) html += `<li class="lead ${esc(lead.tone || 'red')}"><span class="li">${icon(lead.icon || 'alert')}</span><span class="tx">${esc(lead.text)}</span></li>`;
      html += rest.map(c => `<li class="${esc(c.tone || '')}"><span class="nd"></span><span class="ic">${icon(c.icon || 'alert')}</span><span class="tx">${esc(c.text)}</span></li>`).join('');
      setHTML('cause', ui.spine, html);
    } else {
      setHTML('cause', ui.spine, '<li class="lead sk"><span class="li"></span><span class="tx"></span></li><li class="sk"><span class="nd"></span><span class="ic"></span><span class="tx"></span></li><li class="sk"><span class="nd"></span><span class="ic"></span><span class="tx"></span></li>');
    }

    const r = i.respawn || {};
    setHTML('where', ui.where, r.hospital ? `<span class="hi">${icon('hospital')}</span><span class="hn">${esc(r.hospital)}</span>` : '');
    ui.where.style.display = r.hospital ? '' : 'none';

    // bill as an instrument list
    let bill = '';
    if (r.fee !== undefined && r.fee !== null) {
      if (r.fee <= 0) {
        bill = `<div class="row tot teal"><span>${esc(T('death_pay', 'Your share'))}</span><b>${esc(T('death_free', 'Free'))}</b></div>`;
      } else {
        bill = `<div class="row"><i class="nt"></i><span>${esc(T('death_fee', 'Treatment cost'))}</span><b>${money(r.fee)}</b></div>`;
        if (r.cover > 0) {
          bill += `<div class="row ins"><i class="nt"></i><span>${esc(T('death_cover', 'Insurance'))}${r.plan ? ` · ${esc(r.plan)}` : ''}<em>${Math.round(r.cover * 100)}%</em></span><b>−${money(r.fee - r.pay)}</b></div>`;
        }
        bill += `<div class="row tot"><span>${esc(T('death_pay', 'Your share'))}</span><b>${money(r.pay)}</b></div>`;
      }
    }
    setHTML('bill', ui.bill, bill);
    ui.bill.style.display = bill ? '' : 'none';

    const rows = [];
    if (r.heal !== undefined) rows.push(r.heal ? ['teal', 'heart', T('death_heal', 'Injuries treated on arrival')] : ['amber', 'bandage', T('death_noheal', 'Your injuries stay with you')]);
    if (r.loseItems !== undefined) rows.push(r.loseItems ? ['red', 'backpack', T('death_items_lost', 'You lose your items')] : ['', 'backpack', T('death_items_kept', 'Your items stay with you')]);
    if (r.loseCash !== undefined) rows.push(r.loseCash ? ['red', 'cash', T('death_cash_lost', 'You lose your cash')] : ['', 'cash', T('death_cash_kept', 'Your cash stays with you')]);
    setHTML('loss', ui.loss, rows.map(c => `<li class="${c[0]}"><span class="ic">${icon(c[1])}</span><span>${esc(c[2])}</span></li>`).join(''));
    ui.loss.style.display = rows.length ? '' : 'none';
  }

  function renderMeta() {
    const deadFor = Math.floor((D.st.deadFor || 0) + since());
    sinceOdo.set(mmss(deadFor));
    setText(ui.kick, D.st.bagged ? T('death_over_bag', 'Body bagged') : T('death_over', 'Life signs lost'));
    ui.root.classList.toggle('bagged', !!D.st.bagged);
  }

  function setView(v) {
    if (D.view === v) return;
    D.view = v;
    ui.ring.classList.remove('s-wait', 's-ready', 's-busy');
    ui.ring.classList.add(`s-${v}`);
    ui.ret.classList.toggle('ready', v === 'ready');
  }

  function renderRing() {
    const s = D.st;
    const k = s.keys || {};
    const r = D.info.respawn || {};
    const leftS = respawnLeft();
    const ready = !s.loading && leftS <= 0;
    const where = r.hospital || T('death_hospital', 'the nearest hospital');
    let f;
    if (s.respawning) {
      setView('busy');
      f = 1;
      setText(ui.capBusy, T('death_respawning', 'Waking up…'));
      setText(ui.status, T('death_moving', 'Taking you to %s', where));
    } else if (!ready) {
      setView('wait');
      const total = Math.max(1, D.total || 300);
      f = Math.max(0, Math.min(1, 1 - leftS / total));
      odo.set(mmss(leftS));
      setText(ui.capWait, T('death_wait', 'Until respawn'));
      setText(ui.status, T('death_wait_m', 'Respawn unlocks when the ring is full.'));
    } else {
      setView('ready');
      f = 1;
      const key = k.respawn || 'E';
      setText(ui.key, key);
      setText(ui.capReady, T('death_hold', 'Hold %d s', D.info.hold || 3));
      setText(ui.status, T('death_ready', 'Hold %s to wake up at %s', key, where));
    }
    ui.arc.setAttribute('stroke-dasharray', `${(f * 100).toFixed(2)} 100`);
    const hp = D.view === 'ready' ? D.hold : 0;
    ui.hold.setAttribute('stroke-dasharray', `${(hp * 100).toFixed(2)} 100`);
    ui.hold.style.opacity = hp > 0.002 ? '' : '0';     // a round cap would draw a dot at 0
    ui.arc.style.opacity = f > 0.002 ? '' : '0';
    ui.ring.classList.toggle('holding', D.view === 'ready' && D.hold > 0);
    const lit = Math.ceil(f * TICKS - 0.001);
    if (lit !== D.lit) { D.lit = lit; ui.ticks.forEach((t, i) => t.classList.toggle('on', i < lit)); }
  }

  function renderNote() {
    const s = D.st;
    const k = s.keys || {};
    const call = s.call || {};
    const bag = s.bagged;
    const title = bag ? T('death_bagged_t', 'Your body is bagged') : T('death_note_t', 'Your body can still be collected');
    const msg = bag ? T('death_bagged_m', 'The morgue takes it from here. Respawn stays open to you.') : T('death_note_m', 'A medic can bag you and take you to the morgue. Respawn stays open to you.');
    setHTML('note', ui.note, `<span class="ni">${icon(bag ? 'box' : 'ambulance')}</span><div class="tx"><b>${esc(title)}</b><p>${esc(msg)}</p></div>`);
    let key = '';
    if (D.info.recovery !== false && !bag && call.allowed) {
      const cl = Math.max(0, Math.ceil((call.left || 0) - since()));
      if (call.pending) key = `<span class="k busy"><kbd class="teal">${esc(k.call || 'G')}</kbd><span>${esc(T('k_calling', 'Calling…'))}</span><i class="spin"></i></span>`;
      else if (call.called || cl > 0) key = `<span class="k done"><span class="ok">${icon('check')}</span><span>${esc(T('help_recovery', 'Pickup requested'))}</span>${cl > 0 ? `<em>${mmss(cl)}</em>` : ''}</span>`;
      else key = `<span class="k hot"><kbd class="teal">${esc(k.call || 'G')}</kbd><span>${esc(T('k_recovery', 'Ask for body pickup'))}</span></span>`;
    }
    setHTML('call', ui.call, key);
  }

  function tick() {
    renderMeta();
    renderRing();
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
    ui.flash.innerHTML = `<span class="fi">${icon(kind === 'ok' ? 'check' : kind === 'bad' ? 'x' : 'alert')}</span><span>${esc(text)}</span>`;
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
      D.view = '';
      D.lit = -1;
      D.total = Math.max(1, d.timer || d.respawnIn || 300);
      Object.keys(last).forEach(k => { delete last[k]; });
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
      hold(d) { D.hold = Math.max(0, Math.min(1, d.p || 0)); renderRing(); },
      flash(d) { flash(d); },
    },

    /* browser demo: index.html?app=death&demo=wait|ready|bagged|gaveup|free|respawning */
    preview() {
      const demo = new URLSearchParams(location.search).get('demo') || 'wait';
      const ready = demo === 'ready' || demo === 'gaveup' || demo === 'free' || demo === 'respawning';
      const cause = demo === 'gaveup'
        ? [
          { icon: 'flag', text: 'You let go', tone: 'red', lead: true },
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
      const respawn = demo === 'free'
        ? { hospital: 'Sandy Shores Medical Center', fee: 0, cover: 0, plan: null, pay: 0, loseItems: true, loseCash: false, heal: false }
        : { hospital: 'Pillbox Hill Medical Center', fee: 500, cover: 0.8, plan: 'Gold', pay: 100, loseItems: false, loseCash: true, heal: true };
      NZA.demo('death', {
        L: {},
        name: 'Michael Garcia', tod: '21:47', hold: 3, timer: 300, cause, recovery: true, respawn,
        respawnIn: ready ? 0 : 252, ready, loading: false, respawning: demo === 'respawning', bagged: demo === 'bagged', carried: false, deadFor: ready ? 318 : 48,
        call: { allowed: true, left: demo === 'bagged' ? 0 : (ready ? 0 : 37), called: !ready, pending: false },
        keys: { respawn: 'E', call: 'G' },
      });
      if (demo === 'ready') NZA.apps.death.msg.hold({ p: 0.42 });
      if (previewHold) previewHold.destroy();
      previewHold = NZA.ui.Hold({
        key: 'e', seconds: 3,
        onProgress: p => { if (respawnLeft() <= 0) NZA.apps.death.msg.hold({ p }); },
        onDone: () => applyState({ respawning: true }),
      });
    },
  });
})();
