/* ═══════════════════════════════════════════════════════════
   NAYZEEE UI PACK · core runtime
   Tiny shared layer for every theme:
     NZ.on(action, fn)     handle SendNUIMessage({ action, data })
     NZ.post(name, data)   fetch to RegisterNUICallback(name)
     NZ.open(el) / NZ.close(el)
     NZ.preview(fn)        demo data, runs only outside the game
     NZ.icon(name)         inline stroke icon (see ICONS below)
     NZ.addIcons({name: '<path…/>'})  register extra icons from a theme
     NZ.esc(str)           escape player-supplied text before innerHTML
     NZ.shape('twin')      switch the theme's silhouette (see SHAPES in nz-core.css)
   ═══════════════════════════════════════════════════════════ */
(() => {
  const inGame = typeof window.GetParentResourceName === 'function';
  const resource = inGame ? window.GetParentResourceName() : 'nz-preview';
  document.documentElement.classList.add(inGame ? 'nz-nui' : 'nz-preview');

  /* ── stroke icons, 24×24 ── */
  const ICONS = {
    grid:'<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
    map:'<path d="M9 4 3 6.5v13L9 17l6 2.5 6-2.5v-13L15 6.5 9 4z"/><path d="M9 4v13M15 6.5v13"/>',
    pulse:'<path d="M4 17h2l1.5-6L10 19l2.5-14L15 15l1.5-4H20"/>',
    medkit:'<rect x="3.5" y="3.5" width="17" height="17" rx="3"/><path d="M12 8v8M8 12h8"/>',
    file:'<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8l-5-5z"/><path d="M14 3v5h5"/>',
    clipboard:'<rect x="5" y="4" width="14" height="17" rx="2"/><path d="M9 3h6v3H9zM9 12h6M9 16h4"/>',
    user:'<circle cx="12" cy="8" r="3.5"/><path d="M5 20a7 7 0 0 1 14 0"/>',
    users:'<circle cx="9" cy="8" r="3.2"/><path d="M3 20a6 6 0 0 1 12 0M15.5 4.8a3.2 3.2 0 0 1 0 6.4M17.5 14.2A6 6 0 0 1 21 20"/>',
    car:'<path d="M5 17H3.5v-4.5L5.6 7.6A2 2 0 0 1 7.4 6.5h9.2a2 2 0 0 1 1.8 1.1l2.1 4.9V17H19"/><path d="M3.5 12.5h17M9 17h6"/><circle cx="7" cy="17" r="2"/><circle cx="17" cy="17" r="2"/>',
    x:'<path d="M6 6l12 12M18 6 6 18"/>',
    check:'<path d="M4 12.5 9 17.5 20 6.5"/>',
    alert:'<path d="M12 9v5M12 17.5v.01"/><path d="M10.3 3.9 2.5 17.5A2 2 0 0 0 4.2 20.5h15.6a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/>',
    info:'<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 7.5v.01"/>',
    error:'<circle cx="12" cy="12" r="9"/><path d="M12 8v5M12 16.5v.01"/>',
    'chev-r':'<path d="m9 5 7 7-7 7"/>',
    'chev-l':'<path d="m15 5-7 7 7 7"/>',
    'chev-d':'<path d="m5 9 7 7 7-7"/>',
    'chev-u':'<path d="m5 15 7-7 7 7"/>',
    'arrow-up':'<path d="M12 19V5M6 11l6-6 6 6"/>',
    'arrow-l':'<path d="M19 12H5M11 6l-6 6 6 6"/>',
    refresh:'<path d="M20 11a8 8 0 1 0-2.3 5.7M20 5v6h-6"/>',
    filter:'<path d="M4 6h16M7 12h10M10 18h4"/>',
    search:'<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/>',
    cart:'<path d="M3 4h2.2l2.1 10.5a1.5 1.5 0 0 0 1.5 1.2h8.4a1.5 1.5 0 0 0 1.5-1.1L20.5 8H6"/><circle cx="9.5" cy="19.5" r="1.3"/><circle cx="17" cy="19.5" r="1.3"/>',
    bag:'<path d="M5 8h14l-1 12H6L5 8z"/><path d="M9 8V6.5a3 3 0 0 1 6 0V8"/>',
    box:'<path d="M3.5 7.5 12 3l8.5 4.5v9L12 21l-8.5-4.5v-9z"/><path d="M3.5 7.5 12 12l8.5-4.5M12 12v9"/>',
    heart:'<path d="M12 20s-7.5-4.6-7.5-10.2A4.3 4.3 0 0 1 12 7.4a4.3 4.3 0 0 1 7.5 2.4C19.5 15.4 12 20 12 20z"/>',
    shield:'<path d="M12 3 4.5 6v5.5c0 4.6 3.2 8 7.5 9.5 4.3-1.5 7.5-4.9 7.5-9.5V6L12 3z"/>',
    food:'<path d="M4 11a8 6 0 0 1 16 0H4z"/><path d="M3.5 14.5h17M5 18.5h14a1 1 0 0 0 1-1V17H4v.5a1 1 0 0 0 1 1z"/>',
    drop:'<path d="M12 3.5s6 6.6 6 11a6 6 0 0 1-12 0c0-4.4 6-11 6-11z"/>',
    bolt:'<path d="M13 3 5 13.5h6L10 21l8-10.5h-6L13 3z"/>',
    brain:'<path d="M9 4.5a3 3 0 0 0-3 3 3 3 0 0 0-2 5 3 3 0 0 0 2 5 3 3 0 0 0 6 1.5V6a2 2 0 0 0-3-1.5zM15 4.5a3 3 0 0 1 3 3 3 3 0 0 1 2 5 3 3 0 0 1-2 5 3 3 0 0 1-6 1.5"/>',
    mic:'<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"/>',
    fuel:'<path d="M5 20V5a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v15M3.5 20h13M5 10h10"/><path d="M15 8h1.5a2 2 0 0 1 2 2v6.5a1.5 1.5 0 0 0 3 0V9l-3-3"/>',
    seat:'<circle cx="12" cy="4.5" r="2"/><path d="M8.5 21v-6L7.5 10a2 2 0 0 1 2-2.5h5a2 2 0 0 1 2 2.5l-1 5v6M8 9l8 8"/>',
    engine:'<path d="M4 10v6M4 13h2M6 9h3V7h5v2h2l2 2h2v6h-2l-2 2H8l-2-2V9z"/>',
    light:'<path d="M14 6c-4 0-6 2.5-6 6s2 6 6 6h2V6h-2zM3 8h3M3 12h3M3 16h3"/>',
    wrench:'<path d="M15 4.5a4.5 4.5 0 0 0-5.6 5.6L4 15.5V20h4.5l5.4-5.4a4.5 4.5 0 0 0 5.6-5.6L17 11.5 13.5 11 13 7.5 15 4.5z"/>',
    key:'<circle cx="8" cy="15" r="4"/><path d="m11 12 8.5-8.5M16 7l2.5 2.5M14 9l2 2"/>',
    cash:'<rect x="2.5" y="6" width="19" height="12" rx="2"/><circle cx="12" cy="12" r="2.5"/><path d="M6 9.5v.01M18 14.5v.01"/>',
    card:'<rect x="2.5" y="5" width="19" height="14" rx="2.5"/><path d="M2.5 10h19M6.5 15h4"/>',
    bank:'<path d="M3 9.5 12 4l9 5.5M4.5 10v8M9.5 10v8M14.5 10v8M19.5 10v8M3 20.5h18"/>',
    phone:'<rect x="6.5" y="2.5" width="11" height="19" rx="2.5"/><path d="M11 18.5h2"/>',
    home:'<path d="M4 11 12 4l8 7v9h-5v-6H9v6H4v-9z"/>',
    shirt:'<path d="M8.5 3.5 4 6l1.5 4.5L7 10v10.5h10V10l1.5.5L20 6l-4.5-2.5a3.5 3.5 0 0 1-7 0z"/>',
    smile:'<circle cx="12" cy="12" r="9"/><path d="M8.5 14a4.5 4.5 0 0 0 7 0M9 9.5v.01M15 9.5v.01"/>',
    walk:'<circle cx="13" cy="4.5" r="1.8"/><path d="m9 21 2.5-6 2.5 2.5V21M8 12l2-4.5 3.5 1 2 3.5 2.5 1M11.5 15 13 8.5"/>',
    briefcase:'<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M8.5 7V5.5A1.5 1.5 0 0 1 10 4h4a1.5 1.5 0 0 1 1.5 1.5V7M3 12.5h18"/>',
    receipt:'<path d="M6 3h12v18l-2.5-1.5L13 21l-2.5-1.5L8 21l-2-1.5V3z"/><path d="M9 8h6M9 12h6M9 16h3"/>',
    id:'<rect x="3" y="5" width="18" height="14" rx="2.5"/><circle cx="9" cy="11" r="2.2"/><path d="M5.8 16a3.4 3.4 0 0 1 6.4 0M14.5 10h3.5M14.5 13.5h2.5"/>',
    sliders:'<path d="M4 7h10M18 7h2M4 17h4M12 17h8"/><circle cx="16" cy="7" r="2"/><circle cx="10" cy="17" r="2"/>',
    lock:'<rect x="5" y="10.5" width="14" height="10" rx="2"/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3"/>',
    palette:'<path d="M12 3.5a8.5 8.5 0 0 0 0 17c1.2 0 1.8-.8 1.8-1.7 0-1.4-1.2-1.6-1.2-2.8 0-.9.7-1.5 1.6-1.5h2.3a4 4 0 0 0 4-4C20.5 6.8 16.7 3.5 12 3.5z"/><circle cx="7.5" cy="11" r="1"/><circle cx="10" cy="7.5" r="1"/><circle cx="14.5" cy="7.5" r="1"/>',
    gauge:'<path d="M4.5 17a8.5 8.5 0 1 1 15 0"/><path d="m12 13 4-4"/><circle cx="12" cy="13" r="1.2"/>',
    clock:'<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    star:'<path d="m12 3.5 2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.8l-5.2 2.8 1-5.8-4.3-4.1 5.9-.9L12 3.5z"/>',
    trash:'<path d="M4.5 7h15M9.5 7V4.5h5V7M6.5 7l1 13h9l1-13"/>',
    minus:'<path d="M5 12h14"/>',
    plus:'<path d="M12 5v14M5 12h14"/>',
    send:'<path d="M21 3 10.5 13.5M21 3l-6.5 18-4-7.5L3 9.5 21 3z"/>',
    eye:'<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/>',
    message:'<path d="M4 5h16v11H9l-5 4V5z"/>',
    note:'<path d="M5 4h14v11l-5 5H5V4z"/><path d="M14 20v-5h5M9 9h6M9 12.5h4"/>',
    signal:'<path d="M5 19v-3M10 19v-6M15 19v-9M20 19V6"/>',
    wifi:'<path d="M3 9a13 13 0 0 1 18 0M6 12.5a8.5 8.5 0 0 1 12 0M9 16a4 4 0 0 1 6 0M12 19.5v.01"/>',
    battery:'<rect x="2.5" y="8" width="17" height="8" rx="2"/><path d="M21.5 11v2"/><rect x="4.5" y="10" width="10" height="4" rx=".8" fill="currentColor" stroke="none"/>',
    compass:'<circle cx="12" cy="12" r="9"/><path d="m15.5 8.5-2 5-5 2 2-5 5-2z"/>',
    pin:'<path d="M12 21s-6.5-6-6.5-11a6.5 6.5 0 0 1 13 0c0 5-6.5 11-6.5 11z"/><circle cx="12" cy="10" r="2.3"/>',
    timer:'<circle cx="12" cy="13.5" r="7.5"/><path d="M12 9.5v4l2.5 1.5M9.5 2.5h5"/>',
    garage:'<path d="M3 9.5 12 4l9 5.5V20H3V9.5z"/><path d="M7 20v-7h10v7M7 15.5h10M7 18h10"/>',
    tag:'<path d="M3.5 12.5V4h8.5l8.5 8.5-8.5 8.5-8.5-8.5z"/><circle cx="8" cy="8.5" r="1.3"/>',
    mail:'<rect x="3" y="5.5" width="18" height="13" rx="2"/><path d="m3.5 7 8.5 6 8.5-6"/>',
    camera:'<path d="M4 8h3l1.5-2.5h7L17 8h3v11H4V8z"/><circle cx="12" cy="13.5" r="3.5"/>',
    chart:'<path d="M4 20V4M4 20h16M8 16v-4M12 16V8M16 16v-6"/>',
    badge:'<path d="M12 3 5 6v5c0 4.5 3 8 7 10 4-2 7-5.5 7-10V6l-7-3z"/><path d="m12 8.5 1.1 2.2 2.4.4-1.7 1.7.4 2.4-2.2-1.1-2.2 1.1.4-2.4-1.7-1.7 2.4-.4L12 8.5z"/>',
    bell:'<path d="M6 16v-5a6 6 0 0 1 12 0v5l1.5 2h-15L6 16zM10 20.5a2 2 0 0 0 4 0"/>',
    logout:'<path d="M14 4h4a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-4M10 16l-4-4 4-4M6 12h10"/>',
    swap:'<path d="M7 4 3 8l4 4M3 8h14M17 20l4-4-4-4M21 16H7"/>',
    hand:'<path d="M8 13V5.5a1.5 1.5 0 0 1 3 0V11M11 10V4.5a1.5 1.5 0 0 1 3 0V11M14 10.5V6a1.5 1.5 0 0 1 3 0v7c0 4.5-2.5 8-6.5 8-2.5 0-4-1.3-5.5-3.5L3.5 14a1.5 1.5 0 0 1 2.5-1.5L8 15"/>',
    radio:'<rect x="5" y="8" width="14" height="13" rx="2"/><path d="M8 8l7-5M9 12h6M9 15.5h2"/>',
    gem:'<path d="M7 4h10l4 5-9 11L3 9l4-5z"/><path d="M3 9h18M9.5 4 8 9l4 11 4-11-1.5-5"/>',
    bandage:'<path d="m4.9 13.4 8.5-8.5a3.5 3.5 0 0 1 5 5l-8.5 8.5a3.5 3.5 0 0 1-5-5z"/><path d="M10.5 10.5v.01M13.5 13.5v.01M10.5 13.5v.01M13.5 10.5v.01"/>',
    pistol:'<path d="M3 7h17v4h-6l-1 2h-3l-1.5 5h-4l1.5-7H3V7z"/><path d="M10 13h3"/>',
    bottle:'<path d="M10 2.5h4M10.5 2.5v4L8 10v10.5h8V10l-2.5-3.5v-4"/><path d="M8 14h8"/>',
    pill:'<path d="m5.5 18.5-.5-.5a4.2 4.2 0 0 1 0-6L12 5a4.2 4.2 0 0 1 6 6l-7 7a4.2 4.2 0 0 1-5.5.5z"/><path d="m8.5 8.5 7 7"/>',
    more:'<path d="M6 12h.01M12 12h.01M18 12h.01" stroke-width="3"/>',
    door:'<path d="M6 21V4a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v17M3.5 21h17M14.5 12v.5"/>',
    window:'<rect x="4" y="4" width="16" height="16" rx="2"/><path d="M4 12h16M12 4v16"/>',
    power:'<path d="M12 3v8M7 6a7.5 7.5 0 1 0 10 0"/>',
    hood:'<path d="M3 16 6 9h12l3 7H3z"/><path d="M8 9l1-3h6l1 3"/>',
    trunk:'<path d="M3 10h18v8H3zM5 10l2-4h10l2 4M10 14h4"/>',
    cuff:'<circle cx="7" cy="14" r="4"/><circle cx="17" cy="14" r="4"/><path d="M10.5 12.5h3M7 10V7.5a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2V10"/>',
    hat:'<path d="M3 17c3-1.5 15-1.5 18 0M6 16.5 7.5 8a2 2 0 0 1 2-1.5h5a2 2 0 0 1 2 1.5L18 16.5"/>',
    glasses:'<circle cx="6.5" cy="14" r="3.5"/><circle cx="17.5" cy="14" r="3.5"/><path d="M10 14h4M3 14l1-5M21 14l-1-5"/>',
    mask:'<path d="M4 8c3-2 13-2 16 0v4c0 4-4 7-8 7s-8-3-8-7V8z"/><path d="M8 11.5h2M14 11.5h2"/>',
    shoe:'<path d="M3 17v-6l3-1 3 3 5 1 6 1.5a2 2 0 0 1 1 1.5v0H3z"/><path d="M3 19.5h18"/>',
    dance:'<circle cx="12" cy="4.5" r="1.8"/><path d="M6 9l6 1 5-3M12 10v5l-3 6M12 15l4 2 1 4"/>',
    wave:'<path d="M7 11V6.5a1.5 1.5 0 0 1 3 0V11M10 10.5V4.5a1.5 1.5 0 0 1 3 0V11M13 11V6a1.5 1.5 0 0 1 3 0v7c0 4.5-2.5 8-6 8-2.5 0-4-1.3-5.5-3.5L3 14.5"/><path d="M18 3.5c1.5.8 2.5 2.2 2.8 4"/>',
    sit:'<circle cx="9" cy="4.5" r="1.8"/><path d="M9 8v6h6l2 6M9 11h5M5 21h14"/>',
  };

  // themes can register extra icons without touching this file
  const addIcons = map => Object.assign(ICONS, map);

  const icon = (name, cls = '') => {
    const p = ICONS[name] || ICONS.box;
    return `<svg class="nz-ic ${cls}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${p}</svg>`;
  };
  // <i data-ic="car"></i> → inline svg
  const hydrate = (root = document) => {
    root.querySelectorAll('[data-ic]').forEach(el => { el.outerHTML = icon(el.dataset.ic, el.className); });
  };

  /* ── shapes ── */
  const SHAPES = ['cut', 'twin', 'mirror', 'bevel', 'crest', 'flip', 'step', 'blade', 'notch', 'round'];
  const root = document.documentElement;
  const shape = name => {
    if (!SHAPES.includes(name)) return root.dataset.shape || 'cut';
    root.dataset.shape = name;
    document.querySelectorAll('.nz-shapes button').forEach(b => b.classList.toggle('on', b.dataset.s === name));
    return name;
  };
  const urlShape = new URLSearchParams(location.search).get('shape');
  if (urlShape) shape(urlShape);

  /* ── NUI bridge ── */
  const handlers = {};
  const on = (action, fn) => { handlers[action] = fn; };
  window.addEventListener('message', e => {
    const d = e.data;
    if (!d || typeof d !== 'object') return;
    const data = d.data !== undefined ? d.data : d;
    // any message may carry a shape, e.g. open { shape = 'bevel', ... }
    if (data && typeof data === 'object' && typeof data.shape === 'string') shape(data.shape);
    if (d.action === 'shape') return;
    if (handlers[d.action]) handlers[d.action](data);
  });

  async function post(name, data = {}) {
    if (!inGame) { console.info('[nz] →', name, data); return null; }
    try {
      const res = await fetch(`https://${resource}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
      });
      return await res.json();
    } catch { return null; }
  }

  /* ── open / close ── */
  let previewFn = null;
  let reopenEl = null;
  const open = el => {
    el.classList.add('nz-open');
    if (reopenEl) { reopenEl.remove(); reopenEl = null; }
  };
  const close = (el, { notify = true } = {}) => {
    if (!el.classList.contains('nz-open')) return;
    el.classList.remove('nz-open');
    if (notify) post('close');
    if (!inGame && previewFn) showReopen();
  };
  const escape = fn => window.addEventListener('keydown', e => { if (e.key === 'Escape') fn(e); });

  function showReopen() {
    if (reopenEl) return;
    reopenEl = document.createElement('div');
    reopenEl.className = 'nz-reopen';
    reopenEl.innerHTML = `<div class="nz-mark lg"></div><button class="nz-btn teal">Reopen preview</button><p>Closed · in game this posts <b>close</b> to your resource</p>`;
    reopenEl.querySelector('button').onclick = () => { reopenEl.remove(); reopenEl = null; previewFn(); };
    document.body.appendChild(reopenEl);
  }

  function shapePicker() {
    const bar = document.createElement('div');
    bar.className = 'nz-shapes';
    bar.innerHTML = '<span>Shape</span>' + SHAPES.map(n => `<button data-s="${n}">${n}</button>`).join('');
    bar.onclick = e => { const b = e.target.closest('button'); if (b) shape(b.dataset.s); };
    // keep picker clicks away from themes that listen on window (orbit, vault…)
    ['mousedown', 'mouseup', 'pointerdown', 'pointerup', 'click', 'contextmenu'].forEach(t => bar.addEventListener(t, e => e.stopPropagation()));
    document.body.appendChild(bar);
    shape(root.dataset.shape || 'cut');
  }

  // Runs fn with demo data in a browser, never in game.
  const preview = fn => {
    if (inGame) return;
    previewFn = fn;
    const scene = document.createElement('div');
    scene.className = 'nz-scene';
    document.body.prepend(scene);
    if (window.top === window) shapePicker();
    fn();
  };

  /* ── helpers ── */
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]));
  const money = (n, cur = '$') => (n < 0 ? '-' : '') + cur + Math.abs(Math.round(n)).toLocaleString('en-US');
  const initials = name => String(name || '?').split(/\s+/).map(w => w[0]).join('').slice(0, 2).toUpperCase();
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

  window.NZ = { inGame, resource, on, post, open, close, escape, preview, icon, addIcons, hydrate, esc, money, initials, shape, SHAPES, $, $$ };

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => hydrate());
  else hydrate();
})();
