/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · app 'medbag'
   One app, three modes:

   'bag'  The medical bag window. Your pockets dock on the LEFT edge (quantity dial under it), the
          bag dock on the RIGHT edge with the bag drawn OPEN from above: the lid flipped back with
          its mesh pocket, the zipper hinge, the main compartment with elastic loops and the two
          side pouches. Par levels come from the restock list: stocked supplies carry a par bar,
          missing ones leave a shadow outline in a free slot (click it to pack that supply from
          your pockets). The bag log sits under the bag. The centre stays clear: the bag on the
          floor stays in view and moved items fly between the docks.
   'zip'  Body bag zip-up card (bottom-left, no focus): who is being bagged, a step spine and a
          zipper that closes tooth by tooth with the progress.
   'tag'  The toe tag of a body bag (top-right, no focus): a manila tag filled in by hand.

   Lua → JS   open { mode?: 'bag', locale, bag, me, kit: [{ name, label, image, count }], colours, layout }
              open { mode: 'zip', locale, zip: { name, sub, steps: [{ label, share }], key, keyLabel } }
                   zipStep { i, ms }   zipDone {}
              open { mode: 'tag', locale, tag: { id, name, kind, tod, date, cause, by, where, sex, age, blood, call }, ms }
              sync { bag, moved?, by? }   me { me }
   JS → Lua   medbag:move   { dir: 'in'|'out'|'bag', from, to?, count: n|'all', name }
              medbag:action { action: 'sort'|'lock'|'kit'|'empty'|'style', data }
              → { ok, bag, me, moved?, movedList?, msg? }      medbag:close (router)

   bag    = { id, name, colour, hex, owner, mine, locked, canLock, canStyle, slots, weight, maxWeight,
              items: [{ slot, name, label, image, count, weight (g/unit), desc, cat, meta: [{ k?, v }] }] }
   me     = { items: [{ slot, name, label, image, count, weight, desc, cat, meta, allowed }], weight, maxWeight }
   layout = [{ id, place: 'main'|'lid'|'left'|'right', slots, cols?, label }]  (slot numbers follow the order)

   Mouse: click = move the dial quantity · hold = pour one by one (release to move) ·
          Shift + click = whole stack · right click = one · drag = onto a bag slot / the pockets ·
          click a shadow outline = pack that supply up to its par level.
   Dial:  a count arc (1 … 40, notches 1 and 3) then two share notches: half (of the clicked
          stack, rounded up) and the whole stack.
   Keys:  1 2 3 4 = quantity 1 / 3 / half / stack · + − = step · F = filter · Esc = close.
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
  const initials = name => String(name || '?').trim().split(/\s+/).slice(0, 2).map(w => w[0] || '').join('').toUpperCase();

  // Lua sends empty tables as {} → real arrays
  const arr = v => (Array.isArray(v) ? v : (v && typeof v === 'object' ? Object.values(v) : []));
  const normItems = list => arr(list).map(it => Object.assign({}, it, { meta: it && it.meta ? arr(it.meta) : null }));
  const normBag = b => (b ? Object.assign({}, b, { items: normItems(b.items) }) : null);
  const normMe = m => (m ? Object.assign({}, m, { items: normItems(m.items) }) : null);

  /* ─────────────── state ─────────────── */
  // our own notch set: two counts, then two shares of the clicked stack (half, whole)
  const PRESETS = [1, 3, 'half', 'stack'];
  const S = {
    on: false, mode: 'bag', bag: null, me: null, kit: [], kitOn: false, colours: [], layout: null,
    qty: 1, stack: false, half: false, filter: '', log: [],
    queue: Promise.resolve(), busy: 0,
    press: null, drag: null, pour: null, tipFor: null, styling: false, pickColour: null,
    zip: null, tagTimer: null,
  };
  let A = null, R = {}, ghost = null, odo = null, zipOdo = null;

  /* ─────────────── 240° dial geometry (same language as the procedure HUD) ─────────────── */
  const A0 = 150, SW = 240;
  const pt = (cx, cy, r, f) => { const a = (A0 + SW * clamp(f, 0, 1)) * Math.PI / 180; return [cx + r * Math.cos(a), cy + r * Math.sin(a)]; };
  const arcD = (cx, cy, r, f0, f1) => {
    const [x0, y0] = pt(cx, cy, r, f0), [x1, y1] = pt(cx, cy, r, f1);
    return `M${x0.toFixed(2)} ${y0.toFixed(2)}A${r} ${r} 0 ${(f1 - f0) * SW > 180 ? 1 : 0} 1 ${x1.toFixed(2)} ${y1.toFixed(2)}`;
  };
  // quantity ↔ dial position: the count arc runs 1 → 0, 3 → ⅓, 40 → NUM_END;
  // past it sit the two share notches, half → ⅔ and stack → 1
  const NUM_END = 0.6, NUM_MAX = 40;
  const qtyPos = () => {
    if (S.stack) return 1;
    if (S.half) return 2 / 3;
    const q = S.qty;
    if (q <= 1) return 0;
    if (q <= 3) return ((q - 1) / 2) / 3;
    return 1 / 3 + Math.min(1, (q - 3) / (NUM_MAX - 3)) * (NUM_END - 1 / 3);
  };
  const posQty = f => {
    if (f >= 0.84) return 'stack';
    if (f > NUM_END + 0.02) return 'half';
    if (f <= 1 / 3) return Math.round(1 + f * 3 * 2);
    return Math.round(3 + Math.min(1, (f - 1 / 3) / (NUM_END - 1 / 3)) * (NUM_MAX - 3));
  };
  // what a click moves of a stack of n (half rounds up, never 0)
  const halfOf = n => Math.max(1, Math.ceil((Number(n) || 0) / 2));

  /* ─────────────── bag illustration bits ─────────────── */
  // front view of the bag in its colour (header identity tile)
  const BAG_SVG = `<svg viewBox="0 0 44 44" class="bagsvg" aria-hidden="true">
      <path class="hd" d="M15.5 12.5V9.2a2.4 2.4 0 0 1 2.4-2.4h8.2a2.4 2.4 0 0 1 2.4 2.4v3.3"/>
      <rect class="bd" x="5" y="12" width="34" height="23" rx="6"/>
      <rect class="sh" x="5" y="12" width="34" height="9" rx="6"/>
      <rect class="zp" x="8" y="15.2" width="28" height="1.3" rx=".65"/>
      <rect class="rf" x="5" y="29" width="34" height="2.6"/>
      <rect class="pt" x="16.5" y="18.5" width="11" height="9" rx="1.6"/>
      <path class="cr" d="M22 19.9v6.2M18.9 23h6.2"/>
      <circle class="wh" cx="11" cy="37" r="2.4"/><circle class="wh" cx="33" cy="37" r="2.4"/>
    </svg>`;
  const pullHTML = cls => `<span class="zpull ${cls || ''}"><i class="slider"></i><i class="tab"></i></span>`;
  const PLACE_FB = { main: 'Main compartment', lid: 'Lid pocket', left: 'Pouch L', right: 'Pouch R' };
  const DEF_LAYOUT = [
    { id: 'main', place: 'main', slots: 12, cols: 3 },
    { id: 'lid', place: 'lid', slots: 4 },
    { id: 'left', place: 'left', slots: 2 },
    { id: 'right', place: 'right', slots: 2 },
  ];

  /* ─────────────── markup ─────────────── */
  function build(el) {
    el.innerHTML = `
      <div class="mb-win">
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
              <span class="mb-swatch">${BAG_SVG}</span>
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
              <div class="mb-load"><svg viewBox="0 0 120 104"></svg><div class="mb-lv"><b></b><span></span></div><small class="mb-lc"></small></div>
              <ul class="mb-inst"></ul>
            </div>
            <div class="mb-open" data-side="bag"></div>
            <footer class="mb-foot">
              <button class="mb-act teal" data-act="kit">${icon('arrow-down')}<span></span><em></em></button>
              <button class="mb-act" data-act="empty">${icon('arrow-up')}<span></span></button>
            </footer>
          </section>
          <section class="mb-card mb-log nza-hud solid">
            <header class="mb-lh"><b></b><span></span></header>
            <ol class="mb-logl"></ol>
          </section>
        </aside>
        <div class="mb-tip nza-hud solid"></div>
        <div class="mb-fx"></div>
      </div>

      <section class="mb-zip nza-hud solid">
        <header class="zh"><span class="zk"></span><span class="zt"></span></header>
        <div class="zwho"><span class="zav"><i></i><b></b></span><div><b class="zn"></b><small class="zs"></small></div></div>
        <ol class="zsp"></ol>
        <div class="zzip"><svg viewBox="0 0 336 46" preserveAspectRatio="none"></svg></div>
        <footer class="zf"><span class="zpct"><span class="zodo"></span><i>%</i></span><span class="zkey"></span></footer>
      </section>

      <section class="mb-tagw"></section>`;

    const q = s => el.querySelector(s);
    R = {
      win: q('.mb-win'), left: q('.mb-left'), right: q('.mb-right'), pk: q('.mb-pk'), bagCard: q('.mb-bag'),
      pkT: q('.mb-pk-t'), pkW: q('.mb-pk-w'), pkRing: q('.mb-pk .mb-ring > svg.rg .fg'), filter: q('.mb-filter input'),
      list: q('.mb-list'), pnone: q('.mb-pk .mb-none'),
      dialSvg: q('.mb-dial > svg'), odoHost: q('.mb-odo'), stk: q('.mb-stk'), dc: q('.mb-dc'), pre: q('.mb-pre'), gest: q('.mb-gest'),
      bagT: q('.mb-bag-t'), bagS: q('.mb-bag-s'), style: q('.mb-style'),
      loadSvg: q('.mb-load > svg'), loadV: q('.mb-lv b'), loadU: q('.mb-lv span'), loadC: q('.mb-lc'), inst: q('.mb-inst'),
      open: q('.mb-open'),
      kit: q('[data-act="kit"]'), emp: q('[data-act="empty"]'), sty: q('[data-act="style"]'), sort: q('[data-act="sort"]'),
      lock: q('[data-act="lock"]'), close: q('[data-act="close"]'),
      logH: q('.mb-lh b'), logS: q('.mb-lh span'), logL: q('.mb-logl'),
      tip: q('.mb-tip'), fx: q('.mb-fx'),
      zip: q('.mb-zip'), zk: q('.mb-zip .zk'), zt: q('.mb-zip .zt'), zav: q('.mb-zip .zav b'), zn: q('.mb-zip .zn'), zs: q('.mb-zip .zs'),
      zsp: q('.mb-zip .zsp'), zsvg: q('.mb-zip .zzip svg'), zodo: q('.mb-zip .zodo'), zkey: q('.mb-zip .zkey'),
      tagw: q('.mb-tagw'),
    };
    odo = NZA.ui.FlipClock(R.odoHost, { value: '1', small: true });
    zipOdo = NZA.ui.FlipClock(R.zodo, { value: '0', small: true });

    el.addEventListener('click', e => {
      const b = e.target.closest('[data-act]');
      if (b) { e.preventDefault(); action(b.dataset.act); return; }
      const st = e.target.closest('[data-step]');
      if (st) { step(Number(st.dataset.step)); return; }
      const p = e.target.closest('[data-preset]');
      if (p) { const v = p.dataset.preset; setQty(v === 'stack' || v === 'half' ? v : Number(v)); }
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
      const from = e.target.closest && e.target.closest('[data-item],[data-ghost]');
      const to = e.relatedTarget && e.relatedTarget.closest && e.relatedTarget.closest('[data-item],[data-ghost]');
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
    R.loadC.textContent = t('ui_load_l', 'Load');
    R.logH.textContent = t('ui_log', 'Bag log');
    R.logS.textContent = t('ui_log_sub', 'Latest moves');
    R.gest.innerHTML = [
      [t('ui_g_click', 'Click'), t('ui_g_click_d', 'move the quantity')],
      [t('ui_g_hold', 'Hold'), t('ui_g_hold_d', 'pour one by one')],
      [t('ui_g_shift', 'Shift'), t('ui_g_shift_d', 'the whole stack')],
      [t('ui_g_right', 'RMB'), t('ui_g_right_d', 'just one')],
      [t('ui_g_drag', 'Drag'), t('ui_g_drag_d', 'onto a slot')],
    ].map(([k, d]) => `<li><kbd>${esc(k)}</kbd><span>${esc(d)}</span></li>`).join('');
  }

  /* ─────────────── par levels (the restock list) ─────────────── */
  // units of each item in the bag that count for its par level (plain stacks, no metadata)
  function haveByName(items) {
    const h = {};
    (items || []).forEach(i => { if (!i.meta || !i.meta.length) h[i.name] = (h[i.name] || 0) + (Number(i.count) || 0); });
    return h;
  }
  function pocketsOf(name) {
    return ((S.me && S.me.items) || []).filter(i => i.name === name && i.allowed !== false);
  }
  function pocketCount(name) { return pocketsOf(name).reduce((a, i) => a + (Number(i.count) || 0), 0); }
  function parInfo() {
    const items = (S.bag && S.bag.items) || [];
    const have = haveByName(items);
    const out = { have, list: [], byName: {}, lines: 0, stocked: 0, short: 0, canPack: 0 };
    S.kit.forEach(k => {
      const par = Math.max(0, Number(k.count) || 0);
      if (!k.name || par < 1) return;
      const h = have[k.name] || 0, need = Math.max(0, par - h), pockets = pocketCount(k.name);
      const e = Object.assign({}, k, { par, have: h, need, pockets });
      out.list.push(e); out.byName[k.name] = e;
      out.lines++;
      if (!need) out.stocked++;
      out.short += need;
      out.canPack += Math.min(need, pockets);
    });
    return out;
  }

  /* ─────────────── layout (compartments → slot numbers) ─────────────── */
  function layoutFor(n) {
    let src = arr(S.layout).filter(c => c && Number(c.slots) > 0 && ['main', 'lid', 'left', 'right'].includes(c.place));
    if (!src.length) src = DEF_LAYOUT;
    const out = [];
    let next = 1;
    src.forEach(c => {
      const k = Math.max(0, Math.min(Math.floor(Number(c.slots)), n - next + 1));
      if (k < 1) return;
      const list = [];
      for (let i = 0; i < k; i++) list.push(next + i);
      next += k;
      out.push({ id: c.id || c.place, place: c.place, cols: Number(c.cols) || 3, label: c.label || t(`cmp_${c.id || c.place}`, PLACE_FB[c.place]), list });
    });
    if (next <= n) {
      let m = out.find(c => c.place === 'main');
      if (!m) { m = { id: 'main', place: 'main', cols: 3, label: t('cmp_main', PLACE_FB.main), list: [] }; out.unshift(m); }
      for (let s = next; s <= n; s++) m.list.push(s);
    }
    return out;
  }

  /* ─────────────── rendering: bag ─────────────── */
  function tileHTML(it, slot, cmp, par, ghostOf) {
    const tall = cmp.place === 'left' || cmp.place === 'right';
    const extra = cmp.place === 'main' ? '<i class="loop"></i>' : tall ? '<i class="flap"><i></i></i>' : '';
    if (!it && ghostOf) {
      const g = ghostOf;
      return `<div class="mb-slot ghost${g.pockets ? '' : ' none'}${tall ? ' tall' : ''}" data-ghost="${esc(g.name)}" data-side="bag" data-slot="${slot}">
        ${extra}<img src="${imgOf(g)}" alt="" draggable="false" onerror="${imgFallback}">
        <b class="q">0<i>/${esc(g.par)}</i></b><span class="nm">${esc(g.label || g.name)}</span></div>`;
    }
    if (!it) return `<div class="mb-slot empty${tall ? ' tall' : ''}" data-side="bag" data-slot="${slot}">${extra}<span class="sn">${slot}</span></div>`;
    const p = par && par.byName[it.name] && (!it.meta || !it.meta.length) ? par.byName[it.name] : null;
    const parBar = p ? `<i class="par ${p.need ? 'lo' : 'ok'}" style="--p:${clamp(p.have / p.par, 0, 1).toFixed(3)}"></i>` : '';
    // a stack reads as a stack: copies peek out behind the item
    const n = Number(it.count) || 0;
    const stack = tall ? '' : (n >= 2 ? `<img class="stk s1" src="${imgOf(it)}" alt="" draggable="false" onerror="${imgFallback}">` : '')
      + (!tall && n >= 6 ? `<img class="stk s2" src="${imgOf(it)}" alt="" draggable="false" onerror="${imgFallback}">` : '');
    return `<div class="mb-slot${tall ? ' tall' : ''}${p && p.need ? ' short' : ''}" data-item data-side="bag" data-slot="${it.slot}" data-name="${esc(it.name)}">
      ${extra}${stack}<img class="main" src="${imgOf(it)}" alt="" draggable="false" onerror="${imgFallback}">
      <b class="q">${esc(it.count)}</b>
      <span class="nm">${esc(it.label)}</span>${parBar}
    </div>`;
  }

  function cmpHTML(c, bySlot, par, ghosts) {
    const used = c.list.filter(s => bySlot[s]).length;
    const tiles = c.list.map(s => tileHTML(bySlot[s], s, c, par, ghosts[s])).join('');
    const tone = used >= c.list.length ? ' full' : '';
    return `<div class="mb-cmp ${c.place}" data-cmp="${esc(c.id)}">
      <header class="cmp-h"><b>${esc(c.label)}</b><span class="mb-mono${tone}">${used}<i>/${c.list.length}</i></span></header>
      <div class="cmp-g" style="--cols:${c.place === 'lid' ? Math.min(4, c.list.length) : c.place === 'main' ? clamp(c.cols, 1, 4) : 1}">${tiles}</div>
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
    const [kx, ky] = pt(60, 58, 40, p);
    const knob = p > 0.002 ? `<circle class="kn ${tone}" cx="${kx.toFixed(1)}" cy="${ky.toFixed(1)}" r="3.4"/>` : '';
    return `<path class="trk" d="${arcD(60, 58, 40, 0, 1)}"/>${zone}${fill}${knob}<g class="ticks">${ticks}</g>`;
  }

  function renderBag() {
    const b = S.bag;
    if (!b) return;
    if (!S.styling) R.bagCard.style.setProperty('--bc', b.hex || '#08afa2');
    R.bagT.textContent = b.name || t('ui_bag_default', 'Medical bag');
    const who = b.mine ? t('ui_yours', 'Yours') : t('ui_owner', 'Owner %s', b.owner || '?');
    R.bagS.innerHTML = `${esc(b.id)} · ${esc(who)}${b.locked ? ` · <em>${icon('lock')}${esc(t('ui_locked', 'Locked'))}</em>` : ''}${b.held ? ` · <em>${icon('hand')}${esc(t('ui_in_hand', 'In your hand'))}</em>` : ''}`;
    R.lock.style.display = b.canLock ? '' : 'none';
    R.lock.innerHTML = icon(b.locked ? 'lock' : 'unlock');
    R.lock.classList.toggle('on', !!b.locked);
    R.lock.title = b.locked ? t('ui_unlock', 'Unlock the bag') : t('ui_lock', 'Lock the bag');
    R.sty.style.display = b.canStyle && S.colours.length ? '' : 'none';

    const items = b.items || [];
    const max = b.maxWeight || 18000;
    const p = clamp(max > 0 ? (b.weight || 0) / max : 0, 0, 1);
    R.loadSvg.innerHTML = loadDial(p);
    R.loadV.textContent = `${Math.round(p * 100)}`;
    R.loadV.className = loadTone(p);
    R.loadU.textContent = '%';
    const n = Math.max(b.slots || 20, ...items.map(i => i.slot));
    const units = items.reduce((a, i) => a + (Number(i.count) || 0), 0);
    const sTone = items.length >= n ? 'red' : items.length >= n * 0.8 ? 'amber' : '';
    const par = parInfo();
    const rows = [
      [t('ui_load', 'Load'), `${kg(b.weight || 0)}<i> / ${kg(max)} ${esc(t('ui_kg', 'kg'))}</i>`, loadTone(p) || 'teal'],
      [t('ui_slots_l', 'Slots'), `${items.length}<i> / ${n}</i>`, sTone],
      [t('ui_units', 'Units'), `${units}`, ''],
    ];
    if (par.lines) rows.push([t('ui_par', 'Par'), `${par.stocked}<i> / ${par.lines} ${esc(t('ui_par_lines', 'stocked'))}</i>`, par.stocked >= par.lines ? 'teal' : 'amber']);
    R.inst.innerHTML = rows.map(([l, v, tone]) => `<li class="${tone}"><span>${esc(l)}</span><b>${v}</b></li>`).join('');

    // compartments
    const L = layoutFor(n);
    const bySlot = {};
    items.forEach(it => { bySlot[it.slot] = it; });
    // shadow outlines: supplies of the restock list that are not in the bag at all
    const ghosts = {};
    const missing = par.list.filter(e => e.have === 0);
    const order = ['main', 'left', 'right', 'lid'];
    const free = [];
    order.forEach(pl => L.filter(c => c.place === pl).forEach(c => c.list.forEach(s => { if (!bySlot[s]) free.push(s); })));
    missing.forEach((e, i) => { if (free[i] !== undefined) ghosts[free[i]] = e; });

    const of = pl => L.filter(c => c.place === pl).map(c => cmpHTML(c, bySlot, par, ghosts)).join('');
    const lid = of('lid'), left = of('left'), right = of('right'), main = of('main');
    const cols = [left ? '78px' : null, 'minmax(0,1fr)', right ? '78px' : null].filter(Boolean).join(' ');
    const opening = R.open.dataset.fresh === '1';
    R.open.dataset.fresh = '';
    R.open.innerHTML = `
      ${lid ? `<div class="mb-lid"><div class="shell"><div class="inner mesh">${lid}</div></div></div>
      <div class="mb-hinge"><i class="teeth"></i>${pullHTML('l')}${pullHTML('r')}</div>` : ''}
      <div class="mb-body"><div class="shell"><div class="inner" style="grid-template-columns:${cols}">
        ${left ? `<div class="mb-col">${left}</div>` : ''}<div class="mb-col">${main}</div>${right ? `<div class="mb-col">${right}</div>` : ''}
      </div><i class="reflect"></i></div></div>
      <div class="mb-bnone"></div>`;
    if (opening) {
      R.open.classList.remove('opening'); void R.open.offsetWidth; R.open.classList.add('opening');
      R.open.querySelectorAll('.mb-slot:not(.empty)').forEach((s, i) => s.style.setProperty('--d', `${160 + i * 28}ms`));
      setTimeout(() => R.open.classList.remove('opening'), 1500);
    }
    // empty bag: a short note, unless the shadow outlines already show what goes where
    const none = R.open.querySelector('.mb-bnone');
    const showNone = !items.length && !Object.keys(ghosts).length;
    none.textContent = showNone ? t('ui_bag_empty', 'Nothing packed yet. Click an item in your pockets to put it in.') : '';
    none.classList.toggle('on', showNone);
    R.emp.disabled = !items.length;
    R.kit.style.display = S.kitOn ? '' : 'none';
    const em = R.kit.querySelector('em');
    if (par.lines) {
      em.textContent = par.canPack ? `+${par.canPack}` : (par.short ? t('ui_short', '%d short', par.short) : t('ui_full_par', 'At par'));
      em.className = par.canPack ? 'go' : par.short ? 'lo' : 'ok';
      R.kit.disabled = !par.canPack;
    } else { em.textContent = ''; em.className = ''; R.kit.disabled = false; }
  }

  function rowHTML(it, par) {
    const dis = it.allowed === false;
    const p = !dis && par.byName[it.name];
    const need = p && p.need ? `<em class="need">${icon('arrow-r')}${esc(t('ui_need', 'Bag needs %d', p.need))}</em>` : '';
    return `<div class="mb-row${dis ? ' dis' : ''}${need ? ' wanted' : ''}" data-item data-side="me" data-slot="${it.slot}" data-name="${esc(it.name)}">
      <span class="th"><img src="${imgOf(it)}" alt="" draggable="false" onerror="${imgFallback}"></span>
      <span class="tx"><b>${esc(it.label)}</b><small>${dis ? esc(t('ui_stays', 'Stays in your pockets')) : `${esc(catLabel(it.cat))} · ${esc(grams(Number(it.weight) || 0))}`}${need}</small></span>
      <span class="q">×${esc(it.count)}</span>
      <span class="go">${icon(dis ? 'ban' : 'chev-r')}</span>
    </div>`;
  }

  function renderMe() {
    const m = S.me;
    if (!m) return;
    const all = m.items || [];
    const par = parInfo();
    const list = S.filter ? all.filter(it => `${it.label} ${it.name}`.toLowerCase().includes(S.filter)) : all;
    const sorted = [...list.filter(i => i.allowed !== false), ...list.filter(i => i.allowed === false)];
    R.list.innerHTML = sorted.map(it => rowHTML(it, par)).join('');
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
      const major = i % 8 === 0;
      if (!major && i / 24 > NUM_END) continue; // fine ticks only along the count arc; the shares get one notch each
      const [a, b] = pt(70, 66, 60, i / 24), [c, d] = pt(70, 66, major ? 54 : 57, i / 24);
      ticks += `<line x1="${a.toFixed(1)}" y1="${b.toFixed(1)}" x2="${c.toFixed(1)}" y2="${d.toFixed(1)}"/>`;
    }
    const [kx, ky] = pt(70, 66, 47, f);
    R.dialSvg.innerHTML = `<path class="trk" d="${arcD(70, 66, 47, 0, 1)}"/>
      <path class="fill" d="${arcD(70, 66, 47, 0, Math.max(f, 0.004))}"/>
      <g class="ticks">${ticks}</g>
      <circle class="knob" cx="${kx.toFixed(1)}" cy="${ky.toFixed(1)}" r="5.5"/>`;
    const share = shareWord();
    R.pre.innerHTML = PRESETS.map((v, i) => {
      const [x, y] = pt(70, 66, 70, i / 3);
      const on = (v === 'stack' && S.stack) || (v === 'half' && S.half) || (!share && v === S.qty);
      const label = v === 'stack' ? t('ui_stack', 'Stack') : v === 'half' ? t('ui_half', 'Half') : v;
      return `<button data-preset="${v}" class="${on ? 'on' : ''}" style="left:${(x / 140 * 100).toFixed(2)}%;top:${(y / 124 * 100).toFixed(2)}%">${esc(label)}</button>`;
    }).join('');
    R.odoHost.style.display = share ? 'none' : '';
    R.stk.style.display = share ? '' : 'none';
    R.stk.textContent = share || '';
    if (!share) odo.set(String(S.qty));
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
      NZA.audio.tick();
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
        <span class="tx"><b>${esc(e.label || e.name)}</b><small>${e.by ? `<i class="av">${esc(initials(e.by))}</i>` : ''}${esc(who)}</small></span><span class="d">${esc(d)}</span></li>`;
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
  // a share notch is set (half / stack): its word, else null (a plain count)
  function shareWord() { return S.stack ? t('ui_stack', 'Stack') : S.half ? t('ui_half', 'Half') : null; }
  function setQty(v) {
    if (v === 'stack' || v === 'half') { S.stack = v === 'stack'; S.half = v === 'half'; }
    else { S.stack = false; S.half = false; S.qty = clamp(Math.floor(Number(v) || 1), 1, 999); }
    renderQty(); NZA.audio.tick();
  }
  // + − walk the dial: count ↔ … ; stack −→ half −→ the last count, half +→ stack
  function step(d) {
    if (S.stack) { if (d < 0) { S.stack = false; S.half = true; } }
    else if (S.half) { S.half = false; S.stack = d > 0; }
    else S.qty = clamp(S.qty + d, 1, 999);
    renderQty(); NZA.audio.tick();
  }
  // count to send for a click on a stack of n
  const curCount = n => (S.stack ? 'all' : S.half ? halfOf(n) : S.qty);

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
    if (S.drag || S.pour || S.mode !== 'bag') return;
    const s = e.target.closest && e.target.closest('[data-item],[data-ghost]');
    if (!s || s === S.tipFor) return;
    showTip(s);
  }
  function placeTip(node, side) {
    R.tip.classList.toggle('lft', side === 'me');
    const p = posIn(node), W = R.tip.offsetWidth || 280;
    const col = side === 'bag' ? posIn(R.right) : posIn(R.left);
    const x = side === 'bag' ? col.x - W - 14 : col.x + col.w + 14;
    R.tip.style.left = `${x}px`;
    R.tip.classList.add('on');
    const H = R.tip.offsetHeight, maxY = A.el.clientHeight - H - 16;
    R.tip.style.top = `${clamp(p.y + p.h / 2 - 40, 16, Math.max(16, maxY))}px`;
  }
  function ghostTip(node) {
    const par = parInfo();
    const g = par.byName[node.dataset.ghost];
    if (!g) return hideTip();
    S.tipFor = node;
    R.tip.innerHTML = `
      <div class="th"><span class="ti ghost"><img src="${imgOf(g)}" alt="" onerror="${imgFallback}"></span>
        <div><b>${esc(g.label || g.name)}</b><span class="cat amber">${esc(t('ui_missing', 'Missing from the bag'))}</span></div></div>
      <p class="d">${esc(t('ui_ghost_d', 'The outline shows where this supply belongs. The bag should carry %d.', g.par))}</p>
      <ul>
        <li><span>${esc(t('ui_par_level', 'Par level'))}</span><b>${esc(g.par)}</b></li>
        <li><span>${esc(t('ui_in_pockets', 'In your pockets'))}</span><b>${esc(g.pockets)}</b></li>
      </ul>
      ${g.pockets ? `<div class="hk"><kbd>Click</kbd><span>${esc(t('ui_ghost_pack', 'Pack %d from your pockets', Math.min(g.need, g.pockets)))}</span></div>`
        : `<div class="no amber">${icon('alert')}${esc(t('ui_ghost_none', 'You carry none. Restock at the hospital'))}</div>`}`;
    placeTip(node, 'bag');
  }
  function showTip(node) {
    if (!node) return;
    if (node.dataset.ghost) return ghostTip(node);
    const side = node.dataset.side, it = findItem(side, node.dataset.slot);
    if (!it) return hideTip();
    S.tipFor = node;
    const per = Number(it.weight) || 0;
    const dis = side === 'me' && it.allowed === false;
    const par = parInfo();
    const p = (!it.meta || !it.meta.length) ? par.byName[it.name] : null;
    const rows = [
      [t('ui_weight', 'Weight'), `${esc(grams(per))} <em>${esc(t('ui_each', 'each'))}</em> · ${esc(grams(per * it.count))} <em>${esc(t('ui_total', 'total'))}</em>`],
      [t('ui_count', 'Count'), `× ${esc(it.count)}`],
    ];
    if (p && !dis) rows.push([t('ui_par_level', 'Par level'), `${esc(p.have)} / ${esc(p.par)}${p.need ? ` <em class="lo">· ${esc(t('ui_short', '%d short', p.need))}</em>` : ` <em class="ok">· ${esc(t('ui_full_par', 'At par'))}</em>`}`]);
    (it.meta || []).filter(m => m.k).forEach(m => rows.push([keyLabel(m.k), esc(m.v)]));
    const notes = (it.meta || []).filter(m => !m.k).map(m => `<p class="md">${esc(m.v)}</p>`).join('');
    const where = side === 'bag' ? t('ui_tip_bag', 'to your pockets') : t('ui_tip_me', 'into the bag');
    R.tip.innerHTML = `
      <div class="th"><span class="ti"><img src="${imgOf(it)}" alt="" onerror="${imgFallback}"></span>
        <div><b>${esc(it.label)}</b><span class="cat">${esc(catLabel(it.cat))}</span></div></div>
      ${it.desc ? `<p class="d">${esc(it.desc)}</p>` : ''}${notes}
      <ul>${rows.map(([l, v]) => `<li><span>${esc(l)}</span><b>${v}</b></li>`).join('')}</ul>
      ${dis ? `<div class="no">${icon('ban')}${esc(t('ui_stays', 'Stays in your pockets'))}</div>`
            : `<div class="hk"><kbd>Click</kbd><span>${esc(S.stack ? t('ui_stack', 'Stack') : `${S.half ? halfOf(it.count) : S.qty}×`)} ${esc(where)}</span></div>`}`;
    placeTip(node, side);
  }
  function hideTip() { S.tipFor = null; if (R.tip) R.tip.classList.remove('on'); }

  /* ─────────────── mouse: click / hold-to-pour / drag ─────────────── */
  const POUR_DELAY = 320;
  function shake(node) { node.classList.remove('shake'); void node.offsetWidth; node.classList.add('shake'); NZA.audio.click(260); }
  function onDown(e) {
    if (!S.on || S.mode !== 'bag') return;
    const gh = e.target.closest && e.target.closest('[data-ghost]');
    if (gh && e.button === 0) { e.preventDefault(); packGhost(gh); return; }
    const node = e.target.closest && e.target.closest('[data-item]');
    if (!node || (e.button !== 0 && e.button !== 2)) return;
    e.preventDefault();
    const it = findItem(node.dataset.side, node.dataset.slot);
    if (!it) return;
    S.press = { el: node, side: node.dataset.side, slot: Number(node.dataset.slot), name: node.dataset.name, x: e.clientX, y: e.clientY, button: e.button, shift: e.shiftKey, max: it.count, dis: node.dataset.side === 'me' && it.allowed === false };
    if (e.button === 0 && !e.shiftKey && !S.press.dis) {
      const pr = S.press;
      pr.timer = setTimeout(() => { if (S.press === pr && !S.drag) startPour(pr); }, POUR_DELAY);
    }
  }
  // click on a shadow outline: pack that supply from your pockets up to its par level
  function packGhost(node) {
    const par = parInfo();
    const g = par.byName[node.dataset.ghost];
    if (!g) return;
    const src = pocketsOf(g.name).filter(i => !i.meta || !i.meta.length).sort((a, b) => b.count - a.count)[0];
    if (!src || !g.need) { shake(node); return; }
    hideTip();
    const row = R.list.querySelector(`.mb-row[data-slot="${src.slot}"]`);
    move({ dir: 'in', from: src.slot, to: Number(node.dataset.slot), count: Math.min(g.need, src.count), name: g.name }, row || node);
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
    A.el.querySelectorAll('.mb-cmp.over').forEach(x => x.classList.remove('over'));
    R.bagCard.classList.toggle('dropzone', !!(under && under.closest && under.closest('.mb-bag')) && S.drag.side === 'me');
    R.pk.classList.toggle('dropzone', !!(under && under.closest && under.closest('.mb-pk')) && S.drag.side === 'bag');
    if (slot && slot !== S.drag.el) {
      slot.classList.add('drop');
      const c = slot.closest('.mb-cmp');
      if (c) c.classList.add('over');
    }
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
    if (p.dis) return shake(p.el);
    doMove(p, p.button === 2 ? 1 : (p.shift || e.shiftKey ? 'all' : curCount(p.max)));
  }
  function doMove(p, count) {
    move(p.side === 'me' ? { dir: 'in', from: p.slot, count, name: p.name } : { dir: 'out', from: p.slot, count, name: p.name }, p.el);
  }
  function startDrag(p) {
    const it = findItem(p.side, p.slot);
    if (!it) return;
    hideTip();
    S.drag = { side: p.side, slot: p.slot, name: p.name, el: p.el, shift: p.shift, max: it.count };
    p.el.classList.add('lifted');
    A.el.classList.add('dragging');
    ghost = document.createElement('div');
    ghost.className = 'mb-ghost';
    const n = p.shift || S.stack ? it.count : Math.min(S.half ? halfOf(it.count) : S.qty, it.count);
    ghost.innerHTML = `<img src="${imgOf(it)}" alt="" onerror="${imgFallback}"><b>${esc(n)}</b>`;
    ghost.style.setProperty('--z', String(NZA.zoom || 1));
    ghost.style.left = `${p.x}px`; ghost.style.top = `${p.y}px`;
    document.body.appendChild(ghost);
    NZA.audio.click(520);
  }
  function clearDrop() {
    A.el.querySelectorAll('.mb-slot.drop').forEach(x => x.classList.remove('drop'));
    A.el.querySelectorAll('.mb-cmp.over').forEach(x => x.classList.remove('over'));
    R.bagCard.classList.remove('dropzone'); R.pk.classList.remove('dropzone');
    A.el.classList.remove('dragging');
  }
  function endDrag(e) {
    const d = S.drag;
    S.drag = null;
    if (ghost) { ghost.remove(); ghost = null; }
    d.el.classList.remove('lifted');
    clearDrop();
    const under = document.elementFromPoint(e.clientX, e.clientY);
    if (!under || !under.closest) return;
    const count = d.shift || e.shiftKey ? 'all' : curCount(d.max);
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
    f.innerHTML = `<img src="${imgOf(m)}" alt="" onerror="${imgFallback}"><b>${m.dir === 'out' ? '−' : '+'}${esc(m.count)}</b><i class="trail"></i>`;
    R.fx.appendChild(f);
    const lift = Math.min(220, Math.abs(x1 - x0) * 0.22 + 40);
    const mx = (x0 + x1) / 2, my = Math.min(y0, y1) - lift;
    const dir = x1 >= x0 ? 1 : -1;
    const anim = f.animate([
      { transform: `translate(${x0}px,${y0}px) scale(.7) rotate(0deg)`, opacity: 0 },
      { transform: `translate(${(x0 + mx) / 2}px,${(y0 + my) / 2}px) scale(1.05) rotate(${dir * 6}deg)`, opacity: 1, offset: 0.25 },
      { transform: `translate(${mx}px,${my}px) scale(1) rotate(${dir * 10}deg)`, opacity: 1, offset: 0.55 },
      { transform: `translate(${x1}px,${y1}px) scale(.55) rotate(0deg)`, opacity: 0.2 },
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
  const slotNode = s => R.open.querySelector(`.mb-slot[data-slot="${s}"]`);
  function move(data, fromEl, toEl) {
    if (!S.on || S.mode !== 'bag') return;
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
        fly(m, fromBox, (it && slotNode(it.slot)) || R.bagCard);
      } else if (m.dir === 'out') {
        fly(m, fromBox, R.list.querySelector(`.mb-row[data-name="${cssEsc(m.name)}"]`) || R.pk);
      } else if (toEl) {
        land(slotNode(data.to));
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
        const src = m.dir === 'in' ? R.pk : R.bagCard;
        let dst = m.dir === 'in' ? R.bagCard : R.pk;
        if (m.dir === 'in') { const it = ((S.bag && S.bag.items) || []).find(x => x.name === m.name); if (it && slotNode(it.slot)) dst = slotNode(it.slot); }
        const b = posIn(src);
        fly(m, { x: b.x + b.w / 2 - 20, y: b.y + 90, w: 40, h: 40 }, dst);
      }, i * 110));
      if (res.msg) NZA.toast({ title: bagTitle(), message: res.msg, type: 'success', duration: 2600, icon: act === 'lock' ? (S.bag.locked ? 'lock' : 'unlock') : act === 'style' ? 'palette' : 'check' });
      if (act === 'sort') { R.open.classList.remove('sorted'); void R.open.offsetWidth; R.open.classList.add('sorted'); }
    });
  }

  /* ═══════════════════════════ ZIP-UP CARD (body bag) ═══════════════════════════ */
  const TEETH = 37, TX0 = 12, TDX = 7.6, SX0 = 8, SX1 = 291;
  function zipSvg() {
    let teeth = '';
    for (let i = 0; i < TEETH; i++) {
      const x = TX0 + i * TDX;
      teeth += `<g class="tp" data-i="${i}"><rect class="up" x="${x.toFixed(1)}" y="9" width="4.6" height="8" rx="1.2"/><rect class="dn" x="${(x + 3.9).toFixed(1)}" y="29" width="4.6" height="8" rx="1.2"/></g>`;
    }
    return `<defs><linearGradient id="mbzt" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#d5d8de"/><stop offset=".5" stop-color="#8e939b"/><stop offset="1" stop-color="#5d6168"/></linearGradient>
        <linearGradient id="mbzp" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#eceef1"/><stop offset="1" stop-color="#7d828a"/></linearGradient></defs>
      <rect class="tape" x="0" y="2" width="302" height="13" rx="3"/><rect class="tape" x="0" y="31" width="302" height="13" rx="3"/>
      <rect class="gap" x="6" y="17" width="290" height="12"/><rect class="stop" x="297" y="13" width="5" height="20" rx="1.5"/>
      <g class="teeth">${teeth}</g>
      <g class="slider"><rect x="-7" y="11" width="22" height="24" rx="5" fill="url(#mbzp)"/><rect x="-3" y="15" width="14" height="16" rx="3" fill="#2a2d33"/>
        <rect class="tab" x="9" y="18" width="30" height="10" rx="5"/><circle cx="33" cy="23" r="2.2" fill="#15171b"/></g>`;
  }
  function zipSet(p) {
    const z = S.zip;
    if (!z) return;
    p = clamp(p, 0, 1);
    z.p = p;
    const sx = SX0 + p * (SX1 - SX0);
    let closed = 0;
    while (closed < TEETH && TX0 + closed * TDX < sx + 3) closed++;
    if (p <= 0) closed = 0;
    if (closed !== z.closed) {
      z.closed = closed;
      R.zsvg.querySelectorAll('.tp').forEach((g, i) => g.classList.toggle('c', i < closed));
    }
    const sl = R.zsvg.querySelector('.slider');
    if (sl) sl.setAttribute('transform', `translate(${sx.toFixed(1)} 0)`);
    zipOdo.set(String(Math.round(p * 100)));
  }
  function zipRender() {
    const z = S.zip;
    R.zsp.innerHTML = z.steps.map((s, i) => `<li class="${i < z.i ? 'done' : i === z.i ? 'cur' : ''}"><i>${i < z.i ? icon('check') : `<b>${i + 1}</b>`}</i><span>${esc(s.label)}</span></li>`).join('');
  }
  function zipStep(d) {
    const z = S.zip;
    if (!z) return;
    const i = clamp(Math.floor(Number(d.i) || 1) - 1, 0, z.steps.length - 1);
    z.i = i;
    z.from = z.steps.slice(0, i).reduce((a, s) => a + s.share, 0);
    z.span = z.steps[i].share;
    z.t0 = performance.now();
    z.ms = Math.max(200, Number(d.ms) || 1000);
    zipRender();
    NZA.audio.click(820);
    cancelAnimationFrame(z.raf);
    const tick = () => {
      if (S.zip !== z) return;
      const f = clamp((performance.now() - z.t0) / z.ms, 0, 1);
      zipSet(z.from + z.span * f);
      if (f < 1) z.raf = requestAnimationFrame(tick);
    };
    z.raf = requestAnimationFrame(tick);
  }
  function zipDone() {
    const z = S.zip;
    if (!z) return;
    cancelAnimationFrame(z.raf);
    z.i = z.steps.length;
    zipRender();
    zipSet(1);
    R.zip.classList.add('done');
    R.zt.textContent = t('zip_sealed', 'Sealed');
    NZA.audio.success();
  }
  function openZip(d) {
    const zd = d.zip || {};
    let steps = arr(zd.steps).map(s => ({ label: String((s && s.label) || ''), share: Math.max(0.01, Number(s && s.share) || 0) }));
    if (!steps.length) steps = [{ label: t('bb_progress', 'Body bag'), share: 1 }];
    const sum = steps.reduce((a, s) => a + s.share, 0);
    steps.forEach(s => { s.share /= sum; });
    S.zip = { steps, i: 0, p: 0, closed: -1, raf: 0 };
    R.zip.classList.remove('done');
    R.zk.textContent = t('zip_kicker', 'Body bag');
    R.zt.textContent = t('zip_closing', 'Closing');
    R.zav.textContent = initials(zd.name);
    R.zn.textContent = zd.name || t('unknown', 'Unknown person');
    R.zs.textContent = zd.sub || t('zip_sub', 'Deceased · handle with care');
    R.zkey.innerHTML = `<kbd>${esc(zd.key || 'X')}</kbd>${esc(zd.keyLabel || t('zip_stop', 'Stop'))}`;
    R.zsvg.innerHTML = zipSvg();
    zipRender();
    zipSet(0);
  }

  /* ═══════════════════════════ TOE TAG ═══════════════════════════ */
  function openTag(d) {
    const g = d.tag || {};
    const field = (l, v, cls) => `<div class="tf ${cls || ''}"><span>${esc(l)}</span><b>${esc(v || '—')}</b></div>`;
    const sexAge = [g.sex === 'f' ? t('tag_f', 'F') : g.sex === 'm' ? t('tag_m', 'M') : null, g.age ? `${g.age}` : null].filter(Boolean).join(' · ');
    R.tagw.innerHTML = `
      <svg class="string" viewBox="0 0 220 150" aria-hidden="true"><path d="M6 148 C 24 104, 104 118, 128 64 S 188 10, 216 6"/></svg>
      <div class="tag">
        <span class="eyelet"><i></i></span>
        <div class="tg-hd"><b>${esc(t('tag_head', 'Deceased · identification'))}</b><span class="no">${esc(g.id || '')}</span></div>
        <div class="tg-name"><span>${esc(t('tag_name', 'Name'))}</span><b class="ink">${esc(g.name || t('unknown', 'Unknown person'))}</b></div>
        <div class="tg-grid">
          ${field(t('tag_tod', 'Time of death'), [g.date, g.tod].filter(Boolean).join('  '), 'ink')}
          ${field(t('tag_sexage', 'Sex · age'), sexAge, 'ink')}
          ${field(t('tag_cause', 'Cause'), g.cause || t('tag_unknown_cause', 'Undetermined'), 'ink wide')}
          ${field(t('tag_where', 'Found at'), g.where, 'ink wide')}
          ${field(t('tag_by', 'Bagged by'), g.by, 'ink')}
          ${field(g.call ? t('tag_call', 'Call') : t('tag_blood', 'Blood type'), g.call || g.blood, 'ink')}
        </div>
        <div class="tg-ft"><span class="stamp">${esc(g.kind === 'npc' ? t('tag_stamp_npc', 'Unclaimed') : t('tag_stamp', 'Hold for ID'))}</span><span class="perf"></span></div>
      </div>`;
    R.tagw.classList.remove('out'); void R.tagw.offsetWidth; R.tagw.classList.add('in');
    clearTimeout(S.tagTimer);
    const ms = Number(d.ms) || 0;
    if (ms > 600) S.tagTimer = setTimeout(() => { R.tagw.classList.add('out'); }, ms - 400);
    NZA.audio.click(480);
  }

  /* ─────────────── app ─────────────── */
  function setMode(m) {
    S.mode = m;
    A.el.classList.toggle('m-bag', m === 'bag');
    A.el.classList.toggle('m-zip', m === 'zip');
    A.el.classList.toggle('m-tag', m === 'tag');
  }
  function resetBagUI() {
    hideTip();
    if (S.pour) endPour();
    if (ghost) { ghost.remove(); ghost = null; }
    S.drag = null; S.press = null;
    clearDrop();
    A.el.querySelectorAll('.nza-modal-wrap').forEach(m => m.remove());
    if (R.fx) R.fx.innerHTML = '';
  }

  A = NZA.app('medbag', {
    camInput: false,
    init(el) { build(el); texts(); renderQty(); renderLog(); },
    open(d) {
      loc = Object.assign({}, loc, d.locale || {});
      texts();
      resetBagUI();
      if (S.zip) { cancelAnimationFrame(S.zip.raf); S.zip = null; }
      clearTimeout(S.tagTimer);
      const mode = d.mode === 'zip' || d.mode === 'tag' ? d.mode : 'bag';
      setMode(mode);
      S.on = true;
      if (mode === 'zip') return openZip(d);
      if (mode === 'tag') return openTag(d);
      S.bag = normBag(d.bag); S.me = normMe(d.me); S.colours = arr(d.colours); S.layout = d.layout || null;
      S.kit = Array.isArray(d.kit) || (d.kit && typeof d.kit === 'object') ? arr(d.kit) : [];
      S.kitOn = S.kit.length > 0 || d.kit === true;
      S.filter = ''; R.filter.value = ''; S.log = []; S.styling = false; S.pickColour = null;
      R.bagCard.classList.remove('styling'); R.style.innerHTML = ''; R.sty.classList.remove('on');
      R.open.dataset.fresh = '1';
      renderAll();
    },
    close() {
      S.on = false;
      resetBagUI();
      if (S.zip) { cancelAnimationFrame(S.zip.raf); S.zip = null; }
      clearTimeout(S.tagTimer);
    },
    msg: {
      sync(d) {
        if (S.mode !== 'bag' || !d || !d.bag) return;
        S.bag = normBag(d.bag); renderBag(); renderMe();
        if (d.moved) logMove(d.moved, d.by);
        if (S.tipFor && !document.body.contains(S.tipFor)) hideTip();
      },
      me(d) {
        if (S.mode !== 'bag' || !d || !d.me || S.drag || S.busy || S.pour) return;
        S.me = normMe(d.me); renderMe(); renderBag();
        if (S.tipFor && !document.body.contains(S.tipFor)) hideTip();
      },
      zipStep(d) { if (S.mode === 'zip') zipStep(d || {}); },
      zipDone() { if (S.mode === 'zip') zipDone(); },
    },
    keys: {
      '1'(e) { if (S.mode !== 'bag' || typing(e)) return false; setQty(1); },
      '2'(e) { if (S.mode !== 'bag' || typing(e)) return false; setQty(3); },
      '3'(e) { if (S.mode !== 'bag' || typing(e)) return false; setQty('half'); },
      '4'(e) { if (S.mode !== 'bag' || typing(e)) return false; setQty('stack'); },
      '+'(e) { if (S.mode !== 'bag' || typing(e)) return false; step(1); },
      '='(e) { if (S.mode !== 'bag' || typing(e)) return false; step(1); },
      '-'(e) { if (S.mode !== 'bag' || typing(e)) return false; step(-1); },
      KeyF(e) { if (S.mode !== 'bag' || typing(e)) return false; R.filter.focus(); },
      Enter(e) {
        if (S.styling && typing(e)) { const b = R.style.querySelector('[data-style="save"]'); if (b) b.click(); return; }
        return false;
      },
      Escape() {
        if (S.mode === 'bag') {
          const modal = A.el.querySelector('.nza-modal-wrap');
          if (modal) { modal.remove(); return; }
          if (S.styling) { toggleStyle(false); return; }
          if (document.activeElement === R.filter && R.filter.value) { R.filter.value = ''; S.filter = ''; renderMe(); return; }
        }
        NZA.close('medbag');
      },
    },
    preview() { preview(); },
  });
  function typing(e) { return e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA'); }

  /* ═══════════════════════════ PREVIEW (browser only) ═══════════════════════════ */
  function preview() {
    const params = new URLSearchParams(location.search);
    const demo = params.get('demo');
    const img = n => `img/items/${n}.png`;

    if (demo === 'zip' || demo === 'zipdone') {
      NZA.demo('medbag', { mode: 'zip', zip: { name: 'Rafael Moreau', sub: 'Deceased 14:32 · Gunshot wound, chest', key: 'X',
        steps: [{ label: 'Unfold the bag beside the body', share: 0.3 }, { label: 'Roll the body in', share: 0.4 }, { label: 'Zip it closed', share: 0.3 }] } });
      if (demo === 'zipdone') { zipStep({ i: 3, ms: 200 }); setTimeout(zipDone, 260); } else { zipStep({ i: 2, ms: 2600 }); }
      return;
    }
    if (demo === 'tag' || demo === 'tagnpc') {
      NZA.demo('medbag', { mode: 'tag', ms: 0, tag: demo === 'tagnpc'
        ? { id: 'BB-Q7M2D', name: 'Unknown male', kind: 'npc', date: '14 Oct', tod: '22:07', cause: 'Fall from height · Head', where: 'Alta St, Pillbox Hill', by: 'D. Okafor', sex: 'm', age: 41, call: 'C-0042' }
        : { id: 'BB-7K2QF', name: 'Rafael Moreau', kind: 'player', date: '14 Oct', tod: '14:32', cause: 'Gunshot wound · Chest', where: 'Palomino Ave, La Mesa', by: 'Maya Reyes', sex: 'm', age: 34, blood: 'O-' } });
      return;
    }

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
      splint: 'Mouldable splint for a broken arm or leg.', saline_bag: 'Bag of 0.9% saline for infusion.', blood_bag: 'A labelled unit of donated blood.', gauze: 'Sterile gauze for packing deep wounds.',
      sterile_dressing: 'Sterile pad dressing for an open wound.', ice_pack: 'Instant cold pack for bruises and sprains.', foil_blanket: 'Keeps a patient warm on scene.' };
    const STACK = { blood_bag: 1, stethoscope: 1, ems_pager: 1 };
    const OWN = new Set(Object.keys(C));
    const COLOURS = [{ id: 'red', hex: '#e5484d', label: 'Red' }, { id: 'orange', hex: '#f08a24', label: 'Orange' }, { id: 'green', hex: '#2fb36b', label: 'Green' }, { id: 'magenta', hex: '#d23c9a', label: 'Magenta' }];
    const KIT = [['bandage', 10], ['gauze', 10], ['tourniquet', 4], ['sterile_dressing', 6], ['burn_dressing', 4], ['painkillers', 6], ['ice_pack', 2], ['splint', 2], ['foil_blanket', 2], ['iv_kit', 2], ['saline_bag', 2]]
      .map(([n, c]) => ({ name: n, label: L[n], image: img(n), count: c }));
    const LAYOUT = [
      { id: 'main', place: 'main', slots: 12, cols: 3, label: 'Main compartment' },
      { id: 'lid', place: 'lid', slots: 4, label: 'Lid pocket' },
      { id: 'left', place: 'left', slots: 2, label: 'Pouch L' },
      { id: 'right', place: 'right', slots: 2, label: 'Pouch R' },
    ];
    const mk = (name, count, slot, meta) => ({ slot, name, label: L[name] || name, image: img(['phone', 'water', 'lockpick'].includes(name) ? 'nza_unknown' : name), count, weight: W[name] || 100, desc: D[name], cat: C[name] || 'other', meta, allowed: OWN.has(name) });
    const bag = { id: 'MB-7K2QF', name: 'Trauma', colour: 'red', hex: '#e5484d', owner: 'Maya Reyes', mine: true, locked: false, canLock: true, canStyle: true, slots: 20, maxWeight: 18000, items: [
      mk('bandage', 18, 1), mk('gauze', 7, 2), mk('tourniquet', 4, 3), mk('painkillers', 12, 4), mk('burn_dressing', 4, 5), mk('iv_kit', 1, 6),
      mk('morphine', 2, 7), mk('adrenaline', 3, 8),
      mk('splint', 2, 13), mk('cervical_collar', 1, 14),
      mk('saline_bag', 2, 17), mk('blood_bag', 1, 19, [{ k: 'type', v: 'O-' }, { k: 'ml', v: '450' }, { k: 'serial', v: 'LS-04172' }]),
    ] };
    const me = { maxWeight: 60000, items: [
      mk('blood_bag', 1, 1, [{ k: 'type', v: 'A+' }, { k: 'ml', v: '450' }, { k: 'serial', v: 'LS-04188' }]), mk('ems_pager', 1, 2), mk('stethoscope', 1, 3), mk('morphine', 3, 4),
      mk('bandage', 9, 5), mk('sterile_dressing', 6, 6), mk('foil_blanket', 2, 7), mk('gauze', 5, 8), mk('adrenaline', 4, 9), mk('suture_kit', 2, 10),
      mk('txa', 3, 11), mk('iv_kit', 2, 12), mk('pelvic_binder', 1, 13), mk('oxygen_mask', 2, 14), mk('medikit', 1, 15),
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
        if (n < 1) return reply({ ok: false, msg: 'Too heavy. The bag can hold 18.0 kg' });
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
        KIT.forEach(k => {
          const have = bag.items.filter(i => i.name === k.name && !i.meta).reduce((a, i) => a + i.count, 0);
          const it = me.items.find(i => i.name === k.name && !i.meta);
          const n = Math.min(Math.max(0, k.count - have), it ? it.count : 0);
          if (n > 0) { const got = addToBag(it, n); it.count -= got; if (it.count <= 0) me.items.splice(me.items.indexOf(it), 1); if (got) list.push(mv(it, got, 'in')); }
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

    if (demo === 'locked') Object.assign(bag, { mine: false, owner: 'P. Nair', locked: true, canLock: false, canStyle: false, name: null, colour: 'green', hex: '#2fb36b' });
    if (demo === 'empty' || demo === 'bare') bag.items.length = 0;
    if (demo === 'bare') KIT.length = 0;
    if (demo === 'full') {
      [['sterile_dressing', 6, 9], ['foil_blanket', 2, 10], ['ice_pack', 2, 11], ['txa', 4, 12], ['suture_kit', 2, 15], ['oxygen_mask', 2, 16], ['pelvic_binder', 1, 18], ['medikit', 2, 20]]
        .forEach(([n, c, s]) => bag.items.push(mk(n, c, s)));
      bag.items.find(i => i.name === 'gauze').count = 10;
      bag.items.find(i => i.name === 'iv_kit').count = 2;
      bag.items.find(i => i.name === 'painkillers').count = 30;
    }
    refresh();
    NZA.demo('medbag', { bag: clone(bag), me: clone(me), kit: KIT, colours: COLOURS, layout: LAYOUT });

    // a short history: our own moves and one by a colleague (arrives through 'sync')
    logMove({ name: 'splint', label: 'Splint', image: img('splint'), count: 1, dir: 'out' });
    logMove({ name: 'gauze', label: 'Gauze', image: img('gauze'), count: 2, dir: 'out' }, 'P. Nair');
    logMove({ name: 'bandage', label: 'Bandage', image: img('bandage'), count: 5, dir: 'in' });
    setQty(5);

    const node = sel => A.el.querySelector(sel);
    if (demo === 'tip') setTimeout(() => showTip(node('.mb-open .mb-slot[data-slot="19"]')), 300);
    if (demo === 'tippar') setTimeout(() => showTip(node('.mb-open .mb-slot[data-slot="2"]')), 300);
    if (demo === 'ghost') setTimeout(() => showTip(node('.mb-open .mb-slot.ghost')), 300);
    if (demo === 'tipme') setTimeout(() => showTip(node('.mb-list .mb-row[data-slot="17"]')), 300);
    if (demo === 'style') setTimeout(() => { toggleStyle(true); S.pickColour = 'green'; renderStyle(); R.bagCard.style.setProperty('--bc', '#2fb36b'); }, 300);
    if (demo === 'stack') setTimeout(() => setQty('stack'), 300);
    if (demo === 'half') setTimeout(() => setQty('half'), 300);
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
      const tgt = node('.mb-open .mb-slot[data-slot="16"]').getBoundingClientRect();
      onMove({ clientX: r.left + 60, clientY: r.top + 10 });
      onMove({ clientX: tgt.left + tgt.width / 2, clientY: tgt.top + tgt.height / 2 });
    }, 300);
    if (demo === 'fly') setTimeout(() => {
      move({ dir: 'in', from: 9, count: 4, name: 'adrenaline' }, node('.mb-list .mb-row[data-slot="9"]'));
    }, 300);
  }
})();
