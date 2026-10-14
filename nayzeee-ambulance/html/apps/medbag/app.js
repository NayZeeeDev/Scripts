/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · app 'medbag'
   Medical bag storage: three HUD panels on the right (bag slots + capacity,
   transfer amount, personnel pockets + capacity), hover tooltips, drag & drop,
   and a row of transfer cards ("PACKED 5×", "REMOVED 1×") over the world.

   Lua → JS   open { locale, bag, me, kit }    sync { bag }    me { me }    busy { on }
   JS → Lua   medbag:move   { dir: 'in'|'out'|'bag', from, to?, count: n|'all', name }
              medbag:action { action: 'sort'|'lock'|'kit'|'empty', data }
              → { ok, bag, me, moved?, movedList?, msg?, err? }
              medbag:close (router, on Escape / Close)

   bag = { id, owner, mine, locked, canLock, slots, items: [{ slot, name, label, image, count,
           weight (g/unit), desc, cat, meta: [{ k?, v }] }], weight, maxWeight, held }
   me  = { items: [{ slot, name, label, image, count, weight, desc, cat, meta, allowed }], weight, maxWeight }

   Mouse: click = move the transfer amount, Shift+click = all, right click = one,
          drag = to a slot (bag ↔ pockets, or rearrange inside the bag).
   Keys:  1 / 2 / 3 / 4 = amount 1 / 5 / 10 / all, + / - = step, F = search pockets.
   ═══════════════════════════════════════════════════════════ */
(() => {
  const esc = NZA.esc;
  const icon = n => NZA.icon(n);
  const COLS = 5;

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

  const kg = g => (Math.max(0, Number(g) || 0) / 1000).toFixed(1);
  const grams = g => (g >= 1000 ? `${kg(g)} ${t('ui_kg', 'kg')}` : `${Math.round(g)} g`);
  const CAT = { first_aid: 'First aid', wound_care: 'Wound care', medication: 'Medication', fluids: 'Fluids & IV', orthopedic: 'Orthopedic', airway: 'Airway', surgery: 'Surgery', equipment: 'Equipment', documents: 'Documents', other: 'Other' };
  const catLabel = c => t(`cat_${c || 'other'}`, CAT[c] || CAT.other);
  const keyLabel = k => { const s = String(k).replace(/[_-]+/g, ' ').trim(); return s.length <= 3 ? s.toUpperCase() : s.charAt(0).toUpperCase() + s.slice(1); };
  const imgFallback = "this.onerror=null;this.src='img/items/nza_unknown.png'";

  const S = {
    on: false, bag: null, me: null, kit: false,
    amount: 1, all: false, search: '',
    queue: Promise.resolve(), busy: 0,
    drag: null, press: null, tipFor: null,
  };
  let A = null;       // app def
  let R = {};         // element refs
  let seg = null;     // amount segmented control
  let ghost = null;   // drag ghost (body layer, not zoomed)

  /* ─────────────── markup ─────────────── */
  function build(el) {
    el.innerHTML = `
      <div class="mb-col">
        <section class="mb-panel nza-hud solid rail mb-store">
          <header class="mb-ph">
            <div class="nz-tile">${icon('medkit')}</div>
            <div class="mb-pt">
              <b class="mb-title"></b>
              <span class="mb-sub"></span>
            </div>
            <div class="mb-tools">
              <button class="mb-ib" data-act="sort" title="">${icon('sortd')}</button>
              <button class="mb-ib" data-act="lock" title="">${icon('unlock')}</button>
              <button class="pill-close" data-act="close"></button>
            </div>
          </header>
          <div class="mb-meta"></div>
          <div class="mb-grid-wrap"><div class="mb-grid" data-side="bag"></div><div class="mb-empty"></div></div>
          <footer class="mb-cap" data-cap="bag"></footer>
        </section>

        <section class="mb-panel nza-hud solid mb-xfer">
          <div class="mb-xrow">
            <div class="mb-xl"><span class="mb-arrows">${icon('swap')}</span><span class="nza-label mb-amt-l"></span></div>
            <div class="mb-step">
              <button data-step="-1">${icon('minus')}</button>
              <input class="mb-num" type="text" inputmode="numeric" maxlength="4" value="1">
              <button data-step="1">${icon('plus')}</button>
            </div>
            <div class="mb-seg"></div>
          </div>
          <div class="mb-xrow2">
            <div class="mb-acts">
              <button class="btn-line btn-sm mb-kit" data-act="kit">${icon('arrow-down')}<span></span></button>
              <button class="btn-line btn-sm mb-emp" data-act="empty">${icon('arrow-up')}<span></span></button>
            </div>
            <div class="mb-hints"></div>
          </div>
        </section>

        <section class="mb-panel nza-hud solid mb-pers">
          <header class="mb-ph">
            <div class="nz-tile mute">${icon('user')}</div>
            <div class="mb-pt">
              <b class="mb-ptitle"></b>
              <span class="mb-sub mb-psub"></span>
            </div>
            <label class="mb-search">${icon('search')}<input type="text" maxlength="24" spellcheck="false"></label>
          </header>
          <div class="mb-grid-wrap mb-pwrap"><div class="mb-grid mb-pgrid" data-side="me"></div><div class="mb-empty mb-pempty"></div></div>
          <footer class="mb-cap" data-cap="me"></footer>
        </section>
        <div class="mb-tip nza-hud solid"></div>
      </div>
      <div class="mb-toasts"></div>`;

    const q = s => el.querySelector(s);
    R = {
      col: q('.mb-col'), store: q('.mb-store'), pers: q('.mb-pers'), xfer: q('.mb-xfer'),
      title: q('.mb-title'), sub: q('.mb-store .mb-sub'), meta: q('.mb-meta'),
      grid: q('.mb-grid[data-side="bag"]'), empty: q('.mb-store .mb-empty'), capBag: q('[data-cap="bag"]'),
      pgrid: q('.mb-pgrid'), pempty: q('.mb-pempty'), capMe: q('[data-cap="me"]'),
      ptitle: q('.mb-ptitle'), psub: q('.mb-psub'), search: q('.mb-search input'),
      num: q('.mb-num'), segHost: q('.mb-seg'), amtL: q('.mb-amt-l'), hints: q('.mb-hints'),
      kit: q('.mb-kit'), emp: q('.mb-emp'), sort: q('[data-act="sort"]'), lock: q('[data-act="lock"]'),
      close: q('[data-act="close"]'), tip: q('.mb-tip'), toasts: q('.mb-toasts'),
    };

    seg = NZA.ui.Segmented(R.segHost, {
      options: [{ value: '1', label: '1' }, { value: '5', label: '5' }, { value: '10', label: '10' }, { value: 'all', label: 'ALL' }],
      value: '1',
      onChange: v => setAmount(v === 'all' ? 'all' : Number(v)),
    });
    seg.el.classList.add('mb-chips');

    // header + transfer buttons
    el.addEventListener('click', e => {
      const b = e.target.closest('[data-act]');
      if (b) { e.preventDefault(); action(b.dataset.act); return; }
      const st = e.target.closest('[data-step]');
      if (st) { step(Number(st.dataset.step)); }
    });
    R.num.addEventListener('input', () => {
      const v = R.num.value.replace(/[^0-9]/g, '');
      R.num.value = v;
      if (v) setAmount(Math.max(1, Math.min(9999, Number(v))), true);
    });
    R.num.addEventListener('blur', () => renderAmount());
    R.num.addEventListener('wheel', e => { e.preventDefault(); step(e.deltaY < 0 ? 1 : -1); }, { passive: false });
    R.search.addEventListener('input', () => { S.search = R.search.value.trim().toLowerCase(); renderMe(); });

    // slots: press / drag / click / hover
    el.addEventListener('mousedown', onDown);
    el.addEventListener('contextmenu', e => e.preventDefault());
    el.addEventListener('mouseover', onOver);
    el.addEventListener('mouseout', e => { if (e.target.closest && e.target.closest('.mb-slot') && !e.relatedTarget?.closest?.('.mb-slot')) hideTip(); });
    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp);
  }

  function texts() {
    R.title.textContent = t('ui_storage', 'Medical Bag');
    R.ptitle.textContent = t('ui_personnel', 'Personnel');
    R.psub.textContent = t('ui_personnel_sub', 'Equipment & pockets');
    R.close.textContent = t('ui_close', 'Close');
    R.amtL.textContent = t('ui_amount', 'Transfer amount');
    R.kit.querySelector('span').textContent = t('ui_kit', 'Pack kit');
    R.kit.title = t('ui_kit_d', 'Top the bag up from your pockets');
    R.emp.querySelector('span').textContent = t('ui_empty', 'Empty bag');
    R.sort.title = t('ui_sort', 'Sort');
    R.search.placeholder = t('ui_search', 'Search pockets');
    R.hints.innerHTML = [
      ['Shift', t('ui_h_shift', 'Move all')],
      ['RMB', t('ui_h_right', 'Move one')],
    ].map(([k, l]) => `<span><kbd>${esc(k)}</kbd>${esc(l)}</span>`).join('');
  }

  /* ─────────────── rendering ─────────────── */
  function slotHTML(it, slot, side) {
    if (!it) return `<div class="mb-slot empty" data-side="${side}" data-slot="${slot}"><i class="n">${slot}</i></div>`;
    const dis = side === 'me' && it.allowed === false;
    return `<div class="mb-slot${dis ? ' dis' : ''}" data-side="${side}" data-slot="${it.slot}" data-name="${esc(it.name)}">
      ${side === 'bag' ? `<i class="n">${slot}</i>` : ''}
      <img src="${esc(it.image || `img/items/${it.name}.png`)}" alt="" draggable="false" onerror="${imgFallback}">
      ${it.count > 1 || side === 'bag' ? `<b class="c">${esc(it.count)}</b>` : ''}
      ${dis ? `<span class="ban">${icon('ban')}</span>` : ''}
      <span class="lb">${esc(it.label)}</span>
    </div>`;
  }

  function capHTML(weight, max, slotsUsed, slots) {
    if (max === null || max === undefined) {
      return `<div class="mb-capl"><span class="nza-label">${esc(t('ui_capacity', 'Capacity'))}</span><b>${kg(weight)} ${esc(t('ui_kg', 'kg'))}</b></div>`;
    }
    const p = Math.max(0, Math.min(1, max > 0 ? weight / max : 0));
    const tone = p >= 0.95 ? 'red' : p >= 0.8 ? 'amber' : '';
    return `<div class="mb-capl"><span class="nza-label">${esc(t('ui_capacity', 'Capacity'))}</span>
        <b class="${tone}">${kg(weight)}<span> / ${kg(max)} ${esc(t('ui_kg', 'kg'))}</span></b></div>
      <div class="mb-bar ${tone}"><i style="width:${(p * 100).toFixed(1)}%"></i></div>
      ${slots ? `<div class="mb-capr">${esc(t('ui_slots', '%s / %s slots', slotsUsed, slots))}<span>${Math.round(p * 100)}%</span></div>` : ''}`;
  }

  function renderBag() {
    const b = S.bag;
    if (!b) return;
    R.sub.textContent = `${t('ui_storage_sub', 'Unit storage')} · ${b.id}`;
    const chips = [];
    chips.push(b.mine
      ? `<span class="nz-chip">${esc(t('ui_yours', 'Your bag'))}</span>`
      : `<span class="nz-chip white">${esc(t('ui_owner', 'Owner'))} · ${esc(b.owner || '?')}</span>`);
    if (b.locked) chips.push(`<span class="nz-chip mb-lockchip">${icon('lock')}${esc(t('ui_locked', 'Locked'))}</span>`);
    R.meta.innerHTML = chips.join('');
    R.lock.style.display = b.canLock ? '' : 'none';
    R.lock.innerHTML = icon(b.locked ? 'lock' : 'unlock');
    R.lock.classList.toggle('on', !!b.locked);
    R.lock.title = b.locked ? t('ui_unlock', 'Unlock') : t('ui_lock', 'Lock');

    const bySlot = {};
    (b.items || []).forEach(it => { bySlot[it.slot] = it; });
    const n = Math.max(b.slots || 20, ...(b.items || []).map(i => i.slot));
    const cells = [];
    for (let s = 1; s <= n; s++) cells.push(slotHTML(bySlot[s], s, 'bag'));
    R.grid.innerHTML = cells.join('');
    R.empty.textContent = (b.items || []).length ? '' : t('ui_bag_empty', 'The bag is empty. Click or drag items from your pockets.');
    R.empty.classList.toggle('on', !(b.items || []).length);
    R.capBag.innerHTML = capHTML(b.weight || 0, b.maxWeight || 20000, (b.items || []).length, n);
    R.emp.disabled = !(b.items || []).length;
  }

  function renderMe() {
    const m = S.me;
    if (!m) return;
    const all = m.items || [];
    const list = S.search ? all.filter(it => `${it.label} ${it.name}`.toLowerCase().includes(S.search)) : all;
    // allowed items first, keep inventory order inside each group
    const sorted = [...list.filter(i => i.allowed !== false), ...list.filter(i => i.allowed === false)];
    const cells = sorted.map(it => slotHTML(it, it.slot, 'me'));
    const pad = (COLS - (cells.length % COLS)) % COLS + (cells.length < COLS * 3 ? COLS * Math.max(0, 3 - Math.ceil(cells.length / COLS)) : 0);
    for (let i = 0; i < pad; i++) cells.push('<div class="mb-slot empty ph"></div>');
    R.pgrid.innerHTML = cells.join('');
    const none = !list.length;
    R.pempty.classList.toggle('on', none);
    R.pempty.textContent = none ? (S.search ? t('ui_nomatch', 'No item matches') : t('ui_none', 'Nothing in your pockets')) : '';
    R.capMe.innerHTML = capHTML(m.weight || 0, m.maxWeight, null, null);
  }

  function renderAmount() {
    if (S.all) { R.num.value = t('ui_all', 'All').toUpperCase(); seg.set('all'); }
    else { if (document.activeElement !== R.num) R.num.value = String(S.amount); seg.set(['1', '5', '10'].includes(String(S.amount)) ? String(S.amount) : ''); }
    R.kit.style.display = S.kit ? '' : 'none';
  }

  function renderAll() { renderBag(); renderMe(); renderAmount(); }

  /* ─────────────── amount ─────────────── */
  function setAmount(v, typed) {
    if (v === 'all') { S.all = true; }
    else { S.all = false; S.amount = Math.max(1, Math.min(9999, Math.floor(Number(v) || 1))); }
    if (!typed) renderAmount();
    else seg.set(['1', '5', '10'].includes(String(S.amount)) ? String(S.amount) : '');
    NZA.audio.tick();
  }
  function step(d) {
    if (S.all) { S.all = false; S.amount = d > 0 ? 1 : 1; }
    else S.amount = Math.max(1, Math.min(9999, S.amount + d));
    renderAmount(); NZA.audio.tick();
  }
  const curCount = () => (S.all ? 'all' : S.amount);

  /* ─────────────── tooltips ─────────────── */
  function findItem(side, slot) {
    const list = side === 'bag' ? (S.bag && S.bag.items) : (S.me && S.me.items);
    return (list || []).find(i => String(i.slot) === String(slot));
  }
  function onOver(e) {
    if (S.drag) return;
    const s = e.target.closest && e.target.closest('.mb-slot[data-name]');
    if (!s || s === S.tipFor) return;
    showTip(s);
  }
  function offsetIn(node, root) {
    let y = 0, n = node;
    while (n && n !== root) { y += n.offsetTop; n = n.offsetParent; }
    return y;
  }
  function showTip(slotEl) {
    const side = slotEl.dataset.side, it = findItem(side, slotEl.dataset.slot);
    if (!it) return hideTip();
    S.tipFor = slotEl;
    const per = Number(it.weight) || 0;
    const metaRows = (it.meta || []).map(m => (m.k
      ? `<div class="r"><span>${esc(keyLabel(m.k))}</span><b>${esc(m.v)}</b></div>`
      : `<p class="md">${esc(m.v)}</p>`)).join('');
    const scroll = slotEl.closest('.mb-grid-wrap');
    const top = offsetIn(slotEl, R.col) - (scroll ? scroll.scrollTop : 0);
    const dis = side === 'me' && it.allowed === false;
    const actOut = side === 'bag';
    R.tip.innerHTML = `
      <div class="th"><span class="ti"><img src="${esc(it.image || `img/items/${it.name}.png`)}" alt="" onerror="${imgFallback}"></span>
        <div><b>${esc(it.label)}</b><span class="nz-chip white">${esc(catLabel(it.cat))}</span></div></div>
      ${it.desc ? `<p class="d">${esc(it.desc)}</p>` : ''}
      <div class="r"><span>${esc(t('ui_weight', 'Weight'))}</span><b>${esc(grams(per))} <em>${esc(t('ui_unit', 'each'))}</em> · ${esc(grams(per * it.count))} <em>${esc(t('ui_total', 'total'))}</em></b></div>
      <div class="r"><span>${esc(t('ui_stack', 'Stack'))}</span><b>× ${esc(it.count)}</b></div>
      ${metaRows}
      ${dis ? `<div class="no">${icon('ban')}${esc(t('ui_not_allowed', 'Not for the bag'))}</div>`
            : `<div class="hk"><span><kbd>Click</kbd>${actOut ? icon('arrow-down') : icon('arrow-up')}${esc(S.all ? t('ui_all', 'All') : `${S.amount}×`)}</span><span><kbd>Shift</kbd>${esc(t('ui_h_shift', 'Move all'))}</span></div>`}`;
    R.tip.style.top = `${Math.max(0, top - 6)}px`;
    R.tip.classList.add('on');
    // keep it on screen
    const maxTop = R.col.clientHeight - R.tip.offsetHeight - 4;
    if (top - 6 > maxTop) R.tip.style.top = `${Math.max(0, maxTop)}px`;
  }
  function hideTip() { S.tipFor = null; R.tip && R.tip.classList.remove('on'); }

  /* ─────────────── mouse: click / drag ─────────────── */
  function onDown(e) {
    const s = e.target.closest('.mb-slot[data-name]');
    if (!s || (e.button !== 0 && e.button !== 2)) return;
    e.preventDefault();
    S.press = { el: s, side: s.dataset.side, slot: Number(s.dataset.slot), name: s.dataset.name, x: e.clientX, y: e.clientY, button: e.button, shift: e.shiftKey };
  }
  function onMove(e) {
    const p = S.press;
    if (!p) return;
    if (!S.drag && p.button === 0 && Math.hypot(e.clientX - p.x, e.clientY - p.y) > 6) startDrag(p);
    if (!S.drag) return;
    ghost.style.left = `${e.clientX}px`; ghost.style.top = `${e.clientY}px`;
    const under = document.elementFromPoint(e.clientX, e.clientY);
    const slot = under && under.closest && under.closest('.mb-slot[data-side="bag"]');
    const pers = under && under.closest && under.closest('.mb-pers');
    document.querySelectorAll('#app-medbag .mb-slot.drop').forEach(x => x.classList.remove('drop'));
    R.store.classList.toggle('dropzone', !!(slot || (under && under.closest && under.closest('.mb-store'))) && S.drag.side === 'me');
    R.pers.classList.toggle('dropzone', !!pers && S.drag.side === 'bag');
    if (slot && slot !== S.drag.el) slot.classList.add('drop');
  }
  function onUp(e) {
    const p = S.press;
    S.press = null;
    if (!p) return;
    if (S.drag) return endDrag(e);
    // a click
    const count = p.button === 2 ? 1 : (p.shift || e.shiftKey ? 'all' : curCount());
    if (p.side === 'me') {
      const it = findItem('me', p.slot);
      if (it && it.allowed === false) { p.el.classList.add('shake'); setTimeout(() => p.el.classList.remove('shake'), 400); NZA.audio.click(260); return; }
      move({ dir: 'in', from: p.slot, count, name: p.name }, p.el);
    } else {
      move({ dir: 'out', from: p.slot, count, name: p.name }, p.el);
    }
  }
  function startDrag(p) {
    const it = findItem(p.side, p.slot);
    if (!it || (p.side === 'me' && it.allowed === false)) return;
    hideTip();
    S.drag = { side: p.side, slot: p.slot, name: p.name, el: p.el, shift: p.shift };
    p.el.classList.add('lifted');
    ghost = document.createElement('div');
    ghost.className = 'mb-ghost';
    const n = p.shift ? it.count : (S.all ? it.count : Math.min(S.amount, it.count));
    ghost.innerHTML = `<img src="${esc(it.image || `img/items/${it.name}.png`)}" alt="" onerror="${imgFallback}"><b>${esc(n)}</b>`;
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
    document.querySelectorAll('#app-medbag .mb-slot.drop').forEach(x => x.classList.remove('drop'));
    R.store.classList.remove('dropzone'); R.pers.classList.remove('dropzone');
    const under = document.elementFromPoint(e.clientX, e.clientY);
    if (!under || !under.closest) return;
    const count = d.shift || e.shiftKey ? 'all' : curCount();
    const bagSlot = under.closest('.mb-slot[data-side="bag"]');
    const inStore = under.closest('.mb-store');
    const inPers = under.closest('.mb-pers');
    if (d.side === 'me' && (bagSlot || inStore)) {
      move({ dir: 'in', from: d.slot, to: bagSlot ? Number(bagSlot.dataset.slot) : undefined, count, name: d.name }, bagSlot || d.el);
    } else if (d.side === 'bag' && bagSlot) {
      if (Number(bagSlot.dataset.slot) !== d.slot) move({ dir: 'bag', from: d.slot, to: Number(bagSlot.dataset.slot), count, name: d.name }, bagSlot);
    } else if (d.side === 'bag' && inPers) {
      move({ dir: 'out', from: d.slot, count, name: d.name }, d.el);
    }
  }

  /* ─────────────── server round trips (one at a time, in order) ─────────────── */
  function apply(res) {
    if (!res || typeof res !== 'object') return;
    if (res.bag) S.bag = res.bag;
    if (res.me) S.me = res.me;
    renderBag(); renderMe();
    if (S.tipFor && !document.body.contains(S.tipFor)) hideTip();
  }
  function pulse(side, slot) {
    const g = side === 'bag' ? R.grid : R.pgrid;
    const s = g && g.querySelector(`.mb-slot[data-slot="${slot}"]`);
    if (s) { s.classList.remove('pulse'); void s.offsetWidth; s.classList.add('pulse'); }
  }
  function enqueue(fn) {
    S.busy++;
    R.col.classList.add('busy');
    S.queue = S.queue.then(fn).catch(err => console.error('[medbag]', err)).finally(() => {
      S.busy = Math.max(0, S.busy - 1);
      if (!S.busy) R.col.classList.remove('busy');
    });
    return S.queue;
  }
  function failToast(res) {
    NZA.toast({ title: t('title', 'Medical Bag'), message: (res && res.msg) || t('err_failed', "That didn't work. Try again"), type: 'error', duration: 3200 });
    NZA.audio.fail();
  }
  function move(data, fromEl) {
    if (!S.on) return;
    if (fromEl) fromEl.classList.add('pending');
    return enqueue(async () => {
      const res = await NZA.post('medbag:move', data);
      if (fromEl) fromEl.classList.remove('pending');
      if (!res || res === 'timeout') return failToast(null);
      apply(res);
      if (!res.ok) return failToast(res);
      if (res.moved) {
        transferCard(res.moved);
        const it = data.dir === 'out' ? null : (S.bag.items || []).find(i => i.name === res.moved.name && (data.to ? i.slot === data.to : true));
        if (it) pulse('bag', it.slot);
        NZA.audio.click(data.dir === 'out' ? 560 : 760);
      }
    });
  }
  function action(act) {
    if (act === 'close') return NZA.close('medbag');
    if (act === 'empty') {
      NZA.ui.Modal({
        title: t('ui_empty_q', 'Take everything out?'), text: t('ui_empty_t', 'Every item goes into your pockets while there is room.'),
        icon: 'arrow-up', tone: 'teal',
        actions: [{ label: t('ui_cancel', 'Cancel'), kind: 'line' }, { label: t('ui_confirm', 'Take all'), kind: 'teal', onClick: () => { run('empty'); } }],
        host: A.el,
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
      (res.movedList || []).slice(0, 8).forEach((m, i) => setTimeout(() => transferCard(m), i * 90));
      if (res.msg) NZA.toast({ title: t('title', 'Medical Bag'), message: res.msg, type: 'success', duration: 2800, icon: act === 'lock' ? (S.bag.locked ? 'lock' : 'unlock') : 'check' });
      if (act === 'sort') { R.grid.classList.remove('sorted'); void R.grid.offsetWidth; R.grid.classList.add('sorted'); }
    });
  }

  /* ─────────────── transfer cards ─────────────── */
  function transferCard(m) {
    if (!m || !R.toasts) return;
    const dir = m.dir || 'in';
    const label = dir === 'in' ? t('ui_added', 'Packed %s×', m.count) : dir === 'out' ? t('ui_removed', 'Removed %s×', m.count) : t('ui_moved', 'Moved %s×', m.count);
    const c = document.createElement('div');
    c.className = `mb-card ${dir}`;
    c.innerHTML = `<span class="h">${dir === 'out' ? icon('arrow-up') : dir === 'in' ? icon('arrow-down') : icon('swap')}${esc(label)}</span>
      <span class="im"><img src="${esc(m.image || `img/items/${m.name}.png`)}" alt="" onerror="${imgFallback}"></span>
      <span class="nm">${esc(m.label || m.name)}</span><i class="tm"></i>`;
    R.toasts.appendChild(c);
    while (R.toasts.children.length > 6) R.toasts.firstChild.remove();
    setTimeout(() => { c.classList.add('bye'); setTimeout(() => c.remove(), 260); }, 3400);
  }

  /* ─────────────── app ─────────────── */
  A = NZA.app('medbag', {
    camInput: false,
    init(el) { build(el); texts(); },
    open(d) {
      loc = Object.assign({}, loc, d.locale || {});
      texts();
      S.on = true; S.bag = d.bag || null; S.me = d.me || null; S.kit = !!d.kit;
      S.search = ''; R.search.value = '';
      if (d.amount !== undefined) setAmount(d.amount);
      hideTip();
      R.toasts.innerHTML = '';
      renderAll();
      A.el.classList.remove('leaving');
    },
    close() {
      S.on = false; hideTip();
      if (ghost) { ghost.remove(); ghost = null; }
      S.drag = null; S.press = null;
      document.querySelectorAll('.nza-modal-wrap').forEach(m => { if (A.el.contains(m)) m.remove(); });
    },
    msg: {
      sync(d) {
        if (!d || !d.bag) return;
        S.bag = d.bag; renderBag();
        if (S.tipFor && !document.body.contains(S.tipFor)) hideTip();
      },
      me(d) {
        if (!d || !d.me || S.drag || S.busy) return;
        S.me = d.me; renderMe();
        if (S.tipFor && !document.body.contains(S.tipFor)) hideTip();
      },
      busy(d) { R.col.classList.toggle('busy', !!(d && d.on)); },
    },
    keys: {
      '1'(e) { if (typing(e)) return false; setAmount(1); },
      '2'(e) { if (typing(e)) return false; setAmount(5); },
      '3'(e) { if (typing(e)) return false; setAmount(10); },
      '4'(e) { if (typing(e)) return false; setAmount('all'); },
      '+'(e) { if (typing(e)) return false; step(1); },
      '='(e) { if (typing(e)) return false; step(1); },
      '-'(e) { if (typing(e)) return false; step(-1); },
      KeyF(e) { if (typing(e)) return false; R.search.focus(); },
      Escape(e) {
        if (A.el.querySelector('.nza-modal-wrap')) { A.el.querySelector('.nza-modal-wrap').remove(); return; }
        if (document.activeElement === R.search && R.search.value) { R.search.value = ''; S.search = ''; renderMe(); return; }
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
    const mk = (name, count, slot, meta) => ({ slot, name, label: L[name] || name, image: img(name === 'phone' || name === 'water' || name === 'lockpick' ? 'nza_unknown' : name), count, weight: W[name] || 100, desc: D[name], cat: C[name] || 'other', meta, allowed: OWN.has(name) });
    const bag = { id: 'MB-7K2QF', owner: 'Maya Reyes', mine: true, locked: false, canLock: true, slots: 20, maxWeight: 20000, items: [
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
    refresh();
    const clone = o => JSON.parse(JSON.stringify(o));
    const reply = (extra) => { refresh(); return Object.assign({ ok: true, bag: clone(bag), me: clone(me) }, extra); };
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
        return reply({ moved: { name: it.name, label: it.label, image: it.image, count: n, dir: 'in' } });
      }
      if (d.dir === 'out') {
        const it = bag.items.find(i => i.slot === d.from);
        if (!it) return reply({ ok: false, msg: 'That slot is empty' });
        const n = d.count === 'all' ? it.count : Math.min(d.count, it.count);
        it.count -= n; addToMe(it, n);
        if (it.count <= 0) bag.items.splice(bag.items.indexOf(it), 1);
        return reply({ moved: { name: it.name, label: it.label, image: it.image, count: n, dir: 'out' } });
      }
      if (d.dir === 'bag') {
        const it = bag.items.find(i => i.slot === d.from), tg = bag.items.find(i => i.slot === d.to);
        if (!it) return reply({ ok: false });
        if (!tg) it.slot = d.to; else if (tg.name === it.name && sameMeta(tg, it)) { const add = Math.min(cap(it.name) - tg.count, it.count); tg.count += add; it.count -= add; if (it.count <= 0) bag.items.splice(bag.items.indexOf(it), 1); } else { tg.slot = d.from; it.slot = d.to; }
        return reply({ moved: { name: it.name, label: it.label, image: it.image, count: it.count, dir: 'bag' } });
      }
      return reply({ ok: false });
    });
    NZA.mock('medbag:action', d => {
      if (d.action === 'lock') { bag.locked = !!(d.data && d.data.on); return reply({ msg: bag.locked ? 'Bag locked. Only you can open it now' : 'Bag unlocked' }); }
      if (d.action === 'sort') { bag.items.sort((a, b) => a.cat.localeCompare(b.cat) || a.label.localeCompare(b.label)); bag.items.forEach((i, k) => { i.slot = k + 1; }); return reply({ msg: 'Bag sorted' }); }
      if (d.action === 'kit') {
        const list = [];
        [['bandage', 10], ['tourniquet', 4], ['sterile_dressing', 6]].forEach(([n, c]) => {
          const have = bag.items.filter(i => i.name === n).reduce((a, i) => a + i.count, 0);
          const it = me.items.find(i => i.name === n);
          const k = Math.min(Math.max(0, c - have), it ? it.count : 0);
          if (k > 0) { addToBag(it, k); it.count -= k; if (it.count <= 0) me.items.splice(me.items.indexOf(it), 1); list.push({ name: n, label: L[n], image: img(n), count: k, dir: 'in' }); }
        });
        if (!list.length) return reply({ ok: false, msg: 'Nothing to move' });
        return reply({ movedList: list, msg: `Packed ${list.reduce((a, m) => a + m.count, 0)} items into the bag` });
      }
      if (d.action === 'empty') {
        const list = bag.items.map(i => ({ name: i.name, label: i.label, image: i.image, count: i.count, dir: 'out' }));
        bag.items.forEach(i => addToMe(i, i.count)); bag.items.length = 0;
        return reply({ movedList: list, msg: `Took ${list.reduce((a, m) => a + m.count, 0)} items out of the bag` });
      }
      return reply({ ok: false });
    });
    refresh();
    NZA.demo('medbag', { bag: clone(bag), me: clone(me), kit: true });
    // a few cards like the moment after taking supplies out
    setTimeout(() => {
      [['painkillers', 1, 'out'], ['painkillers', 1, 'out'], ['splint', 1, 'out'], ['bandage', 5, 'in']].forEach(([n, c, dir], i) =>
        setTimeout(() => transferCard({ name: n, label: L[n], image: img(n), count: c, dir }), i * 120));
    }, 250);
    const demo = new URLSearchParams(location.search).get('demo');
    if (demo === 'tip') setTimeout(() => { const s = R.grid.querySelector('.mb-slot[data-slot="11"]'); if (s) showTip(s); }, 400);
    if (demo === 'tipme') setTimeout(() => { const s = R.pgrid.querySelector('.mb-slot[data-slot="18"]'); if (s) showTip(s); }, 400);
    if (demo === 'locked') { bag.mine = false; bag.owner = 'J. Doe'; bag.locked = true; bag.canLock = false; NZA.demo('medbag', { bag: clone(bag), me: clone(me), kit: true }); }
    if (demo === 'empty') { bag.items.length = 0; refresh(); NZA.demo('medbag', { bag: clone(bag), me: clone(me), kit: true }); }
    if (demo === 'full') {
      const extra = ['sterile_dressing', 'foil_blanket', 'ice_pack', 'adrenaline', 'suture_kit', 'txa', 'cervical_collar', 'pelvic_binder', 'oxygen_mask', 'medikit', 'morphine'];
      extra.forEach((n, i) => bag.items.push(mk(n, n === 'pelvic_binder' ? 8 : n === 'medikit' ? 6 : 4, 9 + i + (i >= 2 ? 1 : 0))));
      refresh(); NZA.demo('medbag', { bag: clone(bag), me: clone(me), kit: true });
    }
    if (demo === 'drag') setTimeout(() => {
      const s = R.pgrid.querySelector('.mb-slot[data-slot="5"]');
      const r = s.getBoundingClientRect();
      onDown({ target: s, button: 0, clientX: r.left + 20, clientY: r.top + 20, shiftKey: false, preventDefault() {} });
      const tgt = R.grid.querySelector('.mb-slot[data-slot="13"]').getBoundingClientRect();
      onMove({ clientX: r.left + 40, clientY: r.top + 10 });
      onMove({ clientX: tgt.left + tgt.width / 2, clientY: tgt.top + tgt.height / 2 });
    }, 400);
  }
})();
