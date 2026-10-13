// Colour picker popover: saturation / brightness square, hue slider, hex box and recent colours.
// NH.ColorPicker.open(anchor, { value, def, onInput(hex), onClose(changed, outside) })
(() => {
  const NH = window.NH;
  const KEY = 'nh-cp-recent';

  const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
  const toHex = (r, g, b) => '#' + [r, g, b].map((v) => Math.round(v).toString(16).padStart(2, '0')).join('');
  const parse = (v) => {
    let s = String(v || '').trim().replace(/^#/, '');
    if (/^[\da-f]{3}$/i.test(s)) s = s.split('').map((c) => c + c).join('');
    return /^[\da-f]{6}$/i.test(s) ? '#' + s.toLowerCase() : null;
  };
  NH.parseHex = parse;
  const hsv2rgb = (h, s, v) => {
    const f = (n) => { const k = (n + h / 60) % 6; return v - v * s * Math.max(0, Math.min(k, 4 - k, 1)); };
    return [f(5) * 255, f(3) * 255, f(1) * 255];
  };
  const rgb2hsv = (hex) => {
    const n = parseInt(hex.slice(1), 16), r = (n >> 16) / 255, g = ((n >> 8) & 255) / 255, b = (n & 255) / 255;
    const max = Math.max(r, g, b), d = max - Math.min(r, g, b);
    let h = 0;
    if (d) h = max === r ? ((g - b) / d) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
    return [(h * 60 + 360) % 360, max ? d / max : 0, max];
  };
  const recent = () => { try { return JSON.parse(localStorage.getItem(KEY)) || []; } catch (_) { return []; } };
  const remember = (hex) => {
    const list = [hex, ...recent().filter((c) => c !== hex)].slice(0, 9);
    try { localStorage.setItem(KEY, JSON.stringify(list)); } catch (_) { /* private mode: no recents */ }
  };

  let el, st = null, raf = 0;

  const build = () => {
    el = document.createElement('div');
    el.className = 'cp';
    el.innerHTML = `<div class="cp-sv"><i class="cp-dot"></i></div>
      <div class="cp-hue"><i class="cp-knob"></i></div>
      <div class="cp-row"><span class="cp-prev" title="Click the left half to go back"><i class="cp-old"></i><i class="cp-new"></i></span>
        <label class="cp-hexw"><em>#</em><input class="cp-hex" maxlength="7" spellcheck="false"/></label>
        <button class="cp-ib" data-cpa="copy" title="Copy">${NH.ic('copy')}</button></div>
      <div class="cp-rec"></div>
      <div class="cp-foot"><button class="btn-line" data-cpa="def">${NH.ic('reset')}Default</button><button class="btn-teal" data-cpa="done">${NH.ic('check')}Done</button></div>`;
    (document.getElementById('settings') || document.body).appendChild(el);

    const sv = el.querySelector('.cp-sv'), hue = el.querySelector('.cp-hue');
    const drag = (area, fn) => area.addEventListener('mousedown', (e) => {
      e.preventDefault();
      const move = (ev) => { const r = area.getBoundingClientRect(); fn(clamp((ev.clientX - r.left) / r.width, 0, 1), clamp((ev.clientY - r.top) / r.height, 0, 1)); };
      const up = () => { window.removeEventListener('mousemove', move); window.removeEventListener('mouseup', up); area.classList.remove('drag'); };
      area.classList.add('drag');
      move(e);
      window.addEventListener('mousemove', move);
      window.addEventListener('mouseup', up);
    });
    drag(sv, (x, y) => { st.s = x; st.v = 1 - y; update(); });
    drag(hue, (x) => { st.h = x * 360; update(); });
    hue.addEventListener('wheel', (e) => { e.preventDefault(); st.h = (st.h + (e.deltaY > 0 ? 3 : -3) + 360) % 360; update(); }, { passive: false });

    const hex = el.querySelector('.cp-hex');
    hex.addEventListener('input', () => { const c = parse(hex.value); if (c) set(c, false); });
    hex.addEventListener('blur', () => { if (st) hex.value = st.hex.slice(1).toUpperCase(); });
    hex.addEventListener('keydown', (e) => { if (e.key === 'Enter') close(); });

    el.addEventListener('click', (e) => {
      const sw = e.target.closest('[data-cpc]');
      if (sw) return set(sw.dataset.cpc);
      if (e.target.closest('.cp-old')) return set(st.start);
      const a = e.target.closest('[data-cpa]')?.dataset.cpa;
      if (a === 'done') close();
      else if (a === 'def' && st.def) set(st.def);
      else if (a === 'copy') {
        hex.select();
        try { document.execCommand('copy'); } catch (_) { /* CEF without clipboard: text stays selected */ }
        const b = e.target.closest('[data-cpa]');
        b.classList.add('ok'); setTimeout(() => b.classList.remove('ok'), 900);
      }
    });
    // a click anywhere else closes it (the button that opened it toggles it itself)
    document.addEventListener('mousedown', (e) => {
      if (st && !el.contains(e.target) && !st.anchor.contains(e.target)) close(true);
    }, true);
  };

  const set = (hex, syncText = true) => {
    [st.h, st.s, st.v] = rgb2hsv(hex);
    update(syncText, hex);
  };

  // repaint the picker and send the colour out at most once a frame
  const update = (syncText = true, exact) => {
    st.hex = exact || toHex(...hsv2rgb(st.h, st.s, st.v));
    el.style.setProperty('--cp-h', `hsl(${st.h}, 100%, 50%)`);
    el.style.setProperty('--cp-c', st.hex);
    el.querySelector('.cp-dot').style.cssText = `left:${st.s * 100}%;top:${(1 - st.v) * 100}%`;
    el.querySelector('.cp-knob').style.left = `${st.h / 3.6}%`;
    if (syncText && document.activeElement !== el.querySelector('.cp-hex')) el.querySelector('.cp-hex').value = st.hex.slice(1).toUpperCase();
    if (!raf) raf = requestAnimationFrame(() => { raf = 0; if (st && st.hex !== st.sent) { st.sent = st.hex; st.onInput?.(st.hex); } });
  };

  const place = (anchor) => {
    const root = el.parentElement.getBoundingClientRect(), a = anchor.getBoundingClientRect();
    const w = el.offsetWidth, h = el.offsetHeight;
    let x = a.left - root.left, y = a.bottom - root.top + 8;
    if (y + h > root.height - 8) y = a.top - root.top - h - 8;
    el.style.left = `${clamp(x, 8, root.width - w - 8)}px`;
    el.style.top = `${clamp(y, 8, root.height - h - 8)}px`;
  };

  const close = (outside = false) => {
    if (!st) return;
    const s = st;
    st = null;
    cancelAnimationFrame(raf); raf = 0;
    if (s.hex !== s.sent) s.onInput?.(s.hex);
    el.classList.remove('on');
    s.anchor.classList.remove('open');
    const changed = s.hex !== s.start;
    if (changed) remember(s.hex);
    s.onClose?.(changed, outside);
  };

  NH.ColorPicker = {
    get isOpen() { return !!st; },
    get anchor() { return st?.anchor; },
    open(anchor, o) {
      if (!el) build();
      if (st) close();
      const start = parse(o.value) || '#ffffff';
      st = { anchor, start, sent: start, def: parse(o.def), onInput: o.onInput, onClose: o.onClose };
      el.querySelector('.cp-old').style.background = start;
      el.querySelector('[data-cpa="def"]').style.display = st.def ? '' : 'none';
      const rec = recent();
      el.querySelector('.cp-rec').innerHTML = rec.length ? `<small>Recent</small>${rec.map((c) => `<button class="cp-sw" data-cpc="${c}" style="--sw:${c}" title="${c}"></button>`).join('')}` : '';
      set(start);
      st.sent = st.hex;
      anchor.classList.add('open');
      el.classList.add('on');
      place(anchor);
    },
    // a hex typed in the settings box while the picker is open
    sync(hex) { if (st && parse(hex)) { set(parse(hex)); st.sent = st.hex; } },
    close: () => close(),
  };
})();
