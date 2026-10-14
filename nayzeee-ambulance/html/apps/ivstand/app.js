/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · IV stand (app 'ivstand')

   A HUD panel on the right (HUD design): patient group / IV access, live vitals, two hooks with the
   hung bags (saline or labelled blood units, fill, rate, compatibility), roller clamp, pressure
   infuser (gauge + squeeze), infusion rate and time left, TXA slow push, alerts (transfusion
   reaction, unknown group, dilution, no line). The selected blood unit's printed label sits beside
   the panel with the crossmatch strip.

   Lua → JS  open { locale, keys, cfg, data, bay }   data (panel data)   snap (live patient)
   JS → Lua  ivstand:hang { kind, serial?, slot?, force?, rate, hook } → { ok, result | err, msg }
             ivstand:rate { id, rate }   ivstand:takedown { id }   ivstand:txa { seconds }
             ivstand:type   ivstand:iv   ivstand:fill { type }   ivstand:refresh   ivstand:close
   Keys (Config.Blood.Stand.keys, KeyboardEvent.code): squeeze Space · clamp Q / E · TXA hold T
        (Shift = faster) · hooks 1 / 2 · ESC close
   ═══════════════════════════════════════════════════════════ */
(() => {
  const APP = 'ivstand';
  const { esc, clamp } = NZA;
  const icon = (n) => NZA.icon(n);

  let Lc = {};
  const T = (k, fb) => (Lc[k] !== undefined ? Lc[k] : fb);
  const F = (s, ...a) => { let i = 0; return String(s).replace(/%[sd]/g, () => (a[i++] ?? '')); };
  const BB = () => window.NZABlood || {};
  const fmtType = (t) => String(t || '?').replace('-', '−');
  const keyCap = (code) => {
    const c = String(code || '');
    if (c === 'Space') return T('key_space', 'Space');
    if (/^Key[A-Z]$/.test(c)) return c.slice(3);
    if (/^Digit\d$/.test(c)) return c.slice(5);
    return c;
  };
  const REGION = { l_lower_arm: 'Left forearm', r_lower_arm: 'Right forearm', l_upper_arm: 'Left upper arm', r_upper_arm: 'Right upper arm', l_lower_leg: 'Left shin', r_lower_leg: 'Right shin', l_upper_leg: 'Left thigh', r_upper_leg: 'Right thigh', chest: 'Sternum' };

  const S = { on: false };

  /* ═══════════════════════════ DATA ═══════════════════════════ */

  function patient() {
    const d = S.data || {}, sn = S.snap || {};
    const p = Object.assign({}, d.patient || {});
    if (S.snap) {
      p.typed = sn.typed; p.bloodType = sn.typed ? sn.bloodType : null;
      p.state = sn.state || p.state; p.bloodPct = sn.bloodPct ?? p.bloodPct; p.bleed = sn.bleed ?? p.bleed;
      p.vitals = sn.vitals || p.vitals; p.reaction = sn.reaction || null;
      if (sn.given) p.given = { saline: Math.round(sn.given.saline || 0), blood: Math.round(sn.given.blood || 0), txa: sn.given.txa || 0 };
    }
    return p;
  }
  function access() { return S.snap ? S.snap.access : (S.data || {}).access; }

  // infusions with their hook (server panel data knows hooks; the live snapshot knows volumes)
  function infusions() {
    const base = (S.data && S.data.infusions) || [];
    const hookOf = {}; base.forEach(i => { if (i.hook) hookOf[i.id] = i.hook; });
    let list;
    if (S.snap && S.snap.infusions) {
      list = S.snap.infusions.map(i => Object.assign({}, base.find(b => b.id === i.id) || {}, i, { hook: hookOf[i.id] }));
      base.filter(b => b.done && !list.find(x => x.id === b.id)).forEach(b => list.push(b));
    } else list = base.map(i => Object.assign({}, i));
    const used = new Set(list.filter(i => i.hook).map(i => i.hook));
    list.forEach(i => { if (!i.hook) { for (let h = 1; h <= S.cfg.maxBags; h++) if (!used.has(h)) { i.hook = h; used.add(h); break; } } });
    return list;
  }
  const onHook = (h) => infusions().find(i => i.hook === h);

  function bagState(inf) {
    let b = S.bags[inf.id];
    if (!b) {
      const g = S.cfg.gravity || 32;
      b = S.bags[inf.id] = { clamp: clamp((inf.rate || g * 0.66) / g, 0, 1), p: 0, sent: inf.rate || 0, sentAt: 0, left: inf.left, leftAt: performance.now(), srvLeft: inf.left };
    }
    return b;
  }
  function rateOf(inf) {
    const b = bagState(inf), c = S.cfg;
    return (c.gravity || 32) * b.clamp * (1 + (c.pressureGain || 1.15) * b.p / (c.maxPressure || 300));
  }

  /* ═══════════════════════════ BUILD ═══════════════════════════ */

  function build(el) {
    el.innerHTML = '';
    const wrap = NZA.el('div', 'iv-wrap');
    wrap.innerHTML = `
      <aside class="iv-flyout"></aside>
      <section class="iv-panel nza-hud solid rail nza-int">
        <header class="iv-hd">
          <div class="iv-hd-l"><div class="nza-label">${icon('iv')}${esc(T('stand_title', 'IV stand'))}${S.bay ? `<span class="iv-bay">${esc(T('stand_bay', 'Treatment bay'))}</span>` : ''}</div>
            <div class="nza-h iv-name"></div><div class="iv-chips"></div></div>
          <button class="pill-close">${esc(T('close', 'Close'))}</button>
        </header>
        <div class="iv-vit"></div>
        <div class="iv-blood"></div>
        <div class="iv-hooks"></div>
        <div class="iv-ctl"></div>
        <div class="iv-txa"></div>
        <div class="iv-alerts"></div>
        <footer class="iv-keys"></footer>
        <div class="iv-pick"></div>
      </section>`;
    el.appendChild(wrap);
    S.el = el; S.wrap = wrap;
    S.q = (s) => wrap.querySelector(s);
    S.q('.pill-close').onclick = () => NZA.close(APP);
    S.q('.iv-hooks').addEventListener('click', onHooksClick);
    S.q('.iv-alerts').addEventListener('click', onAlertClick);
    S.q('.iv-chips').addEventListener('click', onAlertClick);
    renderAll();
  }

  function renderAll() {
    renderHead(); renderVitals(); renderHooks(); renderControls(); renderTxa(); renderAlerts(); renderKeys(); renderFlyout();
    if (S.picker) renderPicker();
  }

  function renderHead() {
    const p = patient();
    S.q('.iv-name').textContent = p.name || T('patient', 'Patient');
    const acc = access();
    const chips = [];
    if (p.typed && p.bloodType) chips.push(`<span class="iv-chip type">${icon('bloodbag')}${esc(F(T('chip_group', 'Group %s'), fmtType(p.bloodType)))}</span>`);
    else chips.push(`<span class="iv-chip amber">${icon('bloodbag')}${esc(T('chip_untyped', 'Group unknown'))}</span>${S.cfg.typeScreen && (S.data.perms || {}).type ? `<button class="iv-mini" data-a="type">${esc(T('btn_type', 'Type & screen'))}</button>` : ''}`);
    if (acc) chips.push(`<span class="iv-chip teal">${icon('iv')}${esc(F(T('chip_access', '%s · %s'), String(acc.kind || 'iv').toUpperCase(), T('site_' + acc.site, REGION[acc.site] || T('site_unknown', 'line in'))))}</span>`);
    else chips.push(`<span class="iv-chip red">${icon('iv')}${esc(T('chip_noaccess', 'No IV access'))}</span>`);
    if (S.data.warm) chips.push(`<span class="iv-chip">${icon('thermo')}${esc(T('chip_warm', 'Warmed'))}</span>`);
    S.q('.iv-chips').innerHTML = chips.join('');
  }

  function renderVitals() {
    const p = patient(), v = p.vitals || {};
    const map = v.map;
    const mapTone = map === undefined || map === null ? '' : map < 60 ? 'red' : map < 65 ? 'amber' : 'teal';
    const n = (x) => (x === undefined || x === null ? '--' : Math.round(x));
    S.q('.iv-vit').innerHTML = `
      <div class="c hr"><span>${esc(T('v_hr', 'HR'))}</span><b>${n(v.hr)}</b></div>
      <div class="c bp"><span>${esc(T('v_bp', 'NIBP'))}</span><b>${n(v.sys)}<i>/${n(v.dia)}</i></b></div>
      <div class="c map ${mapTone}"><span>${esc(T('v_map', 'MAP'))}</span><b>${n(map)}</b></div>
      <div class="c sp"><span>SpO₂</span><b>${n(v.spo2)}</b></div>`;
    const pct = clamp(Number(p.bloodPct ?? 100), 0, 110);
    const bleed = Number(p.bleed || 0);
    const g = p.given || {};
    S.q('.iv-blood').innerHTML = `
      <div class="bv"><div class="l"><span>${esc(T('v_volume', 'Blood volume'))}</span><b class="${pct < 70 ? 't-red' : pct < 85 ? 't-amber' : ''}">${Math.round(pct)}<i>%</i></b></div>${NZA.ui.meterHTML({ value: pct / 100, zone: [0.85, 1], tone: pct < 70 ? 'red' : pct < 85 ? 'amber' : '' })}</div>
      <div class="kv"><span>${esc(T('v_bleed', 'Bleeding'))}</span><b class="${bleed > 5 ? 't-red' : bleed > 1 ? 't-amber' : ''}">${bleed.toFixed(1)}<i>mL/min</i></b></div>
      <div class="kv"><span>${esc(T('v_saline_in', 'Saline given'))}</span><b>${Math.round(g.saline || 0)}<i>mL</i></b></div>
      <div class="kv"><span>${esc(T('v_blood_in', 'Blood given'))}</span><b>${Math.round(g.blood || 0)}<i>mL</i></b></div>`;
  }

  function hookCard(h) {
    const inf = onHook(h);
    const key = keyCap(h === 1 ? S.keys.hookA : S.keys.hookB);
    const sel = S.sel === h;
    const name = h === 1 ? T('hook_a', 'Hook A') : T('hook_b', 'Hook B');
    if (!inf) {
      const inv = (S.data && S.data.inventory) || {};
      const bloodN = (inv.bags || []).filter(b => !b.expired).length;
      return `<button class="iv-hook empty ${sel ? 'sel' : ''}" data-hook="${h}">
        <div class="hh"><kbd>${esc(key)}</kbd><span>${esc(name)}</span></div>
        <div class="add">${icon('plus')}<b>${esc(T('hang_bag', 'Hang a bag'))}</b><small>${esc(F(T('hang_have', 'Saline %s · Blood %s'), inv.saline || 0, bloodN))}</small></div>
      </button>`;
    }
    const blood = inf.kind === 'blood';
    const b = bagState(inf);
    const left = inf.done ? 0 : Math.max(0, b.left ?? inf.left ?? 0);
    const ml = inf.ml || (blood ? 450 : 500);
    const p = patient();
    const bad = blood && inf.incompatible;
    const status = inf.done ? ['', T('hk_empty', 'Empty')] : inf.paused ? ['amber', T('hk_paused', 'Paused · no line')] : bad ? ['red', T('hk_incompatible', 'Incompatible')] : b.clamp <= 0.01 ? ['', T('hk_clamped', 'Clamped')] : ['teal', T('hk_running', 'Running')];
    const title = blood ? F(T('bag_blood_t', '%s red cells'), fmtType(inf.bag && inf.bag.type)) : inf.kind === 'plasma' ? T('bag_plasma_t', 'Plasma') : T('bag_saline_t', 'Saline 0.9%');
    const sub = blood ? ((inf.bag && inf.bag.serial) || '') : `${ml} mL`;
    const rate = inf.done || inf.paused ? 0 : rateOf(inf);
    return `<div class="iv-hook ${sel ? 'sel' : ''} ${bad ? 'bad' : ''} ${inf.done ? 'done' : ''}" data-hook="${h}">
      <div class="hh"><kbd>${esc(key)}</kbd><span>${esc(name)}</span><span class="st ${status[0]}">${esc(status[1])}</span></div>
      <div class="hb">
        <div class="bag">${(BB().bagSVG || (() => ''))({ fill: left / ml, kind: blood ? 'blood' : 'saline', type: inf.bag && inf.bag.type, w: 56, h: 80 })}</div>
        <div class="info">
          <b>${esc(title)}</b><small>${esc(sub)}</small>
          <div class="lv"><span>${esc(T('left', 'Left'))}</span><em>${Math.round(left)}<i>/ ${ml} mL</i></em></div>
          ${NZA.ui.meterHTML({ value: left / ml, tone: bad ? 'red' : blood ? 'red' : '' })}
          <div class="lv"><span>${esc(T('rate', 'Rate'))}</span><em class="rt">${rate.toFixed(0)}<i>mL/min</i></em></div>
        </div>
      </div>
      <button class="btn-line btn-sm btn-block iv-down ${bad ? 'red' : ''}" data-down="${esc(inf.id)}">${icon('arrow-down')}${esc(inf.done ? T('btn_remove', 'Remove empty bag') : T('btn_takedown', 'Unhang'))}</button>
    </div>`;
  }

  function renderHooks() {
    const n = Math.max(1, S.cfg.maxBags || 2);
    let html = '';
    for (let h = 1; h <= n; h++) html += hookCard(h);
    const box = S.q('.iv-hooks');
    box.style.gridTemplateColumns = `repeat(${Math.min(n, 2)}, 1fr)`;
    box.innerHTML = html;
  }

  // 240° pressure dial in the kit language: track, working band, filled arc, red over-pressure tip
  function gaugeSVG(p) {
    const max = S.cfg.maxPressure || 300;
    const A0 = 150, SW = 240, R = 40, C = 50;
    const pt = (f, r = R) => { const a = (A0 + SW * clamp(f, 0, 1)) * Math.PI / 180; return [C + r * Math.cos(a), C + r * Math.sin(a)]; };
    const arc = (f0, f1, r = R) => { const [x0, y0] = pt(f0, r), [x1, y1] = pt(f1, r); return `M${x0.toFixed(2)} ${y0.toFixed(2)}A${r} ${r} 0 ${(f1 - f0) * SW > 180 ? 1 : 0} 1 ${x1.toFixed(2)} ${y1.toFixed(2)}`; };
    const f = clamp(p / max, 0, 1);
    const over = p > max * 0.97;
    let ticks = '';
    for (let i = 0; i <= 12; i++) {
      const [a, b] = pt(i / 12, R + 7), [c, d] = pt(i / 12, R + (i % 4 ? 9.5 : 12));
      ticks += `<line x1="${a.toFixed(1)}" y1="${b.toFixed(1)}" x2="${c.toFixed(1)}" y2="${d.toFixed(1)}"/>`;
    }
    const tone = over ? 'red' : f >= 200 / max ? 'teal' : 'white';
    return `<svg viewBox="-6 -6 112 104" class="iv-gsvg">
      <path class="trk" d="${arc(0, 1)}"/>
      <path class="band" d="${arc(200 / max, 0.97)}"/>
      <path class="over" d="${arc(0.97, 1)}"/>
      ${f > 0.004 ? `<path class="fill ${tone}" d="${arc(0, Math.max(f, 0.006))}"/>` : ''}
      <g class="ticks">${ticks}</g>
    </svg>`;
  }

  function renderControls() {
    const box = S.q('.iv-ctl');
    const inf = onHook(S.sel);
    const running = inf && !inf.done;
    box.classList.toggle('off', !running);
    if (!box.dataset.built) {
      box.dataset.built = '1';
      box.innerHTML = `
        <div class="row clampr"><div class="lbl"><span>${esc(T('ctl_clamp', 'Roller clamp'))}</span><kbd class="kq"></kbd><kbd class="ke"></kbd></div><div class="sl"></div></div>
        <div class="row inf">
          <div class="gauge"><div class="g"></div><div class="gc"><div class="gl">${esc(T('ctl_bag', 'Bag'))}</div><div class="gd"></div><div class="gu">mmHg</div></div></div>
          <div class="side">
            <div class="lbl"><span>${esc(T('ctl_pressure', 'Pressure infuser'))}</span></div>
            <button class="iv-squeeze"><kbd class="ks"></kbd><span>${esc(T('ctl_squeeze', 'Pump'))}</span></button>
            <div class="flow"><span>${esc(T('ctl_rate', 'Flow'))}</span><b class="fr">0</b><i>mL/min</i></div>
            <div class="eta"></div>
          </div>
        </div>`;
      S.slider = NZA.ui.Slider(box.querySelector('.sl'), { min: 0, max: 100, step: 1, value: 66, format: v => `${v}%`, onChange: v => { const i = onHook(S.sel); if (i && !i.done) { bagState(i).clamp = v / 100; } } });
      S.flipP = NZA.ui.FlipClock(box.querySelector('.gd'), { value: '000', small: true });
      const sq = box.querySelector('.iv-squeeze');
      sq.addEventListener('mousedown', (e) => { e.preventDefault(); squeeze(); });
    }
    box.querySelector('.kq').textContent = keyCap(S.keys.clampDown);
    box.querySelector('.ke').textContent = keyCap(S.keys.clampUp);
    box.querySelector('.ks').textContent = keyCap(S.keys.squeeze);
    if (running) S.slider.set(Math.round(bagState(inf).clamp * 100));
    tickControls(true);
  }

  function tickControls(force) {
    const box = S.q('.iv-ctl');
    const inf = onHook(S.sel);
    const running = inf && !inf.done;
    const b = running ? bagState(inf) : { p: 0, clamp: 0 };
    const p = Math.round(b.p);
    if (force || S.lastP !== p) {
      S.lastP = p;
      box.querySelector('.g').innerHTML = gaugeSVG(b.p);
      S.flipP.set(String(clamp(p, 0, 999)).padStart(3, '0'));
      S.flipP.tone(b.p > (S.cfg.maxPressure || 300) * 0.97 ? 'red' : b.p >= 200 ? 'teal' : '');
    }
    const rate = running && !inf.paused ? rateOf(inf) : 0;
    box.querySelector('.fr').textContent = rate.toFixed(0);
    const left = running ? Math.max(0, b.left ?? inf.left ?? 0) : 0;
    const eta = rate > 0.5 ? left / rate * 60 : 0;
    box.querySelector('.eta').innerHTML = running ? (inf.paused ? `<span class="t-amber">${esc(T('eta_paused', 'Paused · no line'))}</span>` : rate > 0.5 ? `${esc(T('eta', 'Empty in'))} <b>${NZA.fmt.time(eta)}</b>` : esc(T('eta_closed', 'Clamp closed'))) : esc(T('eta_none', 'Select a running bag'));
  }

  function renderTxa() {
    const box = S.q('.iv-txa');
    const inv = (S.data && S.data.inventory) || {};
    const p = patient();
    const given = S.data && S.data.patient && S.data.patient.txaActive;
    const t = S.txa;
    const state = t.done || given ? 'given' : (inv.txa || 0) < 1 ? 'none' : t.holding ? 'push' : '';
    const prog = given && !t.prog ? 1 : t.prog;
    box.className = `iv-txa ${state}`;
    const RING = 2 * Math.PI * 14;
    box.innerHTML = `
      <div class="tr"><svg viewBox="0 0 36 36"><circle class="bg" cx="18" cy="18" r="14"/><circle class="fg ${t.fast ? 'amber' : ''}" cx="18" cy="18" r="14" stroke-dasharray="${RING.toFixed(1)}" stroke-dashoffset="${(RING * (1 - prog)).toFixed(1)}"/></svg><span class="ti">${icon('syringe')}</span></div>
      <div class="tb"><b>${esc(T('txa_title', 'TXA 1 g'))}<em class="tv">${(prog * 1).toFixed(1)} g</em></b>
        <span>${state === 'given' ? esc(T('txa_given', 'Given · helps clots hold for an hour')) : state === 'none' ? esc(T('txa_none', 'No TXA in your bag')) : NZA.rich(F(T('txa_hint', 'Hold {%s} · slow push, %s s'), keyCap(S.keys.txa), S.cfg.txaPush || 10))}</span></div>
      <button class="iv-mini hold" data-a="txa" ${state === 'given' || state === 'none' ? 'disabled' : ''}><kbd>${esc(keyCap(S.keys.txa))}</kbd>${esc(T('txa_btn', 'Hold'))}</button>`;
    const btn = box.querySelector('.hold');
    if (btn && !btn.disabled) {
      btn.addEventListener('mousedown', (e) => { e.preventDefault(); txaHold(true, e.shiftKey); });
    }
    void p;
  }

  function alerts() {
    const out = [];
    const p = patient(), inf = infusions(), acc = access();
    if (p.reaction && p.reaction.stage) {
      const st = p.reaction.stage;
      out.push({ tone: 'red', icon: 'alert', title: T('al_reaction', 'Transfusion reaction'), text: T('al_reaction_' + st, ['Fever and chills. Stop the blood and run saline.', 'Back pain and falling pressure. Stop the transfusion now.', 'Haemolysis - the patient is crashing. Stop the blood, run saline.'][st - 1] || ''), btn: ['stopblood', T('btn_stop_blood', 'Stop blood')] });
    }
    if (!acc && S.cfg.requireAccess) out.push({ tone: 'red', icon: 'iv', title: T('al_noaccess', 'Place an IV first'), text: T('al_noaccess_t', 'Bags cannot run without an IV or IO line.'), btn: ['iv', T('btn_place_iv', 'Place IV')] });
    if (inf.some(i => i.paused)) out.push({ tone: 'amber', icon: 'iv', title: T('al_paused', 'Infusion paused'), text: T('al_paused_t', 'The line is out. Place a new IV to continue.') });
    if (!p.typed && inf.some(i => i.kind === 'blood' && !i.done && i.bag && i.bag.type !== 'O-')) out.push({ tone: 'amber', icon: 'bloodbag', title: T('al_untyped', 'Group unknown'), text: T('al_untyped_t', 'Only O− is safe until you run Type & screen.'), btn: S.cfg.typeScreen && (S.data.perms || {}).type ? ['type', T('btn_type', 'Type & screen')] : null });
    if ((p.given && p.given.saline > (S.cfg.dilution || 1000))) out.push({ tone: 'amber', icon: 'drop', title: T('al_dilution', 'Over 1 L of saline'), text: T('al_dilution_t', 'The blood gets thin - hang red cells instead.') });
    return out;
  }

  function renderAlerts() {
    const list = alerts();
    S.q('.iv-alerts').innerHTML = list.map(a => `
      <div class="iv-note ${a.tone}"><span class="ni">${icon(a.icon)}</span><div class="nt"><b>${esc(a.title)}</b><p>${esc(a.text)}</p></div>${a.btn ? `<button class="iv-mini ${a.tone}" data-a="${esc(a.btn[0])}">${esc(a.btn[1])}</button>` : ''}</div>`).join('');
    S.q('.iv-alerts').style.display = list.length ? '' : 'none';
  }

  function renderKeys() {
    const k = S.keys;
    S.q('.iv-keys').innerHTML = [
      [[keyCap(k.squeeze)], T('k_squeeze', 'pump')], [[keyCap(k.clampDown), keyCap(k.clampUp)], T('k_clamp', 'clamp')],
      [[keyCap(k.txa)], T('k_txa', 'TXA')], [[keyCap(k.hookA), keyCap(k.hookB)], T('k_hook', 'hook')], [['ESC'], T('close', 'Close')],
    ].map(([ks, l]) => `<span>${ks.map(x => `<kbd>${esc(x)}</kbd>`).join('')}<em>${esc(l)}</em></span>`).join('');
  }

  // the printed label of the selected blood unit, beside the panel (with the crossmatch)
  function renderFlyout() {
    const box = S.q('.iv-flyout');
    const inf = onHook(S.sel);
    if (!inf || inf.kind !== 'blood' || !inf.bag || !BB().labelHTML) { box.innerHTML = ''; box.classList.remove('on'); return; }
    const p = patient();
    let cross;
    if (inf.incompatible) cross = { state: 'bad', text: F(T('cross_bad', 'INCOMPATIBLE with %s - stop it'), fmtType(p.bloodType || '?')) };
    else if (p.typed && p.bloodType) cross = { state: 'ok', text: F(T('cross_ok', 'Compatible with %s %s'), p.name ? p.name.split(' ')[0] : '', fmtType(p.bloodType)) };
    else if (inf.bag.type === 'O-') cross = { state: 'ok', text: T('cross_oneg', 'O− · safe for every group') };
    else cross = { state: 'unknown', text: T('cross_unknown', 'Patient not typed - risk of reaction') };
    const key = `${inf.id}:${cross.state}`;
    if (box.dataset.key === key) return;
    box.dataset.key = key;
    box.innerHTML = BB().labelHTML(Object.assign({ product: T('product', 'Red cells in SAG-M'), ml: inf.bag.ml || inf.ml }, inf.bag), { small: true, cross, now: S.now });
    box.classList.add('on');
  }

  /* ═══════════════════════════ PICKER ═══════════════════════════ */

  function openPicker(h) {
    if (S.cfg.requireAccess && !access() && !S.data.easy) { NZA.toast({ title: T('stand_title', 'IV stand'), message: T('al_noaccess', 'Place an IV first'), type: 'error' }); return; }
    S.picker = h; S.sel = h;
    renderPicker(); renderHooks(); renderControls(); renderFlyout();
  }
  function closePicker() { S.picker = null; const pk = S.q('.iv-pick'); pk.classList.remove('on'); pk.innerHTML = ''; }

  function renderPicker() {
    const pk = S.q('.iv-pick');
    const d = S.data || {}, inv = d.inventory || {}, p = patient();
    const perms = d.perms || {};
    const hookName = S.picker === 1 ? T('hook_a', 'Hook A') : T('hook_b', 'Hook B');
    const bags = inv.bags || [];
    const compat = (b) => {
      if (b.expired) return ['red', T('c_expired', 'Expired')];
      if (b.type === 'O-') return ['teal', T('c_universal', 'Universal')];
      if (!p.typed) return ['amber', T('c_unknown', 'Not typed')];
      return b.compatible ? ['teal', T('c_ok', 'Compatible')] : ['red', T('c_bad', 'Incompatible')];
    };
    const rel = BB().relDays || (() => '');
    pk.innerHTML = `
      <div class="pk-hd"><div><div class="nza-label">${esc(F(T('pk_tag', 'Hang on %s'), hookName))}</div><div class="nza-h">${esc(T('pk_title', 'Choose a bag'))}</div></div><button class="iv-x" data-pk="close">${icon('x')}</button></div>
      <div class="pk-body nza-scroll">
        <div class="pk-sec">${esc(T('pk_fluids', 'Fluids'))}</div>
        <button class="pk-row ${inv.saline > 0 ? '' : 'dis'}" data-pk="saline" ${inv.saline > 0 ? '' : 'disabled'}>
          <span class="pk-ico sal">${(BB().bagSVG || (() => ''))({ fill: 1, kind: 'saline', w: 26, h: 38 })}</span>
          <span class="pk-t"><b>${esc(T('bag_saline_t', 'Saline 0.9%'))} · ${S.cfg.salineMl || 500} mL</b><small>${esc(T('pk_saline_sub', 'Crystalloid · buys time, does not carry oxygen'))}</small></span>
          <span class="pk-n">×${inv.saline || 0}</span>
        </button>
        <div class="pk-sec">${esc(T('pk_blood', 'Blood units'))}${p.typed && p.bloodType ? `<span class="pk-pt">${esc(F(T('pk_patient', 'Patient %s'), fmtType(p.bloodType)))}</span>` : `<span class="pk-pt amber">${esc(T('pk_patient_unknown', 'Patient not typed'))}</span>`}</div>
        ${!perms.blood ? `<div class="pk-empty">${esc(T('pk_noperm', 'You are not cleared to give blood products.'))}</div>` : bags.length ? bags.map(b => { const c = compat(b); return `
          <button class="pk-row ${b.expired ? 'dis' : ''}" data-pk="blood" data-serial="${esc(b.serial || '')}" data-slot="${esc(b.slot ?? '')}" ${b.expired ? 'disabled' : ''}>
            <span class="pk-abo ${/-/.test(b.type) ? 'neg' : ''}">${esc(fmtType(b.type))}</span>
            <span class="pk-t"><b>${esc(F(T('bag_blood_t', '%s red cells'), fmtType(b.type)))} · ${esc(b.ml)} mL</b><small>${esc(b.serial || '--')} · ${esc(b.expired ? T('c_expired', 'Expired') : F(T('pk_exp', 'expires %s'), rel(b.expires, S.now)))}</small></span>
            <span class="iv-chip ${c[0]}">${esc(c[1])}</span>
          </button>`; }).join('') : `<div class="pk-empty">${esc(T('pk_noblood', 'You carry no blood units. A blood bank issues them.'))}</div>`}
        ${d.bay && perms.blood ? `<div class="pk-sec">${esc(T('pk_fridge', 'Ambulance fridge'))}</div>
          ${Object.keys(d.bay.stock || {}).map(t => { const n = d.bay.stock[t]; const can = n > 0 && (!d.bay.needEmpty || (inv.empty || 0) > 0); return `
          <div class="pk-row fridge"><span class="pk-abo ${/-/.test(t) ? 'neg' : ''}">${esc(fmtType(t))}</span>
            <span class="pk-t"><b>${esc(F(T('pk_fridge_t', '%s onboard units'), n))}</b><small>${esc(d.bay.needEmpty ? F(T('pk_fridge_sub', 'Fills one of your empty bags (%s)'), inv.empty || 0) : T('pk_fridge_sub2', 'Labelled and handed to you'))}</small></span>
            <button class="iv-mini teal" data-pk="fill" data-type="${esc(t)}" ${can ? '' : 'disabled'}>${esc(T('btn_fill', 'Bag a unit'))}</button></div>`; }).join('')}` : ''}
      </div>`;
    pk.classList.add('on');
    pk.onclick = onPickClick;
  }

  async function onPickClick(e) {
    const b = e.target.closest('[data-pk]');
    if (!b || b.disabled) return;
    const a = b.dataset.pk;
    if (a === 'close') return closePicker();
    if (a === 'saline') return hang('saline', null);
    if (a === 'blood') {
      const bag = ((S.data.inventory || {}).bags || []).find(x => (b.dataset.serial && x.serial === b.dataset.serial) || String(x.slot) === b.dataset.slot);
      if (bag) return hang('blood', bag);
    }
    if (a === 'fill') {
      if (S.busy) return;
      S.busy = true;
      const res = await NZA.post(`${APP}:fill`, { type: b.dataset.type });
      S.busy = false;
      if (res && res.ok && !NZA.inGame) NZA.toast({ title: T('stand_title', 'IV stand'), message: res.msg || 'Filled' });
    }
  }

  function confirmBlood(bag, onYes) {
    const p = patient();
    if (p.typed && bag.compatible === false) {
      const actions = [{ label: T('cancel', 'Cancel'), kind: 'line' }];
      if (S.cfg.allowIncompatible) actions.push({ label: T('hang_anyway', 'Hang anyway'), kind: 'red', onClick: () => onYes(true) });
      NZA.ui.Modal({ title: T('m_bad_title', 'Incompatible unit'), text: F(T('m_bad_text', '**%s** blood into a **%s** patient causes a haemolytic transfusion reaction: fever, back pain, collapse.'), fmtType(bag.type), fmtType(p.bloodType)), icon: 'alert', tone: 'red', actions, host: S.el });
      return;
    }
    if (!p.typed && bag.type !== 'O-') {
      const actions = [{ label: T('cancel', 'Cancel'), kind: 'line' }, { label: T('hang_anyway', 'Hang anyway'), kind: 'red', onClick: () => onYes(true) }];
      if (S.cfg.typeScreen && (S.data.perms || {}).type) actions.splice(1, 0, { label: T('btn_type', 'Type & screen'), kind: 'teal', onClick: () => { closePicker(); act('type'); } });
      NZA.ui.Modal({ title: T('m_unknown_title', 'Blood group not known'), text: F(T('m_unknown_text', 'Only **O−** is safe without Type & screen. A **%s** unit may not match this patient.'), fmtType(bag.type)), icon: 'alert', tone: 'red', actions, host: S.el });
      return;
    }
    onYes(false);
  }

  async function hang(kind, bag, force = false) {
    if (S.busy) return;
    if (kind === 'blood' && !force) return confirmBlood(bag, (f) => hang(kind, bag, f || true));
    S.busy = true;
    S.wrap.classList.add('busy');
    const rate = Math.round((S.cfg.gravity || 32) * 0.66);
    const res = await NZA.post(`${APP}:hang`, { kind, serial: bag && bag.serial, slot: bag && bag.slot, type: bag && bag.type, force: !!force, rate, hook: S.picker || S.sel });
    S.busy = false;
    if (!S.on) return;
    S.wrap.classList.remove('busy');
    if (res && res.ok) {
      const r = res.result || {};
      if (r.id) S.bags[r.id] = { clamp: 0.66, p: 0, sent: rate, sentAt: performance.now(), left: r.left ?? r.ml, leftAt: performance.now(), srvLeft: r.left ?? r.ml };
      closePicker();
      NZA.audio.click(700);
    } else if (res && res.err === 'incompatible') {
      confirmBlood(Object.assign({}, bag, { compatible: false }), (f) => hang(kind, bag, f || true));
    } else if (res) {
      NZA.toast({ title: T('stand_title', 'IV stand'), message: res.msg || T('err_failed', 'That did not work.'), type: 'error' });
    }
  }

  /* ═══════════════════════════ ACTIONS ═══════════════════════════ */

  function onHooksClick(e) {
    const down = e.target.closest('[data-down]');
    if (down) { takedown(down.dataset.down); return; }
    const card = e.target.closest('.iv-hook');
    if (!card) return;
    const h = Number(card.dataset.hook);
    if (card.classList.contains('empty')) return openPicker(h);
    selectHook(h);
  }

  function selectHook(h) {
    if (h > (S.cfg.maxBags || 2)) return;
    S.sel = h;
    if (S.picker) closePicker();
    renderHooks(); renderControls(); renderFlyout();
  }

  async function takedown(id) {
    if (S.busy) return;
    S.busy = true;
    const res = await NZA.post(`${APP}:takedown`, { id });
    S.busy = false;
    if (res && res.ok) { delete S.bags[id]; NZA.audio.click(420); }
    else if (res && res.msg) NZA.toast({ title: T('stand_title', 'IV stand'), message: res.msg, type: 'error' });
  }

  function onAlertClick(e) {
    const b = e.target.closest('[data-a]');
    if (!b || b.disabled) return;
    act(b.dataset.a);
  }

  async function act(a) {
    if (a === 'type') {
      const res = await NZA.post(`${APP}:type`, {});
      if (res && res.ok && !NZA.inGame) { S.data.patient.typed = true; S.data.patient.bloodType = res.bloodType || 'A+'; renderAll(); }
    } else if (a === 'iv') {
      NZA.post(`${APP}:iv`, {});
    } else if (a === 'stopblood') {
      const list = infusions().filter(i => i.kind === 'blood' && !i.done && (i.incompatible || !patient().typed));
      for (const i of (list.length ? list : infusions().filter(x => x.kind === 'blood' && !x.done))) await takedown(i.id);
    }
  }

  function squeeze() {
    const inf = onHook(S.sel);
    if (!inf || inf.done) return;
    const b = bagState(inf);
    const max = S.cfg.maxPressure || 300;
    b.p = Math.min(max * 1.1, b.p + (S.cfg.pump || 24));
    NZA.audio.noise(120, { vol: 0.05, lp: 700, hp: 200, attack: 0.1, release: 0.6 });
    const btn = S.q('.iv-squeeze');
    if (btn) { btn.classList.remove('hit'); void btn.offsetWidth; btn.classList.add('hit'); }
    if (b.p > max) NZA.toast({ title: T('ctl_pressure', 'Pressure infuser'), message: T('over_pressure', 'Over 300 mmHg - the bag could burst. Let it settle.'), type: 'warning', duration: 2500 });
    tickControls();
  }

  function txaHold(on, fast) {
    const t = S.txa;
    const inv = (S.data && S.data.inventory) || {};
    if (on) {
      if (t.done || t.sent || (inv.txa || 0) < 1 || (S.data.patient && S.data.patient.txaActive)) return;
      if (S.cfg.requireAccess && !access()) { NZA.toast({ title: T('txa_title', 'TXA 1 g'), message: T('al_noaccess', 'Place an IV first'), type: 'error' }); return; }
      if (!t.holding) { t.holding = true; t.fastMode = !!fast; if (!t.t0) t.t0 = performance.now(); }
    } else t.holding = false;
    renderTxa();
  }

  async function txaDone() {
    const t = S.txa;
    t.sent = true; t.holding = false;
    const secs = (performance.now() - (t.t0 || performance.now())) / 1000;
    const res = await NZA.post(`${APP}:txa`, { seconds: Math.round(secs * 10) / 10 });
    if (res && res.ok) { t.done = true; NZA.audio.success(); }
    else { t.sent = false; t.prog = 0; t.t0 = 0; if (res && res.msg) NZA.toast({ title: T('txa_title', 'TXA 1 g'), message: res.msg, type: 'error' }); }
    renderTxa();
  }

  /* ═══════════════════════════ LOOP ═══════════════════════════ */

  function loop(now) {
    if (!S.on) return;
    const dt = Math.min(0.1, (now - S.last) / 1000);
    S.last = now;
    const max = S.cfg.maxPressure || 300;
    const leak = S.cfg.leak || 5;
    for (const inf of infusions()) {
      if (inf.done) continue;
      const b = bagState(inf);
      if (b.p > 0) b.p = Math.max(0, b.p - leak * dt * (b.p > max ? 3 : 1));
      const rate = inf.paused ? 0 : rateOf(inf);
      b.left = Math.max(0, (b.left ?? inf.left ?? 0) - rate / 60 * dt);
      if ((Math.abs(rate - b.sent) >= 1 || (rate < 0.2 && b.sent >= 0.2)) && now - b.sentAt > 650 && !inf.paused) {
        b.sent = rate; b.sentAt = now;
        NZA.post(`${APP}:rate`, { id: inf.id, rate: Math.round(rate * 10) / 10 });
      }
    }
    // TXA push
    const t = S.txa;
    if (t.holding && !t.done && !t.sent) {
      const push = S.cfg.txaPush || 10;
      t.prog = Math.min(1, t.prog + dt / push * (t.fastMode ? 2.5 : 1));
      if (t.fastMode && !t.fast) { t.fast = true; NZA.toast({ title: T('txa_title', 'TXA 1 g'), message: T('txa_fast', 'Too fast - a quick push drops the pressure.'), type: 'warning', duration: 2500 }); }
      if (t.prog >= 1) txaDone();
    }
    if (now - (S.uiAt || 0) > 60) {
      S.uiAt = now;
      tickControls();
      if (t.holding) renderTxaProgress();
      if (now - (S.hookAt || 0) > 500) { S.hookAt = now; patchHooks(); }
    }
    S.raf = requestAnimationFrame(loop);
  }

  function renderTxaProgress() {
    const box = S.q('.iv-txa');
    const fg = box.querySelector('.fg');
    const RING = 2 * Math.PI * 14;
    if (fg) { fg.setAttribute('stroke-dashoffset', (RING * (1 - S.txa.prog)).toFixed(1)); fg.classList.toggle('amber', !!S.txa.fast); }
    const v = box.querySelector('.tv');
    if (v) v.textContent = `${S.txa.prog.toFixed(1)} g`;
    box.classList.toggle('push', S.txa.holding);
  }

  // live numbers on the hook cards without rebuilding them
  function patchHooks() {
    S.wrap.querySelectorAll('.iv-hook[data-hook]').forEach(card => {
      const inf = onHook(Number(card.dataset.hook));
      if (!inf || inf.done) return;
      const b = bagState(inf), ml = inf.ml || 500;
      const left = Math.max(0, b.left ?? inf.left ?? 0);
      const em = card.querySelector('.lv em');
      if (em) em.innerHTML = `${Math.round(left)}<i>/ ${ml} mL</i>`;
      const rt = card.querySelector('.rt');
      if (rt) rt.innerHTML = `${(inf.paused ? 0 : rateOf(inf)).toFixed(0)}<i>mL/min</i>`;
      const m = card.querySelector('.mtr > i');
      if (m) m.style.width = `${clamp(left / ml, 0, 1) * 100}%`;
      const bag = card.querySelector('.bag');
      const f = Math.round(clamp(left / ml, 0, 1) * 40) / 40;
      if (bag && bag.dataset.f !== String(f)) { bag.dataset.f = String(f); bag.innerHTML = (BB().bagSVG || (() => ''))({ fill: f, kind: inf.kind === 'blood' ? 'blood' : 'saline', type: inf.bag && inf.bag.type, w: 56, h: 80 }); }
    });
  }

  /* ═══════════════════════════ APP ═══════════════════════════ */

  function applySnap(sn) {
    S.snap = sn;
    // server volumes win over the local estimate when they arrive
    (sn.infusions || []).forEach(i => {
      const b = bagState(i);
      if (b.srvLeft !== i.left) { b.srvLeft = i.left; b.left = i.left; }
      if (S.bags[i.id] && i.rate && Math.abs(i.rate - b.sent) > 2 && performance.now() - b.sentAt > 3000) {
        b.clamp = clamp(i.rate / (S.cfg.gravity || 32), 0, 1); b.sent = i.rate;
      }
    });
    renderHead(); renderVitals(); renderAlerts(); renderFlyout();
    const sig = JSON.stringify(infusions().map(i => [i.id, i.hook, !!i.done, !!i.paused, !!i.incompatible]));
    if (sig !== S.sig) { S.sig = sig; renderHooks(); renderControls(); }
  }

  const def = {
    escClose: true,
    camInput: true,
    open(d) {
      Lc = Object.assign({}, d.locale || {});
      this.close();
      Object.assign(S, {
        on: true, data: d.data || {}, snap: null, bay: !!d.bay, sel: 1, picker: null, bags: {}, busy: false,
        cfg: Object.assign({ gravity: 32, maxRate: 160, pressureGain: 1.15, maxPressure: 300, pump: 24, leak: 5, maxBags: 2, txaPush: 10, allowIncompatible: true, requireAccess: true, salineMl: 500, typeScreen: true, dilution: 1000 }, d.cfg || {}),
        keys: Object.assign({ squeeze: 'Space', clampDown: 'KeyQ', clampUp: 'KeyE', txa: 'KeyT', hookA: 'Digit1', hookB: 'Digit2' }, d.keys || {}),
        txa: { prog: 0, holding: false, done: false, sent: false, fast: false, t0: 0 },
        now: d.now || (d.data && d.data.now) || Math.floor(Date.now() / 1000), last: performance.now(),
      });
      const first = infusions().find(i => !i.done);
      if (first) S.sel = first.hook;
      Object.values(S.keys).forEach(code => {
        if (!def.keys[code]) def.keys[code] = (e) => keyDown(e);
        if (!def.keysUp[code]) def.keysUp[code] = (e) => keyUp(e);
      });
      build(this.el);
      S.sig = JSON.stringify(infusions().map(i => [i.id, i.hook, !!i.done, !!i.paused, !!i.incompatible]));
      S.raf = requestAnimationFrame(loop);
    },
    close() {
      if (S.raf) cancelAnimationFrame(S.raf);
      Object.keys(S).forEach(k => delete S[k]);
      S.on = false;
      this.el.innerHTML = '';
    },
    msg: {
      data(d) {
        if (!S.on || !d) return;
        S.data = d;
        if (d.now) S.now = d.now;
        const sig = JSON.stringify(infusions().map(i => [i.id, i.hook, !!i.done, !!i.paused, !!i.incompatible]));
        if (sig !== S.sig) { S.sig = sig; }
        if (!onHook(S.sel) && !S.picker) { const f = infusions().find(i => !i.done); if (f) S.sel = f.hook; }
        renderAll();
      },
      snap(sn) { if (S.on && sn) applySnap(sn); },
    },
    keys: {
      Escape() {
        if (!S.on) return false;
        if (S.el.querySelector('.nza-modal-wrap')) { S.el.querySelector('.nza-modal-wrap').remove(); return true; }
        if (S.picker) { closePicker(); return true; }
        return false;
      },
      ' '(e) { return keyDown(e); },
    },
    keysUp: {
      ' '(e) { return keyUp(e); },
    },
    preview() { previewRun(new URLSearchParams(location.search).get('state') || ''); },
  };

  function codeOf(e) { return e.code || (e.key === ' ' ? 'Space' : e.key); }
  function keyDown(e) {
    if (!S.on || S.el.querySelector('.nza-modal-wrap')) return false;
    const c = codeOf(e), k = S.keys;
    if (c === k.squeeze) { if (!e.repeat) squeeze(); return true; }
    if (c === k.clampDown || c === k.clampUp) {
      const inf = onHook(S.sel);
      if (inf && !inf.done) {
        const b = bagState(inf);
        b.clamp = clamp(b.clamp + (c === k.clampUp ? 0.05 : -0.05), 0, 1);
        S.slider.set(Math.round(b.clamp * 100));
        NZA.audio.tick();
      }
      return true;
    }
    if (c === k.txa) { if (!e.repeat) txaHold(true, e.shiftKey); return true; }
    if (c === k.hookA) { selectHook(1); return true; }
    if (c === k.hookB) { selectHook(2); return true; }
    return false;
  }
  function keyUp(e) {
    if (!S.on) return false;
    const c = codeOf(e);
    if (c === S.keys.txa) { txaHold(false); return true; }
    return false;
  }
  window.addEventListener('mouseup', () => { if (S.on && S.txa && S.txa.holding) txaHold(false); });

  NZA.app(APP, def);

  /* ═══════════════════════════ PREVIEW ═══════════════════════════ */

  const NOW = 1792000000, DAY = 86400;
  function demoData(variant) {
    const typed = variant !== 'untyped';
    return {
      patient: { pid: 'p:ABC', name: 'Michael Garcia', state: 'wounded', typed, bloodType: typed ? 'A+' : null, bloodPct: 71, fluid: 420, bleed: 18.4,
        given: { saline: 650, blood: 120, txa: 0 }, txaActive: false, vitals: { hr: 118, sys: 92, dia: 58, map: 69, spo2: 96, temp: 35.9 },
        reaction: variant === 'react' ? { stage: 2, ml: 160 } : null },
      access: variant === 'noline' ? null : { kind: 'iv', site: 'l_lower_arm' },
      infusions: variant === 'noline' ? [] : [
        { id: 'f1', kind: 'saline', ml: 500, left: 312, rate: 38, hook: 1 },
        { id: 'f2', kind: 'blood', ml: 450, left: 380, rate: 24, hook: 2, bag: { type: variant === 'react' ? 'B+' : 'O-', serial: 'BB-482913', donor: 'M. Garcia', created: NOW - 9 * DAY, expires: NOW + 26 * DAY, ml: 450 }, incompatible: variant === 'react' ? true : null },
      ],
      inventory: { saline: 2, txa: 1, empty: 1, ivkit: 2, bags: [
        { slot: 4, serial: 'BB-300918', type: 'O-', ml: 450, donor: 'K. Lee', created: NOW - 3 * DAY, expires: NOW + 32 * DAY, compatible: true },
        { slot: 5, serial: 'BB-730551', type: 'A+', ml: 450, donor: 'J. Chen', created: NOW - 4 * DAY, expires: NOW + 31 * DAY, compatible: typed ? true : null },
        { slot: 6, serial: 'BB-204488', type: 'B+', ml: 450, donor: 'D. Wright', created: NOW - 7 * DAY, expires: NOW + 2 * DAY, compatible: typed ? false : null, soon: true },
        { slot: 7, serial: 'BB-118870', type: 'AB-', ml: 450, donor: 'City donor', created: NOW - 36 * DAY, expires: NOW - DAY, expired: true },
      ] },
      bay: { stock: { 'O-': 2 }, needEmpty: true }, perms: { iv: true, blood: true, type: true }, easy: false, warm: true, now: NOW,
    };
  }
  function previewRun(variant) {
    NZA.mock(`${APP}:hang`, (q) => ({ ok: true, result: { id: 'f' + Math.floor(Math.random() * 999), kind: q.kind, ml: q.kind === 'blood' ? 450 : 500, left: q.kind === 'blood' ? 450 : 500, rate: q.rate, hook: q.hook } }));
    NZA.mock(`${APP}:takedown`, () => ({ ok: true }));
    NZA.mock(`${APP}:txa`, () => ({ ok: true }));
    NZA.mock(`${APP}:type`, () => ({ ok: true, bloodType: 'A+' }));
    NZA.mock(`${APP}:fill`, () => ({ ok: true, msg: 'Filled an O− unit' }));
    NZA.demo(APP, {
      locale: {}, bay: variant !== 'field', data: demoData(variant), now: NOW,
      keys: { squeeze: 'Space', clampDown: 'KeyQ', clampUp: 'KeyE', txa: 'KeyT', hookA: 'Digit1', hookB: 'Digit2' },
      cfg: { gravity: 32, maxRate: 160, pressureGain: 1.15, maxPressure: 300, pump: 24, leak: 5, maxBags: 2, txaPush: 10, allowIncompatible: true, requireAccess: true, salineMl: 500, typeScreen: true, bagSize: 500 },
    });
    if (variant === 'react') { S.sel = 2; renderAll(); }
  }

  // screenshot / QA helper
  def._demo = function (state) {
    if (!S.on) return;
    if (state === 'squeeze') { for (let i = 0; i < 9; i++) squeeze(); const inf = onHook(S.sel); if (inf) { bagState(inf).clamp = 0.8; S.slider.set(80); } S.txa.prog = 0.4; S.txa.holding = true; renderTxa(); S.txa.holding = false; }
    else if (state === 'picker') openPicker(2);
    else if (state === 'sel2') selectHook(2);
  };
})();
