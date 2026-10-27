/* ═══════════════════════════════════════════════════════════
   NAYZEEE RADIO · headunit — the MV-90 mobile transceiver (focused, game input kept)
                                                                  apps/headunit/app.js
   Opened by client/modules/vehicle.lua from an operating seat of a radio car with
   NZR.UI.Open('headunit', state, { focus = true, cursor = true, keepInput = true }).
   The device is drawn in CSS: rubber shell, brushed faceplate, a teal-lit LCD in the
   middle, the keypad left of it, function keys right of it, a knob at each end, a guarded
   EMERG switch under the channel knob and a hand mic on its hook. No brand on the face
   (customer rule B): model code and fine print only. The key-hint chips around it are ours.

   It never decides anything: every key, knob step, EMERG and PTT edge is posted to Lua and
   the LCD only draws the state that comes back (client/modules/firmware.lua, device 'vehicle').

   Lua → NUI
     open  (state)    the screen state below
     state (state)    SPEC §10.3 screen state (view off|boot|home|tune|code|emergency, freq, label,
                      access, tx, rx { name, callsign, q, emergency }, bars, nosignal, volume,
                      showVolume, mute, handsfree, entry, code, target, mem, title, hint, notice,
                      busy, emergency) + knobs { vol, ch } (degrees) + pressed (key held | nil)
                      + hold { emerg 0..1 } (EMERG hold progress, timed in Lua)
     close
   NUI → Lua
     headunit:press { key, down }   key: '0'..'9' star hash ok back pre mut pwr emerg ptt
                                    vol- vol+ ch- ch+   (a knob step = one down + one up)
     headunit:close                 Esc (the router posts it)

   Input: mouse on every key; knobs turn by dragging round them, the wheel, or a click on a
   half (held = repeat); the EMERG cover flips up on a click, then hold the button. Keyboard
   while focused: 0-9, * #, Enter = OK, Backspace = CLR, arrows = knobs (up/down channel,
   left/right volume), the PTT key from '_core' config keys.ptt (FiveM mapper name) = talk.
   Browser: index.html?app=headunit (live fake firmware; &hu=tune|code|rx|tx|emergency|off|guard)
   ═══════════════════════════════════════════════════════════ */
(() => {
  const NZR = window.NZR;
  const { esc, t } = NZR;
  const APP = 'headunit';
  const num = (v, d = 0) => { const n = Number(v); return Number.isFinite(n) ? n : d; };
  const clamp = (n, a, b) => Math.max(a, Math.min(b, n));
  const str = v => (typeof v === 'string' || typeof v === 'number' ? String(v) : '');
  const up = v => str(v).toUpperCase();
  const pad2 = n => String(Math.max(0, Math.floor(n))).padStart(2, '0');
  const mmss = ms => { const s = Math.floor(Math.max(0, ms) / 1000); return `${pad2(Math.floor(s / 60) % 100)}:${pad2(s % 60)}`; };
  const fkey = v => { if (v === null || v === undefined || v === false || v === '') return null; const n = Number(String(v).replace(',', '.')); return Number.isFinite(n) && n > 0 ? n.toFixed(2) : null; };
  const $ = (s, r) => r.querySelector(s);
  const $$ = (s, r) => [...r.querySelectorAll(s)];
  const now = () => performance.now();
  // translatable static words (ui.hu_*), re-read when Lua pushes the locale with the config
  const L = (k, f) => `<span data-t="ui.${k}" data-f="${esc(f)}">${esc(t(`ui.${k}`, f))}</span>`;
  const relabel = el => $$('[data-t]', el).forEach(e => { e.textContent = t(e.dataset.t, e.dataset.f); });

  // device words printed by the unit itself (generic labelling, not translated on hardware)
  const DEV = {
    model: 'MV-90', kind: 'MOBILE TRANSCEIVER', fine: '13.8V DC · 25W · IP54', serial: 'SN 9047-2215',
    mhz: 'MHz', tx: 'TX', rx: 'RX', emg: 'EMG', pwr: 'PWR', mem: 'MEM', lock: 'LOCK', mute: 'MUTE', hf: 'HF',
    vol: 'VOL', ch: 'CH', emerg: 'EMERG', lift: 'LIFT', clr: 'CLR', ok: 'OK', mic: 'MIC', ptt: 'PTT',
    live: 'MIC LIVE', nosignal: 'NO SIGNAL', keyin: 'KEY IN A CHANNEL', open: 'OPEN', unit: 'UNIT', selftest: 'SELF TEST',
    titles: { tune: 'TUNE', code: 'ACCESS CODE', emergency: 'EMERGENCY' },
  };
  const LETTERS = { 2: 'ABC', 3: 'DEF', 4: 'GHI', 5: 'JKL', 6: 'MNO', 7: 'PQRS', 8: 'TUV', 9: 'WXYZ', 0: '+', 1: '·' };

  // FiveM key mapper names (Config.Keys.ptt) → KeyboardEvent.code
  const CODES = {
    CAPITAL: 'CapsLock', LMENU: 'AltLeft', RMENU: 'AltRight', LCONTROL: 'ControlLeft', RCONTROL: 'ControlRight',
    LSHIFT: 'ShiftLeft', RSHIFT: 'ShiftRight', SPACE: 'Space', TAB: 'Tab', OEM_3: 'Backquote', GRAVE: 'Backquote',
    INSERT: 'Insert', HOME: 'Home', END: 'End', PRIOR: 'PageUp', NEXT: 'PageDown', DELETE: 'Delete',
    DIVIDE: 'NumpadDivide', SUBTRACT: 'NumpadSubtract', ADD: 'NumpadAdd', DECIMAL: 'NumpadDecimal',
  };
  function codeOf(name) {
    const s = up(name).trim();
    if (!s) return null;
    if (CODES[s]) return CODES[s];
    if (/^[A-Z]$/.test(s)) return `Key${s}`;
    if (/^F\d{1,2}$/.test(s)) return s;
    if (/^NUMPAD\d$/.test(s)) return `Numpad${s.slice(6)}`;
    return null;
  }

  /* ─────────────── markup ─────────────── */
  const screw = c => `<i class="hu-screw ${c}"><i></i></i>`;
  const knob = (id, label, detents) => {
    // printed scale round the knob: the volume arc runs -135..135, the channel ring has a tick per detent
    const ticks = id === 'vol'
      ? Array.from({ length: 11 }, (_, i) => -135 + i * 27)
      : Array.from({ length: detents }, (_, i) => i * (360 / detents));
    const tk = ticks.map((a, i) => {
      const r1 = 46, r2 = id === 'vol' ? (i % 5 === 0 ? 39 : 42) : (i % 4 === 0 ? 39 : 42.5), rad = (a - 90) * Math.PI / 180;
      return `<line x1="${(50 + r1 * Math.cos(rad)).toFixed(2)}" y1="${(50 + r1 * Math.sin(rad)).toFixed(2)}" x2="${(50 + r2 * Math.cos(rad)).toFixed(2)}" y2="${(50 + r2 * Math.sin(rad)).toFixed(2)}"/>`;
    }).join('');
    const arc = id === 'vol' ? '<path class="kn-arc" d="M17.2 82.8A46 46 0 1 1 82.8 82.8"/>' : '';
    return `<div class="hu-knob k-${id}" data-knob="${id}">
      <svg class="kn-scale" viewBox="0 0 100 100">${arc}<g>${tk}</g></svg>
      ${id === 'vol' ? '<b class="kn-min">0</b><b class="kn-max">10</b>' : ''}
      <span class="kn-half l"></span><span class="kn-half r"></span>
      <div class="kn-skirt"><div class="kn-cap"><i class="kn-ind"></i></div></div>
    </div><b class="hu-lbl">${label}</b>`;
  };
  const key = (k, label, sub = '', cls = '') => `<button class="hu-key ${cls}" data-k="${k}" tabindex="-1"><b>${label}</b>${sub !== '' ? `<em>${sub}</em>` : ''}</button>`;
  const PWR_GLYPH = '<svg viewBox="0 0 24 24"><path d="M12 3v8"/><path d="M6.6 6.8a7.6 7.6 0 1 0 10.8 0"/></svg>';

  function markup() {
    const pad = ['1', '2', '3', '4', '5', '6', '7', '8', '9'].map(d => key(d, d, LETTERS[d])).join('') +
      key('star', '*', '·', 'sym') + key('0', '0', LETTERS[0]) + key('hash', '#', '', 'sym');
    return `
<div class="hu-wrap">
  <div class="hu-hints"></div>
  <div class="hu-rig">
    <svg class="hu-cord" aria-hidden="true"><path class="c0"/><path class="c1"/><path class="c2"/><g class="plug"><circle class="p0" r="9.5"/><circle class="p1" r="6.5"/><circle class="p2" r="3"/></g></svg>
    <div class="hu-mic" data-k="ptt" title="">
      <i class="mc-hook"></i>
      <div class="mc-body">
        <i class="mc-led"></i>
        <i class="mc-grille"></i>
        <b class="mc-name">${DEV.ptt}</b>
        <span class="mc-bar"></span>
        <i class="mc-strain"></i>
      </div>
    </div>
    <div class="hu-dev">
      <i class="hu-ear l"><i></i><i></i></i><i class="hu-ear r"><i></i><i></i></i>
      <div class="hu-shell">
        <div class="hu-plate">
          ${screw('s1')}${screw('s2')}${screw('s3')}${screw('s4')}
          <div class="hu-col c-vol">
            ${knob('vol', DEV.vol)}
            <span class="hu-jack"><i></i><em>${DEV.mic}</em></span>
          </div>
          <div class="hu-pad">${pad}</div>
          <div class="hu-center">
            <div class="hu-top">
              <b class="hu-model">${DEV.model}</b><em class="hu-kind">${DEV.kind}</em><span class="sp"></span>
              <span class="hu-pipes"><span><i class="pp p-tx"></i>${DEV.tx}</span><span><i class="pp p-rx"></i>${DEV.rx}</span><span><i class="pp p-emg"></i>${DEV.emg}</span></span>
            </div>
            <div class="hu-bezel">
              <div class="hu-lcd">
                <div class="lc-top">
                  <span class="lc-bars"><i></i><i></i><i></i><i></i></span>
                  <b class="lc-tag"></b>
                  <span class="sp"></span>
                  <b class="an a-mem">${DEV.mem}</b><b class="an a-lock">${DEV.lock}</b><b class="an a-mute">${DEV.mute}</b><b class="an a-hf">${DEV.hf}</b>
                </div>
                <div class="lc-mid">
                  <b class="lc-m"></b>
                  <div class="lc-freq"></div>
                  <div class="lc-entry"><span class="ty"></span><i class="cur"></i><span class="gh"></span></div>
                  <div class="lc-code"><i></i><i></i><i></i><i></i></div>
                  <b class="lc-boot"></b>
                  <em class="lc-unit">${DEV.mhz}</em>
                </div>
                <div class="lc-bot"></div>
                <i class="lc-scan"></i><i class="lc-glare"></i>
              </div>
            </div>
            <div class="hu-fine"><span>${DEV.fine}</span><span class="sp"></span><span>${DEV.serial}</span></div>
          </div>
          <div class="hu-fn">
            ${key('pwr', `${PWR_GLYPH}${DEV.pwr}`, '', 'fn f-pwr')}
            ${key('mut', DEV.mute, '', 'fn')}
            ${key('pre', DEV.mem, '', 'fn')}
            ${key('back', DEV.clr, '', 'fn')}
            ${key('ok', DEV.ok, '', 'fn f-ok')}
          </div>
          <div class="hu-col c-ch">
            ${knob('ch', DEV.ch, 16)}
            <div class="hu-emg">
              <div class="em-well">
                <svg class="em-ring" viewBox="0 0 60 60"><circle class="tr" cx="30" cy="30" r="26"/><circle class="pg" cx="30" cy="30" r="26"/></svg>
                <button class="em-btn" data-k="emerg" tabindex="-1"><i></i></button>
                <div class="em-guard"><i class="gd-hinge"></i><i class="gd-lip"></i><b>${DEV.lift}</b></div>
              </div>
              <b class="hu-lbl red">${DEV.emerg}</b>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>`;
  }

  /* ─────────────── state ─────────────── */
  function norm(s) {
    s = s && typeof s === 'object' ? s : {};
    const view = ['off', 'boot', 'home', 'tune', 'code', 'emergency', 'memories', 'slots', 'menu'].includes(s.view) ? s.view : 'off';
    const r = s.rx && typeof s.rx === 'object' ? s.rx : null;
    const knobs = s.knobs && typeof s.knobs === 'object' ? s.knobs : {};
    const hold = s.hold && typeof s.hold === 'object' ? s.hold : {};
    return {
      view: view === 'memories' || view === 'slots' || view === 'menu' ? 'home' : view,
      model: up(s.model) || DEV.model,
      freq: fkey(s.freq), label: str(s.label), access: ['open', 'code', 'job'].includes(s.access) ? s.access : null,
      tx: s.tx === true,
      rx: r ? { name: str(r.name), callsign: str(r.callsign), q: clamp(num(r.q, 1), 0, 1), emergency: r.emergency === true } : null,
      bars: clamp(Math.round(num(s.bars, 0)), 0, 4), nosignal: s.nosignal === true,
      volume: clamp(Math.round(num(s.volume, 0)), 0, 100), showVolume: s.showVolume === true,
      mute: s.mute === true, handsfree: s.handsfree === true,
      entry: str(s.entry).slice(0, 7), code: str(s.code).slice(0, 6), target: fkey(s.target),
      mem: Math.round(num(s.mem, 0)) || null,
      title: str(s.title) || DEV.titles[view] || '', hint: str(s.hint),
      notice: str(s.notice) || null, busy: s.busy === true, emergency: s.emergency === true,
      knobs: { vol: num(knobs.vol, -135 + 2.7 * num(s.volume, 0)), ch: num(knobs.ch, 0) },
      pressed: str(s.pressed) || null,
      hold: clamp(num(hold.emerg, 0), 0, 1),
    };
  }

  let el = null, wrap = null, dev = null, lcd = null, roll = null;
  let st = norm({}), isOpen = false, txSince = 0, guardOpen = false, guardTimer = 0;
  const held = new Map();        // key → 'mouse' | 'key' (what is held down right now)
  let pttCode = codeOf('CAPITAL'), pttName = NZR.keyName('CAPITAL');

  /* ─────────────── posting ─────────────── */
  function press(k, down) {
    if (!isOpen) return;
    NZR.post(`${APP}:press`, { key: k, down: !!down });
    const e = dev && $(`[data-k="${k}"]`, dev);
    if (e) e.classList.toggle('down', !!down);
    if (k === 'ptt') wrap.classList.toggle('ptt', !!down);
    if (down) wake();
  }
  function hold(k, src) {
    if (held.has(k)) return;
    held.set(k, src);
    press(k, true);
  }
  function release(k) {
    if (!held.has(k)) return;
    held.delete(k);
    press(k, false);
  }
  function releaseAll() { [...held.keys()].forEach(release); }
  // one detent of a knob: a down and an up
  function step(knobId, dir) {
    const k = `${knobId}${dir > 0 ? '+' : '-'}`;
    press(k, true);
    press(k, false);
    const kn = dev && $(`.hu-knob.k-${knobId}`, dev);
    if (kn) { kn.classList.remove('tick'); void kn.offsetWidth; kn.classList.add('tick'); }
  }
  // the cover closes itself a few seconds after the last touch
  function wake() {
    if (!guardOpen) return;
    clearTimeout(guardTimer);
    guardTimer = setTimeout(() => { if (!held.has('emerg')) setGuard(false); }, 6000);
  }
  function setGuard(on) {
    guardOpen = !!on;
    if (dev) dev.classList.toggle('guard-open', guardOpen);
    clearTimeout(guardTimer);
    if (guardOpen) wake();
  }

  /* ─────────────── mouse ─────────────── */
  function bindMouse() {
    // keys + mic: held while the button is down
    dev.addEventListener('pointerdown', e => {
      if (e.button !== 0) return;
      const k = e.target.closest('[data-k]');
      if (!k || k.closest('.hu-knob')) return;
      if (k.dataset.k === 'emerg' && !guardOpen) return;
      e.preventDefault();
      hold(k.dataset.k, 'mouse');
    });
    $('.hu-mic', wrap).addEventListener('pointerdown', e => { if (e.button === 0) { e.preventDefault(); hold('ptt', 'mouse'); } });
    window.addEventListener('pointerup', () => { [...held].forEach(([k, src]) => { if (src === 'mouse') release(k); }); stopKnob(); });
    // a knob being dragged follows the pointer anywhere on the page
    window.addEventListener('pointermove', e => { if (knobDrag) knobDrag.el._drag(e); });
    window.addEventListener('blur', () => { releaseAll(); stopKnob(); });
    // the EMERG cover: a click flips it up (or back down)
    $('.em-guard', dev).addEventListener('pointerdown', e => {
      if (e.button !== 0) return;
      e.preventDefault();
      e.stopPropagation();
      setGuard(!guardOpen);
      NZR.audio.click(guardOpen ? 420 : 300);
    });
    $$('.hu-knob', dev).forEach(bindKnob);
  }

  // knobs: drag round the centre (one detent per 22.5° / 15°), wheel, or press a half (repeats while held)
  let knobDrag = null;
  function stopKnob() {
    if (!knobDrag) return;
    clearTimeout(knobDrag.repeat);
    clearInterval(knobDrag.timer);
    knobDrag.el.classList.remove('grab');
    knobDrag = null;
  }
  function bindKnob(kn) {
    const id = kn.dataset.knob;
    const per = id === 'vol' ? 15 : 22.5;
    const centre = e => {
      const r = kn.getBoundingClientRect();
      const z = (window.NZRInput && window.NZRInput.legacyZoom) ? NZR.zoom : 1;
      return { x: (r.left + r.width / 2) * z, y: (r.top + r.height / 2) * z, w: r.width * z };
    };
    const angle = (e, c) => Math.atan2(e.clientY - c.y, e.clientX - c.x) * 180 / Math.PI;
    kn.addEventListener('pointerdown', e => {
      if (e.button !== 0) return;
      e.preventDefault();
      stopKnob();
      const c = centre(e);
      const dir = e.clientX < c.x ? -1 : 1;
      knobDrag = { el: kn, id, c, last: angle(e, c), acc: 0, moved: false, x: e.clientX, y: e.clientY, dir, repeat: 0, timer: 0, stepped: false };
      kn.classList.add('grab');
      // a press on a half turns once now and repeats while held still
      knobDrag.repeat = setTimeout(() => {
        if (!knobDrag || knobDrag.moved) return;
        knobDrag.stepped = true;
        step(id, knobDrag.dir);
        knobDrag.timer = setInterval(() => step(id, knobDrag.dir), 110);
      }, 380);
    });
    kn._drag = e => {
      const d = knobDrag;
      if (!d || d.el !== kn) return;
      if (!d.moved && Math.hypot(e.clientX - d.x, e.clientY - d.y) < 5) return;
      if (!d.moved) { d.moved = true; clearTimeout(d.repeat); clearInterval(d.timer); }
      const a = angle(e, d.c);
      let da = a - d.last;
      if (da > 180) da -= 360;
      if (da < -180) da += 360;
      d.last = a;
      d.acc += da;
      while (d.acc >= per) { d.acc -= per; step(id, 1); }
      while (d.acc <= -per) { d.acc += per; step(id, -1); }
    };
    kn.addEventListener('pointerup', e => {
      const d = knobDrag;
      if (d && d.el === kn && !d.moved && !d.stepped) step(id, d.dir);
      stopKnob();
    });
    kn.addEventListener('wheel', e => {
      e.preventDefault();
      if (Math.abs(e.deltaY) < 1) return;
      step(id, e.deltaY < 0 ? 1 : -1);
    }, { passive: false });
  }

  /* ─────────────── keyboard (router keys / keysUp) ─────────────── */
  const keyDown = (k, repeatable) => e => {
    if (!isOpen) return false;
    if (e.repeat && !repeatable) return true;
    if (repeatable) { press(k, true); held.set(k, 'key'); return true; }
    hold(k, 'key');
    return true;
  };
  const keyUp = k => () => { if (!held.has(k)) return false; release(k); return true; };
  const KEYMAP = {
    '*': 'star', '#': 'hash', Enter: 'ok', NumpadEnter: 'ok', Backspace: 'back', Delete: 'back',
    ArrowUp: 'ch+', ArrowDown: 'ch-', ArrowLeft: 'vol-', ArrowRight: 'vol+', NumpadMultiply: 'star',
  };
  const REPEAT = { 'ch+': true, 'ch-': true, 'vol-': true, 'vol+': true };
  const keys = {}, keysUp = {};
  for (let d = 0; d <= 9; d++) { keys[String(d)] = keyDown(String(d)); keysUp[String(d)] = keyUp(String(d)); keys[`Numpad${d}`] = keyDown(String(d)); keysUp[`Numpad${d}`] = keyUp(String(d)); }
  Object.entries(KEYMAP).forEach(([code, k]) => { keys[code] = keyDown(k, REPEAT[k]); keysUp[code] = keyUp(k); });
  function bindPtt(name) {
    const code = codeOf(name);
    if (pttCode && pttCode !== code) { delete keys[pttCode]; delete keysUp[pttCode]; }
    pttCode = code;
    pttName = NZR.keyName(name) || 'CAPS';
    if (code) { keys[code] = keyDown('ptt'); keysUp[code] = keyUp('ptt'); }
  }
  bindPtt('CAPITAL');

  /* ─────────────── drawing ─────────────── */
  function rollFreq(v) {
    // a new layout (e.g. '---.--' → '155.50') starts from zeros so every digit rolls in
    const shape = v.replace(/\d/g, 'd');
    if (roll.shape !== shape) { roll.set(v.replace(/\d/g, '0')); void roll.el.offsetWidth; roll.shape = shape; }
    roll.set(v);
  }
  const barsHtml = (n, total = 10) => Array.from({ length: total }, (_, i) => `<i class="${i < n ? 'on' : ''}"></i>`).join('');

  function draw(raw) {
    const prev = st;
    st = norm(raw);
    if (!dev) return;
    const s = st, v = s.view, on = v !== 'off';
    if (s.tx && !prev.tx) txSince = now();
    dev.classList.toggle('on', on);
    dev.classList.toggle('boot', v === 'boot');
    dev.classList.toggle('emg', s.emergency && on);
    // light pipes
    $('.p-tx', dev).classList.toggle('on', on && s.tx);
    $('.p-rx', dev).classList.toggle('on', on && !!s.rx);
    $('.p-emg', dev).classList.toggle('on', on && s.emergency);
    // knobs (the volume knob shows the level, the channel knob its detents)
    $('.k-vol .kn-skirt', dev).style.transform = `rotate(${s.knobs.vol}deg)`;
    $('.k-ch .kn-skirt', dev).style.transform = `rotate(${s.knobs.ch}deg)`;
    // what Lua says is held (pressed) + our own held keys
    $$('[data-k]', wrap).forEach(k => k.classList.toggle('lua-down', k.dataset.k === s.pressed));
    wrap.classList.toggle('ptt', held.has('ptt') || s.pressed === 'ptt' || (on && s.tx));
    // EMERG hold progress ring (Lua times the hold)
    const ring = $('.em-ring .pg', dev);
    ring.style.strokeDasharray = `${(s.hold * 163.4).toFixed(1)} 163.4`;
    dev.classList.toggle('holding', s.hold > 0);
    if (s.emergency && on && guardOpen && !held.has('emerg')) setTimeout(() => { if (st.emergency && !held.has('emerg')) setGuard(false); }, 2200);
    drawLcd(s, prev);
  }

  function drawLcd(s) {
    const v = s.view;
    lcd.dataset.view = v;
    if (v === 'off') return;
    // top row
    // bars: the talker's quality while receiving, else the local estimate; dark during the self test
    const lit = v === 'boot' || s.nosignal ? 0 : s.rx ? Math.max(1, Math.round(s.rx.q * 4)) : s.bars;
    $$('.lc-bars i', lcd).forEach((b, i) => b.classList.toggle('on', i < lit));
    $('.lc-bars', lcd).classList.toggle('bad', s.nosignal);
    const tag = $('.lc-tag', lcd);
    const tagText = v === 'boot' ? '' : s.freq ? up(s.label || DEV.open) : '';
    if (tag.textContent !== tagText) tag.textContent = tagText;
    tag.classList.toggle('hide', !tagText);
    const ann = (c, o) => $(`.${c}`, lcd).classList.toggle('on', !!o && v !== 'boot');
    ann('a-mem', s.mem);
    ann('a-lock', s.freq && (s.access === 'code' || s.access === 'job'));
    ann('a-mute', s.mute);
    ann('a-hf', s.handsfree);
    // middle: frequency / typed digits / code cells / model
    const mode = v === 'boot' ? 'boot' : v === 'tune' ? 'entry' : v === 'code' ? 'code' : 'freq';
    lcd.dataset.mode = mode;
    $('.lc-m', lcd).textContent = mode === 'freq' && s.mem ? `M${s.mem}` : '';
    if (mode === 'freq') {
      rollFreq(s.freq || '---.--');
      $('.lc-freq', lcd).classList.toggle('none', !s.freq);
    } else if (mode === 'entry') {
      const e = s.entry, dot = e.indexOf('.');
      $('.lc-entry .ty', lcd).textContent = e;
      $('.lc-entry .gh', lcd).textContent = dot === -1 ? '.00' : '0'.repeat(Math.max(0, 2 - (e.length - dot - 1)));
    } else if (mode === 'code') {
      $$('.lc-code i', lcd).forEach((c, i) => { c.classList.toggle('on', i < s.code.length); c.classList.toggle('cur', i === s.code.length); });
    } else $('.lc-boot', lcd).textContent = s.model;
    $('.lc-unit', lcd).style.visibility = mode === 'freq' || mode === 'entry' ? '' : 'hidden';
    // bottom line: the most important thing right now
    const bot = $('.lc-bot', lcd);
    let html, cls = '';
    if (v === 'boot') { html = `<b class="bt">${esc(s.title || DEV.selftest)}</b><span class="bp"><i></i></span>`; cls = 'boot'; }
    else if (s.notice) { html = `<b class="nt">${esc(up(s.notice))}</b>`; cls = 'notice'; }
    else if (s.showVolume) { html = `<b class="chip">${s.mute ? DEV.mute : DEV.vol}</b><span class="vb">${barsHtml(Math.round(s.volume / 5), 20)}</span><b class="vn">${s.volume}</b>`; cls = s.mute ? 'vol muted' : 'vol'; }
    else if (v === 'emergency') { html = `<b class="chip red">${esc(s.title)}</b><span class="tx">${esc(up(s.hint))}</span>`; cls = 'emg'; }
    else if (v === 'tune') { html = `<b class="chip">${esc(s.title)}</b><span class="tx">${hintHtml(s.hint)}</span>`; }
    else if (v === 'code') { html = `<b class="chip amber">${esc(s.title)}</b><span class="tx">${esc(s.target || '')}</span>${s.target ? `<span class="tx dim">${DEV.mhz}</span>` : ''}`; }
    else if (s.tx) { html = `<b class="chip red">${DEV.tx}</b><span class="tx">${DEV.live}</span><span class="sp"></span><b class="tt js-txt">${mmss(now() - txSince)}</b>`; cls = 'txing'; }
    else if (s.rx) {
      const r = s.rx;
      html = `<b class="chip ${r.emergency ? 'red' : 'green'}">${r.emergency ? DEV.emg : DEV.rx}</b>${r.callsign ? `<b class="cs">${esc(up(r.callsign))}</b>` : ''}<span class="tx nm">${esc(r.name || (r.callsign ? '' : DEV.unit))}</span><span class="sp"></span><span class="q">${barsHtml(Math.round(r.q * 5), 5)}</span>`;
      cls = 'rxing';
    } else if (s.nosignal) { html = `<b class="chip red">${DEV.nosignal}</b>`; cls = 'nosig'; }
    else if (!s.freq) { html = `<span class="tx dim">${DEV.keyin}</span>`; }
    else { html = `<span class="tx dim">${DEV.vol}</span><span class="vb sm">${barsHtml(Math.round(s.volume / 10), 10)}</span><span class="sp"></span>${s.busy ? '<span class="busy"><i></i><i></i><i></i></span>' : ''}`; cls = s.mute ? 'idle muted' : 'idle'; }
    if (bot._h !== html) { bot.innerHTML = html; bot._h = html; }
    bot.className = `lc-bot ${cls}`;
  }
  const hintHtml = h => esc(h).replace(/(^|\s)(\*|#|OK|BACK|0-9)(?=\s|$)/g, '$1<kbd>$2</kbd>').replace(/\s{2,}/g, ' ');

  // TX timer
  setInterval(() => {
    if (!isOpen || !st.tx || !lcd) return;
    const e = $('.js-txt', lcd);
    if (e) e.textContent = mmss(now() - txSince);
  }, 250);

  /* ─────────────── cord (coiled, from the mic to the jack) ─────────────── */
  function offsetIn(node, root) {
    let x = 0, y = 0;
    while (node && node !== root) { x += node.offsetLeft; y += node.offsetTop; node = node.offsetParent; }
    return { x, y };
  }
  function drawCord() {
    const rig = $('.hu-rig', wrap), mic = $('.mc-strain', wrap), jack = $('.hu-jack i', wrap);
    if (!rig || !mic || !jack || !rig.offsetWidth) return;
    const a = offsetIn(mic, rig), b = offsetIn(jack, rig);
    const p0 = { x: a.x + mic.offsetWidth / 2, y: a.y + mic.offsetHeight - 2 };
    const p2 = { x: b.x + jack.offsetWidth / 2, y: b.y + jack.offsetHeight / 2 + 2 };
    const c = { x: (p0.x + p2.x) / 2 - 10, y: Math.max(p0.y, p2.y) + 30 };
    const q = (t2, k) => (1 - t2) * (1 - t2) * p0[k] + 2 * (1 - t2) * t2 * c[k] + t2 * t2 * p2[k];
    const pts = [];
    const n = 90, coils = 15, amp = 6;
    for (let i = 0; i <= n; i++) {
      const u = i / n;
      const x = q(u, 'x'), y = q(u, 'y');
      const dx = q(Math.min(1, u + 0.01), 'x') - q(Math.max(0, u - 0.01), 'x'), dy = q(Math.min(1, u + 0.01), 'y') - q(Math.max(0, u - 0.01), 'y');
      const l = Math.hypot(dx, dy) || 1;
      // ends straight, coils in the middle
      const env = Math.min(1, u * 9, (1 - u) * 9);
      const o = Math.sin(u * coils * Math.PI * 2) * amp * env;
      pts.push(`${(x - dy / l * o).toFixed(1)} ${(y + dx / l * o + Math.cos(u * coils * Math.PI * 2) * 1.6 * env).toFixed(1)}`);
    }
    const d = `M${pts.join('L')}`;
    const svg = $('.hu-cord', wrap);
    svg.setAttribute('width', rig.offsetWidth);
    svg.setAttribute('height', rig.offsetHeight + 70);
    $$('path', svg).forEach(p => p.setAttribute('d', d));
    $('.plug', svg).setAttribute('transform', `translate(${p2.x.toFixed(1)} ${(p2.y - 2).toFixed(1)})`);
  }

  /* ─────────────── hints ─────────────── */
  function drawHints() {
    const host = $('.hu-hints', wrap);
    NZR.ui.KeyHints(host, [
      { keys: ['ESC'], label: t('ui.hu_close', 'Close') },
      { keys: [pttName], label: t('ui.hu_talk', 'Hold to talk') },
      { keys: ['0-9'], label: t('ui.hu_type', 'Key in a channel') },
      { keys: ['↑', '↓'], label: t('ui.hu_channel', 'Channel') },
      { keys: ['←', '→'], label: t('ui.hu_volume', 'Volume') },
    ]);
    // <b> on purpose: .nzr-hints styles every <span> inside as a chip
    host.firstElementChild.insertAdjacentHTML('beforeend', '<b class="hu-sig"><b class="nz-sig"><b class="nz-mark xs"></b>NAYZEEE</b></b>');
  }

  /* ═══════════════════════════ app ═══════════════════════════ */
  NZR.app(APP, {
    init(root) {
      el = root;
      el.innerHTML = markup();
      wrap = $('.hu-wrap', el);
      dev = $('.hu-dev', el);
      lcd = $('.hu-lcd', el);
      roll = NZR.ui.Odometer($('.lc-freq', lcd), { value: '---.--', blink: false });
      bindMouse();
      drawHints();
      NZR.onCore('config', c => {
        if (c && c.keys && c.keys.ptt) bindPtt(c.keys.ptt);
        relabel(el);
        drawHints();
      });
    },
    open(data) {
      isOpen = true;
      releaseAll();
      setGuard(false);
      wrap.classList.remove('in');
      void wrap.offsetWidth;
      wrap.classList.add('in');
      draw(data);
      requestAnimationFrame(drawCord);
      if (document.fonts && document.fonts.ready) document.fonts.ready.then(drawCord);
    },
    close() {
      isOpen = false;
      held.clear();
      stopKnob();
      setGuard(false);
      $$('.down', wrap).forEach(e => e.classList.remove('down'));
      wrap.classList.remove('ptt');
    },
    msg: { state: draw },
    keys,
    keysUp,
    preview() { Fake.start(); },
  });
  window.addEventListener('resize', () => { if (isOpen) drawCord(); });

  /* ═══════════════════════════ browser preview: a live fake MV-90 firmware ═══════════════════════════
     Behaves like client/modules/firmware.lua for device 'vehicle' closely enough to click through:
     PWR boots, digits tune (155.50 asks for code 1234), MEM cycles memories, the knobs turn,
     EMERG held 1.5 s sends the alert, the mic / PTT key transmits, someone talks now and then. */
  const Fake = (() => {
    const DB = {
      '155.50': { label: 'LSPD Dispatch', access: 'code', code: '1234' }, '160.25': { label: 'EMS Main', access: 'open' },
      '412.75': { label: 'Tac 2', access: 'job' }, '911.00': { denied: true },
    };
    const MEMS = ['155.50', '160.25', '412.75', '48.20'];
    const d = { on: true, view: 'home', bootAt: 0, f: '160.25', vol: 70, mute: false, entry: '', code: '', pending: null, mem: 2, ch: 0,
      notice: null, noticeUntil: 0, volUntil: 0, emergUntil: 0, emergAt: 0, tx: false, rx: null, rxUntil: 0, pressed: null };
    const T = () => now();
    const notice = (txt, ms = 1500) => { d.notice = txt; d.noticeUntil = T() + ms; };
    function join(f, code) {
      const c = DB[f] || {};
      if (c.denied) return notice('RESTRICTED');
      if (c.access === 'code' && code === undefined) { d.view = 'code'; d.pending = f; d.code = ''; return; }
      if (c.access === 'code' && code !== c.code) { d.view = 'home'; d.pending = null; return notice('CODE REJECTED'); }
      d.f = f; d.view = 'home'; d.pending = null;
      const i = MEMS.indexOf(f);
      d.mem = i === -1 ? null : i + 1;
    }
    function typeChar(e, ch) {
      const dot = e.indexOf('.');
      if (ch === '.') return dot === -1 ? (e === '' ? '0.' : e + '.') : null;
      if (dot !== -1) return e.length - dot - 1 >= 2 ? null : e + ch;
      if (e.length >= 3) return `${e}.${ch}`;
      return e + ch;
    }
    function cycle(dir) {
      const i = d.mem ? d.mem - 1 : -1;
      const n = (i + dir + MEMS.length) % MEMS.length;
      d.mem = n + 1; d.f = MEMS[n];
      notice(`M${n + 1} · ${MEMS[n]}`);
    }
    function press(k, down) {
      if (!down) {
        if (k === 'ptt') d.tx = false;
        if (k === 'emerg') d.emergAt = 0;
        if (d.pressed === k) d.pressed = null;
        return;
      }
      if (!/^(vol|ch)[+-]$/.test(k)) d.pressed = k;
      if (k === 'ptt') { if (d.on && d.f && d.view !== 'boot') d.tx = true; else if (d.on) notice('NO CHANNEL'); return; }
      if (!d.on) { if (k === 'pwr') { d.on = true; d.view = 'boot'; d.bootAt = T(); NZR.sfx.play('boot'); } else NZR.sfx.play('error'); return; }
      if (d.view === 'boot') return;
      NZR.sfx.play('key');
      if (k === 'pwr') { d.on = false; d.view = 'off'; d.tx = false; NZR.sfx.play('power_off'); return; }
      if (k === 'vol+' || k === 'vol-') { d.vol = clamp(d.vol + (k === 'vol+' ? 5 : -5), 0, 100); d.volUntil = T() + 1200; return; }
      if (k === 'mut') { d.mute = !d.mute; return notice(d.mute ? 'MUTED' : 'SOUND ON'); }
      if (k === 'emerg') { d.emergAt = T(); return; }
      if (d.view === 'emergency') { if (k === 'ok' || k === 'back') d.view = 'home'; return; }
      if (d.view === 'code') {
        if (/^\d$/.test(k) && d.code.length < 4) d.code += k;
        else if (k === 'back') { if (d.code) d.code = d.code.slice(0, -1); else d.view = 'home'; }
        else if (k === 'hash') d.view = 'home';
        else if (k === 'ok' && d.code.length === 4) join(d.pending, d.code);
        else NZR.sfx.play('error');
        return;
      }
      if (k === 'ch+' || k === 'ch-') { d.ch += k === 'ch+' ? 1 : -1; return cycle(k === 'ch+' ? 1 : -1); }
      if (k === 'pre') return cycle(1);
      if (/^\d$/.test(k) || k === 'star') {
        const e = typeChar(d.view === 'tune' ? d.entry : '', k === 'star' ? '.' : k);
        if (e === null) return NZR.sfx.play('error');
        d.entry = e; d.view = 'tune';
        return;
      }
      if (d.view === 'tune') {
        if (k === 'back') { d.entry = d.entry.slice(0, -1); if (!d.entry) d.view = 'home'; }
        else if (k === 'hash') { d.entry = ''; d.view = 'home'; }
        else if (k === 'ok') {
          const n = Number(d.entry);
          d.entry = '';
          d.view = 'home';
          if (!(n >= 1 && n <= 999.99)) return notice('OUT OF BAND');
          join(n.toFixed(2));
        }
        return;
      }
      if (k === 'hash' && d.f) { d.f = null; d.mem = null; return notice('CLEARED'); }
      if (k === 'back') { d.notice = null; return; }
      NZR.sfx.play('error');
    }
    function render() {
      const t2 = T();
      if (d.view === 'boot' && t2 - d.bootAt > 1500) d.view = 'home';
      if (d.notice && t2 > d.noticeUntil) d.notice = null;
      let hold = d.holdFix || 0;
      if (d.emergAt && !d.holdFix) {
        hold = clamp((t2 - d.emergAt) / 1500, 0, 1);
        if (hold >= 1) { d.emergAt = 0; hold = 0; d.view = 'emergency'; d.emergUntil = t2 + 9000; NZR.sfx.play('emergency'); }
      }
      if (d.view === 'emergency' && t2 > d.emergUntil) d.view = 'home';
      // somebody talks on the channel now and then
      if (d.on && d.f && !d.tx && !d.rx && t2 > d.rxUntil + 7000) { d.rx = { name: 'Maya Reyes', callsign: '2A14', q: 0.86 }; d.rxUntil = t2 + 3200; }
      if (d.rx && (t2 > d.rxUntil || d.tx || !d.f)) { d.rx = null; d.rxUntil = t2; }
      if (d.rx) d.rx.q = clamp(0.8 + Math.sin(t2 / 300) * 0.08, 0, 1);
      const c = DB[d.f] || {};
      const dt = new Date();
      return {
        view: d.on ? d.view : 'off', skin: 'mv90', model: 'MV-90', freq: d.f, label: d.f ? c.label || null : null, access: d.f ? c.access || 'open' : null,
        slot: 1, slots: [{ n: 1, f: d.f, tx: true, rx: !!d.rx }], tx: d.tx && d.on, rx: d.on ? d.rx : null, bars: 3, nosignal: false, jam: 0.04,
        volume: d.vol, showVolume: t2 < d.volUntil, mute: d.mute, handsfree: false, clicks: true, battery: 1, time: `${pad2(dt.getHours())}:${pad2(dt.getMinutes())}`,
        entry: d.view === 'tune' ? d.entry : '', code: d.view === 'code' ? '*'.repeat(d.code.length) : '', target: d.view === 'code' ? d.pending : null,
        mem: d.f ? d.mem : null, title: { tune: 'TUNE', code: 'ACCESS CODE', emergency: 'EMERGENCY', boot: 'SELF TEST' }[d.view] || null,
        hint: { tune: '* point  ·  OK join', code: '4 digits  ·  OK send', emergency: 'ALERT SENT  ·  MIC OPEN' }[d.view] || null,
        notice: d.on ? d.notice : null, busy: false, emergency: d.on && d.view === 'emergency',
        knobs: { vol: Math.round((-135 + 2.7 * d.vol) * 10) / 10, ch: d.ch * 22.5 }, pressed: d.pressed, hold: hold > 0 ? { emerg: Math.round(hold * 100) / 100 } : null,
      };
    }
    function start() {
      const q = new URLSearchParams(location.search).get('hu');
      if (q === 'off') { d.on = false; d.view = 'off'; }
      if (q === 'tune') { d.view = 'tune'; d.entry = '412.7'; }
      if (q === 'code') { d.view = 'code'; d.pending = '155.50'; d.code = '12'; }
      if (q === 'rx') { d.rx = { name: 'Maya Reyes', callsign: '2A14', q: 0.86 }; d.rxUntil = T() + 1e9; }
      if (q === 'tx') { d.tx = true; d.pressed = 'ptt'; }
      if (q === 'emergency') { d.view = 'emergency'; d.emergUntil = T() + 1e9; }
      if (q === 'volume') { d.vol = 55; d.volUntil = T() + 1e9; }
      if (q === 'notice') notice('M2 · 160.25', 1e9);
      if (q === 'hold') { d.emergAt = T(); d.holdFix = 0.62; }
      if (q !== 'rx') d.rxUntil = T() + (q ? 1e9 : 0);
      NZR.mock(`${APP}:press`, p => { press(p.key, p.down); push(); return { ok: true }; });
      NZR.mock(`${APP}:close`, () => ({ ok: true }));
      NZR.demo(APP, render());
      if (q === 'guard' || q === 'hold') setGuard(true);
      if (q === 'hold') { held.set('emerg', 'mouse'); $('.em-btn', dev).classList.add('down'); }
      let last = '';
      function push() { const s = render(); const sig = JSON.stringify(s); if (sig !== last) { last = sig; if (NZR.isOpen(APP)) draw(s); } }
      setInterval(push, 100);
    }
    return { start };
  })();
})();
