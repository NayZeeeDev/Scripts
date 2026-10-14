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
    brand: 'NAYZEEE', model: 'RESQ 360', adult: 'ADULT', pads_on: 'PADS', pads_off: 'NO PADS', lead: 'PADS · II', code: 'CODE',
    tr_fb: 'CPR DEPTH', tr_co2: 'CO₂', hr: 'HR', energy: 'ENERGY', shocks: 'SHOCKS', etco2: 'EtCO₂', mmhg: 'mmHg',
    rate: 'RATE', per_min: '/MIN', compressions: 'COMPRESSIONS', perfect: 'PERFECT', too_fast: 'TOO FAST', too_slow: 'TOO SLOW',
    connect_pads: 'CONNECT PADS', no_defib: 'NO DEFIBRILLATOR', analysing: 'ANALYSING',
    aed: 'AED', manual: 'MAN', mode_aed: 'AED MODE', mode_manual: 'MANUAL', energy_select: 'ENERGY', charge: 'CHARGE', disarm: 'DISARM', shock: 'SHOCK', cycle: 'CYCLE', adr: 'ADR', due: 'DUE',
    sk_pads: 'PADS', sk_analyse: 'ANALYSE', sk_adren: 'ADRENALINE', sk_swap: 'SWAP', sk_pulse: 'PULSE',
    rh_vf: 'VF', rh_vt: 'VT', rh_pea: 'PEA', rh_asystole: 'ASYSTOLE', rh_sinus: 'SINUS', rh_stach: 'S.TACH', rh_sbrady: 'S.BRADY', rh_afib: 'AFIB', rh_rosc: 'ROSC', rh_none: '— — —',
    // device prompt line
    p_compress: 'COMPRESS ON THE BEAT', p_easy: 'START / STOP COMPRESSIONS', p_partner: 'PARTNER COMPRESSING · PADS · DRUGS', p_breath: 'HOLD · GIVE BREATH %s/%s',
    p_handsoff: 'HANDS OFF · BREATHS', p_analyse: 'ANALYSING · DO NOT TOUCH THE PATIENT', p_advised: 'SHOCK ADVISED · CHARGE', p_charging: 'CHARGING %s J · KEEP COMPRESSING',
    p_charged: 'STAND CLEAR · SHOCK', p_rosc: 'ROSC · CHECK THE PULSE', p_noshock: 'NO SHOCK ADVISED · RESUME CPR', p_check: 'RHYTHM CHECK DUE · ANALYSE',
    p_continuous: 'CONTINUOUS COMPRESSIONS · VENTILATOR', p_waitbreath: 'STOP · BREATHS NEXT',
    // team HUD
    t_arrest: 'Cardiac arrest', t_resp: 'Respiratory arrest', t_rosc: 'ROSC · pulse back', down: 'DOWN', ccf: 'CCF', adren: 'ADR',
    role_comp: 'COMPRESSIONS', role_air: 'AIRWAY · DEFIB · DRUGS', you: 'you', nobody: 'Nobody · you do the breaths (30:2)', fatigue: 'FATIGUE',
    join_hint: 'Another medic can choose Join CPR on the patient to take the airway and swap with you.',
    causes: 'Reversible causes (Hs & Ts)', log: 'Code log', npc: 'Unknown',
    c_hypovolemia: 'Hypovolaemia', c_hypoxia: 'Hypoxia', c_hypothermia: 'Hypothermia', c_tension: 'Tension pneumo', c_tamponade: 'Tamponade', c_toxins: 'Toxins',
    // pads
    pads_title: 'Place the pads', pads_text: 'Drag each pad onto the chest: **sternum** below the right collarbone, **apex** on the left side under the armpit. Or press {%s}.',
    pad_r: 'STERNUM', pad_l: 'APEX', pad_wrong: 'Wrong spot: that is the %s position.', pad_ok: '%s pad on.', pads_done: 'Pads on. The monitor shows the rhythm.',
    // proc panel
    pp_compress: 'Compress on the beat', pp_compress_t: 'Tap {%s} on every click: 100 to 120 per minute, deep and let the chest come back up. 30 compressions, then 2 breaths.',
    pp_compress_easy: 'Easy mode: press {%s} to start compressions; they run on the beat by themselves.',
    pp_partner: 'Your partner is compressing', pp_partner_t: 'Place the pads, analyse every 2 minutes, charge and shock, give adrenaline. Swap with {%s} when they tire.',
    pp_breaths: 'Give %s breaths', pp_breaths_1: 'Give the last breath', pp_breaths_bvm: 'Hold {%s} about 1 second per breath with the bag-valve mask and watch the chest rise.',
    pp_breaths_mouth: 'No bag-valve mask: mouth to mouth. Hold {%s} a little longer (1.3 s) per breath; it moves less air.',
    pp_breaths_wait: 'Hands off the chest', pp_breaths_wait_t: 'Your partner gives %s breaths. Get ready to compress again.',
    pp_analyse: 'Analysing the rhythm', pp_analyse_t: 'Everybody hands off. Any compression now spoils the analysis.',
    pp_advised: 'Shock advised', pp_advised_t: 'Keep compressing while you charge: {%s}. Then everybody stands clear.',
    pp_advised_man: 'Shockable rhythm', pp_noshock: 'No shock advised', pp_noshock_t: 'Resume compressions immediately. Think about the reversible causes and adrenaline.',
    pp_charging: 'Charging %s J', pp_charging_t: 'Keep compressing until the device is charged.',
    pp_charged: 'Stand clear!', pp_charged_t: 'Hands off the patient. Deliver the shock with {%s} or disarm with {%s}.',
    pp_rosc: 'ROSC: the heart is beating', pp_rosc_t: 'Check the carotid pulse with {%s}. Keep the pads on: they can arrest again.',
    pp_cont: 'Continuous compressions', pp_cont_t: 'The patient is intubated on a ventilator: compress without pauses, {%s} on the beat.',
    s_rate: 'Rate', s_depth: 'Depth', s_quality: 'Quality', s_vent: 'Ventilation', s_breaths: 'Breaths', s_etco2: 'EtCO₂', w_comp: 'Compressions', w_cycle: 'Cycle %s',
    cap_check: 'Rhythm check in %s', cap_due: 'Rhythm check due: analyse now', cap_adr_due: 'Adrenaline due', tag_cycle: 'Cycle %s', tag_easy: 'Easy mode',
    tool_pads: 'Pads', tool_analyse: 'Analyse', tool_charge: 'Charge', tool_disarm: 'Disarm', tool_shock: 'Shock', tool_adren: 'Adrenaline', tool_swap: 'Swap', tool_pulse: 'Pulse',
    hint_causes: 'Hs & Ts', hint_energy: 'energy', hint_orbit: 'orbit', hint_rmb: 'Right click', abort: 'Hold to stop CPR',
    // lane
    l_perfect: 'PERFECT', l_good: 'GOOD', l_early: 'EARLY', l_late: 'LATE', l_off: 'OFF BEAT', l_shallow: 'PUSH DEEPER', l_lean: 'LET IT RECOIL',
    l_breath: 'CHEST RISE', l_partner: '%s compresses: %s/min, quality %s', l_analyse: 'Analysing… hands off', l_charging: 'Charging', l_charged: 'Charged · stand clear', l_handsoff: 'Hands off · breaths',
    d_depth: 'DEPTH', d_ok: '5–6 cm', d_low: 'too shallow', d_lean: 'leaning',
    // flashes / voice
    f_hands: 'Hands off! The device is charged.', f_motion: 'Motion: the analysis needs everyone off the patient.', f_partner: 'Your partner is compressing.',
    f_waitbreath: 'Stop: breaths come next.', f_breath_short: 'Too short: the chest barely rose.', f_breath_long: 'Too long: air went into the stomach.', f_breath_ok: 'Good breath: chest rose.',
    f_no_defib: 'No defibrillator here: bring one (or a trauma kit), or work in the ambulance / hospital.', f_pulse_yes: 'Carotid pulse %s/min%s.', f_pulse_weak: ', weak', f_pulse_no: 'No pulse. Continue CPR.',
    f_idle: 'Keep going! Every second without compressions counts.', f_aed_energy: 'AED mode chooses the energy itself.',
    v_analyse: 'Analysing heart rhythm. Do not touch the patient.', v_shock: 'Shock advised. Charging.', v_shock_man: 'Shockable rhythm.', v_charged: 'Stand clear. Push the flashing shock button now.',
    v_noshock: 'No shock advised. Start CPR.', v_motion: 'Motion detected. Stop all motion.', v_breaths: 'Give two breaths.', v_check: 'Two minutes. Stop CPR and analyse.', v_adr: 'Consider adrenaline.',
    v_shocked: 'Shock delivered. Start CPR.', v_rosc: 'Pulse detected.', v_who: 'DEVICE',
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
    d_sub: '%s · %s', d_duration: 'DURATION', d_comp: 'COMPRESSIONS', d_quality: 'QUALITY', d_ccf: 'HANDS-ON', d_vent: 'BREATHS', d_shocks: 'SHOCKS', d_adr: 'ADRENALINE', d_protocol: 'PROTOCOL',
    d_rhythm: 'Rhythm %s → %s', d_done: 'Done',
    fb_rosc: 'Pulse back after %s of resuscitation.', fb_quality: 'Compression quality %s%%: press on the click and let the chest come all the way back up.',
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
  };
  const zeroBatch = () => ({ n: 0, timing: 0, depth: 0, recoil: 0 });
  st.batch = zeroBatch();

  let root, dev, pp = null, ecg = null, co2 = null, anchors = null;
  const $ = s => root.querySelector(s);
  const post = (n, d) => NZA.post(`${APP}:${n}`, d || {});
  const snd = () => st.cfg.sounds !== false && NZA.cfg.sounds !== false;

  /* ─────────────── SVG bits ─────────────── */
  const padSVG = (lab) => `<svg viewBox="0 0 44 56" width="100%" height="100%"><defs><linearGradient id="pg${lab}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f4f6f5"/><stop offset="1" stop-color="#cfd5d6"/></linearGradient></defs>
    <rect x="2" y="2" width="40" height="52" rx="9" fill="url(#pg${lab})" stroke="#08afa2" stroke-width="2"/><rect x="9" y="11" width="26" height="34" rx="6" fill="#9fb4b6" opacity=".55"/>
    <path d="M22 2v-2" stroke="#3c4245" stroke-width="3"/><text x="22" y="33" text-anchor="middle" font-family="Lexend,sans-serif" font-weight="800" font-size="9" fill="#065e57">${lab}</text></svg>`;
  const torsoSVG = `<svg viewBox="0 0 150 118"><path d="M38 6c8-4 22-5 37-5s29 1 37 5l26 14c6 3 9 9 9 16v40c0 5-4 8-8 7l-10-3v38H21V80l-10 3c-4 1-8-2-8-7V36c0-7 3-13 9-16z" fill="rgba(255,255,255,.04)" stroke="rgba(255,255,255,.22)" stroke-width="1.4"/>
    <path d="M75 12v62M52 30c7 3 15 4 23 4s16-1 23-4M50 46c8 3 16 4 25 4s17-1 25-4M52 62c7 2 15 3 23 3s16-1 23-3" stroke="rgba(255,255,255,.12)" stroke-width="1.2" fill="none"/>
    <path d="M44 14c10 5 20 7 31 7s21-2 31-7" stroke="rgba(255,255,255,.2)" stroke-width="1.4" fill="none"/></svg>`;
  const knobSVG = (list) => {
    const a0 = -135, a1 = 135, cx = 59, cy = 59;
    return `<svg viewBox="0 0 118 118">${list.map((e, i) => {
      const a = (a0 + (a1 - a0) * (i / Math.max(1, list.length - 1))) * Math.PI / 180;
      const x1 = cx + Math.sin(a) * 39, y1 = cy - Math.cos(a) * 39, x2 = cx + Math.sin(a) * 44, y2 = cy - Math.cos(a) * 44;
      const tx = cx + Math.sin(a) * 53, ty = cy - Math.cos(a) * 53 + 3;
      return `<line x1="${x1.toFixed(1)}" y1="${y1.toFixed(1)}" x2="${x2.toFixed(1)}" y2="${y2.toFixed(1)}" stroke="rgba(255,255,255,.5)" stroke-width="2"/><text data-e="${e}" x="${tx.toFixed(1)}" y="${ty.toFixed(1)}" text-anchor="middle" font-family="JetBrains Mono,monospace" font-size="8.5" font-weight="700" fill="rgba(255,255,255,.45)">${e}</text>`;
    }).join('')}</svg>`;
  };

  /* ═══════════════════════════ DOM ═══════════════════════════ */
  function build(el) {
    root = el;
    el.innerHTML = `
      <div class="cp-wrap">
        <div class="cp-team nza-hud rail" id="cpTeam"></div>
        <div class="cp-banner nza-hud solid" id="cpBanner"><div class="bi"></div><div><b></b><span></span></div></div>
        <div class="cp-pads nza-hud solid" id="cpPads">
          <div class="torso">${torsoSVG}<span class="slot" data-slot="R" style="left:52px;top:34px">${padSVG('R')}</span><span class="slot" data-slot="L" style="left:108px;top:72px">${padSVG('L')}</span></div>
          <div class="txt"><b class="pt"></b><p></p>
            <div class="row"><span class="cp-padl">${esc(T('pad_r'))}</span><div class="cp-pad" data-pad="R">${padSVG('R')}</div><span class="cp-padl" style="margin-left:14px">${esc(T('pad_l'))}</span><div class="cp-pad" data-pad="L">${padSVG('L')}</div></div>
          </div>
        </div>
        <div class="cp-padg" id="cpGhost"></div>
        <div class="cp-wpad hide" id="cpWR">${padSVG('R')}</div><div class="cp-wpad hide" id="cpWL">${padSVG('L')}</div>
        <div class="cp-dev" id="cpDev">
          <div class="cp-voice"><div class="nza-hud solid" id="cpVoice"><span class="ic">${icon('defib')}</span><span class="who"></span><span class="tx"></span></div></div>
          <div class="cp-handle"></div>
          <div class="dev cp-body">
            <span class="cp-bump tl"></span><span class="cp-bump tr"></span><span class="cp-bump bl"></span><span class="cp-bump br"></span>
            <div class="cp-top"><div class="dev-brand"><span class="nz-mark"></span><b>${esc(T('brand'))}</b></div><span class="model">${esc(T('model'))}</span><span class="sp"></span>
              <span class="cp-tag" id="cpModeTag"></span><span class="cp-tag" id="cpPadsTag"></span><span class="dev-led" id="cpLed"></span></div>
            <div class="cp-grid">
              <div>
                <div class="dev-screen cp-scr" id="cpScr">
                  <div class="cp-hdr"><span id="cpHdrL"></span><span class="cp-rh" id="cpRh"></span><span class="r"><span>${esc(T('code'))}</span><b id="cpCode">00:00</b></span></div>
                  <div class="cp-main">
                    <div class="cp-traces">
                      <div class="cp-tr ecg"><span class="tl g">${esc(T('lead'))}</span><canvas id="cpEcg"></canvas><div class="cp-msg dash" id="cpEcgMsg"></div><span class="cp-anl" id="cpAnl"></span></div>
                      <div class="cp-tr fb"><span class="tl w">${esc(T('tr_fb'))}</span><canvas id="cpFb"></canvas></div>
                      <div class="cp-tr co2"><span class="tl y">${esc(T('tr_co2'))}</span><canvas id="cpCo2"></canvas></div>
                    </div>
                    <div class="cp-nums">
                      <div class="cp-n hr" id="cpNHr"><span class="k">${esc(T('hr'))}</span><span class="v">---</span></div>
                      <div class="cp-n en" id="cpNEn"><span class="k">${esc(T('energy'))}</span><span class="v">200<small>J</small></span></div>
                      <div class="cp-n sh" id="cpNSh"><span class="k">${esc(T('shocks'))}</span><span class="v">0</span></div>
                      <div class="cp-n co" id="cpNCo"><span class="k">${esc(T('etco2'))}</span><span class="v">--</span><span class="s">${esc(T('mmhg'))}</span></div>
                    </div>
                  </div>
                  <div class="cp-mt">
                    <div class="cp-m"><div class="row">${esc(T('rate'))} <b id="cpRate">---</b>${esc(T('per_min'))}<span class="sp"></span><span class="cp-chip" id="cpRateChip">—</span></div>
                      <div class="cp-bar"><span class="zone" id="cpRateZone"></span><span class="mk" id="cpRateMk" style="left:0"></span></div></div>
                    <div class="cp-m"><div class="row">${esc(T('compressions'))} <b id="cpCnt">0/30</b><span class="sp"></span><span class="q" id="cpQ">--%</span></div>
                      <div class="cp-bar segs" id="cpCntBar"><i style="width:0"></i></div></div>
                  </div>
                  <div class="cp-prm" id="cpPrm"><kbd></kbd><span class="t"></span><span class="sp"></span><span class="side" id="cpPrmSide"></span></div>
                  <div class="cp-sl" id="cpSl"><span data-sk="pads"></span><span data-sk="analyse"></span><span data-sk="adren"></span><span data-sk="four"></span></div>
                  <div class="cp-chg"><i id="cpChg"></i></div>
                </div>
                <div class="cp-softkeys"><button class="dev-btn cp-soft" data-sk="pads"></button><button class="dev-btn cp-soft" data-sk="analyse"></button><button class="dev-btn cp-soft" data-sk="adren"></button><button class="dev-btn cp-soft" data-sk="four"></button></div>
              </div>
              <div class="cp-side">
                <div class="cp-lbl">${esc(T('energy_select'))}</div>
                <div class="cp-knob" id="cpKnob" data-wheel="1"><div class="kt"></div><div class="cap"></div></div>
                <div class="cp-mode" id="cpMode"><button data-m="aed">${esc(T('aed'))}</button><button data-m="manual">${esc(T('manual'))}</button></div>
                <button class="dev-btn cp-charge" id="cpCharge"><span class="f"></span><span class="lab">${esc(T('charge'))}</span></button>
                <div class="cp-lbl" style="margin-top:2px">${esc(T('shock'))}</div>
                <div class="cp-shock" id="cpShock">${icon('bolt')}</div>
              </div>
            </div>
          </div>
        </div>
        <div class="cp-deb nza-hud solid rail" id="cpDeb"></div>
      </div>`;
    dev = $('#cpDev');
    anchors = NZA.ui.Anchors(APP);
    anchors.on(onAnchors);

    // hardware
    root.querySelectorAll('[data-sk]').forEach(b => { if (b.tagName === 'BUTTON') b.addEventListener('click', () => { blur(); softKey(b.dataset.sk); }); });
    $('#cpCharge').addEventListener('click', () => { blur(); doCharge(); });
    $('#cpShock').addEventListener('click', () => { blur(); doShock(); });
    $('#cpMode').addEventListener('click', e => { const b = e.target.closest('button'); blur(); if (b && !b.disabled) setMode(b.dataset.m); });
    const knob = $('#cpKnob');
    knob.addEventListener('click', e => { const r = knob.getBoundingClientRect(); stepEnergy(e.clientX < r.left + r.width / 2 ? -1 : 1); });
    knob.addEventListener('wheel', e => { e.preventDefault(); stepEnergy(e.deltaY > 0 ? -1 : 1); }, { passive: false });

    // pads drag
    root.querySelectorAll('.cp-pad').forEach(p => p.addEventListener('pointerdown', e => startDrag(e, p.dataset.pad)));
    window.addEventListener('pointermove', moveDrag);
    window.addEventListener('pointerup', endDrag);

    window.addEventListener('keydown', onKeyDown, true);
    window.addEventListener('keyup', onKeyUp, true);
  }
  const blur = () => { if (document.activeElement && document.activeElement.blur) document.activeElement.blur(); };
  const isTop = () => st.open && NZA.isOpen(APP) && NZA.stack[NZA.stack.length - 1] === APP;

  /* ═══════════════════════════ OPEN / CLOSE ═══════════════════════════ */
  function open(data) {
    data = data || {};
    if (data.locale) L = Object.assign({}, L, data.locale);
    st.cfg = Object.assign({}, DEF_CFG, data.cfg || {});
    st.keys = Object.assign({}, DEF_KEYS, data.keys || {});
    st.easy = !!data.easy || !!(data.view && data.view.easy);
    st.open = true; st.ended = false; st.view = null;
    st.localSet = 0; st.waitBreaths = false; st.bars = []; st.hits = []; st.intervals = []; st.rate = 0; st.depth = 0; st.quality = 0;
    st.press = null; st.breath = null; st.auto = false; st.batch = zeroBatch(); st.lastReport = now(); st.lastCompAt = 0; st.lastPressAt = 0;
    st.pads = { R: false, L: false }; st.padsBusy = false; st.padsOpen = false; st.drag = null; st.noShockUntil = 0; st.cycleWarned = 0; st.adrWarned = 0; st.autoCharged = false; st.lastPP = '';
    st.period = 60 / (st.cfg.target || 110); st.beat0 = now() + 400; st.lastBeatIdx = -1;
    root.querySelectorAll('.cp-dev,.cp-team').forEach(e => { e.style.display = ''; });
    dev.classList.remove('cp-dim');
    $('#cpDeb').classList.remove('on');
    hideBanner(); voice(null);
    $('#cpKnob .kt').innerHTML = knobSVG(st.cfg.energies);

    if (!ecg) ecg = NZA.vitals.Trace($('#cpEcg'), { type: 'ecg', rhythm: 'asystole', rate: 60, color: '#3ddc84', speed: 0.2, gain: 0.36, onBeat: () => { const v = st.view; if (v && v.monitor && snd() && !ARREST_RH[v.rhythm] && v.rhythm) NZA.audio.heartbeat(v.spo2 || 96); } });
    else { ecg.start(); ecg.clear(); }
    if (!co2) co2 = NZA.vitals.Trace($('#cpCo2'), { type: 'co2', rr: 0, etco2: 0, color: '#f2d64b', speed: 0.12, gain: 0.3, glow: false });
    else { co2.start(); co2.clear(); }

    if (pp) pp.destroy();
    pp = NZA.ui.ProcPanel(root.querySelector('.cp-wrap'), {
      step: 1, total: 5, title: T('pp_compress'), text: '', abort: { label: T('abort'), key: 'ESC', seconds: 1.2 },
      onAbort: () => { if (!st.ended) post('leave'); }, onTool: k => toolKey(k),
    });
    const lane = document.createElement('div');
    lane.className = 'cp-lane';
    lane.innerHTML = `<div class="cp-beat"><canvas id="cpLane"></canvas><div class="cp-pop" id="cpPop"></div><div class="ov" id="cpLaneOv"><span class="ic"></span><span class="tx"></span><span class="bar"><i></i></span></div></div>
      <div class="cp-depth"><div class="tube"><span class="z"></span><i id="cpTube"></i></div><div><div class="l">${esc(T('d_depth'))}</div><div class="v" id="cpDepthV">--<small>cm</small></div><div class="s" id="cpDepthS">${esc(T('d_ok'))}</div></div></div>`;
    pp.slot.parentNode.insertBefore(lane, pp.slot);
    const z = $('.cp-depth .tube .z'); z.style.top = `${(5 / 7) * 100}%`; z.style.height = `${(1 / 7) * 100}%`;
    // depth tube: top = 0 cm, bottom = 7 cm → the zone sits between 5 and 6 cm from the top

    if (data.view) state(data.view);
    cancelAnimationFrame(st.raf);
    st.raf = requestAnimationFrame(frame);
  }

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
    if (to === 'breaths') { st.waitBreaths = false; st.setPhase = 'breaths'; st.localSet = 0; if (st.breath) st.breath = null; }
    if (to === 'compress' && from !== 'advised' && from !== 'charging') { st.beat0 = now() + 250; st.lastBeatIdx = -1; st.idleWarned = false; }
    if (to === 'compress' && (from === 'breaths' || from === 'charged' || from === 'analyse')) { st.setPhase = ''; st.localSet = 0; st.waitBreaths = false; }
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

  function rhythmInfo(v) {
    if (!v.monitor) return { text: T('rh_none'), cls: '' };
    if (v.rosc && v.state !== 'arrest') return { text: T('rh_rosc'), cls: 'green' };
    const r = v.rhythm || 'asystole';
    const text = T(`rh_${r}`);
    if (r === 'vf' || r === 'vt') return { text, cls: 'red blink' };
    if (r === 'asystole') return { text, cls: 'red' };
    if (r === 'pea') return { text, cls: 'amber' };
    return { text, cls: 'green' };
  }

  /* ─────────────── device ─────────────── */
  function renderDevice() {
    const v = v_();
    const defib = !!v.defib || !!v.pads;
    $('#cpHdrL').textContent = `${T('adult')} · ${v.pads ? T('pads_on') : T('pads_off')}`;
    const mt = $('#cpModeTag');
    mt.textContent = v.mode === 'manual' ? T('mode_manual') : T('mode_aed');
    mt.className = `cp-tag ${v.mode === 'manual' ? '' : 'on'}`;
    const pt = $('#cpPadsTag');
    pt.textContent = v.pads ? T('pads_on') : (defib ? T('pads_off') : T('no_defib'));
    pt.className = `cp-tag ${v.pads ? 'on' : (defib ? '' : 'red')}`;
    $('#cpLed').className = `dev-led ${v.phase === 'charged' ? 'red cp-led blink' : (v.pads ? '' : 'off')}`;
    const rh = rhythmInfo(v);
    const rhe = $('#cpRh'); rhe.textContent = rh.text; rhe.className = `cp-rh ${rh.cls}`;
    const msg = $('#cpEcgMsg');
    if (!v.pads && !v.monitor) { msg.className = 'cp-msg dash on'; msg.innerHTML = `${icon(defib ? 'link' : 'alert')}<span>${esc(defib ? T('connect_pads') : T('no_defib'))}</span>`; }
    else msg.className = 'cp-msg';
    const anl = $('#cpAnl');
    anl.textContent = `${T('analysing')}…`;
    anl.classList.toggle('on', v.phase === 'analyse');
    // numbers
    const arrestRh = v.state === 'arrest' && ARREST_RH[v.rhythm];
    const hr = $('#cpNHr');
    hr.querySelector('.v').textContent = !v.monitor ? '--' : (v.state === 'arrest' && (v.rhythm === 'vf' || v.rhythm === 'asystole')) ? '---' : String(Math.round(v.hr || 0));
    hr.classList.toggle('alarm', !!(v.monitor && arrestRh));
    const en = $('#cpNEn');
    en.querySelector('.v').innerHTML = `${curEnergy()}<small>J</small>`;
    en.classList.toggle('ready', v.phase === 'charged');
    $('#cpNSh .v').textContent = String(v.shocks || 0);
    const co = shownEtco2();
    $('#cpNCo .v').textContent = v.monitor && co ? String(Math.round(co)) : '--';
    // knob
    const knob = $('#cpKnob');
    const list = st.cfg.energies || [];
    const idx = Math.max(0, list.indexOf(curEnergy()));
    const ang = -135 + 270 * (idx / Math.max(1, list.length - 1));
    knob.querySelector('.cap').style.transform = `rotate(${ang}deg)`;
    knob.classList.toggle('aed', v.mode !== 'manual');
    knob.querySelectorAll('text').forEach(tx => tx.setAttribute('fill', Number(tx.dataset.e) === curEnergy() ? '#ffffff' : 'rgba(255,255,255,.4)'));
    // mode
    $('#cpMode').querySelectorAll('button').forEach(b => {
      b.classList.toggle('on', (b.dataset.m === 'manual') === (v.mode === 'manual'));
      b.disabled = (b.dataset.m === 'manual' && !v.canManual) || v.phase === 'charging' || v.phase === 'charged';
    });
    // charge / shock
    const ch = $('#cpCharge');
    const charging = v.phase === 'charging', charged = v.phase === 'charged';
    ch.querySelector('.lab').textContent = charged || charging ? T('disarm') : T('charge');
    ch.classList.toggle('ready', charged);
    ch.classList.toggle('off', !v.pads || (v.mode !== 'manual' && v.phase !== 'advised' && !charging && !charged));
    $('#cpShock').classList.toggle('armed', charged);
    // soft keys
    const labels = { pads: v.pads ? `${T('sk_pads')} ✓` : T('sk_pads'), analyse: T('sk_analyse'), adren: `${T('sk_adren')}${v.adrenaline && v.adrenaline.n ? ' ×' + v.adrenaline.n : ''}`, four: fourKey() === 'swap' ? T('sk_swap') : T('sk_pulse') };
    const lit = { pads: defib && !v.pads, analyse: v.pads && checkDue(), adren: !!(v.adrenaline && v.adrenaline.due), four: fourKey() === 'pulse' ? !!v.rosc : false };
    const off = { pads: !defib || v.pads, analyse: !v.pads, adren: !(v.adrenaline && v.adrenaline.enabled), four: fourKey() === 'swap' ? !v.partner : false };
    root.querySelectorAll('#cpSl span').forEach(s => { const k = s.dataset.sk; s.textContent = labels[k]; s.className = lit[k] ? 'lit' : (off[k] ? 'off' : ''); });
    root.querySelectorAll('.cp-soft').forEach(b => { const k = b.dataset.sk; b.classList.toggle('lit', !!lit[k]); b.classList.toggle('off', !!off[k]); });
    padsTray(defib && !v.pads && st.padsOpen);
  }
  const fourKey = () => (v_().partner ? 'swap' : 'pulse');
  function checkDue() { const v = v_(); return v.state === 'arrest' && cycleElapsed() >= (v.cycleLength || st.cfg.cycleLength) - (st.cfg.checkGrace || 20); }

  function renderLive() {
    const v = v_();
    $('#cpCode').textContent = NZA.fmt.time(codeTime());
    const comp = iAmComp();
    const rate = comp ? st.rate : (v.rate || 0);
    const rmin = st.cfg.rateMin, rmax = st.cfg.rateMax;
    $('#cpRate').textContent = rate ? String(Math.round(rate)) : '---';
    const pos = r => clamp((r - 60) / 100, 0, 1) * 100;
    $('#cpRateZone').style.left = `${pos(rmin)}%`; $('#cpRateZone').style.width = `${pos(rmax) - pos(rmin)}%`;
    $('#cpRateMk').style.left = `${pos(rate || 60)}%`;
    $('#cpRateMk').style.opacity = rate ? 1 : 0;
    const chip = $('#cpRateChip');
    if (!rate) { chip.textContent = '—'; chip.className = 'cp-chip'; }
    else if (rate < rmin) { chip.textContent = T('too_slow'); chip.className = 'cp-chip amber'; }
    else if (rate > rmax) { chip.textContent = T('too_fast'); chip.className = 'cp-chip amber'; }
    else { chip.textContent = T('perfect'); chip.className = 'cp-chip teal'; }
    const per = v.perSet || st.cfg.perSet;
    const n = v.continuous ? (v.total || 0) % per : Math.min(per, st.localSet);
    $('#cpCnt').textContent = `${n}/${per}`;
    $('#cpCntBar i').style.width = `${(n / per) * 100}%`;
    const q = comp && st.quality ? st.quality : (v.quality || 0);
    $('#cpQ').textContent = q ? `${Math.round(q)}%` : '--%';
    renderPrompt();
    const pl = phaseLeft();
    const chg = $('#cpChg');
    if (v.phase === 'charging' && pl !== null) { const tot = Math.max(0.1, (st.chargeMs || 2500) / 1000); chg.style.width = `${clamp(1 - pl / tot, 0, 1) * 100}%`; $('#cpCharge .f').style.width = chg.style.width; }
    else if (v.phase === 'charged') { chg.style.width = '100%'; $('#cpCharge .f').style.width = '100%'; }
    else { chg.style.width = '0'; $('#cpCharge .f').style.width = '0'; }
  }

  function renderPrompt() {
    const v = v_();
    const pr = $('#cpPrm');
    let key = '', text = '', cls = '';
    const kc = keyLabel(st.keys.compress);
    const ph = v.phase;
    if (ph === 'analyse') { text = T('p_analyse'); cls = 'red blink'; }
    else if (ph === 'charged') { key = keyLabel(st.keys.shock); text = T('p_charged'); cls = 'red blink'; }
    else if (ph === 'charging') { text = T('p_charging', curEnergy()); cls = 'amber'; }
    else if (ph === 'advised') { key = keyLabel(st.keys.charge); text = T('p_advised'); cls = 'amber'; }
    else if (ph === 'rosc') { key = keyLabel(st.keys.pulse); text = T('p_rosc'); cls = 'teal'; }
    else if (ph === 'breaths') {
      if (iBreathe()) { key = kc; text = T('p_breath', Math.min(2, (2 - (v.breathsLeft || 0)) + 1), 2); cls = 'teal'; }
      else text = T('p_handsoff');
    } else if (st.noShockUntil > now()) { text = T('p_noshock'); }
    else if (checkDue() && v.pads) { key = keyLabel(st.keys.analyse); text = T('p_check'); cls = 'amber'; }
    else if (st.waitBreaths) { text = T('p_waitbreath'); cls = 'amber'; }
    else if (v.continuous && iAmComp()) { key = kc; text = T('p_continuous'); }
    else if (iAmComp()) { key = kc; text = st.easy ? T('p_easy') : T('p_compress'); }
    else text = T('p_partner');
    pr.className = `cp-prm ${cls}`;
    const k = pr.querySelector('kbd'); k.textContent = key; k.style.display = key ? '' : 'none';
    pr.querySelector('.t').textContent = text;
    const ad = v.adrenaline || {};
    const cyc = Math.max(0, (v.cycleLength || st.cfg.cycleLength) - cycleElapsed());
    let side = `${esc(T('cycle'))} ${v.cycleNo || 1} · <b>${NZA.fmt.time(cyc)}</b>`;
    if (ad.enabled !== false && v.state === 'arrest') {
      if (ad.due) side += ` &nbsp;${esc(T('adr'))} <b class="due">${esc(T('due'))}</b>`;
      else if (ad.dueIn !== null && ad.dueIn !== undefined) side += ` &nbsp;${esc(T('adr'))} <b>${NZA.fmt.time(Math.max(0, ad.dueIn - (now() - st.viewAt) / 1000))}</b>`;
    }
    $('#cpPrmSide').innerHTML = side;
  }

  /* ─────────────── team HUD ─────────────── */
  function renderTeam() {
    const v = v_();
    const ad = v.adrenaline || {};
    const kind = v.rosc && v.state !== 'arrest' ? T('t_rosc') : (v.kind === 'resp' && v.state !== 'arrest' ? T('t_resp') : T('t_arrest'));
    const meComp = v.role === 'comp';
    const fat = f => NZA.ui.meterHTML({ value: clamp((f || 0) / 40, 0, 1), tone: (f || 0) > 15 ? 'amber' : '' });
    const causes = (v.causes || []).map(c => `<div class="cp-cause ${esc(c.s)}"><i></i><span class="cn">${esc(T('c_' + c.k))}</span>${c.v ? `<span class="cv">${esc(c.v)}</span>` : ''}</div>`).join('');
    const log = (v.log || []).slice(-6).map(l => `<div class="${esc(l.tone || '')}"><span>${NZA.fmt.time(l.t)}</span><b>${esc(l.text)}</b></div>`).join('');
    $('#cpTeam').className = `cp-team nza-hud rail ${v.state === 'arrest' ? 'red' : ''}`;
    $('#cpTeam').innerHTML = `
      <div class="hd"><span class="nza-label">${esc(kind)}</span><span class="chipx sm ${v.state === 'arrest' ? 'red' : 'teal'}">P1</span></div>
      <div class="who"><span class="nza-h">${esc(v.name || T('npc'))}</span>${v.npc ? '<span class="tag">NPC</span>' : ''}</div>
      <div class="cp-kv">
        <div><div class="l">${esc(T('down'))}</div><div class="v red">${NZA.fmt.time((v.arrestTime || 0) + (now() - st.viewAt) / 1000)}</div></div>
        <div><div class="l">${esc(T('ccf'))}</div><div class="v ${(v.ccf || 0) >= 80 ? 'teal' : (v.ccf || 0) >= 60 ? 'amber' : 'red'}">${Math.round(v.ccf || 0)}%</div></div>
        <div><div class="l">${esc(T('shocks'))}</div><div class="v">${v.shocks || 0}</div></div>
        <div><div class="l">${esc(T('adren'))}</div><div class="v ${ad.due ? 'amber' : ''}">${ad.n || 0}</div></div>
      </div>
      <div class="cp-roles">
        <div class="cp-role ${meComp ? 'me' : ''}"><span class="ri">${icon('heart')}</span><div><div class="rl">${esc(T('role_comp'))}</div><div class="rn">${esc(v.compName || '')}${meComp ? `<em>${esc(T('you'))}</em>` : ''}</div></div>
          <div class="ft"><div class="l">${esc(T('fatigue'))}</div>${fat(v.compFatigue)}</div></div>
        <div class="cp-role ${!meComp ? 'me' : ''}"><span class="ri">${icon('lungs')}</span><div><div class="rl">${esc(T('role_air'))}</div>${v.airName ? `<div class="rn">${esc(v.airName)}${!meComp ? `<em>${esc(T('you'))}</em>` : ''}</div>` : `<div class="rn dim">${esc(T('nobody'))}</div>`}</div><div></div></div>
      </div>
      ${v.solo ? `<div class="cp-join">${icon('user-plus')}<span>${esc(T('join_hint'))}</span></div>` : ''}
      ${st.showCauses && causes ? `<div class="cp-sec"><div class="sh"><span class="nza-label">${esc(T('causes'))}</span><kbd>${esc(keyLabel(st.keys.causes))}</kbd></div><div class="cp-causes">${causes}</div></div>` : ''}
      ${log ? `<div class="cp-sec"><div class="sh"><span class="nza-label">${esc(T('log'))}</span></div><div class="cp-log">${log}</div></div>` : ''}`;
  }

  /* ─────────────── proc panel ─────────────── */
  function stepOf(ph) { return ({ compress: 1, breaths: 2, analyse: 3, advised: 4, charging: 4, charged: 5, rosc: 5 })[ph] || 1; }
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
    const rTone = !rate ? '' : (rate < st.cfg.rateMin || rate > st.cfg.rateMax) ? 'amber' : 'teal';
    const depth = comp ? st.depth : (v.depth ? 3.5 + v.depth * 0.025 : 0);
    const q = comp && st.quality ? st.quality : (v.quality || 0);
    let stats;
    if (comp || v.solo) {
      stats = [
        { id: 'rate', label: T('s_rate'), value: rate ? Math.round(rate) : '--', unit: '/min', tone: rTone },
        { id: 'depth', label: T('s_depth'), value: depth ? depth.toFixed(1) : '--', unit: 'cm', tone: !depth ? '' : depth >= 5 ? 'teal' : 'amber' },
        { id: 'q', label: T('s_quality'), value: q ? Math.round(q) : '--', unit: '%', tone: !q ? '' : q >= 75 ? 'teal' : q >= 50 ? 'amber' : 'red' },
      ];
    } else {
      stats = [
        { id: 'vent', label: T('s_vent'), value: v.ventN ? Math.round(v.vent || 0) : '--', unit: '%' },
        { id: 'br', label: T('s_breaths'), value: v.ventN || 0 },
        { id: 'co', label: T('s_etco2'), value: shownEtco2() ? Math.round(shownEtco2()) : '--', unit: 'mmHg' },
      ];
    }
    const per = v.perSet || st.cfg.perSet;
    const cl = v.cycleLength || st.cfg.cycleLength;
    const ce = cycleElapsed();
    const due = checkDue();
    const wide = (comp && ph !== 'rosc')
      ? { label: T('w_comp'), value: String(v.continuous ? (v.total || 0) % per : Math.min(per, st.localSet)), unit: `/${per}`, meter: { value: (v.continuous ? (v.total || 0) % per : Math.min(per, st.localSet)) / per, segs: true }, caption: due ? T('cap_due') : T('cap_check', NZA.fmt.time(Math.max(0, cl - ce))), captionTone: due ? 'amber' : '' }
      : { label: T('w_cycle', v.cycleNo || 1), value: NZA.fmt.time(Math.max(0, cl - ce)), meter: { value: clamp(ce / cl, 0, 1), tone: due ? 'amber' : '' }, caption: (v.adrenaline && v.adrenaline.due) ? T('cap_adr_due') : (due ? T('cap_due') : ''), captionTone: 'amber' };

    const tools = toolList();
    const tag = st.easy ? T('tag_easy') : T('tag_cycle', v.cycleNo || 1);
    const sig = JSON.stringify([stepOf(ph), title, text, tone, stats, wide, tools, tag]);
    if (!force && sig === st.lastPP) return;
    st.lastPP = sig;
    pp.set({
      step: stepOf(ph), total: 5, tag, title, titleTone: tone, text, stats, wide, tools,
      hints: [{ keys: [keyLabel(st.keys.causes)], label: T('hint_causes') }].concat(v.mode === 'manual' ? [{ keys: [keyLabel(st.keys.energyDown), keyLabel(st.keys.energyUp)], label: T('hint_energy') }] : [], tools.length <= 4 ? [{ keys: [T('hint_rmb')], label: T('hint_orbit') }] : []),
    });
    pp.el.querySelector('.pp-tag').classList.toggle('easy', st.easy);
  }

  function toolList() {
    const v = v_();
    const defib = !!v.defib || !!v.pads;
    const ph = v.phase;
    const ad = v.adrenaline || {};
    const list = [];
    if (!v.pads) list.push({ key: keyLabel(st.keys.pads), act: 'pads', label: T('tool_pads'), state: !defib ? 'locked' : (st.padsOpen ? 'active' : 'need') });
    list.push({ key: keyLabel(st.keys.analyse), act: 'analyse', icon: 'ecg', label: T('tool_analyse'), state: !v.pads || ph === 'breaths' || ph === 'charging' || ph === 'charged' || ph === 'rosc' ? 'locked' : (ph === 'analyse' ? 'active' : (checkDue() ? 'need' : '')) });
    const charging = ph === 'charging' || ph === 'charged';
    list.push({ key: keyLabel(st.keys.charge), act: 'charge', icon: 'bolt', label: charging ? T('tool_disarm') : T('tool_charge'), sub: `${curEnergy()} J`, state: !v.pads ? 'locked' : (charging ? 'active' : (ph === 'advised' ? 'need' : (v.mode !== 'manual' ? 'locked' : ''))) });
    list.push({ key: keyLabel(st.keys.shock), act: 'shock', icon: 'bolt', label: T('tool_shock'), state: ph === 'charged' ? 'need' : 'locked' });
    if (ad.enabled !== false) list.push({ key: keyLabel(st.keys.adrenaline), act: 'adrenaline', icon: 'syringe', label: T('tool_adren'), count: `×${ad.have || 0}`, state: !ad.enabled || !ad.have ? 'locked' : (ad.due ? 'need' : '') });
    if (v.partner) list.push({ key: keyLabel(st.keys.swap), act: 'swap', icon: 'swap', label: T('tool_swap'), state: ph === 'charged' ? 'locked' : ((v.compFatigue || 0) > 15 ? 'need' : '') });
    else if (v.rosc || ph === 'rosc') list.push({ key: keyLabel(st.keys.pulse), act: 'pulse', icon: 'pulse', label: T('tool_pulse'), state: 'need' });
    return list.map(t => ({ key: t.key, label: t.label, sub: t.sub, count: t.count, state: t.state, act: t.act }));
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
    if (!hit) return;
    if (hit !== k) { pp && pp.flash('warn', T('pad_wrong', hit === 'R' ? T('pad_r') : T('pad_l')), 2600); return; }
    placePad(k);
  }
  function dropTarget(x, y) {
    const snap = st.cfg.snap || 70;
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
    const b = st.batch;
    b.n += 1; b.timing += timing; b.depth += depthScore; b.recoil += recoil;
    st.bars.push({ d: depthCm, cls: depthCm < 5 ? 'low' : (recoil < 60 ? 'lean' : 'ok') });
    if (st.bars.length > 48) st.bars.shift();
    st.hits.push({ t, cls });
    if (st.hits.length > 16) st.hits.shift();
    pop(depthCm < 4.6 ? 'shallow' : recoil < 50 ? 'lean' : cls);
    const v = v_();
    if (compressPhase(ph) && !st.waitBreaths) {
      st.localSet += 1;
      const per = v.perSet || c.perSet;
      if (!v.continuous && st.localSet >= per && v.phase === 'compress') { st.waitBreaths = true; st.waitAt = now(); st.auto = false; report(true); }
      if (v.continuous && st.localSet >= per) st.localSet = 0;
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
    e.className = `cp-pop ${cls === 'shallow' || cls === 'lean' ? 'early' : cls}`;
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
    if (hold < st.cfg.tooShort * k) pp && pp.flash('warn', T('f_breath_short'), 1800);
    else if (hold > st.cfg.tooLong * k) pp && pp.flash('bad', T('f_breath_long'), 1800);
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
        compression(0, 0.15, t, ph);
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
    drawLane(t);
    drawFb();
    drawTube(t);
    if (!st._liveAt || t - st._liveAt > 120) { st._liveAt = t; renderLive(); }
    if (!st._ppAt || t - st._ppAt > 400) { st._ppAt = t; renderPP(false); }
    if (!st._teamAt || t - st._teamAt > 1000) { st._teamAt = t; renderTeam(); }
  }

  function laneOverlay(t) {
    const v = v_();
    const ov = $('#cpLaneOv');
    if (!ov) return;
    const ph = v.phase;
    const set = (cls, ic, text, p) => { ov.className = `ov on ${cls}`; ov.querySelector('.ic').innerHTML = icon(ic); ov.querySelector('.tx').textContent = text; ov.querySelector('.bar').style.display = p === null ? 'none' : ''; if (p !== null) ov.querySelector('.bar i').style.width = `${clamp(p, 0, 1) * 100}%`; };
    const pl = phaseLeft();
    if (ph === 'analyse') return set('red', 'hand', T('l_analyse'), pl === null ? 0 : 1 - pl / (st.cfg.analyseTime || 4)), true;
    if (ph === 'charged') return set('red', 'bolt', T('l_charged'), 1), true;
    if (ph === 'breaths' && !iBreathe()) return set('amber', 'lungs', T('l_handsoff'), null), true;
    if (ph === 'rosc') return set('teal', 'heart', T('pp_rosc'), null), true;
    if (!iAmComp() && ph !== 'breaths') {
      if (ph === 'charging') return set('amber', 'bolt', `${T('l_charging')} ${curEnergy()} J`, pl === null ? 0 : 1 - pl / Math.max(0.1, (st.chargeMs || 2500) / 1000)), true;
      const pq = v.quality ? `${Math.round(v.quality)}%` : '--';
      return set('', 'heart', T('l_partner', v.compName || '', v.rate ? Math.round(v.rate) : '--', pq), null), true;
    }
    ov.className = 'ov';
    return false;
  }

  function drawLane(t) {
    const cv = $('#cpLane');
    if (!cv) return;
    const covered = laneOverlay(t);
    const { w, h, scale } = NZA.fitCanvas(cv);
    const ctx = cv.getContext('2d');
    ctx.clearRect(0, 0, w, h);
    if (covered) return;
    const v = v_();
    const hitX = w * 0.12;
    const s = scale;
    // breath mode: chest-rise meter
    if (v.phase === 'breaths' && iBreathe()) {
      const tgt = breathTarget();
      const k = v.bvm ? 1 : st.cfg.mouthSlower;
      const span = st.cfg.tooLong * k * 1.15;
      const x0 = 16 * s, x1 = w - 16 * s, y = h * 0.7, bh = 12 * s;
      const X = sec => x0 + (x1 - x0) * clamp(sec / span, 0, 1);
      ctx.fillStyle = 'rgba(255,255,255,.08)'; roundRect(ctx, x0, y - bh / 2, x1 - x0, bh, bh / 2); ctx.fill();
      ctx.fillStyle = 'rgba(8,175,162,.25)'; ctx.fillRect(X(st.cfg.tooShort * k), y - bh / 2 - 3 * s, X(st.cfg.tooLong * k) - X(st.cfg.tooShort * k), bh + 6 * s);
      ctx.fillStyle = '#fff'; ctx.fillRect(X(tgt) - 1 * s, y - bh / 2 - 6 * s, 2 * s, bh + 12 * s);
      const held = st.breath ? (st.breath.frozen || (t - st.breath.at) / 1000) : 0;
      if (held > 0) {
        const over = held > st.cfg.tooLong * k;
        ctx.fillStyle = over ? '#e5484d' : (held >= st.cfg.tooShort * k ? '#0fd4c4' : '#f2f4f5');
        roundRect(ctx, x0, y - bh / 2, X(held) - x0, bh, bh / 2); ctx.fill();
      }
      ctx.font = `700 ${10 * s}px Lexend, sans-serif`; ctx.fillStyle = 'rgba(255,255,255,.55)';
      ctx.fillText(`${T('l_breath')} · ${2 - (v.breathsLeft || 0) + (st.breath ? 1 : 0)}/2`, x0, 16 * s);
      // chest profile rising with the breath (right of the label)
      const rise = clamp(held / tgt, 0, 1.3);
      const cx = w - 60 * s, cy = 21 * s;
      ctx.strokeStyle = 'rgba(255,255,255,.18)'; ctx.lineWidth = 1.5 * s; ctx.beginPath(); ctx.moveTo(cx - 44 * s, cy); ctx.lineTo(cx + 44 * s, cy); ctx.stroke();
      ctx.strokeStyle = held > st.cfg.tooLong * k ? '#ff7478' : '#0fd4c4'; ctx.lineWidth = 2 * s; ctx.beginPath();
      ctx.moveTo(cx - 44 * s, cy); ctx.quadraticCurveTo(cx, cy - 4 * s - rise * 11 * s, cx + 44 * s, cy); ctx.stroke();
      ctx.font = `600 ${9 * s}px Lexend, sans-serif`; ctx.fillStyle = 'rgba(255,255,255,.4)';
      ctx.fillText(held ? `${held.toFixed(1)} s` : `${tgt.toFixed(1)} s`, cx - 120 * s, cy + 3 * s);
      return;
    }
    // compression lane
    const pxPerMs = (w - hitX) / 2400;
    // hit zone
    const pz = st.cfg.perfect * 1000 * pxPerMs, gz = st.cfg.good * 1000 * pxPerMs;
    ctx.fillStyle = 'rgba(8,175,162,.10)'; ctx.fillRect(hitX - gz, 0, gz * 2, h);
    ctx.fillStyle = 'rgba(8,175,162,.22)'; ctx.fillRect(hitX - pz, 0, pz * 2, h);
    ctx.fillStyle = 'rgba(15,212,196,.9)'; ctx.fillRect(hitX - 1 * s, 0, 2 * s, h);
    // beats
    const active = compressPhase(v.phase) && !st.waitBreaths;
    const per = st.period * 1000;
    const first = Math.floor((t - 600 - st.beat0) / per);
    for (let i = first; i < first + 8; i++) {
      const tb = st.beat0 + i * per;
      const x = hitX + (tb - t) * pxPerMs;
      if (x < -20 || x > w + 20) continue;
      const near = Math.abs(tb - t) < 90;
      const r = (near ? 9 : 7) * s;
      ctx.beginPath(); ctx.arc(x, h / 2, r, 0, Math.PI * 2);
      ctx.fillStyle = !active ? 'rgba(255,255,255,.12)' : (tb < t ? 'rgba(255,255,255,.18)' : (near ? '#ffffff' : 'rgba(255,255,255,.75)'));
      ctx.fill();
      if (active && tb >= t) { ctx.strokeStyle = 'rgba(8,175,162,.6)'; ctx.lineWidth = 1.5 * s; ctx.stroke(); }
    }
    // your presses
    const col = { perfect: '#0fd4c4', good: '#ffffff', early: '#f3c35a', late: '#f3c35a', bad: '#ff7478' };
    st.hits.forEach(hh => {
      const age = t - hh.t;
      if (age > 2400) return;
      const x = hitX - age * pxPerMs * 0.35;
      ctx.globalAlpha = clamp(1 - age / 2400, 0, 1);
      ctx.fillStyle = col[hh.cls] || '#fff';
      ctx.fillRect(x - 2 * s, h * 0.2, 4 * s, h * 0.6);
      ctx.globalAlpha = 1;
    });
    if (st.press) { ctx.fillStyle = '#ffffff'; ctx.beginPath(); ctx.arc(hitX, h / 2, 12 * s, 0, Math.PI * 2); ctx.globalAlpha = 0.25; ctx.fill(); ctx.globalAlpha = 1; }
    if (st.easy && iAmComp()) {
      ctx.font = `700 ${10 * s}px Lexend, sans-serif`; ctx.fillStyle = st.auto ? '#0fd4c4' : 'rgba(255,255,255,.45)';
      ctx.fillText(st.auto ? 'AUTO ●' : 'AUTO ○', w - 64 * s, 15 * s);
    }
  }
  function roundRect(ctx, x, y, w, h, r) { w = Math.max(0, w); r = Math.min(r, w / 2, h / 2); ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r); ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath(); }

  function drawFb() {
    const cv = $('#cpFb');
    if (!cv) return;
    const { w, h, scale } = NZA.fitCanvas(cv);
    const sig = `${st.bars.length}:${w}`;
    if (cv._sig === sig) return;
    cv._sig = sig;
    const ctx = cv.getContext('2d');
    ctx.fillStyle = '#020303'; ctx.fillRect(0, 0, w, h);
    const top = 12 * scale, bot = h - 4 * scale;
    const Y = cm => top + (bot - top) * clamp(cm / 7, 0, 1);
    ctx.fillStyle = 'rgba(8,175,162,.16)'; ctx.fillRect(0, Y(5), w, Y(6) - Y(5));
    ctx.strokeStyle = 'rgba(15,212,196,.35)'; ctx.lineWidth = 1; ctx.setLineDash([3 * scale, 3 * scale]);
    [5, 6].forEach(cm => { ctx.beginPath(); ctx.moveTo(0, Y(cm)); ctx.lineTo(w, Y(cm)); ctx.stroke(); });
    ctx.setLineDash([]);
    const bw = 7 * scale, gap = 3 * scale;
    const max = Math.floor((w - 8 * scale) / (bw + gap));
    const list = st.bars.slice(-max);
    list.forEach((b, i) => {
      const x = 6 * scale + i * (bw + gap);
      ctx.fillStyle = b.cls === 'ok' ? '#0fd4c4' : (b.cls === 'low' ? '#ffb224' : '#ff7a7e');
      ctx.fillRect(x, top, bw, Y(b.d) - top);
    });
  }

  function drawTube(t) {
    const tube = $('#cpTube');
    if (!tube) return;
    let cm = 0, cls = '';
    if (st.press) cm = 6.25 * (1 - Math.exp(-((t - st.press.at) / 1000) / 0.055));
    else if (st.lastCompAt && t - st.lastCompAt < 260) cm = st.depth * (1 - (t - st.lastCompAt) / 260);
    cls = cm >= 5 ? 'ok' : (cm > 0.3 ? 'low' : '');
    tube.style.height = `${clamp(cm / 7, 0, 1) * 100}%`;
    tube.className = cls;
    if (!st._tubeAt || t - st._tubeAt > 150) {
      st._tubeAt = t;
      const dv = $('#cpDepthV'), ds = $('#cpDepthS');
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
    b.className = `cp-banner nza-hud solid on ${tone}`;
    b.querySelector('.bi').innerHTML = icon(ic);
    b.querySelector('b').textContent = title;
    b.querySelector('span').textContent = sub || '';
    clearTimeout(bannerTimer);
    if (ms) bannerTimer = setTimeout(() => hideBanner(id), ms);
  }
  function hideBanner(id) { if (id && id !== bannerId) return; const b = $('#cpBanner'); if (b) b.className = 'cp-banner nza-hud solid'; bannerId = ''; }
  let voiceTimer = 0;
  function voice(text, ms = 4200) {
    const vb = $('#cpVoice');
    if (!vb) return;
    clearTimeout(voiceTimer);
    if (!text) { vb.classList.remove('on'); return; }
    vb.querySelector('.who').textContent = T('v_who');
    vb.querySelector('.tx').textContent = text;
    vb.classList.remove('on'); void vb.offsetWidth; vb.classList.add('on');
    voiceTimer = setTimeout(() => vb.classList.remove('on'), ms);
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
        st.beat0 = now() + 300; st.lastBeatIdx = -1; st.localSet = 0; st.setPhase = '';
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
    const m = (val) => NZA.ui.meterHTML({ value: clamp((val || 0) / 100, 0, 1), tone: (val || 0) >= 75 ? '' : (val || 0) >= 50 ? 'amber' : 'red' });
    const tiles = [
      [T('d_duration'), NZA.fmt.time(sum.duration || 0), ''],
      [T('d_comp'), sum.compressions || 0, ''],
      [T('d_shocks'), sum.shocks || 0, ''],
      [T('d_adr'), sum.adrenaline || 0, ''],
    ];
    const qtiles = has ? [[T('d_quality'), parts.quality], [T('d_ccf'), parts.ccf], [T('d_vent'), parts.vent], [T('d_protocol'), parts.protocol]] : [];
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
    box.innerHTML = `
      <div class="hd">${grade ? `<div class="grade g-${esc(grade)}">${esc(grade)}</div>` : `<div class="grade g-C">${icon('heart')}</div>`}
        <div><b class="${sum.rosc ? 'teal' : (reason === 'death' ? 'red' : '')}">${esc(T(titleKey))}</b><p>${esc(T('d_sub', v_().name || sum.name || T('npc'), T('r_' + reason)))}</p></div></div>
      <div class="gridx">${tiles.map(([l, val]) => `<div><div class="l">${esc(l)}</div><div class="v">${esc(val)}</div></div>`).join('')}</div>
      ${qtiles.length ? `<div class="gridx">${qtiles.map(([l, val]) => `<div><div class="l">${esc(l)}</div><div class="v">${Math.round(val || 0)}<small>%</small></div>${m(val)}</div>`).join('')}</div>` : ''}
      ${fb.length ? `<ul>${fb.map(([c, txt]) => `<li class="${c}">${esc(txt)}</li>`).join('')}</ul>` : ''}
      <div class="ft">${sum.rhythmStart ? `<span class="rh">${esc(T('d_rhythm', rhLabel(sum.rhythmStart), sum.rosc ? T('rh_rosc') : rhLabel(sum.rhythmEnd)))}</span>` : ''}<span class="sp"></span><button class="btn-teal" id="cpDone"><kbd style="background:rgba(0,0,0,.18);border-color:rgba(0,0,0,.25);color:var(--on-teal)">Enter</kbd>${esc(T('d_done'))}</button></div>`;
    box.classList.add('on');
    box.querySelector('#cpDone').onclick = () => NZA.close(APP);
    if (pp) pp.el.style.display = 'none';
    dev.classList.add('cp-dim');
    if (grade && has) NZA.toast({ title: T(titleKey), message: `${sum.compressions || 0} · ${NZA.fmt.time(sum.duration || 0)}`, grade, type: sum.rosc ? 'success' : 'info' });
    if (snd()) (sum.rosc ? NZA.audio.success() : NZA.audio.fail());
  }

  /* ═══════════════════════════ PREVIEW (browser only) ═══════════════════════════ */
  const DEMO_CAUSES = [{ k: 'hypovolemia', s: 'suspect', v: '~1.9 L' }, { k: 'hypoxia', s: 'treating', v: '72%' }, { k: 'hypothermia', s: 'ok', v: '35.9°' }, { k: 'tension', s: 'unknown' }, { k: 'tamponade', s: 'unknown' }, { k: 'toxins', s: 'unknown' }];
  const DEMO_LOG = [{ t: 0, text: 'CPR started by Ava Moreno', tone: 'teal' }, { t: 41, text: 'Pads on (Ava Moreno)' }, { t: 47, text: 'Analysis: VF, shock advised', tone: 'amber' }, { t: 52, text: 'Shock 1 at 200 J', tone: 'amber' }, { t: 64, text: 'Liam Carter joined the code', tone: 'teal' }];
  function demoView(o = {}) {
    return Object.assign({
      id: 'code_demo', pid: 'n:4512', name: 'Michael Garcia', sex: 'm', npc: false, role: 'comp', solo: false, compName: 'Ava Moreno', airName: 'Liam Carter', partner: 'Liam Carter',
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
    if (name === 'compress' || name === 'air' || name === 'easy') {
      const t0 = now();
      [0, 1, 2, 3, 4, 5, 6, 7].forEach(i => { st.bars.push({ d: 5.2 + (i % 3) * 0.3, cls: 'ok' }); });
      st.bars.push({ d: 4.4, cls: 'low' }); st.bars.push({ d: 5.6, cls: 'ok' }); st.bars.push({ d: 5.9, cls: 'lean' });
      for (let i = 0; i < 10; i++) st.bars.push({ d: 5.3 + ((i * 7) % 5) * 0.15, cls: 'ok' });
      st.rate = 112; st.depth = 5.6; st.quality = 88; st.localSet = v.set; st.lastCompAt = t0;
      st.hits = [{ t: t0 - 520, cls: 'good' }, { t: t0 - 1050, cls: 'perfect' }, { t: t0 - 1600, cls: 'perfect' }, { t: t0 - 2150, cls: 'early' }];
      if (name === 'easy') st.auto = true;
      setTimeout(() => pop('perfect'), 900);
    }
    if (name === 'pads') { st.padsOpen = true; padsTray(true); st.pads.R = true; padsTray(true); }
    if (name === 'analyse') { banner('analyse', '', 'ecg', T('b_analyse'), T('b_analyse_s')); voice(T('v_analyse'), 60000); }
    if (name === 'charged') { banner('clear', 'red pulse', 'alert', T('b_clear'), T('b_clear_s')); voice(T('v_charged'), 60000); }
    if (name === 'rosc') { banner('rosc', 'teal', 'heart', T('b_rosc'), T('b_rosc_s'), 60000); voice(T('v_rosc'), 60000); }
    if (name === 'breaths') { st.breath = { at: now(), frozen: 0.86 }; }
    if (name === 'debrief') ended({ reason: 'rosc', rosc: true, duration: 412, compressions: 618, cycles: 6, shocks: 2, adrenaline: 1, score: 84, grade: 'A', parts: { quality: 86, ccf: 78, vent: 71, protocol: 90 }, rhythmStart: 'vf', rhythmEnd: 'stach', name: 'Michael Garcia' });
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
