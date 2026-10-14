/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · Examination (app 'exam')       module: assess
   Top-down body map: 8 region labels anchored to bones (NZA anchors 'head' 'neck' 'chest'
   'abdomen' 'l_arm' 'r_arm' 'l_leg' 'r_leg' + 'center'), leader lines, status per region,
   "Injuries to treat" card with findings, treatments (NZA.ExamRoutes) and items have/need,
   General card, bottom-left summary and Check pulse / Check breathing / Stop bleeding.

   Lua → JS   open { locale, groups, view, patient, perms }   view (live)   anchors (stream)
   JS → Lua   exam:touch { group }   exam:treat { id, route }   exam:action { action, group }
              exam:close (ESC / Close)
   Keys: ↑/↓ or Tab select region · Enter treat · 1 pulse · 2 breathing · 3 stop bleeding · ESC close

   Also defines window.NZAAssess (preview-only body renderer shared by exam / pulse /
   breathing previews; never used in game).
   ═══════════════════════════════════════════════════════════ */
(() => {
  const esc = NZA.esc, icon = NZA.icon;
  let LOC = {};
  const T = (k, fb, ...a) => { let s = LOC[k] !== undefined ? String(LOC[k]) : fb; a.forEach(v => { s = s.replace(/%[sd]/, v); }); return s; };

  /* ─────────────── preview body (browser only) ─────────────── */
  const NZAAssess = window.NZAAssess = window.NZAAssess || {};
  NZAAssess.body = function body({ focus = 'full', shirtless = false, wounds = [] } = {}) {
    document.querySelectorAll('.nzas-body').forEach(n => n.remove());
    const wrap = document.createElement('div');
    wrap.className = 'nzas-body';
    const skin = '#b98a6c', skinD = '#8f6249', cloth = '#1c2431', clothH = '#2a3546', clothD = '#121821';
    const torso = shirtless ? skin : cloth, torsoH = shirtless ? '#d0a283' : clothH;
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

  /* ─────────────── app ─────────────── */
  const STATUS_TONE = { healthy: 'ok', treated: 'teal', minor: 'amber', serious: 'red', critical: 'crit' };
  const ORDER = ['head', 'neck', 'chest', 'abdomen', 'l_arm', 'r_arm', 'l_leg', 'r_leg'];
  const GROUP_FB = { head: 'Head', neck: 'Neck', chest: 'Chest', abdomen: 'Abdomen', l_arm: 'Left Arm', r_arm: 'Right Arm', l_leg: 'Left Leg', r_leg: 'Right Leg' };
  const MID_COL = { head: 'l', neck: 'r', chest: 'l', abdomen: 'r' };
  const SEV_RANK = { critical: 4, serious: 3, minor: 2, treated: 1, healthy: 0 };

  NZA.app('exam', {
    init(el) {
      this.el = el;
      el.innerHTML = `
        <div class="ex-shade"></div>
        <svg class="ex-lines"></svg>
        <div class="ex-labels"></div>
        <aside class="ex-general nza-hud nza-int"></aside>
        <aside class="ex-side"><div class="ex-head"></div><div class="ex-card nza-hud solid"></div></aside>
        <div class="ex-sum"></div>
        <div class="ex-actions nza-int"></div>`;
      this.$ = s => el.querySelector(s);
      this.lines = this.$('.ex-lines');
      this.labelBox = this.$('.ex-labels');
      this.nodes = {};
      this.anc = NZA.ui.Anchors('exam');
      this.anc.on(() => this.layout());
      window.addEventListener('resize', () => { if (NZA.isOpen('exam')) this.layout(); });
      this.$('.ex-card').addEventListener('click', e => this.onCardClick(e));
      this.$('.ex-actions').addEventListener('click', e => { const b = e.target.closest('button[data-act]'); if (b && !b.disabled) this.action(b.dataset.act); });
    },

    open(d) {
      LOC = Object.assign({}, d.locale || {});
      this.groups = (d.groups && d.groups.length ? d.groups : ORDER.map(n => ({ name: n }))).map(g => ({ name: g.name, label: g.label || T(`group_${g.name}`, GROUP_FB[g.name] || g.name) }));
      this.patient = d.patient || {};
      this.perms = Object.assign({ pulse: true, breathing: true }, d.perms || {});
      this.view = d.view || { groups: {} };
      this.sel = this.pickWorst();
      this.labelBox.innerHTML = '';
      this.lines.innerHTML = '';
      this.nodes = {};
      this.groups.forEach(g => this.makeLabel(g));
      this.renderAll();
      this.layout();
    },
    close() { this.labelBox.innerHTML = ''; this.lines.innerHTML = ''; this.nodes = {}; if (this.flip) { this.flip = null; } },

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
      Digit1() { NZA.apps.exam.action('pulse'); },
      Digit2() { NZA.apps.exam.action('breathing'); },
      Digit3() { NZA.apps.exam.action('stopbleed'); },
    },

    /* ── helpers ── */
    gview(name) { return (this.view.groups || {})[name] || { status: 'healthy', injuries: [], notes: [] }; },
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
      this.sel = name;
      this.renderLabels();
      this.renderCard();
      this.layout();
      if (touch) NZA.post('exam:touch', { group: name });
      NZA.audio.click(720);
    },
    action(act) {
      if (act === 'pulse' && !this.perms.pulse) return;
      if (act === 'breathing' && !this.perms.breathing) return;
      if (act === 'stopbleed' && !this.view.canStop) return;
      NZA.audio.click(880);
      NZA.post('exam:action', { action: act, group: this.sel });
    },
    treatFirst() {
      const g = this.gview(this.sel);
      for (const inj of g.injuries || []) {
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
    onCardClick(e) {
      const b = e.target.closest('button[data-route]');
      if (!b || b.disabled) return;
      this.treat(b.dataset.inj, b.dataset.route);
    },

    /* ── labels ── */
    makeLabel(g) {
      const btn = document.createElement('button');
      btn.className = 'exl nza-int';
      btn.dataset.g = g.name;
      btn.innerHTML = `<span class="d"></span><span class="n">${esc(g.label)}</span><span class="s"></span><span class="c"></span>`;
      btn.addEventListener('click', () => this.select(g.name));
      btn.addEventListener('mouseenter', () => { this.hover = g.name; this.drawLines(); });
      btn.addEventListener('mouseleave', () => { this.hover = null; this.drawLines(); });
      const dot = document.createElement('button');
      dot.className = 'exd nza-int';
      dot.addEventListener('click', () => this.select(g.name));
      this.labelBox.appendChild(dot);
      this.labelBox.appendChild(btn);
      this.nodes[g.name] = { btn, dot, g };
    },
    renderLabels() {
      Object.values(this.nodes).forEach(({ btn, dot, g }) => {
        const v = this.gview(g.name);
        const tone = STATUS_TONE[v.status] || 'ok';
        btn.className = `exl nza-int t-${tone} ${g.name === this.sel ? 'on' : ''}`;
        dot.className = `exd nza-int t-${tone} ${g.name === this.sel ? 'on' : ''}`;
        btn.querySelector('.s').textContent = v.statusLabel || T(`gs_${v.status}`, v.status);
        const n = (v.injuries || []).filter(i => i.status === 'open' || i.status === 'controlled' || i.suspected).length;
        const c = btn.querySelector('.c');
        c.textContent = n > 1 ? String(n) : '';
        c.style.display = n > 1 ? '' : 'none';
      });
    },

    layout() {
      const el = this.el;
      const W = el.clientWidth, H = el.clientHeight;
      if (!W || !H) return;
      const map = this.anc.all() || {};
      const pts = [];
      this.groups.forEach(g => {
        const a = map[g.name];
        const node = this.nodes[g.name];
        if (!node) return;
        if (!a || a.visible === false) { node.btn.style.display = 'none'; node.dot.style.display = 'none'; return; }
        node.btn.style.display = ''; node.dot.style.display = '';
        pts.push({ name: g.name, x: a.x * W, y: a.y * H, node });
      });
      if (!pts.length) { this.lines.innerHTML = ''; return; }
      const left = [], right = [];
      // limbs: the patient's left limbs go to whichever screen column they are closer to;
      // midline regions alternate so both columns stay balanced
      const avg = a => a.reduce((s2, p) => s2 + p.x, 0) / Math.max(1, a.length);
      const sL = pts.filter(p => /^l_/.test(p.name)), sR = pts.filter(p => /^r_/.test(p.name));
      const lOnLeft = sL.length && sR.length ? avg(sL) < avg(sR) : false;
      pts.forEach(p => {
        if (/^[lr]_/.test(p.name)) ((p.name[0] === 'l') === lOnLeft ? left : right).push(p);
        else (MID_COL[p.name] === 'l' ? left : right).push(p);
      });
      const span = Math.max(...pts.map(p => p.x)) - Math.min(...pts.map(p => p.x));
      const gap = Math.max(46, Math.min(110, span * 0.22));
      const reserveR = W - 430;                      // the injuries card
      const placeCol = (col, side) => {
        if (!col.length) return;
        col.sort((a, b) => a.y - b.y);
        const minGap = 38;
        // desired y = anchor y, then push apart
        col.forEach(p => { p.ly = p.y; });
        for (let i = 1; i < col.length; i++) if (col[i].ly - col[i - 1].ly < minGap) col[i].ly = col[i - 1].ly + minGap;
        const over = col[col.length - 1].ly - Math.min(H - 150, col[col.length - 1].ly);
        if (over > 0) col.forEach(p => { p.ly -= over; });
        for (let i = col.length - 2; i >= 0; i--) if (col[i + 1].ly - col[i].ly < minGap) col[i].ly = col[i + 1].ly - minGap;
        const top = 70; if (col[0].ly < top) { const d = top - col[0].ly; col.forEach(p => { p.ly += d; }); }
        const edge = side === 'l' ? Math.min(...col.map(p => p.x)) - gap : Math.max(...col.map(p => p.x)) + gap;
        col.forEach(p => {
          const w = p.node.btn.offsetWidth || 150;
          let lx = side === 'l' ? edge - w : edge;
          if (side === 'r' && lx + w > reserveR) lx = Math.max(p.x + 24, reserveR - w);
          lx = Math.max(16, Math.min(W - w - 16, lx));
          p.lx = lx; p.lw = w; p.side = side;
        });
      };
      placeCol(left, 'l');
      placeCol(right, 'r');
      this.placed = pts;
      pts.forEach(p => {
        p.node.dot.style.transform = `translate(${p.x}px, ${p.y}px)`;
        p.node.btn.style.transform = `translate(${p.lx}px, ${p.ly - 15}px)`;
      });
      this.lines.setAttribute('viewBox', `0 0 ${W} ${H}`);
      this.drawLines();
    },
    drawLines() {
      const pts = this.placed || [];
      this.lines.innerHTML = pts.map(p => {
        const ex = p.side === 'l' ? p.lx + p.lw : p.lx;
        const v = this.gview(p.name);
        const on = p.name === this.sel || p.name === this.hover;
        const tone = STATUS_TONE[v.status] || 'ok';
        return `<line class="ln t-${tone} ${on ? 'on' : ''}" x1="${p.x.toFixed(1)}" y1="${p.y.toFixed(1)}" x2="${ex.toFixed(1)}" y2="${p.ly.toFixed(1)}"/>`;
      }).join('');
    },

    /* ── card ── */
    renderAll() {
      this.renderLabels();
      this.renderCard();
      this.renderGeneral();
      this.renderSummary();
      this.renderActions();
    },
    renderCard() {
      const g = this.groups.find(x => x.name === this.sel) || { label: this.sel };
      const v = this.gview(this.sel);
      const tone = STATUS_TONE[v.status] || 'ok';
      const total = this.view.toTreat || 0;
      this.$('.ex-head').innerHTML = `<h2>${esc(T('card_title', 'Injuries to treat'))}</h2><span class="cnt">${total}</span>`;
      const notes = (v.notes || []).map(n => `<li class="${esc(n.tone || '')}">${esc(n.text)}</li>`).join('');
      const inj = (v.injuries || []).map(i => this.injuryHTML(i)).join('');
      const empty = !inj ? `<div class="ex-empty">${icon(v.status === 'treated' ? 'check' : 'shield-check')}<div><b>${esc(v.status === 'treated' ? T('empty_treated', 'Treated') : T('empty_title', 'Nothing found'))}</b><span>${esc(v.status === 'treated' ? T('empty_treated_sub', 'Everything here has been taken care of.') : T('empty_sub', 'No injuries in this area. Check the other regions.'))}</span></div></div>` : '';
      this.$('.ex-card').innerHTML = `
        <div class="ex-ch"><span class="gn">${esc(g.label)}</span><span class="gs t-${tone}"><i></i>${esc(v.statusLabel || v.status)}</span></div>
        ${notes ? `<ul class="ex-notes">${notes}</ul>` : ''}
        <div class="ex-list nza-scroll">${inj}${empty}</div>`;
    },
    injuryHTML(i) {
      const sevTone = i.suspected ? 'amber' : ({ 1: '', 2: 'amber', 3: 'red', 4: 'red' })[i.severity] || '';
      const finds = (i.findings || []).map(f => `<li class="${esc(f.tone || '')}">${esc(f.text)}</li>`).join('');
      const done = (i.done || []).map(d => `<span class="dn">${icon('check')}${esc(d)}</span>`).join('');
      const routes = i.routes || [];
      const main = routes[0];
      let treat = '';
      if (main) {
        const items = (main.items || []).map(it => `<li class="${it.ok ? 'ok' : 'no'}">${icon(it.ok ? 'check' : 'x')}<span>${esc(it.label)}</span><b>${it.have}<i>/${it.need}</i></b></li>`).join('');
        treat = `<div class="ex-route">
          <div class="rt">${icon(main.icon || 'medkit')}<span>${esc(main.label)}</span></div>
          ${items ? `<ul class="ex-items">${items}</ul>` : ''}
          ${main.reason ? `<div class="why">${icon('alert')}${esc(main.reason)}</div>` : ''}
          <button class="ex-treat" data-inj="${esc(i.id)}" data-route="${esc(main.id)}" ${main.ok ? '' : 'disabled'}>${icon('medkit')}${esc(T('treat', 'Treat injury'))}${main.ok ? '<kbd>Enter</kbd>' : ''}</button>
          ${routes.slice(1).map(r => `<button class="ex-alt" data-inj="${esc(i.id)}" data-route="${esc(r.id)}" ${r.ok ? '' : 'disabled'} title="${esc(r.reason || '')}">${icon(r.icon || 'chev-r')}<span>${esc(r.label)}</span>${r.reason ? `<em>${esc(r.reason)}</em>` : ''}</button>`).join('')}
        </div>`;
      } else if (i.status === 'open' || i.status === 'controlled') {
        treat = `<div class="ex-route none">${icon('info')}<span>${esc(T('no_route', 'No treatment you can do here'))}</span></div>`;
      }
      const heal = (i.status === 'treated' || i.status === 'healing') ? `<div class="ex-heal"><span>${esc(T('healing', 'Healing'))}</span><div class="mtr"><i style="width:${Math.max(4, i.heal || 0)}%"></i></div><b>${Math.round(i.heal || 0)}%</b></div>` : '';
      return `<section class="ex-inj ${i.suspected ? 'sus' : ''} ${(i.status === 'treated' || i.status === 'healing') ? 'done' : ''}">
        <div class="ih"><span class="ic">${icon(i.icon || 'drop')}</span><div class="tt"><b>${esc(i.typeLabel)}</b><span>${esc(i.regionLabel)}${i.status && !i.suspected ? ` · ${esc(i.statusLabel || i.status)}` : ''}</span></div><span class="sev ${sevTone}">${esc(i.sevLabel || '')}</span></div>
        ${finds ? `<ul class="ex-find">${finds}</ul>` : ''}
        ${done ? `<div class="ex-done">${done}</div>` : ''}
        ${heal}${treat}
      </section>`;
    },
    renderGeneral() {
      const v = this.view;
      const rows = (v.general || []).map(r => `<li class="${esc(r.tone || '')}">${icon(r.icon || 'info')}<span>${esc(r.text)}</span></li>`).join('');
      const dev = (v.devices || []).map(d => `<span class="chipx sm teal">${esc(d)}</span>`).join('');
      const tri = v.triage ? `<span class="prio p${v.triage.level || 3}">${esc(v.triage.code || '')}${v.triage.label ? ` ${esc(v.triage.label)}` : ''}</span>` : '';
      this.$('.ex-general').innerHTML = `
        <div class="gh"><div><span class="nza-label">${esc(T('general', 'General'))}</span><b>${esc(v.name || this.patient.name || '')}</b></div>${tri}</div>
        <ul class="gl">${rows}</ul>${dev ? `<div class="gd">${dev}</div>` : ''}`;
    },
    renderSummary() {
      const v = this.view;
      const n = v.toTreat || 0;
      const bleedTone = { none: 'teal', light: 'amber', moderate: 'amber', heavy: 'red', massive: 'red' }[v.bleed] || '';
      let clock = '';
      if (v.clock !== null && v.clock !== undefined) clock = `<div class="ck"><span class="nza-label">${esc(T('bleedout', 'Bleed-out'))}</span><span class="fc"></span></div>`;
      else if (v.stabilized && v.state === 'wounded') clock = `<div class="ck st"><span class="nza-label">${esc(T('stabilized', 'Stabilized'))}</span></div>`;
      this.$('.ex-sum').innerHTML = `
        <div class="t">${esc(T('exam_title', 'Examination'))}</div>
        <div class="l"><span class="${bleedTone}">${esc(v.bleedLabel || '')}</span><i>·</i><span>${esc(n === 1 ? T('to_treat_1', '1 injury to treat') : T('to_treat_n', '%d injuries to treat', n))}</span>${v.state && v.state !== 'alive' ? `<i>·</i><span class="${v.state === 'wounded' ? 'amber' : 'red'}">${esc(v.stateLabel || v.state)}</span>` : ''}</div>
        ${clock}
        <div class="k"><kbd>ESC</kbd><span>${esc(T('close', 'Close'))}</span><kbd>↑↓</kbd><span>${esc(T('regions', 'Regions'))}</span></div>`;
      const fc = this.$('.ex-sum .fc');
      if (fc) { const f = NZA.ui.FlipClock(fc, { value: NZA.fmt.time(v.clock), small: true, tone: v.clock < 60 ? 'red' : '' }); this.flip = f; }
    },
    renderActions() {
      const v = this.view;
      const b = (act, ic, label, key, cls, ok) => `<button class="ex-btn ${cls}" data-act="${act}" ${ok ? '' : 'disabled'}><kbd>${key}</kbd>${icon(ic)}<span>${esc(label)}</span></button>`;
      this.$('.ex-actions').innerHTML =
        b('pulse', 'pulse', T('btn_pulse', 'Check pulse'), '1', '', this.perms.pulse !== false) +
        b('breathing', 'lungs', T('btn_breathing', 'Check breathing'), '2', '', this.perms.breathing !== false) +
        (v.canStop ? b('stopbleed', 'drop', T('btn_stop', 'Stop bleeding'), '3', 'red', true) : '');
    },

    /* ── browser preview ── */
    preview() {
      const body = NZAAssess.body({ focus: 'full', wounds: ['chest', 'thigh_l', 'head'] });
      const route = (id, label, ic, items, ok = true, reason = null) => ({ id, label, icon: ic, ok, avail: ok, reason, items });
      const view = {
        name: 'Michael Garcia', state: 'wounded', stateLabel: 'Wounded', triage: { level: 1, code: 'P1', label: 'Critical' },
        bleed: 'heavy', bleedLabel: 'Heavy bleeding', toTreat: 4, clock: 134, stabilized: false, canStop: true,
        devices: ['IV line'],
        general: [
          { icon: 'brain', text: 'Responds to voice', tone: 'amber' },
          { icon: 'drop', text: 'Pale, sweaty skin', tone: 'amber' },
          { icon: 'pulse', text: 'Pulse 124 bpm · radial · weak · 1 min ago', tone: 'teal' },
        ],
        groups: {
          head: { status: 'minor', statusLabel: 'Minor', pain: 30, notes: [{ text: 'Dazed, keeps asking what happened', tone: 'amber' }], injuries: [
            { id: 'i3', region: 'face', regionLabel: 'Face', type: 'abrasion', typeLabel: 'Abrasion', icon: 'scrape', severity: 1, sevLabel: 'Minor', status: 'open', statusLabel: 'Open',
              findings: [{ text: 'Oozing', tone: 'dim' }, { text: 'Grit in the skin', tone: '' }], done: [], routes: [route('clean', 'Clean & dress', 'gauze', [{ label: 'Saline', have: 3, need: 1, ok: true }, { label: 'Sterile Dressing', have: 6, need: 1, ok: true }])] }] },
          neck: { status: 'healthy', statusLabel: 'Healthy', injuries: [], notes: [] },
          chest: { status: 'critical', statusLabel: 'Critical', pain: 80, notes: [], injuries: [
            { id: 'i1', region: 'chest', regionLabel: 'Chest', type: 'laceration', typeLabel: 'Deep laceration', icon: 'cut', severity: 4, sevLabel: 'Critical', status: 'open', statusLabel: 'Open',
              findings: [{ text: 'Heavy bleeding', tone: 'red' }, { text: '84 mm long, deep', tone: '' }, { text: 'Dirt and debris in the wound', tone: 'amber' }],
              done: [], routes: [route('suture', 'Suture the wound', 'needle', [{ label: 'Bandage', have: 8, need: 1, ok: true }, { label: 'Suture Kit', have: 2, need: 1, ok: true }]), route('stopbleed', 'Pack & bandage', 'gauze', [], true)] },
            { id: 'c:haemothorax_suspected_right', region: 'chest', regionLabel: 'Chest', type: 'haemothorax', typeLabel: 'Haemothorax · right', icon: 'lungs', suspected: true, severity: 3, sevLabel: 'Suspected', status: 'open',
              findings: [{ text: 'Reduced air entry on the right', tone: 'amber' }, { text: 'Found by breathing check · 1 min ago', tone: 'dim' }],
              done: [], routes: [route('chestdrain', 'Chest drain', 'tube', [{ label: 'Chest Drain Kit', have: 0, need: 1, ok: false }], false, 'You need a Chest Drain Kit')] }] },
          abdomen: { status: 'minor', statusLabel: 'Minor', notes: [{ text: 'Belly tense and tender', tone: 'amber' }], injuries: [] },
          l_arm: { status: 'healthy', statusLabel: 'Healthy', injuries: [], notes: [] },
          r_arm: { status: 'treated', statusLabel: 'Treated', injuries: [
            { id: 'i5', region: 'r_lower_arm', regionLabel: 'Right forearm', type: 'laceration', typeLabel: 'Deep laceration', icon: 'cut', severity: 2, sevLabel: 'Moderate', status: 'healing', statusLabel: 'Healing', heal: 46,
              findings: [{ text: 'Not bleeding', tone: 'dim' }], done: ['Irrigated', 'Sutured', 'Dressed'], routes: [] }], notes: [] },
          l_leg: { status: 'serious', statusLabel: 'Serious', injuries: [
            { id: 'i2', region: 'l_upper_leg', regionLabel: 'Left thigh', type: 'gunshot', typeLabel: 'Gunshot wound', icon: 'crosshair', severity: 3, sevLabel: 'Serious', status: 'controlled', statusLabel: 'Controlled',
              findings: [{ text: 'Bleeding controlled', tone: 'teal' }, { text: 'No exit wound: the bullet is probably still inside', tone: 'amber' }, { text: 'Tourniquet on for 12 min', tone: 'teal' }],
              done: ['Tourniquet'], routes: [route('bullet', 'Remove the bullet', 'forceps', [{ label: 'Surgical Kit', have: 1, need: 1, ok: true }], false, 'Needs a surgery room')] }], notes: [] },
          r_leg: { status: 'healthy', statusLabel: 'Healthy', injuries: [], notes: [] },
        },
      };
      NZA.demo('exam', { patient: { name: 'Michael Garcia', sex: 'm', npc: true }, view, locale: {} });
      NZAAssess.feed('exam', [...ORDER, 'center'], body);
      NZA.mock('exam:treat', () => { NZA.toast({ title: 'Treat', message: 'In game this starts the treatment.', type: 'info' }); return { ok: true }; });
      NZA.mock('exam:action', d => { NZA.toast({ title: 'Examination', message: `In game this starts: ${d.action}`, type: 'info' }); return { ok: true }; });
      NZA.mock('exam:touch', d => { const lines = { chest: 'It hurts... it hurts so bad.', l_leg: "Don't press there, please!", head: 'Ow. Easy, easy.' }; if (lines[d.group]) NZA.speech({ name: 'Michael Garcia', text: lines[d.group], ms: 3800 }); return { ok: true }; });
      setTimeout(() => NZA.speech({ name: 'Michael Garcia', text: 'It hurts... it hurts so bad.', ms: 60000 }), 300);
    },
  });
})();
