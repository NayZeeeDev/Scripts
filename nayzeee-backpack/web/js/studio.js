/* Backpack studio UI (/bagtune) */
(function () {
  const $ = (id) => document.getElementById(id);
  const post = (name, data) => fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data || {})
  }).catch(() => {});
  const ic = (d) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor">${d}</svg>`;
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  let S = {
    bags: [], bones: [], presets: [], styles: [], poses: [], current: null, variant: null, pose: null,
    tune: { bone: 24818, pos: { x: 0, y: 0, z: 0 }, rot: { x: 0, y: 0, z: 0 } },
    calibrated: false, cam: { focus: 1 }, admin: false, icon: null,
  };
  let tab = 'fit';
  let moveStep = 0.01, rotStep = 5;
  let search = '';
  const MOVE_STEPS = [[0.0025, '2.5mm'], [0.005, '5mm'], [0.01, '1cm'], [0.025, '2.5cm'], [0.05, '5cm']];
  const ROT_STEPS = [[1, '1°'], [5, '5°'], [15, '15°'], [45, '45°'], [90, '90°']];
  const shots = [];

  const bag = () => S.bags.find((b) => b.key === S.current);
  const open = () => $('studio').classList.contains('open');
  const typing = (el) => el && (el.tagName === 'INPUT' || el.tagName === 'SELECT' || el.tagName === 'TEXTAREA');
  const mult = (e) => (e && e.shiftKey ? 5 : 1) * (e && e.altKey ? 0.2 : 1);

  /* ---------- hold-to-repeat buttons ---------- */
  function holdable(el, fn) {
    let wait, rep;
    const stop = () => { clearTimeout(wait); clearInterval(rep); el.classList.remove('held'); };
    el.addEventListener('pointerdown', (e) => {
      if (e.button !== 0) return;
      e.preventDefault();
      const m = mult(e);
      fn(m);
      el.classList.add('held');
      wait = setTimeout(() => { rep = setInterval(() => fn(m), 85); }, 320);
    });
    ['pointerup', 'pointerleave', 'pointercancel'].forEach((ev) => el.addEventListener(ev, stop));
    window.addEventListener('pointerup', stop);
    window.addEventListener('blur', stop);
  }

  const move = (axis, dir, m) => post('studio:move', { axis, amount: dir * moveStep * (m || 1) });
  const rotate = (axis, dir, m) => post('studio:rotate', { axis, deg: dir * rotStep * (m || 1) });

  document.querySelectorAll('[data-move]').forEach((b) => holdable(b, (m) => move(b.dataset.move, +b.dataset.dir, m)));
  document.querySelectorAll('[data-rot]').forEach((b) => holdable(b, (m) => rotate(b.dataset.rot, +b.dataset.dir, m)));

  function buildSteps() {
    const mk = (el, list, cur, set) => {
      el.querySelectorAll('button').forEach((b) => b.remove());
      list.forEach(([v, label]) => {
        const b = document.createElement('button');
        b.textContent = label;
        if (v === cur()) b.classList.add('on');
        b.onclick = () => { set(v); buildSteps(); };
        el.appendChild(b);
      });
    };
    mk($('moveSteps'), MOVE_STEPS, () => moveStep, (v) => { moveStep = v; });
    mk($('rotSteps'), ROT_STEPS, () => rotStep, (v) => { rotStep = v; });
  }

  /* ---------- exact value rows ---------- */
  function axisRow(group, axis) {
    const isPos = group === 'pos';
    const row = document.createElement('div');
    row.className = 'axis';
    row.innerHTML = `
      <span class="nm">${axis}</span>
      <button class="step" data-d="-1">${ic('<path d="M5 12h14"/>')}</button>
      <input type="range" min="${isPos ? -1.5 : -180}" max="${isPos ? 1.5 : 180}" step="${isPos ? 0.001 : 0.5}">
      <button class="step" data-d="1">${ic('<path d="M12 5v14M5 12h14"/>')}</button>
      <input class="val" type="text">`;
    const range = row.querySelector('input[type=range]');
    const box = row.querySelector('.val');
    const send = (v) => {
      const t = { ...S.tune[group] };
      t[axis] = v;
      if (isPos) post('studio:pos', { pos: t }); else post('studio:rot', { rot: t });
    };
    let pending = null;
    range.addEventListener('input', () => {
      box.value = (+range.value).toFixed(isPos ? 3 : 1);
      if (pending) return;
      pending = requestAnimationFrame(() => { pending = null; send(+range.value); });
    });
    box.addEventListener('change', () => { const v = parseFloat(box.value); if (!isNaN(v)) send(v); });
    row.querySelectorAll('.step').forEach((b) => holdable(b, (m) => {
      const step = isPos ? moveStep : rotStep;
      send(S.tune[group][axis] + (+b.dataset.d) * step * m);
    }));
    row._set = (v) => {
      if (document.activeElement !== box) box.value = (+v).toFixed(isPos ? 3 : 1);
      if (document.activeElement !== range) range.value = v;
    };
    return row;
  }
  const rows = { pos: {}, rot: {} };
  ['x', 'y', 'z'].forEach((a) => {
    rows.pos[a] = axisRow('pos', a); $('posRows').appendChild(rows.pos[a]);
    rows.rot[a] = axisRow('rot', a); $('rotRows').appendChild(rows.rot[a]);
  });
  function setRows() {
    ['x', 'y', 'z'].forEach((a) => { rows.pos[a]._set(S.tune.pos[a]); rows.rot[a]._set(S.tune.rot[a]); });
  }

  /* ---------- builders ---------- */
  function buildBags() {
    const el = $('baglist');
    el.innerHTML = '';
    const q = search.toLowerCase();
    const list = S.bags.filter((b) => !q || b.label.toLowerCase().includes(q) || (b.model || '').toLowerCase().includes(q) || b.key.toLowerCase().includes(q));
    $('bagCount').innerHTML = `<b>${list.length}</b> ${list.length === 1 ? 'bag' : 'bags'}`;
    if (!list.length) {
      el.innerHTML = `<div class="empty">${ic('<path d="M3 9l2-5h14l2 5M3 9v10a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V9M3 9h18"/>')}<b>No bags</b><span>${S.bags.length ? 'Nothing matches that search.' : 'Add entries to Config.Backpacks.'}</span></div>`;
      return;
    }
    list.forEach((b) => {
      const d = document.createElement('div');
      d.className = 'bagitem' + (b.key === S.current ? ' on' : '');
      d.innerHTML = `<b>${esc(b.label)}</b><span>${esc(b.model)}</span>
        <div class="tags">
          <span class="tag">${b.slots} slots</span>
          ${b.variants.length ? `<span class="tag live">${b.variants.length} skins</span>` : ''}
          ${b.carry && b.carry !== 'none' ? '<span class="tag live">pose</span>' : ''}
          ${b.saved ? '<span class="tag live">saved</span>' : (b.tuned ? '<span class="tag">tuned</span>' : '')}
          ${b.job ? `<span class="tag warn">${esc(b.job)}</span>` : ''}
        </div>`;
      d.onclick = () => post('studio:select', { key: b.key });
      el.appendChild(d);
    });
    const on = el.querySelector('.on');
    if (on && on.scrollIntoViewIfNeeded) on.scrollIntoViewIfNeeded(false);
  }

  function buildBones() {
    const s = $('bone');
    s.innerHTML = '';
    const groups = {};
    S.bones.forEach((b) => {
      if (!groups[b.group]) {
        groups[b.group] = document.createElement('optgroup');
        groups[b.group].label = b.group;
        s.appendChild(groups[b.group]);
      }
      const o = document.createElement('option');
      o.value = b.id;
      o.textContent = `${b.label}  ·  ${b.id}`;
      groups[b.group].appendChild(o);
    });
    if (!S.bones.find((b) => b.id === S.tune.bone)) {
      const o = document.createElement('option');
      o.value = S.tune.bone; o.textContent = `Custom bone · ${S.tune.bone}`;
      s.appendChild(o);
    }
    s.value = S.tune.bone;
  }
  $('bone').addEventListener('change', (e) => post('studio:bone', { bone: parseInt(e.target.value, 10) }));

  function buildPresets() {
    const el = $('presets');
    el.innerHTML = '';
    S.presets.forEach((p) => {
      const b = document.createElement('button');
      b.textContent = p.label;
      b.onclick = () => post('studio:preset', { key: p.key });
      el.appendChild(b);
    });
  }

  function buildPoses() {
    const el = $('poseChips');
    el.innerHTML = '';
    if (!S.poses.length) { el.innerHTML = '<span class="note" style="margin:0">No poses in Config.Carry.Poses.</span>'; return; }
    [{ key: null, label: 'None' }, ...S.poses].forEach((p) => {
      const b = document.createElement('button');
      b.textContent = p.label;
      if ((S.pose || null) === p.key) b.classList.add('on');
      b.onclick = () => post('studio:pose', { key: p.key });
      el.appendChild(b);
    });
  }

  function buildVariants() {
    const el = $('variants');
    el.innerHTML = '';
    const b = bag();
    if (!b || !b.variants.length) {
      $('varHint').textContent = '';
      el.innerHTML = `<div class="empty">${ic('<circle cx="12" cy="12" r="9"/><path d="M12 8v4M12 16h.01"/>')}<b>One finish</b><span>Add a variants table to this bag in Config.Backpacks.</span></div>`;
      return;
    }
    $('varHint').textContent = b.variants.some((v) => v.model) ? 'separate models' : 'texture skins';
    b.variants.forEach((v) => {
      const btn = document.createElement('button');
      btn.innerHTML = `${esc(v.label)}<small>${v.model ? esc(v.model) : '#' + (v.texture || 0)}</small>`;
      if (v.id === S.variant) btn.classList.add('on');
      btn.onclick = () => post('studio:variant', { id: v.id });
      el.appendChild(btn);
    });
  }

  function buildLook() {
    const b = bag();
    if (!b) return;
    const keep = (id, v) => { if (document.activeElement !== $(id)) $(id).value = v; };
    keep('fSlots', b.slots);
    keep('fWeight', +(b.weight / 1000).toFixed(2));
    keep('fPrice', b.price == null ? '' : b.price);
    keep('fLabel', b.label);
    ['fSlots', 'fWeight', 'fPrice', 'fLabel', 'saveStorage', 'saveCarry'].forEach((id) => { $(id).disabled = !S.admin; });

    const c = $('fCarry');
    c.innerHTML = S.styles.map((s) => `<option value="${esc(s.key)}">${esc(s.label)}</option>`).join('');
    c.value = b.carry || 'none';
    const p = $('fPose');
    p.innerHTML = '<option value="">Style default</option>' + S.poses.map((x) => `<option value="${esc(x.key)}">${esc(x.label)}</option>`).join('');
    p.value = b.pose || '';
  }

  function buildIcon() {
    const st = S.icon || {};
    $('noShot').classList.toggle('hide', !!st.hasScreenshot);
    $('iconSize').textContent = `${st.size || 512} × ${st.size || 512} png`;
    $('iconToggle').innerHTML = st.active
      ? ic('<rect x="6" y="6" width="12" height="12" rx="2"/>') + 'Leave icon studio'
      : ic('<path d="M6 4l14 8-14 8z"/>') + 'Enter icon studio';
    document.querySelectorAll('[data-chroma]').forEach((b) => b.classList.toggle('on', b.dataset.chroma === st.chroma));
    $('iconGuide').classList.toggle('hide', !st.active);
    ['capOne', 'capAll'].forEach((id) => { $(id).disabled = !st.active || !st.hasScreenshot || !!st.batch; });
    if (st.orbit && document.activeElement !== $('iconZoom')) {
      $('iconZoom').value = st.orbit.zoom; $('iconZoomVal').value = (+st.orbit.zoom).toFixed(2);
    }
    const running = !!st.batch;
    $('batchBar').classList.toggle('hide', !running);
    $('batchCancelRow').classList.toggle('hide', !running);
    $('batchInfo').textContent = running ? `${st.batch.i} / ${st.batch.n}` : '';
    if (running) $('batchBar').firstElementChild.style.width = `${(st.batch.i / Math.max(1, st.batch.n)) * 100}%`;
  }

  function buildShots() {
    const el = $('shots');
    if (!shots.length) return;
    el.innerHTML = shots.map((s) => `<figure><img src="${s.png}"><figcaption>${esc(s.name)}</figcaption></figure>`).join('');
  }

  /* ---------- text output ---------- */
  const f3 = (v) => (+v).toFixed(3), f1 = (v) => (+v).toFixed(1);
  function offsetText() {
    const t = S.tune;
    return `offset = {
    bone = ${t.bone},
    pos  = { x = ${f3(t.pos.x)}, y = ${f3(t.pos.y)}, z = ${f3(t.pos.z)} },
    rot  = { x = ${f1(t.rot.x)}, y = ${f1(t.rot.y)}, z = ${f1(t.rot.z)} },
},`;
  }
  function entryText() {
    const b = bag();
    if (!b) return '';
    const t = S.tune;
    let vars = '';
    if (b.variants.length) {
      vars = '\n    variants = {\n' + b.variants.map((v) => v.model
        ? `        { label = '${v.label}', model = '${v.model}' },`
        : `        { label = '${v.label}', texture = ${v.texture || 0} },`).join('\n') + '\n    },';
    }
    const extra = [
      b.carry && b.carry !== 'none' ? `    carry    = '${b.carry}',` : '',
      b.pose ? `    pose     = '${b.pose}',` : '',
    ].filter(Boolean).join('\n');
    return `['${b.key}'] = {
    label    = '${b.label}',
    model    = '${b.model}',
    category = '${b.category || 'backpack'}',
    theme    = '${b.theme || 'realistic'}',${b.price != null ? `\n    price    = ${b.price},` : ''}
    slots    = ${b.slots},
    weight   = ${b.weight},${extra ? '\n' + extra : ''}
    offset   = {
        bone = ${t.bone},
        pos  = { x = ${f3(t.pos.x)}, y = ${f3(t.pos.y)}, z = ${f3(t.pos.z)} },
        rot  = { x = ${f1(t.rot.x)}, y = ${f1(t.rot.y)}, z = ${f1(t.rot.z)} },
    },${vars}
},`;
  }
  function renderText() {
    $('out').textContent = offsetText();
    $('outEntry').textContent = entryText();
  }

  /* ---------- refresh ---------- */
  function refresh(data) {
    S = data;
    const b = bag();
    $('model').textContent = b ? b.label : '—';
    $('statusBag').innerHTML = b ? `<b>${b.slots}</b> slots · <b>${(b.weight / 1000).toFixed(1)}</b>kg${b.price != null ? ` · <b>$${b.price.toLocaleString()}</b>` : ''}` : '';
    $('calDot').classList.toggle('warn', !S.calibrated);
    $('rotHint').textContent = S.calibrated ? "around the bag's centre" : 'raw axes · measured mode';
    $('ax-yaw').textContent = S.calibrated ? 'yaw' : 'z';
    $('ax-pitch').textContent = S.calibrated ? 'pitch' : 'x';
    $('ax-roll').textContent = S.calibrated ? 'roll' : 'y';
    $('focusBtn').classList.toggle('on', !S.cam || S.cam.focus > 0.5);
    $('save').disabled = !S.admin;
    buildBags(); buildBones(); buildPresets(); buildPoses(); buildSteps();
    buildVariants(); buildLook(); buildIcon(); setRows(); renderText();
  }

  function tuneOnly(t) {
    S.tune = t;
    if (document.activeElement !== $('bone')) $('bone').value = t.bone;
    setRows(); renderText();
  }

  /* ---------- tabs ---------- */
  document.querySelectorAll('.tabs button').forEach((b) => {
    b.onclick = () => {
      tab = b.dataset.tab;
      document.querySelectorAll('.tabs button').forEach((x) => x.classList.toggle('on', x === b));
      document.querySelectorAll('.page').forEach((p) => p.classList.toggle('on', p.id === 'page-' + tab));
      $('foot').classList.toggle('hide', tab === 'icon');
      $('hints').classList.toggle('hide', tab !== 'fit');
    };
  });

  /* ---------- orbit / zoom on the empty middle of the screen ---------- */
  (function () {
    const c = $('orbit');
    let drag = false, lx = 0, ly = 0, ax = 0, ay = 0, raf = null;
    const flush = () => {
      raf = null;
      if (!ax && !ay) return;
      if (S.icon && S.icon.active) post('icon:orbit', { dx: ax, dy: ay });
      else post('studio:cam', { dx: ax, dy: ay });
      ax = 0; ay = 0;
    };
    c.addEventListener('pointerdown', (e) => { drag = true; lx = e.clientX; ly = e.clientY; c.classList.add('drag'); c.setPointerCapture(e.pointerId); });
    c.addEventListener('pointerup', () => { drag = false; c.classList.remove('drag'); });
    c.addEventListener('pointermove', (e) => {
      if (!drag) return;
      ax += e.clientX - lx; ay += e.clientY - ly; lx = e.clientX; ly = e.clientY;
      if (!raf) raf = requestAnimationFrame(flush);
    });
    c.addEventListener('wheel', (e) => {
      e.preventDefault();
      if (S.icon && S.icon.active) post('icon:zoom', { delta: e.deltaY * 0.001 });
      else post('studio:cam', { zoom: e.deltaY * 0.0015 });
    }, { passive: false });
  })();

  /* ---------- buttons ---------- */
  document.querySelectorAll('[data-cam]').forEach((b) => { b.onclick = () => post('studio:cam', { preset: b.dataset.cam }); });
  $('focusBtn').onclick = () => {
    const on = !$('focusBtn').classList.contains('on');
    $('focusBtn').classList.toggle('on', on);
    post('studio:cam', { focus: on });
  };
  document.querySelectorAll('[data-anim]').forEach((b) => { b.onclick = () => post('studio:anim', { name: b.dataset.anim }); });

  $('revert').onclick = () => post('studio:revert');
  $('factory').onclick = () => post('studio:factory');
  $('clearSaved').onclick = () => post('studio:clearSaved');
  $('save').onclick = () => post('studio:save', { offset: true });

  $('saveStorage').onclick = () => {
    const price = $('fPrice').value.trim();
    post('studio:save', { storage: {
      slots: parseInt($('fSlots').value, 10),
      weight: Math.round(parseFloat($('fWeight').value) * 1000),
      price: price === '' ? null : parseInt(price, 10),
      label: $('fLabel').value.trim(),
    } });
  };
  $('saveCarry').onclick = () => post('studio:save', { carry: { style: $('fCarry').value, pose: $('fPose').value || undefined } });

  $('bagSearch').addEventListener('input', (e) => { search = e.target.value.trim(); buildBags(); });

  // icon tab
  $('iconToggle').onclick = () => post('icon:toggle', { on: !(S.icon && S.icon.active) });
  document.querySelectorAll('[data-chroma]').forEach((b) => { b.onclick = () => post('icon:chroma', { color: b.dataset.chroma }); });
  document.querySelectorAll('[data-yaw]').forEach((b) => { b.onclick = () => post('icon:orbit', { yaw: +b.dataset.yaw, elev: +b.dataset.elev }); });
  $('iconZoom').addEventListener('input', () => {
    $('iconZoomVal').value = (+$('iconZoom').value).toFixed(2);
    post('icon:zoom', { set: +$('iconZoom').value });
  });
  $('iconZoomVal').addEventListener('change', () => {
    const v = parseFloat($('iconZoomVal').value);
    if (!isNaN(v)) { $('iconZoom').value = v; post('icon:zoom', { set: v }); }
  });
  $('capOne').onclick = () => post('icon:capture');
  $('capAll').onclick = () => post('icon:batch', { variants: $('capVariants').checked });
  $('batchCancel').onclick = () => post('icon:cancel');

  window.addEventListener('nb:icon', (e) => {
    shots.unshift(e.detail);
    if (shots.length > 8) shots.pop();
    buildShots();
  });

  function copy(text) {
    const ta = document.createElement('textarea');
    ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
    document.body.appendChild(ta); ta.select();
    try { document.execCommand('copy'); } catch (err) { /* clipboard blocked */ }
    document.body.removeChild(ta);
    post('studio:copied');
  }
  $('copy').onclick = () => copy(tab === 'look' ? entryText() : offsetText());

  const close = () => { $('studio').classList.remove('open'); post('studio:close'); };
  $('close').onclick = close;

  /* ---------- keyboard ---------- */
  const KEYMAP = {
    ArrowLeft: () => ['m', 'r', -1], ArrowRight: () => ['m', 'r', 1],
    ArrowUp: () => ['m', 'f', 1], ArrowDown: () => ['m', 'f', -1],
    PageUp: () => ['m', 'u', 1], PageDown: () => ['m', 'u', -1],
    q: () => ['r', 'yaw', 1], e: () => ['r', 'yaw', -1],
    r: () => ['r', 'pitch', 1], f: () => ['r', 'pitch', -1],
    z: () => ['r', 'roll', -1], c: () => ['r', 'roll', 1],
  };
  document.addEventListener('keydown', (e) => {
    if (!open()) return;
    if (e.key === 'Escape') { e.preventDefault(); return close(); }
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') { e.preventDefault(); return post('studio:save', { offset: true }); }
    if (typing(document.activeElement)) return;
    if (e.key === '?') { $('hints').classList.toggle('hide'); return; }
    const fn = KEYMAP[e.key] || KEYMAP[e.key.toLowerCase()];
    if (!fn || tab === 'icon') return;
    e.preventDefault();
    const [kind, axis, dir] = fn();
    if (kind === 'm') move(axis, dir, mult(e)); else rotate(axis, dir, mult(e));
  });

  /* ---------- messages from Lua ---------- */
  window.addEventListener('message', (e) => {
    const { action, data } = e.data || {};
    switch (action) {
      case 'studioOpen': refresh(data); $('studio').classList.add('open'); break;
      case 'studioRefresh': refresh(data); break;
      case 'studioTune': if (data && data.tune) tuneOnly(data.tune); break;
      case 'studioClose': $('studio').classList.remove('open'); break;
      case 'iconState': S.icon = data; buildIcon(); break;
      case 'iconHide': $('studio').classList.add('shooting'); break;
      case 'iconShow': $('studio').classList.remove('shooting'); break;
      default: break;
    }
  });
})();
