/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · CPR & defibrillator (app 'cpr')

   Opened by client/modules/cpr.lua with
     { view, keys, cfg, locale, easy }        view = server code view (server/modules/cpr.lua)
   Lua → JS actions
     open(data)            start / join a code
     state(view)           server view (every change, ≥ 1/s)
     event(ev)             one-off moments { kind, ... } (advice, charging, charged, shock, rosc, swap ...)
     ended(summary)        your part in the code is over → debrief, Enter closes
     anchors               world positions of the pad sites (padR, padL) - handled by the router
   JS → Lua (NUI callbacks, all reply { ok })
     cpr:press   {}                                  a compression started (medic anim sync)
     cpr:report  { n, timing, depth, recoil, rate, done }   compressions since the last report (≤ 1/s)
     cpr:hands   {}                                  the compressor touched the chest while "stand clear"
     cpr:breathStart {} / cpr:breath { hold }        rescue breath (seconds Space was held)
     cpr:action  { name, data }                      pads analyse charge disarm shock energy mode adrenaline swap pulse
                                                     → the server reply { ok, err?, msg?, ... }
     cpr:leave   {}                                  stop / leave the code (ESC hold)
     cpr:close   (router)                            app closed (after the debrief)
   ═══════════════════════════════════════════════════════════ */
(() => {
  const APP = 'cpr';
  const clamp = (n, a, b) => Math.max(a, Math.min(b, n));
  const esc = s => NZA.esc(s);
  const icon = n => NZA.icon(n);
  const now = () => performance.now();

  /* ─────────────── strings (English fallbacks; Lua sends NZA.LocaleTable('cpr')) ─────────────── */
  const EN = {
    // device face (generic labelling only: type + model code + warning sticker, no brand)
    model: 'DF-7', dev_type: 'MONITOR · DEFIBRILLATOR', dev_ref: 'BIPHASIC · 360 J MAX · REF 4107-02', dev_warn: 'DANGER · HIGH VOLTAGE · STAND CLEAR',
    age_adult: 'ADULT', age_child: 'CHILD', pads_on: 'PADS OK', pads_off: 'NO PADS', ecg: 'ECG', lead: 'II · ×1.0 · 25 mm/s', ring_k: 'ELAPSED',
    tr_fb: 'CPR', tr_co2: 'CO₂', hr: 'HR', bpm: 'bpm', energy: 'Energy', shocks: 'Shocks', mmhg: 'mmHg',
    per_min: 'cpm',
    rhs_shock: 'SHOCKABLE', rhs_noshock: 'NON-SHOCKABLE', rhs_perf: 'PERFUSING', rhs_none: 'NO SIGNAL',
    connect_pads: 'CONNECT PADS', no_defib: 'NO DEFIBRILLATOR', analysing: 'ANALYSING', anl_sub: 'HANDS OFF',
    aed: 'AED', manual: 'MAN', mode_aed: 'AED', mode_manual: 'MANUAL', energy_select: 'ENERGY', charge: 'CHARGE', disarm: 'DISARM', shock: 'SHOCK', due: 'DUE', auto: 'AUTO',
    il_cycle: 'Cycle %s', il_adr: 'Adrenaline', il_none: 'none', cb_to: 'TO RHYTHM CHECK', cb_now: 'ANALYSE NOW',
    sk_pads: 'PADS', sk_analyse: 'ANALYSE', sk_adren: 'DRUG', sk_swap: 'SWAP', sk_pulse: 'PULSE',
    rh_vf: 'VF', rh_vt: 'VT', rh_pea: 'PEA', rh_asystole: 'ASYSTOLE', rh_sinus: 'SINUS', rh_stach: 'S.TACH', rh_sbrady: 'S.BRADY', rh_afib: 'AFIB', rh_rosc: 'ROSC', rh_none: '— — —',
    // device message line (what the unit says / shows; no keyboard keys on the device)
    p_compress: 'PUSH HARD · PUSH FAST', p_easy: 'AUTO-PACED CPR', p_partner: 'CPR IN PROGRESS', p_breath: 'GIVE BREATH %s OF %s',
    p_handsoff: 'PAUSE · BREATHS', p_analyse: 'ANALYSING · DO NOT TOUCH THE PATIENT', p_advised: 'SHOCK ADVISED · CHARGE NOW', p_charging: 'CHARGING TO %s J',
    p_charged: 'STAND CLEAR · PRESS SHOCK', p_rosc: 'ROSC · CHECK THE PULSE', p_noshock: 'NO SHOCK ADVISED · RESUME CPR', p_check: 'RHYTHM CHECK DUE · ANALYSE',
    p_continuous: 'CONTINUOUS CPR · VENTILATED', p_waitbreath: 'STOP · BREATHS NEXT', p_nopads: 'CONNECT THE PADS', p_nodefib: 'CPR ONLY · BRING A DEFIBRILLATOR',
    // team card
    t_arrest: 'Cardiac arrest', t_resp: 'Respiratory arrest', t_rosc: 'Pulse back (ROSC)', down: 'Down', ccf: 'Hands-on', adren: 'Adrenaline',
    role_comp: 'COMPRESSIONS', role_air: 'AIRWAY · DEFIB · DRUGS', you: 'you', nobody: 'Nobody yet · you give the breaths (30:2)', fatigue: 'FATIGUE',
    join_hint: 'A second medic can pick Join CPR on the patient to run the airway and swap with you.',
    causes: 'Reversible causes (Hs & Ts)', log: 'Code log', npc: 'Unknown',
    c_hypovolemia: 'Hypovolaemia', c_hypoxia: 'Hypoxia', c_hypothermia: 'Hypothermia', c_tension: 'Tension pneumo', c_tamponade: 'Tamponade', c_toxins: 'Toxins',
    // pads (drawn on the device screen)
    pads_title: 'Pad placement', pads_text: 'Drag each pad onto the chest. **Sternum**: under the right collarbone. **Apex**: left side, below the armpit. {%s} sticks both.',
    pad_r: 'STERNUM', pad_l: 'APEX', pad_wrong: 'Wrong spot: that is where the %s pad goes.', pad_miss: 'Drop the pad on its dashed marker on the chest.', pad_ok: '%s pad on.', pads_done: 'Both pads on. Reading the rhythm.',
    // procedure HUD
    pp_compress: 'Compress the chest', pp_compress_t: 'Press {%s} each time the hand crosses the top. **30 pushes, then 2 breaths**, and again, until the rhythm check. CPR ends when the pulse comes back.',
    pp_compress_easy: 'Easy mode: press {%s} once and the compressions keep time by themselves.',
    pp_partner: 'Your partner is compressing', pp_partner_t: 'Put the pads on, analyse every 2 minutes, charge, shock and give adrenaline. Swap with {%s} when they tire.',
    pp_breaths: 'Give %s breaths', pp_breaths_1: 'Give the last breath', pp_breaths_bvm: 'Hold {%s} about 1 second per breath on the bag and watch the chest rise.',
    pp_breaths_mouth: 'No bag-valve mask: mouth to mouth. Hold {%s} a little longer (1.3 s) per breath; it moves less air.',
    pp_breaths_wait: 'Hands off the chest', pp_breaths_wait_t: 'Your partner gives %s breaths. Be ready to push again.',
    pp_analyse: 'Reading the rhythm', pp_analyse_t: 'Everybody hands off. One push now spoils the analysis.',
    pp_advised: 'Shock advised', pp_advised_t: 'Keep pushing while it charges: {%s}. Then everybody stands clear.',
    pp_advised_man: 'Shockable rhythm', pp_noshock: 'No shock advised', pp_noshock_t: 'Back on the chest now. Think about the reversible causes and adrenaline.',
    pp_charging: 'Charging to %s J', pp_charging_t: 'Keep pushing until the device is ready.',
    pp_charged: 'Stand clear!', pp_charged_t: 'Hands off the patient. Shock with {%s} or disarm with {%s}.',
    pp_rosc: 'Pulse is back', pp_rosc_t: 'Feel the carotid with {%s}. Leave the pads on: they can arrest again.',
    pp_cont: 'Continuous compressions', pp_cont_t: 'Intubated and ventilated: push without pauses, {%s} with the metronome.',
    s_depth: 'Depth', s_recoil: 'Recoil', s_quality: 'Quality', s_vent: 'Ventilation', s_breaths: 'Breaths', s_etco2: 'EtCO₂', w_rate: 'Rate', w_cycle: 'Cycle %s',
    cap_check: 'Rhythm check in %s', cap_due: 'Rhythm check due: analyse', cap_adr_due: 'Adrenaline due', tag_cycle: 'CPR · cycle %s', tag_easy: 'CPR · easy mode',
    st_cycle: 'CPR · 30 pushes, 2 breaths', st_analyse: 'Rhythm check', st_shock: 'Shock if advised', st_rosc: 'Pulse back',
    nx_pads: 'Put the pads on {%s}. Without them there is no rhythm check.', nx_no_defib: 'No defibrillator here: bring one (or a trauma kit) for the rhythm check.',
    nx_check: 'Rhythm check in %s', nx_due: 'Rhythm check now: press {%s}', nx_breaths: '30 more pushes · rhythm check in %s',
    nx_analyse: 'Shock if advised, otherwise straight back to CPR', nx_shock: 'Straight back to CPR after the shock',
    tool_pads: 'Pads', tool_analyse: 'Analyse', tool_charge: 'Charge', tool_disarm: 'Disarm', tool_shock: 'Shock', tool_adren: 'Adrenaline', tool_swap: 'Swap', tool_pulse: 'Pulse',
    hint_causes: 'Hs & Ts', hint_energy: 'energy', hint_orbit: 'orbit', hint_rmb: 'Right click', abort: 'Stop CPR',
    // metronome card (in the procedure column)
    m_title: 'Metronome', m_depth: 'Depth', m_timing: 'Timing · this set', m_early: 'Early', m_on: 'In time', m_late: 'Late', m_recoil: 'Recoil',
    m_breaths: 'Breaths', m_rise: 'Chest rise', m_short: 'short', m_long: 'long', m_ok: 'good', m_wait: 'waiting',
    l_perfect: 'SPOT ON', l_good: 'GOOD', l_early: 'EARLY', l_late: 'LATE', l_off: 'MISSED', l_shallow: 'DEEPER', l_lean: 'LIFT OFF',
    l_handsoff: 'Hands off · breaths',
    // metronome card status panel (hands-off moments and the partner view)
    o_analyse: 'Hands off', o_analyse_s: 'The unit is reading the rhythm', o_charging: 'Charging · %s J', o_charging_s: 'Keep pushing until it is ready',
    o_charged: 'Charged · %s J', o_charged_s: 'Stand clear · %s s left', o_handsoff: 'Hands off', o_handsoff_s: 'Your partner gives the breaths',
    o_rosc: 'Pulse is back', o_rosc_s: 'Stop pushing · feel the carotid', o_partner: '%s', o_partner_s: 'Compressing · %s · quality %s',
    d_ok: '5–6 cm', d_low: 'too shallow', d_lean: 'leaning',
    // flashes / voice
    f_hands: 'Hands off! The device is charged.', f_motion: 'Motion: the analysis needs everyone off the patient.', f_partner: 'Your partner is compressing.',
    f_waitbreath: 'Stop: breaths come next.', f_breath_short: 'Too short: the chest barely rose.', f_breath_long: 'Too long: air went into the stomach.', f_breath_ok: 'Good breath: chest rose.',
    f_no_defib: 'No defibrillator here: bring one (or a trauma kit), or work in the ambulance / hospital.', f_pulse_yes: 'Carotid pulse %s/min%s.', f_pulse_weak: ', weak', f_pulse_no: 'No pulse. Continue CPR.',
    f_idle: 'Keep going! Every second without compressions counts.', f_aed_energy: 'AED mode chooses the energy itself.',
    v_analyse: 'Analysing heart rhythm. Do not touch the patient.', v_shock: 'Shock advised. Charging.', v_shock_man: 'Shockable rhythm.', v_charged: 'Stand clear. Press the flashing shock button now.',
    v_noshock: 'No shock advised. Start CPR.', v_motion: 'Motion detected. Stop all motion.', v_breaths: 'Give two breaths.', v_check: 'Two minutes. Stop CPR and analyse.', v_adr: 'Consider adrenaline.',
    v_shocked: 'Shock delivered. Start CPR.', v_rosc: 'Pulse detected.',
    // banners
    b_analyse: 'ANALYSING', b_analyse_s: 'Do not touch the patient', b_shock: 'SHOCK ADVISED', b_shock_s: '%s · charge the defibrillator', b_clear: 'STAND CLEAR', b_clear_s: 'Everybody off the patient',
    b_shocked: 'SHOCK DELIVERED', b_shocked_s: '%s J · shock %s · resume CPR now', b_noeffect: 'NO EFFECT', b_noeffect_s: 'That rhythm cannot be shocked',
    b_noshock: 'NO SHOCK ADVISED', b_noshock_s: '%s · continue CPR', b_rosc: 'ROSC', b_rosc_s: 'Return of spontaneous circulation', b_motion: 'MOTION DETECTED', b_motion_s: 'Analysis aborted · analyse again',
    b_rearrest: 'RE-ARREST', b_rearrest_s: 'No pulse again · restart compressions', b_zapped: 'YOU WERE SHOCKED', b_zapped_s: 'You touched the patient during the shock',
    b_induced: 'VF INDUCED', b_induced_s: 'You shocked a patient with a pulse', b_arrested: 'CARDIAC ARREST', b_arrested_s: 'The heart has stopped · continue CPR',
    // events
    e_joined: '%s joined the code: airway, pads and drugs.', e_left: '%s left the code.', e_promoted: '%s left: you are alone now (30:2).', e_swap: 'Roles swapped: %s compresses now.',
    e_adren: 'Adrenaline 1 mg given (dose %s).', e_missed: '%s breath(s) missed: compressions resume.', e_changed: 'The rhythm changed after the shock.',
    // debrief
    d_title_rosc: 'ROSC achieved', d_title_death: 'The patient died', d_title_stopped: 'CPR stopped', d_title_left: 'You left the code', d_title_breathing: 'Breathing again',
    d_sub: '%s · %s', d_duration: 'Duration', d_comp: 'Compressions', d_quality: 'Quality', d_ccf: 'Hands-on', d_vent: 'Breaths', d_shocks: 'Shocks', d_adr: 'Adrenaline', d_protocol: 'Protocol',
    d_done: 'Done', d_score: 'Score', d_kicker: 'Code summary', d_path: 'Rhythm', d_tips: 'Notes for next time',
    dv_A: 'STRONG', dv_B: 'SOLID', dv_C: 'FAIR', dv_D: 'WEAK', dv_F: 'POOR',
    fb_rosc: 'Pulse back after %s of resuscitation.', fb_quality: 'Compression quality %s%%: press on the metronome and let the chest come all the way back up.',
    fb_ccf: 'Hands-on time %s%%: keep every pause under 10 seconds (aim for 80%% or more).', fb_vent: 'Breaths %s%%: hold about 1 second and watch the chest rise.',
    fb_protocol: 'Protocol: shocks on a non-shockable rhythm, long pauses before a shock or touching the patient during the shock cost points.',
    fb_adr: 'No adrenaline was given: every 3 to 5 minutes, early in non-shockable rhythms.', fb_good: 'Solid CPR: good rate, depth and recoil.',
    r_rosc: 'ROSC', r_death: 'died', r_stopped: 'stopped', r_left: 'left', r_offline: 'disconnected', r_far: 'walked away', r_down: 'you went down', r_perm: 'no permission',
    r_gone: 'patient gone', r_revived: 'revived', r_breathing: 'breathing on their own', r_error: 'error', r_replaced: 'started another code',
  };
  let L = {};
  const T = (k, ...a) => {
    let s = L[k] !== undefined ? L[k] : (EN[k] !== undefined ? EN[k] : k);
    a.forEach(v => { s = s.replace('%s', v); });
    return s.replace(/%%/g, '%');
  };

  /* ─────────────── defaults (mirrors Config.Cpr; Lua sends the real values) ─────────────── */
  const DEF_KEYS = { compress: 'Space', pads: 'KeyP', analyse: 'KeyA', charge: 'KeyC', shock: 'KeyS', energyUp: 'KeyE', energyDown: 'KeyQ', adrenaline: 'KeyD', swap: 'KeyX', pulse: 'KeyF', causes: 'KeyH', mode: 'KeyM', disarm: 'KeyZ' };
  const DEF_CFG = {
    target: 110, rateMin: 100, rateMax: 120, perSet: 30, perfect: 0.085, good: 0.17, pressMin: 0.07, pressMax: 0.30, metronome: true, idleWarn: 1.6,
    breathHold: 1.0, tooShort: 0.55, tooLong: 1.7, mouthSlower: 1.25, mouthToMouth: true, analyseTime: 4, cycleLength: 120, checkGrace: 20, chargedFor: 25,
    energies: [120, 150, 200, 250, 300, 360], aedEnergies: [200, 300, 360], snap: 70, sounds: true,
  };
  const SHOCKABLE = { vf: true, vt: true };
  const ARREST_RH = { vf: true, vt: true, pea: true, asystole: true };
  const keyLabel = c => (!c ? '' : c === 'Space' ? 'Space' : /^Key[A-Z]$/.test(c) ? c.slice(3) : /^Digit\d$/.test(c) ? c.slice(5) : c.replace(/^Arrow/, ''));

  /* ─────────────── state ─────────────── */
  const st = {
    open: false, view: null, cfg: { ...DEF_CFG }, keys: { ...DEF_KEYS }, easy: false, ended: false,
    beat0: 0, period: 60 / 110, lastBeatIdx: -1, press: null, breath: null, autoBreath: 0,
    intervals: [], lastPressAt: 0, lastCompAt: 0, batch: null, lastReport: 0,
    localSet: 0, waitBreaths: false, setPhase: '', bars: [], hits: [], rate: 0, depth: 0, quality: 0,
    auto: false, showCauses: true, pads: { R: false, L: false }, drag: null, padsBusy: false,
    viewAt: 0, phaseLeftAt: 0, idleWarned: false, cycleWarned: 0, adrWarned: 0, chargedBeep: 0, lastPP: '', raf: 0,
    autoCharged: false, noShockUntil: 0, ppTimer: 0, padsOpen: false, chargeMs: 2500, waitAt: 0,
    recoil: 0, setCells: [], setStats: { early: 0, on: 0, late: 0, miss: 0, recoil: 0, n: 0 }, breathLog: [], voice: '',
  };
  const zeroBatch = () => ({ n: 0, timing: 0, depth: 0, recoil: 0 });
  function resetSet() { st.setCells = []; st.setStats = { early: 0, on: 0, late: 0, miss: 0, recoil: 0, n: 0 }; }
  st.batch = zeroBatch();

  let root, dev, pp = null, ecg = null, co2 = null, anchors = null;
  const $ = s => root.querySelector(s);
  const post = (n, d) => NZA.post(`${APP}:${n}`, d || {});
  const snd = () => st.cfg.sounds !== false && NZA.cfg.sounds !== false;

  /* ─────────────── SVG bits ─────────────── */
  // electrode pad: foam border, gel window, lead wire, a placement pictogram printed on it
  const padSVG = (lab) => {
    const dot = lab === 'R' ? '<circle cx="18.5" cy="34" r="2.6" fill="#e5484d"/>' : '<circle cx="25.5" cy="40" r="2.6" fill="#e5484d"/>';
    return `<svg viewBox="0 0 44 58" width="100%" height="100%"><defs>
      <linearGradient id="pf${lab}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fbfcfb"/><stop offset="1" stop-color="#d8dedd"/></linearGradient>
      <linearGradient id="pgl${lab}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#b9cdd0"/><stop offset="1" stop-color="#8ea7ab"/></linearGradient></defs>
      <path d="M22 0v6" stroke="#2b3134" stroke-width="3" stroke-linecap="round"/><rect x="18" y="4" width="8" height="5" rx="1.5" fill="#3a4246"/>
      <rect x="2" y="8" width="40" height="48" rx="10" fill="url(#pf${lab})" stroke="rgba(0,0,0,.25)" stroke-width="1"/>
      <rect x="8" y="14" width="28" height="36" rx="7" fill="url(#pgl${lab})" opacity=".8"/>
      <path d="M14.5 27c0-3 3-4.5 7.5-4.5s7.5 1.5 7.5 4.5v15h-15z" fill="none" stroke="#2c3b3e" stroke-width="1.3" opacity=".75"/>
      <circle cx="22" cy="19.5" r="2.4" fill="none" stroke="#2c3b3e" stroke-width="1.3" opacity=".75"/>${dot}
      <rect x="2" y="8" width="40" height="48" rx="10" fill="none" stroke="#fff" stroke-opacity=".7" stroke-width=".8"/></svg>`;
  };
  // line-art torso pictogram for the pad map on the device screen (120 × 150)
  const torsoSVG = `<svg viewBox="0 0 120 150" class="tso">
    <circle cx="60" cy="16" r="11" class="o"/>
    <path d="M52 27v7M68 27v7" class="o"/>
    <path d="M24 46c4-8 14-12 28-12h16c14 0 24 4 28 12l8 30c1 4-1 7-5 7l-8-1-1 64H30l-1-64-8 1c-4 0-6-3-5-7z" class="o"/>
    <path d="M60 40v58M42 42c6 3 12 4 18 4s12-1 18-4M38 58c7 3 14 4 22 4s15-1 22-4M38 72c7 3 14 4 22 4s15-1 22-4M40 86c6 2 13 3 20 3s14-1 20-3" class="r"/>
    <path d="M34 40l18 4M86 40l-18 4" class="r"/></svg>`;
  // energy selector ring around the shock button (240°, gap at the bottom)
  const RING = { C: 90, R: 60, A0: 150, SW: 240 };
  const ringPt = (f, r) => { const a = (RING.A0 + RING.SW * f) * Math.PI / 180; return [RING.C + r * Math.cos(a), RING.C + r * Math.sin(a)]; };
  const ringArc = (f0, f1, r) => { const [x0, y0] = ringPt(f0, r), [x1, y1] = ringPt(f1, r); return `M${x0.toFixed(2)} ${y0.toFixed(2)}A${r} ${r} 0 ${(f1 - f0) * RING.SW > 180 ? 1 : 0} 1 ${x1.toFixed(2)} ${y1.toFixed(2)}`; };
  function ringSVG(list) {
    const n = Math.max(1, list.length - 1);
    let ticks = '', labels = '', minor = '';
    for (let i = 0; i <= 48; i++) { const f = i / 48; const [a, b] = ringPt(f, RING.R + 6), [c, d] = ringPt(f, RING.R + 9); minor += `<line x1="${a.toFixed(1)}" y1="${b.toFixed(1)}" x2="${c.toFixed(1)}" y2="${d.toFixed(1)}"/>`; }
    list.forEach((e, i) => {
      const f = i / n;
      const [a, b] = ringPt(f, RING.R + 5), [c, d] = ringPt(f, RING.R + 13), [tx, ty] = ringPt(f, RING.R + 22);
      ticks += `<line data-i="${i}" x1="${a.toFixed(1)}" y1="${b.toFixed(1)}" x2="${c.toFixed(1)}" y2="${d.toFixed(1)}"/>`;
      labels += `<text data-i="${i}" x="${tx.toFixed(1)}" y="${(ty + 3).toFixed(1)}" text-anchor="middle">${e}</text>`;
    });
    return `<svg viewBox="0 0 180 180"><path class="trk" d="${ringArc(0, 1, RING.R)}"/><path class="fil" d=""/>
      <g class="mn">${minor}</g><g class="tk">${ticks}</g><g class="lb">${labels}</g><circle class="dot" r="4" cx="0" cy="0"/>
      <text class="unit" x="${RING.C}" y="${RING.C + RING.R + 4}" text-anchor="middle">J</text></svg>`;
  }

  // cycle ring on the device screen (2-minute cycle, a tick every 30 s)
  const CYC = 2 * Math.PI * 27;
  const cycTicks = () => { let o = ''; for (let i = 0; i < 4; i++) { const a = -Math.PI / 2 + i * Math.PI / 2; o += `<line x1="${(32 + Math.cos(a) * 21).toFixed(1)}" y1="${(32 + Math.sin(a) * 21).toFixed(1)}" x2="${(32 + Math.cos(a) * 24).toFixed(1)}" y2="${(32 + Math.sin(a) * 24).toFixed(1)}"/>`; } return `<g class="tk">${o}</g>`; };

  /* ═══════════════════════════ DOM ═══════════════════════════ */
  // DF-7: a portrait monitor / defibrillator docked left of the tool belt (right ≥ 300 px).
  // Generic labelling only (type, model code, warning sticker).
  function deviceHTML() {
    const key = (sk, ic, lab, id) => `<div class="df-k"><button class="df-key" data-sk="${sk}"${id ? ` id="${id}"` : ''}><span class="led"></span>${ic}</button><label>${esc(lab)}</label></div>`;
    return `
      <div class="df">
        <span class="df-grip l"></span><span class="df-grip r"></span>
        <i class="df-screw tl"></i><i class="df-screw tr"></i><i class="df-screw bl"></i><i class="df-screw br"></i>
        <div class="df-cap">
          <span class="df-port" id="cpPort"><i class="sock"></i><i class="plug"></i></span>
          <span class="df-grille"></span>
          <span class="df-age" title="${esc(T('age_adult'))}"><em class="on">${esc(T('age_adult'))}</em><span class="sw"><i></i></span><em>${esc(T('age_child'))}</em></span>
          <span class="df-leds"><i class="on"></i><i id="cpLedPads"></i><i id="cpLed"></i></span>
        </div>
        <div class="df-plate"><b>${esc(T('model'))}</b><span>${esc(T('dev_type'))}</span><span class="sp"></span><em class="df-tag" id="cpModeTag"></em></div>
        <div class="df-bezel">
          <div class="dev-screen df-scr" id="cpScr">
            <div class="sb">
              <span class="sb-pads" id="cpPadsTag"></span>
              <span class="sp"></span>
              <span class="sb-ic" id="cpSbBell">${icon('bell')}</span>
              <span class="sb-bat"><i></i><i></i><i></i><i></i></span>
              <b class="sb-clk" id="cpClock">--:--</b>
            </div>
            <div class="panes">
              <div class="pane ecg">
                <canvas id="cpEcg"></canvas>
                <span class="pl g">${esc(T('ecg'))}<em>${esc(T('lead'))}</em></span>
                <div class="hrb" id="cpNHr"><span class="k">${esc(T('hr'))}<i class="hb">${icon('heart')}</i></span><b class="v">---</b><span class="u">${esc(T('bpm'))}</span></div>
                <div class="rhy" id="cpRh"><b></b><span></span></div>
                <div class="cp-anl" id="cpAnl"><b>${esc(T('analysing'))}</b><span>${esc(T('anl_sub'))}</span><i class="pb"><i id="cpAnlBar"></i></i></div>
                <div class="cp-msg" id="cpEcgMsg"></div>
              </div>
              <div class="pane co2"><canvas id="cpCo2"></canvas><span class="pl y">${esc(T('tr_co2'))}</span><div class="nv y" id="cpNCo"><b>--</b><span>${esc(T('mmhg'))}</span></div></div>
              <div class="pane cpr"><canvas id="cpFb"></canvas><span class="pl w">${esc(T('tr_fb'))}</span><div class="nv" id="cpNRate"><b>---</b><span>${esc(T('per_min'))}</span><span class="rg" id="cpRateG"><i class="band"></i><i class="mk"></i></span></div></div>
              <div class="cp-padmap" id="cpPads">
                <div class="torso">${torsoSVG}<span class="slot" data-slot="R" style="left:45px;top:58px">${padSVG('R')}</span><span class="slot" data-slot="L" style="left:79px;top:92px">${padSVG('L')}</span></div>
                <div class="txt"><b class="pt"></b><p></p>
                  <div class="row"><div class="pk"><div class="cp-pad" data-pad="R">${padSVG('R')}</div><span>${esc(T('pad_r'))}</span></div><div class="pk"><div class="cp-pad" data-pad="L">${padSVG('L')}</div><span>${esc(T('pad_l'))}</span></div></div>
                </div>
              </div>
            </div>
            <div class="cb">
              <div class="cb-cy" id="cpNCy">
                <div class="cb-ring"><svg viewBox="0 0 64 64"><circle class="bg" cx="32" cy="32" r="27"/><circle class="fg" id="cpCyArc" cx="32" cy="32" r="27" stroke-dasharray="${CYC.toFixed(1)}" stroke-dashoffset="${CYC.toFixed(1)}"/>${cycTicks()}</svg>
                  <div class="c"><span>${esc(T('ring_k'))}</span><b id="cpCode">00:00</b></div></div>
                <div class="cb-ct"><span class="l" id="cpCyL"></span><b id="cpCyV">--:--</b><span class="s" id="cpCyS"></span></div>
              </div>
              <div class="cb-il">
                <div class="en" id="cpNEn"><span>${esc(T('energy'))}</span><b>200<small>J</small></b></div>
                <div class="sh" id="cpNSh"><span>${esc(T('shocks'))}</span><i class="pips" id="cpShPips"></i><b>0</b></div>
                <div class="ad" id="cpNAd"><span>${esc(T('il_adr'))}</span><b>--</b></div>
              </div>
            </div>
            <div class="msg" id="cpPrm"><span class="spk">${icon('volume')}</span><span class="t"></span><span class="wv"><i></i><i></i><i></i><i></i></span></div>
            <div class="cp-chg"><i id="cpChg"></i></div>
          </div>
        </div>
        <div class="df-deck">
          <div class="df-col">
            ${key('analyse', icon('ecg'), T('sk_analyse'))}
            <div class="df-k"><button class="df-key chg" id="cpCharge"><span class="f"></span><span class="led"></span>${icon('bolt')}</button><label class="lab">${esc(T('charge'))}</label></div>
            <div class="df-k"><div class="df-rock" id="cpMode"><button data-m="aed">${esc(T('aed'))}</button><button data-m="manual">${esc(T('manual'))}</button></div><label>${esc(T('energy_select'))}</label></div>
          </div>
          <div class="df-dial" id="cpKnob" data-wheel="1">
            <div class="ring"></div>
            <button class="df-shock" id="cpShock"><span class="halo"></span><span class="face">${icon('bolt')}<small>${esc(T('shock'))}</small></span></button>
          </div>
          <div class="df-col">
            ${key('pads', icon('defib'), T('sk_pads'))}
            ${key('adren', `${icon('syringe')}<span class="cnt" id="cpAdrCnt"></span>`, T('sk_adren'))}
            <div class="df-k"><button class="df-key" data-sk="four"><span class="led"></span><span class="ic4"></span></button><label id="cpFourL"></label></div>
          </div>
        </div>
        <div class="df-foot"><span class="hz"></span><span class="wt">${icon('alert')}<span>${esc(T('dev_warn'))}</span></span><span class="hz"></span></div>
        <div class="df-ref"><span>${esc(T('dev_ref'))}</span><span class="sn">SN 07-41188</span></div>
      </div>`;
  }

  function build(el) {
    root = el;
    el.innerHTML = `
      <div class="cp-wrap">
        <div class="cp-team nza-hud solid" id="cpTeam"></div>
        <div class="cp-banner nza-hud solid" id="cpBanner"><div class="bi"><span class="ic"></span></div><div class="bt"><b></b><span></span></div></div>
        <div class="cp-padg" id="cpGhost"></div>
        <div class="cp-wpad hide" id="cpWR">${padSVG('R')}</div><div class="cp-wpad hide" id="cpWL">${padSVG('L')}</div>
        <div class="cp-dev" id="cpDev"></div>
        <div class="cp-deb nza-hud solid" id="cpDeb"></div>
      </div>`;
    dev = $('#cpDev');
    anchors = NZA.ui.Anchors(APP);
    anchors.on(onAnchors);

    mountDevice();
    // pads drag (the pads themselves are wired in mountDevice)
    window.addEventListener('pointermove', moveDrag);
    window.addEventListener('pointerup', endDrag);

    window.addEventListener('keydown', onKeyDown, true);
    window.addEventListener('keyup', onKeyUp, true);
  }
  // device face markup + hardware wiring (re-run on open so the locale applies to the printed labels)
  function mountDevice() {
    dev.innerHTML = deviceHTML();
    dev.querySelectorAll('button[data-sk]').forEach(b => b.addEventListener('click', () => { blur(); softKey(b.dataset.sk); }));
    $('#cpCharge').addEventListener('click', () => { blur(); doCharge(); });
    $('#cpShock').addEventListener('click', e => { e.stopPropagation(); blur(); doShock(); });
    $('#cpMode').addEventListener('click', e => { const b = e.target.closest('button'); blur(); if (b && !b.disabled) setMode(b.dataset.m); });
    const knob = $('#cpKnob');
    knob.addEventListener('click', e => { if (e.target.closest('#cpShock')) return; const r = knob.getBoundingClientRect(); stepEnergy(e.clientX < r.left + r.width / 2 ? -1 : 1); });
    knob.addEventListener('wheel', e => { e.preventDefault(); stepEnergy(e.deltaY > 0 ? -1 : 1); }, { passive: false });
    dev.querySelectorAll('.cp-pad').forEach(p => p.addEventListener('pointerdown', e => startDrag(e, p.dataset.pad)));
    $('#cpKnob .ring').innerHTML = ringSVG(st.cfg.energies || DEF_CFG.energies);
  }
  const blur = () => { if (document.activeElement && document.activeElement.blur) document.activeElement.blur(); };
  const isTop = () => st.open && NZA.isOpen(APP) && NZA.stack[NZA.stack.length - 1] === APP;

  /* metronome card: lives in the procedure column (pp.slot, above the key legend) */
  function metroHTML() {
    let scale = '';
    for (let cm = 0; cm <= 7; cm++) scale += `<i style="top:${(cm / 7) * 100}%" class="${cm === 5 || cm === 6 ? 'b' : ''}"><em>${cm}</em></i>`;
    return `
      <div class="mt-hd"><span class="k">${esc(T('m_title'))}</span><b id="cpMtBpm">110</b><span class="u">/min</span><span class="sp"></span><span class="mt-auto" id="cpMtAuto">${esc(T('auto'))}</span></div>
      <div class="mt-body">
        <div class="mt-ring"><canvas id="cpRing"></canvas><div class="mt-c"><b id="cpMtN">0</b><span id="cpMtOf">/30</span></div><span class="mt-pop cp-pop" id="cpPop"></span></div>
        <div class="mt-depth"><div class="tube"><span class="sc">${scale}</span><span class="z"></span><i id="cpTube"></i></div>
          <div class="dv"><div class="l" id="cpDepthL">${esc(T('m_depth'))}</div><div class="v" id="cpDepthV">--<small>cm</small></div><div class="s" id="cpDepthS">${esc(T('d_ok'))}</div></div></div>
        <div class="mt-tim" id="cpTim"></div>
        <div class="ov" id="cpLaneOv"><div class="oh"><span class="ic"></span><div class="ot"><b></b><span></span></div></div><div class="ob"><span class="bar"><i></i></span><em></em></div></div>
      </div>`;
  }

  /* ═══════════════════════════ OPEN / CLOSE ═══════════════════════════ */
  function open(data) {
    data = data || {};
    if (data.locale) L = Object.assign({}, L, data.locale);
    st.cfg = Object.assign({}, DEF_CFG, data.cfg || {});
    st.keys = Object.assign({}, DEF_KEYS, data.keys || {});
    st.easy = !!data.easy || !!(data.view && data.view.easy);
    st.open = true; st.ended = false; st.view = null;
    st.localSet = 0; st.waitBreaths = false; st.bars = []; st.hits = []; st.intervals = []; st.rate = 0; st.depth = 0; st.quality = 0; st.recoil = 0;
    st.setCells = []; st.setStats = { early: 0, on: 0, late: 0, miss: 0, recoil: 0, n: 0 }; st.breathLog = [];
    st.press = null; st.breath = null; st.auto = false; st.demoPlay = false; st.batch = zeroBatch(); st.lastReport = now(); st.lastCompAt = 0; st.lastPressAt = 0;
    st.pads = { R: false, L: false }; st.padsBusy = false; st.padsOpen = false; st.drag = null; st.noShockUntil = 0; st.cycleWarned = 0; st.adrWarned = 0; st.autoCharged = false; st.lastPP = '';
    st.period = 60 / (st.cfg.target || 110); st.beat0 = now() + 400; st.lastBeatIdx = -1; st.voice = '';
    mountDevice();   // the locale arrived with the open: rebuild the static device face
    root.querySelectorAll('.cp-dev,.cp-team').forEach(e => { e.style.display = ''; });
    dev.classList.remove('cp-dim');
    $('#cpDeb').classList.remove('on');
    hideBanner(); clearTimeout(voiceTimer);

    if (ecg) ecg.stop();
    if (co2) co2.stop();
    ecg = NZA.vitals.Trace($('#cpEcg'), { type: 'ecg', rhythm: 'asystole', rate: 60, color: '#3ddc84', speed: 0.2, gain: 0.34, onBeat: () => { const v = st.view; if (v && v.monitor && !ARREST_RH[v.rhythm] && v.rhythm) { beatFlash(); if (snd()) NZA.audio.heartbeat(v.spo2 || 96); } } });
    co2 = NZA.vitals.Trace($('#cpCo2'), { type: 'co2', rr: 0, etco2: 0, color: '#f2d64b', speed: 0.12, gain: 0.3, glow: false });

    if (pp) pp.destroy();
    st.ppText = '';
    pp = NZA.ui.ProcPanel(root.querySelector('.cp-wrap'), {
      step: 1, total: 4, tag: T('tag_cycle', 1), title: T('pp_compress'), text: '', steps: stepNames(), abort: { label: T('abort'), key: 'ESC', seconds: 1.2 },
      hints: [{ keys: [keyLabel(st.keys.causes)], label: T('hint_causes') }],
      onAbort: () => { if (!st.ended) post('leave'); }, onTool: k => toolKey(k),
    });
    const card = document.createElement('div');
    card.className = 'cp-metro nza-hud solid nza-int';
    card.id = 'cpMetro';
    card.innerHTML = metroHTML();
    pp.slot.insertBefore(card, pp.slot.firstChild);
    const z = $('.mt-depth .tube .z'); z.style.top = `${(5 / 7) * 100}%`; z.style.height = `${(1 / 7) * 100}%`;
    // depth tube: top = 0 cm, bottom = 7 cm → the band sits between 5 and 6 cm

    if (data.view) state(data.view);
    renderMsg();
    cancelAnimationFrame(st.raf);
    st.raf = requestAnimationFrame(frame);
  }
  // one step per stage of the loop: 30:2 cycles → rhythm check → shock if advised → (back to cycles) … pulse back
  const stepNames = () => [T('st_cycle'), T('st_analyse'), T('st_shock'), T('st_rosc')];
  function beatFlash() { const h = $('#cpNHr'); if (!h) return; h.classList.remove('beat'); void h.offsetWidth; h.classList.add('beat'); }

  function close() {
    st.open = false;
    cancelAnimationFrame(st.raf);
    if (pp) { pp.destroy(); pp = null; }
    if (ecg) ecg.stop();
    if (co2) co2.stop();
    endDrag(null, true);
    NZA.ui.Marker(APP, 'padR', {}).remove(); NZA.ui.Marker(APP, 'padL', {}).remove();
    $('#cpPads').classList.remove('on');
    $('#cpWR').classList.add('hide'); $('#cpWL').classList.add('hide');
    hideBanner(); voice(null);
    clearTimeout(st.ppTimer);
  }
  /* ═══════════════════════════ VIEW ═══════════════════════════ */
  function state(v) {
    if (!v || st.ended) return;
    const prev = st.view || {};
    st.view = v; st.viewAt = now();
    if (v.easy !== undefined) st.easy = !!v.easy || st.easy;
    if (v.phase !== prev.phase) phaseChanged(prev.phase, v.phase);
    if (compressPhase(v.phase)) {
      if (st.setPhase !== 'compress') { st.localSet = v.set || 0; st.setPhase = 'compress'; }
      else if ((v.set || 0) > st.localSet) st.localSet = v.set || 0;
    }
    if (v.pads && !prev.pads) { st.pads = { R: true, L: true }; padsTray(false); }
    renderDevice(); renderTeam(); renderPP(true);
    if (ecg) {
      const rh = v.monitor ? (v.rhythm || 'asystole') : 'asystole';
      let rate = v.hr || 0;
      if (rh === 'pea' && rate < 20) rate = 38;
      ecg.set({ rhythm: rh, rate: Math.max(1, rate), amp: v.monitor ? 1 : 0.15 });
    }
    if (co2) {
      const vent = v.continuous ? 10 : ((v.ventN || 0) > 0 ? 6 : 0);
      co2.set({ rr: v.monitor ? (v.state === 'arrest' ? vent : (v.rosc ? 12 : vent || 12)) : 0, etco2: shownEtco2() || 20 });
    }
    // AED: after "shock advised" the device charges by itself (manual: the medic decides)
    if (v.phase === 'advised' && v.mode !== 'manual' && !st.autoCharged && v.pads) { st.autoCharged = true; act('charge', { energy: v.energy }); }
    if (v.phase !== 'advised') st.autoCharged = false;
  }

  function phaseChanged(from, to) {
    st.press = null;
    if (to === 'breaths') { st.waitBreaths = false; st.setPhase = 'breaths'; st.localSet = 0; st.breathLog = []; if (st.breath) st.breath = null; }
    if (to === 'compress' && from !== 'advised' && from !== 'charging') { st.beat0 = now() + 250; st.lastBeatIdx = -1; st.idleWarned = false; }
    if (to === 'compress' && (from === 'breaths' || from === 'charged' || from === 'analyse')) { st.setPhase = ''; st.localSet = 0; st.waitBreaths = false; st.intervals = []; st.lastPressAt = 0; resetSet(); }
    if (to === 'charged') { st.chargedBeep = now(); }
    if (to !== 'charged' && from === 'charged') hideBanner('clear');
    if (from === 'analyse' && to !== 'analyse') hideBanner('analyse');
    if (to === 'rosc') st.auto = false;
  }

  const v_ = () => st.view || {};
  const iAmComp = () => v_().role === 'comp';
  const iBreathe = () => !!v_().breather;
  const curEnergy = () => v_().energy || 200;
  function codeTime() { const v = v_(); return (v.codeTime || 0) + (now() - st.viewAt) / 1000; }
  function cycleElapsed() { const v = v_(); return (v.cycleElapsed || 0) + (now() - st.viewAt) / 1000; }
  function phaseLeft() { const v = v_(); return v.phaseLeft === null || v.phaseLeft === undefined ? null : Math.max(0, v.phaseLeft - (now() - st.viewAt) / 1000); }
  function shownEtco2() {
    const v = v_();
    if (!v.monitor) return 0;
    if (v.etco2) return v.etco2;
    if (v.state === 'arrest') return st.lastCompAt && now() - st.lastCompAt < 2000 ? Math.round(9 + (st.quality || v.quality || 0) * 0.13) : 6;
    return 0;
  }

  /* ─────────────── device ─────────────── */
  function rhythmInfo(v) {
    if (!v.monitor) return { text: T('rh_none'), sub: T('rhs_none'), cls: 'none' };
    if (v.rosc && v.state !== 'arrest') return { text: T('rh_rosc'), sub: T('rhs_perf'), cls: 'green' };
    const r = v.rhythm || 'asystole';
    const text = T(`rh_${r}`);
    if (r === 'vf' || r === 'vt') return { text, sub: T('rhs_shock'), cls: 'red blink' };
    if (r === 'asystole') return { text, sub: T('rhs_noshock'), cls: 'red' };
    if (r === 'pea') return { text, sub: T('rhs_noshock'), cls: 'amber' };
    return { text, sub: T('rhs_perf'), cls: 'green' };
  }

  function renderDevice() {
    const v = v_();
    if (!$('#cpModeTag')) return;
    const defib = !!v.defib || !!v.pads;
    const man = v.mode === 'manual';
    const charging = v.phase === 'charging', charged = v.phase === 'charged';
    // plate, cable port, LEDs, status bar
    const mt = $('#cpModeTag');
    mt.textContent = man ? T('mode_manual') : T('mode_aed');
    mt.className = `df-tag ${man ? 'man' : ''}`;
    const pt = $('#cpPadsTag');
    pt.innerHTML = `${icon(v.pads ? 'link' : 'alert')}<span>${esc(v.pads ? T('pads_on') : T('pads_off'))}</span>`;
    pt.className = `sb-pads ${v.pads ? 'on' : (defib ? 'warn' : 'red')}`;
    $('#cpPort').className = `df-port ${v.pads ? 'on' : ''}`;
    $('#cpLedPads').className = v.pads ? 'on' : (defib ? 'warn' : '');
    $('#cpLed').className = charged ? 'red blink' : (charging ? 'amber blink' : '');
    // rhythm tag (bottom-left of the ECG pane)
    const rh = rhythmInfo(v);
    const rhe = $('#cpRh');
    rhe.querySelector('b').textContent = rh.text;
    rhe.querySelector('span').textContent = rh.sub;
    rhe.className = `rhy ${rh.cls}`;
    const msg = $('#cpEcgMsg');
    if (!v.pads && !v.monitor) { msg.className = `cp-msg on ${defib ? '' : 'red'}`; msg.innerHTML = `<span>${icon(defib ? 'link' : 'alert')}${esc(defib ? T('connect_pads') : T('no_defib'))}</span>`; }
    else msg.className = 'cp-msg';
    const anl = $('#cpAnl');
    anl.classList.toggle('on', v.phase === 'analyse');
    rhe.classList.toggle('hide', v.phase === 'analyse');
    // HR corner box
    const arrestRh = v.state === 'arrest' && ARREST_RH[v.rhythm];
    const hr = $('#cpNHr');
    hr.querySelector('.v').textContent = !v.monitor ? '--' : (v.state === 'arrest' && (v.rhythm === 'vf' || v.rhythm === 'asystole')) ? '---' : String(Math.round(v.hr || 0));
    hr.classList.toggle('alarm', !!(v.monitor && arrestRh));
    hr.classList.toggle('live', !!(v.monitor && !arrestRh && (v.hr || 0) > 0));
    // instrument list
    const en = $('#cpNEn');
    en.querySelector('b').innerHTML = `${curEnergy()}<small>J</small>`;
    en.className = `en ${charged ? 'ready' : (charging ? 'chg' : '')}`;
    const nsh = v.shocks || 0;
    $('#cpNSh b').textContent = String(nsh);
    const pips = $('#cpShPips');
    const pipsH = Array.from({ length: Math.min(6, nsh) }, () => `<i>${icon('bolt')}</i>`).join('');
    if (pips._h !== pipsH) { pips.innerHTML = pipsH; pips._h = pipsH; }
    const co = shownEtco2();
    $('#cpNCo b').textContent = v.monitor && co ? String(Math.round(co)) : '--';
    // energy ring
    const list = st.cfg.energies || [];
    const idx = Math.max(0, list.indexOf(curEnergy()));
    const f = idx / Math.max(1, list.length - 1);
    const knob = $('#cpKnob');
    const svg = knob.querySelector('svg');
    if (svg) {
      svg.querySelector('.fil').setAttribute('d', ringArc(0, Math.max(f, 0.004), RING.R));
      const [dx, dy] = ringPt(f, RING.R);
      const dot = svg.querySelector('.dot'); dot.setAttribute('cx', dx.toFixed(1)); dot.setAttribute('cy', dy.toFixed(1));
      svg.querySelectorAll('[data-i]').forEach(e => e.classList.toggle('on', Number(e.dataset.i) === idx));
    }
    knob.classList.toggle('aed', !man);
    knob.classList.toggle('hot', charging || charged);
    // mode rocker
    $('#cpMode').querySelectorAll('button').forEach(b => {
      b.classList.toggle('on', (b.dataset.m === 'manual') === man);
      b.disabled = (b.dataset.m === 'manual' && !v.canManual) || charging || charged;
    });
    // charge / shock
    const ch = $('#cpCharge');
    ch.parentNode.querySelector('.lab').textContent = charged || charging ? T('disarm') : T('charge');
    ch.classList.toggle('ready', charged);
    ch.classList.toggle('lit', v.phase === 'advised');
    ch.classList.toggle('off', !v.pads || (!man && v.phase !== 'advised' && !charging && !charged));
    $('#cpShock').classList.toggle('armed', charged);
    // side keys
    const four = fourKey();
    $('#cpFourL').textContent = four === 'swap' ? T('sk_swap') : T('sk_pulse');
    dev.querySelector('[data-sk="four"] .ic4').innerHTML = icon(four === 'swap' ? 'swap' : 'pulse');
    const ad = v.adrenaline || {};
    const cnt = $('#cpAdrCnt');
    cnt.textContent = ad.n ? `×${ad.n}` : '';
    cnt.style.display = ad.n ? '' : 'none';
    const lit = { pads: defib && !v.pads, analyse: v.pads && checkDue(), adren: !!ad.due, four: four === 'pulse' ? !!v.rosc : (v.compFatigue || 0) > 15 };
    const off = { pads: !defib || v.pads, analyse: !v.pads, adren: !ad.enabled, four: four === 'swap' ? !v.partner : false };
    dev.querySelectorAll('.df-key[data-sk]').forEach(b => { const k = b.dataset.sk; b.classList.toggle('lit', !!lit[k]); b.classList.toggle('off', !!off[k] && !lit[k]); b.classList.toggle('done', k === 'pads' && !!v.pads); });
    padsTray(defib && !v.pads && st.padsOpen);
  }
  const fourKey = () => (v_().partner ? 'swap' : 'pulse');
  function checkDue() { const v = v_(); return v.state === 'arrest' && cycleElapsed() >= (v.cycleLength || st.cfg.cycleLength) - (st.cfg.checkGrace || 20); }

  function renderLive() {
    const v = v_();
    if (!$('#cpCode')) return;
    $('#cpCode').textContent = NZA.fmt.time(codeTime());
    const clk = new Date();
    $('#cpClock').textContent = `${String(clk.getHours()).padStart(2, '0')}:${String(clk.getMinutes()).padStart(2, '0')}`;
    const comp = iAmComp();
    const rate = comp ? st.rate : (v.rate || 0);
    const rmin = st.cfg.rateMin, rmax = st.cfg.rateMax;
    const nr = $('#cpNRate');
    nr.querySelector('b').textContent = rate ? String(Math.round(rate)) : '---';
    // rate gauge: a vertical 80–140 /min scale with the target band and a marker
    const G = r => clamp((140 - r) / 60, 0, 1) * 100;
    const rg = $('#cpRateG');
    rg.querySelector('.band').style.cssText = `top:${G(rmax)}%;bottom:${100 - G(rmin)}%`;
    const mk = rg.querySelector('.mk');
    mk.style.top = `${G(rate || 110)}%`;
    const rcls = !rate ? '' : (rate < rmin || rate > rmax) ? 'amber' : 'teal';
    if (nr.className !== `nv ${rcls}`) nr.className = `nv ${rcls}`;
    // cycle ring + countdown to the rhythm check
    const cl = v.cycleLength || st.cfg.cycleLength;
    const due = checkDue();
    const ce = cycleElapsed();
    const cy = $('#cpNCy');
    $('#cpCyL').textContent = T('il_cycle', v.cycleNo || 1);
    $('#cpCyV').textContent = due ? T('due') : NZA.fmt.time(Math.max(0, cl - ce));
    $('#cpCyS').textContent = due ? T('cb_now') : T('cb_to');
    $('#cpCyArc').style.strokeDashoffset = (CYC * (1 - clamp(ce / cl, 0, 1))).toFixed(1);
    const ccls = `cb-cy ${due ? 'due' : ''} ${v.state === 'arrest' ? '' : 'idle'}`;
    if (cy.className !== ccls) cy.className = ccls;
    // analysis progress (rhythm tag slot)
    if (v.phase === 'analyse') { const pa = phaseLeft(); $('#cpAnlBar').style.width = `${pa === null ? 0 : clamp(1 - pa / (st.cfg.analyseTime || 4), 0, 1) * 100}%`; }
    const ad = v.adrenaline || {};
    const ae = $('#cpNAd');
    let at = '--', acls = 'ad';
    if (ad.enabled === false) at = '--';
    else if (ad.due && v.state === 'arrest') { at = T('due'); acls = 'ad due'; }
    else if (ad.dueIn !== null && ad.dueIn !== undefined && v.state === 'arrest') at = NZA.fmt.time(Math.max(0, ad.dueIn - (now() - st.viewAt) / 1000));
    else if (!ad.n) at = T('il_none');
    ae.querySelector('b').textContent = at;
    ae.className = acls;
    // charge progress (screen strip + key fill)
    const pl = phaseLeft();
    const chg = $('#cpChg'), kf = $('#cpCharge .f');
    let w = 0;
    if (v.phase === 'charging' && pl !== null) { const tot = Math.max(0.1, (st.chargeMs || 2500) / 1000); w = clamp(1 - pl / tot, 0, 1) * 100; }
    else if (v.phase === 'charged') w = 100;
    chg.style.width = `${w}%`; kf.style.height = `${w}%`;
    renderMsg();
  }

  // the device's own message line: its spoken prompt while it talks, otherwise the state of the code
  function renderMsg() {
    const v = v_();
    const pr = $('#cpPrm');
    if (!pr) return;
    let text = '', cls = '';
    const ph = v.phase;
    const defib = !!v.defib || !!v.pads;
    if (st.voice) { text = st.voice; cls = 'voice'; }
    else if (ph === 'analyse') { text = T('p_analyse'); cls = 'red blink'; }
    else if (ph === 'charged') { text = T('p_charged'); cls = 'red blink'; }
    else if (ph === 'charging') { text = T('p_charging', curEnergy()); cls = 'amber'; }
    else if (ph === 'advised') { text = T('p_advised'); cls = 'amber'; }
    else if (ph === 'rosc') { text = T('p_rosc'); cls = 'teal'; }
    else if (ph === 'breaths') {
      if (iBreathe()) { text = T('p_breath', Math.min(2, (2 - (v.breathsLeft || 0)) + 1), 2); cls = 'teal'; }
      else text = T('p_handsoff');
    } else if (st.noShockUntil > now()) { text = T('p_noshock'); }
    else if (!v.pads && !defib) { text = T('p_nodefib'); cls = 'dim'; }
    else if (!v.pads) { text = T('p_nopads'); cls = 'amber'; }
    else if (checkDue()) { text = T('p_check'); cls = 'amber'; }
    else if (st.waitBreaths) { text = T('p_waitbreath'); cls = 'amber'; }
    else if (v.continuous && iAmComp()) { text = T('p_continuous'); }
    else if (iAmComp()) { text = st.easy ? T('p_easy') : T('p_compress'); }
    else text = T('p_partner');
    const c = `msg ${cls}`;
    if (pr.className !== c) pr.className = c;
    const te = pr.querySelector('.t');
    if (te.textContent !== text) te.textContent = text;
  }

  /* ─────────────── code-team card (top left) ─────────────── */
  const RC = 2 * Math.PI * 16;
  function ringHTML(frac, tone, ic, label, val, cls = '') {
    return `<div class="cp-ring ${tone} ${cls}"><span class="rg"><svg viewBox="0 0 40 40"><circle class="bg" cx="20" cy="20" r="16"/><circle class="fg" cx="20" cy="20" r="16" stroke-dasharray="${RC.toFixed(1)}" stroke-dashoffset="${(RC * (1 - clamp(frac, 0, 1))).toFixed(1)}"/></svg>${icon(ic)}</span>
      <span class="l">${esc(label)}</span><b>${esc(val)}</b></div>`;
  }
  function renderTeam() {
    const v = v_();
    const ad = v.adrenaline || {};
    const arrest = v.state === 'arrest';
    const kind = v.rosc && !arrest ? T('t_rosc') : (v.kind === 'resp' && !arrest ? T('t_resp') : T('t_arrest'));
    const meComp = v.role === 'comp';
    const fat = f => NZA.ui.meterHTML({ value: clamp((f || 0) / 40, 0, 1), tone: (f || 0) > 15 ? 'amber' : '' });
    const causes = (v.causes || []).map(c => `<div class="cp-cause ${esc(c.s)}"><i></i><span class="cn">${esc(T('c_' + c.k))}</span>${c.v ? `<span class="cv">${esc(c.v)}</span>` : ''}</div>`).join('');
    const log = (v.log || []).slice(-4).map(l => `<div class="${esc(l.tone || '')}"><i></i><span>${NZA.fmt.time(l.t)}</span><b>${esc(l.text)}</b></div>`).join('');
    const down = (v.arrestTime || 0) + (now() - st.viewAt) / 1000;
    const ccf = Math.round(v.ccf || 0);
    const cl = v.cycleLength || st.cfg.cycleLength, ce = cycleElapsed();
    const due = checkDue();
    let adFrac = 0, adVal = String(ad.n || 0), adTone = '';
    if (ad.due && arrest) { adFrac = 1; adTone = 'amber pulse'; adVal = T('due'); }
    else if (ad.dueIn !== null && ad.dueIn !== undefined && ad.gap) { adFrac = 1 - clamp(ad.dueIn / ad.gap, 0, 1); adTone = 'teal'; adVal = `×${ad.n || 0}`; }
    else if (ad.n) { adFrac = 1; adTone = 'teal'; adVal = `×${ad.n}`; }
    const team = $('#cpTeam');
    team.className = `cp-team nza-hud solid ${arrest ? 'arrest' : 'ok'} ${team.className.match(/fit\d/) ? team.className.match(/fit\d/)[0] : ''}`;
    team.innerHTML = `
      <div class="hd"><span class="kick"><i></i>${esc(kind)}</span><span class="sp"></span><span class="shk">${icon('bolt')}${v.shocks || 0}</span><span class="chipx sm ${arrest ? 'red' : 'teal'}">P1</span></div>
      <div class="who"><span class="nza-h">${esc(v.name || T('npc'))}</span>${v.npc ? '<span class="tag">NPC</span>' : ''}</div>
      <div class="cp-rings">
        ${ringHTML(clamp(down / 600, 0, 1), 'red', 'clock', T('down'), NZA.fmt.time(down))}
        ${ringHTML(ccf / 100, ccf >= 80 ? 'teal' : ccf >= 60 ? 'amber' : 'red', 'hand', T('ccf'), `${ccf}%`)}
        ${ringHTML(clamp(ce / cl, 0, 1), due ? 'amber pulse' : 'white', 'timer', T('il_cycle', v.cycleNo || 1), due ? T('due') : NZA.fmt.time(Math.max(0, cl - ce)))}
        ${ringHTML(adFrac, adTone, 'syringe', T('adren'), adVal)}
      </div>
      <div class="cp-roles">
        <div class="cp-role ${meComp ? 'me' : ''}"><span class="ri">${icon('heart')}</span><div class="rx"><div class="rl">${esc(T('role_comp'))}</div><div class="rn">${esc(v.compName || '')}${meComp ? `<em>${esc(T('you'))}</em>` : ''}</div></div>
          <div class="ft"><div class="l">${esc(T('fatigue'))}</div>${fat(v.compFatigue)}</div></div>
        <div class="cp-role ${!meComp ? 'me' : ''}"><span class="ri">${icon('lungs')}</span><div class="rx"><div class="rl">${esc(T('role_air'))}</div>${v.airName ? `<div class="rn">${esc(v.airName)}${!meComp ? `<em>${esc(T('you'))}</em>` : ''}</div>` : `<div class="rn dim">${esc(T('nobody'))}</div>`}</div><div></div></div>
      </div>
      ${v.solo ? `<div class="cp-join">${icon('user-plus')}<span>${esc(T('join_hint'))}</span></div>` : ''}
      ${st.showCauses && causes ? `<div class="cp-sec"><div class="sh"><span class="nza-label">${esc(T('causes'))}</span><kbd>${esc(keyLabel(st.keys.causes))}</kbd></div><div class="cp-causes">${causes}</div></div>` : ''}
      ${log ? `<div class="cp-sec log"><div class="sh"><span class="nza-label">${esc(T('log'))}</span></div><div class="cp-log">${log}</div></div>` : ''}`;
    fitTeam();
  }
  // small screens (the kit zoom is clamped): drop the log, then the hint and the causes, before touching the column
  function fitTeam() {
    const team = $('#cpTeam');
    const col = pp && pp.el.querySelector('.pp-col');
    if (!team || !col || !st.open || st.ended) return;
    const first = col.firstElementChild && col.firstElementChild.offsetParent ? col.firstElementChild : col;
    team.classList.remove('fit1', 'fit2', 'fit3');
    for (let lv = 1; lv <= 3; lv++) {
      if (team.getBoundingClientRect().bottom <= first.getBoundingClientRect().top - 10) return;
      team.classList.remove('fit1', 'fit2', 'fit3');
      team.classList.add(`fit${lv}`);
    }
  }

  /* ─────────────── procedure HUD ─────────────── */
  // pushes and breaths are one step (the 30:2 cycle), so the rail does not jump 1 → 2 → 1 every set
  function stepOf(ph) { return ({ compress: 1, breaths: 1, analyse: 2, advised: 3, charging: 3, charged: 3, rosc: 4 })[ph] || 1; }
  // the 'Next' line: what ends this cycle and when (pads first: no pads, no rhythm check, no pulse back)
  function nextLine(v) {
    const ph = v.phase;
    if (ph === 'rosc') return '';
    if (ph === 'analyse') return T('nx_analyse');
    if (ph === 'advised' || ph === 'charging' || ph === 'charged') return T('nx_shock');
    if (!v.pads) return v.defib ? T('nx_pads', keyLabel(st.keys.pads)) : T('nx_no_defib');
    if (checkDue()) return T('nx_due', keyLabel(st.keys.analyse));
    const left = NZA.fmt.time(Math.max(0, (v.cycleLength || st.cfg.cycleLength) - cycleElapsed()));
    return ph === 'breaths' && !v.continuous ? T('nx_breaths', left) : T('nx_check', left);
  }
  function renderPP(force) {
    if (!pp) return;
    const v = v_();
    const ph = v.phase;
    const kc = keyLabel(st.keys.compress);
    let title, text, tone = '';
    const comp = iAmComp();
    if (ph === 'analyse') { title = T('pp_analyse'); text = T('pp_analyse_t'); tone = 'bad'; }
    else if (ph === 'advised') { title = v.mode === 'manual' ? T('pp_advised_man') : T('pp_advised'); text = T('pp_advised_t', keyLabel(st.keys.charge)); }
    else if (ph === 'charging') { title = T('pp_charging', curEnergy()); text = T('pp_charging_t'); }
    else if (ph === 'charged') { title = T('pp_charged'); text = T('pp_charged_t', keyLabel(st.keys.shock), keyLabel(st.keys.disarm)); tone = 'bad'; }
    else if (ph === 'rosc') { title = T('pp_rosc'); text = T('pp_rosc_t', keyLabel(st.keys.pulse)); tone = 'ok'; }
    else if (ph === 'breaths') {
      if (iBreathe()) { title = (v.breathsLeft || 2) === 1 ? T('pp_breaths_1') : T('pp_breaths', v.breathsLeft || 2); text = v.bvm ? T('pp_breaths_bvm', kc) : T('pp_breaths_mouth', kc); }
      else { title = T('pp_breaths_wait'); text = T('pp_breaths_wait_t', v.breathsLeft || 2); }
    } else if (st.noShockUntil > now()) { title = T('pp_noshock'); text = T('pp_noshock_t'); }
    else if (v.continuous && comp) { title = T('pp_cont'); text = T('pp_cont_t', kc); }
    else if (comp) { title = T('pp_compress'); text = st.easy ? T('pp_compress_easy', kc) : T('pp_compress_t', kc); }
    else { title = T('pp_partner'); text = T('pp_partner_t', keyLabel(st.keys.swap)); }

    const rate = comp ? st.rate : (v.rate || 0);
    const rmin = st.cfg.rateMin, rmax = st.cfg.rateMax;
    const rTone = !rate ? '' : (rate < rmin || rate > rmax) ? 'amber' : 'teal';
    const depth = comp ? st.depth : (v.depth ? 3.5 + v.depth * 0.025 : 0);
    const q = comp && st.quality ? st.quality : (v.quality || 0);
    const rec = comp && st.recoil ? st.recoil : (v.recoil || 0);
    let stats;
    if (comp || v.solo) {
      stats = [
        { id: 'depth', label: T('s_depth'), value: depth ? depth.toFixed(1) : '--', unit: 'cm', tone: !depth ? '' : depth >= 5 ? 'teal' : 'amber' },
        { id: 'recoil', label: T('s_recoil'), value: rec ? Math.round(rec) : '--', unit: '%', tone: !rec ? '' : rec >= 80 ? 'teal' : rec >= 55 ? 'amber' : 'red' },
        { id: 'q', label: T('s_quality'), value: q ? Math.round(q) : '--', unit: '%', tone: !q ? '' : q >= 75 ? 'teal' : q >= 50 ? 'amber' : 'red' },
      ];
    } else {
      stats = [
        { id: 'vent', label: T('s_vent'), value: v.ventN ? Math.round(v.vent || 0) : '--', unit: '%' },
        { id: 'br', label: T('s_breaths'), value: v.ventN || 0 },
        { id: 'co', label: T('s_etco2'), value: shownEtco2() ? Math.round(shownEtco2()) : '--', unit: 'mmHg' },
      ];
    }
    const cl = v.cycleLength || st.cfg.cycleLength;
    const ce = cycleElapsed();
    const due = checkDue();
    const rv = rate ? clamp((rate - 60) / 100, 0, 1) : 0;
    const wide = (comp && ph !== 'rosc')
      ? { label: T('w_rate'), value: rate ? String(Math.round(rate)) : '--', unit: '/min', tone: rTone, meter: { value: rv, zone: [(rmin - 60) / 100, (rmax - 60) / 100], mark: rate ? rv : null, tone: rTone === 'amber' ? 'amber' : '', noFill: !rate }, caption: due ? T('cap_due') : T('cap_check', NZA.fmt.time(Math.max(0, cl - ce))), captionTone: due ? 'amber' : '' }
      : { label: T('w_cycle', v.cycleNo || 1), value: NZA.fmt.time(Math.max(0, cl - ce)), meter: { value: clamp(ce / cl, 0, 1), tone: due ? 'amber' : '' }, caption: (v.adrenaline && v.adrenaline.due) ? T('cap_adr_due') : (due ? T('cap_due') : ''), captionTone: 'amber' };

    const tools = toolList();
    const tag = st.easy ? T('tag_easy') : T('tag_cycle', v.cycleNo || 1);
    const next = nextLine(v);
    const sig = JSON.stringify([stepOf(ph), title, text, tone, stats, wide, tools, tag, next]);
    if (!force && sig === st.lastPP) return;
    st.lastPP = sig;
    const upd = {
      step: stepOf(ph), total: 4, steps: stepNames(), next, tag, stats, wide, tools,
      hints: [{ keys: [keyLabel(st.keys.causes)], label: T('hint_causes') }].concat(v.mode === 'manual' ? [{ keys: [keyLabel(st.keys.energyDown), keyLabel(st.keys.energyUp)], label: T('hint_energy') }] : [], tools.length <= 4 ? [{ keys: [T('hint_rmb')], label: T('hint_orbit') }] : []),
    };
    // only hand the text over when it changed: the kit replays its swap-in animation on every text update
    const txt = `${title}|${tone}|${text}`;
    if (txt !== st.ppText) { st.ppText = txt; Object.assign(upd, { title, titleTone: tone, text }); }
    pp.set(upd);
    pp.el.querySelector('.pp-tag').classList.toggle('easy', st.easy);
  }

  function toolList() {
    const v = v_();
    const defib = !!v.defib || !!v.pads;
    const ph = v.phase;
    const ad = v.adrenaline || {};
    const list = [];
    if (!v.pads) list.push({ key: keyLabel(st.keys.pads), act: 'pads', icon: 'defib', label: T('tool_pads'), state: !defib ? 'locked' : (st.padsOpen ? 'active' : 'need') });
    list.push({ key: keyLabel(st.keys.analyse), act: 'analyse', icon: 'ecg', label: T('tool_analyse'), state: !v.pads || ph === 'breaths' || ph === 'charging' || ph === 'charged' || ph === 'rosc' ? 'locked' : (ph === 'analyse' ? 'active' : (checkDue() ? 'need' : '')) });
    const charging = ph === 'charging' || ph === 'charged';
    list.push({ key: keyLabel(st.keys.charge), act: 'charge', icon: charging ? 'x' : 'battery', label: charging ? T('tool_disarm') : T('tool_charge'), sub: `${curEnergy()} J`, state: !v.pads ? 'locked' : (charging ? 'active' : (ph === 'advised' ? 'need' : (v.mode !== 'manual' ? 'locked' : ''))) });
    list.push({ key: keyLabel(st.keys.shock), act: 'shock', icon: 'bolt', label: T('tool_shock'), state: ph === 'charged' ? 'need' : 'locked' });
    if (ad.enabled !== false) list.push({ key: keyLabel(st.keys.adrenaline), act: 'adrenaline', icon: 'syringe', label: T('tool_adren'), count: `×${ad.have || 0}`, state: !ad.enabled || !ad.have ? 'locked' : (ad.due ? 'need' : '') });
    if (v.partner) list.push({ key: keyLabel(st.keys.swap), act: 'swap', icon: 'swap', label: T('tool_swap'), state: ph === 'charged' ? 'locked' : ((v.compFatigue || 0) > 15 ? 'need' : '') });
    else if (v.rosc || ph === 'rosc') list.push({ key: keyLabel(st.keys.pulse), act: 'pulse', icon: 'pulse', label: T('tool_pulse'), state: 'need' });
    return list.map(t => ({ key: t.key, icon: t.icon, label: t.label, sub: t.sub, count: t.count, state: t.state, act: t.act }));
  }
  function toolKey(k) {
    const t = toolList().find(x => String(x.key).toLowerCase() === String(k).toLowerCase());
    if (t && t.state !== 'locked') runAction(t.act);
  }

  /* ═══════════════════════════ ACTIONS ═══════════════════════════ */
  async function act(name, data) {
    const r = await post('action', { name, data: data || {} });
    if (r && r.ok === false && r.msg) pp && pp.flash('bad', r.msg, 3200);
    return r || {};
  }
  function runAction(a) {
    if (st.ended) return;
    switch (a) {
      case 'pads': return doPads();
      case 'analyse': return act('analyse');
      case 'charge': return doCharge();
      case 'disarm': return act('disarm');
      case 'shock': return doShock();
      case 'adrenaline': return doAdrenaline();
      case 'swap': return act('swap');
      case 'pulse': return doPulse();
    }
  }
  function softKey(k) {
    if (k === 'four') return runAction(fourKey());
    if (k === 'adren') return runAction('adrenaline');
    runAction(k);
  }
  function doCharge() {
    const v = v_();
    if (!v.pads) return;
    if (v.phase === 'charging' || v.phase === 'charged') return act('disarm');
    act('charge', { energy: curEnergy() });
  }
  function doShock() { if (v_().phase === 'charged') act('shock'); }
  async function doAdrenaline() {
    const r = await act('adrenaline');
    if (r && r.ok && r.msg) pp && pp.flash('ok', r.msg, 3000);
  }
  async function doPulse() {
    const r = await act('pulse');
    if (!r || r.ok === false) return;
    if (r.pulse) pp && pp.flash('ok', T('f_pulse_yes', r.rate || '--', r.weak ? T('f_pulse_weak') : ''), 3600);
    else pp && pp.flash('bad', T('f_pulse_no'), 3200);
  }
  function setMode(m) {
    const v = v_();
    if (m === v.mode || (m === 'manual' && !v.canManual)) return;
    act('mode', { mode: m });
  }
  function stepEnergy(dir) {
    const v = v_();
    if (v.mode !== 'manual') { pp && pp.flash('warn', T('f_aed_energy'), 2200); return; }
    const list = st.cfg.energies || [];
    const i = clamp(list.indexOf(curEnergy()) + dir, 0, list.length - 1);
    if (list[i] !== curEnergy()) { if (snd()) NZA.audio.click(900); act('energy', { energy: list[i] }); }
  }

  /* ─────────────── pads ─────────────── */
  function doPads() {
    const v = v_();
    if (v.pads) return;
    if (!v.defib) { pp && pp.flash('bad', T('f_no_defib'), 4200); return; }
    if (st.padsOpen || st.easy) { placePad('R'); placePad('L'); return; }   // second press / easy: stick both
    st.padsOpen = true;
    padsTray(true);
  }
  function padsTray(on) {
    const tray = $('#cpPads');
    const show = !!on && !st.ended;
    tray.classList.toggle('on', show);
    if (show) {
      tray.querySelector('.txt .pt').textContent = T('pads_title');
      tray.querySelector('.txt p').innerHTML = NZA.rich(T('pads_text', keyLabel(st.keys.pads)));
      ['R', 'L'].forEach(k => {
        tray.querySelector(`.cp-pad[data-pad="${k}"]`).classList.toggle('used', st.pads[k]);
        tray.querySelector(`.slot[data-slot="${k}"]`).classList.toggle('done', st.pads[k]);
        if (!st.pads[k]) NZA.ui.Marker(APP, `pad${k}`, { label: k === 'R' ? T('pad_r') : T('pad_l'), dot: 'ring', anchor: `pad${k}` });
        else NZA.ui.Marker(APP, `pad${k}`, {}).remove();
      });
    } else {
      NZA.ui.Marker(APP, 'padR', {}).remove(); NZA.ui.Marker(APP, 'padL', {}).remove();
    }
    updateWorldPads();
  }
  function startDrag(e, k) {
    if (st.pads[k] || st.ended) return;
    e.preventDefault();
    const g = $('#cpGhost');
    g.innerHTML = padSVG(k); g.classList.add('on');
    st.drag = { k };
    moveDrag(e);
  }
  function moveDrag(e) {
    if (!st.drag || !e) return;
    const z = NZA.zoom || 1;
    const g = $('#cpGhost');
    g.style.left = `${e.clientX / z}px`; g.style.top = `${e.clientY / z}px`;
  }
  function endDrag(e, cancel) {
    if (!st.drag) return;
    const k = st.drag.k;
    st.drag = null;
    $('#cpGhost').classList.remove('on');
    if (cancel || !e) return;
    const hit = dropTarget(e.clientX, e.clientY);
    if (!hit) { pp && pp.flash('warn', T('pad_miss'), 2200); return; }
    if (hit !== k) { pp && pp.flash('warn', T('pad_wrong', hit === 'R' ? T('pad_r') : T('pad_l')), 2600); return; }
    placePad(k);
  }
  function dropTarget(x, y) {
    const snap = (st.cfg.snap || 70) * (NZA.zoom || 1);   // 1080p pixels: the pads and markers scale with the UI
    let best = null, bd = Infinity;
    ['R', 'L'].forEach(k => {
      const a = anchors.get(`pad${k}`);
      if (a && a.visible !== false) { const d = Math.hypot(a.x * innerWidth - x, a.y * innerHeight - y); if (d < snap && d < bd) { bd = d; best = k; } }
      const s = root.querySelector(`.slot[data-slot="${k}"]`).getBoundingClientRect();
      const d2 = Math.hypot(s.left + s.width / 2 - x, s.top + s.height / 2 - y);
      if (d2 < Math.max(30, s.width) && d2 < bd) { bd = d2; best = k; }
    });
    return best;
  }
  async function placePad(k) {
    if (st.pads[k]) return;
    st.pads[k] = true;
    if (snd()) NZA.audio.tone(320, 70, { vol: 0.08, type: 'triangle' });
    pp && pp.flash('ok', T('pad_ok', k === 'R' ? T('pad_r') : T('pad_l')), 1600);
    padsTray(true);
    if (st.pads.R && st.pads.L && !st.padsBusy) {
      st.padsBusy = true;
      const r = await act('pads');
      st.padsBusy = false;
      if (r && r.ok) { st.padsOpen = false; padsTray(false); pp && pp.flash('ok', T('pads_done'), 2600); if (snd()) NZA.audio.success(); }
      else { st.pads = { R: false, L: false }; padsTray(true); }
    }
  }
  function onAnchors() { updateWorldPads(); }
  function updateWorldPads() {
    const z = NZA.zoom || 1;
    ['R', 'L'].forEach(k => {
      const e = $(`#cpW${k}`);
      const a = anchors && anchors.get(`pad${k}`);
      const show = st.open && !st.ended && (st.pads[k] || v_().pads) && a && a.visible !== false;
      e.classList.toggle('hide', !show);
      if (show) { e.style.left = `${a.x * innerWidth / z}px`; e.style.top = `${a.y * innerHeight / z}px`; }
    });
  }

  /* ═══════════════════════════ COMPRESSIONS & BREATHS ═══════════════════════════ */
  const compressPhase = ph => ph === 'compress' || ph === 'advised' || ph === 'charging';
  function nearestBeat(t) { const k = Math.round((t - st.beat0) / (st.period * 1000)); return st.beat0 + k * st.period * 1000; }

  function pressStart(t) {
    const v = v_();
    const ph = v.phase;
    if (!iAmComp()) {
      if (ph === 'breaths' && iBreathe()) return breathStart(t);
      pp && pp.flash('warn', T('f_partner'), 1400);
      return;
    }
    if (ph === 'breaths') { if (iBreathe()) return breathStart(t); pp && pp.flash('warn', T('l_handsoff'), 1400); return; }
    if (ph === 'rosc') return;
    if (ph === 'charged') { post('hands'); pp && pp.flash('bad', T('f_hands'), 2200); if (snd()) NZA.audio.alarm(2); }
    if (ph === 'analyse') { pp && pp.flash('bad', T('f_motion'), 2200); }
    if (st.waitBreaths && compressPhase(ph)) { pp && pp.flash('warn', T('f_waitbreath'), 1400); return; }
    if (st.easy && compressPhase(ph)) { st.auto = !st.auto; if (st.auto) { st.beat0 = t + 120; st.lastBeatIdx = -1; } return; }
    st.press = { at: t, err: (t - nearestBeat(t)) / 1000, ph };
    post('press');
    if (snd()) NZA.audio.tone(120, 70, { vol: 0.07, type: 'sine' });
  }
  function pressEnd(t) {
    if (st.breath) return breathEnd(t);
    const p = st.press;
    if (!p) return;
    st.press = null;
    compression(p.err, (t - p.at) / 1000, t, p.ph);
  }
  // one compression: err = seconds off the beat, hold = seconds the chest was pressed
  function compression(err, hold, t, ph) {
    const c = st.cfg;
    const depthCm = 6.25 * (1 - Math.exp(-hold / 0.055));
    let depthScore = depthCm >= 5 ? 100 : Math.max(0, 100 - (5 - depthCm) * 55);
    let recoil = hold <= c.pressMax ? 100 : Math.max(10, 100 - (hold - c.pressMax) * 320);
    if (hold > st.period * 0.92) recoil = Math.min(recoil, 15);
    const ae = Math.abs(err);
    let cls, timing;
    if (ae <= c.perfect) { cls = 'perfect'; timing = 100; }
    else if (ae <= c.good) { cls = 'good'; timing = 75; }
    else if (ae <= st.period * 0.42) { cls = err < 0 ? 'early' : 'late'; timing = 35; }
    else { cls = 'bad'; timing = 10; }
    if (st.lastPressAt) { const iv = (t - hold * 1000 - st.lastPressAt) / 1000; if (iv > 0.2 && iv < 1.6) { st.intervals.push(iv); if (st.intervals.length > 7) st.intervals.shift(); } }
    st.lastPressAt = t - hold * 1000;
    st.lastCompAt = t; st.idleWarned = false;
    if (st.intervals.length >= 2) st.rate = 60 / (st.intervals.reduce((a, b) => a + b, 0) / st.intervals.length);
    const q = timing * 0.45 + depthScore * 0.35 + recoil * 0.20;
    st.quality = st.quality ? st.quality + (q - st.quality) * 0.18 : q;
    st.depth = depthCm;
    st.recoil = st.recoil ? st.recoil + (recoil - st.recoil) * 0.2 : recoil;
    if (compressPhase(ph) && !st.waitBreaths) {
      const ss = st.setStats;
      if (cls === 'perfect' || cls === 'good') ss.on += 1; else if (cls === 'early') ss.early += 1; else if (cls === 'late') ss.late += 1; else ss.miss += 1;
      ss.n += 1; ss.recoil += recoil;
      if (st.setCells.length < (v_().perSet || c.perSet)) st.setCells.push(depthCm < 5 ? 'low' : (recoil < 60 ? 'lean' : (cls === 'bad' ? 'off' : 'ok')));
    }
    const b = st.batch;
    b.n += 1; b.timing += timing; b.depth += depthScore; b.recoil += recoil;
    st.bars.push({ d: depthCm, cls: depthCm < 5 ? 'low' : (recoil < 60 ? 'lean' : 'ok') });
    if (st.bars.length > 48) st.bars.shift();
    st.hits.push({ t, cls, err });
    if (st.hits.length > 16) st.hits.shift();
    pop(depthCm < 4.6 ? 'shallow' : recoil < 50 ? 'lean' : cls);
    const v = v_();
    if (compressPhase(ph) && !st.waitBreaths) {
      st.localSet += 1;
      const per = v.perSet || c.perSet;
      if (!v.continuous && st.localSet >= per && v.phase === 'compress') { st.waitBreaths = true; st.waitAt = now(); st.auto = false; report(true); }
      if (v.continuous && st.localSet >= per) { st.localSet = 0; resetSet(); }
    }
    if (now() - st.lastReport >= 1000) report(false);
  }
  function report(done) {
    const b = st.batch;
    st.lastReport = now();
    if (b.n <= 0 && !done) return;
    const n = Math.max(1, b.n);
    post('report', { n: b.n, timing: Math.round(b.timing / n), depth: Math.round(b.depth / n), recoil: Math.round(b.recoil / n), rate: Math.round(st.rate || 0), done: !!done });
    st.batch = zeroBatch();
  }
  function pop(cls) {
    const e = $('#cpPop');
    if (!e) return;
    const map = { perfect: 'l_perfect', good: 'l_good', early: 'l_early', late: 'l_late', bad: 'l_off', shallow: 'l_shallow', lean: 'l_lean' };
    e.textContent = T(map[cls] || 'l_good');
    e.className = `mt-pop cp-pop ${cls === 'shallow' || cls === 'lean' ? 'early' : cls}`;
    void e.offsetWidth; e.classList.add('go');
  }

  function breathTarget() { const v = v_(); return st.cfg.breathHold * (v.bvm ? 1 : st.cfg.mouthSlower); }
  function breathStart(t) {
    const v = v_();
    if (!v.bvm && st.cfg.mouthToMouth === false) return;
    if (st.breath) return;
    st.breath = { at: t };
    post('breathStart');
    if (snd()) NZA.audio.noise(Math.round(breathTarget() * 1000), { vol: 0.07, lp: v.bvm ? 900 : 600, hp: 200, attack: 0.3, release: 0.4 });
    if (st.easy) st.autoBreath = t + breathTarget() * 1000;
  }
  function breathEnd(t) {
    const b = st.breath;
    if (!b) return;
    if (b.frozen) { st.breath = null; return; }
    if (st.easy && st.autoBreath && t < st.autoBreath) return;   // easy: the breath finishes by itself
    st.breath = null; st.autoBreath = 0;
    const hold = (t - b.at) / 1000;
    const v = v_();
    const k = v.bvm ? 1 : st.cfg.mouthSlower;
    const bc = hold < st.cfg.tooShort * k ? 'short' : (hold > st.cfg.tooLong * k ? 'long' : 'ok');
    st.breathLog.push({ hold, cls: bc });
    if (st.breathLog.length > 2) st.breathLog.shift();
    if (bc === 'short') pp && pp.flash('warn', T('f_breath_short'), 1800);
    else if (bc === 'long') pp && pp.flash('bad', T('f_breath_long'), 1800);
    else pp && pp.flash('ok', T('f_breath_ok'), 1400);
    post('breath', { hold: Math.round(hold * 100) / 100 });
  }

  /* ─────────────── keys ─────────────── */
  function codeIs(e, k) { const c = st.keys[k]; return c && (e.code === c || (c === 'Space' && e.key === ' ')); }
  function onKeyDown(e) {
    if (!isTop()) return;
    if (st.ended) { if (e.key === 'Enter') { e.preventDefault(); NZA.close(APP); } return; }
    if (codeIs(e, 'compress')) { e.preventDefault(); e.stopPropagation(); if (!e.repeat) pressStart(e.timeStamp || now()); return; }
    if (e.repeat || e.key === 'Escape') return;
    const map = [['pads', () => runAction('pads')], ['analyse', () => runAction('analyse')], ['charge', () => doCharge()], ['shock', () => doShock()],
      ['adrenaline', () => runAction('adrenaline')], ['swap', () => v_().partner && runAction('swap')], ['pulse', () => runAction('pulse')], ['disarm', () => act('disarm')],
      ['energyUp', () => stepEnergy(1)], ['energyDown', () => stepEnergy(-1)], ['mode', () => setMode(v_().mode === 'manual' ? 'aed' : 'manual')],
      ['causes', () => { st.showCauses = !st.showCauses; renderTeam(); }]];
    for (const [k, fn] of map) if (codeIs(e, k)) { e.preventDefault(); fn(); return; }
  }
  function onKeyUp(e) {
    if (!st.open) return;
    if (codeIs(e, 'compress')) { e.preventDefault(); pressEnd(e.timeStamp || now()); }
  }

  /* ═══════════════════════════ FRAME LOOP ═══════════════════════════ */
  function frame(t) {
    if (!st.open) return;
    st.raf = requestAnimationFrame(frame);
    const v = v_();
    const ph = v.phase;
    // metronome
    const idx = Math.floor((t - st.beat0) / (st.period * 1000));
    if (idx !== st.lastBeatIdx && t >= st.beat0) {
      st.lastBeatIdx = idx;
      const metro = st.cfg.metronome !== false && iAmComp() && compressPhase(ph) && !st.waitBreaths && !st.ended;
      if (metro && snd()) NZA.audio.tick();
      if (st.auto && iAmComp() && compressPhase(ph) && !st.waitBreaths) {
        post('press');
        st.press = null;
        // preview only: a believable human spread; in game easy mode keeps perfect time
        const j = st.demoPlay ? Math.sin(idx * 2.7) * 0.06 + Math.sin(idx * 1.3) * 0.03 : 0;
        compression(j, st.demoPlay ? 0.13 + Math.abs(Math.sin(idx * 0.9)) * 0.06 : 0.15, t, ph);
        st.rate = 60 / st.period + (st.demoPlay ? Math.sin(idx * 0.7) * 3 : 0);
      }
    }
    if (st.auto && (!compressPhase(ph) || !iAmComp())) st.auto = false;
    // the server did not start the breaths (it counted fewer compressions): carry on with its count
    if (st.waitBreaths && ph === 'compress' && t - (st.waitAt || 0) > 2500) { st.waitBreaths = false; st.localSet = v.set || 0; }
    // easy breath finishes itself
    if (st.breath && st.autoBreath && t >= st.autoBreath) { st.autoBreath = 0; const b = st.breath; st.breath = { at: b.at }; breathEnd(t); }
    // leaning through the next beat
    if (st.press && t - st.press.at > 1600) { const p = st.press; st.press = null; compression(p.err, (t - p.at) / 1000, t, p.ph); }
    // idle warning
    if (iAmComp() && ph === 'compress' && !st.waitBreaths && !st.auto && st.lastCompAt && !st.idleWarned && t - st.lastCompAt > (st.cfg.idleWarn || 1.6) * 1000) {
      st.idleWarned = true; pp && pp.flash('warn', T('f_idle'), 2000); st.rate = 0;
    }
    if (st.batch.n > 0 && t - st.lastReport >= 1000) report(false);
    // charged beep
    if (ph === 'charged' && t - st.chargedBeep > 1000) { st.chargedBeep = t; if (snd()) NZA.audio.tone(1750, 140, { vol: 0.06, type: 'square' }); }
    // cycle / adrenaline voice prompts (once each)
    if (v.state === 'arrest' && checkDue() && v.pads && st.cycleWarned !== v.cycleNo) { st.cycleWarned = v.cycleNo; voice(T('v_check')); if (snd()) NZA.audio.alarm(1); }
    if (v.adrenaline && v.adrenaline.due && st.adrWarned !== (v.adrenaline.n || 0) + 1) { st.adrWarned = (v.adrenaline.n || 0) + 1; voice(T('v_adr')); }
    laneOverlay();
    drawMetro(t);
    drawFb(t);
    drawTube(t);
    if (!st._liveAt || t - st._liveAt > 120) { st._liveAt = t; renderLive(); renderMetro(t); }
    if (!st._ppAt || t - st._ppAt > 400) { st._ppAt = t; renderPP(false); }
    if (!st._teamAt || t - st._teamAt > 1000) { st._teamAt = t; renderTeam(); }
  }

  /* ─────────────── metronome card ─────────────── */
  // overlay over the side panels (the ring stays visible) for hands-off moments and the partner view
  function laneOverlay() {
    const v = v_();
    const ov = $('#cpLaneOv');
    if (!ov) return false;
    const body = ov.parentNode;
    const ph = v.phase;
    const set = (cls, ic, title, sub, p, right) => {
      const c = `ov on ${cls}`;
      if (ov.className !== c) { ov.className = c; ov.querySelector('.ic').innerHTML = icon(ic); }
      body.classList.add('ovl');
      const b = ov.querySelector('.ot b'), sp = ov.querySelector('.ot span'), em = ov.querySelector('.ob em');
      if (b.textContent !== title) b.textContent = title;
      if (sp.textContent !== sub) sp.textContent = sub;
      if (em.textContent !== (right || '')) em.textContent = right || '';
      ov.querySelector('.ob').style.display = p === null ? 'none' : '';
      if (p !== null) ov.querySelector('.bar i').style.width = `${clamp(p, 0, 1) * 100}%`;
      return true;
    };
    const pl = phaseLeft();
    const secs = x => (x === null ? '' : `${x.toFixed(1)} s`);
    if (ph === 'analyse') { const tot = st.cfg.analyseTime || 4; return set('red', 'hand', T('o_analyse'), T('o_analyse_s'), pl === null ? 0 : 1 - pl / tot, secs(pl)); }
    if (ph === 'charged') { const tot = st.cfg.chargedFor || 25; return set('red pulse', 'bolt', T('o_charged', curEnergy()), T('o_charged_s', pl === null ? '--' : Math.ceil(pl)), pl === null ? 1 : pl / tot, ''); }
    if (ph === 'breaths' && !iBreathe()) return set('amber', 'lungs', T('o_handsoff'), T('o_handsoff_s'), null);
    if (ph === 'rosc') return set('teal', 'heart', T('o_rosc'), T('o_rosc_s'), null);
    if (!iAmComp() && ph !== 'breaths') {
      if (ph === 'charging') { const tot = Math.max(0.1, (st.chargeMs || 2500) / 1000); return set('amber', 'bolt', T('o_charging', curEnergy()), T('o_charging_s'), pl === null ? 0 : 1 - pl / tot, secs(pl)); }
      const pq = v.quality ? `${Math.round(v.quality)}%` : '--';
      const q = v.quality || 0;
      return set(`partner ${q >= 75 ? 'qok' : q >= 50 ? 'qmid' : 'qbad'}`, 'heart', T('o_partner', v.compName || ''), T('o_partner_s', v.rate ? `${Math.round(v.rate)}/min` : '--', pq), clamp(q / 100, 0, 1), pq);
    }
    if (ov.className !== 'ov') ov.className = 'ov';
    body.classList.remove('ovl');
    return false;
  }

  const CELL = { ok: '#0fd4c4', low: '#f3c35a', lean: '#ff7478', off: '#ff7478', old: 'rgba(15,212,196,.45)' };
  const HIT = { perfect: '#0fd4c4', good: '#ffffff', early: '#f3c35a', late: '#f3c35a', bad: '#ff7478' };
  const breathSpan = () => { const k = v_().bvm ? 1 : st.cfg.mouthSlower; return { k, span: st.cfg.tooLong * k * 1.18 }; };
  const heldNow = t => (st.breath ? (st.breath.frozen || (t - st.breath.at) / 1000) : 0);
  const setCount = () => {
    const v = v_();
    const per = v.perSet || st.cfg.perSet;
    if (v.continuous) return (v.total || 0) % per;
    return iAmComp() ? Math.min(per, st.localSet) : Math.min(per, v.set || 0);
  };

  // the beat ring: outer = the 30 pushes of this set (coloured by quality), inner = a hand that
  // sweeps once per beat; press as it crosses the top window. Breaths: the ring times the hold.
  function drawMetro(t) {
    const cv = $('#cpRing');
    if (!cv) return;
    const { w, h, scale: s } = NZA.fitCanvas(cv);
    const ctx = cv.getContext('2d');
    ctx.clearRect(0, 0, w, h);
    if (Math.min(w, h) < 48 * s) return;   // card hidden (debrief) or not laid out yet
    const v = v_();
    const ph = v.phase;
    const cx = w / 2, cy = h / 2, R = Math.min(w, h) / 2;
    const TOP = -Math.PI / 2, TAU = Math.PI * 2;
    const handsOff = ph === 'analyse' || ph === 'charged';
    const breathing = ph === 'breaths' && iBreathe();
    // outer: set segments
    const per = v.perSet || st.cfg.perSet;
    const n = setCount();
    const cells = st.setCells, offs = n - cells.length;
    const r1 = R - 5 * s;
    const seg = TAU / per, gap = Math.min(0.05, seg * 0.28);
    ctx.lineCap = 'butt';
    ctx.lineWidth = 6 * s;
    for (let i = 0; i < per; i++) {
      const a0 = TOP + i * seg + gap / 2, a1 = a0 + seg - gap;
      let col = 'rgba(255,255,255,.07)';
      if (i < n) col = CELL[i >= offs ? cells[i - offs] : 'old'] || CELL.ok;
      else if (i === n && iAmComp() && compressPhase(ph) && !st.waitBreaths) col = `rgba(255,255,255,${0.18 + 0.14 * Math.sin(t / 160)})`;
      if (handsOff && i < n) col = 'rgba(255,116,120,.35)';
      ctx.strokeStyle = col;
      ctx.beginPath(); ctx.arc(cx, cy, r1, a0, a1); ctx.stroke();
    }
    // inner track
    const r2 = R - 18 * s;
    ctx.lineWidth = 2 * s;
    ctx.strokeStyle = 'rgba(255,255,255,.08)';
    ctx.beginPath(); ctx.arc(cx, cy, r2, 0, TAU); ctx.stroke();
    // inner ticks (quarter beats)
    ctx.strokeStyle = 'rgba(255,255,255,.16)'; ctx.lineWidth = 1 * s;
    for (let i = 1; i < 8; i++) { const a = TOP + i * TAU / 8; ctx.beginPath(); ctx.moveTo(cx + Math.cos(a) * (r2 - 4 * s), cy + Math.sin(a) * (r2 - 4 * s)); ctx.lineTo(cx + Math.cos(a) * (r2 + 2 * s), cy + Math.sin(a) * (r2 + 2 * s)); ctx.stroke(); }

    if (handsOff) {
      ctx.setLineDash([4 * s, 5 * s]); ctx.lineDashOffset = -t / 40;
      ctx.strokeStyle = 'rgba(255,116,120,.8)'; ctx.lineWidth = 2.5 * s;
      ctx.beginPath(); ctx.arc(cx, cy, r2, 0, TAU); ctx.stroke();
      ctx.setLineDash([]);
      return;
    }
    if (breathing) {
      const { k, span } = breathSpan();
      const A = sec => TOP + TAU * clamp(sec / span, 0, 1);
      ctx.lineCap = 'butt'; ctx.lineWidth = 7 * s;
      ctx.strokeStyle = 'rgba(8,175,162,.25)';
      ctx.beginPath(); ctx.arc(cx, cy, r2, A(st.cfg.tooShort * k), A(st.cfg.tooLong * k)); ctx.stroke();
      const held = heldNow(t);
      if (held > 0) {
        const over = held > st.cfg.tooLong * k;
        ctx.strokeStyle = over ? '#ff7478' : (held >= st.cfg.tooShort * k ? '#0fd4c4' : '#f2f4f5');
        ctx.lineCap = 'round'; ctx.lineWidth = 4 * s;
        ctx.shadowColor = ctx.strokeStyle; ctx.shadowBlur = 8 * s;
        ctx.beginPath(); ctx.arc(cx, cy, r2, TOP, A(held)); ctx.stroke();
        ctx.shadowBlur = 0;
      }
      const at = A(breathTarget());
      ctx.strokeStyle = '#fff'; ctx.lineWidth = 2 * s; ctx.lineCap = 'round';
      ctx.beginPath(); ctx.moveTo(cx + Math.cos(at) * (r2 - 6 * s), cy + Math.sin(at) * (r2 - 6 * s)); ctx.lineTo(cx + Math.cos(at) * (r2 + 6 * s), cy + Math.sin(at) * (r2 + 6 * s)); ctx.stroke();
      return;
    }
    // timing windows at the top
    const perMs = st.period * 1000;
    const pa = (st.cfg.perfect * 1000 / perMs) * TAU, ga = (st.cfg.good * 1000 / perMs) * TAU;
    const active = iAmComp() && compressPhase(ph) && !st.waitBreaths && !st.ended;
    const phase = (((t - st.beat0) / perMs) % 1 + 1) % 1;
    const near = active && (phase < 0.07 || phase > 0.93);
    ctx.lineCap = 'butt'; ctx.lineWidth = 7 * s;
    ctx.strokeStyle = 'rgba(8,175,162,.2)';
    ctx.beginPath(); ctx.arc(cx, cy, r2, TOP - ga, TOP + ga); ctx.stroke();
    ctx.strokeStyle = near ? '#5ff5e6' : 'rgba(15,212,196,.8)';
    if (near) { ctx.shadowColor = '#0fd4c4'; ctx.shadowBlur = 12 * s; }
    ctx.beginPath(); ctx.arc(cx, cy, r2, TOP - pa, TOP + pa); ctx.stroke();
    ctx.shadowBlur = 0;
    // your presses: dots at their timing error, sinking inward as they age
    st.hits.forEach(hh => {
      const age = t - hh.t;
      if (age > 1800 || hh.err === undefined) return;
      const a = TOP + (hh.err / st.period) * TAU;
      const r = r2 - 4 * s - 10 * s * (age / 1800);
      ctx.globalAlpha = clamp(1 - age / 1800, 0, 1);
      ctx.fillStyle = HIT[hh.cls] || '#fff';
      ctx.beginPath(); ctx.arc(cx + Math.cos(a) * r, cy + Math.sin(a) * r, 3 * s, 0, TAU); ctx.fill();
      ctx.globalAlpha = 1;
    });
    if (!active) return;
    // the sweeping hand with a comet tail
    const ang = TOP + phase * TAU;
    for (let i = 0; i < 14; i++) {
      const a0 = ang - (i + 1) * 0.07, a1 = ang - i * 0.07;
      ctx.strokeStyle = `rgba(255,255,255,${(0.5 * (1 - i / 14)).toFixed(3)})`;
      ctx.lineWidth = 3 * s; ctx.lineCap = 'butt';
      ctx.beginPath(); ctx.arc(cx, cy, r2, a0, a1); ctx.stroke();
    }
    ctx.fillStyle = '#ffffff'; ctx.shadowColor = near ? '#0fd4c4' : 'rgba(255,255,255,.8)'; ctx.shadowBlur = 10 * s;
    ctx.beginPath(); ctx.arc(cx + Math.cos(ang) * r2, cy + Math.sin(ang) * r2, 4.5 * s, 0, TAU); ctx.fill();
    ctx.shadowBlur = 0;
    if (st.press) {
      const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, r2);
      g.addColorStop(0, 'rgba(15,212,196,.0)'); g.addColorStop(1, 'rgba(15,212,196,.22)');
      ctx.fillStyle = g; ctx.beginPath(); ctx.arc(cx, cy, r2 - 3 * s, 0, TAU); ctx.fill();
    }
  }

  // text parts of the metronome card (≈ 8 Hz)
  function renderMetro(t) {
    const v = v_();
    const card = $('#cpMetro');
    if (!card) return;
    const ph = v.phase;
    const breathing = ph === 'breaths' && iBreathe();
    card.classList.toggle('breath', breathing);
    card.classList.toggle('off', ph === 'analyse' || ph === 'charged');
    $('#cpMtBpm').textContent = String(Math.round(60 / st.period));
    const au = $('#cpMtAuto');
    au.style.display = st.easy && iAmComp() ? '' : 'none';
    au.classList.toggle('on', !!st.auto);
    const per = v.perSet || st.cfg.perSet;
    if (breathing) { $('#cpMtN').textContent = String(Math.min(2, 2 - (v.breathsLeft || 0) + (st.breath ? 1 : 0))); $('#cpMtOf').textContent = '/2'; }
    else { $('#cpMtN').textContent = String(setCount()); $('#cpMtOf').textContent = `/${per}`; }
    const tim = $('#cpTim');
    let html;
    if (breathing) {
      const rows = [0, 1].map(i => {
        const b = st.breathLog[i];
        const lab = b ? T(b.cls === 'ok' ? 'm_ok' : b.cls === 'short' ? 'm_short' : 'm_long') : T('m_wait');
        return `<div class="br ${b ? b.cls : ''}"><span class="n">${i + 1}</span><span class="k">${esc(lab)}</span><b>${b ? `${b.hold.toFixed(1)} s` : '—'}</b></div>`;
      }).join('');
      html = `<div class="th">${esc(T('m_breaths'))}</div>${rows}`;
    } else {
      const ss = st.setStats, tot = Math.max(1, ss.n);
      const row = (cls, k, val, frac) => `<div class="tr ${cls}"><span class="k">${esc(k)}</span><span class="b"><i style="width:${(clamp(frac, 0, 1) * 100).toFixed(1)}%"></i></span><b>${val}</b></div>`;
      const rec = ss.n ? Math.round(ss.recoil / ss.n) : 0;
      html = `<div class="th">${esc(T('m_timing'))}</div>
        ${row('early', T('m_early'), ss.early, ss.early / tot)}
        ${row('on', T('m_on'), ss.on, ss.on / tot)}
        ${row('late', T('m_late'), ss.late + ss.miss, (ss.late + ss.miss) / tot)}
        ${row(`rc ${!rec ? '' : rec >= 80 ? 'ok' : rec >= 55 ? 'mid' : 'bad'}`, T('m_recoil'), rec ? `${rec}%` : '--', rec / 100)}`;
    }
    if (tim._html !== html) { tim.innerHTML = html; tim._html = html; }
    $('#cpDepthL').textContent = breathing ? T('m_rise') : T('m_depth');
  }

  // compression depth trace on the device screen: one dip per push, 5–6 cm band
  function drawFb(t) {
    const cv = $('#cpFb');
    if (!cv) return;
    const { w, h, scale } = NZA.fitCanvas(cv);
    const live = st.press ? liveDepth(t) : 0;
    const sig = `${st.bars.length}:${st.bars.length ? st.bars[st.bars.length - 1].d : 0}:${w}:${h}:${live.toFixed(2)}`;
    if (cv._sig === sig) return;
    cv._sig = sig;
    const ctx = cv.getContext('2d');
    ctx.fillStyle = '#020303'; ctx.fillRect(0, 0, w, h);
    const top = 14 * scale, bot = h - 5 * scale;
    const Y = cm => top + (bot - top) * clamp(cm / 7, 0, 1);
    ctx.fillStyle = 'rgba(15,212,196,.09)'; ctx.fillRect(0, Y(5), w, Y(6) - Y(5));
    ctx.strokeStyle = 'rgba(15,212,196,.35)'; ctx.lineWidth = 1; ctx.setLineDash([3 * scale, 3 * scale]);
    [5, 6].forEach(cm => { ctx.beginPath(); ctx.moveTo(0, Y(cm)); ctx.lineTo(w, Y(cm)); ctx.stroke(); });
    ctx.setLineDash([]);
    ctx.font = `600 ${7.5 * scale}px JetBrains Mono, monospace`; ctx.fillStyle = 'rgba(15,212,196,.55)';
    ctx.fillText('5', 3 * scale, Y(5) - 2 * scale); ctx.fillText('6', 3 * scale, Y(6) + 8 * scale);
    const stepX = 12 * scale, x0 = 14 * scale, room = w - x0 - 92 * scale;
    const list = st.bars.slice(-Math.max(1, Math.floor(room / stepX)));
    const dip = (x, d, base, col) => {
      ctx.strokeStyle = col; ctx.lineWidth = 1.8 * scale; ctx.shadowColor = col; ctx.shadowBlur = 4 * scale;
      ctx.beginPath(); ctx.moveTo(x, Y(0.2)); ctx.bezierCurveTo(x + stepX * 0.25, Y(0.2), x + stepX * 0.3, Y(d), x + stepX * 0.45, Y(d));
      ctx.bezierCurveTo(x + stepX * 0.6, Y(d), x + stepX * 0.7, Y(base), x + stepX, Y(base)); ctx.stroke();
      ctx.shadowBlur = 0;
    };
    list.forEach((b, i) => dip(x0 + i * stepX, b.d, b.cls === 'lean' ? 1.1 : 0.2, b.cls === 'ok' ? '#e9f6f4' : (b.cls === 'low' ? '#ffb224' : '#ff7a7e')));
    if (live > 0.05) dip(x0 + list.length * stepX, live, 0.2, '#0fd4c4');
  }
  const liveDepth = t => (st.press ? 6.25 * (1 - Math.exp(-((t - st.press.at) / 1000) / 0.055)) : 0);

  function drawTube(t) {
    const tube = $('#cpTube');
    if (!tube) return;
    const v = v_();
    const breathing = v.phase === 'breaths' && iBreathe();
    let frac = 0, cls = '';
    if (breathing) {
      const { k } = breathSpan();
      const held = heldNow(t);
      frac = clamp(held / (st.cfg.tooLong * k * 1.18), 0, 1);
      cls = held > st.cfg.tooLong * k ? 'bad' : (held >= st.cfg.tooShort * k ? 'ok' : (held > 0 ? 'low' : ''));
    } else {
      let cm = 0;
      if (st.press) cm = liveDepth(t);
      else if (st.lastCompAt && t - st.lastCompAt < 260) cm = st.depth * (1 - (t - st.lastCompAt) / 260);
      frac = clamp(cm / 7, 0, 1);
      cls = cm >= 5 ? 'ok' : (cm > 0.3 ? 'low' : '');
    }
    tube.style.height = `${frac * 100}%`;
    if (tube.className !== cls) tube.className = cls;
    if (!st._tubeAt || t - st._tubeAt > 150) {
      st._tubeAt = t;
      const dv = $('#cpDepthV'), ds = $('#cpDepthS');
      $('.mt-depth .tube .z').style.display = breathing ? 'none' : '';
      if (breathing) {
        const held = heldNow(t), { k } = breathSpan();
        dv.innerHTML = `${held ? held.toFixed(1) : breathTarget().toFixed(1)}<small>s</small>`;
        ds.textContent = held > st.cfg.tooLong * k ? T('m_long') : (held >= st.cfg.tooShort * k ? T('m_ok') : (held ? T('m_short') : T('m_wait')));
        ds.className = `s ${held > st.cfg.tooLong * k ? 'red' : held >= st.cfg.tooShort * k ? 'teal' : held ? 'amber' : ''}`;
        return;
      }
      const d = st.depth;
      dv.innerHTML = `${d ? d.toFixed(1) : '--'}<small>cm</small>`;
      const leaning = st.press && t - st.press.at > st.cfg.pressMax * 1000;
      if (leaning) { ds.textContent = T('d_lean'); ds.className = 's red'; }
      else if (d && d < 5) { ds.textContent = T('d_low'); ds.className = 's amber'; }
      else { ds.textContent = T('d_ok'); ds.className = `s ${d ? 'teal' : ''}`; }
    }
  }

  /* ═══════════════════════════ EVENTS ═══════════════════════════ */
  let bannerTimer = 0, bannerId = '';
  function banner(id, tone, ic, title, sub, ms) {
    const b = $('#cpBanner');
    bannerId = id;
    b.className = 'cp-banner nza-hud solid';
    void b.offsetWidth;
    b.className = `cp-banner nza-hud solid on ${tone}`;
    b.querySelector('.bi .ic').innerHTML = icon(ic);
    b.querySelector('.bt b').textContent = title;
    b.querySelector('.bt span').textContent = sub || '';
    clearTimeout(bannerTimer);
    if (ms) bannerTimer = setTimeout(() => hideBanner(id), ms);
  }
  function hideBanner(id) { if (id && id !== bannerId) return; const b = $('#cpBanner'); if (b) b.className = 'cp-banner nza-hud solid'; bannerId = ''; }
  // the unit's spoken prompt: shown on its own message line (speaker + level bars) for a few seconds
  let voiceTimer = 0;
  function voice(text, ms = 4200) {
    clearTimeout(voiceTimer);
    st.voice = text || '';
    if (text) {
      voiceTimer = setTimeout(() => { st.voice = ''; renderMsg(); }, ms);
      const pr = $('#cpPrm');
      if (pr) { pr.classList.remove('voice'); void pr.offsetWidth; }
    }
    renderMsg();
  }
  function rhLabel(r) { return r ? T(`rh_${r}`) : ''; }

  function event(ev) {
    if (!ev || !ev.kind || st.ended) return;
    const v = v_();
    const s = snd();
    switch (ev.kind) {
      case 'analysing':
        banner('analyse', '', 'ecg', T('b_analyse'), T('b_analyse_s'));
        voice(T('v_analyse')); st.auto = false;
        if (s) { NZA.audio.beep(880, 120); NZA.audio.tone(660, 120, { vol: 0.1, at: 0.18 }); }
        break;
      case 'motion':
        banner('motion', 'red', 'hand', T('b_motion'), T('b_motion_s'), 2600); voice(T('v_motion'));
        if (s) NZA.audio.alarm(2);
        break;
      case 'advice':
        if (ev.advice === 'shock') {
          banner('advice', 'amber', 'bolt', T('b_shock'), T('b_shock_s', rhLabel(ev.rhythm)), 3200);
          voice(v.mode === 'manual' ? T('v_shock_man') : T('v_shock'));
          if (s) NZA.audio.alarm(2);
        } else if (ev.advice === 'noshock') {
          st.noShockUntil = now() + 4500;
          banner('advice', '', 'heart', T('b_noshock'), T('b_noshock_s', rhLabel(ev.rhythm)), 3000);
          voice(T('v_noshock')); st.beat0 = now() + 300; st.lastBeatIdx = -1;
          if (s) NZA.audio.beep(520, 160);
        } else if (ev.advice === 'motion') {
          hideBanner('analyse');
        } else if (ev.advice === 'organised') {
          banner('advice', 'teal', 'heart', T('b_rosc'), T('b_rosc_s'), 3500);
        }
        break;
      case 'charging':
        if (s) NZA.audio.charge(ev.ms || 2500);
        st.chargeMs = ev.ms || 2500;
        break;
      case 'charged':
        banner('clear', 'red pulse', 'alert', T('b_clear'), T('b_clear_s'));
        voice(T('v_charged'));
        if (s) NZA.audio.ready();
        break;
      case 'disarmed':
        hideBanner('clear');
        break;
      case 'shock': {
        hideBanner('clear');
        const scr = $('#cpScr'); scr.classList.remove('flash'); void scr.offsetWidth; scr.classList.add('flash');
        if (s) NZA.audio.shock();
        if (ev.result === 'no_effect') banner('shock', 'amber', 'bolt', T('b_noeffect'), T('b_noeffect_s'), 2600);
        else if (ev.result === 'induced') banner('shock', 'red', 'bolt', T('b_induced'), T('b_induced_s'), 3200);
        else if (ev.result !== 'rosc') { banner('shock', '', 'bolt', T('b_shocked'), T('b_shocked_s', ev.energy, ev.n), 2600); voice(T('v_shocked')); }
        if (ev.result === 'changed') pp && pp.flash('warn', T('e_changed'), 2600);
        st.beat0 = now() + 300; st.lastBeatIdx = -1; st.localSet = 0; st.setPhase = ''; resetSet();
        break;
      }
      case 'zapped':
        banner('zapped', 'red', 'bolt', T('b_zapped'), T('b_zapped_s'), 3200);
        break;
      case 'rosc':
        banner('rosc', 'teal', 'heart', T('b_rosc'), T('b_rosc_s'), 5200); voice(T('v_rosc'));
        st.auto = false;
        if (s) NZA.audio.success();
        break;
      case 'rearrest':
        banner('rearrest', 'red', 'alert', T('b_rearrest'), T('b_rearrest_s'), 3200);
        if (s) NZA.audio.alarm(2);
        break;
      case 'arrested':
        banner('arrested', 'red', 'alert', T('b_arrested'), T('b_arrested_s'), 3200);
        if (s) NZA.audio.alarm(2);
        break;
      case 'breaths':
        st.waitBreaths = false; st.auto = false;
        if (ev.breather !== undefined && v.breather) voice(T('v_breaths'), 2600);
        break;
      case 'breath':
        break;
      case 'breaths_missed':
        pp && pp.flash('warn', T('e_missed', ev.n || 1), 2400);
        break;
      case 'adrenaline':
        pp && pp.flash('ok', T('e_adren', ev.n || 1), 2600);
        break;
      case 'swap':
        pp && pp.flash('ok', T('e_swap', ev.compName || ''), 2600);
        st.press = null; st.auto = false; st.intervals = []; st.rate = 0;
        break;
      case 'joined': NZA.toast({ title: T('t_arrest'), message: T('e_joined', ev.name || ''), type: 'info' }); break;
      case 'partner_left': NZA.toast({ title: T('t_arrest'), message: T('e_left', ev.name || ''), type: 'warning' }); break;
      case 'promoted': NZA.toast({ title: T('t_arrest'), message: T('e_promoted', ev.name || ''), type: 'warning' }); break;
    }
  }

  /* ═══════════════════════════ DEBRIEF ═══════════════════════════ */
  function ended(sum) {
    sum = sum || {};
    st.ended = true; st.auto = false; st.press = null; st.breath = null;
    padsTray(false); hideBanner(); voice(null);
    updateWorldPads();
    const reason = sum.left ? 'left' : (sum.reason || 'stopped');
    const titleKey = sum.rosc ? 'd_title_rosc' : ({ death: 'd_title_death', breathing: 'd_title_breathing', left: 'd_title_left' })[reason] || 'd_title_stopped';
    const parts = sum.parts || {};
    const has = sum.score !== undefined && sum.score !== null;
    const grade = sum.grade || (has ? 'C' : null);
    const box = $('#cpDeb');
    const tone = val => ((val || 0) >= 75 ? 'teal' : (val || 0) >= 50 ? 'amber' : 'red');
    const C1 = 2 * Math.PI * 42, C2 = 2 * Math.PI * 17;
    const score = has ? clamp(Math.round(sum.score), 0, 100) : 0;
    const rows = [
      [T('d_duration'), NZA.fmt.time(sum.duration || 0), 'clock'],
      [T('d_comp'), sum.compressions || 0, 'heart'],
      [T('d_shocks'), sum.shocks || 0, 'bolt'],
      [T('d_adr'), sum.adrenaline || 0, 'syringe'],
    ];
    const rings = has ? [[T('d_quality'), parts.quality], [T('d_ccf'), parts.ccf], [T('d_vent'), parts.vent], [T('d_protocol'), parts.protocol]] : [];
    const fb = [];
    if (sum.rosc) fb.push(['', T('fb_rosc', NZA.fmt.time(sum.duration || 0))]);
    if (has) {
      if ((parts.quality || 0) < 60) fb.push(['bad', T('fb_quality', parts.quality || 0)]);
      if ((parts.ccf || 0) < 80) fb.push(['warn', T('fb_ccf', parts.ccf || 0)]);
      if ((parts.vent || 0) < 50) fb.push(['warn', T('fb_vent', parts.vent || 0)]);
      if ((parts.protocol || 0) < 75) fb.push(['bad', T('fb_protocol')]);
      if (!(sum.adrenaline > 0) && (sum.duration || 0) > 240) fb.push(['warn', T('fb_adr')]);
      if (fb.length === (sum.rosc ? 1 : 0)) fb.push(['', T('fb_good')]);
    }
    const rhFrom = sum.rhythmStart ? rhLabel(sum.rhythmStart) : '';
    const rhTo = sum.rhythmStart ? (sum.rosc ? T('rh_rosc') : rhLabel(sum.rhythmEnd)) : '';
    const ttl = sum.rosc ? 'teal' : (reason === 'death' ? 'red' : '');
    box.className = `cp-deb nza-hud solid ${ttl}`;
    box.innerHTML = `
      <div class="db-hd">
        <div class="db-score ${has ? tone(score) : 'none'}"><svg viewBox="0 0 100 100"><circle class="bg" cx="50" cy="50" r="42"/><circle class="fg" cx="50" cy="50" r="42" stroke-dasharray="${C1.toFixed(1)}" stroke-dashoffset="${C1.toFixed(1)}" data-off="${(C1 * (1 - score / 100)).toFixed(1)}"/></svg>
          <div class="c">${has ? `<b>${score}</b><span>${esc(T('d_score'))}</span>` : icon('heart')}</div>${grade && has ? `<em class="vd">${esc(T(({ A: 'dv_A', B: 'dv_B', C: 'dv_C', D: 'dv_D' })[grade] || 'dv_F'))}</em>` : ''}</div>
        <div class="db-t"><span class="k">${esc(T('d_kicker'))}</span><b class="${ttl}">${esc(T(titleKey))}</b><p>${esc(T('d_sub', v_().name || sum.name || T('npc'), T('r_' + reason)))}</p>
          ${rhFrom ? `<div class="path"><span class="l">${esc(T('d_path'))}</span><span class="rh">${esc(rhFrom)}</span>${icon('arrow-r')}<span class="rh ${sum.rosc ? 'ok' : ''}">${esc(rhTo)}</span></div>` : ''}</div>
      </div>
      <div class="db-il">${rows.map(([l, val, ic]) => `<div><span class="i">${icon(ic)}</span><span class="l">${esc(l)}</span><b>${esc(val)}</b></div>`).join('')}</div>
      ${rings.length ? `<div class="db-rings">${rings.map(([l, val]) => `<div class="${tone(val)}"><span class="rg"><svg viewBox="0 0 40 40"><circle class="bg" cx="20" cy="20" r="17"/><circle class="fg" cx="20" cy="20" r="17" stroke-dasharray="${C2.toFixed(1)}" stroke-dashoffset="${C2.toFixed(1)}" data-off="${(C2 * (1 - clamp((val || 0) / 100, 0, 1))).toFixed(1)}"/></svg><b>${Math.round(val || 0)}<small>%</small></b></span><span class="l">${esc(l)}</span></div>`).join('')}</div>` : ''}
      ${fb.length ? `<div class="db-tips"><div class="k">${esc(T('d_tips'))}</div><ul>${fb.map(([c, txt]) => `<li class="${c}">${esc(txt)}</li>`).join('')}</ul></div>` : ''}
      <div class="db-ft"><span class="sp"></span><button class="btn-teal" id="cpDone">${esc(T('d_done'))}<kbd>Enter</kbd></button></div>`;
    box.classList.add('on');
    // rings fill after the card lands
    requestAnimationFrame(() => requestAnimationFrame(() => box.querySelectorAll('circle.fg[data-off]').forEach(c => { c.style.strokeDashoffset = c.dataset.off; })));
    box.querySelector('#cpDone').onclick = () => NZA.close(APP);
    if (pp) pp.el.style.display = 'none';
    dev.classList.add('cp-dim');
    if (has) NZA.toast({ title: T(titleKey), message: `${T('d_score')} ${score} · ${sum.compressions || 0} ${T('d_comp').toLowerCase()} · ${NZA.fmt.time(sum.duration || 0)}`, icon: sum.rosc ? 'heart' : 'ecg', type: sum.rosc ? 'success' : 'info' });
    if (snd()) (sum.rosc ? NZA.audio.success() : NZA.audio.fail());
  }

  /* ═══════════════════════════ PREVIEW (browser only) ═══════════════════════════ */
  const DEMO_CAUSES = [{ k: 'hypovolemia', s: 'suspect', v: '~1.9 L' }, { k: 'hypoxia', s: 'treating', v: '72%' }, { k: 'hypothermia', s: 'ok', v: '35.9°' }, { k: 'tension', s: 'unknown' }, { k: 'tamponade', s: 'unknown' }, { k: 'toxins', s: 'unknown' }];
  const DEMO_LOG = [{ t: 0, text: 'CPR started by Ava Moreno', tone: 'teal' }, { t: 41, text: 'Pads on (Ava Moreno)' }, { t: 47, text: 'Analysis: VF, shock advised', tone: 'amber' }, { t: 52, text: 'Shock 1 at 200 J', tone: 'amber' }, { t: 64, text: 'Liam Carter joined the code', tone: 'teal' }];
  function demoView(o = {}) {
    return Object.assign({
      id: 'code_demo', pid: 'n:4512', name: 'Dario Kemp', sex: 'm', npc: false, role: 'comp', solo: false, compName: 'Ava Moreno', airName: 'Liam Carter', partner: 'Liam Carter',
      phase: 'compress', phaseLeft: null, state: 'arrest', kind: 'arrest', rhythm: 'vf', monitor: true, hr: 0, etco2: 14, set: 12, perSet: 30, total: 214,
      cycleNo: 2, cycleElapsed: 84, cycleLength: 120, quality: 86, rate: 110, depth: 88, recoil: 95, ccf: 84, vent: 72, ventN: 6, fatigue: 9, compFatigue: 9,
      pads: true, mode: 'manual', canManual: true, canAed: true, defib: 'item', energy: 200, energies: DEF_CFG.energies, aedEnergies: DEF_CFG.aedEnergies, advice: null, shocks: 1, lastEnergy: 200,
      adrenaline: { n: 1, since: 96, due: false, dueIn: 144, gap: 150, enabled: true, have: 3, access: true, needAccess: false },
      bvm: true, breather: false, breathsLeft: 0, continuous: false, intubated: false, causes: DEMO_CAUSES, log: DEMO_LOG, codeTime: 75, arrestTime: 262, easy: false, rosc: false, maxTeam: 2,
    }, o);
  }
  // A tiny stand-in for server/modules/cpr.lua so the preview is playable
  const sim = {
    v: null, timers: [],
    push() { state(Object.assign({}, this.v)); },
    later(ms, fn) { this.timers.push(setTimeout(fn, ms)); },
    log(text, tone) { this.v.log = (this.v.log || []).concat([{ t: Math.round(this.v.codeTime), text, tone }]).slice(-8); },
    report(d) {
      const v = this.v;
      if (v.phase === 'analyse') { if (!this.motion) { this.motion = true; event({ kind: 'motion' }); } return { ok: true }; }
      if (!compressPhase(v.phase)) return { ok: true };
      v.set = Math.min(v.perSet, v.set + d.n); v.total += d.n; v.rate = d.rate || v.rate; v.quality = Math.round((d.timing * 0.45 + d.depth * 0.35 + d.recoil * 0.2));
      if (v.phase === 'compress' && (v.set >= v.perSet || (d.done && v.set >= v.perSet - 4))) {
        v.phase = 'breaths'; v.breathsLeft = 2; v.breather = v.solo || v.role === 'air'; this.push(); event({ kind: 'breaths', breather: 1, bvm: v.bvm });
        this.later(10000, () => { if (this.v.phase === 'breaths') { this.v.phase = 'compress'; this.v.set = 0; this.push(); } });
        return { ok: true };
      }
      this.push(); return { ok: true };
    },
    breath(d) {
      const v = this.v;
      if (v.phase !== 'breaths') return { ok: true };
      v.breathsLeft -= 1; v.ventN += 1;
      event({ kind: 'breath', q: 80, left: v.breathsLeft });
      if (v.breathsLeft <= 0) { v.phase = 'compress'; v.set = 0; }
      this.push(); return { ok: true };
    },
    action(name, data) {
      const v = this.v;
      switch (name) {
        case 'pads': v.pads = true; v.monitor = true; this.log('Pads on'); this.push(); return { ok: true };
        case 'analyse':
          if (!v.pads) return { ok: false, err: 'no_pads', msg: 'Attach the pads first.' };
          v.phase = 'analyse'; v.phaseLeft = 4; this.motion = false; this.push(); event({ kind: 'analysing' });
          this.later(4000, () => {
            if (this.motion) { this.v.phase = 'compress'; this.v.phaseLeft = null; this.push(); event({ kind: 'advice', advice: 'motion' }); return; }
            const shock = this.v.rhythm === 'vf' || this.v.rhythm === 'vt';
            this.v.phase = shock ? 'advised' : 'compress'; this.v.phaseLeft = null; this.v.cycleElapsed = 0; this.v.cycleNo += 1;
            this.log(shock ? 'Analysis: VF, shock advised' : 'Analysis: no shock advised', shock ? 'amber' : '');
            this.push(); event({ kind: 'advice', advice: shock ? 'shock' : 'noshock', rhythm: this.v.rhythm });
          });
          return { ok: true };
        case 'charge': {
          if (!['compress', 'advised'].includes(v.phase)) return { ok: false, msg: 'Not now.' };
          const ms = Math.round(2500 * Math.pow(v.energy / 200, 0.6));
          v.phase = 'charging'; v.phaseLeft = ms / 1000; this.push(); event({ kind: 'charging', energy: v.energy, ms });
          this.later(ms, () => { if (this.v.phase === 'charging') { this.v.phase = 'charged'; this.v.phaseLeft = 25; this.push(); event({ kind: 'charged', energy: this.v.energy }); } });
          return { ok: true };
        }
        case 'disarm': v.phase = 'compress'; this.push(); event({ kind: 'disarmed' }); return { ok: true };
        case 'shock': {
          if (v.phase !== 'charged') return { ok: false, msg: 'Charge first.' };
          v.shocks += 1; v.phase = 'compress'; v.set = 0;
          const rosc = Math.random() < 0.5;
          this.log(`Shock ${v.shocks} at ${v.energy} J`, 'amber');
          event({ kind: 'shock', energy: v.energy, n: v.shocks, result: rosc ? 'rosc' : 'none' });
          if (rosc) { v.phase = 'rosc'; v.rosc = true; v.state = 'wounded'; v.rhythm = 'stach'; v.hr = 112; v.etco2 = 41; this.log('ROSC: pulse back', 'teal'); event({ kind: 'rosc' }); }
          this.push(); return { ok: true, result: rosc ? 'rosc' : 'none' };
        }
        case 'energy': v.energy = data.energy; this.push(); return { ok: true, energy: v.energy };
        case 'mode': v.mode = data.mode; this.push(); return { ok: true };
        case 'adrenaline': v.adrenaline = Object.assign({}, v.adrenaline, { n: v.adrenaline.n + 1, due: false, dueIn: 240, have: Math.max(0, v.adrenaline.have - 1) }); this.log(`Adrenaline 1 mg (dose ${v.adrenaline.n})`, 'teal'); this.push(); event({ kind: 'adrenaline', n: v.adrenaline.n }); return { ok: true, msg: 'Adrenaline 1 mg given.' };
        case 'swap': { const r = v.role === 'comp' ? 'air' : 'comp'; v.role = r; const a = v.compName; v.compName = v.airName; v.airName = a; this.push(); event({ kind: 'swap', compName: v.compName }); return { ok: true }; }
        case 'pulse': return v.state === 'arrest' ? { ok: true, pulse: false, rate: 0 } : { ok: true, pulse: true, rate: v.hr, weak: true };
      }
      return { ok: true };
    },
    start(v) {
      this.timers.forEach(clearTimeout); this.timers = [];
      this.v = v;
      clearInterval(this.tick);
      this.tick = setInterval(() => { if (!st.open || st.ended) return; this.v.codeTime += 1; this.v.cycleElapsed += 1; this.v.arrestTime += 1; if (this.v.adrenaline.dueIn) { this.v.adrenaline.dueIn = Math.max(0, this.v.adrenaline.dueIn - 1); if (this.v.adrenaline.dueIn === 0) this.v.adrenaline.due = true; } if (this.v.phaseLeft) this.v.phaseLeft = Math.max(0, this.v.phaseLeft - 1); this.push(); }, 1000);
    },
  };
  function fakeAnchors() {
    const map = { padR: { x: 0.36, y: 0.40, visible: true }, padL: { x: 0.47, y: 0.53, visible: true } };
    window.postMessage({ app: APP, action: 'anchors', data: map }, '*');
  }

  // states for screenshots / QA: NZA.apps.cpr.demo('compress' | 'breaths' | 'pads' | 'analyse' | 'charged' | 'rosc' | 'air' | 'easy' | 'debrief' | 'nodefib')
  function demo(name) {
    const base = {
      compress: {},
      breaths: { phase: 'breaths', breathsLeft: 1, breather: true, role: 'comp', solo: true, airName: null, partner: null, set: 0, ventN: 5, vent: 70, log: DEMO_LOG.slice(0, 4) },
      pads: { pads: false, monitor: false, rhythm: null, shocks: 0, phase: 'compress', set: 22, solo: true, airName: null, partner: null, log: DEMO_LOG.slice(0, 1), codeTime: 38, cycleNo: 1, cycleElapsed: 38, adrenaline: { n: 0, due: false, dueIn: null, enabled: true, have: 2 } },
      analyse: { phase: 'analyse', phaseLeft: 2.4, set: 0 },
      charged: { phase: 'charged', phaseLeft: 21, energy: 300, set: 17 },
      rosc: { phase: 'rosc', rosc: true, state: 'wounded', rhythm: 'stach', hr: 118, etco2: 41, shocks: 2, set: 0, causes: DEMO_CAUSES.map(c => (c.k === 'hypoxia' ? Object.assign({}, c, { s: 'ok' }) : c)) },
      air: { role: 'air', rhythm: 'asystole', mode: 'aed', set: 19, adrenaline: { n: 1, since: 250, due: true, dueIn: 0, gap: 150, enabled: true, have: 2, access: true } },
      easy: { easy: true, solo: true, airName: null, partner: null, rhythm: 'pea', hr: 34 },
      nodefib: { pads: false, monitor: false, defib: false, rhythm: null, solo: true, airName: null, partner: null, shocks: 0 },
      debrief: {},
    }[name] || {};
    const v = demoView(base);
    sim.start(v);
    NZA.demo(APP, { view: v, easy: !!v.easy });
    fakeAnchors();
    if (name === 'compress' || name === 'air' || name === 'easy' || name === 'charged' || name === 'analyse') {
      const t0 = now();
      [0, 1, 2, 3, 4, 5, 6, 7].forEach(i => { st.bars.push({ d: 5.2 + (i % 3) * 0.3, cls: 'ok' }); });
      st.bars.push({ d: 4.4, cls: 'low' }); st.bars.push({ d: 5.6, cls: 'ok' }); st.bars.push({ d: 5.9, cls: 'lean' });
      for (let i = 0; i < 10; i++) st.bars.push({ d: 5.3 + ((i * 7) % 5) * 0.15, cls: 'ok' });
      st.rate = 112; st.depth = 5.6; st.quality = 88; st.recoil = 93; st.localSet = v.set; st.lastCompAt = t0;
      const pat = ['ok', 'ok', 'ok', 'low', 'ok', 'ok', 'ok', 'ok', 'lean', 'ok', 'ok', 'ok', 'ok', 'ok', 'low', 'ok', 'ok', 'ok', 'ok'];
      st.setCells = pat.slice(0, v.set);
      st.setStats = { early: 2, on: Math.max(0, v.set - 3), late: 1, miss: 0, recoil: 93 * v.set, n: v.set };
      st.hits = [{ t: t0 - 260, cls: 'perfect', err: 0.02 }, { t: t0 - 800, cls: 'good', err: -0.11 }, { t: t0 - 1340, cls: 'perfect', err: 0.05 }, { t: t0 - 1600, cls: 'early', err: -0.2 }];
      if (name === 'easy') st.auto = true;
      if (name === 'compress') { st.auto = true; st.demoPlay = true; }
      setTimeout(() => pop('perfect'), 900);
    }
    if (name === 'pads') { st.padsOpen = true; padsTray(true); st.pads.R = true; padsTray(true); }
    if (name === 'analyse') { banner('analyse', '', 'ecg', T('b_analyse'), T('b_analyse_s')); voice(T('v_analyse'), 60000); }
    if (name === 'charged') { banner('clear', 'red pulse', 'alert', T('b_clear'), T('b_clear_s')); voice(T('v_charged'), 60000); }
    if (name === 'rosc') { banner('rosc', 'teal', 'heart', T('b_rosc'), T('b_rosc_s'), 60000); voice(T('v_rosc'), 60000); }
    if (name === 'breaths') { st.breath = { at: now(), frozen: 0.86 }; st.breathLog = [{ hold: 1.04, cls: 'ok' }]; }
    if (name === 'debrief') ended({ reason: 'rosc', rosc: true, duration: 412, compressions: 618, cycles: 6, shocks: 2, adrenaline: 1, score: 84, grade: 'A', parts: { quality: 86, ccf: 78, vent: 71, protocol: 90 }, rhythmStart: 'vf', rhythmEnd: 'stach', name: 'Dario Kemp' });
  }

  NZA.app(APP, {
    escClose: false,
    full: false,
    init(el) { build(el); },
    open, close,
    msg: { state, event, ended, pads(d) { if (d && d.open) { st.padsOpen = true; padsTray(true); } } },
    demo,
    preview() {
      NZA.mock(`${APP}:action`, d => sim.action(d.name, d.data || {}));
      NZA.mock(`${APP}:report`, d => sim.report(d));
      NZA.mock(`${APP}:breath`, d => sim.breath(d));
      NZA.mock(`${APP}:leave`, () => { setTimeout(() => ended({ reason: 'stopped', left: true, duration: Math.round(sim.v.codeTime), compressions: sim.v.total, shocks: sim.v.shocks }), 200); return { ok: true }; });
      const q = new URLSearchParams(location.search).get('demo');
      demo(q || 'compress');
    },
  });
})();
