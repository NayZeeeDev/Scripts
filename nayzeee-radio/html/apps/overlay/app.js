/* ═══════════════════════════════════════════════════════════
   NAYZEEE RADIO · overlay (never takes focus)                         apps/overlay/app.js
   While the handheld is raised (client/modules/interact.lua) and while a jammer is being
   set down (client/modules/jammers.lua).

   Lua → NUI
     open      { hints = [{ keys = { 'LMB' }, label = 'Press' }, ...] }   key dock on the right edge
     hover     { id, poly = [{ x, y }, ...] (0..1 screen fractions), label?, hint?, action?, value?, pressed? }
               { } = nothing hovered. A new id cross-fades, the same id just follows the camera.
     place     { title, hints, valid, reason?, heading? }   placement card, top-left
     placeHide { }
     close     dock + outline go; a placement card still up stays
   NUI → Lua   nothing (no focus, no cursor of its own)

   Key names in hints: FiveM mapper names (CAPITAL, RETURN …) via NZR.keyName, plus LMB / RMB /
   MMB / WHEEL (mouse glyphs) and ARROWS (arrow cluster). Part names on the outline come from
   the hover data (label/hint), else from its action, else from the SPEC §9.2 part id.
   ═══════════════════════════════════════════════════════════ */
(() => {
  const NZR = window.NZR;
  const { esc, t } = NZR;
  const num = (v, d = NaN) => { const n = Number(v); return Number.isFinite(n) ? n : d; };
  // static words: re-read from the locale when Lua pushes the config (it arrives after init)
  const L = (k, f) => `<span data-t="${k}" data-f="${esc(f)}">${esc(t(k, f))}</span>`;
  const relabel = el => el.querySelectorAll('[data-t]').forEach(e => { e.textContent = t(e.dataset.t, e.dataset.f); });

  const DEFAULT_HINTS = [
    { keys: ['LMB'], label: 'Press' },
    { keys: ['RMB', 'ESC'], label: 'Lower' },
    { keys: ['CAPITAL'], label: 'Talk' },
    { keys: ['WHEEL'], label: 'Zoom' },
    { keys: ['0-9'], label: 'Keypad' },
    { keys: ['ARROWS'], label: 'Navigate' },
  ];

  /* ─────────────── key caps ─────────────── */
  const MOUSE_FILL = {
    l: '<path class="f" d="M6.4 2.1C4.1 2.3 2.4 4.2 2.4 6.7V8.3H6.4Z"/>',
    r: '<path class="f" d="M7.6 2.1C9.9 2.3 11.6 4.2 11.6 6.7V8.3H7.6Z"/>',
    w: '<rect class="f" x="5.7" y="2.9" width="2.6" height="4.3" rx="1.3"/>',
  };
  function mouse(which) {
    return `<svg viewBox="0 0 14 18">${MOUSE_FILL[which] || ''}<path class="o" d="M7 1.6C4.1 1.6 2 3.8 2 6.7V11.6C2 14.5 4.1 16.6 7 16.6S12 14.5 12 11.6V6.7C12 3.8 9.9 1.6 7 1.6Z"/><path class="o" d="M2 8.3H12${which === 'w' ? 'M7 1.6V2.9M7 7.2V8.3' : 'M7 1.6V8.3'}"/></svg>`;
  }
  const ARROWS = '<svg viewBox="0 0 16 16"><path class="w" d="M8 1.2 10.5 4.3H5.5ZM8 14.8 5.5 11.7H10.5ZM1.2 8 4.3 5.5V10.5ZM14.8 8 11.7 10.5V5.5Z"/></svg>';
  const MOUSE_KEYS = { LMB: 'l', MOUSE_LEFT: 'l', RMB: 'r', MOUSE_RIGHT: 'r', MMB: 'w', MOUSE_MIDDLE: 'w', WHEEL: 'w', SCROLL: 'w', IOM_WHEEL_UP: 'w', IOM_WHEEL_DOWN: 'w' };
  const MOUSE_TITLE = { l: ['ui.lmb', 'LMB'], r: ['ui.rmb', 'RMB'], w: ['ui.wheel', 'WHEEL'] };

  function cap(k) {
    const s = String(k ?? '').trim();
    const up = s.toUpperCase();
    if (MOUSE_KEYS[up]) { const m = MOUSE_KEYS[up]; return `<kbd class="ms" title="${esc(t(...MOUSE_TITLE[m]))}">${mouse(m)}</kbd>`; }
    if (up === 'ARROWS' || up === 'ARROW' || up === 'ARROWKEYS') return `<kbd class="ar">${ARROWS}</kbd>`;
    if (up === 'ESC' || up === 'ESCAPE') return `<kbd>${esc(t('ui.esc', 'ESC'))}</kbd>`;
    if (/^\d-\d$/.test(s)) return `<kbd>${esc(s.replace('-', '–'))}</kbd>`;
    return `<kbd>${esc(NZR.keyName(s) || s)}</kbd>`;
  }
  function keysHTML(keys) {
    const list = Array.isArray(keys) ? keys : (keys !== undefined && keys !== null ? [keys] : []);
    return `<span class="ov-keys">${list.slice(0, 3).map(cap).join('<i>/</i>')}</span>`;
  }
  function cleanHints(h) {
    if (!Array.isArray(h)) return null;
    return h.filter(x => x && typeof x === 'object' && (x.label || x.keys || x.key))
      .slice(0, 9).map(x => ({ keys: x.keys !== undefined ? x.keys : x.key, label: String(x.label ?? '') }));
  }

  /* ─────────────── part names (hover chip) ─────────────── */
  const ID_ACTION = {
    kstar: ['star'], khash: ['hash'], kok: ['ok'], kset: ['ok'], kback: ['back'], kband: ['back'],
    kmenu: ['menu'], kup: ['up'], kdown: ['down'], kp1: ['p1'], kp2: ['p2'], kpower: ['power'],
    dpad: ['dpad'], knob_ch: ['knob', 'channel'], knob_vol: ['knob', 'volume'], emerg: ['emerg'],
    ptt: ['ptt'], side1: ['side1'], side2: ['side2'],
  };
  const PART = {
    star: ['Key *', 'decimal point'], hash: ['Key #', 'clear slot'], ok: ['OK', 'select'], back: ['Back', 'delete'],
    menu: ['Menu', ''], up: ['Up', 'slot'], down: ['Down', 'slot'], left: ['Left', 'volume'], right: ['Right', 'volume'],
    dpad: ['Navigation pad', 'slots · volume'], p1: ['P1', 'memories'], p2: ['P2', 'mute'], power: ['Power', 'hold'],
    knob_channel: ['Channel knob', 'memories'], knob_volume: ['Volume knob', 'turn · low to switch off'],
    emerg: ['Emergency', 'hold to alert'], ptt: ['Push to talk', 'hold'], side1: ['Side key 1', 'hands-free'],
    side2: ['Side key 2', 'roster'], mute: ['Mute', ''], pre: ['Memories', ''],
  };
  function partName(d) {
    if (d.label) return [String(d.label), String(d.hint ?? '')];
    let action = d.action, value = d.value;
    const id = String(d.id ?? '');
    if (!action) {
      const dg = /^k(\d)$/.exec(id);
      if (dg) { action = 'digit'; value = dg[1]; } else if (ID_ACTION[id]) [action, value] = ID_ACTION[id];
    }
    if (action === 'digit') return [`${t('ui.part_key', 'Key')} ${value ?? ''}`.trim(), ''];
    const key = action === 'knob' ? `knob_${value}` : action;
    const p = PART[key];
    if (!p) return ['', ''];
    return [t(`ui.part_${key}`, p[0]), t(`ui.part_${key}_h`, p[1])];
  }

  /* ─────────────── state ─────────────── */
  let app = null, root = null, dock = null, list = null, svg = null, gA = null, gB = null, tag = null, place = null;
  let cur = null;                 // { id, g }
  let hintsSig = '', placeSig = '', placeValid = true, placeTimer = 0;

  const vp = () => { const z = NZR.zoom || 1; return { W: window.innerWidth / z, H: window.innerHeight / z }; };
  const keysUp = () => NZR.isOpen('overlay');

  // hints: an array (empty = no dock, e.g. the overlay opened only for a jammer placement);
  // missing = the default set. Lua encodes an empty table as {} or [], both mean "none".
  function hintList(d) {
    if (Array.isArray(d.hints)) return cleanHints(d.hints);
    return d.hints === undefined && d.place !== true ? DEFAULT_HINTS : [];
  }
  function renderHints(h) {
    const sig = JSON.stringify(h);
    if (sig === hintsSig) return;
    hintsSig = sig;
    list.innerHTML = h.map((x, i) => `<div class="ov-k" style="--i:${i}"><em>${esc(x.label)}</em>${keysHTML(x.keys)}</div>`).join('');
  }

  /* ─────────────── hover outline ─────────────── */
  function toPx(poly, W, H) {
    const out = [];
    poly.forEach(p => {
      const x = Array.isArray(p) ? num(p[0]) : num(p && p.x);
      const y = Array.isArray(p) ? num(p[1]) : num(p && p.y);
      if (Number.isFinite(x) && Number.isFinite(y)) out.push([x * W, y * H]);
    });
    return out;
  }
  function draw(g, P) {
    const d = `M${P.map(p => `${p[0].toFixed(1)} ${p[1].toFixed(1)}`).join('L')}Z`;
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    P.forEach(([x, y]) => { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); });
    const pad = 5;
    x0 -= pad; y0 -= pad; x1 += pad; y1 += pad;
    const L = Math.max(4, Math.min(9, Math.min(x1 - x0, y1 - y0) * 0.3));
    const f = n => n.toFixed(1);
    const ticks = `M${f(x0)} ${f(y0 + L)}V${f(y0)}H${f(x0 + L)}M${f(x1 - L)} ${f(y0)}H${f(x1)}V${f(y0 + L)}M${f(x1)} ${f(y1 - L)}V${f(y1)}H${f(x1 - L)}M${f(x0 + L)} ${f(y1)}H${f(x0)}V${f(y1 - L)}`;
    const ps = g.children;
    ps[0].setAttribute('d', d); ps[1].setAttribute('d', d); ps[2].setAttribute('d', d); ps[3].setAttribute('d', ticks);
    return { x0, y0, x1, y1 };
  }
  function placeTag(b, W) {
    const tw = tag.offsetWidth || 120;
    const right = b.x1 + 10;
    const left = right + tw > W - 250 && b.x0 - 10 - tw > 8;
    tag.classList.toggle('left', left);
    tag.style.left = `${Math.round(left ? b.x0 - 10 - tw : right)}px`;
    tag.style.top = `${Math.round((b.y0 + b.y1) / 2 - 11)}px`;
  }
  function hover(d) {
    const poly = d && Array.isArray(d.poly) ? d.poly : null;
    const { W, H } = vp();
    const P = poly && poly.length >= 3 ? toPx(poly, W, H) : [];
    if (P.length < 3) { clearHover(); return; }
    svg.setAttribute('viewBox', `0 0 ${W.toFixed(1)} ${H.toFixed(1)}`);
    const id = String(d.id ?? '');
    let b;
    if (!cur || cur.id !== id) {
      const next = cur && cur.g === gA ? gB : gA;
      if (cur) cur.g.classList.remove('on', 'press');
      next.classList.remove('on');
      b = draw(next, P);
      cur = { id, g: next };
      requestAnimationFrame(() => { if (cur && cur.g === next) next.classList.add('on'); });
      const [name, hint] = partName(d);
      tag.classList.remove('on');
      if (name) {
        tag.innerHTML = `<b>${esc(name)}</b><span>${esc(hint)}</span>`;
        placeTag(b, W);
        requestAnimationFrame(() => { if (cur && cur.id === id) tag.classList.add('on'); });
      }
    } else {
      b = draw(cur.g, P);
      if (tag.classList.contains('on')) placeTag(b, W);
    }
    cur.g.classList.toggle('press', d.pressed === true);
  }
  function clearHover() {
    if (cur) cur.g.classList.remove('on', 'press');
    cur = null;
    if (tag) tag.classList.remove('on');
  }

  /* ─────────────── jammer placement ─────────────── */
  function showSection() { root.classList.add('nzr-on'); }
  function maybeHideSection() { if (!keysUp() && !place.classList.contains('on')) root.classList.remove('nzr-on'); }

  function placeShow(d = {}) {
    d = d || {};
    clearTimeout(placeTimer);
    showSection();
    const valid = d.valid !== false;
    const q = s => place.querySelector(s);
    q('.pl-t b').textContent = String(d.title || t('ui.ov_place_title', 'Signal jammer'));
    // status: Lua's own line when it sends one (jammers.lua: why the spot is bad), else ours;
    // reason is shown only as a plain-text fallback next to our line
    const status = typeof d.status === 'string' && d.status ? d.status : '';
    q('.pl-msg').textContent = status || (valid ? t('ui.ov_place_ok', 'Clear to set down') : t('ui.ov_place_bad', "Can't go here"));
    q('.pl-why').textContent = !valid && !status && typeof d.reason === 'string' && /\s/.test(d.reason) ? d.reason : '';
    const hd = num(d.heading);
    q('.pl-rot').textContent = Number.isFinite(hd) ? `${String(Math.round(((hd % 360) + 360) % 360)).padStart(3, '0')}°` : '';
    const hints = cleanHints(d.hints) || [];
    const sig = JSON.stringify(hints);
    if (sig !== placeSig) {
      placeSig = sig;
      q('.pl-keys').innerHTML = hints.map(x => `${keysHTML(x.keys)}<em>${esc(x.label)}</em>`).join('');
      q('.pl-keys').style.display = hints.length ? '' : 'none';
    }
    const wasOn = place.classList.contains('on');
    place.classList.toggle('bad', !valid);
    if (wasOn && placeValid && !valid) {
      place.classList.remove('shake'); void place.offsetWidth; place.classList.add('shake');
    }
    placeValid = valid;
    place.classList.add('on');
  }
  function placeHide() {
    place.classList.remove('on', 'shake');
    clearTimeout(placeTimer);
    placeTimer = setTimeout(maybeHideSection, 300);
  }

  /* ─────────────── preview: a stand-in handset to hover over (generic, no brand) ─────────────── */
  let mockTimer = 0;
  function mock() {
    const { W, H } = vp();
    const cx = W * 0.47, cy = H * 0.53, th = -7 * Math.PI / 180, s = Math.min(1.15, H / 960);
    const tr = (x, y) => [cx + (x * Math.cos(th) - y * Math.sin(th)) * s, cy + (x * Math.sin(th) + y * Math.cos(th)) * s];
    const rect = (x0, y0, x1, y1) => [tr(x0, y0), tr(x1, y0), tr(x1, y1), tr(x0, y1)];
    const circ = (x, y, r) => Array.from({ length: 18 }, (_, i) => tr(x + r * Math.cos(i / 18 * Math.PI * 2), y + r * Math.sin(i / 18 * Math.PI * 2)));
    const parts = {
      knob_ch: rect(-36, -250, -8, -214), knob_vol: rect(12, -256, 40, -214), emerg: circ(74, -230, 13),
      ptt: rect(-123, -122, -110, -22), side1: rect(-123, -8, -110, 24), side2: rect(-123, 34, -110, 66),
      kp1: rect(-94, -4, -58, 20), kp2: rect(58, -4, 94, 20), kok: rect(-94, 28, -58, 52), kback: rect(58, 28, 94, 52),
      dpad: circ(0, 24, 30),
    };
    const labels = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];
    const ids = ['k1', 'k2', 'k3', 'k4', 'k5', 'k6', 'k7', 'k8', 'k9', 'kstar', 'k0', 'khash'];
    const keys = labels.map((l, i) => { const x = [-60, 0, 60][i % 3], y = 86 + Math.floor(i / 3) * 36; parts[ids[i]] = rect(x - 25, y - 14, x + 25, y + 14); return { l, x, y }; });
    const grp = `translate(${cx.toFixed(1)} ${cy.toFixed(1)}) rotate(-7) scale(${s.toFixed(3)})`;
    const el = NZR.el('div');
    el.innerHTML = `<svg class="ov-mock" viewBox="0 0 ${W} ${H}"><defs>
        <linearGradient id="ovmk-bd" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#34393d"/><stop offset=".45" stop-color="#1d2023"/><stop offset="1" stop-color="#0d0e0f"/></linearGradient>
        <linearGradient id="ovmk-k" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#363b3f"/><stop offset="1" stop-color="#191b1d"/></linearGradient>
        <linearGradient id="ovmk-kn" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#1a1c1e"/><stop offset=".5" stop-color="#43494d"/><stop offset="1" stop-color="#16181a"/></linearGradient>
        <linearGradient id="ovmk-gl" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="rgba(255,255,255,.13)"/><stop offset=".35" stop-color="rgba(255,255,255,.02)"/><stop offset=".36" stop-color="rgba(255,255,255,0)"/></linearGradient>
      </defs><g transform="${grp}">
        <rect x="-76" y="-372" width="18" height="160" rx="7" class="kn"/>
        <rect x="-36" y="-250" width="28" height="40" rx="4" class="kn"/><rect x="12" y="-256" width="28" height="46" rx="4" class="kn"/>
        <circle cx="74" cy="-230" r="13" class="em"/>
        <rect x="-123" y="-122" width="16" height="100" rx="5" class="k"/><rect x="-123" y="-8" width="16" height="32" rx="5" class="k"/><rect x="-123" y="34" width="16" height="32" rx="5" class="k"/>
        <path class="bd" d="M-84 -216H84L110 -190V200L84 226H-84L-110 200V-190Z"/><path class="ed" d="M-80 -209H80L103 -186V196L80 219H-80L-103 196V-186Z"/>
        <path class="gr" d="M-58 -194H58M-58 -184H58M-58 -174H58"/><text class="lb" x="-58" y="-158">PX-740</text>
        <rect x="-86" y="-150" width="172" height="124" rx="8" class="sc"/>
        <text class="lcs" x="-74" y="-128">S1 TX</text><path class="lcb" d="M52 -127h3v-4h-3ZM58 -127h3v-7h-3ZM64 -127h3v-10h-3ZM70 -127h3v-13h-3Z"/><text class="lcd" x="-74" y="-92">155.50</text><text class="lcs" x="-74" y="-70">PATROL NORTH</text><text class="lcs" x="-74" y="-48">14:32   MEM 3</text>
        <rect x="-86" y="-150" width="172" height="124" rx="8" class="gl"/>
        <rect x="-94" y="-4" width="36" height="24" rx="6" class="k"/><rect x="58" y="-4" width="36" height="24" rx="6" class="k"/>
        <rect x="-94" y="28" width="36" height="24" rx="6" class="k"/><rect x="58" y="28" width="36" height="24" rx="6" class="k"/>
        <text class="kl" x="-76" y="12" style="font-size:9px">P1</text><text class="kl" x="76" y="12" style="font-size:9px">P2</text>
        <text class="kl" x="-76" y="44" style="font-size:9px">OK</text><text class="kl" x="76" y="44" style="font-size:9px">◂</text>
        <circle cx="0" cy="24" r="30" class="k"/><circle cx="0" cy="24" r="11" class="kn"/>
        ${keys.map(k => `<rect x="${k.x - 25}" y="${k.y - 14}" width="50" height="28" rx="7" class="k"/><text class="kl" x="${k.x}" y="${k.y + 4}">${k.l}</text>`).join('')}
      </g></svg>`;
    root.insertBefore(el.firstChild, root.firstChild);
    const frac = pts => pts.map(([x, y]) => ({ x: +(x / W).toFixed(4), y: +(y / H).toFixed(4) }));
    const order = ['k5', 'kok', 'dpad', 'ptt', 'knob_vol', 'emerg', 'k8', 'side1', 'kp2', 'knob_ch'];
    let i = 0;
    const step = () => {
      const id = order[i % order.length];
      app.msg.hover({ id, poly: frac(parts[id]) });
      if (i % 4 === 3) setTimeout(() => app.msg.hover({ id, poly: frac(parts[id]), pressed: true }), 380);
      i++;
      mockTimer = setTimeout(step, 1300);
    };
    clearTimeout(mockTimer);
    step();
  }

  app = NZR.app('overlay', {
    escClose: false,
    init(el) {
      NZR.onCore('config', () => relabel(el));
      root = el;
      el.innerHTML = `
        <svg class="ov-hov" xmlns="http://www.w3.org/2000/svg"><defs><filter id="ov-glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="2.2" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>
          <g class="ov-g"><path class="hal"/><path class="fil"/><path class="edg" filter="url(#ov-glow)"/><path class="tik"/></g>
          <g class="ov-g"><path class="hal"/><path class="fil"/><path class="edg" filter="url(#ov-glow)"/><path class="tik"/></g></svg>
        <div class="ov-tag"></div>
        <div class="ov-dock"><i class="ov-spine"></i><div class="ov-head">${NZR.icon('walkie')}<span>${L('ui.ov_title', 'Radio up')}</span></div><div class="ov-list"></div></div>
        <div class="ov-place"><div class="pl-card nzr-hud solid nzr-brk">
          <div class="pl-h"><span class="pl-ic">${NZR.icon('jammer')}</span><div class="pl-t"><span class="nzr-label">${L('ui.ov_place_label', 'Setting down')}</span><b></b></div><span class="pl-rot"></span></div>
          <div class="pl-st"><i class="pl-dot"></i><span class="pl-msg"></span><span class="pl-why"></span></div>
          <div class="pl-keys"></div></div></div>`;
      svg = el.querySelector('.ov-hov');
      [gA, gB] = svg.querySelectorAll('.ov-g');
      tag = el.querySelector('.ov-tag');
      dock = el.querySelector('.ov-dock');
      list = el.querySelector('.ov-list');
      place = el.querySelector('.ov-place');
      window.addEventListener('resize', () => { if (cur) clearHover(); });
    },
    open(d) {
      const h = hintList(d || {});
      renderHints(h);
      dock.classList.remove('on');
      void dock.offsetWidth;
      dock.classList.toggle('on', h.length > 0);
    },
    close() {
      dock.classList.remove('on');
      clearHover();
      // a placement card that is still up keeps the section visible
      if (place.classList.contains('on')) showSection();
    },
    msg: {
      hints(d) { const h = hintList(d || {}); renderHints(h); dock.classList.toggle('on', h.length > 0 && keysUp()); },
      hover(d) { hover(d || {}); },
      place(d) { placeShow(d || {}); },
      placeHide() { placeHide(); },
    },
    preview() {
      mock();
      NZR.demo('overlay', { hints: DEFAULT_HINTS });
      const hints = [{ keys: ['E'], label: 'Set it down' }, { keys: ['WHEEL'], label: 'Turn' }, { keys: ['ARROWS'], label: 'Turn slowly' }, { keys: ['BACK', 'RMB'], label: 'Put it away' }];
      let hd = 128, ok = true, n = 0;
      setTimeout(() => app.msg.place({ title: 'JX-40 · Field case', valid: true, heading: hd, hints }), 450);
      setInterval(() => {
        n++; hd = (hd + 37) % 360;
        if (n % 3 === 0) ok = !ok;
        app.msg.place({ title: 'JX-40 · Field case', valid: ok, reason: ok ? '' : 'Ground too steep', heading: hd, hints });
      }, 1500);
    },
  });
})();
