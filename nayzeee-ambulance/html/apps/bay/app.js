/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · app 'bay' — ambulance treatment bay HUD
   Owner: transport module (client/modules/transport_bay.lua)

   Lua → JS
     open    { locale, keys { exit, examine, supplies, ivstand, monitor }, unit { label, plate },
               crew [{ sid, name, grade, idx }], me, warnings { surgeryBlood, bleeding, noAccess,
               arrest, cold, moving }, tools { examine, monitor, ivstand, supplies }, patient }
     patient lite snapshot | false   (vitals, injuries, infusions, devices, surgery, bloodRunning…)
     crew    [...]        tick { speed, plate }        monitor { on }        tools {...}
     supplies { items [{ key, name, label, category, max, taken, left, have, img }], categories,
                resetIn, maxPerTake }                  suppliesClose
   JS → Lua
     bay:take { key, count } → { ok, list | msg }      bay:supplies { open = false }
     bay:action { id = exit|examine|supplies|ivstand|monitor }
   The HUD never takes focus; the supplies window does (Lua SetFocus) and Escape / F2 close it.
   While another procedure app is open the HUD collapses to the top strip.
   Preview: index.html?app=bay  (&demo=empty | supplies | monitor | arrest | moving)
   ═══════════════════════════════════════════════════════════ */
(() => {
  const APP = 'bay';
  const EN = {
    exit: 'Exit treatment bay', bay_title: 'Treatment bay', no_patient: 'No patient on the stretcher',
    no_patient_sub: 'Load a patient into the ambulance to treat them here.',
    hr: 'HR', spo2: 'SpO₂', nibp: 'NIBP', map: 'MAP', rr: 'RR', temp: 'Temp', loss: 'Blood loss', drip: 'Drip', bleed: 'Bleed',
    patient: 'Patient', stabilized: 'Stabilized', bleeding_out: 'Bleeding out',
    st_alive: 'Conscious', st_wounded: 'Wounded', st_arrest: 'Cardiac arrest', st_dead: 'Deceased',
    unit: 'Unit', crew: 'Crew in the bay', moving: 'Moving · %s km/h', parked: 'Standing still',
    examine: 'Examine', supplies: 'Supplies', ivstand: 'IV stand', monitor: 'Monitor',
    lines: 'Lines', no_lines: 'No fluids running', injuries: 'Injuries', no_injuries: 'No open injuries', more: '+%s more',
    warn_surgery: 'Surgery costs the patient blood — hang a unit on the IV stand before you open the wound.',
    warn_bleeding: 'Bleeding %s mL/min — control the bleeding first.',
    warn_access: 'No IV access while the patient is losing blood.',
    warn_arrest: 'No pulse — start CPR now.', warn_cold: 'Hypothermic at %s °C — warm the patient.',
    warn_moving: 'Ambulance moving at %s km/h — hold on.',
    w_surgery: 'Blood first', w_bleeding: 'Active bleeding', w_access: 'No access', w_arrest: 'Cardiac arrest',
    w_cold: 'Hypothermia', w_moving: 'On the move',
    sup_title: 'Supplies', sup_sub: 'Treatment bay shelves', sup_head: 'Free for the crew. Limits reset every shift.',
    sup_all: 'All supplies', sup_left: '%s of %s left this shift', sup_used: 'Used up this shift', sup_take: 'Take',
    sup_take_all: 'Take all', sup_have: 'In your pockets: %s', sup_reset: 'Shift resets in %s',
    sup_taken: 'Taken this shift', sup_left_total: 'Still on the shelves', close: 'Close', qty: 'Quantity',
    cat_wound: 'Wound care', cat_fluids: 'IV & fluids', cat_airway: 'Airway', cat_ortho: 'Immobilisation', cat_meds: 'Medication',
  };
  let L = {};
  const t = (k, ...a) => {
    let s = L[k] !== undefined ? L[k] : (EN[k] !== undefined ? EN[k] : k);
    a.forEach(v => { s = s.replace(/%[sd]/, String(v)); });
    return s;
  };
  const esc = s => NZA.esc(s == null ? '' : String(s));
  const ic = n => NZA.icon(n);
  const num = (v, d = 0) => (v === null || v === undefined || isNaN(v) ? '--' : Number(v).toFixed(d));
  const PASSIVE = new Set(['bay', 'wounded', 'death', 'callcard', 'pager', 'monitor', 'radial']);
  const ARREST = new Set(['vf', 'vt', 'asystole', 'pea']);
  const SEV_TONE = ['', 'teal', 'amber', 'red', 'red'];
  const CAT_ICON = { wound: 'bandage', fluids: 'iv', airway: 'lungs', ortho: 'splint', meds: 'pill' };

  let st = null;
  let R = null;            // element refs
  let ecg = null, pleth = null, flip = null, bigMon = null, win = null, compactT = 0, lastWarn = '';

  const fresh = () => ({
    keys: { exit: 'BACKSPACE', examine: 'F1', supplies: 'F2', ivstand: 'F3', monitor: 'F4' },
    unit: {}, crew: [], me: null, warnings: { surgeryBlood: true, bleeding: 25, noAccess: true, arrest: true, cold: 35, moving: 45 },
    tools: { examine: true, monitor: true, ivstand: true, supplies: true }, patient: null, speed: 0,
    sup: null, supCat: 'all', qty: {}, bigMon: false,
  });

  /* ─────────────── skeleton ─────────────── */
  function build(root) {
    root.innerHTML = `
      <div class="bay-top nza-hud">
        <div class="bay-ecg">
          <div class="bay-scr">
            <div class="bay-tr ecg"><span class="tl">II</span><canvas></canvas></div>
            <div class="bay-tr pl"><span class="tl">PLETH</span><canvas></canvas></div>
            <div class="bay-nosig"><span>NO SIGNAL</span></div>
          </div>
          <div class="bay-scr-foot"><span class="rh"></span><span class="drip"></span></div>
        </div>
        <div class="bay-mid">
          <div class="bay-exit"><kbd class="k-exit"></kbd><span class="x-l"></span></div>
          <div class="bay-unit"><span class="dot"></span><span class="u-l"></span></div>
        </div>
        <div class="bay-vit"></div>
      </div>
      <div class="bay-left">
        <div class="bay-pt nza-hud rail"></div>
      </div>
      <div class="bay-right">
        <div class="bay-warns"></div>
        <div class="bay-crew nza-hud"></div>
      </div>
      <div class="bay-keys nza-hud"></div>
      <div class="bay-mon"></div>
      <div class="bay-sup"></div>`;
    const q = s => root.querySelector(s);
    R = {
      root, top: q('.bay-top'), scr: q('.bay-scr'), rh: q('.rh'), drip: q('.drip'), nosig: q('.bay-nosig'),
      exitK: q('.k-exit'), exitL: q('.x-l'), unit: q('.bay-unit'), unitL: q('.u-l'), vit: q('.bay-vit'),
      pt: q('.bay-pt'), warns: q('.bay-warns'), crew: q('.bay-crew'), keys: q('.bay-keys'), mon: q('.bay-mon'), sup: q('.bay-sup'),
      ecgCv: q('.bay-tr.ecg canvas'), plCv: q('.bay-tr.pl canvas'),
    };
  }

  /* ─────────────── traces ─────────────── */
  function startTraces() {
    stopTraces();
    ecg = NZA.vitals.Trace(R.ecgCv, { type: 'ecg', color: '#3ddc84', speed: 0.2, gain: 0.42, line: 1.6 });
    pleth = NZA.vitals.Trace(R.plCv, { type: 'pleth', color: '#3fd0ff', speed: 0.2, gain: 0.34, line: 1.4 });
  }
  function stopTraces() {
    if (ecg) ecg.stop();
    if (pleth) pleth.stop();
    ecg = null; pleth = null;
  }

  /* ─────────────── top strip ─────────────── */
  function renderTop() {
    const p = st.patient;
    R.exitK.textContent = st.keys.exit || 'BACKSPACE';
    R.exitL.textContent = t('exit');
    const moving = (st.speed || 0) >= 3;
    const unitBits = [st.unit.label || t('bay_title'), st.unit.plate].filter(Boolean).map(esc);
    R.unitL.innerHTML = `${unitBits.join('<i>·</i>')}<i>·</i><b class="${moving ? 'mv' : ''}">${esc(moving ? t('moving', st.speed) : t('parked'))}</b>`;
    R.unit.classList.toggle('moving', moving);

    const v = (p && p.vitals) || {};
    const rhythm = v.rhythm || 'sinus';
    const arrest = p && (p.state === 'arrest' || ARREST.has(rhythm));
    const dead = p && p.state === 'dead';
    const rate = v.ecgRate ?? v.hr;
    R.nosig.style.display = p && !dead ? 'none' : '';
    if (ecg) {
      if (p && !dead) {
        ecg.set({ rhythm: dead ? 'asystole' : rhythm, rate: rate || 0 });
        pleth.set({ rhythm, rate: v.hr || 0, spo2: arrest ? 0 : (v.spo2 ?? 98), amp: Math.max(0.25, Math.min(1, (v.map ?? 80) / 85)) });
      } else {
        ecg.set({ rhythm: 'asystole', rate: 0 });
        pleth.set({ rhythm: 'asystole', rate: 0, spo2: 0 });
      }
    }
    R.rh.textContent = p ? `${rhythm === 'sinus' ? 'SINUS' : rhythm.toUpperCase()}${rate ? ` · ${Math.round(rate)} BPM` : ''}` : '';
    const drip = p ? (p.infusions || []).filter(f => !f.paused && (f.left ?? 1) > 0).reduce((a, f) => a + (Number(f.rate) || 0), 0) : 0;
    R.drip.innerHTML = drip > 0 ? `${esc(t('drip').toUpperCase())} <b>${num(drip)}</b> mL/min` : '';

    const tiles = [
      { k: 'hr', cls: 'hr', label: t('hr'), val: !p ? '--' : (arrest && (rhythm === 'asystole' || rhythm === 'vf')) ? '---' : num(rate), unit: 'bpm',
        alarm: p && (arrest || (rate ?? 75) > 130 || (rate ?? 75) < 45) },
      { k: 'spo2', cls: 'sp', label: t('spo2'), val: !p || arrest || !v.spo2 ? '--' : num(v.spo2), unit: '%', alarm: p && !arrest && (v.spo2 ?? 98) < 90 },
      { k: 'nibp', cls: 'bp', label: t('nibp'), val: !p || arrest ? '--/--' : `${num(v.sys)}/${num(v.dia)}`, unit: 'mmHg',
        sub: p && !arrest ? `${t('map')} ${num(v.map)}` : '', alarm: p && !arrest && (v.map ?? 80) < 60 },
      { k: 'rr', cls: 'rr', label: t('rr'), val: !p ? '--' : num(v.rr), unit: '/min', alarm: p && ((v.rr ?? 14) < 8 || (v.rr ?? 14) > 28) },
      { k: 'temp', cls: 'tp', label: t('temp'), val: !p || !(p.temp ?? v.temp) ? '--' : num(p.temp ?? v.temp, 1), unit: '°C',
        alarm: p && (p.temp ?? v.temp ?? 37) < 35 },
      { k: 'loss', cls: 'ls', label: t('loss'), val: !p ? '--' : num(p.lossMl || 0), unit: 'mL', alarm: p && (p.lossMl || 0) >= 1000,
        warn: p && (p.lossMl || 0) >= 400 },
    ];
    R.vit.innerHTML = tiles.map(x => `
      <div class="vt ${x.cls} ${p ? '' : 'nil'} ${x.alarm ? 'alarm' : ''} ${x.warn && !x.alarm ? 'warn' : ''}">
        <span class="l">${esc(x.label)}</span>
        <span class="v">${esc(x.val)}</span>
        <span class="u">${x.sub ? `<b>${esc(x.sub)}</b> ` : ''}${esc(x.unit)}</span>
      </div>`).join('');
  }

  /* ─────────────── patient card ─────────────── */
  function initials(name) {
    return String(name || '?').split(/\s+/).filter(Boolean).slice(0, 2).map(s => s[0]).join('').toUpperCase();
  }
  function triChip(tr) {
    if (!tr) return '';
    const lvl = tr.level || 3;
    return `<span class="prio p${lvl}">P${lvl} ${esc(String(tr.label || '').toUpperCase())}</span>`;
  }
  function stateBlock(p) {
    if (p.state === 'arrest') {
      const r = String((p.vitals && p.vitals.rhythm) || 'asystole');
      const shock = r === 'vf' || r === 'vt';
      return `<div class="pst red"><span class="pi">${ic('heart')}</span><div><b>${esc(t('st_arrest'))}</b><small>${esc(r.toUpperCase())}${shock ? ' · <em>SHOCKABLE</em>' : ''}</small></div><div class="pc"></div></div>`;
    }
    if (p.state === 'dead') return `<div class="pst dim"><span class="pi">${ic('skull')}</span><div><b>${esc(t('st_dead'))}</b></div></div>`;
    if (p.state === 'wounded' && !p.stabilized) return `<div class="pst red"><span class="pi">${ic('drop')}</span><div><b>${esc(t('bleeding_out'))}</b><small>${esc(t('bleed'))} ${num(p.bleed, 1)} mL/min</small></div><div class="pc"></div></div>`;
    if (p.state === 'wounded') return `<div class="pst teal"><span class="pi">${ic('shield-check')}</span><div><b>${esc(t('stabilized'))}</b><small>${esc(t('st_wounded'))} · AVPU ${esc((p.vitals && p.vitals.avpu) || 'A')}</small></div></div>`;
    return `<div class="pst teal"><span class="pi">${ic('check')}</span><div><b>${esc(t('st_alive'))}</b><small>AVPU ${esc((p.vitals && p.vitals.avpu) || 'A')}</small></div></div>`;
  }
  function sevPips(n) {
    return `<span class="pips s${n}">${[1, 2, 3, 4].map(i => `<i class="${i <= n ? 'on' : ''}"></i>`).join('')}</span>`;
  }
  function renderPatient() {
    const p = st.patient;
    if (flip) flip = null;
    if (!p) {
      R.pt.innerHTML = `<div class="pt-empty"><span class="ei">${ic('bed')}</span><b>${esc(t('no_patient'))}</b><p>${esc(t('no_patient_sub'))}</p></div>`;
      R.pt.classList.add('empty');
      return;
    }
    R.pt.classList.remove('empty');
    const inj = p.injuries || [];
    const more = Math.max(0, (p.injuryCount || inj.length) - inj.length);
    const inf = p.infusions || [];
    const d = p.devices || {};
    const chips = [];
    if (d.iv) chips.push(['iv', String(d.iv).toUpperCase()]);
    if (d.oxygen) chips.push(['wind', 'O₂']);
    if (d.intubated) chips.push(['tube', 'ETT']);
    if (d.collar) chips.push(['collar', 'C-collar']);
    if (d.binder) chips.push(['shield', 'Binder']);
    if (d.tq) chips.push(['clamp', `TQ ×${d.tq}`]);
    if (d.splints) chips.push(['splint', `Splint ×${d.splints}`]);
    if (d.foil) chips.push(['blanket', 'Foil']);
    const bloodPct = Math.max(0, Math.min(100, Number(p.bloodPct ?? 100)));
    R.pt.innerHTML = `
      <div class="pt-head">
        <div class="av">${esc(initials(p.name))}</div>
        <div class="who"><b>${esc(p.name || t('patient'))}</b><span>${esc([p.sex ? String(p.sex).toUpperCase() : '', p.age, p.bloodType].filter(x => x !== undefined && x !== null && x !== '').join(' · '))}</span></div>
        ${triChip(p.triage)}
      </div>
      ${stateBlock(p)}
      <div class="pt-meters">
        <div class="pm"><span>${esc(t('bleed'))}</span><b class="${p.bleed >= 10 ? 'red' : p.bleed > 1 ? 'amber' : 'teal'}">${num(p.bleed, 1)}<i>mL/min</i></b>
          ${NZA.ui.meterHTML({ value: Math.min(1, (p.bleed || 0) / 60), tone: p.bleed >= 10 ? 'red' : p.bleed > 1 ? 'amber' : '' })}</div>
        <div class="pm"><span>Blood</span><b class="${bloodPct < 70 ? 'red' : bloodPct < 85 ? 'amber' : 'teal'}">${num(bloodPct)}<i>%</i></b>
          ${NZA.ui.meterHTML({ value: bloodPct / 100, tone: bloodPct < 70 ? 'red' : bloodPct < 85 ? 'amber' : '', mark: 0.7 })}</div>
      </div>
      <div class="pt-sec"><h4>${esc(t('injuries'))}</h4>
        ${inj.length ? inj.map(i => `
          <div class="inj ${i.status === 'open' ? 'open' : ''}">
            ${sevPips(i.severity || 1)}
            <div class="tx"><b>${esc(i.typeLabel || i.type)}</b><span>${esc(i.regionLabel || i.region)}</span></div>
            ${i.bleed > 0 ? `<span class="bl">${num(i.bleed, 1)}<i>mL/min</i></span>` : `<span class="stt ${esc(i.status)}">${esc(i.status || '')}</span>`}
          </div>`).join('') + (more ? `<div class="inj-more">${esc(t('more', more))}</div>` : '')
        : `<div class="none">${esc(t('no_injuries'))}</div>`}
      </div>
      <div class="pt-sec"><h4>${esc(t('lines'))}</h4>
        ${inf.length ? inf.map(f => {
          const tot = f.ml || 500, left = Math.max(0, f.left ?? tot);
          const nm = f.kind === 'blood' ? `Blood ${f.type || ''}`.trim() : f.kind === 'txa' ? 'TXA' : f.kind === 'plasma' ? 'Plasma' : 'Saline';
          return `<div class="line ${f.kind} ${f.paused ? 'paused' : ''}">
            <span class="li">${ic(f.kind === 'blood' ? 'bloodbag' : 'iv')}</span>
            <div class="tx"><b>${esc(nm)} <i>${num(tot)} mL</i></b>${NZA.ui.meterHTML({ value: left / tot, tone: f.kind === 'blood' ? 'red' : '' })}</div>
            <span class="rt">${f.paused ? 'PAUSED' : `${num(f.rate)}<i>mL/min</i>`}<small>${num(left)} mL</small></span>
          </div>`;
        }).join('') : `<div class="none">${esc(t('no_lines'))}</div>`}
      </div>
      ${chips.length ? `<div class="pt-dev">${chips.map(c => `<span class="chipx sm teal">${ic(c[0])}${esc(c[1])}</span>`).join('')}</div>` : ''}`;
    const pc = R.pt.querySelector('.pc');
    if (pc && p.state === 'wounded' && !p.stabilized && p.clock !== undefined && p.clock !== null) {
      flip = NZA.ui.FlipClock(pc, { value: NZA.fmt.time(p.clock), small: true, tone: p.clock < 60 ? 'red' : '' });
    } else if (pc && p.state === 'arrest' && p.clock) {
      flip = NZA.ui.FlipClock(pc, { value: NZA.fmt.time(p.clock), small: true, tone: 'red' });
    }
  }

  /* ─────────────── warnings ─────────────── */
  function computeWarnings() {
    const w = st.warnings || {};
    const p = st.patient;
    const out = [];
    if (p) {
      if (w.arrest !== false && p.state === 'arrest') out.push({ id: 'arrest', tone: 'error', icon: 'heart', title: t('w_arrest'), text: t('warn_arrest') });
      if (w.surgeryBlood !== false && p.surgery && !p.bloodRunning && p.state !== 'dead') out.push({ id: 'surgery', tone: 'error', icon: 'bloodbag', title: t('w_surgery'), text: t('warn_surgery') });
      if (w.bleeding && (p.bleed || 0) >= w.bleeding) out.push({ id: 'bleeding', tone: 'error', icon: 'drop', title: t('w_bleeding'), text: t('warn_bleeding', num(p.bleed, 1)) });
      if (w.noAccess !== false && !p.access && p.state !== 'dead' && ((p.bleed || 0) > 1 || (p.lossMl || 0) >= 500)) out.push({ id: 'access', tone: 'warning', icon: 'iv', title: t('w_access'), text: t('warn_access') });
      if (w.cold && (p.temp ?? 37) < w.cold && p.state !== 'dead') out.push({ id: 'cold', tone: 'warning', icon: 'thermo', title: t('w_cold'), text: t('warn_cold', num(p.temp, 1)) });
    }
    if (w.moving && (st.speed || 0) >= w.moving) out.push({ id: 'moving', tone: 'warning', icon: 'ambulance', title: t('w_moving'), text: t('warn_moving', st.speed) });
    return out;
  }
  function renderWarnings() {
    const list = computeWarnings();
    const sig = list.map(x => `${x.id}:${x.text}`).join('|');
    if (sig === lastWarn) return;
    const before = new Set(lastWarn.split('|').map(s => s.split(':')[0]));
    lastWarn = sig;
    R.warns.innerHTML = list.map(x => `
      <div class="note ${x.tone} ${before.has(x.id) ? 'still' : ''}" data-id="${x.id}">
        <span class="ni">${ic(x.icon)}</span><div><b>${esc(x.title)}</b><p>${esc(x.text)}</p></div>
      </div>`).join('');
    if (list.some(x => x.tone === 'error' && !before.has(x.id)) && NZA.cfg.sounds !== false) NZA.audio.alarm(1);
  }

  /* ─────────────── crew & keys ─────────────── */
  function renderCrew() {
    const crew = st.crew || [];
    R.crew.style.display = crew.length ? '' : 'none';
    R.crew.innerHTML = `<div class="nza-label">${esc(t('crew'))}<span>${crew.length}</span></div>` + crew.map(c => `
      <div class="cm ${c.sid === st.me ? 'me' : ''}">
        <span class="av">${esc(initials(c.name))}</span>
        <div class="tx"><b>${esc(c.name)}</b>${c.grade ? `<span>${esc(c.grade)}</span>` : ''}</div>
        ${c.sid === st.me ? '<span class="chipx sm teal">YOU</span>' : ''}
      </div>`).join('');
  }
  function renderKeys() {
    const tools = [
      ['examine', 'stetho'], ['supplies', 'box'], ['ivstand', 'iv'], ['monitor', 'monitor'],
    ];
    R.keys.innerHTML = tools.map(([id, icon]) => `
      <button class="bk ${st.tools[id] === false || (!st.patient && (id === 'examine' || id === 'ivstand')) ? 'off' : ''} ${(id === 'monitor' && st.bigMon) || (id === 'supplies' && win) ? 'on' : ''}" data-id="${id}">
        <kbd>${esc(st.keys[id] || '')}</kbd><span class="bi">${ic(icon)}</span><span>${esc(t(id))}</span>
      </button>`).join('');
    R.keys.querySelectorAll('.bk').forEach(b => b.addEventListener('click', () => {
      if (b.dataset.id === 'supplies' && win) return closeSupplies(true);
      NZA.post('bay:action', { id: b.dataset.id });
      if (!NZA.inGame) localAction(b.dataset.id);
    }));
  }

  /* ─────────────── big monitor (F4 fallback) ─────────────── */
  function setBigMonitor(on) {
    st.bigMon = !!on;
    if (!st.bigMon) {
      if (bigMon) { bigMon.destroy(); bigMon = null; }
      R.mon.innerHTML = '';
      R.mon.classList.remove('on');
      renderKeys();
      return;
    }
    R.mon.classList.add('on');
    R.mon.innerHTML = `<div class="dev bay-dev">
      <div class="dev-top"><span class="dev-brand"><span class="nz-mark"></span>NAYZEEE · TRANSPORT MONITOR</span><span class="dev-led ${st.patient ? '' : 'off'}"></span></div>
      <div class="dev-screen"><div class="host"></div></div>
      <div class="dev-foot"><kbd>${esc(st.keys.monitor || 'F4')}</kbd><span>${esc(t('monitor'))}</span></div>
    </div>`;
    bigMon = NZA.vitals.Monitor(R.mon.querySelector('.host'), { traces: ['ecg', 'pleth', 'resp'], height: 246, beep: false, title: 'ADULT · BAY' });
    updateBigMonitor();
    renderKeys();
  }
  function updateBigMonitor() {
    if (!bigMon) return;
    const p = st.patient;
    const v = (p && p.vitals) || {};
    if (!p || p.state === 'dead') bigMon.update({ hr: 0, spo2: 0, sys: 0, dia: 0, map: 0, rr: 0, temp: p ? p.temp : 0, rhythm: 'asystole' });
    else bigMon.update({ hr: v.ecgRate ?? v.hr, spo2: v.spo2, sys: v.sys, dia: v.dia, map: v.map, rr: v.rr, temp: p.temp ?? v.temp, rhythm: v.rhythm || 'sinus' });
    const led = R.mon.querySelector('.dev-led');
    if (led) led.classList.toggle('off', !p);
  }

  /* ─────────────── supplies window ─────────────── */
  function catLabel(id) { return t(`cat_${id}`); }
  function supItems() {
    const items = (st.sup && st.sup.items) || [];
    return st.supCat === 'all' ? items : items.filter(i => i.category === st.supCat);
  }
  function fmtDur(sec) {
    sec = Math.max(0, Math.floor(sec || 0));
    const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60);
    return h > 0 ? `${h}h ${String(m).padStart(2, '0')}m` : `${m}m`;
  }
  function openSupplies(data) {
    st.sup = data || { items: [] };
    if (!win) {
      R.sup.innerHTML = '<div class="nza-dim"></div>';
      const cats = st.sup.categories || [];
      const items = st.sup.items || [];
      win = NZA.ui.Win(R.sup, {
        title: t('sup_title'), sub: [st.unit.label, st.unit.plate].filter(Boolean).join(' · ') || t('sup_sub'),
        width: '1040px', height: '690px',
        nav: [{ id: 'all', label: t('sup_all'), icon: 'grid', tally: items.length }, { group: t('sup_sub') },
          ...cats.map(c => ({ id: c.id, label: c.label || catLabel(c.id), icon: c.icon || CAT_ICON[c.id] || 'box', tally: items.filter(i => i.category === c.id).length }))],
        navValue: st.supCat,
        onNav: id => { st.supCat = id; renderSupplies(); },
        onClose: () => closeSupplies(true),
        status: [{ key: 'ESC', label: t('close') }, { key: st.keys.supplies || 'F2', label: t('supplies') }, { key: '+ / −', label: t('qty') }],
      });
      win.el.classList.add('bay-win');
    }
    renderSupplies();
    renderKeys();
  }
  function renderSupplies() {
    if (!win) return;
    const all = (st.sup && st.sup.items) || [];
    const items = supItems();
    const taken = all.reduce((a, i) => a + (i.taken || 0), 0);
    const left = all.reduce((a, i) => a + (i.left || 0), 0);
    const reset = st.sup && st.sup.resetIn;
    win.setMid(`<span class="nz-dot"></span><p>${reset ? `<b>${esc(t('sup_reset', fmtDur(reset)))}</b> · ` : ''}${esc(t('sup_taken'))} <b>${taken}</b></p>`);
    const maxTake = (st.sup && st.sup.maxPerTake) || 10;
    win.main.innerHTML = `
      <div class="w-head"><div><h1>${esc(st.supCat === 'all' ? t('sup_all') : catLabel(st.supCat))}</h1><p>${esc(t('sup_head'))}</p></div></div>
      <div class="w-stats">
        <div class="w-stat"><div class="nz-tile">${ic('box')}</div><div><span>${esc(t('sup_left_total'))}</span><b>${left}</b></div></div>
        <div class="w-stat"><div class="nz-tile">${ic('check')}</div><div><span>${esc(t('sup_taken'))}</span><b>${taken}</b></div></div>
        <div class="w-stat"><div class="nz-tile">${ic('clock')}</div><div><span>${esc(t('sup_reset', '')).replace(/\s+$/, '')}</span><b>${reset ? esc(fmtDur(reset)) : '—'}</b></div></div>
      </div>
      <div class="sup-grid nza-scroll">${items.map(i => {
        const q = Math.max(1, Math.min(st.qty[i.key] || 1, Math.max(1, Math.min(i.left, maxTake))));
        const used = i.left <= 0;
        const pct = i.max ? i.left / i.max : 0;
        return `<div class="sup ${used ? 'used' : ''}" data-key="${esc(i.key)}">
          <div class="sup-img">${i.img ? `<img src="${esc(i.img)}" alt="" onerror="this.remove()">` : ''}<span class="fb">${ic(CAT_ICON[i.category] || 'box')}</span></div>
          <div class="sup-tx">
            <b>${esc(i.label)}</b>
            <span class="cat">${esc(catLabel(i.category))}</span>
          </div>
          <div class="sup-left">
            <div class="row"><span>${esc(used ? t('sup_used') : t('sup_left', i.left, i.max))}</span>${i.have ? `<em>${esc(t('sup_have', i.have))}</em>` : ''}</div>
            ${NZA.ui.meterHTML({ value: pct, tone: used ? 'red' : pct < 0.34 ? 'amber' : '', segs: true })}
          </div>
          <div class="sup-act">
            <div class="step"><button class="mn" ${used || q <= 1 ? 'disabled' : ''}>${ic('minus')}</button><span>${used ? 0 : q}</span><button class="pl" ${used || q >= Math.min(i.left, maxTake) ? 'disabled' : ''}>${ic('plus')}</button></div>
            <button class="btn-teal btn-sm tk" ${used ? 'disabled' : ''}>${esc(t('sup_take'))}</button>
            <button class="btn-line btn-sm ta" ${used || i.left <= 1 ? 'disabled' : ''}>${esc(t('sup_take_all'))}</button>
          </div>
        </div>`;
      }).join('')}</div>`;
    win.main.querySelectorAll('.sup').forEach(card => {
      const key = card.dataset.key;
      const item = all.find(i => i.key === key);
      if (!item) return;
      const cap = Math.max(1, Math.min(item.left, maxTake));
      const setQ = n => { st.qty[key] = Math.max(1, Math.min(cap, n)); NZA.audio.tick(); renderSupplies(); };
      card.querySelector('.mn').onclick = () => setQ((st.qty[key] || 1) - 1);
      card.querySelector('.pl').onclick = () => setQ((st.qty[key] || 1) + 1);
      card.querySelector('.tk').onclick = () => take(key, Math.min(st.qty[key] || 1, cap), card);
      card.querySelector('.ta').onclick = () => take(key, cap, card);
    });
  }
  async function take(key, count, card) {
    if (card) card.classList.add('busy');
    const res = await NZA.post('bay:take', { key, count });
    if (card) card.classList.remove('busy');
    if (res && res.ok && res.list) {
      st.sup = Object.assign({}, st.sup, res.list);
      st.qty[key] = 1;
      renderSupplies();
      const c = win && win.main.querySelector(`.sup[data-key="${CSS.escape(key)}"]`);
      if (c) { c.classList.remove('flash'); void c.offsetWidth; c.classList.add('flash'); }
      NZA.audio.success();
    } else {
      NZA.audio.fail();
      if (res && res.msg) NZA.toast({ title: t('sup_title'), message: res.msg, type: 'error' });
    }
  }
  function closeSupplies(notify) {
    if (!win) return;
    win.destroy();
    win = null;
    R.sup.innerHTML = '';
    renderKeys();
    if (notify) NZA.post('bay:supplies', { open: false });
  }

  /* ─────────────── compact mode while procedures run ─────────────── */
  function checkCompact() {
    const busy = NZA.stack.some(n => !PASSIVE.has(n));
    R.root.classList.toggle('compact', busy);
  }

  /* ─────────────── preview-only local actions ─────────────── */
  function localAction(id) {
    if (id === 'monitor') setBigMonitor(!st.bigMon);
    if (id === 'supplies') NZA.apps.bay.msg.supplies(demoSupplies());
    if (id === 'exit') NZA.close(APP);
  }

  function renderAll() {
    renderTop(); renderPatient(); renderWarnings(); renderCrew(); renderKeys(); updateBigMonitor();
  }

  NZA.app(APP, {
    escClose: false,
    init(root) { build(root); },
    open(d) {
      st = fresh();
      if (d.locale) L = d.locale;
      if (d.keys) st.keys = Object.assign(st.keys, d.keys);
      if (d.unit) st.unit = d.unit;
      if (d.crew) st.crew = d.crew;
      if (d.me !== undefined) st.me = d.me;
      if (d.warnings) st.warnings = Object.assign(st.warnings, d.warnings);
      if (d.tools) st.tools = Object.assign(st.tools, d.tools);
      st.patient = d.patient || null;
      st.speed = d.speed || 0;
      lastWarn = '';
      closeSupplies(false);
      setBigMonitor(false);
      startTraces();
      renderAll();
      clearInterval(compactT);
      compactT = setInterval(checkCompact, 400);
      checkCompact();
    },
    close() {
      clearInterval(compactT);
      stopTraces();
      setBigMonitor(false);
      closeSupplies(false);
    },
    msg: {
      patient(p) {
        if (!st) return;
        const had = !!st.patient;
        st.patient = p || null;
        renderTop(); renderPatient(); renderWarnings(); updateBigMonitor();
        if (had !== !!st.patient) renderKeys();
      },
      crew(c) { if (!st) return; st.crew = Array.isArray(c) ? c : []; renderCrew(); },
      tick(d) { if (!st) return; st.speed = Math.round(Number(d.speed) || 0); if (d.plate) st.unit.plate = d.plate; renderTop(); renderWarnings(); },
      tools(d) { if (!st) return; st.tools = Object.assign(st.tools, d || {}); renderKeys(); },
      monitor(d) { if (!st) return; setBigMonitor(d && d.on); },
      supplies(d) { if (!st) return; openSupplies(d); },
      suppliesClose() { closeSupplies(false); },
    },
    keys: {
      Escape() { if (win) { closeSupplies(true); return true; } return false; },
      F2() { if (win) { closeSupplies(true); return true; } return false; },
      '+'() { return stepFirst(1); },
      '-'() { return stepFirst(-1); },
    },
    preview() {
      const demo = new URLSearchParams(location.search).get('demo') || '';
      NZA.mock('bay:take', ({ key, count }) => {
        const it = (st.sup.items || []).find(i => i.key === key);
        if (!it || it.left <= 0) return { ok: false, msg: 'You took all of those this shift.' };
        const n = Math.min(count, it.left);
        it.left -= n; it.taken += n; it.have = (it.have || 0) + n;
        NZA.toast({ title: 'Transport', message: `Took ${n}x ${it.label}.` });
        return { ok: true, list: { items: st.sup.items, categories: st.sup.categories, resetIn: st.sup.resetIn, maxPerTake: 10 } };
      });
      NZA.demo(APP, {
        unit: { label: 'Ambulance', plate: 'EMS 12' }, me: 2,
        crew: [{ sid: 2, idx: 1, name: 'Sarah Lin', grade: 'Paramedic' }, { sid: 7, idx: 2, name: 'Dario Costa', grade: 'EMT' }],
        tools: { examine: true, monitor: true, ivstand: true, supplies: true },
        patient: demo === 'empty' ? false : demoPatient(demo),
        speed: demo === 'moving' ? 58 : 0,
      });
      if (demo === 'moving') NZA.apps.bay.msg.tick({ speed: 58 });
      if (demo === 'monitor') setBigMonitor(true);
      if (demo === 'supplies') NZA.apps.bay.msg.supplies(demoSupplies());
      // live demo: vitals drift, the clock runs
      if (demo !== 'empty') {
        setInterval(() => {
          const p = st && st.patient;
          if (!p || p.state === 'dead') return;
          if (p.state === 'wounded' && !p.stabilized && p.clock > 0) p.clock -= 1;
          if (p.state !== 'arrest') {
            p.vitals.hr = Math.round(124 + Math.sin(Date.now() / 3000) * 4);
            p.vitals.ecgRate = p.vitals.hr;
            p.vitals.spo2 = 93 + (Math.random() < 0.3 ? 1 : 0);
          }
          NZA.apps.bay.msg.patient(p);
        }, 1000);
      }
    },
  });

  function stepFirst(dir) {
    if (!win) return false;
    const it = supItems().find(i => i.left > 0);
    if (!it) return true;
    const cap = Math.max(1, Math.min(it.left, (st.sup && st.sup.maxPerTake) || 10));
    st.qty[it.key] = Math.max(1, Math.min(cap, (st.qty[it.key] || 1) + dir));
    renderSupplies();
    return true;
  }

  /* ─────────────── demo data (browser preview only) ─────────────── */
  function demoPatient(kind) {
    const arrest = kind === 'arrest';
    return {
      name: 'Michael Garcia', sex: 'm', age: 34, bloodType: 'O-', state: arrest ? 'arrest' : 'wounded', stabilized: false,
      clock: arrest ? 214 : 142, triage: { level: 1, code: 'P1', label: 'Critical', colour: '#e5484d' },
      vitals: arrest
        ? { hr: 0, ecgRate: 0, sys: 0, dia: 0, map: 0, spo2: 0, rr: 0, temp: 35.1, rhythm: 'vf', avpu: 'U' }
        : { hr: 126, ecgRate: 126, sys: 92, dia: 58, map: 69, spo2: 93, rr: 24, temp: 34.6, rhythm: 'stach', avpu: 'V' },
      temp: arrest ? 35.1 : 34.6, bleed: 14.8, bloodPct: 76, lossMl: 1240, access: true,
      injuries: [
        { region: 'chest', regionLabel: 'Chest', type: 'gunshot', typeLabel: 'Gunshot wound', severity: 3, status: 'open', bleed: 9.2 },
        { region: 'l_upper_arm', regionLabel: 'Left upper arm', type: 'laceration', typeLabel: 'Deep laceration', severity: 2, status: 'controlled', bleed: 3.1 },
        { region: 'abdomen', regionLabel: 'Abdomen', type: 'internal', typeLabel: 'Internal bleeding', severity: 3, status: 'open', bleed: 2.5 },
        { region: 'r_lower_leg', regionLabel: 'Right lower leg', type: 'fracture', typeLabel: 'Fracture', severity: 3, status: 'treated', bleed: 0 },
      ],
      injuryCount: 5,
      infusions: [{ kind: 'saline', ml: 500, left: 320, rate: 125 }],
      devices: { iv: 'iv', oxygen: true, collar: true, tq: 1, splints: 1 },
      surgery: true, bloodRunning: false,
    };
  }
  function demoSupplies() {
    const img = n => `img/items/${n}.png`;
    const items = [
      ['bandage', 'bandage', 'Bandage', 'wound', 12, 4, 2], ['gauze', 'gauze', 'Gauze', 'wound', 12, 0, 0],
      ['dressing', 'sterile_dressing', 'Sterile Dressing', 'wound', 8, 2, 1], ['burn_dressing', 'burn_dressing', 'Burn Dressing', 'wound', 6, 6, 3],
      ['tourniquet', 'tourniquet', 'Tourniquet', 'wound', 4, 1, 1], ['iodine', 'iodine_swab', 'Iodine Swab', 'wound', 8, 0, 0],
      ['ice_pack', 'ice_pack', 'Ice Pack', 'wound', 4, 0, 0], ['foil_blanket', 'foil_blanket', 'Foil Blanket', 'wound', 4, 1, 0],
      ['saline_bag', 'saline_bag', 'Saline Bag 500 ml', 'fluids', 6, 2, 1], ['iv_kit', 'iv_kit', 'IV Kit', 'fluids', 6, 1, 2],
      ['saline', 'saline', 'Saline 0.9%', 'fluids', 6, 0, 0], ['txa', 'txa', 'TXA 1 g', 'fluids', 3, 3, 0],
      ['oxygen_mask', 'oxygen_mask', 'Oxygen Mask', 'airway', 3, 0, 0], ['bvm', 'bvm', 'Bag-Valve Mask', 'airway', 1, 0, 1],
      ['decomp_needle', 'decompression_needle', 'Decompression Needle', 'airway', 2, 0, 0],
      ['splint', 'splint', 'Splint', 'ortho', 4, 1, 0], ['cervical_collar', 'cervical_collar', 'Cervical Collar', 'ortho', 3, 0, 0],
      ['pelvic_binder', 'pelvic_binder', 'Pelvic Binder', 'ortho', 2, 0, 0],
      ['painkillers', 'painkillers', 'Painkillers', 'meds', 6, 2, 3], ['naloxone', 'naloxone', 'Naloxone', 'meds', 2, 0, 0],
    ].map(([key, name, label, category, max, taken, have]) => ({ key, name, label, category, max, taken, left: max - taken, have, img: img(name) }));
    return {
      items, resetIn: 11520, maxPerTake: 10,
      categories: [{ id: 'wound', icon: 'bandage' }, { id: 'fluids', icon: 'iv' }, { id: 'airway', icon: 'lungs' }, { id: 'ortho', icon: 'splint' }, { id: 'meds', icon: 'pill' }],
    };
  }
})();
