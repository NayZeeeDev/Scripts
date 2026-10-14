/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · radial — EMS job menu
   Based on the NAYZEEE UI pack "03 · Orbit" wheel, adapted to the NZA app router and
   the in-game rules (no backdrop-filter). Centre: your name + unit status (10-8 / 10-7 /
   ENR …); in a submenu the submenu title. Mouse angle selection like a weapon wheel.

   Lua → JS
     open   { name, callsign, status, statusLabel, tone, items: [ { id, label, icon, desc, danger,
              active, disabled, items: [...] } ], key: 'F6', locale }
     header { name, status, statusLabel, tone }
   JS → Lua
     radial:select { id } → { close: true } | { items, header }   (toggles stay open)
   Keys: mouse / 1-9 quick pick · ←/→ move · Enter select · RMB / Backspace back · ESC / F6 close
   ═══════════════════════════════════════════════════════════ */
(() => {
  const K = window.NZD;
  const esc = NZA.esc, icon = NZA.icon;
  const R_IN = 104, R_OUT = 226, GAP = 1.1, HALF = 270;
  let tr = K ? K.tr({}) : ((k, fb) => fb);
  let data = { items: [] }, path = [], sel = -1, busy = false, key = 'F6';
  let el, wheel, svgEl, labsEl, hubName, hubSub, hubDesc, hubEl, footEl;

  const pt = (r, deg) => [r * Math.cos(deg * Math.PI / 180), r * Math.sin(deg * Math.PI / 180)];
  function arc(r1, r2, a0, a1) {
    const large = a1 - a0 > 180 ? 1 : 0;
    const [x0, y0] = pt(r2, a0), [x1, y1] = pt(r2, a1), [x2, y2] = pt(r1, a1), [x3, y3] = pt(r1, a0);
    return `M${x0} ${y0}A${r2} ${r2} 0 ${large} 1 ${x1} ${y1}L${x2} ${y2}A${r1} ${r1} 0 ${large} 0 ${x3} ${y3}Z`;
  }
  function stroke(r, a0, a1) {
    const [x0, y0] = pt(r, a0), [x1, y1] = pt(r, a1);
    return `M${x0} ${y0}A${r} ${r} 0 ${a1 - a0 > 180 ? 1 : 0} 1 ${x1} ${y1}`;
  }

  // current ring: root items, or a submenu with a Back segment at the bottom
  function ring() {
    let list = data.items || [];
    const titles = [];
    for (const id of path) {
      const it = list.find(x => x.id === id);
      if (!it || !it.items) break;
      titles.push(it.label);
      list = it.items;
    }
    if (path.length) {
      list = list.slice();
      const n = list.length + 1;
      const backAt = Math.min(list.length, Math.round(n / 2 + 0.5) - 0);
      list.splice(Math.min(backAt, list.length), 0, { id: '__back', label: tr('r_back', 'Back'), icon: 'arrow-l', back: true });
    }
    return { list, title: titles[titles.length - 1] || null };
  }
  const step = () => 360 / Math.max(1, ring().list.length);
  const center = i => -90 - step() / 2 + i * step();

  function render(animate = true) {
    const { list } = ring();
    const n = list.length, s = 360 / Math.max(1, n);
    let svg = `<defs><radialGradient id="rd-g" cx="0" cy="0" r="${R_OUT}" gradientUnits="userSpaceOnUse"><stop offset="${R_IN / R_OUT}" stop-color="#0d1011" stop-opacity=".95"/><stop offset="1" stop-color="#08090a" stop-opacity=".9"/></radialGradient>
      <linearGradient id="rd-t" x1="0" y1="-1" x2="0" y2="1"><stop offset="0" stop-color="#0fd4c4"/><stop offset="1" stop-color="#067d74"/></linearGradient></defs>`;
    svg += `<circle class="rd-disc" r="${R_OUT + 14}"/><circle class="rd-dash" r="${R_OUT + 22}"/>`;
    for (let t = 0; t < 72; t++) {
      const [x0, y0] = pt(R_OUT + 6, t * 5), [x1, y1] = pt(t % 6 ? R_OUT + 9 : R_OUT + 12, t * 5);
      svg += `<line class="rd-tick" x1="${x0}" y1="${y0}" x2="${x1}" y2="${y1}"/>`;
    }
    svg += '<g class="rd-segs">' + list.map((it, i) => {
      const c = -90 - s / 2 + i * s;
      const cls = ['rd-seg', it.danger ? 'danger' : '', it.active ? 'act' : '', it.disabled ? 'off' : '', it.back ? 'back' : ''].join(' ');
      return `<path class="${cls}" data-i="${i}" d="${arc(R_IN, R_OUT, c - s / 2 + GAP, c + s / 2 - GAP)}"/>`;
    }).join('') + '<path class="rd-halo" d="" opacity="0"/></g>';
    svgEl.innerHTML = svg;

    const mid = (R_IN + R_OUT) / 2 + 4;
    labsEl.innerHTML = list.map((it, i) => {
      const [x, y] = pt(mid, -90 - s / 2 + i * s);
      const cls = ['rd-lab', it.danger ? 'danger' : '', it.active ? 'act' : '', it.disabled ? 'off' : '', it.back ? 'back' : ''].join(' ');
      return `<div class="${cls}" data-i="${i}" style="left:${HALF + x}px;top:${HALF + y}px">
        ${it.back ? '' : `<span class="num">${list.slice(0, i).filter(z => !z.back).length + 1}</span>`}
        ${icon(it.icon || 'more')}<span class="t">${esc(it.label)}</span>${it.items && !it.disabled ? '<i class="sub"></i>' : ''}${it.active ? `<em>${esc(tr('r_on', 'ON'))}</em>` : ''}</div>`;
    }).join('');
    if (animate) ['.rd-segs', '.rd-labs'].forEach(q => { const e = el.querySelector(q); e.style.animation = 'none'; void e.offsetWidth; e.style.animation = ''; });
    highlight(-1);
  }

  function header() {
    const r = ring();
    hubEl.classList.toggle('sub', path.length > 0);
    hubName.textContent = data.name || '';
    if (path.length) {
      hubSub.innerHTML = `<span class="rd-title">${esc(String(r.title || '').toUpperCase())}</span>`;
    } else {
      hubSub.innerHTML = `<span class="rd-st ${esc(data.tone || 'off')}"><i></i><b>${esc(data.status || '10-7')}</b>${data.statusLabel ? `<span>${esc(data.statusLabel)}</span>` : ''}</span>`;
    }
  }

  function highlight(i) {
    sel = i;
    const { list } = ring();
    const s = 360 / Math.max(1, list.length);
    el.querySelectorAll('.rd-seg').forEach(p => p.classList.toggle('on', +p.dataset.i === i));
    el.querySelectorAll('.rd-lab').forEach(p => p.classList.toggle('on', +p.dataset.i === i));
    const halo = el.querySelector('.rd-halo');
    const it = list[i];
    header();
    if (it) {
      const c = -90 - s / 2 + i * s;
      halo.setAttribute('d', stroke(R_OUT + 7, c - s / 2 + GAP + 1.5, c + s / 2 - GAP - 1.5));
      halo.setAttribute('class', `rd-halo ${it.danger ? 'danger' : ''} ${it.disabled ? 'off' : ''}`);
      halo.setAttribute('opacity', '1');
      hubDesc.textContent = it.back ? tr('r_back_d', 'Back to the previous menu') : (it.desc || (it.items ? K.fmt(tr('r_options', '%d options'), it.items.length) : tr('r_click', 'Click to confirm')));
      hubDesc.classList.toggle('warn', !!it.disabled);
    } else {
      halo.setAttribute('opacity', '0');
      hubDesc.textContent = path.length ? tr('r_hint_sub', 'Right click to go back') : tr('r_hint', 'Move the mouse to choose');
      hubDesc.classList.remove('warn');
    }
  }

  function shake() {
    wheel.classList.remove('shake'); void wheel.offsetWidth; wheel.classList.add('shake');
    NZA.audio.click(240);
  }

  async function pick(i) {
    const { list } = ring();
    const it = list[i];
    if (!it || busy) return;
    if (it.back) return back();
    if (it.disabled) return shake();
    NZA.audio.click(880);
    if (it.items) { path.push(it.id); render(); return; }
    busy = true;
    const res = await NZA.post('radial:select', { id: it.id });
    busy = false;
    if (res && res.items) {
      data.items = res.items;
      if (res.header) Object.assign(data, res.header);
      const keep = sel;
      render(false);
      highlight(keep);
    }
  }
  function back() {
    if (path.length) { path.pop(); NZA.audio.click(520); render(); } else NZA.close('radial');
  }

  function onMove(e) {
    if (!NZA.isOpen('radial')) return;
    const r = wheel.getBoundingClientRect();
    const z = r.width / (HALF * 2);
    const dx = e.clientX - (r.left + r.width / 2), dy = e.clientY - (r.top + r.height / 2);
    if (Math.hypot(dx, dy) < (R_IN - 12) * z) { if (sel !== -1) highlight(-1); return; }
    const n = ring().list.length, s = 360 / Math.max(1, n);
    const a = Math.atan2(dy, dx) * 180 / Math.PI;
    const i = Math.floor((((a - (-90 - s)) % 360) + 360) % 360 / s) % n;
    if (i !== sel) { highlight(i); NZA.audio.tick(); }
  }

  NZA.app('radial', {
    noscale: true,
    camInput: false,
    init(root) {
      el = root;
      root.innerHTML = `
        <div class="rd-wrap">
          <div class="rd-wheel">
            <svg viewBox="-270 -270 540 540"></svg>
            <div class="rd-labs"></div>
            <div class="rd-hub">
              <span class="nz-mark sm"></span>
              <span class="rd-back">${icon('chev-l')}<span></span></span>
              <b class="rd-name"></b>
              <div class="rd-sub"></div>
              <p class="rd-desc"></p>
            </div>
          </div>
          <div class="rd-foot"></div>
        </div>`;
      wheel = root.querySelector('.rd-wheel');
      svgEl = root.querySelector('svg');
      labsEl = root.querySelector('.rd-labs');
      hubEl = root.querySelector('.rd-hub');
      hubName = root.querySelector('.rd-name');
      hubSub = root.querySelector('.rd-sub');
      hubDesc = root.querySelector('.rd-desc');
      footEl = root.querySelector('.rd-foot');
      window.addEventListener('mousemove', onMove);
      // the menu key closes the menu again
      window.addEventListener('keydown', e => {
        if (!NZA.isOpen('radial') || e.repeat) return;
        const k = String(key || '').toUpperCase();
        if (k && (String(e.key).toUpperCase() === k || String(e.code).toUpperCase() === k || String(e.code).toUpperCase() === 'KEY' + k)) { e.preventDefault(); NZA.close('radial'); }
      });
      root.addEventListener('mousedown', e => {
        if (!NZA.isOpen('radial')) return;
        if (e.button === 2) { e.preventDefault(); back(); return; }
        if (e.button !== 0) return;
        if (sel === -1) { if (e.target.closest('.rd-hub')) back(); return; }
        pick(sel);
      });
    },
    open(d) {
      data = Object.assign({ items: [] }, d || {});
      if (d && d.locale && K) tr = K.tr(d.locale);
      key = (d && d.key) || 'F6';
      path = []; busy = false;
      el.querySelector('.rd-back span').textContent = tr('r_back', 'Back');
      footEl.innerHTML = `<span><span class="nz-key">LMB</span>${esc(tr('r_f_select', 'Select'))}</span><span><span class="nz-key">RMB</span>${esc(tr('r_back', 'Back'))}</span>` +
        `<span><span class="nz-key">1-9</span>${esc(tr('r_f_quick', 'Quick pick'))}</span><span><span class="nz-key">${esc(key)}</span>${esc(tr('r_f_close', 'Close'))}</span><span class="nz-sig"><span class="nz-mark xs"></span>NAYZEEE</span>`;
      wheel.classList.remove('in'); void wheel.offsetWidth; wheel.classList.add('in');
      render();
    },
    close() { path = []; sel = -1; },
    msg: {
      header(h) { Object.assign(data, h || {}); header(); },
    },
    keys: {
      Escape() { NZA.close('radial'); },
      Backspace() { back(); },
      Enter() { if (sel >= 0) pick(sel); },
      ArrowRight() { const n = ring().list.length; highlight((sel + 1 + n) % n); },
      ArrowLeft() { const n = ring().list.length; highlight(((sel < 0 ? 0 : sel) - 1 + n) % n); },
      1() { quick(1); }, 2() { quick(2); }, 3() { quick(3); }, 4() { quick(4); }, 5() { quick(5); },
      6() { quick(6); }, 7() { quick(7); }, 8() { quick(8); }, 9() { quick(9); },
    },
    preview() {
      NZA.mock('radial:select', d => {
        if (d.id === 'd_npc') { const it = data.items[0].items.find(x => x.id === 'd_npc'); it.active = !it.active; return { items: data.items }; }
        NZA.toast({ title: 'Radial', message: `Selected ${d.id}`, type: 'info' });
        return { close: true };
      });
      NZA.demo('radial', {
        name: 'John Doe', callsign: 'Unit 04', status: '10-8', statusLabel: 'Available', tone: 'teal', key: 'F6',
        items: [
          { id: 'dispatch', label: 'Dispatch', icon: 'broadcast', desc: 'Calls, units, queue and map', items: [
            { id: 'd_log', label: 'Call log', icon: 'list' }, { id: 'd_queue', label: 'Hospital queue', icon: 'users' },
            { id: 'd_map', label: 'Unit map', icon: 'map' }, { id: 'd_npc', label: 'NPC calls', icon: 'call', active: true, desc: 'You receive NPC calls' },
            { id: 'd_respond', label: 'Respond', icon: 'siren', desc: 'Respond to the most urgent open call' },
            { id: 'd_clear', label: 'Clear call', icon: 'x', danger: true, disabled: true, desc: 'You are not on a call' },
            { id: 'd_status', label: 'Out of service', icon: 'pause', desc: 'Go 10-7, no call cards' },
            { id: 'd_pager', label: 'Pager', icon: 'pager' },
          ] },
          { id: 'patient', label: 'Patient', icon: 'person', desc: 'Nearest patient', items: [
            { id: 'p_exam', label: 'Examine', icon: 'stetho' }, { id: 'p_pulse', label: 'Check pulse', icon: 'pulse' },
            { id: 'p_breath', label: 'Check breathing', icon: 'lungs' }, { id: 'p_walk', label: 'Ask to walk', icon: 'walk' },
          ] },
          { id: 'duty', label: 'Go off duty', icon: 'power', danger: true, desc: 'Sign out and stop receiving calls' },
          { id: 'stretcher', label: 'Stretcher', icon: 'bed', disabled: true, desc: 'No stretcher nearby' },
        ],
      });
      path = ['dispatch']; render(); highlight(3);
    },
  });

  function quick(n) {
    const { list } = ring();
    const real = list.filter(x => !x.back);
    const it = real[n - 1];
    if (!it) return;
    pick(list.indexOf(it));
  }
})();
