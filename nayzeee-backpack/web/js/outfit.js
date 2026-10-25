/* Outfit bag UI — NAYZEEE v3 window */
(function () {
  const $ = (id) => document.getElementById(id);
  const post = (name, data) => fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data || {})
  }).then((r) => r.json()).catch(() => null);
  const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const ic = (d) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;

  const I = {
    lock: ic('<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>'),
    unlock: ic('<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 7.5-2"/>'),
    star: ic('<path d="M12 3.5l2.6 5.3 5.8.8-4.2 4.1 1 5.8L12 16.8l-5.2 2.7 1-5.8-4.2-4.1 5.8-.8z"/>'),
    down: ic('<path d="M6 9l6 6 6-6"/>'),
    x: ic('<path d="M6 6l12 12M18 6L6 18"/>'),
    refresh: ic('<path d="M20 11a8 8 0 0 0-14.6-4.5M4 4v4h4"/><path d="M4 13a8 8 0 0 0 14.6 4.5M20 20v-4h-4"/>'),
    pen: ic('<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="M13.5 6.5l4 4"/>'),
    share: ic('<circle cx="6" cy="12" r="2.5"/><circle cx="18" cy="6" r="2.5"/><circle cx="18" cy="18" r="2.5"/><path d="M8.2 10.9l7.6-3.8M8.2 13.1l7.6 3.8"/>'),
    copy: ic('<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/>'),
    trash: ic('<path d="M4 7h16M10 11v6M14 11v6"/><path d="M6 7l1 13h10l1-13M9 7V4h6v3"/>'),
    plus: ic('<path d="M12 5v14M5 12h14"/>'),
    alert: ic('<path d="M12 4l9 16H3z"/><path d="M12 10v4M12 17h.01"/>'),
    paste: ic('<rect x="8" y="3" width="8" height="4" rx="1"/><path d="M16 5h2a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2h2"/><path d="M9 14h6M12 11v6"/>'),
    check: ic('<path d="M5 12.5l4.5 4.5L19 7.5"/>'),
  };

  // the order you'd get dressed in
  const PIECES = [
    ['hair', 'Hair'], ['hat', 'Hat'], ['mask', 'Mask'], ['glasses', 'Glasses'], ['ear', 'Ear'],
    ['torso2', 'Jacket'], ['t-shirt', 'Shirt'], ['vest', 'Vest'], ['arms', 'Arms'], ['neck', 'Neck'],
    ['badge', 'Badge'], ['bag', 'Bag'], ['pants', 'Pants'], ['shoes', 'Shoes'],
    ['watch', 'Watch'], ['bracelet', 'Bracelet'],
  ];

  let S = {};
  let filter = 'all', search = '', expanded = null, renaming = null, previewing = null;
  let view = 'list', modal = null;

  const root = $('outfit');
  const isOpen = () => !root.classList.contains('hide');
  const count = () => Object.keys(S.outfits || {}).length;
  const tagOf = (key) => (S.tags || []).find((t) => t.key === key);
  const wrongModel = (o) => o.model && S.model && o.model !== S.model;

  function initials(label) {
    const words = String(label || '').replace(/[^\p{L}\p{N} ]/gu, ' ').trim().split(/\s+/).filter(Boolean);
    if (!words.length) return '··';
    return (words.length > 1 ? words[0][0] + words[1][0] : words[0].slice(0, 2)).toUpperCase();
  }

  function rgba(hex, a) {
    const m = /^#?([0-9a-f]{6})$/i.exec(hex || '');
    if (!m) return `rgba(255,255,255,${a})`;
    const n = parseInt(m[1], 16);
    return `rgba(${n >> 16},${(n >> 8) & 255},${n & 255},${a})`;
  }

  function tint(node, color) {
    node.style.setProperty('--c', color);
    node.style.setProperty('--ce', rgba(color, 0.4));
    node.style.setProperty('--cw', rgba(color, 0.11));
  }

  /* ---------- toast ---------- */

  let toastTimer = 0;
  function toast(title, text) {
    $('obToastIcon').innerHTML = I.check;
    $('obToastTitle').textContent = title;
    $('obToastText').textContent = text || '';
    const t = $('obToast');
    t.classList.remove('show');
    void t.offsetWidth; // restart the progress bar
    t.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.classList.remove('show'), 2200);
  }

  // CEF has no clipboard permission; the old execCommand route still works
  function copyText(text) {
    const ta = el('textarea');
    ta.value = text;
    ta.style.cssText = 'position:fixed;left:-9999px;top:0';
    document.body.appendChild(ta);
    ta.select();
    let ok = false;
    try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
    ta.remove();
    return ok;
  }

  function unpreview() {
    if (previewing) { previewing = null; post('ob:unpreview'); }
  }

  function entries() {
    const q = search.trim().toLowerCase();
    return Object.entries(S.outfits || {})
      .filter(([, o]) => {
        if (q && !o.label.toLowerCase().includes(q)) return false;
        if (filter === 'fav') return !!o.fav;
        if (filter !== 'all') return o.tag === filter;
        return true;
      })
      .sort(([, a], [, b]) => (!!b.fav - !!a.fav) || a.label.localeCompare(b.label));
  }

  /* ---------- render ---------- */

  function renderHead() {
    const n = count(), max = S.maxOutfits || 12;
    $('obCount').textContent = n;
    $('obMax').textContent = max;
    $('obMeter').style.width = `${Math.min(100, (n / max) * 100)}%`;
    $('obMeter').parentElement.classList.toggle('full', n >= max);
    $('obDot').classList.toggle('warn', n >= max);

    $('obSub').textContent = S.quick ? 'Quick change'
      : !S.isOwner ? 'Their bag'
      : S.public ? 'Unlocked' : 'Locked';

    const lock = $('obLock');
    lock.classList.toggle('hide', !S.isOwner || !!S.quick);
    lock.classList.toggle('public', !!S.public);
    lock.innerHTML = S.public ? I.unlock : I.lock;
    lock.title = S.public ? 'Unlocked: people nearby can open it' : 'Locked: only you can open it';

    $('obImportBtn').classList.toggle('hide', !S.canImport);
    $('obCodeBtn').classList.toggle('hide', !(S.canShare && S.canSave));
    $('obSave').disabled = n >= max;
    $('obSave').classList.toggle('hide', !S.canSave);
    $('obUndo').classList.toggle('hide', !S.undo);
    // nothing in the footer for a visitor who can't save and has nothing to undo
    $('obSave').parentElement.classList.toggle('hide', !S.canSave && !S.undo);
  }

  function renderFilters() {
    const box = $('obTags');
    box.innerHTML = '';
    const all = Object.values(S.outfits || {});
    const chips = [{ key: 'all', label: `All ${all.length}` }];
    if (all.some((o) => o.fav)) chips.push({ key: 'fav', label: 'Pinned', color: 'var(--amber)' });
    const used = new Set(all.map((o) => o.tag).filter(Boolean));
    for (const t of S.tags || []) if (used.has(t.key)) chips.push(t);

    if (!chips.some((c) => c.key === filter)) filter = 'all';
    box.classList.toggle('hide', chips.length < 2 || view !== 'list');
    for (const c of chips) {
      const b = el('button', 'ob-chip' + (filter === c.key ? ' on' : ''), (c.color ? '<i></i>' : '') + esc(c.label));
      if (c.color) b.style.setProperty('--c', c.color);
      b.onclick = () => { filter = c.key; render(); };
      box.appendChild(b);
    }
  }

  function row(id, o, i) {
    const off = wrongModel(o);
    const tag = tagOf(o.tag);
    const pieces = PIECES.filter(([k]) => o.outfit && o.outfit[k]);

    const r = el('div', 'ob-row' + (expanded === id ? ' open' : '') + (off ? ' off' : ''));
    r.style.setProperty('--i', i);

    const head = el('div', 'ob-head');

    const av = el('div', 'ob-av' + (tag ? ' tagged' : ''), esc(initials(o.label)));
    if (tag) tint(av, tag.color);

    const txt = el('div', 'ob-txt');
    if (renaming === id) {
      const input = el('input');
      input.maxLength = S.maxLabel || 30;
      input.value = o.label;
      input.onclick = (e) => e.stopPropagation();
      input.onkeydown = (e) => {
        if (e.key === 'Enter') commitRename(id, input.value);
        if (e.key === 'Escape') { e.stopPropagation(); renaming = null; render(); }
      };
      input.onblur = () => commitRename(id, input.value);
      txt.appendChild(input);
      setTimeout(() => { input.focus(); input.select(); }, 0);
    } else {
      const sub = off
        ? '<span class="warn">Saved on another character model</span>'
        : `<span>${pieces.length} piece${pieces.length === 1 ? '' : 's'}${tag ? ' · ' + esc(tag.label) : ''}</span>`;
      txt.innerHTML = `<b><em>${esc(o.label)}</em></b>${sub}`;
    }

    const pin = el('button', 'ob-pin' + (o.fav ? ' on' : '') + (S.canSave ? '' : ' ro'), I.star);
    pin.title = o.fav ? 'Unpin' : 'Pin to the top';
    pin.onclick = (e) => { e.stopPropagation(); o.fav = !o.fav; post('ob:favorite', { id }); render(); };

    const wear = el('button', 'ob-wear', 'Wear');
    wear.disabled = off;
    wear.onclick = (e) => { e.stopPropagation(); unpreview(); post('ob:wear', { id, which: 'all' }); };

    const more = el('button', 'ob-more', I.down);
    more.title = 'More';

    head.append(av, txt, pin, wear, more);
    head.onclick = () => { if (renaming) return; expanded = expanded === id ? null : id; render(); };
    if (S.preview && !off) {
      head.onmouseenter = () => { if (renaming === id) return; previewing = id; post('ob:preview', { id }); };
      head.onmouseleave = () => { if (previewing === id) unpreview(); };
    }
    r.appendChild(head);

    /* detail */
    const d = el('div', 'ob-detail');
    if (!off && pieces.length) {
      d.appendChild(el('div', 'ob-lbl', 'Wear one piece'));
      const box = el('div', 'ob-pieces');
      for (const [k, label] of pieces) {
        const p = el('button', 'ob-piece', `<img src="images/outfit/${k}.png" alt="">${label}`);
        p.onclick = (e) => { e.stopPropagation(); unpreview(); post('ob:wear', { id, which: k }); };
        box.appendChild(p);
      }
      d.appendChild(box);
    }

    if (S.canSave && (S.tags || []).length) {
      d.appendChild(el('div', 'ob-lbl', 'Tag'));
      const sw = el('div', 'ob-swatches');
      const none = el('button', 'ob-sw none' + (!o.tag ? ' on' : ''), I.x);
      none.title = 'No tag';
      none.onclick = (e) => { e.stopPropagation(); o.tag = null; post('ob:tag', { id, tag: null }); render(); };
      sw.appendChild(none);
      for (const t of S.tags) {
        const b = el('button', 'ob-sw' + (o.tag === t.key ? ' on' : ''));
        b.style.setProperty('--c', t.color);
        b.title = t.label;
        b.onclick = (e) => { e.stopPropagation(); o.tag = t.key; post('ob:tag', { id, tag: t.key }); render(); };
        sw.appendChild(b);
      }
      d.appendChild(sw);
    }

    const acts = el('div', 'ob-actions');
    const act = (icon, label, fn, cls) => {
      const b = el('button', 'btn-line' + (cls ? ' ' + cls : ''), icon + label);
      b.onclick = (e) => { e.stopPropagation(); fn(); };
      acts.appendChild(b);
    };
    if (S.canSave) {
      act(I.refresh, 'Update', () => post('ob:overwrite', { id }));
      act(I.pen, 'Rename', () => { renaming = id; render(); });
    }
    if (S.canCopy) act(I.copy, 'Copy to mine', () => post('ob:copy', { id }));
    if (S.canShare) act(I.share, 'Share', () => share(id));
    if (S.canSave) act(I.trash, 'Delete', () => ask('delete', id), 'danger');
    if (acts.children.length) d.appendChild(acts);

    r.appendChild(d);
    return r;
  }

  function render() {
    if (!isOpen()) return;
    renderHead();
    renderFilters();

    const importing = view === 'import';
    $('obImport').classList.toggle('hide', !importing);

    const list = entries();
    const box = $('obList');
    box.innerHTML = '';
    list.forEach(([id, o], i) => box.appendChild(row(id, o, i)));

    const empty = list.length === 0;
    box.classList.toggle('hide', empty || importing);
    $('obEmpty').classList.toggle('hide', !empty || importing);
    if (empty) {
      const none = count() === 0;
      $('obEmptyTitle').textContent = none ? 'No outfits saved yet' : 'Nothing matches';
      $('obEmptyText').textContent = none
        ? (S.canSave ? 'Put a look together, then press Save current outfit.' : 'This bag is empty.')
        : 'Try another search or filter.';
    }
  }

  function commitRename(id, value) {
    if (renaming !== id) return;
    renaming = null;
    const label = value.trim();
    const o = S.outfits[id];
    if (o && label && label !== o.label) { o.label = label; post('ob:rename', { id, label }); }
    render();
  }

  /* ---------- share / modal ---------- */

  async function share(id) {
    const r = await post('ob:share', { id });
    if (!r || !r.code) return;
    if (copyText(r.code)) toast('Share code copied', 'Send it to whoever wants the look.');
    else ask('showcode', r.code);
  }

  function ask(kind, arg) {
    modal = { kind, arg };
    const input = $('obModalInput');
    const ok = $('obModalOk');
    const icon = $('obModalIcon');
    input.classList.add('hide');
    input.readOnly = false;
    ok.classList.remove('hide');
    $('obModalNo').textContent = 'Cancel';

    if (kind === 'delete') {
      icon.className = 'ob-warn';
      icon.innerHTML = I.alert;
      $('obModalTitle').textContent = 'Delete this outfit?';
      $('obModalText').textContent = `"${(S.outfits[arg] || {}).label || ''}" will be removed from the bag. This can't be undone.`;
      ok.className = 'btn-red';
      ok.textContent = 'Delete outfit';
      $('obModalNo').textContent = 'Keep it';
    } else if (kind === 'code') {
      icon.className = 'ob-warn ok';
      icon.innerHTML = I.paste;
      $('obModalTitle').textContent = 'Paste a share code';
      $('obModalText').textContent = 'Someone sent you a look? Paste their code to add it to this bag.';
      input.value = '';
      input.classList.remove('hide');
      ok.className = 'btn-teal';
      ok.textContent = 'Add outfit';
      setTimeout(() => input.focus(), 0);
    } else if (kind === 'showcode') {
      icon.className = 'ob-warn ok';
      icon.innerHTML = I.share;
      $('obModalTitle').textContent = 'Share code';
      $('obModalText').textContent = 'Copy this and send it to whoever wants the look.';
      input.value = arg;
      input.readOnly = true;
      input.classList.remove('hide');
      ok.classList.add('hide');
      $('obModalNo').textContent = 'Done';
      setTimeout(() => input.select(), 0);
    }
    $('obModal').classList.remove('hide');
  }

  function closeModal() {
    modal = null;
    $('obModal').classList.add('hide');
  }

  $('obModalOk').onclick = () => {
    if (!modal) return;
    if (modal.kind === 'delete') {
      unpreview();
      post('ob:delete', { id: modal.arg });
    } else if (modal.kind === 'code') {
      const code = $('obModalInput').value.trim();
      if (!code) return;
      post('ob:importcode', { code });
    }
    closeModal();
  };
  $('obModalNo').onclick = closeModal;
  $('obModalInput').onkeydown = (e) => {
    if (e.key === 'Enter' && modal && modal.kind === 'code') { e.preventDefault(); $('obModalOk').click(); }
  };

  /* ---------- save ---------- */

  function openSave() {
    $('obSaveForm').classList.remove('hide');
    const input = $('obSaveName');
    input.maxLength = S.maxLabel || 30;
    input.value = `Outfit ${count() + 1}`;
    input.focus();
    input.select();
  }
  function closeSave() { $('obSaveForm').classList.add('hide'); }
  function submitSave() {
    const label = $('obSaveName').value.trim();
    if (!label) return;
    closeSave();
    post('ob:save', { label });
  }

  $('obSave').onclick = openSave;
  $('obSaveOk').onclick = submitSave;
  $('obSaveNo').onclick = closeSave;
  $('obSaveName').onkeydown = (e) => {
    if (e.key === 'Enter') submitSave();
    if (e.key === 'Escape') { e.stopPropagation(); closeSave(); }
  };

  /* ---------- toolbar ---------- */

  $('obSearch').oninput = (e) => { search = e.target.value; render(); };
  $('obLock').onclick = () => { S.public = !S.public; post('ob:togglelock'); render(); };
  $('obUndo').onclick = () => { unpreview(); post('ob:undo'); };
  $('obCodeBtn').onclick = () => ask('code');

  $('obImportBtn').onclick = async () => {
    view = 'import';
    $('obImportList').innerHTML = '';
    $('obImportEmpty').classList.add('hide');
    render();
    const r = await post('ob:wardrobe');
    if (view !== 'import') return;
    const rows = (r && r.outfits) || [];
    $('obImportEmpty').classList.toggle('hide', rows.length > 0);
    $('obImportList').classList.toggle('hide', rows.length === 0);
    rows.forEach((w, i) => {
      const line = el('div', 'ob-imp');
      line.style.setProperty('--i', i);
      line.innerHTML = `<div class="ob-av">${esc(initials(w.name))}</div><div class="ob-txt"><b><em>${esc(w.name)}</em></b><span>Wardrobe outfit</span></div>`;
      const add = el('button', 'ob-wear', 'Add');
      add.onclick = () => { post('ob:import', { id: w.id }); view = 'list'; render(); };
      line.appendChild(add);
      $('obImportList').appendChild(line);
    });
  };
  $('obImportBack').onclick = () => { view = 'list'; render(); };

  /* ---------- open / close ---------- */

  function close() { post('ob:close'); }
  $('obClose').onclick = close;

  document.addEventListener('keydown', (e) => {
    if (!isOpen()) return;
    const typing = /^(INPUT|TEXTAREA)$/.test((document.activeElement || {}).tagName || '');
    if (e.key === 'Escape') {
      if (modal) return closeModal();
      if (renaming) return;
      if (!$('obSaveForm').classList.contains('hide')) return closeSave();
      if (view === 'import') { view = 'list'; return render(); }
      return close();
    }
    if (typing || modal) return;
    // 1-9 wears the outfit in that spot
    if (/^[1-9]$/.test(e.key) && view === 'list') {
      const hit = entries()[Number(e.key) - 1];
      if (hit && !wrongModel(hit[1])) { unpreview(); post('ob:wear', { id: hit[0], which: 'all' }); }
    }
    if (e.key === '/') { e.preventDefault(); $('obSearch').focus(); }
  });

  window.addEventListener('message', (e) => {
    const { action, data } = e.data || {};
    switch (action) {
      case 'obOpen':
        S = data || {};
        S.outfits = S.outfits || {};
        filter = 'all'; search = ''; expanded = null; renaming = null; previewing = null; view = 'list';
        $('obSearch').value = '';
        closeSave(); closeModal();
        root.classList.remove('hide', 'leaving');
        render();
        break;
      case 'obSync':
        if (!data) break;
        S.outfits = data.outfits || {};
        if (typeof data.public === 'boolean') S.public = data.public;
        if (expanded && !S.outfits[expanded]) expanded = null;
        if (renaming && !S.outfits[renaming]) renaming = null;
        if (modal && modal.kind === 'delete' && !S.outfits[modal.arg]) closeModal();
        render();
        break;
      case 'obUndo':
        S.undo = !!(data && data.available);
        if (isOpen()) renderHead();
        break;
      case 'obClose':
        if (!isOpen()) break;
        closeModal();
        previewing = null;
        root.classList.add('leaving');
        setTimeout(() => { if (root.classList.contains('leaving')) root.classList.add('hide'); }, 160);
        break;
      default: break;
    }
  });
})();
