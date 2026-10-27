/* ═══════════════════════════════════════════════════════════
   NAYZEEE RADIO · UI kit + app router                                  window.NZR
   Loaded after core/nz-core.js (window.NZ) and before core/sfx.js and the apps.

   ROUTER
     NZR.app(name, def)        register an app (renders into <section id="app-<name>">,
                               created when index.html has none)
       def.init(el)            once, when registered
       def.open(data)          on action 'open' (Lua NZR.UI.Open)
       def.close()             on action 'close' (Lua NZR.UI.Close) or NZR.close(name)
       def.msg = { action(data) }   any other action (Lua NZR.UI.Send(app, action, data))
       def.keys = { Escape(e), Enter(e), ' '(e), KeyF(e), ... }   keydown, by e.key then e.code;
                               return false to let the key fall through to the app below
       def.keysUp = { ... }    keyup
       def.escClose            default true: Escape closes the app (posts '<app>:close')
       def.modalKeys           true: apps below never see the keyboard while this one is open
       def.full                true: the whole section takes the mouse (windows with a dim)
       def.noscale             true: no --nzr-zoom on this section
       def.preview()           browser demo (index.html?app=<name>), believable data
     NZR.post('<app>:<event>', data) → Promise<reply | null>   (NUI callback, Lua NZR.UI.On)
     NZR.close(name)           hide + post '<name>:close'     NZR.closeLocal(name)  hide only
     NZR.open(name, data)      open locally (what Lua 'open' does)
     NZR.demo(name, data)      same, for previews
     NZR.mock('<app>:<event>', fnOrValue)    preview-only replies for NZR.post
     NZR.isOpen(name)  NZR.stack  NZR.apps  NZR.cfg  NZR.inGame  NZR.resource

   '_core' ACTIONS (Lua → page, NZR.UI.Send('_core', action, data))
     config { font, shape, scale, sounds, signature, locale, lang, resource, sfx, clicks, keys }
     toast { title, message, type, duration, icon }      prompt { id, key, label, sub, progress, tone }
     promptHide { id }   promptsOff { on }   focus { top, apps }   closeAll   locale { key: text }
     sfx / rx / noise / ambient / gunfire / anything else → only the NZR.onCore listeners
     NZR.onCore(action, fn(data, action)) → fn   NZR.offCore(action, fn)    ('*' = every action)
     Built-in actions reach the listeners too (after the router handled them).

   KIT   NZR.ui.Win · KeyHints · Segmented · Toggle · Slider · Chips · Meter · Ring · Modal · Hold
               Odometer (alias FlipClock) · Bars (signal bars html) · meterHTML · ringHTML
         NZR.toast · NZR.prompt · NZR.promptHide · NZR.t · NZR.fmt · NZR.icon · NZR.esc · NZR.rich
         NZR.el · NZR.clamp · NZR.keyName · NZR.fitCanvas · NZR.pointer
   AUDIO NZR.audio   tiny shared WebAudio helper { ctx(), out(), unlock(), tone(), noise(), click(), beep() }
         NZR.sfx     the radio sound engine, replaced by core/sfx.js. Until then every method is a
                     no-op, so apps can always call NZR.sfx.play('key') without checking.
   ═══════════════════════════════════════════════════════════ */
(() => {
  const NZ = window.NZ;
  const inGame = NZ.inGame;
  const resource = NZ.resource === 'nz-preview' ? 'nayzeee-radio' : NZ.resource;
  const apps = {};
  const stack = [];         // open apps, last = top
  const mocks = {};
  const coreListeners = {}; // action → [fn]
  let locale = {};
  let cfg = { font: 'Lexend', shape: 'cut', scale: 1, sounds: true, signature: true, sfx: 0.8, clicks: true, keys: {} };
  let zoom = 1;             // current --nzr-zoom (NZR.zoom)
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const esc = NZ.esc;
  const clamp = (n, a, b) => Math.max(a, Math.min(b, n));

  /* ─────────────── icons: radio additions in the NAYZEEE stroke style ───────────────
     24 grid, 1.75 stroke, miter joins, chamfered corners with the bigger cut bottom-right,
     accent paths in --nzi-accent (duotone) */
  const A = 'style="stroke:var(--nzi-accent,currentColor)"';
  NZ.addIcons({
    'antenna': `<path d="M12 9 7.5 21M12 9l4.5 12M9.3 16.2h5.4M8.4 19h7.2"/><circle cx="12" cy="7.6" r="1.4"/><path class="a" d="M8.4 5.6a5 5 0 0 1 7.2 0M5.9 3.2a8.6 8.6 0 0 1 12.2 0" ${A}/>`,
    'jammer': `<path d="M4.2 9.5H19.8L21 10.7V16.9L17.4 20.5H4.2L3 19.3V10.7Z"/><path d="M7 9.5V3.5M16.5 9.5l2-4"/><path class="a" d="M6 15h2.2l1.6-2.6 2.2 5.2 2.2-5.2 1.6 2.6H18" ${A}/>`,
    'headset': `<path d="M4.5 13.5v-1.8a7.5 7.5 0 0 1 15 0v1.8"/><path d="M3.5 13.5H7.5V19.5H4.7L3.5 18.3Z"/><path d="M16.5 13.5H20.5V18.3L19.3 19.5H16.5Z"/><path class="a" d="M18.5 19.5c0 1.4-1.6 2-4.5 2h-1.5" ${A}/>`,
    'dial': `<path d="M12 5.5a6.5 6.5 0 1 1-4.6 1.9"/><path class="a" d="M12 12l3.6-3.6" ${A}/><path d="M12 2v1.8M22 12h-1.8M3.8 12H2M4.9 4.9l1.3 1.3M19.1 4.9l-1.3 1.3"/>`,
    'speaker': `<path d="M5.2 3H18.8L20 4.2V18.4L17.4 21H5.2L4 19.8V4.2Z"/><circle cx="12" cy="14" r="3.6"/><circle class="a" cx="12" cy="7.2" r="1.3" ${A}/>`,
    'frequency': `<path d="M2.5 12c1.6-5 3.2-5 4.75 0s3.15 5 4.75 0 3.2-5 4.75 0 3.15 5 4.75 0"/><path class="a" d="M12 2.5v3.5M12 18v3.5" ${A}/>`,
    'walkie': `<path d="M6.7 7.5H16.3L17.5 8.7V18.6L15.1 21H6.7L5.5 19.8V8.7Z"/><path d="M8.5 7.5V2.5M14 7.5V5.5"/><path class="a" d="M8.4 10.6h6.2v3H8.4Z" ${A}/><path d="M8.5 17h.01M11.5 17h.01M14.5 17h.01"/>`,
  });
  const icon = (n, cls) => NZ.icon(n, cls);

  /* ─────────────── helpers ─────────────── */
  const fmt = {
    time(sec) { sec = Math.max(0, Math.floor(sec || 0)); const m = Math.floor(sec / 60), s = sec % 60; return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`; },
    num(n, d = 0) { if (n === null || n === undefined || isNaN(n)) return '--'; return Number(n).toFixed(d); },
    pct(n, d = 0) { return `${fmt.num(n * 100, d)}%`; },
    // 155.5 | '155.5' → '155.50' (null for nonsense), the same key the Lua side uses
    freq(f) { const n = Number(String(f ?? '').replace(',', '.')); return Number.isFinite(n) && n > 0 ? (Math.round(n * 100) / 100).toFixed(2) : null; },
    money: NZ.money,
  };
  const t = (key, fallback) => (locale[key] !== undefined ? locale[key] : (fallback !== undefined ? fallback : key));

  // "Hold {Click} to talk on **S2**" → key caps + bold
  const rich = s => esc(s ?? '')
    .replace(/\{([^}]{1,24})\}/g, (_, k) => `<kbd>${k}</kbd>`)
    .replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>');

  const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html !== undefined) e.innerHTML = html; return e; };

  // FiveM key mapping names (Config.Keys) → what a key chip shows
  const KEY_NAMES = {
    LMENU: 'L-ALT', RMENU: 'R-ALT', LCONTROL: 'L-CTRL', RCONTROL: 'R-CTRL', LSHIFT: 'L-SHIFT', RSHIFT: 'R-SHIFT',
    CAPITAL: 'CAPS', RETURN: 'ENTER', BACK: 'BACKSPACE', ESCAPE: 'ESC', SPACE: 'SPACE', TAB: 'TAB',
    UP: '↑', DOWN: '↓', LEFT: '←', RIGHT: '→', MULTIPLY: 'NUM *', DIVIDE: 'NUM /', ADD: 'NUM +', SUBTRACT: 'NUM -',
    PRIOR: 'PG UP', NEXT: 'PG DN', HOME: 'HOME', END: 'END', INSERT: 'INS', DELETE: 'DEL',
    MOUSE_LEFT: 'LMB', MOUSE_RIGHT: 'RMB', MOUSE_MIDDLE: 'MMB', IOM_WHEEL_UP: 'WHEEL ↑', IOM_WHEEL_DOWN: 'WHEEL ↓',
  };
  function keyName(k) {
    const s = String(k ?? '').trim().toUpperCase();
    if (!s) return '';
    if (KEY_NAMES[s]) return KEY_NAMES[s];
    if (/^NUMPAD\d$/.test(s)) return `NUM ${s.slice(6)}`;
    return s;
  }

  /* ─────────────── zoom / config ─────────────── */
  function applyZoom() {
    const auto = clamp(window.innerHeight / 1080, 0.75, 2.2);
    const z = clamp((Number(cfg.scale) || 1) * auto, 0.6, 2.6);
    document.documentElement.style.setProperty('--nzr-zoom', z.toFixed(3));
    zoom = z;
    if (window.NZRInput) window.NZRInput.zoomChanged();
  }
  window.addEventListener('resize', applyZoom);

  function applyConfig(c) {
    cfg = Object.assign(cfg, c || {});
    const font = String(cfg.font || 'Lexend');
    if (font.toLowerCase() === 'lexend') document.documentElement.style.removeProperty('--font');
    else document.documentElement.style.setProperty('--font', `'${font.replace(/'/g, '')}','Lexend',system-ui,sans-serif`);
    if (cfg.shape) NZ.shape(cfg.shape);
    document.documentElement.classList.toggle('nzr-nosig', cfg.signature === false);
    if (c && c.locale) locale = Object.assign(locale, c.locale);
    applyZoom();
  }

  /* ─────────────── NUI bridge ─────────────── */
  async function post(name, data = {}) {
    if (!inGame) {
      const m = mocks[name];
      console.info('[nzr] →', name, data);
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
      def.el = el('section', 'nzr-app');
      def.el.id = `app-${name}`;
      def.el.dataset.app = name;
      document.getElementById('nzr-root').appendChild(def.el);
    }
    if (def.full) def.el.classList.add('nzr-full');
    if (def.noscale) def.el.classList.add('noscale');
    apps[name] = def;
    try { def.init && def.init(def.el); } catch (e) { console.error(`[nzr] ${name}.init`, e); }
    return def;
  }

  function isOpen(name) { return stack.includes(name); }

  // every open app that is not the top one gets .nzr-under (apps may dim or stop listening)
  function updateStack() {
    const top = stack[stack.length - 1];
    Object.values(apps).forEach(a => a.el.classList.toggle('nzr-under', isOpen(a.name) && a.name !== top));
  }

  function open(name, data) {
    const a = apps[name];
    if (!a) return console.warn('[nzr] unknown app', name);
    if (!isOpen(name)) stack.push(name);
    a.el.classList.add('nzr-on');
    audio.unlock();
    try { a.open && a.open(data || {}); } catch (e) { console.error(`[nzr] ${name}.open`, e); }
    updateStack();
  }

  function close(name, notify = true) {
    const a = apps[name];
    if (!a) return;
    const i = stack.indexOf(name);
    if (i === -1 && !a.el.classList.contains('nzr-on')) return;
    if (i !== -1) stack.splice(i, 1);
    a.el.classList.remove('nzr-on');
    try { a.close && a.close(); } catch (e) { console.error(`[nzr] ${name}.close`, e); }
    updateStack();
    if (notify) post(`${name}:close`, {});
    if (!inGame && notify && previewApp === name) showReopen(name);
  }

  function emitCore(action, data) {
    [...(coreListeners[action] || []), ...(coreListeners['*'] || [])].forEach(fn => {
      try { fn(data, action); } catch (e) { console.error(`[nzr] _core ${action} listener`, e); }
    });
  }
  function onCore(action, fn) { (coreListeners[action] = coreListeners[action] || []).push(fn); return fn; }
  function offCore(action, fn) { coreListeners[action] = (coreListeners[action] || []).filter(f => f !== fn); }

  window.addEventListener('message', e => {
    const d = e.data;
    if (!d || typeof d !== 'object' || !d.app) return;
    const data = d.data !== undefined ? d.data : {};
    // nz-core.js (verbatim ui-pack) re-shapes the whole page for ANY message whose data has a
    // top-level 'shape' string. Here only '_core config' may do that: put the configured one back.
    if (data && typeof data.shape === 'string' && !(d.app === '_core' && d.action === 'config')) NZ.shape(cfg.shape || 'cut');
    if (d.app === '_core') return core(d.action, data);
    const a = apps[d.app];
    if (!a) {
      // App files missing (e.g. not served by the manifest): hand the cursor back to the game
      if (d.action === 'open') {
        console.error(`[nzr] app "${d.app}" is not loaded - check fxmanifest files {}`);
        post(`${d.app}:close`, { missing: true });
      }
      return;
    }
    if (d.action === 'open') return open(d.app, data);
    if (d.action === 'close') return close(d.app, false);
    const h = a.msg && a.msg[d.action];
    if (h) { try { h(data); } catch (err) { console.error(`[nzr] ${d.app}.${d.action}`, err); } }
  });

  function core(action, data) {
    switch (action) {
      case 'config': applyConfig(data); break;
      case 'toast': toast(data); break;
      case 'prompt': prompt(data.id || 'default', data); break;
      case 'promptHide': promptHide(data.id || 'default'); break;
      case 'promptsOff': { const l = document.getElementById('nzr-layer-prompt'); if (l) l.classList.toggle('off', !!(data && data.on)); break; }   // third eye open
      case 'closeAll': [...stack].forEach(n => close(n, false)); break;
      case 'locale': locale = Object.assign(locale, data || {}); break;
      case 'focus': {   // Lua focus stack → the focused app gets keyboard priority
        const top = data && data.top;
        const i = top ? stack.indexOf(top) : -1;
        if (i !== -1 && i !== stack.length - 1) { stack.splice(i, 1); stack.push(top); }
        updateStack();
        break;
      }
      default: break;
    }
    emitCore(action, data);
  }

  /* keys go to the top-most open app that handles them */
  function keyHandler(map, e) {
    const tag = e.target && e.target.tagName;
    const typing = tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT';
    for (let i = stack.length - 1; i >= 0; i--) {
      const a = apps[stack[i]];
      const h = a && a[map] && (a[map][e.key] || a[map][e.code]);
      // letter / digit hotkeys never fire while a text field has the focus (Escape and Enter still do)
      const passes = !typing || e.key === 'Escape' || e.key === 'Enter';
      if (h && passes) { const r = h(e); if (r !== false) { e.preventDefault(); return; } }
      if (map === 'keys' && e.key === 'Escape' && a && a.escClose !== false && i === stack.length - 1) { close(a.name); e.preventDefault(); return; }
      if (a && a.modalKeys) return;   // apps that own the keyboard stop propagation to apps below
    }
  }
  window.addEventListener('keydown', e => { audio.unlock(); if (e.repeat && e.key !== ' ' && !/^(Arrow|Key|Digit|Backspace)/.test(e.key + e.code)) return; keyHandler('keys', e); });
  window.addEventListener('keyup', e => keyHandler('keysUp', e));
  window.addEventListener('mousedown', () => audio.unlock(), true);
  window.addEventListener('contextmenu', e => e.preventDefault());

  /* ─────────────── toasts (HUD notes, top-right, slide in from their edge) ─────────────── */
  const TOAST_ICON = { success: 'check', error: 'x', warning: 'alert', info: 'info' };
  function toast({ title, message, type = 'success', duration = 4500, icon: ic } = {}) {
    const layer = document.getElementById('nzr-layer-toasts');
    if (!layer || (!title && !message)) return;
    if (!TOAST_ICON[type]) type = 'info';
    const n = el('div', `note ${type === 'success' ? '' : type}`);
    n.innerHTML = `<span class="ni">${icon(ic || TOAST_ICON[type])}</span><div>${title ? `<b>${esc(title)}</b>` : ''}${message ? `<p>${esc(message)}</p>` : ''}</div><i class="bar"></i>`;
    const bar = n.querySelector('.bar');
    bar.animate([{ transform: 'scaleX(1)' }, { transform: 'scaleX(0)' }], { duration, easing: 'linear', fill: 'forwards' });
    layer.appendChild(n);
    while (layer.children.length > 5) layer.firstChild.remove();
    setTimeout(() => { n.classList.add('out'); setTimeout(() => n.remove(), 230); }, duration);
    if (cfg.sounds) audio.click(type === 'error' ? 260 : 660);
  }

  /* ─────────────── prompts ([E] pills on the right edge, below the middle) ─────────────── */
  const prompts = {};
  function prompt(id, { key = 'E', label = '', sub = '', progress = null, tone = '' } = {}) {
    const layer = document.getElementById('nzr-layer-prompt');
    if (!layer) return;
    let p = prompts[id];
    if (!p) { p = el('div', 'prompt nzr-hud solid'); layer.appendChild(p); prompts[id] = p; }
    const prog = progress !== null && progress !== undefined ? clamp(progress, 0, 1) : null;
    const tn = tone === 'red' ? 'red' : '';
    const ring = prog !== null
      ? `<span class="ring"><svg viewBox="0 0 26 26"><circle cx="13" cy="13" r="11" stroke="rgba(255,255,255,.12)"/><circle cx="13" cy="13" r="11" stroke="${tn ? 'var(--red)' : 'var(--teal)'}" stroke-dasharray="${(prog * 69.1).toFixed(1)} 69.1"/></svg><kbd>${esc(key)}</kbd></span>`
      : `<kbd class="${tn}">${esc(key)}</kbd>`;
    p.className = `prompt nzr-hud solid ${tn}`;
    p.innerHTML = `${ring}<span class="t">${esc(label)}${sub ? ` <span>· ${esc(sub)}</span>` : ''}</span>`;
  }
  function promptHide(id) { if (prompts[id]) { prompts[id].remove(); delete prompts[id]; } }

  /* ─────────────── audio ───────────────
     One AudioContext for the whole page (sfx.js should use NZR.audio.ctx() / out() too, so
     the browser never runs two). The context starts suspended until the first key / click /
     open; unlock() resumes it. Everything here is silent when Config.UI.sounds is off. */
  const audio = (() => {
    let ctx = null, master = null;
    const ok = () => cfg.sounds !== false;
    function ac() {
      if (!ctx) {
        const C = window.AudioContext || window.webkitAudioContext;
        if (!C) return null;
        try { ctx = new C(); } catch { return null; }
        master = ctx.createGain(); master.gain.value = 0.7; master.connect(ctx.destination);
      }
      return ctx;
    }
    function unlock() { const c = ac(); if (c && c.state === 'suspended') c.resume().catch(() => {}); }
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
      const len = Math.max(1, Math.floor(c.sampleRate * ms / 1000)), buf = c.createBuffer(1, len, c.sampleRate), d = buf.getChannelData(0);
      for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
      const s = c.createBufferSource(); s.buffer = buf;
      const f1 = c.createBiquadFilter(); f1.type = 'lowpass'; f1.frequency.value = lp;
      const f2 = c.createBiquadFilter(); f2.type = 'highpass'; f2.frequency.value = hp;
      const g = c.createGain(), t0 = c.currentTime + at, dur = ms / 1000;
      g.gain.setValueAtTime(0, t0); g.gain.linearRampToValueAtTime(vol, t0 + dur * attack);
      g.gain.setValueAtTime(vol, t0 + dur * (1 - release)); g.gain.linearRampToValueAtTime(0, t0 + dur);
      s.connect(f1); f1.connect(f2); f2.connect(g); g.connect(master); s.start(t0); s.stop(t0 + dur + 0.02);
    }
    return {
      ctx: ac, out() { ac(); return master; }, unlock, tone, noise,
      beep: (f = 880, ms = 90, vol = 0.12) => tone(f, ms, { vol }),
      click: (f = 660) => tone(f, 40, { vol: 0.05, type: 'triangle' }),
      tick: () => tone(1500, 18, { vol: 0.04, type: 'square' }),
    };
  })();

  // Placeholder engine: core/sfx.js replaces NZR.sfx with the real one. Calls made before
  // (or without) it are dropped quietly.
  const sfxStub = { stub: true, play() {}, stop() {}, volume() {}, unlock: audio.unlock, rx() {}, noise() {}, ambient() {}, gunfire() {} };

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

  /* ── Meter: { value 0..1, zone [a,b], mark 0..1, tone, lg, segs } ── */
  function meterHTML(m = {}) {
    const v = clamp(m.value ?? 0, 0, 1);
    const zone = m.zone ? `<span class="zone" style="left:${m.zone[0] * 100}%;width:${(m.zone[1] - m.zone[0]) * 100}%"></span>` : '';
    const mark = m.mark !== undefined && m.mark !== null ? `<span class="mark" style="left:${clamp(m.mark, 0, 1) * 100}%"></span>` : '';
    const fill = m.noFill ? '' : `<i style="width:${v * 100}%"></i>`;
    return `<div class="mtr ${esc(m.tone || '')} ${m.lg ? 'lg' : ''} ${m.segs ? 'segs' : ''}">${fill}${zone}${mark}</div>`;
  }
  function Meter(host, m = {}) { host.innerHTML = meterHTML(m); return { set(n) { host.innerHTML = meterHTML(Object.assign(m, n)); } }; }

  /* ── Signal bars: NZR.ui.Bars(0..4, { tone, lg }) → html ── */
  function Bars(n, { tone = '', lg = false } = {}) {
    const v = clamp(Math.round(Number(n) || 0), 0, 4);
    const tn = tone || (v <= 1 ? 'red' : v === 2 ? 'amber' : '');
    return `<span class="nzr-bars ${esc(tn)} ${lg ? 'lg' : ''}" aria-label="${v}/4">${[1, 2, 3, 4].map(i => `<i class="${i <= v ? 'on' : ''}"></i>`).join('')}</span>`;
  }

  /* ── Rolling counter (frequencies, timers): each digit rolls like an odometer ──
     NZR.ui.Odometer(host, { value, tone, small, blink }) → { el, set(v), tone(t), paused(p) }
       Every non-digit is a static separator ('.', ':', '-', letters…). Only ':' blinks
       (blink:false keeps it still). Alias: NZR.ui.FlipClock. */
  function Odometer(host, { value = '000.00', tone = '', small = false, blink = true } = {}) {
    const cls = tn => `odo ${tn || ''} ${small ? 'sm' : ''}${blink === false ? ' noblink' : ''}`;
    const root = el('div', cls(tone));
    host.appendChild(root);
    let cur = '';
    const strip = '<span class="st">' + '0123456789'.split('').map(d => `<i>${d}</i>`).join('') + '</span>';
    function set(v) {
      v = String(v);
      const shape = [...v].map(ch => (/[0-9]/.test(ch) ? 'd' : ch)).join('');
      const curShape = [...cur].map(ch => (/[0-9]/.test(ch) ? 'd' : ch)).join('');
      if (shape !== curShape) {
        root.innerHTML = [...v].map(ch => (/[0-9]/.test(ch) ? `<span class="d">${strip}</span>` : `<span class="c${ch === ':' ? ' colon' : ''}">${esc(ch)}</span>`)).join('');
      }
      [...v].forEach((ch, i) => { const d = root.children[i]; if (d && d.classList.contains('d')) d.firstChild.style.transform = `translateY(${-Number(ch)}em)`; });
      cur = v;
    }
    set(value);
    return { el: root, set, tone(tn) { root.className = `${cls(tn)} ${root.classList.contains('paused') ? 'paused' : ''}`; }, paused(p) { root.classList.toggle('paused', !!p); } };
  }

  /* ── Segmented / Toggle / Slider / Chips (HUD design controls) ── */
  function Segmented(host, { options = [], value, onChange } = {}) {
    const root = el('div', 'segc');
    root.innerHTML = options.map(op => `<button data-v="${esc(op.value)}" class="${op.value === value ? 'on' : ''}">${op.icon ? icon(op.icon) : ''}${esc(op.label)}</button>`).join('');
    root.addEventListener('click', e => { const b = e.target.closest('button'); if (!b) return; root.querySelectorAll('button').forEach(x => x.classList.toggle('on', x === b)); onChange && onChange(b.dataset.v); });
    host.appendChild(root);
    return { el: root, set(v) { root.querySelectorAll('button').forEach(x => x.classList.toggle('on', x.dataset.v === String(v))); }, get() { const b = root.querySelector('button.on'); return b ? b.dataset.v : null; } };
  }
  function Toggle(host, { on = false, onChange } = {}) {
    const b = el('button', `nzr-tg ${on ? 'on' : ''}`, '<i></i>');
    b.type = 'button';
    b.addEventListener('click', () => { b.classList.toggle('on'); onChange && onChange(b.classList.contains('on')); });
    host.appendChild(b);
    return { el: b, set(v) { b.classList.toggle('on', !!v); }, get() { return b.classList.contains('on'); } };
  }
  function Slider(host, { min = 0, max = 100, step = 1, value = 50, format = v => v, onChange } = {}) {
    const root = el('div', 'rng', `<input type="range" min="${min}" max="${max}" step="${step}" value="${value}" data-wheel><span></span>`);
    const inp = root.querySelector('input'), lab = root.querySelector('span');
    const paint = () => { const f = (Number(inp.value) - min) / ((max - min) || 1); inp.style.setProperty('--f', `${clamp(f, 0, 1) * 100}%`); };
    const upd = () => { lab.textContent = format(Number(inp.value)); paint(); };
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
      if (multi) { if (sel.has(v)) sel.delete(v); else sel.add(v); } else { sel.clear(); sel.add(v); }
      render(); onChange && onChange([...sel]);
    });
    render(); host.appendChild(root);
    return { el: root, set(vs) { sel.clear(); vs.forEach(v => sel.add(v)); render(); }, get() { return [...sel]; } };
  }

  /* ── Modal: { title, text (rich), icon, tone 'red'|'teal', actions [{ label, kind 'teal'|'line'|'red', onClick → false keeps it open }] } ── */
  function Modal({ title = '', text = '', icon: ic = 'alert', tone = 'red', actions = [], host } = {}) {
    const wrap = el('div', 'nzr-modal-wrap');
    wrap.innerHTML = `<div class="nzr-modal nzr-pop"><div class="mb"><div class="ic ${tone === 'teal' ? 'teal' : ''}">${icon(ic)}</div><div><h4>${esc(title)}</h4><p>${rich(text)}</p></div></div><div class="mf"></div></div>`;
    const f = wrap.querySelector('.mf');
    const closeM = () => wrap.remove();
    actions.forEach(a => {
      const b = el('button', `btn-${a.kind || 'line'}`, esc(a.label));
      b.onclick = () => { const r = a.onClick && a.onClick(); if (r !== false) closeM(); };
      f.appendChild(b);
    });
    (host || document.getElementById('nzr-root')).appendChild(wrap);
    return { close: closeM, el: wrap };
  }

  /* ── Window shell (UI v5): mark + title, mid text, actions, red Close pill, optional side nav, status bar ──
     NZR.ui.Win(host, { title, sub, mid (html), nav [{ id, label, icon, tally } | { group }], navValue,
                        onNav(id), onClose(), status [{ key, label }], width, height })
       → { el, main, side, act, setMid(html), setStatus(keys, extraHtml), setNav(items, value), nav(id), destroy() } */
  function Win(host, o = {}) {
    const w = el('div', 'nzr-win nzr-int');
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
      setTitle(title, sub) { q('.w-brand .t').textContent = title || ''; if (sub !== undefined) q('.w-brand .s').textContent = sub || ''; return api; },
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

  /* ── Key hints row: NZR.ui.KeyHints(host, [{ keys: ['LMB'], label }], { vertical }) ── */
  function KeyHints(host, hints = [], { vertical = false } = {}) {
    host.innerHTML = `<div class="nzr-hints ${vertical ? 'v' : ''}">${hints.map(h => `<span>${(h.keys || []).map(k => `<kbd>${esc(k)}</kbd>`).join('<i>+</i>')}<em>${esc(h.label)}</em></span>`).join('')}</div>`;
    return host.firstChild;
  }

  /* ── Status ring: value in the middle, track + fill, label under it, optional ping ──
     NZR.ui.Ring({ value, frac 0..1, tone, label, unit, beat }) → html  (alias ringHTML)
       tone  '' | teal | red | amber | white      beat  seconds per ping (0 = off) */
  const RING_C = 2 * Math.PI * 18;
  function Ring({ value = '--', frac = 0, tone = '', label = '', unit = '', beat = 0 } = {}) {
    const f = clamp(Number(frac) || 0, 0, 1), b = Number(beat) || 0;
    return `<div class="nzr-ring ${esc(tone || '')}"${b > 0 ? ` style="--beat:${b.toFixed(2)}s"` : ''}><span class="rg"><svg viewBox="0 0 44 44"><circle class="b" cx="22" cy="22" r="18"/><circle class="f" cx="22" cy="22" r="18" stroke-dasharray="${RING_C.toFixed(1)}" stroke-dashoffset="${(RING_C * (1 - f)).toFixed(1)}"/></svg><b>${esc(String(value ?? '--'))}</b>${b > 0 ? '<i class="bt"></i>' : ''}</span>${label || unit ? `<em>${esc(String(label ?? ''))}${unit ? `<small>${esc(String(unit))}</small>` : ''}</em>` : ''}</div>`;
  }

  /* ── canvas sizing that respects app zoom + device pixel ratio ── */
  function fitCanvas(cv, zoomed = true) {
    const z = zoomed ? zoom : 1;
    const dpr = window.devicePixelRatio || 1;
    const w = Math.max(1, Math.round(cv.clientWidth * z * dpr)), h = Math.max(1, Math.round(cv.clientHeight * z * dpr));
    if (cv.width !== w || cv.height !== h) { cv.width = w; cv.height = h; }
    return { w, h, scale: z * dpr };
  }
  // pointer in viewport fractions (0..1, the same space as Lua screen coords)
  const pointer = e => ({ x: e.clientX / window.innerWidth, y: e.clientY / window.innerHeight });

  /* ═══════════════════════════ PREVIEW ═══════════════════════════
     index.html            gallery of every app section (+ the kit)
     index.html?app=<name> that app's def.preview() over a fake street backdrop
     index.html?app=kit    every kit piece on one page
     ?shape=bevel / ?scale=1.2 / ?font=… change the config like Config.UI would */
  let previewApp = null;
  function showReopen(name) {
    if (document.querySelector('.nz-reopen')) return;
    const r = el('div', 'nz-reopen');
    r.style.pointerEvents = 'auto';
    r.innerHTML = `<div class="nz-mark lg"></div><button class="btn-teal">Reopen ${esc(name)}</button><p>Closed · in game this posts <b>${esc(name)}:close</b></p>`;
    r.querySelector('button').onclick = () => { r.remove(); const a = apps[name]; if (a && a.preview) a.preview(); else open(name, {}); };
    document.body.appendChild(r);
  }

  // a section whose app.js is still empty: say so in a HUD card instead of a blank page
  function placeholder(name) {
    const sec = document.getElementById(`app-${name}`) || document.getElementById('nzr-root');
    sec.classList.add('nzr-on');
    const card = el('div', 'nzr-hud solid nzr-card nzr-brk nzr-placeholder nzr-pop');
    card.innerHTML = `<div class="ph-h"><span class="nz-mark sm"></span><div><b>${esc(name)}</b><span>apps/${esc(name)}/app.js has no NZR.app('${esc(name)}', …) yet</span></div></div>
      <p>The router, the kit and this section are in place. Register the app and give it a <b>preview()</b> to see it here.</p>
      <div class="ph-k"></div>`;
    sec.appendChild(card);
    KeyHints(card.querySelector('.ph-k'), [{ keys: ['ESC'], label: 'Close' }, { keys: ['LMB'], label: 'Press' }]);
  }

  function kitDemo() {
    const host = document.getElementById('nzr-root');
    const sec = el('section', 'nzr-app nzr-on nzr-full');
    sec.id = 'app-kit';
    host.appendChild(sec);
    const w = Win(sec, {
      title: 'NAYZEEE RADIO', sub: 'UI kit · every piece', mid: '<span class="nz-dot"></span><p>Channel <b>155.50</b> · 6 radios tuned in</p><span class="nz-ver">v1.0.0</span>',
      nav: [{ group: 'Controls' }, { id: 'ctl', label: 'Controls', icon: 'sliders', tally: 6 }, { id: 'hud', label: 'HUD pieces', icon: 'antenna' }, { group: 'Icons' }, { id: 'ic', label: 'Radio icons', icon: 'walkie' }],
      navValue: 'ctl', status: [{ key: 'ESC', label: 'Close' }, { key: 'TAB', label: 'Switch tab' }],
      onClose: () => toast({ title: 'Close', message: 'In game this posts kit:close.', type: 'info' }),
    });
    w.main.innerHTML = `
      <div class="w-head"><div><h1>Radio kit</h1><p>Window shell, HUD panels and controls the apps build on. Everything here is drawn by core/nzr.css.</p></div></div>
      <div class="kit-grid">
        <section class="w-panel"><div class="w-phead"><div><h2>Controls</h2><p>Segmented, toggle, slider, chips</p></div></div>
          <div class="w-pbody"><div class="opt"><div class="opt-t"><b>Access</b><small>Who may join this channel</small></div><span data-k="seg"></span></div>
            <div class="opt"><div class="opt-t"><b>Mic clicks</b><small>Chirp when someone keys up</small></div><span data-k="tg"></span></div>
            <div class="opt col"><div class="opt-t"><b>Volume</b></div><span data-k="sl"></span></div>
            <div class="opt col"><div class="opt-t"><b>Jobs</b></div><span data-k="ch"></span></div></div></section>
        <section class="w-panel"><div class="w-phead"><div><h2>Readouts</h2><p>Odometer, bars, meter, rings</p></div><button class="btn-line btn-sm" data-k="roll">${icon('refresh')}Roll</button></div>
          <div class="w-pbody"><div class="kit-freq"><span class="nzr-label">TX · S1</span><span data-k="odo"></span><span class="u">MHz</span></div>
            <div class="w-row"><span class="nz-tile">${icon('antenna')}</span><div class="txt"><b>Signal</b><span>clear · weak · poor · lost</span></div>${Bars(4)}${Bars(2)}${Bars(1)}${Bars(0)}</div>
            <div class="w-row"><div class="txt"><b>Jam</b><span>meter with a zone and a mark</span></div><span data-k="mtr" style="width:160px"></span></div>
            <div class="kit-rings">${Ring({ value: '83', frac: 0.83, tone: 'teal', label: 'Signal', unit: '%' })}${Ring({ value: '12', frac: 0.4, tone: 'amber', label: 'Hold', unit: 's' })}${Ring({ value: '3', frac: 0.75, tone: 'red', label: 'Stage', beat: 1.2 })}</div></div></section>
        <section class="w-panel"><div class="w-phead"><div><h2>Notices</h2><p>Toasts, prompts, modal</p></div></div>
          <div class="w-pbody"><button class="btn-teal" data-k="toast">${icon('bell')}Toast</button><button class="btn-line" data-k="prompt">${icon('keyboard')}Prompt</button><button class="btn-red" data-k="modal">${icon('alert')}Modal</button>
            <div data-k="hints"></div></div></section>
        <section class="w-panel"><div class="w-phead"><div><h2>Icons</h2><p>Radio additions to the NAYZEEE set</p></div></div>
          <div class="w-pbody kit-icons">${['antenna', 'jammer', 'headset', 'dial', 'speaker', 'frequency', 'walkie', 'radio', 'signal', 'broadcast', 'mic', 'volume', 'mute', 'lock', 'siren', 'car'].map(n => `<span title="${n}">${icon(n)}<em>${n}</em></span>`).join('')}</div></section>
      </div>`;
    const k = s => w.main.querySelector(`[data-k="${s}"]`);
    Segmented(k('seg'), { options: [{ value: 'open', label: 'Open' }, { value: 'code', label: 'Code' }, { value: 'job', label: 'Job' }], value: 'code' });
    Toggle(k('tg'), { on: true });
    Slider(k('sl'), { value: 60, format: v => `${v}%` });
    Chips(k('ch'), { options: [{ value: 'police', label: 'Police', icon: 'badge' }, { value: 'ems', label: 'EMS', icon: 'medkit' }, { value: 'sheriff', label: 'Sheriff', icon: 'shield' }], values: ['police'] });
    const odo = Odometer(k('odo'), { value: '155.50', tone: 'teal' });
    Meter(k('mtr'), { value: 0.62, zone: [0.7, 0.92], mark: 0.62, tone: 'amber' });
    KeyHints(k('hints'), [{ keys: ['LMB'], label: 'Press a key' }, { keys: ['RMB'], label: 'Lower' }, { keys: [keyName('LMENU')], label: 'Talk' }]);
    k('roll').onclick = () => odo.set((100 + Math.random() * 800).toFixed(2));
    k('toast').onclick = () => toast({ title: 'Channel saved', message: '155.50 is now locked by code.', type: 'success' });
    k('prompt').onclick = () => { prompt('demo', { key: 'E', label: 'Pick up jammer', sub: 'JX-40' }); setTimeout(() => promptHide('demo'), 3500); };
    k('modal').onclick = () => Modal({ title: 'Remove this jammer?', text: 'The **JX-90** at Legion Square goes away for everyone.', actions: [{ label: 'Keep it', kind: 'line' }, { label: 'Remove', kind: 'red' }] });
  }

  function boot() {
    applyZoom();
    if (inGame) { post('_core:ready', {}); return; }
    const params = new URLSearchParams(location.search);
    const name = params.get('app');
    const c = {};
    if (params.get('font')) c.font = params.get('font');
    if (params.get('shape')) c.shape = params.get('shape');   // else applyConfig would put the default back
    if (params.get('scale')) c.scale = +params.get('scale');
    applyConfig(c);
    document.body.prepend(el('div', 'nzr-bg'));
    if (name === 'kit') { kitDemo(); return; }
    if (name && apps[name]) {
      previewApp = name;
      try { if (apps[name].preview) apps[name].preview(); else open(name, {}); } catch (e) { console.error(e); }
      return;
    }
    if (name && document.getElementById(`app-${name}`)) { placeholder(name); return; }
    const g = el('div', 'nzr-gallery');
    const names = $$('#nzr-root .nzr-app').map(s => s.dataset.app);
    g.innerHTML = `<h1><span class="nz-mark"></span>NAYZEEE Radio · NUI preview</h1><p>Every app with demo data. In game these are opened from Lua with NZR.UI.Open(app, data, opts).</p>
      <div class="grid">${names.map(n => `<a href="?app=${encodeURIComponent(n)}">${esc(n)}<span>${apps[n] ? (apps[n].preview ? 'preview' : 'no preview') : 'not written yet'}</span></a>`).join('')}<a href="?app=kit">kit<span>every component</span></a></div>
      <div class="foot nz-hints"><span><kbd>?app=name</kbd>open one app</span><span><kbd>?shape=bevel</kbd>window shape</span><span><kbd>?scale=1.2</kbd>HUD scale</span><span class="nz-sig"><span class="nz-mark xs"></span>NAYZEEE</span></div>`;
    document.body.appendChild(g);
  }
  // open an app locally with demo data (preview only, never posts)
  function demo(name, data) { open(name, data); }

  const NZR = window.NZR = {
    inGame, resource, app, open, close: (n) => close(n, true), closeLocal: (n) => close(n, false), isOpen, demo, boot,
    post, mock: (name, v) => { mocks[name] = v; }, onCore, offCore, toast, prompt, promptHide,
    audio, sfx: sfxStub, fmt, t, icon, rich, esc, el, clamp, keyName, fitCanvas, pointer,
    get stack() { return [...stack]; }, get cfg() { return cfg; }, get locale() { return locale; },
    ui: { Win, KeyHints, Segmented, Toggle, Slider, Chips, Meter, meterHTML, Ring, ringHTML: Ring, Modal, Hold, Odometer, FlipClock: Odometer, Bars },
    apps, get zoom() { return zoom; },
  };
})();
