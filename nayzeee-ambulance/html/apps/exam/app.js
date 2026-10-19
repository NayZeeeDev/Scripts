/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · Head-to-toe check (app 'exam')    module: assess
   Layout (NAYZEEE HUD language):
     top-left     patient card: name, triage, state, open problems, time-left status ring
                  with a rolling counter, observation list (tone notches), devices
     left         holographic body map card: front / back, 8 region hotspots coloured by
                  status, injury pins (diamonds), hover tooltip, scan beam, legend
     centre       diamond markers on the 3D body (NZA anchors), chip on the selected one
     right        findings stack for the selected region: severity rings, accordion of
                  problems, instrument-list findings, supplies, next care step
     right edge   check dock: Pulse / Breathing / Bleed control (status rings, key badges)
     bottom-left  key legend chips
   Lua → JS   open { locale, groups, view, patient, perms }   view (live)   anchors (stream)
   JS → Lua   exam:touch { group }   exam:treat { id, route }   exam:action { action, group }
              exam:close (ESC)
   Keys: ↑/↓ or Tab region · F front/back · Enter start the next care step · 1 pulse ·
         2 breathing · 3 bleed control · ESC close

   Also defines window.NZAAssess (preview-only body renderer shared by exam / pulse /
   breathing previews; never used in game).
   ═══════════════════════════════════════════════════════════ */
(() => {
  const esc = NZA.esc, icon = NZA.icon, clamp = NZA.clamp;
  let LOC = {};
  const T = (k, fb, ...a) => { let s = LOC[k] !== undefined ? String(LOC[k]) : fb; a.forEach(v => { s = s.replace(/%[sd]/, v); }); return s; };

  NZ.addIcons({
    'as-flip': '<path d="M4 9a8 8 0 0 1 14-3l2 2"/><path d="M20 4v4h-4"/><path d="M20 15a8 8 0 0 1-14 3l-2-2"/><path d="M4 20v-4h4"/>',
    'as-body': '<circle cx="12" cy="4.5" r="2.2"/><path d="M8 8.5h8l-1 6h-6z"/><path d="M8 8.5 5 14M16 8.5l3 5.5M10 14.5 9 21M14 14.5l1 6.5"/>',
    'as-diamond': '<path d="M12 3 21 12 12 21 3 12z"/>',
  });

  /* ─────────────── preview body (browser only) ─────────────── */
  const NZAAssess = window.NZAAssess = window.NZAAssess || {};
  NZAAssess.body = function body({ focus = 'full', shirtless = false, wounds = [] } = {}) {
    document.querySelectorAll('.nzas-body').forEach(n => n.remove());
    const wrap = document.createElement('div');
    wrap.className = 'nzas-body';
    const skin = '#b98a6c', skinD = '#8f6249', cloth = '#1c2431', clothH = '#2a3546', clothD = '#121821';
    const torsoH = shirtless ? '#d0a283' : clothH;
    const W = { chest: [128, 150], thigh_l: [160, 360], thigh_r: [100, 352], head: [122, 40], forearm_l: [226, 214], abdomen: [140, 236] };
    const blood = wounds.map((w, i) => { const p = W[w] || [130, 150]; return `<ellipse cx="${p[0]}" cy="${p[1]}" rx="${16 + (i % 2) * 6}" ry="${12 + (i % 3) * 4}" fill="url(#bl)" opacity=".95"/><circle cx="${p[0] + 2}" cy="${p[1] - 1}" r="4" fill="#3a0405"/>`; }).join('');
    wrap.innerHTML = `<svg viewBox="-200 -120 660 860" preserveAspectRatio="xMidYMid meet">
      <defs>
        <radialGradient id="bl"><stop offset="0" stop-color="#6b0b0e"/><stop offset=".55" stop-color="#7d1114" stop-opacity=".85"/><stop offset="1" stop-color="#5a0a0c" stop-opacity="0"/></radialGradient>
        <linearGradient id="cl" x1="0" x2="1"><stop offset="0" stop-color="${clothD}"/><stop offset=".45" stop-color="${torsoH}"/><stop offset="1" stop-color="${clothD}"/></linearGradient>
        <linearGradient id="tr" x1="0" x2="1"><stop offset="0" stop-color="${shirtless ? skinD : clothD}"/><stop offset=".5" stop-color="${torsoH}"/><stop offset="1" stop-color="${shirtless ? skinD : clothD}"/></linearGradient>
        <radialGradient id="hd" cx=".45" cy=".4"><stop offset="0" stop-color="#d4a585"/><stop offset="1" stop-color="${skinD}"/></radialGradient>
        <filter id="sh" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="9"/></filter>
      </defs>
      <g class="b" data-g="1">
        <g filter="url(#sh)" opacity=".55" transform="translate(10 14)">
          <path d="M92 110 L168 110 L176 300 L84 300 Z" fill="#000"/><circle cx="130" cy="44" r="36" fill="#000"/>
          <path d="M92 118 L8 262 L26 270 L106 140Z M168 118 L252 262 L234 270 L154 140Z" fill="#000"/>
          <path d="M96 290 L80 575 L110 578 L128 300Z M164 290 L180 575 L150 578 L132 300Z" fill="#000"/>
        </g>
        <path d="M100 116 C70 150 34 205 12 256 C8 266 22 274 28 266 C54 220 88 178 112 146 Z" fill="${shirtless ? skin : 'url(#cl)'}"/>
        <path d="M160 116 C190 150 226 205 248 256 C252 266 238 274 232 266 C206 220 172 178 148 146 Z" fill="${shirtless ? skin : 'url(#cl)'}"/>
        <ellipse cx="17" cy="266" rx="13" ry="16" fill="${skin}"/><ellipse cx="243" cy="266" rx="13" ry="16" fill="${skin}"/>
        <path d="M104 286 C96 380 86 470 82 560 L114 562 C118 470 124 380 130 300 Z" fill="url(#cl)"/>
        <path d="M156 286 C164 380 174 470 178 560 L146 562 C142 470 136 380 130 300 Z" fill="url(#cl)"/>
        <path d="M78 556 L118 556 L120 592 C120 600 76 600 76 592 Z" fill="#0a0b0c"/><path d="M142 556 L182 556 L184 592 C184 600 140 600 140 592 Z" fill="#0a0b0c"/>
        <path d="M96 104 C110 96 150 96 164 104 C176 112 180 140 176 190 C174 240 172 270 170 300 L90 300 C88 270 86 240 84 190 C80 140 84 112 96 104 Z" fill="url(#tr)"/>
        ${shirtless ? '<path d="M104 150 C116 160 144 160 156 150" stroke="#8f6249" stroke-width="2" fill="none" opacity=".6"/><path d="M130 112 L130 230" stroke="#8f6249" stroke-width="1.5" opacity=".35"/><circle cx="130" cy="238" r="3" fill="#7a5038"/>' : '<path d="M130 106 L130 296" stroke="#0b0f15" stroke-width="2" opacity=".6"/><rect x="88" y="272" width="84" height="12" rx="3" fill="#0b0d10"/><rect x="124" y="272" width="12" height="12" rx="2" fill="#6b6f76"/><rect x="104" y="128" width="16" height="10" rx="2" fill="#c9a24a" opacity=".85"/>'}
        <rect x="116" y="76" width="28" height="30" rx="10" fill="${skinD}"/>
        <ellipse cx="130" cy="44" rx="32" ry="38" fill="url(#hd)"/>
        <path d="M100 30 C104 6 156 6 160 30 C150 18 110 18 100 30Z" fill="#1a120c"/>
        ${blood}
      </g>
    </svg>`;
    const bg = document.querySelector('.nza-bg');
    if (bg && bg.nextSibling) bg.parentNode.insertBefore(wrap, bg.nextSibling); else document.body.prepend(wrap);
    const g = wrap.querySelector('g.b');
    // move point P to the view centre C, then rotate and scale around it
    const tf = (px, py, rot, k, cx = 130, cy = 310) => `translate(${cx} ${cy}) rotate(${rot}) scale(${k}) translate(${-px} ${-py})`;
    const F = {
      full: tf(130, 300, -22, 0.92, 170, 330),
      chest: tf(130, 160, -90, 2.7, 150, 300),
      wrist: tf(22, 252, 13, 2.4, 60, 280),
    };
    g.setAttribute('transform', F[focus] || F.full);
    wrap.dataset.focus = focus;
    const P = {
      head: [130, 40], neck: [130, 92], chest: [130, 150], abdomen: [130, 232], center: [130, 190],
      r_arm: [50, 206], l_arm: [210, 206], r_leg: [101, 440], l_leg: [159, 440],
      wrist: [22, 252], carotid: [120, 92],
      ru: [110, 130], rm: [104, 156], rl: [110, 182], lu: [150, 130], lm: [156, 156], ll: [150, 182],
    };
    const svg = wrap.querySelector('svg');
    const pt = svg.createSVGPoint();
    return {
      el: wrap,
      at(name) {
        const p = P[name]; if (!p) return null;
        pt.x = p[0]; pt.y = p[1];
        const s = pt.matrixTransform(g.getScreenCTM());
        return { x: s.x / window.innerWidth, y: s.y / window.innerHeight, visible: true };
      },
      map(names) { const o = {}; names.forEach(n => { o[n] = this.at(n); }); return o; },
      remove() { wrap.remove(); },
    };
  };
  // feed anchors to an app like Lua would
  NZAAssess.feed = function feed(app, names, body) {
    const send = () => window.postMessage({ app, action: 'anchors', data: body.map(names) }, '*');
    send();
    window.addEventListener('resize', send);
    return send;
  };

  /* ─────────────── constants ─────────────── */
  const TONE = { healthy: 'clear', treated: 'teal', minor: 'amber', serious: 'red', critical: 'crit' };
  const ORDER = ['head', 'neck', 'chest', 'abdomen', 'l_arm', 'r_arm', 'l_leg', 'r_leg'];
  const GROUP_FB = { head: 'Head', neck: 'Neck', chest: 'Chest', abdomen: 'Abdomen', l_arm: 'Left arm', r_arm: 'Right arm', l_leg: 'Left leg', r_leg: 'Right leg' };
  const GS_FB = { healthy: 'Clear', minor: 'Minor', serious: 'Serious', critical: 'Severe', treated: 'Treated' };
  const SEV_RANK = { critical: 4, serious: 3, minor: 2, treated: 1, healthy: 0 };
  const BLEED_LV = { none: 0, light: 1, moderate: 2, heavy: 3, massive: 4 };
  const BLEED_TONE = ['teal', 'amber', 'amber', 'red', 'red'];
  const ACTIVE = s => s === 'open' || s === 'controlled' || s === undefined || s === null;

  /* ─────────────── holographic body (front view coordinates; back = mirrored) ─────────────── */
  const VB = { x: -70, y: -8, w: 340, h: 456 };
  const BODY = {
    head: 'M100,8 C112,8 121,18 121,33 C121,48 112,60 100,60 C88,60 79,48 79,33 C79,18 88,8 100,8 Z',
    neck: 'M90,54 C90,62 89,68 86,74 L114,74 C111,68 110,62 110,54 C106,58 94,58 90,54 Z',
    chest: 'M86,74 C77,76 66,78 60,84 C55,90 55,100 57,112 C59,126 61,142 63,160 L137,160 C139,142 141,126 143,112 C145,100 145,90 140,84 C134,78 123,76 114,74 C108,77 92,77 86,74 Z',
    abdomen: 'M63,160 L137,160 C138,178 140,196 142,214 C143,222 140,230 134,234 C124,238 112,240 100,240 C88,240 76,238 66,234 C60,230 57,222 58,214 C60,196 62,178 63,160 Z',
    r_arm: 'M60,84 C50,86 44,94 42,106 C40,124 38,142 36,158 C34,176 30,196 27,214 C25,226 23,236 22,246 C21,254 24,262 29,262 C34,262 37,256 37,248 C38,238 40,228 42,216 C46,198 50,180 52,164 C54,148 56,132 57,116 C56,104 56,92 60,84 Z',
    l_arm: 'M140,84 C150,86 156,94 158,106 C160,124 162,142 164,158 C166,176 170,196 173,214 C175,226 177,236 178,246 C179,254 176,262 171,262 C166,262 163,256 163,248 C162,238 160,228 158,216 C154,198 150,180 148,164 C146,148 144,132 143,116 C144,104 144,92 140,84 Z',
    r_leg: 'M66,234 C76,238 88,240 98,240 L97,262 C96,290 94,318 92,344 C91,364 90,384 90,404 C90,412 92,420 92,426 C92,432 86,434 78,434 C70,434 68,430 70,424 C72,416 72,408 72,402 C70,382 68,362 67,344 C64,316 61,290 60,262 C59,250 61,240 66,234 Z',
    l_leg: 'M134,234 C124,238 112,240 102,240 L103,262 C104,290 106,318 108,344 C109,364 110,384 110,404 C110,412 108,420 108,426 C108,432 114,434 122,434 C130,434 132,430 130,424 C128,416 128,408 128,402 C130,382 132,362 133,344 C136,316 139,290 140,262 C141,250 139,240 134,234 Z',
  };
  const DETAIL_FRONT = 'M72,85 C84,89 94,87 100,90 C106,87 116,89 128,85 M100,92 L100,150 M70,118 C82,128 94,126 100,121 C106,126 118,128 130,118 M100,164 L100,228 M86,176 L114,176 M85,194 L115,194 M90,62 C96,66 104,66 110,62 M80,346 C84,350 90,350 92,346 M108,346 C110,350 116,350 120,346 M92,30 L96,30 M104,30 L108,30 M97,44 C99,46 101,46 103,44';
  const DETAIL_BACK = 'M100,62 L100,232 M70,96 C76,112 86,118 93,108 M130,96 C124,112 114,118 107,108 M66,226 C80,240 96,238 100,228 C104,238 120,240 134,226 M82,18 C90,12 110,12 118,18 M80,350 L92,350 M108,350 L120,350';
  const CENTER = { head: [100, 30], neck: [100, 64], chest: [100, 116], abdomen: [100, 198], r_arm: [36, 176], l_arm: [164, 176], r_leg: [80, 334], l_leg: [120, 334] };
  const PIN = {
    head: [100, 22], face: [100, 44], neck: [100, 66], chest: [100, 110], back: [100, 124], abdomen: [100, 186], pelvis: [100, 224],
    r_upper_arm: [50, 120], r_lower_arm: [36, 198], l_upper_arm: [150, 120], l_lower_arm: [164, 198],
    r_upper_leg: [80, 292], r_lower_leg: [80, 382], l_upper_leg: [120, 292], l_lower_leg: [120, 382],
  };
  const FRONT_ONLY = { face: 1, chest: 1, abdomen: 1, pelvis: 1 };
  const BACK_ONLY = { back: 1 };

  // 4-segment severity ring with an icon inside
  function sevRing(sev, tone, ic, cls = '') {
    const R = 15, C = 2 * Math.PI * R, q = C / 4, gap = 2.6, seg = q - gap;
    let s = '';
    for (let i = 0; i < 4; i++) s += `<circle class="sg${i < sev ? ' on' : ''}" cx="18" cy="18" r="${R}" stroke-dasharray="${seg.toFixed(2)} ${(C - seg).toFixed(2)}" stroke-dashoffset="${(-(i * q) - gap / 2).toFixed(2)}"/>`;
    return `<span class="sring t-${tone} ${cls}"><svg class="rs" viewBox="0 0 36 36">${s}</svg>${icon(ic)}</span>`;
  }
  // simple progress ring (0..1)
  function ring(p, r = 15, box = 36) {
    const C = 2 * Math.PI * r;
    return `<svg class="rs" viewBox="0 0 ${box} ${box}"><circle class="bg" cx="${box / 2}" cy="${box / 2}" r="${r}"/><circle class="fg" cx="${box / 2}" cy="${box / 2}" r="${r}" stroke-dasharray="${C.toFixed(2)}" stroke-dashoffset="${(C * (1 - clamp(p, 0, 1))).toFixed(2)}"/></svg>`;
  }

  NZA.app('exam', {
    init(el) {
      this.el = el;
      el.innerHTML = `
        <div class="ex-vig"></div>
        <div class="ex-marks"></div>
        <aside class="ex-colL">
          <section class="ex-pt nza-hud solid nza-int"></section>
          <section class="ex-map nza-hud solid nza-int">
            <header class="mh"><span class="kick">${icon('as-body')}<span class="mt"></span></span><div class="seg"><button data-v="front"></button><button data-v="back"></button><kbd>F</kbd></div></header>
            <div class="ex-holo"><div class="hz"></div><div class="htip"></div></div>
            <footer class="ml"></footer>
          </section>
        </aside>
        <aside class="ex-colR"><section class="ex-find nza-hud solid nza-int"></section></aside>
        <nav class="ex-dock nza-int"></nav>
        <div class="ex-keys"></div>`;
      this.$ = s => el.querySelector(s);
      this.marks = this.$('.ex-marks');
      this.holo = this.$('.ex-holo .hz');
      this.tip = this.$('.ex-holo .htip');
      this.diamonds = {};
      this.face = 'front';
      this.anc = NZA.ui.Anchors('exam');
      this.anc.on(() => this.layout());
      window.addEventListener('resize', () => { if (NZA.isOpen('exam')) this.layout(); });
      this.$('.ex-find').addEventListener('click', e => this.onFindClick(e));
      this.$('.ex-dock').addEventListener('click', e => { const b = e.target.closest('button[data-act]'); if (b && !b.classList.contains('off')) this.action(b.dataset.act); });
      this.$('.ex-map .seg').addEventListener('click', e => { const b = e.target.closest('button[data-v]'); if (b) this.flip(b.dataset.v); });
      this.buildHolo();
    },

    open(d) {
      LOC = Object.assign({}, d.locale || {});
      this.groups = (d.groups && d.groups.length ? d.groups : ORDER.map(n => ({ name: n }))).map(g => ({ name: g.name, label: g.label || T(`group_${g.name}`, GROUP_FB[g.name] || g.name) }));
      this.patient = d.patient || {};
      this.perms = Object.assign({ pulse: true, breathing: true }, d.perms || {});
      this.view = d.view || { groups: {} };
      this.sel = this.pickWorst();
      this.expanded = null;
      this.clockMax = 0;
      this.marks.innerHTML = '';
      this.diamonds = {};
      this.groups.forEach(g => this.makeDiamond(g));
      this.$('.ex-map .mt').textContent = T('map_title', 'Body map');
      this.$('.ex-map .seg [data-v="front"]').textContent = T('map_front', 'Front');
      this.$('.ex-map .seg [data-v="back"]').textContent = T('map_back', 'Back');
      this.flip('front', true);
      this.renderKeys();
      this.renderAll();
      this.layout();
      clearInterval(this.tick);
      this.tick = setInterval(() => this.tickClock(), 250);
      this.el.classList.remove('ex-in'); void this.el.offsetWidth; this.el.classList.add('ex-in');
    },
    close() { clearInterval(this.tick); this.marks.innerHTML = ''; this.diamonds = {}; this.odo = null; },

    msg: {
      view(v) {
        const a = NZA.apps.exam;
        a.view = v || a.view;
        if (!a.view.groups[a.sel]) a.sel = a.pickWorst();
        a.renderAll();
        a.layout();
      },
    },

    keys: {
      ArrowDown() { NZA.apps.exam.step(1); },
      ArrowUp() { NZA.apps.exam.step(-1); },
      Tab(e) { NZA.apps.exam.step(e.shiftKey ? -1 : 1); },
      Enter() { NZA.apps.exam.treatFirst(); },
      KeyF() { const a = NZA.apps.exam; a.flip(a.face === 'front' ? 'back' : 'front'); },
      Digit1() { NZA.apps.exam.action('pulse'); },
      Digit2() { NZA.apps.exam.action('breathing'); },
      Digit3() { NZA.apps.exam.action('stopbleed'); },
    },

    /* ── helpers ── */
    gview(name) { return (this.view.groups || {})[name] || { status: 'healthy', injuries: [], notes: [] }; },
    glabel(name) { const g = (this.groups || []).find(x => x.name === name); return g ? g.label : T(`group_${name}`, GROUP_FB[name] || name); },
    gstatus(v) { return v.statusLabel || T(`gs_${v.status}`, GS_FB[v.status] || v.status); },
    openCount(v) { return (v.injuries || []).filter(i => ACTIVE(i.status) || i.suspected).length; },
    pickWorst() {
      let best = 'chest', rank = -1;
      ORDER.forEach(n => { const g = (this.view.groups || {})[n]; const r = g ? (SEV_RANK[g.status] ?? 0) * 10 + (g.injuries || []).length : 0; if (r > rank) { rank = r; best = n; } });
      return best;
    },
    step(dir) {
      const i = ORDER.indexOf(this.sel);
      this.select(ORDER[(i + dir + ORDER.length) % ORDER.length]);
    },
    select(name, touch = true) {
      if (!name) return;
      if (name !== this.sel) this.expanded = null;
      this.sel = name;
      this.renderHoloState();
      this.renderDiamonds();
      this.renderFindings();
      this.layout();
      if (touch) NZA.post('exam:touch', { group: name });
      NZA.audio.click(720);
    },
    action(act) {
      if (act === 'pulse' && this.perms.pulse === false) return;
      if (act === 'breathing' && this.perms.breathing === false) return;
      if (act === 'stopbleed' && !this.view.canStop) { NZA.audio.fail(); return; }
      const b = this.$(`.ex-dock [data-act="${act}"]`);
      if (b) { b.classList.remove('hit'); void b.offsetWidth; b.classList.add('hit'); }
      NZA.audio.click(880);
      NZA.post('exam:action', { action: act, group: this.sel });
    },
    treatFirst() {
      const g = this.gview(this.sel);
      const list = g.injuries || [];
      const first = list.find(i => i.id === this.expanded) || null;
      const ordered = first ? [first, ...list.filter(i => i !== first)] : list;
      for (const inj of ordered) {
        const r = (inj.routes || []).find(x => x.ok);
        if (r) return this.treat(inj.id, r.id);
      }
      NZA.audio.fail();
    },
    async treat(id, route) {
      NZA.audio.click(990);
      const res = await NZA.post('exam:treat', { id, route });
      if (res && res.ok === false) NZA.audio.fail();
    },
    onFindClick(e) {
      const go = e.target.closest('button[data-route]');
      if (go) { if (!go.disabled) this.treat(go.dataset.inj, go.dataset.route); return; }
      const h = e.target.closest('.ij-h');
      if (h) {
        const id = h.dataset.id;
        this.expanded = this.expanded === id ? '__none' : id;
        this.renderFindings();
        NZA.audio.click(640);
      }
    },

    /* ── 3D body: diamond markers ── */
    makeDiamond(g) {
      const b = document.createElement('button');
      b.className = 'exm nza-int';
      b.dataset.g = g.name;
      b.innerHTML = '<span class="dm"><i></i></span><span class="halo"></span><span class="chip"><b></b><em></em></span>';
      b.addEventListener('click', () => this.select(g.name));
      b.addEventListener('mouseenter', () => { this.hover = g.name; this.renderDiamonds(); this.showTip(g.name); });
      b.addEventListener('mouseleave', () => { this.hover = null; this.renderDiamonds(); this.showTip(null); });
      this.marks.appendChild(b);
      this.diamonds[g.name] = b;
    },
    renderDiamonds() {
      Object.entries(this.diamonds).forEach(([name, b]) => {
        const v = this.gview(name);
        const tone = TONE[v.status] || 'clear';
        const on = name === this.sel, hov = name === this.hover;
        b.className = `exm nza-int t-${tone}${on ? ' on' : ''}${hov ? ' hov' : ''}`;
        b.querySelector('.chip b').textContent = this.glabel(name);
        const n = this.openCount(v);
        b.querySelector('.chip em').textContent = n ? T('open_n_short', '%d open', n) : this.gstatus(v);
      });
    },
    layout() {
      const W = this.el.clientWidth, H = this.el.clientHeight;
      if (!W || !H) return;
      const map = this.anc.all() || {};
      Object.entries(this.diamonds).forEach(([name, b]) => {
        const a = map[name];
        if (!a || a.visible === false) { b.style.display = 'none'; return; }
        b.style.display = '';
        b.style.transform = `translate(${(a.x * W).toFixed(1)}px, ${(a.y * H).toFixed(1)}px)`;
        // chip goes to the side with more room
        b.classList.toggle('flipL', a.x > 0.56);
      });
    },

    /* ── holographic body map ── */
    buildHolo() {
      const regions = face => ORDER.map(n => `<path class="rg" data-g="${n}" d="${BODY[n]}"/>`).join('');
      const scan = Object.values(BODY).map(d => `<path d="${d}"/>`).join('');
      const ticks = Array.from({ length: 23 }, (_, i) => `<line x1="-52" x2="${i % 5 ? -46 : -40}" y1="${8 + i * 19}" y2="${8 + i * 19}"/>`).join('');
      this.holo.innerHTML = `<svg class="hs" viewBox="${VB.x} ${VB.y} ${VB.w} ${VB.h}" preserveAspectRatio="xMidYMid meet">
        <defs>
          <linearGradient id="exHg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0fd4c4" stop-opacity=".30"/><stop offset=".55" stop-color="#08afa2" stop-opacity=".13"/><stop offset="1" stop-color="#08afa2" stop-opacity=".05"/></linearGradient>
          <pattern id="exScan" width="4" height="3" patternUnits="userSpaceOnUse"><rect width="4" height="1" fill="#7ff5ea" fill-opacity=".16"/></pattern>
          <linearGradient id="exBeam" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0fd4c4" stop-opacity="0"/><stop offset=".85" stop-color="#0fd4c4" stop-opacity=".35"/><stop offset="1" stop-color="#bffcf6" stop-opacity=".9"/></linearGradient>
          <radialGradient id="exFloor"><stop offset="0" stop-color="#0fd4c4" stop-opacity=".35"/><stop offset="1" stop-color="#0fd4c4" stop-opacity="0"/></radialGradient>
          <clipPath id="exClipF">${scan}</clipPath>
          <clipPath id="exClipB"><g transform="matrix(-1 0 0 1 200 0)">${scan}</g></clipPath>
          <filter id="exGlow" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="2.2" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
        </defs>
        <g class="grid">${Array.from({ length: 9 }, (_, i) => `<line x1="${-60 + i * 40}" y1="-8" x2="${-60 + i * 40}" y2="448"/>`).join('')}${Array.from({ length: 12 }, (_, i) => `<line x1="-70" y1="${i * 40}" x2="270" y2="${i * 40}"/>`).join('')}</g>
        <g class="ruler">${ticks}<text x="-40" y="4">0</text><text x="-40" y="444">${esc(T('map_scale', '1.8 m'))}</text></g>
        <ellipse class="floor" cx="100" cy="438" rx="92" ry="15" fill="url(#exFloor)"/>
        <ellipse class="fring a" cx="100" cy="438" rx="78" ry="11"/><ellipse class="fring b" cx="100" cy="438" rx="58" ry="8"/>
        <g class="view front">
          <g class="body" filter="url(#exGlow)">${regions('front')}</g>
          <g class="scanl" clip-path="url(#exClipF)">${scan.replace(/<path /g, '<path fill="url(#exScan)" ')}<path class="dt" d="${DETAIL_FRONT}"/><rect class="beam" x="-10" y="-60" width="220" height="60" fill="url(#exBeam)"/></g>
          <g class="pins"></g>
        </g>
        <g class="view back">
          <g transform="matrix(-1 0 0 1 200 0)"><g class="body" filter="url(#exGlow)">${regions('back')}</g></g>
          <g class="scanl" clip-path="url(#exClipB)"><g transform="matrix(-1 0 0 1 200 0)">${scan.replace(/<path /g, '<path fill="url(#exScan)" ')}</g><path class="dt" d="${DETAIL_BACK}"/><rect class="beam" x="-10" y="-60" width="220" height="60" fill="url(#exBeam)"/></g>
          <g class="pins"></g>
        </g>
        <text class="side l" x="-6" y="96"></text><text class="side r" x="206" y="96"></text>
      </svg>`;
      this.holo.querySelectorAll('.rg').forEach(p => {
        p.addEventListener('click', () => this.select(p.dataset.g));
        p.addEventListener('mouseenter', () => { this.hover = p.dataset.g; this.renderHoloState(); this.renderDiamonds(); this.showTip(p.dataset.g); });
        p.addEventListener('mouseleave', () => { this.hover = null; this.renderHoloState(); this.renderDiamonds(); this.showTip(null); });
      });
    },
    flip(face, instant) {
      if (face !== 'front' && face !== 'back') return;
      const changed = face !== this.face;
      this.face = face;
      this.$('.ex-map .seg').querySelectorAll('button').forEach(b => b.classList.toggle('on', b.dataset.v === face));
      const svg = this.holo.querySelector('svg');
      const apply = () => {
        svg.classList.toggle('is-back', face === 'back');
        // patient's right is on the viewer's left when facing us
        svg.querySelector('.side.l').textContent = face === 'front' ? T('side_r_short', 'R') : T('side_l_short', 'L');
        svg.querySelector('.side.r').textContent = face === 'front' ? T('side_l_short', 'L') : T('side_r_short', 'R');
        this.renderPins();
      };
      if (instant || !changed) { apply(); return; }
      this.holo.classList.remove('flipping'); void this.holo.offsetWidth; this.holo.classList.add('flipping');
      NZA.audio.click(520);
      setTimeout(apply, 170);
    },
    renderHoloState() {
      this.holo.querySelectorAll('.rg').forEach(p => {
        const n = p.dataset.g, v = this.gview(n);
        p.setAttribute('class', `rg t-${TONE[v.status] || 'clear'}${n === this.sel ? ' on' : ''}${n === this.hover ? ' hov' : ''}`);
      });
    },
    renderPins() {
      const svg = this.holo.querySelector('svg');
      if (!svg) return;
      ['front', 'back'].forEach(face => {
        const box = svg.querySelector(`.view.${face} .pins`);
        const by = {};
        ORDER.forEach(g => (this.gview(g).injuries || []).forEach(i => {
          const r = i.region || g;
          if (face === 'front' && BACK_ONLY[r]) return;
          if (face === 'back' && FRONT_ONLY[r]) return;
          (by[r] = by[r] || []).push(i);
        }));
        let out = '';
        Object.entries(by).forEach(([r, list]) => {
          const p = PIN[r]; if (!p) return;
          list.forEach((i, k) => {
            let x = p[0] + (k - (list.length - 1) / 2) * 12;
            if (face === 'back') x = 200 - x;
            const tone = i.suspected ? 'sus' : (!ACTIVE(i.status) ? 'teal' : ({ 1: 'white', 2: 'amber', 3: 'red', 4: 'crit' })[i.severity] || 'white');
            out += `<g class="pin t-${tone}" transform="translate(${x.toFixed(1)} ${p[1]})"><rect class="pg" x="-7" y="-7" width="14" height="14" transform="rotate(45)"/><rect class="pd" x="-4" y="-4" width="8" height="8" transform="rotate(45)"/></g>`;
          });
        });
        box.innerHTML = out;
      });
    },
    showTip(name) {
      const t = this.tip;
      if (!name) { t.classList.remove('on'); return; }
      const v = this.gview(name);
      const c = CENTER[name]; if (!c) return;
      const x = this.face === 'back' ? 200 - c[0] : c[0];
      t.style.left = `${((x - VB.x) / VB.w) * 100}%`;
      t.style.top = `${((c[1] - VB.y) / VB.h) * 100}%`;
      const n = this.openCount(v);
      t.className = `htip on t-${TONE[v.status] || 'clear'}${x > 100 ? ' l' : ''}`;
      t.innerHTML = `<b>${esc(this.glabel(name))}</b><span><i></i>${esc(this.gstatus(v))}</span><em>${esc(n ? T('open_n_short', '%d open', n) : T('open_none', 'nothing open'))}${v.pain ? ` · ${esc(T('pain_short', 'pain %d', v.pain))}` : ''}</em>`;
    },

    /* ── render ── */
    renderAll() {
      this.renderPatient();
      this.renderHoloState();
      this.renderPins();
      this.renderLegend();
      this.renderDiamonds();
      this.renderFindings();
      this.renderDock();
    },
    renderPatient() {
      const v = this.view;
      const n = v.toTreat || 0;
      const tri = v.triage ? `<span class="prio p${v.triage.level || 3}">${esc(v.triage.code || '')}${v.triage.label ? ` · ${esc(v.triage.label)}` : ''}</span>` : '';
      const stateTone = v.state === 'wounded' ? 'amber' : (v.state && v.state !== 'alive' ? 'red' : 'teal');
      const rows = (v.general || []).map(r => `<li class="t-${esc(r.tone || 'dim')}"><i class="no"></i>${icon(r.icon || 'info')}<span>${esc(r.text)}</span></li>`).join('');
      const lv = BLEED_LV[v.bleed] ?? 0;
      const bleed = v.bleed ? `<li class="bl t-${BLEED_TONE[lv]}"><i class="no"></i>${icon('drop')}<span>${esc(T('bleeding', 'Bleeding'))}</span><span class="segs">${[1, 2, 3, 4].map(k => `<i class="${k <= lv ? 'on' : ''}"></i>`).join('')}</span><b>${esc(v.bleedLabel || '')}</b></li>` : '';
      const dev = (v.devices || []).map(d => `<span class="dv">${icon('check')}${esc(d)}</span>`).join('');
      // status ring: time left / holding / triage
      let ringHtml;
      if (v.clock !== null && v.clock !== undefined) {
        this.clockMax = Math.max(this.clockMax || 0, v.clock, 60);
        this.clockAt = performance.now(); this.clockVal = v.clock;
        ringHtml = `<div class="pc-ring t-${v.clock < 60 ? 'red' : 'amber'}">${ring(v.clock / this.clockMax, 40, 92)}<div class="in"><span class="odoh"></span><small>${esc(T('bleedout', 'Time left'))}</small></div></div>`;
      } else if (v.stabilized && v.state === 'wounded') {
        this.clockVal = null;
        ringHtml = `<div class="pc-ring t-teal">${ring(1, 40, 92)}<div class="in">${icon('shield-check')}<small>${esc(T('stabilized', 'Holding steady'))}</small></div></div>`;
      } else {
        this.clockVal = null;
        const lvl = v.triage ? v.triage.level || 3 : 0;
        ringHtml = `<div class="pc-ring t-${['teal', 'red', 'amber', 'teal'][lvl] || 'teal'}">${ring(lvl ? (4 - lvl) / 3 : 0, 40, 92)}<div class="in"><b class="tc">${esc(v.triage ? v.triage.code || '' : '--')}</b><small>${esc(T('triage', 'Triage'))}</small></div></div>`;
      }
      this.$('.ex-pt').innerHTML = `
        <div class="pc-top">
          <div class="pc-id">
            <span class="kick">${esc(T('exam_title', 'Head-to-toe check'))}</span>
            <h2>${esc(v.name || this.patient.name || '')}</h2>
            <div class="pc-sub">${tri}<span class="sx t-${stateTone}"><i></i>${esc(v.stateLabel || '')}</span></div>
            <div class="pc-open"><b>${n}</b><span>${esc(n === 1 ? T('to_treat_1', 'open problem') : T('to_treat_n', 'open problems'))}</span></div>
          </div>
          ${ringHtml}
        </div>
        <ul class="pc-obs"><li class="hd">${esc(T('general', 'Observations'))}</li>${bleed}${rows}</ul>
        ${dev ? `<div class="pc-dev">${dev}</div>` : ''}`;
      const host = this.$('.ex-pt .odoh');
      if (host) {
        if (!this.odo) this.odo = NZA.ui.FlipClock(host, { value: NZA.fmt.time(v.clock), small: true });
        else host.appendChild(this.odo.el);
        this.odo.set(NZA.fmt.time(v.clock));
      } else this.odo = null;
    },
    tickClock() {
      if (this.clockVal === null || this.clockVal === undefined || !this.odo) return;
      const left = Math.max(0, this.clockVal - (performance.now() - this.clockAt) / 1000);
      this.odo.set(NZA.fmt.time(left));
      const fg = this.$('.ex-pt .pc-ring .fg');
      if (fg) { const C = 2 * Math.PI * 40; fg.style.strokeDashoffset = (C * (1 - clamp(left / (this.clockMax || 1), 0, 1))).toFixed(2); }
      const r = this.$('.ex-pt .pc-ring');
      if (r) r.classList.toggle('t-red', left < 60);
    },
    renderLegend() {
      const it = (tone, k, fb) => `<span class="t-${tone}"><i></i>${esc(T(k, fb))}</span>`;
      this.$('.ex-map .ml').innerHTML = it('crit', 'gs_critical', 'Severe') + it('red', 'gs_serious', 'Serious') + it('amber', 'gs_minor', 'Minor') + it('teal', 'gs_treated', 'Treated') + it('clear', 'gs_healthy', 'Clear');
    },
    renderKeys() {
      const k = (keys, label) => `<span>${keys.map(x => `<kbd>${esc(x)}</kbd>`).join('')}<em>${esc(label)}</em></span>`;
      this.$('.ex-keys').innerHTML = k(['↑', '↓'], T('regions', 'Region')) + k(['F'], T('map_flip', 'Turn the map')) + k(['Enter'], T('key_start', 'Start care')) + k(['ESC'], T('close', 'Close'));
    },
    renderFindings() {
      const name = this.sel;
      const v = this.gview(name);
      const tone = TONE[v.status] || 'clear';
      const n = this.openCount(v);
      const sev = SEV_RANK[v.status] === 4 ? 4 : SEV_RANK[v.status] === 3 ? 3 : SEV_RANK[v.status] === 2 ? 2 : (v.status === 'treated' ? 4 : 0);
      const notes = (v.notes || []).map(x => `<li class="t-${esc(x.tone || 'dim')}">${esc(x.text)}</li>`).join('');
      const list = v.injuries || [];
      if (!this.expanded || (this.expanded !== '__none' && !list.some(i => i.id === this.expanded))) this.expanded = list.length ? list[0].id : null;
      const inj = list.map(i => this.injuryHTML(i, i.id === this.expanded)).join('');
      const empty = !list.length ? `<div class="fd-empty">${sevRing(0, v.status === 'treated' ? 'teal' : 'clear', v.status === 'treated' ? 'check' : 'shield-check')}<div><b>${esc(v.status === 'treated' ? T('empty_treated', 'All cared for') : T('empty_title', 'All clear here'))}</b><span>${esc(v.status === 'treated' ? T('empty_treated_sub', 'Every problem in this region has been handled.') : T('empty_sub', 'Nothing wrong in this region. Pick another one on the map.'))}</span></div></div>` : '';
      const pain = Math.round(v.pain || 0);
      this.$('.ex-find').innerHTML = `
        <header class="fd-head">
          ${sevRing(sev, tone, 'as-diamond', 'lg')}
          <div class="fd-t"><span class="kick">${esc(T('card_title', 'Findings'))}</span><h3>${esc(this.glabel(name))}</h3>
            <div class="fd-st"><span class="sx t-${tone}"><i></i>${esc(this.gstatus(v))}</span><span class="cnt">${esc(n ? T('open_n_short', '%d open', n) : T('open_none', 'nothing open'))}</span></div></div>
          <div class="fd-pain t-${pain >= 70 ? 'red' : pain >= 40 ? 'amber' : 'dim'}">${ring(pain / 100, 15, 36)}<b>${pain}</b><small>${esc(T('pain', 'Pain'))}</small></div>
        </header>
        ${notes ? `<ul class="fd-notes">${notes}</ul>` : ''}
        <div class="fd-stack nza-scroll">${inj}${empty}</div>`;
      const fd = this.$('.ex-find');
      fd.classList.remove('swap'); void fd.offsetWidth; fd.classList.add('swap');
    },
    injuryHTML(i, open) {
      const active = ACTIVE(i.status);
      const tone = i.suspected ? 'sus' : (!active ? 'teal' : ({ 1: 'white', 2: 'amber', 3: 'red', 4: 'crit' })[i.severity] || 'white');
      const finds = (i.findings || []).map(f => `<li class="t-${esc(f.tone || 'base')}"><i class="no"></i><span>${esc(f.text)}</span></li>`).join('');
      const done = (i.done || []).map(d => `<span class="dn">${icon('check')}${esc(d)}</span>`).join('');
      const routes = i.routes || [];
      const main = routes[0];
      let care = '';
      if (main) {
        const items = (main.items || []).map(it => `<li class="${it.ok ? 'ok' : 'no'}"><i class="no"></i><span>${esc(it.label)}</span><em>${esc(T('have_n', '%d on you', it.have))}</em><b>×${it.need}</b></li>`).join('');
        care = `<div class="ij-care">
          <div class="ck"><span>${esc(T('next_care', 'Next care step'))}</span></div>
          ${items ? `<ul class="sup"><li class="hd"><span>${esc(T('supplies', 'Supplies'))}</span><em>${esc(T('carried', 'Carried'))}</em><b>${esc(T('uses', 'Uses'))}</b></li>${items}</ul>` : ''}
          ${main.reason ? `<div class="why">${icon('alert')}<span>${esc(main.reason)}</span></div>` : ''}
          <button class="ij-go" data-inj="${esc(i.id)}" data-route="${esc(main.id)}" ${main.ok ? '' : 'disabled'}><span class="gi">${icon(main.icon || 'medkit')}</span><span class="gl">${esc(main.label)}</span>${main.ok ? '<kbd>Enter</kbd>' : icon('lock')}</button>
          ${routes.length > 1 ? `<div class="alts"><span class="al">${esc(T('alt_care', 'Or instead'))}</span>${routes.slice(1).map(r => `<button class="ij-alt" data-inj="${esc(i.id)}" data-route="${esc(r.id)}" ${r.ok ? '' : 'disabled'}>${icon(r.icon || 'chev-r')}<span>${esc(r.label)}</span>${r.reason ? `<em>${esc(r.reason)}</em>` : icon('chev-r')}</button>`).join('')}</div>` : ''}
        </div>`;
      } else if (active) {
        care = `<div class="ij-care none">${icon('info')}<span>${esc(T('no_route', 'Nothing you can do for this here'))}</span></div>`;
      }
      const heal = (i.status === 'treated' || i.status === 'healing') ? `<div class="ij-heal"><span>${esc(T('healing', 'Healing'))}</span><div class="bar"><i style="width:${Math.max(4, i.heal || 0)}%"></i></div><b>${Math.round(i.heal || 0)}%</b></div>` : '';
      const ready = main && main.ok;
      return `<article class="ij t-${tone}${open ? ' open' : ''}${i.suspected ? ' sus' : ''}${!active ? ' done' : ''}">
        <button class="ij-h" data-id="${esc(i.id)}">
          ${sevRing(i.suspected ? 2 : (i.severity || 1), tone, i.icon || 'drop', i.suspected ? 'dash' : '')}
          <span class="tt"><b>${esc(i.typeLabel)}</b><small>${esc(i.regionLabel || '')}${i.statusLabel ? ` · ${esc(i.statusLabel)}` : ''}</small></span>
          <span class="sv">${esc(i.sevLabel || '')}</span>
          ${ready && !open ? `<span class="rd" title="${esc(main.label)}">${icon('play')}</span>` : ''}
          <span class="cv">${icon('chev-d')}</span>
        </button>
        <div class="ij-b">
          ${finds ? `<ul class="ij-f">${finds}</ul>` : ''}
          ${done ? `<div class="ij-done">${done}</div>` : ''}
          ${heal}${care}
        </div>
      </article>`;
    },
    renderDock() {
      const v = this.view;
      const ck = v.checks || {};
      const item = (act, ic, label, sub, key, cls, ok, tip, fill) => `<button class="dk ${cls}${ok ? '' : ' off'}" data-act="${act}">
          <span class="rr">${ring(fill, 25, 58)}<span class="ic">${icon(ic)}</span><kbd>${key}</kbd></span>
          <b>${esc(label)}</b><small>${esc(sub)}</small><span class="tp">${esc(tip)}</span></button>`;
      const p = ck.pulse, b = ck.breathing;
      const lv = BLEED_LV[v.bleed] ?? 0;
      this.$('.ex-dock').innerHTML = `<span class="dh">${esc(T('dock_title', 'Checks'))}</span>` +
        item('pulse', 'pulse', T('btn_pulse', 'Pulse'), p && p.rate !== undefined ? `${p.rate} ${T('bpm', 'bpm')}` : T('not_checked', 'not checked'), '1', p ? 'has' : '', this.perms.pulse !== false, T('tip_pulse', 'Feel for a pulse'), p ? 1 : 0) +
        item('breathing', 'lungs', T('btn_breathing', 'Breathing'), b && b.rate !== undefined ? `${b.rate} ${T('per_min', '/min')}` : T('not_checked', 'not checked'), '2', b ? 'has' : '', this.perms.breathing !== false, T('tip_breathing', 'Listen to the lungs'), b ? 1 : 0) +
        '<span class="dsep"></span>' +
        item('stopbleed', 'drop', T('btn_stop', 'Bleed control'), v.bleedLabel || '', '3', `red lv${lv}`, !!v.canStop, v.canStop ? T('tip_stop', 'Control the worst bleed') : T('no_bleeding_short', 'Nothing to control'), lv / 4);
    },

    /* ── browser preview ── */
    preview() {
      const body = NZAAssess.body({ focus: 'full', wounds: ['chest', 'thigh_l', 'head'] });
      const route = (id, label, ic, items, ok = true, reason = null) => ({ id, label, icon: ic, ok, avail: ok, reason, items });
      const view = {
        name: 'Tomas Reyna', state: 'wounded', stateLabel: 'Wounded', triage: { level: 1, code: 'P1', label: 'Immediate' },
        bleed: 'heavy', bleedLabel: 'Heavy', toTreat: 4, clock: 134, stabilized: false, canStop: true,
        devices: ['IV line', 'Oxygen'],
        checks: { pulse: { rate: 124, ago: '1 min ago' } },
        general: [
          { icon: 'brain', text: 'Opens eyes when spoken to', tone: 'amber' },
          { icon: 'drop', text: 'Pale and clammy', tone: 'amber' },
          { icon: 'pulse', text: 'Pulse 124 · wrist · weak · 1 min ago', tone: 'teal' },
        ],
        groups: {
          head: { status: 'minor', statusLabel: 'Minor', pain: 30, notes: [{ text: 'Dazed, repeats the same question', tone: 'amber' }], injuries: [
            { id: 'i3', region: 'face', regionLabel: 'Face', type: 'abrasion', typeLabel: 'Abrasion', icon: 'scrape', severity: 1, sevLabel: 'Minor', status: 'open', statusLabel: 'Open',
              findings: [{ text: 'Oozing', tone: 'dim' }, { text: 'Grit in the skin', tone: '' }], done: [], routes: [route('clean', 'Clean & dress', 'gauze', [{ label: 'Saline', have: 3, need: 1, ok: true }, { label: 'Sterile dressing', have: 6, need: 1, ok: true }])] }] },
          neck: { status: 'healthy', statusLabel: 'Clear', injuries: [], notes: [] },
          chest: { status: 'critical', statusLabel: 'Severe', pain: 80, notes: [], injuries: [
            { id: 'i1', region: 'chest', regionLabel: 'Chest', type: 'laceration', typeLabel: 'Deep laceration', icon: 'cut', severity: 4, sevLabel: 'Severe', status: 'open', statusLabel: 'Open',
              findings: [{ text: 'Fast, heavy bleeding', tone: 'red' }, { text: '84 mm long, deep', tone: '' }, { text: 'Dirt and debris in the wound', tone: 'amber' }],
              done: [], routes: [route('suture', 'Close with sutures', 'needle', [{ label: 'Bandage', have: 8, need: 1, ok: true }, { label: 'Suture kit', have: 2, need: 1, ok: true }]), route('stopbleed', 'Pack & wrap', 'gauze', [], true)] },
            { id: 'c:haemothorax_suspected_right', region: 'chest', regionLabel: 'Chest', type: 'haemothorax', typeLabel: 'Haemothorax · right', icon: 'lungs', suspected: true, severity: 3, sevLabel: 'Suspected', status: 'open', statusLabel: 'Suspected',
              findings: [{ text: 'Quiet breath sounds on the right', tone: 'amber' }, { text: 'Breathing check · 1 min ago', tone: 'dim' }],
              done: [], routes: [route('chestdrain', 'Chest drain', 'tube', [{ label: 'Chest drain kit', have: 0, need: 1, ok: false }], false, 'You are missing supplies')] }] },
          abdomen: { status: 'minor', statusLabel: 'Minor', pain: 35, notes: [{ text: 'Belly hard and tender', tone: 'amber' }], injuries: [] },
          l_arm: { status: 'healthy', statusLabel: 'Clear', injuries: [], notes: [] },
          r_arm: { status: 'treated', statusLabel: 'Treated', injuries: [
            { id: 'i5', region: 'r_lower_arm', regionLabel: 'Right forearm', type: 'laceration', typeLabel: 'Deep laceration', icon: 'cut', severity: 2, sevLabel: 'Moderate', status: 'healing', statusLabel: 'Healing', heal: 46,
              findings: [{ text: 'Not bleeding', tone: 'dim' }], done: ['Irrigated', 'Sutured', 'Dressed'], routes: [] }], notes: [] },
          l_leg: { status: 'serious', statusLabel: 'Serious', pain: 65, injuries: [
            { id: 'i2', region: 'l_upper_leg', regionLabel: 'Left thigh', type: 'gunshot', typeLabel: 'Gunshot wound', icon: 'crosshair', severity: 3, sevLabel: 'Serious', status: 'controlled', statusLabel: 'Controlled',
              findings: [{ text: 'Bleeding held', tone: 'teal' }, { text: 'No exit hole: the round is likely still inside', tone: 'amber' }, { text: 'Tourniquet on for 12 min', tone: 'teal' }],
              done: ['Tourniquet'], routes: [route('bullet', 'Remove the round', 'forceps', [{ label: 'Surgical kit', have: 1, need: 1, ok: true }], false, 'Needs an operating room')] }], notes: [] },
          r_leg: { status: 'healthy', statusLabel: 'Clear', injuries: [], notes: [] },
        },
      };
      NZA.demo('exam', { patient: { name: 'Tomas Reyna', sex: 'm', npc: true }, view, locale: {} });
      NZAAssess.feed('exam', [...ORDER, 'center'], body);
      NZA.mock('exam:treat', () => { NZA.toast({ title: 'Care step', message: 'In game this starts the procedure.', type: 'info' }); return { ok: true }; });
      NZA.mock('exam:action', d => { NZA.toast({ title: 'Head-to-toe check', message: `In game this starts: ${d.action}`, type: 'info' }); return { ok: true }; });
      NZA.mock('exam:touch', d => { const lines = { chest: 'Argh... my chest, it burns.', l_leg: 'Not the leg, please!', head: 'Easy... my head is spinning.' }; if (lines[d.group]) NZA.speech({ name: 'Tomas Reyna', text: lines[d.group], ms: 3800 }); return { ok: true }; });
      setTimeout(() => NZA.speech({ name: 'Tomas Reyna', text: 'Argh... my chest, it burns.', ms: 60000 }), 300);
    },
  });
})();
