/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · Head-to-toe check (app 'exam')    module: assess
   Layout (NAYZEEE HUD language):
     top-left     patient card: name, triage, state, open problems, time-left status ring
                  with a rolling counter, observation list (tone notches), devices
     left         "What to do" card: whole-body needs (CPR, oxygen, fluids, hospital ...) with
                  Start buttons and the supplies they take; 'More tools' drawer (every other option)
     centre       ALL 8 body groups: a diamond on the body + a label (name · status) laid out
                  in two columns beside the body with leader lines, so no label hides another
                  whatever the pose; groups with nothing wrong read Healthy
     right        findings stack for the selected group: severity rings, what to do here,
                  accordion of problems with findings and what to do (treatment buttons with
                  the supplies as chips)
     right edge   check dock: Pulse / Breathing / Bleed control (status rings, key badges)
     bottom-left  key legend chips
   Lua → JS   open { locale, groups, view, patient, perms }   view (live)   anchors (stream)
   JS → Lua   exam:touch { group }   exam:treat { id, route }   exam:step { index, code, inj }
              exam:tool { name }   exam:action { action, group }   exam:close (ESC)
   Keys: ↑/↓ or Tab region · Enter start what to do (selected group first, then the whole
         body) · 1 pulse · 2 breathing · 3 bleed control · ESC close

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
  NZAAssess.body = function body({ focus = 'full', shirtless = false, wounds = [], pose = null } = {}) {
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
    // pose = { rot, k, cx, cy } (preview only): any lying angle / zoom, for layout checks
    g.setAttribute('transform', pose ? tf(130, 300, pose.rot || 0, pose.k || 0.92, pose.cx || 170, pose.cy || 330) : (F[focus] || F.full));
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
  const GS_FB = { healthy: 'Healthy', minor: 'Minor', serious: 'Serious', critical: 'Severe', treated: 'Treated' };
  const SEV_RANK = { critical: 4, serious: 3, minor: 2, treated: 1, healthy: 0 };
  const BLEED_LV = { none: 0, light: 1, moderate: 2, heavy: 3, massive: 4 };
  const BLEED_TONE = ['teal', 'amber', 'amber', 'red', 'red'];
  const ACTIVE = s => s === 'open' || s === 'controlled' || s === undefined || s === null;
  // body labels: the side a group on the body's centre line takes, and where a group is drawn
  // (px at 1080p from the body centre, head up) while its bone is not on screen
  const PREF = { head: 'L', neck: 'R', chest: 'L', abdomen: 'R', r_arm: 'L', r_leg: 'L', l_arm: 'R', l_leg: 'R' };
  const FALLBACK = { head: [0, -330], neck: [0, -262], chest: [0, -190], abdomen: [0, -90], r_arm: [-125, -130], l_arm: [125, -130], r_leg: [-55, 190], l_leg: [55, 190] };
  const SVGNS = 'http://www.w3.org/2000/svg';

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
  // supplies a treatment takes: item · ×uses · how many you carry (red when short)
  // Lua sends an empty table as [] or {}: only real arrays are lists
  const arr = x => (Array.isArray(x) ? x : []);
  const chips = items => arr(items).map(it => `<span class="ic ${it.ok ? 'ok' : 'short'}"><i></i><span>${esc(it.label)}</span><b>×${esc(String(it.need))}</b><em>${esc(T('have_n', '%d on you', it.have))}</em></span>`).join('');
  const stepAttrs = r => `data-step="${esc(String(r.idx))}" data-code="${esc(r.code || '')}"${r.inj ? ` data-inj="${esc(r.inj)}"` : ''}`;

  // Labels of one side, sorted by the y they want: overlapping ones merge into a cluster that is
  // centred on what its members want, then clusters are kept inside [minY, maxY].
  function packY(items, minY, maxY, gap) {
    const height = c => c.items.reduce((s, it) => s + it.h, 0) + gap * (c.items.length - 1);
    const place = c => { const want = c.items.reduce((s, it) => s + it.y, 0) / c.items.length; c.H = height(c); c.top = want - c.H / 2; };
    const clusters = items.map(it => { const c = { items: [it] }; place(c); return c; });
    for (let merged = true; merged;) {
      merged = false;
      for (let i = 0; i + 1 < clusters.length; i++) {
        const a = clusters[i], b = clusters[i + 1];
        if (a.top + a.H + gap > b.top) { a.items.push(...b.items); place(a); clusters.splice(i + 1, 1); merged = true; break; }
      }
    }
    let floor = minY;
    clusters.forEach(c => { c.top = Math.max(c.top, floor); floor = c.top + c.H + gap; });
    let ceil = maxY;
    for (let i = clusters.length - 1; i >= 0; i--) { const c = clusters[i]; c.top = Math.min(c.top, ceil - c.H); ceil = c.top - gap; }
    clusters.forEach(c => { let y = c.top; c.items.forEach(it => { it.cy = y + it.h / 2; y += it.h + gap; }); });
  }

  NZA.app('exam', {
    init(el) {
      this.el = el;
      el.innerHTML = `
        <div class="ex-vig"></div>
        <svg class="ex-links" aria-hidden="true" preserveAspectRatio="none"></svg>
        <div class="ex-marks"></div>
        <aside class="ex-colL">
          <section class="ex-pt nza-hud solid nza-int"></section>
          <section class="ex-todo nza-hud solid nza-int"></section>
        </aside>
        <aside class="ex-colR"><section class="ex-find nza-hud solid nza-int"></section></aside>
        <nav class="ex-dock nza-int"></nav>
        <div class="ex-keys"></div>`;
      this.$ = s => el.querySelector(s);
      this.marks = this.$('.ex-marks');
      this.links = this.$('.ex-links');
      this.diamonds = {}; this.labels = {}; this.paths = {}; this.chipW = {};
      this.anc = NZA.ui.Anchors('exam');
      this.anc.on(() => this.layout());
      window.addEventListener('resize', () => { if (NZA.isOpen('exam')) { this.measure(); this.layout(); } });
      this.$('.ex-find').addEventListener('click', e => this.onFindClick(e));
      this.$('.ex-todo').addEventListener('click', e => this.onTodoClick(e));
      this.$('.ex-dock').addEventListener('click', e => { const b = e.target.closest('button[data-act]'); if (b && !b.classList.contains('off')) this.action(b.dataset.act); });
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
      this.sides = {};
      this.ghost = {};
      this.toolsOpen = false;
      this.marks.innerHTML = '';
      this.links.innerHTML = '';
      this.diamonds = {}; this.labels = {}; this.paths = {};
      this.groups.forEach(g => this.makeMark(g));
      this.renderKeys();
      this.renderAll();
      this.layout();
      clearInterval(this.tick);
      this.tick = setInterval(() => this.tickClock(), 250);
      this.el.classList.remove('ex-in'); void this.el.offsetWidth; this.el.classList.add('ex-in');
    },
    close() { clearInterval(this.tick); this.marks.innerHTML = ''; this.links.innerHTML = ''; this.diamonds = {}; this.labels = {}; this.paths = {}; this.odo = null; },

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
      Enter() { NZA.apps.exam.startFirst(); },
      Digit1() { NZA.apps.exam.action('pulse'); },
      Digit2() { NZA.apps.exam.action('breathing'); },
      Digit3() { NZA.apps.exam.action('stopbleed'); },
    },

    /* ── helpers ── */
    gview(name) { return (this.view.groups || {})[name] || { status: 'healthy', injuries: [], notes: [], todo: [] }; },
    glabel(name) { const g = (this.groups || []).find(x => x.name === name); return g ? g.label : T(`group_${name}`, GROUP_FB[name] || name); },
    gstatus(v) { return v.statusLabel || T(`gs_${v.status}`, GS_FB[v.status] || v.status); },
    openCount(v) { return arr(v.injuries).filter(i => ACTIVE(i.status) || i.suspected).length + arr(v.todo).length; },
    pickWorst() {
      let best = 'chest', rank = -1;
      ORDER.forEach(n => { const g = (this.view.groups || {})[n]; const r = g ? (SEV_RANK[g.status] ?? 0) * 10 + arr(g.injuries).length + arr(g.todo).length : 0; if (r > rank) { rank = r; best = n; } });
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
    // Enter: what to do here (the group, then its open wound), else the next whole-body need
    startFirst() {
      const g = this.gview(this.sel);
      const row = arr(g.todo).find(r => r.can);
      if (row) return this.startStep(row);
      const list = arr(g.injuries);
      const first = list.find(i => i.id === this.expanded) || null;
      const ordered = first ? [first, ...list.filter(i => i !== first)] : list;
      for (const inj of ordered) {
        const steps = arr(inj.steps);
        const lead = steps.find(x => x.can && !x.onCard);
        const r = arr(inj.routes).find(x => x.ok);
        if (lead && !(steps[0] && steps[0].onCard)) return this.startStep(lead);
        if (r) return this.treat(inj.id, r.id);
        if (lead) return this.startStep(lead);
      }
      const todo = arr(this.view.todo);
      const gen = todo.find(r => r.can && r.where !== 'hospital') || todo.find(r => r.can);
      if (gen) return this.startStep(gen);
      NZA.audio.fail();
    },
    async startStep(r) {
      NZA.audio.click(990);
      const res = await NZA.post('exam:step', { index: Number(r.idx), code: r.code, inj: r.inj || undefined });
      if (res && res.ok === false) NZA.audio.fail();
    },
    stepFromButton(b) { return { idx: Number(b.dataset.step), code: b.dataset.code || undefined, inj: b.dataset.inj || undefined }; },
    async treat(id, route) {
      NZA.audio.click(990);
      const res = await NZA.post('exam:treat', { id, route });
      if (res && res.ok === false) NZA.audio.fail();
    },
    async tool(name) {
      NZA.audio.click(880);
      await NZA.post('exam:tool', { name });
    },
    onFindClick(e) {
      const st = e.target.closest('button[data-step]');
      if (st) { if (!st.disabled) this.startStep(this.stepFromButton(st)); return; }
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
    onTodoClick(e) {
      const st = e.target.closest('button[data-step]');
      if (st) { if (!st.disabled) this.startStep(this.stepFromButton(st)); return; }
      const tl = e.target.closest('button[data-tool]');
      if (tl) { this.tool(tl.dataset.tool); return; }
      if (e.target.closest('[data-toggle="tools"]')) {
        this.toolsOpen = !this.toolsOpen;
        const box = this.$('.ex-todo .tl');
        if (box) box.classList.toggle('open', this.toolsOpen);
        NZA.audio.click(640);
      }
    },

    /* ── body: a diamond on every group + its label beside the body ── */
    makeMark(g) {
      const d = document.createElement('button');
      d.className = 'exm nza-int';
      d.dataset.g = g.name;
      d.innerHTML = '<span class="dm"><i></i></span><span class="halo"></span>';
      const l = document.createElement('button');
      l.className = 'exl nza-int';
      l.dataset.g = g.name;
      l.innerHTML = '<i class="bar"></i><b></b><em></em>';
      [d, l].forEach(x => {
        x.addEventListener('click', () => this.select(g.name));
        x.addEventListener('mouseenter', () => { this.hover = g.name; this.renderDiamonds(); });
        x.addEventListener('mouseleave', () => { this.hover = null; this.renderDiamonds(); });
      });
      const p = document.createElementNS(SVGNS, 'path');
      this.links.appendChild(p);
      this.marks.appendChild(d);
      this.marks.appendChild(l);
      this.diamonds[g.name] = d; this.labels[g.name] = l; this.paths[g.name] = p;
    },
    renderDiamonds() {
      Object.keys(this.diamonds).forEach(name => {
        const v = this.gview(name);
        const tone = TONE[v.status] || 'clear';
        const st = `t-${tone}${name === this.sel ? ' on' : ''}${name === this.hover ? ' hov' : ''}`;
        this.diamonds[name].className = `exm nza-int ${st}${this.ghost[name] ? ' gh' : ''}`;
        const l = this.labels[name];
        l.className = `exl nza-int ${st} s-${this.sides[name] || PREF[name] || 'R'}`;
        l.querySelector('b').textContent = this.glabel(name);
        const n = this.openCount(v);
        l.querySelector('em').textContent = n ? T('open_n_short', '%d open', n) : this.gstatus(v);
        this.paths[name].setAttribute('class', `lk ${st}`);
      });
      this.measure();
    },
    measure() {
      Object.entries(this.labels).forEach(([n, l]) => { const w = l.offsetWidth; if (w) this.chipW[n] = w; });
      const any = Object.values(this.labels)[0];
      if (any && any.offsetHeight) this.chipH = any.offsetHeight;
    },
    layout() {
      const W = this.el.clientWidth, H = this.el.clientHeight;
      if (!W || !H || !this.labels.head) return;
      const map = this.anc.all() || {};
      const usable = a => a && a.visible !== false && a.x >= -0.01 && a.x <= 1.01 && a.y >= -0.01 && a.y <= 1.01;
      const pts = {};
      let sx = 0, sy = 0, k = 0;
      ORDER.forEach(n => {
        const a = map[n];
        if (usable(a)) { pts[n] = { x: clamp(a.x * W, 8, W - 8), y: clamp(a.y * H, 8, H - 8) }; sx += pts[n].x; sy += pts[n].y; k++; }
      });
      const c = usable(map.center) ? { x: map.center.x * W, y: map.center.y * H } : (k ? { x: sx / k, y: sy / k } : { x: W / 2, y: H / 2 });
      // a bone that is not on screen (or not tracked yet) still gets its diamond and label
      const sc = H / 1080;
      const ghost = {};
      ORDER.forEach(n => {
        if (!pts[n]) { const f = FALLBACK[n]; pts[n] = { x: clamp(c.x + f[0] * sc, 8, W - 8), y: clamp(c.y + f[1] * sc, 8, H - 8) }; ghost[n] = true; }
      });
      this.ghost = ghost;
      // labels live between the side panels, above the key legend
      const colL = this.$('.ex-colL'), colR = this.$('.ex-colR');
      const safeL = (colL ? colL.offsetLeft + colL.offsetWidth : 380) + 16;
      const safeR = (colR ? colR.offsetLeft : W - 520) - 16;
      const top = 22, bottom = H - 72;
      // side per group, with some hysteresis so a breathing body never flips a label (a side
      // picked from a stand-in position is not kept: the real bone decides once it shows)
      const sides = {};
      ORDER.forEach(n => {
        const dx = pts[n].x - c.x;
        let side = ghost[n] ? null : this.sides[n];
        if (!side || (side === 'L' && dx > 70) || (side === 'R' && dx < -70)) side = dx < -24 ? 'L' : (dx > 24 ? 'R' : PREF[n]);
        sides[n] = side;
        if (ghost[n]) delete this.sides[n]; else this.sides[n] = side;
      });
      const h = this.chipH || 30, gap = 34;
      ['L', 'R'].forEach(side => {
        const names = ORDER.filter(n => sides[n] === side);
        if (!names.length) return;
        const wMax = Math.max(...names.map(n => this.chipW[n] || 110));
        // the column edge facing the body: just outside the outermost diamond of that side
        let edge = side === 'L' ? Math.min(...names.map(n => pts[n].x)) - gap : Math.max(...names.map(n => pts[n].x)) + gap;
        edge = side === 'L' ? clamp(edge, safeL + wMax, Math.max(safeL + wMax, safeR - 60)) : clamp(edge, Math.min(safeR - wMax, safeL + 60), safeR - wMax);
        const items = names.map(n => ({ n, y: pts[n].y, h })).sort((a, b) => a.y - b.y);
        packY(items, top, bottom, 6);
        items.forEach(it => {
          const w = this.chipW[it.n] || 110;
          const x = side === 'L' ? edge - w : edge;
          const lab = this.labels[it.n];
          lab.style.transform = `translate(${x.toFixed(1)}px, ${(it.cy - h / 2).toFixed(1)}px)`;
          lab.classList.toggle('s-L', side === 'L');
          lab.classList.toggle('s-R', side === 'R');
          const p = pts[it.n];
          const elbow = side === 'L' ? edge + 12 : edge - 12;
          this.paths[it.n].setAttribute('d', `M${p.x.toFixed(1)} ${p.y.toFixed(1)}L${elbow.toFixed(1)} ${it.cy.toFixed(1)}L${edge.toFixed(1)} ${it.cy.toFixed(1)}`);
        });
      });
      ORDER.forEach(n => {
        const d = this.diamonds[n];
        if (!d) return;
        d.style.transform = `translate(${pts[n].x.toFixed(1)}px, ${pts[n].y.toFixed(1)}px)`;
        d.classList.toggle('gh', !!ghost[n]);
      });
      this.links.setAttribute('viewBox', `0 0 ${W} ${H}`);
    },

    /* ── render ── */
    renderAll() {
      this.renderPatient();
      this.renderTodo();
      this.renderDiamonds();
      this.renderFindings();
      this.renderDock();
    },
    // one 'what to do' row: the need, why, what would run (+ supplies) and Start - or why not here
    rowHTML(r) {
      const cls = ['cr', r.urgent ? 'urgent' : '', r.where === 'hospital' ? 'hosp' : '', r.can ? 'can' : 'off'].filter(Boolean).join(' ');
      const items = arr(r.items);
      const named = r.label && r.label !== r.title && !(items.length === 1 && items[0].label === r.label);
      const act = ((named || items.length) && (r.can || items.length))
        ? `<span class="ac">${named ? `${icon('chev-r')}<span class="al">${esc(r.label)}</span>` : ''}${chips(r.items)}</span>` : '';
      const why = (!r.can && r.reason) ? `<span class="wn${r.where === 'hospital' ? ' hp' : ''}">${icon(r.where === 'hospital' ? 'hospital' : 'lock')}<span>${esc(r.reason)}</span></span>` : '';
      const btn = r.can ? `<button class="go" ${stepAttrs(r)}>${esc(T('start', 'Start'))}</button>`
        : (r.where === 'hospital' ? `<span class="tag hp">${icon('hospital')}${esc(T('at_hospital', 'Hospital'))}</span>` : `<span class="tag lk">${icon('lock')}</span>`);
      return `<li class="${cls}"><span class="nd">${icon(r.icon || 'medkit')}</span><span class="tx"><b>${esc(r.title || '')}</b>${r.why ? `<small>${esc(r.why)}</small>` : ''}${act}${why}</span>${btn}</li>`;
    },
    renderTodo() {
      const box = this.$('.ex-todo');
      const rows = arr(this.view.todo);
      const tools = arr(this.view.tools);
      const anyBody = ORDER.some(n => this.openCount(this.gview(n)) > 0);
      const body = rows.length
        ? `<ol class="cl nza-scroll">${rows.map(r => this.rowHTML(r)).join('')}</ol>`
        : `<div class="cdone${anyBody ? ' part' : ''}">${icon(anyBody ? 'arrow-r' : 'check')}<span>${esc(anyBody ? T('todo_parts', 'Nothing for the whole body. What to do is on each body part.') : T('todo_all_done', 'Nothing left to do. Help them up or let them go.'))}</span></div>`;
      const toolsHTML = tools.length ? `<div class="tl${this.toolsOpen ? ' open' : ''}">
          <button class="tl-h" data-toggle="tools">${icon('wrench')}<span>${esc(T('tools', 'More tools'))}</span><em>${tools.length}</em>${icon('chev-d')}</button>
          <div class="tl-b">${tools.map(t => `<button class="tl-i" data-tool="${esc(t.name)}">${icon(t.icon || 'medkit')}<span>${esc(t.label || t.name)}</span></button>`).join('')}</div>
        </div>` : '';
      box.innerHTML = `
        <header class="ch"><span class="kick">${icon('clipboard')}<span>${esc(T('todo_title', 'What to do'))}</span></span><span class="cnt">${esc(T('todo_whole', 'whole body'))}</span></header>
        ${body}${toolsHTML}`;
    },
    renderPatient() {
      const v = this.view;
      const n = v.toTreat || 0;
      const tri = v.triage ? `<span class="prio p${v.triage.level || 3}">${esc(v.triage.code || '')}${v.triage.label ? ` · ${esc(v.triage.label)}` : ''}</span>` : '';
      const stateTone = v.state === 'wounded' ? 'amber' : (v.state && v.state !== 'alive' ? 'red' : 'teal');
      const rows = arr(v.general).map(r => `<li class="t-${esc(r.tone || 'dim')}"><i class="no"></i>${icon(r.icon || 'info')}<span>${esc(r.text)}</span></li>`).join('');
      const lv = BLEED_LV[v.bleed] ?? 0;
      const bleed = v.bleed ? `<li class="bl t-${BLEED_TONE[lv]}"><i class="no"></i>${icon('drop')}<span>${esc(T('bleeding', 'Bleeding'))}</span><span class="segs">${[1, 2, 3, 4].map(k => `<i class="${k <= lv ? 'on' : ''}"></i>`).join('')}</span><b>${esc(v.bleedLabel || '')}</b></li>` : '';
      const dev = arr(v.devices).map(d => `<span class="dv">${icon('check')}${esc(d)}</span>`).join('');
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
    renderKeys() {
      const k = (keys, label) => `<span>${keys.map(x => `<kbd>${esc(x)}</kbd>`).join('')}<em>${esc(label)}</em></span>`;
      this.$('.ex-keys').innerHTML = k(['↑', '↓'], T('regions', 'Region')) + k(['Enter'], T('key_start_next', 'Start what to do')) + k(['ESC'], T('close', 'Close'));
    },
    renderFindings() {
      const name = this.sel;
      const v = this.gview(name);
      const tone = TONE[v.status] || 'clear';
      const n = this.openCount(v);
      const sev = SEV_RANK[v.status] === 4 ? 4 : SEV_RANK[v.status] === 3 ? 3 : SEV_RANK[v.status] === 2 ? 2 : (v.status === 'treated' ? 4 : 0);
      const notes = arr(v.notes).map(x => `<li class="t-${esc(x.tone || 'dim')}">${esc(x.text)}</li>`).join('');
      const list = arr(v.injuries);
      const todo = arr(v.todo);
      if (!this.expanded || (this.expanded !== '__none' && !list.some(i => i.id === this.expanded))) this.expanded = list.length ? list[0].id : null;
      const here = todo.length ? `<div class="fd-todo"><div class="ck"><span>${esc(T('what_here', 'What to do here'))}</span></div><ol class="cl">${todo.map(r => this.rowHTML(r)).join('')}</ol></div>` : '';
      const inj = list.map(i => this.injuryHTML(i, i.id === this.expanded)).join('');
      const treated = v.status === 'treated';
      const healthy = v.status === 'healthy';
      // signs without a wound (a hard belly, a dazed look): nothing to treat here, but not healthy either
      const emptyT = treated ? [T('empty_treated', 'All cared for'), T('empty_treated_sub', 'Every problem in this region has been handled.')]
        : healthy ? [T('empty_title', 'Healthy'), T('empty_sub', 'Nothing wrong here. Pick another body part.')]
          : [T('empty_watch', 'Nothing to treat here yet'), T('empty_watch_sub', 'Keep an eye on the signs above.')];
      const empty = (!list.length && !todo.length) ? `<div class="fd-empty${healthy ? ' ok' : ''}">${sevRing(0, treated ? 'teal' : (healthy ? 'clear' : 'amber'), treated ? 'check' : (healthy ? 'shield-check' : 'eye'))}<div><b>${esc(emptyT[0])}</b><span>${esc(emptyT[1])}</span></div></div>` : '';
      const pain = Math.round(v.pain || 0);
      this.$('.ex-find').innerHTML = `
        <header class="fd-head">
          ${sevRing(sev, tone, 'as-diamond', 'lg')}
          <div class="fd-t"><span class="kick">${esc(T('card_title', 'Findings'))}</span><h3>${esc(this.glabel(name))}</h3>
            <div class="fd-st"><span class="sx t-${tone}"><i></i>${esc(this.gstatus(v))}</span><span class="cnt">${esc(n ? T('open_n_short', '%d open', n) : T('open_none', 'nothing open'))}</span></div></div>
          <div class="fd-pain t-${pain >= 70 ? 'red' : pain >= 40 ? 'amber' : 'dim'}">${ring(pain / 100, 15, 36)}<b>${pain}</b><small>${esc(T('pain', 'Pain'))}</small></div>
        </header>
        ${notes ? `<ul class="fd-notes">${notes}</ul>` : ''}
        <div class="fd-stack nza-scroll">${here}${inj}${empty}</div>`;
      const fd = this.$('.ex-find');
      fd.classList.remove('swap'); void fd.offsetWidth; fd.classList.add('swap');
    },
    injuryHTML(i, open) {
      const active = ACTIVE(i.status);
      const tone = i.suspected ? 'sus' : (!active ? 'teal' : ({ 1: 'white', 2: 'amber', 3: 'red', 4: 'crit' })[i.severity] || 'white');
      const finds = arr(i.findings).map(f => `<li class="t-${esc(f.tone || 'base')}"><i class="no"></i><span>${esc(f.text)}</span></li>`).join('');
      const done = arr(i.done).map(d => `<span class="dn">${icon('check')}${esc(d)}</span>`).join('');
      const routes = arr(i.routes);
      const steps = arr(i.steps);
      const main = routes[0];
      let care = '';
      if (steps.length || routes.length) {
        // the need(s) the plan lists for this wound, then the way(s) to do it
        const lines = steps.map(st => {
          const no = (!st.onCard && !st.can && st.reason)
            ? `<span class="wn${st.where === 'hospital' ? ' hp' : ''}">${icon(st.where === 'hospital' ? 'hospital' : 'lock')}<span>${esc(st.reason)}</span></span>` : '';
          return `<div class="ij-step${st.urgent ? ' urgent' : ''}${st.where === 'hospital' ? ' hosp' : ''}"><i></i><b>${esc(st.title || '')}</b>${no}</div>`;
        }).join('');
        const stepBtns = steps.filter(st => !st.onCard && st.can).map(st => `<button class="ij-go" ${stepAttrs(st)}><span class="gi">${icon(st.icon || 'medkit')}</span><span class="gl">${esc(st.label || st.title || '')}</span>${chips(st.items) ? `<span class="gs">${chips(st.items)}</span>` : ''}</button>`).join('');
        let routeBtn = '';
        if (main) {
          // supplies ride inside the action button as chips: item · uses · how many you carry
          const sc = arr(main.items).map(it => `<span class="sc ${it.ok ? 'sc-ok' : 'sc-short'}"><i></i><span>${esc(it.label)}</span><b>×${esc(String(it.need))}</b><em>${esc(T('have_n', '%d on you', it.have))}</em></span>`).join('');
          routeBtn = `${main.reason ? `<div class="why">${icon('alert')}<span>${esc(main.reason)}</span></div>` : ''}
            <button class="ij-go" data-inj="${esc(i.id)}" data-route="${esc(main.id)}" ${main.ok ? '' : 'disabled'}><span class="gi">${icon(main.icon || 'medkit')}</span><span class="gl">${esc(main.label)}</span>${main.ok ? '' : icon('lock')}${sc ? `<span class="gs">${sc}</span>` : ''}</button>`;
        }
        const alts = routes.length > 1 ? `<div class="alts"><span class="al">${esc(T('alt_care', 'Or instead'))}</span>${routes.slice(1).map(r => `<button class="ij-alt" data-inj="${esc(i.id)}" data-route="${esc(r.id)}" ${r.ok ? '' : 'disabled'}>${icon(r.icon || 'chev-r')}<span>${esc(r.label)}</span>${r.reason ? `<em>${esc(r.reason)}</em>` : icon('chev-r')}</button>`).join('')}</div>` : '';
        const routeFirst = !steps.length || steps[0].onCard || !stepBtns;
        care = `<div class="ij-care">
          <div class="ck"><span>${esc(T('what_to_do', 'What to do'))}</span></div>
          ${lines}${routeFirst ? routeBtn + stepBtns : stepBtns + routeBtn}${alts}
        </div>`;
      } else if (active) {
        care = `<div class="ij-care none">${icon('info')}<span>${esc(T('no_route', 'Nothing you can do for this here'))}</span></div>`;
      }
      const heal = (i.status === 'treated' || i.status === 'healing') ? `<div class="ij-heal"><span>${esc(T('healing', 'Healing'))}</span><div class="bar"><i style="width:${Math.max(4, i.heal || 0)}%"></i></div><b>${Math.round(i.heal || 0)}%</b></div>` : '';
      const ready = (main && main.ok) || steps.some(st => !st.onCard && st.can);
      return `<article class="ij t-${tone}${open ? ' open' : ''}${i.suspected ? ' sus' : ''}${!active ? ' done' : ''}">
        <button class="ij-h" data-id="${esc(i.id)}">
          ${sevRing(i.suspected ? 2 : (i.severity || 1), tone, i.icon || 'drop', i.suspected ? 'dash' : '')}
          <span class="tt"><b>${esc(i.typeLabel)}</b><small>${esc(i.regionLabel || '')}${i.statusLabel ? ` · ${esc(i.statusLabel)}` : ''}</small></span>
          <span class="sv">${esc(i.sevLabel || '')}</span>
          ${ready && !open ? `<span class="rd">${icon('play')}</span>` : ''}
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
        item('stopbleed', 'drop', T('btn_stop', 'Bleed control'), v.bleedLabel || '', '3', `red lv${v.canStop ? lv : 0}`, !!v.canStop, v.canStop ? T('tip_stop', 'Control the worst bleed') : T('no_bleeding_short', 'Nothing to control'), v.canStop ? lv / 4 : 0);
    },

    /* ── browser preview ──
       index.html?app=exam[&mix=default|healthy|arrest|limbs][&pose=diag|flat|side|turned|far] */
    preview() {
      const q = new URLSearchParams(location.search);
      const mix = q.get('mix') || 'default', poseName = q.get('pose') || 'diag';
      const POSES = { diag: null, flat: { rot: 0, k: 0.95, cx: 175, cy: 320 }, side: { rot: -90, k: 0.9, cx: 170, cy: 330 }, turned: { rot: 180, k: 0.95, cx: 170, cy: 320 }, far: { rot: -10, k: 0.55, cx: 165, cy: 320 } };
      const W = { default: ['chest', 'thigh_l', 'head'], healthy: [], arrest: ['abdomen'], limbs: ['thigh_l', 'forearm_l'] };
      const body = NZAAssess.body({ focus: 'full', wounds: W[mix] || W.default, pose: POSES[poseName] || null });
      const route = (id, label, ic, items, ok = true, reason = null) => ({ id, label, icon: ic, ok, avail: ok, reason, items });
      const it = (label, have, need = 1) => ({ label, have, need, ok: have >= need });
      const row = (idx, code, title, why, o = {}) => Object.assign({ idx, code, title, why, where: 'field', urgent: false, icon: 'medkit', can: true, kind: 'option', label: '', items: [] }, o);
      const clear = () => ({ status: 'healthy', statusLabel: 'Healthy', injuries: [], notes: [], todo: [] });
      const tools = [
        { name: 'nza_field_monitor', label: 'Attach monitor', icon: 'monitor' }, { name: 'nza_fa_oxygen', label: 'Oxygen mask', icon: 'wind' },
        { name: 'nza_field_iv', label: 'IV line', icon: 'syringe' }, { name: 'nza_fa_collar', label: 'Neck collar', icon: 'collar' },
        { name: 'nza_blood_type', label: 'Type & screen', icon: 'bloodbag' }, { name: 'nza_fa_tqoff', label: 'Remove tourniquet', icon: 'clamp' },
      ];
      let view;
      if (mix === 'healthy') {
        view = {
          name: 'Ava Lindqvist', state: 'alive', stateLabel: 'Conscious', triage: { level: 3, code: 'P3', label: 'Delayed' },
          bleed: 'none', bleedLabel: 'None', toTreat: 0, stabilized: true, canStop: false, devices: [],
          general: [{ icon: 'brain', text: 'Awake and talking', tone: '' }, { icon: 'drop', text: 'Skin warm and pink', tone: '' }],
          todo: [row(1, 'release', 'Release patient', 'Nothing left to treat. They can go home.', { icon: 'walk', label: 'Release patient' })],
          tools: tools.slice(0, 2), groups: Object.fromEntries(ORDER.map(n => [n, clear()])),
        };
      } else if (mix === 'arrest') {
        view = {
          name: 'Marco Delgado', state: 'arrest', stateLabel: 'Cardiac arrest', triage: { level: 1, code: 'P1', label: 'Immediate' },
          bleed: 'none', bleedLabel: 'None', toTreat: 1, stabilized: false, canStop: false, devices: [],
          general: [{ icon: 'brain', text: 'No response', tone: 'red' }, { icon: 'alert', text: 'Not breathing', tone: 'red' }],
          todo: [
            row(1, 'cpr', 'Start CPR', 'No pulse. Push hard and fast, use the defibrillator.', { urgent: true, icon: 'heart', kind: 'route', label: 'CPR' }),
            row(2, 'hospital', 'Take them to hospital', 'Stretcher, ambulance, hospital. 1 step(s) there.', { icon: 'ambulance', label: 'Put on the stretcher' }),
            row(3, 'scan', 'Scan for hidden bleeding', 'Signs of bleeding inside. Ultrasound at the hospital.', { where: 'hospital', icon: 'scan', can: false, kind: null }),
          ],
          tools, groups: Object.assign(Object.fromEntries(ORDER.map(n => [n, clear()])), {
            abdomen: { status: 'minor', statusLabel: 'Minor', pain: 0, notes: [{ text: 'Belly hard and tender', tone: 'amber' }], injuries: [], todo: [] },
          }),
        };
      } else {
        const limbsOnly = mix === 'limbs';
        view = {
          name: 'Tomas Reyna', state: 'wounded', stateLabel: 'Wounded', triage: { level: 1, code: 'P1', label: 'Immediate' },
          bleed: 'heavy', bleedLabel: 'Heavy', toTreat: 4, clock: 134, stabilized: false, canStop: true,
          devices: ['IV line', 'Oxygen'],
          checks: { pulse: { rate: 124, ago: '1 min ago' } },
          general: [
            { icon: 'brain', text: 'Opens eyes when spoken to', tone: 'amber' },
            { icon: 'drop', text: 'Pale and clammy', tone: 'amber' },
            { icon: 'pulse', text: 'Pulse 124 · wrist · weak · 1 min ago', tone: 'teal' },
          ],
          todo: [
            row(3, 'fluids', 'Give fluids', 'Lost a lot of blood. IV or IO line, then fluids or blood.', { urgent: true, icon: 'iv', kind: 'route', label: 'Field resuscitation', items: [it('Trauma kit', 2)] }),
            row(5, 'pain', 'Give pain relief', 'A lot of pain.', { icon: 'pill', label: 'Medication' }),
            row(6, 'hospital', 'Take them to hospital', 'Stretcher, ambulance, hospital. 2 step(s) there.', { icon: 'ambulance', label: 'Carry' }),
            row(8, 'drain', 'Drain the chest', 'Blood in the chest. Chest drain (ultrasound cart).', { where: 'hospital', icon: 'lungs', can: false, kind: null }),
          ],
          tools,
          groups: {
            head: limbsOnly ? clear() : { status: 'minor', statusLabel: 'Minor', pain: 30, notes: [{ text: 'Dazed, repeats the same question', tone: 'amber' }], todo: [], injuries: [
              { id: 'i3', region: 'face', regionLabel: 'Face', type: 'abrasion', typeLabel: 'Abrasion', icon: 'scrape', severity: 1, sevLabel: 'Minor', status: 'open', statusLabel: 'Open',
                findings: [{ text: 'Oozing', tone: 'dim' }, { text: 'Grit in the skin', tone: '' }], done: [], steps: [], routes: [route('clean', 'Clean & dress', 'gauze', [it('Saline', 3), it('Sterile dressing', 6)])] }] },
            neck: limbsOnly ? clear() : { status: 'minor', statusLabel: 'Minor', pain: 10, notes: [{ text: 'Neck pain: possible spine injury', tone: 'red' }], injuries: [],
              todo: [row(4, 'collar', 'Put on a neck collar', 'Neck or spine injury. Keep the head still.', { icon: 'collar', kind: 'route', label: 'Neck collar', items: [it('Neck collar', 0)], can: false, reason: 'You need: Neck collar' })] },
            chest: limbsOnly ? clear() : { status: 'critical', statusLabel: 'Severe', pain: 80, notes: [], todo: [], injuries: [
              { id: 'i1', region: 'chest', regionLabel: 'Chest', type: 'laceration', typeLabel: 'Deep laceration', icon: 'cut', severity: 4, sevLabel: 'Severe', status: 'open', statusLabel: 'Open',
                findings: [{ text: 'Fast, heavy bleeding', tone: 'red' }, { text: '84 mm long, deep', tone: '' }, { text: 'Dirt and debris in the wound', tone: 'amber' }], done: [],
                steps: [row(1, 'bleed', 'Stop the bleeding', 'Chest is bleeding.', { urgent: true, icon: 'drop', kind: 'route', label: 'Pack & wrap', onCard: true, inj: 'i1' })],
                routes: [route('stopbleed', 'Pack & wrap', 'gauze', [it('Gauze', 8), it('Bandage', 8)]), route('suture', 'Close with sutures', 'needle', [it('Suture kit', 2)])] },
              { id: 'c:haemothorax_suspected_right', region: 'chest', regionLabel: 'Chest', type: 'haemothorax', typeLabel: 'Haemothorax · right', icon: 'lungs', suspected: true, severity: 3, sevLabel: 'Suspected', status: 'open', statusLabel: 'Suspected',
                findings: [{ text: 'Quiet breath sounds on the right', tone: 'amber' }, { text: 'Breathing check · 1 min ago', tone: 'dim' }],
                done: [], steps: [], routes: [route('us_drain', 'Chest drain', 'tube', [it('Chest drain kit', 0)], false, 'You are missing supplies')] }] },
            abdomen: limbsOnly ? clear() : { status: 'minor', statusLabel: 'Minor', pain: 35, notes: [{ text: 'Belly hard and tender', tone: 'amber' }], injuries: [], todo: [] },
            l_arm: limbsOnly ? { status: 'serious', statusLabel: 'Serious', pain: 55, notes: [], todo: [], injuries: [
              { id: 'i6', region: 'l_lower_arm', regionLabel: 'Left forearm', type: 'fracture', typeLabel: 'Fracture', icon: 'bone', severity: 3, sevLabel: 'Serious', status: 'open', statusLabel: 'Open',
                findings: [{ text: 'Swollen and very tender', tone: '' }], done: [],
                steps: [row(2, 'splint', 'Splint the fracture', 'Left forearm is broken.', { icon: 'bone', kind: 'route', label: 'Splint', onCard: true, inj: 'i6' }),
                  row(7, 'xray', 'Take an X-ray', 'Left forearm fracture. X-ray table, then read the film.', { where: 'hospital', icon: 'xray', can: false, kind: null, reason: 'Put them on the X-ray table first', inj: 'i6' })],
                routes: [route('splint', 'Splint', 'splint', [it('Splint', 4)])] }] } : clear(),
            r_arm: { status: 'treated', statusLabel: 'Treated', notes: [], todo: [], injuries: [
              { id: 'i5', region: 'r_lower_arm', regionLabel: 'Right forearm', type: 'laceration', typeLabel: 'Deep laceration', icon: 'cut', severity: 2, sevLabel: 'Moderate', status: 'healing', statusLabel: 'Healing', heal: 46,
                findings: [{ text: 'Not bleeding', tone: 'dim' }], done: ['Irrigated', 'Sutured', 'Dressed'], steps: [], routes: [] }] },
            l_leg: { status: 'serious', statusLabel: 'Serious', pain: 65, notes: [], todo: [], injuries: [
              { id: 'i2', region: 'l_upper_leg', regionLabel: 'Left thigh', type: 'gunshot', typeLabel: 'Gunshot wound', icon: 'crosshair', severity: 3, sevLabel: 'Serious', status: 'controlled', statusLabel: 'Controlled',
                findings: [{ text: 'Bleeding held', tone: 'teal' }, { text: 'No exit hole: the round is likely still inside', tone: 'amber' }, { text: 'Tourniquet on for 12 min', tone: 'teal' }],
                done: ['Tourniquet'],
                steps: [row(7, 'bullet', 'Remove the bullet', 'Something is still inside the left thigh. Operating table.', { where: 'hospital', icon: 'scalpel', can: false, kind: null, inj: 'i2' })],
                routes: [route('bullet', 'Remove the round', 'forceps', [it('Surgical kit', 1)], false, 'Needs an operating room')] }] },
            r_leg: clear(),
          },
        };
      }
      NZA.demo('exam', { patient: { name: view.name, sex: 'm', npc: true }, view, locale: {} });
      NZAAssess.feed('exam', [...ORDER, 'center'], body);
      NZA.mock('exam:step', d => { NZA.toast({ title: 'What to do', message: `In game this starts plan step ${d.index} (${d.code}).`, type: 'info' }); return { ok: true }; });
      NZA.mock('exam:treat', d => { NZA.toast({ title: 'What to do', message: `In game this starts ${d.route}.`, type: 'info' }); return { ok: true }; });
      NZA.mock('exam:tool', d => { NZA.toast({ title: 'More tools', message: `In game this runs ${d.name}.`, type: 'info' }); return { ok: true }; });
      NZA.mock('exam:action', d => { NZA.toast({ title: 'Head-to-toe check', message: `In game this starts: ${d.action}`, type: 'info' }); return { ok: true }; });
      NZA.mock('exam:touch', () => ({ ok: true }));
      if (q.get('tools') === '1') setTimeout(() => { const a = NZA.apps.exam; a.toolsOpen = true; a.renderTodo(); }, 300);
      if (q.get('sel')) setTimeout(() => NZA.apps.exam.select(q.get('sel'), false), 350);
    },
  });
})();
