/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · app 'bay' — patient cabin HUD (walk-in ambulance)
   Owner: transport module (client/modules/transport_bay.lua)

   Layout (NAYZEEE HUD language — corner brackets, status rings, instrument rows, edge dock):
     top-left      patient card: blood ring avatar, state + rolling counter, holographic body
                   glyph with every wound, wound list, infusion bags, devices; alerts under it
     top-right     cabin monitor card: ECG + pleth sweep, vitals as instrument rows, unit / motion
                   line; crew card under it
     right edge    action dock (bottom-aligned): Assess · Supplies · Fluids · Monitor · Get out
     F4            big transport monitor (handheld industrial shell, generic model code, no brand)
     compact       while another procedure app is open everything folds into a slim cabin tab
                   hanging from the top edge (left of centre), so the procedure HUD stays clear
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
   Preview: index.html?app=bay  (&demo=empty | supplies | monitor | arrest | moving | compact)
   ═══════════════════════════════════════════════════════════ */
(() => {
  const APP = 'bay';
  const EN = {
    exit: 'Get out', bay_title: 'Patient cabin', no_patient: 'Stretcher is empty',
    no_patient_sub: 'Load a patient into the ambulance to work on them here.',
    hr: 'HR', spo2: 'SpO₂', nibp: 'BP', map: 'MAP', rr: 'RR', temp: 'Temp', loss: 'Est. loss', drip: 'Running', bleed: 'Bleed',
    blood: 'Blood', patient: 'Patient', stabilized: 'Holding steady', bleeding_out: 'Bleeding out',
    st_alive: 'Conscious', st_wounded: 'Wounded', st_arrest: 'Cardiac arrest', st_dead: 'Deceased',
    unit: 'Unit', crew: 'In the back', moving: 'Moving · %s km/h', parked: 'Parked',
    examine: 'Assess', supplies: 'Supplies', ivstand: 'Fluids', monitor: 'Monitor',
    lines: 'Infusions', no_lines: 'Nothing running', injuries: 'Wounds', no_injuries: 'No open wounds', more: '+%s more',
    alerts: 'Alerts', vitals: 'Vitals', you: 'You', paused: 'Paused', shockable: 'Shockable', no_signal: 'No signal',
    warn_surgery: 'This patient needs surgery. Start a blood unit before you cut.',
    warn_bleeding: 'Losing %s mL/min. Control the bleed first.',
    warn_access: 'Losing blood with no line in. Place an IV or IO.',
    warn_arrest: 'No pulse. Start compressions.', warn_cold: 'Core temp %s °C. Get a blanket on them.',
    warn_moving: 'Driving at %s km/h. Brace before you work.',
    w_surgery: 'No blood running', w_bleeding: 'Heavy bleed', w_access: 'No line', w_arrest: 'Cardiac arrest',
    w_cold: 'Getting cold', w_moving: 'Rough ride',
    sup_title: 'Supplies', sup_sub: 'Cabin shelves', sup_head: 'Free for the crew. Every shelf refills at the start of a shift.',
    sup_all: 'All shelves', sup_left: '%s of %s left', sup_used: 'Shelf empty', sup_take: 'Take',
    sup_take_all: 'Grab %s at once', sup_have: 'Carrying %s', sup_reset: 'Refill in %s', sup_shelf: 'Shelf %s',
    sup_taken: 'Taken this shift', sup_left_total: 'On the shelves', close: 'Close', qty: 'Quantity',
    cat_wound: 'Wound care', cat_fluids: 'IV & fluids', cat_airway: 'Airway', cat_ortho: 'Immobilisation', cat_meds: 'Medication',
    mon_model: 'Transport monitor', mon_warn: 'Secure before driving',
  };
  let L = {};
  const t = (k, ...a) => {
    let s = L[k] !== undefined ? L[k] : (EN[k] !== undefined ? EN[k] : k);
    a.forEach(v => { s = s.replace(/%[sd]/, String(v)); });
    return s;
  };
  const esc = s => NZA.esc(s == null ? '' : String(s));
  const ic = n => NZA.icon(n);
  const clamp = (n, a, b) => Math.max(a, Math.min(b, n));
  const num = (v, d = 0) => (v === null || v === undefined || isNaN(v) ? '--' : Number(v).toFixed(d));
  const PASSIVE = new Set(['bay', 'wounded', 'death', 'callcard', 'pager', 'monitor', 'radial']);
  const ARREST = new Set(['vf', 'vt', 'asystole', 'pea']);
  const SEV_TONE = ['', 'teal', 'amber', 'red', 'red'];
  const CAT_ICON = { wound: 'bandage', fluids: 'iv', airway: 'lungs', ortho: 'splint', meds: 'pill' };
  const keyCap = k => (String(k || '').toUpperCase() === 'BACKSPACE' ? 'BKSP' : String(k || ''));

  // a hanging IV bag glyph; liquid level = fraction left
  function bagGlyph(frac, kind) {
    const f = clamp(frac, 0, 1), top = 6 + (1 - f) * 20;
    return `<svg class="bag ${kind}" viewBox="0 0 22 40" aria-hidden="true"><path class="hk" d="M11 1v3"/><path class="sh" d="M4 5h14v19a7 7 0 0 1-14 0z"/>
      <clipPath id="bagc-${kind}-${Math.round(f * 100)}"><path d="M4 5h14v19a7 7 0 0 1-14 0z"/></clipPath>
      <rect class="lq" x="4" y="${top.toFixed(1)}" width="14" height="${(31 - top).toFixed(1)}" clip-path="url(#bagc-${kind}-${Math.round(f * 100)})"/>
      <path class="gl" d="M6.5 8v14"/><path class="tb" d="M11 31v8"/></svg>`;
  }

  let st = null;
  let R = null;            // element refs
  let ecg = null, pleth = null, mini = null, odo = null, bigMon = null, win = null, compactT = 0, lastWarn = '', odoKey = '';

  const fresh = () => ({
    keys: { exit: 'BACKSPACE', examine: 'F1', supplies: 'F2', ivstand: 'F3', monitor: 'F4' },
    unit: {}, crew: [], me: null, warnings: { surgeryBlood: true, bleeding: 25, noAccess: true, arrest: true, cold: 35, moving: 45 },
    tools: { examine: true, monitor: true, ivstand: true, supplies: true }, patient: null, speed: 0,
    sup: null, supCat: 'all', qty: {}, bigMon: false,
  });

  /* ─────────────── skeleton ─────────────── */
  function build(root) {
    root.innerHTML = `
      <div class="bay-left">
        <section class="bay-pt"></section>
        <div class="bay-warns"></div>
      </div>
      <div class="bay-right">
        <section class="bay-cab">
          <header class="cab-hd"><span class="cab-ic">${ic('ambulance')}</span><div class="cab-u"><b class="u-l"></b><span class="u-s"></span></div><span class="cab-mv"><i></i><em></em></span></header>
          <div class="cab-scr">
            <div class="cab-tr ecg"><span class="tl">II</span><span class="rh"></span><canvas></canvas></div>
            <div class="cab-tr pl"><span class="tl">PLETH</span><canvas></canvas></div>
            <div class="cab-nosig"><span></span></div>
          </div>
          <div class="cab-vit"></div>
          <footer class="cab-ft"><span class="drip"></span></footer>
        </section>
        <section class="bay-crew"></section>
      </div>
      <nav class="bay-dock"></nav>
      <div class="bay-tab"><span class="tb-hr"><i class="hb">${ic('heart')}</i><b></b></span><span class="tb-v sp"><em>SpO₂</em><b></b></span><span class="tb-v bp"><em>BP</em><b></b></span><canvas class="tb-ecg"></canvas></div>
      <div class="bay-mon"></div>
      <div class="bay-sup"></div>`;
    const q = s => root.querySelector(s);
    R = {
      root, pt: q('.bay-pt'), warns: q('.bay-warns'), cab: q('.bay-cab'), crew: q('.bay-crew'), dock: q('.bay-dock'),
      unitL: q('.u-l'), unitS: q('.u-s'), mv: q('.cab-mv'), rh: q('.cab-tr.ecg .rh'), nosig: q('.cab-nosig'), vit: q('.cab-vit'), drip: q('.cab-ft .drip'),
      ecgCv: q('.cab-tr.ecg canvas'), plCv: q('.cab-tr.pl canvas'), tab: q('.bay-tab'), tabCv: q('.tb-ecg'),
      mon: q('.bay-mon'), sup: q('.bay-sup'),
    };
  }

  /* ─────────────── traces ─────────────── */
  function startTraces() {
    stopTraces();
    ecg = NZA.vitals.Trace(R.ecgCv, { type: 'ecg', color: '#3ddc84', speed: 0.2, gain: 0.42, line: 1.6 });
    pleth = NZA.vitals.Trace(R.plCv, { type: 'pleth', color: '#3fd0ff', speed: 0.2, gain: 0.34, line: 1.4 });
    mini = NZA.vitals.Trace(R.tabCv, { type: 'ecg', color: '#3ddc84', speed: 0.22, gain: 0.5, line: 1.3 });
  }
  function stopTraces() {
    [ecg, pleth, mini].forEach(x => x && x.stop());
    ecg = null; pleth = null; mini = null;
  }

  /* ─────────────── cabin monitor card (top-right) ─────────────── */
  function vitalRows(p) {
    const v = (p && p.vitals) || {};
    const rhythm = v.rhythm || 'sinus';
    const arrest = p && (p.state === 'arrest' || ARREST.has(rhythm));
    const rate = v.ecgRate ?? v.hr;
    return [
      { k: 'hr', cls: 'hr', label: t('hr'), val: !p ? '--' : (arrest && (rhythm === 'asystole' || rhythm === 'vf')) ? '---' : num(rate), unit: 'bpm',
        alarm: p && (arrest || (rate ?? 75) > 130 || (rate ?? 75) < 45), frac: (rate || 0) / 180 },
      { k: 'spo2', cls: 'sp', label: t('spo2'), val: !p || arrest || !v.spo2 ? '--' : num(v.spo2), unit: '%', alarm: p && !arrest && (v.spo2 ?? 98) < 90, frac: ((v.spo2 || 70) - 70) / 30 },
      { k: 'nibp', cls: 'bp', label: t('nibp'), val: !p || arrest ? '--/--' : `${num(v.sys)}/${num(v.dia)}`, unit: p && !arrest ? `${t('map')} ${num(v.map)}` : 'mmHg',
        alarm: p && !arrest && (v.map ?? 80) < 60, frac: (v.map || 0) / 120 },
      { k: 'rr', cls: 'rr', label: t('rr'), val: !p ? '--' : num(v.rr), unit: '/min', alarm: p && ((v.rr ?? 14) < 8 || (v.rr ?? 14) > 28), frac: (v.rr || 0) / 40 },
      { k: 'temp', cls: 'tp', label: t('temp'), val: !p || !(p.temp ?? v.temp) ? '--' : num(p.temp ?? v.temp, 1), unit: '°C',
        alarm: p && (p.temp ?? v.temp ?? 37) < 35, frac: ((p && (p.temp ?? v.temp)) || 30) / 40 - 0.5 },
      { k: 'loss', cls: 'ls', label: t('loss'), val: !p ? '--' : num(p.lossMl || 0), unit: 'mL', alarm: p && (p.lossMl || 0) >= 1000,
        warn: p && (p.lossMl || 0) >= 400, frac: (p ? p.lossMl || 0 : 0) / 2500 },
    ];
  }
  function renderCab() {
    const p = st.patient;
    const moving = (st.speed || 0) >= 3;
    R.unitL.textContent = st.unit.label || t('bay_title');
    R.unitS.textContent = [st.unit.plate, t('bay_title')].filter(Boolean).join(' · ');
    R.mv.className = `cab-mv ${moving ? 'on' : ''}`;
    R.mv.querySelector('em').textContent = moving ? t('moving', st.speed) : t('parked');

    const v = (p && p.vitals) || {};
    const rhythm = v.rhythm || 'sinus';
    const arrest = p && (p.state === 'arrest' || ARREST.has(rhythm));
    const dead = p && p.state === 'dead';
    const rate = v.ecgRate ?? v.hr;
    R.nosig.style.display = p && !dead ? 'none' : '';
    R.nosig.querySelector('span').textContent = t('no_signal').toUpperCase();
    [ecg, mini].forEach(tr => {
      if (!tr) return;
      if (p && !dead) tr.set({ rhythm, rate: rate || 0 }); else tr.set({ rhythm: 'asystole', rate: 0 });
    });
    if (pleth) {
      if (p && !dead) pleth.set({ rhythm, rate: v.hr || 0, spo2: arrest ? 0 : (v.spo2 ?? 98), amp: Math.max(0.25, Math.min(1, (v.map ?? 80) / 85)) });
      else pleth.set({ rhythm: 'asystole', rate: 0, spo2: 0 });
    }
    R.rh.textContent = p ? `${rhythm === 'sinus' ? 'SINUS' : rhythm.toUpperCase()}${rate ? ` ${Math.round(rate)}` : ''}` : '';
    R.rh.className = `rh ${arrest ? 'bad' : ''}`;
    const drip = p ? (p.infusions || []).filter(f => !f.paused && (f.left ?? 1) > 0).reduce((a, f) => a + (Number(f.rate) || 0), 0) : 0;
    R.drip.innerHTML = drip > 0 ? `<i></i>${esc(t('drip'))} <b>${num(drip)}</b> mL/min` : `<i class="off"></i>${esc(t('no_lines'))}`;

    R.vit.innerHTML = vitalRows(p).map(x => `
      <div class="cv ${x.cls} ${p ? '' : 'nil'} ${x.alarm ? 'alarm' : ''} ${x.warn && !x.alarm ? 'warn' : ''}">
        <span class="l">${esc(x.label)}</span>
        <span class="v">${esc(x.val)}</span>
        <span class="u">${esc(x.unit)}</span>
        <i class="m"><i style="width:${(clamp(p ? x.frac || 0 : 0, 0, 1) * 100).toFixed(0)}%"></i></i>
      </div>`).join('');

    // compact cabin tab
    const hrB = R.tab.querySelector('.tb-hr b'), spB = R.tab.querySelector('.sp b'), bpB = R.tab.querySelector('.bp b');
    hrB.textContent = !p || dead ? '--' : arrest ? '---' : num(rate);
    spB.textContent = !p || arrest || !v.spo2 ? '--' : num(v.spo2);
    bpB.textContent = !p || arrest ? '--/--' : `${num(v.sys)}/${num(v.dia)}`;
    R.tab.classList.toggle('alarm', !!(p && (arrest || (v.map ?? 80) < 60)));
    R.tab.style.setProperty('--beat', `${(60 / clamp(rate || 60, 30, 200)).toFixed(2)}s`);
    R.tab.classList.toggle('still', !p || !rate || dead);
  }

  /* ─────────────── patient card (top-left) ─────────────── */
  function initials(name) {
    return String(name || '?').split(/\s+/).filter(Boolean).slice(0, 2).map(s => s[0]).join('').toUpperCase();
  }
  function triChip(tr) {
    if (!tr) return '';
    const lvl = tr.level || 3;
    return `<span class="tri p${lvl}"><i></i>P${lvl} ${esc(String(tr.label || ''))}</span>`;
  }
  function stateBlock(p) {
    if (p.state === 'arrest') {
      const r = String((p.vitals && p.vitals.rhythm) || 'asystole');
      const shock = r === 'vf' || r === 'vt';
      return `<div class="pst red"><span class="pi">${ic('heart')}</span><div><b>${esc(t('st_arrest'))}</b><small>${esc(r.toUpperCase())}${shock ? ` · <em>${esc(t('shockable'))}</em>` : ''}</small></div><div class="pc"></div></div>`;
    }
    if (p.state === 'dead') return `<div class="pst dim"><span class="pi">${ic('skull')}</span><div><b>${esc(t('st_dead'))}</b></div></div>`;
    if (p.state === 'wounded' && !p.stabilized) return `<div class="pst red"><span class="pi">${ic('drop')}</span><div><b>${esc(t('bleeding_out'))}</b><small>${esc(t('bleed'))} ${num(p.bleed, 1)} mL/min</small></div><div class="pc"></div></div>`;
    if (p.state === 'wounded') return `<div class="pst teal"><span class="pi">${ic('shield-check')}</span><div><b>${esc(t('stabilized'))}</b><small>${esc(t('st_wounded'))} · AVPU ${esc((p.vitals && p.vitals.avpu) || 'A')}</small></div></div>`;
    return `<div class="pst teal"><span class="pi">${ic('check')}</span><div><b>${esc(t('st_alive'))}</b><small>AVPU ${esc((p.vitals && p.vitals.avpu) || 'A')}</small></div></div>`;
  }
  function renderPatient() {
    const p = st.patient;
    if (!p) {
      odo = null; odoKey = '';
      R.pt.innerHTML = `<div class="pt-empty"><span class="ei">${ic('bed')}</span><b>${esc(t('no_patient'))}</b><p>${esc(t('no_patient_sub'))}</p></div>`;
      R.pt.classList.add('empty');
      return;
    }
    R.pt.classList.remove('empty');
    const inj = p.injuries || [];
    const shown = inj.slice(0, 4);
    const more = Math.max(0, (p.injuryCount || inj.length) - shown.length);
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
    const bloodPct = clamp(Number(p.bloodPct ?? 100), 0, 100);
    const bTone = bloodPct < 70 ? 'red' : bloodPct < 85 ? 'amber' : 'teal';
    const C = 2 * Math.PI * 20;
    const key = `${p.state}|${p.stabilized}`;
    const keepOdo = odo && odoKey === key && R.pt.querySelector('.pc .odo');
    const oldOdo = keepOdo ? R.pt.querySelector('.pc .odo') : null;
    R.pt.innerHTML = `
      <div class="pt-head">
        <span class="av ${bTone}"><svg viewBox="0 0 48 48"><circle class="b" cx="24" cy="24" r="20"/><circle class="f" cx="24" cy="24" r="20" stroke-dasharray="${C.toFixed(1)}" stroke-dashoffset="${(C * (1 - bloodPct / 100)).toFixed(1)}"/></svg><b>${esc(initials(p.name))}</b></span>
        <div class="who"><span class="k">${esc(t('patient'))}</span><b>${esc(p.name || t('patient'))}</b><span>${esc([p.sex ? String(p.sex).toUpperCase() : '', p.age, p.bloodType].filter(x => x !== undefined && x !== null && x !== '').join(' · '))}</span></div>
        ${triChip(p.triage)}
      </div>
      ${stateBlock(p)}
      <div class="pt-body">
        <div class="pt-inj"><h4>${esc(t('injuries'))}<span>${p.injuryCount || inj.length}</span></h4>
          ${shown.length ? shown.map(i => {
            const tone = i.status === 'treated' || i.status === 'healing' ? 'teal' : (SEV_TONE[i.severity || 1] || 'amber');
            return `<div class="inj" data-t="${tone}">
              <div class="tx"><b>${esc(i.typeLabel || i.type)}</b><span>${esc(i.regionLabel || i.region)}</span></div>
              ${i.bleed > 0 ? `<span class="bl">${num(i.bleed, 1)}<i>mL/min</i></span>` : `<span class="stt ${esc(i.status)}">${esc(i.status || '')}</span>`}
            </div>`;
          }).join('') + (more ? `<div class="inj-more">${esc(t('more', more))}</div>` : '')
          : `<div class="none">${esc(t('no_injuries'))}</div>`}
        </div>
      </div>
      <div class="pt-meters">
        <div class="pm"><span>${esc(t('bleed'))}</span><b class="${p.bleed >= 10 ? 'red' : p.bleed > 1 ? 'amber' : 'teal'}">${num(p.bleed, 1)}<i>mL/min</i></b>
          ${NZA.ui.meterHTML({ value: Math.min(1, (p.bleed || 0) / 60), tone: p.bleed >= 10 ? 'red' : p.bleed > 1 ? 'amber' : '' })}</div>
        <div class="pm"><span>${esc(t('blood'))}</span><b class="${bTone}">${num(bloodPct)}<i>%</i></b>
          ${NZA.ui.meterHTML({ value: bloodPct / 100, tone: bloodPct < 70 ? 'red' : bloodPct < 85 ? 'amber' : '', mark: 0.7 })}</div>
      </div>
      <div class="pt-sec"><h4>${esc(t('lines'))}</h4>
        ${inf.length ? `<div class="lines">${inf.map(f => {
          const tot = f.ml || 500, left = Math.max(0, f.left ?? tot);
          const nm = f.kind === 'blood' ? `${t('blood')} ${f.type || ''}`.trim() : f.kind === 'txa' ? 'TXA' : f.kind === 'plasma' ? 'Plasma' : 'Saline';
          return `<div class="line ${f.kind} ${f.paused ? 'paused' : ''}">
            ${bagGlyph(left / tot, f.kind === 'blood' ? 'blood' : f.kind === 'plasma' ? 'plasma' : 'clear')}
            <div class="tx"><b>${esc(nm)}</b><span>${num(left)} / ${num(tot)} mL</span></div>
            <span class="rt">${f.paused ? esc(t('paused').toUpperCase()) : `${num(f.rate)}<i>mL/min</i>`}</span>
          </div>`;
        }).join('')}</div>` : `<div class="none">${esc(t('no_lines'))}</div>`}
      </div>
      ${chips.length ? `<div class="pt-dev">${chips.map(c => `<span class="dchip">${ic(c[0])}${esc(c[1])}</span>`).join('')}</div>` : ''}`;
    const pc = R.pt.querySelector('.pc');
    const showClock = pc && ((p.state === 'wounded' && !p.stabilized && p.clock !== undefined && p.clock !== null) || (p.state === 'arrest' && p.clock));
    if (showClock) {
      const tone = p.state === 'arrest' || p.clock < 60 ? 'red' : '';
      if (oldOdo) { pc.appendChild(oldOdo); odo.set(NZA.fmt.time(p.clock)); odo.tone(tone); }
      else { odo = NZA.ui.FlipClock(pc, { value: NZA.fmt.time(p.clock), small: true, tone }); odoKey = key; }
    } else { odo = null; odoKey = ''; }
  }

  /* ─────────────── alerts (under the patient card) ─────────────── */
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
    R.warns.classList.toggle('many', list.length > 3);
    R.warns.innerHTML = list.map(x => `
      <div class="alrt ${x.tone} ${before.has(x.id) ? 'still' : ''}" data-id="${x.id}">
        <span class="ai">${ic(x.icon)}</span><div><b>${esc(x.title)}</b><p>${esc(x.text)}</p></div>
      </div>`).join('');
    if (list.some(x => x.tone === 'error' && !before.has(x.id)) && NZA.cfg.sounds !== false) NZA.audio.alarm(1);
  }

  /* ─────────────── crew & action dock ─────────────── */
  function renderCrew() {
    const crew = st.crew || [];
    R.crew.style.display = crew.length ? '' : 'none';
    R.crew.innerHTML = `<h4>${esc(t('crew'))}<span>${crew.length}</span></h4><div class="cm-l">` + crew.map(c => `
      <div class="cm ${c.sid === st.me ? 'me' : ''}">
        <span class="av">${esc(initials(c.name))}</span>
        <div class="tx"><b>${esc(c.name)}</b>${c.grade ? `<span>${esc(c.grade)}</span>` : ''}</div>
        ${c.sid === st.me ? `<span class="me-t">${esc(t('you'))}</span>` : ''}
      </div>`).join('') + '</div>';
  }
  function renderDock() {
    const tools = [['examine', 'stetho'], ['supplies', 'box'], ['ivstand', 'iv'], ['monitor', 'monitor']];
    const slot = (id, icon, extra) => {
      const off = st.tools[id] === false || (!st.patient && (id === 'examine' || id === 'ivstand'));
      const on = (id === 'monitor' && st.bigMon) || (id === 'supplies' && win);
      return `<button class="dk ${off ? 'off' : ''} ${on ? 'on' : ''} ${extra || ''}" data-id="${id}">
        <span class="dl">${esc(t(id))}</span>
        <span class="ds"><span class="di">${ic(icon)}</span><kbd>${esc(keyCap(st.keys[id]))}</kbd></span>
      </button>`;
    };
    R.dock.innerHTML = tools.map(([id, icon]) => slot(id, icon)).join('') + '<i class="dk-sep"></i>' + slot('exit', 'door', 'exit');
    R.dock.querySelectorAll('.dk').forEach(b => b.addEventListener('click', () => {
      if (b.dataset.id === 'supplies' && win) return closeSupplies(true);
      NZA.post('bay:action', { id: b.dataset.id });
      if (!NZA.inGame) localAction(b.dataset.id);
    }));
  }

  /* ─────────────── big monitor (F4 fallback): industrial shell, generic model code ─────────────── */
  function setBigMonitor(on) {
    st.bigMon = !!on;
    if (R && R.root) R.root.classList.toggle('bigmon', st.bigMon);
    if (!st.bigMon) {
      if (bigMon) { bigMon.destroy(); bigMon = null; }
      R.mon.innerHTML = '';
      R.mon.classList.remove('on');
      renderDock();
      return;
    }
    R.mon.classList.add('on');
    R.mon.innerHTML = `<div class="hx">
      <i class="hx-sc a"></i><i class="hx-sc b"></i><i class="hx-sc c"></i><i class="hx-sc d"></i>
      <div class="hx-head"><span class="hx-model"><b>TM-6</b><span>${esc(t('mon_model'))}</span></span><span class="hx-stat"><span class="hx-led"><span class="dev-led ${st.patient ? '' : 'off'}"></span></span><em>${st.patient ? 'RUN' : 'STBY'}</em></span></div>
      <div class="dev-screen"><div class="host"></div></div>
      <div class="hx-foot"><span class="hx-warn"><i></i>${esc(t('mon_warn'))}</span><span class="hx-keys"><kbd>${esc(keyCap(st.keys.monitor || 'F4'))}</kbd>${esc(t('monitor'))}</span><span class="hx-sn">SN 6620-1184</span></div>
    </div>`;
    bigMon = NZA.vitals.Monitor(R.mon.querySelector('.host'), { traces: ['ecg', 'pleth', 'resp'], height: 246, beep: false, title: 'ADULT · CABIN' });
    updateBigMonitor();
    renderDock();
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

  /* ─────────────── supplies window: shelf rack (grouped bins, stock pips) ─────────────── */
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
        width: '1040px', height: '700px',
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
    renderDock();
  }
  function shelfLetter(i) { return String.fromCharCode(65 + i); }
  function renderSupplies() {
    if (!win) return;
    const all = (st.sup && st.sup.items) || [];
    const items = supItems();
    const taken = all.reduce((a, i) => a + (i.taken || 0), 0);
    const left = all.reduce((a, i) => a + (i.left || 0), 0);
    const cap = all.reduce((a, i) => a + (i.max || 0), 0) || 1;
    const reset = st.sup && st.sup.resetIn;
    const shift = (st.sup && st.sup.shiftLength) || 14400;
    const C = 2 * Math.PI * 17;
    win.setMid(`<span class="nz-dot"></span><p>${reset ? `<b>${esc(t('sup_reset', fmtDur(reset)))}</b> · ` : ''}${esc(t('sup_taken'))} <b>${taken}</b></p>`);
    const maxTake = (st.sup && st.sup.maxPerTake) || 10;
    const cats = (st.sup && st.sup.categories) || [];
    const order = cats.map(c => c.id);
    const groups = [];
    items.forEach(i => { let g = groups.find(x => x.id === i.category); if (!g) { g = { id: i.category, items: [] }; groups.push(g); } g.items.push(i); });
    groups.sort((a, b) => (order.indexOf(a.id) + 99) % 99 - (order.indexOf(b.id) + 99) % 99);
    const ring = (frac, tone, inner) => `<span class="sr ${tone}"><svg viewBox="0 0 40 40"><circle class="b" cx="20" cy="20" r="17"/><circle class="f" cx="20" cy="20" r="17" stroke-dasharray="${C.toFixed(1)}" stroke-dashoffset="${(C * (1 - clamp(frac, 0, 1))).toFixed(1)}"/></svg>${inner}</span>`;
    const bin = i => {
      const q = Math.max(1, Math.min(st.qty[i.key] || 1, Math.max(1, Math.min(i.left, maxTake))));
      const used = i.left <= 0;
      const pct = i.max ? i.left / i.max : 0;
      const pips = Array.from({ length: Math.min(i.max || 0, 12) }, (_, k) => {
        const per = (i.max || 1) / Math.min(i.max || 1, 12);
        return `<i class="${k < Math.round(i.left / per) ? 'on' : ''}"></i>`;
      }).join('');
      return `<div class="sup ${used ? 'used' : ''} ${pct < 0.34 && !used ? 'low' : ''}" data-key="${esc(i.key)}">
        <div class="sup-img">${i.img ? `<img src="${esc(i.img)}" alt="" onerror="this.remove()">` : ''}<span class="fb">${ic(CAT_ICON[i.category] || 'box')}</span></div>
        <div class="sup-tx"><b>${esc(i.label)}</b><span>${esc(used ? t('sup_used') : t('sup_left', i.left, i.max))}</span></div>
        <div class="sup-st"><span class="pips">${pips}</span>${i.have ? `<em>${esc(t('sup_have', i.have))}</em>` : '<em class="z"></em>'}</div>
        <div class="sup-act">
          <div class="step"><button class="mn" ${used || q <= 1 ? 'disabled' : ''}>${ic('minus')}</button><span>${used ? 0 : q}</span><button class="pl" ${used || q >= Math.min(i.left, maxTake) ? 'disabled' : ''}>${ic('plus')}</button></div>
          <button class="btn-teal btn-sm tk" ${used ? 'disabled' : ''}>${esc(t('sup_take'))}</button>
          <button class="btn-line btn-sm ta" title="${esc(t('sup_take_all', Math.max(1, Math.min(i.left, maxTake))))}" ${used || i.left <= 1 ? 'disabled' : ''}>${ic('download')}<span>+${used ? 0 : Math.max(1, Math.min(i.left, maxTake))}</span></button>
        </div>
      </div>`;
    };
    win.main.innerHTML = `
      <div class="w-head"><div><h1>${esc(st.supCat === 'all' ? t('sup_all') : catLabel(st.supCat))}</h1><p>${esc(t('sup_head'))}</p></div></div>
      <div class="sup-sum">
        <div class="ss">${ring(left / cap, left / cap < 0.34 ? 'amber' : 'teal', `<b>${Math.round((left / cap) * 100)}</b>`)}<div><span>${esc(t('sup_left_total'))}</span><b>${left}<i>/ ${cap}</i></b></div></div>
        <div class="ss">${ring(taken / cap, 'white', ic('check'))}<div><span>${esc(t('sup_taken'))}</span><b>${taken}</b></div></div>
        <div class="ss">${ring(reset ? 1 - reset / shift : 0, 'teal', ic('clock'))}<div><span>${esc(t('sup_reset', '')).replace(/\s+$/, '')}</span><b>${reset ? esc(fmtDur(reset)) : '—'}</b></div></div>
      </div>
      <div class="sup-rack nza-scroll">${groups.map(g => {
        const letter = shelfLetter(Math.max(0, order.indexOf(g.id)));
        return `<div class="shelf">
          <div class="sh-lbl"><span class="sh-l">${esc(letter)}</span><b>${esc(catLabel(g.id))}</b><i></i><em>${esc(t('sup_shelf', letter))} · ${g.items.length}</em></div>
          ${g.items.map(bin).join('')}
        </div>`;
      }).join('')}</div>`;
    win.main.querySelectorAll('.sup').forEach(card => {
      const key = card.dataset.key;
      const item = all.find(i => i.key === key);
      if (!item) return;
      const capN = Math.max(1, Math.min(item.left, maxTake));
      const setQ = n => { st.qty[key] = Math.max(1, Math.min(capN, n)); NZA.audio.tick(); renderSupplies(); };
      card.querySelector('.mn').onclick = () => setQ((st.qty[key] || 1) - 1);
      card.querySelector('.pl').onclick = () => setQ((st.qty[key] || 1) + 1);
      card.querySelector('.tk').onclick = () => take(key, Math.min(st.qty[key] || 1, capN), card);
      card.querySelector('.ta').onclick = () => take(key, capN, card);
    });
  }
  async function take(key, count, card) {
    if (card) card.classList.add('busy');
    const res = await NZA.post('bay:take', { key, count });
    if (card) card.classList.remove('busy');
    if (res && res.ok && res.list) {
      const scroll = win && win.main.querySelector('.sup-rack') ? win.main.querySelector('.sup-rack').scrollTop : 0;
      st.sup = Object.assign({}, st.sup, res.list);
      st.qty[key] = 1;
      renderSupplies();
      const rack = win && win.main.querySelector('.sup-rack'); if (rack) rack.scrollTop = scroll;
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
    renderDock();
    if (notify) NZA.post('bay:supplies', { open: false });
  }

  /* ─────────────── compact mode while procedures run ─────────────── */
  let forceCompact = false;
  function checkCompact() {
    const busy = forceCompact || NZA.stack.some(n => !PASSIVE.has(n));
    R.root.classList.toggle('compact', busy);
  }

  /* ─────────────── preview-only local actions ─────────────── */
  function localAction(id) {
    if (id === 'monitor') setBigMonitor(!st.bigMon);
    if (id === 'supplies') NZA.apps.bay.msg.supplies(demoSupplies());
    if (id === 'exit') NZA.close(APP);
  }

  function renderAll() {
    renderCab(); renderPatient(); renderWarnings(); renderCrew(); renderDock(); updateBigMonitor();
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
      lastWarn = ''; odo = null; odoKey = '';
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
        renderCab(); renderPatient(); renderWarnings(); updateBigMonitor();
        if (had !== !!st.patient) renderDock();
      },
      crew(c) { if (!st) return; st.crew = Array.isArray(c) ? c : []; renderCrew(); },
      tick(d) { if (!st) return; st.speed = Math.round(Number(d.speed) || 0); if (d.plate) st.unit.plate = d.plate; renderCab(); renderWarnings(); },
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
        if (!it || it.left <= 0) return { ok: false, msg: 'That shelf is empty for this shift.' };
        const n = Math.min(count, it.left);
        it.left -= n; it.taken += n; it.have = (it.have || 0) + n;
        NZA.toast({ title: 'Supplies', message: `Pocketed ${n} × ${it.label}.` });
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
      if (demo === 'compact') { forceCompact = true; checkCompact(); }
      // live demo: vitals drift, the clock runs
      if (demo !== 'empty') {
        setInterval(() => {
          const p = st && st.patient;
          if (!p || p.state === 'dead') return;
          if (p.state === 'wounded' && !p.stabilized && p.clock > 0) p.clock -= 1;
          if (p.state === 'arrest' && p.clock) p.clock += 1;
          if (p.state !== 'arrest') {
            const base = p.stabilized ? 104 : 124;
            p.vitals.hr = Math.round(base + Math.sin(Date.now() / 3000) * 4);
            p.vitals.ecgRate = p.vitals.hr;
            p.vitals.spo2 = (p.stabilized ? 97 : 93) + (Math.random() < 0.3 ? 1 : 0);
            p.infusions.forEach(f => { if (!f.paused) f.left = Math.max(0, f.left - f.rate / 60); });
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
    const capN = Math.max(1, Math.min(it.left, (st.sup && st.sup.maxPerTake) || 10));
    st.qty[it.key] = Math.max(1, Math.min(capN, (st.qty[it.key] || 1) + dir));
    renderSupplies();
    return true;
  }

  /* ─────────────── demo data (browser preview only) ─────────────── */
  function demoPatient(kind) {
    const arrest = kind === 'arrest', stable = kind === 'stable';
    return {
      name: 'Lena Okafor', sex: 'f', age: 34, bloodType: 'O-', state: arrest ? 'arrest' : 'wounded', stabilized: stable,
      clock: arrest ? 214 : 142, triage: { level: 1, code: 'P1', label: 'Critical', colour: '#e5484d' },
      vitals: arrest
        ? { hr: 0, ecgRate: 0, sys: 0, dia: 0, map: 0, spo2: 0, rr: 0, temp: 35.1, rhythm: 'vf', avpu: 'U' }
        : stable ? { hr: 104, ecgRate: 104, sys: 108, dia: 66, map: 80, spo2: 97, rr: 18, temp: 36.2, rhythm: 'sinus', avpu: 'A' }
        : { hr: 126, ecgRate: 126, sys: 92, dia: 58, map: 69, spo2: 93, rr: 24, temp: 34.6, rhythm: 'stach', avpu: 'V' },
      temp: arrest ? 35.1 : stable ? 36.2 : 34.6, bleed: stable ? 1.2 : 14.8, bloodPct: stable ? 84 : 76, lossMl: 1240, access: true,
      injuries: [
        { region: 'chest', regionLabel: 'Chest', type: 'gunshot', typeLabel: 'Gunshot wound', severity: 3, status: 'open', bleed: 9.2 },
        { region: 'l_upper_arm', regionLabel: 'Left upper arm', type: 'laceration', typeLabel: 'Deep laceration', severity: 2, status: 'controlled', bleed: 3.1 },
        { region: 'abdomen', regionLabel: 'Abdomen', type: 'internal', typeLabel: 'Internal bleeding', severity: 3, status: 'open', bleed: 2.5 },
        { region: 'r_lower_leg', regionLabel: 'Right lower leg', type: 'fracture', typeLabel: 'Fracture', severity: 3, status: 'treated', bleed: 0 },
        { region: 'head', regionLabel: 'Head', type: 'abrasion', typeLabel: 'Abrasion', severity: 1, status: 'open', bleed: 0 },
      ],
      injuryCount: 5,
      infusions: stable
        ? [{ kind: 'blood', ml: 450, left: 286, rate: 60 }, { kind: 'saline', ml: 500, left: 140, rate: 80 }]
        : [{ kind: 'saline', ml: 500, left: 320, rate: 125 }, { kind: 'txa', ml: 100, left: 64, rate: 10 }],
      devices: { iv: 'iv', oxygen: true, collar: true, tq: 1, splints: 1 },
      surgery: true, bloodRunning: stable,
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
      items, resetIn: 11520, maxPerTake: 10, shiftLength: 14400,
      categories: [{ id: 'wound', icon: 'bandage' }, { id: 'fluids', icon: 'iv' }, { id: 'airway', icon: 'lungs' }, { id: 'ortho', icon: 'splint' }, { id: 'meds', icon: 'pill' }],
    };
  }
})();
