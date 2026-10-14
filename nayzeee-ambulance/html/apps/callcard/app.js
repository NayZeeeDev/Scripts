/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · callcard
   Urgent dispatch card (top right, HUD design) + "your call" strip with the status chain.
   Opened WITHOUT focus while on duty; respond / dismiss are game keybinds handled in Lua
   (client/modules/dispatch.lua). Also defines window.NZD, small helpers shared by the
   pager, dispatch and radial apps (loaded after this file).

   Lua → JS actions
     open   { locale, keys: { respond, dismiss }, timeout, voiceVolume, chain }
     alert  { call, queue, police, sound, voice }      show a call card (replaces the current one)
     alertUpdate { call }                              same call, new data (units, patients…)
     alertResponded { id }                             flip to "Responding"
     alertHide {}                                      no card
     queue  { n }                                      calls waiting behind the card
     active { call | false, stage }                    "your call" strip
     live   { alert: { id, dist, dir, rel, eta }, active: {…} }   ~5 Hz while visible
   JS → Lua: none (no focus; the router never posts for this app)
   ═══════════════════════════════════════════════════════════ */
(() => {
  /* ─────────── shared dispatch helpers (window.NZD) ─────────── */
  const STAGES = ['DSP', 'ENR', 'SCN', 'CARE', 'TRN', 'HSP'];
  const TYPE_ICON = {
    gunshot: 'crosshair', shrapnel: 'burst', stab: 'knife', laceration: 'cut', abrasion: 'scrape', contusion: 'bruise',
    fracture: 'bone', burn: 'flame', internal: 'drop', arrest: 'ecg', overdose: 'pill', mva: 'car', crash: 'car',
    fall: 'arrow-down', drowning: 'drop', deceased: 'skull', dead: 'skull', unconscious: 'brain', call: 'phone',
    fire: 'flame', assault: 'hand', medical: 'medkit', unknown: 'alert',
  };
  const NZD = window.NZD = {
    STAGES,
    stageIdx: s => Math.max(0, STAGES.indexOf(s)),
    typeIcon: t => TYPE_ICON[String(t || '').toLowerCase()] || 'medkit',
    prio: p => Math.min(3, Math.max(1, Number(p) || 2)),
    tr(loc) { return (k, fb) => (loc && loc[k] != null ? loc[k] : fb); },
    fmt(str, ...a) { let i = 0; return String(str ?? '').replace(/%[sd]/g, () => (a[i++] ?? '')); },
    dist(m) {
      if (m == null || isNaN(m)) return { v: '--', u: 'm' };
      return m >= 1000 ? { v: (m / 1000).toFixed(m >= 10000 ? 0 : 1), u: 'km' } : { v: String(Math.max(0, Math.round(m / 5) * 5)), u: 'm' };
    },
    eta(s) { if (s == null || isNaN(s)) return '--:--'; s = Math.max(0, Math.round(s)); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; },
    age(s) { return NZA.fmt.time(s); },
    where(c) { return [c.zone, c.street].filter(Boolean).join(' · '); },
    unitStatusTone(s) { return ({ '10-8': 'teal', '10-7': 'off', ENR: 'amber', SCN: 'red', CARE: 'red', TRN: 'white', HSP: 'teal' })[s] || 'off'; },
    // 6-stage chain HTML; cls prefix lets every app style it
    chain(cur, tr, cls = 'chain') {
      const ci = NZD.stageIdx(cur);
      return `<div class="${cls}">${STAGES.map((s, i) => `<span class="${i < ci ? 'done' : i === ci ? 'cur' : ''}">${NZA.esc(tr ? tr('st_' + s.toLowerCase() + '_s', s) : s)}</span>`).join('<i>›</i>')}</div>`;
    },
    // dispatch alert tone (P1 three bursts, P2 two, P3 one)
    tone(p) {
      const n = p === 1 ? 3 : p === 2 ? 2 : 1;
      for (let i = 0; i < n; i++) {
        NZA.audio.tone(p === 1 ? 1180 : 960, 120, { vol: 0.09, type: 'square', at: i * 0.42 });
        NZA.audio.tone(p === 1 ? 880 : 720, 150, { vol: 0.09, type: 'square', at: i * 0.42 + 0.14 });
      }
    },
  };

  /* ─────────── app ─────────── */
  const esc = NZA.esc, icon = NZA.icon;
  let tr = NZD.tr({});
  let cfg = { keys: { respond: 'E', dismiss: 'X' }, timeout: 30, voiceVolume: 0.85 };
  let root, cardHost, moreEl, activeEl;
  let card = null;              // { call, police, at (ms), age0 }
  let act = null;               // { call, stage, at, age0 }
  let audioEl = null, timer = 0;

  const prioWord = (p, police) => police ? tr('cc_police', 'POLICE NOTICE') : tr('p' + p + '_word', ['', 'CRITICAL', 'URGENT', 'ROUTINE'][p]);

  function arrowSvg() {
    return '<svg class="cc-arrow" viewBox="0 0 24 24"><path d="M12 3l6.5 15.5L12 15l-6.5 3.5z"/></svg>';
  }

  function renderCard() {
    if (!card) { cardHost.innerHTML = ''; cardHost.className = 'cc-cardhost'; moreEl.classList.remove('on'); return; }
    const c = card.call, p = NZD.prio(c.priority);
    const units = (c.units || []).length, pts = (c.patients || []).length;
    const tags = (c.tags || []).slice(0, 3);
    const voice = card.voice ? `<div class="cc-voice ${card.playing ? 'play' : ''}"><span class="vic">${icon('volume')}</span><span class="wave">${Array.from({ length: 28 }, (_, i) => `<i style="animation-delay:${(i * 73) % 600}ms"></i>`).join('')}</span><span class="vl">${esc(tr('cc_voice', 'Voice call'))}</span></div>` : '';
    const caller = c.caller || c.message ? `<div class="cc-caller">${icon('phone')}<div><span class="lb">${esc(tr('cc_caller', 'Caller'))}</span> <b>${esc(c.caller || tr('cc_unknown_caller', 'Unknown'))}</b>${c.phone ? `<span class="ph">${esc(c.phone)}</span>` : ''}${c.message ? `<q>${esc(c.message)}</q>` : ''}</div></div>` : '';
    const chips = [
      pts ? `<span class="chipx sm">${icon('person')}${esc(NZD.fmt(tr(pts === 1 ? 'cc_patient' : 'cc_patients', pts === 1 ? '%d patient' : '%d patients'), pts))}</span>` : '',
      ...tags.map(tg => `<span class="chipx sm">${icon(NZD.typeIcon(tg))}${esc(tr('type_' + tg, tg))}</span>`),
      units ? `<span class="chipx sm teal">${icon('ambulance')}${esc(NZD.fmt(tr('cc_units_on', '%d on it'), units))}</span>` : '',
      c.npc ? `<span class="chipx sm">${esc(tr('cc_npc', 'NPC'))}</span>` : '',
    ].join('');
    cardHost.className = `cc-cardhost on`;
    cardHost.innerHTML = `
      <div class="cc-card nza-hud solid p${p} ${card.police ? 'police' : ''} ${card.ok ? 'ok' : ''}">
        <div class="cc-head">
          <span class="cc-prio"><i></i>${esc(prioWord(p, card.police))}</span>
          <span class="cc-code">${esc(c.code || '10-52')}</span>
          <span class="cc-id">${esc(c.id || '')}</span>
          <span class="cc-time" data-age>${NZD.age(c.age || 0)}</span>
        </div>
        <div class="cc-main">
          <div class="cc-ico">${icon(NZD.typeIcon(c.type))}</div>
          <div class="cc-tt"><h3>${esc(c.title || tr('call_default', 'Medical emergency'))}</h3>
            <p class="cc-loc">${c.zone ? `<b>${esc(c.zone)}</b>` : ''}${c.zone && c.street ? '<i>·</i>' : ''}${esc(c.street || (c.zone ? '' : tr('unknown_location', 'Unknown location')))}</p></div>
        </div>
        ${caller}${voice}
        ${chips ? `<div class="cc-tags">${chips}</div>` : ''}
        <div class="cc-foot">
          <div class="cc-dist"><b data-dist>--</b><span data-du>m</span></div>
          <div class="cc-dir"><span class="cc-rose">${arrowSvg()}</span><b data-dir>--</b></div>
          <div class="cc-eta"><span>${esc(tr('cc_eta', 'ETA'))}</span><b data-eta>--:--</b></div>
          <span class="sp"></span>
          <button class="cc-x" title="${esc(tr('cc_dismiss', 'Dismiss'))}"><kbd>${esc(cfg.keys.dismiss)}</kbd></button>
          <button class="cc-go"><span class="lbl">${esc(card.ok ? tr('cc_responding', 'RESPONDING') : card.police ? tr('cc_gps', 'SET GPS') : tr('cc_respond', 'RESPOND'))}</span>${card.ok ? icon('check') : `<kbd>${esc(cfg.keys.respond)}</kbd>`}</button>
        </div>
        <i class="cc-bar"></i>
      </div>`;
    const bar = cardHost.querySelector('.cc-bar');
    if (!card.ok) {
      const left = Math.max(0.5, cfg.timeout - (performance.now() - card.at) / 1000);
      bar.animate([{ transform: `scaleX(${left / cfg.timeout})` }, { transform: 'scaleX(0)' }], { duration: left * 1000, easing: 'linear', fill: 'forwards' });
    } else bar.style.transform = 'scaleX(0)';
    renderMore();
    if (card.live) applyLive(cardHost, card.live);
  }

  function renderMore() {
    const n = card ? card.queue || 0 : 0;
    moreEl.classList.toggle('on', n > 0);
    cardHost.classList.toggle('stack', n > 0);
    cardHost.classList.toggle('stack2', n > 1);
    moreEl.innerHTML = n > 0 ? `<span>${esc(NZD.fmt(tr(n === 1 ? 'cc_more_1' : 'cc_more', n === 1 ? '+1 more call' : '+%d more calls'), n))}</span><span class="k"><kbd>${esc(cfg.keys.dismiss)}</kbd>${esc(tr('cc_next', 'next'))}</span>` : '';
  }

  function renderActive() {
    if (!act) { activeEl.classList.remove('on'); activeEl.innerHTML = ''; return; }
    const c = act.call, p = NZD.prio(c.priority);
    activeEl.className = `cc-active nza-hud solid on p${p}`;
    activeEl.innerHTML = `
      <div class="ca-top">
        <span class="ca-tag">${esc(tr('cc_your_call', 'Your call'))}</span>
        <span class="ca-t"><b>${esc(c.code || '')}</b> ${esc(c.title || '')}</span>
        <span class="sp"></span>
        <span class="ca-d"><span class="cc-rose sm">${arrowSvg()}</span><b data-dist>--</b><span data-du>m</span></span>
      </div>
      <div class="ca-sub">${esc(NZD.where(c) || tr('unknown_location', 'Unknown location'))}<span class="ca-id">${esc(c.id)}</span></div>
      ${NZD.chain(act.stage || c.status, tr, 'ca-chain')}`;
    if (act.live) applyLive(activeEl, act.live);
  }

  function applyLive(host, l) {
    if (!l) return;
    const d = NZD.dist(l.dist);
    const q = s => host.querySelector(s);
    if (q('[data-dist]')) q('[data-dist]').textContent = d.v;
    if (q('[data-du]')) q('[data-du]').textContent = d.u;
    if (q('[data-dir]')) q('[data-dir]').textContent = l.dir || '--';
    if (q('[data-eta]')) q('[data-eta]').textContent = NZD.eta(l.eta);
    const a = q('.cc-arrow');
    if (a && l.rel != null) a.style.transform = `rotate(${l.rel}deg)`;
    const card = host.querySelector('.cc-card');
    if (card) card.classList.toggle('near', l.dist != null && l.dist < 60);
  }

  function tickAges() {
    const now = performance.now();
    if (card) {
      const el = cardHost.querySelector('[data-age]');
      if (el) el.textContent = NZD.age((card.call.age || 0) + (now - card.ageAt) / 1000);
    }
  }

  function stopVoice() {
    if (audioEl) { try { audioEl.pause(); } catch (e) { /* already stopped */ } audioEl = null; }
    if (card) card.playing = false;
    const v = cardHost && cardHost.querySelector('.cc-voice');
    if (v) v.classList.remove('play');
  }

  function playVoice(src) {
    stopVoice();
    if (!src || !/^audio\/[\w\-/.]+\.(ogg|mp3|wav)$/.test(src) || src.includes('..')) return;
    try {
      audioEl = new Audio(src);
      audioEl.volume = Math.max(0, Math.min(1, cfg.voiceVolume));
      audioEl.addEventListener('ended', stopVoice);
      audioEl.addEventListener('error', stopVoice);
      const p = audioEl.play();
      if (p && p.catch) p.catch(stopVoice);
      card.playing = true;
      const v = cardHost.querySelector('.cc-voice');
      if (v) v.classList.add('play');
    } catch (e) { stopVoice(); }
  }

  function showAlert(d) {
    if (!d || !d.call) return;
    stopVoice();
    card = { call: d.call, police: !!d.police, queue: d.queue || 0, at: performance.now(), ageAt: performance.now(), voice: d.voice || null, ok: false };
    renderCard();
    const el = cardHost.querySelector('.cc-card');
    if (el) { el.classList.remove('in'); void el.offsetWidth; el.classList.add('in'); }
    if (d.sound !== false && NZA.cfg.sounds !== false) NZD.tone(NZD.prio(d.call.priority));
    if (d.voice) setTimeout(() => { if (card && card.call.id === d.call.id) playVoice(d.voice); }, d.sound !== false ? 900 : 0);
  }

  NZA.app('callcard', {
    escClose: false,
    init(el) {
      root = NZA.el('div', 'cc-root');
      activeEl = NZA.el('div', 'cc-active nza-hud solid');
      cardHost = NZA.el('div', 'cc-cardhost');
      moreEl = NZA.el('div', 'cc-more');
      root.append(activeEl, cardHost, moreEl);
      el.appendChild(root);
    },
    open(d) {
      if (d.locale) tr = NZD.tr(d.locale);
      if (d.keys) cfg.keys = Object.assign(cfg.keys, d.keys);
      if (d.timeout) cfg.timeout = d.timeout;
      if (d.voiceVolume != null) cfg.voiceVolume = d.voiceVolume;
      clearInterval(timer);
      timer = setInterval(tickAges, 1000);
      renderCard(); renderActive();
    },
    close() { clearInterval(timer); stopVoice(); card = null; act = null; renderCard(); renderActive(); },
    msg: {
      alert: showAlert,
      alertUpdate(d) {
        if (!card || !d.call || d.call.id !== card.call.id) return;
        card.call = d.call;
        card.ageAt = performance.now();
        const playing = card.playing;
        renderCard();
        if (playing) { const v = cardHost.querySelector('.cc-voice'); if (v) v.classList.add('play'); }
      },
      alertResponded(d) {
        if (!card || (d && d.id && d.id !== card.call.id)) return;
        card.ok = true; stopVoice(); renderCard();
        NZA.audio.success();
      },
      alertHide() { stopVoice(); card = null; renderCard(); },
      queue(d) { if (card) { card.queue = d.n || 0; renderMore(); } },
      active(d) {
        if (!d || !d.call) { act = null; renderActive(); return; }
        const prev = act && act.call.id === d.call.id ? act.live : null;
        act = { call: d.call, stage: d.stage, live: prev };
        renderActive();
      },
      live(d) {
        if (d.alert && card && d.alert.id === card.call.id) { card.live = d.alert; applyLive(cardHost, d.alert); }
        if (d.active && act && d.active.id === act.call.id) { act.live = d.active; applyLive(activeEl, d.active); }
      },
    },
    preview() {
      NZA.demo('callcard', { keys: { respond: 'E', dismiss: 'X' }, timeout: 30 });
      showAlert({
        call: {
          id: 'C-0412', code: '10-52', priority: 1, title: 'Gunshot Wound', type: 'gunshot', zone: 'Vespucci Canals',
          street: 'Imagination Ct / Prosperity St', caller: 'Michael Garcia', phone: '555-0142',
          message: "My friend's been shot in the chest, he's bleeding a lot. Please hurry!", age: 9,
          patients: [{ pid: 'n:1', tri: 1 }], tags: ['gunshot', 'fracture'], units: [], npc: true,
        },
        queue: 2, sound: false, voice: null,
      });
      card.voice = 'audio/calls/demo.ogg'; card.playing = true; renderCard();
      NZA.apps.callcard.msg.active({
        call: { id: 'C-0409', code: '10-50', priority: 2, title: 'Vehicle Collision', type: 'mva', zone: 'Pillbox Hill', street: 'Palomino Ave', status: 'SCN' },
        stage: 'ENR',
      });
      let rel = 210;
      const step = () => {
        rel = (rel + 3) % 360;
        NZA.apps.callcard.msg.live({ alert: { id: 'C-0412', dist: 312, dir: 'SW', rel, eta: 19 }, active: { id: 'C-0409', dist: 1460, dir: 'NE', rel: (rel + 140) % 360, eta: 74 } });
      };
      step(); setInterval(step, 200);
    },
  });
})();
