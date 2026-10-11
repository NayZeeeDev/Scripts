/* ═══════════════════════════════════════════════════════════
   WIG SNATCH V2 · minigames
   Tug of War · Button Mash · Combo · Skill Check · Grip
   Inputs are sent to the server, which moves the rope.
   ═══════════════════════════════════════════════════════════ */
'use strict';

const G = { on: false, d: null, p: 0, t0: 0, raf: 0, last: 0, lock: 0, game: null, endT: 0 };
const ge = {
  clash: $('#clash'), game: $('#game'), knot: $('.rope-knot'), mine: $('.rope-half.mine'), theirs: $('.rope-half.theirs'),
  time: $('.cl-time'), clock: $('.cl-clock'), flash: $('.cl-flash'), res: $('.cl-result'), mods: $('.cl-mods'),
  hint: $('.cl-hint'), label: $('.cl-game'),
};

const SEQ_KEYS = { KeyW: 'U', ArrowUp: 'U', KeyS: 'D', ArrowDown: 'D', KeyA: 'L', ArrowLeft: 'L', KeyD: 'R', ArrowRight: 'R' };
const SEQ_ICON = { U: 'fa-arrow-up', D: 'fa-arrow-down', L: 'fa-arrow-left', R: 'fa-arrow-right' };

function gFlash(text, good) {
  ge.flash.textContent = text;
  ge.flash.className = 'cl-flash ' + (good ? 'good' : 'bad');
  void ge.flash.offsetWidth;
  ge.flash.classList.add('go');
}
function gShake() { ge.clash.classList.remove('shake'); void ge.clash.offsetWidth; ge.clash.classList.add('shake'); }
function gHit(token) {
  post('clashHit', token ? { token } : {});
  if (PREVIEW && window.Mock) window.Mock.localHit(G.d.role);
}
function gMiss(text = 'Missed') {
  G.lock = performance.now() + (G.d.lockout || 380);
  gFlash(text, false);
  SFX.miss();
  gShake();
}
const locked = () => performance.now() < G.lock;
const pullKey = () => S.prefs.keyPull || 'Space';

/* ─────────────── games ─────────────── */
const GAMES = {};

// Tug of War: sweeping cursor, hit inside the zone
GAMES.clash = {
  mount(el, d) {
    this.x = Math.random(); this.dir = 1; this.zw = clamp(d.zone || 0.16, 0.05, 0.6); this.lastHit = 0;
    el.innerHTML = `<div class="track"><div class="track-zone"></div><div class="track-cursor"></div></div>`;
    this.track = $('.track', el); this.zone = $('.track-zone', el); this.cur = $('.track-cursor', el);
    this.place();
    return `<span class="kc">${keyLabel(pullKey())}</span><span>Pull when the line is in the zone</span>`;
  },
  place() {
    let l, tries = 0;
    do { l = Math.random() * (1 - this.zw); tries++; } while (tries < 12 && Math.abs((l + this.zw / 2) - this.x) < 0.25);
    this.zl = l;
    this.zone.style.left = (l * 100) + '%';
    this.zone.style.width = (this.zw * 100) + '%';
  },
  frame(dt) {
    this.x += this.dir * G.d.speed * dt;
    if (this.x >= 1) { this.x = 1; this.dir = -1; }
    if (this.x <= 0) { this.x = 0; this.dir = 1; }
    this.cur.style.left = (this.x * 100) + '%';
    this.track.classList.toggle('locked', locked());
  },
  key(e) {
    if (e.code !== pullKey() || e.type !== 'keydown') return;
    const now = performance.now();
    if (locked() || now - this.lastHit < 230) return;
    if (this.x >= this.zl && this.x <= this.zl + this.zw) {
      this.lastHit = now;
      gHit(); gFlash('Clean pull', true); SFX.hit();
      this.track.classList.add('hit'); setTimeout(() => this.track.classList.remove('hit'), 120);
      this.place();
    } else gMiss();
  },
};

// Button Mash: alternate two keys
GAMES.mash = {
  mount(el) {
    this.last = null; this.lastAt = 0; this.count = 0;
    const L = S.prefs.keyMashL || 'KeyA', R = S.prefs.keyMashR || 'KeyD';
    this.keys = { [L]: 'L', [R]: 'R' };
    el.innerHTML = `<div class="mash">
      <div class="mash-key" data-side="L"><span>${keyLabel(L)}</span></div>
      <div class="mash-meter"><i></i><b>0</b><small>pulls</small></div>
      <div class="mash-key" data-side="R"><span>${keyLabel(R)}</span></div></div>`;
    this.el = el;
    this.meter = $('.mash-meter i', el); this.countEl = $('.mash-meter b', el);
    this.heat = 0;
    return `<span class="kc">${keyLabel(L)}</span><span class="kc">${keyLabel(R)}</span><span>Alternate as fast as you can</span>`;
  },
  frame(dt) {
    this.heat = Math.max(0, this.heat - dt * 1.6);
    this.meter.style.height = (this.heat * 100) + '%';
  },
  key(e) {
    const side = this.keys[e.code];
    if (!side) return;
    const pad = $(`.mash-key[data-side="${side}"]`, this.el);
    if (e.type === 'keyup') { pad && pad.classList.remove('down'); return; }
    pad && pad.classList.add('down');
    if (side === this.last) { pad && pad.classList.add('wrong'); setTimeout(() => pad && pad.classList.remove('wrong'), 160); return; }
    const now = performance.now();
    if (now - this.lastAt < 80) return;
    this.last = side; this.lastAt = now;
    this.count++; this.countEl.textContent = this.count;
    this.heat = Math.min(1, this.heat + 0.14);
    gHit(side);
    SFX.key();
  },
};

// Combo: type the arrows the server gave you
GAMES.sequence = {
  mount(el, d) {
    this.el = el;
    this.set(d.seq, 0);
    return `<span class="kc">W A S D</span><span>or arrows · type the combo in order</span>`;
  },
  set(seq, idx, state) {
    this.seq = arr(seq); this.idx = idx || 0;
    this.el.innerHTML = `<div class="combo ${state || ''}">${this.seq.map((k, i) => `<div class="combo-key ${i < this.idx ? 'done' : ''} ${i === this.idx ? 'next' : ''}"><i class="fa-solid ${SEQ_ICON[k] || 'fa-question'}"></i></div>`).join('')}</div>`;
  },
  frame() {},
  key(e) {
    if (e.type !== 'keydown') return;
    const tok = SEQ_KEYS[e.code];
    if (!tok || locked() || this.idx >= this.seq.length) return; // finished combo: wait for the next one
    e.preventDefault();
    if (tok === this.seq[this.idx]) {
      this.idx++;
      gHit(tok); SFX.key();
      if (this.idx >= this.seq.length) { gFlash('Combo!', true); SFX.hit(); this.set(this.seq, this.idx, 'flash'); }
      else this.set(this.seq, this.idx);
    } else {
      gHit(tok); // the server resets the combo and sends a lockout
      gMiss('Wrong key');
      this.set(this.seq, 0, 'bad');
    }
  },
  update(s) {
    // the server counts the keys from 1, this list from 0
    this.set(s.seq, Math.max(0, (s.idx || 1) - 1), s.done ? 'fresh' : s.miss ? 'bad' : '');
  },
};

// Skill Check: needle spins round a ring, hit inside the arc
GAMES.circle = {
  mount(el, d) {
    this.a = Math.random(); this.arc = clamp(d.arc || 0.14, 0.05, 0.5); this.lastHit = 0;
    el.innerHTML = `<div class="ring"><svg viewBox="0 0 120 120">
        <circle class="ring-track" cx="60" cy="60" r="48"/>
        <circle class="ring-arc" cx="60" cy="60" r="48" pathLength="1000"/>
        <line class="ring-needle" x1="60" y1="60" x2="60" y2="8"/>
        <circle class="ring-hub" cx="60" cy="60" r="7"/>
      </svg><span class="ring-key">${keyLabel(pullKey())}</span></div>`;
    this.svg = $('svg', el); this.arcEl = $('.ring-arc', el); this.needle = $('.ring-needle', el);
    this.place();
    return `<span class="kc">${keyLabel(pullKey())}</span><span>Hit it when the needle crosses the arc</span>`;
  },
  place() {
    let s, tries = 0;
    do { s = Math.random(); tries++; } while (tries < 12 && Math.abs(((s + this.arc / 2) - this.a + 1.5) % 1 - 0.5) < 0.22);
    this.start = s;
    // dasharray on a pathLength of 1000; rotate so 0 is at 12 o'clock
    this.arcEl.style.strokeDasharray = `${this.arc * 1000} 1000`;
    this.arcEl.style.transform = `rotate(${s * 360 - 90}deg)`;
  },
  frame(dt) {
    this.a = (this.a + G.d.speed * dt) % 1;
    this.needle.style.transform = `rotate(${this.a * 360}deg)`;
    this.svg.classList.toggle('locked', locked());
  },
  key(e) {
    if (e.code !== pullKey() || e.type !== 'keydown') return;
    const now = performance.now();
    if (locked() || now - this.lastHit < 250) return;
    const rel = (this.a - this.start + 1) % 1;
    if (rel <= this.arc) {
      this.lastHit = now;
      gHit(); gFlash('Perfect', true); SFX.hit();
      this.svg.classList.add('hit'); setTimeout(() => this.svg.classList.remove('hit'), 140);
      this.place();
    } else gMiss();
  },
};

// Grip: hold to lift the marker, keep it inside the moving zone
GAMES.balance = {
  mount(el, d) {
    this.y = 0.3; this.v = 0; this.held = false; this.zh = clamp(d.zone || 0.22, 0.08, 0.6);
    this.z = 0.4; this.zt = 0.6; this.inside = 0; this.tick = d.tick || 420;
    el.innerHTML = `<div class="grip"><div class="grip-bar"><div class="grip-zone"></div><div class="grip-mark"></div></div>
      <div class="grip-fill"><i></i></div></div>`;
    this.zoneEl = $('.grip-zone', el); this.mark = $('.grip-mark', el); this.fill = $('.grip-fill i', el); this.bar = $('.grip-bar', el);
    return `<span class="kc">${keyLabel(pullKey())}</span><span>Hold to lift · keep the marker in the zone</span>`;
  },
  frame(dt) {
    // physics: hold = push up, release = gravity
    this.v += (this.held ? 2.6 : -2.2) * dt;
    this.v *= 0.92;
    this.y = clamp(this.y + this.v * dt, 0, 1);
    if (this.y === 0 || this.y === 1) this.v = 0;
    // the zone wanders toward a moving target
    if (Math.abs(this.z - this.zt) < 0.02) this.zt = Math.random() * (1 - this.zh);
    this.z += Math.sign(this.zt - this.z) * Math.min(Math.abs(this.zt - this.z), dt * 0.32);
    this.zoneEl.style.bottom = (this.z * 100) + '%';
    this.zoneEl.style.height = (this.zh * 100) + '%';
    this.mark.style.bottom = (this.y * 100) + '%';
    const inZone = this.y >= this.z && this.y <= this.z + this.zh;
    this.bar.classList.toggle('in', inZone);
    if (inZone) {
      this.inside += dt * 1000;
      if (this.inside >= this.tick) { this.inside = 0; gHit(); SFX.hit(); gFlash('Grip', true); }
    } else this.inside = Math.max(0, this.inside - dt * 600);
    this.fill.style.width = clamp(this.inside / this.tick * 100, 0, 100) + '%';
  },
  key(e) {
    if (e.code !== pullKey()) return;
    this.held = e.type === 'keydown';
  },
};

/* ─────────────── shell ─────────────── */
function renderRope() {
  const d = G.d; if (!d) return;
  const mine = d.role === 'snatcher' ? G.p : -G.p;
  const k = clamp(50 + (mine / d.winAt) * 50, 0, 100);
  ge.mine.style.width = k + '%';
  ge.theirs.style.width = (100 - k) + '%';
  ge.knot.style.left = k + '%';
}

function gLoop(t) {
  if (!G.on) return;
  const dt = Math.min(0.05, (t - (G.last || t)) / 1000);
  G.last = t;
  G.game.frame(dt);
  const rem = Math.max(0, G.d.duration - (performance.now() - G.t0));
  ge.time.textContent = (rem / 1000).toFixed(1);
  ge.clock.classList.toggle('hot', rem < 2000);
  G.raf = requestAnimationFrame(gLoop);
}

function clashStart(d) {
  clearTimeout(G.endT);
  const game = GAMES[d.game] || GAMES.clash;
  Object.assign(G, { on: true, d, p: d.p || 0, t0: performance.now(), last: 0, lock: 0, game });
  ge.res.hidden = true;
  $('.cl-side.me .cl-role').textContent = d.steal ? 'You · Taking it back' : d.role === 'snatcher' ? 'You · Snatching' : 'You · Defending';
  $('.cl-side.me .cl-name').textContent = d.me || 'You';
  $('.cl-side.them .cl-role').textContent = d.role === 'snatcher' ? 'Holding on' : d.steal ? 'Taking it back' : 'Snatching';
  $('.cl-side.them .cl-name').textContent = d.opp || '';
  ge.label.innerHTML = `<i class="${esc(d.icon || 'fa-solid fa-grip-lines-vertical')}"></i>${esc(d.label || 'Tug of War')}`;
  const mods = [];
  if (d.blind) mods.push(`<span class="chip" style="${tintVars('#e5a50a')}"><i class="fa-solid fa-eye-slash"></i>Blindside</span>`);
  if (d.glued) mods.push(`<span class="chip" style="${tintVars(d.role === 'victim' ? S.prefs.accent : S.prefs.alert)}"><i class="fa-solid fa-droplet"></i>Glued down</span>`);
  if (d.layer === 'wig') mods.push(`<span class="chip"><i class="fa-solid fa-masks-theater"></i>Wearing a wig</span>`);
  ge.mods.innerHTML = mods.join('');
  ge.game.className = 'game g-' + (d.game || 'clash');
  ge.hint.innerHTML = game.mount(ge.game, d) || '';
  renderRope();
  ge.clash.hidden = false;
  ge.clash.style.animation = 'none'; void ge.clash.offsetWidth; ge.clash.style.animation = '';
  SFX.start();
  cancelAnimationFrame(G.raf);
  G.raf = requestAnimationFrame(gLoop);
}

function clashTick(p) {
  if (!G.on) return;
  const before = G.p;
  G.p = Number(p) || 0;
  renderRope();
  const mine = G.d.role === 'snatcher' ? G.p - before : before - G.p;
  if (mine < 0) SFX.tick();
}

function clashSeq(s) {
  if (G.on && G.game === GAMES.sequence) GAMES.sequence.update(s);
}

function clashEnd(r) {
  const wasOn = G.on;
  G.on = false;
  cancelAnimationFrame(G.raf);
  if (!wasOn || r.cancelled) { ge.clash.hidden = true; return; }
  if (r.p !== undefined) { G.p = r.p; renderRope(); }
  let title, sub;
  const win = r.win;
  if (r.role === 'snatcher') {
    title = win ? (r.steal ? 'Got it back' : 'Snatched') : 'Shoved off';
    sub = win ? (r.steal ? `Your wig is back from ${esc(r.opp)}` : `You got ${esc(r.opp)}'s hair`) : `${esc(r.opp)} held on`;
  } else {
    title = win ? 'Held on' : (r.steal ? 'Taken back' : 'Snatched');
    sub = win ? `${esc(r.opp)} couldn't get it` : r.steal ? `${esc(r.opp)} took their wig back` : `${esc(r.opp)} took your ${r.layer === 'wig' ? 'wig' : 'hair'}${r.stealBack ? ` · ${r.stealBack} min to steal it back` : ''}`;
  }
  ge.res.className = 'cl-result ' + (win ? 'win' : 'lose');
  ge.res.innerHTML = `<b>${title}</b><span>${sub}</span>`;
  ge.res.hidden = false;
  win ? SFX.win() : SFX.lose();
  G.endT = setTimeout(() => { ge.clash.hidden = true; }, 1900);
}

function gameKey(e) {
  if (!G.on) return false;
  if (e.repeat && e.type === 'keydown') { e.preventDefault(); return true; }
  G.game.key(e);
  if (e.code === 'Space' || e.code.startsWith('Arrow')) e.preventDefault();
  return true;
}
