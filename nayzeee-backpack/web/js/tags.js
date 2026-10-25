/* Name tags: renderer (world + preview) and the editor */
(function () {
  const $ = (id) => document.getElementById(id);
  const post = (name, data) => fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data || {})
  }).catch(() => {});
  const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  let CFG = { fonts: [], colors: [], styles: [], effects: [], particles: [], maxLength: 18, customColors: true };
  const family = (key) => ((CFG.fonts || []).find((f) => f.key === key) || {}).family || 'Lexend';

  const LOCK = '<svg class="nbt-lock" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4"><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>';

  /* ---------- renderer ---------- */

  const GLYPHS = {
    sparkles: ['✦', '✧'], hearts: ['♥'], stars: ['★', '✦'], snow: ['❄', '❅', '•'],
    money: ['$'], notes: ['♪', '♫', '♬'], embers: [''], bubbles: [''],
  };
  const rnd = (a, b) => a + Math.random() * (b - a);

  function particles(fx, type) {
    if (fx.dataset.p === type) return;
    fx.dataset.p = type;
    fx.className = 'nbt-fx p-' + type;
    fx.innerHTML = '';
    const g = GLYPHS[type];
    if (!g) return;
    const n = type === 'snow' ? 12 : 10;
    for (let i = 0; i < n; i++) {
      const b = el('b', null, g[i % g.length]);
      b.style.left = `${rnd(4, 92)}%`;
      b.style.fontSize = `${rnd(10, 16).toFixed(1)}px`;
      b.style.setProperty('--x', `${rnd(-14, 14).toFixed(1)}px`);
      b.style.setProperty('--y', `${rnd(5, 75).toFixed(0)}%`);
      b.style.setProperty('--s', `${rnd(5, 10).toFixed(1)}px`);
      b.style.setProperty('--d', `${rnd(1.8, 3.4).toFixed(2)}s`);
      b.style.setProperty('--w', `${rnd(0, 3.2).toFixed(2)}s`);
      fx.appendChild(b);
    }
  }

  function apply(root, tag, locked) {
    tag = tag || {};
    root.className = `nbt s-${tag.s || 'dark'} e-${tag.e || 'none'}${tag.c2 ? ' grad' : ''}`;
    root.style.setProperty('--c1', tag.c || '#ffffff');
    root.style.setProperty('--c2', tag.c2 || tag.c || '#ffffff');
    root.style.setProperty('--font', `'${family(tag.f)}'`);

    const text = root.querySelector('.nbt-text');
    const value = tag.t || '';
    const key = `${value}|${tag.e}`;
    if (text.dataset.k !== key) {
      text.dataset.k = key;
      if (tag.e === 'wave') {
        text.innerHTML = Array.from(value).map((ch, i) => `<i style="--n:${i}">${ch === ' ' ? '&nbsp;' : esc(ch)}</i>`).join('');
      } else {
        text.textContent = value;
      }
    }

    const body = root.querySelector('.nbt-body');
    const lock = body.querySelector('.nbt-lock');
    if (locked && !lock) body.insertAdjacentHTML('beforeend', LOCK);
    else if (!locked && lock) lock.remove();

    particles(root.querySelector('.nbt-fx'), tag.p || 'none');
  }

  function build(tag, locked) {
    const root = el('div', 'nbt');
    const body = el('div', 'nbt-body');
    body.append(el('i', 'nbt-hole'), el('span', 'nbt-text'));
    root.append(body, el('div', 'nbt-fx'));
    apply(root, tag, locked);
    return root;
  }

  window.NBTag = { build, apply };

  /* ---------- world layer ---------- */

  const layer = $('tagLayer');
  const shown = {}; // key -> { anchor, tag }

  function setTags(list) {
    const keep = {};
    for (const item of list || []) {
      keep[item.k] = true;
      let s = shown[item.k];
      if (!s) {
        const anchor = el('div', 'nbt-anchor');
        anchor.style.opacity = '0';
        const tag = build(item.tag, item.l);
        tag.style.marginTop = '26px';
        anchor.appendChild(tag);
        layer.appendChild(anchor);
        s = shown[item.k] = { anchor, tag };
      } else {
        apply(s.tag, item.tag, item.l);
      }
    }
    for (const k of Object.keys(shown)) {
      if (!keep[k]) { shown[k].anchor.remove(); delete shown[k]; }
    }
  }

  function setPositions(pos) {
    const W = window.innerWidth, H = window.innerHeight;
    for (const k of Object.keys(shown)) {
      const p = pos && pos[k];
      const a = shown[k].anchor;
      if (!p) { a.style.opacity = '0'; continue; }
      a.style.transform = `translate(${(p[0] * W).toFixed(1)}px,${(p[1] * H).toFixed(1)}px) scale(${p[2].toFixed(3)})`;
      a.style.opacity = String(p[3]);
    }
  }

  /* ---------- editor ---------- */

  const ed = $('tagEditor');
  let E = null;       // the tag being edited
  let preview = null;
  let gradient = false;

  function opt(container, items, current, onPick, extra) {
    container.innerHTML = '';
    for (const it of items) {
      const b = el('button', 'te-opt' + (extra ? ' ' + extra : '') + (it.key === current ? ' on' : ''), esc(it.label));
      if (extra === 'font') b.style.fontFamily = `'${it.family}',Lexend,sans-serif`;
      b.onclick = () => { onPick(it.key); renderEditor(); };
      container.appendChild(b);
    }
  }

  function swatches(container, current, onPick) {
    container.innerHTML = '';
    for (const c of CFG.colors || []) {
      const b = el('button', 'te-sw' + (current && current.toLowerCase() === c.toLowerCase() ? ' on' : ''));
      b.style.setProperty('--c', c);
      b.title = c;
      b.onclick = () => { onPick(c); renderEditor(); };
      container.appendChild(b);
    }
    if (CFG.customColors) {
      const pick = el('label', 'te-pick');
      pick.title = 'Any colour';
      const input = el('input');
      input.type = 'color';
      input.value = /^#[0-9a-f]{6}$/i.test(current || '') ? current : '#ffffff';
      input.oninput = () => { onPick(input.value); renderEditor(true); };
      pick.appendChild(input);
      container.appendChild(pick);
    }
  }

  function renderEditor(fromPicker) {
    if (!E) return;
    if (!preview) { preview = build(E); $('tePreview').appendChild(preview); }
    apply(preview, E, false);

    $('teCount').textContent = `${Array.from(E.t || '').length}/${CFG.maxLength}`;
    opt($('teStyles'), CFG.styles, E.s, (k) => { E.s = k; });
    opt($('teFonts'), CFG.fonts, E.f, (k) => { E.f = k; }, 'font');
    opt($('teEffects'), CFG.effects, E.e, (k) => { E.e = k; });
    opt($('teParticles'), CFG.particles, E.p, (k) => { E.p = k; });
    if (!fromPicker) {
      swatches($('teColors'), E.c, (c) => { E.c = c; });
      swatches($('teColors2'), E.c2, (c) => { E.c2 = c; });
    }
    $('teGrad').classList.toggle('on', gradient);
    $('teColors2').classList.toggle('hide', !gradient);
    $('teSave').disabled = !(E.t || '').trim();
  }

  function openEditor(data) {
    CFG = data.cfg || CFG;
    const first = CFG;
    E = Object.assign({
      t: '', s: (first.styles[0] || {}).key, f: (first.fonts[0] || {}).key,
      c: '#ffffff', c2: null, e: 'none', p: 'none',
    }, data.tag || {});
    gradient = !!E.c2;
    $('teBag').textContent = data.bag || 'Backpack';
    $('teText').maxLength = CFG.maxLength || 18;
    $('teText').value = E.t || '';
    $('teCost').textContent = data.free ? 'Editing your tag is free' : 'Uses 1 name tag';
    $('teRemove').classList.toggle('hide', !data.tag);
    if (preview) { preview.remove(); preview = null; }
    ed.classList.remove('hide');
    renderEditor();
    setTimeout(() => $('teText').focus(), 50);
  }

  function closeEditor() {
    ed.classList.add('hide');
    E = null;
  }

  $('teText').oninput = (e) => { if (E) { E.t = e.target.value; renderEditor(true); } };
  $('teGrad').onclick = () => {
    gradient = !gradient;
    if (E) E.c2 = gradient ? (E.c2 || '#08afa2') : null;
    renderEditor();
  };
  $('teSave').onclick = () => {
    if (!E || !(E.t || '').trim()) return;
    post('tag:save', { tag: { t: E.t.trim(), s: E.s, f: E.f, c: E.c, c2: gradient ? E.c2 : null, e: E.e, p: E.p } });
  };
  $('teRemove').onclick = () => post('tag:remove');
  $('teClose').onclick = () => post('tag:close');
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !ed.classList.contains('hide')) post('tag:close');
  });

  /* ---------- messages ---------- */

  window.addEventListener('message', (e) => {
    const { action, data } = e.data || {};
    switch (action) {
      case 'tagInit': CFG = Object.assign(CFG, data || {}); break;
      case 'tagSet': setTags(data); break;
      case 'tagPos': setPositions(data); break;
      case 'tagEdit': openEditor(data || {}); break;
      case 'tagEditClose': closeEditor(); break;
      default: break;
    }
  });
})();
