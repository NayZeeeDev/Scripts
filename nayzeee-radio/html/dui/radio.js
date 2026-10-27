/* ═══════════════════════════════════════════════════════════
   NAYZEEE RADIO · on-prop radio screen (DUI)                           html/dui/radio.js

   A pure renderer. client/modules/firmware.lua decides everything (views, typed digits,
   cursors, notices, holds); this page only draws the screen state it renders. No cursor,
   no clicks, nothing is ever posted back.

   MESSAGES (SendDuiMessage, arrive as window 'message' events; a JSON string is parsed too)
     { type: 'state', state }   the whole firmware screen state (SPEC §10.3 + firmware extras):
         view 'off'|'boot'|'home'|'tune'|'code'|'memories'|'slots'|'menu'|'emergency'
         model, freq, label, access 'open'|'code'|'job', slot, slots [{ n, f, tx, rx, label, access }],
         sel, tx, rx { name, callsign, q, slot, emergency }, bars 0..4, nosignal, jam 0..1,
         volume 0..100, showVolume, mute, handsfree, clicks, earpiece, battery 0..1, time,
         entry, code ('**'), target, memories { index, count, f, label }, mem,
         menu { items [{ id, label, value }], index (0-based) }, title, hint, notice, busy, emergency
     { type: 'ping' }           keep-alive from screen.lua (re-draws the last state)

   SKINS (?skin=, sized to the DUI; ?w= / ?h= scale the drawing to another texture size)
     px740  colour TFT, 512x384   deep blue-black glass, white type, teal accents, slot ladder,
                                  rolling frequency, band scale, RX / TX strip
     fx280  segment LCD, 512x256  grey-green STN panel, SVG 7-segment digits with ghost segments,
                                  segment annunciators, one dot-matrix line (VT323) that scrolls
     mx905  tactical, 512x384     black glass, phosphor green mono, grid frame, NET header,
                                  segmented signal arc, net cells, one status line

   Device words that are not in the state (MHz, TX, RX, VOL ...) are the WORDS table below:
   generic labelling printed by the device itself. Titles, hints and notices come from the
   firmware (locales/en/client.lua, client.scr_*).

   BROWSER   radio.html?skin=px740&demo=1   every view in turn with sample data
             radio.html?skin=fx280&demo=menu   one view frozen (see DEMO_VIEWS)

   In-world device face: model codes only, no NAYZEEE name or mark (customer rule B).
   ═══════════════════════════════════════════════════════════ */
(() => {
  'use strict';

  /* ─────────────── page, skin, size ─────────────── */
  const Q = new URLSearchParams(location.search);
  const DIMS = { px740: [512, 384], fx280: [512, 256], mx905: [512, 384] };
  const MODEL = { px740: 'PX-740', fx280: 'FX-280', mx905: 'MX-905' };
  const SKIN = DIMS[Q.get('skin')] ? Q.get('skin') : 'px740';
  const [BW, BH] = DIMS[SKIN];
  const px = (v, d) => { const n = Math.round(Number(v)); return Number.isFinite(n) && n >= 64 && n <= 4096 ? n : d; };
  const W = px(Q.get('w'), BW), H = px(Q.get('h'), BH);
  const DEMO = Q.get('demo');

  const WORDS = {
    mhz: 'MHz', tx: 'TX', rx: 'RX', vol: 'VOL', mute: 'MUTE', hf: 'HF', mem: 'MEM', lock: 'LOCK',
    standby: 'STANDBY', interference: 'INTERFERENCE', live: 'MIC LIVE', keyed: 'KEYED', nosignal: 'NO SIGNAL', nosig: 'NO SIG',
    nochannel: 'NO CHANNEL', keyin: 'KEY IN A CHANNEL', open: 'OPEN', code: 'CODE', job: 'JOB',
    free: 'FREE', idle: 'IDLE', unit: 'UNIT', of: '/', store: 'STORE', net: 'NET', sec: 'SEC',
    clr: 'CLR', sig: 'SIG', jam: 'JAM', link: 'LINK', stby: 'STBY', emerg: 'EMRG',
    selftest: 'SELF TEST', checks: ['RF', 'AUDIO', 'KEYS'], ok: 'OK', band: [1, 250, 500, 750, 999],
    titles: { tune: 'TUNE', code: 'ACCESS CODE', memories: 'MEMORY', slots: 'SLOTS', menu: 'MENU', emergency: 'EMERGENCY', boot: 'SELF TEST' },
  };

  /* ─────────────── helpers ─────────────── */
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const num = (v, d = 0) => { const n = Number(v); return Number.isFinite(n) ? n : d; };
  const clamp = (n, a, b) => Math.max(a, Math.min(b, n));
  const str = v => (typeof v === 'string' || typeof v === 'number' ? String(v) : '');
  const up = v => str(v).toUpperCase();
  const pad2 = n => String(Math.max(0, Math.floor(n))).padStart(2, '0');
  const mmss = ms => { const s = Math.floor(Math.max(0, ms) / 1000); return `${pad2(Math.floor(s / 60) % 100)}:${pad2(s % 60)}`; };
  const $ = (sel, r) => (r || document).querySelector(sel);
  const $$ = (sel, r) => [...(r || document).querySelectorAll(sel)];
  const set = (sel, r, v) => { const e = $(sel, r); if (e && e.textContent !== v) e.textContent = v; return e; };
  const html = (e, v) => { if (e && e._h !== v) { e.innerHTML = v; e._h = v; } return e; };
  const tog = (e, cls, on) => { if (e) e.classList.toggle(cls, !!on); return e; };
  const now = () => performance.now();
  const one = v => str(v).replace(/\s+/g, ' ').trim();

  // '155.5' | 155.5 → '155.50'; anything else → null (the Lua side sends fkeys already)
  const fkey = v => {
    if (v === null || v === undefined || v === false || v === '') return null;
    const n = Number(String(v).replace(',', '.'));
    return Number.isFinite(n) && n > 0 ? n.toFixed(2) : null;
  };

  // "* point  ·  OK join" → key names as key caps (*, #, OK, BACK, keys, 0-9)
  const keyHint = s => esc(s).replace(/(^|[\s(])(\*|#|OK|BACK|CLR|0-9)(?=[\s:·)]|$)/g, '$1<kbd>$2</kbd>').replace(/<\/kbd>:/g, '</kbd>');

  // the typed frequency split for drawing: typed part, what OK would add ('.00' / '0')
  function entryParts(e) {
    e = str(e);
    const dot = e.indexOf('.');
    const ghost = dot === -1 ? '.00' : '0'.repeat(Math.max(0, 2 - (e.length - dot - 1)));
    return { typed: e, ghost };
  }
  // position of a frequency on the band scale (1..999.99) → 0..1
  const bandPos = f => clamp((num(f, 0) - 1) / 998.99, 0, 1);

  /* ─────────────── state ─────────────── */
  const VIEWS = ['off', 'boot', 'home', 'tune', 'code', 'memories', 'slots', 'menu', 'emergency'];
  const list = v => (Array.isArray(v) ? v : v && typeof v === 'object' ? Object.values(v) : []);

  function norm(s) {
    s = s && typeof s === 'object' ? s : {};
    const mem = s.memories && typeof s.memories === 'object' ? s.memories : {};
    const menu = s.menu && typeof s.menu === 'object' ? s.menu : {};
    const items = list(menu.items).filter(i => i && typeof i === 'object');
    const r = s.rx && typeof s.rx === 'object' ? s.rx : null;
    const view = VIEWS.includes(s.view) ? s.view : 'off';
    return {
      view,
      model: up(s.model) || MODEL[SKIN],
      freq: fkey(s.freq),
      label: str(s.label),
      access: ['open', 'code', 'job'].includes(s.access) ? s.access : null,
      slot: Math.max(1, Math.round(num(s.slot, 1))),
      slots: list(s.slots).slice(0, 8).map((row, i) => {
        row = row && typeof row === 'object' ? row : {};
        return { n: Math.round(num(row.n, i + 1)), f: fkey(row.f), tx: row.tx === true, rx: row.rx === true, label: str(row.label), access: row.access || null };
      }),
      sel: Math.round(num(s.sel, 0)),
      tx: s.tx === true,
      rx: r ? { name: str(r.name), callsign: str(r.callsign), q: clamp(num(r.q, 1), 0, 1), slot: Math.round(num(r.slot, 0)) || null, emergency: r.emergency === true } : null,
      bars: clamp(Math.round(num(s.bars, 0)), 0, 4),
      nosignal: s.nosignal === true,
      jam: clamp(num(s.jam, 0), 0, 1),
      volume: clamp(Math.round(num(s.volume, 0)), 0, 100),
      showVolume: s.showVolume === true,
      mute: s.mute === true,
      handsfree: s.handsfree === true,
      clicks: s.clicks !== false,
      earpiece: s.earpiece === true,
      battery: clamp(num(s.battery, 1), 0, 1),
      time: str(s.time).slice(0, 8),
      entry: str(s.entry).slice(0, 7),
      code: str(s.code).slice(0, 6),
      target: fkey(s.target),
      memories: { index: Math.max(1, Math.round(num(mem.index, 1))), count: Math.max(0, Math.round(num(mem.count, 0))), f: fkey(mem.f), label: str(mem.label) },
      mem: Math.round(num(s.mem, 0)) || null,
      menu: { items: items.map(i => ({ id: str(i.id), label: str(i.label), value: i.value === null || i.value === undefined ? null : str(i.value) })), index: clamp(Math.round(num(menu.index, 0)), 0, Math.max(0, items.length - 1)) },
      title: str(s.title) || WORDS.titles[view] || '',
      hint: str(s.hint),
      notice: str(s.notice) || null,
      busy: s.busy === true,
      emergency: s.emergency === true,
    };
  }

  // what the page keeps between states: when the mic opened (TX timer), the boot start ...
  const live = { txSince: 0, view: null, bootAt: 0, st: null, prev: null };

  /* ─────────────── icons (heavy strokes: read at an angle through glass) ─────────────── */
  const svg = (body, cls = '') => `<svg class="ic ${cls}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="square" stroke-linejoin="miter">${body}</svg>`;
  const IC = {
    lock: svg('<path d="M7.5 10.5V7.5a4.5 4.5 0 0 1 9 0v3"/><path d="M5 10.5h14v10H5Z" fill="currentColor" stroke="none"/>'),
    badge: svg('<path d="M12 2.6 20 5.8v6c0 4.7-3.3 8-8 9.6-4.7-1.6-8-4.9-8-9.6v-6Z" fill="currentColor" stroke="none"/>'),
    mute: svg('<path d="M3.5 9h4l5.5-4.6v15.2L7.5 15h-4Z" fill="currentColor" stroke="none"/><path d="M16 9l5.5 6M21.5 9 16 15"/>'),
    spk: svg('<path d="M3.5 9h4l5.5-4.6v15.2L7.5 15h-4Z" fill="currentColor" stroke="none"/><path d="M16.2 9.2a4 4 0 0 1 0 5.6M19 6.5a7.8 7.8 0 0 1 0 11"/>'),
    mic: svg('<path d="M9 3h6v11H9Z" fill="currentColor" stroke="none"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21.5"/>'),
    ear: svg('<path d="M7 15.5V10a5 5 0 0 1 10 0c0 3.4-3.5 3.8-3.5 6.8a2.6 2.6 0 0 1-5.2.2"/><path d="M10.5 10.5a1.6 1.6 0 0 1 3 0"/>'),
    siren: svg('<path d="M6 18.5V12a6 6 0 0 1 12 0v6.5Z" fill="currentColor" stroke="none"/><path d="M3.5 18.5h17v3h-17ZM12 1.5v2.5M3.6 5.2l1.8 1.8M20.4 5.2l-1.8 1.8"/>'),
    tri: '<svg class="ic tri" viewBox="0 0 12 12"><path d="M2 1.5 10.5 6 2 10.5Z" fill="currentColor"/></svg>',
    tril: '<svg class="ic tri" viewBox="0 0 12 12"><path d="M10 1.5 1.5 6 10 10.5Z" fill="currentColor"/></svg>',
  };

  /* ─────────────── rolling digits (odometer) ─────────────── */
  const STRIP = '<span class="rs">' + '0123456789'.split('').map(d => `<i>${d}</i>`).join('') + '</span>';
  function Roller(host, cls = '') {
    const root = document.createElement('span');
    root.className = `roll ${cls}`;
    host.appendChild(root);
    let shape = null, cur = null;
    return {
      el: root,
      set(v) {
        v = String(v);
        if (v === cur) return;
        const sh = v.replace(/\d/g, 'd');
        if (sh !== shape) {
          // a new layout: digits start at 0 and roll up to their value
          root.innerHTML = [...v].map(ch => (/\d/.test(ch) ? `<span class="rd">${STRIP}</span>` : `<span class="rc">${esc(ch)}</span>`)).join('');
          shape = sh;
          void root.offsetWidth;
        }
        [...v].forEach((ch, i) => {
          const c = root.children[i];
          if (c && c.classList.contains('rd')) c.firstChild.style.transform = `translateY(${-Number(ch)}em)`;
        });
        cur = v;
      },
    };
  }

  /* ─────────────── 7-segment digits (fx280) ───────────────
     Drawn as SVG polygons (bevelled hexagons) so they look like real LCD segments, with every
     unlit segment still faintly visible ("ghost"), slanted like the glass print. */
  const SEG = {
    0: 'abcdef', 1: 'bc', 2: 'abdeg', 3: 'abcdg', 4: 'bcfg', 5: 'acdfg', 6: 'acdefg', 7: 'abc', 8: 'abcdefg', 9: 'abcdfg',
    '-': 'g', _: 'd', ' ': '', A: 'abcefg', b: 'cdefg', C: 'adef', c: 'deg', d: 'bcdeg', E: 'adefg', F: 'aefg', G: 'acdef',
    H: 'bcefg', h: 'cefg', I: 'bc', J: 'bcde', L: 'def', n: 'ceg', O: 'abcdef', o: 'cdeg', P: 'abefg', r: 'eg', S: 'acdfg',
    t: 'defg', U: 'bcdef', u: 'cde', y: 'bcdfg', '°': 'abfg', '=': 'dg', '8': 'abcdefg',
  };
  function segPolys(w, h, t, g) {
    const hz = (x1, x2, y) => `${x1},${y} ${x1 + t / 2},${y - t / 2} ${x2 - t / 2},${y - t / 2} ${x2},${y} ${x2 - t / 2},${y + t / 2} ${x1 + t / 2},${y + t / 2}`;
    const vt = (x, y1, y2) => `${x},${y1} ${x + t / 2},${y1 + t / 2} ${x + t / 2},${y2 - t / 2} ${x},${y2} ${x - t / 2},${y2 - t / 2} ${x - t / 2},${y1 + t / 2}`;
    const L = t / 2, R = w - t / 2, T = t / 2, M = h / 2, B = h - t / 2;
    return {
      a: hz(L + g, R - g, T), b: vt(R, T + g, M - g), c: vt(R, M + g, B - g), d: hz(L + g, R - g, B),
      e: vt(L, M + g, B - g), f: vt(L, T + g, M - g), g: hz(L + g, R - g, M),
    };
  }
  /** Seg7(host, { n, w, h, t, gap, dp, colon, cls }) → { set(text, { blink }) }
      text: one char per cell, '.' lights the previous cell's point, ':' the colon after cell 2 */
  function Seg7(host, { n = 5, w = 46, h = 86, t = 10, gap = 14, dp = true, colon = false, cls = '' } = {}) {
    const P = segPolys(w, h, t, Math.max(1, t * 0.14));
    const dpR = t * 0.62, skew = -7, padL = h * 0.13 + 2;
    const cw = w + gap;
    const width = Math.ceil(padL + n * cw + (colon ? gap : 0));
    let body = '';
    for (let i = 0; i < n; i++) {
      const x = padL + i * cw + (colon && i >= 2 ? gap : 0);
      body += `<g class="cell" transform="translate(${x.toFixed(1)} 0) skewX(${skew})">` +
        Object.keys(P).map(k => `<polygon class="sg s-${k}" points="${P[k]}"/>`).join('') +
        (dp ? `<circle class="sg s-dp" cx="${(w + gap * 0.5).toFixed(1)}" cy="${(h - dpR).toFixed(1)}" r="${dpR.toFixed(1)}"/>` : '') + '</g>';
    }
    if (colon) {
      const cx = padL + 2 * cw + gap * 0.15;
      body += `<g transform="skewX(${skew})"><rect class="sg s-col" x="${(cx + h * 0.12).toFixed(1)}" y="${(h * 0.28).toFixed(1)}" width="${(t * 1.05).toFixed(1)}" height="${(t * 1.05).toFixed(1)}"/>` +
        `<rect class="sg s-col" x="${(cx + h * 0.05).toFixed(1)}" y="${(h * 0.64).toFixed(1)}" width="${(t * 1.05).toFixed(1)}" height="${(t * 1.05).toFixed(1)}"/></g>`;
    }
    host.insertAdjacentHTML('beforeend', `<svg class="seg7 ${cls}" viewBox="0 0 ${width} ${h}" width="${width}" height="${h}">${body}</svg>`);
    const root = host.lastElementChild;
    const cells = $$('.cell', root);
    let last = null;
    return {
      el: root,
      set(text, { blink = -1, colonOn = false } = {}) {
        const key = `${text}|${blink}|${colonOn}`;
        if (key === last) return;
        last = key;
        const chars = [], dots = [];
        for (const ch of String(text)) {
          if (ch === '.' && chars.length) { dots[chars.length - 1] = true; continue; }
          chars.push(ch);
        }
        cells.forEach((c, i) => {
          const on = SEG[chars[i]] !== undefined ? SEG[chars[i]] : (chars[i] && SEG[String(chars[i]).toUpperCase()]) || '';
          $$('.sg', c).forEach(p => {
            const k = p.classList[1].slice(2);
            p.classList.toggle('on', k === 'dp' ? !!dots[i] : on.includes(k));
          });
          c.classList.toggle('blink', i === blink);
        });
        $$('.s-col', root).forEach(p => p.classList.toggle('on', colonOn));
      },
    };
  }

  /* ─────────────── shared bits ─────────────── */
  const barsHTML = (n, cls = '') => `<span class="bars ${cls}">${[1, 2, 3, 4].map(i => `<i class="b${i}"></i>`).join('')}</span>`;
  const setBars = (e, n) => { if (e) $$('i', e).forEach((b, i) => b.classList.toggle('on', i < n)); };
  const segBar = (n, total) => Array.from({ length: total }, (_, i) => `<i class="${i < n ? 'on' : ''}"></i>`).join('');
  const talkerName = r => (r ? (r.name || r.callsign || WORDS.unit) : '');

  function setView(root, view) {
    $$('.view', root).forEach(v => {
      const on = v.classList.contains(`v-${view}`);
      if (on !== v.classList.contains('up')) v.classList.toggle('up', on);
    });
  }

  // the list window around the cursor (menus, slots): at most `max` rows
  function windowOf(count, index, max) {
    if (count <= max) return [0, count];
    const start = clamp(index - Math.floor(max / 2), 0, count - max);
    return [start, start + max];
  }

  /* ═══════════════════════════ PX-740 · colour TFT ═══════════════════════════ */
  const PX740 = {
    build(root) {
      root.innerHTML = `
<div class="sk px">
  <div class="px-bar">
    <span class="px-sig">${barsHTML(0)}<b class="px-nosig">${WORDS.nosig}</b></span>
    <b class="px-slot">S1</b>
    <span class="px-acc"></span>
    <span class="px-busy"><i></i><i></i><i></i></span>
    <span class="sp"></span>
    <span class="px-ic px-mute">${IC.mute}</span>
    <span class="px-ic px-hf">${IC.mic}<b>${WORDS.hf}</b></span>
    <span class="px-ic px-ear">${IC.ear}</span>
    <span class="px-bat"><i></i><i></i><i></i></span>
    <b class="px-clock">--:--</b>
  </div>
  <section class="view v-home">
    <div class="px-ladder"></div>
    <div class="px-main">
      <div class="px-tags"><b class="px-memtag"></b><b class="px-acctag"></b><span class="sp"></span><em>${WORDS.mhz}</em></div>
      <div class="px-freq"></div>
      <div class="px-label"></div>
      <div class="px-scale"><span class="sc"></span><i class="nd"></i></div>
    </div>
    <div class="px-strip">
      <div class="st st-idle">${IC.spk}<span class="px-volbar"></span><b class="vv"></b><span class="sp"></span><em>${WORDS.standby}</em></div>
      <div class="st st-rx"><b class="tag">${WORDS.rx}</b><b class="cs"></b><span class="nm"></span><span class="sp"></span><span class="qm"></span><b class="qv"></b></div>
      <div class="st st-tx"><b class="tag">${WORDS.tx}</b><span class="nm">${WORDS.live}</span><span class="vu">${'<i></i>'.repeat(9)}</span><span class="sp"></span><b class="tt js-txt">00:00</b></div>
    </div>
  </section>
  <section class="view v-tune">
    <div class="px-head"><i class="ac"></i><b class="ttl"></b><span class="sp"></span><b class="px-chip js-slot"></b></div>
    <div class="px-entry"><span class="ty"></span><i class="cur"></i><span class="gh"></span><em>${WORDS.mhz}</em></div>
    <div class="px-scale wide"><span class="sc"></span><i class="nd"></i></div>
    <div class="px-hint"></div>
  </section>
  <section class="view v-code">
    <div class="px-head"><i class="ac amber"></i><b class="ttl"></b><span class="sp"></span><span class="px-hic">${IC.lock}</span></div>
    <div class="px-ctgt"><b class="cf"></b><em>${WORDS.mhz}</em><span class="cl"></span></div>
    <div class="px-cells">${'<i><b></b></i>'.repeat(4)}</div>
    <div class="px-hint"></div>
  </section>
  <section class="view v-memories">
    <div class="px-head"><i class="ac"></i><b class="ttl"></b><span class="sp"></span><b class="px-of"></b></div>
    <div class="px-mem">
      <div class="px-mix"></div>
      <div class="px-mdat"><div class="mf"></div><div class="ml"></div><div class="ms"></div></div>
    </div>
    <div class="px-rail"></div>
    <div class="px-hint"></div>
  </section>
  <section class="view v-slots">
    <div class="px-head"><i class="ac"></i><b class="ttl"></b><span class="sp"></span><b class="px-of"></b></div>
    <div class="px-list js-slots"></div>
    <div class="px-hint"></div>
  </section>
  <section class="view v-menu">
    <div class="px-head"><i class="ac"></i><b class="ttl"></b><span class="sp"></span><b class="px-of"></b></div>
    <div class="px-list js-menu"></div>
    <div class="px-hint"></div>
  </section>
  <section class="view v-emergency">
    <div class="px-emg">
      <div class="eh">${IC.siren}<b class="ttl"></b></div>
      <div class="ef"><b class="ff"></b><em>${WORDS.mhz}</em><span class="el"></span></div>
      <div class="ei"></div>
    </div>
    <div class="px-hazard"></div>
  </section>
  <section class="view v-boot">
    <div class="px-boot">
      <b class="bm"></b>
      <span class="bt"></span>
      <span class="bp"><i></i></span>
      <span class="bc">${WORDS.checks.map((c, i) => `<em style="--d:${i}">${esc(c)}<b>${WORDS.ok}</b></em>`).join('')}</span>
    </div>
    <i class="px-sweep"></i>
  </section>
  <div class="px-vol"><span class="vi"></span><b class="vl">${WORDS.vol}</b><span class="vb"></span><b class="vn"></b></div>
  <div class="px-note"><b></b></div>
</div>`;
      const r = root.firstElementChild;
      this.r = r;
      this.freq = Roller($('.px-freq', r), 'big');
      this.scaleMarks($$('.px-scale .sc', r));
    },
    scaleMarks(hosts) {
      const ticks = Array.from({ length: 41 }, (_, i) => `<i class="${i % 10 === 0 ? 'mj' : i % 5 === 0 ? 'md' : ''}" style="left:${(i * 2.5).toFixed(1)}%"></i>`).join('');
      hosts.forEach(h => { h.innerHTML = ticks; });
    },
    draw(s) {
      const r = this.r;
      setView(r, s.view);
      // status bar
      setBars($('.px-sig .bars', r), s.bars);
      tog($('.px-sig', r), 'nosig', s.nosignal);
      set('.px-slot', r, `S${s.slot}`);
      html($('.px-acc', r), s.access === 'code' ? IC.lock : s.access === 'job' ? IC.badge : '');
      tog($('.px-busy', r), 'on', s.busy);
      tog($('.px-mute', r), 'on', s.mute);
      tog($('.px-hf', r), 'on', s.handsfree);
      tog($('.px-ear', r), 'on', s.earpiece);
      const bat = Math.ceil(s.battery * 3 - 0.05);
      $$('.px-bat i', r).forEach((b, i) => b.classList.toggle('on', i < bat));
      tog($('.px-bat', r), 'low', s.battery < 0.2);
      set('.px-clock', r, s.time || '--:--');

      const v = s.view;
      if (v === 'home') this.home(s);
      else if (v === 'tune') {
        const sec = $('.v-tune', r), p = entryParts(s.entry);
        set('.ttl', sec, s.title);
        set('.js-slot', sec, `S${s.slot}`);
        set('.ty', sec, p.typed);
        set('.gh', sec, p.ghost);
        this.needle($('.px-scale', sec), s.entry ? bandPos(s.entry) : null);
        html($('.px-hint', sec), keyHint(s.hint));
      } else if (v === 'code') {
        const sec = $('.v-code', r);
        set('.ttl', sec, s.title);
        set('.cf', sec, s.target || s.freq || '---.--');
        set('.cl', sec, !s.target || s.target === s.freq ? s.label : '');
        $$('.px-cells i', sec).forEach((c, i) => { c.classList.toggle('on', i < s.code.length); c.classList.toggle('cur', i === s.code.length); });
        html($('.px-hint', sec), keyHint(s.hint));
      } else if (v === 'memories') {
        const sec = $('.v-memories', r), m = s.memories;
        set('.ttl', sec, s.title);
        set('.px-of', sec, `${pad2(m.index)} ${WORDS.of} ${pad2(m.count)}`);
        set('.px-mix', sec, pad2(m.index));
        const mf = set('.mf', sec, m.f || WORDS.free);
        tog(mf, 'free', !m.f);
        set('.ml', sec, m.f ? (m.label || WORDS.open) : (m.label && m.label.toUpperCase() !== WORDS.free ? m.label : ''));
        const ms = $('.ms', sec);
        html(ms, s.entry ? `${IC.tri}<b>${esc(WORDS.store)}</b><span>${esc(s.entry)}</span><i class="cur"></i>` : '');
        html($('.px-rail', sec), Array.from({ length: Math.min(m.count, 12) }, (_, i) => `<i class="${i + 1 === m.index ? 'on' : ''}">${i + 1}</i>`).join(''));
        html($('.px-hint', sec), keyHint(s.hint));
      } else if (v === 'slots') {
        const sec = $('.v-slots', r);
        set('.ttl', sec, s.title);
        const sel = clamp(s.sel || s.slot, 1, Math.max(1, s.slots.length));
        set('.px-of', sec, `S${sel} ${WORDS.of} ${s.slots.length}`);
        const [a, b] = windowOf(s.slots.length, sel - 1, 4);
        html($('.js-slots', sec), s.slots.slice(a, b).map(row => {
          const on = row.n === sel;
          const f = on && s.entry ? `<span class="ed">${esc(s.entry)}<i class="cur"></i></span>` : esc(row.f || '———');
          return `<div class="li${on ? ' on' : ''}${row.f ? '' : ' empty'}"><b class="n">${row.n}</b><b class="f">${f}</b><span class="l">${esc(row.label || (row.f ? WORDS.open : WORDS.idle))}</span>` +
            `${row.access === 'code' ? `<span class="lk">${IC.lock}</span>` : ''}${row.rx ? `<b class="t rx">${WORDS.rx}</b>` : ''}${row.tx ? `<b class="t tx">${WORDS.tx}</b>` : ''}</div>`;
        }).join(''));
        html($('.px-hint', sec), keyHint(s.hint));
      } else if (v === 'menu') {
        const sec = $('.v-menu', r), items = s.menu.items;
        set('.ttl', sec, s.title);
        set('.px-of', sec, items.length ? `${s.menu.index + 1} ${WORDS.of} ${items.length}` : '');
        const [a, b] = windowOf(items.length, s.menu.index, 5);
        html($('.js-menu', sec), items.slice(a, b).map((it, k) => {
          const on = a + k === s.menu.index;
          const val = it.value === null ? '' : `<b class="v ${/^(ON)$/i.test(it.value) ? 'yes' : /^(OFF)$/i.test(it.value) ? 'no' : ''}">${esc(it.value)}</b>`;
          return `<div class="li mi${on ? ' on' : ''}">${on ? IC.tri : '<i class="sp0"></i>'}<span class="l">${esc(it.label)}</span>${val}</div>`;
        }).join('') + (items.length > 5 ? `<i class="sbar" style="--a:${a / items.length};--b:${(b - a) / items.length}"></i>` : ''));
        html($('.px-hint', sec), keyHint(s.hint));
      } else if (v === 'emergency') {
        const sec = $('.v-emergency', r);
        set('.ttl', sec, s.title);
        set('.ff', sec, s.freq || '---.--');
        set('.el', sec, s.label);
        html($('.ei', sec), keyHint(s.hint));
      } else if (v === 'boot') {
        const sec = $('.v-boot', r);
        set('.bm', sec, s.model);
        set('.bt', sec, s.title || WORDS.selftest);
      }

      // volume popup + notice
      const vol = $('.px-vol', r);
      tog(vol, 'on', s.showVolume && v !== 'off' && v !== 'boot');
      html($('.vi', vol), s.mute ? IC.mute : IC.spk);
      tog(vol, 'muted', s.mute);
      html($('.vb', vol), segBar(Math.round(s.volume / 5), 20));
      set('.vn', vol, String(s.volume));
      const note = $('.px-note', r);
      tog(note, 'on', !!s.notice && v !== 'off' && v !== 'boot');
      if (s.notice) set('b', note, s.notice);
    },
    home(s) {
      const sec = $('.v-home', this.r);
      html($('.px-ladder', sec), s.slots.map(row =>
        `<div class="lr${row.tx ? ' tx' : ''}${row.rx ? ' rx' : ''}${row.f ? '' : ' empty'}"><b class="n">${row.n}</b><span class="d"><b>${esc(row.f || '———')}</b>` +
        `<em>${row.tx ? `<i class="t">${WORDS.tx}</i>` : ''}${row.rx ? `<i class="r">${WORDS.rx}</i>` : ''}${!row.tx && !row.rx && row.access === 'code' ? IC.lock : ''}</em></span></div>`).join(''));
      tog(sec, 'n4', s.slots.length > 3);
      this.freq.set(s.freq || '---.--');
      tog($('.px-freq', sec), 'none', !s.freq);
      const mt = set('.px-memtag', sec, s.mem ? `M${s.mem}` : '');
      tog(mt, 'on', !!s.mem);
      const at = $('.px-acctag', sec);
      html(at, s.freq ? (s.access === 'code' ? `${IC.lock}${WORDS.code}` : s.access === 'job' ? `${IC.badge}${WORDS.job}` : WORDS.open) : '');
      at.className = `px-acctag ${s.freq ? s.access || 'open' : ''}`;
      const lab = set('.px-label', sec, s.freq ? (s.label || `S${s.slot} · ${WORDS.open}`) : WORDS.keyin);
      tog(lab, 'dim', !s.freq || !s.label);
      this.needle($('.px-scale', sec), s.freq ? bandPos(s.freq) : null);
      // strip
      const strip = $('.px-strip', sec);
      const mode = s.tx ? 'tx' : s.rx ? 'rx' : 'idle';
      strip.dataset.mode = mode;
      tog(strip, 'emg', !!(s.rx && s.rx.emergency));
      if (mode === 'rx') {
        const rx = s.rx;
        const tag = $('.st-rx .tag', strip);
        tag.textContent = rx.emergency ? WORDS.emerg : rx.slot && rx.slot !== s.slot ? `${WORDS.rx}${rx.slot}` : WORDS.rx;
        const cs = set('.st-rx .cs', strip, rx.callsign);
        tog(cs, 'hide', !rx.callsign);
        set('.st-rx .nm', strip, rx.name || (rx.callsign ? '' : WORDS.unit));
        const lit = Math.round(rx.q * 6);
        html($('.st-rx .qm', strip), Array.from({ length: 6 }, (_, i) => `<i class="${i < lit ? 'on' : ''}" style="height:${10 + i * 6}px"></i>`).join(''));
        set('.st-rx .qv', strip, String(Math.round(rx.q * 100)));
      } else if (mode === 'idle') {
        html($('.px-volbar', strip), segBar(Math.round(s.volume / 6.25), 16));
        tog($('.st-idle', strip), 'muted', s.mute);
        set('.st-idle .vv', strip, s.mute ? WORDS.mute : String(s.volume));
        // the right end of the strip: what the radio is up to when nobody talks
        const em = $('.st-idle em', strip);
        const jammed = !s.nosignal && s.jam >= 0.3;
        em.textContent = s.nosignal ? WORDS.nosignal : jammed ? WORDS.interference : WORDS.standby;
        tog(em, 'bad', s.nosignal);
        tog(em, 'warn', jammed);
      }
    },
    needle(scale, pos) {
      if (!scale) return;
      tog(scale, 'none', pos === null);
      if (pos !== null) $('.nd', scale).style.left = `${(pos * 100).toFixed(2)}%`;
    },
  };

  /* ═══════════════════════════ FX-280 · segment LCD ═══════════════════════════ */
  const DOT_N = 19;
  const BLOCK = '\u2588';   // a filled dot-matrix cell
  const FX280 = {
    build(root) {
      const ann = (cls, label) => `<b class="an ${cls}">${label}</b>`;
      root.innerHTML = `
<div class="sk fx">
  <div class="fx-icons">
    <svg class="fx-sig" viewBox="0 0 64 30"><path class="sg a-ant" d="M2 3h14l-6 8v17H8V11Z"/>${[0, 1, 2, 3].map(i => `<rect class="sg a-b${i + 1}" x="${22 + i * 10.5}" y="${22 - i * 6.5}" width="7" height="${7 + i * 6.5}"/>`).join('')}</svg>
    ${ann('a-tx', WORDS.tx)}${ann('a-rx', WORDS.rx)}${ann('a-mem', WORDS.mem)}${ann('a-hf', WORDS.hf)}
    <svg class="fx-mute" viewBox="0 0 30 26"><path class="sg a-spk" d="M2 8h6l8-6v22l-8-6H2Z"/><path class="sg a-x" d="M19 7.5l2-2 3 3 3-3 2 2-3 3 3 3-2 2-3-3-3 3-2-2 3-3Z"/></svg>
    <svg class="fx-lock" viewBox="0 0 22 26"><path class="sg a-lock" fill-rule="evenodd" d="M5 11V7.5a6 6 0 0 1 12 0V11h-3V7.5a3 3 0 0 0-6 0V11Z M2 11h18v14H2Z"/></svg>
    ${ann('a-emg', 'SOS')}
    <span class="sp"></span>
    <svg class="fx-bat" viewBox="0 0 46 22"><path class="sg a-bo" fill-rule="evenodd" d="M1 2h40v5h4v8h-4v5H1Z M4 5v12h34V5Z"/>${[0, 1, 2].map(i => `<rect class="sg a-c${i + 1}" x="${6.5 + i * 10.5}" y="7.5" width="8.5" height="7"/>`).join('')}</svg>
    <span class="fx-clk"></span>
  </div>
  <div class="fx-main">
    <div class="fx-side">
      <div class="fx-sd"><em>CH</em><span class="js-ch"></span></div>
      <div class="fx-sd"><em>M</em><span class="js-m"></span></div>
    </div>
    <div class="fx-big"></div>
    <div class="fx-unit"><span class="fx-vol"><span class="vb"></span></span><b class="an a-code">${WORDS.code}</b><b class="an a-mhz">${WORDS.mhz}</b></div>
  </div>
  <div class="fx-dot"><span class="cells"></span></div>
  <div class="fx-test"></div>
</div>`;
      const r = root.firstElementChild;
      this.r = r;
      this.big = Seg7($('.fx-big', r), { n: 5, w: 48, h: 90, t: 11, gap: 13 });
      this.ch = Seg7($('.js-ch', r), { n: 1, w: 18, h: 34, t: 5.5, gap: 5, dp: false, cls: 'sm' });
      this.m = Seg7($('.js-m', r), { n: 2, w: 18, h: 34, t: 5.5, gap: 5, dp: false, cls: 'sm' });
      this.clk = Seg7($('.fx-clk', r), { n: 4, w: 13, h: 24, t: 4, gap: 4.5, dp: false, colon: true, cls: 'xs' });
      $('.fx-dot .cells', r).innerHTML = Array.from({ length: DOT_N }, () => '<i><b></b></i>').join('');
      // the volume ladder is a segment group: always printed (ghost), lit only while the level is shown
      $('.fx-vol .vb', r).innerHTML = Array.from({ length: 10 }, (_, i) => `<i style="height:${5 + i * 2.1}px"></i>`).join('');
      this.dotText = '';
      this.dotOpts = {};
      this.marq = 0;
      this.marqAt = 0;
    },
    // the dot-matrix line: text (uppercase), centred or left, inverted, blinking, scrolling when long
    dot(text, opts = {}) {
      text = up(text);
      const key = `${text}|${opts.inv ? 1 : 0}|${opts.blink ? 1 : 0}|${opts.center ? 1 : 0}`;
      if (key !== this.dotKey) { this.dotKey = key; this.marq = 0; this.marqAt = now(); }
      this.dotText = text;
      this.dotOpts = opts;
      this.paintDot();
    },
    paintDot() {
      const r = this.r, text = this.dotText, o = this.dotOpts;
      let shown;
      if (text.length > DOT_N) {
        const loop = `${text}    `;
        const k = this.marq % loop.length;
        shown = (loop + loop).slice(k, k + DOT_N);
      } else if (o.center) shown = ' '.repeat(Math.floor((DOT_N - text.length) / 2)) + text;
      else shown = text;
      $$('.fx-dot .cells i', r).forEach((c, i) => {
        const ch = shown[i] || ' ';
        const blk = ch === BLOCK;
        const t = blk || ch === ' ' ? '' : ch;
        if (c.firstChild.textContent !== t) c.firstChild.textContent = t;
        c.classList.toggle('blk', blk);
      });
      const line = $('.fx-dot', r);
      tog(line, 'inv', !!o.inv);
      tog(line, 'blink', !!o.blink);
    },
    tick(t) {
      if (this.dotText.length > DOT_N && t - this.marqAt > (this.marq === 0 ? 900 : 260)) {
        this.marq++;
        this.marqAt = t;
        this.paintDot();
      }
    },
    draw(s) {
      const r = this.r, v = s.view;
      r.dataset.view = v;
      const ann = (cls, on, blink) => { const e = $(`.${cls}`, r); if (e) { e.classList.toggle('on', !!on); e.classList.toggle('blink', !!blink); } };
      const allOn = v === 'boot' && now() - live.bootAt < 650;
      tog(r, 'lamp', allOn);
      if (v === 'boot' && !allOn) s = Object.assign({}, s, { bars: 0, tx: false, rx: null, mem: null, handsfree: false, mute: false, access: null, emergency: false, nosignal: true });
      // annunciators
      ann('a-ant', (!s.nosignal && v !== 'boot') || allOn, s.nosignal && !allOn && v !== 'boot');
      [1, 2, 3, 4].forEach(i => ann(`a-b${i}`, i <= s.bars || allOn));
      ann('a-tx', s.tx || allOn);
      ann('a-rx', !!s.rx || allOn);
      ann('a-mem', !!s.mem || v === 'memories' || allOn);
      ann('a-hf', s.handsfree || allOn);
      ann('a-spk', s.mute || allOn);
      ann('a-x', s.mute || allOn);
      ann('a-lock', (s.access === 'code' || s.access === 'job' || v === 'code') || allOn);
      ann('a-emg', s.emergency || allOn, s.emergency);
      ann('a-bo', true);
      const bat = Math.ceil(s.battery * 3 - 0.05);
      [1, 2, 3].forEach(i => ann(`a-c${i}`, i <= bat || allOn));
      ann('a-mhz', ['home', 'tune', 'memories', 'slots', 'emergency'].includes(v) || allOn);
      ann('a-code', v === 'code' || allOn);
      const hm = /^(\d{1,2}):(\d{2})/.exec(s.time || '');
      this.clk.set(allOn ? '8888' : hm ? hm[1].padStart(2, ' ') + hm[2] : '    ', { colonOn: allOn || (!!hm && Math.floor(Date.now() / 1000) % 2 === 0) });

      const slotDigit = n => String(clamp(n, 0, 9));
      const big5 = f => (f ? f.padStart(6, ' ') : '-----');   // '155.50' → 5 cells + point
      let big = '     ', blink = -1, ch = slotDigit(s.slot), m = s.mem ? pad2(s.mem) : '  ', mBlink = -1, chBlink = -1;

      if (allOn) {
        this.big.set('8.8.8.8.8.');
        this.ch.set('8');
        this.m.set('88');
        this.dot(''.padEnd(DOT_N, BLOCK));
        this.volShow(false, s, true);
        return;
      }

      if (v === 'home' || v === 'emergency') {
        big = big5(s.freq);
        if (v === 'emergency') this.dot(s.title, { inv: true, blink: true, center: true });
        else if (s.notice) this.dot(s.notice, { inv: true, center: true });
        else if (s.tx) this.dot(`${WORDS.tx} ${WORDS.live} ${mmss(now() - live.txSince)}`, { center: true });
        else if (s.rx) this.dot(`${s.rx.emergency ? WORDS.emerg + ' ' : ''}${s.rx.callsign ? s.rx.callsign + ' ' : ''}${s.rx.name || (s.rx.callsign ? '' : WORDS.unit)}`, {});
        else if (s.nosignal) this.dot(WORDS.nosignal, { blink: true, center: true });
        else if (!s.freq) this.dot(WORDS.nochannel, { center: true });
        else this.dot(s.label || `S${s.slot} ${WORDS.open}`, { center: true });
      } else if (v === 'tune') {
        const p = this.entryCells(s.entry);
        big = p.text;
        blink = p.blink;
        // the title only when it fits with the key help on the one line
        const both = one(`${s.title} ${s.hint}`), hint = one(s.hint);
        this.dot(s.notice || (both.length <= DOT_N || !hint ? both : hint.length <= DOT_N ? hint : both), s.notice ? { inv: true, center: true } : { center: true });
      } else if (v === 'code') {
        const n = s.code.length;
        big = ' ' + Array.from({ length: 4 }, (_, i) => (i < n ? '°' : '_')).join('');
        blink = n < 4 ? n + 1 : -1;
        this.dot(s.notice || `${s.title} ${s.target || ''}`.trim(), s.notice ? { inv: true, center: true } : {});
      } else if (v === 'memories') {
        const mm = s.memories;
        m = pad2(mm.index);
        mBlink = -1;
        if (s.entry) { const p = this.entryCells(s.entry); big = p.text; blink = p.blink; } else big = big5(mm.f);
        this.dot(s.notice || (s.entry ? `${WORDS.store} M${mm.index}` : mm.f ? (mm.label || WORDS.open) : (mm.label || WORDS.free)), s.notice ? { inv: true, center: true } : { center: true });
      } else if (v === 'slots') {
        const sel = clamp(s.sel || s.slot, 1, Math.max(1, s.slots.length));
        const row = s.slots[sel - 1] || {};
        ch = slotDigit(sel);
        chBlink = 0;
        if (s.entry) { const p = this.entryCells(s.entry); big = p.text; blink = p.blink; } else big = big5(row.f);
        this.dot(s.notice || `S${sel} ${row.f ? (row.label || WORDS.open) : WORDS.idle}${row.tx ? ' ' + WORDS.tx : ''}`, s.notice ? { inv: true, center: true } : {});
      } else if (v === 'menu') {
        const it = s.menu.items[s.menu.index] || { label: '', value: null };
        m = pad2(s.menu.index + 1);
        const val = up(it.value);
        big = val === 'ON' ? '  On ' : val === 'OFF' ? ' OFF ' : '     ';
        if (s.notice) this.dot(s.notice, { inv: true, center: true });
        else {
          const right = it.value !== null && val !== 'ON' && val !== 'OFF' ? val : '';
          const room = DOT_N - 2 - right.length;
          this.dot(`>${up(it.label).slice(0, room).padEnd(room, ' ')} ${right}`.slice(0, DOT_N + 12), {});
        }
      } else if (v === 'boot') {
        // after the lamp test: 'tESt' on the segments while the dot line fills behind the model code
        big = ' tESt';
        const p = clamp((now() - live.bootAt - 650) / 800, 0, 1);
        const n = Math.round(p * 8);
        this.dot(`${s.model} ${BLOCK.repeat(n)}`, {});
      } else {
        this.dot('');
      }
      this.big.set(big, { blink });
      this.ch.set(v === 'off' || v === 'boot' ? ' ' : ch, { blink: chBlink });
      this.m.set(v === 'off' || v === 'boot' ? '  ' : m, { blink: mBlink });
      this.volShow(s.showVolume && v !== 'off' && v !== 'boot', s);
      // 'block' characters in the dot line are drawn as filled cells
    },
    volShow(on, s, lamp = false) {
      const r = this.r;
      tog(r, 'vol', on);
      const lit = lamp ? 10 : on ? Math.round(s.volume / 10) : 0;
      $$('.fx-vol .vb i', r).forEach((b, i) => b.classList.toggle('on', i < lit));
      if (!on) return;
      this.dot(`${s.mute ? WORDS.mute : WORDS.vol} ${String(s.volume).padStart(3, ' ')}`, { center: true });
    },
    // typed digits on the 5 big cells: integer part right-aligned into 3, decimals after the point
    entryCells(e) {
      e = str(e);
      const dot = e.indexOf('.');
      const ip = dot === -1 ? e : e.slice(0, dot), dp = dot === -1 ? '' : e.slice(dot + 1);
      const ints = ip.slice(-3).padStart(3, ' ');
      const decs = (dp + '__').slice(0, 2);
      const next = dot === -1 ? (ip.length < 3 ? 2 : 3) : Math.min(4, 3 + dp.length);
      return { text: `${ints}.${decs}`, blink: dot === -1 && ip.length < 3 ? -1 : next };
    },
  };

  /* ═══════════════════════════ MX-905 · tactical ═══════════════════════════ */
  const ARC_N = 18;
  function arcSegs(cx, cy, r, n, from, sweep, gap) {
    const seg = sweep / n;
    const p = a => `${(cx + r * Math.cos(a * Math.PI / 180)).toFixed(2)} ${(cy + r * Math.sin(a * Math.PI / 180)).toFixed(2)}`;
    return Array.from({ length: n }, (_, i) => {
      const a0 = from + i * seg + gap / 2, a1 = from + (i + 1) * seg - gap / 2;
      return `<path class="as" d="M${p(a0)}A${r} ${r} 0 0 1 ${p(a1)}"/>`;
    }).join('');
  }
  const MX905 = {
    build(root) {
      const corner = c => `<i class="mx-c ${c}"></i>`;
      root.innerHTML = `
<div class="sk mx">
  <div class="mx-grid"></div>
  <div class="mx-frame">${corner('tl')}${corner('tr')}${corner('bl')}${corner('br')}</div>
  <div class="mx-head">
    <b class="mx-net"></b><b class="mx-sec"></b><b class="mx-mem"></b>
    <span class="mx-busy"><i></i><i></i><i></i></span>
    <span class="sp"></span>
    <b class="fl f-hf">${WORDS.hf}</b><b class="fl f-mu">MUT</b><b class="fl f-ea">EAR</b>
    <span class="mx-bat"><i></i><i></i><i></i><i></i></span>
    <b class="mx-clock"></b>
  </div>
  <section class="view v-home">
    <div class="mx-gauge">
      <svg viewBox="0 0 160 160"><g class="trk">${arcSegs(80, 80, 62, ARC_N, 135, 270, 4)}</g><g class="lit">${arcSegs(80, 80, 62, ARC_N, 135, 270, 4)}</g>
        <path class="tk" d="M80 6v8M6 80h8M146 80h8"/></svg>
      <div class="gv"><b></b><em>${WORDS.sig}</em></div>
      <div class="gj"></div>
    </div>
    <div class="mx-chan">
      <em class="cap">FREQ · ${WORDS.mhz.toUpperCase()}</em>
      <div class="mx-freq"></div>
      <div class="mx-lab"></div>
      <div class="mx-acc"></div>
    </div>
    <div class="mx-nets"></div>
    <div class="mx-line"></div>
  </section>
  <section class="view v-tune">
    <div class="mx-ttl"><b class="ttl"></b><span class="sp"></span><b class="tg"></b></div>
    <div class="mx-entry"><i class="br l"></i><span class="ty"></span><i class="cur"></i><span class="gh"></span><i class="br r"></i></div>
    <div class="mx-scale"><span class="sc"></span><i class="nd"></i></div>
    <div class="mx-hint"></div>
  </section>
  <section class="view v-code">
    <div class="mx-ttl"><b class="ttl"></b><span class="sp"></span><b class="tg"></b></div>
    <div class="mx-cells">${'<i><b></b></i>'.repeat(4)}</div>
    <div class="mx-sub"></div>
    <div class="mx-hint"></div>
  </section>
  <section class="view v-memories">
    <div class="mx-ttl"><b class="ttl"></b><span class="sp"></span><b class="tg"></b></div>
    <div class="mx-mem2"><b class="mi"></b><div class="md"><b class="mf"></b><span class="ml"></span><span class="ms"></span></div></div>
    <div class="mx-rail"></div>
    <div class="mx-hint"></div>
  </section>
  <section class="view v-slots">
    <div class="mx-ttl"><b class="ttl"></b><span class="sp"></span><b class="tg"></b></div>
    <div class="mx-list js-slots"></div>
    <div class="mx-hint"></div>
  </section>
  <section class="view v-menu">
    <div class="mx-ttl"><b class="ttl"></b><span class="sp"></span><b class="tg"></b></div>
    <div class="mx-list js-menu"></div>
    <div class="mx-hint"></div>
  </section>
  <section class="view v-emergency">
    <div class="mx-emg"><b class="ttl"></b><b class="ef"></b><span class="el"></span><span class="ei"></span></div>
  </section>
  <section class="view v-boot">
    <div class="mx-boot"><b class="bm"></b><span class="bt"></span>
      <span class="bl">${WORDS.checks.map((c, i) => `<em style="--d:${i}"><span>${esc(c)}</span><i></i><b>${WORDS.ok}</b></em>`).join('')}</span>
      <span class="bp">${'<i></i>'.repeat(16)}</span></div>
  </section>
  <div class="mx-vol"><b>${WORDS.vol}</b><span class="vb"></span><b class="vn"></b></div>
  <div class="mx-note"><b></b></div>
</div>`;
      const r = root.firstElementChild;
      this.r = r;
      this.freq = Roller($('.mx-freq', r), 'big');
      const ticks = Array.from({ length: 21 }, (_, i) => `<i class="${i % 5 === 0 ? 'mj' : ''}" style="left:${i * 5}%"></i>`).join('');
      $$('.mx-scale .sc', r).forEach(h => { h.innerHTML = ticks; });
    },
    draw(s) {
      const r = this.r, v = s.view;
      setView(r, v);
      set('.mx-net', r, `${WORDS.net} ${s.slot}`);
      const sec = set('.mx-sec', r, s.freq ? (s.access === 'code' || s.access === 'job' ? WORDS.sec : WORDS.clr) : '');
      tog(sec, 'on', s.access === 'code' || s.access === 'job');
      tog(sec, 'hide', !s.freq);
      const mm = set('.mx-mem', r, s.mem ? `M${pad2(s.mem)}` : '');
      tog(mm, 'hide', !s.mem);
      tog($('.mx-busy', r), 'on', s.busy);
      tog($('.f-hf', r), 'on', s.handsfree);
      tog($('.f-mu', r), 'on', s.mute);
      tog($('.f-ea', r), 'on', s.earpiece);
      const bat = Math.ceil(s.battery * 4 - 0.05);
      $$('.mx-bat i', r).forEach((b, i) => b.classList.toggle('on', i < bat));
      set('.mx-clock', r, s.time || '--:--');

      if (v === 'home') this.home(s);
      else if (v === 'tune') {
        const sc = $('.v-tune', r), p = entryParts(s.entry);
        set('.ttl', sc, s.title);
        set('.tg', sc, `${WORDS.net} ${s.slot}`);
        set('.ty', sc, p.typed);
        set('.gh', sc, p.ghost);
        const sl = $('.mx-scale', sc);
        tog(sl, 'none', !s.entry);
        if (s.entry) $('.nd', sl).style.left = `${(bandPos(s.entry) * 100).toFixed(2)}%`;
        html($('.mx-hint', sc), keyHint(s.hint));
      } else if (v === 'code') {
        const sc = $('.v-code', r);
        set('.ttl', sc, s.title);
        set('.tg', sc, s.target || s.freq || '');
        $$('.mx-cells i', sc).forEach((c, i) => { c.classList.toggle('on', i < s.code.length); c.classList.toggle('cur', i === s.code.length); });
        set('.mx-sub', sc, s.label && (!s.target || s.target === s.freq) ? up(s.label) : `${WORDS.net} ${s.slot}`);
        html($('.mx-hint', sc), keyHint(s.hint));
      } else if (v === 'memories') {
        const sc = $('.v-memories', r), m = s.memories;
        set('.ttl', sc, s.title);
        set('.tg', sc, `${pad2(m.index)}${WORDS.of}${pad2(m.count)}`);
        set('.mi', sc, `M${pad2(m.index)}`);
        const mf = set('.mf', sc, m.f || WORDS.free);
        tog(mf, 'free', !m.f);
        set('.ml', sc, up(m.f ? (m.label || WORDS.open) : ''));
        html($('.ms', sc), s.entry ? `${IC.tri}${esc(WORDS.store)} <b>${esc(s.entry)}</b><i class="cur"></i>` : '');
        html($('.mx-rail', sc), Array.from({ length: Math.min(m.count, 12) }, (_, i) => `<i class="${i + 1 === m.index ? 'on' : ''}"></i>`).join(''));
        html($('.mx-hint', sc), keyHint(s.hint));
      } else if (v === 'slots') {
        const sc = $('.v-slots', r);
        const sel = clamp(s.sel || s.slot, 1, Math.max(1, s.slots.length));
        set('.ttl', sc, s.title);
        set('.tg', sc, `${WORDS.net} ${sel}${WORDS.of}${s.slots.length}`);
        const [a, b] = windowOf(s.slots.length, sel - 1, 5);
        html($('.js-slots', sc), s.slots.slice(a, b).map(row => {
          const on = row.n === sel;
          const f = on && s.entry ? `${esc(s.entry)}<i class="cur"></i>` : esc(row.f || '---.--');
          return `<div class="li${on ? ' on' : ''}${row.f ? '' : ' empty'}"><b class="n">N${row.n}</b><b class="f">${f}</b><span class="l">${esc(up(row.label || (row.f ? WORDS.open : WORDS.idle)))}</span>` +
            `${row.rx ? `<b class="t">${WORDS.rx}</b>` : ''}${row.tx ? `<b class="t tx">${WORDS.tx}</b>` : ''}</div>`;
        }).join(''));
        html($('.mx-hint', sc), keyHint(s.hint));
      } else if (v === 'menu') {
        const sc = $('.v-menu', r), items = s.menu.items;
        set('.ttl', sc, s.title);
        set('.tg', sc, items.length ? `${pad2(s.menu.index + 1)}${WORDS.of}${pad2(items.length)}` : '');
        const [a, b] = windowOf(items.length, s.menu.index, 5);
        html($('.js-menu', sc), items.slice(a, b).map((it, k) => {
          const on = a + k === s.menu.index;
          return `<div class="li${on ? ' on' : ''}"><b class="n">${on ? IC.tri : ''}</b><span class="l">${esc(up(it.label))}</span>${it.value === null ? '' : `<b class="v">${esc(up(it.value))}</b>`}</div>`;
        }).join('') + (items.length > 5 ? `<i class="sbar" style="--a:${a / items.length};--b:${(b - a) / items.length}"></i>` : ''));
        html($('.mx-hint', sc), keyHint(s.hint));
      } else if (v === 'emergency') {
        const sc = $('.v-emergency', r);
        set('.ttl', sc, s.title);
        set('.ef', sc, `${s.freq || '---.--'} ${WORDS.mhz.toUpperCase()}`);
        set('.el', sc, up(s.label));
        html($('.ei', sc), keyHint(s.hint));
      } else if (v === 'boot') {
        const sc = $('.v-boot', r);
        set('.bm', sc, s.model);
        set('.bt', sc, s.title || WORDS.selftest);
      }
      const vol = $('.mx-vol', r);
      tog(vol, 'on', s.showVolume && v !== 'off' && v !== 'boot');
      tog(vol, 'muted', s.mute);
      set('b', vol, s.mute ? WORDS.mute : WORDS.vol);
      html($('.vb', vol), segBar(Math.round(s.volume / 5), 20));
      set('.vn', vol, String(s.volume).padStart(3, '0'));
      const note = $('.mx-note', r);
      tog(note, 'on', !!s.notice && v !== 'off' && v !== 'boot');
      if (s.notice) set('b', note, up(s.notice));
    },
    home(s) {
      const sc = $('.v-home', this.r);
      // signal arc: the talker's quality while receiving, else the local estimate (bars)
      const level = s.nosignal ? 0 : s.rx ? s.rx.q : s.bars / 4;
      const lit = Math.round(level * ARC_N);
      $$('.lit .as', sc).forEach((p, i) => p.classList.toggle('on', i < lit));
      tog($('.mx-gauge', sc), 'bad', s.nosignal || level < 0.3);
      set('.gv b', sc, s.nosignal ? '--' : String(Math.round(level * 100)).padStart(2, '0'));
      const gj = set('.gj', sc, s.nosignal ? WORDS.nosignal : s.jam > 0.04 ? `${WORDS.jam} ${String(Math.round(s.jam * 100)).padStart(2, '0')}` : WORDS.link);
      tog(gj, 'warn', s.nosignal || s.jam > 0.04);
      this.freq.set(s.freq || '---.--');
      tog($('.mx-freq', sc), 'none', !s.freq);
      const lab = set('.mx-lab', sc, s.freq ? up(s.label || `${WORDS.net} ${s.slot}`) : WORDS.keyin);
      tog(lab, 'dim', !s.freq || !s.label);
      html($('.mx-acc', sc), s.freq ? (s.access === 'code' ? `${IC.lock}<b>${WORDS.sec}</b> ${WORDS.code}` : s.access === 'job' ? `${IC.badge}<b>${WORDS.sec}</b> ${WORDS.job}` : `<b>${WORDS.clr}</b> ${WORDS.open}`) : '');
      html($('.mx-nets', sc), s.slots.map(row =>
        `<div class="nc${row.tx ? ' tx' : ''}${row.rx ? ' rx' : ''}${row.f ? '' : ' empty'}"><span class="nh"><b>N${row.n}</b>${row.tx ? `<em>${WORDS.tx}</em>` : row.rx ? `<em>${WORDS.rx}</em>` : ''}</span><b class="nf">${esc(row.f || '---.--')}</b></div>`).join(''));
      $('.mx-nets', sc).style.setProperty('--n', Math.max(1, s.slots.length));
      const line = $('.mx-line', sc);
      if (s.tx) {
        line.dataset.mode = 'tx';
        html(line, `<b class="tag">${IC.tri}${WORDS.tx}</b><span>${WORDS.keyed}</span><span class="sp"></span><b class="js-txt">${mmss(now() - live.txSince)}</b>`);
      } else if (s.rx) {
        line.dataset.mode = s.rx.emergency ? 'emg' : 'rx';
        html(line, `<b class="tag">${IC.tril}${s.rx.emergency ? WORDS.emerg : WORDS.rx}</b>${s.rx.callsign ? `<b class="cs">${esc(up(s.rx.callsign))}</b>` : ''}<span class="nm">${esc(up(s.rx.name || (s.rx.callsign ? '' : WORDS.unit)))}</span><span class="sp"></span><b>Q${String(Math.round(s.rx.q * 100)).padStart(2, '0')}</b>`);
      } else {
        line.dataset.mode = 'idle';
        html(line, `<b class="tag dim">${WORDS.stby}</b><span>${s.mute ? WORDS.mute : `${WORDS.vol} ${String(s.volume).padStart(3, '0')}`}</span><span class="sp"></span><span>${WORDS.net} ${s.slot}${WORDS.of}${Math.max(1, s.slots.length)}</span>`);
      }
    },
  };

  /* ═══════════════════════════ screen, layers, messages ═══════════════════════════ */
  const SKINS = { px740: PX740, fx280: FX280, mx905: MX905 };
  const sk = SKINS[SKIN];
  const scr = document.getElementById('scr');
  document.documentElement.dataset.skin = SKIN;
  document.documentElement.style.setProperty('--W', `${W}px`);
  document.documentElement.style.setProperty('--H', `${H}px`);
  scr.style.width = `${BW}px`;
  scr.style.height = `${BH}px`;
  scr.style.transform = W === BW && H === BH ? '' : `scale(${(W / BW).toFixed(5)},${(H / BH).toFixed(5)})`;
  scr.innerHTML = '<div class="skin"></div><div class="lay"><i class="l-jam"></i><i class="l-flash"></i><i class="l-scan"></i><i class="l-vig"></i><i class="l-glare"></i></div>';
  sk.build($('.skin', scr));

  let offTimer = 0;
  function paint(s) {
    scr.dataset.view = s.view;
    tog(scr, 'is-tx', s.tx && s.view !== 'off');
    tog(scr, 'is-rx', !!s.rx && s.view !== 'off');
    tog(scr, 'is-emg', s.emergency && s.view !== 'off');
    tog(scr, 'is-jam', s.jam > 0.12 && s.view !== 'off' && s.view !== 'boot');
    scr.style.setProperty('--jam', s.jam.toFixed(2));
    try { sk.draw(s); } catch (e) { console.error('[radio screen]', e); }
  }
  function draw(raw) {
    const s = norm(raw);
    const prev = live.st;
    live.prev = prev;
    live.st = s;
    if (s.tx && !(prev && prev.tx)) live.txSince = now();
    if (s.view === 'off') {
      // switched off: the last picture collapses to a line, then the glass goes black
      if (prev && prev.view !== 'off' && !scr.classList.contains('poweroff')) {
        scr.classList.add('poweroff');
        clearTimeout(offTimer);
        offTimer = setTimeout(() => { scr.classList.remove('poweroff'); if (live.st && live.st.view === 'off') paint(live.st); }, 420);
      }
      if (scr.classList.contains('poweroff')) return;
    } else if (scr.classList.contains('poweroff')) {
      clearTimeout(offTimer);
      scr.classList.remove('poweroff');
    }
    if (s.view === 'boot' && (!prev || prev.view !== 'boot')) {
      live.bootAt = now();
      // restart the boot animations
      $$('.v-boot', scr).forEach(v => v.classList.remove('up'));
      void scr.offsetWidth;
    }
    paint(s);
  }

  // live parts that move without a new state: TX timer, the fx280 dot line, the clock colon
  setInterval(() => {
    const s = live.st;
    if (!s || s.view === 'off') return;
    if (s.tx) $$('.js-txt', scr).forEach(e => { const t = mmss(now() - live.txSince); if (e.textContent !== t) e.textContent = t; });
    if (SKIN === 'fx280') {
      if (s.view === 'boot' || (s.tx && s.view === 'home') || s.view === 'emergency' || s.time) sk.draw(s);
      sk.tick(now());
    }
  }, 250);

  function onMessage(e) {
    let m = e && e.data;
    if (typeof m === 'string') { try { m = JSON.parse(m); } catch { return; } }
    if (!m || typeof m !== 'object') return;
    if (m.type === 'state' && m.state && typeof m.state === 'object') draw(m.state);
    else if (m.type === 'ping' && live.st) draw(live.st);
  }
  window.addEventListener('message', onMessage);
  draw({ view: 'off', model: MODEL[SKIN] });

  /* ═══════════════════════════ browser demo ═══════════════════════════ */
  if (!DEMO) return;
  const DEMO_VIEWS = ['boot', 'home', 'rx', 'tx', 'tune', 'code', 'memories', 'slots', 'menu', 'emergency', 'volume', 'notice', 'nosignal', 'jam', 'off'];

  // bigger browser window: show the screen centred and scaled up
  if (innerWidth > W + 40 || innerHeight > H + 40) {
    document.body.classList.add('stage');
    document.documentElement.style.setProperty('--W', '100vw');
    document.documentElement.style.setProperty('--H', '100vh');
    const fit = () => { const k = Math.min((innerWidth - 80) / W, (innerHeight - 80) / H, 2.4); document.documentElement.style.setProperty('--fit', k.toFixed(3)); };
    fit();
    addEventListener('resize', fit);
  }

  const N = SKIN === 'px740' ? 3 : SKIN === 'fx280' ? 4 : 5;
  const CH = [
    { f: '155.50', label: 'LSPD Dispatch', access: 'code' },
    { f: '160.25', label: 'EMS Main', access: 'open' },
    { f: '412.75', label: 'Tac 2', access: 'job' },
    { f: '48.20', label: null, access: 'open' },
    { f: null },
  ];
  const clock = () => { const d = new Date(); return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`; };
  function base() {
    const slots = Array.from({ length: N }, (_, i) => {
      const c = N === 3 && i === 2 ? { f: null } : CH[i];
      return { n: i + 1, f: c.f, tx: i === 0, rx: false, label: c.label || undefined, access: c.f ? c.access : undefined };
    });
    return {
      view: 'home', skin: SKIN, model: MODEL[SKIN], freq: '155.50', label: 'LSPD Dispatch', access: 'code', slot: 1, slots, sel: 1,
      tx: false, bars: 3, nosignal: false, jam: 0.04, volume: 70, showVolume: false, mute: false, handsfree: false, clicks: true,
      earpiece: false, battery: 0.82, time: clock(), entry: '', code: '', memories: { index: 1, count: 6, f: '155.50', label: 'LSPD Dispatch' },
      mem: 1, menu: { items: [], index: 0 }, notice: null, busy: false, emergency: false,
    };
  }
  const MENU = [
    { id: 'memories', label: 'MEMORIES' }, { id: 'slots', label: 'SLOTS' }, { id: 'mute', label: 'MUTE', value: 'OFF' },
    { id: 'handsfree', label: 'HANDS-FREE', value: 'ON' }, { id: 'clicks', label: 'MIC CLICKS', value: 'ON' },
    { id: 'roster', label: 'ROSTER', value: 'OFF' }, { id: 'callsign', label: 'CALLSIGN', value: '2A14' }, { id: 'close', label: 'CLOSE' },
  ];
  const RX = { name: 'Maya Reyes', callsign: '2A14', q: 0.83, slot: 1 };
  function sample(view, step = 0) {
    const s = base();
    switch (view) {
      case 'boot': return Object.assign(s, { view: 'boot', title: 'SELF TEST' });
      case 'rx': s.rx = Object.assign({}, RX, { q: 0.83 - (step % 3) * 0.06 }); s.slots[0].rx = true; s.bars = 3; return s;
      case 'tx': s.tx = true; s.bars = 4; return s;
      case 'tune': return Object.assign(s, { view: 'tune', entry: ['1', '16', '160', '160.2', '160.25'][Math.min(step, 4)], title: 'TUNE', hint: '* point  ·  OK join' });
      case 'code': return Object.assign(s, { view: 'code', target: '412.75', code: '**', title: 'ACCESS CODE', hint: '4 digits  ·  OK send' });
      case 'memories': return Object.assign(s, { view: 'memories', memories: { index: 2, count: 6, f: '160.25', label: 'EMS Main' }, title: 'MEMORY', hint: 'keys: store · OK: tune' });
      case 'slots': s.slots[1].rx = true; return Object.assign(s, { view: 'slots', sel: 2, title: 'SLOTS', hint: 'OK talk here  ·  # leave' });
      case 'menu': return Object.assign(s, { view: 'menu', menu: { items: MENU, index: 3 }, title: 'MENU', hint: 'OK select  ·  BACK exit' });
      case 'emergency': return Object.assign(s, { view: 'emergency', emergency: true, tx: true, title: 'EMERGENCY', hint: 'ALERT SENT  ·  MIC OPEN' });
      case 'volume': return Object.assign(s, { showVolume: true, volume: 65 });
      case 'notice': return Object.assign(s, { notice: 'STORED' });
      case 'nosignal': return Object.assign(s, { nosignal: true, bars: 0, jam: 0.96 });
      case 'jam': return Object.assign(s, { jam: 0.58, bars: 1 });
      case 'off': return { view: 'off', model: MODEL[SKIN] };
      default: return s;
    }
  }
  const post = st => window.postMessage({ type: 'state', state: st }, '*');
  if (DEMO_VIEWS.includes(DEMO) || DEMO === 'home') {
    // one view frozen (the boot view restarts every few seconds so its animation can be seen)
    post(sample(DEMO, 4));
    if (DEMO === 'rx') setInterval(() => post(sample('rx', Math.floor(now() / 700))), 700);
    if (DEMO === 'boot') setInterval(() => { post(sample('off')); setTimeout(() => post(sample('boot')), 500); }, 3200);
    return;
  }
  // every view in turn
  const SEQ = [['off', 900], ['boot', 1600], ['home', 2600], ['rx', 2800], ['tx', 2600], ['tune', 2800], ['code', 2200], ['memories', 2400],
    ['slots', 2400], ['menu', 2600], ['volume', 1800], ['notice', 1600], ['jam', 2200], ['nosignal', 2200], ['emergency', 2800]];
  let k = 0, at = now();
  post(sample(SEQ[0][0]));
  setInterval(() => {
    const t = now();
    const [view, dur] = SEQ[k];
    const step = Math.floor((t - at) / 450);
    if (t - at >= dur) { k = (k + 1) % SEQ.length; at = t; post(sample(SEQ[k][0], 0)); return; }
    if (view === 'tune' || view === 'rx') post(sample(view, step));
  }, 150);
})();
