/* ═══════════════════════════════════════════════════════════
   WIG SNATCH V2 · wig table + supplier side window
   the same window, order and HUD as the nayzeee-sneakers shoe table
   ═══════════════════════════════════════════════════════════ */
'use strict';

(() => {
  const el = (id) => document.getElementById(id);

  /* ---------------- icons (inline SVG, 24px grid, stroked) ---------------- */
  const PATHS = {
    check: '<path d="M4 12.5 9 17.5 20 6.5"/>',
    x: '<path d="M6 6l12 12M18 6 6 18"/>',
    chevron: '<path d="M9 6l6 6-6 6"/>',
    lock: '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
    level: '<path d="M4 20h4v-5h4v-5h4V5h4"/>',
    spark: '<path d="M12 3.5l2.4 5.2 5.6.7-4.1 3.9 1 5.6-4.9-2.7-4.9 2.7 1-5.6L4 9.4l5.6-.7z"/>',
    back: '<path d="M19 12H5M11 6l-6 6 6 6"/>',
    scissors: '<circle cx="6" cy="7" r="2.8"/><circle cx="6" cy="17" r="2.8"/><path d="M8.3 8.6 20 19M8.3 15.4 20 5"/>',
    cart: '<path d="M3 4h2l2.4 11.2a1.5 1.5 0 0 0 1.5 1.2h8.6a1.5 1.5 0 0 0 1.5-1.1L21 8H6.2"/><circle cx="9.5" cy="20" r="1.2"/><circle cx="17" cy="20" r="1.2"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    minus: '<path d="M5 12h14"/>',
    camera: '<path d="M4 8h3l1.5-2h7L17 8h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>',
    book: '<path d="M4 5.5A2.5 2.5 0 0 1 6.5 3H20v15H6.5A2.5 2.5 0 0 0 4 20.5z"/><path d="M4 20.5A2.5 2.5 0 0 0 6.5 23H20v-5"/>',
    wig: '<path d="M5 15c-1-6 2.5-11 7-11s8 5 7 11"/><path d="M5 15c0 3 1 5 2.5 5.5M19 15c0 3-1 5-2.5 5.5"/><path d="M8.5 9.5c1.5 1 5.5 1 7 0"/>',
    bundle: '<path d="M7 3c-1 6 0 12 2 18M12 3v18M17 3c1 6 0 12-2 18"/><path d="M6.5 7.5h11"/>',
    drop: '<path d="M12 3.5c3.5 4.4 6 7.6 6 10.6a6 6 0 0 1-12 0c0-3 2.5-6.2 6-10.6z"/>',
    user: '<circle cx="12" cy="8" r="4"/><path d="M4.5 20.5a7.5 7.5 0 0 1 15 0"/>',
    box: '<path d="M3.5 7.5 12 3.5l8.5 4v9L12 20.5l-8.5-4z"/><path d="M3.5 7.5 12 11.5l8.5-4M12 11.5v9"/>',
  };
  const icon = (n) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">${PATHS[n] || PATHS.chevron}</svg>`;
  const fillIcons = (root) => root.querySelectorAll('[data-icon]').forEach((x) => { x.innerHTML = icon(x.dataset.icon); });
  fillIcons(el('sk'));

  /* key names in hint text become key caps: "X to stop · V to change view" */
  const KEY = /^(LMB|RMB|Scroll|Backspace|ESC|Enter|Shift|←|→|↑|↓|[A-Z0-9]|F\d+)$/;
  function keyHint(text) {
    return String(text || '').split(' · ').map((part) => {
      const words = part.split(' ');
      const out = [];
      for (let i = 0; i < words.length; i++) {
        const w = words[i];
        if (w === '/' && KEY.test(words[i - 1] || '') && KEY.test(words[i + 1] || '')) continue;
        out.push(KEY.test(w) ? `<span class="key">${esc(w)}</span>` : esc(w) + ' ');
      }
      return `<span>${out.join('').trim()}</span>`;
    }).join('');
  }

  const fmtTime = (ms) => (ms / 1000).toFixed(1).replace(/\.0$/, '') + 's';
  const itemImg = (name) => `../INSTALL/images/${name}.png`;
  const fallbackImg = (name) => `https://cfx-nui-ox_inventory/web/images/${name}.png`;
  const imgTag = (name) => `<img src="${itemImg(name)}" alt="" onerror="if(!this.dataset.f){this.dataset.f=1;this.src='${fallbackImg(name)}'}else{this.replaceWith(Object.assign(document.createElement('span'),{className:'ph',innerHTML:'${icon('box').replace(/"/g, '&quot;')}'}))}">`;
  const shot = (m, d, t) => `../shots/wig_${m}_${d}_${t || 0}.png`;
  const hasShot = (m, d, t) => B.shots.has(`${m}/${d}_${t || 0}`);
  const ph = (n) => `<span class="ph">${icon(n)}</span>`;
  const shotTag = (m, d, t, fb = 'wig') => hasShot(m, d, t) ? `<img src="${shot(m, d, t)}" alt="" loading="lazy">` : ph(fb);

  /* ---------------- side window ---------------- */
  let side = null;   // 'bench' | 'shop' | null

  function openSide(kind, title, sub) {
    side = kind;
    el('skTitle').textContent = title.toUpperCase();
    el('skSub').textContent = sub;
    el('skBench').hidden = kind !== 'bench';
    el('skShop').hidden = kind !== 'shop';
    el('skSide').hidden = false;
    document.body.classList.add('side-open');
  }
  function hideSide() {
    side = null;
    showGuide(false);
    el('skSide').hidden = true;
    document.body.classList.remove('side-open');
  }
  function closeSide() {
    if (!side) return;
    const kind = side;
    hideSide();
    post(kind === 'bench' ? 'benchClose' : 'shopClose');
  }
  el('skClose').addEventListener('click', closeSide);

  function setNote(n, kind, html) {
    n.className = 'note' + (html ? ' show ' + kind : '');
    n.innerHTML = html || '';
  }

  /* guide drawer */
  const GUIDES = {
    bench: { title: 'WIG TABLE', steps: [
      ['Get materials', ['Buy them from the <b>Hair Supply</b> (on your map).', 'Materials are only used up when a wig is finished.']],
      ['Pick a wig', ['<b>Make</b> builds a wig from materials: pick any hairstyle in the city, a texture, a length, a lace and a colour.',
        '<b>Bundles</b> turns hair you snatched into a wig. <b>Dye</b> recolours a wig you own (or your own hair).']],
      ['Make it', ['You work at the table. The wig takes shape on the foam head in front of you, one stage at a time.',
        'Some stages have a <b>skill check</b>. Clean work can bump the wig a tier; sloppy work costs condition.',
        'Press <b>V</b> to change the camera, <b>X</b> to stop. You keep your materials.']],
      ['Level up', ['Every wig gives XP. Higher levels unlock better lace, faster work and better prices.']],
    ] },
    shop: { title: 'HAIR SUPPLY', steps: [
      ['Fill your cart', ['Use <b>+</b> and <b>−</b> on each material. Shift-click adds or removes five.', 'Some materials unlock at higher levels.']],
      ['Pay', ['<b>Buy</b> takes the total and puts everything in your pockets.']],
    ] },
  };
  function showGuide(on) {
    el('skGuide').classList.toggle('on', on);
    el('skScrim').classList.toggle('on', on);
    if (!on || !side) return;
    const g = GUIDES[side];
    el('skGuideTitle').textContent = g.title;
    el('skGuideBody').innerHTML = g.steps.map(([h, items], i) =>
      `<div class="gstep"><h3><span class="n">${i + 1}</span>${esc(h)}</h3><ul>${items.map((t) => `<li>${t}</li>`).join('')}</ul></div>`).join('');
  }
  el('skGuideBtn').addEventListener('click', () => showGuide(true));
  el('skGuideClose').addEventListener('click', () => showGuide(false));
  el('skScrim').addEventListener('click', () => showGuide(false));

  /* ---------------- wig table ---------------- */
  const B = {
    data: null, mode: 'make', view: null, shots: new Set(), pal: [], styles: [],
    pick: null, mk: { t: 0, length: 18, lace: null, c: 2, h: 2 },
    sel: new Set(), dye: { target: null, c: 0, h: 0 },
  };

  function setViews(v) {
    el('skViewsRow').hidden = !v;
    if (!v) { B.view = null; return; }
    B.view = B.view || v.current;
    if (v.label) el('skViewsLabel').textContent = v.label;
    el('skViews').innerHTML = arr(v.list).map((x) => `<button data-v="${esc(x.id)}" class="${x.id === B.view ? 'on' : ''}">${esc(x.label)}</button>`).join('');
  }
  el('skViews').addEventListener('click', (e) => {
    const b = e.target.closest('button');
    if (!b) return;
    B.view = b.dataset.v;
    [...el('skViews').children].forEach((x) => x.classList.toggle('on', x === b));
  });

  function setXP(d) {
    el('skLvl').textContent = d.level;
    const max = d.to == null;
    el('skXpLabel').textContent = max ? 'Max level' : 'Next level';
    el('skXpText').textContent = max ? `${num(d.xp)} XP` : `${num(d.xp - d.from)} / ${num(d.to - d.from)}`;
    el('skXpBar').style.width = (max ? 100 : Math.min(100, (d.xp - d.from) / (d.to - d.from) * 100)) + '%';
    el('skSub').textContent = `Level ${d.level} · ${num(d.xp)} XP`;
  }

  function modes() {
    const d = B.data, out = [];
    if (d.make) out.push(['make', 'scissors', 'Make']);
    if (d.ws && d.ws.craft) out.push(['bundles', 'bundle', 'Bundles']);
    if (d.ws && d.ws.dye) out.push(['dye', 'drop', 'Dye']);
    return out;
  }

  function openBench(d) {
    B.data = d; B.pick = null; B.sel.clear();
    B.shots = new Set(arr(d.shots));
    B.pal = arr(d.palette);
    B.styles = [];
    ['f', 'm'].forEach((m) => arr((d.styles || {})[m]).forEach((s) => B.styles.push(Object.assign({ m }, s))));
    // your own model's hair first, like the sneakers list puts the easy pairs first
    B.styles.sort((a, b) => (a.m === d.myModel ? 0 : 1) - (b.m === d.myModel ? 0 : 1) || a.d - b.d);
    B.view = d.views ? d.views.current : null;
    const ms = modes();
    if (!ms.some(([k]) => k === B.mode)) B.mode = ms.length ? ms[0][0] : 'make';
    openSide('bench', 'Wig table', '');
    setXP(d);
    setViews(d.views);
    el('skMode').hidden = ms.length < 2;
    el('skMode').innerHTML = ms.map(([k, ic, l]) => `<button data-v="${k}" class="${k === B.mode ? 'on' : ''}">${icon(ic)}${l}</button>`).join('');
    el('skSearch').value = '';
    showList();
  }

  el('skMode').addEventListener('click', (e) => {
    const b = e.target.closest('button');
    if (!b) return;
    B.mode = b.dataset.v;
    [...el('skMode').children].forEach((x) => x.classList.toggle('on', x === b));
    el('skSearch').value = '';
    showList();
  });

  function showList() {
    B.pick = null;
    el('skPickView').hidden = false;
    el('skDetail').hidden = B.mode !== 'bundles';
    renderList();
    if (B.mode === 'bundles') renderBundles();
  }
  el('skSearch').addEventListener('input', renderList);

  const speedK = () => 1 - Math.min(0.4, (B.data.level - 1) * (B.data.speed || 0));
  const lacesOf = () => arr(B.data.make && B.data.make.laces);

  function renderList() {
    const q = el('skSearch').value.trim().toLowerCase();
    const list = el('skList');
    list.innerHTML = '';
    el('skSearchWrap').hidden = B.mode === 'bundles';
    if (B.mode === 'make') {
      el('skPickTitle').textContent = 'Pick a hairstyle';
      const f = B.styles.filter((s) => s.m === 'f').length;
      el('skPickSub').textContent = `${B.styles.length} hairstyles · ${f} female · ${B.styles.length - f} male`;
      const rows = B.styles.filter((s) => !q || String(s.d) === q || String(s.name || '').toLowerCase().includes(q) || (q === 'male' ? s.m === 'm' : q === 'female' ? s.m === 'f' : false));
      rows.forEach((s) => {
        const b = document.createElement('button');
        b.className = 'row';
        b.innerHTML = `<span class="av img">${shotTag(s.m, s.d, 0)}</span>` +
          `<span class="row-txt"><b>${esc(s.name || 'Hairstyle ' + s.d)}</b><span>${s.m === 'm' ? 'Male' : 'Female'}${s.n > 1 ? ` · ${s.n} textures` : ''}</span></span>` +
          `<span class="tag off">#${s.d}</span>`;
        b.addEventListener('click', () => pickStyle(s));
        list.appendChild(b);
      });
    } else if (B.mode === 'bundles') {
      const ws = B.data.ws;
      el('skPickTitle').textContent = `Pick ${ws.need} bundles`;
      el('skPickSub').textContent = 'All from the same male or female hair';
      arr(ws.bundles).forEach((bd) => {
        const b = document.createElement('button');
        b.className = 'row' + (B.sel.has(bd.key) ? ' sel' : '');
        b.innerHTML = `<span class="av img">${bd.image ? `<img src="${esc(bd.image)}" alt="" loading="lazy">` : ph('bundle')}</span>` +
          `<span class="row-txt"><b>${esc(bd.style || bd.label || 'Bundle')}</b><span>${esc(gradeLabel(bd.grade))} · ${bd.length || '-'}" · ${money(bd.value)}</span></span>` +
          `<span class="check">${icon('check')}</span>`;
        b.addEventListener('click', () => {
          if (B.sel.has(bd.key)) B.sel.delete(bd.key);
          else if (B.sel.size < ws.need) B.sel.add(bd.key);
          renderList(); renderBundles();
        });
        list.appendChild(b);
      });
      if (!list.children.length) list.innerHTML = '<div class="note show">No bundles yet. Snip long hair with scissors to collect some.</div>';
      return;
    } else {
      const ws = B.data.ws;
      el('skPickTitle').textContent = 'Pick a wig';
      el('skPickSub').textContent = `${ws.dyes} hair dye${ws.dyes === 1 ? '' : 's'} · dyed wigs sell for +${Math.round((ws.dyeBonus || 0) * 100)}%`;
      const wigs = arr(ws.wigs).filter((w) => !w.generic && (!q || String(goodTitle(w)).toLowerCase().includes(q)));
      if (ws.ownHair && (!q || 'my own hair'.includes(q))) {
        const b = document.createElement('button');
        b.className = 'row';
        b.innerHTML = `<span class="av">${icon('user')}</span><span class="row-txt"><b>My own hair</b><span>${ws.hair && ws.hair.bald ? 'You\'re bald' : 'Done on the spot'}</span></span><span class="tag off">You</span>`;
        b.addEventListener('click', () => pickDye('self'));
        list.appendChild(b);
      }
      wigs.forEach((w) => {
        const t = tier(w.tier);
        const b = document.createElement('button');
        b.className = 'row';
        b.innerHTML = `<span class="av img">${w.image ? `<img src="${esc(w.image)}" alt="" loading="lazy">` : ph('wig')}</span>` +
          `<span class="row-txt"><b>${esc(goodTitle(w))}</b><span>${esc(t.label)} · ${w.dyed ? 'Dyed' : 'Natural'}</span></span>` +
          `<span class="tag off">${money(w.value)}</span>`;
        b.addEventListener('click', () => pickDye(w.key));
        list.appendChild(b);
      });
    }
    if (!list.children.length) list.innerHTML = `<div class="note show">Nothing matches <b>${esc(q)}</b>.</div>`;
  }

  /* ----- make: detail ----- */
  function pickStyle(s) {
    B.pick = s;
    B.mk.t = 0;
    const laces = lacesOf();
    if (!B.mk.lace || !laces.some((l) => l.id === B.mk.lace && !l.locked)) B.mk.lace = (laces.find((l) => !l.locked) || laces[0] || {}).id;
    const [lo, hi] = arr(B.data.make.lengths);
    B.mk.length = clamp(B.mk.length, lo || 10, hi || 30);
    el('skPickView').hidden = true;
    el('skDetail').hidden = false;
    el('skBench').scrollTop = 0;
    renderMake();
  }

  function recipe() {
    const i = B.data.make, out = {};
    const add = (k, n) => (out[k] = (out[k] || 0) + n);
    Object.entries(i.base || {}).forEach(([k, n]) => add(k, n));
    add(i.weft, Math.ceil(B.mk.length / (i.weftInches || 6)));
    const lace = lacesOf().find((l) => l.id === B.mk.lace);
    if (lace) Object.entries(lace.items || {}).forEach(([k, n]) => add(k, n));
    if (!arr(i.natural).includes(B.mk.c)) add(i.dye, 1);
    return { items: out, lace };
  }

  function matsPanel(items, have, labels, sub) {
    let missing = null;
    const rows = Object.entries(items).map(([name, count]) => {
      const h = have[name] || 0, ok = h >= count;
      if (!ok && !missing) missing = labels[name] || name;
      return `<div class="row"><span class="av img">${imgTag(name)}</span>` +
        `<span class="row-txt"><b>${esc(labels[name] || name)}</b><span>Needs ${count}</span></span>` +
        `<span class="need${ok ? ' ok' : ''}">${h} / ${count}</span></div>`;
    }).join('');
    return { missing, html: `<section class="panel"><div class="p-head"><div><h2>Materials</h2><p>${sub}</p></div></div><div class="p-body">${rows}</div></section>` };
  }

  function stagesPanel(kind, btn, btnIcon) {
    const st = arr((B.data.stages || {})[kind]);
    const time = st.reduce((a, s) => a + s.time, 0) * speedK();
    return `<section class="panel"><div class="p-head"><div><h2>Stages</h2><p>${st.length} stages · about ${fmtTime(time)}</p></div></div>
      <div class="p-body">
        <div class="steps">${st.map((s) => `<div><span>${esc(s.label)}</span>${s.check ? '<span class="chip amber">CHECK</span>' : ''}</div>`).join('')}</div>
        <div class="note" id="skStatus"></div>
        <button class="btn-teal wide" id="skGo">${icon(btnIcon)}${btn}</button>
      </div></section>`;
  }

  const palRow = (field, cur) => `<div class="pals">${B.pal.map((hex, n) => `<button class="pal ${cur === n ? 'on' : ''}" style="background:${hex}" data-f="${field}" data-n="${n}" title="${n}"></button>`).join('')}</div>`;

  function renderMake() {
    const s = B.pick, i = B.data.make, mk = B.mk;
    const { items, lace } = recipe();
    const laces = lacesOf();
    const lt = lace ? tier(lace.tier) : null;
    const [lo, hi] = arr(i.lengths);
    const lengths = [];
    for (let n = lo || 10; n <= (hi || 30); n += 2) lengths.push(n);
    const natural = arr(i.natural).includes(mk.c);
    const mats = matsPanel(items, i.have || {}, i.labels || {}, 'Used up when the wig is finished');
    const textures = Math.min(s.n || 1, 16);

    el('skDetail').innerHTML = `
      <section class="panel">
        <div class="p-head">
          <div><h2>${esc(s.name || 'Hairstyle ' + s.d)}</h2><p class="teal">${s.m === 'm' ? 'Male' : 'Female'} · Texture ${mk.t + 1}</p></div>
          <button class="btn-ghost" data-a="back">${icon('back')}All hairstyles</button>
        </div>
        <div class="p-body">
          <div class="preview">${hasShot(s.m, s.d, mk.t) ? `<img src="${shot(s.m, s.d, mk.t)}" alt="">` : ph('wig')}<span class="tag off lvl">#${s.d}</span></div>
          ${textures > 1 ? `<div class="swatches">${Array.from({ length: textures }, (_, n) =>
            `<button class="sw ${n === mk.t ? 'on' : ''}" data-t="${n}" title="Texture ${n + 1}">${hasShot(s.m, s.d, n) ? `<img src="${shot(s.m, s.d, n)}" alt="">` : n + 1}</button>`).join('')}</div>` : ''}
        </div>
      </section>
      <section class="panel">
        <div class="p-head"><div><h2>Length</h2><p>Inches · longer takes more wefts</p></div></div>
        <div class="p-body"><div class="chips">${lengths.map((n) => `<button class="${n === mk.length ? 'on' : ''}" data-len="${n}">${n}"</button>`).join('')}</div></div>
      </section>
      <section class="panel">
        <div class="p-head"><div><h2>Lace</h2><p>${lt ? `${esc(lt.label)} wig · sells for ${money(lace.price[0])}–${money(lace.price[1])}` : ''}</p></div></div>
        <div class="p-body"><div class="chips">${laces.map((l) => `<button class="${l.id === mk.lace ? 'on' : ''}" data-lace="${esc(l.id)}" ${l.locked ? 'disabled' : ''}>${l.locked ? icon('lock') : ''}${esc(l.label)}${l.locked ? ` · Lv ${l.level}` : ''}</button>`).join('')}</div></div>
      </section>
      <section class="panel">
        <div class="p-head"><div><h2>Colour</h2><p>${natural ? 'A natural colour, no dye needed' : 'Needs a hair dye'}</p></div></div>
        <div class="p-body">
          <div class="pal-l"><span>Colour</span><b>${mk.c}</b></div>${palRow('c', mk.c)}
          <div class="pal-l"><span>Highlight</span><b>${mk.h}</b></div>${palRow('h', mk.h)}
        </div>
      </section>
      ${mats.html}
      ${stagesPanel('make', 'Make this wig', 'scissors')}`;

    let kind = 'ok', text = `<b>Ready.</b> A ${mk.length}" ${lace ? esc(lace.label.toLowerCase()) : ''} wig.`;
    if (lace && lace.locked) { kind = 'warn'; text = `<b>${esc(lace.label)}</b> unlocks at level ${lace.level}.`; }
    else if (mats.missing) { kind = 'err'; text = `You're missing <b>${esc(mats.missing)}</b>.${i.supplier ? ` ${esc(i.supplier)} sells it.` : ''}`; }
    setNote(el('skStatus'), kind, text);
    el('skGo').disabled = kind !== 'ok';
  }

  /* ----- bundles: picked list + materials + stages ----- */
  function renderBundles() {
    const ws = B.data.ws;
    const picked = arr(ws.bundles).filter((b) => B.sel.has(b.key));
    const models = new Set(picked.map((b) => b.fits));
    const items = {}, have = {}, labels = {};
    const cap = ws.capItem || 'wig_cap';
    if (ws.needCap) { items[cap] = 1; have[cap] = ws.caps; labels[cap] = ws.capLabel || 'Wig cap'; }
    const mats = matsPanel(items, have, labels, ws.needCap ? 'Used up when the wig is finished' : 'Just the bundles');
    el('skDetail').innerHTML = `${ws.needCap ? mats.html : ''}${stagesPanel('craft', 'Make this wig', 'scissors')}`;
    let kind = 'ok', text = `<b>Ready.</b> ${picked.length} bundles of ${esc(picked[0] ? picked[0].style : '')}.`;
    if (picked.length < ws.need) { kind = 'warn'; text = `Pick <b>${ws.need - picked.length}</b> more bundle${ws.need - picked.length === 1 ? '' : 's'}.`; }
    else if (models.size > 1) { kind = 'err'; text = 'Those bundles mix <b>male and female</b> hair.'; }
    else if (mats.missing) { kind = 'err'; text = `You're missing a <b>wig cap</b>.`; }
    setNote(el('skStatus'), kind, text);
    el('skGo').disabled = kind !== 'ok';
  }

  /* ----- dye: detail ----- */
  function pickDye(target) {
    B.dye.target = target;
    const ws = B.data.ws;
    const w = target === 'self' ? null : arr(ws.wigs).find((x) => x.key === target);
    const c = w ? w.color : ws.hair && ws.hair.dye ? ws.hair.dye.c : null;
    const h = w ? w.highlight : ws.hair && ws.hair.dye ? ws.hair.dye.h : null;
    if (typeof c === 'number') { B.dye.c = c; B.dye.h = typeof h === 'number' ? h : c; }
    el('skPickView').hidden = true;
    el('skDetail').hidden = false;
    el('skBench').scrollTop = 0;
    renderDye();
  }

  function renderDye() {
    const ws = B.data.ws, d = B.dye, self = d.target === 'self';
    const w = self ? null : arr(ws.wigs).find((x) => x.key === d.target);
    const dye = ws.dyeItem || 'hair_dye';
    const mats = matsPanel({ [dye]: 1 }, { [dye]: ws.dyes }, { [dye]: ws.dyeLabel || 'Hair dye' }, 'Used up when the colour is in');
    el('skDetail').innerHTML = `
      <section class="panel">
        <div class="p-head">
          <div><h2>${self ? 'My own hair' : esc(goodTitle(w))}</h2><p class="teal">Colour ${d.c} · Highlight ${d.h}</p></div>
          <button class="btn-ghost" data-a="back">${icon('back')}All wigs</button>
        </div>
        <div class="p-body"><div class="preview">${w && w.image ? `<img src="${esc(w.image)}" alt="" style="opacity:.35">` : ''}
          <div class="dye-pv"><div><span style="background:${B.pal[d.c] || '#222'}"></span>Colour</div><div><span style="background:${B.pal[d.h] || '#222'}"></span>Highlight</div></div></div></div>
      </section>
      <section class="panel">
        <div class="p-head"><div><h2>Colour</h2><p>Any of the city's hair colours</p></div></div>
        <div class="p-body">
          <div class="pal-l"><span>Colour</span><b>${d.c}</b></div>${palRow('c', d.c)}
          <div class="pal-l"><span>Highlight</span><b>${d.h}</b></div>${palRow('h', d.h)}
        </div>
      </section>
      ${mats.html}
      ${self ? `<section class="panel"><div class="p-body"><div class="note" id="skStatus"></div>
        <button class="btn-teal wide" id="skGo">${icon('drop')}Dye my hair</button>
        ${ws.hair && ws.hair.dye ? `<button class="btn-ghost" data-a="rinse" style="justify-content:center;height:34px">${icon('drop')}Rinse my dye out</button>` : ''}</div></section>`
        : stagesPanel('dye', 'Dye this wig', 'drop')}`;
    let kind = 'ok', text = self ? '<b>Ready.</b> Takes a few seconds.' : '<b>Ready.</b> Worked through at the table.';
    if (self && ws.hair && ws.hair.bald) { kind = 'warn'; text = "You're <b>bald</b>. Nothing to dye."; }
    else if (mats.missing) { kind = 'err'; text = `You're missing a <b>hair dye</b>.${B.data.make && B.data.make.supplier ? ` ${esc(B.data.make.supplier)} sells it.` : ''}`; }
    setNote(el('skStatus'), kind, text);
    el('skGo').disabled = kind !== 'ok';
  }

  function rerender() {
    if (B.mode === 'make' && B.pick) renderMake();
    else if (B.mode === 'dye' && B.dye.target) renderDye();
    else if (B.mode === 'bundles') renderBundles();
  }

  el('skDetail').addEventListener('click', (e) => {
    const b = e.target.closest('button');
    if (!b || b.disabled) return;
    if (b.dataset.a === 'back') { B.dye.target = null; el('skSearch').value = ''; return showList(); }
    if (b.dataset.a === 'rinse') { post('rinse'); return; }
    if (b.id === 'skGo') return go();
    if (b.dataset.t !== undefined) B.mk.t = Number(b.dataset.t);
    else if (b.dataset.len !== undefined) B.mk.length = Number(b.dataset.len);
    else if (b.dataset.lace !== undefined) B.mk.lace = b.dataset.lace;
    else if (b.dataset.f) (B.mode === 'dye' ? B.dye : B.mk)[b.dataset.f] = Number(b.dataset.n);
    else return;
    const sc = el('skBench').scrollTop;
    rerender();
    el('skBench').scrollTop = sc;
  });

  // start the job: the window goes, the work plays out at the table (like the sneakers "Make this pair")
  function go() {
    if (el('skGo').disabled) return;
    const view = B.view;
    if (B.mode === 'dye' && B.dye.target === 'self') {
      post('dyeSelf', { c: B.dye.c, h: B.dye.h });
      return closeSide();
    }
    hideSide();
    if (B.mode === 'make') {
      const s = B.pick, mk = B.mk;
      post('make', { m: s.m, d: s.d, t: mk.t, length: mk.length, lace: mk.lace, c: mk.c, h: mk.h, view });
    } else if (B.mode === 'bundles') {
      post('craft', { keys: [...B.sel], view });
      B.sel.clear();
    } else {
      post('dyeWig', { key: B.dye.target, c: B.dye.c, h: B.dye.h, view });
    }
  }

  /* ---------------- supplier ---------------- */
  const SH = { shop: null, cart: {} };

  function openShop(shop) {
    SH.shop = shop; SH.cart = {};
    openSide('shop', shop.title || 'Hair Supply', '');
    renderShop();
  }

  function renderShop() {
    const sh = SH.shop;
    el('skSub').textContent = `${sh.account === 'bank' ? 'Bank' : 'Cash'} ${money(sh.money)} · Level ${sh.level}`;
    const list = el('skShopList');
    list.innerHTML = '';
    let total = 0;
    arr(sh.items).forEach((it) => {
      const qty = SH.cart[it.name] || 0;
      total += qty * it.price;
      const locked = it.locked || sh.level < it.level;
      const row = document.createElement('div');
      row.className = 'row' + (qty ? ' sel' : '');
      row.innerHTML = `<span class="av img">${imgTag(it.name)}</span>` +
        `<span class="row-txt"><b>${esc(it.label)}</b><span><span class="price">${money(it.price)}</span> each${it.have ? ` · you have ${it.have}` : ''}</span></span>` +
        (locked ? `<span class="tag warn">${icon('lock')}Lv ${it.level}</span>` :
          `<span class="stepper"><button data-d="-1">${icon('minus')}</button><span>${qty}</span><button data-d="1">${icon('plus')}</button></span>`);
      row.querySelectorAll('.stepper button').forEach((b) => b.addEventListener('click', (e) => {
        const n = Math.max(0, Math.min(sh.max, qty + Number(b.dataset.d) * (e.shiftKey ? 5 : 1)));
        if (n) SH.cart[it.name] = n; else delete SH.cart[it.name];
        renderShop();
      }));
      list.appendChild(row);
    });
    el('skShopTotal').textContent = money(total);
    const broke = total > sh.money;
    setNote(el('skShopStatus'), 'err', broke ? `That's more than you have (<b>${money(sh.money)}</b>).` : '');
    el('skBuy').disabled = total === 0 || broke;
  }

  el('skBuy').addEventListener('click', async () => {
    if (el('skBuy').disabled) return;
    el('skBuy').disabled = true;
    const res = await post('shopBuy', { cart: SH.cart });
    if (res && res.ok) {
      arr(SH.shop.items).forEach((it) => { it.have = (it.have || 0) + (SH.cart[it.name] || 0); });
      SH.cart = {};
      if (typeof res.money === 'number') SH.shop.money = res.money;
    }
    if (side === 'shop') renderShop();
  });

  /* ---------------- crafting stage HUD (also the plain progress bar) ---------------- */
  let pgRaf = 0, pgHide = 0;
  function showStage(d) {
    cancelAnimationFrame(pgRaf);
    clearTimeout(pgHide);
    const box = el('skStage');
    if (!d || d.hide) { box.hidden = true; return; }
    box.hidden = false;
    el('skStLabel').textContent = d.label || '';
    el('skStStep').hidden = !d.steps;
    el('skStStep').textContent = d.steps ? `STAGE ${d.step} / ${d.steps}` : '';
    el('skStRef').textContent = d.ref || (d.steps ? 'CRAFTING' : '');
    el('skStHint').hidden = !d.hint;
    el('skStHint').innerHTML = keyHint(d.hint);
    const start = performance.now(), bar = el('skStBar'), time = d.time || 1;
    const tick = (now) => {
      bar.style.width = Math.min(100, (now - start) / time * 100) + '%';
      if (now - start < time) pgRaf = requestAnimationFrame(tick);
    };
    bar.style.width = '0%';
    pgRaf = requestAnimationFrame(tick);
    if (d.auto) pgHide = setTimeout(() => { box.hidden = true; }, time + 150);
  }

  /* ---------------- finished wig ---------------- */
  let rsTimer = 0;
  function showResult(d) {
    clearTimeout(rsTimer);
    const box = el('skResult');
    box.classList.remove('out');
    box.hidden = false;
    const h = d.hair;
    el('skRsImg').innerHTML = h && hasShot(h.m, h.d, h.t) ? `<img src="${shot(h.m, h.d, h.t)}" alt="">` : ph(d.dyed ? 'drop' : 'wig');
    el('skRsName').textContent = d.name || 'Wig';
    const badge = el('skRsBadge');
    badge.textContent = String(d.dyed ? 'DYED' : (d.tier || 'WIG')).toUpperCase();
    badge.setAttribute('style', d.color ? `color:${d.color};border-color:${d.color}55;background:${d.color}1c` : '');
    el('skRsChecks').textContent = d.checks ? `${d.passed} / ${d.checks} CHECKS` : '';
    const q = Math.round(d.cond ?? 100);
    el('skRsQ').textContent = q + '%';
    const bar = el('skRsBar');
    bar.className = q < 50 ? 'high' : q < 80 ? 'mid' : '';
    bar.style.width = '0%';
    requestAnimationFrame(() => requestAnimationFrame(() => { bar.style.width = q + '%'; }));
    rsTimer = setTimeout(() => {
      box.classList.add('out');
      rsTimer = setTimeout(() => { box.hidden = true; box.classList.remove('out'); }, 320);
    }, 4200);
  }

  /* ---------------- key hint pill ---------------- */
  function showHint(d) {
    const pill = el('hint');
    if (!d || !d.show) { pill.hidden = true; return; }
    const keys = arr(d.keys).map((k) => `<span class="key">${esc(k)}</span>`).join('');
    pill.innerHTML = keys ? `<span>${keys}${esc(d.text || '')}</span>` : keyHint(d.text);
    pill.hidden = false;
  }

  /* ---------------- keys ---------------- */
  function sideKey(e) {
    if (!side || e.type !== 'keydown') return false;
    if (e.target.tagName === 'INPUT') {
      if (e.key === 'Escape') { e.target.blur(); return true; }
      return false;
    }
    if (e.key === 'Escape') {
      e.preventDefault();
      if (el('skGuide').classList.contains('on')) showGuide(false); else closeSide();
      return true;
    }
    if (e.key === 'g' || e.key === 'G') { showGuide(!el('skGuide').classList.contains('on')); return true; }
    return false;
  }

  window.Side = {
    open: (d) => { if (d.kind === 'shop') openShop(d.data || {}); else openBench(d.data || {}); },
    hide: () => { if (side) hideSide(); },
    stage: showStage,
    result: showResult,
    hint: showHint,
    key: sideKey,
    isOpen: () => !!side,
  };
})();
