/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · app 'bed'
   mode 'ai'   cinematic AI doctor treatment: letterbox; care-plan card top-left (progress
               ring around a rolling time-left counter, vertical step spine with a live
               ring on the current node); generic patient monitor + cost card top-right;
               doctor lines through NZA.speech (top-centre voice card); discharge card.
   mode 'rest' bed rest card on the right edge: recovery ring, rolling rest timer,
               instrument list, per-injury healing rings, get-up key.
   No product name or logo on the monitor face (generic model code + labels).

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

  const S = { el: null, mode: null, ses: null, recv: 0, base: 0, mon: null, flip: null, rflip: null, raf: 0, timer: 0, cam: true, keys: {}, done: false, rest: null, restRecv: 0, lastIdx: -1, hidden: true };

  const elapsed = () => S.base + (performance.now() - S.recv) / 1000;
  function curIndex(t) {
    const steps = (S.ses && S.ses.steps) || [];
    let acc = 0;
    for (let i = 0; i < steps.length; i++) { acc += steps[i].time; if (t < acc) return i; }
    return steps.length - 1;
  }
  function stepStart(i) { let acc = 0; for (let k = 0; k < i; k++) acc += S.ses.steps[k].time; return acc; }
  const p2 = n => String(Math.max(0, n)).padStart(2, '0');

  /* ── status ring (SVG in a 100 box; optional tick bezel) ── */
  function ring(p, { r = 42, w = 6, ticks = 0, cls = '' } = {}) {
    const C = 2 * Math.PI * r, off = C * (1 - Math.max(0, Math.min(1, p)));
    let tk = '';
    for (let i = 0; i < ticks; i++) {
      const a = (i / ticks) * Math.PI * 2, big = i % 5 === 0, r1 = 49.5, r2 = big ? 46 : 47.6;
      tk += `<line x1="${(50 + r1 * Math.sin(a)).toFixed(2)}" y1="${(50 - r1 * Math.cos(a)).toFixed(2)}" x2="${(50 + r2 * Math.sin(a)).toFixed(2)}" y2="${(50 - r2 * Math.cos(a)).toFixed(2)}"${big ? ' class="b"' : ''}/>`;
    }
    return `<svg class="bd-rs ${cls}" viewBox="0 0 100 100">${tk ? `<g class="tk">${tk}</g>` : ''}<circle class="tr" cx="50" cy="50" r="${r}" stroke-width="${w}"/><circle class="ar" cx="50" cy="50" r="${r}" stroke-width="${w}" stroke-dasharray="${C.toFixed(2)}" stroke-dashoffset="${off.toFixed(2)}" data-c="${C.toFixed(2)}"/></svg>`;
  }
  function setRing(svg, p) {
    const a = svg && svg.querySelector('.ar');
    if (a) a.style.strokeDashoffset = String(Number(a.dataset.c) * (1 - Math.max(0, Math.min(1, p))));
  }

  /* ═══════════════════════ AI DOCTOR ═══════════════════════ */
  function buildAI() {
    const s = S.ses;
    const root = S.el.querySelector('.bd-ai');
    const doc = s.doctor || tr('ai_name', 'Dr. Hale (AI)');
    const n = s.steps.length;
    root.innerHTML = `
      <div class="bd-lb top"></div><div class="bd-lb bot"></div>
      <div class="bd-cap"><span class="l"><span class="bd-cross">${icon('cross')}</span>${esc(s.hospital || '')}</span><span class="c"><i></i>${esc(tr('ai_live', 'Treatment in progress'))}</span><span class="r">${esc(s.ticket || '')}<em>·</em>${esc(s.bed || '')}</span></div>
      <section class="bd-plan bd-card">
        <div class="bd-ph">
          <div class="bd-pring">${ring(0, { r: 43, w: 5, ticks: 60, cls: 'teal' })}<div class="bd-prc"><div class="bd-flip"></div><small>${esc(tr('ai_left', 'Time left'))}</small></div></div>
          <div class="bd-pid">
            <small>${esc(tr('ai_label', 'AI doctor · on your case'))}</small>
            <b>${esc(doc)}</b>
            <span>${esc(s.hospital || '')}</span>
            <div class="bd-tags"><span class="bd-tag">${icon('ticket')}${esc(s.ticket || '')}</span><span class="bd-tag">${icon('bed')}${esc(s.bed || '')}</span></div>
          </div>
        </div>
        <div class="bd-ilist">
          <div class="bd-irow teal"><span>${esc(tr('ai_progress', 'Progress'))}</span><b class="bd-ovpct">0%</b></div>
          <div class="bd-irow white"><span>${esc(tr('ai_stage', 'Stage'))}</span><b class="bd-ovn"><em>01</em>/${p2(n)}</b></div>
        </div>
        <div class="bd-spine nza-scroll">
          <div class="bd-trk"><i></i></div>
          ${s.steps.map((st, i) => `
          <div class="bd-step" data-i="${i}">
            <span class="bd-node">${ring(0, { r: 40, w: 12, cls: 'node' })}<i></i></span>
            <div class="bd-stx"><div class="bd-stl"><span class="bd-sic">${icon(STEP_ICON[st.key] || st.icon || 'medkit')}</span><b>${esc(st.label)}</b></div><span>${esc(st.text || '')}</span></div>
            <span class="bd-stm">${mmss(st.time)}</span>
          </div>`).join('')}
        </div>
      </section>
      <section class="bd-right">
        <div class="dev bd-dev">
          <div class="bd-devhd"><span class="bd-model">PM-7</span><span class="bd-devt">${esc(tr('mon_title', 'Patient monitor'))}</span><span class="bd-sticker">${esc(tr('mon_adult', 'Adult'))}</span><span class="dev-led"></span></div>
          <div class="dev-screen bd-mon"></div>
          <div class="bd-devft"><span class="bd-grill"></span><span class="bd-plate">PM-7 · 100–240V~ · IPX1</span><span class="bd-btns"><i></i><i></i><i class="r"></i></span></div>
        </div>
        ${s.bill && s.bill.enabled !== false ? `<div class="bd-bill bd-card">${billHTML(s.bill, false)}</div>` : ''}
      </section>
      <div class="bd-keys"><span class="bd-k" data-k="cam"><kbd>${esc(S.keys.cam || 'C')}</kbd>${esc(tr('k_cam', 'Camera'))}</span><span class="bd-k bd-hold"><span class="bd-ring"><svg viewBox="0 0 30 30"><circle cx="15" cy="15" r="13"/><circle class="p" cx="15" cy="15" r="13"/></svg><kbd>${esc(S.keys.getUp || 'X')}</kbd></span>${esc(tr('k_getup_hold', 'Leave the bed (hold)'))}</span></div>
      <div class="bd-donewrap"></div>`;
    S.flip = NZA.ui.FlipClock(root.querySelector('.bd-flip'), { value: '00:00', small: true, tone: 'teal' });
    S.mon = NZA.vitals.Monitor(root.querySelector('.bd-mon'), { traces: ['ecg', 'pleth', 'resp'], height: 168, beep: false, title: (s.name || '').toUpperCase() });
    if (s.vitals) S.mon.update(s.vitals);
    root.classList.toggle('nocam', !S.cam);
  }
  function billHTML(b, final) {
    const lines = (b.lines || []).map(l => `<div class="bd-bl"><span>${esc(l.label)}</span><b>${money(l.amount)}</b></div>`).join('');
    const cover = b.cover > 0 ? `<div class="bd-bl ins"><span>${icon('shield-check')}${esc(b.plan ? fmtS(tr('bill_ins_plan', 'Insurance · %s'), b.plan) : tr('bill_ins', 'Insurance'))} <em>${Math.round(b.cover * 100)}%</em></span><b>−${money(b.coverAmount)}</b></div>` : `<div class="bd-bl noins"><span>${icon('shield')}${esc(tr('bill_noins', 'No insurance'))}</span><b>—</b></div>`;
    const cov = b.subtotal > 0 ? Math.max(0, Math.min(1, (b.coverAmount || 0) / b.subtotal)) : 0;
    return `
      <div class="bd-bhd"><div><small>${esc(final ? tr('bill_final', 'Final costs') : tr('bill_est', 'Running estimate'))}</small><b>${esc(tr('bill_title', 'Care costs'))}</b></div><span class="bd-bcov">${ring(cov, { r: 40, w: 10, cls: 'teal' })}<em>${Math.round(cov * 100)}%</em></span></div>
      <div class="bd-blines nza-scroll">${lines}</div>
      <div class="bd-bsub"><div class="bd-bl"><span>${esc(tr('bill_sub', 'Subtotal'))}</span><b>${money(b.subtotal)}</b></div>${cover}</div>
      <div class="bd-btot"><span>${esc(tr('bill_total', 'Your share'))}</span><b>${money(b.total)}</b></div>`;
  }
  function say(text) {
    if (!text || !S.ses) return;
    NZA.speech({ name: S.ses.doctor || tr('ai_name', 'Dr. Hale (AI)'), role: tr('ai_role', 'AI doctor'), text, ms: Math.max(4200, text.length * 80) });
  }
  function frameAI() {
    if (S.mode !== 'ai' || !S.ses) return;
    const s = S.ses, total = s.total || 1;
    const t = S.done ? total : Math.min(total, elapsed());
    const i = S.done ? s.steps.length : curIndex(t);
    const root = S.el.querySelector('.bd-ai');
    if (!root) return;
    const rows = root.querySelectorAll('.bd-step');
    if (i !== S.lastIdx) {
      S.lastIdx = i;
      rows.forEach((row, k) => { row.classList.toggle('done', k < i); row.classList.toggle('cur', k === i); });
      const st = s.steps[i];
      if (st && !S.done) {
        say(tr('line_' + st.key, LINES[st.key] || st.text || ''));
        const row = root.querySelector(`.bd-step[data-i="${i}"]`);
        if (row && row.scrollIntoView) row.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
      }
      root.querySelector('.bd-ovn').innerHTML = S.done ? esc(tr('ai_complete', 'Complete')) : `<em>${p2(Math.min(i + 1, s.steps.length))}</em>/${p2(s.steps.length)}`;
      // spine fill: up to the centre of the current node
      const trk = root.querySelector('.bd-trk'), cur = rows[Math.min(i, rows.length - 1)];
      if (trk && cur) {
        const top = rows[0].offsetTop + 13, end = S.done ? rows[rows.length - 1].offsetTop + 13 : cur.offsetTop + 13;
        trk.firstChild.style.height = `${Math.max(0, end - top)}px`;
      }
    }
    rows.forEach((row, k) => {
      const st = s.steps[k], a = stepStart(k);
      const p = Math.max(0, Math.min(1, (t - a) / st.time));
      if (k === i) setRing(row.querySelector('.bd-rs'), p);
      row.querySelector('.bd-stm').innerHTML = k < i ? icon('check') : k === i ? mmss(st.time - (t - a)) : mmss(st.time);
    });
    const pct = t / total;
    root.querySelector('.bd-ovpct').textContent = `${Math.round(pct * 100)}%`;
    setRing(root.querySelector('.bd-pring .bd-rs'), pct);
    S.flip.set(mmss(total - t));
    S.raf = requestAnimationFrame(frameAI);
  }
  function showDone(d) {
    S.done = true;
    const root = S.el.querySelector('.bd-ai');
    if (!root) return;
    root.classList.add('finished');
    const b = d.bill || S.ses.bill || {};
    const steps = (S.ses.steps || []).map(st => `<div class="bd-dst"><i>${icon('check')}</i><span>${esc(st.label)}</span><b>${mmss(st.time)}</b></div>`).join('');
    const ok = d.paid || b.enabled === false || !b.subtotal;
    const paidTxt = b.enabled === false || !b.subtotal ? tr('done_free', 'No charge') : (d.paid ? fmtS(tr('done_paid', '%s paid'), money(d.amount != null ? d.amount : b.total)) : fmtS(tr('done_unpaid', '%s billed to you'), money(d.amount != null ? d.amount : b.total)));
    const secs = Number(S.keys.summary || 9);
    root.querySelector('.bd-donewrap').innerHTML = `
      <div class="bd-done bd-card">
        <div class="bd-dl">
          <div class="bd-dring">${ring(1, { r: 43, w: 5, ticks: 60, cls: 'teal' })}<span class="bd-dic">${icon('check')}</span></div>
          <small>${esc(S.ses.ticket || '')} · ${esc(S.ses.bed || '')}</small>
          <h2>${esc(tr('done_title', 'You are patched up'))}</h2>
          <p>${esc(d.msg || tr('done_p', 'Take it easy for a few days.'))}</p>
          <div class="bd-dsteps"><div class="bd-dtrk"></div>${steps}</div>
        </div>
        <div class="bd-dr">
          ${b.enabled === false ? `<div class="bd-dfree">${icon('shield-check')}<b>${esc(tr('done_free', 'No charge'))}</b></div>` : `<div class="bd-dbill">${billHTML(b, true)}</div>`}
          <div class="bd-dpay ${ok ? 'ok' : 'bad'}">${icon(ok ? 'check' : 'alert')}<span>${esc(paidTxt)}</span></div>
          <div class="bd-dleave"><span class="bd-lring" style="--d:${secs}s"><svg viewBox="0 0 30 30"><circle cx="15" cy="15" r="12"/><circle class="p" cx="15" cy="15" r="12"/></svg></span><span>${esc(tr('done_leave', 'Getting up…'))}</span></div>
        </div>
      </div>`;
    NZA.audio.success();
  }

  /* ═══════════════════════ BED REST ═══════════════════════ */
  function buildRest(d) {
    const root = S.el.querySelector('.bd-rest');
    root.innerHTML = `
      <div class="bd-rp bd-card">
        <div class="bd-rhd">
          <span class="bd-rtile">${icon('bed')}</span>
          <div class="bd-rid"><small>${esc(tr('rest_title', 'Bed rest'))}</small><b class="bd-rbed">${esc(d.bed || d.label || tr('bed', 'Bed'))}</b><span class="bd-rhosp">${esc(d.hospital || '')}</span></div>
          <span class="bd-rmult"><b>×<span>4</span></b><small>${esc(tr('rest_heal', 'Healing'))}</small></span>
        </div>
        <div class="bd-rmain">
          <div class="bd-rring">${ring(0, { r: 43, w: 6, ticks: 60, cls: 'teal' })}<div class="bd-rrc"><b class="bd-rpct">--</b><small>${esc(tr('rest_recovery', 'Recovered'))}</small></div></div>
          <div class="bd-ilist bd-rlist">
            <div class="bd-irow white"><span>${esc(tr('rest_time', 'Resting'))}</span><div class="bd-rflip"></div></div>
            <div class="bd-irow teal"><span>${esc(tr('rest_eta_l', 'Healed in'))}</span><b class="bd-reta">--</b></div>
            <div class="bd-irow bd-rblood"><span>${esc(tr('rest_blood', 'Blood'))}</span><b>--</b></div>
            <div class="bd-irow bd-rpain"><span>${esc(tr('rest_pain', 'Pain'))}</span><b>--</b></div>
          </div>
        </div>
        <p class="bd-rnote"></p>
        <div class="bd-rinj"></div>
        <div class="bd-rkey"></div>
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
    const list = r.injuries || [];
    const stuck = list.some(i => !i.healing);
    root.querySelector('.bd-rpct').innerHTML = rec != null ? `${Math.round(rec)}<i>%</i>` : '--';
    root.querySelector('.bd-rring').classList.toggle('amber', stuck);
    setRing(root.querySelector('.bd-rring .bd-rs'), (rec || 0) / 100);
    const mult = r.mult || 4;
    root.querySelector('.bd-rmult span').textContent = mult;
    root.querySelector('.bd-rmult').classList.toggle('off', mult <= 1);
    const eta = list.length && r.eta > 0 ? (r.eta >= 3600 ? `${Math.floor(r.eta / 3600)} h ${pad((r.eta % 3600) / 60)} min` : `~${Math.max(1, Math.round(r.eta / 60))} min`) : (list.length ? '—' : tr('rest_now', 'Now'));
    root.querySelector('.bd-reta').textContent = eta;
    const note = root.querySelector('.bd-rnote');
    note.textContent = list.length ? (stuck ? tr('rest_needs', 'Some wounds need treatment before they heal') : '') : tr('rest_healed', 'Nothing left to heal — you can get up');
    note.className = `bd-rnote ${list.length ? (stuck ? 'amber' : '') : 'teal'}`;
    const blood = r.blood ?? null, pain = r.pain ?? 0;
    const bl = root.querySelector('.bd-rblood');
    bl.className = `bd-irow bd-rblood ${blood != null && blood < 80 ? 'red' : ''}`;
    bl.querySelector('b').textContent = blood != null ? `${blood}%` : '--';
    const pn = root.querySelector('.bd-rpain');
    pn.className = `bd-irow bd-rpain ${pain >= 50 ? 'amber' : ''}`;
    pn.querySelector('b').textContent = `${pain}/100`;
    const inj = list.slice(0, 5).map((i, k) => {
      const h = Math.round(i.heal || 0);
      return `<div class="bd-ri ${i.healing ? '' : 'stuck'}" style="--i:${k}">
        <span class="bd-rir">${ring(h / 100, { r: 40, w: 9, cls: i.healing ? 'teal' : 'amber' })}<span>${icon(STEP_ICON[i.icon] || i.icon || 'medkit')}</span></span>
        <div class="bd-rit"><b>${esc(i.short || i.label)}</b><span>${esc(i.healing ? (i.region || '') : tr('rest_stuck', 'Needs treatment first'))}</span></div>
        <em>${h}%</em>
      </div>`;
    }).join('');
    const more = list.length > 5 ? `<span class="bd-rmore">+${list.length - 5}</span>` : '';
    root.querySelector('.bd-rinj').innerHTML = inj ? inj + more : `<div class="bd-rnone">${icon('check')}${esc(tr('rest_clear', 'No injuries'))}</div>`;
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
