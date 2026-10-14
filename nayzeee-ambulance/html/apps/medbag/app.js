/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · app 'medbag'
   Medical bag storage, NAYZEEE layout: your pockets dock on the LEFT edge with the
   quantity dial under it, the bag dock on the RIGHT edge (colour-coded bag identity,
   load dial + instrument list, slot grid, restock / unpack) with the bag log under it.
   The centre stays clear: the bag on the floor stays visible and moved items fly across.

   Lua → JS   open { locale, bag, me, kit, colours }   sync { bag, moved?, by? }   me { me }
   JS → Lua   medbag:move   { dir: 'in'|'out'|'bag', from, to?, count: n|'all', name }
              medbag:action { action: 'sort'|'lock'|'kit'|'empty'|'style', data }
              → { ok, bag, me, moved?, movedList?, msg? }      medbag:close (router)

   bag = { id, name, colour, hex, owner, mine, locked, canLock, canStyle, slots, weight, maxWeight,
           items: [{ slot, name, label, image, count, weight (g/unit), desc, cat, meta: [{ k?, v }] }] }
   me  = { items: [{ slot, name, label, image, count, weight, desc, cat, meta, allowed }], weight, maxWeight }

   Mouse: click = move the dial quantity · hold = pour one by one (release to move) ·
          Shift + click = whole stack · right click = one · drag = onto a bag slot / the pockets.
   Keys:  1 2 3 4 = quantity 1 / 5 / 10 / stack · + − = step · F = filter · Esc = close.
   ═══════════════════════════════════════════════════════════ */
(() => {
  const esc = NZA.esc;
  const icon = n => NZA.icon(n);
  const clamp = (n, a, b) => Math.max(a, Math.min(b, n));

  /* ─────────────── locale ─────────────── */
  let loc = {};
  const t = (key, fb, ...args) => {
    let s = loc[key] !== undefined ? loc[key] : NZA.t(`medbag.${key}`, fb !== undefined ? fb : key);
    if (s === `medbag.${key}`) s = fb !== undefined ? fb : key;
    let i = 0;
    return String(s).replace(/%(?:\.\d)?[sdf]/g, m => {
      const v = args[i++];
      if (v === undefined) return m;
      const dec = /%\.(\d)f/.exec(m);
      return dec ? Number(v).toFixed(+dec[1]) : String(v);
    });
  };
  const CAT = { first_aid: 'First aid', wound_care: 'Wound care', medication: 'Medication', fluids: 'Fluids & IV', orthopedic: 'Orthopedic', airway: 'Airway', surgery: 'Surgery', equipment: 'Equipment', documents: 'Documents', other: 'Other' };
  const catLabel = c => t(`cat_${c || 'other'}`, CAT[c] || CAT.other);
  const kg = g => (Math.max(0, Number(g) || 0) / 1000).toFixed(1);
  const grams = g => (g >= 1000 ? `${kg(g)} ${t('ui_kg', 'kg')}` : `${Math.round(g)} g`);
  const keyLabel = k => { const s = String(k).replace(/[_-]+/g, ' ').trim(); return s.length <= 3 ? s.toUpperCase() : s.charAt(0).toUpperCase() + s.slice(1); };
  const imgOf = it => esc(it.image || `img/items/${it.name}.png`);
  const imgFallback = "this.onerror=null;this.src='img/items/nza_unknown.png'";
  const clock = () => { const d = new Date(); return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`; };
  const cssEsc = s => (window.CSS && CSS.escape ? CSS.escape(s) : String(s).replace(/["\\]/g, '\\$&'));

  // Lua sends empty tables as {} → real arrays
  const arr = v => (Array.isArray(v) ? v : (v && typeof v === 'object' ? Object.values(v) : []));
  const normItems = list => arr(list).map(it => Object.assign({}, it, { meta: it && it.meta ? arr(it.meta) : null }));
  const normBag = b => (b ? Object.assign({}, b, { items: normItems(b.items) }) : null);
  const normMe = m => (m ? Object.assign({}, m, { items: normItems(m.items) }) : null);

  /* ─────────────── state ─────────────── */
  const PRESETS = [1, 5, 10, 'stack'];
  const S = {
    on: false, bag: null, me: null, kit: false, colours: [],
    qty: 1, stack: false, filter: '', log: [],
    queue: Promise.resolve(), busy: 0,
    press: null, drag: null, pour: null, tipFor: null, styling: false, pickColour: null,
  };
  let A = null, R = {}, ghost = null, odo = null;

  /* ─────────────── 240° dial geometry (same language as the procedure HUD) ─────────────── */
  const A0 = 150, SW = 240;
  const pt = (cx, cy, r, f) => { const a = (A0 + SW * clamp(f, 0, 1)) * Math.PI / 180; return [cx + r * Math.cos(a), cy + r * Math.sin(a)]; };
  const arcD = (cx, cy, r, f0, f1) => {
    const [x0, y0] = pt(cx, cy, r, f0), [x1, y1] = pt(cx, cy, r, f1);
    return `M${x0.toFixed(2)} ${y0.toFixed(2)}A${r} ${r} 0 ${(f1 - f0) * SW > 180 ? 1 : 0} 1 ${x1.toFixed(2)} ${y1.toFixed(2)}`;
  };
  // quantity ↔ dial position (1 → 0, 5 → ⅓, 10 → ⅔, stack → 1)
  const qtyPos = () => {
    if (S.stack) return 1;
    const q = S.qty;
    if (q <= 1) return 0;
    if (q <= 5) return ((q - 1) / 4) / 3;
    if (q <= 10) return 1 / 3 + ((q - 5) / 5) / 3;
    return 2 / 3 + Math.min(1, (q - 10) / 40) / 3 * 0.92;
  };
  const posQty = f => {
    if (f >= 0.985) return 'stack';
    if (f <= 1 / 3) return Math.round(1 + f * 3 * 4);
    if (f <= 2 / 3) return Math.round(5 + (f - 1 / 3) * 3 * 5);
    return Math.round(10 + ((f - 2 / 3) * 3 / 0.92) * 40);
  };

  /* ─────────────── markup ─────────────── */
  function build(el) {
    el.innerHTML = `
      <aside class="mb-left">
        <section class="mb-card mb-pk nza-hud solid">
          <header class="mb-hd">
            <span class="mb-ring"><svg class="rg" viewBox="0 0 40 40"><circle class="bg" cx="20" cy="20" r="17"/><circle class="fg" cx="20" cy="20" r="17"/></svg>${icon('user')}</span>
            <div class="mb-ht"><b class="mb-pk-t"></b><span class="mb-mono mb-pk-w"></span></div>
            <label class="mb-filter">${icon('search')}<input type="text" maxlength="24" spellcheck="false"></label>
          </header>
          <div class="mb-list" data-side="me"></div>
          <div class="mb-none"></div>
        </section>
        <section class="mb-card mb-qty nza-hud solid">
          <div class="mb-dial">
            <svg viewBox="0 0 140 124"></svg>
            <div class="mb-dv"><span class="mb-odo"></span><span class="mb-stk"></span></div>
            <div class="mb-dc"></div>
            <div class="mb-pre"></div>
            <button class="mb-db" data-step="-1">${icon('minus')}</button>
            <button class="mb-db" data-step="1">${icon('plus')}</button>
          </div>
          <ul class="mb-gest"></ul>
        </section>
      </aside>

      <aside class="mb-right">
        <section class="mb-card mb-bag nza-hud solid">
          <header class="mb-hd">
            <span class="mb-swatch">${icon('medkit')}</span>
            <div class="mb-ht"><b class="mb-bag-t"></b><span class="mb-mono mb-bag-s"></span></div>
            <div class="mb-tools">
              <button class="mb-ib" data-act="style">${icon('palette')}</button>
              <button class="mb-ib" data-act="sort">${icon('sortd')}</button>
              <button class="mb-ib" data-act="lock">${icon('unlock')}</button>
              <button class="pill-close" data-act="close"></button>
            </div>
          </header>
          <div class="mb-style"></div>
          <div class="mb-read">
            <div class="mb-load"><svg viewBox="0 0 120 104"></svg><div class="mb-lv"><b></b><span></span></div></div>
            <ul class="mb-inst"></ul>
          </div>
          <div class="mb-gwrap"><div class="mb-grid" data-side="bag"></div><div class="mb-none mb-bnone"></div></div>
          <footer class="mb-foot">
            <button class="mb-act teal" data-act="kit">${icon('arrow-down')}<span></span></button>
            <button class="mb-act" data-act="empty">${icon('arrow-up')}<span></span></button>
          </footer>
        </section>
        <section class="mb-card mb-log nza-hud solid">
          <header class="mb-lh"><b></b><span></span></header>
          <ol class="mb-logl"></ol>
        </section>
      </aside>
      <div class="mb-tip nza-hud solid"></div>
      <div class="mb-fx"></div>`;

    const q = s => el.querySelector(s);
    R = {
      left: q('.mb-left'), right: q('.mb-right'), pk: q('.mb-pk'), bagCard: q('.mb-bag'),
      pkT: q('.mb-pk-t'), pkW: q('.mb-pk-w'), pkRing: q('.mb-pk .mb-ring > svg.rg .fg'), filter: q('.mb-filter input'),
      list: q('.mb-list'), pnone: q('.mb-pk .mb-none'),
      dialSvg: q('.mb-dial > svg'), odoHost: q('.mb-odo'), stk: q('.mb-stk'), dc: q('.mb-dc'), pre: q('.mb-pre'), gest: q('.mb-gest'),
      bagT: q('.mb-bag-t'), bagS: q('.mb-bag-s'), style: q('.mb-style'),
      loadSvg: q('.mb-load > svg'), loadV: q('.mb-lv b'), loadU: q('.mb-lv span'), inst: q('.mb-inst'),
      gwrap: q('.mb-gwrap'), grid: q('.mb-grid'), bnone: q('.mb-bnone'),
      kit: q('[data-act="kit"]'), emp: q('[data-act="empty"]'), sty: q('[data-act="style"]'), sort: q('[data-act="sort"]'),
      lock: q('[data-act="lock"]'), close: q('[data-act="close"]'),
      logH: q('.mb-lh b'), logS: q('.mb-lh span'), logL: q('.mb-logl'),
      tip: q('.mb-tip'), fx: q('.mb-fx'),
    };
    odo = NZA.ui.FlipClock(R.odoHost, { value: '1', small: true });

    el.addEventListener('click', e => {
      const b = e.target.closest('[data-act]');
      if (b) { e.preventDefault(); action(b.dataset.act); return; }
      const st = e.target.closest('[data-step]');
      if (st) { step(Number(st.dataset.step)); return; }
      const p = e.target.closest('[data-preset]');
      if (p) { setQty(p.dataset.preset === 'stack' ? 'stack' : Number(p.dataset.preset)); }
    });
    R.dialSvg.addEventListener('mousedown', e => {
      if (e.button !== 0) return;
      const r = R.dialSvg.getBoundingClientRect();
      const x = (e.clientX - r.left) / r.width * 140, y = (e.clientY - r.top) / r.height * 124;
      let a = Math.atan2(y - 66, x - 70) * 180 / Math.PI;
      if (a < 0) a += 360;
      let f = (a - A0) / SW;
      if (f < 0) f += 360 / SW;
      if (f > 1.15) return;
      setQty(posQty(clamp(f, 0, 1)));
    });
    el.querySelector('.mb-dial').addEventListener('wheel', e => { e.preventDefault(); step(e.deltaY < 0 ? 1 : -1); }, { passive: false });
    R.filter.addEventListener('input', () => { S.filter = R.filter.value.trim().toLowerCase(); renderMe(); });

    el.addEventListener('mousedown', onDown);
    el.addEventListener('contextmenu', e => e.preventDefault());
    el.addEventListener('mouseover', onOver);
    el.addEventListener('mouseout', e => {
      const from = e.target.closest && e.target.closest('[data-item]');
      const to = e.relatedTarget && e.relatedTarget.closest && e.relatedTarget.closest('[data-item]');
      if (from && from !== to) hideTip();
    });
    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp);
  }

  function texts() {
    R.pkT.textContent = t('ui_pockets', 'Your pockets');
    R.filter.placeholder = t('ui_filter', 'Filter');
    R.close.textContent = t('ui_close', 'Close');
    R.kit.querySelector('span').textContent = t('ui_restock', 'Restock');
    R.kit.title = t('ui_restock_d', 'Top the bag up from your pockets');
    R.emp.querySelector('span').textContent = t('ui_unpack', 'Unpack all');
    R.sty.title = t('ui_style', 'Name & colour');
    R.sort.title = t('ui_sort', 'Sort by type');
    R.dc.innerHTML = `<b>${esc(t('ui_qty', 'Quantity'))}</b>${esc(t('ui_qty_sub', 'per click'))}`;
    R.logH.textContent = t('ui_log', 'Bag log');
    R.logS.textContent = t('ui_log_sub', 'Latest moves');
    R.gest.innerHTML = [
      ['Click', t('ui_g_click_d', 'move the quantity')],
      [t('ui_g_hold', 'Hold'), t('ui_g_hold_d', 'pour one by one')],
      ['Shift', t('ui_g_shift_d', 'the whole stack')],
      [t('ui_g_right', 'RMB'), t('ui_g_right_d', 'just one')],
      [t('ui_g_drag', 'Drag'), t('ui_g_drag_d', 'onto a slot')],
    ].map(([k, d]) => `<li><kbd>${esc(k)}</kbd><span>${esc(d)}</span></li>`).join('');
  }

  /* ─────────────── rendering ─────────────── */
  function slotHTML(it, slot) {
    if (!it) return `<div class="mb-slot empty" data-side="bag" data-slot="${slot}"></div>`;
    return `<div class="mb-slot" data-item data-side="bag" data-slot="${it.slot}" data-name="${esc(it.name)}">
      <b class="q">${esc(it.count)}</b>
      <img src="${imgOf(it)}" alt="" draggable="false" onerror="${imgFallback}">
      <span class="nm">${esc(it.label)}</span>
    </div>`;
  }

  function rowHTML(it) {
    const dis = it.allowed === false;
    return `<div class="mb-row${dis ? ' dis' : ''}" data-item data-side="me" data-slot="${it.slot}" data-name="${esc(it.name)}">
      <span class="th"><img src="${imgOf(it)}" alt="" draggable="false" onerror="${imgFallback}"></span>
      <span class="tx"><b>${esc(it.label)}</b><small>${dis ? esc(t('ui_stays', 'Stays in your pockets')) : `${esc(catLabel(it.cat))} · ${esc(grams(Number(it.weight) || 0))}`}</small></span>
      <span class="q">×${esc(it.count)}</span>
      <span class="go">${icon(dis ? 'ban' : 'chev-r')}</span>
    </div>`;
  }

  function loadTone(p) { return p >= 0.95 ? 'red' : p >= 0.8 ? 'amber' : ''; }

  function loadDial(p) {
    let ticks = '';
    for (let i = 0; i <= 10; i++) {
      const [a, b] = pt(60, 58, 52, i / 10), [c, d] = pt(60, 58, i % 5 ? 49 : 46, i / 10);
      ticks += `<line x1="${a.toFixed(1)}" y1="${b.toFixed(1)}" x2="${c.toFixed(1)}" y2="${d.toFixed(1)}"/>`;
    }
    const tone = loadTone(p);
    const fill = p > 0.002 ? `<path class="fill ${tone}" d="${arcD(60, 58, 40, 0, Math.max(p, 0.004))}"/>` : '';
    const zone = `<path class="zone" d="${arcD(60, 58, 40, 0.8, 1)}"/>`;
    return `<path class="trk" d="${arcD(60, 58, 40, 0, 1)}"/>${zone}${fill}<g class="ticks">${ticks}</g>`;
  }

  function renderBag() {
    const b = S.bag;
    if (!b) return;
    if (!S.styling) R.bagCard.style.setProperty('--bc', b.hex || '#08afa2');
    R.bagT.textContent = b.name || t('ui_bag_default', 'Medical bag');
    const who = b.mine ? t('ui_yours', 'Yours') : t('ui_owner', 'Owner %s', b.owner || '?');
    R.bagS.innerHTML = `${esc(b.id)} · ${esc(who)}${b.locked ? ` · <em>${icon('lock')}${esc(t('ui_locked', 'Locked'))}</em>` : ''}`;
    R.lock.style.display = b.canLock ? '' : 'none';
    R.lock.innerHTML = icon(b.locked ? 'lock' : 'unlock');
    R.lock.classList.toggle('on', !!b.locked);
    R.lock.title = b.locked ? t('ui_unlock', 'Unlock the bag') : t('ui_lock', 'Lock the bag');
    R.sty.style.display = b.canStyle && S.colours.length ? '' : 'none';

    const items = b.items || [];
    const max = b.maxWeight || 20000;
    const p = clamp(max > 0 ? (b.weight || 0) / max : 0, 0, 1);
    R.loadSvg.innerHTML = loadDial(p);
    R.loadV.textContent = `${Math.round(p * 100)}`;
    R.loadV.className = loadTone(p);
    R.loadU.textContent = '%';
    const n = Math.max(b.slots || 20, ...items.map(i => i.slot));
    const units = items.reduce((a, i) => a + (Number(i.count) || 0), 0);
    const sTone = items.length >= n ? 'red' : items.length >= n * 0.8 ? 'amber' : '';
    R.inst.innerHTML = [
      [t('ui_load', 'Load'), `${kg(b.weight || 0)}<i> / ${kg(max)} ${esc(t('ui_kg', 'kg'))}</i>`, loadTone(p) || 'teal'],
      [t('ui_slots_l', 'Slots'), `${items.length}<i> / ${n}</i>`, sTone],
      [t('ui_units', 'Units'), `${units}`, ''],
    ].map(([l, v, tone]) => `<li class="${tone}"><span>${esc(l)}</span><b>${v}</b></li>`).join('');

    const bySlot = {};
    items.forEach(it => { bySlot[it.slot] = it; });
    const cells = [];
    for (let s = 1; s <= n; s++) cells.push(slotHTML(bySlot[s], s));
    R.grid.innerHTML = cells.join('');
    R.bnone.textContent = items.length ? '' : t('ui_bag_empty', 'Nothing packed yet. Click an item in your pockets to put it in.');
    R.bnone.classList.toggle('on', !items.length);
    R.emp.disabled = !items.length;
    R.kit.style.display = S.kit ? '' : 'none';
  }

  function renderMe() {
    const m = S.me;
    if (!m) return;
    const all = m.items || [];
    const list = S.filter ? all.filter(it => `${it.label} ${it.name}`.toLowerCase().includes(S.filter)) : all;
    const sorted = [...list.filter(i => i.allowed !== false), ...list.filter(i => i.allowed === false)];
    R.list.innerHTML = sorted.map(rowHTML).join('');
    const none = !list.length;
    R.pnone.classList.toggle('on', none);
    R.pnone.textContent = none ? (S.filter ? t('ui_nomatch', 'No item matches') : t('ui_none', 'Your pockets are empty')) : '';
    const w = m.weight || 0, max = m.maxWeight;
    const C = 2 * Math.PI * 17;
    R.pkRing.style.strokeDasharray = `${C}`;
    if (max) {
      const p = clamp(w / max, 0, 1);
      R.pkW.innerHTML = `${kg(w)}<i> / ${kg(max)} ${esc(t('ui_kg', 'kg'))}</i>`;
      R.pkRing.style.strokeDashoffset = `${C * (1 - p)}`;
      R.pkRing.setAttribute('class', `fg ${loadTone(p)}`);
    } else {
      R.pkW.innerHTML = `${kg(w)}<i> ${esc(t('ui_kg', 'kg'))}</i>`;
      R.pkRing.style.strokeDashoffset = `${C}`;
    }
  }

  function renderQty() {
    const f = qtyPos();
    let ticks = '';
    for (let i = 0; i <= 24; i++) {
      const [a, b] = pt(70, 66, 60, i / 24), [c, d] = pt(70, 66, i % 8 ? 57 : 54, i / 24);
      ticks += `<line x1="${a.toFixed(1)}" y1="${b.toFixed(1)}" x2="${c.toFixed(1)}" y2="${d.toFixed(1)}"/>`;
    }
    const [kx, ky] = pt(70, 66, 47, f);
    R.dialSvg.innerHTML = `<path class="trk" d="${arcD(70, 66, 47, 0, 1)}"/>
      <path class="fill" d="${arcD(70, 66, 47, 0, Math.max(f, 0.004))}"/>
      <g class="ticks">${ticks}</g>
      <circle class="knob" cx="${kx.toFixed(1)}" cy="${ky.toFixed(1)}" r="5.5"/>`;
    R.pre.innerHTML = PRESETS.map((v, i) => {
      const [x, y] = pt(70, 66, 70, i / 3);
      const on = (v === 'stack' && S.stack) || (!S.stack && v === S.qty);
      return `<button data-preset="${v}" class="${on ? 'on' : ''}" style="left:${(x / 140 * 100).toFixed(2)}%;top:${(y / 124 * 100).toFixed(2)}%">${esc(v === 'stack' ? t('ui_stack', 'Stack') : v)}</button>`;
    }).join('');
    R.odoHost.style.display = S.stack ? 'none' : '';
    R.stk.style.display = S.stack ? '' : 'none';
    R.stk.textContent = t('ui_stack', 'Stack');
    if (!S.stack) odo.set(String(S.qty));
  }

  function renderStyle() {
    const b = S.bag;
    if (!b) return;
    const cur = S.pickColour || b.colour;
    R.style.innerHTML = `
      <label class="mb-in"><span>${esc(t('ui_name', 'Bag name'))}</span><input type="text" maxlength="20" spellcheck="false" placeholder="${esc(t('ui_name_ph', 'e.g. Trauma, Airway'))}" value="${esc(b.name || '')}"></label>
      <div class="mb-cols"><span>${esc(t('ui_colour', 'Colour'))}</span><div>${S.colours.map(c => `<button class="mb-sw ${c.id === cur ? 'on' : ''}" data-colour="${esc(c.id)}" title="${esc(c.label)}" style="--sw:${esc(c.hex)}"></button>`).join('')}</div></div>
      <div class="mb-sb"><button class="btn-line btn-sm" data-style="cancel">${esc(t('ui_cancel', 'Cancel'))}</button><button class="btn-teal btn-sm" data-style="save">${icon('check')}${esc(t('ui_save', 'Save'))}</button></div>`;
    R.style.querySelectorAll('[data-colour]').forEach(btn => btn.addEventListener('click', () => {
      S.pickColour = btn.dataset.colour;
      R.style.querySelectorAll('[data-colour]').forEach(x => x.classList.toggle('on', x === btn));
      const c = S.colours.find(x => x.id === btn.dataset.colour);
      if (c) R.bagCard.style.setProperty('--bc', c.hex);
    }));
    R.style.querySelector('[data-style="cancel"]').addEventListener('click', () => toggleStyle(false));
    R.style.querySelector('[data-style="save"]').addEventListener('click', () => {
      const name = R.style.querySelector('input').value;
      const colour = S.pickColour || b.colour;
      toggleStyle(false);
      run('style', { name, colour });
    });
  }
  function toggleStyle(on) {
    S.styling = on === undefined ? !S.styling : !!on;
    S.pickColour = null;
    R.bagCard.classList.toggle('styling', S.styling);
    R.sty.classList.toggle('on', S.styling);
    if (S.styling) { renderStyle(); setTimeout(() => { const i = R.style.querySelector('input'); if (i) i.focus(); }, 30); }
    else { R.style.innerHTML = ''; if (S.bag) R.bagCard.style.setProperty('--bc', S.bag.hex || '#08afa2'); }
  }

  function renderLog() {
    if (!S.log.length) { R.logL.innerHTML = `<li class="none">${esc(t('ui_log_empty', 'Moves show up here'))}</li>`; return; }
    R.logL.innerHTML = S.log.map((e, i) => {
      const where = e.dir === 'in' ? t('ui_in', 'into the bag') : e.dir === 'out' ? t('ui_out', 'to pockets') : t('ui_inside', 'rearranged');
      const who = e.by ? (e.dir === 'in' ? t('ui_by_in', '%s packed it', e.by) : e.dir === 'out' ? t('ui_by_out', '%s took it', e.by) : t('ui_by_inside', '%s moved it', e.by)) : where;
      const d = e.dir === 'in' ? `+${e.count}` : e.dir === 'out' ? `−${e.count}` : `${e.count}`;
      return `<li class="${e.dir}${i === 0 && e.fresh ? ' fresh' : ''}${e.by ? ' other' : ''}"><span class="tm">${esc(e.at)}</span><span class="th"><img src="${imgOf(e)}" alt="" onerror="${imgFallback}"></span>
        <span class="tx"><b>${esc(e.label || e.name)}</b><small>${esc(who)}</small></span><span class="d">${esc(d)}</span></li>`;
    }).join('');
    S.log.forEach(e => { e.fresh = false; });
  }
  function logMove(m, by) {
    if (!m) return;
    S.log.unshift({ name: m.name, label: m.label, image: m.image, count: m.count, dir: m.dir || 'in', by: by || null, at: clock(), fresh: true });
    S.log.length = Math.min(S.log.length, 8);
    renderLog();
  }

  function renderAll() { renderBag(); renderMe(); renderQty(); renderLog(); }

  /* ─────────────── quantity ─────────────── */
  function setQty(v) {
    if (v === 'stack') S.stack = true;
    else { S.stack = false; S.qty = clamp(Math.floor(Number(v) || 1), 1, 999); }
    renderQty(); NZA.audio.tick();
  }
  function step(d) {
    if (S.stack) { S.stack = false; S.qty = d > 0 ? 50 : 10; }
    else S.qty = clamp(S.qty + d, 1, 999);
    renderQty(); NZA.audio.tick();
  }
  const curCount = () => (S.stack ? 'all' : S.qty);

  /* ─────────────── positions inside the app (zoom-safe: layout offsets, not client rects) ─────────────── */
  function posIn(node) {
    let x = 0, y = 0, n = node;
    const root = A.el;
    while (n && n !== root) { x += n.offsetLeft; y += n.offsetTop; n = n.offsetParent; }
    for (let p = node.parentElement; p && p !== root; p = p.parentElement) { x -= p.scrollLeft || 0; y -= p.scrollTop || 0; }
    return { x, y, w: node.offsetWidth, h: node.offsetHeight };
  }

  /* ─────────────── tooltips ─────────────── */
  function findItem(side, slot) {
    const list = side === 'bag' ? (S.bag && S.bag.items) : (S.me && S.me.items);
    return (list || []).find(i => String(i.slot) === String(slot));
  }
  function onOver(e) {
    if (S.drag || S.pour) return;
    const s = e.target.closest && e.target.closest('[data-item]');
    if (!s || s === S.tipFor) return;
    showTip(s);
  }
  function showTip(node) {
    if (!node) return;
    const side = node.dataset.side, it = findItem(side, node.dataset.slot);
    if (!it) return hideTip();
    S.tipFor = node;
    const per = Number(it.weight) || 0;
    const dis = side === 'me' && it.allowed === false;
    const rows = [
      [t('ui_weight', 'Weight'), `${esc(grams(per))} <em>${esc(t('ui_each', 'each'))}</em> · ${esc(grams(per * it.count))} <em>${esc(t('ui_total', 'total'))}</em>`],
      [t('ui_count', 'Count'), `× ${esc(it.count)}`],
    ].concat((it.meta || []).filter(m => m.k).map(m => [keyLabel(m.k), esc(m.v)]));
    const notes = (it.meta || []).filter(m => !m.k).map(m => `<p class="md">${esc(m.v)}</p>`).join('');
    const where = side === 'bag' ? t('ui_tip_bag', 'to your pockets') : t('ui_tip_me', 'into the bag');
    R.tip.innerHTML = `
      <div class="th"><span class="ti"><img src="${imgOf(it)}" alt="" onerror="${imgFallback}"></span>
        <div><b>${esc(it.label)}</b><span class="cat">${esc(catLabel(it.cat))}</span></div></div>
      ${it.desc ? `<p class="d">${esc(it.desc)}</p>` : ''}${notes}
      <ul>${rows.map(([l, v]) => `<li><span>${esc(l)}</span><b>${v}</b></li>`).join('')}</ul>
      ${dis ? `<div class="no">${icon('ban')}${esc(t('ui_stays', 'Stays in your pockets'))}</div>`
            : `<div class="hk"><kbd>Click</kbd><span>${esc(S.stack ? t('ui_stack', 'Stack') : `${S.qty}×`)} ${esc(where)}</span></div>`}`;
    R.tip.classList.toggle('flip', side === 'me');
    const p = posIn(node), W = R.tip.offsetWidth || 270;
    const col = side === 'bag' ? posIn(R.right) : posIn(R.left);
    const x = side === 'bag' ? col.x - W - 14 : col.x + col.w + 14;
    R.tip.style.left = `${x}px`;
    R.tip.classList.add('on');
    const H = R.tip.offsetHeight, maxY = A.el.clientHeight - H - 16;
    R.tip.style.top = `${clamp(p.y + p.h / 2 - 40, 16, Math.max(16, maxY))}px`;
  }
  function hideTip() { S.tipFor = null; if (R.tip) R.tip.classList.remove('on'); }

  /* ─────────────── mouse: click / hold-to-pour / drag ─────────────── */
  const POUR_DELAY = 320;
  function onDown(e) {
    const node = e.target.closest && e.target.closest('[data-item]');
    if (!node || (e.button !== 0 && e.button !== 2) || !S.on) return;
    e.preventDefault();
    const it = findItem(node.dataset.side, node.dataset.slot);
    if (!it) return;
    S.press = { el: node, side: node.dataset.side, slot: Number(node.dataset.slot), name: node.dataset.name, x: e.clientX, y: e.clientY, button: e.button, shift: e.shiftKey, max: it.count, dis: node.dataset.side === 'me' && it.allowed === false };
    if (e.button === 0 && !e.shiftKey && !S.press.dis) {
      const pr = S.press;
      pr.timer = setTimeout(() => { if (S.press === pr && !S.drag) startPour(pr); }, POUR_DELAY);
    }
  }
  function startPour(pr) {
    hideTip();
    const ring = document.createElement('span');
    ring.className = 'mb-pour';
    const C = 2 * Math.PI * 21;
    ring.innerHTML = `<svg viewBox="0 0 48 48"><circle class="bg" cx="24" cy="24" r="21"/><circle class="fg" cx="24" cy="24" r="21" stroke-dasharray="${C}" stroke-dashoffset="${C}"/></svg><b>${pr.side === 'me' ? '+' : '−'}1</b>`;
    pr.el.appendChild(ring);
    const pour = { pr, n: 1, ring, C, t0: performance.now(), next: performance.now() + 260 };
    S.pour = pour;
    pr.el.classList.add('pouring');
    NZA.audio.click(700);
    const tick = () => {
      if (S.pour !== pour) return;
      const now = performance.now();
      if (now >= pour.next && pour.n < pr.max) {
        pour.n++;
        const held = (now - pour.t0) / 1000;
        pour.next = now + Math.max(45, 240 - held * 110);
        ring.querySelector('b').textContent = `${pr.side === 'me' ? '+' : '−'}${pour.n}`;
        NZA.audio.tick();
      }
      ring.querySelector('.fg').style.strokeDashoffset = `${C * (1 - pour.n / Math.max(1, pr.max))}`;
      pour.raf = requestAnimationFrame(tick);
    };
    pour.raf = requestAnimationFrame(tick);
  }
  function endPour() {
    const pour = S.pour;
    S.pour = null;
    if (!pour) return 0;
    cancelAnimationFrame(pour.raf);
    pour.ring.remove();
    pour.pr.el.classList.remove('pouring');
    return pour.n;
  }
  function onMove(e) {
    const p = S.press;
    if (!p) return;
    if (!S.drag && !S.pour && p.button === 0 && !p.dis && Math.hypot(e.clientX - p.x, e.clientY - p.y) > 6) { clearTimeout(p.timer); startDrag(p); }
    if (!S.drag) return;
    ghost.style.left = `${e.clientX}px`; ghost.style.top = `${e.clientY}px`;
    const under = document.elementFromPoint(e.clientX, e.clientY);
    const slot = under && under.closest && under.closest('.mb-slot');
    A.el.querySelectorAll('.mb-slot.drop').forEach(x => x.classList.remove('drop'));
    R.bagCard.classList.toggle('dropzone', !!(under && under.closest && under.closest('.mb-bag')) && S.drag.side === 'me');
    R.pk.classList.toggle('dropzone', !!(under && under.closest && under.closest('.mb-pk')) && S.drag.side === 'bag');
    if (slot && slot !== S.drag.el) slot.classList.add('drop');
  }
  function onUp(e) {
    const p = S.press;
    S.press = null;
    if (!p) return;
    clearTimeout(p.timer);
    if (S.drag) return endDrag(e);
    if (S.pour) {
      const n = endPour();
      if (n > 0) doMove(p, n);
      return;
    }
    if (p.dis) { p.el.classList.remove('shake'); void p.el.offsetWidth; p.el.classList.add('shake'); NZA.audio.click(260); return; }
    doMove(p, p.button === 2 ? 1 : (p.shift || e.shiftKey ? 'all' : curCount()));
  }
  function doMove(p, count) {
    move(p.side === 'me' ? { dir: 'in', from: p.slot, count, name: p.name } : { dir: 'out', from: p.slot, count, name: p.name }, p.el);
  }
  function startDrag(p) {
    const it = findItem(p.side, p.slot);
    if (!it) return;
    hideTip();
    S.drag = { side: p.side, slot: p.slot, name: p.name, el: p.el, shift: p.shift };
    p.el.classList.add('lifted');
    ghost = document.createElement('div');
    ghost.className = 'mb-ghost';
    const n = p.shift || S.stack ? it.count : Math.min(S.qty, it.count);
    ghost.innerHTML = `<img src="${imgOf(it)}" alt="" onerror="${imgFallback}"><b>${esc(n)}</b>`;
    ghost.style.setProperty('--z', String(NZA.zoom || 1));
    ghost.style.left = `${p.x}px`; ghost.style.top = `${p.y}px`;
    document.body.appendChild(ghost);
    NZA.audio.click(520);
  }
  function endDrag(e) {
    const d = S.drag;
    S.drag = null;
    if (ghost) { ghost.remove(); ghost = null; }
    d.el.classList.remove('lifted');
    A.el.querySelectorAll('.mb-slot.drop').forEach(x => x.classList.remove('drop'));
    R.bagCard.classList.remove('dropzone'); R.pk.classList.remove('dropzone');
    const under = document.elementFromPoint(e.clientX, e.clientY);
    if (!under || !under.closest) return;
    const count = d.shift || e.shiftKey ? 'all' : curCount();
    const slot = under.closest('.mb-slot');
    if (d.side === 'me' && (slot || under.closest('.mb-bag'))) {
      move({ dir: 'in', from: d.slot, to: slot ? Number(slot.dataset.slot) : undefined, count, name: d.name }, d.el, slot);
    } else if (d.side === 'bag' && slot) {
      if (Number(slot.dataset.slot) !== d.slot) move({ dir: 'bag', from: d.slot, to: Number(slot.dataset.slot), count, name: d.name }, slot, slot);
    } else if (d.side === 'bag' && under.closest('.mb-pk')) {
      move({ dir: 'out', from: d.slot, count, name: d.name }, d.el);
    }
  }

  /* ─────────────── flights (the item image travels between the docks) ─────────────── */
  function land(node) { if (!node) return; node.classList.remove('land'); void node.offsetWidth; node.classList.add('land'); }
  function fly(m, fromBox, toNode) {
    if (!fromBox || !toNode || !R.fx || !toNode.isConnected) return land(toNode);
    const to = posIn(toNode);
    const x0 = fromBox.x + fromBox.w / 2, y0 = fromBox.y + fromBox.h / 2;
    const x1 = to.x + to.w / 2, y1 = to.y + Math.min(to.h, 80) / 2;
    const f = document.createElement('div');
    f.className = `mb-fly ${m.dir || 'in'}`;
    f.innerHTML = `<img src="${imgOf(m)}" alt="" onerror="${imgFallback}"><b>${m.dir === 'out' ? '−' : '+'}${esc(m.count)}</b>`;
    R.fx.appendChild(f);
    const lift = Math.min(220, Math.abs(x1 - x0) * 0.22 + 40);
    const mx = (x0 + x1) / 2, my = Math.min(y0, y1) - lift;
    const anim = f.animate([
      { transform: `translate(${x0}px,${y0}px) scale(.7)`, opacity: 0 },
      { transform: `translate(${(x0 + mx) / 2}px,${(y0 + my) / 2}px) scale(1.05)`, opacity: 1, offset: 0.25 },
      { transform: `translate(${mx}px,${my}px) scale(1)`, opacity: 1, offset: 0.55 },
      { transform: `translate(${x1}px,${y1}px) scale(.55)`, opacity: 0.2 },
    ], { duration: 640, easing: 'cubic-bezier(.35,.05,.25,1)', fill: 'forwards' });
    anim.onfinish = () => { f.remove(); land(toNode); };
  }

  /* ─────────────── server round trips (queued, in order) ─────────────── */
  function apply(res) {
    if (!res || typeof res !== 'object') return;
    if (res.bag) S.bag = normBag(res.bag);
    if (res.me) S.me = normMe(res.me);
    renderBag(); renderMe();
    if (S.tipFor && !document.body.contains(S.tipFor)) hideTip();
  }
  function enqueue(fn) {
    S.busy++;
    A.el.classList.add('busy');
    S.queue = S.queue.then(fn).catch(err => console.error('[medbag]', err)).finally(() => {
      S.busy = Math.max(0, S.busy - 1);
      if (!S.busy) A.el.classList.remove('busy');
    });
    return S.queue;
  }
  const bagTitle = () => (S.bag && S.bag.name) || t('ui_bag_default', 'Medical bag');
  function failToast(res) {
    NZA.toast({ title: bagTitle(), message: (res && res.msg) || t('err_failed', "That didn't work. Try again"), type: 'error', duration: 3200 });
    NZA.audio.fail();
  }
  function move(data, fromEl, toEl) {
    if (!S.on) return;
    const fromBox = fromEl ? posIn(fromEl) : null;
    if (fromEl) fromEl.classList.add('pending');
    return enqueue(async () => {
      const res = await NZA.post('medbag:move', data);
      if (fromEl) fromEl.classList.remove('pending');
      if (!res || res === 'timeout') return failToast(null);
      apply(res);
      if (!res.ok) return failToast(res);
      const m = res.moved;
      if (!m) return;
      logMove(m);
      NZA.audio.click(m.dir === 'out' ? 560 : 760);
      if (m.dir === 'in') {
        const items = S.bag.items || [];
        const it = items.find(i => i.name === m.name && data.to && i.slot === data.to) || items.find(i => i.name === m.name);
        fly(m, fromBox, (it && R.grid.querySelector(`.mb-slot[data-slot="${it.slot}"]`)) || R.bagCard);
      } else if (m.dir === 'out') {
        fly(m, fromBox, R.list.querySelector(`.mb-row[data-name="${cssEsc(m.name)}"]`) || R.pk);
      } else if (toEl) {
        land(R.grid.querySelector(`.mb-slot[data-slot="${data.to}"]`));
      }
    });
  }
  function action(act) {
    if (act === 'close') return NZA.close('medbag');
    if (act === 'style') return toggleStyle();
    if (act === 'empty') {
      NZA.ui.Modal({
        title: t('ui_unpack_q', 'Unpack the whole bag?'), text: t('ui_unpack_t', 'Everything goes into your pockets while there is room.'),
        icon: 'arrow-up', tone: 'teal', host: A.el,
        actions: [{ label: t('ui_cancel', 'Cancel'), kind: 'line' }, { label: t('ui_unpack_ok', 'Unpack'), kind: 'teal', onClick: () => { run('empty'); } }],
      });
      return;
    }
    if (act === 'lock') return run('lock', { on: !(S.bag && S.bag.locked) });
    run(act);
  }
  function run(act, data) {
    return enqueue(async () => {
      const res = await NZA.post('medbag:action', { action: act, data: data || {} });
      if (!res || res === 'timeout') return failToast(null);
      apply(res);
      if (!res.ok) return failToast(res);
      const list = arr(res.movedList);
      list.slice(0, 8).reverse().forEach(m => logMove(m));
      list.slice(0, 6).forEach((m, i) => setTimeout(() => {
        const src = m.dir === 'in' ? R.pk : R.bagCard, dst = m.dir === 'in' ? R.bagCard : R.pk;
        const b = posIn(src);
        fly(m, { x: b.x + b.w / 2 - 20, y: b.y + 90, w: 40, h: 40 }, dst);
      }, i * 110));
      if (res.msg) NZA.toast({ title: bagTitle(), message: res.msg, type: 'success', duration: 2600, icon: act === 'lock' ? (S.bag.locked ? 'lock' : 'unlock') : act === 'style' ? 'palette' : 'check' });
      if (act === 'sort') { R.grid.classList.remove('sorted'); void R.grid.offsetWidth; R.grid.classList.add('sorted'); }
    });
  }

  /* ─────────────── app ─────────────── */
  A = NZA.app('medbag', {
    camInput: false,
    init(el) { build(el); texts(); renderQty(); renderLog(); },
    open(d) {
      loc = Object.assign({}, loc, d.locale || {});
      texts();
      S.on = true; S.bag = normBag(d.bag); S.me = normMe(d.me); S.kit = !!d.kit; S.colours = arr(d.colours);
      S.filter = ''; R.filter.value = ''; S.log = []; S.styling = false; S.pickColour = null;
      R.bagCard.classList.remove('styling'); R.style.innerHTML = ''; R.sty.classList.remove('on');
      hideTip();
      renderAll();
    },
    close() {
      S.on = false; hideTip();
      if (S.pour) endPour();
      if (ghost) { ghost.remove(); ghost = null; }
      S.drag = null; S.press = null;
      A.el.querySelectorAll('.nza-modal-wrap').forEach(m => m.remove());
      if (R.fx) R.fx.innerHTML = '';
    },
    msg: {
      sync(d) {
        if (!d || !d.bag) return;
        S.bag = normBag(d.bag); renderBag();
        if (d.moved) logMove(d.moved, d.by);
        if (S.tipFor && !document.body.contains(S.tipFor)) hideTip();
      },
      me(d) {
        if (!d || !d.me || S.drag || S.busy || S.pour) return;
        S.me = normMe(d.me); renderMe();
        if (S.tipFor && !document.body.contains(S.tipFor)) hideTip();
      },
    },
    keys: {
      '1'(e) { if (typing(e)) return false; setQty(1); },
      '2'(e) { if (typing(e)) return false; setQty(5); },
      '3'(e) { if (typing(e)) return false; setQty(10); },
      '4'(e) { if (typing(e)) return false; setQty('stack'); },
      '+'(e) { if (typing(e)) return false; step(1); },
      '='(e) { if (typing(e)) return false; step(1); },
      '-'(e) { if (typing(e)) return false; step(-1); },
      KeyF(e) { if (typing(e)) return false; R.filter.focus(); },
      Enter(e) {
        if (S.styling && typing(e)) { const b = R.style.querySelector('[data-style="save"]'); if (b) b.click(); return; }
        return false;
      },
      Escape() {
        const modal = A.el.querySelector('.nza-modal-wrap');
        if (modal) { modal.remove(); return; }
        if (S.styling) { toggleStyle(false); return; }
        if (document.activeElement === R.filter && R.filter.value) { R.filter.value = ''; S.filter = ''; renderMe(); return; }
        NZA.close('medbag');
      },
    },
    preview() { preview(); },
  });
  function typing(e) { return e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA'); }

  /* ═══════════════════════════ PREVIEW (browser only) ═══════════════════════════ */
  function preview() {
    const img = n => `img/items/${n}.png`;
    const W = { bandage: 50, gauze: 20, tourniquet: 150, painkillers: 30, splint: 400, saline_bag: 550, iv_kit: 80, sterile_dressing: 40, burn_dressing: 60,
      foil_blanket: 60, ice_pack: 200, blood_bag: 550, morphine: 20, adrenaline: 20, suture_kit: 120, txa: 30, cervical_collar: 300, stethoscope: 200,
      ems_pager: 100, medikit: 600, phone: 190, water: 500, lockpick: 80, pelvic_binder: 700, oxygen_mask: 300 };
    const L = { bandage: 'Bandage', gauze: 'Gauze', tourniquet: 'Tourniquet', painkillers: 'Painkillers', splint: 'Splint', saline_bag: 'Saline 500 ml', iv_kit: 'IV Kit',
      sterile_dressing: 'Sterile Dressing', burn_dressing: 'Burn Dressing', foil_blanket: 'Foil Blanket', ice_pack: 'Ice Pack', blood_bag: 'Blood Bag', morphine: 'Morphine',
      adrenaline: 'Adrenaline 1 mg', suture_kit: 'Suture Kit', txa: 'TXA 1 g', cervical_collar: 'Cervical Collar', stethoscope: 'Stethoscope', ems_pager: 'EMS Pager',
      medikit: 'Medkit', phone: 'Phone', water: 'Water', lockpick: 'Lockpick', pelvic_binder: 'Pelvic Binder', oxygen_mask: 'Oxygen Mask' };
    const C = { bandage: 'first_aid', gauze: 'wound_care', tourniquet: 'first_aid', painkillers: 'medication', splint: 'orthopedic', saline_bag: 'fluids', iv_kit: 'fluids',
      sterile_dressing: 'wound_care', burn_dressing: 'wound_care', foil_blanket: 'first_aid', ice_pack: 'first_aid', blood_bag: 'fluids', morphine: 'medication', adrenaline: 'medication',
      suture_kit: 'wound_care', txa: 'medication', cervical_collar: 'orthopedic', stethoscope: 'equipment', ems_pager: 'equipment', medikit: 'first_aid', pelvic_binder: 'orthopedic', oxygen_mask: 'airway' };
    const D = { bandage: 'Elastic roll for dressing wounds and slowing light bleeding.', painkillers: 'Fast-acting pain relief tablets.', tourniquet: 'Windlass strap that stops limb bleeding.',
      splint: 'Mouldable splint for a broken arm or leg.', saline_bag: 'Bag of 0.9% saline for infusion.', blood_bag: 'A labelled unit of donated blood.', gauze: 'Sterile gauze for packing deep wounds.' };
    const STACK = { blood_bag: 1, stethoscope: 1, ems_pager: 1 };
    const OWN = new Set(Object.keys(C));
    const COLOURS = [{ id: 'red', hex: '#e5484d', label: 'Red' }, { id: 'orange', hex: '#f08a24', label: 'Orange' }, { id: 'green', hex: '#2fb36b', label: 'Green' }, { id: 'magenta', hex: '#d23c9a', label: 'Magenta' }];
    const mk = (name, count, slot, meta) => ({ slot, name, label: L[name] || name, image: img(['phone', 'water', 'lockpick'].includes(name) ? 'nza_unknown' : name), count, weight: W[name] || 100, desc: D[name], cat: C[name] || 'other', meta, allowed: OWN.has(name) });
    const bag = { id: 'MB-7K2QF', name: 'Trauma', colour: 'red', hex: '#e5484d', owner: 'Maya Reyes', mine: true, locked: false, canLock: true, canStyle: true, slots: 20, maxWeight: 20000, items: [
      mk('painkillers', 12, 1), mk('bandage', 18, 2), mk('tourniquet', 4, 3), mk('gauze', 20, 4), mk('splint', 2, 5),
      mk('saline_bag', 2, 6), mk('iv_kit', 3, 7), mk('burn_dressing', 4, 8), mk('blood_bag', 1, 11, [{ k: 'type', v: 'O-' }, { k: 'ml', v: '450' }, { k: 'serial', v: 'LS-04172' }]),
    ] };
    const me = { maxWeight: 85000, items: [
      mk('blood_bag', 1, 1, [{ k: 'type', v: 'A+' }, { k: 'ml', v: '450' }, { k: 'serial', v: 'LS-04188' }]), mk('ems_pager', 1, 2), mk('stethoscope', 1, 3), mk('morphine', 3, 4),
      mk('bandage', 9, 5), mk('sterile_dressing', 6, 6), mk('foil_blanket', 2, 7), mk('ice_pack', 2, 8), mk('adrenaline', 4, 9), mk('suture_kit', 2, 10),
      mk('txa', 3, 11), mk('cervical_collar', 1, 12), mk('pelvic_binder', 1, 13), mk('oxygen_mask', 2, 14), mk('medikit', 1, 15),
      mk('phone', 1, 16), mk('water', 2, 17), mk('lockpick', 3, 18),
    ] };
    const wsum = list => list.reduce((a, i) => a + i.weight * i.count, 0);
    const refresh = () => { bag.weight = wsum(bag.items); me.weight = wsum(me.items) + 31200; };
    const clone = o => JSON.parse(JSON.stringify(o));
    const reply = extra => { refresh(); return Object.assign({ ok: true, bag: clone(bag), me: clone(me) }, extra); };
    const cap = n => STACK[n] || 50;
    const sameMeta = (a, b) => JSON.stringify(a.meta || null) === JSON.stringify(b.meta || null);
    const addToBag = (src, n, to) => {
      let left = n; const tries = [];
      if (to) tries.push(to);
      bag.items.filter(i => i.name === src.name && sameMeta(i, src)).forEach(i => tries.push(i.slot));
      for (let s = 1; s <= bag.slots; s++) if (!bag.items.find(i => i.slot === s)) tries.push(s);
      for (const s of tries) {
        if (left <= 0) break;
        const e = bag.items.find(i => i.slot === s);
        if (!e) { const add = Math.min(cap(src.name), left); bag.items.push(Object.assign(clone(src), { slot: s, count: add })); left -= add; }
        else if (e.name === src.name && sameMeta(e, src) && e.count < cap(src.name)) { const add = Math.min(cap(src.name) - e.count, left); e.count += add; left -= add; }
      }
      return n - left;
    };
    const addToMe = (src, n) => {
      const e = me.items.find(i => i.name === src.name && sameMeta(i, src) && !STACK[i.name]);
      if (e) e.count += n;
      else { const slot = Math.max(0, ...me.items.map(i => i.slot)) + 1; me.items.push(Object.assign(clone(src), { slot, count: n, allowed: true })); }
    };
    const mv = (it, n, dir) => ({ name: it.name, label: it.label, image: it.image, count: n, dir });
    NZA.mock('medbag:move', d => {
      if (d.dir === 'in') {
        const it = me.items.find(i => i.slot === d.from);
        if (!it) return reply({ ok: false, msg: 'Your pockets changed. Try again' });
        if (!it.allowed) return reply({ ok: false, msg: `${it.label} does not belong in a medical bag` });
        let n = d.count === 'all' ? it.count : Math.min(d.count, it.count);
        n = Math.min(n, Math.floor((bag.maxWeight - wsum(bag.items)) / it.weight));
        if (n < 1) return reply({ ok: false, msg: 'Too heavy. The bag can hold 20.0 kg' });
        n = addToBag(it, n, d.to);
        if (n < 1) return reply({ ok: false, msg: 'The bag has no free slot for that' });
        it.count -= n; if (it.count <= 0) me.items.splice(me.items.indexOf(it), 1);
        return reply({ moved: mv(it, n, 'in') });
      }
      if (d.dir === 'out') {
        const it = bag.items.find(i => i.slot === d.from);
        if (!it) return reply({ ok: false, msg: 'That slot is empty' });
        const n = d.count === 'all' ? it.count : Math.min(d.count, it.count);
        it.count -= n; addToMe(it, n);
        if (it.count <= 0) bag.items.splice(bag.items.indexOf(it), 1);
        return reply({ moved: mv(it, n, 'out') });
      }
      if (d.dir === 'bag') {
        const it = bag.items.find(i => i.slot === d.from), tg = bag.items.find(i => i.slot === d.to);
        if (!it) return reply({ ok: false });
        if (!tg) it.slot = d.to;
        else if (tg.name === it.name && sameMeta(tg, it)) { const add = Math.min(cap(it.name) - tg.count, it.count); tg.count += add; it.count -= add; if (it.count <= 0) bag.items.splice(bag.items.indexOf(it), 1); }
        else { tg.slot = d.from; it.slot = d.to; }
        return reply({ moved: mv(it, it.count, 'bag') });
      }
      return reply({ ok: false });
    });
    NZA.mock('medbag:action', d => {
      if (d.action === 'lock') { bag.locked = !!(d.data && d.data.on); return reply({ msg: bag.locked ? 'Bag locked. Only you can open it now' : 'Bag unlocked' }); }
      if (d.action === 'style') {
        const c = COLOURS.find(x => x.id === d.data.colour) || COLOURS[0];
        bag.colour = c.id; bag.hex = c.hex; bag.name = (d.data.name || '').trim().slice(0, 20) || null;
        return reply({ msg: 'Bag updated' });
      }
      if (d.action === 'sort') { bag.items.sort((a, b) => a.cat.localeCompare(b.cat) || a.label.localeCompare(b.label)); bag.items.forEach((i, k) => { i.slot = k + 1; }); return reply({ msg: 'Bag sorted' }); }
      if (d.action === 'kit') {
        const list = [];
        [['bandage', 24], ['tourniquet', 4], ['sterile_dressing', 6]].forEach(([n, c]) => {
          const have = bag.items.filter(i => i.name === n).reduce((a, i) => a + i.count, 0);
          const it = me.items.find(i => i.name === n);
          const k = Math.min(Math.max(0, c - have), it ? it.count : 0);
          if (k > 0) { addToBag(it, k); it.count -= k; if (it.count <= 0) me.items.splice(me.items.indexOf(it), 1); list.push(mv(it, k, 'in')); }
        });
        if (!list.length) return reply({ ok: false, msg: 'Nothing to move' });
        return reply({ movedList: list, msg: `Packed ${list.reduce((a, m) => a + m.count, 0)} items into the bag` });
      }
      if (d.action === 'empty') {
        const list = bag.items.map(i => mv(i, i.count, 'out'));
        bag.items.forEach(i => addToMe(i, i.count)); bag.items.length = 0;
        return reply({ movedList: list, msg: `Took ${list.reduce((a, m) => a + m.count, 0)} items out of the bag` });
      }
      return reply({ ok: false });
    });

    const demo = new URLSearchParams(location.search).get('demo');
    if (demo === 'locked') Object.assign(bag, { mine: false, owner: 'J. Doe', locked: true, canLock: false, canStyle: false, name: null, colour: 'green', hex: '#2fb36b' });
    if (demo === 'empty') bag.items.length = 0;
    if (demo === 'full') {
      ['sterile_dressing', 'foil_blanket', 'ice_pack', 'adrenaline', 'suture_kit', 'txa', 'cervical_collar', 'pelvic_binder', 'oxygen_mask', 'medikit', 'morphine']
        .forEach((n, i) => bag.items.push(mk(n, n === 'pelvic_binder' ? 8 : n === 'medikit' ? 6 : 4, 9 + i + (i >= 2 ? 1 : 0))));
    }
    refresh();
    NZA.demo('medbag', { bag: clone(bag), me: clone(me), kit: true, colours: COLOURS });

    // a short history: our own moves and one by a colleague (arrives through 'sync')
    logMove({ name: 'splint', label: 'Splint', image: img('splint'), count: 1, dir: 'out' });
    logMove({ name: 'painkillers', label: 'Painkillers', image: img('painkillers'), count: 2, dir: 'out' }, 'J. Doe');
    logMove({ name: 'bandage', label: 'Bandage', image: img('bandage'), count: 5, dir: 'in' });
    setQty(5);

    const node = sel => A.el.querySelector(sel);
    if (demo === 'tip') setTimeout(() => showTip(node('.mb-grid .mb-slot[data-slot="11"]')), 300);
    if (demo === 'tipme') setTimeout(() => showTip(node('.mb-list .mb-row[data-slot="17"]')), 300);
    if (demo === 'style') setTimeout(() => { toggleStyle(true); S.pickColour = 'green'; renderStyle(); R.bagCard.style.setProperty('--bc', '#2fb36b'); }, 300);
    if (demo === 'stack') setTimeout(() => setQty('stack'), 300);
    if (demo === 'pour') setTimeout(() => {
      const el = node('.mb-list .mb-row[data-slot="5"]');
      S.press = { el, side: 'me', slot: 5, name: 'bandage', x: 0, y: 0, button: 0, shift: false, max: 9, dis: false };
      startPour(S.press);
      S.pour.n = 6; S.pour.next = Infinity;
      S.pour.ring.querySelector('b').textContent = '+6';
    }, 300);
    if (demo === 'drag') setTimeout(() => {
      const s = node('.mb-list .mb-row[data-slot="6"]');
      const r = s.getBoundingClientRect();
      onDown({ target: s, button: 0, clientX: r.left + 30, clientY: r.top + 20, shiftKey: false, preventDefault() {} });
      clearTimeout(S.press.timer);
      const tgt = node('.mb-grid .mb-slot[data-slot="10"]').getBoundingClientRect();
      onMove({ clientX: r.left + 60, clientY: r.top + 10 });
      onMove({ clientX: tgt.left + tgt.width / 2, clientY: tgt.top + tgt.height / 2 });
    }, 300);
    if (demo === 'fly') setTimeout(() => {
      move({ dir: 'in', from: 9, count: 4, name: 'adrenaline' }, node('.mb-list .mb-row[data-slot="9"]'));
    }, 300);
  }
})();
