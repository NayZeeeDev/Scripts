/* ═══════════════════════════════════════════════════════════
   Device shells: laptop OS (windows) and tablet OS (home screen)
   ═══════════════════════════════════════════════════════════ */
(() => {
  const S = NZ.state;
  const icon = NZ.icon;
  const esc = NZ.esc;
  const stage = NZ.$('#stage');
  const device = NZ.$('#device');
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const APPS = ['trader', 'news', 'calc', 'settings'];
  let shell = null;

  // ── scale the 1920×1080 stage to the screen ───────────────────
  function fit() {
    const s = Math.min(innerWidth / 1920, innerHeight / 1080);
    NZ.scale = s;
    stage.style.transform = `translate(${(innerWidth - 1920 * s) / 2}px, ${(innerHeight - 1080 * s) / 2}px) scale(${s})`;
    NZ.emit('scale');
  }
  addEventListener('resize', fit);
  fit();
  NZ.toLocal = (cx, cy, el) => {
    const r = el.getBoundingClientRect();
    return { x: (cx - r.left) / NZ.scale, y: (cy - r.top) / NZ.scale };
  };

  // ── toasts, modals, context menus, world hint ─────────────────
  NZ.toast = ({ title, text, kind = 'ok', life = 4500 }) => {
    const host = (shell && S.open && shell.toasts) || NZ.$('#world-toasts');
    const ic = { err: 'alert', warn: 'bell', info: 'info' }[kind] || 'check';
    const el = NZ.h(`<div class="toast ${kind === 'ok' || kind === 'info' ? '' : kind}" style="--life:${life}ms"><div class="ti">${icon(ic)}</div><div><b>${esc(title)}</b>${text ? `<p>${esc(text)}</p>` : ''}</div></div>`);
    host.appendChild(el);
    while (host.childElementCount > 4) host.firstElementChild.remove();
    setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 260); }, life);
  };

  NZ.confirm = ({ title, text, ok = 'Confirm', okClass = 'btn-red', icon: ic = 'alert', teal = false }) => new Promise((resolve) => {
    const host = shell ? shell.screen : stage;
    const el = NZ.h(`<div class="scrim"><div class="modal"><div class="modal-b"><div class="warn ${teal ? 'teal' : ''}">${icon(ic)}</div>
      <div><h4>${esc(title)}</h4><p>${esc(text)}</p></div></div>
      <div class="modal-f"><button class="btn-line" data-x="0">Cancel</button><button class="${okClass}" data-x="1">${esc(ok)}</button></div></div></div>`);
    const done = (v) => { el.remove(); NZ.modal = null; resolve(v); };
    el.addEventListener('click', (e) => {
      const b = e.target.closest('[data-x]');
      if (b) done(b.dataset.x === '1');
      else if (e.target === el) done(false);
    });
    NZ.modal = { close: () => done(false), ok: () => done(true) };
    host.appendChild(el);
  });

  function closeMenu() { if (NZ.ctxMenu) { NZ.ctxMenu.remove(); NZ.ctxMenu = null; } }
  NZ.menu = (items, cx, cy) => {
    closeMenu();
    if (!shell) return;
    const host = shell.screen;
    const p = NZ.toLocal(cx, cy, host);
    const el = NZ.h(`<div class="ctx">${items.map((it, i) => (it ? `<button data-i="${i}"><i style="background:${it.color}"></i>${esc(it.label)}</button>` : '<hr>')).join('')}</div>`);
    host.appendChild(el);
    el.style.left = Math.min(p.x, host.offsetWidth - el.offsetWidth - 8) + 'px';
    el.style.top = Math.min(p.y, host.offsetHeight - el.offsetHeight - 8) + 'px';
    el.addEventListener('click', (e) => {
      const b = e.target.closest('[data-i]');
      if (b) { closeMenu(); items[+b.dataset.i].run(); }
    });
    NZ.ctxMenu = el;
  };
  document.addEventListener('mousedown', (e) => { if (NZ.ctxMenu && !NZ.ctxMenu.contains(e.target)) closeMenu(); });

  NZ.hint = (d) => {
    let el = NZ.$('#hint');
    if (!d) { if (el) el.remove(); return; }
    if (!el) { el = NZ.h('<div id="hint"></div>'); stage.appendChild(el); }
    el.innerHTML = `<div class="h-title"><div class="mark xs"></div>${esc(d.title)}</div>
      <div class="h-keys">${d.keys.map(([k, l]) => `<span><i class="key">${esc(k)}</i>${esc(l)}</span>`).join('')}</div>`;
  };

  // ── shared pieces ─────────────────────────────────────────────
  const appMeta = (id) => {
    const a = NZ.apps[id];
    return { title: typeof a.title === 'function' ? a.title() : a.title, sub: typeof a.sub === 'function' ? a.sub() : a.sub };
  };
  const appIcon = (id, cls = '') => {
    const a = NZ.apps[id];
    return a.icon === 'teal' ? `<div class="appicon teal ${cls}"></div>` : `<div class="appicon ${a.tone || ''} ${cls}">${icon(a.glyph)}</div>`;
  };
  const barHtml = (id, extraEnd = '') => {
    const m = appMeta(id);
    return `<header class="bar"><div class="bar-brand"><div class="mark"></div><div><div class="title-txt">${esc(m.title)}</div><div class="sub">${esc(m.sub || '')}</div></div></div>
      <div class="bar-mid"></div><div class="bar-end"><div class="slot" style="display:flex;align-items:center;gap:10px"></div>${extraEnd}</div></header>`;
  };
  const nowClock = () => {
    const d = new Date();
    return { time: d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' }), date: d.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' }), short: d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) };
  };
  const marketLine = () => {
    const idx = S.syms.find((m) => m.type === 'index');
    return idx ? `${idx.s} ${NZ.pct(NZ.change(idx))}` : '';
  };
  const userName = () => (S.profile ? S.profile.name : S.player.name) || 'Trader';

  function lockHtml(tablet) {
    return `<div class="lock">
      <div class="clock"><b data-r="lt"></b><span data-r="ld"></span></div>
      <div class="user"><div class="avatar">${esc(NZ.initials(userName()))}</div><div class="name">${esc(userName())}</div>
        ${tablet ? '<div class="hint"><div class="spin"></div><span data-r="lh">Face recognition…</span></div>'
          : `<div class="pw"><div class="dots" data-r="dots"><em>Password</em></div><button data-r="go">${icon('arrowRight')}</button></div><div class="hint" data-r="lh">Press <i class="key" style="margin:0 2px">Enter</i> to sign in</div>`}
      </div></div>`;
  }

  // ═════════════════════════════════════════════════════════════
  // LAPTOP
  // ═════════════════════════════════════════════════════════════
  function Laptop() {
    device.className = 'dev laptop show';
    device.innerHTML = `
      <div class="bezel"><i class="cam"></i>
        <div class="screen" data-wall="${S.settings.wallpaper}">
          <div class="wall blur"></div>
          <div class="boot"><div class="mark xl"></div><div class="bar-track"><i></i></div><small>NAYZEEE OS</small></div>
          ${lockHtml(false)}
          <div class="desktop">
            <div class="icons">${APPS.map((id) => `<button class="dicon" data-app="${id}">${appIcon(id)}<span>${esc(appMeta(id).title)}</span></button>`).join('')}</div>
            <div class="windows"></div>
            <div class="taskbar">
              <button class="tb-start" data-r="start"><div class="mark sm"></div></button><div class="tb-sep"></div>
              <div class="tb-apps" data-r="tapps"></div>
              <div class="tb-tray">
                <div class="tb-market"><span class="dot" data-r="mdot"></span><b data-r="mk"></b><span data-r="mi"></span></div>
                ${icon('wifi')}${icon('volume')}${icon('battery')}<span>86%</span>
                <div class="tb-clock"><b data-r="tt"></b><span data-r="td"></span></div>
              </div>
            </div>
          </div>
          <div class="toasts"></div>
          <div class="power on"></div>
        </div>
        <div class="chin">NAYZEEE</div>
      </div>`;

    const screen = device.querySelector('.screen');
    const r = {};
    device.querySelectorAll('[data-r]').forEach((el) => { r[el.dataset.r] = el; });
    const wall = screen.querySelector('.wall');
    const lock = screen.querySelector('.lock');
    const desktop = screen.querySelector('.desktop');
    const winsEl = screen.querySelector('.windows');
    const power = screen.querySelector('.power');
    const wins = {};
    let z = 10, active = null, startMenu = null, skip = false, alive = true, unlocked = false;
    lock.classList.add('hidden');

    // ── clock & tray ──
    function tick() {
      const c = nowClock();
      NZ.text(r.lt, c.time); NZ.text(r.ld, c.date);
      NZ.text(r.tt, c.time); NZ.text(r.td, c.short);
      NZ.text(r.mk, NZ.sessionLabel());
      NZ.text(r.mi, marketLine());
      r.mdot.className = 'dot ' + NZ.sessionDot();
    }
    tick();
    const clock = setInterval(tick, 1000);

    // ── boot → lock → desktop ──
    async function boot() {
      await sleep(80);
      power.classList.remove('on');
      device.querySelector('.cam').classList.add('on');
      NZ.sound.play('boot');
      screen.querySelector('.boot .bar-track i').style.width = '100%';
      await sleep(skip ? 200 : 1050);
      screen.querySelector('.boot').remove();
      lock.classList.remove('hidden');
      await sleep(skip ? 100 : 550);
      const len = 8;
      for (let i = 0; i < len && alive; i++) {
        if (i === 0) r.dots.innerHTML = '';
        r.dots.appendChild(document.createElement('i'));
        NZ.sound.play('key');
        await sleep(skip ? 15 : 70 + Math.random() * 70);
      }
      if (!alive) return;
      r.lh.innerHTML = '<div class="spin"></div><span>Signing in…</span>';
      await sleep(skip ? 120 : 520);
      unlock();
    }
    function unlock() {
      if (unlocked || !alive) return;
      unlocked = true;
      NZ.sound.play('unlock');
      lock.classList.add('gone');
      wall.classList.remove('blur');
      desktop.classList.add('show');
      setTimeout(() => openApp('trader'), 250);
    }
    lock.addEventListener('click', () => { skip = true; });

    // ── window manager ──
    function area() { return { w: winsEl.clientWidth, h: winsEl.clientHeight }; }
    function place(w) {
      const a = area();
      const g = w.max ? { x: 0, y: 0, w: a.w, h: a.h } : w.geom;
      Object.assign(w.el.style, { left: g.x + 'px', top: g.y + 'px', width: g.w + 'px', height: g.h + 'px' });
      w.el.classList.toggle('max', w.max);
      const mb = w.el.querySelector('[data-w=max]');
      if (mb) mb.innerHTML = icon(w.max ? 'restore' : 'max');
      NZ.emit('scale');
    }
    function focusWin(w) {
      active = w;
      w.el.style.zIndex = ++z;
      Object.values(wins).forEach((x) => x.el.classList.toggle('focus', x === w));
      renderTaskbar();
    }
    function renderTaskbar() {
      r.tapps.innerHTML = Object.values(wins).map((w) => `<button class="tb-app ${w === active && !w.el.classList.contains('min') ? 'focus' : ''}" data-tb="${w.id}">${appIcon(w.id)}${esc(appMeta(w.id).title)}</button>`).join('');
    }
    function openApp(id, arg) {
      closeStart();
      let w = wins[id];
      if (!w) {
        const app = NZ.apps[id];
        const el = NZ.h(`<div class="win"><div class="win-in">${barHtml(id, `<div class="wbtns"><button class="wbtn" data-w="min">${icon('minus')}</button><button class="wbtn" data-w="max">${icon('max')}</button><button class="wbtn x" data-w="close">${icon('x')}</button></div>`)}<div class="win-body"></div></div></div>`);
        const a = area();
        const n = Object.keys(wins).length;
        const gw = Math.min(app.w || 960, a.w - 40), gh = Math.min(app.h || 680, a.h - 40);
        w = { id, el, max: app.size === 'max', geom: { x: (a.w - gw) / 2 + n * 24, y: Math.max(16, (a.h - gh) / 2 - 20 + n * 24), w: gw, h: gh } };
        wins[id] = w;
        winsEl.appendChild(el);
        place(w);
        w.inst = app.create({
          body: el.querySelector('.win-body'), mid: el.querySelector('.bar-mid'), end: el.querySelector('.slot'),
          device: 'laptop', open: openApp, close: () => closeWin(w),
        });
        bindWin(w);
        NZ.sound.play('click');
      }
      w.el.classList.remove('min');
      focusWin(w);
      if (arg && w.inst.ticket) w.inst.ticket(arg);
      return w.inst;
    }
    function closeWin(w) {
      if (w.inst && w.inst.destroy) w.inst.destroy();
      delete wins[w.id];
      w.el.classList.add('closing');
      setTimeout(() => w.el.remove(), 200);
      if (active === w) active = Object.values(wins).sort((a, b) => b.el.style.zIndex - a.el.style.zIndex)[0] || null;
      if (active) focusWin(active); else renderTaskbar();
    }
    function bindWin(w) {
      const bar = w.el.querySelector('.bar');
      w.el.addEventListener('mousedown', () => { if (active !== w) focusWin(w); });
      w.el.querySelector('.wbtns').addEventListener('click', (e) => {
        const b = e.target.closest('[data-w]');
        if (!b) return;
        const a = b.dataset.w;
        if (a === 'close') closeWin(w);
        else if (a === 'max') { w.max = !w.max; place(w); }
        else { w.el.classList.add('min'); active = null; renderTaskbar(); }
      });
      bar.addEventListener('dblclick', (e) => { if (!e.target.closest('button,input,select')) { w.max = !w.max; place(w); } });
      bar.addEventListener('mousedown', (e) => {
        if (e.button !== 0 || w.max || e.target.closest('button,input,select,.acct-switch')) return;
        const start = NZ.toLocal(e.clientX, e.clientY, winsEl);
        const g0 = { ...w.geom };
        w.el.classList.add('dragging');
        const move = (ev) => {
          const p = NZ.toLocal(ev.clientX, ev.clientY, winsEl);
          const a = area();
          w.geom.x = Math.max(-g0.w + 120, Math.min(a.w - 120, g0.x + p.x - start.x));
          w.geom.y = Math.max(0, Math.min(a.h - 52, g0.y + p.y - start.y));
          w.el.style.left = w.geom.x + 'px';
          w.el.style.top = w.geom.y + 'px';
        };
        const up = () => { w.el.classList.remove('dragging'); removeEventListener('mousemove', move); removeEventListener('mouseup', up); };
        addEventListener('mousemove', move);
        addEventListener('mouseup', up);
      });
    }

    // ── desktop, taskbar, start menu ──
    desktop.querySelector('.icons').addEventListener('click', (e) => {
      const b = e.target.closest('[data-app]');
      desktop.querySelectorAll('.dicon').forEach((x) => x.classList.toggle('sel', x === b));
    });
    desktop.querySelector('.icons').addEventListener('dblclick', (e) => {
      const b = e.target.closest('[data-app]');
      if (b) openApp(b.dataset.app);
    });
    r.tapps.addEventListener('click', (e) => {
      const b = e.target.closest('[data-tb]');
      if (!b) return;
      const w = wins[b.dataset.tb];
      if (w === active && !w.el.classList.contains('min')) { w.el.classList.add('min'); active = null; renderTaskbar(); }
      else { w.el.classList.remove('min'); focusWin(w); }
    });
    function closeStart() { if (startMenu) { startMenu.remove(); startMenu = null; r.start.classList.remove('on'); } }
    r.start.addEventListener('click', () => {
      if (startMenu) return closeStart();
      const acc = NZ.account();
      const mt = NZ.metrics(acc);
      startMenu = NZ.h(`<div class="start">
        <div class="who"><div class="av">${esc(NZ.initials(userName()))}</div><div class="grow"><b>${esc(userName())}</b><span>${mt ? `${S.active === 'live' ? 'Live' : 'Practice'} · ${NZ.money(mt.equity)}` : 'No brokerage account'}</span></div></div>
        <div class="list">${APPS.map((id) => `<button class="item" data-app="${id}">${appIcon(id)}${esc(appMeta(id).title)}</button>`).join('')}</div>
        <div class="foot"><span class="muted" style="font-size:10.5px">${esc(S.cfg.ui.company)} · v${esc(S.cfg.ui.version)}</span><button class="btn-red" data-a="off">${icon('power')}Shut down</button></div></div>`);
      startMenu.addEventListener('click', (e) => {
        const a = e.target.closest('[data-app]');
        if (a) openApp(a.dataset.app);
        if (e.target.closest('[data-a=off]')) shutdown();
      });
      desktop.appendChild(startMenu);
      r.start.classList.add('on');
      NZ.sound.play('click');
    });
    screen.addEventListener('mousedown', (e) => { if (startMenu && !startMenu.contains(e.target) && !r.start.contains(e.target)) closeStart(); });

    const offSettings = NZ.on('settings', () => { screen.dataset.wall = S.settings.wallpaper; });

    async function shutdown() {
      if (!alive) return;
      alive = false;
      closeStart();
      NZ.sound.play('shutdown');
      Object.values(wins).forEach((w) => w.inst && w.inst.destroy && w.inst.destroy());
      power.classList.add('on');
      await sleep(420);
      device.classList.add('closing');
      await sleep(330);
      destroy();
      NZ.closed();
    }
    function destroy() {
      alive = false;
      clearInterval(clock);
      offSettings();
      device.innerHTML = '';
      device.className = '';
    }

    boot();
    return {
      screen, toasts: screen.querySelector('.toasts'),
      open: openApp, shutdown, destroy,
      escape() { if (startMenu) return closeStart(); if (!unlocked) { skip = true; return; } shutdown(); },
      enter() { if (!unlocked) skip = true; },
      activeInst: () => (active && !active.el.classList.contains('min') ? active.inst : null),
    };
  }

  // ═════════════════════════════════════════════════════════════
  // TABLET
  // ═════════════════════════════════════════════════════════════
  function Tablet() {
    device.className = 'dev tablet show';
    device.innerHTML = `
      <div class="bezel"><i class="cam"></i>
        <div class="screen" data-wall="${S.settings.wallpaper}">
          <div class="wall blur"></div>
          <div class="t-status"><span data-r="tt"></span><div class="mid"><span class="dot" data-r="mdot"></span><span data-r="mk"></span></div><div class="ic">${icon('wifi')}${icon('battery')}</div></div>
          ${lockHtml(true)}
          <div class="home">
            <div class="widgets">
              <div class="widget clock"><small data-r="wd"></small><b data-r="wt"></b></div>
              <div class="widget"><small>${icon('wallet', 'style="width:13px;height:13px"')}<span data-r="wa">Account</span></small><b data-r="weq">—</b><span data-r="wday"></span></div>
              <div class="widget"><small>${icon('globe', 'style="width:13px;height:13px"')}<span data-r="wi">Market</span></small><b data-r="wix">—</b><span data-r="wic"></span></div>
            </div>
            <div class="grid">${APPS.map((id) => `<button class="tapp" data-app="${id}">${appIcon(id)}<span>${esc(appMeta(id).title)}</span></button>`).join('')}</div>
            <div class="dock">${APPS.map((id) => `<button data-app="${id}">${appIcon(id)}</button>`).join('')}</div>
          </div>
          <div class="toasts"></div>
          <div class="power on"></div>
        </div>
      </div>`;

    const screen = device.querySelector('.screen');
    const r = {};
    device.querySelectorAll('[data-r]').forEach((el) => { r[el.dataset.r] = el; });
    const wall = screen.querySelector('.wall');
    const lock = screen.querySelector('.lock');
    const home = screen.querySelector('.home');
    const power = screen.querySelector('.power');
    let current = null, alive = true, unlocked = false;

    function tick() {
      const c = nowClock();
      NZ.text(r.lt, c.time); NZ.text(r.ld, c.date); NZ.text(r.tt, c.time);
      NZ.text(r.wt, c.time); NZ.text(r.wd, c.date);
      NZ.text(r.mk, NZ.sessionLabel());
      r.mdot.className = 'dot ' + NZ.sessionDot();
      const mt = NZ.metrics();
      if (mt) {
        NZ.text(r.wa, S.active === 'live' ? 'Live account' : 'Practice account');
        NZ.text(r.weq, NZ.money(mt.equity));
        NZ.text(r.wday, `${NZ.signed(mt.day)} today`);
        r.wday.className = NZ.dir(mt.day);
      }
      const idx = S.syms.find((m) => m.type === 'index');
      if (idx) {
        NZ.text(r.wi, idx.n);
        NZ.text(r.wix, NZ.px(idx.q.last));
        NZ.text(r.wic, NZ.pct(NZ.change(idx)));
        r.wic.className = NZ.dir(NZ.change(idx));
      }
    }
    tick();
    const clock = setInterval(tick, 1000);

    async function boot() {
      await sleep(120);
      power.classList.remove('on');
      NZ.sound.play('boot');
      await sleep(900);
      unlock();
    }
    function unlock() {
      if (unlocked || !alive) return;
      unlocked = true;
      NZ.text(r.lh, 'Unlocked');
      NZ.sound.play('unlock');
      lock.classList.add('gone');
      wall.classList.remove('blur');
      home.classList.add('show');
      setTimeout(() => openApp('trader'), 260);
    }
    lock.addEventListener('click', unlock);

    function openApp(id, arg) {
      if (current && current.id === id) { if (arg && current.inst.ticket) current.inst.ticket(arg); return current.inst; }
      if (current) closeApp(true);
      const el = NZ.h(`<div class="t-app">${barHtml(id, `<button class="btn-ghost" data-a="home">${icon('home')}Home</button>`)}<div class="win-body"></div><div class="t-homebar" data-a="home"><i></i></div></div>`);
      screen.insertBefore(el, screen.querySelector('.toasts'));
      current = { id, el };
      current.inst = NZ.apps[id].create({
        body: el.querySelector('.win-body'), mid: el.querySelector('.bar-mid'), end: el.querySelector('.slot'),
        device: 'tablet', open: openApp, close: () => closeApp(),
      });
      el.addEventListener('click', (e) => { if (e.target.closest('[data-a=home]')) closeApp(); });
      NZ.sound.play('click');
      if (arg && current.inst.ticket) current.inst.ticket(arg);
      return current.inst;
    }
    function closeApp(instant) {
      if (!current) return;
      const c = current;
      current = null;
      if (c.inst.destroy) c.inst.destroy();
      if (instant) return c.el.remove();
      c.el.classList.add('closing');
      setTimeout(() => c.el.remove(), 220);
    }
    home.addEventListener('click', (e) => { const b = e.target.closest('[data-app]'); if (b) openApp(b.dataset.app); });

    const offSettings = NZ.on('settings', () => { screen.dataset.wall = S.settings.wallpaper; });

    async function shutdown() {
      if (!alive) return;
      alive = false;
      NZ.sound.play('shutdown');
      if (current && current.inst.destroy) current.inst.destroy();
      power.classList.add('on');
      await sleep(300);
      device.classList.add('closing');
      await sleep(330);
      destroy();
      NZ.closed();
    }
    function destroy() {
      alive = false;
      clearInterval(clock);
      offSettings();
      device.innerHTML = '';
      device.className = '';
    }

    boot();
    return {
      screen, toasts: screen.querySelector('.toasts'),
      open: openApp, shutdown, destroy,
      escape: shutdown,
      enter: unlock,
      activeInst: () => (current ? current.inst : null),
    };
  }

  // ── public ────────────────────────────────────────────────────
  NZ.os = {
    open(kind) {
      if (shell) shell.destroy();
      shell = kind === 'tablet' ? Tablet() : Laptop();
    },
    shutdown() { if (shell) shell.shutdown(); },
  };

  NZ.closed = () => {
    shell = null;
    closeMenu();
    S.open = false;
    NZ.post('close');
  };

  document.addEventListener('keydown', (e) => {
    if (!S.open || !shell) return;
    if (e.key === 'Escape') {
      e.preventDefault();
      if (NZ.modal) return NZ.modal.close();
      if (NZ.ctxMenu) return closeMenu();
      return shell.escape();
    }
    if (NZ.modal) { if (e.key === 'Enter') NZ.modal.ok(); return; }
    if (e.key === 'Enter' && shell.enter) shell.enter();
    const tag = e.target.tagName;
    if (tag === 'INPUT' || tag === 'SELECT' || tag === 'TEXTAREA') return;
    const inst = shell.activeInst();
    if (inst && inst.key && inst.key(e)) e.preventDefault();
  });
})();
