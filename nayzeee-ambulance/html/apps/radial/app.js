/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · radial — EMS job menu ("orbit")
   Separate round nodes on an orbit (first node at 12 o'clock), labels as dark chips
   outside the orbit, a beam from the centre to the node under the mouse. Centre: the
   unit badge — unit ring (call progress with four phase nodes on a call, status colour
   otherwise) inside the duty ring (shift clock). A detail card under the orbit explains
   the hovered node.
   Submenus fly out from the centre; the centre, RMB or Backspace goes back (no Back node).
   Mouse angle selection like a weapon wheel.

   Lua → JS
     open   { name, callsign, grade, status, statusLabel, tone, onDuty, shift, call, stage,
              items: [ { id, label, icon, desc, danger, active, disabled, items: [...] } ], key: 'F6', locale }
     header { same header fields }
   JS → Lua
     radial:select { id } → { close: true } | { items, header }   (toggles stay open)
   Keys: mouse / 1-9 quick pick · ←/→ move · Enter select · RMB / Backspace back · ESC / F6 close
   ═══════════════════════════════════════════════════════════ */
(() => {
  const K = window.NZD;
  const esc = NZA.esc, icon = NZA.icon;
  const HALF = 380, R_HUB = 98, R_ORB = 214, R_NODE = 34, R_LAB = 262;
  let tr = K ? K.tr({}) : ((k, fb) => fb);
  let data = { items: [] }, path = [], sel = -1, busy = false, key = 'F6', shiftAt = 0, shiftT = 0;
  let el, wheel, svgEl, nodesEl, hubEl, infoEl, footEl;

  const pt = (r, deg) => [+(r * Math.cos(deg * Math.PI / 180)).toFixed(2), +(r * Math.sin(deg * Math.PI / 180)).toFixed(2)];
  function arc(r, a0, a1) {
    const [x0, y0] = pt(r, a0), [x1, y1] = pt(r, a1);
    return `M${x0} ${y0}A${r} ${r} 0 ${a1 - a0 > 180 ? 1 : 0} 1 ${x1} ${y1}`;
  }

  // current ring: root items, or a submenu
  function ring() {
    let list = data.items || [];
    const titles = [];
    for (const id of path) {
      const it = list.find(x => x.id === id);
      if (!it || !it.items) break;
      titles.push(it);
      list = it.items;
    }
    return { list, parent: titles[titles.length - 1] || null };
  }
  const angleOf = (i, n) => -90 + i * (360 / Math.max(1, n));

  /* ── static decoration + hub rings ── */
  function hubRings() {
    const onDuty = data.onDuty !== false;
    const st = data.status || (onDuty ? '10-8' : '10-7');
    const onCall = !!(K && K.onCall(st));
    let unit = '';
    if (onCall) {
      // one progress arc + four phase nodes (12 / 3 / 6 / 9 o'clock)
      const ph = K.phase(st), done = K.done(st), f = Math.max(0.02, K.fill(st));
      unit = `<path class="u-fill" d="${f >= 1 ? `${arc(78, -90, 89.9)}${arc(78, 89.9, 269.9)}` : arc(78, -90, -90 + f * 360)}"/>` +
        K.PHASES.map((_, i) => { const [x, y] = pt(78, -90 + i * 90); return `<circle class="u-nd ${i < ph || done ? 'dn' : i === ph ? 'cur' : ''}" cx="${x}" cy="${y}" r="7"/>`; }).join('');
    } else {
      unit = `<circle class="u-full ${!onDuty ? 'off' : st === '10-7' ? 'amber' : 'teal'}" r="78"/>`;
    }
    const sh = Math.max(0, Number(data.shift) || 0) + (shiftAt ? (performance.now() - shiftAt) / 1000 : 0);
    const frac = onDuty ? (sh % 3600) / 3600 : 0;
    let ticks = '';
    for (let i = 0; i < 60; i++) {
      const a = -90 + i * 6, [x0, y0] = pt(i % 5 ? 92 : 90, a), [x1, y1] = pt(95, a);
      ticks += `<line class="${i / 60 < frac ? 'on' : ''} ${i % 5 ? '' : 'q'}" x1="${x0}" y1="${y0}" x2="${x1}" y2="${y1}"/>`;
    }
    return `<g class="rd-hubrings"><circle class="h-face" r="${R_HUB}"/>${ticks}${frac > 0 ? `<path class="d-arc" d="${arc(86.5, -90, -90 + Math.max(1, frac * 360 - 0.01))}"/>` : ''}<circle class="u-trk" r="78"/>${unit}</g>`;
  }

  function render(animate = true) {
    const { list } = ring();
    const n = list.length, s = 360 / Math.max(1, n);
    let orbTicks = '';
    for (let a = 0; a < 360; a += 3) { const [x0, y0] = pt(R_ORB + 46, a), [x1, y1] = pt(a % 30 ? R_ORB + 49 : R_ORB + 54, a); orbTicks += `<line class="${a % 30 ? '' : 'q'}" x1="${x0}" y1="${y0}" x2="${x1}" y2="${y1}"/>`; }
    svgEl.innerHTML = `
      <defs>
        <radialGradient id="rd-dim" cx="0" cy="0" r="330" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#000" stop-opacity=".62"/><stop offset=".72" stop-color="#000" stop-opacity=".42"/><stop offset="1" stop-color="#000" stop-opacity="0"/></radialGradient>
        <radialGradient id="rd-face" cx="0" cy="-30" r="${R_HUB + 20}" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#1a1f22"/><stop offset=".75" stop-color="#0a0c0d"/><stop offset="1" stop-color="#060707"/></radialGradient>
        <linearGradient id="rd-beam" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#0fd4c4" stop-opacity="0"/><stop offset="1" stop-color="#0fd4c4" stop-opacity=".9"/></linearGradient>
      </defs>
      <circle r="340" fill="url(#rd-dim)"/>
      <circle class="rd-guide" r="${R_ORB - R_NODE - 18}"/>
      <circle class="rd-orbit" r="${R_ORB}"/>
      <g class="rd-otk">${orbTicks}</g>
      ${list.map((it, i) => { const [x, y] = pt(R_ORB, angleOf(i, n)); return `<circle class="rd-pad ${it.danger ? 'danger' : ''}" cx="${x}" cy="${y}" r="${R_NODE + 7}"/>`; }).join('')}
      <path class="rd-sel" d="" opacity="0"/>
      <line class="rd-beam" x1="0" y1="0" x2="0" y2="0" opacity="0"/>
      ${hubRings()}`;

    nodesEl.innerHTML = list.map((it, i) => {
      const a = angleOf(i, n), [x, y] = pt(R_ORB, a), [lx, ly] = pt(R_LAB, a);
      const c = Math.cos(a * Math.PI / 180), sn = Math.sin(a * Math.PI / 180);
      const kx = Math.max(-1, Math.min(1, c * 1.8));
      const ky = Math.abs(c) < 0.45 ? (sn < 0 ? -1 : 1) : 0;
      const cls = [it.danger ? 'danger' : '', it.active ? 'act' : '', it.disabled ? 'off' : '', it.items ? 'grp' : ''].join(' ');
      return `<div class="rd-node ${cls}" data-i="${i}" style="left:${HALF + x}px;top:${HALF + y}px;--dx:${-x}px;--dy:${-y}px;--d:${i * 28}ms">
          <span class="disc">${icon(it.icon || 'more')}</span>
          <span class="num">${i + 1}</span>
          ${it.active ? `<span class="on">${esc(tr('r_on', 'ON'))}</span>` : ''}
          ${it.disabled ? `<span class="lock">${icon('lock')}</span>` : ''}
        </div>
        <div class="rd-lab ${cls}" data-i="${i}" style="left:${HALF + lx}px;top:${HALF + ly}px;transform:translate(calc(-50% + ${(50 * kx).toFixed(1)}%),calc(-50% + ${(50 * ky).toFixed(1)}%));--d:${i * 28 + 90}ms">
          <b>${esc(it.label)}</b>${it.items && !it.disabled ? `<small>${esc(K ? K.fmt(tr('r_options', '%d options'), it.items.length) : it.items.length)}</small>` : ''}</div>`;
    }).join('');
    if (animate) { nodesEl.classList.remove('fly'); void nodesEl.offsetWidth; nodesEl.classList.add('fly'); }
    header();
    highlight(-1);
  }

  function header() {
    const r = ring();
    const onDuty = data.onDuty !== false;
    const st = data.status || (onDuty ? '10-8' : '10-7');
    hubEl.classList.toggle('sub', path.length > 0);
    if (path.length) {
      hubEl.innerHTML = `
        <span class="hb-back">${icon('arrow-l')}<span>${esc(tr('r_back', 'Back'))}</span></span>
        <span class="hb-ic">${icon(r.parent.icon || 'more')}</span>
        <b class="hb-title">${esc(r.parent.label || '')}</b>
        <span class="hb-cs">${esc(data.callsign || data.name || '')}</span>`;
    } else {
      const word = data.statusLabel || (K ? K.unitWord(st, tr) : st);
      hubEl.innerHTML = `
        <span class="hb-k">${esc(onDuty ? tr('r_unit', 'Unit') : tr('r_shift_off', 'Off shift'))}</span>
        <b class="hb-cs">${esc(data.callsign || data.name || '')}</b>
        <span class="hb-nm">${esc(data.callsign ? data.name || '' : data.grade || '')}</span>
        <span class="hb-st ${esc(data.tone || 'off')}"><i></i>${esc(word)}</span>
        ${onDuty ? `<span class="hb-sh">${icon('clock')}<b data-shift>${shiftText()}</b></span>` : ''}`;
    }
    const rings = svgEl.querySelector('.rd-hubrings');
    if (rings) rings.outerHTML = hubRings();
  }
  function shiftText() {
    const sh = Math.max(0, Number(data.shift) || 0) + (shiftAt ? (performance.now() - shiftAt) / 1000 : 0);
    const h = Math.floor(sh / 3600), m = Math.floor((sh % 3600) / 60);
    return `${h}:${String(m).padStart(2, '0')}`;
  }

  function highlight(i) {
    sel = i;
    const { list } = ring();
    const n = list.length, s = 360 / Math.max(1, n);
    el.querySelectorAll('.rd-node,.rd-lab').forEach(p => p.classList.toggle('sel', +p.dataset.i === i));
    const selArc = svgEl.querySelector('.rd-sel'), beam = svgEl.querySelector('.rd-beam');
    const it = list[i];
    if (it) {
      const a = angleOf(i, n);
      const span = Math.min(s / 2 - 6, 22);
      selArc.setAttribute('d', arc(R_ORB, a - span, a + span));
      selArc.setAttribute('class', `rd-sel ${it.danger ? 'danger' : ''} ${it.disabled ? 'off' : ''}`);
      selArc.setAttribute('opacity', '1');
      const [x0, y0] = pt(R_HUB + 4, a), [x1, y1] = pt(R_ORB - R_NODE - 6, a);
      beam.setAttribute('x1', x0); beam.setAttribute('y1', y0); beam.setAttribute('x2', x1); beam.setAttribute('y2', y1);
      beam.setAttribute('class', `rd-beam ${it.danger ? 'danger' : ''} ${it.disabled ? 'off' : ''}`);
      beam.setAttribute('opacity', '1');
      const desc = it.desc || (it.items ? K.fmt(tr('r_options', '%d options'), it.items.length) : tr('r_click', 'Click to use'));
      infoEl.className = `rd-info on ${it.danger ? 'danger' : ''} ${it.disabled ? 'off' : ''} ${it.active ? 'act' : ''}`;
      infoEl.innerHTML = `<span class="ii">${icon(it.disabled ? 'lock' : it.icon || 'more')}</span><div><b>${esc(it.label)}${it.active ? `<em>${esc(tr('r_on', 'ON'))}</em>` : ''}</b><p>${esc(desc)}</p></div><span class="ik"><kbd>${i + 1}</kbd></span>`;
    } else {
      selArc.setAttribute('opacity', '0');
      beam.setAttribute('opacity', '0');
      infoEl.className = 'rd-info';
      infoEl.innerHTML = `<span class="ii">${icon('mouse')}</span><div><b>${esc(path.length ? tr('r_hint_sub', 'Right click or the centre to go back') : tr('r_hint', 'Point at an option'))}</b></div>`;
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
    if (it.disabled) return shake();
    NZA.audio.click(880);
    const node = el.querySelector(`.rd-node[data-i="${i}"]`);
    if (node) { node.classList.remove('hit'); void node.offsetWidth; node.classList.add('hit'); }
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
    if (Math.hypot(dx, dy) < R_HUB * z) { if (sel !== -1) highlight(-1); return; }
    const n = ring().list.length, s = 360 / Math.max(1, n);
    if (!n) return;
    const a = Math.atan2(dy, dx) * 180 / Math.PI;
    const i = Math.round((((a + 90) % 360) + 360) % 360 / s) % n;
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
            <svg viewBox="-${HALF} -${HALF} ${HALF * 2} ${HALF * 2}"></svg>
            <div class="rd-nodes"></div>
            <div class="rd-hub"></div>
          </div>
          <div class="rd-info"></div>
          <div class="rd-foot"></div>
        </div>`;
      wheel = root.querySelector('.rd-wheel');
      svgEl = root.querySelector('svg');
      nodesEl = root.querySelector('.rd-nodes');
      hubEl = root.querySelector('.rd-hub');
      infoEl = root.querySelector('.rd-info');
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
      shiftAt = performance.now();
      footEl.innerHTML = `<span><kbd>LMB</kbd>${esc(tr('r_f_select', 'Use'))}</span><span><kbd>RMB</kbd>${esc(tr('r_back', 'Back'))}</span>` +
        `<span><kbd>1-9</kbd>${esc(tr('r_f_quick', 'Quick pick'))}</span><span><kbd>${esc(key)}</kbd>${esc(tr('r_f_close', 'Close'))}</span><span class="nz-sig"><span class="nz-mark xs"></span>NAYZEEE</span>`;
      wheel.classList.remove('in'); void wheel.offsetWidth; wheel.classList.add('in');
      render();
      clearInterval(shiftT);
      shiftT = setInterval(() => { const s = hubEl.querySelector('[data-shift]'); if (s) s.textContent = shiftText(); }, 15000);
    },
    close() { path = []; sel = -1; clearInterval(shiftT); },
    msg: {
      header(h) { Object.assign(data, h || {}); shiftAt = performance.now(); header(); },
    },
    keys: {
      Escape() { NZA.close('radial'); },
      Backspace() { back(); },
      Enter() { if (sel >= 0) pick(sel); },
      ArrowRight() { const n = ring().list.length; if (n) highlight((sel + 1 + n) % n); },
      ArrowLeft() { const n = ring().list.length; if (n) highlight(((sel < 0 ? 0 : sel) - 1 + n) % n); },
      1() { quick(1); }, 2() { quick(2); }, 3() { quick(3); }, 4() { quick(4); }, 5() { quick(5); },
      6() { quick(6); }, 7() { quick(7); }, 8() { quick(8); }, 9() { quick(9); },
    },
    preview() {
      const find = (list, id) => { for (const it of list || []) { if (it.id === id) return it; const f = find(it.items, id); if (f) return f; } return null; };
      NZA.mock('radial:select', d => {
        if (d.id === 'd_npc') { const it = find(data.items, 'd_npc'); it.active = !it.active; return { items: data.items }; }
        NZA.toast({ title: 'Job menu', message: `Selected ${d.id}`, type: 'info' });
        return { close: true };
      });
      NZA.demo('radial', {
        name: 'Dana Whitfield', callsign: 'Medic 12', grade: 'Paramedic', status: 'ENR', statusLabel: 'Rolling', tone: 'amber', onDuty: true, shift: 8040, call: 'C-0416', key: 'F6',
        items: [
          { id: 'status', label: 'Status', icon: 'radio', desc: 'Available · availability and your shift', items: [
            { id: 'd_status', label: 'Go unavailable', icon: 'pause', disabled: true, desc: 'Stand down from your call first' },
            { id: 'duty', label: 'End shift', icon: 'logout', danger: true, desc: 'Clock out and stop getting paged' },
          ] },
          { id: 'dispatch', label: 'Calls', icon: 'broadcast', desc: 'Take or drop calls, open the board, street calls', items: [
            { id: 'd_respond', label: 'Take next call', icon: 'siren', desc: 'Take the most urgent open call' },
            { id: 'd_clear', label: 'Stand down', icon: 'x', danger: true, desc: 'Leave C-0416 and become available' },
            { id: 'checkin_next', label: 'Call next patient', icon: 'bell', desc: 'Next number to an open bed' },
            { id: 'd_board', label: 'Board', icon: 'grid', desc: 'Ops board on the live map with your call' },
            { id: 'd_npc', label: 'Street calls', icon: 'call', active: true, desc: 'Locals can page you. Click to stop.' },
            { id: 'd_phone', label: 'Link phone', icon: 'phone', desc: 'Get every call on your phone too.' },
          ] },
          { id: 'patient', label: 'Care', icon: 'heart', desc: 'Treat the closest patient or work the gurney', items: [
            { id: 'patient:assess', label: 'Assess', icon: 'stetho', desc: 'Ask to walk · Examine · Pulse …', items: [
              { id: 'assess_walk', label: 'Ask to walk', icon: 'walk' }, { id: 'assess_exam', label: 'Examine', icon: 'stetho' },
              { id: 'assess_pulse', label: 'Pulse', icon: 'pulse' }, { id: 'assess_breath', label: 'Breathing', icon: 'lungs' },
            ] },
            { id: 'patient:treat', label: 'Resus & treat', icon: 'medkit', desc: 'Stop the bleed · Tourniquet · Meds …', items: [
              { id: 'fa_stopbleed', label: 'Stop the bleed', icon: 'drop' }, { id: 'fa_tourniquet', label: 'Tourniquet', icon: 'bandage' },
              { id: 'fa_meds', label: 'Meds', icon: 'pill' }, { id: 'field_iv', label: 'IV line', icon: 'iv' },
            ] },
            { id: 'patient:move', label: 'Move', icon: 'walk', desc: 'Carry · Gurney', items: [
              { id: 'tr_carry', label: 'Carry', icon: 'hand' }, { id: 'stretcher', label: 'Gurney', icon: 'bed', items: [{ id: 'tr_str_take', label: 'Take gurney', icon: 'bed' }] },
            ] },
            { id: 'pharmacy_bill', label: 'Send bill', icon: 'receipt' },
          ] },
          { id: 'd_pager', label: 'Pager', icon: 'pager' },
        ],
      });
      path = ['dispatch']; render(); highlight(4);
    },
  });

  function quick(n) {
    const { list } = ring();
    if (list[n - 1]) pick(n - 1);
  }
})();
