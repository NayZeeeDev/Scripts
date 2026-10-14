/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · UI kit + app router
   Loaded after core/nz-core.js (window.NZ).

   ROUTER
     NZA.app(name, def)        register an app (renders into <section id="app-<name>">)
       def.init(el)            once, when registered
       def.open(data)          on action 'open' (Lua NZA.UI.Open)
       def.close()             on action 'close' or NZA.close(name)
       def.msg = { action(data) }   any other action
       def.keys = { Escape(e), Enter(e), ' '(e), KeyF(e), ... }   keydown (by e.key, then e.code)
       def.keysUp = { ... }    keyup
       def.escClose            default true: Escape closes the app
       def.full                true: the whole screen captures the mouse
       def.preview()           browser demo (index.html?app=<name>)
     NZA.post('<app>:<event>', data) → Promise     NZA.close(name)    NZA.demo(name, data)
     NZA.mock('<app>:<event>', fnOrValue)          preview-only replies for NZA.post

   KIT  NZA.ui.ProcPanel · FlipClock · Hold · Segmented · Toggle · Slider · Chips · Modal
        Win · Anchors · Marker · Meter · KeyHints
        NZA.toast · NZA.speech · NZA.prompt · NZA.audio · NZA.fmt · NZA.t · NZA.icon
   ═══════════════════════════════════════════════════════════ */
(() => {
  const NZ = window.NZ;
  const inGame = NZ.inGame;
  const resource = NZ.resource === 'nz-preview' ? 'nayzeee-ambulance' : NZ.resource;
  const apps = {};
  const stack = [];         // open apps, last = top
  const mocks = {};
  let locale = {};
  let cfg = { font: 'Lexend', shape: 'cut', scale: 1, sounds: true, signature: true };
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const esc = NZ.esc;
  const clamp = (n, a, b) => Math.max(a, Math.min(b, n));

  /* ─────────────── icons: medical additions in the NAYZEEE stroke style ─────────────── */
  NZ.addIcons({
    'bone': '<path d="M7.5 4.5a2.2 2.2 0 0 0-3 3l1.6 1.6-1.6 1.6a2.2 2.2 0 1 0 3 3l1.6-1.6 5.8 5.8-1.6 1.6a2.2 2.2 0 1 0 3 3l1.6-1.6 1.6 1.6a2.2 2.2 0 1 0 3-3"/><path d="M7.5 4.5 9.1 6.1"/>',
    'lungs': '<path d="M12 4v7M12 11l-3 2M12 11l3 2"/><path d="M9 8.5C6.5 8.5 4 11 4 15.5v3.2c0 .9.7 1.3 1.5 1L9 18V8.5zM15 8.5c2.5 0 5 2.5 5 7v3.2c0 .9-.7 1.3-1.5 1L15 18V8.5z"/>',
    'stetho': '<path d="M6 3v5a4 4 0 0 0 8 0V3"/><path d="M10 12v3a5 5 0 0 0 10 0v-2"/><circle cx="20" cy="11" r="2"/><path d="M5 3h2M13 3h2"/>',
    'xray': '<rect x="3.5" y="3.5" width="17" height="17" rx="1.5"/><path d="M12 6v12M8.5 9h7M8 12h8M8.5 15h7"/>',
    'scan': '<path d="M4 9V5h4M20 9V5h-4M4 15v4h4M20 15v4h-4"/><path d="M8 12h8"/>',
    'probe': '<path d="M9 3h6l1 8H8z"/><path d="M8 11c0 4 1.5 7 4 10 2.5-3 4-6 4-10"/>',
    'bed': '<path d="M3 18V7M21 18v-5a3 3 0 0 0-3-3h-8v5"/><path d="M3 14h18"/><circle cx="6.5" cy="10.5" r="1.6"/>',
    'ambulance': '<path d="M3 17V8a1 1 0 0 1 1-1h10v10M14 10h4l3 3.5V17h-2"/><path d="M6 17h8"/><circle cx="7.5" cy="17.5" r="1.7"/><circle cx="17" cy="17.5" r="1.7"/><path d="M8.5 9.5v4M6.5 11.5h4"/>',
    'wheelchair': '<circle cx="10" cy="4.5" r="1.6"/><path d="M10 8v6h5l2.5 5"/><path d="M10 11h5"/><path d="M7.5 11.2A5.5 5.5 0 1 0 15 18"/>',
    'crutch': '<path d="M8 3h5M10.5 3v18M8.5 9h4"/><path d="M9 21h3"/>',
    'burst': '<path d="M12 3l1.6 5 4.9-2-2.8 4.5L21 12l-5.3 1.5 2.8 4.5-4.9-2L12 21l-1.6-5-4.9 2 2.8-4.5L3 12l5.3-1.5L5.5 6l4.9 2z"/>',
    'cut': '<path d="M4 20 20 4"/><path d="M7 17l-2-2M10 14l-2-2M13 11l-2-2M16 8l-2-2"/>',
    'scrape': '<path d="M4 9h16M4 13h12M4 17h8"/>',
    'bruise': '<circle cx="12" cy="12" r="7.5"/><circle cx="12" cy="12" r="3.5"/>',
    'crosshair': '<circle cx="12" cy="12" r="7.5"/><path d="M12 2v5M12 17v5M2 12h5M17 12h5"/>',
    'bloodbag': '<path d="M7 4h10v11a5 5 0 0 1-10 0z"/><path d="M12 20v2M10 4V2.5h4V4"/><path d="M7 11h10"/>',
    'iv': '<path d="M8 3h8v9a4 4 0 0 1-8 0z"/><path d="M12 16v3M12 19c0 2 2 2 3 2h3"/><path d="M8 8h8"/>',
    'defib': '<rect x="3" y="6" width="18" height="12" rx="2"/><path d="M13 8.5l-3 4h4l-3 4"/>',
    'ecg': '<path d="M3 12h4l2-5 3 10 2.5-7 1.5 2h5"/>',
    'pager': '<rect x="4" y="5" width="16" height="13" rx="2.5"/><rect x="7" y="8" width="10" height="5" rx="1"/><path d="M8 15.5h2M14 15.5h2"/>',
    'ticket': '<path d="M4 6h16v4a2 2 0 0 0 0 4v4H4v-4a2 2 0 0 0 0-4z"/><path d="M13 6v12" stroke-dasharray="2 2"/>',
    'cross': '<path d="M9.5 3.5h5v6h6v5h-6v6h-5v-6h-6v-5h6z"/>',
    'scalpel': '<path d="M3 21l8-8"/><path d="M11 13l2.5-2.5c2-2 4.5-3.5 7.5-4-0.5 3-2 5.5-4 7.5L14.5 16.5z"/>',
    'forceps': '<path d="M7 3l5 11M17 3l-5 11M12 14v7"/><path d="M9 9h6"/>',
    'needle': '<path d="M4 20 16 8"/><path d="M14 4h6v6"/><path d="M16 8l2-2"/>',
    'gauze': '<rect x="4" y="4" width="16" height="16" rx="1.5"/><path d="M4 9h16M4 15h16M9 4v16M15 4v16" opacity=".55"/>',
    'splint': '<path d="M8 3h8v18H8z"/><path d="M6 7h12M6 12h12M6 17h12"/>',
    'collar': '<path d="M5 9c0-2 3-4 7-4s7 2 7 4v5c0 2-3 4-7 4s-7-2-7-4z"/><path d="M5 11.5c2 1.3 4.4 2 7 2s5-.7 7-2"/>',
    'tube': '<path d="M5 19c3-3 3-7 6-10s6-3 8-5"/><circle cx="5" cy="19" r="1.5"/>',
    'skull': '<path d="M5 11a7 7 0 1 1 14 0v3l-2 1v3h-2.5v-2h-1v2h-3v-2h-1v2H7v-3l-2-1z"/><circle cx="9.3" cy="11.5" r="1.4"/><circle cx="14.7" cy="11.5" r="1.4"/>',
    'monitor': '<rect x="3" y="4" width="18" height="13" rx="1.5"/><path d="M5.5 11h3l1.5-3 2.5 6 1.5-3h4.5"/><path d="M9 20h6"/>',
    'kit': '<rect x="3" y="7" width="18" height="13" rx="1.5"/><path d="M9 7V4h6v3"/><path d="M12 10.5v6M9 13.5h6"/>',
    'lightbox': '<rect x="4" y="3" width="16" height="13" rx="1"/><path d="M12 16v5M8 21h8"/><path d="M9 6v7M15 6v7M12 6v7" opacity=".55"/>',
    'snow': '<path d="M12 3v18M4.2 7.5l15.6 9M4.2 16.5l15.6-9"/>',
    'chair': '<path d="M7 3v9h9l2 9M7 12l-2 9M9 16h7"/>',
    'clamp': '<path d="M6 3l6 9 6-9M12 12v9"/><circle cx="12" cy="12" r="1.5"/>',
    'blanket': '<path d="M4 6h16v12H4z"/><path d="M4 10l16 4M4 14l16-6" opacity=".55"/>',
    'helmet': '<path d="M4 15a8 8 0 0 1 16 0v2H4z"/><path d="M12 7v6"/>',
  });
  const icon = (n, cls) => NZ.icon(n, cls);

  /* ─────────────── helpers ─────────────── */
  const fmt = {
    time(sec) { sec = Math.max(0, Math.floor(sec || 0)); const m = Math.floor(sec / 60), s = sec % 60; return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`; },
    num(n, d = 0) { if (n === null || n === undefined || isNaN(n)) return '--'; return Number(n).toFixed(d); },
    pct(n, d = 0) { return `${fmt.num(n * 100, d)}%`; },
    money: NZ.money,
  };
  const t = (key, fallback) => (locale[key] !== undefined ? locale[key] : (fallback !== undefined ? fallback : key));

  // "Hold {Click} to run saline over the **burn**" → key caps + bold
  const rich = s => esc(s ?? '')
    .replace(/\{([^}]{1,24})\}/g, (_, k) => `<kbd>${k}</kbd>`)
    .replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>');

  const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html !== undefined) e.innerHTML = html; return e; };

  /* ─────────────── zoom / config ─────────────── */
  function applyZoom() {
    const auto = clamp(window.innerHeight / 1080, 0.75, 2.2);
    const z = clamp((cfg.scale || 1) * auto, 0.6, 2.6);
    document.documentElement.style.setProperty('--nza-zoom', z.toFixed(3));
    NZA.zoom = z;
  }
  window.addEventListener('resize', applyZoom);
  function applyConfig(c) {
    cfg = Object.assign(cfg, c || {});
    document.documentElement.classList.toggle('font-inter', String(cfg.font).toLowerCase() === 'inter');
    if (cfg.shape) NZ.shape(cfg.shape);
    if (c && c.locale) locale = Object.assign(locale, c.locale);
    applyZoom();
  }

  /* ─────────────── NUI bridge ─────────────── */
  async function post(name, data = {}) {
    if (!inGame) {
      const m = mocks[name];
      console.info('[nza] →', name, data);
      if (typeof m === 'function') return m(data);
      return m !== undefined ? m : { ok: true };
    }
    try {
      const res = await fetch(`https://${resource}/${name}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data),
      });
      const txt = await res.text();
      try { return JSON.parse(txt); } catch { return txt; }
    } catch { return null; }
  }

  /* ─────────────── router ─────────────── */
  function app(name, def) {
    def.name = name;
    def.el = document.getElementById(`app-${name}`);
    if (!def.el) {
      def.el = el('section', 'nza-app');
      def.el.id = `app-${name}`;
      def.el.dataset.app = name;
      document.getElementById('nza-root').appendChild(def.el);
    }
    if (def.full) def.el.classList.add('nza-full');
    if (def.noscale) def.el.classList.add('noscale');
    def.anchors = { map: {}, fns: [] };
    apps[name] = def;
    try { def.init && def.init(def.el); } catch (e) { console.error(`[nza] ${name}.init`, e); }
    return def;
  }

  function isOpen(name) { return stack.includes(name); }

  function open(name, data) {
    const a = apps[name];
    if (!a) return console.warn('[nza] unknown app', name);
    if (!isOpen(name)) stack.push(name);
    a.el.classList.add('nza-on');
    audio.unlock();
    try { a.open && a.open(data || {}); } catch (e) { console.error(`[nza] ${name}.open`, e); }
  }

  function close(name, notify = true) {
    const a = apps[name];
    if (!a) return;
    const i = stack.indexOf(name);
    if (i === -1 && !a.el.classList.contains('nza-on')) return;
    if (i !== -1) stack.splice(i, 1);
    a.el.classList.remove('nza-on');
    try { a.close && a.close(); } catch (e) { console.error(`[nza] ${name}.close`, e); }
    clearMarkers(name);
    if (notify) post(`${name}:close`, {});
    if (!inGame && notify && previewApp === name) showReopen(name);
  }

  window.addEventListener('message', e => {
    const d = e.data;
    if (!d || typeof d !== 'object' || !d.app) return;
    const data = d.data !== undefined ? d.data : {};
    if (d.app === '_core') return core(d.action, data);
    const a = apps[d.app];
    if (!a) return;
    if (d.action === 'open') return open(d.app, data);
    if (d.action === 'close') return close(d.app, false);
    if (d.action === 'anchors') {
      a.anchors.map = data || {};
      a.anchors.fns.forEach(fn => { try { fn(a.anchors.map); } catch (err) { console.error(err); } });
      moveMarkers(d.app);
    }
    const h = a.msg && a.msg[d.action];
    if (h) { try { h(data); } catch (err) { console.error(`[nza] ${d.app}.${d.action}`, err); } }
  });

  function core(action, data) {
    switch (action) {
      case 'config': return applyConfig(data);
      case 'toast': return toast(data);
      case 'speech': return speech(data);
      case 'prompt': return prompt(data.id || 'default', data);
      case 'promptHide': return promptHide(data.id || 'default');
      case 'closeAll': return [...stack].forEach(n => close(n, false));
      case 'sound': return audio.play(data.name, data);
      case 'locale': locale = Object.assign(locale, data || {}); return;
      case 'focus': {   // Lua focus stack → the focused app gets keyboard priority
        const top = data && data.top;
        const i = top ? stack.indexOf(top) : -1;
        if (i !== -1 && i !== stack.length - 1) { stack.splice(i, 1); stack.push(top); }
        return;
      }
    }
  }

  /* keys go to the top-most open app that handles them */
  function keyHandler(map, e) {
    for (let i = stack.length - 1; i >= 0; i--) {
      const a = apps[stack[i]];
      const h = a && a[map] && (a[map][e.key] || a[map][e.code]);
      if (h) { const r = h(e); if (r !== false) { e.preventDefault(); return; } }
      if (map === 'keys' && e.key === 'Escape' && a && a.escClose !== false && i === stack.length - 1) { close(a.name); e.preventDefault(); return; }
      if (a && a.modalKeys) return;   // apps that own the keyboard stop propagation to apps below
    }
  }
  window.addEventListener('keydown', e => { if (e.repeat && e.key !== ' ' && !/^(Arrow|Key)/.test(e.key + e.code)) return; keyHandler('keys', e); });
  window.addEventListener('keyup', e => keyHandler('keysUp', e));

  /* ─────────────── camera input → Lua NZA.Cam (client/core/cam.lua) ───────────────
     With full NUI focus the game can't read the mouse, so right-drag / wheel are forwarded.
     An app opts out with def.camInput = false, or by calling e.preventDefault() in its own
     mousedown/wheel handler. R = recentre only for apps with def.camInput === true. */
  const cam = { down: false, dx: 0, dy: 0, wheel: 0, pan: false, raf: 0 };
  const camApp = () => { const n = stack[stack.length - 1]; return n ? apps[n] : null; };
  const camOk = () => { const a = camApp(); return inGame && a && a.camInput !== false; };
  const camFlush = () => {
    cam.raf = 0;
    if (!cam.dx && !cam.dy && !cam.wheel) return;
    post('_core:camInput', { dx: cam.dx, dy: cam.dy, wheel: cam.wheel, pan: cam.pan });
    cam.dx = 0; cam.dy = 0; cam.wheel = 0;
  };
  const camQueue = () => { if (!cam.raf) cam.raf = requestAnimationFrame(camFlush); };
  window.addEventListener('mousedown', e => { if (e.button === 2 && !e.defaultPrevented && camOk()) cam.down = true; });
  window.addEventListener('mouseup', e => { if (e.button === 2) cam.down = false; });
  window.addEventListener('contextmenu', e => e.preventDefault());
  window.addEventListener('mousemove', e => {
    if (!cam.down) return;
    cam.dx += e.movementX / window.innerWidth; cam.dy += e.movementY / window.innerHeight; cam.pan = e.shiftKey; camQueue();
  });
  window.addEventListener('wheel', e => {
    if (e.defaultPrevented || !camOk()) return;
    if (e.target && e.target.closest && e.target.closest('.nza-scroll,.w-pbody,.w-side,input,select,textarea,[data-wheel]')) return;
    cam.wheel += Math.sign(e.deltaY); camQueue();
  });
  window.addEventListener('keydown', e => {
    const a = camApp();
    if (inGame && a && a.camInput === true && (e.key === 'r' || e.key === 'R') && !e.repeat) post('_core:camInput', { recenter: true });
  });

  /* ─────────────── toasts ─────────────── */
  const TOAST_ICON = { success: 'check', error: 'x', warning: 'alert', info: 'info' };
  function toast({ title, message, type = 'success', duration = 4500, icon: ic, grade } = {}) {
    const layer = document.getElementById('nza-layer-toasts');
    if (!layer) return;
    const n = el('div', `note ${type === 'success' ? '' : type}`);
    const badge = grade ? `<span class="grade g-${esc(grade)}" style="width:30px;height:30px;font-size:15px;border-radius:9px;flex:none;box-shadow:none">${esc(grade)}</span>` : `<span class="ni">${icon(ic || TOAST_ICON[type] || 'info')}</span>`;
    n.innerHTML = `${badge}<div>${title ? `<b>${esc(title)}</b>` : ''}${message ? `<p>${esc(message)}</p>` : ''}</div><i class="bar"></i>`;
    const bar = n.querySelector('.bar');
    bar.animate([{ transform: 'scaleX(1)' }, { transform: 'scaleX(0)' }], { duration, easing: 'linear', fill: 'forwards' });
    layer.appendChild(n);
    while (layer.children.length > 5) layer.firstChild.remove();
    setTimeout(() => { n.classList.add('out'); setTimeout(() => n.remove(), 230); }, duration);
    if (cfg.sounds) audio.click(type === 'error' ? 260 : 660);
  }

  /* ─────────────── speech (patient subtitles) ─────────────── */
  let speechTimer = null;
  function speech({ name, text, ms } = {}) {
    const layer = document.getElementById('nza-layer-speech');
    if (!layer || !text) return;
    layer.innerHTML = '';
    const s = el('div', 'speech nza-hud solid');
    s.innerHTML = `<span class="who">${esc(t('ui.patient', 'Patient'))} · <b>${esc(name || '')}</b></span><span class="txt">${esc(text)}</span>`;
    layer.appendChild(s);
    clearTimeout(speechTimer);
    speechTimer = setTimeout(() => { s.classList.add('out'); setTimeout(() => s.remove(), 200); }, ms || Math.max(2600, text.length * 75));
  }

  /* ─────────────── prompts ([E] Check in · Check-in Desk) ─────────────── */
  const prompts = {};
  function prompt(id, { key = 'E', label = '', sub = '', progress = null, tone = '' } = {}) {
    const layer = document.getElementById('nza-layer-prompt');
    let p = prompts[id];
    if (!p) { p = el('div', 'prompt nza-hud solid'); layer.appendChild(p); prompts[id] = p; }
    const ring = progress !== null && progress !== undefined
      ? `<span class="ring"><svg viewBox="0 0 26 26"><circle cx="13" cy="13" r="11" stroke="rgba(255,255,255,.12)"/><circle cx="13" cy="13" r="11" stroke="${tone === 'red' ? 'var(--red)' : 'var(--teal)'}" stroke-dasharray="${(progress * 69.1).toFixed(1)} 69.1"/></svg><kbd style="position:absolute;inset:3px;min-width:0;height:auto;font-size:10px">${esc(key)}</kbd></span>`
      : `<kbd class="${tone}">${esc(key)}</kbd>`;
    p.innerHTML = `${ring}<span class="t">${esc(label)}${sub ? ` <span>· ${esc(sub)}</span>` : ''}</span>`;
  }
  function promptHide(id) { if (prompts[id]) { prompts[id].remove(); delete prompts[id]; } }

  /* ─────────────── audio (WebAudio synth, no files) ─────────────── */
  const audio = (() => {
    let ctx = null, master = null;
    const ok = () => cfg.sounds !== false;
    function ac() {
      if (!ctx) {
        const C = window.AudioContext || window.webkitAudioContext;
        if (!C) return null;
        ctx = new C(); master = ctx.createGain(); master.gain.value = 0.7; master.connect(ctx.destination);
      }
      return ctx;
    }
    function unlock() { const c = ac(); if (c && c.state === 'suspended') c.resume(); }
    function tone(freq, ms, { vol = 0.12, type = 'sine', at = 0, slide = null } = {}) {
      if (!ok()) return; const c = ac(); if (!c) return;
      const o = c.createOscillator(), g = c.createGain(), t0 = c.currentTime + at;
      o.type = type; o.frequency.setValueAtTime(freq, t0);
      if (slide) o.frequency.exponentialRampToValueAtTime(slide, t0 + ms / 1000);
      g.gain.setValueAtTime(0, t0); g.gain.linearRampToValueAtTime(vol, t0 + 0.008);
      g.gain.exponentialRampToValueAtTime(0.0001, t0 + ms / 1000);
      o.connect(g); g.connect(master); o.start(t0); o.stop(t0 + ms / 1000 + 0.02);
    }
    function noise(ms, { vol = 0.12, lp = 1200, hp = 120, at = 0, attack = 0.05, release = 0.2 } = {}) {
      if (!ok()) return; const c = ac(); if (!c) return;
      const len = Math.floor(c.sampleRate * ms / 1000), buf = c.createBuffer(1, len, c.sampleRate), d = buf.getChannelData(0);
      for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
      const s = c.createBufferSource(); s.buffer = buf;
      const f1 = c.createBiquadFilter(); f1.type = 'lowpass'; f1.frequency.value = lp;
      const f2 = c.createBiquadFilter(); f2.type = 'highpass'; f2.frequency.value = hp;
      const g = c.createGain(), t0 = c.currentTime + at, dur = ms / 1000;
      g.gain.setValueAtTime(0, t0); g.gain.linearRampToValueAtTime(vol, t0 + dur * attack);
      g.gain.setValueAtTime(vol, t0 + dur * (1 - release)); g.gain.linearRampToValueAtTime(0, t0 + dur);
      s.connect(f1); f1.connect(f2); f2.connect(g); g.connect(master); s.start(t0); s.stop(t0 + dur + 0.02);
    }
    const api = {
      unlock, tone, noise,
      beep: (f = 880, ms = 90, vol = 0.12) => tone(f, ms, { vol }),
      click: (f = 660) => tone(f, 40, { vol: 0.05, type: 'triangle' }),
      tick: () => tone(1500, 18, { vol: 0.04, type: 'square' }),
      heartbeat: (spo2 = 98) => tone(clamp(440 + (spo2 - 80) * 14, 300, 760), 70, { vol: 0.09 }),
      alarm: (level = 1) => { const f = level >= 2 ? 960 : 700; for (let i = 0; i < (level >= 2 ? 3 : 2); i++) tone(f, 140, { vol: 0.1, type: 'square', at: i * 0.2 }); },
      charge: (ms = 2400) => tone(500, ms, { vol: 0.08, type: 'sine', slide: 2300 }),
      ready: () => { for (let i = 0; i < 3; i++) tone(1800, 120, { vol: 0.08, at: i * 0.25 }); },
      shock: () => { noise(260, { vol: 0.35, lp: 900, hp: 40, attack: 0.02, release: 0.6 }); tone(70, 300, { vol: 0.35, type: 'sine', slide: 40 }); },
      pager: () => { [0, 0.16, 0.32, 0.7, 0.86, 1.02].forEach((a, i) => tone(i % 2 ? 2600 : 3100, 110, { vol: 0.07, type: 'square', at: a })); },
      success: () => { tone(660, 90, { vol: 0.08 }); tone(990, 140, { vol: 0.08, at: 0.1 }); },
      fail: () => { tone(320, 160, { vol: 0.1, type: 'triangle' }); tone(220, 220, { vol: 0.1, type: 'triangle', at: 0.15 }); },
      play(name, data) { const f = api[name]; if (typeof f === 'function') f(...(Array.isArray(data && data.args) ? data.args : [])); },
    };
    return api;
  })();

  /* ═══════════════════════════ COMPONENTS ═══════════════════════════ */

  /* ── Hold-to-confirm: hold a key (or press the element) for `seconds` ── */
  function Hold({ key = 'Escape', code = null, seconds = 1.2, el: target = null, onDone, onProgress } = {}) {
    let start = 0, raf = 0, active = false, armed = true, fired = false;
    const tick = () => {
      const p = clamp((performance.now() - start) / (seconds * 1000), 0, 1);
      onProgress && onProgress(p);
      if (target) target.style.setProperty('--hold', p);
      if (p >= 1) { if (!fired) { fired = true; active = false; onDone && onDone(); } return; }
      raf = requestAnimationFrame(tick);
    };
    const begin = () => { if (!armed || active) return; active = true; fired = false; start = performance.now(); tick(); };
    const end = () => { if (!active) return; active = false; cancelAnimationFrame(raf); onProgress && onProgress(0); if (target) target.style.setProperty('--hold', 0); };
    const kd = e => { if (e.key === key || (code && e.code === code)) { if (!e.repeat) begin(); e.preventDefault(); } };
    const ku = e => { if (e.key === key || (code && e.code === code)) end(); };
    window.addEventListener('keydown', kd, true); window.addEventListener('keyup', ku, true);
    if (target) { target.addEventListener('mousedown', begin); window.addEventListener('mouseup', end); }
    return {
      arm(v) { armed = v; if (!v) end(); },
      destroy() { end(); window.removeEventListener('keydown', kd, true); window.removeEventListener('keyup', ku, true); if (target) { target.removeEventListener('mousedown', begin); window.removeEventListener('mouseup', end); } },
    };
  }

  /* ── Meter: { value 0..1, zone [a,b], mark 0..1, tone } ── */
  function meterHTML(m = {}) {
    const v = clamp(m.value ?? 0, 0, 1);
    const zone = m.zone ? `<span class="zone" style="left:${m.zone[0] * 100}%;width:${(m.zone[1] - m.zone[0]) * 100}%"></span>` : '';
    const mark = m.mark !== undefined && m.mark !== null ? `<span class="mark" style="left:${clamp(m.mark, 0, 1) * 100}%"></span>` : '';
    const fill = m.noFill ? '' : `<i style="width:${v * 100}%"></i>`;
    return `<div class="mtr ${m.tone || ''} ${m.lg ? 'lg' : ''} ${m.segs ? 'segs' : ''}">${fill}${zone}${mark}</div>`;
  }
  function Meter(host, m) { host.innerHTML = meterHTML(m); return { set(n) { host.innerHTML = meterHTML(Object.assign(m, n)); } }; }

  /* ── Procedure panel (bottom centre, every minigame) ── */
  function ProcPanel(host, opts = {}) {
    const root = el('div', 'pp nza-hud solid nza-int');
    host.appendChild(root);
    let o = Object.assign({ step: 1, total: 1, tag: '', title: '', text: '', stats: [], wide: null, tools: [], hints: [], abort: { label: t('ui.holdAbort', 'Hold to abort'), key: 'ESC', seconds: 1.2 } }, opts);
    let flashTimer = null, hold = null, doneHandler = null;

    root.innerHTML = `
      <div class="pp-top">
        <div class="pp-left">
          <div class="pp-step"><span class="n"></span><span class="pp-segs"></span><span class="pp-tag"></span></div>
          <div class="pp-title"></div>
          <div class="pp-text"></div>
          <div class="pp-flash"></div>
        </div>
        <div class="pp-right"><div class="pp-stats"></div><div class="pp-wide"></div></div>
      </div>
      <div class="pp-bot"><div class="pp-tools" style="display:flex;gap:8px;flex-wrap:wrap"></div><div class="pp-hints"></div><div class="pp-abort"><span class="fill"></span><kbd></kbd><span class="al"></span></div></div>`;
    const q = s => root.querySelector(s);

    function renderStep() {
      q('.pp-step .n').innerHTML = `<b>${o.step}</b>/${o.total}`;
      q('.pp-segs').innerHTML = Array.from({ length: o.total }, (_, i) => `<i class="${i + 1 < o.step ? 'done' : i + 1 === o.step ? 'cur' : ''}"></i>`).join('');
      q('.pp-tag').textContent = o.tag || '';
    }
    function renderText() {
      const ti = q('.pp-title');
      ti.textContent = o.title || '';
      ti.className = `pp-title ${o.titleTone || ''}`;
      q('.pp-text').innerHTML = rich(o.text);
    }
    function renderStats() {
      const right = q('.pp-right');
      const hasStats = (o.stats && o.stats.length) || o.wide;
      right.style.display = hasStats ? '' : 'none';
      q('.pp-stats').innerHTML = (o.stats || []).map(s => `
        <div class="pp-stat" data-id="${esc(s.id || '')}">
          <div class="l">${esc(s.label)}</div>
          <div class="v ${s.small ? 'sm' : ''} ${s.tone || ''}">${esc(s.value ?? '--')}${s.unit ? `<span class="u">${esc(s.unit)}</span>` : ''}</div>
          ${s.meter ? `<div class="m">${meterHTML(s.meter)}</div>` : ''}
        </div>`).join('');
      const w = o.wide;
      const wide = q('.pp-wide');
      wide.style.display = w ? '' : 'none';
      if (w) {
        wide.innerHTML = `
          <div class="pp-stat"><div class="l">${esc(w.label)}</div></div>
          <div class="row"><div class="pp-stat"><div class="v ${w.tone || ''}" style="font-size:26px">${esc(w.value ?? '--')}${w.unit ? `<span class="u">${esc(w.unit)}</span>` : ''}</div></div>
          <div class="meter">${w.meter ? meterHTML(Object.assign({ lg: true }, w.meter)) : ''}</div></div>
          ${w.caption ? `<div class="cap ${w.captionTone || ''}">${rich(w.caption)}</div>` : ''}`;
      }
    }
    function renderTools() {
      const box = q('.pp-tools');
      box.innerHTML = (o.tools || []).map(tl => {
        const ic = tl.img ? `<span class="ico"><img src="${esc(tl.img)}" alt=""></span>` : tl.icon ? `<span class="ico">${icon(tl.icon)}</span>` : '';
        return `<button class="pp-tool ${tl.state || ''}" data-key="${esc(tl.key)}">${tl.key ? `<kbd>${esc(tl.key)}</kbd>` : ''}${ic}<span>${esc(tl.label)}${tl.sub ? `<span class="cnt" style="display:block;font-size:9px;letter-spacing:.08em">${esc(tl.sub)}</span>` : ''}</span>${tl.count ? `<span class="cnt">${esc(tl.count)}</span>` : ''}</button>`;
      }).join('');
      box.querySelectorAll('.pp-tool').forEach(b => b.addEventListener('click', () => o.onTool && o.onTool(b.dataset.key)));
    }
    function renderHints() {
      q('.pp-hints').innerHTML = (o.hints || []).map(h => `<span>${(h.keys || []).map(k => `<kbd>${esc(k)}</kbd>`).join('<span style="opacity:.6">+</span>')} ${esc(h.label)}</span>`).join('');
      const ab = q('.pp-abort');
      if (o.abort === false) { ab.style.display = 'none'; return; }
      ab.style.display = '';
      q('.pp-abort kbd').textContent = o.abort.key || 'ESC';
      q('.pp-abort .al').textContent = o.abort.label;
    }
    function armAbort() {
      if (hold) hold.destroy();
      if (o.abort === false || !o.onAbort) return;
      const fill = q('.pp-abort .fill');
      hold = Hold({ key: 'Escape', seconds: o.abort.seconds || 1.2, onProgress: p => { fill.style.width = `${p * 100}%`; }, onDone: () => o.onAbort && o.onAbort() });
    }
    renderStep(); renderText(); renderStats(); renderTools(); renderHints(); armAbort();

    const api = {
      el: root,
      set(n) {
        const prev = o; o = Object.assign({}, o, n);
        if ('step' in n || 'total' in n || 'tag' in n) renderStep();
        if ('title' in n || 'text' in n || 'titleTone' in n) renderText();
        if ('stats' in n || 'wide' in n) renderStats();
        if ('tools' in n) renderTools();
        if ('hints' in n || 'abort' in n) renderHints();
        if ('onAbort' in n && n.onAbort !== prev.onAbort) armAbort();
        return api;
      },
      // update one stat in place: pp.stat('bleed', { value: '2.4', tone: 'red' })
      stat(id, patch) { o.stats = (o.stats || []).map(s => (s.id === id ? Object.assign({}, s, patch) : s)); renderStats(); return api; },
      wide(patch) { o.wide = Object.assign({}, o.wide || {}, patch); renderStats(); return api; },
      tool(key, state) { o.tools = (o.tools || []).map(tl => (tl.key === key ? Object.assign({}, tl, { state }) : tl)); renderTools(); return api; },
      active(key) { o.tools = (o.tools || []).map(tl => Object.assign({}, tl, { state: tl.key === key ? 'active' : (tl.state === 'active' ? '' : tl.state) })); renderTools(); return api; },
      flash(type, text, ms = 2600) {
        const f = q('.pp-flash');
        f.className = `pp-flash on ${type}`; f.innerHTML = `${icon(type === 'ok' ? 'check' : type === 'bad' ? 'x' : 'alert')}<span>${rich(text)}</span>`;
        clearTimeout(flashTimer);
        if (ms) flashTimer = setTimeout(() => { f.className = 'pp-flash'; }, ms);
        return api;
      },
      // Show a finished state with a Done button (Enter)
      complete({ title, text, label = t('ui.done', 'Done'), onDone } = {}) {
        o.step = o.total; renderStep();
        api.set({ title: title || t('ui.complete', 'Complete'), titleTone: 'ok', text: text || '' });
        const box = q('.pp-tools');
        box.innerHTML = `<button class="pp-done"><kbd>Enter</kbd>${esc(label)}</button>`;
        doneHandler = onDone;
        box.querySelector('.pp-done').onclick = () => doneHandler && doneHandler();
        q('.pp-segs').querySelectorAll('i').forEach(i => { i.className = 'done'; });
        return api;
      },
      // digit keys → tools; Enter → done. Call from your app's keys handler: return pp.key(e)
      key(e) {
        if (e.key === 'Enter' && doneHandler) { doneHandler(); return true; }
        const tl = (o.tools || []).find(x => String(x.key).toLowerCase() === String(e.key).toLowerCase());
        if (tl && tl.state !== 'locked' && o.onTool) { o.onTool(tl.key); return true; }
        return false;
      },
      destroy() { if (hold) hold.destroy(); clearTimeout(flashTimer); root.remove(); },
    };
    return api;
  }

  /* ── Flip clock ── */
  function FlipClock(host, { value = '00:00', tone = '', small = false } = {}) {
    const root = el('div', `flip ${tone} ${small ? 'sm' : ''}`);
    host.appendChild(root);
    let cur = '';
    function set(v) {
      v = String(v);
      if (v.length !== cur.length) {
        root.innerHTML = [...v].map(ch => (ch === ':' ? '<span class="c">:</span>' : `<span class="d">${esc(ch)}</span>`)).join('');
      } else {
        const ds = [...root.children];
        [...v].forEach((ch, i) => { if (ch !== cur[i] && ds[i] && ds[i].classList.contains('d')) { ds[i].textContent = ch; ds[i].classList.remove('tick'); void ds[i].offsetWidth; ds[i].classList.add('tick'); } });
      }
      cur = v;
    }
    set(value);
    return { el: root, set, tone(tn) { root.className = `flip ${tn || ''} ${small ? 'sm' : ''} ${root.classList.contains('paused') ? 'paused' : ''}`; }, paused(p) { root.classList.toggle('paused', !!p); } };
  }

  /* ── Segmented / Toggle / Slider / Chips (HUD design controls) ── */
  function Segmented(host, { options = [], value, onChange } = {}) {
    const root = el('div', 'segc');
    root.innerHTML = options.map(op => `<button data-v="${esc(op.value)}" class="${op.value === value ? 'on' : ''}">${esc(op.label)}</button>`).join('');
    root.addEventListener('click', e => { const b = e.target.closest('button'); if (!b) return; root.querySelectorAll('button').forEach(x => x.classList.toggle('on', x === b)); onChange && onChange(b.dataset.v); });
    host.appendChild(root);
    return { el: root, set(v) { root.querySelectorAll('button').forEach(x => x.classList.toggle('on', x.dataset.v === String(v))); } };
  }
  function Toggle(host, { on = false, onChange } = {}) {
    const b = el('button', `tg ${on ? 'on' : ''}`, '<i></i>');
    b.addEventListener('click', () => { b.classList.toggle('on'); onChange && onChange(b.classList.contains('on')); });
    host.appendChild(b);
    return { el: b, set(v) { b.classList.toggle('on', !!v); }, get() { return b.classList.contains('on'); } };
  }
  function Slider(host, { min = 0, max = 100, step = 1, value = 50, format = v => v, onChange } = {}) {
    const root = el('div', 'rng', `<input type="range" min="${min}" max="${max}" step="${step}" value="${value}"><span></span>`);
    const inp = root.querySelector('input'), lab = root.querySelector('span');
    const upd = () => { lab.textContent = format(Number(inp.value)); };
    inp.addEventListener('input', () => { upd(); onChange && onChange(Number(inp.value)); });
    upd(); host.appendChild(root);
    return { el: root, set(v) { inp.value = v; upd(); }, get() { return Number(inp.value); } };
  }
  function Chips(host, { options = [], values = [], multi = true, onChange } = {}) {
    const sel = new Set(values);
    const root = el('div', 'chips');
    const render = () => {
      root.innerHTML = options.map(op => `<button class="chipx ${sel.has(op.value) ? 'on' : ''}" data-v="${esc(op.value)}">${op.icon ? icon(op.icon) : ''}${esc(op.label)}</button>`).join('');
    };
    root.addEventListener('click', e => {
      const b = e.target.closest('.chipx'); if (!b) return;
      const v = b.dataset.v;
      if (multi) { sel.has(v) ? sel.delete(v) : sel.add(v); } else { sel.clear(); sel.add(v); }
      render(); onChange && onChange([...sel]);
    });
    render(); host.appendChild(root);
    return { el: root, set(vs) { sel.clear(); vs.forEach(v => sel.add(v)); render(); }, get() { return [...sel]; } };
  }

  /* ── Modal ── */
  function Modal({ title = '', text = '', icon: ic = 'alert', tone = 'red', actions = [], host } = {}) {
    const wrap = el('div', 'nza-modal-wrap');
    wrap.innerHTML = `<div class="nza-modal nza-pop"><div class="mb"><div class="ic ${tone === 'teal' ? 'teal' : ''}">${icon(ic)}</div><div><h4>${esc(title)}</h4><p>${rich(text)}</p></div></div><div class="mf"></div></div>`;
    const f = wrap.querySelector('.mf');
    const closeM = () => wrap.remove();
    actions.forEach(a => {
      const b = el('button', `btn-${a.kind || 'line'}`, esc(a.label));
      b.onclick = () => { const r = a.onClick && a.onClick(); if (r !== false) closeM(); };
      f.appendChild(b);
    });
    (host || document.getElementById('nza-root')).appendChild(wrap);
    wrap.style.pointerEvents = 'auto';
    return { close: closeM, el: wrap };
  }

  /* ── Window shell (UI v5) ── */
  function Win(host, o = {}) {
    const w = el('div', 'nza-win nza-int');
    if (o.width) w.style.width = o.width;
    if (o.height) w.style.height = o.height;
    w.innerHTML = `
      <div class="w-shell">
        <div class="w-bar">
          <div class="w-brand"><div class="nz-mark"></div><div><div class="t"></div><div class="s"></div></div></div>
          <div class="w-mid"></div>
          <div class="w-act"></div>
          <button class="pill-close">${esc(t('ui.close', 'Close'))}</button>
        </div>
        <div class="w-body ${o.nav ? '' : 'noside'}">${o.nav ? '<nav class="w-side"></nav>' : ''}<main class="w-main"></main></div>
        <div class="w-status"></div>
      </div>`;
    host.appendChild(w);
    const q = s => w.querySelector(s);
    q('.w-brand .t').textContent = o.title || '';
    q('.w-brand .s').textContent = o.sub || '';
    let navValue = o.navValue;
    const api = {
      el: w, main: q('.w-main'), side: q('.w-side'), act: q('.w-act'),
      setMid(html) { q('.w-mid').innerHTML = html; return api; },
      setStatus(keys = [], extra = '') {
        q('.w-status').innerHTML = keys.map(k => `<span><span class="key">${esc(k.key)}</span>${esc(k.label)}</span>`).join('') + (extra || '') +
          (cfg.signature !== false ? '<span class="nz-sig"><span class="nz-mark xs"></span>NAYZEEE</span>' : '');
        return api;
      },
      setNav(items, value) {
        if (!api.side) return api;
        if (value !== undefined) navValue = value;
        api.side.innerHTML = (o.navTop || '') + items.map(n => (n.group
          ? `<div class="w-grp">${esc(n.group)}</div>`
          : `<button class="w-nav ${n.id === navValue ? 'on' : ''}" data-id="${esc(n.id)}">${icon(n.icon || 'grid')}<span>${esc(n.label)}</span>${n.tally !== undefined && n.tally !== null ? `<span class="tally">${esc(n.tally)}</span>` : ''}</button>`)).join('');
        api.side.querySelectorAll('.w-nav').forEach(b => b.addEventListener('click', () => {
          navValue = b.dataset.id;
          api.side.querySelectorAll('.w-nav').forEach(x => x.classList.toggle('on', x === b));
          o.onNav && o.onNav(navValue);
        }));
        o.navItems = items;
        return api;
      },
      nav(id) { navValue = id; if (o.navItems) api.setNav(o.navItems); return api; },
      destroy() { w.remove(); },
    };
    q('.pill-close').onclick = () => o.onClose && o.onClose();
    if (o.mid) api.setMid(o.mid);
    if (o.nav) api.setNav(o.nav, navValue);
    api.setStatus(o.status || [{ key: 'ESC', label: t('ui.close', 'Close') }]);
    return api;
  }

  /* ── Anchors & world markers ── */
  function Anchors(name) {
    const a = apps[name];
    return {
      on(fn) { a.anchors.fns.push(fn); return fn; },
      off(fn) { a.anchors.fns = a.anchors.fns.filter(f => f !== fn); },
      get(id) { return a.anchors.map[id]; },
      all() { return a.anchors.map; },
    };
  }
  const markers = {};   // app → { id → { el, opts } }
  function Marker(name, id, opts = {}) {
    const layer = document.getElementById('nza-layer-anchors');
    markers[name] = markers[name] || {};
    let m = markers[name][id];
    if (!m) { m = { el: el('div', 'anc hide') }; layer.appendChild(m.el); markers[name][id] = m; }
    m.opts = Object.assign(m.opts || {}, opts);
    const o = m.opts;
    m.el.innerHTML = `${o.dot === false ? '' : `<span class="dot ${o.dot || ''}"></span>`}${o.label ? `<span class="lbl ${o.tone || ''}">${esc(o.label)}</span>` : ''}`;
    m.el.classList.toggle('int', !!o.interactive);
    moveMarkers(name);
    return { el: m.el, set(p) { return Marker(name, id, p); }, remove() { m.el.remove(); delete markers[name][id]; } };
  }
  function moveMarkers(name) {
    const a = apps[name]; const ms = markers[name];
    if (!a || !ms) return;
    Object.entries(ms).forEach(([id, m]) => {
      const p = (m.opts && m.opts.at) || a.anchors.map[m.opts.anchor || id];
      if (!p || p.visible === false) { m.el.classList.add('hide'); return; }
      m.el.classList.remove('hide');
      m.el.style.left = `${p.x * 100}%`; m.el.style.top = `${p.y * 100}%`;
    });
  }
  function clearMarkers(name) { if (markers[name]) { Object.values(markers[name]).forEach(m => m.el.remove()); delete markers[name]; } }

  /* ── Key hints row ── */
  function KeyHints(host, hints = []) {
    host.innerHTML = `<div class="pp-hints" style="margin:0">${hints.map(h => `<span>${(h.keys || []).map(k => `<kbd>${esc(k)}</kbd>`).join('+')} ${esc(h.label)}</span>`).join('')}</div>`;
  }

  /* ── canvas sizing that respects app zoom + device pixel ratio ── */
  function fitCanvas(cv, zoomed = true) {
    const z = zoomed ? (NZA.zoom || 1) : 1;
    const dpr = window.devicePixelRatio || 1;
    const w = Math.max(1, Math.round(cv.clientWidth * z * dpr)), h = Math.max(1, Math.round(cv.clientHeight * z * dpr));
    if (cv.width !== w || cv.height !== h) { cv.width = w; cv.height = h; }
    return { w, h, scale: z * dpr };
  }
  // pointer in viewport fractions (same space as anchors)
  const pointer = e => ({ x: e.clientX / window.innerWidth, y: e.clientY / window.innerHeight });

  /* ═══════════════════════════ PREVIEW ═══════════════════════════ */
  let previewApp = null;
  function showReopen(name) {
    if (document.querySelector('.nz-reopen')) return;
    const r = el('div', 'nz-reopen');
    r.style.pointerEvents = 'auto';
    r.innerHTML = `<div class="nz-mark lg"></div><button class="btn-teal">Reopen ${esc(name)}</button><p>Closed · in game this posts <b>${esc(name)}:close</b></p>`;
    r.querySelector('button').onclick = () => { r.remove(); const a = apps[name]; a.preview && a.preview(); };
    document.body.appendChild(r);
  }
  function boot() {
    applyZoom();
    if (inGame) { post('_core:ready', {}); return; }
    const params = new URLSearchParams(location.search);
    const name = params.get('app');
    if (params.get('font')) applyConfig({ font: params.get('font') });
    document.body.prepend(el('div', 'nza-bg'));
    if (name && apps[name]) {
      previewApp = name;
      try { apps[name].preview ? apps[name].preview() : open(name, {}); } catch (e) { console.error(e); }
      return;
    }
    const g = el('div', 'nza-gallery');
    const names = $$('#nza-root .nza-app').map(s => s.dataset.app);
    g.innerHTML = `<h1><span class="nz-mark"></span>NAYZEEE Ambulance · NUI preview</h1><p>Every app with demo data. In game these are opened from Lua with NZA.UI.Open(app, data).</p>
      <div class="grid">${names.map(n => `<a href="?app=${n}">${n}<span>${apps[n] ? (apps[n].preview ? 'preview' : 'no preview') : 'missing'}</span></a>`).join('')}</div>`;
    document.body.appendChild(g);
  }
  // open an app locally with demo data (preview only, never posts)
  function demo(name, data) { open(name, data); }

  window.NZA = {
    inGame, resource, app, open, close: (n) => close(n, true), closeLocal: (n) => close(n, false), isOpen, demo, boot,
    post, mock: (name, v) => { mocks[name] = v; }, toast, speech, prompt, promptHide,
    audio, fmt, t, icon, rich, esc, el, clamp, fitCanvas, pointer, get stack() { return [...stack]; }, get cfg() { return cfg; },
    ui: { ProcPanel, FlipClock, Hold, Segmented, Toggle, Slider, Chips, Modal, Win, Anchors, Marker, Meter, meterHTML, KeyHints },
    apps,
  };
})();
