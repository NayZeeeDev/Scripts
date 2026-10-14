/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · app 'bed'
   mode 'ai'   cinematic AI doctor treatment: letterbox, step timeline with timers,
               live bedside monitor (NZA.vitals.Monitor), bill with insurance cover,
               doctor subtitles, completion summary.
   mode 'rest' bed rest HUD: rest timer, healing ×4, recovery per injury, get-up key.

   Lua → JS   open { mode, session | point/bed/how, keys { getUp, hospitalGetUp, cam, hold }, cinematic, locale, clock }
              step { index, elapsed } · vitals {…} · done { bill, paid, amount, unpaid, msg }
              hold { p 0..1 } · cam { on } · rest { … } · abort {}
   JS → Lua   bed:hidden
   ═══════════════════════════════════════════════════════════ */
(() => {
  const esc = NZA.esc, icon = NZA.icon;
  let L = {};
  const tr = (k, f) => (L[k] !== undefined && L[k] !== '' ? L[k] : f);
  const fmtS = (s, ...a) => { let i = 0; return String(s).replace(/%[sd]/g, () => (a[i] !== undefined ? a[i++] : '')); };
  const pad = n => String(Math.max(0, Math.floor(n))).padStart(2, '0');
  const mmss = s => { s = Math.max(0, Math.ceil(s || 0)); return `${pad(s / 60)}:${pad(s % 60)}`; };
  const money = n => `$${Math.round(Number(n) || 0).toLocaleString('en-US')}`;
  const STEP_ICON = { assess: 'stetho', resus: 'heart', transfusion: 'bloodbag', discharge: 'check', gunshot: 'crosshair', shrapnel: 'burst', stab: 'knife', laceration: 'cut', abrasion: 'scrape', contusion: 'bruise', fracture: 'bone', burn: 'flame', internal: 'scalpel' };
  const LINES = {
    assess: "Let's have a look at you. Breathe normally for me.",
    resus: 'Stay with me — oxygen on, push the adrenaline.',
    transfusion: "You've lost a lot of blood. Hanging a unit now.",
    gunshot: 'Found the bullet. Hold still while I take it out.',
    shrapnel: 'A few fragments in there. Getting them all out.',
    stab: 'Deep one. Packing it, then I will close it up.',
    laceration: "Numbing it first — you'll only feel a little pressure.",
    abrasion: 'Cleaning the grit out. This might sting.',
    contusion: 'Nasty bruise. Ice and a dressing will do.',
    fracture: 'X-ray shows a clean break. Setting it and putting a cast on.',
    burn: 'Cooling the burn and covering it with a sterile dressing.',
    internal: 'There is a bleed inside. Sealing the vessel now.',
    discharge: "All done. Take it easy for a few days — you're good to go.",
  };

  const S = { el: null, mode: null, ses: null, recv: 0, base: 0, mon: null, flip: null, rflip: null, raf: 0, timer: 0, cam: true, keys: {}, done: false, rest: null, restRecv: 0, lastIdx: -1, sayTimer: 0, hidden: true };

  const elapsed = () => S.base + (performance.now() - S.recv) / 1000;
  function curIndex(t) {
    const steps = (S.ses && S.ses.steps) || [];
    let acc = 0;
    for (let i = 0; i < steps.length; i++) { acc += steps[i].time; if (t < acc) return i; }
    return steps.length - 1;
  }
  function stepStart(i) { let acc = 0; for (let k = 0; k < i; k++) acc += S.ses.steps[k].time; return acc; }

  /* ═══════════════════════ AI DOCTOR ═══════════════════════ */
  function buildAI() {
    const s = S.ses;
    const root = S.el.querySelector('.bd-ai');
    const doc = s.doctor || tr('ai_name', 'Dr. Hale (AI)');
    root.innerHTML = `
      <div class="bd-lb top"></div><div class="bd-lb bot"></div>
      <div class="bd-cap"><span class="l"><span class="nz-mark xs"></span>${esc(s.hospital || '')}</span><span class="c"><i></i>${esc(tr('ai_live', 'Treatment in progress'))}</span><span class="r">${esc(s.ticket || '')} · ${esc(s.bed || '')}</span></div>
      <section class="bd-left nza-hud solid rail">
        <div class="bd-hd">
          <div class="bd-dtile">${icon('stetho')}</div>
          <div class="bd-dn"><small>${esc(tr('ai_label', 'AI doctor · treating you'))}</small><b>${esc(doc)}</b><span>${esc(s.hospital || '')}</span></div>
          <div class="bd-tags"><span class="bd-tag">${icon('ticket')}${esc(s.ticket || '')}</span><span class="bd-tag">${icon('bed')}${esc(s.bed || '')}</span></div>
        </div>
        <div class="bd-ov">
          <div class="bd-ovl"><small>${esc(tr('ai_left', 'Time left'))}</small><div class="bd-flip"></div></div>
          <div class="bd-ovr"><div class="bd-ovtop"><span class="bd-ovpct">0%</span><span class="bd-ovn"></span></div><div class="bd-segs">${s.steps.map(st => `<i style="flex:${st.time}"><b></b></i>`).join('')}</div></div>
        </div>
        <div class="bd-steps nza-scroll">${s.steps.map((st, i) => `
          <div class="bd-step" data-i="${i}">
            <span class="bd-sic">${icon(STEP_ICON[st.key] || st.icon || 'medkit')}</span>
            <div class="bd-stx"><b>${esc(st.label)}</b><span>${esc(st.text || '')}</span><div class="bd-sbar"><i></i></div></div>
            <span class="bd-stm">${mmss(st.time)}</span>
          </div>`).join('')}</div>
      </section>
      <section class="bd-right">
        <div class="dev bd-dev"><div class="bd-devhd"><span class="dev-brand"><span class="nz-mark"></span>NAYZEEE</span><span class="bd-devt">${esc(tr('mon_title', 'Bedside monitor'))}</span><span class="dev-led"></span></div><div class="dev-screen bd-mon"></div></div>
        ${s.bill && s.bill.enabled !== false ? `<div class="bd-bill nza-hud solid">${billHTML(s.bill, false)}</div>` : ''}
      </section>
      <div class="bd-sub"></div>
      <div class="bd-keys"><span class="bd-k" data-k="cam"><kbd>${esc(S.keys.cam || 'C')}</kbd>${esc(tr('k_cam', 'Camera'))}</span><span class="bd-k bd-hold"><span class="bd-ring"><svg viewBox="0 0 30 30"><circle cx="15" cy="15" r="13"/><circle class="p" cx="15" cy="15" r="13"/></svg><kbd>${esc(S.keys.getUp || 'X')}</kbd></span>${esc(tr('k_getup_hold', 'Hold to get up'))}</span></div>
      <div class="bd-donewrap"></div>`;
    S.flip = NZA.ui.FlipClock(root.querySelector('.bd-flip'), { value: '00:00', small: true, tone: 'teal' });
    S.mon = NZA.vitals.Monitor(root.querySelector('.bd-mon'), { traces: ['ecg', 'pleth', 'resp'], height: 168, beep: false, title: (s.name || '').toUpperCase() });
    if (s.vitals) S.mon.update(s.vitals);
    root.classList.toggle('nocam', !S.cam);
  }
  function billHTML(b, final) {
    const lines = (b.lines || []).map(l => `<div class="bd-bl"><span>${esc(l.label)}</span><b>${money(l.amount)}</b></div>`).join('');
    const cover = b.cover > 0 ? `<div class="bd-bl ins"><span>${icon('shield-check')}${esc(b.plan ? fmtS(tr('bill_ins_plan', 'Insurance · %s'), b.plan) : tr('bill_ins', 'Insurance'))} <em>${Math.round(b.cover * 100)}%</em></span><b>−${money(b.coverAmount)}</b></div>` : `<div class="bd-bl noins"><span>${icon('shield')}${esc(tr('bill_noins', 'No insurance'))}</span><b>—</b></div>`;
    return `
      <div class="bd-bhd"><div><small>${esc(final ? tr('bill_final', 'Your bill') : tr('bill_est', 'Estimated bill'))}</small><b>${esc(tr('bill_title', 'Treatment costs'))}</b></div>${icon('receipt')}</div>
      <div class="bd-blines nza-scroll">${lines}</div>
      <div class="bd-bsub"><div class="bd-bl"><span>${esc(tr('bill_sub', 'Subtotal'))}</span><b>${money(b.subtotal)}</b></div>${cover}</div>
      <div class="bd-btot"><span>${esc(tr('bill_total', 'You pay'))}</span><b>${money(b.total)}</b></div>`;
  }
  function say(text) {
    const host = S.el.querySelector('.bd-sub');
    if (!host || !text) return;
    clearTimeout(S.sayTimer);
    host.innerHTML = `<div class="bd-speech"><span class="who">${esc(S.ses.doctor || tr('ai_name', 'Dr. Hale (AI)'))}</span><span class="txt">${esc(text)}</span></div>`;
    S.sayTimer = setTimeout(() => { const sp = host.querySelector('.bd-speech'); if (sp) sp.classList.add('out'); }, Math.max(4200, text.length * 80));
  }
  function frameAI() {
    if (S.mode !== 'ai' || !S.ses) return;
    const s = S.ses, total = s.total || 1;
    const t = S.done ? total : Math.min(total, elapsed());
    const i = S.done ? s.steps.length : curIndex(t);
    const root = S.el.querySelector('.bd-ai');
    if (!root) return;
    if (i !== S.lastIdx) {
      S.lastIdx = i;
      root.querySelectorAll('.bd-step').forEach((row, k) => { row.classList.toggle('done', k < i); row.classList.toggle('cur', k === i); });
      const st = s.steps[i];
      if (st && !S.done) {
        say(tr('line_' + st.key, LINES[st.key] || st.text || ''));
        const row = root.querySelector(`.bd-step[data-i="${i}"]`);
        if (row && row.scrollIntoView) row.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
      }
      root.querySelector('.bd-ovn').textContent = S.done ? tr('ai_complete', 'Complete') : fmtS(tr('ai_stepn', 'Step %d of %d'), Math.min(i + 1, s.steps.length), s.steps.length);
    }
    // per-step bars + timers
    root.querySelectorAll('.bd-step').forEach((row, k) => {
      const st = s.steps[k], a = stepStart(k);
      const p = Math.max(0, Math.min(1, (t - a) / st.time));
      row.querySelector('.bd-sbar i').style.width = `${(k < i ? 1 : k === i ? p : 0) * 100}%`;
      row.querySelector('.bd-stm').textContent = k < i ? '✓' : k === i ? mmss(st.time - (t - a)) : mmss(st.time);
    });
    root.querySelectorAll('.bd-segs i').forEach((seg, k) => {
      const st = s.steps[k], a = stepStart(k);
      const p = Math.max(0, Math.min(1, (t - a) / st.time));
      seg.className = k < i ? 'done' : k === i ? 'cur' : '';
      seg.querySelector('b').style.width = `${p * 100}%`;
    });
    root.querySelector('.bd-ovpct').textContent = `${Math.round((t / total) * 100)}%`;
    S.flip.set(mmss(total - t));
    S.raf = requestAnimationFrame(frameAI);
  }
  function showDone(d) {
    S.done = true;
    const root = S.el.querySelector('.bd-ai');
    if (!root) return;
    root.classList.add('finished');
    const b = d.bill || S.ses.bill || {};
    const steps = (S.ses.steps || []).map(st => `<span class="bd-dchip">${icon(STEP_ICON[st.key] || 'check')}${esc(st.label)}</span>`).join('');
    const paidTxt = b.enabled === false || !b.subtotal ? tr('done_free', 'No charge') : (d.paid ? fmtS(tr('done_paid', '%s paid'), money(d.amount != null ? d.amount : b.total)) : fmtS(tr('done_unpaid', '%s billed to you'), money(d.amount != null ? d.amount : b.total)));
    const secs = Number(S.keys.summary || 9);
    root.querySelector('.bd-donewrap').innerHTML = `
      <div class="bd-done nza-hud solid rail nza-pop">
        <div class="bd-dbadge">${icon('check')}</div>
        <small>${esc(S.ses.ticket || '')} · ${esc(S.ses.bed || '')}</small>
        <h2>${esc(tr('done_title', 'Treatment complete'))}</h2>
        <p>${esc(d.msg || tr('done_p', "You've been patched up. Take it easy for a few days."))}</p>
        <div class="bd-dchips">${steps}</div>
        ${b.enabled === false ? '' : `<div class="bd-dbill">${billHTML(b, true)}</div>`}
        <div class="bd-dpay ${d.paid || b.enabled === false ? 'ok' : 'bad'}">${icon(d.paid || b.enabled === false ? 'check' : 'alert')}<span>${esc(paidTxt)}</span></div>
        <div class="bd-dbar"><i style="animation-duration:${secs}s"></i></div>
        <span class="bd-dleave">${esc(tr('done_leave', 'Standing up…'))}</span>
      </div>`;
    NZA.audio.success();
  }

  /* ═══════════════════════ BED REST ═══════════════════════ */
  function buildRest(d) {
    const root = S.el.querySelector('.bd-rest');
    root.innerHTML = `
      <div class="bd-rp nza-hud solid rail">
        <div class="bd-rtop">
          <div class="bd-rt"><div class="bd-rtile">${icon('bed')}</div><div><small>${esc(tr('rest_title', 'Bed rest'))}</small><b class="bd-rbed">${esc(d.bed || d.label || tr('bed', 'Bed'))}</b><span class="bd-rhosp">${esc(d.hospital || '')}</span></div></div>
          <div class="bd-rsep"></div>
          <div class="bd-rtime"><small>${esc(tr('rest_time', 'Resting'))}</small><div class="bd-rflip"></div></div>
          <div class="bd-rsep"></div>
          <div class="bd-rrec"><div class="bd-rrtop"><small>${esc(tr('rest_recovery', 'Recovery'))}</small><b class="bd-rpct">--%</b></div><div class="mtr lg bd-rmtr"><i style="width:0"></i></div><span class="bd-reta"></span></div>
          <div class="bd-rmult"><b>×<span>4</span></b><small>${esc(tr('rest_heal', 'Healing'))}</small></div>
        </div>
        <div class="bd-rbot"><div class="bd-rinj"></div><div class="bd-rvit"></div><div class="bd-rkey"></div></div>
      </div>`;
    S.rflip = NZA.ui.FlipClock(root.querySelector('.bd-rflip'), { value: '00:00', small: true });
    updateRest(d);
  }
  function updateRest(d) {
    S.rest = Object.assign(S.rest || {}, d);
    if (d.since != null) { S.restBase = d.since; S.restRecv = performance.now(); }
    const r = S.rest, root = S.el.querySelector('.bd-rest');
    if (!root.querySelector('.bd-rp')) return;
    if (r.label) root.querySelector('.bd-rbed').textContent = r.label;
    if (r.hospital) root.querySelector('.bd-rhosp').textContent = r.hospital;
    const rec = r.recovery != null ? Math.max(0, Math.min(100, r.recovery)) : null;
    root.querySelector('.bd-rpct').textContent = rec != null ? `${rec}%` : '--%';
    root.querySelector('.bd-rmtr i').style.width = `${rec || 0}%`;
    const mult = r.mult || 4;
    root.querySelector('.bd-rmult span').textContent = mult;
    root.querySelector('.bd-rmult').classList.toggle('off', mult <= 1);
    root.querySelector('.bd-reta').textContent = (r.injuries && r.injuries.length) ? (r.eta > 0 ? fmtS(tr('rest_eta', 'Fully healed in ~%s'), r.eta >= 3600 ? `${Math.floor(r.eta / 3600)} h ${pad((r.eta % 3600) / 60)} min` : `${Math.max(1, Math.round(r.eta / 60))} min`) : tr('rest_needs', 'Some wounds need treatment before they heal')) : tr('rest_healed', 'Nothing left to heal — you can get up');
    const inj = (r.injuries || []).slice(0, 5).map(i => `<div class="bd-ri ${i.healing ? '' : 'stuck'}"><span class="bd-rii">${icon(STEP_ICON[i.icon] || i.icon || 'medkit')}</span><div><b>${esc(i.short || i.label)}</b><span>${esc(i.region || '')}</span></div><div class="bd-rih"><em>${Math.round(i.heal || 0)}%</em><div class="mtr"><i style="width:${Math.round(i.heal || 0)}%"></i></div></div></div>`).join('');
    const more = (r.injuries || []).length > 5 ? `<span class="bd-rmore">+${r.injuries.length - 5}</span>` : '';
    root.querySelector('.bd-rinj').innerHTML = inj ? inj + more : `<div class="bd-rnone">${icon('check')}${esc(tr('rest_clear', 'No injuries'))}</div>`;
    root.querySelector('.bd-rvit').innerHTML = `<div><small>${esc(tr('rest_blood', 'Blood'))}</small><b class="${(r.blood ?? 100) < 80 ? 't-red' : ''}">${r.blood ?? '--'}%</b></div><div><small>${esc(tr('rest_pain', 'Pain'))}</small><b class="${(r.pain || 0) >= 50 ? 't-amber' : ''}">${r.pain ?? 0}</b></div>`;
    const how = r.how || {};
    root.querySelector('.bd-rkey').innerHTML = how.medic
      ? `<span class="bd-rmed">${icon('user')}${esc(tr('rest_medic', 'A medic will help you off the bed'))}</span>`
      : `<span class="bd-k"><kbd>${esc(how.getUp || S.keys.getUp || 'X')}</kbd>${esc(tr('k_getup', 'Get up'))}</span>`;
  }
  function tickRest() {
    if (S.mode !== 'rest' || !S.rflip) return;
    const secs = (S.restBase || 0) + (performance.now() - (S.restRecv || performance.now())) / 1000;
    S.rflip.set(secs >= 3600 ? `${pad(secs / 3600)}:${pad((secs % 3600) / 60)}` : `${pad(secs / 60)}:${pad(secs % 60)}`);
  }

  /* ═══════════════════════ lifecycle ═══════════════════════ */
  function reset() {
    cancelAnimationFrame(S.raf);
    clearInterval(S.timer);
    clearTimeout(S.sayTimer);
    if (S.mon) { S.mon.destroy(); S.mon = null; }
    S.flip = null; S.rflip = null; S.ses = null; S.done = false; S.lastIdx = -1; S.rest = null;
    S.el.querySelector('.bd-ai').innerHTML = '';
    S.el.querySelector('.bd-rest').innerHTML = '';
    S.el.classList.remove('m-ai', 'm-rest');
    document.body.classList.remove('nza-bed-ai');
  }

  NZA.app('bed', {
    escClose: false,
    init(el) {
      S.el = el;
      el.innerHTML = '<div class="bd-ai"></div><div class="bd-rest"></div>';
    },
    open(d) {
      if (d.locale) L = Object.assign(L, d.locale);
      if (d.keys) S.keys = Object.assign(S.keys, d.keys);
      reset();
      S.mode = d.mode === 'ai' ? 'ai' : 'rest';
      S.el.classList.add(S.mode === 'ai' ? 'm-ai' : 'm-rest');
      if (S.mode === 'ai' && d.session) {
        S.ses = d.session;
        S.base = Number(d.session.elapsed) || 0; S.recv = performance.now();
        S.cam = d.cinematic !== false;
        document.body.classList.add('nza-bed-ai');
        buildAI();
        S.raf = requestAnimationFrame(frameAI);
      } else {
        S.restBase = Number(d.since) || 0; S.restRecv = performance.now();
        buildRest({ bed: d.bed, how: d.how, hospital: d.hospital });
        S.timer = setInterval(tickRest, 500);
        tickRest();
      }
    },
    close() { reset(); S.mode = null; },
    msg: {
      step(d) { if (!S.ses) return; if (d.elapsed != null) { S.base = Number(d.elapsed); S.recv = performance.now(); } },
      vitals(v) { if (S.mon) S.mon.update(v); },
      done(d) { if (S.mode === 'ai') showDone(d || {}); },
      hold(d) {
        const r = S.el.querySelector('.bd-hold');
        if (!r) return;
        const p = Math.max(0, Math.min(1, Number(d.p) || 0));
        r.querySelector('circle.p').style.strokeDashoffset = String(81.7 * (1 - p));
        r.classList.toggle('on', p > 0);
      },
      cam(d) { S.cam = !!d.on; const root = S.el.querySelector('.bd-ai'); if (root) root.classList.toggle('nocam', !S.cam); },
      rest(d) { if (S.mode === 'rest') updateRest(d || {}); },
      abort() { NZA.post('bed:hidden', {}); },
    },

    preview() {
      const p = new URLSearchParams(location.search);
      const view = p.get('view') || 'ai';
      const locale = {};
      if (view === 'rest') {
        NZA.demo('bed', { mode: 'rest', bed: 'Bed 3', hospital: 'Pillbox Medical', since: 252, how: { getUp: 'X', own: true }, keys: { getUp: 'X', cam: 'C', hold: 1.5 }, locale });
        NZA.apps.bed.msg.rest({ ok: true, inBed: true, label: 'Bed 3', hospital: 'Pillbox Medical', mult: 4, recovery: 62, eta: 410, blood: 88, pain: 18, state: 'alive', since: 252, how: { getUp: 'X', own: true },
          injuries: [{ label: 'Gunshot wound', short: 'GSW', icon: 'gunshot', region: 'Abdomen', heal: 41, severity: 3, healing: true }, { label: 'Fracture', short: 'Fracture', icon: 'fracture', region: 'Left lower leg', heal: 58, severity: 2, healing: true }, { label: 'Deep laceration', short: 'Laceration', icon: 'laceration', region: 'Right lower arm', heal: 87, severity: 2, healing: true }, { label: 'Abrasion', short: 'Abrasion', icon: 'abrasion', region: 'Left upper arm', heal: 12, severity: 1, healing: false }] });
        return;
      }
      const steps = [
        { key: 'assess', label: 'Assessment', text: 'Airway, breathing, circulation and your vitals.', time: 8 },
        { key: 'transfusion', label: 'Transfusion (O+)', text: 'A unit of blood to replace what you lost.', time: 14 },
        { key: 'gunshot', label: 'Gunshot wound · Abdomen', text: 'Bullet out, wound packed and closed.', time: 32, region: 'Abdomen', severity: 3 },
        { key: 'fracture', label: 'Fracture · Left lower leg', text: 'X-ray, reduction and a cast.', time: 26, region: 'Left lower leg', severity: 2 },
        { key: 'laceration', label: 'Laceration · Right lower arm', text: 'Numbed, cleaned and stitched.', time: 18, region: 'Right lower arm', severity: 2 },
        { key: 'discharge', label: 'Discharge', text: 'Final check, paperwork and the bill.', time: 8 },
      ];
      const total = steps.reduce((a, s) => a + s.time, 0);
      const bill = { enabled: true, lines: [{ label: 'Consultation & bed', amount: 150 }, { label: 'Transfusion (O+)', amount: 220 }, { label: 'Gunshot wound — Abdomen', amount: 480 }, { label: 'Fracture — Left lower leg', amount: 375 }, { label: 'Deep laceration — Right lower arm', amount: 150 }], subtotal: 1375, cover: 0.6, coverAmount: 825, plan: 'Silver', total: 550 };
      const session = { ticket: 'A-014', bed: 'Bed 3', hospital: 'Pillbox Medical', point: 13, steps, total, elapsed: view === 'done' ? total : 47, index: 3, doctor: 'Dr. Hale (AI)', bill, name: 'Ben Carter',
        vitals: { hr: 104, spo2: 95, sys: 108, dia: 66, map: 80, rr: 19, temp: 36.4, rhythm: 'stach' } };
      NZA.demo('bed', { mode: 'ai', session, cinematic: view !== 'nocam', keys: { getUp: 'X', cam: 'C', hold: 1.5, summary: 9 }, locale });
      if (view === 'hold') setTimeout(() => NZA.apps.bed.msg.hold({ p: 0.6 }), 200);
      if (view === 'done') setTimeout(() => NZA.apps.bed.msg.done({ bill, paid: true, amount: 550, msg: 'Treatment finished. Ticket A-014 closed — take care!' }), 150);
    },
  });
})();
