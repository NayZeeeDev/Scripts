/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · callcard
   Incoming-call strip (top right, left of the toast column): a range scope on the left
   (answer-window ring, blip pointing at the call relative to the camera, distance in the
   centre), the call itself with an instrument list in the middle and a vertical key rail
   on the right (E take · X pass). Above it, while you are on a call, the "on call" strip
   with the 6-stage ring. Opened WITHOUT focus while on duty; take / pass are game
   keybinds handled in Lua (client/modules/dispatch.lua). Also defines window.NZD, small
   helpers shared by the pager, dispatch and radial apps (loaded after this file).

   Lua → JS actions
     open   { locale, keys: { respond, dismiss }, timeout, voiceVolume, chain }
     alert  { call, queue, police, sound, voice }      show a call (replaces the current one)
     alertUpdate { call }                              same call, new data (units, patients…)
     alertResponded { id }                             flip to "rolling"
     alertHide {}                                      no call
     queue  { n }                                      calls waiting behind this one
     active { call | false, stage }                    "on call" strip
     live   { alert: { id, dist, dir, rel, eta }, active: {…} }   ~5 Hz while visible
   JS → Lua: none (no focus; the router never posts for this app)
   ═══════════════════════════════════════════════════════════ */
(() => {
  /* ─────────── shared dispatch helpers (window.NZD) ─────────── */
  // internal stage codes (server) → our own words on screen
  const STAGES = ['DSP', 'ENR', 'SCN', 'CARE', 'TRN', 'HSP'];
  const STAGE_WORD = { DSP: 'Paged', ENR: 'Rolling', SCN: 'On scene', CARE: 'Treating', TRN: 'Transporting', HSP: 'Handover' };
  const STAGE_SHORT = { DSP: 'PAGED', ENR: 'ROLLING', SCN: 'ON SCENE', CARE: 'TREATING', TRN: 'TRANSPORT', HSP: 'HANDOVER' };
  const STAGE_ICON = { DSP: 'bell-ring', ENR: 'nav', SCN: 'pin', CARE: 'medkit', TRN: 'ambulance', HSP: 'hospital' };
  const UNIT_WORD = { 108: 'Available', 107: 'Unavailable' };
  const PRIO_WORD = ['', 'Life threat', 'Serious', 'Minor'];
  const TYPE_ICON = {
    gunshot: 'crosshair', shrapnel: 'burst', stab: 'knife', laceration: 'cut', abrasion: 'scrape', contusion: 'bruise',
    fracture: 'bone', burn: 'flame', internal: 'drop', arrest: 'ecg', overdose: 'pill', mva: 'car', crash: 'car',
    fall: 'arrow-down', drowning: 'drop', deceased: 'skull', dead: 'skull', unconscious: 'brain', call: 'phone',
    fire: 'flame', assault: 'hand', medical: 'medkit', unknown: 'alert',
  };
  const P = (r, deg) => [+(r * Math.cos(deg * Math.PI / 180)).toFixed(2), +(r * Math.sin(deg * Math.PI / 180)).toFixed(2)];
  const arcD = (r, a0, a1) => { const [x0, y0] = P(r, a0), [x1, y1] = P(r, a1); return `M${x0} ${y0}A${r} ${r} 0 ${a1 - a0 > 180 ? 1 : 0} 1 ${x1} ${y1}`; };

  const NZD = window.NZD = {
    STAGES, STAGE_ICON,
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
    prioWord: (p, tr) => (tr ? tr('p' + p + '_word', PRIO_WORD[p]) : PRIO_WORD[p]),
    stageWord: (s, tr) => { const k = STAGES.includes(s) ? s : 'DSP'; return tr ? tr('unit_' + k, STAGE_WORD[k]) : STAGE_WORD[k]; },
    stageShort: (s, tr) => { const k = STAGES.includes(s) ? s : 'DSP'; return tr ? tr('st_' + k.toLowerCase() + '_s', STAGE_SHORT[k]) : STAGE_SHORT[k]; },
    // unit status (10-8 / 10-7 / stage code) → word
    unitWord(s, tr) {
      const k = String(s || '').replace('-', '');
      if (UNIT_WORD[k]) return tr ? tr('unit_' + k, UNIT_WORD[k]) : UNIT_WORD[k];
      return NZD.stageWord(s, tr);
    },
    unitStatusTone(s) { return ({ '10-8': 'teal', '10-7': 'off', DSP: 'amber', ENR: 'amber', SCN: 'red', CARE: 'red', TRN: 'white', HSP: 'teal' })[s] || 'off'; },
    /* Stage ring: six arcs round a dial, done = teal, current = white + pulse, ahead = dim.
       Styles: .nzd-ring in callcard/app.css (loaded globally, used by every dispatch app). */
    stageRing(cur, { size = 44, icon: withIcon = true, cls = '' } = {}) {
      const ci = STAGES.includes(cur) ? STAGES.indexOf(cur) : 0;
      const seg = 60, gap = 9;
      const arcs = STAGES.map((s, i) => {
        const a0 = -90 + i * seg + gap / 2, a1 = -90 + (i + 1) * seg - gap / 2;
        return `<path class="${i < ci ? 'dn' : i === ci ? 'cur' : ''}" d="${arcD(40, a0, a1)}"/>`;
      }).join('');
      const ticks = STAGES.map((s, i) => { const [x0, y0] = P(47, -90 + i * seg), [x1, y1] = P(50, -90 + i * seg); return `<line x1="${x0}" y1="${y0}" x2="${x1}" y2="${y1}"/>`; }).join('');
      return `<span class="nzd-ring s${ci} ${cls}" style="--sz:${size}px"><svg viewBox="-52 -52 104 104"><circle class="bk" r="40"/>${arcs}<g class="tk">${ticks}</g></svg>${withIcon ? `<i>${NZA.icon(STAGE_ICON[STAGES[ci]])}</i>` : ''}</span>`;
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
  let card = null;              // { call, police, at (ms), ageAt, voice, playing, ok, live }
  let act = null;               // { call, stage, live }
  let audioEl = null, timer = 0, ageClock = null;

  /* range scope: answer ring, compass ticks, blip at the call's bearing relative to the camera */
  function scopeSVG() {
    let ticks = '';
    for (let a = 0; a < 360; a += 10) {
      const long = a % 90 === 0, mid = a % 30 === 0;
      const [x0, y0] = P(long ? 41 : mid ? 43 : 45, a - 90), [x1, y1] = P(47.5, a - 90);
      ticks += `<line class="${long ? 'l' : mid ? 'm' : ''}" x1="${x0}" y1="${y0}" x2="${x1}" y2="${y1}"/>`;
    }
    return `<svg class="sc-svg" viewBox="-60 -60 120 120">
      <defs><radialGradient id="cc-face"><stop offset="0" stop-color="#15191b"/><stop offset=".72" stop-color="#0b0d0e"/><stop offset="1" stop-color="#050606"/></radialGradient>
        <linearGradient id="cc-sweep" x1="0" y1="0" x2="0" y2="-1"><stop offset="0" stop-color="var(--pc)" stop-opacity="0"/><stop offset="1" stop-color="var(--pc)" stop-opacity=".42"/></linearGradient></defs>
      <circle class="sc-face" r="51"/>
      <circle class="sc-rng" r="31"/><circle class="sc-rng" r="16"/>
      <path class="sc-x" d="M-47 0H-34M34 0H47M0 34V47"/>
      <g class="sc-tk">${ticks}</g>
      <path class="sc-fwd" d="M0 -51.5 L4 -45 L-4 -45Z"/>
      <circle class="sc-trk" r="56"/>
      <circle class="sc-ans" r="56" pathLength="100" stroke-dasharray="100 100"/>
      <g class="sc-blip"><path class="sc-sweep" d="M0 0 L${P(46, -104).join(' ')} A46 46 0 0 1 ${P(46, -76).join(' ')}Z"/><circle class="sc-ping" cx="0" cy="-38" r="4"/><circle class="sc-dot" cx="0" cy="-38" r="3.4"/></g>
    </svg>`;
  }

  function casualtyText(c) {
    const pts = c.patients || [];
    if (!pts.length) return { v: tr('cc_cas_unknown', 'Unknown'), tone: '' };
    const worst = Math.min(...pts.map(p => Number(p.tri) || 3));
    return { v: `${pts.length} · ${String(tr('tri_' + worst, ['', 'Immediate', 'Delayed', 'Minor'][worst])).toLowerCase()}`, tone: worst === 1 ? 'red' : worst === 2 ? 'amber' : 'teal' };
  }

  function renderCard() {
    if (ageClock) ageClock = null;
    if (!card) { cardHost.innerHTML = ''; cardHost.className = 'cc-cardhost'; moreEl.classList.remove('on'); return; }
    const c = card.call, p = NZD.prio(c.priority);
    const units = (c.units || []).length;
    const tags = (c.tags || []).slice(0, 3);
    const cas = casualtyText(c);
    const police = card.police;
    const voice = card.voice ? `<span class="cc-wave ${card.playing ? 'play' : ''}">${Array.from({ length: 13 }, (_, i) => `<i style="animation-delay:${(i * 97) % 640}ms"></i>`).join('')}</span><span class="cc-live">${esc(tr('cc_voice', 'Live audio'))}</span>` : '';
    const caller = c.caller || c.message ? `
      <div class="cc-call">
        <div class="cl-h">${icon('phone')}<b>${esc(c.caller || tr('cc_unknown_caller', 'Unknown'))}</b>${c.phone ? `<span class="ph">${esc(c.phone)}</span>` : ''}<span class="sp"></span>${voice}</div>
        ${c.message ? `<q>${esc(c.message)}</q>` : ''}
      </div>` : '';
    const chips = [
      ...tags.map(tg => `<span class="cc-tag">${icon(NZD.typeIcon(tg))}${esc(tr('type_' + tg, tg))}</span>`),
      c.npc ? `<span class="cc-tag dim">${icon('walk')}${esc(tr('cc_npc', 'Street call'))}</span>` : '',
    ].join('');
    const takeLbl = card.ok ? tr('cc_responding', 'Rolling') : police ? tr('cc_gps', 'Mark map') : tr('cc_respond', 'Take call');
    cardHost.className = 'cc-cardhost on';
    cardHost.innerHTML = `
      <div class="cc-card p${p} ${police ? 'police' : ''} ${card.ok ? 'ok' : ''}">
        <div class="cc-scope">
          <div class="sc-dial">${scopeSVG()}<div class="sc-mid"><b data-dist>--</b><span data-du>m</span><em data-dir>--</em></div></div>
          <span class="sc-lbl">${card.ok ? `${icon('route')}${esc(tr('cc_sc_route', 'Route set'))}` : police ? esc(tr('cc_sc_notice', 'Notice')) : `${esc(tr('cc_sc_answer', 'Answer in'))}<b data-left>${Math.ceil(cfg.timeout)}s</b>`}</span>
        </div>
        <div class="cc-body">
          <div class="cc-kick"><span class="cc-pchip">${police ? icon('shield') : `P${p}`}</span><span class="cc-pw">${esc(police ? tr('cc_police', 'EMS notice') : NZD.prioWord(p, tr))}</span><span class="sp"></span><span class="cc-ref">${esc([c.code, c.id].filter(Boolean).join(' · '))}</span></div>
          <h3><span class="cc-ti">${icon(NZD.typeIcon(c.type))}</span><span class="tt">${esc(c.title || tr('call_default', 'Medical emergency'))}</span></h3>
          <div class="cc-where"><b>${esc(c.zone || tr('unknown_location', 'Unknown location'))}</b>${c.street ? `<span>${esc(c.street)}</span>` : ''}</div>
          <div class="cc-inst">
            <div class="ir"><span>${esc(tr('cc_i_drive', 'Drive time'))}</span><b data-eta>--:--</b></div>
            <div class="ir ${cas.tone}"><span>${esc(tr('cc_i_cas', 'Casualties'))}</span><b>${esc(cas.v)}</b></div>
            <div class="ir ${units ? 'teal' : 'amber'}"><span>${esc(tr('cc_i_crews', 'Crews on it'))}</span><b>${esc(units ? NZD.fmt(tr('cc_units_on', '%d crew'), units) : tr('cc_none_yet', 'None yet'))}</b></div>
            <div class="ir"><span>${esc(tr('cc_i_holding', 'Holding'))}</span><b class="cc-age"></b></div>
          </div>
        </div>
        <div class="cc-rail">
          <div class="cc-key take">${card.ok ? `<span class="ok">${icon('check')}</span>` : `<kbd>${esc(cfg.keys.respond)}</kbd>`}<span>${esc(takeLbl)}</span></div>
          <div class="cc-key pass"><kbd>${esc(cfg.keys.dismiss)}</kbd><span>${esc(tr('cc_dismiss', 'Pass'))}</span></div>
        </div>
        ${caller || chips ? `<div class="cc-foot">${caller}${chips ? `<div class="cc-tags">${chips}</div>` : ''}</div>` : ''}
      </div>`;
    ageClock = NZA.ui.FlipClock(cardHost.querySelector('.cc-age'), { value: NZD.age((c.age || 0) + (performance.now() - card.ageAt) / 1000), small: true });
    const ans = cardHost.querySelector('.sc-ans');
    if (!card.ok) {
      const left = Math.max(0.5, cfg.timeout - (performance.now() - card.at) / 1000);
      const from = 100 - (left / cfg.timeout) * 100;
      ans.animate([{ strokeDashoffset: from }, { strokeDashoffset: 100 }], { duration: left * 1000, easing: 'linear', fill: 'forwards' });
    } else ans.style.strokeDashoffset = '0';
    renderMore();
    if (card.live) applyLive(cardHost, card.live);
  }

  function renderMore() {
    const n = card ? card.queue || 0 : 0;
    moreEl.classList.toggle('on', n > 0);
    cardHost.classList.toggle('stack', n > 0);
    moreEl.innerHTML = n > 0 ? `<span class="pips">${'<i></i>'.repeat(Math.min(n, 5))}</span><span>${esc(NZD.fmt(tr(n === 1 ? 'cc_more_1' : 'cc_more', n === 1 ? '1 more in the queue' : '%d more in the queue'), n))}</span><span class="k"><kbd>${esc(cfg.keys.dismiss)}</kbd>${esc(tr('cc_next', 'skips ahead'))}</span>` : '';
  }

  function renderActive() {
    if (!act) { activeEl.classList.remove('on'); activeEl.innerHTML = ''; return; }
    const c = act.call, p = NZD.prio(c.priority);
    const stage = act.stage || c.status || 'DSP';
    const ni = NZD.stageIdx(stage) + 1;
    activeEl.className = `cc-active on p${p}`;
    activeEl.innerHTML = `
      ${NZD.stageRing(stage, { size: 54 })}
      <div class="ca-txt">
        <span class="ca-k">${esc(tr('cc_your_call', 'On call'))}<i>${esc(c.id)}</i><em>P${p}</em></span>
        <b class="ca-t">${esc(c.title || '')}</b>
        <span class="ca-s"><em>${esc(NZD.stageWord(stage, tr))}</em>${ni < 6 ? `<span class="nx">${icon('chev-r')}${esc(NZD.stageWord(NZD.STAGES[ni], tr))}</span>` : ''}</span>
      </div>
      <div class="ca-rng">
        <span class="ca-ar"><svg class="cc-arrow" viewBox="0 0 24 24"><path d="M12 3l6.5 15.5L12 15l-6.5 3.5z"/></svg></span>
        <span class="ca-d"><b data-dist>--</b><span data-du>m</span></span>
        <span class="ca-e" data-eta>--:--</span>
      </div>`;
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
    if (l.rel != null) {
      const b = q('.sc-blip'); if (b) b.style.transform = `rotate(${l.rel}deg)`;
      const a = q('.cc-arrow'); if (a) a.style.transform = `rotate(${l.rel}deg)`;
    }
    const cardEl = host.querySelector('.cc-card');
    if (cardEl) cardEl.classList.toggle('near', l.dist != null && l.dist < 60);
  }

  function tickAges() {
    if (!card) return;
    if (ageClock) ageClock.set(NZD.age((card.call.age || 0) + (performance.now() - card.ageAt) / 1000));
    const l = cardHost.querySelector('[data-left]');
    if (l) {
      const left = Math.max(0, Math.ceil(cfg.timeout - (performance.now() - card.at) / 1000));
      l.textContent = `${left}s`;
      l.classList.toggle('low', left <= 8);
    }
  }

  function stopVoice() {
    if (audioEl) { try { audioEl.pause(); } catch (e) { /* already stopped */ } audioEl = null; }
    if (card) card.playing = false;
    const v = cardHost && cardHost.querySelector('.cc-wave');
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
      const v = cardHost.querySelector('.cc-wave');
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
      activeEl = NZA.el('div', 'cc-active');
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
        if (playing) { const v = cardHost.querySelector('.cc-wave'); if (v) v.classList.add('play'); }
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
          id: 'C-0412', code: '10-52', priority: 1, title: 'Shot in the chest', type: 'gunshot', zone: 'Vespucci Canals',
          street: 'Imagination Ct / Prosperity St', caller: 'Michael Garcia', phone: '555-0142',
          message: 'He took one in the chest outside the laundromat, he is still breathing but it is fast. Please hurry.', age: 9,
          patients: [{ pid: 'n:1', tri: 1 }], tags: ['gunshot', 'internal'], units: [], npc: true,
        },
        queue: 2, sound: false, voice: null,
      });
      card.voice = 'audio/calls/demo.ogg'; card.playing = true; renderCard();
      NZA.apps.callcard.msg.active({
        call: { id: 'C-0409', code: '10-50', priority: 2, title: 'Two-car collision', type: 'mva', zone: 'Pillbox Hill', street: 'Palomino Ave', status: 'SCN' },
        stage: 'ENR',
      });
      let rel = 212;
      const step = () => {
        rel = (rel + 1.5) % 360;
        NZA.apps.callcard.msg.live({ alert: { id: 'C-0412', dist: 312, dir: 'SW', rel, eta: 19 }, active: { id: 'C-0409', dist: 1460, dir: 'NE', rel: (rel + 140) % 360, eta: 74 } });
      };
      step(); setInterval(step, 200);
    },
  });
})();
