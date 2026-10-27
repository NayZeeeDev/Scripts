/* ═══════════════════════════════════════════════════════════
   NAYZEEE RADIO · roster (never takes focus)                          apps/roster/app.js
   Who is on your TX channel (client/modules/roster.lua).

   Lua → NUI
     open   { x?, y? }   0..1 screen fractions of the card's top-left (from roster:moved);
                         none = docked to the right edge, top-right quarter
     data   { fkey, label, count?, access?, max?, members = [{ id, name, callsign, bars 0..4, talking, you }] }
     close
   NUI → Lua
     roster:moved { x, y }   after a drag (only possible while some other window gives the page
                             a cursor), the card's top-left as 0..1 fractions

   Rows: talkers float to the top (rows slide to their new place), at most 6 rows then
   "+N more". The server formats names with Config.Roster.nameFormat; a callsign already
   in the name is not shown twice.
   ═══════════════════════════════════════════════════════════ */
(() => {
  const NZR = window.NZR;
  const { esc, t } = NZR;
  const MAX_ROWS = 6;
  const DOCK = { right: 22, top: 104, width: 268 };
  const num = (v, d = NaN) => { const n = Number(v); return Number.isFinite(n) ? n : d; };
  // static words: re-read from the locale when Lua pushes the config (it arrives after init)
  const L = (k, f) => `<span data-t="${k}" data-f="${esc(f)}">${esc(t(k, f))}</span>`;
  const relabel = el => el.querySelectorAll('[data-t]').forEach(e => { e.textContent = t(e.dataset.t, e.dataset.f); });

  // signal dial: four arcs over 270° (lit from the lower left, clockwise)
  const ARCS = [0, 1, 2, 3].map(i => {
    const a0 = (135 + i * 67.5 + 4.5) * Math.PI / 180, a1 = a0 + 58.5 * Math.PI / 180;
    const p = a => `${(8 + 6 * Math.cos(a)).toFixed(2)} ${(8 + 6 * Math.sin(a)).toFixed(2)}`;
    return `M${p(a0)}A6 6 0 0 1 ${p(a1)}`;
  });
  const SIG = `<svg viewBox="0 0 16 16">${ARCS.map(d => `<path d="${d}"/>`).join('')}<circle cx="8" cy="8" r="1.7"/></svg>`;

  let app = null, sec = null, wrap = null, card = null, rowsEl = null, labEl = null, moreEl = null;
  let freqOdo = null, cntOdo = null;
  const rowEls = new Map();      // id → row element (live rows only)
  let pos = null;                // null = docked, else { fx, fy } screen fractions
  let drag = null;

  const vp = () => { const z = NZR.zoom || 1; return { W: window.innerWidth / z, H: window.innerHeight / z }; };

  /* ─────────────── position ─────────────── */
  function place() {
    // the alert stack steps aside while this card sits docked at the right edge
    document.documentElement.classList.toggle('nzr-rs-dock', !pos && NZR.isOpen('roster'));
    if (!pos) { wrap.classList.remove('free'); wrap.style.left = ''; wrap.style.top = ''; return; }
    const { W, H } = vp();
    const h = card.offsetHeight || 220;
    const x = Math.max(6, Math.min(W - DOCK.width - 6, pos.fx * W));
    const y = Math.max(6, Math.min(H - Math.min(h, 120) - 6, pos.fy * H));
    wrap.classList.add('free');
    wrap.style.left = `${Math.round(x)}px`;
    wrap.style.top = `${Math.round(y)}px`;
  }
  function current() {
    const { W } = vp();
    if (!pos) return { x: W - DOCK.right - DOCK.width, y: DOCK.top };
    return { x: parseFloat(wrap.style.left) || 0, y: parseFloat(wrap.style.top) || 0 };
  }

  function dragStart(e) {
    if (e.button !== undefined && e.button !== 0) return;
    const c = current();
    drag = { sx: e.clientX, sy: e.clientY, x: c.x, y: c.y, moved: false };
    e.preventDefault();
  }
  function dragMove(e) {
    if (!drag) return;
    const z = NZR.zoom || 1;
    const dx = (e.clientX - drag.sx) / z, dy = (e.clientY - drag.sy) / z;
    if (!drag.moved && Math.abs(dx) + Math.abs(dy) < 3) return;
    drag.moved = true;
    wrap.classList.add('drag');
    const { W, H } = vp();
    pos = { fx: (drag.x + dx) / W, fy: (drag.y + dy) / H };
    place();
  }
  function dragEnd() {
    if (!drag) return;
    const moved = drag.moved;
    drag = null;
    wrap.classList.remove('drag');
    if (!moved || !pos) return;
    const { W, H } = vp();
    const c = current();
    pos = { fx: c.x / W, fy: c.y / H };
    NZR.post('roster:moved', { x: +pos.fx.toFixed(4), y: +pos.fy.toFixed(4) });
  }

  /* ─────────────── rows ─────────────── */
  function displayName(m) {
    let name = String(m.name ?? '').trim();
    const cs = String(m.callsign ?? '').trim();
    if (cs && name.length > cs.length) {
      const lo = name.toLowerCase(), c = cs.toLowerCase();
      if (lo.endsWith(` ${c}`)) name = name.slice(0, -cs.length).trim();
      else if (lo.startsWith(`${c} `)) name = name.slice(cs.length).trim();
      name = name.replace(/[\s·|-]+$/, '').replace(/^[\s·|-]+/, '');
    }
    return name || `#${m.id ?? '?'}`;
  }
  function makeRow(id) {
    const el = NZR.el('div', 'rs-r', `<span class="rs-sig">${SIG}</span><span class="rs-nm"><b></b></span><span class="rs-cs"></span><span class="rs-tk"><i></i><i></i><b></b></span>`);
    el.dataset.id = id;
    el.addEventListener('animationend', ev => { if (ev.animationName === 'rs-row-in') el.classList.remove('in'); });
    return el;
  }
  function fill(el, m) {
    const nm = el.querySelector('.rs-nm');
    const name = displayName(m);
    const b = nm.querySelector('b');
    if (b.textContent !== name) b.textContent = name;
    const you = m.you === true;
    let em = nm.querySelector('em');
    if (you && !em) { em = NZR.el('em', '', esc(t('ui.rs_you', 'you'))); nm.appendChild(em); }
    if (!you && em) em.remove();
    const cs = el.querySelector('.rs-cs');
    const csv = m.callsign ? String(m.callsign) : '';
    if (cs.textContent !== csv) cs.textContent = csv;
    const bars = Math.max(0, Math.min(4, Math.round(num(m.bars, 0))));
    const sig = el.querySelector('.rs-sig');
    sig.className = `rs-sig t${bars <= 1 ? bars : bars === 2 ? 2 : 4}`;
    sig.querySelectorAll('path').forEach((p, i) => p.classList.toggle('on', i < bars));
    el.classList.toggle('talk', m.talking === true);
    el.classList.toggle('me', you);
  }
  function updateRows(list) {
    // FLIP: remember where the surviving rows were
    const first = new Map();
    rowEls.forEach((el, id) => first.set(id, el.offsetTop));
    const keep = new Set(list.map(m => String(m.id ?? m.name)));
    rowEls.forEach((el, id) => {
      if (keep.has(id)) return;
      rowEls.delete(id);
      el.classList.remove('in', 'talk');
      el.classList.add('out');
      setTimeout(() => el.remove(), 280);
    });
    const empty = rowsEl.querySelector('.rs-empty');
    if (empty && list.length) empty.remove();
    let fresh = 0;
    list.forEach(m => {
      const id = String(m.id ?? m.name);
      let el = rowEls.get(id);
      if (!el) { el = makeRow(id); el.classList.add('in'); el.style.setProperty('--i', fresh++); rowEls.set(id, el); }
      fill(el, m);
      rowsEl.appendChild(el);
    });
    rowEls.forEach((el, id) => {
      if (!first.has(id) || el.classList.contains('in')) return;
      const dy = first.get(id) - el.offsetTop;
      if (!dy) return;
      el.style.transition = 'none';
      el.style.transform = `translateY(${dy}px)`;
      void el.offsetWidth;
      el.style.transition = '';
      el.style.transform = '';
    });
  }
  function emptyRow(text) {
    rowEls.forEach(el => el.remove());
    rowEls.clear();
    rowsEl.innerHTML = `<div class="rs-empty">${NZR.icon('antenna')}<span>${esc(text)}</span></div>`;
  }

  // a value whose digit layout changed is first laid out as zeros so its digits still roll
  function roll(odo, v) {
    const shape = v.replace(/\d/g, 'd');
    if (odo.shape !== shape) { odo.set(v.replace(/\d/g, '0')); void odo.el.offsetWidth; odo.shape = shape; }
    odo.set(v);
  }

  function data(d = {}) {
    d = d || {};
    const f = NZR.fmt.freq(d.fkey ?? d.freq);
    roll(freqOdo, f || '000.00');   // no channel: unlit zeros
    wrap.classList.toggle('nofreq', !f);
    const access = d.access === 'code' ? NZR.icon('lock') : d.access === 'job' ? NZR.icon('badge') : '';
    labEl.innerHTML = d.label ? `${access}${esc(d.label)}` : '';
    const members = (Array.isArray(d.members) ? d.members : []).filter(m => m && typeof m === 'object');
    const count = Math.max(members.length, Math.round(num(d.count, members.length)));
    roll(cntOdo, String(count));
    const order = members.map((m, i) => ({ m, i }))
      .sort((a, b) => ((b.m.talking === true) - (a.m.talking === true)) || (a.i - b.i))
      .map(x => x.m);
    // Config.Roster.maxRows (sent as max) can lower the row count, the card never shows more than MAX_ROWS
    const cap = Math.max(1, Math.min(MAX_ROWS, Math.round(num(d.max, MAX_ROWS))));
    const shown = order.slice(0, cap);
    const more = count - shown.length;
    moreEl.textContent = more > 0 ? `+${more} ${t('ui.rs_more', 'more')}` : '';
    wrap.classList.toggle('live', shown.some(m => m.talking === true));
    if (!f) emptyRow(t('ui.rs_nochan', 'No channel on your TX slot'));
    else if (!shown.length) emptyRow(t('ui.rs_nobody', 'Nobody tuned in yet'));
    else updateRows(shown);
  }

  app = NZR.app('roster', {
    escClose: false,
    init(el) {
      NZR.onCore('config', () => relabel(el));
      sec = el;
      el.innerHTML = `<div class="rs"><div class="rs-card nzr-hud solid nzr-brk">
          <div class="rs-h"><span class="rs-ant">${NZR.icon('antenna')}</span><div class="rs-f"><span class="rs-fo"></span><small>${L('ui.mhz', 'MHz')}</small></div>
            <span class="rs-n"><span class="rs-co"></span>${L('ui.rs_tuned', 'tuned')}</span></div>
          <div class="rs-sub"><span class="rs-lab nzr-chip"></span></div>
          <div class="rs-rows"></div>
          <div class="rs-ft"><span class="rs-more"></span><span class="rs-grip">${NZR.icon('swap')}${L('ui.rs_drag', 'drag to move')}</span><span class="nz-sig"><span class="nz-mark xs"></span>NAYZEEE</span></div>
        </div></div>`;
      wrap = el.querySelector('.rs');
      card = el.querySelector('.rs-card');
      rowsEl = el.querySelector('.rs-rows');
      labEl = el.querySelector('.rs-lab');
      moreEl = el.querySelector('.rs-more');
      freqOdo = NZR.ui.Odometer(el.querySelector('.rs-fo'), { value: '000.00', blink: false });
      cntOdo = NZR.ui.Odometer(el.querySelector('.rs-co'), { value: '0', blink: false });
      wrap.addEventListener('pointerdown', dragStart);
      window.addEventListener('pointermove', dragMove);
      window.addEventListener('pointerup', dragEnd);
      window.addEventListener('pointercancel', dragEnd);
      window.addEventListener('resize', () => { if (pos) place(); });
    },
    open(d) {
      const x = num(d && d.x), y = num(d && d.y);
      pos = Number.isFinite(x) && Number.isFinite(y) && x >= 0 && x <= 1 && y >= 0 && y <= 1 ? { fx: x, fy: y } : null;
      place();
      // replay the slide-in each time the card comes back
      card.style.animation = 'none'; void card.offsetWidth; card.style.animation = '';
      if (Array.isArray(d && d.members)) data(d);
    },
    close() { drag = null; wrap.classList.remove('drag'); document.documentElement.classList.remove('nzr-rs-dock'); },
    msg: { data },
    preview() {
      const crew = [
        { id: 12, name: 'Tex Holloway', callsign: '1G', bars: 4, you: true },
        { id: 7, name: 'Maya Reyes 2A14', callsign: '2A14', bars: 3, talking: true },
        { id: 31, name: 'Dario Kostas', callsign: '1L20', bars: 2 },
        { id: 44, name: 'June Whitfield', callsign: 'K9', bars: 4 },
        { id: 52, name: 'Owen Price', callsign: null, bars: 1 },
        { id: 60, name: 'Sam Brooks', callsign: '3D', bars: 3 },
        { id: 61, name: 'Lena Ortiz', callsign: '4H', bars: 0 },
      ];
      NZR.mock('roster:moved', d => ({ ok: true, d }));
      NZR.demo('roster', {});
      app.msg.data({ fkey: '000.00', label: '', members: [] });
      setTimeout(() => app.msg.data({ fkey: '155.50', label: 'Patrol North', access: 'job', count: 9, members: crew }), 350);
      let n = 0;
      setInterval(() => {
        n++;
        const talker = [1, 3, null, 0, 5][n % 5];
        const list = crew.map((m, i) => Object.assign({}, m, { talking: i === talker, bars: Math.max(0, Math.min(4, m.bars + (i === 2 ? (n % 2 ? 1 : -1) : 0))) }));
        if (n % 4 === 2) list.splice(4, 1);
        app.msg.data({ fkey: '155.50', label: 'Patrol North', access: 'job', count: n % 4 === 2 ? 8 : 9, members: list });
      }, 2200);
    },
  });
})();
